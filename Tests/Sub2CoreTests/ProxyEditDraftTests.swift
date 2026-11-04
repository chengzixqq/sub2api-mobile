import Foundation
import Testing
@testable import Sub2Core

// 60 §14.3–§14.4 (S6-14): the add / edit / renew form, what it sends and what it says.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let noon = at("2026-10-16T12:00:00+08:00")
private let secret = "s3cret-proxy-pass"

private func proxy(id: Int = 1, name: String = "hk-02", scheme: String = "socks5", host: String = "203.0.113.24", port: Int? = 1080,
                   username: String? = "relay", status: String? = "active", expires: String? = "2026-10-22T09:00:00+08:00", warnDays: Int? = 7,
                   fallback: String? = "proxy", backup: Int? = 2, accounts: Int? = 3) -> AdminProxy {
    AdminProxy(id: id, name: name, scheme: scheme, host: host, port: port, username: username, password: secret, status: status,
               expiresAt: expires.map(at), fallbackMode: fallback, backupProxyID: backup, expiryWarnDays: warnDays, accountCount: accounts,
               hasAccountCountKey: accounts != nil)
}
private let hk02 = proxy()
private let jpTokyo = proxy(id: 3, name: "jp-tokyo-1", scheme: "socks5h", host: "192.0.2.88", status: "expired",
                            expires: "2026-10-13T09:00:00+08:00", fallback: "none", backup: nil, accounts: 1)
private let catalog = [
    hk02, proxy(id: 2, name: "sg-01", expires: nil, fallback: "direct", backup: nil), jpTokyo,
    proxy(id: 6, name: "de-fra-1", status: "inactive", expires: "2026-10-19T00:00:00+08:00", fallback: "direct", backup: nil),
    proxy(id: 8, name: "kr-seoul-1", expires: "2026-10-15T00:00:00+08:00", fallback: "direct", backup: nil)
]
private func candidates(excluding id: Int?) -> [ProxyBackupCandidate] { ProxyBackupCandidate.make(from: catalog, excluding: id, now: noon) }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func body(_ draft: ProxyEditDraft, id: Int = 1) throws -> String { text(try draft.updateRequest(now: noon).requestBody(proxyID: id)) }
private func filled() -> ProxyEditDraft {
    var draft = ProxyEditDraft.adding()
    draft.name = "  fr-par-1 "
    draft.host = "198.51.100.9"
    draft.portText = "1080"
    return draft
}

@Test func proxyEditModeOrderAndTitles() {
    #expect(ProxyEditMode.resolve(nil, now: noon) == .add)
    #expect(ProxyEditMode.resolve(hk02, now: noon) == .edit)
    #expect(ProxyEditMode.resolve(proxy(status: "inactive"), now: noon) == .edit)
    #expect(ProxyEditMode.resolve(jpTokyo, now: noon) == .renew)
    // Stopped before its day came and now past it: ··· offers 续期…, so the sheet renews.
    #expect(ProxyEditMode.resolve(proxy(status: "inactive", expires: "2026-10-15T00:00:00+08:00"), now: noon) == .renew)
    #expect([ProxyEditMode.add, .edit, .renew].map(\.title) == ["添加代理", "编辑代理", "续期代理"])
    #expect(ProxyEditDraft.adding().submitTitle == "添加")
    #expect(ProxyEditDraft(editing: hk02, now: noon).submitTitle == "保存")
    var renew = ProxyEditDraft(editing: jpTokyo, now: noon)
    #expect(renew.submitTitle == "保存")
    renew.selectExpiry(.days(30))
    #expect(renew.submitTitle == "续期")

    #expect(ProxyEditSection.order(for: .renew) == [.expiry, .status, .fallback, .name, .address, .auth])
    #expect(ProxyEditSection.order(for: .edit) == [.name, .address, .auth, .expiry, .fallback, .status])
    #expect(ProxyEditSection.order(for: .add) == [.name, .address, .auth, .expiry, .fallback])
    #expect(ProxyEditSection.order(for: .edit).map { $0.title(in: .edit) } == ["名称与协议", "地址", "认证（可选）", "有效期", "到期回退", "状态"])
    #expect(ProxyEditSection.expiry.title(in: .renew) == "有效期 · 续期")
}

