import Foundation
import Testing
@testable import Sub2Core

private func account(_ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":4,"name":"主力","platform":"anthropic","type":"apikey","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func server(_ status: Int, _ reason: String?, metadata: [String: String] = [:]) -> APIError {
    APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata))
}
private func body(_ request: AccountPatchRequest) throws -> String { String(decoding: try request.requestBody(), as: UTF8.self) }
private let unconfirmed = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)

// MARK: - 错误分类

@Test func versionConflictCarriesCurrentETag() {
    #expect(AccountPatchFailure(server(412, "ACCOUNT_VERSION_CONFLICT", metadata: ["current_etag": "\"cv-8\""]))
            == .versionConflict(currentETag: "\"cv-8\""))
    #expect(AccountPatchFailure(server(412, "ACCOUNT_VERSION_CONFLICT")) == .versionConflict(currentETag: nil))
}

@Test func mixedChannelReadsMetadataAndWebText() throws {
    let metadata = ["group_id": "1", "group_name": "高级组", "current_platform": "Anthropic", "other_platform": "Antigravity"]
    guard case .mixedChannel(let warning?) = AccountPatchFailure(server(409, "MIXED_CHANNEL_WARNING", metadata: metadata)) else {
        Issue.record("expected a warning"); return
    }
    #expect(warning.message.hasPrefix("警告：分组“高级组”中同时包含 Anthropic 和 Antigravity 账号。"))
    #expect(AccountPatchFailure(server(409, "MIXED_CHANNEL_WARNING")) == .mixedChannel(nil))
    let check = MixedChannelCheck(hasRisk: true, details: .init(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic", otherPlatform: "Antigravity"))
    #expect(MixedChannelWarning(check: check) == warning)
}

@Test(arguments: ["INVALID_IF_MATCH", "INVALID_PATCH", "CREDENTIAL_KEY_NOT_DELETABLE"])
func patchContractRefusalsAreRejectedWithReason(_ reason: String) {
    #expect(AccountPatchFailure(server(400, reason)) == .rejected(reason: reason))
}

@Test func otherBadRequestsUseCatalogText() {
    #expect(AccountEditCopy.rejected(reason: "INVALID_PATCH") == "服务器拒绝了这次修改（INVALID_PATCH）")
    for error in [server(400, "VALIDATION_ERROR"), server(400, nil)] {
        #expect(AccountPatchFailure(error) == .refused(error.localizedDescription))
    }
}

@Test func accountNotFoundIsRemovedButGroupNotFoundIsNot() {
    #expect(AccountPatchFailure(server(404, "ACCOUNT_NOT_FOUND")) == .removed)
    let group = server(404, "GROUP_NOT_FOUND")
    #expect(AccountPatchFailure(group) == .refused(group.localizedDescription))
}

@Test func unknownResultsNeedReadback() {
    let errors: [any Error] = [
        APIError(kind: .transport, message: "连接超时"), APIError.invalidResponse,
        server(408, nil), server(502, nil), server(504, nil), server(503, nil), server(503, "SERVICE_UNAVAILABLE"), unconfirmed
    ]
    for error in errors { #expect(AccountPatchFailure(error) == .unknownResult, "\(error)") }
}

@Test func explicitRefusalsUseCatalogText() {
    let refusals = [server(500, nil), server(409, "UPSTREAM_BILLING_RATE_SYNC_CONFLICT"), server(429, nil), server(503, "ACCOUNT_STATS_UNAVAILABLE")]
    for error in refusals { #expect(AccountPatchFailure(error) == .refused(error.localizedDescription), "\(error)") }
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    #expect(AccountPatchFailure(conflict) == .refused(conflict.localizedDescription))
    #expect(AccountPatchFailure(APIError.refreshDeferred) == .refused(APIError.refreshDeferred.localizedDescription))
}

@Test func securityRefusalsReconfirmOrRefuse() {
    let passed = server(403, "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(AccountPatchFailure(passed) == .reconfirm(passed.localizedDescription))
    #expect(passed.localizedDescription == "二次验证已通过，请重新确认后发送")
    let compliance = server(423, nil).withSecurityOutcome(.passed)
    #expect(AccountPatchFailure(compliance) == .reconfirm("合规确认已完成，请重新确认后发送"))
    #expect(AccountPatchFailure(server(403, "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == .cancelled)
    let readOnly = server(403, "ACCESS_TOKEN_READ_ONLY").withSecurityOutcome(.blocked)
    guard case .refused(let text) = AccountPatchFailure(readOnly) else { Issue.record("expected a refusal"); return }
    #expect(text.hasPrefix("尚未执行："))
}

@Test func cancellationAndLegacyCredentialsPut() {
    #expect(AccountPatchFailure(CancellationError()) == .cancelled)
    let legacy = APIError(kind: .unsupported, reason: AccountWriteReason.legacyCredentialsPut, message: AccountWriteReason.legacyCredentialsPutMessage)
    #expect(AccountPatchFailure(legacy) == .needsWeb("这个站点版本过旧，凭据相关设置请在 Web 中修改"))
}

// MARK: - 尝试与读回

@Test func attemptTransformsKeepRequest() throws {
    let base = AccountEditBase(account: try account(), etag: "\"cv-3\"")
    let key = UUID()
    let attempt = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(name: "新", groupIDs: [1]), idempotencyKey: key)
    #expect(attempt.ifMatch == "\"cv-3\"")
    let current = AccountEditBase(account: try account(#""notes":"别人的""#), etag: "\"cv-5\"")
    let overwritten = attempt.overwriting(current: current)
    #expect(try body(overwritten.request) == body(attempt.request))
    #expect(overwritten.ifMatch == "\"cv-5\"" && overwritten.base.account.notes == "别人的" && overwritten.idempotencyKey == key)
    let tagged = attempt.overwriting(etag: "\"cv-9\"")
    #expect(tagged.ifMatch == "\"cv-9\"" && tagged.base.account.notes == nil)
    let fresh = UUID()
    let confirmed = attempt.confirmingMixedChannel(idempotencyKey: fresh)
    #expect(try body(confirmed.request) == #"{"confirm_mixed_channel_risk":true,"group_ids":[1],"name":"新"}"#)
    #expect(confirmed.ifMatch == "\"cv-3\"" && confirmed.idempotencyKey == fresh)
    let versioned = AccountEditBase(VersionedAccount(account: try account(), etag: "\"cv-7\""))
    #expect(versioned.etag == "\"cv-7\"")
}

@Test func precheckOnlyWhenGroupsChangeWithoutDetailsCapability() throws {
    let base = AccountEditBase(account: try account(), etag: "\"cv-1\"")
    let groups = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(groupIDs: [1]))
    #expect(groups.needsMixedChannelPrecheck(hasDetailsCapability: false))
    #expect(!groups.needsMixedChannelPrecheck(hasDetailsCapability: true))
    #expect(!groups.confirmingMixedChannel(idempotencyKey: nil).needsMixedChannelPrecheck(hasDetailsCapability: false))
    let name = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(name: "新"))
    #expect(!name.needsMixedChannelPrecheck(hasDetailsCapability: false))
}

@Test func readbackVerdictComparesFieldsOrVersion() throws {
    let base = AccountEditBase(account: try account(), etag: "\"cv-3\"")
    let rename = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(name: "新"))
    let renamed = VersionedAccount(account: try account().renamed("新"), etag: "\"cv-4\"")
    let unchanged = VersionedAccount(account: try account(), etag: "\"cv-3\"")
    #expect(AccountPatchReadbackVerdict.evaluate(attempt: rename, current: renamed) == .applied)
    #expect(AccountPatchReadbackVerdict.evaluate(attempt: rename, current: unchanged) == .notApplied)
    let secret = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(credentialsPatch: ["api_key": .set("sk-new")]))
    let cases: [(VersionedAccount, AccountPatchReadbackVerdict)] = [
        (unchanged, .notApplied), (VersionedAccount(account: try account(), etag: "W/\"cv-3\""), .notApplied),
        (renamed, .unconfirmed), (VersionedAccount(account: try account(), etag: nil), .unconfirmed)
    ]
    for (current, verdict) in cases { #expect(AccountPatchReadbackVerdict.evaluate(attempt: secret, current: current) == verdict) }
    let put = AccountPatchAttempt(accountID: 4, base: AccountEditBase(account: try account(), etag: nil), request: secret.request)
    #expect(AccountPatchReadbackVerdict.evaluate(attempt: put, current: unchanged) == .unconfirmed)
}

@Test func attemptPrintsKeyNamesOnly() throws {
    let base = AccountEditBase(account: try account(), etag: "\"cv-3\"")
    let attempt = AccountPatchAttempt(accountID: 4, base: base, request: AccountPatchRequest(notes: "sk-secret-note", credentialsPatch: ["api_key": .set("sk-secret-key")]))
    var dumped = ""
    dump(attempt, to: &dumped)
    for printed in [String(describing: attempt), String(reflecting: attempt), "\(attempt)", dumped] {
        #expect(!printed.contains("sk-secret"))
    }
    #expect(String(describing: attempt).contains("credentials_patch.api_key") && String(describing: attempt).contains("4"))
}

private extension UpstreamAccount {
    func renamed(_ name: String) -> UpstreamAccount { var copy = self; copy.name = name; return copy }
}
