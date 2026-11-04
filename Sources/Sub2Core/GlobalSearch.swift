import Foundation

/// The object kinds of the global search (60 §2) and of its “查看全部” route `.searchResults(kind:query:)`.
/// Stage 6 adds the search fan-out to this file (60 §2.7).
public enum SearchResultKind: String, CaseIterable, Hashable, Sendable {
    case accounts, users, groups, proxies

    public var title: String {
        switch self {
        case .accounts: "账号"
        case .users: "用户"
        case .groups: "分组"
        case .proxies: "代理"
        }
    }
}

/// 60 §2.2: one request of the fan-out each. Declaration order is the display order.
public enum SearchSection: String, CaseIterable, Hashable, Sendable {
    case accounts, users, groups, proxies, usage, errors
    /// Accounts, users, groups and proxies show their first five.
    public static let previewPageSize = 5
    /// Usage records and request errors show their first twenty.
    public static let requestPageSize = 20

    public var kind: SearchResultKind? {
        switch self {
        case .accounts: .accounts
        case .users: .users
        case .groups: .groups
        case .proxies: .proxies
        case .usage, .errors: nil
        }
    }
    public var isRequestLog: Bool { kind == nil }
}

/// The search box's text once trimmed; nil (nothing is sent) below two characters (60 §2.2).
public struct GlobalSearchQuery: Hashable, Sendable {
    public static let minimumLength = 2
    /// U51: “looks like a request ID”.
    public static let requestIDLengths = 8...256
    /// The server trims `search` and keeps its first 100 bytes, which can split a character.
    static let serverSearchByteLimit = 100
    public let text: String

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minimumLength else { return nil }
        self.text = text
    }
    /// No whitespace of any kind (tabs and the ideographic space too), no “@”, 8–256 characters.
    public var isRequestIDLike: Bool {
        Self.requestIDLengths.contains(text.count) && !text.contains { $0.isWhitespace || $0 == "@" }
    }
    /// 60 §2.2's table. An unknown identity counts as the site administrator (60 §1.5); errors are left out only when
    /// monitoring is known to be off (nil answers OPS_DISABLED, which hides the section). Vendors are U01's reserve.
    public func sends(_ section: SearchSection, me: AdminMe?) -> Bool {
        if section.isRequestLog, !isRequestIDLike { return false }
        if section == .errors, me?.features.opsMonitoringEnabled == false { return false }
        guard let workspace = me?.workspace else { return true }
        return Self.vendorReads(section, workspace.permissions)
    }
    public func plan(me: AdminMe?) -> GlobalSearchPlan {
        GlobalSearchPlan(query: self, sections: SearchSection.allCases.filter { sends($0, me: me) },
                         maskedView: me?.has(.apiKeysMaskedView) ?? false, showsVendorNote: me?.workspace != nil)
    }
    /// 60 §2.3 “· Key 片段匹配”: the sent search is in none of email, username and notes (case-insensitive like the server),
    /// so the user came back for one of their keys.
    public func matchesOnlyByKey(_ user: AdminUser) -> Bool {
        guard let search = UserListQuery(search: text).normalizedSearch else { return false }
        return ![user.email, user.username, user.notes].contains { $0?.range(of: search, options: .caseInsensitive) != nil }
    }

    /// `vendor_routes.go`'s read permits; a missing permission is false. Users and ops are site-administrator only.
    private static func vendorReads(_ section: SearchSection, _ permissions: AdminMe.WorkspacePermissions?) -> Bool {
        let accounts = permissions?.accountManage == true, monitor = permissions?.monitorView == true
        switch section {
        case .accounts: return accounts || monitor
        case .users, .errors: return false
        case .groups: return permissions?.groupOps == true || permissions?.groupBilling == true || accounts || monitor
        case .proxies: return permissions?.proxyManage == true || accounts
        case .usage: return monitor
        }
    }
}

/// Which sections one query sends, for the identity at the time it was typed; also the 30-second cache key (60 §2.6).
public struct GlobalSearchPlan: Hashable, Sendable {
    public let query: GlobalSearchQuery
    public let sections: [SearchSection]
    /// `api_keys.masked_view` (S4D1-06).
    public let maskedView: Bool
    /// “当前身份看不到用户与错误请求”.
    public let showsVendorNote: Bool
    public init(query: GlobalSearchQuery, sections: [SearchSection], maskedView: Bool, showsVendorNote: Bool) {
        self.query = query; self.sections = sections; self.maskedView = maskedView; self.showsVendorNote = showsVendorNote
    }
    /// nil for a section outside the plan.
    public func request(for section: SearchSection) -> GlobalSearchRequest? {
        guard sections.contains(section) else { return nil }
        let pageSize = section.isRequestLog ? SearchSection.requestPageSize : SearchSection.previewPageSize
        return GlobalSearchRequest(section, text: query.text, page: 1, pageSize: pageSize, maskedView: maskedView)
    }
}

