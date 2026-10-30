import XCTest

/// 60 §15 公告列表 on the AnnouncementFixtures data: 31 / 30 / 33 / 32 展示中, 29 草稿, 27 / 24 / 21 已归档. The app and the
/// helpers are internal so S6-17…S6-19 can add their cases in extensions or at the end of this class.
final class AnnouncementsUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    @MainActor func testDirectoryOpensListWithSubtitleAndSegments() {
        launchAnnouncements()
        defer { diagnostics("announcements-open-final") }
        XCTAssertTrue(element("announcements.list").exists, app.debugDescription)
        XCTAssertTrue(text("公告站点 · 8 条").waitForExistence(timeout: 10), app.debugDescription)
        for title in ["全部 8", "展示中 4", "草稿 1", "已归档 3"] {
            XCTAssertTrue(segmentButton(labeled: title).waitForExistence(timeout: 10), "\(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(segment("全部").isSelected, app.debugDescription)
        XCTAssertTrue(app.buttons["announcements.compose"].exists, app.debugDescription)
    }

    @MainActor func testRowsShowTargetScheduleAndStatus() {
        launchAnnouncements()
        defer { diagnostics("announcements-rows-final") }
        let maintenance = row(31)
        XCTAssertTrue(maintenance.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["10 月 18 日凌晨维护通知", "展示中", "所有用户", "弹窗 · "] {
            XCTAssertTrue(maintenance.label.contains(part), "\(maintenance.label) ∌ \(part)")
        }
        XCTAssertTrue(waitForLabel(row(30), containing: "订阅 企业专线"), row(30).label)
        XCTAssertTrue(row(30).label.contains("静默 · 立即 – 永久"), row(30).label)
        XCTAssertTrue(row(33).label.contains("（未开始）") && row(33).label.contains("余额 ≥ $10.00"), row(33).label)
        reveal(row(32))
        XCTAssertTrue(row(32).label.contains("（已结束）") && row(32).label.contains("订阅 分组 #99"), row(32).label)
        reveal(row(21))
        XCTAssertTrue(row(24).label.contains(" 且 ") && row(24).label.contains(" 或 "), row(24).label)
        XCTAssertTrue(row(24).label.contains("已归档"), row(24).label)
        XCTAssertTrue(row(21).label.contains("订阅 高级组、企业专线"), row(21).label)
    }

    @MainActor func testSegmentSwitchFiltersRows() {
        launchAnnouncements()
        defer { diagnostics("announcements-segments-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        segment("草稿").tap()
        XCTAssertTrue(row(29).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(31).exists, app.debugDescription)
        for part in ["余额不足提醒", "草稿", "余额 < $5.00", "弹窗 · 更新于"] {
            XCTAssertTrue(row(29).label.contains(part), "\(row(29).label) ∌ \(part)")
        }
        segment("已归档").tap()
        XCTAssertTrue(row(27).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(24).exists && row(21).exists, app.debugDescription)
        XCTAssertFalse(row(31).exists || row(29).exists, app.debugDescription)
        segment("全部").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(29).exists, app.debugDescription)
    }

    @MainActor func testReadProgressShownWithCapabilityAndNeverOnDrafts() {
        launchAnnouncements()
        defer { diagnostics("announcements-read-progress-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(31).label.contains("已读 410/1,036"), row(31).label)
        XCTAssertTrue(row(30).label.contains("已读 12/38"), row(30).label)
        segment("草稿").tap()
        XCTAssertTrue(row(29).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(29).label.contains("已读"), row(29).label)
    }

    @MainActor func testReadProgressHiddenWithoutCapability() {
        launchAnnouncements(["-ui-without-capabilities", "announcements.read_stats"])
        defer { diagnostics("announcements-no-read-stats-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row(31).label.contains("所有用户") && row(31).label.contains("展示中"), row(31).label)
        XCTAssertFalse(row(31).label.contains("已读"), row(31).label)
        XCTAssertFalse(row(30).label.contains("已读"), row(30).label)
    }

    @MainActor func testEmptySegmentShowsNoSuchAnnouncements() {
        launchAnnouncements(["-ui-announcements-no-archived"])
        defer { diagnostics("announcements-empty-segment-final") }
        XCTAssertTrue(segmentButton(labeled: "已归档 0").waitForExistence(timeout: 10), app.debugDescription)
        segment("已归档").tap()
        let empty = element("announcements.segment.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(empty.label.contains("没有这类公告"), empty.label)
        XCTAssertFalse(element("announcements.empty").exists, app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "全部 5").exists, app.debugDescription)
        segment("全部").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testNoAnnouncementsShowsCreateEntry() {
        launchAnnouncements(["-ui-announcements-empty"])
        defer { diagnostics("announcements-empty-final") }
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["还没有公告"].exists, app.debugDescription)
        let create = app.buttons["announcements.empty.create"]
        XCTAssertTrue(create.exists && create.label == "新建公告", app.debugDescription)
        create.tap()
        // S6-18: the edit sheet; 取消 without changes closes it at once.
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcement.edit.cancel"].tap()
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testComposeOpensNewAnnouncementSheet() {
        launchAnnouncements()
        defer { diagnostics("announcements-compose-final") }
        app.buttons["announcements.compose"].tap()
        // S6-18: the edit sheet; 取消 without changes closes it at once.
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcement.edit.cancel"].tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenHidesCompose() {
        launchAnnouncements(readOnlyToken: true)
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.compose"].exists, app.debugDescription)
        diagnostics("announcements-readonly-list")
        app.terminate()
        launchAnnouncements(["-ui-announcements-empty"], readOnlyToken: true)
        defer { diagnostics("announcements-readonly-empty-final") }
        XCTAssertTrue(element("announcements.empty").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.empty.create"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["announcements.compose"].exists, app.debugDescription)
    }

    @MainActor func testFailureThenRetry() {
        launchAnnouncements(["-ui-announcements-error"])
        defer { diagnostics("announcements-failure-final") }
        XCTAssertTrue(element("announcements.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["暂时无法加载"].exists, app.debugDescription)
        app.buttons["重试"].tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("announcements.failure").exists, app.debugDescription)
    }

    @MainActor func testCountsFailureShowsSegmentNamesOnly() {
        launchAnnouncements(["-ui-announcements-counts-error"])
        defer { diagnostics("announcements-counts-failure-final") }
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        let labels = app.segmentedControls["announcements.segment"].buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["全部", "展示中", "草稿", "已归档"], app.debugDescription)
        XCTAssertTrue(text("公告站点 · 8 条").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testScrollingLoadsNextPageAndRetries() {
        launchAnnouncements(["-ui-announcements-many", "-ui-announcements-page-error"])
        defer { diagnostics("announcements-next-page-final") }
        XCTAssertTrue(segmentButton(labeled: "全部 33").waitForExistence(timeout: 10), app.debugDescription)
        let retry = app.buttons["announcements.more.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 16))
        XCTAssertEqual(retry.label, "加载失败 · 重试")
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(row(101), maxSwipes: 16))
        XCTAssertTrue(row(101).label.contains("历史公告 1"), row(101).label)
        XCTAssertFalse(retry.exists, app.debugDescription)
    }

    @MainActor func testRowPushesDetailRoute() {
        launchAnnouncements()
        defer { diagnostics("announcements-push-final") }
        segment("展示中").tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        row(31).tap()
        // S6-17: the detail page.
        XCTAssertTrue(element("announcement.detail").waitForExistence(timeout: 10) && app.navigationBars["公告"].exists, app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment("展示中").isSelected, app.debugDescription)
        XCTAssertFalse(row(29).exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Signs in to “公告站点” (an access token with `readOnlyToken`, so `-ui-readonly-token` makes it read-only) and opens 公告
    /// from the search tab's directory.
    @MainActor func launchAnnouncements(_ arguments: [String] = [], readOnlyToken: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + (readOnlyToken ? ["-ui-readonly-token"] : [])
        app.launchQuietly()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://announcements.example.invalid", in: app.textFields["login.url"])
        enter("公告站点", in: app.textFields["login.name"])
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
        app.openSearchItem("search.item.announcements")
        XCTAssertTrue(app.navigationBars["公告"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func row(_ id: Int) -> XCUIElement { app.buttons["announcement.row.\(id)"] }
    /// A segment by the start of its title (“全部 8” or only “全部” when its count failed).
    @MainActor func segment(_ title: String) -> XCUIElement {
        app.segmentedControls["announcements.segment"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    @MainActor func segmentButton(labeled label: String) -> XCUIElement {
        app.segmentedControls["announcements.segment"].buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    /// A list row: scrolled between the bars (UITestNavigation).
    @MainActor func reveal(_ item: XCUIElement, down: Bool = true) { app.scrollUntilExists(item, towardBottom: down) }
    @MainActor func waitForLabel(_ item: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor private func tap(_ item: XCUIElement) { revealLoginField(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard, toward a field already passed or further down, until it can be tapped.
    @MainActor private func revealLoginField(_ item: XCUIElement) {
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

    // MARK: - 详情（S6-17）

    @MainActor func testDetailDraftPublishConfirmation() {
        launchAnnouncements()
        openDetail(29)
        defer { diagnostics("announcement-detail-publish-final") }
        XCTAssertTrue(text("草稿 · 弹窗").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(detailButton("publish").exists && detailButton("edit").exists, app.debugDescription)
        XCTAssertFalse(detailButton("archive").exists || element("announcement.detail.reads").exists, app.debugDescription)
        detailButton("publish").tap()
        let alert = app.alerts["发布「余额不足提醒」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["余额 < $5.00 · 用户打开时弹窗提示", "有效期 立即 – 永久"] {
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch.exists, "\(part)\n\(app.debugDescription)")
        }
        alert.buttons["发布"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已发布 · 符合条件的用户能看到"), app.debugDescription)
        XCTAssertTrue(detailButton("archive").waitForExistence(timeout: 10) && detailButton("edit").exists, app.debugDescription)
        XCTAssertFalse(detailButton("publish").exists, app.debugDescription)
    }

    @MainActor func testDetailActiveArchiveAndUndo() {
        launchAnnouncements()
        openDetail(30)
        defer { diagnostics("announcement-detail-archive-final") }
        XCTAssertTrue(detailButton("archive").exists && detailButton("edit").exists, app.debugDescription)
        detailButton("archive").tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已归档 · 用户不再看到"), app.debugDescription)
        XCTAssertTrue(detailButton("republish").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(detailButton("archive").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(detailButton("republish").exists, app.debugDescription)
    }

    @MainActor func testDetailArchivedButtonsAndMenu() {
        launchAnnouncements()
        openDetail(27)
        defer { diagnostics("announcement-detail-menu-final") }
        XCTAssertTrue(detailButton("republish").exists && detailButton("edit").exists, app.debugDescription)
        XCTAssertFalse(detailButton("archive").exists, app.debugDescription)
        openMoreMenu()
        for title in ["编辑公告", "重新发布", "已读情况", "删除公告…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
        }
        for line in ["国庆期间客服时间调整", "已归档 · 静默"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", line)).firstMatch.exists, "\(line)\n\(app.debugDescription)")
        }
    }

    @MainActor func testDetailEditOpensEditSheet() {
        launchAnnouncements()
        openDetail(31)
        defer { diagnostics("announcement-detail-edit-final") }
        detailButton("edit").tap()
        // S6-18: the edit sheet; 取消 without changes closes it at once.
        XCTAssertTrue(app.navigationBars["编辑公告"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcement.edit.cancel"].tap()
        XCTAssertTrue(element("announcement.detail").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testDetailDeleteByTypingTitle() {
        launchAnnouncements()
        openDetail(27)
        defer { diagnostics("announcement-detail-delete-final") }
        openMoreMenu()
        menuItem("删除公告…").tap()
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 10), app.debugDescription)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = app.textFields["delete.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { input.tap() }
        input.typeText("国庆期间客服时间调整")
        XCTAssertTrue(confirm.isEnabled, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已删除公告「国庆期间客服时间调整」"), app.debugDescription)
        XCTAssertTrue(element("announcements.list").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("announcement.detail").exists, app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "已归档 2").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(27).exists, app.debugDescription)
    }

    @MainActor func testDetailDeleteWithFaceID() {
        launchAnnouncements(["-ui-faceid-on"])
        openDetail(21)
        defer { diagnostics("announcement-detail-delete-faceid-final") }
        openMoreMenu()
        menuItem("删除公告…").tap()
        XCTAssertTrue(element("delete.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.textFields["delete.input"].exists, app.debugDescription)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        confirm.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已删除公告「高级组与企业专线限额调整」"), app.debugDescription)
        XCTAssertTrue(element("announcements.list").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row(21).exists, app.debugDescription)
    }

    @MainActor func testDetailPreviewStylesAndMarkdown() {
        launchAnnouncements()
        openDetail(31)
        defer { diagnostics("announcement-detail-preview-final") }
        XCTAssertTrue(waitForLabel(element("announcement.preview.label"), containing: "用户看到的样子 · 弹窗"), app.debugDescription)
        XCTAssertTrue(element("announcement.preview.dismiss").exists, app.debugDescription)
        XCTAssertTrue(element("announcement.markdown.list.2.item.0").exists && element("announcement.markdown.list.2.item.1").exists, app.debugDescription)
        XCTAssertTrue(element("announcement.markdown.list.2.item.1").label.contains("控制台暂停充值与兑换"), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openDetail(24)
        XCTAssertTrue(waitForLabel(element("announcement.preview.label"), containing: "用户看到的样子 · 静默"), app.debugDescription)
        XCTAssertFalse(element("announcement.preview.dismiss").exists, app.debugDescription)
        XCTAssertEqual(element("announcement.markdown.heading.0").label, "计费口径")
        XCTAssertTrue(element("announcement.markdown.list.1.item.1").label.contains("缓存读取按官方折扣计费"), app.debugDescription)
    }

    @MainActor func testDetailReadsRow() {
        launchAnnouncements()
        openDetail(31)
        defer { diagnostics("announcement-detail-reads-final") }
        let reads = element("announcement.detail.reads")
        app.scrollUntilExists(reads)
        XCTAssertTrue(waitForLabel(reads, containing: "已读 410 / 符合条件 1,036"), reads.label)
        XCTAssertTrue(reads.label.contains("另有 2 人读后已不符合条件"), reads.label)
        reads.tap()
        // The 已读情况 page (S6-19).
        XCTAssertTrue(app.navigationBars["已读情况"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testDetailReadsRowFallbacks() {
        for arguments in [["-ui-without-capabilities", "announcements.read_stats"], ["-ui-announcement-detail-summary-error"]] {
            launchAnnouncements(arguments)
            openDetail(31)
            let reads = element("announcement.detail.reads")
            app.scrollUntilExists(reads)
            XCTAssertTrue(waitForLabel(reads, containing: "逐个用户看：是否符合条件、什么时候读的"), "\(arguments) \(reads.label)")
            XCTAssertFalse(reads.label.contains("已读 410"), "\(arguments) \(reads.label)")
            diagnostics("announcement-detail-reads-fallback")
            app.terminate()
        }
        launchAnnouncements()
        openDetail(29)
        defer { diagnostics("announcement-detail-reads-draft-final") }
        XCTAssertTrue(element("announcement.detail.created").exists || app.scrollUntilExists(element("announcement.detail.created")), app.debugDescription)
        XCTAssertFalse(element("announcement.detail.reads").exists, app.debugDescription)
    }

    @MainActor func testDetailReadOnlyTokenHidesButtons() {
        launchAnnouncements(readOnlyToken: true)
        openDetail(31)
        defer { diagnostics("announcement-detail-readonly-final") }
        for action in ["publish", "archive", "republish", "edit"] { XCTAssertFalse(detailButton(action).exists, "\(action)\n\(app.debugDescription)") }
        openMoreMenu()
        for title in ["编辑公告", "归档", "删除公告…"] {
            XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
            XCTAssertFalse(menuItem(title).isEnabled, "\(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(menuItem("已读情况").isEnabled, app.debugDescription)
    }

    @MainActor func testDetailMissingShowsGonePage() {
        launchAnnouncements(["-ui-announcement-detail-missing"])
        defer { diagnostics("announcement-detail-missing-final") }
        openDetail(32, waitingFor: "announcement.detail.gone")
        XCTAssertTrue(element("announcement.detail.gone").label.contains("已删除"), app.debugDescription)
        XCTAssertFalse(app.buttons["announcement.detail.more"].exists || detailButton("edit").exists, app.debugDescription)
    }

    /// From the list: the first row once it is read, then the row (scrolled to: lower rows are not made yet) and its page.
    @MainActor private func openDetail(_ id: Int, waitingFor identifier: String = "announcement.detail") {
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
        reveal(row(id))
        row(id).tap()
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func detailButton(_ action: String) -> XCUIElement { app.buttons["announcement.detail.\(action)"] }
    @MainActor private func openMoreMenu() {
        let more = app.buttons["announcement.detail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
    }
    /// A ··· entry by its title, not the button row's button of the same name.
    @MainActor private func menuItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "announcement.detail.")).firstMatch
    }

    // MARK: - 编辑 / 新建（S6-18）

    @MainActor func testComposeSavesDraft() {
        launchAnnouncements()
        defer { diagnostics("announcement-edit-draft-final") }
        XCTAssertTrue(segmentButton(labeled: "草稿 1").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        let save = editButton("trailing")
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.label == "存草稿", app.debugDescription)
        XCTAssertFalse(save.isEnabled, app.debugDescription)
        XCTAssertEqual(editButton("primary").label, "发布")
        fillEdit(title: "系统升级预告", content: "本周六凌晨升级")
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        save.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已存为草稿"), app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "草稿 2").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.navigationBars["新建公告"].exists, app.debugDescription)
    }

    @MainActor func testBalanceConditionPublishShowsConfirmation() {
        launchAnnouncements()
        defer { diagnostics("announcement-edit-publish-final") }
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("announcement.edit.targetFootnote").label.contains("所有用户都能看到。"), app.debugDescription)
        let targetMode = app.segmentedControls["announcement.edit.targetMode"]
        app.scrollUntilExists(targetMode)
        targetMode.buttons["按条件"].tap()
        let below = app.buttons["announcement.edit.operator.lt"]
        XCTAssertTrue(below.waitForExistence(timeout: 5) && below.isSelected, app.debugDescription)
        XCTAssertEqual(app.textFields["announcement.edit.amount"].value as? String, "5")
        XCTAssertTrue(element("announcement.edit.targetFootnote").label.contains("手机上设一个条件"), app.debugDescription)
        fillEdit(title: "余额提醒", content: "请及时充值")
        editButton("primary").tap()
        let alert = app.alerts["发布「余额提醒」？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["余额 < $5.00 · 静默出现在通知里", "有效期 立即 – 永久"] {
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch.exists, "\(part)\n\(app.debugDescription)")
        }
        alert.buttons["发布"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已发布公告"), app.debugDescription)
        XCTAssertTrue(segmentButton(labeled: "展示中 5").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testMultiConditionAnnouncementIsReadOnly() {
        launchAnnouncements()
        openDetail(24)
        defer { diagnostics("announcement-edit-locked-final") }
        detailButton("edit").tap()
        XCTAssertTrue(app.navigationBars["编辑公告"].waitForExistence(timeout: 10), app.debugDescription)
        let first = element("announcement.edit.locked.0"), second = element("announcement.edit.locked.1")
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(first.label.hasPrefix("条件") && first.label.contains(" 且 "), first.label)
        XCTAssertTrue(second.label.hasPrefix("或") && second.label.contains("余额 ≥ $500.00"), second.label)
        XCTAssertTrue(element("announcement.edit.targetFootnote").label.contains("手机上只读；要修改请在 Web 编辑。"), app.debugDescription)
        XCTAssertFalse(app.segmentedControls["announcement.edit.targetMode"].exists, app.debugDescription)
        XCTAssertEqual(editButton("trailing").label, "保存")
        XCTAssertEqual(editButton("primary").label, "重新发布")
        let body = app.textViews["announcement.edit.content"]
        body.tap()
        body.typeText("补充说明")
        editButton("trailing").tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["receipt.text"], containing: "已保存"), app.debugDescription)
        XCTAssertTrue(element("announcement.detail").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.navigationBars["编辑公告"].exists, app.debugDescription)
    }

    @MainActor func testOverlongTitleDisablesSave() {
        launchAnnouncements()
        defer { diagnostics("announcement-edit-long-title-final") }
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        // 201 bytes, as 67 汉字 would be.
        fillEdit(title: String(repeating: "a", count: 201), content: "正文")
        let footnote = element("announcement.edit.titleFootnote")
        XCTAssertTrue(footnote.waitForExistence(timeout: 5) && footnote.label == "标题太长（最多约 66 个汉字）", app.debugDescription)
        XCTAssertFalse(editButton("trailing").isEnabled || editButton("primary").isEnabled, app.debugDescription)
        let title = app.textFields["announcement.edit.title"]
        title.tap()
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(footnote.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(editButton("trailing").isEnabled && editButton("primary").isEnabled, app.debugDescription)
    }

    @MainActor func testEditPreviewToggle() {
        launchAnnouncements()
        defer { diagnostics("announcement-edit-preview-final") }
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        fillEdit(title: "预览测试", content: "## 计费\n- 第一条")
        XCTAssertTrue(waitForLabel(element("announcement.edit.count"), containing: "11 字"), element("announcement.edit.count").label)
        let mode = app.segmentedControls["announcement.edit.mode"]
        mode.buttons["预览"].tap()
        XCTAssertTrue(element("announcement.edit.preview").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("announcement.preview.title").label, "预览测试")
        XCTAssertEqual(element("announcement.markdown.heading.0").label, "计费")
        XCTAssertTrue(element("announcement.markdown.list.1.item.0").label.contains("第一条"), app.debugDescription)
        XCTAssertFalse(element("announcement.preview.dismiss").exists, app.debugDescription)
        mode.buttons["编辑"].tap()
        let body = app.textViews["announcement.edit.content"]
        XCTAssertTrue(body.waitForExistence(timeout: 5) && (body.value as? String)?.contains("第一条") == true, app.debugDescription)
        let notify = app.segmentedControls["announcement.edit.notify"]
        app.scrollUntilExists(notify)
        notify.buttons["弹窗"].tap()
        XCTAssertTrue(waitForLabel(element("announcement.edit.notifyFootnote"), containing: "弹窗模式会自动弹出通知给用户。"), app.debugDescription)
        mode.buttons["预览"].tap()
        XCTAssertTrue(element("announcement.preview.dismiss").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testUnsavedChangesAskBeforeDiscard() {
        launchAnnouncements()
        defer { diagnostics("announcement-edit-discard-final") }
        app.buttons["announcements.compose"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForExistence(timeout: 10), app.debugDescription)
        editButton("cancel").tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        app.buttons["announcements.compose"].tap()
        let title = app.textFields["announcement.edit.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        title.tap()
        title.typeText("草稿标题")
        editButton("cancel").tap()
        let discard = app.alerts["放弃修改？"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["继续编辑"].tap()
        XCTAssertEqual(title.value as? String, "草稿标题")
        // Dragged from the bar towards the bottom: the sheet holds and asks instead of closing.
        app.navigationBars["新建公告"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["放弃修改"].tap()
        XCTAssertTrue(app.navigationBars["新建公告"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row(31).waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func editButton(_ name: String) -> XCUIElement { app.buttons["announcement.edit.\(name)"] }
    /// Types into the title, then the body (the keyboard stays up).
    @MainActor private func fillEdit(title: String, content: String) {
        let titleField = app.textFields["announcement.edit.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        titleField.tap()
        titleField.typeText(title)
        let body = app.textViews["announcement.edit.content"]
        body.tap()
        body.typeText(content)
    }

    // MARK: - 已读情况（S6-19）

    /// The fixture roster (26 users, ten a page) is the same for every announcement; the bar's summary is 31's read_stats.
    @MainActor func testReadsPageShowsSummaryRowsAndOpensUser() {
        openReadsPage()
        defer { diagnostics("announcement-reads-final") }
        let summary = element("announcementReads.summary")
        XCTAssertTrue(waitForLabel(summary, containing: "已读 412 · 符合条件 1,036 · 共 1,036 位用户 · 统计于"), summary.label)
        XCTAssertTrue(text("10 月 18 日凌晨维护通知").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.segmentedControls["announcementReads.state"].exists, app.debugDescription)
        let alice = readRow(1)
        XCTAssertTrue(alice.waitForExistence(timeout: 10), app.debugDescription)
        for part in ["alice@example.com", "$12.40", "alice", "符合条件", "10/16 08:12"] {
            XCTAssertTrue(alice.label.contains(part), "\(alice.label) ∌ \(part)")
        }
        XCTAssertTrue(readRow(2).label.contains("未读"), readRow(2).label)
        XCTAssertFalse(element("announcementReads.found").exists, app.debugDescription)
        reveal(readRow(6))
        XCTAssertTrue(readRow(6).label.contains("不符合"), readRow(6).label)
        XCTAssertTrue(readRow(5).label.hasPrefix("erin@example.com"), readRow(5).label)
        reveal(alice, down: false)
        alice.tap()
        XCTAssertTrue(element("announcementReads.list").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).exists, app.debugDescription)
    }

    @MainActor func testReadsSegmentAndEligibleOnlyFilter() {
        openReadsPage()
        defer { diagnostics("announcement-reads-filter-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        app.segmentedControls["announcementReads.state"].buttons["已读"].tap()
        let found = element("announcementReads.found")
        XCTAssertTrue(found.waitForExistence(timeout: 10) && waitForLabel(found, containing: "找到 7 位"), app.debugDescription)
        XCTAssertTrue(readRow(6).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(readRow(2).exists, app.debugDescription)
        let eligibleOnly = app.switches["announcementReads.eligibleOnly"]
        XCTAssertTrue(eligibleOnly.exists, app.debugDescription)
        eligibleOnly.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
        XCTAssertTrue(waitForLabel(found, containing: "找到 6 位"), found.label)
        XCTAssertTrue(readRow(6).waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(readRow(1).exists, app.debugDescription)
    }

    @MainActor func testReadsSortMenu() {
        openReadsPage()
        defer { diagnostics("announcement-reads-sort-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        openReadsSortMenu()
        for title in ["按邮箱", "按用户名", "按余额", "按阅读时间"] {
            XCTAssertTrue(readsSortItem(title).waitForExistence(timeout: 5), "\(title)\n\(app.debugDescription)")
        }
        XCTAssertTrue(readsSortItem("按余额").label.contains("从高到低"), readsSortItem("按余额").label)
        readsSortItem("按余额").tap()
        XCTAssertTrue(waitForLabel(app.buttons["announcementReads.sort"], containing: "按余额"), app.debugDescription)
        let nova = readRow(15)
        XCTAssertTrue(nova.waitForExistence(timeout: 10) && readRow(9).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(nova.label.contains("Nova 工作室"), nova.label)
        XCTAssertLessThan(nova.frame.minY, readRow(9).frame.minY, app.debugDescription)
        // A sort is not a filter.
        XCTAssertFalse(element("announcementReads.found").exists, app.debugDescription)
    }

    @MainActor func testReadsSearchAndEmpty() {
        openReadsPage()
        defer { diagnostics("announcement-reads-search-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        let field = app.searchFields["搜索邮箱或用户名"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("bob")
        let found = element("announcementReads.found")
        XCTAssertTrue(found.waitForExistence(timeout: 10) && waitForLabel(found, containing: "找到 1 位"), app.debugDescription)
        XCTAssertTrue(readRow(2).exists && readRow(1).waitForNonExistence(timeout: 5), app.debugDescription)
        field.typeText("zzz")
        let empty = element("announcementReads.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(empty.label.contains("没有匹配的用户"), empty.label)
        XCTAssertTrue(waitForLabel(found, containing: "找到 0 位"), found.label)
    }

    @MainActor func testReadsPaginatesOnScroll() {
        openReadsPage()
        defer { diagnostics("announcement-reads-pages-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        // Ten a page by email: page 2 starts with 26, page 3 ends with 24. The fixture answers at once, so the footer's
        // spinner is gone before a swipe can stop on it; only its absence after the last page is checked.
        XCTAssertTrue(app.scrollUntilExists(readRow(26), maxSwipes: 12))
        XCTAssertTrue(app.scrollUntilExists(readRow(24), maxSwipes: 20))
        XCTAssertTrue(element("announcementReads.more").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testReadsWithoutReadStatsCapability() {
        openReadsPage(["-ui-without-capabilities", "announcements.read_stats"])
        defer { diagnostics("announcement-reads-legacy-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        let summary = element("announcementReads.summary")
        XCTAssertTrue(waitForLabel(summary, containing: "第 1 页 · 共 26 位用户"), summary.label)
        XCTAssertFalse(app.segmentedControls["announcementReads.state"].exists, app.debugDescription)
        XCTAssertFalse(app.switches["announcementReads.eligibleOnly"].exists, app.debugDescription)
        openReadsSortMenu()
        XCTAssertTrue(readsSortItem("按余额").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(readsSortItem("按阅读时间").exists, app.debugDescription)
    }

    @MainActor func testReadsFailureAndRetry() {
        openReadsPage(["-ui-announcement-reads-error", "-ui-announcement-detail-summary-error"])
        defer { diagnostics("announcement-reads-failure-final") }
        let failure = element("announcementReads.failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["重试"].tap()
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(failure.exists, app.debugDescription)
        // A summary that failed falls back to the page's total.
        let summary = element("announcementReads.summary")
        XCTAssertTrue(waitForLabel(summary, containing: "第 1 页 · 共 26 位用户"), summary.label)
    }

    @MainActor func testReadsLoadMoreFailureRetry() {
        openReadsPage(["-ui-announcement-reads-more-error"])
        defer { diagnostics("announcement-reads-more-final") }
        XCTAssertTrue(readRow(1).waitForExistence(timeout: 10), app.debugDescription)
        let retry = app.buttons["announcementReads.more.retry"]
        XCTAssertTrue(app.scrollUntilExists(retry, maxSwipes: 10))
        XCTAssertEqual(retry.label, "加载失败 · 重试")
        retry.tap()
        XCTAssertTrue(app.scrollUntilExists(readRow(24), maxSwipes: 20))
        XCTAssertFalse(retry.exists, app.debugDescription)
    }

    /// Announcement 31's detail, then its 已读情况 row.
    @MainActor private func openReadsPage(_ arguments: [String] = []) {
        launchAnnouncements(arguments)
        openDetail(31)
        let reads = element("announcement.detail.reads")
        app.scrollUntilExists(reads)
        reads.tap()
        XCTAssertTrue(element("announcementReads.list").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func readRow(_ userID: Int) -> XCUIElement { app.buttons["announcementReads.row.\(userID)"] }
    @MainActor private func openReadsSortMenu() {
        let sort = app.buttons["announcementReads.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10), app.debugDescription)
        sort.tap()
    }
    /// A sort entry by its title; its second line is the direction.
    @MainActor private func readsSortItem(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == '' AND (label == %@ OR label BEGINSWITH %@)", title, title + ",")).firstMatch
    }
}
