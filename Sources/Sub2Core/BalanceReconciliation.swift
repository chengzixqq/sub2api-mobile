import Foundation

/// What the ledger says about one pending balance write (00 §2.5.5, 30 §3.4, D25). Only `executed` confirms anything.
public enum BalanceReconcileOutcome: Sendable, Equatable {
    /// The ledger row of this write: shows before_value → after_value.
    case executed(UserAdjustment)
    /// Not in the ledger and older than the execution grace: the same number may be retried.
    case notExecuted
    /// Not in the ledger yet, but sent less than 40 seconds ago: the server may still be running it.
    case stillRunning
    /// Without a usable request id or an action id only these remain: one row that may be this write, shown to the administrator
    /// and never resolved on its own (an “仍要充值” write of the same amount and notes matches as well).
    case candidate(UserAdjustment)
    case ambiguous([UserAdjustment])
    /// Nothing to conclude from: the fallback query could not be sent, or its page was cut off without a match.
    case notFound
}

/// What the fallback query saw: all of its window, only the first page of it, or nothing (no usable email).
public enum FallbackCoverage: Sendable, Equatable { case complete, truncated, unavailable }

/// 00 §2.5.5 and 30 §3.4 as pure functions: a row is this write only when the user matches and its action_id or request_id
/// does, because an old server ignores the filters and `keyword` matches emails loosely. A site whose proxy rewrites
/// X-Request-ID (SiteFlags) matches by action_id only and falls back to candidates.
public enum BalanceReconciliation {
    /// The server runs a keyed money write for up to 30 seconds after the connection is gone; 10 more as margin.
    public static let executionGrace: TimeInterval = 40
    /// The fallback window starts this long before the write was sent.
    public static let lookback: TimeInterval = 120
    public static let firstPageSize = 20

