import XCTest

/// S6-24: 设置 → 推送通知 (60 §7) and a target's page. The fixture store has 我的 Bark (12) and a stopped Webhook (13);
/// `-ui-push-local-on` / `-ui-push-local-unregistered` register this phone as 11. Fixture arguments (PushFixture; the UI
/// tests cannot import the App): not ready, config fails, subscription fails, test fails, register fails, list fails,
/// pending deletion; S6-23's `-ui-push-denied` and `-ui-push-no-capability`.
final class PushSettingsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testNotReadyBannerGreysTheLocalSwitch() {
        launchAndLogin(arguments: ["-ui-push-not-ready"])
        defer { diagnostics("push-not-ready-final") }
        openPushSettings()
        let banner = element("push.banner.notReady")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(banner.label, "站点还没配好 APNs，本机收不到推送。可改用 Bark / ntfy / Webhook，或在下方配置 APNs。")
        let toggle = localSwitch()
        XCTAssertFalse(toggle.isEnabled, app.debugDescription)
        XCTAssertTrue(toggle.label.contains("站点配好 APNs 后才能打开"), toggle.label)
        XCTAssertFalse(app.buttons["push.local.test"].isEnabled, app.debugDescription)
        let status = element("push.apns.status")
        reveal(status)
        XCTAssertEqual(status.value as? String, "未就绪")
        XCTAssertEqual(element("push.apns.privateKey").value as? String, "未配置")
        diagnostics("push-not-ready")
    }

    @MainActor func testConfigFailureHidesAPNsButKeepsTheSwitch() {
        launchAndLogin(arguments: ["-ui-push-config-fails"])
        defer { diagnostics("push-config-fails-final") }
        openPushSettings()
        XCTAssertTrue(waitUntil(localSwitch(), "isEnabled == true"), app.debugDescription)
        XCTAssertFalse(element("push.banner.notReady").exists, app.debugDescription)
        reveal(app.buttons["push.targets.add"])
        for _ in 0..<2 { app.swipeUp() }
        XCTAssertFalse(element("push.apns.status").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["push.apns.edit"].exists, app.debugDescription)
    }

    @MainActor func testTurningLocalPushOnAndOffUpdatesStatusAndSettingsRow() {
        launchAndLogin()
        defer { diagnostics("push-local-switch-final") }
        app.openSearchItem("search.item.interface")
        XCTAssertTrue(waitUntil(settingsEntry(), "value == '未开启'"), app.debugDescription)
        settingsEntry().tap()
        let toggle = localSwitch()
        XCTAssertTrue(waitUntil(toggle, "isEnabled == true"), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["push.local.test"].isEnabled, app.debugDescription)
        XCTAssertFalse(event("ops_alert.fired").exists, app.debugDescription)
        tapSwitch(toggle)
        XCTAssertTrue(waitUntil(toggle, "value == '1'", timeout: 10), app.debugDescription)
        let status = element("push.local.status")
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(status.label, "已开启 · 还没有送达记录")
        XCTAssertTrue(app.buttons["push.local.test"].isEnabled, app.debugDescription)
        for (id, value) in [("ops_alert.fired", "1"), ("ops_alert.resolved", "0"), ("account.error", "1"), ("account.test_finished", "0")] {
            let item = event(id); reveal(item)
            XCTAssertEqual(item.value as? String, value, id)
        }
        diagnostics("push-local-on")
        goBack()
        XCTAssertTrue(waitUntil(settingsEntry(), "value == '已开启'", timeout: 10), app.debugDescription)
        settingsEntry().tap()
        let again = localSwitch()
        XCTAssertTrue(waitUntil(again, "value == '1'"), app.debugDescription)
        tapSwitch(again)
        XCTAssertTrue(waitUntil(again, "value == '0'", timeout: 10), app.debugDescription)
        XCTAssertTrue(element("push.local.status").waitForNonExistence(timeout: 5), app.debugDescription)
        goBack()
        XCTAssertTrue(waitUntil(settingsEntry(), "value == '未开启'", timeout: 10), app.debugDescription)
    }

    @MainActor func testUnregisteredLocalDeviceShowsWhyAndSettingsSaysStopped() {
        launchAndLogin(arguments: ["-ui-push-local-unregistered"])
        defer { diagnostics("push-unregistered-final") }
        app.openSearchItem("search.item.interface")
        XCTAssertTrue(waitUntil(settingsEntry(), "value == '已停用'", timeout: 10), app.debugDescription)
        settingsEntry().tap()
        let status = element("push.local.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(status.label, "设备令牌已失效，关掉再打开即可恢复")
        let toggle = localSwitch()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.buttons["push.local.test"].isEnabled, app.debugDescription)
        XCTAssertTrue(event("ops_alert.fired").waitForExistence(timeout: 5), app.debugDescription)
        diagnostics("push-unregistered")
        // Registering the same token again enables the same target (S6D2b-06).
        tapSwitch(toggle)
        XCTAssertTrue(waitUntil(toggle, "value == '1'", timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(status, "label BEGINSWITH '已开启'"), status.label)
        XCTAssertFalse(element("push.targets.row.9001").exists, app.debugDescription)
    }

    @MainActor func testDeniedPermissionOffersSystemSettings() {
        launchAndLogin(arguments: ["-ui-push-denied"])
        defer { diagnostics("push-denied-final") }
        openPushSettings()
        let permission = app.buttons["push.local.permission"]
        XCTAssertTrue(permission.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(permission.label, "系统设置里关闭了通知 · 去设置")
        XCTAssertTrue(permission.isEnabled, app.debugDescription)
        let toggle = localSwitch()
        tapSwitch(toggle)
        settle()
        XCTAssertTrue(waitUntil(toggle, "isEnabled == true AND value == '0'"), app.debugDescription)
        XCTAssertFalse(element("push.local.status").exists, app.debugDescription)
        XCTAssertFalse(element("push.local.error").exists, app.debugDescription)
    }

    @MainActor func testRegistrationFailuresTurnTheSwitchBackOff() {
        let cases = [("-ui-push-register-fails", "最多 20 个推送目标，先删除不用的"),
                     ("-ui-push-no-capability", "这个 App 构建没有开启推送能力；APNs 只适用于用站点同一 Apple Team 的 p8 私钥构建的 App。可改用 Bark / ntfy / Webhook。")]
        defer { diagnostics("push-register-fails-final") }
        for (index, (argument, text)) in cases.enumerated() {
            if index > 0 { app.terminate() }
            launchAndLogin(arguments: [argument])
            openPushSettings()
            let toggle = localSwitch()
            XCTAssertTrue(waitUntil(toggle, "isEnabled == true"), app.debugDescription)
            tapSwitch(toggle)
            let error = element("push.local.error")
            XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(error.label, text)
            XCTAssertTrue(waitUntil(toggle, "value == '0'"), app.debugDescription)
        }
    }

    @MainActor func testSubscriptionEditsSaveAtOnce() {
        launchAndLogin(arguments: ["-ui-push-local-on"])
        defer { diagnostics("push-subscription-final") }
        openPushSettings()
        let resolved = event("ops_alert.resolved")
        reveal(resolved)
        XCTAssertEqual(resolved.value as? String, "0")
        tapSwitch(resolved)
        XCTAssertTrue(waitUntil(resolved, "value == '1'"), app.debugDescription)
        settle()
        app.pullToRefresh(from: element("push.local.status"))
        settle()
        reveal(event("ops_alert.resolved"))
        XCTAssertEqual(event("ops_alert.resolved").value as? String, "1")
        for id in ["ops_alert.fired", "account.error", "ops_alert.resolved"] {
            let item = event(id); reveal(item); tapSwitch(item)
            XCTAssertTrue(waitUntil(item, "value == '0'"), id)
        }
        let paused = element("push.subscription.paused")
        XCTAssertTrue(paused.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(paused.label, "已暂停推送")
        let severity = app.buttons["push.subscription.severity"]
        reveal(severity)
        XCTAssertEqual(severity.value as? String, "P1 及以上")
        severity.tap()
        let p0 = app.buttons.matching(NSPredicate(format: "label == %@", "P0 及以上")).firstMatch
        XCTAssertTrue(p0.waitForExistence(timeout: 5), app.debugDescription)
        p0.tap()
        XCTAssertTrue(waitUntil(severity, "value == 'P0 及以上'"), app.debugDescription)
        let quiet = app.switches["push.subscription.quiet"]
        reveal(quiet)
        XCTAssertTrue(quiet.label.contains("按本机时区 Asia/Shanghai；时段内的事件不补推"), quiet.label)
        tapSwitch(quiet)
        XCTAssertTrue(waitUntil(quiet, "value == '1'"), app.debugDescription)
        XCTAssertTrue(element("push.subscription.quiet.start").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("push.subscription.quiet.end").exists, app.debugDescription)
        let footer = element("push.subscription.footer")
        reveal(footer)
        XCTAssertEqual(footer.label, "同一账号出错 30 分钟内最多推一次；推送最多晚约 15 秒；测试完成只推给发起测试的人。")
        diagnostics("push-subscription-edited")
        let groups = app.buttons["push.subscription.groups"]
        reveal(groups)
        XCTAssertTrue(groups.label.contains("全站告警不受范围限制") && groups.label.contains("全部分组"), groups.label)
        groups.tap()
        let option = app.buttons["push.scope.option.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), app.debugDescription)
        option.tap()
        app.buttons["push.scope.done"].tap()
        XCTAssertTrue(element("push.scope.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil(groups, "label CONTAINS '高级组'"), groups.label)
    }

    @MainActor func testFailedSubscriptionSaveRollsBack() {
        launchAndLogin(arguments: ["-ui-push-local-on", "-ui-push-subscription-fails"])
        defer { diagnostics("push-subscription-fails-final") }
        openPushSettings()
        let resolved = event("ops_alert.resolved")
        reveal(resolved)
        tapSwitch(resolved)
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(receipt.label.hasPrefix("推送内容没有保存："), receipt.label)
        XCTAssertTrue(waitUntil(resolved, "value == '0'"), app.debugDescription)
    }

    @MainActor func testSendingATestShowsTheReceipt() {
        launchAndLogin(arguments: ["-ui-push-local-on"])
        defer { diagnostics("push-test-final") }
        openPushSettings()
        let status = element("push.local.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("已开启 · 上次送达 "), status.label)
        app.buttons["push.local.test"].tap()
        XCTAssertTrue(waitForReceipt("已发送测试推送，请看通知"), app.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("已开启 · 上次送达 "), status.label)
    }

    @MainActor func testRefusedTestShowsTheProviderReasonAndReloads() {
        launchAndLogin(arguments: ["-ui-push-local-on", "-ui-push-test-fails"])
        defer { diagnostics("push-test-refused-final") }
        openPushSettings()
        let toggle = localSwitch()
        XCTAssertTrue(waitUntil(toggle, "value == '1'"), app.debugDescription)
        app.buttons["push.local.test"].tap()
        XCTAssertTrue(waitForReceipt("推送服务没有接受：BadDeviceToken（400）"), app.debugDescription)
        XCTAssertTrue(waitUntil(element("push.local.status"), "label CONTAINS '设备令牌无效'"), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor func testDeletingAnotherTargetNeedsItsName() {
        launchAndLogin()
        defer { diagnostics("push-delete-final") }
        openPushSettings()
        let bark = element("push.targets.row.12")
        reveal(bark)
        XCTAssertTrue(bark.label.contains("我的 Bark") && bark.label.contains("Bark · api.day.app"), bark.label)
        let webhook = element("push.targets.row.13")
        reveal(webhook)
        XCTAssertTrue(webhook.label.contains("hooks.example.com") && webhook.label.contains("已停用"), webhook.label)
        reveal(bark)
        bark.tap()
        XCTAssertTrue(app.navigationBars["我的 Bark"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(event("ops_alert.fired").waitForExistence(timeout: 10), app.debugDescription)
        let delete = app.buttons["push.target.delete"]
        reveal(delete)
        delete.tap()
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除接收方式「我的 Bark」？")
        let message = element("delete.message").label
        XCTAssertTrue(message.contains("站点 \(siteName) · 删除后不能恢复。") && message.contains("这个地址不再收到推送，要恢复需重新添加。"), message)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = app.textFields["delete.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { input.tap() }
        input.typeText("我的 Bark")
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        diagnostics("push-delete-confirm")
        confirm.tap()
        XCTAssertTrue(waitForReceipt("已删除接收方式「我的 Bark」"), app.debugDescription)
        XCTAssertTrue(element("push.list").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["推送通知"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("push.targets.row.12").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testFaceIDDeletesWithoutTyping() {
        launchAndLogin(arguments: ["-ui-faceid-on"])
        defer { diagnostics("push-delete-faceid-final") }
        openPushSettings()
        let webhook = element("push.targets.row.13")
        reveal(webhook)
        webhook.tap()
        XCTAssertTrue(app.navigationBars["hooks.example.com"].waitForExistence(timeout: 10), app.debugDescription)
        let delete = app.buttons["push.target.delete"]
        reveal(delete)
        delete.tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitForReceipt("已删除接收方式「hooks.example.com」"), app.debugDescription)
        XCTAssertTrue(app.navigationBars["推送通知"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("push.targets.row.13").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenHidesAddAndGreysAPNsEdit() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_ui-fixture")
        defer { diagnostics("push-read-only-final") }
        openPushSettings()
        // 60 §0.3: a read-only token may still register this phone.
        XCTAssertTrue(waitUntil(localSwitch(), "isEnabled == true"), app.debugDescription)
        let edit = app.buttons["push.apns.edit"]
        reveal(edit)
        XCTAssertFalse(edit.isEnabled, app.debugDescription)
        XCTAssertEqual(element("push.apns.editNote").label, "只读令牌")
        XCTAssertFalse(app.buttons["push.targets.add"].exists, app.debugDescription)
        diagnostics("push-read-only")
        app.terminate()
        launchAndLogin()
        openPushSettings()
        let add = app.buttons["push.targets.add"]
        reveal(add)
        add.tap()
        // S6-25 replaces the placeholder with its sheet (push.add.sheet, push.add.cancel).
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testListFailureShowsRetryRowsAndPendingDeletionNotice() {
        launchAndLogin(arguments: ["-ui-push-list-fails", "-ui-push-pending-deletion"])
        defer { diagnostics("push-list-fails-final") }
        openPushSettings()
        let pending = element("push.pendingDeletion")
        XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(pending.label, "有设备未能从站点移除，可在 Web 删除")
        for id in ["push.local.retry", "push.targets.retry"] {
            let retry = app.buttons[id]
            reveal(retry)
            XCTAssertEqual(retry.label, "加载失败 · 重试", id)
        }
        XCTAssertFalse(localSwitch().isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["push.local.test"].isEnabled, app.debugDescription)
    }

    // MARK: Helpers

    private let siteName = "推送设置站点"
    private let siteURL = "https://push-settings.example.invalid"

    /// Password sign-in, or the access-token method for `accessToken`.
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
    /// 界面与模式 → 通知 → 推送通知.
    @MainActor private func openPushSettings() {
        app.openSearchItem("search.item.interface")
        settingsEntry().tap()
        XCTAssertTrue(app.navigationBars["推送通知"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(localSwitch().exists, app.debugDescription)
    }
    @MainActor private func settingsEntry() -> XCUIElement {
        let entry = app.buttons["settings.push"]
        reveal(entry)
        return entry
    }
    @MainActor private func localSwitch() -> XCUIElement {
        let toggle = app.switches["push.local.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        return toggle
    }
    @MainActor private func event(_ rawValue: String) -> XCUIElement { app.switches["push.subscription.event.\(rawValue)"] }
    @MainActor private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }
    /// The switch itself, on the right of the row, once the list has stopped moving.
    @MainActor private func tapSwitch(_ toggle: XCUIElement) {
        toggle.waitUntilSettled()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
    }
    @MainActor private func waitForReceipt(_ text: String) -> Bool {
        let receipt = app.staticTexts["receipt.text"]
        guard receipt.waitForExistence(timeout: 10) else { return false }
        return waitUntil(receipt, "label == '\(text)'")
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String, timeout: TimeInterval = 5) -> Bool {
        let match = expectation(for: NSPredicate(format: format), evaluatedWith: item)
        return XCTWaiter().wait(for: [match], timeout: timeout) == .completed
    }
    /// A request the tap started has answered (the fixtures answer at once).
    @MainActor private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(1)) }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Rows of a List exist only near the screen; the row must end up between the navigation bar and the tab bar.
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<12 {
            if item.exists && item.isHittable && isBetweenBars(item) { item.waitUntilSettled(); return }
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
    @MainActor private func isBetweenBars(_ item: XCUIElement) -> Bool {
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        return item.frame.minY >= top && item.frame.maxY <= bottom
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
