import Foundation
import Observation
import Sub2Core

/// The pages the form pushes in its own stack (20 §3.1: no second sheet).
enum AccountNewPage: Hashable { case proxy, expiry, customExpiry }

/// 20 §7 新建账号: the draft (S2-18's rules: methods, 还差, switching, the request), the catalog, groups and proxies read once
/// when the form opens, the per-group mixed-channel marks, the embedded authorization, and AccountNewSubmission's create. Keys,
/// tokens and the Service Account JSON live only in `draft`, which goes with the sheet (U16).
@MainActor @Observable
final class AccountNewModel {
    /// Where 还差 and 返回修改分组 scroll.
    enum Anchor: String, Hashable, Sendable { case banner, platform, credentials, name, groups, schedule, network, more }
    enum Prompt: Identifiable, Equatable {
        case discard(AccountNewConfirmation)
        case switchPlatform(String, AccountNewConfirmation)
        case switchMethod(AccountNewMethod, AccountNewConfirmation)
        case switchClaudeKind(OAuthAuthKind, AccountNewConfirmation)
        case switchGeminiType(GeminiOAuthType, AccountNewConfirmation)
        /// “账号「{name}」可能还在参与调度”: 重试停止调度 / 仍然关闭 / 继续处理.
        case pauseUnconfirmed
        /// “账号「{name}」可能已经创建”: 核对 / 仍然关闭 / 继续处理 (00 §2.5.4: the create's result is still unknown).
        case createUnconfirmed
        var id: String {
            switch self {
            case .discard: "discard"
            case .switchPlatform(let id, _): "platform." + id
            case .switchMethod(let method, _): "method." + method.id
            case .switchClaudeKind(let kind, _): "kind." + kind.rawValue
            case .switchGeminiType(let type, _): "gemini." + type.rawValue
            case .pauseUnconfirmed: "pause"
            case .createUnconfirmed: "unconfirmed"
            }
        }
        var confirmation: AccountNewConfirmation? {
            switch self {
            case .discard(let question), .switchPlatform(_, let question), .switchMethod(_, let question), .switchClaudeKind(_, let question),
                 .switchGeminiType(_, let question): question
            case .pauseUnconfirmed, .createUnconfirmed: nil
            }
        }
        /// The three-answer questions about a result that is not confirmed.
        var isResolution: Bool { self == .pauseUnconfirmed || self == .createUnconfirmed }
    }

    var draft: AccountNewDraft
    private(set) var catalog: MetaCatalog = .builtin
    private(set) var catalogFailed = false
    let proxies = LoadState<[AdminProxy]>()
    /// The picked groups the pre-check found at risk (20 §7.2), by group id.
    private(set) var mixedRisks: [Int: MixedChannelWarning] = [:]
    private(set) var oauthFlow: OAuthFlowModel?
    let submission: AccountNewSubmission
    var prompt: Prompt?
    var scrollTarget: Anchor?
    var path: [AccountNewPage] = []
    var moreExpanded = false
    private(set) var vertexError: String?
    /// The form is done (created, or closed anyway): the view dismisses.
    private(set) var isFinished = false
    /// 继续创建 was tapped; the question stays closed until that send ends.
    private var answeredMixedChannel = false
    @ObservationIgnored let app: AppModel
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private var summary: AccountStatusSummary?
    @ObservationIgnored private var counts: [String: Int] = [:]
    @ObservationIgnored private var pickedProxyName: String?
    /// 换个代理再试: picking a proxy exchanges the same code again (20 §7.4-6).
    @ObservationIgnored private var exchangesAfterProxyPick = false

    init(app: AppModel, router: AppRouter) {
        self.app = app; self.router = router
        draft = AccountNewDraft(isLegacyServer: app.siteSession?.me.isLegacyServer ?? false)
        submission = AccountNewSubmission(source: app)
    }

    // MARK: Reading

