import Foundation
import Testing
@testable import Sub2Core

// S5-02: 50 §0.2 buckets and health, §0.3 cells, §1.3 list, §0.6 formats, §2.3 配置, §3.3 availableAfter, §9 QA.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }
private func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.0001 }

private func counts(_ account: Int, _ active: Int, _ limited: Int, error: Int? = nil, idle: Int? = nil) -> GroupAccountCounts {
    GroupAccountCounts(accountCount: account, activeAccountCount: active, rateLimitedAccountCount: limited, errorAccountCount: error, idleAccountCount: idle)
}
private func buckets(_ available: Int, _ limited: Int = 0, _ error: Int = 0, _ idle: Int = 0) -> GroupBuckets {
    GroupBuckets(counts(available + limited + error + idle, available, limited, error: error, idle: idle))
}
private func group(_ id: Int, _ name: String = "高级组", platform: String = "anthropic", status: String = "active", account: Int = 3, active: Int = 3,
                   limited: Int = 0, error: Int? = 0, idle: Int? = 0, sortOrder: Int? = nil, rate: String? = "0.8", exclusive: Bool? = false,
                   type: String? = "standard", rpm: Int? = 0, description: String? = nil, claudeCodeOnly: Bool? = false, fallback: Int? = nil,
                   daily: Decimal? = nil, weekly: Decimal? = nil, monthly: Decimal? = nil) -> AdminGroup {
    AdminGroup(id: id, name: name, description: description, platform: platform, status: status, rateMultiplier: rate.flatMap { Decimal(string: $0) },
               isExclusive: exclusive, subscriptionType: type, dailyLimitUSD: daily, weeklyLimitUSD: weekly, monthlyLimitUSD: monthly, rpmLimit: rpm,
               accountCount: account, activeAccountCount: active, rateLimitedAccountCount: limited, sortOrder: sortOrder,
               errorAccountCount: error, idleAccountCount: idle, claudeCodeOnly: claudeCodeOnly, fallbackGroupID: fallback)
}
private func member(_ id: Int, platform: String = "anthropic", status: String = "active", schedulable: Bool = true, overload: String? = nil,
                    rateLimit: String? = nil, temp: String? = nil, autoPause: Bool? = nil, expiresAt: Int64? = nil, groups: [Int] = []) -> UpstreamAccount {
    UpstreamAccount(id: id, name: "账号-\(id)", platform: platform, type: "oauth", status: status, schedulable: schedulable, expiresAt: expiresAt,
                    groupIDs: groups, rateLimitResetAt: rateLimit, overloadUntil: overload, tempUnschedulableUntil: temp, autoPauseOnExpired: autoPause)
}

// MARK: 0.2 四个桶

@Test func bucketsTakeF04CountsWhenTheErrorKeyIsPresent() {
    let served = GroupBuckets(counts(6, 4, 1, error: 0, idle: 1), fallbackErrors: 3)
    #expect(served.available == 4 && served.limited == 1 && served.error == 0 && served.idle == 1 && served.total == 6)
    #expect(served.usesServerBuckets)
    #expect(!GroupBuckets(counts(6, 4, 1)).usesServerBuckets)
    let noIdle = GroupBuckets(counts(6, 2, 1, error: 1))
    #expect(noIdle.error == 1 && noIdle.idle == 2 && noIdle.usesServerBuckets)
    let viaGroup = GroupBuckets(group: group(1, account: 6, active: 4, limited: 1, error: 0, idle: 1))
    #expect(viaGroup == served)
}

@Test func bucketsFallBackToTheErrorListAndTheRemainder() {
    let fallback = GroupBuckets(counts(5, 2, 1), fallbackErrors: 1)
    #expect(fallback.available == 2 && fallback.limited == 1 && fallback.error == 1 && fallback.idle == 1 && !fallback.usesServerBuckets)
    let bare = GroupBuckets(group: AdminGroup(id: 9, name: "旧站点", platform: "anthropic"))
    #expect(bare.available == 0 && bare.limited == 0 && bare.error == 0 && bare.idle == 0 && bare.total == 0)
}

