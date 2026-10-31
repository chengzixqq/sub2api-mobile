import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func listClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
}
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func values(_ items: [URLQueryItem]) -> [String: String] {
    Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private struct SentUsage: Decodable {
    let userIDs: [Int]
    enum CodingKeys: String, CodingKey { case userIDs = "user_ids" }
}
private func sentIDs(_ request: URLRequest?) -> [Int] { (try? JSONDecoder().decode(SentUsage.self, from: request?.httpBody ?? Data()))?.userIDs ?? [] }
/// `today_actual_cost` is "<id>.5", so a merged value shows which reply it came from.
private func usageJSON(ids: [Int]) -> String {
    let items = ids.map { #""\#($0)":{"user_id":\#($0),"today_actual_cost":\#($0).5,"total_actual_cost":"30","by_platform":[{"platform":"openai","today_actual_cost":1.25,"total_actual_cost":"2"}]}"# }
    return "{\"stats\":{\(items.joined(separator: ","))}}"
}
private func tooManyIDs(max limit: String?) -> HTTPResponse {
    let metadata = limit.map { #","metadata":{"field":"user_ids","max":"\#($0)"}"# } ?? #","metadata":{"field":"user_ids"}"#
    return errorReply(400, reason: "TOO_MANY_IDS", extra: metadata)
}
private func decodeUser(_ json: String) throws -> AdminUser { try JSONDecoder().decode(AdminUser.self, from: Data(json.utf8)) }
private func decodeSettings(_ json: String) throws -> PublicSettings { try JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8)) }

// MARK: - UserListQuery

@Test func userListQueryUsesFixedSortAndDefaultPageSize() throws {
    let query = UserListQuery()
    #expect(query.search == nil && query.page == 1 && query.pageSize == 20 && query.role == nil)
    #expect(UserListQuery.usageBatchSize == 200)
    #expect(values(try query.queryItems()) == ["page": "1", "page_size": "20", "sort_by": "created_at", "sort_order": "desc",
                                               "include_subscriptions": "false"])
}

@Test func userListQueryTrimsAndCutsSearchAndSendsRole() throws {
    #expect(UserListQuery(search: "  alice@example.invalid \n").normalizedSearch == "alice@example.invalid")
    #expect(UserListQuery(search: " \n ").normalizedSearch == nil)
    #expect(values(try UserListQuery(search: "   ").queryItems())["search"] == nil)
    #expect(UserListQuery(search: String(repeating: "测", count: 101)).normalizedSearch == String(repeating: "测", count: 100))
    let family = "👨‍👩‍👧"
    #expect(UserListQuery(search: String(repeating: "a", count: 99) + family + "b").normalizedSearch == String(repeating: "a", count: 99) + family)
    let admins = values(try UserListQuery(pageSize: 1, role: "admin").queryItems())
    #expect(admins["role"] == "admin" && admins["page_size"] == "1" && admins["search"] == nil)
    #expect(values(try UserListQuery(search: "wang", page: 3, pageSize: 5).queryItems()) == [
        "page": "3", "page_size": "5", "sort_by": "created_at", "sort_order": "desc", "include_subscriptions": "false", "search": "wang"])
    #expect(values(try UserListQuery(pageSize: 1_000).queryItems())["page_size"] == "1000")
    #expect(values(try UserListQuery(role: " ").queryItems())["role"] == nil)
    #expect(throws: APIError.self) { try UserListQuery(page: 0).queryItems() }
}

@Test func usersQuerySendsOneGETWithoutStatusAndDecodesThePage() async throws {
    let page = "{\"items\":[\(stubUserJSON)],\"total\":41,\"page\":2,\"page_size\":20,\"pages\":3}"
    let transport = ScriptedTransport { _ in okReply(page) }
    let client = listClient(transport)
    let result = try await client.users(query: UserListQuery(search: " a+b@example.invalid ", page: 2))
    #expect(result.total == 41 && result.pages == 3 && result.page == 2 && result.hasMore && result.items.map(\.id) == [7])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/users" && request.timeoutInterval == 20)
    let encoded = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery })
    #expect(encoded.contains("a%2Bb"))
    #expect(sentQuery(request) == ["page": "2", "page_size": "20", "sort_by": "created_at", "sort_order": "desc",
                                   "include_subscriptions": "false", "search": "a+b@example.invalid"])
    let invalid = await thrownAPIError { _ = try await client.users(query: UserListQuery(page: 0)) }
    #expect(invalid?.kind == .validation)
    #expect(await transport.requests.count == 1)
}

// MARK: - quick-topup

