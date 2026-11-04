import Foundation

// MARK: The form (60 §10.2–§10.3, D25)

extension RedeemCodeType {
    /// The type tiles of step 1.
    public var generateHint: String {
        switch self {
        case .balance: "余额金额（美元），兑换后计入用户余额。"
        case .concurrency: "并发数增量，兑换后提高用户的并发上限。"
        case .subscription: "兑换后开通或延长所选订阅分组。"
        case .invitation: "邀请码用于限制用户注册，使用后自动标记为已使用。"
        }
    }
}

/// The generate wizard's values. The full rules live only here; RedeemGenerateSpec keeps its basic checks, so a record
/// saved before a rule changed still encodes. Fields of the other types are ignored, not sent.
public struct RedeemGenerateForm: Sendable, Equatable {
    public enum Field: Sendable, Hashable { case value, concurrency, group, validityDays, count, expiresInDays, notes }
    public static let countRange = 1...100
    public static let dayRange = 1...3_650
    public static let concurrencyRange = 1...50
    public static let notesLimit = 1_000
    /// The keypad takes six whole digits (60 §10.3).
    public static let amountLimit: Decimal = 1_000_000

    public var type: RedeemCodeType
    /// USD per balance code; no default (BUILDER_GUIDE: money has no preset amount).
    public var amount: Decimal?
    public var concurrency: Int
    public var groupID: Int?
    public var groupName: String?
    public var validityDays: Int?
    public var count: Int
    /// nil = never expires.
    public var expiresInDays: Int?
    public var notes: String
    public init(type: RedeemCodeType = .balance, amount: Decimal? = nil, concurrency: Int = 1, groupID: Int? = nil, groupName: String? = nil,
                validityDays: Int? = 30, count: Int = 1, expiresInDays: Int? = nil, notes: String = "") {
        self.type = type; self.amount = amount; self.concurrency = concurrency; self.groupID = groupID; self.groupName = groupName
        self.validityDays = validityDays; self.count = count; self.expiresInDays = expiresInDays; self.notes = notes
    }

    public var invalidFields: Set<Field> {
        var fields = Set<Field>()
        switch type {
        case .balance: if !Self.isValidAmount(amount) { fields.insert(.value) }
        case .concurrency: if !Self.concurrencyRange.contains(concurrency) { fields.insert(.concurrency) }
        case .subscription:
            if (groupID ?? 0) <= 0 { fields.insert(.group) }
            if !(validityDays.map { Self.dayRange.contains($0) } ?? false) { fields.insert(.validityDays) }
        case .invitation: break
        }
        if !Self.countRange.contains(count) { fields.insert(.count) }
        if let expiresInDays, !Self.dayRange.contains(expiresInDays) { fields.insert(.expiresInDays) }
        // The server counts runes, which are Unicode scalars.
        if trimmedNotes.unicodeScalars.count > Self.notesLimit { fields.insert(.notes) }
        return fields
    }
    public var isValid: Bool { invalidFields.isEmpty }

    public func validated() throws -> RedeemGenerateSpec {
        guard isValid else { throw APIError(kind: .validation, message: "生成参数不符合要求，请检查面额、数量、有效期与备注。") }
        switch type {
        case .balance:
            return spec(value: amount ?? 0)
        case .concurrency:
            return spec(value: Decimal(concurrency))
        case .subscription:
            return RedeemGenerateSpec(type: type, value: 0, count: count, groupID: groupID, groupName: RedeemPresentation.trimmed(groupName),
                                      validityDays: validityDays, expiresInDays: expiresInDays, notes: trimmedNotes)
        case .invitation:
            return spec(value: 0)
        }
    }

    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func spec(value: Decimal) -> RedeemGenerateSpec {
        RedeemGenerateSpec(type: type, value: value, count: count, expiresInDays: expiresInDays, notes: trimmedNotes)
    }
    private static func isValidAmount(_ amount: Decimal?) -> Bool {
        guard let amount, !amount.isNaN else { return false }
        return amount > 0 && amount < amountLimit && amount.hasAtMostFractionDigits(2)
    }
}

/// Step 3's receipt, the confirmation and the one-line batch text (60 §10.3, §8.4, §11.3; S6D1-05). The expiry date is the
/// server's clock plus N × 24 hours, read on the server's calendar, as the server computes it.
public struct RedeemGenerateSummary: Sendable, Equatable {
    public let typeLabel: String
    /// “$10.00” / “+2 并发” / “企业专线 · 30 天” / “注册邀请”.
    public let each: String
    /// “× 20”.
    public let quantity: String
    /// “7 天后过期（10/23）” / “永不过期”.
    public let expiry: String
    /// Balance codes only.
    public let total: String?
    public let totalAmount: Decimal?
    /// “生成 20 个兑换码”.
    public let submitTitle: String
    public let confirmTitle: String
    public let confirmButton: String
    /// “20 个 × $10.00 · 合计 $200.00”: the list banner, the + interception and the pending receipt read this.
    public let batchLine: String
    /// Balance codes make money: the confirm button is red.
    public let isDestructive: Bool

