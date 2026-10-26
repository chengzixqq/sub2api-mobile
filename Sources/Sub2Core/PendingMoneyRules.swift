import Foundation

/// The three money-write records, one file each (00 §2.5.5, R01).
public enum PendingMoneyKind: String, CaseIterable, Sendable {
    case balance, redeemBatch, compensation
    public init?(record: any PendingMoneyWrite) {
        switch record {
        case is PendingBalanceOperation: self = .balance
        case is PendingRedeemBatch: self = .redeemBatch
        case is PendingCompensation: self = .compensation
        default: return nil
        }
    }
    /// 00 §2.5.5: an unreadable file pauses new writes of its own kind only.
    public var unreadableMessage: String {
        let (record, action) = switch self {
        case .balance: ("余额", "余额操作")
        case .redeemBatch: ("兑换码", "兑换码生成")
        case .compensation: ("补偿", "补偿发放")
        }
        return "未决\(record)记录无法读取，已暂停新的\(action)。请保留应用数据并检查设备存储。"
    }
    /// 00 §2.5.2, 60 §10.5, §19.4: a record that cannot be saved is not sent.
    public var unsavedMessage: String {
        switch self {
        case .balance: "未决记录无法保存，已暂停此操作"
        case .redeemBatch: "未决记录无法保存，已暂停生成"
        case .compensation: "未决记录无法保存，已暂停发放"
        }
    }
}

// MARK: Redeem batches and compensations (00 §2.5.5; 60 §11.4, §19.4)

public enum RedeemBatchReconcileOutcome: Sendable, Equatable {
    /// As many codes of this batch as were asked for.
    case generated([AdminRedeemCode])
    case notGenerated
    /// Some, but not all (one transaction, so normally impossible): kept until the administrator has checked on the web.
    case countMismatch([AdminRedeemCode])
    /// Codes of other batches came back: the server ignored `batch_id`. Stage 6 adds the heuristic check of old servers.
    case unverifiable
}

public enum RedeemBatchReconciliation {
    public static func query(for batch: PendingRedeemBatch) -> RedeemCodeListQuery {
        RedeemCodeListQuery(batchID: batch.id, pageSize: 100, sortBy: "id", ascending: true)
    }
    public static func evaluate(_ batch: PendingRedeemBatch, items: [AdminRedeemCode]) -> RedeemBatchReconcileOutcome {
        guard items.allSatisfy({ $0.batchID == batch.id }) else { return .unverifiable }
        if items.isEmpty { return .notGenerated }
        return items.count == batch.count ? .generated(items) : .countMismatch(items)
    }
}

public enum CompensationReconcileOutcome: Sendable, Equatable {
    /// Redeemed by this user; a code expired or disabled after that still counts (60 §8.3).
    case issued(AdminRedeemCode)
    /// The code exists but the redemption stopped half way: the same number redeems it.
    case createdNotRedeemed(AdminRedeemCode)
    case notFound
    /// Another user has this code (60 §19.4 REDEEM_CODE_CONFLICT): it was not issued to this user.
    case redeemedByOther(AdminRedeemCode)
    /// Marked used without a user: left to the administrator.
    case unverifiable(AdminRedeemCode)
}

public enum CompensationReconciliation {
    public static func query(for grant: PendingCompensation) -> RedeemCodeListQuery { RedeemCodeListQuery(search: grant.code, pageSize: 5) }
    /// `search` also matches codes and emails that merely contain it, so only the exact code counts; the user decides,
    /// like the server's own create-and-redeem check.
    public static func evaluate(_ grant: PendingCompensation, items: [AdminRedeemCode]) -> CompensationReconcileOutcome {
        guard let code = items.first(where: { $0.code == grant.code }) else { return .notFound }
        if code.usedBy == grant.userID { return .issued(code) }
        if code.usedBy != nil { return .redeemedByOther(code) }
        return code.status == "used" ? .unverifiable(code) : .createdNotRedeemed(code)
    }
}

/// One reconciliation result; only a confirmed execution lets AppModel drop the record by itself.
public enum PendingReconcileOutcome: Sendable, Equatable {
    case balance(BalanceReconcileOutcome)
    case redeemBatch(RedeemBatchReconcileOutcome)
    case compensation(CompensationReconcileOutcome)
    public var confirmsExecution: Bool {
        switch self {
        case .balance(.executed), .redeemBatch(.generated), .compensation(.issued): true
        default: false
        }
    }
}

// MARK: Writes while a record awaits reconciliation (00 §2.5.4 step 4, R03)

