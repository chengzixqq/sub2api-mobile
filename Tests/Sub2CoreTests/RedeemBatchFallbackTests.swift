import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// S6-06: the check of a pending batch on a server that keeps no batch (60 §11.4 末条, U43).

private let fallbackID = UUID(uuidString: "0F000000-0000-4000-8000-000000000606")!
private let made = Date(timeIntervalSince1970: 1_800_000_000)
private let tenDollarsWeekly = RedeemGenerateSpec(type: .balance, value: 10, count: 2, expiresInDays: 7)

private func queryFields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private func pending(_ spec: RedeemGenerateSpec = tenDollarsWeekly, serverID: UUID = UUID(), actor: Int? = 1) -> PendingRedeemBatch {
    PendingRedeemBatch(id: fallbackID, serverID: serverID, actorUserID: actor, createdAt: made, spec: spec)
}
/// A code made `after` seconds after the record, on a server whose clock agrees with the phone.
private func fresh(_ id: Int, type: String = "balance", value: Decimal = 10, after: TimeInterval = 30, expiresInDays: Int? = 7,
                  batchID: UUID? = nil, createdBy: Int? = 1, groupID: Int? = nil, validityDays: Int? = nil, notes: String? = nil) -> AdminRedeemCode {
    let createdAt = made.addingTimeInterval(after)
    return AdminRedeemCode(id: id, code: String(format: "%032lx", id), type: type, value: value, status: "unused", createdAt: createdAt,
                           expiresAt: expiresInDays.map { createdAt.addingTimeInterval(TimeInterval($0) * 86_400) }, groupID: groupID,
                           validityDays: validityDays, notes: notes, batchID: batchID, createdBy: createdBy)
}
private func fallbackClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func page(_ codes: [AdminRedeemCode]) -> String {
    let items = codes.map { code in
        let created = code.createdAt.map { #","created_at":"\#(ServerTime.utcTimestamp($0))""# } ?? ""
        let expires = code.expiresAt.map { #","expires_at":"\#(ServerTime.utcTimestamp($0))""# } ?? ""
        return #"{"id":\#(code.id),"code":"\#(code.code)","type":"\#(code.type)","value":\#(code.value ?? 0),"status":"unused","created_by":1\#(created)\#(expires)}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))],"total":\#(codes.count),"page":1,"page_size":100}"#
}

@Test func fallbackQueryReadsTheNewestCodesOfTheBatchType() throws {
    #expect(queryFields(try RedeemBatchFallback.query(for: pending()).queryItems(page: 1))
            == ["page": "1", "page_size": "100", "sort_by": "created_at", "sort_order": "desc", "type": "balance"])
    let invitation = pending(RedeemGenerateSpec(type: .invitation, value: 0, count: 10))
    #expect(queryFields(try RedeemBatchFallback.query(for: invitation).queryItems(page: 1))["type"] == "invitation")
    #expect(RedeemBatchFallback.query(for: pending()).batchID == nil && RedeemBatchFallback.query(for: pending()).status == nil)
}

@Test func fallbackWindowFollowsTheServerClockAndTheLastSend() {
    let batch = pending()
    #expect(RedeemBatchFallback.window(for: batch, sentAt: nil, clockOffset: 0) == made.addingTimeInterval(-120)...made.addingTimeInterval(120))
    #expect(RedeemBatchFallback.window(for: batch, sentAt: nil, clockOffset: 45) == made.addingTimeInterval(-75)...made.addingTimeInterval(165))
    #expect(RedeemBatchFallback.window(for: batch, sentAt: made.addingTimeInterval(600), clockOffset: 0)
            == made.addingTimeInterval(-120)...made.addingTimeInterval(720))
    // A send stamped before the record (a phone clock moved back) does not shrink it.
    #expect(RedeemBatchFallback.window(for: batch, sentAt: made.addingTimeInterval(-600), clockOffset: 0).upperBound == made.addingTimeInterval(120))
}

@Test func fallbackMatchesTypeValueExpirySenderAndTime() {
    let batch = pending(), window = RedeemBatchFallback.window(for: batch, sentAt: nil, clockOffset: 0)
    func matches(_ code: AdminRedeemCode, _ record: PendingRedeemBatch = pending()) -> Bool {
        RedeemBatchFallback.matches(code, batch: record, window: RedeemBatchFallback.window(for: record, sentAt: nil, clockOffset: 0))
    }
    #expect(RedeemBatchFallback.matches(fresh(1), batch: batch, window: window))
    #expect(matches(fresh(1, batchID: fallbackID)) && matches(fresh(1, createdBy: nil)))
    #expect(!matches(fresh(1, type: "concurrency")))
    #expect(!matches(fresh(1, value: Decimal(string: "10.5")!)))
    #expect(!matches(fresh(1, after: 200)) && !matches(fresh(1, after: -200)))
    #expect(!matches(fresh(1, expiresInDays: nil)) && !matches(fresh(1, expiresInDays: 30)))
    #expect(!matches(fresh(1, batchID: UUID())))
    #expect(!matches(fresh(1, createdBy: 2)))
    #expect(matches(fresh(1, createdBy: 2), pending(actor: nil)))
    #expect(!matches(fresh(1, notes: "别的批次"), pending(RedeemGenerateSpec(type: .balance, value: 10, count: 2, expiresInDays: 7, notes: "活动"))))
    #expect(matches(fresh(1, notes: "活动"), pending(RedeemGenerateSpec(type: .balance, value: 10, count: 2, expiresInDays: 7, notes: "活动"))))

    let monthly = pending(RedeemGenerateSpec(type: .subscription, value: 0, count: 2, groupID: 4, groupName: "企业专线", validityDays: 30))
    #expect(matches(fresh(1, type: "subscription", value: 0, expiresInDays: nil, groupID: 4, validityDays: 30), monthly))
    #expect(!matches(fresh(1, type: "subscription", value: 0, expiresInDays: nil, groupID: 5, validityDays: 30), monthly))
    #expect(!matches(fresh(1, type: "subscription", value: 0, expiresInDays: nil, groupID: 4, validityDays: 7), monthly))
    let invites = pending(RedeemGenerateSpec(type: .invitation, value: 0, count: 2))
    #expect(matches(fresh(1, type: "invitation", value: 0, expiresInDays: nil), invites))
}

@Test func fallbackEvaluatesCountsAndATruncatedPage() {
    let batch = pending(), others = (100...105).map { fresh($0, value: 20) }
    #expect(RedeemBatchFallback.evaluate(batch, items: [fresh(12), fresh(11)] + others, sentAt: nil, clockOffset: 0) == .likelyGenerated([fresh(11), fresh(12)]))
    #expect(RedeemBatchFallback.evaluate(batch, items: [fresh(11)] + others, sentAt: nil, clockOffset: 0) == .countMismatch([fresh(11)]))
    #expect(RedeemBatchFallback.evaluate(batch, items: [fresh(13), fresh(12), fresh(11)], sentAt: nil, clockOffset: 0)
            == .countMismatch([fresh(11), fresh(12), fresh(13)]))
    #expect(RedeemBatchFallback.evaluate(batch, items: others, sentAt: nil, clockOffset: 0) == .notFound)
    // A full page whose oldest code is still inside the window may hide the batch on the next page.
    let crowded = (200..<300).map { fresh($0, value: 20, after: 60) }
    #expect(RedeemBatchFallback.evaluate(batch, items: crowded, sentAt: nil, clockOffset: 0) == .inconclusive)
    #expect(RedeemBatchFallback.evaluate(batch, items: Array(crowded.dropLast()) + [fresh(11, after: -600)], sentAt: nil, clockOffset: 0) == .notFound)
    // A batch of 100 fills the page by itself.
    let hundred = pending(RedeemGenerateSpec(type: .balance, value: 10, count: 100, expiresInDays: 7))
    #expect(RedeemBatchFallback.evaluate(hundred, items: (1...100).map { fresh($0) }, sentAt: nil, clockOffset: 0) == .likelyGenerated((1...100).map { fresh($0) }))
}

