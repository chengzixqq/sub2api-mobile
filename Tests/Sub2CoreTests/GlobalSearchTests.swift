import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 60 §2: the global search's decisions, requests and states (S6-20).

private let requestIDText = "client:3f2504e0-4f89-41d3-9a0c-0305e82c3301"
private let searchZone = ServerTimeZone(identifier: "Asia/Kathmandu", utcOffset: "+05:45")!
private let landedAt = Date(timeIntervalSince1970: 1_800_000_000)

private func query(_ text: String) -> GlobalSearchQuery { GlobalSearchQuery(text)! }
private func vendor(_ permissions: AdminMe.WorkspacePermissions?) -> AdminMe {
    AdminMe(workspace: AdminMe.Workspace(id: 2, name: "供应商", permissions: permissions), features: AdminMe.Features(opsMonitoringEnabled: true))
}
private func site(ops: Bool? = true, capabilities: Set<String> = []) -> AdminMe {
    AdminMe(features: AdminMe.Features(opsMonitoringEnabled: ops), server: AdminMe.Server(capabilities: capabilities))
}
private func searchClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate, serverTimeZone: searchZone)
}
private func sentQuery(_ request: URLRequest) -> [String: String] {
    guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

// MARK: Fixtures

private func accountRow(_ id: Int) -> String {
    #"{"id":\#(id),"name":"账号 \#(id)","platform":"openai","type":"oauth","status":"active","schedulable":true}"#
}
private func userRow(_ id: Int) -> String { #"{"id":\#(id),"email":"user\#(id)@example.invalid","balance":"1","status":"active"}"# }
private func groupRow(_ id: Int) -> String { #"{"id":\#(id),"name":"分组 \#(id)","platform":"openai","status":"active"}"# }
private func proxyRow(_ id: Int) -> String { #"{"id":\#(id),"name":"代理 \#(id)","protocol":"http","host":"proxy.example.invalid","port":8080}"# }
private func usageRow(_ id: Int) -> String {
    #"{"id":\#(id),"request_id":"\#(requestIDText)","created_at":"2026-10-16T08:00:00Z","model":"gpt-example","user_id":8,"account_id":9,"api_key_id":10}"#
}
private func errorRow(_ id: Int) -> String {
    #"{"id":\#(id),"created_at":"2026-10-16T08:01:00Z","request_id":"\#(requestIDText)","phase":"upstream","type":"upstream_error","status_code":502,"platform":"openai","model":"gpt-example","resolved":false,"message":"bad gateway"}"#
}
private func pageJSON(_ items: [String], total: Int?, pageSize: Int = 5, hasMore: Bool? = nil) -> String {
    let more = hasMore.map { ",\"has_more\":\($0)" } ?? ""
    return "{\"items\":[\(items.joined(separator: ","))],\"total\":\(total.map(String.init) ?? "null"),\"page\":1,\"page_size\":\(pageSize)\(more)}"
}
private func decoded<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

/// One section's answer with `rows` rows; usage and errors use page size 20.
private func hits(_ section: SearchSection, rows: Int, total: Int? = nil, hasMore: Bool? = nil) throws -> SearchHits {
    let ids = Array(1...max(rows, 1)).prefix(rows)
    switch section {
    case .accounts: return .accounts(try decoded(pageJSON(ids.map(accountRow), total: total ?? rows)))
    case .users: return .users(try decoded(pageJSON(ids.map(userRow), total: total ?? rows)))
    case .groups: return .groups(try decoded(pageJSON(ids.map(groupRow), total: total ?? rows)))
    case .proxies: return .proxies(try decoded(pageJSON(ids.map(proxyRow), total: total ?? rows)))
    case .usage: return .usage(try decoded(pageJSON(ids.map(usageRow), total: nil, pageSize: 20, hasMore: hasMore ?? false)))
    case .errors: return .errors(try decoded(pageJSON(ids.map { errorRow($0 + 100) }, total: total ?? rows, pageSize: 20, hasMore: hasMore)))
    }
}
private let everything = query(requestIDText).plan(me: nil)

private func landed(_ answers: [SearchSection: Result<SearchHits, any Error>], plan: GlobalSearchPlan = everything) -> GlobalSearchResults {
    answers.reduce(GlobalSearchResults(plan: plan)) { $0.landing($1.value, for: $1.key, at: landedAt) }
}

// MARK: Query and plan (60 §2.2, U51)

@Test func queryTrimsWhitespaceAndNeedsTwoCharacters() {
    #expect(GlobalSearchQuery("") == nil && GlobalSearchQuery("  ") == nil && GlobalSearchQuery(" a ") == nil && GlobalSearchQuery("\na\n") == nil)
    #expect(GlobalSearchQuery(" ab ")?.text == "ab")
    #expect(GlobalSearchQuery("组") == nil && GlobalSearchQuery("分组")?.text == "分组")
    #expect(GlobalSearchQuery("🇨🇳👍🏽")?.text == "🇨🇳👍🏽")
    #expect(GlobalSearchQuery.minimumLength == 2)
}

@Test(arguments: [
    (String(repeating: "a", count: 7), false), (String(repeating: "a", count: 8), true), (String(repeating: "a", count: 256), true),
    (String(repeating: "a", count: 257), false), ("  abcdefgh  ", true), ("abcd efgh", false), ("abcd\tefgh", false),
    ("abcd\u{3000}efgh", false), ("admin@example.com", false), (requestIDText, true)
])
func requestIDLikeFollowsU51Boundaries(text: String, expected: Bool) {
    #expect(query(text).isRequestIDLike == expected)
    #expect(GlobalSearchQuery.requestIDLengths == 8...256)
}

@Test func siteAdministratorSendsEverySection() {
    let me = site()
    #expect(query(requestIDText).plan(me: me).sections == [.accounts, .users, .groups, .proxies, .usage, .errors])
    #expect(query("alice").plan(me: me).sections == [.accounts, .users, .groups, .proxies])
    #expect(!query("alice").plan(me: me).showsVendorNote)
}

@Test func errorsAreDroppedOnlyWhenOpsMonitoringIsOff() {
    let off = query(requestIDText).plan(me: site(ops: false)).sections
    #expect(!off.contains(.errors) && off.contains(.usage))
    #expect(query(requestIDText).plan(me: site(ops: nil)).sections.contains(.errors))
    let legacy = AdminMe.legacy(authMethod: .jwt, authMe: nil, settings: nil, compliance: nil)
    #expect(query(requestIDText).plan(me: legacy).sections.contains(.errors))
}

@Test func unknownIdentityCountsAsSiteAdministrator() {
    let plan = query(requestIDText).plan(me: nil)
    #expect(plan.sections == SearchSection.allCases && !plan.maskedView && !plan.showsVendorNote)
}

private typealias Permissions = AdminMe.WorkspacePermissions
@Test(arguments: [
    (nil, []), (Permissions(), []), (Permissions(accountManage: false, monitorView: false), []),
    (Permissions(accountManage: true), [.accounts, .groups, .proxies]), (Permissions(monitorView: true), [.accounts, .groups, .usage]),
    (Permissions(proxyManage: true), [.proxies]), (Permissions(groupOps: true), [.groups]), (Permissions(groupBilling: true), [.groups]),
    (Permissions(accountManage: true, groupOps: true, groupBilling: true, proxyManage: true, monitorView: true), [.accounts, .groups, .proxies, .usage])
] as [(AdminMe.WorkspacePermissions?, [SearchSection])])
func vendorSendMatrix(permissions: AdminMe.WorkspacePermissions?, expected: [SearchSection]) {
    let plan = query(requestIDText).plan(me: vendor(permissions))
    #expect(plan.sections == expected)
    #expect(!plan.sections.contains(.users) && !plan.sections.contains(.errors) && plan.showsVendorNote)
    #expect(query("alice").plan(me: vendor(permissions)).sections == expected.filter { $0 != .usage })
}

// MARK: Requests (60 §2.2, R19)

@Test func sectionRequestsReuseTheSharedListQueries() {
    let plan = query(requestIDText).plan(me: site(capabilities: [Capability.apiKeysMaskedView.rawValue]))
    #expect(plan.maskedView)
    #expect(plan.request(for: .accounts) == .accounts(page: 1, query: AccountListQuery(search: requestIDText, pageSize: 5)))
    #expect(plan.request(for: .users) == .users(UserListQuery(search: requestIDText, page: 1, pageSize: 5)))
    #expect(plan.request(for: .groups) == .groups(page: 1, pageSize: 5, search: requestIDText))
    #expect(plan.request(for: .proxies) == .proxies(page: 1, query: ProxyListQuery(search: requestIDText, pageSize: 5)))
    #expect(plan.request(for: .usage) == .usage(page: 1, filter: RequestLogFilter(time: .none, requestID: requestIDText, pageSize: 20), maskedView: true))
    #expect(plan.request(for: .errors) == .errors(page: 1, filter: RequestLogFilter(time: .rolling(.d30), requestID: requestIDText, pageSize: 20)))
    #expect(SearchSection.allCases.allSatisfy { plan.request(for: $0)?.section == $0 })
    #expect(query("alice").plan(me: nil).request(for: .usage) == nil)
}

private func searchTransport() -> ScriptedTransport {
    ScriptedTransport { request in
        let path = request.url!.path
        if path.hasSuffix("/admin/accounts") { return okReply(pageJSON([accountRow(3)], total: 12)) }
        if path.hasSuffix("/admin/users") { return okReply(pageJSON([userRow(3)], total: 3)) }
        if path.hasSuffix("/admin/groups") { return okReply(pageJSON([groupRow(3)], total: 1)) }
        if path.hasSuffix("/admin/proxies") { return okReply(pageJSON([proxyRow(3)], total: 1)) }
        if path.hasSuffix("/admin/usage") { return okReply(pageJSON([usageRow(41)], total: nil, pageSize: 20, hasMore: true)) }
        return okReply(pageJSON([errorRow(51)], total: 25, pageSize: 20))
    }
}

@Test func sectionRequestBytesMatch60Section2Point2() async throws {
    let transport = searchTransport()
    let client = searchClient(transport)
    let plan = query(requestIDText).plan(me: site(capabilities: [Capability.apiKeysMaskedView.rawValue]))
    for section in plan.sections { _ = try await client.searchHits(plan.request(for: section)!) }
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/api/v1/admin/accounts", "/api/v1/admin/users", "/api/v1/admin/groups", "/api/v1/admin/proxies",
                                               "/api/v1/admin/usage", "/api/v1/admin/ops/request-errors"])
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    let q = requestIDText
    #expect(sentQuery(requests[0]) == ["page": "1", "page_size": "5", "lite": "1", "search": q, "sort_by": "name", "sort_order": "asc"])
    #expect(sentQuery(requests[1]) == ["page": "1", "page_size": "5", "search": q, "sort_by": "created_at", "sort_order": "desc",
                                       "include_subscriptions": "false"])
    #expect(sentQuery(requests[2]) == ["page": "1", "page_size": "5", "search": q])
    #expect(sentQuery(requests[3]) == ["page": "1", "page_size": "5", "search": q, "sort_by": "id", "sort_order": "desc"])
    #expect(sentQuery(requests[4]) == ["request_id": q, "page": "1", "page_size": "20", "sort_by": "created_at", "sort_order": "desc",
                                       "timezone": "Asia/Kathmandu", "count_mode": "deferred", "key_view": "masked"])
    #expect(sentQuery(requests[5]) == ["request_id": q, "view": "all", "time_range": "30d", "page": "1", "page_size": "20",
                                       "sort_by": "created_at", "sort_order": "desc"])
}

