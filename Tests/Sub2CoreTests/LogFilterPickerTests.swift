import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 40 §6.4 按对象筛选 sheet: the account query, the local group match, the user cut and the rows' text (S4-07).

/// DemoData's eleven groups, `sort_order` = id.
private let directory: [AdminGroup] = [
    (1, "高级组", "anthropic"), (2, "标准组", "openai"), (3, "默认组", "deepseek"), (4, "企业专线", "openai"),
    (5, "Claude Code 组", "anthropic"), (6, "测试组", "gemini"), (7, "GLM 组", "zhipu"), (8, "Kimi 组", "kimi"),
    (9, "MiniMax 组", "minimax"), (10, "Antigravity 组", "antigravity"), (11, "Codex 专线", "openai"),
].map { AdminGroup(id: $0.0, name: $0.1, platform: $0.2, sortOrder: $0.0) }
private let groupNames = Dictionary(uniqueKeysWithValues: directory.map { ($0.id, $0.name) })
private func ids(_ groups: [AdminGroup]) -> [Int] { groups.map(\.id) }

@Test func accountQueryIsPageOneNameAscendingSixLite() throws {
    let query = LogFilterPicker.accountQuery(search: " 官方 ")
    #expect(try query.queryItems(page: 1) == [
        URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "page_size", value: "6"), URLQueryItem(name: "lite", value: "1"),
        URLQueryItem(name: "sort_by", value: "name"), URLQueryItem(name: "sort_order", value: "asc"), URLQueryItem(name: "search", value: "官方"),
    ])
    #expect(query.search == "官方" && query.sort == .name && !query.descending)
    #expect(!query.supportsListQuery && query.statuses.isEmpty && !query.includeCounts && query.group == nil)
}

@Test func blankSearchSendsNoSearchParameter() throws {
    let items = try LogFilterPicker.accountQuery(search: "  \n").queryItems(page: 1)
    #expect(!items.contains { $0.name == "search" })
    #expect(items.contains(URLQueryItem(name: "page_size", value: "6")) && items.contains(URLQueryItem(name: "sort_by", value: "name")))
}

@Test func groupsMatchNameOnlyCaseInsensitiveInDirectoryOrder() {
    #expect(ids(LogFilterPicker.groups(directory, matching: "")) == [1, 2, 3, 4])
    #expect(ids(LogFilterPicker.groups(directory, matching: "glm")) == [7])
    #expect(ids(LogFilterPicker.groups(directory, matching: " 组 ")) == [1, 2, 3, 5])
    #expect(LogFilterPicker.groups(directory, matching: "openai").isEmpty)
    #expect(LogFilterPicker.groups(directory, matching: "xyz").isEmpty)
    #expect(ids(LogFilterPicker.groups(directory.reversed(), matching: "组")) == [10, 9, 8, 7])
}

@Test func usersHiddenForBlankKeywordAndCutToThree() {
    let matches = (1...5).map { UsageUserMatch(id: $0, email: "a\($0)@example.com", deleted: $0 == 2) }
    #expect(LogFilterPicker.users(matches, matching: "").isEmpty)
    #expect(LogFilterPicker.users(matches, matching: " \n").isEmpty)
    let shown = LogFilterPicker.users(matches, matching: " a ")
    #expect(shown.map(\.id) == [1, 2, 3])
    #expect(shown.map(\.deleted) == [false, true, false])
}

@Test func accountMetaNamesPlatformAndGroupsFromDirectory() {
    let names: (Int) -> String? = { groupNames[$0] }
    let claude = UpstreamAccount(id: 1, name: "Claude-官方-01", platform: "anthropic", type: "oauth", groupIDs: [1, 5])
    #expect(LogFilterPicker.accountMeta(claude, catalog: nil, directory: names) == "Anthropic · 高级组、Claude Code 组")
    let grok = UpstreamAccount(id: 10, name: "Grok-旧-01", platform: "grok", type: "apikey")
    #expect(LogFilterPicker.accountMeta(grok, catalog: nil, directory: names) == "Grok · 未分组")
    let glm = UpstreamAccount(id: 11, name: "GLM-直连-01", platform: "zhipu", type: "apikey", groupIDs: [7])
    #expect(LogFilterPicker.accountMeta(glm, catalog: .builtin, directory: names) == "智谱 GLM · GLM 组")
    let embedded = UpstreamAccount(id: 4, name: "OpenAI-主力-01", platform: "openai", type: "apikey", groupIDs: [2],
                                   groups: [UpstreamAccount.Group(id: 2, name: "标准组")])
    #expect(LogFilterPicker.accountMeta(embedded, catalog: nil, directory: { _ in nil }) == "OpenAI · 标准组")
    let unknown = UpstreamAccount(id: 12, name: "OpenAI-新", platform: "openai", type: "apikey", groupIDs: [99])
    #expect(LogFilterPicker.accountMeta(unknown, catalog: nil, directory: names) == "OpenAI · #99")
}

@Test func trailingPlatformAndObjectNames() {
    #expect(LogFilterPicker.accountTrailing(UpstreamAccount(id: 12, name: "OpenAI-新", platform: "openai", type: "apikey")) == "#12")
    #expect(LogFilterPicker.groupPlatform(directory[1], catalog: nil) == "OpenAI")
    #expect(LogFilterPicker.groupPlatform(directory[6], catalog: .builtin) == "智谱 GLM")
    #expect(LogFilterPicker.objectName("  ") == nil)
    #expect(LogFilterPicker.objectName(" Claude-官方-01 ") == "Claude-官方-01")
}

@Test func copyAndLimitsMatchSpec() {
    #expect(LogFilterPicker.title == "按对象筛选")
    #expect(LogFilterPicker.searchPrompt == "账号名、邮箱或分组")
    #expect([LogFilterPicker.accountsTitle, LogFilterPicker.groupsTitle, LogFilterPicker.usersTitle] == ["账号", "分组", "用户"])
    #expect(LogFilterPicker.deletedUser == "已删除")
    #expect(LogFilterPicker.addChipTitle == "筛选")
    #expect(LogFilterPicker.noMatches == "没有匹配的账号、分组或用户")
    #expect(LogFilterPicker.accountLimit == 6 && LogFilterPicker.groupLimit == 4 && LogFilterPicker.userLimit == 3)
    #expect(LogFilterPicker.debounce == .milliseconds(300))
}
