import Foundation
import Sub2Core

// Fixtures are reachable only through the explicit -ui-testing launch argument.
enum DemoData {
    static let dashboard = DashboardSummary(
        stats: DashboardStats(
            todayRequests: 128, todayTokens: 1_234_567, todayCost: Decimal(string: "99.99")!,
            totalUsers: 22, totalAccounts: 8, errorAccounts: 1, rpm: 1234, tpm: 987_654,
            todayActualCost: Decimal(string: "12.34")!, todayAccountCost: Decimal(string: "4.56")!,
            totalActualCost: Decimal(string: "1234.56")!, totalAccountCost: Decimal(string: "456.78")!,
            totalTokens: 9_876_543_210, averageDurationMs: 1250, totalRequests: 213_009_545, rpmAvailable: true),
        trend: [
            TrendPoint(date: "2026-10-14 22:00", requests: 90, totalTokens: 32_000, cost: Decimal(string: "0.80")!, actualCost: Decimal(string: "0.31")!),
            TrendPoint(date: "2026-10-15 00:00", requests: 128, totalTokens: 54_000, cost: Decimal(string: "1.25")!, actualCost: Decimal(string: "0.52")!),
            TrendPoint(date: "2026-10-15 02:00", requests: 64, totalTokens: 27_000, cost: Decimal(string: "0.63")!, actualCost: Decimal(string: "0.27")!)],
        monitoring: OpsSnapshot(errorRate: 0.01, qps: 0.2, activeRequests: 2))
    static let longHourlyTrend: [TrendPoint] = (0..<36).map { hour in
        let date = String(format: "2026-10-%02d %02d:00", 14 + hour / 24, hour % 24)
        let actual = Decimal(string: "0.10000001")! + Decimal(hour) / 1_000
        return TrendPoint(date: date, requests: 100 + hour * 3, totalTokens: 1_000_000 + hour * 12_345,
                          cost: actual + 9, actualCost: actual)
    }
    static let allAccounts = [
        UpstreamAccount(id: 1, name: "测试上游 A", platform: "openai", type: "apikey", concurrency: 4,
                        priority: 7, rateMultiplier: Decimal(string: "0.5"), notes: "工作日上游",
                        lastUsedAt: "2026-10-15T08:00:00Z", expiresAt: 1_800_000_000,
                        createdAt: "2026-10-01T00:00:00Z", baseRPM: 60, quotaUsed: Decimal(string: "12.3456"),
                        groupIDs: [10, 11], groups: [.init(id: 10, name: "标准分组"), .init(id: 11, name: "高级分组")],
                        currentConcurrency: 2, probeConcurrency: 1, currentRPM: 37,
                        quotaLimit: 100, quotaDailyLimit: 20, quotaDailyUsed: Decimal(string: "3.45"),
                        quotaWeeklyLimit: 80, quotaWeeklyUsed: Decimal(string: "8.90")),
        UpstreamAccount(id: 2, name: "测试上游 B", platform: "anthropic", type: "oauth", concurrency: 2)
    ]
    static let allUsers = [
        AdminUser(id: 1, email: "alice@example.com", username: "Alice", balance: Decimal(string: "12.50")!, role: "user", concurrency: 2,
                  notes: "常用测试用户", rpmLimit: 120, currentConcurrency: 1, createdAt: "2026-10-01T00:00:00Z",
                  updatedAt: "2026-10-15T08:00:00Z", lastUsedAt: "2026-10-15T08:00:00Z", lastActiveAt: "2026-10-15T07:00:00Z"),
        AdminUser(id: 2, email: "bob@example.com", username: "Bob", balance: 20, role: "user", concurrency: 2)
    ]
    static let keys = [UserAPIKey(id: 1, name: "开发密钥", key: "sk-fixture-secret", status: "active", quota: 100, quotaUsed: 2)]
    static let accountStats = AccountTodayStats(requests: 12, tokens: 4200, cost: Decimal(string: "0.12")!, userCost: Decimal(string: "0.31"), standardCost: Decimal(string: "0.62"))

    static func accounts(page: Int, search: String, status: String?, platform: String?) -> Page<UpstreamAccount> {
        let matches = allAccounts.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (status == nil || status == $0.status) && (platform == nil || platform == $0.platform) }
        return Page(items: Array(matches.dropFirst(max(0, page - 1)).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
    }
    static func users(page: Int, search: String, status: String?) -> Page<AdminUser> {
        let matches = allUsers.filter { (search.isEmpty || $0.email.localizedCaseInsensitiveContains(search)) && (status == nil || status == $0.status) }
        return Page(items: Array(matches.dropFirst(max(0, page - 1)).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
    }
}
