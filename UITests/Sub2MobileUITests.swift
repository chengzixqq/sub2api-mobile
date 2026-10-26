import XCTest

final class Sub2MobileUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    @MainActor func testLoginRequiresHTTPSAndCredentials() {
        launch()
        submitLogin()
        XCTAssertTrue(app.staticTexts["login.error"].exists)
        enter("测试站点", in: app.textFields["login.name"], towardBottom: false)
        enter("http://example.com", in: app.textFields["login.url"])
        submitLogin()
        XCTAssertTrue(app.staticTexts["login.error"].label.contains("HTTPS"))
    }

    @MainActor func testLoginDashboardAccountPaginationAndDetails() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        XCTAssertTrue(app.otherElements["dashboard.metrics"].waitForExistence(timeout: 10) || app.staticTexts["今日请求"].exists)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        app.buttons["accounts.more"].tap()
        XCTAssertTrue(app.buttons["account.2"].waitForExistence(timeout: 10))
        app.buttons["account.1"].tap()
        reveal(app.buttons["account.test"])
        app.buttons["account.test"].tap()
        XCTAssertTrue(app.buttons["account.test.start"].waitForExistence(timeout: 5))
        // Opening the screen never launches a test or performs a server write.
        XCTAssertFalse(app.staticTexts["测试成功"].exists)
    }

    @MainActor func testUserPaginationAndMaskedKeys() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        app.buttons["users.more"].tap()
        XCTAssertTrue(app.buttons["user.2"].waitForExistence(timeout: 10))
        app.buttons["user.1"].tap()
        reveal(app.staticTexts["开发密钥"])
        XCTAssertTrue(app.staticTexts["••••••••cret"].exists)
        XCTAssertFalse(app.staticTexts["sk-fixture-secret"].exists)
        reveal(app.buttons["user.balance"])
    }

    @MainActor func testDashboardCountersSurviveDetailTimeouts() {
        launch(arguments: ["-ui-dashboard-detail-errors"])
        login(name: "慢统计站点", url: "https://slow.example.com")
        let counter = app.descendants(matching: .any)["dashboard.today-requests"].firstMatch
        let counterExists = counter.waitForExistence(timeout: 10)
        if !counterExists {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(counterExists, app.debugDescription)
        // Both detail requests start automatically; either local failure must
        // leave the successful counters and the other section available.
        XCTAssertTrue(app.staticTexts["dashboard.trend.error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dashboard.monitoring.error"].waitForExistence(timeout: 10))
        reveal(counter, towardBottom: false)
        XCTAssertTrue(counter.exists)
        reveal(app.buttons["dashboard.trend.load"])
        app.buttons["dashboard.trend.load"].tap()
        XCTAssertTrue(app.staticTexts["dashboard.trend.error"].waitForExistence(timeout: 5))
        reveal(app.buttons["dashboard.monitoring.load"])
        app.buttons["dashboard.monitoring.load"].tap()
        XCTAssertTrue(app.staticTexts["dashboard.monitoring.error"].waitForExistence(timeout: 5))
        app.tabBars.buttons["账号"].tap()
        app.tabBars.buttons["概览"].tap()
        reveal(counter, towardBottom: false)
        XCTAssertTrue(counter.exists)
    }

    @MainActor func testDashboardAutomaticallyLoadsAllSections() {
        launch()
        defer { dashboardDiagnostics(named: "dashboard-automatic-sections") }
        login(name: "分区自动加载验收", url: "https://automatic.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.monitoring.qps"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.monitoring.qps", contains: ["0.2"])
        assertDashboardValue("dashboard.monitoring.active-requests", contains: ["2"])
        assertDashboardValue("dashboard.monitoring.error-rate", contains: ["1.0%"])
    }

    @MainActor func testDashboardSlowTrendDoesNotDelayCountersOrMonitoring() {
        launch(arguments: ["-ui-dashboard-slow-trend"])
        defer { dashboardDiagnostics(named: "dashboard-independent-slow-trend-final") }
        login(name: "分区独立加载验收", url: "https://independent.example.com")
        let counter = app.descendants(matching: .any)["dashboard.today-requests"].firstMatch
        let qps = app.descendants(matching: .any)["dashboard.monitoring.qps"].firstMatch
        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(qps.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(chart.exists, "A pending trend must not delay successful stats and monitoring.")
        dashboardDiagnostics(named: "dashboard-independent-sections-before-trend")
        XCTAssertTrue(chart.waitForExistence(timeout: 12), app.debugDescription)
        reveal(chart)
        dashboardDiagnostics(named: "dashboard-independent-trend-arrived")
    }

    @MainActor func testDashboardShowsActualAndAccountCostsTokensPerformanceAndDates() {
        launch()
        defer { dashboardDiagnostics(named: "dashboard-final-state") }
        login(name: "概览显示验收", url: "https://dashboard.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)

        assertDashboardValue("dashboard.today-requests", contains: ["128"])
        let totalRequests = assertDashboardValue("dashboard.total-requests", contains: ["总计"])
        XCTAssertTrue(totalRequests.replacingOccurrences(of: ",", with: "").contains("213009545"), totalRequests)
        assertDashboardValue("dashboard.today-tokens", contains: ["1.2M"])
        let actual = assertDashboardValue("dashboard.today-actual-cost", contains: ["今日实际费用", "$12.34"])
        let account = assertDashboardValue("dashboard.today-account-cost", contains: ["今日上游成本", "$4.56"])
        // Distinct fixture prices catch accidentally displaying standard cost.
        XCTAssertFalse(actual.contains("99.99"))
        XCTAssertFalse(account.contains("99.99"))
        assertDashboardValue("dashboard.total-tokens", contains: ["9.9B"])
        assertDashboardValue("dashboard.total-actual-cost", contains: ["累计实际费用", "$1.23K"])
        assertDashboardValue("dashboard.total-account-cost", contains: ["累计上游成本", "$456.78"])
        dashboardDiagnostics(named: "dashboard-compact-tokens-and-real-costs")

        assertDashboardValue("dashboard.performance.rpm", contains: ["1,234", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.7K", "TPM"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.3s"])
        dashboardDiagnostics(named: "dashboard-performance-units")

        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        // Runtime health now follows the chart, so return upward after reading
        // its average response time rather than continuing below the chart.
        reveal(chart, towardBottom: false)
        XCTAssertGreaterThan(chart.frame.height, 100)
        assertDashboardValue("dashboard.trend.range", contains: ["10/14", "22:00", "10/15", "02:00"])
        // Keep the rendered chart and AX tree: the cross-day tick spacing is
        // reviewed from the screenshot rather than inferred from an AX label.
        dashboardDiagnostics(named: "dashboard-cross-day-trend-axis")
    }

    @MainActor func testDashboardPerformanceCardAndHealthContainTheirMetrics() {
        launch()
        defer { dashboardDiagnostics(named: "dashboard-performance-card-and-health-final") }
        login(name: "性能卡与健康验收", url: "https://health.example.com")
        let metrics = app.descendants(matching: .any)["dashboard.metrics"].firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: 10), app.debugDescription)
        let performance = metrics.descendants(matching: .any)["dashboard.performance.card"].firstMatch
        XCTAssertTrue(performance.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(performance.isHittable, "The combined performance card should be visible before scrolling.")
        XCTAssertTrue(performance.descendants(matching: .any)["dashboard.performance.rpm"].firstMatch.exists)
        XCTAssertTrue(performance.descendants(matching: .any)["dashboard.performance.tpm"].firstMatch.exists)
        assertSummaryCardsHaveEqualHeights(maximumHeight: 116)
        assertEmbeddedSummaryFootersFit(diagnosticSuffix: "standard")
        assertDashboardValue("dashboard.performance.rpm", contains: ["1,234", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.7K", "TPM"])
        dashboardDiagnostics(named: "dashboard-top-performance-card")

        let health = app.descendants(matching: .any)["dashboard.health"].firstMatch
        reveal(health)
        let trend = app.descendants(matching: .any)["dashboard.trend.section"].firstMatch
        XCTAssertTrue(trend.exists, app.debugDescription)
        // Read both frames after scrolling: they must share the same viewport.
        XCTAssertLessThan(trend.frame.minY, health.frame.minY, "Usage trend should precede runtime health.")
        XCTAssertTrue(health.descendants(matching: .any)["dashboard.health.errors"].firstMatch.exists)
        XCTAssertTrue(health.descendants(matching: .any)["dashboard.performance.duration"].firstMatch.exists)
        assertDashboardValue("dashboard.health.errors", contains: ["1"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.3s"])
        dashboardDiagnostics(named: "dashboard-running-health")
    }

    @MainActor func testDashboardSummaryCardsRemainEqualAtAccessibilityTextSize() {
        launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { dashboardDiagnostics(named: "dashboard-equal-cards-accessibility-text") }
        login(name: "大字体等高验收", url: "https://large-text.example.com")
        assertSummaryCardsHaveEqualHeights()
        assertEmbeddedSummaryFootersFit(diagnosticSuffix: "accessibility-text")
    }

    @MainActor func testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection() {
        launch(arguments: ["-ui-trend-long-series"])
        defer { dashboardDiagnostics(named: "dashboard-trend-interaction-final") }
        login(name: "趋势交互验收", url: "https://trend.example.com")
        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        let metric = app.segmentedControls["dashboard.trend.metric"]
        reveal(metric)
        XCTAssertTrue(metric.buttons["实际消费"].isSelected, "Actual consumption should be the initial trend metric.")

        let zoomIn = app.buttons["dashboard.trend.zoom-in"]
        reveal(zoomIn)
        zoomIn.waitUntilSettled()
        let initialZoom = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch.label
        let visibleRange = app.descendants(matching: .any)["dashboard.trend.visible-range"].firstMatch
        let anchoredStart = visibleRange.label.components(separatedBy: " — ").first
        for step in 0..<4 {
            if !zoomIn.isEnabled { break }
            let beforeZoom = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch.label
            zoomIn.tap()
            let zoomLabel = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", beforeZoom), object: zoomLabel)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
            XCTAssertEqual(visibleRange.label.components(separatedBy: " — ").first, anchoredStart,
                           "Zooming in should hold the left time boundary instead of panning to the old center.")
            if step == 2 {
                reveal(chart)
                dashboardDiagnostics(named: "dashboard-trend-readable-labels-before-maximum")
                revealTrendZoomControl(zoomIn)
            }
        }
        XCTAssertFalse(zoomIn.isEnabled, "Zoom should reach its bounded maximum.")
        let maximumZoom = assertDashboardValue("dashboard.trend.zoom-level", contains: ["放大"])
        XCTAssertNotEqual(maximumZoom, initialZoom)
        reveal(chart)
        dashboardDiagnostics(named: "dashboard-trend-max-zoom-actual-consumption")

        reveal(visibleRange)
        chart.waitUntilSettled()
        let beforeScroll = visibleRange.label
        chart.swipeLeft()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", beforeScroll), object: visibleRange)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed, app.debugDescription)
        let afterScroll = visibleRange.label
        chart.swipeRight()
        let reversed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", afterScroll), object: visibleRange)
        XCTAssertEqual(XCTWaiter.wait(for: [reversed], timeout: 5), .completed, app.debugDescription)
        dashboardDiagnostics(named: "dashboard-trend-horizontal-navigation")

        reveal(chart)
        chart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.trend.selection"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        assertDashboardValue("dashboard.trend.selection", contains: ["实际消费", "$"])
        dashboardDiagnostics(named: "dashboard-trend-chart-tap-selection")

        selectNewestTrendHour(contains: ["$0.14"], diagnosticName: "dashboard-trend-amount-details-two-digits")
        let actual = assertDashboardValue("dashboard.trend.selection", contains: ["10/15", "11:00", "$0.14"])
        XCTAssertFalse(actual.contains("0.10000001"), "Displayed amounts should use at most two fraction digits.")
        XCTAssertFalse(actual.contains("9.10"), "Selected consumption must not use standard cost.")
        dashboardDiagnostics(named: "dashboard-trend-exact-actual-selection")

        reveal(metric, towardBottom: false)
        metric.buttons["Tokens"].tap()
        XCTAssertTrue(metric.buttons["Tokens"].isSelected)
        selectNewestTrendHour(contains: ["1.4M", "Tokens"], diagnosticName: "dashboard-trend-token-details-compact")
        let tokens = assertDashboardValue("dashboard.trend.selection", contains: ["Tokens", "1.4M"])
        XCTAssertFalse(tokens.replacingOccurrences(of: ",", with: "").contains("1000000"), "Selected Tokens should use K/M/B units.")
        dashboardDiagnostics(named: "dashboard-trend-exact-token-selection")

        reveal(metric, towardBottom: false)
        metric.buttons["请求数"].tap()
        XCTAssertTrue(metric.buttons["请求数"].isSelected)
        selectNewestTrendHour()
        assertDashboardValue("dashboard.trend.selection", contains: ["请求数", "205 次"])
        dashboardDiagnostics(named: "dashboard-trend-exact-request-selection")

        let zoomOut = app.buttons["dashboard.trend.zoom-out"]
        revealTrendZoomControl(zoomOut)
        let priorZoom = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch.label
        zoomOut.tap()
        let zoomLevel = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch
        let zoomedOut = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", priorZoom), object: zoomLevel)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomedOut], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(zoomIn.isEnabled)
        dashboardDiagnostics(named: "dashboard-trend-zoomed-out")

        reveal(chart, towardBottom: false)
        let priorPinch = zoomLevel.label
        chart.pinch(withScale: 0.6, velocity: -1)
        let pinched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", priorPinch), object: zoomLevel)
        XCTAssertEqual(XCTWaiter.wait(for: [pinched], timeout: 5), .completed, app.debugDescription)
        dashboardDiagnostics(named: "dashboard-trend-pinch-zoom")
    }

    @MainActor func testDashboardMissingAccountCostLoadsIndependentSnapshot() {
        launch(arguments: ["-ui-missing-account-cost"])
        defer { dashboardDiagnostics(named: "dashboard-cost-snapshot-success") }
        login(name: "旧版费用接口", url: "https://legacy-cost.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.today-tokens", contains: ["1.2M"])
        assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        let account = app.descendants(matching: .any)["dashboard.today-account-cost"].firstMatch
        reveal(account)
        let snapshotReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "$4.56", "$4.56"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [snapshotReady], timeout: 10), .completed, app.debugDescription)
        let accountText = assertDashboardValue("dashboard.today-account-cost", contains: ["$4.56"])
        XCTAssertFalse(accountText.contains("99.99"))
        assertDashboardValue("dashboard.total-actual-cost", contains: ["$1.23K"])
        assertDashboardValue("dashboard.total-account-cost", contains: ["$456.78"])
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.costs.error"].firstMatch.exists)
        dashboardDiagnostics(named: "dashboard-cost-snapshot-amounts")
        assertDashboardValue("dashboard.performance.duration", contains: ["1.3s"])
    }

    @MainActor func testDashboardCostSnapshotFailureKeepsPrimaryStatsAndRetryLocal() {
        launch(arguments: ["-ui-missing-account-cost", "-ui-cost-snapshot-error"])
        defer { dashboardDiagnostics(named: "dashboard-cost-snapshot-local-error") }
        login(name: "费用快照超时", url: "https://cost-timeout.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.today-tokens", contains: ["1.2M"])
        let actual = assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        let unavailable = assertDashboardValue("dashboard.today-account-cost", contains: ["—"])
        XCTAssertFalse(actual.contains("99.99"))
        XCTAssertFalse(unavailable.contains("99.99"))
        let error = app.descendants(matching: .any)["dashboard.costs.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.costs.error", contains: ["费用快照超时"])
        dashboardDiagnostics(named: "dashboard-cost-snapshot-before-retry")

        let retry = app.buttons["dashboard.costs.load"]
        reveal(retry)
        XCTAssertTrue(retry.isEnabled)
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.costs.error", contains: ["费用快照超时"])
        assertDashboardValue("dashboard.performance.rpm", contains: ["1,234", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.7K", "TPM"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.3s"])
        assertDashboardValue("dashboard.today-tokens", contains: ["1.2M"], towardBottom: false)
        assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        assertDashboardValue("dashboard.today-account-cost", contains: ["—"])
        assertDashboardValue("dashboard.total-actual-cost", contains: ["$1.23K"])
        assertDashboardValue("dashboard.total-account-cost", contains: ["—"])
        XCTAssertFalse(app.alerts["操作未完成"].exists)
    }

    @MainActor func testPerformanceTrendFourthTabShowsRealRatesAndNewestDetails() {
        launch(arguments: ["-ui-dashboard-detail-errors"])
        login(name: "性能趋势验收", url: "https://performance.example.com")
        XCTAssertTrue(app.staticTexts["dashboard.trend.error"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.performance.chart"].firstMatch.exists,
                       "Historical performance loads only after selecting its tab.")
        let tabs = app.segmentedControls["dashboard.trend.metric"]
        reveal(tabs)
        XCTAssertEqual(tabs.buttons.count, 4)
        tabs.buttons["性能指标"].tap()
        let chart = app.descendants(matching: .any)["dashboard.performance.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        reveal(chart)
        dashboardDiagnostics(named: "performance-trend-rpm")
        let selector = app.segmentedControls["dashboard.performance.metric"]
        reveal(selector, towardBottom: false)
        selector.buttons["TPM"].tap()
        XCTAssertTrue(selector.buttons["TPM"].isSelected)
        reveal(app.buttons["dashboard.performance.details"])
        app.buttons["dashboard.performance.details"].tap()
        let latest = app.buttons["dashboard.performance.row.69"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.performance.row.")).firstMatch.identifier,
                       latest.identifier)
        XCTAssertTrue(latest.label.contains("RPM 69"), latest.label)
        XCTAssertTrue(latest.label.contains("TPM 690K"), latest.label)
        dashboardDiagnostics(named: "performance-trend-newest-details")
        latest.tap()
        assertDashboardValue("dashboard.performance.selection", contains: ["TPM", "690K"])
        let ranges = app.segmentedControls["dashboard.performance.range"]
        reveal(ranges, towardBottom: false)
        ranges.buttons["近 6 小时"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "每桶 5 分钟平均速率")).firstMatch.waitForExistence(timeout: 5))
        dashboardDiagnostics(named: "performance-trend-six-hours")
    }

    @MainActor func testPerformanceDisabledKeepsOtherOverviewMetrics() {
        launch(arguments: ["-ui-performance-error"])
        login(name: "未开启性能监控", url: "https://disabled.example.com")
        let tabs = app.segmentedControls["dashboard.trend.metric"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        reveal(tabs)
        tabs.buttons["性能指标"].tap()
        XCTAssertTrue(app.staticTexts["dashboard.performance.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.performance.chart"].firstMatch.exists)
        dashboardDiagnostics(named: "performance-trend-disabled")
        reveal(tabs, towardBottom: false)
        tabs.buttons["实际消费"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch.waitForExistence(timeout: 5))
        assertDashboardValue("dashboard.today-requests", contains: ["128"], towardBottom: false)
    }

    @MainActor func testAddAndSwitchStations() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        login(name: "站点 B", url: "https://b.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.站点 A"].tap()
        // 10 §0.7-5: the switch ends with a receipt that outlives the rebuilt tabs.
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(receipt.label, "已切换到 站点 A")
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10))
    }

    @MainActor func testSameStationKeepsNewLoginAsSeparateIdentity() {
        launch()
        login(name: "管理员 A", url: "https://same.example.com")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        login(name: "管理员 B", url: "https://same.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.管理员 A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.site.管理员 B"].exists)
    }

    @MainActor func testLogoutErasesCredentialInsteadOfRestoringSession() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        // S0-15: the row now reads like the dialog's button, so the button is told apart by its missing identifier.
        reveal(app.buttons["settings.logout"])
        app.buttons["settings.logout"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "退出并清除凭据", "settings.logout")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        reveal(app.buttons["login.saved.站点 A"])
        app.buttons["login.saved.站点 A"].tap()
        // The site's own login page, prefilled, instead of an error alert (00 §1.1).
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["login.notice"].label, "此站点凭据已清除，请重新登录。")
        XCTAssertEqual(app.textFields["login.name"].value as? String, "站点 A")
        XCTAssertEqual(app.textFields["login.url"].value as? String, "https://a.example.com")
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
        // Signing in again keeps the same site instead of adding a second “站点 A”.
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        submitLogin()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "settings.site.站点 A").count, 1)
    }

    @MainActor func testRemovingActiveStationReturnsToLoginWithoutIt() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.more.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.more.站点 A"].tap()
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        // The confirmation dialog repeats the action as its destructive button.
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["login.saved.站点 A"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
    }

    @MainActor func testRevokedSessionReturnsToPrefilledLogin() {
        launch(arguments: ["-ui-session-revoked"])
        login(name: "失效站点", url: "https://revoked.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["login.notice"].label, "登录已失效，请重新登录")
        XCTAssertEqual(app.textFields["login.url"].value as? String, "https://revoked.example.com")
        // The original sign-in method stays selected (00 §1.7.4).
        XCTAssertTrue(app.textFields["login.email"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
    }

    @MainActor func testBackgroundAndForegroundKeepsSession() {
        launch(arguments: ["-ui-count-user-loads"])
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        let loads = app.descendants(matching: .any)["user.1.field.username"].firstMatch
        XCTAssertTrue(loads.waitForExistence(timeout: 10), app.debugDescription)
        let before = loads.label
        XCTAssertTrue(before.contains("读取 "), before)
        XCUIDevice.shared.press(.home)
        app.activate()
        // Returning reloads the list (D18): the fixture's read count moves on, and the session is still connected.
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 15))
        let reloaded = NSPredicate(format: "label CONTAINS %@ AND label != %@", "读取 ", before)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: reloaded, evaluatedWith: loads)], timeout: 15), .completed, loads.label)
        XCTAssertFalse(app.buttons["login.submit"].exists)
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 15))
    }

    /// D17 on the balance sheet: only the administrator who sent a pending write may retry its number.
    @MainActor func testPendingBalanceRetryFollowsTheSender() {
        for (argument, retries, note) in [(nil, true, nil), ("-ui-pending-actor-unknown", true, "balance.retry.actor-unknown"),
                                          ("-ui-pending-other-actor", false, "balance.retry.other-actor")] as [(String?, Bool, String?)] {
            launch(arguments: ["-ui-pending-money"] + (argument.map { [$0] } ?? []))
            login(name: "站点 A", url: "https://a.example.com")
            app.tabBars.buttons["用户"].tap()
            XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
            app.buttons["user.1"].tap()
            reveal(app.buttons["user.balance"])
            app.buttons["user.balance"].tap()
            let retry = app.buttons["balance.retry"]
            let other = app.descendants(matching: .any)["balance.retry.other-actor"].firstMatch
            XCTAssertTrue(retry.waitForExistence(timeout: 5) || other.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertEqual(retry.exists, retries, (argument ?? "same sender") + "\n" + app.debugDescription)
            for identifier in ["balance.retry.actor-unknown", "balance.retry.other-actor"] {
                XCTAssertEqual(app.descendants(matching: .any)[identifier].firstMatch.exists, identifier == note, identifier)
            }
            app.terminate()
        }
    }

    @MainActor private func login(name: String, url: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter(name, in: app.textFields["login.name"], towardBottom: false)
        enter(url, in: app.textFields["login.url"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        submitLogin()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }

    @MainActor private func assertSummaryCardsHaveEqualHeights(maximumHeight: CGFloat? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let identifiers = [
            "dashboard.today-requests", "dashboard.today-tokens", "dashboard.total-tokens", "dashboard.performance.card"
        ]
        var heights: [CGFloat] = []
        for identifier in identifiers {
            let card = app.descendants(matching: .any)[identifier].firstMatch
            reveal(card, file: file, line: line)
            XCTAssertGreaterThan(card.frame.height, 0, identifier, file: file, line: line)
            heights.append(card.frame.height)
        }
        let shortest = heights.min() ?? 0
        let tallest = heights.max() ?? 0
        if let maximumHeight {
            XCTAssertLessThanOrEqual(tallest, maximumHeight, "Standard summary cards should stay compact.", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(tallest - shortest, 1, "All four cards should have equal heights: \(zip(identifiers, heights).map { "\($0.0)=\($0.1)" }.joined(separator: ", "))", file: file, line: line)
        let attachment = XCTAttachment(string: zip(identifiers, heights).map { "\($0.0)=\($0.1)" }.joined(separator: "\n"))
        attachment.name = "dashboard-summary-card-heights"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func assertEmbeddedSummaryFootersFit(diagnosticSuffix: String, file: StaticString = #filePath, line: UInt = #line) {
        let footers: [(card: String, footer: String, values: [String])] = [
            ("dashboard.today-requests", "dashboard.total-requests", ["dashboard.total-requests"]),
            ("dashboard.today-tokens", "dashboard.today-costs", ["dashboard.today-actual-cost", "dashboard.today-account-cost"]),
            ("dashboard.total-tokens", "dashboard.total-costs", ["dashboard.total-actual-cost", "dashboard.total-account-cost"])
        ]
        let expectedValues = [
            "dashboard.total-requests": ["总计", "213009545"],
            "dashboard.today-actual-cost": ["今日实际费用", "$12.34"],
            "dashboard.today-account-cost": ["今日上游成本", "$4.56"],
            "dashboard.total-actual-cost": ["累计实际费用", "$1.23K"],
            "dashboard.total-account-cost": ["累计上游成本", "$456.78"]
        ]
        for specification in footers {
            let card = app.descendants(matching: .any)[specification.card].firstMatch
            revealSummaryCardFully(card, file: file, line: line)
            let footer = card.descendants(matching: .any)[specification.footer].firstMatch
            XCTAssertTrue(footer.exists, "Footer must be embedded in \(specification.card)", file: file, line: line)
            assertFrame(footer, fitsInside: card, file: file, line: line)
            for identifier in specification.values {
                let value = identifier == specification.footer ? footer : footer.descendants(matching: .any)[identifier].firstMatch
                XCTAssertTrue(value.exists, "Missing footer value \(identifier)", file: file, line: line)
                assertFrame(value, fitsInside: footer, file: file, line: line)
                assertFrame(value, fitsInside: card, file: file, line: line)
                let text = (value.label + " " + (value.value as? String ?? "")).replacingOccurrences(of: ",", with: "")
                for expected in expectedValues[identifier] ?? [] {
                    XCTAssertTrue(text.contains(expected), "Expected \(identifier) to contain \(expected); observed \(text)", file: file, line: line)
                }
            }
            dashboardDiagnostics(named: "\(specification.footer)-\(diagnosticSuffix)")
        }
    }

    @MainActor private func assertFrame(_ child: XCUIElement, fitsInside parent: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let inner = child.frame
        let outer = parent.frame.insetBy(dx: -1, dy: -1)
        XCTAssertGreaterThan(inner.width, 0, child.identifier, file: file, line: line)
        XCTAssertGreaterThan(inner.height, 0, child.identifier, file: file, line: line)
        XCTAssertTrue(outer.contains(inner), "\(child.identifier) \(inner) overflows \(parent.identifier) \(parent.frame)", file: file, line: line)
    }

    @MainActor private func revealSummaryCardFully(_ card: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for attempt in 0...10 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.tabBars.firstMatch.frame.minY
            if card.isHittable && card.frame.minY >= top && card.frame.maxY <= bottom { return }
            if attempt < 10 {
                // Move only the measured overflow, so a large text card is not
                // repeatedly scrolled past the opposite edge of the viewport.
                let overflow = card.frame.minY < top ? card.frame.minY - top - 12 : card.frame.maxY - bottom + 12
                let distance = min(abs(overflow), (bottom - top) * 0.6)
                let startY = overflow > 0 ? bottom - 30 : top + 30
                let endY = startY + (overflow > 0 ? -distance : distance)
                let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                let start = origin.withOffset(CGVector(dx: 0, dy: startY - app.frame.minY))
                let end = origin.withOffset(CGVector(dx: 0, dy: endY - app.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        XCTFail("Summary card was not fully visible after bounded scrolling: \(card.identifier) \(card.frame)\n\(app.debugDescription)", file: file, line: line)
    }

    @MainActor private func selectNewestTrendHour(contains values: [String] = [], diagnosticName: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let details = app.buttons["dashboard.trend.details"]
        reveal(details, file: file, line: line)
        details.tap()
        let first = app.buttons["dashboard.trend.hour.2026-10-15 11:00"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.trend.hour.")).firstMatch.identifier,
                       first.identifier, "Hourly details must put the newest row first.", file: file, line: line)
        let text = first.label + " " + (first.value as? String ?? "")
        for value in values {
            XCTAssertTrue(text.contains(value), "Expected hourly detail to contain \(value); observed \(text)", file: file, line: line)
        }
        if let diagnosticName { dashboardDiagnostics(named: diagnosticName) }
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.trend.selection"].firstMatch.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    @MainActor private func revealTrendZoomControl(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // A chart control can report isHittable while above the navigation bar.
        // Require its complete frame to be inside the visible content region.
        let navigationBar = app.navigationBars.firstMatch
        let tabBar = app.tabBars.firstMatch
        for attempt in 0...8 {
            if element.exists && element.isHittable && navigationBar.exists && tabBar.exists {
                let frame = element.frame
                if frame.minY >= navigationBar.frame.maxY + 4 && frame.maxY <= tabBar.frame.minY { element.waitUntilSettled(); return }
            }
            if attempt < 8 { scroll(towardBottom: false) }
        }
        XCTFail("Trend zoom control was not fully visible after bounded scrolling: \(element.frame)\n\(app.debugDescription)", file: file, line: line)
    }

    @MainActor @discardableResult
    private func assertDashboardValue(_ identifier: String, contains values: [String], towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        reveal(element, towardBottom: towardBottom, file: file, line: line)
        // Metric cards expose children so their individual footer values remain
        // accessible. Include child text when asserting a whole card's value.
        let text = ([element] + element.descendants(matching: .staticText).allElementsBoundByIndex)
            .map { $0.label + " " + ($0.value as? String ?? "") }.joined(separator: " ")
        for value in values {
            XCTAssertTrue(text.contains(value), "Expected \(identifier) to contain \(value); observed \(text)\n\(app.debugDescription)", file: file, line: line)
        }
        return text
    }

    @MainActor private func dashboardDiagnostics(named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor private func submitLogin() {
        // The root page and the 添加站点 sheet have different titles (60 §4.1), and a form scrolled to its top may not have
        // created the button's row yet: any login field shows the page is there.
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "login.")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        // The login form dismisses its keyboard when scrolling. Keep the drag
        // above the keyboard so it scrolls the form rather than typing a key.
        if app.keyboards.firstMatch.exists { scroll(towardBottom: true) }
        reveal(app.buttons["login.submit"])
        app.buttons["login.submit"].tap()
    }

    @MainActor private func enter(_ value: String, in field: XCUIElement, towardBottom: Bool = true) {
        reveal(field, towardBottom: towardBottom)
        field.tap()
        field.typeText(value)
    }

    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI List/Form virtualize rows; an offscreen row may not exist in
        // the accessibility tree until scrolling creates it.
        for attempt in 0...8 {
            if element.exists && element.isHittable { return }
            if attempt < 8 { scroll(towardBottom: towardBottom) }
        }
        XCTAssertTrue(element.exists, "Element was not created after bounded scrolling: \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Element remained offscreen after bounded scrolling: \(element)", file: file, line: line)
    }

    @MainActor private func scroll(towardBottom: Bool) {
        let frame = app.frame
        let navigationBar = app.navigationBars.firstMatch
        let top = max(frame.minY + 100, navigationBar.exists ? navigationBar.frame.maxY + 20 : frame.minY + 100)
        let keyboard = app.keyboards.firstMatch
        let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
        let height = max(40, bottom - top)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
        let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
        (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
    }
}
