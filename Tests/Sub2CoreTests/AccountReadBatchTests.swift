import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let readOwner = ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key")
private let versionedAccountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"error_message":null,"concurrency":5}"#
private let noFailures = #""failed_account_ids":[],"degraded":false"#
private let groupEcho = #""failed_account_ids":[],"degraded":false,"group_id":12"#

private func readClient(_ transport: ScriptedTransport, identity: ConditionalCache.Identity? = nil, cache: ConditionalCache = ConditionalCache(),
                        clock: ServerClock = ServerClock()) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate,
              cacheIdentity: identity, conditionalCache: cache, serverClock: clock)
}
private struct SentBatch: Decodable {
    let accountIDs: [Int]
    enum CodingKeys: String, CodingKey { case accountIDs = "account_ids" }
}
private func bodyIDs(_ request: URLRequest?) -> [Int] { (try? JSONDecoder().decode(SentBatch.self, from: request?.httpBody ?? Data()))?.accountIDs ?? [] }
private func bodyText(_ request: URLRequest?) -> String { String(decoding: request?.httpBody ?? Data(), as: UTF8.self) }
private func queryItems(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}
/// `user_cost` is "<id>.5", so a merged value shows which reply it came from.
private func todayJSON(ids: [Int], tail: String = noFailures) -> String {
    let items = ids.map { #""\#($0)":{"requests":\#($0),"tokens":10,"cost":"0.1","standard_cost":"0.2","user_cost":"\#($0).5"}"# }
    return "{\"stats\":{\(items.joined(separator: ","))}" + (tail.isEmpty ? "" : ",\(tail)") + "}"
}
private func runtimeJSON(ids: [Int], sampledAt: String = "2026-10-22T10:00:00Z") -> String {
    let items = ids.map { #""\#($0)":{"current_concurrency":1,"probe_concurrency":0,"concurrency_available":true,"status":"active","schedulable":true,"rate_limit_reset_at":null,"overload_until":null,"temp_unschedulable_until":null}"# }
    return "{\"sampled_at\":\"\(sampledAt)\",\"items\":{\(items.joined(separator: ","))}}"
}
private func tooManyIDs(max limit: String?) -> HTTPResponse {
    let metadata = limit.map { #","metadata":{"field":"account_ids","max":"\#($0)"}"# } ?? #","metadata":{"field":"account_ids"}"#
    return errorReply(400, reason: "TOO_MANY_IDS", extra: metadata)
}

// MARK: - ids

@Test func accountBatchIDsNormalizeSortAndChunk() {
    #expect(AccountBatchIDs.maxPerRequest == 200)
    #expect(AccountBatchIDs.normalized([5, 0, -2, 3, 5, 1]) == [1, 3, 5])
    let chunks = AccountBatchIDs.batches(Array(1...401))
    #expect(chunks.map(\.count) == [200, 200, 1] && chunks.flatMap { $0 } == Array(1...401))
    #expect(AccountBatchIDs.batches([]).isEmpty)
    #expect(AccountBatchIDs.batches(Array(1...120), size: 50).map(\.count) == [50, 50, 20])
    #expect(AccountBatchIDs.batches([3, 1, 2], size: 0) == [[3], [1], [2]])
}

// MARK: - today-stats/batch

@Test func todayBatchSendsNothingForNoPositiveIDs() async throws {
    let transport = ScriptedTransport { _ in okReply(todayJSON(ids: [1])) }
    let client = readClient(transport)
    for (ids, group) in [([Int](), nil), ([0, -3], 12)] as [([Int], Int?)] {
        let batch = try await client.accountTodayStatsBatch(ids: ids, groupID: group)
        #expect(batch.stats.isEmpty && batch.failedIDs.isEmpty && !batch.degraded && batch.groupID == nil)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func todayBatchSplitsAt200InAscendingOrderAndMerges() async throws {
    let transport = ScriptedTransport { request in okReply(todayJSON(ids: bodyIDs(request))) }
    let client = readClient(transport)
    let single = try await client.accountTodayStatsBatch(ids: Array(1...200).shuffled() + [7, 0, -1, 200])
    #expect(single.stats.count == 200)
    #expect(await transport.requests.count == 1)
    let merged = try await client.accountTodayStatsBatch(ids: Array((1...201).reversed()))
    let sent = Array(await transport.requests.dropFirst())
    #expect(sent.map { bodyIDs($0) } == [Array(1...200), [201]])
    #expect(sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/accounts/today-stats/batch" })
    #expect(sent.allSatisfy { $0.timeoutInterval == 20 && sentHeader($0, "Idempotency-Key") == nil })
    #expect(merged.stats.count == 201 && merged.stats[201]?.userCost == Decimal(string: "201.5") && merged.stats[1]?.requests == 1)
    #expect(merged.failedIDs.isEmpty && !merged.degraded && merged.groupID == nil)
}

@Test func todayBatchMatchesFailedIDsAsSetAndDropsPlaceholders() async throws {
    let zero = #"{"requests":0,"tokens":0,"cost":"0","standard_cost":"0","user_cost":"0"}"#
    let reply = #"{"stats":{"3":\#(zero),"5":{"requests":2,"tokens":20,"cost":"0.2","user_cost":"1.25"},"7":\#(zero),"99":\#(zero)},"failed_account_ids":[7,3,42],"degraded":true}"#
    let batch = try await readClient(ScriptedTransport { _ in okReply(reply) }).accountTodayStatsBatch(ids: [7, 5, 3])
    #expect(batch.failedIDs == [3, 7] && Set(batch.stats.keys) == [5] && batch.degraded)
    #expect(batch.stats[5]?.userCost == Decimal(string: "1.25"))
}

@Test func todayBatchTreats503AsWholeBatchFailedWithoutThrowing() async throws {
    let unavailable = errorReply(503, reason: "ACCOUNT_STATS_UNAVAILABLE")
    let transport = ScriptedTransport { request in bodyIDs(request) == [201] ? unavailable : okReply(todayJSON(ids: bodyIDs(request))) }
    let partial = try await readClient(transport).accountTodayStatsBatch(ids: Array(1...201))
    #expect(partial.failedIDs == [201] && partial.stats.count == 200 && partial.stats[201] == nil)
    #expect(await transport.requests.count == 2)
    let whole = try await readClient(ScriptedTransport { _ in unavailable }).accountTodayStatsBatch(ids: [4, 2], groupID: 12)
    #expect(whole.stats.isEmpty && whole.failedIDs == [2, 4] && whole.groupID == nil && !whole.degraded)
}

@Test func todayBatchOtherFailuresThrowTheWholeCall() async throws {
    let serverError = ScriptedTransport { request in bodyIDs(request) == [201] ? errorReply(500) : okReply(todayJSON(ids: bodyIDs(request))) }
    let client = readClient(serverError)
    let failure = try #require(await thrownAPIError { _ = try await client.accountTodayStatsBatch(ids: Array(1...201)) })
    #expect(failure.statusCode == 500 && failure.kind == .temporary)
    #expect(await serverError.requests.count == 2)
    let limited = ScriptedTransport { _ in errorReply(429) }
    let limitedClient = readClient(limited)
    let rateLimit = try #require(await thrownAPIError { _ = try await limitedClient.accountTodayStatsBatch(ids: Array(1...201)) })
    #expect(rateLimit.statusCode == 429 && rateLimit.retryAfter == 30)
    #expect(await limited.requests.count == 1)
}

@Test func todayBatchSendsGroupIDOnlyWhenPositive() async throws {
    let transport = ScriptedTransport { request in okReply(todayJSON(ids: bodyIDs(request))) }
    let client = readClient(transport)
    for group in [nil, 0, -4, 12] as [Int?] { _ = try await client.accountTodayStatsBatch(ids: [2, 1], groupID: group) }
    let plain = #"{"account_ids":[1,2]}"#
    #expect(await transport.requests.map { bodyText($0) } == [plain, plain, plain, #"{"account_ids":[1,2],"group_id":12}"#])
}

@Test func todayBatchReadsGroupEchoOnlyWhenEverySuccessfulBatchEchoes() async throws {
    func echoed(ids: [Int] = [1, 2], _ handler: @escaping @Sendable (URLRequest) -> HTTPResponse) async throws -> Int? {
        try await readClient(ScriptedTransport { handler($0) }).accountTodayStatsBatch(ids: ids, groupID: 12).groupID
    }
    #expect(try await echoed({ okReply(todayJSON(ids: bodyIDs($0), tail: groupEcho)) }) == 12)
    #expect(try await echoed({ okReply(todayJSON(ids: bodyIDs($0))) }) == nil)
    #expect(try await echoed(ids: Array(1...201), { request in
        okReply(todayJSON(ids: bodyIDs(request), tail: bodyIDs(request) == [201] ? noFailures : groupEcho))
    }) == nil)
    #expect(try await echoed(ids: Array(1...201), { okReply(todayJSON(ids: bodyIDs($0), tail: groupEcho)) }) == 12)
    #expect(try await echoed(ids: Array(1...201), { request in
        bodyIDs(request) == [201] ? errorReply(503, reason: "ACCOUNT_STATS_UNAVAILABLE") : okReply(todayJSON(ids: bodyIDs(request), tail: groupEcho))
    }) == 12)
    #expect(try await echoed({ _ in errorReply(503, reason: "ACCOUNT_STATS_UNAVAILABLE") }) == nil)
}

