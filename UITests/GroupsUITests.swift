import XCTest

final class GroupsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testCreateEditStatusAndDeleteGroup() {
        launchAndOpenGroups()
        defer { diagnostics("group-lifecycle-final") }
        app.buttons["groups.create"].tap()
        set("移动分组", field: "group-editor.name", towardBottom: false)
        set("iPhone 管理", field: "group-editor.description")
        set("1.25", field: "group-editor.rate")
        set("90", field: "group-editor.rpm")
        confirmEditor()
        XCTAssertTrue(app.buttons["group.12"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["group.12"].tap()
        reveal(app.buttons["group.edit"])
        app.buttons["group.edit"].tap()
        set("移动分组更新", field: "group-editor.name", towardBottom: false)
        set("仅修改描述与名称", field: "group-editor.description")
        confirmEditor()
        // An Any query by the new title also matches the editor TextField's
        // value while the sheet is dismissing. Wait for the destination bar.
        XCTAssertTrue(app.navigationBars["移动分组更新"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(app.buttons["group.status"])
        app.buttons["group.status"].tap()
        confirmDialog()
        let statusResult = element("group.result")
        reveal(statusResult)
        XCTAssertTrue(statusResult.label.contains("状态已更新"), app.debugDescription)
        XCTAssertTrue(app.buttons["group.status"].label.contains("启用"), app.debugDescription)
        diagnostics("group-edit-and-status-success")
        reveal(app.buttons["group.delete"])
        app.buttons["group.delete"].tap()
        confirmDialog()
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["group.12"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["group.10"].exists)
    }

    @MainActor func testGroupValidationAndStatisticsNavigation() {
        launchAndOpenGroups()
        defer { diagnostics("group-validation-navigation-final") }
        app.buttons["groups.create"].tap()
        reveal(app.buttons["group-editor.prepare"])
        app.buttons["group-editor.prepare"].tap()
        reveal(element("group-editor.result"))
        XCTAssertTrue(element("group-editor.result").label.contains("名称"), app.debugDescription)
        set("验证分组", field: "group-editor.name", towardBottom: false)
        set("0", field: "group-editor.rate")
        reveal(app.buttons["group-editor.prepare"])
        app.buttons["group-editor.prepare"].tap()
        reveal(element("group-editor.result"))
        XCTAssertTrue(element("group-editor.result").label.contains("倍率"), app.debugDescription)
        app.buttons["group-editor.close"].tap()
        app.buttons["group.10"].tap()
        reveal(app.buttons["group.analytics"])
        app.buttons["group.analytics"].tap()
        XCTAssertTrue(app.navigationBars["统计分析"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func launchAndOpenGroups() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launchQuietly()
        set("分组管理验收", field: "login.name", towardBottom: false)
        set("https://groups-ui.example.invalid", field: "login.url")
        set("admin@example.com", field: "login.email")
        set("fixture-password", field: "login.password")
        reveal(app.buttons["login.submit"]); app.buttons["login.submit"].tap()
        app.openSearchItem("search.item.groups")
        XCTAssertTrue(app.buttons["group.10"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func confirmEditor() {
        reveal(app.buttons["group-editor.prepare"]); app.buttons["group-editor.prepare"].tap()
        confirmDialog()
    }
    @MainActor private func confirmDialog() {
        let button = app.buttons["确认发送"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription); button.tap()
    }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func set(_ value: String, field id: String, towardBottom: Bool = true) {
        let field = element(id); reveal(field, towardBottom: towardBottom); field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            XCTAssertTrue((field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue, app.debugDescription)
        }
        field.typeText(value)
    }
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<12 {
            if visibleFrame(item), item.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 100, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let height = max(40, bottom - top)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        guard visibleFrame(item) else {
            XCTFail("Expected a visible, nonempty element frame.\n\(app.debugDescription)"); return
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    @MainActor private func visibleFrame(_ item: XCUIElement) -> Bool {
        guard item.exists else { return false }
        let frame = item.frame
        return !frame.isEmpty && !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite && frame.intersects(app.frame)
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
