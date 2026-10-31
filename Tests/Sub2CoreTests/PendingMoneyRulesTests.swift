import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let batchID = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!
private let batchKey = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
private let grantCode = "0123456789abcdef0123456789abcdef"
private func fields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private func batch(serverID: UUID = UUID(), count: Int = 3) -> PendingRedeemBatch {
    PendingRedeemBatch(id: batchID, serverID: serverID, actorUserID: 7, spec: RedeemGenerateSpec(type: .balance, value: 10, count: count))
}
private func grant(serverID: UUID = UUID(), userID: Int = 42) -> PendingCompensation {
    PendingCompensation(serverID: serverID, actorUserID: 7, userID: userID, userDisplayName: "王小明", userEmail: "wang@example.invalid",
                        code: grantCode, type: .balance, value: 10)
}
private func balance(serverID: UUID, userID: Int = 42, _ operation: BalanceOperation, _ amount: Decimal) -> PendingBalanceOperation {
    PendingBalanceOperation(serverID: serverID, userID: userID, amount: amount, operation: operation, actorUserID: 7)
}
private func codeJSON(_ id: Int, code: String = grantCode, status: String = "unused", usedBy: Int? = nil, batch: String? = batchKey) -> String {
    let user = usedBy.map(String.init) ?? "null", batchField = batch.map { ",\"batch_id\":\"\($0)\"" } ?? ""
    return #"{"id":\#(id),"code":"\#(code)","type":"balance","value":10,"status":"\#(status)","used_by":\#(user)\#(batchField)}"#
}
private func codes(_ items: String...) throws -> [AdminRedeemCode] {
    try JSONDecoder().decode([AdminRedeemCode].self, from: Data("[\(items.joined(separator: ","))]".utf8))
}
private func codePage(_ items: String...) -> HTTPResponse {
    okReply(#"{"items":[\#(items.joined(separator: ","))],"total":\#(items.count),"page":1,"page_size":100,"pages":1}"#)
}

@Test func redeemBatchOutcomes() throws {
    let pending = batch()
    let three = try codes(codeJSON(1, code: "a"), codeJSON(2, code: "b"), codeJSON(3, code: "c"))
    #expect(RedeemBatchReconciliation.evaluate(pending, items: three) == .generated(three))
    #expect(RedeemBatchReconciliation.evaluate(pending, items: []) == .notGenerated)
    #expect(RedeemBatchReconciliation.evaluate(pending, items: Array(three.prefix(2))) == .countMismatch(Array(three.prefix(2))))
    // The server ignored batch_id: other batches or old codes without one came back.
    let otherBatch = try codes(codeJSON(4, batch: UUID().uuidString)), withoutBatch = try codes(codeJSON(5, batch: nil))
    #expect(RedeemBatchReconciliation.evaluate(pending, items: otherBatch) == .unverifiable)
    #expect(RedeemBatchReconciliation.evaluate(pending, items: three + withoutBatch) == .unverifiable)
    #expect(PendingReconcileOutcome.redeemBatch(.generated(three)).confirmsExecution)
    for outcome: RedeemBatchReconcileOutcome in [.notGenerated, .countMismatch(three), .unverifiable] {
        #expect(!PendingReconcileOutcome.redeemBatch(outcome).confirmsExecution)
    }
}

@Test func redeemBatchQueryMatchesSpec() throws {
    let sent = fields(try RedeemBatchReconciliation.query(for: batch()).queryItems(page: 1))
    #expect(sent == ["batch_id": batchKey, "page": "1", "page_size": "100", "sort_by": "id", "sort_order": "asc"])
}

@Test func compensationOutcomes() throws {
    let pending = grant()
    let issued = try codes(codeJSON(1, status: "used", usedBy: 42))
    #expect(CompensationReconciliation.evaluate(pending, items: issued) == .issued(issued[0]))
    let laterExpired = try codes(codeJSON(1, status: "expired", usedBy: 42))
    #expect(CompensationReconciliation.evaluate(pending, items: laterExpired) == .issued(laterExpired[0]))
    let unused = try codes(codeJSON(2))
    #expect(CompensationReconciliation.evaluate(pending, items: unused) == .createdNotRedeemed(unused[0]))
    // `search` is a contains match: a longer code holding this one is not it.
    let longer = try codes(codeJSON(3, code: grantCode + "ff", status: "used", usedBy: 42))
    #expect(CompensationReconciliation.evaluate(pending, items: longer) == .notFound)
    let other = try codes(codeJSON(4, status: "used", usedBy: 43))
    #expect(CompensationReconciliation.evaluate(pending, items: other) == .redeemedByOther(other[0]))
    let odd = try codes(codeJSON(5, status: "used"))
    #expect(CompensationReconciliation.evaluate(pending, items: odd) == .unverifiable(odd[0]))
    #expect(PendingReconcileOutcome.compensation(.issued(issued[0])).confirmsExecution)
    #expect(!PendingReconcileOutcome.compensation(.createdNotRedeemed(unused[0])).confirmsExecution)
    #expect(fields(try CompensationReconciliation.query(for: pending).queryItems(page: 1))
            == ["search": grantCode, "page": "1", "page_size": "5", "sort_by": "id", "sort_order": "desc"])
}

