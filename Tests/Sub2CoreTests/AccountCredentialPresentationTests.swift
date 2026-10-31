import Foundation
import Testing
@testable import Sub2Core

/// 2026-10-24T08:00:00Z, 16:00 in Shanghai.
private let rowNow = Date(timeIntervalSince1970: 1_792_828_800)
private let shanghaiZone = TimeZone(identifier: "Asia/Shanghai")!
private let utcZone = TimeZone(identifier: "UTC")!

private func wireAccount(platform: String = "openai", type: String = "apikey", status: String = "active", schedulable: Bool = true,
                         _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":7,"name":"OpenAI-备用-A","platform":"\#(platform)","type":"\#(type)","status":"\#(status)","schedulable":\#(schedulable)"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func tokenAccount(expiresIn seconds: TimeInterval?, autoRefresh: Bool? = true) -> UpstreamAccount {
    let status = seconds.map { AccountTokenStatus(expiresAt: ServerTime.utcTimestamp(rowNow.addingTimeInterval($0)), lifetimeSeconds: 28_800,
                                                  autoRefresh: autoRefresh) }
    return UpstreamAccount(id: 1, name: "Claude-官方-01", platform: "anthropic", type: "oauth", tokenStatus: status)
}
private func body(_ change: AccountEditChange?) throws -> String {
    String(decoding: try #require(change).request.requestBody(), as: UTF8.self)
}

// MARK: - Kind, menu and footers

@Test func credentialKindFollowsAccountType() throws {
    let catalog = MetaCatalog.builtin
    #expect(AccountCredentialKind.of(try wireAccount(platform: "anthropic", type: "oauth"), catalog: catalog) == .token)
    #expect(AccountCredentialKind.of(try wireAccount(platform: "anthropic", type: "setup-token"), catalog: catalog) == .token)
    #expect(AccountCredentialKind.of(try wireAccount(), catalog: catalog) == .key(.optional))
    #expect(AccountCredentialKind.of(try wireAccount(platform: "antigravity"), catalog: catalog) == .key(.required))
    #expect(AccountCredentialKind.of(try wireAccount(platform: "anthropic", type: "upstream"), catalog: catalog) == .key(.required))
    #expect(AccountCredentialKind.of(try wireAccount(platform: "anthropic", type: "bedrock"), catalog: catalog) == .webOnly)
    #expect(AccountCredentialKind.of(try wireAccount(platform: "gemini", type: "service_account"), catalog: catalog) == .webOnly)
    // S2D1-22: a multi-protocol platform's endpoints are edited on the Web.
    #expect(AccountCredentialKind.of(try wireAccount(platform: "zhipu"), catalog: catalog) == .key(.inWeb))
    #expect(AccountCredentialKind.of(try wireAccount(platform: "kimi"), catalog: catalog) == .key(.inWeb))
}

@Test func credentialMenuActionsAndFooters() {
    #expect(AccountCredentialKind.key(.optional).menuActions == [.replaceKey])
    #expect(AccountCredentialKind.key(.inWeb).menuActions == [.replaceKey])
    #expect(AccountCredentialKind.token.menuActions == [.refresh, .reauthorize])
    #expect(AccountCredentialMenuAction.reauthorize.title == "重新授权…" && AccountCredentialMenuAction.reauthorize.systemImage == "key")
    #expect(AccountCredentialKind.webOnly.menuActions.isEmpty)
    #expect(AccountCredentialMenuAction.replaceKey.title == "更换 API Key…")
    #expect(AccountCredentialMenuAction.refresh.title == "刷新令牌")
    #expect(AccountCredentialKind.key(.required).footer
            == "已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。")
    #expect(AccountCredentialKind.token.footer
            == "令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。")
    #expect(AccountCredentialKind.webOnly.footer == "已保存的凭据不可查看；这类凭据请在 Web 中更换。")
    #expect(AccountCredentialPresentation.immediate == "立即生效")
}

// MARK: - API Key row

