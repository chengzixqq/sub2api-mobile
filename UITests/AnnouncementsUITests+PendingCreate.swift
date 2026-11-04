import XCTest

/// U-22 (S6-高-13): a new announcement left at 稍后核对 (`-ui-announcement-save-lost` loses the session's first create) makes
/// the next 新建 ask “上一条公告的新建结果未确认” first: 继续核对 / 仍要新建 / 取消.
extension AnnouncementsUITests {
    /// 继续核对 opens the same attempt as it was left, the form as sent with 用同一编号重试; the retry saves it, and the next 新建
    /// no longer asks.
    @MainActor func testComposeOffersUnconfirmedCreateFirst() {
        leaveCreateUnconfirmed()
        defer { diagnostics("announcement-compose-intercept-final") }
        let intercept = composeIntercept()
        let message = NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "「系统升级预告」· ", "服务器可能已经创建了它，先核对")
        XCTAssertTrue(intercept.staticTexts.matching(message).firstMatch.exists, app.debugDescription)
        diagnostics("announcement-compose-intercept")
        intercept.buttons["继续核对"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(editButton("retry").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.textFields["announcement.edit.title"].value as? String, "系统升级预告")
        editButton("retry").tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已存为草稿"), app.debugDescription)
        XCTAssertTrue(app.navigationBars["新建公告"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "草稿 2").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists || editButton("retry").exists, app.debugDescription)
    }

    /// 取消 leaves everything as it was; 仍要新建 drops the record and opens a blank form, after which 新建 no longer asks.
    @MainActor func testNewAnnouncementDiscardsPendingRecord() {
        leaveCreateUnconfirmed()
        defer { diagnostics("announcement-compose-discard-final") }
        composeIntercept().buttons["取消"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "草稿 1").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.navigationBars["新建公告"].exists || app.staticTexts["receipt.text"].exists, app.debugDescription)
        composeIntercept().buttons["仍要新建"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        let title = app.textFields["announcement.edit.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertNotEqual(title.value as? String, "系统升级预告")
        XCTAssertFalse(editButton("retry").exists || editButton("trailing").isEnabled, app.debugDescription)
        diagnostics("announcement-compose-discard")
        editButton("cancel").tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    /// 新建 → 存草稿, whose reply is lost → 取消 → 稍后核对: the session keeps the attempt; the list still has one draft.
    @MainActor private func leaveCreateUnconfirmed() {
        launchAnnouncements(["-ui-announcement-save-lost"])
        XCTAssertTrue(segmentButton(labeled: "草稿 1").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        fillEdit(title: "系统升级预告", content: "本周六凌晨升级")
        editButton("trailing").tap()
        XCTAssertTrue(editButton("retry").waitForExistence(timeout: 10), app.debugDescription)
        editButton("cancel").tap()
        let later = app.alerts["结果未确认"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
        later.buttons["稍后核对"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForNonExistence(timeout: 5), app.debugDescription)
    }
    /// 新建 with the record kept: the question, not the sheet.
    @MainActor private func composeIntercept() -> XCUIElement {
        app.buttons["announcements.compose"].tap()
        let intercept = app.alerts["上一条公告的新建结果未确认"]
        XCTAssertTrue(intercept.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.navigationBars["新建公告"].exists, app.debugDescription)
        return intercept
    }
}
