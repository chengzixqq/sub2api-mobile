import SwiftUI
import Sub2Core

// The account test page before 20 §4 rewrites it, moved from AccountsView.swift (S2-04) and reading the S2-13 stream and wording;
// the new detail (S2-08) opens it from 测试连接 until S2-14, which deletes this file and moves accountWriteFailure, which
// AccountEditView still calls.

func accountWriteFailure(_ error: any Error) -> String {
    // Compliance, step-up and read-only refusals come before the handler; the global sheet already answered them.
    if let api = error as? APIError, SecurityInterruption(api) != nil { return "尚未执行：\(api.localizedDescription)" }
    if let api = error as? APIError, let status = api.statusCode, (400..<500).contains(status), status != 408 {
        if status == 409 { return "服务器拒绝：账号或分组存在冲突，请核对配置；未自动覆盖混合渠道限制。" }
        return "服务器拒绝：\(api.localizedDescription)"
    }
    return "结果不明：\(error.localizedDescription) 请先刷新核对，未自动重试。"
}

struct AccountTestView: View {
    let account: UpstreamAccount
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var modelName = ""
    @State private var lines: [String] = []
    @State private var running = false
    @State private var outcome: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("测试目标") {
                    LabeledValue(label: "站点", value: model.activeProfile?.name ?? "")
                    LabeledValue(label: "账号", value: account.name)
                    TextField("模型（可选，使用后端默认值）", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("测试会向上游发起实际请求，可能产生费用。").font(.footnote).foregroundStyle(.secondary)
                    Button(running ? "正在测试…" : "确认并开始测试") { start() }.disabled(running).frame(minHeight: 44).accessibilityIdentifier("account.test.start")
                }
                if let outcome { Section("结果") { Text(outcome).textSelection(.enabled) } }
                if !lines.isEmpty { Section("流式输出") { Text(lines.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
            }
            .navigationTitle("手动测试")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(running ? "停止并关闭" : "关闭") { task?.cancel(); dismiss() } } }
            .onDisappear { task?.cancel() }
        }
    }
    private func start() {
        guard !running else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        guard let client = session?.client else { return }
        let expectsTestResult = session?.has(.accountsTestResult) == true
        running = true; lines = []; outcome = nil
        task = Task {
            defer { running = false }
            do {
                guard generation == model.sessionGeneration else { return }
                guard !model.isUITesting else { throw AppFailure("界面测试模式不会发起上游测试。") }
                let stream = try await client.testAccount(id: account.id, model: modelName, expectsTestResult: expectsTestResult)
                var transcript = AccountTestTranscript(startedAt: ContinuousClock.now)
                for try await event in stream {
                    guard generation == model.sessionGeneration, !Task.isCancelled else { return }
                    transcript.apply(event, at: ContinuousClock.now)
                    lines = transcript.displayLines
                }
                guard generation == model.sessionGeneration, !Task.isCancelled else { return }
                transcript.finish(at: ContinuousClock.now)
                lines = transcript.displayLines
                outcome = Self.summary(transcript, account: account)
            } catch {
                guard generation == model.sessionGeneration else { return }
                // A compliance or step-up refusal was answered in the global sheet; the text says whether to start again.
                if !(error is CancellationError) { outcome = error.localizedDescription }
            }
        }
    }

    /// 20 §4.3 wording; an old server's verdict comes from test_complete / error alone (S2-14 adds the before/after comparison).
    private static func summary(_ transcript: AccountTestTranscript, account: UpstreamAccount) -> String {
        let credential = AccountTestPresentation.CredentialKind(accountType: account.type)
        let outcome = transcript.serverOutcome
            ?? AccountTestOutcome(passed: transcript.legacyPassed ?? false, timing: transcript.localTiming, errorText: transcript.errorText)
        return [AccountTestPresentation.headline(outcome), AccountTestPresentation.recoveryNote(outcome)?.text,
                AccountTestPresentation.failureNote(outcome, credential: credential), AccountTestPresentation.usageText(outcome)]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
