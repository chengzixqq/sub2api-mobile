import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §7.2 / §7.5: where the request detail reads from and what it shows meanwhile (S4-08).

/// Records every read and answers through closures; `call` counts from 1 per read kind.
private actor RequestDetailStub {
    struct ChainCall: Sendable, Equatable {
        let id: String
        let around: Date?
    }
    typealias UsageHandler = @Sendable (_ call: Int, _ filter: RequestLogFilter) async throws -> UsageRequestRecord?
    typealias DetailHandler = @Sendable (_ call: Int) async throws -> RequestErrorDetail
    typealias ChainHandler = @Sendable (_ call: Int, _ id: String) async throws -> RequestAttempts
    private let onUsage: UsageHandler
    private let onDetail: DetailHandler
    private let onChain: ChainHandler
    private(set) var usageFilters: [RequestLogFilter] = []
    private(set) var detailReads: [Int] = []
    private(set) var chainCalls: [ChainCall] = []

    init(usage: @escaping UsageHandler = { _, _ in nil }, detail: @escaping DetailHandler = { _ in try detailReply() },
         chain: @escaping ChainHandler = { _, _ in throw APIError.server(status: 404, reason: "OPS_REQUEST_NOT_FOUND") }) {
        onUsage = usage; onDetail = detail; onChain = chain
    }
    func usage(_ filter: RequestLogFilter) async throws -> UsageRequestRecord? {
        usageFilters.append(filter)
        return try await onUsage(usageFilters.count, filter)
    }
    func detail(_ id: Int, _ kind: ErrorLogKind) async throws -> RequestErrorDetail {
        detailReads.append(id)
        return try await onDetail(detailReads.count)
    }
    func chain(_ id: String, _ around: Date?) async throws -> RequestAttempts {
        chainCalls.append(ChainCall(id: id, around: around))
        return try await onChain(chainCalls.count, id)
    }
    nonisolated var source: RequestDetailSource {
        RequestDetailSource(usageRecord: { try await self.usage($0) }, errorDetail: { try await self.detail($0, $1) },
                            attempts: { try await self.chain($0, $1) })
    }
}

/// The model's session flag, ops switch and clocks, and what it reported to LiveOpsStore (“nil” for a success).
@MainActor private final class DetailHarness {
    var isCurrent = true
    var opsEnabled = true
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Server minus phone time, as ServerClock keeps it; `phone` moves with `now`.
    var serverOffset: TimeInterval = 0
    var phone: Date { now.addingTimeInterval(-serverOffset) }
    /// S4-08b's write epoch.
    var epoch = 0
    private(set) var reports: [String] = []

    func model(_ route: RequestRoute, _ stub: RequestDetailStub, attemptsSupported: Bool = true) -> RequestDetailModel {
        RequestDetailModel(route: route, source: stub.source, attemptsSupported: attemptsSupported, isOpsEnabled: { self.opsEnabled },
                           isCurrent: { self.isCurrent },
                           onOpsResponse: { error in self.reports.append(error.map { ($0 as? APIError)?.reason ?? "other" } ?? "nil") },
                           now: { self.now }, phoneNow: { self.phone }, writeEpoch: { self.epoch })
    }
}

private let detailStamp = "2026-10-16T01:41:07Z"
private let detailCreatedAt = ServerTime.parseTimestamp("2026-10-16T01:41:07Z")!
private let detailClientID = "00000000-0000-4000-9000-000000002006"
private let notFoundChain = APIError.server(status: 404, reason: "OPS_REQUEST_NOT_FOUND")
private let goneDetail = APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND")
private let opsOffReply = APIError.server(status: 404, reason: "OPS_DISABLED")
private let serverFailure = APIError.server(status: 500, reason: "OPS_ERROR_LOAD_FAILED")

