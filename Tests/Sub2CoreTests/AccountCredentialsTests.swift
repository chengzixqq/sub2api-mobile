import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let refreshedAccountJSON = #"{"id":42,"name":"凭据账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true}"#
/// 2026-10-24T08:00:00Z.
private let credentialNow = Date(timeIntervalSince1970: 1_792_828_800)
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

private func credentialClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func credentialAccount(status: String = "active", schedulable: Bool = true, _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":42,"name":"凭据账号","platform":"anthropic","type":"oauth","status":"\#(status)","schedulable":\#(schedulable)"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func refreshResult(_ fields: String = "", warning: String? = nil) throws -> AccountRefreshResult {
    AccountRefreshResult(account: try credentialAccount(fields), warning: warning)
}
private func keyedFailure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}
/// Model limits 09:00 and 09:30 on 2026-10-24 (UTC), both still running at `credentialNow`.
private let twoModelLimits = #""extra":{"model_rate_limits":{"claude-a":{"rate_limit_reset_at":"2026-10-24T09:00:00Z"},"claude-b":{"rate_limit_reset_at":"2026-10-24T09:30:00Z"}}}"#
private let oneModelLimit = #""extra":{"model_rate_limits":{"claude-a":{"rate_limit_reset_at":"2026-10-24T09:00:00Z"}}}"#

// MARK: - API Key preview and Base URL

@Test func apiKeyPreviewMasksKnownPrefixes() throws {
    let cases: [(String, String, Int)] = [
        ("sk-ant-api03-AbCdEfGh1234", "sk-ant-api03-••••1234", 25), ("sk-proj-abcdefWXYZ", "sk-proj-••••WXYZ", 18),
        ("  sk-test-9999  ", "sk-••••9999", 12), ("AIzaSyD-1234abcd", "AIza••••abcd", 16), ("xai-0123456789", "xai-••••6789", 14),
        ("AKIAIOSFODNN7EXAMPLE", "AKIA••••MPLE", 20), ("plainsecretvalue", "••••alue", 16), ("abc12345", "••••••••", 8)
    ]
    for (input, masked, count) in cases {
        let preview = try #require(APIKeyPreview(input))
        #expect(preview.masked == masked, "\(input)")
        #expect(preview.characterCount == count, "\(input)")
    }
    #expect(APIKeyPreview("sk-ant-api03-AbCdEfGh1234")?.text == "新密钥 sk-ant-api03-••••1234 · 25 个字符")
    #expect(APIKeyPreview("   ") == nil && APIKeyPreview("") == nil)
    #expect(APIKeyPreview.emptyText == "当前密钥已设置，不可查看")
    let values = Mirror(reflecting: try #require(APIKeyPreview("sk-proj-abcdefWXYZ"))).children.map { String(describing: $0.value) }
    #expect(!values.contains { $0.contains("abcdef") })
}

@Test func baseURLRuleValidatesPrefixAndMapsPatchValue() {
    #expect(BaseURLRule.validate("https://api.example.com") == .url("https://api.example.com"))
    #expect(BaseURLRule.validate("http://10.0.0.1:8080/v1") == .url("http://10.0.0.1:8080/v1"))
    #expect(BaseURLRule.validate(" https://relay.example.com/ ") == .url("https://relay.example.com/"))
    for bad in ["ftp://x.example.com", "https://", "https:///path", "api.example.com", "https:// spaced.example.com"] {
        #expect(BaseURLRule.validate(bad) == .invalid, "\(bad)")
    }
    #expect(BaseURLRule.validate("") == .officialDefault && BaseURLRule.validate("  ") == .officialDefault)
    #expect(BaseURLRule.invalidMessage == "地址要以 http:// 或 https:// 开头")
    #expect(BaseURLRule.Verdict.url("https://a.example.com").patchValue == .set(.string("https://a.example.com")))
    #expect(BaseURLRule.Verdict.officialDefault.patchValue == .delete && BaseURLRule.Verdict.invalid.patchValue == nil)
    #expect(BaseURLRule.requiresValue(platform: "antigravity", type: "apikey"))
    #expect(!BaseURLRule.requiresValue(platform: "anthropic", type: "apikey") && !BaseURLRule.requiresValue(platform: "antigravity", type: "oauth"))
    #expect(BaseURLRule.requiresValue(platform: "openai", type: "upstream") && BaseURLRule.requiresValue(platform: "antigravity", type: "upstream"))
    #expect(BaseURLRule.isUnchanged(.url("https://a.example.com"), current: " https://a.example.com "))
    #expect(BaseURLRule.isUnchanged(.officialDefault, current: nil) && BaseURLRule.isUnchanged(.officialDefault, current: " "))
    #expect(!BaseURLRule.isUnchanged(.officialDefault, current: "https://a.example.com"))
    #expect(!BaseURLRule.isUnchanged(.url("https://b.example.com"), current: "https://a.example.com") && !BaseURLRule.isUnchanged(.invalid, current: nil))
}

// MARK: - Refresh

@Test func keyedRefreshSendsOneKeyAndRetriesSameBytes() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(refreshedAccountJSON))])
    let key = UUID()
    let outcome = try await credentialClient(transport).refreshAccount(id: 42, idempotencyKey: key)
    #expect(outcome.value.account.id == 42 && outcome.value.warning == nil)
    let sent = await transport.requests
    #expect(sent.count == 2)
    for request in sent {
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/v1/admin/accounts/42/refresh")
        #expect(request.httpBody == Data("{}".utf8))
        #expect(sentHeader(request, "Idempotency-Key") == key.uuidString.lowercased())
        #expect(sentHeader(request, "X-Request-ID") == key.uuidString.lowercased())
        #expect(request.timeoutInterval == 65)
    }
    let failing = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let failure = await keyedFailure { _ = try await credentialClient(failing).refreshAccount(id: 42, idempotencyKey: UUID()) }
    #expect(failure?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(await failing.requests.count == 3)
}

