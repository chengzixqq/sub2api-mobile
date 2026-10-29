import SwiftUI
import Sub2Core

/// 60 §13: one proxy. The name with “SOCKS5 · host:port” and ··· on top; the status card with the latency block and the three
/// facts, the button row (hidden for who may not write), then 壹 有效期, 贰 使用该 IP 的账号 and 叁 连接. Pushed from the list
/// (its row shows at once), from an account's proxy row or from search (only an id: the card's placeholder first). Reads on entry,
/// on pull and back in the foreground, never polls; an address edit (H04) reads once more 5 seconds later. ProxyDetailModel
/// decides what to send.
struct ProxyDetailView: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ProxyDetailModel?
    @State private var detailGeneration: UUID?
    @State private var deleteRequest: DeleteRequest?
    @State private var block: ProxyDeleteBlock?
    /// A 409 found while the delete confirmation was open: shown once it has closed.
    @State private var pendingBlock: ProxyDeleteBlock?
    /// Set once the delete went through; the page pops when its confirmation has closed.
    @State private var popsAfterDelete = false
    private static let blockDelay: Duration = .milliseconds(600)

    init(id: Int) { self.id = id }

    private var proxy: AdminProxy? { detail?.isGone == false ? detail?.proxy : nil }
    /// 60 §0.3: the button row is hidden for a read-only token or a vendor without `proxy_manage`.
    private var canManage: Bool { session.map { ProxyAccess.canManage(me: $0.site.me, isReadOnlyToken: $0.isReadOnlyToken) } ?? false }
    /// The ··· writes: a read-only token greys them through readOnlyGate, a vendor without `proxy_manage` here.
    private var vendorMayWrite: Bool { ProxyAccess.canManage(me: session?.site.me, isReadOnlyToken: false) }
    private var hasFallbackPage: Bool { session?.has(.proxiesFallbackAccounts) == true }
    private var clock: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    var body: some View {
        content
            .navigationTitle(proxy.map(ProxyPresentation.displayName) ?? "代理")
            .navigationSubtitle(proxy.map(ProxyPresentation.addressLine) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let detail, let proxy {
                    ToolbarItem(placement: .topBarTrailing) { moreMenu(proxy, detail: detail) }
                }
            }
            .task(id: session?.generation) { await appeared() }
            // 00 §4.6 (D18): back in the foreground the proxy and its accounts are read again, as a pull would.
            .onChange(of: model.foregroundRevision) { _, _ in Task { await detail?.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .proxyAddressDidChange)) { addressChanged($0) }
            .onChange(of: model.proxyStore?.proxy(id: id)) { _, row in detail?.adopt(row) }
            .onChange(of: deleteRequest == nil) { _, closed in confirmationClosed(closed) }
            .confirmDelete($deleteRequest)
            .alert(block?.title ?? "", isPresented: isShowingBlock, presenting: block) { shown in
                if shown.offersFallbackPage(hasCapability: hasFallbackPage) {
                    Button(ProxyDetailCopy.viewFallbackAccounts) { router.push(.proxyFallbackAccounts(proxyID: id)) }
                }
                Button(ProxyDetailCopy.understood, role: .cancel) {}
            } message: { Text($0.message) }
    }

    @ViewBuilder private var content: some View {
        if let detail, detail.isGone {
            ContentUnavailableView(ProxyDetailCopy.gone, systemImage: "trash")
                .accessibilityElement(children: .combine).accessibilityIdentifier("proxy.detail.gone")
        } else if let detail {
            switch detail.detail.display {
            case .placeholder, .disabled: placeholder
            case .failed(let reason):
                FailureView(message: reason ?? "") { Task { await detail.load() } }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("proxy.detail.failure")
            case .value(let proxy, let at, _, let updateFailed):
                page(proxy, detail: detail, updatedAt: at, refreshFailed: updateFailed)
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        List {
            Section { ProxyStatusCardPlaceholder().listRowBackground(Color.clear).listRowInsets(Self.cardInsets) }
        }
        .listStyle(.insetGrouped)
    }
    private static let cardInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)

    private func page(_ proxy: AdminProxy, detail: ProxyDetailModel, updatedAt: Date?, refreshFailed: Bool) -> some View {
        let now = clock, zone = zone
        let note = ProxyPresentation.expiryNote(proxy, backupName: detail.backupName, supportsFallbackAccounts: hasFallbackPage, now: now, timeZone: zone)
        let availability = model.liveOps?.availability?.accounts
        return List {
            if refreshFailed { refreshFailedBanner(updatedAt: updatedAt, detail: detail) }
            Section {
                VStack(spacing: 12) {
                    ProxyStatusCardView(card: ProxyPresentation.statusCard(proxy, isTesting: detail.isTesting, justTestedAt: detail.justTestedAt, timeZone: zone),
                                        reading: ProxyPresentation.latency(proxy, isTesting: detail.isTesting, now: now, timeZone: zone),
                                        facts: ProxyPresentation.facts(proxy, isCheckingQuality: detail.isCheckingQuality, timeZone: zone),
                                        isReprobing: detail.isReprobing)
                    if canManage {
                        ProxyDetailActions(isExpired: proxy.status == "expired", isTesting: detail.isTesting, isBusy: detail.isBusy,
                                           onTest: { Task { await detail.test() } }, onEdit: { router.present(.proxyEdit(id: id)) })
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(Self.cardInsets)
            }
            ProxyExpirySection(proxyID: id, note: note,
                               rows: ProxyDetailRows.expiry(proxy, backupName: detail.backupName, hasNote: note != nil, now: now, timeZone: zone),
                               fallbackLink: ProxyDetailRows.fallbackLink(proxy, hasCapability: hasFallbackPage))
            ProxyAccountsSection(state: detail.accounts, detail: { ProxyDetailRows.accountDetail($0, catalog: nil) },
                                 stateOf: { ProxyAccountStateLookup.state(accountID: $0, items: availability, now: now) }, now: now,
                                 onRetry: { Task { await detail.reloadAccounts() } })
            ProxyConnectionSection(rows: ProxyDetailRows.connection(proxy, timeZone: zone))
        }
        .listStyle(.insetGrouped)
        .refreshable { await detail.load() }
        .accessibilityIdentifier("proxy.detail")
    }

    /// 00 §4.6: the older proxy stays; tapping reads again.
    private func refreshFailedBanner(updatedAt: Date?, detail: ProxyDetailModel) -> some View {
        let shown = updatedAt.map { $0.addingTimeInterval(session?.site.clockOffset ?? 0) }
        let line = shown.map { "更新于 " + DisplayFormat.clock($0, timeZone: zone.timeZone) }
        return Section {
            Button { Task { await detail.load() } } label: {
                StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: "更新失败 · 重试", detail: line)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(["更新失败 · 重试", line].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("proxy.detail.refreshFailed")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    // MARK: - ···

    /// 13.4: titled with the name and the address; 编辑代理, 复制代理 URL, 质量检测, 停用 / 启用 / 续期…, then 删除代理… in red.
    private func moreMenu(_ proxy: AdminProxy, detail: ProxyDetailModel) -> some View {
        let toggle = ProxyStatusToggle(proxy, now: clock)
        let url = ProxyPresentation.copyURL(proxy)
        return Menu {
            Section(ProxyPresentation.displayName(proxy)) {
                Text(ProxyPresentation.addressLine(proxy))
                writeItem(Button("编辑代理", systemImage: "square.and.pencil") { router.present(.proxyEdit(id: id)) }, id: "edit", detail: detail)
                Button("复制代理 URL", systemImage: "doc.on.doc") { copy(url) }
                    .disabled(url == nil).accessibilityIdentifier("proxy.more.copy")
                writeItem(Button("质量检测", systemImage: "checkmark.shield") { Task { await detail.checkQuality() } }
                    .disabled(detail.isCheckingQuality), id: "quality", detail: detail)
                writeItem(Button(toggle.menuTitle, systemImage: toggle == .disable ? "pause.circle" : "play.circle") { perform(toggle, detail: detail) },
                          id: "toggle", detail: detail)
            }
            Section {
                writeItem(Button("删除代理…", systemImage: "trash", role: .destructive) { confirmDelete(proxy, detail: detail) }, id: "delete", detail: detail)
            }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("proxy.more")
    }
    private func writeItem(_ button: some View, id: String, detail: ProxyDetailModel) -> some View {
        button.disabled(!vendorMayWrite || detail.isBusy).readOnlyGate(showsCaption: false).accessibilityIdentifier("proxy.more.\(id)")
    }

    private func perform(_ toggle: ProxyStatusToggle, detail: ProxyDetailModel) {
        guard toggle != .renew else { return router.present(.proxyEdit(id: id)) }
        Task { await detail.toggleStatus(now: clock) }
    }
    /// 60 §0.4: this phone only and gone after 120 seconds; the URL carries the password, so it is never shown or logged.
    private func copy(_ url: String?) {
        guard let url else { return }
        SensitivePasteboard.copy(url, expiresIn: SensitivePasteboard.proxyURLLifetime)
        model.receipts.show(Receipt(text: ProxyDetailCopy.copiedURL, systemImage: "doc.on.doc"))
    }
    /// 13.4: accounts on it or moved off it say why it cannot go; otherwise the whole name is typed (or Face ID).
    private func confirmDelete(_ proxy: AdminProxy, detail: ProxyDetailModel) {
        if let found = ProxyDeleteBlock.before(proxy) { block = found; return }
        deleteRequest = DeleteRequest(objectNoun: ProxyDetailCopy.objectNoun, displayName: ProxyPresentation.displayName(proxy),
                                      siteName: model.activeProfile?.name ?? "") {
            switch await detail.delete() {
            case .deleted: popsAfterDelete = true
            case .blocked(let found): pendingBlock = found
            case .failed, .unconfirmed, .ignored: break
            }
        }
    }
    /// The confirmation has closed: pop after a delete, or show the box a 409 asked for once the sheet is out of the way.
    private func confirmationClosed(_ closed: Bool) {
        guard closed else { return }
        if popsAfterDelete {
            popsAfterDelete = false
            return dismiss()
        }
        guard let found = pendingBlock else { return }
        pendingBlock = nil
        Task {
            try? await Task.sleep(for: Self.blockDelay)
            block = found
        }
    }
    private var isShowingBlock: Binding<Bool> {
        Binding(get: { block != nil }, set: { if !$0 { block = nil } })
    }

    // MARK: - Session

    /// A new session gets a new model; coming back (from an account) reads again only what leaving cancelled.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let detail, detailGeneration == session.generation {
            if detail.proxy == nil || detail.accounts.value == nil { await detail.load() }
            return
        }
        let generation = session.generation
        let store = model.proxyStore.flatMap { $0.generation == generation ? $0 : nil }
        // Under -ui-testing the catalog's source is this session's FixtureProxySource, shared with the list (S6D1-12).
        let source = (store?.source as? any ProxyDetailSource) ?? ClientProxySource(client: session.client)
        let created = ProxyDetailModel(id: id, seed: store?.proxy(id: id), source: source, store: store, receipts: model.receipts,
                                       isCurrent: { [weak model] in model?.sessionGeneration == generation })
        detail = created
        detailGeneration = generation
        await created.load()
    }
    /// H04 (C-34): only this proxy in this session.
    private func addressChanged(_ notification: Notification) {
        guard let change = ProxyAddressSignal.change(in: notification), change.proxyID == id, change.generation == model.sessionGeneration,
              let detail else { return }
        Task { await detail.beginAddressReprobe() }
    }
}
