import XCTest

/// 40 §1.4 更多图表卡 and §2 更多图表 on the billing fixtures (S4-17). S4-17b / S4-18 / S4-18b add their tests at the end of the class
/// and call the helpers below; launching, finding elements and waiting are AnalyticsUITestSupport's. The fixture's endpoints are
/// fixed (AnalyticsFixtures.inboundEndpoints / upstreamEndpoints: change both together).
final class AnalyticsMoreUITests: XCTestCase {
    @MainActor var app: XCUIApplication!

    private enum Argument {
        static let opsDisabled = "-ui-ops-disabled"
    }

    // MARK: Helpers (S4-17b / S4-18 / S4-18b use these)

    /// Signs in, opens 统计分析 from the search directory (近 7 天) and scrolls to 更多图表卡's foot.
    @MainActor func openMoreCard(_ arguments: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.signInForAnalytics(name: "图表站点", url: "https://charts.example.invalid", arguments: arguments, file: file, line: line)
        app.openAnalyticsFromSearch(file: file, line: line)
        app.scrollUntilExists(app.analyticsElement("analytics.moreCard.foot"), file: file, line: line)
    }
    /// A tile of the card (already on screen), into 更多图表.
    @MainActor func openTile(_ chart: String, file: StaticString = #filePath, line: UInt = #line) {
        let tile = app.analyticsElement("analytics.moreCard.tile.\(chart)")
        app.scrollUntilExists(tile, file: file, line: line)
        tile.tap()
        XCTAssertTrue(app.navigationBars["更多图表"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }
    /// 全部图表: 更多图表 at its top.
    @MainActor func openAllCharts(file: StaticString = #filePath, line: UInt = #line) {
        let foot = app.analyticsElement("analytics.moreCard.foot")
        app.scrollUntilExists(foot, file: file, line: line)
        foot.tap()
        XCTAssertTrue(app.navigationBars["更多图表"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }
    /// A topic's capsule on the pinned bar.
    @MainActor func selectTopic(_ topic: String, file: StaticString = #filePath, line: UInt = #line) {
        let chip = app.analyticsElement("analytics.more.topic.\(topic)")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        chip.tap()
    }
    /// The element sits below the pinned bar, on screen.
    @MainActor func assertBelowTopicBar(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        element.waitUntilSettled()
        let bar = app.analyticsElement("analytics.more.topicBar").frame
        XCTAssertGreaterThanOrEqual(element.frame.minY, bar.maxY - 1, "\(element) under the bar\n\(app.debugDescription)", file: file, line: line)
        XCTAssertLessThan(element.frame.minY, app.frame.maxY - 120, "\(element) off screen\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor func assertTopicSelected(_ topic: String, file: StaticString = #filePath, line: UInt = #line) {
        let chip = app.analyticsElement("analytics.more.topic.\(topic)")
        XCTAssertTrue(chip.poll(NSPredicate(format: "isSelected == true"), timeout: 5), "\(topic) should be lit\n\(app.debugDescription)",
                      file: file, line: line)
    }

    // MARK: Private helpers

    @MainActor private func element(_ identifier: String) -> XCUIElement { app.analyticsElement(identifier) }
    @MainActor private func endpointRow(_ index: Int) -> XCUIElement { element("analytics.endpoints.row.\(index)") }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: 更多图表卡与落点（40 §1.4、§2.1）

    @MainActor func testTileOpensMoreChartsScrolledToHighlightedChart() {
        openMoreCard()
        app.waitForLabel(element("analytics.moreCard.count"), containing: "12 张")
        app.waitForLabel(element("analytics.moreCard.foot"), containing: "全部图表")
        app.waitForLabel(element("analytics.moreCard.foot"), containing: "计费 2 · 用量 4 · 运行 6")
        for chart in ["tokens", "userTrend", "errTrend", "latency"] {
            XCTAssertTrue(element("analytics.moreCard.tile.\(chart)").exists, "\(chart)\n\(app.debugDescription)")
        }
        XCTAssertFalse(element("analytics.moreCard.tile.endpoints").exists, app.debugDescription)
        let tokens = element("analytics.moreCard.tile.tokens")
        app.waitForLabel(tokens, containing: "Tokens")
        app.waitForLabel(tokens, containing: "缓存读占 54%")
        app.waitForLabel(element("analytics.moreCard.tile.userTrend"), containing: "稍后提供")

        openTile("tokens")
        assertBelowTopicBar(element("analytics.more.chart.tokens"))
        assertTopicSelected("usage")
        attachScreenshot("more-landed-tokens")
    }

    @MainActor func testTopicChipsJumpAndFollowScrolling() {
        openMoreCard()
        openAllCharts()
        assertTopicSelected("billing")
        XCTAssertTrue(element("analytics.range.caption").waitForExistence(timeout: 5), app.debugDescription)
        app.waitForLabel(element("analytics.more.topic.ops"), containing: "运行")

        selectTopic("ops")
        assertBelowTopicBar(element("analytics.more.topicHeader.ops"))
        assertTopicSelected("ops")
        app.waitForLabel(element("analytics.more.topicHeader.ops"), containing: "需开启运维监控")

        selectTopic("billing")
        assertBelowTopicBar(element("analytics.more.topicHeader.billing"))
        assertTopicSelected("billing")

        selectTopic("usage")
        assertBelowTopicBar(element("analytics.more.topicHeader.usage"))
        assertTopicSelected("usage")

        // Scrolled to the end, the last topic lights up.
        app.scrollUntilExists(element("analytics.more.chart.tokenSpeed.placeholder"), maxSwipes: 20)
        for _ in 0..<2 { app.swipeUp() }
        assertTopicSelected("ops")
        selectTopic("billing")
        assertTopicSelected("billing")
    }

    // MARK: Token 使用趋势与端点分布（40 §2.3）

    @MainActor func testTokenLegendShowsOnlyOneKind() {
        openMoreCard()
        openTile("tokens")
        let footnote = element("analytics.tokens.footnote")
        let total = NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label ENDSWITH %@", "合计 ", "· 缓存读占 ", "· 点图例只看一项")
        XCTAssertTrue(footnote.poll(total, timeout: 10), app.debugDescription)
        app.waitForLabel(footnote, containing: "合计 642.5M · 缓存读占 54%")
        attachScreenshot("more-tokens-chart")

        let cacheRead = element("analytics.tokens.legend.cacheRead")
        app.scrollUntilExists(cacheRead)
        cacheRead.tap()
        XCTAssertTrue(cacheRead.poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
        app.waitForLabel(footnote, containing: "只看缓存读，再点一次图例恢复全部")
        attachScreenshot("more-tokens-cache-read")

        cacheRead.tap()
        XCTAssertTrue(cacheRead.poll(NSPredicate(format: "isSelected == false"), timeout: 5), app.debugDescription)
        XCTAssertTrue(footnote.poll(total, timeout: 5), app.debugDescription)
    }

    @MainActor func testEndpointSegmentsSwitchInboundAndUpstream() {
        openMoreCard()
        openAllCharts()
        selectTopic("usage")
        app.scrollUntilExists(endpointRow(2))
        app.waitForLabel(endpointRow(0), containing: "/v1/messages")
        app.waitForLabel(endpointRow(0), containing: "10,920")
        app.waitForLabel(endpointRow(0), containing: "60.0%")
        app.waitForLabel(endpointRow(0), containing: "实际 $612.40")
        app.waitForLabel(endpointRow(2), containing: "/v1/responses")
        app.waitForLabel(endpointRow(2), containing: "12.0%")

        app.segmentedControls["analytics.endpoints.side"].buttons["上游端点"].tap()
        app.waitForLabel(endpointRow(0), containing: "70.0%")
        app.waitForLabel(endpointRow(1), containing: "/v1/chat/completions")
        XCTAssertTrue(endpointRow(2).pollGone(timeout: 5), app.debugDescription)

        app.segmentedControls["analytics.endpoints.side"].buttons["入站端点"].tap()
        app.waitForLabel(endpointRow(2), containing: "/v1/responses")
    }

    // MARK: 运维关闭（40 §1.4、§2.5）

    @MainActor func testOpsDisabledCardAndRunTopic() {
        openMoreCard([Argument.opsDisabled])
        app.waitForLabel(element("analytics.moreCard.count"), containing: "6 张")
        app.waitForLabel(element("analytics.moreCard.foot"), containing: "计费 2 · 用量 4 · 运行 未开启")
        for chart in ["tokens", "userTrend", "endpoints", "reqType"] {
            XCTAssertTrue(element("analytics.moreCard.tile.\(chart)").exists, "\(chart)\n\(app.debugDescription)")
        }
        XCTAssertFalse(element("analytics.moreCard.tile.errTrend").exists, app.debugDescription)
        XCTAssertFalse(element("analytics.moreCard.tile.latency").exists, app.debugDescription)
        app.waitForLabel(element("analytics.moreCard.tile.endpoints"), containing: "60%")
        app.waitForLabel(element("analytics.moreCard.tile.endpoints"), containing: "/v1/messages 占请求")

        openTile("endpoints")
        assertBelowTopicBar(element("analytics.more.chart.endpoints"))
        app.waitForLabel(element("analytics.more.topic.ops"), containing: "运行，未开启")

        selectTopic("ops")
        let off = element("analytics.more.ops.off")
        XCTAssertTrue(off.waitForExistence(timeout: 10), app.debugDescription)
        // OpsDisabledNotice inside the card (its own identifier folds into the card's).
        XCTAssertTrue(off.staticTexts["运维监控未开启"].exists, app.debugDescription)
        XCTAssertTrue(off.descendants(matching: .any)["ops.disabled.enable"].firstMatch.exists, app.debugDescription)
        XCTAssertFalse(element("analytics.more.chart.perf").exists, app.debugDescription)
        assertTopicSelected("ops")
    }

    // MARK: 范围 Menu（40 §2.1）

    @MainActor func testRangeMenuReloadsChartsAndKeepsTheRangeOnReturn() {
        openMoreCard()
        openAllCharts()
        let caption = element("analytics.range.caption")
        app.waitForLabel(caption, containing: "按天")

        element("analytics.range.menu").tap()
        let today = app.buttons["今天"].firstMatch
        let toggle = app.switches["今天"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5) || toggle.exists, app.debugDescription)
        (today.exists ? today : toggle).tap()
        app.waitForLabel(caption, containing: "按小时")
        app.waitForLabel(element("analytics.range.menu"), containing: "时间范围")
        XCTAssertTrue(element("analytics.range.menu").poll(NSPredicate(format: "value == %@", "今天"), timeout: 5), app.debugDescription)

        selectTopic("usage")
        let footnote = element("analytics.tokens.footnote")
        XCTAssertTrue(footnote.poll(NSPredicate(format: "label BEGINSWITH %@", "合计 "), timeout: 10), app.debugDescription)

        goBack()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.rangeSegment("今天").poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription)
    }
}
