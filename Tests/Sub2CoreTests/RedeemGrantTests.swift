import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// S6-08: the compensation's code, draft, numbering, availability, subscription plan, result table and create-and-redeem
// (60 §19.2–§19.4, U52, R01, R04, R05, X34, S6D1-07, S6D1-08, S6D1-15).

private let grantKey = UUID(uuidString: "5E000000-0000-4000-8000-0000000000AA")!
private let grantCode = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
private let created = Date(timeIntervalSince1970: 1_800_000_000)
private let wang = AdminUser(id: 42, email: "wang@example.com", username: "王小明", balance: Decimal(string: "12.40")!, concurrency: 5)
private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func instant(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }
private func record(_ draft: RedeemGrantDraft, serverID: UUID = grantKey, user: AdminUser = wang) throws -> PendingCompensation {
    try draft.compensation(id: grantKey, serverID: serverID, actorUserID: 7, createdAt: created, user: user, code: grantCode)
}

// MARK: Code, request body and draft

@Test func redeemCodeIsThirtyTwoLowercaseHex() throws {
    #expect(try RedeemCode.random(using: { count in (0..<count).map { UInt8($0) } }) == "000102030405060708090a0b0c0d0e0f")
    let first = try RedeemCode.random(), second = try RedeemCode.random()
    #expect(first != second); #expect(RedeemCode.isWellFormed(first)); #expect(RedeemCode.isWellFormed(second))
    let sources: [RedeemCode.ByteSource] = [{ _ in [UInt8](repeating: 1, count: 15) }, { _ in throw URLError(.unknown) }]
    for source in sources {
        do { _ = try RedeemCode.random(using: source); Issue.record("expected the code to fail") }
        catch let error as APIError { #expect(error.kind == .validation); #expect(error.localizedDescription == "无法生成兑换码，请重试。") }
    }
    #expect(RedeemCode.isWellFormed(grantCode))
    for bad in [grantCode.uppercased(), String(grantCode.dropLast()), grantCode + "0", "g" + String(grantCode.dropFirst()), ""] {
        #expect(!RedeemCode.isWellFormed(bad), "\(bad.count)")
    }
}

@Test func requestBodiesOfTheThreeTypes() throws {
    let balance = try record(RedeemGrantDraft(value: .balance(decimal("10.5")), notes: "  故障补偿 · 工单 #8812 \n"))
    #expect(text(try balance.requestBody())
            == #"{"code":"\#(grantCode)","notes":"故障补偿 · 工单 #8812","type":"balance","user_id":42,"value":10.5}"#)
    let concurrency = try record(RedeemGrantDraft(value: .concurrency(2)))
    #expect(text(try concurrency.requestBody()) == #"{"code":"\#(grantCode)","notes":"","type":"concurrency","user_id":42,"value":2}"#)
    let subscription = try record(RedeemGrantDraft(value: .subscription(groupID: 3, days: 30)))
    #expect(text(try subscription.requestBody())
            == #"{"code":"\#(grantCode)","group_id":3,"notes":"","type":"subscription","user_id":42,"validity_days":30,"value":30}"#)
    #expect(subscription.value == 30 && subscription.validityDays == 30 && subscription.groupID == 3)
}

@Test func draftValidationAndRecordFields() throws {
    let invalid: [RedeemGrantDraft.Value] = [.balance(0), .balance(-1), .balance(decimal("1.005")), .concurrency(0), .concurrency(51),
                                             .subscription(groupID: 3, days: 0), .subscription(groupID: 3, days: 3_651), .subscription(groupID: 0, days: 30)]
    for value in invalid {
        let draft = RedeemGrantDraft(value: value)
        #expect(!draft.isValid, "\(value)")
        #expect(throws: APIError.self) { try record(draft) }
    }
    let valid: [RedeemGrantDraft.Value] = [.balance(decimal("0.01")), .concurrency(1), .concurrency(50), .subscription(groupID: 3, days: 1),
                                           .subscription(groupID: 3, days: 3_650)]
    for value in valid { #expect(RedeemGrantDraft(value: value).isValid, "\(value)"); _ = try record(RedeemGrantDraft(value: value)) }
    // S6D1-15: notes count Unicode scalars, as the server counts runes.
    let thumbs = String(repeating: "👍🏽", count: 500)
    #expect(RedeemGrantDraft(value: .concurrency(1), notes: thumbs).isValid)
    let over = RedeemGrantDraft(value: .concurrency(1), notes: thumbs + "a")
    #expect(!over.isValid); #expect(throws: APIError.self) { try record(over) }
    #expect(!RedeemGrantDraft(value: .concurrency(1), notes: String(repeating: "备", count: 1_001)).isValid)

    let grant = try record(RedeemGrantDraft(value: .balance(10), notes: " 补偿 "))
    #expect(grant.id == grantKey && grant.serverID == grantKey && grant.actorUserID == 7 && grant.createdAt == created)
    #expect(grant.userID == 42 && grant.userDisplayName == "王小明" && grant.userEmail == "wang@example.com")
    #expect(grant.code == grantCode && grant.type == .balance && grant.value == 10 && grant.groupID == nil && grant.validityDays == nil)
    #expect(grant.notes == "补偿")
    let unnamed = try record(RedeemGrantDraft(value: .concurrency(2)), user: AdminUser(id: 43, email: "lee@example.com", username: "  "))
    #expect(unnamed.userDisplayName == "lee" && unnamed.type == .concurrency && unnamed.value == 2)
}

@Test func draftStateChangesCodeOnlyAfterASend() throws {
    let opened = try GrantDraftState.opening(using: { count in [UInt8](repeating: 0xab, count: count) })
    #expect(opened == GrantDraftState(code: String(repeating: "ab", count: 16)))
    #expect(opened.edited(newCode: { "fresh-0" }) == opened)
    let first = opened.confirmed(), second = opened.confirmed()
    #expect(first.code == opened.code && second.code == opened.code)
    #expect(first.key != nil && second.key != nil && first.key != second.key)
    #expect(first.confirmed(key: grantKey).key == grantKey)
    let sent = first.sent()
    #expect(sent.hasSent && sent.key == first.key && sent.code == opened.code)
    // R05: confirming again without an edit keeps the code under a new key.
    let reconfirmed = sent.confirmed()
    #expect(reconfirmed.code == opened.code && reconfirmed.key != sent.key && reconfirmed.hasSent)
    #expect(sent.edited(newCode: { "fresh-1" }) == GrantDraftState(code: "fresh-1"))
    #expect(reconfirmed.edited(newCode: { "fresh-2" }) == GrantDraftState(code: "fresh-2"))
    #expect(sent.renumbered(code: "fresh-3") == GrantDraftState(code: "fresh-3"))
    #expect(opened.renumbered(code: "fresh-4") == GrantDraftState(code: "fresh-4"))
}

/// 60 §19.3 “默认第一个” until a grant went out; then only the group it went out with (§19.4 step 5): the code may exist on the
/// server with that group, so a group gone from the list is chosen again, which takes a new code.
@Test func grantGroupFallsBackToTheFirstOnlyBeforeASend() {
    let groups = [AdminGroup(id: 4, name: "企业专线", sortOrder: 1), AdminGroup(id: 6, name: "标准订阅", sortOrder: 2)]
    let fresh = GrantDraftState(code: grantCode), sent = fresh.confirmed().sent()
    #expect(fresh.group(chosen: nil, in: groups)?.id == 4)
    #expect(fresh.group(chosen: 6, in: groups)?.id == 6)
    #expect(fresh.group(chosen: 9, in: groups)?.id == 4)
    #expect(fresh.group(chosen: 4, in: []) == nil)
    #expect(sent.group(chosen: 6, in: groups)?.id == 6)
    #expect(sent.group(chosen: 9, in: groups) == nil)
    #expect(sent.group(chosen: nil, in: groups) == nil)
    #expect(sent.renumbered(code: "fresh").group(chosen: 9, in: groups)?.id == 4)
    #expect(sent.edited(newCode: { "fresh" }).group(chosen: 9, in: groups)?.id == 4)
}

@Test func availabilityFollowsU52() {
    let unlimited = GrantAvailability(user: AdminUser(id: 1, email: "a@example.com", concurrency: 0), hasSubscriptionGroups: true)
    #expect(unlimited.reason(for: .concurrency) == "这个用户并发不限制，发放后反而会变成有上限")
    #expect(!unlimited.isAvailable(.concurrency)); #expect(unlimited.isAvailable(.balance)); #expect(unlimited.isAvailable(.subscription))
    for concurrency in [nil, 5] as [Int?] {
        let availability = GrantAvailability(user: AdminUser(id: 1, email: "a@example.com", concurrency: concurrency), hasSubscriptionGroups: true)
        #expect(availability.reason(for: .concurrency) == nil)
    }
    let noGroups = GrantAvailability(user: wang, hasSubscriptionGroups: false)
    #expect(noGroups.reason(for: .subscription) == "没有订阅类型的分组"); #expect(!noGroups.isAvailable(.subscription))
    #expect(noGroups.reason(for: .balance) == nil); #expect(noGroups.isAvailable(.concurrency))
}

// MARK: Subscription plan (60 §19.3, subscription_service.go)

@Test func subscriptionPlanFourCases() {
    let now = instant("2026-10-16T08:00:00Z"), utc = zone("UTC")
    func plan(_ rows: [AdminUserSubscription], days: Int = 30) -> SubscriptionGrantPlan {
        SubscriptionGrantPlan.make(rows: rows, groupID: 3, days: days, now: now, timeZone: utc)
    }
    func row(_ expires: String?, _ status: String?, group: Int = 3) -> AdminUserSubscription {
        AdminUserSubscription(id: 1, groupID: group, expiresAt: expires.map(instant), status: status)
    }
    #expect(plan([]) == SubscriptionGrantPlan(kind: .new, currentExpiry: nil, newExpiry: instant("2026-11-15T08:00:00Z")))
    #expect(plan([row("2026-12-30T08:00:00Z", "active", group: 4)]).kind == .new)
    let ends = instant("2026-10-30T08:00:00Z"), extended = instant("2026-11-29T08:00:00Z")
    #expect(plan([row("2026-10-30T08:00:00Z", "active")]) == SubscriptionGrantPlan(kind: .extend, currentExpiry: ends, newExpiry: extended))
    // The server only looks at expires_at: any other status still extends from the old end and turns active.
    for status in ["suspended", "expired", nil] as [String?] {
        #expect(plan([row("2026-10-30T08:00:00Z", status)]) == SubscriptionGrantPlan(kind: .resume, currentExpiry: ends, newExpiry: extended))
    }
    let lapsed = instant("2026-10-10T08:00:00Z"), fresh = instant("2026-11-15T08:00:00Z")
    #expect(plan([row("2026-10-10T08:00:00Z", "active")]) == SubscriptionGrantPlan(kind: .renew, currentExpiry: lapsed, newExpiry: fresh))
    #expect(plan([row("2026-10-16T08:00:00Z", "active")]).kind == .renew)
    #expect(plan([row(nil, "active")]) == SubscriptionGrantPlan(kind: .renew, currentExpiry: nil, newExpiry: fresh))
    #expect(plan([row("2026-10-20T08:00:00Z", "active"), row("2026-10-30T08:00:00Z", "active"), row(nil, "active")]).currentExpiry == ends)
    #expect(plan([row("2099-12-20T00:00:00Z", "active")]).newExpiry == SubscriptionGrantPlan.maxExpiry)
    #expect(SubscriptionGrantPlan.maxExpiry == instant("2099-12-31T23:59:59Z"))
}

@Test func subscriptionPlanUsesServerDayBoundary() {
    let now = instant("2026-10-16T16:30:00Z")
    let shanghai = SubscriptionGrantPlan.make(rows: [], groupID: 3, days: 30, now: now, timeZone: zone("Asia/Shanghai"))
    let utc = SubscriptionGrantPlan.make(rows: [], groupID: 3, days: 30, now: now, timeZone: zone("UTC"))
    #expect(RedeemGrantCopy.planChange(shanghai, now: now, timeZone: zone("Asia/Shanghai")) == "新开通 · 到期 11/16")
    #expect(RedeemGrantCopy.planChange(utc, now: now, timeZone: zone("UTC")) == "新开通 · 到期 11/15")
    // Days are added on the server's calendar: across a DST change the wall clock stays.
    let newYork = zone("America/New_York"), before = instant("2026-10-30T13:00:00Z")
    let row = AdminUserSubscription(id: 1, groupID: 3, expiresAt: before, status: "active")
    #expect(SubscriptionGrantPlan.make(rows: [row], groupID: 3, days: 7, now: now, timeZone: newYork).newExpiry == instant("2026-11-06T14:00:00Z"))
}

// MARK: Result table (60 §19.4 with R04, S6D1-08)

private let issued = AdminRedeemCode(id: 91, code: grantCode, type: "balance", value: 10, status: "used", usedBy: 42)
private let unconfirmed = GrantResultAction.pending(message: "结果未确认，已记为待核对", retryNotBefore: nil)
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: grantKey.uuidString.lowercased(), actionID: nil, lastError: nil)
}
private func action(_ error: any Error, retrying: Bool = false) -> GrantResultAction { GrantResultAction.classify(error, retrying: retrying) }
private let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
private let refusedBeforeHandler: [APIError] = [.server(status: 401, reason: nil), .server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), stepUp,
                                                stepUp.withSecurityOutcome(.cancelled), .server(status: 423, reason: nil),
                                                .server(status: 429, reason: "RATE_LIMITED")]
