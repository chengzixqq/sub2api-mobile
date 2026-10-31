import Observation

/// C-12: a user's data changed somewhere else in this session, so a page showing that user reads it again. Session state
/// (C-0.2): AppModel makes a new one in `publish` and drops it in `endActiveSession`.
/// `bumpBalance`: 充值 / 退款 succeeded, “用同一编号重试” found it done, a balance compensation was granted.
/// `bump`: reconciliation found a write done, the edit page saved, groups or keys changed authorisations, other compensation.
/// The user page reloads on `revision(userID:)`; the edit page's leaving confirmation counts “余额” by `balanceRevision(userID:)`.
@MainActor @Observable
final class UserChangeSignal {
    /// Profile or balance changes.
    private(set) var revisions: [Int: Int] = [:]
    /// Balance writes only.
    private(set) var balanceRevisions: [Int: Int] = [:]

    init() {}

    func bump(userID: Int) { revisions[userID, default: 0] += 1 }
    func bumpBalance(userID: Int) {
        balanceRevisions[userID, default: 0] += 1
        revisions[userID, default: 0] += 1
    }
    func revision(userID: Int) -> Int { revisions[userID] ?? 0 }
    func balanceRevision(userID: Int) -> Int { balanceRevisions[userID] ?? 0 }
}
