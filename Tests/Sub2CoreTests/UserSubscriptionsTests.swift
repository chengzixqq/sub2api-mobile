import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decodeSubscription(_ json: String) throws -> AdminUserSubscription {
    try JSONDecoder().decode(AdminUserSubscription.self, from: Data(json.utf8))
}

@Test func adminUserSubscriptionDecodesEveryField() throws {
    let subscription = try decodeSubscription(#"""
    {"id":3,"user_id":10,"group_id":4,"starts_at":"2026-10-01T00:00:00Z","expires_at":"2026-11-01T08:00:00+08:00","status":"active",
     "daily_window_start":"2026-10-20T00:00:00Z","daily_usage_usd":"1.25","weekly_usage_usd":7.5,"monthly_usage_usd":"30.00000001",
     "created_at":"2026-10-01T00:00:00Z","assigned_by":1,"assigned_at":"2026-10-01T00:00:00Z","notes":"渠道","group":{"id":4,"name":"企业专线"},
     "user":{"id":10,"email":"ops@studio-k.example","username":"Studio-K 团队","status":"active","balance":"1020"}}
    """#)
    #expect(subscription.id == 3 && subscription.userID == 10 && subscription.groupID == 4 && subscription.status == "active")
    #expect(subscription.startsAt == ServerTime.parseTimestamp("2026-10-01T00:00:00Z"))
    #expect(subscription.expiresAt == ServerTime.parseTimestamp("2026-11-01T00:00:00Z"))
    #expect(subscription.dailyUsageUSD == Decimal(string: "1.25") && subscription.weeklyUsageUSD == Decimal(string: "7.5"))
    #expect(subscription.monthlyUsageUSD == Decimal(string: "30.00000001"))
    #expect(subscription.user == AdminUserSummary(id: 10, email: "ops@studio-k.example", username: "Studio-K 团队", status: "active"))
}

@Test func adminUserSubscriptionToleratesMissingFields() throws {
    let bare = try decodeSubscription(#"{"id":3}"#)
    #expect(bare == AdminUserSubscription(id: 3))
    #expect(bare.userID == nil && bare.groupID == nil && bare.startsAt == nil && bare.expiresAt == nil && bare.status == nil)
    #expect(bare.dailyUsageUSD == nil && bare.weeklyUsageUSD == nil && bare.monthlyUsageUSD == nil && bare.user == nil)
    let broken = try decodeSubscription(#"""
    {"id":3,"user_id":"x","starts_at":"昨天","expires_at":null,"status":7,"daily_usage_usd":"abc","weekly_usage_usd":null,"user":[]}
    """#)
    #expect(broken == AdminUserSubscription(id: 3))
    #expect(throws: (any Error).self) { try decodeSubscription(#"{"user_id":10}"#) }
}

@Test func userSubscriptionsReadsUserArray() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"[{"id":3,"group_id":4,"status":"active"},{"id":4,"group_id":5,"status":"expired"}]"#))])
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
    let subscriptions = try await client.userSubscriptions(userID: 5)
    #expect(subscriptions.map(\.id) == [3, 4] && subscriptions.map(\.groupID) == [4, 5])
    let sent = await transport.requests
    #expect(sent.count == 1 && sent.first?.httpMethod == "GET" && sent.first?.url?.path == "/api/v1/admin/users/5/subscriptions")
    #expect(sent.first?.url?.query == nil)
    #expect(await thrownAPIError { _ = try await client.userSubscriptions(userID: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
}
