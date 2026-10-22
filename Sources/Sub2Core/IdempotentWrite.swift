import Foundation

/// 00 §2.4 and §2.5.3–§2.5.4 numbers for keyed writes (R04, U03); the client timeout is RequestTimeout.keyedWrite.
public enum IdempotencyPolicy {
    /// Same key and bytes again after a timeout, a lost connection, 502, 504 or a proxy 503.
    public static let transportRetryDelays: [Duration] = [.seconds(2), .seconds(5)]
    /// IN_PROGRESS and RETRY_BACKOFF are waited for at most this long after the first such reply.
    public static let waitBudget: TimeInterval = 30
    /// Seconds when neither Retry-After nor metadata.retry_after is present.
    public static let defaultRetryAfter = 2
    /// STORE_UNAVAILABLE did not run the write; the same number may be retried after this.
    public static let storeUnavailableCooldown: TimeInterval = 10
    /// Without X-Idempotency-Expires-At a record counts as replayable for 24 hours after createdAt.
    public static let defaultExpiry: TimeInterval = 86_400
}

/// A write that succeeded, with the idempotency headers of 00 §2.2 / §2.5.3.
public struct WriteOutcome<Value: Sendable>: Sendable {
    public let value: Value
    /// The server returned the first result without running the write again; runtime fields may be stale.
    public let replayed: Bool
    /// The server found the result of a stuck first execution (group duplicate).
    public let recovered: Bool
    /// Any X-Idempotency-Degraded value (result-committed, store-unavailable): a success after which this key is not reused.
    public let degraded: Bool
    public let expiresAt: Date?
    public let actionID: UUID?
    public let batchID: UUID?
    /// The echoed X-Request-ID.
    public let requestID: String?
    public init(value: Value, replayed: Bool = false, recovered: Bool = false, degraded: Bool = false, expiresAt: Date? = nil,
                actionID: UUID? = nil, batchID: UUID? = nil, requestID: String? = nil) {
        self.value = value; self.replayed = replayed; self.recovered = recovered; self.degraded = degraded
        self.expiresAt = expiresAt; self.actionID = actionID; self.batchID = batchID; self.requestID = requestID
    }
    public init(value: Value, headers: [String: String]) {
        func field(_ name: String) -> String? {
            guard let raw = headers.headerValue(name)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            return raw
        }
        self.init(value: value, replayed: field("X-Idempotency-Replayed")?.lowercased() == "true",
                  recovered: field("X-Idempotency-Recovered")?.lowercased() == "true", degraded: field("X-Idempotency-Degraded") != nil,
                  expiresAt: field("X-Idempotency-Expires-At").flatMap(rfc3339), actionID: field("X-Admin-Adjustment-Action-ID").flatMap(UUID.init(uuidString:)),
                  batchID: field("X-Redeem-Batch-ID").flatMap(UUID.init(uuidString:)), requestID: field("X-Request-ID"))
    }
}

/// The backend writes RFC 3339 UTC without fractions; S0-07's ServerTime can replace this once it exists.
private func rfc3339(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: raw) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: raw)
}

/// 00 §2.5.3, decided by the exact (status, reason) pair.
public enum IdempotencyOutcome: Sendable, Equatable {
    case succeeded
    /// 2xx whose body is not a readable envelope: the write may have run.
    case unreadableSuccess
    case inProgress(retryAfter: Int), retryBackoff(retryAfter: Int)
    case keyConflict, invalidKeyOrPayload, keyRequired, storeUnavailable
    /// 502, 504 and a 503 without its own reason (or SERVICE_UNAVAILABLE): handled like a lost connection.
    case transportFailure
    /// Business and pre-execution errors (step-up, 423, 429, 404, EMAIL_EXISTS…) and 2xx with a non-zero code.
    case rejected

