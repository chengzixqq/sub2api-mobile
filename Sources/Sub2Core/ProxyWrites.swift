import Foundation

// 60 §14: the create and edit bodies of a proxy (S6-10). Kept beside Proxies.swift so that file stays under 700 lines.

/// `fallback_mode`: what the expiry sweep does with the accounts still on the proxy.
public enum ProxyFallbackMode: String, Sendable, Equatable, CaseIterable, Encodable { case none, proxy, direct }
/// The statuses a PUT takes; `expired` comes only from the server's sweep.
public enum ProxyStatusChange: String, Sendable, Equatable, Encodable { case active, inactive }
/// An edit that clears a field (JSON null) or sets it; a nil property of the request leaves the key out.
public enum ProxyFieldChange<Value: Sendable & Equatable>: Sendable, Equatable {
    case clear, set(Value)
    fileprivate func map<T: Sendable & Equatable>(_ transform: (Value) throws -> T) rethrows -> ProxyFieldChange<T> {
        switch self {
        case .clear: .clear
        case .set(let value): .set(try transform(value))
        }
    }
}

/// `POST admin/proxies` (60 §14.2). `expires_at` goes out as Unix seconds; an empty username or password and a missing expiry
/// (never expires) are left out. The password stays in memory and every description writes <redacted>.
public struct ProxyCreateRequest: Encodable, Sendable, Equatable {
    public static let schemes = ["http", "https", "socks5", "socks5h"]
    public var name: String
    public var scheme: String
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    public var expiresAt: Date?
    public var fallbackMode: ProxyFallbackMode
    public var backupProxyID: Int?
    public var expiryWarnDays: Int
    public init(name: String, scheme: String = "socks5", host: String, port: Int, username: String = "", password: String = "", expiresAt: Date? = nil,
                fallbackMode: ProxyFallbackMode = ProxyFallbackMode.none, backupProxyID: Int? = nil, expiryWarnDays: Int = 7) {
        self.name = name; self.scheme = scheme; self.host = host; self.port = port; self.username = username; self.password = password
        self.expiresAt = expiresAt; self.fallbackMode = fallbackMode; self.backupProxyID = backupProxyID; self.expiryWarnDays = expiryWarnDays
    }
    /// The checks of 60 §14.4 and the column sizes: name and host not blank, name ≤ 100, host ≤ 255, username and password ≤ 100
    /// UTF-8 bytes; a known scheme, port 1–65535, warning days ≥ 0; a backup id above 0, required for the backup-proxy fallback.
    public func validate() throws {
        try ProxyWriteCheck.name(name); try ProxyWriteCheck.host(host); try ProxyWriteCheck.port(port); try ProxyWriteCheck.scheme(scheme)
        try ProxyWriteCheck.credential(username); try ProxyWriteCheck.credential(password); try ProxyWriteCheck.warnDays(expiryWarnDays)
        if let backupProxyID { try ProxyWriteCheck.backupID(backupProxyID) }
        if let expiresAt { _ = try ProxyWriteCheck.unixSeconds(expiresAt) }
        guard fallbackMode != .proxy || backupProxyID != nil else { throw ProxyWriteCheck.error(ProxyWriteCheck.backupRequired) }
    }
    public func requestBody() throws -> Data { try validate(); return try ProxyWriteCheck.encode(self) }
    enum CodingKeys: String, CodingKey {
        case name, scheme = "protocol", host, port, username, password, expiresAt = "expires_at", fallbackMode = "fallback_mode"
        case backupProxyID = "backup_proxy_id", expiryWarnDays = "expiry_warn_days"
    }
    /// Text is trimmed as the server trims it.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ProxyWriteCheck.trimmed(name), forKey: .name); try c.encode(ProxyWriteCheck.trimmed(scheme), forKey: .scheme)
        try c.encode(ProxyWriteCheck.trimmed(host), forKey: .host); try c.encode(port, forKey: .port)
        try c.encodeIfPresent(ProxyWriteCheck.nonEmpty(username), forKey: .username)
        try c.encodeIfPresent(ProxyWriteCheck.nonEmpty(password), forKey: .password)
        try c.encodeIfPresent(expiresAt.map(ProxyWriteCheck.unixSeconds), forKey: .expiresAt)
        try c.encode(fallbackMode, forKey: .fallbackMode); try c.encodeIfPresent(backupProxyID, forKey: .backupProxyID)
        try c.encode(expiryWarnDays, forKey: .expiryWarnDays)
    }
}

