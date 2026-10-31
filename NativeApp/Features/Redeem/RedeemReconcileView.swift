import SwiftUI
import Sub2Core

/// `.redeemReconcile(batchID:)` 核对结果 (60 §11): the pending page, the page after a check that found nothing, and the
/// result page. Settings, the list's banner and the overview's row open it for the same record, with the current identity,
/// also for an older login at this address (X34). Nothing is read until a button is tapped (11.6); while a request runs both
/// buttons wait and the sheet stays (11.5).
struct RedeemReconcileView: View {
    let batchID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var page: RedeemReconcileModel?
    @State private var confirmsAbandon = false
    /// Moves when a retry cooldown ends, so the grey button wakes up.
    @State private var tick = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let page { content(page).padding(16) }
            }
            .background(Palette.sheetBackground)
            .navigationTitle("核对结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isResult ? "完成" : "关闭") { dismiss() }.disabled(page?.busy != nil).accessibilityIdentifier("sheet.close")
                }
            }
            .accessibilityIdentifier("redeem.reconcile.root")
        }
        .interactiveDismissDisabled(page?.busy != nil)
        .alert(RedeemReconcilePresentation.abandonPromptTitle, isPresented: $confirmsAbandon) {
            Button(RedeemReconcilePresentation.abandonTitle, role: .destructive) { abandon() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(RedeemReconcilePresentation.abandonPromptMessage)
        }
        .task { await prepare() }
        .task(id: model.retryHeldUntil(batchID)) { await wakeAfterCooldown() }
    }

    private var isResult: Bool {
        if case .result? = page?.phase { true } else { false }
    }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }
    /// The server's clock, for the receipt's date.
    private var now: Date { session?.client.serverClock.now() ?? Date() }
    /// The phone's clock, like the cooldown; reading `tick` redraws the page when it ends.
    private var clock: Date { max(tick, Date()) }

    @ViewBuilder private func content(_ page: RedeemReconcileModel) -> some View {
        switch page.phase {
        case .result(let kind, let codes):
            if let batch = page.snapshot {
                RedeemResultView(kind: kind, spec: batch.spec, codes: codes, startedAt: batch.createdAt, timeZone: zone,
                                 onConfirmChecked: kind.needsConfirmation && !page.isConfirmed ? { page.confirmChecked(model: model) } : nil)
            }
        case .pending:
            let exists = model.pendingRedeemBatches.contains { $0.id == batchID }
            pending(page, stage: page.stage(recordExists: exists) ?? .settled)
        }
    }

    private func pending(_ page: RedeemReconcileModel, stage: RedeemReconcileStage) -> some View {
        let header = RedeemReconcilePresentation.header(for: stage), clock = self.clock
        let retry = page.snapshot.map { model.redeemRetryContext(for: $0, actorLabel: page.actorLabel) } ?? .refusing
        let notes = RedeemReconcilePresentation.notes(for: stage, retry: retry, now: clock)
        return VStack(spacing: 16) {
            MoneyPendingHeader(systemImage: header.systemImage, title: header.title, message: header.message, tone: header.tone)
            if let batch = page.snapshot { MoneyPendingReceipt(lines: receipt(batch)) }
            if let notice = page.notice { MoneyPendingNotice(text: notice.text, tone: notice.tone) }
            MoneyPendingActions(actions: actions(stage, retry: retry, busy: page.busy, now: clock)) { perform($0, page: page) }
            if !notes.isEmpty { MoneyPendingFootnote(text: notes.joined(separator: "\n"), identifier: "redeem.reconcile.notes") }
            if let footnote = RedeemReconcilePresentation.footnote(for: stage, isLegacyServer: model.isLegacyRedeemServer) {
                MoneyPendingFootnote(text: footnote)
            }
        }
    }

    private func receipt(_ batch: PendingRedeemBatch) -> [MoneyReceiptLine] {
        let origin = PendingRecordOrigin(recordServerID: batch.serverID, currentServerID: model.activeProfile?.id, sameAddress: model.sameAddressServerIDs())
        let site = model.profileForRecord(serverID: batch.serverID)?.name ?? model.activeProfile?.name ?? "原站点"
        return RedeemReconcilePresentation.receipt(batch, siteName: site, origin: origin, timeZone: zone, now: now)
    }
    private func actions(_ stage: RedeemReconcileStage, retry: RedeemRetryContext, busy: RedeemReconcilePresentation.Busy?, now: Date) -> [MoneyPendingAction] {
        RedeemReconcilePresentation.actions(for: stage, retry: retry, busy: busy, now: now).map {
            MoneyPendingAction(id: Self.identifier($0.kind), title: $0.title, isPrimary: $0.isPrimary, isEnabled: $0.isEnabled)
        }
    }
    private static func identifier(_ kind: RedeemReconcileAction.Kind) -> String { "redeem.reconcile." + kind.rawValue }

    /// Not tied to the view: the sheet cannot close while a request runs.
    private func perform(_ id: String, page: RedeemReconcileModel) {
        switch id {
        case Self.identifier(.check): Task { await page.check(model: model) }
        case Self.identifier(.retry): Task { await page.retry(model: model) }
        case Self.identifier(.abandon): confirmsAbandon = true
        default: break
        }
    }
    private func abandon() {
        guard let page, page.abandon(model: model) else { return }
        dismiss()
    }
    private func prepare() async {
        if page == nil { page = RedeemReconcileModel(batchID: batchID, record: model.pendingRedeemBatches.first { $0.id == batchID }) }
        await page?.loadActorLabel(model: model)
    }
    private func wakeAfterCooldown() async {
        guard let until = model.retryHeldUntil(batchID) else { return }
        try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.2))
        guard !Task.isCancelled else { return }
        tick = Date()
    }
}
