import SwiftUI
import Sub2Core

/// 30 §2.3, R02: at the top of the detail, before the disabled banner. The user's earliest pending balance write of this
/// address (C-26) and every compensation, one caution banner each; a record of an older login says so. “核对” checks a
/// balance record here (a progress while it runs) and opens a compensation's result page (60 §19). One settled, the next
/// shows.
struct PendingBalanceBanner: View {
    let userID: Int
    /// The balance on the page, for the Face ID amount of a set (D26).
    let balance: Decimal?
    let flow: BalanceReconcileFlow
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        if model.hasPendingBanner(userID: userID) {
            Section {
                // The start times read “N 分钟前”.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 8) {
                        ForEach(model.pendingBannerEntries(userID: userID, now: context.date)) { row($0) }
                    }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
    }

    private func row(_ entry: PendingBannerEntry) -> some View {
        StatusBanner(tone: .caution, systemImage: "doc.text.magnifyingglass", title: entry.title,
                     detail: [entry.detail, entry.originNote].compactMap { $0 }.joined(separator: "\n")) {
            if flow.isBusy(entry.id) {
                ProgressView()
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("核对中")
                    .accessibilityIdentifier("user.pending.checking.\(entry.id.uuidString)")
            } else {
                Button("核对") { check(entry) }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityIdentifier("user.pending.check.\(entry.id.uuidString)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("user.pending.\(entry.id.uuidString)")
    }

    private func check(_ entry: PendingBannerEntry) {
        switch entry.kind {
        case .compensation:
            guard let grant = model.pendingCompensations.first(where: { $0.id == entry.id }) else { return }
            router.present(.redeemGrant(userID: grant.userID, pendingID: grant.id))
        case .balance:
            guard let op = model.pendingBalance(id: entry.id) else { return }
            Task { await flow.reconcile(op, model: model, balance: balance) }
        }
    }
}
