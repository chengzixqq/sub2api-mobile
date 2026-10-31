import Foundation
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utc = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
/// The design's day: 2026-10-16 12:00 in Shanghai.
private let noon = at("2026-10-16T12:00:00+08:00")
private func place(_ code: String) -> String { Locale(identifier: "zh_CN").localizedString(forRegionCode: code)! }

// The seven proxies of the design (shared/data.jsx), with the account counts its accounts give them.
private let hk02 = AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "fixture-pass",
                              status: "active", expiresAt: at("2026-10-22T00:00:00+08:00"), fallbackMode: "proxy", backupProxyID: 2,
                              expiryWarnDays: 7, accountCount: 3, hasAccountCountKey: true, fallbackAccountCount: 0, latencyMs: 182,
                              latencyStatus: "success", ipAddress: "203.0.113.24", countryCode: "HK", qualityScore: 92, qualityGrade: "A",
                              qualityChecked: at("2026-10-15T22:00:00+08:00"))
private let sg01 = AdminProxy(id: 2, name: "sg-01", scheme: "https", host: "198.51.100.7", port: 443, status: "active",
                              expiresAt: at("2027-03-01T00:00:00+08:00"), fallbackMode: "none", expiryWarnDays: 7, accountCount: 2,
                              hasAccountCountKey: true, fallbackAccountCount: 0, latencyMs: 96, latencyStatus: "success", countryCode: "SG")
private let jpTokyo = AdminProxy(id: 3, name: "jp-tokyo-1", scheme: "socks5h", host: "192.0.2.88", port: 1080, status: "expired",
                                 expiresAt: at("2026-10-13T00:00:00+08:00"), fallbackMode: "none", expiryWarnDays: 7, accountCount: 1,
                                 hasAccountCountKey: true, fallbackAccountCount: 0, latencyStatus: "failed",
                                 latencyMessage: "dial tcp 192.0.2.88:1080: i/o timeout")
private let hk01 = AdminProxy(id: 4, name: "hk-01", scheme: "http", host: "203.0.113.9", port: 3128, status: "active",
                              expiresAt: at("2026-11-30T00:00:00+08:00"), fallbackMode: "proxy", backupProxyID: 1, expiryWarnDays: 7,
                              accountCount: 2, hasAccountCountKey: true, fallbackAccountCount: 0, latencyMs: 311, latencyStatus: "success",
                              countryCode: "HK")
private let usWest = AdminProxy(id: 5, name: "us-west-3", scheme: "http", host: "203.0.113.140", port: 8080, status: "active", fallbackMode: "none",
                                expiryWarnDays: 7, accountCount: 1, hasAccountCountKey: true, fallbackAccountCount: 0, latencyMs: 238,
                                latencyStatus: "success", countryCode: "US")
private let usEast = AdminProxy(id: 7, name: "us-east-2", scheme: "http", host: "198.51.100.23", port: 3128, status: "expired",
                                expiresAt: at("2026-10-11T00:00:00+08:00"), fallbackMode: "direct", expiryWarnDays: 7, accountCount: 0,
                                hasAccountCountKey: true, fallbackAccountCount: 2, qualityScore: 80, qualityGrade: "B")
private let deFra = AdminProxy(id: 6, name: "de-fra-1", scheme: "socks5", host: "198.51.100.61", port: 1080, status: "inactive",
                               expiresAt: at("2026-10-19T00:00:00+08:00"), fallbackMode: "none", expiryWarnDays: 3, accountCount: 0,
                               hasAccountCountKey: true, fallbackAccountCount: 0)
private let demo = [hk02, sg01, jpTokyo, hk01, usWest, usEast, deFra]

/// A proxy for one row of a table: only what the rule looks at.
private func proxy(id: Int = 9, name: String = "kr-01", scheme: String = "http", status: String? = "active", expires: String? = nil,
                   fallback: String? = "none", warnDays: Int? = 7, accounts: Int? = 0, moved: Int? = 0, latencyMs: Int? = nil,
                   latency: String? = nil, message: String? = nil, checkedAt: Date? = nil) -> AdminProxy {
    AdminProxy(id: id, name: name, scheme: scheme, host: "198.51.100.40", port: 8080, status: status, expiresAt: expires.map(at),
               fallbackMode: fallback, expiryWarnDays: warnDays, accountCount: accounts, hasAccountCountKey: accounts != nil,
               fallbackAccountCount: moved, latencyMs: latencyMs, latencyStatus: latency, latencyMessage: message, latencyCheckedAt: checkedAt)
}
private let soonDate = "2026-10-22T09:00:00+08:00"

