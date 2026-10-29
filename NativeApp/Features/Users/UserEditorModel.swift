import Foundation
import Observation
import Sub2Core

extension UserEditSegment {
    init(_ section: UserDraftSection) { self = section == .basic ? .basic : .access }
}

/// A message that stays on the page until the next press of “创建用户”, with the answer's “详情” when there is one.
struct UserEditNotice: Equatable {
    let text: String
    let details: ErrorDetails?
}

/// 30 §5 / §6 (S3-10): the state of the new and edit user page. This item fills in `.create`; S3-11 adds the edit state in
/// UserEditorModel+Edit / +Save. The password and the frozen request live only here and are dropped when the page goes away.
@MainActor @Observable
final class UserEditorModel {
    enum Mode: Hashable, Sendable { case create, edit(userID: Int) }
    enum Phase: Equatable { case editing, confirming(UserCreateConfirmation), submitting }
    /// Where the page scrolls after a failed check; a new value each time, so the same row can be asked for twice.
    struct FocusRequest: Equatable {
        let field: UserDraftField
        let id = UUID()
    }
    enum DefinitionsState: Equatable { case loading, loaded, failed }

    let mode: Mode
    var segment: UserEditSegment
    var draft = UserAccessDraft()
    private(set) var definitions: [UserAttributeDefinition] = []
    private(set) var definitionsState = DefinitionsState.loading
    /// Issues show from the first press of “创建用户” on (design `showErrors`).
    private(set) var showsIssues = false
    /// The rows the last refusal marked (30 §5.5).
    private(set) var serverMarks: UserServerMarks?
    private(set) var phase = Phase.editing
    private(set) var notice: UserEditNotice?
    private(set) var focusRequest: FocusRequest?
    /// The number made at the last confirmation and the draft it was made for (R05): sent again only for that same draft,
    /// after a result nobody could confirm only once the address is read back (00 §2.5.4).
    @ObservationIgnored private var frozen: (operation: PendingUserCreateOperation, draft: UserAccessDraft, readsBackFirst: Bool)?
    @ObservationIgnored private var lastConfirmation: UserCreateConfirmation?
    /// 00 §2.5.3: after IDEMPOTENCY_STORE_UNAVAILABLE the kept number waits until then.
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var isClosed = false

    init(mode: Mode, segment: UserEditSegment = .basic) {
        self.mode = mode; self.segment = segment
    }

    var isFrozen: Bool { phase == .submitting }
    var hasContent: Bool { draft.hasContent }
    var displayName: String { UserEditCopy.newUserName(username: draft.username, email: draft.email) }
    var initial: String? { UserEditCopy.newUserInitial(username: draft.username, email: draft.email) }
    var identityTail: String { UserEditCopy.newUserTail(role: draft.role) }

    /// The local check in form order, then the last refusal's marks while their rows hold what was sent.
    var issues: [UserDraftIssue] {
        let local = draft.issues(against: nil, definitions: definitions)
        let fields = Set(local.map(\.field))
        return local + (serverMarks?.standing(in: draft) ?? []).filter { !fields.contains($0.field) }
    }
    func issue(for field: UserDraftField) -> String? {
        guard showsIssues else { return nil }
        return issues.first { $0.field == field }?.message
    }
    func issueCount(in segment: UserEditSegment) -> Int {
        guard showsIssues else { return 0 }
        return issues.filter { UserEditSegment($0.field.section) == segment }.count
    }

    // MARK: - 加载

    /// 30 §5.6: from the session's cache when it has them (the group directory loads on its own).
    func loadDefinitions(model: AppModel) async {
        definitionsState = .loading
        do {
            definitions = try await model.loadUserAttributeDefinitions()
            definitionsState = .loaded
        } catch { definitionsState = error is CancellationError ? .loading : .failed }
    }

    // MARK: - 表单操作