@Test func proxyEditAddingDefaultsAndRequired() {
    let draft = ProxyEditDraft.adding()
    #expect(draft.mode == .add && draft.original == nil)
    #expect(draft.scheme == .socks5 && draft.expiry == .never && draft.warnDays == 7 && draft.fallback == ProxyFallbackMode.none)
    #expect(!draft.hasUnsavedChanges)
    #expect(draft.issues(backups: []) == [.nameRequired, .hostRequired, .portMissing])
    for section in ProxyEditSection.allCases { #expect(draft.issueNote(for: section, backups: []) == nil) }
    #expect(!draft.isSubmittable(backups: [], now: noon))
    #expect(filled().isSubmittable(backups: [], now: noon))
    #expect(filled().hasUnsavedChanges)
    #expect(ProxyProtocolChoice.allCases.map(\.title) == ["HTTP", "HTTPS", "SOCKS5", "SOCKS5H"])
    #expect(ProxyEditCopy.fallbackOrder.map(ProxyEditCopy.title) == ["不回退", "回退直连", "备用代理"])
    #expect([ProxyStatusChange.active, .inactive].map(ProxyEditCopy.title) == ["正常", "停用"])
}

@Test func proxyEditPrefillsWithoutPassword() {
    let draft = ProxyEditDraft(editing: hk02, now: noon)
    #expect(draft.mode == .edit && draft.password.isEmpty)
    #expect(draft.name == "hk-02" && draft.scheme == .socks5 && draft.host == "203.0.113.24" && draft.portText == "1080" && draft.username == "relay")
    #expect(draft.expiry == .keep && draft.warnDays == 7 && draft.fallback == .proxy && draft.backupID == 2 && draft.status == .active)
    #expect(ProxyEditDraft(editing: proxy(expires: nil), now: noon).expiry == .never)
    #expect(ProxyEditDraft(editing: proxy(scheme: "vendor"), now: noon).scheme == .socks5)
    #expect(!ProxyEditDraft(editing: proxy(scheme: "vendor"), now: noon).updateRequest(now: noon).hasChanges)
    #expect(ProxyEditDraft(editing: proxy(scheme: " SOCKS5H "), now: noon).scheme == .socks5h)
    #expect(ProxyEditDraft(editing: proxy(status: "inactive"), now: noon).status == .inactive)
    // A backup id kept from an earlier fallback mode is not the form's.
    #expect(ProxyEditDraft(editing: proxy(fallback: "direct", backup: 2), now: noon).backupID == nil)
    #expect(!draft.hasUnsavedChanges)
    #expect(!draft.isSubmittable(backups: candidates(excluding: 1), now: noon))
}

@Test func proxyEditRenewStatusSwitchesBack() {
    var renew = ProxyEditDraft(editing: jpTokyo, now: noon)
    #expect(renew.mode == .renew && renew.status == .inactive && renew.expiry == .keep)
    #expect(!renew.hasUnsavedChanges)
    renew.selectExpiry(.days(30))
    #expect(renew.status == .active)
    renew.status = .inactive
    renew.selectExpiry(.days(90))
    #expect(renew.status == .active)
    renew.status = .inactive
    renew.selectExpiry(.keep)
    #expect(renew.status == .inactive)

    var edit = ProxyEditDraft(editing: proxy(status: "inactive"), now: noon)
    edit.selectExpiry(.days(30))
    #expect(edit.status == .inactive)
}

@Test func proxyEditPortAndCustomDays() {
    #expect(ProxyEditDraft.sanitizePort("12a34") == "1234")
    #expect(ProxyEditDraft.sanitizePort("123456") == "12345")
    #expect(ProxyEditDraft.sanitizePort("８０80") == "80")
    #expect(ProxyEditDraft.sanitizeCustomDays("1a2345") == "1234")
    var draft = filled()
    draft.portText = "1234567"
    #expect(draft.portText == "12345")
    for (port, ok) in [("0", false), ("65536", false), ("1", true), ("65535", true), ("70000", false)] {
        draft.portText = port
        #expect(draft.issues(backups: []).contains(.portOutOfRange) == !ok, "\(port)")
        #expect(draft.issueNote(for: .address, backups: []) == (ok ? nil : "端口必须在 1-65535 之间"), "\(port)")
    }
    draft.portText = "8080"
    draft.selectExpiry(.custom)
    #expect(draft.issues(backups: []) == [.customDaysMissing])
    #expect(draft.issueNote(for: .expiry, backups: []) == nil)
    draft.customDaysText = "0"
    #expect(draft.issues(backups: []) == [.customDaysInvalid])
    #expect(draft.issueNote(for: .expiry, backups: []) == "天数要在 1-9999 之间")
    draft.customDaysText = "1"
    #expect(draft.issues(backups: []).isEmpty)
    draft.customDaysText = "99999x"
    #expect(draft.customDaysText == "9999" && draft.issues(backups: []).isEmpty)
}

@Test func proxyEditValidationRows() {
    var draft = filled()
    draft.name = "   "
    draft.host = " \n"
    #expect(draft.issues(backups: []) == [.nameRequired, .hostRequired])
    draft.name = String(repeating: "代", count: 34)
    draft.host = String(repeating: "h", count: 256)
    draft.username = String(repeating: "u", count: 101)
    draft.password = String(repeating: "p", count: 101)
    #expect(draft.issues(backups: []) == [.nameTooLong, .hostTooLong, .usernameTooLong, .passwordTooLong])
    #expect(draft.issueNote(for: .name, backups: []) == "名称最多 100 字节")
    #expect(draft.issueNote(for: .auth, backups: []) == "用户名最多 100 字节")
    draft.name = String(repeating: "代", count: 33)
    draft.host = String(repeating: "h", count: 255)
    draft.username = ""
    draft.password = ""
    #expect(draft.issues(backups: []).isEmpty)

    let backups = candidates(excluding: nil)
    draft.fallback = .proxy
    #expect(draft.issues(backups: backups) == [.backupRequired])
    #expect(draft.issueNote(for: .fallback, backups: backups) == "选了备用代理回退，请选择一个备用代理")
    draft.backupID = 6
    #expect(draft.issues(backups: backups) == [.backupRequired])
    draft.backupID = 2
    #expect(draft.issues(backups: backups).isEmpty)

    var renew = ProxyEditDraft(editing: jpTokyo, now: noon)
    renew.status = .active
    #expect(renew.issues(backups: candidates(excluding: 3)) == [.lapsedKeepActive])
    #expect(renew.footnote(for: .status, timeZone: shanghai) == "有效期已过，改回“正常”前先在上面选新的有效期。")
    #expect(!renew.isSubmittable(backups: candidates(excluding: 3), now: noon))
    // An unusable backup the proxy already had stays chosen and does not block another change.
    var kept = ProxyEditDraft(editing: proxy(backup: 6), now: noon)
    kept.name = "hk-02b"
    #expect(kept.issues(backups: candidates(excluding: 1)).isEmpty)
}

@Test func proxyEditExpiryConversionAndOptions() {
    var draft = filled()
    #expect(draft.expiresAt(now: noon) == nil)
    draft.selectExpiry(.days(30))
    #expect(draft.expiresAt(now: noon) == noon.addingTimeInterval(2_592_000))
    draft.selectExpiry(.days(90))
    #expect(draft.expiresAt(now: noon) == noon.addingTimeInterval(7_776_000))
    draft.selectExpiry(.custom)
    draft.customDaysText = "7"
    #expect(draft.expiresAt(now: noon) == noon.addingTimeInterval(604_800))
    #expect(ProxyEditDraft.adding().expiryOptions(timeZone: shanghai).map(\.title) == ["永不过期", "30 天", "90 天", "自定义"])
    #expect(ProxyEditDraft.adding().expiryOptions(timeZone: shanghai).map(\.id) == ["never", "30", "90", "custom"])
    #expect(ProxyEditDraft(editing: hk02, now: noon).expiryOptions(timeZone: shanghai).map(\.title)
        == ["保持 2026-10-22", "永不过期", "30 天", "90 天", "自定义"])
    #expect(ProxyEditDraft(editing: jpTokyo, now: noon).expiryOptions(timeZone: shanghai).first?.title == "保持 2026-10-13（已过期）")
    #expect(ProxyEditDraft(editing: proxy(expires: nil), now: noon).expiryOptions(timeZone: shanghai).first?.choice == .never)
    // The server's day: 23:30 UTC is already the next day in Shanghai.
    #expect(ProxyEditDraft(editing: proxy(expires: "2026-12-31T23:30:00Z"), now: noon).expiryOptions(timeZone: shanghai).first?.title
        == "保持 2027-01-01")
    #expect(ProxyEditDraft(editing: hk02, now: noon).expiresAt(now: noon) == at("2026-10-22T09:00:00+08:00"))
}

