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
    static let allUsers = (namedUsers + numberedUsers + largeCustomers).map(withAccessSeed)
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
    /// 阶段 3 唯一夹具表（S3D1-04），只增不改: the key table, only masks and never a plaintext; a user without a row has no keys.
    /// Alice's 开发密钥 is S3-03's; 脚本, 备用 and 王小明's 301 are S3-05's. Later items add keys, never change these.
    static func apiKeys(userID: Int, now: Date = Date()) -> [AdminAPIKey] {
        switch userID {
        case 1: [AdminAPIKey(id: 1, userID: 1, keyMasked: "sk-…cret", name: "开发密钥", groupID: 2, status: "active", effectiveStatus: "active",
                             lastUsedAt: now.addingTimeInterval(-180), quota: 100, quotaUsed: 2),
                 AdminAPIKey(id: 2, userID: 1, keyMasked: "sk-…pt02", name: "脚本", groupID: 2, status: "inactive", effectiveStatus: "inactive"),
                 AdminAPIKey(id: 3, userID: 1, keyMasked: "sk-…bk03", name: "备用", status: "active", effectiveStatus: "quota_exhausted",
                             quota: 10, quotaUsed: 10)]
        case 3: [AdminAPIKey(id: 301, userID: 3, keyMasked: "sk-…x301", name: "脚本", groupID: 5, status: "active", effectiveStatus: "active",
                             lastUsedAt: now.addingTimeInterval(-7_200))]
        default: []
        }
    }
    /// 阶段 3 唯一夹具表（S3D1-04），只增不改: allowed_groups / restrict_public_groups / group_rates. 3, 10 and 13 are S3-05's; everyone
    /// else has no exclusive group and is not restricted.
    static func userAccessSeed(userID: Int) -> (allowedGroups: [Int]?, restrictPublicGroups: Bool, groupRates: [Int: Decimal]?) {
        switch userID {
        case 3: ([5], false, [5: Decimal(string: "1.3")!])
        case 10: ([1, 2], true, [2: Decimal(string: "0.9")!])
        case 13: ([5], false, nil)
        default: (nil, false, nil)
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
    private static func withAccessSeed(_ user: AdminUser) -> AdminUser {
        let seed = userAccessSeed(userID: user.id)
        var seeded = user
        seeded.allowedGroups = seed.allowedGroups; seeded.restrictPublicGroups = seed.restrictPublicGroups; seeded.groupRates = seed.groupRates
        return seeded
    }
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

/// 30 §2.5's `-ui-testing` launch arguments (S3-05).
enum UserDetailFixtureArgument {
    /// `-ui-user-detail-fail profile,today,month,keys,ledger`: the first read of each listed block in this process fails with 500;
    /// `status`: every enable / disable answers 500 without a reason; `gone`: every user read answers 404 USER_NOT_FOUND.
    static let fail = "-ui-user-detail-fail"
    /// `-ui-users-self 8`: the signed-in administrator is that fixture user (S3D1-14).
    static let selfUser = "-ui-users-self"

    enum Failure: String, CaseIterable, Sendable { case profile, today, month, keys, ledger, status, gone }

    static func failures(arguments: [String]) -> Set<Failure> {
        Set(value(after: fail, in: arguments)?.split(separator: ",").compactMap { Failure(rawValue: $0.trimmingCharacters(in: .whitespaces)) } ?? [])
    }
    static func selfUserID(arguments: [String]) -> Int? { value(after: selfUser, in: arguments).flatMap { Int($0) } }
    /// A missing or dash-prefixed value is none.
    private static func value(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("-") else { return nil }
        return arguments[index + 1]
    }
}

// 30 §2 (S3-05): the detail's month spend and its injected failures.
extension DemoData {
    /// total_actual_cost of this month; everyone else spent nothing.
    static let monthCostFixture: [Int: Decimal] = [1: Decimal(string: "86.10")!, 3: Decimal(string: "120.40")!]
    /// Blocks that already failed once in this process (each UI test launches a new one).
    @MainActor static var userDetailFailed: Set<UserDetailFixtureArgument.Failure> = []

    @MainActor static func failUserDetailRead(_ block: UserDetailFixtureArgument.Failure,
                                              arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        let failures = UserDetailFixtureArgument.failures(arguments: arguments)
        if block == .profile, failures.contains(.gone) { throw APIError.server(status: 404, reason: "USER_NOT_FOUND") }
        guard failures.contains(block), userDetailFailed.insert(block).inserted else { return }
        throw APIError.server(status: 500, reason: nil)
    }
}

/// S3-07's `-ui-testing` launch arguments: what a balance check finds, and more pending records (C-26).
enum BalanceReconcileFixtureArgument {
    /// The check finds the record by action_id / request_id.
    static let executed = "-ui-reconcile-executed"
    /// 服务器上没有这笔记录.
    static let notExecuted = "-ui-reconcile-notfound"
    static let candidate = "-ui-reconcile-candidate"
    static let ambiguous = "-ui-reconcile-ambiguous"
    /// The fallback could not conclude (S3-06's notFound).
    static let inconclusive = "-ui-reconcile-inconclusive"
    static let running = "-ui-reconcile-running"
    /// The query fails with 500.
    static let failed = "-ui-reconcile-failed"
    /// An older login at the connected address (another site id): Alice 充值 $50.00, a redeem batch and Bob's compensation.
    static let oldSite = "-ui-pending-old-site"
    /// A $10.00 balance compensation of Alice at the connected site.
    static let compensationHere = "-ui-pending-compensation-here"
    /// The records were sent by user 2 (Bob), not the fixture administrator 1; shared with `-ui-pending-money` (S0-15).
    static let otherActor = "-ui-pending-other-actor"
    /// With `-ui-step-up-required`, a balance write is refused with STEP_UP_REQUIRED until verified.
    static let retryStepUp = "-ui-balance-retry-step-up"
}

// S3-07 (C-26): records of an older login at the same address and the reconciliation's ledger rows. Ids 0B… (older login),
// 0C… (this site) and 0D… (the older login's site id) are not used elsewhere.
extension DemoData {
    struct PendingVariants {
        let oldLoginSite: ServerProfile?
        let balances: [PendingBalanceOperation]
        let batches: [PendingRedeemBatch]
        let compensations: [PendingCompensation]
        var ids: Set<UUID> { Set(balances.map(\.id) + batches.map(\.id) + compensations.map(\.id)) }
    }
    static let oldLoginSiteID = UUID(uuidString: "0D000000-0000-4000-8000-000000000001")!

    /// The older login's records are ten minutes old, before `-ui-pending-money`'s refund, so Alice's banner shows them first.
    static func pendingVariants(current: ServerProfile, now: Date, arguments: [String]) -> PendingVariants? {
        let oldSite = arguments.contains(BalanceReconcileFixtureArgument.oldSite), here = arguments.contains(BalanceReconcileFixtureArgument.compensationHere)
        guard oldSite || here else { return nil }
        let actor = arguments.contains(BalanceReconcileFixtureArgument.otherActor) ? 2 : 1, old = now.addingTimeInterval(-600)
        var balances: [PendingBalanceOperation] = [], batches: [PendingRedeemBatch] = [], compensations: [PendingCompensation] = []
        if oldSite {
            balances.append(PendingBalanceOperation(id: fixtureID("0B000000-0000-4000-8000-000000000001"), serverID: oldLoginSiteID, userID: 1, amount: 50,
                                                    operation: .add, notes: "补偿 10/16 故障", actorUserID: actor, createdAt: old,
                                                    userDisplayName: "Alice", userEmail: "alice@example.com"))
            batches.append(PendingRedeemBatch(id: fixtureID("0B000000-0000-4000-8000-000000000002"), serverID: oldLoginSiteID, actorUserID: actor,
                                              createdAt: old, spec: RedeemGenerateSpec(type: .balance, value: 5, count: 10)))
            compensations.append(PendingCompensation(id: fixtureID("0B000000-0000-4000-8000-000000000003"), serverID: oldLoginSiteID, actorUserID: actor,
                                                     createdAt: old, userID: 2, userDisplayName: "Bob", userEmail: "bob@example.com",
                                                     code: "FIXTURE-GRANT-0B03", type: .balance, value: 8))
        }
        if here {
            compensations.append(PendingCompensation(id: fixtureID("0C000000-0000-4000-8000-000000000001"), serverID: current.id, actorUserID: 1,
                                                     createdAt: now.addingTimeInterval(-120), userID: 1, userDisplayName: "Alice",
                                                     userEmail: "alice@example.com", code: "FIXTURE-GRANT-0C01", type: .balance, value: 10))
        }
        let site = oldSite ? ServerProfile(id: oldLoginSiteID, name: current.name, baseURL: current.baseURL, authentication: current.authentication) : nil
        return PendingVariants(oldLoginSite: site, balances: balances, batches: batches, compensations: compensations)
    }

    /// What `-ui-reconcile-*` makes the check find; nil without one. `balance` is the user's in this session: an add ends above
    /// it, a refund or set ends at it.
    static func reconcileOutcome(for op: PendingBalanceOperation, balance: Decimal, arguments: [String]) throws -> BalanceReconcileOutcome? {
        typealias Argument = BalanceReconcileFixtureArgument
        if arguments.contains(Argument.failed) { throw APIError.server(status: 500, reason: nil) }
        if arguments.contains(Argument.running) { return .stillRunning }
        if arguments.contains(Argument.notExecuted) { return .notExecuted }
        if arguments.contains(Argument.inconclusive) { return .notFound }
        let row = try adjustmentRow(id: 9201, for: op, balance: balance)
        if arguments.contains(Argument.executed) { return .executed(row) }
        if arguments.contains(Argument.candidate) { return .candidate(row) }
        if arguments.contains(Argument.ambiguous) { return .ambiguous([row, try adjustmentRow(id: 9202, for: op, balance: balance)]) }
        return nil
    }

    private static func fixtureID(_ text: String) -> UUID { UUID(uuidString: text)! }
    /// A `GET admin/user-adjustments` row of this write, as the server writes it.
    private static func adjustmentRow(id: Int, for op: PendingBalanceOperation, balance: Decimal) throws -> UserAdjustment {
        let (before, after): (Decimal, Decimal) = switch op.operation {
        case .add: (balance, balance + op.amount)
        case .subtract: (balance + op.amount, balance)
        case .set: (balance, op.amount)
        }
        func amount(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
        let fields: [String: Any] = [
            "id": id, "kind": "balance", "operation": op.operation.rawValue, "requested_value": amount(op.amount), "delta": amount(after - before),
            "before_value": amount(before), "after_value": amount(after), "user_id": op.userID, "user_email": op.userEmail ?? "",
            "operator_user_id": op.actorUserID ?? 0, "notes": op.notes, "request_id": op.key, "source": "admin",
            "created_at": ServerTime.utcTimestamp((op.createdAt ?? Date()).addingTimeInterval(5)),
        ]
        return try JSONDecoder().decode(UserAdjustment.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}

/// S3-08's `-ui-testing` launch arguments for a keypad send, after the action id; without one the write runs (S3-07's fixture).
enum BalanceFixtureArgument {
    /// The server keeps answering IN_PROGRESS: the sheet counts the seconds until “稍后核对” (or a minute) stops waiting.
    static let slow = "-ui-balance-slow"
    /// The reply is lost: the result is unknown and the record stays to be checked.
    static let uncertain = "-ui-balance-uncertain"
    /// 400 INVALID_BALANCE: refused before it ran.
    static let rejected = "-ui-balance-rejected"
    private static let slowLimit = 60

    static func interrupt(_ record: PendingBalanceOperation, actionID: UUID, onEvent: KeyedWriteEventHandler,
                          arguments: [String] = ProcessInfo.processInfo.arguments) async throws {
        func unconfirmed(_ cause: KeyedWriteFailure.UnconfirmedCause) -> KeyedWriteFailure {
            KeyedWriteFailure(disposition: .unconfirmed(cause, retryNotBefore: nil), key: record.key, actionID: actionID, lastError: nil)
        }
        if arguments.contains(rejected) { throw APIError.server(status: 400, reason: "INVALID_BALANCE") }
        if arguments.contains(uncertain) { throw unconfirmed(.transport) }
        guard arguments.contains(slow) else { return }
        for second in 1...slowLimit {
            try await Task.sleep(for: .seconds(1))
            await onEvent(.waitingForServer(elapsedSeconds: second))
        }
        throw unconfirmed(.stillProcessing)
    }
}

/// S3-10's `-ui-testing` launch arguments for a new user (30 §5.4, §5.5). Groups come from DemoData.accountGroups (X11).
enum UserCreateFixtureArgument {
    /// The first creation in this process answers 409 EMAIL_EXISTS; an address the session's users have always does.
    static let emailExists = "-ui-user-email-exists"
    /// The user is created but the reply is lost; the page reads it back by email and finds it.
    static let uncertain = "-ui-user-create-uncertain"
    /// The reply is lost and nobody was created; the read-back finds nothing.
    static let lost = "-ui-user-create-lost"
    /// The first read-back by email fails as the network still does; later ones answer.
    static let readBackFailsOnce = "-ui-user-find-fail-once"
    /// 400 without a reason, as the server's request binding answers.
    static let invalid = "-ui-user-create-invalid"
    /// The creation waits three seconds, so the frozen form can be seen.
    static let slow = "-ui-user-create-slow"
    /// Every attribute write answers 400 ATTRIBUTE_VALIDATION_FAILED (S3-11 reuses it, S3D1-22).
    static let attributeFailure = "-ui-user-attr-fail"
    /// 公司 and 标签 are required (标签 is multi_select, which this App never requires, U28).
    static let requiredAttribute = "-ui-user-attr-required"
    /// The site defines no attribute.
    static let noAttributes = "-ui-user-attrs-empty"
}

// S3-10: the attribute definitions, the session's attribute values (the only store, S3D1-22) and the creations by number.
extension DemoData {
    /// 11 公司 (text), 12 来源 (select), 13 标签 (multi_select, shown read-only).
    static func userAttributeDefinitions(arguments: [String]) -> [UserAttributeDefinition] {
        guard !arguments.contains(UserCreateFixtureArgument.noAttributes) else { return [] }
        let required = arguments.contains(UserCreateFixtureArgument.requiredAttribute)
        func options(_ labels: [String]) -> [UserAttributeDefinition.Option] { labels.map { UserAttributeDefinition.Option(value: $0, label: $0) } }
        return [
            UserAttributeDefinition(id: 11, key: "company", name: "公司", type: "text", isRequired: required, displayOrder: 1),
            UserAttributeDefinition(id: 12, key: "source", name: "来源", type: "select", options: options(["官网注册", "渠道商", "老客户介绍"]), displayOrder: 2),
            UserAttributeDefinition(id: 13, key: "tags", name: "标签", type: "multi_select", options: options(["重点客户", "试用"]), isRequired: required,
                                    displayOrder: 3),
        ]
    }
    /// Attribute values by session and user; S3-11 reads and writes the same store.
    @MainActor static var userAttributeValues: [UUID: [Int: [Int: String]]] = [:]
    /// The session's values; the first read seeds 王小明 (3) with 公司 Studio-K and 来源 渠道商.
    @MainActor static func attributeValues(generation: UUID) -> [Int: [Int: String]] {
        if let values = userAttributeValues[generation] { return values }
        let seeded: [Int: [Int: String]] = [3: [11: "Studio-K", 12: "渠道商"]]
        userAttributeValues[generation] = seeded
        return seeded
    }
    /// Users created in this process by operation number: the same number is answered as a replay (00 §2.5.2).
    @MainActor static var userCreations: [UUID: AdminUser] = [:]
    @MainActor private static var emailExistsAnswered = false
    @MainActor private static var readBackFailed = false

    /// Emails are unique ignoring case (user_repo.go); `-ui-user-email-exists` refuses the first creation whatever its address.
    @MainActor static func answersEmailExists(_ email: String, users: [AdminUser], arguments: [String]) -> Bool {
        if users.contains(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) { return true }
        guard arguments.contains(UserCreateFixtureArgument.emailExists), !emailExistsAnswered else { return false }
        emailExistsAnswered = true
        return true
    }
    /// `-ui-user-find-fail-once`: only the first read-back in this process fails.
    @MainActor static func failsUserReadBack(arguments: [String]) -> Bool {
        guard arguments.contains(UserCreateFixtureArgument.readBackFailsOnce), !readBackFailed else { return false }
        readBackFailed = true
        return true
    }
    /// The created user as the server returns it: the request without the password, active, with the site default balance 0.
    static func createdUser(body: Data, id: Int, now: Date = Date()) throws -> AdminUser {
        var payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        payload.removeValue(forKey: "password")
        payload["id"] = id
        payload["balance"] = payload["balance"] ?? 0
        payload["status"] = "active"
        payload["created_at"] = ServerTime.utcTimestamp(now)
        return try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}

/// S3-11's `-ui-testing` launch arguments for the edit user page (30 §6.4, §6.5).
enum UserEditFixtureArgument {
    /// The site has one administrator: demoting any is refused before sending.
    static let lastAdmin = "-ui-user-last-admin"
    /// The save goes through but its reply is lost; the page reads the user back and finds it saved.
    static let saveUncertain = "-ui-user-save-uncertain"
    /// The reply is lost and nothing was saved; the read-back differs.
    static let saveDrift = "-ui-user-save-drift"
    /// rpm-status answers 501 RPM_STATUS_UNAVAILABLE.
    static let rpmUnavailable = "-ui-user-rpm-unavailable"
    /// rpm-status fails with 500.
    static let rpmFailed = "-ui-user-rpm-failed"
    /// Each rpm-status read counts one more request this minute: 2 / 60, then 3 / 60 …
    static let rpmTicking = "-ui-user-rpm-ticking"
}

// S3-11: `PUT admin/users/:id` as strict as the server (S3D1-10), so a page that sends what it did not change fails.
extension DemoData {
    /// The rpm-status reads so far, for `-ui-user-rpm-ticking`.
    @MainActor static var userRPMReads = 0
    /// 王小明 (3) used 2 of 60 this minute (plus `extraUsed`), 2 of them on Claude Code 组 under his own RPM; everyone else
    /// nothing, unlimited.
    static func rpmStatus(userID: Int, extraUsed: Int = 0) -> UserRPMStatus {
        guard userID == 3 else { return UserRPMStatus(userUsed: 0, userLimit: 0, userTracked: true) }
        return UserRPMStatus(userUsed: 2 + extraUsed, userLimit: 60, userTracked: true,
                             perGroup: [UserRPMStatus.Group(groupID: 5, groupName: "Claude Code 组", used: 2, limit: 30, source: "override", tracked: true)])
    }
    /// Refusals first (balance, an unchanged key, a taken email, disabling an administrator, a rate ≤ 0), then the merge:
    /// allowed_groups replaces the list, group_rates merges key by key and null removes one. Password and adjustment notes are
    /// never kept.
    static func updatedUser(_ user: AdminUser, body: Data, users: [AdminUser]) throws -> AdminUser {
        let fields = (try JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        if fields["balance"] != nil { throw APIError.server(status: 400, reason: "USER_BALANCE_NOT_EDITABLE") }
        if sendsUnchanged(fields, of: user) { throw APIError.server(status: 400, reason: nil) }
        if let email = fields["email"] as? String,
           users.contains(where: { $0.id != user.id && $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            throw APIError.server(status: 409, reason: "EMAIL_EXISTS")
        }
        if user.role == AdminUserRole.admin.rawValue, fields["status"] as? String == "disabled" { throw APIError.server(status: 500, reason: nil) }
        var payload = (try JSONSerialization.jsonObject(with: JSONEncoder().encode(user)) as? [String: Any]) ?? [:]
        for (key, value) in fields where !["password", "adjustment_notes", "group_rates"].contains(key) { payload[key] = value }
        if let rates = fields["group_rates"] as? [String: Any] {
            var merged = payload["group_rates"] as? [String: Any] ?? [:]
            for (id, rate) in rates {
                if rate is NSNull { merged.removeValue(forKey: id); continue }
                guard let number = rate as? NSNumber, number.doubleValue > 0 else { throw APIError.server(status: 500, reason: nil) }
                merged[id] = number
            }
            payload["group_rates"] = merged
        }
        return try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    /// A key equal to the user's value; allowed_groups and restrict_public_groups travel together and count as one.
    private static func sendsUnchanged(_ fields: [String: Any], of user: AdminUser) -> Bool {
        func same<Value: Equatable>(_ key: String, _ value: Value) -> Bool { (fields[key] as? Value).map { $0 == value } ?? false }
        let scalars = same("email", user.email) || same("username", user.username ?? "") || same("notes", user.notes ?? "")
            || same("role", user.role ?? "") || same("status", user.status) || same("concurrency", user.concurrency ?? -1)
            || same("rpm_limit", user.rpmLimit ?? -1)
        let groups = fields["allowed_groups"] != nil && same("allowed_groups", (user.allowedGroups ?? []).sorted())
            && same("restrict_public_groups", user.restrictPublicGroups ?? false)
        let rates = (fields["group_rates"] as? [String: Any] ?? [:]).contains { id, rate in
            let current = Int(id).flatMap { user.groupRates?[$0] }
            guard let number = rate as? NSNumber else { return current == nil }
            return current.map { abs(NSDecimalNumber(decimal: $0).doubleValue - number.doubleValue) < 1e-9 } ?? false
        }
        return scalars || groups || rates
    }
}
