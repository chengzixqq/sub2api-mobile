import XCTest

/// S1-18, stage 1's completion mark (10 §1.7): the overview's six fixtures (全部正常, 运维关闭, 账号状态失败, 每小时超时, 平静,
/// 平静 + 限流), the per-endpoint fallback of a site from before dashboard.home, and the monitor's (默认, 运维关闭, 渠道监控关闭,
/// 没有告警) each render their sections. One table entry and one test per fixture, with screenshots kept in the result bundle.
/// Values from LiveOpsFixtures (来源 LiveOpsFixtureIDs; the UI tests cannot import the App, so change both together); how the
/// pages behave is HomeUITests', HomeCalmUITests', MonitorUITests' and AlertDetailUITests'.
final class StageOneFixtureUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    /// One check; a screen's steps run top to bottom and scroll down to each element they name.
    private enum Step: Sendable {
        /// There; its label, value or a child reads `text` when given (waited for: the first read may still be on its way).
        case shows(String, String? = nil)
        /// There once loaded (enabled), reading neither `text` nor the skeleton's 正在加载.
        case showsWithout(String, String)
        /// Not there at this point of the page.
        case lacks(String)
        /// The navigation bar's subtitle reads it.
        case subtitle(String)
        /// The monitor's segment of this title carries no count.
        case segmentWithoutCount(String)
    }
    /// The overview, or the monitor's segment `segment`.
    private struct Screen: Sendable {
        let name: String
        var segment: String?
        let steps: [Step]
    }
    private struct Fixture: Sendable {
        let arguments: [String]
        let screens: [Screen]
    }

    // MARK: Fixtures

    /// LiveOpsFixtures' default home (stats, rates, fiveMinuteOverview), as HomeUITests reads it.
    private static let tickers: [Step] = [("actualCost", "$1,284.50"), ("requests", "18.2K"), ("errorRate", "0.8%"), ("profit", "$772.42"),
                                          ("rpm", "46"), ("tpm", "240K")].map { Step.shows("home.ticker." + $0.0, $0.1) }
    private static let loadedTickers: [Step] = ["actualCost", "requests", "errorRate", "profit", "rpm", "tpm"].map {
        Step.showsWithout("home.ticker." + $0, "正在加载")
    }
    private static let health = "94，良好"
    private static let missing = "无数据"
    /// LiveOpsFixtures.homeLegacyWithheldCapabilities.
    private static let legacyCapabilities = "dashboard.home,dashboard.rates,dashboard.account_cost,accounts.status_summary,ops.alert_event_counts"

    private static let homeAllOK = Fixture(arguments: [], screens: [Screen(name: "home-all-ok", steps: join([.shows("home.regular")], tickers, [
        .lacks("home.calm.flag"), .lacks("home.unreachable"), .lacks("ops.disabled.inline"), .shows("home.attention", "6 项"),
        .shows("home.attention.alert-41"), .lacks("home.attention.retry-availability"), .shows("home.attention.groups"),
        .shows("home.today.chart"), .lacks("home.today.hourly.failed"), .shows("home.today.accountCost", "$512.08"),
        .shows("home.run.health", health), .shows("home.run.channels", "可用 3")
    ]))])
    private static let homeOpsDisabled = Fixture(arguments: ["-ui-ops-disabled"], screens: [Screen(name: "home-ops-disabled", steps: [
        .shows("home.regular"), .shows("home.ticker.actualCost", "$1,284.50"), .showsWithout("home.ticker.errorRate", "%"),
        .shows("ops.disabled.inline", "运维监控未开启"), .lacks("home.unreachable"),
        .shows("home.attention.account-7"), .lacks("home.attention.alert-41"),
        .shows("home.today.chart"), .shows("home.today.successRate", missing), .shows("home.run.health", missing + "，运维监控未开启")
    ])])
    private static let homeAvailabilityError = Fixture(arguments: ["-ui-home-availability-error"], screens: [
        Screen(name: "home-availability-error", steps: join([.shows("home.regular")], tickers, [
            .subtitle("部分数据未更新"), .shows("home.attention", "3 项"), .shows("home.attention.retry-availability", "账号状态读取失败"),
            .lacks("home.attention.account-7"), .lacks("home.attention.limited"), .shows("home.today.chart"), .shows("home.run.health", health)
        ]))
    ])
    private static let homeHourlyTimeout = Fixture(arguments: ["-ui-home-hourly-timeout"], screens: [
        Screen(name: "home-hourly-timeout", steps: join([.shows("home.regular")], tickers, [
            .shows("home.today.hourly.failed", "每小时数据加载失败"), .lacks("home.today.chart"), .shows("home.today.accountCost", "$512.08"),
            .shows("home.run.health", health)
        ]))
    ])
    private static let homeCalm = Fixture(arguments: ["-ui-home-calm"], screens: [Screen(name: "home-calm", steps: join([
        .shows("home.calm"), .shows("home.calm.flag", "全部正常"), .lacks("home.regular"), .lacks("home.attention")], loadedTickers, [
        .lacks("home.calm.recovering"), .shows("home.today.chart"), .shows("home.calm.ranking.1", "Claude-官方-01"), .shows("home.today.more"),
        .shows("home.calm.channels", "8 个渠道"), .lacks("home.run.health")
    ]))])
    private static let homeCalmLimited = Fixture(arguments: ["-ui-home-calm-limited"], screens: [Screen(name: "home-calm-limited", steps: join([
        .shows("home.calm"), .shows("home.calm.flag", "无需处理"), .lacks("home.regular")], loadedTickers, [
        .shows("home.calm.recovering.header", "2 个"), .shows("home.calm.recovering", "受限 2 个账号"), .shows("home.today.chart"),
        .shows("home.calm.ranking.2"), .lacks("home.calm.ranking.12"), .shows("home.calm.channels")
    ]))])
    /// S1-07: home answers a non-JSON 404 on a site without the newer capabilities, so every block takes its own endpoint.
    private static let homeLegacy = Fixture(arguments: ["-ui-home-legacy", "-ui-without-capabilities", legacyCapabilities], screens: [
        Screen(name: "home-legacy-fallback", steps: [
            .shows("home.regular"), .shows("home.ticker.actualCost", "$1,284.50"), .shows("home.ticker.requests", "18.2K"),
            .shows("home.ticker.rpm", "46"), .shows("home.ticker.tpm", "240K"), .showsWithout("home.ticker.errorRate", "正在加载"),
            .showsWithout("home.ticker.profit", "正在加载"), .lacks("home.unreachable"), .lacks("home.calm.flag"),
            .shows("home.attention.alert-41"), .shows("home.today.chart"), .shows("home.run.health", health), .shows("home.run.channels")
        ])
    ])
    private static let monitorDefault = Fixture(arguments: [], screens: [
        Screen(name: "monitor-default-overview", segment: "概况", steps: [
            .shows("monitor.run.health", health), .shows("monitor.run.trend"), .shows("monitor.server.header")]),
        Screen(name: "monitor-default-channels", segment: "渠道", steps: [
            .shows("monitor.channels.count.available", "3"), .shows("monitor.channels.header"), .shows("monitor.channels.row.8")]),
        Screen(name: "monitor-default-alerts", segment: "告警", steps: [
            .shows("monitor.alerts.firing", "2 条"), .shows("monitor.alerts.row.41"), .shows("monitor.alerts.ended")])
    ])
    /// The channel monitor has its own switch: 渠道 stays while ops monitoring is off.
    private static let monitorOpsDisabled = Fixture(arguments: ["-ui-ops-disabled"], screens: [
        Screen(name: "monitor-ops-disabled-overview", segment: "概况", steps: [
            .shows("ops.disabled.empty", "运维监控未开启"), .lacks("monitor.run.health")]),
        Screen(name: "monitor-ops-disabled-channels", segment: "渠道", steps: [
            .shows("monitor.channels.count.available", "3"), .lacks("ops.disabled.empty")]),
        Screen(name: "monitor-ops-disabled-alerts", segment: "告警", steps: [
            .shows("ops.disabled.empty", "运维监控未开启"), .lacks("monitor.alerts.firing")])
    ])
    private static let monitorChannelsOff = Fixture(arguments: ["-ui-channel-monitor-off"], screens: [
        Screen(name: "monitor-channels-off-overview", segment: "概况", steps: [.shows("monitor.run.health", health)]),
        Screen(name: "monitor-channels-off", segment: "渠道", steps: [
            .shows("monitor.channels.disabled", "渠道监控未开启"), .lacks("monitor.channels.count.available"), .lacks("monitor.channels.row.8")])
    ])
    /// The calm fixture fires nothing.
    private static let monitorNoFiring = Fixture(arguments: ["-ui-home-calm"], screens: [
        Screen(name: "monitor-no-firing-overview", segment: "概况", steps: [.shows("monitor.run.alerts", "没有告警"), .segmentWithoutCount("告警")]),
        Screen(name: "monitor-no-firing-alerts", segment: "告警", steps: [
            .shows("monitor.alerts.firing.empty", "没有告警"), .shows("monitor.alerts.ended")])
    ])

    private static func join(_ parts: [Step]...) -> [Step] { parts.flatMap { $0 } }

    // MARK: Tests

    @MainActor func testHomeAllOKRenders() { assertRenders(Self.homeAllOK) }
    @MainActor func testHomeOpsDisabledRenders() { assertRenders(Self.homeOpsDisabled) }
    @MainActor func testHomeAvailabilityErrorRenders() { assertRenders(Self.homeAvailabilityError) }
    @MainActor func testHomeHourlyTimeoutRenders() { assertRenders(Self.homeHourlyTimeout) }
    @MainActor func testHomeCalmRenders() { assertRenders(Self.homeCalm) }
    @MainActor func testHomeCalmLimitedRenders() { assertRenders(Self.homeCalmLimited) }
    @MainActor func testHomeLegacyFallbackRenders() { assertRenders(Self.homeLegacy) }
    @MainActor func testMonitorDefaultRendersEverySegment() { assertRenders(Self.monitorDefault) }
    @MainActor func testMonitorOpsDisabledRendersEverySegment() { assertRenders(Self.monitorOpsDisabled) }
    @MainActor func testMonitorChannelMonitorOffRendersChannels() { assertRenders(Self.monitorChannelsOff) }
    @MainActor func testMonitorNoFiringRendersEmptyAlerts() { assertRenders(Self.monitorNoFiring) }

    // MARK: Helpers

    @MainActor private func assertRenders(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        launchAndLogin(fixture.arguments, file: file, line: line)
        for screen in fixture.screens {
            if let segment = screen.segment { openSegment(segment, file: file, line: line) }
            for (index, step) in screen.steps.enumerated() {
                check(step, on: screen.name, patience: index == 0 ? 10 : 2, file: file, line: line)
                if index == 0 { attachScreenshot(screen.name) }
            }
            attachScreenshot(screen.name + "-end")
        }
    }

    @MainActor private func check(_ step: Step, on screen: String, patience: TimeInterval, file: StaticString, line: UInt) {
        switch step {
        case .shows(let id, let text):
            let item = shown(id, patience: patience, file: file, line: line)
            guard let text else { return }
            XCTAssertTrue(reads(item, text), "\(screen): \(id) 没有「\(text)」\n\(item.debugDescription)", file: file, line: line)
        case .showsWithout(let id, let text):
            let item = shown(id, patience: patience, file: file, line: line)
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: item)
            XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 10), .completed, "\(screen): \(id) 仍在加载", file: file, line: line)
            let spoken = item.label + " " + ((item.value as? String) ?? "")
            XCTAssertFalse(spoken.contains(text) || spoken.contains("正在加载"), "\(screen): \(id)「\(spoken)」", file: file, line: line)
        case .lacks(let id):
            XCTAssertTrue(element(id).waitForNonExistence(timeout: 5), "\(screen): \(id) 不应出现\n\(app.debugDescription)", file: file, line: line)
        case .subtitle(let text):
            let subtitle = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            XCTAssertTrue(subtitle.waitForExistence(timeout: 10), "\(screen): 副标题没有「\(text)」\n\(app.debugDescription)", file: file, line: line)
        case .segmentWithoutCount(let title):
            XCTAssertEqual(app.segmentedControls["monitor.segment"].segment(title).label, title, screen, file: file, line: line)
        }
    }

    @MainActor private func launchAndLogin(_ arguments: [String], file: StaticString, line: UInt) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for (value, identifier) in [("阶段一站点", "login.name"), ("https://stage-one.example.invalid", "login.url"), ("admin@example.com", "login.email"),
                                    ("fixture-password", "login.password")] {
            let field = element(identifier); reveal(field, file: file, line: line); field.tap(); field.typeText(value)
        }
        let submit = app.buttons["login.submit"]; reveal(submit, file: file, line: line); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }
    /// The monitor tab's segment `title`, scrolled back up to the picker first.
    @MainActor private func openSegment(_ title: String, file: StaticString, line: UInt) {
        let tab = app.tabBars.buttons["监控"], segments = app.segmentedControls["monitor.segment"]
        if !tab.isSelected {
            tab.tap()
            XCTAssertTrue(segments.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        }
        reveal(segments, towardBottom: false, file: file, line: line)
        let segment = segments.segment(title)
        segment.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: segment)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    /// Waits `patience` seconds for a read to put the element on the page, then scrolls down to it.
    @MainActor private func shown(_ id: String, patience: TimeInterval, file: StaticString, line: UInt) -> XCUIElement {
        let item = element(id)
        _ = item.waitForExistence(timeout: patience)
        reveal(item, file: file, line: line)
        return item
    }
    /// A child's label first (a container reads nothing itself), then the element's own label or value once a read filled it.
    @MainActor private func reads(_ item: XCUIElement, _ text: String) -> Bool {
        if item.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists { return true }
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text), object: item)
        return XCTWaiter().wait(for: [shown], timeout: 10) == .completed
    }
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString, line: UInt) {
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
    @MainActor private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
