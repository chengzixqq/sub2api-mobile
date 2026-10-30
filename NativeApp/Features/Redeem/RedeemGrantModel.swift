import Foundation
import Observation
import Sub2Core

/// `.redeemGrant`'s wizard (60 §19.1–§19.4): 类型 → 数值 → 备注与确认, the confirmation on screen, the send in flight and what the
/// sheet turns into. The code is made when the sheet opens (step 3 shows its last four); each confirmation makes a new key and,
/// once a grant went out, every edit takes a new code (GrantDraftState, R05). Sent by CompensationSubmission; only “稍后核对”
/// cancels the task, which keeps the record to be checked.
@MainActor @Observable
final class RedeemGrantModel {
    enum Exit: Equatable {
        case granted(AdminRedeemCode, replayed: Bool, grant: PendingCompensation)
        /// 结果待核对 of this record, in the same sheet.
        case pending(UUID)
        /// USER_NOT_FOUND: the sheet closes with this line.
        case closed(String)
    }
    enum Subscriptions: Equatable { case idle, loading, loaded([AdminUserSubscription]), failed }
    struct Confirmation: Identifiable {
        let id = UUID()
        let content: GrantConfirmation
        /// Set when a security prompt cleared the record: the same one is confirmed again (S6D1-08).
        let record: PendingCompensation?
    }

    let user: AdminUser
    private(set) var draftState: GrantDraftState
    private(set) var step: GrantStep = .type
    private(set) var type: CompensationType?
    private(set) var amountText = ""
    private(set) var concurrency = 1
    private(set) var groupID: Int?
    private(set) var days: RedeemSubscriptionDaysChoice = .days(30)
    private(set) var customDaysText = ""
    private(set) var notes = ""
    private(set) var subscriptions: Subscriptions = .idle
    private(set) var confirmation: Confirmation?
    /// From the confirmation until the result, Face ID included.
    private(set) var isWorking = false
    private(set) var isVerifying = false
    /// Set once the record is saved: “稍后核对” is offered from then on.
    private(set) var progress: BalanceWriteProgress?
    /// A refusal, a record that could not be saved, a cleared security prompt, a new code.
    private(set) var notice: String?
    private(set) var exit: Exit?
    /// A new code could not be made after an edit: nothing may go out until one is.
    private var needsNewCode = false
    @ObservationIgnored private var sending: Task<Void, Never>?

    init(user: AdminUser, draftState: GrantDraftState) {
        self.user = user; self.draftState = draftState
    }
    /// 重新发放 from the pending page: the record's content again, at step 3 (step 2 for a group the server refused).
    init(user: AdminUser, regranting grant: PendingCompensation, draftState: GrantDraftState, notice: String?, atValueStep: Bool) {
        self.user = user; self.draftState = draftState; self.notice = notice
        type = grant.type
        notes = grant.notes
        switch grant.type {
        case .balance: amountText = NSDecimalNumber(decimal: grant.value).stringValue
        case .concurrency: concurrency = NSDecimalNumber(decimal: grant.value).intValue
        case .subscription:
            groupID = grant.groupID
            let length = grant.validityDays ?? NSDecimalNumber(decimal: grant.value).intValue
            days = RedeemSubscriptionDaysChoice.options.first { $0 == .days(length) } ?? .custom
            if days == .custom { customDaysText = String(length) }
        }
        step = atValueStep ? .value : .note
    }

    private var canEdit: Bool { !isWorking && exit == nil }

    // MARK: Steps

    /// A tile: the type, then step 2; the subscription type reads the user's subscriptions once.
    func choose(_ type: CompensationType, availability: GrantAvailability, app: AppModel) {
        guard canEdit, availability.isAvailable(type) else { return }
        if self.type != type { self.type = type; contentEdited() }
        step = .value
        if type == .subscription, subscriptions == .idle { Task { [weak self] in await self?.loadSubscriptions(app: app) } }
    }
    func advance(groups: [AdminGroup]) {
        guard canEdit, step == .value, draft(groups: groups) != nil else { return }
        step = .note
    }
    func goBack() {
        guard canEdit, let previous = step.previous else { return }
        step = previous
    }