@Test func proxyEditWarnDaysRange() throws {
    #expect(ProxyEditDraft.adding().warnDaysRange == 1...30)
    #expect(ProxyEditDraft(editing: proxy(warnDays: 0), now: noon).warnDaysRange == 0...30)
    #expect(ProxyEditDraft(editing: proxy(warnDays: 45), now: noon).warnDaysRange == 1...45)
    #expect(ProxyEditDraft(editing: proxy(warnDays: nil), now: noon).warnDays == 7)
    var draft = ProxyEditDraft(editing: proxy(warnDays: 0), now: noon)
    #expect(!draft.updateRequest(now: noon).hasChanges)
    draft.warnDays = 3
    #expect(try body(draft) == #"{"expiry_warn_days":3}"#)
}

@Test func proxyEditFootnotes() {
    var draft = filled()
    #expect(draft.footnote(for: .name, timeZone: shanghai) == nil)
    draft.scheme = .socks5h
    #expect(draft.footnote(for: .name, timeZone: shanghai) == "SOCKS5H 由代理服务器解析域名（远程 DNS）。")
    #expect(draft.footnote(for: .expiry, timeZone: shanghai) == "到期前按提醒天数在代理列表和告警里提示。")
    #expect(ProxyEditDraft(editing: jpTokyo, now: noon).footnote(for: .expiry, timeZone: shanghai) == "10/13 已过期。选一个新的有效期来续期。")
    #expect(draft.footnote(for: .fallback, timeZone: shanghai) == "到期后账号留在这个过期代理上，需要手动处理。")
    draft.fallback = .direct
    #expect(draft.footnote(for: .fallback, timeZone: shanghai) == "到期后把在用的账号改为直连，可在账号详情里“恢复原代理”。")
    draft.fallback = .proxy
    #expect(draft.footnote(for: .fallback, timeZone: shanghai) == "回退链会跳过停用或已过期的代理，所以它们不能选作备用。")

    var renew = ProxyEditDraft(editing: jpTokyo, now: noon)
    #expect(renew.footnote(for: .status, timeZone: shanghai) == "已过期的代理保存后仍是已过期；选新的有效期即可续期。")
    renew.selectExpiry(.days(30))
    #expect(renew.footnote(for: .status, timeZone: shanghai) == "续期后状态改回“正常”。")
    let lapsedIdle = ProxyEditDraft(editing: proxy(status: "inactive", expires: "2026-10-15T00:00:00+08:00"), now: noon)
    #expect(lapsedIdle.footnote(for: .status, timeZone: shanghai) == "已过期的代理保存后仍是停用；选新的有效期即可续期。")
    var edit = ProxyEditDraft(editing: hk02, now: noon)
    #expect(edit.footnote(for: .status, timeZone: shanghai) == nil)
    edit.status = .inactive
    #expect(edit.footnote(for: .status, timeZone: shanghai)
        == "停用后：账号编辑里选不到它，也不会被选作备用代理；正在用它的 3 个账号照常走这个代理，要更换请到账号编辑页。")
    var unused = ProxyEditDraft(editing: proxy(accounts: 0), now: noon)
    unused.status = .inactive
    #expect(unused.footnote(for: .status, timeZone: shanghai) == "停用后：账号编辑里选不到它，也不会被选作备用代理；已经在用它的账号照常走这个代理。")
}

