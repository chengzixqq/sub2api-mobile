import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private actor ManagedAccountTransport: HTTPTransport {
    private var captured: [URLRequest] = []
    let reply: HTTPResponse
    let fails: Bool
    init(reply: HTTPResponse = HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"success":1,"failed":1,"results":[{"account_id":1,"success":true},{"account_id":2,"success":false,"error":"private upstream details"}]}}"#.utf8)), fails: Bool = false) { self.reply = reply; self.fails = fails }
    func data(for request: URLRequest) async throws -> HTTPResponse {
        captured.append(request)
        if fails { throw URLError(.timedOut) }
        return reply
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw APIError.invalidResponse }
    func requests() -> [URLRequest] { captured }
}
private func managedAccountServer() -> ServerProfile {
    ServerProfile(name: "账号管理测试", baseURL: URL(string: "https://accounts.example.invalid")!, authentication: .adminKey)
}

@Test func accountFiltersUseServerPaginationAndSupportedGlobalSorts() throws {
    var query = AccountListQuery(); query.search = " Alpha & B "; query.type = "apikey"
    query.status = "unschedulable"; query.platform = "openai"; query.group = "10"
    query.sort = .lastUsed; query.descending = true; query.includeSchedulerScore = true
    let fields = Dictionary(uniqueKeysWithValues: try query.queryItems(page: 3).map { ($0.name, $0.value ?? "") })
    #expect(fields["page"] == "3" && fields["page_size"] == "20")
    #expect(fields["search"] == "Alpha & B" && fields["type"] == "apikey")
    #expect(fields["status"] == "unschedulable" && fields["group"] == "10")
    #expect(fields["sort_by"] == "last_used_at" && fields["sort_order"] == "desc")
    #expect(fields["lite"] == "true" && fields["include_scheduler_score"] == "true")
    #expect(!AccountSort.allCases.map(\.rawValue).contains("current_rpm"))
    query.group = "ungrouped"; #expect(throws: Never.self) { _ = try query.queryItems(page: 1) }
    query.group = "-1"; #expect(throws: APIError.self) { _ = try query.queryItems(page: 1) }
    #expect(throws: APIError.self) { _ = try AccountListQuery().queryItems(page: 0) }
}

@Test func accountQuickEditPreservesDecimalAndExplicitClearsWithoutCredentials() throws {
    let request = AccountUpdateRequest(notes: "", concurrency: 0, priority: 0, rateMultiplier: Decimal(string: "0.12345678"), groupIDs: [])
    let bytes = try request.requestBody()
    let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(json["notes"] as? String == "" && json["concurrency"] as? Int == 0)
    #expect(json["group_ids"] as? [Int] == [])
    #expect(json["name"] == nil && json["credentials"] == nil && json["extra"] == nil)
    #expect(String(decoding: bytes, as: UTF8.self).contains("0.12345678"))
    let clearLoad = try JSONSerialization.jsonObject(with: AccountUpdateRequest(loadFactor: 0).requestBody()) as? [String: Any]
    #expect(clearLoad?["load_factor"] as? Int == 0)
    for invalid in [AccountUpdateRequest(), AccountUpdateRequest(name: "  "), AccountUpdateRequest(concurrency: -1), AccountUpdateRequest(priority: -1), AccountUpdateRequest(rateMultiplier: -1), AccountUpdateRequest(loadFactor: -1), AccountUpdateRequest(loadFactor: 10_001), AccountUpdateRequest(groupIDs: [10, 10])] {
        #expect(throws: APIError.self) { try invalid.validate() }
    }
}

@Test func accountWritesRejectOldIdentityAndNeverReplayUnknownResults() async throws {
    let transport = ManagedAccountTransport(fails: true)
    let server = managedAccountServer()
    let client = APIClient(server: server, credential: .adminKey("fixture"), transport: transport)
    let identity = await client.userWriteIdentity()
    let pending = try PendingAccountUpdate(serverID: server.id, identity: identity, accountID: 4, request: AccountUpdateRequest(notes: "说明"))
    await #expect(throws: APIError.self) { try await client.updateAccount(pending) }
    #expect(await transport.requests().count == 1)
    let sent = try #require(await transport.requests().first)
    #expect(sent.httpMethod == "PUT" && sent.url?.path == "/api/v1/admin/accounts/4" && sent.httpBody == pending.body)
    await client.cancelAll()
    await #expect(throws: APIError.self) { try await client.updateAccount(pending) }
    await #expect(throws: APIError.self) { try await client.setAccountsSchedulable(ids: [4], enabled: false, identity: identity) }
    await #expect(throws: APIError.self) { try await client.refreshManagedAccount(id: 4, identity: identity) }
    #expect(await transport.requests().count == 1)
}

@Test func bulkAccountSchedulingPreservesPartialFailureAndUnknownRows() async throws {
    let transport = ManagedAccountTransport()
    let client = APIClient(server: managedAccountServer(), credential: .adminKey("fixture"), transport: transport)
    let identity = await client.userWriteIdentity()
    let result = try await client.setAccountsSchedulable(ids: [1, 2], enabled: false, identity: identity)
    #expect(result.outcome(for: 1) == true && result.outcome(for: 2) == false && result.outcome(for: 3) == nil)
    let sent = try #require(await transport.requests().first)
    let json = try #require(JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any])
    #expect(json["account_ids"] as? [Int] == [1, 2] && json["schedulable"] as? Bool == false)
    #expect(sent.url?.path == "/api/v1/admin/accounts/bulk-update" && sent.httpMethod == "POST")
    await #expect(throws: APIError.self) { try await client.setAccountsSchedulable(ids: [1, 1], enabled: false, identity: identity) }
    await #expect(throws: APIError.self) { try await client.setAccountsSchedulable(ids: Array(1...51), enabled: false, identity: identity) }
    #expect(await transport.requests().count == 1)
    let duplicate = try JSONDecoder().decode(AccountBulkReply.self, from: Data(#"{"success":2,"failed":0,"results":[{"account_id":1,"success":true},{"account_id":1,"success":true}]}"#.utf8))
    #expect(duplicate.outcome(for: 1) == nil)
}

/// Every later account would meet the same ended session or security gate, so the batch stops there (00 §1.7.2, D06).
@Test func batchRefreshStopsOnEveryEndedSessionAndSecurityRefusal() {
    let stopping: [APIError] = [
        .server(status: 401, reason: "TOKEN_REVOKED"), .server(status: 401, reason: "SESSION_BINDING_MISMATCH"),
        .server(status: 401, reason: "INVALID_ADMIN_KEY"), .server(status: 401, reason: "ACCESS_TOKEN_EXPIRED"), .server(status: 401, reason: nil),
        .server(status: 403, reason: "WORKSPACE_DISABLED"), .server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"),
        .server(status: 403, reason: "STEP_UP_REQUIRED"), .server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), .authenticationRequired
    ]
    for error in stopping { #expect(AccountBatchRefresh.stopsRemaining(after: error), "\(error.statusCode ?? 0) \(error.reason ?? "-")") }
    let continuing: [any Error] = [APIError.server(status: 400, reason: "INVALID_REQUEST"), APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"),
                                   APIError.server(status: 500, reason: nil), APIError.server(status: 403, reason: "FORBIDDEN"),
                                   APIError.transport(URLError(.timedOut)), URLError(.timedOut)]
    for error in continuing { #expect(!AccountBatchRefresh.stopsRemaining(after: error), "\(error)") }
}
