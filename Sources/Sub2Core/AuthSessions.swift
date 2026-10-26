import Foundation

/// One entry of `GET /api/v1/auth/sessions` (00 §1.8, 60 §5.2). Sessions issued before the server tracked them have no
/// `client_type`; times stay raw strings until they are displayed.
public struct AuthSessionItem: Identifiable, Decodable, Sendable, Equatable {
    public let id: String
    public let deviceName: String?
    public let clientType: String?
    public let userAgent: String?
    public let ip: String?
    public let createdAt: String?
    public let lastSeenAt: String?
    public let expiresAt: String?
    /// The session this App is signed in with.
    public let current: Bool

    enum CodingKeys: String, CodingKey {
        case id, ip, current
        case deviceName = "device_name", clientType = "client_type", userAgent = "user_agent"
        case createdAt = "created_at", lastSeenAt = "last_seen_at", expiresAt = "expires_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName); clientType = try c.decodeIfPresent(String.self, forKey: .clientType)
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent); ip = try c.decodeIfPresent(String.self, forKey: .ip)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt); lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
    public init(id: String, deviceName: String? = nil, clientType: String? = nil, userAgent: String? = nil, ip: String? = nil,
                createdAt: String? = nil, lastSeenAt: String? = nil, expiresAt: String? = nil, current: Bool = false) {
        self.id = id; self.deviceName = deviceName; self.clientType = clientType; self.userAgent = userAgent; self.ip = ip
        self.createdAt = createdAt; self.lastSeenAt = lastSeenAt; self.expiresAt = expiresAt; self.current = current
    }
}

extension APIClient {
    /// Only an account sign-in has sessions; a key would be refused by the server, so nothing is sent.
    public func sessions() async throws -> [AuthSessionItem] {
        try requireAccountSession()
        let reply: AuthSessionList = try await request("auth/sessions", timeout: RequestTimeout.probe)
        return reply.items ?? []
    }
    /// `true` when the revoked session is this App's own: the caller then signs out of the site (00 §1.8).
    @discardableResult
    public func revokeSession(id: String) async throws -> Bool {
        try requireAccountSession()
        guard Self.isSessionID(id) else { throw APIError(kind: .validation, message: "无效的会话编号。") }
        let reply: RevocationReply = try await request("auth/sessions/\(id)", method: "DELETE", timeout: RequestTimeout.probe)
        return reply.current ?? false
    }
    /// The body is always `{"keep_current":true}`: without it the server signs out every session, this one included (00 §1.8).
    public func revokeOtherSessions() async throws {
        try requireAccountSession()
        let _: EmptyReply = try await request("auth/revoke-all-sessions", method: "POST", body: encode(["keep_current": true]),
                                              timeout: RequestTimeout.probe)
    }

    private func requireAccountSession() throws {
        guard case .tokens? = currentCredential() else { throw APIError(kind: .validation, message: "登录设备只适用于账号登录。") }
    }
    /// Session ids are hex strings; anything outside this set could change the path.
    static func isSessionID(_ id: String) -> Bool {
        (1...128).contains(id.utf8.count) && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}

/// `{message, current}` of a revocation (60 §5.4, §6.4); a missing `current` is not this App's.
struct RevocationReply: Decodable, Sendable { let current: Bool? }
private struct AuthSessionList: Decodable, Sendable { let items: [AuthSessionItem]? }

// MARK: Presentation (60 §5.3–§5.5)

extension AuthSessionItem {
    public static let currentBadgeText = "本机"
    public static let noOtherDevicesText = "没有其他设备登录"
    public static let footnote = "部署新版本前登录的设备，下一次自动续期后才会出现在这里。"
    /// U50: this device signs out only through 设置.
    public static let currentDeviceNoteTitle = "这是本机"
    public static let currentDeviceNoteMessage = "要退出请用设置里的“退出并清除凭据”。"
    public static let revokeActionTitle = "下线"
    public static let revokeMessage = "该设备需要重新登录。"
    public static let revokeOthersButtonTitle = "让其他所有设备下线"
    public static let revokeOthersMessage = "它们需要重新登录，本机不受影响。"
    public static let revokeOthersConfirmTitle = "全部下线"
    /// The login page's notice when a revocation turned out to be this device's own (60 §5.4).
    public static let signedOutNotice = "本机已下线，请重新登录。"
    public static func revokeTitle(_ title: String) -> String { "让「\(title)」下线？" }
    public static func revokedReceipt(_ title: String) -> String { "已下线「\(title)」" }
    public static func revokeOthersTitle(count: Int) -> String { "让其他 \(count) 台设备下线？" }

