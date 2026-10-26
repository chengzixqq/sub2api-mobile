import Foundation

/// `POST /admin/push/devices` (00 §7.2, 60 §7.2). The APNs token, device key, topic, secret and endpoint stay private: they
/// are never printed, reflected or decoded back, and nothing here is stored. `subscription` is never sent, so registering
/// again keeps the one the administrator chose. Every platform sends `locale` and `timezone`: the backend writes Chinese only
/// for a `zh` locale and reads quiet hours in the target's zone (UTC without one).
public struct PushDeviceRegistration: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let locale = "zh-Hans"
    public static let defaultBarkEndpoint = "https://api.day.app"
    public static let defaultNtfyEndpoint = "https://ntfy.sh"
    public let platform: PushPlatform
    public let bundleID: String?
    /// nil or "sandbox": nil follows the site's `apns_environment`; "production" is never sent.
    public let environment: String?
    public let deviceName: String?
    public let timezone: String?
    /// iOS only: the site's `ServerProfile.id.uuidString`, which routes a tapped notification (U47).
    public let siteTag: String?
    private let apnsToken: String?
    private let endpoint: String?
    private let token: String?
    private let secret: String?

    /// `deviceToken` of `didRegisterForRemoteNotificationsWithDeviceToken`, two lowercase digits per byte.
    public static func apnsTokenHex(_ deviceToken: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        return String(decoding: deviceToken.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] }, as: UTF8.self)
    }
    /// `sandbox` only for a build with the development `aps-environment` (S6-23's APNS_SANDBOX).
    public static func ios(apnsToken: String, bundleID: String?, deviceName: String, timezone: String, siteID: UUID, sandbox: Bool) -> Self {
        Self(platform: .ios, bundleID: nonBlank(bundleID), environment: sandbox ? PushAPNsEnvironment.sandbox.rawValue : nil,
             deviceName: nonBlank(deviceName), timezone: nonBlank(timezone), siteTag: siteID.uuidString,
             apnsToken: nonBlank(apnsToken)?.lowercased(), endpoint: nil, token: nil, secret: nil)
    }
    /// `token` is the Bark device key; Bark has no secret.
    public static func bark(endpoint: String = PushDeviceRegistration.defaultBarkEndpoint, deviceKey: String, deviceName: String, timezone: String) -> Self {
        target(.bark, endpoint: endpoint, token: deviceKey, secret: nil, deviceName: deviceName, timezone: timezone)
    }
    /// `token` is the topic; `accessToken` the optional ntfy access token.
    public static func ntfy(endpoint: String = PushDeviceRegistration.defaultNtfyEndpoint, topic: String, accessToken: String?, deviceName: String,
                            timezone: String) -> Self {
        target(.ntfy, endpoint: endpoint, token: topic, secret: accessToken, deviceName: deviceName, timezone: timezone)
    }
    /// `secret` signs each request (`X-Sub2-Signature`).
    public static func webhook(endpoint: String, secret: String?, deviceName: String, timezone: String) -> Self {
        target(.webhook, endpoint: endpoint, token: nil, secret: secret, deviceName: deviceName, timezone: timezone)
    }

    public var hasSecret: Bool { secret != nil }
    /// The minimum a request needs; the add-target form checks the details first (S6-25).
    public func validate() throws {
        let isComplete = switch platform {
        case .ios: apnsToken.map(Self.isAPNsToken) ?? false
        case .bark, .ntfy: endpoint != nil && token != nil
        case .webhook: endpoint != nil
        }
        guard isComplete else { throw APIError(kind: .validation, message: "推送接收方式的信息不完整。") }
    }

    enum CodingKeys: String, CodingKey {
        case platform, environment, endpoint, token, secret, locale, timezone
        case apnsToken = "apns_token", bundleID = "bundle_id", deviceName = "device_name", siteTag = "site_tag"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(platform, forKey: .platform)
        try c.encodeIfPresent(apnsToken, forKey: .apnsToken); try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encodeIfPresent(environment, forKey: .environment); try c.encodeIfPresent(siteTag, forKey: .siteTag)
        try c.encodeIfPresent(endpoint, forKey: .endpoint); try c.encodeIfPresent(token, forKey: .token); try c.encodeIfPresent(secret, forKey: .secret)
        try c.encodeIfPresent(deviceName, forKey: .deviceName); try c.encode(Self.locale, forKey: .locale)
        try c.encodeIfPresent(timezone, forKey: .timezone)
    }
    public var description: String { "PushDeviceRegistration(\(platform.rawValue), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["platform": platform, "hasEndpoint": endpoint != nil, "hasSecret": hasSecret], displayStyle: .struct)
    }

    private static func target(_ platform: PushPlatform, endpoint: String, token: String?, secret: String?, deviceName: String, timezone: String) -> Self {
        Self(platform: platform, bundleID: nil, environment: nil, deviceName: nonBlank(deviceName), timezone: nonBlank(timezone), siteTag: nil,
             apnsToken: nil, endpoint: nonBlank(endpoint), token: nonBlank(token), secret: nonBlank(secret))
    }
    /// Backend `^[0-9a-f]{64,200}$`.
    private static func isAPNsToken(_ token: String) -> Bool {
        (64...200).contains(token.utf8.count) && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// `PUT /admin/push/config` with only the changed fields (60 §7.4). A private key left empty is not sent, which keeps the
/// site's; the key is never printed, reflected or decoded back.
public struct PushAPNsConfigUpdate: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let enabled: Bool?
    public let teamID: String?
    public let keyID: String?
    public let topic: String?
    public let environment: PushAPNsEnvironment?
    private let privateKey: String?

    public init(enabled: Bool? = nil, teamID: String? = nil, keyID: String? = nil, privateKey: String? = nil, topic: String? = nil,
                environment: PushAPNsEnvironment? = nil) {
        self.enabled = enabled; self.teamID = teamID; self.keyID = keyID; self.topic = topic; self.environment = environment
        self.privateKey = nonBlank(privateKey) == nil ? nil : privateKey
    }
    /// The form against what was loaded. Team ID and Key ID compare trimmed and upper-cased, as the backend stores them, and
    /// Topic trimmed; a missing value is empty, and clearing one sends "".
    public init(changesFrom current: PushAPNsConfig, enabled: Bool, teamID: String, keyID: String, privateKey: String?, topic: String,
                environment: PushAPNsEnvironment) {
        let team = Self.identifier(teamID), key = Self.identifier(keyID), newTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(enabled: enabled == current.enabled ? nil : enabled,
                  teamID: team == Self.identifier(current.teamID ?? "") ? nil : team,
                  keyID: key == Self.identifier(current.keyID ?? "") ? nil : key,
                  privateKey: privateKey, topic: newTopic == (current.topic ?? "") ? nil : newTopic,
                  environment: environment == current.environment ? nil : environment)
    }
    public var isEmpty: Bool { enabled == nil && teamID == nil && keyID == nil && privateKey == nil && topic == nil && environment == nil }
    public var includesPrivateKey: Bool { privateKey != nil }

    enum CodingKeys: String, CodingKey {
        case enabled = "apns_enabled", teamID = "apns_team_id", keyID = "apns_key_id", privateKey = "apns_private_key"
        case topic = "apns_topic", environment = "apns_environment"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled); try c.encodeIfPresent(teamID, forKey: .teamID)
        try c.encodeIfPresent(keyID, forKey: .keyID); try c.encodeIfPresent(privateKey, forKey: .privateKey)
        try c.encodeIfPresent(topic, forKey: .topic); try c.encodeIfPresent(environment, forKey: .environment)
    }
    public var description: String { "PushAPNsConfigUpdate(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["enabled": enabled as Any, "teamID": teamID as Any, "keyID": keyID as Any, "topic": topic as Any,
                                "environment": environment as Any, "includesPrivateKey": includesPrivateKey], displayStyle: .struct)
    }

    private static func identifier(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
}

private func nonBlank(_ text: String?) -> String? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    return text
}