private func detailDecoded<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}
private func detailUsage(_ changes: [String: Any] = [:]) throws -> UsageRequestRecord {
    let row: [String: Any] = [
        "id": 1040, "request_id": "client:00000000-0000-4000-8000-000000001040", "created_at": detailStamp, "model": "claude-opus-4",
        "user_id": 1, "account_id": 1, "api_key_id": 101, "duration_ms": 3_200, "first_token_ms": 1_200,
        "account": ["id": 1, "name": "Claude-官方-01"],
    ]
    return try detailDecoded(UsageRequestRecord.self, row.merging(changes) { _, new in new })
}
private func detailRowObject(_ changes: [String: Any] = [:]) -> [String: Any] {
    let row: [String: Any] = [
        "id": 2006, "created_at": detailStamp, "request_id": "req-err-2006", "phase": "upstream", "type": "rate_limit_error",
        "status_code": 429, "platform": "openai", "model": "gpt-4.1", "resolved": false, "message": "上游请求受限", "account_id": 4,
        "account_name": "OpenAI-主力-01", "client_request_id": detailClientID,
    ]
    return row.merging(changes) { _, new in new }
}
private func detailRow(_ changes: [String: Any] = [:]) throws -> RequestErrorRecord {
    try detailDecoded(RequestErrorRecord.self, detailRowObject(changes))
}
/// Two failed tries: the second has no duration, so the fallback estimates it from the gap (1.0s).
private func detailEvents() -> [[String: Any]] {
    [["account_id": 4, "account_name": "OpenAI-主力-01", "upstream_status_code": 429, "at_unix_ms": 1_792_114_865_000, "duration_ms": 400,
      "dropped_earlier_attempts": 2],
     ["account_id": 7, "account_name": "OpenAI-备用-A", "upstream_status_code": 500, "at_unix_ms": 1_792_114_866_000]]
}
private func detailReply(_ changes: [String: Any] = [:], events: [[String: Any]] = detailEvents()) throws -> RequestErrorDetail {
    let list = String(decoding: try JSONSerialization.data(withJSONObject: events), as: UTF8.self)
    let fields: [String: Any] = ["upstream_status_code": 429, "upstream_errors": list, "auth_latency_ms": 12, "api_key_prefix": "sk-abc12"]
    return try detailDecoded(RequestErrorDetail.self, detailRowObject(fields.merging(changes) { _, new in new }))
}
/// `count` tries, the last one a success when the client got 200.
private func detailChain(count: Int, clientStatus: Int = 200) throws -> RequestAttempts {
    let attempts: [[String: Any]] = (1...count).map { index in
        let isLast = index == count, succeeded = isLast && clientStatus == 200
        return ["index": index, "outcome": succeeded ? "success" : "failed", "account_id": index, "account_name": "账号 \(index)",
                "upstream_status_code": succeeded ? 200 : 429, "upstream_request_id": "up-\(index)", "duration_ms": 400]
    }
    return try detailDecoded(RequestAttempts.self, ["client_status_code": clientStatus, "attempts": attempts])
}
private func ambiguousReply(_ ids: [String], times: [Date]) -> APIError {
    let metadata = ["client_request_ids": ids.joined(separator: ","), "client_request_id_times": times.map(ServerTime.utcTimestamp).joined(separator: ",")]
    return APIError.server(status: 409, envelope: ErrorEnvelope(reason: "OPS_REQUEST_AMBIGUOUS", metadata: metadata))
}

/// Up to five seconds: under `swift test --parallel` a child task can take a while to be scheduled.
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

// MARK: - 成功样子

