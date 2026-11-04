import SwiftUI

/// S2-中-27: a routed sheet whose form holds unsaved input keeps a tab switch (AppRouter.select) until it has asked. The sheet
/// tells the router while it is up; the router drops that with the sheet, so a page pushed inside the sheet keeps it. A switch
/// that waits runs `ask`, the sheet's own question: 放弃 goes on with `confirmPendingSelect()`, staying calls
/// `cancelPendingSelect()`.
private struct TabSwitchGuard: ViewModifier {
    let hasUnsavedInput: Bool
    let ask: @MainActor () -> Void
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .onChange(of: hasUnsavedInput, initial: true) { _, unsaved in router.sheetHasUnsavedInput = unsaved }
            .onChange(of: router.pendingSelect) { _, pending in if pending != nil { ask() } }
    }
}

extension View {
    func guardsTabSwitch(hasUnsavedInput: Bool, ask: @escaping @MainActor () -> Void) -> some View {
        modifier(TabSwitchGuard(hasUnsavedInput: hasUnsavedInput, ask: ask))
    }
}
