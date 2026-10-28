import SwiftUI
import Sub2Core

/// 60 §12: the proxy list. “代理” with “<站点名> · N 个”; 全部测试 and + on the right only for who may write (60 §0.3, hidden
/// rather than greyed); under 全部 the expiry banner, then the five capsules, the column header and the rows, each pushing its
/// detail. No swipe actions, no polling. The session's ProxyStore holds the catalog; this page asks it to read on appearing
/// (when older than 60 seconds), on pull, on returning to the foreground and after compliance.
struct ProxiesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @State private var selection: ProxyFilter

    init(filter: String?) { _selection = State(initialValue: ProxyFilter(routeValue: filter)) }

    private var canManage: Bool { session.map { ProxyAccess.canManage(me: $0.site.me, isReadOnlyToken: $0.isReadOnlyToken) } ?? false }
    private var subtitle: String {
        let site = model.activeProfile?.name ?? ""
        guard let catalog = model.proxyStore?.catalog else { return site }
        return "\(site) · \(catalog.count) 个"
    }

    var body: some View {
        content
            .navigationTitle("代理")
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canManage, let store = model.proxyStore {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(store.isTestingAll ? "测试中…" : "全部测试") { testAll(store) }
                            .disabled(store.isTestingAll || store.catalog?.isComplete != true || store.proxies.isEmpty)
                            .accessibilityIdentifier("proxies.testAll")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加代理", systemImage: "plus", action: add).accessibilityIdentifier("proxies.add")
                    }
                }
            }
            .task(id: session?.generation) { await model.proxyStore?.ensureFresh() }
            // A read stopped by the background reads again on return (D18); one refused while compliance was pending reads once
            // it is accepted (00 §1.10).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await model.proxyStore?.ensureFresh() } }
            .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await model.proxyStore?.ensureFresh() } }
    }

    @ViewBuilder private var content: some View {
        if let store = model.proxyStore {
            ProxyListContent(store: store, selection: $selection, canManage: canManage, onAdd: add)
        } else {
            ProgressView("正在读取代理…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("proxies.loading")
        }
    }

    /// The sheet is S6-14's.
    private func add() { router.present(.proxyEdit(id: nil)) }

    /// Runs on after leaving the page; the receipt is the App's (12.4). A session that ended meanwhile shows none.
    private func testAll(_ store: ProxyStore) {
        Task {
            guard let summary = await store.testAll() else { return }
            model.receipts.show(summary.receipt)
        }
    }
}

