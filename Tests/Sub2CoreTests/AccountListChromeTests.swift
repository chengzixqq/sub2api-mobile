import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_792_028_400)   // 2026-10-15T01:40:00Z, 09:40 in Shanghai
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

private func subtitle(total: Int? = 11, updatedAt: Date?, refreshing: Bool = false) -> String {
    AccountListChrome.subtitle(site: "站点 A", total: total, updatedAt: updatedAt, isRefreshing: refreshing, now: now, timeZone: shanghai)
}

private func account(_ id: Int, platform: String) -> UpstreamAccount {
    UpstreamAccount(id: id, name: "账号-\(id)", platform: platform, type: "apikey")
}

@Test func subtitleShowsSiteTotalAndFreshness() {
    #expect(subtitle(updatedAt: now.addingTimeInterval(-20)) == "站点 A · 11 个 · 刚刚更新")
    #expect(subtitle(updatedAt: now.addingTimeInterval(-300)) == "站点 A · 11 个 · 5 分钟前更新")
    #expect(subtitle(updatedAt: now.addingTimeInterval(-7_200)) == "站点 A · 11 个 · 今天 07:40 更新")
    #expect(subtitle(total: 1_234, updatedAt: now) == "站点 A · 1,234 个 · 刚刚更新")
}

@Test func subtitleWhileRefreshingAndWithoutTotal() {
    #expect(subtitle(updatedAt: now.addingTimeInterval(-300), refreshing: true) == "站点 A · 11 个 · 正在刷新…")
    #expect(subtitle(total: nil, updatedAt: now) == "站点 A · 刚刚更新")
    #expect(subtitle(updatedAt: nil) == "站点 A · 11 个")
    #expect(subtitle(total: nil, updatedAt: nil, refreshing: true) == "站点 A · 正在刷新…")
}

@Test func staleBannerUsesServerTimeZone() {
    #expect(AccountListChrome.staleBanner(updatedAt: now.addingTimeInterval(60), timeZone: shanghai) == "读取失败，显示的是 09:41 的数据")
    #expect(AccountListChrome.staleBanner(updatedAt: nil, timeZone: shanghai) == "读取失败")
}

@Test func platformMenuFromSummaryOrderedByTotalThenName() {
    let summary = [("anthropic", 3), ("gemini", 1), ("kimi", 0), ("openai", 2), ("grok", 1)]
        .map { AccountStatusPlatformSummary(platform: $0.0, counts: AccountStateCounts(total: $0.1)) }
    let menu = AccountListChrome.platformMenu(summary: summary, loaded: [], selected: nil, allCount: 11, catalog: .builtin)
    #expect(menu.map(\.title) == ["全部平台", "Anthropic", "OpenAI", "Gemini", "Grok"])
    #expect(menu.map(\.total) == [11, 3, 2, 1, 1])
    #expect(menu.map(\.platform) == [nil, "anthropic", "openai", "gemini", "grok"])
    #expect(menu[0].detail == "11 个" && menu[1].detail == "3 个")
    #expect(Set(menu.map(\.id)).count == menu.count)
}

@Test func platformMenuFallsBackToLoadedRowsAndKeepsSelection() {
    let rows = [account(1, platform: "openai"), account(2, platform: "zhipu"), account(3, platform: "openai")]
    let menu = AccountListChrome.platformMenu(summary: nil, loaded: rows, selected: "deepseek", allCount: nil, catalog: .builtin)
    #expect(menu.map(\.title) == ["全部平台", "OpenAI", "智谱 GLM", "DeepSeek"])
    #expect(menu.map(\.total) == [nil, 2, 1, nil])
    #expect(menu[0].detail == nil && menu[3].detail == nil)
    let kept = AccountListChrome.platformMenu(summary: nil, loaded: rows, selected: "openai", allCount: 3, catalog: .builtin)
    #expect(kept.map(\.platform) == [nil, "openai", "zhipu"])
}

@Test func platformTokenTexts() {
    #expect(AccountListChrome.platformToken("Anthropic") == "平台：Anthropic")
    #expect(AccountListChrome.platformTokenSpoken("Anthropic") == "移除平台筛选 Anthropic")
}