    public static func classify(_ response: HTTPResponse) -> IdempotencyOutcome {
        let envelope = ErrorEnvelope.decode(response.data)
        if (200..<300).contains(response.statusCode) {
            guard let envelope, envelope.code != nil else { return .unreadableSuccess }
            return envelope.isSuccess ? .succeeded : .rejected
        }
        let marker = envelope?.marker
        switch (response.statusCode, marker) {
        case (409, "IDEMPOTENCY_IN_PROGRESS"?): return .inProgress(retryAfter: waitSeconds(response, envelope))
        case (409, "IDEMPOTENCY_RETRY_BACKOFF"?): return .retryBackoff(retryAfter: waitSeconds(response, envelope))
        case (409, "IDEMPOTENCY_KEY_CONFLICT"?): return .keyConflict
        case (400, "IDEMPOTENCY_KEY_INVALID"?), (400, "IDEMPOTENCY_PAYLOAD_INVALID"?): return .invalidKeyOrPayload
        case (400, "IDEMPOTENCY_KEY_REQUIRED"?): return .keyRequired
        case (503, "IDEMPOTENCY_STORE_UNAVAILABLE"?): return .storeUnavailable
        default: return RequestPolicy.isRetryableStatus(response.statusCode, marker: marker) ? .transportFailure : .rejected
        }
    }
    /// Retry-After, then metadata.retry_after, then 2 seconds; never below 1 (D04).
    static func waitSeconds(_ response: HTTPResponse, _ envelope: ErrorEnvelope?) -> Int {
        max(1, RetryAfter.resolve(headers: response.headers, envelope: envelope) ?? IdempotencyPolicy.defaultRetryAfter)
    }
}

/// A keyed write that ended without a definite answer (00 §2.5.4) or that must be confirmed again with a new key.
public struct KeyedWriteFailure: LocalizedError, Sendable, Equatable {
    public enum UnconfirmedCause: Sendable, Equatable { case transport, stillProcessing, storeUnavailable, unreadableResponse }
    public enum NewKeyCause: Sendable, Equatable { case keyConflict, invalid, keyRequired }
    public enum Disposition: Sendable, Equatable {
        /// The server may have run it: keep the record, then check or retry the same number (not before `retryNotBefore`).
        case unconfirmed(UnconfirmedCause, retryNotBefore: Date?)
        /// The server did not run it and will not take these bytes under this key: confirm again with a new key.
        case needsNewKey(NewKeyCause)
    }
    public let disposition: Disposition
    /// Lowercased Idempotency-Key, also the X-Request-ID.
    public let key: String
    public let actionID: UUID?
    /// The last server answer or transport error, for the error details.
    public let lastError: APIError?
    public init(disposition: Disposition, key: String, actionID: UUID?, lastError: APIError?) {
        self.disposition = disposition; self.key = key; self.actionID = actionID; self.lastError = lastError
    }
    /// 00 §2.5.4 step 3, also shown when the user stops waiting (“稍后核对”).
    public static let unconfirmedMessage = ReasonCatalog.entry(status: 409, reason: "IDEMPOTENCY_IN_PROGRESS").message
    public var errorDescription: String? {
        switch disposition {
        case .unconfirmed(.storeUnavailable, _): "服务器暂时无法受理，稍后用同一编号重试"
        case .unconfirmed: Self.unconfirmedMessage
        case .needsNewKey(.keyConflict): ReasonCatalog.entry(status: 409, reason: "IDEMPOTENCY_KEY_CONFLICT").message
        case .needsNewKey: ReasonCatalog.entry(status: 400, reason: "IDEMPOTENCY_KEY_INVALID").message
        }
    }
}

/// Progress of one keyed write, for “正在确认结果…”, waiting seconds and saving the action id before the result is known.
public enum KeyedWriteEvent: Sendable, Equatable {
    /// X-Admin-Adjustment-Action-ID, reported the first time any reply carries it (30 §3.4 step 4).
    case actionID(UUID)
    /// The same key and bytes go out again after a transport failure: retry 1 or 2.
    case confirming(retry: Int)
    /// IN_PROGRESS / RETRY_BACKOFF: whole seconds since the first such reply.
    case waitingForServer(elapsedSeconds: Int)
}
public typealias KeyedWriteEventHandler = @Sendable (KeyedWriteEvent) async -> Void

