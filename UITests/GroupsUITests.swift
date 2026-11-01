import XCTest

/// 50 §1 (S5-04): the group list on the `-ui-testing` site — eleven groups whose buckets are counted from the demo accounts
/// (GroupFixtures). Timed windows run an hour longer so GLM 组's overload holds for the whole test. Creating, editing and
/// deleting still go through the old editor and detail, entered from the new list.
final class GroupsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let listFailure = "-ui-group-list-failure"
        static let refreshFailure = "-ui-group-refresh-failure"
        static let usageFailure = "-ui-group-usage-failure"
        static let usageSlow = "-ui-group-usage-slow"
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
        XCTAssertTrue(element("group-editor.name").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["创建分组"].exists, app.debugDescription)
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
        set("移动分组", field: "group-editor.name", towardBottom: false)
        set("iPhone 管理", field: "group-editor.description")
        set("1.25", field: "group-editor.rate")
        set("90", field: "group-editor.rpm")
        confirmEditor()
        // A new group has no account yet: 需处理, “没有账号”.
        let created = row(12)
        XCTAssertTrue(created.waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(created)
        XCTAssertTrue(created.label.contains("没有账号"), created.label)
        XCTAssertGreaterThan(created.frame.minY, element("groups.section.attention").frame.minY)
        created.tap()
        reveal(app.buttons["group.menu.edit"])
        app.buttons["group.menu.edit"].tap()
        set("移动分组更新", field: "group-editor.name", towardBottom: false)
        set("仅修改描述与名称", field: "group-editor.description")
        confirmEditor()
        // An Any query by the new title also matches the editor TextField's
        // value while the sheet is dismissing. Wait for the destination bar.
        XCTAssertTrue(app.navigationBars["移动分组更新"].waitForExistence(timeout: 10), app.debugDescription)
        // S5-05: 停用分组… asks first, then says so in a receipt.
        reveal(app.buttons["group.menu.disable"])
        app.buttons["group.menu.disable"].tap()
        confirmDisable()
        waitForReceipt("已停用「移动分组更新」")
        XCTAssertTrue(app.buttons["group.menu.enable"].waitForExistence(timeout: 5), app.debugDescription)
        diagnostics("group-edit-and-status-success")
        reveal(app.buttons["group.menu.delete"])
        app.buttons["group.menu.delete"].tap()
        typeDeleteName("移动分组更新")
        waitForReceipt("已删除分组「移动分组更新」")
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(created.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(4).exists, app.debugDescription)
    }

    @MainActor func testGroupValidationAndStatisticsNavigation() {
        launchAndOpenGroups()
        defer { diagnostics("group-validation-navigation-final") }
        app.buttons["groups.create"].tap()
        reveal(app.buttons["group-editor.prepare"])
        app.buttons["group-editor.prepare"].tap()
        reveal(element("group-editor.result"))
        XCTAssertTrue(element("group-editor.result").label.contains("名称"), app.debugDescription)
        set("验证分组", field: "group-editor.name", towardBottom: false)
        set("0", field: "group-editor.rate")
        reveal(app.buttons["group-editor.prepare"])
        app.buttons["group-editor.prepare"].tap()
        reveal(element("group-editor.result"))
        XCTAssertTrue(element("group-editor.result").label.contains("倍率"), app.debugDescription)
        app.buttons["group-editor.close"].tap()
        let premium = row(1)
        app.scrollUntilExists(premium)
        premium.tap()
        reveal(app.buttons["group.analytics"])
        app.buttons["group.analytics"].tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
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
    @MainActor private func confirmEditor() {
        reveal(app.buttons["group-editor.prepare"]); app.buttons["group-editor.prepare"].tap()
        confirmDialog()
    }
    @MainActor private func confirmDialog() {
        let button = app.buttons["确认发送"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription); button.tap()
    }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func set(_ value: String, field id: String, towardBottom: Bool = true) {
        let field = element(id); reveal(field, towardBottom: towardBottom); field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
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
}
