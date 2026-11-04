import Foundation
import Sub2Core

/// S3-14's `-ui-testing` launch arguments; the wrappers in AppModel+Users read them. A site without single-platform writes is
/// `-ui-without-capabilities users.platform_quota_item` (X05).
enum PlatformQuotaFixtureArgument {
    /// restore answers 409 USER_PLATFORM_QUOTA_ACTIVE_EXISTS, as when another administrator set the platform again meanwhile.
    static let restoreConflict = "-ui-quota-restore-conflict"
    /// A site without the quota service: the list is empty (as the server answers) and every write 503 SERVICE_UNAVAILABLE.
    static let unavailable = "-ui-quota-unavailable"
    /// The session's first list read fails with 500.
    static let listError = "-ui-quota-list-error"
}

/// S3-14 (S3D1-04): the session's copy of the platform quota table — Alice (1) Anthropic 10 / 50 / 不限 with $2.80 · $41.00 ·
/// $48.60 used, 王小明 (3) OpenAI 0 / 0 / 0. Writes change it as the handlers do: a new row starts from 0, a removed one goes on
/// a soft-delete stack that restore takes back with its use, the whole-table PUT keeps the use of the rows it updates.
@MainActor final class PlatformQuotaDemoStore {
    private struct Row {
        let platform: String
        let limits: PlatformQuotaLimits
        let usage: [PlatformQuotaWindowKind: Decimal]
        /// nil until the first request (or a reset) starts the windows.
        let started: Date?
    }
    private static var stores: [UUID: PlatformQuotaDemoStore] = [:]
    private var rows: [Int: [Row]]
    private var deleted: [Int: [String: [Row]]] = [:]
    private var listReads = 0

    /// One per session; the first use copies the seed.
    static func current(for generation: UUID) -> PlatformQuotaDemoStore {
        if let store = stores[generation] { return store }
        let store = PlatformQuotaDemoStore(now: Date())
        stores[generation] = store
        return store
    }
    private init(now: Date) {
        func amount(_ text: String) -> Decimal { Decimal(string: text)! }
        rows = [
            1: [Row(platform: "anthropic", limits: PlatformQuotaLimits(daily: 10, weekly: 50), usage: [.daily: amount("2.80"), .weekly: 41, .monthly: amount("48.60")],
                    started: now)],
            3: [Row(platform: "openai", limits: PlatformQuotaLimits(daily: 0, weekly: 0, monthly: 0), usage: [:], started: nil)],
        ]
    }

    func list(userID: Int, arguments: [String], now: Date, zone: ServerTimeZone) throws -> [UserPlatformQuota] {
        listReads += 1
        if arguments.contains(PlatformQuotaFixtureArgument.listError), listReads == 1 { throw APIError.server(status: 500, reason: nil) }
        if arguments.contains(PlatformQuotaFixtureArgument.unavailable) { return [] }
        return quotas(userID, zone: zone)
    }
    func upsert(userID: Int, platform: String, limits: PlatformQuotaLimits, zone: ServerTimeZone) -> PlatformQuotaUpsertResult {
        let old = row(userID, platform)
        guard !limits.isEmpty else {
            if let old { softDelete(old, userID: userID) }
            return PlatformQuotaUpsertResult(platformQuota: nil, previous: old?.limits)
        }
        let fresh = Row(platform: platform, limits: limits, usage: old?.usage ?? [:], started: old?.started)
        rows[userID] = others(userID, platform) + [fresh]
        return PlatformQuotaUpsertResult(platformQuota: Self.quota(fresh, zone: zone), previous: old?.limits)
    }
    func delete(userID: Int, platform: String) throws -> PlatformQuotaDeleteResult {
        guard let old = row(userID, platform) else { throw Self.quotaGone }
        softDelete(old, userID: userID)
        return PlatformQuotaDeleteResult(removed: true, previous: old.limits)
    }
    func restore(userID: Int, platform: String, arguments: [String], zone: ServerTimeZone) throws -> PlatformQuotaRestoreResult {
        if arguments.contains(PlatformQuotaFixtureArgument.restoreConflict) || row(userID, platform) != nil {
            throw APIError.server(status: 409, reason: "USER_PLATFORM_QUOTA_ACTIVE_EXISTS")
        }
        guard let back = deleted[userID]?[platform]?.last else { throw Self.quotaGone }
        deleted[userID]?[platform]?.removeLast()
        rows[userID, default: []].append(back)
        return PlatformQuotaRestoreResult(platformQuota: Self.quota(back, zone: zone), restored: true)
    }
    func reset(userID: Int, platform: String, window: PlatformQuotaWindowKind, now: Date, zone: ServerTimeZone) throws -> [UserPlatformQuota] {
        guard let old = row(userID, platform) else { throw Self.quotaGone }
        let usage = old.usage.merging([window: 0]) { _, zero in zero }
        rows[userID] = (rows[userID] ?? []).map { $0.platform == platform ? Row(platform: platform, limits: old.limits, usage: usage, started: now) : $0 }
        return quotas(userID, zone: zone)
    }
    /// Platforms left out are soft-deleted; kept ones keep their use; new ones start from 0.
    func replace(userID: Int, entries: [PlatformQuotaEntry], zone: ServerTimeZone) -> [UserPlatformQuota] {
        let kept = entries.filter { !$0.limits.isEmpty }
        for old in rows[userID] ?? [] where !kept.contains(where: { $0.platform == old.platform }) { softDelete(old, userID: userID) }
        rows[userID] = kept.map { entry in
            let old = row(userID, entry.platform)
            return Row(platform: entry.platform, limits: entry.limits, usage: old?.usage ?? [:], started: old?.started)
        }
        return quotas(userID, zone: zone)
    }

    private static let quotaGone = APIError.server(status: 404, reason: "USER_PLATFORM_QUOTA_NOT_FOUND")
    private func row(_ userID: Int, _ platform: String) -> Row? { rows[userID]?.first { $0.platform == platform } }
    private func others(_ userID: Int, _ platform: String) -> [Row] { (rows[userID] ?? []).filter { $0.platform != platform } }
    private func softDelete(_ old: Row, userID: Int) {
        rows[userID] = others(userID, old.platform)
        deleted[userID, default: [:]][old.platform, default: []].append(old)
    }
    private func quotas(_ userID: Int, zone: ServerTimeZone) -> [UserPlatformQuota] { (rows[userID] ?? []).map { Self.quota($0, zone: zone) } }
    /// quotaview: the day resets at the server's midnight, the week on Monday, the month 30 days after its start.
    private static func quota(_ row: Row, zone: ServerTimeZone) -> UserPlatformQuota {
        let calendar = zone.calendar
        func window(_ kind: PlatformQuotaWindowKind) -> PlatformQuotaWindow {
            let resets = row.started.map { start -> Date in
                let day = calendar.startOfDay(for: start)
                switch kind {
                case .daily: return calendar.date(byAdding: .day, value: 1, to: day) ?? start
                case .weekly:
                    let weekday = calendar.component(.weekday, from: day)
                    return calendar.date(byAdding: .day, value: (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7, to: day) ?? start
                case .monthly: return start.addingTimeInterval(30 * 86_400)
                }
            }
            return PlatformQuotaWindow(usage: row.usage[kind] ?? 0, limit: row.limits.limit(kind), resetsAt: resets, windowStart: row.started)
        }
        return UserPlatformQuota(platform: row.platform, daily: window(.daily), weekly: window(.weekly), monthly: window(.monthly))
    }
}
