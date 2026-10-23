import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records the teardown calls in order; each step answers from its stub.
private actor TeardownRecorder: SiteTeardownAPI {
    enum Call: Equatable { case deletePush(Int), accessTokens, revoke(Int), logout }
    private(set) var calls = [Call]()
    private let pushErrors: [Int: any Error]
    private let tokens: [AdminAccessToken]
    private let tokensError: (any Error)?
    private let revokeError: (any Error)?
    private let hangs: Bool
    init(pushErrors: [Int: any Error] = [:], tokens: [AdminAccessToken] = [], tokensError: (any Error)? = nil,
         revokeError: (any Error)? = nil, hangs: Bool = false) {
        self.pushErrors = pushErrors; self.tokens = tokens; self.tokensError = tokensError; self.revokeError = revokeError; self.hangs = hangs
    }
    func deletePushDevice(id: Int) async throws {
        calls.append(.deletePush(id))
        if hangs { try await Task.sleep(for: .seconds(60)) }
        if let error = pushErrors[id] { throw error }
    }
    func accessTokens() async throws -> [AdminAccessToken] {
        calls.append(.accessTokens)
        try Task.checkCancellation()
        if let tokensError { throw tokensError }
        return tokens
    }
    func revokeAccessToken(id: Int) async throws -> Bool {
        calls.append(.revoke(id))
        if let revokeError { throw revokeError }
        return true
    }
    func logout() async throws { calls.append(.logout) }
}

