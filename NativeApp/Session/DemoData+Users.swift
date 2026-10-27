import Foundation
import Sub2Core

/// The user list's `-ui-testing` launch arguments (30 §1.5); the wrappers in AppModel+Users read them.
enum UserListFixtureArgument {
    /// Every list empty, the strip too.
    static let empty = "-ui-users-empty"
    /// Every list read fails with 500.
    static let error = "-ui-users-error"
    /// The session's first first-page read succeeds, every later one fails with 500.
    static let refreshError = "-ui-users-refresh-error"
    /// 403 FORBIDDEN.
    static let forbidden = "-ui-users-forbidden"
    /// users-usage fails with 500.
    static let usageError = "-ui-users-usage-error"
    /// quick-topup fails with 503 QUICK_TOPUP_UNAVAILABLE.
    static let quickTopupError = "-ui-users-quick-error"
    /// The session's first first-page read waits six seconds.
    static let slow = "-ui-users-slow"
}

// Stage 3's user fixtures (X05, S3D1-04): later items add users, keys and subscriptions here and never change an existing row.
extension DemoData {
    /// 30 §1: newest first, as the list sorts them; page_size 20 puts 21–26 on the second page. Alice and Bob keep their
    /// fields for the older tests; 4, 7, 11 and 12 are low by a fixed, a percentage, the global and a percentage-of-zero
    /// threshold, 6 is disabled and 8 an administrator.
    static let allUsers = namedUsers + numberedUsers + largeCustomers
    private static let namedUsers: [AdminUser] = [
        AdminUser(id: 1, email: "alice@example.com", username: "Alice", balance: Decimal(string: "12.50")!, role: "user", concurrency: 2,
                  notes: "常用测试用户", rpmLimit: 120, currentConcurrency: 1, createdAt: "2026-10-01T00:00:00Z",
                  updatedAt: "2026-10-15T08:00:00Z", lastUsedAt: "2026-10-15T08:00:00Z", lastActiveAt: "2026-10-15T07:00:00Z",
                  totalRecharged: 70),
        AdminUser(id: 2, email: "bob@example.com", username: "Bob", balance: 20, role: "user", concurrency: 2, createdAt: listCreatedAt(2)),
        listUser(3, "王小明", "xm.wang@example.com", "12.40", recharged: 60),
        listUser(4, "李娜", "na.li@example.com", "3.20", threshold: (5, "fixed")),
        listUser(5, "周婷", "ting.zhou@example.com", "56.30"),
        listUser(6, "赵磊", "lei.zhao@example.com", "0", status: "disabled"),
        listUser(7, "孙浩", "hao.sun@example.com", "8.90", recharged: 100, threshold: (10, "percentage")),
        listUser(8, "陈思远", "siyuan.chen@example.com", "248.00", role: "admin"),
        listUser(9, "林一", "yi.lin@example.com", "75.00"),
        listUser(10, "Studio-K 团队", "ops@studio-k.example", "1020.00", notes: "企业客户"),
        listUser(11, "郑可", "ke.zheng@example.com", "6.00"),
        listUser(12, "吴悦", "yue.wu@example.com", "3.00", recharged: 0, threshold: (5, "percentage")),
    ]
    /// $30 to $198.
    private static let numberedUsers: [AdminUser] = (13...20).map { id in
        listUser(id, "测试用户 \(id)", "user\(id)@example.com", "\(30 + (id - 13) * 24).00")
    }
    private static let largeCustomers: [AdminUser] = [
        listUser(21, "Nova 工作室", "billing@nova.example", "2310.00"),
        listUser(22, "Atlas 科技", "ops@atlas.example", "860.50"),
        listUser(23, "深蓝 AI", "team@deepblue.example", "1475.00"),
        listUser(24, "Mira Labs", "hello@mira.example", "92.40"),
        listUser(25, "Pixel 工坊", "studio@pixel.example", "310.00"),
        listUser(26, "北辰数据", "data@beichen.example", "45.20"),
    ]

