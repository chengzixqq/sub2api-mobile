import Foundation
import os
import Sub2Core

/// What the server-side teardown calls; `APIClient` is the real one, tests pass a recorder.
protocol SiteTeardownAPI: Sendable {
    func deletePushDevice(id: Int) async throws
    func accessTokens() async throws -> [AdminAccessToken]
    func revokeAccessToken(id: Int) async throws -> Bool
    func logout() async throws
}
extension APIClient: SiteTeardownAPI {}

/// Copies of what a local erasure removed, for the server-side steps that follow it.
struct EndedSession: Sendable {
    let profile: ServerProfile
    /// nil when the client no longer held one; then nothing can be sent.
    let credential: Credential?
    let deviceID: UUID
}

/// What the server-side steps achieved; only `notes` reach the user (60 §3.4 receipt, D19).
struct TeardownReport: Sendable, Equatable {
    var deletedPushDeviceIDs: [Int] = []
    var failedPushDeviceIDs: [Int] = []
    /// nil when no token revocation was due (signing out, or not a `sat_` site).
    var accessTokenRevoked: Bool?
    /// nil for a key: only a JWT session signs out on the server.
    var serverLogoutSucceeded: Bool?
    var notes: [String] = []
}

/// The server half of signing out and deleting a site, in the fixed order of 00 §1.7.5 and 60 §3.4: push devices first
/// (revoking a session leaves them behind), then the `sat_` revocation (deleting a site only) or the JWT logout. The local
/// erasure has already happened, so every failure is recorded and nothing stops the next step.
struct SiteTeardown: Sendable {
    enum Mode: Sendable { case signOut, removeSite }
    /// A deleted `sat_` site sends up to four requests; past this the remaining steps are abandoned and reported.
    static let deadline: Duration = .seconds(20)
    static let tokenNotRevokedNote = "令牌未能吊销，可用 API 吊销"
    static let pushNotRemovedNote = "推送设备未能从站点移除，可在 Web 删除"
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "session")

    let credential: Credential
    let mode: Mode
    let pushDeviceIDs: [Int]

    var hasNetworkSteps: Bool { !pushDeviceIDs.isEmpty || signsOutOnServer || revokesAccessToken }
    private var signsOutOnServer: Bool { if case .tokens = credential { true } else { false } }
    private var revokesAccessToken: Bool { if mode == .removeSite, case .accessToken = credential { true } else { false } }

    /// Deleting a site whose credential is already gone (signed out, cleared, or unreadable) sends nothing, so what the
    /// confirmation promised is reported as not done (60 §3.4). nil when nothing was due.
    static func unsentReport(mode: Mode, authentication: AuthenticationKind, pushDeviceIDs: [Int]) -> TeardownReport? {
        guard mode == .removeSite else { return nil }
        var report = TeardownReport(failedPushDeviceIDs: pushDeviceIDs)
        if !pushDeviceIDs.isEmpty { report.notes.append(pushNotRemovedNote) }
        if authentication == .accessToken { report.accessTokenRevoked = false; report.notes.append(tokenNotRevokedNote) }
        return report.notes.isEmpty ? nil : report
    }

    /// Cancelled when the deadline passes; unfinished steps count as failed.
    func run(using api: some SiteTeardownAPI, within deadline: Duration = Self.deadline) async -> TeardownReport {
        let work = Task { await perform(using: api) }
        let timer = Task { if (try? await Task.sleep(for: deadline)) != nil { work.cancel() } }
        defer { timer.cancel() }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func perform(using api: some SiteTeardownAPI) async -> TeardownReport {
        var report = TeardownReport()
        for id in pushDeviceIDs {
            if await deletePushDevice(id, using: api) { report.deletedPushDeviceIDs.append(id) } else { report.failedPushDeviceIDs.append(id) }
        }
        if mode == .removeSite, !report.failedPushDeviceIDs.isEmpty { report.notes.append(Self.pushNotRemovedNote) }
        if revokesAccessToken {
            let revoked = await revokeCurrentToken(using: api)
            report.accessTokenRevoked = revoked
            if !revoked { report.notes.append(Self.tokenNotRevokedNote) }
        }
        if signsOutOnServer {
            do { try await api.logout(); report.serverLogoutSucceeded = true }
            catch { Self.record(error, step: "POST auth/logout"); report.serverLogoutSucceeded = false }
        }
        return report
    }

    /// A device the server no longer has counts as deleted (00 §3.2 “DELETE 时收到不存在视为已删除”).
    private func deletePushDevice(_ id: Int, using api: some SiteTeardownAPI) async -> Bool {
        do { try await api.deletePushDevice(id: id); return true }
        catch let error as APIError where error.category == .notFound || error.category == .unsupported { return true }
        catch { Self.record(error, step: "DELETE admin/push/devices/:id"); return false }
    }
    /// The token this App uses is the `current` one. Only a rejected credential (INVALID_ADMIN_KEY, ACCESS_TOKEN_EXPIRED) or
    /// a token already gone needs no revoking; other session-ending replies (owner disabled, a proxy's 401) leave it valid.
    private func revokeCurrentToken(using api: some SiteTeardownAPI) async -> Bool {
        do {
            guard let current = try await api.accessTokens().first(where: \.current) else { return false }
            _ = try await api.revokeAccessToken(id: current.id)
            return true
        } catch let error as APIError where error.category == .notFound || error.action == .clearCredential {
            return true
        } catch {
            Self.record(error, step: "DELETE admin/access-tokens/:id")
            return false
        }
    }
    /// Path template, status, reason and request ID only (00 §3.4).
    private static func record(_ error: any Error, step: String) {
        guard let error = error as? APIError else {
            log.notice("\(step, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        log.notice("\(step, privacy: .public) failed: \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public) \(error.requestID ?? "-", privacy: .public)")
    }
}

/// D19: where a deletion ends up. Another site's deletion ends with a receipt while a site is still connected; after the
/// connected one, or when no site is left by the time the server steps end, the notes use the root alert, so a token left
/// unrevoked is never dropped silently.
enum SiteRemovalNotice: Equatable {
    case receipt(notes: [String])
    case alert(String)
    case silent

    static func after(removingCurrent: Bool, hasReceiptHost: Bool, notes: [String]) -> SiteRemovalNotice {
        if !removingCurrent && hasReceiptHost { return .receipt(notes: notes) }
        return notes.isEmpty ? .silent : .alert(Receipt.siteRemoved(notes: notes).text)
    }
}
