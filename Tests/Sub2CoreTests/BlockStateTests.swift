import Foundation
import Testing
@testable import Sub2Core

private let lastSuccess = Date(timeIntervalSince1970: 1_800_000_000)

@Test func blockDisplayShowsValueWheneverPresent() {
    let t = lastSuccess
    #expect(BlockState<Int>.idle.display == .placeholder)
    #expect(BlockState<Int>.loading(previous: nil, at: nil).display == .placeholder)
    #expect(BlockState.loading(previous: 5, at: t).display == .value(5, at: t, isRefreshing: true, updateFailed: false))
    #expect(BlockState.loaded(5, at: t).display == .value(5, at: t, isRefreshing: false, updateFailed: false))
    #expect(BlockState.failed(reason: "x", previous: 5, at: t).display == .value(5, at: t, isRefreshing: false, updateFailed: true))
    #expect(BlockState<Int>.failed(reason: "x", previous: nil, at: nil).display == .failed(reason: "x"))
    #expect(BlockState<Int>.disabled(reason: "OPS_DISABLED").display == .disabled(reason: "OPS_DISABLED"))
}

@Test func loadingKeepsPreviousValueAndTimeAndClearsFailure() {
    let t = lastSuccess
    #expect(BlockState<Int>.idle.withLoading() == .loading(previous: nil, at: nil))
    #expect(BlockState.loaded(5, at: t).withLoading() == .loading(previous: 5, at: t))
    let retried = BlockState.failed(reason: "x", previous: 5, at: t).withLoading()
    #expect(retried == .loading(previous: 5, at: t))
    #expect(retried.failureReason == nil && retried.value == 5 && retried.updatedAt == t && retried.isLoading)
}

@Test func failureKeepsPreviousValueAndLastSuccessTime() {
    let t = lastSuccess
    let failed = BlockState.loading(previous: 5, at: t).withFailure("y")
    #expect(failed == .failed(reason: "y", previous: 5, at: t))
    #expect(failed.failureReason == "y" && failed.value == 5 && failed.updatedAt == t && !failed.isLoading)
    #expect(BlockState<Int>.loading(previous: nil, at: nil).withFailure("y") == .failed(reason: "y", previous: nil, at: nil))
}

@Test func cancelledLoadRestoresLastSuccessOrIdle() {
    let t = lastSuccess
    let restored = BlockState.loading(previous: 5, at: t).withCancelledLoad()
    #expect(restored == .loaded(5, at: t))
    #expect(restored.failureReason == nil && !restored.isLoading && restored.updatedAt == t)
    let empty = BlockState<Int>.loading(previous: nil, at: nil).withCancelledLoad()
    #expect(empty == .idle)
    #expect(empty.failureReason == nil && !empty.isLoading && empty.value == nil)
}

@Test func cancelOutsideLoadingIsNoOp() {
    let t = lastSuccess
    let states: [BlockState<Int>] = [.idle, .loaded(5, at: t), .failed(reason: "x", previous: 5, at: t), .disabled(reason: "r")]
    for state in states { #expect(state.withCancelledLoad() == state) }
}

@Test func disabledHasNoValueAndRestartsEmpty() {
    let disabled = BlockState<Int>.disabled(reason: "OPS_DISABLED")
    #expect(disabled.value == nil && disabled.updatedAt == nil && !disabled.isLoading && disabled.failureReason == nil)
    #expect(disabled.disabledReason == "OPS_DISABLED")
    #expect(disabled.withLoading() == .loading(previous: nil, at: nil))
    #expect(BlockState.loaded(5, at: lastSuccess).disabledReason == nil)
}

@Test func refreshIntervalDoublesAfterEachFailureUpToFiveMinutes() {
    #expect(BlockRefresh.nextRefreshInterval(consecutiveFailures: 0) == 60)
    #expect([0, 1, 2, 3, 4, 100].map { BlockRefresh.nextRefreshInterval(base: 60, consecutiveFailures: $0) } == [60, 120, 240, 300, 300, 300])
    #expect([0, 1, 2, 3, 4].map { BlockRefresh.nextRefreshInterval(base: 30, consecutiveFailures: $0) } == [30, 60, 120, 240, 300])
    #expect(BlockRefresh.nextRefreshInterval(base: 600, consecutiveFailures: 2) == 600)
}

@Test func failuresBackOffAndSuccessRestoresTheBaseInterval() {
    let now = lastSuccess
    var refresh = BlockRefresh()
    #expect(refresh.consecutiveFailures == 0 && refresh.notBefore == nil && refresh.nextDelay(base: 60, at: now) == 60)
    refresh = refresh.recordingFailure(URLError(.timedOut), at: now)
    #expect(refresh.consecutiveFailures == 1 && refresh.notBefore == nil && refresh.allowsRequest(at: now))
    #expect(refresh.nextDelay(base: 60, at: now) == 120)
    refresh = refresh.recordingFailure(APIError.server(status: 503, reason: nil), at: now)
    #expect(refresh.nextDelay(base: 60, at: now) == 240 && refresh.throttleMessage(at: now) == nil)
    refresh = refresh.recordingSuccess()
    #expect(refresh == BlockRefresh() && refresh.nextDelay(base: 60, at: now) == 60)
}

@Test func rateLimitedBlockWaitsRetryAfterBeforeTheNextRequest() {
    let now = lastSuccess
    let limited = APIError.server(status: 429, envelope: nil, retryAfter: 12)
    let refresh = BlockRefresh().recordingFailure(limited, at: now)
    #expect(refresh.notBefore == now.addingTimeInterval(12) && refresh.consecutiveFailures == 1)
    #expect(!refresh.allowsRequest(at: now.addingTimeInterval(11.9)))
    #expect(refresh.allowsRequest(at: now.addingTimeInterval(12)))
    #expect(refresh.throttleMessage(at: now.addingTimeInterval(0.5)) == "请求过于频繁，12 秒后自动重试")
    #expect(refresh.throttleMessage(at: now.addingTimeInterval(11.2)) == "请求过于频繁，1 秒后自动重试")
    #expect(refresh.throttleMessage(at: now.addingTimeInterval(12)) == nil)
    #expect(refresh.nextDelay(base: 60, at: now) == 12)
    #expect(refresh.nextDelay(base: 60, at: now.addingTimeInterval(11.5)) == 1)
    #expect(refresh.nextDelay(base: 60, at: now.addingTimeInterval(12)) == 120)
    let recovered = refresh.recordingSuccess()
    #expect(recovered.notBefore == nil && recovered.allowsRequest(at: now))
}

@Test func rateLimitWithoutRetryAfterWaitsTheDefault() {
    let now = lastSuccess
    let limited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁")
    let refresh = BlockRefresh().recordingFailure(limited, at: now)
    #expect(refresh.notBefore == now.addingTimeInterval(TimeInterval(RetryAfter.rateLimitDefault)))
    #expect(refresh.throttleMessage(at: now) == "请求过于频繁，30 秒后自动重试")
    let later = refresh.recordingFailure(URLError(.notConnectedToInternet), at: now.addingTimeInterval(31))
    #expect(later.notBefore == nil && later.consecutiveFailures == 2)
}
