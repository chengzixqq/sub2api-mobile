import Foundation
import Testing
@testable import Sub2Core

private func account(platform: String, groups: String = "[]", groupIDs: String = "[]", extra: String? = nil) throws -> UpstreamAccount {
    let json = #"{"id":21,"name":"账号","platform":"\#(platform)","type":"oauth","status":"active","schedulable":true,"#
        + #""groups":\#(groups),"group_ids":\#(groupIDs)"# + (extra.map { #","extra":\#($0)"# } ?? "") + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func group(_ id: Int, _ name: String, _ platform: String, status: String = "active", rate: String = "0.8", sort: Int? = nil,
                   members: Int? = 5, active: Int? = 3, exclusive: Bool = false, subscription: String = "standard") -> AdminGroup {
    AdminGroup(id: id, name: name, platform: platform, status: status, rateMultiplier: Decimal(string: rate), isExclusive: exclusive,
               subscriptionType: subscription, accountCount: members, activeAccountCount: active, sortOrder: sort ?? id)
}
private func name(_ platform: String) -> String { GroupPlatform.title(platform) }
private func calendar(_ identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}
private func local(_ text: String, _ zone: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = text.contains(".") ? "yyyy-MM-dd'T'HH:mm:ss.SSS" : "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.date(from: text)!
}

// MARK: - 分组选择器

@Test func groupChoicesKeepActiveSamePlatformAndComposite() throws {
    let groups = [group(1, "高级组", "anthropic"), group(2, "标准组", "openai"), group(3, "组合", "composite"),
                  group(4, "旧组", "Anthropic", status: "inactive"), group(5, "大写", "ANTHROPIC")]
    let choices = AccountGroupChoices.choices(groups: groups, account: try account(platform: "anthropic"), current: [], platformName: name)
    #expect(choices.map(\.id) == [1, 3, 5])
}