@Test func bucketsFallbackClampsAtZeroAndKeepsTheSum() {
    let clamped = GroupBuckets(counts(5, 2, 1), fallbackErrors: 5)
    #expect(clamped.error == 2 && clamped.idle == 0)
    #expect(clamped.available + clamped.limited + clamped.error + clamped.idle == clamped.total)
    #expect(clamped.unavailable == 3 && clamped.breakdown == "受限 1 · 错误 2")
    let over = GroupBuckets(counts(3, 3, 2), fallbackErrors: 1)
    #expect(over.error == 0 && over.idle == 0 && over.cellCount == 5 && over.unavailable == 0)
}

@Test func errorCountsCountEachErrorAccountOncePerGroup() {
    let accounts: [UpstreamAccount] = [member(1, status: "error", groups: [1, 2]), member(2, status: "error", groups: [2, 2]), member(3, status: "error"),
                    member(4, groups: [1])]
    #expect(GroupBuckets.errorCounts(accounts: accounts) == [1: 1, 2: 2])
    #expect(GroupBuckets.errorCounts(accounts: []).isEmpty)
}

// MARK: 0.2 健康

@Test func healthFollowsTheTableOrder() {
    func health(_ g: AdminGroup) -> GroupHealth { GroupHealth.resolve(group: g, buckets: GroupBuckets(group: g), shortage: nil) }
    #expect(health(group(1, status: "inactive", account: 3, active: 0, idle: 3)) == .off)
    let none = group(2, account: 3, active: 0, idle: 3)
    #expect(health(none) == .noAvailable && GroupHealth.noAvailable.badge(GroupBuckets(group: none)) == "无可用账号")
    let empty = group(3, account: 0, active: 0)
    #expect(health(empty) == .noAvailable && GroupHealth.noAvailable.badge(GroupBuckets(group: empty)) == "没有账号")
    #expect(health(group(4, account: 3, active: 1, idle: 2)) == .low)
    #expect(health(group(5, account: 4, active: 2, idle: 2)) == .ok)
    #expect(health(group(6, account: 2, active: 1, idle: 1)) == .ok)
    #expect(GroupHealth.ok.badge(buckets(3)) == nil && GroupHealth.low.badge(buckets(1, 0, 0, 2)) == "可用偏低")
    #expect(GroupHealth.off.badge(buckets(3)) == "已停用")
    #expect(GroupHealth.localShortageRatio == 0.5)
}

@Test func healthUsesShortageBeforeTheLocalHalfRule() {
    let short = AccountStatusGroupSummary.Shortage(isShort: true, source: "alert_rule", threshold: 60)
    let fine = AccountStatusGroupSummary.Shortage(isShort: false, source: "default")
    let threeOfFour = group(1, account: 4, active: 3, idle: 1), oneOfFour = group(2, account: 4, active: 1, idle: 3)
    #expect(GroupHealth.resolve(group: threeOfFour, buckets: GroupBuckets(group: threeOfFour), shortage: short) == .low)
    #expect(GroupHealth.resolve(group: oneOfFour, buckets: GroupBuckets(group: oneOfFour), shortage: fine) == .ok)
    let none = group(3, account: 2, active: 0, idle: 2), off = group(4, status: "inactive")
    #expect(GroupHealth.resolve(group: none, buckets: GroupBuckets(group: none), shortage: fine) == .noAvailable)
    #expect(GroupHealth.resolve(group: off, buckets: GroupBuckets(group: off), shortage: short) == .off)
}

@Test func healthWordsTonesSymbolsAndSections() {
    #expect(GroupHealth.off.tone == .neutral && GroupHealth.noAvailable.tone == .critical && GroupHealth.low.tone == .caution && GroupHealth.ok.tone == .ok)
    #expect(GroupHealth.noAvailable.systemImage == "exclamationmark.octagon" && GroupHealth.low.systemImage == "gauge.with.dots.needle.33percent")
    #expect(GroupHealth.ok.systemImage == "square.stack.3d.up" && GroupHealth.off.systemImage == "minus.circle")
    #expect(GroupHealth.noAvailable.section == .attention && GroupHealth.low.section == .attention)
    #expect(GroupHealth.ok.section == .normal && GroupHealth.off.section == .off)
    #expect(GroupHealth.ok.cardTitle(buckets(3)) == "全部可用" && GroupHealth.ok.cardTitle(buckets(3, 1)) == "正常")
    #expect(GroupHealth.noAvailable.cardTitle(buckets(0, 0, 0, 2)) == "无可用账号" && GroupHealth.low.cardTitle(buckets(1, 0, 0, 3)) == "可用偏低")
    #expect(GroupHealth.allCases.sorted() == [.noAvailable, .low, .ok, .off])
    #expect(GroupHealth.noAvailable < .low && GroupHealth.ok < .off && !(GroupHealth.off < .ok))
    #expect(GroupHealth.noAvailable.rawValue == "none" && GroupHealth(rawValue: "none") == .noAvailable)
}

