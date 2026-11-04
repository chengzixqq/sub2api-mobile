import XCTest

/// S6-01: 登录设备 (60 §5) reached from 站点与凭据 → 当前站点: this device explains how to sign out (U50), another device
/// signs out after a confirmation with a receipt, 让其他所有设备下线 reloads the list (a pre-deployment session ends this
/// device too, BACKLOG), and the count on the settings page follows.
final class SessionsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private let currentID = "5e5510000000000000000000000000a1"
    private let webID = "5e5510000000000000000000000000b2"
    private let legacyID = "5e5510000000000000000000000000c3"
    private let spareID = "5e5510000000000000000000000000d4"

    @MainActor func testEntryFromSitesSettingsListsDevices() {
        launchAndLogin()
        defer { diagnostics("sessions-entry-final") }
        openSessions(expectingCount: "3")
        XCTAssertTrue(app.navigationBars["登录设备"].exists, app.debugDescription)
        let this = row(currentID)
        XCTAssertTrue(this.waitForExistence(timeout: 5), app.debugDescription)
        for expected in ["演示 iPhone", "本机", "203.0.113.24 · 3 分钟前活跃", "登录于"] {
            XCTAssertTrue(this.label.contains(expected), this.label)
        }
        XCTAssertTrue(row(webID).label.contains("Mozilla/5.0"), row(webID).label)
        XCTAssertTrue(row(webID).label.contains("198.51.100.7 · "), row(webID).label)
        XCTAssertTrue(row(legacyID).label.contains("未知设备"), row(legacyID).label)
        XCTAssertFalse(row(legacyID).label.contains("本机"), row(legacyID).label)
        XCTAssertTrue(app.buttons["sessions.revokeOthers"].exists, app.debugDescription)
        let footnote = element("sessions.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "部署新版本前登录的设备，下一次自动续期后才会出现在这里。")
        diagnostics("sessions-list")
    }

    @MainActor func testCurrentRowHasNoSwipeAndExplains() {
        launchAndLogin()
        defer { diagnostics("sessions-current-final") }
        openSessions(expectingCount: "3")
        let this = row(currentID)
        XCTAssertTrue(this.waitForExistence(timeout: 5), app.debugDescription)
        this.swipeLeft()
        XCTAssertFalse(app.buttons["sessions.revoke.\(currentID)"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.buttons["下线"].exists, app.debugDescription)
        this.tap()
        let alert = app.alerts["这是本机"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "要退出请用设置里的“退出并清除凭据”。").exists, app.debugDescription)
        diagnostics("sessions-current-note")
        alert.buttons["知道了"].tap()
        XCTAssertTrue(waitUntilGone(alert), app.debugDescription)
        XCTAssertTrue(row(currentID).exists && row(webID).exists && row(legacyID).exists, app.debugDescription)
    }

    @MainActor func testRevokingAnotherDeviceConfirmsAndShowsReceipt() {
        launchAndLogin()
        defer { diagnostics("sessions-revoke-final") }
        openSessions(expectingCount: "3")
        let legacy = row(legacyID)
        XCTAssertTrue(legacy.waitForExistence(timeout: 5), app.debugDescription)
        legacy.swipeLeft()
        swipeButton(for: legacyID).tap()
        XCTAssertTrue(text(containing: "让「未知设备」下线？").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "该设备需要重新登录。").exists, app.debugDescription)
        diagnostics("sessions-revoke-confirm")
        confirmDialogButton("下线").tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(receipt.label, "已下线「未知设备」")
        XCTAssertTrue(waitUntilGone(row(legacyID)), app.debugDescription)
        XCTAssertTrue(row(currentID).exists && row(webID).exists, app.debugDescription)
        goBackToSettings(expectingCount: "2")
    }

    @MainActor func testRevokingAllOthersLeavesOnlyThisDevice() {
        launchAndLogin()
        defer { diagnostics("sessions-revoke-all-final") }
        openSessions(expectingCount: "3")
        let revokeOthers = app.buttons["sessions.revokeOthers"]
        XCTAssertTrue(revokeOthers.waitForExistence(timeout: 5), app.debugDescription)
        reveal(revokeOthers)
        revokeOthers.tap()
        XCTAssertTrue(text(containing: "让其他 2 台设备下线？").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "它们需要重新登录，本机不受影响。").exists, app.debugDescription)
        confirmDialogButton("全部下线").tap()
        let noOthers = element("sessions.noOthers")
        XCTAssertTrue(noOthers.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(noOthers.label, "没有其他设备登录")
        XCTAssertTrue(row(currentID).exists, app.debugDescription)
        XCTAssertFalse(row(webID).exists || row(legacyID).exists, app.debugDescription)
        XCTAssertFalse(app.buttons["sessions.revokeOthers"].exists, app.debugDescription)
        diagnostics("sessions-only-this")
        goBackToSettings(expectingCount: "1")
    }

    @MainActor func testRevokingAllWithLegacySessionSignsThisDeviceOut() {
        launchAndLogin(arguments: ["-ui-sessions-legacy-current"])
        defer { diagnostics("sessions-legacy-final") }
        openSessions(expectingCount: "3")
        XCTAssertTrue(row(spareID).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(webID).exists && row(legacyID).exists, app.debugDescription)
        XCTAssertFalse(row(spareID).label.contains("本机"), row(spareID).label)
        let revokeOthers = app.buttons["sessions.revokeOthers"]
        reveal(revokeOthers)
        revokeOthers.tap()
        XCTAssertTrue(text(containing: "让其他 3 台设备下线？").waitForExistence(timeout: 5), app.debugDescription)
        confirmDialogButton("全部下线").tap()
        // The reload after the revocation answers 401 TOKEN_REVOKED: this device was signed out with the others.
        let notice = app.staticTexts["login.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(notice.label, "登录已失效，请重新登录")
        XCTAssertFalse(app.tabBars.buttons["概览"].exists, app.debugDescription)
    }

    @MainActor func testFailureShowsRetry() {
        launchAndLogin(arguments: ["-ui-sessions-unavailable"])
        defer { diagnostics("sessions-failure-final") }
        openSessions(expectingCount: "3", waitsForList: false)
        XCTAssertTrue(text(containing: "暂时无法加载").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "站点暂时不可用，请稍后重试").exists, app.debugDescription)
        diagnostics("sessions-failure")
        app.buttons["重试"].tap()
        XCTAssertTrue(row(currentID).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(webID).exists && row(legacyID).exists, app.debugDescription)
    }

    /// 让其他所有设备下线 went through but the reload after it failed: the revoked devices still leave the older list,
    /// which says it failed to refresh (00 §4.6), and the retry reads it again.
    @MainActor func testRevokingAllOthersHidesThemWhenReloadFails() {
        launchAndLogin(arguments: ["-ui-sessions-reload-fails"])
        defer { diagnostics("sessions-revoke-all-reload-failed-final") }
        openSessions(expectingCount: "3")
        let revokeOthers = app.buttons["sessions.revokeOthers"]
        XCTAssertTrue(revokeOthers.waitForExistence(timeout: 5), app.debugDescription)
        reveal(revokeOthers)
        revokeOthers.tap()
        confirmDialogButton("全部下线").tap()
        let stale = app.buttons["sessions.refreshFailed"]
        XCTAssertTrue(stale.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(stale.label.contains("刷新失败 · 重试") && stale.label.contains("更新于 "), stale.label)
        XCTAssertTrue(waitUntilGone(row(webID)), app.debugDescription)
        XCTAssertFalse(row(legacyID).exists, app.debugDescription)
        XCTAssertTrue(row(currentID).exists, app.debugDescription)
        XCTAssertEqual(element("sessions.noOthers").label, "没有其他设备登录")
        diagnostics("sessions-revoke-all-reload-failed")
        stale.tap()
        XCTAssertTrue(waitUntilGone(stale), app.debugDescription)
        XCTAssertTrue(row(currentID).exists && element("sessions.noOthers").exists, app.debugDescription)
        goBackToSettings(expectingCount: "1")
    }

    // MARK: Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter("登录设备站点", in: "login.name")
        enter("https://sessions.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openSessions(expectingCount count: String, waitsForList: Bool = true) {
        app.openSitesSettings()
        let entry = app.buttons["settings.current.sessions"]
        reveal(entry)
        XCTAssertTrue(waitForLabel(entry, containing: count), entry.label)
        entry.tap()
        XCTAssertTrue(app.navigationBars["登录设备"].waitForExistence(timeout: 5), app.debugDescription)
        if waitsForList { XCTAssertTrue(element("sessions.list").waitForExistence(timeout: 5), app.debugDescription) }
    }
    /// Back on the settings page, which reads the count again when it reappears (60 §3.6).
    @MainActor private func goBackToSettings(expectingCount count: String) {
        app.navigationBars["登录设备"].buttons.element(boundBy: 0).tap()
        let entry = app.buttons["settings.current.sessions"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
        reveal(entry)
        XCTAssertTrue(waitForLabel(entry, containing: count), entry.label)
    }
    @MainActor private func row(_ id: String) -> XCUIElement { element("sessions.row.\(id)") }
    /// The swipe action by its identifier, else by its title: only the row's swipe says 下线 before the confirmation opens.
    @MainActor private func swipeButton(for id: String) -> XCUIElement {
        let byID = app.buttons["sessions.revoke.\(id)"]
        if byID.waitForExistence(timeout: 3) { return byID }
        let byTitle = app.buttons["下线"]
        XCTAssertTrue(byTitle.waitForExistence(timeout: 2), app.debugDescription)
        return byTitle
    }
    /// The confirmation's button, never the row's swipe action of the same title.
    @MainActor private func confirmDialogButton(_ label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", label, "sessions.")
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        return button
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
