import Foundation
import Testing
@testable import Sub2Core

// 30 §7.4 (S3-13): the new / edit key form, its requests, the undo, the read-back, the failure words, 显示完整 Key's
// availability and finding a created key after a lost reply.

private func amount(_ text: String) -> Decimal { Decimal(string: text)! }
private func at(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
/// 10:00 in Shanghai.
private let now = at("2026-10-26T02:00:00Z")
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!

private func key(id: Int = 7, name: String = "脚本", quota: String = "0", used: String = "0", expires: Date? = nil, white: [String] = [],
                 black: [String] = [], limits: (String, String, String) = ("0", "0", "0"), created: Date? = nil) -> AdminAPIKey {
    AdminAPIKey(id: id, userID: 1, keyMasked: "sk-…cret", name: name, groupID: 2, ipWhitelist: white, ipBlacklist: black, quota: amount(quota),
                quotaUsed: amount(used), expiresAt: expires, rateLimit5h: amount(limits.0), rateLimit1d: amount(limits.1),
                rateLimit7d: amount(limits.2), createdAt: created)
}
private func json(_ data: Data) throws -> NSDictionary { try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary) }
private func json(_ text: String) throws -> NSDictionary { try json(Data(text.utf8)) }

@Test func createRequestMatchesSpecExample() throws {
    var draft = UserKeyDraft()
    draft.name = "  脚本 "
    draft.groupID = 3
    draft.quota = "50"
    draft.expiryChoice = .days30
    draft.ipWhitelist = " 198.51.100.0/24 \n\n"
    draft.rateLimit5h = "5"
    draft.rateLimit1d = "20"
    let request = try UserKeyForm.createRequest(draft)
    let expected = #"{"name":"脚本","group_id":3,"quota":50,"expires_in_days":30,"ip_whitelist":["198.51.100.0/24"],"ip_blacklist":[],"rate_limit_5h":5,"rate_limit_1d":20,"rate_limit_7d":0}"#
    #expect(try json(request.requestBody()) == json(expected))

    var plain = UserKeyDraft()
    plain.name = "默认"
    let body = try json(UserKeyForm.createRequest(plain).requestBody())
    #expect(body["group_id"] == nil && body["expires_in_days"] == nil)
    #expect(body["quota"] as? Int == 0)
    for (choice, days) in [(UserKeyExpiryChoice.days7, 7), (.days90, 90)] {
        plain.expiryChoice = choice
        #expect(UserKeyForm.expiresInDays(plain) == days)
    }
    plain.expiryChoice = .custom
    plain.customDays = "365"
    #expect(UserKeyForm.expiresInDays(plain) == 365)
    plain.expiryChoice = .never
    #expect(UserKeyForm.expiresInDays(plain) == nil)
    #expect(UserKeyExpiryChoice.allCases.map(\.title) == ["永久", "7 天", "30 天", "90 天", "自定义"])
}

@Test func issuesFollowFormOrder() {
    var draft = UserKeyDraft()
    draft.quota = "-1"
    draft.expiryChoice = .custom
    draft.customDays = "36501"
    draft.ipWhitelist = "10.0.0.1\n10.0.0.300"
    draft.ipBlacklist = "fe80::1%en0"
    draft.rateLimit7d = "1.123456789"
    let issues = UserKeyForm.issues(draft, editing: nil, zone: shanghai, now: now)
    #expect(issues.map(\.field) == [.name, .quota, .expiry, .ipWhitelist, .ipBlacklist, .rateLimit7d])
    #expect(issues.first?.message == "名称不能为空")
    #expect(issues.first { $0.field == .ipWhitelist }?.message == "第 2 行不是有效的 IP 或 CIDR")
    #expect(issues.first { $0.field == .ipBlacklist }?.message == "第 1 行不是有效的 IP 或 CIDR")
    #expect(issues.first { $0.field == .expiry }?.message == "自定义天数要填 1–36500 的整数")

    // The server stores the name escaped and refuses more than 100 bytes of that with a bare 500.
    var long = UserKeyDraft()
    long.name = String(repeating: "&", count: 21)
    #expect(UserKeyForm.issues(long, editing: nil, zone: shanghai, now: now).map(\.field) == [.name])
    long.name = String(repeating: "&", count: 20)
    #expect(UserKeyForm.issues(long, editing: nil, zone: shanghai, now: now).isEmpty)

    // Editing: a day already over is refused; empty amounts are 0.
    var edit = UserKeyDraft(editing: key())
    edit.editExpiry = .on(at("2026-10-25T02:00:00Z"))
    #expect(UserKeyForm.issues(edit, editing: key(), zone: shanghai, now: now).map(\.field) == [.expiry])
    edit.editExpiry = .on(now)
    #expect(UserKeyForm.issues(edit, editing: key(), zone: shanghai, now: now).isEmpty)
    // An expired key keeps its day without complaint while other fields change.
    let expired = key(expires: at("2026-10-20T02:00:00Z"))
    var renamed = UserKeyDraft(editing: expired)
    renamed.name = "新名"
    #expect(UserKeyForm.issues(renamed, editing: expired, zone: shanghai, now: now).isEmpty)
}

