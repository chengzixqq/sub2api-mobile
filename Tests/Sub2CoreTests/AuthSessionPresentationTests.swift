import Foundation
import Testing
@testable import Sub2Core

// 60 §5.3–§5.5: how one signed-in device reads on 登录设备, and the page's fixed wording.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func item(name: String? = nil, client: String? = nil, agent: String? = nil, ip: String? = nil, created: String? = nil,
                  seen: String? = nil, expires: String? = nil, current: Bool = false) -> AuthSessionItem {
    AuthSessionItem(id: "0a1b", deviceName: name, clientType: client, userAgent: agent, ip: ip, createdAt: created, lastSeenAt: seen,
                    expiresAt: expires, current: current)
}

@Test func iconNameFollowsClientType() {
    #expect(item(client: "ios").iconName == "iphone")
    #expect(item(client: "android").iconName == "smartphone")
    #expect(item(client: "web").iconName == "globe")
    #expect(item(client: " IOS ").iconName == "iphone")
    #expect(item(client: "").iconName == "questionmark.circle")
    #expect(item(client: nil).iconName == "questionmark.circle")
    #expect(item(client: "desktop").iconName == "questionmark.circle")
}

@Test func displayTitlePrefersDeviceNameThenUserAgent() {
    #expect(item(name: "演示 iPhone", agent: "Sub2Mobile-iOS/1.0").displayTitle == "演示 iPhone")
    #expect(item(name: "  ", agent: "Sub2Mobile-iOS/1.0").displayTitle == "Sub2 Mobile（iOS）")
    #expect(item(name: "", agent: "Mozilla/5.0 (Macintosh)").displayTitle == "Mozilla/5.0 (Macintosh)")
    #expect(item(name: "", agent: "  ").displayTitle == "未知设备")
    #expect(item(name: nil, agent: nil).displayTitle == "未知设备")
}

@Test func displayTitleCutsUserAgentAtFortyCharacters() {
    let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    #expect(item(agent: safari).displayTitle == String(safari.prefix(40)))
    #expect(item(agent: safari).displayTitle.count == 40)
    let exact = String(repeating: "a", count: 40)
    #expect(item(agent: exact).displayTitle == exact)
    let chinese = String(repeating: "设", count: 45)
    #expect(item(agent: chinese).displayTitle == String(repeating: "设", count: 40))
    #expect(!item(agent: safari).displayTitle.hasSuffix("…"))
}

@Test func activityLineJoinsIPAndRelativeTime() {
    let now = instant("2026-10-17T04:00:00Z")
    let seen = { (seconds: TimeInterval) in ServerTime.utcTimestamp(now.addingTimeInterval(-seconds)) }
    #expect(item(ip: "203.0.113.24", seen: seen(180)).activityLine(now: now, timeZone: shanghai) == "203.0.113.24 · 3 分钟前活跃")
    #expect(item(ip: "203.0.113.24", seen: seen(20)).activityLine(now: now, timeZone: shanghai) == "203.0.113.24 · 刚刚活跃")
    // Shanghai 12:00 now, 08:00 then: a time of day ends with a digit, so 活跃 is set apart.
    #expect(item(ip: "203.0.113.24", seen: "2026-10-17T00:00:00Z").activityLine(now: now, timeZone: shanghai) == "203.0.113.24 · 今天 08:00 活跃")
    #expect(item(ip: "", seen: seen(180)).activityLine(now: now, timeZone: shanghai) == "3 分钟前活跃")
    #expect(item(ip: nil, seen: seen(180)).activityLine(now: now, timeZone: shanghai) == "3 分钟前活跃")
}

@Test func activityLineTreatsMissingAndZeroTimesAsAbsent() {
    let now = instant("2026-10-17T04:00:00Z")
    #expect(item(ip: "203.0.113.24", seen: nil).activityLine(now: now, timeZone: shanghai) == "203.0.113.24")
    #expect(item(ip: "203.0.113.24", seen: "yesterday").activityLine(now: now, timeZone: shanghai) == "203.0.113.24")
    // The backend writes Go's zero time when Redis has no such field.
    #expect(item(ip: "203.0.113.24", seen: "0001-01-01T00:00:00Z").activityLine(now: now, timeZone: shanghai) == "203.0.113.24")
    #expect(item(ip: "", seen: "0001-01-01T00:00:00Z").activityLine(now: now, timeZone: shanghai) == "—")
    #expect(item().activityLine(now: now, timeZone: shanghai) == "—")
}

@Test func activityLineDayBoundaryFollowsServerZone() {
    let now = instant("2026-10-17T01:00:00Z")
    let session = item(seen: "2026-10-16T17:30:00Z")
    #expect(session.activityLine(now: now, timeZone: shanghai) == "今天 01:30 活跃")
    #expect(session.activityLine(now: now, timeZone: utc) == "昨天 17:30 活跃")
}

@Test func lifetimeLineUsesServerTimeZone() {
    let session = item(created: "2026-10-17T01:41:00Z", expires: "2026-11-16T01:41:00Z")
    #expect(session.lifetimeLine(timeZone: shanghai) == "登录于 10/17 09:41 · 11/16 到期")
    #expect(session.lifetimeLine(timeZone: utc) == "登录于 10/17 01:41 · 11/16 到期")
    let offset = item(created: "2026-10-17T09:41:00.123456+08:00", expires: "2026-11-16T09:41:00.5+08:00")
    #expect(offset.lifetimeLine(timeZone: shanghai) == "登录于 10/17 09:41 · 11/16 到期")
    let september = item(created: "2026-09-05T01:00:00Z", expires: "2026-10-05T01:00:00Z")
    #expect(september.lifetimeLine(timeZone: shanghai) == "登录于 09/05 09:00 · 10/05 到期")
}

