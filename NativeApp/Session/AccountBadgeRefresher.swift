import Foundation

/// 20 §1.6: the account tab's badge is fetched again every 60 seconds in the foreground, unless the list or LiveOpsStore wrote it
/// within the last 60 seconds. A failure keeps the shown count and says nothing (20 §1.5). Times are the device clock, which only
/// measures elapsed time, as for every writer of AccountErrorBadge.
@MainActor
final class AccountBadgeRefresher {
    static let interval: Duration = .seconds(60)
    private let badge: AccountErrorBadge
    private let isActive: @MainActor () -> Bool
    private let fetch: @MainActor () async throws -> Int
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (Duration) async throws -> Void

    init(badge: AccountErrorBadge, isActive: @escaping @MainActor () -> Bool, fetch: @escaping @MainActor () async throws -> Int,
         now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.badge = badge; self.isActive = isActive; self.fetch = fetch; self.now = now; self.sleep = sleep
    }

    func refreshIfNeeded() async {
        guard isActive(), badge.needsRefresh(now: now()) else { return }
        let readAt = now()
        guard let count = try? await fetch() else { return }
        badge.update(errorCount: count, at: readAt)
    }

    /// Until the task is cancelled: a check at once, then one every interval.
    func run() async {
        while !Task.isCancelled {
            await refreshIfNeeded()
            do { try await sleep(Self.interval) } catch { return }
        }
    }
}