@Test func balanceGateOnlyInterceptsSameDirection() {
    let site = UUID()
    func gate(_ records: [PendingBalanceOperation], _ direction: BalanceDirection, userID: Int = 42) -> PendingMoneyGate {
        .evaluate(.balance(userID: userID, direction: direction), serverIDs: [site], balances: records, redeemBatches: [], compensations: [], unavailable: [])
    }
    let credit = balance(serverID: site, .add, 50)
    #expect(gate([credit], .credit) == .overridable([credit.id]))
    #expect(gate([credit], .debit) == .clear)
    let refundAll = balance(serverID: site, .set, 0)
    #expect(gate([refundAll], .debit) == .overridable([refundAll.id])); #expect(gate([refundAll], .credit) == .clear)
    let debit = balance(serverID: site, .subtract, 5)
    #expect(gate([debit], .debit) == .overridable([debit.id]))
    // A `set` above 0 only exists in older records; its direction is unknown, so it holds back both.
    let oldSet = balance(serverID: site, .set, 20)
    #expect(gate([oldSet], .credit) == .overridable([oldSet.id])); #expect(gate([oldSet], .debit) == .overridable([oldSet.id]))
    #expect(gate([credit], .credit, userID: 43) == .clear)
    #expect(gate([balance(serverID: UUID(), .add, 50)], .credit) == .clear)
}

@Test func redeemAndCompensationGates() {
    let site = UUID()
    let pendingBatch = batch(serverID: site), pendingGrant = grant(serverID: site), credit = balance(serverID: site, .add, 1)
    func gate(_ intent: MoneyWriteIntent, unavailable: Set<PendingMoneyKind> = []) -> PendingMoneyGate {
        .evaluate(intent, serverIDs: [site], balances: [credit], redeemBatches: [pendingBatch], compensations: [pendingGrant], unavailable: unavailable)
    }
    #expect(gate(.redeemGenerate) == .overridable([pendingBatch.id]))
    #expect(gate(.compensation(userID: 42)) == .blocked([pendingGrant.id]))
    #expect(gate(.compensation(userID: 43)) == .clear)
    #expect(PendingMoneyGate.evaluate(.redeemGenerate, serverIDs: [UUID()], balances: [], redeemBatches: [pendingBatch], compensations: [], unavailable: []) == .clear)
    #expect(gate(.compensation(userID: 43), unavailable: [.compensation]) == .paused(.compensation))
    #expect(gate(.redeemGenerate, unavailable: [.redeemBatch]) == .paused(.redeemBatch))
    // Another kind's unreadable file does not pause this one.
    #expect(gate(.balance(userID: 42, direction: .credit), unavailable: [.redeemBatch]) == .overridable([credit.id]))
    #expect(gate(.balance(userID: 42, direction: .credit), unavailable: [.balance]) == .paused(.balance))
}

@Test func retryPermissionRequiresSameActor() {
    #expect(PendingRetryPermission.evaluate(actorUserID: nil, currentUserID: 7) == .allowedActorUnknown)
    #expect(PendingRetryPermission.evaluate(actorUserID: nil, currentUserID: nil) == .allowedActorUnknown)
    #expect(PendingRetryPermission.evaluate(actorUserID: 7, currentUserID: 7) == .allowed)
    #expect(PendingRetryPermission.evaluate(actorUserID: 7, currentUserID: 8) == .otherActor)
    #expect(PendingRetryPermission.evaluate(actorUserID: 7, currentUserID: nil) == .otherActor)
}

