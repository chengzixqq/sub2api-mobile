import XCTest

/// S6-07: 批量生成兑换码 (60 §10) and the list's + interception (60 §8.4). The fixture server answers a new batch with its codes
/// (5000 + 100 × the batch id's first byte on) and adds them to the list; `-ui-redeem-generate-unknown / -replayed / -rejected`
/// change the answer, `-ui-redeem-no-subscription-groups` empties the subscription groups (RedeemFixtures). `-ui-pending-money`
/// gives the site a batch of 20 × $10.00 awaiting its result, `-ui-pending-old-site` an older login's 10 × $5.00 (S3-07).
final class RedeemGenerateUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let site = "生成验收"

    @MainActor func testBalanceBatchConfirmsAndShowsResult() {
        launchAndLogin()
        defer { diagnostics("generate-balance-final") }
        openGenerate()
        for type in ["balance", "concurrency", "subscription", "invitation"] {
            XCTAssertTrue(app.buttons["redeem.generate.type.\(type)"].exists, type + "\n" + app.debugDescription)
        }
        XCTAssertTrue(element("redeem.generate.steps").label.contains("第 1 步，共 3 步"), app.debugDescription)
        app.buttons["redeem.generate.type.balance"].tap()
        let amount = element("redeem.generate.amount"), next = app.buttons["redeem.generate.next"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(amount.label, "$0")
        XCTAssertFalse(next.isEnabled)
        press("1", "0")
        XCTAssertEqual(amount.label, "$10")
        app.buttons["redeem.generate.count.pick.20"].tap()
        XCTAssertTrue(element("redeem.generate.preview").label.contains("$200.00"), element("redeem.generate.preview").label)
        diagnostics("generate-balance-value")
        next.tap()
        let submit = app.buttons["redeem.generate.submit"]
        XCTAssertTrue(waitForLabel(submit, equalTo: "生成 20 个兑换码"), submit.label)
        for (row, value) in [("type", "余额"), ("each", "$10.00"), ("count", "× 20"), ("expiry", "永不过期"), ("total", "$200.00")] {
            XCTAssertTrue(element("money.pending.receipt.\(row)").label.contains(value), "\(row) ∌ \(value)\n\(app.debugDescription)")
        }
        XCTAssertFalse(element("redeem.generate.faceid").exists)
        diagnostics("generate-balance-receipt")
        submit.tap()
        let confirm = waitForAlert("生成 20 个余额兑换码，合计 $200.00？")
        XCTAssertTrue(labelled(containing: "站点 \(Self.site) · 每个 $10.00", in: confirm).exists, app.debugDescription)
        confirm.buttons["生成 $200.00"].tap()
        XCTAssertTrue(waitForLabel(element("redeem.result.header.title"), equalTo: "已生成 20 个兑换码"), app.debugDescription)
        let copyAll = app.buttons["redeem.result.copyAll"]
        XCTAssertTrue(copyAll.label.contains("全部复制（20 个，每行一个）"), copyAll.label)
        copyAll.tap()
        XCTAssertTrue(waitForLabel(copyAll, containing: "已复制全部 20 个"), copyAll.label)
        diagnostics("generate-balance-result")
        close()
        // The list reads page 1 and the counts again: 11 + 20.
        XCTAssertTrue(text("\(Self.site) · 31 个").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("redeem.pending.banner").exists, app.debugDescription)
    }

    @MainActor func testReplayedResultSaysFetched() {
        launchAndLogin(["-ui-redeem-generate-replayed"])
        defer { diagnostics("generate-replayed-final") }
        openGenerate()
        generateInvitations()
        XCTAssertTrue(waitForLabel(element("redeem.result.header.title"), equalTo: "已生成 1 个兑换码（服务器已有这一批，已取回）"), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.result.copyAll"].label.contains("复制兑换码"), app.buttons["redeem.result.copyAll"].label)
    }

    @MainActor func testFaceIDAboveThresholdIsVerified() {
        launchAndLogin(["-ui-faceid-on"])
        defer { diagnostics("generate-faceid-final") }
        openGenerate()
        app.buttons["redeem.generate.type.balance"].tap()
        press("1", "0")
        app.buttons["redeem.generate.count.pick.10"].tap()
        app.buttons["redeem.generate.next"].tap()
        // A total of exactly $100 is not above the threshold.
        XCTAssertTrue(waitForLabel(app.buttons["redeem.generate.submit"], equalTo: "生成 10 个兑换码"), app.debugDescription)
        XCTAssertFalse(element("redeem.generate.faceid").exists, app.debugDescription)
        app.buttons["redeem.generate.back"].tap()
        app.buttons["redeem.generate.count.pick.20"].tap()
        app.buttons["redeem.generate.next"].tap()
        let line = "合计超过 $100，确认后验证 Face ID。"
        XCTAssertTrue(waitForLabel(element("redeem.generate.faceid"), containing: line), app.debugDescription)
        diagnostics("generate-faceid-note")
        app.buttons["redeem.generate.submit"].tap()
        let confirm = waitForAlert("生成 20 个余额兑换码，合计 $200.00？")
        XCTAssertTrue(labelled(containing: line, in: confirm).exists, app.debugDescription)
        confirm.buttons["生成 $200.00"].tap()
        XCTAssertTrue(waitForLabel(element("redeem.result.header.title"), equalTo: "已生成 20 个兑换码"), app.debugDescription)
    }

    @MainActor func testDeniedFaceIDSendsNothing() {
        launchAndLogin(["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("generate-faceid-denied-final") }
        openGenerate()
        app.buttons["redeem.generate.type.balance"].tap()
        press("1", "0")
        app.buttons["redeem.generate.count.pick.20"].tap()
        app.buttons["redeem.generate.next"].tap()
        let submit = app.buttons["redeem.generate.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), app.debugDescription)
        submit.tap()
        waitForAlert("生成 20 个余额兑换码，合计 $200.00？").buttons["生成 $200.00"].tap()
        // Nothing saved, nothing sent: still step 3, the button ready again.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND label == %@", "生成 20 个兑换码"), object: submit)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 10), .completed, app.debugDescription)
        XCTAssertFalse(element("redeem.result.header.title").exists, app.debugDescription)
        diagnostics("generate-faceid-denied")
        leaveWizard()
        XCTAssertFalse(element("redeem.pending.banner").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(text("\(Self.site) · 11 个").exists, app.debugDescription)
    }

    @MainActor func testSubscriptionWithoutGroupsCannotAdvance() {
        launchAndLogin(["-ui-redeem-no-subscription-groups"])
        defer { diagnostics("generate-no-groups-final") }
        openGenerate()
        app.buttons["redeem.generate.type.subscription"].tap()
        XCTAssertTrue(element("redeem.generate.noGroups").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("redeem.generate.noGroups").label, "站点还没有订阅类型的分组")
        XCTAssertFalse(app.buttons["redeem.generate.next"].isEnabled, app.debugDescription)
        diagnostics("generate-no-groups")
        app.terminate()

        launchAndLogin()
        openGenerate()
        app.buttons["redeem.generate.type.subscription"].tap()
        let group = app.buttons["redeem.generate.group.4"]
        XCTAssertTrue(group.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(group.isSelected && group.label == "企业专线", app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.generate.days.30"].isSelected, app.debugDescription)
        app.buttons["redeem.generate.days.custom"].tap()
        XCTAssertFalse(app.buttons["redeem.generate.next"].isEnabled, app.debugDescription)
        app.buttons["redeem.generate.days.90"].tap()
        XCTAssertTrue(app.buttons["redeem.generate.next"].isEnabled, app.debugDescription)
        app.buttons["redeem.generate.next"].tap()
        XCTAssertTrue(element("money.pending.receipt.each").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("money.pending.receipt.each").label.contains("企业专线 · 90 天"), element("money.pending.receipt.each").label)
    }

    @MainActor func testUnknownResultTurnsIntoPendingPage() {
        launchAndLogin(["-ui-redeem-generate-unknown"])
        defer { diagnostics("generate-unknown-final") }
        openGenerate()
        app.buttons["redeem.generate.type.concurrency"].tap()
        XCTAssertTrue(labelled(containing: "增加并发 +1").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["redeem.generate.next"].tap()
        app.buttons["redeem.generate.submit"].tap()
        waitForAlert("生成 1 个并发数兑换码？").buttons["生成 1 个"].tap()
        XCTAssertTrue(waitForLabel(element("money.pending.header.title"), equalTo: "请求可能已提交"), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.reconcile.check"].exists && app.buttons["redeem.reconcile.retry"].exists, app.debugDescription)
        diagnostics("generate-unknown")
        close()
        XCTAssertTrue(element("redeem.pending.banner").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "1 个 × +1 并发").exists, app.debugDescription)
    }

    @MainActor func testRejectedReturnsToStepThree() {
        launchAndLogin(["-ui-redeem-generate-rejected"])
        defer { diagnostics("generate-rejected-final") }
        openGenerate()
        generateInvitations()
        let notice = element("redeem.generate.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.generate.submit"].exists, app.debugDescription)
        XCTAssertFalse(element("redeem.result.header.title").exists, app.debugDescription)
        diagnostics("generate-rejected")
        leaveWizard()
        XCTAssertFalse(element("redeem.pending.banner").waitForExistence(timeout: 2), app.debugDescription)
    }

    @MainActor func testPendingBatchInterceptsPlus() {
        launchAndLogin(["-ui-pending-money"])
        defer { diagnostics("generate-intercept-final") }
        let plus = app.buttons["redeem.generate"]
        plus.tap()
        var question = waitForAlert("上一批兑换码的生成结果未确认")
        for part in ["20 个 × $10.00 · 合计 $200.00", "分钟前发起。先核对，避免重复生成。"] {
            XCTAssertTrue(labelled(containing: part, in: question).exists, part + "\n" + app.debugDescription)
        }
        diagnostics("generate-intercept")
        question.buttons["取消"].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.generate.type.balance"].waitForExistence(timeout: 2), app.debugDescription)

        plus.tap()
        waitForAlert("上一批兑换码的生成结果未确认").buttons["先核对"].tap()
        XCTAssertTrue(app.navigationBars["核对结果"].waitForExistence(timeout: 10), app.debugDescription)
        close()

        plus.tap()
        question = waitForAlert("上一批兑换码的生成结果未确认")
        question.buttons["仍要生成新的一批"].tap()
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testOldLoginBatchAlsoIntercepts() {
        launchAndLogin(["-ui-pending-old-site"])
        defer { diagnostics("generate-intercept-old-final") }
        app.buttons["redeem.generate"].tap()
        let question = waitForAlert("上一批兑换码的生成结果未确认")
        XCTAssertTrue(labelled(containing: "10 个 × $5.00 · 合计 $50.00", in: question).exists, app.debugDescription)
        question.buttons["取消"].tap()
    }

    @MainActor func testUnreadableBatchFilePausesGeneration() {
        launchAndLogin(["-ui-pending-money", "-ui-pending-unreadable"])
        defer { diagnostics("generate-paused-final") }
        app.buttons["redeem.generate"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已暂停新的兑换码生成"), app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.generate.type.balance"].exists, app.debugDescription)
    }

    @MainActor func testBackAndCancelButtons() {
        launchAndLogin()
        defer { diagnostics("generate-back-final") }
        openGenerate()
        let leading = app.buttons["sheet.close"]
        XCTAssertEqual(leading.label, "取消")
        leading.tap()
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].waitForNonExistence(timeout: 5), app.debugDescription)

        openGenerate()
        app.buttons["redeem.generate.type.balance"].tap()
        press("1", "2", ".", "5")
        app.buttons["redeem.generate.next"].tap()
        let back = app.buttons["redeem.generate.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.label == "上一步", app.debugDescription)
        back.tap()
        XCTAssertTrue(waitForLabel(element("redeem.generate.amount"), equalTo: "$12.5"), app.debugDescription)
        back.tap()
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].isSelected, app.debugDescription)
        app.buttons["sheet.close"].tap()
    }

    // MARK: - Helpers

    /// Signs in to “生成验收” with a password and opens 兑换码 from the search tab's directory.
    @MainActor private func launchAndLogin(_ arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://redeem-generate.example.invalid", in: app.textFields["login.url"])
        enter(Self.site, in: app.textFields["login.name"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
        app.openSearchItem("search.item.redeem")
        XCTAssertTrue(app.navigationBars["兑换码"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.generate"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openGenerate() {
        app.buttons["redeem.generate"].tap()
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// One invitation code, never expiring, confirmed.
    @MainActor private func generateInvitations() {
        app.buttons["redeem.generate.type.invitation"].tap()
        let next = app.buttons["redeem.generate.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isEnabled, app.debugDescription)
        next.tap()
        let submit = app.buttons["redeem.generate.submit"]
        XCTAssertTrue(waitForLabel(submit, equalTo: "生成 1 个兑换码"), app.debugDescription)
        submit.tap()
        waitForAlert("生成 1 个邀请码？").buttons["生成 1 个"].tap()
    }
    /// From step 3 back to step 1, then 取消.
    @MainActor private func leaveWizard() {
        for _ in 0..<2 { app.buttons["redeem.generate.back"].tap() }
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(app.buttons["redeem.generate.type.balance"].waitForNonExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func press(_ keys: String...) {
        for key in keys { app.buttons["redeem.generate.keypad.key.\(key == "." ? "dot" : key)"].tap() }
    }
    /// The result page's 完成 or the pending page's 关闭.
    @MainActor private func close() {
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    @discardableResult @MainActor private func waitForAlert(_ title: String) -> XCUIElement {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), title + "\n" + app.debugDescription)
        return alert
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equalTo text: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)], timeout: 10) == .completed
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing text: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)], timeout: 10) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    @MainActor private func labelled(containing text: String, in root: XCUIElement? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard until the field can be tapped.
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
        guard let app, app.state != .notRunning else { return }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
