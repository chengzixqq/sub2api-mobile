import XCTest

/// 30 §1 against the `-ui-testing` fixtures (DemoData+Users): 26 users, 20 a page; the strip's recent 3, 10, 1, 4 and low
/// balances 4, 7, 11, 12; `-ui-users-*` arguments for the states of 30 §1.5.
final class UserListUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testRowsShowBalanceTodayAndThreeMarks() {
        launchAndLogin(arguments: ["-ui-pending-money"])
        defer { diagnostics("users-list-rows-final") }
        openUsers()
        XCTAssertTrue(text(containing: "· 26 位").waitForExistence(timeout: 10), app.debugDescription)
        let legend = element("users.legend")
        XCTAssertTrue(legend.waitForExistence(timeout: 5), app.debugDescription)
        for text in ["余额低", "待核对", "禁用", "余额 / 今日消费"] { XCTAssertTrue(legend.label.contains(text), legend.label) }
        let alice = app.buttons["user.1"]
        for text in ["$12.50", "待核对", "今日 $2.80"] { waitForLabel(alice, contains: text) }
        waitForLabel(app.buttons["user.2"], contains: "今日 $0.00")
        XCTAssertTrue(app.buttons["users.create"].isEnabled)
        XCTAssertFalse(app.buttons["users.fields"].exists)
        XCTAssertFalse(app.buttons["全部状态"].exists)
        for id in [4, 6, 7, 11, 12] {
            let row = app.buttons["user.\(id)"]
            app.scrollUntilExists(row)
            XCTAssertTrue(row.label.contains(id == 6 ? "禁用" : "余额低"), row.label)
        }
        XCTAssertFalse(app.buttons["users.more"].exists)
    }

    @MainActor func testQuickTopupOrderAndTopupSheet() {
        launchAndLogin()
        defer { diagnostics("users-list-quick-final") }
        openUsers()
        XCTAssertTrue(element("users.quick").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("快捷充值").exists, app.debugDescription)
        XCTAssertTrue(text("最近调整 · 余额低").exists, app.debugDescription)
        let wang = app.buttons["users.quick.3"], studio = app.buttons["users.quick.10"], alice = app.buttons["users.quick.1"]
        XCTAssertTrue(wang.frame.minX < studio.frame.minX && studio.frame.minX < alice.frame.minX, app.debugDescription)
        XCTAssertEqual(wang.label, "给王小明充值，余额 $12.40")
        wang.tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("balance.user").label.contains("王小明 · 余额 $12.40"), element("balance.user").label)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("balance.mode").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("users.quick").exists, app.debugDescription)
    }

    @MainActor func testPendingAvatarGoesLastAndOpensDetail() {
        launchAndLogin(arguments: ["-ui-pending-money"])
        defer { diagnostics("users-list-pending-avatar-final") }
        openUsers()
        let alice = app.buttons["users.quick.1"], last = app.buttons["users.quick.12"]
        XCTAssertTrue(alice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(alice.label, "Alice，上一笔退款待核对，打开详情去核对")
        XCTAssertGreaterThan(alice.frame.minX, last.frame.minX)
        for _ in 0..<4 where !alice.isHittable { element("users.quick").swipeLeft() }
        alice.waitUntilSettled()
        alice.tap()
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("balance.mode").exists)
    }

    @MainActor func testSearchHidesStripMatchesNotesAndClears() {
        launchAndLogin()
        defer { diagnostics("users-list-search-final") }
        openUsers()
        XCTAssertTrue(element("users.quick").waitForExistence(timeout: 10), app.debugDescription)
        let field = app.searchFields["邮箱、用户名或备注"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("bob")
        XCTAssertTrue(element("users.quick").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user.2"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user.1"].waitForNonExistence(timeout: 5), app.debugDescription)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "常用测试")
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["user.2"].waitForNonExistence(timeout: 5), app.debugDescription)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "zzz\n")
        XCTAssertTrue(element("users.search.empty").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("users.search.empty").label, "没有匹配“zzz”的用户")
        app.buttons["users.search.clear"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("users.quick").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testScrollLoadsSecondPageWithTodayCosts() {
        launchAndLogin()
        defer { diagnostics("users-list-pages-final") }
        openUsers()
        XCTAssertFalse(app.buttons["user.21"].exists)
        let last = app.buttons["user.26"]
        XCTAssertTrue(app.scrollUntilExists(last, maxSwipes: 16))
        waitForLabel(last, contains: "$45.20")
        waitForLabel(last, contains: "今日 $48.69")
        let first = app.buttons["user.21"]
        app.scrollUntilExists(first, towardBottom: false)
        waitForLabel(first, contains: "今日 $402.10")
        XCTAssertLessThanOrEqual(app.buttons.matching(identifier: "user.20").count, 1)
    }

    @MainActor func testEmptyStateOpensCreateSheet() {
        launchAndLogin(arguments: ["-ui-users-empty"])
        defer { diagnostics("users-list-empty-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(element("users.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("users.empty").label, "还没有用户")
        XCTAssertFalse(element("users.quick").exists)
        let create = app.buttons["users.empty.create"]
        XCTAssertTrue(create.isEnabled)
        create.tap()
        // S3-10: the new user page is pushed.
        XCTAssertTrue(element("user-edit.email").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["新建用户"].exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenShowsTodayDashAndGraysCreate() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("users-list-read-only-final") }
        openUsers()
        waitForLabel(app.buttons["user.1"], contains: "今日无数据")
        XCTAssertFalse(app.buttons["user.1"].label.contains("今日 $"), app.buttons["user.1"].label)
        XCTAssertFalse(app.buttons["users.create"].isEnabled)
        let wang = app.buttons["users.quick.3"]
        XCTAssertTrue(wang.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(wang.isEnabled)
    }

    @MainActor func testReadOnlyTokenEmptyStateButtonHasCaption() {
        launchAndLogin(arguments: ["-ui-readonly-token", "-ui-users-empty"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("users-list-read-only-empty-final") }
        app.tabBars.buttons["用户"].tap()
        let create = app.buttons["users.empty.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(create.isEnabled)
        let caption = element("readonly.caption")
        XCTAssertTrue(caption.exists, app.debugDescription)
        XCTAssertEqual(caption.label, "只读令牌")
    }

    @MainActor func testPullToRefreshFailureKeepsRowsWithBanner() {
        launchAndLogin(arguments: ["-ui-users-refresh-error"])
        defer { diagnostics("users-list-stale-final") }
        openUsers()
        // The 60-second timer counts from the first read, so the fixture's failing second read waits for the pull (30 §1.6).
        XCTAssertFalse(element("users.banner").waitForExistence(timeout: 3), app.debugDescription)
        app.pullToRefresh(from: app.buttons["user.1"])
        XCTAssertTrue(element("users.banner").waitForExistence(timeout: 10), app.debugDescription)
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "刷新失败 · ", "的数据")).firstMatch
        XCTAssertTrue(title.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["users.banner.retry"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["user.1"].exists)
    }

    @MainActor func testFirstLoadShowsSkeletonThenRows() {
        launchAndLogin(arguments: ["-ui-users-slow"])
        defer { diagnostics("users-list-skeleton-final") }
        app.tabBars.buttons["用户"].tap()
        let skeleton = element("users.skeleton")
        XCTAssertTrue(skeleton.waitForExistence(timeout: 3), app.debugDescription)
        // The subtitle names only the site until the first page arrives.
        XCTAssertFalse(text(containing: " 位").exists, app.debugDescription)
        XCTAssertTrue(text(containing: "用户列表验收").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["user.1"].exists)
        XCTAssertFalse(element("users.error").exists)
        XCTAssertFalse(element("users.empty").exists)
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(skeleton.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testLoadFailureAndForbidden() {
        launchAndLogin(arguments: ["-ui-users-error"])
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(element("users.error").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("users.error").label, "加载用户失败")
        XCTAssertTrue(app.buttons["users.error.retry"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["user.1"].exists)
        XCTAssertFalse(element("users.quick").exists)
        diagnostics("users-list-error")
        app.terminate()
        launchAndLogin(arguments: ["-ui-users-forbidden"])
        defer { diagnostics("users-list-forbidden-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(element("users.forbidden").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("users.forbidden").label, "当前身份不能管理用户")
        XCTAssertFalse(element("users.error").exists)
    }

    @MainActor func testUsageFailureOnlyAffectsToday() {
        launchAndLogin(arguments: ["-ui-users-usage-error", "-ui-users-quick-error"])
        defer { diagnostics("users-list-usage-error-final") }
        openUsers()
        let alice = app.buttons["user.1"]
        waitForLabel(alice, contains: "$12.50")
        waitForLabel(alice, contains: "今日无数据")
        XCTAssertFalse(element("users.quick").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(element("users.banner").exists)
        XCTAssertFalse(element("users.error").exists)
    }

    @MainActor func testMissingQuickTopupCapabilityHidesStrip() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "users.quick_topup"])
        defer { diagnostics("users-list-no-strip-final") }
        openUsers()
        waitForLabel(app.buttons["user.1"], contains: "今日 $2.80")
        XCTAssertFalse(element("users.quick").waitForExistence(timeout: 2), app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in, or the access-token method for `accessToken` (a `sat_` key selects it on its own, 60 §4.3), so
    /// `-ui-readonly-token` makes the session read-only.
    @MainActor private func launchAndLogin(arguments: [String] = [], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://users-list.example.invalid", in: app.textFields["login.url"])
        enter("用户列表验收", in: app.textFields["login.name"])
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
    @MainActor private func openUsers() {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard, toward a field already passed or further down, until it can be tapped.
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            let frame = app.frame, keyboard = app.keyboards.firstMatch, bar = app.navigationBars.firstMatch
            let top = max(frame.minY + 100, bar.exists ? bar.frame.maxY + 20 : frame.minY + 100)
            let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            let down = !(item.exists && item.frame.maxY < top)
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
