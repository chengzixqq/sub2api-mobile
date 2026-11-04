import Foundation
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
/// 2026-10-16 12:00 in Shanghai.
private let noon = at("2026-10-16T12:00:00+08:00")
private let hk02 = AccountProxy(id: 1, name: "hk-02", status: "active", expiresAt: "2026-10-22T09:00:00+08:00", scheme: "socks5",
                                host: "203.0.113.24", port: 1080, expiryWarnDays: 7)
private let tokyo = AccountProxy(id: 3, name: "jp-tokyo-1", status: "expired", expiresAt: "2026-10-13T10:00:00+08:00", scheme: "socks5h",
                                 host: "198.51.100.30", port: 1080, expiryWarnDays: 7)

private func account(proxy: AccountProxy? = nil, proxyID: Int? = nil, originID: Int? = nil, originName: String? = nil) -> UpstreamAccount {
    UpstreamAccount(id: 9, name: "Kimi-01", platform: "kimi", type: "apikey", proxy: proxy, proxyID: proxyID ?? proxy?.id,
                    proxyFallbackOriginID: originID, proxyFallbackOriginName: originName)
}
private func admin(_ id: Int, _ name: String, created: String, expires: String? = "2027-03-01T00:00:00+08:00", status: String = "active",
                   count: Int? = 3, countryCode: String? = nil, city: String? = nil, warn: Int? = 7) -> AdminProxy {
    AdminProxy(id: id, name: name, scheme: "https", host: "198.51.100.\(id)", port: 443, status: status, createdAt: at(created),
               expiresAt: expires.map(at), expiryWarnDays: warn, accountCount: count, hasAccountCountKey: count != nil,
               countryCode: countryCode, city: city)
}

@Test func sectionRowVariants() {
    let row = AccountProxyPresentation.section(account(proxy: hk02), now: noon, timeZone: shanghai).row
    #expect(row.kind == .proxy && row.title == "hk-02" && row.detail == "SOCKS5 · 6 天后到期" && row.expiry?.tone == .caution)
    #expect(row.address == "socks5://203.0.113.24:1080" && row.proxyID == 1)
    let direct = AccountProxyPresentation.section(account(), now: noon, timeZone: shanghai).row
    #expect(direct == AccountProxyRowContent(kind: .direct, title: "无代理", detail: nil, expiry: nil, address: nil, proxyID: nil))
    let unresolved = AccountProxyPresentation.section(account(proxyID: 9), now: noon, timeZone: shanghai).row
    #expect(unresolved.kind == .unresolved && unresolved.title == "代理 #9" && unresolved.proxyID == 9 && unresolved.address == nil)
    let unnamed = AccountProxy(id: 5, name: " ", status: "active", scheme: "http", host: "203.0.113.140", port: 8080)
    let blank = AccountProxyPresentation.section(account(proxy: unnamed), now: noon, timeZone: shanghai).row
    #expect(blank.title == "代理 #5" && blank.detail == "HTTP · 永不过期")
    #expect(["https", "socks5h", "http", "SOCKS5", "quic"].map(AccountProxyPresentation.protocolLabel) == ["HTTPS", "SOCKS5H", "HTTP", "SOCKS5", "QUIC"])
    #expect(AccountProxyPresentation.protocolLabel(nil).isEmpty)
}

@Test func sectionHints() {
    let expired = AccountProxyPresentation.section(account(proxy: tokyo), now: noon, timeZone: shanghai)
    #expect(expired.hint == AccountProxyHint(text: AccountProxyCopy.expiredHint, tone: .critical))
    #expect(expired.row.detail == "SOCKS5H · 10/13 已过期" && expired.row.expiry?.tone == .critical)
    let stopped = AccountProxy(id: 6, name: "de-fra-1", status: "inactive", expiresAt: "2026-10-19T10:00:00+08:00", scheme: "socks5")
    let inactive = AccountProxyPresentation.section(account(proxy: stopped), now: noon, timeZone: shanghai)
    #expect(inactive.hint == AccountProxyHint(text: AccountProxyCopy.inactiveHint, tone: .neutral))
    #expect(inactive.row.detail == "SOCKS5 · 10/19 到期")
    #expect(AccountProxyPresentation.section(account(proxy: hk02), now: noon, timeZone: shanghai).hint == nil)
}

@Test func fallbackLineAndFootnote() {
    let fallen = AccountProxyPresentation.section(account(proxy: hk02, originID: 4, originName: "hk-01"), now: noon, timeZone: shanghai)
    #expect(fallen.fallback == AccountProxyFallbackLine(originID: 4, originName: "hk-01", title: "已回退：原代理 hk-01", detail: "原代理到期后已改为hk-02"))
    #expect(fallen.footnote == "选中即生效，回执里可撤销。恢复原代理不能撤销。")
    let nameless = AccountProxyPresentation.section(account(proxy: hk02, originID: 4), now: noon, timeZone: shanghai)
    #expect(nameless.fallback?.title == "已回退：原代理 #4" && nameless.fallback?.originName == "#4")
    let direct = AccountProxyPresentation.section(account(originID: 4, originName: "hk-01"), now: noon, timeZone: shanghai)
    #expect(direct.fallback?.detail == "原代理到期后已改为直连")
    let plain = AccountProxyPresentation.section(account(proxy: hk02), now: noon, timeZone: shanghai)
    #expect(plain.fallback == nil && plain.footnote == "选中即生效，回执里可撤销。")
}