    var siteName: String { app.activeProfile?.name ?? "" }
    var shelves: [AccountNewShelfSection] { AccountNewCatalog.sections(catalog) }
    var methods: [AccountNewMethod] { draft.platform.map { AccountNewCatalog.methods(for: $0, in: catalog) } ?? [] }
    var platformName: String? { draft.platform.map { AccountNaming.platformName($0, catalog: catalog) } }
    var isAccountMode: Bool { draft.platform.flatMap { catalog.platform($0)?.multiProtocol } != nil }
    var isAntigravity: Bool { draft.platform == OAuthPlatform.antigravity.rawValue }
    /// S2-18's 还差 list, then an address filled in but malformed (it keeps the request from being built).
    var missingItems: [(label: String, anchor: Anchor)] {
        let items = draft.missing(in: catalog).map { (label: $0.label, anchor: Self.anchor($0.anchor)) }
        let issues = draft.issues.map { (label: Self.issueLabel($0.field), anchor: Anchor.credentials) }
        return items + issues.filter { issue in !items.contains { $0.label == issue.label } }
    }
    var subtitle: String {
        AccountNewFlow.subtitle(site: siteName, missingCount: missingItems.count, createdID: submission.createdAccountID, status: submission.scheduleStatus)
    }
    var dock: AccountNewDockContent { AccountNewDockContent.make(stage: submission.stage, missing: missingItems.map(\.label), keyed: submission.isKeyed) }
    var groupsState: BlockState<[AdminGroup]> { app.groupDirectory?.state ?? .idle }
    var eligibleGroups: [AdminGroup] {
        guard let platform = draft.platform else { return [] }
        return AccountNewGroups.eligible(app.groupDirectory?.groups ?? [], platform: platform, mixedScheduling: draft.mixedScheduling)
    }
    var riskyGroups: [AdminGroup] { eligibleGroups.filter { draft.groupIDs.contains($0.id) && mixedRisks[$0.id] != nil } }
    var oauthInProgress: Bool { oauthFlow?.link != nil && draft.oauthGrant == nil }
    var isPauseUnconfirmed: Bool { if case .pauseUnconfirmed = submission.stage { true } else { false } }
    /// The create and the check by name both came back unknown: the account may exist.
    var isResultUnconfirmed: Bool { if case .unconfirmed = submission.stage { true } else { false } }
    var mixedChannelWarning: MixedChannelWarning? {
        guard !answeredMixedChannel, case .confirmingMixedChannel(let warning) = submission.stage else { return nil }
        return warning
    }
    /// Swiping the sheet away would lose what was entered, or leave a create half done.
    var blocksInteractiveDismiss: Bool { draft.platform != nil || submission.isBusy || submission.createdAccountID != nil }
    var proxyName: String? {
        guard let id = draft.proxyID else { return nil }
        return proxies.value?.first { $0.id == id }?.name ?? pickedProxyName ?? "#\(id)"
    }
    var accountName: String { submission.account?.name ?? draft.name }

    // MARK: Loading (20 §7.6: once when the form opens)

    func load() async {
        async let catalogRead: Void = loadCatalog()
        async let groupsRead: Void = loadGroups(refreshing: true)
        async let proxiesRead: Void = loadProxies()
        async let summaryRead: Void = loadSummary()
        _ = await (catalogRead, groupsRead, proxiesRead, summaryRead)
    }
    func loadCatalog() async {
        let result = await app.metaCatalogResult()
        catalog = result.catalog
        catalogFailed = result.failed
    }
    func loadGroups(refreshing: Bool) async {
        guard let directory = app.groupDirectory else { return }
        if refreshing, directory.state.value != nil { await directory.refresh() } else { await directory.ensureLoaded() }
    }
    func retryGroups() async { await app.groupDirectory?.refresh() }
    func loadProxies() async {
        let app = app, generation = app.sessionGeneration
        await proxies.load(isCurrent: { app.sessionGeneration == generation }) { try await app.allProxies(withCount: true) }
    }
    private func loadSummary() async {
        guard app.sessionContext?.has(.accountsStatusSummary) == true, let read = try? await app.accountStatusSummary() else { return }
        summary = read
        if let platform = draft.platform { draft.suggestName(suggestedName(for: platform)) }
    }

    // MARK: Platform, method and authorization kind (20 §7.4-5)

