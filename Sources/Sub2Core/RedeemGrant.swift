import Foundation
#if canImport(Security)
import Security
#endif

// 60 §19 “发放兑换码（补偿）” (S6-08): the code, the draft and its numbering, what may be granted, the subscription plan,
// the result table and the one send. The sheet (S6-09) and the session wiring (AppModel+BalanceReconcile) use these.

/// The App-made code of a compensation (60 §19.2): 16 random bytes as 32 lowercase hex digits, the shape of the server's own
/// codes. It is worth money: logs, receipts and test failures show only RedeemPresentation.shortCode.
public enum RedeemCode {
    public typealias ByteSource = @Sendable (Int) throws -> [UInt8]
    static let byteCount = 16
    static let failure = APIError(kind: .validation, message: "无法生成兑换码，请重试。")

    /// SecRandomCopyBytes (nil is kSecRandomDefault); the system generator where Security does not exist (Linux CI).
    public static let secureBytes: ByteSource = { count in
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        guard SecRandomCopyBytes(nil, count, &bytes) == errSecSuccess else { throw RedeemCode.failure }
        #else
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = generator.next() }
        #endif
        return bytes
    }
    public static func random(using source: ByteSource = secureBytes) throws -> String {
        guard let bytes = try? source(byteCount), bytes.count == byteCount else { throw failure }
        return bytes.map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }
    public static func isWellFormed(_ code: String) -> Bool { code.utf8.count == byteCount * 2 && code.utf8.allSatisfy { hexDigits.contains($0) } }
    private static let hexDigits = Set("0123456789abcdef".utf8)
}

/// What the sheet grants (60 §19.2): USD balance, a concurrency increase, or a subscription group and its days; and notes.
public struct RedeemGrantDraft: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case balance(Decimal)
        case concurrency(Int)
        case subscription(groupID: Int, days: Int)
    }
    public static let concurrencyRange = 1...50
    public static let daysRange = 1...3_650
    /// Counted in Unicode scalars, as the server counts runes (S6D1-15).
    public static let notesLimit = 1_000
    static let notesTooLong = APIError(kind: .validation, message: "备注最多 1000 字。")

    public let value: Value
    /// Without outer whitespace; empty is sent as "".
    public let notes: String
    public init(value: Value, notes: String = "") {
        self.value = value
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var type: CompensationType {
        switch value {
        case .balance: .balance
        case .concurrency: .concurrency
        case .subscription: .subscription
        }
    }
    /// Balance above 0 with at most two decimals, concurrency 1–50, a subscription group with 1–3650 days, notes ≤ 1000.
    public var isValid: Bool {
        guard notes.unicodeScalars.count <= Self.notesLimit else { return false }
        switch value {
        case .balance(let amount): return !amount.isNaN && amount > 0 && amount.hasAtMostFractionDigits(2)
        case .concurrency(let count): return Self.concurrencyRange.contains(count)
        case .subscription(let groupID, let days): return groupID > 0 && Self.daysRange.contains(days)
        }
    }
    /// The record saved before the send (00 §0 rule 4). A subscription's value is its days, which the server requires to be
    /// non-zero; the bytes come from PendingCompensation.requestBody (S0-06) and are never encoded here.
    public func compensation(id: UUID, serverID: UUID, actorUserID: Int?, createdAt: Date, user: AdminUser, code: String) throws -> PendingCompensation {
        guard notes.unicodeScalars.count <= Self.notesLimit else { throw Self.notesTooLong }
        let (amount, groupID, days): (Decimal, Int?, Int?) = switch value {
        case .balance(let amount): (amount, nil, nil)
        case .concurrency(let count): (Decimal(count), nil, nil)
        case .subscription(let groupID, let days): (Decimal(days), groupID, days)
        }
        let grant = PendingCompensation(id: id, serverID: serverID, actorUserID: actorUserID, createdAt: createdAt, userID: user.id,
                                        userDisplayName: user.displayName, userEmail: user.email, code: code, type: type, value: amount,
                                        groupID: groupID, validityDays: days, notes: notes)
        try grant.validate()
        return grant
    }
}

/// 60 §19.4 steps 2 and 5 (R05): the code is made when the sheet opens; each confirmation makes a new key (also X-Request-ID
/// and the record id). Once a grant went out, any edit takes a new code too: the old code may already exist on the server
/// with the old content, and reusing it would redeem that.
public struct GrantDraftState: Sendable, Equatable {
    public let code: String
    public let key: UUID?
    public let hasSent: Bool
    public init(code: String, key: UUID? = nil, hasSent: Bool = false) { self.code = code; self.key = key; self.hasSent = hasSent }

