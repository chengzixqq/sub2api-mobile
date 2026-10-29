import Foundation
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let noon = at("2026-10-16T12:00:00+08:00")

private func proxy(id: Int = 1, name: String = "hk-02", scheme: String = "socks5", host: String = "203.0.113.24", port: Int? = 1080,
                   username: String? = "relay", password: String? = "fixture-pass", status: String? = "active", expires: String? = nil,
                   warnDays: Int? = 7, fallback: String? = "none", backup: Int? = nil, accounts: Int? = 3, moved: Int? = 0,
                   created: String? = "2026-07-14T10:00:00+08:00") -> AdminProxy {
    AdminProxy(id: id, name: name, scheme: scheme, host: host, port: port, username: username, password: password, status: status,
               createdAt: created.map(at), expiresAt: expires.map(at), fallbackMode: fallback, backupProxyID: backup, expiryWarnDays: warnDays,
               accountCount: accounts, hasAccountCountKey: accounts != nil, fallbackAccountCount: moved)
}
private func values(_ rows: [ProxyKV]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: rows.map { ($0.key.rawValue, $0.value) })
}

@Test func proxyDetailExpiryRowsWithAndWithoutNote() {
    let soon = proxy(expires: "2026-10-22T09:00:00+08:00")
    let noted = ProxyDetailRows.expiry(soon, backupName: nil, hasNote: true, now: noon, timeZone: shanghai)
    #expect(noted.map(\.key) == [.expiresAt, .warnDays])
    #expect(noted.map(\.label) == ["到期日", "到期提醒"])
    #expect(values(noted) == ["expiresAt": "2026-10-22", "warnDays": "提前 7 天"])

    let long = proxy(expires: "2027-02-25T09:00:00+08:00")
    #expect(values(ProxyDetailRows.expiry(long, backupName: nil, hasNote: false, now: noon, timeZone: shanghai))
        == ["expiresAt": "2027-02-25", "warnDays": "提前 7 天", "remaining": "剩余 132 天", "fallback": "不回退"])
    let never = proxy(expires: nil, fallback: "direct")
    let neverRows = ProxyDetailRows.expiry(never, backupName: nil, hasNote: false, now: noon, timeZone: shanghai)
    #expect(neverRows.map(\.key) == [.expiresAt, .warnDays, .remaining, .fallback])
    #expect(values(neverRows) == ["expiresAt": "永不过期", "warnDays": "提前 7 天", "remaining": "不限", "fallback": "回退直连"])
    let idle = proxy(status: "inactive", expires: "2026-10-19T00:00:00+08:00", fallback: "proxy", backup: 2)
    #expect(values(ProxyDetailRows.expiry(idle, backupName: "sg-01", hasNote: false, now: noon, timeZone: shanghai))["remaining"] == "—")
    #expect(values(ProxyDetailRows.expiry(idle, backupName: "sg-01", hasNote: false, now: noon, timeZone: shanghai))["fallback"] == "备用 sg\u{2011}01")
    #expect(values(ProxyDetailRows.expiry(idle, backupName: nil, hasNote: false, now: noon, timeZone: shanghai))["fallback"] == "备用 —")
    // The expiry day is the server's: 23:30 UTC is already the next day in Shanghai.
    let late = proxy(expires: "2026-12-31T23:30:00Z", warnDays: nil)
    #expect(values(ProxyDetailRows.expiry(late, backupName: nil, hasNote: true, now: noon, timeZone: shanghai))
        == ["expiresAt": "2027-01-01", "warnDays": "—"])
}

@Test func proxyDetailConnectionRowsMaskPassword() {
    let rows = ProxyDetailRows.connection(proxy(), timeZone: shanghai)
    #expect(rows.map(\.key) == [.scheme, .port, .host, .username, .password, .createdAt])
    #expect(rows.map(\.label) == ["协议", "端口", "主机", "用户名", "密码", "创建时间"])
    #expect(values(rows) == ["scheme": "SOCKS5", "port": "1080", "host": "203.0.113.24", "username": "relay", "password": "••••••",
                             "createdAt": "2026-07-14"])
    #expect(rows.filter(\.isMonospaced).map(\.key) == [.host, .username])
    let bare = ProxyDetailRows.connection(proxy(scheme: "socks5h", port: 65_535, username: "", password: nil, created: nil), timeZone: shanghai)
    #expect(values(bare) == ["scheme": "SOCKS5H", "port": "65535", "host": "203.0.113.24", "username": "—", "password": "未设置",
                             "createdAt": "—"])
    #expect(bare.filter(\.isMonospaced).map(\.key) == [.host])
    #expect(values(ProxyDetailRows.connection(proxy(scheme: "https", port: nil, password: ""), timeZone: shanghai))["port"] == "—")
    #expect(values(ProxyDetailRows.connection(proxy(scheme: "https", password: ""), timeZone: shanghai))["password"] == "未设置")
    for row in rows { #expect(!row.value.contains("fixture-pass")) }
}