@Test func unkeyedRefreshIsSentOnceWithoutIdempotencyKey() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(refreshedAccountJSON))])
    _ = try await credentialClient(transport).refreshAccount(id: 42, idempotencyKey: nil)
    let request = try #require(await transport.requests.first)
    #expect(sentHeader(request, "Idempotency-Key") == nil)
    let requestID = try #require(sentHeader(request, "X-Request-ID"))
    #expect(UUID(uuidString: requestID) != nil && requestID == requestID.lowercased())
    #expect(request.timeoutInterval == 30 && request.httpBody == Data("{}".utf8))
    let timedOut = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let lost = await thrownAPIError { _ = try await credentialClient(timedOut).refreshAccount(id: 42, idempotencyKey: nil) }
    #expect(lost?.kind == .transport)
    #expect(await timedOut.requests.count == 1)
    let gateway = ScriptedTransport(script: [.reply(errorReply(502))])
    #expect(await thrownAPIError { _ = try await credentialClient(gateway).refreshAccount(id: 42, idempotencyKey: nil) } != nil)
    #expect(await gateway.requests.count == 1)
}

@Test func refreshDecodesBareAccountAndWrappedWarning() async throws {
    let wrapped = #"{"account":\#(refreshedAccountJSON),"message":"Token refreshed successfully, but project_id could not be retrieved (will retry automatically)","warning":"missing_project_id_temporary"}"#
    let transport = ScriptedTransport(script: [.reply(okReply(refreshedAccountJSON)), .reply(okReply(wrapped, headers: ["X-Idempotency-Replayed": "true"]))])
    let client = credentialClient(transport)
    let bare = try await client.refreshAccount(id: 42, idempotencyKey: nil)
    #expect(bare.value.account.id == 42 && bare.value.warning == nil)
    let warned = try await client.refreshAccount(id: 42, idempotencyKey: UUID())
    #expect(warned.value.account.name == "凭据账号" && warned.value.warning == AccountRefreshResult.missingProjectIDWarning)
    #expect(warned.replayed)
    #expect(Mirror(reflecting: warned.value).children.compactMap(\.label) == ["account", "warning"])
}

