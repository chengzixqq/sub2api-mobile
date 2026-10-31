import SwiftUI
import Sub2Core

// 20 §9 定时测试（只读, S2-21）: 记录's last row and the small page it opens. Plans are created and edited only in the Web.

/// “定时测试”, then the plan's summary on the right (nothing while the first read is out), into the small page.
struct AccountScheduledTestsRow: View {
    let accountID: Int
    let summary: ScheduledTestSummary?

    var body: some View {
        NavigationLink(value: AppRoute.accountScheduledTests(accountID: accountID)) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.ink3).frame(width: 22)
                Text("定时测试").foregroundStyle(Palette.ink1).layoutPriority(1)
                Spacer(minLength: 8)
                if let summary {
                    cronLed(summary.text, rawCron: summary.monospacedPrefix)
                        .font(.subheadline).monospacedDigit().foregroundStyle(summary.tone?.ink ?? Palette.ink2)
                        .multilineTextAlignment(.trailing).lineLimit(2)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("定时测试"))
        .accessibilityValue(Text(summary.map { DisplayFormat.spoken($0.text) } ?? ""))
        .accessibilityIdentifier("account.records.scheduledTests")
    }
}

/// The primary plan and its newest 20 results, pulled to refresh; “在 Web 中编辑计划” goes through S2-11's openAccountInWeb.
struct AccountScheduledTestsView: View {
    let accountID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.openURL) private var openURL
    @State private var load = LoadState<AccountScheduledTestsSnapshot>()
    /// For the Web link's search and copy; without it the link carries only the id.
    @State private var accountName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
                webLink
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
        }
        .background(Palette.canvas)
        .navigationTitle("定时测试")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if case .idle = load.state { await reload() } }
        .task { await readName() }
        .onChange(of: model.foregroundRevision) { _, _ in Task { await reload() } }
    }

    @ViewBuilder private var content: some View {
        switch load.state.display {
        case .placeholder:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160).accessibilityIdentifier("account.scheduledTests.loading")
        case .failed, .disabled:
            failure
        case .value(let snapshot, _, _, let updateFailed):
            if updateFailed { retryLine("更新失败 · 重试") }
            loaded(snapshot)
        }
    }

    @ViewBuilder private func loaded(_ snapshot: AccountScheduledTestsSnapshot) -> some View {
        if let plan = snapshot.primaryPlan {
            AccountDetailSectionBox(title: "最近结果", ordinal: "", id: "account.scheduledTests.header") {
                planLine(plan)
                Divider().overlay(Palette.hairline)
                results(snapshot.results)
            }
            if let note = ScheduledTestsPresentation.otherPlansNote(snapshot) { footnote(note, id: "account.scheduledTests.otherPlans") }
        } else {
            ContentUnavailableView("没有定时测试计划", systemImage: "clock.arrow.circlepath", description: Text("计划在 Web 中添加"))
                .frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("account.scheduledTests.empty")
        }
    }

    private func planLine(_ plan: ScheduledTestPlan) -> some View {
        let text = ScheduledTestsPresentation.planText(plan)
        let cron = ScheduledTestsPresentation.cronText(plan.cronExpression)
        return cronLed(text, rawCron: cron.isRaw ? cron.text : nil)
            .font(.subheadline.weight(.semibold)).foregroundStyle(plan.enabled ? Palette.ink1 : Palette.ink3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel(Text(text))
            .accessibilityIdentifier("account.scheduledTests.plan")
    }

    @ViewBuilder private func results(_ results: AccountScheduledTestsSnapshot.Results) -> some View {
        switch results {
        case .loaded(let items) where !items.isEmpty:
            let timeZone = session?.site.serverTimeZone.timeZone ?? .current
            let rows = items.map { ScheduledTestsPresentation.resultRow($0, timeZone: timeZone) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    AccountScheduledTestResultLine(row: row)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account.scheduledTests.list")
        case .loaded, .notRequested:
            footnote("还没有测试结果", id: "account.scheduledTests.noResults").padding(.vertical, 8)
        case .unavailable:
            footnote("没有权限查看测试结果，在 Web 中查看", id: "account.scheduledTests.unavailable").padding(.vertical, 8)
        }
    }

    /// 20 §9.5: a failed read (a vendor's other-workspace account included, 404 ACCOUNT_NOT_FOUND) says so and offers 重试.
    private var failure: some View {
        ContentUnavailableView {
            Label("读取失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(load.error ?? "")
        } actions: {
            Button("重试") { Task { await reload() } }
                .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("account.scheduledTests.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.scheduledTests.failure")
    }

    private func retryLine(_ text: String) -> some View {
        Button { Task { await reload() } } label: {
            Text(text).font(.subheadline).foregroundStyle(Palette.accent).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.scheduledTests.retry")
    }

    /// The Web's deep link opens the account's edit dialog; its plans are under that account's “定时测试” menu item.
    private var webLink: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.openAccountInWeb(id: accountID, name: accountName, using: openURL) } label: {
                Label("在 Web 中编辑计划", systemImage: "safari").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("account.scheduledTests.web")
            footnote("计划在 Web 账号操作菜单的“定时测试”中新建与编辑。", id: "account.scheduledTests.webNote")
        }
        .padding(.top, 6)
    }

    private func footnote(_ text: String, id: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }

    private func reload() async {
        let model = model, id = accountID, generation = model.sessionGeneration
        await load.load(isCurrent: { model.sessionGeneration == generation }) {
            try await model.accountScheduledTests(accountID: id, resultLimit: ScheduledTestsPresentation.resultLimit)
        }
    }
    private func readName() async {
        guard accountName == nil else { return }
        accountName = (try? await model.account(id: accountID))?.name
    }
}

/// HH:MM, then “成功 · 1.3s”, or the status badge and the kind word; read as one line.
private struct AccountScheduledTestResultLine: View {
    let row: ScheduledTestResultRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(isSuccess ? Tone.ok.base : Tone.critical.base).frame(width: 22)
            Text(row.time).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
            switch row.outcome {
            case .success:
                Text(row.text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
            case .failure(let badge, let tone, let word):
                ToneBadge(text: badge, tone: tone)
                Text(word).font(.subheadline).foregroundStyle(Palette.ink1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spokenText))
        .accessibilityIdentifier("account.scheduledTests.result.\(row.id)")
    }

    private var isSuccess: Bool {
        if case .success = row.outcome { true } else { false }
    }
}

/// `text` with its leading raw cron set monospaced (20 §9.3 “其余原样等宽”).
private func cronLed(_ text: String, rawCron: String?) -> Text {
    guard let rawCron, text.hasPrefix(rawCron) else { return Text(text) }
    return Text("\(Text(rawCron).monospaced())\(String(text.dropFirst(rawCron.count)))")
}
