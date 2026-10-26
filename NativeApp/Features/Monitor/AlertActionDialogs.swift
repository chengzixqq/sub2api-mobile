import SwiftUI
import Sub2Core

/// C-6: a page's request to confirm one alert action (S1-12 alert detail, S1-16 monitor rows, S2-22 the account tab's alert
/// sheet); `.alertActions($request)` shows it and hands the choice to the session's AlertActions.
struct AlertActionRequest: Identifiable {
    typealias Kind = AlertActionKind
    let id: UUID
    let event: AlertEvent
    let kind: Kind

    init(event: AlertEvent, kind: Kind, id: UUID = UUID()) { self.id = id; self.event = event; self.kind = kind }
}

extension View {
    /// 10 §7.1, §0.7-8: 手动解决 as an alert; 静默 and 改静默时长 as a confirmation dialog, 结束静默 destructive. A request for an event
    /// whose write is still on the way, or without a session, shows nothing and is cleared.
    func alertActions(_ request: Binding<AlertActionRequest?>) -> some View { modifier(AlertActionDialogs(request: request)) }
}

private struct AlertActionDialogs: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var request: AlertActionRequest?

    /// The request with its dialog, while it can be shown.
    private struct Shown {
        let request: AlertActionRequest
        let dialog: AlertActionDialog
        let actions: AlertActions
    }

    func body(content: Content) -> some View {
        let shown = shownRequest
        content
            .alert(shown?.dialog.title ?? "", isPresented: isPresented(.alert, shown), presenting: shown) { buttons($0) } message: {
                Text($0.dialog.message)
            }
            .confirmationDialog(shown?.dialog.title ?? "", isPresented: isPresented(.actionSheet, shown), titleVisibility: .visible,
                                presenting: shown) { buttons($0) } message: { Text($0.dialog.message) }
            .onChange(of: request?.id, initial: true) {
                if request != nil, shownRequest == nil { request = nil }
            }
    }

    private var shownRequest: Shown? {
        guard let pending = request, let actions = model.liveOps?.alertActions, !actions.isRunning(pending.event.id) else { return nil }
        return Shown(request: pending, dialog: actions.dialog(for: pending.kind, event: pending.event), actions: actions)
    }

    private func isPresented(_ style: AlertActionDialog.Style, _ shown: Shown?) -> Binding<Bool> {
        Binding(get: { shown?.dialog.style == style }, set: { isShown in
            if !isShown, shown?.dialog.style == style { request = nil }
        })
    }

    /// The request is cleared before the write starts, so the dialog never comes back when the write ends.
    @ViewBuilder private func buttons(_ shown: Shown) -> some View {
        ForEach(shown.dialog.options) { option in
            Button(option.title, role: option.isDestructive ? .destructive : nil) {
                let actions = shown.actions, event = shown.request.event
                request = nil
                Task { await actions.perform(option.choice, on: event) }
            }
            .accessibilityIdentifier("alertActions." + option.id)
        }
        Button("取消", role: .cancel) { request = nil }
            .accessibilityIdentifier("alertActions.cancel")
    }
}
