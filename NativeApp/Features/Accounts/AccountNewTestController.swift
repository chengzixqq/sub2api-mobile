import Foundation
import Observation
import Sub2Core

/// 20 §7.3 / §7.4 once the account exists (S2-20): the test sheet, `GET :id` for the version and the models before the test,
/// 保存并重新测试 (S2-18's diff through S2-10's AccountPatchFlow, then the test), and what follows a test that did not pass:
/// 保留, 保存为停用, 删除账号… (S3-00's confirmation) or the form again. The test and the switch after it are AccountTestCenter's
/// run, so 后台继续 and a closed form leave them going. Keys and tokens stay in AccountNewModel's draft; nothing here is logged.
@MainActor @Observable
final class AccountNewTestController {
    enum Save: Equatable { case idle, saving, saved, unchanged, failed(String) }

    var showsSheet = false
    var resolveDialog: AccountNewResolveDialog?
    private(set) var deleteRequest: DeleteRequest?
    private(set) var base: AccountEditBase?
    /// The draft the server holds (the create's, then each save's): 保存并重新测试 sends what differs from it.
    private(set) var savedDraft: AccountNewDraft?
    private(set) var isRetry = false
    private(set) var save: Save = .idle
    private(set) var models: [AccountModelOption] = []
    private(set) var isPreparing = false
    private(set) var patchFlow: AccountPatchFlow?
    private var model: String?
    private var saveInFlight = false
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let submission: AccountNewSubmission
    @ObservationIgnored private var platformName = ""
    @ObservationIgnored private var finishesAfterDelete = false

    init(app: AppModel, router: AppRouter, submission: AccountNewSubmission) {
        self.app = app; self.router = router; self.submission = submission
    }

    // MARK: Reading

    var accountID: Int? { base?.account.id ?? submission.createdAccountID }
    var run: AccountNewTestRun? { app.accountTests?.newAccountRun(for: accountID) }
    var testState: AccountTestState? { accountID.flatMap { app.accountTests?.state(for: $0) } }
    var status: AccountNewScheduleStatus { run?.status ?? .paused }
    var accountName: String { base?.account.name ?? submission.account?.name ?? "" }
    var isTesting: Bool { isPreparing || run?.isSettled == false }
    var isPassed: Bool { run?.isPassed == true }
    var isBusy: Bool { isPreparing || saveInFlight || patchFlow?.isSaving == true }
    /// Created, tested and not passed: the form's banner, the note above the credentials and the dock's 保存并重新测试.
    var needsResolution: Bool {
        guard base != nil, let run, run.isSettled, !run.isPassed else { return false }
        if case .enableFailed = run.phase { return false }
        return true
    }
    /// The subtitle's third part once tested.
    var scheduleStatus: AccountNewScheduleStatus? {
        guard base != nil, let run else { return nil }
        return run.isPassed ? .active : run.status
    }
    func hasChanges(_ draft: AccountNewDraft) -> Bool { savedDraft.map { draft.hasChanges(since: $0) } ?? false }

    var snapshot: AccountNewTestSnapshot? {
        guard let id = accountID else { return nil }
        return AccountNewTestSnapshot(accountID: id, isRetry: isRetry, write: write, pause: submission.stage.testSheetPause, test: test,
                                      enable: enable, model: testState?.shownModel ?? model, status: status)
    }
    var sheetTitle: String { snapshot.map(AccountNewTestPresentation.sheetTitle) ?? AccountNewFlow.dockActionTitle(isCreated: false, hasChanges: false) }
    var outputLines: [String] { testState?.lines ?? [] }
    var isOutputRunning: Bool { testState?.isRunning == true }
    var outputSummary: AccountNewTestOutputSummary? {
        guard let state = testState else { return nil }
        let header = state.lines.count - state.transcript.displayLines.count
        return AccountNewTestPresentation.outputSummary(lines: state.lines, lineCount: header + state.transcript.lineCount)
    }
    func banner(draft: AccountNewDraft) -> (title: String, detail: String)? {
        guard !showsSheet, needsResolution, let id = accountID, let run else { return nil }
        return AccountNewTestPresentation.banner(accountID: id, status: status, reason: run.verdict?.reason, incomplete: run.verdict == nil,
                                                 retryTitle: AccountNewFlow.dockActionTitle(isCreated: true, hasChanges: hasChanges(draft)))
    }
    var credentialNote: String? {
        guard needsResolution, let id = accountID else { return nil }
        return AccountNewTestPresentation.credentialNote(accountID: id, status: status)
    }
    func dock(draft: AccountNewDraft, missing: [String]) -> AccountNewDockContent? {
        guard needsResolution, case .created(let id) = submission.stage else { return nil }
        return .afterTest(accountID: id, status: status, hasChanges: hasChanges(draft), missing: missing)
    }

