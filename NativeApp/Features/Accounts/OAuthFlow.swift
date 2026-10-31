import SwiftUI
import Sub2Core
import UIKit
import UniformTypeIdentifiers

/// 20 §6.3 / §7.3 三步清单 (design AeReauthSheet, AnOAuthList), shared by 重新授权 and 新建账号 (S2-19): ① the method (Claude
/// OAuth / Setup Token, a new Gemini account's Google One / Code Assist), 生成授权链接, the link with 复制链接 / 打开 and its 30
/// minutes; ② signing in; ③ the code or the callback link. An error shows under its step with its remedies; the owner handles
/// the ones that are not about the link (`remedy`) and puts its own controls after step 3 (`accessory`). With
/// `listensForCallback` a loopback link is answered by the App while Safari shows it.
struct OAuthFlow<Accessory: View>: View {
    let model: OAuthFlowModel
    let platformName: String
    let proxyName: String?
    let listensForCallback: Bool
    let remedy: (AccountOAuthErrorCopy.Remedy) -> (() -> Void)?
    let accessory: Accessory
    @State private var browser: OAuthBrowserPage?
    @State private var listener = OAuthCallbackListener()
    @State private var copiedAt: Date?

    init(model: OAuthFlowModel, platformName: String, proxyName: String?, listensForCallback: Bool,
         remedy: @escaping (AccountOAuthErrorCopy.Remedy) -> (() -> Void)? = { _ in nil }, @ViewBuilder accessory: () -> Accessory) {
        self.model = model; self.platformName = platformName; self.proxyName = proxyName; self.listensForCallback = listensForCallback
        self.remedy = remedy; self.accessory = accessory()
    }

