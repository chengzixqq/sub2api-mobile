import Foundation
import Observation
import Sub2Core

/// 30 §7.4 (S3-13): the state of one 新建 / 编辑 Key sheet. Local issues show from the first press of “创建” / “保存”; any
/// change to the draft clears them and the server's marks. A new key's request and Idempotency-Key are frozen at that press
/// and reused while the draft stays the same (R05).
@MainActor @Observable
final class UserKeyFormModel: Identifiable {
    enum Mode: Equatable { case create(userID: Int), edit(AdminAPIKey) }
    struct FrozenCreate: Sendable {
        let request: AdminAPIKeyCreateRequest
        let key: UUID
        /// The first send, for finding the key after a lost reply.
        let startedAt: Date
        let draft: UserKeyDraft
        /// The keys the list had before the first send.
        let knownIDs: Set<Int>
    }
    enum UpdatePlan { case invalid, unchanged, send(AdminAPIKeyUpdateRequest) }

    let id = UUID()
    let mode: Mode
    var draft = UserKeyDraft() {
        didSet {
            guard draft != oldValue else { return }
            localErrors = [:]; serverErrors = [:]; formError = nil
            if frozen?.draft != draft { frozen = nil }
        }
    }
    private(set) var localErrors: [UserKeyField: String] = [:]
    private(set) var serverErrors: [UserKeyField: String] = [:]
    private(set) var formError: String?
    private(set) var isSubmitting = false
    /// “正在确认结果…” while the executor retries or waits for the server.
    private(set) var progressNote: String?
    @ObservationIgnored private var frozen: FrozenCreate?

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let key) = mode { draft = UserKeyDraft(editing: key) }
    }

    var original: AdminAPIKey? {
        guard case .edit(let key) = mode else { return nil }
        return key
    }
    var isCreate: Bool { original == nil }
    var hasChanges: Bool { UserKeyForm.hasChanges(draft, original: original) }
    /// 重置已用额度 only for a key with a quota.
    var showsResetQuota: Bool { (original?.quota ?? 0) > 0 }
    func error(for field: UserKeyField) -> String? { localErrors[field] ?? serverErrors[field] }
    /// Where the form scrolls after a press: the bottom message, else the first row with an issue.
    var issueAnchor: String? {
        if formError != nil { return "keys.form.formError" }
        return UserKeyField.allCases.first { error(for: $0) != nil }.map { "keys.form.error.\($0.rawValue)" }
    }
    /// “创建” waits for the user's “保存” when the new key binds a group (S3D1-11).
    func canSubmit(immediateWritesAllowed: Bool) -> Bool {
        hasChanges && !isSubmitting && (immediateWritesAllowed || draft.groupID == nil)
    }

    // MARK: - 提交

    func prepareCreate(zone: ServerTimeZone, now: Date, knownIDs: Set<Int>) -> FrozenCreate? {
        guard validate(zone: zone, now: now) else { return nil }
        if let frozen, frozen.draft == draft { return frozen }
        guard let request = try? UserKeyForm.createRequest(draft) else { return nil }
        let made = FrozenCreate(request: request, key: UUID(), startedAt: now, draft: draft, knownIDs: knownIDs)
        frozen = made
        return made
    }
    func prepareUpdate(zone: ServerTimeZone, now: Date) -> UpdatePlan {
        guard let original, validate(zone: zone, now: now) else { return .invalid }
        guard let request = try? UserKeyForm.updateRequest(draft, original: original, zone: zone) else { return .unchanged }
        return .send(request)
    }
    /// The server did not run it and will not take these bytes under this key again.
    func dropFrozen() { frozen = nil }

    func beginSubmit() {
        isSubmitting = true
        progressNote = nil
        formError = nil
    }
    func endSubmit() {
        isSubmitting = false
        progressNote = nil
    }
    func apply(_ failure: UserKeyFormCopy.Failure) {
        switch failure.placement {
        case .field(.group) where !isCreate, .form: formError = failure.message
        case .field(let field): serverErrors[field] = failure.message
        }
    }
    func note(_ event: KeyedWriteEvent) {
        switch event {
        case .actionID: break
        case .confirming: progressNote = "正在确认结果…"
        case .waitingForServer(let seconds): progressNote = "服务器仍在处理（\(seconds) 秒）"
        }
    }

    private func validate(zone: ServerTimeZone, now: Date) -> Bool {
        let issues = UserKeyForm.issues(draft, editing: original, zone: zone, now: now)
        localErrors = Dictionary(issues.map { ($0.field, $0.message) }, uniquingKeysWith: { first, _ in first })
        serverErrors = [:]
        formError = nil
        return issues.isEmpty
    }
}
