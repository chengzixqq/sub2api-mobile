import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decodeSummary(_ json: String) throws -> AccountStatusSummary {
    try JSONDecoder().decode(AccountStatusSummary.self, from: Data(json.utf8))
}
private func summaryClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
}
private func counts() -> String {
    #""total":10,"available":3,"error":1,"overloaded":2,"rate_limited":1,"temp_unschedulable":1,"paused":1,"inactive":1,"stopped":2"#
}
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private let fullSummary = #"""
{"collected_at":"2026-10-22T10:00:00.123456789Z",
 "totals":{\#(counts())},
 "platforms":[{"platform":"anthropic",\#(counts())},{"platform":"openai","total":2,"available":2,"error":0,"overloaded":0,"rate_limited":0,"temp_unschedulable":0,"paused":0,"inactive":0,"stopped":0}],
 "groups":[
  {"group_id":7,"group_name":"高级组","platform":"anthropic","group_status":"active",\#(counts()),"shortage":{"is_short":true,"source":"alert_rule","rule_id":7,"metric_type":"group_available_ratio","operator":"<","threshold":50,"current":33.3}},
  {"group_id":8,"group_name":"备用组","platform":"openai","group_status":"inactive","total":4,"available":1,"error":0,"overloaded":0,"rate_limited":0,"temp_unschedulable":0,"paused":3,"inactive":0,"stopped":0,"shortage":{"is_short":true,"source":"default","threshold":0.5,"current":0.25}}
 ],
 "accounts":[
  {"id":1,"name":"A","platform":"anthropic","group_ids":[7],"state":"rate_limited","stopped":true,"status":"active","schedulable":false,"error_message":"server-private-text","rate_limit_reset_at":"2026-10-22T18:30:00+08:00","overload_until":null,"temp_unschedulable_until":null,"temp_unschedulable_reason":"","expires_at":"2026-12-01T00:00:00Z","model_rate_limits":[{"model":"claude-opus","reset_at":"2026-10-22T10:20:00Z"},{"model":"bad","reset_at":"garbage"},{"reset_at":"2026-10-22T10:20:00Z"}]},
  {"id":2,"name":"B","platform":"openai","group_ids":[],"state":"frozen","stopped":false,"status":"active","schedulable":true,"error_message":"","rate_limit_reset_at":null,"overload_until":null,"temp_unschedulable_until":null,"temp_unschedulable_reason":"","expires_at":null,"model_rate_limits":[]}
 ]}
"""#

@Test func statusSummaryDecodesBackendShape() throws {
    let summary = try decodeSummary(fullSummary)
    let collected = try #require(summary.collectedAt)
    #expect(abs(collected.timeIntervalSince1970 - 1_792_663_200.123) <= 0.001)
    let expected = AccountStateCounts(total: 10, available: 3, error: 1, overloaded: 2, rateLimited: 1, tempUnschedulable: 1, paused: 1, inactive: 1, stopped: 2)
    #expect(summary.totals == expected)
    #expect(summary.platforms.map(\.platform) == ["anthropic", "openai"] && summary.platforms[0].counts == expected)
    #expect(summary.platforms[1].counts.available == 2 && summary.platforms[1].id == "openai")
    let rule = summary.groups[0], fallback = summary.groups[1]
    #expect(rule.groupID == 7 && rule.id == 7 && rule.groupName == "高级组" && rule.platform == "anthropic" && rule.groupStatus == "active")
    #expect(rule.counts == expected)
    #expect(rule.shortage == .init(isShort: true, source: "alert_rule", ruleID: 7, metricType: "group_available_ratio", comparison: "<", threshold: 50, current: 33.3))
    #expect(rule.shortage.isFromAlertRule && !fallback.shortage.isFromAlertRule)
    #expect(fallback.groupStatus == "inactive" && fallback.counts.paused == 3)
    #expect(fallback.shortage == .init(isShort: true, source: "default", threshold: 0.5, current: 0.25))
    let first = summary.accounts[0]
    #expect(first.id == 1 && first.name == "A" && first.platform == "anthropic" && first.groupIDs == [7])
    #expect(first.state == .rateLimited && first.stopped && first.status == "active" && !first.schedulable)
    #expect(first.rateLimitResetAt == ServerTime.parseTimestamp("2026-10-22T10:30:00Z"))
    #expect(first.overloadUntil == nil && first.tempUnschedulableUntil == nil && first.tempUnschedulableReason == "")
    #expect(first.expiresAt == ServerTime.parseTimestamp("2026-12-01T00:00:00Z"))
    #expect(first.modelRateLimits == [AccountModelRateLimit(model: "claude-opus", resetAt: ServerTime.parseTimestamp("2026-10-22T10:20:00Z")!)])
    #expect(summary.accounts[1].state == nil && summary.accounts[1].groupIDs.isEmpty)
    #expect(!summary.accountsTruncated)
    #expect(!String(describing: summary).contains("server-private-text"))
}

@Test func statusSummaryToleratesMissingFields() throws {
    let empty = try decodeSummary("{}")
    #expect(empty.totals == AccountStateCounts() && empty.totals.total == 0)
    #expect(empty.platforms.isEmpty && empty.groups.isEmpty && empty.accounts.isEmpty)
    #expect(empty.collectedAt == nil && !empty.accountsTruncated)
    let sparse = try decodeSummary(#"{"collected_at":"bad","totals":{"error":2},"groups":[{"group_id":5}],"accounts":[{"id":4}],"platforms":null}"#)
    #expect(sparse.collectedAt == nil && sparse.totals.error == 2 && sparse.totals.total == 0)
    let group = try #require(sparse.groups.first)
    #expect(group.groupName == "" && group.platform == "" && group.groupStatus == "" && !group.shortage.isShort)
    #expect(group.shortage.source == nil && group.counts == AccountStateCounts())
    let item = try #require(sparse.accounts.first)
    #expect(item == AccountStatusItem(id: 4, status: "", schedulable: false))
    #expect(sparse.platforms.isEmpty)
    // One unreadable row is dropped instead of failing the badge and every group head.
    let rows = try decodeSummary(#"{"totals":[],"platforms":[{"total":1},{"platform":"openai","total":"x"}],"groups":[{"group_name":"缺编号"},{"group_id":6,"shortage":"x"}],"accounts":[{"name":"缺编号"},7,{"id":5,"state":3,"group_ids":"x","model_rate_limits":{}}]}"#)
    #expect(rows.totals == AccountStateCounts())
    #expect(rows.platforms == [AccountStatusPlatformSummary(platform: "openai")])
    #expect(rows.groups.map(\.groupID) == [6] && !rows.groups[0].shortage.isShort)
    #expect(rows.accounts.map(\.id) == [5] && rows.accounts[0].state == nil && rows.accounts[0].groupIDs.isEmpty)
    #expect(rows.accounts[0].modelRateLimits.isEmpty)
}

@Test func homeAvailabilityDecodesWithSameModel() throws {
    let availability = try decodeSummary(#"{"collected_at":"2026-10-22T10:00:00Z","totals":{\#(counts())},"groups":[],"accounts":[{"id":1,"state":"error","status":"error","schedulable":true},{"id":2,"state":"overloaded","status":"active","schedulable":true,"overload_until":"2026-10-22T10:01:00Z"}],"accounts_truncated":true}"#)
    #expect(availability.accountsTruncated && availability.platforms.isEmpty)
    #expect(availability.accounts.map(\.state) == [.error, .overloaded])
    #expect(availability.totals.needsAttention == 5)
}

@Test func stateCountsHelpers() {
    let counts = AccountStateCounts(total: 20, available: 4, error: 1, overloaded: 2, rateLimited: 3, tempUnschedulable: 4, paused: 5, inactive: 1, stopped: 6)
    #expect(counts.needsAttention == 10)
    #expect(counts.limited == 9)
    #expect(AccountStateCounts().needsAttention == 0)
}

@Test func accountStatusSummaryRequestEncodesOnlyGivenParameters() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"collected_at":"2026-10-22T10:00:00Z","totals":{"total":1,"available":1},"groups":[]}"#) }
    let client = summaryClient(transport)
    let summary = try await client.accountStatusSummary()
    #expect(summary.totals.available == 1)
    var requests = await transport.requests
    let plain = try #require(requests.first)
    #expect(requests.count == 1 && plain.httpMethod == "GET" && plain.httpBody == nil)
    #expect(plain.url?.path == "/api/v1/admin/accounts/status-summary" && plain.url?.query == nil)
    #expect(sentHeader(plain, "x-api-key") == "fixture-admin-key")
    _ = try await client.accountStatusSummary(platform: " anthropic ", groupID: 7, includeAccounts: true)
    _ = try await client.accountStatusSummary(platform: "  ", groupID: nil, includeAccounts: false)
    requests = await transport.requests
    #expect(sentQuery(requests[1]) == ["platform": "anthropic", "group_id": "7", "include_accounts": "true"])
    #expect(requests[2].url?.query == nil)
}

@Test(arguments: [0, -1])
func accountStatusSummaryRejectsInvalidGroupLocally(groupID: Int) async throws {
    let transport = ScriptedTransport { _ in okReply("{}") }
    let error = await thrownAPIError { _ = try await summaryClient(transport).accountStatusSummary(groupID: groupID) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func accountStatusSummaryErrorsAreClassified() async throws {
    let rejected = ScriptedTransport { _ in errorReply(400, reason: "INVALID_GROUP_FILTER", extra: #","message":"server-private-text""#) }
    let error = try #require(await thrownAPIError { _ = try await summaryClient(rejected).accountStatusSummary(groupID: 7) })
    #expect(error.reason == "INVALID_GROUP_FILTER" && error.statusCode == 400)
    #expect(!error.localizedDescription.contains("server-private-text"))
    #expect(await rejected.requests.count == 1)
    let oldSite = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["content-type": "text/html"], data: Data("<html>not found</html>".utf8)) }
    let missing = try #require(await thrownAPIError { _ = try await summaryClient(oldSite).accountStatusSummary() })
    #expect(missing.kind == .unsupported)
}