// MARK: Money-write records (00 §2.5.5)

/// What the overview, settings and banners show for a pending money write. createdAt is nil only for balance records saved
/// before S0-06; sort those first.
public struct PendingMoneyWriteSummary: Sendable, Equatable {
    public enum Subject: Sendable, Equatable {
        case balance(BalanceOperation, amount: Decimal)
        /// `total` only for balance-type codes.
        case redeemBatch(count: Int, total: Decimal?)
        case compensation(CompensationType, value: Decimal)
    }
    public let subject: Subject
    public let createdAt: Date?
    public let userID: Int?
    public let userDisplayName: String?
    public let userEmail: String?
    public init(subject: Subject, createdAt: Date?, userID: Int? = nil, userDisplayName: String? = nil, userEmail: String? = nil) {
        self.subject = subject; self.createdAt = createdAt; self.userID = userID; self.userDisplayName = userDisplayName; self.userEmail = userEmail
    }
}

/// The three money-write records share this (D16): createdAt and the user fields are read from `summary`, because a legacy
/// balance record has no createdAt and a redeem batch no user, and protocol property types must match exactly.
public protocol PendingMoneyWrite: Identifiable, Codable, Sendable where ID == UUID {
    var id: UUID { get }
    var serverID: UUID { get }
    var actorUserID: Int? { get }
    var idempotencyExpiresAt: Date? { get }
    var summary: PendingMoneyWriteSummary { get }
    /// Deterministic bytes: every retry of the record sends exactly these.
    func requestBody() throws -> Data
}
extension PendingMoneyWrite {
    /// Idempotency-Key = X-Request-ID (and a redeem batch's batch_id).
    public var key: String { id.uuidString.lowercased() }
    public var effectiveExpiresAt: Date? {
        idempotencyExpiresAt ?? summary.createdAt?.addingTimeInterval(IdempotencyPolicy.defaultExpiry)
    }
    public var line: PendingMoneyWriteLine { PendingMoneyWriteLine(summary) }
}

/// Proof that a money write's record is on disk (00 §0 rule 4): money-write methods only accept this, and the only way to get
/// one is a `persist` that did not throw. AppModel.persisted is the production caller.
public struct PersistedMoneyWrite<Record: PendingMoneyWrite>: Sendable {
    public let record: Record
    public init(_ record: Record, persist: (Record) throws -> Void) rethrows {
        try persist(record)
        self.record = record
    }
}

/// The only title and detail line of a pending money write (00 §2.5.5, R02). The caller formats the amount and passes the
/// relative time from DisplayFormat.
public struct PendingMoneyWriteLine: Sendable, Equatable {
    public enum Amount: Sendable, Equatable { case money(Decimal), allBalance }
    public static let allBalanceText = "全部余额"
    public let title: String
    /// Right-hand amount; nil for non-money compensations and batches without a total.
    public let amount: Amount?
    public let object: String
    /// 入账 / 生成 / 发放.
    public let verb: String
    public init(_ summary: PendingMoneyWriteSummary) {
        switch summary.subject {
        case .balance(let operation, let amount):
            title = operation == .add ? "充值结果待核对" : operation == .subtract || amount == 0 ? "退款结果待核对" : "余额设置结果待核对"
            self.amount = operation == .set && amount == 0 ? .allBalance : .money(amount)
            verb = "入账"
        case .redeemBatch(let count, let total):
            title = "兑换码生成结果待核对"; amount = total.map(Amount.money); verb = "生成"
            object = "\(count) 个"; return
        case .compensation(let type, let value):
            title = "补偿结果待核对"; amount = type == .balance ? .money(value) : nil; verb = "发放"
        }
        object = Self.userLabel(summary)
    }
    /// “<对象> · <相对时间> · 未确认是否<动词>”; a legacy record without createdAt leaves the time out.
    public func detail(relativeTime: String?) -> String {
        [object, relativeTime, "未确认是否" + verb].compactMap { $0 }.joined(separator: " · ")
    }
    private static func userLabel(_ summary: PendingMoneyWriteSummary) -> String {
        for candidate in [summary.userDisplayName, summary.userEmail] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return summary.userID.map { "用户 #\($0)" } ?? "用户"
    }
}