private let answeredAboutTheCode: [(APIError, GrantResultAction)] = [
    (.server(status: 409, reason: "REDEEM_CODE_CONFLICT"), .renumber(message: "兑换码编号冲突，已换新编号，请重新确认")),
    (.server(status: 409, reason: "REDEEM_CODE_EXPIRED"), .renumber(message: "这个兑换码已失效，已换新编号，请重新确认")),
    (.server(status: 400, reason: "GROUP_NOT_SUBSCRIPTION_TYPE"), .backToValue(message: "这个分组不能用于订阅，请重新选择")),
    (.server(status: 404, reason: "GROUP_NOT_FOUND"), .backToValue(message: "这个分组不能用于订阅，请重新选择")),
    (.server(status: 404, reason: "USER_NOT_FOUND"), .userGone(message: "用户不存在或已删除")),
]

@Test func firstSendResultTable() {
    for outcome in [WriteOutcome(value: issued), WriteOutcome(value: issued, degraded: true)] {
        #expect(GrantResultAction.classify(outcome) == .granted(issued, replayed: false))
    }
    let masked = AdminRedeemCode(id: 91, code: "***", type: "balance", status: "used", usedBy: 42)
    #expect(GrantResultAction.classify(WriteOutcome(value: masked, replayed: true)) == .granted(masked, replayed: true))
    for (error, expected) in answeredAboutTheCode { #expect(action(error) == expected, "\(error.reason ?? "")") }
    for error in [APIError.server(status: 400, reason: nil), .server(status: 400, envelope: nil), .server(status: 400, reason: "REDEEM_CODE_UNSUPPORTED_TYPE")] {
        #expect(action(error) == .rejected(message: error.localizedDescription, reportsDefect: true))
    }
    for cause in [KeyedWriteFailure.NewKeyCause.keyConflict, .invalid, .keyRequired] {
        let failure = keyed(.needsNewKey(cause))
        #expect(action(failure) == .newKeyNeeded(message: failure.localizedDescription))
    }
    for error in refusedBeforeHandler { #expect(action(error) == .rejected(message: error.localizedDescription, reportsDefect: false)) }
    #expect(action(stepUp.withSecurityOutcome(.passed)) == .reconfirm(message: "二次验证已通过，请重新确认后发送"))
    let compliance = APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED").withSecurityOutcome(.passed)
    #expect(action(compliance) == .reconfirm(message: "合规确认已完成，请重新确认后发送"))
    let cooldown = created.addingTimeInterval(10)
    #expect(action(keyed(.unconfirmed(.storeUnavailable, retryNotBefore: cooldown)))
            == .pending(message: "服务器暂时无法受理，稍后用同一编号重试", retryNotBefore: cooldown))
    for cause in [KeyedWriteFailure.UnconfirmedCause.transport, .stillProcessing, .unreadableResponse] {
        #expect(action(keyed(.unconfirmed(cause, retryNotBefore: nil))) == unconfirmed)
    }
    let kept: [any Error] = [APIError.server(status: 500, reason: nil), APIError.server(status: 409, reason: "REDEEM_CODE_USED"),
                             APIError.server(status: 409, reason: "REDEEM_CODE_LOCKED"), APIError.server(status: 418, reason: nil),
                             APIError(kind: .transport, message: "无法连接站点"), CancellationError(), URLError(.timedOut)]
    for error in kept { #expect(action(error) == unconfirmed) }
    for error in [APIError(kind: .validation, message: "补偿内容不符合要求。"), .stationMismatch, .otherActorWrite] {
        #expect(action(error) == .rejected(message: error.localizedDescription, reportsDefect: false))
    }
    #expect(!unconfirmed.resolvesRecord)
    let settled: [GrantResultAction] = [.granted(issued, replayed: false), .renumber(message: ""), .backToValue(message: ""), .userGone(message: ""),
                                        .newKeyNeeded(message: ""), .reconfirm(message: ""), .rejected(message: "", reportsDefect: false)]
    #expect(settled.allSatisfy { $0.resolvesRecord })
}

@Test func retryingResultTable() {
    // The server checks the code before anything else, so these still say it was not redeemed for this user.
    for (error, expected) in answeredAboutTheCode { #expect(action(error, retrying: true) == expected, "\(error.reason ?? "")") }
    let unsupported = APIError.server(status: 400, reason: "REDEEM_CODE_UNSUPPORTED_TYPE")
    #expect(action(unsupported, retrying: true) == .rejected(message: unsupported.localizedDescription, reportsDefect: true))
    // A refusal of this attempt, a local check or a reply without a reason says nothing about the earlier one.
    let unanswered: [APIError] = [.server(status: 400, reason: nil), .server(status: 400, envelope: nil), .server(status: 500, reason: nil),
                                  APIError(kind: .validation, message: "补偿内容不符合要求。"), .stationMismatch, .otherActorWrite]
    for error in refusedBeforeHandler + unanswered { #expect(action(error, retrying: true) == unconfirmed, "\(error.statusCode ?? 0)") }
    #expect(action(stepUp.withSecurityOutcome(.passed), retrying: true) == .pending(message: "二次验证已通过，请重新确认后发送", retryNotBefore: nil))
    #expect(action(keyed(.needsNewKey(.keyConflict)), retrying: true) == .pending(message: "这个操作编号已被另一笔请求占用，请先核对", retryNotBefore: nil))
    let invalid = keyed(.needsNewKey(.invalid))
    #expect(action(invalid, retrying: true) == .newKeyNeeded(message: invalid.localizedDescription))
    let replayed: Result<WriteOutcome<AdminRedeemCode>, any Error> = .success(WriteOutcome(value: issued, replayed: true))
    #expect(GrantResultAction.classify(replayed, retrying: true) == .granted(issued, replayed: true))
    let refused: Result<WriteOutcome<AdminRedeemCode>, any Error> = .failure(stepUp)
    #expect(GrantResultAction.classify(refused, retrying: true) == unconfirmed)
    #expect(GrantResultAction.classify(refused, retrying: false) == .rejected(message: stepUp.localizedDescription, reportsDefect: false))
}

// MARK: create-and-redeem (60 §19.2, §19.4; R01, R04, X34)

private let redeemedJSON = #"{"redeem_code":{"id":91,"code":"\#(grantCode)","type":"balance","value":10,"status":"used","used_by":42}}"#
private let maskedJSON = #"{"redeem_code":{"id":91,"code":"***","type":"balance","value":10,"status":"used","used_by":42}}"#
private func grantClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func pending(_ client: APIClient, serverID: UUID? = nil, value: Decimal = 10) -> PendingCompensation {
    PendingCompensation(id: grantKey, serverID: serverID ?? client.server.id, actorUserID: 7, createdAt: created, userID: 42,
                        userDisplayName: "王小明", userEmail: "wang@example.com", code: grantCode, type: .balance, value: value)
}
private func failure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}
private func locked() -> ScriptStep { .reply(errorReply(409, reason: "REDEEM_CODE_LOCKED")) }

@Test func createAndRedeemSendsOneKeyedWrite() async throws {
    let transport = ScriptedTransport { _ in okReply(redeemedJSON, headers: ["X-Request-ID": grantKey.uuidString.lowercased()]) }
    let client = grantClient(transport)
    let grant = pending(client)
    let outcome = try await client.createAndRedeem(stubPersisted(grant), sameAddress: [])
    #expect(outcome.value.id == 91 && outcome.value.usedBy == 42 && outcome.value.code == grantCode && !outcome.replayed)
    let request = try #require(await transport.requests.first)
    #expect(await transport.requests.count == 1)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/create-and-redeem")
    #expect(sentHeader(request, "Idempotency-Key") == grant.key); #expect(sentHeader(request, "X-Request-ID") == grant.key)
    #expect(request.httpBody == (try grant.requestBody())); #expect(request.timeoutInterval == 35)
    // A code is worth money: logs and failure messages show only its ends.
    #expect(!String(reflecting: outcome.value).contains(grantCode))

    let replay = ScriptedTransport { _ in okReply(maskedJSON, headers: ["X-Idempotency-Replayed": "true"]) }
    let replayClient = grantClient(replay)
    let replayed = try await replayClient.createAndRedeem(stubPersisted(pending(replayClient)), sameAddress: [])
    #expect(replayed.replayed && replayed.value.isRedacted && replayed.value.id == 91)
}

@Test func lockedIsRetriedOnceAfterTwoSeconds() async throws {
    let recorder = SleepRecorder()
    let transport = ScriptedTransport(script: [locked(), .reply(okReply(redeemedJSON))])
    let client = grantClient(transport, clock: .recording(recorder))
    let grant = pending(client)
    #expect(try await client.createAndRedeem(stubPersisted(grant), sameAddress: []).value.id == 91)
    let requests = await transport.requests, body = try grant.requestBody()
    #expect(requests.count == 2); #expect(await recorder.durations == [.seconds(2)])
    #expect(requests.allSatisfy { $0.httpBody == body && sentHeader($0, "Idempotency-Key") == grant.key && sentHeader($0, "X-Request-ID") == grant.key })

    let twice = ScriptedTransport(script: [locked(), locked()])
    let stillLocked = grantClient(twice)
    #expect(await failure { _ = try await stillLocked.createAndRedeem(stubPersisted(pending(stillLocked)), sameAddress: []) }?.disposition
            == .unconfirmed(.stillProcessing, retryNotBefore: nil))
    #expect(await twice.requests.count == 2)

    // The lock's holder may be running this grant, so a refusal of the second attempt leaves it to be checked.
    let refused = ScriptedTransport(script: [locked(), .reply(errorReply(403, reason: "ACCESS_TOKEN_READ_ONLY"))])
    let refusedClient = grantClient(refused)
    #expect(await failure { _ = try await refusedClient.createAndRedeem(stubPersisted(pending(refusedClient)), sameAddress: []) }?.disposition
            == .unconfirmed(.transport, retryNotBefore: nil))

    let conflict = ScriptedTransport(script: [locked(), .reply(errorReply(409, reason: "REDEEM_CODE_CONFLICT"))])
    let conflictClient = grantClient(conflict)
    let answer = await thrownAPIError { _ = try await conflictClient.createAndRedeem(stubPersisted(pending(conflictClient)), sameAddress: []) }
    #expect(answer?.reason == "REDEEM_CODE_CONFLICT")

    let backoffRecorder = SleepRecorder()
    let backoff = ScriptedTransport(script: [locked(), .reply(errorReply(409, reason: "IDEMPOTENCY_RETRY_BACKOFF", headers: ["Retry-After": "3"])),
                                             .reply(okReply(redeemedJSON))])
    let backoffClient = grantClient(backoff, clock: .recording(backoffRecorder))
    #expect(try await backoffClient.createAndRedeem(stubPersisted(pending(backoffClient)), sameAddress: []).value.id == 91)
    #expect(await backoff.requests.count == 3); #expect(await backoffRecorder.durations == [.seconds(2), .seconds(3)])
}

@Test func transportFailuresBecomeUnconfirmed() async throws {
    let recorder = SleepRecorder()
    let lost = ScriptedTransport { _ in throw URLError(.timedOut) }
    let client = grantClient(lost, clock: .recording(recorder))
    #expect(await failure { _ = try await client.createAndRedeem(stubPersisted(pending(client)), sameAddress: []) }?.disposition
            == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(await lost.requests.count == 3); #expect(await recorder.durations == [.seconds(2), .seconds(5)])

    let clock = ManualClock()
    let store = ScriptedTransport { _ in errorReply(503, reason: "IDEMPOTENCY_STORE_UNAVAILABLE") }
    let storeClient = grantClient(store, clock: clock.requestClock)
    #expect(await failure { _ = try await storeClient.createAndRedeem(stubPersisted(pending(storeClient)), sameAddress: []) }?.disposition
            == .unconfirmed(.storeUnavailable, retryNotBefore: clock.start.addingTimeInterval(10)))
    #expect(await store.requests.count == 1)
}

