import SwiftUI
import Sub2Core

/// 40 §7 请求详情, pushed as `.request` by the log rows (with their row), the account detail's 最近上游错误 (the id only) and, from
/// stage 6, the request-ID search. The three looks share one page: the head card and, for the failed ones, the button row, then
/// 耗时, 上游尝试, Token, 关联 and 标识 numbered as they appear (RequestDetailLayout). RequestDetailModel decides what to read; this
/// page reads on entry, on pull, back in the foreground and after compliance passed, never on a timer (D18).
/// Identifiers: logs.detail (the list), logs.detail.loading, .gone, .back, .page.failure / .page.retry, .opsDisabled, .detailNotice,
/// .detail.failure / .detail.retry; the card's, the buttons' and 标识's below; the other sections' in RequestDetailSections.swift.
struct RequestDetailView: View {
    let route: RequestRoute
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session

    init(route: RequestRoute) { self.route = route }

    var body: some View {
        Group {
            if let session {
                RequestDetailScreen(make: { makeModel(session) }, timeZone: session.site.serverTimeZone.timeZone).id(session.generation)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(RequestDetailPresentation.title(kind: route.errorKind))
        .navigationBarTitleDisplayMode(.inline)
        // S4-08b：导航栏 ··· 菜单（复制请求 ID / 上游请求 ID）接在这里。
    }

    /// Ops off as LiveOpsStore has it, admin/me's until then (S4D2a-17); its outcomes go back to the store (S1D1-02).
    private func makeModel(_ session: SessionContext) -> RequestDetailModel {
        let model = model, client = session.client, generation = session.generation
        let settingOff = session.site.me.features.opsMonitoringEnabled == false
        return RequestDetailModel(route: route, source: .app(model, session: session, row: route.initialErrorRow),
                                  attemptsSupported: session.has(.opsRequestAttempts),
                                  isOpsEnabled: { [weak model] in !(model?.liveOps?.opsDisabled ?? settingOff) },
                                  isCurrent: { [weak model] in model?.sessionGeneration == generation },
                                  onOpsResponse: { [weak model] error in await model?.liveOps?.recordOpsResponse(error) },
                                  now: { client.serverClock.now() })
    }
}

extension RequestDetailSource {
    /// S4D2a-08: the site's reads, or LogFixtures+Detail under `-ui-testing`; the page and S4-08b's flow both come here.
    @MainActor static func app(_ model: AppModel, session: SessionContext, row: RequestErrorRecord?) -> RequestDetailSource {
        guard model.isUITesting else { return .live(session.client, site: session.site) }
        return LogFixtures.requestDetailSource(arguments: ProcessInfo.processInfo.arguments, row: row)
    }
}

private struct RequestDetailScreen: View {
    @State private var detail: RequestDetailModel
    /// The reason the shown values were read for; coming back from a pushed page reads nothing new.
    @State private var loadedKey: ReloadKey?
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let timeZone: TimeZone
    private static let cardInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)

    init(make: () -> RequestDetailModel, timeZone: TimeZone) {
        _detail = State(initialValue: make())
        self.timeZone = timeZone
    }

    private struct ReloadKey: Hashable { let foreground, compliance: Int }
    private var reloadKey: ReloadKey {
        ReloadKey(foreground: model.foregroundRevision, compliance: model.securityPrompts.complianceRevision)
    }

    var body: some View {
        content
            .navigationSubtitle(subtitle)
            .task(id: reloadKey) {
                let key = reloadKey
                guard key != loadedKey || !detail.hasLoaded else { return }
                loadedKey = key
                await detail.load()
            }
    }

    @ViewBuilder private var content: some View {
        switch detail.page {
        case .loading:
            ProgressView(RequestDetailCopy.loading).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("logs.detail.loading")
        case .gone: gone
        case .opsDisabled:
            VStack { OpsDisabledNotice(style: .emptyState, notesDataGap: true) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("logs.detail.opsDisabled")
        case .failed:
            BlockFailureRow(error: detail.pageError, refresh: detail.detailRefresh, id: "logs.detail.page") { reload() }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .content: list
        }
    }
    private var subtitle: String {
        guard let stamp = detail.usage?.createdAt ?? detail.record?.createdAt else { return "" }
        return RequestDetailPresentation.subtitle(createdAt: ServerTime.parseTimestamp(stamp), kind: detail.kind, timeZone: timeZone)
    }

    /// 40 §7.5: the page says the record is gone; 返回 leaves it.
    private var gone: some View {
        ContentUnavailableView {
            Label(RequestDetailCopy.gone, systemImage: "doc.text.magnifyingglass").accessibilityIdentifier("logs.detail.gone")
        } actions: {
            Button("返回") { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("logs.detail.back")
        }
    }

    private var list: some View {
        let sections = detail.sections
        return List {
            Section {
                headCard
                actions
            }
            .listRowBackground(Color.clear)
            .listRowInsets(Self.cardInsets)
            .listRowSeparator(.hidden)
            if detail.kind != nil, detail.detail.disabledReason != nil {
                Section {
                    Text(RequestDetailCopy.opsDisabledDetail).font(.subheadline).foregroundStyle(Palette.ink2)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("logs.detail.detailNotice")
                }
            }
            ForEach(sections, id: \.self) { section(for: $0, ordinal: RequestDetailLayout.ordinal($0, in: sections)) }
            if detail.detail.failureReason != nil {
                Section {
                    BlockFailureRow(title: RequestDetailCopy.detailFailed, error: detail.detailError, refresh: detail.detailRefresh,
                                    id: "logs.detail.detail") { reload() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .refreshable { await detail.load() }
        .accessibilityIdentifier("logs.detail")
    }

    @ViewBuilder private func section(for section: RequestDetailSection, ordinal: String?) -> some View {
        switch section {
        case .timing:
            RequestTimingSection(timing: detail.timing, method: detail.method, ordinal: ordinal,
                                 isLoading: detail.kind != nil && detail.detail.isLoading)
        case .attempts:
            RequestAttemptsSection(state: detail.attempts, rows: detail.attemptRows, meta: detail.attemptsMeta, dropped: detail.droppedNote,
                                   ordinal: ordinal)
        case .tokens:
            if let usage = detail.usage { RequestTokensSection(cells: RequestDetailLayout.tokenCells(usage), ordinal: ordinal) }
        case .links: RequestLinksSection(rows: detail.links, ordinal: ordinal)
        case .identifiers: RequestIdentifiersSection(rows: detail.identifiers, ordinal: ordinal)
        }
    }

    @ViewBuilder private var headCard: some View {
        if let usage = detail.usage {
            RequestDetailHeadCard(style: .success, line: RequestDetailPresentation.successStatusLine, cause: nil, model: usage.model,
                                  upstreamModel: RequestDetailPresentation.upstreamModel(model: usage.model, upstream: usage.upstreamModel),
                                  costs: RequestDetailPresentation.costCells(usage), followerNote: RequestDetailPresentation.followerCostNote(usage),
                                  recovery: nil, message: nil, isLoading: false)
        } else if let record = detail.record, let kind = detail.kind {
            let fetched = detail.detail.value, style = detail.style
            RequestDetailHeadCard(style: style, line: RequestDetailPresentation.errorStatusLine(record: record, kind: kind, detail: fetched,
                                                                                                clientStatusCode: detail.chain?.clientStatusCode),
                                  cause: RequestDetailPresentation.causeLine(record), model: record.model,
                                  upstreamModel: RequestDetailPresentation.upstreamModel(model: record.model, upstream: record.upstreamModel),
                                  costs: [], followerNote: nil, recovery: style == .recovered ? RequestDetailPresentation.recoveryNote(record) : nil,
                                  message: RequestDetailPresentation.errorMessage(record: record, detail: fetched), isLoading: detail.detail.isLoading)
        }
    }
    /// The failed looks only: 查看账号 when the row names an account, and who resolved it once the detail says so.
    @ViewBuilder private var actions: some View {
        if let record = detail.record, detail.kind != nil {
            let accountID = record.accountID.flatMap { $0 > 0 ? $0 : nil }
            let resolved = RequestDetailPresentation.resolvedNote(record, timeZone: timeZone)
            if accountID != nil || resolved != nil {
                RequestDetailActions(accountID: accountID, resolvedNote: resolved) { router.push(.account(id: $0)) }
            }
        }
    }
    private func reload() { Task { await detail.load() } }
}

/// 40 §7.3 头部状态卡: the status row (the failed look also draws the capsule), the cause, the model, then the success's three
/// amounts or a failure's recovery note and message (monospaced, six lines until tapped). A small spinner while the detail loads.
/// Identifiers logs.detail.card, .status, .cause, .model, .upstreamModel, .charge, .cost, .standard, .followerNote, .recovery,
/// .message, .detail.loading.
struct RequestDetailHeadCard: View {
    let style: RequestDetailStyle
    let line: RequestStatusLine
    let cause: String?
    let model: String
    let upstreamModel: String?
    let costs: [RequestCostCell]
    let followerNote: String?
    let recovery: String?
    let message: String?
    let isLoading: Bool
    @State private var isExpanded = false
    private static let costIDs = ["charge", "cost", "standard"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                status
                if let cause {
                    Text(cause).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("logs.detail.cause")
                }
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView().controlSize(.small).accessibilityLabel("正在读取详情").accessibilityIdentifier("logs.detail.detail.loading")
                }
            }
            Text(model).font(.headline).monospaced().foregroundStyle(Palette.ink1).accessibilityIdentifier("logs.detail.model")
            if let upstreamModel {
                HStack(spacing: 6) {
                    Text("上游模型").foregroundStyle(Palette.ink3)
                    Text(upstreamModel).monospaced().foregroundStyle(Palette.ink2)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("logs.detail.upstreamModel")
            }
            if !costs.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(zip(Self.costIDs, costs)), id: \.0) { id, cell in
                        RequestDetailFigure(label: cell.label, value: cell.value, id: "logs.detail." + id, isProminent: id == "charge")
                    }
                }
            }
            notes
        }
        .padding(EdgeInsets(top: 16, leading: StatusCapsuleMetrics.contentLeadingInset + 4, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .statusCapsule(tone: line.capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logs.detail.card")
    }

    /// “✓ 成功 200”, “上游失败 [429]” (the code as a badge), “⛔ 失败 504”.
    private var status: some View {
        HStack(spacing: 6) {
            switch style {
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
                Text("\(line.label) \(line.badge)").monospacedDigit().foregroundStyle(Palette.okInk)
            case .recovered:
                Text(line.label).foregroundStyle(Palette.ink1)
                ToneBadge(text: line.badge, tone: line.tone)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(line.tone.base)
                Text("\(line.label) \(line.badge)").monospacedDigit().foregroundStyle(line.tone.ink)
            }
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.label) \(DisplayFormat.spoken(line.badge))")
        .accessibilityIdentifier("logs.detail.status")
    }

    @ViewBuilder private var notes: some View {
        if let followerNote {
            Text(followerNote).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("logs.detail.followerNote")
        }
        if let recovery {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                Text(recovery)
            }
            .font(.footnote.weight(.medium)).foregroundStyle(Palette.okInk)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recovery)
            .accessibilityIdentifier("logs.detail.recovery")
        }
        if let message {
            Text(message)
                .font(.footnote).monospaced().foregroundStyle(Palette.ink1)
                .lineLimit(isExpanded ? nil : 6)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .padding(10)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(isExpanded ? "" : RequestDetailCopy.expandHint)
                .accessibilityIdentifier("logs.detail.message")
        }
    }
}

/// 40 §7.3 按钮行 of the failed looks: 查看账号 (`account_id` > 0) and the “已处理 · 人 · 时间” line. S4-08b puts 标记已处理 first.
/// Identifiers logs.detail.actions, .viewAccount, .resolvedNote.
struct RequestDetailActions: View {
    let accountID: Int?
    let resolvedNote: String?
    let openAccount: @MainActor (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // S4-08b：“标记已处理 / 已处理”插在这里（最前面）。
            if let accountID {
                Button { openAccount(accountID) } label: {
                    Label(RequestDetailCopy.viewAccount, systemImage: "server.rack").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("logs.detail.viewAccount")
            }
            if let resolvedNote {
                Text(resolvedNote).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("logs.detail.resolvedNote")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logs.detail.actions")
    }
}

/// 40 §7.3 标识: the label over the ID in monospace, selectable. S4-08b swaps the rows for RequestIdentifierCopyRow (tap to copy),
/// keeping the identifiers logs.detail.id.request / .client / .upstream.
struct RequestIdentifiersSection: View {
    let rows: [RequestIdentifierRow]
    let ordinal: String?

    var body: some View {
        Section {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label).font(.footnote).foregroundStyle(Palette.ink2)
                    Text(row.value).font(.footnote).monospaced().foregroundStyle(Palette.ink1).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("logs.detail.id." + row.kind.rawValue)
            }
        } header: {
            NumberedSectionHeader(title: RequestDetailLayout.title(.identifiers), ordinal: ordinal, id: "logs.detail.identifiers")
        }
    }
}
