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
/// “仍要生成新的一批”); a compensation has none. Records of every site id at the connected address count (X34): a new
/// login there gets a new id while its old records stay (D17).
public enum PendingMoneyGate: Sendable, Equatable {
    case clear
    /// Pending records of the same object: confirm twice before going on.
    case overridable([UUID])
    case blocked([UUID])
    /// The kind's file cannot be read.
    case paused(PendingMoneyKind)

    /// `serverIDs`: the connected site and the older logins of its address (AppModel.sameAddressServerIDs).
    public static func evaluate(_ intent: MoneyWriteIntent, serverIDs: Set<UUID>, balances: [PendingBalanceOperation], redeemBatches: [PendingRedeemBatch],
                                compensations: [PendingCompensation], unavailable: Set<PendingMoneyKind>) -> PendingMoneyGate {
        guard !unavailable.contains(intent.kind) else { return .paused(intent.kind) }
        switch intent {
        case .balance(let userID, let direction):
            let ids = balances.filter { serverIDs.contains($0.serverID) && $0.userID == userID && BalanceDirection.directions(of: $0).contains(direction) }.map(\.id)
            return ids.isEmpty ? .clear : .overridable(ids)
        case .redeemGenerate:
            let ids = redeemBatches.filter { serverIDs.contains($0.serverID) }.map(\.id)
            return ids.isEmpty ? .clear : .overridable(ids)
        case .compensation(let userID):
            let ids = compensations.filter { serverIDs.contains($0.serverID) && $0.userID == userID }.map(\.id)
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
    /// User ids belong to a server. An older login at the same address shares them, but only a known sender who is the current
    /// administrator retries its record (C-26); a record of another address never.
    public static func evaluate(actorUserID: Int?, currentUserID: Int?, recordServerID: UUID, currentServerID: UUID?,
                                sameAddress: Set<UUID>) -> PendingRetryPermission {
        switch MoneyRecordOrigin.Kind(recordServerID: recordServerID, currentServerID: currentServerID, sameAddress: sameAddress) {
        case .currentSite: evaluate(actorUserID: actorUserID, currentUserID: currentUserID)
        case .sameAddressOldLogin: actorUserID != nil && actorUserID == currentUserID ? .allowed : .otherActor
        case .otherAddress: .otherActor
        }
    }
    public static func evaluate(_ record: any PendingMoneyWrite, activeServerID: UUID?, currentUserID: Int?,
                                sameAddress: Set<UUID> = []) -> PendingRetryPermission {
        evaluate(actorUserID: record.actorUserID, currentUserID: currentUserID, recordServerID: record.serverID, currentServerID: activeServerID,
                 sameAddress: sameAddress)
    }
}

/// Where a money record came from, relative to the connected site (X34, C-26). The pages' wording, the reconciliation guards
/// and the same-number retries of all three kinds share this one rule.
public enum MoneyRecordOrigin {
    public enum Kind: Sendable, Equatable {
        case currentSite, sameAddressOldLogin, otherAddress
        /// No connected site → otherAddress.
        public init(recordServerID: UUID, currentServerID: UUID?, sameAddress: Set<UUID>) {
            guard let currentServerID else { self = .otherAddress; return }
            if recordServerID == currentServerID { self = .currentSite }
            else { self = sameAddress.contains(recordServerID) ? .sameAddressOldLogin : .otherAddress }
        }
    }
    /// The only copy of this text (S3D1-08): banners put “这笔在” before it, settings and the overview show it as is.
    public static let oldLoginNote = "本站点的旧登录下发起"

    /// One address: ServerProfile.normalizedURL's https and lowercased host, without the default port 443. nil for an address
    /// that would not be accepted as a site.
    public static func addressKey(of url: URL) -> String? {
        guard let normalized = try? ServerProfile.normalizedURL(url.absoluteString),
              var parts = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else { return nil }
        if parts.port == 443 { parts.port = nil }
        return parts.url?.absoluteString
    }
    /// The current site and every profile at its address; only itself when its address has no key.
    public static func sameAddressIDs(of current: ServerProfile, among profiles: [ServerProfile]) -> Set<UUID> {
        guard let key = addressKey(of: current.baseURL) else { return [current.id] }
        return Set(profiles.filter { addressKey(of: $0.baseURL) == key }.map(\.id)).union([current.id])
    }
    /// Reconciliation and same-number retries accept a record of this site or of an older login at its address.
    public static func check(recordServerID: UUID, currentServerID: UUID, sameAddress: Set<UUID>) throws {
        guard recordServerID == currentServerID || sameAddress.contains(recordServerID) else { throw APIError.stationMismatch }
    }
    /// Before a record goes out again under its own number (S3D1-16): the server derives action_id from the sender, so another
    /// administrator's retry would run the write a second time.
    public static func checkSender(actorUserID: Int?, currentUserID: Int?, recordServerID: UUID, currentServerID: UUID?, sameAddress: Set<UUID>) throws {
        let permission = PendingRetryPermission.evaluate(actorUserID: actorUserID, currentUserID: currentUserID, recordServerID: recordServerID,
                                                         currentServerID: currentServerID, sameAddress: sameAddress)
        guard permission != .otherActor else { throw APIError.otherActorWrite }
    }
}

extension APIClient {
    public func reconcileRedeemBatch(_ batch: PendingRedeemBatch, sameAddress: Set<UUID> = []) async throws -> RedeemBatchReconcileOutcome {
        try MoneyRecordOrigin.check(recordServerID: batch.serverID, currentServerID: server.id, sameAddress: sameAddress)
        let page = try await redeemCodes(page: 1, query: RedeemBatchReconciliation.query(for: batch))
        return RedeemBatchReconciliation.evaluate(batch, items: page.items)
    }
    public func reconcileCompensation(_ grant: PendingCompensation, sameAddress: Set<UUID> = []) async throws -> CompensationReconcileOutcome {
        try MoneyRecordOrigin.check(recordServerID: grant.serverID, currentServerID: server.id, sameAddress: sameAddress)
        let page = try await redeemCodes(page: 1, query: CompensationReconciliation.query(for: grant))
        return CompensationReconciliation.evaluate(grant, items: page.items)
    }
    /// 00 §9.5: one entry for the overview, settings, banners and the foreground check; it only reads, with the current
    /// identity, also for a record of an older login at the same address (`sameAddress`, C-26).
    public func reconcile(_ record: any PendingMoneyWrite, requestIDUsable: Bool = true, sameAddress: Set<UUID> = []) async throws -> PendingReconcileOutcome {
        switch record {
        case let op as PendingBalanceOperation: return .balance(try await reconcileBalance(op, requestIDUsable: requestIDUsable, sameAddress: sameAddress))
        case let batch as PendingRedeemBatch: return .redeemBatch(try await reconcileRedeemBatch(batch, sameAddress: sameAddress))
        case let grant as PendingCompensation: return .compensation(try await reconcileCompensation(grant, sameAddress: sameAddress))
        default: throw APIError(kind: .validation, message: "无法核对这类记录。")
        }
    }
}
