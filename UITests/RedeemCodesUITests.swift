import XCTest

/// 60 §8 兑换码列表 on the RedeemFixtures data (“兑换码站点”): today 2046 / 2045 unused and 2044 used by 王小明 (the batch
/// 社群活动 · 第 3 批), yesterday 2038 (企业专线 · 30 天) and 2036 (Studio-K 团队), earlier 2031, 2027, 2019 (expired), 2015
/// (disabled), 2012 (subscription, group from the directory), 2008 (user missing) and the admin row 2005 an old server returns.
/// Eleven codes, 4 unused / 5 used / 1 expired / 1 disabled. The app and the helpers are internal so S6-05 can add its cases
/// in an extension (S6D1-10).
final class RedeemCodesUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    @MainActor func testDirectoryOpensListWithSubtitleAndChipCounts() {
        launchRedeem()
        defer { diagnostics("redeem-open-final") }
        XCTAssertTrue(element("redeem.list").exists, app.debugDescription)
        XCTAssertTrue(text("兑换码站点 · 11 个").waitForExistence(timeout: 10), app.debugDescription)
        for (key, title) in [("all", "全部 11"), ("unused", "未使用 4"), ("used", "已使用 5"), ("expired", "已过期 1"), ("disabled", "已禁用 1")] {
            XCTAssertTrue(waitForLabel(chip(key), equalTo: title), "\(chip(key).label) ≠ \(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(chip("all").isSelected, app.debugDescription)
        XCTAssertEqual(app.buttons["redeem.type"].label, "类型")
        XCTAssertTrue(app.buttons["redeem.generate"].exists, app.debugDescription)
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("redeem.section.今天生成").exists && element("redeem.section.昨天生成").exists, app.debugDescription)
        for part in ["兑换码结尾 d4e8", "$10.00", "余额 · ", " 过期", "未使用"] { XCTAssertTrue(card(2046).label.contains(part), "\(card(2046).label) ∌ \(part)") }
        XCTAssertTrue(card(2044).label.contains("余额 · 王小明 · "), card(2044).label)
        XCTAssertTrue(card(2038).label.contains("30 天") && card(2038).label.contains("企业专线 · "), card(2038).label)
        diagnostics("redeem-open")
    }

