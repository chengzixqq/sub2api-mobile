import XCTest

/// S0-14: the four tabs and the search tab (10 §0.7, U14), the search directory (60 §1), the monitor placeholder, and
/// the site menu with its switch receipt (10 §0.7-5, §0.7-6). One function per tab and directory item (S1-00, X40): an item
/// changes only its own area's functions and adds new ones after the last test.
final class AppNavigationUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testTabBarAndTodayTab() {
        launchNavigationSite()
        defer { diagnostics("app-tabs-final") }
        for title in ["概览", "账号", "用户", "监控"] { XCTAssertTrue(app.tabBars.buttons[title].exists, app.debugDescription) }
        XCTAssertFalse(app.tabBars.buttons["管理"].exists)
        XCTAssertFalse(app.tabBars.buttons["设置"].exists)
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(element("home.ticker.requests").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testAccountsTabShowsAccounts() {
        launchNavigationSite()
        defer { diagnostics("app-tabs-accounts-final") }
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUsersTabShowsUsers() {
        launchNavigationSite()
        defer { diagnostics("app-tabs-users-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testMonitorTabShowsSegments() {
        launchNavigationSite()
        defer { diagnostics("app-tabs-monitor-final") }
        app.tabBars.buttons["监控"].tap()
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 5), app.debugDescription)
        // S1-13: 概况 opens first with its run section.
        XCTAssertTrue(element("monitor.run.health").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segments.segment("概况").isSelected, app.debugDescription)
    }

    @MainActor func testSearchTabShowsDirectory() {
        launchNavigationSite()
        defer { diagnostics("app-tabs-search-final") }
        app.openSearchTab()
        XCTAssertTrue(element("search.home").waitForExistence(timeout: 5), app.debugDescription)
        diagnostics("search-directory")
    }

    @MainActor func testSearchDirectoryShowsSectionsAndWebItems() {
        launchDirectorySite()
        defer { diagnostics("search-directory-final") }
        app.openSearchTab()
        XCTAssertTrue(header("记录").waitForExistence(timeout: 5), app.debugDescription)
        reveal(app.buttons["search.item.webSettings"])
        for title in ["资源", "设置", "在 Web 中打开"] { XCTAssertTrue(header(title).exists, app.debugDescription) }
        // The fixture site has payments off (DemoData), so 支付与套餐 is hidden (60 §1.3).
        XCTAssertFalse(app.buttons["search.item.webPayments"].exists)
        diagnostics("search-directory-web")
    }

    @MainActor func testSearchDirectoryOpensUsageLogs() {
        launchDirectorySite()
        defer { diagnostics("search-directory-usage-final") }
        app.openSearchItem("search.item.usage")
        assertLogsMode("请求记录")
    }

    @MainActor func testSearchDirectoryOpensErrorLogs() {
        launchDirectorySite()
        defer { diagnostics("search-directory-errors-final") }
        app.openSearchItem("search.item.errors")
        assertLogsMode("失败请求")
    }

    @MainActor func testSearchDirectoryOpensGroups() {
        launchDirectorySite()
        defer { diagnostics("search-directory-groups-final") }
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testSearchDirectoryOpensAnalytics() {
        launchDirectorySite()
        defer { diagnostics("search-directory-analytics-final") }
        app.openSearchItem("search.item.analytics")
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testSearchDirectoryOpensRedeemList() {
        launchDirectorySite()
        defer { diagnostics("search-directory-redeem-final") }
        app.openSearchItem("search.item.redeem")
        XCTAssertTrue(element("redeem.list").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["兑换码"].exists, app.debugDescription)
        XCTAssertFalse(element("route.placeholder").exists, app.debugDescription)
        diagnostics("redeem-list")
    }

    @MainActor func testSearchDirectoryOpensInterfaceSettings() {
        launchDirectorySite()
        defer { diagnostics("search-directory-interface-final") }
        app.openSearchItem("search.item.interface")
        // S0-15: the settings page opens on 界面模式 under the entry's title.
        XCTAssertTrue(app.buttons["settings.mode.main"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["界面与模式"].exists, app.debugDescription)
    }

    @MainActor func testAlertEventsSelectsMonitorAlertsSegment() {
        launchAndLogin(name: "告警站点", url: "https://alerts.example.invalid")
        defer { diagnostics("alert-events-final") }
        app.openSearchItem("search.item.alerts")
        let segments = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segments.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["监控"].isSelected, app.debugDescription)
        XCTAssertTrue(segments.segment("告警").isSelected, app.debugDescription)
        // S1-16: the segment shows its alerts (#41, 来源 LiveOpsFixtureIDs).
        XCTAssertTrue(app.descendants(matching: .any)["monitor.alerts.firing"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["monitor.alerts.row.41"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        // The intent is taken once: a segment chosen afterwards survives leaving and returning to the tab.
        segments.segment("概况").tap()
        app.tabBars.buttons["用户"].tap()
        app.tabBars.buttons["监控"].tap()
        XCTAssertTrue(segments.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(segments.segment("概况").isSelected, app.debugDescription)
    }

    @MainActor func testSearchTextShowsPlaceholder() {
        launchAndLogin(name: "搜索站点", url: "https://search.example.invalid")
        defer { diagnostics("search-text-final") }
        app.openSearchTab()
        let field = app.searchFields["搜索全部对象"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("abc")
        XCTAssertTrue(element("search.placeholder").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["search.item.usage"].exists)
        diagnostics("search-placeholder")
        let clear = field.buttons.firstMatch
        if clear.exists { clear.tap() } else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3)) }
        XCTAssertTrue(app.buttons["search.item.usage"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testSiteMenuSwitchesStationWithReceipt() {
        launchAndLogin(name: "站点 A", url: "https://a.example.invalid")
        defer { diagnostics("site-menu-switch-final") }
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        fillLogin(name: "站点 B", url: "https://b.example.invalid")
        openSiteMenu(title: "站点 B")
        for label in ["站点 A", "站点 B", "添加站点…", "站点与凭据"] {
            XCTAssertTrue(menuItem(label).waitForExistence(timeout: 5), app.debugDescription)
        }
        // The current site is checked; the host is read after the name.
        XCTAssertTrue(menuItem("站点 B").isSelected, app.debugDescription)
        XCTAssertFalse(menuItem("站点 A").isSelected)
        XCTAssertTrue(menuItem("站点 A").label.contains("a.example.invalid"), menuItem("站点 A").label)
        diagnostics("site-menu")
        menuItem("站点 A").tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(receipt.label, "已切换到 站点 A")
        diagnostics("site-switch-receipt")
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected)
        app.tabBars.buttons["账号"].tap()
        openSiteMenu(title: "账号")
        XCTAssertTrue(menuItem("站点 B").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(menuItem("站点 A").isSelected, app.debugDescription)
    }

    @MainActor func testSiteMenuOpensSitesSettingsAndAddSite() {
        launchAndLogin(name: "菜单站点", url: "https://menu.example.invalid")
        defer { diagnostics("site-menu-entries-final") }
        openSiteMenu(title: "菜单站点")
        let settings = menuItem("站点与凭据")
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        // Pushed onto 概览's own stack (10 §0.7-2).
        XCTAssertTrue(app.buttons["settings.add"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected)
        goBack()
        openSiteMenu(title: "菜单站点")
        let add = menuItem("添加站点…")
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription)
        add.tap()
        XCTAssertTrue(app.textFields["login.url"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// X05: a site without some capabilities still opens every tab; 管理访问令牌 follows admin.access_tokens (60 §3.3).
    @MainActor func testWithheldCapabilitiesStillOpenEveryTab() {
        launchAndLogin(name: "能力站点", url: "https://capabilities.example.invalid",
                       arguments: ["-ui-without-capabilities", "dashboard.home,admin.access_tokens"])
        defer { diagnostics("withheld-capabilities-final") }
        for title in ["账号", "用户", "监控", "概览"] {
            let tab = app.tabBars.buttons[title]
            tab.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(tab.isSelected, app.debugDescription)
            XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        }
        app.openSitesSettings()
        reveal(element("settings.current.web"))
        XCTAssertTrue(element("settings.current.sessions").exists, app.debugDescription)
        XCTAssertFalse(element("settings.current.tokens").exists, app.debugDescription)
    }

    @MainActor private func launchAndLogin(name: String, url: String, arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launch()
        fillLogin(name: name, url: url)
    }
    @MainActor private func launchNavigationSite() { launchAndLogin(name: "导航站点", url: "https://navigation.example.invalid") }
    @MainActor private func launchDirectorySite() { launchAndLogin(name: "目录站点", url: "https://directory.example.invalid") }
    @MainActor private func fillLogin(name: String, url: String) {
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(name, in: "login.name")
        enter(url, in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The navigation title is the site menu (`toolbarTitleMenu`, 10 §0.7-5); it shows as a button in the bar.
    @MainActor private func openSiteMenu(title: String) {
        let button = app.navigationBars[title].buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
    }
    /// System menu items carry no identifier; a site reads “name, host”. Rows elsewhere with the same text have one.
    @MainActor private func menuItem(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == '' AND (label == %@ OR label BEGINSWITH %@)", label, label + ",")).firstMatch
    }
    @MainActor private func assertLogsMode(_ title: String) {
        let mode = app.segmentedControls["logs.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(mode.buttons[title].isSelected, app.debugDescription)
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    /// Section headers read as their title only; the number beside it is decoration.
    @MainActor private func header(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15)))
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