    func setRestrictPublicGroups(_ on: Bool, catalog: UserGroupCatalog) { draft = draft.settingRestrictPublicGroups(on, catalog: catalog) }
    func setPublicGroup(_ id: Int, allowed: Bool) {
        guard draft.restrictPublicGroups else { return }
        if allowed { draft.publicGroupIDs.insert(id) } else { draft.publicGroupIDs.remove(id) }
    }
    func addExclusiveGroups(_ ids: Set<Int>) { draft.exclusiveGroupIDs.formUnion(ids) }
    func removeExclusiveGroup(_ id: Int) { draft.exclusiveGroupIDs.remove(id) }
    func generatePassword() { draft.password = UserAccessDraft.randomPassword() }
    /// The steppers: never below 0 nor above the server's int32.
    func step(_ field: UserDraftField, by delta: Int) {
        func next(_ value: Int?) -> Int { min(max((value ?? 0) + delta, 0), Int(Int32.max)) }
        switch field {
        case .concurrency: draft.concurrency = next(draft.concurrency)
        case .rpmLimit: draft.rpmLimit = next(draft.rpmLimit)
        default: break
        }
    }

    // MARK: - 创建

    /// 30 §5.4 steps 1–4.
    func create(model: AppModel, router: AppRouter) async {
        guard phase == .editing, mode == .create else { return }
        showsIssues = true
        notice = nil
        let current = issues
        if let first = current.first {
            model.receipts.show(Receipt(text: UserCreateReceipt.pendingIssues(current.count), systemImage: "exclamationmark.circle", tone: .caution))
            jump(to: first.field)
            return
        }
        let balance = try? UserAccessDraft.initialBalance(draft.initialBalance)
        let siteName = model.activeProfile?.name ?? ""
        switch UserCreatePlan(role: draft.role ?? .user, initialBalance: balance) {
        case .send:
            lastConfirmation = nil
            await submit(model: model, router: router)
        case .confirmInitialBalance(let amount):
            present(.initialBalance(name: displayName, amount: amount, siteName: siteName,
                                    hasBalanceLedger: model.siteSession?.has(.usersBalanceLedger) == true,
                                    faceIDLine: model.biometricGate.amountConfirmationLine(amount: amount)))
        case .stepUpThenConfirm:
            await stepUpThenConfirm(model: model, balance: balance, siteName: siteName)
        }
    }
    /// The confirmation's button: Face ID (inside the submission) and the send.
    func confirm(model: AppModel, router: AppRouter) async {
        guard !isFrozen else { return }
        await submit(model: model, router: router)
    }
    func cancelConfirmation() {
        if case .confirming = phase { phase = .editing }
    }
    func reopen() { isClosed = false }
    /// The page went away: the password and the frozen request go with it.
    func close() {
        isClosed = true
        draft.password = ""
        frozen = nil
    }

