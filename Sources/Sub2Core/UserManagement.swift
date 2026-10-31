import Foundation

public enum AdminUserRole: String, CaseIterable, Sendable, Encodable {
    case user, vendor, admin
    /// 30 §0.3 role words.
    public var title: String {
        switch self { case .user: "用户"; case .vendor: "供应商"; case .admin: "管理员" }
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
    /// Sorted and unique; none is stored as nil and left out of the body (the server reads a missing list as empty).
    public let allowedGroups: [Int]?
    public let restrictPublicGroups: Bool
    public var debugDescription: String { "UserCreateRequest(<redacted>)" }
    public init(email: String, password: String, username: String = "", notes: String = "", role: AdminUserRole = .user, concurrency: Int = 1, rpmLimit: Int = 0, balance: Decimal? = nil,
                allowedGroups: [Int] = [], restrictPublicGroups: Bool = false) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines); self.password = password
        self.username = username; self.notes = notes; self.role = role
        self.concurrency = concurrency; self.rpmLimit = rpmLimit; self.balance = balance
        self.allowedGroups = allowedGroups.isEmpty ? nil : Set(allowedGroups).sorted(); self.restrictPublicGroups = restrictPublicGroups
    }
    enum CodingKeys: String, CodingKey {
        case email, password, username, notes, role, concurrency, balance
        case rpmLimit = "rpm_limit", allowedGroups = "allowed_groups", restrictPublicGroups = "restrict_public_groups"
    }
    public func validate() throws {
        try UserWriteValidation.email(email)
        try UserWriteValidation.password(password)
        try UserWriteValidation.limit(concurrency); try UserWriteValidation.limit(rpmLimit)
        if let balance { try PendingBalanceOperation.validateAmount(balance) }
        try UserWriteValidation.groupIDs(allowedGroups ?? [])
    }
    public func requestBody() throws -> Data { try validate(); return try UserWriteValidation.encode(self) }
}

/// Only the fields that changed (30 §6.4). `allowed_groups` and `restrict_public_groups` always travel together (S3D1-10):
/// the list is the full grant, sorted and unique, and `[]` clears it. Never carries `balance` (400 USER_BALANCE_NOT_EDITABLE).
public struct UserUpdateRequest: Encodable, Sendable, Equatable, CustomDebugStringConvertible {
    public let email: String?
    private let password: String?
    public let username: String?
    public let notes: String?
    public let role: AdminUserRole?
    public let concurrency: Int?
    public let rpmLimit: Int?
    /// Kept only with a concurrency change, trimmed and non-empty.
    public let adjustmentNotes: String?
    /// "active" or "disabled".
    public let status: String?
    public let allowedGroups: [Int]?
    public let restrictPublicGroups: Bool?
    /// Changed groups only; a nil rate clears that group's rate (JSON null). An empty map is stored as nil: the server would
    /// read `{}` as “clear every rate”.
    public let groupRates: [Int: Decimal?]?
    public var debugDescription: String { "UserUpdateRequest(<redacted>)" }
    public init(email: String? = nil, password: String? = nil, username: String? = nil, notes: String? = nil, role: AdminUserRole? = nil, concurrency: Int? = nil, rpmLimit: Int? = nil, adjustmentNotes: String? = nil,
                status: String? = nil, allowedGroups: [Int]? = nil, restrictPublicGroups: Bool? = nil, groupRates: [Int: Decimal?]? = nil) {
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password?.isEmpty == true ? nil : password
        self.username = username; self.notes = notes; self.role = role
        self.concurrency = concurrency; self.rpmLimit = rpmLimit
        let reason = adjustmentNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.adjustmentNotes = concurrency == nil || reason?.isEmpty != false ? nil : reason
        self.status = status; self.allowedGroups = allowedGroups.map { Set($0).sorted() }; self.restrictPublicGroups = restrictPublicGroups
        self.groupRates = groupRates?.isEmpty == true ? nil : groupRates
    }
    enum CodingKeys: String, CodingKey {
        case email, password, username, notes, role, concurrency, status
        case rpmLimit = "rpm_limit", adjustmentNotes = "adjustment_notes", allowedGroups = "allowed_groups"
        case restrictPublicGroups = "restrict_public_groups", groupRates = "group_rates"
    }
    /// Every field must be listed here: a field left out would silently never be sent.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(email, forKey: .email); try c.encodeIfPresent(password, forKey: .password)
        try c.encodeIfPresent(username, forKey: .username); try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(role, forKey: .role); try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(concurrency, forKey: .concurrency); try c.encodeIfPresent(rpmLimit, forKey: .rpmLimit)
        try c.encodeIfPresent(adjustmentNotes, forKey: .adjustmentNotes)
        try c.encodeIfPresent(allowedGroups, forKey: .allowedGroups); try c.encodeIfPresent(restrictPublicGroups, forKey: .restrictPublicGroups)
        guard let groupRates else { return }
        var rates = c.nestedContainer(keyedBy: GroupIDKey.self, forKey: .groupRates)
        for (id, rate) in groupRates {
            if let rate { try rates.encode(rate, forKey: GroupIDKey(id)) } else { try rates.encodeNil(forKey: GroupIDKey(id)) }
        }
    }
    /// Adjustment notes alone are not a change.
    var hasChanges: Bool {
        let account = email != nil || password != nil || username != nil || notes != nil || role != nil || status != nil
        let limits = concurrency != nil || rpmLimit != nil
        return account || limits || allowedGroups != nil || restrictPublicGroups != nil || groupRates != nil
    }
    public func validate() throws {
        guard hasChanges else { throw APIError(kind: .validation, message: "请至少修改一个用户字段。") }
        if let email { try UserWriteValidation.email(email) }
        if let password { try UserWriteValidation.password(password) }
        if let status { try UserWriteValidation.status(status) }
        if let concurrency { try UserWriteValidation.limit(concurrency) }
        if let rpmLimit { try UserWriteValidation.limit(rpmLimit) }
        if let allowedGroups { try UserWriteValidation.groupIDs(allowedGroups) }
        guard let groupRates else { return }
        try UserWriteValidation.groupIDs(Array(groupRates.keys))
        for case let rate? in groupRates.values { try UserWriteValidation.rate(rate) }
    }
    public func requestBody() throws -> Data { try validate(); return try UserWriteValidation.encode(self) }
}