@MainActor @Test func usageRowDrawsAtOnceAndReadsItsChain() async throws {
    let harness = DetailHarness(), gate = SessionGate(), usage = try detailUsage()
    let stub = RequestDetailStub(chain: { _, _ in await gate.wait(); return try detailChain(count: 2) })
    let model = harness.model(.usage(RoutePreload(usage)), stub)
    #expect(model.page == .content && model.usage?.id == 1040 && model.style == .success)
    let loading = Task { await model.load() }
    #expect(await eventually { await gate.arrived })
    #expect(model.attempts == .hidden)
    await gate.open()
    await loading.value
    #expect(await stub.chainCalls == [RequestDetailStub.ChainCall(id: "client:00000000-0000-4000-8000-000000001040", around: detailCreatedAt)])
    #expect(model.showsAttempts && model.sections == [.timing, .attempts, .tokens, .links, .identifiers])
    #expect(model.attemptsMeta == "2 次 · 返回客户端 200")
    #expect(model.hasLoaded)
    let single = harness.model(.usage(RoutePreload(usage)), RequestDetailStub(chain: { _, _ in try detailChain(count: 1) }))
    await single.load()
    #expect(single.chain != nil && !single.showsAttempts && !single.sections.contains(.attempts))
}

@MainActor @Test func successChainFailuresHideTheSection() async throws {
    let harness = DetailHarness(), usage = try detailUsage()
    for failure in [notFoundChain, .server(status: 400, reason: "INVALID_REQUEST_ID"), serverFailure] {
        let stub = RequestDetailStub(chain: { _, _ in throw failure })
        let model = harness.model(.usage(RoutePreload(usage)), stub)
        await model.load()
        let calls = await stub.chainCalls.count
        #expect(model.attempts == .hidden && calls == 1, "\(failure)")
    }
    let slashed = try detailUsage(["request_id": "local:a/b"])
    let unsupported: [(RequestDetailModel, RequestDetailStub)] = [
        { let stub = RequestDetailStub(); return (harness.model(.usage(RoutePreload(slashed)), stub), stub) }(),
        { let stub = RequestDetailStub(); return (harness.model(.usage(RoutePreload(usage)), stub, attemptsSupported: false), stub) }(),
    ]
    for (model, stub) in unsupported {
        await model.load()
        let calls = await stub.chainCalls.count
        #expect(model.attempts == .hidden && calls == 0)
    }
    harness.opsEnabled = false
    let offStub = RequestDetailStub()
    await harness.model(.usage(RoutePreload(usage)), offStub).load()
    #expect(await offStub.chainCalls.isEmpty)
    harness.opsEnabled = true
    let disabled = harness.model(.usage(RoutePreload(usage)), RequestDetailStub(chain: { _, _ in throw opsOffReply }))
    await disabled.load()
    #expect(disabled.attempts == .hidden && harness.reports == ["OPS_DISABLED"])
}

@MainActor @Test func usageRequestIDLookup() async throws {
    let harness = DetailHarness(), usage = try detailUsage(), requestID = "client:00000000-0000-4000-8000-000000001040"
    let empty = RequestDetailStub()
    let missing = harness.model(.usageRequestID(requestID), empty)
    #expect(missing.page == .loading && missing.usage == nil)
    await missing.load()
    #expect(missing.page == .gone)
    let filter = await empty.usageFilters.first
    #expect(filter?.time == LogTimeWindow.none && filter?.requestID == requestID && filter?.pageSize == 1)

    let stub = RequestDetailStub(usage: { call, _ in
        guard call > 1 else { throw serverFailure }
        return usage
    }, chain: { _, _ in try detailChain(count: 2) })
    let model = harness.model(.usageRequestID(requestID), stub)
    await model.load()
    #expect(model.page == .failed && model.pageError?.statusCode == 500)
    #expect(await stub.chainCalls.isEmpty)
    await model.load()
    #expect(model.page == .content && model.usage?.id == 1040 && model.pageError == nil && model.showsAttempts)
    await model.load()
    #expect(await stub.usageFilters.count == 2)
    #expect(await stub.chainCalls.count == 2)
}

// MARK: - 失败类：详情

