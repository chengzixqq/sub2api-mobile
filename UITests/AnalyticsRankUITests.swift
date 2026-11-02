import XCTest

/// 40 §1.4 排行卡 and §4 全部排行 on AnalyticsFixtures+Rank (S4-15). S4-19 adds its tests at the end of the class and calls the four
/// helpers below; launching, finding elements and waiting are AnalyticsUITestSupport's. The fixture's numbers are written out
/// here (the UI tests cannot import the App, so change both together).
final class AnalyticsRankUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    private enum Argument {
        static let empty = "-ui-rank-empty"
        static let pageFailure = "-ui-rank-page-fail"
        static let refreshChanges = "-ui-analytics-refresh-changes"
        static let withoutCapabilities = "-ui-without-capabilities"
    }
    private static let pageTitles = ["模型": "模型分布", "用户": "用户排行", "分组": "分组使用分布"]

    // MARK: Helpers (S4-19 uses these four)

    /// Scrolls the card flow to the rank card's segments.
    @MainActor func openRankCard(file: StaticString = #filePath, line: UInt = #line) {
        app.scrollUntilExists(app.analyticsElement("analytics.rankCard.segment"), file: file, line: line)
    }
    /// 模型 · 用户 · 分组 on the card.
    @MainActor func selectCardSegment(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.segmentedControls["analytics.rankCard.segment"].buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        button.tap()
    }
    /// The card's segment, then its foot, into the full ranking.
    @MainActor func openRankPage(from segment: String, file: StaticString = #filePath, line: UInt = #line) {
        openRankCard(file: file, line: line)
        selectCardSegment(segment, file: file, line: line)
        let foot = app.analyticsElement("analytics.rankCard.foot")
        XCTAssertTrue(foot.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        app.scrollUntilExists(foot, file: file, line: line)
        foot.tap()
        XCTAssertTrue(app.navigationBars[Self.pageTitles[segment] ?? segment].waitForExistence(timeout: 10), app.debugDescription,
                      file: file, line: line)
    }
    /// An item of the list header's 排序与口径 menu, by its title.
    @MainActor func chooseSort(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.analyticsElement("analytics.rank.sort")
        app.scrollUntilExists(menu, towardBottom: false, file: file, line: line)
        menu.tap()
        let item = app.buttons[title].firstMatch
        let toggle = app.switches[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5) || toggle.exists, app.debugDescription, file: file, line: line)
        (item.exists ? item : toggle).tap()
    }

    // MARK: Private helpers

    @MainActor private func launch(_ arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.signInForAnalytics(name: "排行站点", url: "https://rank.example.invalid", arguments: arguments)
        app.openAnalyticsFromSearch()
    }
    @MainActor private func cardRow(_ rank: Int) -> XCUIElement { app.analyticsElement("analytics.rankCard.row.\(rank)") }
    @MainActor private func pageRow(_ rank: Int) -> XCUIElement { app.analyticsElement("analytics.rank.row.\(rank)") }
    @MainActor private var cardFoot: XCUIElement { app.analyticsElement("analytics.rankCard.foot") }
    @MainActor private var header: XCUIElement { app.analyticsElement("analytics.rank.header") }
    @MainActor private var footnote: XCUIElement { app.analyticsElement("analytics.rank.footnote") }

    @MainActor @discardableResult
    private func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10,
                              file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let shown = element.poll(NSPredicate(format: "value CONTAINS %@", text), timeout: timeout)
        XCTAssertTrue(shown, "\(element) value should contain “\(text)”, is “\(element.value as? String ?? "nil")”\n\(app.debugDescription)",
                      file: file, line: line)
        return shown
    }
    /// The navigation bar's filter sheet, then a group row.
    @MainActor private func filterByGroup(_ id: Int, file: StaticString = #filePath, line: UInt = #line) {
        app.navigationBars.buttons["analytics.filter.button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["筛选"].waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let row = app.analyticsElement("analytics.filter.row.group.\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription, file: file, line: line)
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: 排行卡（40 §1.4）

    @MainActor func testRankCardSegmentsShowTopFiveAndRememberTheSegment() {
        launch()
        defer { diagnostics("rank-card-final") }
        openRankCard()
        let card = app.analyticsElement("analytics.rankCard")
        XCTAssertTrue(card.staticTexts["排行"].exists, app.debugDescription)
        XCTAssertTrue(card.staticTexts["实际扣费 · 前 5"].exists, app.debugDescription)
        app.waitForLabel(cardRow(1), containing: "claude-opus-4")
        waitForValue(cardRow(1), containing: "$180.20")
        app.waitForLabel(cardRow(5), containing: "glm-4.6")
        XCTAssertFalse(cardRow(6).exists, app.debugDescription)
        app.waitForLabel(cardFoot, containing: "全部 12 个模型 · 含上游口径")
        diagnostics("rank-card-models")

        selectCardSegment("用户")
        app.waitForLabel(cardRow(1), containing: "Studio-K 团队")
        app.waitForLabel(cardFoot, containing: "查看前 50 位用户")
        XCTAssertEqual(cardFoot.label, "查看前 50 位用户", "a foot without a meta reads no trailing “ · ”")
        selectCardSegment("分组")
        app.waitForLabel(cardRow(1), containing: "高级组")
        waitForValue(cardRow(1), containing: "$182.40")
        app.waitForLabel(cardRow(5), containing: "未分组")
        app.waitForLabel(cardFoot, containing: "全部 9 个分组")
        XCTAssertEqual(cardFoot.label, "全部 9 个分组")

        // Remembered on this phone: the next entry opens on 分组.
        app.openAnalyticsFromSearch()
        openRankCard()
        let groups = app.segmentedControls["analytics.rankCard.segment"].buttons["分组"]
        XCTAssertTrue(groups.poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
        app.waitForLabel(cardRow(1), containing: "高级组")
    }

    @MainActor func testRankCardNarrowedFilterClearsAndUserKeyGroupNote() {
        launch()
        defer { diagnostics("rank-card-narrowed-final") }
        openRankCard()
        selectCardSegment("分组")
        app.waitForLabel(cardRow(1), containing: "高级组")
        filterByGroup(1)
        let narrowed = app.analyticsElement("analytics.rankCard.narrowed")
        app.waitForLabel(narrowed, containing: "已筛选分组：高级组")
        XCTAssertFalse(cardRow(1).exists, app.debugDescription)
        XCTAssertFalse(cardFoot.exists, app.debugDescription)
        diagnostics("rank-card-narrowed")
        app.analyticsElement("analytics.rankCard.narrowed.clear").tap()
        XCTAssertTrue(app.analyticsElement("analytics.filter.chip").pollGone(timeout: 5), app.debugDescription)
        app.waitForLabel(cardRow(1), containing: "高级组")

        filterByGroup(1)
        selectCardSegment("用户")
        app.waitForLabel(app.analyticsElement("analytics.rankCard.keyGroupNote"),
                         containing: "按请求时 Key 所属的分组统计：只算各用户在「高级组」Key 上的用量。")
        app.waitForLabel(cardRow(3), containing: "王小明")
        XCTAssertFalse(cardRow(4).exists, app.debugDescription)
        selectCardSegment("模型")
        app.waitForLabel(cardRow(3), containing: "claude-haiku-4.5")
        XCTAssertFalse(cardRow(4).exists, app.debugDescription)
        XCTAssertFalse(cardFoot.exists, app.debugDescription)
    }

    @MainActor func testRankCardEmptyState() {
        launch([Argument.empty])
        defer { diagnostics("rank-card-empty-final") }
        openRankCard()
        let empty = app.analyticsElement("analytics.rankCard.empty")
        app.waitForLabel(empty, containing: "这个范围内没有模型用量")
        XCTAssertFalse(cardFoot.exists, app.debugDescription)
        selectCardSegment("用户")
        app.waitForLabel(empty, containing: "这个范围内没有用户用量")
        XCTAssertFalse(cardFoot.exists, app.debugDescription)
        selectCardSegment("分组")
        app.waitForLabel(empty, containing: "这个范围内没有分组用量")
        XCTAssertFalse(cardFoot.exists, app.debugDescription)
    }

    @MainActor func testRankCardPullToRefreshRereadsTheShownSegment() {
        launch([Argument.refreshChanges])
        defer { diagnostics("rank-card-refresh-final") }
        openRankCard()
        waitForValue(cardRow(1), containing: "$180.20")
        selectCardSegment("用户")
        waitForValue(cardRow(1), containing: "$120.40")
        selectCardSegment("模型")
        waitForValue(cardRow(1), containing: "$180.20")
        let amount = app.analyticsElement("analytics.billing.amount")
        app.scrollUntilExists(amount, towardBottom: false)
        app.pullToRefresh(from: amount)
        openRankCard()
        waitForValue(cardRow(1), containing: "$360.40")
        // The refresh dropped the hidden 用户 segment: shown again, it reads the new answer.
        selectCardSegment("用户")
        waitForValue(cardRow(1), containing: "$240.80")
    }

    // MARK: 全部排行（40 §4）

    @MainActor func testFullModelRankingSortsLocallyAndSwitchesSourceRemembered() {
        launch()
        defer { diagnostics("rank-models-final") }
        openRankPage(from: "模型")
        let subtitle = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "排行站点 · 近 7 天"))
        XCTAssertTrue(subtitle.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let strip = app.analyticsElement("analytics.rank.strip")
        app.waitForLabel(strip, containing: "前 3 占 83.2%")
        XCTAssertTrue(strip.label.contains("合计 $377.50") && strip.label.contains("其余 9 个模型"), strip.label)
        app.waitForLabel(header, containing: "12 个模型")
        app.waitForLabel(pageRow(1), containing: "claude-opus-4")
        diagnostics("rank-models")

        chooseSort("按请求")
        app.waitForLabel(pageRow(1), containing: "claude-sonnet-4.5")
        waitForValue(pageRow(1), containing: "2,400")
        chooseSort("上游模型")
        app.waitForLabel(header, containing: "13 个模型 · 上游模型")
        app.waitForLabel(pageRow(1), containing: "claude-sonnet-4-5-20250929")
        chooseSort("映射（请求 → 上游）")
        app.waitForLabel(header, containing: "13 个模型 · 映射")
        app.waitForLabel(pageRow(1), containing: "claude-sonnet-4.5")
        waitForValue(pageRow(1), containing: "→ claude-sonnet-4-5-20250929")

        // The sort and the source are remembered.
        goBack()
        openRankPage(from: "模型")
        app.waitForLabel(header, containing: "13 个模型 · 映射")
        waitForValue(app.analyticsElement("analytics.rank.sort"), containing: "按请求")
    }

    @MainActor func testFullUserRankingServerSortHeaderAndFootnote() {
        launch()
        defer { diagnostics("rank-users-final") }
        openRankPage(from: "用户")
        app.waitForLabel(header, containing: "前 10 位 · 共 143 位")
        app.waitForLabel(footnote, containing: "按实际扣费取前 50 位，共 143 位用户有用量。")
        app.waitForLabel(pageRow(1), containing: "Studio-K 团队")
        for part in ["ops@studio-k.example", "请求 860", "24.1M Tokens", "账号成本 $61.20"] { waitForValue(pageRow(1), containing: part) }
        app.waitForLabel(pageRow(8), containing: "studio@pixel.example")
        diagnostics("rank-users")
        chooseSort("按请求")
        app.waitForLabel(pageRow(1), containing: "Alice")
        app.waitForLabel(footnote, containing: "按请求取前 50 位，共 143 位用户有用量。")
    }

    @MainActor func testUserRankingWithoutSortCapabilityReSortsLocally() {
        launch([Argument.withoutCapabilities, "dashboard.users_ranking_sort"])
        defer { diagnostics("rank-users-old-final") }
        openRankPage(from: "用户")
        app.waitForLabel(header, containing: "前 10 位")
        XCTAssertFalse(header.label.contains("共"), header.label)
        app.waitForLabel(footnote, containing: "按实际扣费取前 50 位。")
        app.waitForLabel(pageRow(1), containing: "Studio-K 团队")
        XCTAssertFalse((pageRow(1).value as? String ?? "").contains("账号成本"), app.debugDescription)
        chooseSort("按请求")
        app.waitForLabel(pageRow(1), containing: "Alice")
        app.waitForLabel(footnote, containing: "用户排行按实际扣费取前 50 位，这里在其中按请求重排。")
    }

    @MainActor func testRankRowsOpenModelPageAndUserDetail() {
        launch()
        defer { diagnostics("rank-rows-final") }
        openRankCard()
        app.waitForLabel(cardRow(1), containing: "claude-opus-4")
        app.scrollUntilExists(cardRow(1))
        cardRow(1).tap()
        // ComingSoonView until S4-19 builds the model page; both carry the model's name.
        XCTAssertTrue(app.navigationBars["claude-opus-4"].waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        selectCardSegment("用户")
        app.waitForLabel(cardRow(1), containing: "Studio-K 团队")
        app.scrollUntilExists(cardRow(1))
        cardRow(1).tap()
        XCTAssertTrue(app.analyticsElement("user.detail").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Studio-K 团队"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testRankPageFailureOffersRetry() {
        launch([Argument.pageFailure])
        defer { diagnostics("rank-page-failure-final") }
        openRankCard()
        selectCardSegment("用户")
        app.waitForLabel(cardRow(1), containing: "Studio-K 团队")
        openRankPage(from: "用户")
        let failure = app.analyticsElement("analytics.rank.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        let text = failure.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "加载失败")).firstMatch
        XCTAssertTrue(text.exists, app.debugDescription)
        XCTAssertTrue(app.analyticsElement("analytics.rank.retry").exists, app.debugDescription)
        XCTAssertTrue(app.rangeSegment("7 天").exists, app.debugDescription)
        // The failure keeps the sort menu: a sort that fails too (it is remembered at once) can be changed back.
        let sort = app.analyticsElement("analytics.rank.sort")
        waitForValue(sort, containing: "按实际扣费")
        chooseSort("按请求")
        waitForValue(sort, containing: "按请求")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        chooseSort("按实际扣费")
        waitForValue(sort, containing: "按实际扣费")
        XCTAssertTrue(failure.exists, app.debugDescription)
    }

    @MainActor func testFullGroupRankingNarrowsWhenFilteredByGroup() {
        launch()
        defer { diagnostics("rank-groups-final") }
        openRankPage(from: "分组")
        app.waitForLabel(header, containing: "9 个分组")
        app.waitForLabel(pageRow(5), containing: "未分组")
        filterByGroup(1)
        let narrowed = app.analyticsElement("analytics.rank.narrowed")
        app.waitForLabel(narrowed, containing: "已筛选分组：高级组")
        XCTAssertFalse(app.analyticsElement("analytics.rank.strip").exists, app.debugDescription)
        XCTAssertFalse(header.exists, app.debugDescription)
        XCTAssertFalse(pageRow(1).exists, app.debugDescription)
        XCTAssertTrue(app.rangeSegment("7 天").exists, app.debugDescription)
        diagnostics("rank-groups-narrowed")
        app.analyticsElement("analytics.rank.narrowed.clear").tap()
        app.waitForLabel(header, containing: "9 个分组")
        // The session is shared: back on the card flow there is no filter either.
        goBack()
        openRankCard()
        XCTAssertFalse(app.analyticsElement("analytics.filter.chip").exists, app.debugDescription)
        app.waitForLabel(cardRow(1), containing: "高级组")
    }

    // MARK: 模型页（40 §5，S4-19）

    private static let opsDisabled = "-ui-ops-disabled"

    /// The rank card's first model row, claude-opus-4 as requested, into its page.
    @MainActor private func openModelFromCard(file: StaticString = #filePath, line: UInt = #line) {
        openRankCard(file: file, line: line)
        app.waitForLabel(cardRow(1), containing: "claude-opus-4", file: file, line: line)
        app.scrollUntilExists(cardRow(1), file: file, line: line)
        cardRow(1).tap()
        XCTAssertTrue(app.analyticsElement("analytics.model").waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }

    @MainActor func testRankModelRowOpensModelPage() {
        launch()
        defer { diagnostics("model-page-final") }
        openModelFromCard()
        XCTAssertTrue(app.navigationBars["claude-opus-4"].waitForExistence(timeout: 10), app.debugDescription)
        let subtitle = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "模型 · 近 7 天"))
        XCTAssertTrue(subtitle.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.waitForLabel(app.analyticsElement("analytics.model.share"), containing: "实际扣费 · 占全部 2.1%")
        app.waitForLabel(app.analyticsElement("analytics.model.actual"), containing: "$180.20")
        app.waitForLabel(app.analyticsElement("analytics.model.change"), containing: "↑ 11.1%")
        XCTAssertFalse(app.analyticsElement("analytics.model.upstream").exists, app.debugDescription)
        diagnostics("model-page")
        for part in ["trend", "usage", "speed", "users"] { app.scrollUntilExists(app.analyticsElement("analytics.model.\(part).header")) }
        waitForValue(app.analyticsElement("analytics.model.usage.requests"), containing: "1,210")
        waitForValue(app.analyticsElement("analytics.model.speed.tps"), containing: "52.4")
        let logs = app.analyticsElement("analytics.model.logs")
        app.scrollUntilExists(logs)
        app.waitForLabel(logs, containing: "这个模型的使用记录，近 24 小时 · 带上模型筛选，可以去掉")
        let alice = app.analyticsElement("analytics.model.user.1")
        app.waitForLabel(alice, containing: "第 2 名，Alice")
        app.scrollUntilExists(alice, towardBottom: false)
        alice.tap()
        XCTAssertTrue(app.analyticsElement("user.detail").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testMappingModelRowShowsArrowTitleAndUpstreamModel() {
        launch()
        defer { diagnostics("model-mapping-final") }
        openRankPage(from: "模型")
        chooseSort("映射（请求 → 上游）")
        app.waitForLabel(header, containing: "13 个模型 · 映射")
        app.waitForLabel(pageRow(1), containing: "claude-opus-4")
        app.scrollUntilExists(pageRow(1))
        pageRow(1).tap()
        XCTAssertTrue(app.navigationBars["claude-opus-4 → claude-opus-4-20250514"].waitForExistence(timeout: 10), app.debugDescription)
        app.waitForLabel(app.analyticsElement("analytics.model.upstream"), containing: "上游模型 claude-opus-4-20250514")
        app.waitForLabel(app.analyticsElement("analytics.model.actual"), containing: "$180.20")
        diagnostics("model-mapping")
    }

    @MainActor func testModelLogsRowKeepsGroupAndRemovableModelChip() {
        launch()
        defer { diagnostics("model-logs-final") }
        filterByGroup(1)
        openModelFromCard()
        app.waitForLabel(app.analyticsElement("analytics.model.share"), containing: "实际扣费 · 占高级组 5.4%")
        let logs = app.analyticsElement("analytics.model.logs")
        app.scrollUntilExists(logs)
        app.waitForLabel(logs, containing: "近 24 小时 · 带上模型和分组筛选，可以去掉")
        logs.tap()
        XCTAssertTrue(app.navigationBars["使用记录"].waitForExistence(timeout: 10), app.debugDescription)
        let model = app.buttons["logs.chip.model"], group = app.buttons["logs.chip.group"]
        app.waitForLabel(model, containing: "claude-opus-4")
        app.waitForLabel(group, containing: "高级组")
        diagnostics("model-logs")
        model.tap()
        XCTAssertTrue(model.pollGone(timeout: 5), app.debugDescription)
        XCTAssertTrue(group.exists, app.debugDescription)
    }

    /// 40 §5.5: the speed block goes without leaving a gap; the users take its number (叁, checked by AnalyticsModelPageTests).
    @MainActor func testModelPageHidesSpeedWhenOpsMonitoringIsOff() {
        launch([Self.opsDisabled])
        defer { diagnostics("model-ops-off-final") }
        openModelFromCard()
        app.waitForLabel(app.analyticsElement("analytics.model.actual"), containing: "$180.20")
        app.scrollUntilExists(app.analyticsElement("analytics.model.usage.header"))
        app.scrollUntilExists(app.analyticsElement("analytics.model.users.header"))
        XCTAssertFalse(app.analyticsElement("analytics.model.speed.header").exists, app.debugDescription)
        XCTAssertFalse(app.analyticsElement("analytics.model.speed").exists, app.debugDescription)
        app.scrollUntilExists(app.analyticsElement("analytics.model.logs"))
        XCTAssertTrue(app.analyticsElement("analytics.model.user.10").exists, app.debugDescription)
    }
}
