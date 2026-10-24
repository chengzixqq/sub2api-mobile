import SwiftUI
import WebKit
import Sub2Core

/// 00 §1.5, 60 §4.4: the site's verification page in a non-persistent web view. The result arrives once: a proof, 取消, or a
/// load failure; the sheet cannot be swiped away.
struct CaptchaView: View {
    let request: CaptchaRequest
    let completion: (CaptchaOutcome) -> Void
    @Environment(AppModel.self) private var model
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isUITesting {
                    CaptchaFixtureView(request: request) { finish($0) }
                } else {
                    CaptchaWebView(request: request) { finish($0) }
                }
            }
            .safeAreaInset(edge: .top) {
                if request.showsFallbackHint {
                    StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: LoginCopy.captchaFallbackHint)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("captcha.hint")
                }
            }
            .navigationTitle("站点安全验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { finish(.cancelled) }.accessibilityIdentifier("captcha.cancel")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish(_ outcome: CaptchaOutcome) {
        guard !finished else { return }
        finished = true
        completion(outcome)
    }
}

/// UI tests never reach a real site: the page is replaced by one button that hands back a fixture proof.
private struct CaptchaFixtureView: View {
    let request: CaptchaRequest
    let completion: (CaptchaOutcome) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("界面测试：\(request.provider) 验证页").foregroundStyle(Palette.ink2)
            Button("模拟完成验证") { completion(.proof(CaptchaProof(provider: request.provider, turnstileToken: "ui-fixture-proof"))) }
                .buttonStyle(.borderedProminent).tint(Palette.accentFill).frame(minHeight: 44)
                .accessibilityIdentifier("captcha.fixture.complete")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CaptchaWebView: UIViewRepresentable {
    let request: CaptchaRequest
    let completion: (CaptchaOutcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(request: request, completion: completion) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "sub2Captcha")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if let url = request.url { view.load(URLRequest(url: url)) }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "sub2Captcha")
        uiView.navigationDelegate = nil
        coordinator.invalidate()
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let request: CaptchaRequest
        private let completion: (CaptchaOutcome) -> Void
        private let createdAt = Date()
        private var done = false
        private var timeoutTask: Task<Void, Never>?
        init(request: CaptchaRequest, completion: @escaping (CaptchaOutcome) -> Void) {
            self.request = request; self.completion = completion
            super.init()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(CaptchaBridge.timeout)) } catch { return }
                self?.finish(.failed(LoginCopy.captchaTimeout))
            }
        }
        func invalidate() { done = true; timeoutTask?.cancel(); timeoutTask = nil }
        private func sameOrigin(_ url: URL?) -> Bool {
            guard let url, let expected = URLComponents(url: request.server.baseURL, resolvingAgainstBaseURL: false),
                  let actual = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            return actual.scheme?.lowercased() == "https" && actual.scheme?.lowercased() == expected.scheme?.lowercased()
                && actual.host?.lowercased() == expected.host?.lowercased() && (actual.port ?? 443) == (expected.port ?? 443)
                && actual.user == nil && actual.password == nil
        }
        private func finish(_ outcome: CaptchaOutcome) {
            guard !done else { return }; done = true; timeoutTask?.cancel(); timeoutTask = nil; completion(outcome)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !done, Date().timeIntervalSince(createdAt) < CaptchaBridge.timeout,
                  message.frameInfo.isMainFrame, sameOrigin(message.frameInfo.request.url),
                  let body = message.body as? [String: Any], JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body),
                  let result = try? CaptchaBridgeValidator.parse(data, nonce: request.id, provider: request.provider) else { return }
            switch result {
            case .cancelled: finish(.cancelled)
            case .proof(let proof): finish(.proof(proof))
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Provider challenge frames may load off-origin; the top-level document may not.
            if navigationAction.targetFrame?.isMainFrame == false { return .allow }
            return sameOrigin(navigationAction.request.url) ? .allow : .cancel
        }
        /// A missing page usually comes back as the SPA's 200; an error status of the page itself is a load failure.
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard navigationResponse.isForMainFrame, let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode,
                  let message = CaptchaLoadFailure.message(httpStatus: status) else { return .allow }
            finish(.failed(message))
            return .cancel
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            failed(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            failed(error)
        }
        private func failed(_ error: any Error) {
            let error = error as NSError
            guard let message = CaptchaLoadFailure.message(domain: error.domain, code: error.code) else { return }
            finish(.failed(message))
        }
    }
}
