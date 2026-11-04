import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 40 §0.6 / §1.3 the degraded fan-out, four at a time, and the old server's segment-by-segment profit (S4-13b).

private struct FanOutFailure: Error {}
private struct StopMarker: Error {}

/// How many operations run at once, and the most there ever were.
private actor InFlight {
    private(set) var peak = 0
    private(set) var calls = 0
    private var current = 0
    func enter() { current += 1; calls += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

@Test func fanOutKeepsInputOrderAndTurnsFailuresIntoNil() async throws {
    let values = try await AnalyticsFanOut.map(Array(0..<6)) { input -> Int in
        if input == 2 || input == 4 { throw FanOutFailure() }
        try await Task.sleep(for: .milliseconds(6 - input))
        return input * 10
    }
    #expect(values == [0, 10, nil, 30, nil, 50])
    #expect(try await AnalyticsFanOut.map([Int]()) { $0 }.isEmpty)
}

@Test func fanOutNeverHasMoreThanTheLimitInFlight() async throws {
    #expect(AnalyticsFanOut.maxConcurrent == 4)
    for (limit, expected) in [(AnalyticsFanOut.maxConcurrent, 2...4), (1, 1...1)] {
        let inFlight = InFlight()
        _ = try await AnalyticsFanOut.map(Array(0..<12), limit: limit) { input -> Int in
            await inFlight.enter()
            try await Task.sleep(for: .milliseconds(20))
            await inFlight.leave()
            return input
        }
        #expect(expected.contains(await inFlight.peak))
        #expect(await inFlight.calls == 12)
    }
}

@Test func fanOutStopsLaunchingAfterAStoppingError() async throws {
    let inFlight = InFlight()
    let values = try await AnalyticsFanOut.map(Array(0..<5), limit: 1, stopsAfter: { $0 is StopMarker }) { input -> Int in
        await inFlight.enter()
        await inFlight.leave()
        if input == 2 { throw StopMarker() }
        return input
    }
    #expect(values == [0, 1, nil, nil, nil])
    #expect(await inFlight.calls == 3)
}

@Test func fanOutResultsKeepEachErrorAndLeaveSkippedInputsNil() async throws {
    let inFlight = InFlight()
    let results = try await AnalyticsFanOut.results(Array(0..<5), limit: 1, stopsAfter: { $0 is StopMarker }) { input -> Int in
        await inFlight.enter()
        await inFlight.leave()
        if input == 1 { throw StopMarker() }
        return input
    }
    #expect(results.count == 5)
    #expect((try? results[0]?.get()) == 0)
    if case .failure(let error)? = results[1] { #expect(error is StopMarker) } else { Issue.record("\(String(describing: results[1]))") }
    #expect(results[2...].allSatisfy { $0 == nil })
    #expect(await inFlight.calls == 2)
    // A failure that does not stop keeps its error and the rest go on.
    let mixed = try await AnalyticsFanOut.results([0, 1, 2]) { input -> Int in
        if input == 1 { throw FanOutFailure() }
        return input
    }
    if case .failure(let error)? = mixed[1] { #expect(error is FanOutFailure) } else { Issue.record("\(String(describing: mixed[1]))") }
    #expect((try? mixed[2]?.get()) == 2)
}

@Test func fanOutThrowsCancellationWhenTheCallerIsCancelled() async {
    let task = Task {
        try await AnalyticsFanOut.map(Array(0..<8)) { input -> Int in
            try await Task.sleep(for: .seconds(30))
            return input
        }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

// MARK: - 旧服务端逐段利润

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai: today has 10 hourly buckets, the last one running.
private let today = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-16T01:41:00Z"), zone: shanghai)

private func segmentClient(_ transport: ScriptedTransport) -> APIClient {
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://analysis.example.invalid")!, authentication: .adminKey)
    return APIClient(server: profile, credential: .adminKey("fixture"), transport: transport, requestClock: .immediate, serverTimeZone: shanghai)
}
private func sentItems(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func stats(accountCost: String?) -> HTTPResponse {
    okReply(#"{"total_requests":3,"total_tokens":30,"total_actual_cost":"5.00""# + (accountCost.map { #","total_account_cost":"\#($0)""# } ?? "") + "}")
}

@Test func profitSegmentCostsSendsOneStatsPerBucketWithTheRangeFilter() async throws {
    let buckets = Array(today.buckets[7...9])
    let costs = Dictionary(uniqueKeysWithValues: zip(buckets.map { ServerTime.utcTimestamp($0.start) },
                                                     ["1.25", "2.50", "0.75"]))
    let transport = ScriptedTransport { request in stats(accountCost: costs[sentItems(request)["start_time"] ?? ""]) }
    let query = AnalyticsQuery(start: today.start, end: today.end, granularity: .hour, timeZone: shanghai, groupID: 2,
                               model: "claude-opus-4", modelSource: .requested)
    let read = try await segmentClient(transport).profitSegmentCosts(query, buckets: buckets)
    let requests = await transport.requests(path: "admin/usage/stats")
    #expect(requests.count == 3)
    let sent = requests.map(sentItems)
    #expect(Set(sent.map { [$0["start_time"] ?? "", $0["end_time"] ?? ""] })
        == Set(buckets.map { [ServerTime.utcTimestamp($0.start), ServerTime.utcTimestamp($0.end)] }))
    for items in sent {
        #expect(items["timezone"] == "Asia/Shanghai" && items["group_id"] == "2")
        #expect(items["model"] == "claude-opus-4" && items["model_source"] == "requested")
        #expect(items["granularity"] == nil)
    }
    // The running hour ends now.
    #expect(sent.contains { $0["end_time"] == "2026-10-16T01:41:00Z" })
    #expect(read.cost(for: buckets[0]) == Decimal(string: "1.25"))
    #expect(read.cost(for: buckets[1]) == Decimal(string: "2.5"))
    #expect(read.cost(for: buckets[2]) == Decimal(string: "0.75"))
    #expect(read.segments.count == 3)
}

@Test func profitSegmentCostsLeavesFailedAndCostlessSegmentsOut() async throws {
    let buckets = Array(today.buckets[6...9])
    let starts = buckets.map { ServerTime.utcTimestamp($0.start) }
    let transport = ScriptedTransport { request in
        switch sentItems(request)["start_time"] {
        case starts[1]: errorReply(500)
        case starts[2]: stats(accountCost: nil)
        default: stats(accountCost: "4.00")
        }
    }
    let query = AnalyticsQuery(start: today.start, end: today.end, granularity: .hour, timeZone: shanghai)
    let read = try await segmentClient(transport).profitSegmentCosts(query, buckets: buckets)
    #expect(read.cost(for: buckets[0]) == 4 && read.cost(for: buckets[3]) == 4)
    #expect(read.cost(for: buckets[1]) == nil && read.cost(for: buckets[2]) == nil)
    #expect(Set(read.segments.keys) == [buckets[0].wireKey, buckets[3].wireKey])
    // A 500 is that segment's alone: nothing holds the rest back.
    #expect(read.rateLimit == nil)
}

@Test func profitSegmentCostsStopsSendingAfterA429() async throws {
    let transport = ScriptedTransport { _ in errorReply(429, headers: ["Retry-After": "120"]) }
    let query = AnalyticsQuery(start: today.start, end: today.end, granularity: .hour, timeZone: shanghai)
    let read = try await segmentClient(transport).profitSegmentCosts(query, buckets: Array(today.buckets[0..<6]))
    #expect(await transport.requests(path: "admin/usage/stats").count == AnalyticsFanOut.maxConcurrent)
    #expect(read.segments.isEmpty)
    // The 429 comes back with its Retry-After, so the block waits it out (00 §2.7.2).
    #expect(read.rateLimit?.statusCode == 429 && read.rateLimit?.retryAfter == 120)
}

@Test func profitSegmentCostsKeepWhatWasReadBeforeA429() async throws {
    let buckets = Array(today.buckets[0..<4])
    let limited = ServerTime.utcTimestamp(buckets[1].start)
    let transport = ScriptedTransport { request in
        sentItems(request)["start_time"] == limited ? errorReply(429, headers: ["Retry-After": "45"]) : stats(accountCost: "2.00")
    }
    let query = AnalyticsQuery(start: today.start, end: today.end, granularity: .hour, timeZone: shanghai)
    let read = try await segmentClient(transport).profitSegmentCosts(query, buckets: buckets)
    #expect(read.cost(for: buckets[0]) == 2 && read.cost(for: buckets[2]) == 2 && read.cost(for: buckets[3]) == 2)
    #expect(read.cost(for: buckets[1]) == nil)
    #expect(read.rateLimit?.retryAfter == 45)
}
