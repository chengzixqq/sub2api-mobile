import Foundation

// Push targets, their subscriptions and the site's APNs settings (60 §7.2, 00 §7.2–§7.4). The request bodies that carry
// secrets, `PushDeviceRegistration` and `PushAPNsConfigUpdate`, are in PushRequests.swift; the wording in PushPresentation.swift.

public enum PushPlatform: String, CaseIterable, Sendable, Codable {
    case ios, bark, ntfy, webhook
}

/// The four events a target can subscribe to, in the backend's order; `push.test` is not one of them.
public enum PushEvent: String, CaseIterable, Sendable, Codable {
    case opsAlertFired = "ops_alert.fired", opsAlertResolved = "ops_alert.resolved"
    case accountError = "account.error", accountTestFinished = "account.test_finished"
}

/// The lowest alert level pushed; P0 is the most severe. It only applies to `ops_alert.*`.
public enum PushSeverity: String, CaseIterable, Sendable, Codable {
    case p0 = "P0", p1 = "P1", p2 = "P2", p3 = "P3"
    public static let `default`: PushSeverity = .p1
}

/// A daily window in the target's `timezone` (UTC when it has none). It may cross midnight; equal ends mean no window.
public struct PushQuietHours: Codable, Sendable, Equatable {
    public static let minutesPerDay = 1_440
    public let startMinute: Int
    public let endMinute: Int
    public var start: String { Self.format(startMinute) }
    public var end: String { Self.format(endMinute) }
    public var isEffective: Bool { startMinute != endMinute }

    public init?(start: String, end: String) {
        guard let start = Self.minuteOfDay(start), let end = Self.minuteOfDay(end) else { return nil }
        startMinute = start; endMinute = end
    }
    public init?(startMinute: Int, endMinute: Int) {
        guard Self.isMinuteOfDay(startMinute), Self.isMinuteOfDay(endMinute) else { return nil }
        self.startMinute = startMinute; self.endMinute = endMinute
    }
    /// "HH:MM", two ASCII digits each (backend `pushClockPattern`); surrounding whitespace is ignored.
    public static func minuteOfDay(_ clock: String) -> Int? {
        let bytes = Array(clock.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count == 5, bytes[2] == UInt8(ascii: ":") else { return nil }
        let digits = [bytes[0], bytes[1], bytes[3], bytes[4]].map { Int($0) - 48 }
        guard digits.allSatisfy({ (0...9).contains($0) }) else { return nil }
        let hour = digits[0] * 10 + digits[1], minute = digits[2] * 10 + digits[3]
        return hour < 24 && minute < 60 ? hour * 60 + minute : nil
    }
    public static func clock(minuteOfDay minute: Int) -> String? { isMinuteOfDay(minute) ? format(minute) : nil }

    enum CodingKeys: String, CodingKey { case start, end }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = Self.minuteOfDay(try c.decode(String.self, forKey: .start)),
              let end = Self.minuteOfDay(try c.decode(String.self, forKey: .end)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "quiet_hours must be HH:MM"))
        }
        startMinute = start; endMinute = end
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
    }
    private static func isMinuteOfDay(_ minute: Int) -> Bool { (0..<minutesPerDay).contains(minute) }
    private static func format(_ minute: Int) -> String { pad(minute / 60) + ":" + pad(minute % 60) }
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}

/// `PUT …/subscription` replaces the whole object (00 §7.3). No events pauses the target; no groups or platforms means all,
/// and both only filter events that carry a group or a platform.
public struct PushSubscription: Codable, Sendable, Equatable {
    public static let maxGroupIDs = 100
    public static let maxPlatforms = 20
    /// Backend `DefaultPushSubscription`, which a target gets when it registers without one.
    public static let `default` = PushSubscription(events: [.opsAlertFired, .accountError])
    public var events: [PushEvent]
    public var minSeverity: PushSeverity
    public var groupIDs: [Int]
    public var platforms: [String]
    public var quietHours: PushQuietHours?