private func token(_ id: Int, current: Bool) -> AdminAccessToken {
    try! JSONDecoder().decode(AdminAccessToken.self, from: Data(#"{"id":\#(id),"scope":"read","current":\#(current)}"#.utf8))
}
private let jwt = Credential.tokens(TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: Date().addingTimeInterval(600)))
private let accessToken = Credential.accessToken("sat_fixture")
private let adminKey = Credential.adminKey("fixture-key")

@Test func signOutDeletesPushDevicesBeforeLogout() async {
    let api = TeardownRecorder()
    let report = await SiteTeardown(credential: jwt, mode: .signOut, pushDeviceIDs: [12, 30]).run(using: api)
    #expect(await api.calls == [.deletePush(12), .deletePush(30), .logout])
    #expect(report.deletedPushDeviceIDs == [12, 30]); #expect(report.failedPushDeviceIDs.isEmpty)
    #expect(report.serverLogoutSucceeded == true); #expect(report.accessTokenRevoked == nil); #expect(report.notes.isEmpty)
}

@Test func failedPushDeletionDoesNotBlockLogout() async {
    let api = TeardownRecorder(pushErrors: [12: URLError(.timedOut)])
    let report = await SiteTeardown(credential: jwt, mode: .signOut, pushDeviceIDs: [12, 30]).run(using: api)
    #expect(await api.calls == [.deletePush(12), .deletePush(30), .logout])
    #expect(report.failedPushDeviceIDs == [12]); #expect(report.deletedPushDeviceIDs == [30])
    // Signing out keeps it as pending for the next login instead of a note.
    #expect(report.notes.isEmpty)
}

@Test func pushDeviceTheServerNoLongerHasCountsAsDeleted() async {
    let api = TeardownRecorder(pushErrors: [12: APIError.server(status: 404, reason: "PUSH_DEVICE_NOT_FOUND")])
    let report = await SiteTeardown(credential: adminKey, mode: .signOut, pushDeviceIDs: [12]).run(using: api)
    #expect(report.deletedPushDeviceIDs == [12]); #expect(report.failedPushDeviceIDs.isEmpty)
}

@Test func signingOutOfAnAccessTokenSiteDoesNotRevokeIt() async {
    let api = TeardownRecorder(tokens: [token(5, current: true)])
    let teardown = SiteTeardown(credential: accessToken, mode: .signOut, pushDeviceIDs: [12])
    let report = await teardown.run(using: api)
    #expect(await api.calls == [.deletePush(12)])
    #expect(report.accessTokenRevoked == nil); #expect(report.serverLogoutSucceeded == nil)
    #expect(!SiteTeardown(credential: accessToken, mode: .signOut, pushDeviceIDs: []).hasNetworkSteps)
}

@Test func removingAnAccessTokenSiteRevokesTheCurrentTokenAfterPush() async {
    let api = TeardownRecorder(tokens: [token(3, current: false), token(5, current: true)])
    let report = await SiteTeardown(credential: accessToken, mode: .removeSite, pushDeviceIDs: [12]).run(using: api)
    #expect(await api.calls == [.deletePush(12), .accessTokens, .revoke(5)])
    #expect(report.accessTokenRevoked == true); #expect(report.notes.isEmpty)
}

@Test func tokenRevocationFailureAddsTheReceiptNote() async {
    for api in [TeardownRecorder(tokens: [token(5, current: true)], revokeError: URLError(.timedOut)),
                TeardownRecorder(tokens: [token(3, current: false)]), TeardownRecorder(tokensError: URLError(.notConnectedToInternet))] {
        let report = await SiteTeardown(credential: accessToken, mode: .removeSite, pushDeviceIDs: []).run(using: api)
        #expect(report.accessTokenRevoked == false); #expect(report.notes == ["令牌未能吊销，可用 API 吊销"])
    }
}

@Test func aTokenAlreadyInvalidNeedsNoNote() async {
    let apis = [TeardownRecorder(tokensError: APIError.server(status: 401, reason: "INVALID_ADMIN_KEY")),
                TeardownRecorder(tokensError: APIError.server(status: 401, reason: "ACCESS_TOKEN_EXPIRED")),
                TeardownRecorder(tokens: [token(5, current: true)], revokeError: APIError.server(status: 404, reason: "ACCESS_TOKEN_NOT_FOUND"))]
    for api in apis {
        let report = await SiteTeardown(credential: accessToken, mode: .removeSite, pushDeviceIDs: []).run(using: api)
        #expect(report.accessTokenRevoked == true); #expect(report.notes.isEmpty)
    }
}

/// These end the session, yet the token itself stays valid: its owner disabled, a workspace stopped, a 401 from a proxy.
@Test func aTokenTheServerStillHoldsKeepsTheNote() async {
    let apis = [TeardownRecorder(tokensError: APIError.server(status: 401, reason: "USER_INACTIVE")),
                TeardownRecorder(tokensError: APIError.server(status: 401, envelope: nil)),
                TeardownRecorder(tokens: [token(5, current: true)], revokeError: APIError.server(status: 403, reason: "WORKSPACE_DISABLED"))]
    for api in apis {
        let report = await SiteTeardown(credential: accessToken, mode: .removeSite, pushDeviceIDs: []).run(using: api)
        #expect(report.accessTokenRevoked == false); #expect(report.notes == ["令牌未能吊销，可用 API 吊销"])
    }
}

/// A site deleted after its credential was gone (signed out, cleared, unreadable) sends nothing; what the confirmation
/// promised is reported as not done.
@Test func removingASiteWithoutACredentialReportsWhatWasNotSent() {
    let report = SiteTeardown.unsentReport(mode: .removeSite, authentication: .accessToken, pushDeviceIDs: [12])
    #expect(report?.failedPushDeviceIDs == [12]); #expect(report?.accessTokenRevoked == false)
    #expect(report?.notes == ["推送设备未能从站点移除，可在 Web 删除", "令牌未能吊销，可用 API 吊销"])
    #expect(SiteTeardown.unsentReport(mode: .removeSite, authentication: .password, pushDeviceIDs: [12])?.notes == ["推送设备未能从站点移除，可在 Web 删除"])
    #expect(SiteTeardown.unsentReport(mode: .removeSite, authentication: .adminKey, pushDeviceIDs: []) == nil)
    #expect(SiteTeardown.unsentReport(mode: .removeSite, authentication: .password, pushDeviceIDs: []) == nil)
    #expect(SiteTeardown.unsentReport(mode: .signOut, authentication: .accessToken, pushDeviceIDs: [12]) == nil)
}

@Test func removingAdminKeyAndAccountSites() async {
    #expect(!SiteTeardown(credential: adminKey, mode: .removeSite, pushDeviceIDs: []).hasNetworkSteps)
    let key = TeardownRecorder()
    _ = await SiteTeardown(credential: adminKey, mode: .removeSite, pushDeviceIDs: [12]).run(using: key)
    #expect(await key.calls == [.deletePush(12)])
    let account = TeardownRecorder()
    #expect(SiteTeardown(credential: jwt, mode: .removeSite, pushDeviceIDs: []).hasNetworkSteps)
    _ = await SiteTeardown(credential: jwt, mode: .removeSite, pushDeviceIDs: [12]).run(using: account)
    #expect(await account.calls == [.deletePush(12), .logout])
}

@Test func removalPushFailureAddsTheWebHint() async {
    let api = TeardownRecorder(pushErrors: [12: URLError(.timedOut)])
    let report = await SiteTeardown(credential: adminKey, mode: .removeSite, pushDeviceIDs: [12]).run(using: api)
    #expect(report.notes == ["推送设备未能从站点移除，可在 Web 删除"])
}

@Test func deadlineAbandonsTheRemainingSteps() async {
    let api = TeardownRecorder(hangs: true)
    let started = ContinuousClock.now
    let report = await SiteTeardown(credential: accessToken, mode: .removeSite, pushDeviceIDs: [12, 30]).run(using: api, within: .milliseconds(200))
    #expect(ContinuousClock.now - started < .seconds(10))
    #expect(report.failedPushDeviceIDs == [12, 30])
    #expect(report.notes == ["推送设备未能从站点移除，可在 Web 删除", "令牌未能吊销，可用 API 吊销"])
}

@Test func cancelledTeardownStillReturnsAReport() async {
    let api = TeardownRecorder(hangs: true)
    let task = Task { await SiteTeardown(credential: jwt, mode: .signOut, pushDeviceIDs: [12]).run(using: api) }
    task.cancel()
    let report = await task.value
    #expect(report.failedPushDeviceIDs == [12]); #expect(report.serverLogoutSucceeded != nil)
}
