import SwiftUI
import Sub2Core

/// 60 §19.1 打开前拦截 (X38): the user detail's “发放兑换码（补偿）…” asks first while a compensation of this user at this address
/// awaits its check (X34, no exception for a compensation), and opens nothing while the compensation file cannot be read.
enum RedeemGrantEntry {
    /// Opens the sheet and returns nil, or returns the question to ask first (shown by `.redeemGrantBlockAlert`).
    @MainActor static func open(userID: Int, model: AppModel, router: AppRouter, timeZone: TimeZone) -> GrantBlockPrompt? {
        let decision = GrantEntryDecision.decide(gate: model.moneyWriteGate(.compensation(userID: userID)), compensations: model.pendingCompensations,
                                                 groupNames: model.grantGroupNames, now: Date(), timeZone: timeZone)
        switch decision {
        case .open:
            router.present(.redeemGrant(userID: userID, pendingID: nil))
        case .paused(let message):
            model.receipts.show(Receipt(text: message, systemImage: "exclamationmark.triangle", tone: .caution))
        case .blocked(let prompt):
            return prompt
        }
        return nil
    }
}

extension View {
    /// “上一次补偿的发放结果未确认”: 先核对 (the default) opens that record's pending page in the sheet, 取消 nothing.
    func redeemGrantBlockAlert(_ prompt: Binding<GrantBlockPrompt?>, userID: Int, router: AppRouter) -> some View {
        modifier(RedeemGrantBlockAlert(prompt: prompt, userID: userID, router: router))
    }
}

private struct RedeemGrantBlockAlert: ViewModifier {
    @Binding var prompt: GrantBlockPrompt?
    let userID: Int
    let router: AppRouter
    /// A sheet opened from this alert's button waits for it to leave.
    private static let followUpDelay: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        content.alert(GrantBlockPrompt.title, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { shown in
            Button(GrantBlockPrompt.checkTitle) {
                let router = router, userID = userID
                Task { @MainActor in
                    try? await Task.sleep(for: Self.followUpDelay)
                    router.present(.redeemGrant(userID: userID, pendingID: shown.recordID))
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(GrantBlockPrompt.cancelTitle, role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }
}