@Test func ipPatternsMatchGoParseRules() {
    for valid in ["1.2.3.4", "255.255.255.255", "0.0.0.0", "::1", "::", "1::", "2001:db8::8a2e:370:7334", "::ffff:1.2.3.4", "1:2:3:4:5:6:7:8",
                  "1:2:3:4:5:6:1.2.3.4", "198.51.100.0/24", "10.0.0.0/0", "10.0.0.0/32", "2001:db8::/32", "::/128", "FE80::1", "10.0.0.0/024"] {
        #expect(UserKeyForm.isValidIPPattern(valid), "\(valid)")
    }
    for invalid in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1.2.3.4/33", "2001:db8::/129", "fe80::1%en0", "1:2:3:4:5:6:7:8:9",
                    ":1:2:3:4:5:6:7", "1:::2", "1::2::3", "12345::1", "1.2.3.4/", "1.2.3.4/-1", "1.2.3.4/a", " 1.2.3.4", "1:2:3:4:5:6:7::8",
                    "::1.2.3", "1.2.3.4::"] {
        #expect(!UserKeyForm.isValidIPPattern(invalid), "\(invalid)")
    }
    #expect(UserKeyForm.ipLines("  1.2.3.4 \n\n\t10.0.0.0/8\r\n ") == ["1.2.3.4", "10.0.0.0/8"])
    #expect(UserKeyForm.ipLines(" \n ").isEmpty)
}

