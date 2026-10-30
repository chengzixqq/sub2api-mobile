import Foundation
import Observation
import Sub2Core

/// 30 §7.4 (S3-13, S3D1-02): 新建 / 编辑 / 删除 Key and 显示完整 Key for one edit page. The sheets' state lives here, the cards
/// in the segment's UserKeysModel; grants and “已立即生效” go through that model's hooks and write gate, as its own writes do.
/// Nothing is optimistic: the cards change once the server has answered.
@MainActor @Observable
final class UserKeyManageModel {
    var form: UserKeyFormModel?
    var revealed: RevealedKeySecret?
    var deleteRequest: DeleteRequest?
    private(set) var revealingKeyID: Int?
    /// What follows once the form's sheet has gone: the new key's sheet and its receipt, or only a receipt.
    @ObservationIgnored private var afterForm: (secret: RevealedKeySecret?, receipt: Receipt?)?
    @ObservationIgnored private var afterSecret: Receipt?
    @ObservationIgnored private weak var receipts: ReceiptCenter?

    func beginCreate(userID: Int) { form = UserKeyFormModel(mode: .create(userID: userID)) }
    func beginEdit(_ key: AdminAPIKey) { form = UserKeyFormModel(mode: .edit(key)) }

    func submit(_ form: UserKeyFormModel, keys: UserKeysModel, model: AppModel) async {
        guard !form.isSubmitting, let context = keys.context, !context.isReadOnlyToken else { return }
        receipts = keys.receipts
        switch form.mode {
        case .create(let userID): await create(form, userID: userID, keys: keys, model: model, context: context)
        case .edit(let key): await save(form, key: key, keys: keys, context: context)
        }
    }
    /// The form's `onDismiss`: a second sheet opens only after the first has gone.
    func formDismissed() {
        guard let next = afterForm else { return }
        afterForm = nil
        if let secret = next.secret {
            afterSecret = next.receipt
            revealed = secret
        } else if let receipt = next.receipt {
            receipts?.show(receipt)
        }
    }
    /// The full key's `onDismiss`: the plaintext is gone, then 已创建's receipt shows.
    func secretDismissed() {
        revealed?.clear()
        revealed = nil
        if let receipt = afterSecret { receipts?.show(receipt) }
        afterSecret = nil
    }

    // MARK: - 新建（E01）

