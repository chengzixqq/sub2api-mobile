import XCTest

/// 60 §13.4 被改走的账号 (S6-13) on ProxyFixtures: hk-01 (4, active) has Kimi-01 (9, now on hk-02) and MiniMax-01 (12, direct)
/// moved off it, the expired us-east-2 (7) has GLM-直连-01 (11) and Grok-旧-01 (10).
extension ProxiesUITests {
    /// ProxyFixtures' fallback page arguments.
    enum FallbackArgument {
        static let skipped = "-ui-proxy-fallback-skipped"
        static let failed = "-ui-proxy-fallback-failed"
        static let originUnavailable = "-ui-proxy-fallback-origin-unavailable"
        static let listError = "-ui-proxy-fallback-list-error"
    }

    @MainActor func testFallbackPageListsRowsAndRevertsAll() {
        openFallbackAccounts(4, title: "hk-01")
        defer { diagnostics("proxy-fallback-all-final") }
        expect(fallbackRow(9), contains: ["Kimi-01", "Kimi · API Key · 现在：备用 hk-02"])
        expect(fallbackRow(12), contains: ["MiniMax-01", "现在：直连"])
        let revertAll = app.buttons["proxy.fallback.revertAll"]
        XCTAssertEqual(revertAll.label, "全部恢复到 hk-01")
        XCTAssertTrue(revertAll.isEnabled, app.debugDescription)
        XCTAssertFalse(element("proxy.fallback.revertAll.note").exists, app.debugDescription)
        revertAll.tap()
        let alert = app.alerts["把 2 个账号改回走 hk-01？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["它们的出口 IP 会变回 203.0.113.9。"].exists, app.debugDescription)
        alert.buttons["恢复"].firstMatch.tap()
        waitForReceipt("已恢复 2 个账号到 hk-01")
        XCTAssertTrue(element("proxy.fallback.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(revertAll.exists, app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["hk-01"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["proxy.fallbackLink"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testRevertAllWithSkippedReceipt() {
        openFallbackAccounts(4, title: "hk-01", arguments: [FallbackArgument.skipped])
        defer { diagnostics("proxy-fallback-skipped-final") }
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        waitForReceipt("已恢复 1 个账号到 hk-01 · 1 个已不在回退状态，已跳过")
        XCTAssertTrue(element("proxy.fallback.empty").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// The failed account is listed with fixed words; the server's own text is never shown (R11).
    @MainActor func testRevertAllWithFailedListsFailure() {
        openFallbackAccounts(4, title: "hk-01", arguments: [FallbackArgument.failed])
        defer { diagnostics("proxy-fallback-failed-final") }
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        waitForReceipt("已恢复 1 个账号到 hk-01 · 1 个没有恢复")
        let failure = element("proxy.fallback.failure.12")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        expect(failure, contains: ["MiniMax-01", "服务器没能恢复这个账号"])
        XCTAssertTrue(fallbackRow(9).waitForNonExistence(timeout: 10), app.debugDescription)
        reveal(fallbackRow(12))
        XCTAssertTrue(fallbackRow(12).exists, app.debugDescription)
    }

    /// One row needs no Face ID (60 §3.4 covers batches): it goes through although every check would be refused.
    @MainActor func testSwipeRevertsSingleAccount() {
        openFallbackAccounts(4, title: "hk-01", arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("proxy-fallback-swipe-final") }
        fallbackRow(9).swipeLeft()
        let swipe = swipeRevertButton(9)
        XCTAssertNotNil(swipe, app.debugDescription)
        swipe?.tap()
        let alert = app.alerts["把「Kimi-01」改回走 hk-01？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["它的出口 IP 会变回 203.0.113.9。"].exists, app.debugDescription)
        alert.buttons["恢复"].firstMatch.tap()
        waitForReceipt("已恢复 1 个账号到 hk-01")
        XCTAssertTrue(fallbackRow(9).waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(fallbackRow(12).exists, app.debugDescription)
        XCTAssertTrue(waitForEnabled(app.buttons["proxy.fallback.revertAll"]), app.debugDescription)
    }

    @MainActor func testExpiredProxyGreysRevertAll() {
        openFallbackAccounts(7, title: "us-east-2")
        defer { diagnostics("proxy-fallback-expired-final") }
        expect(fallbackRow(11), contains: ["GLM-直连-01", "智谱 GLM · API Key · 现在：直连"])
        let revertAll = app.buttons["proxy.fallback.revertAll"]
        XCTAssertTrue(revertAll.exists, app.debugDescription)
        XCTAssertFalse(revertAll.isEnabled, app.debugDescription)
        XCTAssertEqual(element("proxy.fallback.revertAll.note").label, "先续期并启用这个代理")
        fallbackRow(11).swipeLeft()
        XCTAssertNil(swipeRevertButton(11, timeout: 2), app.debugDescription)
    }

    @MainActor func testOriginUnavailableReceipt() {
        openFallbackAccounts(4, title: "hk-01", arguments: [FallbackArgument.originUnavailable])
        defer { diagnostics("proxy-fallback-origin-final") }
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        waitForReceipt("原代理仍已过期或已停用，请先续期或启用后再恢复")
        XCTAssertTrue(fallbackRow(9).exists && fallbackRow(12).exists, app.debugDescription)
    }

    /// 全部恢复 is a batch: with Face ID on, a refused check sends nothing and says nothing.
    @MainActor func testRevertAllNeedsFaceIDWhenOn() {
        openFallbackAccounts(4, title: "hk-01", arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        XCTAssertTrue(waitForEnabled(app.buttons["proxy.fallback.revertAll"], timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(fallbackRow(9).exists && fallbackRow(12).exists, app.debugDescription)
        diagnostics("proxy-fallback-faceid-denied")
        app.terminate()
        openFallbackAccounts(4, title: "hk-01", arguments: ["-ui-faceid-on"])
        defer { diagnostics("proxy-fallback-faceid-final") }
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        waitForReceipt("已恢复 2 个账号到 hk-01")
    }

    /// A read-only token sees the accounts and opens them, without 全部恢复 or the swipe.
    @MainActor func testReadOnlyTokenHidesRevertAndRowOpensAccount() {
        openFallbackAccounts(4, title: "hk-01", readOnlyToken: true)
        defer { diagnostics("proxy-fallback-readonly-final") }
        XCTAssertTrue(fallbackRow(12).exists, app.debugDescription)
        XCTAssertFalse(app.buttons["proxy.fallback.revertAll"].exists, app.debugDescription)
        fallbackRow(9).tap()
        XCTAssertTrue(app.navigationBars["Kimi-01"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.proxy.row").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(fallbackRow(12).waitForExistence(timeout: 10), app.debugDescription)
        // Without a swipe action the drag may land as a tap and open the account; either way nothing offers 恢复.
        fallbackRow(12).swipeLeft()
        XCTAssertNil(swipeRevertButton(12, timeout: 2), app.debugDescription)
    }

    @MainActor func testFallbackListFailureShowsFailureView() {
        openFallbackAccounts(4, title: "hk-01", arguments: [FallbackArgument.listError], waitsForRows: false)
        defer { diagnostics("proxy-fallback-list-error-final") }
        XCTAssertTrue(element("proxy.fallback.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("暂时无法加载").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["重试"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["proxy.fallback.revertAll"].exists, app.debugDescription)
        XCTAssertFalse(element("proxy.fallback.list").exists, app.debugDescription)
    }

    // MARK: - S6-13 helpers

    /// The detail, then its 被改走的账号 row, waiting for the page's rows.
    @MainActor func openFallbackAccounts(_ id: Int, title: String, arguments: [String] = [], readOnlyToken: Bool = false, waitsForRows: Bool = true) {
        openDetail(id, title: title, arguments: arguments, readOnlyToken: readOnlyToken)
        let link = app.buttons["proxy.fallbackLink"]
        reveal(link)
        link.tap()
        XCTAssertTrue(app.navigationBars["被改走的账号"].waitForExistence(timeout: 10), app.debugDescription)
        guard waitsForRows else { return }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "proxy.fallback.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func fallbackRow(_ id: Int) -> XCUIElement { app.buttons["proxy.fallback.row.\(id)"] }
    @MainActor func revertAllAndConfirm(_ title: String) {
        let revertAll = app.buttons["proxy.fallback.revertAll"]
        XCTAssertTrue(waitForEnabled(revertAll), app.debugDescription)
        revertAll.tap()
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["恢复"].firstMatch.tap()
    }
    /// The row's swipe action by its identifier, else by its title; nil when the swipe offers none.
    @MainActor func swipeRevertButton(_ id: Int, timeout: TimeInterval = 3) -> XCUIElement? {
        let byID = app.buttons["proxy.fallback.row.\(id).revert"]
        if byID.waitForExistence(timeout: timeout) { return byID }
        let byTitle = app.buttons.matching(NSPredicate(format: "label == %@", "恢复")).firstMatch
        return byTitle.exists ? byTitle : nil
    }

    // MARK: - S6-13 审查修正

    /// From DeepSeek-01's proxy row while the catalog never loaded (its read fails): the revert still reaches the detail under
    /// the page, which reads hk-01 and 贰 again; the 被改走的账号 row is gone and both accounts are back on it.
    @MainActor func testRevertFromAccountEntryReadsDetailAgain() {
        launchProxies([DemoArgument.listError])
        defer { diagnostics("proxy-fallback-account-entry-final") }
        XCTAssertTrue(element("proxies.failure").waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["accounts.chip.all"].waitForExistence(timeout: 10), app.debugDescription)
        let account = app.buttons["account.8"]
        reveal(account)
        account.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        let proxyRow = element("account.proxy.row")
        reveal(proxyRow)
        proxyRow.tap()
        XCTAssertTrue(app.navigationBars["hk-01"].waitForExistence(timeout: 10), app.debugDescription)
        let link = app.buttons["proxy.fallbackLink"]
        reveal(link)
        link.tap()
        XCTAssertTrue(fallbackRow(9).waitForExistence(timeout: 10), app.debugDescription)
        revertAllAndConfirm("把 2 个账号改回走 hk-01？")
        waitForReceipt("已恢复 2 个账号到 hk-01")
        XCTAssertTrue(element("proxy.fallback.empty").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["hk-01"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(link.waitForNonExistence(timeout: 10), app.debugDescription)
        let restored = app.buttons["proxy.account.12"]
        reveal(restored)
        XCTAssertTrue(restored.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["proxy.account.9"].exists && app.buttons["proxy.account.8"].exists, app.debugDescription)
    }
}