@Test func proxyDetailAccountLineMetaAndFallbackLink() {
    #expect(ProxyDetailRows.accountDetail(ProxyAccountRef(id: 1, name: "Claude-官方-01", platform: "anthropic", type: "oauth"), catalog: nil)
        == "Anthropic · OAuth")
    #expect(ProxyDetailRows.accountDetail(ProxyAccountRef(id: 4, name: "OpenAI-主力-01", platform: "openai", type: "apikey"), catalog: nil)
        == "OpenAI · API Key")
    #expect(ProxyDetailCopy.accountsMeta(3) == "3 个")
    let moved = proxy(accounts: 0, moved: 2)
    #expect(ProxyDetailRows.fallbackLink(moved, hasCapability: true) == "被改走的账号 2 个")
    #expect(ProxyDetailRows.fallbackLink(moved, hasCapability: false) == nil)
    #expect(ProxyDetailRows.fallbackLink(proxy(moved: 0), hasCapability: true) == nil)
    #expect(ProxyDetailRows.fallbackLink(proxy(moved: nil), hasCapability: true) == nil)
}

@Test func proxyDetailStatusToggleAndReceipts() {
    #expect(ProxyStatusToggle(proxy(status: "active"), now: noon) == .disable)
    #expect(ProxyStatusToggle(proxy(status: nil), now: noon) == .disable)
    #expect(ProxyStatusToggle(proxy(status: "inactive"), now: noon) == .enable)
    #expect(ProxyStatusToggle(proxy(status: "expired"), now: noon) == .renew)
    // Stopped before its day came: the sweep only marks active proxies, so it is still “inactive” and is renewed, not enabled.
    #expect(ProxyStatusToggle(proxy(status: "inactive", expires: "2026-10-13T00:00:00+08:00"), now: noon) == .renew)
    #expect(ProxyStatusToggle(proxy(status: "inactive", expires: "2026-10-16T12:00:00+08:00"), now: noon) == .renew)
    #expect(ProxyStatusToggle(proxy(status: "inactive", expires: "2026-10-16T12:00:01+08:00"), now: noon) == .enable)
    #expect(ProxyStatusToggle(proxy(status: "active", expires: "2026-10-13T00:00:00+08:00"), now: noon) == .disable)
    #expect([ProxyStatusToggle.disable, .enable, .renew].map(\.menuTitle) == ["停用代理", "启用代理", "续期…"])
    #expect(ProxyStatusToggle.disable.target == .inactive && ProxyStatusToggle.disable.undoTarget == .active)
    #expect(ProxyStatusToggle.enable.target == .active && ProxyStatusToggle.enable.undoTarget == .inactive)
    #expect(ProxyStatusToggle.renew.target == nil && ProxyStatusToggle.renew.undoTarget == nil)
    #expect(ProxyDetailCopy.disabled(name: "hk-02", accountCount: 3) == "已停用 hk-02 · 在用的 3 个账号不受影响")
    #expect(ProxyDetailCopy.disabled(name: "hk-02", accountCount: 0) == "已停用 hk-02")
    #expect(ProxyDetailCopy.enabled(name: "de-fra-1") == "已启用 de-fra-1")
    #expect(ProxyDetailCopy.statusFailed(.disable, reason: "网络错误") == "停用没有成功：网络错误")
    #expect(ProxyDetailCopy.statusFailed(.enable, reason: "网络错误") == "启用没有成功：网络错误")
    #expect(ProxyDetailCopy.undoFailed(reason: "网络错误") == "撤销没有成功：网络错误")
    #expect(ProxyDetailCopy.deleteFailed(reason: "网络错误") == "删除没有成功：网络错误")
    #expect(ProxyPresentation.displayName(proxy(id: 9, name: "  ")) == "代理 #9")
}