@Test func antigravityMixedSchedulingAddsAnthropicAndGemini() throws {
    let groups = [group(1, "A", "anthropic"), group(2, "G", "gemini"), group(3, "AG", "antigravity"), group(4, "O", "openai")]
    let mixed = try account(platform: "antigravity", extra: #"{"mixed_scheduling":true}"#)
    #expect(AccountGroupChoices.choices(groups: groups, account: mixed, current: [], platformName: name).map(\.id) == [1, 2, 3])
    #expect(AccountGroupChoices.platforms(for: mixed) == ["antigravity", "composite", "anthropic", "gemini"])
    for plain in [try account(platform: "antigravity", extra: #"{"mixed_scheduling":false}"#), try account(platform: "antigravity")] {
        #expect(AccountGroupChoices.choices(groups: groups, account: plain, current: [], platformName: name).map(\.id) == [3])
    }
    let openai = try account(platform: "openai", extra: #"{"mixed_scheduling":true}"#)
    #expect(AccountGroupChoices.platforms(for: openai) == ["openai", "composite"])
}

@Test func currentGroupsStayListedEvenWhenInactiveOrOtherPlatform() throws {
    let groups = [group(1, "高级组", "anthropic"), group(6, "测试组", "gemini", status: "inactive"), group(2, "标准组", "openai")]
    let base = try account(platform: "anthropic", groups: #"[{"id":6,"name":"测试组"},{"id":2,"name":"标准组"},{"id":44,"name":"已删组"}]"#)
    let choices = AccountGroupChoices.choices(groups: groups, account: base, current: [6, 2, 44, 45], platformName: name)
    #expect(choices.map(\.id) == [1, 2, 6, 44, 45])
    let stopped = try #require(choices.first { $0.id == 6 })
    #expect(stopped.isInactive && stopped.badges.first == "停用")
    #expect(stopped.detail == "分组已停用，不接收请求 · 可以移出")
    #expect(choices.first { $0.id == 2 }?.badges == ["OpenAI"])
    #expect(choices.first { $0.id == 44 }?.name == "已删组")
    #expect(choices.first { $0.id == 45 }?.name == "#45")
}

@Test func groupChoicesFollowSortOrderThenID() throws {
    let groups = [group(3, "C", "openai", sort: 2), group(1, "A", "openai", sort: 2), group(2, "B", "openai", sort: 1), group(9, "Z", "openai", sort: 0)]
    #expect(AccountGroupChoices.choices(groups: groups, account: try account(platform: "openai"), current: [], platformName: name).map(\.id)
            == [9, 2, 1, 3])
}

@Test func groupRowDetailAndBadges() throws {
    let groups = [group(1, "有账号", "openai", rate: "0.8", members: 5, active: 3), group(2, "空组", "openai", rate: "1.25", members: 0, active: 0),
                  group(3, "缺计数", "openai", members: 4, active: nil), group(4, "无计数", "openai", members: nil, active: nil),
                  group(5, "全", "composite", status: "inactive", exclusive: true, subscription: "subscription")]
    let choices = AccountGroupChoices.choices(groups: groups, account: try account(platform: "openai"), current: [5], platformName: name)
    #expect(choices.map(\.detail) == ["倍率 ×0.8 · 可用 3/5", "倍率 ×1.25 · 还没有账号", "倍率 ×0.8 · 可用 0/4", "倍率 ×0.8 · 还没有账号",
                                      "分组已停用，不接收请求 · 可以移出"])
    #expect(choices.last?.badges == ["停用", "组合", "订阅", "专属"])
    #expect(choices.first?.badges == [])
}

@Test func groupPickerHeaderEmptyAndMixedNotes() throws {
    let anthropic = try account(platform: "anthropic")
    #expect(AccountGroupChoices.header(account: anthropic, platformName: name) == "只列出 Anthropic 分组和组合分组 · 可多选")
    let mixed = try account(platform: "antigravity", extra: #"{"mixed_scheduling":true}"#)
    #expect(AccountGroupChoices.header(account: mixed, platformName: name)
            == "已开启“在 /v1/messages 中使用”：列出 Antigravity、Anthropic、Gemini 分组和组合分组 · 可多选")
    let kimi = try account(platform: "kimi")
    #expect(AccountGroupChoices.emptyText(account: kimi, platformName: name) == "没有可加入的 Kimi 分组")
    #expect(AccountGroupChoices.noActiveText(account: kimi, platformName: name) == "没有启用的 Kimi 分组可加入；在“分组”里启用或新建后再来。")
    #expect(AccountGroupChoices.mixedChannelNote(account: anthropic) == "Anthropic 与 Antigravity 账号进同一分组时，保存会先提示混合渠道风险")
    #expect(AccountGroupChoices.mixedChannelNote(account: mixed) != nil)
    #expect(AccountGroupChoices.mixedChannelNote(account: kimi) == nil)
}

// MARK: - 过期时间

@Test func expiryPresetsAddCalendarMonthsWithMonthEndClamp() {
    let cases: [(from: String, months: Int, to: String, zone: String)] = [
        ("2026-01-31T12:34:56.789", 1, "2026-02-28T12:34:56", "Asia/Shanghai"),
        ("2028-01-31T12:34:56.789", 1, "2028-02-29T12:34:56", "Asia/Shanghai"),
        ("2028-02-29T12:34:56.789", 12, "2029-02-28T12:34:56", "Asia/Shanghai"),
        ("2026-12-31T12:34:56.789", 1, "2027-01-31T12:34:56", "Asia/Shanghai"),
        ("2028-10-31T02:30:00", 1, "2028-11-30T02:30:00", "Australia/Melbourne")
    ]
    for item in cases {
        let seconds = AccountExpiry.seconds(adding: item.months, to: local(item.from, item.zone), calendar: calendar(item.zone))
        #expect(seconds == Int64(local(item.to, item.zone).timeIntervalSince1970), "\(item.from)")
    }
}

@Test func expiryPresetsStartFromGivenNow() {
    let device = Date(timeIntervalSince1970: 1_800_000_000)
    let zone = calendar("Asia/Shanghai")
    let skewed = AccountExpiry.seconds(adding: 1, to: device.addingTimeInterval(3_600), calendar: zone)
    #expect(skewed - AccountExpiry.seconds(adding: 1, to: device, calendar: zone) == 3_600)
}

@Test func expiryTextUsesGivenTimeZone() throws {
    let seconds: Int64 = 1_800_000_000
    #expect(AccountExpiry.text(seconds, timeZone: try #require(TimeZone(identifier: "Asia/Shanghai"))) == "2027-01-15 16:00")
    #expect(AccountExpiry.text(seconds, timeZone: try #require(TimeZone(identifier: "America/New_York"))) == "2027-01-15 03:00")
    for unset: Int64? in [nil, 0, -5] { #expect(AccountExpiry.text(unset, timeZone: .current) == "不过期") }
}

@Test func timeZoneNoteOnlyWhenOffsetsDiffer() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let shanghai = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    #expect(AccountExpiry.timeZoneNote(device: newYork, server: shanghai, at: at) == "按本机时区 America/New_York")
    #expect(AccountExpiry.timeZoneNote(device: try #require(TimeZone(identifier: "Asia/Hong_Kong")), server: shanghai, at: at) == nil)
}

@Test func expiryMustBeInTheFuture() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(AccountExpiry.isFuture(1_800_000_001, now: now))
    #expect(!AccountExpiry.isFuture(1_800_000_000, now: now))
    #expect(!AccountExpiry.isFuture(1_700_000_000, now: now))
    #expect(AccountExpiry.confirmTitle(1_800_000_000, timeZone: TimeZone(identifier: "Asia/Shanghai")!) == "到期时间 2027-01-15 16:00")
}
