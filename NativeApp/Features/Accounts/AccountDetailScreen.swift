import SwiftUI
import Sub2Core

/// 20 §2: the account detail. From the list it opens on the row's snapshot; with only an id it shows skeletons until `GET :id`
/// answers. Above the sections (S2-09 容量 · 今日 · 记录, then S2-10's 基础 · 调度, edited in AccountSectionSheet, S2-16's 凭据,
/// S2-11's 代理 and S2-12's 模型 · 高级)
/// sit the status card and the button row; the buttons go through AccountActions (20 §5). ⋯ holds the credential items (S2-16),
/// 在 Web 中编辑 and 删除账号… (S2-11). 测试连接 opens the router's test sheet (S2-14); every 重新授权… opens S2-17's sheet.
struct AccountDetailScreen: View {
    @Environment(AppModel.self) private var model
    private let id: Int
    private let focus: AccountDetailFocus?
    private let preload: UpstreamAccount?

    init(id: Int, focus: AccountDetailFocus? = nil, preload: UpstreamAccount? = nil) {
        self.id = id; self.focus = focus; self.preload = preload
    }

    var body: some View { AccountDetailContent(app: model, id: id, focus: focus, preload: preload) }
}

/// The countdown's GET waits for the window end while the page may refresh (20 §2.6).
private struct AccountCountdownWait: Hashable {
    let target: Date?
    let isOpen: Bool
}

