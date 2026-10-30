import XCTest

/// S3-12 Key 与限额 · API Key 卡片 (30 §7): Studio-K 团队 (10) has the status matrix of S3D1-04 — 4031 企业网关 (企业专线, with an
/// active subscription), 4087 默认 (高级组, two rate windows), 4099 脚本 (标准组 at ×0.9, $18.40 of $20, IP rules), 4100 停用的,
/// 4117 预发 (used up), 4118 过期 and the deleted 4119 — and is granted 高级组 and 标准组 with the public groups restricted.
final class UserKeysUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testSegmentShowsNoticeHeaderAndFirstCardExpanded() {
        launchAndLogin()
        defer { diagnostics("user-keys-segment-final") }
        openKeys()
        XCTAssertEqual(element("keys.notice").label, "这一段立即生效，不用保存，也不随“放弃更改”撤回")
        waitForValue(element("keys.header"), contains: "6 个 · 活跃 3")
        waitForLabel(app.buttons["user-edit.segment.keys"], contains: "Key 与限额（6）")
        XCTAssertEqual(toggle(4031).value as? String, "已展开")
        waitForLabel(element("keys.card.4031.expiry"), contains: "永久有效")
        waitForLabel(element("keys.card.4031.usage"), contains: "今日 $1.20")
        waitForLabel(element("keys.card.4031.meta"), contains: "企业专线 · 默认 ×1.2 · 最近使用")
        XCTAssertTrue(element("keys.card.4031.rate.none").exists, app.debugDescription)
        XCTAssertFalse(element("keys.card.4119").exists, app.debugDescription)
        let footnote = element("keys.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "换分组、停用的回执里可以撤销；重置速率限制、删除不能撤销。")
    }

    @MainActor func testOnlyOneCardExpandsAtATime() {
        launchAndLogin()
        defer { diagnostics("user-keys-expand-final") }
        openKeys()
        expand(4087)
        // Closing 4031 above moved 4087's head; the page brings it back.
        XCTAssertTrue(toggle(4087).isHittable, app.debugDescription)
        XCTAssertFalse(element("keys.card.4031.expiry").exists, app.debugDescription)
        reveal(toggle(4031), towardBottom: false)
        XCTAssertEqual(toggle(4031).value as? String, "已收起")
        expand(4087)
        toggle(4087).tap()
        XCTAssertTrue(waitUntil(toggle(4087), "value == '已收起'"), app.debugDescription)
    }

