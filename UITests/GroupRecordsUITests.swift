import XCTest

/// 50 §6–§7 (S5-12): the group's API key page and subscription page on the `-ui-testing` site, entered from the detail's
/// 记录与关联 rows (S5-07). Times shift with the clock, so only fragments that do not are asserted (the day boundary and the
/// clock formats are unit-tested).
final class GroupRecordsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let keysFailure = "-ui-group-keys-failure"
        static let keysMoreFailure = "-ui-group-keys-more-failure"
        static let slowMore = "-ui-group-records-slow-more"
    }

    /// 高级组: the status badges, masks, owners, today's spend and the quota bar; the head and the footnote; a row opens its owner
    /// and back the page is as it was.
    @MainActor func testKeyRowsShowBadgesMasksOwnersAndTodayAndOpenTheOwner() {
        openKeys(group: 1)
        defer { diagnostics("group-keys-premium-final") }
        XCTAssertTrue(app.staticTexts["高级组 · 共 38 个"].waitForExistence(timeout: 10), app.debugDescription)
        let head = element("group.keys.head")
        XCTAssertTrue(head.label.contains("新建的在前") && head.label.contains("所属用户 · 最近使用 · 今日"), head.label)
        let production = key(5138)
        for part in ["生产", "sk-…Kp21", "Nova 工作室 · "] { waitForLabel(production, contains: part) }
        waitForLabel(production, contains: "今日 $12.40")
        XCTAssertFalse(production.label.contains("已停用"), production.label)
        let rows: [(Int, [String])] = [(5135, ["移动端", "额度 $8.45 / $20.00"]), (5133, ["已过期", "赵磊（已禁用）"]),
                                       (5132, ["用户 #26", "从未使用"]), (5131, ["<脚本> & 工具", "已停用"])]
        for (id, parts) in rows {
            app.scrollUntilExists(key(id))
            for part in parts { waitForLabel(key(id), contains: part) }
        }

        app.scrollUntilExists(production, towardBottom: false)
        production.tap()
        XCTAssertTrue(element("user.detail").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(production.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("group.keys.skeleton").exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["API 密钥"].exists, app.debugDescription)
    }

    /// 50 §6.3 翻页提示: at the bottom of page 1 “已显示 20 / 38 个”, then the rest; the footnote under the last row.
    @MainActor func testKeysLoadNextPageAtTheBottom() {
        openKeys(group: 1, arguments: [Fixture.slowMore])
        defer { diagnostics("group-keys-more-final") }
        let more = element("group.keys.more")
        app.scrollUntilExists(more)
        XCTAssertTrue(more.label.contains("已显示 20 / 38 个 · 滚动到底继续加载"), more.label)
        XCTAssertTrue(more.waitForNonExistence(timeout: 15), app.debugDescription)
        let last = key(5101)
        app.scrollUntilExists(last)
        let footnote = element("group.keys.footnote")
        app.scrollUntilExists(footnote)
        XCTAssertEqual(footnote.label, "点按进入所属用户。给 Key 换分组、重置速率限制在用户的 Key 里操作。")
    }

    /// 6.5: a failed next page keeps the rows and offers 加载失败 · 重试.
    @MainActor func testKeysNextPageFailureRetries() {
        openKeys(group: 1, arguments: [Fixture.keysMoreFailure])
        defer { diagnostics("group-keys-more-failure-final") }
        let retry = app.buttons["group.keys.more.retry"]
        app.scrollUntilExists(retry)
        XCTAssertEqual(retry.label, "加载失败 · 重试")
        XCTAssertTrue(key(5119).exists, app.debugDescription)
        retry.tap()
        let last = key(5101)
        app.scrollUntilExists(last)
        XCTAssertFalse(app.buttons["group.keys.more.retry"].exists, app.debugDescription)
    }

    /// 6.5: the first page fails without rows to keep: the list failure, then 重试.
    @MainActor func testKeysListFailureRetries() {
        openKeys(group: 1, arguments: [Fixture.keysFailure])
        defer { diagnostics("group-keys-failure-final") }
        let failure = element("group.keys.list.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(key(5138).exists, app.debugDescription)
        app.buttons["group.keys.list.retry"].tap()
        XCTAssertTrue(key(5138).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(failure.exists, app.debugDescription)
    }

    /// 企业专线's used-up quota rides the caution badge; Antigravity 组 has none; 默认组's stopped key (the list scrolls down only).
    @MainActor func testExhaustedStoppedAndEmptyGroups() {
        openKeys(group: 4)
        defer { diagnostics("group-keys-others-final") }
        XCTAssertTrue(app.staticTexts["企业专线 · 共 6 个"].waitForExistence(timeout: 10), app.debugDescription)
        for part in ["企业网关", "额度耗尽", "额度 $50.00 / $50.00"] { waitForLabel(key(5406), contains: part) }
        XCTAssertFalse(element("group.keys.more").exists, app.debugDescription)

        goBack(); goBack()
        openListedGroupRecords(10, record: "keys")
        let empty = element("group.keys.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(empty.label.contains("还没有 API 密钥使用这个分组"), empty.label)
        XCTAssertTrue(app.staticTexts["Antigravity 组 · 共 0 个"].exists, app.debugDescription)
        XCTAssertFalse(element("group.keys.more").exists, app.debugDescription)

        goBack(); goBack()
        openListedGroupRecords(3, record: "keys")
        XCTAssertTrue(app.staticTexts["默认组 · 共 21 个"].waitForExistence(timeout: 10), app.debugDescription)
        let stopped = key(5320)
        app.scrollUntilExists(stopped)
        waitForLabel(stopped, contains: "已停用")
    }

    /// R14: a read-only token never asks for the keys' today spend: every row says 今日 —, and no error shows.
    @MainActor func testReadOnlyTokenShowsDashForTodaySpend() {
        launchAndOpenGroups(readOnly: true)
        openListedGroupRecords(1, record: "keys")
        defer { diagnostics("group-keys-readonly-final") }
        let production = key(5138)
        XCTAssertTrue(production.waitForExistence(timeout: 10), app.debugDescription)
        waitForLabel(production, contains: "今日无数据")
        XCTAssertFalse(element("group.keys.list.failure").exists, app.debugDescription)
        XCTAssertFalse(element("group.keys.refresh.retry").exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["高级组 · 共 38 个"].exists, app.debugDescription)
    }

    /// 50 §7: the limits, days left and the three usage columns of active rows; suspended and expired rows without usage; a row
    /// without its user; the footnote; a row opens the user.
    @MainActor func testSubscriptionsShowDaysLeftUsageAndDimmedRows() {
        launchAndOpenGroups()
        openListedGroupRecords(4, record: "subscriptions")
        defer { diagnostics("group-subscriptions-final") }
        XCTAssertTrue(app.navigationBars["订阅"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["企业专线 · 生效中 12 个"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("group.subs.limits").label, "每个订阅的限额，每日 $20，每周 $100，每月 $300")
        let head = element("group.subs.head")
        XCTAssertTrue(head.label.contains("新分配的在前") && head.label.contains("用量 · 到期"), head.label)
        let soon = subscription(815)
        for part in ["林一", "剩余 4 天", "每周 $18.60 / $100", "至 ", "yi.lin@example.com"] { waitForLabel(soon, contains: part) }
        waitForLabel(subscription(814), contains: "每日 $18.20 / $20")
        let suspended = subscription(813)
        app.scrollUntilExists(suspended)
        waitForLabel(suspended, contains: "已暂停")
        XCTAssertFalse(suspended.label.contains("每日"), suspended.label)
        let expired = subscription(812)
        for part in ["已过期", "已到期"] { waitForLabel(expired, contains: part) }
        XCTAssertFalse(expired.label.contains("每日"), expired.label)
        waitForLabel(subscription(811), contains: "用户 #26")
        let footnote = element("group.subs.footnote")
        app.scrollUntilExists(footnote)
        XCTAssertEqual(footnote.label, "点按进入用户。调整有效期、重置配额、撤销在 Web 订阅管理中操作。")
        XCTAssertFalse(element("group.subs.more").exists, app.debugDescription)

        app.scrollUntilExists(soon, towardBottom: false)
        soon.tap()
        XCTAssertTrue(element("user.detail").waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in (or a read-only `sat_` token), then 搜索 → 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = [], readOnly: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (readOnly ? ["-ui-readonly-token"] : []) + arguments
        app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("分组记录验收", in: "login.name")
        enter("https://group-records.example.invalid", in: "login.url")
        if readOnly {
            let method = element("login.method.accessToken"); reveal(method); method.tap()
            enter("sat_fixture-readonly", in: "login.key")
        } else {
            enter("admin@example.com", in: "login.email")
            enter("fixture-password", in: "login.password")
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(app.buttons["group.row.4"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openKeys(group: Int, arguments: [String] = []) {
        launchAndOpenGroups(arguments: arguments)
        openListedGroupRecords(group, record: "keys")
    }
    /// The list's row, the detail, then its 记录与关联 row (group.records.keys / .subscriptions).
    @MainActor private func openListedGroupRecords(_ id: Int, record: String) {
        let target = app.buttons["group.row.\(id)"]
        app.scrollUntilExists(target)
        target.tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        let row = element("group.records.\(record)")
        app.scrollUntilExists(row)
        row.tap()
        let title = record == "keys" ? "API 密钥" : "订阅"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func key(_ id: Int) -> XCUIElement { element("group.key.\(id)") }
    @MainActor private func subscription(_ id: Int) -> XCUIElement { element("group.sub.\(id)") }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Drags the page until the item sits above the keyboard or the tab bar.
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
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.poll(NSPredicate(format: "label CONTAINS %@", text), timeout: 10), "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                      file: file, line: line)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
