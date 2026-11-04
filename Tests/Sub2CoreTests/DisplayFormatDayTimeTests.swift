import Foundation
import Testing
@testable import Sub2Core

// S1-12: 10 §3.3 the alert detail's 触发 / 结束 times (DisplayFormat.dayTime).

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = at("2026-10-22T10:00:00+08:00")

@Test func dayTimeNamesTheServerDay() {
    #expect(DisplayFormat.dayTime(at("2026-10-22T09:29:00+08:00"), now: now, timeZone: shanghai) == "今天 09:29")
    // Within the minute it is still a time of day, never 刚刚.
    #expect(DisplayFormat.dayTime(at("2026-10-22T09:59:30+08:00"), now: now, timeZone: shanghai) == "今天 09:59")
    #expect(DisplayFormat.dayTime(at("2026-10-21T22:10:00+08:00"), now: now, timeZone: shanghai) == "昨天 22:10")
    #expect(DisplayFormat.dayTime(at("2026-10-20T09:29:00+08:00"), now: now, timeZone: shanghai) == "10月20日 09:29")
    #expect(DisplayFormat.dayTime(nil, now: now, timeZone: shanghai) == DisplayFormat.missing)
}

@Test func dayTimeFollowsTheServerZone() {
    // 01:30 in Shanghai is 17:30 the day before in UTC, where `now` is 02:00.
    let date = at("2026-10-22T01:30:00+08:00")
    #expect(DisplayFormat.dayTime(date, now: now, timeZone: shanghai) == "今天 01:30")
    #expect(DisplayFormat.dayTime(date, now: now, timeZone: utc) == "昨天 17:30")
}