extension ProxyCreateRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ProxyCreateRequest(name: \(name), address: \(scheme)://\(host):\(port), password: \(ProxyWriteCheck.mask(password)))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "address": "\(scheme)://\(host):\(port)", "password": ProxyWriteCheck.mask(password)], displayStyle: .struct)
    }
}

/// `PUT admin/proxies/:id` (60 §14.2): only the keys that changed. `username` "" clears it and nil leaves it (the server reads null
/// as no change too, so null is never sent); `password` only when the user typed one; `.clear` sends null.
public struct ProxyUpdateRequest: Encodable, Sendable, Equatable {
    public var name: String?
    public var scheme: String?
    public var host: String?
    public var port: Int?
    public var username: String?
    public var password: String?
    public var status: ProxyStatusChange?
    /// `.clear`: never expires.
    public var expiresAt: ProxyFieldChange<Date>?
    public var fallbackMode: ProxyFallbackMode?
    public var backupProxyID: ProxyFieldChange<Int>?
    public var expiryWarnDays: Int?
    public init(name: String? = nil, scheme: String? = nil, host: String? = nil, port: Int? = nil, username: String? = nil, password: String? = nil,
                status: ProxyStatusChange? = nil, expiresAt: ProxyFieldChange<Date>? = nil, fallbackMode: ProxyFallbackMode? = nil,
                backupProxyID: ProxyFieldChange<Int>? = nil, expiryWarnDays: Int? = nil) {
        self.name = name; self.scheme = scheme; self.host = host; self.port = port; self.username = username; self.password = password
        self.status = status; self.expiresAt = expiresAt; self.fallbackMode = fallbackMode; self.backupProxyID = backupProxyID
        self.expiryWarnDays = expiryWarnDays
    }
    public var hasChanges: Bool { !sentKeys.isEmpty }
    /// Scheme, host, port, username or password is sent: the server drops the latency snapshot and probes again (H04, 60 §13.6).
    public var touchesNetwork: Bool { scheme != nil || host != nil || port != nil || username != nil || password != nil }
    /// The create checks for the keys present, at least one key, and a backup other than the proxy itself.
    public func validate(proxyID: Int) throws {
        guard hasChanges else { throw ProxyWriteCheck.error("没有要保存的修改。") }
        if let name { try ProxyWriteCheck.name(name) }
        if let host { try ProxyWriteCheck.host(host) }
        if let port { try ProxyWriteCheck.port(port) }
        if let scheme { try ProxyWriteCheck.scheme(scheme) }
        for credential in [username, password].compactMap({ $0 }) { try ProxyWriteCheck.credential(credential) }
        if let expiryWarnDays { try ProxyWriteCheck.warnDays(expiryWarnDays) }
        if case .set(let date)? = expiresAt { _ = try ProxyWriteCheck.unixSeconds(date) }
        if case .set(let backup)? = backupProxyID {
            try ProxyWriteCheck.backupID(backup)
            guard backup != proxyID else { throw ProxyWriteCheck.error("备用代理不能是它自己") }
        }
        guard fallbackMode != .proxy || backupProxyID != .clear else { throw ProxyWriteCheck.error(ProxyWriteCheck.backupRequired) }
    }
    public func requestBody(proxyID: Int) throws -> Data { try validate(proxyID: proxyID); return try ProxyWriteCheck.encode(self) }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, scheme = "protocol", host, port, username, password, status, expiresAt = "expires_at", fallbackMode = "fallback_mode"
        case backupProxyID = "backup_proxy_id", expiryWarnDays = "expiry_warn_days"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name.map(ProxyWriteCheck.trimmed), forKey: .name); try c.encodeIfPresent(scheme.map(ProxyWriteCheck.trimmed), forKey: .scheme)
        try c.encodeIfPresent(host.map(ProxyWriteCheck.trimmed), forKey: .host); try c.encodeIfPresent(port, forKey: .port)
        try c.encodeIfPresent(username.map(ProxyWriteCheck.trimmed), forKey: .username)
        try c.encodeIfPresent(password.map(ProxyWriteCheck.trimmed), forKey: .password)
        try c.encodeIfPresent(status, forKey: .status); try c.encodeIfPresent(fallbackMode, forKey: .fallbackMode)
        try c.encodeIfPresent(expiryWarnDays, forKey: .expiryWarnDays)
        try Self.encode(expiresAt.map { try $0.map(ProxyWriteCheck.unixSeconds) }, forKey: .expiresAt, in: &c)
        try Self.encode(backupProxyID, forKey: .backupProxyID, in: &c)
    }
    /// R06 read-back on a fresh `GET :id`: only the keys this edit sends; text compared trimmed, the expiry by whole seconds, the
    /// password with the admin DTO's plain one.
    public func matches(_ proxy: AdminProxy) -> Bool {
        func same(_ sent: String?, _ stored: String?) -> Bool {
            sent.map { ProxyWriteCheck.trimmed($0) == ProxyWriteCheck.trimmed(stored ?? "") } ?? true
        }
        let seconds = { (date: Date) in date.timeIntervalSince1970.rounded(.down) }
        return same(name, proxy.name) && same(scheme, proxy.scheme) && same(host, proxy.host) && (port.map { $0 == proxy.port } ?? true)
            && same(username, proxy.username) && same(password, proxy.password) && same(status?.rawValue, proxy.status)
            && same(fallbackMode?.rawValue, proxy.fallbackMode) && (expiryWarnDays.map { $0 == proxy.expiryWarnDays } ?? true)
            && Self.same(expiresAt?.map(seconds), proxy.expiresAt.map(seconds)) && Self.same(backupProxyID, proxy.backupProxyID)
    }

    private var sentKeys: [CodingKeys] {
        let sent: [CodingKeys: Bool] = [.name: name != nil, .scheme: scheme != nil, .host: host != nil, .port: port != nil,
                                        .username: username != nil, .password: password != nil, .status: status != nil,
                                        .expiresAt: expiresAt != nil, .fallbackMode: fallbackMode != nil, .backupProxyID: backupProxyID != nil,
                                        .expiryWarnDays: expiryWarnDays != nil]
        return CodingKeys.allCases.filter { sent[$0] == true }
    }
    private static func encode<Value: Encodable>(_ change: ProxyFieldChange<Value>?, forKey key: CodingKeys,
                                                 in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch change {
        case .clear?: try container.encodeNil(forKey: key)
        case .set(let value)?: try container.encode(value, forKey: key)
        case nil: break
        }
    }
    private static func same<Value: Equatable>(_ change: ProxyFieldChange<Value>?, _ stored: Value?) -> Bool {
        switch change {
        case nil: true
        case .clear?: stored == nil
        case .set(let value)?: stored == value
        }
    }
}

