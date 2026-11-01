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
        /// 40% of 近 7 天 under a group filter.
        static let weekFiltered = "$3,364.92"
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

    // MARK: S4-12 范围与筛选 sheet（S4D1-05）

    @MainActor func testCustomRangeShortcutAppliesToCaptionAndCard() {
        launch()
        defer { diagnostics("analytics-custom-shortcut-final") }
        app.openAnalyticsFromSearch()
        openCustomRange()
        element("analytics.custom.preset.last14").tap()
        XCTAssertTrue(element("analytics.custom.preset.last14").poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
        element("analytics.custom.apply").tap()
        XCTAssertTrue(app.navigationBars["自定义范围"].pollGone(timeout: 5), app.debugDescription)
        assertSegmentSelected("近 14 天")
        let caption = element("analytics.range.caption")
        app.waitForLabel(caption, containing: "（今天到")
        app.waitForLabel(caption, containing: "按天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 14 天")
        app.waitForValue(amount, equal: "$16,824.64")
        app.waitForLabel(element("analytics.billing.foot"), containing: "全部 14 天 · 计费明细")
    }

    @MainActor func testPickingLastMonthSelectsItsShortcutAndOldDatesAreDisabled() {
        launch()
        defer { diagnostics("analytics-custom-last-month-final") }
        app.openAnalyticsFromSearch()
        openCustomRange()
        let lastMonth = Self.lastMonth()
        // From 本月 (the sheet's start for a bar preset): one month back on each end.
        pickDay(on: "start", monthsBack: 1, month: lastMonth.month, day: 1)
        pickDay(on: "end", monthsBack: 1, month: lastMonth.month, day: lastMonth.lastDay)
        let shortcut = element("analytics.custom.preset.lastMonth")
        XCTAssertTrue(shortcut.poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
        diagnostics("analytics-custom-last-month")
        // U36: 366 days back at most, so the start calendar stops about a year back.
        tapRow("analytics.custom.start")
        let previous = calendar("start").buttons["DatePicker.PreviousMonth"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5), app.debugDescription)
        var steps = 0
        while previous.isEnabled, steps < 14 {
            previous.tap()
            steps += 1
        }
        XCTAssertFalse(previous.isEnabled, app.debugDescription)
        XCTAssertTrue((11...13).contains(steps), "\(steps) months back\n\(app.debugDescription)")
        let earliest = Self.earliestDay()
        if earliest.day > 1 {
            let before = dayButton(on: "start", month: earliest.month, day: earliest.day - 1)
            XCTAssertTrue(before.exists && !before.isEnabled, app.debugDescription)
            XCTAssertTrue(dayButton(on: "start", month: earliest.month, day: earliest.day).isEnabled, app.debugDescription)
        }
        element("analytics.custom.apply").tap()
        app.waitForLabel(amount, containing: "实际扣费 · 上月")
        let change = element("analytics.billing.change")
        app.waitForLabel(change, containing: "比 ")
        XCTAssertTrue(change.label.hasSuffix(" 月"), change.label)
    }

    @MainActor func testGroupFilterShowsARemovableChipAndScalesTheCard() {
        launch()
        defer { diagnostics("analytics-group-filter-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        openFilter()
        let row = element("analytics.filter.row.group.1")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription)
        let chip = element("analytics.filter.chip")
        app.waitForLabel(chip, containing: "分组：高级组")
        app.waitForValue(amount, equal: Expected.weekFiltered)
        chip.tap()
        XCTAssertTrue(chip.pollGone(timeout: 5), app.debugDescription)
        app.waitForValue(amount, equal: Expected.week)
    }

    @MainActor func testModelFilterNoteWithoutOpsModelFilter() {
        launch(["-ui-without-capabilities", "ops.dashboard_model_filter"])
        defer { diagnostics("analytics-model-filter-note-final") }
        app.openAnalyticsFromSearch()
        openFilter()
        app.segmentedControls["analytics.filter.kind"].buttons["模型"].tap()
        let note = app.staticTexts["运行类图表（RPM / TPM、时长、错误）后端不支持按模型，仍显示全站。"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: S4-13 卡内状态（40 §1.6）

    @MainActor func testFirstLoadShowsProgressInsideTheCard() {
        launch(["-ui-analytics-slow"])
        defer { diagnostics("analytics-first-load-final") }
        app.openSearchItem("search.item.analytics")
        let loading = element("analytics.billing.loading")
        XCTAssertTrue(loading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(loading.frame.height, 250, app.debugDescription)
        diagnostics("analytics-first-load")
        app.waitForValue(amount, equal: Expected.week, timeout: 15)
        XCTAssertTrue(loading.pollGone(timeout: 5), app.debugDescription)
    }

    @MainActor func testFailedCardRetriesThisItem() {
        launch(["-ui-analytics-fail-once"])
        defer { diagnostics("analytics-failed-final") }
        app.openSearchItem("search.item.analytics")
        let failure = element("analytics.billing.failure")
        XCTAssertTrue(text(in: failure, containing: "加载失败").waitForExistence(timeout: 10), app.debugDescription)
        let retry = element("analytics.billing.retry")
        XCTAssertEqual(retry.label, "重试本项")
        diagnostics("analytics-failed")
        retry.tap()
        app.waitForValue(amount, equal: Expected.week)
        XCTAssertTrue(failure.pollGone(timeout: 5), app.debugDescription)
    }

    @MainActor func testTimedOutCardSaysStatisticsAreSlow() {
        launch(["-ui-analytics-timeout"])
        defer { diagnostics("analytics-timeout-final") }
        app.openSearchItem("search.item.analytics")
        let failure = element("analytics.billing.failure")
        XCTAssertTrue(text(in: failure, containing: "统计较慢，加载超时").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("analytics.billing.retry").label, "重试本项")
    }

    @MainActor func testThrottledCardCountsDownWithRetryDisabled() {
        launch(["-ui-analytics-throttled"])
        defer { diagnostics("analytics-throttled-final") }
        app.openSearchItem("search.item.analytics")
        let failure = element("analytics.billing.failure")
        let countdown = failure.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "请求过于频繁，", "秒后自动重试")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("analytics.billing.retry").isEnabled, app.debugDescription)
    }

    @MainActor func testRefreshFailureKeepsOldDataWithAStaleLine() {
        launch(["-ui-analytics-refresh-fails"])
        defer { diagnostics("analytics-stale-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        app.waitForLabel(element("analytics.billing.change"), containing: Expected.weekChange)
        app.pullToRefresh(from: amount)
        let stale = element("analytics.billing.stale.failure")
        XCTAssertTrue(text(in: stale, containing: "更新失败 · 显示的是 ").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(in: stale, containing: " 的数据").exists, app.debugDescription)
        XCTAssertEqual(element("analytics.billing.stale.retry").label, "重试本项")
        XCTAssertEqual(amount.value as? String, Expected.week)
        // The comparison read again and the totals did not: no change line across the two moments.
        XCTAssertTrue(element("analytics.billing.change").pollGone(timeout: 5), app.debugDescription)
    }

    @MainActor func testEmptyRangeSaysNoUsage() {
        launch(["-ui-analytics-empty"])
        defer { diagnostics("analytics-empty-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: "$0.00")
        app.waitForLabel(element("analytics.billing.chart.empty"), containing: "这个范围内没有用量")
        app.waitForValue(element("analytics.billing.requests"), equal: "0")
        app.waitForValue(element("analytics.billing.duration"), equal: "无数据")
    }

    @MainActor func testOldServerAndFailedComparison() {
        launch(["-ui-without-capabilities", "dashboard.account_cost", "-ui-analytics-comparison-fails"])
        defer { diagnostics("analytics-old-server-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        app.waitForValue(element("analytics.billing.accountCost"), equal: "无数据")
        app.waitForValue(element("analytics.billing.profit"), equal: "无数据")
        app.waitForValue(element("analytics.billing.standardCost"), equal: Expected.weekFigures[1])
        XCTAssertFalse(element("analytics.billing.change").exists, app.debugDescription)
    }

    // MARK: Helpers of the sheet and state tests

    @MainActor private func openCustomRange() {
        element("analytics.range.caption").tap()
        XCTAssertTrue(app.navigationBars["自定义范围"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func openFilter() {
        app.navigationBars.buttons["analytics.filter.button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["筛选"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func text(in container: XCUIElement, containing part: String) -> XCUIElement {
        container.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func calendar(_ end: String) -> XCUIElement { element("analytics.custom.calendar." + end) }
    /// A day of the graphical calendar: “10月1日 星期四”, “今天, 11月1日 星期日”, with the year when it is not this one.
    @MainActor private func dayButton(on end: String, month: Int, day: Int) -> XCUIElement {
        let name = "\(month)月\(day)日 "
        return calendar(end).buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS %@",
                                                          name, ", " + name, "年" + name)).firstMatch
    }
    /// Opens the start or end row's calendar unless it is open.
    @MainActor private func tapRow(_ identifier: String) {
        let row = element(identifier)
        revealInSheet(row)
        if !(row.value as? String == "1" || row.isSelected) { row.tap() }
    }
    @MainActor private func pickDay(on end: String, monthsBack: Int, month: Int, day: Int) {
        tapRow("analytics.custom." + end)
        let previous = calendar(end).buttons["DatePicker.PreviousMonth"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<monthsBack { previous.tap() }
        let button = dayButton(on: end, month: month, day: day)
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        revealInSheet(button)
        button.tap()
    }
    /// The sheet's list scrolls the open calendar's last rows into view.
    @MainActor private func revealInSheet(_ item: XCUIElement) {
        for _ in 0..<4 where !(item.exists && item.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
    }
    /// The site's (Asia/Shanghai, the fixture server's) calendar.
    private static var siteCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private static func lastMonth() -> (month: Int, lastDay: Int) {
        let calendar = siteCalendar
        let date = calendar.date(byAdding: .month, value: -1, to: Date())!
        return (calendar.component(.month, from: date), calendar.range(of: .day, in: .month, for: date)!.count)
    }
    /// U36: 366 days before the site's today.
    private static func earliestDay() -> (month: Int, day: Int) {
        let calendar = siteCalendar
        let date = calendar.date(byAdding: .day, value: -366, to: Date())!
        return (calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    // MARK: S4-13b 利润明细卡

    /// AnalyticsFixtures' 近 7 天 profit as the card shows it (change both together).
    private enum ProfitExpected {
        /// The billing card's 利润: the loss and the old server's trend leave the totals as they are.
        static let week = "$5,050.23"
        /// Rows 6, 5, 4, 3 (newest on top): actual − account cost per day.
        static let weekRows = ["$1,082.20", "$841.71", "$961.95", "$721.46"]
        static let loss = "−$50.00"
    }

    @MainActor private var profitAmount: XCUIElement { element("analytics.profit.amount") }
    @MainActor private func profitRow(_ index: Int) -> XCUIElement { element("analytics.profit.row.\(index)") }
    /// The profit chart's bars from left to right, by what VoiceOver reads for them (the table's rows also read 实际).
    @MainActor private var profitBars: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "，利润 ", "，实际 ")).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
    }
    /// Scrolls until the card's foot shows, with the chart and the table above it.
    @MainActor private func revealProfitCard() { app.scrollUntilExists(element("analytics.profit.foot")) }
    @MainActor private func touchProfitBar(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        revealProfitCard()
        let bars = profitBars
        XCTAssertTrue(bars.indices.contains(index), app.debugDescription, file: file, line: line)
        bars[index].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor func testProfitCardShowsTotalLatestFourRowsAndSelection() {
        launch()
        defer { diagnostics("analytics-profit-final") }
        app.openAnalyticsFromSearch()
        revealProfitCard()
        app.waitForLabel(profitAmount, containing: "利润 · 近 7 天")
        app.waitForValue(profitAmount, equal: ProfitExpected.week)
        XCTAssertEqual(element("analytics.profit.meta").label, "实际扣费 − 账号成本")
        app.waitForLabel(element("analytics.profit.change"), containing: "比前 7 天同期")
        let rows = [6, 5, 4, 3].map { profitRow($0) }
        for (row, profit) in zip(rows, ProfitExpected.weekRows) { app.waitForLabel(row, containing: "，利润 " + profit) }
        let tops = rows.map { $0.frame.minY }
        XCTAssertEqual(tops, tops.sorted(), app.debugDescription)
        XCTAssertFalse(profitRow(2).exists, app.debugDescription)
        diagnostics("analytics-profit")
        // A bar shows its bucket; the same bar again clears it.
        touchProfitBar(5)
        XCTAssertTrue(profitAmount.poll(NSPredicate(format: "label MATCHES %@", #"^\d+月\d+日 周.$"#), timeout: 5), app.debugDescription)
        app.waitForValue(profitAmount, equal: ProfitExpected.weekRows[1])
        let selection = element("analytics.profit.selection")
        XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(selection.label.hasPrefix("实际 $") && selection.label.hasSuffix("再点一下取消"), selection.label)
        XCTAssertFalse(element("analytics.profit.change").exists, app.debugDescription)
        XCTAssertTrue(profitRow(5).isSelected, app.debugDescription)
        touchProfitBar(5)
        app.waitForLabel(profitAmount, containing: "利润 · 近 7 天")
        XCTAssertTrue(selection.pollGone(timeout: 5), app.debugDescription)
        // A range change clears the selection; the foot counts the new range and opens 利润明细.
        touchProfitBar(6)
        XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
        app.scrollUntilExists(app.rangeSegment("30 天"), towardBottom: false)
        app.selectRangeSegment("30 天")
        app.waitForLabel(profitAmount, containing: "利润 · 近 30 天")
        XCTAssertTrue(selection.pollGone(timeout: 5), app.debugDescription)
        let foot = element("analytics.profit.foot")
        app.waitForLabel(foot, containing: "全部 30 天 · 利润明细")
        app.scrollUntilExists(foot)
        foot.tap()
        // 图表 until S4-14 builds 利润明细.
        let detail = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["图表", "利润明细"])).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testProfitLossBucketDrawsBelowZeroAndReadsNegative() {
        launch(["-ui-analytics-loss"])
        defer { diagnostics("analytics-profit-loss-final") }
        app.openAnalyticsFromSearch()
        revealProfitCard()
        app.waitForValue(profitAmount, equal: ProfitExpected.week)
        let row = profitRow(5)
        app.waitForLabel(row, containing: "，利润 " + ProfitExpected.loss)
        XCTAssertFalse(row.label.contains("-$") || row.label.contains("+"), row.label)
        XCTAssertTrue(profitBars.contains { $0.label.contains("，利润 " + ProfitExpected.loss) }, app.debugDescription)
        // A loss is not an empty range.
        XCTAssertFalse(element("analytics.profit.chart.empty").exists, app.debugDescription)
        diagnostics("analytics-profit-loss")
        touchProfitBar(5)
        app.waitForValue(profitAmount, equal: ProfitExpected.loss)
        XCTAssertTrue(element("analytics.profit.selection").label.hasPrefix("实际 $1,402.05 · 账号成本 $1,452.05"), app.debugDescription)
    }

    @MainActor func testLegacyTrendProfitReadsEachSegmentAndMarksTheFailedOne() {
        launch(["-ui-analytics-legacy-trend"])
        defer { diagnostics("analytics-profit-legacy-final") }
        app.openAnalyticsFromSearch()
        revealProfitCard()
        // The total still comes from usage/stats; the failed segment's cost and profit are missing.
        app.waitForValue(profitAmount, equal: ProfitExpected.week)
        app.waitForLabel(profitRow(4), containing: "，账号成本 无数据，利润 无数据")
        for (index, profit) in [(6, ProfitExpected.weekRows[0]), (5, ProfitExpected.weekRows[1]), (3, ProfitExpected.weekRows[3])] {
            app.waitForLabel(profitRow(index), containing: "，利润 " + profit)
        }
        XCTAssertTrue(profitBars.contains { $0.label.contains("，利润 无数据") }, app.debugDescription)
        diagnostics("analytics-profit-legacy")
    }

    // MARK: S4-16 RPM / TPM 趋势卡

    /// AnalyticsFixtures+Perf as the card shows it (change both together): “now” is 2026-10-15 09:01:23 in Asia/Shanghai.
    private enum PerfExpected {
        /// The newest bucket, 09:00 (its start in Unix seconds), and the one before it in 5-minute buckets, 08:55.
        static let newestRow = "analytics.perf.row.1792026000"
        static let previousFiveMinuteRow = "analytics.perf.row.1792025700"
        /// /admin/me says ops monitoring is on, the throughput reads answer 404 OPS_DISABLED.
        static let opsGone = "-ui-analytics-ops-gone"
    }

    @MainActor private var perfAmount: XCUIElement { element("analytics.perf.amount") }
    @MainActor private var perfNotice: XCUIElement { element("analytics.perf").descendants(matching: .any)["ops.disabled.empty"].firstMatch }
    @MainActor private func perfSegment(_ control: String, _ title: String) -> XCUIElement {
        app.segmentedControls[control].buttons[title].firstMatch
    }
    /// Scrolls the card flow until the card's foot shows, with the big number and the chart above it.
    @MainActor private func perfRevealCard(file: StaticString = #filePath, line: UInt = #line) {
        app.scrollUntilExists(element("analytics.perf.foot"), file: file, line: line)
    }
    @MainActor private func perfAssertSelected(_ control: String, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let selected = perfSegment(control, title).poll(NSPredicate(format: "isSelected == true"), timeout: 5)
        XCTAssertTrue(selected, "\(title) should be selected\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func perfSelectWindow(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let segment = perfSegment("analytics.perf.window", title)
        let isAbove = segment.exists && segment.frame.minY < app.navigationBars.firstMatch.frame.maxY
        app.scrollUntilExists(segment, towardBottom: !isAbove, file: file, line: line)
        segment.tap()
        perfAssertSelected("analytics.perf.window", title, file: file, line: line)
    }
    @MainActor private func perfWaitUntilHittable(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, app.debugDescription, file: file, line: line)
    }

    @MainActor func testPerfCardFromTPMCellScrollsToCardAndSelectsTPM() {
        launch()
        defer { diagnostics("analytics-perf-tpm-final") }
        app.openAnalyticsFromOverview("home.ticker.tpm")
        // 40 §1.1: the page scrolls to the card once and opens it on TPM.
        XCTAssertTrue(perfAmount.waitForExistence(timeout: 10), app.debugDescription)
        perfWaitUntilHittable(perfAmount)
        perfAssertSelected("analytics.perf.metric", "TPM")
        app.waitForLabel(perfAmount, containing: "TPM · 最新一桶 09:00")
        app.waitForValue(perfAmount, equal: "240K")
        app.waitForLabel(element("analytics.perf.subline"), containing: "峰值 260K · 平均 220K · 近 1 小时")
        XCTAssertEqual(element("analytics.perf.meta").label, "截至现在 · 运维监控")
        diagnostics("analytics-perf-tpm")
        // route.metric was remembered: entering from the search directory shows TPM too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openAnalyticsFromSearch()
        perfRevealCard()
        perfAssertSelected("analytics.perf.metric", "TPM")
    }

    @MainActor func testPerfDetailsShowPartialBucketAndRowSelectsPoint() {
        launch()
        defer { diagnostics("analytics-perf-details-final") }
        app.openAnalyticsFromSearch()
        perfRevealCard()
        perfAssertSelected("analytics.perf.metric", "RPM")
        app.waitForLabel(perfAmount, containing: "RPM · 最新一桶 09:00")
        app.waitForValue(perfAmount, equal: "46")
        app.waitForLabel(element("analytics.perf.subline"), containing: "峰值 52 · 平均 44 · 近 1 小时")
        let foot = element("analytics.perf.foot")
        app.waitForLabel(foot, containing: "性能明细 · 60 桶 · 最新在上")
        app.waitForLabel(element("analytics.perf.note"), containing: "窗口从 08:01 到现在")
        app.waitForLabel(element("analytics.perf.updated"), containing: " · 前台每 30 秒刷新")
        // 近 6 小时 has 5-minute buckets; the window cuts the first and the newest.
        perfSelectWindow("近 6 小时")
        app.waitForLabel(foot, containing: "73 桶 · 最新在上")
        app.scrollUntilExists(foot)
        foot.tap()
        XCTAssertTrue(app.navigationBars["性能明细"].waitForExistence(timeout: 5), app.debugDescription)
        let close = element("analytics.perf.sheet.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(close.label, "关闭")
        XCTAssertLessThan(close.frame.midX, app.frame.midX, "关闭 sits at the top left")
        app.waitForLabel(element("analytics.perf.sheet.note"), containing: "最新在上 · 近 6 小时 · 每桶 5 分钟")
        let newest = element(PerfExpected.newestRow)
        app.waitForLabel(newest, containing: "09:00 · 只覆盖 60 秒")
        XCTAssertTrue(newest.label.contains("RPM 46 · TPM 240K"), newest.label)
        let previous = element(PerfExpected.previousFiveMinuteRow)
        XCTAssertTrue(previous.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(newest.frame.minY, previous.frame.minY, "newest on top")
        XCTAssertFalse(previous.label.contains("只覆盖"), previous.label)
        diagnostics("analytics-perf-details")
        // A row closes the sheet and selects its bucket.
        newest.tap()
        XCTAssertTrue(app.navigationBars["性能明细"].pollGone(timeout: 5), app.debugDescription)
        app.waitForLabel(element("analytics.perf.subline"), containing: "09:00 · RPM 46 · 再点一下取消")
        XCTAssertTrue(perfAmount.poll(NSPredicate(format: "label == %@", "RPM · 09:00"), timeout: 5), perfAmount.label)
        // The window is remembered; entering again starts without a selection.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openAnalyticsFromSearch()
        perfRevealCard()
        perfAssertSelected("analytics.perf.window", "近 6 小时")
        app.waitForLabel(perfAmount, containing: "RPM · 最新一桶 09:00")
        XCTAssertFalse(element("analytics.perf.subline").label.contains("再点一下取消"), app.debugDescription)
    }

    @MainActor func testPerfCardShowsOpsDisabledNoticeAndLoadsAfterEnabling() {
        launch(["-ui-ops-disabled"])
        defer { diagnostics("analytics-perf-ops-off-final") }
        app.openAnalyticsFromSearch()
        // 10 §7.2's OpsDisabledNotice takes the whole body (S1D1-28), the header keeps only 运维监控.
        app.scrollUntilExists(perfNotice)
        XCTAssertEqual(element("analytics.perf.meta").label, "运维监控")
        XCTAssertFalse(element("analytics.perf.chart").exists, app.debugDescription)
        XCTAssertFalse(element("analytics.perf.window").exists, app.debugDescription)
        diagnostics("analytics-perf-ops-off")
        let enable = element("analytics.perf").descendants(matching: .any)["ops.disabled.enable"].firstMatch
        XCTAssertTrue(enable.waitForExistence(timeout: 5), app.debugDescription)
        enable.tap()
        let alert = app.alerts["开启运维监控？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["开启"].firstMatch.tap()
        // The card reads as soon as ops is on.
        XCTAssertTrue(element("analytics.perf.chart").waitForExistence(timeout: 15), app.debugDescription)
        app.waitForLabel(perfAmount, containing: "最新一桶")
        app.waitForLabel(element("analytics.perf.meta"), containing: "截至现在 · 运维监控")
        XCTAssertFalse(perfNotice.exists, app.debugDescription)
    }

    @MainActor func testPerfCardTurnsIntoNoticeOn404OpsDisabled() {
        launch([PerfExpected.opsGone])
        defer { diagnostics("analytics-perf-ops-gone-final") }
        app.openAnalyticsFromSearch()
        // 40 §1.6: 404 OPS_DISABLED is not a failure of the card.
        app.scrollUntilExists(perfNotice)
        XCTAssertFalse(element("analytics.perf.failure").exists, app.debugDescription)
        XCTAssertFalse(text(in: element("analytics.perf"), containing: "加载失败").exists, app.debugDescription)
        XCTAssertFalse(element("analytics.perf.chart").exists, app.debugDescription)
        diagnostics("analytics-perf-ops-gone")
    }

    @MainActor func testPerfCardSaysSiteWideForModelFilterWithoutCapability() {
        launch(["-ui-without-capabilities", "ops.dashboard_model_filter"])
        defer { diagnostics("analytics-perf-site-wide-final") }
        app.openAnalyticsFromSearch()
        openFilter()
        app.segmentedControls["analytics.filter.kind"].buttons["模型"].tap()
        let row = element("analytics.filter.row.model.claude-opus-4")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription)
        // 40 §1.2: the model cannot reach the ops charts, so the card says it shows the whole site.
        let note = element("analytics.perf.siteWide")
        app.scrollUntilExists(note)
        app.waitForLabel(note, containing: "运行类图表不支持按这个模型筛选，这里显示全站")
        app.waitForLabel(perfAmount, containing: "最新一桶")
        diagnostics("analytics-perf-site-wide")
        let chip = element("analytics.filter.chip")
        app.scrollUntilExists(chip, towardBottom: false)
        chip.tap()
        XCTAssertTrue(note.pollGone(timeout: 5), app.debugDescription)
    }

    /// 00 §2.7.2: a 429 among an old server's segments counts down on the card with 重试本项 held back; what was read still shows.
    @MainActor func testLegacyTrendProfitSegmentsCutShortByA429CountDown() {
        launch(["-ui-analytics-legacy-trend", "-ui-analytics-throttled-segments"])
        defer { diagnostics("analytics-profit-throttled-final") }
        app.openAnalyticsFromSearch()
        revealProfitCard()
        app.waitForLabel(profitRow(4), containing: "，账号成本 无数据，利润 无数据")
        app.waitForLabel(profitRow(5), containing: "，利润 " + ProfitExpected.weekRows[1])
        let failure = element("analytics.profit.segments.stale.failure")
        let notice = failure.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "请求过于频繁，")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10) && notice.label.hasSuffix("秒后自动重试"), app.debugDescription)
        let retry = element("analytics.profit.segments.stale.retry")
        XCTAssertTrue(retry.exists && !retry.isEnabled, app.debugDescription)
        diagnostics("analytics-profit-throttled")
    }

    // MARK: S4-14 单图页（40 §3）

    @MainActor private var billingHead: XCUIElement { element("analytics.body.billing.head") }
    @MainActor private func billingDetailRow(_ index: Int) -> XCUIElement { element("analytics.body.billing.row.\(index)") }
    @MainActor private var selectedBillingRows: XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isSelected == true", "analytics.body.billing.row."))
    }
    /// 计费趋势's foot → 计费明细, once its head has the total.
    @MainActor private func openBillingDetail(file: StaticString = #filePath, line: UInt = #line) {
        let foot = element("analytics.billing.foot")
        app.scrollUntilExists(foot, file: file, line: line)
        foot.tap()
        XCTAssertTrue(app.navigationBars["计费明细"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        app.waitForLabel(billingHead, containing: "实际 $", file: file, line: line)
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    @MainActor func testBillingDetailOpensFromTheCardAndListsEveryBucket() {
        launch()
        defer { diagnostics("analytics-billing-detail-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        openBillingDetail()
        XCTAssertTrue(subtitle(containing: "计费 · 近 7 天").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["计费明细"].buttons["analytics.filter.button"].exists, app.debugDescription)
        XCTAssertTrue(element("analytics.chart.page").exists, app.debugDescription)
        // The session's totals and trend: shown at once, not read again.
        XCTAssertEqual(billingHead.label, "实际 " + Expected.week)
        for (key, value) in zip(["accountCost", "standardCost", "profit"], Expected.weekFigures) {
            app.waitForValue(element("analytics.body.billing." + key), equal: value)
        }
        XCTAssertTrue(element("analytics.body.billing.chart").exists, app.debugDescription)
        diagnostics("analytics-billing-detail")
        // Every bucket, newest on top, nothing folded on the full page.
        for index in (0...6).reversed() {
            let row = billingDetailRow(index)
            app.scrollUntilExists(row)
            for part in ["，实际 $", "，标准 $", "，请求 "] { XCTAssertTrue(row.label.contains(part), row.label) }
        }
        XCTAssertLessThan(billingDetailRow(1).frame.minY, billingDetailRow(0).frame.minY, app.debugDescription)
        XCTAssertFalse(billingDetailRow(7).exists, app.debugDescription)
        XCTAssertFalse(element("analytics.body.billing.expand").exists, app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(amount.value as? String, Expected.week)
    }

    @MainActor func testBillingDetailHighlightsTheRowOfTheSelectedBar() {
        launch()
        defer { diagnostics("analytics-billing-detail-selection-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        openBillingDetail()
        let bars = billingBars
        XCTAssertEqual(bars.count, 7, app.debugDescription)
        guard bars.count == 7 else { return }
        bars[4].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let row = billingDetailRow(4)
        XCTAssertTrue(row.poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
        XCTAssertEqual(selectedBillingRows.count, 1, app.debugDescription)
        // The head names the row's bucket and its actual charge: “10月14日 周三 · $1,202.04”.
        let parts = row.label.components(separatedBy: "，")
        XCTAssertGreaterThan(parts.count, 1, row.label)
        guard parts.count > 1 else { return }
        app.waitForLabel(billingHead, containing: parts[0] + " · " + parts[1].replacingOccurrences(of: "实际 ", with: ""))
        diagnostics("analytics-billing-detail-selection")
        // The same bar again clears both.
        billingBars[4].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(row.poll(NSPredicate(format: "isSelected == false"), timeout: 5), app.debugDescription)
        XCTAssertEqual(selectedBillingRows.count, 0, app.debugDescription)
        app.waitForLabel(billingHead, containing: "实际 " + Expected.week)
    }

    @MainActor func testChartPageRangeChangeStaysAfterReturning() {
        launch()
        defer { diagnostics("analytics-chart-range-final") }
        app.openAnalyticsFromSearch()
        app.waitForValue(amount, equal: Expected.week)
        openBillingDetail()
        app.selectRangeSegment("30 天")
        XCTAssertTrue(subtitle(containing: "计费 · 近 30 天").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(billingDetailRow(29).waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(billingDetailRow(0))
        XCTAssertFalse(billingDetailRow(30).exists, app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(app.rangeSegment("30 天"), towardBottom: false)
        assertSegmentSelected("30 天")
        app.waitForLabel(amount, containing: "实际扣费 · 近 30 天")
        openBillingDetail()
        XCTAssertTrue(subtitle(containing: "计费 · 近 30 天").waitForExistence(timeout: 10), app.debugDescription)
        assertSegmentSelected("30 天")
    }

    @MainActor func testProfitDetailEndsWithTotalAndNote() {
        launch(["-ui-analytics-loss"])
        defer { diagnostics("analytics-profit-detail-final") }
        app.openAnalyticsFromSearch()
        revealProfitCard()
        app.waitForValue(profitAmount, equal: ProfitExpected.week)
        element("analytics.profit.foot").tap()
        XCTAssertTrue(app.navigationBars["利润明细"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(subtitle(containing: "计费 · 近 7 天").waitForExistence(timeout: 5), app.debugDescription)
        app.waitForLabel(element("analytics.body.profit.head"), containing: "利润 " + ProfitExpected.week)
        app.waitForValue(element("analytics.body.profit.profit"), equal: ProfitExpected.week)
        let lossRow = element("analytics.body.profit.row.5")
        app.scrollUntilExists(lossRow)
        app.waitForLabel(lossRow, containing: "，利润 " + ProfitExpected.loss)
        // 合计 after the oldest row, then the note.
        let total = element("analytics.body.profit.row.total")
        app.scrollUntilExists(total)
        XCTAssertTrue(total.label.hasPrefix("合计，实际 $") && total.label.hasSuffix("，利润 " + ProfitExpected.week), total.label)
        let oldest = element("analytics.body.profit.row.0")
        XCTAssertTrue(oldest.exists && oldest.frame.maxY <= total.frame.minY + 1, app.debugDescription)
        let note = element("analytics.body.profit.note")
        app.scrollUntilExists(note)
        XCTAssertEqual(note.label, "每天的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。")
        diagnostics("analytics-profit-detail")
        // By the hour.
        app.scrollUntilExists(app.rangeSegment("今天"), towardBottom: false)
        app.selectRangeSegment("今天")
        XCTAssertTrue(subtitle(containing: "计费 · 今天").waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(note)
        app.waitForLabel(note, containing: "每小时的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。")
    }
}
