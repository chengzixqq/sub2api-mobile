import SwiftUI
import Sub2Core

/// 50 §5 `.groupBatch` (design GvBatchScreen), pushed by a member write's 查看 with its outcome: the status card — the failures
/// on a caution capsule, or the quiet “全部完成 · …” / “已全部撤销” — 5.5's red line, 重试 n 个 · 撤销成功的 s 个, then 失败 and
/// 成功, each row opening its account. Names and states are the submit-time snapshots (the App keeps no session-wide account
/// cache); a row without one draws the stopped glyph. Retries and undos go through GroupBatchResultModel and S5-08's
/// GroupMemberWriter, which has the group list and detail read again. No polling, no pull (5.6).
struct GroupBatchResultView: View {
    let groupID: Int
    let name: String
    let outcome: GroupBatchOutcome
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View { GroupBatchResultContent(app: model, router: router, groupID: groupID, name: name, outcome: outcome) }
}

/// 5.3's row glyph, shared with S5-11's member rows: the account tab's (an 8pt dot for 正常, a 17pt symbol otherwise).
typealias GroupAccountStateGlyph = AccountStateGlyph

private struct GroupBatchResultContent: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @State private var page: GroupBatchResultModel
    private let groupID: Int
    private let name: String

    init(app: AppModel, router: AppRouter, groupID: Int, name: String, outcome: GroupBatchOutcome) {
        self.groupID = groupID; self.name = name
        _page = State(initialValue: Self.makePage(app: app, router: router, groupID: groupID, outcome: outcome))
    }

    var body: some View {
        let outcome = page.outcome
        List {
            Section { top(outcome) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            sections(outcome)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .accessibilityIdentifier("group.batch")
        .navigationTitle(GroupBatchCopy.title)
        .navigationSubtitle(GroupBatchCopy.subtitle(groupName: model.groupStore?.group(id: groupID)?.name ?? name, count: outcome.items.count))
        .navigationBarTitleDisplayMode(.inline)
        .alert(page.mixedChannelPrompt?.title ?? "", isPresented: isConfirming, presenting: page.mixedChannelPrompt) { prompt in
            Button(prompt.confirmTitle) { Task { await page.confirmMixedChannel() } }
            Button(GroupMixedChannelConfirmation.cancelTitle, role: .cancel) { page.cancelMixedChannel() }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    // MARK: - Status card and buttons (5.3, 5.5)

    private func top(_ outcome: GroupBatchOutcome) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBatchCardView(card: outcome.statusCard)
            if let line = page.failureLine {
                Text(line).font(.subheadline).foregroundStyle(Tone.critical.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("group.batch.requestFailure")
            }
            buttons
            if showsLegacyNotice {
                Text(GroupMembersLegacyExecutor.notice).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("group.batch.legacyNote")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var buttons: some View {
        let retry = page.retryCount, undo = page.undoCount
        if retry > 0 || undo > 0 {
            HStack(spacing: 10) {
                if retry > 0 {
                    GroupBatchActionButton(title: GroupBatchCopy.retryButton(retry), systemImage: "arrow.clockwise", isPrimary: true,
                                           isRunning: page.running == .retry, id: "group.batch.retry") { Task { await page.retry() } }
                }
                if undo > 0 {
                    GroupBatchActionButton(title: GroupBatchCopy.undoButton(undo), systemImage: "arrow.uturn.backward", isPrimary: false,
                                           isRunning: page.running == .undo, id: "group.batch.undo") { Task { await page.undo() } }
                }
            }
            .disabled(page.running != nil)
        }
    }

    // MARK: - 失败 and 成功 (5.3)

    @ViewBuilder private func sections(_ outcome: GroupBatchOutcome) -> some View {
        let failures = outcome.failures, successes = outcome.successes, now = serverNow
        if !failures.isEmpty {
            Section {
                let rails = RailPosition.positions(of: failures) { _ in true }
                ForEach(Array(failures.enumerated()), id: \.element.id) { index, item in row(item, rail: rails[index], now: now) }
            } header: {
                NumberedSectionHeader(title: Self.failuresTitle, ordinal: ChineseOrdinal.text(1), meta: GroupBatchCopy.failuresMeta(failures.count),
                                      id: "group.batch.section.failed")
            }
        }
        if !successes.isEmpty {
            Section {
                ForEach(successes) { row($0, rail: nil, now: now) }
            } header: {
                NumberedSectionHeader(title: Self.successesTitle, ordinal: ChineseOrdinal.text(failures.isEmpty ? 1 : 2),
                                      meta: GroupBatchCopy.successesMeta(outcome.succeededCount), id: "group.batch.section.succeeded")
            }
        }
    }

    /// The whole row is one element: the name, the result, then the reason.
    private func row(_ item: GroupBatchItem, rail: RailPosition?, now: Date) -> some View {
        Button { router.push(.account(id: item.accountID)) } label: { GroupBatchRow(item: item, now: now) }
            .buttonStyle(.plain)
            .statusCapsule(tone: item.isFailed ? .critical : nil, position: rail ?? .single)
            .accessibilityLabel(Text([item.name, item.resultLabel, item.reasonText].compactMap { $0 }.joined(separator: "，")))
            .accessibilityIdentifier("group.batch.row.\(item.accountID)")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.surface)
            .listRowSeparatorTint(Palette.hairline)
    }

    // MARK: - Words and wiring

    private static let failuresTitle = "失败"
    private static let successesTitle = "成功"

    private var isConfirming: Binding<Bool> {
        Binding(get: { page.mixedChannelPrompt != nil }, set: { if !$0 { page.cancelMixedChannel() } })
    }
    /// 0.4.4: the retries and undos go one account after another, as the picker says.
    private var showsLegacyNotice: Bool {
        guard let write = model.groupMemberWriteSession else { return false }
        return !write.usesBatch && write.allowsLegacy
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }

    /// Sends through the session's member writer, or under `-ui-testing` through GroupFixtures.batchSend; answers from another
    /// session are dropped.
    private static func makePage(app: AppModel, router: AppRouter, groupID: Int, outcome: GroupBatchOutcome) -> GroupBatchResultModel {
        let writer = GroupMemberWriter(model: app, router: router)
        let write: GroupBatchEndpoints.Send = { [writer] in await writer.send($0, to: groupID) }
        let generation = app.sessionGeneration
        return GroupBatchResultModel(outcome: outcome, endpoints: GroupBatchEndpoints(send: app.isUITesting ? GroupFixtures.batchSend(write: write) : write),
                                     receipts: app.receipts, isCurrent: { [weak app] in app?.sessionGeneration == generation })
    }
}

/// 5.3 状态卡: failures — a caution capsule, the big “f 个失败” badge, “s 个成功” on the right when there are any and the note;
/// none — the quiet card.
private struct GroupBatchCardView: View {
    let card: GroupBatchStatusCard
    @ScaledMetric(relativeTo: .subheadline) private var badgeHeight = 28.0

    var body: some View {
        Group {
            switch card {
            case .failures(let failed, let succeeded): failures(failed: failed, succeeded: succeeded)
            case .allDone(let text): quiet(text)
            case .allUndone: quiet(GroupBatchCopy.allUndone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .statusCapsule(tone: isFailures ? .caution : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group.batch.card")
    }

    private var isFailures: Bool { if case .failures = card { true } else { false } }

    private func failures(failed: Int, succeeded: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    Text(GroupBatchCopy.failedBadge(failed)).accessibilityIdentifier("group.batch.card.failed")
                }
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Tone.caution.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: badgeHeight)
                .background(Tone.caution.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 4)
                if succeeded > 0 {
                    Text(GroupBatchCopy.succeededText(succeeded)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
                        .accessibilityIdentifier("group.batch.card.succeeded")
                }
            }
            Text(GroupBatchCopy.failureNote).font(.subheadline).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("group.batch.card.note")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 16))
    }

    /// Design hero-quiet: the 正常 glyph and one line.
    private func quiet(_ text: String) -> some View {
        HStack(spacing: 10) {
            GroupAccountStateGlyph(state: .available)
            Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("group.batch.card.quiet")
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }
}

/// The glyph of the submit-time state (停用 without one), the name, the result on the right — a critical badge for a failure,
/// 已撤销 faded — and a failure's reason below.
private struct GroupBatchRow: View {
    let item: GroupBatchItem
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            GroupAccountStateGlyph(state: item.state.map { AccountDisplayState($0, now: now).state } ?? .inactive)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    result
                }
                if let reason = item.reasonText {
                    Text(reason).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 16))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var result: some View {
        if item.isFailed {
            ToneBadge(text: item.resultLabel, tone: .critical)
        } else {
            Text(item.resultLabel).font(.subheadline.weight(.semibold)).foregroundStyle(resultColor).lineLimit(1)
        }
    }
    private var resultColor: Color {
        switch item.result {
        case .succeeded(.undone): Palette.ink3
        case .succeeded(.unchanged): Palette.ink2
        default: Tone.ok.ink
        }
    }
}

/// 5.3 按钮行: equal capsules, the primary filled with the accent; the running one spins.
private struct GroupBatchActionButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let isRunning: Bool
    let id: String
    let perform: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = 46.0
    @ScaledMetric(relativeTo: .body) private var size = 15.5

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                if isRunning { ProgressView().tint(isPrimary ? Palette.onAccent : Palette.ink1) }
                else { Image(systemName: systemImage).font(.system(size: size * 0.9, weight: .semibold)) }
                Text(title).font(.system(size: size, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? Palette.onAccent : Palette.ink1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(isPrimary ? Palette.accentFill : Palette.surface, in: Capsule())
            .overlay { if !isPrimary { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || isRunning ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .readOnlyGate(showsCaption: false)
    }
}