/// A group id as a JSON object key (`group_rates`).
private struct GroupIDKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ id: Int) { stringValue = String(id) }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue) }
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
    /// The request as frozen: after an unconfirmed result it is compared with a GET (`UserAccessDraft.readback`).
    public let request: UserUpdateRequest
    public var key: String { id.uuidString.lowercased() }
    public var debugDescription: String { "PendingUserUpdateOperation(<redacted>)" }
    public init(id: UUID = UUID(), serverID: UUID, identity: UUID, userID: Int, request: UserUpdateRequest, serverSupportsIdempotentWrites: Bool = false) throws {
        guard userID > 0 else { throw APIError(kind: .validation, message: "无效的用户编号。") }
        self.id = id; self.serverID = serverID; self.identity = identity; self.userID = userID
        supportsSafeRetry = serverSupportsIdempotentWrites || request.concurrency != nil
        body = try request.requestBody(); self.request = request
    }
}

/// Shared with UserAccessDraft, which shows the per-field texts of 30 §5.3 instead of these sentences.
enum UserWriteValidation {
    static let rateMessage = "要大于 0，最多 3 位小数"
    static let limitMessage = "并发和 RPM 必须是 0 至 2147483647 的整数；0 表示不限制。"
    static func isEmail(_ value: String) -> Bool { value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    /// Backend min=6 counts Unicode scalar values; bcrypt rejects more than 72 UTF-8 bytes.
    static func isLongEnough(_ password: String) -> Bool { password.unicodeScalars.count >= 6 }
    static func fitsBcrypt(_ password: String) -> Bool { password.utf8.count <= 72 }
    static func isLimit(_ value: Int) -> Bool { value >= 0 && value <= Int(Int32.max) }
    /// 30 §6.3: above 0 with at most 3 decimals; the server answers a 500 without reason to a rate ≤ 0 (U30).
    static func isValidRate(_ value: Decimal) -> Bool { !value.isNaN && value > 0 && value.hasAtMostFractionDigits(3) }
    static func email(_ value: String) throws {
        guard isEmail(value) else { throw APIError(kind: .validation, message: "请输入有效的邮箱地址。") }
    }
    static func password(_ value: String) throws {
        guard isLongEnough(value), fitsBcrypt(value) else {
            throw APIError(kind: .validation, message: "密码至少 6 个字符，且 UTF-8 长度不能超过 72 字节。")
        }
    }
    static func limit(_ value: Int) throws {
        guard isLimit(value) else { throw APIError(kind: .validation, message: limitMessage) }
    }
    static func status(_ value: String) throws {
        guard ["active", "disabled"].contains(value) else { throw APIError(kind: .validation, message: "无效的用户状态。") }
    }
    static func groupIDs(_ ids: [Int]) throws {
        guard ids.allSatisfy({ $0 > 0 }) else { throw APIError(kind: .validation, message: "无效的分组编号。") }
    }
    static func rate(_ value: Decimal) throws {
        guard isValidRate(value) else { throw APIError(kind: .validation, message: rateMessage) }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

// MARK: - 用户读写接口（S3-01 从 APIClient.swift 移来）

extension APIClient {
    /// With admin.idempotent_writes the frozen number is also the Idempotency-Key (00 §2.5.1); without it, X-Request-ID only.
    public func createUser(_ operation: PendingUserCreateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        try check(operation.identity)
        guard operation.sendsIdempotencyKey else { return try await performUnkeyedWrite("admin/users", method: "POST", body: operation.body, requestID: operation.key) }
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/users", method: "POST", body: operation.body, key: operation.id), onEvent: onEvent)
    }
    public func updateUser(_ operation: PendingUserUpdateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        try check(operation.identity)
        let path = "admin/users/\(try validID(operation.userID))"
        guard operation.supportsSafeRetry else { return try await performUnkeyedWrite(path, method: "PUT", body: operation.body, requestID: operation.key) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "PUT", body: operation.body, key: operation.id), onEvent: onEvent)
    }
    /// 30 §2.2 本月消费: usage/stats from the 1st of the server's month to its today, in its zone; read `totalActualCost`.
    /// (The legacy /admin/users/:id/usage endpoint returns mock zeros in this backend.)
    public func userMonthUsage(id: Int) async throws -> UserUsageSummary {
        try await request("admin/usage/stats", query: monthRange() + [URLQueryItem(name: "user_id", value: String(validID(id)))],
                          timeout: RequestTimeout.aggregate)
    }
    /// Sent once, without a key: the request-layer tests use it as the plain unkeyed write.
    public func setUserStatus(id: Int, status: String) async throws -> AdminUser {
        try await request("admin/users/\(validID(id))", method: "PUT", body: statusBody(status))
    }
    /// 30 §2.4 启用 / 禁用: with admin.idempotent_writes the caller passes a key and the write is retried and waited for under it
    /// (00 §2.5); without one it is the same bytes sent once.
    public func setUserStatus(id: Int, status: String, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        let path = "admin/users/\(try validID(id))", body = try statusBody(status)
        guard let idempotencyKey else { return try await performUnkeyedWrite(path, method: "PUT", body: body, requestID: UUID().uuidString.lowercased()) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "PUT", body: body, key: idempotencyKey), onEvent: onEvent)
    }
    /// 30 §2.4 删除用户: no key and no retry (a repeat answers 404). `false` when the server says the user is already gone.
    public func deleteUser(id: Int) async throws -> Bool {
        let path = "admin/users/\(try validID(id))"
        do {
            let _: DeletedUserReply = try await request(path, method: "DELETE")
            return true
        } catch let error as APIError where error.isUserNotFound {
            return false
        }
    }
    private func statusBody(_ status: String) throws -> Data {
        guard ["active", "disabled"].contains(status) else { throw APIError(kind: .validation, message: "无效的用户状态。") }
        return try encode(["status": status])
    }
}

/// `{"message":"User deleted successfully"}`; only that it decoded matters.
private struct DeletedUserReply: Decodable, Sendable { let message: String? }

// MARK: - 新建 / 编辑用户的核对读取（S3-09）

extension APIClient {
    /// 30 §6.2 降级预检: administrators on the site, from the list's `total`. Like the server's own last-admin check it can
    /// race a concurrent change; the server still refuses (500 without reason).
    public func adminCount() async throws -> Int {
        let page = try await users(query: UserListQuery(page: 1, pageSize: 1, role: AdminUserRole.admin.rawValue))
        guard let total = page.total else { throw APIError.invalidResponse }
        return total
    }
    /// 00 §2.5.5 / 30 §5.4 step 7: the user created under this address, if any. The search also matches usernames, notes
    /// and keys, so only an address equal ignoring case counts; the list is newest first, so a new user is on page 1.
    public func findUserByEmail(_ email: String) async throws -> AdminUser? {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw APIError(kind: .validation, message: "请输入邮箱") }
        let page = try await users(query: UserListQuery(search: address, page: 1, pageSize: PageSize.standard))
        return page.items.first { $0.email.caseInsensitiveCompare(address) == .orderedSame }
    }
}
