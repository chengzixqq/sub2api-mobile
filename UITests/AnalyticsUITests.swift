import XCTest

final class AnalyticsUITests: XCTestCase {
    @MainActor func testAnalyticsScopeAndDecimalSummary() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        func reveal(_ element: XCUIElement, down: Bool = true) {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                let frame = app.frame
                let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
                let keyboard = app.keyboards.firstMatch
                let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
                let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
                let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
                (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
            }
            XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
        }
        func fill(_ id: String, _ text: String) {
            let field = app.descendants(matching: .any)[id].firstMatch
            reveal(field); field.tap(); field.typeText(text)
        }
        fill("login.name", "统计测试")
        fill("login.url", "https://analysis.example.invalid")
        fill("login.email", "admin@example.com")
        fill("login.password", "fixture-password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        app.openSearchItem("search.item.analytics")
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 5))
        app.buttons["analytics.filters"].tap()
        XCTAssertTrue(app.navigationBars["统计筛选"].waitForExistence(timeout: 5))
        app.textFields["账号 ID"].tap(); app.textFields["账号 ID"].typeText("42")
        app.buttons["analytics.filters.apply"].tap()
        XCTAssertTrue(app.staticTexts["账号 #42"].waitForExistence(timeout: 5))
        let difference = app.descendants(matching: .any)["analytics.difference"].firstMatch
        reveal(difference)
        XCTAssertTrue(difference.exists, app.debugDescription)
        XCTAssertTrue(difference.label.contains("$6.67"), difference.label)
        let chart = app.descendants(matching: .any)["analytics.chart"].firstMatch
        reveal(chart)
        XCTAssertTrue(chart.exists, app.debugDescription)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "analytics-single-bucket-chart"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
