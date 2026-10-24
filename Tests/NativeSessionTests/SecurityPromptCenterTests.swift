import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

@MainActor private final class PromptClock {
    var current = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}
/// `present` registers its waiter without suspending once it runs, so a few yields are enough; the bound keeps a bug from hanging.
@MainActor private func settle(_ center: SecurityPromptCenter, waiting count: Int) async {
    var spins = 0
    while center.waitingCount < count && spins < 10_000 { await Task.yield(); spins += 1 }
}
@MainActor private func ask(_ center: SecurityPromptCenter, _ kind: SecurityPromptCenter.Prompt.Kind, purpose: String? = nil, isRead: Bool = true,
                            _ generation: UUID) -> Task<SecurityPromptOutcome, Never> {
    Task { await center.present(kind, purpose: purpose, isRead: isRead, generation: generation) }
}

@MainActor @Test(.timeLimit(.minutes(1))) func concurrentRequestsShareOnePrompt() async throws {
    let center = SecurityPromptCenter(), session = UUID()
    let first = ask(center, .compliance, purpose: "保存", session)
    let second = ask(center, .compliance, purpose: "删除", isRead: false, session)
    await settle(center, waiting: 2)
    let prompt = try #require(center.active)
    #expect(prompt.kind == .compliance); #expect(prompt.generation == session)
    #expect(!prompt.isRead); #expect(prompt.purpose == nil)
    center.complete(prompt.id, outcome: .passed)
    #expect(await first.value == .passed); #expect(await second.value == .passed)
    #expect(center.active == nil); #expect(center.complianceRevision == 1); #expect(center.waitingCount == 0)
    center.complete(prompt.id, outcome: .cancelled)
    #expect(center.complianceRevision == 1)
}

@MainActor @Test(.timeLimit(.minutes(1))) func differentPromptKindWaitsForActiveOne() async throws {
    let center = SecurityPromptCenter(), session = UUID()
    let compliance = ask(center, .compliance, session)
    await settle(center, waiting: 1)
    let stepUp = ask(center, .stepUpVerify, purpose: "把「Alice」设为管理员", isRead: false, session)
    await settle(center, waiting: 2)
    let shown = try #require(center.active)
    #expect(shown.kind == .compliance)
    center.complete(shown.id, outcome: .cancelled)
    #expect(await compliance.value == .cancelled)
    let next = try #require(center.active)
    #expect(next.kind == .stepUpVerify); #expect(next.purpose == "把「Alice」设为管理员"); #expect(center.waitingCount == 1)
    center.complete(next.id, outcome: .passed)
    #expect(await stepUp.value == .passed); #expect(center.active == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func resetCancelsWaitersAndClearsPrompt() async throws {
    let center = SecurityPromptCenter(), session = UUID()
    let tasks = [ask(center, .compliance, session), ask(center, .compliance, isRead: false, session), ask(center, .stepUpNoTOTP, session)]
    await settle(center, waiting: 3)
    center.recordStepUpGrant(expiresIn: 900, generation: session)
    center.reset()
    for task in tasks { #expect(await task.value == .cancelled) }
    #expect(center.active == nil); #expect(center.waitingCount == 0); #expect(center.localGrantExpiry(generation: session) == nil)
    let again = ask(center, .stepUpVerify, session)
    await settle(center, waiting: 1)
    let prompt = try #require(center.active)
    #expect(prompt.kind == .stepUpVerify)
    center.complete(prompt.id, outcome: .blocked)
    #expect(await again.value == .blocked)
}

@MainActor @Test(.timeLimit(.minutes(1))) func cancelledCallerDoesNotDismissSharedPrompt() async throws {
    let center = SecurityPromptCenter(), session = UUID()
    let first = ask(center, .stepUpVerify, session), second = ask(center, .stepUpVerify, session)
    await settle(center, waiting: 2)
    let prompt = try #require(center.active)
    first.cancel()
    #expect(await first.value == .cancelled)
    #expect(center.active == prompt); #expect(center.waitingCount == 1)
    center.complete(prompt.id, outcome: .passed)
    #expect(await second.value == .passed)
    let cancelledEarly = Task { () -> SecurityPromptOutcome in
        withUnsafeCurrentTask { $0?.cancel() }
        return await center.present(.compliance, purpose: nil, isRead: true, generation: session)
    }
    #expect(await cancelledEarly.value == .cancelled); #expect(center.active == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func recentCompliancePassShortCircuitsLateReads() async throws {
    let clock = PromptClock(), session = UUID()
    let center = SecurityPromptCenter(now: { clock.current })
    let first = ask(center, .compliance, session)
    await settle(center, waiting: 1)
    center.complete(try #require(center.active).id, outcome: .passed)
    #expect(await first.value == .passed)
    clock.advance(9)
    #expect(await center.present(.compliance, purpose: nil, isRead: true, generation: session) == .passed)
    #expect(center.active == nil)
    let otherSession = ask(center, .compliance, UUID())
    await settle(center, waiting: 1)
    center.complete(try #require(center.active).id, outcome: .cancelled)
    #expect(await otherSession.value == .cancelled)
    clock.advance(2)
    let late = ask(center, .compliance, session)
    await settle(center, waiting: 1)
    #expect(center.active?.kind == .compliance)
    center.complete(try #require(center.active).id, outcome: .passed)
    #expect(await late.value == .passed)
}

@MainActor @Test(.timeLimit(.minutes(1))) func declinedComplianceIsNotRepromptedForReads() async throws {
    let clock = PromptClock(), session = UUID()
    let center = SecurityPromptCenter(now: { clock.current })
    let first = ask(center, .compliance, session)
    await settle(center, waiting: 1)
    center.complete(try #require(center.active).id, outcome: .cancelled)
    #expect(await first.value == .cancelled)
    #expect(await center.present(.compliance, purpose: nil, isRead: true, generation: session) == .cancelled)
    #expect(center.active == nil)
    let write = ask(center, .compliance, isRead: false, session)
    await settle(center, waiting: 1)
    center.complete(try #require(center.active).id, outcome: .passed)
    #expect(await write.value == .passed)
    clock.advance(11)
    let read = ask(center, .compliance, session)
    await settle(center, waiting: 1)
    #expect(center.active?.kind == .compliance)
    center.reset()
    #expect(await read.value == .cancelled)
}

@MainActor @Test(.timeLimit(.minutes(1))) func stepUpGrantShortCircuitAndStaleGrantReprompts() async throws {
    let clock = PromptClock(), session = UUID()
    let center = SecurityPromptCenter(now: { clock.current })
    center.recordStepUpGrant(expiresIn: nil, generation: session)
    center.recordStepUpGrant(expiresIn: 0, generation: session)
    #expect(center.localGrantExpiry(generation: session) == nil)
    center.recordStepUpGrant(expiresIn: 900, generation: session)
    #expect(center.localGrantExpiry(generation: session) == clock.current.addingTimeInterval(900))
    #expect(center.localGrantExpiry(generation: UUID()) == nil)
    clock.advance(3)
    #expect(await center.present(.stepUpVerify, purpose: nil, isRead: true, generation: session) == .passed)
    #expect(center.active == nil)
    clock.advance(7)
    let stale = ask(center, .stepUpVerify, session)
    await settle(center, waiting: 1)
    #expect(center.active?.kind == .stepUpVerify); #expect(center.localGrantExpiry(generation: session) == nil)
    center.complete(try #require(center.active).id, outcome: .cancelled)
    #expect(await stale.value == .cancelled)
}
