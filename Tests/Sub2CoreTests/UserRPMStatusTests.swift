import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let fullStatusJSON = #"{"user_rpm_used":45,"user_rpm_limit":60,"user_rpm_tracked":true,"per_group":[{"group_id":5,"group_name":"Claude Code 组","used":3,"limit":30,"source":"group","tracked":true},{"group_id":7,"group_name":"","used":0,"limit":0,"source":"","tracked":false}]}"#
private func rpmClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-key"), transport: transport, requestClock: .immediate)
}
private func decodeStatus(_ json: String) throws -> UserRPMStatus { try JSONDecoder().decode(UserRPMStatus.self, from: Data(json.utf8)) }
private let tracking = UserRPMContext(isSimpleMode: false, reportsTracking: true)
private let legacy = UserRPMContext(isSimpleMode: false, reportsTracking: false)
private let simple = UserRPMContext(isSimpleMode: true, reportsTracking: true)

@Test func statusDecodesFullAndLegacyShapes() throws {
    let full = try decodeStatus(fullStatusJSON)
    #expect(full.userUsed == 45 && full.userLimit == 60 && full.userTracked == true)
    #expect(full.perGroup == [UserRPMStatus.Group(groupID: 5, groupName: "Claude Code 组", used: 3, limit: 30, source: "group", tracked: true),
                              UserRPMStatus.Group(groupID: 7, groupName: "", used: 0, limit: 0, source: "", tracked: false)])
    #expect(try decodeStatus(#"{"user_rpm_used":0,"user_rpm_limit":0,"user_rpm_tracked":false,"per_group":null}"#).perGroup.isEmpty)
    let old = try decodeStatus(#"{"user_rpm_used":1,"user_rpm_limit":10,"per_group":[{"group_id":5,"group_name":"A","used":1,"limit":5,"source":"group"}]}"#)
    #expect(old.userTracked == nil && old.perGroup.first?.tracked == nil)
    #expect(try decodeStatus(#"{"user_rpm_used":1,"user_rpm_limit":10,"per_group":"x"}"#).perGroup.isEmpty)
}

@Test func rpmStatusRequestsUserPath() async throws {
    let transport = ScriptedTransport { _ in okReply(fullStatusJSON) }
    let client = rpmClient(transport)
    #expect(try await client.userRPMStatus(id: 24) == .status(decodeStatus(fullStatusJSON)))
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/users/24/rpm-status" && request.url?.query == nil)
    #expect(await thrownAPIError { _ = try await client.userRPMStatus(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
}

/// 30 §6.3 整块: 501 RPM_STATUS_UNAVAILABLE, or a site without the route, reads as “暂不可用”; anything else is an error.
@Test func unavailableAnswersBecomeUnavailable() async throws {
    let disabled = ScriptedTransport { _ in errorReply(501, reason: "RPM_STATUS_UNAVAILABLE") }
    #expect(try await rpmClient(disabled).userRPMStatus(id: 24) == .unavailable)
    #expect(await disabled.requests.count == 1)
    let old = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["Content-Type": "text/plain"], data: Data("404 page not found".utf8)) }
    #expect(try await rpmClient(old).userRPMStatus(id: 24) == .unavailable)
    let broken = ScriptedTransport { _ in errorReply(500) }
    await #expect(throws: APIError.self) { _ = try await rpmClient(broken).userRPMStatus(id: 24) }
    let other = ScriptedTransport { _ in errorReply(501, reason: "NOT_IMPLEMENTED") }
    await #expect(throws: APIError.self) { _ = try await rpmClient(other).userRPMStatus(id: 24) }
}

struct RPMTotalCase: Sendable, CustomTestStringConvertible {
    let status: UserRPMStatus
    let context: UserRPMContext
    let value: String
    var progress: Double? = nil
    var tone: Tone? = nil
    var testDescription: String { value }
}

@Test(arguments: [
    RPMTotalCase(status: UserRPMStatus(userUsed: 45, userLimit: 60, userTracked: true), context: simple, value: "简易模式不计数"),
    RPMTotalCase(status: UserRPMStatus(userUsed: 0, userLimit: 60, userTracked: false), context: tracking, value: "不限 · 不计数"),
    RPMTotalCase(status: UserRPMStatus(userUsed: 0, userLimit: 0), context: legacy, value: "不限 · 不计数"),
    RPMTotalCase(status: UserRPMStatus(userUsed: 0, userLimit: 0, userTracked: true), context: tracking, value: "不限制"),
    RPMTotalCase(status: UserRPMStatus(userUsed: 3, userTracked: true), context: tracking, value: "—"),
    RPMTotalCase(status: UserRPMStatus(userUsed: 45, userLimit: 60, userTracked: true), context: tracking, value: "45 / 60", progress: 0.75, tone: .caution),
    RPMTotalCase(status: UserRPMStatus(userUsed: 54, userLimit: 60, userTracked: true), context: tracking, value: "54 / 60", progress: 0.9, tone: .critical),
    RPMTotalCase(status: UserRPMStatus(userUsed: 30, userLimit: 60, userTracked: true), context: tracking, value: "30 / 60", progress: 0.5),
    RPMTotalCase(status: UserRPMStatus(userUsed: 1200, userLimit: 2000), context: legacy, value: "1,200 / 2,000", progress: 0.6),
    RPMTotalCase(status: UserRPMStatus(userLimit: 60, userTracked: true), context: tracking, value: "— / 60")
])
func totalLineTable(row: RPMTotalCase) {
    let line = UserRPMPresentation.total(row.status, context: row.context)
    #expect(line.label == nil && line.value == row.value)
    #expect(line.progress == row.progress && line.tone == row.tone)
}

