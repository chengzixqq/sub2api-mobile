import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private actor LeaseGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@Test func lateOldClientSaveAndLogoutCannotReplaceNewSessionCredential() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID()
    let old = try await vault.commit(.adminKey("old-fixture"), serverID: serverID, lease: UUID())
    let gate = LeaseGate()
    let lateRefresh = Task {
        await gate.wait()
        try await old.save(.adminKey("late-old-refresh"), serverID: serverID)
    }
    _ = try await vault.commit(.adminKey("new-fixture"), serverID: serverID, lease: UUID())
    await gate.release()
    await #expect(throws: CancellationError.self) { try await lateRefresh.value }
    // An old APIClient.logout() eventually calls remove through its scoped store.
    try await old.remove(serverID: serverID)
    #expect(try await vault.load(serverID: serverID) == .adminKey("new-fixture"))
}

@Test func revokedLeaseCannotRestoreErasedCredentials() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID()
    let lease = UUID()
    let scoped = try await vault.commit(.adminKey("fixture"), serverID: serverID, lease: lease)
    try await vault.revoke(serverID: serverID, lease: lease, erase: true)
    await #expect(throws: CancellationError.self) { try await scoped.save(.adminKey("late-fixture"), serverID: serverID) }
    await #expect(throws: CancellationError.self) { try await scoped.load(serverID: serverID) }
    #expect(try await vault.load(serverID: serverID) == nil)
}

@Test func credentialLeasesAndRevocationAreIndependentAcrossStations() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let firstID = UUID(), secondID = UUID(), firstLease = UUID()
    let first = try await vault.commit(.adminKey("first-fixture"), serverID: firstID, lease: firstLease)
    let second = try await vault.commit(.adminKey("second-fixture"), serverID: secondID, lease: UUID())
    await #expect(throws: CancellationError.self) { try await first.save(.adminKey("cross-station"), serverID: secondID) }
    try await vault.revoke(serverID: firstID, lease: firstLease, erase: true)
    try await second.save(.adminKey("second-refreshed"), serverID: secondID)
    #expect(try await vault.load(serverID: firstID) == nil)
    #expect(try await vault.load(serverID: secondID) == .adminKey("second-refreshed"))
}

@Test func staleCandidateRollbackRevokesOnlyItsOwnLease() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID(), staleLease = UUID(), currentLease = UUID()
    _ = try await vault.commit(.adminKey("candidate-fixture"), serverID: serverID, lease: staleLease)
    let current = try await vault.commit(.adminKey("active-fixture"), serverID: serverID, lease: currentLease)
    // Models an obsolete connection attempt finishing cleanup after a newer commit.
    try await vault.revoke(serverID: serverID, lease: staleLease, erase: true)
    try await vault.revoke(serverID: serverID, lease: staleLease, erase: false)
    #expect(try await current.load(serverID: serverID) == .adminKey("active-fixture"))
    try await current.save(.adminKey("active-refreshed"), serverID: serverID)
    #expect(try await vault.load(serverID: serverID) == .adminKey("active-refreshed"))
}
