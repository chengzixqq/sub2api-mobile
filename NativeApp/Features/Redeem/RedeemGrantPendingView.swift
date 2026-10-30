import SwiftUI
import Sub2Core

/// What 重新发放 opens: the record's content again in the wizard, under a new code (or the same one when only the key was
/// refused), at step 3 (step 2 for a group the server refused).
struct GrantRegrant: Equatable {
    let grant: PendingCompensation
    let keepsCode: Bool
    let atValueStep: Bool
    let notice: String
}

/// 60 §19.3 结果待核对 / 没找到 / 未兑换 of one compensation and what a check or a retry found, drawn with S6-06's parts. Settings,
/// the overview, the user detail's banner and an uncertain grant open it for the same record, with the current identity, also
/// for an older login at this address (X34); nothing is read until a button is tapped (19.6). While a request runs both buttons
/// wait and the sheet stays (19.5).
struct RedeemGrantPendingView: View {
    let recordID: UUID
    let onRegrant: @MainActor (GrantRegrant) -> Void
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var page: RedeemGrantPendingModel?
    @State private var confirmsAbandon = false
    /// Moves when a retry cooldown ends, so the grey button wakes up.
    @State private var tick = Date()

    private typealias Copy = CompensationPendingPresentation
    /// Each button's identifier is this and its kind.
    private static let prefix = "grant.pending."

    var body: some View {
        ScrollView {
            if let page { content(page).padding(16) }
        }
        .background(Palette.sheetBackground)
        .navigationTitle(Copy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }.disabled(page?.busy != nil).accessibilityIdentifier("sheet.close")
            }
        }
        .interactiveDismissDisabled(page?.busy != nil)
        .alert(Copy.abandonPromptTitle, isPresented: $confirmsAbandon) {
            Button(Copy.abandonTitle, role: .destructive) { abandon() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(Copy.abandonPromptMessage)
        }
        .task { await prepare() }
        .task(id: model.retryHeldUntil(recordID)) { await wakeAfterCooldown() }
        .onChange(of: page?.exit) { _, exit in if let exit { leave(exit) } }
    }

    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    private func content(_ page: RedeemGrantPendingModel) -> some View {
        let state = page.state(recordExists: model.pendingCompensations.contains { $0.id == recordID })
        let header = Copy.header(for: state, userName: page.snapshot?.userDisplayName ?? "这个用户")
        let retry = page.snapshot.map { model.compensationRetryContext(for: $0, actorLabel: page.actorLabel) } ?? .refusing
        let clock = max(tick, Date()), notes = Copy.notes(for: state, retry: retry, now: clock)
        return VStack(spacing: 16) {
            MoneyPendingHeader(systemImage: header.systemImage, title: header.title, message: header.message, tone: header.tone,
                               identifier: "grant.pending.header")
            if let grant = page.snapshot { MoneyPendingReceipt(lines: receipt(grant)) }
            if let notice = page.notice { MoneyPendingNotice(text: notice.text, tone: notice.tone, identifier: "grant.pending.notice") }
            MoneyPendingActions(actions: Copy.actions(for: state, retry: retry, busy: page.busy, now: clock).map {
                MoneyPendingAction(id: Self.prefix + $0.kind.rawValue, title: $0.title, isPrimary: $0.isPrimary, isEnabled: $0.isEnabled)
            }) { perform($0, page: page) }
            if !notes.isEmpty { MoneyPendingFootnote(text: notes.joined(separator: "\n"), identifier: "grant.pending.notes") }
            if let footnote = Copy.footnote(for: state) { MoneyPendingFootnote(text: footnote, identifier: "grant.pending.footnote") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grant.pending")
    }

    private func receipt(_ grant: PendingCompensation) -> [MoneyReceiptLine] {
        let origin = MoneyRecordOrigin.Kind(recordServerID: grant.serverID, currentServerID: model.activeProfile?.id, sameAddress: model.sameAddressServerIDs())
        let site = model.profileForRecord(serverID: grant.serverID)?.name ?? model.activeProfile?.name ?? "原站点"
        return Copy.receipt(grant, siteName: site, groupName: grant.groupID.flatMap { model.groupDirectory?.name(for: $0) }, origin: origin,
                            timeZone: zone, now: session?.client.serverClock.now() ?? Date())
    }

    /// Not tied to the view: the sheet cannot close while a request runs.
    private func perform(_ id: String, page: RedeemGrantPendingModel) {
        guard let kind = CompensationPendingAction.Kind(rawValue: String(id.dropFirst(Self.prefix.count))) else { return }
        switch kind {
        case .check: Task { await page.check(app: model) }
        case .retry: Task { await page.retry(app: model) }
        case .abandon: confirmsAbandon = true
        case .markChecked: if page.markChecked(app: model) { dismiss() }
        case .regrant: if let regrant = page.regrant { onRegrant(regrant) }
        }
    }
    private func abandon() {
        guard let page, page.abandon(app: model) else { return }
        dismiss()
    }
    private func leave(_ exit: RedeemGrantPendingModel.Exit) {
        if case .granted(let code, let replayed, let grant) = exit { model.showGrantReceipt(code, replayed: replayed, grant: grant, router: router) }
        dismiss()
    }
    private func prepare() async {
        if page == nil { page = RedeemGrantPendingModel(recordID: recordID, record: model.pendingCompensations.first { $0.id == recordID }) }
        await page?.loadActorLabel(app: model)
    }
    private func wakeAfterCooldown() async {
        guard let until = model.retryHeldUntil(recordID) else { return }
        try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.2))
        guard !Task.isCancelled else { return }
        tick = Date()
    }
}

