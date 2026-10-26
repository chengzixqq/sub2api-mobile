import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

@Test func deviceIDIsStablePerStationAndDistinctAcrossStations() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let first = UUID(), second = UUID()
    let id = try await vault.deviceID(serverID: first)
    #expect(try await vault.deviceID(serverID: first) == id)
    #expect(try await vault.deviceID(serverID: second) != id)
}

@Test func storedDraftDeviceIDIsReturnedForStation() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID(), draft = UUID()
    _ = try await vault.deviceID(serverID: serverID)
    try await vault.storeDeviceID(draft, serverID: serverID)
    #expect(try await vault.deviceID(serverID: serverID) == draft)
}

@Test func deviceIDIsSavedLowercasedUnderStationDeviceAccount() async throws {
    let items = MemorySecureItems()
    let vault = KeychainCredentialStore(items: items)
    let serverID = UUID()
    let id = try await vault.deviceID(serverID: serverID)
    #expect(KeychainCredentialStore.deviceAccount(for: serverID) == serverID.uuidString + ".device")
    #expect(KeychainCredentialStore.deviceAccount(for: serverID) != KeychainCredentialStore.credentialAccount(for: serverID))
    let stored = try #require(try items.read(account: serverID.uuidString + ".device"))
    #expect(String(decoding: stored, as: UTF8.self) == id.uuidString.lowercased())
    // A value that is not a UUID is replaced; the site still gets one fixed ID from then on.
    try items.write(Data("not-a-uuid".utf8), account: KeychainCredentialStore.deviceAccount(for: serverID))
    let replaced = try await vault.deviceID(serverID: serverID)
    #expect(replaced != id); #expect(try await vault.deviceID(serverID: serverID) == replaced)
}

@Test func unreadableDeviceIDIsThrownNeverOverwritten() async throws {
    let items = FailingSecureItems(.read) { $0.hasSuffix(".device") }
    let vault = KeychainCredentialStore(items: items)
    await #expect(throws: (any Error).self) { try await vault.deviceID(serverID: UUID()) }
    #expect(items.writeCount == 0)
}

@Test func logoutErasureKeepsDeviceIDButStationRemovalDeletesIt() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID(), lease = UUID()
    let id = try await vault.deviceID(serverID: serverID)
    _ = try await vault.commit(.adminKey("fixture"), serverID: serverID, lease: lease)
    try await vault.revoke(serverID: serverID, lease: lease, erase: true)
    #expect(try await vault.load(serverID: serverID) == nil)
    #expect(try await vault.deviceID(serverID: serverID) == id)
    let scoped = try await vault.commit(.adminKey("again"), serverID: serverID, lease: UUID())
    try await scoped.remove(serverID: serverID)
    try await vault.eraseCredential(serverID: serverID)
    #expect(try await vault.load(serverID: serverID) == nil)
    #expect(try await vault.deviceID(serverID: serverID) == id)
    _ = try await vault.commit(.adminKey("third"), serverID: serverID, lease: UUID())
    try await vault.remove(serverID: serverID)
    #expect(try await vault.load(serverID: serverID) == nil)
    #expect(try await vault.deviceID(serverID: serverID) != id)
}

@Test func committingDraftDeviceIDSavesItBeforeTheCredential() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID(), draft = UUID()
    _ = try await vault.commit(.adminKey("fixture"), serverID: serverID, lease: UUID(), deviceID: draft)
    #expect(try await vault.deviceID(serverID: serverID) == draft)
    let failing = KeychainCredentialStore(items: FailingSecureItems(.write) { $0.hasSuffix(".device") })
    await #expect(throws: (any Error).self) { _ = try await failing.commit(.adminKey("fixture"), serverID: serverID, lease: UUID(), deviceID: draft) }
    #expect(try await failing.load(serverID: serverID) == nil)
}

@Test func abandonedAttemptForgetsDraftOnlyWhenNoNewerLeaseHoldsTheSite() async throws {
    let vault = KeychainCredentialStore(memoryOnly: true)
    let serverID = UUID(), stale = UUID(), current = UUID(), draft = UUID()
    _ = try await vault.commit(.adminKey("stale"), serverID: serverID, lease: stale, deviceID: draft)
    _ = try await vault.commit(.adminKey("current"), serverID: serverID, lease: current, deviceID: draft)
    try await vault.abandon(serverID: serverID, lease: stale, forgetDevice: true)
    #expect(try await vault.load(serverID: serverID) == .adminKey("current"))
    #expect(try await vault.deviceID(serverID: serverID) == draft)
    try await vault.abandon(serverID: serverID, lease: current, forgetDevice: true)
    #expect(try await vault.load(serverID: serverID) == nil)
    #expect(try await vault.deviceID(serverID: serverID) != draft)
    // A failed commit has no lease: only the draft of a never-saved site goes.
    let other = UUID()
    try await vault.storeDeviceID(draft, serverID: other)
    try await vault.abandon(serverID: other, lease: nil, forgetDevice: false)
    #expect(try await vault.deviceID(serverID: other) == draft)
}

@Test func legacyAdminKeyCredentialWithSatPrefixLoadsAsAccessToken() async throws {
    let decode = { (json: String) in try KeychainCredentialStore.decodeCredential(Data(json.utf8)) }
    #expect(try decode(#"{"adminKey":{"_0":"sat_fixture"}}"#) == .accessToken("sat_fixture"))
    #expect(try decode(#"{"adminKey":{"_0":"plain-fixture"}}"#) == .adminKey("plain-fixture"))
    let tokens = try decode(#"{"tokens":{"_0":{"accessToken":"a","refreshToken":"r","expiresAt":0}}}"#)
    guard case .tokens(let pair) = tokens else { Issue.record("Expected tokens"); return }
    #expect(pair.accessToken == "a"); #expect(pair.refreshToken == "r")
    // load goes through the same decoding.
    let items = MemorySecureItems()
    let serverID = UUID()
    try items.write(Data(#"{"adminKey":{"_0":"sat_saved"}}"#.utf8), account: KeychainCredentialStore.credentialAccount(for: serverID))
    #expect(try await KeychainCredentialStore(items: items).load(serverID: serverID) == .accessToken("sat_saved"))
}

/// The deletion prompt reads the kind the teardown will act on: a `sat_` saved as an Admin Key is an access token (00 §9.4).
@Test func storedAuthenticationFollowsTheMigratedCredential() async throws {
    let items = MemorySecureItems()
    let vault = KeychainCredentialStore(items: items)
    let legacy = UUID(), key = UUID(), account = UUID(), unreadable = UUID()
    try items.write(Data(#"{"adminKey":{"_0":"sat_saved"}}"#.utf8), account: KeychainCredentialStore.credentialAccount(for: legacy))
    try await vault.save(.adminKey("plain"), serverID: key)
    try await vault.save(.tokens(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date())), serverID: account)
    try items.write(Data("not json".utf8), account: KeychainCredentialStore.credentialAccount(for: unreadable))
    #expect(await vault.storedAuthentication(serverID: legacy) == .accessToken)
    #expect(await vault.storedAuthentication(serverID: key) == .adminKey)
    #expect(await vault.storedAuthentication(serverID: account) == .password)
    #expect(await vault.storedAuthentication(serverID: unreadable) == nil)
    #expect(await vault.storedAuthentication(serverID: UUID()) == nil)
}