    @MainActor func testStatusChipAndTypeMenuNarrowTheList() {
        launchRedeem()
        defer { diagnostics("redeem-filters-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        chip("used").tap()
        XCTAssertTrue(card(2044).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card(2046).waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(chip("used").isSelected, app.debugDescription)
        pickType("订阅")
        XCTAssertTrue(card(2012).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card(2044).waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(card(2038).exists, app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 2") && waitForLabel(chip("unused"), equalTo: "未使用 1"), app.debugDescription)
        XCTAssertEqual(app.buttons["redeem.type"].label, "订阅")
        // The group comes from the directory when the row has none.
        XCTAssertTrue(waitForLabel(card(2012), containing: "企业专线 · 林一"), card(2012).label)
        pickType("全部类型")
        XCTAssertTrue(card(2036).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 11"), app.debugDescription)
        chip("disabled").tap()
        XCTAssertTrue(card(2015).waitForExistence(timeout: 10), app.debugDescription)
        pickType("邀请码")
        XCTAssertTrue(text("没有这类兑换码").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("redeem.search.clear").exists, app.debugDescription)
    }

    @MainActor func testSearchMatchesCodeOrEmailAndClears() {
        launchRedeem()
        defer { diagnostics("redeem-search-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        search("studio-k")
        XCTAssertTrue(card(2036).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card(2046).waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 1"), app.debugDescription)
        search("9c1e7b", replacing: true)
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(card(2045).exists, app.debugDescription)
        search("zzz", replacing: true)
        XCTAssertTrue(text("没有匹配“zzz”的兑换码").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["redeem.search.clear"].tap()
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card(2045).exists, app.debugDescription)
    }

    @MainActor func testOnlyOneCardOpensAndCodeIsMasked() {
        launchRedeem()
        defer { diagnostics("redeem-open-one-final") }
        open(2046)
        XCTAssertEqual(boxText(2046).label, "兑换码已遮罩，结尾 d4e8")
        XCTAssertEqual(card(2046).value as? String, "已展开")
        for part in ["生成时间", "过期时间", "还剩 7 天", "社群活动 · 第 3 批"] {
            XCTAssertTrue(labelled(containing: part, in: element("redeem.card.2046.body")).exists, part + "\n" + app.debugDescription)
        }
        XCTAssertFalse(element("redeem.card.2046.user").exists, app.debugDescription)
        open(2045)
        XCTAssertTrue(element("redeem.card.2046.body").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(card(2046).value as? String, "已收起")
        card(2045).tap()
        XCTAssertTrue(element("redeem.card.2045.body").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testRevealAndCopyShowReceipt() {
        launchRedeem()
        defer { diagnostics("redeem-copy-final") }
        open(2046)
        app.buttons["redeem.card.2046.box.reveal"].tap()
        XCTAssertTrue(waitForLabel(boxText(2046), equalTo: "a3f09c1e7b2d44af90c1e3b75b20d4e8"), boxText(2046).label)
        XCTAssertEqual(app.buttons["redeem.card.2046.box.reveal"].label, "隐藏兑换码")
        app.buttons["redeem.card.2046.box.reveal"].tap()
        XCTAssertTrue(waitForLabel(boxText(2046), equalTo: "兑换码已遮罩，结尾 d4e8"), boxText(2046).label)
        app.buttons["redeem.card.2046.box.copy"].tap()
        waitForReceipt("已复制兑换码")
        card(2046).tap()
        XCTAssertTrue(app.staticTexts["receipt.text"].waitForNonExistence(timeout: 8), app.debugDescription)
        // A collapsed card copies on a leading swipe.
        card(2045).swipeRight()
        let swipeCopy = app.buttons.matching(NSPredicate(format: "label == '复制兑换码'")).firstMatch
        XCTAssertTrue(swipeCopy.waitForExistence(timeout: 5), app.debugDescription)
        swipeCopy.tap()
        waitForReceipt("已复制兑换码")
    }

    @MainActor func testSameBatchFilterAndRemoveChip() {
        launchRedeem()
        defer { diagnostics("redeem-batch-final") }
        open(2046)
        openMenu(2046)
        menuItem("查看同一批").tap()
        let batch = app.buttons["redeem.batch"]
        XCTAssertTrue(batch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(batch, equalTo: "移除筛选 同一批 · 3 个"), batch.label)
        XCTAssertTrue(card(2045).waitForExistence(timeout: 10) && card(2044).exists, app.debugDescription)
        XCTAssertTrue(card(2038).waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(chip("all").exists || app.buttons["redeem.type"].exists, app.debugDescription)
        XCTAssertTrue(element("redeem.card.2046.body").exists, app.debugDescription)
        diagnostics("redeem-batch")
        batch.tap()
        XCTAssertTrue(chip("all").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card(2038).waitForExistence(timeout: 10), app.debugDescription)
        // A code without a batch has no such item.
        open(2036)
        openMenu(2036)
        XCTAssertTrue(menuItem("复制兑换码").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuItem("查看同一批").exists, app.debugDescription)
        XCTAssertTrue(menuItem("查看使用者 Studio-K 团队").exists, app.debugDescription)
    }

    @MainActor func testUserLinkOpensUserDetail() {
        launchRedeem()
        defer { diagnostics("redeem-user-final") }
        let missing = card(2008)
        reveal(missing)
        XCTAssertTrue(missing.label.contains("余额 · 用户 #99 · "), missing.label)
        reveal(card(2044), down: false)
        open(2044)
        let user = app.buttons["redeem.card.2044.user"]
        XCTAssertTrue(user.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(user.label, "王小明")
        user.tap()
        XCTAssertTrue(element("user.detail").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testLocateCodeNotLoadedPinsItOnTop() {
        launchRedeem(["-ui-redeem-many", "-ui-redeem-open", "1001"])
        defer { diagnostics("redeem-locate-final") }
        XCTAssertTrue(card(1001).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("redeem.card.1001.body").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("定位的兑换码").exists, app.debugDescription)
        XCTAssertTrue(card(1001).frame.minY < card(2046).frame.minY, app.debugDescription)
        diagnostics("redeem-locate")
        app.terminate()
        launchRedeem(["-ui-redeem-open", "9999"])
        waitForReceipt("这个兑换码已被删除")
        XCTAssertFalse(text("定位的兑换码").exists, app.debugDescription)
    }

    @MainActor func testWithoutStatsHidesCountsAndDropsAdminRows() {
        launchRedeem(["-ui-without-capabilities", "redeem_codes.stats"])
        defer { diagnostics("redeem-no-stats-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("兑换码站点").exists, app.debugDescription)
        XCTAssertFalse(text("兑换码站点 · 11 个").exists, app.debugDescription)
        for (key, title) in [("all", "全部"), ("unused", "未使用"), ("used", "已使用"), ("expired", "已过期"), ("disabled", "已禁用")] {
            XCTAssertEqual(chip(key).label, title)
        }
        reveal(card(2008))
        XCTAssertFalse(card(2005).exists, app.debugDescription)
        pickType("余额")
        XCTAssertTrue(card(2019).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(card(2005).exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenHidesGenerate() {
        launchRedeem(readOnlyToken: true)
        defer { diagnostics("redeem-readonly-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.generate"].exists, app.debugDescription)
        open(2046)
        app.buttons["redeem.card.2046.box.copy"].tap()
        waitForReceipt("已复制兑换码")
    }

    @MainActor func testPendingBannerOpensReconcileSheet() {
        launchRedeem(["-ui-pending-money"])
        defer { diagnostics("redeem-banner-final") }
        XCTAssertTrue(element("redeem.pending.banner").waitForExistence(timeout: 10), app.debugDescription)
        for part in ["兑换码生成结果待核对", "20 个 × $10.00 · 合计 $200.00", "分钟前发起，未确认是否已生成"] {
            XCTAssertTrue(labelled(containing: part).exists, part + "\n" + app.debugDescription)
        }
        XCTAssertFalse(labelled(containing: "等 2 批").exists || labelled(containing: "旧登录").exists, app.debugDescription)
        let check = app.buttons["redeem.pending.check"]
        XCTAssertNotEqual(check.value as? String, "primary")
        check.tap()
        XCTAssertTrue(app.navigationBars["核对结果"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testPendingBannerOfOldLoginOnSameAddress() {
        launchRedeem(["-ui-pending-money", "-ui-pending-old-site"])
        defer { diagnostics("redeem-banner-old-final") }
        XCTAssertTrue(element("redeem.pending.banner").waitForExistence(timeout: 10), app.debugDescription)
        for part in ["兑换码生成结果待核对等 2 批", "10 个 × $5.00 · 合计 $50.00", "分钟前发起，未确认是否已生成 · 这笔在本站点的旧登录下发起"] {
            XCTAssertTrue(labelled(containing: part).exists, part + "\n" + app.debugDescription)
        }
    }

    @MainActor func testReconcileRouteHighlightsBanner() {
        launchRedeem(["-ui-pending-money", "-ui-redeem-reconcile"])
        defer { diagnostics("redeem-banner-focus-final") }
        let check = app.buttons["redeem.pending.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(check.value as? String, "primary")
    }

    @MainActor func testListFailureAndLoadMoreFailure() {
        launchRedeem(["-ui-redeem-list-error"])
        defer { diagnostics("redeem-failures-final") }
        XCTAssertTrue(element("redeem.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 11"), app.debugDescription)
        element("redeem.failure").buttons["重试"].tap()
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()

        launchRedeem(["-ui-redeem-many", "-ui-redeem-more-error"])
        let retry = app.buttons["redeem.more.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 30), app.debugDescription)
        XCTAssertEqual(retry.label, "加载失败 · 重试")
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(card(1001), maxSwipes: 20), app.debugDescription)
        app.terminate()

        launchRedeem(["-ui-redeem-empty"])
        XCTAssertTrue(element("redeem.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("还没有兑换码").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.empty.generate"].exists, app.debugDescription)
    }

    /// `.redeem(open:)` whose first page failed: 重试 still opens the code (60 §8.1).
    @MainActor func testLocateCodeAfterRetryingFailedFirstPage() {
        launchRedeem(["-ui-redeem-list-error", "-ui-redeem-many", "-ui-redeem-open", "1001"])
        defer { diagnostics("redeem-locate-retry-final") }
        XCTAssertTrue(element("redeem.failure").waitForExistence(timeout: 10), app.debugDescription)
        element("redeem.failure").buttons["重试"].tap()
        XCTAssertTrue(element("redeem.card.1001.body").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("定位的兑换码").exists, app.debugDescription)
    }

    /// An old server whose newest four pages are admin rows: nothing to show yet is not “还没有兑换码”, and 加载更多 reads on.
    @MainActor func testOldServerOffersLoadMoreAfterPagesOfAdminRows() {
        launchRedeem(["-ui-without-capabilities", "redeem_codes.stats", "-ui-redeem-admin-flood"])
        defer { diagnostics("redeem-admin-pages-final") }
        let more = app.buttons["redeem.more.load"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(more.label, "加载更多")
        XCTAssertFalse(text("还没有兑换码").exists, app.debugDescription)
        more.tap()
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(card(3200).exists || card(2005).exists, app.debugDescription)
    }

    /// Typing on and back to the applied search within the debounce keeps the read it started (three seconds here).
    @MainActor func testSearchReadSurvivesTypingBackToTheSameText() {
        launchRedeem(["-ui-redeem-slow-search"])
        defer { diagnostics("redeem-search-same-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 10), app.debugDescription)
        search("studio-k")
        XCTAssertTrue(card(2046).waitForNonExistence(timeout: 5), app.debugDescription)
        app.searchFields["搜索兑换码或邮箱"].typeText("x" + XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(card(2036).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 1"), app.debugDescription)
    }

    /// `.redeem(open:)` whose first page waited out a 429: the read after the wait still opens the code, though GET :id is
    /// still running when the page clears the wait (00 §2.7.2, 60 §8.1).
    @MainActor func testLocateCodeAfterThrottledFirstPageWaitsOut() {
        launchRedeem(["-ui-redeem-throttled", "-ui-redeem-many", "-ui-redeem-open", "1001"])
        defer { diagnostics("redeem-locate-throttled-final") }
        XCTAssertTrue(card(2046).waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(element("redeem.card.1001.body").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("定位的兑换码").exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to “兑换码站点” (an access token with `readOnlyToken`, made read-only by `-ui-readonly-token`) and opens 兑换码
    /// from the search tab's directory.
    @MainActor func launchRedeem(_ arguments: [String] = [], readOnlyToken: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + (readOnlyToken ? ["-ui-readonly-token"] : [])
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://redeem.example.invalid", in: app.textFields["login.url"])
        enter("兑换码站点", in: app.textFields["login.name"])
        if readOnlyToken {
            tapLoginField(app.buttons["login.method.adminKey"])
            enter("sat_fixture-readonly", in: app.secureTextFields["login.key"])
        } else {
            enter("admin@example.com", in: app.textFields["login.email"])
            enter("fixture-password", in: app.secureTextFields["login.password"])
        }
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tapLoginField(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
        app.openSearchItem("search.item.redeem")
        XCTAssertTrue(app.navigationBars["兑换码"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func card(_ id: Int) -> XCUIElement { app.buttons["redeem.card.\(id)"] }
    @MainActor func boxText(_ id: Int) -> XCUIElement { element("redeem.card.\(id).box.text") }
    @MainActor func chip(_ key: String) -> XCUIElement { app.buttons["redeem.chip.\(key)"] }
    /// Scrolls the card between the bars and opens it.
    @MainActor func open(_ id: Int) {
        let head = card(id)
        XCTAssertTrue(head.waitForExistence(timeout: 10), app.debugDescription)
        reveal(head)
        head.tap()
        XCTAssertTrue(element("redeem.card.\(id).body").waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor func openMenu(_ id: Int) {
        let more = app.buttons["redeem.card.\(id).more"]
        reveal(more)
        more.tap()
    }
    /// System menu items carry no identifier.
    @MainActor func menuItem(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == '' AND label == %@", label)).firstMatch
    }
    /// The type menu ends the chip row, which scrolls sideways; a list scrolled down has unloaded it.
    @MainActor func pickType(_ label: String) {
        let menu = app.buttons["redeem.type"]
        for _ in 0..<6 where !menu.exists { app.swipeDown() }
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        menu.tap()
        let item = menuItem(label)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    @MainActor func search(_ text: String, replacing: Bool = false) {
        let field = app.searchFields["搜索兑换码或邮箱"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        if replacing, let current = field.value as? String, !current.isEmpty, current != "搜索兑换码或邮箱" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }
    @MainActor func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    @MainActor func labelled(containing text: String, in root: XCUIElement? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    /// A card: scrolled between the bars (UITestNavigation).
    @MainActor func reveal(_ item: XCUIElement, down: Bool = true) { app.scrollUntilExists(item, towardBottom: down) }
    @MainActor func waitForLabel(_ item: XCUIElement, equalTo text: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor func waitForLabel(_ item: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(waitForLabel(receipt, equalTo: text), "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor private func enter(_ value: String, in field: XCUIElement) { tapLoginField(field); field.typeText(value) }
    /// The login form: drags above the keyboard, toward a field already passed or further down, until it can be tapped.
    @MainActor private func tapLoginField(_ item: XCUIElement) {
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
        item.tap()
    }
}