@Test func todayBatchDecodesOldServerWithoutFailureFields() async throws {
    let reply = #"{"stats":{"1":{"requests":3,"tokens":30,"cost":"0.1","user_cost":"0.3"},"3":{"requests":1,"tokens":1,"cost":"not-a-number"}}}"#
    let batch = try await readClient(ScriptedTransport { _ in okReply(reply) }).accountTodayStatsBatch(ids: [1, 2, 3])
    #expect(batch.failedIDs.isEmpty && !batch.degraded && batch.groupID == nil)
    #expect(batch.stats[1]?.userCost == Decimal(string: "0.3") && batch.stats[2] == nil && batch.stats[3] == nil)
}

@Test func todayBatchRevalidatesThroughConditionalCache() async throws {
    let transport = ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == "\"t1\"" ? HTTPResponse(statusCode: 304, headers: ["etag": "\"t1\""], data: Data())
            : okReply(todayJSON(ids: bodyIDs(request)), headers: ["etag": "\"t1\""])
    }
    let client = readClient(transport, identity: readOwner)
    let first = try await client.accountTodayStatsBatch(ids: [2, 1])
    let second = try await client.accountTodayStatsBatch(ids: [1, 2])
    #expect(first.stats[2]?.userCost == Decimal(string: "2.5") && second.stats[2]?.userCost == first.stats[2]?.userCost)
    #expect(Set(second.stats.keys) == [1, 2])
    #expect(await transport.requests.map { sentHeader($0, "If-None-Match") } == [nil, "\"t1\""])
}

