import XCTest

/// 60 §12 代理列表 on the ProxyFixtures data, newest id first: 8 kr-seoul-1 (链接失败), 7 us-east-2 (expired, unused), 6 de-fra-1
/// (stopped), 5 us-west-3 (never probed), 4 hk-01 (311ms), 3 jp-tokyo-1 (expired, 1 account, failed), 2 sg-01 (96ms), 1 hk-02
/// (182ms, 6 days left, 3 accounts). The app and the helpers are internal so S6-12…S6-14 can add their cases at the end of
/// this class.
final class ProxiesUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    @MainActor func testDirectoryOpensListWithHeaderAndRows() {
        launchProxies()
        defer { diagnostics("proxies-open-final") }
        XCTAssertTrue(element("proxies.list").exists, app.debugDescription)
        XCTAssertTrue(text("代理站点 · 8 个").waitForExistence(timeout: 10), app.debugDescription)
        let header = element("proxies.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(header.label.contains("延迟 / 状态"), header.label)
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        expect(row(8), contains: ["kr-seoul-1", "链接失败", "SOCKS5 · 203.0.113.77:1080", "1 个账号在用"])
        expect(row(7), contains: ["已过期", "没有账号在用"])
        expect(row(6), contains: ["停用", "没有账号在用"])
        XCTAssertFalse(row(6).label.contains("德国"), row(6).label)
        reveal(row(5))
        expect(row(5), contains: ["未测试", "HTTP · 203.0.113.140:8080"])
        reveal(row(3))
        expect(row(3), contains: ["已过期", "1 个账号仍在用", "链接失败"])
        reveal(row(1))
        expect(row(1), contains: ["182ms", "SOCKS5 · 203.0.113.24:1080", "3 个账号在用", "6 天后到期"])
        // S6-14 replaces the placeholder sheet.
        app.buttons["proxies.add"].tap()
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testBannerSummarizesSeveralAndShowOpensExpired() {
        launchProxies()
        defer { diagnostics("proxies-banner-several-final") }
        XCTAssertTrue(text(containing: "2 个代理需要处理").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "jp-tokyo-1 已过期仍在用 · hk-02 6 天后到期").exists, app.debugDescription)
        app.buttons["proxies.banner.show"].tap()
        XCTAssertTrue(waitForSelected(chip("expired")), app.debugDescription)
        XCTAssertTrue(row(3).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(7).exists, app.debugDescription)
        XCTAssertFalse(row(8).exists || row(1).exists, app.debugDescription)
        XCTAssertFalse(element("proxies.banner").exists, app.debugDescription)
    }

    @MainActor func testSingleSoonBannerShowOpensSoon() {
        launchProxies([DemoArgument.soonOnly])
        defer { diagnostics("proxies-banner-soon-final") }
        XCTAssertTrue(text(containing: "hk-02 6 天后到期，3 个账号在用").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text(containing: "到期前续期，或设置到期回退").exists, app.debugDescription)
        XCTAssertNotEqual(chip("expired").value as? String, "有代理已过期仍在用", app.debugDescription)
        app.buttons["proxies.banner.show"].tap()
        XCTAssertTrue(waitForSelected(chip("soon")), app.debugDescription)
        XCTAssertTrue(row(1).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(8).exists || row(3).exists, app.debugDescription)
    }