@Test func refreshRejectsInvalidIDWithoutSending() async {
    let transport = ScriptedTransport(script: [.reply(okReply(refreshedAccountJSON))])
    let client = credentialClient(transport)
    #expect(await thrownAPIError { _ = try await client.refreshAccount(id: 0, idempotencyKey: UUID()) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.refreshAccount(id: -1, idempotencyKey: nil) }?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

// MARK: - Receipts and notes

@Test func refreshReceiptUsesServerZoneAndWarning() throws {
    let status = #""token_status":{"expires_at":"2026-10-24T08:30:00Z","refreshed_at":"2026-10-24T08:00:00Z"}"#
    #expect(AccountCredentialCopy.refreshReceipt(try refreshResult(status), timeZone: shanghai) == "已刷新令牌 · 新令牌 16:30 到期")
    #expect(AccountCredentialCopy.refreshReceipt(try refreshResult(status, warning: AccountRefreshResult.missingProjectIDWarning), timeZone: shanghai)
            == "已刷新令牌，project_id 暂未取到（会自动重试）")
    #expect(AccountCredentialCopy.refreshedWithoutProjectID == "已刷新令牌，project_id 暂未取到（会自动重试）")
    for legacy in [#""credentials":{"expires_at":1792830600}"#, #""credentials":{"expires_at":"1792830600"}"#,
                   #""credentials":{"expires_at":"2026-10-24T08:30:00Z"}"#] {
        #expect(AccountCredentialCopy.refreshReceipt(try refreshResult(legacy), timeZone: shanghai) == "已刷新令牌 · 新令牌 16:30 到期", "\(legacy)")
    }
    for unknown in [#""token_status":{"expires_at":null},"credentials":{"expires_at":1792830600}"#, #""credentials":{"expires_at":"garbage"}"#,
                    #""credentials":{"expires_at":9999999999999}"#, ""] {
        #expect(AccountCredentialCopy.refreshReceipt(try refreshResult(unknown), timeZone: shanghai) == "已刷新令牌", "\(unknown)")
    }
}

