import XCTest

/// 50 §2.4 and §4 (S5-08): the member rows' 移出 and status actions, and 添加账号 from the list, the detail and the members
/// section, on the `-ui-testing` site. Timed windows run an hour longer, so Claude-官方-03 stays rate limited. Menu items and
/// dialog buttons are tapped by title (they may drop identifiers); a receipt is up for 4.2 seconds, so its button is tapped as
/// soon as it shows and the rows are checked after. The helpers are internal for S5-09's GroupMembersUITests+Batch.swift.
final class GroupMembersUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    // MARK: - 成员左滑（2.4）

    /// The last available member of an active group asks first; 取消 keeps it, 仍然移出 takes it out.
    @MainActor func testRemovingTheOnlyAvailableAccountAsksFirst() {
        openGroup(2)
        defer { diagnostics("group-members-remove-last-final") }
        let main = member(4)
        app.scrollUntilExists(main)
        swipeMember(4, to: "remove", titled: "移出")
        let confirm = app.buttons["group.member.remove.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "仍然移出")
        XCTAssertTrue(text(containing: "把「OpenAI-主力-01」移出「标准组」？").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "它是这个分组唯一可用的账号").exists, app.debugDescription)
        dismissDialog()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(main.exists, app.debugDescription)

        swipeMember(4, to: "remove", titled: "移出")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        waitForReceipt("已移出「OpenAI-主力-01」 · 可用 1 → 0")
        XCTAssertTrue(main.pollGone(timeout: 10), app.debugDescription)
    }

    /// Any other removal goes at once; 撤销 brings the row back.
    @MainActor func testRemovingAMemberCanBeUndone() {
        openGroup(1)
        defer { diagnostics("group-members-remove-undo-final") }
        let first = member(1)
        app.scrollUntilExists(first)
        swipeMember(1, to: "remove", titled: "移出")
        waitForReceipt("已移出「Claude-官方-01」 · 可用 2 → 1")
        XCTAssertFalse(first.exists, app.debugDescription)
        tapReceiptAction(titled: "撤销")
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group.detail.card.figure").poll(NSPredicate(format: "label == %@", "2 / 3 个账号可用"), timeout: 10),
                      app.debugDescription)
    }

    /// 恢复状态 asks through AccountActions' confirmation; an available member offers 停止调度.
    @MainActor func testRateLimitedMemberRecoversThroughAccountActions() {
        openGroup(1)
        defer { diagnostics("group-members-recover-final") }
        let limited = member(3)
        app.scrollUntilExists(limited)
        swipeMember(3, to: "status", titled: "恢复状态")
        XCTAssertTrue(text(containing: "恢复「Claude-官方-03」？").waitForExistence(timeout: 5), app.debugDescription)
        let recover = dialogButton("恢复状态")
        XCTAssertTrue(recover.waitForExistence(timeout: 5), app.debugDescription)
        recover.tap()
        waitForReceipt("已恢复 · 参与调度")
        let first = member(1)
        app.scrollUntilExists(first)
        first.swipeLeft()
        XCTAssertTrue(swipeButton(of: 1, action: "status", titled: "停止调度").waitForExistence(timeout: 5), app.debugDescription)
    }

    // MARK: - 添加账号（4）

    /// 4.3 底部坞 and 0.4.3: one account into 企业专线 from the members section's row; 撤销 takes it out again.
    @MainActor func testAddingAccountShowsAvailabilityAndUndoTakesItBack() {
        openGroup(4)
        defer { diagnostics("group-members-add-undo-final") }
        openPickerFromMembers(title: "添加 OpenAI 账号")
        XCTAssertTrue(app.navigationBars["添加到「企业专线」"].waitForExistence(timeout: 10), app.debugDescription)
        let main = pickRow(4)
        XCTAssertTrue(main.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(main.label.contains("可调度"), main.label)
        XCTAssertFalse(pickRow(7).exists, app.debugDescription)
        XCTAssertEqual(element("group.pick.preview").label, "选择要加入的账号")
        XCTAssertFalse(app.buttons["group.pick.submit"].isEnabled, app.debugDescription)
        main.tap()
        XCTAssertTrue(element("group.pick.preview").poll(NSPredicate(format: "label == %@", "加入后可用 0 → 1 / 2"), timeout: 5), app.debugDescription)
        submitPicks(titled: "加入 1 个账号")
        waitForReceipt("已加入 1 个账号 · 可用 0 → 1")
        XCTAssertTrue(member(4).poll(timeout: 3), app.debugDescription)
        tapReceiptAction(titled: "撤销")
        XCTAssertTrue(member(4).pollGone(timeout: 10), app.debugDescription)
        XCTAssertTrue(member(7).exists, app.debugDescription)
    }

    /// 4.3 空态: every Anthropic account is already in 高级组 (opened from ⋯); the footnote names the platform.
    @MainActor func testPremiumGroupPickerSaysEveryAnthropicAccountIsAMember() {
        openGroup(1)
        defer { diagnostics("group-members-premium-empty-final") }
        app.buttons["group.more"].tap()
        let item = menuItem("添加账号")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
        let empty = element("group.pick.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "Anthropic 账号都已在这个分组里")
        XCTAssertTrue(element("group.pick.note").label.hasPrefix("只列出 Anthropic 账号："), element("group.pick.note").label)
        XCTAssertEqual(app.buttons["group.pick.submit"].label, "加入")
        XCTAssertFalse(app.buttons["group.pick.submit"].isEnabled, app.debugDescription)
    }

    /// 4.3 排序 and the search: schedulable first; the search narrows the list, then finds nothing.
    @MainActor func testPickerSearchFiltersCandidates() {
        openGroup(11)
        defer { diagnostics("group-members-search-final") }
        let add = app.buttons["group.action.addAccounts"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        add.tap()
        let main = pickRow(4), spare = pickRow(7)
        XCTAssertTrue(spare.waitForExistence(timeout: 10) && main.exists, app.debugDescription)
        XCTAssertLessThan(main.frame.minY, spare.frame.minY, app.debugDescription)
        XCTAssertTrue(main.label.contains("已在 标准组"), main.label)
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "搜索 OpenAI 账号")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("主力")
        XCTAssertTrue(spare.pollGone(timeout: 10), app.debugDescription)
        XCTAssertTrue(main.exists, app.debugDescription)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "不存在")
        let empty = element("group.pick.empty")
        XCTAssertTrue(empty.poll(NSPredicate(format: "label == %@", "没有匹配的账号"), timeout: 10), app.debugDescription)
    }

    /// -ui-group-batch-partial: 7 is missing, 4 goes in; 查看 opens the per-item results (S5-09's page later).
    @MainActor func testBatchFailureReceiptOffersResults() {
        openGroup(11, arguments: [Fixture.batchPartial])
        defer { diagnostics("group-members-partial-final") }
        app.buttons["group.action.addAccounts"].tap()
        XCTAssertTrue(pickRow(7).waitForExistence(timeout: 10), app.debugDescription)
        pickRow(4).tap(); pickRow(7).tap()
        submitPicks(titled: "加入 2 个账号")
        waitForReceipt("已加入 1 个，1 个失败")
        tapReceiptAction(titled: "查看")
        XCTAssertTrue(app.navigationBars["逐项结果"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 0.8: a member write lost after its one resend says so with 重试; nothing changed.
    @MainActor func testRequestFailureReceiptOffersRetry() {
        openGroup(4, arguments: [Fixture.batchOffline])
        defer { diagnostics("group-members-offline-final") }
        openPickerFromMembers(title: "添加 OpenAI 账号")
        XCTAssertTrue(pickRow(4).waitForExistence(timeout: 10), app.debugDescription)
        pickRow(4).tap()
        submitPicks(titled: "加入 1 个账号")
        waitForReceipt("成员改动未确认")
        XCTAssertTrue(app.buttons["receipt.action"].poll(NSPredicate(format: "label == %@", "重试"), timeout: 3), app.debugDescription)
        app.scrollUntilExists(member(7))
        XCTAssertFalse(member(4).exists, app.debugDescription)
    }

    /// 0.4.4: without `groups.member_batch` the sheet warns and the accounts go one by one; no counts come back.
    @MainActor func testLegacyServerAddsAccountsOneByOne() {
        openGroup(4, arguments: [Fixture.withoutCapabilities, "groups.member_batch"])
        defer { diagnostics("group-members-legacy-final") }
        openPickerFromMembers(title: "添加 OpenAI 账号")
        let notice = element("group.pick.legacy")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(notice.label, "服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改，并会重置这些账号在其他分组里的排序。")
        pickRow(4).tap()
        submitPicks(titled: "加入 1 个账号")
        waitForReceipt("已加入 1 个账号")
        app.scrollUntilExists(member(4))
        XCTAssertTrue(member(4).exists, app.debugDescription)
    }

    /// 1.4: the list's right swipe offers 添加账号 on an active group only.
    @MainActor func testListLeadingSwipeOffersAddOnlyForActiveGroups() {
        launchAndOpenGroups()
        defer { diagnostics("group-members-list-swipe-final") }
        row(4).swipeRight()
        let add = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.swipe.addAccounts", "添加账号")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription)
        add.tap()
        XCTAssertTrue(app.navigationBars["添加到「企业专线」"].waitForExistence(timeout: 10), app.debugDescription)
        let main = pickRow(4)
        XCTAssertTrue(main.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(main.poll(NSPredicate(format: "label CONTAINS %@", "已在 标准组"), timeout: 5), main.label)
        app.buttons["group.pick.cancel"].tap()
        XCTAssertTrue(app.navigationBars["添加到「企业专线」"].waitForNonExistence(timeout: 10), app.debugDescription)
        let stopped = row(6)
        app.scrollUntilExists(stopped)
        stopped.swipeRight()
        XCTAssertFalse(add.waitForExistence(timeout: 2), app.debugDescription)
    }

    /// S5D2a-12: with -ui-group-batch-partial a lone Anthropic add fails MIXED_CHANNEL_RISK (S5-09's Claude Code 组 case).
    @MainActor func testBatchPartialFailsALoneAnthropicAddOnMixedChannels() {
        openGroup(5, arguments: [Fixture.batchPartial])
        defer { diagnostics("group-members-partial-mixed-final") }
        app.buttons["group.action.addAccounts"].tap()
        XCTAssertTrue(pickRow(3).waitForExistence(timeout: 10), app.debugDescription)
        pickRow(3).tap()
        submitPicks(titled: "加入 1 个账号")
        waitForReceipt("加入失败 · 1 个账号没有改动")
        XCTAssertTrue(app.buttons["receipt.action"].poll(NSPredicate(format: "label == %@", "查看"), timeout: 3), app.debugDescription)
    }

    // MARK: - Helpers

    enum Fixture {
        static let batchPartial = "-ui-group-batch-partial"
        static let batchOffline = "-ui-group-batch-offline"
        static let withoutCapabilities = "-ui-without-capabilities"
    }
    @MainActor func pickRow(_ id: Int) -> XCUIElement { app.buttons["group.pick.\(id)"] }
    /// The members section's 添加 row, below the members.
    @MainActor func openPickerFromMembers(title: String, file: StaticString = #filePath, line: UInt = #line) {
        let add = element("group.members.add")
        app.scrollUntilExists(add)
        XCTAssertEqual(add.label, title, file: file, line: line)
        add.tap()
    }
    @MainActor func submitPicks(titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        let submit = app.buttons["group.pick.submit"]
        XCTAssertTrue(submit.poll(NSPredicate(format: "label == %@ AND isEnabled == true", title), timeout: 5), app.debugDescription, file: file, line: line)
        submit.tap()
    }
    /// A menu item by title, apart from the button row's button of the same title.
    @MainActor func menuItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'group.action.')", title)).firstMatch
    }

    /// Password sign-in, then 搜索 → 资源 · 分组.
    @MainActor func launchAndOpenGroups(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("分组成员验收", in: "login.name")
        enter("https://group-members.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The list's row, then the detail once its card shows.
    @MainActor func openGroup(_ id: Int, arguments: [String] = []) {
        launchAndOpenGroups(arguments: arguments)
        let target = row(id)
        app.scrollUntilExists(target)
        target.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func row(_ id: Int) -> XCUIElement { app.buttons["group.row.\(id)"] }
    @MainActor func member(_ id: Int) -> XCUIElement { app.buttons["group.member.\(id)"] }
    @MainActor func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor func text(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    /// A member row's swipe button, by identifier or, where the swipe drops it, by title.
    @MainActor func swipeButton(of accountID: Int, action: String, titled title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.member.\(accountID).\(action)", title)).firstMatch
    }
    @MainActor func swipeMember(_ accountID: Int, to action: String, titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        member(accountID).swipeLeft()
        let button = swipeButton(of: accountID, action: action, titled: title)
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        button.tap()
    }
    /// Dialog buttons, apart from the rows' swipe buttons of the same title (`group.member.<id>.<action>`).
    @MainActor func dialogButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier ENDSWITH '.remove' OR identifier ENDSWITH '.status')", label)).firstMatch
    }
    /// The dialog's 取消 where the system draws one; otherwise a tap beside the floating dialog closes it.
    @MainActor func dismissDialog() {
        let cancel = dialogButton("取消")
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); return }
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, app.debugDescription)
        let below = sheet.frame.maxY + 80
        let y = below < app.frame.maxY - 120 ? below : sheet.frame.minY - 80
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: sheet.frame.midX, dy: y)).tap()
    }
    @MainActor func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor func tapReceiptAction(titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons["receipt.action"]
        XCTAssertTrue(action.poll(NSPredicate(format: "label == %@", title), timeout: 3), app.debugDescription, file: file, line: line)
        action.tap()
    }
    @MainActor func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Drags the page until the item sits above the keyboard or the tab bar, then lets it settle.
    @MainActor func reveal(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
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
    @MainActor func isAboveBottomBar(_ item: XCUIElement) -> Bool {
        let keyboard = app.keyboards.firstMatch, bar = app.tabBars.firstMatch
        if keyboard.exists { return item.frame.maxY <= keyboard.frame.minY }
        return !bar.exists || item.frame.maxY <= bar.frame.minY
    }
    @MainActor func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