    // MARK: Inputs

    func editAmount(_ text: String) {
        edit { $0.amountText = KeypadInput.edit($0.amountText, to: text, maxDigits: BalanceGrantPreview.maxDigits,
                                               maxFractionDigits: BalanceGrantPreview.maxFractionDigits) }
    }
    func setConcurrency(_ value: Int) {
        edit { $0.concurrency = min(max(value, RedeemGrantDraft.concurrencyRange.lowerBound), RedeemGrantDraft.concurrencyRange.upperBound) }
    }
    func selectGroup(_ id: Int) { edit { $0.groupID = id } }
    func chooseDays(_ choice: RedeemSubscriptionDaysChoice) { edit { $0.days = choice } }
    /// Half-width digits only, at most four (1–3650).
    func editCustomDays(_ text: String) { edit { $0.customDaysText = String(text.filter { $0.isASCII && $0.isNumber }.prefix(4)) } }
    /// The server counts runes, which are Unicode scalars.
    func editNotes(_ text: String) { edit { $0.notes = String(Substring(text.unicodeScalars.prefix(RedeemGrantDraft.notesLimit))) } }

    // MARK: What the steps show

    func selectedGroup(in groups: [AdminGroup]) -> AdminGroup? { groups.first { $0.id == groupID } ?? groups.first }
    /// What would go out now; nil while anything is missing.
    func draft(groups: [AdminGroup]) -> RedeemGrantDraft? {
        guard !needsNewCode, let type else { return nil }
        let value: RedeemGrantDraft.Value
        switch type {
        case .balance:
            guard let amount = KeypadInput.value(of: amountText) else { return nil }
            value = .balance(amount)
        case .concurrency:
            value = .concurrency(concurrency)
        case .subscription:
            guard let group = selectedGroup(in: groups), let length = days.grantDays(customText: customDaysText) else { return nil }
            value = .subscription(groupID: group.id, days: length)
        }
        let draft = RedeemGrantDraft(value: value, notes: notes)
        return draft.isValid ? draft : nil
    }
    /// nil until the user's subscriptions are read (or when they cannot be): the server's result wins then.
    func plan(groups: [AdminGroup], now: Date, timeZone: TimeZone) -> SubscriptionGrantPlan? {
        guard type == .subscription, case .loaded(let rows) = subscriptions, let group = selectedGroup(in: groups),
              let length = days.grantDays(customText: customDaysText) else { return nil }
        return SubscriptionGrantPlan.make(rows: rows, groupID: group.id, days: length, now: now, timeZone: timeZone)
    }
    func summary(groups: [AdminGroup], now: Date, timeZone: TimeZone) -> GrantSummary? {
        guard let draft = draft(groups: groups) else { return nil }
        let groupName: String? = switch draft.value {
        case .subscription(let id, _): groups.first { $0.id == id }?.name
        case .balance, .concurrency: nil
        }
        return GrantSummary(draft: draft, user: user, groupName: groupName, plan: plan(groups: groups, now: now, timeZone: timeZone), now: now, timeZone: timeZone)
    }

    // MARK: Confirmation and send

    /// 发放 …: the confirmation with object, site and change (BUILDER_GUIDE), plus the Face ID line when it will ask.
    func submit(app: AppModel, groups: [AdminGroup], now: Date, timeZone: TimeZone) {
        guard canEdit, let draft = draft(groups: groups), let summary = summary(groups: groups, now: now, timeZone: timeZone) else { return }
        notice = nil
        confirmation = Confirmation(content: content(summary, notes: draft.notes, app: app), record: nil)
    }
    func dismissConfirmation(_ id: UUID) {
        if confirmation?.id == id { confirmation = nil }
    }
    /// Accepted: a new key now (R05), or the cleared record again; then the gate, Face ID, the saved record and the send.
    func confirm(_ shown: Confirmation, app: AppModel, groups: [AdminGroup]) {
        dismissConfirmation(shown.id)
        guard canEdit, let record = shown.record ?? newRecord(app: app, groups: groups) else { return }
        let submission = app.compensationSubmission { [weak self] in self?.isVerifying = $0 }
        isWorking = true
        notice = nil
        sending = Task { [weak self] in
            let outcome = await submission.grant(record) { [weak self] in self?.progress = $0 }
            self?.finish(outcome, record: record, app: app, groups: groups)
        }
    }
    /// “稍后核对”: stops waiting; the record stays to be checked.
    func later() { sending?.cancel() }

