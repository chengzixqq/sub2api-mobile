import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records the revocation's calls in order; `accessTokens` and `logout` must never be reached.
private actor RevocationRecorder: SiteTeardownAPI {
    enum Call: Equatable { case deletePush(Int), accessTokens, revoke(Int), logout }
    private(set) var calls = [Call]()
    private let pushErrors: [Int: any Error]
    private let revokeReply: Result<Bool, any Error>
    init(pushErrors: [Int: any Error] = [:], revokeReply: Result<Bool, any Error> = .success(false)) {
        self.pushErrors = pushErrors; self.revokeReply = revokeReply
    }
    func deletePushDevice(id: Int) async throws {
        calls.append(.deletePush(id))
        if let error = pushErrors[id] { throw error }
    }
    func accessTokens() async throws -> [AdminAccessToken] { calls.append(.accessTokens); return [] }
    func revokeAccessToken(id: Int) async throws -> Bool {
        calls.append(.revoke(id))
        return try revokeReply.get()
    }
    func logout() async throws { calls.append(.logout) }
}

private let accessToken = Credential.accessToken("sat_fixture")
private let jwt = Credential.tokens(TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: Date().addingTimeInterval(600)))

@Test func currentTokenDeletesPushDevicesBeforeRevoking() async throws {
    let api = RevocationRecorder(revokeReply: .success(true))
    let outcome = try await AccessTokenRevocation(tokenID: 5, isCurrent: true, pushDeviceIDs: [12, 30], credential: accessToken).run(using: api)
    #expect(await api.calls == [.deletePush(12), .deletePush(30), .revoke(5)])
    #expect(outcome.kind == .revokedCurrent)
    #expect(outcome.pushReport?.deletedPushDeviceIDs == [12, 30]); #expect(outcome.pushReport?.failedPushDeviceIDs == [])
    #expect(outcome.failure == nil)
}

@Test func failedPushDeletionDoesNotBlockRevocation() async throws {
    let api = RevocationRecorder(pushErrors: [12: URLError(.timedOut), 30: APIError.server(status: 404, reason: "PUSH_DEVICE_NOT_FOUND")],
                                 revokeReply: .success(true))
    let outcome = try await AccessTokenRevocation(tokenID: 5, isCurrent: true, pushDeviceIDs: [12, 30, 41], credential: accessToken).run(using: api)
    #expect(await api.calls == [.deletePush(12), .deletePush(30), .deletePush(41), .revoke(5)])
    #expect(outcome.kind == .revokedCurrent)
    // A device the server no longer has counts as deleted.
    #expect(outcome.pushReport?.failedPushDeviceIDs == [12]); #expect(outcome.pushReport?.deletedPushDeviceIDs == [30, 41])
}

@Test func otherTokenRevokesWithoutTouchingPushDevices() async throws {
    let api = RevocationRecorder()
    let outcome = try await AccessTokenRevocation(tokenID: 7, isCurrent: false, pushDeviceIDs: [12], credential: accessToken).run(using: api)
    #expect(await api.calls == [.revoke(7)])
    #expect(outcome.kind == .revoked); #expect(outcome.pushReport == nil); #expect(outcome.failure == nil)
}

/// The list was stale and the row was this App's token after all: the session ends, and the push devices it could no
/// longer delete wait for the next login.
@Test func serverSaysCurrentForAnotherRowStillEndsTheSession() async throws {
    let api = RevocationRecorder(revokeReply: .success(true))
    let outcome = try await AccessTokenRevocation(tokenID: 7, isCurrent: false, pushDeviceIDs: [12], credential: accessToken).run(using: api)
    #expect(await api.calls == [.revoke(7)])
    #expect(outcome.kind == .revokedCurrent)
    #expect(outcome.pushReport == TeardownReport(failedPushDeviceIDs: [12]))
}

@Test func missingTokenCountsAsAlreadyGone() async throws {
    let api = RevocationRecorder(revokeReply: .failure(APIError.server(status: 404, reason: "ACCESS_TOKEN_NOT_FOUND")))
    let outcome = try await AccessTokenRevocation(tokenID: 7, isCurrent: false, pushDeviceIDs: [], credential: accessToken).run(using: api)
    #expect(outcome.kind == .alreadyGone); #expect(outcome.failure == nil)
}

@Test func otherFailuresKeepTheSessionAndCarryTheError() async throws {
    let errors: [any Error] = [APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE"),
                               URLError(.notConnectedToInternet)]
    for error in errors {
        let api = RevocationRecorder(revokeReply: .failure(error))
        let outcome = try await AccessTokenRevocation(tokenID: 7, isCurrent: false, pushDeviceIDs: [12], credential: accessToken).run(using: api)
        #expect(outcome.kind == .failed)
        #expect((outcome.failure as? APIError)?.reason == (error as? APIError)?.reason)
        #expect(outcome.failure != nil); #expect(outcome.pushReport == nil)
    }
    // This App's own token: the push devices are gone whatever the revocation did, so the report still comes back.
    let api = RevocationRecorder(revokeReply: .failure(APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")))
    let outcome = try await AccessTokenRevocation(tokenID: 5, isCurrent: true, pushDeviceIDs: [12], credential: accessToken).run(using: api)
    #expect(outcome.kind == .failed); #expect(outcome.pushReport?.deletedPushDeviceIDs == [12])
}

@Test func cancellationIsRethrown() async {
    let api = RevocationRecorder(revokeReply: .failure(CancellationError()))
    await #expect(throws: CancellationError.self) {
        try await AccessTokenRevocation(tokenID: 7, isCurrent: false, pushDeviceIDs: [], credential: accessToken).run(using: api)
    }
}

/// Only a `sat_` sign-in can be the current token; anything else revokes and never signs out on the server.
@Test func nonTokenCredentialNeverLogsOut() async throws {
    let api = RevocationRecorder(revokeReply: .success(false))
    let outcome = try await AccessTokenRevocation(tokenID: 5, isCurrent: true, pushDeviceIDs: [12], credential: jwt).run(using: api)
    #expect(await api.calls == [.revoke(5)])
    #expect(outcome.kind == .revoked); #expect(outcome.pushReport == nil)
}

@MainActor @Test func pushRecordsFollowTheRevocationReport() {
    let suite = "AccessTokenRevocationTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = PushDeviceRecords(defaults: defaults), site = UUID()
    records.setRegisteredDeviceID(12, serverID: site)
    records.apply(TeardownReport(failedPushDeviceIDs: [30]), serverID: site)
    records.setRegisteredDeviceID(12, serverID: site)
    #expect(records.teardownCandidates(serverID: site) == [12, 30])
    records.apply(TeardownReport(deletedPushDeviceIDs: [12], failedPushDeviceIDs: [30]), serverID: site)
    #expect(records.registeredDeviceID(serverID: site) == nil)
    #expect(records.pendingDeletions(serverID: site) == [30])
}
