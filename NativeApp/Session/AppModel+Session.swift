import Foundation
import Sub2Core

/// Signing out, deleting and switching sites, the scene lifecycle and ended sessions (00 §0 rule 13, §1.1, §1.7.4–§1.7.5,
/// §4.6; D11, D17–D19). The local erasure itself is `endActiveSession` in AppModel.swift.
extension AppModel {
    static let credentialClearedNotice = "此站点凭据已清除，请重新登录。"

    var isSuspended: Bool { lifecycle.isSuspended }
    /// Pages without their own scene handling reload when this changes (D18).
    var foregroundRevision: Int { lifecycle.foregroundRevision }

    /// The only scene-phase entry (Sub2MobileApp, all windows together); S0-12 and S0-13 dispatch their foreground work
    /// from here too.
    func sceneDidChange(to activity: AppActivity) {
        // Every activation, including the first after a launch while locked, which is not a resume.
        if activity == .active { reloadUnreadablePendingRecords() }
        switch lifecycle.transition(to: activity, now: Date(), lastProbe: siteSession?.probedAt) {
        case .none: return
        case .suspend: forwardToClient { await $0.suspend() }
        case .resume(let reprobe):
            forwardToClient { await $0.resume() }
            if reprobe { Task { await reprobeActiveSession() } }
        }
    }
    /// Back after more than five minutes (00 §4.6). A failed probe keeps the previous site session; a session the server
    /// ended is reported by the client instead.
    func reprobeActiveSession() async {
        do { try await reloadSiteSession() } catch { return }
    }

    /// 00 §1.7.5: erased locally first, then push devices and the JWT logout with the erased copies.
    func logout() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        guard let ended = await endActiveSession(cancelsConnection: true, then: .savedSites) else { return }
        let pushIDs = pushRecords.teardownCandidates(serverID: ended.profile.id)
        guard let report = await teardown(ended, of: ended.profile, mode: .signOut, pushDeviceIDs: pushIDs) else { return }
        pushRecords.apply(report, serverID: ended.profile.id)
    }

    /// 00 §1.1, 60 §3.4, D19: erased like signing out, the credential and device ID deleted, then the server steps with the
    /// erased copies (a `sat_` site revokes its token). Returns the report; nil when nothing was due. A site without a
    /// credential left reports the revocation and push removal it could not send.
    @discardableResult
    func remove(_ profile: ServerProfile) async -> TeardownReport? {
        guard !isSigningOut else { return nil }
        if hasPendingRecords(serverID: profile.id) { profileArchive[profile.id] = profile }
        let isActive = activeProfile?.id == profile.id
        if isActive { isSigningOut = true }
        defer { if isActive { isSigningOut = false } }
        let ended = isActive ? await endActiveSession(cancelsConnection: true, then: .savedSites) : await storedSession(of: profile)
        profiles.removeAll { $0.id == profile.id }
        if loginPrompt?.profile.id == profile.id { loginPrompt = nil }
        persistProfiles()
        let pushIDs = pushRecords.teardownCandidates(serverID: profile.id)
        pushRecords.removeAll(serverID: profile.id)
        do { try await credentials.remove(serverID: profile.id) } catch { report(error) }
        guard let result = await teardown(ended, of: profile, mode: .removeSite, pushDeviceIDs: pushIDs) else { return nil }
        // Until S0-15's receipt the notes use the root alert.
        if !result.notes.isEmpty { errorMessage = "已删除站点 · " + result.notes.joined(separator: "；") }
        return result
    }

    /// 00 §1.1: the candidate's me() decides first, so a failed switch keeps the connected site. A site without a credential,
    /// or whose session the server ended, opens its own login page.
    func switchTo(_ profile: ServerProfile) async {
        guard !isSigningOut else { return }
        let attempt = beginConnection()
        do {
            guard let credential = try await credentials.load(serverID: profile.id) else {
                if isCurrent(attempt) { openSiteLogin(profile, notice: Self.credentialClearedNotice) }
                return
            }
            try await connect(profile: profile, credential: credential, attempt: attempt)
        } catch { await connectionFailed(error, profile: profile) }
    }
    /// A switch or restore the server refused for good: the connected site ends like any invalidated session, another site
    /// has its credential erased; both open the site's login page. Any other failure keeps everything and is shown.
    func connectionFailed(_ error: any Error, profile: ServerProfile) async {
        guard let invalidation = SessionInvalidation(error: error) else { report(error); return }
        if activeProfile?.id == profile.id {
            await invalidateSession(invalidation, serverID: profile.id, generation: sessionGeneration)
            return
        }
        do { try await credentials.eraseCredential(serverID: profile.id) } catch { report(error) }
        openSiteLogin(profile, notice: invalidation.message)
    }

    /// The client reported that the server ended this session (D06): erased locally without any request (the site, its
    /// device ID and push records stay), then its login page with the reason. Reports for an older session are dropped.
    func invalidateSession(_ invalidation: SessionInvalidation, serverID: UUID, generation: UUID) async {
        guard !isSigningOut, generation == sessionGeneration, activeProfile?.id == serverID else { return }
        _ = await endActiveSession(cancelsConnection: false, then: .siteLogin(notice: invalidation.message))
    }
    /// Stage 6: this App's own session or token was just revoked (60 §5.4, §6.4), so nothing is left to sign out of.
    func forgetActiveSession(notice: String?) async {
        guard !isSigningOut else { return }
        _ = await endActiveSession(cancelsConnection: false, then: .siteLogin(notice: notice))
    }

    func openSiteLogin(_ profile: ServerProfile, notice: String?) {
        loginPrompt = LoginPrompt(profile: profile, notice: notice, reusesSiteID: !hasPendingRecords(serverID: profile.id))
    }
    /// Money records of any kind awaiting reconciliation keep the site id from being reused (D17); so does a records file
    /// that cannot be read yet, which may hold some.
    func hasPendingRecords(serverID: UUID) -> Bool { pendingMoney.mayHaveRecords(serverID: serverID) }

    /// Suspend and resume reach the client in the order the scene changed.
    private func forwardToClient(_ action: @escaping @Sendable (APIClient) async -> Void) {
        guard let client else { return }
        let previous = sceneTask
        sceneTask = Task { await previous?.value; await action(client) }
    }
    /// A saved site's credential and device ID, read before they are deleted; nil when there is nothing to send with.
    private func storedSession(of profile: ServerProfile) async -> EndedSession? {
        cancelConnection()
        guard let credential = try? await credentials.load(serverID: profile.id),
              let deviceID = try? await credentials.deviceID(serverID: profile.id) else { return nil }
        return EndedSession(profile: profile, credential: credential, deviceID: deviceID)
    }
    /// The server half, through a client without store or callback (D13) and within SiteTeardown.deadline. Without a
    /// credential nothing is sent and a deleted site reports what was not done. Fixture sites are not reachable.
    private func teardown(_ ended: EndedSession?, of profile: ServerProfile, mode: SiteTeardown.Mode, pushDeviceIDs: [Int]) async -> TeardownReport? {
        guard !isUITesting else { return nil }
        guard let ended, let credential = ended.credential else {
            return SiteTeardown.unsentReport(mode: mode, authentication: profile.authentication, pushDeviceIDs: pushDeviceIDs)
        }
        let teardown = SiteTeardown(credential: credential, mode: mode, pushDeviceIDs: pushDeviceIDs)
        guard teardown.hasNetworkSteps else { return nil }
        return await teardown.run(using: APIClient(server: ended.profile, credential: credential, deviceID: ended.deviceID))
    }
}
