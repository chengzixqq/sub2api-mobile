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

/// 30 §5 / §6: the state of the new (S3-10) and edit (S3-11, UserEditorModel+Edit / +Save) user page. The password and the
/// frozen request live only here and are dropped when the page goes away.
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
    /// Issues show from the first press of “创建用户” / “保存” on (design `showErrors`).
    var showsIssues = false
    /// The rows the last refusal marked (30 §5.5, §6.5).
    var serverMarks: UserServerMarks?
    private(set) var phase = Phase.editing
    private(set) var notice: UserEditNotice?
    private(set) var focusRequest: FocusRequest?
    /// The number made at the last confirmation and the draft it was made for (R05): sent again only for that same draft,
    /// after a result nobody could confirm only once the address is read back (00 §2.5.4).
    @ObservationIgnored private var frozen: (operation: PendingUserCreateOperation, draft: UserAccessDraft, readsBackFirst: Bool)?
    @ObservationIgnored private var lastConfirmation: UserCreateConfirmation?
    /// 00 §2.5.3: after IDEMPOTENCY_STORE_UNAVAILABLE the kept number waits until then.
    @ObservationIgnored var holdUntil: Date?
    @ObservationIgnored private(set) var isClosed = false

    // MARK: 编辑态（S3-11）：UserEditorModel+Edit / +Save 写，S3-12 只读（S3D1-13）
    enum EditLoad: Equatable { case loading, loaded, failed(String?), missing }
    var editLoad = EditLoad.loading
    /// The server's user when the page opened (30 §6.6): immediate writes move it, polling never does.
    private(set) var baseline: UserBaseline?
    /// The directory the draft's groups are read against (X11).
    private(set) var catalog = UserGroupCatalog.empty
    /// The profile as last read: the identity strip and the confirmations' name.
    var stripUser: AdminUser?
    var isSelf = false
    /// What took effect since the page opened (30 §6.4 离开).
    private(set) var applied: [String] = []
    /// The user's keys, for “绑定 N 个 Key” and the third segment's count; S3-12 replaces it with its UserKeysModel.
    private(set) var boundKeys: [AdminAPIKey]?
    var saveProgress: UserSaveProgress?
    /// S3D1-11: immediate writes out now; “保存” waits for them, they wait for “保存”.
    private(set) var immediateWritesInFlight = 0
    var dialog: UserEditDialog?
    var deleteRequest: DeleteRequest?
    var didDelete = false
    /// The role a last-administrator check refused (U30); its message stands while the draft keeps that role.
    var lastAdminRole: AdminUserRole?
    var passwordFoldOpen = false
    /// `UserChangeSignal.balanceRevision` when the page opened: a larger one adds “余额” to the leave confirmation.
    @ObservationIgnored var entryBalanceRevision: Int?
    @ObservationIgnored var keptUpdate: KeptUserUpdate?
    /// The user's attribute values, until the profile has made the base.
    @ObservationIgnored private var attributeValues: [Int: String]?

    init(mode: Mode, segment: UserEditSegment = .basic) {
        self.mode = mode; self.segment = segment
    }

    var isFrozen: Bool { phase == .submitting || saveProgress != nil }
    var hasContent: Bool { draft.hasContent }
    var displayName: String { UserEditCopy.newUserName(username: draft.username, email: draft.email) }
    var initial: String? { UserEditCopy.newUserInitial(username: draft.username, email: draft.email) }
    var identityTail: String { UserEditCopy.newUserTail(role: draft.role) }

    /// The local check in form order, then the last refusal's marks while their rows hold what was sent.
    var issues: [UserDraftIssue] {
        let local = draft.issues(against: baseline, definitions: definitions)
        let fields = Set(local.map(\.field))
        let lastAdmin = lastAdminRole != nil && draft.role == lastAdminRole ? [UserDraftIssue(field: .role, message: UserEditCopy.lastAdminField)] : []
        return local + ((serverMarks?.standing(in: draft) ?? []) + lastAdmin).filter { !fields.contains($0.field) }
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

    /// 30 §5.6: from the session's cache when it has them (the group directory loads on its own). Editing, the user's values
    /// come with them (30 §6.2), and the rows show only once both are in.
    func loadDefinitions(model: AppModel) async {
        definitionsState = .loading
        do {
            let loaded = try await model.loadUserAttributeDefinitions()
            if case .edit(let id) = mode { adoptAttributes(try await model.userAttributes(userID: id)) }
            definitions = loaded
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
        keptUpdate = nil
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
    func jump(to field: UserDraftField) {
        segment = UserEditSegment(field.section)
        focusRequest = FocusRequest(field: field)
    }

    // MARK: - 编辑态的基线与立即生效（S3-11，30 §6.6；S3D1-11、S3D1-13 的对外成员）

    /// The first profile read makes the base and the draft, once.
    func startEditing(_ user: AdminUser, catalog: UserGroupCatalog) {
        guard baseline == nil else { return }
        var base = UserBaseline(user: user)
        base.attributes = attributeValues ?? [:]
        self.catalog = catalog
        baseline = base
        draft = UserAccessDraft(editing: base, catalog: catalog)
    }
    /// A directory that arrives after the profile (or after a failed read) splits the grant into exclusive and public only now.
    func adoptCatalog(_ next: UserGroupCatalog) {
        guard next != catalog else { return }
        let wasEmpty = catalog.exclusiveIDs.isEmpty && catalog.publicIDs.isEmpty
        catalog = next
        guard wasEmpty, let baseline else { return }
        let fresh = UserAccessDraft(editing: baseline, catalog: next)
        draft.exclusiveGroupIDs = fresh.exclusiveGroupIDs
        draft.publicGroupIDs = fresh.publicGroupIDs
    }
    /// An immediate write took effect (S3-12, S3-14, S3-15): named in the leave confirmation; a grant change moves the base and
    /// the draft together and keeps every other change (design `both()`).
    func applyImmediate(_ name: String, groupsChange: UserGroupsChange? = nil) {
        if !applied.contains(name) { applied.append(name) }
        rebase(groupsChange)
    }
    /// Its undo: pass the change the write made; the reverse is applied here.
    func undoImmediate(_ name: String, groupsChange: UserGroupsChange? = nil) {
        applied.removeAll { $0 == name }
        rebase(groupsChange?.reversed)
    }
    /// The user PUT went through and only the attributes failed (30 §6.4 step 7): what was saved stops counting as changed.
    func settleSaved(_ request: UserUpdateRequest?) {
        guard let request, let baseline else { return }
        self.baseline = baseline.applying(request)
        draft.password = ""
        draft.adjustmentNotes = ""
    }
    var isApplyingImmediate: Bool { immediateWritesInFlight > 0 }
    var canStartImmediateWrite: Bool { saveProgress == nil }
    /// false (and nothing counted) while “保存” is out.
    func beginImmediateWrite() -> Bool {
        guard canStartImmediateWrite else { return false }
        immediateWritesInFlight += 1
        return true
    }
    func endImmediateWrite() { immediateWritesInFlight = max(immediateWritesInFlight - 1, 0) }
    /// 30 §6.2: “绑定 N 个 Key” and the count on the third segment; a failure leaves them unknown.
    func loadBoundKeys(model: AppModel) async {
        guard case .edit(let id) = mode else { return }
        let generation = model.sessionGeneration
        guard let keys = try? await model.userAPIKeys(userID: id), generation == model.sessionGeneration else { return }
        boundKeys = keys
    }

    private func rebase(_ change: UserGroupsChange?) {
        guard let change, !change.isEmpty, let baseline else { return }
        (self.baseline, draft) = UserEditRebase.apply(change, baseline: baseline, draft: draft, catalog: catalog)
    }
    private func adoptAttributes(_ values: [UserAttributeValue]) {
        let shown = UserAttributeEdits.values(values)
        attributeValues = shown
        guard baseline != nil else { return }
        baseline?.attributes = shown
        draft.attributes = shown
    }
}
