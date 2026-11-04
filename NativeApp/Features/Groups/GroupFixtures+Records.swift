import Foundation
import Sub2Core

/// 50 §6–§7 `-ui-testing` (S5-12, X44): the group's keys and subscriptions on the fixture site. Each group has as many keys and
/// subscriptions as GroupFixtures.stats says (S5-05, the detail's counts); the curated rows come first (newest), the rest are plain
/// active keys of users 13–20. Only masks, never a plaintext; the table is not the user pages' UserKeyDemoStore (X05).
extension GroupFixtures {
    enum RecordsArgument {
        /// The session's first page-1 key read answers 502; later ones work.
        static let keysFailure = "-ui-group-keys-failure"
        /// The session's first key read past page 1 answers 502; later ones work.
        static let keysMoreFailure = "-ui-group-keys-more-failure"
        /// Reads past page 1 take 5 seconds, so the “已显示” footer can be read.
        static let slowMore = "-ui-group-records-slow-more"
        /// S5-高-3: on one key page the second today read answers 502; the first and later ones work.
        static let keysTodayFailureAfterFirst = "-ui-group-keys-today-failure-after-first"
        /// S5-高-3: on one subscription page the second active-count read answers 502; the first and later ones work.
        static let subsCountFailureAfterFirst = "-ui-group-subs-count-failure-after-first"
    }
    static let slowMoreDelay: Duration = .seconds(5)

    /// today_actual_cost; a key not listed spent nothing today (the server leaves it out).
    static let recordKeyCosts: [Int: Decimal] = ([5138: "12.4", 5137: "3.15", 5135: "1.2", 5134: "0.86", 5406: "4.5", 5321: "2.05"] as [Int: String])
        .mapValues { Decimal(string: $0) ?? 0 }

    /// id = 5000 + group × 100 + n, newest first.
    static func recordKeys(groupID: Int, now: Date) -> [AdminAPIKey] {
        let total = stats(groupID: groupID).totalAPIKeys
        guard total > 0 else { return [] }
        let curated = curatedKeys(groupID: groupID, now: now)
        let base = 5000 + groupID * 100
        return (1...total).reversed().map { n in
            let id = base + n
            if let key = curated.first(where: { $0.id == id }) { return key }
            let userID = 13 + n % 8
            return AdminAPIKey(id: id, userID: userID, keyMasked: "sk-…" + String(format: "%04d", id % 10_000), name: "密钥 \(n)", groupID: groupID,
                               status: "active", effectiveStatus: "active", lastUsedAt: now.addingTimeInterval(-Double(n % 5 + 1) * 3_600),
                               user: summary(userID))
        }
    }
    /// Subscription groups only; ids from 801, the curated rows first.
    static func recordSubscriptions(groupID: Int, now: Date) -> [AdminUserSubscription] {
        let counts = stats(groupID: groupID)
        guard counts.subscriptionsTotal > 0 else { return [] }
        let day: TimeInterval = 86_400
        func row(_ id: Int, _ userID: Int?, _ status: String, days: Double, usage: (String, String, String) = ("0", "0", "0"),
                 withUser: Bool = true) -> AdminUserSubscription {
            AdminUserSubscription(id: id, userID: userID, groupID: groupID, startsAt: now.addingTimeInterval((days - 30) * day),
                                  expiresAt: now.addingTimeInterval(days * day), status: status, dailyUsageUSD: Decimal(string: usage.0),
                                  weeklyUsageUSD: Decimal(string: usage.1), monthlyUsageUSD: Decimal(string: usage.2),
                                  user: withUser ? userID.flatMap(Self.summary) : nil)
        }
        let curated = [row(815, 9, "active", days: 4, usage: ("6.2", "18.6", "120")),
                       row(814, 21, "active", days: 26, usage: ("18.2", "64", "236.4")),
                       row(813, 2, "suspended", days: 40), row(812, 5, "expired", days: -7),
                       row(811, 26, "active", days: 60, withUser: false)]
        let extra = max(0, counts.subscriptionsTotal - curated.count)
        let plain = (0..<extra).map { 800 + extra - $0 }.map { id in
            id == 801 ? row(id, 13, "expired", days: -20) : row(id, 13 + id % 8, "active", days: Double(10 + (id - 800) * 3), usage: ("1.5", "7.2", "31"))
        }
        return curated + plain
    }
    static func recordsPage<Row: Decodable & Sendable>(_ rows: [Row], page: Int, size: Int = GroupRecordsPolicy.pageSize) -> Page<Row> {
        Page(items: Array(rows.dropFirst((page - 1) * size).prefix(size)), total: rows.count, page: page, pageSize: size,
             pages: max(1, (rows.count + size - 1) / size))
    }