// MARK: 0.3 色格条

@Test func listCellsDrawOneCellPerAccountUpToNineteen() {
    let layout = GroupCellsLayout.list(buckets(10, 4, 2, 3), isActive: true)
    #expect(!layout.isProportional && layout.cells.count == 19)
    #expect(layout.height == 8 && layout.spacing == 2 && layout.cornerRadius == 1.5 && layout.width == 96)
    let width = (96.0 - 36) / 19
    #expect(layout.cells.allSatisfy { close($0.width, width) })
    #expect(layout.cells.enumerated().allSatisfy { close($0.element.x, Double($0.offset) * (width + 2)) })
    let order: [GroupBucket] = [.available, .limited, .error, .idle]
    let runs = zip(order, [10, 4, 2, 3]).flatMap { Array(repeating: Optional($0.0), count: $0.1) }
    #expect(layout.cells.map(\.bucket) == runs)
    #expect(layout.cells.prefix(16).allSatisfy { $0.style == .solid })
    #expect(layout.cells[0].tone == .ok && layout.cells[10].tone == .caution && layout.cells[14].tone == .critical)
    #expect(layout.cells.suffix(3).allSatisfy { $0.tone == .neutral && $0.style == .outline(lineWidth: 1.5, opacity: 0.6) })
    #expect(layout.cells.map(\.id) == Array(0..<19))
}

@Test func listCellsSwitchToProportionalSegmentsFromTwenty() {
    let layout = GroupCellsLayout.list(buckets(10, 0, 5, 5), isActive: true)
    #expect(layout.isProportional && layout.cells.map(\.bucket) == [.available, .error, .idle])
    let total = layout.cells.reduce(0) { $0 + $1.width } + 2 * Double(layout.cells.count - 1)
    #expect(close(total, 96))
    #expect(close(layout.cells[0].width, 92.0 / 2) && close(layout.cells[1].width, 92.0 / 4) && close(layout.cells[2].width, 92.0 / 4))
    #expect(close(layout.cells[1].x, 46 + 2) && close(layout.cells[2].x, 46 + 2 + 23 + 2))
}

@Test func proportionalSegmentsKeepThreePointsForSmallBuckets() {
    let layout = GroupCellsLayout.list(buckets(97, 1, 1, 1), isActive: true)
    #expect(layout.isProportional && layout.cells.count == 4)
    #expect(close(layout.cells[0].width, 96 - 9 - 6))
    #expect(layout.cells.dropFirst().allSatisfy { close($0.width, 3) })
    let narrow = GroupCellsLayout.detail(buckets(40, 1, 1, 1), isActive: true, width: 10)
    #expect(narrow.isProportional && narrow.cells.count == 4)
    #expect(narrow.cells.allSatisfy { close($0.width, 0.25) && $0.width >= 0 })
    let zero = GroupCellsLayout.detail(buckets(40, 1), isActive: true, width: 0)
    #expect(zero.cells.allSatisfy { $0.width >= 0 })
}

@Test func emptyAndInactiveGroupCellStyles() {
    let empty = GroupCellsLayout.list(buckets(0), isActive: true)
    #expect(empty.cells.count == 1 && empty.cells[0].bucket == nil && close(empty.cells[0].width, 96) && empty.cells[0].x == 0)
    #expect(empty.cells[0].tone == .critical && empty.cells[0].style == .outline(lineWidth: 1, opacity: 0.7))
    let off = GroupCellsLayout.list(buckets(2, 1, 0, 1), isActive: false)
    #expect(off.cells.count == 4 && off.cells.allSatisfy { $0.tone == .neutral && $0.style == .outline(lineWidth: 1.5, opacity: 0.45) })
    #expect(off.cells.map(\.bucket) == [.available, .available, .limited, .idle])
    let offEmpty = GroupCellsLayout.list(buckets(0), isActive: false)
    #expect(offEmpty.cells[0].tone == .neutral && offEmpty.cells[0].style == .outline(lineWidth: 1.5, opacity: 0.45))
}