@Test func usageKeyViewFollowsTheMaskedViewCapability() async throws {
    for masked in [true, false] {
        let transport = searchTransport()
        let client = searchClient(transport)
        let plan = query(requestIDText).plan(me: site(capabilities: masked ? [Capability.apiKeysMaskedView.rawValue] : []))
        #expect(plan.maskedView == masked)
        _ = try await client.searchHits(plan.request(for: .usage)!)
        _ = try await client.searchHits(plan.request(for: .errors)!)
        let requests = await transport.requests
        #expect(sentQuery(requests[0])["key_view"] == (masked ? "masked" : nil))
        #expect(sentQuery(requests[1])["key_view"] == nil)
    }
}

@Test func groupSearchIsCutAtACharacterBoundaryUnder100Bytes() {
    let long = String(repeating: "组", count: 40)
    guard case .groups(_, _, let search) = query(long).plan(me: nil).request(for: .groups) else { Issue.record("没有分组请求"); return }
    #expect(search == String(repeating: "组", count: 33) && search.utf8.count == 99)
    guard case .groups(_, _, let short) = query("ab").plan(me: nil).request(for: .groups) else { Issue.record("没有分组请求"); return }
    #expect(short == "ab")
    #expect(query(long).plan(me: nil).request(for: .accounts) == .accounts(page: 1, query: AccountListQuery(search: long, pageSize: 5)))
}

