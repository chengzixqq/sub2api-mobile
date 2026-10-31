import XCTest

/// 20 §3 内联编辑 (S2-10): the 基础 and 调度 sheets on the fixture site's demo accounts, saved through AccountDemoStore's PATCH,
/// PUT and mixed-channel fixtures (DemoData+Accounts).
final class AccountEditUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "账号编辑站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let conflict = "-ui-account-patch-conflict"
        static let mixed = "-ui-account-mixed-channel"
        static let timeout = "-ui-account-patch-timeout"
        static let expired = "-ui-account-expired"
        static let without = "-ui-without-capabilities"
        static let otherNotes = "另一位管理员改了备注"
        static let mixedWarning = "分组“高级组”中同时包含 Anthropic 和 Antigravity 账号"
    }

    /// OpenAI-主力-01: 保存 is greyed until something changes; the receipt's 撤销 writes the old name back.
    @MainActor func testRenameSavesShowsReceiptAndUndoRestores() {
        openSheet(4, section: "basic")
        defer { diagnostics("account-edit-rename-final") }
        let save = app.buttons["account.edit.save"]
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        addText("改名-", to: "account.edit.name")
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        diagnostics("account-edit-rename")
        save.tap()
        waitForReceipt("已保存：名称")
        app.buttons["receipt.action"].tap()
        let name = element("account.basic.name")
        reveal(name)
        waitForValue(name, equals: "OpenAI-主力-01")
        XCTAssertFalse(save.exists, app.debugDescription)
    }

    @MainActor func testCancelWithChangesAsksBeforeDiscarding() {
        openSheet(4, section: "basic")
        defer { diagnostics("account-edit-discard-final") }
        let cancel = app.buttons["account.edit.cancel"]
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), app.debugDescription)
        openSection("basic")
        addText("临时名", to: "account.edit.name")
        cancel.tap()
        let alert = app.alerts["放弃未保存的改动？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["1 项改动不会保存：名称"].exists, app.debugDescription)
        diagnostics("account-edit-discard")
        alert.buttons["继续编辑"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5) && app.buttons["account.edit.save"].exists, app.debugDescription)
        cancel.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["放弃改动"].tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), app.debugDescription)
        let name = element("account.basic.name")
        reveal(name)
        XCTAssertEqual(name.value as? String, "OpenAI-主力-01")
    }

    @MainActor func testInvalidFieldsDisableSaveWithMessages() {
        openSheet(4, section: "basic")
        defer { diagnostics("account-edit-invalid-final") }
        let save = app.buttons["account.edit.save"]
        clearText(in: "account.edit.name")
        XCTAssertTrue(element("account.edit.error.name").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.edit.error.name").label, "请输入账号名称")
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        app.buttons["account.edit.cancel"].tap()
        app.alerts.firstMatch.buttons["放弃改动"].tap()
        openSection("sched")
        addText("1.", to: "account.edit.rate")
        XCTAssertTrue(element("account.edit.error.rateMultiplier").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.edit.error.rateMultiplier").label, "账号计费倍率需要是不小于 0 的数字")
        addText("10001", to: "account.edit.loadFactor")
        XCTAssertTrue(element("account.edit.error.loadFactor").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.edit.error.loadFactor").label, "负载因子为 1–10000 的整数；留空或 0 恢复默认")
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        diagnostics("account-edit-invalid")
    }

    // MARK: - 412

    /// Someone else changed the notes before the save: only the name was edited, so it goes again by itself.
    @MainActor func testVersionConflictOnUntouchedFieldSavesSilently() {
        openSheet(4, section: "basic", arguments: [Fixture.conflict])
        defer { diagnostics("account-edit-conflict-silent-final") }
        addText("主力-静默重发", to: "account.edit.name")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：名称")
        XCTAssertFalse(app.alerts["账号已被其他人修改"].exists, app.debugDescription)
        let notes = element("account.basic.notes")
        reveal(notes)
        waitForValue(notes, equals: Fixture.otherNotes)
    }

    @MainActor func testVersionConflictOnSameFieldOffersOverwrite() {
        openSheet(4, section: "basic", arguments: [Fixture.conflict])
        defer { diagnostics("account-edit-conflict-overwrite-final") }
        addText("我的备注", to: "account.edit.notes")
        app.buttons["account.edit.save"].tap()
        let alert = app.alerts["账号已被其他人修改"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alert.buttons["用我的修改覆盖"].exists && alert.buttons["重新载入"].exists, app.debugDescription)
        diagnostics("account-edit-conflict")
        alert.buttons["用我的修改覆盖"].tap()
        waitForReceipt("已保存：备注")
        let notes = element("account.basic.notes")
        reveal(notes)
        waitForValue(notes, equals: "我的备注")
    }

    @MainActor func testVersionConflictReloadDiscardsDraft() {
        openSheet(4, section: "basic", arguments: [Fixture.conflict])
        defer { diagnostics("account-edit-conflict-reload-final") }
        addText("我的备注", to: "account.edit.notes")
        let save = app.buttons["account.edit.save"]
        save.tap()
        let alert = app.alerts["账号已被其他人修改"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["重新载入"].tap()
        waitForValue(element("account.edit.notes"), equals: Fixture.otherNotes)
        XCTAssertTrue(save.exists && !save.isEnabled, app.debugDescription)
    }

    // MARK: - 409

    /// Claude-官方-01 leaves Claude Code 组 and stays in 高级组, which the fixture puts at mixed-channel risk.
    @MainActor func testMixedChannelWarningContinueSaves() {
        openSheet(1, section: "sched", arguments: [Fixture.mixed])
        defer { diagnostics("account-edit-mixed-final") }
        leaveGroup(5)
        let save = app.buttons["account.edit.save"]
        save.tap()
        let alert = app.alerts["混合渠道警告"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", Fixture.mixedWarning)).firstMatch.exists,
                      app.debugDescription)
        diagnostics("account-edit-mixed")
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5) && save.isEnabled, app.debugDescription)
        save.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["继续保存"].tap()
        waitForReceipt("已保存：分组")
        let groups = element("account.sched.groups")
        reveal(groups)
        waitForValue(groups, equals: "高级组")
    }

    /// Without accounts.mixed_channel_details the same question comes from the pre-check, before anything is written.
    @MainActor func testMixedChannelPrecheckWithoutDetailsCapability() {
        openSheet(1, section: "sched", arguments: [Fixture.mixed, Fixture.without, "accounts.mixed_channel_details"])
        defer { diagnostics("account-edit-precheck-final") }
        leaveGroup(5)
        app.buttons["account.edit.save"].tap()
        let alert = app.alerts["混合渠道警告"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["继续保存"].tap()
        waitForReceipt("已保存：分组")
    }

    // MARK: - Pickers

    /// Gemini-测试-B sits in the stopped 测试组: listed, selected, and taken out.
    @MainActor func testGroupPickerListsInactiveCurrentGroupAndRemovesIt() {
        openSheet(5, section: "sched")
        defer { diagnostics("account-edit-groups-final") }
        app.buttons["account.edit.groups"].tap()
        let row = app.buttons["account.groups.6"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row.isSelected, app.debugDescription)
        XCTAssertEqual(row.value as? String, "分组已停用，不接收请求 · 可以移出")
        XCTAssertTrue(element("account.groups.header").label.hasPrefix("只列出 Gemini 分组和组合分组"), app.debugDescription)
        diagnostics("account-edit-groups")
        row.tap()
        XCTAssertFalse(row.isSelected, app.debugDescription)
        app.navigationBars["分组"].buttons.element(boundBy: 0).tap()
        let groups = app.buttons["account.edit.groups"]
        XCTAssertTrue(groups.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(groups.value as? String, "未分组")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：分组")
        let shown = element("account.sched.groups")
        reveal(shown)
        waitForValue(shown, equals: "未分组")
    }

    /// U53: the presets count in the phone's zone, which the footnote names when it differs from the site's (Asia/Shanghai).
    @MainActor func testExpiryPresetsShowDatesAndDeviceTimeZoneNote() {
        openSheet(4, section: "sched", environment: ["TZ": "America/New_York"])
        defer { diagnostics("account-edit-expiry-final") }
        XCTAssertFalse(app.switches["account.edit.autoPause"].exists, app.debugDescription)
        app.buttons["account.edit.expiry"].tap()
        for id in ["never", "month", "year", "custom"] {
            XCTAssertTrue(app.buttons["account.expiry.\(id)"].waitForExistence(timeout: 5), id)
        }
        XCTAssertTrue(app.buttons["account.expiry.month"].label.hasPrefix("1 个月后"), app.buttons["account.expiry.month"].label)
        XCTAssertNotNil(app.buttons["account.expiry.year"].label.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}"#, options: .regularExpression))
        XCTAssertEqual(element("account.expiry.timezone").label, "按本机时区 America/New_York")
        diagnostics("account-edit-expiry")
        app.buttons["account.expiry.month"].tap()
        XCTAssertTrue(app.switches["account.edit.autoPause"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：过期时间")
        let expiry = element("account.sched.expiry")
        reveal(expiry)
        XCTAssertNotNil((expiry.value as? String)?.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression),
                        String(describing: expiry.value))
    }

    /// S2D1-20: DeepSeek-01 is paused by its expiry; 修改过期时间… opens the 调度 sheet.
    @MainActor func testExpiredAccountEditsExpiryFromActionButton() {
        openDetail(8, arguments: [Fixture.expired])
        defer { diagnostics("account-edit-expired-final") }
        let action = app.buttons["account.action.editExpiry"]
        XCTAssertTrue(action.waitForExistence(timeout: 10), app.debugDescription)
        waitForEnabled(action)
        action.tap()
        XCTAssertTrue(app.buttons["account.edit.expiry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["编辑调度"].exists, app.debugDescription)
        XCTAssertTrue(app.switches["account.edit.autoPause"].exists, app.debugDescription)
        app.buttons["account.edit.expiry"].tap()
        app.buttons["account.expiry.year"].tap()
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：过期时间")
    }

    // MARK: - Unknown results and old servers

    /// The first PATCH is lost: the read-back shows nothing changed, and 重试 sends it again. Until then the fields wait, so
    /// nothing typed after the failure is closed away with the retried save.
    @MainActor func testUnknownResultNotAppliedOffersRetry() {
        openSheet(4, section: "basic", arguments: [Fixture.timeout])
        defer { diagnostics("account-edit-timeout-final") }
        addText("主力-重试", to: "account.edit.name")
        app.buttons["account.edit.save"].tap()
        let message = element("account.edit.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(message.label, "没有保存成功")
        XCTAssertFalse(element("account.edit.name").isEnabled, app.debugDescription)
        XCTAssertFalse(element("account.edit.notes").isEnabled, app.debugDescription)
        XCTAssertTrue(app.buttons["account.edit.retry"].isEnabled && app.buttons["account.edit.cancel"].isEnabled, app.debugDescription)
        diagnostics("account-edit-timeout")
        app.buttons["account.edit.retry"].tap()
        waitForReceipt("已保存：名称")
    }

    /// Without accounts.patch the save and its undo are PUTs.
    @MainActor func testSiteWithoutPatchSavesThroughFullUpdate() {
        openSheet(4, section: "basic", arguments: [Fixture.without, "accounts.patch"])
        defer { diagnostics("account-edit-put-final") }
        addText("主力-PUT", to: "account.edit.name")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：名称")
        app.buttons["receipt.action"].tap()
        let name = element("account.basic.name")
        reveal(name)
        waitForValue(name, equals: "OpenAI-主力-01")
    }

    // MARK: - Helpers

    @MainActor private func openSheet(_ id: Int, section: String, arguments: [String] = [], environment: [String: String] = [:]) {
        openDetail(id, arguments: arguments, environment: environment)
        openSection(section)
    }
    /// 编辑 enables once the page has read the account.
    @MainActor private func openSection(_ section: String) {
        let edit = app.buttons["account.section.\(section).edit"]
        reveal(edit)
        waitForEnabled(edit)
        edit.tap()
        XCTAssertTrue(app.buttons["account.edit.save"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openDetail(_ id: Int, arguments: [String] = [], environment: [String: String] = [:]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-edit.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["accounts.chip.all"].waitForExistence(timeout: 10), app.debugDescription)
        // Rows further down are only made once the list scrolls to them.
        let row = app.buttons["account.\(id)"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// 分组 → the group's row, then back to the form.
    @MainActor private func leaveGroup(_ id: Int) {
        app.buttons["account.edit.groups"].tap()
        let row = app.buttons["account.groups.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        app.navigationBars["分组"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["account.edit.save"].waitForExistence(timeout: 5), app.debugDescription)
    }
    /// Types where the caret lands (the start of a trailing-aligned field's text): these tests only need the value to change.
    @MainActor private func addText(_ text: String, to identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        field.tap()
        field.typeText(text)
        let shown = (field.value as? String) ?? ""
        XCTAssertTrue(shown.contains(text), "\(identifier): \(shown)\n\(app.debugDescription)", file: file, line: line)
    }
    /// A single tap snaps the caret to a word boundary, so each pass double-taps the word at the trailing edge and deletes the
    /// selection. An empty field reports its placeholder as its value.
    @MainActor private func clearText(in identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        field.tap()
        for _ in 0..<12 {
            let current = (field.value as? String) ?? ""
            if current.isEmpty || current == field.placeholderValue { return }
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).doubleTap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        XCTFail("\(identifier): \(String(describing: field.value))\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForEnabled(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitForValue(_ item: XCUIElement, equals expected: String, timeout: TimeInterval = 10,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: timeout), .completed, "\(String(describing: item.value))\n\(app.debugDescription)",
                       file: file, line: line)
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

    // MARK: - 模型 · 高级 (S2-12)

    /// Claude-官方-03's four rows; the badge follows the actual model, so the mapped claude-opus-4-1 is limited too.
    @MainActor func testModelsSectionShowsMappingRowsAndLimitBadges() {
        openDetail(3)
        defer { diagnostics("account-models-rows-final") }
        let summary = element("account.section.models.meta")
        reveal(summary)
        XCTAssertEqual(summary.label, "只调度这 4 个")
        let mapped = element("account.models.row.claude-opus-4-1")
        reveal(mapped)
        XCTAssertTrue(mapped.label.contains("映射到 claude-opus-4") && mapped.label.contains("限流 "), mapped.label)
        let same = element("account.models.row.claude-opus-4")
        XCTAssertTrue(same.label.contains("原样转发") && same.label.contains("限流 "), same.label)
        XCTAssertTrue(element("account.models.row.claude-3-5-sonnet-*").label.contains("映射到 claude-sonnet-4-5"), app.debugDescription)
        XCTAssertFalse(element("account.models.empty").exists, app.debugDescription)
        diagnostics("account-models-rows")
    }

    /// OpenAI-主力-01: − takes gpt-4o out, 添加模型 ticks gpt-4.1 (no display name, so its id), 添加映射 adds gpt-4-*; 撤销 restores.
    @MainActor func testModelMappingAddRemoveSaveReceiptAndUndo() {
        openSheet(4, section: "models")
        defer { diagnostics("account-models-edit-final") }
        app.buttons["accountSheet.models.remove.gpt-4o"].tap()
        XCTAssertTrue(element("accountSheet.models.row.gpt-4o").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["accountSheet.models.addModels"].tap()
        let option = app.buttons["accountModels.option.gpt-4.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(option.label, "gpt-4.1")
        XCTAssertTrue(app.buttons["accountModels.option.gpt-5"].isSelected && !option.isSelected, app.debugDescription)
        option.tap()
        XCTAssertTrue(waitUntil(option, "isSelected == true"), app.debugDescription)
        goBack("添加模型")
        app.buttons["accountSheet.models.addMapping"].tap()
        addText("gpt-4-*", to: "accountMapping.from")
        addText("gpt-4.1", to: "accountMapping.to")
        XCTAssertEqual(element("accountMapping.preview").label, "gpt-4-* → gpt-4.1")
        diagnostics("account-models-mapping")
        app.buttons["accountMapping.add"].tap()
        XCTAssertTrue(element("accountSheet.models.row.gpt-4-*").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("accountSheet.models.summary").label, "只调度这 4 个")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：模型")
        // The page shows the save with its receipt; 撤销 goes before any scrolling, inside the receipt's 4.2 seconds (S2-16's
        // 凭据 section made the page longer).
        let summary = element("account.section.models.meta")
        XCTAssertEqual(summary.label, "只调度这 4 个")
        XCTAssertTrue(element("account.models.row.gpt-4-*").exists && !element("account.models.row.gpt-4o").exists, app.debugDescription)
        app.buttons["receipt.action"].tap()
        reveal(summary)
        XCTAssertTrue(waitUntil(summary, "label == '只调度这 3 个'"), summary.label)
        XCTAssertTrue(element("account.models.row.gpt-4o").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testModelMappingValidationAndClearingSavesSupportAll() {
        openSheet(4, section: "models")
        defer { diagnostics("account-models-validation-final") }
        app.buttons["accountSheet.models.addMapping"].tap()
        addText("gpt-*-mini", to: "accountMapping.from")
        let error = element("accountMapping.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(error.label, "通配符 * 只能放在末尾")
        XCTAssertFalse(app.buttons["accountMapping.add"].isEnabled, app.debugDescription)
        goBack("添加映射")
        app.buttons["accountSheet.models.addMapping"].tap()
        addText("gpt-4o-*", to: "accountMapping.from")
        addText("gpt-4*", to: "accountMapping.to")
        XCTAssertTrue(waitUntil(element("accountMapping.error"), "label == '实际模型不能用通配符'"), app.debugDescription)
        XCTAssertFalse(app.buttons["accountMapping.add"].isEnabled, app.debugDescription)
        diagnostics("account-models-validation")
        goBack("添加映射")
        for model in ["gpt-4o", "gpt-5", "gpt-5-mini"] { app.buttons["accountSheet.models.remove.\(model)"].tap() }
        XCTAssertTrue(element("accountSheet.models.empty").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：模型")
        let empty = element("account.models.empty")
        reveal(empty)
        XCTAssertEqual(empty.label, "支持所有模型")
        XCTAssertEqual(element("account.section.models.meta").label, "未限制")
    }

    /// OpenAI-备用-A: the passthrough note over its row, and the OpenAI key's advanced rows.
    @MainActor func testOpenAIPassthroughNoteAndAdvancedRows() {
        openDetail(7)
        defer { diagnostics("account-adv-openai-final") }
        let note = element("account.models.passthroughNote")
        reveal(note)
        XCTAssertEqual(note.label, "已开启自动透传，模型限制不生效")
        let passthrough = element("account.adv.openai_passthrough")
        reveal(passthrough)
        XCTAssertEqual(passthrough.value as? String, "开")
        XCTAssertEqual(element("account.adv.openai_responses_mode").value as? String, "自动")
        XCTAssertEqual(element("account.adv.pool_mode").value as? String, "关")
        XCTAssertTrue(element("account.adv.upstream_billing_probe_enabled").exists, app.debugDescription)
        XCTAssertFalse(element("account.adv.intercept_warmup_requests").exists, app.debugDescription)
    }

    /// Claude-官方-01: the six token rows (no 客户端亲和调度), a switch saved and undone, 在 Web 中编辑's receipt.
    @MainActor func testAdvancedSwitchSaveUndoAndWebRow() {
        openDetail(1)
        defer { diagnostics("account-adv-switch-final") }
        let empty = element("account.models.empty")
        reveal(empty)
        XCTAssertEqual(element("account.section.models.meta").label, "未限制")
        let masking = element("account.adv.session_id_masking_enabled")
        reveal(masking)
        let values = ["intercept_warmup_requests": "开", "window_cost_limit": "$50.00", "max_sessions": "3", "base_rpm": "60",
                      "enable_tls_fingerprint": "开", "session_id_masking_enabled": "关"]
        for (key, value) in values { XCTAssertEqual(element("account.adv.\(key)").value as? String, value, key) }
        XCTAssertFalse(app.staticTexts["客户端亲和调度"].exists, app.debugDescription)
        openSection("adv")
        let toggle = app.switches["accountSheet.adv.session_id_masking_enabled"]
        revealInSheet(toggle)
        tapSwitch(toggle)
        XCTAssertTrue(waitUntil(toggle, "value == '1'"), app.debugDescription)
        diagnostics("account-adv-switch")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：会话 ID 伪装")
        // 撤销 inside the receipt's 4.2 seconds, before scrolling (the page is longer since S2-16's 凭据 section).
        XCTAssertEqual(masking.value as? String, "开")
        app.buttons["receipt.action"].tap()
        reveal(masking)
        waitForValue(masking, equals: "关")
        let web = app.buttons["account.adv.web"]
        reveal(web)
        web.tap()
        waitForReceipt("已在浏览器打开「Claude-官方-01」的编辑页")
    }

    @MainActor func testAdvancedRPMValidationDiscardAndSave() {
        openSheet(1, section: "adv")
        defer { diagnostics("account-adv-rpm-final") }
        let save = app.buttons["account.edit.save"]
        replaceText(in: "accountSheet.adv.base_rpm.value", with: "20000")
        let error = element("accountSheet.adv.base_rpm.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(error.label, "基础 RPM 为 1–10000 的整数")
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        app.buttons["account.edit.cancel"].tap()
        let alert = app.alerts["放弃未保存的改动？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["1 项改动不会保存：RPM 限制"].exists, app.debugDescription)
        alert.buttons["继续编辑"].tap()
        replaceText(in: "accountSheet.adv.base_rpm.value", with: "120")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5) && save.isEnabled, app.debugDescription)
        diagnostics("account-adv-rpm")
        save.tap()
        waitForReceipt("已保存：RPM 限制")
        let row = element("account.adv.base_rpm")
        reveal(row)
        waitForValue(row, equals: "120")
    }

    /// Kimi-01 on the official Anthropic endpoint switches to Chat Completions; MiniMax-01's custom endpoint keeps both rows.
    @MainActor func testMultiProtocolSwitchAndCustomEndpointLock() {
        openDetail(9)
        defer { diagnostics("account-adv-protocol-final") }
        let protocolRow = element("account.adv.api_protocol")
        reveal(protocolRow)
        XCTAssertEqual(element("account.adv.account_mode").value as? String, "按量付费")
        XCTAssertEqual(protocolRow.value as? String, "Anthropic")
        openSection("adv")
        app.buttons["accountSheet.adv.api_protocol"].tap()
        let options = ["adaptive", "chat_completions", "anthropic", "responses"].map { app.buttons["accountSheet.adv.option.\($0)"] }
        XCTAssertTrue(options[0].waitForExistence(timeout: 5) && options.allSatisfy { $0.exists }, app.debugDescription)
        XCTAssertTrue(options[2].isSelected, app.debugDescription)
        diagnostics("account-adv-protocol-options")
        options[1].tap()
        let save = app.buttons["account.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isEnabled, app.debugDescription)
        save.tap()
        waitForReceipt("已保存：API 协议")
        reveal(protocolRow)
        waitForValue(protocolRow, equals: "Chat Completions")
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        let minimax = app.buttons["account.12"]
        reveal(minimax)
        minimax.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        openSection("adv")
        XCTAssertTrue(element("accountSheet.adv.endpointsLocked").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["accountSheet.adv.api_protocol"].exists, app.debugDescription)
        XCTAssertFalse(app.segmentedControls["accountSheet.adv.account_mode"].exists, app.debugDescription)
    }

    /// S2D1-09: a server before credential redaction takes no credential PUT; the sheet offers the Web instead.
    @MainActor func testLegacyServerModelSaveOffersWeb() {
        openSheet(4, section: "models", arguments: ["-ui-account-legacy-server", Fixture.without, "accounts.patch"])
        defer { diagnostics("account-models-legacy-final") }
        app.buttons["accountSheet.models.addModels"].tap()
        let option = app.buttons["accountModels.option.gpt-4.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), app.debugDescription)
        option.tap()
        goBack("添加模型")
        app.buttons["account.edit.save"].tap()
        let message = element("account.edit.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(message.label, "这个站点版本过旧，凭据相关设置请在 Web 中修改")
        diagnostics("account-models-legacy")
        app.buttons["account.edit.openWeb"].tap()
        waitForReceipt("已在浏览器打开「OpenAI-主力-01」的编辑页")
    }

    /// C-1: a read-only token greys both “编辑”; 在 Web 中编辑 writes nothing and stays.
    @MainActor func testReadOnlyTokenGreysModelsAndAdvancedEdit() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-readonly-token", Fixture.longWindows]; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-edit.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-readonly", in: "login.key")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        defer { diagnostics("account-adv-readonly-final") }
        let row = app.buttons["account.1"]
        reveal(row)
        row.tap()
        let web = app.buttons["account.adv.web"]
        reveal(web)
        XCTAssertFalse(app.buttons["account.section.models.edit"].isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["account.section.adv.edit"].isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists && web.isEnabled, app.debugDescription)
        web.tap()
        waitForReceipt("已在浏览器打开「Claude-官方-01」的编辑页")
    }

    // MARK: - Helpers (S2-12)

    /// The navigation bar's back button of a page pushed inside the sheet.
    @MainActor private func goBack(_ title: String) {
        app.navigationBars[title].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["account.edit.save"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String, timeout: TimeInterval = 10) -> Bool {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }
    /// The switch itself, at the row's trailing edge (a tap on the label may not flip it).
    @MainActor private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
    }
    /// The sheet's form scrolls on its own; the tab bar is not in the way there.
    @MainActor private func revealInSheet(_ item: XCUIElement) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<4 where !item.isHittable { app.swipeUp() }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    @MainActor private func replaceText(in identifier: String, with text: String) {
        clearText(in: identifier)
        let field = element(identifier)
        field.typeText(text)
        XCTAssertTrue(waitUntil(field, "value == '\(text)'"), String(describing: field.value))
    }

    // MARK: - 列表完整刷新（S2-23）

    /// 20 §1.6: a save in the detail makes the account tab read its whole list again, so the row has the new name on the way back.
    @MainActor func testRenameInDetailShowsNewNameInListAfterBack() {
        openSheet(4, section: "basic")
        defer { diagnostics("account-edit-rename-list-final") }
        addText("改名-", to: "account.edit.name")
        app.buttons["account.edit.save"].tap()
        waitForReceipt("已保存：名称")
        XCTAssertTrue(app.buttons["account.edit.save"].waitForNonExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["account.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(row, "label CONTAINS '改名-'", timeout: 5), "\(row.label)\n\(app.debugDescription)")
    }
}