@Test func createAndRedeemChecksOriginAndBody() async throws {
    let transport = ScriptedTransport { _ in okReply(redeemedJSON) }
    let client = grantClient(transport)
    let oldLogin = UUID()
    let elsewhere = await thrownAPIError { _ = try await client.createAndRedeem(stubPersisted(pending(client, serverID: UUID())), sameAddress: [oldLogin]) }
    #expect(elsewhere == .stationMismatch); #expect(await transport.requests.isEmpty)
    let alone = await thrownAPIError { _ = try await client.createAndRedeem(stubPersisted(pending(client, serverID: oldLogin)), sameAddress: []) }
    #expect(alone == .stationMismatch); #expect(await transport.requests.isEmpty)
    _ = try await client.createAndRedeem(stubPersisted(pending(client, serverID: oldLogin)), sameAddress: [client.server.id, oldLogin])
    #expect(await transport.requests.count == 1)
    let zero = await thrownAPIError { _ = try await client.createAndRedeem(stubPersisted(pending(client, value: 0)), sameAddress: []) }
    #expect(zero?.kind == .validation); #expect(await transport.requests.count == 1)
}

@Test func suspendDuringLockedWaitKeepsItUnconfirmed() async throws {
    let sleeping = OpenGate()
    let clock = RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let transport = ScriptedTransport(script: [locked(), .reply(okReply(redeemedJSON))])
    let client = grantClient(transport, clock: clock)
    let waiting = Task { try await client.createAndRedeem(stubPersisted(pending(client)), sameAddress: []) }
    let watcher = Task { _ = try? await waiting.value; await sleeping.open() }
    await sleeping.wait()
    await client.suspend()
    #expect(await failure { _ = try await waiting.value }?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    _ = await watcher.value
    #expect(await transport.requests.count == 1)

    let gate = OpenGate()
    let cancelClock = RequestClock(sleep: { _ in await gate.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let cancelled = ScriptedTransport(script: [locked(), .reply(okReply(redeemedJSON))])
    let cancelClient = grantClient(cancelled, clock: cancelClock)
    let pendingWrite = Task { try await cancelClient.createAndRedeem(stubPersisted(pending(cancelClient)), sameAddress: []) }
    let cancelWatcher = Task { _ = try? await pendingWrite.value; await gate.open() }
    await gate.wait()
    await cancelClient.cancelAll()
    await #expect(throws: CancellationError.self) { try await pendingWrite.value }
    _ = await cancelWatcher.value
    #expect(await cancelled.requests.count == 1)
}

// MARK: The same address for the gate, the check and the retry (X34, C-26; S6D1-15)

private let currentSite = UUID(uuidString: "5E000000-0000-4000-8000-000000000001")!
private let oldSite = UUID(uuidString: "5E000000-0000-4000-8000-000000000002")!
private func stored(serverID: UUID, userID: Int = 42, actor: Int? = 7) -> PendingCompensation {
    PendingCompensation(id: UUID(), serverID: serverID, actorUserID: actor, createdAt: created, userID: userID, userDisplayName: "王小明",
                        userEmail: "wang@example.com", code: grantCode, type: .balance, value: 10)
}

@Test func compensationGateBlocksAcrossSameAddressSiteIDs() {
    let old = stored(serverID: oldSite)
    let balance = PendingBalanceOperation(serverID: currentSite, userID: 42, amount: 5, operation: .add, actorUserID: 7, createdAt: created)
    let batch = PendingRedeemBatch(serverID: currentSite, actorUserID: 7, createdAt: created, spec: RedeemGenerateSpec(type: .balance, value: 1, count: 1))
    func gate(_ userID: Int, serverIDs: Set<UUID> = [currentSite, oldSite], unavailable: Set<PendingMoneyKind> = []) -> PendingMoneyGate {
        .evaluate(.compensation(userID: userID), serverIDs: serverIDs, balances: [balance], redeemBatches: [batch], compensations: [old],
                  unavailable: unavailable)
    }
    #expect(gate(42) == .blocked([old.id]))
    #expect(gate(43) == .clear)
    #expect(gate(42, serverIDs: [currentSite]) == .clear)
    #expect(gate(42, unavailable: [.compensation]) == .paused(.compensation))
    #expect(gate(42, unavailable: [.balance, .redeemBatch]) == .blocked([old.id]))
    #expect(PendingMoneyGate.evaluate(.compensation(userID: 42), serverIDs: [currentSite, oldSite], balances: [balance], redeemBatches: [batch],
                                      compensations: [], unavailable: []) == .clear)
}