    func requestPlatform(_ id: String) {
        guard id != draft.platform, !submission.locksForm else { return }
        let name = AccountNaming.platformName(id, catalog: catalog)
        if let question = draft.platformSwitchConfirmation(toPlatformName: name, oauthInProgress: oauthInProgress) {
            prompt = .switchPlatform(id, question)
        } else {
            switchPlatform(to: id)
        }
    }
    func requestMethod(_ method: AccountNewMethod) {
        guard method.id != draft.method?.id, !submission.locksForm else { return }
        if let question = draft.methodSwitchConfirmation(to: method, createdAccountID: nil, oauthInProgress: oauthInProgress) {
            prompt = .switchMethod(method, question)
        } else {
            switchMethod(to: method)
        }
    }
    /// After authorizing, OAuth / Setup Token asks first; before, the list's own picker changes it.
    func requestClaudeKind(_ kind: OAuthAuthKind) {
        guard kind != draft.claudeAuthKind, !submission.locksForm else { return }
        if let question = draft.authKindSwitchConfirmation(toTitle: kind.title) { prompt = .switchClaudeKind(kind, question) } else { applyClaudeKind(kind) }
    }
    func requestGeminiType(_ type: GeminiOAuthType) {
        guard type != draft.geminiOAuthType, !submission.locksForm else { return }
        if let question = draft.authKindSwitchConfirmation(toTitle: type.title) { prompt = .switchGeminiType(type, question) } else { applyGeminiType(type) }
    }
    /// The destructive button of the current question; true when the form should close.
    func confirmPrompt() -> Bool {
        guard let prompt else { return false }
        self.prompt = nil
        switch prompt {
        case .discard: return true
        case .switchPlatform(let id, _): switchPlatform(to: id)
        case .switchMethod(let method, _): switchMethod(to: method)
        case .switchClaudeKind(let kind, _): applyClaudeKind(kind)
        case .switchGeminiType(let type, _): applyGeminiType(type)
        case .pauseUnconfirmed, .createUnconfirmed: break
        }
        return false
    }

    private func switchPlatform(to id: String) {
        draft = draft.switchingPlatform(to: id, methods: AccountNewCatalog.methods(for: id, in: catalog), suggestedName: suggestedName(for: id))
        mixedRisks = [:]
        rebuildOAuthFlow()
        guard knownCount(id) == nil else { return }
        Task { await countAccounts(on: id) }
    }
    private func switchMethod(to method: AccountNewMethod) {
        draft = draft.switchingMethod(to: method)
        vertexError = nil
        rebuildOAuthFlow()
    }
    private func applyClaudeKind(_ kind: OAuthAuthKind) {
        draft = draft.switchingClaudeAuthKind(kind)
        oauthFlow?.restart()
        oauthFlow?.selectKind(kind)
    }
    private func applyGeminiType(_ type: GeminiOAuthType) {
        draft = draft.switchingGeminiOAuthType(type)
        oauthFlow?.restart()
        oauthFlow?.selectGeminiType(type)
    }
    private func rebuildOAuthFlow() {
        guard case .oauth? = draft.method?.kind, let platform = draft.platform.flatMap(OAuthPlatform.init(accountPlatform:)) else {
            oauthFlow = nil
            return
        }
        let gemini = platform == .gemini
        let request = OAuthLinkRequest(platform: platform, kind: platform == .anthropic ? draft.claudeAuthKind : .oauth, proxyID: draft.proxyID,
                                       geminiOAuthType: draft.geminiOAuthType, projectID: draft.gcpProjectID,
                                       tierID: gemini ? draft.geminiOAuthType.defaultTierID : nil)
        oauthFlow = OAuthFlowModel(request: request, variant: .create, choosesGeminiType: gemini, source: app)
    }

    // MARK: Names (20 §7.2 名称建议)

    private func knownCount(_ platform: String) -> Int? {
        if let rows = summary?.platforms, !rows.isEmpty {
            return AccountNewNaming.existingCount(platform: platform, summary: summary, loadedAccounts: [])
        }
        return counts[platform]
    }
    private func suggestedName(for platform: String) -> String {
        AccountNewNaming.suggestedName(platform: platform, existingCount: knownCount(platform) ?? 0)
    }
    /// Without per-platform rows, the list's count for the platform.
    private func countAccounts(on platform: String) async {
        guard let page = try? await app.managedAccounts(page: 1, query: AccountListQuery(platform: platform, pageSize: 1)) else { return }
        counts[platform] = page.total
        if draft.platform == platform { draft.suggestName(suggestedName(for: platform)) }
    }
}

// MARK: - Groups, network, files, authorization

