import Foundation
import Observation
import Sub2Core

/// What 新建账号 reads of the session when the admin taps “创建并测试” (S2D1-05); its generation goes with every write.
struct AccountCreateSession: Sendable, Equatable {
    let generation: UUID
    /// admin.idempotent_writes: the stop-scheduling carries a key. The create always does (00 §2.5.1): the backend has deduplicated
    /// admin.accounts.create by key since well before this capability.
    let idempotentWrites: Bool
    /// accounts.mixed_channel_details: sent straight away and asked about on the 409 (20 §7.4-1).
    let mixedChannelDetails: Bool
    let isReadOnlyToken: Bool
}

/// The writes and the by-name read-back of 新建账号 (AppModel+Accounts). A write throws CancellationError once the session it was
/// tapped in has ended.
@MainActor protocol AccountCreateSource: AnyObject {
    var accountCreateSession: AccountCreateSession? { get }
    func serverNow() -> Date
    func createAccount(_ request: AccountCreateRequest, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler?,
                       generation: UUID) async throws -> WriteOutcome<UpstreamAccount>
    func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?, generation: UUID) async throws -> MixedChannelCheck
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount>
    /// 20 §7.5: `GET admin/accounts?search={name}&lite=1` matched by AccountCreateReconciliation; nil when it is not there.
    func findCreatedAccount(name: String, platform: String, notBefore: Date) async throws -> UpstreamAccount?
}

/// 20 §7.4-1 / §7.5 “创建并测试” up to an account that exists outside the scheduler (S2D1-13: the create and stop-scheduling
/// stages). The key is made at the tap (R05), on every site (00 §2.5.1), and the request frozen with it; Anthropic / Antigravity
/// groups are checked first without accounts.mixed_channel_details, otherwise the 409 asks; “继续创建” sends the confirmation under
/// a new key and the same groups are not asked about again in this flow. A server that ignores `schedulable: false` gets a
/// separate stop. An unknown result is looked up by name: found counts as created, not found offers the same number again. A
/// result that arrives after the session changed is dropped. The request holds the credentials, so nothing here is logged.
@MainActor @Observable
final class AccountNewSubmission {
    enum Stage: Equatable, Sendable {
        case idle
        case checkingMixedChannel
        case confirmingMixedChannel(MixedChannelWarning)
        /// `confirming`: the same key went out again (KeyedWriteEvent), “正在确认结果…”.
        case creating(confirming: Bool)
        case pausing(accountID: Int)
        /// Created and outside the scheduler.
        case created(accountID: Int)
        case pauseUnconfirmed(accountID: Int, reason: String)
        /// Refused for certain (4xx, a 409 other than the mixed channel, 429): the next tap takes a new key.
        case rejected(reason: String)
        /// The security sheet cleared it (00 §2.6.2 step 4): the same request tapped again keeps its key.
        case reconfirm(notice: String)
        case reconciling
        /// The by-name check failed as well: 核对 again, or the same number.
        case unconfirmed(reason: String)
        /// The by-name check did not find it: the same number again.
        case notCreated
    }
    enum Failure: Equatable, Sendable {
        case cancelled
        case mixedChannel(MixedChannelWarning)
        /// An older server's 409 without metadata (or a MIXED_CHANNEL_WARNING without it); the catalog's words if no group tells.
        case mixedChannelWithoutDetails(String)
        case reconfirm(String)
        case needsNewKey(String)
        case rejected(String)
        case unconfirmed
    }

    private(set) var stage: Stage = .idle
    /// The created account (or the one the check found), then the stop's answer.
    private(set) var account: UpstreamAccount?
    @ObservationIgnored private let source: any AccountCreateSource
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    @ObservationIgnored private var frozen: AccountNewFrozenRequest?
    @ObservationIgnored private var session: AccountCreateSession?
    /// The groups 继续创建 accepted in this flow.
    @ObservationIgnored private var confirmedGroups: Set<Int>?

    init(source: any AccountCreateSource, makeKey: @escaping @MainActor () -> UUID = { UUID() }) {
        self.source = source; self.makeKey = makeKey
    }

    var isBusy: Bool {
        switch stage {
        case .checkingMixedChannel, .creating, .pausing, .reconciling: true
        default: false
        }
    }
    /// The account exists (or may): its id.
    var createdAccountID: Int? {
        switch stage {
        case .pausing(let id), .created(let id), .pauseUnconfirmed(let id, _): id
        default: account?.id
        }
    }
    /// 00 §2.5.4 step 4: nothing can be edited while a result is out or the account exists.
    var locksForm: Bool {
        if isBusy || createdAccountID != nil { return true }
        if case .unconfirmed = stage { return true }
        return false
    }
    /// The subtitle's third part once the account exists.
    var scheduleStatus: AccountNewScheduleStatus {
        if case .created = stage { return .paused }
        return .unconfirmed
    }
    /// The frozen request carries a key: “用同一编号重试” rather than a plain resend.
    var isKeyed: Bool { frozen?.key != nil }

