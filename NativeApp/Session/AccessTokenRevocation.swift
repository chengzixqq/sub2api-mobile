import Foundation
import Sub2Core

/// 60 §6.4: revoking one of the account's access tokens. This App's own token first removes the site's push devices
/// (00 §1.7.5 step 1: once it is revoked it can no longer delete them; a failure is kept for later and blocks nothing), then
/// sends the DELETE. A reply that the revoked token was this App's ends the session locally, without a logout request; a
/// token already gone counts as revoked. No idempotency key and no step-up: sending it again changes nothing.
struct AccessTokenRevocation: Sendable {
    struct Outcome: Sendable {
        enum Kind: Sendable, Equatable { case revoked, alreadyGone, revokedCurrent, failed }
        let kind: Kind
        /// The reason a `.failed` revocation shows.
        let failure: (any Error)?
        /// What became of the site's push devices, for `PushDeviceRecords.apply`; nil when they were not touched.
        let pushReport: TeardownReport?
        init(kind: Kind, failure: (any Error)? = nil, pushReport: TeardownReport? = nil) {
            self.kind = kind; self.failure = failure; self.pushReport = pushReport
        }
    }
    static let currentRevokedNotice = "已吊销本机正在使用的令牌，请重新登录"

    let tokenID: Int
    /// The list's `current`: the token this App signs in with.
    let isCurrent: Bool
    let pushDeviceIDs: [Int]
    let credential: Credential

    /// Throws only CancellationError.
    func run(using api: some SiteTeardownAPI) async throws -> Outcome {
        // The sign-out half of SiteTeardown: with a `sat_` credential it only deletes push devices, never logs out.
        let pushReport = removesPushDevicesFirst
            ? await SiteTeardown(credential: credential, mode: .signOut, pushDeviceIDs: pushDeviceIDs).run(using: api) : nil
        do {
            guard try await api.revokeAccessToken(id: tokenID) else { return Outcome(kind: .revoked, pushReport: pushReport) }
            // A stale row that was this App's token after all: its push devices could not be deleted any more.
            return Outcome(kind: .revokedCurrent, pushReport: pushReport ?? TeardownReport(failedPushDeviceIDs: pushDeviceIDs))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError where error.category == .notFound {
            return Outcome(kind: .alreadyGone, pushReport: pushReport)
        } catch {
            return Outcome(kind: .failed, failure: error, pushReport: pushReport)
        }
    }

    private var removesPushDevicesFirst: Bool {
        guard isCurrent, case .accessToken = credential else { return false }
        return true
    }
}