    @MainActor func testChipsCountFilterAndEmptyFilter() {
        launchProxies()
        defer { diagnostics("proxies-chips-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        for (name, label) in [("all", "全部 8"), ("expired", "已过期 2"), ("soon", "即将到期 1"), ("failed", "链接失败 2"), ("inactive", "停用 1")] {
            XCTAssertEqual(chip(name).label, label, app.debugDescription)
        }
        XCTAssertEqual(chip("expired").value as? String, "有代理已过期仍在用", app.debugDescription)
        XCTAssertTrue(chip("all").isSelected, app.debugDescription)
        tapChip("failed")
        XCTAssertTrue(row(3).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(8).exists, app.debugDescription)
        XCTAssertFalse(row(7).exists || row(1).exists, app.debugDescription)
        tapChip("inactive")
        XCTAssertTrue(row(6).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(8).exists || row(3).exists, app.debugDescription)
        diagnostics("proxies-chips-inactive")
        app.terminate()
        launchProxies([DemoArgument.soonOnly])
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        tapChip("failed")
        let empty = element("proxies.filter-empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(empty.label, "没有这类代理", app.debugDescription)
    }

    @MainActor func testTestAllShowsProgressThenReceipt() {
        launchProxies()
        defer { diagnostics("proxies-test-all-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        let testAll = app.buttons["proxies.testAll"]
        XCTAssertEqual(testAll.label, "全部测试", app.debugDescription)
        testAll.tap()
        XCTAssertTrue(waitForLabel(row(8), containing: "测试中", timeout: 3), row(8).label)
        XCTAssertEqual(testAll.label, "测试中…", app.debugDescription)
        XCTAssertFalse(testAll.isEnabled, app.debugDescription)
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(receipt.label, "已测试 8 个代理 · 3 个失败", app.debugDescription)
        XCTAssertTrue(waitForLabel(testAll, containing: "全部测试"), testAll.label)
        reveal(row(5))
        XCTAssertTrue(row(5).label.contains("244ms"), row(5).label)
        reveal(row(1))
        XCTAssertTrue(row(1).label.contains("176ms"), row(1).label)
    }

    @MainActor func testHTTPErrorDuringTestAllKeepsOldLatency() {
        launchProxies([DemoArgument.testHTTPError])
        defer { diagnostics("proxies-test-http-error-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["proxies.testAll"].tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(receipt.label, "已测试 8 个代理 · 4 个失败", app.debugDescription)
        reveal(row(4))
        XCTAssertTrue(row(4).label.contains("311ms"), row(4).label)
    }

    @MainActor func testPullToRefreshKeepsTestedValues() {
        launchProxies()
        defer { diagnostics("proxies-refresh-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["proxies.testAll"].tap()
        XCTAssertTrue(app.staticTexts["receipt.text"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(waitForLabel(app.buttons["proxies.testAll"], containing: "全部测试"), app.debugDescription)
        app.pullToRefresh(from: row(8))
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(5))
        XCTAssertTrue(waitForLabel(row(5), containing: "244ms"), row(5).label)
        reveal(row(1))
        XCTAssertTrue(row(1).label.contains("176ms"), row(1).label)
    }

    @MainActor func testReadOnlyTokenHidesTestAllAndAdd() {
        launchProxies(readOnlyToken: true)
        defer { diagnostics("proxies-readonly-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("代理站点 · 8 个").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["proxies.testAll"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["proxies.add"].exists, app.debugDescription)
    }

    @MainActor func testEmptyStateAddOpensSheet() {
        launchProxies([DemoArgument.empty])
        defer { diagnostics("proxies-empty-final") }
        let empty = element("proxies.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(empty.label.contains("还没有代理"), empty.label)
        app.buttons["proxies.empty.add"].tap()
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testLoadFailureShowsFailureView() {
        launchProxies([DemoArgument.listError])
        defer { diagnostics("proxies-failure-final") }
        XCTAssertTrue(element("proxies.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["暂时无法加载"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["重试"].exists, app.debugDescription)
        XCTAssertFalse(row(8).exists, app.debugDescription)
    }

    /// 00 §2.7.2: the first read answers 429 (retry_after 6): the failure names the wait and offers no 重试, then the list reads
    /// by itself.
    @MainActor func testRateLimitedLoadWaitsThenReadsByItself() {
        launchProxies([DemoArgument.throttled])
        defer { diagnostics("proxies-throttled-final") }
        XCTAssertTrue(element("proxies.failure").waitForExistence(timeout: 10), app.debugDescription)
        let notice = text(containing: "请求过于频繁，")
        XCTAssertTrue(notice.exists && notice.label.hasSuffix("秒后自动重试"), app.debugDescription)
        XCTAssertFalse(app.buttons["重试"].exists, app.debugDescription)
        diagnostics("proxies-throttled")
        XCTAssertTrue(row(8).waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(element("proxies.failure").exists, app.debugDescription)
    }

    @MainActor func testLaterPageFailureKeepsRowsAndRetries() {
        launchProxies([DemoArgument.secondPageError])
        defer { diagnostics("proxies-page2-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        for id in [7, 6] { XCTAssertTrue(row(id).exists, "\(id)\n\(app.debugDescription)") }
        let retry = app.buttons["proxies.more-failure"]
        reveal(retry)
        XCTAssertTrue(row(5).exists, app.debugDescription)
        XCTAssertFalse(row(4).exists || row(1).exists, app.debugDescription)
        XCTAssertEqual(retry.label, "加载失败 · 重试", app.debugDescription)
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10), app.debugDescription)
        reveal(row(1))
        XCTAssertTrue(row(1).exists, app.debugDescription)
    }

    @MainActor func testRowOpensProxyDetail() {
        launchProxies()
        defer { diagnostics("proxies-detail-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(1))
        row(1).tap()
        // S6-12 replaces the placeholder with the detail.
        XCTAssertTrue(app.navigationBars["代理详情"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("route.placeholder").exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// The ProxyFixtures launch arguments.
    enum DemoArgument {
        static let empty = "-ui-proxies-empty"
        static let soonOnly = "-ui-proxies-soon-only"
        static let listError = "-ui-proxies-error"
        static let secondPageError = "-ui-proxies-page2-error"
        static let testHTTPError = "-ui-proxies-test-http-error"
        static let throttled = "-ui-proxies-throttled"
    }

    @MainActor func launchProxies(_ arguments: [String] = [], readOnlyToken: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + (readOnlyToken ? ["-ui-readonly-token"] : [])
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://proxies.example.invalid", in: app.textFields["login.url"])
        enter("代理站点", in: app.textFields["login.name"])
        if readOnlyToken {
            tap(app.buttons["login.method.adminKey"])
            enter("sat_ui-fixture", in: app.secureTextFields["login.key"])
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
        app.openSearchItem("search.item.proxies")
        XCTAssertTrue(app.navigationBars["代理"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func row(_ id: Int) -> XCUIElement { app.buttons["proxy.row.\(id)"] }
    @MainActor func chip(_ filter: String) -> XCUIElement { app.buttons["proxies.chip.\(filter)"] }
    /// The capsules scroll sideways; the last ones may start off screen.
    @MainActor func tapChip(_ filter: String) {
        let item = chip(filter)
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<3 where !item.isHittable { chip("all").swipeLeft() }
        item.tap()
        XCTAssertTrue(waitForSelected(item), app.debugDescription)
    }
    @MainActor func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    @MainActor func text(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    /// A list row: scrolled between the bars (UITestNavigation).
    @MainActor func reveal(_ item: XCUIElement, down: Bool = true) { app.scrollUntilExists(item, towardBottom: down) }
    @MainActor func expect(_ item: XCUIElement, contains parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        for part in parts { XCTAssertTrue(item.label.contains(part), "\(item.label) ∌ \(part)", file: file, line: line) }
    }
    @MainActor func waitForLabel(_ item: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor func waitForSelected(_ item: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor private func tap(_ item: XCUIElement) { revealLoginField(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard, toward a field already passed or further down, until it can be tapped.
    @MainActor private func revealLoginField(_ item: XCUIElement) {
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
}
