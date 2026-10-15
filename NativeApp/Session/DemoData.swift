import Foundation
import Sub2Core

// Fixtures are reachable only through the explicit -ui-testing launch argument.
enum DemoData {
    static let dashboard = DashboardSummary(
        stats: DashboardStats(todayRequests: 128, todayTokens: 54_000, todayCost: Decimal(string: "1.25")!, totalUsers: 22, totalAccounts: 8, errorAccounts: 1, rpm: 4, tpm: 1800),
        trend: [TrendPoint(date: "2026-10-01", requests: 90, totalTokens: 32_000, cost: Decimal(string: "0.80")!), TrendPoint(date: "2026-10-02", requests: 128, totalTokens: 54_000, cost: Decimal(string: "1.25")!)],
        monitoring: OpsSnapshot(errorRate: 0.01, qps: 0.2, activeRequests: 2))
    static let allAccounts = [UpstreamAccount(id: 1, name: "测试上游 A", platform: "openai", type: "apikey", concurrency: 4), UpstreamAccount(id: 2, name: "测试上游 B", platform: "anthropic", type: "oauth", concurrency: 2)]
    static let allUsers = [AdminUser(id: 1, email: "alice@example.com", username: "Alice", balance: Decimal(string: "12.50")!, role: "user", concurrency: 2), AdminUser(id: 2, email: "bob@example.com", username: "Bob", balance: 20, role: "user", concurrency: 2)]
    static let keys = [UserAPIKey(id: 1, name: "开发密钥", key: "sk-fixture-secret", status: "active", quota: 100, quotaUsed: 2)]

    static func accounts(page: Int, search: String, status: String?, platform: String?) -> Page<UpstreamAccount> {
        let matches = allAccounts.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (status == nil || status == $0.status) && (platform == nil || platform == $0.platform) }
        return Page(items: Array(matches.dropFirst(max(0, page - 1)).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
    }
    static func users(page: Int, search: String, status: String?) -> Page<AdminUser> {
        let matches = allUsers.filter { (search.isEmpty || $0.email.localizedCaseInsensitiveContains(search)) && (status == nil || status == $0.status) }
        return Page(items: Array(matches.dropFirst(max(0, page - 1)).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
    }
}
