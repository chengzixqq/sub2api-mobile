import XCTest

/// 20 §3.3 凭据 and §6 (S2-16) on the fixture site's demo accounts (DemoData+Accounts, DemoData+AccountCredentials):
/// OpenAI-备用-A (#7) holds a refused key and was stopped when it failed; OpenAI-主力-01 (#4) is a healthy key account on a relay;
/// Claude-官方-01 (#1) has 5 hours of token left, Claude-官方-02 (#2) 40 minutes and no refresh token; Kimi-01 (#9) is a
/// multi-protocol account. Face ID is off unless a test turns it on.
final class AccountCredentialUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "凭据站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let refreshFail = "-ui-account-refresh-fail"
        static let legacyServer = "-ui-account-legacy-server"
        static let without = "-ui-without-capabilities"
        static let tokenError = "-ui-account-token-error"
        static let tokenInactive = "-ui-account-token-inactive"
        static let reauthPersistFail = "-ui-account-reauth-persist-fail"
        static let reauthUnsupported = "-ui-account-reauth-unsupported"
        static let keyFooter = "已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。"
        static let tokenFooter = "令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。"
    }

    /// 20 §2.3 / §6.4: the card's 更换 API Key… → the sheet → “已更换 API Key”; the row and the button row follow the mark, which a
    /// passing test (it clears the error) ends again.
    @MainActor func testReplaceKeyFromStatusCardShowsReceiptAndRowChanges() {
        openDetail(7)
        defer { diagnostics("account-cred-replace-final") }
        let hint = element("account.cred.key.hint")
        reveal(hint)
        XCTAssertEqual(hint.label, "上游拒绝了这个密钥（401），需要更换")
        let fix = app.buttons["account.action.replaceKey"]
        reveal(fix, towardBottom: false)
        fix.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("account.cred.target").label, "OpenAI-备用-A · 点按底部按钮后立即生效")
        XCTAssertEqual(element("account.cred.key.preview").label, "当前密钥已设置，不可查看")
        let submit = app.buttons["account.cred.key.submit"]
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        XCTAssertFalse(element("account.cred.key.note").label.contains("Face ID"), element("account.cred.key.note").label)
        typeKey("sk-proj-EXAMPLEKEY0000abcd")
        waitForLabel(element("account.cred.key.preview"), equals: "新密钥 sk-proj-••••abcd · 26 个字符")
        diagnostics("account-cred-replace-sheet")
        submit.tap()
        waitForReceipt("已更换 API Key")
        XCTAssertEqual(app.buttons["receipt.action"].label, "测试")
        XCTAssertTrue(element("account.cred.key.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        let test = app.buttons["account.action.test"]
        XCTAssertTrue(test.waitForExistence(timeout: 5) && app.buttons["account.action.recover"].exists, app.debugDescription)
        XCTAssertLessThan(test.frame.minX, app.buttons["account.action.recover"].frame.minX)
        XCTAssertFalse(app.buttons["account.action.replaceKey"].exists, app.debugDescription)
        let key = element("account.cred.key")
        reveal(key)
        XCTAssertNotNil((key.value as? String)?.range(of: #"^已更换 · \d{2}:\d{2}$"#, options: .regularExpression), String(describing: key.value))
        XCTAssertEqual(element("account.cred.key.hint").label, "已更换：测试连接通过后自动清除错误（仍暂停调度）")
        diagnostics("account-cred-replaced")
        // The test passes and clears the error, which ends the mark.
        reveal(test, towardBottom: false)
        test.tap()
        XCTAssertTrue(element("account.test.sheet").waitForExistence(timeout: 10), app.debugDescription)
        let detail = element("account.test.result.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.test.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["account.action.resume"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(key)
        waitForValue(key, equals: "已设置 · 不可查看")
        XCTAssertFalse(element("account.cred.key.hint").exists, app.debugDescription)
    }

    /// 60 §3.4: with Face ID on the note says so; a refused check sends nothing and the sheet stays.
    @MainActor func testFaceIDOnAddsNoteAndFailedCheckSendsNothing() {
        openDetail(7, arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("account-cred-faceid-final") }
        let fix = app.buttons["account.action.replaceKey"]
        XCTAssertTrue(fix.waitForExistence(timeout: 10), app.debugDescription)
        fix.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.cred.key.note").label.hasSuffix("。点按后验证 Face ID"), element("account.cred.key.note").label)
        typeKey("sk-test-EXAMPLE0001")
        let submit = app.buttons["account.cred.key.submit"]
        XCTAssertTrue(waitUntil(submit, "isEnabled == true"), app.debugDescription)
        submit.tap()
        XCTAssertFalse(app.staticTexts["receipt.text"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(element("account.cred.key.sheet").exists && waitUntil(submit, "isEnabled == true"), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["account.action.replaceKey"].exists, app.debugDescription)
        let key = element("account.cred.key")
        reveal(key)
        waitForValue(key, equals: "已设置 · 不可查看")
    }

    /// A healthy key account: ⋯ and the row's 更换 open the same sheet; the receipt's 测试 opens the test; the buttons stay.
    @MainActor func testHealthyKeyAccountReplacesFromMenuAndRow() {
        openDetail(4)
        defer { diagnostics("account-cred-healthy-final") }
        app.buttons["account.detail.more"].tap()
        let item = menuItem("更换 API Key…")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        let order = ["更换 API Key…", "在 Web 中编辑", "删除账号…"].map { menuItem($0).frame.minY }
        XCTAssertEqual(order, order.sorted(), app.debugDescription)
        item.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        let replace = app.buttons["account.cred.key.replace"]
        reveal(replace)
        XCTAssertTrue(waitUntil(replace, "isEnabled == true", timeout: 10), app.debugDescription)
        replace.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        typeKey("sk-test-EXAMPLE9999")
        app.buttons["account.cred.key.submit"].tap()
        waitForReceipt("已更换 API Key")
        XCTAssertTrue(element("account.cred.key.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("account.test.sheet").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.test.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        let key = element("account.cred.key")
        reveal(key)
        XCTAssertNotNil((key.value as? String)?.range(of: #"^已更换 · \d{2}:\d{2}$"#, options: .regularExpression), String(describing: key.value))
        XCTAssertFalse(element("account.cred.key.hint").exists, app.debugDescription)
        let test = app.buttons["account.action.test"], stop = app.buttons["account.action.stop"]
        reveal(test, towardBottom: false)
        XCTAssertTrue(stop.exists, app.debugDescription)
        XCTAssertLessThan(test.frame.minX, stop.frame.minX)
    }

    /// 20 §6.3 Base URL: the check, 改回官方地址 (null) and a new address, each with 测试; a multi-protocol account goes to the Web.
    @MainActor func testBaseURLValidationSaveAndRestoreOfficial() {
        openDetail(4)
        defer { diagnostics("account-cred-baseurl-final") }
        let row = element("account.cred.baseurl")
        reveal(row)
        waitForValue(row, equals: "https://relay.example.com/v1")
        openBaseURLSheet()
        let submit = app.buttons["account.cred.baseurl.submit"], message = element("account.cred.baseurl.message")
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        app.buttons["account.cred.baseurl.clear"].tap()
        waitForLabel(message, equals: "留空：使用官方地址")
        XCTAssertEqual(submit.label, "改回官方地址")
        typeURL("relay.example.com")
        waitForLabel(message, equals: "地址要以 http:// 或 https:// 开头")
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        app.buttons["account.cred.baseurl.clear"].tap()
        XCTAssertTrue(waitUntil(submit, "isEnabled == true"), app.debugDescription)
        submit.tap()
        waitForReceipt("已改回官方地址")
        XCTAssertEqual(app.buttons["receipt.action"].label, "测试")
        reveal(row)
        waitForValue(row, equals: "官方地址")
        openBaseURLSheet()
        typeURL("https://new.example.com/v1")
        waitForLabel(message, equals: "请求改发到这个地址")
        XCTAssertEqual(submit.label, "保存 Base URL")
        submit.tap()
        waitForReceipt("已保存 Base URL")
        reveal(row)
        waitForValue(row, equals: "https://new.example.com/v1")
        // S2D1-22: Kimi's endpoints are edited on the Web.
        goBack()
        open(9)
        let web = app.buttons["account.cred.baseurl.web"]
        reveal(web)
        XCTAssertFalse(app.buttons["account.cred.baseurl.edit"].exists, app.debugDescription)
        web.tap()
        waitForReceipt("已在浏览器打开「Kimi-01」的编辑页")
    }

    /// 20 §6.4: 刷新令牌 runs at once (no question) and its receipt has no button; ⋯ offers the same, and no 更换 API Key….
    @MainActor func testRefreshTokenUpdatesRowAndShowsReceipt() {
        openDetail(1)
        defer { diagnostics("account-cred-refresh-final") }
        let token = element("account.cred.token")
        reveal(token)
        XCTAssertEqual(element("account.cred.token.badge").label, "有效")
        XCTAssertNotNil(token.label.range(of: #"^[45] 小时后（到期 \d{2}:\d{2}）$"#, options: .regularExpression), token.label)
        XCTAssertFalse(element("account.cred.token.note").exists, app.debugDescription)
        let refresh = app.buttons["account.cred.refresh"]
        reveal(refresh)
        XCTAssertEqual(refresh.label, "刷新令牌")
        XCTAssertEqual(refresh.value as? String, "立即生效")
        XCTAssertTrue(app.buttons["account.cred.reauthorize"].exists, app.debugDescription)
        refresh.tap()
        waitForReceipt(matching: #"^已刷新令牌 · 新令牌 \d{2}:\d{2} 到期$"#)
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        waitForLabel(token, matching: #"^8 小时后（到期 \d{2}:\d{2}）$"#)
        diagnostics("account-cred-refreshed")
        app.buttons["account.detail.more"].tap()
        let item = menuItem("刷新令牌")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuItem("更换 API Key…").exists, app.debugDescription)
        item.tap()
        waitForReceipt(matching: #"^已刷新令牌 · 新令牌 \d{2}:\d{2} 到期$"#)
    }

    @MainActor func testRefreshTokenFailureShowsReason() {
        openDetail(1, arguments: [Fixture.refreshFail])
        defer { diagnostics("account-cred-refresh-fail-final") }
        let refresh = app.buttons["account.cred.refresh"]
        reveal(refresh)
        let before = element("account.cred.token").label
        refresh.tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(receipt.label.hasPrefix("刷新令牌没有成功："), receipt.label)
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertEqual(element("account.cred.token").label, before)
    }

    /// C-1: a read-only token greys every credential write; the section says “只读令牌” once.
    @MainActor func testReadOnlyTokenGreysEveryCredentialEntry() {
        launchAndLogin(arguments: ["-ui-readonly-token"], readOnly: true)
        defer { diagnostics("account-cred-readonly-final") }
        open(4)
        let edit = app.buttons["account.cred.baseurl.edit"], replace = app.buttons["account.cred.key.replace"]
        reveal(edit)
        XCTAssertFalse(edit.isEnabled || replace.isEnabled, app.debugDescription)
        XCTAssertEqual(element("account.section.cred.meta").label, "只读令牌")
        goBack()
        open(1)
        let refresh = app.buttons["account.cred.refresh"]
        reveal(refresh)
        XCTAssertFalse(refresh.isEnabled || app.buttons["account.cred.reauthorize"].isEnabled, app.debugDescription)
        goBack()
        open(7)
        XCTAssertFalse(app.buttons["account.action.replaceKey"].isEnabled, app.debugDescription)
        let key = app.buttons["account.cred.key.replace"]
        reveal(key)
        XCTAssertFalse(key.isEnabled, app.debugDescription)
        app.buttons["account.detail.more"].tap()
        let item = menuItem("更换 API Key…")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(item.isEnabled, app.debugDescription)
    }

    /// 20 §3.1: 基础 · 调度 · 凭据 · 代理; a token close to its end, without auto refresh, and the two footnotes.
    @MainActor func testCredentialSectionOrderAndTokenRows() {
        openDetail(4)
        defer { diagnostics("account-cred-order-final") }
        reveal(text(Fixture.keyFooter))
        goBack()
        open(2)
        let sched = element("account.section.sched"), cred = element("account.section.cred"), proxy = element("account.section.proxy")
        reveal(cred)
        XCTAssertTrue(sched.exists && proxy.exists, app.debugDescription)
        XCTAssertLessThan(sched.frame.minY, cred.frame.minY)
        XCTAssertLessThan(cred.frame.minY, proxy.frame.minY)
        let token = element("account.cred.token")
        reveal(token)
        XCTAssertEqual(element("account.cred.token.badge").label, "即将到期")
        XCTAssertNotNil(token.label.range(of: #"^\d+ 分钟后（到期 \d{2}:\d{2}）$"#, options: .regularExpression), token.label)
        XCTAssertEqual(element("account.cred.token.note").label, "不会自动刷新")
        let footer = text(Fixture.tokenFooter)
        reveal(footer)
        let reauthorize = app.buttons["account.cred.reauthorize"]
        reveal(reauthorize)
        reauthorize.tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["account.reauth.cancel"].tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// S2D1-09: a server older than credential redaction takes no credential PUT; the sheet points to the Web.
    @MainActor func testLegacyServerKeyReplacementPointsToWeb() {
        openDetail(4, arguments: [Fixture.legacyServer, Fixture.without, "accounts.patch"])
        defer { diagnostics("account-cred-legacy-final") }
        let replace = app.buttons["account.cred.key.replace"]
        reveal(replace)
        XCTAssertTrue(waitUntil(replace, "isEnabled == true", timeout: 10), app.debugDescription)
        replace.tap()
        XCTAssertTrue(element("account.cred.key.sheet").waitForExistence(timeout: 10), app.debugDescription)
        typeKey("sk-test-EXAMPLE4242")
        app.buttons["account.cred.key.submit"].tap()
        let message = element("account.edit.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(message.label, "这个站点版本过旧，凭据相关设置请在 Web 中修改")
        XCTAssertTrue(element("account.cred.key.sheet").exists, app.debugDescription)
        app.buttons["account.edit.openWeb"].tap()
        waitForReceipt("已在浏览器打开「OpenAI-主力-01」的编辑页")
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = [], readOnly: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-credentials.example.invalid", in: "login.url")
        if readOnly {
            let method = element("login.method.accessToken"); reveal(method); method.tap()
            enter("sat_fixture-readonly", in: "login.key")
        } else {
            enter("admin@example.com", in: "login.email")
            enter("fixture-password", in: "login.password")
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
    }
    @MainActor private func openDetail(_ id: Int, arguments: [String] = []) {
        launchAndLogin(arguments: arguments)
        open(id)
    }
    /// From the account list: the row, then the detail's card once the page has read the account.
    @MainActor private func open(_ id: Int) {
        XCTAssertTrue(app.buttons["accounts.chip.all"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["account.\(id)"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openBaseURLSheet() {
        let edit = app.buttons["account.cred.baseurl.edit"]
        reveal(edit)
        XCTAssertTrue(waitUntil(edit, "isEnabled == true", timeout: 10), app.debugDescription)
        edit.tap()
        XCTAssertTrue(element("account.cred.baseurl.sheet").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// PasteButton asks the system; the tests type instead. Return ends the editing, so the keyboard leaves the button free.
    @MainActor private func typeKey(_ key: String) {
        let field = element("account.cred.key.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(key + "\n")
    }
    @MainActor private func typeURL(_ url: String) {
        let field = element("account.cred.baseurl.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(url + "\n")
    }
    /// System menu items by their title, apart from the page's own buttons of the same title.
    @MainActor private func menuItem(_ label: String) -> XCUIElement {
        let format = "label == %@ AND NOT (identifier BEGINSWITH 'account.cred.') AND NOT (identifier BEGINSWITH 'account.action.')"
            + " AND NOT (identifier BEGINSWITH 'account.adv.')"
        return app.buttons.matching(NSPredicate(format: format, label)).firstMatch
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        waitForLabel(app.staticTexts["receipt.text"], equals: text, file: file, line: line)
    }
    @MainActor private func waitForReceipt(matching pattern: String, file: StaticString = #filePath, line: UInt = #line) {
        waitForLabel(app.staticTexts["receipt.text"], matching: pattern, file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "\(item.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    /// NSPredicate's MATCHES misses some patterns next to full-width brackets, so the label is read and matched here.
    @MainActor private func waitForLabel(_ item: XCUIElement, matching pattern: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        var label = ""
        repeat {
            label = item.exists ? item.label : ""
            if label.range(of: pattern, options: .regularExpression) != nil { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        XCTFail("\(label) ≁ \(pattern)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForValue(_ item: XCUIElement, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: 10), .completed, "\(String(describing: item.value))\n\(app.debugDescription)",
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

    // MARK: - 重新授权（S2-17）

    /// 20 §6.3: the 凭据 row opens the sheet; the link, the pasted code, 替换令牌, and the receipt's 测试. The UI tests paste: the
    /// App's own callback listener needs a real device and Safari.
    @MainActor func testReauthorizeFromCredentialRowReplacesTokenAndOffersTest() {
        openDetail(1)
        defer { diagnostics("account-reauth-row-final") }
        openReauthorizeFromRow()
        let target = element("account.reauth.target")
        XCTAssertTrue(target.label.contains("授权走已保存的代理 hk-02；分组、并发和代理设置不变"), target.label)
        let submit = app.buttons["account.reauth.submit"]
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        XCTAssertEqual(element("oauth.scope").label, "完整权限")
        generateLink()
        waitForLabel(element("oauth.countdown"), matching: #"^已生成 · [0-9]+:[0-9]{2} 内有效$"#)
        XCTAssertTrue(element("oauth.proxyHint").label.contains("出口打开"), app.debugDescription)
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        typeCode("demo-code#demo-state")
        let note = element("account.reauth.note")
        reveal(note)
        XCTAssertTrue(note.label.hasPrefix("点按后立即保存新令牌") && !note.label.contains("Face ID"), note.label)
        diagnostics("account-reauth-row-ready")
        replaceToken()
        waitForReceipt("已重新授权 · 令牌已替换")
        XCTAssertEqual(app.buttons["receipt.action"].label, "测试")
        XCTAssertTrue(element("account.reauth.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("account.test.sheet").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// Another method drops the link and the code; the receipt names the new type.
    @MainActor func testReauthorizeSwitchingToSetupTokenDropsLinkAndConvertsType() {
        openDetail(1)
        defer { diagnostics("account-reauth-setup-final") }
        chooseReauthorizeFromMenu()
        XCTAssertTrue(element("account.reauth.sheet").waitForExistence(timeout: 10), app.debugDescription)
        generateLink()
        typeCode("demo-code#demo-state")
        let method = app.segmentedControls["oauth.method"]
        reveal(method, towardBottom: false)
        method.buttons["Setup Token"].tap()
        XCTAssertTrue(element("oauth.link").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("oauth.scope").label, "只授予推理权限 · 授权后账号类型改为 Setup Token")
        XCTAssertTrue(app.buttons["oauth.generate"].exists && !app.buttons["account.reauth.submit"].isEnabled, app.debugDescription)
        generateLink()
        typeCode("demo-setup#demo-state")
        replaceToken()
        waitForReceipt(matching: "^已重新授权 · 账号类型改为 Setup.Token · 令牌已替换$")
    }

    /// 20 §6.4-1: a stopped account asks before the sheet; cancelling sends nothing, going on enables it.
    @MainActor func testReauthorizeInactiveAccountAsksBeforeOpening() {
        openDetail(2, arguments: [Fixture.tokenInactive])
        defer { diagnostics("account-reauth-inactive-final") }
        let alert = app.alerts["重新授权「Claude-官方-02」？"]
        chooseReauthorizeFromMenu()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.staticTexts["这个账号现在是停用状态。授权后账号会被重新启用并参与调度。"].exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertFalse(element("account.reauth.sheet").waitForExistence(timeout: 2), app.debugDescription)
        chooseReauthorizeFromMenu()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        alert.buttons["继续授权"].tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForExistence(timeout: 10), app.debugDescription)
        generateLink()
        typeCode("demo-code#demo-state")
        replaceToken()
        waitForReceipt("已重新授权 · 已启用账号 · 参与调度")
        XCTAssertEqual(app.buttons["receipt.action"].label, "测试")
    }

    /// 20 §2.3: a refused token leads with 重新授权…; the error is cleared, the switch stays off, and 启用调度 turns it on.
    @MainActor func testCredentialErrorTokenAccountLeadsWithReauthorizeAndOffersEnableScheduling() {
        openDetail(2, arguments: [Fixture.tokenError])
        defer { diagnostics("account-reauth-error-final") }
        let fix = app.buttons["account.action.reauthorize"], recover = app.buttons["account.action.recover"]
        XCTAssertTrue(fix.waitForExistence(timeout: 10) && recover.exists && app.buttons["account.action.test"].exists, app.debugDescription)
        XCTAssertLessThan(fix.frame.minX, recover.frame.minX)
        reveal(fix, towardBottom: false)
        fix.tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForExistence(timeout: 10), app.debugDescription)
        let note = element("account.reauth.note")
        reveal(note)
        XCTAssertTrue(note.label.contains("出错时已停止调度，之后仍暂停。"), note.label)
        generateLink()
        typeCode("demo-code#demo-state")
        replaceToken()
        waitForReceipt("已重新授权 · 已清除错误 · 仍暂停调度")
        XCTAssertEqual(app.buttons["receipt.action"].label, "启用调度")
        app.buttons["receipt.action"].tap()
        waitForReceipt("已启用调度")
        XCTAssertTrue(app.buttons["account.action.stop"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// 20 §0.5 REAUTH_PERSIST_FAILED: the read-back shows nothing saved, so the sheet offers 重试保存 with the same session and
    /// greys 替换令牌 until then.
    @MainActor func testReauthorizePersistFailureOffersRetrySave() {
        openDetail(1, arguments: [Fixture.reauthPersistFail])
        defer { diagnostics("account-reauth-persist-final") }
        openReauthorizeFromRow()
        generateLink()
        typeCode("demo-code#demo-state")
        replaceToken()
        let failed = element("account.reauth.persistFailed")
        XCTAssertTrue(failed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(failed.label, "令牌已换到，但没保存成功")
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["account.reauth.submit"].isEnabled, app.debugDescription)
        diagnostics("account-reauth-persist-failed")
        let retry = app.buttons["account.reauth.retrySave"]
        reveal(retry)
        retry.tap()
        waitForReceipt("已重新授权 · 令牌已替换")
        XCTAssertTrue(element("account.reauth.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// 60 §3.4: with Face ID on the note says so; a refused check sends nothing and keeps the code.
    @MainActor func testReauthorizeFaceIDDeniedKeepsSheetAndSendsNothing() {
        openDetail(1, arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("account-reauth-faceid-final") }
        openReauthorizeFromRow()
        generateLink()
        typeCode("demo-code#demo-state")
        let note = element("account.reauth.note")
        reveal(note)
        XCTAssertTrue(note.label.hasSuffix("；之后验证 Face ID"), note.label)
        replaceToken()
        XCTAssertFalse(app.staticTexts["receipt.text"].waitForExistence(timeout: 3), app.debugDescription)
        let submit = app.buttons["account.reauth.submit"]
        XCTAssertTrue(element("account.reauth.sheet").exists && waitUntil(submit, "isEnabled == true"), app.debugDescription)
        XCTAssertEqual(element("oauth.code").value as? String, "demo-code#demo-state")
        app.buttons["account.reauth.cancel"].tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// 20 §0.5 REAUTH_UNSUPPORTED (a shadow account): the reason and 在 Web 中编辑, no receipt.
    @MainActor func testReauthorizeUnsupportedAccountOffersEditInWeb() {
        openDetail(1, arguments: [Fixture.reauthUnsupported])
        defer { diagnostics("account-reauth-unsupported-final") }
        openReauthorizeFromRow()
        generateLink()
        typeCode("demo-code#demo-state")
        replaceToken()
        let unsupported = element("account.reauth.unsupported")
        XCTAssertTrue(unsupported.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(unsupported.label, "影子账号的凭据跟随母账号，请重新授权母账号")
        XCTAssertTrue(app.buttons["account.reauth.editInWeb"].isEnabled, app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
    }

    /// C-1: a read-only token greys every 重新授权… entry.
    @MainActor func testReadOnlyTokenGreysReauthorizeEntries() {
        launchAndLogin(arguments: ["-ui-readonly-token", Fixture.tokenError], readOnly: true)
        defer { diagnostics("account-reauth-readonly-final") }
        open(2)
        let fix = app.buttons["account.action.reauthorize"]
        XCTAssertTrue(fix.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(fix.isEnabled, app.debugDescription)
        goBack()
        open(1)
        let row = app.buttons["account.cred.reauthorize"]
        reveal(row)
        XCTAssertFalse(row.isEnabled, app.debugDescription)
        app.buttons["account.detail.more"].tap()
        let item = menuItem("重新授权…")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(item.isEnabled, app.debugDescription)
        XCTAssertFalse(element("account.reauth.sheet").exists, app.debugDescription)
    }

    /// 20 §6.2 退路: without accounts.reauthorize the code is exchanged and the token applied.
    @MainActor func testReauthorizeWithoutEndpointFallsBackToExchangeAndApply() {
        openDetail(1, arguments: [Fixture.without, "accounts.reauthorize"])
        defer { diagnostics("account-reauth-fallback-final") }
        openReauthorizeFromRow()
        generateLink()
        typeCode("demo-code#demo-state")
        replaceToken()
        waitForReceipt("已重新授权 · 令牌已替换")
        XCTAssertTrue(element("account.reauth.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor private func openReauthorizeFromRow() {
        let row = app.buttons["account.cred.reauthorize"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.reauth.sheet").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func chooseReauthorizeFromMenu() {
        app.buttons["account.detail.more"].tap()
        let item = menuItem("重新授权…")
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    @MainActor private func generateLink() {
        let generate = app.buttons["oauth.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5), app.debugDescription)
        reveal(generate, towardBottom: false)
        generate.tap()
        XCTAssertTrue(element("oauth.link").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// PasteButton asks the system; the tests type instead, and Return closes the keyboard.
    @MainActor private func typeCode(_ code: String) {
        let field = element("oauth.code")
        reveal(field)
        field.tap()
        field.typeText(code + "\n")
    }
    @MainActor private func replaceToken() {
        let submit = app.buttons["account.reauth.submit"]
        reveal(submit)
        XCTAssertTrue(waitUntil(submit, "isEnabled == true"), app.debugDescription)
        submit.tap()
    }
}
