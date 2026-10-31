import Foundation
import Testing
@testable import Sub2Core

// C-30 (X31): the log row's “首字/耗时” (40 §0.5, §6.3).

@Test func firstTokenAndDurationJoinsListDurations() {
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: 1_200, durationMs: 3_200) == "1.2s/3.2s")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: nil, durationMs: 3_200) == "—/3.2s")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: 1_200, durationMs: nil) == "1.2s/—")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: nil, durationMs: nil) == DisplayFormat.missing)
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: 600, durationMs: 181_600) == "0.6s/182s")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: 0, durationMs: 99_960) == "0.0s/100s")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: -5, durationMs: 3_200) == "—/3.2s")
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: -5, durationMs: -1) == DisplayFormat.missing)
    #expect(DisplayFormat.firstTokenAndDuration(firstTokenMs: 42_100, durationMs: 1_234_000) == "42.1s/1,234s")
}
