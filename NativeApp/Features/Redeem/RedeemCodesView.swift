import SwiftUI
import Sub2Core

/// 60 §8: the redeem code list. “兑换码” with “<站点名> · N 个”, + on the right (hidden for a read-only token, C-1), the search
/// field, the pending batch banner (11.3), the status chips and type menu or the same-batch chip, then the cards by day.
/// RedeemCodesModel decides when to read; this view reports appearing, pulls, the foreground and compliance.
struct RedeemCodesView: View {
    let route: RedeemRouteState
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @State private var list: RedeemCodesModel?
    /// S6-05: this list's 禁用 / 启用、删除 and edit sheet saves.
    @State private var writes: RedeemCodeWrites?

    private var canGenerate: Bool { session.map { !$0.isReadOnlyToken } ?? false }

    var body: some View {
        content
            .navigationTitle(RedeemListText.title)
            .navigationSubtitle(RedeemListText.subtitle(siteName: model.activeProfile?.name ?? "", total: list?.siteTotal))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canGenerate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(RedeemListText.generateTitle, systemImage: "plus", action: generate).accessibilityIdentifier("redeem.generate")
                    }
                }
            }
            .task(id: session?.generation) { await appeared() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .task(id: list?.refresh.notBefore) { await retryAfterWait() }
            .onDisappear { list?.disappeared() }
            // A read stopped by the background is read again on return (D18); a list refused while compliance was pending reads
            // again once it is accepted (00 §1.10).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await list?.foregroundResumed() } }
            .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await list?.markNeedsReload() } }
    }

    @ViewBuilder private var content: some View {
        if let list, let writes {
            RedeemListContent(list: list, writes: writes, canGenerate: canGenerate, onGenerate: generate)
        } else {
            ProgressView(RedeemListText.loading).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("redeem.loading")
        }
    }

    /// The + interception and the wizard are S6-07's.
    private func generate() { router.present(.redeemGenerate) }

    /// A new session gets a new list (and forgets the route's code to open); then it reads unless what it shows is recent.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if list?.generation != session.generation {
            let generation = session.generation
            list = RedeemCodesModel(session: session, source: model.redeemCodesSource(for: session),
                                    route: model.isUITesting ? route.applyingFixtureArguments() : route, receipts: model.receipts,
                                    isCurrent: { [weak model] in model?.sessionGeneration == generation })
            let writes = model.redeemCodeWrites(for: session)
            writes.host = list
            self.writes = writes
        }
        await list?.appeared()
    }
    /// “请求过于频繁，N 秒后自动重试”: once the wait is over, a shown list reads again (00 §2.7.2).
    private func retryAfterWait() async {
        guard let list, let notBefore = list.refresh.notBefore else { return }
        let wait = notBefore.timeIntervalSinceNow
        if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
        // Not part of this task: page 1 clearing the wait restarts it, which must not stop the counts or the located code.
        Task { await list.markNeedsReload() }
    }
}

private struct RedeemListContent: View {
    @Bindable var list: RedeemCodesModel
    let writes: RedeemCodeWrites
    let canGenerate: Bool
    let onGenerate: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    /// S6-05: the edit sheet opens on the card as listed (60 §9.6); the delete confirmation is the shared one (S3-00).
    @State private var editing: AdminRedeemCode?
    @State private var deleteRequest: DeleteRequest?
    /// After the expand animation, so the open card is measured at its full height.
    private static let revealDelay: Duration = .milliseconds(350)

