import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// LoadState moved to NativeApp/Session in S1-05 (X27): the existing guards, tested on macOS for the first time.

@MainActor @Test func lateResultOfReplacedLoadIsDropped() async {
    let state = LoadState<Int>()
    let gate = SessionGate()
    let first = Task { await state.load(isCurrent: { true }) { await gate.wait(); return 1 } }
    while await !gate.arrived { await Task.yield() }
    await state.load(isCurrent: { true }) { 2 }
    await gate.open()
    await first.value
    #expect(state.value == 2 && state.error == nil && !state.isLoading)
}

@MainActor @Test func resultIsDroppedWhenSessionIsNoLongerCurrent() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { 1 }
    let session = TestSwitch()
    let gate = SessionGate()
    let pending = Task { await state.load(isCurrent: { session.isOn }) { await gate.wait(); return 2 } }
    while await !gate.arrived { await Task.yield() }
    session.isOn = false
    await gate.open()
    await pending.value
    #expect(state.value == 1 && state.error == nil)
    await state.load(isCurrent: { session.isOn }) { throw APIError.server(status: 500, reason: nil) }
    #expect(state.value == 1 && state.error == nil && state.refresh.consecutiveFailures == 0)
}

@MainActor @Test func rateLimitedLoadSkipsUntilNotBefore() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { 1 }
    await state.load(isCurrent: { true }) { throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }
    let calls = TestCounter()
    await state.load(isCurrent: { true }) { calls.count += 1; return 3 }
    #expect(calls.count == 0 && state.value == 1 && state.error != nil)
    let delay = state.nextDelay(base: 60)
    #expect(delay >= 29 && delay <= 30)
}

@MainActor @Test func updateValueKeepsTimeAndBackoff() async {
    let state = LoadState<[Int]>()
    state.updateValue { $0 + [9] }
    #expect(state.state == .idle)
    await state.load(isCurrent: { true }) { [1, 2] }
    await state.load(isCurrent: { true }) { throw APIError.server(status: 500, reason: nil) }
    let before = (state.updatedAt, state.refresh)
    state.updateValue { $0.filter { $0 != 1 } }
    #expect(state.value == [2] && state.updatedAt == before.0 && state.refresh == before.1 && state.refresh.consecutiveFailures == 1)
    #expect(state.error != nil)
}

// MARK: - S1-08 · lastError / lastErrorAt（BlockFailureRow 的合规按钮与诊断）

@MainActor @Test func failedLoadKeepsAPIErrorAndTime() async {
    let state = LoadState<Int>()
    let failure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
    await state.load(isCurrent: { true }) { throw failure }
    #expect(state.lastError?.statusCode == 503 && state.lastError?.reason == "SERVICE_UNAVAILABLE")
    #expect(state.lastErrorAt != nil && state.error == failure.localizedDescription)
}

@MainActor @Test func successClearsLastError() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { throw APIError.server(status: 500, reason: nil) }
    await state.load(isCurrent: { true }) { 1 }
    #expect(state.lastError == nil && state.lastErrorAt == nil && state.value == 1 && state.error == nil)
}

@MainActor @Test func nonAPIErrorFailureLeavesLastErrorNil() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { throw URLError(.badServerResponse) }
    #expect(state.error != nil && state.lastError == nil && state.lastErrorAt != nil)
}

@MainActor @Test func cancelledLoadDoesNotRecordError() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { throw CancellationError() }
    #expect(state.lastError == nil && state.lastErrorAt == nil)
    let gate = SessionGate()
    let pending = Task { await state.load(isCurrent: { true }) { await gate.wait(); throw APIError.server(status: 500, reason: nil) } }
    while await !gate.arrived { await Task.yield() }
    state.cancel()
    await gate.open()
    await pending.value
    #expect(state.lastError == nil && state.lastErrorAt == nil)
}

@MainActor @Test func supersededLoadDoesNotOverwriteLastError() async {
    let state = LoadState<Int>()
    let gate = SessionGate()
    let first = Task { await state.load(isCurrent: { true }) { await gate.wait(); throw APIError.server(status: 500, reason: nil) } }
    while await !gate.arrived { await Task.yield() }
    await state.load(isCurrent: { true }) { 2 }
    await gate.open()
    await first.value
    #expect(state.lastError == nil && state.value == 2)
}

@MainActor @Test func resetClearsLastErrorExceptDuring429Wait() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { throw APIError.server(status: 500, reason: nil) }
    state.reset()
    #expect(state.lastError == nil && state.lastErrorAt == nil && state.state == .idle)
    let throttled = LoadState<Int>()
    await throttled.load(isCurrent: { true }) { throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }
    throttled.reset()
    #expect(throttled.error != nil && throttled.lastError?.statusCode == 429 && throttled.lastErrorAt != nil)
}

@MainActor @Test func complianceRefusalIsVisibleThroughLastError() async {
    let state = LoadState<Int>()
    await state.load(isCurrent: { true }) { throw APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED") }
    #expect(BlockStatusPresentation.needsCompliance(state.lastError))
}
