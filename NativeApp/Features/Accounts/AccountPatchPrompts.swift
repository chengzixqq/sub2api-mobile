import SwiftUI
import Sub2Core

// C-14 on screen: the App's entry to AccountPatchFlow, its two questions and the status row. The flow itself is
// NativeApp/Session/AccountPatchFlow.swift, so its branches are unit-tested.

extension AccountPatchFlow {
    /// Writes go through AppModel+Accounts and their receipts to the App's one ReceiptCenter.
    convenience init(model: AppModel, accountID: Int, onChange: @escaping @MainActor (AccountEditBase) -> Void,
                     onRemoved: @escaping @MainActor () -> Void, onReload: @escaping @MainActor () -> Void) {
        self.init(source: model, receipts: model.receipts, accountID: accountID, onChange: onChange, onRemoved: onRemoved, onReload: onReload)
    }
}

/// 20 §0.4-6 “账号已被其他人修改” (no body: the page behind already shows the server's copy) and §0.4-7 混合渠道警告 (Web's
/// words). The buttons start the flow at once, so the question is gone before the next frame.
private struct AccountPatchPrompts: ViewModifier {
    let flow: AccountPatchFlow

    func body(content: Content) -> some View {
        content
            .alert(AccountEditCopy.conflictTitle, isPresented: asksOverwrite) {
                Button(AccountEditCopy.overwrite) { _ = Task.immediate { await flow.overwrite() } }
                Button(AccountEditCopy.reload) { _ = Task.immediate { await flow.reloadAfterConflict() } }
            }
            .alert(AccountEditCopy.mixedChannelTitle, isPresented: asksMixedChannel) {
                Button(AccountEditCopy.mixedChannelContinue) { _ = Task.immediate { await flow.confirmMixedChannel() } }
                Button("取消", role: .cancel) { flow.dismissPrompt() }
            } message: {
                if case .mixedChannel(_, let warning)? = flow.prompt { Text(warning.message) }
            }
    }

    /// Alerts close only through their buttons, which answer the flow themselves.
    private var asksOverwrite: Binding<Bool> {
        Binding(get: { if case .overwrite? = flow.prompt { true } else { false } }, set: { _ in })
    }
    private var asksMixedChannel: Binding<Bool> {
        Binding(get: { if case .mixedChannel? = flow.prompt { true } else { false } }, set: { _ in })
    }
}

extension View {
    func accountPatchPrompts(_ flow: AccountPatchFlow) -> some View { modifier(AccountPatchPrompts(flow: flow)) }
}

/// What a save that did not finish says inside its sheet (20 §3.5): 没有保存成功 + 重试, 结果未确认 + 刷新核对, a refusal, the
/// cleared notice (保存 again), or the old-server note with 在 Web 中编辑 when the caller can open it.
struct AccountPatchStatusRow: View {
    let flow: AccountPatchFlow
    var onOpenWeb: (() -> Void)?

    init(flow: AccountPatchFlow, onOpenWeb: (() -> Void)? = nil) { self.flow = flow; self.onOpenWeb = onOpenWeb }

    var body: some View {
        if let message {
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text).font(.subheadline).foregroundStyle(message.tone.ink).accessibilityIdentifier("account.edit.message")
                if let button = message.button {
                    Button(button.title, action: button.perform).buttonStyle(.borderless).frame(minHeight: 44)
                        .accessibilityIdentifier(button.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Action {
        let title: String
        let id: String
        let perform: () -> Void
    }
    private struct Message {
        let text: String
        let tone: Tone
        var button: Action?
    }
    private var message: Message? {
        switch flow.phase {
        case .idle, .saving: nil
        case .notApplied:
            Message(text: AccountEditCopy.notApplied, tone: .caution,
                    button: Action(title: AccountEditCopy.retry, id: "account.edit.retry") { Task { await flow.retry() } })
        case .unconfirmed:
            Message(text: AccountEditCopy.unconfirmed, tone: .caution,
                    button: Action(title: AccountEditCopy.recheck, id: "account.edit.recheck") { Task { await flow.recheck() } })
        case .failed(let text): Message(text: text, tone: .critical)
        case .reconfirm(let text): Message(text: text, tone: .caution)
        case .needsWeb(let text):
            Message(text: text, tone: .neutral, button: onOpenWeb.map { Action(title: AccountEditCopy.openWeb, id: "account.edit.openWeb", perform: $0) })
        }
    }
}
