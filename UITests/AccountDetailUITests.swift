import XCTest

/// 20 §2 account detail top half (S2-08) on the fixture site's demo accounts (DemoData+Accounts). Most tests add
/// -ui-accounts-long-windows so the timed windows and model limits hold through a slow run.
final class AccountDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "账号详情站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let detailError = "-ui-account-detail-error"
        static let removed = "-ui-account-removed"
        static let slowDetail = "-ui-account-detail-slow"
        static let groupTransition = "-ui-account-group-transition"
        static let opsDisabled = "-ui-ops-disabled"
        static let todayThrottled = "-ui-account-today-throttled"
        static let errorSummary = "401 凭据已失效（invalid_api_key）"
    }

    /// Claude-官方-03 is rate limited with two model limits; its switch is on.
    @MainActor func testRateLimitedAccountShowsCountdownResumeTimeAndModelLimits() {
        openDetail(3)
        defer { diagnostics("account-detail-limited-final") }
        XCTAssertEqual(element("account.detail.card.title").label, "限流中")
        XCTAssertEqual(element("account.detail.card.cause").label, "上游 429")
        let countdown = element("account.detail.countdown")
        XCTAssertTrue(countdown.exists, app.debugDescription)
        XCTAssertNotNil(countdown.label.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression), countdown.label)
        let resume = element("account.detail.resume-note").label
        XCTAssertNotNil(resume.range(of: #"^后自动恢复 · 预计 \d{2}:\d{2}$"#, options: .regularExpression), resume)
        XCTAssertEqual(element("account.detail.model-limits.title").label, "模型限流 2")
        for model in ["claude-opus-4", "claude-sonnet-4-5"] {
            let row = element("account.detail.model-limit.\(model)")
            XCTAssertTrue(row.exists, app.debugDescription)
            XCTAssertTrue(row.label.contains(model) && row.label.hasSuffix("后"), row.label)
        }
        let recover = app.buttons["account.action.recover"], test = app.buttons["account.action.test"], stop = app.buttons["account.action.stop"]
        for button in [recover, test, stop] { XCTAssertTrue(button.exists && button.isHittable, app.debugDescription) }
        XCTAssertLessThan(recover.frame.minX, test.frame.minX)
        XCTAssertLessThan(test.frame.minX, stop.frame.minX)
        diagnostics("account-detail-limited")
    }

    /// OpenAI-备用-A has an auth error and was stopped when it failed: the fix leads, then 恢复状态 and 测试连接.
    @MainActor func testCredentialErrorAccountLeadsWithReplaceKey() {
        openDetail(7)
        defer { diagnostics("account-detail-credential-final") }
        XCTAssertEqual(element("account.detail.card.title").label, "错误")
        XCTAssertEqual(element("account.detail.error-body").label, Fixture.errorSummary)
        XCTAssertTrue(element("account.detail.schedule-note").label.contains("出错时已自动停止调度"), app.debugDescription)
        let fix = app.buttons["account.action.replaceKey"], recover = app.buttons["account.action.recover"], test = app.buttons["account.action.test"]
        for button in [fix, recover, test] { XCTAssertTrue(button.exists, app.debugDescription) }
        XCTAssertEqual(fix.label, "更换 API Key…")
        XCTAssertLessThan(fix.frame.minX, recover.frame.minX)
        XCTAssertLessThan(recover.frame.minX, test.frame.minX)
        XCTAssertFalse(app.buttons["account.action.stop"].exists || app.buttons["account.action.resume"].exists, app.debugDescription)
        diagnostics("account-detail-credential")
        // S2-16: the fix opens the 更换 API Key sheet.
        fix.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("account.cred.target").label, "OpenAI-备用-A · 点按底部按钮后立即生效")
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 5), app.debugDescription)
    }

    /// Gemini-测试-B has its switch off: 启用调度 leads, its receipt offers 撤销, and 撤销 pauses it again.
    @MainActor func testPausedAccountEnableSchedulingReceiptAndUndo() {
        openDetail(5)
        defer { diagnostics("account-detail-resume-final") }
        let title = element("account.detail.card.title")
        XCTAssertEqual(title.label, "暂停 · 不参与调度")
        app.buttons["account.action.resume"].tap()
        waitForReceipt("已启用调度")
        XCTAssertTrue(app.buttons["account.action.stop"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "正常 · 参与调度")
        app.buttons.matching(NSPredicate(format: "identifier == 'receipt.action' AND label == '撤销'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["account.action.resume"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "暂停 · 不参与调度")
    }

    /// 20 §5.3: an account stopped by its error may recover with or without scheduling.
    @MainActor func testRecoverDialogOffersBothChoicesWhenSchedulingIsOff() {
        openDetail(7)
        defer { diagnostics("account-detail-recover-two-final") }
        app.buttons["account.action.recover"].tap()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(dialogButton("只恢复状态（保持暂停）").exists, app.debugDescription)
        diagnostics("account-detail-recover-two")
        dismissDialog()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "错误")
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
    }

    @MainActor func testRecoverDialogSingleChoiceWhenSchedulingIsOn() {
        openDetail(3)
        defer { diagnostics("account-detail-recover-one-final") }
        app.buttons["account.action.recover"].tap()
        XCTAssertTrue(dialogButton("恢复状态").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(dialogButton("恢复并启用调度").exists, app.debugDescription)
        dismissDialog()
        XCTAssertTrue(app.buttons["account.action.recover"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// 20 §2.5: a failed GET :id keeps the list's snapshot on screen under the banner.
    @MainActor func testSnapshotBannerWhenDetailReadFails() {
        openDetail(1, arguments: [Fixture.detailError])
        defer { diagnostics("account-detail-snapshot-final") }
        XCTAssertTrue(element("account.detail.snapshot-banner").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("读取最新数据失败，显示的是列表里的快照").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.action.test"].exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
        diagnostics("account-detail-snapshot")
        app.buttons["account.detail.snapshot-banner.retry"].tap()
        XCTAssertTrue(element("account.detail.snapshot-banner").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.detail.card").exists, app.debugDescription)
    }

    /// 404 ACCOUNT_NOT_FOUND: the whole page says so.
    @MainActor func testRemovedAccountReplacesWholePage() {
        launchAndOpenAccounts(arguments: [Fixture.removed])
        let row = app.buttons["account.1"]
        reveal(row)
        row.tap()
        defer { diagnostics("account-detail-removed-final") }
        let removed = element("account.detail.removed")
        XCTAssertTrue(removed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(removed.label, "这个账号已删除。")
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["account.detail.more"].exists, app.debugDescription)
    }

    /// AccountDestination(id:) (the request detail's “查看账号”) opens the new page with only the id.
    @MainActor func testDetailOpenedFromRequestLogUsesNewScreen() {
        openAccountFromRequestLog()
        defer { diagnostics("account-detail-from-log-final") }
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
    }

    @MainActor func testDetailOpenedByIDShowsFailurePageWhenReadFails() {
        openAccountFromRequestLog(arguments: [Fixture.detailError])
        defer { diagnostics("account-detail-by-id-failure-final") }
        XCTAssertTrue(element("account.detail.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("读取账号失败").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.detail.retry"].isHittable, app.debugDescription)
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
    }

    /// The sections edit the account (S2-10), so ⋯ has no 编辑账号: 在 Web 中编辑 and 删除账号… last (S2-11), after the credential
    /// items (S2-16), whose 刷新令牌 runs at once.
    @MainActor func testMoreMenuKeepsTransitionalItems() {
        openDetail(4)
        defer { diagnostics("account-detail-more-final") }
        XCTAssertTrue(app.buttons["account.section.basic.edit"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("在 Web 中编辑").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(menuButton("删除账号…").exists, app.debugDescription)
        XCTAssertFalse(menuButton("刷新令牌").exists, app.debugDescription)
        XCTAssertFalse(menuButton("编辑账号").exists, app.debugDescription)
        menuButton("在 Web 中编辑").tap()
        waitForReceipt("已在浏览器打开「OpenAI-主力-01」的编辑页")
        goBack()
        let row = app.buttons["account.1"]
        reveal(row, towardBottom: false)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("刷新令牌").waitForExistence(timeout: 5), app.debugDescription)
        let order = ["刷新令牌", "在 Web 中编辑", "删除账号…"].map { menuButton($0).frame.minY }
        XCTAssertEqual(order, order.sorted(), app.debugDescription)
        XCTAssertFalse(menuButton("编辑账号").exists, app.debugDescription)
        menuButton("刷新令牌").tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(receipt.label.hasPrefix("已刷新令牌 · 新令牌 "), receipt.label)
    }

    /// S2D1-18: the group page's transitional account list pushes the detail itself, and going back stays in that list.
    @MainActor func testGroupTransitionRowOpensDetailAndBackReturnsToGroupAccounts() {
        launchAndLogin(arguments: [Fixture.groupTransition])
        defer { diagnostics("account-detail-group-transition-final") }
        app.openSearchItem("search.item.groups")
        let group = app.buttons["group.10"]
        XCTAssertTrue(group.waitForExistence(timeout: 10), app.debugDescription)
        group.tap()
        let entry = app.buttons["group.accounts"]
        app.scrollUntilExists(entry)
        entry.tap()
        let row = app.buttons["account.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["OpenAI-主力-01"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
    }

    /// The first GET :id is still out (eight seconds here) when the recover dialog covers the page and cancels it: once the
    /// dialog closes it goes out again at once, so its failure shows seconds later, not after the 60-second refresh.
    @MainActor func testFirstReadCancelledByDialogIsSentAgainWhenPageIsBack() {
        openDetail(7, arguments: [Fixture.slowDetail, Fixture.detailError])
        defer { diagnostics("account-detail-cancelled-read-final") }
        let banner = element("account.detail.snapshot-banner")
        app.buttons["account.action.recover"].tap()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(banner.exists, "the first read answered before the dialog covered the page\n\(app.debugDescription)")
        dismissDialog()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(banner.waitForExistence(timeout: 20), app.debugDescription)
    }

    // MARK: - 容量 · 今日 · 记录（S2-09）

    /// Claude-官方-01: 容量 with its counts, notes and 5-hour window, 今日's three amounts; OpenAI-主力-01: a daily quota only.
    @MainActor func testCapacityAndTodayShowAccountFigures() {
        openDetail(1)
        defer { diagnostics("account-detail-sections-final") }
        let header = element("account.capacity.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        waitForValue(header, containing: ["更新于 "])
        waitForValue(element("account.capacity.concurrency"), containing: ["2/4"])
        waitForValue(element("account.capacity.rpm"), containing: ["14/60", "自然分钟"])
        waitForValue(element("account.capacity.sessions"), containing: ["2/3", "空闲 5 分钟释放"])
        waitForValue(element("account.capacity.fiveHour"), containing: ["42.0%", "重置"])
        let actual = element("account.today.actual")
        reveal(actual)
        waitForValue(actual, equals: "$409.38")
        let figures = ["cost": "$162.42", "standard": "$511.73", "requests": "4,418", "tokens": "27.3M"]
        for (id, expected) in figures { XCTAssertEqual(element("account.today.\(id)").value as? String, expected, id) }
        XCTAssertEqual(element("account.today.footnote").label, "账号成本与标准只按真实上游调用计算；实际扣费还含合并探测的跟随请求。")
        diagnostics("account-detail-sections")
        goBack()
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        XCTAssertTrue(app.navigationBars["OpenAI-主力-01"].waitForExistence(timeout: 10), app.debugDescription)
        waitForValue(element("account.capacity.dailyQuota"), containing: ["$96.30 / $150.00"])
        for id in ["rpm", "sessions", "fiveHour"] { XCTAssertFalse(element("account.capacity.\(id)").exists, id) }
    }

    /// 记录's rows open the log page filtered by this account (the old page until S4-05).
    @MainActor func testRecordsRowsOpenLogsFilteredByAccount() {
        openDetail(1)
        defer { diagnostics("account-detail-records-final") }
        let upstream = app.buttons["account.records.upstream"]
        reveal(upstream)
        waitForValue(upstream, equals: "近 24 小时 0 条")
        upstream.tap()
        assertLogsMode("上游错误")
        XCTAssertTrue(element("logs.account-filter").label.contains("#1"), app.debugDescription)
        goBack()
        let usage = app.buttons["account.records.usage"]
        reveal(usage)
        usage.tap()
        assertLogsMode("请求记录")
        XCTAssertTrue(element("logs.account-filter").label.contains("#1"), app.debugDescription)
    }

    /// OpenAI-备用-A is in error: the card's newest upstream error opens that request (a placeholder until S4-05 / S4-08).
    @MainActor func testErrorAccountLatestUpstreamErrorOpensRequestRoute() {
        openDetail(7)
        defer { diagnostics("account-detail-last-upstream-final") }
        let latest = app.buttons["account.status.lastUpstreamError"]
        XCTAssertTrue(latest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(latest.label.hasPrefix("最近上游错误 ") && latest.label.hasSuffix(" · 401"), latest.label)
        XCTAssertFalse(element("account.status.erroredAt").exists, app.debugDescription)
        let upstream = app.buttons["account.records.upstream"]
        reveal(upstream)
        waitForValue(upstream, equals: "近 24 小时 3 条")
        diagnostics("account-detail-last-upstream")
        reveal(latest, towardBottom: false)
        latest.tap()
        XCTAssertTrue(element("route.placeholder").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["请求详情"].exists, app.debugDescription)
    }

    /// U22: with ops monitoring off the card says when the account failed, without a link, and 记录 says so but still opens.
    @MainActor func testOpsDisabledShowsNoticeRowAndErroredAtLine() {
        openDetail(7, arguments: [Fixture.opsDisabled])
        defer { diagnostics("account-detail-ops-disabled-final") }
        let erroredAt = element("account.status.erroredAt")
        XCTAssertTrue(erroredAt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(erroredAt.label.hasPrefix("出错于 ") && erroredAt.label.hasSuffix(" · 401"), erroredAt.label)
        XCTAssertFalse(app.buttons["account.status.lastUpstreamError"].exists, app.debugDescription)
        let upstream = app.buttons["account.records.upstream"]
        reveal(upstream)
        waitForValue(upstream, equals: "运维监控未开启")
        diagnostics("account-detail-ops-disabled")
        upstream.tap()
        assertLogsMode("上游错误")
    }

    /// The first today-stats read answers 429 (retry_after 8): C-5's failure row counts down with 重试 greyed out, then today is
    /// read again by itself (X37, S2-23).
    @MainActor func testTodayThrottleCountsDownThenRetriesAutomatically() {
        openDetail(1, arguments: [Fixture.todayThrottled])
        defer { diagnostics("account-detail-today-throttled-final") }
        let retry = app.buttons["account.today.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(retry.isEnabled, app.debugDescription)
        let failure = element("account.today.failure")
        let notice = failure.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "请求过于频繁，")).firstMatch
        XCTAssertTrue(notice.exists && notice.label.hasSuffix("秒后自动重试"), app.debugDescription)
        let actual = element("account.today.actual")
        XCTAssertEqual(actual.value as? String, "无数据")
        diagnostics("account-detail-today-throttled")
        waitForValue(actual, equals: "$409.38", timeout: 20)
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    // MARK: - 基础 · 调度（S2-10）

    /// OpenAI-主力-01's rows as the fixture holds them; an OAuth account has no 配额, a stopped one reads 停用.
    @MainActor func testBasicAndScheduleSectionsShowReadOnlyValues() {
        openDetail(4)
        defer { diagnostics("account-detail-edit-sections-final") }
        let name = element("account.basic.name")
        reveal(name)
        waitForValue(name, equals: "OpenAI-主力-01")
        XCTAssertEqual(element("account.basic.status").value as? String, "正常")
        XCTAssertEqual(element("account.basic.platform").value as? String, "OpenAI · API Key")
        XCTAssertEqual(element("account.basic.notes").value as? String, "无数据")
        // Top to bottom: reveal only scrolls down, and 凭据 (S2-16) below 调度 lets a drag carry an earlier row off the screen.
        let expected: KeyValuePairs = ["concurrency": "8", "priority": "1", "loadFactor": "默认", "groups": "标准组", "expiry": "不过期",
                                       "quota.daily": "$150.00"]
        for (id, value) in expected {
            let row = element("account.sched.\(id)")
            reveal(row)
            XCTAssertEqual(row.value as? String, value, id)
        }
        XCTAssertFalse(element("account.sched.quota.none").exists, app.debugDescription)
        diagnostics("account-detail-edit-sections")
        goBack()
        let oauth = app.buttons["account.1"]
        reveal(oauth, towardBottom: false)
        oauth.tap()
        let priority = element("account.sched.priority")
        reveal(priority)
        XCTAssertFalse(element("account.sched.quota.none").exists || element("account.sched.quota.daily").exists, app.debugDescription)
        goBack()
        let stopped = app.buttons["account.10"]
        reveal(stopped)
        stopped.tap()
        let status = element("account.basic.status")
        reveal(status)
        waitForValue(status, equals: "停用")
    }

    /// Without a `GET :id` the page shows the list's copy: both 编辑 are greyed with “先刷新账号”.
    @MainActor func testEditNeedsFreshDetail() {
        openDetail(4, arguments: [Fixture.detailError])
        defer { diagnostics("account-detail-edit-needs-refresh-final") }
        let edit = app.buttons["account.section.basic.edit"]
        reveal(edit)
        XCTAssertFalse(edit.isEnabled, app.debugDescription)
        XCTAssertTrue(element("account.section.basic.needsRefresh").waitForExistence(timeout: 5), app.debugDescription)
        let sched = app.buttons["account.section.sched.edit"]
        reveal(sched)
        XCTAssertFalse(sched.isEnabled, app.debugDescription)
        XCTAssertTrue(element("account.section.sched.needsRefresh").exists, app.debugDescription)
    }

    /// C-1: a read-only admin access token greys 编辑 with “只读令牌” under it.
    @MainActor func testReadOnlyTokenGreysEditButtons() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-readonly-token", Fixture.longWindows]; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-detail.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-readonly", in: "login.key")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        defer { diagnostics("account-detail-edit-readonly-final") }
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        let edit = app.buttons["account.section.basic.edit"]
        reveal(edit)
        XCTAssertFalse(edit.isEnabled, app.debugDescription)
        let sched = app.buttons["account.section.sched.edit"]
        reveal(sched)
        XCTAssertFalse(sched.isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-detail.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func launchAndOpenAccounts(arguments: [String] = []) {
        launchAndLogin(arguments: arguments)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(element("accounts.chip.all").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The list's row, so the page opens on its snapshot; waits for the server's copy unless the read fails.
    @MainActor private func openDetail(_ id: Int, arguments: [String] = []) {
        launchAndOpenAccounts(arguments: arguments)
        let row = app.buttons["account.\(id)"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openAccountFromRequestLog(arguments: [String] = []) {
        launchAndLogin(arguments: arguments)
        app.openSearchItem("search.item.usage")
        let request = app.buttons["logs.request.101"]
        XCTAssertTrue(request.waitForExistence(timeout: 10), app.debugDescription)
        request.tap()
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '查看账号'")).firstMatch
        app.scrollUntilExists(link)
        link.tap()
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    /// Dialog buttons, apart from the page's own button of the same title.
    @MainActor private func dialogButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'account.action.')", label)).firstMatch
    }
    /// The dialog's 取消 where the system draws one; otherwise a tap beside the floating dialog closes it.
    @MainActor private func dismissDialog() {
        let cancel = dialogButton("取消")
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); return }
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, app.debugDescription)
        let below = sheet.frame.maxY + 80
        let y = below < app.frame.maxY - 120 ? below : sheet.frame.minY - 80
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: sheet.frame.midX, dy: y)).tap()
    }
    /// System menu items are found by their title, apart from the 凭据 section's own 刷新令牌 (S2-16).
    @MainActor private func menuButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'account.cred.')", label)).firstMatch
    }
    @MainActor private func text(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func waitForValue(_ item: XCUIElement, equals expected: String, timeout: TimeInterval = 10,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: timeout), .completed, "\(String(describing: item.value))\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func waitForValue(_ item: XCUIElement, containing parts: [String], timeout: TimeInterval = 10,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: parts.map { NSPredicate(format: "value CONTAINS %@", $0) })
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: timeout), .completed, "\(String(describing: item.value))\n\(app.debugDescription)",
                       file: file, line: line)
    }
    /// The old log page (until S4-05) shows its scope as the selected segment.
    @MainActor private func assertLogsMode(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let mode = app.segmentedControls["logs.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(mode.buttons[title].isSelected, app.debugDescription, file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Lists create rows as they scroll in; the drag stops before the floating tab bar, and the list settles before a tap.
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

    // MARK: - 定时测试（S2-21）

    private static let scheduledTestsError = "-ui-scheduled-tests-error"
    private static let scheduledTestsThrottled = "-ui-scheduled-tests-throttled"

    /// 记录's last row sums up the first enabled plan and its newest result (DemoData+ScheduledTests); a raw cron stays as written.
    @MainActor func testScheduledTestsRowSummarizesEnabledPlan() {
        openDetail(3)
        defer { diagnostics("account-detail-scheduled-row-final") }
        let row = app.buttons["account.records.scheduledTests"]
        reveal(row)
        waitForValue(row, equals: "每 10 分钟 · claude-sonnet-4-5 · 上次失败")
        diagnostics("account-detail-scheduled-row")
        openListedAccount(1)
        reveal(row)
        waitForValue(row, equals: "每 30 分钟 · claude-haiku-4-5 · 上次成功")
        openListedAccount(8)
        reveal(row)
        waitForValue(row, equals: "15 9 * * 1-5 · 默认模型")
    }

    /// No plan: the row says where to add one and the small page is empty with the Web link; all plans off: “计划已停用”.
    @MainActor func testScheduledTestsRowEmptyAndDisabledPlans() {
        openDetail(9)
        defer { diagnostics("account-detail-scheduled-empty-final") }
        let row = app.buttons["account.records.scheduledTests"]
        reveal(row)
        waitForValue(row, equals: "没有计划 · 在 Web 中添加")
        row.tap()
        XCTAssertTrue(app.navigationBars["定时测试"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.scheduledTests.empty").waitForExistence(timeout: 10), app.debugDescription)
        let web = app.buttons["account.scheduledTests.web"]
        reveal(web)
        diagnostics("account-scheduled-empty")
        web.tap()
        waitForReceipt("已在浏览器打开「Kimi-01」的编辑页")
        goBack()
        openListedAccount(5)
        reveal(row)
        waitForValue(row, equals: "计划已停用")
    }

    /// The small page lists the plan's newest results: a failure as its code and kind word, never error_message; GLM's 529 comes
    /// only from its message. Pull to refresh keeps the list.
    @MainActor func testScheduledTestsPageListsResultsWithoutRawMessage() {
        openDetail(7)
        defer { diagnostics("account-scheduled-page-final") }
        let row = app.buttons["account.records.scheduledTests"]
        reveal(row)
        waitForValue(row, equals: "每 10 分钟 · gpt-4.1-mini · 上次失败")
        row.tap()
        XCTAssertTrue(app.navigationBars["定时测试"].waitForExistence(timeout: 10), app.debugDescription)
        let newest = element("account.scheduledTests.result.7101")
        XCTAssertTrue(newest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(newest.label.contains("401 凭据无效"), newest.label)
        XCTAssertTrue(element("account.scheduledTests.result.7102").label.contains("成功 · 0.8s"), app.debugDescription)
        XCTAssertEqual(element("account.scheduledTests.plan").label, "每 10 分钟 · gpt-4.1-mini")
        let raw = NSPredicate(format: "identifier BEGINSWITH 'account.scheduledTests' AND label CONTAINS 'invalid_api_key'")
        XCTAssertEqual(app.descendants(matching: .any).matching(raw).count, 0, app.debugDescription)
        diagnostics("account-scheduled-page")
        app.pullToRefresh(from: newest)
        XCTAssertTrue(element("account.scheduledTests.result.7103").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        openListedAccount(11)
        reveal(row)
        row.tap()
        let parsed = element("account.scheduledTests.result.11101")
        XCTAssertTrue(parsed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(parsed.label.contains("529 上游 529"), parsed.label)
    }

    /// A failed read: the row says “读取失败” and still opens the small page, which offers 重试; the other sections are unaffected.
    @MainActor func testScheduledTestsReadFailureShowsRetry() {
        openDetail(3, arguments: [Self.scheduledTestsError])
        defer { diagnostics("account-scheduled-error-final") }
        let row = app.buttons["account.records.scheduledTests"]
        reveal(row)
        waitForValue(row, equals: "读取失败")
        XCTAssertTrue(element("account.today.header").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.records.upstream"].exists, app.debugDescription)
        row.tap()
        let retry = app.buttons["account.scheduledTests.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        diagnostics("account-scheduled-error")
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["account.scheduledTests.web"].exists, app.debugDescription)
    }

    /// The small page's first read answers 429 (retry_after 8): C-5's failure row counts down with 重试 greyed out, then the page
    /// reads again by itself.
    @MainActor func testScheduledTestsPageThrottleCountsDownThenRetries() {
        openDetail(7, arguments: [Self.scheduledTestsThrottled])
        defer { diagnostics("account-scheduled-throttled-final") }
        let row = app.buttons["account.records.scheduledTests"]
        reveal(row)
        waitForValue(row, equals: "每 10 分钟 · gpt-4.1-mini · 上次失败")
        row.tap()
        let retry = app.buttons["account.scheduledTests.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(retry.isEnabled, app.debugDescription)
        let notice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "请求过于频繁，")).firstMatch
        XCTAssertTrue(notice.exists && notice.label.hasSuffix("秒后自动重试"), app.debugDescription)
        diagnostics("account-scheduled-throttled")
        XCTAssertTrue(element("account.scheduledTests.result.7101").waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(element("account.scheduledTests.failure").exists, app.debugDescription)
    }

    /// Back to the list, then the account `id` further down (the list keeps its order while it lives).
    @MainActor private func openListedAccount(_ id: Int) {
        goBack()
        let listed = app.buttons["account.\(id)"]
        reveal(listed)
        listed.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - 区块 429 与路由分区（S2-23）

    private static let todayRefreshThrottled = "-ui-account-today-refresh-throttled"
    private static let detailFocus = "-ui-account-focus"

    /// The second today-stats read (the return to the foreground reads every section again) answers 429 (retry_after 8): the
    /// figures stay, the countdown sits beside 今日's title, and today is read again by itself (X37).
    @MainActor func testTodayRefreshThrottleKeepsFiguresWithHeaderCountdown() {
        openDetail(1, arguments: [Self.todayRefreshThrottled])
        defer { diagnostics("account-detail-today-refresh-throttled-final") }
        let actual = element("account.today.actual")
        waitForValue(actual, equals: "$409.38")
        XCUIDevice.shared.press(.home)
        app.activate()
        let status = element("account.today.status")
        let counting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "请求过于频繁，"), object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [counting], timeout: 10), .completed, app.debugDescription)
        diagnostics("account-detail-today-refresh-throttled")
        XCTAssertEqual(actual.value as? String, "$409.38")
        XCTAssertFalse(element("account.today.failure").exists, app.debugDescription)
        XCTAssertTrue(status.waitForNonExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(actual.value as? String, "$409.38")
    }

    /// X39: `.account(id:focus:)` opens the detail on each of its six sections without a scroll (`-ui-account-focus`, Claude-官方-01).
    @MainActor func testRouteFocusScrollsToEachSection() {
        for focus in ["basic", "sched", "cred", "proxy", "models", "adv"] {
            launchAndLogin(arguments: [Self.detailFocus, focus])
            app.tabBars.buttons["账号"].tap()
            let header = element("account.section.\(focus)")
            XCTAssertTrue(header.waitForExistence(timeout: 10), "\(focus)\n\(app.debugDescription)")
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: header)
            XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "\(focus)\n\(app.debugDescription)")
            XCTAssertTrue(isAboveTabBar(header), "\(focus)\n\(app.debugDescription)")
            XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
            diagnostics("account-detail-focus-\(focus)")
            app.terminate()
        }
    }
}