@Test func reauthorizeReceiptComparesBeforeAndAfter() throws {
    typealias Row = (before: UpstreamAccount, after: UpstreamAccount, switchedTo: OAuthAuthKind?, text: String, followUp: AccountCredentialReceipt.FollowUp)
    let normal = try credentialAccount(), paused = try credentialAccount(schedulable: false)
    let rows: [Row] = [
        (normal, normal, nil, "已重新授权 · 令牌已替换", .test),
        (try credentialAccount(status: "error"), normal, nil, "已重新授权 · 已清除错误 · 参与调度", .test),
        (try credentialAccount(status: "error", schedulable: false), paused, nil, "已重新授权 · 已清除错误 · 仍暂停调度", .enableScheduling),
        (try credentialAccount(#""rate_limit_reset_at":"2026-10-24T09:00:00Z","# + twoModelLimits), normal, nil,
         "已重新授权 · 已清除限流和 2 项模型限流 · 参与调度", .test),
        (try credentialAccount(status: "inactive"), normal, nil, "已重新授权 · 已启用账号 · 参与调度", .test),
        (try credentialAccount(status: "inactive", schedulable: false), paused, nil, "已重新授权 · 已启用账号 · 仍暂停调度", .enableScheduling),
        (normal, normal, .setupToken, "已重新授权 · 账号类型改为 Setup\u{00A0}Token · 令牌已替换", .test),
        (paused, paused, nil, "已重新授权 · 令牌已替换", .enableScheduling),
        (try credentialAccount(oneModelLimit), normal, nil, "已重新授权 · 已清除 1 项模型限流", .test),
        (try credentialAccount(schedulable: false, #""overload_until":"2026-10-24T09:00:00Z""#), paused, nil,
         "已重新授权 · 已清除过载 · 仍暂停调度", .enableScheduling),
        (try credentialAccount(#""temp_unschedulable_until":"2026-10-24T09:00:00Z""#), normal, nil, "已重新授权 · 已清除临时不可调度 · 参与调度", .test)
    ]
    for row in rows {
        let receipt = AccountCredentialCopy.reauthorizeReceipt(before: row.before, after: row.after, switchedTo: row.switchedTo, now: credentialNow)
        #expect(receipt.text == row.text)
        #expect(receipt.followUp == row.followUp, "\(row.text)")
    }
    #expect(AccountCredentialReceipt.FollowUp.test.title == "测试" && AccountCredentialReceipt.FollowUp.enableScheduling.title == "启用调度")
}

@Test func replaceTokenNoteCoversEveryBranch() throws {
    let tail = "站点不再使用旧令牌，不能撤回"
    func note(_ account: UpstreamAccount, _ switchedTo: OAuthAuthKind? = nil, faceID: Bool = false) -> String {
        AccountCredentialCopy.replaceTokenNote(account, switchedTo: switchedTo, verifiesWithFaceID: faceID, now: credentialNow)
    }
    let normal = try credentialAccount()
    #expect(note(normal) == "点按后立即保存新令牌；调度开关不变。" + tail)
    #expect(note(normal, faceID: true) == "点按后立即保存新令牌；调度开关不变。" + tail + "；之后验证 Face ID")
    #expect(note(normal, .setupToken) == "点按后立即保存新令牌，账号类型改为 Setup\u{00A0}Token；调度开关不变。" + tail)
    #expect(note(try credentialAccount(status: "inactive")) == "点按后立即保存新令牌，并重新启用账号；调度开关不变。" + tail)
    #expect(note(try credentialAccount(status: "error", schedulable: false))
            == "点按后立即保存新令牌，并清除错误；调度开关不变。出错时已停止调度，之后仍暂停。" + tail)
    let limited = try credentialAccount(schedulable: false, #""rate_limit_reset_at":"2026-10-24T09:00:00Z","# + twoModelLimits)
    #expect(note(limited) == "点按后立即保存新令牌，并清除限流和 2 项模型限流；调度开关不变。账号已停止调度，之后仍暂停。" + tail)
    #expect(note(try credentialAccount(oneModelLimit)) == "点按后立即保存新令牌，并清除 1 项模型限流；调度开关不变。" + tail)
    let expiredLimit = try credentialAccount(#""extra":{"model_rate_limits":{"claude-a":{"rate_limit_reset_at":"2026-10-24T07:00:00Z"}}}"#)
    #expect(note(expiredLimit) == "点按后立即保存新令牌；调度开关不变。" + tail)
}

// MARK: - Token timing and read-back

@Test func tokenReadbackComparesRefreshedAtWithStart() throws {
    let account = try credentialAccount(#""token_status":{"refreshed_at":"2026-10-24T08:00:05Z"}"#)
    let base = credentialNow.timeIntervalSince1970
    #expect(AccountTokenReadback.clockSlack == 2)
    #expect(AccountTokenReadback.check(account, since: Date(timeIntervalSince1970: base + 5.7)) == .replaced) // saved within the same second
    #expect(AccountTokenReadback.check(account, since: Date(timeIntervalSince1970: base + 7.2)) == .replaced)
    #expect(AccountTokenReadback.check(account, since: Date(timeIntervalSince1970: base + 8)) == .notReplaced)
    // Newer than the value read before the write, even when the server clock is far behind ours.
    let before = Date(timeIntervalSince1970: base - 60)
    #expect(AccountTokenReadback.check(account, since: Date(timeIntervalSince1970: base + 60), previousRefreshedAt: before) == .replaced)
    let same = Date(timeIntervalSince1970: base + 5)
    #expect(AccountTokenReadback.check(account, since: Date(timeIntervalSince1970: base + 60), previousRefreshedAt: same) == .notReplaced)
    #expect(AccountTokenReadback.check(try credentialAccount(#""token_status":{"refreshed_at":null}"#), since: credentialNow) == .notReplaced)
    #expect(AccountTokenReadback.check(try credentialAccount(), since: credentialNow) == .unknown)
    #expect(AccountWriteCheck.tokenReplaced(account, since: Date(timeIntervalSince1970: base + 5.7)) == .replaced)
    #expect(AccountWriteCheck.tokenReplaced(account, since: Date(timeIntervalSince1970: base + 60), previousRefreshedAt: before) == .replaced)
}

@Test func tokenTimingPrefersTokenStatusAndFallsBackToCredentials() throws {
    let target = Date(timeIntervalSince1970: 1_792_830_600)
    let both = try credentialAccount(#""token_status":{"expires_at":"2026-10-24T08:30:00Z"},"credentials":{"expires_at":1800000000}"#)
    #expect(AccountTokenTiming.expiresAt(both) == target)
    for legacy in ["1792830600", #""1792830600""#, #""2026-10-24T08:30:00Z""#] {
        #expect(AccountTokenTiming.expiresAt(try credentialAccount(#""credentials":{"expires_at":\#(legacy)}"#)) == target, "\(legacy)")
    }
    for bad in [#""garbage""#, "0", "9999999999999"] {
        #expect(AccountTokenTiming.expiresAt(try credentialAccount(#""credentials":{"expires_at":\#(bad)}"#)) == nil, "\(bad)")
    }
    let refreshed = try credentialAccount(#""token_status":{"refreshed_at":"2026-10-24T08:00:05Z"}"#)
    #expect(AccountTokenTiming.refreshedAt(refreshed) == credentialNow.addingTimeInterval(5))
    #expect(AccountTokenTiming.refreshedAt(try credentialAccount()) == nil)
}