@Test func updateRequestSendsOnlyChangedFields() throws {
    let original = key(name: "a&amp;b", quota: "50", used: "10", expires: at("2030-12-31T04:00:00Z"), white: ["198.51.100.0/24"],
                       limits: ("5", "0", "0"))
    let draft = UserKeyDraft(editing: original)
    #expect(draft.name == "a&b" && draft.quota == "50" && draft.ipWhitelist == "198.51.100.0/24" && draft.rateLimit5h == "5" && draft.rateLimit1d == "")
    #expect(try UserKeyForm.updateRequest(draft, original: original, zone: shanghai) == nil)
    #expect(!UserKeyForm.hasChanges(draft, original: original))

    var renamed = draft
    renamed.name = " 脚本 "
    #expect(UserKeyForm.hasChanges(renamed, original: original))
    #expect(try json(#require(try UserKeyForm.updateRequest(renamed, original: original, zone: shanghai)).requestBody()) == json(#"{"name":"脚本"}"#))
    var spaced = draft
    spaced.name = "a&b  "
    #expect(UserKeyForm.hasChanges(spaced, original: original))
    #expect(try UserKeyForm.updateRequest(spaced, original: original, zone: shanghai) == nil)

    var same = draft
    same.quota = "50.00"
    #expect(try UserKeyForm.updateRequest(same, original: original, zone: shanghai) == nil)

    var cleared = draft
    cleared.quota = ""
    cleared.ipWhitelist = " \n"
    cleared.resetQuota = true
    cleared.editExpiry = .never
    let body = try json(#require(try UserKeyForm.updateRequest(cleared, original: original, zone: shanghai)).requestBody())
    #expect(body == (try json(#"{"quota":0,"ip_whitelist":[],"reset_quota":true,"expires_at":""}"#)))

    // A day on the server's calendar is sent as its 23:59:59; the key's own day is no change.
    var moved = draft
    moved.editExpiry = .on(at("2031-01-15T20:00:00Z"))
    let movedBody = try json(#require(try UserKeyForm.updateRequest(moved, original: original, zone: shanghai)).requestBody())
    #expect(movedBody["expires_at"] as? String == "2031-01-16T15:59:59Z")
    moved.editExpiry = .on(at("2030-12-31T10:00:00Z"))
    #expect(try UserKeyForm.updateRequest(moved, original: original, zone: shanghai) == nil)
    #expect(UserKeyForm.endOfDay(at("2026-10-26T17:30:00Z"), in: shanghai) == at("2026-10-27T15:59:59Z"))

    // Never expiring: picking a day sends it; 永久 sends nothing.
    let forever = key(quota: "0")
    var dated = UserKeyDraft(editing: forever)
    #expect(dated.editExpiry == .never)
    dated.editExpiry = .on(now)
    #expect(try json(#require(try UserKeyForm.updateRequest(dated, original: forever, zone: shanghai)).requestBody())["expires_at"] as? String
            == "2026-10-26T15:59:59Z")
    // 重置已用额度 only counts while the key has a quota.
    var reset = UserKeyDraft(editing: forever)
    reset.resetQuota = true
    #expect(try UserKeyForm.updateRequest(reset, original: forever, zone: shanghai) == nil)
}

@Test func undoAndReadbackAndEscaping() throws {
    let previous = AdminAPIKeyPrevious(name: "a&amp;b", status: "quota_exhausted", quota: 50, quotaUsed: 10, expiresAt: .never,
                                       ipWhitelist: [], rateLimit5h: 5)
    let undo = try #require(try UserKeyForm.undoRequest(previous: previous))
    #expect(try json(undo.requestBody()) == json(#"{"name":"a&b","quota":50,"expires_at":"","ip_whitelist":[],"rate_limit_5h":5}"#))
    let dated = try #require(try UserKeyForm.undoRequest(previous: AdminAPIKeyPrevious(expiresAt: .at(at("2030-12-31T04:00:00Z")))))
    #expect(try json(dated.requestBody())["expires_at"] as? String == "2030-12-31T04:00:00Z")
    #expect(try UserKeyForm.undoRequest(previous: AdminAPIKeyPrevious(status: "active", quotaUsed: 3)) == nil)

    #expect(UserKeyFormCopy.saved("脚本", resetQuota: false) == "已保存「脚本」")
    #expect(UserKeyFormCopy.saved("脚本", resetQuota: true) == "已保存「脚本」，已用额度的重置不能撤销")
    for name in ["a&b", "<x>", "it's", "say \"hi\"", "&amp;"] {
        #expect(UserKeyName.unescaped(UserKeyName.escaped(name)) == name)
    }
    #expect(UserKeyName.escaped("<a href='x'>&\"") == "&lt;a href=&#39;x&#39;&gt;&amp;&#34;")

    let sent = try AdminAPIKeyUpdateRequest(name: "a&b", quota: 0, expiresAt: .set(at("2031-01-16T15:59:59Z")), ipWhitelist: [])
    let server = key(name: "a&amp;b", quota: "0", expires: at("2031-01-16T15:59:59.400Z"), black: ["203.0.113.9"], limits: ("9", "0", "0"))
    #expect(UserKeyForm.readbackMatches(sent, server: server))
    #expect(!UserKeyForm.readbackMatches(sent, server: key(name: "旧名", quota: "0", expires: at("2031-01-16T15:59:59Z"))))
    #expect(!UserKeyForm.readbackMatches(sent, server: key(name: "a&amp;b", quota: "0", expires: at("2031-01-16T16:00:05Z"))))
    let reset = try AdminAPIKeyUpdateRequest(resetQuota: true, expiresAt: .clear)
    #expect(UserKeyForm.readbackMatches(reset, server: key()))
    #expect(!UserKeyForm.readbackMatches(reset, server: key(used: "1")))
    #expect(UserKeyForm.isRedactedPlaintext("***") && !UserKeyForm.isRedactedPlaintext("sk-ui-1") && !UserKeyForm.isRedactedPlaintext(""))
}

@Test func failureRevealAndRecovery() throws {
    func failure(_ status: Int, _ reason: String?, draft: UserKeyDraft? = nil) -> UserKeyFormCopy.Failure {
        UserKeyFormCopy.failure(.server(status: status, reason: reason), draft: draft)
    }
    #expect(failure(400, "API_KEY_NAME_REQUIRED") == .init(placement: .field(.name), message: "名称不能为空"))
    #expect(failure(400, "API_KEY_LIMIT_INVALID") == .init(placement: .field(.quota), message: "额度和速率限制必须是非负数"))
    #expect(failure(400, "API_KEY_EXPIRY_INVALID") == .init(placement: .field(.expiry), message: "有效期天数必须大于 0"))
    #expect(failure(400, "INVALID_IP_PATTERN").placement == .field(.ipWhitelist))
    var blacklisted = UserKeyDraft()
    blacklisted.ipWhitelist = "10.0.0.1"
    blacklisted.ipBlacklist = "10.0.0.300"
    #expect(failure(400, "INVALID_IP_PATTERN", draft: blacklisted) == .init(placement: .field(.ipBlacklist), message: "IP 或 CIDR 格式不对"))
    #expect(failure(400, "GROUP_NOT_ACTIVE") == .init(placement: .field(.group), message: "这个分组已停用"))
    #expect(failure(400, "SUBSCRIPTION_REQUIRED").placement == .field(.group))
    #expect(failure(404, "GROUP_NOT_FOUND") == .init(placement: .field(.group), message: "分组不存在"))
    #expect(failure(403, "API_KEY_COUNT_EXCEEDED") == .init(placement: .form, message: "这个用户的 Key 数量已达上限，请先删除不用的 Key"))
    #expect(failure(404, "USER_NOT_FOUND") == .init(placement: .form, message: "用户不存在或已删除"))
    #expect(failure(400, nil) == .init(placement: .form, message: "请求无效（错误码 HTTP 400）"))
    // The server's own words are never decoded, so none can reach the form.
    let refused = APIError.from(HTTPResponse(statusCode: 400, headers: [:],
                                             data: Data(#"{"code":400,"reason":"API_KEY_NAME_REQUIRED","message":"name must not be empty"}"#.utf8)))
    #expect(!UserKeyFormCopy.failure(refused).message.contains("must"))

    let security = { (enabled: Bool?, available: Bool?, totp: Bool?) in
        AdminMe.Security(totpEnabled: totp, stepUpEnabled: enabled, stepUpAvailable: available, stepUpGranted: false)
    }
    #expect(UserKeyReveal.availability(hasMaskedView: false, security: security(false, nil, nil), authMethod: .jwt) == .hidden)
    #expect(UserKeyReveal.availability(hasMaskedView: true, security: security(false, false, false), authMethod: .adminAPIKey) == .available)
    #expect(UserKeyReveal.availability(hasMaskedView: true, security: security(nil, nil, nil), authMethod: .adminAPIKey) == .available)
    #expect(UserKeyReveal.availability(hasMaskedView: true, security: security(true, true, true), authMethod: .jwt) == .available)
    #expect(UserKeyReveal.availability(hasMaskedView: true, security: security(true, false, true), authMethod: .adminAPIKey)
            == .disabled("Admin Key 登录不能查看完整 Key"))
    #expect(UserKeyReveal.availability(hasMaskedView: true, security: security(true, false, false), authMethod: .jwt)
            == .disabled("需要先在 Web 端开启二次验证"))

    let request = try AdminAPIKeyCreateRequest(name: "a&b")
    let started = now
    let keys = [key(id: 3, name: "a&amp;b", created: started.addingTimeInterval(-3_600)), key(id: 9, name: "a&amp;b", created: started.addingTimeInterval(-4)),
                key(id: 11, name: "a&amp;b", created: started.addingTimeInterval(2)), key(id: 12, name: "a&b2", created: started),
                key(id: 13, name: "a&amp;b", created: started.addingTimeInterval(1))]
    #expect(UserKeyCreateRecovery.match(in: keys, request: request, startedAt: started, knownIDs: [3, 13])?.id == 11)
    #expect(UserKeyCreateRecovery.match(in: Array(keys.prefix(1)), request: request, startedAt: started, knownIDs: []) == nil)
    #expect(UserKeyCreateRecovery.match(in: [key(id: 4, name: "a&amp;b", created: started.addingTimeInterval(-6))], request: request,
                                        startedAt: started, knownIDs: []) == nil)
}