@Test func filterRouteValuesAndTitles() {
    #expect(ProxyFilter(routeValue: "expired") == .expired && ProxyFilter(routeValue: "soon") == .soon)
    #expect(ProxyFilter(routeValue: "failed") == .failed && ProxyFilter(routeValue: "inactive") == .inactive)
    for value in [nil, "", "x", "all"] as [String?] { #expect(ProxyFilter(routeValue: value) == .all) }
    #expect(ProxyFilter.allCases.map(\.title) == ["全部", "已过期", "即将到期", "链接失败", "停用"])
}

@Test func chipsCountAndDotOnDemoSet() {
    let chips = ProxyPresentation.chips(demo, now: noon, timeZone: shanghai)
    #expect(chips.map(\.filter) == ProxyFilter.allCases && chips.map(\.title) == ProxyFilter.allCases.map(\.title))
    #expect(chips.map(\.count) == [7, 2, 1, 1, 1])
    #expect(chips.map(\.showsDot) == [false, true, false, false, false])
    #expect(demo.filter { ProxyPresentation.matches($0, filter: .soon, now: noon, timeZone: shanghai) }.map(\.name) == ["hk-02"])
    #expect(demo.filter { ProxyPresentation.matches($0, filter: .failed, now: noon, timeZone: shanghai) }.map(\.name) == ["jp-tokyo-1"])

    let calm = ProxyPresentation.chips([hk02, usEast, deFra], now: noon, timeZone: shanghai)
    #expect(calm.map(\.count) == [3, 1, 1, 0, 1] && calm.allSatisfy { !$0.showsDot })
}

@Test func linkFailedAndSoonFilterEdges() {
    func failed(_ proxy: AdminProxy) -> Bool { ProxyPresentation.isLinkFailed(proxy) }
    #expect(!failed(proxy(status: "inactive", accounts: 3, latency: "failed")))
    #expect(failed(proxy(status: "active", accounts: 0, latency: "failed")))
    #expect(!failed(proxy(status: "expired", accounts: 0, latency: "failed")) && failed(proxy(status: "expired", accounts: 1, latency: "failed")))
    #expect(!failed(proxy(status: "active", accounts: 3, latency: "success")) && !failed(proxy(status: "active", accounts: 3)))

    func soon(_ proxy: AdminProxy) -> Bool { ProxyPresentation.matches(proxy, filter: .soon, now: noon, timeZone: shanghai) }
    #expect(!soon(proxy(expires: soonDate, accounts: 0)) && soon(proxy(expires: soonDate, accounts: 1)))
    #expect(soon(proxy(expires: "2026-10-15T09:00:00+08:00", accounts: 2)))
    #expect(!soon(proxy(status: "inactive", expires: soonDate, accounts: 2)) && !soon(proxy(expires: "2026-11-30T00:00:00+08:00", accounts: 2)))

    let mixed = demo + [proxy(id: 20, status: "active", accounts: 0, latency: "failed"), proxy(id: 21, expires: "2026-10-15T09:00:00+08:00", accounts: 2)]
    for chip in ProxyPresentation.chips(mixed, now: noon, timeZone: shanghai) {
        #expect(chip.count == mixed.filter { ProxyPresentation.matches($0, filter: chip.filter, now: noon, timeZone: shanghai) }.count)
    }
}

@Test func bannerVariants() {
    let lapsed = ProxyPresentation.banner([jpTokyo, sg01], now: noon, timeZone: shanghai)
    #expect(lapsed == ProxyBanner(title: "jp-tokyo-1 已过期，仍有 1 个账号在用", detail: "续期，或给这些账号换代理", tone: .critical, target: .expired, proxyIDs: [3]))
    let soon = ProxyPresentation.banner([hk02, sg01], now: noon, timeZone: shanghai)
    #expect(soon == ProxyBanner(title: "hk-02 6 天后到期，3 个账号在用", detail: "到期前续期，或设置到期回退", tone: .caution, target: .soon, proxyIDs: [1]))
    let both = ProxyPresentation.banner(demo, now: noon, timeZone: shanghai)
    #expect(both == ProxyBanner(title: "2 个代理需要处理", detail: "jp-tokyo-1 已过期仍在用 · hk-02 6 天后到期", tone: .critical, target: .expired, proxyIDs: [3, 1]))
    #expect(ProxyBanner.actionTitle == "查看")

    let sooner = proxy(id: 30, name: "tw-01", expires: "2026-10-18T09:00:00+08:00", accounts: 1)
    let ordered = ProxyPresentation.banner([hk02, sooner], now: noon, timeZone: shanghai)
    #expect(ordered?.detail == "tw-01 2 天后到期 · hk-02 6 天后到期" && ordered?.tone == .caution && ordered?.target == .soon && ordered?.proxyIDs == [30, 1])

    let quiet = [usEast, deFra, proxy(expires: soonDate, accounts: 0), proxy(status: "inactive", expires: soonDate, accounts: 4), sg01]
    #expect(ProxyPresentation.banner(quiet, now: noon, timeZone: shanghai) == nil)
    #expect(ProxyPresentation.banner([], now: noon, timeZone: shanghai) == nil)
}

@Test func rowTableFor12_3() {
    func row(_ proxy: AdminProxy, testing: Bool = false) -> ProxyRowContent { ProxyPresentation.row(proxy, now: noon, timeZone: shanghai, isTesting: testing) }
    let soon = row(hk02)
    #expect(soon.id == 1 && soon.title == "hk-02" && soon.address == "SOCKS5 · 203.0.113.24:1080")
    #expect(soon.tone == .caution && soon.glyph == .normal && soon.trailing == .latency("182ms"))
    #expect(soon.footnote == "3 个账号在用 · " + place("HK") && soon.expiryBadge == ProxyBadge(text: "6 天后到期", tone: .caution))
    #expect(!soon.showsLinkFailedBadge && !soon.isDimmed)

    let calm = row(sg01)
    #expect(calm.tone == nil && calm.glyph == .normal && calm.trailing == .latency("96ms") && calm.expiryBadge == nil)
    #expect(calm.address == "HTTPS · 198.51.100.7:443" && calm.footnote == "2 个账号在用 · " + place("SG"))

    let idle = row(deFra)
    #expect(idle.tone == nil && idle.glyph == .idle && idle.trailing == .status(ProxyBadge(text: "停用", tone: .neutral)))
    #expect(idle.footnote == "没有账号在用" && idle.isDimmed && idle.expiryBadge == nil)
    #expect(row(proxy(status: "inactive", accounts: 2)).footnote == "2 个账号在用")

    let stuck = row(jpTokyo)
    #expect(stuck.tone == .critical && stuck.glyph == .error && stuck.trailing == .status(ProxyBadge(text: "已过期", tone: .critical)))
    #expect(stuck.footnote == "1 个账号仍在用 · 10/13 到期" && stuck.showsLinkFailedBadge && !stuck.isDimmed && stuck.expiryBadge == nil)
    #expect(stuck.address == "SOCKS5H · 192.0.2.88:1080")

    let empty = row(usEast)
    #expect(empty.tone == nil && empty.glyph == .idle && empty.trailing == .status(ProxyBadge(text: "已过期", tone: .neutral)))
    #expect(empty.footnote == "没有账号在用 · 10/11 到期" && empty.isDimmed && !empty.showsLinkFailedBadge)
    #expect(empty.address == "HTTP · 198.51.100.23:3128")

    let broken = row(proxy(accounts: 2, latency: "failed", message: "proxy connection failed"))
    #expect(broken.tone == .critical && broken.glyph == .error && broken.trailing == .linkFailed && broken.footnote == "2 个账号在用")
    let untested = row(proxy(accounts: 0))
    #expect(untested.trailing == .untested && untested.glyph == .untested && untested.tone == nil && untested.footnote == "没有账号在用")
    #expect(row(hk02, testing: true).trailing == .testing && row(deFra, testing: true).trailing == .testing)
    #expect(row(proxy(latencyMs: 1_234, latency: "success")).trailing == .latency("1.2s"))
    #expect(row(proxy(name: "  ")).title == "代理 #9")
}

@Test func latencyReadingAndLastTestedFollowServerZone() {
    func reading(_ proxy: AdminProxy, testing: Bool = false, zone: ServerTimeZone = shanghai) -> ProxyLatencyReading {
        ProxyPresentation.latency(proxy, isTesting: testing, now: noon, timeZone: zone)
    }
    #expect(reading(hk02) == .success(value: "182", unit: "ms", needle: 0.364, lastTested: nil))
    #expect(reading(proxy(latencyMs: 650, latency: "success")) == .success(value: "650", unit: "ms", needle: 1, lastTested: nil))
    #expect(reading(proxy(latencyMs: 0, latency: "success")) == .success(value: "0", unit: "ms", needle: 0, lastTested: nil))
    #expect(reading(proxy(latencyMs: 2_000, latency: "success")) == .success(value: "2.0", unit: "s", needle: 1, lastTested: nil))
    let tested = proxy(latencyMs: 182, latency: "success", checkedAt: at("2026-10-16T01:12:00Z"))
    #expect(reading(tested) == .success(value: "182", unit: "ms", needle: 0.364, lastTested: "上次测试 10/16 09:12"))
    #expect(reading(tested, zone: utc) == .success(value: "182", unit: "ms", needle: 0.364, lastTested: "上次测试 10/16 01:12"))
    #expect(reading(jpTokyo) == .failed(message: "dial tcp 192.0.2.88:1080: i/o timeout"))
    #expect(reading(proxy(latency: "failed", message: "  ")) == .failed(message: nil))
    #expect(reading(proxy()) == .untested && reading(proxy(latency: "success")) == .untested)
    #expect(reading(jpTokyo, testing: true) == .testing)
    #expect(ProxyPresentation.latencyScaleMaxMs == 500)
    #expect(ProxyPresentation.latencyText(182) == "182ms" && ProxyPresentation.latencyText(nil) == nil)
}

@Test func statusCardTableFor13_3() {
    func card(_ proxy: AdminProxy, testing: Bool = false, justTested: Date? = nil, zone: ServerTimeZone = shanghai) -> ProxyStatusCard {
        ProxyPresentation.statusCard(proxy, isTesting: testing, justTestedAt: justTested, timeZone: zone)
    }
    #expect(card(hk02) == ProxyStatusCard(badge: ProxyBadge(text: "正常", tone: .ok), cause: nil, isCritical: false))
    #expect(card(proxy(status: "inactive", accounts: 2)) == ProxyStatusCard(badge: ProxyBadge(text: "停用", tone: .neutral), cause: "在用的账号不受影响", isCritical: false))
    #expect(card(deFra).cause == "账号编辑里选不到它")
    #expect(card(jpTokyo) == ProxyStatusCard(badge: ProxyBadge(text: "已过期", tone: .critical), cause: nil, isCritical: true))
    #expect(card(usEast) == ProxyStatusCard(badge: ProxyBadge(text: "已过期", tone: .neutral), cause: nil, isCritical: false))
    #expect(card(proxy(status: nil)).badge == ProxyBadge(text: "正常", tone: .ok))

    let justNow = at("2026-10-16T09:41:00+08:00")
    #expect(card(hk02, testing: true, justTested: justNow).cause == "正在测试连通性")
    #expect(card(hk02, justTested: justNow).cause == "刚刚测试 09:41" && card(hk02, justTested: justNow, zone: utc).cause == "刚刚测试 01:41")
    #expect(card(deFra, justTested: justNow).cause == "刚刚测试 09:41")
    #expect(card(proxy(accounts: 0, latency: "failed")).isCritical && !card(proxy(status: "inactive", accounts: 2, latency: "failed")).isCritical)
    #expect(!card(proxy(status: "expired", accounts: 0, latency: "failed")).isCritical)
}

@Test func factsCells() {
    func facts(_ proxy: AdminProxy, checking: Bool = false) -> ProxyFacts { ProxyPresentation.facts(proxy, isCheckingQuality: checking, timeZone: shanghai) }
    #expect(facts(hk02) == ProxyFacts(exitIP: "203.0.113.24", exitIPIsMonospaced: true, region: place("HK"), quality: "A · 92", qualityDate: "10/15"))
    #expect(ProxyPresentation.facts(hk02, isCheckingQuality: false, timeZone: utc).qualityDate == "10/15")
    #expect(facts(proxy()) == ProxyFacts(exitIP: "—", exitIPIsMonospaced: false, region: "—", quality: "—", qualityDate: nil))
    #expect(facts(AdminProxy(id: 2, name: "sg-01", qualityGrade: "A")).quality == "A")
    #expect(facts(AdminProxy(id: 2, name: "sg-01", qualityScore: 81)).quality == "81")
    #expect(facts(AdminProxy(id: 2, name: "sg-01", qualityChecked: at("2026-10-15T22:00:00+08:00"))).qualityDate == nil)
    #expect(facts(hk02, checking: true).quality == "检测中…" && facts(hk02, checking: true).qualityDate == nil)
    let lateUTC = AdminProxy(id: 2, name: "sg-01", qualityGrade: "B", qualityChecked: at("2026-10-15T17:30:00Z"))
    #expect(facts(lateUTC).qualityDate == "10/16" && ProxyPresentation.facts(lateUTC, isCheckingQuality: false, timeZone: utc).qualityDate == "10/15")
}

@Test func expiryNoteSevenRows() {
    func note(_ proxy: AdminProxy, backup: String? = nil, supports: Bool = true) -> ProxyExpiryNote? {
        ProxyPresentation.expiryNote(proxy, backupName: backup, supportsFallbackAccounts: supports, now: noon, timeZone: shanghai)
    }
    let lapsed = "2026-10-13T00:00:00+08:00"
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "none", accounts: 3)) == ProxyExpiryNote(tone: .critical,
            text: "已过期，3 个账号仍在用这个代理。到期回退设的是“不回退”，所以账号没被改走；续期，或到账号编辑页换代理。"))
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "direct", accounts: 3)) == ProxyExpiryNote(tone: .critical,
            text: "已过期，3 个账号仍在用这个代理。续期，或到账号编辑页换代理。"))
    #expect(note(usEast) == ProxyExpiryNote(tone: .neutral, text: "到期后已把 2 个账号改为直连。续期并启用后，可以在“被改走的账号”里一键恢复。"))
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "proxy", accounts: 0, moved: 2), backup: "sg-01")?.text
            == "到期后已把 2 个账号改为备用 sg\u{2011}01。续期并启用后，可以在“被改走的账号”里一键恢复。")
    #expect(note(usEast, supports: false) == ProxyExpiryNote(tone: .neutral, text: "到期后已把 2 个账号改为直连。要改回来，在账号详情里点“恢复原代理”。"))
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "direct", accounts: 0, moved: 0)) == ProxyExpiryNote(tone: .neutral, text: "已过期，没有账号在用。"))
    #expect(note(proxy(expires: soonDate, fallback: "none", accounts: 3, moved: 2))
            == ProxyExpiryNote(tone: .caution, text: "2 个账号在本代理到期时被改走，还没恢复。"))
    #expect(note(proxy(expires: "2027-03-01T00:00:00+08:00", accounts: 0, moved: 1))?.text == "1 个账号在本代理到期时被改走，还没恢复。")
    #expect(note(proxy(expires: soonDate, fallback: "none", accounts: 3)) == ProxyExpiryNote(tone: .caution,
            text: "6 天后到期。到期后不回退，在用的 3 个账号会继续挂在这个过期代理上。"))
    #expect(note(proxy(expires: soonDate, fallback: "none", accounts: 0))?.text == "6 天后到期。到期后不回退。")
    #expect(note(proxy(expires: soonDate, fallback: "proxy", accounts: 3)) == ProxyExpiryNote(tone: .caution, text: "6 天后到期。到期后把在用的账号改为备用代理。"))
    #expect(note(hk02, backup: "sg-01")?.text == "6 天后到期。到期后把在用的账号改为备用 sg\u{2011}01。")
    #expect(note(proxy(expires: soonDate, fallback: "direct", accounts: 3))?.text == "6 天后到期。到期后把在用的账号改为直连。")
    #expect(note(deFra) == nil && note(proxy(status: "inactive", expires: soonDate, accounts: 2, moved: 2)) == nil)
    #expect(note(sg01) == nil && note(usWest) == nil)
}