@MainActor @Test func errorRowDrawsAtOnceAndDetailFillsIn() async throws {
    let harness = DetailHarness(), detailGate = SessionGate(), chainGate = SessionGate(), row = try detailRow()
    let stub = RequestDetailStub(detail: { _ in await detailGate.wait(); return try detailReply() },
                                 chain: { _, _ in await chainGate.wait(); return try detailChain(count: 2, clientStatus: 429) })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), stub)
    #expect(model.page == .content && model.record?.id == 2006 && model.record?.upstreamStatusCode == nil && model.style == .failed)
    let loading = Task { await model.load() }
    #expect(await eventually { let detailArrived = await detailGate.arrived; let chainArrived = await chainGate.arrived; return detailArrived && chainArrived })
    #expect(model.detail.isLoading && model.attempts == .loading && model.showsAttempts)
    await detailGate.open()
    await chainGate.open()
    await loading.value
    #expect(model.detail.value != nil && model.record?.upstreamStatusCode == 429 && model.detailRevision == 1)
    #expect(model.chain?.attempts.count == 2 && model.attemptsMeta == "2 次 · 返回客户端 429")
    #expect(model.sections == [.timing, .attempts, .links, .identifiers])
    #expect(harness.reports == ["nil", "nil"])
}

@MainActor @Test func errorWithoutRowWaitsForDetailThenReadsChain() async throws {
    let harness = DetailHarness(), gate = SessionGate()
    let stub = RequestDetailStub(detail: { _ in
        await gate.wait()
        return try detailReply(["id": 9701, "client_request_id": "cid-9701", "status_code": 401])
    }, chain: { _, _ in try detailChain(count: 3, clientStatus: 401) })
    let model = harness.model(.error(id: 9701, kind: .upstream), stub)
    #expect(model.page == .loading && model.record == nil)
    let loading = Task { await model.load() }
    #expect(await eventually { await gate.arrived })
    #expect(await stub.chainCalls.isEmpty)
    await gate.open()
    await loading.value
    #expect(await stub.detailReads == [9701])
    #expect(model.page == .content && model.record?.id == 9701)
    #expect(await stub.chainCalls == [RequestDetailStub.ChainCall(id: "cid-9701", around: detailCreatedAt)])
    #expect(model.attemptsMeta == "3 次 · 返回客户端 401")
}

@MainActor @Test func detailNotFoundFillsThePage() async throws {
    let harness = DetailHarness()
    let withRow = RequestDetailStub(detail: { _ in throw goneDetail })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), withRow, attemptsSupported: false)
    await model.load()
    #expect(model.page == .gone && model.attempts == .hidden)
    #expect(await withRow.usageFilters.isEmpty)
    await model.load()
    #expect(await withRow.detailReads.count == 1)
    let withoutRow = RequestDetailStub(detail: { _ in throw goneDetail })
    let entered = harness.model(.error(id: 9701, kind: .upstream), withoutRow)
    await entered.load()
    #expect(entered.page == .gone)
    #expect(await withoutRow.chainCalls.isEmpty)
}

@MainActor @Test func detailOpsDisabledKeepsTheRow() async throws {
    let harness = DetailHarness()
    let stub = RequestDetailStub(detail: { _ in throw opsOffReply }, chain: { _, _ in throw opsOffReply })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), stub)
    await model.load()
    #expect(model.page == .content && model.detail.disabledReason == "OPS_DISABLED" && model.attempts == .hidden)
    #expect(harness.reports.contains("OPS_DISABLED"))
    let entered = harness.model(.error(id: 9701, kind: .upstream), RequestDetailStub(detail: { _ in throw opsOffReply }))
    await entered.load()
    #expect(entered.page == .opsDisabled)
}

@MainActor @Test func detailFailureKeepsTheRowAndRetries() async throws {
    let harness = DetailHarness()
    let stub = RequestDetailStub(detail: { call in
        guard call > 1 else { throw serverFailure }
        return try detailReply()
    })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), stub, attemptsSupported: false)
    await model.load()
    #expect(model.page == .content && model.detail.failureReason != nil && model.detailError?.statusCode == 500)
    #expect(model.detailRevision == 0)
    await model.load()
    #expect(model.detail.value != nil && model.detailError == nil && model.detailRevision == 1)

    let throttled = RequestDetailStub(detail: { _ in throw APIError.server(status: 429, reason: "RATE_LIMITED") })
    let waiting = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), throttled)
    await waiting.load()
    #expect(waiting.detailRefresh.notBefore != nil)
    harness.now = harness.now.addingTimeInterval(5)
    await waiting.load()
    #expect(await throttled.detailReads.count == 1)
}

