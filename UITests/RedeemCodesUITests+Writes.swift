import XCTest

/// S6-05 (60 §8.4, §9): 禁用 / 启用 with 撤销, the trailing swipe, 删除 through the shared confirmation, the edit sheet for notes,
/// renewal and the 409 race, and a read-only token keeping only 复制. Writes change the session's RedeemDemoStore only.
extension RedeemCodesUITests {
    @MainActor func testDisableThenUndoRestoresUnused() {
        launchRedeem()
        defer { diagnostics("redeem-disable-final") }
        open(2046)
        let toggle = cardButton(2046, "toggle")
        XCTAssertEqual(toggle.label, "禁用")
        XCTAssertEqual(cardButton(2046, "edit").label, "编辑")
        toggle.tap()
        waitForReceipt("已禁用 · 不能再兑换")
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(waitForLabel(card(2046), containing: "未使用"), card(2046).label)
        XCTAssertTrue(waitForLabel(cardButton(2046, "toggle"), equalTo: "禁用"), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("disabled"), equalTo: "已禁用 1"), chip("disabled").label)
        toggle.tap()
        XCTAssertTrue(waitForLabel(card(2046), containing: "已禁用"), card(2046).label)
        XCTAssertTrue(waitForLabel(cardButton(2046, "toggle"), equalTo: "启用"), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("disabled"), equalTo: "已禁用 2"), chip("disabled").label)
        // A collapsed unused card offers 禁用 on a trailing swipe, never 删除.
        let other = card(2045)
        reveal(other)
        other.swipeLeft()
        let swipe = app.buttons["redeem.swipe.toggle.2045"]
        XCTAssertTrue(swipe.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(swipe.label, "禁用")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '删除'")).firstMatch.exists, app.debugDescription)
    }

    @MainActor func testDeleteTypingLastFourInAnyCase() {
        launchRedeem()
        defer { diagnostics("redeem-delete-final") }
        open(2046)
        openMenu(2046)
        let delete = menuItem("删除兑换码…")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("delete.title").label, "删除兑换码「····d4e8」？")
        let message = element("delete.message").label
        XCTAssertTrue(message.contains("站点 兑换码站点 · 删除后不能恢复。") && message.contains("余额 · $10.00 · 未使用"), message)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "删除兑换码")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("D4E")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText("8")
        XCTAssertTrue(waitForState(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        waitForReceipt("已删除兑换码「····d4e8」")
        XCTAssertTrue(card(2046).waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitForLabel(chip("all"), equalTo: "全部 10"), chip("all").label)
        // A redeemed code is never deleted.
        open(2044)
        openMenu(2044)
        XCTAssertTrue(menuItem("复制兑换码").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuItem("删除兑换码…").exists, app.debugDescription)
    }

    /// 60 §3.4: with Face ID nothing is typed; a refused check deletes nothing.
    @MainActor func testFaceIDOnDeleteButtonTitle() {
        launchRedeem(["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("redeem-delete-faceid-final") }
        openDeleteConfirmation(2045)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitForState(confirm, "isEnabled == true"), app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(card(2045).exists, app.debugDescription)
        app.terminate()

        launchRedeem(["-ui-faceid-on"])
        openDeleteConfirmation(2045)
        XCTAssertEqual(app.buttons["delete.confirm"].label, "用 Face ID 删除")
        app.buttons["delete.confirm"].tap()
        waitForReceipt("已删除兑换码「····e519」")
        XCTAssertTrue(card(2045).waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testEditNotesOnRedeemedCode() {
        launchRedeem()
        defer { diagnostics("redeem-edit-notes-final") }
        open(2031)
        let edit = cardButton(2031, "edit")
        XCTAssertEqual(edit.label, "编辑备注")
        XCTAssertFalse(app.buttons["redeem.card.2031.toggle"].exists, app.debugDescription)
        edit.tap()
        XCTAssertTrue(app.navigationBars["编辑备注"].waitForExistence(timeout: 5), app.debugDescription)
        let banner = element("redeem.edit.usedBanner")
        XCTAssertTrue(banner.label.contains("已使用的兑换码只能改备注。") && banner.label.contains("使用者 周婷 · "), banner.label)
        XCTAssertTrue(element("redeem.edit.target").label.contains("并发数 · +2 并发 · 面值生成后不能改"), element("redeem.edit.target").label)
        XCTAssertFalse(app.segmentedControls["redeem.edit.status"].exists || app.buttons["redeem.edit.expiry.never"].exists, app.debugDescription)
        let save = app.buttons["redeem.edit.save"]
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        let notes = element("redeem.edit.notes")
        notes.tap()
        notes.typeText("补发凭证已核对")
        XCTAssertTrue(waitForState(save, "isEnabled == true"), app.debugDescription)
        save.tap()
        waitForReceipt("已保存备注")
        XCTAssertTrue(app.navigationBars["编辑备注"].waitForNonExistence(timeout: 5), app.debugDescription)
        // The row reads “备注、<notes>”.
        XCTAssertTrue(waitForLabel(element("redeem.card.2031.notes"), containing: "补发凭证已核对"), app.debugDescription)
    }

    @MainActor func testRenewExpiredCodeBecomesUnused() {
        launchRedeem()
        defer { diagnostics("redeem-renew-final") }
        // Earlier than the first screen: its cell exists once scrolled to.
        reveal(card(2019))
        open(2019)
        let renew = cardButton(2019, "renew")
        XCTAssertEqual(renew.label, "续期")
        XCTAssertFalse(app.buttons["redeem.card.2019.edit"].exists || app.buttons["redeem.card.2019.toggle"].exists, app.debugDescription)
        renew.tap()
        XCTAssertTrue(app.navigationBars["续期兑换码"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["redeem.edit.cancel"].tap()
        XCTAssertTrue(app.navigationBars["续期兑换码"].waitForNonExistence(timeout: 5), app.debugDescription)
        // The collapsed card renews on a trailing swipe.
        card(2019).tap()
        XCTAssertTrue(element("redeem.card.2019.body").waitForNonExistence(timeout: 5), app.debugDescription)
        card(2019).swipeLeft()
        let swipe = app.buttons["redeem.swipe.renew.2019"]
        XCTAssertTrue(swipe.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(swipe.label, "续期")
        swipe.tap()
        XCTAssertTrue(app.navigationBars["续期兑换码"].waitForExistence(timeout: 5), app.debugDescription)
        let save = app.buttons["redeem.edit.save"]
        XCTAssertEqual(save.label, "保存")
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        let expiryHeader = text("新的过期时间"), statusRow = element("redeem.edit.statusReadonly")
        XCTAssertTrue(expiryHeader.exists && statusRow.exists, app.debugDescription)
        XCTAssertLessThan(expiryHeader.frame.minY, statusRow.frame.minY)
        XCTAssertEqual(statusRow.value as? String, "已过期")
        XCTAssertTrue(app.buttons["redeem.edit.expiry.keep"].label.hasSuffix("（已过期）"), app.buttons["redeem.edit.expiry.keep"].label)
        app.buttons["redeem.edit.expiry.d7"].tap()
        XCTAssertTrue(waitForLabel(save, equalTo: "续期"), save.label)
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        XCTAssertEqual(statusRow.value as? String, "已过期 → 未使用")
        XCTAssertTrue(element("redeem.edit.expiry.footnote").label.hasSuffix("过期，状态改回“未使用”。"), element("redeem.edit.expiry.footnote").label)
        save.tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(waitForLabel(receipt, containing: "过期，改回未使用"), receipt.label)
        XCTAssertTrue(receipt.label.hasPrefix("已续期 · "), receipt.label)
        XCTAssertTrue(waitForLabel(card(2019), containing: "未使用"), card(2019).label)
    }

    @MainActor func testReadOnlyTokenLeavesOnlyCopy() {
        launchRedeem(readOnlyToken: true)
        defer { diagnostics("redeem-readonly-writes-final") }
        open(2046)
        XCTAssertFalse(app.buttons["redeem.card.2046.toggle"].exists || app.buttons["redeem.card.2046.edit"].exists, app.debugDescription)
        openMenu(2046)
        let copy = menuItem("复制兑换码")
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuItem("删除兑换码…").exists, app.debugDescription)
        copy.tap()
        waitForReceipt("已复制兑换码")
        card(2046).tap()
        XCTAssertTrue(element("redeem.card.2046.body").waitForNonExistence(timeout: 5), app.debugDescription)
        card(2045).swipeLeft()
        XCTAssertFalse(app.buttons["redeem.swipe.toggle.2045"].waitForExistence(timeout: 2), app.debugDescription)
    }

    /// The list showed the code unused, but it was redeemed meanwhile: the sheet stays, now for notes only.
    @MainActor func testUsedRaceSwitchesToNotesOnly() {
        launchRedeem(["-ui-redeem-edit-used-race"])
        defer { diagnostics("redeem-edit-race-final") }
        open(2046)
        cardButton(2046, "edit").tap()
        XCTAssertTrue(app.navigationBars["编辑兑换码"].waitForExistence(timeout: 5), app.debugDescription)
        let status = app.segmentedControls["redeem.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        status.buttons["已禁用"].tap()
        let save = app.buttons["redeem.edit.save"]
        XCTAssertTrue(waitForState(save, "isEnabled == true"), app.debugDescription)
        save.tap()
        let message = element("redeem.edit.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(message.label.contains("这个码已被兑换，只能改备注"), message.label)
        XCTAssertTrue(app.navigationBars["编辑备注"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(status.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["redeem.edit.save"].isEnabled, app.debugDescription)
        app.buttons["redeem.edit.cancel"].tap()
        XCTAssertTrue(app.navigationBars["编辑备注"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(card(2046).label.contains("未使用"), card(2046).label)
    }

    // MARK: - Helpers

    /// A button of an open card, scrolled between the bars.
    @MainActor private func cardButton(_ id: Int, _ name: String) -> XCUIElement {
        let button = app.buttons["redeem.card.\(id).\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        reveal(button)
        return button
    }
    @MainActor private func openDeleteConfirmation(_ id: Int) {
        open(id)
        openMenu(id)
        let delete = menuItem("删除兑换码…")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func waitForState(_ item: XCUIElement, _ format: String, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)], timeout: timeout) == .completed
    }
}
