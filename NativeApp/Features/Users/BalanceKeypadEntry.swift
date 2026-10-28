import SwiftUI
import Sub2Core

extension BalanceKeypadMode {
    var direction: BalanceDirection { self == .topup ? .credit : .debit }
    init(_ direction: BalanceDirection) { self = direction == .credit ? .topup : .refund }
}

/// R03's first confirmation (30 §3.4): a record of the same direction awaiting its check asks before the keypad opens; the
/// other direction never does. S3-05's detail and S3-11's identity strip open the keypad through `open`.
struct BalanceKeypadEntry: Identifiable {
    let id = UUID()
    let userID: Int
    let mode: BalanceKeypadMode
    /// The earliest such record, named in the question and checked by “先核对”.
    let pending: PendingBalanceOperation

    var title: String { BalanceChangeCopy.entryTitle(pending) }

    /// Opens the keypad and returns nil, or returns the question to ask first (shown by `.balanceKeypadEntry`).
    @MainActor static func open(userID: Int, mode: BalanceKeypadMode, model: AppModel, router: AppRouter) -> BalanceKeypadEntry? {
        if case .sameDirection(let pending) = check(userID: userID, mode: mode, model: model) {
            return BalanceKeypadEntry(userID: userID, mode: mode, pending: pending)
        }
        router.present(.balanceKeypad(userID: userID, mode: mode))
        return nil
    }
    /// R03 for this user and direction over the connected address's records (X34).
    @MainActor static func check(userID: Int, mode: BalanceKeypadMode, model: AppModel) -> BalancePendingCheck {
        BalancePendingCheck(gate: model.moneyWriteGate(.balance(userID: userID, direction: mode.direction)), balances: model.pendingBalances)
    }
    /// The design's `vuTopup`: 充值 loses its fill while a top-up awaits its check.
    @MainActor static func holdsBack(userID: Int, mode: BalanceKeypadMode, model: AppModel) -> Bool {
        if case .sameDirection = check(userID: userID, mode: mode, model: model) { true } else { false }
    }
}

extension View {
    /// The first confirmation: “先核对” runs `reconcile` (S3-07's check), “仍要充值 / 仍要退款” opens the keypad, “取消”.
    func balanceKeypadEntry(_ entry: Binding<BalanceKeypadEntry?>,
                            reconcile: @escaping @MainActor @Sendable (PendingBalanceOperation) -> Void) -> some View {
        modifier(BalanceKeypadEntryAlert(entry: entry, reconcile: reconcile))
    }
}

private struct BalanceKeypadEntryAlert: ViewModifier {
    @Binding var entry: BalanceKeypadEntry?
    let reconcile: @MainActor @Sendable (PendingBalanceOperation) -> Void
    @Environment(AppRouter.self) private var router
    /// An alert or sheet opened from this alert's button waits for it to leave.
    private static let followUpDelay: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        let shown = entry
        content.alert(shown?.title ?? "", isPresented: Binding(get: { entry != nil && entry?.id == shown?.id }, set: { if !$0, entry?.id == shown?.id { entry = nil } }),
                      presenting: shown) { question in
            Button(BalanceChangeCopy.reconcileFirst) { afterAlert { reconcile(question.pending) } }
            Button(BalanceChangeCopy.proceedAnyway(question.mode.direction)) {
                let router = router
                afterAlert { router.present(.balanceKeypad(userID: question.userID, mode: question.mode)) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text(BalanceChangeCopy.entryMessage)
        }
    }

    private func afterAlert(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.followUpDelay)
            action()
        }
    }
}
