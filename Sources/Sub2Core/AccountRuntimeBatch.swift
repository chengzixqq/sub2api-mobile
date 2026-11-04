import Foundation

/// One `runtime/batch` item (20 §1.2). A counter the server could not read is nil, never 0: concurrency comes back null with
/// `concurrency_available` false, the other counters are omitted (also when they do not apply to the account).
public struct AccountRuntime: Decodable, Sendable, Equatable {
    public let status: String
    public let schedulable: Bool
    public let currentConcurrency: Int?
    public let probeConcurrency: Int?
    public let concurrencyAvailable: Bool
    public let currentRPM: Int?
    public let schedulingRPM: Int?
    public let activeSessions: Int?
    /// Only sent with `includeWindowCost`.
    public let currentWindowCost: Decimal?
    public let rateLimitResetAt: Date?
    public let overloadUntil: Date?
    public let tempUnschedulableUntil: Date?

    /// `concurrencyAvailable` nil means “whether a concurrency was reported”, as for an item that omits the flag.
    public init(status: String, schedulable: Bool, currentConcurrency: Int? = nil, probeConcurrency: Int? = nil, concurrencyAvailable: Bool? = nil,
                currentRPM: Int? = nil, schedulingRPM: Int? = nil, activeSessions: Int? = nil, currentWindowCost: Decimal? = nil,
                rateLimitResetAt: Date? = nil, overloadUntil: Date? = nil, tempUnschedulableUntil: Date? = nil) {
        self.status = status; self.schedulable = schedulable; self.currentConcurrency = currentConcurrency
        self.probeConcurrency = probeConcurrency; self.concurrencyAvailable = concurrencyAvailable ?? (currentConcurrency != nil)
        self.currentRPM = currentRPM; self.schedulingRPM = schedulingRPM; self.activeSessions = activeSessions
        self.currentWindowCost = currentWindowCost; self.rateLimitResetAt = rateLimitResetAt; self.overloadUntil = overloadUntil
        self.tempUnschedulableUntil = tempUnschedulableUntil
    }
    enum CodingKeys: String, CodingKey {
        case status, schedulable
        case currentConcurrency = "current_concurrency", probeConcurrency = "probe_concurrency", concurrencyAvailable = "concurrency_available"
        case currentRPM = "current_rpm", schedulingRPM = "scheduling_rpm", activeSessions = "active_sessions", currentWindowCost = "current_window_cost"
        case rateLimitResetAt = "rate_limit_reset_at", overloadUntil = "overload_until", tempUnschedulableUntil = "temp_unschedulable_until"
    }
    /// `status` and `schedulable` are required; an item without them is dropped by the batch read.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        try self.init(status: c.decode(String.self, forKey: .status), schedulable: c.decode(Bool.self, forKey: .schedulable),
                      currentConcurrency: count(.currentConcurrency), probeConcurrency: count(.probeConcurrency),
                      concurrencyAvailable: try? c.decodeIfPresent(Bool.self, forKey: .concurrencyAvailable),
                      currentRPM: count(.currentRPM), schedulingRPM: count(.schedulingRPM), activeSessions: count(.activeSessions),
                      currentWindowCost: try? c.optionalDecimal(.currentWindowCost),
                      rateLimitResetAt: c.optionalTimestamp(.rateLimitResetAt), overloadUntil: c.optionalTimestamp(.overloadUntil),
                      tempUnschedulableUntil: c.optionalTimestamp(.tempUnschedulableUntil))
    }
}

extension APIClient {
    /// 20 §1.2 light refresh: at most 200 ids per request, sent in order. Out-of-scope and deleted ids are simply absent (the
    /// server does not probe existence). `include_window_cost=0` unless asked: the server would run one database aggregate per
    /// capped Anthropic token account, and no new screen shows the window cost. Each reply's `sampled_at` becomes the site's
    /// clock base (00 §6.3), so countdowns compare `*_until` against `serverClock.now()`.
    public func accountRuntime(ids: [Int], includeWindowCost: Bool = false) async throws -> [Int: AccountRuntime] {
        var merged = [Int: AccountRuntime]()
        for chunk in AccountBatchIDs.batches(AccountBatchIDs.normalized(ids)) {
            let part = try await runtimeChunk(chunk, includeWindowCost: includeWindowCost, splitsOnLimit: true)
            merged.merge(part) { _, latest in latest }
        }
        return merged
    }
    /// 00 §4.5: a TOO_MANY_IDS (the server lowered its limit below ours) splits this request once by `metadata.max`.
    private func runtimeChunk(_ ids: [Int], includeWindowCost: Bool, splitsOnLimit: Bool) async throws -> [Int: AccountRuntime] {
        do {
            let reply: RuntimeBatchReply = try await request("admin/accounts/runtime/batch", method: "POST",
                                                             query: includeWindowCost ? [] : [URLQueryItem(name: "include_window_cost", value: "0")],
                                                             body: encode(["account_ids": ids]), requestClass: .readBatch)
            if let sampledAt = reply.sampledAt { serverClock.record(sampledAt: sampledAt, receivedAt: serverClock.localNow()) }
            return AccountBatchIDs.matched(reply.items, requested: Set(ids))
        } catch let error as APIError where splitsOnLimit && error.category == .batchLimit {
            guard let limit = error.metadata["max"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), limit > 0, limit < ids.count else { throw error }
            var merged = [Int: AccountRuntime]()
            for part in AccountBatchIDs.batches(ids, size: limit) {
                let smaller = try await runtimeChunk(part, includeWindowCost: includeWindowCost, splitsOnLimit: false)
                merged.merge(smaller) { _, latest in latest }
            }
            return merged
        }
    }
}

/// `{sampled_at, items: {"<id>": item}}`; an item that does not decode reads as absent.
private struct RuntimeBatchReply: Decodable, Sendable {
    let sampledAt: Date?
    let items: [String: AccountRuntime]
    enum CodingKeys: String, CodingKey { case items; case sampledAt = "sampled_at" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sampledAt = try c.optionalTimestamp(.sampledAt)
        items = ((try? c.decodeIfPresent([String: LenientDecoded<AccountRuntime>].self, forKey: .items)) ?? [:]).compactMapValues(\.value)
    }
}