extension AccountNewModel {
    /// Picked in order (S2D1-07); an Anthropic / Antigravity pick is checked on its own for the chip's mark (20 §7.2).
    func toggleGroup(_ id: Int) {
        guard !submission.locksForm else { return }
        if draft.groupIDs.contains(id) {
            draft.groupIDs.removeAll { $0 == id }
            mixedRisks[id] = nil
            return
        }
        draft.groupIDs.append(id)
        Task { await precheckGroup(id) }
    }
    /// Antigravity's “在 /v1/messages 中使用”: turning it off drops the groups it allowed, with 撤销 on the receipt (20 §7.4-5).
    func setMixedScheduling(_ isOn: Bool) {
        guard !submission.locksForm, isAntigravity else { return }
        let before = draft.groupIDs
        let result = draft.settingMixedScheduling(isOn, groups: app.groupDirectory?.groups ?? [])
        draft = result.draft
        for id in result.removedGroupIDs { mixedRisks[id] = nil }
        guard !result.removedGroupIDs.isEmpty else { return }
        app.receipts.show(Receipt(text: AccountNewCopy.groupsRemovedReceipt(count: result.removedGroupIDs.count), systemImage: "minus.circle",
                                  tone: .neutral, undo: { [weak self] in self?.restoreMixedScheduling(groups: before) }))
    }
    private func restoreMixedScheduling(groups: [Int]) {
        guard isAntigravity, !submission.locksForm else { return }
        var next = draft.settingMixedScheduling(true, groups: app.groupDirectory?.groups ?? []).draft
        next.groupIDs = groups
        draft = next
        for id in groups { Task { await precheckGroup(id) } }
    }
    private func precheckGroup(_ id: Int) async {
        guard let platform = draft.platform, [OAuthPlatform.anthropic.rawValue, OAuthPlatform.antigravity.rawValue].contains(platform),
              let session = app.accountCreateSession, !session.isReadOnlyToken,
              let check = try? await app.checkMixedChannel(platform: platform, groupIDs: [id], accountID: nil, generation: session.generation),
              app.sessionGeneration == session.generation, draft.platform == platform, draft.groupIDs.contains(id) else { return }
        mixedRisks[id] = MixedChannelWarning(check: check)
    }

    func pickProxy(_ choice: AccountProxyChoice) {
        draft.proxyID = choice.proxyID
        pickedProxyName = choice.displayName
        oauthFlow?.updateProxy(choice.proxyID)
        path.removeAll()
        guard exchangesAfterProxyPick else { return }
        exchangesAfterProxyPick = false
        Task { await finishAuthorization() }
    }
    /// 换个代理再试 / 改选代理.
    func chooseProxyForExchange() {
        exchangesAfterProxyPick = true
        path = [.proxy]
    }

    /// fileImporter's JSON, read here and kept only in the draft.
    func importVertex(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= VertexServiceAccountFile.maxBytes else { throw APIError(kind: .validation, message: "Service Account JSON 格式无效") }
            draft.vertexFile = try VertexServiceAccountFile(fileName: url.lastPathComponent, data: Data(contentsOf: url))
            vertexError = nil
        } catch {
            vertexError = (error as? APIError)?.localizedDescription ?? "Service Account JSON 格式无效"
        }
    }

    /// ③ 完成授权: exchange-code with the proxy picked now; the token goes only into the draft (20 §7.4-6).
    func finishAuthorization() async {
        guard let flow = oauthFlow, !flow.isBusy, case .ready(let ready) = flow.submission(at: flow.now), let session = app.oauthSession,
              !session.isReadOnlyToken else { return }
        flow.beginExchange()
        do {
            let token = try await app.exchangeOAuthCode(ready.link, code: ready.code, proxyID: ready.proxyID, generation: session.generation)
            guard app.sessionGeneration == session.generation, oauthFlow === flow else { return }
            var next = draft
            switch ready.link.platform {
            case .anthropic: next = next.switchingClaudeAuthKind(ready.link.request.kind)
            case .gemini:
                next = next.switchingGeminiOAuthType(ready.link.request.geminiOAuthType)
                next.gcpProjectID = ready.link.request.projectID ?? ""
            default: break
            }
            next.oauthGrant = AccountNewOAuthGrant(token)
            draft = next
            flow.finishExchange(email: token.accountEmail)
        } catch {
            guard app.sessionGeneration == session.generation, oauthFlow === flow else { return }
            let copy = (error as? APIError).flatMap {
                AccountOAuthErrorCopy.resolve($0, flow: .exchange, platform: ready.link.platform, reasonsSupported: session.errorReasons)
            }
            flow.failExchange(copy ?? AccountOAuthErrorCopy(message: AccountActionCopy.reason(for: error), step: .code, remedies: [.retry]))
            if AccountActionCopy.disposition(of: error) == .cancelled { flow.clearError() }
        }
    }
    /// 重新授权 from the done state: back to step 1.
    func resetAuthorization() {
        guard !submission.locksForm else { return }
        draft.oauthGrant = nil
        oauthFlow?.restart()
    }
}