    private func create(_ form: UserKeyFormModel, userID: Int, keys: UserKeysModel, model: AppModel, context: UserKeysContext) async {
        guard let frozen = form.prepareCreate(zone: context.serverTimeZone, now: context.now(), knownIDs: Set(keys.keys.map(\.id))) else { return }
        let groupID = frozen.request.groupID
        let granted = groupID.map { id in UserKeyPresentation.newlyGranted(target: keys.hooks.groups().first { $0.id == id }, access: keys.hooks.access()) }
        // S3D1-11: binding a group may grant it, so the user's “保存” and this wait for each other.
        if groupID != nil, !keys.writeGate.begin() {
            form.apply(UserKeyFormCopy.Failure(placement: .form, message: UserEditCopy.immediateBlockedBySave))
            return
        }
        form.beginSubmit()
        defer {
            if groupID != nil { keys.writeGate.end() }
            form.endSubmit()
        }
        do {
            let outcome = try await model.createUserAPIKey(userID: userID, frozen.request, idempotencyKey: frozen.key,
                                                           onEvent: { [weak form] event in await form?.note(event) })
            guard keys.isCurrent(context.generation) else { return }
            await created(outcome.value, grantedGroupID: granted == true ? groupID : nil, form: form, keys: keys, context: context)
        } catch {
            guard keys.isCurrent(context.generation) else { return }
            await createFailed(error, form: form, frozen: frozen, grantedGroupID: granted == true ? groupID : nil, keys: keys)
        }
    }
    /// The card takes the masked form; the plaintext goes only to the result sheet, and its receipt waits for that sheet.
    private func created(_ value: CreatedAPIKey, grantedGroupID: Int?, form: UserKeyFormModel, keys: UserKeysModel, context: UserKeysContext) async {
        let key = value.apiKey, name = key.displayName
        keys.insert(key)
        noteCreated(name, grantedGroupID: grantedGroupID, keys: keys)
        if UserKeyForm.isRedactedPlaintext(value.key) {
            afterForm = (nil, Receipt(text: UserKeyFormCopy.createdRecovered(name), systemImage: "checkmark.circle"))
        } else {
            afterForm = (RevealedKeySecret(keyID: key.id, purpose: .created, name: name, plaintext: value.key),
                         Receipt(text: UserKeyFormCopy.created(name), systemImage: "checkmark.circle"))
        }
        close(form)
        await keys.refreshConcurrency(key.id, context: context)
    }
    private func createFailed(_ error: any Error, form: UserKeyFormModel, frozen: UserKeyFormModel.FrozenCreate, grantedGroupID: Int?,
                              keys: UserKeysModel) async {
        if let failure = error as? KeyedWriteFailure {
            switch failure.disposition {
            case .unconfirmed(.storeUnavailable, _): form.apply(.init(placement: .form, message: failure.localizedDescription))
            case .unconfirmed: await recover(form: form, frozen: frozen, grantedGroupID: grantedGroupID, keys: keys)
            case .needsNewKey:
                form.dropFrozen()
                form.apply(.init(placement: .form, message: failure.localizedDescription))
            }
            return
        }
        guard let api = error as? APIError else {
            if !(error is CancellationError) { form.apply(.init(placement: .form, message: error.localizedDescription)) }
            return
        }
        if api.securityOutcome == .cancelled { return }
        // Refused before the handler (a cleared prompt) keeps the number; the server's own refusal does not.
        if api.securityOutcome != .passed { form.dropFrozen() }
        if api.reason == "GROUP_NOT_FOUND" || api.reason == "GROUP_NOT_ACTIVE" { keys.hooks.onGroupsStale() }
        if api.reason == "SUBSCRIPTION_REQUIRED" { await keys.loadSubscriptions() }
        form.apply(UserKeyFormCopy.failure(api, draft: frozen.draft))
    }
    /// 30 §7.4: a reply nobody saw. A key of that name made since the send is taken as this one (its plaintext only through
    /// 显示完整 Key); otherwise the same number stays for the next press.
    private func recover(form: UserKeyFormModel, frozen: UserKeyFormModel.FrozenCreate, grantedGroupID: Int?, keys: UserKeysModel) async {
        await keys.refreshAll()
        guard let found = UserKeyCreateRecovery.match(in: keys.keys, request: frozen.request, startedAt: frozen.startedAt, knownIDs: frozen.knownIDs) else {
            form.apply(.init(placement: .form, message: UserKeyFormCopy.createUnconfirmed))
            return
        }
        form.dropFrozen()
        noteCreated(found.displayName, grantedGroupID: grantedGroupID, keys: keys)
        afterForm = (nil, Receipt(text: UserKeyFormCopy.createdRecovered(found.displayName), systemImage: "checkmark.circle"))
        close(form)
    }
    /// A newly granted group joins the page's base like 换分组's; no 撤销 (taking a new key back is deleting it).
    private func noteCreated(_ name: String, grantedGroupID: Int?, keys: UserKeysModel) {
        keys.hooks.onImmediate(.applied(name: UserKeyFormCopy.createdOperation(name), grantedGroupID: grantedGroupID))
        if grantedGroupID != nil { keys.hooks.onUserChanged() }
    }
    private func close(_ form: UserKeyFormModel) {
        if self.form === form { self.form = nil }
    }
}

// MARK: - 编辑（E01）