@Test func todayBatchRetriesLikeARead() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(502)), .reply(okReply(todayJSON(ids: [1, 2])))])
    let batch = try await readClient(transport).accountTodayStatsBatch(ids: [1, 2])
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.first?.httpBody == sent.last?.httpBody)
    #expect(sentHeader(sent.first, "X-Request-ID") != nil && sentHeader(sent.first, "X-Request-ID") == sentHeader(sent.last, "X-Request-ID"))
    #expect(batch.stats.count == 2)
}

// MARK: - runtime/batch

@Test func runtimeBatchSendsNothingForNoPositiveIDs() async throws {
    let transport = ScriptedTransport { request in okReply(runtimeJSON(ids: bodyIDs(request))) }
    let client = readClient(transport)
    #expect(try await client.accountRuntime(ids: []).isEmpty)
    #expect(try await client.accountRuntime(ids: [0, -1]).isEmpty)
    #expect(await transport.requests.isEmpty)
}

@Test func runtimeBatchSplitsAt200AndSkipsWindowCostByDefault() async throws {
    let transport = ScriptedTransport { request in okReply(runtimeJSON(ids: bodyIDs(request))) }
    let client = readClient(transport)
    let runtime = try await client.accountRuntime(ids: Array((1...401).reversed()) + [0, 3])
    let sent = await transport.requests
    #expect(runtime.count == 401)
    #expect(sent.map { bodyIDs($0) } == [Array(1...200), Array(201...400), [401]])
    #expect(sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/accounts/runtime/batch" && $0.timeoutInterval == 20 })
    #expect(sent.allSatisfy { queryItems($0) == [URLQueryItem(name: "include_window_cost", value: "0")] })
    _ = try await client.accountRuntime(ids: [1], includeWindowCost: true)
    #expect(queryItems(await transport.requests.last).isEmpty)
    #expect(await transport.requests.count == 4)
}

