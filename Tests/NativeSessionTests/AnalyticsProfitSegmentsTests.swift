import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §1.3 降级 and 00 §2.7.2: an old server's profit segments, cut short by a 429, wait out Retry-After as the block (S4-13b).

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai: today has 10 hourly buckets.
private let morning = Date(timeIntervalSince1970: 1_792_114_860)
private let segmentsKey = AnalyticsCardKey("profit.segments")

private func startTime(_ request: URLRequest) -> String? {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return items.first { $0.name == "start_time" }?.value
}
private func segmentStats(_ cost: String) -> HTTPResponse {
    sessionOK(#"{"total_requests":3,"total_tokens":30,"total_actual_cost":"5.00","total_account_cost":"\#(cost)"}"#)
}
private let rateLimited = HTTPResponse(statusCode: 429, headers: ["content-type": "application/json", "Retry-After": "120"],
                                       data: Data(#"{"code":429}"#.utf8))

@MainActor private func segmentSession(_ scratch: ScratchDefaults, _ transport: SessionTransport) -> AnalyticsSessionState {
    AnalyticsSessionState(serverID: UUID(), generation: UUID(), client: sessionClient(transport), timeZone: shanghai,
                          supportsModelSource: true, supportsOpsModelFilter: true, memory: AnalyticsMemory(defaults: scratch.defaults),
                          entry: .today, groups: nil, clock: { morning }, isSessionCurrent: { true })
}

/// The read `loadProfitSegments` makes (AnalyticsCards.swift): the buckets asked for, merged over what was kept.
@MainActor private func readSegments(_ session: AnalyticsSessionState, buckets: [AnalyticsBucket]) async {
    let kept = session.state(segmentsKey, as: ProfitSegmentCosts.self)?.value ?? ProfitSegmentCosts()
    await session.load(segmentsKey, refresh: true, fixture: { _ in kept }) { client, session in
        kept.merging(try await client.profitSegmentCosts(session.query(), buckets: buckets), reread: buckets)
    }
}

@MainActor @Test func profitSegmentsCutShortByA429SendNothingUntilRetryAfter() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let buckets = Array(AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai).buckets.prefix(6))
    let limited = ServerTime.utcTimestamp(buckets[2].start)
    let transport = SessionTransport { request in startTime(request) == limited ? rateLimited : segmentStats("1.00") }
    let throttled = segmentSession(scratch, transport)

    await readSegments(throttled, buckets: buckets)
    let sent = await transport.requests.count
    let segments = throttled.state(segmentsKey, as: ProfitSegmentCosts.self)
    // What was read before the 429 still shows; the bucket that got it is “—”.
    #expect(segments?.value?.cost(for: buckets[0]) == 1 && segments?.value?.cost(for: buckets[1]) == 1)
    #expect(segments?.value?.cost(for: buckets[2]) == nil)
    // The card says so and counts down.
    #expect(segments?.error != nil)
    #expect(segments?.refresh.throttleMessage(at: Date()) == "请求过于频繁，120 秒后自动重试")

    // Pull to refresh, the 60-second tick or a new trend within the 120 seconds: no usage/stats goes out.
    await readSegments(throttled, buckets: buckets.filter { segments?.value?.covers($0) != true })
    #expect(await transport.requests.count == sent)
    // A range change keeps the wait (it describes the site): the new range's segments wait too.
    throttled.select(.preset(.last7))
    await readSegments(throttled, buckets: Array(throttled.range.buckets.prefix(3)))
    #expect(await transport.requests.count == sent)
    #expect(throttled.state(segmentsKey, as: ProfitSegmentCosts.self)?.refresh.throttleMessage(at: Date()) != nil)
}
