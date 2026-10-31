import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 30 §8.2 / §8.4 / §8.7 (S3-14): the platform quota rows, the strict three-key body, the undo plan, the whole-table fallback
// and the six requests.

private func quotaClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func body(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self) }
private func amount(_ raw: String) -> Decimal { Decimal(string: raw)! }
private func decodeQuota(_ json: String) throws -> UserPlatformQuota { try JSONDecoder().decode(UserPlatformQuota.self, from: Data(json.utf8)) }
private func limits(_ daily: Decimal?, _ weekly: Decimal?, _ monthly: Decimal?) -> PlatformQuotaLimits {
    PlatformQuotaLimits(daily: daily, weekly: weekly, monthly: monthly)
}
private func row(_ platform: String, _ daily: Decimal?, _ weekly: Decimal?, _ monthly: Decimal?, usage: Decimal = 0, readable: Bool = true) -> UserPlatformQuota {
    UserPlatformQuota(platform: platform, daily: PlatformQuotaWindow(usage: usage, limit: daily), weekly: PlatformQuotaWindow(limit: weekly),
                      monthly: PlatformQuotaWindow(limit: monthly), limitsReadable: readable)
}
private func isValidation(_ make: () throws -> Void) -> Bool {
    do { try make(); return false } catch { return (error as? APIError)?.kind == .validation }
}
private let anthropicJSON = #"""
{"platform":"anthropic","daily_usage_usd":2.8,"daily_limit_usd":10,"daily_window_resets_at":"2026-10-31T16:00:00Z","daily_window_start":"2026-10-30T16:00:00Z",
 "weekly_usage_usd":"41","weekly_limit_usd":"50","weekly_window_resets_at":null,"weekly_window_start":null,
 "monthly_usage_usd":48.6,"monthly_limit_usd":null,"monthly_window_resets_at":"2026-11-20T00:00:00Z","monthly_window_start":"2026-10-21T00:00:00Z"}
