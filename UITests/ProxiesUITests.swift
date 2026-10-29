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
        XCTAssertTrue(app.navigationBars["hk-02"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("proxy.detail.card").waitForExistence(timeout: 10), app.debugDescription)
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

    // MARK: - S6-12 详情

    /// ProxyFixtures' detail arguments.
    enum DetailArgument {
        static let notFound = "-ui-proxy-not-found"
        static let accountsError = "-ui-proxy-accounts-error"
        static let accountsErrorOnce = "-ui-proxy-accounts-error-once"
        static let qualityError = "-ui-proxy-quality-error"
        static let deleteConflict = "-ui-proxy-delete-conflict"
        static let slowDetail = "-ui-proxy-slow-detail"
        static let withoutCapabilities = "-ui-without-capabilities"
    }

    @MainActor func testDetailLayoutFromListRow() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-layout-final") }
        XCTAssertTrue(text("SOCKS5 · 203.0.113.24:1080").exists, app.debugDescription)
        XCTAssertEqual(element("proxy.detail.badge").label, "正常")
        XCTAssertFalse(element("proxy.detail.cause").exists, app.debugDescription)
        expect(element("proxy.latency"), contains: ["182ms", "上次测试 "])
        expect(element("proxy.facts.exitIP"), contains: ["出口 IP", "203.0.113.24"])
        expect(element("proxy.facts.quality"), contains: ["质量", "—"])
        XCTAssertTrue(app.buttons["proxy.action.test"].exists && app.buttons["proxy.action.edit"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["proxy.action.renew"].exists, app.debugDescription)
        let note = element("proxy.expiry.note")
        reveal(note)
        XCTAssertTrue(note.label.contains("6 天后到期。到期后把在用的账号改为备用 sg\u{2011}01。"), note.label)
        expect(element("proxy.kv.warnDays"), contains: ["到期提醒", "提前 7 天"])
        XCTAssertFalse(element("proxy.kv.remaining").exists, app.debugDescription)
        let account = app.buttons["proxy.account.1"]
        reveal(account)
        XCTAssertEqual(element("proxy.accounts.meta").value as? String, "3 个", app.debugDescription)
        expect(account, contains: ["Claude-官方-01", "Anthropic · OAuth"])
        let password = element("proxy.kv.password")
        reveal(password)
        expect(password, contains: ["密码", "••••••"])
        expect(element("proxy.kv.host"), contains: ["203.0.113.24"])
        expect(element("proxy.kv.scheme"), contains: ["SOCKS5"])
        for id in ["proxy.kv.password", "proxy.kv.username", "proxy.kv.host"] {
            XCTAssertFalse(element(id).label.contains("fixture-proxy-secret"), element(id).label)
        }
    }

    @MainActor func testExpiredProxyShowsRenewFirstAndFailedLatency() {
        openDetail(3, title: "jp-tokyo-1")
        defer { diagnostics("proxy-detail-expired-final") }
        XCTAssertEqual(element("proxy.detail.badge").label, "已过期")
        expect(element("proxy.latency"), contains: ["链接失败", "i/o timeout"])
        let renew = app.buttons["proxy.action.renew"], test = app.buttons["proxy.action.test"]
        XCTAssertTrue(renew.exists && test.exists, app.debugDescription)
        XCTAssertLessThan(renew.frame.minX, test.frame.minX, app.debugDescription)
        XCTAssertFalse(app.buttons["proxy.action.edit"].exists, app.debugDescription)
        let note = element("proxy.expiry.note")
        reveal(note)
        XCTAssertTrue(note.label.contains("已过期，1 个账号仍在用这个代理。"), note.label)
        reveal(renew, down: false)
        renew.tap()
        // S6-14 replaces the placeholder sheet.
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testTestConnectionUpdatesLatencyAndCause() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-test-final") }
        app.buttons["proxy.action.test"].tap()
        let cause = element("proxy.detail.cause")
        XCTAssertTrue(cause.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(waitForLabel(cause, containing: "正在测试连通性", timeout: 3), cause.label)
        XCTAssertTrue(waitForLabel(cause, containing: "刚刚测试 ", timeout: 8), cause.label)
        expect(element("proxy.latency"), contains: ["176ms"])
        goBack()
        XCTAssertTrue(app.navigationBars["代理"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(1))
        XCTAssertTrue(row(1).label.contains("176ms"), row(1).label)
    }

    @MainActor func testTestHTTPFailureKeepsValue() {
        openDetail(4, title: "hk-01", arguments: [DemoArgument.testHTTPError])
        defer { diagnostics("proxy-detail-test-error-final") }
        app.buttons["proxy.action.test"].tap()
        waitForReceipt("测试请求失败，请稍后再试", timeout: 8)
        expect(element("proxy.latency"), contains: ["311ms"])
        XCTAssertFalse(element("proxy.detail.cause").exists, app.debugDescription)
    }

    @MainActor func testDisableThenUndo() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-disable-final") }
        chooseFromMenu("停用代理")
        waitForReceipt("已停用 hk-02 · 在用的 3 个账号不受影响")
        let badge = element("proxy.detail.badge")
        XCTAssertTrue(waitForLabel(badge, containing: "停用"), badge.label)
        XCTAssertEqual(element("proxy.detail.cause").label, "在用的账号不受影响")
        let undo = app.buttons["receipt.action"]
        XCTAssertEqual(undo.label, "撤销")
        undo.tap()
        XCTAssertTrue(waitForLabel(badge, containing: "正常"), badge.label)
        goBack()
        reveal(row(1))
        XCTAssertTrue(waitForLabel(row(1), containing: "182ms"), row(1).label)
    }

    @MainActor func testEnableInactiveProxy() {
        openDetail(6, title: "de-fra-1")
        defer { diagnostics("proxy-detail-enable-final") }
        XCTAssertEqual(element("proxy.detail.cause").label, "账号编辑里选不到它")
        chooseFromMenu("启用代理")
        waitForReceipt("已启用 de-fra-1")
        XCTAssertTrue(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(waitForLabel(element("proxy.detail.badge"), containing: "正常"), app.debugDescription)
    }

    @MainActor func testCopyProxyURLReceipt() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-copy-final") }
        chooseFromMenu("复制代理 URL")
        waitForReceipt("已复制代理 URL")
        XCTAssertFalse(app.staticTexts["receipt.text"].label.contains("fixture"), app.debugDescription)
    }

    @MainActor func testQualityCheckReceiptAndFacts() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-quality-final") }
        chooseFromMenu("质量检测")
        let quality = element("proxy.facts.quality")
        XCTAssertTrue(waitForLabel(quality, containing: "检测中…", timeout: 4), quality.label)
        waitForReceipt("质量检测完成：评分 92（A）", timeout: 12)
        XCTAssertTrue(waitForLabel(quality, containing: "A · 92"), quality.label)
        app.terminate()
        openDetail(1, title: "hk-02", arguments: [DetailArgument.qualityError])
        chooseFromMenu("质量检测")
        waitForReceipt("代理质量检测失败", timeout: 12)
        XCTAssertTrue(waitForLabel(element("proxy.facts.quality"), containing: "B · 78"), app.debugDescription)
    }

    @MainActor func testDeleteBlockedWhenAccountsUseIt() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-detail-delete-in-use-final") }
        chooseFromMenu("删除代理…")
        let alert = app.alerts["不能删除「hk-02」"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["该代理已有 3 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。"].exists, app.debugDescription)
        XCTAssertFalse(alert.buttons["查看被改走的账号"].exists, app.debugDescription)
        alert.buttons["知道了"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element("delete.sheet").exists, app.debugDescription)
        XCTAssertTrue(element("proxy.detail.card").exists, app.debugDescription)
    }

    @MainActor func testDeleteBlockedByFallbackAccounts() {
        openDetail(7, title: "us-east-2")
        defer { diagnostics("proxy-detail-delete-fallback-final") }
        let link = app.buttons["proxy.fallbackLink"]
        reveal(link)
        XCTAssertEqual(link.label, "被改走的账号 2 个")
        chooseFromMenu("删除代理…")
        let alert = app.alerts["不能删除「us-east-2」"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["2 个账号到期时从这个代理改走，删除后它们就恢复不了原代理。先恢复这些账号，或在账号详情里处理。"].exists,
                      app.debugDescription)
        XCTAssertTrue(alert.buttons["知道了"].exists, app.debugDescription)
        alert.buttons["查看被改走的账号"].tap()
        // S6-13 replaces the placeholder.
        XCTAssertTrue(app.navigationBars["被改走的账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        openDetail(7, title: "us-east-2", arguments: [DetailArgument.withoutCapabilities, "proxies.fallback_accounts"])
        XCTAssertFalse(app.buttons["proxy.fallbackLink"].exists, app.debugDescription)
        chooseFromMenu("删除代理…")
        let plain = app.alerts["不能删除「us-east-2」"]
        XCTAssertTrue(plain.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(plain.buttons["查看被改走的账号"].exists, app.debugDescription)
        plain.buttons["知道了"].tap()
    }

    /// The proxy looked free, but the DELETE answers 409 without metadata: the in-use box once the confirmation has closed.
    @MainActor func testDeleteConflictShowsInUseBox() {
        openDetail(5, title: "us-west-3", arguments: [DetailArgument.deleteConflict])
        defer { diagnostics("proxy-detail-delete-conflict-final") }
        chooseFromMenu("删除代理…")
        typeNameAndConfirm("us-west-3")
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        let alert = app.alerts["不能删除「us-west-3」"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["该代理已有 1 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。"].exists, app.debugDescription)
        alert.buttons["知道了"].tap()
        XCTAssertTrue(app.navigationBars["us-west-3"].exists, app.debugDescription)
    }

    @MainActor func testDeleteByTypingNameReturnsToList() {
        openDetail(5, title: "us-west-3")
        defer { diagnostics("proxy-detail-delete-final") }
        chooseFromMenu("删除代理…")
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除代理「us-west-3」？")
        XCTAssertTrue(element("delete.message").label.contains("站点 代理站点 · 删除后不能恢复。"), element("delete.message").label)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "删除代理")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("US-WEST-3")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "us-west-3")
        XCTAssertTrue(waitForEnabled(confirm), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["代理"].waitForExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已删除代理「us-west-3」")
        XCTAssertTrue(row(5).waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("代理站点 · 7 个").exists, app.debugDescription)
    }

    /// 60 §3.4: with Face ID nothing is typed; a refused check deletes nothing and says nothing.
    @MainActor func testDeleteWithFaceIDAndDenied() {
        openDetail(5, title: "us-west-3", arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        chooseFromMenu("删除代理…")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitForEnabled(confirm), app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("proxy.detail.card").exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        diagnostics("proxy-detail-delete-faceid-denied")
        app.terminate()
        openDetail(5, title: "us-west-3", arguments: ["-ui-faceid-on"])
        defer { diagnostics("proxy-detail-delete-faceid-final") }
        chooseFromMenu("删除代理…")
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["delete.confirm"].tap()
        waitForReceipt("已删除代理「us-west-3」")
        XCTAssertTrue(app.navigationBars["代理"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(5).waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testNotFoundShowsGonePage() {
        openDetail(1, title: "代理", arguments: [DetailArgument.notFound], waitsForCard: false)
        defer { diagnostics("proxy-detail-gone-final") }
        let gone = element("proxy.detail.gone")
        XCTAssertTrue(gone.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(gone.label.contains("已删除"), gone.label)
        XCTAssertFalse(app.buttons["proxy.more"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(text("代理站点 · 7 个").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(2))
        XCTAssertFalse(row(1).exists, app.debugDescription)
    }

    @MainActor func testAccountsSectionFailureAndAccountPush() {
        openDetail(1, title: "hk-02", arguments: [DetailArgument.accountsError])
        defer { diagnostics("proxy-detail-accounts-final") }
        let retry = app.buttons["proxy.accounts.retry"]
        reveal(retry)
        XCTAssertEqual(retry.label, "暂时无法加载 · 重试")
        app.terminate()
        openDetail(5, title: "us-west-3")
        let empty = element("proxy.accounts.empty")
        reveal(empty)
        XCTAssertEqual(empty.label, "暂无账号使用此代理")
        goBack()
        reveal(row(1))
        row(1).tap()
        XCTAssertTrue(app.navigationBars["hk-02"].waitForExistence(timeout: 10), app.debugDescription)
        let account = app.buttons["proxy.account.1"]
        reveal(account)
        account.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenHidesButtonsAndGreysMenu() {
        openDetail(1, title: "hk-02", readOnlyToken: true)
        defer { diagnostics("proxy-detail-readonly-final") }
        XCTAssertFalse(app.buttons["proxy.action.test"].exists || app.buttons["proxy.action.edit"].exists, app.debugDescription)
        app.buttons["proxy.more"].tap()
        for title in ["编辑代理", "质量检测", "停用代理", "删除代理…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
            XCTAssertFalse(menuItem(title).isEnabled, "\(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(menuItem("复制代理 URL").isEnabled, app.debugDescription)
        menuItem("复制代理 URL").tap()
        waitForReceipt("已复制代理 URL")
    }

    /// From an account's proxy row with only an id (the catalog never loaded): the card's placeholder, then the card.
    @MainActor func testIdOnlyEntryShowsPlaceholderThenCard() {
        launchProxies([DemoArgument.listError, DetailArgument.slowDetail])
        defer { diagnostics("proxy-detail-id-only-final") }
        XCTAssertTrue(element("proxies.failure").waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["accounts.chip.all"].waitForExistence(timeout: 10), app.debugDescription)
        let account = app.buttons["account.1"]
        reveal(account)
        account.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        let proxyRow = element("account.proxy.row")
        reveal(proxyRow)
        proxyRow.tap()
        XCTAssertTrue(element("proxy.detail.placeholder").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("proxy.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["hk-02"].exists, app.debugDescription)
        XCTAssertFalse(element("proxy.detail.placeholder").exists, app.debugDescription)
    }

    // MARK: - S6-12 helpers

    /// The list, then the row's detail with its card.
    @MainActor func openDetail(_ id: Int, title: String, arguments: [String] = [], readOnlyToken: Bool = false, waitsForCard: Bool = true) {
        launchProxies(arguments, readOnlyToken: readOnlyToken)
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(id))
        row(id).tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
        if waitsForCard { XCTAssertTrue(element("proxy.detail.card").waitForExistence(timeout: 10), app.debugDescription) }
    }
    /// A ··· entry by its title, not the button row's button of a similar name.
    @MainActor func menuItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "proxy.action.")).firstMatch
    }
    @MainActor func chooseFromMenu(_ title: String) {
        let more = app.buttons["proxy.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        let item = menuItem(title)
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    @MainActor func typeNameAndConfirm(_ name: String) {
        let input = element("delete.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        input.tap()
        input.typeText(name)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(waitForEnabled(confirm), app.debugDescription)
        confirm.tap()
    }
    @MainActor func waitForReceipt(_ text: String, timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: timeout), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor func waitForEnabled(_ item: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: item)], timeout: timeout) == .completed
    }
    @MainActor func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    // MARK: - S6-12 审查修正

    /// 00 §4.6 (D18): back in the foreground the detail reads its proxy and accounts again; 贰's first read had failed.
    @MainActor func testForegroundReadsDetailAgain() {
        openDetail(1, title: "hk-02", arguments: [DetailArgument.accountsErrorOnce])
        defer { diagnostics("proxy-detail-foreground-final") }
        let retry = app.buttons["proxy.accounts.retry"]
        reveal(retry)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["proxy.account.1"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(retry.exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["hk-02"].exists, app.debugDescription)
    }
}
