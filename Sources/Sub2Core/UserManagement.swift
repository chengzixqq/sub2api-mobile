import Foundation

public enum AdminUserRole: String, CaseIterable, Sendable, Encodable {
    case user, vendor, admin
    public var title: String {
        switch self { case .user: "普通用户"; case .vendor: "代运营"; case .admin: "管理员" }
    }
}

/// Write requests deliberately cannot be decoded/persisted: passwords live only in the form and request memory.
public struct UserCreateRequest: Encodable, Sendable, CustomDebugStringConvertible {
    public let email: String
    private let password: String
    public let username: String
    public let notes: String
    public let role: AdminUserRole
    public let concurrency: Int
    public let rpmLimit: Int
    public let balance: Decimal?
    public var debugDescription: String { "UserCreateRequest(<redacted>)" }
    public init(email: String, password: String, username: String = "", notes: String = "", role: AdminUserRole = .user, concurrency: Int = 1, rpmLimit: Int = 0, balance: Decimal? = nil) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines); self.password = password
        self.username = username; self.notes = notes; self.role = role
        self.concurrency = concurrency; self.rpmLimit = rpmLimit; self.balance = balance
    }
    enum CodingKeys: String, CodingKey { case email, password, username, notes, role, concurrency, balance; case rpmLimit = "rpm_limit" }
    public func validate() throws {
        try UserWriteValidation.email(email)
        try UserWriteValidation.password(password)
        try UserWriteValidation.limit(concurrency); try UserWriteValidation.limit(rpmLimit)
        if let balance { try PendingBalanceOperation.validateAmount(balance) }
    }
    public func requestBody() throws -> Data { try validate(); return try UserWriteValidation.encode(self) }
}

public struct UserUpdateRequest: Encodable, Sendable, CustomDebugStringConvertible {
    public let email: String?
    private let password: String?
    public let username: String?
    public let notes: String?
    public let role: AdminUserRole?
    public let concurrency: Int?
    public let rpmLimit: Int?
    public let adjustmentNotes: String?
    public var debugDescription: String { "UserUpdateRequest(<redacted>)" }
    public init(email: String? = nil, password: String? = nil, username: String? = nil, notes: String? = nil, role: AdminUserRole? = nil, concurrency: Int? = nil, rpmLimit: Int? = nil, adjustmentNotes: String? = nil) {
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password?.isEmpty == true ? nil : password
        self.username = username; self.notes = notes; self.role = role
        self.concurrency = concurrency; self.rpmLimit = rpmLimit; self.adjustmentNotes = adjustmentNotes
    }
    enum CodingKeys: String, CodingKey {
        case email, password, username, notes, role, concurrency
        case rpmLimit = "rpm_limit", adjustmentNotes = "adjustment_notes"
    }
    public func validate() throws {
        guard email != nil || password != nil || username != nil || notes != nil || role != nil || concurrency != nil || rpmLimit != nil else {
            throw APIError(kind: .validation, message: "请至少修改一个用户字段。")
        }
        if let email { try UserWriteValidation.email(email) }
        if let password { try UserWriteValidation.password(password) }
        if let concurrency { try UserWriteValidation.limit(concurrency) }
        if let rpmLimit { try UserWriteValidation.limit(rpmLimit) }
    }
    public func requestBody() throws -> Data { try validate(); return try UserWriteValidation.encode(self) }
}

/// A frozen POST admin/users (00 §2.5.2): identity, bytes and number stay fixed until the result is known. Never persist it:
/// the body holds the password. `sendsIdempotencyKey` follows admin.idempotent_writes (wired by S0-10, D24).
public struct PendingUserCreateOperation: Identifiable, Sendable, CustomDebugStringConvertible {
    public let id: UUID
    public let serverID: UUID
    public let identity: UUID
    public let email: String
    public let sendsIdempotencyKey: Bool
    public let body: Data
    /// What the Face ID threshold is compared with before sending (60 §3.4).
    public let initialBalance: Decimal?
    /// X-Request-ID, and the Idempotency-Key when one is sent.
    public var key: String { id.uuidString.lowercased() }
    public var debugDescription: String { "PendingUserCreateOperation(<redacted>)" }
    public init(id: UUID = UUID(), serverID: UUID, identity: UUID, request: UserCreateRequest, sendsIdempotencyKey: Bool) throws {
        self.id = id; self.serverID = serverID; self.identity = identity; email = request.email; initialBalance = request.balance
        self.sendsIdempotencyKey = sendsIdempotencyKey
        body = try request.requestBody()
    }
}

/// Immutable identity, bytes and UUID are retained across explicit retries, including step-up.
/// Never persist this type: a prepared update can contain a password.
public struct PendingUserUpdateOperation: Identifiable, Sendable, CustomDebugStringConvertible {
    public let id: UUID
    public let serverID: UUID
    public let identity: UUID
    public let userID: Int
    /// Sent with an Idempotency-Key: the site has admin.idempotent_writes (S0-10 passes it, D24), or concurrency changes.
    public let supportsSafeRetry: Bool
    public let body: Data
    public var key: String { id.uuidString.lowercased() }
    public var debugDescription: String { "PendingUserUpdateOperation(<redacted>)" }
    public init(id: UUID = UUID(), serverID: UUID, identity: UUID, userID: Int, request: UserUpdateRequest, serverSupportsIdempotentWrites: Bool = false) throws {
        guard userID > 0 else { throw APIError(kind: .validation, message: "无效的用户编号。") }
        self.id = id; self.serverID = serverID; self.identity = identity; self.userID = userID
        supportsSafeRetry = serverSupportsIdempotentWrites || request.concurrency != nil
        body = try request.requestBody()
    }
}

private enum UserWriteValidation {
    static func email(_ value: String) throws {
        guard value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            throw APIError(kind: .validation, message: "请输入有效的邮箱地址。")
        }
    }
    static func password(_ value: String) throws {
        // Backend min=6 counts Unicode scalar values; bcrypt rejects more than 72 UTF-8 bytes.
        guard value.unicodeScalars.count >= 6, value.utf8.count <= 72 else {
            throw APIError(kind: .validation, message: "密码至少 6 个字符，且 UTF-8 长度不能超过 72 字节。")
        }
    }
    static func limit(_ value: Int) throws {
        guard value >= 0, value <= Int(Int32.max) else {
            throw APIError(kind: .validation, message: "并发和 RPM 必须是 0 至 2147483647 的整数；0 表示不限制。")
        }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
