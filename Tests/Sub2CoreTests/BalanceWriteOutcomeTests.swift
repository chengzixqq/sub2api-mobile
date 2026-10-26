import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 30 §3.4 result table, R04 and the S0-06 rule that a refusal after an uncertain attempt stays unconfirmed; the
// X-Request-ID echo check.

/// AdminUser is not Equatable, so outcomes are compared through this.
private enum Verdict: Equatable {
    case executed(userID: Int, replayed: Bool)
    case notExecuted(String)
    case pending(String, Date?)
}
private func verdict(_ outcome: BalanceWriteOutcome) -> Verdict {
    switch outcome {
    case .executed(let user, let replayed): .executed(userID: user.id, replayed: replayed)
    case .notExecuted(let message): .notExecuted(message)
    case .pending(let message, let retryNotBefore): .pending(message, retryNotBefore)
    }
}
private func verdict(_ error: any Error, retrying: Bool = false) -> Verdict {
    verdict(BalanceReconciliation.balanceWriteOutcome(for: error, retrying: retrying))
}
private func adminUser() throws -> AdminUser { try JSONDecoder().decode(AdminUser.self, from: Data(stubUserJSON.utf8)) }
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: "1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f", actionID: nil, lastError: nil)
}
private let unconfirmed = Verdict.pending("结果未确认，已记为待核对", nil)
private let cooldownEnd = Date(timeIntervalSince1970: 1_800_000_010)

private func balanceClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func persistedWrite(_ client: APIClient, serverID: UUID? = nil) -> PersistedMoneyWrite<PendingBalanceOperation> {
    stubPersisted(PendingBalanceOperation(serverID: serverID ?? client.server.id, userID: 7, amount: 1, operation: .add))
}

@Test func successfulWritesAreExecuted() throws {
    let user = try adminUser()
    for (outcome, replayed) in [(WriteOutcome(value: user), false), (WriteOutcome(value: user, degraded: true), false), (WriteOutcome(value: user, replayed: true), true)] {
        let result = BalanceReconciliation.balanceWriteOutcome(for: outcome)
        #expect(verdict(result) == .executed(userID: 7, replayed: replayed))
        #expect(result.resolvesRecord)
    }
}

@Test func definiteRefusalsResolve() {
    let fixed: [(APIError, String)] = [
        (.server(status: 400, reason: "INVALID_BALANCE"), "金额不合法，未入账"),
        (.server(status: 400, reason: nil), "请求无效（错误码 HTTP 400），未入账"),
        (.server(status: 400, envelope: nil), "请求无效（错误码 HTTP 400），未入账"),
        (.server(status: 400, reason: "IDEMPOTENCY_KEY_REQUIRED"), "请求格式错误，未入账"),
        (.server(status: 400, reason: "IDEMPOTENCY_KEY_INVALID"), "请求格式错误，未入账"),
        (.server(status: 400, reason: "IDEMPOTENCY_PAYLOAD_INVALID"), "请求格式错误，未入账"),
        (.server(status: 400, reason: "VALIDATION_ERROR"), "请求参数有误（错误码 VALIDATION_ERROR），未入账"),
        (.server(status: 404, reason: "USER_NOT_FOUND"), "用户不存在或已删除"),
        (.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), "当前管理访问令牌只读，不能执行此操作")
    ]
    for (error, message) in fixed { #expect(verdict(error) == .notExecuted(message)) }
    let catalog: [APIError] = [.server(status: 401, reason: nil), .server(status: 403, reason: "STEP_UP_REQUIRED"), .server(status: 423, reason: nil),
                               .server(status: 429, reason: "RATE_LIMITED"), .server(status: 503, reason: "STEP_UP_UNAVAILABLE"), .invalidAmount,
                               .server(status: 404, reason: "RESOURCE_NOT_FOUND")]
    for error in catalog {
        #expect(verdict(error) == .notExecuted(error.localizedDescription))
        #expect(BalanceReconciliation.balanceWriteOutcome(for: error, retrying: false).resolvesRecord)
    }
}

@Test func keyedFailuresMapToTheTable() {
    #expect(verdict(keyed(.needsNewKey(.invalid))) == .notExecuted("请求格式错误，未入账"))
    #expect(verdict(keyed(.needsNewKey(.keyRequired))) == .notExecuted("请求格式错误，未入账"))
    #expect(verdict(keyed(.needsNewKey(.keyConflict))) == .pending("这个操作编号已被另一笔请求占用，请先核对", nil))
    #expect(verdict(keyed(.unconfirmed(.storeUnavailable, retryNotBefore: cooldownEnd))) == .pending("服务器暂时无法受理，稍后用同一编号重试", cooldownEnd))
    for cause: KeyedWriteFailure.UnconfirmedCause in [.transport, .stillProcessing, .unreadableResponse] {
        #expect(verdict(keyed(.unconfirmed(cause, retryNotBefore: nil))) == unconfirmed)
    }
    #expect(!BalanceReconciliation.balanceWriteOutcome(for: keyed(.needsNewKey(.keyConflict)), retrying: false).resolvesRecord)
}

@Test func serverAndNetworkFailuresStayPending() {
    let errors: [any Error] = [APIError.server(status: 500, reason: nil), APIError.server(status: 502, envelope: nil), APIError.server(status: 503, reason: nil),
                               APIError.server(status: 409, reason: "IDEMPOTENCY_IN_PROGRESS"), APIError.server(status: 418, reason: nil),
                               APIError(kind: .transport, message: "无法连接站点"), CancellationError(), URLError(.timedOut)]
    for error in errors {
        for retrying in [false, true] {
            #expect(verdict(error, retrying: retrying) == unconfirmed)
            #expect(!BalanceReconciliation.balanceWriteOutcome(for: error, retrying: retrying).resolvesRecord)
        }
    }
}