    public init(events: [PushEvent], minSeverity: PushSeverity = .default, groupIDs: [Int] = [], platforms: [String] = [],
                quietHours: PushQuietHours? = nil) {
        self.events = events; self.minSeverity = minSeverity; self.groupIDs = groupIDs; self.platforms = platforms; self.quietHours = quietHours
    }
    public var isPaused: Bool { events.isEmpty }
    /// What the backend stores: events in their order, ids and platform keys deduplicated and sorted, an empty window dropped.
    public var normalized: PushSubscription {
        PushSubscription(events: PushEvent.allCases.filter(events.contains), minSeverity: minSeverity, groupIDs: Array(Set(groupIDs)).sorted(),
                         platforms: Array(Set(platforms.compactMap(Self.platformKey))).sorted(),
                         quietHours: quietHours?.isEffective == true ? quietHours : nil)
    }
    /// The backend's limits, checked before sending.
    public func validate() throws {
        let value = normalized
        guard value.groupIDs.count <= Self.maxGroupIDs, value.groupIDs.allSatisfy({ $0 > 0 }),
              value.platforms.count <= Self.maxPlatforms, value.platforms.allSatisfy(Self.isPlatformKey) else {
            throw APIError(kind: .validation, message: "推送订阅超出范围。")
        }
    }

    enum CodingKeys: String, CodingKey {
        case events, platforms
        case minSeverity = "min_severity", groupIDs = "group_ids", quietHours = "quiet_hours"
    }
    /// All five keys, normalized; no window is an explicit null.
    public func encode(to encoder: any Encoder) throws {
        let value = normalized
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value.events, forKey: .events); try c.encode(value.minSeverity, forKey: .minSeverity)
        try c.encode(value.groupIDs, forKey: .groupIDs); try c.encode(value.platforms, forKey: .platforms)
        if let quietHours = value.quietHours { try c.encode(quietHours, forKey: .quietHours) } else { try c.encodeNil(forKey: .quietHours) }
    }
    /// Missing or null `events` is the default set, as on the backend; unknown events and unreadable entries are dropped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decodeIfPresent([Lossy<String>].self, forKey: .events) {
            events = raw.compactMap { $0.value.flatMap(PushEvent.init(rawValue:)) }
        } else {
            events = Self.default.events
        }
        let severity = try? c.decodeIfPresent(String.self, forKey: .minSeverity)
        minSeverity = severity.flatMap { PushSeverity(rawValue: $0.trimmingCharacters(in: .whitespaces).uppercased()) } ?? .default
        groupIDs = c.lossyList(Int.self, .groupIDs)
        platforms = c.lossyList(String.self, .platforms)
        quietHours = try? c.decodeIfPresent(PushQuietHours.self, forKey: .quietHours)
    }

    private static func platformKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }
    /// Backend `^[a-z0-9_-]{1,32}$`.
    private static func isPlatformKey(_ key: String) -> Bool {
        (1...32).contains(key.utf8.count) && key.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}

/// Why the backend stopped sending to a target; registering again or a successful test clears it.
public enum PushDisabledReason: Sendable, Equatable {
    case unregistered, badDeviceToken, topicMismatch, endpointGone, secretUndecryptable, other(String)

    /// nil for a missing or blank value.
    public init?(rawValue: String?) {
        guard let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw {
        case "unregistered": self = .unregistered
        case "bad_device_token": self = .badDeviceToken
        case "topic_mismatch": self = .topicMismatch
        case "endpoint_gone": self = .endpointGone
        case "secret_undecryptable": self = .secretUndecryptable
        default: self = .other(raw)
        }
    }
    public var rawValue: String {
        switch self {
        case .unregistered: "unregistered"
        case .badDeviceToken: "bad_device_token"
        case .topicMismatch: "topic_mismatch"
        case .endpointGone: "endpoint_gone"
        case .secretUndecryptable: "secret_undecryptable"
        case .other(let value): value
        }
    }
}

