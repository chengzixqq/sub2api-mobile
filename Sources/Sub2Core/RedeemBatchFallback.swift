import Foundation

/// What the newest codes of a server without batches say about a pending batch (60 §11.4 末条, U43). A guess, never a
/// confirmation: the record stays until the administrator taps “我已核对” or gives the batch up.
public enum RedeemBatchFallbackOutcome: Sendable, Equatable {
    /// As many matching codes as the batch asked for, by id ascending.
    case likelyGenerated([AdminRedeemCode])
    case countMismatch([AdminRedeemCode])
    case notFound
    /// The page was full and its oldest code still inside the window: the batch may lie beyond it.
    case inconclusive
}

/// 60 §11.4 末条: without `redeem_codes.stats`, or when the server ignored `batch_id`, the newest codes of the batch's type
/// are matched by face value, group and days, expiry, sender and creation time instead.
public enum RedeemBatchFallback {
    /// “发起后 2 分钟内”, on both sides of the window for clock skew.
    public static let margin: TimeInterval = 120
    public static let pageSize = 100
    public static let ambiguityNote = "另一位管理员同时生成时可能分不清"

    /// `created_at` descending; `type` is the filter old servers know, and it also keeps admin adjustments out.
    public static func query(for batch: PendingRedeemBatch) -> RedeemCodeListQuery {
        RedeemCodeListQuery(type: batch.spec.type, pageSize: pageSize, sortBy: "created_at", ascending: false)
    }
    /// Server time, from `margin` before the record was made to `margin` after its last send (a retry may have run it).
    public static func window(for batch: PendingRedeemBatch, sentAt: Date?, clockOffset: TimeInterval) -> ClosedRange<Date> {
        let last = max(batch.createdAt, sentAt ?? batch.createdAt)
        return batch.createdAt.addingTimeInterval(clockOffset - margin)...last.addingTimeInterval(clockOffset + margin)
    }
    public static func matches(_ code: AdminRedeemCode, batch: PendingRedeemBatch, window: ClosedRange<Date>) -> Bool {
        guard code.type == batch.spec.type.rawValue, let createdAt = code.createdAt, window.contains(createdAt) else { return false }
        // Another batch's code, or one made by someone else, is not this batch even on a server that keeps both.
        if let other = code.batchID, other != batch.id { return false }
        if let actor = batch.actorUserID, let sender = code.createdBy, actor != sender { return false }
        return matchesValue(code, spec: batch.spec) && matchesExpiry(code, spec: batch.spec, createdAt: createdAt) && matchesNotes(code, spec: batch.spec)
    }
    public static func evaluate(_ batch: PendingRedeemBatch, items: [AdminRedeemCode], sentAt: Date?, clockOffset: TimeInterval) -> RedeemBatchFallbackOutcome {
        let window = window(for: batch, sentAt: sentAt, clockOffset: clockOffset)
        let found = items.filter { matches($0, batch: batch, window: window) }.sorted { $0.id < $1.id }
        if found.count == batch.count { return .likelyGenerated(found) }
        if items.count >= pageSize, let oldest = items.compactMap(\.createdAt).min(), oldest >= window.lowerBound { return .inconclusive }
        return found.isEmpty ? .notFound : .countMismatch(found)
    }

    private static func matchesValue(_ code: AdminRedeemCode, spec: RedeemGenerateSpec) -> Bool {
        switch spec.type {
        case .balance, .concurrency: code.value == spec.value
        case .subscription: code.groupID == spec.groupID && code.validityDays == spec.validityDays
        case .invitation: true
        }
    }
    /// The server stamps expires_at from the same clock as created_at, N × 24 hours later.
    private static func matchesExpiry(_ code: AdminRedeemCode, spec: RedeemGenerateSpec, createdAt: Date) -> Bool {
        guard let days = spec.expiresInDays else { return code.expiresAt == nil }
        guard let expiresAt = code.expiresAt else { return false }
        return abs(expiresAt.timeIntervalSince(createdAt) - TimeInterval(days) * 86_400) <= margin
    }
    /// A server from before notes keeps none, so only two notes that both exist must agree.
    private static func matchesNotes(_ code: AdminRedeemCode, spec: RedeemGenerateSpec) -> Bool {
        guard let notes = RedeemPresentation.trimmed(code.notes), let asked = RedeemPresentation.trimmed(spec.notes) else { return true }
        return notes == asked
    }
}

extension APIClient {
    /// Only reads, with the current identity, a record of this site or of an older login at its address (C-26). The window
    /// follows the server clock; `sentAt` is the batch's last send (its saved `lastSentAt`).
    public func reconcileRedeemBatchFallback(_ batch: PendingRedeemBatch, sentAt: Date? = nil, sameAddress: Set<UUID>) async throws -> RedeemBatchFallbackOutcome {
        try MoneyRecordOrigin.check(recordServerID: batch.serverID, currentServerID: server.id, sameAddress: sameAddress)
        let page = try await redeemCodes(page: 1, query: RedeemBatchFallback.query(for: batch))
        return RedeemBatchFallback.evaluate(batch, items: page.items, sentAt: sentAt, clockOffset: serverClock.offset)
    }
    /// A stored replay masks its codes (`***`): each one is read again by id, one at a time, in order; a code gone throws.
    public func revealingRedactedCodes(_ codes: [AdminRedeemCode]) async throws -> [AdminRedeemCode] {
        var revealed: [AdminRedeemCode] = []
        for code in codes { revealed.append(code.isRedacted ? try await redeemCode(id: code.id) : code) }
        return revealed
    }
}
