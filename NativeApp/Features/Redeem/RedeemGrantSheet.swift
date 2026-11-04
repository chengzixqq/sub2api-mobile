import SwiftUI
import Sub2Core

/// `.redeemGrant(userID:pendingID:)` (60 §19) at the large detent. With a pending id: that record's 结果待核对 page. Without one:
/// the user is read by id (19.7 takes the object, a route only an id), then the wizard, or the block page when a compensation of
/// this user awaits its check and nothing asked first (X38's fallback; the user detail asks before opening). A grant closes the
/// sheet with its receipt, an uncertain answer turns it into the pending page, 重新发放 there into the wizard again. A new
/// session closes it.
struct RedeemGrantSheet: View {
    let userID: Int
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage
    @State private var attempt = 0

    enum Stage {
        case loading
        case regranting(GrantRegrant)
        case failed(String)
        case blocked(GrantBlockPrompt)
        case paused(String)
        case wizard(RedeemGrantModel)
        case pending(UUID)
    }

    init(userID: Int, pendingID: UUID?) {
        self.userID = userID
        _stage = State(initialValue: pendingID.map(Stage.pending) ?? .loading)
    }

    var body: some View {
        NavigationStack { content }
            .presentationDetents([.large])
            .task(id: attempt) { await prepare() }
            .onChange(of: model.sessionGeneration) { _, _ in dismiss() }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .loading, .regranting:
            ProgressView("正在读取用户…").toolbar { closeItem }
        case .failed(let message):
            FailureView(message: message) { retry() }.toolbar { closeItem }
        case .blocked(let prompt):
            RedeemGrantBlockPage(prompt: prompt) { stage = .pending(prompt.recordID) }
        case .paused(let message):
            ContentUnavailableView("补偿发放已暂停", systemImage: "exclamationmark.triangle", description: Text(message))
                .accessibilityIdentifier("grant.paused")
                .toolbar { closeItem }
        case .wizard(let state):
            RedeemGrantWizard(state: state) { leave($0) }
        case .pending(let id):
            RedeemGrantPendingView(recordID: id) { regrant in
                stage = .regranting(regrant)
                attempt += 1
            }
        }
    }

    private var closeItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
    }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    private func retry() {
        stage = .loading
        attempt += 1
    }
    /// Reads the user, then opens the wizard: fresh after the gate, or with a settled record's content (重新发放).
    private func prepare() async {
        let regrant: GrantRegrant?
        switch stage {
        case .loading: regrant = nil
        case .regranting(let request): regrant = request
        default: return
        }
        guard let session, session.generation == model.sessionGeneration else { return }
        do {
            let user = try await model.grantUser(id: regrant?.grant.userID ?? userID)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            if let regrant { stage = try wizard(user: user, regranting: regrant) } else { stage = try opening(user) }
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            stage = .failed(error.localizedDescription)
        }
    }
    private func opening(_ user: AdminUser) throws -> Stage {
        switch GrantEntryDecision.decide(gate: model.moneyWriteGate(.compensation(userID: user.id)), compensations: model.pendingCompensations,
                                         groupNames: model.grantGroupNames, now: Date(), timeZone: zone.timeZone) {
        case .open: return .wizard(RedeemGrantModel(user: user, draftState: try GrantDraftState.opening()))
        case .blocked(let prompt): return .blocked(prompt)
        case .paused(let message): return .paused(message)
        }
    }
    private func wizard(user: AdminUser, regranting request: GrantRegrant) throws -> Stage {
        // The old code may already exist with the old content: a key refusal alone keeps it, anything else takes a new one.
        let state = request.keepsCode ? GrantDraftState(code: request.grant.code, hasSent: true) : try GrantDraftState.opening()
        return .wizard(RedeemGrantModel(user: user, regranting: request.grant, draftState: state, notice: request.notice, atValueStep: request.atValueStep))
    }
    private func leave(_ exit: RedeemGrantModel.Exit) {
        switch exit {
        case .granted(let code, let replayed, let grant):
            model.showGrantReceipt(code, replayed: replayed, grant: grant, router: router)
            dismiss()
        case .pending(let id):
            stage = .pending(id)
        case .closed(let message):
            model.receipts.show(Receipt(text: message, systemImage: "exclamationmark.triangle", tone: .caution))
            dismiss()
        }
    }
}

