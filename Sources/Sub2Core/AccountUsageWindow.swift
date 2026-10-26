import Foundation

/// `GET admin/accounts/:id/usage?source=passive` (20 §2.2): the 5-hour window estimated from the last session, without
/// calling upstream. Only the 5-hour row is read; the capacity section shows nothing else from this reply.
public struct AccountUsageWindow: Decodable, Sendable, Equatable {
    public struct Progress: Decodable, Sendable, Equatable {
        /// A percentage, 0–100 and above.
        public let utilization: Double
        public let resetsAt: Date?
        public let remainingSeconds: Int?
        /// `utilization ÷ 100`; may exceed 1, the bar clamps it.
        public var ratio: Double { utilization / 100 }
        public init(utilization: Double, resetsAt: Date? = nil, remainingSeconds: Int? = nil) {
            self.utilization = utilization; self.resetsAt = resetsAt; self.remainingSeconds = remainingSeconds
        }
        enum CodingKeys: String, CodingKey { case utilization; case resetsAt = "resets_at", remainingSeconds = "remaining_seconds" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(utilization: c.decode(Double.self, forKey: .utilization), resetsAt: c.optionalTimestamp(.resetsAt),
                          remainingSeconds: try? c.decodeIfPresent(Int.self, forKey: .remainingSeconds))
        }
    }
    /// nil when `five_hour` is null (no session window yet), missing or unreadable: the row is not drawn.
    public let fiveHour: Progress?
    public init(fiveHour: Progress?) { self.fiveHour = fiveHour }
    enum CodingKeys: String, CodingKey { case fiveHour = "five_hour" }
    public init(from decoder: any Decoder) throws {
        fiveHour = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Progress.self, forKey: .fiveHour)
    }

    /// The backend serves passive usage only to Anthropic OAuth / Setup Token accounts (IsAnthropicOAuthOrSetupToken) and answers
    /// others with a 500, so callers check this before asking.
    public static func applies(to account: UpstreamAccount) -> Bool { applies(platform: account.platform, type: account.type) }
    public static func applies(platform: String, type: String) -> Bool { platform == "anthropic" && (type == "oauth" || type == "setup-token") }
}

extension APIClient {
    /// `source=passive` is always sent: the server's default (active) may call upstream.
    public func accountPassiveUsage(id: Int) async throws -> AccountUsageWindow {
        try await request("admin/accounts/\(validID(id))/usage", query: [URLQueryItem(name: "source", value: "passive")])
    }
}
