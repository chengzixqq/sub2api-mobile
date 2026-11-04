import Foundation
import Testing
@testable import NativeSessionSupport

// S6-08 (60 §19.4 step 9, S6D1-15): a money record is marked while it goes out, so the foreground check leaves it alone and
// the same record never goes out twice at once.

private struct Refused: Error {}

@MainActor @Test func registersOnlyWhileSending() async throws {
    let inFlight = MoneyWriteInFlight(), id = UUID()
    let markedInside = try await inFlight.sending(id) { inFlight.contains(id) }
    #expect(markedInside)
    #expect(!inFlight.contains(id) && inFlight.ids.isEmpty)
    await #expect(throws: Refused.self) { try await inFlight.sending(id) { throw Refused() } }
    #expect(!inFlight.contains(id))

    let entered = SessionGate()
    let sending = Task { @MainActor in
        try await inFlight.sending(id) {
            await entered.open()
            try await Task.sleep(for: .seconds(60))
        }
    }
    await entered.wait()
    #expect(inFlight.contains(id))
    sending.cancel()
    await #expect(throws: CancellationError.self) { try await sending.value }
    #expect(!inFlight.contains(id))
}

@MainActor @Test func sameRecordCannotBeSentTwiceAtOnce() async throws {
    let inFlight = MoneyWriteInFlight(), id = UUID(), other = UUID()
    let entered = SessionGate(), release = SessionGate()
    let first = Task { @MainActor in
        try await inFlight.sending(id) {
            await entered.open()
            await release.wait()
            return "first"
        }
    }
    await entered.wait()
    let secondRuns = TestCounter()
    await #expect(throws: MoneyWriteInFlight.Busy()) { try await inFlight.sending(id) { secondRuns.count += 1 } }
    #expect(secondRuns.count == 0)
    #expect(MoneyWriteInFlight.Busy().localizedDescription == "这笔正在发送，请稍候")
    let both = try await inFlight.sending(other) { inFlight.ids }
    #expect(both == [id, other])
    #expect(inFlight.contains(id) && !inFlight.contains(other))
    await release.open()
    let firstResult = try await first.value
    #expect(firstResult == "first")
    #expect(inFlight.ids.isEmpty)
}