@Test func detailCellsUseFullWidthTwelvePointsAndThreeSpacing() {
    let thirty = GroupCellsLayout.detail(buckets(30), isActive: true, width: 300)
    #expect(!thirty.isProportional && thirty.cells.count == 30 && thirty.height == 12 && thirty.spacing == 3 && thirty.cornerRadius == 2)
    #expect(close(thirty.cells[0].width, (300.0 - 87) / 30))
    #expect(GroupCellsLayout.detail(buckets(60), isActive: true, width: 300).isProportional)
}

@Test func cellsAndLegendSpeakAndDimTheRightThings() {
    let mixed = buckets(2, 0, 0, 1)
    #expect(GroupCellsLayout.list(mixed, isActive: true).accessibilityLabel == "可用 2 / 3")
    let legend = buckets(2, 1, 0, 2).legend
    #expect(legend.map(\.bucket) == [.available, .limited, .error, .idle])
    #expect(legend.map(\.text) == ["可用 2", "受限 1", "错误 0", "暂停·停用 2"])
    #expect(legend.map(\.isDimmed) == [false, false, true, false] && legend[1].id == .limited)
    #expect(buckets(1, 1, 1, 2).breakdown == "受限 1 · 错误 1 · 暂停·停用 2")
    #expect(buckets(1, 1).breakdown == "受限 1" && buckets(3).breakdown == nil)
    #expect(GroupFormat.availability(mixed) == "可用 2/3")
    #expect(GroupBucket.allCases.map(\.label) == ["可用", "受限", "错误", "暂停·停用"])
    #expect(GroupBucket.allCases.map(\.tone) == [.ok, .caution, .critical, .neutral])
}

// MARK: 1.3 列表

@Test func listSectionsSplitIntoAttentionNormalAndOff() {
    let rows = GroupListSections.rows([group(1, account: 3, active: 0, idle: 3), group(2, account: 3, active: 1, idle: 2),
                                       group(3), group(4, account: 0, active: 0)])
    let sections = GroupListSections.sections(rows)
    #expect(sections.map(\.kind) == [.attention, .normal])
    #expect(sections[0].header == "需处理 3" && sections[1].header == "正常 1" && sections[0].id == .attention)
    #expect(GroupListSection.Kind.allCases.map(\.rawValue) == ["attention", "normal", "off"])
    #expect(GroupListSection.Kind.allCases.map(\.title) == ["需处理", "正常", "停用"])
    let off = GroupListSections.sections(GroupListSections.rows([group(5, status: "inactive"), group(6)]))
    #expect(off.map(\.kind) == [.normal, .off] && off[1].rows.map(\.id) == [5])
    #expect(off[1].rows[0].isDimmed && off[1].rows[0].badge == "已停用" && off[0].rows[0].badge == nil && !off[0].rows[0].isDimmed)
}

@Test func listOrderFollowsHealthRatioSortOrderAndID() {
    let rows = GroupListSections.rows([
        group(1, account: 4, active: 2, idle: 2, sortOrder: 0), group(2, account: 3, active: 1, idle: 2), group(3, account: 0, active: 0),
        group(4, account: 4, active: 0, idle: 4), group(5, account: 6, active: 2, idle: 4, sortOrder: 2), group(6, account: 6, active: 2, idle: 4, sortOrder: nil),
        group(7, account: 6, active: 2, idle: 4, sortOrder: nil), group(8, account: 4, active: 1, idle: 3, sortOrder: 9)
    ])
    let attention = GroupListSections.sections(rows)[0]
    #expect(attention.rows.map(\.health) == [.noAvailable, .noAvailable, .low, .low, .low, .low, .low])
    #expect(attention.rows.map(\.id) == [3, 4, 8, 2, 6, 7, 5])
    let normal = GroupListSections.sections(rows)[1]
    #expect(normal.rows.map(\.id) == [1])
}

