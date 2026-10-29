import XCTest

/// S3-10 新建用户 (30 §5): the pushed page, its two segments, the check, groups, the confirmations and every answer of
/// the create fixture (UserCreateFixtureArgument). Groups are DemoData.accountGroups: exclusive standard 5 and 11, the
/// subscription group 4 and the disabled 6 are not grantable.
final class UserCreateUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testEntryShowsTwoSegmentsAndIdentityFollowsTyping() {
        launchAndLogin()
        defer { diagnostics("user-create-entry-final") }
        openCreate()
        XCTAssertTrue(app.navigationBars["新建用户"].exists, app.debugDescription)
        XCTAssertTrue(text(containing: "新建用户验收").exists, app.debugDescription)
        let usersTab = app.tabBars.buttons["用户"]
        XCTAssertFalse(usersTab.exists && usersTab.isHittable, "新建页隐藏 Tab 栏")
        XCTAssertTrue(element("user-edit.segment.basic").exists && element("user-edit.segment.access").exists)
        XCTAssertFalse(element("user-edit.segment.keys").exists)
        XCTAssertEqual(element("user-edit.hint").label, "两段填完后点底部“创建用户”")
        let identity = element("user-edit.identity")
        waitForLabel(identity, contains: "新用户")
        waitForLabel(identity, contains: "用户 · 创建后启用")
        type("qi.he@example.invalid", into: "user-edit.email")
        waitForLabel(identity, contains: "qi.he")
        type("何琪", into: "user-edit.username")
        waitForLabel(identity, contains: "何琪")
        app.buttons["user-edit.next"].tap()
        XCTAssertTrue(app.buttons["user-edit.create"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user-edit.previous"].exists)
        chooseRole("供应商")
        waitForLabel(identity, contains: "供应商 · 创建后启用")
        XCTAssertTrue(app.staticTexts["供应商只能访问账号、代理、分组和用量，看不到用户与资金。"].exists, app.debugDescription)
        app.buttons["user-edit.previous"].tap()
        XCTAssertTrue(app.buttons["user-edit.next"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testValidationJumpsToFirstErrorAndMarksSegments() {
        launchAndLogin(arguments: ["-ui-user-attr-required"])
        defer { diagnostics("user-create-validation-final") }
        openCreate()
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        waitForReceipt("还有 3 项需要填写或修改")
        // The page went back to 基础 and to the email row.
        let email = element("user-edit.email.error")
        XCTAssertTrue(email.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(email.label, "请输入邮箱")
        XCTAssertEqual(element("user-edit.segment.basic").label, "基础，有 3 项要修改")
        XCTAssertEqual(element("user-edit.attr.11.error").label, "请填写 公司")
        XCTAssertEqual(element("user-edit.attr.13").label.contains("在 Web 端修改"), true, app.debugDescription)
        type("not-an-email", into: "user-edit.email")
        waitForLabel(email, contains: "邮箱格式不对")
        type("12345", into: "user-edit.password")
        waitForLabel(element("user-edit.password.error"), contains: "至少 6 位")
        type("1.2.3", into: "user-edit.balance")
        waitForLabel(element("user-edit.balance.error"), contains: "不是合法金额")
    }

    @MainActor func testGeneratedPasswordIsShownCopiedAndHidden() {
        launchAndLogin()
        defer { diagnostics("user-create-password-final") }
        openCreate()
        XCTAssertFalse(app.buttons["user-edit.password.copy"].exists)
        tap(app.buttons["user-edit.password.generate"])
        let shown = app.textFields["user-edit.password"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5), app.debugDescription)
        let value = shown.value as? String ?? ""
        XCTAssertNotNil(value.range(of: #"^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$"#, options: .regularExpression), value)
        tap(app.buttons["user-edit.password.copy"])
        waitForReceipt("密码已复制")
        tap(app.buttons["user-edit.password.toggle"])
        XCTAssertTrue(app.secureTextFields["user-edit.password"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testLeavingAsksOnlyWithContent() {
        launchAndLogin()
        defer { diagnostics("user-create-leave-final") }
        openCreate()
        XCTAssertFalse(app.buttons["user-edit.back"].exists, "空表单用系统返回")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["users.create"].waitForExistence(timeout: 5), app.debugDescription)
        openCreate()
        type("何琪", into: "user-edit.username")
        app.buttons["user-edit.back"].tap()
        let alert = app.alerts["放弃新建用户？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["已填写的内容不会保留。"].exists)
        alert.buttons["继续编辑"].tap()
        XCTAssertTrue(element("user-edit.email").exists)
        app.buttons["user-edit.back"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["放弃"].tap()
        XCTAssertTrue(app.buttons["users.create"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testExclusiveAndPublicGroups() {
        launchAndLogin()
        defer { diagnostics("user-create-groups-final") }
        openCreate()
        app.buttons["user-edit.next"].tap()
        tap(app.buttons["user-edit.exclusive.add"])
        XCTAssertTrue(app.buttons["user-edit.add-groups.5"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user-edit.add-groups.11"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["user-edit.add-groups.4"].exists, "订阅分组不能授予")
        XCTAssertFalse(app.buttons["user-edit.add-groups.6"].exists, "停用分组不列出")
        app.buttons["user-edit.add-groups.5"].tap()
        let add = app.buttons["user-edit.add-groups.confirm"]
        waitForLabel(add, contains: "添加 1 个")
        add.tap()
        let row = app.buttons["user-edit.exclusive.5"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(row, contains: "默认 ×0.8")
        XCTAssertTrue(text(containing: "企业专线是订阅分组").exists, app.debugDescription)
        tap(row)
        let remove = app.buttons["user-edit.group-sheet.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["专属倍率在创建后设置"].exists, app.debugDescription)
        remove.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), app.debugDescription)
        // Public groups: all ticked and fixed while unrestricted; turning the switch off ticks them all again.
        let ring = app.buttons["user-edit.public.1"]
        reveal(ring)
        XCTAssertFalse(ring.isEnabled)
        XCTAssertEqual(ring.value as? String, "已勾选")
        let restrict = app.switches["user-edit.public.restrict"]
        reveal(restrict)
        tapSwitch(restrict)
        XCTAssertTrue(waitUntil(restrict, "value == '1'"), app.debugDescription)
        reveal(ring)
        ring.tap()
        XCTAssertTrue(waitUntil(ring, "value == '未勾选'"), app.debugDescription)
        reveal(restrict)
        tapSwitch(restrict)
        XCTAssertTrue(waitUntil(restrict, "value == '0'"), app.debugDescription)
        reveal(ring)
        XCTAssertEqual(ring.value as? String, "已勾选")
    }

    @MainActor func testCreateLandsOnDetailAndListShowsNewUserFirst() {
        launchAndLogin()
        defer { diagnostics("user-create-land-final") }
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        tap(app.buttons["user-edit.exclusive.add"])
        XCTAssertTrue(app.buttons["user-edit.add-groups.5"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["user-edit.add-groups.5"].tap()
        app.buttons["user-edit.add-groups.confirm"].tap()
        app.buttons["user-edit.create"].tap()
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["何琪"].exists, app.debugDescription)
        waitForReceipt("已创建用户「何琪」")
        XCTAssertFalse(app.buttons["receipt.action"].exists, "新建不给撤销")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let created = app.buttons["user.27"]
        XCTAssertTrue(created.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThan(created.frame.minY, app.buttons["user.1"].frame.minY)
    }

    @MainActor func testInitialBalanceConfirmationWithFaceIDLine() {
        launchAndLogin(arguments: ["-ui-faceid-on"])
        defer { diagnostics("user-create-balance-final") }
        openCreate()
        fillBasics()
        type("150", into: "user-edit.balance")
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        let alert = app.alerts["创建「何琪」并入账 $150.00？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "会写一条“初始余额”记录到充值与调整记录。")).firstMatch.exists)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "超过 $100，确认后验证 Face ID。")).firstMatch.exists)
        alert.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["user-edit.create"].isEnabled)
        app.buttons["user-edit.create"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["创建并入账 $150.00"].tap()
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已创建用户「何琪」，初始余额 $150.00")
    }

    @MainActor func testWithoutBalanceLedgerSaysDirectWrite() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "users.balance_ledger"])
        defer { diagnostics("user-create-no-ledger-final") }
        openCreate()
        fillBasics()
        type("20", into: "user-edit.balance")
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        let alert = app.alerts["创建「何琪」并入账 $20.00？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "创建时直接写入，不会出现在“充值与调整记录”里。")).firstMatch.exists)
        XCTAssertFalse(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Face ID")).firstMatch.exists)
        alert.buttons["取消"].tap()
    }

    @MainActor func testAdministratorNeedsStepUpThenConfirms() {
        launchAndLogin(arguments: ["-ui-step-up-required"])
        defer { diagnostics("user-create-admin-final") }
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        chooseRole("管理员")
        XCTAssertTrue(app.staticTexts["创建时需要输入二次验证码，验证后再确认一次。"].exists, app.debugDescription)
        app.buttons["user-edit.create"].tap()
        let code = element("stepup.code")
        XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
        code.tap()
        code.typeText("123456")
        let alert = app.alerts["创建管理员「何琪」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["二次验证已通过。管理员可以管理全部账号、用户和资金。"].exists, app.debugDescription)
        alert.buttons["创建管理员"].tap()
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已创建用户「何琪」")
    }

    @MainActor func testStepUpWithoutTOTPKeepsTheForm() {
        launchAndLogin(arguments: ["-ui-step-up-no-totp"])
        defer { diagnostics("user-create-no-totp-final") }
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        chooseRole("管理员")
        app.buttons["user-edit.create"].tap()
        XCTAssertTrue(app.staticTexts["需要先在 Web 端开启二次验证"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("stepup.code").exists)
        app.buttons["stepup.ack"].tap()
        XCTAssertTrue(app.buttons["user-edit.create"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user-edit.create"].isEnabled)
        XCTAssertTrue(app.segmentedControls["user-edit.role"].buttons["管理员"].isSelected, app.debugDescription)
        XCTAssertFalse(app.buttons["user.more"].exists)
    }

    @MainActor func testServerRefusalsMarkFieldsAndUnfreeze() {
        launchAndLogin()
        defer { diagnostics("user-create-email-exists-final") }
        openCreate()
        fillBasics(email: "alice@example.com")
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        waitForReceipt("创建失败：这个邮箱已被注册")
        let error = element("user-edit.email.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(error.label, "这个邮箱已被注册")
        type("qi.he@example.invalid", into: "user-edit.email")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()

        launchAndLogin(arguments: ["-ui-user-create-invalid"])
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        let notice = element("user-edit.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(notice.label.contains("服务器没有接受填写的内容（错误码 HTTP 400），请检查邮箱和密码"), notice.label)
        XCTAssertEqual(element("user-edit.email.error").label, "请检查邮箱")
        XCTAssertEqual(element("user-edit.password.error").label, "请检查密码")
        XCTAssertTrue(element("error.details.disclosure").exists, app.debugDescription)
    }

    @MainActor func testUnknownResultReadsBackByEmail() {
        launchAndLogin(arguments: ["-ui-user-create-uncertain"])
        defer { diagnostics("user-create-uncertain-final") }
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已在服务器上找到这个用户")
        app.terminate()

        launchAndLogin(arguments: ["-ui-user-create-lost"])
        openCreate()
        fillBasics()
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        let notice = element("user-edit.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(notice.label.contains("没有创建成功，可以再试一次"), notice.label)
        XCTAssertTrue(app.buttons["user-edit.create"].isEnabled)
        XCTAssertFalse(app.buttons["user.more"].exists)
    }

    @MainActor func testFrozenWhileCreatingAndAttributeFailure() {
        launchAndLogin(arguments: ["-ui-user-create-slow", "-ui-user-attr-fail"])
        defer { diagnostics("user-create-slow-final") }
        openCreate()
        type("qi.he@example.invalid", into: "user-edit.email")
        type("何琪", into: "user-edit.username")
        type("Studio-K", into: "user-edit.attr.11")
        tap(app.buttons["user-edit.attr.12"])
        XCTAssertTrue(app.buttons["user-edit.attr-option.none"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["user-edit.attr-option.渠道商"].tap()
        XCTAssertTrue(waitUntil(app.buttons["user-edit.attr.12"], "value == '渠道商'"), app.debugDescription)
        tap(app.buttons["user-edit.password.generate"])
        app.buttons["user-edit.next"].tap()
        app.buttons["user-edit.create"].tap()
        waitForLabel(app.buttons["user-edit.create"], contains: "正在创建…")
        XCTAssertFalse(element("user-edit.segment.basic").isEnabled)
        XCTAssertFalse(app.buttons["user-edit.back"].isEnabled)
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        waitForReceipt("用户已创建，自定义属性没保存成功，可在编辑用户里补填")
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://user-create.example.invalid", in: app.textFields["login.url"])
        enter("新建用户验收", in: app.textFields["login.name"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openCreate() {
        let usersTab = app.tabBars.buttons["用户"]
        if usersTab.exists && usersTab.isHittable { usersTab.tap() }
        let create = app.buttons["users.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        create.tap()
        XCTAssertTrue(element("user-edit.email").waitForExistence(timeout: 5), app.debugDescription)
    }
    /// Email, the name 何琪 and a generated password.
    @MainActor private func fillBasics(email: String = "qi.he@example.invalid") {
        type(email, into: "user-edit.email")
        type("何琪", into: "user-edit.username")
        tap(app.buttons["user-edit.password.generate"])
    }
    @MainActor private func chooseRole(_ title: String) {
        let role = app.segmentedControls["user-edit.role"]
        reveal(role)
        role.buttons[title].tap()
        XCTAssertTrue(waitUntil(role.buttons[title], "isSelected == true"), app.debugDescription)
    }
    /// Replaces the field's text.
    @MainActor private func type(_ value: String, into identifier: String) {
        let field = element(identifier)
        reveal(field)
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
    }
    @MainActor private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
    }
    @MainActor private func waitForReceipt(_ text: String) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "回执应为「\(text)」\n\(app.debugDescription)")
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
    /// its bottom bar or the keyboard: a row half under the bar still reports itself hittable. Half a band at a time, slowly
    /// and holding at the end, so no fling carries the row past it. A row not loaded yet is looked for below first, then above.
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
    /// Below the navigation bar and the page head, above the bottom bar and the keyboard.
    @MainActor private func visibleBand() -> (CGFloat, CGFloat) {
        let frame = app.frame, navigation = app.navigationBars.firstMatch, keyboard = app.keyboards.firstMatch
        var top = navigation.exists ? navigation.frame.maxY : frame.minY + 100
        var bottom = frame.maxY - 40
        let segments = element("user-edit.segment.basic")
        if segments.exists { top = max(top, segments.frame.maxY + 36) }
        for id in ["user-edit.next", "user-edit.create"] where app.buttons[id].exists { bottom = min(bottom, app.buttons[id].frame.minY - 12) }
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        return (top, max(bottom, top + 80))
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
