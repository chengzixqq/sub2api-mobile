import Foundation

/// `POST admin/accounts/today-stats/batch` merged over its 200-id requests (20 §1.2, 00 §4.5).
/// `stats` holds only requested accounts that did not fail: the 0 the server fills in for a failed one is a placeholder
/// (00 §6.5), so a missing entry always reads as “—” and callers never need `failedIDs` for that.
public struct AccountTodayStatsBatch: Sendable {
    public let stats: [Int: AccountTodayStats]
    /// `failed_account_ids` matched as a set against the request, plus every id of a 503 ACCOUNT_STATS_UNAVAILABLE request.
    public let failedIDs: Set<Int>
    public let degraded: Bool
    /// The `group_id` every answered request echoed (X23). An old server ignores the filter silently and echoes nothing,
    /// so nil means the numbers are site-wide.
    public let groupID: Int?
    public init(stats: [Int: AccountTodayStats] = [:], failedIDs: Set<Int> = [], degraded: Bool = false, groupID: Int? = nil) {
        self.stats = stats; self.failedIDs = failedIDs; self.degraded = degraded; self.groupID = groupID
    }
    public static let empty = AccountTodayStatsBatch()
}

/// 00 §4.5: ids go out positive, unique and ascending, at most 200 per request; replies are matched by id, never by order.
enum AccountBatchIDs {
    static let maxPerRequest = 200
    static func normalized(_ ids: [Int]) -> [Int] { Array(Set(ids.filter { $0 > 0 })).sorted() }
    static func batches(_ ids: [Int], size: Int = maxPerRequest) -> [[Int]] {
        let step = max(size, 1)
        return stride(from: 0, to: ids.count, by: step).map { Array(ids[$0..<min($0 + step, ids.count)]) }
    }
    /// A reply map keyed by id strings, restricted to `requested`; a key that is not a number is dropped.
    static func matched<Value>(_ raw: [String: Value], requested: Set<Int>) -> [Int: Value] {
        let pairs = raw.compactMap { key, value -> (Int, Value)? in
            guard let id = Int(key), requested.contains(id) else { return nil }
            return (id, value)
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

/// C-21's name for `Lossy` (Models.swift): one entry that fails to decode reads as nil instead of failing the reply.
/// The account batch reads use it, and S2-21's bare-array replies reuse it.
typealias LenientDecoded<Value: Decodable> = Lossy<Value>

extension APIClient {
    /// Requests go one after another (.readBatch: retried like a read, conditional per 00 §4.2). A 503 ACCOUNT_STATS_UNAVAILABLE
    /// marks that request's ids failed; any other error fails the whole call. `group_id` is sent only when positive, and whether the
    /// site supports it (`accounts.today_stats_group`) is the caller's check.
    public func accountTodayStatsBatch(ids: [Int], groupID: Int? = nil) async throws -> AccountTodayStatsBatch {
        let group = groupID.flatMap { $0 > 0 ? $0 : nil }
        var parts = [TodayStatsPart]()
        for chunk in AccountBatchIDs.batches(AccountBatchIDs.normalized(ids)) {
            parts.append(TodayStatsPart(requested: Set(chunk), reply: try await todayStatsChunk(chunk, groupID: group)))
        }
        return AccountTodayStatsBatch(merging: parts)
    }
    /// nil for a 503 ACCOUNT_STATS_UNAVAILABLE, which carries its own reason and so is never retried automatically.
    private func todayStatsChunk(_ ids: [Int], groupID: Int?) async throws -> TodayStatsReply? {
        do {
            let reply: TodayStatsReply = try await request("admin/accounts/today-stats/batch", method: "POST",
                                                           body: encode(TodayStatsBody(accountIDs: ids, groupID: groupID)), requestClass: .readBatch)
            return reply
        } catch let error as APIError where error.category == .statsUnavailable {
            return nil
        }
    }
}

/// sortedKeys bytes (`encode`), so the ConditionalCache key of an unchanged request stays the same.
private struct TodayStatsBody: Encodable {
    let accountIDs: [Int]
    let groupID: Int?
    enum CodingKeys: String, CodingKey { case accountIDs = "account_ids", groupID = "group_id" }
}

/// Every field may be missing on an older server (`accounts.today_stats_failures`, `accounts.today_stats_group`).
private struct TodayStatsReply: Decodable, Sendable {
    let stats: [String: AccountTodayStats]
    let failedIDs: Set<Int>
    let degraded: Bool
    let groupID: Int?
    enum CodingKeys: String, CodingKey { case stats, degraded; case failedIDs = "failed_account_ids", groupID = "group_id" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: LenientDecoded<AccountTodayStats>].self, forKey: .stats)) ?? [:]
        stats = raw.compactMapValues(\.value)
        failedIDs = Set((try? c.decodeIfPresent([Int].self, forKey: .failedIDs)) ?? [])
        degraded = (try? c.decodeIfPresent(Bool.self, forKey: .degraded)) ?? false
        groupID = try? c.decodeIfPresent(Int.self, forKey: .groupID)
    }
}

private struct TodayStatsPart {
    let requested: Set<Int>
    let reply: TodayStatsReply?
}

private extension AccountTodayStatsBatch {
    init(merging parts: [TodayStatsPart]) {
        var stats = [Int: AccountTodayStats](), failed = Set<Int>()
        for part in parts {
            let failedHere = part.reply.map { $0.failedIDs.intersection(part.requested) } ?? part.requested
            failed.formUnion(failedHere)
            let answered = AccountBatchIDs.matched(part.reply?.stats ?? [:], requested: part.requested)
            stats.merge(answered.filter { !failedHere.contains($0.key) }) { _, latest in latest }
        }
        let replies = parts.compactMap(\.reply)
        let echoes = Set(replies.map(\.groupID))
        self.init(stats: stats, failedIDs: failed, degraded: replies.contains { $0.degraded },
                  groupID: echoes.count == 1 ? echoes.first.flatMap { $0 } : nil)
    }
}