    /// 30 §0.4: verified first; the confirmation's first sentence only when the site has step-up on (S3D1-01).
    private func stepUpThenConfirm(model: AppModel, balance: Decimal?, siteName: String) async {
        let verified = model.siteSession?.me.security.stepUpEnabled == true
        switch await model.ensureStepUp(purpose: UserEditCopy.stepUpPurpose) {
        case .passed:
            guard !isClosed else { return }
            present(.administrator(name: displayName, initialBalance: balance, siteName: siteName, stepUpVerified: verified,
                                   faceIDLine: balance.flatMap { model.biometricGate.amountConfirmationLine(amount: $0) }))
        case .cancelled:
            break
        case .blocked(let text):
            model.receipts.show(Receipt(text: text, systemImage: "lock", tone: .caution))
        }
    }
    private func present(_ confirmation: UserCreateConfirmation) {
        lastConfirmation = confirmation
        phase = .confirming(confirmation)
    }
    private func submit(model: AppModel, router: AppRouter) async {
        let request: UserCreateRequest
        do { request = try draft.createRequest() } catch {
            phase = .editing
            model.receipts.show(Receipt(text: error.localizedDescription, systemImage: "exclamationmark.circle", tone: .caution))
            return
        }
        let sent = draft
        let kept = frozen.flatMap { $0.draft == sent ? $0 : nil }
        if kept != nil, let holdUntil, Date() < holdUntil {
            phase = .editing
            model.receipts.show(Receipt(text: UserCreateFailure.storeUnavailable, systemImage: "clock", tone: .caution))
            return
        }
        phase = .submitting
        let submission = UserCreateSubmission(effects: model.userCreateEffects(isPageAlive: { [weak self] in self?.isClosed == false }))
        let outcome = await submission.run(request: request, attributes: sent.attributeChanges(from: nil, definitions: definitions),
                                           reusing: kept?.operation, readsBackFirst: kept?.readsBackFirst == true)
        await finish(outcome, sent: sent, balance: request.balance, model: model, router: router)
    }
    private func finish(_ outcome: UserCreateSubmission.Outcome, sent: UserAccessDraft, balance: Decimal?, model: AppModel, router: AppRouter) async {
        switch outcome {
        case .created(let user, let saved, _):
            land(on: user, model: model, router: router)
            let text = saved ? UserCreateReceipt.created(name: user.displayName, initialBalance: balance) : UserCreateReceipt.attributesFailed
            model.receipts.show(Receipt(text: text, systemImage: saved ? "checkmark.circle" : "exclamationmark.triangle", tone: saved ? .ok : .caution))
        case .foundOnServer(let user, let saved):
            land(on: user, model: model, router: router)
            let text = saved ? UserCreateReceipt.foundOnServer : UserCreateReceipt.attributesFailed
            model.receipts.show(Receipt(text: text, systemImage: saved ? "checkmark.circle" : "exclamationmark.triangle", tone: saved ? .ok : .caution))
        case .notCreated(let operation):
            keep(operation, for: sent, readsBackFirst: false, saying: UserCreateReceipt.notCreated, model: model)
        case .unconfirmed(let operation):
            keep(operation, for: sent, readsBackFirst: true,
                 saying: UserCreateReceipt.unconfirmed(sendsIdempotencyKey: operation.sendsIdempotencyKey), model: model)
        case .failed(let failure, let operation):
            await refused(failure, operation: operation, sent: sent, model: model, router: router)
        case .notAuthorized, .stale:
            phase = .editing
        }
    }
    /// 30 §5.5: rows marked, the page sent to the first one, the form open again; a cleared prompt confirms the same number.
    private func refused(_ failure: UserCreateFailure, operation: PendingUserCreateOperation?, sent: UserAccessDraft, model: AppModel,
                         router: AppRouter) async {
        phase = .editing
        frozen = operation.map { (operation: $0, draft: sent, readsBackFirst: false) }
        holdUntil = failure.retryNotBefore
        if !failure.fieldIssues.isEmpty {
            serverMarks = UserServerMarks(failure.fieldIssues, sent: sent)
            showsIssues = true
            jump(to: failure.fieldIssues[0].field)
        }
        if let details = failure.details { notice = UserEditNotice(text: failure.receipt ?? "", details: ErrorDetails(details)) }
        if let text = failure.receipt { model.receipts.show(Receipt(text: text, systemImage: "xmark.octagon", tone: .critical)) }
        guard failure.next == .reconfirm, !isClosed else { return }
        if let lastConfirmation { phase = .confirming(lastConfirmation) } else { await submit(model: model, router: router) }
    }
    /// 30 §5.4 step 7: back to the form with the number kept for the same draft, and the words on the page until the next press.
    private func keep(_ operation: PendingUserCreateOperation, for sent: UserAccessDraft, readsBackFirst: Bool, saying text: String,
                      model: AppModel) {
        phase = .editing
        frozen = (operation: operation, draft: sent, readsBackFirst: readsBackFirst)
        notice = UserEditNotice(text: text, details: nil)
        model.receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution))
    }
    /// 30 §5.1: the new page leaves the stack for the user's detail; the list reads its first page when it shows again.
    private func land(on user: AdminUser, model: AppModel, router: AppRouter) {
        model.userList?.setNeedsRefresh()
        close()
        let tab = router.selectedTab
        var path = router.path(for: tab)
        guard let index = path.lastIndex(of: .userNew) else { router.push(.user(id: user.id)); return }
        path.removeSubrange(index...)
        router.setPath(path + [.user(id: user.id)], for: tab)
    }
    private func jump(to field: UserDraftField) {
        segment = UserEditSegment(field.section)
        focusRequest = FocusRequest(field: field)
    }
}