"""#

// MARK: - 解码

@Test func decodesListWithNullVersusZeroLimits() throws {
    let quota = try decodeQuota(anthropicJSON)
    #expect(quota.id == "anthropic" && quota.limitsReadable)
    #expect(quota.daily == PlatformQuotaWindow(usage: amount("2.8"), limit: 10, resetsAt: ServerTime.parseTimestamp("2026-10-31T16:00:00Z"),
                                               windowStart: ServerTime.parseTimestamp("2026-10-30T16:00:00Z")))
    #expect(quota.weekly.usage == 41 && quota.weekly.limit == 50 && quota.weekly.resetsAt == nil && quota.weekly.windowStart == nil)
    #expect(quota.monthly.limit == nil && quota.monthly.usage == amount("48.6"))
    #expect(quota.limits == limits(10, 50, nil) && !quota.isBanned)

    let banned = try decodeQuota(#"{"platform":"openai","daily_limit_usd":0,"weekly_limit_usd":"2.5"}"#)
    #expect(banned.daily.limit == 0 && banned.weekly.limit == amount("2.5") && banned.monthly.limit == nil)
    #expect(banned.daily.usage == 0 && banned.isBanned && banned.limitsReadable)

    for odd in [#"true"#, #""2.5x""#, #""-1""#, #"-3"#, #"{}"#] {
        let unreadable = try decodeQuota(#"{"platform":"gemini","daily_usage_usd":1,"weekly_limit_usd":\#(odd)}"#)
        #expect(!unreadable.limitsReadable, "\(odd)")
        #expect(unreadable.daily.usage == 1)
    }
    let list = try JSONDecoder().decode(PlatformQuotaList.self, from: Data(#"{"platform_quotas":[\#(anthropicJSON)]}"#.utf8))
    #expect(list.platformQuotas.map(\.platform) == ["anthropic"])
}

@Test func decodesWriteResultsWithNullPlatformQuota() throws {
    let upsert = try JSONDecoder().decode(PlatformQuotaUpsertResult.self, from: Data(#"{"platform_quota":\#(anthropicJSON),"previous":null}"#.utf8))
    #expect(upsert.platformQuota?.platform == "anthropic" && upsert.previous == nil && upsert.previousReadable)
    let removed = try JSONDecoder().decode(PlatformQuotaUpsertResult.self, from: Data(#"{"platform_quota":null,"previous":\#(anthropicJSON)}"#.utf8))
    #expect(removed.platformQuota == nil && removed.previous == limits(10, 50, nil))
    let deleted = try JSONDecoder().decode(PlatformQuotaDeleteResult.self, from: Data(#"{"removed":true,"previous":\#(anthropicJSON)}"#.utf8))
    #expect(deleted.removed && deleted.previous == limits(10, 50, nil) && deleted.previousReadable)
    let unreadable = try JSONDecoder().decode(PlatformQuotaDeleteResult.self,
                                              from: Data(#"{"removed":true,"previous":{"platform":"openai","daily_limit_usd":"x"}}"#.utf8))
    #expect(!unreadable.previousReadable)
    let restored = try JSONDecoder().decode(PlatformQuotaRestoreResult.self, from: Data(#"{"platform_quota":\#(anthropicJSON),"restored":true}"#.utf8))
    #expect(restored.restored && restored.platformQuota?.daily.usage == amount("2.8"))
}

// MARK: - 请求体

@Test func limitsEncodeExactlyThreeKeysWithJSONNull() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(body(try encoder.encode(limits(10, 0, nil))) == #"{"daily_limit_usd":10,"monthly_limit_usd":null,"weekly_limit_usd":0}"#)
    #expect(body(try encoder.encode(PlatformQuotaLimits())) == #"{"daily_limit_usd":null,"monthly_limit_usd":null,"weekly_limit_usd":null}"#)
    #expect(body(try encoder.encode(limits(amount("2.5"), nil, amount("0.00000001")))) ==
            #"{"daily_limit_usd":2.5,"monthly_limit_usd":0.00000001,"weekly_limit_usd":null}"#)
    #expect(body(try encoder.encode(PlatformQuotaEntry(platform: "openai", limits: limits(nil, 50, nil)))) ==
            #"{"daily_limit_usd":null,"monthly_limit_usd":null,"platform":"openai","weekly_limit_usd":50}"#)
    #expect(PlatformQuotaLimits().isEmpty && !limits(0, nil, nil).isEmpty)
}

@Test func limitsValidateRejectsNegativeAndTooLarge() throws {
    try limits(0, amount("9999999999.99999999"), nil).validate()
    for bad in [amount("-0.01"), Decimal.nan, amount("10000000000"), amount("0.000000001")] {
        #expect(isValidation { try limits(nil, nil, bad).validate() }, "\(bad)")
    }
}

// MARK: - 撤销与整表退路

@Test func undoPlanCoversThreeBranches() {
    #expect(PlatformQuotaUndo.plan(previous: nil, current: limits(10, nil, nil)) == .delete)
    #expect(PlatformQuotaUndo.plan(previous: limits(5, nil, 30), current: limits(10, nil, nil)) == .put(limits(5, nil, 30)))
    #expect(PlatformQuotaUndo.plan(previous: limits(5, nil, nil), current: nil) == .restore)
    #expect(PlatformQuotaUndo.plan(previous: limits(5, nil, nil), current: PlatformQuotaLimits()) == .restore)
    #expect(PlatformQuotaUndo.plan(previous: nil, current: nil) == nil)
    #expect(PlatformQuotaUndo.plan(previous: PlatformQuotaLimits(), current: PlatformQuotaLimits()) == nil)
}

@Test func fallbackEntriesChangeOnlyTargetPlatform() throws {
    let latest = [row("anthropic", 10, nil, nil), row("openai", nil, 50, nil), row("zhipu", 0, 0, 0)]
    let changed = try PlatformQuotaFallback.entries(latest: latest, setting: "openai", to: limits(20, nil, nil))
    #expect(changed == [PlatformQuotaEntry(platform: "anthropic", limits: limits(10, nil, nil)), PlatformQuotaEntry(platform: "openai", limits: limits(20, nil, nil)),
                        PlatformQuotaEntry(platform: "zhipu", limits: limits(0, 0, 0))])
    let cleared = try PlatformQuotaFallback.entries(latest: latest, setting: "openai", to: PlatformQuotaLimits())
    #expect(cleared.map(\.platform) == ["anthropic", "zhipu"] && cleared[1].limits == limits(0, 0, 0))
    #expect(try PlatformQuotaFallback.entries(latest: latest, setting: "openai", to: nil).map(\.platform) == ["anthropic", "zhipu"])
    let added = try PlatformQuotaFallback.entries(latest: latest, setting: "gemini", to: limits(nil, nil, 3))
    #expect(added.map(\.platform) == ["anthropic", "openai", "zhipu", "gemini"] && added.last?.limits == limits(nil, nil, 3))
    // A platform the app's catalog does not know is copied as it is.
    let unknown = try PlatformQuotaFallback.entries(latest: [row("future_ai", 7, nil, nil)], setting: "openai", to: limits(1, nil, nil))
    #expect(unknown == [PlatformQuotaEntry(platform: "future_ai", limits: limits(7, nil, nil)), PlatformQuotaEntry(platform: "openai", limits: limits(1, nil, nil))])
}

@Test func fallbackEntriesThrowsWhenUnreadable() {
    let latest = [row("anthropic", 10, nil, nil), row("openai", nil, nil, nil, readable: false)]
    #expect(throws: PlatformQuotaFallback.Failure.unreadable) { try PlatformQuotaFallback.entries(latest: latest, setting: "anthropic", to: limits(1, nil, nil)) }
    #expect(throws: PlatformQuotaFallback.Failure.unreadable) { try PlatformQuotaFallback.undoEntries(latest: latest, platform: "anthropic", before: nil) }
}

@Test func fallbackUndoEntriesRestoreBeforeSnapshot() throws {
    let latest = [row("anthropic", 20, nil, nil), row("openai", nil, 50, nil)]
    #expect(try PlatformQuotaFallback.undoEntries(latest: latest, platform: "anthropic", before: limits(10, 50, nil)) ==
            [PlatformQuotaEntry(platform: "anthropic", limits: limits(10, 50, nil)), PlatformQuotaEntry(platform: "openai", limits: limits(nil, 50, nil))])
    #expect(try PlatformQuotaFallback.undoEntries(latest: latest, platform: "anthropic", before: nil).map(\.platform) == ["openai"])
    #expect(PlatformQuotaFallback.undoResetsUsage(before: limits(10, nil, nil), after: nil))
    #expect(PlatformQuotaFallback.undoResetsUsage(before: limits(10, nil, nil), after: PlatformQuotaLimits()))
    #expect(!PlatformQuotaFallback.undoResetsUsage(before: limits(10, nil, nil), after: limits(20, nil, nil)))
    #expect(!PlatformQuotaFallback.undoResetsUsage(before: nil, after: limits(20, nil, nil)))
}

// MARK: - 请求

@Test func platformQuotasRequestShape() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"platform_quotas":[\#(anthropicJSON)]}"#))])
    let quotas = try await quotaClient(transport).platformQuotas(userID: 7)
    #expect(quotas.map(\.platform) == ["anthropic"])
    let sent = await transport.requests
    #expect(sent.count == 1 && sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/users/7/platform-quotas")
    #expect(sentHeader(sent[0], "Idempotency-Key") == nil && sent[0].httpBody == nil)
    #expect(await thrownAPIError { _ = try await quotaClient(transport).platformQuotas(userID: 0) }?.kind == .validation)
}

@Test func upsertSendsStrictBodyWithoutIdempotencyKey() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"platform_quota":\#(anthropicJSON),"previous":null}"#)), .reply(errorReply(502))])
    let client = quotaClient(transport)
    let result = try await client.upsertPlatformQuota(userID: 7, platform: "anthropic", limits: limits(10, 50, nil))
    #expect(result.platformQuota?.limits == limits(10, 50, nil) && result.previous == nil)
    #expect(await thrownAPIError { _ = try await client.upsertPlatformQuota(userID: 7, platform: "anthropic", limits: limits(10, nil, nil)) }?.statusCode == 502)
    let sent = await transport.requests
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.httpMethod == "PUT" && $0.url?.path == "/api/v1/admin/users/7/platform-quotas/anthropic" && sentHeader($0, "Idempotency-Key") == nil })
    #expect(body(sent[0].httpBody) == #"{"daily_limit_usd":10,"monthly_limit_usd":null,"weekly_limit_usd":50}"#)
    // Refused before anything goes out.
    #expect(await thrownAPIError { _ = try await client.upsertPlatformQuota(userID: 7, platform: "anthropic", limits: limits(-1, nil, nil)) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.upsertPlatformQuota(userID: 7, platform: "../users", limits: limits(1, nil, nil)) }?.kind == .validation)
    #expect(await transport.requests.count == 2)
}

@Test func deleteRestoreResetAndReplaceRequestShapes() async throws {
    let list = okReply(#"{"platform_quotas":[\#(anthropicJSON)]}"#)
    let transport = ScriptedTransport(script: [
        .reply(okReply(#"{"removed":true,"previous":\#(anthropicJSON)}"#)),
        .reply(okReply(#"{"platform_quota":\#(anthropicJSON),"restored":true}"#)),
        .reply(list), .reply(list),
    ])
    let client = quotaClient(transport)
    #expect(try await client.deletePlatformQuota(userID: 7, platform: "openai").removed)
    #expect(try await client.restorePlatformQuota(userID: 7, platform: "openai").restored)
    #expect(try await client.resetPlatformQuotaWindow(userID: 7, platform: "anthropic", window: .weekly).count == 1)
    let entries = [PlatformQuotaEntry(platform: "anthropic", limits: limits(10, nil, nil)), PlatformQuotaEntry(platform: "zhipu", limits: limits(0, 0, 0))]
    #expect(try await client.replaceUserPlatformQuotas(userID: 7, quotas: entries).count == 1)
    let sent = await transport.requests
    #expect(sent.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
        "DELETE /api/v1/admin/users/7/platform-quotas/openai", "POST /api/v1/admin/users/7/platform-quotas/openai/restore",
        "POST /api/v1/admin/users/7/platform-quotas/reset", "PUT /api/v1/admin/users/7/platform-quotas",
    ])
    #expect(sent[0].httpBody == nil && sent[1].httpBody == nil)
    #expect(body(sent[2].httpBody) == #"{"platform":"anthropic","window":"weekly"}"#)
    #expect(body(sent[3].httpBody) == #"{"quotas":[{"daily_limit_usd":10,"monthly_limit_usd":null,"platform":"anthropic","weekly_limit_usd":null},"# +
            #"{"daily_limit_usd":0,"monthly_limit_usd":0,"platform":"zhipu","weekly_limit_usd":0}]}"#)
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })
}

@Test func quotaWritesAreNeverResent() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(503))])
    let client = quotaClient(transport)
    #expect(await thrownAPIError { _ = try await client.replaceUserPlatformQuotas(userID: 7, quotas: []) }?.statusCode == 503)
    #expect(await thrownAPIError { _ = try await client.resetPlatformQuotaWindow(userID: 7, platform: "openai", window: .daily) }?.statusCode == 503)
    #expect(await thrownAPIError { _ = try await client.deletePlatformQuota(userID: 7, platform: "openai") }?.statusCode == 503)
    #expect(await thrownAPIError { _ = try await client.restorePlatformQuota(userID: 7, platform: "openai") }?.statusCode == 503)
    #expect(await transport.requests.count == 4)
}

@Test func quotaErrorsKeepReasons() async throws {
    let secret = #","message":"daily_limit_usd must be >= 0 SERVER-ONLY-TEXT""#
    let transport = ScriptedTransport(script: [
        .reply(errorReply(400, reason: "INVALID_QUOTA_LIMIT", extra: secret)),
        .reply(errorReply(404, reason: "USER_PLATFORM_QUOTA_NOT_FOUND", extra: secret)),
        .reply(errorReply(409, reason: "USER_PLATFORM_QUOTA_ACTIVE_EXISTS", extra: secret)),
    ])
    let client = quotaClient(transport)
    let invalid = await thrownAPIError { _ = try await client.upsertPlatformQuota(userID: 7, platform: "openai", limits: limits(1, nil, nil)) }
    let missing = await thrownAPIError { _ = try await client.deletePlatformQuota(userID: 7, platform: "openai") }
    let conflict = await thrownAPIError { _ = try await client.restorePlatformQuota(userID: 7, platform: "openai") }
    #expect(invalid?.reason == "INVALID_QUOTA_LIMIT" && invalid?.statusCode == 400)
    #expect(missing?.reason == "USER_PLATFORM_QUOTA_NOT_FOUND" && missing?.statusCode == 404)
    #expect(conflict?.reason == "USER_PLATFORM_QUOTA_ACTIVE_EXISTS" && conflict?.statusCode == 409)
    for error in [invalid, missing, conflict] { #expect(error?.localizedDescription.contains("SERVER-ONLY-TEXT") == false) }
}