@Test func expiryNoteOldServerAndSoonBoundary() {
    func note(_ proxy: AdminProxy, zone: ServerTimeZone = shanghai, now: Date = noon) -> ProxyExpiryNote? {
        ProxyPresentation.expiryNote(proxy, backupName: nil, supportsFallbackAccounts: false, now: now, timeZone: zone)
    }
    let lapsed = "2026-10-13T00:00:00+08:00"
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "direct", accounts: 0, moved: nil)) == ProxyExpiryNote(tone: .neutral,
            text: "到期后已把在用的账号改为直连。要改回来，在账号详情里点“恢复原代理”。"))
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "proxy", accounts: 0, moved: nil))?.text
            == "到期后已把在用的账号改为备用代理。要改回来，在账号详情里点“恢复原代理”。")
    #expect(note(proxy(status: "expired", expires: lapsed, fallback: "none", accounts: 0, moved: nil))?.text == "已过期，没有账号在用。")

    #expect(note(proxy(expires: "2026-10-23T09:00:00+08:00", warnDays: 7, accounts: 1))?.text.hasPrefix("7 天后到期。") == true)
    #expect(note(proxy(expires: "2026-10-24T09:00:00+08:00", warnDays: 7, accounts: 1)) == nil)
    let expires = at("2026-10-23T01:00:00+08:00"), late = at("2026-10-16T23:00:00+08:00")
    let edge = proxy(expires: "2026-10-23T01:00:00+08:00", warnDays: 7, accounts: 1)
    #expect(note(edge, now: late)?.text.hasPrefix("7 天后到期。") == true)
    let utcDays = ProxyExpiry.days(until: expires, now: late, timeZone: utc)
    #expect(utcDays == 6 && note(edge, zone: utc, now: late)?.text.hasPrefix("\(utcDays) 天后到期。") == true)
}