    /// By action_id when a reply carried one, otherwise by request_id when the site keeps it; nil for a legacy record and for
    /// an unusable request id without an action id.
    public static func firstQuery(for op: PendingBalanceOperation, requestIDUsable: Bool = true) -> UserAdjustmentQuery? {
        var query = UserAdjustmentQuery()
        query.userID = op.userID; query.pageSize = firstPageSize
        if let actionID = op.actionID { query.actionID = actionID }
        else if requestIDUsable, let requestID = op.requestID { query.requestID = requestID }
        else { return nil }
        return query
    }
    /// The old-server fallback: the full email from two minutes before the write to now, in server time (`clockOffset` is
    /// server minus phone, 00 §6.3). The end never precedes the start, which the server would reject. A legacy record has
    /// neither, so its user id is the keyword and there is no start. nil for a new record without a usable email.
    public static func fallbackQuery(for op: PendingBalanceOperation, now: Date, clockOffset: TimeInterval = 0) -> UserAdjustmentQuery? {
        var query = UserAdjustmentQuery()
        query.pageSize = UserAdjustmentQuery.maximumPageSize
        guard let createdAt = op.createdAt else {
            query.keyword = String(op.userID); query.endTime = now.addingTimeInterval(clockOffset)
            return query
        }
        guard let email = op.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty,
              email.count <= UserAdjustmentQuery.maximumKeywordLength else { return nil }
        let start = createdAt.addingTimeInterval(clockOffset - lookback)
        query.keyword = email
        query.startTime = start; query.endTime = max(now.addingTimeInterval(clockOffset), start.addingTimeInterval(1))
        return query
    }
    public static func isExactMatch(_ row: UserAdjustment, for op: PendingBalanceOperation, requestIDUsable: Bool = true) -> Bool {
        guard row.kind == "balance", row.userID == op.userID else { return false }
        if let actionID = op.actionID, row.actionID.flatMap(UUID.init(uuidString:)) == actionID { return true }
        if requestIDUsable, let requestID = op.requestID, row.requestID == requestID { return true }
        return false
    }
    /// 30 §3.4 候选匹配: same user, operation, requested amount (the “全部余额” refund is set / 0) and trimmed notes, the same
    /// operator when both sides have one, and created at most two minutes before the write (server time); a legacy record
    /// has no time to compare.
    public static func candidates(in rows: [UserAdjustment], for op: PendingBalanceOperation, clockOffset: TimeInterval = 0) -> [UserAdjustment] {
        let notes = op.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let earliest = op.createdAt?.addingTimeInterval(clockOffset - lookback)
        return rows.filter { row in
            guard row.kind == "balance", row.userID == op.userID, row.operation == op.operation.rawValue, row.requestedValue == op.amount,
                  (row.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == notes else { return false }
            if let sender = row.operatorUserID, let actor = op.actorUserID, sender != actor { return false }
            guard let earliest else { return true }
            return row.createdAt.map { $0 >= earliest } ?? false
        }
    }
    /// `rows` are all rows both queries returned; `now` is phone time, like createdAt. 30 §3.4 steps 3–4.
    public static func evaluate(_ op: PendingBalanceOperation, rows: [UserAdjustment], now: Date, requestIDUsable: Bool = true,
                                clockOffset: TimeInterval = 0, coverage: FallbackCoverage = .complete) -> BalanceReconcileOutcome {
        var seen = Set<Int>()
        let rows = rows.filter { seen.insert($0.id).inserted }
        if let row = rows.first(where: { isExactMatch($0, for: op, requestIDUsable: requestIDUsable) }) { return .executed(row) }
        if let start = op.graceStart, now.timeIntervalSince(start) < executionGrace { return .stillRunning }
        if op.actionID != nil || (requestIDUsable && op.requestID != nil) { return coverage == .complete ? .notExecuted : .notFound }
        guard coverage != .unavailable else { return .notFound }
        let found = candidates(in: rows, for: op, clockOffset: clockOffset)
        switch found.count {
        case 0: return coverage == .truncated ? .notFound : .notExecuted
        case 1: return .candidate(found[0])
        default: return .ambiguous(found)
        }
    }

    /// 30 §3.4 X-Request-ID 回显检查: true only when the reply echoed a different id. No header is no evidence.
    public static func requestIDEchoMismatch(sent: String, echoed: String?) -> Bool {
        guard let echoed = echoed?.trimmingCharacters(in: .whitespacesAndNewlines), !echoed.isEmpty else { return false }
        return echoed.lowercased() != sent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension PendingBalanceOperation {
    /// 30 §3.4 step 2, R05: the record is made when the write is confirmed. A form checked earlier keeps its number, body and
    /// action id but takes the confirmation time, which starts the execution grace and the fallback window. A legacy
    /// record is returned unchanged.
    public func confirmed(at date: Date) -> PendingBalanceOperation {
        guard !isLegacy else { return self }
        return PendingBalanceOperation(id: id, serverID: serverID, userID: userID, amount: amount, operation: operation, notes: notes,
                                       actorUserID: actorUserID, createdAt: date, userDisplayName: userDisplayName, userEmail: userEmail)
            .with(actionID: actionID)
    }
    /// The execution grace runs from the latest send; the fallback window stays at createdAt. A legacy record has a grace only
    /// after a retry.
    public var graceStart: Date? { [createdAt, lastSentAt].compactMap { $0 }.max() }
}

extension APIClient {
    /// Only reads, with the current identity: the first query, and the fallback only when the first has no exact match. A
    /// record of an older login at the same address is accepted (C-26); a failed query is thrown.
    public func reconcileBalance(_ op: PendingBalanceOperation, requestIDUsable: Bool = true, sameAddress: Set<UUID> = []) async throws -> BalanceReconcileOutcome {
        try MoneyRecordOrigin.check(recordServerID: op.serverID, currentServerID: server.id, sameAddress: sameAddress)
        let now = serverClock.localNow(), offset = serverClock.offset
        var rows = [UserAdjustment]()
        if let first = BalanceReconciliation.firstQuery(for: op, requestIDUsable: requestIDUsable) {
            rows = try await userAdjustments(query: first).items
            if let row = rows.first(where: { BalanceReconciliation.isExactMatch($0, for: op, requestIDUsable: requestIDUsable) }) { return .executed(row) }
        }
        var coverage = FallbackCoverage.unavailable
        if let fallback = BalanceReconciliation.fallbackQuery(for: op, now: now, clockOffset: offset) {
            let page = try await userAdjustments(query: fallback)
            rows += page.items
            coverage = page.hasMore ? .truncated : .complete
        }
        return BalanceReconciliation.evaluate(op, rows: rows, now: now, requestIDUsable: requestIDUsable, clockOffset: offset, coverage: coverage)
    }
    /// The send of “用同一编号重试” for a record of this site or of an older login at the same address (C-26). It checks the
    /// address only: APIClient does not know the administrator, so callers go through AppModel+Users.updateBalance, which
    /// runs MoneyRecordOrigin.checkSender first (S3D1-16).
    public func updateBalance(_ write: PersistedMoneyWrite<PendingBalanceOperation>, sameAddress: Set<UUID>,
                              onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        let operation = write.record
        try MoneyRecordOrigin.check(recordServerID: operation.serverID, currentServerID: server.id, sameAddress: sameAddress)
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/users/\(validID(operation.userID))/balance", method: "POST",
                                                             body: operation.requestBody(), key: operation.id), onEvent: onEvent)
    }
}

// MARK: The result of one balance write (30 §3.4 result table, R04)

/// `executed` and `notExecuted` resolve the record; `pending` keeps it for reconciliation.
public enum BalanceWriteOutcome: Sendable {
    case executed(AdminUser, replayed: Bool)
    case notExecuted(message: String)
    /// `retryNotBefore`: STORE_UNAVAILABLE's cooldown before the same number may go out again.
    case pending(message: String, retryNotBefore: Date?)
    public var resolvesRecord: Bool {
        if case .pending = self { return false }
        return true
    }
}

extension BalanceReconciliation {
    public static let unconfirmedReceipt = "结果未确认，已记为待核对"
    public static let keyConflictMessage = "这个操作编号已被另一笔请求占用，请先核对"
    public static let storeUnavailableMessage = "服务器暂时无法受理，稍后用同一编号重试"
    static let invalidBalanceMessage = "金额不合法，未入账"
    static let malformedRequestMessage = "请求格式错误，未入账"
    static let invalidRequestMessage = "请求无效（错误码 HTTP 400），未入账"
    static let userMissingMessage = "用户不存在或已删除"

