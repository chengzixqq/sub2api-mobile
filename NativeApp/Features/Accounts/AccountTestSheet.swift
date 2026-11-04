import SwiftUI
import Sub2Core

/// 20 §4: 测试连接, from the detail's button row and the overview's error rows (.accountTest). The test starts as the sheet
/// opens, once the account, its models and the platform names are read; there is no start button. Picking a model tests again.
/// Closing the sheet leaves a running test to AccountTestCenter, which ends it in a receipt; a test already running for the
/// account is shown as it goes.
struct AccountTestSheet: View {
    let accountID: Int
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var preparation: Preparation = .loading
    @State private var models: [AccountModelOption] = []
    @State private var attempt = 0

    private enum Preparation: Equatable { case loading, failed(String), started }

    private var center: AccountTestCenter? { model.accountTests }

    var body: some View {
        NavigationStack {
            List {
                if let state = center?.state(for: accountID) { sections(state) } else { preparing }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("account.test.sheet")
            .navigationTitle("测试连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A running test goes on after the sheet closes (20 §4.4).
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
            }
        }
        .presentationDetents([.large])
        .task(id: attempt) { await open() }
        .onDisappear { center?.detach(accountID) }
    }

    // MARK: - Sections

    @ViewBuilder private func sections(_ state: AccountTestState) -> some View {
        Section {
            targetRow(state.target.name)
            modelRow(state)
        }
        Section("输出") {
            Text(state.lines.joined(separator: "\n"))
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("account.test.output")
            if state.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在测试…").font(.footnote).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account.test.running")
            }
        }
        if let result = state.content { Section { resultRows(result, state: state) } }
    }

    private func targetRow(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).foregroundStyle(Palette.ink1).accessibilityIdentifier("account.test.target")
            Text(AccountTestFlow.notice).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("account.test.notice")
        }
        .padding(.vertical, 2)
    }

    /// The model the test uses; once it has ended, another pick (or the same one) tests again.
    private func modelRow(_ state: AccountTestState) -> some View {
        Menu {
            if models.isEmpty {
                Button(AccountTestPresentation.defaultModelLabel) { restart(state, model: nil) }
            }
            ForEach(models) { option in
                Button(option.displayName) { restart(state, model: option.id) }
            }
        } label: {
            LabeledContent("模型") {
                Text(state.shownModel ?? AccountTestPresentation.defaultModelLabel)
                    .font(.system(.subheadline, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            }
            .frame(minHeight: 44)
        }
        .disabled(state.isRunning)
        .accessibilityIdentifier("account.test.model")
    }

    @ViewBuilder private func resultRows(_ result: AccountTestResultContent, state: AccountTestState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.systemImage).font(.title3).foregroundStyle(result.tone.base).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                    .accessibilityIdentifier("account.test.result.title")
                if let detail = result.detail {
                    Text(detail).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("account.test.result.detail")
                }
                if let usage = result.usage {
                    Text(usage).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).accessibilityIdentifier("account.test.result.usage")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if result.offersEnableScheduling {
                Button("启用调度") { enableScheduling(state) }
                    .buttonStyle(.bordered).tint(Palette.accent).frame(minHeight: 44)
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier("account.test.enable")
            }
        }
        .listRowBackground(result.tone.wash)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.test.result")
        if result.offersRetest {
            if case .ended(let ending, let endedAt) = state.phase, AccountTestFlow.retryWait(ending, endedAt: endedAt, now: model.serverNow()) > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    retryButton(remaining: AccountTestFlow.retryWait(ending, endedAt: endedAt, now: model.serverNow()))
                }
            } else {
                retryButton(remaining: 0)
            }
        }
    }

    private func retryButton(remaining: Int) -> some View {
        Button(AccountTestFlow.retryTitle(remainingSeconds: remaining)) { center?.retry(accountID) }
            .frame(minHeight: 44)
            .disabled(remaining > 0)
            .accessibilityIdentifier("account.test.retry")
    }

    @ViewBuilder private var preparing: some View {
        switch preparation {
        case .loading, .started:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在读取账号…").font(.footnote).foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account.test.preparing")
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.ink1)
                    .accessibilityIdentifier("account.test.prepare.failure")
                Button("重试") { attempt += 1 }.frame(minHeight: 44).accessibilityIdentifier("account.test.prepare.retry")
            }
        }
    }

    // MARK: - Actions

    /// A test already here (running, or ended while the sheet is open) is shown; otherwise the account is read and tested.
    private func open() async {
        guard let center else { return }
        if center.state(for: accountID) != nil {
            center.attach(accountID)
            if models.isEmpty { models = await Self.modelOptions(model, id: accountID) }
            return
        }
        preparation = .loading
        let app = model, id = accountID, generation = model.sessionGeneration
        async let options = Self.modelOptions(app, id: id)
        async let catalog = app.metaCatalog()
        do {
            let account = try await app.accountWithVersion(id: id).account
            let (loaded, names) = await (options, catalog)
            guard !Task.isCancelled, generation == app.sessionGeneration, let center = app.accountTests else { return }
            models = loaded
            let target = AccountTestTarget(account: account, platformName: AccountNaming.platformName(account.platform, catalog: names))
            center.start(target, model: AccountTestPresentation.defaultModel(among: loaded.map(\.id)), opener: opener)
            preparation = .started
        } catch {
            guard !Task.isCancelled, generation == app.sessionGeneration, !(error is CancellationError) else { return }
            preparation = .failed(AccountTestStartFailure.failed(error.localizedDescription).message)
        }
    }
    /// 20 §4.5: without a list the server picks the platform's default model.
    private static func modelOptions(_ app: AppModel, id: Int) async -> [AccountModelOption] {
        do { return try await app.accountModels(id: id) } catch { return [] }
    }
    private func restart(_ state: AccountTestState, model: String?) {
        center?.start(state.target, model: model, opener: opener)
    }
    /// 20 §5: the switch goes on through AccountActions, whose receipt and 撤销 outlive the sheet.
    private func enableScheduling(_ state: AccountTestState) {
        let account = state.accountAfterTest, center = center
        dismiss()
        Task { await center?.enableScheduling(account) }
    }
    /// A receipt's “查看”: the account's detail on the current tab.
    private var opener: AccountTestCenter.Opener {
        { [weak router] id in router?.showAccount(id: id) }
    }
}
