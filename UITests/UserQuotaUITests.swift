import XCTest

/// S3-14 Key 与限额 · 平台限额 (30 §8): Alice (1) has Anthropic 10 / 50 / 不限 with $2.80 · $41.00 · $48.60 used, 王小明 (3) has
/// OpenAI banned (0 / 0 / 0), Studio-K 团队 (10) an active subscription and Bob (2) no quota (S3D1-04, PlatformQuotaDemoStore).
final class UserQuotaUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testQuotaSectionShowsWindowsBannedBadgeAndEmptyState() {
        launchAndLogin()
        defer { diagnostics("user-quota-section-final") }
        openKeys(1, name: "Alice")
        let row = quotaRow("anthropic")
        reveal(row)
        for part in ["Anthropic", "28.0%", "$2.80 / $10", "82.0%", "$41.00 / $50", "不限", "已用 $48.60"] { XCTAssertTrue(row.label.contains(part), row.label) }
        XCTAssertFalse(row.label.contains("已禁止使用"), row.label)
        XCTAssertFalse(element("keys.quota.subscription").exists, app.debugDescription)
        let footnote = element("keys.quota.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "留空 = 不限制，0 = 禁止使用该平台。月为 30 天滚动窗口。")
        backToUsers()
        openKeys(3, name: "王小明")
        let banned = quotaRow("openai")
        reveal(banned)
        for part in ["OpenAI", "已禁止使用", "已禁止", "不能使用"] { XCTAssertTrue(banned.label.contains(part), banned.label) }
        backToUsers()
        openKeys(2, name: "Bob", viaMenu: true)
        let empty = element("keys.quota.empty")
        reveal(empty)
        XCTAssertEqual(empty.label, "没有设置，各平台不限制")
        XCTAssertTrue(app.buttons["keys.quota.add"].exists, app.debugDescription)
    }