@Test func copyURLEncodingAndShapes() {
    func url(scheme: String = "http", host: String = "198.51.100.7", port: Int? = 3128, username: String? = nil, password: String? = nil) -> String? {
        ProxyPresentation.copyURL(AdminProxy(id: 1, name: "p", scheme: scheme, host: host, port: port, username: username, password: password))
    }
    #expect(url(scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "p@ss:w/rd")
            == "socks5://relay:p%40ss%3Aw%2Frd@203.0.113.24:1080")
    #expect(url(username: "relay") == "http://relay@198.51.100.7:3128")
    #expect(url(username: "", password: "x") == "http://:x@198.51.100.7:3128")
    #expect(url(scheme: "https", port: 443, username: "", password: "") == "https://198.51.100.7:443")
    #expect(url(username: "用户 1") == "http://%E7%94%A8%E6%88%B7%201@198.51.100.7:3128")
    #expect(url(scheme: "socks5", host: "2001:db8::1", port: 1080) == "socks5://[2001:db8::1]:1080")
    #expect(url(port: nil) == "http://198.51.100.7")
    #expect(url(host: " ") == nil && url(scheme: "") == nil)
}

@Test func deleteRestrictionAndAddressLine() {
    #expect(ProxyPresentation.deleteRestriction(proxy(accounts: 3)) == .hasAccounts(3))
    #expect(ProxyPresentation.deleteRestriction(proxy(accounts: 0, moved: 2)) == .hasFallbackAccounts(2))
    #expect(ProxyPresentation.deleteRestriction(proxy(accounts: 1, moved: 2)) == .hasAccounts(1))
    #expect(ProxyPresentation.deleteRestriction(proxy(accounts: 0, moved: 0)) == .allowed)
    #expect(ProxyPresentation.deleteRestriction(proxy(accounts: nil, moved: nil)) == .allowed)
    #expect(ProxyPresentation.addressLine(hk02) == "SOCKS5 · 203.0.113.24:1080")
    #expect(ProxyPresentation.addressLine(AdminProxy(id: 2, name: "sg-01", scheme: "http", host: "198.51.100.7")) == "HTTP · 198.51.100.7")
    #expect(ProxyPresentation.addressLine(AdminProxy(id: 2, name: "v6", scheme: "socks5", host: "2001:db8::1", port: 1080)) == "SOCKS5 · [2001:db8::1]:1080")
}
