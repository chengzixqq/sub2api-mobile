import SwiftUI
import Sub2Core

/// 20 §7.3 凭据, following the method (S2-18's kinds): an API Key with its Base URL; a multi-protocol mode's key and 接入 (protocol,
/// official or custom endpoint); Bedrock's SigV4 or API Key with the Region; Vertex's Service Account JSON from Files and its
/// Location; Antigravity's upstream; or the three-step authorization with the App listening on the loopback port (S2-17).
/// The values stay in the draft only.
struct AccountNewCredentialSection: View {
    @Bindable var model: AccountNewModel
    @Binding var importingVertex: Bool

    var body: some View {
        if let method = model.draft.method {
            switch method.kind {
            case .oauth: AccountNewOAuthSection(model: model)
            case .apiKey: apiKey(method)
            case .multiProtocol(let mode): multiProtocol(method, mode: mode)
            case .bedrock: bedrock(method)
            case .vertex: vertex
            case .upstream: upstream(method)
            }
        } else {
            Section("凭据") {
                Text(AccountNewCopy.credentialsPlaceholder(platformPicked: model.draft.platform != nil, isAccountMode: model.isAccountMode))
                    .foregroundStyle(Palette.ink3).frame(minHeight: 44)
                    .id(AccountNewModel.Anchor.credentials)
            }
        }
    }

    // MARK: API Key

    private func apiKey(_ method: AccountNewMethod) -> some View {
        let platform = model.draft.platform ?? ""
        return Section {
            AccountNewSecretField(title: "API Key", text: $model.draft.apiKey, placeholder: Self.keyHint(platform), identifier: "account-new.apikey")
                .id(AccountNewModel.Anchor.credentials)
            AccountNewTextRow(title: "Base URL", text: $model.draft.baseURL, prompt: AccountNewCatalog.officialBaseURL(for: platform),
                              identifier: "account-new.baseurl", monospaced: true)
            issue(.baseURL)
        } header: {
            Text("凭据")
        } footer: {
            Text(AccountNewCopy.credentialFootnote)
        }
    }

    // MARK: Multi-protocol (20 §7.2 多协议 API Key 平台)