    /// 200, including a replay and `X-Idempotency-Degraded`.
    public static func balanceWriteOutcome(for outcome: WriteOutcome<AdminUser>) -> BalanceWriteOutcome {
        .executed(outcome.value, replayed: outcome.replayed)
    }
    /// `retrying`: the record was sent before (it is already in the ledger), so that attempt may have run. Then a refusal of
    /// this attempt says nothing about it (S0-06); only a refusal decided by the body, which the earlier bytes got as well,
    /// still settles it. Within one call KeyedWriteFlow already keeps such a refusal unconfirmed.
    public static func balanceWriteOutcome(for error: any Error, retrying: Bool) -> BalanceWriteOutcome {
        if let failure = error as? KeyedWriteFailure { return outcome(of: failure.disposition) }
        guard let error = error as? APIError else { return .pending(message: unconfirmedReceipt, retryNotBefore: nil) }
        if let message = bodyRefusal(error, retrying: retrying) { return .notExecuted(message: message) }
        guard !retrying, let message = refusalBeforeExecution(error) else { return .pending(message: unconfirmedReceipt, retryNotBefore: nil) }
        return .notExecuted(message: message)
    }
    public static func balanceWriteOutcome(for result: Result<WriteOutcome<AdminUser>, any Error>, retrying: Bool) -> BalanceWriteOutcome {
        switch result {
        case .success(let outcome): balanceWriteOutcome(for: outcome)
        case .failure(let error): balanceWriteOutcome(for: error, retrying: retrying)
        }
    }

    /// 409 KEY_CONFLICT keeps the record to be checked (30 §3.4; the new write is confirmed again by the keypad, R04).
    private static func outcome(of disposition: KeyedWriteFailure.Disposition) -> BalanceWriteOutcome {
        switch disposition {
        case .needsNewKey(.keyConflict): .pending(message: keyConflictMessage, retryNotBefore: nil)
        case .needsNewKey: .notExecuted(message: malformedRequestMessage)
        case .unconfirmed(.storeUnavailable, let retryNotBefore): .pending(message: storeUnavailableMessage, retryNotBefore: retryNotBefore)
        case .unconfirmed(_, let retryNotBefore): .pending(message: unconfirmedReceipt, retryNotBefore: retryNotBefore)
        }
    }
    /// 400s the handler or the key check returns before executing, for these exact bytes. One without a reason may also be a
    /// proxy's page, which the earlier bytes did not get, so it settles a first send only.
    private static func bodyRefusal(_ error: APIError, retrying: Bool) -> String? {
        guard error.statusCode == 400 else { return nil }
        switch error.reason.flatMap({ $0.isEmpty ? nil : $0 }) {
        case nil: return retrying ? nil : invalidRequestMessage
        case "INVALID_BALANCE"?: return invalidBalanceMessage
        case "IDEMPOTENCY_KEY_INVALID"?, "IDEMPOTENCY_KEY_REQUIRED"?, "IDEMPOTENCY_PAYLOAD_INVALID"?: return malformedRequestMessage
        default: return nil
        }
    }
    /// A first send refused before it ran: another 400, 404 USER_NOT_FOUND, the middleware's 401 / 403 / 423 / 429 / step-up,
    /// or a local check. Anything else (5xx, 409, any other 404, which the handler never answers, statuses outside the table,
    /// transport) may have run.
    private static func refusalBeforeExecution(_ error: APIError) -> String? {
        switch error.statusCode {
        case 400?: return ReasonCatalog.entry(status: 400, reason: error.reason).message + "，未入账"
        case 404?: return error.reason == "USER_NOT_FOUND" ? userMissingMessage : nil
        case nil: return error.kind == .validation ? error.localizedDescription : nil
        default: return error.isRefusedBeforeHandler ? error.localizedDescription : nil
        }
    }
}
