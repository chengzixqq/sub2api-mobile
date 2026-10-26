import Foundation

/// `POST /admin/accounts/check-mixed-channel` (20 §3.2), the pre-check for a server without `accounts.mixed_channel_details`.
/// The reply's `error` / `message` are never read (R11).
public struct MixedChannelCheck: Decodable, Sendable, Equatable {
    public struct Details: Decodable, Sendable, Equatable {
        public let groupID: Int?
        public let groupName: String
        public let currentPlatform: String
        public let otherPlatform: String
        public init(groupID: Int?, groupName: String, currentPlatform: String, otherPlatform: String) {
            self.groupID = groupID; self.groupName = groupName; self.currentPlatform = currentPlatform; self.otherPlatform = otherPlatform
        }
        enum CodingKeys: String, CodingKey {
            case groupID = "group_id", groupName = "group_name", currentPlatform = "current_platform", otherPlatform = "other_platform"
        }
    }
    public let hasRisk: Bool
    /// Only with a risk; a malformed one reads as nil.
    public let details: Details?
    public init(hasRisk: Bool, details: Details? = nil) { self.hasRisk = hasRisk; self.details = details }
    enum CodingKeys: String, CodingKey { case hasRisk = "has_risk", details }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasRisk = (try? c.decodeIfPresent(Bool.self, forKey: .hasRisk)) ?? false
        let decoded = try? c.decodeIfPresent(Details.self, forKey: .details)
        details = hasRisk ? decoded : nil
    }
}

/// 20 §0.4-7: the group whose accounts would mix Anthropic and Antigravity, from a 409 MIXED_CHANNEL_WARNING (create, PUT, PATCH,
/// bulk-update) or from the pre-check. `message` is the Web confirmation; the server's own text is never shown.
public struct MixedChannelWarning: Sendable, Equatable {
    public let groupID: Int?
    public let groupName: String
    public let currentPlatform: String
    public let otherPlatform: String
    public init(groupID: Int?, groupName: String, currentPlatform: String, otherPlatform: String) {
        self.groupID = groupID; self.groupName = groupName; self.currentPlatform = currentPlatform; self.otherPlatform = otherPlatform
    }
    /// The 409's string metadata (the `details` object does not survive ErrorEnvelope). nil for any other reply, including an older
    /// server's 409 without reason or metadata: ask check-mixed-channel then.
    public init?(error: APIError) {
        guard error.statusCode == 409, error.reason == AccountWriteReason.mixedChannelWarning else { return nil }
        let names = ["group_name", "current_platform", "other_platform"].map { error.metadata[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard !names.contains(where: \.isEmpty) else { return nil }
        let groupID = error.metadata["group_id"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.init(groupID: groupID, groupName: names[0], currentPlatform: names[1], otherPlatform: names[2])
    }
    public init?(check: MixedChannelCheck) {
        guard check.hasRisk, let details = check.details else { return nil }
        self.init(groupID: details.groupID, groupName: details.groupName, currentPlatform: details.currentPlatform, otherPlatform: details.otherPlatform)
    }
    public var message: String {
        "警告：分组“\(groupName)”中同时包含 \(currentPlatform) 和 \(otherPlatform) 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？"
    }
}

extension APIClient {
    /// No group means no risk, so nothing is sent (the server answers the same). Without side effects but off the read list of
    /// 00 §2.4, so it goes out once like any unkeyed POST.
    public func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?) async throws -> MixedChannelCheck {
        let platform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty, groupIDs.allSatisfy({ $0 > 0 }), (accountID ?? 1) > 0 else {
            throw APIError(kind: .validation, message: "混合渠道检查的平台或分组无效。")
        }
        guard !groupIDs.isEmpty else { return MixedChannelCheck(hasRisk: false) }
        return try await request("admin/accounts/check-mixed-channel", method: "POST",
                                 body: encode(MixedChannelCheckBody(accountID: accountID, groupIDs: groupIDs, platform: platform)))
    }
}

private struct MixedChannelCheckBody: Encodable {
    let accountID: Int?
    let groupIDs: [Int]
    let platform: String
    enum CodingKeys: String, CodingKey { case accountID = "account_id", groupIDs = "group_ids", platform }
}