    @MainActor func testAddPlatformQuotaAndSaveThenUndo() {
        launchAndLogin()
        defer { diagnostics("user-quota-add-final") }
        openKeys(1, name: "Alice")
        tap(app.buttons["keys.quota.add"])
        XCTAssertTrue(app.navigationBars["添加平台限额"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["keys.quota.pick.anthropic"].exists, "已有限额的平台不在列表里")
        XCTAssertFalse(app.buttons["keys.quota.pick.composite"].exists)
        app.buttons["keys.quota.pick.openai"].tap()
        XCTAssertTrue(app.navigationBars["OpenAI 限额"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["keys.quota.clear"].exists, "还没有限额时没有“清空三个窗口”")
        XCTAssertFalse(app.buttons["keys.quota.reset.daily"].exists, app.debugDescription)
        fill("keys.quota.input.daily", with: "20")
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已更新 OpenAI 的平台限额")
        let row = quotaRow("openai")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("$0.00 / $20"), row.label)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(quotaRow("anthropic").exists, app.debugDescription)
    }

    @MainActor func testZeroWarningAndSaveDisabledUntilChanged() {
        launchAndLogin()
        defer { diagnostics("user-quota-zero-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        let save = app.buttons["keys.quota.save"]
        XCTAssertFalse(save.isEnabled, "没改窗口时“保存”不亮")
        XCTAssertEqual(element("keys.quota.input.daily").value as? String, "10")
        XCTAssertTrue(element("keys.quota.usage.daily").label.contains("已用 $2.80 · 明天 00:00 重置"), element("keys.quota.usage.daily").label)
        XCTAssertEqual(element("keys.quota.usage.monthly").label, "已用 $48.60")
        XCTAssertTrue(app.buttons["keys.quota.reset.weekly"].exists && !app.buttons["keys.quota.reset.monthly"].exists, app.debugDescription)
        fill("keys.quota.input.monthly", with: "0")
        let warning = element("keys.quota.zero.monthly")
        XCTAssertTrue(warning.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(warning.label, "填 0 会完全禁止使用 Anthropic，不论其他窗口")
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        // The caret is still after the “0” just typed.
        element("keys.quota.input.monthly").typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(waitUntil(save, "isEnabled == false"), "改回原值后“保存”又不亮")
        XCTAssertFalse(warning.exists, app.debugDescription)
        app.buttons["keys.quota.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Anthropic 限额"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testCancelQuotaAndUndoRestores() {
        launchAndLogin()
        defer { diagnostics("user-quota-cancel-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        tap(app.buttons["keys.quota.clear"])
        let daily = element("keys.quota.input.daily")
        XCTAssertTrue(["", "不限制"].contains(daily.value as? String ?? "?"), "清空只清本地输入：\(String(describing: daily.value))")
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已取消 Anthropic 的平台限额")
        XCTAssertTrue(quotaRow("anthropic").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        let row = quotaRow("anthropic")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row.label.contains("$2.80 / $10") && row.label.contains("$41.00 / $50"), "恢复时连用量一起恢复：\(row.label)")
    }

    @MainActor func testChangeLimitAndUndoPutsPrevious() {
        launchAndLogin()
        defer { diagnostics("user-quota-change-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        fill("keys.quota.input.daily", with: "20")
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已更新 Anthropic 的平台限额")
        let row = quotaRow("anthropic")
        waitForLabel(row, contains: "$2.80 / $20")
        app.buttons["receipt.action"].tap()
        waitForLabel(row, contains: "$2.80 / $10")
        XCTAssertTrue(row.label.contains("$41.00 / $50"), row.label)
    }

    @MainActor func testRestoreConflictShowsFixedCopy() {
        launchAndLogin(arguments: ["-ui-quota-restore-conflict"])
        defer { diagnostics("user-quota-conflict-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        tap(app.buttons["keys.quota.clear"])
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已取消 Anthropic 的平台限额")
        app.buttons["receipt.action"].tap()
        waitForReceipt("已有人重新设置了这个平台的限额，无法恢复")
    }

    @MainActor func testResetWindowConfirmsAndIsNotUndoable() {
        launchAndLogin()
        defer { diagnostics("user-quota-reset-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        tap(app.buttons["keys.quota.reset.daily"])
        let alert = app.alerts["重置 Anthropic 的日用量？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["Alice在 Anthropic 的日用量（$2.80）会归零。此操作立即生效。"].exists, app.debugDescription)
        alert.buttons["重置该窗口"].tap()
        waitForReceipt("已重置 Anthropic 日用量")
        XCTAssertFalse(app.buttons["receipt.action"].exists, "重置不能撤销")
        waitForLabel(element("keys.quota.usage.daily"), contains: "已用 $0.00")
        XCTAssertEqual(element("keys.quota.input.daily").value as? String, "10")
    }

    @MainActor func testSubscriptionNoticeForActiveSubscriber() {
        launchAndLogin()
        defer { diagnostics("user-quota-subscription-final") }
        openKeys()
        let notice = element("keys.quota.subscription")
        reveal(notice)
        XCTAssertEqual(notice.label, "此用户有活跃订阅：平台限额只在余额模式下生效，订阅模式的请求不受限额约束。")
        tap(app.buttons["keys.quota.add"])
        app.buttons["keys.quota.pick.anthropic"].tap()
        XCTAssertTrue(app.navigationBars["Anthropic 限额"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("keys.quota.subscription").exists, app.debugDescription)
    }

    @MainActor func testLegacyFallbackRewritesWholeTableAndWarnsUsageReset() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "users.platform_quota_item"])
        defer { diagnostics("user-quota-fallback-final") }
        openKeys(1, name: "Alice")
        openQuota("anthropic", title: "Anthropic 限额")
        tap(app.buttons["keys.quota.clear"])
        app.buttons["keys.quota.save"].tap()
        waitForReceipt("已取消 Anthropic 的平台限额")
        XCTAssertTrue(quotaRow("anthropic").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        waitForReceipt("已撤销，Anthropic 的已用额度会从 0 重新计算")
        let row = quotaRow("anthropic")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("$0.00 / $10"), row.label)
    }

    @MainActor func testServiceUnavailableShowsDisabledCopy() {
        launchAndLogin(arguments: ["-ui-quota-unavailable"])
        defer { diagnostics("user-quota-unavailable-final") }
        openKeys(1, name: "Alice")
        reveal(element("keys.quota.empty"))
        tap(app.buttons["keys.quota.add"])
        app.buttons["keys.quota.pick.anthropic"].tap()
        XCTAssertTrue(app.navigationBars["Anthropic 限额"].waitForExistence(timeout: 5), app.debugDescription)
        fill("keys.quota.input.daily", with: "10")
        app.buttons["keys.quota.save"].tap()
        let disabled = element("keys.quota.unavailable")
        XCTAssertTrue(disabled.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(disabled.label, "站点没有启用平台限额")
        XCTAssertFalse(app.buttons["keys.quota.add"].exists, app.debugDescription)
    }

    @MainActor func testListFailureRetriesInSection() {
        launchAndLogin(arguments: ["-ui-quota-list-error"])
        defer { diagnostics("user-quota-retry-final") }
        openKeys(1, name: "Alice")
        let retry = app.buttons["keys.quota.retry"]
        reveal(retry)
        XCTAssertTrue(retry.label.contains("平台限额加载失败 · 重试"), retry.label)
        retry.tap()
        XCTAssertTrue(quotaRow("anthropic").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenDisablesQuotaWrites() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-quota-read-only-final") }
        openKeys(1, name: "Alice")
        let add = app.buttons["keys.quota.add"]
        reveal(add)
        XCTAssertFalse(add.isEnabled, app.debugDescription)
        openQuota("anthropic", title: "Anthropic 限额")
        XCTAssertFalse(app.buttons["keys.quota.save"].isEnabled, app.debugDescription)
        let reset = app.buttons["keys.quota.reset.daily"]
        reveal(reset)
        XCTAssertFalse(reset.isEnabled, app.debugDescription)
        let clear = app.buttons["keys.quota.clear"]
        reveal(clear)
        XCTAssertFalse(clear.isEnabled, app.debugDescription)
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
        enter("https://user-quota.example.invalid", in: app.textFields["login.url"])
        enter("限额验收", in: app.textFields["login.name"])
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
    /// The detail's key summary lands on the third segment; `viaMenu` goes through ⋯ 编辑用户 (a user without keys has no summary).
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
    /// From the edit page back to the list: the edit page, then the detail.
    @MainActor private func backToUsers() {
        for _ in 0..<3 where !app.buttons["user.1"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            _ = app.buttons["user.1"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons["user.1"].exists, app.debugDescription)
    }
    @MainActor private func quotaRow(_ platform: String) -> XCUIElement { app.buttons["keys.quota.row.\(platform)"] }
    @MainActor private func openQuota(_ platform: String, title: String) {
        tap(quotaRow(platform))
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), app.debugDescription)
    }
    /// Replaces a limit field's text in the sheet. A tap snaps the caret to a word boundary of the right-aligned number, so a
    /// whole number there is selected with a double tap and typed over.
    @MainActor private func fill(_ identifier: String, with value: String) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.doubleTap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(value)
        XCTAssertTrue(waitUntil(field, "value == '\(value)'"), "\(identifier) 应为 \(value)：\(String(describing: field.value))")
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
