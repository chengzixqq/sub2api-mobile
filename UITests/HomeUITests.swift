import XCTest

/// 10 §1 the overview's regular layout over LiveOpsFixtures (S1-09). Shared by later items (S1-09b, S1-10, S1-11, S1-12, S1-15,
/// S1-18, S4-02, S4-13): the helpers stay at the top, each item appends its own tests and helpers at the end of the class.
final class HomeUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// LiveOpsFixtures' default home as the cells show it (from LiveOpsFixtures.stats / rates; the UI tests cannot import the App,
    /// so change both together).
    private enum Expected {
        static let actualCost = "$1,284.50"
        static let change = "▲8.1%"
        static let requests = "18.2K"
        static let errorRate = "0.8%"
        static let profit = "$772.42"
        static let rpm = "46"
        static let tpm = "240K"
        /// `-ui-home-loss`: account cost $1,400.00.
        static let lossProfit = "\u{2212}$115.50"
        static let kinds = ["actualCost", "requests", "errorRate", "profit", "rpm", "tpm"]
    }

    // MARK: Helpers

    /// Email and password sign-in with `-ui-testing` and `arguments`.
    @MainActor private func launchAndLogin(name: String = "概览站点", url: String = "https://home.example.invalid", arguments: [String] = []) {
        launch(arguments)
        enter(name, in: "login.name")
        enter(url, in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        submit()
    }
    /// The access-token method with a `sat_` key; `-ui-readonly-token` makes it read-only.
    @MainActor private func launchAndLoginWithAccessToken(name: String = "令牌概览", url: String = "https://home-token.example.invalid",
                                                          token: String = "sat_fixture-home", arguments: [String] = []) {
        launch(arguments)
        enter(name, in: "login.name")
        enter(url, in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter(token, in: "login.key")
        submit()
    }
    @MainActor private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func submit() {
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func tickerCell(_ kind: String) -> XCUIElement { element("home.ticker." + kind) }
    /// A cell once the first load filled it (the skeleton is disabled).
    @MainActor private func loadedCell(_ kind: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let cell = tickerCell(kind)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: cell)
        XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        return cell
    }
    /// Any element reading `text`: a banner combines its lines into one element.
    @MainActor private func text(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor @discardableResult
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [shown], timeout: timeout) == .completed
    }
    /// The subtitle under the site name; the title menu's button may read it with the name.
    @MainActor private func subtitle(containing text: String) -> XCUIElement {
        app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func enter(_ value: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(value)
    }
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
    }
    /// The ··· menu; a toolbar menu may expose only its label.
    @MainActor private func openMoreMenu(file: StaticString = #filePath, line: UInt = #line) {
        let byIdentifier = element("home.more")
        let more = byIdentifier.waitForExistence(timeout: 5) ? byIdentifier : app.navigationBars.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        more.tap()
    }
    /// The 开启运维监控？ alert's confirm button, by its title: system alert buttons do not always carry the identifier, and on
    /// iOS 27 the button and its label both answer to it.
    @MainActor private func confirmEnable(file: StaticString = #filePath, line: UInt = #line) {
        let alert = app.alerts["开启运维监控？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        alert.buttons["开启"].firstMatch.tap()
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: S1-09 六格、横幅与提示行

    @MainActor func testTickerShowsSixCellsInFixedOrder() {
        launchAndLogin()
        defer { diagnostics("home-ticker-final") }
        let cells = Expected.kinds.map(tickerCell)
        _ = loadedCell("actualCost")
        XCTAssertTrue(cells.allSatisfy(\.exists), app.debugDescription)
        // 3 × 2: the first three share a row from left to right, the other three sit below.
        let frames = cells.map(\.frame)
        for (row, range) in [(0, 0..<3), (1, 3..<6)] {
            XCTAssertEqual(Set(range.map { frames[$0].minY.rounded() }).count, 1, "row \(row): \(frames)")
            XCTAssertTrue(zip(range.dropLast(), range.dropFirst()).allSatisfy { frames[$0.0].minX < frames[$0.1].minX }, "\(frames)")
        }
        XCTAssertGreaterThan(frames[3].minY, frames[0].minY)
        let values = [Expected.actualCost, Expected.requests, Expected.errorRate, Expected.profit, Expected.rpm, Expected.tpm]
        for (cell, value) in zip(cells, values) { XCTAssertTrue(cell.label.contains(value), cell.label) }
        // The cell shows Expected.change under the amount; the button reads it out in words.
        XCTAssertTrue(cells[0].label.contains("比昨天同时上升 8.1%"), cells[0].label)
        XCTAssertFalse(cells[3].label.contains("+"), cells[3].label)
        for cell in cells.prefix(4) { XCTAssertTrue(cell.label.hasSuffix("打开统计分析"), cell.label) }
        XCTAssertTrue(cells[4].label.hasSuffix("打开 RPM 趋势"), cells[4].label)
        XCTAssertTrue(cells[5].label.hasSuffix("打开 TPM 趋势"), cells[5].label)
        let old = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard."))
        XCTAssertEqual(old.count, 0, app.debugDescription)
    }

    @MainActor func testActualCostCellOpensAnalytics() {
        launchAndLogin()
        defer { diagnostics("home-actual-cost-final") }
        loadedCell("actualCost").tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("home.ticker").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testRPMCellOpensLegacyTrendWithRPMSelected() {
        launchAndLogin()
        defer { diagnostics("home-rpm-final") }
        loadedCell("rpm").tap()
        XCTAssertTrue(element("legacy.trend").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.segmentedControls["dashboard.trend.metric"].buttons["性能指标"].isSelected, app.debugDescription)
        XCTAssertTrue(app.segmentedControls["dashboard.performance.metric"].buttons["RPM"].isSelected, app.debugDescription)
        XCTAssertTrue(element("dashboard.performance.chart").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testSubtitleShowsServerDateAndFreshness() {
        launchAndLogin(name: "副标题站点")
        defer { diagnostics("home-subtitle-final") }
        _ = loadedCell("requests")
        XCTAssertTrue(app.navigationBars["副标题站点"].exists, app.debugDescription)
        // D30: the fixture server is in Asia/Shanghai, the simulator's zone may differ; the date reads “M月d日 周X”.
        let line = subtitle(containing: "刚刚更新")
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(line.label.contains("月") && line.label.contains("日 周"), line.label)
    }

    @MainActor func testUnreachableShowsEmptyStateAndRetryLoads() {
        launchAndLogin(arguments: ["-ui-home-unreachable-once"])
        defer { diagnostics("home-unreachable-final") }
        let empty = element("home.unreachable")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "无法连接到站点").exists, app.debugDescription)
        XCTAssertFalse(element("home.ticker").exists, app.debugDescription)
        diagnostics("home-unreachable")
        element("home.unreachable.retry").tap()
        XCTAssertTrue(waitForLabel(tickerCell("requests"), containing: Expected.requests), app.debugDescription)
        XCTAssertFalse(empty.exists, app.debugDescription)
    }

    @MainActor func testMoreMenuRefreshesAndOpensAnalytics() {
        launchAndLogin(arguments: ["-ui-home-unreachable-once"])
        defer { diagnostics("home-more-final") }
        XCTAssertTrue(element("home.unreachable").waitForExistence(timeout: 10), app.debugDescription)
        // U11: 刷新 reads home again, so the page leaves the empty state.
        openMoreMenu()
        let refresh = app.buttons["刷新"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        refresh.tap()
        XCTAssertTrue(waitForLabel(tickerCell("requests"), containing: Expected.requests), app.debugDescription)
        openMoreMenu()
        let analytics = app.buttons["统计分析"].firstMatch
        XCTAssertTrue(analytics.waitForExistence(timeout: 5), app.debugDescription)
        analytics.tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testOpsDisabledInlineNoticeEnableShowsReceipt() {
        launchAndLogin(arguments: ["-ui-ops-disabled"])
        defer { diagnostics("home-ops-disabled-final") }
        let notice = element("ops.disabled.inline")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        let ticker = element("home.ticker")
        XCTAssertGreaterThanOrEqual(notice.frame.minY, ticker.frame.maxY, "The notice sits right under the six cells.")
        XCTAssertTrue(text(containing: "运维监控未开启 · 错误率与告警不可用，RPM 只计成功请求").exists, app.debugDescription)
        // U12: the cells add no words; 错误率 has no figure.
        XCTAssertFalse(loadedCell("errorRate").label.contains("%"), tickerCell("errorRate").label)
        diagnostics("home-ops-disabled")
        element("ops.disabled.enable").tap()
        confirmEnable()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "已开启运维监控")
        XCTAssertTrue(notice.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testOpsConfigOffNoticeHasNoButton() {
        launchAndLogin(arguments: ["-ui-ops-config-off"])
        defer { diagnostics("home-ops-config-off-final") }
        XCTAssertTrue(element("ops.disabled.inline").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "运维监控已在服务器配置中关闭").exists, app.debugDescription)
        XCTAssertFalse(element("ops.disabled.enable").exists, app.debugDescription)
    }

    /// S1-08's notice under a read-only `sat_` token: 开启 shows but is greyed, with the read-only caption (C-1).
    @MainActor func testOpsEnableIsGatedForReadOnlyToken() {
        launchAndLoginWithAccessToken(arguments: ["-ui-ops-disabled", "-ui-readonly-token"])
        defer { diagnostics("home-ops-readonly-final") }
        let enable = element("ops.disabled.enable")
        XCTAssertTrue(enable.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(enable.isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }

    @MainActor func testAvailabilityErrorKeepsTickerAndMarksPartialUpdate() {
        launchAndLogin(arguments: ["-ui-home-availability-error"])
        defer { diagnostics("home-availability-error-final") }
        let values = [Expected.actualCost, Expected.requests, Expected.errorRate, Expected.profit, Expected.rpm, Expected.tpm]
        for (kind, value) in zip(Expected.kinds, values) {
            XCTAssertTrue(waitForLabel(tickerCell(kind), containing: value), tickerCell(kind).label)
        }
        XCTAssertTrue(subtitle(containing: "部分数据未更新").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testLossFixtureShowsNegativeProfit() {
        launchAndLogin(arguments: ["-ui-home-loss"])
        defer { diagnostics("home-loss-final") }
        let profit = loadedCell("profit")
        XCTAssertTrue(waitForLabel(profit, containing: Expected.lossProfit), profit.label)
        XCTAssertFalse(profit.label.contains("+") || profit.label.contains("-$"), profit.label)
        XCTAssertTrue(tickerCell("actualCost").label.contains(Expected.actualCost), tickerCell("actualCost").label)
    }

    /// R18: a login without a refresh token, above the six cells; an ordinary login has no banner.
    @MainActor func testRenewalBannerAboveTickerWhenRefreshUnavailable() {
        launchAndLogin(arguments: ["-ui-refresh-unavailable"])
        defer { diagnostics("home-renewal-final") }
        let banner = element("home.banner.renewal")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(banner.label.contains("本次登录无法自动续期") && banner.label.contains("后需要重新登录"), banner.label)
        let ticker = element("home.ticker")
        XCTAssertTrue(ticker.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(banner.frame.maxY, ticker.frame.minY, "The banner sits above the six cells.")
        diagnostics("home-renewal")
        app.terminate()
        launchAndLogin()
        XCTAssertTrue(loadedCell("requests").exists)
        XCTAssertFalse(element("home.banner.renewal").exists, app.debugDescription)
    }

    @MainActor func testTickerFitsAtAccessibilityTextSize() {
        launchAndLogin(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { diagnostics("home-ticker-accessibility-text") }
        _ = loadedCell("actualCost")
        let window = app.windows.firstMatch.frame
        let cells = Expected.kinds.map(tickerCell)
        for cell in cells {
            XCTAssertTrue(cell.exists, app.debugDescription)
            XCTAssertGreaterThan(cell.frame.width, 0)
            XCTAssertLessThanOrEqual(cell.frame.maxX, window.maxX + 1, "\(cell.identifier) \(cell.frame)")
        }
        // Two columns: 今日实际扣费 and 请求 share the first row, 错误率 starts the next.
        XCTAssertEqual(cells[0].frame.minY.rounded(), cells[1].frame.minY.rounded(), "\(cells[0].frame) \(cells[1].frame)")
        XCTAssertGreaterThan(cells[2].frame.minY, cells[0].frame.minY, "\(cells[2].frame)")
        XCTAssertTrue(cells[0].label.contains(Expected.actualCost), cells[0].label)
    }

    @MainActor func testFirstLoadShowsSkeletonNotZero() {
        launchAndLogin(arguments: ["-ui-home-pending"])
        defer { diagnostics("home-skeleton-final") }
        let cell = tickerCell("actualCost")
        XCTAssertTrue(cell.waitForExistence(timeout: 10), app.debugDescription)
        for kind in Expected.kinds {
            let skeleton = tickerCell(kind)
            XCTAssertEqual(skeleton.value as? String, "正在加载", skeleton.debugDescription)
            XCTAssertFalse(skeleton.label.contains("$0") || skeleton.label.contains("无数据"), skeleton.label)
        }
        XCTAssertTrue(subtitle(containing: "正在加载…").exists, app.debugDescription)
        XCTAssertFalse(element("home.unreachable").exists)
    }

    /// 10 §1.2 rates fallback ③ (no dashboard.home or dashboard.rates, monitoring off): TPM excludes cache tokens, marked * and
    /// explained in the notice.
    @MainActor func testLegacyRatesMarkTPMAndExplainInNotice() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "dashboard.home,dashboard.rates", "-ui-ops-disabled"])
        defer { diagnostics("home-legacy-rates-final") }
        XCTAssertTrue(waitForLabel(tickerCell("tpm"), containing: "不含缓存 Tokens"), tickerCell("tpm").label)
        XCTAssertTrue(text(containing: "TPM 不含缓存 Tokens").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §1.5 on the fallback, where each block lands on its own (S1-07): the rates cells fill in while today's figures are still on
    /// their way, and those stay the skeleton, never “—” read as 无数据.
    @MainActor func testFallbackKeepsCellsOfAPendingBlockAsSkeleton() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "dashboard.home", "-ui-home-stats-pending"])
        defer { diagnostics("home-fallback-stats-pending-final") }
        XCTAssertTrue(loadedCell("rpm").label.contains(Expected.rpm), tickerCell("rpm").label)
        XCTAssertTrue(tickerCell("errorRate").label.contains(Expected.errorRate), tickerCell("errorRate").label)
        for kind in ["actualCost", "requests", "profit"] {
            let skeleton = tickerCell(kind)
            XCTAssertEqual(skeleton.value as? String, "正在加载", skeleton.debugDescription)
            XCTAssertFalse(skeleton.isEnabled, skeleton.debugDescription)
            XCTAssertFalse(skeleton.label.contains("无数据"), skeleton.label)
        }
    }

    // MARK: S1-09b 今日区与运行区

    /// LiveOpsFixtures' default home in the today and run sections (from LiveOpsFixtures.stats / opsOverview / home; change both
    /// together). Values as VoiceOver reads them.
    private enum TodayExpected {
        static let chartLabel = "每小时实际扣费，今天与昨天对比"
        static let figures = [("accountCost", "$512.08"), ("standardCost", "$1,610.14"), ("profit", "$772.42"), ("tokens", "96.4M"),
                              ("successRate", "99.2%")]
        static let health = "94，良好"
        static let rates = [("errorRate", "0.8%"), ("upstream429", "12"), ("upstream529", "3")]
        static let channels = "可用 7 · 性能下降 1 · 不可用 1 · 未知 1"
        static let missing = "无数据"
    }

    @MainActor private func todayFigure(_ kind: String) -> XCUIElement { element("home.today." + kind) }
    @MainActor private func assertValue(_ item: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(item, file: file, line: line)
        XCTAssertEqual(item.value as? String, value, item.debugDescription, file: file, line: line)
    }

    @MainActor func testHomeTodaySectionShowsChartCellsAndSuccessRate() {
        launchAndLogin()
        defer { diagnostics("home-today-final") }
        _ = loadedCell("actualCost")
        let header = element("home.today.header")
        reveal(header)
        XCTAssertEqual(header.label, "今日")
        XCTAssertEqual(header.value as? String, "00:00 起")
        let chart = element("home.today.chart")
        reveal(chart)
        XCTAssertEqual(chart.label, TodayExpected.chartLabel)
        for (kind, value) in TodayExpected.figures { assertValue(todayFigure(kind), value) }
        diagnostics("home-today")
        let more = element("home.today.more")
        reveal(more)
        // 今日 sits above 运行.
        let run = element("home.run.header")
        reveal(run)
        XCTAssertEqual(run.label, "运行")
        if more.exists { XCTAssertLessThanOrEqual(more.frame.maxY, run.frame.minY, "\(more.frame) \(run.frame)") }
    }

    /// 10 §1.3.4: hourly timed out, so only the chart has its failure row; the cells under it, the six cells and 运行 stay.
    @MainActor func testHomeHourlyTimeoutOnlyAffectsChart() {
        launchAndLogin(arguments: ["-ui-home-hourly-timeout"])
        defer { diagnostics("home-hourly-timeout-final") }
        let values = [Expected.actualCost, Expected.requests, Expected.errorRate, Expected.profit, Expected.rpm, Expected.tpm]
        for (kind, value) in zip(Expected.kinds, values) {
            XCTAssertTrue(waitForLabel(tickerCell(kind), containing: value), tickerCell(kind).label)
        }
        let failed = element("home.today.hourly.failed")
        reveal(failed)
        XCTAssertTrue(text(containing: "每小时数据加载失败").exists, app.debugDescription)
        XCTAssertTrue(element("home.today.hourly.retry").exists, app.debugDescription)
        XCTAssertFalse(element("home.today.chart").exists, app.debugDescription)
        diagnostics("home-hourly-timeout")
        for (kind, value) in TodayExpected.figures where ["accountCost", "tokens", "successRate"].contains(kind) {
            assertValue(todayFigure(kind), value)
        }
        assertValue(element("home.run.health"), TodayExpected.health)
    }

    @MainActor func testHomeMoreStatsOpensAnalytics() {
        launchAndLogin()
        defer { diagnostics("home-more-stats-final") }
        _ = loadedCell("actualCost")
        let more = element("home.today.more")
        reveal(more)
        XCTAssertTrue(more.label.contains("更多统计") && more.label.contains("模型 · 用户 · 分组排行"), more.label)
        more.tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testHomeRunSectionShowsHealthErrorRateAndUpstreamCounts() {
        launchAndLogin()
        defer { diagnostics("home-run-final") }
        _ = loadedCell("actualCost")
        let health = element("home.run.health")
        assertValue(health, TodayExpected.health)
        XCTAssertEqual(health.label, "健康分")
        for (kind, value) in TodayExpected.rates { assertValue(element("home.run." + kind), value) }
        XCTAssertEqual(element("home.run.upstream529").label, "上游 529")
        XCTAssertFalse(element("home.run.health.failed").exists, app.debugDescription)
        diagnostics("home-run")
    }

    /// 10 §1.1: the channel row switches to 监控 · 渠道 (the stage-0 placeholder segment until S1-15).
    @MainActor func testHomeChannelRowSelectsMonitorChannelsSegment() {
        launchAndLogin()
        defer { diagnostics("home-channels-final") }
        _ = loadedCell("actualCost")
        let channels = element("home.run.channels")
        assertValue(channels, TodayExpected.channels)
        channels.tap()
        let monitorTab = app.tabBars.buttons["监控"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: monitorTab)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 10), .completed, app.debugDescription)
        let segment = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment.buttons["渠道"].isSelected, app.debugDescription)
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(element("home.regular").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §1.3.5 and appendix B L23 with ops monitoring off: 健康分 “—” with 运维监控未开启, the rates and 成功率 “—” (never 0 or
    /// 100%); the chart and the other cells stay.
    @MainActor func testHomeOpsDisabledRunSectionAndSuccessRate() {
        launchAndLogin(arguments: ["-ui-ops-disabled"])
        defer { diagnostics("home-ops-disabled-run-final") }
        XCTAssertTrue(element("ops.disabled.inline").waitForExistence(timeout: 10), app.debugDescription)
        reveal(element("home.today.chart"))
        assertValue(todayFigure("accountCost"), "$512.08")
        assertValue(todayFigure("successRate"), TodayExpected.missing)
        assertValue(element("home.run.health"), TodayExpected.missing + "，运维监控未开启")
        for (kind, _) in TodayExpected.rates { assertValue(element("home.run." + kind), TodayExpected.missing) }
        diagnostics("home-ops-disabled-run")
    }

    /// 10 §1.5, §0.5: only the rates block timed out before any value, so 错误率 / 上游 429 / 529 read “—” over one “加载超时 · 重试”
    /// line in 运行 (the six cells' 错误率 / RPM / TPM come from the same block); 健康分, 渠道 and today's figures stay.
    @MainActor func testHomeRatesTimeoutShowsTimedOutRowInRunSection() {
        launchAndLogin(arguments: ["-ui-home-rates-timeout"])
        defer { diagnostics("home-rates-timeout-final") }
        _ = loadedCell("actualCost")
        XCTAssertTrue(waitForLabel(tickerCell("errorRate"), containing: TodayExpected.missing), tickerCell("errorRate").label)
        reveal(element("home.run.rates.failed"))
        XCTAssertTrue(text(containing: "加载超时").exists, app.debugDescription)
        XCTAssertTrue(element("home.run.rates.retry").exists, app.debugDescription)
        for (kind, _) in TodayExpected.rates { assertValue(element("home.run." + kind), TodayExpected.missing) }
        diagnostics("home-rates-timeout")
        assertValue(element("home.run.health"), TodayExpected.health)
        assertValue(element("home.run.channels"), TodayExpected.channels)
        assertValue(todayFigure("accountCost"), "$512.08")
    }
}