    public static func opening(using source: RedeemCode.ByteSource = RedeemCode.secureBytes) throws -> GrantDraftState {
        GrantDraftState(code: try RedeemCode.random(using: source))
    }
    /// Type, value, group, days or notes changed.
    public func edited(newCode: () throws -> String) rethrows -> GrantDraftState {
        hasSent ? GrantDraftState(code: try newCode()) : self
    }
    public func confirmed(key: UUID = UUID()) -> GrantDraftState { GrantDraftState(code: code, key: key, hasSent: hasSent) }
    public func sent() -> GrantDraftState { GrantDraftState(code: code, key: key, hasSent: true) }
    /// REDEEM_CODE_CONFLICT / REDEEM_CODE_EXPIRED: back to step 3 with a new code, confirmed again.
    public func renumbered(code: String) -> GrantDraftState { GrantDraftState(code: code) }
    /// The subscription group that would go out (60 §19.3 “默认第一个”). Once a grant went out, only the one chosen, which the
    /// sheet pins when it sends: falling back to another group in silence would send the old code, made with the old group.
    public func group(chosen id: Int?, in groups: [AdminGroup]) -> AdminGroup? {
        let chosen = groups.first { $0.id == id }
        return hasSent ? chosen : chosen ?? groups.first
    }
}

/// The type tiles of step 1 (60 §19.3, U52).
public struct GrantAvailability: Sendable, Equatable {
    /// 0 is “unlimited” (concurrency_service.go): a grant would add a limit.
    public static let unlimitedConcurrency = "这个用户并发不限制，发放后反而会变成有上限"
    public static let noSubscriptionGroups = "没有订阅类型的分组"
    public let userConcurrency: Int?
    /// The caller decides with `groups.contains(where: \.isActiveSubscriptionGroup)` (S6-03).
    public let hasSubscriptionGroups: Bool
    public init(user: AdminUser, hasSubscriptionGroups: Bool) {
        userConcurrency = user.concurrency; self.hasSubscriptionGroups = hasSubscriptionGroups
    }
    /// Why the tile is greyed; nil when it may be granted.
    public func reason(for type: CompensationType) -> String? {
        switch type {
        case .balance: nil
        case .concurrency: userConcurrency == 0 ? Self.unlimitedConcurrency : nil
        case .subscription: hasSubscriptionGroups ? nil : Self.noSubscriptionGroups
        }
    }
    public func isAvailable(_ type: CompensationType) -> Bool { reason(for: type) == nil }
}

/// What a subscription grant does to the user's row of that group (60 §19.3; subscription_service.go): the server keeps one row
/// per user and group, extends one that has not ended from its end, and starts one that ended or does not exist from now.
/// Only for display: the server's result wins.
public struct SubscriptionGrantPlan: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case new, extend
        /// Not ended but not active (suspended…): extended and active again.
        case resume
        /// Ended (or without an end): from today, usage reset.
        case renew
    }
    /// MaxExpiresAt of subscription_service.go.
    public static let maxExpiry = Date(timeIntervalSince1970: 4_102_444_799)
    public let kind: Kind
    public let currentExpiry: Date?
    public let newExpiry: Date
    public init(kind: Kind, currentExpiry: Date?, newExpiry: Date) { self.kind = kind; self.currentExpiry = currentExpiry; self.newExpiry = newExpiry }

    /// `now` is the server-corrected clock; days are added on the server's calendar (`timeZone`), like the backend's AddDate.
    public static func make(rows: [AdminUserSubscription], groupID: Int, days: Int, now: Date, timeZone: TimeZone) -> SubscriptionGrantPlan {
        let row = rows.filter { $0.groupID == groupID }.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
        guard let row else { return plan(.new, current: nil, from: now, days: days, timeZone: timeZone) }
        guard let end = row.expiresAt, end > now else { return plan(.renew, current: row.expiresAt, from: now, days: days, timeZone: timeZone) }
        return plan(row.status == "active" ? .extend : .resume, current: end, from: end, days: days, timeZone: timeZone)
    }
    private static func plan(_ kind: Kind, current: Date?, from start: Date, days: Int, timeZone: TimeZone) -> SubscriptionGrantPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
        return SubscriptionGrantPlan(kind: kind, currentExpiry: current, newExpiry: min(end, maxExpiry))
    }
}