public enum CompensationType: String, Codable, CaseIterable, Sendable { case balance, concurrency, subscription }

/// POST admin/redeem-codes/create-and-redeem (60 §19.2): the App-generated `code` dedupes on the server, the key guards the request.
public struct PendingCompensation: PendingMoneyWrite, Equatable {
    public let id: UUID
    public let serverID: UUID
    public let actorUserID: Int?
    public let createdAt: Date
    public let idempotencyExpiresAt: Date?
    public let userID: Int
    public let userDisplayName: String
    public let userEmail: String
    public let code: String
    public let type: CompensationType
    /// Balance in USD, concurrency increase, or the subscription's validity days (the server rejects 0).
    public let value: Decimal
    public let groupID: Int?
    public let validityDays: Int?
    public let notes: String
    public init(id: UUID = UUID(), serverID: UUID, actorUserID: Int?, createdAt: Date = Date(), idempotencyExpiresAt: Date? = nil, userID: Int,
                userDisplayName: String, userEmail: String, code: String, type: CompensationType, value: Decimal, groupID: Int? = nil,
                validityDays: Int? = nil, notes: String = "") {
        self.id = id; self.serverID = serverID; self.actorUserID = actorUserID; self.createdAt = createdAt
        self.idempotencyExpiresAt = idempotencyExpiresAt; self.userID = userID; self.userDisplayName = userDisplayName; self.userEmail = userEmail
        self.code = code; self.type = type; self.value = value; self.groupID = groupID; self.validityDays = validityDays; self.notes = notes
    }
    public var summary: PendingMoneyWriteSummary {
        PendingMoneyWriteSummary(subject: .compensation(type, value: value), createdAt: createdAt, userID: userID,
                                 userDisplayName: userDisplayName, userEmail: userEmail)
    }
    /// Code 3–128 without outer whitespace; balance > 0 with at most 2 decimals; concurrency 1–50; subscription needs a group,
    /// 1–3650 days and value == days; notes at most 1000 characters.
    public func validate() throws {
        guard (3...128).contains(code.count), code.trimmingCharacters(in: .whitespacesAndNewlines) == code, userID > 0,
              notes.count <= 1_000, !value.isNaN, value > 0 else { throw Self.invalid }
        switch type {
        case .balance:
            guard groupID == nil, validityDays == nil, value.hasAtMostFractionDigits(2) else { throw Self.invalid }
        case .concurrency:
            guard groupID == nil, validityDays == nil, value <= 50, value.hasAtMostFractionDigits(0) else { throw Self.invalid }
        case .subscription:
            guard let groupID, groupID > 0, let validityDays, (1...3_650).contains(validityDays), value == Decimal(validityDays) else { throw Self.invalid }
        }
    }
    /// `value` is a JSON number encoded straight from Decimal (00 §6.1); the optional fields only for subscriptions.
    public func requestBody() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Body(code: code, groupID: groupID, notes: notes, type: type, userID: userID, validityDays: validityDays, value: value))
    }
    private static let invalid = APIError(kind: .validation, message: "补偿内容不符合要求，请检查兑换码、数值、分组、天数与备注。")
    private struct Body: Encodable {
        let code: String; let groupID: Int?; let notes: String; let type: CompensationType; let userID: Int; let validityDays: Int?; let value: Decimal
        enum CodingKeys: String, CodingKey { case code, notes, type, value, groupID = "group_id", userID = "user_id", validityDays = "validity_days" }
    }
}
