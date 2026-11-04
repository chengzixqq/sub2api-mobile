import Foundation
import Testing
@testable import Sub2Core

// 40 §7.3 / §7.4: 标记已处理's failures and words, the row it changes in place, and what 标识 and the ··· menu copy (S4-08b).

private func resolveDecoded<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}
private func resolveRow(_ id: Int = 2006, _ changes: [String: Any] = [:]) throws -> RequestErrorRecord {
    let row: [String: Any] = [
        "id": id, "created_at": "2026-10-16T01:41:07Z", "request_id": "req-err-\(id)", "phase": "upstream", "type": "rate_limit_error",
        "status_code": 429, "platform": "openai", "model": "gpt-4.1", "resolved": false, "message": "上游请求受限", "account_id": 4,
        "client_request_id": "00000000-0000-4000-9000-00000000\(id)",
    ]
    return try resolveDecoded(RequestErrorRecord.self, row.merging(changes) { _, new in new })
}
private func resolveChain(lastUpstreamID: String?) throws -> RequestAttempts {
    var last: [String: Any] = ["index": 2, "outcome": "failed", "account_id": 7, "upstream_status_code": 429]
    if let lastUpstreamID { last["upstream_request_id"] = lastUpstreamID }
    let attempts: [[String: Any]] = [["index": 1, "outcome": "failed", "account_id": 4, "upstream_status_code": 429, "upstream_request_id": "up-1"], last]
    return try resolveDecoded(RequestAttempts.self, ["client_status_code": 429, "attempts": attempts])
}
private func resolveUsage(upstreamID: Any) throws -> UsageRequestRecord {
    try resolveDecoded(UsageRequestRecord.self, [
        "id": 1040, "request_id": "client:00000000-0000-4000-8000-000000001040", "created_at": "2026-10-16T01:41:07Z",
        "model": "claude-opus-4", "user_id": 1, "account_id": 4, "api_key_id": 101, "upstream_request_id": upstreamID,
    ])
}

struct ResolveFailureCase: Sendable, CustomTestStringConvertible {
    let name: String
    let error: any Error & Sendable
    let expected: RequestResolveFailure?
    var testDescription: String { name }
}
private let failureCases: [ResolveFailureCase] = [
    ResolveFailureCase(name: "404 OPS_ERROR_NOT_FOUND", error: APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND"), expected: .gone),
    ResolveFailureCase(name: "404 OPS_DISABLED", error: APIError.server(status: 404, reason: "OPS_DISABLED"), expected: .opsDisabled),
    ResolveFailureCase(name: "403 read-only", error: APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), expected: .readOnly),
    ResolveFailureCase(name: "429", error: APIError.server(status: 429, envelope: ErrorEnvelope(reason: nil), retryAfter: 7),
                expected: .rateLimited("请求过于频繁，请 7 秒后再试")),
    ResolveFailureCase(name: "transport", error: APIError(kind: .transport, message: "连接超时"), expected: .resultUnknown),
    ResolveFailureCase(name: "invalid response", error: APIError.invalidResponse, expected: .resultUnknown),
    ResolveFailureCase(name: "502", error: APIError.server(status: 502, envelope: nil), expected: .resultUnknown),
    ResolveFailureCase(name: "504", error: APIError.server(status: 504, reason: nil), expected: .resultUnknown),
    ResolveFailureCase(name: "503", error: APIError.server(status: 503, reason: nil), expected: .resultUnknown),
    ResolveFailureCase(name: "503 STEP_UP_UNAVAILABLE", error: APIError.server(status: 503, reason: "STEP_UP_UNAVAILABLE"), expected: .refused),
    ResolveFailureCase(name: "400 without reason", error: APIError.server(status: 400, reason: nil), expected: .programError),
    ResolveFailureCase(name: "500", error: APIError.server(status: 500, reason: nil), expected: .refused),
    ResolveFailureCase(name: "404 not JSON", error: APIError.server(status: 404, envelope: nil), expected: .refused),
    ResolveFailureCase(name: "400 OPS_ERROR_INVALID_ID", error: APIError.server(status: 400, reason: "OPS_ERROR_INVALID_ID"), expected: .refused),
    ResolveFailureCase(name: "cancelled", error: CancellationError(), expected: nil),
    ResolveFailureCase(name: "prompt cancelled", error: APIError.server(status: 423, reason: nil).withSecurityOutcome(.cancelled), expected: nil),
]

@Test(arguments: failureCases)
func resolveFailureClassifiesEveryAnswer(_ item: ResolveFailureCase) {
    #expect(RequestResolveFailure(item.error) == item.expected)
}

