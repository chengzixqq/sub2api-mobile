import Foundation
import Observation

/// C-11, 20 §1.6: the account tab's badge, the site's error account count. Session state (C-0.2): AppModel makes a new one in
/// `publish` and in `endActiveSession`. The list writes it from status-summary and LiveOpsStore from availability; both pass the
/// device time the data was read at, which only measures elapsed time.
@MainActor @Observable
final class AccountErrorBadge {
    nonisolated static let refreshInterval: TimeInterval = 60
    private(set) var errorCount = 0
    private(set) var updatedAt: Date?

    init() {}

    /// A result read up to a minute before the shown one is a late reply and is dropped; further back means the clock moved.
    func update(errorCount: Int, at date: Date) {
        if let updatedAt, date < updatedAt, updatedAt.timeIntervalSince(date) < Self.refreshInterval { return }
        self.errorCount = max(0, errorCount)
        updatedAt = date
    }
    /// Read within the last 60 seconds: skip. A clock moved back counts as due.
    func needsRefresh(now: Date) -> Bool {
        guard let updatedAt else { return true }
        let elapsed = now.timeIntervalSince(updatedAt)
        return elapsed < 0 || elapsed >= Self.refreshInterval
    }
}
