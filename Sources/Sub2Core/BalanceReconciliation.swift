import Foundation

/// What the ledger says about one pending balance write (00 §2.5.5, D25). Only `executed` confirms anything.
public enum BalanceReconcileOutcome: Sendable, Equatable {
    /// The ledger row of this write: shows before_value → after_value.
    case executed(UserAdjustment)
    /// Not in the ledger and older than the execution grace: the same number may be retried.
    case notExecuted
    /// Not in the ledger yet, but sent less than 40 seconds ago: the server may still be running it.
    case stillRunning
    /// A record saved before S0-06 (no createdAt) that was not found: no conclusion, the page asks for a manual check.
    case notFound
}

/// 00 §2.5.5 and 30 §3.4 as pure functions: a row is this write only when the user matches and its action_id or request_id
/// does, because an old server ignores the filters and `keyword` matches emails loosely. Stage 3 adds the candidate match,
/// the request-id echo check and the legacy-record query in this file.
public enum BalanceReconciliation {
    /// The server runs a keyed money write for up to 30 seconds after the connection is gone; 10 more as margin.
    public static let executionGrace: TimeInterval = 40
    /// The fallback window starts this long before the write was sent.
    public static let lookback: TimeInterval = 120
    public static let firstPageSize = 20

    /// By action_id when a reply carried one, otherwise by request_id; nil for a legacy record without either.
    public static func firstQuery(for op: PendingBalanceOperation) -> UserAdjustmentQuery? {
        var query = UserAdjustmentQuery()
        query.userID = op.userID; query.pageSize = firstPageSize
        if let actionID = op.actionID { query.actionID = actionID }
        else if let requestID = op.requestID { query.requestID = requestID }
        else { return nil }
        return query
    }
    /// The old-server fallback: the full email from two minutes before the write to now, in server time (`clockOffset` is
    /// server minus phone, 00 §6.3). The end never precedes the start, which the server would reject. nil without createdAt
    /// or a usable email.
    public static func fallbackQuery(for op: PendingBalanceOperation, now: Date, clockOffset: TimeInterval = 0) -> UserAdjustmentQuery? {
        guard let createdAt = op.createdAt, let email = op.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty,
              email.count <= UserAdjustmentQuery.maximumKeywordLength else { return nil }
        let start = createdAt.addingTimeInterval(clockOffset - lookback)
        var query = UserAdjustmentQuery()
        query.keyword = email; query.pageSize = UserAdjustmentQuery.maximumPageSize
        query.startTime = start; query.endTime = max(now.addingTimeInterval(clockOffset), start.addingTimeInterval(1))
        return query
    }
    public static func isExactMatch(_ row: UserAdjustment, for op: PendingBalanceOperation) -> Bool {
        guard row.kind == "balance", row.userID == op.userID else { return false }
        if let actionID = op.actionID, row.actionID.flatMap(UUID.init(uuidString:)) == actionID { return true }
        if let requestID = op.requestID, row.requestID == requestID { return true }
        return false
    }
    /// `rows` are all rows both queries returned; `now` is phone time, like createdAt.
    public static func evaluate(_ op: PendingBalanceOperation, rows: [UserAdjustment], now: Date) -> BalanceReconcileOutcome {
        if let row = rows.first(where: { isExactMatch($0, for: op) }) { return .executed(row) }
        guard let createdAt = op.createdAt else { return .notFound }
        return now.timeIntervalSince(createdAt) < executionGrace ? .stillRunning : .notExecuted
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
}

extension APIClient {
    /// Only reads: the first query, and the fallback only when the first has no exact match. A failed query is thrown.
    public func reconcileBalance(_ op: PendingBalanceOperation) async throws -> BalanceReconcileOutcome {
        guard op.serverID == server.id else { throw APIError.stationMismatch }
        let now = serverClock.localNow()
        var rows = [UserAdjustment]()
        if let first = BalanceReconciliation.firstQuery(for: op) {
            rows = try await userAdjustments(query: first).items
            if let row = rows.first(where: { BalanceReconciliation.isExactMatch($0, for: op) }) { return .executed(row) }
        }
        if let fallback = BalanceReconciliation.fallbackQuery(for: op, now: now, clockOffset: serverClock.offset) {
            rows += try await userAdjustments(query: fallback).items
        }
        return BalanceReconciliation.evaluate(op, rows: rows, now: now)
    }
}