/// The three steps in the sheet's NavigationStack: step bar, subject bar, the step, and the confirmation (60 §19.1, §19.3).
private struct RedeemGrantWizard: View {
    let state: RedeemGrantModel
    let leave: (RedeemGrantModel.Exit) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = model.grantSubscriptionGroups, step = state.step
        VStack(spacing: 0) {
            GrantStepBar(step: step)
            GrantSubjectBar(user: state.user, line: subjectLine(groups))
            switch step {
            case .type:
                GrantTypeStep(availability: GrantAvailability(user: state.user, hasSubscriptionGroups: !groups.isEmpty)) { type in
                    state.choose(type, availability: GrantAvailability(user: state.user, hasSubscriptionGroups: !groups.isEmpty), app: model)
                }
            case .value:
                GrantValueStep(state: state, groups: groups, now: now, timeZone: zone)
            case .note:
                GrantNoteStep(state: state, groups: groups, now: now, timeZone: zone) {
                    state.submit(app: model, groups: groups, now: now, timeZone: zone)
                }
            }
        }
        .background(Palette.sheetBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grant.sheet")
        .navigationTitle(step.title(for: state.type))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { leadingButton(step) } }
        .overlay { if state.isVerifying { GrantFaceIDOverlay() } }
        .alert(state.confirmation?.content.title ?? "", isPresented: confirmationShown, presenting: state.confirmation) { shown in
            Button(shown.content.button, role: shown.content.isDestructive ? .destructive : nil) { state.confirm(shown, app: model, groups: groups) }
            Button("取消", role: .cancel) {}
        } message: { shown in
            Text(shown.content.message)
        }
        .interactiveDismissDisabled(state.isWorking)
        .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
        .onChange(of: state.exit) { _, exit in if let exit { leave(exit) } }
    }

    private var now: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: TimeZone { (session?.site.serverTimeZone ?? .device).timeZone }

    /// Step 1 names the email; later steps what the chosen type changes.
    private func subjectLine(_ groups: [AdminGroup]) -> String {
        let type = state.step == .type ? nil : state.type
        let group = type == .subscription ? state.selectedGroup(in: groups)?.name : nil
        return RedeemGrantCopy.subjectLine(user: state.user, type: type, groupName: group, plan: state.plan(groups: groups, now: now, timeZone: zone),
                                           now: now, timeZone: zone)
    }
    @ViewBuilder private func leadingButton(_ step: GrantStep) -> some View {
        if step == .type {
            Button(step.leadingTitle) { dismiss() }.accessibilityIdentifier("sheet.close")
        } else {
            Button(step.leadingTitle) { state.goBack() }.disabled(state.isWorking).accessibilityIdentifier("grant.back")
        }
    }
    private var confirmationShown: Binding<Bool> {
        let id = state.confirmation?.id
        return Binding(get: { id != nil && state.confirmation?.id == id }, set: { if !$0, let id { state.dismissConfirmation(id) } })
    }
}

/// X38's fallback (60 §19.1): the sheet opened without asking while a compensation of this user awaits its check.
private struct RedeemGrantBlockPage: View {
    let prompt: GrantBlockPrompt
    let check: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MoneyPendingHeader(systemImage: "exclamationmark.triangle", title: GrantBlockPrompt.title, message: prompt.message, tone: .caution,
                                   identifier: "grant.blocked.header")
                MoneyPendingActions(actions: [
                    MoneyPendingAction(id: "grant.blocked.check", title: GrantBlockPrompt.checkTitle, isPrimary: true, isEnabled: true),
                    MoneyPendingAction(id: "grant.blocked.cancel", title: GrantBlockPrompt.cancelTitle, isPrimary: false, isEnabled: true),
                ]) { id in if id == "grant.blocked.check" { check() } else { dismiss() } }
            }
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("grant.blocked")
        }
        .background(Palette.sheetBackground)
        .navigationTitle(GrantStep.type.title(for: nil))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") } }
    }
}
