import XCTest

/// S1-09: the old overview's trend chart on its stage 1 page, reached from the overview's RPM and TPM cells
/// (`.analytics(focus: .perf, metric:)`). S4-13 deletes this class with the page (X20).
final class LegacyTrendUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    /// From the RPM cell the page opens on 性能指标; the usage chart is one tap away (S1-09).
    @MainActor func testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection() {
        launch(arguments: ["-ui-trend-long-series"])
        defer { dashboardDiagnostics(named: "dashboard-trend-interaction-final") }
        login(name: "趋势交互验收", url: "https://trend.example.com")
        openLegacyTrend(from: "rpm")
        let metric = app.segmentedControls["dashboard.trend.metric"]
        reveal(metric, towardBottom: false)
        XCTAssertTrue(metric.buttons["性能指标"].isSelected, app.debugDescription)
        metric.buttons["实际扣费"].tap()
        XCTAssertTrue(metric.buttons["实际扣费"].isSelected, app.debugDescription)
        let chart = app.descendants(matching: .any)["dashboard.trend.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)

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
        assertDashboardValue("dashboard.trend.selection", contains: ["实际扣费", "$"])
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

    /// From the TPM cell: 性能指标 and TPM are chosen, and a failed usage trend leaves the performance tab working (S1-09).
    @MainActor func testPerformanceTrendFourthTabShowsRealRatesAndNewestDetails() {
        launch(arguments: ["-ui-dashboard-detail-errors"])
        login(name: "性能趋势验收", url: "https://performance.example.com")
        openLegacyTrend(from: "tpm")
        XCTAssertTrue(app.staticTexts["dashboard.trend.error"].waitForExistence(timeout: 10), app.debugDescription)
        let tabs = app.segmentedControls["dashboard.trend.metric"]
        reveal(tabs, towardBottom: false)
        XCTAssertEqual(tabs.buttons.count, 4)
        XCTAssertTrue(tabs.buttons["性能指标"].isSelected, app.debugDescription)
        let chart = app.descendants(matching: .any)["dashboard.performance.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), app.debugDescription)
        let selector = app.segmentedControls["dashboard.performance.metric"]
        reveal(selector, towardBottom: false)
        XCTAssertTrue(selector.buttons["TPM"].isSelected, app.debugDescription)
        reveal(chart)
        dashboardDiagnostics(named: "performance-trend-tpm")
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

    @MainActor private func login(name: String, url: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter(name, in: app.textFields["login.name"], towardBottom: false)
        enter(url, in: app.textFields["login.url"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        submitLogin()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }

    /// Taps the overview's `home.ticker.<kind>` cell once the first load filled it, and waits for the page.
    @MainActor private func openLegacyTrend(from kind: String, file: StaticString = #filePath, line: UInt = #line) {
        let cell = app.descendants(matching: .any)["home.ticker." + kind].firstMatch
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: cell)
        XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        cell.tap()
        XCTAssertTrue(app.descendants(matching: .any)["legacy.trend"].firstMatch.waitForExistence(timeout: 10), app.debugDescription,
                      file: file, line: line)
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