@Test func proxyEditBackupCandidates() {
    let list = candidates(excluding: 1)
    #expect(list.map(\.id) == [2, 3, 6, 8])
    #expect(list.map(\.name) == ["sg-01", "jp-tokyo-1", "de-fra-1", "kr-seoul-1"])
    #expect(list.map(\.isSelectable) == [true, false, false, false])
    #expect(list.map(\.note) == [nil, "已过期", "停用", "已过期"])
    #expect(candidates(excluding: nil).map(\.id) == [1, 2, 3, 6, 8])
}

@Test func proxyEditCreateRequestBytes() throws {
    let minimal = try filled().createRequest(now: noon)
    #expect(text(try minimal.requestBody())
        == #"{"expiry_warn_days":7,"fallback_mode":"none","host":"198.51.100.9","name":"fr-par-1","port":1080,"protocol":"socks5"}"#)
    var full = filled()
    full.scheme = .http
    full.username = "relay"
    full.password = secret
    full.selectExpiry(.days(30))
    full.warnDays = 5
    full.fallback = .proxy
    full.backupID = 2
    let seconds = Int(noon.timeIntervalSince1970) + 2_592_000
    #expect(text(try full.createRequest(now: noon).requestBody())
        == #"{"backup_proxy_id":2,"expires_at":\#(seconds),"expiry_warn_days":5,"fallback_mode":"proxy","host":"198.51.100.9","#
        + #""name":"fr-par-1","password":"\#(secret)","port":1080,"protocol":"http","username":"relay"}"#)
    full.fallback = .direct
    #expect(!text(try full.createRequest(now: noon).requestBody()).contains("backup_proxy_id"))
    full.portText = "0"
    #expect(throws: APIError.self) { try full.createRequest(now: noon) }
    full.portText = "8080"
    full.selectExpiry(.custom)
    #expect(throws: APIError.self) { try full.createRequest(now: noon) }
}