extension ProxyUpdateRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ProxyUpdateRequest(keys: [\(sentKeys.map(\.rawValue).joined(separator: ", "))], password: \(ProxyWriteCheck.mask(password)))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["keys": sentKeys.map(\.rawValue), "password": ProxyWriteCheck.mask(password)], displayStyle: .struct)
    }
}

/// The create and edit rules of 60 §14.4; sizes from `ent/schema/proxy.go`, in bytes as Go counts them.
enum ProxyWriteCheck {
    static let nameLimit = 100, hostLimit = 255, credentialLimit = 100
    static let backupRequired = "选了备用代理回退，请选择一个备用代理"
    static func error(_ message: String = "代理信息不符合要求。") -> APIError { APIError(kind: .validation, message: message) }
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func nonEmpty(_ text: String) -> String? { let value = trimmed(text); return value.isEmpty ? nil : value }
    static func mask(_ password: String?) -> String { (password ?? "").isEmpty ? "none" : "<redacted>" }
    static func name(_ raw: String) throws {
        let name = trimmed(raw)
        guard !name.isEmpty else { throw error("请输入代理名称") }
        guard name.utf8.count <= nameLimit else { throw error() }
    }
    static func host(_ raw: String) throws {
        let host = trimmed(raw)
        guard !host.isEmpty else { throw error("请输入主机地址") }
        guard host.utf8.count <= hostLimit else { throw error() }
    }
    static func port(_ port: Int) throws { guard (1...65_535).contains(port) else { throw error("端口必须在 1-65535 之间") } }
    static func scheme(_ raw: String) throws { guard ProxyCreateRequest.schemes.contains(trimmed(raw)) else { throw error() } }
    static func credential(_ raw: String) throws { guard trimmed(raw).utf8.count <= credentialLimit else { throw error() } }
    static func warnDays(_ days: Int) throws { guard days >= 0 else { throw error() } }
    static func backupID(_ id: Int) throws { guard id > 0 else { throw error() } }
    /// Whole seconds, rounded down. A time at or before 1970 would read as “never expires” (the server ignores `expires_at <= 0`).
    static func unixSeconds(_ date: Date) throws -> Int64 {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        guard seconds.isFinite, seconds >= 1, seconds < 1e15 else { throw error() }
        return Int64(seconds)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