    private var test: AccountNewTestSnapshot.Test {
        if isPreparing { return .preparing }
        guard let run else { return .waiting }
        switch run.phase {
        case .testing: return .running
        case .enabling, .passed, .enableFailed, .failed: return run.verdict.map { .finished($0) } ?? .running
        case .interrupted: return .interrupted
        case .notStarted(let message): return .notStarted(message)
        }
    }
    private var enable: AccountNewTestSnapshot.Enable {
        switch run?.phase {
        case .enabling?: .running
        case .passed?: .done
        case .enableFailed(let reason)?: .failed(reason)
        default: .waiting
        }
    }
    /// A save that ended without the success callback: the flow's phase says why (a mixed-channel question declined reads as not saved).
    private var write: AccountNewTestSnapshot.Write {
        switch save {
        case .idle, .saved: return .done
        case .unchanged: return .unchanged
        case .failed(let reason): return .failed(reason)
        case .saving:
            guard !saveInFlight, let flow = patchFlow, !flow.isSaving, flow.prompt == nil else { return .running }
            return .failed(Self.failure(of: flow.phase))
        }
    }

    // MARK: Creating and testing (20 §7.4-1)

    /// S2-19 settled at `.created`: the sheet opens, the version and the models are read, then the test starts.
    func accountCreated(_ account: UpstreamAccount, draft: AccountNewDraft, platformName: String) {
        guard base?.account.id != account.id else { return }
        base = AccountEditBase(account: account, etag: nil)
        savedDraft = draft; self.platformName = platformName; isRetry = false; save = .idle
        patchFlow = AccountPatchFlow(model: app, accountID: account.id, onChange: { [weak self] in self?.base = $0 },
                                     onRemoved: { [weak self] in self?.accountRemoved() }, onReload: {})
        showsSheet = true
        Task { await prepare() }
    }
    /// The test row's model, 重新测试 after an interruption, or the test after a save.
    func startTest(model: String?) {
        guard let base, let center = app.accountTests else { return }
        self.model = model
        let router = router
        center.startNewAccountTest(AccountTestTarget(account: base.account, platformName: platformName), model: model, status: status, writer: app,
                                   opener: { [weak router] id in router?.showAccount(id: id) })
    }
    func retest() { startTest(model: model) }
    func retryEnable() { run?.retryEnable() }

    /// 20 §7.4-2: the edits go as one PATCH (credentials as credentials_patch), then the test; without edits only the test.
    func saveAndRetest(draft: AccountNewDraft) {
        guard let saved = savedDraft, let base, let flow = patchFlow, !isBusy, run?.isSettled != false else { return }
        isRetry = true
        showsSheet = true
        guard draft.hasChanges(since: saved) else {
            save = .unchanged
            return startTest(model: model)
        }
        let request: AccountPatchRequest
        do { request = try draft.patch(since: saved) } catch {
            save = .failed(AccountActionCopy.reason(for: error))
            return
        }
        save = .saving
        saveInFlight = true
        // The flow keeps this until the save ends, through its questions: weak, so a form closed meanwhile goes away.
        let onSaved: AccountPatchFlow.ReceiptMaker = { [weak self] saved in
            self?.saved(saved, draft: draft)
            return nil
        }
        Task {
            let done = await flow.save(AccountEditChange(fieldNames: [], request: request, undo: nil), base: base, receipt: onSaved)
            saveInFlight = false
            if done == nil, flow.prompt == nil, save == .saving { save = .failed(Self.failure(of: flow.phase)) }
        }
    }

    // MARK: Closing (20 §7.1 去向, §7.4-3, -4)