    @ViewBuilder private func multiProtocol(_ method: AccountNewMethod, mode: MetaCatalog.Mode) -> some View {
        Section {
            AccountNewSecretField(title: "API Key", text: $model.draft.apiKey, placeholder: "sk-...", identifier: "account-new.apikey")
                .id(AccountNewModel.Anchor.credentials)
        } header: {
            Text("\(AccountProtocolEndpoints.modeTitle(mode.mode)) · 凭据")
        } footer: {
            Text(AccountNewCopy.credentialFootnote)
        }
        let current = model.draft.effectiveProtocol ?? AccountProtocolEndpoints.adaptive
        let adaptive = current == AccountProtocolEndpoints.adaptive
        Section {
            if method.protocolOptions.count > 1 {
                Picker("API 协议", selection: Binding(get: { current }, set: { model.draft.apiProtocol = $0 })) {
                    ForEach(method.protocolOptions, id: \.self) { Text(AccountProtocolEndpoints.protocolTitle($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("account-new.protocol")
            } else {
                LabeledContent("API 协议", value: AccountProtocolEndpoints.protocolTitle(current)).accessibilityIdentifier("account-new.protocol")
            }
            if adaptive {
                LabeledContent("官方端点") {
                    Text(Self.adaptiveEndpoint(method) ?? "").font(.footnote.monospaced()).multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("account-new.endpoint.official")
            } else {
                Picker("端点", selection: $model.draft.usesCustomEndpoint) {
                    Text(Self.host(method.officialEndpoint(for: current))).tag(false)
                    Text("自定义").tag(true)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("account-new.endpoint")
                if model.draft.usesCustomEndpoint {
                    AccountNewTextRow(title: "自定义端点", text: $model.draft.customEndpoint, prompt: "https://", identifier: "account-new.custom-endpoint",
                                      monospaced: true)
                    issue(.customEndpoint)
                }
            }
        } header: {
            Text("接入")
        } footer: {
            Text(adaptive ? "按入站协议优先使用供应商原生端点，没有对应端点时才转换。" : "请求都转发到这个端点；入站协议不同时由网关转换。")
        }
    }

    // MARK: Bedrock, Vertex, upstream

    @ViewBuilder private func bedrock(_ method: AccountNewMethod) -> some View {
        Section("认证方式") {
            Picker("认证方式", selection: $model.draft.bedrockAuth) {
                Text("SigV4 签名").tag(BedrockAuthMode.sigv4)
                Text("Bedrock API Key").tag(BedrockAuthMode.apikey)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account-new.bedrock.auth")
            .id(AccountNewModel.Anchor.credentials)
        }
        Section {
            if model.draft.bedrockAuth == .sigv4 {
                AccountNewTextRow(title: "AWS Access Key ID", text: $model.draft.awsAccessKeyID, prompt: "AKIA...", identifier: "account-new.bedrock.akid",
                                  monospaced: true)
                AccountNewSecretField(title: "AWS Secret Access Key", text: $model.draft.awsSecretAccessKey, placeholder: "必填",
                                      identifier: "account-new.bedrock.secret")
                AccountNewTextRow(title: "AWS Session Token", text: $model.draft.awsSessionToken, prompt: "可选", identifier: "account-new.bedrock.session",
                                  monospaced: true)
            } else {
                AccountNewSecretField(title: "Bedrock API Key", text: $model.draft.bedrockAPIKey, placeholder: "必填", identifier: "account-new.bedrock.apikey")
            }
            Picker("AWS Region", selection: $model.draft.awsRegion) {
                ForEach(AccountNewDefaults.bedrockRegions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("account-new.bedrock.region")
        } header: {
            Text("凭据")
        } footer: {
            Text(model.draft.bedrockAuth == .sigv4 ? "Session Token 可选，用于临时凭证。" : "Bearer Token 认证。")
        }
    }

    @ViewBuilder private var vertex: some View {
        Section {
            Group {
                if let file = model.draft.vertexFile {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text").font(.title3).foregroundStyle(Palette.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.fileName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                            Text("已读取 · project_id \(file.projectID)").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("account-new.vertex.selected")
                        Spacer(minLength: 8)
                        Button("重新选择") { importingVertex = true }.buttonStyle(.borderless).frame(minHeight: 44)
                            .accessibilityIdentifier("account-new.vertex.file")
                    }
                } else {
                    Button { importingVertex = true } label: {
                        Label("从“文件”选择 JSON", systemImage: "doc.badge.plus").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("account-new.vertex.file")
                }
            }
            .id(AccountNewModel.Anchor.credentials)
            if let error = model.vertexError {
                Text(error).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("account-new.vertex.error")
            }
        } header: {
            Text("Service Account JSON")
        } footer: {
            Text("密钥内容不会显示，只在创建账号时提交。")
        }
        Section {
            Picker("Location", selection: $model.draft.vertexLocation) {
                ForEach(AccountNewDefaults.vertexLocations, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("account-new.vertex.location")
        } header: {
            Text("Location")
        } footer: {
            Text("不同模型可用的 location 不同，这里选账号默认的。")
        }
    }

    private func upstream(_ method: AccountNewMethod) -> some View {
        Section {
            AccountNewTextRow(title: "上游 Base URL", text: $model.draft.upstreamBaseURL, prompt: "https://", identifier: "account-new.upstream.url",
                              monospaced: true)
                .id(AccountNewModel.Anchor.credentials)
            issue(.upstreamBaseURL)
            AccountNewSecretField(title: "上游 API Key", text: $model.draft.upstreamAPIKey, placeholder: "必填", identifier: "account-new.upstream.key")
        } header: {
            Text("上游")
        } footer: {
            Text("上游 Antigravity 服务的地址和 Key。" + AccountNewCopy.credentialFootnote)
        }
    }

    @ViewBuilder private func issue(_ field: AccountNewIssue.Field) -> some View {
        if let issue = model.draft.issues.first(where: { $0.field == field }) {
            Text(issue.message).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("account-new.issue.\(field.rawValue)")
        }
    }

    /// Design AN_KEY_HINT.
    private static func keyHint(_ platform: String) -> String {
        switch platform {
        case "anthropic": "sk-ant-api03-..."
        case "openai": "sk-proj-..."
        case "gemini": "AIza..."
        case "grok": "xai-..."
        default: "sk-..."
        }
    }
    /// 自适应 sends every native endpoint with base_url its chat one (S2-18).
    private static func adaptiveEndpoint(_ method: AccountNewMethod) -> String? {
        method.officialEndpoint(for: "chat_completions")
            ?? AccountProtocolEndpoints.nativeProtocolOrder.lazy.compactMap { method.officialEndpoint(for: $0) }.first
    }
    private static func host(_ url: String?) -> String {
        guard let url else { return "官方端点" }
        return URL(string: url)?.host() ?? url
    }
}

/// 20 §7.3 凭据 · OAuth: S2-17's three steps with 完成授权 after the code; once authorized, “已授权 · {邮箱}” (no e-mail from Gemini)
/// and 重新授权. Changing OAuth / Setup Token or Google One / Code Assist after that asks first (20 §7.4-5).
private struct AccountNewOAuthSection: View {
    let model: AccountNewModel

    var body: some View {
        let platform = model.draft.platform.flatMap(OAuthPlatform.init(accountPlatform:))
        Section {
            Group {
                if let grant = model.draft.oauthGrant { authorized(grant, platform: platform) } else if let flow = model.oauthFlow { steps(flow) }
            }
            .id(AccountNewModel.Anchor.credentials)
        } header: {
            HStack {
                Text("\(platform?.signInName ?? "") 授权")
                Spacer()
                if model.draft.oauthGrant != nil { Text("已完成") }
            }
        } footer: {
            if model.draft.oauthGrant == nil { Text("兑换令牌和之后的请求都走所选代理。") }
        }
    }

    private func steps(_ flow: OAuthFlowModel) -> some View {
        OAuthFlow(model: flow, platformName: model.platformName ?? "", proxyName: model.proxyName, listensForCallback: true,
                  remedy: { remedy(for: $0) }) {
            finishButton(flow)
        }
        .onChange(of: flow.receivedAutomatically) { _, received in
            if received { Task { await model.finishAuthorization() } }
        }
    }
    private func finishButton(_ flow: OAuthFlowModel) -> some View {
        let ready = if case .ready = flow.submission(at: flow.now) { true } else { false }
        let exchanging = flow.phase == .exchanging
        return Button { Task { await model.finishAuthorization() } } label: {
            HStack(spacing: 6) {
                if exchanging { ProgressView().tint(Palette.onAccent) }
                Text(exchanging ? "验证中…" : "完成授权")
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accentFill)
        .disabled(!ready || flow.isBusy)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityIdentifier("account-new.oauth.finish")
        .readOnlyGate()
    }
    /// The list's remedies that are this form's: 重试 exchanges again, 换个代理再试 picks a proxy and then exchanges.
    private func remedy(for remedy: AccountOAuthErrorCopy.Remedy) -> (() -> Void)? {
        let model = model
        switch remedy {
        case .retry: return { Task { await model.finishAuthorization() } }
        case .changeProxy, .pickProxy: return { model.chooseProxyForExchange() }
        default: return nil
        }
    }

    private func authorized(_ grant: AccountNewOAuthGrant, platform: OAuthPlatform?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if platform == .anthropic {
                Picker("添加方式", selection: Binding(get: { model.draft.claudeAuthKind }, set: { model.requestClaudeKind($0) })) {
                    ForEach(OAuthAuthKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("account-new.oauth.kind")
            } else if platform == .gemini {
                Picker("授权类型", selection: Binding(get: { model.draft.geminiOAuthType }, set: { model.requestGeminiType($0) })) {
                    ForEach(AccountNewDefaults.geminiOAuthTypes, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("account-new.oauth.kind")
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.ok.base).accessibilityHidden(true)
                Text(AccountNewCopy.authorized(email: grant.email)).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                    .accessibilityIdentifier("account-new.oauth.done")
                Spacer(minLength: 8)
                Button("重新授权") { model.resetAuthorization() }
                    .buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityIdentifier("account-new.oauth.reset")
            }
            if let proxy = model.proxyName { Text("代理 \(proxy)").font(.footnote).foregroundStyle(Palette.ink2) }
        }
        .padding(.vertical, 6)
    }
}

/// A secret (20 §7.3): secure until 显示, PasteButton while empty (no clipboard prompt), 清除 once filled; trimmed when the field is
/// left, and “{前缀}••••{末 4 位} · N 个字符” below (S2-15's APIKeyPreview). Its value is never logged.
struct AccountNewSecretField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let identifier: String
    @State private var isRevealed = false
    @State private var note: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let binding = $text
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Palette.ink1).fixedSize()
                Group {
                    if isRevealed {
                        TextField(title, text: $text, prompt: Text(placeholder))
                    } else {
                        SecureField(title, text: $text, prompt: Text(placeholder))
                    }
                }
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(nil).privacySensitive()
                .focused($isFocused)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
                if text.isEmpty {
                    // The paste may answer off the main thread; the value goes back to the field on it.
                    PasteButton(payloadType: String.self) { @Sendable pasted in
                        guard let value = pasted.first else { return }
                        Task { @MainActor in binding.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier(identifier + ".paste")
                } else {
                    Button { isRevealed.toggle() } label: { Image(systemName: isRevealed ? "eye.slash" : "eye").frame(width: 32, height: 44) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(isRevealed ? "隐藏" : "显示")
                        .accessibilityIdentifier(identifier + ".reveal")
                    Button { text = ""; note = nil; isRevealed = false } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 44) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.ink3)
                        .accessibilityLabel("清除")
                        .accessibilityIdentifier(identifier + ".clear")
                }
            }
            .frame(minHeight: 44)
            if let preview = APIKeyPreview(text) {
                Text([note, isRevealed ? nil : preview.masked, "\(preview.characterCount) 个字符"].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote.monospacedDigit()).foregroundStyle(Palette.ink3)
                    .accessibilityIdentifier(identifier + ".hint")
            }
        }
        .onChange(of: isFocused) { _, focused in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !focused, trimmed != text else { return }
            text = trimmed
            note = "已去掉首尾空格"
        }
    }
}