@Test func fallbackReadsTheListOnceForASameAddressRecordOnly() async throws {
    let transport = ScriptedTransport { _ in okReply(page([fresh(12), fresh(11), fresh(10, value: 20)])) }
    let client = fallbackClient(transport)
    let oldLogin = UUID()
    let outcome = try await client.reconcileRedeemBatchFallback(pending(serverID: oldLogin), sameAddress: [client.server.id, oldLogin])
    #expect(outcome == .likelyGenerated([fresh(11), fresh(12)]))
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/v1/admin/redeem-codes"); #expect(request.httpMethod == "GET")
    let other = await thrownAPIError { _ = try await client.reconcileRedeemBatchFallback(pending(), sameAddress: [client.server.id, oldLogin]) }
    #expect(other == .stationMismatch)
    #expect(await transport.requests.count == 1)
}

@Test func revealReadsOnlyMaskedCodesByIDInOrder() async throws {
    let transport = ScriptedTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/redeem-codes/11": okReply(#"{"id":11,"code":"a3f01b2c3d4e5f60718293a4b5c6d4e8","type":"balance","value":10,"status":"unused"}"#)
        case "/api/v1/admin/redeem-codes/13": okReply(#"{"id":13,"code":"c3f01b2c3d4e5f60718293a4b5c6d4e8","type":"balance","value":10,"status":"unused"}"#)
        default: errorReply(404, reason: "REDEEM_CODE_NOT_FOUND")
        }
    }
    let client = fallbackClient(transport)
    let masked = [11, 12, 13].map { AdminRedeemCode(id: $0, code: $0 == 12 ? "b3f01b2c3d4e5f60718293a4b5c6d4e8" : "***", type: "balance", status: "unused") }
    let revealed = try await client.revealingRedactedCodes(masked)
    #expect(revealed.map(\.code) == ["a3f01b2c3d4e5f60718293a4b5c6d4e8", "b3f01b2c3d4e5f60718293a4b5c6d4e8", "c3f01b2c3d4e5f60718293a4b5c6d4e8"])
    #expect(await transport.requests.compactMap { $0.url?.path } == ["/api/v1/admin/redeem-codes/11", "/api/v1/admin/redeem-codes/13"])
    let gone = await thrownAPIError { _ = try await client.revealingRedactedCodes([AdminRedeemCode(id: 14, code: "***", type: "balance", status: "unused")]) }
    #expect(gone?.reason == "REDEEM_CODE_NOT_FOUND")
}
