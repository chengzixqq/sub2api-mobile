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
        XCTAssertFalse(app.staticTexts["dashboard.trend.error"].exists)
        reveal(app.buttons["dashboard.trend.load"])
        app.buttons["dashboard.trend.load"].tap()
        XCTAssertTrue(app.staticTexts["dashboard.trend.error"].waitForExistence(timeout: 5))
        reveal(counter, towardBottom: false)
        XCTAssertTrue(counter.exists)
        reveal(app.buttons["dashboard.monitoring.load"])
        app.buttons["dashboard.monitoring.load"].tap()
        XCTAssertTrue(app.staticTexts["dashboard.monitoring.error"].waitForExistence(timeout: 5))
        app.tabBars.buttons["账号"].tap()
        app.tabBars.buttons["概览"].tap()
        reveal(counter, towardBottom: false)
        XCTAssertTrue(counter.exists)
    }

    @MainActor func testDashboardShowsActualAndAccountCostsTokensPerformanceAndDates() {
        launch()
        defer { dashboardDiagnostics(named: "dashboard-final-state") }
        login(name: "概览显示验收", url: "https://dashboard.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)

        assertDashboardValue("dashboard.today-requests", contains: ["128"])
        assertDashboardValue("dashboard.today-tokens", contains: ["1.23M"])
        let actual = assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        let account = assertDashboardValue("dashboard.today-account-cost", contains: ["$4.56"])
        // Distinct fixture prices catch accidentally displaying standard cost.
        XCTAssertFalse(actual.contains("99.99"))
        XCTAssertFalse(account.contains("99.99"))
        assertDashboardValue("dashboard.total-tokens", contains: ["9.88B"])
        dashboardDiagnostics(named: "dashboard-compact-tokens-and-real-costs")

        assertDashboardValue("dashboard.performance.rpm", contains: ["1.23K", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.65K", "TPM"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.25s"])
        dashboardDiagnostics(named: "dashboard-performance-units")

        let load = app.buttons["dashboard.trend.load"]
        reveal(load)
        load.tap()
        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        reveal(chart)
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
        assertDashboardValue("dashboard.performance.rpm", contains: ["1.23K", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.65K", "TPM"])
        dashboardDiagnostics(named: "dashboard-top-performance-card")

        let health = app.descendants(matching: .any)["dashboard.health"].firstMatch
        reveal(health)
        XCTAssertTrue(health.descendants(matching: .any)["dashboard.health.errors"].firstMatch.exists)
        XCTAssertTrue(health.descendants(matching: .any)["dashboard.performance.duration"].firstMatch.exists)
        assertDashboardValue("dashboard.health.errors", contains: ["1"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.25s"])
        dashboardDiagnostics(named: "dashboard-running-health")
    }

    @MainActor func testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection() {
        launch(arguments: ["-ui-trend-long-series"])
        defer { dashboardDiagnostics(named: "dashboard-trend-interaction-final") }
        login(name: "趋势交互验收", url: "https://trend.example.com")
        let load = app.buttons["dashboard.trend.load"]
        reveal(load)
        load.tap()
        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        let metric = app.segmentedControls["dashboard.trend.metric"]
        reveal(metric)
        XCTAssertTrue(metric.buttons["实际消费"].isSelected, "Actual consumption should be the initial trend metric.")

        let zoomIn = app.buttons["dashboard.trend.zoom-in"]
        reveal(zoomIn)
        let initialZoom = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch.label
        for _ in 0..<4 {
            if !zoomIn.isEnabled { break }
            zoomIn.tap()
        }
        XCTAssertFalse(zoomIn.isEnabled, "Zoom should reach its bounded maximum.")
        let maximumZoom = assertDashboardValue("dashboard.trend.zoom-level", contains: ["放大"])
        XCTAssertNotEqual(maximumZoom, initialZoom)
        reveal(chart)
        dashboardDiagnostics(named: "dashboard-trend-max-zoom-actual-consumption")

        let visibleRange = app.descendants(matching: .any)["dashboard.trend.visible-range"].firstMatch
        reveal(visibleRange)
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

        selectFirstTrendHour()
        let actual = assertDashboardValue("dashboard.trend.selection", contains: ["10/14", "00:00", "0.10000001"])
        XCTAssertFalse(actual.contains("9.10000001"), "The exact selected value must not use standard cost.")
        dashboardDiagnostics(named: "dashboard-trend-exact-actual-selection")

        reveal(metric, towardBottom: false)
        metric.buttons["Tokens"].tap()
        XCTAssertTrue(metric.buttons["Tokens"].isSelected)
        selectFirstTrendHour()
        let tokens = assertDashboardValue("dashboard.trend.selection", contains: ["Tokens"])
        XCTAssertTrue(tokens.replacingOccurrences(of: ",", with: "").contains("1000000"), tokens)
        XCTAssertFalse(tokens.contains("1.00M"), "Selected hourly values should preserve exact counts.")
        dashboardDiagnostics(named: "dashboard-trend-exact-token-selection")

        reveal(metric, towardBottom: false)
        metric.buttons["请求数"].tap()
        XCTAssertTrue(metric.buttons["请求数"].isSelected)
        selectFirstTrendHour()
        assertDashboardValue("dashboard.trend.selection", contains: ["请求数", "100 次"])
        dashboardDiagnostics(named: "dashboard-trend-exact-request-selection")

        let zoomOut = app.buttons["dashboard.trend.zoom-out"]
        reveal(zoomOut, towardBottom: false)
        let priorZoom = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch.label
        zoomOut.tap()
        let zoomLevel = app.descendants(matching: .any)["dashboard.trend.zoom-level"].firstMatch
        XCTAssertNotEqual(zoomLevel.label, priorZoom)
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
        assertDashboardValue("dashboard.today-tokens", contains: ["1.23M"])
        assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        let account = app.descendants(matching: .any)["dashboard.today-account-cost"].firstMatch
        reveal(account)
        let snapshotReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "$4.56", "$4.56"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [snapshotReady], timeout: 10), .completed, app.debugDescription)
        let accountText = assertDashboardValue("dashboard.today-account-cost", contains: ["$4.56"])
        XCTAssertFalse(accountText.contains("99.99"))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.costs.error"].firstMatch.exists)
        dashboardDiagnostics(named: "dashboard-cost-snapshot-amounts")
        assertDashboardValue("dashboard.performance.duration", contains: ["1.25s"])
    }

    @MainActor func testDashboardCostSnapshotFailureKeepsPrimaryStatsAndRetryLocal() {
        launch(arguments: ["-ui-missing-account-cost", "-ui-cost-snapshot-error"])
        defer { dashboardDiagnostics(named: "dashboard-cost-snapshot-local-error") }
        login(name: "费用快照超时", url: "https://cost-timeout.example.com")
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.today-requests"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertDashboardValue("dashboard.today-tokens", contains: ["1.23M"])
        let actual = assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        let unavailable = assertDashboardValue("dashboard.today-account-cost", contains: ["不可用"])
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
        assertDashboardValue("dashboard.performance.rpm", contains: ["1.23K", "RPM"])
        assertDashboardValue("dashboard.performance.tpm", contains: ["987.65K", "TPM"])
        assertDashboardValue("dashboard.performance.duration", contains: ["1.25s"])
        assertDashboardValue("dashboard.today-tokens", contains: ["1.23M"], towardBottom: false)
        assertDashboardValue("dashboard.today-actual-cost", contains: ["$12.34"])
        assertDashboardValue("dashboard.today-account-cost", contains: ["不可用"])
        XCTAssertFalse(app.alerts["操作未完成"].exists)
    }

    @MainActor func testAddAndSwitchStations() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.add"].tap()
        login(name: "站点 B", url: "https://b.example.com")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.站点 A"].tap()
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10))
    }

    @MainActor func testSameStationKeepsNewLoginAsSeparateIdentity() {
        launch()
        login(name: "管理员 A", url: "https://same.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.add"].tap()
        login(name: "管理员 B", url: "https://same.example.com")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.site.管理员 A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.site.管理员 B"].exists)
    }

    @MainActor func testLogoutErasesCredentialInsteadOfRestoringSession() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.logout"].tap()
        app.buttons["退出并清除凭据"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        reveal(app.buttons["login.saved.站点 A"])
        app.buttons["login.saved.站点 A"].tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["此站点凭据已清除，请重新登录。"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
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

    @MainActor private func selectFirstTrendHour(file: StaticString = #filePath, line: UInt = #line) {
        let details = app.buttons["dashboard.trend.details"]
        reveal(details, file: file, line: line)
        details.tap()
        let first = app.buttons["dashboard.trend.hour.2026-10-14 00:00"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.trend.selection"].firstMatch.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    @MainActor @discardableResult
    private func assertDashboardValue(_ identifier: String, contains values: [String], towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        reveal(element, towardBottom: towardBottom, file: file, line: line)
        let text = element.label + " " + (element.value as? String ?? "")
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
        XCTAssertTrue(app.navigationBars["Sub2 Mobile"].waitForExistence(timeout: 10))
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
