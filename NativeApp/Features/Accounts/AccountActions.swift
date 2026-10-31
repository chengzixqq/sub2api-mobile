import SwiftUI
import Sub2Core

// 20 §5 on screen: the App's entry to AccountActions (C-7), the recover confirmation and the list row's swipe. The class itself is
// NativeApp/Session/AccountActionsCore.swift, so its flows are unit-tested.
extension AccountActions {
    /// Writes go through AppModel+Accounts and their receipts to the App's one ReceiptCenter.
    convenience init(model: AppModel, onChange: @escaping @MainActor (UpstreamAccount) -> Void, onMissing: (@MainActor (Int) -> Void)? = nil) {
        self.init(source: model, receipts: model.receipts, onChange: onChange, onMissing: onMissing)
    }
}

/// 20 §5.3 `confirmRecover` for the account in `account`; picking an option runs `recover` with or without scheduling.
struct AccountRecoverDialog: ViewModifier {
    @Binding var account: UpstreamAccount?
    let actions: AccountActions
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let copy = account.map { AccountActionCopy.recoverDialog(for: $0, now: model.serverNow()) }
        return content.confirmationDialog(copy?.title ?? "", isPresented: isPresented, titleVisibility: .visible, presenting: account) { target in
            ForEach(copy?.options ?? []) { option in
                Button(option.title) { Task { await actions.recover(target, enableScheduling: option.enablesScheduling) } }
                    .accessibilityIdentifier("account.recover.\(option.rawValue)")
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text(copy?.message ?? "")
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { account != nil }, set: { if !$0 { account = nil } })
    }
}

extension View {
    func accountRecoverDialog(_ account: Binding<UpstreamAccount?>, actions: AccountActions) -> some View {
        modifier(AccountRecoverDialog(account: account, actions: actions))
    }

    /// 20 §1.4: 停止调度 or 启用调度 on the row's trailing edge; none without actions, for a read-only token (C-1: swipe actions
    /// are not offered rather than greyed) or where the switch would not help (S2D1-20).
    func accountScheduleSwipe(_ account: UpstreamAccount, actions: AccountActions?, now: Date, isReadOnly: Bool) -> some View {
        let swipe = isReadOnly ? nil : AccountActionCopy.swipeAction(for: account, now: now)
        return swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let actions, let swipe {
                Button { Task { await actions.setSchedulable(account, enabled: swipe.enables) } } label: {
                    Label(swipe.title, systemImage: swipe.systemImage)
                }
                .tint(swipe.enables ? Palette.accent : Tone.neutral.base)
                .disabled(actions.isRunning(account.id))
                .accessibilityIdentifier("account.\(account.id).schedule")
            }
        }
    }
}
