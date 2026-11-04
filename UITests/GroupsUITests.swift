import XCTest

/// 50 §1 (S5-04): the group list on the `-ui-testing` site — eleven groups whose buckets are counted from the demo accounts
/// (GroupFixtures). Timed windows run an hour longer so GLM 组's overload holds for the whole test. Creating and editing go
/// through the group sheet (S5-10), entered from the list and the detail's 编辑分组; its own cases are GroupEditUITests.
final class GroupsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let listFailure = "-ui-group-list-failure"
        static let refreshFailure = "-ui-group-refresh-failure"
        static let usageFailure = "-ui-group-usage-failure"
        static let usageSlow = "-ui-group-usage-slow"
        static let usageFailureAfterFirst = "-ui-group-usage-failure-after-first"
        static let shortageFailureAfterFirst = "-ui-group-shortage-failure-after-first"
        static let empty = "-ui-group-empty"
        static let segment = "-ui-group-segment"
        static let withoutCapabilities = "-ui-without-capabilities"
    }

    @MainActor func testListSplitsIntoAttentionNormalAndOffInOrder() {
        launchAndOpenGroups()
        defer { diagnostics("groups-list-sections-final") }
        XCTAssertEqual(element("groups.section.attention").label, "需处理 6")
        XCTAssertTrue(text(containing: "· 5 个分组无可用账号").waitForExistence(timeout: 10), app.debugDescription)
        // none before low; the same share by sort_order.
        assertOrder([4, 7, 9, 10, 11, 2])
        let normal = element("groups.section.normal")
        app.scrollUntilExists(normal)
        XCTAssertEqual(normal.label, "正常 4")
        // The available share ascending.
        assertOrder([1, 3, 5, 8])
        let off = element("groups.section.off")
        app.scrollUntilExists(off)
        XCTAssertEqual(off.label, "停用 1")
        app.scrollUntilExists(row(6))
        XCTAssertTrue(element("groups.footnote").exists, app.debugDescription)
    }

    @MainActor func testRowsShowAvailabilityBreakdownBillingAndToday() {
        launchAndOpenGroups()
        defer { diagnostics("groups-list-rows-final") }
        assertLabel(row(4), contains: ["企业专线", "OpenAI", "专属", "无可用账号", "可用 0 / 1", "错误 1", "费率倍数 ×1.2 · 订阅计费", "今日 $0.00"])
        assertLabel(row(10), contains: ["Antigravity 组", "没有账号", "可用 0 / 0", "今日 $0.00"])
        assertLabel(row(2), contains: ["标准组", "可用偏低", "可用 1 / 2", "错误 1"])
        assertLabel(row(1), contains: ["高级组", "Anthropic", "可用 2 / 3", "受限 1", "费率倍数 ×0.8 · 标准计费", "今日 $933.30"])
        for word in ["专属", "可用偏低", "无可用账号", "没有账号", "已停用"] { XCTAssertFalse(row(1).label.contains(word), row(1).label) }
        assertLabel(row(6), contains: ["测试组", "Gemini", "已停用", "暂停·停用 1", "今日 $10.80"])
    }

    @MainActor func testSearchFiltersByNameOrPlatformAndShowsNoMatch() {
        launchAndOpenGroups()
        defer { diagnostics("groups-list-search-final") }
        let field = app.searchFields["分组名称或平台"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("智谱")
        XCTAssertTrue(row(7).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(4).waitForNonExistence(timeout: 5), app.debugDescription)
        field.typeText(deletes(2) + "anthropic")
        XCTAssertTrue(row(1).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(5).exists, app.debugDescription)
        XCTAssertFalse(row(2).exists, app.debugDescription)
        XCTAssertFalse(row(7).exists, app.debugDescription)
        field.typeText(deletes(9) + "不存在的分组")
        let none = element("groups.search.empty")
        XCTAssertTrue(none.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(none.label, "没有匹配的分组")
        field.typeText(deletes(6))
        XCTAssertTrue(row(4).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(none.exists, app.debugDescription)
    }

    @MainActor func testUsageFailureShowsDashOnEveryRow() {
        launchAndOpenGroups(arguments: [Fixture.usageFailure])
        defer { diagnostics("groups-list-usage-failure-final") }
        waitForLabel(row(4), contains: "今日无数据")
        XCTAssertFalse(row(4).label.contains("今日 $"), row(4).label)
        app.scrollUntilExists(row(1))
        waitForLabel(row(1), contains: "今日无数据")
        XCTAssertFalse(element("groups.refresh.retry").exists, app.debugDescription)
        XCTAssertFalse(element("groups.list.failure").exists, app.debugDescription)
        // Never read: no 更新失败 strip (U-10).
        XCTAssertFalse(element("groups.stale.retry").exists, app.debugDescription)
    }

    @MainActor func testListFailureShowsErrorStateAndRetryLoads() {
        launchAndOpenGroups(arguments: [Fixture.listFailure], waitsForRows: false)
        defer { diagnostics("groups-list-failure-final") }
        let failure = element("groups.list.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(4).exists, app.debugDescription)
        app.buttons["groups.list.retry"].tap()
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testRefreshFailureKeepsRowsUnderBanner() {
        launchAndOpenGroups(arguments: [Fixture.refreshFailure])
        defer { diagnostics("groups-list-refresh-failure-final") }
        app.pullToRefresh(from: row(4))
        let strip = app.buttons["groups.refresh.retry"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(strip.label.contains("刷新失败"), strip.label)
        XCTAssertTrue(row(4).exists, app.debugDescription)
        XCTAssertFalse(element("groups.list.failure").exists, app.debugDescription)
    }

    @MainActor func testOldServerCountsErrorsFromAccountsAndJudgesShortageLocally() {
        launchAndOpenGroups(arguments: [Fixture.withoutCapabilities, "groups.account_buckets,accounts.status_summary"])
        defer { diagnostics("groups-list-old-server-final") }
        // F04's fallback counts 企业专线's error account; without it the account would read 暂停·停用.
        waitForLabel(row(4), contains: "错误 1")
        XCTAssertFalse(row(4).label.contains("暂停·停用"), row(4).label)
        let normal = element("groups.section.normal")
        app.scrollUntilExists(normal)
        XCTAssertEqual(normal.label, "正常 5")
        // The local half rule: 1 of 2 is not short.
        app.scrollUntilExists(row(2))
        XCTAssertFalse(row(2).label.contains("可用偏低"), row(2).label)
        XCTAssertGreaterThan(row(2).frame.minY, normal.frame.minY)
    }

    @MainActor func testEmptySiteOffersNewGroup() {
        launchAndOpenGroups(arguments: [Fixture.empty], waitsForRows: false)
        defer { diagnostics("groups-list-empty-final") }
        let empty = element("groups.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "还没有分组")
        let create = app.buttons["groups.empty.create"]
        XCTAssertTrue(create.isEnabled, app.debugDescription)
        create.tap()
        XCTAssertTrue(element("group-edit.name").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["新建分组"].exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenGreysNewGroup() {
        launchAndOpenGroups(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("groups-list-read-only-final") }
        let create = app.buttons["groups.create"]
        XCTAssertTrue(create.exists, app.debugDescription)
        XCTAssertFalse(create.isEnabled, app.debugDescription)
        waitForLabel(row(4), contains: "今日 $0.00")
    }

    @MainActor func testSegmentRouteScrollsToSection() {
        launchAndOpenGroups(arguments: [Fixture.segment, "off"], waitsForRows: false)
        defer { diagnostics("groups-list-segment-final") }
        let target = row(6)
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 10), .completed, app.debugDescription)
        XCTAssertTrue(element("groups.section.off").isHittable, app.debugDescription)
    }

    @MainActor func testCreateEditStatusAndDeleteGroup() {
        launchAndOpenGroups()
        defer { diagnostics("group-lifecycle-final") }
        app.buttons["groups.create"].tap()
        set("移动分组", field: "group-edit.name", towardBottom: false)
        set("iPhone 管理", field: "group-edit.description")
        set("1.25", field: "group-edit.rate")
        set("90", field: "group-edit.rpm")
        // S5-10: a public group with nothing available asks first.
        submitEditor()
        confirmAlert("仍然创建")
        waitForReceipt("已创建「移动分组」")
        // A new group has no account yet: 需处理, “没有账号”.
        let created = row(12)
        XCTAssertTrue(created.waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(created)
        XCTAssertTrue(created.label.contains("没有账号"), created.label)
        XCTAssertGreaterThan(created.frame.minY, element("groups.section.attention").frame.minY)
        created.tap()
        // S5-06: the detail's button row; a group without accounts has only 编辑分组 until S5-08.
        reveal(app.buttons["group.action.edit"])
        app.buttons["group.action.edit"].tap()
        set("移动分组更新", field: "group-edit.name", towardBottom: false)
        set("仅修改描述与名称", field: "group-edit.description")
        // Only the name and the description: saved without asking.
        submitEditor()
        // An Any query by the new title also matches the editor TextField's
        // value while the sheet is dismissing. Wait for the destination bar.
        XCTAssertTrue(app.navigationBars["移动分组更新"].waitForExistence(timeout: 10), app.debugDescription)
        // S5-05: 停用分组… (in the detail's ⋯) asks first, then says so in a receipt; 启用分组 then leads the button row.
        tapMoreItem("停用分组…")
        confirmDisable()
        waitForReceipt("已停用「移动分组更新」")
        XCTAssertTrue(app.buttons["group.action.enable"].waitForExistence(timeout: 5), app.debugDescription)
        diagnostics("group-edit-and-status-success")
        tapMoreItem("删除分组…")
        typeDeleteName("移动分组更新")
        waitForReceipt("已删除分组「移动分组更新」")
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(created.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(4).exists, app.debugDescription)
    }

    /// 00 §4.6: a slow usage-summary does not hold back 重试; the list is read again at once.
    @MainActor func testListRetryDoesNotWaitForSlowUsage() {
        launchAndOpenGroups(arguments: [Fixture.listFailure, Fixture.usageSlow], waitsForRows: false)
        defer { diagnostics("groups-list-retry-slow-usage-final") }
        XCTAssertTrue(element("groups.list.failure").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["groups.list.retry"].tap()
        XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription)
        // usage-summary is still out.
        XCTAssertTrue(row(4).label.contains("今日无数据"), row(4).label)
    }

    /// 00 §4.6: a pull while usage-summary is still out reads the list again too.
    @MainActor func testPullReadsListAgainWhileUsageIsSlow() {
        launchAndOpenGroups(arguments: [Fixture.refreshFailure, Fixture.usageSlow])
        defer { diagnostics("groups-list-pull-slow-usage-final") }
        app.pullToRefresh(from: row(4))
        let strip = app.buttons["groups.refresh.retry"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(4).exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in, or the access-token method for `accessToken` (`-ui-readonly-token` makes it read-only); then 搜索 →
    /// 资源 · 分组.
    @MainActor private func launchAndOpenGroups(arguments: [String] = [], accessToken: String? = nil, waitsForRows: Bool = true) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launchQuietly()
        set("分组管理验收", field: "login.name", towardBottom: false)
        set("https://groups-ui.example.invalid", field: "login.url")
        if let accessToken {
            let method = app.buttons["login.method.adminKey"]
            reveal(method); method.tap()
            set(accessToken, field: "login.key")
        } else {
            set("admin@example.com", field: "login.email")
            set("fixture-password", field: "login.password")
        }
        reveal(app.buttons["login.submit"]); app.buttons["login.submit"].tap()
        app.openSearchItem("search.item.groups")
        if waitsForRows { XCTAssertTrue(row(4).waitForExistence(timeout: 10), app.debugDescription) }
    }
    @MainActor private func row(_ id: Int) -> XCUIElement { app.buttons["group.row.\(id)"] }
    /// Each row above the next; the lower one is scrolled between the bars first.
    @MainActor private func assertOrder(_ ids: [Int], file: StaticString = #filePath, line: UInt = #line) {
        for (upper, lower) in zip(ids, ids.dropFirst()) {
            let below = row(lower), above = row(upper)
            app.scrollUntilExists(below, file: file, line: line)
            XCTAssertTrue(above.exists, "group.row.\(upper) missing\n\(app.debugDescription)", file: file, line: line)
            XCTAssertLessThan(above.frame.minY, below.frame.minY, "group.row.\(upper) should come before group.row.\(lower)", file: file, line: line)
        }
    }
    @MainActor private func assertLabel(_ item: XCUIElement, contains parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        app.scrollUntilExists(item, file: file, line: line)
        for part in parts { XCTAssertTrue(item.label.contains(part), "“\(part)” missing in “\(item.label)”", file: file, line: line) }
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    private func deletes(_ count: Int) -> String { String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    /// The sheet's 创建 / 保存 once the form passes.
    @MainActor private func submitEditor() {
        let submit = app.buttons["group-edit.submit"]
        XCTAssertTrue(submit.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        submit.tap()
    }
    @MainActor private func confirmAlert(_ title: String) {
        let button = app.alerts.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription); button.tap()
    }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func set(_ value: String, field id: String, towardBottom: Bool = true) {
        let field = element(id); reveal(field, towardBottom: towardBottom); field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            // The group sheet's inputs are right-aligned (S5-10): the caret goes to the trailing edge, again while text is left.
            for _ in 0..<6 where !(field.value as? String ?? "").isEmpty && field.value as? String != field.placeholderValue {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count))
            }
            XCTAssertTrue((field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue, app.debugDescription)
        }
        field.typeText(value)
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
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    /// S5-06: the detail's ⋯, then an item by title (UIMenu may drop identifiers), apart from the button row's button.
    @MainActor private func tapMoreItem(_ title: String) {
        app.buttons["group.more"].tap()
        let item = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'group.action.')", title)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    /// S5-05: the disable alert's 停用分组.
    @MainActor private func confirmDisable() {
        let button = app.alerts.buttons["停用分组"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription); button.tap()
    }
    /// S5-05: the delete confirmation (Face ID off): 删除分组 only once the whole name is typed.
    @MainActor private func typeDeleteName(_ name: String) {
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input"); input.tap(); input.typeText(name)
        XCTAssertTrue(confirm.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
        confirm.tap()
    }
    @MainActor private func waitForReceipt(_ text: String) {
        let shown = app.staticTexts["receipt.text"].poll(NSPredicate(format: "label == %@", text), timeout: 10)
        XCTAssertTrue(shown, "receipt “\(text)” not shown\n\(app.debugDescription)")
    }

    // MARK: - S5-13 只读令牌、旧服务端与 QA 对账

    /// C-1 on the list: no swipe at all, every long-press write item there but greyed.
    @MainActor func testReadOnlyTokenGreysListWriteEntries() {
        launchAndOpenGroups(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("groups-list-read-only-entries-final") }
        XCTAssertFalse(app.buttons["groups.create"].isEnabled, app.debugDescription)
        let premium = row(1)
        app.scrollUntilExists(premium)
        premium.swipeLeft()
        XCTAssertFalse(swipeButton("edit", titled: "编辑").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(swipeButton("disable", titled: "停用").exists, app.debugDescription)
        leaveDetailIfPushed()
        app.scrollUntilExists(premium)
        premium.swipeRight()
        XCTAssertFalse(swipeButton("addAccounts", titled: "添加账号").waitForExistence(timeout: 2), app.debugDescription)
        // A right swipe the row does not take pops the page (iOS 26 lets it start anywhere).
        if !app.buttons["groups.create"].waitForExistence(timeout: 2) { app.openSearchItem("search.item.groups") }
        leaveDetailIfPushed()
        app.scrollUntilExists(premium)
        premium.press(forDuration: 1.0)
        for title in ["编辑分组", "添加账号", "停用分组…", "复制分组", "删除分组…"] {
            let item = app.buttons[title]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title) missing\n\(app.debugDescription)")
            XCTAssertFalse(item.isEnabled, "\(title)\n\(app.debugDescription)")
        }
    }

    /// 50 §0.1 on a server without F04, the capacity filter, the member batch, D02, today_stats_group and the list query: errors
    /// from the error accounts' group_ids, the local half rule, every section still there.
    @MainActor func testLegacyServerListFallsBackLocally() {
        launchAndOpenGroups(arguments: [Fixture.withoutCapabilities, Self.legacyCapabilities])
        defer { diagnostics("groups-list-legacy-final") }
        waitForLabel(row(4), contains: "错误 1")
        XCTAssertTrue(row(4).label.contains("无可用账号"), row(4).label)
        app.scrollUntilExists(row(2))
        waitForLabel(row(2), contains: "错误 1")
        XCTAssertFalse(row(2).label.contains("可用偏低"), row(2).label)
        let normal = element("groups.section.normal")
        app.scrollUntilExists(normal)
        XCTAssertEqual(normal.label, "正常 5")
        app.scrollUntilExists(element("groups.section.off"))
        XCTAssertEqual(element("groups.section.off").label, "停用 1")
    }

    /// 50 §9: on every row 可用 + 受限 + 错误 + 暂停·停用 = 总数, read from the row's own words (the fixture's buckets).
    @MainActor func testQABucketsAddUpOnEveryRow() {
        launchAndOpenGroups()
        defer { diagnostics("groups-list-qa-buckets-final") }
        for id in [4, 7, 9, 10, 11, 2, 1, 3, 5, 8, 6] {
            let item = row(id)
            app.scrollUntilExists(item)
            let label = item.label
            guard let shown = Self.number(in: label, after: "可用 ", before: " / "), let total = Self.number(in: label, after: " / ") else {
                XCTFail("no availability in “\(label)”"); continue
            }
            let others = ["受限 ", "错误 ", "暂停·停用 "].map { Self.number(in: label, after: $0) ?? 0 }
            XCTAssertEqual(shown + others.reduce(0, +), total, "group.row.\(id): \(label)")
        }
    }

    private static let legacyCapabilities = "groups.account_buckets,groups.capacity_filter,groups.member_batch,accounts.status_summary,"
        + "accounts.today_stats_group,accounts.list_query"
    /// The digits right after `prefix` (and before `suffix` when given) in a row's label.
    private static func number(in label: String, after prefix: String, before suffix: String? = nil) -> Int? {
        let pattern = NSRegularExpression.escapedPattern(for: prefix) + "([0-9,]+)" + (suffix.map(NSRegularExpression.escapedPattern(for:)) ?? "")
        guard let match = label.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = label[match].dropFirst(prefix.count).prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)
        return Int(String(digits))
    }
    /// The left / right swipe's button, by identifier or, where the swipe drops it, by title.
    @MainActor private func swipeButton(_ action: String, titled title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "group.swipe.\(action)", title)).firstMatch
    }
    /// A row without swipe actions may take the swipe as a tap.
    @MainActor private func leaveDetailIfPushed() {
        guard element("group.detail.card").waitForExistence(timeout: 2) else { return }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - U-10 刷新失败保留上次的“今日”与“可用偏低”

    /// S5-高-3: a failed usage refresh keeps 今日 under a second strip, 更新失败 · 重试 naming 今日; tapping it reads again.
    @MainActor func testStaleTodayShowsUpdateFailedStrip() {
        launchAndOpenGroups(arguments: [Fixture.usageFailureAfterFirst])
        defer { diagnostics("groups-list-stale-today-final") }
        waitForLabel(row(7), contains: "今日 $18.40")
        let strip = app.buttons["groups.stale.retry"]
        XCTAssertFalse(strip.exists, app.debugDescription)
        app.pullToRefresh(from: row(4))
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(strip.label.contains("更新失败") && strip.label.contains("今日"), strip.label)
        XCTAssertFalse(strip.label.contains("可用状态"), strip.label)
        XCTAssertTrue(row(7).label.contains("今日 $18.40"), row(7).label)
        // The list itself was read again.
        XCTAssertFalse(element("groups.refresh.retry").exists, app.debugDescription)
        strip.tap()
        // Every read after the first fails: the strip comes back and the amount stays.
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(7).label.contains("今日 $18.40"), row(7).label)
    }

    /// S5-中-8: a failed status-summary refresh keeps D02's judgement, so 标准组 stays 可用偏低 in 需处理 (the local half rule
    /// would move it to 正常), under the strip naming 可用状态.
    @MainActor func testStaleShortageKeepsSection() {
        launchAndOpenGroups(arguments: [Fixture.shortageFailureAfterFirst])
        defer { diagnostics("groups-list-stale-shortage-final") }
        let attention = element("groups.section.attention")
        XCTAssertTrue(attention.poll(NSPredicate(format: "label == %@", "需处理 6"), timeout: 10), attention.label)
        app.pullToRefresh(from: row(4))
        let strip = app.buttons["groups.stale.retry"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(strip.label.contains("更新失败") && strip.label.contains("可用状态"), strip.label)
        XCTAssertFalse(strip.label.contains("今日"), strip.label)
        XCTAssertEqual(attention.label, "需处理 6")
        assertLabel(row(2), contains: ["标准组", "可用偏低"])
        let normal = element("groups.section.normal")
        app.scrollUntilExists(normal)
        XCTAssertEqual(normal.label, "正常 4")
    }
}
