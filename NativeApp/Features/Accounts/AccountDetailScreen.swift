import SwiftUI
import Sub2Core

/// 20 §2: the account detail. From the list it opens on the row's snapshot; with only an id it shows skeletons until `GET :id`
/// answers. Above the sections later items add (S2-09 容量 · 今日 · 记录, S2-10 起 the edit sections) sit the status card and
/// the button row; the buttons go through AccountActions (20 §5). Until their items land, 测试连接 opens the old test page
/// (S2-14), the credential fixes a placeholder (S2-11 / S2-16 / S2-17), and ⋯ keeps the old edit page (S2-10) and refresh (S2-16).
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

private enum AccountDetailSheet: Hashable, Identifiable {
    case legacyTest, legacyEdit, placeholder(AccountDetailAction)
    var id: Self { self }
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
    @State private var detail: AccountDetailModel
    @State private var actions: AccountActions
    @State private var sheet: AccountDetailSheet?
    @State private var recovering: UpstreamAccount?
    @State private var confirmingRefresh = false
    @State private var running: AccountDetailAction?
    @State private var visible = false
    @State private var reloadsOnDismiss = false
    @State private var scrolledToFocus = false
    private let focus: AccountDetailFocus?

    init(app: AppModel, id: Int, focus: AccountDetailFocus?, preload: UpstreamAccount?) {
        let made = AccountDetailModel(app: app, accountID: id, preload: preload)
        _detail = State(initialValue: made)
        // 20 §5.6 / §2.6: a write's account replaces the page's at once.
        _actions = State(initialValue: AccountActions(model: app, onChange: { [weak made] in made?.applyWrite($0) },
                                                      onMissing: { [weak made] _ in made?.noteMissing() }))
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
        .refreshable { await detail.refreshAll() }
        .task { await detail.loadCatalog() }
        .task(id: isOpen) { if isOpen { await detail.poll() } }
        .task(id: wait) { await waitForCountdown(wait) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: model.foregroundRevision) { _, _ in Task { await detail.load() } }
        // A read that failed while compliance was pending reads again once it is accepted (00 §1.10).
        .onChange(of: model.securityPrompts.complianceRevision) { _, _ in if detail.failure != nil { Task { await detail.load() } } }
        .accountRecoverDialog($recovering, actions: actions)
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheetContent($0) }
        .confirmationDialog("刷新令牌？", isPresented: $confirmingRefresh, titleVisibility: .visible) {
            Button("刷新令牌") { Task { await refreshToken() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("站点：\(model.activeProfile?.name ?? "")\n账号：\(detail.account?.name ?? "")（#\(detail.accountID)）")
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
            if let account = detail.account { top(account) }
            // 分区：S2-09 起在此追加（各节挂 .id(AccountDetailFocus.xxx)，focus 由 scrollToFocus 滚到，X39）
        }
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
            AccountStatusCard(account: account)
            AccountActionButtonRow(row: AccountDetailPresentation.actionRow(account, now: serverNow), running: running) { perform($0, on: account) }
                .disabled(running != nil || actions.isRunning(account.id))
        }
    }

    // MARK: - Actions (20 §2.4)

    private func perform(_ action: AccountDetailAction, on account: UpstreamAccount) {
        switch action {
        case .test:
            reloadsOnDismiss = true
            sheet = .legacyTest
        case .stopScheduling, .resumeScheduling:
            run(action) { await actions.setSchedulable(account, enabled: action == .resumeScheduling) }
        case .enableAccount:
            let etag = detail.etagNeedsRefresh ? nil : detail.etag
            run(action) { await actions.enableAccount(account, etag: etag) }
        case .recover: recovering = account
        case .replaceKey, .reauthorize, .webCredential: sheet = .placeholder(action)
        // S2D1-20: the old edit page holds the expiry until S2-10's 调度 section.
        case .editExpiry: sheet = .legacyEdit
        }
    }
    private func run(_ action: AccountDetailAction, _ write: @escaping @MainActor () async -> AccountActionOutcome) {
        guard running == nil else { return }
        running = action
        Task {
            _ = await write()
            running = nil
        }
    }

    // MARK: - Transitional ⋯, sheets and refresh

    private func moreMenu(_ account: UpstreamAccount) -> some View {
        Menu {
            Button("编辑账号", systemImage: "pencil") { sheet = .legacyEdit }
                .readOnlyGate(showsCaption: false)
                .accessibilityIdentifier("account.detail.more.edit")
            if account.isTokenAccount {
                Button("刷新令牌", systemImage: "arrow.clockwise") { confirmingRefresh = true }
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier("account.detail.more.refresh")
            }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("account.detail.more")
    }

    @ViewBuilder private func sheetContent(_ sheet: AccountDetailSheet) -> some View {
        if let account = detail.account {
            switch sheet {
            case .legacyTest: AccountTestView(account: account)
            case .legacyEdit: AccountEditView(initial: account) { detail.applyWrite($0) }
            case .placeholder(let action): ComingSoonSheet(title: action.title)
            }
        }
    }
    /// A test may change the account's state; the old test page reports nothing back.
    private func sheetClosed() {
        guard reloadsOnDismiss else { return }
        reloadsOnDismiss = false
        Task { await detail.load() }
    }
    /// The old detail's 刷新账号凭据 until S2-16 (`:id/refresh` has no Idempotency-Key there yet).
    private func refreshToken() async {
        guard let account = detail.account, let session, session.generation == model.sessionGeneration else { return }
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行服务器写操作。") }
            try await session.client.refreshAccount(id: account.id)
            guard session.generation == model.sessionGeneration else { return }
            model.receipts.show(Receipt(text: "已刷新令牌", systemImage: "arrow.clockwise"))
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError) else { return }
            model.receipts.show(Receipt(text: "刷新令牌没有成功：\(AccountActionCopy.reason(for: error))", systemImage: "exclamationmark.triangle",
                                        tone: .critical))
        }
        await detail.load()
    }

    // MARK: - Refresh gates (20 §2.6)

    /// Foreground, visible, nothing over the page and no write running.
    private var isRefreshOpen: Bool {
        guard visible, scenePhase == .active, !model.isSuspended, sheet == nil, recovering == nil, !confirmingRefresh, running == nil,
              !detail.isRemoved else { return false }
        return !actions.isRunning(detail.accountID)
    }
    private var countdownTarget: Date? { detail.account.flatMap { AccountDisplayState($0, now: serverNow).countdownTarget } }
    private func waitForCountdown(_ wait: AccountCountdownWait) async {
        guard wait.isOpen, let target = wait.target else { return }
        let seconds = max(0, target.timeIntervalSince(serverNow)) + 0.5
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        await detail.countdownElapsed(target: target)
    }
    /// X39: the route's section, once, when the account first shows (the sections carry the ids from S2-10 on).
    private func scrollToFocus(_ page: AccountDetailPageState, proxy: ScrollViewProxy) {
        guard case .content = page, !scrolledToFocus, let focus else { return }
        scrolledToFocus = true
        proxy.scrollTo(focus, anchor: .top)
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
