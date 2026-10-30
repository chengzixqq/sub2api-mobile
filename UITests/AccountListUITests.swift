import XCTest

/// 20 §1 account tab (S2-04) on the fixture site's 11 demo accounts (DemoData+Accounts, S2-03). Most tests add
/// -ui-accounts-long-windows so 过载中 (72 seconds in the design) and the model limits hold through a slow run.
final class AccountListUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// The demo accounts' figures; only these change if the fixture does.
    private enum Fixture {
        static let chipLabels = ["needs": "需处理 4", "all": "全部 11", "limited": "受限 3", "paused": "暂停·停用 2"]
        static let errorCount = "1"
        static let errorSummary = "401 凭据已失效（invalid_api_key）"
        static let site = "账号列表站点"
        static let longWindows = "-ui-accounts-long-windows"
    }

    @MainActor func testPlatformSectionsOrderAndHeaderSummaries() {
        launchAndOpenAccounts()
        defer { diagnostics("account-sections-final") }
        let openai = element("accounts.section.openai"), zhipu = element("accounts.section.zhipu"), anthropic = element("accounts.section.anthropic")
        for header in [openai, zhipu, anthropic] { XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription) }
        // 有错误或过载 → 有需处理 → 正常 → 全停; same rank by needs, then total.
        XCTAssertLessThan(openai.frame.minY, zhipu.frame.minY)
        XCTAssertLessThan(zhipu.frame.minY, anthropic.frame.minY)
        assertLabel(openai, contains: ["OpenAI", "2 个", "需处理 1", "已展开"])
        assertLabel(anthropic, contains: ["Anthropic", "3 个", "需处理 1"])
        diagnostics("account-sections")
        anthropic.tap()
        XCTAssertTrue(app.buttons["account.1"].waitForNonExistence(timeout: 5), app.debugDescription)
        assertLabel(anthropic, contains: ["已收起"])
        anthropic.tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 5), app.debugDescription)
        // Opening a detail and coming back keeps the order (frozen while the list lives).
        app.buttons["account.4"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(zhipu.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThan(openai.frame.minY, zhipu.frame.minY)
        let minimax = element("accounts.section.minimax")
        reveal(minimax)
        XCTAssertTrue(!anthropic.exists || anthropic.frame.minY < minimax.frame.minY, app.debugDescription)
        let gemini = element("accounts.section.gemini"), grok = element("accounts.section.grok")
        reveal(gemini)
        assertLabel(gemini, contains: ["Gemini", "1 个", "暂停 1"])
        reveal(grok)
        assertLabel(grok, contains: ["Grok", "1 个", "停用 1"])
    }

    @MainActor func testRowsShowCountdownErrorAndIdleStates() {
        launchAndOpenAccounts()
        defer { diagnostics("account-rows-final") }
        let limited = app.buttons["account.3"]
        reveal(limited)
        assertLabel(limited, contains: ["Claude-官方-03", "限流中", "剩余 ", "高级组 · OAuth", "上游 429", "模型限流 2"])
        XCTAssertNotNil(limited.label.range(of: #"\d{2}:\d{2} 恢复"#, options: .regularExpression), limited.label)
        let before = limited.label
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        XCTAssertNotEqual(limited.label, before, "the countdown should move every second")
        let normal = app.buttons["account.1"]
        reveal(normal)
        assertLabel(normal, contains: ["Claude-官方-01", "正常", "高级组、Claude Code 组 · OAuth", "并发 2/4", "今日 $409.38"])
        let error = app.buttons["account.7"]
        reveal(error, towardBottom: false)
        assertLabel(error, contains: ["OpenAI-备用-A", "错误", Fixture.errorSummary])
        let paused = app.buttons["account.5"]
        reveal(paused)
        assertLabel(paused, contains: ["Gemini-测试-B", "暂停"])
        let disabled = app.buttons["account.10"]
        reveal(disabled)
        assertLabel(disabled, contains: ["Grok-旧-01", "停用", "未分组 · API Key"])
        // Dimmed names cannot be read by XCUITest; the screenshot is for a person (Sub2Core tests cover isIdle).
        diagnostics("account-row-idle")
    }

    @MainActor func testChipsSwitchServerFilterAndShowCounts() {
        launchAndOpenAccounts()
        defer { diagnostics("account-chips-final") }
        for (key, label) in Fixture.chipLabels {
            let chip = element("accounts.chip.\(key)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(chip.label, label)
        }
        XCTAssertTrue(element("accounts.chip.all").isSelected, app.debugDescription)
        element("accounts.chip.limited").tap()
        XCTAssertTrue(app.buttons["account.1"].waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("accounts.chip.limited").isSelected, app.debugDescription)
        for id in [3, 11] { XCTAssertTrue(app.buttons["account.\(id)"].waitForExistence(timeout: 5), app.debugDescription) }
        reveal(app.buttons["account.12"])
        // Header numbers stay those of the whole platform.
        reveal(element("accounts.section.anthropic"), towardBottom: false)
        assertLabel(element("accounts.section.anthropic"), contains: ["3 个"])
        diagnostics("account-chip-limited")
        reveal(element("accounts.chip.paused"), towardBottom: false)
        element("accounts.chip.paused").tap()
        XCTAssertTrue(app.buttons["account.3"].waitForNonExistence(timeout: 10), app.debugDescription)
        for id in [5, 10] { XCTAssertTrue(app.buttons["account.\(id)"].waitForExistence(timeout: 5), app.debugDescription) }
        XCTAssertTrue(element("accounts.chip.paused").isSelected, app.debugDescription)
    }

    @MainActor func testPlatformMenuAddsRemovableToken() {
        launchAndOpenAccounts()
        defer { diagnostics("account-platform-final") }
        pickPlatform("Anthropic", expecting: "3 个")
        let token = element("accounts.chip.platform-token")
        XCTAssertTrue(token.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(token.label, "移除平台筛选 Anthropic")
        XCTAssertLessThan(token.frame.minX, element("accounts.chip.needs").frame.minX)
        XCTAssertTrue(element("accounts.section.openai").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("accounts.section.anthropic").exists, app.debugDescription)
        diagnostics("account-platform-token")
        token.tap()
        XCTAssertTrue(token.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("accounts.section.openai").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testEmptyFilterShowsEmptyCard() {
        launchAndOpenAccounts()
        defer { diagnostics("account-empty-final") }
        pickPlatform("Kimi", expecting: "1 个")
        XCTAssertTrue(element("accounts.section.kimi").waitForExistence(timeout: 10), app.debugDescription)
        element("accounts.chip.limited").tap()
        let empty = element("accounts.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "没有符合条件的账号")
        XCTAssertFalse(element("accounts.section.kimi").exists, app.debugDescription)
    }

    /// 10 §0.7-4 through the fixture intent; the overview row that sends it is S1-10's (HomeUITests).
    @MainActor func testLimitedIntentSelectsLimitedChipOnce() {
        launchAndOpenAccounts(arguments: ["-ui-accounts-intent", "limited"])
        defer { diagnostics("account-intent-final") }
        XCTAssertTrue(app.buttons["account.3"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("accounts.chip.limited").isSelected, app.debugDescription)
        XCTAssertFalse(app.buttons["account.1"].exists, app.debugDescription)
        element("accounts.chip.all").tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["用户"].tap()
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(element("accounts.chip.all").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("accounts.chip.all").isSelected, app.debugDescription)
        XCTAssertFalse(element("accounts.chip.limited").isSelected, app.debugDescription)
    }

    @MainActor func testRefreshFailureKeepsRowsWithBanner() {
        launchAndOpenAccounts(arguments: ["-ui-accounts-refresh-error"])
        defer { diagnostics("account-refresh-error-final") }
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
        pullToRefresh()
        let banner = element("accounts.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "读取失败，显示的是").exists, app.debugDescription)
        XCTAssertTrue(element("accounts.banner.retry").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.1"].exists, app.debugDescription)
        diagnostics("account-refresh-error")
    }

    @MainActor func testListFailureWithoutDataShowsRetry() {
        launchAndOpenAccounts(arguments: ["-ui-accounts-list-error"])
        defer { diagnostics("account-list-error-final") }
        XCTAssertTrue(element("accounts.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "读取账号失败").exists, app.debugDescription)
        XCTAssertTrue(element("accounts.failure.retry").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["account.1"].exists, app.debugDescription)
        XCTAssertFalse(element("accounts.section.openai").exists, app.debugDescription)
    }

    @MainActor func testTodayFailureShowsDash() {
        launchAndOpenAccounts(arguments: ["-ui-accounts-today-error"])
        defer { diagnostics("account-today-error-final") }
        let normal = app.buttons["account.1"]
        reveal(normal)
        assertLabel(normal, contains: ["今日 无数据", "并发 2/4"])
        XCTAssertFalse(element("accounts.failure").exists, app.debugDescription)
    }

    @MainActor func testTappingRowOpensDetail() {
        launchAndOpenAccounts()
        defer { diagnostics("account-open-detail-final") }
        let row = app.buttons["account.1"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(element("accounts.chip.all").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["账号"].isSelected, app.debugDescription)
        XCTAssertTrue(element("accounts.section.anthropic").exists, app.debugDescription)
    }

    /// The badge comes from AppModel's fetch without opening the tab: status-summary, or dashboard/stats without the capability.
    @MainActor func testAccountsTabBadgeShowsErrorCount() {
        for extra in [[], ["-ui-without-capabilities", "accounts.status_summary"]] {
            launchAndLogin(arguments: extra)
            let tab = app.tabBars.buttons["账号"]
            // The system reads the badge as the tab's value (“1 项” or “1”); the label stays “账号”.
            let badged = NSPredicate(format: "(value CONTAINS %@) OR (label CONTAINS %@)", Fixture.errorCount, Fixture.errorCount)
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: badged, object: tab)], timeout: 15), .completed,
                           "\(extra): \(String(describing: tab.value)) \(app.debugDescription)")
            diagnostics("account-tab-badge")
            app.terminate()
        }
    }

    @MainActor func testSubtitleShowsSiteAndTotal() {
        launchAndOpenAccounts()
        defer { diagnostics("account-subtitle-final") }
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
        let subtitle = text(containing: "\(Fixture.site) · 11 个")
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(subtitle.label.contains("更新"), subtitle.label)
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label == '账号' OR label BEGINSWITH '账号,'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.tap()
        XCTAssertTrue(menuItem("添加站点…").waitForExistence(timeout: 5), app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://accounts-list.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func launchAndOpenAccounts(arguments: [String] = [Fixture.longWindows]) {
        launchAndLogin(arguments: arguments.contains(Fixture.longWindows) ? arguments : arguments + [Fixture.longWindows])
        app.tabBars.buttons["账号"].tap()
    }
    @MainActor private func pickPlatform(_ name: String, expecting count: String) {
        let menu = element("accounts.chip.platform")
        reveal(menu, towardBottom: false)
        menu.tap()
        XCTAssertTrue(menuItem("全部平台").waitForExistence(timeout: 5), app.debugDescription)
        let item = menuItem(name)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(item.label.contains(count), item.label)
        diagnostics("account-platform-menu")
        item.tap()
    }
    @MainActor private func pullToRefresh() {
        let list = app.collectionViews.firstMatch
        let target: XCUIElement = list.exists ? list : app
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    }
    @MainActor private func assertLabel(_ item: XCUIElement, contains parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for part in parts { XCTAssertTrue(item.label.contains(part), "“\(part)” missing in “\(item.label)”", file: file, line: line) }
    }
    /// System menu items carry no identifier and read “title, detail”.
    @MainActor private func menuItem(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == '' AND (label == %@ OR label BEGINSWITH %@)", label, label + ",")).firstMatch
    }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
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

    // MARK: - 行右滑（S2-06）

    /// OpenAI-主力-01 is normal: 停止调度 pauses it, and 撤销 on the receipt (within its 4.2 seconds) brings it back.
    @MainActor func testScheduleSwipeStopsThenUndoRestores() {
        launchAndOpenAccounts()
        defer { diagnostics("account-swipe-stop-final") }
        let row = app.buttons["account.4"]
        reveal(row)
        assertLabel(row, contains: ["OpenAI-主力-01", "正常"])
        tapSwipeAction(on: row, titled: "停止调度")
        waitForReceipt("已停止调度")
        // The receipt stays 4.2 seconds: one look at the row, then 撤销.
        XCTAssertTrue(row.label.contains("暂停"), row.label)
        app.buttons.matching(NSPredicate(format: "identifier == 'receipt.action' AND label == '撤销'")).firstMatch.tap()
        waitForLabel(row, containing: "正常")
        XCTAssertFalse(row.label.contains("暂停"), row.label)
        XCTAssertTrue(app.staticTexts["receipt.text"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// Gemini-测试-B has its switch off: the swipe offers only 启用调度.
    @MainActor func testScheduleSwipeEnablesPausedAccount() {
        launchAndOpenAccounts()
        defer { diagnostics("account-swipe-enable-final") }
        let row = app.buttons["account.5"]
        reveal(row)
        assertLabel(row, contains: ["Gemini-测试-B", "暂停"])
        row.swipeLeft()
        let enable = swipeButton("启用调度")
        XCTAssertTrue(enable.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(swipeButton("停止调度").exists, app.debugDescription)
        diagnostics("account-swipe-enable")
        enable.tap()
        waitForReceipt("已启用调度")
        XCTAssertEqual(app.buttons["receipt.action"].label, "撤销")
        waitForLabel(row, containing: "正常")
    }

    @MainActor func testScheduleSwipeFailureShowsReasonAndKeepsRow() {
        launchAndOpenAccounts(arguments: ["-ui-account-write-fail"])
        defer { diagnostics("account-swipe-failure-final") }
        let row = app.buttons["account.4"]
        reveal(row)
        tapSwipeAction(on: row, titled: "停止调度")
        waitForReceipt("停止调度没有成功：站点暂时不可用")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        assertLabel(row, contains: ["正常"])
    }

    /// 00 §2.6.3 / C-1: a read-only admin access token gets no swipe; the row still opens the detail. A row without swipe
    /// actions may take the swipe as a tap (as before S2-06), so the detail can already be open.
    @MainActor func testReadOnlyTokenOffersNoScheduleSwipe() {
        launchWithReadOnlyToken()
        defer { diagnostics("account-swipe-readonly-final") }
        app.tabBars.buttons["账号"].tap()
        let row = app.buttons["account.4"]
        reveal(row)
        row.swipeLeft()
        XCTAssertFalse(swipeButton("停止调度").waitForExistence(timeout: 1), app.debugDescription)
        let detail = app.navigationBars["OpenAI-主力-01"]
        if !detail.exists { row.tap() }
        XCTAssertTrue(detail.waitForExistence(timeout: 10), app.debugDescription)
    }

    /// The access-token method with a `sat_` key; `-ui-readonly-token` makes it read-only.
    @MainActor private func launchWithReadOnlyToken() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-readonly-token", Fixture.longWindows]; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://accounts-list.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-readonly", in: "login.key")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// System swipe buttons are found by their title; the identifier does not always reach them. A swipe taken as a tap opens
    /// the detail, whose button row has the same titles (S2-08).
    @MainActor private func swipeButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'account.action.')", title)).firstMatch
    }
    @MainActor private func tapSwipeAction(on row: XCUIElement, titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        row.swipeLeft()
        let button = swipeButton(title)
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        button.tap()
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing part: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", part), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "“\(part)” missing in “\(item.label)”", file: file, line: line)
    }
}
