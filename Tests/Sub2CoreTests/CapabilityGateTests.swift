import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 00 §9.8 “没有 capability 时不发新参数” (D24): from what me() reports to what goes on the wire. Stage 0 has two gated
// sends: the Idempotency-Key of user writes (admin.idempotent_writes) and since_id of incremental reads (logs.since_id).

private let gatewayNotFound = HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))
private let modernMeJSON = #"""
{"auth_method":"admin_api_key","user":{"id":1,"email":"admin@example.invalid","role":"admin"},"workspace":null,
 "server":{"version":"1.0.0","capabilities":["admin.idempotent_writes","logs.since_id"]}}
"""#

/// `modern` answers admin/me with both capabilities; otherwise the site predates it (gateway 404, 00 §1.9).
private func gateTransport(modern: Bool) -> ScriptedTransport {
    ScriptedTransport { request in
        switch request.url?.path ?? "" {
        case "/api/v1/admin/me": return modern ? okReply(modernMeJSON) : gatewayNotFound
        case "/api/v1/admin/compliance": return okReply(#"{"required":false}"#)
        case "/api/v1/settings/public": return okReply("{}")
        default: return okReply(stubUserJSON)
        }
    }
}
private func gateClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
}
private struct GateRow: IncrementalRecord {
    let id: Int
    let createdAt: String
}

@Test func legacyServerReportsNoCapabilityAndSendsNoNewParameters() async throws {
    let transport = gateTransport(modern: false)
    let me = try await gateClient(transport).me()
    #expect(me.isLegacyServer); #expect(me.capabilities.isEmpty)
    #expect(Capability.allCases.allSatisfy { !me.has($0) })
    let requests = await transport.requests
    #expect(Set(requests.compactMap { $0.url?.path }) == ["/api/v1/admin/me", "/api/v1/admin/compliance", "/api/v1/settings/public"])
    #expect(requests.allSatisfy { $0.url?.query == nil })
}

@Test(arguments: [false, true])
func userWritesCarryIdempotencyKeyOnlyWithTheCapability(modern: Bool) async throws {
    let transport = gateTransport(modern: modern)
    let client = gateClient(transport)
    let sendsKey = try await client.me().has(.adminIdempotentWrites)
    #expect(sendsKey == modern)
    let identity = await client.userWriteIdentity()
    let create = try PendingUserCreateOperation(serverID: client.server.id, identity: identity,
                                                request: UserCreateRequest(email: "new@example.invalid", password: "fixture-password"),
                                                sendsIdempotencyKey: sendsKey)
    _ = try await client.createUser(create)
    let update = try PendingUserUpdateOperation(serverID: client.server.id, identity: identity, userID: 7,
                                                request: UserUpdateRequest(notes: "gate"), serverSupportsIdempotentWrites: sendsKey)
    _ = try await client.updateUser(update)
    let writes = await transport.requests.filter { $0.httpMethod != "GET" }
    #expect(writes.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == ["POST /api/v1/admin/users", "PUT /api/v1/admin/users/7"])
    for (request, key) in zip(writes, [create.key, update.key]) {
        #expect(sentHeader(request, "X-Request-ID") == key)
        #expect(sentHeader(request, "Idempotency-Key") == (modern ? key : nil))
    }
}

@Test(arguments: [false, true])
func incrementalReadsSendSinceIDOnlyWithTheCapability(modern: Bool) async throws {
    let supportsSinceID = try await gateClient(gateTransport(modern: modern)).me().has(.logsSinceID)
    #expect(supportsSinceID == modern)
    let list = IncrementalList<GateRow>().reset(firstPage: [GateRow(id: 9, createdAt: "2026-10-22T01:40:00Z"),
                                                            GateRow(id: 5, createdAt: "2026-10-22T01:39:00Z")])
    let now = try #require(ServerTime.parseTimestamp("2026-10-22T01:41:00Z"))
    let items = list.nextFetch(supportsSinceID: supportsSinceID, now: now)
        .queryItems(base: [URLQueryItem(name: "account_id", value: "9")], deferredCount: true)
    let names = Set(items.map(\.name))
    if modern {
        #expect(names == ["account_id", "page_size", "since_id"])
    } else {
        #expect(!names.contains("since_id"))
        #expect(names.isSuperset(of: ["page", "start_time", "end_time", "count_mode"]))
        #expect(items.filter { $0.name.hasSuffix("_time") }.allSatisfy { $0.value?.hasSuffix("Z") == true })
    }
}
