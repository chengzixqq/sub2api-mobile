import Foundation
import Sub2Core

// 60 §2 under `-ui-testing` (S6-21): the global search over the other chapters' fixtures, read only (X05, X44). Accounts are
// AccountDemoStore's, users the session's user table, groups DemoData.accountGroups (name or description, like the server),
// proxies the session's FixtureProxySource by name only (the server does not match the host), requests LogFixtures' rows.
//
// 查询词与命中（UI 测试照此）：
//
// | q | 账号 | 用户 | 分组 | 代理 | 请求 |
// |---|---|---|---|---|---|
// | de | 4：Claude-官方-01/02/03、DeepSeek-01 | 1：23 深蓝 AI | 2：5 Claude Code 组、11 Codex 专线 | 1：6 de-fra-1 | 不发 |
// | 测试 | 1：5 Gemini-测试-B | 9：1 Alice（备注）、13–20 | 1：6 测试组（停用） | 0 | 不发 |
// | example | 0 | 26（全部邮箱，查看全部分两页） | 0 | 0 | 不发 |
// | zhao | 0 | 1：6 赵磊（禁用） | 0 | 0 | 不发 |
// | k301x9 | 0 | 1：3 王小明（只有 Key 片段命中） | 0 | 0 | 不发 |
// | req-search-1040 | 0 | 0 | 0 | 0 | 2：使用记录 1040、错误请求 2006 |
// | req-search-capped | 0 | 0 | 0 | 0 | 20：使用记录 1040…1021，has_more |
// | zzqq | 0 | 0 | 0 | 0 | 不发 |
//
// Any other request-ID-like q matches LogFixtures' request_id exactly.

extension DemoData {
    enum SearchFixture {
        static let requestID = "req-search-1040"
        static let cappedRequestID = "req-search-capped"
        /// Every request waits `slowDelay` first, so “搜索中…” shows.
        static let slowArgument = "-ui-search-slow"
        static let slowDelay: Duration = .seconds(3)
        /// `-ui-search-fail-once=users` / `=users,groups` / `=all`: each named section's first request answers 502.
        static let failOncePrefix = "-ui-search-fail-once="
        /// The first page-2 read answers 502 (a “查看全部” page's second page; the preview reads page 1 only).
        static let secondPageFailsOnceArgument = "-ui-search-list-page2-fail-once"
        static let failure = APIError.server(status: 502, reason: nil)
        /// The plaintext fragments a key search can hit; 王小明's 脚本 (301) only.
        static let keyFragments: [Int: [String]] = [3: ["sk-k301x9-fixture-x301"]]
    }

    struct SearchFixtureOptions: Sendable {
        let isSlow: Bool
        let failingOnce: Set<SearchSection>
        let secondPageFailsOnce: Bool

        init(arguments: [String]) {
            isSlow = arguments.contains(SearchFixture.slowArgument)
            secondPageFailsOnce = arguments.contains(SearchFixture.secondPageFailsOnceArgument)
            let names = arguments.first { $0.hasPrefix(SearchFixture.failOncePrefix) }
                .map { $0.dropFirst(SearchFixture.failOncePrefix.count).split(separator: ",").map(String.init) } ?? []
            failingOnce = names.contains("all") ? Set(SearchSection.allCases) : Set(names.compactMap(SearchSection.init(rawValue:)))
        }
    }

    /// The session's users as the user pages see them.
    @MainActor static func searchUsers(model: AppModel, generation: UUID) -> [AdminUser] {
        model.demoUsersBySession[generation] ?? allUsers
    }

