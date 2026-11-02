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
        app.waitForLabel(element("analytics.moreCard.tile.userTrend"), containing: "第 1 · Nova 工作室")

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
        app.scrollUntilExists(element("analytics.tokenStats.footnote"), maxSwipes: 20)
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

    // MARK: 用户用量趋势与请求类型（40 §2.3，S4-17b）

    private enum UsageArgument {
        static let without = "-ui-without-capabilities"
        static let refreshChanges = "-ui-analytics-refresh-changes"
    }

    @MainActor private func userTrendRow(_ userID: Int) -> XCUIElement { element("analytics.userTrend.row.\(userID)") }
    @MainActor private func requestTypeRow(_ type: String) -> XCUIElement { element("analytics.reqType.row.\(type)") }
    @MainActor private var userTrendMetric: XCUIElement { app.segmentedControls["analytics.userTrend.metric"] }
    /// The navigation bar's filter sheet, then a group row.
    @MainActor private func filterByGroup(_ id: Int, file: StaticString = #filePath, line: UInt = #line) {
        app.navigationBars.buttons["analytics.filter.button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["筛选"].waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let row = element("analytics.filter.row.group.\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription, file: file, line: line)
    }

    @MainActor func testUserTrendSwitchesMetricReordersRowsAndOpensUser() {
        openMoreCard()
        let tile = element("analytics.moreCard.tile.userTrend")
        app.waitForLabel(tile, containing: "12.4M Tokens")
        app.waitForLabel(tile, containing: "第 1 · Nova 工作室")
        openTile("userTrend")
        assertBelowTopicBar(element("analytics.more.chart.userTrend"))
        app.waitForLabel(userTrendRow(21), containing: "第 1 名，Nova 工作室，12.4M Tokens")
        let note = element("analytics.userTrend.note")
        app.scrollUntilExists(note)
        app.waitForLabel(note, containing: "按 Tokens 取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。")
        // By Tokens Mira Labs is fifth and Pixel 工坊 sixth.
        app.waitForLabel(userTrendRow(24), containing: "第 5 名，Mira Labs")
        XCTAssertFalse(userTrendRow(25).exists, app.debugDescription)
        attachScreenshot("more-user-trend-tokens")

        app.scrollUntilExists(userTrendMetric, towardBottom: false)
        userTrendMetric.buttons["实际扣费"].tap()
        app.waitForLabel(userTrendRow(22), containing: "第 1 名，Atlas 科技，$412.80")
        app.waitForLabel(userTrendRow(21), containing: "第 2 名，Nova 工作室，$389.20")
        app.waitForLabel(userTrendRow(25), containing: "第 5 名，Pixel 工坊")
        XCTAssertFalse(userTrendRow(24).exists, app.debugDescription)
        app.waitForLabel(note, containing: "按实际扣费取前 12 位，这里显示前 5 位")
        attachScreenshot("more-user-trend-cost")

        let atlas = userTrendRow(22)
        app.scrollUntilExists(atlas, towardBottom: false)
        atlas.tap()
        XCTAssertTrue(element("user.detail").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUserTrendUnderFilterWithoutFilteredMetricOffersTokensOnly() {
        openMoreCard([UsageArgument.without, "dashboard.users_trend_filtered_metric"])
        openTile("userTrend")
        XCTAssertTrue(userTrendMetric.waitForExistence(timeout: 10), app.debugDescription)
        userTrendMetric.buttons["实际扣费"].tap()
        app.waitForLabel(userTrendRow(22), containing: "第 1 名，Atlas 科技，$412.80")

        // The site cannot rank a filtered range by cost: only Tokens, and the footnote says so.
        filterByGroup(1)
        XCTAssertTrue(userTrendMetric.pollGone(timeout: 5), app.debugDescription)
        app.waitForLabel(userTrendRow(21), containing: "第 1 名，Nova 工作室，12.4M Tokens")
        app.waitForLabel(element("analytics.userTrend.note"), containing: "按 Tokens 取前 12 位")
        attachScreenshot("more-user-trend-filtered")

        let chip = element("analytics.filter.chip")
        app.scrollUntilExists(chip, towardBottom: false)
        chip.tap()
        XCTAssertTrue(chip.pollGone(timeout: 5), app.debugDescription)
        selectTopic("usage")
        app.scrollUntilExists(userTrendMetric)
        XCTAssertTrue(userTrendMetric.buttons["实际扣费"].waitForExistence(timeout: 10), app.debugDescription)
        userTrendMetric.buttons["实际扣费"].tap()
        app.waitForLabel(userTrendRow(22), containing: "第 1 名，Atlas 科技，$412.80")
    }

    @MainActor func testRequestTypesShowFiveFixedRowsHollowZeroAndTile() {
        openMoreCard([Argument.opsDisabled])
        let tile = element("analytics.moreCard.tile.reqType")
        app.waitForLabel(tile, containing: "72%")
        app.waitForLabel(tile, containing: "流式占请求")
        openTile("reqType")
        assertBelowTopicBar(element("analytics.more.chart.reqType"))
        let rows = ["stream", "sync", "ws_v2", "cyber", "live"].map(requestTypeRow)
        app.scrollUntilExists(rows[4])
        app.waitForLabel(element("analytics.reqType.bar"), containing: "流式 72.1%，同步 23.7%，WS 3.4%，安全策略 0.9%")
        app.waitForLabel(rows[0], containing: "流式，13,120 次请求，占 72.1%")
        app.waitForLabel(rows[3], containing: "安全策略，162 次请求，占 0.9%")
        app.waitForLabel(rows[4], containing: "Live，0 次请求，占 0.0%")
        app.waitForValue(rows[4], equal: "没有请求")
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            XCTAssertLessThan(upper.frame.minY, lower.frame.minY, "\(upper) above \(lower)\n\(app.debugDescription)")
        }
        attachScreenshot("more-request-types")
    }

    @MainActor func testRequestTypesFallBackToPerTypeUsageStatsWithoutCapability() {
        openMoreCard([Argument.opsDisabled, UsageArgument.without, "dashboard.request_types"])
        // 9,800 of 12,000: the fallback's numbers, not the dashboard's.
        app.waitForLabel(element("analytics.moreCard.tile.reqType"), containing: "82%")
        openTile("reqType")
        let live = requestTypeRow("live")
        app.scrollUntilExists(live)
        app.waitForLabel(requestTypeRow("stream"), containing: "流式，9,800 次请求")
        app.waitForLabel(requestTypeRow("ws_v2"), containing: "WS，0 次请求")
        app.waitForValue(requestTypeRow("ws_v2"), equal: "没有请求")
        app.waitForLabel(live, containing: "Live，60 次请求")
        XCTAssertTrue(element("analytics.reqType.bar").exists, app.debugDescription)
    }

    @MainActor func testMoreChartsPullToRefreshRereadsLoadedCards() {
        openMoreCard([UsageArgument.refreshChanges])
        openAllCharts()
        selectTopic("usage")
        let nova = userTrendRow(21)
        app.scrollUntilExists(nova)
        app.waitForLabel(nova, containing: "12.4M")

        let caption = element("analytics.range.caption")
        app.scrollUntilExists(caption, towardBottom: false)
        app.pullToRefresh(from: caption)
        // The card scrolled away stays registered: the pull read it again (S4D2b-02 ⑤).
        selectTopic("usage")
        app.scrollUntilExists(nova)
        app.waitForLabel(nova, containing: "24.8M")
    }

    // MARK: 运行主题（40 §2.3、§2.5，S4-18）

    private enum OpsArgument {
        /// admin/me says ops monitoring is on, yet every ops chart answers 404 OPS_DISABLED (AnalyticsFixtures.opsGoneArgument).
        static let gone = "-ui-analytics-ops-gone"
        static let siteWide = "运行类图表不支持按这个模型筛选，这里显示全站"
    }

    /// 全部图表, then the 运行 capsule.
    @MainActor private func openOpsTopic(_ arguments: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        openMoreCard(arguments, file: file, line: line)
        openAllCharts(file: file, line: line)
        selectTopic("ops", file: file, line: line)
    }

    @MainActor func testOpsTopicRendersSwitchLatencyAndErrorTrend() {
        openOpsTopic()
        let highest = element("analytics.ops.switch.highest")
        app.scrollUntilExists(highest)
        app.waitForValue(highest, equal: "0.032")
        XCTAssertTrue(element("analytics.ops.switch.chart").exists, app.debugDescription)
        app.waitForLabel(element("analytics.ops.switch.footnote"), containing: "曲线每小时一点。请求因限流、过载或错误换到另一个账号，记一次切换。")
        attachScreenshot("more-ops-switch")

        let footnote = element("analytics.ops.latency.footnote")
        app.scrollUntilExists(footnote)
        app.waitForLabel(footnote, containing: "成功请求 18,204 次的总耗时分布")
        app.waitForLabel(element("analytics.ops.latency.column.2"), containing: "30%，5,461 次")
        let duration = element("analytics.ops.latency.row.duration")
        app.scrollUntilExists(duration)
        XCTAssertTrue(duration.poll(NSPredicate(format: "value CONTAINS %@", "P50 2.4s，P90 5.1s"), timeout: 10), app.debugDescription)
        XCTAssertTrue(element("analytics.ops.latency.row.ttft").poll(NSPredicate(format: "value CONTAINS %@", "P50 820ms"), timeout: 5),
                      app.debugDescription)
        attachScreenshot("more-ops-latency")

        let upstream = element("analytics.ops.errTrend.upstream")
        app.scrollUntilExists(upstream)
        app.waitForLabel(upstream, containing: "上游失败（含重试成功）：429 186 · 529 64 · 其他 53")
        app.waitForValue(element("analytics.ops.errTrend.errors"), equal: "397")
        app.waitForValue(element("analytics.ops.errTrend.rate"), equal: "1.7%")
        app.waitForValue(element("analytics.ops.errTrend.sla"), equal: "317")
        app.waitForLabel(element("analytics.ops.errTrend.legend"), containing: "SLA 错误 317，业务限制 80")
        XCTAssertTrue(element("analytics.ops.errTrend.chart").exists, app.debugDescription)
        app.waitForLabel(element("analytics.ops.errTrend.footnote"), containing: "后端每小时一桶，这里按天合计。")
        attachScreenshot("more-ops-error-trend")

        // 错误分布 and Token 请求统计 follow (S4-18b).
        app.scrollUntilExists(element("analytics.errDist.legend"))
        app.scrollUntilExists(element("analytics.tokenStats.footnote"))
        XCTAssertFalse(element("analytics.more.ops.off").exists, app.debugDescription)
    }

    /// 40 §2.5: a 404 OPS_DISABLED (the switch just turned off) swaps the whole topic for the notice.
    @MainActor func testOps404SwapsTheWholeTopicForTheNotice() {
        openMoreCard([OpsArgument.gone])
        // RPM / TPM on 统计分析 got the 404 first: six charts are left.
        app.waitForLabel(element("analytics.moreCard.count"), containing: "6 张")
        openAllCharts()
        app.waitForLabel(element("analytics.more.topic.ops"), containing: "运行，未开启")
        selectTopic("ops")
        let off = element("analytics.more.ops.off")
        XCTAssertTrue(off.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(off.staticTexts["运维监控未开启"].exists, app.debugDescription)
        for chart in ["analytics.more.chart.perf", "analytics.more.chart.switch", "analytics.ops.switch.chart", "analytics.ops.errTrend.upstream"] {
            XCTAssertFalse(element(chart).exists, "\(chart)\n\(app.debugDescription)")
        }
        attachScreenshot("more-ops-gone")
    }

    @MainActor func testOpsChartsSayTheyShowTheWholeSiteWithoutModelFilter() {
        openMoreCard([UsageArgument.without, "ops.dashboard_model_filter"])
        openAllCharts()
        app.navigationBars.buttons["analytics.filter.button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["筛选"].waitForExistence(timeout: 5), app.debugDescription)
        app.segmentedControls["analytics.filter.kind"].buttons["模型"].tap()
        let row = element("analytics.filter.row.model.claude-opus-4")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription)

        selectTopic("ops")
        for chart in ["perf", "switch", "latency", "errTrend"] {
            let note = element("analytics.ops.\(chart).notes.siteWide")
            app.scrollUntilExists(note)
            app.waitForLabel(note, containing: OpsArgument.siteWide)
        }
        // 近 7 天 starts within the 30 days the error logs keep.
        XCTAssertFalse(element("analytics.ops.errTrend.notes.retention").exists, app.debugDescription)
        app.waitForValue(element("analytics.ops.errTrend.errors"), equal: "397")
        attachScreenshot("more-ops-site-wide")
    }

    // MARK: 错误分布、Token 请求统计与运行类磁贴（40 §1.4、§2.3、§2.5，S4-18b）

    @MainActor private func tokenStatsRow(_ index: Int) -> XCUIElement { element("analytics.tokenStats.row.\(index)") }
    @MainActor private var tokenStatsOrder: XCUIElement { app.segmentedControls["analytics.tokenStats.order"] }
    /// The rows' labels start with these models, top first.
    @MainActor private func assertTokenStatsModels(_ models: [String], file: StaticString = #filePath, line: UInt = #line) {
        for (index, model) in models.enumerated() {
            XCTAssertTrue(tokenStatsRow(index).poll(NSPredicate(format: "label BEGINSWITH %@", model + "，"), timeout: 10),
                          "row \(index) should be \(model)\n\(app.debugDescription)", file: file, line: line)
        }
    }
    /// Scrolled to, then out from under the pinned bar, so a tap reaches it.
    @MainActor private func revealUnderTopicBar(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        app.scrollUntilExists(item, maxSwipes: 20, file: file, line: line)
        let bar = element("analytics.more.topicBar")
        for _ in 0..<4 where item.frame.minY < bar.frame.maxY {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
            item.waitUntilSettled()
        }
        XCTAssertGreaterThanOrEqual(item.frame.minY, bar.frame.maxY - 1, "\(item) under the bar\n\(app.debugDescription)", file: file, line: line)
    }
    /// The navigation bar's filter sheet, then a model row.
    @MainActor private func filterByModel(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        app.navigationBars.buttons["analytics.filter.button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["筛选"].waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        app.segmentedControls["analytics.filter.kind"].buttons["模型"].tap()
        let row = element("analytics.filter.row.model.\(name)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["筛选"].pollGone(timeout: 5), app.debugDescription, file: file, line: line)
    }
    /// 范围 Menu → 自定义… → 上月 → 应用; the menu can swallow a tap while the page redraws, so it is tried again.
    @MainActor private func applyLastMonth(file: StaticString = #filePath, line: UInt = #line) {
        let menu = element("analytics.range.menu"), shortcut = element("analytics.custom.preset.lastMonth")
        let item = app.buttons.matching(NSPredicate(format: "label == %@", "自定义…")).firstMatch
        for _ in 0..<3 where !shortcut.exists {
            menu.tap()
            if item.waitForExistence(timeout: 3) { item.tap() }
            _ = shortcut.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(shortcut.exists, app.debugDescription, file: file, line: line)
        shortcut.tap()
        XCTAssertTrue(shortcut.poll(NSPredicate(format: "isSelected == true"), timeout: 5), app.debugDescription, file: file, line: line)
        element("analytics.custom.apply").tap()
        XCTAssertTrue(app.navigationBars["自定义范围"].pollGone(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertTrue(menu.poll(NSPredicate(format: "value == %@", "上月"), timeout: 5), app.debugDescription, file: file, line: line)
    }
    /// U35 on the site's calendar (Asia/Shanghai): 上月 starts before the same moment 30 days ago, which early March and the 1st
    /// after a 30-day month do not.
    private static func lastMonthStartsBeyondRetention(now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        return calendar.date(byAdding: .month, value: -1, to: thisMonth)! < calendar.date(byAdding: .day, value: -30, to: now)!
    }

    @MainActor func testTokenStatsSortsLocallyAndPinsFilteredModel() {
        openOpsTopic()
        revealUnderTopicBar(tokenStatsOrder)
        XCTAssertTrue(element("analytics.more.chart.tokenSpeed").staticTexts["近 7 天 · 运维监控"].exists, app.debugDescription)
        assertTokenStatsModels(["claude-opus-4", "gpt-5", "deepseek-v3", "gemini-2.5-pro", "gpt-4.1-mini"])
        XCTAssertFalse(tokenStatsRow(5).exists, app.debugDescription)
        app.waitForLabel(tokenStatsRow(4), containing: "gpt-4.1-mini，输出每秒 86.4，首 Token 410ms，平均时长 2.4s")
        app.waitForLabel(element("analytics.tokenStats.footnote"), containing: "统计窗口与所选范围一致。")

        tokenStatsOrder.buttons["按速度"].tap()
        assertTokenStatsModels(["gpt-4.1-mini", "gemini-2.5-pro", "o4-mini"])
        tokenStatsOrder.buttons["按首 Token"].tap()
        assertTokenStatsModels(["gpt-4.1-mini", "o4-mini", "gemini-2.5-pro"])
        attachScreenshot("more-token-stats-first-token")

        // glm-4.6 is seventh by requests: its row follows the first five, lit.
        filterByModel("glm-4.6")
        selectTopic("ops")
        revealUnderTopicBar(tokenStatsOrder)
        tokenStatsOrder.buttons["按请求"].tap()
        assertTokenStatsModels(["claude-opus-4", "gpt-5", "deepseek-v3", "gemini-2.5-pro", "gpt-4.1-mini", "glm-4.6"])
        XCTAssertTrue(tokenStatsRow(5).poll(NSPredicate(format: "value == %@", "已筛选"), timeout: 5), app.debugDescription)
        XCTAssertFalse(tokenStatsRow(6).exists, app.debugDescription)
        attachScreenshot("more-token-stats-pinned")
    }

    @MainActor func testTokenStatsRollingWindowAndGroupWithoutModels() {
        openOpsTopic([UsageArgument.without, "ops.token_stats_custom_range"])
        app.scrollUntilExists(element("analytics.more.chart.tokenSpeed").staticTexts["近 15 天 · 运维监控"], maxSwipes: 20)
        let footnote = element("analytics.tokenStats.footnote")
        app.scrollUntilExists(footnote)
        app.waitForLabel(footnote, containing: "统计窗口近 15 天，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。")
        assertTokenStatsModels(["claude-opus-4"])

        // 测试组 (inactive) has no usage: neither chart has a row.
        filterByGroup(6)
        selectTopic("ops")
        let empty = element("analytics.tokenStats.empty")
        app.scrollUntilExists(empty, maxSwipes: 20)
        app.waitForLabel(empty, containing: "这个分组在窗口内没有模型用量")
        XCTAssertTrue(footnote.poll(NSPredicate(format: "label ENDSWITH %@", "只列「测试组」用到的模型。"), timeout: 10), app.debugDescription)
        XCTAssertFalse(tokenStatsRow(0).exists, app.debugDescription)
        let noErrors = element("analytics.errDist.empty")
        app.scrollUntilExists(noErrors, towardBottom: false)
        app.waitForLabel(noErrors, containing: "这个范围内没有错误")
        attachScreenshot("more-token-stats-group-empty")
    }

    @MainActor func testErrorDistributionRowsLegendAndRetentionHint() {
        openOpsTopic()
        let legend = element("analytics.errDist.legend")
        app.scrollUntilExists(legend, maxSwipes: 20)
        app.waitForLabel(legend, containing: "429 限流，其他错误（含 504、529），业务限制（不计 SLA）")
        let rows = [429, 502, 403, 529, 500, 504].map { element("analytics.errDist.row.\($0)") }
        app.waitForLabel(rows[0], containing: "状态码 429，160 条，占 40%，SLA 148，业务限制 12")
        app.waitForLabel(rows[2], containing: "状态码 403，68 条，占 17%，SLA 0，业务限制 68")
        app.waitForLabel(rows[5], containing: "状态码 504，18 条，占 5%")
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            XCTAssertLessThan(upper.frame.minY, lower.frame.minY, "\(upper) above \(lower)\n\(app.debugDescription)")
        }
        // 近 7 天 is within the 30 days the error logs keep.
        let retention = element("analytics.ops.errDist.notes.retention")
        XCTAssertFalse(retention.exists, app.debugDescription)
        attachScreenshot("more-error-distribution")

        applyLastMonth()
        selectTopic("ops")
        if Self.lastMonthStartsBeyondRetention() {
            app.scrollUntilExists(retention, maxSwipes: 20)
            app.waitForLabel(retention, containing: "运维日志默认只保留 30 天，更早的时段可能没有记录")
        } else {
            app.scrollUntilExists(legend, maxSwipes: 20)
            XCTAssertFalse(retention.exists, app.debugDescription)
        }
        app.waitForLabel(rows[0], containing: "状态码 429，160 条")
    }

    @MainActor func testMoreCardOpsTilesShowValuesAndSiteWideTag() {
        openMoreCard([UsageArgument.without, "ops.dashboard_model_filter"])
        let errors = element("analytics.moreCard.tile.errTrend"), latency = element("analytics.moreCard.tile.latency")
        app.waitForLabel(errors, containing: "错误趋势，1.7%，错误率 · SLA")
        app.waitForLabel(latency, containing: "请求时长分布，2.4s，P50 总耗时")
        attachScreenshot("more-card-ops-tiles")

        // A model filter the ops charts cannot send: both tiles say they show the whole site; Token 使用趋势 does not.
        filterByModel("claude-opus-4")
        // The card's grid builds its second row only on screen.
        app.scrollUntilExists(app.analyticsElement("analytics.moreCard.foot"))
        app.waitForLabel(errors, containing: "1.7%，全站 错误率 · SLA")
        app.waitForLabel(latency, containing: "2.4s，全站 P50 总耗时")
        let tokens = element("analytics.moreCard.tile.tokens")
        app.waitForLabel(tokens, containing: "Tokens")
        XCTAssertFalse(tokens.label.contains("全站"), app.debugDescription)
        attachScreenshot("more-card-ops-tiles-site-wide")
    }
}
