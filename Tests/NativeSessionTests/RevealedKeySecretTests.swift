import Foundation
import Testing
@testable import NativeSessionSupport

/// One wait per request, woken by the test; a cancelled wait throws as Task.sleep does.
private actor SecretClock {
    private(set) var requests: [Duration] = []
    private var waits: [CheckedContinuation<Void, any Error>] = []
    func sleep(_ duration: Duration) async throws {
        requests.append(duration)
        try await withCheckedThrowingContinuation { waits.append($0) }
    }
    var pending: Int { waits.count }
    func fire() { for wait in waits { wait.resume() }; waits = [] }
}
@MainActor private func settle(until done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}
@MainActor private func secret(_ clock: SecretClock, purpose: RevealedKeySecret.Purpose = .reveal) -> RevealedKeySecret {
    RevealedKeySecret(keyID: 4087, purpose: purpose, name: "默认", plaintext: "sk-ui-secret-4087", sleep: { try await clock.sleep($0) })
}

@MainActor @Test(.timeLimit(.minutes(1))) func lifetimeAndRedaction() async {
    let clock = SecretClock()
    let shown = secret(clock, purpose: .created)
    #expect(shown.plaintext == "sk-ui-secret-4087" && !shown.expired)
    var spins = 0
    while await clock.pending == 0, spins < 10_000 { await Task.yield(); spins += 1 }
    #expect(await clock.requests == [.seconds(30)])
    #expect(RevealedKeySecret.lifetime == .seconds(30))
    await clock.fire()
    await settle { shown.plaintext == nil }
    #expect(shown.plaintext == nil && shown.expired)
    #expect(shown.name == "默认" && shown.keyID == 4087 && shown.purpose == .created)

    // The plaintext never prints, reflects or dumps.
    let other = secret(clock)
    var dumped = ""
    dump(other, to: &dumped)
    for text in [String(describing: other), String(reflecting: other), dumped, "\(Mirror(reflecting: other).children.map(\.value))"] {
        #expect(!text.contains("sk-ui-secret"), "\(text)")
    }
    other.clear()
    #expect(other.plaintext == nil && !other.expired)
    await clock.fire()
}

@MainActor @Test(.timeLimit(.minutes(1))) func backgroundClearsAndInactiveShields() async {
    let clock = SecretClock()
    let shown = secret(clock)
    var spins = 0
    while await clock.pending == 0, spins < 10_000 { await Task.yield(); spins += 1 }
    shown.activityChanged(to: .inactive)
    #expect(shown.isShielded && shown.plaintext != nil)
    shown.activityChanged(to: .active)
    #expect(!shown.isShielded)
    shown.activityChanged(to: .inactive)
    shown.activityChanged(to: .background)
    #expect(shown.plaintext == nil && !shown.expired)
    shown.activityChanged(to: .active)
    #expect(!shown.isShielded && shown.plaintext == nil)
    // The timer that was running is gone: firing it later does not mark the secret expired.
    await clock.fire()
    for _ in 0..<100 { await Task.yield() }
    #expect(!shown.expired)
}