    private func newRecord(app: AppModel, groups: [AdminGroup]) -> PendingCompensation? {
        guard let serverID = app.activeProfile?.id, let draft = draft(groups: groups) else { return nil }
        let confirmed = draftState.confirmed()
        guard let key = confirmed.key else { return nil }
        do {
            let record = try draft.compensation(id: key, serverID: serverID, actorUserID: app.siteSession?.me.user?.id, createdAt: Date(), user: user,
                                                code: confirmed.code)
            draftState = confirmed.sent()
            return record
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }
    private func finish(_ outcome: CompensationSubmission.Outcome, record: PendingCompensation, app: AppModel, groups: [AdminGroup]) {
        isWorking = false; isVerifying = false; progress = nil; sending = nil
        switch outcome {
        case .notAuthorized, .stale, .gone: return
        case .blocked(let id): exit = .pending(id)
        case .pending: exit = .pending(record.id)
        case .granted(let code, let replayed): exit = .granted(code, replayed: replayed, grant: record)
        case .userGone(let text): exit = .closed(text)
        case .paused(let text), .refused(let text), .notSaved(let text), .rejected(let text), .newKey(let text): notice = text
        case .renumber(let text): renumber(text)
        case .backToValue(let text):
            notice = text
            step = .value
            Task { await app.groupDirectory?.refresh() }
        case .reconfirm(let again, let text):
            notice = text
            let now = app.client?.serverClock.now() ?? Date(), zone = app.siteSession?.serverTimeZone.timeZone ?? .current
            guard let summary = summary(groups: groups, now: now, timeZone: zone) else { return }
            confirmation = Confirmation(content: content(summary, notes: again.notes, app: app), record: again)
        }
    }
    /// REDEEM_CODE_CONFLICT / EXPIRED: a new code and, at the next confirmation, a new key.
    private func renumber(_ text: String) {
        do { draftState = draftState.renumbered(code: try RedeemCode.random()); needsNewCode = false } catch { needsNewCode = true }
        notice = text
    }
    private func content(_ summary: GrantSummary, notes: String, app: AppModel) -> GrantConfirmation {
        let faceID = summary.isMoney ? app.biometricGate.amountConfirmationLine(amount: summary.amount) : nil
        return RedeemGrantCopy.confirmation(summary, userName: user.displayName, siteName: app.activeProfile?.name ?? "", notes: notes,
                                            userDisabled: user.status == "disabled", faceIDLine: faceID)
    }

    /// Inputs change only while nothing is going out; a real change after a send takes a new code (60 §19.4 step 5).
    private func edit(_ change: (RedeemGrantModel) -> Void) {
        guard canEdit else { return }
        let before = (amountText, concurrency, groupID, days, customDaysText, notes)
        change(self)
        guard before != (amountText, concurrency, groupID, days, customDaysText, notes) else { return }
        contentEdited()
    }
    private func contentEdited() {
        notice = nil
        do { draftState = try draftState.edited { try RedeemCode.random() }; needsNewCode = false } catch {
            needsNewCode = true
            notice = error.localizedDescription
        }
    }
    private func loadSubscriptions(app: AppModel) async {
        guard subscriptions == .idle else { return }
        subscriptions = .loading
        let generation = app.sessionGeneration
        do {
            let rows = try await app.grantSubscriptions(userID: user.id)
            guard generation == app.sessionGeneration else { return }
            subscriptions = .loaded(rows)
        } catch {
            guard generation == app.sessionGeneration else { return }
            subscriptions = .failed
        }
    }
}