    // MARK: Creating

    /// “创建并测试”: the key is made now and the request frozen with it; a request cleared by the security sheet keeps both.
    func submit(_ request: AccountCreateRequest) async {
        guard canSubmit, let current = source.accountCreateSession, !current.isReadOnlyToken else { return }
        let outgoing = outgoing(request)
        if case .reconfirm = stage, let frozen, frozen.request == outgoing, session?.generation == current.generation {
            await send()
            return
        }
        session = current
        frozen = AccountNewFrozenRequest(request: outgoing, key: makeKey(), submittedAt: source.serverNow())
        let confirmed = outgoing.confirmMixedChannelRisk
        if AccountNewFlow.needsMixedChannelPrecheck(platform: outgoing.platform, groupIDs: outgoing.groupIDs,
                                                    hasMixedChannelDetails: current.mixedChannelDetails, alreadyConfirmed: confirmed) {
            guard await precheck(outgoing, current) else { return }
        }
        await send()
    }
    /// “继续创建”: these groups are accepted for the flow; the body changes, so a keyed request takes a new key (00 §2.5.2).
    func confirmMixedChannel() async {
        guard case .confirmingMixedChannel = stage, let frozen, let session, isCurrent(session) else { return }
        confirmedGroups = Set(frozen.request.groupIDs)
        self.frozen = frozen.confirmingMixedChannel(renewingKeyWith: makeKey())
        await send()
    }
    /// “返回修改分组”: nothing is sent.
    func declineMixedChannel() {
        guard case .confirmingMixedChannel = stage else { return }
        frozen = nil
        stage = .idle
    }
    /// 核对 after the check itself failed.
    func reconcile() async {
        guard case .unconfirmed = stage else { return }
        await lookUp()
    }
    /// 用同一编号重试: the same key and bytes (00 §2.5.3).
    func retrySameKey() async {
        switch stage {
        case .notCreated, .unconfirmed: break
        default: return
        }
        guard let session, isCurrent(session) else { return }
        await send()
    }
    /// 重试停止调度: a new intent, so a new key.
    func retryPause() async {
        guard case .pauseUnconfirmed(let id, _) = stage, let session, isCurrent(session) else { return }
        await pause(id, session)
    }
    /// The form changed after a refusal, a cleared prompt or a check that found nothing: the frozen request and its key go.
    func draftDidChange(_ request: AccountCreateRequest?) {
        switch stage {
        case .rejected, .reconfirm, .notCreated: break
        default: return
        }
        guard request.map(outgoing) != frozen?.request || frozen == nil else { return }
        frozen = nil
        stage = .idle
    }

    // MARK: Sending

    private var canSubmit: Bool {
        switch stage {
        case .idle, .rejected, .reconfirm: true
        default: false
        }
    }
    private func outgoing(_ request: AccountCreateRequest) -> AccountCreateRequest {
        guard let confirmedGroups, !request.groupIDs.isEmpty, Set(request.groupIDs) == confirmedGroups else { return request }
        return request.confirmingMixedChannel()
    }
    private func isCurrent(_ session: AccountCreateSession) -> Bool { source.accountCreateSession?.generation == session.generation }