/// The failure row counts the wait down and reads again on the phone's clock (BlockFailureRow); a site clock behind the
/// phone's (the Date header is cut to the second) must not hold that read back.
@MainActor @Test func detailThrottleWaitRunsOnThePhoneClock() async throws {
    let harness = DetailHarness()
    harness.serverOffset = -1
    let limited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30)
    let stub = RequestDetailStub(detail: { call in
        guard call > 1 else { throw limited }
        return try detailReply()
    })
    let model = harness.model(.error(id: 9701, kind: .upstream), stub, attemptsSupported: false)
    await model.load()
    #expect(model.page == .failed)
    let notBefore = try #require(model.detailRefresh.notBefore)
    #expect(notBefore == harness.phone.addingTimeInterval(30))
    // ResendAfterWait sleeps `notBefore.timeIntervalSinceNow`, then the row calls retry.
    harness.now = harness.now.addingTimeInterval(notBefore.timeIntervalSince(harness.phone))
    await model.load()
    #expect(await stub.detailReads.count == 2)
    #expect(model.page == .content)
}

@MainActor @Test func opsOffSendsNoOpsRequest() async throws {
    let harness = DetailHarness()
    harness.opsEnabled = false
    let stub = RequestDetailStub()
    let withRow = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), stub)
    await withRow.load()
    #expect(withRow.page == .content && withRow.detail.disabledReason == "OPS_DISABLED" && withRow.attempts == .hidden)
    let withoutRow = harness.model(.error(id: 9701, kind: .upstream), stub)
    await withoutRow.load()
    #expect(withoutRow.page == .opsDisabled)
    #expect(await stub.detailReads.isEmpty)
    #expect(await stub.chainCalls.isEmpty)
}

// MARK: - 失败类：上游尝试

@MainActor @Test func failedChainUsesClientRequestIDFirst() async throws {
    let harness = DetailHarness()
    let cases: [([String: Any], String?)] = [([:], detailClientID), (["client_request_id": NSNull()], "req-err-2006"),
                                             (["client_request_id": NSNull(), "request_id": "local:a/b"], nil)]
    for (changes, expected) in cases {
        let stub = RequestDetailStub()
        let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow(changes))), stub)
        await model.load()
        let calls = await stub.chainCalls
        let expectedCalls = expected.map { [RequestDetailStub.ChainCall(id: $0, around: detailCreatedAt)] } ?? []
        #expect(calls == expectedCalls, "\(changes)")
        #expect(model.attemptRows.count == 2, "\(changes)")
    }
}

@MainActor @Test func ambiguousAsksTheClosestOnce() async throws {
    let harness = DetailHarness()
    let candidates = ambiguousReply(["cid-new", "cid-near"], times: [detailCreatedAt.addingTimeInterval(3_000), detailCreatedAt.addingTimeInterval(2)])
    let row = try detailRow(["client_request_id": NSNull()])
    let resolved = RequestDetailStub(chain: { call, _ in
        guard call > 1 else { throw candidates }
        return try detailChain(count: 2)
    })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), resolved)
    await model.load()
    #expect(await resolved.chainCalls.map(\.id) == ["req-err-2006", "cid-near"])
    #expect(model.chain?.attempts.count == 2)

    let twice = RequestDetailStub(chain: { _, _ in throw candidates })
    let fallback = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), twice)
    await fallback.load()
    #expect(await twice.chainCalls.count == 2)
    #expect(fallback.attemptRows.count == 2 && fallback.chain == nil)

    let itself = RequestDetailStub(chain: { _, _ in throw ambiguousReply(["req-err-2006"], times: [detailCreatedAt]) })
    await harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), itself).load()
    #expect(await itself.chainCalls.count == 1)
}

