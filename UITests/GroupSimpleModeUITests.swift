import XCTest

/// 50 §0.7 (S5-13): the group pages on a simple-mode site (`-ui-simple-mode`, DemoData.adminMe's run_mode). The fixture server
/// answers as the backend does there (GroupFixtures+SimpleMode): replies without billing fields, 403 for copies and the advanced
/// reads, 409 GROUP_NOT_EMPTY for a group that still has accounts, and with `-ui-group-simple-unbindable` 400
/// SIMPLE_MODE_GROUP_NOT_BINDABLE for member writes (the fixtures have no composite group). Menu items are tapped by title.
final class GroupSimpleModeUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let simpleMode = "-ui-simple-mode"
        static let unbindable = "-ui-group-simple-unbindable"
        static let withoutCapabilities = "-ui-without-capabilities"
    }

    /// 1.3 / 1.4: no third line, 编辑 alone on the left swipe, no 停用 / 启用 / 复制 in the long press.
    @MainActor func testListHidesBillingRowAndStatusActions() {
        launchAndOpenGroups()
        defer { diagnostics("group-simple-list-final") }
        let premium = row(1)
        app.scrollUntilExists(premium)
        for part in ["高级组", "Anthropic", "可用 2 / 3"] { XCTAssertTrue(premium.label.contains(part), "“\(part)” missing in “\(premium.label)”") }
        for part in ["费率倍数", "标准计费", "今日"] { XCTAssertFalse(premium.label.contains(part), "“\(part)” in “\(premium.label)”") }

        premium.swipeLeft()
        XCTAssertTrue(swipeButton("edit", titled: "编辑").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(swipeButton("disable", titled: "停用").exists, app.debugDescription)
        premium.swipeRight()
        XCTAssertTrue(swipeButton("edit", titled: "编辑").waitForNonExistence(timeout: 5), app.debugDescription)

        premium.press(forDuration: 1.0)
        assertMenu(shows: ["编辑分组", "添加账号", "删除分组…"], hides: ["停用分组…", "启用分组", "复制分组"])
        closeMenuThroughEditor()
        let stopped = row(6)
        app.scrollUntilExists(stopped)
        stopped.press(forDuration: 1.0)
        assertMenu(shows: ["编辑分组", "删除分组…"], hides: ["启用分组", "复制分组"])
        XCTAssertEqual(app.alerts.count, 0, app.debugDescription)
    }

    /// 2.1 / 2.3: the platform alone under the title; ⋯ without 复制 / 停用 / 启用; 贰 keeps 请求 · Tokens · 账号成本, 叁 has no keys
    /// or subscriptions, 肆 only the Web row.
    @MainActor func testDetailShowsPlatformOnlyAndHidesAdvancedRows() {
        openGroup(1)
        defer { diagnostics("group-simple-detail-final") }
        XCTAssertTrue(app.staticTexts["Anthropic"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Anthropic · 标准（余额） · 公开"].exists, app.debugDescription)
        expectValue("group.usage.todayLine", "请求 10,194，Tokens 62.9M，账号成本 $370.27")
        for absent in ["group.usage.today", "group.usage.yesterday", "group.usage.total", "group.capacity.concurrency", "group.capacity.empty"] {
            XCTAssertFalse(element(absent).exists, absent)
        }
        let usage = element("group.records.usage")
        app.scrollUntilExists(usage)
        XCTAssertTrue(element("group.records.errors").exists && element("group.records.upstream").exists, app.debugDescription)
        XCTAssertFalse(element("group.records.keys").exists || element("group.records.subscriptions").exists, app.debugDescription)
        let web = element("group.config.web")
        app.scrollUntilExists(web)
        for kind in ["rate", "billing", "rpm", "exclusive", "client", "fallback"] { XCTAssertFalse(element("group.config.\(kind)").exists, kind) }
        app.buttons["group.more"].tap()
        assertMenu(shows: ["编辑分组", "添加账号", "删除分组…"], hides: ["复制分组", "停用分组…", "启用分组"])
        XCTAssertEqual(app.alerts.count, 0, app.debugDescription)
    }

    /// A stopped group: the quiet card and 编辑分组 alone, also in ⋯ (S5D2a-13: not made the primary button).
    @MainActor func testInactiveGroupOffersEditOnly() {
        openGroup(6)
        defer { diagnostics("group-simple-inactive-final") }
        XCTAssertEqual(element("group.detail.card.quiet").label, "已停用 · 使用此分组的 API 密钥会被拒绝")
        XCTAssertTrue(app.buttons["group.action.edit"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["group.action.enable"].exists, app.debugDescription)
        app.buttons["group.more"].tap()
        assertMenu(shows: ["编辑分组", "删除分组…"], hides: ["启用分组", "停用分组…"])
    }

    /// 3.3: the sheet has the name and the description (a new group the platform too), no status, 专属, billing or limits; the
    /// members section stays for a group that is not composite. The new group's footnote only says the platform is fixed.
    @MainActor func testEditAndCreateSheetsShowOnlyBasicFields() {
        openGroup(1)
        defer { diagnostics("group-simple-sheets-final") }
        app.buttons["group.action.edit"].tap()
        XCTAssertTrue(element("group-edit.name").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group-edit.description").exists, app.debugDescription)
        assertNoAdvancedFields()
        app.scrollUntilExists(element("group-edit.members.header"))
        XCTAssertFalse(element("group-edit.basic.footnote").exists, app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(element("group-edit.name").waitForNonExistence(timeout: 10), app.debugDescription)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let create = app.buttons["groups.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        create.tap()
        XCTAssertTrue(element("group-edit.name").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group-edit.platform").exists && element("group-edit.description").exists, app.debugDescription)
        assertNoAdvancedFields()
        let footnote = element("group-edit.basic.footnote")
        XCTAssertTrue(footnote.exists, app.debugDescription)
        XCTAssertEqual(footnote.label, "平台创建后不能修改。")
    }

    /// 0.7 删除: no member line in the confirmation; the server keeps a group with accounts (409 GROUP_NOT_EMPTY) and deletes an
    /// empty one.
    @MainActor func testDeletingGroupWithMembersShowsGroupNotEmpty() {
        launchAndOpenGroups()
        defer { diagnostics("group-simple-delete-final") }
        let premium = row(1)
        app.scrollUntilExists(premium)
        premium.press(forDuration: 1.0)
        tapMenuItem("删除分组…")
        let message = element("delete.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(message.label.contains("个成员账号移出分组"), message.label)
        typeDeleteName("高级组")
        let refused = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label CONTAINS %@", "分组里还有账号，先移出成员再删除。"), timeout: 10)
        XCTAssertTrue(refused, app.debugDescription)
        XCTAssertTrue(premium.exists, app.debugDescription)

        let codex = row(11)
        app.scrollUntilExists(codex)
        codex.press(forDuration: 1.0)
        tapMenuItem("删除分组…")
        typeDeleteName("Codex 专线")
        waitForReceipt("已删除分组「Codex 专线」")
        XCTAssertTrue(codex.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// 0.8: SIMPLE_MODE_GROUP_NOT_BINDABLE's words in the picker; nothing joined.
    @MainActor func testAddingAccountsShowsNotBindableCopy() {
        openGroup(11, arguments: [Fixture.unbindable])
        defer { diagnostics("group-simple-unbindable-final") }
        app.buttons["group.action.addAccounts"].tap()
        let main = app.buttons["group.pick.4"]
        XCTAssertTrue(main.waitForExistence(timeout: 10), app.debugDescription)
        main.tap()
        let submit = app.buttons["group.pick.submit"]
        XCTAssertTrue(submit.poll(NSPredicate(format: "label == %@ AND isEnabled == true", "加入 1 个账号"), timeout: 5), app.debugDescription)
        submit.tap()
        let error = element("group.pick.error")
        XCTAssertTrue(error.poll(NSPredicate(format: "label == %@", "简易模式下不能给组合分组添加账号。"), timeout: 10), app.debugDescription)
        app.buttons["group.pick.cancel"].tap()
        XCTAssertTrue(app.buttons["group.pick.cancel"].waitForNonExistence(timeout: 10), app.debugDescription)
        let add = element("group.members.add")
        app.scrollUntilExists(add)
        XCTAssertFalse(app.buttons["group.member.4"].exists, app.debugDescription)
        XCTAssertEqual(element("group.detail.card.badge").label, "没有账号")
    }

    /// S5-中-12: without `groups.member_batch` the button row's 添加账号, ⋯'s and the section's 添加 row stay but are greyed, and
    /// the section says why.
    @MainActor func testMembersGreyedWithoutMemberBatch() {
        openGroup(1, arguments: [Fixture.withoutCapabilities, "groups.member_batch"])
        defer { diagnostics("group-simple-no-batch-final") }
        let button = app.buttons["group.action.addAccounts"]
        XCTAssertTrue(button.exists, app.debugDescription)
        XCTAssertFalse(button.isEnabled, app.debugDescription)
        let add = element("group.members.add")
        app.scrollUntilExists(add)
        XCTAssertFalse(add.isEnabled, app.debugDescription)
        let note = element("group.members.note.batch")
        app.scrollUntilExists(note)
        XCTAssertEqual(note.label, "服务器暂不支持批量调整成员")
        app.buttons["group.more"].tap()
        let item = menuItem("添加账号")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(item.isEnabled, app.debugDescription)
        XCTAssertTrue(menuItem("编辑分组").isEnabled, app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in on the simple-mode site, then 搜索 → 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows", Fixture.simpleMode] + arguments
        app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("简易模式验收", in: "login.name")
        enter("https://group-simple.example.invalid", in: "login.url")
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
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    /// The left swipe's button, by identifier or, where the swipe drops it, by title.
    @MainActor private func swipeButton(_ action: String, titled title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.swipe.\(action)", title)).firstMatch
    }
    /// A menu item by title, apart from the button row's button of the same title.
    @MainActor private func menuItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'group.action.')", title)).firstMatch
    }
    @MainActor private func assertMenu(shows shown: [String], hides hidden: [String], file: StaticString = #filePath, line: UInt = #line) {
        for title in shown {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)", file: file, line: line)
        }
        for title in hidden { XCTAssertFalse(menuItem(title).exists, "\(title) shown\n\(app.debugDescription)", file: file, line: line) }
    }
    @MainActor private func tapMenuItem(_ title: String) {
        let item = menuItem(title)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    /// Leaves an open menu the one sure way: 编辑分组, then the sheet's 取消 (nothing changed, so it closes at once).
    @MainActor private func closeMenuThroughEditor() {
        tapMenuItem("编辑分组")
        let name = element("group-edit.name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func assertNoAdvancedFields(file: StaticString = #filePath, line: UInt = #line) {
        for id in ["status", "status.value", "exclusive", "exclusive.value", "rate", "rate.value", "billing", "billing.value", "rpm", "rpm.value",
                   "limit.daily", "limits.standard", "billing.footnote"] {
            XCTAssertFalse(element("group-edit.\(id)").exists, "group-edit.\(id)\n\(app.debugDescription)", file: file, line: line)
        }
    }
    /// Scrolls to the item, then waits for its accessibility value.
    @MainActor private func expectValue(_ identifier: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = element(identifier)
        app.scrollUntilExists(item, file: file, line: line)
        XCTAssertTrue(item.poll(NSPredicate(format: "value == %@", expected), timeout: 10),
                      "\(identifier): \(String(describing: item.value)) ≠ \(expected)\n\(app.debugDescription)", file: file, line: line)
    }
    /// The delete confirmation (Face ID off): 删除分组 once the whole name is typed.
    @MainActor private func typeDeleteName(_ name: String) {
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        let input = element("delete.input"); input.tap(); input.typeText(name)
        XCTAssertTrue(confirm.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        confirm.tap()
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Drags the page until the item sits above the keyboard or the tab bar, then lets it settle.
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
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
