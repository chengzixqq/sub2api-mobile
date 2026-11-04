import XCTest

/// S6-02: 管理访问令牌 (60 §6) reached from 站点与凭据 → 当前站点. Rows show the scope, 本机 and expiry; another token is
/// revoked after a confirmation with a receipt, a read-only token may revoke only itself (00 §2.6.3), revoking this App's
/// own token returns to the site's login page, and the App issues no token (U02).
final class AccessTokensUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testEntryShowsIntroBadgesAndMaskedRows() {
        launchAndLogin(accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-entry-final") }
        openTokens(expectingCount: "3")
        XCTAssertTrue(element("accessTokens.intro").label.hasPrefix("访问令牌以签发它的管理员身份调用管理接口，可只读、会过期、能单独吊销。"),
                      element("accessTokens.intro").label)
        let this = row(1)
        XCTAssertTrue(this.waitForExistence(timeout: 5), app.debugDescription)
        for expected in ["本机 iPhone，读写，本机，", "sat_3f9a…c71e", "最近使用 3 分钟前 · 203.0.113.24", "到期 · 还剩 87 天"] {
            XCTAssertTrue(this.label.contains(expected), this.label)
        }
        XCTAssertNotEqual(this.value as? String, "即将到期")
        XCTAssertTrue(row(2).label.contains("监控脚本，只读，sat_9b20…41ad"), row(2).label)
        XCTAssertTrue(row(2).label.contains("198.51.100.7"), row(2).label)
        let soon = row(3)
        XCTAssertTrue(soon.label.contains("从未使用") && soon.label.contains("还剩 5 天"), soon.label)
        XCTAssertEqual(soon.value as? String, "即将到期")
        // U02: nothing is issued here, so the bar holds only the back button.
        let addButtons = app.navigationBars["管理访问令牌"].buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label ==[c] %@",
                                                                                     "添加", "新建", "add"))
        XCTAssertEqual(addButtons.count, 0, app.debugDescription)
        diagnostics("tokens-list")
    }

    @MainActor func testRevokingAnotherTokenRemovesTheRow() {
        launchAndLogin(accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-revoke-final") }
        openTokens(expectingCount: "3")
        openRevokeConfirmation(for: 2)
        XCTAssertTrue(text(containing: "吊销「监控脚本」？").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。").exists, app.debugDescription)
        XCTAssertFalse(text(containing: "本机会退出这个站点。").exists, app.debugDescription)
        diagnostics("tokens-revoke-confirm")
        confirmButton().tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(receipt.label, "已吊销「监控脚本」")
        XCTAssertTrue(waitUntilGone(row(2)), app.debugDescription)
        XCTAssertTrue(row(1).exists && row(3).exists, app.debugDescription)
        goBackToSettings(expectingCount: "2")
    }

    @MainActor func testCancellingKeepsTheRow() {
        launchAndLogin(accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-cancel-final") }
        openTokens(expectingCount: "3")
        openRevokeConfirmation(for: 3)
        XCTAssertTrue(text(containing: "吊销「临时排查」？").waitForExistence(timeout: 5), app.debugDescription)
        dismissConfirmation()
        XCTAssertTrue(waitUntilGone(text(containing: "吊销「临时排查」？")), app.debugDescription)
        XCTAssertTrue(row(3).exists && row(1).exists && row(2).exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenCanOnlyRevokeItself() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-read-only-final") }
        openTokens(expectingCount: "3")
        XCTAssertTrue(row(1).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(1).label.contains("本机 iPhone，只读，本机，"), row(1).label)
        for id in [2, 3] {
            row(id).swipeLeft()
            XCTAssertFalse(app.buttons["accessTokens.row.\(id).revoke"].waitForExistence(timeout: 2), app.debugDescription)
            XCTAssertFalse(app.buttons["吊销"].exists, app.debugDescription)
        }
        row(1).swipeLeft()
        XCTAssertTrue(revokeButton(for: 1).exists, app.debugDescription)
        diagnostics("tokens-read-only-swipe")
    }

    @MainActor func testRevokingTheCurrentTokenReturnsToTheSiteLogin() {
        launchAndLogin(accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-revoke-current-final") }
        openTokens(expectingCount: "3")
        openRevokeConfirmation(for: 1)
        XCTAssertTrue(text(containing: "吊销「本机 iPhone」？").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "本机会退出这个站点。").exists, app.debugDescription)
        diagnostics("tokens-revoke-current-confirm")
        confirmButton().tap()
        let notice = app.staticTexts["login.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(notice.label, "已吊销本机正在使用的令牌，请重新登录")
        XCTAssertEqual(app.textFields["login.name"].value as? String, siteName)
        XCTAssertEqual(app.textFields["login.url"].value as? String, siteURL)
        let method = app.buttons["login.method.accessToken"]
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: method)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists, app.debugDescription)
    }

    @MainActor func testAccountSignInListsTokensWithoutACurrentOne() {
        launchAndLogin()
        defer { diagnostics("tokens-account-final") }
        openTokens(expectingCount: "3")
        for id in [1, 2, 3] {
            XCTAssertTrue(row(id).waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(row(id).label.contains("，本机，"), row(id).label)
        }
        for id in [3, 2, 1] {
            row(id).swipeLeft()
            XCTAssertTrue(revokeButton(for: id).exists, app.debugDescription)
            // Closed again, so the next row's swipe is not taken for this one's.
            row(id).swipeRight()
            XCTAssertTrue(waitUntilGone(app.buttons["吊销"]), app.debugDescription)
        }
    }

    @MainActor func testEmptyListExplainsThatTheAppIssuesNone() {
        launchAndLogin(arguments: ["-ui-access-tokens-empty"], accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-empty-final") }
        openTokens(expectingCount: "0")
        XCTAssertTrue(text(containing: "还没有访问令牌").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "首版 App 不签发访问令牌。").exists, app.debugDescription)
        XCTAssertFalse(row(1).exists, app.debugDescription)
    }

    @MainActor func testLoadFailureShowsRetry() {
        launchAndLogin(arguments: ["-ui-access-tokens-failure"], accessToken: "sat_ui-fixture")
        defer { diagnostics("tokens-failure-final") }
        openTokens(expectingCount: nil)
        XCTAssertTrue(text(containing: "暂时无法加载").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "站点暂时不可用，请稍后重试").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["重试"].exists, app.debugDescription)
    }

    // MARK: Helpers

    private let siteName = "令牌站点"
    private let siteURL = "https://tokens.example.invalid"

    /// Password sign-in, or the access-token method for `accessToken` (a `sat_` key selects it on its own, 60 §4.3).
    @MainActor private func launchAndLogin(arguments: [String] = [], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(siteURL, in: "login.url")
        enter(siteName, in: "login.name")
        if let accessToken {
            let method = app.buttons["login.method.adminKey"]; reveal(method); method.tap()
            enter(accessToken, in: "login.key")
        } else {
            enter("admin@example.com", in: "login.email")
            enter("fixture-password", in: "login.password")
        }
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// nil: the count failed to load and is left out (60 §3.6).
    @MainActor private func openTokens(expectingCount count: String?) {
        app.openSitesSettings()
        let entry = app.buttons["settings.current.tokens"]
        reveal(entry)
        if let count {
            XCTAssertTrue(waitForLabel(entry, containing: count), entry.label)
        } else {
            XCTAssertFalse(entry.label.contains(where: \.isNumber), entry.label)
        }
        entry.tap()
        XCTAssertTrue(app.navigationBars["管理访问令牌"].waitForExistence(timeout: 5), app.debugDescription)
    }
    /// Back on the settings page, which reads the count again when it reappears (60 §3.6).
    @MainActor private func goBackToSettings(expectingCount count: String) {
        app.navigationBars["管理访问令牌"].buttons.element(boundBy: 0).tap()
        let entry = app.buttons["settings.current.tokens"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
        reveal(entry)
        XCTAssertTrue(waitForLabel(entry, containing: count), entry.label)
    }
    @MainActor private func row(_ id: Int) -> XCUIElement { element("accessTokens.row.\(id)") }
    @MainActor private func openRevokeConfirmation(for id: Int) {
        let item = row(id)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.swipeLeft()
        revokeButton(for: id).tap()
    }
    /// The swipe action by its identifier, else by its title: only the row's swipe says 吊销 before the confirmation opens.
    @MainActor private func revokeButton(for id: Int) -> XCUIElement {
        let byID = app.buttons["accessTokens.row.\(id).revoke"]
        if byID.waitForExistence(timeout: 3) { return byID }
        let byTitle = app.buttons["吊销"]
        XCTAssertTrue(byTitle.waitForExistence(timeout: 2), app.debugDescription)
        return byTitle
    }
    /// The confirmation's button, never the row's swipe action of the same title. The system nests one button in another
    /// under the same identifier.
    @MainActor private func confirmButton() -> XCUIElement {
        let byID = app.buttons["accessTokens.confirm"].firstMatch
        if byID.waitForExistence(timeout: 2) { return byID }
        let predicate = NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "吊销", "accessTokens.row.")
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        return button
    }
    /// The sheet's 取消 where the system draws one; otherwise a tap below the floating confirmation closes it.
    @MainActor private func dismissConfirmation() {
        let cancel = app.buttons["取消"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); return }
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: sheet.frame.midX, dy: sheet.frame.maxY + 80)).tap()
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing text: String) -> Bool {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: item)
        return XCTWaiter().wait(for: [match], timeout: 5) == .completed
    }
    @MainActor private func waitUntilGone(_ item: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: item)
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func text(containing label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Rows of a List exist only near the screen; the row must end up between the navigation bar and the tab bar.
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveTabBar(item) { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let bottom = min(tabTop, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            let down = !(item.exists && item.frame.maxY < top)
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func isAboveTabBar(_ item: XCUIElement) -> Bool {
        guard app.tabBars.firstMatch.exists else { return true }
        return item.frame.maxY <= app.tabBars.firstMatch.frame.minY && item.frame.minY >= app.navigationBars.firstMatch.frame.maxY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
