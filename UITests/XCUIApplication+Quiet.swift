import XCTest

/// Every UI test launches the app through `launchQuietly()`, not `launch()`.
/// With Xcode 27.2 the app under test mirrors XCTest's automation os_log (every element query, a few dozen lines each) to its
/// standard output, and xcodebuild keeps that output for the whole run: about 20 MB per test, several GB per simulator in a
/// full run, enough to exhaust the Mac's memory. `OS_ACTIVITY_DT_MODE=NO` stops the mirroring (measured on
/// AlertDetailUITests: 209 MB → 10 KB of app output, same results). The app's own `os.Logger` output is unaffected in Console.
extension XCUIApplication {
    @MainActor func launchQuietly() {
        launchEnvironment["OS_ACTIVITY_DT_MODE"] = "NO"
        launch()
    }
}