/// One of the caller's push targets (60 §7.2). The server never returns a token, secret or full endpoint.
public struct PushDevice: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    /// nil for a platform this App does not know; `rawPlatform` keeps it.
    public let platform: PushPlatform?
    public let rawPlatform: String?
    /// The token's or device key's last four characters.
    public let tokenHint: String?
    public let endpointHost: String?
    public let bundleID: String?
    /// nil follows the site's `apns_environment`.
    public let environment: String?
    public let deviceName: String?
    public let locale: String?
    public let timezone: String?
    public let siteTag: String?
    public let enabled: Bool
    public let disabledReason: PushDisabledReason?
    public let disabledAt: Date?
    public let lastSuccessAt: Date?
    public let lastError: String?
    public let lastErrorAt: Date?
    public let credentialsEncrypted: Bool?
    /// nil when missing or unreadable; `effectiveSubscription` then reads the default.
    public let subscription: PushSubscription?
    public let createdAt: Date?
    public let updatedAt: Date?
    public var effectiveSubscription: PushSubscription { subscription ?? .default }

    public init(id: Int, platform: PushPlatform?, rawPlatform: String? = nil, tokenHint: String? = nil, endpointHost: String? = nil,
                bundleID: String? = nil, environment: String? = nil, deviceName: String? = nil, locale: String? = nil, timezone: String? = nil,
                siteTag: String? = nil, enabled: Bool = true, disabledReason: PushDisabledReason? = nil, disabledAt: Date? = nil,
                lastSuccessAt: Date? = nil, lastError: String? = nil, lastErrorAt: Date? = nil, credentialsEncrypted: Bool? = nil,
                subscription: PushSubscription? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.platform = platform; self.rawPlatform = rawPlatform ?? platform?.rawValue; self.tokenHint = tokenHint
        self.endpointHost = endpointHost; self.bundleID = bundleID; self.environment = environment; self.deviceName = deviceName
        self.locale = locale; self.timezone = timezone; self.siteTag = siteTag; self.enabled = enabled; self.disabledReason = disabledReason
        self.disabledAt = disabledAt; self.lastSuccessAt = lastSuccessAt; self.lastError = lastError; self.lastErrorAt = lastErrorAt
        self.credentialsEncrypted = credentialsEncrypted; self.subscription = subscription; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, platform, environment, locale, timezone, enabled, subscription
        case tokenHint = "token_hint", endpointHost = "endpoint_host", bundleID = "bundle_id", deviceName = "device_name", siteTag = "site_tag"
        case disabledReason = "disabled_reason", disabledAt = "disabled_at", lastSuccessAt = "last_success_at", lastError = "last_error"
        case lastErrorAt = "last_error_at", credentialsEncrypted = "credentials_encrypted", createdAt = "created_at", updatedAt = "updated_at"
    }
    /// Only a positive `id` is required; every other field reads on its own, and a blank string is missing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try? c.decode(Int.self, forKey: .id), id > 0 else { throw APIError.invalidResponse }
        let platform = c.pushText(.platform), reason = PushDisabledReason(rawValue: c.pushText(.disabledReason))
        let enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        self.init(id: id, platform: platform.flatMap { PushPlatform(rawValue: $0.lowercased()) }, rawPlatform: platform,
                  tokenHint: c.pushText(.tokenHint), endpointHost: c.pushText(.endpointHost), bundleID: c.pushText(.bundleID),
                  environment: c.pushText(.environment), deviceName: c.pushText(.deviceName), locale: c.pushText(.locale),
                  timezone: c.pushText(.timezone), siteTag: c.pushText(.siteTag), enabled: enabled ?? (reason == nil), disabledReason: reason,
                  disabledAt: try? c.optionalTimestamp(.disabledAt), lastSuccessAt: try? c.optionalTimestamp(.lastSuccessAt),
                  lastError: c.pushText(.lastError), lastErrorAt: try? c.optionalTimestamp(.lastErrorAt),
                  credentialsEncrypted: try? c.decodeIfPresent(Bool.self, forKey: .credentialsEncrypted),
                  subscription: try? c.decodeIfPresent(PushSubscription.self, forKey: .subscription),
                  createdAt: try? c.optionalTimestamp(.createdAt), updatedAt: try? c.optionalTimestamp(.updatedAt))
    }
}

/// `POST …/test` → `{delivered, provider_status}`; a 2xx reply was delivered.
public struct PushTestResult: Decodable, Sendable, Equatable {
    public let delivered: Bool
    public let providerStatus: Int?
    public init(delivered: Bool, providerStatus: Int?) { self.delivered = delivered; self.providerStatus = providerStatus }
    enum CodingKeys: String, CodingKey { case delivered, providerStatus = "provider_status" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let delivered = try? c.decodeIfPresent(Bool.self, forKey: .delivered)
        self.init(delivered: delivered ?? true, providerStatus: try? c.decodeIfPresent(Int.self, forKey: .providerStatus))
    }
}

public enum PushAPNsEnvironment: String, CaseIterable, Sendable, Codable {
    case production, sandbox
}

