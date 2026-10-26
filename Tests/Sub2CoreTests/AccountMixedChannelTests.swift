import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let mixedChannelReply = #"{"code":409,"reason":"MIXED_CHANNEL_WARNING","error":"mixed_channel_warning","message":"mixed_channel_warning: Group 混合组 has Anthropic and Antigravity","metadata":{"group_id":"12","group_name":"混合组","current_platform":"Anthropic","other_platform":"Antigravity"},"details":{"group_id":12,"group_name":"混合组","current_platform":"Anthropic","other_platform":"Antigravity"}}"#
private let specCopy = "警告：分组“混合组”中同时包含 Anthropic 和 Antigravity 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？"
private let mixedAccountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true}"#

private func mixedClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func bodyText(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }

@Test func warningReadsConflictMetadataWithSpecCopy() async throws {
    let transport = ScriptedTransport(script: [.reply(HTTPResponse(statusCode: 409, data: Data(mixedChannelReply.utf8)))])
    let client = mixedClient(transport)
    let patchError = try #require(await thrownAPIError {
        _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(groupIDs: [12]), ifMatch: "\"cv-1\"")
    })
    let warning = try #require(MixedChannelWarning(error: patchError))
    #expect(warning == MixedChannelWarning(groupID: 12, groupName: "混合组", currentPlatform: "Anthropic", otherPlatform: "Antigravity"))
    #expect(warning.message == specCopy)
    #expect(!patchError.localizedDescription.contains("Group"))
    let putError = try #require(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(groupIDs: [12]), base: nil) })
    #expect(MixedChannelWarning(error: putError) == warning)
}

@Test(arguments: [
    #"{"error":"mixed_channel_warning","message":"Group x mixes channels"}"#,
    #"{"code":409,"reason":"ACCOUNT_TEST_RUNNING","metadata":{"group_name":"g","current_platform":"A","other_platform":"B"}}"#,
    #"{"code":409,"reason":"MIXED_CHANNEL_WARNING","metadata":{"group_name":"g","current_platform":"A"}}"#,
    #"{"code":409,"reason":"MIXED_CHANNEL_WARNING","metadata":{"group_name":"","current_platform":"A","other_platform":"B"}}"#
])
func warningIsNilForOtherConflicts(body: String) {
    #expect(MixedChannelWarning(error: APIError.from(HTTPResponse(statusCode: 409, data: Data(body.utf8)))) == nil)
}

@Test func warningNeedsAConflictAndKeepsAnOddGroupIDAsNil() {
    let metadata = #","metadata":{"group_name":"g","current_platform":"A","other_platform":"B"}"#
    #expect(MixedChannelWarning(error: APIError.from(errorReply(400, reason: "MIXED_CHANNEL_WARNING", extra: metadata))) == nil)
    #expect(MixedChannelWarning(error: APIError(kind: .validation, message: "本地错误")) == nil)
    let odd = MixedChannelWarning(error: APIError.from(errorReply(409, reason: "MIXED_CHANNEL_WARNING",
                                                                  extra: #","metadata":{"group_id":"abc","group_name":"g","current_platform":"A","other_platform":"B"}"#)))
    #expect(odd == MixedChannelWarning(groupID: nil, groupName: "g", currentPlatform: "A", otherPlatform: "B"))
}

@Test func checkMixedChannelEncodesRequestAndIsSentOnce() async throws {
    let safe = okReply(#"{"has_risk":false}"#)
    let transport = ScriptedTransport(script: [.reply(safe), .reply(safe), .fail(URLError(.timedOut)), .reply(safe)])
    let client = mixedClient(transport)
    #expect(try await client.checkMixedChannel(platform: "anthropic", groupIDs: [3, 5], accountID: 7) == MixedChannelCheck(hasRisk: false))
    _ = try await client.checkMixedChannel(platform: " antigravity ", groupIDs: [3, 5], accountID: nil)
    #expect(await thrownAPIError { _ = try await client.checkMixedChannel(platform: "anthropic", groupIDs: [3], accountID: nil) }?.kind == .transport)
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/v1/admin/accounts/check-mixed-channel")
        #expect(sentHeader(request, "Idempotency-Key") == nil)
    }
    #expect(bodyText(requests[0]) == #"{"account_id":7,"group_ids":[3,5],"platform":"anthropic"}"#)
    #expect(bodyText(requests[1]) == #"{"group_ids":[3,5],"platform":"antigravity"}"#)
}

@Test func checkMixedChannelDecodesRiskWithoutMessage() throws {
    let risky = try JSONDecoder().decode(MixedChannelCheck.self, from: Data(#"{"has_risk":true,"error":"mixed_channel_warning","message":"upstream text","details":{"group_id":12,"group_name":"混合组","current_platform":"Anthropic","other_platform":"Antigravity"}}"#.utf8))
    let details = MixedChannelCheck.Details(groupID: 12, groupName: "混合组", currentPlatform: "Anthropic", otherPlatform: "Antigravity")
    #expect(risky == MixedChannelCheck(hasRisk: true, details: details))
    #expect(MixedChannelWarning(check: risky)?.message == specCopy)
    let safe = try JSONDecoder().decode(MixedChannelCheck.self, from: Data(#"{"has_risk":false}"#.utf8))
    #expect(safe.details == nil && MixedChannelWarning(check: safe) == nil)
    let broken = try JSONDecoder().decode(MixedChannelCheck.self, from: Data(#"{"has_risk":true,"details":{"group_id":{"x":1},"group_name":"g","current_platform":"A","other_platform":"B"}}"#.utf8))
    #expect(broken.hasRisk && broken.details == nil && MixedChannelWarning(check: broken) == nil)
    #expect(try JSONDecoder().decode(MixedChannelCheck.self, from: Data("{}".utf8)) == MixedChannelCheck(hasRisk: false))
}

@Test func checkMixedChannelSkipsEmptyGroupsAndValidatesLocally() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"has_risk":true}"#))])
    let client = mixedClient(transport)
    #expect(try await client.checkMixedChannel(platform: "anthropic", groupIDs: [], accountID: 7) == MixedChannelCheck(hasRisk: false))
    let invalid: [(String, [Int], Int?)] = [("  ", [3], 7), ("anthropic", [0], nil), ("anthropic", [3], 0)]
    for (platform, groups, account) in invalid {
        #expect(await thrownAPIError { _ = try await client.checkMixedChannel(platform: platform, groupIDs: groups, accountID: account) }?.kind == .validation)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func mixedChannelWarningAlsoComesFromAKeyedPut() async throws {
    let transport = ScriptedTransport(script: [.reply(HTTPResponse(statusCode: 409, data: Data(mixedChannelReply.utf8))), .reply(okReply(mixedAccountJSON))])
    let client = mixedClient(transport)
    let patch = AccountPatchRequest(groupIDs: [12])
    let error = try #require(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: patch, base: nil, idempotencyKey: UUID()) })
    #expect(MixedChannelWarning(error: error)?.groupName == "混合组")
    // The confirmed body differs, so it goes out under a new key (00 §2.5.2).
    let confirmed = try await client.fullUpdate(id: 9, patch: patch.confirmingMixedChannel(), base: nil, idempotencyKey: UUID())
    #expect(confirmed.id == 9)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(bodyText(requests[1]) == #"{"confirm_mixed_channel_risk":true,"group_ids":[12]}"#)
}