private struct ProxyListContent: View {
    let store: ProxyStore
    @Binding var selection: ProxyFilter
    let canManage: Bool
    let onAdd: () -> Void
    @Environment(\.sessionContext) private var session
    private static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)

    private var clock: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    var body: some View {
        List {
            switch store.state.display {
            case .placeholder:
                Section {
                    ForEach(0..<4, id: \.self) { _ in ProxyRowSkeleton().listRowInsets(Self.rowInsets).accessibilityIdentifier("proxies.loading") }
                }
            case .failed(let reason):
                Section {
                    FailureView(message: reason ?? "", retry: { Task { await store.reload() } })
                        .accessibilityElement(children: .contain).accessibilityIdentifier("proxies.failure")
                }
                .listRowBackground(Color.clear)
            case .value(let catalog, _, _, _) where catalog.isComplete && catalog.proxies.isEmpty:
                emptyState
            case .value(let catalog, _, let isRefreshing, let updateFailed):
                catalogSections(catalog, now: clock, zone: zone, isRefreshing: isRefreshing, updateFailed: updateFailed)
            case .disabled:
                EmptyView()
            }
        }
        .refreshable { await store.reload() }
        .accessibilityIdentifier("proxies.list")
    }

    @ViewBuilder private func catalogSections(_ catalog: ProxyCatalog, now: Date, zone: ServerTimeZone, isRefreshing: Bool, updateFailed: Bool) -> some View {
        if selection == .all, catalog.isComplete, let banner = ProxyPresentation.banner(catalog.proxies, now: now, timeZone: zone) {
            bannerSection(banner)
        }
        Section {
            ProxyFilterChips(chips: ProxyPresentation.chips(catalog.proxies, now: now, timeZone: zone), showsCounts: catalog.isComplete,
                             selection: $selection)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
        }
        Section {
            let rows = catalog.proxies.filter { ProxyPresentation.matches($0, filter: selection, now: now, timeZone: zone) }
            if rows.isEmpty {
                Text("没有这类代理").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("proxies.filter-empty")
            } else {
                self.rows(rows, now: now, zone: zone)
            }
            footer(isComplete: catalog.isComplete, isRefreshing: isRefreshing, updateFailed: updateFailed)
        } header: {
            HStack {
                Text("代理")
                Spacer()
                Text("延迟 / 状态")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("proxies.header")
        }
    }

    @ViewBuilder private func rows(_ proxies: [AdminProxy], now: Date, zone: ServerTimeZone) -> some View {
        let positions = RailPosition.positions(of: proxies) { ProxyPresentation.row($0, now: now, timeZone: zone).tone?.drawsRail == true }
        ForEach(Array(proxies.enumerated()), id: \.element.id) { index, proxy in
            let row = ProxyRow(proxy: proxy, now: now, timeZone: zone, isTesting: store.testing.contains(proxy.id), railPosition: positions[index])
            NavigationLink(value: AppRoute.proxyDetail(id: proxy.id)) { row }
                .accessibilityLabel(Text(row.spokenLabel))
                .accessibilityIdentifier("proxy.row.\(proxy.id)")
                .listRowInsets(Self.rowInsets)
        }
    }

    /// 12.5: pages still loading show a spinner; a failed read keeps the rows above and offers to read everything again.
    @ViewBuilder private func footer(isComplete: Bool, isRefreshing: Bool, updateFailed: Bool) -> some View {
        if updateFailed {
            Button("加载失败 · 重试") { Task { await store.reload() } }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("proxies.more-failure")
        } else if isRefreshing, !isComplete {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("proxies.more-loading")
        }
    }

    /// 12.3 到期横幅: “查看” switches to 已过期 or 即将到期, where the banner no longer shows.
    private func bannerSection(_ banner: ProxyBanner) -> some View {
        Section {
            StatusBanner(tone: banner.tone, systemImage: "clock.badge.exclamationmark", title: banner.title, detail: banner.detail) {
                Button(ProxyBanner.actionTitle) { selection = banner.target }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityIdentifier("proxies.banner.show")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("proxies.banner")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    /// 12.5 没有代理: 添加代理 only for who may write.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有代理", systemImage: "shield").accessibilityIdentifier("proxies.empty")
        } actions: {
            if canManage {
                Button("添加代理", action: onAdd).buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .accessibilityIdentifier("proxies.empty.add")
            }
        }
        .listRowBackground(Color.clear)
    }
}

/// 12.3 筛选胶囊: each with its count once every page is in; 已过期 carries a dot while an expired proxy is still in use.
private struct ProxyFilterChips: View {
    let chips: [ProxyFilterChip]
    let showsCounts: Bool
    @Binding var selection: ProxyFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let count = showsCounts ? chip.count : nil
                    let dot = showsCounts && chip.showsDot
                    Button { selection = chip.filter } label: {
                        ProxyChipLabel(title: chip.title, count: count, showsDot: dot, isOn: selection == chip.filter)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(count.map { "\(chip.title) \($0)" } ?? chip.title)
                    .accessibilityValue(dot ? "有代理已过期仍在用" : "")
                    .accessibilityAddTraits(selection == chip.filter ? .isSelected : [])
                    .accessibilityIdentifier("proxies.chip.\(chip.filter.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct ProxyChipLabel: View {
    let title: String
    let count: Int?
    let showsDot: Bool
    let isOn: Bool
    @ScaledMetric(relativeTo: .subheadline) private var size = 14.5
    @ScaledMetric(relativeTo: .footnote) private var countSize = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var height = 34.0
    @ScaledMetric(relativeTo: .footnote) private var dotSize = 7.0

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: size))
            if let count {
                Text(DisplayFormat.grouped(count)).font(.system(size: countSize, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink2)
            }
            if showsDot { Circle().fill(Tone.critical.base).frame(width: dotSize, height: dotSize) }
        }
        .lineLimit(1)
        .foregroundStyle(isOn ? Palette.accent : Palette.ink1)
        .padding(.horizontal, 13)
        .frame(height: height)
        .background(isOn ? Palette.accentWash : Palette.sunken, in: Capsule())
        .overlay { if isOn { Capsule().strokeBorder(Palette.accent, lineWidth: 1) } }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