// MARK: The result (60 §19.4 with R01, R04, S6D1-08)

/// One create-and-redeem call, first send or “用同一编号重试”. Every action but `pending` resolves the record.
public enum GrantResultAction: Sendable, Equatable {
    /// 2xx, a replay or X-Idempotency-Degraded. A replay's code may be `***`: the record's own code is the one to show.
    case granted(AdminRedeemCode, replayed: Bool)
    /// REDEEM_CODE_CONFLICT / REDEEM_CODE_EXPIRED: back to step 3 with a new code and key (GrantDraftState.renumbered).
    case renumber(message: String)
    /// GROUP_NOT_SUBSCRIPTION_TYPE / GROUP_NOT_FOUND: back to step 2, the group directory read again.
    case backToValue(message: String)
    /// USER_NOT_FOUND: the sheet closes.
    case userGone(message: String)
    /// A key the server will not take (a defect, 00 §2.5.3): confirmed again under a new key with the same code, which the
    /// server dedupes, so nothing is granted twice.
    case newKeyNeeded(message: String)
    /// A first send turned away by a security prompt the administrator then cleared: resolved, and the same record (id and
    /// bytes) is confirmed again.
    case reconfirm(message: String)
    /// Not granted. `reportsDefect`: the App should never send what the server refused (00 §3.3 “请求无效”), reported without the code.
    case rejected(message: String, reportsDefect: Bool)
    /// The server may have granted it: the record stays to be checked, retried not before `retryNotBefore`.
    case pending(message: String, retryNotBefore: Date?)

    public var resolvesRecord: Bool {
        if case .pending = self { return false }
        return true
    }

    static let conflictMessage = "兑换码编号冲突，已换新编号，请重新确认"
    static let expiredMessage = "这个兑换码已失效，已换新编号，请重新确认"
    static let groupMessage = "这个分组不能用于订阅，请重新选择"

    public static func classify(_ outcome: WriteOutcome<AdminRedeemCode>) -> GrantResultAction {
        .granted(outcome.value, replayed: outcome.replayed || outcome.recovered)
    }
    /// `retrying`: the record went out before, so that attempt may have run; then only the server's answer about this code
    /// settles it.
    public static func classify(_ error: any Error, retrying: Bool) -> GrantResultAction {
        if let failure = error as? KeyedWriteFailure { return action(of: failure, retrying: retrying) }
        guard let error = error as? APIError else { return pending() }
        if let answer = answerAboutCode(error) { return answer }
        return retrying ? pending(error.securityOutcome == .passed ? error.localizedDescription : BalanceReconciliation.unconfirmedReceipt)
            : firstSend(error)
    }
    public static func classify(_ result: Result<WriteOutcome<AdminRedeemCode>, any Error>, retrying: Bool) -> GrantResultAction {
        switch result {
        case .success(let outcome): classify(outcome)
        case .failure(let error): classify(error, retrying: retrying)
        }
    }

    /// The server looks the code up before anything else (redeem_handler.go), so these say the code was not redeemed for
    /// this user, on any attempt.
    static func answerAboutCode(_ error: APIError) -> GrantResultAction? {
        switch (error.statusCode, error.reason) {
        case (409?, "REDEEM_CODE_CONFLICT"?): .renumber(message: conflictMessage)
        case (409?, "REDEEM_CODE_EXPIRED"?): .renumber(message: expiredMessage)
        case (400?, "GROUP_NOT_SUBSCRIPTION_TYPE"?), (404?, "GROUP_NOT_FOUND"?): .backToValue(message: groupMessage)
        case (404?, "USER_NOT_FOUND"?): .userGone(message: BalanceReconciliation.userMissingMessage)
        case (400?, "REDEEM_CODE_UNSUPPORTED_TYPE"?): .rejected(message: error.localizedDescription, reportsDefect: true)
        default: nil
        }
    }
    static func isLocked(_ error: APIError) -> Bool { error.statusCode == 409 && error.reason == "REDEEM_CODE_LOCKED" }

