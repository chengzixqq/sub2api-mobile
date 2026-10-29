import XCTest

/// S6-06: the check sheet of a pending redeem batch (60 §11) from settings and from the list's banner. Fixtures: `-ui-pending-money`
/// gives the connected site a batch of 20 × $10.00 (0A…02, five minutes old, S0-15); `-ui-pending-old-site` an older login at
/// the same address with 10 × $5.00 (0B…02, S3-07); `-ui-redeem-*` decides what a check or a retry finds (RedeemFixtures).
/// Without one, a check finds nothing and a retry generates the batch (codes 6000… / 6100…).
final class RedeemReconcileUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let batch = "0A000000-0000-4000-8000-000000000002"
    private static let refund = "0A000000-0000-4000-8000-000000000001"
    private static let oldBatch = "0B000000-0000-4000-8000-000000000002"
    private static let oldTopUp = "0B000000-0000-4000-8000-000000000001"

    @MainActor func testSettingsOpensThePendingPage() {
        launchAndLogin(["-ui-pending-money"])
        defer { diagnostics("reconcile-batch-pending-final") }
        openFromSettings(Self.batch)
        XCTAssertTrue(waitForLabel("money.pending.header.title", "请求可能已提交"), app.debugDescription)
        XCTAssertEqual(element("money.pending.header.message").label, "没有收到服务器确认。不要重新生成，先核对。")
        for (row, part) in [("content", "20 个 × $10.00"), ("total", "$200.00"), ("started", "核对验收 · "), ("key", Self.batch.lowercased())] {
            XCTAssertTrue(element("money.pending.receipt.\(row)").label.contains(part), "\(row) ∌ \(part)\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.buttons["redeem.reconcile.check"].isEnabled && app.buttons["redeem.reconcile.retry"].isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.reconcile.abandon"].exists)
        XCTAssertTrue(element("money.pending.footnote").label.hasPrefix("编号已保存在本机。核对会按这个编号在服务器上找这一批"), element("money.pending.footnote").label)
        diagnostics("reconcile-batch-pending")
        close()
        XCTAssertTrue(element("settings.pending.check.\(Self.batch)").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testCheckFindsTheBatchAndClearsBannerAndSettings() {
        launchAndLogin(["-ui-pending-money", "-ui-redeem-reconcile-generated"])
        defer { diagnostics("reconcile-batch-generated-final") }
        openFromBanner()
        tapAction("check")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "已核对：服务器已生成 20 个"), app.debugDescription)
        XCTAssertEqual(element("redeem.result.header.message").label, "余额 · 每个 $10.00 · 永不过期")
        let copyAll = app.buttons["redeem.result.copyAll"]
        XCTAssertTrue(copyAll.label.contains("全部复制（20 个，每行一个）"), copyAll.label)
        copyAll.tap()
        XCTAssertTrue(waitForLabel(copyAll, containing: "已复制全部 20 个"), copyAll.label)
        XCTAssertTrue(element("redeem.result.code.1.text").exists && app.buttons["redeem.result.code.1.copy"].exists, app.debugDescription)
        XCTAssertTrue(element("redeem.result.footnote").label.contains("发起时生成的，已在列表的“今天生成”里"), element("redeem.result.footnote").label)
        diagnostics("reconcile-batch-generated")
        close()
        XCTAssertTrue(element("redeem.pending.banner").waitForNonExistence(timeout: 10), app.debugDescription)
        assertSettingsKeepsOnly(Self.refund, gone: Self.batch)
        // 概览 reads the same record: the refund's row stays, the batch's is gone.
        app.tabBars.buttons["概览"].tap()
        app.scrollUntilExists(element("home.attention.pending-" + Self.refund.lowercased()))
        XCTAssertFalse(element("home.attention.pending-" + Self.batch.lowercased()).exists, app.debugDescription)
    }

    @MainActor func testNotFoundThenRetryGeneratesTheBatch() {
        launchAndLogin(["-ui-pending-money"])
        defer { diagnostics("reconcile-batch-retry-final") }
        openFromBanner()
        tapAction("check")
        XCTAssertTrue(waitForLabel("money.pending.header.title", "服务器上没有这一批"), app.debugDescription)
        XCTAssertEqual(element("money.pending.footnote").label, "重试用的是本机保存的同一个编号，服务器最多生成一批。")
        XCTAssertTrue(app.buttons["redeem.reconcile.abandon"].exists && !app.buttons["redeem.reconcile.check"].exists, app.debugDescription)
        diagnostics("reconcile-batch-notfound")
        tapAction("retry")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "已生成 20 个兑换码"), app.debugDescription)
        close()
        XCTAssertTrue(element("redeem.pending.banner").waitForNonExistence(timeout: 10), app.debugDescription)
        // The list reads again and shows the new batch first.
        XCTAssertTrue(app.buttons["redeem.card.6019"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testAbandonAsksFirstThenStopsReminding() {
        launchAndLogin(["-ui-pending-money"])
        defer { diagnostics("reconcile-batch-abandon-final") }
        openFromBanner()
        tapAction("check")
        tapAction("abandon")
        let confirm = app.alerts["放弃这一批？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "这些兑换码仍在列表里", in: confirm).exists, app.debugDescription)
        confirm.buttons["取消"].tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("redeem.reconcile.root").exists, app.debugDescription)
        tapAction("abandon")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.buttons["放弃这一批"].tap()
        waitForReceipt("已放弃这一批 · 不再提醒")
        XCTAssertTrue(element("redeem.reconcile.root").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("redeem.pending.banner").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUnconfirmedRetryAndStoreCooldownKeepTheRecord() {
        defer { diagnostics("reconcile-batch-retry-kept-final") }
        launchAndLogin(["-ui-pending-money", "-ui-redeem-retry-unknown"])
        openFromBanner()
        tapAction("retry")
        XCTAssertTrue(waitForLabel("money.pending.notice", containing: "结果未确认，已记为待核对"), app.debugDescription)
        XCTAssertEqual(element("money.pending.header.title").label, "请求可能已提交")
        XCTAssertTrue(app.buttons["redeem.reconcile.retry"].isEnabled)
        app.terminate()

        launchAndLogin(["-ui-pending-money", "-ui-redeem-retry-store-unavailable"])
        openFromBanner()
        tapAction("retry")
        XCTAssertTrue(waitForLabel("redeem.reconcile.notes", containing: "服务器暂时无法受理，稍后用同一编号重试"), app.debugDescription)
        let retry = app.buttons["redeem.reconcile.retry"]
        XCTAssertFalse(retry.isEnabled, app.debugDescription)
        diagnostics("reconcile-batch-cooldown")
        let awake = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: retry)
        XCTAssertEqual(XCTWaiter().wait(for: [awake], timeout: 20), .completed, app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.reconcile.check"].isEnabled)
    }

    @MainActor func testCountMismatchWaitsForConfirmationAndFailureKeepsTheRecord() {
        defer { diagnostics("reconcile-batch-mismatch-final") }
        launchAndLogin(["-ui-pending-money", "-ui-redeem-reconcile-mismatch"])
        openFromBanner()
        tapAction("check")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "已核对：服务器上找到 15 个"), app.debugDescription)
        XCTAssertTrue(element("redeem.result.caution").label.contains("数量与发起时不符，请到 Web 核对"), app.debugDescription)
        diagnostics("reconcile-batch-mismatch")
        close()
        // Kept until “我已核对”.
        openFromBanner()
        tapAction("check")
        let confirm = app.buttons["redeem.result.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.tap()
        waitForReceipt("已核对这一批 · 不再提醒")
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), app.debugDescription)
        close()
        XCTAssertTrue(element("redeem.pending.banner").waitForNonExistence(timeout: 10), app.debugDescription)
        app.terminate()

        launchAndLogin(["-ui-pending-money", "-ui-redeem-reconcile-failed"])
        openFromBanner()
        tapAction("check")
        XCTAssertTrue(waitForLabel("money.pending.notice", containing: "核对失败，请稍后再试"), app.debugDescription)
        XCTAssertEqual(element("money.pending.header.title").label, "请求可能已提交")
        close()
        XCTAssertTrue(element("redeem.pending.banner").exists, app.debugDescription)
    }

    @MainActor func testOtherAdministratorAndReadOnlyTokenCannotRetry() {
        defer { diagnostics("reconcile-batch-other-final") }
        launchAndLogin(["-ui-pending-old-site", "-ui-pending-other-actor"])
        openFromSettings(Self.oldBatch)
        XCTAssertTrue(waitForLabel("redeem.reconcile.notes", containing: "这一批由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新生成。"),
                      app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.reconcile.retry"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.reconcile.abandon"].exists && app.buttons["redeem.reconcile.check"].exists, app.debugDescription)
        XCTAssertTrue(element("money.pending.receipt.started").label.contains("本站点的旧登录下发起"), app.debugDescription)
        diagnostics("reconcile-batch-other")
        app.terminate()

        launchAndLogin(["-ui-pending-money"], readOnlyToken: true)
        openFromBanner()
        XCTAssertTrue(app.buttons["redeem.reconcile.retry"].exists && !app.buttons["redeem.reconcile.retry"].isEnabled, app.debugDescription)
        XCTAssertTrue(element("redeem.reconcile.notes").label.contains("当前登录的是只读令牌，不能修改"), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.reconcile.check"].isEnabled)
    }

    /// X34 / C-26: an older login's batch at this address is retried by its sender and leaves settings and the banner at once.
    @MainActor func testOldLoginBatchRetryClearsEveryEntry() {
        launchAndLogin(["-ui-pending-old-site"])
        defer { diagnostics("reconcile-batch-old-site-final") }
        openFromBanner()
        XCTAssertTrue(element("money.pending.receipt.started").label.contains("本站点的旧登录下发起"), app.debugDescription)
        XCTAssertTrue(element("money.pending.receipt.content").label.contains("10 个 × $5.00"), app.debugDescription)
        tapAction("retry")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "已生成 10 个兑换码"), app.debugDescription)
        close()
        XCTAssertTrue(element("redeem.pending.banner").waitForNonExistence(timeout: 10), app.debugDescription)
        assertSettingsKeepsOnly(Self.oldTopUp, gone: Self.oldBatch)
    }

    /// U43: without `redeem_codes.stats` the newest codes stand in for the batch, and a replay's masked codes are read by id.
    @MainActor func testOldServerGuessNeedsConfirmationAndRetryReadsCodes() {
        defer { diagnostics("reconcile-batch-legacy-final") }
        let legacy = ["-ui-without-capabilities", "redeem_codes.stats", "-ui-pending-money"]
        launchAndLogin(legacy + ["-ui-redeem-legacy-match"])
        openFromSettings(Self.batch)
        XCTAssertTrue(element("money.pending.footnote").label.contains("这个站点的版本较旧"), app.debugDescription)
        tapAction("check")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "找到 20 个可能是这一批的兑换码"), app.debugDescription)
        XCTAssertTrue(element("redeem.result.caution").label.contains("另一位管理员同时生成时可能分不清"), app.debugDescription)
        app.buttons["redeem.result.confirm"].tap()
        waitForReceipt("已核对这一批 · 不再提醒")
        diagnostics("reconcile-batch-legacy")
        app.terminate()

        launchAndLogin(legacy)
        openFromSettings(Self.batch)
        tapAction("check")
        XCTAssertTrue(waitForLabel("money.pending.header.title", "服务器上没有这一批"), app.debugDescription)
        XCTAssertTrue(element("redeem.reconcile.notes").label.contains("另一位管理员同时生成时可能分不清"), app.debugDescription)
        tapAction("retry")
        XCTAssertTrue(waitForLabel("redeem.result.header.title", "已生成 20 个兑换码（服务器已有这一批，已取回）"), app.debugDescription)
        XCTAssertFalse(element("redeem.result.code.1.text").label.contains("*"), element("redeem.result.code.1.text").label)
    }

    /// 60 §10.4 第 2 步: a retry from “没找到” whose answer is lost may have run, so the page goes back to 结果待核对 with the
    /// check offered again instead of still saying nothing was generated.
    @MainActor func testUnconfirmedRetryFromNotFoundReturnsToThePendingPage() {
        launchAndLogin(["-ui-pending-money", "-ui-redeem-retry-unknown"])
        defer { diagnostics("reconcile-batch-notfound-retry-kept-final") }
        openFromBanner()
        tapAction("check")
        XCTAssertTrue(waitForLabel("money.pending.header.title", "服务器上没有这一批"), app.debugDescription)
        tapAction("retry")
        XCTAssertTrue(waitForLabel("money.pending.notice", containing: "结果未确认，已记为待核对"), app.debugDescription)
        XCTAssertTrue(waitForLabel("money.pending.header.title", "请求可能已提交"), app.debugDescription)
        XCTAssertTrue(app.buttons["redeem.reconcile.check"].isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.reconcile.abandon"].exists, app.debugDescription)
        diagnostics("reconcile-batch-notfound-retry-kept")
        close()
        XCTAssertTrue(element("redeem.pending.banner").exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to “核对验收” with a password, or with a read-only access token.
    @MainActor private func launchAndLogin(_ arguments: [String], readOnlyToken: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + (readOnlyToken ? ["-ui-readonly-token"] : [])
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://reconcile.example.invalid", in: app.textFields["login.url"])
        enter("核对验收", in: app.textFields["login.name"])
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
    }
    /// 站点与凭据 → the record's “去核对 ›”.
    @MainActor private func openFromSettings(_ id: String) {
        app.openSitesSettings()
        let check = element("settings.pending.check.\(id)")
        app.scrollUntilExists(check)
        check.tap()
        XCTAssertTrue(element("redeem.reconcile.root").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["核对结果"].exists, app.debugDescription)
    }
    /// 兑换码 → the pending banner's 核对.
    @MainActor private func openFromBanner() {
        if !app.buttons["redeem.pending.check"].exists {
            app.openSearchItem("search.item.redeem")
            XCTAssertTrue(app.navigationBars["兑换码"].waitForExistence(timeout: 10), app.debugDescription)
        }
        let check = app.buttons["redeem.pending.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 10), app.debugDescription)
        check.tap()
        XCTAssertTrue(element("redeem.reconcile.root").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func tapAction(_ kind: String) {
        let button = app.buttons["redeem.reconcile.\(kind)"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, kind + "\n" + app.debugDescription)
        button.tap()
    }
    @MainActor private func close() {
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(element("redeem.reconcile.root").waitForNonExistence(timeout: 10), app.debugDescription)
    }
    /// Settings lists the record next to `kept` (same age) without the settled one.
    @MainActor private func assertSettingsKeepsOnly(_ kept: String, gone: String) {
        app.openSitesSettings()
        let row = element("settings.pending.check.\(kept)")
        app.scrollUntilExists(row)
        XCTAssertFalse(element("settings.pending.check.\(gone)").exists, app.debugDescription)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(waitForLabel(receipt, equalTo: text), "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ identifier: String, _ text: String) -> Bool { waitForLabel(element(identifier), equalTo: text) }
    @MainActor private func waitForLabel(_ identifier: String, containing text: String) -> Bool { waitForLabel(element(identifier), containing: text) }
    @MainActor private func waitForLabel(_ item: XCUIElement, equalTo text: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)], timeout: 10) == .completed
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing text: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)], timeout: 10) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func labelled(containing text: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
