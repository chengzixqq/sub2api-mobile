import XCTest

/// XCTest's own waits (XCTNSPredicateExpectation, `waitForExistence`, `waitForNonExistence`) look first about a second after
/// they start and then once a second, even when the state is already there (S3-16, from the result bundle's activity log). A
/// receipt is up for 4.2 seconds (R17): three of them between a receipt and its 撤销 used about 3 of those seconds, and on a
/// loaded Mac the tap found the receipt gone. These look at once and then every 0.2 s. Only where time counts like that: polled
/// everywhere, the next step came while a card was still expanding and `isHittable` failed on its buttons.
extension XCUIElement {
    /// The element as it is now, or nil. `exists` first, as a snapshot of a missing element retries for about 2 seconds; one
    /// leaving between the two (a receipt on its timer) only makes the snapshot throw, where reading `label` or `frame` from
    /// the element would fail the test (S3-13).
    @MainActor var shownSnapshot: (any XCUIElementSnapshot)? { exists ? try? snapshot() : nil }

    /// True once the element is there and, given a predicate on its attributes (`label`, `value`, `isEnabled`), satisfies it.
    @MainActor func poll(_ predicate: NSPredicate? = nil, timeout: TimeInterval) -> Bool {
        poll(timeout: timeout) { shownSnapshot.map { predicate?.evaluate(with: $0) ?? true } ?? false }
    }
    /// True once the element is gone.
    @MainActor func pollGone(timeout: TimeInterval) -> Bool { poll(timeout: timeout) { !exists } }

    @MainActor private func poll(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }
}
