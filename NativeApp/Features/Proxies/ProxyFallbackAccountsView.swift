import SwiftUI
import Sub2Core

/// 60 §13.4 被改走的账号 (H03), titled with the proxy's name below: the accounts its expiry moved to a direct connection or a
/// backup, each pushing its account. “全部恢复到 hk-01” at the bottom and 恢复 on a row's swipe are confirmed first and offered
/// only while the proxy is active and unexpired (greyed with “先续期并启用这个代理” otherwise); both are hidden for a read-only
/// token or a vendor without `proxy_manage` and `account_manage`. Reads on entry, on pull and back in the foreground, never polls.
struct ProxyFallbackAccountsView: View {
    let proxyID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var page: ProxyFallbackAccountsModel?
    @State private var pageGeneration: UUID?
    @State private var confirming: ProxyFallbackScope?

    init(proxyID: Int) { self.proxyID = proxyID }

    private var canWrite: Bool {
        session.map { ProxyAccess.canRevertFallback(me: $0.site.me, isReadOnlyToken: $0.isReadOnlyToken) } ?? false
    }
    private var subtitle: String { page?.proxyName ?? ProxyFallbackPresentation.proxyName(model.proxyStore?.proxy(id: proxyID), id: proxyID) }

    var body: some View {
        content
            .navigationTitle(ProxyFallbackPresentation.title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            // 00 §4.6 (D18): back in the foreground the page reads again, as a pull would.
            .onChange(of: model.foregroundRevision) { _, _ in Task { await page?.load() } }
            .alert(Text(confirmTitle), isPresented: isConfirming, presenting: confirming) { scope in
                Button(ProxyFallbackPresentation.revertAction) { confirm(scope) }
                Button(ProxyFallbackPresentation.cancelAction, role: .cancel) {}
            } message: { scope in
                Text(ProxyFallbackPresentation.confirmMessage(scope, exitIP: page?.proxy?.ipAddress))
            }
    }

    @ViewBuilder private var content: some View {
        if let page, page.isUnsupported {
            ContentUnavailableView(ProxyFallbackPresentation.unsupportedTitle, systemImage: "clock.arrow.circlepath")
                .accessibilityElement(children: .combine).accessibilityIdentifier("proxy.fallback.unsupported")
        } else if let page, page.isGone {
            ContentUnavailableView(ProxyDetailCopy.gone, systemImage: "trash")
                .accessibilityElement(children: .combine).accessibilityIdentifier("proxy.fallback.gone")
        } else if let page {
            switch page.accounts.display {
            case .placeholder, .disabled: loading
            case .failed(let reason):
                FailureView(message: reason ?? "") { Task { await page.load() } }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("proxy.fallback.failure")
            case .value(let rows, _, _, let updateFailed): list(rows, page: page, updateFailed: updateFailed)
            }
        } else {
            loading
        }
    }

    private var loading: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("proxy.fallback.loading")
    }

