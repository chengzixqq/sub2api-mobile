import XCTest

/// 20 §3.3–§3.4 (S2-11): the detail's 代理 section and picker, 恢复原代理, ⋯'s 在 Web 中编辑 and 删除账号…, on the fixture site's
/// demo accounts and proxies (DemoData+Accounts). OpenAI-主力-01 (4) is on sg-01, Gemini-测试-B (5) on the expired jp-tokyo-1,
/// Kimi-01 (9) fell back from hk-01 to hk-02, Grok-旧-01 (10) has no proxy.
final class AccountDetailMenuUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "账号菜单站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let detailError = "-ui-account-detail-error"
        static let writeFail = "-ui-account-write-fail"
        static let notInFallback = "-ui-account-revert-not-in-fallback"
        static let originUnavailable = "-ui-account-revert-origin-unavailable"
        static let bedrock = "-ui-account-bedrock-error"
        static let proxyConflict = "-ui-account-proxy-conflict"
        static let without = "-ui-without-capabilities"
        static let deepLink = "web.accounts_edit_deep_link"
    }

    // MARK: - 代理

    @MainActor func testPickingProxySavesThenUndoRestores() {
        openDetail(4)
        defer { diagnostics("account-menu-proxy-pick-final") }
        let row = element("account.proxy.row")
        reveal(row)
        waitForLabel(row, contains: "sg-01")
        XCTAssertTrue(row.label.contains("HTTPS · 剩余"), row.label)
        openPicker()
        let direct = element("account.proxy.option.direct")
        XCTAssertTrue(direct.label.contains("无代理") && direct.label.contains("直连上游"), direct.label)
        let hk02 = element("account.proxy.option.1")
        XCTAssertTrue(hk02.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(hk02.label.contains("6 天后到期") && hk02.label.contains("个账号在用"), hk02.label)
        XCTAssertTrue(element("account.proxy.option.2").isSelected, app.debugDescription)
        hk02.tap()
        // The receipt stays 4.2 seconds (R17): one wait for the closed picker's row, then 撤销 while the receipt is still up.
        waitForLabel(element("account.proxy.row"), contains: "hk-02")
        XCTAssertEqual(app.staticTexts["receipt.text"].label, "已保存：代理 → hk-02")
        let undo = app.buttons["receipt.action"]
        XCTAssertEqual(undo.label, "撤销")
        undo.tap()
        XCTAssertFalse(element("account.proxy.picker").exists, app.debugDescription)
        waitForLabel(element("account.proxy.row"), contains: "sg-01")
    }

    /// U23: without a proxy the row opens the picker, as “编辑” does.
    @MainActor func testSwitchingToNoProxy() {
        openDetail(4)
        defer { diagnostics("account-menu-proxy-direct-final") }
        openPicker()
        element("account.proxy.option.direct").tap()
        waitForReceipt("已保存：代理 → 无代理")
        let row = element("account.proxy.row")
        reveal(row)
        waitForLabel(row, contains: "无代理")
        XCTAssertFalse(row.label.contains("://"), row.label)
        row.tap()
        XCTAssertTrue(element("account.proxy.picker").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.proxy.option.direct").isSelected, app.debugDescription)
        app.buttons["account.proxy.cancel"].tap()
        XCTAssertTrue(element("account.proxy.picker").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testExpiredProxyShowsHintAndPickerNote() {
        openDetail(5)
        defer { diagnostics("account-menu-proxy-expired-final") }
        let row = element("account.proxy.row")
        reveal(row)
        waitForLabel(row, contains: "已过期")
        XCTAssertEqual(element("account.proxy.hint").label, "代理已过期，这个账号仍挂在上面。换一个启用中的代理，或改为无代理。")
        openPicker()
        let note = element("account.proxy.current-note")
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(note.label.contains("当前代理 jp-tokyo-1 已过期，不在可选列表里"), note.label)
        XCTAssertTrue(element("account.proxy.option.1").exists, app.debugDescription)
        XCTAssertFalse(element("account.proxy.option.3").exists, app.debugDescription)
        app.buttons["account.proxy.cancel"].tap()
    }

    /// A row with a proxy pushes its detail (S6-12).
    @MainActor func testProxyRowOpensProxyDetail() {
        openDetail(1)
        defer { diagnostics("account-menu-proxy-detail-final") }
        let row = element("account.proxy.row")
        reveal(row)
        waitForLabel(row, contains: "hk-02")
        row.tap()
        XCTAssertTrue(element("proxy.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["hk-02"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testProxyEditDisabledWithoutVersion() {
        openDetail(4, arguments: [Fixture.detailError])
        defer { diagnostics("account-menu-proxy-noversion-final") }
        let edit = app.buttons["account.section.proxy.edit"]
        reveal(edit)
        XCTAssertFalse(edit.isEnabled, app.debugDescription)
        XCTAssertTrue(element("account.section.proxy.needsRefresh").exists, app.debugDescription)
        XCTAssertTrue(element("account.proxy.row").isEnabled, app.debugDescription)
        goBack()
        open(10)
        let direct = element("account.proxy.row")
        reveal(direct)
        XCTAssertFalse(direct.isEnabled, app.debugDescription)
    }

    // MARK: - 恢复原代理

    @MainActor func testRevertFallbackConfirmsAndReceiptsWithoutUndo() {
        openDetail(9)
        defer { diagnostics("account-menu-revert-final") }
        let fallback = element("account.proxy.fallback")
        reveal(fallback)
        XCTAssertTrue(fallback.label.contains("已回退：原代理 hk-01") && fallback.label.contains("原代理到期后已改为hk-02"), fallback.label)
        XCTAssertTrue(text("选中即生效，回执里可撤销。恢复原代理不能撤销。").exists, app.debugDescription)
        let revert = app.buttons["account.proxy.revert"]
        revert.tap()
        let alert = app.alerts["恢复原代理「hk-01」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["账号改回走 hk-01，出口 IP 随之改变。恢复后不能撤销。"].exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        confirmRevert()
        waitForReceipt("已恢复原代理「hk-01」")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(element("account.proxy.fallback").waitForNonExistence(timeout: 10), app.debugDescription)
        waitForLabel(element("account.proxy.row"), contains: "hk-01")
    }

    @MainActor func testRevertWhenNoLongerInFallbackRefreshes() {
        openDetail(9, arguments: [Fixture.notInFallback])
        defer { diagnostics("account-menu-revert-gone-final") }
        reveal(element("account.proxy.fallback"))
        confirmRevert()
        waitForReceipt("这个账号已不在回退状态")
        XCTAssertTrue(element("account.proxy.fallback").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testRevertOriginUnavailableOffersOriginDetail() {
        openDetail(9, arguments: [Fixture.originUnavailable])
        defer { diagnostics("account-menu-revert-origin-final") }
        reveal(element("account.proxy.fallback"))
        confirmRevert()
        waitForReceipt("原代理已删除、停用或过期，续期并启用后才能恢复")
        let view = app.buttons["receipt.action"]
        XCTAssertEqual(view.label, "查看原代理")
        view.tap()
        XCTAssertTrue(element("proxy.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["hk-01"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(element("account.proxy.fallback").waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - 删除账号

    @MainActor func testDeleteNeedsExactNameWhenFaceIDOff() {
        openDetail(10)
        defer { diagnostics("account-menu-delete-final") }
        chooseFromMenu("删除账号…")
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除账号「Grok-旧-01」？")
        XCTAssertTrue(element("delete.message").label.contains("站点 \(Fixture.site) · 删除后不能恢复。"), element("delete.message").label)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "删除账号")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("grok-旧-01")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Grok-旧-01")
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Grok-旧-01"].waitForNonExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已删除账号「Grok-旧-01」")
        // Back on the list, still scrolled to where the row was: it leaves once the list has been read again.
        XCTAssertTrue(app.navigationBars["账号"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["account.10"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// 60 §3.4: a refused check deletes nothing and says nothing; with Face ID nothing is typed.
    @MainActor func testDeleteWithFaceIDWhenEnabled() {
        openDetail(10, arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        chooseFromMenu("删除账号…")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("account.detail.card").exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        diagnostics("account-menu-delete-faceid-denied")
        app.terminate()
        openDetail(10, arguments: ["-ui-faceid-on"])
        defer { diagnostics("account-menu-delete-faceid-final") }
        chooseFromMenu("删除账号…")
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["delete.confirm"].tap()
        waitForReceipt("已删除账号「Grok-旧-01」")
        XCTAssertTrue(app.buttons["account.10"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testDeleteFailureShowsReasonAndStays() {
        openDetail(10, arguments: [Fixture.writeFail])
        defer { diagnostics("account-menu-delete-failure-final") }
        chooseFromMenu("删除账号…")
        let input = element("delete.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        input.tap()
        input.typeText("Grok-旧-01")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(receipt.label.hasPrefix("删除没有成功："), receipt.label)
        XCTAssertTrue(element("account.detail.card").exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Grok-旧-01"].exists, app.debugDescription)
    }

    // MARK: - 在 Web 中编辑

    @MainActor func testOpenInWebDeepLinkReceipt() {
        openDetail(4)
        defer { diagnostics("account-menu-web-final") }
        chooseFromMenu("在 Web 中编辑")
        waitForReceipt("已在浏览器打开「OpenAI-主力-01」的编辑页")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor func testOpenInWebFallbackReceiptWithoutCapability() {
        openDetail(4, arguments: [Fixture.without, Fixture.deepLink])
        defer { diagnostics("account-menu-web-fallback-final") }
        chooseFromMenu("在 Web 中编辑")
        waitForReceipt("已打开 Web 账号管理 · 已复制「OpenAI-主力-01」，可直接搜索")
    }

    /// A Bedrock account's credential error: the primary button opens the Web editor instead of a placeholder.
    @MainActor func testBedrockCredentialErrorOpensWeb() {
        openDetail(7, arguments: [Fixture.bedrock])
        defer { diagnostics("account-menu-bedrock-final") }
        let web = app.buttons["account.action.webCredential"]
        XCTAssertTrue(web.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(web.label, "在 Web 中更换凭据")
        web.tap()
        waitForReceipt("已在浏览器打开「OpenAI-备用-A」的编辑页")
        XCTAssertFalse(element("route.placeholder").exists, app.debugDescription)
    }

    /// C-1: a read-only token greys 编辑, 恢复原代理 and 删除账号…; 在 Web 中编辑 is no server write and stays.
    @MainActor func testReadOnlyTokenGreysProxyRevertAndDelete() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-readonly-token", Fixture.longWindows]; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-menu.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-readonly", in: "login.key")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        defer { diagnostics("account-menu-readonly-final") }
        open(9)
        let revert = app.buttons["account.proxy.revert"]
        reveal(revert)
        XCTAssertFalse(revert.isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["account.section.proxy.edit"].isEnabled, app.debugDescription)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("删除账号…").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuButton("删除账号…").isEnabled, app.debugDescription)
        let web = menuButton("在 Web 中编辑")
        XCTAssertTrue(web.isEnabled, app.debugDescription)
        web.tap()
        waitForReceipt("已在浏览器打开「Kimi-01」的编辑页")
    }

    /// 412 with a third value: 重新载入 keeps the picker open on the server's copy (us-west-3, another administrator's move), so
    /// its tick, the next save's version and that save's 撤销 all follow it rather than the copy the picker opened on.
    @MainActor func testProxyConflictReloadMovesPickerToServerCopy() {
        openDetail(4, arguments: [Fixture.proxyConflict])
        defer { diagnostics("account-menu-proxy-conflict-final") }
        openPicker()
        let original = element("account.proxy.option.2")
        XCTAssertTrue(original.isSelected, app.debugDescription)
        element("account.proxy.option.1").tap()
        let alert = app.alerts["账号已被其他人修改"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["重新载入"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil(element("account.proxy.option.5"), "isSelected == true"), app.debugDescription)
        XCTAssertFalse(original.isSelected, app.debugDescription)
        original.tap()
        waitForReceipt("已保存：代理 → sg-01")
        XCTAssertEqual(app.buttons["receipt.action"].label, "撤销")
        XCTAssertTrue(element("account.proxy.picker").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        let row = element("account.proxy.row")
        reveal(row)
        waitForLabel(row, contains: "us-west-3")
    }

    /// S2-16, U17: a Bedrock account's 凭据 shows the stored secret and 在 Web 中更换凭据; ⋯ adds no credential item.
    @MainActor func testBedrockCredentialSectionOpensWebAndMenuHasNoKeyItem() {
        openDetail(7, arguments: [Fixture.bedrock])
        defer { diagnostics("account-menu-bedrock-cred-final") }
        let secret = element("account.cred.secret")
        reveal(secret)
        XCTAssertEqual(secret.value as? String, "已设置 · 不可查看")
        XCTAssertFalse(app.buttons["account.cred.key.replace"].exists, app.debugDescription)
        let web = app.buttons["account.cred.web"]
        reveal(web)
        XCTAssertTrue(text("已保存的凭据不可查看；这类凭据请在 Web 中更换。").exists, app.debugDescription)
        web.tap()
        waitForReceipt("已在浏览器打开「OpenAI-备用-A」的编辑页")
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("删除账号…").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuButton("更换 API Key…").exists, app.debugDescription)
        XCTAssertFalse(menuButton("刷新令牌").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func openDetail(_ id: Int, arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments
        app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-menu.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        open(id)
    }
    /// From the account list: the row, then the detail's card.
    @MainActor private func open(_ id: Int) {
        XCTAssertTrue(app.buttons["accounts.chip.all"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["account.\(id)"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// 编辑 enables once the page has read the account.
    @MainActor private func openPicker() {
        let edit = app.buttons["account.section.proxy.edit"]
        reveal(edit)
        XCTAssertTrue(waitUntil(edit, "isEnabled == true", timeout: 10), app.debugDescription)
        edit.tap()
        XCTAssertTrue(element("account.proxy.option.direct").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func confirmRevert() {
        app.buttons["account.proxy.revert"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["恢复原代理"].tap()
    }
    @MainActor private func chooseFromMenu(_ title: String) {
        app.buttons["account.detail.more"].tap()
        let item = menuButton(title)
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    /// System menu items are found by their title.
    @MainActor private func menuButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)], timeout: timeout) == .completed
    }
    @MainActor private func text(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Lists create rows as they scroll in; the drag stops before the floating tab bar, and the list settles before a tap.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if item.exists && item.isHittable && isAboveTabBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20
                : app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private func isAboveTabBar(_ item: XCUIElement) -> Bool {
        let bar = app.tabBars.firstMatch
        return !bar.exists || item.frame.maxY <= bar.frame.minY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
