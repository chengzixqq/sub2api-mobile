import XCTest

final class RequestLogsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor func testRequestPaginationAndDistinctChargeCostDetails() {
        launchLogs()
        defer { diagnostics("request-log-pagination-and-billing") }
        let first = app.buttons["logs.request.101"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(first.label.contains("扣费 $0.3500"), first.label)
        XCTAssertTrue(first.label.contains("成本 $0.1200"), first.label)
        XCTAssertTrue(first.label.contains("1.2M"), first.label)
        let more = app.buttons["logs.more"]; reveal(more); more.tap()
        XCTAssertTrue(app.buttons["logs.request.102"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(more.exists, "Deferred totals must stop on has_more=false.")
        reveal(first, down: false); first.tap()
        let charge = element("logs.detail.charge"); reveal(charge)
        XCTAssertTrue(charge.label.contains("$0.3500"), charge.label)
        XCTAssertTrue(element("logs.detail.cost").label.contains("$0.1200"), app.debugDescription)
    }
    @MainActor func testErrorDetailAndUserFilterCanBeCleared() {
        launchLogs()
        defer { diagnostics("request-log-error-filter-and-detail") }
        let segmented = app.segmentedControls["logs.mode"]
        XCTAssertTrue(segmented.waitForExistence(timeout: 5), app.debugDescription)
        segmented.buttons["失败请求"].tap()
        let row = app.buttons["logs.error.201"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        XCTAssertTrue(element("logs.detail.message").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("logs.detail.message").label.contains("上游请求受限"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        segmented.buttons["上游错误"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["logs.filter"].tap()
        XCTAssertTrue(app.textFields["logs.filter.account"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.textFields["logs.filter.user"].exists)
        XCTAssertFalse(app.textFields["logs.filter.model"].exists)
        app.buttons["取消"].tap()
        segmented.buttons["请求记录"].tap()
        app.buttons["logs.filter"].tap()
        let user = app.textFields["logs.filter.user"]; reveal(user); user.tap(); user.typeText("999")
        app.buttons["logs.filter.apply"].tap()
        XCTAssertTrue(element("logs.empty").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["logs.filter"].tap()
        let clear = app.buttons["logs.filter.clear"]; reveal(clear); clear.tap()
        app.buttons["logs.filter.apply"].tap()
        XCTAssertTrue(app.buttons["logs.request.101"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func launchLogs() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launchQuietly()
        enter("日志验收", field: app.textFields["login.name"])
        enter("https://logs-ui.example.invalid", field: app.textFields["login.url"])
        enter("admin@example.invalid", field: app.textFields["login.email"])
        enter("fixture-password", field: app.secureTextFields["login.password"])
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.usage")
    }
    @MainActor private func enter(_ text: String, field: XCUIElement) { reveal(field); field.tap(); field.typeText(text) }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func reveal(_ element: XCUIElement, down: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let keyboard = app.keyboards.firstMatch
            let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