    private func list(_ rows: [ProxyFallbackAccount], page: ProxyFallbackAccountsModel, updateFailed: Bool) -> some View {
        let writes = canWrite
        return List {
            if !page.failures.isEmpty { failuresSection(page.failures) }
            if updateFailed {
                Button(ProxyFallbackPresentation.reloadFailed) { Task { await page.load() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("proxy.fallback.reload")
            }
            if rows.isEmpty {
                ContentUnavailableView(ProxyFallbackPresentation.emptyTitle, systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("proxy.fallback.empty")
            } else {
                Section {
                    ForEach(rows) { row($0, offersRevert: writes && page.canRevert && page.running == nil) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await page.load() }
        .accessibilityIdentifier("proxy.fallback.list")
        .safeAreaInset(edge: .bottom) {
            if writes, !rows.isEmpty { revertAllBar(page) }
        }
    }

    private func row(_ account: ProxyFallbackAccount, offersRevert: Bool) -> some View {
        NavigationLink(value: AppRoute.account(id: account.id, focus: .proxy)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ProxyFallbackPresentation.rowName(account)).font(.body).foregroundStyle(Palette.ink1).lineLimit(1)
                Text(ProxyFallbackPresentation.rowDetail(account)).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("proxy.fallback.row.\(account.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if offersRevert {
                Button { confirming = .account(account.id) } label: {
                    Label(ProxyFallbackPresentation.revertAction, systemImage: "arrow.uturn.backward")
                }
                .tint(Palette.accentFill)
                .accessibilityIdentifier("proxy.fallback.row.\(account.id).revert")
            }
        }
    }

    private func failuresSection(_ failures: [ProxyFallbackFailureLine]) -> some View {
        Section(ProxyFallbackPresentation.failuresTitle) {
            ForEach(failures) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name).font(.body).foregroundStyle(Palette.ink1).lineLimit(1)
                    Text(line.reason).font(.footnote).foregroundStyle(line.tone.base)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("proxy.fallback.failure.\(line.id)")
            }
        }
    }

    /// 全部恢复到 <name>: greyed with its reason while the proxy cannot take the accounts back; a spinner while it runs.
    private func revertAllBar(_ page: ProxyFallbackAccountsModel) -> some View {
        VStack(spacing: 6) {
            Button { confirming = .all } label: {
                Group {
                    if page.running == .all {
                        Label { Text(ProxyFallbackPresentation.running) } icon: { ProgressView() }
                    } else {
                        Text(ProxyFallbackPresentation.revertAllTitle(proxyName: page.proxyName))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(!page.canRevert || page.running != nil)
            .accessibilityIdentifier("proxy.fallback.revertAll")
            if !page.canRevert {
                Text(page.proxy == nil ? ProxyFallbackPresentation.proxyUnavailableNote : ProxyFallbackPresentation.blockedNote)
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("proxy.fallback.revertAll.note")
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { model.receipts.setBottomClearance($0 + 8) }
        .onDisappear { model.receipts.setBottomClearance(0) }
    }

    // MARK: - Confirmation

    private var confirmTitle: String {
        guard let confirming, let page else { return "" }
        let rows = page.accounts.value ?? []
        var accountName: String?
        if case .account(let id) = confirming { accountName = rows.first { $0.id == id }.map(ProxyFallbackPresentation.rowName) }
        return ProxyFallbackPresentation.confirmTitle(confirming, count: rows.count, accountName: accountName, proxyName: page.proxyName)
    }
    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }
    private func confirm(_ scope: ProxyFallbackScope) {
        guard let page else { return }
        Task { await page.revert(scope) }
    }

    // MARK: - Session

    /// A new session gets a new page; coming back (from an account) reads again only what leaving cancelled.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let page, pageGeneration == session.generation {
            if page.accounts.value == nil { await page.load() }
            return
        }
        let generation = session.generation, client = session.client
        let store = model.proxyStore.flatMap { $0.generation == generation ? $0 : nil }
        // Under -ui-testing the proxy rows are this session's FixtureProxySource, shared with the list and the detail (S6D1-12).
        let endpoints = model.isUITesting ? DemoData.proxyFallbackEndpoints(model: model) : .live(client)
        let created = ProxyFallbackAccountsModel(proxyID: proxyID, seed: store?.proxy(id: proxyID), isSupported: session.has(.proxiesFallbackAccounts),
                                                 endpoints: endpoints, store: store, accountSignal: model.accountListSignal, receipts: model.receipts,
                                                 authorize: { [weak model] in await model?.biometricGate.authorize($0) ?? false },
                                                 isCurrent: { [weak model] in model?.sessionGeneration == generation },
                                                 now: { client.serverClock.now() },
                                                 afterRevert: { [proxyID] in ProxyFallbackSignal.post(proxyID: proxyID, generation: generation) })
        page = created
        pageGeneration = generation
        await created.load()
    }
}