    /// `GET admin/users` over the fixture: email, username and notes match case-insensitively, then the page is cut by the
    /// real page size.
    static func userPage(_ users: [AdminUser], query: UserListQuery) -> Page<AdminUser> {
        let matches = users.filter { user in
            guard let search = query.normalizedSearch else { return true }
            return [user.email, user.username ?? "", user.notes ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        let size = max(query.pageSize, 1), page = max(query.page, 1)
        let items = Array(matches.dropFirst((page - 1) * size).prefix(size))
        return Page(items: items, total: matches.count, page: page, pageSize: size, pages: (matches.count + size - 1) / size)
    }
    /// recent 3, 10, 1, 4 and low balance 4, 7, 11, 12, with the session's balances.
    static func quickTopupFixture(users: [AdminUser]) -> QuickTopupReply {
        func item(_ id: Int) -> QuickTopupUser? {
            users.first { $0.id == id }.map { QuickTopupUser(userID: $0.id, email: $0.email, username: $0.username, status: $0.status, balance: $0.balance) }
        }
        return QuickTopupReply(recent: [3, 10, 1, 4].compactMap(item), lowBalance: [4, 7, 11, 12].compactMap(item), lowBalanceEnabled: true)
    }
    /// S3D1-04's key table: only masks, never a plaintext; a user without a row has no keys. Later items add keys, not change these.
    static func apiKeys(userID: Int, now: Date = Date()) -> [AdminAPIKey] {
        switch userID {
        case 1: [AdminAPIKey(id: 1, userID: 1, keyMasked: "sk-…cret", name: "开发密钥", groupID: 2, status: "active", effectiveStatus: "active",
                             lastUsedAt: now.addingTimeInterval(-180), quota: 100, quotaUsed: 2)]
        default: []
        }
    }
    /// users-usage: ids without spend today are left out of the reply, as the server does.
    static func todayUsage(ids: [Int]) -> [Int: UserTodayUsage] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in todayCosts[id].map { (id, UserTodayUsage(userID: id, todayActualCost: $0)) } })
    }
    static let lowBalanceGlobalFixture = UserLowBalanceGlobal(enabled: true, threshold: 10)
    /// First-page reads per session, for `-ui-users-slow` and `-ui-users-refresh-error`.
    @MainActor static var userListFirstPageLoads: [UUID: Int] = [:]

    private static let todayCosts: [Int: Decimal] = ([
        1: "2.80", 3: "3.24", 4: "1.02", 5: "0.84", 7: "2.10", 8: "12.60", 9: "4.40", 10: "64.30",
        21: "402.10", 22: "289.40", 23: "201.35", 24: "156.80", 25: "97.66", 26: "48.69",
    ] as [Int: String]).mapValues { Decimal(string: $0)! }

    private static func listUser(_ id: Int, _ name: String, _ email: String, _ balance: String, status: String = "active", role: String = "user",
                                 notes: String? = nil, recharged: Decimal? = nil, threshold: (Decimal, String)? = nil) -> AdminUser {
        AdminUser(id: id, email: email, username: name, balance: Decimal(string: balance)!, status: status, role: role, concurrency: 1,
                  notes: notes, createdAt: listCreatedAt(id), totalRecharged: recharged, balanceNotifyThreshold: threshold?.0,
                  balanceNotifyThresholdType: threshold?.1)
    }
    /// One day apart, older with every id, so the fixture's order is the server's created_at desc.
    private static func listCreatedAt(_ id: Int) -> String { String(format: "2026-09-%02dT00:00:00Z", 32 - id) }
}

/// 30 §4.5's `-ui-testing` launch arguments. Only page_size 20 reads count, so the detail's latest five (S3-05) never use them up.
enum UserLedgerFixtureArgument {
    /// `-ui-ledger-fail-once 1,2`: the first read of each listed page fails with 500.
    static let failOnce = "-ui-ledger-fail-once"
    /// The second read of page 1, a pull, fails with 500.
    static let refreshFailOnce = "-ui-ledger-refresh-fail-once"
}

// 30 §4 (S3-04): balance-history. Alice has every type, adding up to her breakdown and total_recharged 70; 王小明 (3) has the
// design's three rows and 60; everyone else, a missing id included, has an empty page as the server answers.
extension DemoData {
    /// Newest first. Redeemed 10 + 6 + 12 × 2 = 40, admin 20, grant 10 (101, no operator), affiliate 5 (the synthetic −7).
    static let balanceHistoryAlice: [BalanceHistoryItem] = [
        ledgerRow(124, "balance", "10", "2026-10-16T01:20:00Z", code: "e81c6a0f5d2b4c3a9e7f1a2b3c4d5e6f", notes: "社群活动 · 第 3 批"),
        ledgerRow(123, "admin_balance", "20", "2026-10-12T06:02:00Z", notes: "月初预充", adjustment: (9001, "12.40000000", "32.40000000", "ops@example.com")),
        ledgerRow(122, "admin_balance", "-5", "2026-10-08T01:15:00Z", notes: "退回未用额度", adjustment: (9002, "32.40000000", "27.40000000", "ops@example.com")),
        ledgerRow(-7, "affiliate_balance", "5", "2026-10-07T12:30:00Z", code: "AFF-7"),
        ledgerRow(121, "concurrency", "2", "2026-10-06T08:00:00Z", code: "c0ffee1234567890abcdef0123456789"),
        ledgerRow(120, "admin_concurrency", "2", "2026-10-05T02:00:00Z", notes: "高峰期临时加并发", adjustment: (9003, "5.00000000", "7.00000000", "ops@example.com")),
        ledgerRow(119, "admin_concurrency", "-1", "2026-10-04T02:00:00Z", adjustment: (9004, "7.00000000", "6.00000000", "ops@example.com")),
        ledgerRow(118, "subscription", "30", "2026-10-03T05:12:00Z", code: "4e7c0b95aa11bb22cc33dd44ee55ff66", group: (4, "企业专线"), validityDays: 30),
        // Migrated from an old code: no before and after.
        ledgerRow(117, "admin_balance", "-3", "2026-10-02T03:00:00Z", notes: "旧版调整", adjustment: (9005, nil, nil, "ops@example.com")),
        // The invitation used at sign-up is listed too (其他记录).
        ledgerRow(116, "invitation", "0", "2026-10-01T09:00:00Z", code: "INVITE-2026"),
        ledgerRow(115, "balance", "6", "2026-09-30T02:00:00Z", code: "9a8b7c6d5e4f30211203f4e5d6c7b8a9"),
    ] + (103...114).reversed().map { id in
        ledgerRow(id, "balance", "2", "2026-09-\(id - 85)T02:00:00Z", code: "5eed\(id)0c0de1234567890abcdef0123", notes: id % 3 == 0 ? "9 月活动" : "")
    } + [
        ledgerRow(101, "admin_balance", "10", "2026-09-01T00:00:00Z", notes: "注册赠送", adjustment: (9000, "0.00000000", "10.00000000", nil)),
    ]
    static let balanceHistoryWang: [BalanceHistoryItem] = [
        ledgerRow(95, "balance", "10", "2026-10-16T01:20:00Z", code: "b7d41e0912ab34cd56ef78aa90bb12cc", notes: "社群活动 · 第 3 批"),
        ledgerRow(94, "admin_balance", "50", "2026-10-12T06:02:00Z", notes: "月初预充", adjustment: (9101, "2.40000000", "52.40000000", "ops@example.com")),
        ledgerRow(93, "admin_balance", "-20", "2026-10-08T01:15:00Z", notes: "退回未用额度", adjustment: (9102, "22.40000000", "2.40000000", "ops@example.com")),
    ]
    /// page_size 20 reads per page number in this process (each UI test launches a new one).
    @MainActor static var balanceHistoryRequests: [Int: Int] = [:]

