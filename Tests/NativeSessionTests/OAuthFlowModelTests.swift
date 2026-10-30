import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private func flowAccount(platform: String = "anthropic", type: String = "oauth", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":2,"name":"Claude-官方-02","platform":"\#(platform)","type":"\#(type)","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}

/// Hands out links on a clock the test moves; records each request with its generation. Waits at `gate` when one is set.
@MainActor final class FakeOAuthLinkSource: OAuthLinkSource {
    var oauthSession: AccountOAuthSession? = AccountOAuthSession(generation: UUID(), reauthorizeEndpoint: true, errorReasons: true,
                                                                 isReadOnlyToken: false)
    private(set) var requests: [OAuthLinkRequest] = []
    private(set) var generations: [UUID] = []
    /// The next links' auth_url and state; an empty list answers a link without a redirect.
    var replies: [Result<(url: String, state: String?), any Error>] = []
    var gate: SessionGate?
    var now: ContinuousClock.Instant = .now

    func generateOAuthLink(_ request: OAuthLinkRequest, generation: UUID) async throws -> OAuthLink {
        requests.append(request); generations.append(generation)
        let number = requests.count
        if let gate { await gate.wait() }
        let reply = replies.isEmpty ? .success((url: "https://auth.example.invalid/authorize", state: nil)) : replies.removeFirst()
        let (url, state) = try reply.get()
        return OAuthLink(request: request, authURL: URL(string: url)!, sessionID: "sess-\(number)", state: state,
                         lifetime: OAuthLinkLifetime(generatedAt: now))
    }
}

@MainActor private func reauthFlow(_ account: UpstreamAccount, _ source: FakeOAuthLinkSource) throws -> OAuthFlowModel {
    let flow = OAuthFlowModel.reauthorize(account, source: source, now: { source.now })
    return try #require(flow)
}
private func redirect(_ address: String, state: String? = nil) -> String {
    let encoded = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? address
    return "https://auth.example.invalid/authorize?redirect_uri=\(encoded)" + (state.map { "&state=\($0)" } ?? "")
}

@MainActor @Test func claudeKindPreselectedFromAccountType() throws {
    let source = FakeOAuthLinkSource()
    let setup = try reauthFlow(try flowAccount(type: "setup-token"), source)
    #expect(setup.kind == .setupToken && setup.typeSwitchTarget == nil && setup.variant == .reauthorize)
    #expect(try reauthFlow(try flowAccount(), source).kind == .oauth)
    let openAI = try reauthFlow(try flowAccount(platform: "openai"), source)
    #expect(openAI.platform == .openai && openAI.originalKind == nil)
    #expect(OAuthFlowModel.reauthorize(try flowAccount(platform: "kiro"), source: source) == nil)
}

@MainActor @Test func generateSendsPlatformKindProxyAndAccount() async throws {
    let source = FakeOAuthLinkSource()
    let claude = try reauthFlow(try flowAccount(#""proxy_id":7"#), source)
    await claude.generate()
    #expect(source.requests.last?.platform == .anthropic && source.requests.last?.kind == .oauth && source.requests.last?.proxyID == 7)
    #expect(source.generations.last == source.oauthSession?.generation)
    #expect(claude.phase == .ready && claude.link?.sessionID == "sess-1" && !claude.isBusy)
    claude.selectKind(.setupToken)
    await claude.generate()
    #expect(source.requests.last?.kind == .setupToken)
    await (try reauthFlow(try flowAccount(platform: "openai"), source)).generate()
    #expect(source.requests.last?.proxyID == nil)
    await (try reauthFlow(try flowAccount(platform: "grok"), source)).generate()
    #expect(source.requests.last?.accountID == 2)
    let gemini = try reauthFlow(try flowAccount(platform: "gemini", #""credentials":{"oauth_type":"google_one","tier_id":"google_one_free"}"#), source)
    await gemini.generate()
    #expect(source.requests.last?.geminiOAuthType == .googleOne && source.requests.last?.tierID == "google_one_free")
    await (try reauthFlow(try flowAccount(platform: "gemini"), source)).generate()
    #expect(source.requests.last?.geminiOAuthType == .codeAssist)
}

@MainActor @Test func generatingIsBusyUntilTheLinkArrives() async throws {
    let source = FakeOAuthLinkSource()
    let gate = SessionGate()
    source.gate = gate
    let flow = try reauthFlow(try flowAccount(), source)
    let task = Task { await flow.generate() }
    while await !gate.arrived { await Task.yield() }
    #expect(flow.isBusy && flow.phase == .generating && !flow.canGenerate)
    await gate.open()
    await task.value
    #expect(!flow.isBusy && flow.stage == .browser)
}

@MainActor @Test func changingClaudeKindDropsLinkAndCode() async throws {
    let flow = try reauthFlow(try flowAccount(), FakeOAuthLinkSource())
    await flow.generate()
    flow.setCode("abc#s")
    #expect(flow.stage == .code)
    flow.selectKind(.oauth)
    #expect(flow.link != nil && flow.code == "abc#s")
    flow.selectKind(.setupToken)
    #expect(flow.link == nil && flow.code.isEmpty && flow.error == nil && flow.stage == .link)
    #expect(flow.typeSwitchTarget == .setupToken)
    flow.selectKind(.oauth)
    #expect(flow.typeSwitchTarget == nil)
}

@MainActor @Test func staleGenerateResultIsDropped() async throws {
    let source = FakeOAuthLinkSource()
    let gate = SessionGate()
    source.gate = gate
    let flow = try reauthFlow(try flowAccount(), source)
    let task = Task { await flow.generate() }
    while await !gate.arrived { await Task.yield() }
    flow.selectKind(.setupToken)
    await gate.open()
    await task.value
    #expect(flow.link == nil && flow.phase == .idle)
    await flow.generate()
    #expect(flow.link?.sessionID == "sess-2" && flow.link?.request.kind == .setupToken)
}

@MainActor @Test func linkExpiresAfterThirtyMinutesOnMonotonicClock() async throws {
    let source = FakeOAuthLinkSource()
    let flow = try reauthFlow(try flowAccount(), source)
    let start = source.now
    await flow.generate()
    flow.setCode("Kp7v#U5oT")
    #expect(flow.remainingSeconds(at: start) == 1_800 && flow.remainingSeconds(at: start + .seconds(1_799)) == 1)
    #expect(!flow.isExpired(at: start + .seconds(1_799)))
    #expect(flow.shownError(at: start + .seconds(1_799)) == nil)
    let late = start + .seconds(1_800)
    #expect(flow.isExpired(at: late) && flow.submission(at: late) == .expired)
    #expect(flow.shownError(at: late) == AccountOAuthErrorCopy.linkExpired)
    flow.restart()
    #expect(flow.link == nil && flow.error == nil && flow.shownError(at: late) == nil && flow.code.isEmpty)
}

@MainActor @Test func claudeSubmissionKeepsHashState() async throws {
    let source = FakeOAuthLinkSource()
    let flow = try reauthFlow(try flowAccount(#""proxy_id":3"#), source)
    #expect(flow.submission(at: source.now) == .notReady)
    await flow.generate()
    #expect(flow.submission(at: source.now) == .notReady)
    flow.setCode("  Kp7v#U5oT \n")
    guard case .ready(let submission) = flow.submission(at: source.now) else { Issue.record("not ready"); return }
    #expect(submission.code == OAuthCode(value: "Kp7v#U5oT") && submission.code.state == nil)
    #expect(submission.link.request.kind == .oauth && submission.proxyID == 3)
}

@MainActor @Test func callbackPlatformTakesStateFromURLThenLink() async throws {
    let source = FakeOAuthLinkSource()
    source.replies = [.success((url: redirect("http://localhost:1455/auth/callback", state: "s1"), state: "s1"))]
    let openAI = try reauthFlow(try flowAccount(platform: "openai"), source)
    await openAI.generate()
    #expect(openAI.codeDelivery == .callback(address: "localhost:1455"))
    openAI.setCode("http://localhost:1455/auth/callback?code=c1&state=s9")
    guard case .ready(let pasted) = openAI.submission(at: source.now) else { Issue.record("not ready"); return }
    #expect(pasted.code.value == "c1" && pasted.code.state == "s9" && openAI.recognizesLink)
    openAI.setCode("c1")
    guard case .ready(let bare) = openAI.submission(at: source.now) else { Issue.record("not ready"); return }
    #expect(bare.code.state == nil && bare.link.state == "s1" && !openAI.recognizesLink)
    openAI.setCode("http://localhost:1455/auth/callback?state=s9")
    #expect(openAI.submission(at: source.now) == .notReady)
}

@MainActor @Test func geminiDeliveryFollowsTheRedirect() async throws {
    let source = FakeOAuthLinkSource()
    source.replies = [.success((url: redirect("https://codeassist.example.invalid/authcode"), state: "g7")),
                      .success((url: redirect("http://localhost:1455/auth/callback"), state: "g8"))]
    let codeAssist = try reauthFlow(try flowAccount(platform: "gemini"), source)
    #expect(codeAssist.codeDelivery == .displayedCode)
    await codeAssist.generate()
    #expect(codeAssist.codeDelivery == .displayedCode && codeAssist.loopback == nil)
    codeAssist.setCode("4/0AVMBs")
    guard case .ready(let shown) = codeAssist.submission(at: source.now) else { Issue.record("not ready"); return }
    #expect(shown.code.value == "4/0AVMBs" && shown.link.state == "g7")
    let aiStudio = try reauthFlow(try flowAccount(platform: "gemini", #""credentials":{"oauth_type":"ai_studio"}"#), source)
    #expect(aiStudio.codeDelivery == .callback(address: "localhost:1455"))
    await aiStudio.generate()
    #expect(aiStudio.loopback?.port == 1455)
}

@MainActor @Test func deniedCallbackLandsOnBrowserStep() async throws {
    let source = FakeOAuthLinkSource()
    source.replies = [.success((url: redirect("http://localhost:8085/callback"), state: "a2"))]
    let flow = try reauthFlow(try flowAccount(platform: "antigravity"), source)
    await flow.generate()
    flow.setCode("http://localhost:8085/callback?error=access_denied&state=a2")
    #expect(flow.submission(at: source.now) == .denied)
    #expect(flow.shownError(at: source.now) == AccountOAuthErrorCopy.denied && AccountOAuthErrorCopy.denied.step == .browser)
    flow.setCode("http://localhost:8085/callback?code=c2&state=a2")
    #expect(flow.shownError(at: source.now) == nil)
}

@MainActor @Test func generateFailureLandsOnLinkStep() async throws {
    let source = FakeOAuthLinkSource()
    source.replies = [.failure(APIError.server(status: 404, reason: "PROXY_NOT_FOUND")),
                      .failure(APIError(kind: .transport, message: "无法连接站点")), .failure(CancellationError())]
    let flow = try reauthFlow(try flowAccount(#""proxy_id":3"#), source)
    await flow.generate()
    #expect(flow.error?.step == .link && flow.error?.message == "代理不属于本工作区" && !flow.isBusy && flow.link == nil)
    await flow.generate()
    #expect(flow.error?.step == .link && flow.error?.message == "无法连接站点")
    await flow.generate()
    #expect(flow.error == nil && flow.phase == .idle)
    source.oauthSession = nil
    await flow.generate()
    #expect(source.requests.count == 3 && flow.link == nil)
}

@MainActor @Test func callbackReceiptAndProxyChange() async throws {
    let source = FakeOAuthLinkSource()
    source.replies = [.success((url: redirect("http://localhost:1455/auth/callback"), state: "s"))]
    let flow = OAuthFlowModel(request: OAuthLinkRequest(platform: .openai, proxyID: 4), variant: .create, source: source, now: { source.now })
    await flow.generate()
    let url = URL(string: "http://localhost:1455/auth/callback?code=c&state=s")!
    flow.receiveCallback(url)
    #expect(flow.code == url.absoluteString && flow.receivedAutomatically)
    guard case .ready = flow.submission(at: source.now) else { Issue.record("not ready"); return }
    flow.setCode("c")
    #expect(!flow.receivedAutomatically)
    flow.noteListenFailed()
    #expect(flow.listenFailed)
    let link = flow.link
    flow.updateProxy(9)
    #expect(flow.link == link && flow.request.proxyID == 9)
    guard case .ready(let submission) = flow.submission(at: source.now) else { Issue.record("not ready"); return }
    #expect(submission.proxyID == 9 && submission.link.request.proxyID == 4)
    flow.beginExchange()
    #expect(flow.isBusy && flow.phase == .exchanging)
    flow.finishExchange(email: "ops@example.invalid")
    #expect(flow.phase == .done && flow.authorizedEmail == "ops@example.invalid")
}

@MainActor @Test func createVariantChoosesGeminiTypeAndNeedsProjectForCodeAssist() async throws {
    let source = FakeOAuthLinkSource()
    let flow = OAuthFlowModel(request: OAuthLinkRequest(platform: .gemini, geminiOAuthType: .googleOne), variant: .create, choosesGeminiType: true,
                              source: source, now: { source.now })
    #expect(flow.canGenerate)
    await flow.generate()
    flow.selectGeminiType(.codeAssist)
    #expect(flow.link == nil && !flow.canGenerate)
    flow.setProjectID("  demo-project ")
    #expect(flow.canGenerate)
    await flow.generate()
    #expect(source.requests.last?.geminiOAuthType == .codeAssist && source.requests.last?.projectID == "demo-project")
    let reauth = try reauthFlow(try flowAccount(platform: "gemini"), source)
    reauth.selectGeminiType(.googleOne)
    #expect(reauth.request.geminiOAuthType == .codeAssist && reauth.canGenerate)
}

@MainActor @Test func submissionDescriptionHidesCode() async throws {
    let source = FakeOAuthLinkSource()
    let flow = try reauthFlow(try flowAccount(), source)
    await flow.generate()
    flow.setCode("secret-code#secret-state")
    guard case .ready(let submission) = flow.submission(at: source.now) else { Issue.record("not ready"); return }
    for text in [String(describing: submission), String(reflecting: submission)] {
        #expect(!text.contains("secret-code") && !text.contains("sess-1") && text.contains("anthropic"), "\(text)")
    }
}
