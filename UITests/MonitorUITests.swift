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
        XCTAssertTrue(element("monitor.alerts.firing").waitForExistence(timeout: 10), app.debugDescription)
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

    /// 10 §1.1: the overview's 渠道 row opens 监控 · 渠道.
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
        XCTAssertTrue(element("monitor.channels.header").waitForExistence(timeout: 10), app.debugDescription)
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

    // MARK: S1-14 概况 · 服务器

    /// LiveOpsFixtures+Server.swift as VoiceOver reads it (the UI tests cannot import the App, so change both together).
    private enum ServerExpected {
        static let figures = [("concurrency", "8/50"), ("queue", "1"), ("qps", "0.8"), ("sla", "99.2%")]
        static let jobs = [("ops_metrics_collector", ["指标采集", "最近成功", "最近一次失败：redis: connection pool timeout"]),
                           ("ops_preaggregation_hourly", ["预聚合（小时）", "没有成功，需要看一下"]), ("ops_cleanup", ["清理", "按计划应在"]),
                           ("ops_scheduled_reports", ["定时报告", "已关闭"]), ("ops_custom_sync", ["ops_custom_sync"])]
        /// LiveOpsFixtures.serverLegacyWithheldCapabilities.
        static let legacyCapabilities = "ops.system_metrics_history,ops.ingress_reject_totals"
    }

    /// The section's title, scrolled into view.
    @discardableResult @MainActor private func revealServerSection(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let header = element("monitor.server.header")
        reveal(header, file: file, line: line)
        return header
    }

    /// 10 §4.3: CPU / 内存 with their tones and lines, the four figures, a row per job (none of them a button) and 日志采集 with
    /// the rejections and the jobs that need attention.
    @MainActor func testServerSectionShowsMetersFiguresJobsAndIngest() {
        launchAndLogin()
        defer { diagnostics("monitor-server-final") }
        openMonitor()
        let header = revealServerSection()
        XCTAssertTrue(header.label.hasPrefix("服务器"), header.debugDescription)
        XCTAssertEqual(header.value as? String, "仅管理员可见")
        assertValue(element("monitor.server.cpu.critical"), "92.0%")
        assertValue(element("monitor.server.memory.caution"), "78.0%")
        XCTAssertTrue(element("monitor.server.cpu.trend").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("monitor.server.memory.trend").exists, app.debugDescription)
        for (kind, value) in ServerExpected.figures { assertValue(element("monitor.server." + kind), value) }
        diagnostics("monitor-server")
        for (job, parts) in ServerExpected.jobs {
            let row = element("monitor.server.job." + job)
            reveal(row)
            for part in parts { XCTAssertTrue(row.label.contains(part), "\(job): \(row.label)") }
        }
        XCTAssertTrue(element("monitor.server.job.ops_custom_sync").label.hasPrefix("ops_custom_sync"), app.debugDescription)
        XCTAssertFalse(app.buttons["monitor.server.job.ops_cleanup"].exists, app.debugDescription)
        let ingest = element("monitor.server.ingest")
        reveal(ingest)
        for part in ["日志采集", "延迟 850ms", "入口拒绝 3 次（1 小时）· 3 个任务需留意"] {
            XCTAssertTrue(ingest.label.contains(part), ingest.label)
        }
        XCTAssertFalse(app.buttons["monitor.server.ingest"].exists, app.debugDescription)
        XCTAssertFalse(element("monitor.server.load.failure").exists, app.debugDescription)
    }

    /// Appendix A S7: realtime monitoring off is “—” with 实时监控未开启 beside it, the queue from the overview; ops monitoring stays on.
    @MainActor func testServerSectionRealtimeOffShowsDashAndHint() {
        launchAndLogin(arguments: ["-ui-monitor-realtime-off"])
        defer { diagnostics("monitor-server-realtime-off-final") }
        openMonitor()
        assertValue(element("monitor.run.health"), Expected.health)
        revealServerSection()
        assertValue(element("monitor.server.concurrency"), Expected.missing)
        let note = element("monitor.server.realtimeOff")
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(note.label, "实时监控未开启")
        assertValue(element("monitor.server.queue"), "4")
        XCTAssertTrue(element("monitor.server.cpu.critical").exists, app.debugDescription)
        XCTAssertFalse(element("ops.disabled.empty").exists, app.debugDescription)
        XCTAssertFalse(text(containing: "运维监控未开启").exists, app.debugDescription)
        diagnostics("monitor-server-realtime-off")
    }

    /// 10 §0.2: without the history the lines wait for points of their own (one so far); without the totals up to three pages are
    /// added up (“≥ 600”).
    @MainActor func testServerSectionWithoutHistoryAndIngressTotals() {
        launchAndLogin(arguments: ["-ui-without-capabilities", ServerExpected.legacyCapabilities])
        defer { diagnostics("monitor-server-legacy-final") }
        openMonitor()
        revealServerSection()
        assertValue(element("monitor.server.cpu.critical"), "92.0%")
        XCTAssertFalse(element("monitor.server.cpu.trend").exists, app.debugDescription)
        XCTAssertFalse(element("monitor.server.memory.trend").exists, app.debugDescription)
        let ingest = element("monitor.server.ingest")
        reveal(ingest)
        XCTAssertTrue(waitFor(ingest, "label CONTAINS %@", "入口拒绝 ≥ 600 次（1 小时）· 3 个任务需留意"), ingest.label)
        XCTAssertFalse(element("monitor.server.load.failure").exists, app.debugDescription)
    }

    // MARK: S1-15 渠道

    /// LiveOpsFixtures+Channels.swift as VoiceOver reads it (group ids 来源 LiveOpsFixtureIDs / DEMO.groups; the UI tests cannot
    /// import the App, so change both together).
    private enum ChannelExpected {
        static let counts = [("available", "3"), ("degraded", "1"), ("unavailable", "1"), ("unknown", "4")]
        static let firstRows = ["monitor.channels.row.8", "monitor.channels.row.5", "monitor.channels.row.10"]
        static let notes = [(8, "不可用，错误率 31.0% · 首字 —"), (5, "性能下降，可用率 97.5% · 首字 8.6s"), (10, "未知，采集不可用"),
                            (7, "未知，样本不足"), (9, "未知，数据已过期"), (3, "未知，无样本"), (2, "可用，可用率 99.9% · 首字 900ms")]
        static let coverage = "渠道数据采集延迟，显示的可能不是最新状态"
        static let monitorOff = "-ui-channel-monitor-off"
    }

    /// The 渠道 segment, opened from 概况.
    @discardableResult @MainActor private func openChannels(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let segments = openMonitor(file: file, line: line)
        segments.segment("渠道").tap()
        assertSelected(segments.segment("渠道"), file: file, line: line)
        return segments
    }
    @MainActor private func channelRow(_ groupID: Int) -> XCUIElement { element("monitor.channels.row.\(groupID)") }
    @MainActor private func channelElements(_ prefixes: [String]) -> XCUIElementQuery {
        let format = prefixes.map { _ in "identifier BEGINSWITH %@" }.joined(separator: " OR ")
        return app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: prefixes))
    }
    @MainActor private func assertChannelCounts(_ expected: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (key, value) in expected { assertValue(element("monitor.channels.count." + key), value, file: file, line: line) }
    }

    /// 10 §5.3: the four counts, the title, rows worst first; the segment carries unavailable + degraded (S1-13).
    @MainActor func testChannelsSegmentShowsCountsAndSortedRows() {
        launchAndLogin()
        defer { diagnostics("monitor-channels-final") }
        let segments = openMonitor()
        XCTAssertTrue(waitFor(segments.segment("渠道"), "label == %@", "渠道 2"), segments.debugDescription)
        openChannels()
        assertChannelCounts(ChannelExpected.counts)
        let header = element("monitor.channels.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(header.label.hasPrefix("渠道"), header.debugDescription)
        XCTAssertEqual(header.value as? String, "可用率 · 首字")
        XCTAssertFalse(element("monitor.channels.coverage").exists, app.debugDescription)
        XCTAssertTrue(channelRow(8).waitForExistence(timeout: 10), app.debugDescription)
        // A List row may report its identifier on the cell and the link alike: each identifier once, in list order.
        let shown = channelElements(["monitor.channels.row."]).allElementsBoundByIndex.map(\.identifier)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        XCTAssertEqual(Array(shown.prefix(3)), ChannelExpected.firstRows)
        XCTAssertTrue(text(containing: "渠道 · 近 90 分钟", in: app.navigationBars.firstMatch).exists, app.debugDescription)
        diagnostics("monitor-channels")
    }

    /// 10 §5.3: each note's branch, the first token as R10's millisecond reading; the title with the platform.
    @MainActor func testChannelRowNotesCoverEveryState() {
        launchAndLogin()
        defer { diagnostics("monitor-channel-notes-final") }
        openChannels()
        XCTAssertTrue(channelRow(8).waitForExistence(timeout: 10), app.debugDescription)
        for (groupID, value) in ChannelExpected.notes {
            let row = channelRow(groupID)
            reveal(row)
            XCTAssertEqual(row.value as? String, value, row.debugDescription)
        }
        XCTAssertEqual(channelRow(2).label, "标准组，OpenAI")
    }

    /// U07: a row opens its group on this tab's stack; back returns to 渠道.
    @MainActor func testChannelRowOpensGroupDetail() {
        launchAndLogin()
        defer { diagnostics("monitor-channel-group-final") }
        openChannels()
        let row = channelRow(10)
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        reveal(row)
        row.tap()
        XCTAssertTrue(app.segmentedControls["monitor.segment"].waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["监控"].isSelected, app.debugDescription)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription)
        assertSelected(segments.segment("渠道"))
        XCTAssertTrue(channelRow(10).waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §5.2, §5.5: the channel monitor off is one empty state with no switch; the segment carries no count.
    @MainActor func testChannelMonitorOffShowsDisabledState() {
        launchAndLogin(arguments: [ChannelExpected.monitorOff])
        defer { diagnostics("monitor-channels-off-final") }
        let segments = openMonitor()
        XCTAssertEqual(segments.segment("渠道").label, "渠道")
        openChannels()
        let off = element("monitor.channels.disabled")
        XCTAssertTrue(off.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["渠道监控未开启", "可在 Web 后台的渠道监控设置中开启"] {
            XCTAssertTrue(off.label.contains(part) || text(containing: part, in: off).exists, off.debugDescription)
        }
        XCTAssertEqual(channelElements(["monitor.channels.row.", "monitor.channels.count."]).count, 0, app.debugDescription)
        XCTAssertFalse(element("monitor.channels.retry").exists, app.debugDescription)
        diagnostics("monitor-channels-off")
    }

    /// 10 §5.3: collection lagging adds one neutral line above the list; the counts stay.
    @MainActor func testChannelCoverageHintAppears() {
        launchAndLogin(arguments: ["-ui-channel-coverage-stale"])
        defer { diagnostics("monitor-channels-coverage-final") }
        openChannels()
        let coverage = element("monitor.channels.coverage")
        XCTAssertTrue(coverage.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(coverage.label, ChannelExpected.coverage)
        assertChannelCounts(ChannelExpected.counts)
    }

    /// 10 §5.5: a failure before any list: the counts “—”, 渠道加载失败 · 重试 and no rows; 重试 asks again.
    @MainActor func testChannelLoadFailureShowsRetry() {
        launchAndLogin(arguments: ["-ui-channel-overview-fails"])
        defer { diagnostics("monitor-channels-failure-final") }
        openChannels()
        let failure = element("monitor.channels.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "渠道加载失败", in: failure).exists, app.debugDescription)
        assertChannelCounts(ChannelExpected.counts.map { ($0.0, Expected.missing) })
        XCTAssertEqual(channelElements(["monitor.channels.row."]).count, 0, app.debugDescription)
        let retry = element("monitor.channels.retry")
        XCTAssertTrue(retry.exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §5.2: ops monitoring off leaves the channel monitor alone.
    @MainActor func testChannelsSegmentIgnoresOpsSwitch() {
        launchAndLogin(arguments: ["-ui-ops-disabled"])
        defer { diagnostics("monitor-channels-ops-off-final") }
        openMonitor()
        XCTAssertTrue(element("ops.disabled.empty").waitForExistence(timeout: 10), app.debugDescription)
        openChannels()
        assertValue(element("monitor.channels.count.available"), "3")
        XCTAssertFalse(element("ops.disabled.empty").exists, app.debugDescription)
    }

    /// 00 §3.3: a site without the channel monitor's route (a non-JSON 404) is greyed out as 站点版本较旧, with no counts, no
    /// 重试 and no count on the segment.
    @MainActor func testChannelRouteMissingShowsUnsupportedState() {
        launchAndLogin(arguments: ["-ui-channel-overview-unsupported"])
        defer { diagnostics("monitor-channels-unsupported-final") }
        let segments = openChannels()
        let unsupported = element("monitor.channels.unsupported")
        XCTAssertTrue(unsupported.waitForExistence(timeout: 10), app.debugDescription)
        let title = "站点版本较旧，暂不支持此功能"
        XCTAssertTrue(unsupported.label.contains(title) || text(containing: title, in: unsupported).exists, unsupported.debugDescription)
        XCTAssertEqual(channelElements(["monitor.channels.row.", "monitor.channels.count."]).count, 0, app.debugDescription)
        XCTAssertFalse(element("monitor.channels.retry").exists || element("monitor.channels.failure").exists, app.debugDescription)
        XCTAssertTrue(waitFor(segments.segment("渠道"), "label == %@", "渠道"), segments.debugDescription)
        diagnostics("monitor-channels-unsupported")
    }

    // MARK: S1-16 告警

    /// LiveOpsFixtureIDs (来源 LiveOpsFixtureIDs; the UI tests cannot import the App, so change both together): #41 P1 标准组, not
    /// silenced; #40 P2 Anthropic, silenced; #37 resolved; `-ui-alerts-history` ends with #3160.
    private enum AlertFixture {
        static let alertA = 41
        static let anthropic = 40
        static let endedResolved = 37
        static let oldestHistory = 3160
        static let history = "-ui-alerts-history"
        static let listFails = "-ui-alerts-list-fails"
        static let writeFails = "-ui-alert-write-fails"
    }

    /// The 告警 segment, opened from 概况.
    @discardableResult @MainActor private func openAlerts(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let segments = openMonitor(file: file, line: line)
        segments.segment("告警").tap()
        assertSelected(segments.segment("告警"), file: file, line: line)
        return segments
    }
    @MainActor private func alertRow(_ id: Int) -> XCUIElement { app.buttons["monitor.alerts.row.\(id)"].firstMatch }
    /// `kind` is resolve or silence.
    @MainActor private func alertButton(_ kind: String, _ id: Int) -> XCUIElement { app.buttons["monitor.alerts.\(kind).\(id)"].firstMatch }
    /// 加载更早 sits under some fifty rows of a lazy list: swipe until `item` is on screen.
    @MainActor private func scrollTo(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<25 {
            if item.exists && item.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
    }
    /// 手动解决 on the row, then the alert's own 手动解决.
    @MainActor private func resolveInline(_ id: Int, file: StaticString = #filePath, line: UInt = #line) {
        let resolve = alertButton("resolve", id)
        XCTAssertTrue(resolve.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        resolve.tap()
        let confirm = app.alerts["手动解决这条告警？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        confirm.buttons["手动解决"].firstMatch.tap()
    }

    /// 10 §6.3: 告警中 (2 条) with each firing row's buttons; 最近结束 with its ended rows, which have none.
    @MainActor func testAlertsSegmentShowsFiringAndEndedSections() {
        launchAndLogin()
        defer { diagnostics("monitor-alerts-final") }
        openAlerts()
        assertValue(element("monitor.alerts.firing"), "2 条")
        for id in [AlertFixture.alertA, AlertFixture.anthropic] {
            XCTAssertTrue(waitFor(alertRow(id), "label CONTAINS %@", "告警中"), alertRow(id).debugDescription)
        }
        XCTAssertTrue(alertButton("resolve", AlertFixture.alertA).exists, app.debugDescription)
        XCTAssertTrue(alertButton("silence", AlertFixture.alertA).label.hasPrefix("静默"), alertButton("silence", AlertFixture.alertA).label)
        XCTAssertTrue(alertButton("silence", AlertFixture.anthropic).label.hasPrefix("改静默"), alertButton("silence", AlertFixture.anthropic).label)
        XCTAssertTrue(alertRow(AlertFixture.anthropic).label.contains("已静默至"), alertRow(AlertFixture.anthropic).label)
        XCTAssertTrue(text(containing: "告警 · 2 条进行中", in: app.navigationBars.firstMatch).exists, app.debugDescription)
        diagnostics("monitor-alerts")
        let ended = element("monitor.alerts.ended")
        reveal(ended)
        XCTAssertTrue(waitFor(ended, "value ENDSWITH %@", " 条"), ended.debugDescription)
        let resolved = alertRow(AlertFixture.endedResolved)
        reveal(resolved)
        XCTAssertTrue(resolved.label.contains("已恢复"), resolved.label)
        XCTAssertFalse(alertButton("resolve", AlertFixture.endedResolved).exists, app.debugDescription)
    }

    /// 10 §7.1: 手动解决 on the row asks first; the receipt has no undo, the row moves to 最近结束, the counts drop, and the
    /// overview's row is gone too.
    @MainActor func testInlineResolveMovesRowToEndedAndUpdatesHome() {
        launchAndLogin()
        defer { diagnostics("monitor-alerts-resolve-final") }
        let segments = openAlerts()
        resolveInline(AlertFixture.alertA)
        let receipt = element("receipt.text")
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "已手动解决")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(alertButton("resolve", AlertFixture.alertA).waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(segments.segment("告警"), "label == %@", "告警 1"), segments.debugDescription)
        assertValue(element("monitor.alerts.firing"), "1 条")
        let row = alertRow(AlertFixture.alertA)
        reveal(row)
        XCTAssertTrue(waitFor(row, "label CONTAINS %@", "已手动解决"), row.debugDescription)
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(element("home.attention.alert-\(AlertFixture.anthropic)").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("home.attention.alert-\(AlertFixture.alertA)").exists, app.debugDescription)
    }

    /// 10 §7.1: 静默… offers the three durations; the receipt has 撤销, the row says until when and its button becomes 改静默….
    @MainActor func testInlineSilenceShowsDurationsAndReceipt() {
        launchAndLogin()
        defer { diagnostics("monitor-alerts-silence-final") }
        openAlerts()
        let silence = alertButton("silence", AlertFixture.alertA)
        XCTAssertTrue(silence.waitForExistence(timeout: 10), app.debugDescription)
        silence.tap()
        let hour = menuButton("静默 1 小时")
        XCTAssertTrue(hour.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "静默这条规则多久？").exists, app.debugDescription)
        for title in ["静默 24 小时", "静默 7 天"] { XCTAssertTrue(menuButton(title).exists, title) }
        hour.tap()
        let undo = app.buttons["receipt.action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("receipt.text").label, "已静默 1 小时")
        XCTAssertEqual(undo.label, "撤销")
        XCTAssertTrue(waitFor(alertRow(AlertFixture.alertA), "label CONTAINS %@", "已静默至"), alertRow(AlertFixture.alertA).debugDescription)
        XCTAssertTrue(waitFor(silence, "label BEGINSWITH %@", "改静默"), silence.debugDescription)
    }

    /// 10 §7.1 step 4: a failed write says why and changes nothing.
    @MainActor func testInlineWriteFailureShowsReceiptAndKeepsRow() {
        launchAndLogin(arguments: [AlertFixture.writeFails])
        defer { diagnostics("monitor-alerts-write-fails-final") }
        openAlerts()
        resolveInline(AlertFixture.alertA)
        let receipt = element("receipt.text")
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "站点暂时不可用")
        XCTAssertTrue(alertButton("resolve", AlertFixture.alertA).exists, app.debugDescription)
        XCTAssertTrue(alertRow(AlertFixture.alertA).label.contains("告警中"), alertRow(AlertFixture.alertA).label)
    }

    /// 10 §6.2 更早: a full 最近结束 ends with 加载更早, which adds the older rows; at the end it goes away.
    @MainActor func testLoadEarlierAppendsOlderEndedRows() {
        launchAndLogin(arguments: [AlertFixture.history])
        defer { diagnostics("monitor-alerts-earlier-final") }
        openAlerts()
        XCTAssertTrue(alertRow(AlertFixture.alertA).waitForExistence(timeout: 10), app.debugDescription)
        let loadEarlier = app.buttons["monitor.alerts.loadEarlier"].firstMatch
        scrollTo(loadEarlier)
        XCTAssertFalse(alertRow(AlertFixture.oldestHistory).exists, app.debugDescription)
        loadEarlier.tap()
        scrollTo(alertRow(AlertFixture.oldestHistory))
        XCTAssertTrue(alertRow(AlertFixture.oldestHistory).label.contains("全站错误率"), alertRow(AlertFixture.oldestHistory).label)
        XCTAssertFalse(app.buttons["monitor.alerts.loadEarlier"].exists, app.debugDescription)
    }

    /// 10 §6.5: no list read yet and the reads fail: one 告警加载失败 · 重试 instead of the sections.
    @MainActor func testAlertListFailureShowsRetry() {
        launchAndLogin(arguments: [AlertFixture.listFails])
        defer { diagnostics("monitor-alerts-failure-final") }
        openAlerts()
        let failure = element("monitor.alerts.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "告警加载失败", in: failure).exists, app.debugDescription)
        XCTAssertFalse(element("monitor.alerts.firing").exists || element("monitor.alerts.ended").exists, app.debugDescription)
        let retry = element("monitor.alerts.retry")
        XCTAssertTrue(retry.exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §6.5, §7.2: monitoring off makes the segment the empty state.
    @MainActor func testAlertsSegmentOpsDisabledShowsNotice() {
        launchAndLogin(arguments: ["-ui-ops-disabled"])
        defer { diagnostics("monitor-alerts-ops-off-final") }
        openAlerts()
        let empty = element("ops.disabled.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "运维监控未开启", in: empty).exists, app.debugDescription)
        XCTAssertFalse(element("monitor.alerts.firing").exists, app.debugDescription)
    }

    /// 10 §6.3: nothing firing says 没有告警 under “0 条”; 最近结束 still lists what ended.
    @MainActor func testAlertsSegmentEmptyFiringSaysNoAlerts() {
        launchAndLogin(arguments: ["-ui-home-calm"])
        defer { diagnostics("monitor-alerts-calm-final") }
        openAlerts()
        let empty = element("monitor.alerts.firing.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "没有告警")
        assertValue(element("monitor.alerts.firing"), "0 条")
        XCTAssertTrue(alertRow(AlertFixture.endedResolved).waitForExistence(timeout: 10), app.debugDescription)
    }

    /// C-1, X10: a read-only `sat_` token sees the row's buttons greyed, with 只读令牌 under them.
    @MainActor func testReadOnlyTokenGreysOutInlineActions() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-monitor")
        defer { diagnostics("monitor-alerts-readonly-final") }
        openAlerts()
        let resolve = alertButton("resolve", AlertFixture.alertA)
        XCTAssertTrue(resolve.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(resolve.isEnabled, app.debugDescription)
        XCTAssertFalse(alertButton("silence", AlertFixture.alertA).isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }
}