@Test func runtimeBatchDecodesNullCountersAndServerTimes() async throws {
    let reply = #"""
    {"sampled_at":"2026-10-22T10:00:00Z","items":{
     "1":{"current_concurrency":null,"probe_concurrency":null,"concurrency_available":false,"status":"active","schedulable":true,"rate_limit_reset_at":null,"overload_until":null,"temp_unschedulable_until":null},
     "2":{"current_concurrency":3,"probe_concurrency":1,"concurrency_available":true,"current_rpm":12,"scheduling_rpm":10,"active_sessions":2,"current_window_cost":1.25,"status":"error","schedulable":false,"rate_limit_reset_at":"2026-10-22T10:30:00Z","overload_until":"2026-10-22T18:30:00.123456+08:00","temp_unschedulable_until":null},
     "3":{"current_concurrency":1,"concurrency_available":true,"schedulable":true},
     "4":{"current_concurrency":2,"status":"active","schedulable":true}}}
    """#
    let runtime = try await readClient(ScriptedTransport { _ in okReply(reply) }).accountRuntime(ids: [1, 2, 3, 4])
    #expect(Set(runtime.keys) == [1, 2, 4])
    let idle = try #require(runtime[1])
    #expect(idle == AccountRuntime(status: "active", schedulable: true, concurrencyAvailable: false))
    #expect(idle.currentConcurrency == nil && idle.probeConcurrency == nil && !idle.concurrencyAvailable && idle.currentRPM == nil)
    #expect(idle.schedulingRPM == nil && idle.activeSessions == nil && idle.currentWindowCost == nil && idle.rateLimitResetAt == nil)
    let busy = try #require(runtime[2])
    #expect(busy.currentConcurrency == 3 && busy.probeConcurrency == 1 && busy.concurrencyAvailable && busy.currentRPM == 12)
    #expect(busy.schedulingRPM == 10 && busy.activeSessions == 2 && busy.currentWindowCost == Decimal(string: "1.25"))
    #expect(busy.status == "error" && !busy.schedulable && busy.tempUnschedulableUntil == nil)
    let reset = try #require(busy.rateLimitResetAt), overload = try #require(busy.overloadUntil)
    #expect(abs(reset.timeIntervalSince1970 - 1_792_665_000) < 0.001)
    #expect(abs(overload.timeIntervalSince1970 - 1_792_665_000.123) < 0.001)
    // An old item without concurrency_available counts the concurrency it does report.
    #expect(runtime[4]?.concurrencyAvailable == true && runtime[4]?.currentConcurrency == 2)
    #expect(!AccountRuntime(status: "active", schedulable: true).concurrencyAvailable)
    #expect(AccountRuntime(status: "active", schedulable: true, currentConcurrency: 0).concurrencyAvailable)
}

@Test func runtimeBatchKeepsOnlyRequestedIDs() async throws {
    let item = #"{"current_concurrency":0,"concurrency_available":true,"status":"active","schedulable":true}"#
    let reply = #"{"sampled_at":"2026-10-22T10:00:00Z","items":{"1":\#(item),"99":\#(item),"x":\#(item)}}"#
    let runtime = try await readClient(ScriptedTransport { _ in okReply(reply) }).accountRuntime(ids: [1, 2])
    #expect(Array(runtime.keys) == [1])
}

@Test func runtimeBatchResplitsOnceByMetadataMax() async throws {
    let limited = ScriptedTransport { request in
        bodyIDs(request).count > 50 ? tooManyIDs(max: "50") : okReply(runtimeJSON(ids: bodyIDs(request)))
    }
    let runtime = try await readClient(limited).accountRuntime(ids: Array(1...120))
    #expect(runtime.count == 120)
    #expect(await limited.requests.map { bodyIDs($0).count } == [120, 50, 50, 20])
    let stubborn = ScriptedTransport { _ in tooManyIDs(max: "50") }
    let stubbornClient = readClient(stubborn)
    let error = try #require(await thrownAPIError { _ = try await stubbornClient.accountRuntime(ids: Array(1...120)) })
    #expect(error.reason == "TOO_MANY_IDS" && error.category == .batchLimit)
    #expect(await stubborn.requests.count == 2)
    for limit in [nil, "120", "200", "0", "abc"] as [String?] {
        let transport = ScriptedTransport { _ in tooManyIDs(max: limit) }
        let client = readClient(transport)
        #expect(await thrownAPIError { _ = try await client.accountRuntime(ids: Array(1...120)) }?.reason == "TOO_MANY_IDS")
        #expect(await transport.requests.count == 1, "max \(limit ?? "nil")")
    }
}

@Test func runtimeBatchRecordsSampledAtOnServerClock() async throws {
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    let sampled = local.addingTimeInterval(90)
    let stamp = ISO8601DateFormatter().string(from: sampled)
    let clock = ServerClock(localNow: { local })
    let client = readClient(ScriptedTransport { request in okReply(runtimeJSON(ids: bodyIDs(request), sampledAt: stamp)) }, clock: clock)
    _ = try await client.accountRuntime(ids: [1])
    #expect(abs(client.serverClock.now().timeIntervalSince(sampled)) < 0.001)
    let quiet = ServerClock(localNow: { local })
    _ = try await readClient(ScriptedTransport { _ in okReply(#"{"items":{}}"#) }, clock: quiet).accountRuntime(ids: [1])
    #expect(quiet.offset == 0)
}

// MARK: - usage?source=passive

@Test func passiveUsageAlwaysSendsSourcePassive() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"five_hour":null}"#) }
    let client = readClient(transport)
    let usage = try await client.accountPassiveUsage(id: 9)
    #expect(usage.fiveHour == nil)
    let sent = await transport.requests
    #expect(sent.count == 1 && sent.first?.httpMethod == "GET" && sent.first?.url?.path == "/api/v1/admin/accounts/9/usage")
    #expect(queryItems(sent.first) == [URLQueryItem(name: "source", value: "passive")])
    let invalid = try #require(await thrownAPIError { _ = try await client.accountPassiveUsage(id: 0) })
    #expect(invalid.kind == .validation)
    #expect(await transport.requests.count == 1)
}

@Test func passiveUsageDecodesFiveHourWindow() throws {
    func decode(_ json: String) throws -> AccountUsageWindow { try JSONDecoder().decode(AccountUsageWindow.self, from: Data(json.utf8)) }
    let usage = try decode(#"{"five_hour":{"utilization":87.5,"resets_at":"2026-10-22T18:30:00+08:00","remaining_seconds":3600,"window_stats":{"requests":3,"tokens":10,"cost":0.1}},"seven_day":null}"#)
    let window = try #require(usage.fiveHour)
    #expect(window.utilization == 87.5 && window.ratio == 0.875 && window.remainingSeconds == 3600)
    #expect(window.resetsAt == ServerTime.parseTimestamp("2026-10-22T10:30:00Z"))
    #expect(try decode(#"{"five_hour":{"utilization":120,"resets_at":null,"remaining_seconds":0}}"#).fiveHour?.ratio == 1.2)
    for json in [#"{"five_hour":null}"#, #"{}"#, #"{"five_hour":{"resets_at":"2026-10-22T10:30:00Z"}}"#, #"{"five_hour":"soon"}"#] {
        #expect(try decode(json).fiveHour == nil, "\(json)")
    }
    #expect(AccountUsageWindow.Progress(utilization: 50).ratio == 0.5)
}

@Test func passiveUsageAppliesOnlyToAnthropicTokenAccounts() {
    let rows: [(platform: String, type: String, expected: Bool)] = [
        ("anthropic", "oauth", true), ("anthropic", "setup-token", true), ("anthropic", "apikey", false), ("anthropic", "bedrock", false),
        ("openai", "oauth", false), ("antigravity", "oauth", false), ("Anthropic", "oauth", false)
    ]
    for row in rows {
        #expect(AccountUsageWindow.applies(platform: row.platform, type: row.type) == row.expected, "\(row.platform) \(row.type)")
        #expect(AccountUsageWindow.applies(to: UpstreamAccount(id: 1, name: "A", platform: row.platform, type: row.type)) == row.expected)
    }
}

// MARK: - account detail with its version

@Test func versionedAccountReadsETagAndNeverSendsIfNoneMatch() async throws {
    let cache = ConditionalCache()
    let transport = ScriptedTransport { _ in okReply(versionedAccountJSON, headers: ["ETag": "\"cv-12\""]) }
    let client = readClient(transport, identity: readOwner, cache: cache)
    for _ in 0..<2 {
        let versioned = try await client.accountWithVersion(id: 9)
        #expect(versioned.etag == "\"cv-12\"" && versioned.account.id == 9 && versioned.account.platform == "anthropic")
    }
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/v1/admin/accounts/9" })
    #expect(sent.allSatisfy { sentHeader($0, "If-None-Match") == nil })
    #expect(await cache.count == 0)
}

@Test func versionedAccountWithoutETagIsNil() async throws {
    let rows: [(headers: [String: String], expected: String?)] = [([:], nil), (["etag": "  "], nil), (["etag": " W/\"cv-3\" "], "W/\"cv-3\"")]
    for row in rows {
        let versioned = try await readClient(ScriptedTransport { _ in okReply(versionedAccountJSON, headers: row.headers) }).accountWithVersion(id: 9)
        #expect(versioned.etag == row.expected && versioned.account.name == "测试账号")
    }
}

@Test func versionedAccountNotFoundThrows() async throws {
    let client = readClient(ScriptedTransport { _ in errorReply(404, reason: "ACCOUNT_NOT_FOUND") })
    let error = try #require(await thrownAPIError { _ = try await client.accountWithVersion(id: 9) })
    #expect(error.kind == .notFound && error.category == .notFound && error.reason == "ACCOUNT_NOT_FOUND")
}
