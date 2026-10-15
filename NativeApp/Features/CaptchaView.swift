import SwiftUI
import WebKit
import Sub2Core

struct CaptchaRequest: Identifiable {
    let id = UUID()
    let server: ServerProfile
    let provider: String
}

struct CaptchaView: View {
    let request: CaptchaRequest
    let completion: (Result<CaptchaProof, Error>) -> Void
    @State private var finished = false
    var body: some View {
        NavigationStack {
            CaptchaWebView(request: request) { result in
                guard !finished else { return }; finished = true; completion(result)
            }
            .navigationTitle("站点安全验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") {
                guard !finished else { return }; finished = true; completion(.failure(AppFailure("已取消安全验证。")))
            } } }
        }
        .interactiveDismissDisabled()
    }
}

private struct CaptchaWebView: UIViewRepresentable {
    let request: CaptchaRequest
    let completion: (Result<CaptchaProof, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(request: request, completion: completion) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "sub2Captcha")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        var components = URLComponents(url: request.server.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/mobile/verify"
        components.queryItems = [URLQueryItem(name: "nonce", value: request.id.uuidString)]
        if let url = components.url { view.load(URLRequest(url: url)) }
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
        private let completion: (Result<CaptchaProof, Error>) -> Void
        private let createdAt = Date()
        private var done = false
        private var timeoutTask: Task<Void, Never>?
        init(request: CaptchaRequest, completion: @escaping (Result<CaptchaProof, Error>) -> Void) {
            self.request = request; self.completion = completion
            super.init()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                self?.finish(.failure(AppFailure("安全验证已超时，请重新开始。")))
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
        private func finish(_ result: Result<CaptchaProof, Error>) {
            guard !done else { return }; done = true; timeoutTask?.cancel(); timeoutTask = nil; completion(result)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !done, Date().timeIntervalSince(createdAt) < 180,
                  message.frameInfo.isMainFrame, sameOrigin(message.frameInfo.request.url),
                  let body = message.body as? [String: Any], JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body),
                  let result = try? CaptchaBridgeValidator.parse(data, nonce: request.id, provider: request.provider) else { return }
            switch result {
            case .cancelled: finish(.failure(AppFailure("已取消安全验证。")))
            case .proof(let proof): finish(.success(proof))
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Provider challenge frames may load off-origin; the top-level document may not.
            if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            decisionHandler(sameOrigin(navigationAction.request.url) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(AppFailure("验证码页面无法打开，请确认站点已部署 /mobile/verify。")))
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(AppFailure("验证码页面加载失败，请重试。")))
        }
    }
}