@Test func proxyEditUpdateRequestKeys() throws {
    var draft = ProxyEditDraft(editing: hk02, now: noon)
    #expect(!draft.updateRequest(now: noon).hasChanges)
    draft.name = " hk-02 "
    #expect(!draft.updateRequest(now: noon).hasChanges)
    draft.name = "hk-02-new"
    #expect(try body(draft) == #"{"name":"hk-02-new"}"#)

    var cleared = ProxyEditDraft(editing: hk02, now: noon)
    cleared.username = ""
    #expect(try body(cleared) == #"{"username":""}"#)
    var typed = ProxyEditDraft(editing: hk02, now: noon)
    typed.password = "n3w"
    #expect(try body(typed) == #"{"password":"n3w"}"#)
    var never = ProxyEditDraft(editing: hk02, now: noon)
    never.selectExpiry(.never)
    #expect(try body(never) == #"{"expires_at":null}"#)
    var none = ProxyEditDraft(editing: hk02, now: noon)
    none.fallback = ProxyFallbackMode.none
    #expect(try body(none) == #"{"backup_proxy_id":null,"fallback_mode":"none"}"#)
    var other = ProxyEditDraft(editing: hk02, now: noon)
    other.backupID = 8
    #expect(try body(other) == #"{"backup_proxy_id":8}"#)
    var address = ProxyEditDraft(editing: hk02, now: noon)
    address.scheme = .https
    address.host = "203.0.113.25"
    address.portText = "443"
    #expect(try body(address) == #"{"host":"203.0.113.25","port":443,"protocol":"https"}"#)
}

@Test func proxyEditUpdateRequestStatus() throws {
    var edit = ProxyEditDraft(editing: hk02, now: noon)
    edit.status = .inactive
    #expect(try body(edit) == #"{"status":"inactive"}"#)
    var renew = ProxyEditDraft(editing: jpTokyo, now: noon)
    renew.selectExpiry(.days(30))
    let seconds = Int(noon.timeIntervalSince1970) + 2_592_000
    #expect(try body(renew, id: 3) == #"{"expires_at":\#(seconds),"status":"active"}"#)
    var idle = ProxyEditDraft(editing: jpTokyo, now: noon)
    idle.name = "jp-tokyo-2"
    #expect(try body(idle, id: 3) == #"{"name":"jp-tokyo-2"}"#)
    #expect(idle.isSubmittable(backups: candidates(excluding: 3), now: noon))
}