@Test func keyRowValueVariants() throws {
    let stored = try wireAccount(#""credentials":{},"credentials_status":{"has_api_key":true}"#)
    let plain = AccountCredentialPresentation.keyRow(stored, replacedAt: nil, now: rowNow, timeZone: shanghaiZone)
    #expect(plain.value == "已设置 · 不可查看" && !plain.isReplaced && plain.hint == nil)
    let replacedAt = try #require(ServerTime.parseTimestamp("2026-10-24T02:42:00Z"))
    let replaced = AccountCredentialPresentation.keyRow(stored, replacedAt: replacedAt, now: rowNow, timeZone: shanghaiZone)
    #expect(replaced.value == "已更换 · 10:42" && replaced.isReplaced)
    #expect(AccountCredentialPresentation.keyRow(stored, replacedAt: replacedAt, now: rowNow, timeZone: utcZone).value == "已更换 · 02:42")
    // credentials_status is omitempty: no secret at all leaves it out.
    #expect(AccountCredentialPresentation.keyRow(try wireAccount(#""credentials":{}"#), replacedAt: nil, now: rowNow, timeZone: utcZone).value == "未设置")
    // The list's lite copy carries no credentials yet.
    #expect(AccountCredentialPresentation.keyRow(try wireAccount(), replacedAt: nil, now: rowNow, timeZone: utcZone).value == "—")
}

@Test func keyRowHintForCredentialError() throws {
    let rejected = try wireAccount(status: "error", schedulable: false, #""error_kind":"auth","error_status_code":401,"credentials":{}"#)
    let row = AccountCredentialPresentation.keyRow(rejected, replacedAt: nil, now: rowNow, timeZone: utcZone)
    #expect(row.hint == .rejected(statusCode: 401))
    #expect(row.hint?.text == "上游拒绝了这个密钥（401），需要更换")
    #expect(row.hint?.tone == .critical)
    // R12: the code comes from error_status_code only, never from the message.
    let forbidden = try wireAccount(status: "error", #""error_kind":"forbidden","error_message":"403 forbidden","credentials":{}"#)
    #expect(AccountCredentialPresentation.keyRow(forbidden, replacedAt: nil, now: rowNow, timeZone: utcZone).hint?.text == "上游拒绝了这个密钥，需要更换")
    let quota = try wireAccount(status: "error", #""error_kind":"quota","credentials":{}"#)
    #expect(AccountCredentialPresentation.keyRow(quota, replacedAt: nil, now: rowNow, timeZone: utcZone).hint == nil)
    #expect(AccountCredentialPresentation.keyRow(try wireAccount(#""credentials":{}"#), replacedAt: nil, now: rowNow, timeZone: utcZone).hint == nil)
}

@Test func keyRowHintAfterReplacement() throws {
    let paused = try wireAccount(status: "error", schedulable: false, #""error_kind":"auth","error_status_code":401,"credentials":{}"#)
    let waiting = AccountCredentialPresentation.keyRow(paused, replacedAt: rowNow, now: rowNow, timeZone: utcZone)
    #expect(waiting.hint == .awaitingTest(stillPaused: true))
    #expect(waiting.hint?.text == "已更换：测试连接通过后自动清除错误（仍暂停调度）")
    #expect(waiting.hint?.tone == .neutral)
    let scheduling = try wireAccount(status: "error", #""error_kind":"auth","credentials":{}"#)
    #expect(AccountCredentialPresentation.keyRow(scheduling, replacedAt: rowNow, now: rowNow, timeZone: utcZone).hint?.text
            == "已更换：测试连接通过后自动清除错误")
    let healthy = AccountCredentialPresentation.keyRow(try wireAccount(#""credentials":{}"#), replacedAt: rowNow, now: rowNow, timeZone: utcZone)
    #expect(healthy.hint == nil && healthy.value == "已更换 · 08:00")
}

// MARK: - Base URL row

@Test func baseURLValueVariants() throws {
    let custom = AccountCredentialPresentation.baseURL(try wireAccount(#""credentials":{"base_url":"https://relay.example.com/v1/"}"#))
    #expect(custom == .custom("https://relay.example.com/v1/") && custom.text == "https://relay.example.com/v1/")
    #expect(AccountCredentialPresentation.baseURL(try wireAccount(#""credentials":{"base_url":"  https://a.example.com \n"}"#)) == .custom("https://a.example.com"))
    for fields in [#""credentials":{}"#, #""credentials":{"base_url":""}"#, #""credentials":{"base_url":"   "}"#, #""credentials":{"base_url":null}"#] {
        let value = AccountCredentialPresentation.baseURL(try wireAccount(fields))
        #expect(value == .official && value.text == "官方地址", "\(fields)")
    }
    let unknown = AccountCredentialPresentation.baseURL(try wireAccount())
    #expect(unknown == .unknown && unknown.text == "—")
}

// MARK: - Access token row

@Test func tokenRowBadgesAndText() {
    let cases: [(TimeInterval, AccountTokenRow.Badge, String)] = [
        (28_800, .valid, "8 小时后（到期 00:00）"),
        (28_740, .valid, "8 小时后（到期 23:59）"),
        (3_600, .valid, "1 小时后（到期 17:00）"),
        (3_599, .expiring, "60 分钟后（到期 16:59）"),
        (61, .expiring, "2 分钟后（到期 16:01）"),
        (1, .expiring, "1 分钟后（到期 16:00）"),
        (0, .expired, "已过期（到期 16:00）"),
        (-300, .expired, "已过期（到期 15:55）"),
        (30 * 86_400, .valid, "30 天后（到期 2026-11-23 16:00）"),
        (-2 * 86_400, .expired, "已过期（到期 2026-10-22 16:00）")
    ]
    for (left, badge, text) in cases {
        let row = AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: left), now: rowNow, timeZone: shanghaiZone)
        #expect(row.badge == badge, "\(left)")
        #expect(row.text == text, "\(left)")
    }
    #expect(AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: 28_800), now: rowNow, timeZone: utcZone).text == "8 小时后（到期 16:00）")
    #expect(AccountTokenRow.Badge.valid.title == "有效" && AccountTokenRow.Badge.valid.tone == .ok)
    #expect(AccountTokenRow.Badge.expiring.title == "即将到期" && AccountTokenRow.Badge.expiring.tone == .caution)
    #expect(AccountTokenRow.Badge.expired.title == "已过期" && AccountTokenRow.Badge.expired.tone == .critical)
}

@Test func tokenRowFallsBackToCredentialsAndUnknown() throws {
    // Without accounts.token_status the old credentials.expires_at (Unix seconds) is read.
    let legacy = try wireAccount(platform: "anthropic", type: "oauth", #""credentials":{"expires_at":"1792857600"}"#)
    #expect(AccountCredentialPresentation.tokenRow(legacy, now: rowNow, timeZone: utcZone).text == "8 小时后（到期 16:00）")
    let unknown = AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: nil), now: rowNow, timeZone: utcZone)
    #expect(unknown.badge == nil && unknown.text == "—" && unknown.note == nil)
}

@Test func tokenRowSaysWhenItWillNotRefreshItself() {
    #expect(AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: 2_400, autoRefresh: false), now: rowNow, timeZone: utcZone).note == "不会自动刷新")
    #expect(AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: 2_400, autoRefresh: true), now: rowNow, timeZone: utcZone).note == nil)
    #expect(AccountCredentialPresentation.tokenRow(tokenAccount(expiresIn: 2_400, autoRefresh: nil), now: rowNow, timeZone: utcZone).note == nil)
}

@Test func webOnlyCredentialValue() throws {
    let bedrock = try wireAccount(type: "bedrock", #""credentials":{"region":"us-east-1"},"credentials_status":{"has_aws_secret_access_key":true}"#)
    #expect(AccountCredentialPresentation.storedSecret(bedrock) == "已设置 · 不可查看")
    #expect(AccountCredentialPresentation.storedSecret(try wireAccount(type: "bedrock", #""credentials":{}"#)) == "未设置")
    #expect(AccountCredentialPresentation.storedSecret(try wireAccount(type: "bedrock")) == "—")
}

// MARK: - Sheets

@Test func keySheetCopyAndRequestBody() throws {
    #expect(AccountKeySheetCopy.target(name: "OpenAI-备用-A") == "OpenAI-备用-A · 点按底部按钮后立即生效")
    #expect(AccountKeySheetCopy.footer(verifiesFaceID: false) == "站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销")
    #expect(AccountKeySheetCopy.footer(verifiesFaceID: true) == "站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销。点按后验证 Face ID")
    let change = try #require(AccountKeySheetCopy.change(forKey: "  sk-test-0001\n"))
    #expect(try body(change) == #"{"credentials_patch":{"api_key":"sk-test-0001"}}"#)
    #expect(change.fieldNames == ["API Key"] && change.undo == nil)
    #expect(!String(describing: change).contains("sk-test-0001"))
    #expect(AccountKeySheetCopy.change(forKey: "") == nil && AccountKeySheetCopy.change(forKey: " \n ") == nil)
}

@Test func baseURLDraftTable() throws {
    let account = try wireAccount(#""credentials":{"base_url":"https://a.example.com"}"#)
    var draft = AccountBaseURLDraft(account: account)
    #expect(draft.text == "https://a.example.com" && !draft.isChanged && !draft.canSubmit && draft.change == nil)
    #expect(draft.submitTitle == "保存 Base URL" && draft.note == "请求改发到这个地址" && draft.error == nil)
    draft.text = "relay.example.com"
    #expect(draft.error == "地址要以 http:// 或 https:// 开头" && draft.note == draft.error && !draft.canSubmit)
    draft.text = "https://b.example.com/v1"
    #expect(draft.canSubmit && draft.receipt == "已保存 Base URL" && draft.note == "请求改发到这个地址")
    // JSONEncoder escapes the slashes; the server reads the same string.
    #expect(try body(draft.change) == #"{"credentials_patch":{"base_url":"https:\/\/b.example.com\/v1"}}"#)
    #expect(draft.change?.fieldNames == ["Base URL"] && draft.change?.undo == nil)
    draft.text = ""
    #expect(draft.isRestore && draft.submitTitle == "改回官方地址" && draft.receipt == "已改回官方地址" && draft.note == "留空：使用官方地址")
    #expect(try body(draft.change) == #"{"credentials_patch":{"base_url":null}}"#)
    draft.text = "  https://a.example.com "
    #expect(!draft.isChanged && !draft.canSubmit)

    var official = AccountBaseURLDraft(account: try wireAccount(#""credentials":{}"#))
    #expect(official.text.isEmpty && !official.isChanged && !official.canSubmit && !official.isRestore)
    official.text = "https://c.example.com"
    #expect(official.canSubmit && official.submitTitle == "保存 Base URL")

    var upstream = AccountBaseURLDraft(account: try wireAccount(platform: "antigravity", #""credentials":{"base_url":"https://up.example.com"}"#))
    upstream.text = ""
    #expect(upstream.error == "对接上游需要填写 Base URL" && !upstream.isRestore && !upstream.canSubmit && upstream.submitTitle == "保存 Base URL")
}

// MARK: - 刷新令牌

@Test func refreshFailureCopy() {
    #expect(AccountRefreshCopy.failed(reason: "站点暂时不可用") == "刷新令牌没有成功：站点暂时不可用")
    #expect(AccountRefreshCopy.reason(for: APIError.server(status: 400, reason: "SPARK_SHADOW_NO_REFRESH")) == "影子账号的凭据跟随母账号，请刷新母账号的令牌")
    // The refresh endpoint's 404 carries no reason.
    for error in [APIError.server(status: 404, reason: nil), APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND")] {
        #expect(AccountRefreshCopy.isMissing(error))
        #expect(AccountRefreshCopy.reason(for: error) == "这个账号已删除或不在本工作区")
    }
    #expect(!AccountRefreshCopy.isMissing(APIError.server(status: 404, envelope: nil)))
    #expect(!AccountRefreshCopy.isMissing(APIError(kind: .transport, message: "无法连接站点")))
    #expect(AccountRefreshCopy.reason(for: APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")) == AccountActionCopy.readOnly.text)
    #expect(AccountRefreshCopy.notApplied == "刷新令牌没有生效，可以重试")
    #expect(AccountRefreshCopy.unconfirmedRetry == "刷新令牌结果未确认，可用同一编号重试")
}