@MainActor @Test func fallbackBuildsRowsFromDetailEvents() async throws {
    let harness = DetailHarness()
    let failedStub = RequestDetailStub()
    let failed = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), failedStub, attemptsSupported: false)
    await failed.load()
    #expect(await failedStub.chainCalls.isEmpty)
    #expect(failed.attemptRows.count == 2 && failed.attemptRows[1].trailing == "500 · 约 1.0s")
    #expect(failed.droppedNote == "更早的 2 次尝试因队列上限没有记录")
    #expect(failed.attemptsMeta == "2 次 · 返回客户端 429")

    let recoveredRow = try detailRow(["status_code": 200])
    let found = try detailUsage(["account": ["id": 3, "name": "Claude-官方-03"], "account_id": 3])
    let foundStub = RequestDetailStub(usage: { _, _ in found }, detail: { _ in try detailReply(["status_code": 200]) })
    let recovered = harness.model(.error(id: 3005, kind: .upstream, initial: RoutePreload(recoveredRow)), foundStub, attemptsSupported: false)
    #expect(recovered.style == .recovered)
    await recovered.load()
    let filter = await foundStub.usageFilters.first
    #expect(filter?.requestID == "client:" + detailClientID && filter?.time == LogTimeWindow.none && filter?.pageSize == 1)
    #expect(recovered.attemptRows.map(\.subtitle).last == "成功，结果返回客户端" && recovered.attemptRows.count == 3)

    let lookups: [RequestDetailStub.UsageHandler] = [{ _, _ in nil }, { _, _ in throw serverFailure }]
    for usage in lookups {
        let stub = RequestDetailStub(usage: usage, detail: { _ in try detailReply(["status_code": 200]) })
        let model = harness.model(.error(id: 3005, kind: .upstream, initial: RoutePreload(recoveredRow)), stub, attemptsSupported: false)
        await model.load()
        #expect(model.attemptRows.count == 2 && model.attemptRows.last?.subtitle == "失败，后续尝试未记录")
    }
    let quiet = RequestDetailStub(detail: { _ in try detailReply(events: []) })
    let none = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), quiet, attemptsSupported: false)
    await none.load()
    #expect(none.attempts == .hidden && !none.sections.contains(.attempts))
}

@MainActor @Test func fallbackFailsWithTheDetail() async throws {
    let harness = DetailHarness()
    let stub = RequestDetailStub(detail: { _ in throw serverFailure }, chain: { _, _ in throw APIError.server(status: 503, reason: "OPS_REPO_UNAVAILABLE") })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())), stub)
    await model.load()
    #expect(model.attempts == .unavailable && model.showsAttempts && model.sections.contains(.attempts))
    let disabled = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(try detailRow())),
                                 RequestDetailStub(detail: { _ in throw opsOffReply }, chain: { _, _ in throw serverFailure }))
    await disabled.load()
    #expect(disabled.attempts == .hidden)
}

// MARK: - 过时回复

@MainActor @Test func staleRepliesAreDropped() async throws {
    let harness = DetailHarness(), row = try detailRow()
    let gate = SessionGate()
    let ended = RequestDetailStub(detail: { _ in await gate.wait(); return try detailReply(["message": "late"]) })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), ended, attemptsSupported: false)
    let loading = Task { await model.load() }
    #expect(await eventually { await gate.arrived })
    harness.isCurrent = false
    await gate.open()
    await loading.value
    #expect(model.record?.message == "上游请求受限" && model.detailRevision == 0)

    harness.isCurrent = true
    let firstGate = SessionGate()
    let racing = RequestDetailStub(detail: { call in
        if call == 1 { await firstGate.wait(); return try detailReply(["message": "first"]) }
        return try detailReply(["message": "second"])
    })
    let raced = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), racing, attemptsSupported: false)
    let first = Task { await raced.load() }
    #expect(await eventually { await firstGate.arrived })
    await raced.load()
    await firstGate.open()
    await first.value
    #expect(raced.record?.message == "second" && raced.detailRevision == 1)

    let cancelGate = SessionGate()
    let cancelling = RequestDetailStub(detail: { call in
        guard call > 1 else { return try detailReply(["message": "kept"]) }
        await cancelGate.wait()
        try Task.checkCancellation()
        return try detailReply(["message": "never"])
    })
    let kept = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), cancelling, attemptsSupported: false)
    await kept.load()
    let cancelled = Task { await kept.load() }
    #expect(await eventually { await cancelGate.arrived })
    cancelled.cancel()
    await cancelGate.open()
    await cancelled.value
    #expect(kept.detail.value?.record.message == "kept" && !kept.detail.isLoading && kept.detailRevision == 1)
}