@Test func proxyDetailDeleteBlocksAndConflict() {
    #expect(ProxyDeleteBlock.before(proxy(accounts: 3, moved: 2)) == .inUse(name: "hk-02", accounts: 3))
    #expect(ProxyDeleteBlock.before(proxy(name: "us-east-2", accounts: 0, moved: 2)) == .fallback(name: "us-east-2", accounts: 2))
    #expect(ProxyDeleteBlock.before(proxy(accounts: 0, moved: 0)) == nil)
    let inUse = ProxyDeleteBlock.inUse(name: "hk-02", accounts: 3)
    #expect(inUse.title == "不能删除「hk-02」")
    #expect(inUse.message == "该代理已有 3 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。")
    #expect(!inUse.offersFallbackPage(hasCapability: true))
    let fallback = ProxyDeleteBlock.fallback(name: "us-east-2", accounts: 2)
    #expect(fallback.title == "不能删除「us-east-2」")
    #expect(fallback.message == "2 个账号到期时从这个代理改走，删除后它们就恢复不了原代理。先恢复这些账号，或在账号详情里处理。")
    #expect(fallback.offersFallbackPage(hasCapability: true) && !fallback.offersFallbackPage(hasCapability: false))
    #expect(inUse.id != fallback.id)

    func conflict(_ metadata: [String: String], reason: String = ProxyReason.inUse, status: Int = 409) -> APIError {
        APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata))
    }
    #expect(ProxyDeleteBlock.fromConflict(conflict(["fallback_account_count": "2"]), name: "us-east-2") == fallback)
    for metadata in [[:], ["fallback_account_count": "0"], ["fallback_account_count": "x"]] {
        #expect(ProxyDeleteBlock.fromConflict(conflict(metadata), name: "hk-02") == nil)
    }
    #expect(ProxyDeleteBlock.fromConflict(conflict(["fallback_account_count": "2"], reason: "OTHER"), name: "hk-02") == nil)
    #expect(ProxyDeleteBlock.isInUseConflict(conflict([:])) && !ProxyDeleteBlock.isInUseConflict(conflict([:], reason: "OTHER")))

    let local = proxy(accounts: 0)
    #expect(ProxyDeleteBlock.resolveInUse(refreshed: proxy(accounts: 2), local: local) == .inUse(name: "hk-02", accounts: 2))
    #expect(ProxyDeleteBlock.resolveInUse(refreshed: proxy(accounts: 0), local: local) == .inUse(name: "hk-02", accounts: 1))
    #expect(ProxyDeleteBlock.resolveInUse(refreshed: nil, local: proxy(accounts: 4)) == .inUse(name: "hk-02", accounts: 4))
    #expect(ProxyDeleteBlock.resolveInUse(refreshed: proxy(accounts: 0, moved: 3), local: local) == .fallback(name: "hk-02", accounts: 3))
}

@Test func proxyDetailQualityNotice() {
    let pass = ProxyQualityResult(score: 92, grade: "A", items: [ProxyQualityItem(target: "base_connectivity", status: "pass")])
    #expect(ProxyQualityNotice(pass) == ProxyQualityNotice(text: "质量检测完成：评分 92（A）", tone: .ok))
    let failed = ProxyQualityResult(score: 78, grade: "B", items: [ProxyQualityItem(target: "base_connectivity", status: "fail")])
    #expect(ProxyQualityNotice(failed) == ProxyQualityNotice(text: "代理质量检测失败", tone: .critical))
    #expect(ProxyQualityNotice(ProxyQualityResult(score: 92, grade: "A")).text == "代理质量检测失败")
    #expect(ProxyQualityNotice(ProxyQualityResult(items: pass.items)).tone == .critical)
}

@Test func proxyDetailFailuresAreClassified() {
    #expect(ProxyDetailFailure.classify(APIError.server(status: 404, reason: ProxyReason.notFound)) == .gone)
    #expect(ProxyDetailFailure.isGone(APIError.server(status: 404, reason: ProxyReason.notFound)))
    #expect(!ProxyDetailFailure.isGone(APIError.server(status: 404, reason: nil)))
    #expect(ProxyDetailFailure.classify(APIError.server(status: 502, reason: nil)) == .unconfirmed)
    #expect(ProxyDetailFailure.classify(APIError(kind: .transport, message: "无法连接站点")) == .unconfirmed)
    #expect(ProxyDetailFailure.classify(CancellationError()) == .cancelled)
    let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
    #expect(ProxyDetailFailure.classify(readOnly) == .rejected(readOnly.localizedDescription))
}

/// H02: an older server's `GET :id` has no `account_count`; the counts the row was shown with stay.
@Test func proxyDetailKeepsShownCountsOverACountlessRead() {
    let shown = proxy(accounts: 3, moved: 2)
    let countless = AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, status: "inactive", latencyMs: 90,
                               latencyStatus: "success", qualityScore: 70, qualityGrade: "C")
    let kept = countless.keepingCounts(of: shown)
    #expect(kept.accountCount == 3 && kept.hasAccountCountKey && kept.fallbackAccountCount == 2)
    #expect(kept.status == "inactive" && kept.latencyMs == 90 && kept.qualityScore == 70 && kept.qualityGrade == "C")
    #expect(countless.keepingCounts(of: nil) == countless)
    #expect(countless.keepingCounts(of: proxy(id: 2)) == countless)
    #expect(countless.keepingCounts(of: proxy(accounts: nil, moved: nil)) == countless)
    // A read with the key is the server's count, 0 included.
    let counted = proxy(accounts: 0, moved: 0)
    #expect(counted.keepingCounts(of: shown) == counted)
}
