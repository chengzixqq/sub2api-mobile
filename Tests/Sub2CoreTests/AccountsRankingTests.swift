import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let rankingJSON = #"{"ranking":[{"account_id":7,"account_name":"账号七","platform":"anthropic","status":"active","requests":120,"tokens":50000,"actual_cost":"12.34567890123456789","account_cost":4.5,"standard_cost":15},{"account_id":3,"account_name":"账号三","platform":"openai","status":"error","requests":30,"tokens":900,"actual_cost":3.5,"account_cost":1,"standard_cost":4},{"account_id":11,"account_name":"账号十一","platform":"gemini","status":"active","requests":2,"tokens":10,"actual_cost":0,"account_cost":0,"standard_cost":0}],"total_actual_cost":15.85,"start_date":"2026-10-23","end_date":"2026-10-23","query":{"timezone":"Asia/Shanghai"}}"#

private func rankingClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate,
              cacheIdentity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"))
}
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

@Test func rankingRequestsTodayByServerZone() async throws {
    let transport = ScriptedTransport { _ in okReply(rankingJSON, headers: ["etag": "\"k1\""]) }
    let client = rankingClient(transport)
    _ = try await client.accountsRanking(timezone: shanghai)
    _ = try await client.accountsRanking(timezone: shanghai)
    let sent = await transport.requests
    #expect(sent.count == 2 && sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/dashboard/accounts-ranking")
    #expect(sentQuery(sent[0]) == ["limit": "4", "timezone": "Asia/Shanghai"])
    #expect(sent[0].timeoutInterval == RequestTimeout.aggregate && RequestTimeout.aggregate == 45)
    #expect(sent.allSatisfy { sentHeader($0, "If-None-Match") == nil })
}

@Test func rankingDecodesItemsInServerOrderWithExactMoney() async throws {
    let ranking = try await rankingClient(ScriptedTransport { _ in okReply(rankingJSON) }).accountsRanking(limit: 10, timezone: shanghai)
    let exact = try #require(Decimal(string: "12.34567890123456789"))
    #expect(ranking.map(\.id) == [7, 3, 11] && ranking.map(\.accountID) == [7, 3, 11])
    #expect(ranking[0] == AccountsRankingItem(accountID: 7, accountName: "账号七", platform: "anthropic", requests: 120, actualCost: exact))
    #expect(ranking[1].actualCost == Decimal(string: "3.5") && ranking[1].platform == "openai" && ranking[1].requests == 30)
    #expect(ranking[2].actualCost == 0 && ranking[2].accountName == "账号十一")
}

@Test(arguments: [#"{"ranking":null,"total_actual_cost":0}"#, #"{"total_actual_cost":0}"#])
func rankingNullOrMissingListIsEmpty(json: String) async throws {
    #expect(try await rankingClient(ScriptedTransport { _ in okReply(json) }).accountsRanking(timezone: shanghai).isEmpty)
}

private let limits: [(Int, String)] = [(0, "1"), (-3, "1"), (10, "10"), (50, "50"), (80, "50")]

@Test(arguments: limits)
func rankingLimitIsClampedToServerRange(limit: Int, sent: String) async throws {
    let transport = ScriptedTransport { _ in okReply(rankingJSON) }
    _ = try await rankingClient(transport).accountsRanking(limit: limit, timezone: shanghai)
    #expect(await transport.requests.map { sentQuery($0)["limit"] } == [sent])
    #expect(AccountsRankingItem.limitRange == 1...50)
}

@Test func rankingItemDefaultsAndRequiredAccountID() async throws {
    let sparse = try await rankingClient(ScriptedTransport { _ in okReply(#"{"ranking":[{"account_id":9}]}"#) }).accountsRanking(timezone: shanghai)
    #expect(sparse == [AccountsRankingItem(accountID: 9)])
    #expect(sparse[0].accountName == "" && sparse[0].platform == "" && sparse[0].requests == 0 && sparse[0].actualCost == 0)
    let anonymous = ScriptedTransport { _ in okReply(#"{"ranking":[{"account_id":9},{"account_name":"无编号","actual_cost":1}]}"#) }
    let error = await thrownAPIError { _ = try await rankingClient(anonymous).accountsRanking(timezone: shanghai) }
    #expect(error?.kind == .response)
}

@Test func rankingInvalidTimezoneResendsOnceWithoutTimezone() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400)), .reply(okReply(rankingJSON))])
    let ranking = try await rankingClient(transport).accountsRanking(timezone: shanghai)
    let sent = await transport.requests
    #expect(ranking.count == 3 && sent.count == 2)
    #expect(sentQuery(sent[0]) == ["limit": "4", "timezone": "Asia/Shanghai"] && sentQuery(sent[1]) == ["limit": "4"])
}

@Test func rankingSecondBadRequestIsThrown() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400))])
    let error = await thrownAPIError { _ = try await rankingClient(transport).accountsRanking(timezone: shanghai) }
    #expect(error?.statusCode == 400 && error?.reason == nil)
    #expect(await transport.requests.count == 2)

    let coded = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_GROUP_FILTER"))])
    let refused = await thrownAPIError { _ = try await rankingClient(coded).accountsRanking(timezone: shanghai) }
    #expect(refused?.reason == "INVALID_GROUP_FILTER")
    #expect(await coded.requests.count == 1)
}