@Test func compensationReconcileAcceptsSameAddressOldSite() async throws {
    let page = #"{"items":[{"id":91,"code":"\#(grantCode)","type":"balance","value":10,"status":"used","used_by":42}],"total":1,"page":1,"page_size":5,"pages":1}"#
    let transport = ScriptedTransport { _ in okReply(page) }
    let client = grantClient(transport)
    let old = stored(serverID: oldSite)
    #expect(try await client.reconcileCompensation(old, sameAddress: [client.server.id, oldSite]) == .issued(issued))
    let request = try #require(await transport.requests.first)
    let url = try #require(request.url)
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    #expect(query["search"] == grantCode && query["page_size"] == "5" && request.httpMethod == "GET")
    #expect(await thrownAPIError { _ = try await client.reconcileCompensation(old) } == .stationMismatch)
    #expect(await transport.requests.count == 1)
}

@Test func compensationRetryPermissionAcrossSiteIDs() {
    let sameAddress: Set<UUID> = [currentSite, oldSite]
    func permission(_ record: PendingCompensation, currentUserID: Int? = 7) -> PendingRetryPermission {
        .evaluate(record, activeServerID: currentSite, currentUserID: currentUserID, sameAddress: sameAddress)
    }
    #expect(permission(stored(serverID: oldSite)) == .allowed)
    #expect(permission(stored(serverID: oldSite, actor: nil)) == .otherActor)
    #expect(permission(stored(serverID: oldSite, actor: 8)) == .otherActor)
    #expect(permission(stored(serverID: UUID())) == .otherActor)
    #expect(permission(stored(serverID: currentSite)) == .allowed)
    // 60 §19.4 step 7: past its expiry the same number still goes, by its sender only.
    let expired = PendingCompensation(serverID: oldSite, actorUserID: 7, createdAt: created.addingTimeInterval(-3 * 86_400), idempotencyExpiresAt: created,
                                      userID: 42, userDisplayName: "王小明", userEmail: "wang@example.com", code: grantCode, type: .balance, value: 10)
    #expect(permission(expired) == .allowed)
    for (record, currentUserID) in [(stored(serverID: oldSite, actor: nil), 7), (stored(serverID: UUID()), 7), (stored(serverID: oldSite), 8)] {
        #expect(throws: APIError.otherActorWrite) {
            try MoneyRecordOrigin.checkSender(actorUserID: record.actorUserID, currentUserID: currentUserID, recordServerID: record.serverID,
                                              currentServerID: currentSite, sameAddress: sameAddress)
        }
    }
}