/// One section's read, built only from the queries other stages own (R19): no list read of its own.
public enum GlobalSearchRequest: Equatable, Sendable {
    case accounts(page: Int, query: AccountListQuery)
    case users(UserListQuery)
    case groups(page: Int, pageSize: Int, search: String)
    case proxies(page: Int, query: ProxyListQuery)
    case usage(page: Int, filter: RequestLogFilter, maskedView: Bool)
    case errors(page: Int, filter: RequestLogFilter)

    /// The one search rule of the fan-out and of “查看全部”. Accounts always carry lite=1 (AccountListQuery); groups are cut here
    /// because `groups(page:pageSize:search:)` only trims; usage reads all time next to a request ID, errors the last 30 days.
    init(_ section: SearchSection, text: String, page: Int, pageSize: Int, maskedView: Bool) {
        switch section {
        case .accounts: self = .accounts(page: page, query: AccountListQuery(search: text, pageSize: pageSize))
        case .users: self = .users(UserListQuery(search: text, page: page, pageSize: pageSize))
        case .groups:
            self = .groups(page: page, pageSize: pageSize, search: AccountWebLink.truncatedUTF8(text, maxBytes: GlobalSearchQuery.serverSearchByteLimit))
        case .proxies: self = .proxies(page: page, query: ProxyListQuery(search: text, pageSize: pageSize))
        case .usage: self = .usage(page: page, filter: RequestLogFilter(time: .none, requestID: text, pageSize: pageSize), maskedView: maskedView)
        case .errors: self = .errors(page: page, filter: RequestLogFilter(time: .rolling(.d30), requestID: text, pageSize: pageSize))
        }
    }
    public var section: SearchSection {
        switch self {
        case .accounts: .accounts
        case .users: .users
        case .groups: .groups
        case .proxies: .proxies
        case .usage: .usage
        case .errors: .errors
        }
    }
}

extension SearchResultKind {
    /// “查看全部” pages (60 §2.3).
    public static let listPageSize = PageSize.standard
    public var section: SearchSection {
        switch self {
        case .accounts: .accounts
        case .users: .users
        case .groups: .groups
        case .proxies: .proxies
        }
    }
    /// The fan-out's search with 20 a page; accounts stay lite.
    public func request(_ query: GlobalSearchQuery, page: Int) -> GlobalSearchRequest {
        GlobalSearchRequest(section, text: query.text, page: page, pageSize: Self.listPageSize, maskedView: false)
    }
}

/// One row of the search results or of a “查看全部” page; the id carries the kind, so equal object ids never collide.
public enum SearchHit: Identifiable, Sendable {
    case account(UpstreamAccount), user(AdminUser), group(AdminGroup), proxy(AdminProxy), usage(UsageRequestRecord), error(RequestErrorRecord)

    public var id: String {
        let prefix = switch self {
        case .account: "account"
        case .user: "user"
        case .group: "group"
        case .proxy: "proxy"
        case .usage: "usage"
        case .error: "error"
        }
        return "\(prefix)-\(objectID)"
    }
    public var objectID: Int {
        switch self {
        case .account(let row): row.id
        case .user(let row): row.id
        case .group(let row): row.id
        case .proxy(let row): row.id
        case .usage(let row): row.id
        case .error(let row): row.id
        }
    }
}

/// One section's answer page.
public enum SearchHits: Sendable {
    case accounts(AccountListPage)
    case users(Page<AdminUser>)
    case groups(Page<AdminGroup>)
    case proxies(Page<AdminProxy>)
    case usage(Page<UsageRequestRecord>)
    case errors(Page<RequestErrorRecord>)

    public var section: SearchSection {
        switch self {
        case .accounts: .accounts
        case .users: .users
        case .groups: .groups
        case .proxies: .proxies
        case .usage: .usage
        case .errors: .errors
        }
    }
    /// The rows in the server's order.
    public var hits: [SearchHit] {
        switch self {
        case .accounts(let page): page.items.map(SearchHit.account)
        case .users(let page): page.items.map(SearchHit.user)
        case .groups(let page): page.items.map(SearchHit.group)
        case .proxies(let page): page.items.map(SearchHit.proxy)
        case .usage(let page): page.items.map(SearchHit.usage)
        case .errors(let page): page.items.map(SearchHit.error)
        }
    }
    public var count: Int { hits.count }
    /// The envelope's total; nil for usage records (count_mode=deferred).
    public var total: Int? {
        switch self {
        case .accounts(let page): page.total
        case .users(let page): page.total
        case .groups(let page): page.total
        case .proxies(let page): page.total
        case .usage(let page): page.total
        case .errors(let page): page.total
        }
    }
    public var hasMore: Bool {
        switch self {
        case .accounts(let page): page.hasMore
        case .users(let page): page.hasMore
        case .groups(let page): page.hasMore
        case .proxies(let page): page.hasMore
        case .usage(let page): page.hasMore
        case .errors(let page): page.hasMore
        }
    }
}

