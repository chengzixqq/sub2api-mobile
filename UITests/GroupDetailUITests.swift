import XCTest

/// 50 §2 (S5-06): the group detail on the `-ui-testing` site — the status card, the button row and ⋯, 壹 · 成员账号 and the
/// deleted page, entered from the group list. Timed windows run an hour longer, so Claude-官方-03 stays rate limited. Menu items
/// are tapped by title (UIMenu may drop identifiers); receipts are up for 4.2 seconds.
final class GroupDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let deleted = "-ui-group-deleted"
        static let memberFailure = "-ui-group-member-failure"
        static let withoutCapabilities = "-ui-without-capabilities"
    }

    @MainActor func testPremiumGroupShowsCountsRecoveryAndMembersUnavailableFirst() {
        openGroup(1)
        defer { diagnostics("group-detail-premium-final") }
        XCTAssertTrue(app.navigationBars["高级组"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Anthropic · 标准（余额） · 公开"].exists, app.debugDescription)
        XCTAssertEqual(element("group.detail.card.badge").label, "正常")
        XCTAssertEqual(element("group.detail.card.cause").label, "1 个不可用")
        XCTAssertEqual(element("group.detail.card.figure").label, "2 / 3 个账号可用")
        XCTAssertEqual(element("group.detail.cells").label, "可用 2 / 3")
        for part in ["可用 2", "受限 1"] { XCTAssertTrue(element("group.detail.legend").label.contains(part), element("group.detail.legend").label) }
        let recovery = element("group.detail.card.recovery")
        XCTAssertTrue(recovery.waitForExistence(timeout: 10), app.debugDescription)
        let pattern = "^最早 \\d+:\\d{2}(:\\d{2})? 后恢复 1 个 · Claude-官方-03$"
        XCTAssertTrue(recovery.label.range(of: pattern, options: .regularExpression) != nil, recovery.label)
        let first = recovery.label
        XCTAssertTrue(recovery.poll(NSPredicate(format: "label != %@", first), timeout: 5), "the recovery line did not count down: \(first)")
        XCTAssertFalse(element("group.detail.card.stopped").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["group.action.edit"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["group.action.addAccounts"].exists, app.debugDescription)
        for old in ["group.analytics", "group.accounts", "group.logs"] { XCTAssertFalse(element(old).exists, old) }

        let header = element("group.members.header")
        app.scrollUntilExists(header)
        XCTAssertEqual(header.value as? String, "3 个 · 不可用在前")
        let limited = member(3), premium = member(1), second = member(2)
        app.scrollUntilExists(second)
        XCTAssertTrue(limited.exists && premium.exists, app.debugDescription)
        XCTAssertLessThan(limited.frame.minY, premium.frame.minY, app.debugDescription)
        XCTAssertLessThan(premium.frame.minY, second.frame.minY, app.debugDescription)
        waitForLabel(premium, contains: "今日 $380.98")
        XCTAssertTrue(premium.label.contains("另属 Claude Code 组"), premium.label)
        let footnote = element("group.members.footnote")
        app.scrollUntilExists(footnote)
        XCTAssertEqual(footnote.label, "成员行的“今日”只算这个分组的请求（按 Key 所属分组）。")
    }

    /// U38: without `accounts.today_stats_group` the rows show each account's whole today and the footnote says so.
    @MainActor func testMemberTodayFootnoteFallsBackToSiteWide() {
        openGroup(1, arguments: [Fixture.withoutCapabilities, "accounts.today_stats_group"])
        defer { diagnostics("group-detail-site-today-final") }
        let premium = member(1)
        app.scrollUntilExists(premium)
        waitForLabel(premium, contains: "今日 $409.38")
        let footnote = element("group.members.footnote")
        app.scrollUntilExists(footnote)
        XCTAssertEqual(footnote.label, "成员行的“今日”是账号今日，含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。")
    }

    @MainActor func testEnterpriseGroupWarnsNoAvailableAccounts() {
        openGroup(4)
        defer { diagnostics("group-detail-enterprise-final") }
        XCTAssertEqual(element("group.detail.card.badge").label, "无可用账号")
        XCTAssertEqual(element("group.detail.card.cause").label, "1 个不可用")
        XCTAssertEqual(element("group.detail.card.figure").label, "0 / 1 个账号可用")
        XCTAssertEqual(element("group.detail.card.warning").label,
                       "没有可用的账号，这个分组的新请求会失败。先让成员账号恢复或启用调度，或加入同平台的可用账号。")
        XCTAssertTrue(app.staticTexts["OpenAI · 订阅（配额） · 专属"].exists, app.debugDescription)
        let errorRow = member(7)
        app.scrollUntilExists(errorRow)
        XCTAssertTrue(errorRow.label.contains("错误"), errorRow.label)
        XCTAssertFalse(element("group.members.footnote").exists, app.debugDescription)
    }

    /// A stopped group: the quiet card, 启用分组 first; enabling it turns the card into the health card.
    @MainActor func testDisabledTestGroupShowsQuietCardAndEnablesFirst() {
        openGroup(6)
        defer { diagnostics("group-detail-disabled-final") }
        XCTAssertEqual(element("group.detail.card.quiet").label, "已停用 · 使用此分组的 API 密钥会被拒绝")
        for absent in ["group.detail.card.figure", "group.detail.cells", "group.detail.card.warning"] {
            XCTAssertFalse(element(absent).exists, absent)
        }
        let enable = app.buttons["group.action.enable"], edit = app.buttons["group.action.edit"]
        XCTAssertTrue(enable.exists && edit.exists, app.debugDescription)
        XCTAssertLessThan(enable.frame.minX, edit.frame.minX, app.debugDescription)
        enable.tap()
        waitForReceipt("已启用「测试组」")
        XCTAssertTrue(element("group.detail.card.quiet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group.detail.card.badge").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(enable.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// Antigravity 组: no members and no key uses it.
    @MainActor func testEmptyGroupWarnsNoAccountsAndNoKeys() {
        openGroup(10)
        defer { diagnostics("group-detail-empty-final") }
        XCTAssertEqual(element("group.detail.card.badge").label, "没有账号")
        XCTAssertEqual(element("group.detail.card.cause").label, "共 0 个账号")
        let warning = element("group.detail.card.warning")
        XCTAssertTrue(warning.poll(NSPredicate(format: "label == %@", "分组里还没有账号，新请求会失败。目前也没有 API 密钥使用它。"), timeout: 10),
                      warning.label)
        let add = element("group.members.add")
        app.scrollUntilExists(add)
        XCTAssertEqual(add.label, "添加 Antigravity 账号")
        XCTAssertFalse(element("group.members.empty").exists, app.debugDescription)
        XCTAssertFalse(element("group.members.footnote").exists, app.debugDescription)
    }

    /// 404 GROUP_NOT_FOUND: the whole page, only 返回 left; the list no longer has the group.
    @MainActor func testDeletedGroupShowsWholePageEmptyStateAndLeavesList() {
        launchAndOpenGroups(arguments: [Fixture.deleted])
        defer { diagnostics("group-detail-deleted-final") }
        let target = row(9)
        app.scrollUntilExists(target)
        target.tap()
        let deleted = element("group.detail.deleted")
        XCTAssertTrue(deleted.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(deleted.label, "这个分组已删除")
        XCTAssertTrue(app.navigationBars["分组"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["group.more"].exists, app.debugDescription)
        XCTAssertFalse(element("group.detail.card").exists, app.debugDescription)
        goBack()
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(target.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// 2.5: the members fail on their own; the card keeps the group's counts and leaves out what needs the members.
    @MainActor func testMemberFailureKeepsStatusCard() {
        openGroup(1, arguments: [Fixture.memberFailure])
        defer { diagnostics("group-detail-member-failure-final") }
        let failure = element("group.members.failure")
        app.scrollUntilExists(failure)
        XCTAssertTrue(app.staticTexts["成员加载失败"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["group.members.retry"].exists, app.debugDescription)
        XCTAssertEqual(element("group.detail.card.figure").label, "2 / 3 个账号可用")
        XCTAssertFalse(element("group.detail.card.recovery").exists, app.debugDescription)
        XCTAssertFalse(element("group.detail.card.stopped").exists, app.debugDescription)
    }

    @MainActor func testMemberRowOpensAccountDetailAndBackReturnsToGroup() {
        openGroup(2)
        defer { diagnostics("group-detail-member-open-final") }
        let row = member(4)
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["OpenAI-主力-01"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["标准组"].exists, app.debugDescription)
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
    }

    /// 编辑分组 opens the group sheet (S5-10); ⋯ lists the actions this identity has (添加账号 since S5-08), and 删除分组… asks for
    /// the name while Face ID is off.
    @MainActor func testEditButtonAndMoreMenuOpenTheirSheets() {
        openGroup(1)
        defer { diagnostics("group-detail-edit-more-final") }
        app.buttons["group.action.edit"].tap()
        let name = element("group-edit.name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["编辑分组"].exists, app.debugDescription)
        let platform = element("group-edit.platform.value")
        XCTAssertTrue(platform.label.contains("Anthropic"), platform.label)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group.detail.card").exists, app.debugDescription)

        app.buttons["group.more"].tap()
        for title in ["编辑分组", "添加账号", "停用分组…", "复制分组", "删除分组…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)")
        }
        menuItem("删除分组…").tap()
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除分组「高级组」？")
        XCTAssertFalse(app.buttons["delete.confirm"].isEnabled, app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["高级组"].exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in, then 搜索 → 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("分组详情验收", in: "login.name")
        enter("https://group-detail.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The list's row, then the detail once its card shows.
    @MainActor private func openGroup(_ id: Int, arguments: [String] = []) {
        launchAndOpenGroups(arguments: arguments)
        let target = row(id)
        app.scrollUntilExists(target)
        target.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func row(_ id: Int) -> XCUIElement { app.buttons["group.row.\(id)"] }
    @MainActor private func member(_ id: Int) -> XCUIElement { app.buttons["group.member.\(id)"] }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    /// A menu item by title, apart from the button row's button of the same title.
    @MainActor private func menuItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'group.action.')", title)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Drags the page until the item sits above the keyboard or the tab bar.
    @MainActor private func reveal(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveBottomBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20
                : app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2)))
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private func isAboveBottomBar(_ item: XCUIElement) -> Bool {
        let keyboard = app.keyboards.firstMatch, bar = app.tabBars.firstMatch
        if keyboard.exists { return item.frame.maxY <= keyboard.frame.minY }
        return !bar.exists || item.frame.maxY <= bar.frame.minY
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.poll(NSPredicate(format: "label CONTAINS %@", text), timeout: 10), "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                      file: file, line: line)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: - S5-07 告警横幅、贰 · 用量与容量、叁 · 记录与关联、肆 · 配置

    private enum SectionsFixture {
        static let opsDisabled = "-ui-ops-disabled"
        static let usageFailure = "-ui-group-usage-failure"
    }

    /// 2.3 告警横幅 above the card opens #41; back from the alert the banner is read again, so a manual resolve ends it (2.4).
    @MainActor func testStandardGroupAlertBannerOpensAlertAndLeavesOnceResolved() {
        openGroup(2)
        defer { diagnostics("group-detail-banner-final") }
        let banner = element("group.detail.alert")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(banner.label, "P1 告警中 · 标准组错误率 5.2%")
        let detail = banner.value as? String ?? ""
        let pattern = "^错误率 > 5\\.0%（5 分钟） · ([0-9]{2}/[0-9]{2} )?[0-9]{2}:[0-9]{2} 起$"
        XCTAssertNotNil(detail.range(of: pattern, options: .regularExpression), detail)
        XCTAssertLessThanOrEqual(banner.frame.maxY, element("group.detail.card").frame.minY, app.debugDescription)
        banner.tap()
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("alert.detail.ruleName").label, "标准组错误率")
        goBack()
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)

        banner.tap()
        let resolve = element("alert.detail.resolve")
        XCTAssertTrue(resolve.waitForExistence(timeout: 10), app.debugDescription)
        resolve.tap()
        let dialog = app.alerts["手动解决这条告警？"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
        dialog.buttons["手动解决"].firstMatch.tap()
        waitForReceipt("已手动解决")
        goBack()
        XCTAssertTrue(app.navigationBars["标准组"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(banner.pollGone(timeout: 5), app.debugDescription)

        // 高级组's only alert (#35) has ended.
        goBack()
        openListedGroup(1)
        XCTAssertFalse(banner.waitForExistence(timeout: 3), app.debugDescription)
    }

    /// 贰: the list's usage-summary, dashboard/groups' line and capacity counted like the backend. 高级组 and Claude Code 组 both
    /// schedule Claude-官方-01 and -02 (-03 is rate limited); 标准组 has only a concurrency ceiling.
    @MainActor func testUsageAmountsTodayLineAndCapacityLines() {
        openGroup(2)
        defer { diagnostics("group-detail-usage-final") }
        expectValue("group.capacity.concurrency", "2/8")
        app.scrollUntilExists(element("group.records.header"))
        XCTAssertFalse(element("group.capacity.sessions").exists, app.debugDescription)
        XCTAssertFalse(element("group.capacity.rpm").exists, app.debugDescription)

        goBack()
        openListedGroup(1)
        let header = element("group.usage.header")
        app.scrollUntilExists(header)
        XCTAssertEqual(header.value as? String, "按 Key 所属分组 · 00:00 切分")
        for (id, value) in [("today", "$933.30"), ("yesterday", "$2,985.60"), ("total", "$186,420.55")] { expectValue("group.usage.\(id)", value) }
        expectValue("group.usage.todayLine", "请求 10,194，Tokens 62.9M，账号成本 $370.27")
        expectPremiumCapacity()

        goBack()
        openListedGroup(5)
        expectPremiumCapacity()
    }

    /// 容量 — with why: nothing schedulable (企业专线), no members (Antigravity 组), a stopped group (测试组).
    @MainActor func testCapacityNotesForUnschedulableEmptyAndStoppedGroups() {
        openGroup(4)
        defer { diagnostics("group-detail-capacity-notes-final") }
        expectCapacityNote("没有可调度的账号")
        goBack()
        openListedGroup(10)
        expectCapacityNote("没有成员账号")
        goBack()
        openListedGroup(6)
        expectCapacityNote("停用的分组不统计容量")
        XCTAssertFalse(element("group.capacity.concurrency").exists, app.debugDescription)
    }

    /// 2.5: usage-summary and dashboard/groups fail (a first read, so “—”); capacity and the card do not depend on them.
    @MainActor func testUsageFailureShowsDashesAndKeepsCapacity() {
        openGroup(1, arguments: [SectionsFixture.usageFailure])
        defer { diagnostics("group-detail-usage-failure-final") }
        XCTAssertEqual(element("group.detail.card.figure").label, "2 / 3 个账号可用")
        for id in ["today", "yesterday", "total", "todayLine"] { expectValue("group.usage.\(id)", "无数据") }
        expectValue("group.capacity.concurrency", "5/8")
        XCTAssertFalse(element("group.usage.retry").exists, app.debugDescription)
    }

    /// 叁: the 24-hour counts, the logs filtered by the group (either log page), the group's keys and subscriptions.
    @MainActor func testRecordRowsCountTheLastDayAndOpenTheirPages() {
        openGroup(4)
        defer { diagnostics("group-detail-records-final") }
        expectValue("group.records.subscriptions", "生效中 12 个")
        element("group.records.subscriptions").tap()
        XCTAssertTrue(app.navigationBars["订阅"].waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["企业专线"].waitForExistence(timeout: 10), app.debugDescription)

        goBack()
        openListedGroup(2)
        expectValue("group.records.errors", "近 24 小时 37 条")
        expectValue("group.records.upstream", "近 24 小时 9 条")
        XCTAssertTrue(element("group.records.usage").exists, app.debugDescription)
        element("group.records.errors").tap()
        waitForLogsPage()
        goBack()
        XCTAssertTrue(app.navigationBars["标准组"].waitForExistence(timeout: 10), app.debugDescription)
        expectValue("group.records.keys", "64 个")
        element("group.records.keys").tap()
        XCTAssertTrue(app.navigationBars["API 密钥"].waitForExistence(timeout: 10), app.debugDescription)
        goBack()

        goBack()
        openListedGroup(1)
        expectValue("group.records.errors", "近 24 小时 0 条")
        expectValue("group.records.keys", "38 个")
        XCTAssertFalse(element("group.records.subscriptions").exists, app.debugDescription)
    }

    /// 2.5 ops 关闭: no banner, both counts say so and still open the logs.
    @MainActor func testOpsDisabledHidesBannerAndSaysMonitoringOff() {
        openGroup(2, arguments: [SectionsFixture.opsDisabled])
        defer { diagnostics("group-detail-ops-disabled-final") }
        expectValue("group.records.errors", "运维监控未开启")
        expectValue("group.records.upstream", "运维监控未开启")
        element("group.records.errors").tap()
        waitForLogsPage()
        goBack()
        app.scrollUntilExists(element("group.detail.card"), towardBottom: false)
        XCTAssertFalse(element("group.detail.alert").exists, app.debugDescription)
    }

    /// 肆: a subscription group's limits, 高级组's plain rows, Claude Code 组's fallback by name; rate opens the editor and the Web
    /// row only shows its receipt under -ui-testing.
    @MainActor func testConfigRowsLimitsFallbackEditorAndWebRow() {
        openGroup(4)
        defer { diagnostics("group-detail-config-final") }
        let limits = element("group.config.limits")
        app.scrollUntilExists(limits)
        let spoken = limits.value as? String ?? ""
        for amount in ["每日 $20", "每周 $100", "每月 $300"] { XCTAssertTrue(spoken.contains(amount), spoken) }

        goBack()
        openListedGroup(1)
        expectValue("group.config.rpm", "不限")
        expectValue("group.config.client", "所有客户端")
        expectValue("group.config.fallback", "无数据")

        goBack()
        openListedGroup(5)
        for (id, value) in [("rate", "×0.8"), ("rpm", "60"), ("exclusive", "专属"), ("client", "仅限 Claude Code"), ("fallback", "高级组")] {
            expectValue("group.config.\(id)", value)
        }
        XCTAssertFalse(element("group.config.description").exists, app.debugDescription)
        let rate = element("group.config.rate")
        app.scrollUntilExists(rate, towardBottom: false)
        rate.tap()
        let name = element("group-edit.name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), app.debugDescription)
        let web = element("group.config.web")
        app.scrollUntilExists(web)
        XCTAssertTrue(web.label.contains("模型白名单、组合路由、图片计费"), web.label)
        web.tap()
        waitForReceipt("已打开 Web 分组管理")
    }

    /// Back on the list: the row, then the detail once its card shows.
    @MainActor private func openListedGroup(_ id: Int) {
        let target = row(id)
        app.scrollUntilExists(target)
        target.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// Scrolls to the item, then waits for its accessibility value.
    @MainActor private func expectValue(_ identifier: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = element(identifier)
        app.scrollUntilExists(item, file: file, line: line)
        XCTAssertTrue(item.poll(NSPredicate(format: "value == %@", expected), timeout: 10),
                      "\(identifier): \(String(describing: item.value)) ≠ \(expected)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func expectPremiumCapacity(file: StaticString = #filePath, line: UInt = #line) {
        for (id, value) in [("concurrency", "5/8"), ("sessions", "5/6"), ("rpm", "26/120")] {
            expectValue("group.capacity.\(id)", value, file: file, line: line)
        }
    }
    @MainActor private func expectCapacityNote(_ note: String, file: StaticString = #filePath, line: UInt = #line) {
        expectValue("group.capacity.empty", "无数据", file: file, line: line)
        let item = element("group.capacity.note")
        app.scrollUntilExists(item, file: file, line: line)
        XCTAssertEqual(item.label, note, file: file, line: line)
    }
    /// S5D2a-16: the old log page or S4-05's, whichever this build has.
    @MainActor private func waitForLogsPage(file: StaticString = #filePath, line: UInt = #line) {
        let titles = ["使用记录", "请求与错误日志"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if titles.contains(where: { app.navigationBars[$0].exists || app.navigationBars.staticTexts[$0].exists }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("no log page\n\(app.debugDescription)", file: file, line: line)
    }

    /// 2.5 ops 关闭 learned on another tab: back on the detail the banner is gone and both counts say so at once, though the
    /// 60-second refresh reads neither.
    @MainActor func testBannerAndCountsLeaveOnceOpsIsTurnedOffElsewhere() {
        openGroup(2)
        defer { diagnostics("group-detail-ops-turned-off-final") }
        let banner = element("group.detail.alert")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        expectValue("group.records.errors", "近 24 小时 37 条")
        turnOpsOffOnMonitorTab()
        app.openSearchTab()
        XCTAssertTrue(app.navigationBars["标准组"].waitForExistence(timeout: 10), app.debugDescription)
        expectValue("group.records.errors", "运维监控未开启")
        expectValue("group.records.upstream", "运维监控未开启")
        app.scrollUntilExists(element("group.detail.card"), towardBottom: false)
        XCTAssertFalse(banner.exists, app.debugDescription)
    }
    /// 监控's ··· → 关闭运维监控… → 关闭运维监控 → 仍要关闭 (U10).
    @MainActor private func turnOpsOffOnMonitorTab() {
        app.tabBars.buttons["监控"].tap()
        let byIdentifier = element("monitor.more")
        let more = byIdentifier.waitForExistence(timeout: 10) ? byIdentifier : app.navigationBars.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        more.tap()
        for title in ["关闭运维监控…", "关闭运维监控"] {
            let item = menuItem(title)
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)")
            item.tap()
        }
        let last = app.alerts.firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        last.buttons["仍要关闭"].firstMatch.tap()
        waitForReceipt("已关闭运维监控")
    }

    // MARK: - S5-13 只读令牌、旧服务端、QA 对账与首页下钻

    /// C-1 on the detail: the button row and the members' 添加 row greyed with “只读令牌”, ⋯'s writes greyed, no member swipe, the
    /// members' today still read (today-stats/batch is allowed for a read-only token), and 肆's rows open no sheet.
    @MainActor func testReadOnlyTokenGreysDetailWriteEntries() {
        signIn(readOnly: true)
        app.openSearchItem("search.item.groups")
        openListedGroup(1)
        defer { diagnostics("group-detail-read-only-final") }
        for id in ["addAccounts", "edit"] {
            let button = app.buttons["group.action.\(id)"]
            XCTAssertTrue(button.exists && !button.isEnabled, "group.action.\(id)\n\(app.debugDescription)")
        }
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
        let premium = member(1)
        app.scrollUntilExists(premium)
        waitForLabel(premium, contains: "今日 $")
        premium.swipeLeft()
        // A row without swipe actions takes the swipe as a tap.
        if element("account.detail.card").waitForExistence(timeout: 2) { goBack() }
        XCTAssertTrue(app.navigationBars["高级组"].waitForExistence(timeout: 10), app.debugDescription)
        let swipes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'group.member.1.' OR label IN %@", ["移出", "停止调度"]))
        XCTAssertFalse(swipes.firstMatch.exists, app.debugDescription)
        let add = element("group.members.add")
        app.scrollUntilExists(add)
        XCTAssertFalse(add.isEnabled, app.debugDescription)
        let rate = element("group.config.rate")
        app.scrollUntilExists(rate)
        rate.tap()
        XCTAssertFalse(element("group-edit.name").waitForExistence(timeout: 2), app.debugDescription)
        app.buttons["group.more"].tap()
        for title in ["编辑分组", "添加账号", "停用分组…", "复制分组", "删除分组…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)")
            XCTAssertFalse(menuItem(title).isEnabled, "\(title)\n\(app.debugDescription)")
        }
    }

    /// 50 §0.1 on an older server: the members' whole-site today and its footnote, capacity filtered here, the key count from the
    /// key list's total, a disable confirmation without a number, and the member fallback's note.
    @MainActor func testLegacyServerDetailUsesFallbacks() {
        openGroup(1, arguments: [Fixture.withoutCapabilities, Self.legacyCapabilities])
        defer { diagnostics("group-detail-legacy-final") }
        let footnote = element("group.members.footnote")
        app.scrollUntilExists(footnote)
        XCTAssertEqual(footnote.label, "成员行的“今日”是账号今日，含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。")
        expectPremiumCapacity()
        expectValue("group.records.keys", "38 个")
        app.buttons["group.more"].tap()
        let disable = menuItem("停用分组…")
        XCTAssertTrue(disable.waitForExistence(timeout: 5), app.debugDescription)
        disable.tap()
        let alert = app.alerts["停用「高级组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        let keys = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "使用这个分组的 API 密钥会被拒绝")).firstMatch
        XCTAssertTrue(keys.exists, app.debugDescription)
        XCTAssertFalse(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个 API 密钥")).firstMatch.exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["group.more"].tap()
        let add = menuItem("添加账号")
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription)
        add.tap()
        let notice = element("group.pick.legacy")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(notice.label, "服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改。")
    }

    /// 50 §9: the detail's 今日 is the list's, and the members' today in the group's terms adds up to no more than it (a rate-limited
    /// row shows its recovery instead of today, so it adds nothing here).
    @MainActor func testQATodayReconcilesWithListAndMembers() {
        launchAndOpenGroups()
        defer { diagnostics("group-detail-qa-today-final") }
        for (id, today, members) in [(1, "$933.30", [1, 2, 3]), (5, "$52.75", [1, 2])] {
            let listed = row(id)
            app.scrollUntilExists(listed)
            waitForLabel(listed, contains: "今日 \(today)")
            listed.tap()
            XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
            waitForLabel(member(1), contains: "今日 $")
            var membersCents = 0
            for account in members {
                let item = member(account)
                app.scrollUntilExists(item)
                membersCents += Self.cents(after: "今日 ", in: item.label) ?? 0
            }
            XCTAssertGreaterThan(membersCents, 0, "group \(id)")
            expectValue("group.usage.today", today)
            XCTAssertLessThanOrEqual(membersCents, Self.cents(after: "", in: today) ?? 0, "group \(id)")
            goBack()
        }
    }

    /// 50 §8.1: the overview's 可用不足 1 个分组 opens the group detail on 概览's own stack, and back returns there.
    @MainActor func testHomeShortGroupRowOpensGroupDetail() {
        signIn()
        defer { diagnostics("group-detail-home-shortage-final") }
        let groups = element("home.attention.groups")
        XCTAssertTrue(groups.waitForExistence(timeout: 15), app.debugDescription)
        reveal(groups)
        XCTAssertTrue(groups.label.contains("企业专线 0/1"), groups.label)
        groups.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["企业专线"].waitForExistence(timeout: 5), app.debugDescription)
        let warning = element("group.detail.card.warning")
        XCTAssertTrue(warning.poll(NSPredicate(format: "label BEGINSWITH %@", "没有可用的账号，这个分组的新请求会失败。"), timeout: 10), app.debugDescription)
        XCTAssertFalse(element("group.accounts").exists, app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected, app.debugDescription)
        goBack()
        XCTAssertTrue(groups.waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 50 §8.1: the alert's scope row opens the group detail with its banner; back returns to the alert.
    @MainActor func testAlertScopeGroupRowOpensGroupDetail() {
        signIn()
        defer { diagnostics("group-detail-alert-scope-final") }
        let alertRow = element("home.attention.alert-41")
        XCTAssertTrue(alertRow.waitForExistence(timeout: 15), app.debugDescription)
        reveal(alertRow)
        alertRow.tap()
        let scope = element("alert.detail.scope.group")
        XCTAssertTrue(scope.waitForExistence(timeout: 10), app.debugDescription)
        reveal(scope)
        scope.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["标准组"].waitForExistence(timeout: 5), app.debugDescription)
        let banner = element("group.detail.alert")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(banner.label.contains("告警中") && banner.label.contains("标准组"), banner.label)
        goBack()
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 10), app.debugDescription)
    }

    private static let legacyCapabilities = "groups.account_buckets,groups.capacity_filter,groups.member_batch,accounts.status_summary,"
        + "accounts.today_stats_group,accounts.list_query"
    /// Password sign-in, or a read-only `sat_` access token, up to the overview.
    @MainActor private func signIn(readOnly: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + (readOnly ? ["-ui-readonly-token"] : [])
        app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("分组详情验收", in: "login.name")
        enter("https://group-detail.example.invalid", in: "login.url")
        if readOnly {
            let method = element("login.method.accessToken"); reveal(method); method.tap()
            enter("sat_fixture-readonly", in: "login.key")
        } else {
            enter("admin@example.com", in: "login.email")
            enter("fixture-password", in: "login.password")
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// “$1,234.56” after `prefix` in `text`, in cents.
    private static func cents(after prefix: String, in text: String) -> Int? {
        let pattern = NSRegularExpression.escapedPattern(for: prefix) + "\\$[0-9,]+\\.[0-9]{2}"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(String(text[range].dropFirst(prefix.count).filter(\.isNumber)))
    }

    // MARK: - U-11 刷新失败保留上次值（S5-高-3）

    private static let blocksFailureAfterFirst = "-ui-group-detail-blocks-failure-after-first"

    /// 贰: a failed refresh keeps every figure and puts one 更新失败 beside the title for its three blocks; a tap reads again.
    /// Entering took the list's usage-summary, so the first pull fails dashboard/groups and capacity, the second usage-summary too.
    @MainActor func testStaleUsageHeaderOffersRetry() {
        openGroup(1, arguments: [Self.blocksFailureAfterFirst])
        defer { diagnostics("group-detail-stale-usage-final") }
        let todayLine = "请求 10,194，Tokens 62.9M，账号成本 $370.27"
        expectValue("group.usage.todayLine", todayLine)
        expectPremiumCapacity()
        let retry = app.buttons["group.usage.retry"]
        XCTAssertFalse(retry.exists, app.debugDescription)
        let card = element("group.detail.card")
        app.scrollUntilExists(card, towardBottom: false)
        app.pullToRefresh(from: card)
        app.scrollUntilExists(element("group.usage.header"))
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(retry.label.contains("更新失败"), retry.label)
        expectValue("group.usage.todayLine", todayLine)
        expectPremiumCapacity()

        app.scrollUntilExists(retry, towardBottom: false)
        retry.tap()
        // Every read after the first fails: the accessory comes back and every figure stays.
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        for (id, value) in [("today", "$933.30"), ("yesterday", "$2,985.60"), ("total", "$186,420.55")] { expectValue("group.usage.\(id)", value) }
        expectValue("group.usage.todayLine", todayLine)
        XCTAssertTrue(retry.label.contains("更新失败"), retry.label)
    }

    /// 告警横幅: a failed refresh keeps the banner and adds the caution strip under it; tapping it reads the banner again.
    @MainActor func testAlertBannerStaleStrip() {
        openGroup(2, arguments: [Self.blocksFailureAfterFirst])
        defer { diagnostics("group-detail-stale-alert-final") }
        let banner = element("group.detail.alert")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        let strip = app.buttons["group.detail.alert.retry"]
        XCTAssertFalse(strip.exists, app.debugDescription)
        app.pullToRefresh(from: banner)
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(strip.label, "告警更新失败 · 重试")
        XCTAssertEqual(banner.label, "P1 告警中 · 标准组错误率 5.2%")
        XCTAssertLessThanOrEqual(banner.frame.maxY, strip.frame.minY, app.debugDescription)
        XCTAssertLessThanOrEqual(strip.frame.maxY, element("group.detail.card").frame.minY, app.debugDescription)
        strip.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(banner.label, "P1 告警中 · 标准组错误率 5.2%")
    }
}