    var body: some View {
        ScrollViewReader { proxy in
            List {
                RedeemPendingBannerSection(highlighted: list.highlightsBanner)
                filterSection
                listBody
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .onChange(of: list.revealRequest) { _, request in
                guard let id = request.id else { return }
                Task {
                    try? await Task.sleep(for: Self.revealDelay)
                    withAnimation { proxy.scrollTo(id) }
                }
            }
        }
        .searchable(text: $list.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: RedeemListText.searchPrompt)
        .task(id: list.searchText) {
            do { try await Task.sleep(for: RedeemListPolicy.searchDebounce) } catch { return }
            // Not part of this task: typing on must not stop the read a search started (a newer search drops its reply instead).
            Task { await list.applySearch() }
        }
        .refreshable { await list.pullToRefresh() }
        .accessibilityIdentifier("redeem.list")
        .sheet(item: $editing) { RedeemEditSheet(code: $0, writes: writes) }
        .confirmDelete($deleteRequest)
    }

    // MARK: Filters

    private var filterSection: some View {
        Section {
            Group {
                if let batch = list.filter.batch {
                    RedeemBatchChipButton(chip: batch, total: list.batchTotal) { Task { await list.clearBatch() } }
                } else {
                    RedeemChipsBar(status: list.filter.status, type: list.filter.type, stats: list.stats,
                                   onStatus: { status in Task { await list.select(status: status) } },
                                   onType: { type in Task { await list.select(type: type) } })
                }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Rows and states

    @ViewBuilder private var listBody: some View {
        switch list.state.display {
        case .placeholder:
            Section { ForEach(0..<3, id: \.self) { _ in RedeemCodeCardSkeleton() } }
        case .failed(let reason):
            Section {
                FailureView(message: list.throttleMessage() ?? reason ?? "", retry: retry)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("redeem.failure")
            }
            .listRowBackground(Color.clear)
        case .value(let page, _, _, let updateFailed):
            if updateFailed { refreshFailedBanner }
            if let pinned = list.pinned {
                Section { card(pinned) } header: { Text(RedeemListText.locatedHeader) }
            }
            ForEach(RedeemListLayout.sections(page.codes, now: clock, timeZone: zone.timeZone)) { section in
                ForEach(Array(section.codes.enumerated()), id: \.element.id) { index, code in
                    Section {
                        card(code)
                    } header: {
                        if index == 0 { sectionHeader(section) }
                    }
                }
            }
            if let empty = list.empty, list.pinned == nil { emptyState(empty) }
            nextPageFooter
        case .disabled:
            EmptyView()
        }
    }

    private var clock: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    private func card(_ code: AdminRedeemCode) -> some View {
        RedeemCodeCard(code: code, isOpen: list.openID == code.id, now: clock, timeZone: zone,
                       groupName: code.groupID.flatMap { model.groupDirectory?.name(for: $0) }, readOnly: session?.isReadOnlyToken ?? true,
                       onToggle: { withAnimation(.snappy) { list.toggle(code.id) } }, onCopy: { copy(code) },
                       onOpenUser: { router.push(.user(id: $0)) }, onShowBatch: { Task { await list.showBatch(of: code) } },
                       isRunning: writes.isRunning(code.id), onAction: { perform($0, on: code) }, onDelete: { confirmDelete(code) })
            .id(code.id)
            .onAppear { Task { await list.loadMoreIfNeeded(after: code.id) } }
    }

    private func sectionHeader(_ section: RedeemListSection) -> some View {
        HStack {
            Text(section.title)
            Spacer()
            Text(section.countText).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("redeem.section.\(section.title)")
    }

    /// 60 §8.4: 禁用 / 启用 at once (with 撤销); 编辑, 编辑备注 and 续期 open the sheet.
    private func perform(_ action: RedeemCardAction, on code: AdminRedeemCode) {
        switch action {
        case .disable, .enable: Task { await writes.toggleStatus(code) }
        case .edit, .editNotes, .renew: editing = code
        case .more: break
        }
    }
    /// 60 §0.4 / §8.4: the last 4 characters in either case, or Face ID; the confirmation shows only “····d4e8”.
    private func confirmDelete(_ code: AdminRedeemCode) {
        let writes = self.writes
        deleteRequest = DeleteRequest(objectNoun: RedeemEditCopy.objectNoun, displayName: RedeemPresentation.deleteSubject(code.code),
                                      siteName: model.activeProfile?.name ?? "", consequences: [RedeemEditCopy.deleteConsequence(code)],
                                      expectedText: code.code, match: .suffix(4)) { await writes.delete(code) }
    }

    /// 60 §0.4: this phone only, never Handoff; the code itself is never logged or shown in the receipt.
    private func copy(_ code: AdminRedeemCode) {
        SensitivePasteboard.copy(code.code)
        model.receipts.show(Receipt(text: RedeemListText.copiedReceipt, systemImage: "doc.on.doc"))
    }

    @ViewBuilder private var nextPageFooter: some View {
        switch list.nextPage {
        case .loading:
            Section { ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("redeem.more.loading") }
                .listRowBackground(Color.clear)
        case .failed:
            Section {
                Button(RedeemListText.loadMoreFailed) { Task { await list.retryMore() } }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("redeem.more.retry")
            }
        case .idle where list.offersLoadMore:
            Section {
                Button(RedeemListText.loadMore) { Task { await list.loadMore() } }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("redeem.more.load")
            }
        case .idle:
            EmptyView()
        }
    }

    /// 00 §4.6: a failed refresh keeps the cards; tapping reads again (not during a 429 wait).
    private var refreshFailedBanner: some View {
        let detail = list.throttleMessage()
        return Section {
            Button { Task { await list.reloadFirstPageAndStats() } } label: {
                StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: "刷新失败 · 重试", detail: detail)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(list.state.isLoading || detail != nil)
            .accessibilityLabel(["刷新失败 · 重试", detail].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("redeem.refresh.retry")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    /// 60 §8.5: no code at all offers 生成兑换码 (not to a read-only token); a filter without rows says so, and a search can be
    /// cleared.
    @ViewBuilder private func emptyState(_ empty: RedeemListEmpty) -> some View {
        Section {
            if empty == .noCodes {
                ContentUnavailableView {
                    Label(empty.title, systemImage: "gift").accessibilityIdentifier("redeem.empty")
                } actions: {
                    if canGenerate {
                        Button(RedeemListText.generateTitle, action: onGenerate).buttonStyle(.borderedProminent).frame(minHeight: 44)
                            .accessibilityIdentifier("redeem.empty.generate")
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text(DisplayFormat.missing).font(.title.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                    Text(empty.title).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                        .accessibilityIdentifier("redeem.filter.empty")
                    if case .noSearchMatch = empty {
                        Button(RedeemListText.clearSearch) { list.searchText = "" }
                            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("redeem.search.clear")
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .listRowBackground(Color.clear)
    }

    /// No retry during a 429 wait; the page reads again on its own when it ends.
    private var retry: (() -> Void)? {
        guard list.throttleMessage() == nil else { return nil }
        return { Task { await list.reloadFirstPageAndStats() } }
    }
}

/// 60 §8.3 状态胶囊 and 类型: counts follow the search and the type (names only without them); the type menu is a picker.
private struct RedeemChipsBar: View {
    let status: RedeemCodeStatus?
    let type: RedeemCodeType?
    let stats: RedeemCodeStats?
    let onStatus: @MainActor (RedeemCodeStatus?) -> Void
    let onType: @MainActor (RedeemCodeType?) -> Void
    private static let statuses: [RedeemCodeStatus?] = [nil] + RedeemCodeStatus.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.statuses, id: \.self) { item in
                    Button { onStatus(item) } label: {
                        RedeemChipLabel(title: item?.label ?? "全部", count: stats?.count(item), isOn: status == item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RedeemPresentation.statusChipTitle(item, stats: stats))
                    .accessibilityAddTraits(status == item ? .isSelected : [])
                    .accessibilityIdentifier("redeem.chip.\(item?.rawValue ?? "all")")
                }
                typeMenu
            }
            .padding(.horizontal, 16)
        }
    }

    private var typeMenu: some View {
        Menu {
            Picker(RedeemPresentation.typeChipTitle(nil), selection: Binding(get: { type }, set: { onType($0) })) {
                Text(RedeemPresentation.allTypesTitle).tag(RedeemCodeType?.none)
                ForEach(RedeemCodeType.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
        } label: {
            RedeemChipLabel(title: RedeemPresentation.typeChipTitle(type), count: nil, isOn: type != nil, trailingSymbol: "chevron.down")
        }
        .accessibilityLabel(RedeemPresentation.typeChipTitle(type))
        .accessibilityIdentifier("redeem.type")
    }
}

/// U49: “同一批 · 20 个 ✕”; tapping removes it and brings the earlier filter back.
private struct RedeemBatchChipButton: View {
    let chip: RedeemBatchChip
    let total: Int?
    let onRemove: () -> Void

    /// Laid out like the chips it replaces, so only the capsule takes the tap.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onRemove) {
                    RedeemChipLabel(title: chip.title(total: total), count: nil, isOn: true, trailingSymbol: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.removeLabel(total: total))
                .accessibilityIdentifier("redeem.batch")
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Design `.chip`: 34pt capsule, sunken when off, accent wash and edge when on.
private struct RedeemChipLabel: View {
    let title: String
    let count: Int?
    let isOn: Bool
    var trailingSymbol: String?
    @ScaledMetric(relativeTo: .subheadline) private var size = 14.5
    @ScaledMetric(relativeTo: .footnote) private var countSize = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var height = 34.0

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: size))
            if let count {
                Text(DisplayFormat.grouped(count)).font(.system(size: countSize, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink2)
            }
            if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: countSize * 0.85, weight: .bold)) }
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

/// 60 §11.3 and X34: the earliest batch of this address awaiting its result, with “等 N 批” for more; an older login's batch says
/// so. It shows and leaves with the records; 核对 opens the reconciliation sheet (S6-06) for the current identity. From the
/// overview (`reconcile: true`) the button is the primary one.
private struct RedeemPendingBannerSection: View {
    let highlighted: Bool
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session

    var body: some View {
        if let serverID = session?.serverID, banner(serverID: serverID, now: Date()) != nil {
            Section {
                // The start time reads “N 分钟前”.
                TimelineView(.everyMinute) { context in
                    if let banner = banner(serverID: serverID, now: context.date) { row(banner) }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
    }

    private func banner(serverID: UUID, now: Date) -> RedeemPendingBanner? {
        RedeemPendingBanner.make(records: model.pendingMoneyWrites(sameAddressAs: serverID), currentServerID: serverID,
                                 sameAddress: model.sameAddressServerIDs(), now: now, timeZone: session?.site.serverTimeZone.timeZone ?? .current)
    }

    private func row(_ banner: RedeemPendingBanner) -> some View {
        StatusBanner(tone: .caution, systemImage: "doc.text.magnifyingglass", title: banner.title, detail: banner.amountLine + "\n" + banner.timeLine) {
            checkButton(banner)
        }
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tone.caution.base, lineWidth: 2) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("redeem.pending.banner")
    }

    @ViewBuilder private func checkButton(_ banner: RedeemPendingBanner) -> some View {
        let button = Button("核对") { router.present(.redeemReconcile(batchID: banner.batchID)) }
        Group {
            if highlighted { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        }
        .frame(minHeight: 44)
        .accessibilityValue(highlighted ? "primary" : "")
        .accessibilityIdentifier("redeem.pending.check")
    }
}