@Test func resolveCopyMatchesSpec() {
    #expect(RequestDetailCopy.markTitle == "标记已处理" && RequestDetailCopy.resolvedTitle == "已处理")
    #expect(RequestDetailCopy.marked == "已标记为已处理" && RequestDetailCopy.markFailed == "标记失败，请重试")
    #expect(RequestDetailCopy.resolveGone == "记录已不存在" && RequestDetailCopy.resolveOpsDisabled == "运维监控未开启，无法标记")
    #expect(RequestDetailCopy.readOnly == "当前管理访问令牌只读，不能执行此操作")
    #expect(RequestDetailCopy.readOnly == ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message)
    #expect(RequestDetailCopy.unconfirmed == "结果未确认，请刷新核对后再操作")
    for marking in [true, false] {
        #expect(RequestDetailCopy.failureText(.gone, marking: marking) == "记录已不存在")
        #expect(RequestDetailCopy.failureText(.opsDisabled, marking: marking) == "运维监控未开启，无法标记")
        #expect(RequestDetailCopy.failureText(.readOnly, marking: marking) == "当前管理访问令牌只读，不能执行此操作")
        #expect(RequestDetailCopy.failureText(.rateLimited("请求过于频繁，请 7 秒后再试"), marking: marking) == "请求过于频繁，请 7 秒后再试")
        for failure in [RequestResolveFailure.refused, .programError, .resultUnknown] {
            #expect(RequestDetailCopy.failureText(failure, marking: marking) == (marking ? "标记失败，请重试" : "撤回失败，请重试"))
        }
    }
}

@Test func settingResolvedChangesOnlyTheMark() throws {
    let zone = TimeZone(identifier: "Asia/Shanghai")!, now = ServerTime.parseTimestamp("2026-10-21T02:00:00Z")!
    let handled = try resolveRow(2006, ["resolved": true, "resolved_at": "2026-10-16T01:52:00Z", "resolved_by_user_name": "admin@example.invalid"])
    #expect(RequestDetailPresentation.resolvedNote(handled, now: now, timeZone: zone) != nil)
    let reopened = handled.settingResolved(false)
    #expect(!reopened.resolved && reopened.resolvedAt == nil && reopened.resolvedByUserName == nil)
    #expect(reopened.id == handled.id && reopened.requestID == handled.requestID && reopened.clientRequestID == handled.clientRequestID)
    #expect(reopened.statusCode == 429 && reopened.message == handled.message && reopened.accountID == 4 && reopened.createdAt == handled.createdAt)
    let marked = try resolveRow().settingResolved(true)
    #expect(marked.resolved && marked.resolvedAt == nil && RequestDetailPresentation.resolvedNote(marked, now: now, timeZone: zone) == nil)
    let same = handled.settingResolved(true)
    #expect(same.resolvedAt == handled.resolvedAt && same.resolvedByUserName == "admin@example.invalid")
    #expect(RequestDetailPresentation.resolvedNote(same, now: now, timeZone: zone) == RequestDetailPresentation.resolvedNote(handled, now: now, timeZone: zone))
}

@Test func listRowTakesTheMarkInPlace() throws {
    let list = IncrementalList(items: [try resolveRow(30), try resolveRow(20), try resolveRow(10)], cursor: 25)
    let marked = try #require(list.settingResolved(true, id: 20))
    #expect(marked.items.map(\.id) == [30, 20, 10] && marked.items.map(\.resolved) == [false, true, false])
    #expect(marked.cursor == 25 && marked.limit == nil)
    #expect(list.settingResolved(true, id: 99) == nil)
    let back = try #require(marked.settingResolved(false, id: 20))
    #expect(back.items.map(\.resolved) == [false, false, false])
}

@Test func identifiersFollowTheLookAndMenu() throws {
    let usage = RequestDetailLayout.identifiers(try resolveUsage(upstreamID: "upreq-1040"))
    let usageMenu = RequestDetailLayout.menuIdentifiers(usage)
    #expect(usageMenu.map(\.kind) == [.request, .upstream])
    #expect(usageMenu.compactMap(\.kind.menuTitle) == ["复制请求 ID", "复制上游请求 ID"])
    let blanks: [Any] = ["", "  ", NSNull()]
    for blank in blanks {
        #expect(RequestDetailLayout.menuIdentifiers(RequestDetailLayout.identifiers(try resolveUsage(upstreamID: blank))).map(\.kind) == [.request])
    }
    let failed = RequestDetailLayout.identifiers(try resolveRow(), chain: try resolveChain(lastUpstreamID: "up-2"))
    #expect(failed.map(\.kind) == [.request, .client, .upstream])
    #expect(RequestDetailLayout.menuIdentifiers(failed).map(\.kind) == [.request, .upstream])
    #expect(RequestIdentifierRow.Kind.client.menuTitle == nil)
    #expect(RequestDetailLayout.menuIdentifiers(RequestDetailLayout.identifiers(try resolveRow(), chain: nil)).map(\.kind) == [.request])
    #expect(RequestDetailLayout.identifiers(try resolveRow(), chain: try resolveChain(lastUpstreamID: nil)).map(\.kind) == [.request, .client])
    #expect(failed.map(\.kind.copiedReceipt) == ["已复制请求 ID", "已复制服务端请求 ID", "已复制上游请求 ID"])
    let copyable = failed.map(\.isCopyable)
    #expect(copyable == [true, true, true])
    let blankID = RequestDetailLayout.identifiers(try resolveRow(2006, ["request_id": ""]), chain: nil)
    #expect(blankID.first?.isCopyable == false && RequestDetailLayout.menuIdentifiers(blankID).isEmpty)
}
