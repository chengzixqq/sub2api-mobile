import SwiftUI
import Sub2Core

/// 60 §8.4 生成: the list's + and the empty list's 生成兑换码 ask first while a batch of this address awaits its result (R03,
/// X34), and open nothing while the batch file cannot be read (00 §2.5.5).
enum RedeemGenerateEntry {
    /// Opens the wizard and returns nil, or returns the question to ask first (shown by `.redeemGenerateEntry`).
    @MainActor static func open(model: AppModel, router: AppRouter, now: Date, timeZone: TimeZone) -> RedeemGenerateIntercept? {
        let decision = RedeemGenerateEntryDecision.decide(gate: model.moneyWriteGate(.redeemGenerate), batches: model.pendingRedeemBatches,
                                                          now: now, timeZone: timeZone)
        switch decision {
        case .open:
            router.present(.redeemGenerate)
        case .paused(let message):
            model.receipts.show(Receipt(text: message, systemImage: "exclamationmark.triangle", tone: .caution))
        case .intercept(let question):
            return question
        }
        return nil
    }
}

extension View {
    /// “上一批兑换码的生成结果未确认”: 先核对 (the default) opens that batch's check sheet, 仍要生成新的一批 opens the wizard (R03's
    /// exception), 取消 nothing.
    func redeemGenerateEntry(_ question: Binding<RedeemGenerateIntercept?>, reconcile: @escaping @MainActor @Sendable (UUID) -> Void,
                             generate: @escaping @MainActor @Sendable () -> Void) -> some View {
        modifier(RedeemGenerateEntryAlert(question: question, reconcile: reconcile, generate: generate))
    }
}

private struct RedeemGenerateEntryAlert: ViewModifier {
    @Binding var question: RedeemGenerateIntercept?
    let reconcile: @MainActor @Sendable (UUID) -> Void
    let generate: @MainActor @Sendable () -> Void
    /// A sheet opened from this alert's button waits for it to leave.
    private static let followUpDelay: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        content.alert(RedeemGenerateIntercept.title, isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                      presenting: question) { shown in
            Button(RedeemGenerateIntercept.reconcileTitle) { afterAlert { reconcile(shown.batchID) } }
                .keyboardShortcut(.defaultAction)
            Button(RedeemGenerateIntercept.overrideTitle) { afterAlert(generate) }
            Button(RedeemGenerateIntercept.cancelTitle, role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }

    private func afterAlert(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.followUpDelay)
            action()
        }
    }
}