@Test func listSearchMatchesNameAndChinesePlatformNameIgnoringCase() {
    let rows = GroupListSections.rows([group(1, "高级组"), group(2, "国产", platform: "zhipu"), group(3, "路由", platform: "composite"),
                                       group(4, "Codex 组", platform: "openai")])
    func ids(_ query: String) -> [Int] { GroupListSections.sections(rows, query: query).flatMap(\.rows).map(\.id) }
    #expect(ids("glm") == [2] && ids("ANTH") == [1] && ids("组合") == [3] && ids("codex") == [4] && ids("  高级 ") == [1])
    #expect(ids("没有这个").isEmpty && GroupListSections.sections(rows, query: "没有这个").isEmpty)
    #expect(Set(ids("")) == [1, 2, 3, 4] && Set(ids("   ")) == [1, 2, 3, 4])
    let catalog = MetaCatalog(platforms: [.init(id: "newcloud", displayName: "New Cloud")], platformAuth: [:])
    let custom = GroupListSections.rows([group(5, "海外", platform: "newcloud")])
    #expect(GroupListSections.sections(custom, query: "cloud", catalog: catalog).count == 1)
    #expect(GroupListSections.sections(custom, query: "cloud").count == 1)
    #expect(GroupListSections.matches(group(6, "甲", platform: "newcloud"), query: "new cloud", catalog: catalog))
    #expect(!GroupListSections.matches(group(6, "甲", platform: "newcloud"), query: "new cloud"))
}

@Test func listSubtitleCountsGroupsWithoutAvailableAccounts() {
    let two = GroupListSections.rows([group(1, account: 2, active: 0, idle: 2), group(2, account: 0, active: 0), group(3), group(4, status: "inactive", active: 0, idle: 3)])
    #expect(GroupListSections.subtitle(siteName: "演示站", rows: two) == "演示站 · 2 个分组无可用账号")
    let calm = GroupListSections.rows((1...11).map { group($0, status: $0 == 11 ? "inactive" : "active", active: $0 == 11 ? 0 : 3, idle: $0 == 11 ? 3 : 0) })
    #expect(GroupListSections.subtitle(siteName: "演示站", rows: calm) == "演示站 · 11 个分组")
    let merged = GroupListSections.rows([group(7, account: 4, active: 3, limited: 0, error: nil, idle: nil)], fallbackErrors: [7: 1, 8: 5],
                                        shortages: [7: .init(isShort: true)])
    #expect(merged[0].buckets.error == 1 && merged[0].buckets.idle == 0 && merged[0].health == .low)
    #expect(GroupListRow(group: group(9)).health == .ok)
    #expect(GroupListSections.searchPrompt == "分组名称或平台" && GroupListSections.noMatches == "没有匹配的分组" && GroupListSections.empty == "还没有分组")
    #expect(GroupListSections.footnote == "左滑编辑或停用，右滑添加账号；长按看全部操作。今日按 Key 所属分组统计。")
}

// MARK: 0.6 显示格式

/// U-02: the App's one rate format, three decimals with trailing zeros trimmed down to one.
@Test func rateTextUsesThreeDigits() {
    #expect(GroupFormat.rateText(Decimal(string: "0.8")) == "×0.8")
    #expect(GroupFormat.rateText(1) == "×1.0")
    #expect(GroupFormat.rateText(Decimal(string: "1.25")) == "×1.25")
    #expect(GroupFormat.rateText(Decimal(string: "1.23456789")) == "×1.235")
    #expect(GroupFormat.rateText(Decimal(string: "2.999")) == "×2.999")
    #expect(GroupFormat.rateText(Decimal(string: "0.05")) == "×0.05")
    #expect(GroupFormat.rateText(nil) == "—")
}

@Test func billingRPMLimitExclusiveAndStatusTexts() {
    #expect(GroupFormat.billingText("standard") == "标准（余额）" && GroupFormat.billingText("standard", style: .short) == "标准计费")
    #expect(GroupFormat.billingText("subscription") == "订阅（配额）" && GroupFormat.billingText("subscription", style: .short) == "订阅计费")
    #expect(GroupFormat.billingText("prepaid") == "prepaid" && GroupFormat.billingText(nil) == "—")
    #expect(GroupFormat.rpmText(0) == "不限" && GroupFormat.rpmText(600) == "600" && GroupFormat.rpmText(2000) == "2,000" && GroupFormat.rpmText(nil) == "—")
    #expect(GroupFormat.limitText(nil) == "无限制" && GroupFormat.limitText(20) == "$20" && GroupFormat.limitText(0) == "$0")
    #expect(GroupFormat.limitText(Decimal(string: "20.5")) == "$20.50" && GroupFormat.limitText(1_500) == "$1,500")
    #expect(GroupFormat.exclusiveText(true) == "专属" && GroupFormat.exclusiveText(false) == "公开" && GroupFormat.exclusiveText(nil) == "—")
    #expect(GroupFormat.statusText("active") == "正常" && GroupFormat.statusText("inactive") == "停用" && GroupFormat.statusText("archived") == "archived")
}