    private static func pending(_ message: String = BalanceReconciliation.unconfirmedReceipt) -> GrantResultAction {
        .pending(message: message, retryNotBefore: nil)
    }
    private static func action(of failure: KeyedWriteFailure, retrying: Bool) -> GrantResultAction {
        switch failure.disposition {
        case .unconfirmed(.storeUnavailable, let date): .pending(message: BalanceReconciliation.storeUnavailableMessage, retryNotBefore: date)
        case .unconfirmed(_, let date): .pending(message: BalanceReconciliation.unconfirmedReceipt, retryNotBefore: date)
        case .needsNewKey(.keyConflict) where retrying: pending(BalanceReconciliation.keyConflictMessage)
        case .needsNewKey: .newKeyNeeded(message: failure.localizedDescription)
        }
    }
    /// Nothing went out before: a refusal of this attempt, a local check or a body without a reason settles it.
    private static func firstSend(_ error: APIError) -> GrantResultAction {
        if error.securityOutcome == .passed { return .reconfirm(message: error.localizedDescription) }
        if error.statusCode == 400, error.reason == nil { return .rejected(message: error.localizedDescription, reportsDefect: true) }
        if error.isRefusedBeforeHandler || (error.statusCode == nil && error.kind == .validation) {
            return .rejected(message: error.localizedDescription, reportsDefect: false)
        }
        return pending()
    }
}

public enum RedeemGrantPolicy {
    /// 60 §19.4 REDEEM_CODE_LOCKED: the same key and bytes go once more after this.
    public static let lockedRetryDelay: Duration = .seconds(2)
}

extension APIClient {
    /// `POST admin/redeem-codes/create-and-redeem` under the record's number (R01, R04): Idempotency-Key = X-Request-ID = record
    /// id, the same bytes on every attempt, 35 seconds; transport failures retried twice and IN_PROGRESS waited for 30 seconds
    /// by performKeyedWrite. A record of this site or of an older login at its address goes out (X34); the sender check is the
    /// caller's (MoneyRecordOrigin.checkSender, S3D1-16). REDEEM_CODE_LOCKED is sent once more after two seconds.
    public func createAndRedeem(_ write: PersistedMoneyWrite<PendingCompensation>, sameAddress: Set<UUID>,
                                onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminRedeemCode> {
        let grant = write.record
        try MoneyRecordOrigin.check(recordServerID: grant.serverID, currentServerID: server.id, sameAddress: sameAddress)
        let body = try grant.requestBody()
        let request = KeyedWriteRequest(path: "admin/redeem-codes/create-and-redeem", method: "POST", body: body, key: grant.id)
        let snapshot = currentGeneration()
        do { return try await redeemOnce(request, onEvent: onEvent) }
        catch let locked as APIError where GrantResultAction.isLocked(locked) {
            try await waitAfterLock(locked, key: grant.key, generation: snapshot)
            return try await redeemAfterLock(request, onEvent: onEvent)
        }
    }

    private func redeemOnce(_ request: KeyedWriteRequest, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminRedeemCode> {
        let reply: WriteOutcome<CreateAndRedeemReply> = try await performKeyedWrite(request, onEvent: onEvent)
        return WriteOutcome(value: reply.value.redeemCode, replayed: reply.replayed, recovered: reply.recovered, degraded: reply.degraded,
                            expiresAt: reply.expiresAt, actionID: reply.actionID, batchID: reply.batchID, requestID: reply.requestID)
    }
    /// Suspended during the wait (D18): the lock's holder may be running this grant, so it stays to be checked.
    private func waitAfterLock(_ locked: APIError, key: String, generation snapshot: UUID) async throws {
        do { try await pause(RedeemGrantPolicy.lockedRetryDelay, generation: snapshot) }
        catch is CancellationError where currentGeneration() == snapshot && !Task.isCancelled {
            throw KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: key, actionID: nil, lastError: locked)
        }
    }
    /// After a lock only a success or the server's answer about this code settles the grant; a second lock is still
    /// processing, anything else says nothing about the holder's run.
    private func redeemAfterLock(_ request: KeyedWriteRequest, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminRedeemCode> {
        do { return try await redeemOnce(request, onEvent: onEvent) }
        catch let error as APIError where GrantResultAction.answerAboutCode(error) == nil {
            let cause: KeyedWriteFailure.UnconfirmedCause = GrantResultAction.isLocked(error) ? .stillProcessing : .transport
            throw KeyedWriteFailure(disposition: .unconfirmed(cause, retryNotBefore: nil), key: request.key.uuidString.lowercased(),
                                    actionID: error.actionID, lastError: error)
        }
    }
}

/// `data` of create-and-redeem: `{"redeem_code": AdminRedeemCode}` without user or group.
private struct CreateAndRedeemReply: Decodable, Sendable {
    let redeemCode: AdminRedeemCode
    enum CodingKeys: String, CodingKey { case redeemCode = "redeem_code" }
}
