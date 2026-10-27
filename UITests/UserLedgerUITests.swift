import XCTest

/// 30 §4 against the `-ui-testing` fixtures (DemoData+Users): Alice (1) has 24 records of every type, 20 a page, the second
/// page overlapping the first by one row; Bob (2) has none. Entered through the old detail's temporary row (S3-05 keeps its
/// identifier `user.ledger.all`).
final class UserLedgerUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testOpensFromDetailWithHeaderBreakdownAndRows() {
        launchAndLogin()
        defer { diagnostics("user-ledger-rows-final") }
        openLedger()
        XCTAssertTrue(app.navigationBars["充值与调整记录"].staticTexts["Alice"].waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(element("user.ledger.count"), equals: "24 条")
        XCTAssertEqual(element("user.ledger.recharged").label, "总充值 $70.00")
        let breakdown = element("user.ledger.breakdown")
        for text in ["兑换 $40.00 · 管理员 $20.00 · 站点赠送 $10.00", "另有返利转入 $5.00，不计入总充值"] {
            XCTAssertTrue(breakdown.label.contains(text), breakdown.label)
        }
        let redeemed = row(124)
        expect(redeemed, contains: ["余额充值（兑换）", "+$10.00", "10/16 09:20 · 社群活动 · 第 3 批", "兑换码 e81c6a0f 开头"])
        redeemed.tap()
        XCTAssertTrue(app.navigationBars["充值与调整记录"].exists, app.debugDescription)
        expect(row(-7), contains: ["余额充值（返利转入）", "+$5.00"], lacks: ["兑换码"])
        expect(row(121), contains: ["并发增加（兑换）", "+2 并发", "兑换码 c0ffee12 开头"])
        expect(row(118), contains: ["订阅已分配", "企业专线 · 30 天", "兑换码 4e7c0b95 开头"])
        expect(row(116), contains: ["其他记录", "无数据"], lacks: ["兑换码"])
    }