    public init(spec: RedeemGenerateSpec, now: Date, timeZone: TimeZone) {
        typeLabel = spec.type.label
        each = Self.eachText(spec)
        quantity = "× \(spec.count)"
        expiry = spec.expiresInDays.map { days in
            let date = now.addingTimeInterval(TimeInterval(days) * 86_400)
            return "\(days) 天后过期（\(RedeemPresentation.day(date, now: now, timeZone: timeZone))）"
        } ?? "永不过期"
        totalAmount = spec.total
        total = spec.total.map { DisplayFormat.moneyExact($0) }
        submitTitle = "生成 \(spec.count) 个兑换码"
        let noun = spec.type == .invitation ? spec.type.label : spec.type.label + "兑换码"
        confirmTitle = "生成 \(spec.count) 个\(noun)" + (total.map { "，合计 \($0)" } ?? "") + "？"
        confirmButton = total.map { "生成 \($0)" } ?? "生成 \(spec.count) 个"
        batchLine = "\(spec.count) 个 × \(each)" + (total.map { " · 合计 \($0)" } ?? "")
        isDestructive = spec.type == .balance
    }
    /// “站点 主站 · 每个 $10.00\n7 天后过期（10/23）”, plus the Face ID line the page passes when it will ask.
    public func confirmMessage(siteName: String, faceIDLine: String?) -> String {
        ["站点 \(siteName) · 每个 \(each)", expiry, faceIDLine].compactMap { $0 }.joined(separator: "\n")
    }
    private static func eachText(_ spec: RedeemGenerateSpec) -> String {
        switch spec.type {
        case .balance: return DisplayFormat.moneyExact(spec.value)
        case .concurrency: return "+" + DisplayFormat.number(spec.value, minFraction: 0, maxFraction: nil) + " 并发"
        case .subscription:
            let group = RedeemPresentation.trimmed(spec.groupName) ?? spec.groupID.map { "分组 #\($0)" } ?? spec.type.label
            return group + " · " + (spec.validityDays.map(String.init) ?? DisplayFormat.missing) + " 天"
        case .invitation: return "注册邀请"
        }
    }
}

// MARK: The result (60 §10.4 with R04, S0-06, S6D1-08, S6D1-09)

/// One generate call, first send or a retry of the same number. Every outcome but `unconfirmed` resolves the record.
public enum RedeemGenerateResult: Sendable, Equatable {
    /// `batchConfirmed`: X-Redeem-Batch-ID named this batch (G03); an older server's replay has no header. `needsRefetch`:
    /// the codes came back masked and are read again by id before they are shown.
    case generated(codes: [AdminRedeemCode], replayed: Bool, batchConfirmed: Bool, needsRefetch: Bool)
    /// The server may have run it: keep the record; not before `retryNotBefore`.
    case unconfirmed(message: String, retryNotBefore: Date?)
    /// Not generated. `returnsToForm`: the body was refused, so the wizard goes back to step 3; otherwise the refusal (401,
    /// 403, 423, 429, a local check) is about the session, not the form.
    case rejected(message: String, returnsToForm: Bool)
    /// A first send turned away by a security prompt the administrator then cleared: resolve, and confirm the same record again.
    case reconfirm(notice: String)

    public var resolvesRecord: Bool {
        if case .unconfirmed = self { return false }
        return true
    }

    public static let batchConflictMessage = "这个编号已用于参数不同的一批兑换码，请重新生成"
    /// A retry: the earlier attempt may be that batch, so it is checked first.
    public static let retryBatchConflictMessage = "这个编号下已有一批参数不同的兑换码，请先核对"
    static let malformedRequestMessage = "请求格式错误，未生成"
    /// Refused before the handler for these exact bytes, which an earlier attempt got as well.
    static let bodyRefusals: Set<String> = ["REDEEM_CODE_EXPIRY_CONFLICT", "REDEEM_CODE_EXPIRES_IN_DAYS_INVALID", "REDEEM_CODE_EXPIRES_AT_INVALID",
                                            "REDEEM_BATCH_ID_INVALID", "IDEMPOTENCY_KEY_INVALID", "IDEMPOTENCY_KEY_REQUIRED", "IDEMPOTENCY_PAYLOAD_INVALID"]