public enum BalanceDirection: Sendable, Hashable {
    case credit, debit
    /// `set 0` is the “refund all” of 30 §3.3; a `set` above 0 only exists in records of older versions, whose direction is
    /// unknown, so it holds back both.
    public static func directions(of op: PendingBalanceOperation) -> Set<BalanceDirection> {
        switch op.operation {
        case .add: [.credit]
        case .subtract: [.debit]
        case .set: op.amount == 0 ? [.debit] : [.credit, .debit]
        }
    }
}

public enum MoneyWriteIntent: Sendable, Equatable {
    case balance(userID: Int, direction: BalanceDirection)
    case redeemGenerate
    case compensation(userID: Int)
    public var kind: PendingMoneyKind {
        switch self {
        case .balance: .balance
        case .redeemGenerate: .redeemBatch
        case .compensation: .compensation
        }
    }
}

/// Whether a new money write may start. The pages own the two exceptions of R03 (30 §3.4 “仍要充值 / 仍要退款”, 60 §8.4
/// “仍要生成新的一批”); a compensation has none.
public enum PendingMoneyGate: Sendable, Equatable {
    case clear
    /// Pending records of the same object: confirm twice before going on.
    case overridable([UUID])
    case blocked([UUID])
    /// The kind's file cannot be read.
    case paused(PendingMoneyKind)

    public static func evaluate(_ intent: MoneyWriteIntent, serverID: UUID, balances: [PendingBalanceOperation], redeemBatches: [PendingRedeemBatch],
                                compensations: [PendingCompensation], unavailable: Set<PendingMoneyKind>) -> PendingMoneyGate {
        guard !unavailable.contains(intent.kind) else { return .paused(intent.kind) }
        switch intent {
        case .balance(let userID, let direction):
            let ids = balances.filter { $0.serverID == serverID && $0.userID == userID && BalanceDirection.directions(of: $0).contains(direction) }.map(\.id)
            return ids.isEmpty ? .clear : .overridable(ids)
        case .redeemGenerate:
            let ids = redeemBatches.filter { $0.serverID == serverID }.map(\.id)
            return ids.isEmpty ? .clear : .overridable(ids)
        case .compensation(let userID):
            let ids = compensations.filter { $0.serverID == serverID && $0.userID == userID }.map(\.id)
            return ids.isEmpty ? .clear : .blocked(ids)
        }
    }
}

/// 00 §2.5.2, 30 §3.4, D17: the server's fingerprint includes the administrator, so only the sender may retry the same number.
public enum PendingRetryPermission: Sendable, Equatable {
    case allowed
    /// A record without a sender (saved by an older version): retried as the current administrator, with “无法确认发起人”.
    case allowedActorUnknown
    case otherActor
    public static func evaluate(actorUserID: Int?, currentUserID: Int?) -> PendingRetryPermission {
        guard let actorUserID else { return .allowedActorUnknown }
        return actorUserID == currentUserID ? .allowed : .otherActor
    }
    /// User ids belong to a site, so a record of another site is never the current administrator's.
    public static func evaluate(_ record: any PendingMoneyWrite, activeServerID: UUID?, currentUserID: Int?) -> PendingRetryPermission {
        evaluate(actorUserID: record.actorUserID, currentUserID: record.serverID == activeServerID ? currentUserID : nil)
    }
}

extension APIClient {
    public func reconcileRedeemBatch(_ batch: PendingRedeemBatch) async throws -> RedeemBatchReconcileOutcome {
        guard batch.serverID == server.id else { throw APIError.stationMismatch }
        let page = try await redeemCodes(page: 1, query: RedeemBatchReconciliation.query(for: batch))
        return RedeemBatchReconciliation.evaluate(batch, items: page.items)
    }
    public func reconcileCompensation(_ grant: PendingCompensation) async throws -> CompensationReconcileOutcome {
        guard grant.serverID == server.id else { throw APIError.stationMismatch }
        let page = try await redeemCodes(page: 1, query: CompensationReconciliation.query(for: grant))
        return CompensationReconciliation.evaluate(grant, items: page.items)
    }
    /// 00 §9.5: one entry for the overview, settings, banners and the foreground check; it only reads.
    public func reconcile(_ record: any PendingMoneyWrite) async throws -> PendingReconcileOutcome {
        switch record {
        case let op as PendingBalanceOperation: return .balance(try await reconcileBalance(op))
        case let batch as PendingRedeemBatch: return .redeemBatch(try await reconcileRedeemBatch(batch))
        case let grant as PendingCompensation: return .compensation(try await reconcileCompensation(grant))
        default: throw APIError(kind: .validation, message: "无法核对这类记录。")
        }
    }
}