    /// Email, username, notes and the key fragments, ignoring case.
    static func searchUserPage(_ users: [AdminUser], query: UserListQuery) -> Page<AdminUser> {
        guard let term = query.normalizedSearch else { return searchPage(users, page: query.page, pageSize: query.pageSize) }
        let matched = users.filter { user in
            ([user.email, user.username ?? "", user.notes ?? ""] + (SearchFixture.keyFragments[user.id] ?? []))
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
        return searchPage(matched, page: query.page, pageSize: query.pageSize)
    }
    static func searchGroupPage(page: Int, pageSize: Int, search: String) -> Page<AdminGroup> {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = accountGroups.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term)
            || ($0.description ?? "").localizedCaseInsensitiveContains(term) }
        return searchPage(matched.sorted(by: AdminGroup.displayOrder), page: page, pageSize: pageSize)
    }
    /// `page` and `pageSize` from 1.
    static func searchPage<Row: Decodable & Sendable>(_ rows: [Row], page: Int, pageSize: Int) -> Page<Row> {
        let size = max(pageSize, 1), page = max(page, 1)
        return Page(items: Array(rows.dropFirst((page - 1) * size).prefix(size)), total: rows.count, page: page, pageSize: size,
                    pages: max(1, (rows.count + size - 1) / size))
    }

    /// usage reads all time and counts nothing, so has_more decides (60 §2.2).
    static func searchUsagePage(_ rows: [UsageRequestRecord], requestID: String?, page: Int, pageSize: Int) -> Page<UsageRequestRecord> {
        let sorted = rows.sorted { $0.id > $1.id }
        let matched = if requestID == SearchFixture.requestID { sorted.filter { $0.id == LogFixtures.newestUsageID } }
            else if requestID == SearchFixture.cappedRequestID { sorted }
            else { sorted.filter { $0.requestID == requestID } }
        let shown = searchPage(matched, page: page, pageSize: pageSize)
        return Page(items: shown.items, total: nil, page: shown.page, pageSize: shown.pageSize, pages: nil,
                    hasMore: shown.page * shown.pageSize < matched.count)
    }
    static func searchErrorPage(_ rows: [RequestErrorRecord], requestID: String?, page: Int, pageSize: Int) -> Page<RequestErrorRecord> {
        let matched = requestID == SearchFixture.requestID ? rows.filter { $0.id == 2_006 } : rows.filter { $0.requestID == requestID }
        return searchPage(matched.sorted { $0.id > $1.id }, page: page, pageSize: pageSize)
    }
}

/// One search box's fixture site: the other fixtures read on each request, and the scripted failures served once per source.
actor FixtureGlobalSearchSource: GlobalSearchSource {
    private let model: AppModel
    private let generation: UUID
    private let base: Date
    private let options: DemoData.SearchFixtureOptions
    private let usageRows: [UsageRequestRecord]
    private let errorRows: [RequestErrorRecord]
    private var failed: Set<SearchSection> = []
    private var secondPageFailed = false

    init(model: AppModel, session: SessionContext, arguments: [String] = ProcessInfo.processInfo.arguments) {
        let base = session.client.serverClock.now(), zone = session.site.serverTimeZone
        self.model = model; generation = session.generation; self.base = base
        options = DemoData.SearchFixtureOptions(arguments: arguments)
        usageRows = LogFixtures.usageRows(base: base, timeZone: zone)
        errorRows = LogFixtures.errorRows(.request, base: base, timeZone: zone)
    }

    func hits(for request: GlobalSearchRequest) async throws -> SearchHits {
        if options.isSlow { try await Task.sleep(for: DemoData.SearchFixture.slowDelay) }
        try failIfScripted(request)
        switch request {
        case .accounts(let page, let query): return .accounts(try await model.managedAccounts(page: page, query: query))
        case .users(let query):
            return .users(DemoData.searchUserPage(await DemoData.searchUsers(model: model, generation: generation), query: query))
        case .groups(let page, let pageSize, let search): return .groups(DemoData.searchGroupPage(page: page, pageSize: pageSize, search: search))
        case .proxies(let page, let query): return .proxies(try await proxies(page: page, query: query))
        case .usage(let page, let filter, _):
            return .usage(DemoData.searchUsagePage(usageRows, requestID: filter.requestID, page: page, pageSize: filter.pageSize))
        case .errors(let page, let filter):
            return .errors(DemoData.searchErrorPage(errorRows, requestID: filter.requestID, page: page, pageSize: filter.pageSize))
        }
    }

    private func failIfScripted(_ request: GlobalSearchRequest) throws {
        let section = request.section
        if options.failingOnce.contains(section), !failed.contains(section) {
            failed.insert(section)
            throw DemoData.SearchFixture.failure
        }
        if options.secondPageFailsOnce, !secondPageFailed, Self.page(of: request) == 2 {
            secondPageFailed = true
            throw DemoData.SearchFixture.failure
        }
    }
    /// All of the session's proxies, then the name alone like `proxy_repo.go`.
    private func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        let source = await DemoData.proxySource(for: generation, base: base)
        let term = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try await source.proxies(page: 1, query: ProxyListQuery()).items
        let matched = all.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
        return DemoData.searchPage(matched, page: page, pageSize: query.pageSize)
    }
    private static func page(of request: GlobalSearchRequest) -> Int {
        switch request {
        case .accounts(let page, _), .groups(let page, _, _), .proxies(let page, _), .usage(let page, _, _), .errors(let page, _): page
        case .users(let query): query.page
        }
    }
}