@Test func proxyEditNetworkFieldsAndUnsaved() {
    let base = ProxyEditDraft(editing: hk02, now: noon)
    let network: [(inout ProxyEditDraft) -> Void] = [
        { $0.scheme = .http }, { $0.host = "203.0.113.30" }, { $0.portText = "1081" }, { $0.username = "other" }, { $0.password = "x" }
    ]
    for change in network {
        var draft = base
        change(&draft)
        #expect(draft.updateRequest(now: noon).touchesNetwork)
        #expect(draft.hasUnsavedChanges)
    }
    let quiet: [(inout ProxyEditDraft) -> Void] = [
        { $0.name = "hk-03" }, { $0.selectExpiry(.days(30)) }, { $0.fallback = .direct }, { $0.warnDays = 9 }, { $0.status = .inactive }
    ]
    for change in quiet {
        var draft = base
        change(&draft)
        #expect(!draft.updateRequest(now: noon).touchesNetwork)
        #expect(draft.hasUnsavedChanges)
    }
    var back = base
    back.name = "hk-03"
    back.name = "hk-02"
    back.selectExpiry(.custom)
    back.customDaysText = "12"
    back.selectExpiry(.keep)
    #expect(!back.hasUnsavedChanges)
}

@Test func proxyEditAddAttemptReusesKey() throws {
    var keys = [UUID(), UUID(), UUID()].makeIterator()
    let draft = { () -> ProxyEditDraft in var d = filled(); d.selectExpiry(.days(30)); return d }()
    let first = try ProxyAddAttempt.next(previous: nil, draft: draft, now: noon) { keys.next()! }
    let again = try ProxyAddAttempt.next(previous: first, draft: draft, now: noon.addingTimeInterval(40)) { keys.next()! }
    #expect(again.key == first.key)
    #expect(try again.request.requestBody() == first.request.requestBody())
    var renamed = draft
    renamed.name = "fr-par-2"
    let second = try ProxyAddAttempt.next(previous: again, draft: renamed, now: noon) { keys.next()! }
    #expect(second.key != first.key)
    let third = try ProxyAddAttempt.next(previous: second, draft: draft, now: noon) { keys.next()! }
    #expect(third.key != first.key && third.key != second.key)
    var broken = draft
    broken.portText = "0"
    #expect(throws: APIError.self) { try ProxyAddAttempt.next(previous: third, draft: broken, now: noon) { UUID() } }
}

/// 00 §2.5.4 核对: a row of the same name is this add only when it was not listed at 添加, was created after it (15 seconds for
/// the clocks) and carries what was sent; the key's retries keep the time and the list of the first 添加.
@Test func proxyEditAddAttemptMatchesOnlyItsOwnRow() throws {
    let attempt = try ProxyAddAttempt.next(previous: nil, draft: filled(), now: noon, existing: [5]) { UUID() }
    let again = try ProxyAddAttempt.next(previous: attempt, draft: filled(), now: noon.addingTimeInterval(40), existing: [5, 9]) { UUID() }
    #expect(again == attempt && again.madeAt == noon && again.existing == [5])
    func made(id: Int = 9, created: Date? = noon.addingTimeInterval(2), username: String? = nil, fallback: String? = "none",
              warnDays: Int? = 7) -> AdminProxy {
        AdminProxy(id: id, name: "fr-par-1", scheme: "socks5", host: "198.51.100.9", port: 1080, username: username, status: "active",
                   createdAt: created, fallbackMode: fallback, expiryWarnDays: warnDays)
    }
    #expect(attempt.matches(made()))
    #expect(attempt.matches(made(created: noon.addingTimeInterval(-15))))
    #expect(attempt.matches(made(username: "", fallback: nil, warnDays: nil)))
    #expect(!attempt.matches(made(id: 5)))
    #expect(!attempt.matches(made(created: noon.addingTimeInterval(-16))))
    #expect(!attempt.matches(made(created: nil)))
    #expect(!attempt.matches(made(username: "user-b")))
    #expect(!attempt.matches(made(fallback: "direct")))
    #expect(!attempt.matches(made(warnDays: 3)))
    #expect(!attempt.matches(AdminProxy(id: 9, name: "fr-par-1", scheme: "socks5h", host: "198.51.100.9", port: 1080, createdAt: noon)))
    #expect(!attempt.matches(AdminProxy(id: 9, name: "fr-par-1", scheme: "socks5", host: "198.51.100.9", port: 1081, createdAt: noon)))
}

