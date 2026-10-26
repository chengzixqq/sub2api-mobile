import Foundation
import Testing
@testable import Sub2Core

// 60 §6.3–§6.5: how one access token reads on 管理访问令牌, the revocation prompt and the page's fixed wording.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func token(name: String? = "监控脚本", prefix: String? = "sat_3f9a", last4: String? = "c71e", scope: String? = "write",
                   expires: String? = nil, used: String? = nil, ip: String? = nil, current: Bool = false) -> AdminAccessToken {
    AdminAccessToken(id: 7, name: name, prefix: prefix, last4: last4, scope: scope, expiresAt: expires, lastUsedAt: used, lastUsedIP: ip,
                     createdAt: "2026-10-01T00:00:00Z", current: current)
}

@Test func maskedTextJoinsPrefixAndLast4() {
    #expect(token().maskedText == "sat_3f9a…c71e")
    #expect(token(prefix: nil).maskedText == "sat_…c71e")
    #expect(token(prefix: " ").maskedText == "sat_…c71e")
    #expect(token(last4: nil).maskedText == "sat_3f9a…")
    #expect(token(last4: "").maskedText == "sat_3f9a…")
}

@Test func scopeBadgeFollowsReadOnlyRule() {
    #expect(token(scope: "read").scopeTitle == "只读"); #expect(token(scope: "read").scopeTone == .neutral)
    #expect(token(scope: "write").scopeTitle == "读写"); #expect(token(scope: "write").scopeTone == .caution)
    // Same rule as isReadOnly: an unknown scope is read-only, a missing one writable.
    #expect(token(scope: "admin").scopeTitle == "只读"); #expect(token(scope: "admin").isReadOnly)
    #expect(token(scope: nil).scopeTitle == "读写"); #expect(!token(scope: nil).isReadOnly)
}

@Test func usageLineShowsRelativeTimeAndIP() {
    let now = instant("2026-10-21T02:00:00Z")
    let used = { (seconds: TimeInterval) in ServerTime.utcTimestamp(now.addingTimeInterval(-seconds)) }
    #expect(token(used: used(180), ip: "203.0.113.24").usageLine(now: now, timeZone: shanghai) == "最近使用 3 分钟前 · 203.0.113.24")
    #expect(token(used: used(180), ip: "").usageLine(now: now, timeZone: shanghai) == "最近使用 3 分钟前")
    #expect(token(used: used(180), ip: nil).usageLine(now: now, timeZone: shanghai) == "最近使用 3 分钟前")
    // Shanghai 10:00 now: 23:00 UTC the day before is already 07:00 today there; 15:30 UTC is 23:30 yesterday.
    #expect(token(used: "2026-10-20T23:00:00Z", ip: "198.51.100.7").usageLine(now: now, timeZone: shanghai) == "最近使用 今天 07:00 · 198.51.100.7")
    #expect(token(used: "2026-10-20T15:30:00Z", ip: "198.51.100.7").usageLine(now: now, timeZone: shanghai) == "最近使用 昨天 23:30 · 198.51.100.7")
}

