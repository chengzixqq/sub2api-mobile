import Foundation
import Testing
@testable import Sub2Core

private func moment(_ raw: String) throws -> Date {
    guard let date = ServerTime.parseTimestamp(raw) else { throw CocoaError(.formatting) }
    return date
}
private let shanghaiZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utcZone = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private let newYorkZone = ServerTimeZone(identifier: "America/New_York", utcOffset: nil)!

@Test func monthDayClockWritesMonthDayAndTimeWithinTheYear() throws {
    let now = try moment("2026-10-27T04:00:00Z")
    #expect(DisplayFormat.monthDayClock(try moment("2026-10-16T01:20:00Z"), timeZone: shanghaiZone, now: now) == "10/16 09:20")
    #expect(DisplayFormat.monthDayClock(try moment("2026-09-05T00:07:00Z"), timeZone: shanghaiZone, now: now) == "09/05 08:07")
    #expect(DisplayFormat.monthDayClock(try moment("2026-01-02T03:04:00Z"), timeZone: utcZone, now: now) == "01/02 03:04")
    #expect(DisplayFormat.monthDayClock(nil, timeZone: shanghaiZone, now: now) == DisplayFormat.missing)
}

@Test func monthDayClockFollowsTheServerZoneNotThePhone() throws {
    let date = try moment("2026-10-15T16:30:00Z"), now = try moment("2026-10-27T04:00:00Z")
    #expect(DisplayFormat.monthDayClock(date, timeZone: shanghaiZone, now: now) == "10/16 00:30")
    #expect(DisplayFormat.monthDayClock(date, timeZone: utcZone, now: now) == "10/15 16:30")
    #expect(DisplayFormat.monthDayClock(date, timeZone: newYorkZone, now: now) == "10/15 12:30")
}

@Test func monthDayClockAddsTheYearOutsideNowsYear() throws {
    let now = try moment("2026-10-27T04:00:00Z")
    #expect(DisplayFormat.monthDayClock(try moment("2025-12-31T15:59:00Z"), timeZone: shanghaiZone, now: now) == "2025/12/31 23:59")
    // The year is the server's: 16:00 UTC on 31 December is already 2026 in Shanghai.
    #expect(DisplayFormat.monthDayClock(try moment("2025-12-31T16:00:00Z"), timeZone: shanghaiZone, now: now) == "01/01 00:00")
    #expect(DisplayFormat.monthDayClock(try moment("2025-12-31T16:00:00Z"), timeZone: utcZone, now: now) == "2025/12/31 16:00")
    #expect(DisplayFormat.monthDayClock(try moment("2027-01-03T00:00:00Z"), timeZone: utcZone, now: now) == "2027/01/03 00:00")
}
