import Foundation
import Testing
@testable import Sub2Core

// 40 §7.1 / §7.3: the request detail's sections, 关联, 标识 and Token rows (S4-08).

/// Rows are dictionaries so a test replaces a key instead of sending it twice; NSNull() sends null.
private func layoutDecoded<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}
private func layoutUsage(_ changes: [String: Any] = [:]) throws -> UsageRequestRecord {
    let row: [String: Any] = [
        "id": 1040, "request_id": "client:00000000-0000-4000-8000-000000001040", "created_at": "2026-10-16T01:41:07Z",
        "model": "claude-opus-4", "user_id": 1, "account_id": 4, "api_key_id": 101, "group_id": 2, "input_tokens": 1_200_000,
        "output_tokens": 240, "cache_read_tokens": 0, "cache_creation_tokens": 128, "upstream_request_id": "upreq-1040",
        "user": ["id": 1, "email": "alice@example.com", "username": "Alice"],
        "api_key": ["id": 101, "name": "默认", "key_masked": "sk-…a101", "key": "sk-plaintext-never-shown-123456"],
        "group": ["id": 2, "name": "标准组"], "account": ["id": 4, "name": "OpenAI-主力-01"],
    ]
    return try layoutDecoded(UsageRequestRecord.self, row.merging(changes) { _, new in new })
}
private func errorRowObject(_ changes: [String: Any] = [:]) -> [String: Any] {
    let row: [String: Any] = [
        "id": 2006, "created_at": "2026-10-16T01:41:07Z", "request_id": "req-err-2006", "phase": "upstream", "type": "rate_limit_error",
        "status_code": 429, "platform": "openai", "model": "gpt-4.1", "resolved": false, "message": "上游请求受限", "user_id": 3,
        "user_email": "xm.wang@example.com", "api_key_id": 301, "api_key_name": "脚本", "account_id": 4, "account_name": "OpenAI-主力-01",
        "group_id": 2, "group_name": "标准组", "client_request_id": "00000000-0000-4000-9000-000000002006",
    ]
    return row.merging(changes) { _, new in new }
}
private func layoutErrorRow(_ changes: [String: Any] = [:]) throws -> RequestErrorRecord {
    try layoutDecoded(RequestErrorRecord.self, errorRowObject(changes))
}
private func layoutDetail() throws -> RequestErrorDetail {
    try layoutDecoded(RequestErrorDetail.self, errorRowObject(["api_key_prefix": "sk-abc12XYZ"]))
}
private func layoutChain(lastUpstreamID: String) throws -> RequestAttempts {
    let attempts: [[String: Any]] = [
        ["index": 1, "outcome": "failed", "account_id": 4, "upstream_status_code": 429, "upstream_request_id": "up-1"],
        ["index": 2, "outcome": "failed", "account_id": 7, "upstream_status_code": 429, "upstream_request_id": lastUpstreamID],
    ]
    return try layoutDecoded(RequestAttempts.self, ["client_status_code": 429, "attempts": attempts])
}

@Test func sectionsAndOrdinalsFollowTheLook() {
    let plain = RequestDetailLayout.sections(style: .success, showsAttempts: false)
    #expect(plain == [.timing, .tokens, .links, .identifiers])
    #expect(plain.map { RequestDetailLayout.ordinal($0, in: plain) } == ["壹", "贰", "叁", "肆"])
    let retried = RequestDetailLayout.sections(style: .success, showsAttempts: true)
    #expect(retried == [.timing, .attempts, .tokens, .links, .identifiers])
    #expect(RequestDetailLayout.ordinal(.identifiers, in: retried) == "伍")
    for style in [RequestDetailStyle.recovered, .failed] {
        #expect(RequestDetailLayout.sections(style: style, showsAttempts: true) == [.timing, .attempts, .links, .identifiers])
        #expect(RequestDetailLayout.sections(style: style, showsAttempts: false) == [.timing, .links, .identifiers])
    }
    #expect(RequestDetailLayout.ordinal(.tokens, in: [.timing, .links]) == nil)
    #expect(RequestDetailSection.allCases.map(RequestDetailLayout.title) == ["耗时", "上游尝试", "Token", "关联", "标识"])
}

@Test func successLinksFollowTheTable() throws {
    let links = RequestDetailLayout.links(try layoutUsage())
    #expect(links.map(\.kind) == [.user, .key, .group, .account])
    #expect(links[0] == RequestLinkRow(kind: .user, title: "Alice", trailing: "用户", isMonospacedTrailing: false, targetID: 1))
    #expect(links[1] == RequestLinkRow(kind: .key, title: "默认", trailing: "sk-…a101", isMonospacedTrailing: true, targetID: nil))
    #expect(links[2] == RequestLinkRow(kind: .group, title: "标准组", trailing: "分组", isMonospacedTrailing: false, targetID: 2))
    #expect(links[3] == RequestLinkRow(kind: .account, title: "OpenAI-主力-01", trailing: "账号", isMonospacedTrailing: false, targetID: 4))
    #expect(!String(describing: links).contains("plaintext"))
    let emailOnly = RequestDetailLayout.links(try layoutUsage(["user": ["id": 1, "email": "alice@example.com", "username": ""]]))
    #expect(emailOnly[0].title == "alice@example.com" && emailOnly[0].targetID == 1)
}