extension UserKeyManageModel {
    /// Only what changed, once and without a key; a lost answer is read back (R06).
    private func save(_ form: UserKeyFormModel, key: AdminAPIKey, keys: UserKeysModel, context: UserKeysContext) async {
        let request: AdminAPIKeyUpdateRequest
        switch form.prepareUpdate(zone: context.serverTimeZone, now: context.now()) {
        case .invalid: return
        case .unchanged: close(form); return
        case .send(let built): request = built
        }
        guard let source = keys.keySource else { return }
        form.beginSubmit()
        defer { form.endSubmit() }
        do {
            let result = try await source.updateAPIKey(id: key.id, request)
            guard keys.isCurrent(context.generation) else { return }
            var fresh = result.apiKey
            if fresh == nil { fresh = try? await source.apiKey(id: key.id) }
            guard keys.isCurrent(context.generation) else { return }
            saved(request, fresh: fresh, previous: result.previous, key: key, form: form, keys: keys)
            await keys.refreshConcurrency(key.id, context: context)
        } catch {
            guard keys.isCurrent(context.generation), let failure = UserKeyWriteFailure(error) else { return }
            switch failure {
            case .keyGone: gone(key.id, form: form, keys: keys)
            case .unconfirmed: await readBack(request, key: key, form: form, keys: keys, context: context)
            default: form.apply((error as? APIError).map { UserKeyFormCopy.failure($0, draft: form.draft) } ?? .init(placement: .form, message: failure.message))
            }
        }
    }
    /// “已保存「脚本」” with 撤销 from the reply's `previous`; none after a read-back or for a quota reset alone.
    private func saved(_ request: AdminAPIKeyUpdateRequest, fresh: AdminAPIKey?, previous: AdminAPIKeyPrevious?, key: AdminAPIKey,
                       form: UserKeyFormModel, keys: UserKeysModel) {
        if let fresh { keys.replace(fresh) }
        let name = fresh?.displayName ?? request.name ?? key.displayName
        let operation = UserKeyFormCopy.editedOperation(name)
        keys.hooks.onImmediate(.applied(name: operation, grantedGroupID: nil))
        var undo: (@MainActor @Sendable () -> Void)?
        if let previous, let back = try? UserKeyForm.undoRequest(previous: previous) {
            let id = key.id
            undo = { [self, keys] in Task { await self.undoEdit(keyID: id, operation: operation, request: back, keys: keys) } }
        }
        afterForm = (nil, Receipt(text: UserKeyFormCopy.saved(name, resetQuota: request.resetQuota), systemImage: "checkmark.circle", undo: undo))
        close(form)
    }
    private func readBack(_ request: AdminAPIKeyUpdateRequest, key: AdminAPIKey, form: UserKeyFormModel, keys: UserKeysModel,
                          context: UserKeysContext) async {
        guard let source = keys.keySource else { return }
        do {
            let fresh = try await source.apiKey(id: key.id)
            guard keys.isCurrent(context.generation) else { return }
            keys.replace(fresh)
            if UserKeyForm.readbackMatches(request, server: fresh) {
                saved(request, fresh: fresh, previous: nil, key: key, form: form, keys: keys)
            } else {
                form.apply(.init(placement: .form, message: UserKeyFormCopy.saveMismatch))
            }
        } catch {
            guard keys.isCurrent(context.generation) else { return }
            if UserKeyWriteFailure(error) == .keyGone { gone(key.id, form: form, keys: keys); return }
            form.apply(.init(placement: .form, message: UserKeyWriteFailure.unconfirmed.message))
        }
    }
    /// The receipt's 撤销: `previous` written back. Runs after the page has gone too.
    func undoEdit(keyID: Int, operation: String, request: AdminAPIKeyUpdateRequest, keys: UserKeysModel) async {
        guard let context = keys.context, let source = keys.keySource else { return }
        do {
            let result = try await source.updateAPIKey(id: keyID, request)
            guard keys.isCurrent(context.generation) else { return }
            var fresh = result.apiKey
            if fresh == nil { fresh = try? await source.apiKey(id: keyID) }
            guard keys.isCurrent(context.generation) else { return }
            if let fresh { keys.replace(fresh) }
            keys.hooks.onImmediate(.withdrawn(name: operation, revokedGroupID: nil))
            await keys.refreshConcurrency(keyID, context: context)
        } catch {
            guard keys.isCurrent(context.generation), let failure = UserKeyWriteFailure(error) else { return }
            if failure == .keyGone { keys.remove(id: keyID) }
            keys.report(.failed(failure), undoing: true)
        }
    }
    /// 30 §7.5: 404 API_KEY_NOT_FOUND on any write removes the card.
    private func gone(_ keyID: Int, form: UserKeyFormModel, keys: UserKeysModel) {
        keys.remove(id: keyID)
        afterForm = (nil, Receipt(text: UserKeyWriteFailure.keyGone.message, systemImage: "exclamationmark.triangle", tone: .critical))
        close(form)
    }
}

// MARK: - 删除（E01）