@Test func lifetimeLineOmitsMissingParts() {
    #expect(item(expires: "2026-11-16T01:41:00Z").lifetimeLine(timeZone: shanghai) == "11/16 到期")
    #expect(item(created: "2026-10-17T01:41:00Z").lifetimeLine(timeZone: shanghai) == "登录于 10/17 09:41")
    #expect(item(created: "2026-10-17T01:41:00Z", expires: "0001-01-01T00:00:00Z").lifetimeLine(timeZone: shanghai) == "登录于 10/17 09:41")
    #expect(item(created: "", expires: "nonsense").lifetimeLine(timeZone: shanghai) == "—")
    #expect(item().lifetimeLine(timeZone: shanghai) == "—")
}

@Test func otherDeviceCountIgnoresThisDevice() {
    let this = item(current: true), other = item()
    #expect(AuthSessionItem.otherDeviceCount(in: [this, other, other]) == 2)
    #expect(AuthSessionItem.otherDeviceCount(in: [this]) == 0)
    // A pre-deployment session has no sid, so the list has no current entry at all.
    #expect(AuthSessionItem.otherDeviceCount(in: [other, other, other]) == 3)
    #expect(AuthSessionItem.otherDeviceCount(in: []) == 0)
}

@Test func otherDeviceIDsAreTheRowsRevokeAllEnds() {
    let this = AuthSessionItem(id: "a1", current: true), web = AuthSessionItem(id: "b2"), legacy = AuthSessionItem(id: "c3")
    #expect(AuthSessionItem.otherDeviceIDs(in: [this, web, legacy]) == ["b2", "c3"])
    #expect(AuthSessionItem.otherDeviceIDs(in: [this]).isEmpty)
    // Without a current entry this device's pre-deployment session ends with the others.
    #expect(AuthSessionItem.otherDeviceIDs(in: [web, legacy]) == ["b2", "c3"])
}

@Test func failedReloadKeepsTheOlderListWithItsTime() {
    #expect(AuthSessionItem.refreshFailedText == "刷新失败 · 重试")
    #expect(AuthSessionItem.updatedLine(instant("2026-10-17T01:41:00Z"), timeZone: shanghai) == "更新于 09:41")
    #expect(AuthSessionItem.updatedLine(instant("2026-10-17T01:41:00Z"), timeZone: utc) == "更新于 01:41")
    #expect(AuthSessionItem.updatedLine(nil, timeZone: shanghai) == nil)
}

@Test func alreadyGoneOnlyForSessionNotFound() {
    #expect(AuthSessionItem.isAlreadyGone(APIError.server(status: 404, reason: "SESSION_NOT_FOUND")))
    #expect(!AuthSessionItem.isAlreadyGone(APIError.server(status: 404, reason: "ACCESS_TOKEN_NOT_FOUND")))
    #expect(!AuthSessionItem.isAlreadyGone(APIError.server(status: 404, envelope: nil)))
    #expect(!AuthSessionItem.isAlreadyGone(APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")))
    #expect(!AuthSessionItem.isAlreadyGone(CancellationError()))
    #expect(!AuthSessionItem.isAlreadyGone(URLError(.timedOut)))
}

@Test func copyMatchesSpec() {
    #expect(AuthSessionItem.revokeTitle("未知设备") == "让「未知设备」下线？")
    #expect(AuthSessionItem.revokeMessage == "该设备需要重新登录。")
    #expect(AuthSessionItem.revokedReceipt("未知设备") == "已下线「未知设备」")
    #expect(AuthSessionItem.revokeOthersTitle(count: 2) == "让其他 2 台设备下线？")
    #expect(AuthSessionItem.revokeOthersMessage == "它们需要重新登录，本机不受影响。")
    #expect(AuthSessionItem.revokeOthersButtonTitle == "让其他所有设备下线")
    #expect(AuthSessionItem.noOtherDevicesText == "没有其他设备登录")
    #expect(AuthSessionItem.footnote == "部署新版本前登录的设备，下一次自动续期后才会出现在这里。")
    #expect(AuthSessionItem.currentBadgeText == "本机")
    #expect(AuthSessionItem.currentDeviceNoteTitle + "。" + AuthSessionItem.currentDeviceNoteMessage == "这是本机。要退出请用设置里的“退出并清除凭据”。")
}

@Test func memberwiseInitMatchesDecoding() throws {
    let json = #"{"id":"0a1b","device_name":"演示 iPhone","client_type":"ios","user_agent":"Sub2Mobile-iOS/1.0","ip":"203.0.113.24","#
        + #""created_at":"2026-10-17T01:41:00Z","last_seen_at":"2026-10-17T03:57:00Z","expires_at":"2026-11-16T01:41:00Z","current":true}"#
    let decoded = try JSONDecoder().decode(AuthSessionItem.self, from: Data(json.utf8))
    #expect(decoded == AuthSessionItem(id: "0a1b", deviceName: "演示 iPhone", clientType: "ios", userAgent: "Sub2Mobile-iOS/1.0",
                                       ip: "203.0.113.24", createdAt: "2026-10-17T01:41:00Z", lastSeenAt: "2026-10-17T03:57:00Z",
                                       expiresAt: "2026-11-16T01:41:00Z", current: true))
    let bare = try JSONDecoder().decode(AuthSessionItem.self, from: Data(#"{"id":"ff00"}"#.utf8))
    #expect(bare == AuthSessionItem(id: "ff00"))
    #expect(!AuthSessionItem(id: "ff00").current)
}
