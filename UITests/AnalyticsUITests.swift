import XCTest

/// 40 §1 统计分析 on AnalyticsFixtures (S4-13): the billing card, its selection, the range memory, S4-12's range and filter sheets
/// and the cards' states. Shared by S4-13b, S4-14 and S4-16, which add their tests at the end of the class; the helpers every
/// analytics class uses are in AnalyticsUITestSupport.swift.
final class AnalyticsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// AnalyticsFixtures' numbers as the card shows them (the UI tests cannot import the App, so change both together).
    private enum Expected {
        static let week = "$8,412.30"
        static let weekChange = "↑ 7.9% · 比前 7 天同期"
        /// 账号成本 / 标准 / 利润.
        static let weekFigures = ["$3,362.07", "$10,515.38", "$5,050.23"]
        static let today = "$1,284.50"
        static let todayChange = "↑ 8.1% · 比昨天同时"
        /// HomeUITests.Expected.profit: the overview's cell (40 §1.4 分段取整).
        static let todayProfit = "$772.42"
    }

    // MARK: Helpers

    @MainActor private func launch(_ arguments: [String] = [], name: String = "统计测试") {
        continueAfterFailure = false
        app = XCUIApplication()
        app.signInForAnalytics(name: name, arguments: arguments)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.analyticsElement(identifier) }
    @MainActor private var amount: XCUIElement { element("analytics.billing.amount") }
    @MainActor private func assertSegmentSelected(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let selected = app.rangeSegment(title).poll(NSPredicate(format: "isSelected == true"), timeout: 5)
        XCTAssertTrue(selected, "\(title) should be selected\n\(app.debugDescription)", file: file, line: line)
    }
    /// The billing chart's bars from left to right, found by what VoiceOver reads for them (40 §1.5).
    @MainActor private var billingBars: [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "，实际扣费 ")).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
    }
    /// Taps the chart over one bar (`held`: presses it for a moment, the way `.chartXSelection` scrubs): the whole plot takes the
    /// touch, its x picks the bucket.
    @MainActor private func touchBar(_ index: Int, held: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        app.scrollUntilExists(element("analytics.billing.foot"))
        let bars = billingBars
        XCTAssertTrue(bars.indices.contains(index), app.debugDescription, file: file, line: line)
        let point = bars[index].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if held { point.press(forDuration: 0.3) } else { point.tap() }
    }
    @MainActor private func subtitle(containing text: String) -> XCUIElement {
        app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: S4-13 计费趋势卡

    @MainActor func testFirstEntryFromSearchIsLast7AndShowsTheBillingCard() {
        launch()
        defer { diagnostics("analytics-search-entry-final") }
        app.openAnalyticsFromSearch()
        XCTAssertTrue(subtitle(containing: "统计测试 · 刚刚更新").waitForExistence(timeout: 10), app.debugDescription)
        assertSegmentSelected("7 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 7 天")
        app.waitForValue(amount, equal: Expected.week)
        app.waitForLabel(element("analytics.billing.change"), containing: Expected.weekChange)
        for (key, value) in zip(["accountCost", "standardCost", "profit"], Expected.weekFigures) {
            app.waitForValue(element("analytics.billing." + key), equal: value)
        }
        app.waitForValue(element("analytics.billing.requests"), equal: "121,480")
        app.waitForValue(element("analytics.billing.tokens"), equal: "642.5M")
        app.waitForValue(element("analytics.billing.duration"), equal: "2.3s")
        XCTAssertEqual(element("analytics.billing.foot").label, "全部 7 天 · 计费明细")
        XCTAssertTrue(element("analytics.legend").exists, app.debugDescription)
        // 40 §1.8: the old page's filter form and wording are gone.
        XCTAssertFalse(element("analytics.filters").exists)
        for old in ["上游成本", "扣费与成本差额"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", old)).firstMatch.exists, old)
        }
    }

    @MainActor func testTodayMatchesTheOverviewAndCountsHours() {
        launch()
        defer { diagnostics("analytics-today-final") }
        app.openAnalyticsFromSearch()
        app.selectRangeSegment("今天")
        app.waitForLabel(amount, containing: "实际扣费 · 今天")
        app.waitForValue(amount, equal: Expected.today)
        app.waitForLabel(element("analytics.billing.change"), containing: Expected.todayChange)
        app.waitForValue(element("analytics.billing.profit"), equal: Expected.todayProfit)
        let foot = element("analytics.billing.foot").label
        XCTAssertNotNil(foot.range(of: #"^全部 \d+ 小时 · 计费明细$"#, options: .regularExpression), foot)
    }

    @MainActor func testSelectingABarShowsItsBucketAndTappingAgainClears() {
        launch()
        defer { diagnostics("analytics-selection-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        touchBar(0)
        let dayLabel = NSPredicate(format: "label MATCHES %@", #"^\d+月\d+日 周.$"#)
        XCTAssertTrue(amount.poll(dayLabel, timeout: 5), app.debugDescription)
        let selection = element("analytics.billing.selection")
        XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
        for part in ["标准 $", "请求 ", "再点一下取消"] { XCTAssertTrue(selection.label.contains(part), selection.label) }
        XCTAssertFalse(element("analytics.billing.change").exists, app.debugDescription)
        diagnostics("analytics-selection")
        // The same bucket again clears the selection.
        touchBar(0)
        app.waitForLabel(amount, containing: "实际扣费 · 近 7 天")
        XCTAssertTrue(selection.pollGone(timeout: 5), app.debugDescription)
        // Pressed and held selects as well; a range change clears it.
        touchBar(6, held: true)
        XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
        app.selectRangeSegment("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
        XCTAssertTrue(selection.pollGone(timeout: 5), app.debugDescription)
    }

    @MainActor func testBarsReadBucketAndAmountForVoiceOver() {
        launch()
        defer { diagnostics("analytics-bars-voiceover-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        XCTAssertTrue(element("analytics.billing.chart").exists, app.debugDescription)
        let bars = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "，实际扣费 $"))
        XCTAssertEqual(bars.count, 7, app.debugDescription)
    }

    @MainActor func testBillingFootOpensTheBillingDetail() {
        launch()
        defer { diagnostics("analytics-foot-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        let foot = element("analytics.billing.foot")
        app.scrollUntilExists(foot)
        foot.tap()
        // 图表 until S4-14 builds 计费明细.
        let detail = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["图表", "计费明细"])).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        // The session kept the card: no reload on the way back.
        XCTAssertFalse(element("analytics.billing.loading").exists, app.debugDescription)
        XCTAssertEqual(amount.value as? String, Expected.week)
    }

    // MARK: S4-13 范围记忆（40 §0.1）

    @MainActor func testRangeChangedFromSearchIsKeptWhenEnteringFromTheOverview() {
        launch()
        defer { diagnostics("analytics-memory-overview-final") }
        app.openAnalyticsFromSearch()
        assertSegmentSelected("7 天")
        app.selectRangeSegment("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
        app.openAnalyticsFromOverview("home.ticker.actualCost")
        assertSegmentSelected("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
    }

    @MainActor func testOverviewEntryWithoutAChangeIsNotRemembered() {
        launch()
        defer { diagnostics("analytics-memory-unchanged-final") }
        app.openAnalyticsFromOverview("home.today.more")
        assertSegmentSelected("今天")
        app.waitForLabel(amount, containing: "实际扣费 · 今天")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openAnalyticsFromSearch()
        assertSegmentSelected("7 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 7 天")
    }

    @MainActor func testAnotherSiteStartsFromItsEntryDefault() {
        launch(name: "站点 A")
        defer { diagnostics("analytics-memory-site-final") }
        app.openAnalyticsFromSearch()
        app.selectRangeSegment("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        app.signInForAnalytics(name: "站点 B", url: "https://analysis-b.example.invalid", launch: false)
        app.openAnalyticsFromSearch()
        assertSegmentSelected("7 天")
        app.openSitesSettings()
        let siteA = app.buttons["settings.site.站点 A"]
        app.scrollUntilExists(siteA, towardBottom: false)
        siteA.tap()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10), app.debugDescription)
        app.openAnalyticsFromSearch()
        assertSegmentSelected("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
    }
}
