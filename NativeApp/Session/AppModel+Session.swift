import Foundation
import Sub2Core

/// The scene lifecycle of the connected site (00 §4.6, §9.5; D11, D18).
extension AppModel {
    var isSuspended: Bool { lifecycle.isSuspended }
    /// Pages without their own scene handling reload when this changes (D18).
    var foregroundRevision: Int { lifecycle.foregroundRevision }

    /// The only scene-phase entry (RootView); S0-12 and S0-13 dispatch their foreground work from here too.
    func sceneDidChange(to activity: AppActivity) {
        switch lifecycle.transition(to: activity, now: Date(), lastProbe: siteSession?.probedAt) {
        case .none: return
        case .suspend: forwardToClient { await $0.suspend() }
        case .resume(let reprobe):
            forwardToClient { await $0.resume() }
            if reprobe { Task { await reprobeActiveSession() } }
        }
    }
    /// Back after more than five minutes (00 §4.6). A failed probe keeps the previous site session; a session the server
    /// ended is reported by the client instead.
    func reprobeActiveSession() async {
        do { try await reloadSiteSession() } catch { return }
    }

    /// Suspend and resume reach the client in the order the scene changed.
    private func forwardToClient(_ action: @escaping @Sendable (APIClient) async -> Void) {
        guard let client else { return }
        let previous = sceneTask
        sceneTask = Task { await previous?.value; await action(client) }
    }
}