@Test func platformClientAndFallbackTexts() {
    #expect(GroupFormat.platformName("zhipu") == "智谱 GLM" && GroupFormat.platformName("composite") == "组合分组")
    #expect(GroupFormat.platformName("newcloud") == "newcloud" && GroupFormat.platformName("") == "—")
    #expect(GroupFormat.clientText(true) == "仅限 Claude Code" && GroupFormat.clientText(false) == "所有客户端" && GroupFormat.clientText(nil) == "—")
    #expect(GroupFormat.fallbackText(group(1, claudeCodeOnly: false, fallback: 2), fallbackName: "标准组") == "—")
    #expect(GroupFormat.fallbackText(group(1, claudeCodeOnly: nil), fallbackName: nil) == "—")
    #expect(GroupFormat.fallbackText(group(1, claudeCodeOnly: true), fallbackName: nil) == "直接拒绝")
    #expect(GroupFormat.fallbackText(group(1, claudeCodeOnly: true, fallback: 2), fallbackName: "标准组") == "标准组")
    #expect(GroupFormat.fallbackText(group(1, claudeCodeOnly: true, fallback: 2), fallbackName: nil) == "分组 #2")
}

@Test func detailSubtitleBillingLineAndTodayText() {
    #expect(GroupFormat.detailSubtitle(group(1), isSimpleMode: false) == "Anthropic · 标准（余额） · 公开")
    #expect(GroupFormat.detailSubtitle(group(1, exclusive: true, type: "subscription"), isSimpleMode: false) == "Anthropic · 订阅（配额） · 专属")
    #expect(GroupFormat.detailSubtitle(group(1), isSimpleMode: true) == "Anthropic")
    #expect(GroupFormat.detailSubtitle(group(1, exclusive: nil, type: nil), isSimpleMode: false) == "Anthropic")
    #expect(GroupFormat.billingLine(group(1)) == "费率倍数 ×0.8 · 标准计费")
    let summary = GroupUsageSummary(groupID: 1, todayCost: Decimal(string: "933.3"), yesterdayCost: nil, totalCost: nil)
    #expect(GroupFormat.todayText(summary) == "今日 $933.30" && GroupFormat.todayValue(summary) == "$933.30")
    #expect(GroupFormat.todayText(nil) == "今日 —")
    #expect(GroupFormat.todayText(GroupUsageSummary(groupID: 1, todayCost: nil, yesterdayCost: 1, totalCost: 1)) == "今日 —")
    #expect(GroupFormat.todayText(GroupUsageSummary(groupID: 1, todayCost: 0, yesterdayCost: nil, totalCost: nil)) == "今日 $0.00")
}

@Test func configRowsFollowTheDetailTable() {
    let standard = GroupFormat.configRows(group(1, rpm: 600, description: "  夜间批量任务  ", claudeCodeOnly: true, fallback: 2), fallbackName: "标准组")
    #expect(standard.map(\.kind) == [.rate, .billing, .rpm, .exclusive, .client, .fallback, .description])
    #expect(standard.map(\.title) == ["费率倍数", "计费类型", "每用户 RPM", "类型", "客户端", "降级分组", "描述"])
    #expect(standard.map(\.value) == ["×0.8", "标准（余额）", "600", "公开", "仅限 Claude Code", "标准组", "夜间批量任务"])
    #expect(standard.filter(\.opensEditor).map(\.kind) == [.rate, .rpm, .exclusive] && standard[0].id == .rate)
    #expect(!GroupFormat.configRows(group(1, description: "   "), fallbackName: nil).contains { $0.kind == .description })
    let subscription = GroupFormat.configRows(group(2, type: "subscription", daily: 20, monthly: Decimal(string: "99.5")), fallbackName: nil)
    #expect(subscription.suffix(3).map(\.kind) == [.dailyLimit, .weeklyLimit, .monthlyLimit])
    #expect(subscription.suffix(3).map(\.title) == ["每日", "每周", "每月"])
    #expect(subscription.suffix(3).map(\.value) == ["$20", "无限制", "$99.50"])
    #expect(subscription.first { $0.kind == .fallback }?.value == "—")
}

// MARK: 3.3 / 3.4 保存后可用

