import XCTest

/// 10 §3 the alert detail over LiveOpsFixtures (S1-12). Shared by S1-16 and S1-17: the helpers stay at the top, each item appends
/// its own tests and helpers at the end of the class.
final class AlertDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// LiveOpsFixtureIDs and the fixtures' words (来源 LiveOpsFixtureIDs; the UI tests cannot import the App, so change both together):
    /// #41 P1 标准组错误率 5.2% (group 2 标准组: 1 of 2 available, #7 in error), #40 P2 Anthropic 上游错误率, silenced.
    private enum Fixture {
        static let alertA = "alert-41"
        static let alertB = "alert-40"
        static let gone = "-ui-alert-gone"
        static let opsOff = "-ui-alert-detail-ops-disabled"
        static let legacySilence = "-ui-alert-legacy-silence"
        static let withoutDetails = ["-ui-without-capabilities", "ops.alert_event_details"]
    }

    // MARK: Helpers

    /// Email and password sign-in with `-ui-testing` and `arguments`.
    @MainActor private func launchAndLogin(arguments: [String] = []) {
        launch(arguments)
        enter("告警站点", in: "login.name")
        enter("https://alerts.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        submit()
    }
    /// The access-token method with a `sat_` key; `-ui-readonly-token` makes it read-only.
    @MainActor private func launchAndLoginWithAccessToken(arguments: [String]) {
        launch(arguments)
        enter("令牌告警", in: "login.name")
        enter("https://alerts-token.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-alerts", in: "login.key")
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
    @MainActor private func text(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor @discardableResult
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [shown], timeout: timeout) == .completed
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
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    /// The overview's alert row (`home.attention.alert-<id>`, S1-10) once home's first read listed it.
    @MainActor private func homeRow(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = element("home.attention." + id)
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        reveal(row, file: file, line: line)
        return row
    }
    /// Opens the alert from the overview and waits for its page: the status card, or `waitFor` when the page shows something else.
    @MainActor private func openAlert(_ id: String, waitFor identifier: String = "alert.detail.status", file: StaticString = #filePath,
                                      line: UInt = #line) {
        homeRow(id, file: file, line: line).tap()
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(isAlertPage, app.debugDescription, file: file, line: line)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected, file: file, line: line)
    }
    /// The page titled “告警”; with a subtitle the bar may expose the title only as its text.
    @MainActor private var isAlertPage: Bool { app.navigationBars["告警"].exists || app.navigationBars.staticTexts["告警"].exists }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    /// A button of the system alert or action sheet, by its title (their buttons do not always carry the identifier).
    @MainActor private func dialogButton(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch }
    @MainActor private func assertSelected(tab title: String, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: app.tabBars.buttons[title])
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }

    // MARK: S1-12 告警详情

    /// 10 §3.3: the status card, 壹 范围 (标准组 from status-summary) and 贰 规则 of a firing group alert.
    @MainActor func testHomeAlertRowOpensDetailWithStatusCardScopeAndRule() {
        launchAndLogin()
        defer { diagnostics("alert-detail-final") }
        openAlert(Fixture.alertA)
        XCTAssertEqual(element("alert.detail.badge").label, "告警中")
        let cause = element("alert.detail.cause").label
        XCTAssertTrue(cause.hasPrefix("P1 · ") && cause.hasSuffix(" 触发"), cause)
        XCTAssertEqual(element("alert.detail.ruleName").label, "标准组错误率")
        XCTAssertEqual(element("alert.detail.metric").label, "5.2%")
        XCTAssertEqual(element("alert.detail.threshold").label, "阈值 5.0% · 近 5 分钟")
        XCTAssertFalse(element("alert.detail.silenceNote").exists)
        XCTAssertTrue(element("alert.detail.resolve").exists, app.debugDescription)
        XCTAssertEqual(element("alert.detail.silence").label, "静默…")
        let subtitle = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "P1 · 分组 · 标准组")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), app.debugDescription)
        let group = element("alert.detail.scope.group")
        XCTAssertTrue(waitForLabel(group, containing: "1/2 可用"), group.label)
        for part in ["标准组", "OpenAI · 1 个账号受影响"] { XCTAssertTrue(group.label.contains(part), group.label) }
        diagnostics("alert-detail")
        let condition = element("alert.detail.rule.condition")
        reveal(condition)
        XCTAssertTrue(condition.label.contains("错误率 > 5.0%"), condition.label)
        XCTAssertTrue(element("alert.detail.rule.window").label.contains("5 分钟"), element("alert.detail.rule.window").label)
        XCTAssertTrue(element("alert.detail.rule.severity").label.contains("P1"), element("alert.detail.rule.severity").label)
        XCTAssertTrue(element("alert.detail.rule.fired").label.contains("今天"), element("alert.detail.rule.fired").label)
        XCTAssertFalse(element("alert.detail.rule.ended").exists)
    }

    /// 10 §7.1: 手动解决 asks first, then the receipt (no undo), the card says how it ended, and the overview's row is gone.
    @MainActor func testManualResolveShowsReceiptAndClearsHomeRow() {
        launchAndLogin()
        defer { diagnostics("alert-detail-resolve-final") }
        openAlert(Fixture.alertA)
        element("alert.detail.resolve").tap()
        let alert = app.alerts["手动解决这条告警？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["手动解决"].firstMatch.tap()
        let receipt = element("receipt.text")
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(receipt.label, "已手动解决")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(waitForLabel(element("alert.detail.badge"), containing: "已手动解决"), app.debugDescription)
        XCTAssertTrue(element("alert.detail.resolve").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element("alert.detail.silence").exists)
        XCTAssertTrue(waitForLabel(element("alert.detail.endNote"), containing: "由 admin 手动解决"), app.debugDescription)
        let ended = element("alert.detail.rule.ended")
        reveal(ended)
        XCTAssertTrue(ended.label.contains("今天"), ended.label)
        goBack()
        XCTAssertTrue(homeRow(Fixture.alertB).exists, app.debugDescription)
        XCTAssertFalse(element("home.attention." + Fixture.alertA).exists, app.debugDescription)
    }

    /// 10 §7.1: 静默 1 小时 shows its time on the card and a receipt with 撤销, which ends the silence again.
    @MainActor func testSilenceOneHourShowsUndoAndUndoRestores() {
        launchAndLogin()
        defer { diagnostics("alert-detail-silence-final") }
        openAlert(Fixture.alertA)
        element("alert.detail.silence").tap()
        let hour = dialogButton("静默 1 小时")
        XCTAssertTrue(hour.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "静默这条规则多久？").exists, app.debugDescription)
        hour.tap()
        let undo = app.buttons["receipt.action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("receipt.text").label, "已静默 1 小时")
        XCTAssertEqual(undo.label, "撤销")
        undo.tap()
        XCTAssertTrue(element("alert.detail.silenceNote").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(element("alert.detail.silence"), containing: "静默…"), app.debugDescription)
        XCTAssertFalse(element("alert.detail.silence").label.contains("改静默时长"), element("alert.detail.silence").label)
    }

    /// The silence shows on the card, and the silenced alert's button opens 改静默时长 with 结束静默.
    @MainActor func testSilenceNoteAndChangeSilenceDialogWithEndSilence() {
        launchAndLogin()
        defer { diagnostics("alert-detail-change-silence-final") }
        openAlert(Fixture.alertB)
        let note = element("alert.detail.silenceNote")
        XCTAssertTrue(note.label.hasPrefix("⌛ 已静默至 "), note.label)
        XCTAssertEqual(element("alert.detail.silence").label, "改静默时长…")
        element("alert.detail.silence").tap()
        XCTAssertTrue(dialogButton("结束静默").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "改静默时长").exists, app.debugDescription)
        for title in ["静默 1 小时", "静默 24 小时", "静默 7 天"] { XCTAssertTrue(dialogButton(title).exists, title) }
    }

    /// S1D1-15: events without the `silence` key offer only 手动解决.
    @MainActor func testLegacySilenceFixtureOffersOnlyResolve() {
        launchAndLogin(arguments: [Fixture.legacySilence])
        defer { diagnostics("alert-detail-legacy-silence-final") }
        openAlert(Fixture.alertA)
        XCTAssertTrue(element("alert.detail.resolve").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.silence").exists, app.debugDescription)
    }

    /// 10 §3.5, §7.2: ops monitoring found off shows the empty state with its switch; turning it on brings the alert back.
    @MainActor func testOpsDisabledReplyShowsNoticeAndEnablingReadsAgain() {
        launchAndLogin(arguments: [Fixture.opsOff])
        defer { diagnostics("alert-detail-ops-disabled-final") }
        openAlert(Fixture.alertA, waitFor: "ops.disabled.empty")
        XCTAssertTrue(text(containing: "运维监控未开启").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "关闭期间不会记录错误请求").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.status").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.rule.condition").exists, app.debugDescription)
        let enable = element("ops.disabled.enable")
        XCTAssertTrue(enable.exists, app.debugDescription)
        enable.tap()
        let confirm = app.alerts["开启运维监控？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.buttons["开启"].firstMatch.tap()
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 15), app.debugDescription)
    }

    /// 10 §3.5: a gone event is an empty state; 「返回」 goes back to the overview.
    @MainActor func testMissingAlertShowsEmptyStateAndBackReturnsHome() {
        launchAndLogin(arguments: [Fixture.gone])
        defer { diagnostics("alert-detail-gone-final") }
        openAlert(Fixture.alertA, waitFor: "alert.detail.notFound")
        XCTAssertTrue(text(containing: "这条告警不存在或已被清理").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.status").exists, app.debugDescription)
        element("alert.detail.back").tap()
        XCTAssertTrue(element("home.attention").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(isAlertPage, app.debugDescription)
    }

    /// 10 §3.1: the group row pushes the group, the platform's channel row opens 监控 · 渠道.
    @MainActor func testScopeRowsLeaveForGroupAndMonitorChannels() {
        launchAndLogin()
        defer { diagnostics("alert-detail-scope-final") }
        openAlert(Fixture.alertA)
        let group = element("alert.detail.scope.group")
        XCTAssertTrue(waitForLabel(group, containing: "1/2 可用"), group.label)
        group.tap()
        XCTAssertTrue(element("alert.detail.badge").waitForNonExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(element("alert.detail.badge").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        openAlert(Fixture.alertB)
        let channel = element("alert.detail.scope.channel")
        XCTAssertTrue(waitForLabel(channel, containing: "2 个分组渠道"), channel.label)
        XCTAssertTrue(channel.label.contains("Anthropic 渠道") && channel.label.contains("可用"), channel.label)
        channel.tap()
        assertSelected(tab: "监控")
        let segment = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment.segment("渠道").isSelected, app.debugDescription)
    }

    /// S1D1-16: a server without `ops.alert_event_details` sends no rule or group name; the detail still reads them.
    @MainActor func testOldServerDetailGetsRuleAndGroupName() {
        launchAndLogin(arguments: Fixture.withoutDetails)
        defer { diagnostics("alert-detail-old-server-final") }
        openAlert(Fixture.alertA)
        XCTAssertTrue(waitForLabel(element("alert.detail.ruleName"), containing: "标准组错误率"), app.debugDescription)
        XCTAssertEqual(element("alert.detail.threshold").label, "阈值 5.0% · 近 5 分钟")
        let subtitle = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "分组 · 标准组")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), app.debugDescription)
        let condition = element("alert.detail.rule.condition")
        reveal(condition)
        XCTAssertTrue(condition.label.contains("错误率 > 5.0%"), condition.label)
        XCTAssertTrue(element("alert.detail.rule.window").label.contains("5 分钟"), element("alert.detail.rule.window").label)
    }

    /// C-1: a read-only token sees both buttons greyed, with 只读令牌 under them.
    @MainActor func testReadOnlyTokenGreysOutActions() {
        launchAndLoginWithAccessToken(arguments: ["-ui-readonly-token"])
        defer { diagnostics("alert-detail-readonly-final") }
        openAlert(Fixture.alertA)
        XCTAssertFalse(element("alert.detail.resolve").isEnabled, app.debugDescription)
        XCTAssertFalse(element("alert.detail.silence").isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }

    // MARK: S1-16 从监控 · 告警进入

    /// 10 §6.1: a row of 监控 · 告警 opens the alert on the monitor tab's own stack; back returns to the segment.
    @MainActor func testAlertsSegmentRowOpensDetail() {
        launchAndLogin()
        defer { diagnostics("alert-detail-from-monitor-final") }
        app.tabBars.buttons["监控"].tap()
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription)
        segments.segment("告警").tap()
        let row = app.buttons["monitor.alerts.row.41"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(isAlertPage, app.debugDescription)
        XCTAssertEqual(element("alert.detail.ruleName").label, "标准组错误率")
        assertSelected(tab: "监控")
        goBack()
        XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segments.segment("告警").isSelected, app.debugDescription)
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: S1-17 错误请求计数

    /// 来源 LiveOpsFixtureIDs / LiveOpsFixtures+AlertDetail.swift: 标准组 is group 2; its 近 24 小时 counts 37 failed requests,
    /// the whole site 128.
    private enum ErrorCount {
        static let standardGroup = 2
        static let siteWide = "-ui-alert-site-wide"
        static let fails = "-ui-alert-error-count-fails"
    }

    /// 10 §3.3: under 标准组 the 错误请求 row counts the last 24 hours and opens the group's failed requests.
    @MainActor func testErrorCountRowShowsCountAndOpensErrorLogs() {
        launchAndLogin()
        defer { diagnostics("alert-detail-error-count-final") }
        openAlert(Fixture.alertA)
        let group = element("alert.detail.scope.group"), errors = element("alert.detail.scope.errors")
        XCTAssertTrue(errors.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(errors, containing: "近 24 小时 37 条"), errors.label)
        XCTAssertTrue(errors.label.contains("错误请求"), errors.label)
        XCTAssertGreaterThan(errors.frame.minY, group.frame.minY, app.debugDescription)
        reveal(errors)
        errors.tap()
        assertErrorLogsOpened(groupID: ErrorCount.standardGroup)
        goBack()
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 10 §3.3: a site-wide error rule counts the whole site under 全站, and its logs carry no group.
    @MainActor func testSiteWideErrorAlertCountsWithoutGroupFilter() {
        launchAndLogin(arguments: [ErrorCount.siteWide])
        defer { diagnostics("alert-detail-error-count-site-final") }
        openAlert(Fixture.alertA)
        let site = element("alert.detail.scope.site")
        XCTAssertTrue(site.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(site.label.contains("全站") && site.label.contains("监控 · 概况"), site.label)
        XCTAssertFalse(element("alert.detail.scope.group").exists, app.debugDescription)
        let errors = element("alert.detail.scope.errors")
        XCTAssertTrue(errors.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(errors, containing: "近 24 小时 128 条"), errors.label)
        XCTAssertTrue(errors.label.contains("错误请求"), errors.label)
        reveal(errors)
        errors.tap()
        assertErrorLogsOpened(groupID: nil)
    }

    /// 10 §3.5: a failed count fails only its row; 「重试」 reads just the count.
    @MainActor func testErrorCountFailureRetriesOnlyThatRow() {
        launchAndLogin(arguments: [ErrorCount.fails])
        defer { diagnostics("alert-detail-error-count-failure-final") }
        openAlert(Fixture.alertA)
        let failure = element("alert.detail.scope.errors.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "错误请求 · 加载失败").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.scope.errors").exists, app.debugDescription)
        XCTAssertTrue(element("alert.detail.status").exists, app.debugDescription)
        XCTAssertTrue(waitForLabel(element("alert.detail.scope.group"), containing: "1/2 可用"), app.debugDescription)
        let retry = element("alert.detail.scope.errors.retry")
        reveal(retry)
        retry.tap()
        let errors = element("alert.detail.scope.errors")
        XCTAssertTrue(errors.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(errors, containing: "近 24 小时 37 条"), errors.label)
        XCTAssertFalse(failure.exists, app.debugDescription)
        let condition = element("alert.detail.rule.condition")
        reveal(condition)
        XCTAssertTrue(condition.label.contains("错误率 > 5.0%"), condition.label)
    }

    /// 10 §3.3: a platform alert has its channel row and no error count.
    @MainActor func testPlatformAlertHasNoErrorCountRow() {
        launchAndLogin()
        defer { diagnostics("alert-detail-error-count-platform-final") }
        openAlert(Fixture.alertB)
        XCTAssertTrue(waitForLabel(element("alert.detail.scope.channel"), containing: "Anthropic 渠道"), app.debugDescription)
        XCTAssertFalse(element("alert.detail.scope.errors").exists, app.debugDescription)
        XCTAssertFalse(element("alert.detail.scope.errors.failure").exists, app.debugDescription)
    }

    /// The log page the row opened. Until S4-05 it is the old 请求与错误日志 with 失败请求 selected and the group as “分组 #<id>”;
    /// S4-05's 使用记录 replaces this check.
    @MainActor private func assertErrorLogsOpened(groupID: Int?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("alert.detail.badge").waitForNonExistence(timeout: 10), app.debugDescription, file: file, line: line)
        let old = app.navigationBars["请求与错误日志"]
        XCTAssertTrue(old.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        let mode = app.segmentedControls["logs.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(mode.buttons["失败请求"].isSelected, app.debugDescription, file: file, line: line)
        if let groupID {
            XCTAssertTrue(text(containing: "分组 #\(groupID)").waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        } else {
            XCTAssertFalse(text(containing: "分组 #").exists, app.debugDescription, file: file, line: line)
        }
    }
}
