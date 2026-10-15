import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let accountBase = #"{"id":9,"name":"账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"concurrency":8,"base_rpm":120}"#
private func runtimeAccount(_ fields: String = "") throws -> UpstreamAccount {
    let raw = fields.isEmpty ? accountBase : String(accountBase.dropLast()) + "," + fields + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(raw.utf8))
}

@Test func accountLiveUsageIsIndependentFromConfiguredCapacityAndMissingStaysUnavailable() throws {
    let old = try runtimeAccount()
    #expect(old.concurrency == 8 && old.baseRPM == 120)
    #expect(old.currentConcurrency == nil && old.probeConcurrency == nil && old.currentRPM == nil)
    #expect(AccountFieldPresentation.value(.concurrency, account: old) == "不可用")
    #expect(AccountFieldPresentation.value(.rpm, account: old) == "不可用")
    #expect(AccountFieldPresentation.value(.baseRPM, account: old) == "120")
    #expect(AccountFieldPresentation.capacity(old).contains("并发 不可用 / 8"))
    let zero = try runtimeAccount(#""current_concurrency":0,"probe_concurrency":0,"current_rpm":0"#)
    #expect(AccountFieldPresentation.value(.concurrency, account: zero) == "0")
    #expect(AccountFieldPresentation.value(.rpm, account: zero) == "0")
    let busy = try runtimeAccount(#""current_concurrency":3,"probe_concurrency":1,"current_rpm":47"#)
    #expect(busy.currentConcurrency == 3 && busy.probeConcurrency == 1 && busy.currentRPM == 47)
    let roundTrip = try JSONDecoder().decode(UpstreamAccount.self, from: JSONEncoder().encode(busy))
    #expect(roundTrip.currentConcurrency == 3 && roundTrip.probeConcurrency == 1 && roundTrip.currentRPM == 47)
    #expect(try runtimeAccount(#""current_concurrency":null,"current_rpm":null"#).currentRPM == nil)
}

@Test func capacityPreservesWindowSessionAndQuotaSourcesWithoutInventingUsage() throws {
    let account = try runtimeAccount(#""current_concurrency":3,"current_rpm":47,"window_cost_limit":"100.00000001","current_window_cost":"1.005","active_sessions":2,"max_sessions":5,"quota_limit":1000,"quota_used":"12.34567890123456789","quota_daily_limit":10,"quota_daily_used":0,"quota_weekly_limit":70,"session_window_start":"2026-10-15T00:00:00Z","session_window_end":"2026-10-15T05:00:00Z","session_window_status":"active","load_factor":4"#)
    #expect(account.windowCostLimit == Decimal(string: "100.00000001"))
    #expect(account.quotaUsed == Decimal(string: "12.34567890123456789"))
    #expect(account.sessionWindowStatus == "active" && account.loadFactor == 4)
    let display = AccountFieldPresentation.capacity(account)
    #expect(display.contains("并发 3 / 8"))
    #expect(display.contains("窗口标准费用 $1.01 / $100.00"))
    #expect(display.contains("会话 2 / 5"))
    #expect(display.contains("RPM 47 / 120"))
    #expect(display.contains("日配额 $0.00 / $10.00"))
    #expect(display.contains("周配额 不可用 / $70.00"))
    #expect(display.contains("总配额 $12.35 / $1000.00"))
    #expect(AccountFieldPresentation.value(.window, account: account) != "不可用")
    var zero = account; zero.concurrency = 0
    #expect(AccountFieldPresentation.capacity(zero).contains("并发 3 / 0"))
    #expect(!AccountFieldPresentation.capacity(zero).contains("不限制"))
}

@Test func safeAccountMetadataDoesNotRetainProxyOrProbeSecretsAndExpiredBillingIsUnavailable() throws {
    let account = try runtimeAccount(#""proxy":{"id":2,"name":"线路 A","status":"active","host":"secret-host","username":"secret-user","password":"secret-password"},"extra":{"private_token":"secret-token","upstream_billing_probe":{"status":"ok","fresh_until":"2026-10-15T02:00:00Z","last_error":"secret-error","data":{"effective_rate_multiplier":"1.234567890123456789","observed_at":"2026-10-15T00:00:00Z"}}}"#)
    #expect(AccountFieldPresentation.value(.proxy, account: account) == "线路 A（#2）")
    let probe = try #require(account.extra?.upstreamBillingProbe)
    let beforeExpiry = Date(timeIntervalSince1970: 1_792_026_000)
    #expect(probe.historicalMultiplier(at: beforeExpiry) == Decimal(string: "1.234567890123456789"))
    #expect(probe.historicalMultiplier(at: beforeExpiry.addingTimeInterval(3_600)) == nil)
    #expect(probe.historicalMultiplier(at: beforeExpiry.addingTimeInterval(-7_200)) == nil)
    let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
    #expect(!encoded.contains("secret-"))
    #expect(!encoded.contains("host") && !encoded.contains("password"))
}

@Test func oldAccountFieldPreferencesKeepHiddenRuntimeFieldsAndOriginalRawKeys() {
    let old = #"{"version":1,"order":["platform","authenticationType","groups","concurrency","priority","rateMultiplier","status","schedulable","expiresAt","lastUsedAt","createdAt","notes","rpm","usage"],"enabled":["platform","groups"]}"#
    let restored = ListFieldSelection<AccountListField>(rawValue: old)
    #expect(!restored.isEnabled(.concurrency) && !restored.isEnabled(.rpm))
    #expect(restored.isEnabled(.capacity))
    #expect(restored.orderedFields[3] == .concurrency && restored.orderedFields[12] == .rpm)
    #expect(AccountListField.rpm.rawValue == "rpm" && AccountListField.rpm.title == "在用 RPM")
    #expect(ListFieldSelection<AccountListField>().isEnabled(.rpm))
    #expect(ListFieldSelection<AccountListField>(rawValue: restored.rawValue) == restored)
}

@Test func accountTodayActualChargeNeverFallsBackToProviderOrStandardCost() throws {
    let stats = try JSONDecoder().decode(AccountTodayStats.self, from: Data(#"{"requests":128,"tokens":123456,"cost":"4.56789123","standard_cost":"10.00000001","user_cost":"12.34567890123456789"}"#.utf8))
    #expect(stats.cost == Decimal(string: "4.56789123"))
    #expect(stats.standardCost == Decimal(string: "10.00000001"))
    #expect(stats.userCost == Decimal(string: "12.34567890123456789"))
    #expect(AccountFieldPresentation.value(.todayStats, account: try runtimeAccount(), today: stats).contains("扣费 $12.35"))
    #expect(AccountFieldPresentation.value(.todayStats, account: try runtimeAccount(), today: stats).contains("成本 $4.57"))
    for fields in ["", #","user_cost":null,"standard_cost":null"#, #","actual_cost":88,"account_cost":99"#] {
        let missing = try JSONDecoder().decode(AccountTodayStats.self, from: Data((#"{"requests":1,"tokens":2,"cost":4.56"# + fields + "}").utf8))
        #expect(missing.cost == Decimal(string: "4.56") && missing.userCost == nil && missing.standardCost == nil)
        #expect(AccountFieldPresentation.value(.todayStats, account: try runtimeAccount(), today: missing).contains("扣费 不可用"))
    }
}

private actor AccountRuntimeTransport: HTTPTransport {
    private var seen = [URLRequest]()
    func data(for request: URLRequest) async throws -> HTTPResponse {
        seen.append(request)
        let body: String
        switch request.url?.path {
        case "/api/v1/admin/accounts":
            body = #"{"items":[{"id":9,"name":"账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"concurrency":8,"current_concurrency":3,"probe_concurrency":1,"current_rpm":47}],"total":1,"page":1,"page_size":20}"#
        case "/api/v1/admin/accounts/today-stats/batch":
            body = #"{"stats":{"9":{"requests":128,"tokens":123456,"cost":4.56,"standard_cost":10,"user_cost":12.34},"99":{"requests":1,"tokens":2,"cost":3}}}"#
        default: throw URLError(.unsupportedURL)
        }
        return HTTPResponse(statusCode: 200, data: Data(("{\"code\":0,\"data\":" + body + "}").utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
    func requests() -> [URLRequest] { seen }
}

@Test func accountPageCarriesRuntimeCountersInOneListRequestAndTodayUsesOneScopedBatch() async throws {
    let transport = AccountRuntimeTransport()
    let site = ServerProfile(name: "账号测试", baseURL: URL(string: "https://accounts.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: site, credential: .adminKey("fixture"), transport: transport)
    let page = try await client.accounts(page: 1, search: "", status: nil, platform: nil)
    #expect(page.items.first?.currentConcurrency == 3 && page.items.first?.currentRPM == 47)
    #expect(await transport.requests().count == 1)
    #expect(try await client.accountTodayStats(ids: []).isEmpty)
    #expect(try await client.accountTodayStats(ids: [-1, 0]).isEmpty)
    let today = try await client.accountTodayStats(ids: [9, 2, 9, 0])
    #expect(today[9]?.userCost == Decimal(string: "12.34"))
    #expect(today[2] == nil && today[99] == nil)
    let sent = await transport.requests()
    #expect(sent.count == 2 && sent[1].httpMethod == "POST")
    #expect(URLComponents(url: sent[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "include_scheduler_score" } == false)
    let body = try #require(sent[1].httpBody)
    #expect(try JSONSerialization.jsonObject(with: body) as? [String: [Int]] == ["account_ids": [2, 9]])
}

@Test func schedulerScoresStaySeparateFromLoadFactorAndRequireExplicitOptIn() async throws {
    let account = try runtimeAccount(#""load_factor":3,"scheduler_scores":[{"group_id":null,"base_score":1.25,"sticky_score":2.5,"sticky_score_infinity":false,"sticky_weighted_enabled":true},{"group_id":7,"group_name":"分组 A","base_score":4,"sticky_score":0,"sticky_score_infinity":true,"sticky_weighted_enabled":false}]"#)
    #expect(account.loadFactor == 3 && account.schedulerScores?.first?.groupID == nil)
    let score = AccountFieldPresentation.value(.schedulerScore, account: account)
    #expect(score.contains("未分组：基础分 1.25 / 粘性分 2.5"))
    #expect(score.contains("分组 A：基础分 4 / 粘性分 ∞"))
    #expect(AccountFieldPresentation.value(.loadFactor, account: account) == "3")
    #expect(AccountFieldPresentation.value(.schedulerScore, account: try runtimeAccount()) == "不可用")
    let transport = AccountRuntimeTransport()
    let site = ServerProfile(name: "账号测试", baseURL: URL(string: "https://accounts.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: site, credential: .adminKey("fixture"), transport: transport)
    _ = try await client.accounts(page: 1, search: "", status: nil, platform: nil, includeSchedulerScore: true)
    let request = try #require(await transport.requests().first)
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "include_scheduler_score", value: "1")) == true)
}