// MARK: - Submitting, cancelling and the dock

extension AccountNewModel {
    func perform(_ action: AccountNewDockContent.Action) {
        switch action {
        case .create: submit()
        case .retrySameKey, .resend: run { await $0.retrySameKey() }
        case .reconcile: run { await $0.reconcile() }
        case .retryPause: run { await $0.retryPause() }
        }
    }
    func confirmMixedChannel() {
        answeredMixedChannel = true
        run { await $0.confirmMixedChannel() }
    }
    func declineMixedChannel() {
        submission.declineMixedChannel()
        scrollTarget = .groups
    }
    func jumpToFirstMissing() { scrollTarget = missingItems.first?.anchor }

    /// true: close now (nothing picked). Otherwise a question is set, or nothing happens while a request is out.
    func cancelRequested() -> Bool {
        let action = AccountNewFlow.cancelAction(hasPlatform: draft.platform != nil, isCreated: submission.createdAccountID != nil,
                                                 isBusy: submission.isBusy, isTesting: false, isPassed: false, pauseUnconfirmed: isPauseUnconfirmed,
                                                 resultUnconfirmed: isResultUnconfirmed)
        switch action {
        case .close, .finish, .resolveCreated: return true
        case .confirmDiscard:
            guard let question = draft.discardConfirmation(oauthInProgress: oauthInProgress) else { return true }
            prompt = .discard(question)
        case .resolvePauseFailed: prompt = .pauseUnconfirmed
        case .resolveUnconfirmed: prompt = .createUnconfirmed
        case .blocked, .continueInBackground: break
        }
        return false
    }
    /// 仍然关闭 while the stop is not confirmed: a receipt that leads to the account, where it can be stopped by hand. While the
    /// create itself is not confirmed there is no account to lead to: the receipt says to check the list (the key goes with the form).
    func closeAnyway() {
        if let account = submission.account {
            app.receipts.show(Receipt(text: AccountNewCopy.leftUnconfirmedReceipt(name: account.name), systemImage: "exclamationmark.triangle",
                                      tone: .caution, action: viewAction(account)))
        } else if isResultUnconfirmed {
            app.receipts.show(Receipt(text: AccountNewCopy.leftCreateUnconfirmedReceipt(name: draft.name), systemImage: "questionmark.circle",
                                      tone: .caution))
        }
        isFinished = true
    }

    private func submit() {
        guard missingItems.isEmpty else { return jumpToFirstMissing() }
        do {
            let request = try draft.createRequest()
            run { await $0.submit(request) }
        } catch {
            app.receipts.show(Receipt(text: AccountActionCopy.reason(for: error), systemImage: "exclamationmark.triangle", tone: .critical))
        }
    }
    /// Not tied to the view: a create that was sent finishes, and its receipt shows, after the sheet has gone.
    private func run(_ body: @escaping @MainActor (AccountNewSubmission) async -> Void) {
        let submission = submission
        Task {
            await body(submission)
            self.answeredMixedChannel = false
            self.settled()
        }
    }
    /// S2-19's step before S2-20's test sheet: created and outside the scheduler, the form closes with “已创建「{name}」· 暂停调度”.
    private func settled() {
        guard case .created = submission.stage, let account = submission.account, !isFinished else { return }
        let copy = AccountNewCopy.createdReceipt(name: account.name)
        app.receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: viewAction(account)))
        isFinished = true
    }
    private func viewAction(_ account: UpstreamAccount) -> ReceiptAction {
        let router = router
        return ReceiptAction(title: AccountNewCopy.viewAccount) { [weak router] in
            guard let router else { return }
            router.selectedTab = .accounts
            router.setPath(router.path(for: .accounts) + [.account(id: account.id, preload: RoutePreload(account))], for: .accounts)
        }
    }

    private static func anchor(_ anchor: AccountNewMissing.Anchor) -> Anchor {
        switch anchor {
        case .platform: .platform
        case .oauth, .credentials: .credentials
        case .name: .name
        case .schedule: .schedule
        }
    }
    private static func issueLabel(_ field: AccountNewIssue.Field) -> String {
        switch field {
        case .baseURL: "Base URL"
        case .customEndpoint: "自定义端点"
        case .upstreamBaseURL: "上游 Base URL"
        }
    }
}
