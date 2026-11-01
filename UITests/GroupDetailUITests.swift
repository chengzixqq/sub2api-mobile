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
        XCTAssertFalse(app.buttons["group.action.addAccounts"].exists, app.debugDescription)
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
        let empty = element("group.members.empty")
        app.scrollUntilExists(empty)
        XCTAssertEqual(empty.label, "没有成员账号")
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

    /// 编辑分组 opens the group editor; ⋯ lists the actions this identity has (添加账号 waits for S5-08), and 删除分组… asks for
    /// the name while Face ID is off.
    @MainActor func testEditButtonAndMoreMenuOpenTheirSheets() {
        openGroup(1)
        defer { diagnostics("group-detail-edit-more-final") }
        app.buttons["group.action.edit"].tap()
        let name = element("group-editor.name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["group-editor.close"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group.detail.card").exists, app.debugDescription)

        app.buttons["group.more"].tap()
        for title in ["编辑分组", "停用分组…", "复制分组", "删除分组…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)")
        }
        XCTAssertFalse(menuItem("添加账号").exists, app.debugDescription)
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
}