extension APIClient {
    /// 60 §2.2: hands one section's request to that object's only list read (R19). It builds no parameters and is no list read
    /// of its own.
    public func searchHits(_ request: GlobalSearchRequest) async throws -> SearchHits {
        switch request {
        case .accounts(let page, let query): return try await .accounts(managedAccounts(page: page, query: query))
        case .users(let query): return try await .users(users(query: query))
        case .groups(let page, let pageSize, let search): return try await .groups(groups(page: page, pageSize: pageSize, search: search))
        case .proxies(let page, let query): return try await .proxies(proxies(page: page, query: query))
        case .usage(let page, let filter, let maskedView): return try await .usage(requestRecords(page: page, filter: filter, maskedView: maskedView))
        case .errors(let page, let filter): return try await .errors(errorRecords(page: page, filter: filter, kind: .request))
        }
    }
}

public enum GlobalSearchFailure {
    /// 60 §2.5: 403 (any reason) and 404 OPS_DISABLED hide the section; every other failure shows “这一类暂时搜不到 · 重试”.
    public static func hidesSection(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 403 || AccountUpstreamErrors.isOpsDisabled(api)
    }
    /// A cancelled read of a round still shown: APIClient's suspend (D18) throws CancellationError for it.
    public static func isCutOff(_ result: Result<SearchHits, any Error>) -> Bool {
        if case .failure(let error) = result { error is CancellationError } else { false }
    }
}

// MARK: - 结果与状态（60 §2.3、§2.5）

public enum SearchSectionStatus: Equatable, Sendable { case notSent, searching, found(Int), hidden, failed }
public enum GlobalSearchPhase: Equatable, Sendable { case results, empty, failed }

/// The five blocks on screen: usage records and request errors share “请求”.
public enum SearchBlock: String, CaseIterable, Hashable, Sendable {
    case accounts, users, groups, proxies, requests
    public var kind: SearchResultKind? { SearchResultKind(rawValue: rawValue) }
    public var title: String { kind?.title ?? "请求" }
    public var sections: [SearchSection] { kind.map { [$0.section] } ?? [.usage, .errors] }
}

public struct SearchBlockSummary: Equatable, Sendable {
    public let block: SearchBlock
    /// One line “搜索中…” after the rows already in.
    public let isSearching: Bool
    /// One line “这一类暂时搜不到 · 重试” that resends only these.
    public let failedSections: Set<SearchSection>
    public let itemCount: Int
    /// The header's number: the envelope's total for the four kinds, the shown rows for requests (usage has no total); nil
    /// without rows.
    public let headerCount: Int?
    /// “查看全部 N 个” when a kind's total is above five; never for requests.
    public let viewAllTotal: Int?
    /// “只显示前 20 条” under requests.
    public let showsFirstPageNote: Bool
    public var isVisible: Bool { isSearching || !failedSections.isEmpty || itemCount > 0 }
}

/// Each planned section's BlockState (10 §0.5); sections outside the plan stay idle. Not Equatable: compare summaries.
public struct GlobalSearchResults: Sendable {
    public let plan: GlobalSearchPlan
    private let states: [SearchSection: BlockState<SearchHits>]

    /// Every planned section searching.
    public init(plan: GlobalSearchPlan) {
        self.init(plan: plan, states: Dictionary(uniqueKeysWithValues: plan.sections.map { ($0, .loading(previous: nil, at: nil)) }))
    }
    private init(plan: GlobalSearchPlan, states: [SearchSection: BlockState<SearchHits>]) { self.plan = plan; self.states = states }

    public func state(of section: SearchSection) -> BlockState<SearchHits> { states[section] ?? .idle }
    public func status(of section: SearchSection) -> SearchSectionStatus {
        switch state(of: section) {
        case .idle: .notSent
        case .loading: .searching
        case .loaded(let hits, _): .found(hits.count)
        case .disabled: .hidden
        case .failed: .failed
        }
    }
    /// A section outside the plan, or a read the suspend cut off (no failure, it goes out again: 00 §4.6), is left as it is.
    /// 403 and OPS_DISABLED hide it; any other failure keeps the catalog text.
    public func landing(_ result: Result<SearchHits, any Error>, for section: SearchSection, at date: Date) -> GlobalSearchResults {
        guard states[section] != nil, !GlobalSearchFailure.isCutOff(result) else { return self }
        let state: BlockState<SearchHits> = switch result {
        case .success(let hits): .loaded(hits, at: date)
        case .failure(let error) where GlobalSearchFailure.hidesSection(error): .disabled(reason: (error as? APIError)?.reason ?? "FORBIDDEN")
        case .failure(let error): .failed(reason: error.localizedDescription, previous: nil, at: nil)
        }
        return GlobalSearchResults(plan: plan, states: states.merging([section: state]) { _, new in new })
    }
    /// Planned sections among these go back to searching.
    public func reloading(_ sections: Set<SearchSection>) -> GlobalSearchResults {
        let reset = plan.sections.filter(sections.contains).map { ($0, BlockState<SearchHits>.loading(previous: nil, at: nil)) }
        return GlobalSearchResults(plan: plan, states: states.merging(reset) { _, new in new })
    }

