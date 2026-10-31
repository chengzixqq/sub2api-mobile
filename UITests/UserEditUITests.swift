import XCTest

/// S3-11 编辑用户 (30 §6): the pushed page over the user detail, its segments and marks, the strict save fixture (a key equal to
/// the user's value is a 400, S3D1-10), leaving, the last administrator, one's own account, rates, removal, the password fold,
/// refusals, unknown results, attributes, ⋯ and the read-only token. 王小明 (3) has Claude Code 组 (5) at ×1.3 and Key 301
/// bound to it; 陈思远 (8) is an administrator (S3D1-04).
final class UserEditUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testEditSendsOnlyChangedFields() {
        launchAndLogin()
        defer { diagnostics("user-edit-only-changed-final") }
        openEditor(3, name: "王小明")
        XCTAssertEqual(element("user-edit.hint").label, "基础、权限与并发改完点右上“保存”，两段一起提交")
        XCTAssertFalse(app.buttons["user-edit.save"].isEnabled)
        type("小明", into: "user-edit.username")
        waitForLabel(app.buttons["user-edit.segment.basic"], contains: "已改 1 项")
        app.buttons["user-edit.segment.access"].tap()
        tap(app.buttons["user-edit.concurrency.plus"])
        reveal(element("user-edit.concurrency.value"))
        waitForLabel(element("user-edit.concurrency.value"), contains: "2")
        type("高峰期临时加并发", into: "user-edit.adjustment")
        XCTAssertTrue(text(containing: "调整备注只写进这次的并发流水").exists, app.debugDescription)
        waitForLabel(app.buttons["user-edit.segment.access"], contains: "已改 1 项")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 2 项更改")
        XCTAssertTrue(app.navigationBars["小明"].waitForExistence(timeout: 10), app.debugDescription)
        chooseFromMenu("编辑用户")
        XCTAssertTrue(element("user-edit.username").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("user-edit.username").value as? String, "小明")
        app.buttons["user-edit.segment.access"].tap()
        let value = element("user-edit.concurrency.value")
        reveal(value)
        waitForLabel(value, contains: "2")
        XCTAssertFalse(element("user-edit.adjustment").exists, app.debugDescription)
    }

    @MainActor func testSegmentMarksAndErrors() {
        launchAndLogin()
        defer { diagnostics("user-edit-marks-final") }
        openEditor(3, name: "王小明")
        type("bad", into: "user-edit.email")
        waitForLabel(app.buttons["user-edit.segment.basic"], contains: "已改 1 项")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("还有 1 项需要填写或修改")
        XCTAssertEqual(element("user-edit.email.error").label, "邮箱格式不对")
        waitForLabel(app.buttons["user-edit.segment.basic"], contains: "有 1 项要修改")
        // Switching segments drops the email field's focus, so the head unfolds and shows its line again.
        app.buttons["user-edit.segment.access"].tap()
        waitForLabel(element("user-edit.hint"), contains: "基础 1 项要修改、已改 1 项")
    }

    @MainActor func testLeaveConfirmation() {
        launchAndLogin()
        defer { diagnostics("user-edit-leave-final") }
        openEditor(3, name: "王小明")
        type("渠道客户", into: "user-edit.notes")
        app.buttons["user-edit.back"].tap()
        let alert = app.alerts["放弃未保存的更改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["备注还没保存，会被放弃。"].exists, app.debugDescription)
        alert.buttons["继续编辑"].tap()
        XCTAssertTrue(element("user-edit.notes").exists, app.debugDescription)
        // A top-up from the strip took effect at once, so leaving names it.
        app.buttons["user-edit.topup"].tap()
        XCTAssertTrue(app.buttons["balance.key.5"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["balance.key.5"].tap()
        app.buttons["balance.submit"].tap()
        let topUp = app.alerts["向「王小明」充值 $5.00？"]
        XCTAssertTrue(topUp.waitForExistence(timeout: 10), app.debugDescription)
        topUp.buttons["充值 $5.00"].tap()
        waitForReceipt("已向 王小明 充值 $5.00")
        waitForLabel(element("user-edit.identity"), contains: "$17.40")
        XCTAssertEqual(element("user-edit.notes").value as? String, "渠道客户", "立即生效的操作不覆盖草稿")
        app.buttons["user-edit.back"].tap()
        let again = app.alerts["放弃未保存的更改？"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(again.staticTexts["备注还没保存，会被放弃。\n已经立即生效、不会撤回：余额。"].exists, app.debugDescription)
        again.buttons["继续编辑"].tap()
        app.buttons["user-edit.back"].tap()
        XCTAssertTrue(app.alerts["放弃未保存的更改？"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["王小明"].waitForExistence(timeout: 10), app.debugDescription)
        chooseFromMenu("编辑用户")
        XCTAssertTrue(element("user-edit.notes").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["user-edit.back"].exists, "没有改动时用系统返回")
        goBack()
        XCTAssertTrue(app.navigationBars["王小明"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    @MainActor func testLastAdminDemotionBlocked() {
        launchAndLogin(arguments: ["-ui-user-last-admin"])
        defer { diagnostics("user-edit-last-admin-final") }
        openEditor(8, name: "陈思远")
        app.buttons["user-edit.segment.access"].tap()
        chooseRole("用户")
        XCTAssertTrue(text(containing: "降级后会失去后台权限").exists, app.debugDescription)
        app.buttons["user-edit.save"].tap()
        waitForReceipt("保存失败：不能降级站点最后一个管理员")
        XCTAssertEqual(element("user-edit.role.error").label, "站点只剩这一位管理员，不能降级")
        XCTAssertTrue(element("user-edit.role").exists, "留在编辑页")
        chooseRole("管理员")
        XCTAssertTrue(element("user-edit.role.error").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testOwnRoleLocked() {
        launchAndLogin(arguments: ["-ui-users-self", "8"])
        defer { diagnostics("user-edit-self-final") }
        openEditor(8, name: "陈思远")
        let identity = element("user-edit.identity")
        waitForLabel(identity, contains: "你")
        reveal(app.switches["user-edit.status"])
        XCTAssertFalse(app.switches["user-edit.status"].isEnabled)
        XCTAssertEqual(element("user-edit.status.subtitle").label, "管理员不能禁用")
        app.buttons["user-edit.segment.access"].tap()
        let role = app.segmentedControls["user-edit.role"]
        reveal(role)
        XCTAssertTrue(role.buttons["管理员"].isSelected)
        XCTAssertFalse(role.buttons["用户"].isEnabled)
        XCTAssertEqual(element("user-edit.role.footnote").label, "这是你当前登录的账号（陈思远）：不能把自己降级，也不能禁用或删除。")
        app.buttons["user-edit.more"].tap()
        // A menu item with a subtitle may read both lines as its label.
        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "删除用户…")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(delete.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "管理员不能删除")).firstMatch.exists,
                      app.debugDescription)
    }

    @MainActor func testExclusiveRateSetAndCleared() {
        launchAndLogin()
        defer { diagnostics("user-edit-rate-final") }
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        let row = app.buttons["user-edit.exclusive.5"]
        reveal(row)
        waitForLabel(row, contains: "专属倍率 ×1.3")
        XCTAssertTrue(row.label.contains("Anthropic · 绑定 1 个 Key"), row.label)
        row.tap()
        let rate = element("user-edit.group-sheet.rate")
        XCTAssertTrue(rate.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("user-edit.group-sheet.note").label.contains("绑定 1 个 Key"), app.debugDescription)
        replace(rate, with: "0")
        XCTAssertEqual(element("user-edit.group-sheet.rate.error").label, "要大于 0，最多 3 位小数")
        XCTAssertFalse(app.buttons["user-edit.group-sheet.done"].isEnabled)
        replace(rate, with: "1.25")
        app.buttons["user-edit.group-sheet.done"].tap()
        waitForLabel(row, contains: "专属倍率 ×1.25")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 1 项更改")
        chooseFromMenu("编辑用户")
        XCTAssertTrue(app.buttons["user-edit.segment.access"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user-edit.segment.access"].tap()
        reveal(row)
        waitForLabel(row, contains: "专属倍率 ×1.25")
        row.tap()
        let reset = app.buttons["user-edit.group-sheet.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(reset.label, "改回默认倍率 ×0.8")
        reset.tap()
        app.buttons["user-edit.group-sheet.done"].tap()
        waitForLabel(row, contains: "默认 ×0.8")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 1 项更改")
    }

    @MainActor func testRemoveExclusiveGroupReceipt() {
        launchAndLogin()
        defer { diagnostics("user-edit-remove-group-final") }
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        removeGroup5()
        let removed = element("user-edit.exclusive.5")
        waitForLabel(removed, contains: "保存后移除 · 1 个 Key 会无法调用")
        app.buttons["user-edit.exclusive.5.undo"].tap()
        waitForLabel(app.buttons["user-edit.exclusive.5"], contains: "专属倍率 ×1.3")
        removeGroup5()
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 1 项更改；绑定在「Claude Code 组」的 1 个 Key 将无法调用")
        XCTAssertTrue(app.navigationBars["王小明"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testPasswordFoldAndValidation() {
        launchAndLogin()
        defer { diagnostics("user-edit-password-final") }
        openEditor(1, name: "Alice")
        let fold = app.buttons["user-edit.password.fold"]
        reveal(fold)
        XCTAssertTrue(fold.label.contains("重置密码 · 不修改"), fold.label)
        XCTAssertFalse(element("user-edit.password").exists)
        fold.tap()
        type("short", into: "user-edit.password")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("还有 1 项需要填写或修改")
        XCTAssertEqual(element("user-edit.password.error").label, "至少 6 位")
        tap(app.buttons["user-edit.password.generate"])
        XCTAssertTrue(waitUntil(element("user-edit.password"), "value MATCHES '^[A-Za-z2-9]{4}-[A-Za-z2-9]{4}-[A-Za-z2-9]{4}$'"), app.debugDescription)
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 1 项更改")
        chooseFromMenu("编辑用户")
        reveal(app.buttons["user-edit.password.fold"])
        XCTAssertTrue(app.buttons["user-edit.password.fold"].label.contains("不修改"), app.debugDescription)
    }

    @MainActor func testEmailTaken() {
        launchAndLogin()
        defer { diagnostics("user-edit-email-taken-final") }
        openEditor(3, name: "王小明")
        type("bob@example.com", into: "user-edit.email")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("保存失败：这个邮箱已被其他用户使用")
        XCTAssertEqual(element("user-edit.email.error").label, "已被其他用户使用")
    }

    @MainActor func testUncertainSaveReadsBack() {
        launchAndLogin(arguments: ["-ui-user-save-uncertain"])
        defer { diagnostics("user-edit-uncertain-final") }
        openEditor(3, name: "王小明")
        type("渠道客户", into: "user-edit.notes")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("已保存 1 项更改")
        XCTAssertTrue(app.navigationBars["王小明"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testDriftedSaveKeepsTheDraft() {
        launchAndLogin(arguments: ["-ui-user-save-drift"])
        defer { diagnostics("user-edit-drift-final") }
        openEditor(3, name: "王小明")
        type("渠道客户", into: "user-edit.notes")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("服务器上的资料与你的修改不一致，请检查后再保存")
        XCTAssertEqual(element("user-edit.notes").value as? String, "渠道客户")
        XCTAssertTrue(app.buttons["user-edit.save"].isEnabled)
    }

    @MainActor func testAttributeFailureStays() {
        launchAndLogin(arguments: ["-ui-user-attr-fail"])
        defer { diagnostics("user-edit-attr-fail-final") }
        openEditor(3, name: "王小明")
        XCTAssertTrue(waitUntil(element("user-edit.attr.11"), "value == 'Studio-K'"), app.debugDescription)
        type("渠道客户", into: "user-edit.notes")
        type("Studio-Q", into: "user-edit.attr.11")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("资料已保存，自定义属性没保存成功")
        XCTAssertTrue(element("user-edit.attr.11").exists, "留在编辑页")
        waitForLabel(app.buttons["user-edit.segment.basic"], contains: "已改 1 项")
    }

    @MainActor func testCopyEmailAndDelete() {
        launchAndLogin()
        defer { diagnostics("user-edit-delete-final") }
        openEditor(3, name: "王小明")
        chooseFromEditMenu("复制邮箱")
        waitForReceipt("已复制邮箱")
        chooseFromEditMenu("删除用户…")
        let input = element("delete.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("delete.message").label.contains("名下 1 个 Key 一并删除。"), app.debugDescription)
        input.tap()
        input.typeText("王小明")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        waitForReceipt("已删除用户「王小明」")
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["user.3"].exists, app.debugDescription)
        XCTAssertFalse(app.navigationBars["王小明"].exists, app.debugDescription)
    }

    @MainActor func testKeysSegmentFromDetail() {
        launchAndLogin()
        defer { diagnostics("user-edit-keys-final") }
        openUser(3, name: "王小明")
        let keys = app.buttons["user.keys"]
        XCTAssertTrue(app.scrollUntilExists(keys))
        keys.tap()
        let segment = app.buttons["user-edit.segment.keys"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10), app.debugDescription)
        waitForLabel(segment, contains: "Key 与限额（1）")
        XCTAssertTrue(segment.isSelected, app.debugDescription)
        XCTAssertTrue(element("keys.card.301").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user-edit.segment.basic"].tap()
        XCTAssertTrue(element("user-edit.email").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testRPMStatusStates() {
        launchAndLogin()
        defer { diagnostics("user-edit-rpm-final") }
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        let total = element("user-edit.rpm.total")
        reveal(total)
        waitForLabel(total, contains: "2 / 60")
        let group = element("user-edit.rpm.group.5")
        XCTAssertTrue(group.label.contains("Claude Code 组") && group.label.contains("专属 RPM") && group.label.contains("2 / 30"), group.label)
        XCTAssertTrue(text(containing: "RPM 状态 · 本分钟").exists, app.debugDescription)
        app.terminate()
        launchAndLogin(arguments: ["-ui-user-rpm-unavailable"])
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        let unavailable = element("user-edit.rpm.unavailable")
        reveal(unavailable)
        XCTAssertEqual(unavailable.label, "RPM 状态暂不可用")
        app.terminate()
        launchAndLogin(arguments: ["-ui-user-rpm-failed"])
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        let retry = app.buttons["user-edit.rpm.retry"]
        reveal(retry)
        XCTAssertEqual(retry.label, "RPM 状态加载失败 · 重试")
    }

    @MainActor func testReadOnlyTokenGraysSave() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-edit-read-only-final") }
        openUser(1, name: "Alice")
        let keys = app.buttons["user.keys"]
        XCTAssertTrue(app.scrollUntilExists(keys))
        keys.tap()
        XCTAssertTrue(app.buttons["user-edit.segment.basic"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user-edit.segment.basic"].tap()
        XCTAssertFalse(app.buttons["user-edit.topup"].isEnabled)
        type("只读改动", into: "user-edit.notes")
        XCTAssertFalse(app.buttons["user-edit.save"].isEnabled)
    }

    /// 30 §6.6: the block reads again every 15 seconds while it stays on screen, also after its first value replaced the spinner.
    @MainActor func testRPMStatusKeepsRefreshingWhileShown() {
        launchAndLogin(arguments: ["-ui-user-rpm-ticking"])
        defer { diagnostics("user-edit-rpm-refresh-final") }
        openEditor(3, name: "王小明")
        app.buttons["user-edit.segment.access"].tap()
        let total = element("user-edit.rpm.total")
        reveal(total)
        waitForLabel(total, contains: "/ 60")
        let first = total.label
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: total)
        XCTAssertEqual(XCTWaiter().wait(for: [next], timeout: 25), .completed, "15 秒后应再读一次：\(first)\n\(app.debugDescription)")
    }

    /// 30 §6.4 step 7: the profile PUT took Claude Code 组 (and its ×1.3) away and the attributes failed. The page stays, and the
    /// saved removal no longer counts as a change, so the next “保存” sends nothing more for the group.
    @MainActor func testAttributeFailureSettlesARemovedGroup() {
        launchAndLogin(arguments: ["-ui-user-attr-fail"])
        defer { diagnostics("user-edit-attr-fail-removed-final") }
        openEditor(3, name: "王小明")
        XCTAssertTrue(waitUntil(element("user-edit.attr.11"), "value == 'Studio-K'"), app.debugDescription)
        type("Studio-Q", into: "user-edit.attr.11")
        let access = app.buttons["user-edit.segment.access"]
        access.tap()
        removeGroup5()
        waitForLabel(access, contains: "已改 1 项")
        app.buttons["user-edit.save"].tap()
        waitForReceipt("资料已保存，自定义属性没保存成功")
        waitForLabel(app.buttons["user-edit.segment.basic"], contains: "已改 1 项")
        XCTAssertFalse(access.label.contains("已改"), access.label)
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
        enter("https://user-edit.example.invalid", in: app.textFields["login.url"])
        enter("编辑用户验收", in: app.textFields["login.name"])
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
    @MainActor private func openUser(_ id: Int, name: String) {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["user.\(id)"]
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The detail's ⋯ 编辑用户; the system menu's items are found by their words.
    @MainActor private func openEditor(_ id: Int, name: String) {
        openUser(id, name: name)
        chooseFromMenu("编辑用户")
        XCTAssertTrue(app.navigationBars["编辑用户"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user-edit.email").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func chooseFromMenu(_ title: String) {
        let more = app.buttons["user.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    @MainActor private func chooseFromEditMenu(_ title: String) {
        app.buttons["user-edit.more"].tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    @MainActor private func removeGroup5() {
        let row = app.buttons["user-edit.exclusive.5"]
        reveal(row)
        row.tap()
        let remove = app.buttons["user-edit.group-sheet.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription)
        remove.tap()
        let alert = app.alerts["移除「Claude Code 组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["绑定在「Claude Code 组」的 1 个 Key 会无法调用。要保留请用替换分组。"].exists, app.debugDescription)
        // S3-15: a group the user has offers the replace instead.
        XCTAssertTrue(alert.buttons["改用替换分组"].exists, app.debugDescription)
        alert.buttons["仍要移除"].tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func chooseRole(_ title: String) {
        let role = app.segmentedControls["user-edit.role"]
        reveal(role)
        role.buttons[title].tap()
        XCTAssertTrue(waitUntil(role.buttons[title], "isSelected == true"), app.debugDescription)
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    /// Replaces the field's text.
    @MainActor private func type(_ value: String, into identifier: String) {
        let field = element(identifier)
        reveal(field)
        replace(field, with: value)
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String) {
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
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// Drags the form (over the row labels, away from the edge-swipe area) until the element sits between the page's head and
    /// the keyboard; a row not loaded yet is looked for below first, then above. The login form has no head.
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
    /// Below the navigation bar and the page head, above the keyboard.
    @MainActor private func visibleBand() -> (CGFloat, CGFloat) {
        let frame = app.frame, navigation = app.navigationBars.firstMatch, keyboard = app.keyboards.firstMatch
        var top = navigation.exists ? navigation.frame.maxY : frame.minY + 100
        var bottom = frame.maxY - 40
        let segments = element("user-edit.segment.basic")
        if segments.exists { top = max(top, segments.frame.maxY + 36) }
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        return (top, max(bottom, top + 80))
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: - S3-14 平台限额是立即生效写

    @MainActor func testImmediateQuotaWriteListedOnLeave() {
        launchAndLogin()
        defer { diagnostics("user-edit-quota-leave-final") }
        openEditor(1, name: "Alice")
        type("季度客户", into: "user-edit.notes")
        app.buttons["user-edit.segment.keys"].tap()
        let row = app.buttons["keys.quota.row.anthropic"]
        tap(row)
        XCTAssertTrue(app.navigationBars["Anthropic 限额"].waitForExistence(timeout: 5), app.debugDescription)
        let daily = element("keys.quota.input.daily")
        XCTAssertTrue(daily.waitForExistence(timeout: 5), app.debugDescription)
        // The right-aligned “10” is selected with a double tap and typed over (a tap snaps the caret to the word's start).
        daily.tap()
        daily.doubleTap()
        daily.typeText(XCUIKeyboardKey.delete.rawValue + "20")
        XCTAssertTrue(waitUntil(daily, "value == '20'"), String(describing: daily.value))
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已更新 Anthropic 的平台限额")
        app.buttons["user-edit.back"].tap()
        let alert = app.alerts["放弃未保存的更改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已经立即生效、不会撤回：平台限额（Anthropic）。")).firstMatch
        XCTAssertTrue(message.exists, app.debugDescription)
        alert.buttons["继续编辑"].tap()
    }
}