@Test func pickerOptionsOrderAndText() {
    let region = Locale(identifier: "zh_CN").localizedString(forRegionCode: "SG")!
    let proxies = [
        admin(4, "hk-01", created: "2026-05-22T00:00:00Z", count: 0),
        admin(1, "hk-02", created: "2026-07-14T00:00:00Z", expires: "2026-10-22T09:00:00+08:00", count: 3),
        admin(6, "de-fra-1", created: "2026-08-01T00:00:00Z", status: "inactive"),
        admin(2, "sg-01", created: "2026-08-22T00:00:00Z", expires: "2027-03-01T09:00:00+08:00", count: 3, countryCode: "SG"),
        admin(7, "us-a", created: "2026-08-22T00:00:00Z", expires: nil, count: nil),
        admin(5, "us-west-3", created: "2026-08-25T00:00:00Z", expires: nil, count: 1, city: "Fremont")
    ]
    let picker = AccountProxyPresentation.picker(proxies, current: hk02, currentID: 1, now: noon, timeZone: shanghai)
    #expect(picker.options.map(\.id) == [5, 7, 2, 1, 4])
    #expect(picker.currentNote == nil)
    let byID = Dictionary(uniqueKeysWithValues: picker.options.map { ($0.id, $0) })
    #expect(byID[1]?.badge == "6 天后到期" && byID[1]?.meta == "3 个账号在用")
    #expect(byID[1]?.name == "hk-02" && byID[1]?.address == "https://198.51.100.1:443")
    #expect(byID[2]?.badge == nil && byID[2]?.meta == "3 个账号在用 · \(region) · 剩余 136 天")
    #expect(byID[4]?.meta.hasPrefix("没有账号在用 · 剩余 ") == true)
    #expect(byID[5]?.meta == "1 个账号在用 · Fremont · 永不过期")
    #expect(byID[7]?.meta == "永不过期")
}

@Test func pickerCurrentNote() {
    let active = [admin(1, "hk-02", created: "2026-07-14T00:00:00Z")]
    let lapsed = AccountProxyPresentation.picker(active, current: tokyo, currentID: 3, now: noon, timeZone: shanghai).currentNote
    #expect(lapsed == AccountProxyHint(text: "当前代理 jp-tokyo-1 已过期，不在可选列表里。选一个启用中的代理，或改为无代理。", tone: .critical))
    let stopped = AccountProxy(id: 6, name: "de-fra-1", status: "inactive")
    let idle = AccountProxyPresentation.picker(active, current: stopped, currentID: 6, now: noon, timeZone: shanghai).currentNote
    #expect(idle == AccountProxyHint(text: "当前代理 de-fra-1 已停用，不在可选列表里。选一个启用中的代理，或改为无代理。", tone: .neutral))
    #expect(AccountProxyPresentation.picker(active, current: hk02, currentID: 1, now: noon, timeZone: shanghai).currentNote == nil)
    #expect(AccountProxyPresentation.picker(active, current: nil, currentID: nil, now: noon, timeZone: shanghai).currentNote == nil)
    let unknown = AccountProxyPresentation.picker(active, current: nil, currentID: 7, now: noon, timeZone: shanghai).currentNote
    #expect(unknown == AccountProxyHint(text: "当前代理 #7 不在可选列表里。选一个启用中的代理，或改为无代理。", tone: .neutral))
    #expect(AccountProxyPresentation.pickerFootnote == "只列出启用中的代理；已停用、已过期的代理在“代理”里管理。")
}

@Test func proxyCopies() {
    #expect(AccountProxyCopy.fieldName("hk-02") == "代理 → hk-02" && AccountProxyCopy.fieldName(nil) == "代理 → 无代理")
    #expect(AccountEditCopy.savedReceipt([AccountProxyCopy.fieldName("hk-02")]) == "已保存：代理 → hk-02")
    #expect(AccountProxyCopy.revertTitle("hk-01") == "恢复原代理「hk-01」？")
    #expect(AccountProxyCopy.revertMessage("hk-01") == "账号改回走 hk-01，出口 IP 随之改变。恢复后不能撤销。")
    #expect(AccountProxyCopy.reverted("hk-01") == "已恢复原代理「hk-01」")
    #expect(AccountProxyCopy.revertFailed(reason: "站点暂时不可用") == "恢复原代理没有成功：站点暂时不可用")
    #expect(AccountProxyCopy.notInFallback == "这个账号已不在回退状态")
    #expect(AccountProxyCopy.originUnavailable == "原代理已删除、停用或过期，续期并启用后才能恢复")
    #expect(AccountProxyCopy.viewOrigin == "查看原代理" && AccountProxyCopy.unconfirmed == "恢复原代理结果未确认")
}