    public static func classify(_ outcome: WriteOutcome<[AdminRedeemCode]>, batchID: UUID) -> RedeemGenerateResult {
        .generated(codes: outcome.value, replayed: outcome.replayed, batchConfirmed: outcome.batchID == batchID,
                   needsRefetch: outcome.value.contains(where: \.isRedacted))
    }
    /// `retrying`: the record went out before, so that attempt may have run and only a refusal decided by the body settles it.
    public static func classify(_ error: any Error, retrying: Bool) -> RedeemGenerateResult {
        if let failure = error as? KeyedWriteFailure { return result(of: failure.disposition) }
        guard let error = error as? APIError else { return pending() }
        return retrying ? retried(error) : firstSend(error)
    }
    public static func classify(_ result: Result<WriteOutcome<[AdminRedeemCode]>, any Error>, batchID: UUID, retrying: Bool) -> RedeemGenerateResult {
        switch result {
        case .success(let outcome): classify(outcome, batchID: batchID)
        case .failure(let error): classify(error, retrying: retrying)
        }
    }

    private static func pending(_ message: String = BalanceReconciliation.unconfirmedReceipt) -> RedeemGenerateResult {
        .unconfirmed(message: message, retryNotBefore: nil)
    }
    private static func result(of disposition: KeyedWriteFailure.Disposition) -> RedeemGenerateResult {
        switch disposition {
        case .needsNewKey(.keyConflict): pending(BalanceReconciliation.keyConflictMessage)
        case .needsNewKey: .rejected(message: malformedRequestMessage, returnsToForm: false)
        case .unconfirmed(.storeUnavailable, let retryNotBefore): .unconfirmed(message: BalanceReconciliation.storeUnavailableMessage, retryNotBefore: retryNotBefore)
        case .unconfirmed(_, let retryNotBefore): .unconfirmed(message: BalanceReconciliation.unconfirmedReceipt, retryNotBefore: retryNotBefore)
        }
    }
    private static func firstSend(_ error: APIError) -> RedeemGenerateResult {
        if error.securityOutcome == .passed { return .reconfirm(notice: error.localizedDescription) }
        if let refusal = bodyRefusal(error) { return refusal }
        if error.statusCode == 409, error.reason == "REDEEM_BATCH_CONFLICT" { return .rejected(message: batchConflictMessage, returnsToForm: true) }
        if error.isRefusedBeforeHandler || (error.statusCode == nil && error.kind == .validation) {
            return .rejected(message: error.localizedDescription, returnsToForm: false)
        }
        guard let status = error.statusCode, (400..<500).contains(status), status != 408 else { return pending() }
        return .rejected(message: error.localizedDescription, returnsToForm: true)
    }
    private static func retried(_ error: APIError) -> RedeemGenerateResult {
        if let reason = error.reason, bodyRefusals.contains(reason), let refusal = bodyRefusal(error) { return refusal }
        if error.statusCode == 409, error.reason == "REDEEM_BATCH_CONFLICT" { return pending(retryBatchConflictMessage) }
        return pending(error.securityOutcome == .passed ? error.localizedDescription : BalanceReconciliation.unconfirmedReceipt)
    }
    /// A 400 refuses these bytes before anything runs. One without a reason may also be a proxy's page, so a retry takes only
    /// `bodyRefusals` as settled.
    private static func bodyRefusal(_ error: APIError) -> RedeemGenerateResult? {
        guard error.statusCode == 400 else { return nil }
        if let reason = error.reason, reason.hasPrefix("IDEMPOTENCY_") { return .rejected(message: malformedRequestMessage, returnsToForm: false) }
        return .rejected(message: error.localizedDescription, returnsToForm: true)
    }
}

extension APIClient {
    /// `POST admin/redeem-codes/generate` under the record's number (00 §2.5, R04): Idempotency-Key = X-Request-ID = batch_id,
    /// the same bytes on every attempt, 35 seconds, IN_PROGRESS waited for 30 seconds in all. A record of this site or of an
    /// older login at its address goes out (X34); the sender check is the caller's (MoneyRecordOrigin.checkSender, S3D1-16).
    public func generateRedeemCodes(_ write: PersistedMoneyWrite<PendingRedeemBatch>, sameAddress: Set<UUID>,
                                    onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<[AdminRedeemCode]> {
        let batch = write.record
        try MoneyRecordOrigin.check(recordServerID: batch.serverID, currentServerID: server.id, sameAddress: sameAddress)
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/redeem-codes/generate", method: "POST", body: batch.requestBody(), key: batch.id),
                                           onEvent: onEvent)
    }
}