@Test func errorLinksFollowTheTable() throws {
    let row = try layoutErrorRow()
    let fromRow = RequestDetailLayout.links(row, detail: nil)
    #expect(fromRow.map(\.title) == ["xm.wang@example.com", "脚本", "标准组", "OpenAI-主力-01"])
    #expect(fromRow.map(\.targetID) == [3, nil, 2, 4])
    #expect(fromRow[1].trailing == nil && fromRow[1].isMonospacedTrailing)
    #expect(fromRow.map(\.trailing) == ["用户", nil, "分组", "账号"])
    let withDetail = RequestDetailLayout.links(row, detail: try layoutDetail())
    #expect(withDetail[1].trailing == "sk-abc12…")
    for unset in [0, NSNull()] as [Any] {
        #expect(RequestDetailLayout.links(try layoutErrorRow(["account_id": unset]), detail: nil)[3].targetID == nil)
    }
}

@Test func missingLinkValuesReadDashAndAreNotTappable() throws {
    let usage = try layoutUsage(["user": ["id": 1, "email": "", "username": " "], "api_key": ["id": 101, "name": ""], "group": NSNull(),
                                 "group_id": NSNull(), "account": ["id": 4, "name": ""]])
    let links = RequestDetailLayout.links(usage)
    #expect(links.map(\.title) == ["—", "—", "—", "—"])
    #expect(links.allSatisfy { $0.targetID == nil })
    #expect(links[1].trailing == nil)
    let row = try layoutErrorRow(["user_email": "", "account_name": "", "group_name": NSNull()])
    let errorLinks = RequestDetailLayout.links(row, detail: nil)
    #expect(errorLinks[0].title == "—" && errorLinks[0].targetID == nil)
    #expect(errorLinks[2].title == "—" && errorLinks[2].targetID == nil)
    #expect(errorLinks[3].title == "—" && errorLinks[3].targetID == nil)
}

@Test func identifierRowsPerLook() throws {
    let usage = RequestDetailLayout.identifiers(try layoutUsage())
    #expect(usage == [RequestIdentifierRow(kind: .request, label: "请求 ID", value: "client:00000000-0000-4000-8000-000000001040"),
                      RequestIdentifierRow(kind: .upstream, label: "上游请求 ID", value: "upreq-1040")])
    #expect(RequestDetailLayout.identifiers(try layoutUsage(["upstream_request_id": NSNull()])).map(\.kind) == [.request])
    let row = try layoutErrorRow()
    let full = RequestDetailLayout.identifiers(row, chain: try layoutChain(lastUpstreamID: "up-2"))
    #expect(full.map(\.kind) == [.request, .client, .upstream])
    #expect(full.map(\.label) == ["请求 ID", "服务端请求 ID", "上游请求 ID"])
    #expect(full.map(\.value) == ["req-err-2006", "00000000-0000-4000-9000-000000002006", "up-2"])
    #expect(RequestDetailLayout.identifiers(row, chain: nil).map(\.kind) == [.request, .client])
    #expect(RequestDetailLayout.identifiers(row, chain: try layoutChain(lastUpstreamID: "")).map(\.kind) == [.request, .client])
    let old = try layoutErrorRow(["client_request_id": NSNull()])
    #expect(RequestDetailLayout.identifiers(old, chain: try layoutChain(lastUpstreamID: "up-2")).map(\.kind) == [.request, .upstream])
}

@Test func tokenCellsAreGroupedInOrder() throws {
    let cells = RequestDetailLayout.tokenCells(try layoutUsage())
    #expect(cells.map(\.label) == ["输入", "输出", "缓存读", "缓存写"])
    #expect(cells.map(\.value) == ["1,200,000", "240", "0", "128"])
}

@Test func recoveredFallbackWithoutSuccessDoesNotBlameTheClient() throws {
    let events = [UpstreamErrorEvent(accountID: 3, accountName: "Claude-官方-03", upstreamStatusCode: 429, atUnixMs: 1_792_114_865_000, durationMs: 400),
                  UpstreamErrorEvent(accountID: 3, accountName: "Claude-官方-03", upstreamStatusCode: 429, atUnixMs: 1_792_114_866_000)]
    let plain = RequestDetailPresentation.fallbackRows(events: events, success: nil)
    let recovered = RequestDetailPresentation.fallbackRows(events: events, success: nil, clientSucceeded: true)
    #expect(recovered.count == 2)
    #expect(recovered[0] == plain[0])
    #expect(recovered[1].subtitle == "失败，后续尝试未记录")
    #expect(recovered[1].trailing == plain[1].trailing && recovered[1].tone == plain[1].tone && recovered[1].id == plain[1].id)
    #expect(RequestDetailPresentation.fallbackRows(events: events, success: nil, clientSucceeded: false) == plain)
    let success = try layoutUsage()
    #expect(RequestDetailPresentation.fallbackRows(events: events, success: success, clientSucceeded: true)
            == RequestDetailPresentation.fallbackRows(events: events, success: success))
    #expect(RequestDetailPresentation.fallbackRows(events: [], success: nil, clientSucceeded: true).isEmpty)
}