/// S0-06: once an attempt may have run, a later refusal of a retry says nothing about it; only a refusal decided by the body
/// (the same bytes were refused before as well) still settles it.
@Test func refusalAfterUncertainAttemptStaysPending() {
    let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
    let refusals: [APIError] = [.server(status: 401, reason: nil), stepUp, stepUp.withSecurityOutcome(.passed), stepUp.withSecurityOutcome(.cancelled),
                                .server(status: 423, reason: nil), .server(status: 429, reason: "RATE_LIMITED"), .server(status: 404, reason: "USER_NOT_FOUND"),
                                .server(status: 503, reason: "STEP_UP_UNAVAILABLE"), .server(status: 400, reason: "VALIDATION_ERROR"), .stationMismatch]
    for error in refusals {
        #expect(verdict(error, retrying: true) == unconfirmed)
        guard case .notExecuted = verdict(error, retrying: false) else { Issue.record("a first send refused before execution resolves"); continue }
    }
    #expect(verdict(APIError.server(status: 400, reason: "INVALID_BALANCE"), retrying: true) == .notExecuted("金额不合法，未入账"))
    #expect(verdict(APIError.server(status: 400, reason: nil), retrying: true) == .notExecuted("请求无效（错误码 HTTP 400），未入账"))
    #expect(verdict(keyed(.needsNewKey(.invalid)), retrying: true) == .notExecuted("请求格式错误，未入账"))
    #expect(verdict(keyed(.needsNewKey(.keyConflict)), retrying: true) == .pending("这个操作编号已被另一笔请求占用，请先核对", nil))
}

@Test func executorResultsFlowThroughOutcome() async throws {
    let refused = ScriptedTransport { _ in errorReply(400, reason: "INVALID_BALANCE") }
    let invalid = balanceClient(refused)
    do { _ = try await invalid.updateBalance(persistedWrite(invalid)); Issue.record("expected a refusal") }
    catch { #expect(verdict(error) == .notExecuted("金额不合法，未入账")) }

    let gateway = ScriptedTransport { _ in HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8)) }
    let lost = balanceClient(gateway)
    do { _ = try await lost.updateBalance(persistedWrite(lost)); Issue.record("expected an unconfirmed write") }
    catch { #expect(error is KeyedWriteFailure); #expect(verdict(error) == unconfirmed) }
    #expect(await gateway.requests.count == 3)

    let rewritten = ScriptedTransport { _ in okReply(stubUserJSON, headers: ["X-Request-ID": "proxy-generated"]) }
    let echoing = balanceClient(rewritten)
    let sent = persistedWrite(echoing)
    let outcome = try await echoing.updateBalance(sent)
    #expect(BalanceReconciliation.requestIDEchoMismatch(sent: sent.record.key, echoed: outcome.requestID))
    #expect(verdict(BalanceReconciliation.balanceWriteOutcome(for: outcome)) == .executed(userID: 7, replayed: false))
}

@Test func updateBalanceAcceptsSameAddressRecordsOnly() async throws {
    let transport = ScriptedTransport { _ in okReply(stubUserJSON, headers: ["X-Request-ID": "echo"]) }
    let client = balanceClient(transport), oldLogin = UUID()
    let retried = persistedWrite(client, serverID: oldLogin), body = try retried.record.requestBody()
    #expect(try await client.updateBalance(retried, sameAddress: [client.server.id, oldLogin]).value.id == 7)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(sentHeader(requests.first, "Idempotency-Key") == retried.record.key); #expect(sentHeader(requests.first, "X-Request-ID") == retried.record.key)
    #expect(requests.first?.httpBody == body)
    #expect(requests.first?.url?.path == "/api/v1/admin/users/7/balance")
    await #expect(throws: APIError.stationMismatch) { try await client.updateBalance(persistedWrite(client, serverID: UUID()), sameAddress: [client.server.id, oldLogin]) }
    #expect(await transport.requests.count == 1)
}

@Test func resultOverloadMatchesSplitOverloads() throws {
    let outcome = WriteOutcome(value: try adminUser(), replayed: true)
    for retrying in [false, true] {
        let success = BalanceReconciliation.balanceWriteOutcome(for: .success(outcome), retrying: retrying)
        #expect(verdict(success) == verdict(BalanceReconciliation.balanceWriteOutcome(for: outcome)))
        let samples: [any Error] = [APIError.server(status: 400, reason: "INVALID_BALANCE"), APIError.server(status: 429, reason: "RATE_LIMITED"),
                                    keyed(.unconfirmed(.storeUnavailable, retryNotBefore: cooldownEnd))]
        for error in samples {
            #expect(verdict(BalanceReconciliation.balanceWriteOutcome(for: .failure(error), retrying: retrying)) == verdict(error, retrying: retrying))
        }
    }
}

@Test func requestIDEchoMismatchRules() {
    let sent = "1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f"
    #expect(!BalanceReconciliation.requestIDEchoMismatch(sent: sent, echoed: sent))
    #expect(BalanceReconciliation.requestIDEchoMismatch(sent: sent, echoed: "9f0e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c"))
    // No header is no evidence; spacing and case are not a rewrite.
    #expect(!BalanceReconciliation.requestIDEchoMismatch(sent: sent, echoed: nil))
    #expect(!BalanceReconciliation.requestIDEchoMismatch(sent: sent, echoed: "  "))
    #expect(!BalanceReconciliation.requestIDEchoMismatch(sent: sent, echoed: " " + sent.uppercased() + " "))
}