    public var isSettled: Bool { !plan.sections.contains { state(of: $0).isLoading } }
    public var failedSections: Set<SearchSection> { Set(plan.sections.filter { status(of: $0) == .failed }) }
    /// Hidden sections take no part: all the others failed → FailureView; all the others empty (or none left) → “—”.
    public var phase: GlobalSearchPhase {
        let shown = plan.sections.filter { status(of: $0) != .hidden }
        if !shown.isEmpty, shown.allSatisfy({ status(of: $0) == .failed }) { return .failed }
        return shown.allSatisfy { status(of: $0) == .found(0) } ? .empty : .results
    }
    /// The first failed section's text, for FailureView.
    public var failureMessage: String? { plan.sections.lazy.compactMap { state(of: $0).failureReason }.first }

    public func summary(of block: SearchBlock) -> SearchBlockSummary {
        let planned = block.sections.filter(plan.sections.contains)
        let pages = planned.compactMap(loaded)
        let itemCount = pages.reduce(0) { $0 + $1.count }
        let total = block.kind == nil ? itemCount : pages.first?.total ?? itemCount
        let viewAll = block.kind == nil ? nil : pages.first?.total.flatMap { $0 > SearchSection.previewPageSize ? $0 : nil }
        let firstPageOnly = block.kind == nil
            && pages.contains { $0.hasMore || ($0.section == .errors && ($0.total ?? 0) > SearchSection.requestPageSize) }
        return SearchBlockSummary(block: block, isSearching: planned.contains { state(of: $0).isLoading },
                                  failedSections: Set(planned.filter { status(of: $0) == .failed }), itemCount: itemCount,
                                  headerCount: itemCount == 0 ? nil : total, viewAllTotal: viewAll, showsFirstPageNote: firstPageOnly)
    }
    public var visibleBlocks: [SearchBlock] { SearchBlock.allCases.filter { summary(of: $0).isVisible } }
    public func hits(of block: SearchBlock) -> [SearchHit] { block.sections.compactMap(loaded).flatMap(\.hits) }
    /// Usage records first, then request errors, each in the server's order.
    public var requestHits: [SearchHit] { hits(of: .requests) }

    public var accounts: [UpstreamAccount] { if case .accounts(let page)? = loaded(.accounts) { page.items } else { [] } }
    public var users: [AdminUser] { if case .users(let page)? = loaded(.users) { page.items } else { [] } }
    public var groups: [AdminGroup] { if case .groups(let page)? = loaded(.groups) { page.items } else { [] } }
    public var proxies: [AdminProxy] { if case .proxies(let page)? = loaded(.proxies) { page.items } else { [] } }

    private func loaded(_ section: SearchSection) -> SearchHits? {
        if case .loaded(let hits, _) = state(of: section) { hits } else { nil }
    }
}

/// 60 §2.3–§2.5 and S6D2b-02's wording; numbers grouped.
public enum GlobalSearchCopy {
    public static let searching = "搜索中…"
    public static let sectionFailed = "这一类暂时搜不到 · 重试"
    public static let clearSearch = "清除搜索"
    public static let firstPageOnly = "只显示前 \(SearchSection.requestPageSize) 条"
    public static let vendorNote = "当前身份看不到用户与错误请求"
    public static let keyFragmentNote = "· Key 片段匹配"
    public static let tooShort = "至少输入 \(GlobalSearchQuery.minimumLength) 个字符"
    public static let nextPageFailure = "加载失败 · 重试"

    public static func noMatch(_ query: GlobalSearchQuery) -> String { "没有匹配“\(query.text)”的账号、用户、分组、代理或请求" }
    /// No “›”: the row's own chevron is the arrow (S6D2b-02).
    public static func viewAll(total: Int) -> String { "查看全部 \(DisplayFormat.grouped(total)) 个" }
    public static func listSubtitle(_ query: GlobalSearchQuery, total: Int?) -> String {
        let searched = "搜索“\(query.text)”"
        return total.map { "\(searched) · \(DisplayFormat.grouped($0)) 个" } ?? searched
    }
    public static func listEmpty(_ kind: SearchResultKind, query: GlobalSearchQuery) -> String { "没有匹配“\(query.text)”的\(kind.title)" }
}