@Test func neverUsedWhenLastUsedIsNullOrUnreadable() {
    let now = instant("2026-10-21T02:00:00Z")
    for raw in [nil, "", "yesterday", "0001-01-01T00:00:00Z"] {
        #expect(token(used: raw, ip: "203.0.113.24").usageLine(now: now, timeZone: shanghai) == "从未使用")
    }
    let decoded = try! JSONDecoder().decode(AdminAccessToken.self, from: Data(#"{"id":3,"last_used_at":null,"last_used_ip":""}"#.utf8))
    #expect(decoded.usageLine(now: now, timeZone: shanghai) == "从未使用")
}

@Test func expiryLineCountsServerCalendarDays() {
    let now = instant("2026-10-21T02:00:00Z")
    #expect(token(expires: "2027-01-16T03:00:00Z").expiryLine(now: now, timeZone: shanghai) == "2027/01/16 到期 · 还剩 87 天")
    #expect(token(expires: "2027-01-16T03:00:00Z").daysLeft(now: now, timeZone: shanghai) == 87)
    // 17:00 UTC is already the next day in Shanghai, though the same day in UTC.
    #expect(token(expires: "2026-10-21T17:00:00Z").expiryLine(now: now, timeZone: shanghai) == "2026/10/22 到期 · 还剩 1 天")
    #expect(token(expires: "2026-10-21T17:00:00.123456789Z").daysLeft(now: now, timeZone: shanghai) == 1)
    #expect(token(expires: "2027-01-16T11:00:00+08:00").expiryLine(now: now, timeZone: shanghai) == "2027/01/16 到期 · 还剩 87 天")
}

@Test func expiryDueTodayAndMissing() {
    let now = instant("2026-10-21T02:00:00Z")
    #expect(token(expires: "2026-10-21T15:00:00Z").expiryLine(now: now, timeZone: shanghai) == "今天到期")
    #expect(token(expires: "2026-10-21T15:00:00Z").daysLeft(now: now, timeZone: shanghai) == 0)
    for raw in [nil, "", "soon"] {
        let missing = token(expires: raw)
        #expect(missing.expiryLine(now: now, timeZone: shanghai) == "—")
        #expect(missing.daysLeft(now: now, timeZone: shanghai) == nil)
        #expect(!missing.isExpiringSoon(now: now, timeZone: shanghai))
    }
}

@Test func expiringSoonAtSevenDaysOrLess() {
    let now = instant("2026-10-21T02:00:00Z")
    let soon = { (days: Int) in token(expires: ServerTime.utcTimestamp(now.addingTimeInterval(TimeInterval(days) * 86_400))).isExpiringSoon(now: now, timeZone: shanghai) }
    #expect(soon(7)); #expect(!soon(8)); #expect(soon(5)); #expect(soon(0)); #expect(!soon(87))
}

@Test func revokeConfirmationCopy() {
    #expect(token(name: "监控脚本").revokeTitle == "吊销「监控脚本」？")
    #expect(token(name: "监控脚本").revokeMessage == "用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。")
    #expect(token(name: "本机 iPhone", current: true).revokeMessage == "用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。\n本机会退出这个站点。")
    #expect(token(name: "  ").revokeTitle == "吊销「未命名令牌」？")
    #expect(token(name: nil).displayName == "未命名令牌")
    #expect(AdminAccessToken.revokedReceipt("监控脚本") == "已吊销「监控脚本」")
}

@Test func accessTokenPageFixedWording() {
    #expect(AdminAccessToken.intro == "访问令牌以签发它的管理员身份调用管理接口，可只读、会过期、能单独吊销。比 Admin Key 安全：Admin Key 以第一个管理员身份操作，丢了只能到 Web 重新生成。")
    #expect(AdminAccessToken.currentBadgeText == "本机")
    #expect(AdminAccessToken.emptyTitle == "还没有访问令牌")
    #expect(AdminAccessToken.emptyMessage == "首版 App 不签发访问令牌。")
    #expect(AdminAccessToken.revokeActionTitle == "吊销")
}

@Test func accessTokenMemberwiseInitMatchesDecoding() throws {
    let json = #"""
    {"id":7,"name":"监控脚本","prefix":"sat_3f9a","last4":"c71e","scope":"write","expires_at":"2027-01-16T03:00:00Z",
     "last_used_at":"2026-10-21T01:57:00Z","last_used_ip":"203.0.113.24","created_at":"2026-10-01T00:00:00Z","current":true}
    """#
    let decoded = try JSONDecoder().decode(AdminAccessToken.self, from: Data(json.utf8))
    #expect(decoded == token(expires: "2027-01-16T03:00:00Z", used: "2026-10-21T01:57:00Z", ip: "203.0.113.24", current: true))
    #expect(AdminAccessToken(id: 3) == (try JSONDecoder().decode(AdminAccessToken.self, from: Data(#"{"id":3}"#.utf8))))
}
