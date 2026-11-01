import XCTest

/// 40 §6 使用记录 over LogFixtures (NativeApp/Features/Logs/LogFixtures.swift): usage 1040…1001 (30 a page, page 2 repeats 1011),
/// request errors 2006…2001 and upstream errors 3006…3001; user 1 Alice has 10 / 0 / 1 of them. Later items add their tests at the
/// end and launch with `launchLogs(arguments:)`.
final class RequestLogsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let empty = "-ui-logs-empty"
        static let firstPageFails = "-ui-logs-first-error"
        static let nextPageFails = "-ui-logs-page-error"
        static let opsDisabledReply = "-ui-logs-ops-404"
        /// S1-08: admin/me says ops monitoring is off.
        static let opsDisabled = "-ui-ops-disabled"
    }

    @MainActor func testUsageRowsShowColumnsInDaySections() {
        launchLogs()
        defer { diagnostics("logs-usage-rows") }
        let newest = row("usage", 1040)
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isLogsPage, app.debugDescription)
        XCTAssertTrue(segment("用量明细").isSelected, app.debugDescription)
        XCTAssertTrue(element("logs.time").label.contains("近 24 小时"), element("logs.time").label)
        for part in ["claude-opus-4", "状态 200", "alice@example.com", "Claude-官方-01", "金额 $0.0124", "1.2s/3.2s"] {
            XCTAssertTrue(newest.label.contains(part), "\(part)：\(newest.label)")
        }
        XCTAssertTrue(header("今天").exists, app.debugDescription)
        let sync = row("usage", 1036)
        app.scrollUntilExists(sync)
        XCTAssertTrue(sync.label.contains("首字/耗时 无数据/3.2s"), sync.label)
        XCTAssertTrue(app.scrollUntilExists(header("昨天"), maxSwipes: 20))
    }

    /// 40 §6.4: the last row reads page 2 once; the row both pages carry shows once.
    @MainActor func testScrollingToEndLoadsNextPageOnce() {
        launchLogs()
        defer { diagnostics("logs-next-page") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.scrollUntilExists(row("usage", 1001), maxSwipes: 25))
        XCTAssertFalse(element("logs.more.loading").exists, app.debugDescription)
        XCTAssertFalse(element("logs.list.failure").exists, app.debugDescription)
        XCTAssertTrue(app.scrollUntilExists(row("usage", 1011), towardBottom: false, maxSwipes: 6))
        XCTAssertEqual(app.buttons.matching(identifier: "logs.row.usage.1011").count, 1, app.debugDescription)
    }

    /// X39: the user detail's route keeps its user in every segment.
    @MainActor func testUserRouteConditionStaysAcrossSegments() {
        launchUserLogs(1)
        defer { diagnostics("logs-user-route") }
        let chip = element("logs.chip.user")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(chip.label, "用户：Alice")
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row("usage", 1039).exists, app.debugDescription)
        segment("上游错误").tap()
        XCTAssertTrue(row("upstream", 3001).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(chip.exists, app.debugDescription)
        XCTAssertFalse(row("upstream", 3005).exists, app.debugDescription)
        segment("错误请求").tap()
        let empty = element("logs.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "近 24 小时内，这些条件下没有记录")
        // S4-05b: an applied condition puts 清除筛选 under it.
        XCTAssertTrue(app.buttons["logs.empty.clear"].exists, app.debugDescription)
    }

    /// 40 §6.3: the badge is the status code, a retried upstream row shows the code it hit, and errors have no amount.
    @MainActor func testErrorAndUpstreamRowsShowStatusBadges() {
        launchLogs(item: "search.item.errors")
        defer { diagnostics("logs-error-badges") }
        let newest = row("errors", 2006)
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment("错误请求").isSelected, app.debugDescription)
        XCTAssertTrue(newest.label.contains("状态 429"), newest.label)
        let internalError = row("errors", 2005)
        XCTAssertTrue(internalError.label.contains("状态 500") && internalError.label.contains("金额 无数据"), internalError.label)
        segment("上游错误").tap()
        XCTAssertTrue(row("upstream", 3006).waitForExistence(timeout: 10), app.debugDescription)
        for (id, badge) in [(3006, "状态 502"), (3005, "状态 429"), (3004, "状态 鉴权"), (3003, "状态 恢复")] {
            let item = row("upstream", id)
            app.scrollUntilExists(item)
            XCTAssertTrue(item.label.contains(badge), "\(id)：\(item.label)")
        }
    }

    /// 40 §6.3 / §6.1: the time menu narrows the list and the subtitle; 自定义… applies a fixed range.
    @MainActor func testTimeMenuChangesWindowAndSubtitle() {
        launchLogs()
        defer { diagnostics("logs-time-menu") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let time = app.buttons["logs.time"]
        time.tap()
        menuItem("近 1 小时").tap()
        XCTAssertTrue(time.poll(NSPredicate(format: "label CONTAINS %@", "近 1 小时"), timeout: 10), time.label)
        let subtitle = app.navigationBars.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "日志验收 · 近 1 小时")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(header("昨天").exists, app.debugDescription)
        time.tap()
        menuItem("自定义…").tap()
        XCTAssertTrue(element("logs.time.custom.start").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("logs.time.custom.end").exists, app.debugDescription)
        app.buttons["logs.time.custom.apply"].tap()
        XCTAssertTrue(time.poll(NSPredicate(format: "label CONTAINS %@", " – "), timeout: 10), time.label)
    }

    /// 40 §6.5 empty without conditions: no 清除筛选.
    @MainActor func testEmptyListSaysNoRecords() {
        launchLogs(arguments: [Fixture.empty])
        defer { diagnostics("logs-empty") }
        let empty = element("logs.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "近 24 小时内没有记录")
        XCTAssertFalse(element("logs.empty.clear").exists, app.debugDescription)
        XCTAssertFalse(element("logs.list.failure").exists, app.debugDescription)
    }

    /// 40 §6.5: with ops monitoring off the error segments show the notice instead of a list; usage still loads.
    @MainActor func testErrorSegmentsShowOpsDisabledNotice() {
        launchLogs(arguments: [Fixture.opsDisabled])
        defer { diagnostics("logs-ops-disabled") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let notice = element("ops.disabled.empty")
        for title in ["错误请求", "上游错误"] {
            segment(title).tap()
            XCTAssertTrue(notice.waitForExistence(timeout: 10), "\(title)\n\(app.debugDescription)")
            XCTAssertTrue(text(containing: "关闭期间不会记录错误请求").exists, app.debugDescription)
        }
        segment("用量明细").tap()
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(notice.exists, app.debugDescription)
    }

    /// 40 §6.5: a 404 OPS_DISABLED while admin/me still says on also shows the notice, not a failure.
    @MainActor func testOpsDisabledReplyReplacesErrorList() {
        launchLogs(arguments: [Fixture.opsDisabledReply], item: "search.item.errors")
        defer { diagnostics("logs-ops-404") }
        XCTAssertTrue(element("ops.disabled.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("logs.list.failure").exists, app.debugDescription)
        XCTAssertFalse(anyRow("errors").exists, app.debugDescription)
    }

    /// 40 §6.5: a failed next page keeps the rows, says so, and 重试 reads that page.
    @MainActor func testNextPageFailureKeepsRowsAndRetries() {
        launchLogs(arguments: [Fixture.nextPageFails])
        defer { diagnostics("logs-next-page-failure") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let retry = app.buttons["logs.list.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 25))
        XCTAssertTrue(element("logs.list.failure").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "加载失败").exists, app.debugDescription)
        XCTAssertEqual(element("logs.list.kept").label, "保留上次成功加载的记录")
        XCTAssertTrue(row("usage", 1012).exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(row("usage", 1001), maxSwipes: 10))
        XCTAssertTrue(element("logs.list.failure").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testFirstLoadFailureRetries() {
        launchLogs(arguments: [Fixture.firstPageFails])
        defer { diagnostics("logs-first-failure") }
        let retry = app.buttons["logs.list.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("logs.list.failure").exists, app.debugDescription)
        XCTAssertFalse(element("logs.list.kept").exists, app.debugDescription)
        XCTAssertFalse(anyRow("usage").exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 40 §6.1: a row opens its request and the list is kept on return; what the detail shows is RequestDetailUITests' (S4-08b).
    @MainActor func testRowsOpenRequestDetails() {
        launchLogs()
        defer { diagnostics("logs-open-detail") }
        let newest = row("usage", 1040)
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        newest.tap()
        XCTAssertTrue(element("logs.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment("用量明细").isSelected, app.debugDescription)
        segment("错误请求").tap()
        let error = row("errors", 2006)
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        error.tap()
        XCTAssertTrue(element("logs.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to the fixture site “日志验收”, then opens a search directory row.
    @MainActor private func launchLogs(arguments: [String] = [], item: String = "search.item.usage") {
        login(arguments: arguments)
        app.openSearchItem(item)
    }
    /// The user tab's user, then its 使用记录 row.
    @MainActor private func launchUserLogs(_ userID: Int, arguments: [String] = []) {
        login(arguments: arguments)
        app.tabBars.buttons["用户"].tap()
        let user = app.buttons["user.\(userID)"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(user)
        user.tap()
        let logs = app.buttons["user.logs"]
        XCTAssertTrue(app.scrollUntilExists(logs))
        logs.tap()
    }
    @MainActor private func login(arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        enter("日志验收", field: app.textFields["login.name"])
        enter("https://logs-ui.example.invalid", field: app.textFields["login.url"])
        enter("admin@example.invalid", field: app.textFields["login.email"])
        enter("fixture-password", field: app.secureTextFields["login.password"])
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
    }
    /// The titled page; with a subtitle the bar may expose the title only as its text.
    @MainActor private var isLogsPage: Bool { app.navigationBars["使用记录"].exists || app.navigationBars.staticTexts["使用记录"].exists }
    /// The segment's label starts with its title (S4-05b adds the count).
    @MainActor private func segment(_ title: String) -> XCUIElement {
        let mode = app.segmentedControls["logs.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription)
        return mode.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    @MainActor private func row(_ scope: String, _ id: Int) -> XCUIElement { app.buttons["logs.row.\(scope).\(id)"] }
    @MainActor private func anyRow(_ scope: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "logs.row.\(scope).")).firstMatch
    }
    /// Section headers read as their title, with the column legend as their value.
    @MainActor private func header(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
    /// System menu items carry no identifier.
    @MainActor private func menuItem(_ label: String) -> XCUIElement {
        let item = app.buttons.matching(NSPredicate(format: "identifier == '' AND label == %@", label)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        return item
    }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func enter(_ text: String, field: XCUIElement) { reveal(field); field.tap(); field.typeText(text) }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func reveal(_ element: XCUIElement, down: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let keyboard = app.keyboards.firstMatch
            let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: - S4-05b 分段计数、条件胶囊、清除筛选与参数无效

    /// LogFixtures' counts follow the table at the top of LogFixtures.swift: all 40 / 6 / 6, user 1 Alice 10 / 0 / 1.
    private enum CountFixture {
        static let legacyServer = "-ui-logs-legacy-server"
        static let countFails = "-ui-logs-count-fails"
        static let countTicks = "-ui-logs-count-ticks"
        static let badRequest = "-ui-logs-bad-request"
    }

    /// 40 §6.3 / §6.4 / §6.6: the counts come on entry and stay when switching segments; a pull asks them again, the shown
    /// error segment taking its list's total (`-ui-logs-count-ticks` adds one per ask).
    @MainActor func testSegmentCountsShowOnEntryAndStayWhenSwitching() {
        launchLogs(arguments: [CountFixture.countTicks])
        defer { diagnostics("logs-counts") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        expectSegments(["用量明细 40", "错误请求 6", "上游错误 6"])
        segment("错误请求").tap()
        let newest = row("errors", 2006)
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        expectSegments(["用量明细 40", "错误请求 6", "上游错误 6"])
        app.pullToRefresh(from: newest)
        expectSegments(["用量明细 41", "错误请求 6", "上游错误 7"])
    }

    /// 40 §6.5: with ops monitoring off both error counts read “—”; usage still counts, and no 30-day notice shows.
    @MainActor func testErrorCountsReadDashWhenOpsMonitoringIsOff() {
        launchLogs(arguments: [Fixture.opsDisabled])
        defer { diagnostics("logs-counts-ops-off") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        expectSegments(["用量明细 40", "错误请求 —", "上游错误 —"])
        segment("错误请求").tap()
        XCTAssertTrue(element("ops.disabled.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("logs.retention").exists, app.debugDescription)
    }

    /// 40 §6.3 “拿不到写 —”: a failed usage/stats leaves the list and the other counts alone.
    @MainActor func testUsageCountReadsDashWhenStatsFail() {
        launchLogs(arguments: [CountFixture.countFails])
        defer { diagnostics("logs-count-fails") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        expectSegments(["用量明细 —", "错误请求 6", "上游错误 6"])
        XCTAssertTrue(row("usage", 1039).exists, app.debugDescription)
    }

    /// 40 §6.3: a tap on the chip drops its condition; the list and the counts start again and the time stays.
    @MainActor func testRemovingConditionChipReloadsListAndCounts() {
        launchUserLogs(1)
        defer { diagnostics("logs-remove-chip") }
        let chip = app.buttons["logs.chip.user"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(chip.label.hasPrefix("用户：Alice"), chip.label)
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row("usage", 1039).exists, app.debugDescription)
        expectSegments(["用量明细 10", "错误请求 0", "上游错误 1"])
        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 1039).waitForExistence(timeout: 10), app.debugDescription)
        expectSegments(["用量明细 40", "错误请求 6", "上游错误 6"])
        XCTAssertTrue(element("logs.time").label.contains("近 24 小时"), element("logs.time").label)
    }

    /// 40 §6.4: on a server without D03 the upstream segment greys the user chip, says why under the chips, and lists everyone.
    @MainActor func testUpstreamGreysUserChipWithReasonOnOldServer() {
        launchUserLogs(1, arguments: [CountFixture.legacyServer])
        defer { diagnostics("logs-greyed-chip") }
        let chip = app.buttons["logs.chip.user"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertNotEqual(chip.value as? String, "未生效")
        let reason = element("logs.chips.reason")
        XCTAssertFalse(reason.exists, app.debugDescription)
        expectSegments(["用量明细 10", "错误请求 0", "上游错误 6"])
        segment("上游错误").tap()
        XCTAssertTrue(row("upstream", 3005).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(chip.poll(NSPredicate(format: "value == %@", "未生效"), timeout: 5), "\(String(describing: chip.value))")
        XCTAssertTrue(reason.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(reason.label, "上游错误不能按模型、用户筛选，这里显示全部")
        expectSegments(["上游错误 6"])
        segment("用量明细").tap()
        XCTAssertTrue(reason.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// 40 §6.5 empty with conditions: 清除筛选 drops them all; the time and the segment stay.
    @MainActor func testEmptyWithConditionsClearsFiltersAndKeepsTime() {
        launchUserLogs(1)
        defer { diagnostics("logs-clear-filters") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        segment("错误请求").tap()
        let empty = element("logs.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "近 24 小时内，这些条件下没有记录")
        expectSegments(["错误请求 0"])
        let clear = app.buttons["logs.empty.clear"]
        XCTAssertTrue(clear.exists, app.debugDescription)
        clear.tap()
        XCTAssertTrue(row("errors", 2006).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("logs.chip.user").exists, app.debugDescription)
        XCTAssertFalse(empty.exists || clear.exists, app.debugDescription)
        XCTAssertTrue(segment("错误请求").isSelected, app.debugDescription)
        expectSegments(["用量明细 40", "错误请求 6", "上游错误 6"])
        XCTAssertTrue(element("logs.time").label.contains("近 24 小时"), element("logs.time").label)
    }

    /// 40 §6.5 “400 其他（参数）”: 请求参数无效 with 清除筛选, and the count it could not get reads “—”.
    @MainActor func testBadRequestShowsInvalidParametersAndClearsFilters() {
        launchUserLogs(1, arguments: [CountFixture.badRequest])
        defer { diagnostics("logs-bad-request") }
        let invalid = element("logs.invalid")
        XCTAssertTrue(invalid.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(invalid.label, "请求参数无效")
        XCTAssertFalse(app.buttons["logs.list.retry"].exists, app.debugDescription)
        expectSegments(["用量明细 —"])
        app.buttons["logs.invalid.clear"].tap()
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(invalid.waitForNonExistence(timeout: 5), app.debugDescription)
        expectSegments(["用量明细 40"])
    }

    /// Each label as a whole, e.g. “用量明细 40”; the segment is found by the title before the count.
    @MainActor private func expectSegments(_ labels: [String], file: StaticString = #filePath, line: UInt = #line) {
        for label in labels {
            let title = label.components(separatedBy: " ").first ?? label
            let item = segment(title)
            XCTAssertTrue(item.poll(NSPredicate(format: "label == %@", label), timeout: 10), "\(label)：\(item.label)", file: file, line: line)
        }
    }

    // MARK: - S4-06 自动刷新

    /// LogFixtures+Refresh.swift: `-ui-logs-live` makes N 5 and has each poll bring a usage row newer than the rest (2001, 2002…);
    /// the interval follows `-ui-logs-poll-interval`.
    private enum RefreshFixture {
        static let live = "-ui-logs-live"
        static let interval = "-ui-logs-poll-interval"
    }

    /// 40 §6.6: the polls put the new rows on top, and past N at the top the tail goes; nothing else loads.
    @MainActor func testAutoRefreshPutsNewRowsOnTopAndTrimsAtTheTop() {
        launchLogs(arguments: [RefreshFixture.live, RefreshFixture.interval, "2"])
        defer { diagnostics("logs-auto-refresh") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 2001).waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(row("usage", 2002).waitForExistence(timeout: 20), app.debugDescription)
        let shown = shownRowIDs("usage")
        XCTAssertGreaterThanOrEqual(shown.first ?? 0, 2002, "\(shown)")
        XCTAssertTrue(row("usage", 1036).pollGone(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("logs.more.loading").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThanOrEqual(shownRowIDs("usage").count, 5, app.debugDescription)
        XCTAssertFalse(element("logs.list.failure").exists, app.debugDescription)
    }

    /// 40 §6.6: scrolled down, the poll back from the background (D18; the timer is out of reach here) keeps the tail; back at
    /// the top the tail goes.
    @MainActor func testAutoRefreshHoldsTheTrimWhileScrolledDown() {
        launchLogs(arguments: [RefreshFixture.live, RefreshFixture.interval, "600"])
        defer { diagnostics("logs-auto-refresh-scrolled") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 1036).exists, app.debugDescription)
        let oldest = row("usage", 1001)
        XCTAssertTrue(app.scrollUntilExists(oldest, maxSwipes: 25))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        // The poll put 2001 on top, out of sight; the tail is still there.
        XCTAssertTrue(app.scrollUntilExists(oldest, maxSwipes: 4))
        XCTAssertTrue(app.scrollUntilExists(row("usage", 2001), towardBottom: false, maxSwipes: 20))
        XCTAssertTrue(row("usage", 1036).pollGone(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(shownRowIDs("usage").count, 5, app.debugDescription)
        XCTAssertEqual(shownRowIDs("usage").first, 2001, app.debugDescription)
    }

    /// 40 §6.6: a custom range is fixed, so nothing polls it.
    @MainActor func testCustomRangeDoesNotAutoRefresh() {
        launchLogs(arguments: [RefreshFixture.live, RefreshFixture.interval, "2"])
        defer { diagnostics("logs-auto-refresh-custom") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let time = app.buttons["logs.time"]
        openCustomRange(from: time).tap()
        XCTAssertTrue(time.poll(NSPredicate(format: "label CONTAINS %@", " – "), timeout: 10), time.label)
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let polled = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "logs.row.usage.20")).firstMatch
        XCTAssertFalse(polled.waitForExistence(timeout: 6), app.debugDescription)
    }

    /// The 自定义… sheet's 应用; a poll redrawing the list can swallow a tap on the menu, so it is tried again.
    @MainActor private func openCustomRange(from time: XCUIElement) -> XCUIElement {
        let apply = app.buttons["logs.time.custom.apply"]
        let item = app.buttons.matching(NSPredicate(format: "identifier == '' AND label == %@", "自定义…")).firstMatch
        for _ in 0..<3 where !apply.exists {
            time.tap()
            if item.waitForExistence(timeout: 3) { item.tap() }
            _ = apply.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(apply.exists, app.debugDescription)
        return apply
    }
    /// The rows on screen, top first, read from one snapshot: the polls keep changing the list.
    @MainActor private func shownRowIDs(_ scope: String) -> [Int] {
        let prefix = "logs.row.\(scope)."
        guard let tree = try? app.snapshot() else { return [] }
        var tops: [Int: CGFloat] = [:]
        var pending: [any XCUIElementSnapshot] = [tree]
        while let node = pending.popLast() {
            if node.identifier.hasPrefix(prefix), let id = Int(node.identifier.dropFirst(prefix.count)) {
                tops[id] = min(tops[id] ?? .greatestFiniteMagnitude, node.frame.minY)
            }
            pending += node.children
        }
        return tops.sorted { $0.value < $1.value }.map(\.key)
    }

    // MARK: - S4-07 按对象筛选

    /// The groups fail through the session's group directory (S2-03); search-users through LogFixtures+Picker.swift.
    private enum PickerFixture {
        static let groupsError = "-ui-account-groups-error"
        static let usersError = "-ui-logs-picker-users-error"
    }

    /// 40 §6.4: the first six accounts by name, then the groups, no users; a keyword narrows the accounts; the pick filters the
    /// list by that account (1040 is account 1's, 1039 account 4's) and its chip takes it off again.
    @MainActor func testPickerSearchesAccountFiltersListAndChipRemoves() {
        launchLogs()
        defer { diagnostics("logs-picker-account") }
        XCTAssertTrue(row("usage", 1039).waitForExistence(timeout: 10), app.debugDescription)
        let field = openPicker("logs.picker.open")
        XCTAssertTrue(app.staticTexts["按对象筛选"].exists || app.navigationBars["按对象筛选"].exists, app.debugDescription)
        for id in [1, 2, 3, 8, 11, 5] {
            XCTAssertTrue(pickerRow("account", id).waitForExistence(timeout: 10), "\(id)\n\(app.debugDescription)")
        }
        XCTAssertFalse(pickerRow("account", 10).exists, app.debugDescription)
        // The groups follow below the fold; the list makes only the rows near the screen.
        XCTAssertTrue(pickerRow("group", 1).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(anyPickerRow("user").exists, app.debugDescription)
        search(field, "官方-01")
        XCTAssertTrue(pickerRow("account", 2).pollGone(timeout: 10), app.debugDescription)
        let claude = pickerRow("account", 1)
        XCTAssertTrue(claude.exists && claude.label.contains("Claude-官方-01") && claude.label.contains("#1"), claude.label)
        pick("account", 1)
        let chip = app.buttons["logs.chip.account"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(chip.label, "账号：Claude-官方-01")
        XCTAssertTrue(row("usage", 1039).pollGone(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row("usage", 1039).waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 40 §6.4: groups match by name in the directory's order, four at most; a pick replaces the condition of its kind and keeps
    /// the others; a deleted user is marked; 关闭 changes nothing.
    @MainActor func testPickerReplacesSameKindForGroupAndUser() {
        launchLogs()
        defer { diagnostics("logs-picker-replace") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        search(openPicker("logs.chip.add"), "组")
        for id in [1, 2, 3, 5] { XCTAssertTrue(pickerRow("group", id).waitForExistence(timeout: 10), "\(id)\n\(app.debugDescription)") }
        XCTAssertFalse(pickerRow("group", 4).exists || pickerRow("group", 7).exists, app.debugDescription)
        pick("group", 1)
        let group = app.buttons["logs.chip.group"]
        XCTAssertTrue(group.poll(NSPredicate(format: "label == %@", "分组：高级组"), timeout: 10), app.debugDescription)
        search(openPicker("logs.picker.open"), "标准")
        XCTAssertTrue(pickerRow("account", 1).pollGone(timeout: 10), app.debugDescription)
        pick("group", 2)
        XCTAssertTrue(group.poll(NSPredicate(format: "label == %@", "分组：标准组"), timeout: 10), group.label)
        XCTAssertEqual(app.buttons.matching(identifier: "logs.chip.group").count, 1, app.debugDescription)
        search(openPicker("logs.picker.open"), "xm.wang")
        pick("user", 3)
        let user = app.buttons["logs.chip.user"]
        XCTAssertTrue(user.poll(NSPredicate(format: "label == %@", "用户：xm.wang@example.com"), timeout: 10), app.debugDescription)
        search(openPicker("logs.picker.open"), "alice")
        pick("user", 1)
        XCTAssertTrue(user.poll(NSPredicate(format: "label == %@", "用户：alice@example.com"), timeout: 10), user.label)
        XCTAssertEqual(app.buttons.matching(identifier: "logs.chip.user").count, 1, app.debugDescription)
        XCTAssertEqual(group.label, "分组：标准组")
        search(openPicker("logs.picker.open"), "former")
        let deleted = pickerRow("user", 27)
        XCTAssertTrue(deleted.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(deleted.label.contains("former.ops@example.com") && deleted.label.contains("已删除"), deleted.label)
        closePicker()
        XCTAssertEqual(user.label, "用户：alice@example.com")
        XCTAssertEqual(group.label, "分组：标准组")
    }

    /// 40 §6.4: each group fails on its own: the groups' failure row stays while the accounts come, and a keyword brings the
    /// users' failure row next to the matching accounts.
    @MainActor func testPickerGroupsFailAloneAndUsersRetry() {
        launchLogs(arguments: [PickerFixture.groupsError, PickerFixture.usersError])
        defer { diagnostics("logs-picker-failures") }
        XCTAssertTrue(row("usage", 1040).waitForExistence(timeout: 10), app.debugDescription)
        let field = openPicker("logs.picker.open")
        XCTAssertTrue(pickerRow("account", 1).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("logs.picker.groups.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["logs.picker.groups.retry"].exists, app.debugDescription)
        XCTAssertFalse(element("logs.picker.users.failure").exists, app.debugDescription)
        XCTAssertFalse(anyPickerRow("group").exists || anyPickerRow("user").exists, app.debugDescription)
        search(field, "Claude")
        XCTAssertTrue(element("logs.picker.users.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["logs.picker.users.retry"].exists, app.debugDescription)
        for id in [1, 2, 3] { XCTAssertTrue(pickerRow("account", id).waitForExistence(timeout: 10), "\(id)\n\(app.debugDescription)") }
        XCTAssertTrue(pickerRow("account", 8).pollGone(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("logs.picker.groups.failure").exists, app.debugDescription)
    }

    /// The sheet's search field, found by its prompt.
    @MainActor private var pickerField: XCUIElement { app.searchFields["账号名、邮箱或分组"] }
    /// The bar's filter button or the “+ 筛选” chip; returns the sheet's search field.
    @MainActor private func openPicker(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 10), app.debugDescription)
        return pickerField
    }
    @MainActor private func search(_ field: XCUIElement, _ text: String) { field.tap(); field.typeText(text) }
    @MainActor private func pickerRow(_ kind: String, _ id: Int) -> XCUIElement { app.buttons["logs.picker.\(kind).\(id)"] }
    @MainActor private func anyPickerRow(_ kind: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "logs.picker.\(kind).")).firstMatch
    }
    /// Picks the row once it is there and on screen; the sheet closes.
    @MainActor private func pick(_ kind: String, _ id: Int) {
        let item = pickerRow(kind, id)
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        reveal(item)
        item.tap()
        XCTAssertTrue(pickerField.pollGone(timeout: 10), app.debugDescription)
    }
    /// 关闭. While the search is active the bar shows the field's own close button (no identifier) instead; it comes first.
    @MainActor private func closePicker() {
        let close = app.buttons["sheet.close"]
        if !(close.exists && close.isHittable) {
            let labels = ["关闭", "Close", "取消", "Cancel"]
            let endSearch = app.buttons.matching(NSPredicate(format: "identifier == '' AND label IN %@", labels)).firstMatch
            if endSearch.exists { endSearch.tap() }
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(pickerField.pollGone(timeout: 10), app.debugDescription)
    }
}