@Test func availableAfterCountsSchedulableMembersOfThePlatform() {
    let members = [
        member(1), member(2, schedulable: false), member(3, rateLimit: at(300)), member(4, autoPause: true, expiresAt: Int64(now.timeIntervalSince1970) - 60),
        member(5, status: "error"), member(6, status: "inactive"), member(7, platform: "openai"), member(8, rateLimit: at(-60)), member(9, overload: at(-1))
    ]
    #expect(GroupPresentation.availableAfter(members: members, platform: "anthropic", now: now) == 3)
    #expect(GroupPresentation.availableAfter(members: members, platform: "composite", now: now) == 4)
    #expect(GroupPresentation.availableAfter(members: members, platform: "gemini", now: now) == 0)
    #expect(GroupPresentation.availableAfter(members: [], platform: "anthropic", now: now) == 0)
}

// MARK: §9 QA 对账

/// The backend's F04 predicates (group_repo.go:991-1022), written out to check the App's D02 conversion against.
private func serverBucket(_ input: AccountStateInput, now: Date) -> GroupBucket {
    if input.status == "error" { return .error }
    guard input.status == "active", input.schedulable else { return .idle }
    if input.autoPauseOnExpired == true, let expiresAt = input.expiresAt, expiresAt <= now { return .idle }
    let windows = [input.overloadUntil, input.rateLimitResetAt, input.tempUnschedulableUntil]
    return windows.contains { ($0 ?? .distantPast) > now } ? .limited : .available
}
private func serverCounts(_ inputs: [AccountStateInput]) -> GroupAccountCounts {
    let found = inputs.map { serverBucket($0, now: now) }
    func n(_ bucket: GroupBucket) -> Int { found.filter { $0 == bucket }.count }
    return GroupAccountCounts(accountCount: inputs.count, activeAccountCount: n(.available), rateLimitedAccountCount: n(.limited),
                              errorAccountCount: n(.error), idleAccountCount: n(.idle))
}
/// What D02 reports for these members: the state of each, a stopped one also counted under its timed state.
private func d02Counts(_ states: [AccountDisplayState]) -> AccountStateCounts {
    func n(_ state: AccountScheduleState) -> Int { states.filter { $0.state == state }.count }
    return AccountStateCounts(total: states.count, available: n(.available), error: n(.error), overloaded: n(.overloaded), rateLimited: n(.rateLimited),
                              tempUnschedulable: n(.tempUnschedulable), paused: n(.paused), inactive: n(.inactive), stopped: states.filter(\.isStopped).count)
}
private let expired = now.addingTimeInterval(-60)
private let window = now.addingTimeInterval(300)
private let qaMembers: [AccountStateInput] = [
    AccountStateInput(status: "active", schedulable: true),
    AccountStateInput(status: "active", schedulable: true, overloadUntil: window),
    AccountStateInput(status: "active", schedulable: false, rateLimitResetAt: window),
    AccountStateInput(status: "active", schedulable: true, tempUnschedulableUntil: window),
    AccountStateInput(status: "active", schedulable: false),
    AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: true, expiresAt: expired),
    AccountStateInput(status: "inactive", schedulable: true),
    AccountStateInput(status: "error", schedulable: false, rateLimitResetAt: window)
]

