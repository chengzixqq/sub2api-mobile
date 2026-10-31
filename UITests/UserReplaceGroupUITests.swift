import XCTest

/// S3-15 Key 与限额 · 替换分组 (30 §8.3–§8.4): 王小明 (3) has Claude Code 组 (5) with Key 301「脚本」bound to it, 测试用户 13 has
/// group 5 and no key, Bob (2) no exclusive group; 11 Codex 专线 is the other active exclusive standard group (S3D1-04, S3D1-15).
final class UserReplaceGroupUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testReplaceShowsReceiptAndMovesKeys() {
        launchAndLogin()
        defer { diagnostics("user-replace-receipt-final") }
        openKeys(3, name: "王小明")
        let footnote = element("keys.replace.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "把一个专属分组换成另一个：绑定的 Key 一起迁移，旧分组的权限随之移除。")
        let row = app.buttons["keys.replace.row.5"]
        reveal(row)
        XCTAssertTrue(row.label.contains("替换「Claude Code 组」…") && row.label.contains("绑定 1 个 Key"), row.label)
        row.tap()
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("keys.replace.note").label, "选择新分组替换「Claude Code 组」，将自动迁移绑定的 1 个 Key 并更新分组权限。")
        let submit = app.buttons["keys.replace.submit"]
        XCTAssertTrue(submit.label.contains("选择目标分组") && !submit.isEnabled, submit.label)
        let option = app.buttons["keys.replace.option.11"]
        XCTAssertTrue(option.label.contains("Codex 专线") && option.label.contains("OpenAI · 专属分组 · 默认倍率 ×1"), option.label)
        XCTAssertFalse(app.buttons["keys.replace.option.5"].exists || app.buttons["keys.replace.option.4"].exists, app.debugDescription)
        option.tap()
        XCTAssertTrue(waitUntil(submit, "label CONTAINS '替换为「Codex 专线」'"), submit.label)
        submit.tap()
        let alert = app.alerts["把「Claude Code 组」替换为「Codex 专线」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["王小明绑定在「Claude Code 组」的 1 个 Key 会迁移到「Codex 专线」，并移除「Claude Code 组」的使用权限。立即生效，不经过“保存”。"].exists,
                      app.debugDescription)
        alert.buttons["确认替换"].tap()
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        XCTAssertEqual(app.buttons["receipt.action"].label, "撤销")
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Codex 专线")
        let replaced = app.buttons["keys.replace.row.11"]
        reveal(replaced)
        XCTAssertTrue(replaced.label.contains("替换「Codex 专线」…") && replaced.label.contains("绑定 1 个 Key"), replaced.label)
        XCTAssertFalse(row.exists, app.debugDescription)
    }

    @MainActor func testUndoRestoresExactly() {
        launchAndLogin()
        defer { diagnostics("user-replace-undo-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        app.buttons["receipt.action"].tap()
        let row = app.buttons["keys.replace.row.5"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["keys.replace.row.11"].exists, app.debugDescription)
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Claude Code 组")
        let access = app.buttons["user-edit.segment.access"]
        access.tap()
        let group = app.buttons["user-edit.exclusive.5"]
        reveal(group)
        XCTAssertTrue(group.label.contains("专属倍率 ×1.3") && group.label.contains("绑定 1 个 Key"), group.label)
        XCTAssertFalse(app.buttons["user-edit.exclusive.11"].exists, app.debugDescription)
        XCTAssertFalse(access.label.contains("已改"), access.label)
    }

    @MainActor func testEmptyMigrationUndoUsesAllowedGroups() {
        launchAndLogin()
        defer { diagnostics("user-replace-empty-final") }
        openKeys(13, name: "测试用户 13", viaMenu: true)
        let row = app.buttons["keys.replace.row.5"]
        reveal(row)
        XCTAssertTrue(row.label.contains("绑定 0 个 Key"), row.label)
        replace(5, with: 11)
        waitForReceipt("分组替换成功，已迁移 0 个 Key")
        XCTAssertTrue(app.buttons["keys.replace.row.11"].waitForExistence(timeout: 5), app.debugDescription)
        // The fixture refuses a reverse replace without key_ids: the undo has to go through allowed_groups.
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["keys.replace.row.11"].exists, app.debugDescription)
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertFalse(receipt.exists && receipt.label.hasPrefix("撤销没有成功"), receipt.label)
    }

    @MainActor func testEnterFromRemoveGroupConfirmation() {
        launchAndLogin()
        defer { diagnostics("user-replace-from-remove-final") }
        openKeys(3, name: "王小明", viaMenu: true, segment: "access")
        let group = app.buttons["user-edit.exclusive.5"]
        reveal(group)
        group.tap()
        let remove = app.buttons["user-edit.group-sheet.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription)
        remove.tap()
        let alert = app.alerts["移除「Claude Code 组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["改用替换分组"].tap()
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("keys.replace.note").label, "选择新分组替换「Claude Code 组」，将自动迁移绑定的 1 个 Key 并更新分组权限。")
        app.buttons["keys.replace.option.11"].tap()
        app.buttons["keys.replace.submit"].tap()
        let confirm = app.alerts["把「Claude Code 组」替换为「Codex 专线」？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.buttons["确认替换"].tap()
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        XCTAssertTrue(app.buttons["user-edit.exclusive.11"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["user-edit.exclusive.5"].exists, "替换不是“保存”前的移除：\(app.debugDescription)")
        XCTAssertFalse(app.buttons["user-edit.segment.access"].label.contains("已改"), app.buttons["user-edit.segment.access"].label)
    }

    @MainActor func testTargetInactiveStaysInSheet() {
        launchAndLogin(arguments: ["-ui-replace-target-inactive"])
        defer { diagnostics("user-replace-inactive-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        let error = element("keys.replace.error")
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(error.label, "目标分组已停用")
        XCTAssertTrue(app.navigationBars["替换专属分组"].exists, app.debugDescription)
        let option = app.buttons["keys.replace.option.11"]
        XCTAssertTrue(option.isEnabled, app.debugDescription)
        option.tap()
        XCTAssertTrue(waitUntil(app.buttons["keys.replace.submit"], "isEnabled == true"), app.debugDescription)
        XCTAssertFalse(error.exists, "重选后红字消失")
    }

    @MainActor func testUndoSourceInactive() {
        launchAndLogin(arguments: ["-ui-replace-undo-source-inactive"])
        defer { diagnostics("user-replace-undo-inactive-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        app.buttons["receipt.action"].tap()
        waitForReceipt("原分组已停用，无法撤销")
        XCTAssertTrue(app.buttons["keys.replace.row.11"].exists, app.debugDescription)
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Codex 专线")
    }

    @MainActor func testUncertainResultReadsBack() {
        launchAndLogin(arguments: ["-ui-replace-uncertain"])
        defer { diagnostics("user-replace-uncertain-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        waitForReceipt("分组替换已生效")
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["keys.replace.row.11"].waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Codex 专线")
    }

    @MainActor func testEmptyTargetsAndHiddenSection() {
        launchAndLogin()
        defer { diagnostics("user-replace-empty-targets-final") }
        openKeys(2, name: "Bob", viaMenu: true)
        reveal(element("keys.quota.footnote"))
        XCTAssertFalse(element("keys.replace.section").exists, app.debugDescription)
        backToUsers()
        openKeys(3, name: "王小明", viaMenu: true, segment: "access")
        let add = app.buttons["user-edit.exclusive.add"]
        reveal(add)
        add.tap()
        let pick = app.buttons["user-edit.add-groups.11"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5), app.debugDescription)
        pick.tap()
        app.buttons["user-edit.add-groups.confirm"].tap()
        XCTAssertTrue(pick.waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["user-edit.segment.keys"].tap()
        XCTAssertTrue(element("keys.notice").waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["keys.replace.row.5"]
        reveal(row)
        row.tap()
        let empty = element("keys.replace.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(empty.label, "没有其他可用的专属分组")
        let submit = app.buttons["keys.replace.submit"]
        XCTAssertTrue(submit.label.contains("选择目标分组") && !submit.isEnabled, submit.label)
        app.buttons["keys.replace.cancel"].tap()
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testLeaveConfirmationListsReplace() {
        launchAndLogin()
        defer { diagnostics("user-replace-leave-final") }
        openKeys(3, name: "王小明", viaMenu: true, segment: "basic")
        type("小明", into: "user-edit.username")
        app.buttons["user-edit.segment.keys"].tap()
        XCTAssertTrue(element("keys.notice").waitForExistence(timeout: 10), app.debugDescription)
        replace(5, with: 11)
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        app.buttons["user-edit.back"].tap()
        let alert = app.alerts["放弃未保存的更改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        let line = "已经立即生效、不会撤回：替换分组（Claude Code 组 → Codex 专线）。"
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", line)).firstMatch.exists, app.debugDescription)
        alert.buttons["继续编辑"].tap()
    }

    @MainActor func testReadOnlyTokenDisablesReplace() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-replace-read-only-final") }
        openKeys(3, name: "王小明")
        let row = app.buttons["keys.replace.row.5"]
        reveal(row)
        XCTAssertFalse(row.isEnabled, app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == 'readonly.caption' AND label == '只读令牌'")).firstMatch.exists,
                      app.debugDescription)
    }

    /// The user got Codex 专线 on the Web after the page was read (new_group_newly_granted false): the page takes it on all the
    /// same, and the undo keeps it (keep_old_group_access) while Claude Code 组 comes back.
    @MainActor func testTargetGrantedElsewhereJoinsBaseAndStaysAfterUndo() {
        launchAndLogin(arguments: ["-ui-replace-target-granted"])
        defer { diagnostics("user-replace-target-granted-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        let replaced = app.buttons["keys.replace.row.11"]
        XCTAssertTrue(replaced.waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(app.buttons["keys.replace.row.5"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(replaced.exists, "撤销保留网页上授予的「Codex 专线」：\(app.debugDescription)")
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Claude Code 组")
        let access = app.buttons["user-edit.segment.access"]
        access.tap()
        XCTAssertTrue(app.buttons["user-edit.exclusive.5"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user-edit.exclusive.11"].exists, app.debugDescription)
        XCTAssertFalse(access.label.contains("已改"), access.label)
    }

    /// 00 §2.5.4: the reply and the read back are both lost. The sheet may close, but the page keeps the number: the sheet opened
    /// again has the same target, and sending it again answers the first result with its exact undo.
    @MainActor func testUnreadResultKeepsItsNumberAfterTheSheetCloses() {
        launchAndLogin(arguments: ["-ui-replace-uncertain", "-ui-replace-unread"])
        defer { diagnostics("user-replace-unread-final") }
        openKeys(3, name: "王小明")
        replace(5, with: 11)
        let error = element("keys.replace.error")
        XCTAssertTrue(error.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(error.label, "结果未确认，请刷新后检查")
        app.buttons["keys.replace.cancel"].tap()
        XCTAssertTrue(app.navigationBars["替换专属分组"].waitForNonExistence(timeout: 5), app.debugDescription)
        let row = app.buttons["keys.replace.row.5"]
        reveal(row)
        XCTAssertTrue(waitUntil(row, "isEnabled == true"), app.debugDescription)
        row.tap()
        let submit = app.buttons["keys.replace.submit"]
        XCTAssertTrue(waitUntil(submit, "label CONTAINS '替换为「Codex 专线」' AND isEnabled == true"), submit.label)
        XCTAssertEqual(element("keys.replace.error").label, "结果未确认，请刷新后检查")
        submit.tap()
        let confirm = app.alerts.buttons["确认替换"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        waitForReceipt("分组替换成功，已迁移 1 个 Key")
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["keys.replace.row.11"].exists, app.debugDescription)
        waitForLabel(revealUp(element("keys.card.301.meta")), contains: "Claude Code 组")
    }

    // MARK: - Helpers

    /// Password sign-in, or the access-token method for `accessToken` (a `sat_` key selects it on its own).
    @MainActor private func launchAndLogin(arguments: [String] = [], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://user-replace.example.invalid", in: app.textFields["login.url"])
        enter("替换分组验收", in: app.textFields["login.name"])
        if let accessToken {
            tap(app.buttons["login.method.adminKey"])
            enter(accessToken, in: app.secureTextFields["login.key"])
        } else {
            enter("admin@example.com", in: app.textFields["login.email"])
            enter("fixture-password", in: app.secureTextFields["login.password"])
        }
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The detail's key summary lands on the third segment; `viaMenu` goes through ⋯ 编辑用户 and then `segment`.
    @MainActor private func openKeys(_ id: Int, name: String, viaMenu: Bool = false, segment: String = "keys") {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["user.\(id)"]
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
        if viaMenu {
            let more = app.buttons["user.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
            more.tap()
            let item = app.buttons["编辑用户"]
            XCTAssertTrue(item.waitForExistence(timeout: 3), app.debugDescription)
            item.tap()
            let tab = app.buttons["user-edit.segment.\(segment)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), app.debugDescription)
            tab.tap()
        } else {
            let keys = app.buttons["user.keys"]
            XCTAssertTrue(app.scrollUntilExists(keys))
            keys.tap()
        }
        if segment == "keys" { XCTAssertTrue(element("keys.notice").waitForExistence(timeout: 10), app.debugDescription) }
    }
    /// The section's row, the target, “替换为「…」” and “确认替换”.
    @MainActor private func replace(_ source: Int, with target: Int) {
        let row = app.buttons["keys.replace.row.\(source)"]
        reveal(row)
        XCTAssertTrue(waitUntil(row, "isEnabled == true"), app.debugDescription)
        row.tap()
        let option = app.buttons["keys.replace.option.\(target)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription)
        option.tap()
        let submit = app.buttons["keys.replace.submit"]
        XCTAssertTrue(waitUntil(submit, "isEnabled == true"), app.debugDescription)
        submit.tap()
        let confirm = app.alerts.buttons["确认替换"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
    }
    /// From the edit page back to the list: the edit page, then the detail.
    @MainActor private func backToUsers() {
        for _ in 0..<3 where !app.buttons["user.1"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            _ = app.buttons["user.1"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons["user.1"].exists, app.debugDescription)
    }
    /// Replaces the field's text.
    @MainActor private func type(_ value: String, into identifier: String) {
        let field = element(identifier)
        reveal(field)
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "回执应为「\(text)」\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)], timeout: 5) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// Drags the form (over the row labels, away from the edge-swipe area) until the element sits between the page's head and
    /// the keyboard; a row not loaded yet is looked for below first, then above.
    @MainActor private func reveal(_ item: XCUIElement) {
        for attempt in 0..<16 {
            let (top, bottom) = visibleBand()
            if item.exists && item.isHittable && item.frame.minY >= top && item.frame.maxY <= bottom { return }
            let up = item.exists ? item.frame.maxY < top : attempt >= 8
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.75))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            (up ? upper : lower).press(forDuration: 0.05, thenDragTo: up ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    /// A key card sits at the top of the segment: the form is dragged down until it shows.
    @discardableResult @MainActor private func revealUp(_ item: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !(item.exists && item.isHittable) {
            let (top, bottom) = visibleBand()
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.75)), withVelocity: .slow,
                       thenHoldForDuration: 0.2)
        }
        return item
    }
    /// Below the navigation bar and the page head, above the keyboard and a receipt.
    @MainActor private func visibleBand() -> (CGFloat, CGFloat) {
        let frame = app.frame
        var top = shownFrame(app.navigationBars.firstMatch)?.maxY ?? frame.minY + 100
        var bottom = frame.maxY - 40
        if let segments = shownFrame(element("user-edit.segment.basic")) { top = max(top, segments.maxY + 36) }
        if let keyboard = shownFrame(app.keyboards.firstMatch) { bottom = min(bottom, keyboard.minY) }
        if let receipt = shownFrame(element("receipt")) { bottom = min(bottom, receipt.minY) }
        return (top, max(bottom, top + 80))
    }
    /// A receipt leaving on its 4.2-second timer between `exists` and `frame` would fail the test, so the frame comes from a
    /// snapshot, which only throws then; `exists` first, as a snapshot of a missing element retries for about 2 seconds.
    @MainActor private func shownFrame(_ item: XCUIElement) -> CGRect? { item.exists ? (try? item.snapshot())?.frame : nil }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
