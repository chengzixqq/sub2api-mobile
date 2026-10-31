import XCTest

/// S0-14: 管理 and 设置 are no longer tabs. Tests reach those pages through the search tab's directory (60 §1);
/// later items reuse these helpers instead of tapping tabs by name.
extension XCUIApplication {
    /// `Tab(role: .search)` is a separate button beside the tab bar; depending on the system it may sit outside `tabBars`.
    @MainActor func openSearchTab(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tabBars.buttons["概览"].waitForExistence(timeout: 10), debugDescription, file: file, line: line)
        let inBar = tabBars.buttons["搜索"]
        let button = inBar.exists ? inBar : buttons["搜索"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), debugDescription, file: file, line: line)
        button.tap()
        dismissSearchKeyboard()
    }

    /// Opens a directory row by its `search.item.*` identifier, from the directory itself even when this session pushed a
    /// page on the search tab before.
    @MainActor func openSearchItem(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        openSearchTab(file: file, line: line)
        let item = buttons[identifier]
        var backs = 0
        while !item.waitForExistence(timeout: 2), backs < 4 {
            let back = navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap(); backs += 1
        }
        revealAboveTabBar(item, file: file, line: line)
        item.tap()
    }

    /// The directory's “站点与凭据”. Waits for the add button rather than the title, which S0-15 changes (D27).
    @MainActor func openSitesSettings(file: StaticString = #filePath, line: UInt = #line) {
        openSearchItem("search.item.sites", file: file, line: line)
        XCTAssertTrue(buttons["settings.add"].waitForExistence(timeout: 10), debugDescription, file: file, line: line)
    }

    /// A search tab that activates its field on selection brings up the keyboard; the directory is what the tests need.
    @MainActor private func dismissSearchKeyboard() {
        guard keyboards.firstMatch.waitForExistence(timeout: 1) else { return }
        for label in ["取消", "Cancel", "关闭", "Close"] where buttons[label].firstMatch.exists {
            buttons[label].firstMatch.tap()
            return
        }
    }

    /// Scrolls the directory until the row sits between the navigation bar and the floating tab bar, which covers the last
    /// rows while they still report themselves hittable. A list left scrolled down has unloaded its first rows.
    @MainActor private func revealAboveTabBar(_ item: XCUIElement, file: StaticString, line: UInt) {
        for _ in 0..<3 where !item.exists { drag(from: 0.35, to: 0.8) }
        XCTAssertTrue(item.waitForExistence(timeout: 5), debugDescription, file: file, line: line)
        for _ in 0..<6 {
            let top = navigationBars.firstMatch.exists ? navigationBars.firstMatch.frame.maxY : frame.minY + 100
            let bottom = tabBars.firstMatch.exists ? tabBars.firstMatch.frame.minY - 8 : frame.maxY - 100
            if item.isHittable && item.frame.minY >= top && item.frame.maxY <= bottom { return }
            if item.frame.minY < top { drag(from: 0.4, to: 0.65) } else { drag(from: 0.7, to: 0.45) }
        }
        XCTAssertTrue(item.isHittable, debugDescription, file: file, line: line)
    }

    @MainActor private func drag(from start: CGFloat, to end: CGFloat) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)))
    }

    /// S3-02: drags a list a bounded number of times until the element exists and sits between the navigation bar and the
    /// floating tab bar; reaching the last rows of a paged list loads the next page on the way.
    @MainActor @discardableResult
    func scrollUntilExists(_ element: XCUIElement, towardBottom: Bool = true, maxSwipes: Int = 12,
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable && isBetweenBars(element) { element.waitUntilSettled(); return true }
            if towardBottom { drag(from: 0.72, to: 0.38) } else { drag(from: 0.38, to: 0.72) }
        }
        let found = element.exists && element.isHittable
        XCTAssertTrue(found, "\(element) not reached\n\(debugDescription)", file: file, line: line)
        return found
    }
    /// Pull to refresh from a row: dragged down to 85% of the screen, past the always-shown search field.
    @MainActor func pullToRefresh(from element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    }
    @MainActor private func isBetweenBars(_ element: XCUIElement) -> Bool {
        let top = navigationBars.firstMatch.exists ? navigationBars.firstMatch.frame.maxY : frame.minY
        let bottom = tabBars.firstMatch.exists ? tabBars.firstMatch.frame.minY : frame.maxY
        return element.frame.minY >= top && element.frame.maxY <= bottom
    }
}

extension XCUIElement {
    /// A scroll drag leaves the list decelerating, and a tap then only stops the scroll (S0-19: the switch and reorder
    /// taps that “did not change value”). Returns once two frame reads 0.15 s apart agree, at most after `timeout`.
    @MainActor func waitUntilSettled(timeout: TimeInterval = 2) {
        var previous = frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let current = frame
            if current == previous { return }
            previous = current
        }
    }
}