    /// SF Symbol; a session from before the server recorded `client_type` gets the question mark.
    public var iconName: String {
        switch (clientType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios": "iphone"
        case "android": "smartphone"
        case "web": "globe"
        default: "questionmark.circle"
        }
    }
    /// `device_name`, else the App's own user agent, else the first 40 characters of the user agent (the row cuts the rest).
    public var displayTitle: String {
        if let name = Self.trimmed(deviceName) { return name }
        guard let agent = Self.trimmed(userAgent) else { return "未知设备" }
        return agent.contains("Sub2Mobile") ? "Sub2 Mobile（iOS）" : String(agent.prefix(40))
    }
    /// “203.0.113.24 · 3 分钟前活跃”: `now` is the site's clock, the day boundary the server's zone (00 §6.3).
    public func activityLine(now: Date, timeZone: TimeZone) -> String {
        let time = Self.sessionDate(lastSeenAt).map { date -> String in
            let relative = DisplayFormat.relativeTime(date, now: now, timeZone: timeZone)
            return relative + (relative.last?.isNumber == true ? " 活跃" : "活跃")
        }
        return Self.joined([Self.trimmed(ip), time])
    }
    /// “登录于 10/17 09:41 · 11/16 到期” in the server's zone; a missing half is left out.
    public func lifetimeLine(timeZone: TimeZone) -> String {
        let created = Self.sessionDate(createdAt).map { "登录于 " + Self.monthDay($0, timeZone: timeZone) + " " + DisplayFormat.clock($0, timeZone: timeZone) }
        let expires = Self.sessionDate(expiresAt).map { Self.monthDay($0, timeZone: timeZone) + " 到期" }
        return Self.joined([created, expires])
    }
    /// 让其他所有设备下线 shows from one; a pre-deployment session has no current entry, so every row counts.
    public static func otherDeviceCount(in items: [AuthSessionItem]) -> Int { items.filter { !$0.current }.count }
    /// The rows 让其他所有设备下线 ended: the page hides them at once, so a reload that fails cannot bring them back.
    public static func otherDeviceIDs(in items: [AuthSessionItem]) -> Set<String> { Set(items.filter { !$0.current }.map(\.id)) }
    /// 00 §4.6: a failed reload keeps the older list, with this retry and the time of that list.
    public static let refreshFailedText = "刷新失败 · 重试"
    public static func updatedLine(_ date: Date?, timeZone: TimeZone) -> String? {
        date.map { "更新于 " + DisplayFormat.clock($0, timeZone: timeZone) }
    }
    /// The session is gone already: the row is simply removed (60 §5.4).
    public static func isAlreadyGone(_ error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error.statusCode == 404 && error.reason == "SESSION_NOT_FOUND"
    }

    /// The backend sends Go's zero time for a field Redis does not have; it counts as missing.
    static func sessionDate(_ raw: String?) -> Date? {
        guard let date = ServerTime.parseTimestamp(raw), date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    private static func joined(_ parts: [String?]) -> String {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? DisplayFormat.missing : present.joined(separator: " · ")
    }
    /// MM/dd; S6-26 moves this to DisplayFormat.monthDayClock (S6D1-16).
    private static func monthDay(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.month, .day], from: date)
        return pad(day.month ?? 0) + "/" + pad(day.day ?? 0)
    }
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}