    @MainActor func testPagingLoadsNextPageAndDropsOverlap() {
        launchAndLogin()
        defer { diagnostics("user-ledger-paging-final") }
        openLedger()
        let last = row(101, maxSwipes: 24)
        expect(last, contains: ["余额充值（管理员）", "+$10.00", "09/01 08:00 · 注册赠送"], lacks: ["→"])
        let overlap = row(106, towardBottom: false)
        XCTAssertTrue(overlap.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "user.ledger.row.106").count, 1, app.debugDescription)
        XCTAssertFalse(element("user.ledger.more.loading").exists, app.debugDescription)
        XCTAssertFalse(element("user.ledger.more.retry").exists, app.debugDescription)
        XCTAssertTrue(app.scrollUntilExists(element("user.ledger.row.124"), towardBottom: false, maxSwipes: 24))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "user.ledger.row.124").count, 1, app.debugDescription)
    }

    @MainActor func testAdjustmentLineOnlyOnAdminRowsWithAllLedgerFields() {
        launchAndLogin()
        defer { diagnostics("user-ledger-adjustments-final") }
        openLedger()
        expect(row(124), contains: ["余额充值（兑换）"], lacks: ["→"])
        expect(row(123), contains: ["余额充值（管理员）", "+$20.00", "余额 $12.40 → $32.40 · ops@example.com"])
        expect(row(122), contains: ["余额扣除（管理员）", "\u{2212}$5.00", "余额 $32.40 → $27.40 · ops@example.com"])
        expect(row(120), contains: ["并发增加（管理员）", "+2 并发", "并发 5 → 7 · ops@example.com"])
        expect(row(119), contains: ["并发减少（管理员）", "\u{2212}1 并发", "并发 7 → 6 · ops@example.com"])
        // A migrated row has no before and after.
        expect(row(117), contains: ["余额扣除（管理员）", "\u{2212}$3.00", "旧版调整"], lacks: ["→"])
    }

    @MainActor func testLongPressCopiesOnlyRedeemedCodes() {
        launchAndLogin()
        defer { diagnostics("user-ledger-copy-final") }
        openLedger()
        row(124).press(forDuration: 1.0)
        let copy = app.buttons["复制兑换码"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        copy.tap()
        // The sign-in receipt may still be up; the new one replaces it.
        let receipt = app.staticTexts["receipt.text"]
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "已复制兑换码"), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [copied], timeout: 5), .completed, app.debugDescription)
        for id in [123, -7] {
            row(id).press(forDuration: 1.0)
            XCTAssertFalse(app.buttons["复制兑换码"].waitForExistence(timeout: 2), "\(id)\n\(app.debugDescription)")
        }
    }

    @MainActor func testWithoutBalanceLedgerCapabilityHidesBreakdownAndAdjustmentLines() {
        launchAndLogin(arguments: ["-ui-without-capabilities", "users.balance_ledger"])
        defer { diagnostics("user-ledger-no-ledger-final") }
        openLedger()
        waitForLabel(element("user.ledger.count"), equals: "24 条")
        XCTAssertEqual(element("user.ledger.recharged").label, "总充值 $70.00")
        XCTAssertFalse(element("user.ledger.breakdown").exists, app.debugDescription)
        expect(row(124), contains: ["兑换码 e81c6a0f 开头"])
        expect(row(123), contains: ["余额充值（管理员）", "+$20.00"], lacks: ["→"])
        expect(row(120), contains: ["并发增加（管理员）"], lacks: ["→"])
    }

    @MainActor func testUserWithoutRecordsShowsEmpty() {
        launchAndLogin()
        defer { diagnostics("user-ledger-empty-final") }
        openLedger(userID: 2, name: "Bob")
        let empty = element("user.ledger.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "暂无记录")
        XCTAssertTrue(app.navigationBars["充值与调整记录"].staticTexts["Bob"].waitForExistence(timeout: 5), app.debugDescription)
        for id in ["user.ledger.count", "user.ledger.recharged", "user.ledger.more.loading"] {
            XCTAssertFalse(element(id).exists, "\(id)\n\(app.debugDescription)")
        }
    }

    @MainActor func testFirstPageAndNextPageFailuresRetry() {
        launchAndLogin(arguments: ["-ui-ledger-fail-once", "1,2"])
        defer { diagnostics("user-ledger-failures-final") }
        openLedger()
        XCTAssertTrue(element("user.ledger.error").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("user.ledger.row.124").exists)
        app.buttons["user.ledger.error.retry"].tap()
        XCTAssertTrue(element("user.ledger.row.124").waitForExistence(timeout: 10), app.debugDescription)
        let retry = app.buttons["user.ledger.more.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 24))
        XCTAssertTrue(retry.label.contains("加载更多失败 · 重试"), retry.label)
        XCTAssertTrue(element("user.ledger.row.106").exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(element("user.ledger.row.101")))
        XCTAssertFalse(retry.exists, app.debugDescription)
    }

    @MainActor func testPullToRefreshFailureKeepsRowsAndRetries() {
        launchAndLogin(arguments: ["-ui-ledger-refresh-fail-once"])
        defer { diagnostics("user-ledger-refresh-final") }
        openLedger()
        let first = row(124)
        app.pullToRefresh(from: first)
        let retry = app.buttons["user.ledger.refresh.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        for text in ["刷新失败 · 重试", "更新于"] { XCTAssertTrue(retry.label.contains(text), retry.label) }
        XCTAssertTrue(element("user.ledger.row.124").exists, app.debugDescription)
        XCTAssertEqual(element("user.ledger.count").label, "24 条")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.ledger.row.124").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://users-ledger.example.invalid", in: app.textFields["login.url"])
        enter("充值记录验收", in: app.textFields["login.name"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The user list → the old detail → its last row.
    @MainActor private func openLedger(userID: Int = 1, name: String = "Alice") {
        app.tabBars.buttons["用户"].tap()
        let user = app.buttons["user.\(userID)"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), app.debugDescription)
        user.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
        let entry = app.buttons["user.ledger.all"]
        XCTAssertTrue(app.scrollUntilExists(entry, maxSwipes: 16))
        entry.tap()
        XCTAssertTrue(app.navigationBars["充值与调整记录"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// Scrolls the record into view; rows outside the screen are not in the tree.
    @MainActor private func row(_ id: Int, towardBottom: Bool = true, maxSwipes: Int = 16) -> XCUIElement {
        let item = element("user.ledger.row.\(id)")
        if !item.waitForExistence(timeout: 2) || !item.isHittable {
            app.scrollUntilExists(item, towardBottom: towardBottom, maxSwipes: maxSwipes)
        }
        return item
    }
    @MainActor private func expect(_ item: XCUIElement, contains parts: [String], lacks absent: [String] = [],
                                   file: StaticString = #filePath, line: UInt = #line) {
        for part in parts { XCTAssertTrue(item.label.contains(part), "\(item.label) ∌ \(part)", file: file, line: line) }
        for part in absent { XCTAssertFalse(item.label.contains(part), "\(item.label) ∋ \(part)", file: file, line: line) }
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ≠ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
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
