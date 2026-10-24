import Foundation

/// The scene phase of the whole App as AppModel sees it; Sub2MobileApp maps SwiftUI's `ScenePhase` onto it (D18).
enum AppActivity: Sendable { case active, inactive, background }

/// 00 §4.6, §9.5: only `.background` suspends. Coming back to `.active` from there resumes, bumps the revision that pages
/// without their own scene handling reload on, and probes the site again when its last `/admin/me` is over five minutes old.
struct SessionLifecycle: Sendable, Equatable {
    static let reprobeInterval: TimeInterval = 300
    enum Action: Sendable, Equatable { case none, suspend, resume(reprobe: Bool) }
    private(set) var isSuspended = false
    private(set) var foregroundRevision = 0

    /// `lastProbe` is the connected site's `SiteSession.probedAt`; nil when no site is connected.
    mutating func transition(to activity: AppActivity, now: Date, lastProbe: Date?) -> Action {
        switch activity {
        case .inactive: return .none
        case .background:
            guard !isSuspended else { return .none }
            isSuspended = true
            return .suspend
        case .active:
            guard isSuspended else { return .none }
            isSuspended = false; foregroundRevision += 1
            return .resume(reprobe: lastProbe.map { now.timeIntervalSince($0) > Self.reprobeInterval } ?? false)
        }
    }
}