    /// The fixture server: reads cut by page_size 20; a read-only token is refused api-keys-usage as the server does.
    static func recordsSource(_ app: AppModel, session: SessionContext, group: @escaping @MainActor @Sendable (_ id: Int) async throws -> AdminGroup,
                              arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupRecordsSource {
        let generation = session.generation
        let reads = RecordReads(arguments: arguments)
        return GroupRecordsSource(
            group: group,
            keys: { groupID, page in
                if page == 1, failsOnce(RecordsArgument.keysFailure, generation: generation, arguments: arguments) { throw recordsFailure }
                if page > 1, arguments.contains(RecordsArgument.slowMore) { try await Task.sleep(for: slowMoreDelay) }
                if page > 1, failsOnce(RecordsArgument.keysMoreFailure, generation: generation, arguments: arguments) { throw recordsFailure }
                return recordsPage(recordKeys(groupID: groupID, now: Date()), page: page)
            },
            keysToday: { [weak app] ids in
                if app?.siteSession?.isReadOnlyToken != false { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
                if reads.failsSecond(RecordsArgument.keysTodayFailureAfterFirst) { throw recordsFailure }
                return recordKeyCosts.filter { ids.contains($0.key) }
            },
            subscriptions: { groupID, page in recordsPage(recordSubscriptions(groupID: groupID, now: Date()), page: page) },
            stats: { groupID in
                if reads.failsSecond(RecordsArgument.subsCountFailureAfterFirst) { throw recordsFailure }
                return servedStats(groupID: groupID, arguments: arguments)
            },
            activeSubscriptionCount: { stats(groupID: $0).subscriptionsActive })
    }

    private static let recordsFailure = APIError.server(status: 502, reason: nil)
    /// “<session>/<argument>”: a one-time failure happens once per session.
    private static var spentRecordFailures: Set<String> = []
    private static func failsOnce(_ argument: String, generation: UUID, arguments: [String]) -> Bool {
        arguments.contains(argument) && spentRecordFailures.insert("\(generation)/\(argument)").inserted
    }
    private static func summary(_ userID: Int) -> AdminUserSummary? {
        DemoData.allUsers.first { $0.id == userID }.map { AdminUserSummary(id: $0.id, email: $0.email, username: $0.username, status: $0.status) }
    }
    /// 高级组: the design's rows — Nova 工作室's key used minutes ago, a quota, an expired key of a disabled user, one whose owner
    /// is not embedded, a stopped one with an escaped name. 企业专线: a used-up quota. 默认组: a stopped key.
    private static func curatedKeys(groupID: Int, now: Date) -> [AdminAPIKey] {
        func key(_ id: Int, _ name: String, _ userID: Int?, mask: String, status: String = "active", effective: String = "active",
                 usedAgo: TimeInterval? = 3_600, quota: Decimal = 0, used: Decimal = 0, expiresAt: Date? = nil, embedsUser: Bool = true) -> AdminAPIKey {
            AdminAPIKey(id: id, userID: userID, keyMasked: mask, name: name, groupID: groupID, status: status, effectiveStatus: effective,
                        lastUsedAt: usedAgo.map { now.addingTimeInterval(-$0) }, quota: quota, quotaUsed: used, expiresAt: expiresAt,
                        user: embedsUser ? userID.flatMap(Self.summary) : nil)
        }
        switch groupID {
        case 1:
            return [key(5138, "生产", 21, mask: "sk-…Kp21", usedAgo: 180), key(5137, "测试环境", 10, mask: "sk-…T7e2", usedAgo: 7_200),
                    key(5136, "CI 流水线", 3, mask: "sk-…c1Q8", usedAgo: 86_400),
                    key(5135, "移动端", 9, mask: "sk-…m9A4", usedAgo: 1_800, quota: 20, used: Decimal(string: "8.45") ?? 0),
                    key(5134, "批量任务", 22, mask: "sk-…b4N6", usedAgo: 5_400),
                    key(5133, "旧版脚本", 6, mask: "sk-…7Lw0", effective: "expired", usedAgo: 9 * 86_400, expiresAt: now.addingTimeInterval(-2 * 86_400)),
                    key(5132, "未命名", 26, mask: "sk-…n0U5", usedAgo: nil, embedsUser: false),
                    key(5131, "&lt;脚本&gt; &amp; 工具", 1, mask: "sk-…s3T1", status: "inactive", effective: "inactive", usedAgo: 20 * 86_400)]
        case 3:
            return [key(5320, "停用的集成", 4, mask: "sk-…d2X0", status: "inactive", effective: "inactive", usedAgo: 4 * 86_400)]
        case 4:
            return [key(5406, "企业网关", 10, mask: "sk-…g6E4", effective: "quota_exhausted", usedAgo: 600, quota: 50, used: 50)]
        default:
            return []
        }
    }
}

/// One records page's reads under the `…-failure-after-first` arguments (each page makes its own source).
@MainActor private final class RecordReads {
    private let arguments: [String]
    private var counts: [String: Int] = [:]

    init(arguments: [String]) { self.arguments = arguments }

    /// Counts a read under `argument` when it is on; the second answers 502.
    func failsSecond(_ argument: String) -> Bool {
        guard arguments.contains(argument) else { return false }
        counts[argument, default: 0] += 1
        return counts[argument] == 2
    }
}

extension GroupRecordsSource {
    /// `-ui-testing` reads GroupFixtures+Records, otherwise the session's client with its masked view. Either way the group itself
    /// comes through GroupStore.fetch (S5D2a-10); a 404 drops it from the list and the directory before the page hears of it.
    @MainActor static func make(_ app: AppModel, session: SessionContext) -> GroupRecordsSource {
        let group: @MainActor @Sendable (_ id: Int) async throws -> AdminGroup = { [weak app] id in
            guard let store = app?.groupStore else { throw CancellationError() }
            do {
                return try await store.fetch(id: id)
            } catch let error as APIError {
                if GroupErrorCopy.resolve(error, context: .read).action == .treatAsDeleted { store.remove(id: id) }
                throw error
            }
        }
        guard app.isUITesting else { return .live(client: session.client, maskedView: session.has(.apiKeysMaskedView), group: group) }
        return GroupFixtures.recordsSource(app, session: session, group: group)
    }
}
