import SwiftUI
import Sub2Core

/// 00 §1.10, full screen: the document opens in Safari and the phrase must be typed exactly; “稍后” leaves it unaccepted.
/// There is no design for this page: the texts are drafted and listed for the user to review.
struct ComplianceSheet: View {
    let prompt: SecurityPromptCenter.Prompt
    @Environment(AppModel.self) private var model
    @State private var status: AdminComplianceStatus?
    @State private var loadError: String?
    @State private var phrase = ""
    @State private var error: String?
    @State private var busy = false
    @State private var document: DocumentLink?

    private var isReadOnlyToken: Bool { model.siteSession?.isReadOnlyToken == true }

    var body: some View {
        NavigationStack {
            Form {
                if let status { content(status) }
                else if let loadError {
                    Section {
                        Text(loadError).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("compliance.error")
                        Button("重试") { Task { await load() } }.frame(minHeight: 44).accessibilityIdentifier("compliance.retry")
                    }
                } else { ProgressView("正在读取合规要求…").frame(maxWidth: .infinity) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("合规确认")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { finish(.cancelled) }.disabled(busy).accessibilityIdentifier("compliance.later")
                }
            }
            .task { await load() }
            .sheet(item: $document) { SafariView(url: $0.url).ignoresSafeArea() }
        }
    }

    @ViewBuilder private func content(_ status: AdminComplianceStatus) -> some View {
        Section {
            Text(Self.introduction(version: status.version)).accessibilityIdentifier("compliance.sheet")
            if let site = model.activeProfile?.baseURL, let url = status.documentURL(site: site) {
                Button("阅读合规文件") { document = DocumentLink(url: url) }.frame(minHeight: 44).accessibilityIdentifier("compliance.read")
            } else {
                Text("请在 Web 后台查看合规文件").foregroundStyle(Palette.ink2)
            }
        }
        Section {
            Text(status.ackPhraseZH ?? "—").textSelection(.enabled).accessibilityIdentifier("compliance.ack")
            TextField("逐字输入上面的确认语句", text: $phrase, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .disabled(busy || isReadOnlyToken).accessibilityIdentifier("compliance.phrase")
        } header: { Text("确认语句") } footer: {
            if let note = footnote { Text(note) }
        }
        Section {
            Button { Task { await submit(status) } } label: { Text("确认").frame(maxWidth: .infinity, minHeight: 44) }
                .disabled(busy || isReadOnlyToken || !status.phraseMatches(phrase)).accessibilityIdentifier("compliance.confirm")
            if busy { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("compliance.error") }
        }
    }
    /// 00 §1.10: a read-only token cannot accept; an Admin Key accepts as the first administrator.
    private var footnote: String? {
        if isReadOnlyToken { return AdminComplianceStatus.acceptFailureMessage(for: APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")) }
        guard model.siteSession?.authMethod == .adminAPIKey else { return nil }
        return model.siteSession?.identityEmail.map { "将以第一个管理员（\($0)）身份确认" } ?? "将以第一个管理员身份确认"
    }

    private func load() async {
        loadError = nil
        do {
            let loaded = try await model.loadComplianceStatus()
            guard loaded.required != false else {
                // Accepted elsewhere in the meantime (another device or the Web).
                try? await model.reloadSiteSession()
                finish(.passed); return
            }
            status = loaded
        } catch is CancellationError {
        } catch { loadError = error.localizedDescription }
    }
    private func submit(_ status: AdminComplianceStatus) async {
        guard !busy, status.phraseMatches(phrase) else { return }
        busy = true; defer { busy = false }
        do { try await model.submitCompliance(phrase: phrase, prompt: prompt) }
        catch is CancellationError {
        } catch { self.error = AdminComplianceStatus.acceptFailureMessage(for: error) }
    }
    private func finish(_ outcome: SecurityPromptOutcome) { model.securityPrompts.complete(prompt.id, outcome: outcome) }

    static func introduction(version: String?) -> String {
        let document = version.flatMap { $0.isEmpty ? nil : "《Sub2API 部署与运营合规承诺》（版本 \($0)）" } ?? "《Sub2API 部署与运营合规承诺》"
        return "站点要求管理员先阅读并确认\(document)，确认前其他管理功能暂不可用。"
    }
}

private struct DocumentLink: Identifiable {
    let url: URL
    var id: URL { url }
}