private struct AccountDetailContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @State private var detail: AccountDetailModel
    @State private var actions: AccountActions
    /// 代理 (S2-11): the picker, the 恢复原代理 question and its run, the delete confirmation.
    @State private var proxyEditor: AccountProxyEditorRequest?
    @State private var preparingProxy = false
    @State private var reverting: AccountProxyFallbackLine?
    @State private var revert: AccountProxyRevert
    @State private var deleteRequest: DeleteRequest?
    @State private var popsAfterDelete = false
    /// 重新授权 (S2-17): the account its sheet (or the stopped account's question first) opens for.
    @State private var reauthRequest: UpstreamAccount?
    @State private var recovering: UpstreamAccount?
    @State private var running: AccountDetailAction?
    /// 凭据 (S2-16): 刷新令牌, and the 更换 API Key / Base URL sheet with the version read before it opens.
    @State private var refresher: AccountTokenRefresher
    @State private var credentialSheet: AccountCredentialSheetRequest?
    @State private var preparingCredential = false
    @State private var visible = false
    @State private var scrolledToFocus = false
    private let focus: AccountDetailFocus?

    init(app: AppModel, id: Int, focus: AccountDetailFocus?, preload: UpstreamAccount?) {
        let made = AccountDetailModel(app: app, accountID: id, preload: preload)
        _detail = State(initialValue: made)
        // 20 §5.6 / §2.6: a write's account replaces the page's at once.
        _actions = State(initialValue: AccountActions(model: app, onChange: { [weak made] in made?.applyWrite($0) },
                                                      onMissing: { [weak made] _ in made?.noteMissing() }))
        _refresher = State(initialValue: AccountTokenRefresher(model: app, onChange: { [weak made] in made?.applyWrite($0) },
                                                               onMissing: { [weak made] _ in made?.noteMissing() }))
        // 20 §3.4: the account read back after 恢复原代理 replaces the page's, and the list reads everything again.
        _revert = State(initialValue: AccountProxyRevert(source: app, receipts: app.receipts,
                                                         onAccount: { [weak made] in made?.applyEdit(AccountEditBase($0)) },
                                                         onStale: { [weak made] in
                                                             guard let made else { return }
                                                             Task { await made.load() }
                                                         },
                                                         onListChanged: { [weak app] in app?.accountListSignal.bump() }))
        self.focus = focus
    }

    var body: some View {
        // The tasks take the values of this pass, even if onAppear changes them before SwiftUI starts the task.
        let page = detail.page, isOpen = isRefreshOpen
        let wait = AccountCountdownWait(target: countdownTarget, isOpen: isOpen)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content(page) }
                    .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
            }
            .onChange(of: page, initial: true) { _, current in scrollToFocus(current, proxy: proxy) }
        }
        .background(Palette.canvas)
        .navigationTitle(title(page))
        .navigationSubtitle(subtitle(page))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .content = page, let account = detail.account {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(account) }
            }
        }
        .refreshable { await detail.pullToRefresh() }
        .task { await detail.loadCatalog() }
        .task { await detail.loadScheduledTestsIfUnread() }
        .task(id: isOpen) { if isOpen { await detail.poll() } }
        .task(id: wait) { await waitForCountdown(wait) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: model.foregroundRevision) { _, _ in
            Task {
                async let tests: Void = detail.refreshScheduledTestsOnForeground()
                await detail.refreshAll()
                await tests
            }
        }
        // A read that failed while compliance was pending reads again once it is accepted (00 §1.10).
        .onChange(of: model.securityPrompts.complianceRevision) { _, _ in if detail.failure != nil { Task { await detail.load() } } }
        .accountRecoverDialog($recovering, actions: actions)
        // 20 §4.4: a test that ended (here or after its sheet closed) updates the page.
        .onChange(of: model.accountTests?.completion(for: detail.accountID)?.id) { _, _ in
            guard let completion = model.accountTests?.completion(for: detail.accountID) else { return }
            Task { await detail.testFinished(completion) }
        }
        .sheet(item: Binding(get: { detail.editor }, set: { detail.editor = $0 })) { AccountSectionSheet(request: $0) }
        .accountProxyPrompts(editor: $proxyEditor, reverting: $reverting, onSaved: { model.accountListSignal.bump() },
                             onRevert: { _ in startRevert() })
        .confirmDelete($deleteRequest)
        // 20 §3.4: the deleted account's page leaves once the confirmation has closed.
        .onChange(of: deleteRequest == nil) { _, closed in
            guard closed, popsAfterDelete else { return }
            popsAfterDelete = false
            dismiss()
        }
        .accountCredentialSheet($credentialSheet)
        .accountReauthorize($reauthRequest, platformName: { AccountNaming.platformName($0.platform, catalog: detail.catalog) },
                            onFinished: { reauthorized($0) }, onMissing: { detail.noteMissing() },
                            onEditInWeb: { model.openAccountInWeb($0, using: openURL) })
        // 20 §2.3: “本次已更换 Key” ends with the error it was made for.
        .onChange(of: [detail.account?.status, detail.account?.errorAt], initial: true) { _, _ in
            if let account = detail.account { model.accountKeyMarks.reconcile(account) }
        }
    }

    // MARK: - Pages (20 §2.5)

    @ViewBuilder private func content(_ page: AccountDetailPageState) -> some View {
        switch page {
        case .skeleton: AccountDetailSkeleton()
        case .failure(let message): AccountDetailFailurePage(message: message) { Task { await detail.load() } }
        case .removed: AccountDetailRemovedPage()
        case .content(let banner):
            if let banner { snapshotBanner(banner) }
            if let account = detail.account {
                top(account)
                sections(account)
                editSections(account)
                credentialSection(account)
                proxySection(account)
                AccountModelsSection(account: account, now: { serverNow }, edit: sectionEdit(.models)).id(AccountDetailFocus.models)
                AccountAdvancedSection(account: account, catalog: detail.catalog, edit: sectionEdit(.adv)) { model.openAccountInWeb(account, using: openURL) }
                    .id(AccountDetailFocus.adv)
            }
            // 分区：各节挂 .id(AccountDetailFocus.xxx)，focus 由 scrollToFocus 滚到（X39）
        }
    }

    /// 容量（壹）· 今日（贰）· 记录（叁）, numbered over the sections shown (S2-09).
    @ViewBuilder private func sections(_ account: UpstreamAccount) -> some View {
        let timeZone = session?.site.serverTimeZone.timeZone ?? .current
        let capacity = AccountDetailPresentation.capacityRows(account: account, usageWindow: detail.usageWindow.value, timeZone: timeZone)
        let ordinals = AccountDetailPresentation.sectionOrdinals(hasCapacity: !capacity.isEmpty)
        if let ordinal = ordinals.capacity {
            AccountCapacitySection(rows: capacity, ordinal: ordinal,
                                   updatedText: AccountDetailPresentation.capacityUpdatedText(detail.updatedAt, timeZone: timeZone))
        }
        AccountTodaySection(load: detail.today, ordinal: ordinals.today, autoRetry: isRefreshOpen) { await detail.reloadToday() }
        AccountRecordsSection(account: RouteObject(id: account.id, name: account.name), upstream: detail.upstreamErrors.state,
                              ordinal: ordinals.records, showsScheduledTests: true, scheduledSummary: detail.scheduledTestsSummary)
    }

    /// 基础 · 调度 (S2-10), each with “编辑”; the route's focus scrolls to them.
    @ViewBuilder private func editSections(_ account: UpstreamAccount) -> some View {
        let platform = AccountNaming.platformName(account.platform, catalog: detail.catalog) + " · "
            + AccountNaming.typeName(platform: account.platform, type: account.type)
        AccountBasicSection(account: account, platformText: platform, edit: sectionEdit(.basic)).id(AccountDetailFocus.basic)
        AccountScheduleSection(account: account, groupName: { groupName($0, in: account) }, edit: sectionEdit(.sched)).id(AccountDetailFocus.sched)
    }
    /// Greyed while the page has only the list's copy or a write runs; “先刷新账号” once reading it failed.
    private func sectionEdit(_ section: AccountEditSection) -> AccountSectionEdit {
        let needsRefresh = detail.editNeedsRefresh || (!detail.canEdit && detail.failure != nil)
        return AccountSectionEdit(isEnabled: detail.canEdit && running == nil, needsRefresh: needsRefresh, isPreparing: detail.isPreparingEdit) {
            Task { await detail.beginEdit(section) }
        }
    }
    /// 代理 (S2-11): 编辑 and the 无代理 row open the picker on the account's current version (S2D1-06); a proxy row pushes its
    /// detail and 恢复原代理 needs no version.
    private func proxySection(_ account: UpstreamAccount) -> some View {
        let needsRefresh = detail.editNeedsRefresh || (!detail.canEdit && detail.failure != nil)
        let edit = AccountSectionEdit(isEnabled: detail.canEdit && running == nil && !revert.isRunning, needsRefresh: needsRefresh,
                                      isPreparing: preparingProxy) { beginProxyEdit() }
        return AccountProxySection(content: AccountProxyPresentation.section(account, now: serverNow, timeZone: serverZone), edit: edit,
                                   isReverting: revert.runningAccountID == account.id, onOpenProxy: { router.push(.proxyDetail(id: $0)) },
                                   onRevert: { reverting = $0 })
            .id(AccountDetailFocus.proxy)
    }
    private func beginProxyEdit() {
        guard proxyEditor == nil, !preparingProxy else { return }
        preparingProxy = true
        Task {
            defer { preparingProxy = false }
            guard let base = await detail.editVersion(), let flow = detail.makePatchFlow() else { return }
            proxyEditor = AccountProxyEditorRequest(base: base, flow: flow)
        }
    }
    private func startRevert() {
        guard let account = detail.account else { return }
        let router = router
        Task { await revert.revert(account, openOrigin: { router.push(.proxyDetail(id: $0)) }) }
    }
    /// 凭据 (S2-16): 更换 and 修改 open their sheet on the account's current version, like 编辑 (S2D1-06); 刷新令牌 needs none.
    private func credentialSection(_ account: UpstreamAccount) -> some View {
        AccountCredentialSection(account: account, kind: credentialKind(account), replacedAt: model.accountKeyMarks.mark(for: account)?.replacedAt,
                                 canEdit: detail.canEdit && running == nil && !preparingCredential,
                                 needsRefresh: detail.editNeedsRefresh || (!detail.canEdit && detail.failure != nil),
                                 isRefreshing: refresher.isRunning(account.id), timeZone: serverZone.timeZone, now: { serverNow },
                                 handlers: credentialHandlers(account))
            .id(AccountDetailFocus.cred)
    }
    private func credentialKind(_ account: UpstreamAccount) -> AccountCredentialKind { AccountCredentialKind.of(account, catalog: detail.catalog) }
    private func credentialHandlers(_ account: UpstreamAccount) -> AccountCredentialHandlers {
        let refresher = refresher
        return AccountCredentialHandlers(replaceKey: { beginCredentialEdit(.replaceKey) }, editBaseURL: { beginCredentialEdit(.baseURL) },
                                         refresh: { Task { await refresher.refresh(account) } }, reauthorize: { reauthRequest = account },
                                         openWeb: { model.openAccountInWeb(account, using: openURL) })
    }
    private func beginCredentialEdit(_ kind: AccountCredentialSheetRequest.Kind) {
        guard credentialSheet == nil, !preparingCredential else { return }
        preparingCredential = true
        Task {
            defer { preparingCredential = false }
            guard let base = await detail.editVersion(), let flow = detail.makePatchFlow() else { return }
            credentialSheet = AccountCredentialSheetRequest(kind: kind, base: base, flow: flow)
        }
    }
    private func groupName(_ id: Int, in account: UpstreamAccount) -> String {
        account.groups.first { $0.id == id }?.name ?? model.groupDirectory?.name(for: id) ?? "#\(id)"
    }

    private func snapshotBanner(_ text: String) -> some View {
        StatusBanner(tone: .neutral, systemImage: "exclamationmark.arrow.triangle.2.circlepath", title: text) {
            Button("重试") { Task { await detail.load() } }
                .buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("account.detail.snapshot-banner.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.detail.snapshot-banner")
    }

    private func top(_ account: UpstreamAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AccountStatusCard(account: account) { AccountUpstreamErrorLineView(account: account, upstream: detail.upstreamErrors.state) }
            AccountActionButtonRow(row: AccountDetailPresentation.actionRow(account, now: serverNow, keyReplaced: model.accountKeyMarks.isReplaced(account)),
                                   running: shownRunning(account)) {
                perform($0, on: account)
            }
                .disabled(running != nil || actions.isRunning(account.id))
        }
    }

    // MARK: - Actions (20 §2.4)

    private func perform(_ action: AccountDetailAction, on account: UpstreamAccount) {
        switch action {
        case .test: router.present(.accountTest(id: account.id))
        case .stopScheduling, .resumeScheduling:
            run(action) { await actions.setSchedulable(account, enabled: action == .resumeScheduling) }
        case .enableAccount:
            let etag = detail.etagNeedsRefresh ? nil : detail.etag
            run(action) { await actions.enableAccount(account, etag: etag) }
        case .recover: recovering = account
        case .webCredential: model.openAccountInWeb(account, using: openURL)
        case .replaceKey: beginCredentialEdit(.replaceKey)
        case .reauthorize: reauthRequest = account
        // S2D1-20: 修改过期时间… opens the 调度 sheet.
        case .editExpiry: Task { await detail.beginEdit(.sched) }
        }
    }
    /// A test that goes on after its sheet closed spins 测试连接, which still opens the sheet to follow it.
    private func shownRunning(_ account: UpstreamAccount) -> AccountDetailAction? {
        running ?? (model.accountTests?.isRunning(account.id) == true ? .test : nil)
    }
    private func run(_ action: AccountDetailAction, _ write: @escaping @MainActor () async -> AccountActionOutcome) {
        guard running == nil else { return }
        running = action
        Task {
            _ = await write()
            running = nil
        }
    }

    // MARK: - ⋯, sheets and refresh

    private func moreMenu(_ account: UpstreamAccount) -> some View {
        AccountDetailMenu(onOpenWeb: { model.openAccountInWeb(account, using: openURL) }, onDelete: { confirmDelete(account) }) {
            AccountCredentialMenuItems(kind: credentialKind(account), isRefreshing: refresher.isRunning(account.id), handlers: credentialHandlers(account))
        }
    }
    /// 20 §3.4: the delete confirmation; a deleted (or already gone) account pops the page and the list reads everything again.
    private func confirmDelete(_ account: UpstreamAccount) {
        let flow = AccountDeleteFlow(source: model, receipts: model.receipts)
        let signal = model.accountListSignal
        deleteRequest = .account(account, siteName: model.activeProfile?.name ?? "") {
            await flow.delete(account) {
                signal.bump()
                popsAfterDelete = true
            }
        }
    }

    /// 20 §6.4-4 / §6.6: the account the server returned (or read back) replaces the page's, its version is read again before the
    /// next PATCH, the list reads everything again, and the receipt offers 测试 or 启用调度.
    private func reauthorized(_ result: AccountReauthResult) {
        if let version = result.version { detail.apply(version) } else { detail.applyWrite(result.account) }
        model.accountListSignal.bump()
        model.receipts.show(result.receipt(router: router, actions: actions))
        Task { await detail.load() }
    }
    // MARK: - Refresh gates (20 §2.6)

    /// Foreground, visible, nothing over the page (the router's sheets included) and no write running.
    private var isRefreshOpen: Bool {
        guard visible, scenePhase == .active, !model.isSuspended, reauthRequest == nil, router.presentedSheet == nil, detail.editor == nil,
              recovering == nil, credentialSheet == nil,
              running == nil, !detail.isRemoved, proxyEditor == nil, reverting == nil, deleteRequest == nil, !revert.isRunning else { return false }
        return !actions.isRunning(detail.accountID) && !refresher.isRunning(detail.accountID)
    }
    private var countdownTarget: Date? { detail.account.flatMap { AccountDisplayState($0, now: serverNow).countdownTarget } }
    private func waitForCountdown(_ wait: AccountCountdownWait) async {
        guard wait.isOpen, let target = wait.target else { return }
        let seconds = max(0, target.timeIntervalSince(serverNow)) + 0.5
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        await detail.countdownElapsed(target: target)
    }
    /// X39: the route's section, once, when the account first shows; after a turn, so the sections are laid out.
    private func scrollToFocus(_ page: AccountDetailPageState, proxy: ScrollViewProxy) {
        guard case .content = page, !scrolledToFocus, let focus else { return }
        scrolledToFocus = true
        Task {
            await Task.yield()
            withAnimation { proxy.scrollTo(focus, anchor: .top) }
        }
    }

    private func title(_ page: AccountDetailPageState) -> String {
        if case .removed = page { return AccountDetailPresentation.removedTitle }
        return detail.account?.name ?? AccountDetailPresentation.removedTitle
    }
    private func subtitle(_ page: AccountDetailPageState) -> String {
        if case .removed = page { return AccountDetailPresentation.removedSubtitle }
        return detail.account.map { AccountDetailPresentation.subtitle($0, catalog: detail.catalog) } ?? ""
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
    private var serverZone: ServerTimeZone { session?.site.serverTimeZone ?? .device }
}

/// 20 §2.5 只带 id 进入: the status card's and button row's shapes, and the sections' places.
private struct AccountDetailSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface).frame(height: 132)
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Palette.sunken).frame(height: 46) }
            }
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface).frame(height: 112)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在读取账号")
        .accessibilityIdentifier("account.detail.skeleton")
    }
}

/// 20 §2.5: `GET :id` failed and there is no snapshot.
private struct AccountDetailFailurePage: View {
    let message: String
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(AccountDetailPresentation.loadFailedTitle, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { retry() }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("account.detail.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.detail.failure")
    }
}

/// Design RemovedAccount: 404 ACCOUNT_NOT_FOUND replaces the whole page.
private struct AccountDetailRemovedPage: View {
    var body: some View {
        Text(AccountDetailPresentation.removedMessage)
            .font(.subheadline).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, minHeight: 240)
            .accessibilityIdentifier("account.detail.removed")
    }
}