@Test func proxyEditFailureClassification() {
    func failure(_ status: Int, _ reason: String?, backup: Bool = false) -> ProxyWriteFailure {
        ProxyWriteFailure.classify(APIError.server(status: status, reason: reason), sentBackup: backup)
    }
    #expect(failure(400, "PROXY_BACKUP_REQUIRED") == .rejected(message: "选了备用代理回退，请选择一个备用代理", section: .fallback))
    #expect(failure(400, "PROXY_BACKUP_SELF") == .rejected(message: "备用代理不能是它自己", section: .fallback))
    #expect(failure(404, "PROXY_NOT_FOUND", backup: true) == .backupGone)
    #expect(failure(404, "PROXY_NOT_FOUND") == .gone)
    #expect(ProxyEditCopy.backupGone == "备用代理已不存在，请重新选择")
    for status in [403, 423, 429, 500] {
        guard case .rejected(let message, nil) = failure(status, nil) else { Issue.record("\(status)"); continue }
        #expect(!message.isEmpty)
    }
    for status in [502, 504] { #expect(failure(status, nil) == .unconfirmed(retryNotBefore: nil)) }
    #expect(ProxyWriteFailure.classify(APIError(kind: .transport, message: "timeout"), sentBackup: false) == .unconfirmed(retryNotBefore: nil))
    let later = noon.addingTimeInterval(10)
    let unknown = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: later), key: "k", actionID: nil, lastError: nil)
    #expect(ProxyWriteFailure.classify(unknown, sentBackup: false) == .unconfirmed(retryNotBefore: later))
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    #expect(ProxyWriteFailure.classify(conflict, sentBackup: false) == .needsNewKey(message: conflict.localizedDescription))
    #expect(ProxyWriteFailure.classify(CancellationError(), sentBackup: false) == .cancelled)
    // Other reasons read the catalog's words for their status (R11).
    let warnDays = APIError.server(status: 400, reason: "PROXY_WARN_DAYS_INVALID")
    #expect(ProxyWriteFailure.classify(warnDays, sentBackup: false) == .rejected(message: warnDays.localizedDescription, section: nil))
}

@Test func proxyEditReceiptsAndTarget() {
    #expect(ProxyEditDraft.adding().renewTarget == nil)
    #expect(ProxyEditDraft(editing: hk02, now: noon).renewTarget == nil)
    let target = ProxyEditDraft(editing: jpTokyo, now: noon).renewTarget
    #expect(target?.line == "jp-tokyo-1 · SOCKS5H · 192.0.2.88:1080 · 1 个账号仍在用")
    #expect(ProxyEditDraft(editing: proxy(id: 7, name: "us-east-2", status: "expired", expires: "2026-10-11T00:00:00+08:00", accounts: 0), now: noon)
        .renewTarget?.detail == "SOCKS5 · 203.0.113.24:1080 · 没有账号在用")
    #expect(ProxyEditDraft.adding().successReceipt(saved: hk02) == "代理添加成功")
    #expect(ProxyEditDraft(editing: jpTokyo, now: noon).successReceipt(saved: proxy(id: 3, name: "jp-tokyo-1", status: "active")) == "已续期 · jp-tokyo-1 恢复正常")
    #expect(ProxyEditDraft(editing: jpTokyo, now: noon).successReceipt(saved: jpTokyo) == "代理更新成功")
    #expect(ProxyEditDraft(editing: hk02, now: noon).successReceipt(saved: hk02) == "代理更新成功")
    #expect(ProxyEditCopy.undoFailed(inUse: true) == "撤销没有成功：已有账号在用这个代理")
    #expect(ProxyEditCopy.undoFailed(reason: "对象不存在或已删除") == "撤销没有成功：对象不存在或已删除")
}

@Test func proxyEditPasswordRedacted() throws {
    var draft = ProxyEditDraft(editing: hk02, now: noon)
    draft.password = "typed-\(secret)"
    var dumped = ""
    dump(draft, to: &dumped)
    for shown in [String(describing: draft), String(reflecting: draft), dumped] { #expect(!shown.contains(secret), "\(shown)") }
    var added = filled()
    added.password = secret
    let attempt = try ProxyAddAttempt.next(previous: nil, draft: added, now: noon) { UUID() }
    var dumpedAttempt = ""
    dump(attempt, to: &dumpedAttempt)
    for shown in [String(describing: attempt), String(reflecting: attempt), dumpedAttempt] { #expect(!shown.contains(secret), "\(shown)") }
}
