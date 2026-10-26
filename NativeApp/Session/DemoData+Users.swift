import Foundation
import Sub2Core

// Stage 3's user fixtures (X05, S3D1-04): later items add users, keys and subscriptions here and never change an existing row.
extension DemoData {
    static let allUsers = [
        AdminUser(id: 1, email: "alice@example.com", username: "Alice", balance: Decimal(string: "12.50")!, role: "user", concurrency: 2,
                  notes: "常用测试用户", rpmLimit: 120, currentConcurrency: 1, createdAt: "2026-10-01T00:00:00Z",
                  updatedAt: "2026-10-15T08:00:00Z", lastUsedAt: "2026-10-15T08:00:00Z", lastActiveAt: "2026-10-15T07:00:00Z"),
        AdminUser(id: 2, email: "bob@example.com", username: "Bob", balance: 20, role: "user", concurrency: 2)
    ]
    static let keys = [UserAPIKey(id: 1, name: "开发密钥", key: "sk-fixture-secret", status: "active", quota: 100, quotaUsed: 2)]

    /// One user per page, so two fixture users already need “加载更多”. The search matches email or username; `status` is the
    /// old status picker's filter, kept for the fixture until S3-02 removes the picker.
    static func userPage(_ users: [AdminUser], query: UserListQuery, status: String?) -> Page<AdminUser> {
        let search = query.normalizedSearch
        let matches = users.filter { user in
            let found = search.map { user.email.localizedCaseInsensitiveContains($0) || (user.username?.localizedCaseInsensitiveContains($0) ?? false) } ?? true
            return found && (status == nil || status == user.status)
        }
        let page = max(query.page, 1)
        return Page(items: Array(matches.dropFirst(page - 1).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
    }
}