@Test func quickTopupDecodesTheServerShapeAndDropsOnlyBadItems() async throws {
    let recent = #"{"user_id":3,"email":"wang@example.invalid","username":"王小明","status":"active","balance":12.5,"last_adjusted_at":"2026-10-20T08:00:00+08:00","last_delta":"50.00000000","last_operation":"add"}"#
    let low = #"{"user_id":4,"email":"low@example.invalid","username":"","status":"active","balance":"1.5","effective_threshold":10,"threshold_source":"global","threshold_type":"fixed"}"#
    let bad = #"{"email":"nobody@example.invalid"},{"user_id":0,"email":"zero@example.invalid"},"x",{"user_id":5,"email":"odd@example.invalid","balance":"oops","last_adjusted_at":7}"#
    let transport = ScriptedTransport { _ in okReply("{\"recent\":[\(recent),\(bad)],\"low_balance\":[\(low)],\"low_balance_enabled\":true}") }
    let reply = try await listClient(transport).quickTopup()
    #expect(reply.recent.map(\.userID) == [3, 5] && reply.lowBalanceEnabled == true)
    let first = try #require(reply.recent.first)
    #expect(first.id == 3 && first.email == "wang@example.invalid" && first.username == "王小明" && first.status == "active")
    #expect(first.balance == Decimal(string: "12.5") && first.lastDelta == 50 && first.lastOperation == "add" && first.displayName == "王小明")
    #expect(first.lastAdjustedAt == Date(timeIntervalSince1970: 1_792_454_400))
    #expect(first.effectiveThreshold == nil && first.thresholdSource == nil && first.thresholdType == nil)
    let odd = try #require(reply.recent.last)
    #expect(odd.balance == nil && odd.lastAdjustedAt == nil && odd.displayName == "odd")
    let lowest = try #require(reply.lowBalance.first)
    #expect(lowest.userID == 4 && lowest.displayName == "low" && lowest.balance == Decimal(string: "1.5"))
    #expect(lowest.effectiveThreshold == 10 && lowest.thresholdSource == "global" && lowest.thresholdType == "fixed" && lowest.lastDelta == nil)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/users/quick-topup" && request.url?.query == nil)
    #expect(try await listClient(ScriptedTransport { _ in okReply("{}") }).quickTopup() == QuickTopupReply())
    let nulls = try await listClient(ScriptedTransport { _ in okReply(#"{"recent":null,"low_balance":{},"low_balance_enabled":"yes"}"#) }).quickTopup()
    #expect(nulls == QuickTopupReply())
}

// MARK: - users-usage

@Test func usersTodayUsageSendsAscendingBatchesOf200AndKeepsOnlyRequestedIDs() async throws {
    // Each reply leaves out the last id it was asked for and adds one nobody asked for.
    let transport = ScriptedTransport { request in okReply(usageJSON(ids: Array(sentIDs(request).dropLast()) + [9_999])) }
    let client = listClient(transport)
    let usage = try await client.usersTodayUsage(ids: Array((1...450).reversed()) + [7, 0, -3, 450])
    let sent = await transport.requests
    #expect(sent.map { sentIDs($0) } == [Array(1...200), Array(201...400), Array(401...450)])
    #expect(sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/dashboard/users-usage" && $0.timeoutInterval == 20 })
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil && sentHeader($0, "If-None-Match") == nil })
    #expect(usage.count == 447 && usage[200] == nil && usage[400] == nil && usage[450] == nil && usage[9_999] == nil)
    let platform = UserTodayUsage.Platform(platform: "openai", todayActualCost: Decimal(string: "1.25"), totalActualCost: 2)
    #expect(usage[201] == UserTodayUsage(userID: 201, todayActualCost: Decimal(string: "201.5"), totalActualCost: 30, byPlatform: [platform]))
    #expect(try await client.usersTodayUsage(ids: [0, -1]).isEmpty)
    #expect(try await client.usersTodayUsage(ids: []).isEmpty)
    #expect(await transport.requests.count == 3)
}

@Test func usersTodayUsageReadsMissingCostsAsUnknown() async throws {
    let reply = #"{"stats":{"3":{"user_id":3},"4":{"today_actual_cost":"x","total_actual_cost":null,"by_platform":"none"},"5":"broken","six":{"today_actual_cost":1}}}"#
    let usage = try await listClient(ScriptedTransport { _ in okReply(reply) }).usersTodayUsage(ids: [3, 4, 5, 6])
    #expect(usage == [3: UserTodayUsage(userID: 3, todayActualCost: nil), 4: UserTodayUsage(userID: 4, todayActualCost: nil)])
}

@Test func usersTodayUsageSplitsOnceByTheServerLimitAndOtherwiseThrows() async throws {
    let limited = ScriptedTransport { request in sentIDs(request).count > 50 ? tooManyIDs(max: "50") : okReply(usageJSON(ids: sentIDs(request))) }
    #expect(try await listClient(limited).usersTodayUsage(ids: Array(1...201)).count == 201)
    #expect(await limited.requests.map { sentIDs($0).count } == [200, 50, 50, 50, 50, 1])
    for limit in [nil, "200", "500", "0", "abc"] as [String?] {
        let transport = ScriptedTransport { _ in tooManyIDs(max: limit) }
        let failure = await thrownAPIError { _ = try await listClient(transport).usersTodayUsage(ids: Array(1...200)) }
        #expect(failure?.reason == "TOO_MANY_IDS", "\(limit ?? "nil")")
        #expect(await transport.requests.count == 1)
    }
    let stubborn = ScriptedTransport { _ in tooManyIDs(max: "50") }
    let again = await thrownAPIError { _ = try await listClient(stubborn).usersTodayUsage(ids: Array(1...120)) }
    #expect(again?.reason == "TOO_MANY_IDS")
    #expect(await stubborn.requests.map { sentIDs($0).count } == [120, 50])
    let broken = ScriptedTransport { request in sentIDs(request).first == 201 ? errorReply(500) : okReply(usageJSON(ids: sentIDs(request))) }
    let failure = await thrownAPIError { _ = try await listClient(broken).usersTodayUsage(ids: Array(1...250)) }
    #expect(failure?.statusCode == 500)
}

// MARK: - 新字段

@Test func adminUserReadsAccessAndThresholdFieldsLeniently() throws {
    let current = try decodeUser(#"{"id":3,"email":"wang@example.invalid","balance":12.5,"status":"active","total_recharged":"100.5","balance_notify_threshold":20,"balance_notify_threshold_type":"percentage","allowed_groups":[5,7],"group_rates":{"5":1.25,"x":2,"-1":3,"7":"bad"},"restrict_public_groups":true}"#)
    #expect(current.totalRecharged == Decimal(string: "100.5") && current.balanceNotifyThreshold == 20)
    #expect(current.balanceNotifyThresholdType == "percentage" && current.allowedGroups == [5, 7] && current.restrictPublicGroups == true)
    #expect(current.groupRates == [5: Decimal(string: "1.25")!])
    #expect(try JSONDecoder().decode(AdminUser.self, from: JSONEncoder().encode(current)) == current)
    let old = try decodeUser(#"{"id":3,"email":"wang@example.invalid","balance":0,"status":"active"}"#)
    let broken = try decodeUser(#"{"id":3,"email":"wang@example.invalid","balance":0,"status":"active","total_recharged":"x","balance_notify_threshold":"x","balance_notify_threshold_type":5,"allowed_groups":"5","group_rates":[1],"restrict_public_groups":"yes"}"#)
    let cleared = try decodeUser(#"{"id":3,"email":"wang@example.invalid","balance":0,"status":"active","total_recharged":null,"balance_notify_threshold":null,"group_rates":null}"#)
    for user in [old, broken, cleared] {
        #expect(user.totalRecharged == nil && user.balanceNotifyThreshold == nil && user.balanceNotifyThresholdType == nil)
        #expect(user.allowedGroups == nil && user.groupRates == nil && user.restrictPublicGroups == nil)
    }
    #expect(AdminUser(id: 3, email: "wang@example.invalid", totalRecharged: 5, groupRates: [5: 1]).groupRates == [5: 1])
}

@Test func publicSettingsReadsTheGlobalLowBalanceReminderLeniently() throws {
    let on = try decodeSettings(#"{"site_name":"演示","balance_low_notify_enabled":true,"balance_low_notify_threshold":10.5}"#)
    #expect(on.balanceLowNotifyEnabled == true && on.balanceLowNotifyThreshold == Decimal(string: "10.5") && on.siteName == "演示")
    let old = try decodeSettings(#"{"site_name":"演示"}"#)
    let broken = try decodeSettings(#"{"site_name":"演示","balance_low_notify_enabled":"yes","balance_low_notify_threshold":"ten"}"#)
    let nulls = try decodeSettings(#"{"site_name":"演示","balance_low_notify_enabled":null,"balance_low_notify_threshold":null}"#)
    for settings in [old, broken, nulls] {
        #expect(settings.balanceLowNotifyEnabled == nil && settings.balanceLowNotifyThreshold == nil && settings.siteName == "演示")
    }
}