@Test func qaFourBucketsAlwaysSumToAccountCount() {
    let sources = [GroupBuckets(counts(6, 4, 1, error: 0, idle: 1)), GroupBuckets(counts(5, 2, 1), fallbackErrors: 1),
                   GroupBuckets(counts(5, 2, 1), fallbackErrors: 9),
                   GroupBuckets(GroupAccountCounts.counting(qaMembers.map { AccountDisplayState($0, now: now) }))]
    for source in sources { #expect(source.available + source.limited + source.error + source.idle == source.total) }
    let counted = GroupAccountCounts.counting(qaMembers.map { AccountDisplayState($0, now: now) })
    #expect(counted == GroupAccountCounts(accountCount: 8, activeAccountCount: 1, rateLimitedAccountCount: 2, errorAccountCount: 1, idleAccountCount: 4))
    #expect(GroupAccountCounts.counting([]) == GroupAccountCounts(errorAccountCount: 0, idleAccountCount: 0))
}

@Test func qaF04MatchesD02ExceptExpiredAutoPauseInAWindow() {
    let states = qaMembers.map { AccountDisplayState($0, now: now) }
    let converted = GroupAccountCounts(d02: d02Counts(states))
    #expect(converted == GroupAccountCounts.counting(states))
    #expect(converted == serverCounts(qaMembers))
    #expect(converted.activeAccountCount == d02Counts(states).available && converted.errorAccountCount == d02Counts(states).error)
    // Expired with auto-pause, scheduling still on, inside a window: F04 says idle, D02 says limited and not stopped (50 §0.2).
    let transitional = qaMembers + [AccountStateInput(status: "active", schedulable: true, rateLimitResetAt: window, autoPauseOnExpired: true, expiresAt: expired)]
    let viaD02 = GroupAccountCounts(d02: d02Counts(transitional.map { AccountDisplayState($0, now: now) }))
    let served = serverCounts(transitional)
    #expect(viaD02.rateLimitedAccountCount == served.rateLimitedAccountCount + 1 && viaD02.idleAccountCount == (served.idleAccountCount ?? 0) - 1)
    #expect(viaD02.activeAccountCount == served.activeAccountCount && viaD02.errorAccountCount == served.errorAccountCount)
    #expect(viaD02.accountCount == served.accountCount)
}

// MARK: - QA 对账（S5-13）

/// The backend's simpleModeGroupResponse: the three omitempty counts drop out at 0, error / idle always come, nothing billing.
private let simpleModeReply = Data("""
{"id":1,"name":"高级组","description":"","platform":"anthropic","status":"active","account_count":3,"active_account_count":2,
 "error_account_count":1,"idle_account_count":0,"sort_order":1,"created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-02T00:00:00Z"}
""".utf8)
private let simpleModeEmptyReply = Data("""
{"id":10,"name":"Antigravity 组","platform":"antigravity","status":"active","error_account_count":0,"idle_account_count":0,"sort_order":10}
""".utf8)

@Test func qaSimpleModeReplyDecodesAndBucketsAddUp() throws {
    let decoded = try JSONDecoder().decode(AdminGroup.self, from: simpleModeReply)
    #expect(decoded.rateMultiplier == nil && decoded.isExclusive == nil && decoded.subscriptionType == nil && decoded.rpmLimit == nil)
    #expect(decoded.dailyLimitUSD == nil && decoded.billingLocked == nil && decoded.claudeCodeOnly == nil && decoded.fallbackGroupID == nil)
    let buckets = GroupBuckets(group: decoded)
    #expect(buckets.usesServerBuckets && buckets.available == 2 && buckets.limited == 0 && buckets.error == 1 && buckets.idle == 0)
    #expect(buckets.available + buckets.limited + buckets.error + buckets.idle == decoded.accountCount ?? 0)
    #expect(GroupFormat.detailSubtitle(decoded, isSimpleMode: true) == "Anthropic")
    #expect(!GroupFormat.detailSubtitle(decoded, isSimpleMode: false).contains(" · "))

    let empty = try JSONDecoder().decode(AdminGroup.self, from: simpleModeEmptyReply)
    let none = GroupBuckets(group: empty)
    #expect(empty.accountCount == nil && none.total == 0 && none.cellCount == 0)
    #expect(none.available + none.limited + none.error + none.idle == empty.accountCount ?? 0)
    let health = GroupHealth.resolve(group: empty, buckets: none, shortage: nil)
    #expect(health == .noAvailable && health.badge(none) == "没有账号")
}

/// 50 §9: the list's 今日 and the detail's 今日 column are one amount from one function.
@Test func qaListAndDetailTodayShareOneAmountText() {
    let summary = GroupUsageSummary(groupID: 1, todayCost: Decimal(string: "933.3"), yesterdayCost: Decimal(string: "2985.6"),
                                    totalCost: Decimal(string: "186420.55"))
    let listed = GroupFormat.todayText(summary)
    #expect(listed.hasPrefix("今日 ") && String(listed.dropFirst("今日 ".count)) == GroupUsageFigures(summary).today)
    #expect(GroupUsageFigures(summary).today == "$933.30")
    #expect(GroupFormat.todayText(nil) == "今日 —" && GroupUsageFigures(nil).today == "—")
    let unread = GroupUsageSummary(groupID: 1, todayCost: nil, yesterdayCost: 1, totalCost: 1)
    #expect(String(GroupFormat.todayText(unread).dropFirst("今日 ".count)) == GroupUsageFigures(unread).today)
}
