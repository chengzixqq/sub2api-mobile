import XCTest

/// 50 §0.5 (S5-05): 停用 / 启用 / 复制 / 删除 from the group list's left swipe and long press and the detail's ⋯ (S5-06), on
/// the `-ui-testing` site's group fixtures (GroupFixtures+Actions: each group's keys and subscriptions, copies, deletes and
/// `-ui-group-write-timeout`). Menu items are tapped by title (UIMenu may drop identifiers); receipts are up for 4.2 seconds, so
/// their buttons are tapped as soon as the words show.
final class GroupActionsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testSwipeDisableShowsKeyCountAndUndoRestores() {
        launchAndOpenGroups()
        defer { diagnostics("group-actions-swipe-disable-final") }
        let premium = row(1)
        app.scrollUntilExists(premium)
        swipe(premium, to: "disable", titled: "停用")
        let alert = app.alerts["停用「高级组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "站点 分组动作验收").exists, app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "使用这个分组的 36 个 API 密钥会被拒绝（提示“所属分组已停用”）。").exists, app.debugDescription)
        alert.buttons["停用分组"].tap()
        waitForReceipt("已停用「高级组」")
        tapReceiptAction(titled: "撤销")
        XCTAssertTrue(premium.poll(NSPredicate(format: "NOT (label CONTAINS %@)", "已停用"), timeout: 10), app.debugDescription)
        XCTAssertTrue(premium.label.contains("可用 2 / 3"), premium.label)
    }

    @MainActor func testLongPressDuplicateViewOpensCopy() {
        launchAndOpenGroups()
        defer { diagnostics("group-actions-duplicate-final") }
        let premium = row(1)
        app.scrollUntilExists(premium)
        premium.press(forDuration: 1.0)
        tapMenuItem("复制分组")
        waitForReceipt("已复制为「高级组 (Copy)」 · 停用中 · 3 个成员账号")
        tapReceiptAction(titled: "查看")
        XCTAssertTrue(app.navigationBars["高级组 (Copy)"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let copy = row(12)
        app.scrollUntilExists(copy)
        XCTAssertTrue(copy.label.contains("已停用"), copy.label)
        app.scrollUntilExists(premium, towardBottom: false)
        premium.press(forDuration: 1.0)
        tapMenuItem("复制分组")
        waitForReceipt("已复制为「高级组 (Copy 2)」 · 停用中 · 3 个成员账号")
    }

    @MainActor func testDeleteNeedsTheFullNameAndRemovesTheRow() {
        launchAndOpenGroups()
        defer { diagnostics("group-actions-delete-name-final") }
        let target = row(10)
        app.scrollUntilExists(target)
        target.press(forDuration: 1.0)
        tapMenuItem("删除分组…")
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除分组「Antigravity 组」？")
        XCTAssertEqual(element("delete.message").label, "站点 分组动作验收 · 删除后不能恢复。")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "删除分组")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("Antigravity")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText(" 组")
        XCTAssertTrue(confirm.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        confirm.tap()
        waitForReceipt("已删除分组「Antigravity 组」")
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(target.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["分组"].exists, app.debugDescription)
    }

    @MainActor func testDeleteConsequencesListKeysSubscriptionsAndMembers() {
        launchAndOpenGroups()
        defer { diagnostics("group-actions-delete-consequences-final") }
        let target = row(4)
        app.scrollUntilExists(target)
        target.press(forDuration: 1.0)
        tapMenuItem("删除分组…")
        let message = element("delete.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        for line in ["站点 分组动作验收 · 删除后不能恢复。", "使用这个分组的 6 个 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。",
                     "删除 15 条订阅记录（生效中 12 条）。", "1 个成员账号移出分组，账号本身保留。"] {
            XCTAssertTrue(message.label.contains(line), "“\(line)” missing in “\(message.label)”")
        }
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(target.exists, app.debugDescription)
    }

    @MainActor func testFaceIDDeleteFromDetailLeavesFirst() {
        launchAndOpenGroups(arguments: ["-ui-faceid-on"])
        defer { diagnostics("group-actions-delete-faceid-final") }
        let target = row(3)
        app.scrollUntilExists(target)
        target.tap()
        XCTAssertTrue(app.navigationBars["默认组"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["group.more"].tap()
        tapMenuItem("删除分组…")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        XCTAssertTrue(element("delete.message").label.hasSuffix("确认后验证 Face ID。"), element("delete.message").label)
        confirm.tap()
        waitForReceipt("已删除分组「默认组」")
        XCTAssertTrue(app.navigationBars["分组"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(target.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUnconfirmedDisableReadsBackThenRetriesTheSameNumber() {
        launchAndOpenGroups(arguments: ["-ui-group-write-timeout"])
        defer { diagnostics("group-actions-unconfirmed-final") }
        let standard = row(2)
        app.scrollUntilExists(standard)
        swipe(standard, to: "disable", titled: "停用")
        let alert = app.alerts["停用「标准组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["停用分组"].tap()
        waitForReceipt("停用结果未确认，可用同一编号重试")
        tapReceiptAction(titled: "用同一编号重试")
        waitForReceipt("已停用「标准组」")
        app.scrollUntilExists(standard)
        XCTAssertTrue(standard.poll(NSPredicate(format: "label CONTAINS %@", "已停用"), timeout: 10), standard.label)
    }

    // MARK: - Helpers

    /// Password sign-in, then 搜索 → 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("分组动作验收", in: "login.name")
        enter("https://group-actions.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func row(_ id: Int) -> XCUIElement { app.buttons["group.row.\(id)"] }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
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
    /// The left swipe's button, by identifier or, where the swipe drops it, by title.
    @MainActor private func swipe(_ row: XCUIElement, to action: String, titled title: String) {
        row.swipeLeft()
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.swipe.\(action)", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }
    @MainActor private func tapMenuItem(_ title: String) {
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    @MainActor private func alertText(_ alert: XCUIElement, containing part: String) -> XCUIElement {
        alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func tapReceiptAction(titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons["receipt.action"]
        XCTAssertTrue(action.poll(NSPredicate(format: "label == %@", title), timeout: 3), app.debugDescription, file: file, line: line)
        action.tap()
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