    /// Pages after the first start one row early, as if a record was written while paging, so the list must drop the repeat.
    @MainActor static func balanceHistory(userID: Int, page: Int, pageSize: Int,
                                          arguments: [String] = ProcessInfo.processInfo.arguments) throws -> BalanceHistoryPage {
        if pageSize == PageSize.standard { try failLedgerRead(page: page, arguments: arguments) }
        let (items, breakdown) = ledgerFixture(userID: userID)
        let size = max(pageSize, 1), start = page > 1 ? (page - 1) * size - 1 : 0
        return BalanceHistoryPage(items: Array(items.dropFirst(start).prefix(size)), total: items.count, page: max(page, 1), pageSize: size,
                                  pages: max((items.count + size - 1) / size, 1), totalRecharged: breakdown.redeem + breakdown.admin + breakdown.grant,
                                  breakdown: breakdown)
    }
    /// The comma-separated page numbers after `-ui-ledger-fail-once`; a missing or dash-prefixed value yields [].
    static func ledgerFailOncePages(arguments: [String]) -> Set<Int> {
        guard let index = arguments.firstIndex(of: UserLedgerFixtureArgument.failOnce), arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("-") else { return [] }
        return Set(arguments[index + 1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private static func ledgerFixture(userID: Int) -> (items: [BalanceHistoryItem], breakdown: RechargeBreakdown) {
        switch userID {
        case 1: (balanceHistoryAlice, RechargeBreakdown(redeem: 40, admin: 20, grant: 10, affiliate: 5))
        case 3: (balanceHistoryWang, RechargeBreakdown(redeem: 10, admin: 50))
        default: ([], RechargeBreakdown())
        }
    }
    @MainActor private static func failLedgerRead(page: Int, arguments: [String]) throws {
        let reads = balanceHistoryRequests[page, default: 0] + 1
        balanceHistoryRequests[page] = reads
        let failsOnce = reads == 1 && ledgerFailOncePages(arguments: arguments).contains(page)
        let failsPull = reads == 2 && page == 1 && arguments.contains(UserLedgerFixtureArgument.refreshFailOnce)
        if failsOnce || failsPull { throw APIError.server(status: 500, reason: nil) }
    }
    private static func ledgerRow(_ id: Int, _ type: String, _ value: String, _ usedAt: String, code: String = "", notes: String = "",
                                  group: (id: Int, name: String)? = nil, validityDays: Int = 0,
                                  adjustment: (id: Int, before: String?, after: String?, operatorEmail: String?)? = nil) -> BalanceHistoryItem {
        func amount(_ raw: String?) -> Decimal? { raw.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        let time = ServerTime.parseTimestamp(usedAt)
        return BalanceHistoryItem(id: id, code: code, type: type, value: amount(value), usedAt: time, createdAt: time,
                                  groupID: group?.id, groupName: group?.name, validityDays: validityDays, notes: notes,
                                  adjustmentID: adjustment?.id, beforeValue: amount(adjustment?.before), afterValue: amount(adjustment?.after),
                                  operatorEmail: adjustment?.operatorEmail)
    }
}
