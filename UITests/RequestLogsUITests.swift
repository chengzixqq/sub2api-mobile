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
        XCTAssertFalse(element("logs.empty.clear").exists, app.debugDescription)
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

    /// 40 §6.1: a row opens its request (the old details until S4-08) and the list is kept on return.
    @MainActor func testRowsOpenRequestDetails() {
        launchLogs()
        defer { diagnostics("logs-open-detail") }
        let newest = row("usage", 1040)
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        newest.tap()
        let charge = element("logs.detail.charge")
        XCTAssertTrue(charge.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(charge.label.contains("$0.0124"), charge.label)
        goBack()
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment("用量明细").isSelected, app.debugDescription)
        segment("错误请求").tap()
        let error = row("errors", 2006)
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        error.tap()
        XCTAssertTrue(element("logs.detail.message").waitForExistence(timeout: 10), app.debugDescription)
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
}