    var body: some View {
        // The countdown, the expiry and “已复制” follow the clock.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = model.now, error = model.shownError(at: model.now)
            VStack(alignment: .leading, spacing: 0) {
                OAuthStepRow(number: 1, mark: mark(.link), title: title(.link), detail: model.link == nil ? OAuthFlowCopy.lifetimeNote : nil, id: "oauth.step.link") {
                    linkStep(now: now)
                    errorBlock(error, at: .link)
                }
                OAuthStepRow(number: 2, mark: mark(.browser), title: title(.browser),
                             detail: OAuthFlowCopy.browserNote(delivery: model.codeDelivery, listening: listens), id: "oauth.step.browser") {
                    errorBlock(error, at: .browser)
                }
                OAuthStepRow(number: 3, mark: mark(.code), title: title(.code), detail: nil, id: "oauth.step.code") {
                    OAuthCodeField(model: model)
                    errorBlock(error, at: .code)
                }
                accessory
            }
        }
        .sheet(item: $browser, onDismiss: { listener.stop() }) { page in SafariView(url: page.url).ignoresSafeArea() }
        .onDisappear { listener.stop() }
    }

    private var listens: Bool { listensForCallback && model.loopback != nil }
    private func title(_ step: OAuthFlowStep) -> String {
        OAuthFlowCopy.title(step, variant: model.variant, platform: model.platform, platformName: platformName, delivery: model.codeDelivery)
    }
    private func mark(_ step: OAuthFlowStep) -> OAuthStepMark {
        step < model.stage ? .done : step == model.stage ? .current : .upcoming
    }

    // MARK: ① 授权链接

    @ViewBuilder private func linkStep(now: ContinuousClock.Instant) -> some View {
        if model.platform == .anthropic { OAuthClaudeMethod(model: model) }
        if model.choosesGeminiType, model.platform == .gemini { OAuthGeminiType(model: model) }
        if let link = model.link {
            Text(link.authURL.absoluteString)
                .font(.footnote.monospaced()).foregroundStyle(Palette.ink1)
                .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                .accessibilityIdentifier("oauth.link")
            if let seconds = model.remainingSeconds(at: now), !model.isExpired(at: now) {
                Text(OAuthFlowCopy.remaining(seconds)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("oauth.countdown")
                if let proxyName {
                    Text(OAuthFlowCopy.proxyHint(proxyName: proxyName)).font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("oauth.proxyHint")
                }
                linkButtons(link)
            }
        } else {
            Button { Task { await model.generate() } } label: {
                HStack(spacing: 6) {
                    if model.phase == .generating { ProgressView() }
                    Text(model.phase == .generating ? OAuthFlowCopy.generating : OAuthFlowCopy.generate)
                }
                .frame(minHeight: 30)
            }
            .buttonStyle(.borderedProminent).tint(Palette.accentFill)
            .disabled(!model.canGenerate)
            .accessibilityIdentifier("oauth.generate")
            .readOnlyGate()
        }
    }
    private func linkButtons(_ link: OAuthLink) -> some View {
        let copied = copiedAt.map { Date().timeIntervalSince($0) < 1.8 } ?? false
        return HStack(spacing: 10) {
            Button { copy(link) } label: {
                Label(copied ? OAuthFlowCopy.copied : OAuthFlowCopy.copyLink, systemImage: copied ? "checkmark" : "doc.on.doc").frame(minHeight: 30)
            }
            .accessibilityIdentifier("oauth.copy")
            Button { open(link) } label: { Label(OAuthFlowCopy.open, systemImage: "safari").frame(minHeight: 30) }
                .accessibilityIdentifier("oauth.open")
        }
        .buttonStyle(.bordered)
    }
    /// The link carries state and the PKCE challenge, not the verifier: it may reach a computer on the same proxy (20 §6.3), so it
    /// is not kept to this phone, and it leaves the clipboard when it expires.
    private func copy(_ link: OAuthLink) {
        let left = model.remainingSeconds(at: model.now) ?? 0
        UIPasteboard.general.setItems([[UTType.plainText.identifier: link.authURL.absoluteString]],
                                      options: [.expirationDate: Date().addingTimeInterval(max(1, left))])
        copiedAt = Date()
    }
    private func open(_ link: OAuthLink) {
        guard link.authURL.scheme?.lowercased() == "https" else { return }
        if listensForCallback, let endpoint = model.loopback {
            let model = model
            listener.start(endpoint, onCallback: { url in
                model.receiveCallback(url)
                browser = nil
            }, onFailure: { model.noteListenFailed() })
        }
        browser = OAuthBrowserPage(url: link.authURL)
    }

    // MARK: Errors

    @ViewBuilder private func errorBlock(_ error: AccountOAuthErrorCopy?, at step: OAuthFlowStep) -> some View {
        if let error, error.step == step {
            OAuthStepError(copy: error, step: step, actions: error.remedies.compactMap { remedy in action(for: remedy, at: step).map { (remedy, $0) } })
        }
    }
    /// The link's own remedies happen here; the rest belong to the owner.
    private func action(for remedy: AccountOAuthErrorCopy.Remedy, at step: OAuthFlowStep) -> (() -> Void)? {
        switch remedy {
        case .regenerateLink:
            return { model.restart(); Task { await model.generate() } }
        case .reopenLink:
            guard let link = model.link, !model.isExpired(at: model.now) else { return nil }
            return { open(link) }
        case .retry where step == .link:
            return { Task { await model.generate() } }
        default:
            return self.remedy(remedy)
        }
    }
}

extension OAuthFlow where Accessory == EmptyView {
    init(model: OAuthFlowModel, platformName: String, proxyName: String?, listensForCallback: Bool,
         remedy: @escaping (AccountOAuthErrorCopy.Remedy) -> (() -> Void)? = { _ in nil }) {
        self.init(model: model, platformName: platformName, proxyName: proxyName, listensForCallback: listensForCallback, remedy: remedy) { EmptyView() }
    }
}

private struct OAuthBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

private enum OAuthStepMark { case done, current, upcoming }

/// One numbered step: a check once it is done, the number otherwise; the current one in the accent colour.
private struct OAuthStepRow<Content: View>: View {
    let number: Int
    let mark: OAuthStepMark
    let title: String
    let detail: String?
    let id: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(mark == .upcoming ? Palette.sunken : Palette.accentFill)
                if mark == .done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Palette.onAccent)
                } else {
                    Text("\(number)").font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(mark == .current ? Palette.onAccent : Palette.ink2)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(mark == .upcoming ? Palette.ink2 : Palette.ink1)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true) }
                }
                .accessibilityElement(children: .combine)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// Claude's method (OAuth / Setup Token) and its scope; another method drops the link and the code (20 §6.3).
