import Foundation
import Testing
@testable import Sub2Core

private func decodeKey(_ json: String) throws -> AdminAPIKey { try JSONDecoder().decode(AdminAPIKey.self, from: Data(json.utf8)) }
private func utc(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
/// Every string a value shows to printing, debugging, dump and reflection.
private func everythingPrinted(_ value: Any) -> String {
    func reflected(_ value: Any) -> [String] {
        Mirror(reflecting: value).children.flatMap { child -> [String] in
            if let text = child.value as? String { return [text] }
            return reflected(child.value)
        }
    }
    var dumped = ""
    dump(value, to: &dumped)
    return ([String(describing: value), String(reflecting: value), dumped] + reflected(value)).joined(separator: "\n")
}

@Test func adminAPIKeyDecodesEveryMaskedListField() throws {
    let key = try decodeKey(#"""
    {"id":4087,"user_id":10,"key":"","key_masked":"sk-…3f9a","name":"脚本","group_id":3,"status":"active","effective_status":"quota_exhausted",
     "ip_whitelist":["198.51.100.0/24"],"ip_blacklist":["203.0.113.9","203.0.113.10"],"last_used_at":"2026-10-20T08:00:00Z",
     "last_used_ip":"198.51.100.7","quota":"50.00000001","quota_used":12.3,"expires_at":"2026-12-31T15:59:59Z","current_concurrency":2,
     "rate_limit_5h":5,"rate_limit_1d":"20","rate_limit_7d":0,"usage_5h":2.1,"usage_1d":3,"usage_7d":0,
     "window_5h_start":"2026-10-20T06:00:00Z","reset_5h_at":"2026-10-20T19:20:00.123+08:00","reset_7d_at":"2026-10-27T00:00:00Z",
     "created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-15T08:00:00Z","group":{"id":3,"name":"默认组"},
     "user":{"id":10,"email":"ops@studio-k.example","username":"Studio-K 团队","status":"disabled","balance":"1020","role":"user"}}
    """#)
    #expect(key.id == 4087 && key.userID == 10 && key.keyMasked == "sk-…3f9a" && !key.isTombstone)
    #expect(key.name == "脚本" && key.groupID == 3 && key.status == "active" && key.effectiveStatus == "quota_exhausted")
    #expect(key.ipWhitelist == ["198.51.100.0/24"] && key.ipBlacklist == ["203.0.113.9", "203.0.113.10"])
    #expect(key.lastUsedAt == utc("2026-10-20T08:00:00Z") && key.lastUsedIP == "198.51.100.7")
    #expect(key.quota == Decimal(string: "50.00000001") && key.quotaUsed == Decimal(string: "12.3"))
    #expect(key.expiresAt == utc("2026-12-31T15:59:59Z") && key.currentConcurrency == 2)
    #expect(key.rateLimit5h == 5 && key.rateLimit1d == 20 && key.rateLimit7d == 0)
    #expect(key.usage5h == Decimal(string: "2.1") && key.usage1d == 3 && key.usage7d == 0)
    #expect(key.reset5hAt == utc("2026-10-20T11:20:00.123Z") && key.reset1dAt == nil && key.reset7dAt == utc("2026-10-27T00:00:00Z"))
    #expect(key.createdAt == utc("2026-10-01T00:00:00Z") && key.updatedAt == utc("2026-10-15T08:00:00Z"))
    #expect(key.user == AdminUserSummary(id: 10, email: "ops@studio-k.example", username: "Studio-K 团队", status: "disabled"))
}

@Test func adminAPIKeyDropsPlaintextKey() throws {
    let key = try decodeKey(#"{"id":9,"key":"sk-live-SECRET-0123456789","key_masked":"sk-…6789","name":"脚本","status":"active"}"#)
    #expect(key.keyMasked == "sk-…6789")
    #expect(!everythingPrinted(key).contains("SECRET"))
    let page = try JSONDecoder().decode(Page<AdminAPIKey>.self, from: Data(#"""
    {"items":[{"id":9,"key":"sk-live-SECRET-0123456789","key_masked":"sk-…6789"}],"total":1,"page":1,"page_size":100}
    """#.utf8))
    #expect(!everythingPrinted(page).contains("SECRET"))
}

@Test func adminAPIKeyDerivesMaskWithoutKeyMasked() throws {
    let legacy = try decodeKey(#"{"id":1,"key":"sk-abcdefgh1234"}"#)
    #expect(legacy.keyMasked == "sk-…1234" && !legacy.isTombstone)
    #expect(try decodeKey(#"{"id":1,"key":"sk-abcdefgh1234","key_masked":null}"#).keyMasked == "sk-…1234")
    #expect(try decodeKey(#"{"id":1,"key":"abcdefg"}"#).keyMasked == "…")
    #expect(try decodeKey(#"{"id":1,"key":"abcdefgh"}"#).keyMasked == "abc…efgh")
    for raw in ["__deleted__x", ""] {
        let tombstone = try decodeKey(#"{"id":1,"key":"\#(raw)"}"#)
        #expect(tombstone.keyMasked == "" && tombstone.isTombstone, "\(raw)")
    }
    #expect(try decodeKey(#"{"id":1,"key":"密钥甲乙丙丁戊己庚"}"#).keyMasked == "密钥甲…丁戊己庚")
    #expect(AdminAPIKey.localMask("密钥甲乙丙丁戊己庚") == "密钥甲…丁戊己庚")
    for secret in ["sk-abcdefgh1234", "密钥甲乙丙丁戊己庚"] {
        let printed = everythingPrinted(try decodeKey(#"{"id":1,"key":"\#(secret)"}"#))
        #expect(!printed.contains(secret) && !printed.contains("abcdefgh") && !printed.contains("乙丙"))
    }
    let bare = try decodeKey(#"{"id":1}"#)
    #expect(bare.keyMasked == nil && !bare.isTombstone)
    #expect(try decodeKey(#"{"id":1,"key_masked":""}"#).isTombstone)
}

@Test func adminAPIKeyToleratesMissingFields() throws {
    let key = try decodeKey(#"{"id":7}"#)
    #expect(key.name == "" && key.status == "" && key.userID == nil)
    #expect(key.quota == 0 && key.quotaUsed == 0 && key.rateLimit5h == 0 && key.rateLimit1d == 0 && key.rateLimit7d == 0)
    #expect(key.usage5h == 0 && key.usage1d == 0 && key.usage7d == 0)
    #expect(key.ipWhitelist.isEmpty && key.ipBlacklist.isEmpty)
    #expect(key.groupID == nil && key.effectiveStatus == nil && key.currentConcurrency == nil && key.expiresAt == nil && key.user == nil)
    #expect(key.lastUsedAt == nil && key.lastUsedIP == nil && key.createdAt == nil && key.updatedAt == nil)
    let nulls = try decodeKey(#"""
    {"id":7,"group_id":null,"ip_whitelist":null,"ip_blacklist":null,"last_used_ip":null,"quota":null,"expires_at":"not a time",
     "last_used_at":"2026-13-40","effective_status":null,"current_concurrency":null,"user":"broken"}
    """#)
    #expect(nulls.groupID == nil && nulls.ipWhitelist.isEmpty && nulls.ipBlacklist.isEmpty && nulls.lastUsedIP == nil && nulls.quota == 0)
    #expect(nulls.expiresAt == nil && nulls.lastUsedAt == nil && nulls.user == nil)
    #expect(throws: (any Error).self) { try decodeKey(#"{"id":7,"quota":"abc"}"#) }
    #expect(throws: (any Error).self) { try decodeKey(#"{"id":7,"usage_1d":"x"}"#) }
    #expect(throws: (any Error).self) { try decodeKey(#"{"name":"没有编号"}"#) }
}

@Test func adminAPIKeyKeepsDecimalStringsAndNumbers() throws {
    let key = try decodeKey(#"{"id":1,"name":"test","key":null,"status":"active","quota":"100.00000001","quota_used":1.2}"#)
    #expect(key.quota == Decimal(string: "100.00000001"))
    #expect(key.quotaUsed == Decimal(string: "1.2"))
}

@Test func adminAPIKeyStatusUsesEffectiveStatusThenLocalFallback() throws {
    let now = utc("2026-10-20T00:00:00Z")
    #expect(try decodeKey(#"{"id":1,"status":"active","effective_status":"expired"}"#).status(now: now) == .expired)
    #expect(try decodeKey(#"{"id":1,"status":"active","expires_at":"2026-10-19T00:00:00Z"}"#).status(now: now) == .expired)
    #expect(try decodeKey(#"{"id":1,"status":"active","quota":10,"quota_used":10}"#).status(now: now) == .quotaExhausted)
    #expect(try decodeKey(#"{"id":1,"status":"disabled"}"#).status(now: now) == .inactive)
    #expect(try decodeKey(#"{"id":1,"status":"active","effective_status":"paused","quota":10,"quota_used":11}"#).status(now: now) == .quotaExhausted)
    #expect(try decodeKey(#"{"id":1,"status":"active","quota":0,"quota_used":11}"#).status(now: now) == .active)
}

@Test func adminAPIKeyPageEnvelopeDecodes() throws {
    let page = try JSONDecoder().decode(Page<AdminAPIKey>.self, from: Data(#"""
    {"items":[{"id":1,"key_masked":"sk-…aaaa","name":"一"},{"id":2,"key_masked":"","name":"墓碑"}],"total":41,"page":1,"page_size":20,"pages":3}
    """#.utf8))
    #expect(page.items.map(\.id) == [1, 2] && page.items.map(\.isTombstone) == [false, true])
    #expect(page.total == 41 && page.hasMore)
}

/// S3D1-12: the server stores `html.EscapeString(name)`; pages show the unescaped name.
@Test func keyNameEscapingRoundTrips() throws {
    #expect(UserKeyName.escaped(#"A&B <x> 'q' "w""#) == "A&amp;B &lt;x&gt; &#39;q&#39; &#34;w&#34;")
    for name in [#"A&B <x> 'q' "w""#, "&amp;", "普通名称", "", "&&;;", "<\u{338}"] {
        #expect(UserKeyName.unescaped(UserKeyName.escaped(name)) == name, "\(name)")
    }
    #expect(UserKeyName.unescaped("A&amp;B") == "A&B")
    #expect(UserKeyName.unescaped("&lt;x&gt;") == "<x>")
    #expect(UserKeyName.unescaped("&#39;单&#39; &#34;双&#34;") == #"'单' "双""#)
    #expect(UserKeyName.unescaped("a&nbsp;b &copy; &") == "a&nbsp;b &copy; &")
    #expect(UserKeyName.unescaped("&amp;lt;") == "&lt;")
    let key = try decodeKey(#"{"id":1,"name":"A&amp;B &lt;脚本&gt;"}"#)
    #expect(key.name == "A&amp;B &lt;脚本&gt;" && key.displayName == "A&B <脚本>")
}
