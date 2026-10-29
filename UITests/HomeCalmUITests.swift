import XCTest

/// 10 §2 the overview's calm layout over LiveOpsFixtures' calm variants (S1-11). Its own class beside HomeUITests, which is near
/// the 800-line limit; the regular layout's tests stay there.
final class HomeCalmUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// LiveOpsFixtures' calm variants (来源 LiveOpsFixtureIDs, LiveOpsFixtures.ranking and LiveOpsFixtures.channels; the UI tests
    /// cannot import the App, so change both together): 9 schedulable accounts, or 7 with #3 and #12 recovering; 按账号 #1 #2 #4 #3,
    /// or #1 #2 with #12 at $0.00 left out; 8 channels.
    private enum Expected {
        static let calm = "-ui-home-calm"
        static let calmLimited = "-ui-home-calm-limited"
        static let calmThenError = "-ui-home-calm-then-error"
        static let withoutRanking = ["-ui-without-capabilities", "dashboard.accounts_ranking"]
        static let kinds = ["actualCost", "requests", "errorRate", "profit", "rpm", "tpm"]
        static let ranking = [1, 2, 4, 3]
        static let firstRow = ["Claude-官方-01", "$409.38", "Anthropic · 4,418 次请求"]
        static let channels = "8 个渠道"
        static let channelLine = "可用 7 · 未知 1"
    }

    // MARK: Helpers

    @MainActor private func launchAndLogin(arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        for (value, identifier) in [("平静站点", "login.name"), ("https://calm.example.invalid", "login.url"), ("admin@example.com", "login.email"),
                                    ("fixture-password", "login.password")] {
            let field = element(identifier); reveal(field); field.tap(); field.typeText(value)
        }
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func rankingRow(_ id: Int) -> XCUIElement { element("home.calm.ranking.\(id)") }
    /// The calm layout once home's first read chose it.
    @MainActor @discardableResult
    private func calmFlag(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let flag = element("home.calm.flag")
        XCTAssertTrue(flag.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(element("home.regular").waitForNonExistence(timeout: 5), app.debugDescription, file: file, line: line)
        return flag
    }
    /// 待处理's title once a read filled it: “N 项” is its value.
    @MainActor private func loadedAttention(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let header = element("home.attention")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value ENDSWITH %@", " 项"), object: header)
        XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        return header
    }
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
    }
    @MainActor private func assertAbove(_ upper: XCUIElement, _ lower: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard upper.exists, lower.exists else { return }
        XCTAssertLessThanOrEqual(upper.frame.maxY, lower.frame.minY + 1, "\(upper.identifier) \(upper.frame) · \(lower.identifier) \(lower.frame)",
                                 file: file, line: line)
    }
    @MainActor private func assertSelected(tab title: String, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: app.tabBars.buttons[title])
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }

    // MARK: Tests

    /// 10 §2.4: the flag over the six cells, the hourly line, 按账号's top four in the server's order and 渠道; no 待处理, 运行 or
    /// 自动恢复中.
    @MainActor func testCalmLayoutShowsFlagTopFourRankingAndNoRunSection() {
        launchAndLogin(arguments: [Expected.calm])
        defer { diagnostics("home-calm-final") }
        let flag = calmFlag()
        XCTAssertTrue(flag.label.contains("全部正常") && flag.label.contains("9 个账号可调度"), flag.label)
        XCTAssertFalse(flag.label.contains("✓"), flag.label)
        for kind in Expected.kinds { XCTAssertTrue(element("home.ticker." + kind).exists, kind) }
        diagnostics("home-calm")
        let header = element("home.calm.hourly")
        reveal(header)
        XCTAssertEqual(header.label, "每小时实际扣费")
        XCTAssertEqual(header.value as? String, "00:00 起")
        reveal(element("home.today.chart"))
        var previous: XCUIElement?
        for id in Expected.ranking {
            let row = rankingRow(id)
            reveal(row)
            if let previous { assertAbove(previous, row) }
            previous = row
        }
        let more = element("home.today.more")
        reveal(more)
        if let previous { assertAbove(previous, more) }
        let channels = element("home.calm.channels")
        reveal(channels)
        XCTAssertEqual(channels.label, Expected.channels)
        XCTAssertEqual(channels.value as? String, Expected.channelLine)
        diagnostics("home-calm-bottom")
        for id in ["home.regular", "home.attention", "home.run.header", "home.run.health", "home.run.channels", "home.calm.recovering"] {
            XCTAssertFalse(element(id).exists, id)
        }
        let first = rankingRow(1)
        reveal(first, towardBottom: false)
        for part in Expected.firstRow { XCTAssertTrue(first.label.contains(part), first.label) }
    }

    /// 10 §2.1: a row opens the account on 概览's stack; back again the calm layout and its ranking are still there.
    @MainActor func testCalmRankingRowPushesAccountDetail() {
        launchAndLogin(arguments: [Expected.calm])
        defer { diagnostics("home-calm-ranking-open-final") }
        calmFlag()
        let first = rankingRow(1)
        reveal(first)
        first.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("sheet.close").exists, app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("home.calm.flag").exists || element("home.calm").exists, app.debugDescription)
    }

    /// 10 §2.2, §2.4: accounts that recover by themselves keep the calm layout: “无需处理”, then 自动恢复中 with the regular 受限 row,
    /// which switches to the 账号 tab; 按账号 leaves out the account at $0.00.
    @MainActor func testCalmLimitedShowsRecoveringRowAndSelectsAccountsTab() {
        launchAndLogin(arguments: [Expected.calmLimited])
        defer { diagnostics("home-calm-limited-final") }
        let flag = calmFlag()
        XCTAssertTrue(flag.label.contains("无需处理") && flag.label.contains("7 个账号可调度"), flag.label)
        let header = element("home.calm.recovering.header")
        reveal(header)
        XCTAssertEqual(header.label, "自动恢复中")
        XCTAssertEqual(header.value as? String, "2 个")
        let recovering = element("home.calm.recovering")
        reveal(recovering)
        for part in ["受限 2 个账号", "最早 ", "Claude-官方-03、MiniMax-01"] { XCTAssertTrue(recovering.label.contains(part), recovering.label) }
        diagnostics("home-calm-limited")
        // The rows below the fold load as the list scrolls to them.
        reveal(rankingRow(1))
        let second = rankingRow(2)
        reveal(second)
        let more = element("home.today.more")
        reveal(more)
        assertAbove(second, more)
        XCTAssertFalse(rankingRow(12).exists, app.debugDescription)
        reveal(recovering, towardBottom: false)
        recovering.tap()
        assertSelected(tab: "账号")
    }

    /// 10 §2.1: a read past the cache finds an error account, so the whole screen goes back to the regular layout with its row.
    /// ··· 刷新 reads past the cache like a pull, without the gesture.
    @MainActor func testCalmSwitchesToRegularAfterRefreshFindsErrorAccount() {
        launchAndLogin(arguments: [Expected.calmThenError])
        defer { diagnostics("home-calm-then-error-final") }
        calmFlag()
        let byIdentifier = element("home.more")
        let more = byIdentifier.waitForExistence(timeout: 5) ? byIdentifier : app.navigationBars.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        more.tap()
        let refresh = app.buttons["刷新"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        refresh.tap()
        let errorRow = element("home.attention.account-7")
        XCTAssertTrue(errorRow.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("home.regular").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("home.calm.flag").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(loadedAttention().value as? String, "1 项")
        XCTAssertTrue(errorRow.label.contains("OpenAI-备用-A"), errorRow.label)
    }

    /// 10 §0.2: without dashboard.accounts_ranking 按账号 is not there; 更多统计 moves under the chart and 渠道 stays.
    @MainActor func testCalmHidesRankingWithoutCapabilityButKeepsMoreStatsAndChannels() {
        launchAndLogin(arguments: [Expected.calm] + Expected.withoutRanking)
        defer { diagnostics("home-calm-without-ranking-final") }
        calmFlag()
        let more = element("home.today.more")
        reveal(more)
        let channels = element("home.calm.channels")
        reveal(channels)
        assertAbove(more, channels)
        XCTAssertEqual(channels.label, Expected.channels)
        XCTAssertFalse(element("home.calm.ranking").exists || rankingRow(1).exists, app.debugDescription)
    }

    /// 10 §2.2 condition 4, X34: money records waiting for a check keep the regular layout, those of an earlier login of this
    /// address too (S3-07's fixture; S1-18 covers the compensation variants).
    @MainActor func testPendingMoneyRecordsKeepRegularLayout() {
        for (arguments, count) in [(["-ui-pending-money"], 2), (["-ui-pending-old-site"], 3)] {
            launchAndLogin(arguments: [Expected.calm] + arguments)
            XCTAssertEqual(loadedAttention().value as? String, "\(count) 项", arguments.joined())
            XCTAssertTrue(element("home.regular").exists, app.debugDescription)
            XCTAssertFalse(element("home.calm.flag").exists, app.debugDescription)
            diagnostics("home-calm-pending" + arguments.joined())
            app.terminate()
        }
    }

    /// 10 §2.1: the 渠道 row switches to 监控 · 渠道 (the stage-0 placeholder segment until S1-15).
    @MainActor func testCalmChannelsRowSelectsMonitorChannels() {
        launchAndLogin(arguments: [Expected.calm])
        defer { diagnostics("home-calm-channels-final") }
        calmFlag()
        let channels = element("home.calm.channels")
        reveal(channels)
        channels.tap()
        assertSelected(tab: "监控")
        let segment = app.segmentedControls["monitor.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(segment.buttons["渠道"].isSelected, app.debugDescription)
    }
}