@Test func kindMessagesMatchSpec() {
    #expect(PendingMoneyKind.balance.unreadableMessage == "未决余额记录无法读取，已暂停新的余额操作。请保留应用数据并检查设备存储。")
    #expect(PendingMoneyKind.redeemBatch.unreadableMessage == "未决兑换码记录无法读取，已暂停新的兑换码生成。请保留应用数据并检查设备存储。")
    #expect(PendingMoneyKind.compensation.unreadableMessage == "未决补偿记录无法读取，已暂停新的补偿发放。请保留应用数据并检查设备存储。")
    #expect(PendingMoneyKind.balance.unsavedMessage == "未决记录无法保存，已暂停此操作")
    #expect(PendingMoneyKind.redeemBatch.unsavedMessage == "未决记录无法保存，已暂停生成")
    #expect(PendingMoneyKind.compensation.unsavedMessage == "未决记录无法保存，已暂停发放")
    #expect(PendingMoneyKind(record: balance(serverID: UUID(), .add, 1)) == .balance)
    #expect(PendingMoneyKind(record: batch()) == .redeemBatch)
    #expect(PendingMoneyKind(record: grant()) == .compensation)
}

@Test func reconcileDispatchesEachRecordType() async throws {
    let server = stubServer()
    let op = balance(serverID: server.id, .add, 50)
    let ledgerRow = #"{"id":8,"kind":"balance","user_id":42,"request_id":"\#(op.id.uuidString.lowercased())","before_value":"1","after_value":"51"}"#
    let transport = ScriptedTransport { request in
        let query = fields(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
        switch request.url?.path {
        case "/api/v1/admin/user-adjustments": return okReply(#"{"items":[\#(ledgerRow)],"total":1,"page":1,"page_size":20,"pages":1}"#)
        case "/api/v1/admin/redeem-codes" where query["batch_id"] != nil:
            return codePage(codeJSON(1, code: "a"), codeJSON(2, code: "b"), codeJSON(3, code: "c"))
        case "/api/v1/admin/redeem-codes": return codePage(codeJSON(9, status: "used", usedBy: 42, batch: nil))
        default: return errorReply(404)
        }
    }
    let client = APIClient(server: server, credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)

    guard case .balance(.executed(let row)) = try await client.reconcile(op) else { Issue.record("expected an executed balance"); return }
    #expect(row.id == 8)
    guard case .redeemBatch(.generated(let generated)) = try await client.reconcile(batch(serverID: server.id)) else {
        Issue.record("expected a generated batch"); return
    }
    #expect(generated.map(\.code) == ["a", "b", "c"])
    guard case .compensation(.issued(let code)) = try await client.reconcile(grant(serverID: server.id)) else { Issue.record("expected an issued grant"); return }
    #expect(code.id == 9)
    #expect(await transport.requests.count == 3)

    for record: any PendingMoneyWrite in [batch(), grant()] {
        #expect(await thrownAPIError { _ = try await client.reconcile(record) } == .stationMismatch)
    }
    #expect(await transport.requests.count == 3)
}

/// D17: user ids belong to a site, so a record of another site is never the current administrator's (AppModel.retryPermission).
@Test func retryPermissionOfARecordIsScopedToTheActiveSite() {
    let site = UUID(), other = UUID()
    let mine = balance(serverID: site, .add, 5)
    #expect(PendingRetryPermission.evaluate(mine, activeServerID: site, currentUserID: 7) == .allowed)
    #expect(PendingRetryPermission.evaluate(mine, activeServerID: site, currentUserID: 8) == .otherActor)
    #expect(PendingRetryPermission.evaluate(mine, activeServerID: other, currentUserID: 7) == .otherActor)
    #expect(PendingRetryPermission.evaluate(mine, activeServerID: nil, currentUserID: 7) == .otherActor)
    let unknown = PendingBalanceOperation(serverID: site, userID: 42, amount: 5, operation: .add)
    #expect(PendingRetryPermission.evaluate(unknown, activeServerID: site, currentUserID: 7) == .allowedActorUnknown)
    // Another site's record without a sender is never retried here (C-26: only the same address and the same sender).
    #expect(PendingRetryPermission.evaluate(unknown, activeServerID: other, currentUserID: 7) == .otherActor)
    #expect(PendingRetryPermission.evaluate(mine, activeServerID: other, currentUserID: 7, sameAddress: [other, site]) == .allowed)
    #expect(PendingRetryPermission.evaluate(grant(serverID: other), activeServerID: site, currentUserID: 7) == .otherActor)
}

// MARK: Records of an older login at the same address (X34 / C-26; BACKLOG “待核对门控跨站点 id”)

private func profile(_ address: String) -> ServerProfile {
    ServerProfile(name: "站点", baseURL: URL(string: address)!, authentication: .password)
}

@Test func gateCountsSameAddressRecordsByKind() {
    let current = UUID(), oldLogin = UUID(), elsewhere = UUID()
    let credit = balance(serverID: oldLogin, .add, 50), refund = balance(serverID: oldLogin, .subtract, 5), farCredit = balance(serverID: elsewhere, .add, 50)
    let oldBatch = batch(serverID: oldLogin), oldGrant = grant(serverID: oldLogin), farGrant = grant(serverID: elsewhere)
    func gate(_ intent: MoneyWriteIntent, serverIDs: Set<UUID>, unavailable: Set<PendingMoneyKind> = []) -> PendingMoneyGate {
        .evaluate(intent, serverIDs: serverIDs, balances: [credit, refund, farCredit], redeemBatches: [oldBatch], compensations: [oldGrant, farGrant],
                  unavailable: unavailable)
    }
    let same: Set<UUID> = [current, oldLogin]
    #expect(gate(.balance(userID: 42, direction: .credit), serverIDs: same) == .overridable([credit.id]))
    #expect(gate(.balance(userID: 42, direction: .debit), serverIDs: same) == .overridable([refund.id]))
    #expect(gate(.balance(userID: 43, direction: .credit), serverIDs: same) == .clear)
    #expect(gate(.redeemGenerate, serverIDs: same) == .overridable([oldBatch.id]))
    #expect(gate(.compensation(userID: 42), serverIDs: same) == .blocked([oldGrant.id]))
    #expect(gate(.compensation(userID: 43), serverIDs: same) == .clear)
    #expect(gate(.compensation(userID: 42), serverIDs: same, unavailable: [.compensation]) == .paused(.compensation))
    // Records of another address hold nothing back.
    #expect(gate(.balance(userID: 42, direction: .credit), serverIDs: [current]) == .clear)
    #expect(gate(.redeemGenerate, serverIDs: [current]) == .clear)
    #expect(gate(.compensation(userID: 42), serverIDs: [current]) == .clear)
}

@Test func addressKeyDropsDefaultPortOnly() throws {
    func key(_ address: String) throws -> String? { MoneyRecordOrigin.addressKey(of: try #require(URL(string: address))) }
    let base = try #require(try key("https://sub2.example.com"))
    #expect(try key("https://Sub2.Example.com/") == base)
    #expect(try key("https://sub2.example.com:443") == base)
    #expect(try key("https://A.example.com:443") == key("https://a.example.com"))
    #expect(try key("https://sub2.example.com:8443") != base)
    #expect(try key("https://other.example.com") != base)
    #expect(try key("http://sub2.example.com") == nil)
}

@Test func sameAddressIDsCoverOlderLoginsOfOneAddress() {
    let current = profile("https://sub2.example.com"), older = profile("https://SUB2.example.com:443/"), archived = profile("https://sub2.example.com")
    let otherPort = profile("https://sub2.example.com:8443"), otherHost = profile("https://ops.example.com")
    #expect(MoneyRecordOrigin.sameAddressIDs(of: current, among: [current, older, archived, otherPort, otherHost]) == [current.id, older.id, archived.id])
    #expect(MoneyRecordOrigin.sameAddressIDs(of: current, among: []) == [current.id])
    let unusable = profile("http://sub2.example.com")
    #expect(MoneyRecordOrigin.sameAddressIDs(of: unusable, among: [unusable, current, profile("http://sub2.example.com")]) == [unusable.id])
}

@Test func kindCoversThreeOrigins() {
    let current = UUID(), oldLogin = UUID(), same: Set<UUID> = [current, oldLogin]
    #expect(MoneyRecordOrigin.Kind(recordServerID: current, currentServerID: current, sameAddress: []) == .currentSite)
    #expect(MoneyRecordOrigin.Kind(recordServerID: current, currentServerID: current, sameAddress: same) == .currentSite)
    #expect(MoneyRecordOrigin.Kind(recordServerID: oldLogin, currentServerID: current, sameAddress: same) == .sameAddressOldLogin)
    #expect(MoneyRecordOrigin.Kind(recordServerID: UUID(), currentServerID: current, sameAddress: same) == .otherAddress)
    #expect(MoneyRecordOrigin.Kind(recordServerID: oldLogin, currentServerID: nil, sameAddress: same) == .otherAddress)
    #expect(MoneyRecordOrigin.oldLoginNote == "本站点的旧登录下发起")
}

@Test func moneyRecordOriginAllowsOnlySameAddress() {
    let current = UUID(), oldLogin = UUID()
    #expect(throws: Never.self) { try MoneyRecordOrigin.check(recordServerID: current, currentServerID: current, sameAddress: []) }
    #expect(throws: Never.self) { try MoneyRecordOrigin.check(recordServerID: oldLogin, currentServerID: current, sameAddress: [current, oldLogin]) }
    #expect(throws: APIError.stationMismatch) { try MoneyRecordOrigin.check(recordServerID: UUID(), currentServerID: current, sameAddress: [current, oldLogin]) }
    #expect(throws: APIError.stationMismatch) { try MoneyRecordOrigin.check(recordServerID: oldLogin, currentServerID: current, sameAddress: []) }
}

@Test func retryPermissionAcrossSiteIDs() {
    let current = UUID(), oldLogin = UUID()
    func permission(_ actor: Int?, _ me: Int?, record: UUID, active: UUID? = current) -> PendingRetryPermission {
        .evaluate(actorUserID: actor, currentUserID: me, recordServerID: record, currentServerID: active, sameAddress: [current, oldLogin])
    }
    #expect(permission(nil, 7, record: current) == .allowedActorUnknown)
    #expect(permission(7, 7, record: current) == .allowed)
    #expect(permission(7, 8, record: current) == .otherActor)
    // An older login of the same address: only a known sender who is the current administrator.
    #expect(permission(7, 7, record: oldLogin) == .allowed)
    #expect(permission(nil, 7, record: oldLogin) == .otherActor)
    #expect(permission(7, 8, record: oldLogin) == .otherActor)
    #expect(permission(7, nil, record: oldLogin) == .otherActor)
    #expect(permission(7, 7, record: UUID()) == .otherActor)
    #expect(permission(nil, 7, record: UUID()) == .otherActor)
    #expect(permission(7, 7, record: current, active: nil) == .otherActor)
}

/// S3D1-16: the server derives action_id from the sender, so another administrator's same key would run the write again.
@Test func checkSenderRefusesOtherActorEvenAtSameAddress() {
    let current = UUID(), oldLogin = UUID(), same: Set<UUID> = [current, oldLogin]
    func check(_ actor: Int?, record: UUID) throws {
        try MoneyRecordOrigin.checkSender(actorUserID: actor, currentUserID: 1, recordServerID: record, currentServerID: current, sameAddress: same)
    }
    #expect(throws: APIError.otherActorWrite) { try check(7, record: oldLogin) }
    #expect(throws: APIError.otherActorWrite) { try check(nil, record: oldLogin) }
    #expect(throws: APIError.otherActorWrite) { try check(1, record: UUID()) }
    #expect(throws: Never.self) { try check(nil, record: current) }
    #expect(throws: Never.self) { try check(1, record: oldLogin) }
    #expect(throws: Never.self) { try check(1, record: current) }
    #expect(APIError.otherActorWrite.localizedDescription == "这笔由其他管理员发起，不能用同一编号重试。")
    #expect(APIError.otherActorWrite.kind == .validation)
}

@Test func reconcileAcceptsSameAddressRecordsOfEveryKind() async throws {
    let server = stubServer(), oldLogin = UUID()
    let op = balance(serverID: oldLogin, .add, 50), oldBatch = batch(serverID: oldLogin), oldGrant = grant(serverID: oldLogin)
    let ledgerRow = #"{"id":8,"kind":"balance","user_id":42,"request_id":"\#(op.key)","before_value":"1","after_value":"51"}"#
    let transport = ScriptedTransport { request in
        let query = fields(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
        switch request.url?.path {
        case "/api/v1/admin/user-adjustments": return okReply(#"{"items":[\#(ledgerRow)],"total":1,"page":1,"page_size":20,"pages":1}"#)
        case "/api/v1/admin/redeem-codes" where query["batch_id"] != nil:
            return codePage(codeJSON(1, code: "a"), codeJSON(2, code: "b"), codeJSON(3, code: "c"))
        case "/api/v1/admin/redeem-codes": return codePage(codeJSON(9, status: "used", usedBy: 42, batch: nil))
        default: return errorReply(404)
        }
    }
    let client = APIClient(server: server, credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
    let same: Set<UUID> = [server.id, oldLogin]
    let balanceOutcome = try await client.reconcile(op, sameAddress: same)
    let batchOutcome = try await client.reconcile(oldBatch, sameAddress: same)
    let grantOutcome = try await client.reconcile(oldGrant, sameAddress: same)
    #expect(balanceOutcome.confirmsExecution); #expect(batchOutcome.confirmsExecution); #expect(grantOutcome.confirmsExecution)
    #expect(await transport.requests.count == 3)
    for record: any PendingMoneyWrite in [op, oldBatch, oldGrant] {
        #expect(await thrownAPIError { _ = try await client.reconcile(record) } == .stationMismatch)
        #expect(await thrownAPIError { _ = try await client.reconcile(record, sameAddress: [server.id]) } == .stationMismatch)
    }
    #expect(await transport.requests.count == 3)
}

// MARK: S6-07 the + of the redeem list (60 §8.4, R03, X34)

private func redeemBatch(_ id: String, serverID: UUID, minutesAgo: Double, now: Date, count: Int = 20) -> PendingRedeemBatch {
    PendingRedeemBatch(id: UUID(uuidString: id)!, serverID: serverID, actorUserID: 7, createdAt: now.addingTimeInterval(-minutesAgo * 60),
                       spec: RedeemGenerateSpec(type: .balance, value: 10, count: count))
}
private func redeemGate(serverIDs: Set<UUID>, batches: [PendingRedeemBatch], unavailable: Set<PendingMoneyKind> = []) -> PendingMoneyGate {
    .evaluate(.redeemGenerate, serverIDs: serverIDs, balances: [], redeemBatches: batches, compensations: [], unavailable: unavailable)
}

@Test func redeemGateCountsSameAddressOldSiteBatches() {
    let current = UUID(), oldLogin = UUID(), elsewhere = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = redeemBatch("0B000000-0000-4000-8000-000000000002", serverID: oldLogin, minutesAgo: 10, now: now, count: 10)
    let far = redeemBatch("0F000000-0000-4000-8000-000000000002", serverID: elsewhere, minutesAgo: 20, now: now)
    let gate = redeemGate(serverIDs: [current, oldLogin], batches: [old, far])
    #expect(gate == .overridable([old.id]))
    #expect(redeemGate(serverIDs: [current], batches: [old, far]) == .clear)
    // The older login's batch is asked about, not the other address's, though that one is older.
    let decision = RedeemGenerateEntryDecision.decide(gate: gate, batches: [old, far], now: now, timeZone: TimeZone(identifier: "UTC")!)
    #expect(decision == .intercept(RedeemGenerateIntercept(batchID: old.id, message: "10 个 × $10.00 · 合计 $100.00\n10 分钟前发起。先核对，避免重复生成。")))
}

@Test func redeemGateKeepsBothBatchesAfterOverride() {
    let current = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = redeemBatch("0A000000-0000-4000-8000-000000000002", serverID: current, minutesAgo: 5, now: now)
    // “仍要生成新的一批” made a second batch whose result is unknown as well: both hold the next +.
    let second = redeemBatch("0A000000-0000-4000-8000-000000000012", serverID: current, minutesAgo: 1, now: now)
    let gate = redeemGate(serverIDs: [current], batches: [second, first])
    #expect(gate == .overridable([second.id, first.id]))
    guard case .intercept(let intercept) = RedeemGenerateEntryDecision.decide(gate: gate, batches: [second, first], now: now,
                                                                              timeZone: TimeZone(identifier: "UTC")!) else {
        Issue.record("not intercepted"); return
    }
    #expect(intercept.batchID == first.id)
}

@Test func redeemGatePausedWinsOverSameAddressBatches() {
    let current = UUID(), oldLogin = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = redeemBatch("0B000000-0000-4000-8000-000000000002", serverID: oldLogin, minutesAgo: 10, now: now)
    let paused = redeemGate(serverIDs: [current, oldLogin], batches: [old], unavailable: [.redeemBatch])
    #expect(paused == .paused(.redeemBatch))
    #expect(RedeemGenerateEntryDecision.decide(gate: paused, batches: [old], now: now, timeZone: TimeZone(identifier: "UTC")!)
            == .paused(message: PendingMoneyKind.redeemBatch.unreadableMessage))
    // Another kind's unreadable file does not pause generating.
    #expect(redeemGate(serverIDs: [current, oldLogin], batches: [old], unavailable: [.balance, .compensation]) == .overridable([old.id]))
}