private struct OAuthClaudeMethod: View {
    let model: OAuthFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("授权方式", selection: Binding(get: { model.kind }, set: { model.selectKind($0) })) {
                ForEach(OAuthAuthKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)
            .accessibilityIdentifier("oauth.method")
            Text(OAuthFlowCopy.claudeScope(model.kind, original: model.originalKind))
                .font(.footnote).foregroundStyle(model.typeSwitchTarget == nil ? Palette.ink2 : Tone.caution.ink)
                .accessibilityIdentifier("oauth.scope")
        }
    }
}

/// A new Gemini account's type (20 §7.3): Google One, or Code Assist with its GCP Project ID.
private struct OAuthGeminiType: View {
    let model: OAuthFlowModel
    private static let types: [GeminiOAuthType] = [.googleOne, .codeAssist]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("授权类型", selection: Binding(get: { model.request.geminiOAuthType }, set: { model.selectGeminiType($0) })) {
                ForEach(Self.types, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)
            .accessibilityIdentifier("oauth.gemini.type")
            if model.request.geminiOAuthType == .codeAssist {
                TextField("GCP Project ID", text: Binding(get: { model.request.projectID ?? "" }, set: { model.setProjectID($0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("oauth.gemini.project")
            }
        }
    }
}

/// ③: the code or the callback link, typed or pasted (PasteButton asks no permission); greyed until a link exists.
private struct OAuthCodeField: View {
    let model: OAuthFlowModel

    var body: some View {
        let delivery = model.codeDelivery, enabled = model.link != nil && !model.isBusy
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(OAuthFlowCopy.codeLabel(delivery), text: Binding(get: { model.code }, set: { model.setCode($0) }),
                          prompt: Text(OAuthFlowCopy.codePlaceholder(delivery)))
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(nil).privacySensitive()
                    .disabled(!enabled)
                    .accessibilityLabel(OAuthFlowCopy.codeLabel(delivery))
                    .accessibilityIdentifier("oauth.code")
                if model.code.isEmpty {
                    PasteButton(payloadType: String.self) { @Sendable pasted in
                        guard let text = pasted.first else { return }
                        Task { @MainActor in model.setCode(text) }
                    }
                    .labelStyle(.titleOnly).buttonBorderShape(.capsule)
                    .disabled(!enabled)
                    .accessibilityIdentifier("oauth.code.paste")
                } else {
                    Button(OAuthFlowCopy.clear) { model.setCode("") }
                        .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("oauth.code.clear")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
            .opacity(model.link == nil ? 0.55 : 1)
            if let hint {
                Text(hint).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("oauth.code.hint")
            }
        }
    }
    private var hint: String? {
        if model.receivedAutomatically, case .callback(let address) = model.codeDelivery { return OAuthFlowCopy.autoReceived(address: address) }
        if model.recognizesLink { return OAuthFlowCopy.recognized }
        if model.listenFailed, model.code.isEmpty { return OAuthFlowCopy.listenFailedHint }
        return nil
    }
}

/// Red text under its step and the buttons that fix it (20 §6.5).
private struct OAuthStepError: View {
    let copy: AccountOAuthErrorCopy
    let step: OAuthFlowStep
    let actions: [(AccountOAuthErrorCopy.Remedy, () -> Void)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "xmark.octagon.fill").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.message).font(.footnote.weight(.semibold))
                    if let detail = copy.detail { Text(detail).font(.footnote) }
                }
            }
            .foregroundStyle(Tone.critical.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("oauth.error.\(Self.name(step))")
            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(actions, id: \.0) { remedy, perform in
                        Button(remedy.title, action: perform)
                            .buttonStyle(.bordered).frame(minHeight: 44)
                            .accessibilityIdentifier("oauth.error.\(remedy.rawValue)")
                    }
                }
            }
        }
    }
    private static func name(_ step: OAuthFlowStep) -> String {
        switch step {
        case .link: "link"
        case .browser: "browser"
        case .code: "code"
        }
    }
}
