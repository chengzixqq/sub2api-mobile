import XCTest

/// S6-21: the global search's results and its “查看全部” page (60 §2) over SearchFixtures' table of queries.
final class GlobalSearchUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testTypingShowsSearchingRowsThenSections() {
        launch(arguments: ["-ui-search-slow"])
        defer { diagnostics("search-sections-final") }
        search("de")
        XCTAssertTrue(element("search.section.accounts.loading").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("search.section.users.loading").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["search.item.usage"].exists)
        diagnostics("search-searching")
        XCTAssertTrue(app.buttons["search.account.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("search.section.accounts").value as? String, "4")
        XCTAssertFalse(element("search.section.accounts.loading").exists)
        XCTAssertFalse(app.buttons["search.section.accounts.all"].exists)
        app.scrollUntilExists(app.buttons["search.proxy.6"])
        XCTAssertTrue(app.buttons["search.user.23"].exists || app.buttons["search.group.5"].exists, app.debugDescription)
        // “de” does not look like a request ID: no request block (60 §2.2).
        XCTAssertFalse(element("search.section.requests").exists)
    }

    @MainActor func testShortQueryDoesNotSearch() {
        launch()
        defer { diagnostics("search-short-final") }
        search("a")
        XCTAssertTrue(element("search.hint.short").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element("search.results").exists)
        XCTAssertFalse(element("search.section.users.loading").exists)
        app.searchFields["搜索全部对象"].typeText("b")
        XCTAssertTrue(app.buttons["search.user.24"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("search.hint.short").exists)
    }

    @MainActor func testBadgesNotesAndViewAll() {
        launch()
        defer { diagnostics("search-badges-final") }
        search("测试")
        let all = app.buttons["search.section.users.all"]
        XCTAssertTrue(app.buttons["search.user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("search.section.users").value as? String, "9")
        app.scrollUntilExists(all)
        XCTAssertEqual(all.label, "查看全部 9 个")
        app.scrollUntilExists(app.buttons["search.group.6"])
        XCTAssertTrue(app.buttons["search.group.6"].label.contains("停用"), app.buttons["search.group.6"].label)

        search("zhao")
        let disabled = app.buttons["search.user.6"]
        XCTAssertTrue(disabled.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(disabled.label.contains("禁用"), disabled.label)
        XCTAssertFalse(disabled.label.contains("Key 片段匹配"), disabled.label)

        search("k301x9")
        let byKey = app.buttons["search.user.3"]
        XCTAssertTrue(byKey.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(byKey.label.contains("Key 片段匹配"), byKey.label)
    }

    @MainActor func testRequestIDShowsRequestsAndCap() {
        launch()
        defer { diagnostics("search-requests-final") }
        search("req-search-1040")
        let usage = app.buttons["search.usage.1040"]
        XCTAssertTrue(usage.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["search.error.2006"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("search.section.requests").value as? String, "2")
        XCTAssertFalse(element("search.section.requests.capped").exists)
        usage.tap()
        XCTAssertTrue(app.navigationBars["请求详情"].waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(usage.waitForExistence(timeout: 5), app.debugDescription)

        search("req-search-capped")
        XCTAssertTrue(app.buttons["search.usage.1040"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("search.section.requests").value as? String, "20")
        app.scrollUntilExists(element("search.section.requests.capped"))
        XCTAssertEqual(element("search.section.requests.capped").label, "只显示前 20 条")
    }

    @MainActor func testViewAllPagesWithinSearchTab() {
        launch(arguments: ["-ui-search-list-page2-fail-once"])
        defer { diagnostics("search-view-all-final") }
        search("example")
        let all = app.buttons["search.section.users.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(all.label, "查看全部 26 个")
        app.scrollUntilExists(all)
        all.tap()
        XCTAssertTrue(app.navigationBars["用户"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["search.list.user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["搜索“example” · 26 个"].exists, app.debugDescription)
        // Still the search tab's own stack (60 §2.1).
        XCTAssertFalse(app.tabBars.buttons["用户"].isSelected)
        app.scrollUntilExists(app.buttons["search.list.more.retry"])
        app.buttons["search.list.more.retry"].tap()
        app.scrollUntilExists(app.buttons["search.list.user.26"])
        goBack()
        XCTAssertTrue(all.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.searchFields["搜索全部对象"].value as? String, "example")
    }

    @MainActor func testSingleSectionFailureRetriesOnlyThatSection() {
        launch(arguments: ["-ui-search-fail-once=users"])
        defer { diagnostics("search-section-failure-final") }
        search("de")
        let retry = app.buttons["search.section.users.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(retry.label, "这一类暂时搜不到 · 重试")
        XCTAssertTrue(app.buttons["search.account.1"].exists, app.debugDescription)
        app.scrollUntilExists(retry)
        retry.tap()
        XCTAssertTrue(app.buttons["search.user.23"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(retry.exists)
    }

    @MainActor func testAllSectionsFailedShowsFailureView() {
        launch(arguments: ["-ui-search-fail-once=all"])
        defer { diagnostics("search-all-failed-final") }
        search("de")
        XCTAssertTrue(app.staticTexts["暂时无法加载"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("search.results").exists)
        app.buttons["重试"].tap()
        XCTAssertTrue(app.buttons["search.account.1"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testNoMatchShowsEmptyStateAndClearSearch() {
        launch()
        defer { diagnostics("search-empty-final") }
        search("zzqq")
        let empty = element("search.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "没有匹配“zzqq”的账号、用户、分组、代理或请求")
        app.buttons["search.empty.clear"].tap()
        XCTAssertTrue(app.buttons["search.item.usage"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(app.searchFields["搜索全部对象"].value as? String, "zzqq")
    }

    @MainActor func testRowsOpenDetailsInSearchTab() {
        launch()
        defer { diagnostics("search-rows-final") }
        search("de")
        let account = app.buttons["search.account.1"]
        XCTAssertTrue(account.waitForExistence(timeout: 10), app.debugDescription)
        account.tap()
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.tabBars.buttons["账号"].isSelected)
        goBack()
        open("search.proxy.6", expecting: "de-fra-1")
        open("search.user.23", expecting: "深蓝 AI")
        let group = app.buttons["search.group.5"]
        app.scrollUntilExists(group)
        group.tap()
        XCTAssertTrue(element("search.results").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("搜索站点", in: "login.name")
        enter("https://search.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchTab()
    }
    /// Replaces the field's text, then 搜索 on the keyboard puts the keyboard away so the rows are reachable.
    @MainActor private func search(_ text: String) {
        let field = app.searchFields["搜索全部对象"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        let clear = field.buttons.firstMatch
        if clear.exists { clear.tap() }
        field.typeText(text)
        if text.count >= 2 { field.typeText("\n") }
    }
    /// Opens a result row and comes back to the results.
    @MainActor private func open(_ identifier: String, expecting title: String) {
        let row = app.buttons[identifier]
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15)))
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