/// `GET /admin/push/config` (site owner only); the private key itself is never returned.
public struct PushAPNsConfig: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let teamID: String?
    public let keyID: String?
    public let privateKeyConfigured: Bool
    /// nil follows the App's bundle ID.
    public let topic: String?
    public let environment: PushAPNsEnvironment
    /// Without the site's fixed encryption key no private key can be saved.
    public let encryptionKeyConfigured: Bool
    /// Enabled, with Team ID, Key ID and a private key.
    public let ready: Bool

    public init(enabled: Bool = false, teamID: String? = nil, keyID: String? = nil, privateKeyConfigured: Bool = false, topic: String? = nil,
                environment: PushAPNsEnvironment = .production, encryptionKeyConfigured: Bool = false, ready: Bool = false) {
        self.enabled = enabled; self.teamID = teamID; self.keyID = keyID; self.privateKeyConfigured = privateKeyConfigured; self.topic = topic
        self.environment = environment; self.encryptionKeyConfigured = encryptionKeyConfigured; self.ready = ready
    }
    enum CodingKeys: String, CodingKey {
        case ready
        case enabled = "apns_enabled", teamID = "apns_team_id", keyID = "apns_key_id", privateKeyConfigured = "apns_private_key_configured"
        case topic = "apns_topic", environment = "apns_environment", encryptionKeyConfigured = "encryption_key_configured"
    }
    /// A missing flag is false; a missing or unknown environment is production, the backend's default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        self.init(enabled: flag(.enabled), teamID: c.pushText(.teamID), keyID: c.pushText(.keyID), privateKeyConfigured: flag(.privateKeyConfigured),
                  topic: c.pushText(.topic), environment: c.pushText(.environment).flatMap { PushAPNsEnvironment(rawValue: $0.lowercased()) } ?? .production,
                  encryptionKeyConfigured: flag(.encryptionKeyConfigured), ready: flag(.ready))
    }
}

extension APIClient {
    /// 00 §1.7.5 step 1, §7.6: done before signing out, because revoking a session does not remove its device.
    public func deletePushDevice(id: Int) async throws {
        let _: EmptyReply = try await request("admin/push/devices/\(validID(id))", method: "DELETE")
    }
    /// The caller's own targets in id order; an entry without a usable id is skipped.
    public func pushDevices() async throws -> [PushDevice] {
        let reply: PushDeviceList = try await request("admin/push/devices")
        return reply.items
    }
    /// 201 creates; 200 registers the same token or target again (same id, enabled again, subscription kept). Sent once (R06).
    public func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool) {
        try registration.validate()
        let response: APIResponse<RegisteredPushDevice> = try await requestWithHeaders("admin/push/devices", method: "POST", body: encode(registration))
        return (response.value.device, response.value.created ?? (response.status == 201))
    }
    public func updatePushSubscription(id: Int, _ subscription: PushSubscription) async throws -> PushDevice {
        let id = try validID(id)
        try subscription.validate()
        return try await request("admin/push/devices/\(id)/subscription", method: "PUT", body: encode(subscription))
    }
    /// The server waits up to 15 seconds for the provider; a refusal is 502 PUSH_DELIVERY_FAILED with `provider_reason`.
    @discardableResult
    public func testPushDevice(id: Int) async throws -> PushTestResult {
        try await request("admin/push/devices/\(validID(id))/test", method: "POST")
    }
    public func pushConfig() async throws -> PushAPNsConfig { try await request("admin/push/config") }
    /// Behind step-up: the page verifies first (S6-25); a refusal is thrown and never resent.
    public func updatePushConfig(_ update: PushAPNsConfigUpdate) async throws -> PushAPNsConfig {
        try await request("admin/push/config", method: "PUT", body: encode(update))
    }
}

private struct PushDeviceList: Decodable, Sendable {
    let items: [PushDevice]
    enum CodingKeys: String, CodingKey { case items }
    init(from decoder: any Decoder) throws { items = try decoder.container(keyedBy: CodingKeys.self).lossyList(PushDevice.self, .items) }
}
/// The device view plus `created`.
private struct RegisteredPushDevice: Decodable, Sendable {
    let device: PushDevice
    let created: Bool?
    enum CodingKeys: String, CodingKey { case created }
    init(from decoder: any Decoder) throws {
        device = try PushDevice(from: decoder)
        created = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .created)
    }
}

private extension KeyedDecodingContainer {
    /// The backend writes absent text as ""; whitespace-only counts as absent too.
    func pushText(_ key: Key) -> String? {
        guard let text = (try? decodeIfPresent(String.self, forKey: key))?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