    /// false when the admin is asked first, or the check failed.
    private func precheck(_ request: AccountCreateRequest, _ session: AccountCreateSession) async -> Bool {
        stage = .checkingMixedChannel
        do {
            let check = try await source.checkMixedChannel(platform: request.platform, groupIDs: request.groupIDs, accountID: nil,
                                                           generation: session.generation)
            guard isCurrent(session) else { return false }
            guard let warning = MixedChannelWarning(check: check) else { return true }
            stage = .confirmingMixedChannel(warning)
        } catch {
            guard isCurrent(session) else { return false }
            frozen = nil
            switch Self.failure(of: error, mixedPlatform: false) {
            case .cancelled: stage = .idle
            case .reconfirm(let text), .rejected(let text), .needsNewKey(let text), .mixedChannelWithoutDetails(let text): stage = .rejected(reason: text)
            case .mixedChannel, .unconfirmed: stage = .rejected(reason: AccountActionCopy.reason(for: error))
            }
        }
        return false
    }
    private func send() async {
        guard let frozen, let session else { return }
        stage = .creating(confirming: false)
        let outcome: WriteOutcome<UpstreamAccount>
        do {
            outcome = try await source.createAccount(frozen.request, idempotencyKey: frozen.key, onEvent: { [weak self] event in
                await self?.note(event)
            }, generation: session.generation)
        } catch {
            guard isCurrent(session) else { return }
            await settle(error, frozen, session)
            return
        }
        guard isCurrent(session) else { return }
        await take(outcome.value, session)
    }
    private func note(_ event: KeyedWriteEvent) {
        guard case .creating(false) = stage else { return }
        switch event {
        case .confirming, .waitingForServer: stage = .creating(confirming: true)
        case .actionID: break
        }
    }
    private func settle(_ error: any Error, _ frozen: AccountNewFrozenRequest, _ session: AccountCreateSession) async {
        let mixedPlatform = [OAuthPlatform.anthropic.rawValue, OAuthPlatform.antigravity.rawValue].contains(frozen.request.platform)
        switch Self.failure(of: error, mixedPlatform: mixedPlatform) {
        case .cancelled:
            self.frozen = nil
            stage = .idle
        case .mixedChannel(let warning): stage = .confirmingMixedChannel(warning)
        case .mixedChannelWithoutDetails(let reason): await askForDetails(frozen.request, reason: reason, session)
        case .reconfirm(let notice): stage = .reconfirm(notice: notice)
        case .needsNewKey(let reason), .rejected(let reason):
            self.frozen = nil
            stage = .rejected(reason: reason)
        case .unconfirmed: await lookUp()
        }
    }
    /// An older server's 409 names no group: check-mixed-channel does, when there are groups to ask about.
    private func askForDetails(_ request: AccountCreateRequest, reason: String, _ session: AccountCreateSession) async {
        if !request.groupIDs.isEmpty {
            stage = .checkingMixedChannel
            let check = try? await source.checkMixedChannel(platform: request.platform, groupIDs: request.groupIDs, accountID: nil,
                                                            generation: session.generation)
            guard isCurrent(session) else { return }
            if let warning = check.flatMap(MixedChannelWarning.init(check:)) {
                stage = .confirmingMixedChannel(warning)
                return
            }
        }
        frozen = nil
        stage = .rejected(reason: reason)
    }
    /// 20 §7.5: by name and platform, created no earlier than the first send.
    private func lookUp() async {
        guard let frozen, let session, isCurrent(session) else { return }
        stage = .reconciling
        do {
            let found = try await source.findCreatedAccount(name: frozen.request.name, platform: frozen.request.platform, notBefore: frozen.submittedAt)
            guard isCurrent(session) else { return }
            guard let found else { stage = .notCreated; return }
            await take(found, session)
        } catch {
            guard isCurrent(session) else { return }
            stage = .unconfirmed(reason: KeyedWriteFailure.unconfirmedMessage)
        }
    }
    private func take(_ created: UpstreamAccount, _ session: AccountCreateSession) async {
        account = created
        frozen = nil
        guard created.schedulable else { stage = .created(accountID: created.id); return }
        await pause(created.id, session)
    }
    /// An older server ignored `schedulable: false` (20 §7.4-1).
    private func pause(_ id: Int, _ session: AccountCreateSession) async {
        stage = .pausing(accountID: id)
        do {
            let outcome = try await source.setAccountSchedulable(id: id, enabled: false, idempotencyKey: session.idempotentWrites ? makeKey() : nil,
                                                                 generation: session.generation)
            guard isCurrent(session) else { return }
            account = outcome.value
            stage = .created(accountID: id)
        } catch {
            guard isCurrent(session) else { return }
            let cancelled = AccountActionCopy.disposition(of: error) == .cancelled
            stage = .pauseUnconfirmed(accountID: id, reason: cancelled ? AccountActionCopy.unconfirmed : AccountActionCopy.reason(for: error))
        }
    }

    // MARK: Classifying

    /// 00 §2.4 / §2.5.4 for a create: a transport failure, a timeout or a 5xx may have created it (the account is stored before its
    /// groups), so it is looked up; a 4xx was refused. The words are the catalog's, never the server's.
    nonisolated static func failure(of error: any Error, mixedPlatform: Bool) -> Failure {
        if error is CancellationError { return .cancelled }
        if let keyed = error as? KeyedWriteFailure {
            if case .needsNewKey = keyed.disposition { return .needsNewKey(keyed.localizedDescription) }
            return .unconfirmed
        }
        guard let api = error as? APIError else { return .unconfirmed }
        switch api.securityOutcome {
        case .cancelled?: return .cancelled
        case .passed?: return .reconfirm(api.localizedDescription)
        case .blocked?, nil: break
        }
        if let warning = MixedChannelWarning(error: api) { return .mixedChannel(warning) }
        if mixedPlatform, AccountNewFlow.mayBeMixedChannelConflict(api) { return .mixedChannelWithoutDetails(api.localizedDescription) }
        guard let status = api.statusCode else {
            let sent = (api.kind == .transport && api != .refreshDeferred) || api == .invalidResponse
            return sent ? .unconfirmed : .rejected(api.localizedDescription)
        }
        if status == 408 || status >= 500 { return .unconfirmed }
        return .rejected(AccountActionCopy.reason(for: api))
    }
}
