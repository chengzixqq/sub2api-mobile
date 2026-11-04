import Foundation
import Observation
import Sub2Core

/// 20 §2.3 “本次已更换 Key”: kept in memory for the session (AppModel builds a new one in publish and endActiveSession). The mark
/// holds while the account is as it was when the key was replaced: an error account until the error is gone (a passing test
/// clears it) or comes back after the replacement; a healthy one until it errors.
@MainActor @Observable
final class AccountKeyReplacementMarks {
    struct Mark: Equatable, Sendable {
        /// ServerClock time.
        let replacedAt: Date
        let wasError: Bool
    }

    private(set) var marks: [Int: Mark] = [:]

    init() {}

    func record(_ account: UpstreamAccount, at replacedAt: Date) {
        marks[account.id] = Mark(replacedAt: replacedAt, wasError: account.status == "error")
    }
    /// nil once the account no longer matches; an `error_at` that cannot be read keeps the mark.
    func mark(for account: UpstreamAccount) -> Mark? {
        guard let mark = marks[account.id], (account.status == "error") == mark.wasError else { return nil }
        if mark.wasError, let erredAt = ServerTime.parseTimestamp(account.errorAt), erredAt > mark.replacedAt { return nil }
        return mark
    }
    func isReplaced(_ account: UpstreamAccount) -> Bool { mark(for: account) != nil }
    /// Drops a mark that no longer holds, so it cannot come back when the account changes again.
    func reconcile(_ account: UpstreamAccount) {
        guard marks[account.id] != nil, mark(for: account) == nil else { return }
        marks[account.id] = nil
    }
    func remove(accountID: Int) { marks[accountID] = nil }
}
