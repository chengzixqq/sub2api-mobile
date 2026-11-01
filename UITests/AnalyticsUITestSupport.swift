import XCTest

/// S4-13: what the analytics UI test classes share (AnalyticsUITests, then S4-15's AnalyticsRankUITests, S4-17's
/// AnalyticsMoreUITests and S4-19): sign in on the `-ui-testing` fixtures, open 统计分析 from the search directory or an overview
/// entry, find elements, wait for a label or a value, pick a range segment. The names are fixed (S4D2b-16 ①); each class keeps
/// only its own helpers.
extension XCUIApplication {
    /// Launches with `-ui-testing` and `arguments` (or, with `launch: false`, adds a site from the running app's login page), signs
    /// in with email and password, and waits for the tabs.
    @MainActor func signInForAnalytics(name: String = "统计测试", url: String = "https://analysis.example.invalid", arguments: [String] = [],
                                       launch: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        if launch {
            launchArguments = ["-ui-testing"] + arguments
            launchQuietly()
        }
        XCTAssertTrue(analyticsElement("login.name").waitForExistence(timeout: 10), debugDescription, file: file, line: line)
        enterForAnalytics(name, in: "login.name")
        enterForAnalytics(url, in: "login.url")
        enterForAnalytics("admin@example.com", in: "login.email")
        enterForAnalytics("fixture-password", in: "login.password")
        let submit = buttons["login.submit"]
        revealForAnalytics(submit)
        submit.tap()
        XCTAssertTrue(tabBars.buttons["概览"].waitForExistence(timeout: 10), debugDescription, file: file, line: line)
    }

    /// 搜索 → 资源 · 统计分析 (`.analytics(range: .last7)`), once its billing card has an answer.
    @MainActor func openAnalyticsFromSearch(file: StaticString = #filePath, line: UInt = #line) {
        openSearchItem("search.item.analytics", file: file, line: line)
        waitForAnalytics(file: file, line: line)
    }

    /// 概览 → one of its entries (`home.ticker.<kind>`, `home.today.more`): `.analytics()`, today unless the site remembers a range.
    @MainActor func openAnalyticsFromOverview(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        tabBars.buttons["概览"].tap()
        // The cells are disabled skeletons until the first load; rows further down the list exist once scrolled to.
        let loaded = NSPredicate(format: "isEnabled == true")
        XCTAssertTrue(analyticsElement("home.ticker.actualCost").poll(loaded, timeout: 10), debugDescription, file: file, line: line)
        let entry = analyticsElement(identifier)
        scrollUntilExists(entry, file: file, line: line)
        XCTAssertTrue(entry.poll(loaded, timeout: 10), debugDescription, file: file, line: line)
        entry.tap()
        waitForAnalytics(file: file, line: line)
    }

    @MainActor func analyticsElement(_ identifier: String) -> XCUIElement { descendants(matching: .any)[identifier].firstMatch }

    @MainActor @discardableResult
    func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let shown = element.poll(NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
        XCTAssertTrue(shown, "\(element) label should contain “\(text)”\n\(debugDescription)", file: file, line: line)
        return shown
    }

    @MainActor @discardableResult
    func waitForValue(_ element: XCUIElement, equal value: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let shown = element.poll(NSPredicate(format: "value == %@", value), timeout: timeout)
        XCTAssertTrue(shown, "\(element) value should be “\(value)”, is “\(element.value as? String ?? "nil")”\n\(debugDescription)",
                      file: file, line: line)
        return shown
    }

    /// 今天 · 7 天 · 30 天 · 自定义 on the range bar.
    @MainActor func selectRangeSegment(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = rangeSegment(title)
        XCTAssertTrue(button.waitForExistence(timeout: 10), debugDescription, file: file, line: line)
        button.tap()
    }

    @MainActor func rangeSegment(_ title: String) -> XCUIElement {
        segmentedControls["analytics.range.segment"].buttons[title].firstMatch
    }

    // MARK: Private

    @MainActor private func waitForAnalytics(file: StaticString, line: UInt) {
        XCTAssertTrue(navigationBars["统计分析"].waitForExistence(timeout: 10), debugDescription, file: file, line: line)
        let amount = analyticsElement("analytics.billing.amount")
        let failure = analyticsElement("analytics.billing.failure")
        XCTAssertTrue(amount.waitForExistence(timeout: 10) || failure.exists, debugDescription, file: file, line: line)
    }

    @MainActor private func enterForAnalytics(_ value: String, in identifier: String) {
        let field = analyticsElement(identifier)
        revealForAnalytics(field)
        field.tap()
        field.typeText(value)
    }

    /// The login form scrolls under the keyboard; drags it until `item` is hittable.
    @MainActor private func revealForAnalytics(_ item: XCUIElement) {
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            let top = max(frame.minY + 100, navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, keyboards.firstMatch.exists ? keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15)))
        }
    }
}