@Test func viewAllRequestsAskTwentyPerPageAndKeepLite() async throws {
    let q = query("alice")
    #expect(SearchResultKind.listPageSize == 20)
    #expect(SearchResultKind.accounts.request(q, page: 3) == .accounts(page: 3, query: AccountListQuery(search: "alice", pageSize: 20)))
    #expect(SearchResultKind.users.request(q, page: 2) == .users(UserListQuery(search: "alice", page: 2, pageSize: 20)))
    #expect(SearchResultKind.groups.request(q, page: 2) == .groups(page: 2, pageSize: 20, search: "alice"))
    #expect(SearchResultKind.proxies.request(q, page: 2) == .proxies(page: 2, query: ProxyListQuery(search: "alice", pageSize: 20)))
    #expect(SearchResultKind.allCases.allSatisfy { $0.section.rawValue == $0.rawValue && $0.section.kind == $0 })
    let transport = searchTransport()
    _ = try await searchClient(transport).searchHits(SearchResultKind.accounts.request(q, page: 3))
    let sent = sentQuery(try #require(await transport.requests.first))
    #expect(sent["page"] == "3" && sent["page_size"] == "20" && sent["lite"] == "1" && sent["search"] == "alice")
}

@Test func searchHitsReadTotalsAndHasMore() async throws {
    let client = searchClient(searchTransport())
    let plan = query(requestIDText).plan(me: nil)
    let usage = try await client.searchHits(plan.request(for: .usage)!)
    #expect(usage.section == .usage && usage.total == nil && usage.hasMore && usage.count == 1)
    let errors = try await client.searchHits(plan.request(for: .errors)!)
    #expect(errors.section == .errors && errors.total == 25 && errors.hasMore)
    let accounts = try await client.searchHits(plan.request(for: .accounts)!)
    #expect(accounts.section == .accounts && accounts.total == 12 && accounts.hasMore && accounts.count == 1)
    let users = try await client.searchHits(plan.request(for: .users)!)
    #expect(users.section == .users && users.total == 3 && !users.hasMore)
}

// MARK: States (60 §2.5)

@Test(arguments: [
    (APIError.server(status: 403, reason: "FORBIDDEN"), true), (APIError.server(status: 403, reason: "VENDOR_FORBIDDEN"), true),
    (APIError.server(status: 404, reason: "OPS_DISABLED"), true), (APIError.server(status: 404, reason: "USER_NOT_FOUND"), false),
    (APIError.server(status: 429, reason: nil), false), (APIError.server(status: 500, reason: nil), false),
    (APIError(kind: .transport, message: "网络连接已中断"), false)
])
func onlyForbiddenAndOpsDisabledHideASection(error: APIError, hides: Bool) {
    #expect(GlobalSearchFailure.hidesSection(error) == hides)
    let results = landed([.users: .failure(error)])
    #expect(results.status(of: .users) == (hides ? .hidden : .failed))
    if !hides { #expect(results.state(of: .users).failureReason == error.localizedDescription) }
}

@Test func cancellationNeverHidesASection() {
    #expect(!GlobalSearchFailure.hidesSection(CancellationError()))
}

/// 00 §4.6: a read cut off by the suspend is no failure, so no system text reaches FailureView; the section keeps searching.
@Test func aCancelledReadLeavesItsSectionSearching() {
    let results = landed([.users: .failure(CancellationError())])
    #expect(results.status(of: .users) == .searching && results.state(of: .users).failureReason == nil)
    #expect(results.failedSections.isEmpty && results.failureMessage == nil && !results.isSettled)
    let allCut = landed(Dictionary(uniqueKeysWithValues: SearchSection.allCases.map { ($0, .failure(CancellationError())) }))
    #expect(allCut.phase == .results && allCut.failureMessage == nil)
}

/// One row of 60 §2.5's table; internal because parameterized tests cannot take private types.
enum GlobalSearchAnswer: Sendable { case searching, rows(Int), forbidden, opsDisabled, failed }
struct GlobalSearchStatusRow: Sendable, CustomTestStringConvertible {
    let name: String
    let answers: [SearchSection: GlobalSearchAnswer]
    let phase: GlobalSearchPhase
    var testDescription: String { name }
}
private func resultsFor(_ answers: [SearchSection: GlobalSearchAnswer], plan: GlobalSearchPlan = everything) throws -> GlobalSearchResults {
    var results = GlobalSearchResults(plan: plan)
    for (section, answer) in answers {
        switch answer {
        case .searching: continue
        case .rows(let n): results = results.landing(.success(try hits(section, rows: n)), for: section, at: landedAt)
        case .forbidden: results = results.landing(.failure(APIError.server(status: 403, reason: "FORBIDDEN")), for: section, at: landedAt)
        case .opsDisabled: results = results.landing(.failure(APIError.server(status: 404, reason: "OPS_DISABLED")), for: section, at: landedAt)
        case .failed: results = results.landing(.failure(APIError.server(status: 502, reason: nil)), for: section, at: landedAt)
        }
    }
    return results
}
private func all(_ answer: GlobalSearchAnswer) -> [SearchSection: GlobalSearchAnswer] { Dictionary(uniqueKeysWithValues: SearchSection.allCases.map { ($0, answer) }) }
private func merged(_ base: [SearchSection: GlobalSearchAnswer], _ overrides: [SearchSection: GlobalSearchAnswer]) -> [SearchSection: GlobalSearchAnswer] {
    base.merging(overrides) { _, new in new }
}

@Test(arguments: [
    GlobalSearchStatusRow(name: "全部搜索中", answers: all(.searching), phase: .results),
    GlobalSearchStatusRow(name: "全部为空", answers: all(.rows(0)), phase: .empty),
    GlobalSearchStatusRow(name: "为空且两路隐藏", answers: merged(all(.rows(0)), [.users: .forbidden, .errors: .opsDisabled]), phase: .empty),
    GlobalSearchStatusRow(name: "一路失败其余有结果", answers: merged(all(.rows(1)), [.groups: .failed]), phase: .results),
    GlobalSearchStatusRow(name: "一路失败其余为空", answers: merged(all(.rows(0)), [.groups: .failed]), phase: .results),
    GlobalSearchStatusRow(name: "全部失败", answers: all(.failed), phase: .failed),
    GlobalSearchStatusRow(name: "全部失败另有一路隐藏", answers: merged(all(.failed), [.errors: .opsDisabled]), phase: .failed),
    GlobalSearchStatusRow(name: "一路搜索中其余失败", answers: merged(all(.failed), [.proxies: .searching]), phase: .results),
    GlobalSearchStatusRow(name: "全部隐藏", answers: all(.forbidden), phase: .empty)
])
func statusTableOf60Section2Point5(row: GlobalSearchStatusRow) throws {
    let shown = try resultsFor(row.answers)
    #expect(shown.phase == row.phase)
    #expect(shown.isSettled == !row.answers.values.contains { if case .searching = $0 { true } else { false } })
    #expect((shown.failureMessage != nil) == !shown.failedSections.isEmpty)
    if row.phase == .failed { #expect(shown.failureMessage != nil) }
    if row.name == "全部搜索中" {
        #expect(shown.visibleBlocks == SearchBlock.allCases && shown.visibleBlocks.allSatisfy { shown.summary(of: $0).isSearching })
    }
    if row.name == "为空且两路隐藏" { #expect(shown.visibleBlocks.isEmpty && shown.failedSections.isEmpty) }
    if row.name == "一路失败其余有结果" { #expect(shown.summary(of: .groups).failedSections == [.groups] && shown.failedSections == [.groups]) }
}

@Test func emptyVendorPlanIsEmpty() {
    let plan = query("alice").plan(me: vendor(nil))
    let results = GlobalSearchResults(plan: plan)
    #expect(plan.sections.isEmpty && results.phase == .empty && results.isSettled && results.visibleBlocks.isEmpty)
}

@Test func kindBlockShowsTotalAndViewAllAboveFive() throws {
    let twelve = landed([.accounts: .success(try hits(.accounts, rows: 5, total: 12))]).summary(of: .accounts)
    #expect(twelve.itemCount == 5 && twelve.headerCount == 12 && twelve.viewAllTotal == 12 && twelve.isVisible && !twelve.isSearching)
    let five = landed([.accounts: .success(try hits(.accounts, rows: 5, total: 5))]).summary(of: .accounts)
    #expect(five.headerCount == 5 && five.viewAllTotal == nil)
    let none = landed([.accounts: .success(try hits(.accounts, rows: 0))]).summary(of: .accounts)
    #expect(!none.isVisible && none.headerCount == nil && none.itemCount == 0)
    let searching = GlobalSearchResults(plan: everything)
    #expect(searching.summary(of: .users).isSearching && searching.summary(of: .users).itemCount == 0)
    #expect(searching.accounts.isEmpty && searching.users.isEmpty && searching.groups.isEmpty && searching.proxies.isEmpty)
    let loaded = landed([.accounts: .success(try hits(.accounts, rows: 2)), .users: .success(try hits(.users, rows: 1)),
                         .groups: .success(try hits(.groups, rows: 3)), .proxies: .failure(APIError.server(status: 500, reason: nil))])
    #expect(loaded.accounts.map(\.id) == [1, 2] && loaded.users.map(\.id) == [1] && loaded.groups.count == 3 && loaded.proxies.isEmpty)
}

@Test func requestBlockCountsShownRowsAndFirstPageNote() throws {
    let quiet = landed([.usage: .success(try hits(.usage, rows: 2, hasMore: false)), .errors: .success(try hits(.errors, rows: 1, total: 1))])
    let summary = quiet.summary(of: .requests)
    #expect(summary.itemCount == 3 && summary.headerCount == 3 && !summary.showsFirstPageNote && summary.viewAllTotal == nil)
    #expect(quiet.requestHits.map(\.id) == ["usage-1", "usage-2", "error-101"])
    let moreUsage = landed([.usage: .success(try hits(.usage, rows: 2, hasMore: true)), .errors: .success(try hits(.errors, rows: 0))])
    #expect(moreUsage.summary(of: .requests).showsFirstPageNote)
    let manyErrors = landed([.usage: .success(try hits(.usage, rows: 0)), .errors: .success(try hits(.errors, rows: 20, total: 21))])
    #expect(manyErrors.summary(of: .requests).showsFirstPageNote)
}

@Test func requestBlockKeepsRowsBesideAFailedRoute() throws {
    let failure = APIError.server(status: 502, reason: nil)
    let one = landed([.usage: .failure(failure), .errors: .success(try hits(.errors, rows: 1))]).summary(of: .requests)
    #expect(one.itemCount == 1 && one.failedSections == [.usage] && one.isVisible)
    let both = landed([.usage: .failure(failure), .errors: .failure(failure)]).summary(of: .requests)
    #expect(both.itemCount == 0 && both.failedSections == [.usage, .errors] && both.isVisible)
    let hidden = landed([.usage: .failure(APIError.server(status: 403, reason: "FORBIDDEN")), .errors: .success(try hits(.errors, rows: 0))])
    #expect(!hidden.summary(of: .requests).isVisible && !hidden.visibleBlocks.contains(.requests))
}

@Test func landingIgnoresUnplannedSectionsAndReloadingResetsOnlyPlannedOnes() throws {
    let plan = query("alice").plan(me: vendor(Permissions(accountManage: true)))
    let start = GlobalSearchResults(plan: plan)
    let landedUsers = start.landing(.success(try hits(.users, rows: 1)), for: .users, at: landedAt)
    #expect(landedUsers.status(of: .users) == .notSent && landedUsers.phase == start.phase)
    let failed = start.landing(.failure(APIError.server(status: 500, reason: nil)), for: .accounts, at: landedAt)
    let reloading = failed.reloading([.users, .accounts])
    #expect(reloading.status(of: .accounts) == .searching && reloading.status(of: .users) == .notSent)
    #expect(failed.status(of: .accounts) == .failed)
}

@Test func searchHitIDsDifferAcrossKindsWithSameObjectID() throws {
    let account = SearchHit.account(UpstreamAccount(id: 3, name: "账号", platform: "openai", type: "oauth"))
    let user = SearchHit.user(AdminUser(id: 3, email: "user@example.invalid"))
    #expect(account.id == "account-3" && user.id == "user-3" && account.id != user.id)
    #expect(account.objectID == 3 && user.objectID == 3)
    let usage = try hits(.usage, rows: 3).hits.last, error = try hits(.errors, rows: 1).hits.first
    #expect(usage?.id == "usage-3" && usage?.objectID == 3 && error?.id == "error-101" && error?.objectID == 101)
    #expect(SearchHit.group(AdminGroup(id: 3, name: "分组")).id == "group-3" && SearchHit.proxy(AdminProxy(id: 3, name: "代理")).id == "proxy-3")
}

@Test func hitsOfBlockFollowsLoadedValues() throws {
    let results = landed([.accounts: .success(try hits(.accounts, rows: 3)), .usage: .success(try hits(.usage, rows: 1)),
                          .errors: .success(try hits(.errors, rows: 2))])
    #expect(results.hits(of: .accounts).map(\.id) == ["account-1", "account-2", "account-3"])
    #expect(results.hits(of: .users).isEmpty && results.hits(of: .groups).isEmpty)
    #expect(results.hits(of: .requests).map(\.id) == results.requestHits.map(\.id) && results.requestHits.count == 3)
    #expect(try hits(.groups, rows: 2).hits.map(\.id) == ["group-1", "group-2"])
}

// MARK: Key fragment and wording (60 §2.3, S6D2b-01 / 02)

@Test func keyFragmentMatchNeedsNoHitInEmailNameOrNotes() {
    let q = query(" sk-ab12 ")
    #expect(q.matchesOnlyByKey(AdminUser(id: 1, email: "ops@example.invalid", username: "运维", notes: "值班")))
    #expect(!q.matchesOnlyByKey(AdminUser(id: 1, email: "SK-AB12@example.invalid")))
    #expect(!q.matchesOnlyByKey(AdminUser(id: 1, email: "ops@example.invalid", username: "sk-ab12-owner")))
    #expect(!q.matchesOnlyByKey(AdminUser(id: 1, email: "ops@example.invalid", notes: "旧 Key sk-AB12")))
    #expect(q.matchesOnlyByKey(AdminUser(id: 1, email: "ops@example.invalid", username: nil, notes: nil)))
}

@Test func copyFollowsTheSpecWording() {
    let q = query("alice")
    #expect(GlobalSearchCopy.searching == "搜索中…" && GlobalSearchCopy.sectionFailed == "这一类暂时搜不到 · 重试")
    #expect(GlobalSearchCopy.clearSearch == "清除搜索" && GlobalSearchCopy.firstPageOnly == "只显示前 20 条")
    #expect(GlobalSearchCopy.vendorNote == "当前身份看不到用户与错误请求" && GlobalSearchCopy.keyFragmentNote == "· Key 片段匹配")
    #expect(GlobalSearchCopy.tooShort == "至少输入 2 个字符" && GlobalSearchCopy.nextPageFailure == "加载失败 · 重试")
    #expect(GlobalSearchCopy.noMatch(q) == "没有匹配“alice”的账号、用户、分组、代理或请求")
    #expect(GlobalSearchCopy.viewAll(total: 12) == "查看全部 12 个" && GlobalSearchCopy.viewAll(total: 1_284) == "查看全部 1,284 个")
    #expect(GlobalSearchCopy.listSubtitle(q, total: 12) == "搜索“alice” · 12 个" && GlobalSearchCopy.listSubtitle(q, total: nil) == "搜索“alice”")
    #expect(GlobalSearchCopy.listEmpty(.groups, query: q) == "没有匹配“alice”的分组")
    #expect(SearchBlock.allCases.map(\.title) == ["账号", "用户", "分组", "代理", "请求"])
    #expect(SearchBlock.requests.sections == [.usage, .errors] && SearchBlock.requests.kind == nil && SearchBlock.users.kind == .users)
    #expect(SearchResultKind.allCases.map(\.title) == ["账号", "用户", "分组", "代理"])
}