    @MainActor func testCardsShowMaskOnlyAndExpandedFacts() {
        launchAndLogin()
        defer { diagnostics("user-keys-facts-final") }
        openKeys()
        expand(4087)
        XCTAssertTrue(toggle(4087).label.contains("sk-…4087"), toggle(4087).label)
        let fiveHours = element("keys.card.4087.rate.5h")
        reveal(fiveHours)
        for part in ["5 小时", "42.0%", "$2.10 / $5", "重置"] { XCTAssertTrue(fiveHours.label.contains(part), fiveHours.label) }
        XCTAssertTrue(element("keys.card.4087.rate.1d").label.contains("$9.40 / $20"), app.debugDescription)
        XCTAssertTrue(element("keys.card.4087.rate.7d").label.contains("已用 $0.00"), app.debugDescription)
        waitForLabel(element("keys.card.4087.concurrency"), contains: "1")
        waitForLabel(element("keys.card.4087.ip"), contains: "203.0.113.24")
        expand(4099)
        for part in ["$18.40 / $20.00", "92.0%"] { waitForLabel(element("keys.card.4099.usage"), contains: part) }
        waitForLabel(element("keys.card.4099.meta"), contains: "标准组 · 专属倍率 ×0.9")
        waitForLabel(element("keys.card.4099.expiry"), contains: "至 2030-12-31")
        waitForLabel(element("keys.card.4099.iprule"), contains: "白名单 198.51.100.0/24 · 黑名单 203.0.113.9")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "sk-fixture")).count, 0)
    }

    @MainActor func testStatusBadgesFollowRunMode() {
        launchAndLogin()
        defer { diagnostics("user-keys-badges-final") }
        openKeys()
        for (id, badge) in [(4100, "已停用"), (4117, "额度耗尽"), (4118, "已过期")] {
            reveal(toggle(id))
            XCTAssertTrue(toggle(id).label.contains(badge), toggle(id).label)
        }
        XCTAssertFalse(toggle(4087).label.contains("活跃"), toggle(4087).label)
        app.terminate()
        launchAndLogin(arguments: ["-ui-user-keys-simple"])
        openKeys()
        waitForValue(element("keys.header"), contains: "6 个 · 活跃 5")
        reveal(toggle(4117))
        XCTAssertTrue(toggle(4117).label.contains("额度耗尽 · 仍可调用"), toggle(4117).label)
    }

    @MainActor func testChangeGroupReceiptAndUndo() {
        launchAndLogin()
        defer { diagnostics("user-keys-group-final") }
        openKeys()
        openGroupSheet(4087)
        XCTAssertTrue(app.navigationBars["换分组 · 默认"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["keys.group.option.none"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["keys.group.option.6"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["keys.group.option.1"].isSelected, app.debugDescription)
        XCTAssertTrue(app.buttons["keys.group.option.3"].label.contains("用户被限制，调用会被拒绝"), app.buttons["keys.group.option.3"].label)
        XCTAssertTrue(app.buttons["keys.group.option.4"].label.contains("订阅分组 · 有效订阅"), app.buttons["keys.group.option.4"].label)
        XCTAssertTrue(app.buttons["keys.group.option.5"].label.contains("专属分组 · 默认倍率 ×0.8 · 会同时授予这个分组"), app.debugDescription)
        let codex = app.buttons["keys.group.option.11"]
        XCTAssertTrue(app.scrollUntilExists(codex), app.debugDescription)
        app.scrollUntilExists(app.buttons["keys.group.option.2"], towardBottom: false)
        app.buttons["keys.group.option.2"].tap()
        XCTAssertTrue(app.buttons["keys.group.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("「默认」已改到「标准组」")
        waitForLabel(element("keys.card.4087.meta"), contains: "标准组 · 专属倍率 ×0.9")
        app.buttons["receipt.action"].tap()
        waitForLabel(element("keys.card.4087.meta"), contains: "高级组 · 默认 ×0.8")
    }

    @MainActor func testUnbindReceipt() {
        launchAndLogin()
        defer { diagnostics("user-keys-unbind-final") }
        openKeys()
        openGroupSheet(4087)
        app.buttons["keys.group.option.none"].tap()
        waitForReceipt("「默认」已不绑定分组")
        waitForLabel(element("keys.card.4087.meta"), contains: "不绑定分组")
    }

    @MainActor func testNewlyGrantedGroupUpdatesBaselineAndLeaveList() {
        launchAndLogin()
        defer { diagnostics("user-keys-grant-final") }
        openKeys()
        grantClaudeCode()
        app.buttons["user-edit.segment.access"].tap()
        let row = app.buttons["user-edit.exclusive.5"]
        reveal(row)
        XCTAssertTrue(row.label.contains("绑定 1 个 Key"), row.label)
        XCTAssertFalse(row.label.contains("新添加"), row.label)
        XCTAssertFalse(app.buttons["user-edit.segment.access"].label.contains("已改"), app.debugDescription)
        app.buttons["user-edit.segment.basic"].tap()
        type("企业客户 · 已续约", into: "user-edit.notes")
        app.buttons["user-edit.back"].tap()
        let alert = app.alerts["放弃未保存的更改？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        let applied = alert.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "已经立即生效、不会撤回：Key「默认」换分组")).firstMatch
        XCTAssertTrue(applied.exists, app.debugDescription)
    }

    @MainActor func testUndoNewlyGrantedRevokesAccess() {
        launchAndLogin()
        defer { diagnostics("user-keys-grant-undo-final") }
        openKeys()
        grantClaudeCode()
        app.buttons["receipt.action"].tap()
        waitForLabel(element("keys.card.4087.meta"), contains: "高级组")
        app.buttons["user-edit.segment.access"].tap()
        XCTAssertTrue(element("user-edit.exclusive.add").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["user-edit.exclusive.5"].exists, app.debugDescription)
    }

    @MainActor func testUndoKeepsGrantWhenGroupStillInUse() {
        launchAndLogin(arguments: ["-ui-key-still-in-use"])
        defer { diagnostics("user-keys-still-in-use-final") }
        openKeys()
        grantClaudeCode()
        app.buttons["receipt.action"].tap()
        waitForReceipt("Key 已还原；该分组还有其他 Key 在用，授权保留")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        app.buttons["user-edit.segment.access"].tap()
        XCTAssertTrue(app.buttons["user-edit.exclusive.5"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testLegacyKeysShowGapsAndTwoStepUndo() {
        launchAndLogin(arguments: ["-ui-legacy-keys"])
        defer { diagnostics("user-keys-legacy-final") }
        openKeys()
        let gap = app.buttons["keys.card.4031.gap.disable"]
        reveal(gap)
        XCTAssertTrue(app.buttons["keys.card.4031.gap.delete"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["keys.card.4031.more"].exists, app.debugDescription)
        gap.tap()
        let alert = app.alerts["停用 Key 需要后端新增接口"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["keys.new.gap"].exists || app.scrollUntilExists(app.buttons["keys.new.gap"]), app.debugDescription)
        reveal(toggle(4087), towardBottom: false)
        grantClaudeCode()
        app.buttons["receipt.action"].tap()
        waitForLabel(element("keys.card.4087.meta"), contains: "高级组")
        app.buttons["user-edit.segment.access"].tap()
        XCTAssertTrue(element("user-edit.exclusive.add").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["user-edit.exclusive.5"].exists, app.debugDescription)
        app.terminate()
        launchAndLogin(arguments: ["-ui-legacy-keys", "-ui-key-revoke-fails"])
        openKeys()
        grantClaudeCode()
        app.buttons["receipt.action"].tap()
        waitForReceipt("Key 已还原，但分组授权没收回，请在权限与并发里手动移除")
    }

    @MainActor func testDisableEnableWithUndo() {
        launchAndLogin()
        defer { diagnostics("user-keys-status-final") }
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "停用 Key")
        waitForReceipt("已停用「默认」")
        XCTAssertTrue(waitUntil(toggle(4087), "label CONTAINS '已停用'"), toggle(4087).label)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(waitUntil(toggle(4087), "NOT (label CONTAINS '已停用')"), toggle(4087).label)
        expand(4100)
        chooseFromCardMenu(4100, "启用 Key")
        waitForReceipt("已启用「停用的」")
    }

    @MainActor func testEnableExpiredKeyExplainsStillBlocked() {
        launchAndLogin()
        defer { diagnostics("user-keys-expired-final") }
        openKeys()
        expand(4118)
        chooseFromCardMenu(4118, "停用 Key")
        waitForReceipt("已停用「过期」")
        chooseFromCardMenu(4118, "启用 Key")
        waitForReceipt("已启用，但 Key 已过期，仍不能调用")
    }

    @MainActor func testResetRateLimitConfirmIsNotUndoable() {
        launchAndLogin()
        defer { diagnostics("user-keys-reset-final") }
        openKeys()
        expand(4087)
        let reset = app.buttons["keys.card.4087.reset"]
        reveal(reset)
        reset.tap()
        let alert = app.alerts["重置「默认」的速率限制用量？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["5 小时、1 天、7 天三个窗口的已用额度会归零，立即生效，不能撤销。"].exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        reset.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["重置用量"].tap()
        waitForReceipt("速率限制已重置")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        waitForLabel(element("keys.card.4087.rate.5h"), contains: "$0.00 / $5")
    }

    @MainActor func testGroupErrorsAndDeletedKey() {
        launchAndLogin(arguments: ["-ui-key-group-inactive"])
        defer { diagnostics("user-keys-errors-final") }
        openKeys()
        openGroupSheet(4087)
        app.buttons["keys.group.option.2"].tap()
        waitForReceipt("这个分组已停用")
        waitForLabel(element("keys.card.4087.meta"), contains: "高级组")
        app.terminate()
        launchAndLogin(arguments: ["-ui-key-gone"])
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "停用 Key")
        waitForReceipt("这个 Key 已被删除")
        XCTAssertTrue(toggle(4087).waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenShowsTodayDashAndGraysWrites() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-keys-read-only-final") }
        openKeys()
        waitForLabel(element("keys.card.4031.usage"), contains: "今日 —")
        let group = app.buttons["keys.card.4031.group"]
        reveal(group)
        XCTAssertFalse(group.isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["keys.card.4031.more"].isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }

    @MainActor func testEmptyAndLoadFailureStates() {
        launchAndLogin()
        defer { diagnostics("user-keys-states-final") }
        openKeys(2, name: "Bob", viaMenu: true)
        waitForLabel(element("keys.empty"), contains: "可以在这里替用户新建；用户也可以在 Web 端「API 密钥」里自己创建。")
        app.terminate()
        launchAndLogin(arguments: ["-ui-legacy-keys"])
        openKeys(2, name: "Bob", viaMenu: true)
        waitForLabel(element("keys.empty"), contains: "用户在 Web 端「API 密钥」里自己创建；创建后可以在这里换分组、重置速率限制。")
        app.terminate()
        launchAndLogin(arguments: ["-ui-key-list-error"])
        openKeys(viaMenu: true)
        XCTAssertTrue(app.buttons["keys.list.retry"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        launchAndLogin(arguments: ["-ui-key-usage-error"])
        openKeys()
        waitForLabel(element("keys.card.4031.usage"), contains: "今日 —")
    }

    @MainActor func testConcurrencyDashWithoutCapability() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "api_keys.current_concurrency"])
        defer { diagnostics("user-keys-concurrency-final") }
        openKeys()
        waitForLabel(element("keys.card.4031.concurrency"), contains: "—")
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
        enter("https://user-keys.example.invalid", in: app.textFields["login.url"])
        enter("Key 验收", in: app.textFields["login.name"])
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
    /// The detail's key summary lands on the third segment; `viaMenu` goes through ⋯ 编辑用户 (a failed key read hides no entry).
    @MainActor private func openKeys(_ id: Int = 10, name: String = "Studio-K 团队", viaMenu: Bool = false) {
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
            let segment = app.buttons["user-edit.segment.keys"]
            XCTAssertTrue(segment.waitForExistence(timeout: 10), app.debugDescription)
            segment.tap()
        } else {
            let keys = app.buttons["user.keys"]
            XCTAssertTrue(app.scrollUntilExists(keys))
            keys.tap()
        }
        XCTAssertTrue(element("keys.notice").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func toggle(_ id: Int) -> XCUIElement { app.buttons["keys.card.\(id).toggle"] }
    /// A card below the fold is created only once scrolled to.
    @MainActor private func expand(_ id: Int) {
        let button = toggle(id)
        let anyCard = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "keys.card.")).firstMatch
        XCTAssertTrue(anyCard.waitForExistence(timeout: 10), app.debugDescription)
        reveal(button)
        if button.value as? String != "已展开" { button.tap() }
        XCTAssertTrue(waitUntil(button, "value == '已展开'"), app.debugDescription)
    }
    @MainActor private func openGroupSheet(_ id: Int) {
        expand(id)
        let group = app.buttons["keys.card.\(id).group"]
        reveal(group)
        group.tap()
        XCTAssertTrue(app.buttons["keys.group.cancel"].waitForExistence(timeout: 5), app.debugDescription)
    }
    /// 4087 默认 moves to Claude Code 组 (5), which the user lacks, so it is granted with the move.
    @MainActor private func grantClaudeCode() {
        openGroupSheet(4087)
        let option = app.buttons["keys.group.option.5"]
        app.scrollUntilExists(option)
        option.tap()
        waitForReceipt("已改到「Claude Code 组」，并为用户添加了这个分组")
        waitForLabel(element("keys.card.4087.meta"), contains: "Claude Code 组")
    }
    /// The system menu's items are found by their words.
    @MainActor private func chooseFromCardMenu(_ id: Int, _ title: String) {
        let more = app.buttons["keys.card.\(id).more"]
        reveal(more)
        more.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        item.tap()
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
    @MainActor private func waitForValue(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(String(describing: item.value)) ∌ \(text)\n\(app.debugDescription)",
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
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true) {
        for attempt in 0..<16 {
            let (top, bottom) = visibleBand()
            if item.exists && item.isHittable && item.frame.minY >= top && item.frame.maxY <= bottom { return }
            let up = item.exists ? item.frame.maxY < top : (towardBottom ? attempt >= 8 : attempt < 8)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.75))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            (up ? upper : lower).press(forDuration: 0.05, thenDragTo: up ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    /// Below the navigation bar and the page head, above the keyboard and a receipt.
    @MainActor private func visibleBand() -> (CGFloat, CGFloat) {
        let frame = app.frame, navigation = app.navigationBars.firstMatch, keyboard = app.keyboards.firstMatch
        var top = navigation.exists ? navigation.frame.maxY : frame.minY + 100
        var bottom = frame.maxY - 40
        let segments = element("user-edit.segment.basic"), receipt = element("receipt")
        if segments.exists { top = max(top, segments.frame.maxY + 36) }
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        if receipt.exists { bottom = min(bottom, receipt.frame.minY) }
        return (top, max(bottom, top + 80))
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: - S3-13 新建 / 编辑 / 删除 Key 与显示完整 Key（Alice 1 号：开发密钥、脚本、备用；新建的 Key 从 9001 起）

    @MainActor func testCreateKeyShowsPlaintextOnceThenMaskOnly() {
        launchAndLogin()
        defer { diagnostics("user-keys-create-final") }
        openKeys(1, name: "Alice")
        openNewKeyForm()
        XCTAssertTrue(app.navigationBars["新建 Key"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["keys.form.submit"].isEnabled, app.debugDescription)
        fill("keys.form.name", with: "新脚本")
        app.buttons["keys.form.submit"].tap()
        let key = element("keys.reveal.key")
        XCTAssertTrue(key.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Key 已创建"].exists, app.debugDescription)
        XCTAssertTrue(key.label.contains("sk-ui-created-9001"), key.label)
        XCTAssertEqual(element("keys.reveal.notice").label, "完整 Key 只在这里显示一次；之后查看需要二次验证。")
        diagnostics("user-keys-created-sheet")
        app.buttons["keys.reveal.copy"].tap()
        waitForLabel(element("keys.reveal.notice"), contains: "已复制")
        app.buttons["keys.reveal.done"].tap()
        waitForReceipt("已创建「新脚本」")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        reveal(toggle(9001))
        XCTAssertTrue(toggle(9001).label.contains("sk-…9001"), toggle(9001).label)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "sk-ui-created")).count, 0)
    }

    @MainActor func testCreateKeyWithExclusiveGroupGrantsIt() {
        launchAndLogin()
        defer { diagnostics("user-keys-create-group-final") }
        openKeys(1, name: "Alice")
        openNewKeyForm()
        fill("keys.form.name", with: "专属 Key")
        app.buttons["keys.form.group"].tap()
        let option = app.buttons["keys.group.option.5"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(option.label.contains("会同时授予这个分组"), option.label)
        option.tap()
        // LabeledContent may read its value as the label's tail or as the element's value.
        let picked = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Claude Code 组", "Claude Code 组")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: picked, object: app.buttons["keys.form.group"])], timeout: 5),
                       .completed, app.debugDescription)
        app.buttons["keys.form.submit"].tap()
        XCTAssertTrue(app.buttons["keys.reveal.done"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["keys.reveal.done"].tap()
        waitForReceipt("已创建「专属 Key」")
        app.buttons["user-edit.segment.access"].tap()
        XCTAssertTrue(app.buttons["user-edit.exclusive.5"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testCreateKeyCountExceededStaysInForm() {
        launchAndLogin(arguments: ["-ui-key-count-exceeded"])
        defer { diagnostics("user-keys-create-limit-final") }
        openKeys(1, name: "Alice")
        openNewKeyForm()
        fill("keys.form.name", with: "第四个")
        app.buttons["keys.form.submit"].tap()
        waitForLabel(formElement("keys.form.formError"), contains: "这个用户的 Key 数量已达上限，请先删除不用的 Key")
        XCTAssertTrue(element("keys.form.sheet").exists, app.debugDescription)
        XCTAssertFalse(element("keys.reveal.sheet").exists, app.debugDescription)
    }

    @MainActor func testCreateKeyUncertainFindsCreatedKey() {
        launchAndLogin(arguments: ["-ui-key-create-uncertain"])
        defer { diagnostics("user-keys-create-uncertain-final") }
        openKeys(1, name: "Alice")
        openNewKeyForm()
        fill("keys.form.name", with: "找回的 Key")
        app.buttons["keys.form.submit"].tap()
        waitForReceipt("已创建「找回的 Key」；完整 Key 只能通过“显示完整 Key”查看")
        XCTAssertFalse(element("keys.reveal.sheet").exists, app.debugDescription)
        reveal(toggle(9001))
        XCTAssertTrue(toggle(9001).label.contains("找回的 Key"), toggle(9001).label)
        app.terminate()
        // Nothing made and no answer: the same number goes out again, and only that one is taken.
        launchAndLogin(arguments: ["-ui-key-create-lost"])
        openKeys(1, name: "Alice")
        openNewKeyForm()
        fill("keys.form.name", with: "重试的 Key")
        app.buttons["keys.form.submit"].tap()
        waitForLabel(formElement("keys.form.formError"), contains: "结果未确认，请刷新后检查")
        app.buttons["keys.form.submit"].tap()
        let key = element("keys.reveal.key")
        XCTAssertTrue(key.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(key.label.contains("sk-ui-created-9001"), key.label)
    }

    @MainActor func testEditKeySavesAndUndo() {
        launchAndLogin()
        defer { diagnostics("user-keys-edit-final") }
        openKeys()
        expand(4099)
        chooseFromCardMenu(4099, "编辑 Key…")
        XCTAssertTrue(element("keys.form.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["编辑 Key"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["keys.form.submit"].isEnabled, app.debugDescription)
        XCTAssertEqual(element("keys.form.name").value as? String, "脚本")
        fill("keys.form.name", with: "脚本 B")
        fill("keys.form.ipWhitelist", with: "")
        XCTAssertTrue(waitUntil(app.buttons["keys.form.submit"], "isEnabled == true"), app.debugDescription)
        app.buttons["keys.form.submit"].tap()
        waitForReceipt("已保存「脚本 B」")
        waitForLabel(toggle(4099), contains: "脚本 B")
        waitForLabel(element("keys.card.4099.iprule"), contains: "黑名单 203.0.113.9")
        XCTAssertFalse(element("keys.card.4099.iprule").label.contains("白名单"), element("keys.card.4099.iprule").label)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(waitUntil(toggle(4099), "NOT (label CONTAINS '脚本 B')"), toggle(4099).label)
        waitForLabel(element("keys.card.4099.iprule"), contains: "白名单 198.51.100.0/24")
    }

    @MainActor func testEditKeyResetQuotaAndServerError() {
        launchAndLogin()
        defer { diagnostics("user-keys-edit-reset-final") }
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "编辑 Key…")
        XCTAssertTrue(element("keys.form.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.switches["keys.form.resetQuota"].exists, app.debugDescription)
        app.buttons["keys.form.cancel"].tap()
        XCTAssertTrue(element("keys.form.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        expand(4099)
        chooseFromCardMenu(4099, "编辑 Key…")
        let reset = formElement("keys.form.resetQuota")
        reset.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
        XCTAssertTrue(waitUntil(reset, "value == '1'"), app.debugDescription)
        app.buttons["keys.form.submit"].tap()
        waitForReceipt("已保存「脚本」，已用额度的重置不能撤销")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        waitForLabel(element("keys.card.4099.usage"), contains: "$0.00 / $20.00")
        app.terminate()
        launchAndLogin(arguments: ["-ui-key-name-required"])
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "编辑 Key…")
        fill("keys.form.name", with: "默认 2")
        app.buttons["keys.form.submit"].tap()
        waitForLabel(formElement("keys.form.error.name"), contains: "名称不能为空")
        XCTAssertTrue(element("keys.form.sheet").exists, app.debugDescription)
    }

    @MainActor func testDeleteKeyByTypingName() {
        launchAndLogin()
        defer { diagnostics("user-keys-delete-final") }
        openKeys(1, name: "Alice")
        expand(1)
        chooseFromCardMenu(1, "删除 Key…")
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除 Key「开发密钥」？")
        let message = element("delete.message").label
        XCTAssertTrue(message.contains("站点 Key 验收 · 用户 Alice"), message)
        XCTAssertTrue(message.contains("删除后这个 Key 立即不能调用，不能撤销。"), message)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "删除 Key")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("开发")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText("密钥")
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        waitForReceipt("已删除 Key「开发密钥」")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(toggle(1).waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testDeleteKeyWithFaceID() {
        launchAndLogin(arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        openKeys(1, name: "Alice")
        expand(1)
        chooseFromCardMenu(1, "删除 Key…")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(toggle(1).exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        app.terminate()
        launchAndLogin(arguments: ["-ui-faceid-on"])
        defer { diagnostics("user-keys-delete-faceid-final") }
        openKeys(1, name: "Alice")
        expand(1)
        chooseFromCardMenu(1, "删除 Key…")
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["delete.confirm"].tap()
        waitForReceipt("已删除 Key「开发密钥」")
        XCTAssertTrue(toggle(1).waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testRevealNeedsLocalAuthentication() {
        launchAndLogin()
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "显示完整 Key…")
        let key = element("keys.reveal.key")
        XCTAssertTrue(key.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["完整 Key"].exists, app.debugDescription)
        XCTAssertTrue(key.label.contains("sk-ui-full-4087"), key.label)
        XCTAssertEqual(element("keys.reveal.notice").label, "完整 Key 只在这里显示，关闭后不保留")
        diagnostics("user-keys-reveal-sheet")
        app.buttons["keys.reveal.done"].tap()
        XCTAssertTrue(key.waitForNonExistence(timeout: 5), app.debugDescription)
        app.terminate()
        // A refused check asks for nothing more and says nothing.
        launchAndLogin(arguments: ["-ui-biometric-deny"])
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "显示完整 Key…")
        XCTAssertFalse(element("keys.reveal.sheet").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(element("stepup.code").exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        app.terminate()
        launchAndLogin(arguments: ["-ui-biometric-unavailable"])
        defer { diagnostics("user-keys-reveal-local-final") }
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "显示完整 Key…")
        waitForReceipt("这台设备没有设置 Face ID / 触控 ID，不能显示完整 Key")
        XCTAssertFalse(element("keys.reveal.sheet").exists, app.debugDescription)
    }

    @MainActor func testRevealAsksStepUpThenShowsKey() {
        launchAndLogin(arguments: ["-ui-step-up-required"])
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "显示完整 Key…")
        let code = element("stepup.code")
        XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
        code.tap()
        code.typeText("123456")
        let key = element("keys.reveal.key")
        XCTAssertTrue(key.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(key.label.contains("sk-ui-full-4087"), key.label)
        app.buttons["keys.reveal.done"].tap()
        XCTAssertTrue(key.waitForNonExistence(timeout: 5), app.debugDescription)
        // Verified once: the grant covers the next reveal.
        chooseFromCardMenu(4087, "显示完整 Key…")
        XCTAssertTrue(key.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(code.exists, app.debugDescription)
        app.buttons["keys.reveal.done"].tap()
        app.terminate()
        launchAndLogin(arguments: ["-ui-key-reveal-gone"])
        defer { diagnostics("user-keys-reveal-gone-final") }
        openKeys()
        expand(4087)
        chooseFromCardMenu(4087, "显示完整 Key…")
        waitForReceipt("这个 Key 已删除，没有可显示的内容")
        XCTAssertTrue(toggle(4087).waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testRevealDisabledForAdminKeyLogin() {
        launchAndLogin(arguments: ["-ui-step-up-required"], accessToken: "ui-admin-key")
        defer { diagnostics("user-keys-reveal-disabled-final") }
        openKeys()
        expand(4087)
        assertRevealDisabled(4087, reason: "Admin Key 登录不能查看完整 Key")
        app.terminate()
        launchAndLogin(arguments: ["-ui-step-up-no-totp"])
        openKeys()
        expand(4087)
        assertRevealDisabled(4087, reason: "需要先在 Web 端开启二次验证")
        app.terminate()
        launchAndLogin(arguments: ["-ui-without-capabilities", "api_keys.masked_view"])
        openKeys()
        expand(4087)
        let more = app.buttons["keys.card.4087.more"]
        reveal(more)
        more.tap()
        XCTAssertTrue(app.buttons["编辑 Key…"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["删除 Key…"].exists, app.debugDescription)
        XCTAssertFalse(revealItem().exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenGreysKeyManagement() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-keys-read-only-manage-final") }
        openKeys()
        let more = app.buttons["keys.card.4031.more"]
        reveal(more)
        XCTAssertFalse(more.isEnabled, app.debugDescription)
        let new = app.buttons["keys.new"]
        reveal(new)
        XCTAssertFalse(new.isEnabled, app.debugDescription)
    }

    // MARK: - S3-13 helpers

    @MainActor private func openNewKeyForm() {
        let new = app.buttons["keys.new"]
        reveal(new)
        new.tap()
        XCTAssertTrue(element("keys.form.sheet").waitForExistence(timeout: 5), app.debugDescription)
    }
    /// The sheet's form renders rows as they scroll in: swipes up until the row is there.
    @MainActor private func formElement(_ identifier: String) -> XCUIElement {
        let item = element(identifier)
        for _ in 0..<6 where !(item.waitForExistence(timeout: 1) && item.isHittable) { element("keys.form.sheet").swipeUp() }
        XCTAssertTrue(item.exists, "\(identifier)\n\(app.debugDescription)")
        return item
    }
    /// Replaces a form field's text; "" clears it.
    @MainActor private func fill(_ identifier: String, with value: String) {
        let field = formElement(identifier)
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !value.isEmpty { field.typeText(value) }
    }
    @MainActor private func revealItem() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "显示完整 Key…")).firstMatch
    }
    /// The item stays in ⋯, greyed, with the reason as its second line.
    @MainActor private func assertRevealDisabled(_ id: Int, reason: String, file: StaticString = #filePath, line: UInt = #line) {
        let more = app.buttons["keys.card.\(id).more"]
        reveal(more)
        more.tap()
        let item = revealItem()
        XCTAssertTrue(item.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
        XCTAssertFalse(item.isEnabled, app.debugDescription, file: file, line: line)
        let why = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", reason)).firstMatch
        XCTAssertTrue(why.exists, "\(reason)\n\(app.debugDescription)", file: file, line: line)
    }
}