struct RPMGroupCase: Sendable, CustomTestStringConvertible {
    let row: UserRPMStatus.Group
    let context: UserRPMContext
    let label: String
    let value: String
    var testDescription: String { "\(label) \(value)" }
}

@Test(arguments: [
    RPMGroupCase(row: .init(groupID: 5, used: 12, limit: 30, source: "override", tracked: true), context: tracking, label: "专属 RPM", value: "12 / 30"),
    RPMGroupCase(row: .init(groupID: 5, used: 12, limit: 30, source: "group", tracked: true), context: tracking, label: "分组 RPM", value: "12 / 30"),
    RPMGroupCase(row: .init(groupID: 5, used: 0, limit: 0, source: "", tracked: false), context: tracking, label: "—", value: "—"),
    RPMGroupCase(row: .init(groupID: 5, used: 2, limit: 20, source: "inherit", tracked: true), context: tracking, label: "—", value: "2 / 20"),
    RPMGroupCase(row: .init(groupID: 5, used: 0, limit: 0, source: "override", tracked: false), context: tracking, label: "专属 RPM", value: "免检"),
    RPMGroupCase(row: .init(groupID: 5, used: 0, limit: 0, source: "group", tracked: false), context: tracking, label: "分组 RPM", value: "不限 · 不计数"),
    RPMGroupCase(row: .init(groupID: 5, used: 0, limit: 0, source: "group", tracked: true), context: tracking, label: "分组 RPM", value: "不限"),
    RPMGroupCase(row: .init(groupID: 5, used: 0, limit: 0, source: "group"), context: legacy, label: "分组 RPM", value: "不限 · 不计数"),
    RPMGroupCase(row: .init(groupID: 5, used: 3, limit: 30, source: "group", tracked: true), context: simple, label: "分组 RPM", value: "简易模式不计数")
])
func groupLineTable(row: RPMGroupCase) {
    let line = UserRPMPresentation.group(row.row, context: row.context)
    #expect(line.label == row.label && line.value == row.value)
    #expect(line.progress == nil && line.tone == nil)
}

@Test func groupNameFallsBackToID() {
    #expect(UserRPMPresentation.groupName(.init(groupID: 7, groupName: "  ")) == "分组 #7")
    #expect(UserRPMPresentation.groupName(.init(groupID: 5, groupName: "Claude Code 组")) == "Claude Code 组")
}

@Test func progressToneThresholds() {
    #expect(UserRPMPresentation.tone(used: 74, limit: 100) == nil)
    #expect(UserRPMPresentation.tone(used: 75, limit: 100) == .caution && UserRPMPresentation.tone(used: 89, limit: 100) == .caution)
    #expect(UserRPMPresentation.tone(used: 90, limit: 100) == .critical && UserRPMPresentation.tone(used: 130, limit: 100) == .critical)
    #expect(UserRPMPresentation.tone(used: 5, limit: 0) == nil)
    #expect(UserRPMPresentation.total(UserRPMStatus(userUsed: 130, userLimit: 100, userTracked: true), context: tracking).progress == 1)
}

@Test func contextFromAdminMe() throws {
    func me(_ server: String) throws -> AdminMe { try JSONDecoder().decode(AdminMe.self, from: Data("{\"server\":\(server)}".utf8)) }
    let simpleMe = try me(#"{"run_mode":" Simple ","capabilities":["users.rpm_tracked"]}"#)
    #expect(UserRPMContext(me: simpleMe) == UserRPMContext(isSimpleMode: true, reportsTracking: true))
    #expect(try UserRPMContext(me: me(#"{"run_mode":"standard","capabilities":[]}"#)) == legacy)
    #expect(UserRPMContext(me: nil) == legacy)
    #expect(UserRPMPresentation.title == "RPM 状态 · 本分钟")
    #expect(UserRPMPresentation.unavailableText == "RPM 状态暂不可用" && UserRPMPresentation.failedText == "RPM 状态加载失败 · 重试")
}