/// The page's state: one request at a time, each answer kept only for the session that asked. The record is AppModel's, so a
/// check here also clears the overview's row, the settings row and the user detail's banner.
@MainActor @Observable
final class RedeemGrantPendingModel {
    enum Exit: Equatable {
        /// Granted by “用同一编号重试”: the receipt with 查看兑换码.
        case granted(AdminRedeemCode, replayed: Bool, grant: PendingCompensation)
        /// The check found it granted; S6-08's settle showed its receipt.
        case checked
    }
    struct Notice: Equatable {
        let text: String
        let tone: Tone
    }

    let recordID: UUID
    /// The record as the page found it: the receipt and 重新发放 keep it after it was settled.
    let snapshot: PendingCompensation?
    private(set) var busy: RedeemReconcilePresentation.Busy?
    private(set) var notice: Notice?
    /// Another administrator's email for the restriction line.
    private(set) var actorLabel: String?
    private(set) var exit: Exit?
    private(set) var regrant: GrantRegrant?
    private var stage: CompensationPendingState

    init(recordID: UUID, record: PendingCompensation?) {
        self.recordID = recordID; snapshot = record
        stage = record == nil ? .settled : .awaitingCheck
    }

    /// A page whose record was settled elsewhere (the foreground check, another page) says so.
    func state(recordExists: Bool) -> CompensationPendingState {
        switch stage {
        case .awaitingCheck, .notFound, .createdNotRedeemed, .unverifiable: recordExists ? stage : .settled
        case .regrant, .ended, .settled: stage
        }
    }
    func loadActorLabel(app: AppModel) async {
        guard let snapshot, actorLabel == nil, app.retryPermission(for: snapshot) == .otherActor else { return }
        actorLabel = await app.pendingActorLabel(for: snapshot)
    }

    /// 核对发放结果 (60 §19.4 step 6): only reads.
    func check(app: AppModel) async {
        guard busy == nil, let grant = snapshot else { return }
        guard app.pendingCompensations.contains(where: { $0.id == recordID }) else { stage = .settled; return }
        busy = .checking; notice = nil
        defer { busy = nil }
        do {
            let outcome = try await app.checkCompensation(grant)
            switch outcome {
            case .issued:
                app.settleIssuedCompensation(grant)
                RedeemCodesModel.noteExternalChange()
                exit = .checked
            case .redeemedByOther:
                // Not granted to this user (19.4 step 6, as REDEEM_CODE_CONFLICT): settled, the same content under a new code.
                do { try app.resolve(grant) } catch { app.report(error) }
                offerRegrant(grant, message: CompensationPendingPresentation.otherUserMessage, keepsCode: false, atValueStep: false)
            case .createdNotRedeemed, .notFound, .unverifiable:
                stage = CompensationPendingState(outcome) ?? .settled
            }
        } catch is CancellationError {
        } catch {
            notice = Notice(text: BalanceReconcilePresentation.failedText, tone: .critical)
        }
    }

    /// 用同一编号重试 (19.4 step 7): same key, same bytes, by its sender only; the answer follows the result table.
    func retry(app: AppModel) async {
        guard busy == nil, let grant = snapshot else { return }
        busy = .retrying; notice = nil
        defer { busy = nil }
        switch await app.compensationSubmission().retry(recordID, progress: { _ in }) {
        case .granted(let code, let replayed): exit = .granted(code, replayed: replayed, grant: grant)
        case .gone: stage = .settled
        case .pending(let text):
            // STORE_UNAVAILABLE's cooldown is the grey button's own line.
            stage = .awaitingCheck
            notice = app.retryHeldUntil(recordID) == nil ? Notice(text: text, tone: .caution) : nil
        case .refused(let text), .paused(let text): notice = Notice(text: text, tone: .caution)
        case .notSaved(let text): notice = Notice(text: text, tone: .critical)
        case .reconfirm(_, let text): notice = Notice(text: text, tone: .caution)
        case .renumber(let text): offerRegrant(grant, message: text, keepsCode: false, atValueStep: false)
        case .backToValue(let text): offerRegrant(grant, message: text, keepsCode: false, atValueStep: true)
        case .newKey(let text): offerRegrant(grant, message: text, keepsCode: true, atValueStep: false)
        case .userGone(let text), .rejected(let text): stage = .ended(text)
        case .blocked, .notAuthorized, .stale: break
        }
    }

    /// After its confirmation (19.4 step 8): the record goes, nothing is sent; one already gone counts as done.
    func abandon(app: AppModel) -> Bool {
        close(app: app, receipt: Receipt(text: CompensationPendingPresentation.abandonReceipt, systemImage: "xmark.circle", tone: .neutral))
    }
    /// 我已在 Web 核对 of a code marked used without a user.
    func markChecked(app: AppModel) -> Bool {
        close(app: app, receipt: Receipt(text: CompensationPendingPresentation.markCheckedReceipt))
    }

    private func close(app: AppModel, receipt: Receipt) -> Bool {
        if let grant = snapshot, app.pendingCompensations.contains(where: { $0.id == recordID }) {
            do { try app.abandon(grant) } catch {
                notice = Notice(text: error.localizedDescription, tone: .critical)
                return false
            }
        }
        app.receipts.show(receipt)
        return true
    }
    private func offerRegrant(_ grant: PendingCompensation, message: String, keepsCode: Bool, atValueStep: Bool) {
        stage = .regrant(message)
        regrant = GrantRegrant(grant: grant, keepsCode: keepsCode, atValueStep: atValueStep,
                               notice: keepsCode || atValueStep ? message : RedeemGrantPresentation.renumberedNotice)
    }
}