/// S4-08b: a detail keeps the write epoch of when its read went out, not of when it arrived.
@MainActor @Test func detailKeepsTheWriteEpochOfItsRead() async throws {
    let harness = DetailHarness(), gate = SessionGate(), row = try detailRow()
    let stub = RequestDetailStub(detail: { call in
        if call == 1 { await gate.wait() }
        return try detailReply()
    })
    let model = harness.model(.error(id: 2006, kind: .request, initial: RoutePreload(row)), stub, attemptsSupported: false)
    let loading = Task { await model.load() }
    #expect(await eventually { await gate.arrived })
    harness.epoch = 2
    await gate.open()
    await loading.value
    #expect(model.detailRevision == 1 && model.detailEpoch == 0)
    await model.load()
    #expect(model.detailRevision == 2 && model.detailEpoch == 2)
}

// MARK: - 线上数据源

@Test func liveSourceSendsKeyViewOnlyWithCapability() async throws {
    let usage = try JSONSerialization.data(withJSONObject: [
        "id": 1040, "request_id": "client:x", "created_at": detailStamp, "model": "m", "user_id": 1, "account_id": 1, "api_key_id": 1,
    ] as [String: Any])
    let page = #"{"items":["# + String(decoding: usage, as: UTF8.self) + #"],"total":null,"page":1,"page_size":1,"pages":null,"has_more":false}"#
    let detail = String(decoding: try JSONSerialization.data(withJSONObject: detailRowObject(["id": 9701])), as: UTF8.self)
    let transport = SessionTransport { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/admin/usage") { return sessionOK(page) }
        if path.hasSuffix("/attempts") { return sessionOK(#"{"client_status_code":200,"attempts":[]}"#) }
        return sessionOK(detail)
    }
    let client = sessionClient(transport)
    let filter = RequestLogFilter(time: .none, requestID: "client:x", pageSize: 1)
    let found = try await RequestDetailSource.live(client, site: liveOpsSite([.apiKeysMaskedView])).usageRecord(filter)
    #expect(found?.id == 1040)
    _ = try await RequestDetailSource.live(client, site: liveOpsSite([])).usageRecord(filter)
    let plain = RequestDetailSource.live(client, site: liveOpsSite([.apiKeysMaskedView]))
    _ = try await plain.errorDetail(9701, .upstream)
    _ = try await plain.errorDetail(2006, .request)
    _ = try await plain.attempts("cid-1", detailCreatedAt)
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/v1/admin/usage", "/api/v1/admin/usage", "/api/v1/admin/ops/upstream-errors/9701",
                                              "/api/v1/admin/ops/request-errors/2006", "/api/v1/admin/ops/requests/cid-1/attempts"])
    let queries = requests.map { request in
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                   uniquingKeysWith: { first, _ in first })
    }
    #expect(queries[0]["key_view"] == "masked" && queries[0]["request_id"] == "client:x")
    #expect(queries[0]["page"] == "1" && queries[0]["page_size"] == "1")
    #expect(queries[0]["start_time"] == nil && queries[0]["end_time"] == nil)
    #expect(queries[1]["key_view"] == nil && queries[1]["request_id"] == "client:x")
    #expect(queries[4]["around"] == detailStamp)
}
