import XCTest

/// 60 §15 公告列表 on the AnnouncementFixtures data: 31 / 30 / 33 / 32 展示中, 29 草稿, 27 / 24 / 21 已归档. The app and the
/// helpers are internal so S6-17…S6-19 can add their cases in extensions or at the end of this class.
final class AnnouncementsUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    @MainActor func testDirectoryOpensListWithSubtitleAndSegments() {
        launchAnnouncements()
        defer { diagnostics("announcements-open-final") }
        XCTAssertTrue(element("announcements.list").exists, app.debugDescription)
        XCTAssertTrue(text("公告站点 · 8 条").waitForExistence(timeout: 10), app.debugDescription)
        for title in ["全部 8", "展示中 4", "草稿 1", "已归档 3"] {
            XCTAssertTrue(segmentButton(labeled: title).waitForExistence(timeout: 10), "\(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(segment("全部").isSelected, app.debugDescription)
        XCTAssertTrue(app.buttons["announcements.compose"].exists, app.debugDescription)
    }

    @MainActor func testRowsShowTargetScheduleAndStatus() {
        launchAnnouncements()
        defer { diagnostics("announcements-rows-final") }
        let maintenance = row(31)
        XCTAssertTrue(maintenance.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["10 月 18 日凌晨维护通知", "展示中", "所有用户", "弹窗 · "] {
            XCTAssertTrue(maintenance.label.contains(part), "\(maintenance.label) ∌ \(part)")
        }
        XCTAssertTrue(waitForLabel(row(30), containing: "订阅 企业专线"), row(30).label)
        XCTAssertTrue(row(30).label.contains("静默 · 立即 – 永久"), row(30).label)
        XCTAssertTrue(row(33).label.contains("（未开始）") && row(33).label.contains("余额 ≥ $10.00"), row(33).label)
        reveal(row(32))
        XCTAssertTrue(row(32).label.contains("（已结束）") && row(32).label.contains("订阅 分组 #99"), row(32).label)
        reveal(row(21))
        XCTAssertTrue(row(24).label.contains(" 且 ") && row(24).label.contains(" 或 "), row(24).label)
        XCTAssertTrue(row(24).label.contains("已归档"), row(24).label)
        XCTAssertTrue(row(21).label.contains("订阅 高级组、企业专线"), row(21).label)
    }

    @MainActor func testSegmentSwitchFiltersRows() {
        launchAnnouncements()
        defer { diagnostics("announcements-segments-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        segment("草稿").tap()
        XCTAssertTrue(row(29).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(31).exists, app.debugDescription)
        for part in ["余额不足提醒", "草稿", "余额 < $5.00", "弹窗 · 更新于"] {
            XCTAssertTrue(row(29).label.contains(part), "\(row(29).label) ∌ \(part)")
        }
        segment("已归档").tap()
        XCTAssertTrue(row(27).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(24).exists && row(21).exists, app.debugDescription)
        XCTAssertFalse(row(31).exists || row(29).exists, app.debugDescription)
        segment("全部").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(29).exists, app.debugDescription)
    }

    @MainActor func testReadProgressShownWithCapabilityAndNeverOnDrafts() {
        launchAnnouncements()
        defer { diagnostics("announcements-read-progress-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(31).label.contains("已读 410/1,036"), row(31).label)
        XCTAssertTrue(row(30).label.contains("已读 12/38"), row(30).label)
        segment("草稿").tap()
        XCTAssertTrue(row(29).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(29).label.contains("已读"), row(29).label)
    }

    @MainActor func testReadProgressHiddenWithoutCapability() {
        launchAnnouncements(["-ui-without-capabilities", "announcements.read_stats"])
        defer { diagnostics("announcements-no-read-stats-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(31).label.contains("所有用户") && row(31).label.contains("展示中"), row(31).label)
        XCTAssertFalse(row(31).label.contains("已读"), row(31).label)
        XCTAssertFalse(row(30).label.contains("已读"), row(30).label)
    }

    @MainActor func testEmptySegmentShowsNoSuchAnnouncements() {
        launchAnnouncements(["-ui-announcements-no-archived"])
        defer { diagnostics("announcements-empty-segment-final") }
        XCTAssertTrue(segmentButton(labeled: "已归档 0").waitForExistence(timeout: 10), app.debugDescription)
        segment("已归档").tap()
        let empty = element("announcements.segment.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(empty.label.contains("没有这类公告"), empty.label)
        XCTAssertFalse(element("announcements.empty").exists, app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "全部 5").exists, app.debugDescription)
        segment("全部").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testNoAnnouncementsShowsCreateEntry() {
        launchAnnouncements(["-ui-announcements-empty"])
        defer { diagnostics("announcements-empty-final") }
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["还没有公告"].exists, app.debugDescription)
        let create = app.buttons["announcements.empty.create"]
        XCTAssertTrue(create.exists && create.label == "新建公告", app.debugDescription)
        create.tap()
        // S6-18 replaces the placeholder sheet.
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testComposeOpensNewAnnouncementSheet() {
        launchAnnouncements()
        defer { diagnostics("announcements-compose-final") }
        app.buttons["announcements.compose"].tap()
        // S6-18 replaces the placeholder sheet.
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenHidesCompose() {
        launchAnnouncements(readOnlyToken: true)
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.compose"].exists, app.debugDescription)
        diagnostics("announcements-readonly-list")
        app.terminate()
        launchAnnouncements(["-ui-announcements-empty"], readOnlyToken: true)
        defer { diagnostics("announcements-readonly-empty-final") }
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.empty.create"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.compose"].exists, app.debugDescription)
    }

    @MainActor func testFailureThenRetry() {
        launchAnnouncements(["-ui-announcements-error"])
        defer { diagnostics("announcements-failure-final") }
        XCTAssertTrue(element("announcements.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["暂时无法加载"].exists, app.debugDescription)
        app.buttons["重试"].tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("announcements.failure").exists, app.debugDescription)
    }

    @MainActor func testCountsFailureShowsSegmentNamesOnly() {
        launchAnnouncements(["-ui-announcements-counts-error"])
        defer { diagnostics("announcements-counts-failure-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        let labels = app.segmentedControls["announcements.segment"].buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["全部", "展示中", "草稿", "已归档"], app.debugDescription)
        XCTAssertTrue(text("公告站点 · 8 条").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testScrollingLoadsNextPageAndRetries() {
        launchAnnouncements(["-ui-announcements-many", "-ui-announcements-page-error"])
        defer { diagnostics("announcements-next-page-final") }
        XCTAssertTrue(segmentButton(labeled: "全部 33").waitForExistence(timeout: 10), app.debugDescription)
        let retry = app.buttons["announcements.more.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 16))
        XCTAssertEqual(retry.label, "加载失败 · 重试")
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(row(101), maxSwipes: 16))
        XCTAssertTrue(row(101).label.contains("历史公告 1"), row(101).label)
        XCTAssertFalse(retry.exists, app.debugDescription)
    }

    @MainActor func testRowPushesDetailRoute() {
        launchAnnouncements()
        defer { diagnostics("announcements-push-final") }
        segment("展示中").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        row(31).tap()
        // S6-17 replaces the placeholder detail.
        XCTAssertTrue(app.navigationBars["公告详情"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment("展示中").isSelected, app.debugDescription)
        XCTAssertFalse(row(29).exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to “公告站点” (an access token with `readOnlyToken`, so `-ui-readonly-token` makes it read-only) and opens 公告
    /// from the search tab's directory.
    @MainActor func launchAnnouncements(_ arguments: [String] = [], readOnlyToken: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + (readOnlyToken ? ["-ui-readonly-token"] : [])
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://announcements.example.invalid", in: app.textFields["login.url"])
        enter("公告站点", in: app.textFields["login.name"])
        if readOnlyToken {
            tap(app.buttons["login.method.adminKey"])
            enter("sat_fixture-readonly", in: app.secureTextFields["login.key"])
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
        app.openSearchItem("search.item.announcements")
        XCTAssertTrue(app.navigationBars["公告"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func row(_ id: Int) -> XCUIElement { app.buttons["announcement.row.\(id)"] }
    /// A segment by the start of its title (“全部 8” or only “全部” when its count failed).
    @MainActor func segment(_ title: String) -> XCUIElement {
        app.segmentedControls["announcements.segment"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    @MainActor func segmentButton(labeled label: String) -> XCUIElement {
        app.segmentedControls["announcements.segment"].buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    /// A list row: scrolled between the bars (UITestNavigation).
    @MainActor func reveal(_ item: XCUIElement, down: Bool = true) { app.scrollUntilExists(item, towardBottom: down) }
    @MainActor func waitForLabel(_ item: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
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
