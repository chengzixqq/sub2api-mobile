import XCTest

extension XCUIElement {
    /// S1-13: a segment of `monitor.segment` by its title; a segment with something to look at carries its count (10 §4.1:
    /// “告警 2”), so the label is the title alone or the title, a space and the count.
    @MainActor func segment(_ title: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + " ")).firstMatch
    }
}