extension UserKeyManageModel {
    /// C-2's confirmation: the whole name typed, or Face ID with the switch on.
    func requestDelete(_ key: AdminAPIKey, siteName: String, userDisplayName: String, keys: UserKeysModel, model: AppModel) {
        deleteRequest = DeleteRequest(objectNoun: UserKeyFormCopy.objectNoun, displayName: key.displayName, siteName: siteName,
                                      siteLine: UserKeyFormCopy.deleteSiteLine(siteName: siteName, userDisplayName: userDisplayName),
                                      consequences: [UserKeyFormCopy.deleteConsequence]) { [self, keys, model] in
            await self.delete(key, keys: keys, model: model)
        }
    }
    /// 404 is already deleted; a lost answer is settled by reading the key.
    func delete(_ key: AdminAPIKey, keys: UserKeysModel, model: AppModel) async {
        guard let context = keys.context, !context.isReadOnlyToken else { return }
        do { _ = try await model.deleteAPIKey(id: key.id) } catch {
            guard keys.isCurrent(context.generation), let failure = UserKeyWriteFailure(error) else { return }
            switch failure {
            case .keyGone: break
            case .unconfirmed:
                guard await isGone(key.id, keys: keys) else { keys.report(.failed(failure)); return }
            default:
                keys.report(.failed(failure))
                return
            }
        }
        guard keys.isCurrent(context.generation) else { return }
        keys.remove(id: key.id)
        keys.hooks.onImmediate(.applied(name: UserKeyFormCopy.deletedOperation(key.displayName), grantedGroupID: nil))
        keys.receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: UserKeyFormCopy.objectNoun, displayName: key.displayName),
                                   systemImage: "trash"))
    }
    private func isGone(_ keyID: Int, keys: UserKeysModel) async -> Bool {
        guard let source = keys.keySource else { return false }
        do {
            _ = try await source.apiKey(id: keyID)
            return false
        } catch {
            return UserKeyWriteFailure(error) == .keyGone
        }
    }
}

// MARK: - 显示完整 Key（E03）

extension UserKeyManageModel {
    func revealAvailability(model: AppModel) -> UserKeyReveal.Availability {
        guard let site = model.siteSession else { return .hidden }
        return UserKeyReveal.availability(hasMaskedView: site.has(.apiKeysMaskedView), security: site.me.security, authMethod: site.authMethod)
    }
    /// Verified on the phone every time (R16), then step-up when the site asks for it; the plaintext goes only to the sheet.
    func reveal(_ key: AdminAPIKey, keys: UserKeysModel, model: AppModel) async {
        guard revealingKeyID == nil, let context = keys.context, !context.isReadOnlyToken else { return }
        receipts = keys.receipts
        switch revealAvailability(model: model) {
        case .hidden: return
        case .disabled(let reason):
            keys.receipts.show(Receipt(text: reason, systemImage: "lock", tone: .caution))
            return
        case .available: break
        }
        revealingKeyID = key.id
        defer { revealingKeyID = nil }
        guard await verify(key, model: model, receipts: keys.receipts) else { return }
        do {
            let reveal = try await model.revealAPIKey(id: key.id)
            guard keys.isCurrent(context.generation) else { return }
            revealed = RevealedKeySecret(keyID: key.id, purpose: .reveal, name: key.displayName, plaintext: reveal.key)
        } catch {
            guard keys.isCurrent(context.generation) else { return }
            revealFailed(error, key: key, keys: keys)
        }
    }
    private func verify(_ key: AdminAPIKey, model: AppModel, receipts: ReceiptCenter) async -> Bool {
        let gate = model.biometricGate
        guard gate.isAvailable else {
            receipts.show(Receipt(text: UserKeyFormCopy.biometricUnavailable, systemImage: "faceid", tone: .caution))
            return false
        }
        guard await gate.authorize(.revealKey, reason: UserKeyFormCopy.revealReason(key.displayName)) else { return false }
        switch await model.ensureStepUp(purpose: UserKeyFormCopy.stepUpPurpose, isRead: true) {
        case .passed: return true
        case .cancelled: return false
        case .blocked(let text):
            receipts.show(Receipt(text: text, systemImage: "lock", tone: .caution))
            return false
        }
    }
    private func revealFailed(_ error: any Error, key: AdminAPIKey, keys: UserKeysModel) {
        guard !(error is CancellationError) else { return }
        let api = error as? APIError
        if api?.securityOutcome == .cancelled { return }
        if api?.statusCode == 404, api?.reason == "API_KEY_NOT_FOUND" {
            keys.remove(id: key.id)
            keys.receipts.show(Receipt(text: UserKeyFormCopy.revealGone, systemImage: "exclamationmark.triangle", tone: .critical))
            return
        }
        keys.receipts.show(Receipt(text: error.localizedDescription, systemImage: "exclamationmark.triangle", tone: .critical))
    }
}
