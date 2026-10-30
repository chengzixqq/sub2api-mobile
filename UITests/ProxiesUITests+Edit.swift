import XCTest

/// 60 §14 添加 / 编辑 / 续期代理 (S6-14) on ProxyFixtures: an add answers id 9 and its first probe (158ms) about 2 seconds later;
/// an address edit probes again the same way; `-ui-proxy-backup-gone` refuses any write that sends a backup with 404 and
/// `-ui-proxy-add-lost` makes the first add but loses its reply.
extension ProxiesUITests {
    /// ProxyFixtures' editor arguments.
    enum EditArgument {
        static let backupGone = "-ui-proxy-backup-gone"
        static let addLost = "-ui-proxy-add-lost"
    }

    /// 14.4: added, then 撤销 deletes it; added again, its first probe shows about 3 seconds later.
    @MainActor func testAddProxyThenUndo() {
        launchProxies()
        defer { diagnostics("proxy-edit-add-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        openAdd()
        let submit = app.buttons["proxyEdit.submit"]
        XCTAssertEqual(submit.label, "添加")
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        fillNewProxy("fr-par-1")
        XCTAssertTrue(waitForEnabled(submit), app.debugDescription)
        submit.tap()
        waitForReceipt("代理添加成功")
        XCTAssertTrue(app.navigationBars["添加代理"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(9).waitForExistence(timeout: 3), app.debugDescription)
        let undo = app.buttons["receipt.action"]
        XCTAssertEqual(undo.label, "撤销")
        undo.tap()
        waitForReceipt("已删除代理「fr-par-1」")
        XCTAssertTrue(row(9).waitForNonExistence(timeout: 10), app.debugDescription)
        openAdd()
        fillNewProxy("fr-par-2")
        app.buttons["proxyEdit.submit"].tap()
        waitForReceipt("代理添加成功")
        XCTAssertTrue(row(9).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(9).label.contains("fr-par-2"), row(9).label)
        XCTAssertTrue(waitForLabel(row(9), containing: "158ms", timeout: 8), row(9).label)
    }

    @MainActor func testPortOutOfRangeDisablesAdd() {
        launchProxies()
        defer { diagnostics("proxy-edit-port-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        openAdd()
        typeIn("proxyEdit.name", "fr-par-1")
        typeIn("proxyEdit.host", "198.51.100.9")
        typeIn("proxyEdit.port", "70000")
        let note = element("proxyEdit.issue.address")
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(note.label, "端口必须在 1-65535 之间")
        let submit = app.buttons["proxyEdit.submit"]
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        let port = app.textFields["proxyEdit.port"]
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "8080")
        XCTAssertTrue(note.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitForEnabled(submit), app.debugDescription)
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "1234567")
        XCTAssertTrue(waitForValue(port, "12345"), String(describing: port.value))
        XCTAssertTrue(waitForEnabled(submit), app.debugDescription)
        app.buttons["proxyEdit.cancel"].tap()
        let discard = app.alerts["放弃修改？"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["放弃修改"].tap()
        XCTAssertTrue(app.navigationBars["添加代理"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// 13.6 / H04: a new port makes the detail wait for the server's probe instead of testing; a new name alone does not.
    @MainActor func testEditNetworkFieldShowsRetestingOnDetail() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-edit-network-final") }
        openEditor("proxy.action.edit", title: "编辑代理")
        let password = app.secureTextFields["proxyEdit.password"]
        XCTAssertTrue(password.exists, app.debugDescription)
        XCTAssertEqual(password.placeholderValue, "留空保持不变")
        XCTAssertFalse((password.value as? String ?? "").contains("•"), String(describing: password.value))
        replaceText(in: app.textFields["proxyEdit.port"], with: "1081")
        app.buttons["proxyEdit.submit"].tap()
        waitForReceipt("代理更新成功")
        let latency = element("proxy.latency")
        XCTAssertTrue(waitForLabel(latency, containing: "地址已修改，正在重新测试", timeout: 5), latency.label)
        XCTAssertTrue(waitForLabel(latency, containing: "158ms", timeout: 8), latency.label)
        let port = element("proxy.kv.port")
        reveal(port)
        XCTAssertTrue(port.label.contains("1081"), port.label)
        reveal(app.buttons["proxy.action.edit"], down: false)
        openEditor("proxy.action.edit", title: "编辑代理")
        replaceText(in: app.textFields["proxyEdit.name"], with: "hk-02b")
        app.buttons["proxyEdit.submit"].tap()
        waitForReceipt("代理更新成功")
        XCTAssertTrue(app.navigationBars["hk-02b"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(latency.label.contains("正在重新测试"), latency.label)
    }

    /// 14.3: renewing shows the proxy, then 有效期 · 续期, 状态, 到期回退 and 名称与协议; it opens as 停用, and a new expiry switches
    /// it back to 正常.
    @MainActor func testRenewModeOrderAndStatusSwitchesBack() {
        openDetail(3, title: "jp-tokyo-1")
        defer { diagnostics("proxy-edit-renew-final") }
        openEditor("proxy.action.renew", title: "续期代理")
        XCTAssertEqual(element("proxyEdit.renewTarget").label, "jp-tokyo-1 · SOCKS5H · 198.51.100.30:1080 · 1 个账号仍在用")
        let expiry = element("proxyEdit.section.expiry"), status = element("proxyEdit.section.status")
        let fallback = element("proxyEdit.section.fallback")
        XCTAssertTrue(expiry.exists && status.exists && fallback.exists, app.debugDescription)
        XCTAssertEqual(expiry.label, "有效期 · 续期")
        XCTAssertLessThan(expiry.frame.minY, status.frame.minY, app.debugDescription)
        XCTAssertLessThan(status.frame.minY, fallback.frame.minY, app.debugDescription)
        let states = app.segmentedControls["proxyEdit.status"]
        XCTAssertTrue(states.buttons["停用"].isSelected, app.debugDescription)
        let submit = app.buttons["proxyEdit.submit"]
        XCTAssertEqual(submit.label, "保存")
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        states.buttons["正常"].tap()
        let footnote = element("proxyEdit.footnote.status")
        XCTAssertTrue(waitForLabel(footnote, containing: "有效期已过，改回“正常”前先在上面选新的有效期。"), footnote.label)
        XCTAssertFalse(submit.isEnabled, app.debugDescription)
        states.buttons["停用"].tap()
        app.buttons["proxyEdit.expiry.30"].tap()
        XCTAssertTrue(waitForSelected(states.buttons["正常"]), app.debugDescription)
        XCTAssertTrue(waitForLabel(submit, containing: "续期"), submit.label)
        XCTAssertTrue(waitForEnabled(submit), app.debugDescription)
        let name = element("proxyEdit.section.name")
        reveal(name)
        if fallback.exists { XCTAssertLessThan(fallback.frame.minY, name.frame.minY, app.debugDescription) }
        submit.tap()
        waitForReceipt("已续期 · jp-tokyo-1 恢复正常")
        XCTAssertTrue(waitForLabel(element("proxy.detail.badge"), containing: "正常"), app.debugDescription)
    }

    /// 14.4: nothing changed, the sheet is swiped away; changed, a swipe and 取消 both ask “放弃修改？” first.
    @MainActor func testUnsavedChangesAskBeforeDismiss() {
        openDetail(1, title: "hk-02")
        defer { diagnostics("proxy-edit-discard-final") }
        openEditor("proxy.action.edit", title: "编辑代理")
        dragSheetDown("编辑代理")
        XCTAssertTrue(app.navigationBars["编辑代理"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        openEditor("proxy.action.edit", title: "编辑代理")
        let name = app.textFields["proxyEdit.name"]
        replaceText(in: name, with: "hk-02-edit")
        dragSheetDown("编辑代理")
        let discard = app.alerts["放弃修改？"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["继续编辑"].tap()
        XCTAssertEqual(name.value as? String, "hk-02-edit")
        app.buttons["proxyEdit.cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["放弃修改"].tap()
        XCTAssertTrue(app.navigationBars["编辑代理"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["hk-02"].exists, app.debugDescription)
    }

    /// 14.2: the backup candidates leave the proxy out and grey the stopped and expired ones; a backup deleted meanwhile keeps the
    /// sheet open with the reason under 到期回退.
    @MainActor func testBackupCandidatesAndGoneReason() {
        launchProxies()
        defer { diagnostics("proxy-edit-backup-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        openAdd()
        fillNewProxy("fr-par-1")
        element("proxyEdit.form").swipeUp()
        let modes = app.segmentedControls["proxyEdit.fallback"]
        reveal(modes)
        modes.buttons["备用代理"].tap()
        // The form builds its rows as they scroll in: the footer under the candidates exists only once on screen.
        let issue = element("proxyEdit.issue.fallback")
        reveal(issue)
        XCTAssertEqual(issue.label, "选了备用代理回退，请选择一个备用代理")
        XCTAssertFalse(app.buttons["proxyEdit.submit"].isEnabled, app.debugDescription)
        let sg = app.buttons["proxyEdit.backup.2"], stopped = app.buttons["proxyEdit.backup.6"], expired = app.buttons["proxyEdit.backup.3"]
        reveal(sg)
        XCTAssertFalse(stopped.isEnabled, app.debugDescription)
        XCTAssertTrue(stopped.label.contains("停用"), stopped.label)
        XCTAssertFalse(expired.isEnabled, app.debugDescription)
        XCTAssertTrue(expired.label.contains("已过期"), expired.label)
        sg.tap()
        XCTAssertTrue(issue.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitForEnabled(app.buttons["proxyEdit.submit"]), app.debugDescription)
        app.terminate()

        openDetail(4, title: "hk-01", arguments: [EditArgument.backupGone])
        openEditor("proxy.action.edit", title: "编辑代理")
        let chosen = app.buttons["proxyEdit.backup.1"]
        reveal(chosen)
        XCTAssertTrue(chosen.isSelected, app.debugDescription)
        XCTAssertFalse(app.buttons["proxyEdit.backup.4"].exists, app.debugDescription)
        let other = app.buttons["proxyEdit.backup.2"]
        reveal(other)
        other.tap()
        app.buttons["proxyEdit.submit"].tap()
        XCTAssertTrue(app.buttons["proxyEdit.submit"].waitForExistence(timeout: 8), app.debugDescription)
        let gone = element("proxyEdit.issue.fallback")
        reveal(gone)
        XCTAssertEqual(gone.label, "备用代理已不存在，请重新选择")
        XCTAssertTrue(app.navigationBars["编辑代理"].exists, app.debugDescription)
    }

    /// 00 §2.5.4: the add went through but its reply was lost, so the sheet stays with 核对 and 用同一编号重试. A swipe and 取消
    /// ask “结果未确认” rather than “放弃修改？”; 继续核对 keeps the sheet, 稍后核对 closes it and the list reads the new proxy.
    @MainActor func testUnconfirmedAddAsksBeforeClosing() {
        launchProxies([EditArgument.addLost])
        defer { diagnostics("proxy-edit-unconfirmed-final") }
        XCTAssertTrue(row(8).waitForExistence(timeout: 10), app.debugDescription)
        openAdd()
        fillNewProxy("fr-par-1")
        app.buttons["proxyEdit.submit"].tap()
        XCTAssertTrue(app.buttons["proxyEdit.reconcile"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["proxyEdit.retrySame"].exists, app.debugDescription)
        dragSheetDown("添加代理")
        let later = app.alerts["结果未确认"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.alerts["放弃修改？"].exists, app.debugDescription)
        later.buttons["继续核对"].tap()
        XCTAssertTrue(later.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["添加代理"].exists, app.debugDescription)
        XCTAssertFalse(row(9).exists, app.debugDescription)
        app.buttons["proxyEdit.cancel"].tap()
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
        later.buttons["稍后核对"].tap()
        XCTAssertTrue(app.navigationBars["添加代理"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(9).waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - S6-14 helpers

    @MainActor private func openAdd() {
        app.buttons["proxies.add"].tap()
        XCTAssertTrue(app.navigationBars["添加代理"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The detail's 编辑 or 续期 button.
    @MainActor private func openEditor(_ button: String, title: String) {
        let item = app.buttons[button]
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        item.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["proxyEdit.submit"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func fillNewProxy(_ name: String) {
        typeIn("proxyEdit.name", name)
        typeIn("proxyEdit.host", "198.51.100.9")
        typeIn("proxyEdit.port", "1080")
    }
    @MainActor private func typeIn(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap()
        field.typeText(text)
    }
    /// A tap snaps the caret to a word boundary, so each pass double-taps the word at the trailing edge and deletes the selection
    /// (as AccountEditUITests); an empty field reports its placeholder as its value.
    @MainActor private func replaceText(in field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        field.tap()
        for _ in 0..<12 {
            let current = (field.value as? String) ?? ""
            if current.isEmpty || current == field.placeholderValue { break }
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).doubleTap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, app.debugDescription, file: file, line: line)
    }
    /// Dragged from the sheet's bar towards the bottom.
    @MainActor private func dragSheetDown(_ title: String) {
        app.navigationBars[title].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    }
    @MainActor private func waitForValue(_ item: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
