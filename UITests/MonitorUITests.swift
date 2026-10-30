import XCTest

/// 10 §4 监控 · 概况 over LiveOpsFixtures (S1-13): the segments, the run section, 告警中 and the ops switch. S1-14, S1-15, S1-16 and
/// S1-18 append their own tests and helpers at the end of the class.
final class MonitorUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// The run section as VoiceOver reads it: LiveOpsFixtures.fiveMinuteOverview, the overview's 运行 too (the UI tests cannot
    /// import the App, so change both together).
    private enum Expected {
        static let health = "94，良好"
        static let rates = [("errorRate", "0.8%"), ("upstream429", "12"), ("upstream529", "3")]
        static let missing = "无数据"
        static let trendLabel = "错误率 · 近 45 分钟"
    }

    // MARK: Helpers

    /// Email and password sign-in, or the access-token method with a `sat_` key (`-ui-readonly-token` makes it read-only).
    @MainActor private func launchAndLogin(arguments: [String] = [], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("监控站点", in: "login.name")
        enter("https://monitor.example.invalid", in: "login.url")
        if let accessToken {
            let method = element("login.method.accessToken"); reveal(method); method.tap()
            enter(accessToken, in: "login.key")
        } else {
            enter("admin@example.com", in: "login.email")
            enter("fixture-password", in: "login.password")
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @discardableResult @MainActor private func openMonitor(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        app.tabBars.buttons["监控"].tap()
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        return segments
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func text(containing text: String, in container: XCUIElement? = nil) -> XCUIElement {
        (container ?? app).descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func menuButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func enter(_ value: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(value)
    }
    @MainActor private func reveal(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15)))
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitFor(_ item: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: item)
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }
    @MainActor private func assertValue(_ item: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(waitFor(item, "value == %@", value), "\(item.debugDescription) ≠ \(value)", file: file, line: line)
    }
    @MainActor private func assertSelected(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    /// The ··· menu; a toolbar menu may expose only its label.
    @MainActor private func openMoreMenu(file: StaticString = #filePath, line: UInt = #line) {
        let byIdentifier = element("monitor.more")
        let more = byIdentifier.waitForExistence(timeout: 5) ? byIdentifier : app.navigationBars.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        more.tap()
        XCTAssertTrue(menuButton("刷新").waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }
    /// The confirmation's 取消 where the system draws one; otherwise a tap beside the floating dialog closes it.
    @MainActor private func dismissDialog() {
        let cancel = menuButton("取消")
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); return }
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, app.debugDescription)
        let below = sheet.frame.maxY + 80
        let y = below < app.frame.maxY - 120 ? below : sheet.frame.minY - 80
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: sheet.frame.midX, dy: y)).tap()
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: S1-13 概况 · 运行

    @MainActor func testMonitorOpensOnOverviewWithRunValues() {
        launchAndLogin()
        defer { diagnostics("monitor-overview-final") }
        let segments = openMonitor()
        assertSelected(segments.segment("概况"))
        assertValue(element("monitor.run.health"), Expected.health)
        for (kind, value) in Expected.rates { assertValue(element("monitor.run." + kind), value) }
        XCTAssertEqual(element("monitor.run.upstream529").label, "上游 529")
        XCTAssertTrue(text(containing: "运行与服务器", in: app.navigationBars.firstMatch).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("monitor.run.header").exists, app.debugDescription)
        XCTAssertFalse(element("monitor.placeholder").exists, app.debugDescription)
        diagnostics("monitor-overview")
    }

    @MainActor func testErrorTrendSparklineIsShown() {
        launchAndLogin()
        defer { diagnostics("monitor-trend-final") }
        openMonitor()
        let trend = element("monitor.run.trend")
        XCTAssertTrue(trend.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(trend.label, Expected.trendLabel)
        XCTAssertTrue(waitFor(trend, "value BEGINSWITH %@", "最近"), trend.debugDescription)
        XCTAssertFalse(element("monitor.run.trend.failure").exists, app.debugDescription)
    }

    /// 10 §4.1: 告警中 switches the page to its 告警 segment; nothing is pushed and the tab stays.
    @MainActor func testAlertsRowSwitchesToAlertsSegment() {
        launchAndLogin()
        defer { diagnostics("monitor-alerts-row-final") }
        let segments = openMonitor()
        let row = element("monitor.run.alerts")
        XCTAssertTrue(waitFor(row, "label == %@", "告警中 2 条"), row.debugDescription)
        XCTAssertTrue(waitFor(row, "value CONTAINS %@", "、"), row.debugDescription)
        reveal(row)
        row.tap()
        assertSelected(segments.segment("告警"))
        XCTAssertTrue(element("monitor.placeholder").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["监控"].isSelected, app.debugDescription)
        XCTAssertTrue(segments.exists, app.debugDescription)
    }

    /// 10 §4.1: 告警 carries the firing count, nothing when none fire.
    @MainActor func testSegmentCountsHideZero() {
        launchAndLogin()
        let segments = openMonitor()
        XCTAssertTrue(waitFor(segments.segment("告警"), "label == %@", "告警 2"), segments.debugDescription)
        diagnostics("monitor-segment-counts")
        app.terminate()

        launchAndLogin(arguments: ["-ui-home-calm"])
        defer { diagnostics("monitor-segment-counts-calm-final") }
        let calm = openMonitor()
        XCTAssertTrue(waitFor(element("monitor.run.alerts"), "label == %@", "告警中 0 条"), app.debugDescription)
        XCTAssertEqual(element("monitor.run.alerts").value as? String, "没有告警")
        XCTAssertEqual(calm.segment("告警").label, "告警")
    }

    /// U08: the segment chosen stays while switching tabs within the session.
    @MainActor func testSegmentIsRememberedWithinSession() {
        launchAndLogin()
        defer { diagnostics("monitor-segment-memory-final") }
        let segments = openMonitor()
        segments.segment("告警").tap()
        assertSelected(segments.segment("告警"))
        app.tabBars.buttons["用户"].tap()
        openMonitor()
        assertSelected(segments.segment("告警"))
        segments.segment("概况").tap()
        app.tabBars.buttons["账号"].tap()
        openMonitor()
        assertSelected(segments.segment("概况"))
        XCTAssertTrue(element("monitor.run.health").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §1.1: the overview's 渠道 row opens 监控 · 渠道 (a placeholder until S1-15).
    @MainActor func testHomeChannelRowOpensChannelsSegment() {
        launchAndLogin()
        defer { diagnostics("monitor-from-home-channels-final") }
        // The row sits below the fold and the list loads lazily: scroll to it once the overview shows.
        XCTAssertTrue(element("home.regular").waitForExistence(timeout: 10), app.debugDescription)
        let channels = element("home.run.channels")
        reveal(channels)
        XCTAssertTrue(waitFor(channels, "value BEGINSWITH %@", "可用"), channels.debugDescription)
        channels.tap()
        assertSelected(app.tabBars.buttons["监控"])
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription)
        assertSelected(segments.segment("渠道"))
        XCTAssertTrue(element("monitor.placeholder").exists, app.debugDescription)
    }

    /// 10 §4.5, §7.2: monitoring off makes the whole segment the empty state with the data-gap line; 开启 asks, then the run returns.
    @MainActor func testOpsDisabledShowsEmptyStateAndEnables() {
        launchAndLogin(arguments: ["-ui-ops-disabled"])
        defer { diagnostics("monitor-ops-disabled-final") }
        openMonitor()
        let empty = element("ops.disabled.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "运维监控未开启", in: empty).exists, app.debugDescription)
        XCTAssertTrue(text(containing: "关闭期间不会记录错误请求，开启后也不会补回", in: empty).exists, app.debugDescription)
        XCTAssertFalse(element("monitor.run.health").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "运行与服务器", in: app.navigationBars.firstMatch).exists, app.debugDescription)
        diagnostics("monitor-ops-disabled")
        openMoreMenu()
        XCTAssertFalse(menuButton("关闭运维监控…").exists, app.debugDescription)
        menuButton("刷新").tap()
        let enable = element("ops.disabled.enable")
        XCTAssertTrue(enable.waitForExistence(timeout: 10), app.debugDescription)
        enable.tap()
        let alert = app.alerts["开启运维监控？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["开启"].firstMatch.tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "已开启运维监控")
        assertValue(element("monitor.run.health"), Expected.health)
        XCTAssertFalse(empty.exists, app.debugDescription)
    }

    @MainActor func testConfigOffHasNoEnableButton() {
        launchAndLogin(arguments: ["-ui-ops-config-off"])
        defer { diagnostics("monitor-ops-config-off-final") }
        openMonitor()
        let empty = element("ops.disabled.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "运维监控已在服务器配置中关闭", in: empty).exists, app.debugDescription)
        XCTAssertFalse(element("ops.disabled.enable").exists, app.debugDescription)
        openMoreMenu()
        XCTAssertFalse(menuButton("关闭运维监控…").exists, app.debugDescription)
        menuButton("刷新").tap()
    }

    /// U10 (security): both confirmations can be cancelled without a write; only 仍要关闭 turns monitoring off.
    @MainActor func testDisableOpsMonitoringNeedsTwoConfirmations() {
        launchAndLogin()
        defer { diagnostics("monitor-ops-disable-final") }
        openMonitor()
        let health = element("monitor.run.health")
        assertValue(health, Expected.health)
        let receipt = app.staticTexts["receipt.text"]

        openMoreMenu()
        menuButton("关闭运维监控…").tap()
        XCTAssertTrue(menuButton("关闭运维监控").waitForExistence(timeout: 5), app.debugDescription)
        diagnostics("monitor-ops-disable-first")
        dismissDialog()
        XCTAssertTrue(menuButton("关闭运维监控").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(health.exists && !receipt.exists, app.debugDescription)

        openMoreMenu()
        menuButton("关闭运维监控…").tap()
        let first = menuButton("关闭运维监控")
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        first.tap()
        let lastAlert = app.alerts.firstMatch
        XCTAssertTrue(lastAlert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(lastAlert.label.contains("监控站点"), lastAlert.label)
        diagnostics("monitor-ops-disable-final-alert")
        lastAlert.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(lastAlert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(health.exists && !receipt.exists, app.debugDescription)

        openMoreMenu()
        menuButton("关闭运维监控…").tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        first.tap()
        XCTAssertTrue(lastAlert.waitForExistence(timeout: 5), app.debugDescription)
        lastAlert.buttons["仍要关闭"].firstMatch.tap()
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "已关闭运维监控")
        XCTAssertTrue(element("ops.disabled.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(health.exists, app.debugDescription)
    }

    /// 10 §4.5: the overview failed before any value: “—” and 加载失败 · 重试; the line is its own block and stays.
    @MainActor func testOverviewFailureShowsDashesAndRetry() {
        launchAndLogin(arguments: ["-ui-monitor-overview-fails"])
        defer { diagnostics("monitor-overview-fails-final") }
        openMonitor()
        let failure = element("monitor.run.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "加载失败", in: failure).exists, app.debugDescription)
        XCTAssertTrue(element("monitor.run.retry").exists, app.debugDescription)
        assertValue(element("monitor.run.health"), Expected.missing)
        for (kind, _) in Expected.rates { assertValue(element("monitor.run." + kind), Expected.missing) }
        XCTAssertTrue(waitFor(element("monitor.run.trend"), "value BEGINSWITH %@", "最近"), app.debugDescription)
    }

    /// 10 §4.3: the line failed before any value: one 趋势加载失败 · 重试 row in its place; the run's figures stay.
    @MainActor func testTrendFailureShowsSingleLine() {
        launchAndLogin(arguments: ["-ui-monitor-trend-fails"])
        defer { diagnostics("monitor-trend-fails-final") }
        openMonitor()
        let failure = element("monitor.run.trend.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "趋势加载失败", in: failure).exists, app.debugDescription)
        XCTAssertTrue(element("monitor.run.trend.retry").exists, app.debugDescription)
        XCTAssertFalse(element("monitor.run.trend").exists, app.debugDescription)
        assertValue(element("monitor.run.health"), Expected.health)
    }

    /// C-1, X10: a read-only `sat_` token still sees 关闭运维监控…, greyed.
    @MainActor func testReadOnlyTokenGreysOutDisableOps() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-monitor")
        defer { diagnostics("monitor-ops-readonly-final") }
        openMonitor()
        assertValue(element("monitor.run.health"), Expected.health)
        openMoreMenu()
        let disable = menuButton("关闭运维监控…")
        XCTAssertTrue(disable.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(disable.isEnabled, app.debugDescription)
        menuButton("刷新").tap()
    }
}
