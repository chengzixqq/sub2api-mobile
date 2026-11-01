import XCTest

/// 40 §7 请求详情 over LogFixtures+Detail (NativeApp/Features/Logs/LogFixtures+Detail.swift): U1 = usage 1040 (two tries), U2 = 1039
/// (no chain), E1 = request error 2006 (two upstream events), R1 = upstream error 3005 (409, then the nearer id: two tries) and
/// account 7's newest upstream error 9701 (three tries, one without timings, two dropped). S4-08b adds its tests at the end.
final class RequestDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let missing = "-ui-request-detail-missing"
        static let fails = "-ui-request-detail-fails"
        static let opsDisabled = "-ui-request-detail-ops-disabled"
        /// C-0.4: a site without `ops.request_attempts` reads the detail's upstream events instead.
        static let withoutAttempts = ["-ui-without-capabilities", "ops.request_attempts"]
    }

    /// U1: the success look's amounts, timing, two tries, tokens, links and IDs; U2 has one try, so no 上游尝试.
    @MainActor func testSuccessLookShowsCostTimingTokensAndAttempts() {
        launch()
        openLogRow("usage", 1040)
        defer { diagnostics("request-detail-success") }
        let status = element("logs.detail.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isTitled("请求详情"), app.debugDescription)
        XCTAssertEqual(status.label, "成功 200")
        for (id, amount) in [("charge", "$0.0124"), ("cost", "$0.0074"), ("standard", "$0.0155")] {
            XCTAssertTrue(element("logs.detail.\(id)").label.contains(amount), element("logs.detail.\(id)").label)
        }
        XCTAssertTrue(element("logs.detail.timing.total").exists, app.debugDescription)
        XCTAssertFalse(element("logs.detail.actions").exists, app.debugDescription)
        let attempts = element("logs.detail.attempts")
        XCTAssertTrue(attempts.waitForExistence(timeout: 10), app.debugDescription)
        waitForValue(attempts, "2 次 · 返回客户端 200")
        reveal(app.buttons["logs.detail.attempt.2"])
        XCTAssertTrue(app.buttons["logs.detail.attempt.1"].label.contains("失败，切换到"), app.buttons["logs.detail.attempt.1"].label)
        XCTAssertTrue(app.buttons["logs.detail.attempt.2"].label.contains("成功，结果返回客户端"), app.buttons["logs.detail.attempt.2"].label)
        reveal(element("logs.detail.tokens.input"))
        for kind in ["user", "key", "group", "account"] { reveal(element("logs.detail.link.\(kind)")) }
        reveal(element("logs.detail.id.request"))
        XCTAssertTrue(element("logs.detail.id.upstream").exists, app.debugDescription)
        goBack()
        let second = app.buttons["logs.row.usage.1039"]
        XCTAssertTrue(second.waitForExistence(timeout: 10), app.debugDescription)
        second.tap()
        XCTAssertTrue(element("logs.detail.status").waitForExistence(timeout: 10), app.debugDescription)
        reveal(element("logs.detail.tokens.input"))
        XCTAssertFalse(element("logs.detail.attempts").exists, app.debugDescription)
    }

    /// 9701 without its row: the detail comes first, then its client request ID reads three tries; 查看账号 opens account 7.
    @MainActor func testFailedUpstreamErrorFromAccountLoadsDetailAndChain() {
        launch()
        openAccountLatestError(7)
        defer { diagnostics("request-detail-account-error") }
        let status = element("logs.detail.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isTitled("上游错误"), app.debugDescription)
        XCTAssertEqual(status.label, "失败 401")
        XCTAssertEqual(element("logs.detail.cause").label, "上游 · 上游服务商 · P1")
        XCTAssertTrue(element("logs.detail.message").label.contains("Upstream authentication failed"), element("logs.detail.message").label)
        let attempts = element("logs.detail.attempts")
        reveal(attempts)
        waitForValue(attempts, "3 次 · 返回客户端 401")
        let old = app.buttons["logs.detail.attempt.2"]
        reveal(old)
        XCTAssertTrue(old.label.contains("500 · —"), old.label)
        let dropped = element("logs.detail.attempts.dropped")
        reveal(dropped)
        XCTAssertEqual(dropped.label, "更早的 2 次尝试因队列上限没有记录")
        reveal(element("logs.detail.id.client"))
        reveal(element("logs.detail.id.upstream"))
        let viewAccount = app.buttons["logs.detail.viewAccount"]
        reveal(viewAccount, towardBottom: false)
        viewAccount.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isTitled("OpenAI-备用-A"), app.debugDescription)
    }

    /// R1: a retried 429 the client got 200 for; its request_id is ambiguous, so the nearer client request ID is read once.
    @MainActor func testRecoveredRowResolvesAmbiguousRequestID() {
        launch()
        openLogRow("upstream", 3005)
        defer { diagnostics("request-detail-recovered") }
        let status = element("logs.detail.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isTitled("上游错误"), app.debugDescription)
        XCTAssertEqual(status.label, "上游失败 429")
        XCTAssertEqual(element("logs.detail.recovery").label, "已自动重试成功，客户端收到 200")
        XCTAssertTrue(element("logs.detail.message").exists, app.debugDescription)
        let attempts = element("logs.detail.attempts")
        reveal(attempts)
        waitForValue(attempts, "2 次 · 返回客户端 200")
    }

    /// Without `ops.request_attempts` the tries come from `upstream_errors`: a missing duration is the gap since the previous one.
    @MainActor func testFallbackWithoutAttemptsCapabilityEstimatesDurations() {
        launch(arguments: Fixture.withoutAttempts)
        openAccountLatestError(7)
        defer { diagnostics("request-detail-fallback") }
        let attempts = element("logs.detail.attempts")
        XCTAssertTrue(attempts.waitForExistence(timeout: 10), app.debugDescription)
        reveal(attempts)
        waitForValue(attempts, "3 次 · 返回客户端 401")
        let estimated = app.buttons["logs.detail.attempt.2"]
        reveal(estimated)
        XCTAssertTrue(estimated.label.contains("500 · 约 "), estimated.label)
        reveal(element("logs.detail.attempts.dropped"))
        reveal(element("logs.detail.id.client"))
        XCTAssertFalse(element("logs.detail.id.upstream").exists, app.debugDescription)
    }

    /// E1 keeps its row when the detail fails; with no chain to read either, 上游尝试 says so.
    @MainActor func testDetailFailureKeepsRowAndChainUnavailable() {
        launch(arguments: [Fixture.fails] + Fixture.withoutAttempts)
        openLogRow("errors", 2006)
        defer { diagnostics("request-detail-failure") }
        XCTAssertTrue(element("logs.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("logs.detail.message").exists, app.debugDescription)
        let unavailable = element("logs.detail.attempts.unavailable")
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(unavailable.label, "没能取到重试链")
        let retry = app.buttons["logs.detail.detail.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry))
        XCTAssertTrue(element("logs.detail.detail.failure").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "详情加载失败").exists, app.debugDescription)
    }

    /// 9701 without a row: a failed detail fails the page, with 重试.
    @MainActor func testDetailFailureWithoutRowFailsThePage() {
        launch(arguments: [Fixture.fails])
        openAccountLatestError(7)
        defer { diagnostics("request-detail-page-failure") }
        XCTAssertTrue(element("logs.detail.page.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["logs.detail.page.retry"].isHittable, app.debugDescription)
        XCTAssertFalse(element("logs.detail.card").exists, app.debugDescription)
    }

    /// 404 OPS_ERROR_NOT_FOUND replaces the row with “记录不存在或已清理”; 返回 goes back to the list.
    @MainActor func testMissingRecordFillsThePage() {
        launch(arguments: [Fixture.missing])
        openLogRow("errors", 2006)
        defer { diagnostics("request-detail-gone") }
        let gone = element("logs.detail.gone")
        XCTAssertTrue(gone.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(gone.label, "记录不存在或已清理")
        XCTAssertFalse(element("logs.detail.card").exists, app.debugDescription)
        app.buttons["logs.detail.back"].tap()
        XCTAssertTrue(app.buttons["logs.row.errors.2006"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 404 OPS_DISABLED keeps the row and says why there is nothing more.
    @MainActor func testDetailOpsDisabledKeepsRowData() {
        launch(arguments: [Fixture.opsDisabled])
        openLogRow("errors", 2006)
        defer { diagnostics("request-detail-ops-disabled") }
        let notice = element("logs.detail.detailNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(notice.label, "运维监控未开启，看不到更多信息")
        XCTAssertTrue(element("logs.detail.card").exists, app.debugDescription)
        XCTAssertTrue(element("logs.detail.message").exists, app.debugDescription)
        XCTAssertFalse(element("logs.detail.detail.failure").exists, app.debugDescription)
    }

    /// 40 §7.1: 用户, 分组 and 账号 open their pages; the key opens nothing.
    @MainActor func testLinkRowsOpenUserGroupAndAccount() {
        launch()
        openLogRow("usage", 1040)
        defer { diagnostics("request-detail-links") }
        let user = app.buttons["logs.detail.link.user"]
        XCTAssertTrue(app.scrollUntilExists(user))
        XCTAssertFalse(app.buttons["logs.detail.link.key"].exists, app.debugDescription)
        XCTAssertTrue(element("logs.detail.link.key").exists, app.debugDescription)
        user.tap()
        let userPage = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["user.detail", "user.detail.not-found"])).firstMatch
        XCTAssertTrue(userPage.waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        let group = app.buttons["logs.detail.link.group"]
        XCTAssertTrue(app.scrollUntilExists(group))
        group.tap()
        XCTAssertTrue(group.waitForNonExistence(timeout: 10), app.debugDescription)
        goBack()
        let account = app.buttons["logs.detail.link.account"]
        XCTAssertTrue(app.scrollUntilExists(account))
        account.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isTitled("Claude-官方-01"), app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to the fixture site “请求详情验收”.
    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10), app.debugDescription)
        enter("请求详情验收", field: app.textFields["login.name"])
        enter("https://request-detail.example.invalid", field: app.textFields["login.url"])
        enter("admin@example.invalid", field: app.textFields["login.email"])
        enter("fixture-password", field: app.secureTextFields["login.password"])
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// 使用记录 from the search directory, the scope's segment (its label starts with the title, S4-05b adds the count), then the row.
    @MainActor private func openLogRow(_ scope: String, _ id: Int) {
        app.openSearchItem("search.item.usage")
        let titles = ["usage": "用量明细", "errors": "错误请求", "upstream": "上游错误"]
        if scope != "usage", let title = titles[scope] {
            let mode = app.segmentedControls["logs.mode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription)
            mode.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.tap()
        }
        let row = app.buttons["logs.row.\(scope).\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(row)
        row.tap()
    }
    /// 账号 tab → the account → 最近上游错误 on its status card (the route carries only the id).
    @MainActor private func openAccountLatestError(_ accountID: Int) {
        app.tabBars.buttons["账号"].tap()
        let row = app.buttons["account.\(accountID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        let latest = app.buttons["account.status.lastUpstreamError"]
        XCTAssertTrue(latest.waitForExistence(timeout: 10), app.debugDescription)
        reveal(latest, towardBottom: false)
        latest.tap()
    }
    /// The titled page; with a subtitle the bar may expose the title only as its text.
    @MainActor private func isTitled(_ title: String) -> Bool {
        app.navigationBars[title].waitForExistence(timeout: 5) || app.navigationBars.staticTexts[title].exists
    }
    @MainActor private func waitForValue(_ item: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: 10), .completed, "\(String(describing: item.value))\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func enter(_ text: String, field: XCUIElement) { reveal(field); field.tap(); field.typeText(text) }
    /// Lists create rows as they scroll in; the drag stays between the bars, and the list settles before a tap.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveTabBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20
                : app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private func isAboveTabBar(_ item: XCUIElement) -> Bool {
        let bar = app.tabBars.firstMatch
        return !bar.exists || item.frame.maxY <= bar.frame.minY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