    /// The toolbar's 关闭 or a swipe: a pass completes, a pass whose switch failed closes paused, anything else returns to the form.
    func closeSheet() {
        switch run?.phase {
        case .passed?: complete(viewAccount: false)
        case .enableFailed?:
            let copy = AccountNewCopy.createdReceipt(name: accountName), id = accountID
            finish()
            show(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, opening: id)
        default: showsSheet = false
        }
    }
    func complete(viewAccount: Bool) {
        guard let id = accountID else { return }
        guard viewAccount else { return finish(with: AccountNewTestPresentation.completed(name: accountName)) }
        finish()
        openAccount(id)
    }
    func continueInBackground() {
        guard let id = accountID else { return }
        app.accountTests?.detachNewAccountTest(id)
        showsSheet = false
        onFinish?()
    }
    /// The form went away some other way (another tab): a test still going ends in its receipt.
    func viewDisappeared() {
        guard let id = accountID, app.accountTests?.newAccountRun(for: id) != nil else { return }
        app.accountTests?.detachNewAccountTest(id)
    }
    func presentResolve(hasUnsavedChanges: Bool) {
        guard let id = accountID else { return }
        resolveDialog = AccountNewTestPresentation.resolveDialog(name: accountName, accountID: id, status: status, incomplete: run?.verdict == nil,
                                                                 hasUnsavedChanges: hasUnsavedChanges)
    }
    /// 保留: nothing is sent.
    func keep() { finish(with: AccountNewTestPresentation.kept(name: accountName, status: status)) }
    /// 保存为停用: PATCH {status: inactive}; a version question while the sheet is closed is not asked (nobody else edits a
    /// minute-old account), it fails with the reason.
    func saveInactive() {
        guard let base, let flow = patchFlow, !isBusy else { return }
        let verb = AccountNewTestPresentation.saveInactiveVerb
        saveInFlight = true
        let onSaved: AccountPatchFlow.ReceiptMaker = { [weak self] saved in
            self?.finish(with: AccountNewTestPresentation.savedInactive(name: saved.account.name))
            return nil
        }
        Task {
            let change = AccountEditChange(fieldNames: [verb], request: AccountPatchRequest(status: .inactive), undo: nil)
            let done = await flow.save(change, base: base, receipt: onSaved)
            saveInFlight = false
            guard done == nil else { return }
            if flow.prompt != nil {
                guard !showsSheet else { return }
                flow.reset()
                return show(AccountNewTestPresentation.actionFailed(verb, reason: AccountActionCopy.modifiedElsewhere))
            }
            show(AccountNewTestPresentation.actionFailed(verb, reason: Self.failure(of: flow.phase)))
        }
    }
    /// 删除账号… through the App's one confirmation (Face ID, or the whole name typed); the form closes once it has gone.
    func requestDelete() {
        guard let account = base?.account ?? submission.account else { return }
        let flow = AccountDeleteFlow(source: app, receipts: app.receipts), signal = app.accountListSignal
        deleteRequest = .account(account, siteName: app.activeProfile?.name ?? "") { [weak self] in
            await flow.delete(account) {
                signal.bump()
                self?.finishesAfterDelete = true
            }
        }
    }
    func deleteRequestChanged(_ request: DeleteRequest?) {
        deleteRequest = request
        guard request == nil, finishesAfterDelete else { return }
        finishesAfterDelete = false
        finish()
    }

    // MARK: - Internals

    private func prepare() async {
        guard let id = accountID else { return }
        isPreparing = true
        let app = app, generation = app.sessionGeneration
        async let read = try? app.accountWithVersion(id: id)
        async let options = try? app.accountModels(id: id)
        let (fresh, loaded) = await (read, options)
        isPreparing = false
        guard generation == app.sessionGeneration else { return }
        if let fresh { base = AccountEditBase(fresh) }
        models = loaded ?? []
        startTest(model: AccountTestPresentation.defaultModel(among: models.map(\.id)))
    }
    private func saved(_ saved: AccountEditBase, draft: AccountNewDraft) {
        base = saved; savedDraft = draft; save = .saved
        startTest(model: model)
    }
    private func accountRemoved() {
        finish()
        app.receipts.show(Receipt(text: AccountActionCopy.missingReason, systemImage: "exclamationmark.triangle", tone: .critical))
    }
    private func finish(with copy: AccountNewTestReceipt? = nil) {
        let id = accountID
        if let id { app.accountTests?.endNewAccountTest(id) }
        showsSheet = false
        if let copy { show(copy, accountID: id) }
        onFinish?()
    }
    private func show(_ copy: AccountNewTestReceipt, accountID: Int? = nil) {
        show(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, opening: copy.button == nil ? nil : accountID ?? self.accountID)
    }
    /// `opening`: the receipt's 查看 leads to that account's detail on the account tab.
    private func show(text: String, systemImage: String, tone: Tone, opening id: Int?) {
        let router = router
        let action = id.map { id in
            ReceiptAction(title: AccountNewTestReceipt.Button.view.title) { [weak router] in
                router?.selectedTab = .accounts
                router?.showAccount(id: id)
            }
        }
        app.receipts.show(Receipt(text: text, systemImage: systemImage, tone: tone, action: action))
    }
    private func openAccount(_ id: Int) {
        router.selectedTab = .accounts
        router.showAccount(id: id)
    }
    private static func failure(of phase: AccountPatchFlow.Phase) -> String {
        switch phase {
        case .failed(let text), .reconfirm(let text), .needsWeb(let text): text
        case .unconfirmed: AccountEditCopy.unconfirmed
        case .idle, .saving, .notApplied: AccountEditCopy.notApplied
        }
    }
}
