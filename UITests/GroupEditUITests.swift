import XCTest

/// 50 §3 (S5-10): the new / edit group sheet on the `-ui-testing` site's group fixtures — defaults, checks, the confirmations,
/// what is saved and the lost-result path (`-ui-group-write-timeout` loses each group's first write and the session's first
/// creation). The fixture server refuses a PUT that carries an unchanged field. Receipts are up for 4.2 seconds.
final class GroupEditUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let writeTimeout = "-ui-group-write-timeout"
    }

    @MainActor func testNewGroupStartsActivePublicAnthropicAtOne() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-defaults-final") }
        openCreate()
        XCTAssertTrue(isBlank(element("group-edit.name")), app.debugDescription)
        let platform = element("group-edit.platform")
        XCTAssertTrue("\(platform.label) \(platform.value as? String ?? "")".contains("Anthropic"), platform.debugDescription)
        XCTAssertTrue(element("group-edit.status.value").label.contains("正常"), app.debugDescription)
        XCTAssertEqual(app.switches["group-edit.exclusive"].value as? String, "0")
        let footnote = element("group-edit.basic.footnote")
        XCTAssertTrue(footnote.label.contains("公开：所有用户新建 API 密钥时都能选它。"), footnote.label)
        XCTAssertTrue(footnote.label.contains("组合路由（Composite）分组在 Web 中创建。"), footnote.label)
        let rate = element("group-edit.rate")
        reveal(rate)
        XCTAssertEqual(rate.value as? String, "1.0")
        XCTAssertTrue(app.segmentedControls["group-edit.billing"].buttons["标准（余额）"].isSelected, app.debugDescription)
        let rpm = element("group-edit.rpm")
        reveal(rpm)
        XCTAssertTrue(isBlank(rpm), app.debugDescription)
        let standard = element("group-edit.limits.standard")
        reveal(standard)
        XCTAssertEqual(standard.label, "标准（余额）计费从用户余额扣除，没有订阅限额。")
        let web = element("group-edit.web")
        reveal(web)
        XCTAssertEqual(web.label, "模型白名单、组合路由、图片计费、客户端限制在 Web 中编辑。")
        XCTAssertFalse(app.staticTexts["目标站点"].exists, app.debugDescription)
        let submit = app.buttons["group-edit.submit"]
        XCTAssertEqual(submit.label, "创建")
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        turnSwitch("group-edit.exclusive", on: true, towardBottom: false)
        XCTAssertTrue(element("group-edit.basic.footnote").poll(NSPredicate(format: "label CONTAINS %@", "专属：只有分配了这个分组的用户能选它。"), timeout: 5),
                      app.debugDescription)
    }

    @MainActor func testPublicGroupWithoutAccountsAsksBeforeCreating() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-public-create-final") }
        openCreate()
        set("Claude 夜间组", field: "group-edit.name", towardBottom: false)
        submit()
        let alert = app.alerts["创建公开分组「Claude 夜间组」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "站点 分组编辑验收 · Anthropic · 费率倍数 ×1.0").exists, app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "创建后所有用户新建 API 密钥时都能选它，但现在没有可用账号，选它的请求会失败。").exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("group-edit.name").value as? String, "Claude 夜间组")
        submit()
        confirmAlert("仍然创建")
        waitForReceipt("已创建「Claude 夜间组」")
        XCTAssertTrue(element("group-edit.name").waitForNonExistence(timeout: 10), app.debugDescription)
        let created = row(12)
        app.scrollUntilExists(created)
        XCTAssertTrue(created.label.contains("没有账号"), created.label)
        XCTAssertGreaterThan(created.frame.minY, element("groups.section.attention").frame.minY)
    }

    @MainActor func testDuplicateNameShowsRedTextAndGreysCreate() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-duplicate-final") }
        openCreate()
        set("高级组", field: "group-edit.name", towardBottom: false)
        let taken = element("group-edit.name.taken")
        XCTAssertTrue(taken.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(taken.label, "已有同名分组。")
        let submitButton = app.buttons["group-edit.submit"]
        XCTAssertFalse(submitButton.isEnabled, app.debugDescription)
        element("group-edit.name").typeText(" 2")
        XCTAssertTrue(taken.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(submitButton.isEnabled, app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        confirmAlert("放弃修改")
        editRow(2)
        XCTAssertFalse(element("group-edit.name.taken").exists, app.debugDescription)
        set("高级组", field: "group-edit.name", towardBottom: false)
        XCTAssertTrue(element("group-edit.name.taken").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["group-edit.submit"].isEnabled, app.debugDescription)
    }

    @MainActor func testInvalidNameOrRateGreysCreate() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-invalid-final") }
        openCreate()
        let submitButton = app.buttons["group-edit.submit"]
        set("   ", field: "group-edit.name", towardBottom: false)
        XCTAssertFalse(submitButton.isEnabled, app.debugDescription)
        set("验证分组", field: "group-edit.name", towardBottom: false)
        XCTAssertTrue(submitButton.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        set("0", field: "group-edit.rate")
        XCTAssertTrue(submitButton.poll(NSPredicate(format: "isEnabled == false"), timeout: 5), app.debugDescription)
        set("0.5", field: "group-edit.rate")
        XCTAssertTrue(submitButton.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        set(String(repeating: "组", count: 34), field: "group-edit.name", towardBottom: false)
        let tooLong = element("group-edit.name.tooLong")
        XCTAssertTrue(tooLong.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(tooLong.label, "名称太长：最多 100 个字节，一个汉字算 3 个")
        XCTAssertFalse(submitButton.isEnabled, app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        confirmAlert("放弃修改")
        XCTAssertTrue(app.navigationBars["新建分组"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testRateStepUpAsksWithChangeLinesThenSaves() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-rate-final") }
        editRow(1)
        let rate = element("group-edit.rate")
        reveal(rate)
        XCTAssertEqual(rate.value as? String, "0.8")
        app.buttons["group-edit.rate.increment"].tap()
        XCTAssertTrue(rate.poll(NSPredicate(format: "value == %@", "0.9"), timeout: 5), app.debugDescription)
        submit()
        let alert = app.alerts["保存「高级组」的修改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        for line in ["站点 分组编辑验收 · 分组「高级组」", "费率倍数 ×0.8 → ×0.9", "此后的请求按新倍率计费，已产生的记录不变。"] {
            XCTAssertTrue(alertText(alert, containing: line).exists, "\(line)\n\(app.debugDescription)")
        }
        alert.buttons["保存修改"].tap()
        waitForReceipt("已保存「高级组」")
        let premium = row(1)
        app.scrollUntilExists(premium)
        XCTAssertTrue(premium.poll(NSPredicate(format: "label CONTAINS %@", "费率倍数 ×0.9 · 标准计费"), timeout: 10), premium.label)
    }

    @MainActor func testRenameOnlySavesWithoutAsking() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-rename-final") }
        editRow(2)
        set("标准组 B", field: "group-edit.name", towardBottom: false)
        submit()
        waitForReceipt("已保存「标准组 B」")
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(element("group-edit.name").waitForNonExistence(timeout: 10), app.debugDescription)
        let standard = row(2)
        app.scrollUntilExists(standard)
        XCTAssertTrue(standard.label.contains("标准组 B"), standard.label)
    }

    @MainActor func testEditShowsReadOnlyPlatformAndBillingAndDisableCountsKeys() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-disable-final") }
        editRow(1)
        XCTAssertTrue(element("group-edit.platform.value").label.contains("Anthropic"), app.debugDescription)
        XCTAssertFalse(element("group-edit.platform").exists, app.debugDescription)
        let status = app.switches["group-edit.status"]
        XCTAssertEqual(status.value as? String, "1")
        XCTAssertTrue(status.label.contains("正常"), status.label)
        let billing = element("group-edit.billing.value")
        reveal(billing)
        XCTAssertTrue(billing.label.contains("标准（余额）") && billing.label.contains("创建后不能修改"), billing.label)
        turnSwitch("group-edit.status", on: false, towardBottom: false)
        let footnote = element("group-edit.basic.footnote")
        XCTAssertTrue(footnote.poll(NSPredicate(format: "label CONTAINS %@", "停用：使用这个分组的 API 密钥会被拒绝。"), timeout: 5), footnote.label)
        submit()
        let alert = app.alerts["保存「高级组」的修改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "停用分组（36 个 API 密钥会被拒绝）").exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("group-edit.name").exists, app.debugDescription)
        XCTAssertEqual(app.switches["group-edit.status"].value as? String, "0")
    }

    @MainActor func testSubscriptionLimitsLeftBlankMeanUnlimited() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-limits-final") }
        openCreate()
        set("订阅夜间组", field: "group-edit.name", towardBottom: false)
        turnSwitch("group-edit.exclusive", on: true, towardBottom: false)
        let subscription = app.segmentedControls["group-edit.billing"].buttons["订阅（配额）"]
        reveal(subscription)
        subscription.tap()
        for period in ["daily", "weekly", "monthly"] {
            let field = element("group-edit.limit.\(period)")
            reveal(field)
            XCTAssertTrue(isBlank(field), period)
        }
        let footnote = element("group-edit.limits.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "留空 = 无限制；超过限额的订阅请求会被拒绝。")
        set("20", field: "group-edit.limit.daily")
        let currency = element("group-edit.limit.daily.currency")
        XCTAssertTrue(currency.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(currency.label, "$")
        clear("group-edit.limit.daily")
        XCTAssertTrue(currency.waitForNonExistence(timeout: 5), app.debugDescription)
        submit()
        waitForReceipt("已创建「订阅夜间组」")
        let created = row(12)
        app.scrollUntilExists(created)
        XCTAssertTrue(created.label.contains("订阅计费"), created.label)

        editRow(4)
        clear("group-edit.limit.daily")
        submit()
        let alert = app.alerts["保存「企业专线」的修改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alertText(alert, containing: "每日限额 $20 → 无限制").exists, app.debugDescription)
        alert.buttons["保存修改"].tap()
        waitForReceipt("已保存「企业专线」")
        XCTAssertTrue(element("group-edit.name").waitForNonExistence(timeout: 10), app.debugDescription)
        editRow(4)
        for (period, value) in [("daily", ""), ("weekly", "100"), ("monthly", "300")] {
            let field = element("group-edit.limit.\(period)")
            reveal(field)
            XCTAssertTrue(value.isEmpty ? isBlank(field) : field.value as? String == value, "\(period): \(field.debugDescription)")
        }
    }

    @MainActor func testCancelWithChangesAsksToDiscard() {
        launchAndOpenGroups()
        defer { diagnostics("group-edit-discard-final") }
        openCreate()
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(app.navigationBars["新建分组"].waitForNonExistence(timeout: 10), app.debugDescription)
        openCreate()
        set("临时分组", field: "group-edit.name", towardBottom: false)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(app.alerts["放弃修改？"].waitForExistence(timeout: 5), app.debugDescription)
        confirmAlert("继续编辑")
        XCTAssertEqual(element("group-edit.name").value as? String, "临时分组")
        app.buttons["group-edit.cancel"].tap()
        confirmAlert("放弃修改")
        XCTAssertTrue(app.navigationBars["新建分组"].waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(12).exists, app.debugDescription)
    }

    @MainActor func testUnconfirmedEditChecksThenRetriesTheSameNumber() {
        launchAndOpenGroups(arguments: [Fixture.writeTimeout])
        defer { diagnostics("group-edit-unconfirmed-edit-final") }
        editRow(1)
        set("高级组 A", field: "group-edit.name", towardBottom: false)
        submit()
        let state = element("group-edit.unconfirmed")
        XCTAssertTrue(state.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(state.label.contains("结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行"), state.label)
        let note = element("group-edit.check.note")
        XCTAssertTrue(note.poll(NSPredicate(format: "label == %@", "服务器上的分组还不是这次的修改。"), timeout: 10), app.debugDescription)
        let name = element("group-edit.name")
        reveal(name, towardBottom: false)
        XCTAssertFalse(name.isEnabled, app.debugDescription)
        app.buttons["group-edit.cancel"].tap()
        XCTAssertTrue(app.alerts["结果未确认"].waitForExistence(timeout: 5), app.debugDescription)
        confirmAlert("继续核对")
        let retry = app.buttons["group-edit.retry-same"]
        reveal(retry)
        retry.tap()
        waitForReceipt("已保存「高级组 A」")
        let premium = row(1)
        app.scrollUntilExists(premium)
        XCTAssertTrue(premium.poll(NSPredicate(format: "label CONTAINS %@", "高级组 A"), timeout: 10), premium.label)
    }

    @MainActor func testUnconfirmedCreateSearchesByNameThenRetries() {
        launchAndOpenGroups(arguments: [Fixture.writeTimeout])
        defer { diagnostics("group-edit-unconfirmed-create-final") }
        openCreate()
        set("核对测试组", field: "group-edit.name", towardBottom: false)
        turnSwitch("group-edit.exclusive", on: true, towardBottom: false)
        submit()
        let note = element("group-edit.check.note")
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        reveal(note)
        XCTAssertTrue(note.poll(NSPredicate(format: "label == %@", "服务器上还没有找到这个分组，可能仍在处理。"), timeout: 10), app.debugDescription)
        let retry = app.buttons["group-edit.retry-same"]
        reveal(retry)
        retry.tap()
        waitForReceipt("已创建「核对测试组」")
        let created = row(12)
        app.scrollUntilExists(created)
        XCTAssertTrue(created.label.contains("核对测试组"), created.label)
        XCTAssertFalse(row(13).exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in on the group-edit site, then 搜索 → 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launchQuietly()
        set("分组编辑验收", field: "login.name", towardBottom: false)
        set("https://group-edit.example.invalid", field: "login.url")
        set("admin@example.com", field: "login.email")
        set("fixture-password", field: "login.password")
        reveal(app.buttons["login.submit"]); app.buttons["login.submit"].tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openCreate() {
        let create = app.buttons["groups.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        create.tap()
        XCTAssertTrue(app.navigationBars["新建分组"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group-edit.name").waitForExistence(timeout: 5), app.debugDescription)
    }
    /// The list's left swipe 编辑 (S5-05).
    @MainActor private func editRow(_ id: Int) {
        let target = row(id)
        app.scrollUntilExists(target)
        target.swipeLeft()
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.swipe.edit", "编辑")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
        XCTAssertTrue(app.navigationBars["编辑分组"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("group-edit.name").waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func submit() {
        let button = app.buttons["group-edit.submit"]
        XCTAssertTrue(button.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        button.tap()
    }
    @MainActor private func confirmAlert(_ title: String) {
        let button = app.alerts.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }
    @MainActor private func alertText(_ alert: XCUIElement, containing part: String) -> XCUIElement {
        alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func turnSwitch(_ id: String, on: Bool, towardBottom: Bool = true) {
        let toggle = app.switches[id]
        reveal(toggle, towardBottom: towardBottom)
        if (toggle.value as? String == "1") != on {
            let knob = toggle.switches.firstMatch
            (knob.exists ? knob : toggle).tap()
        }
        XCTAssertTrue(toggle.poll(NSPredicate(format: "value == %@", on ? "1" : "0"), timeout: 5), app.debugDescription)
    }
    @MainActor private func row(_ id: Int) -> XCUIElement { app.buttons["group.row.\(id)"] }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    /// Empty: no value, or only its placeholder.
    @MainActor private func isBlank(_ field: XCUIElement) -> Bool {
        let value = field.value as? String ?? ""
        return value.isEmpty || value == field.placeholderValue
    }
    @MainActor private func clear(_ id: String) {
        let field = element(id); reveal(field); field.tap()
        clearText(field)
    }
    @MainActor private func set(_ value: String, field id: String, towardBottom: Bool = true) {
        let field = element(id); reveal(field, towardBottom: towardBottom); field.tap()
        clearText(field)
        field.typeText(value)
    }
    /// The sheet's inputs are right-aligned and a tap snaps the caret to a word boundary, so each pass puts it at the trailing edge
    /// and deletes what is left.
    @MainActor private func clearText(_ field: XCUIElement) {
        for _ in 0..<6 {
            let current = field.value as? String ?? ""
            if current.isEmpty || current == field.placeholderValue { return }
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        XCTAssertTrue(isBlank(field), app.debugDescription)
    }
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<12 {
            if visibleFrame(item), item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let height = max(40, bottom - top)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        guard visibleFrame(item) else {
            XCTFail("Expected a visible, nonempty element frame.\n\(app.debugDescription)"); return
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    @MainActor private func visibleFrame(_ item: XCUIElement) -> Bool {
        guard item.exists else { return false }
        let frame = item.frame
        return !frame.isEmpty && !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite && frame.intersects(app.frame)
    }
    @MainActor private func waitForReceipt(_ text: String) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)")
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
