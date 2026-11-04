import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S2-22 审查修正: the account headers read LiveOpsStore's firing LoadState; a failed read hides every header alert (20 §1.3 /
// §1.5, S2D1-17), and the old list a retry carries, or a cancelled retry restores, must not bring one back.

@MainActor private func headersShowAlerts(_ list: LoadState<[AlertEvent]>) -> Bool {
    AccountAlertMatch.isListUsable(list, opsDisabled: false)
}

@MainActor @Test func failedFiringListStaysHiddenThroughRetryAndCancelledRetry() async {
    let list = LoadState<[AlertEvent]>()
    let event = firingEvent(40, severity: "P2", platform: "anthropic")
    await list.load(isCurrent: { true }) { [event] }
    #expect(headersShowAlerts(list))
    await list.load(isCurrent: { true }) { throw APIError.server(status: 502, reason: nil) }
    #expect(!headersShowAlerts(list))

    let gate = SessionGate()
    let retry = Task { await list.load(isCurrent: { true }) { await gate.wait(); throw APIError.server(status: 502, reason: nil) } }
    while await !gate.arrived { await Task.yield() }
    #expect(list.isLoading && list.value == [event])
    #expect(!headersShowAlerts(list))
    list.cancel()
    await gate.open()
    await retry.value
    #expect(list.value == [event] && list.error == nil)
    #expect(!headersShowAlerts(list))

    await list.load(isCurrent: { true }) { [event] }
    #expect(headersShowAlerts(list))
}

/// A refresh after a success keeps the headers as they were while it runs (20 §1.2).
@MainActor @Test func firingListRefreshAfterSuccessKeepsHeaderAlerts() async {
    let list = LoadState<[AlertEvent]>()
    await list.load(isCurrent: { true }) { [firingEvent(40, severity: "P2", platform: "anthropic")] }
    let gate = SessionGate()
    let refresh = Task { await list.load(isCurrent: { true }) { await gate.wait(); return [] } }
    while await !gate.arrived { await Task.yield() }
    #expect(list.isLoading && headersShowAlerts(list))
    await gate.open()
    await refresh.value
    #expect(list.value == [] && headersShowAlerts(list))
}
