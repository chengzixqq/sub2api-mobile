import Foundation
import Observation
import Sub2Core

/// What the login page sends (00 §1.4): APIClient in the App, the DemoData fixture in UI tests, stubs in unit tests. The
/// App's client is built with no session hook and no security interceptor, so a refused login never ends the connected site
/// (D13).
protocol LoginGateway: Sendable {
    func publicSettings() async throws -> PublicSettings
    func login(email: String, password: String, proof: CaptchaProof?, deviceName: String, declaresCaptchaProvider: Bool) async throws -> LoginResult
    func completeTOTP(tempToken: String, code: String) async throws -> AuthSession
    func cancelAll() async
}
extension APIClient: LoginGateway {}

/// The App side of a login; LoginView builds it from AppModel.
struct LoginEnvironment {
    var deviceName: String
    var makeGateway: @MainActor (ServerProfile, UUID) -> any LoginGateway
    /// The device ID a saved site signs in with (00 §1.2); asked only when the login keeps the site's id.
    var storedDeviceID: @MainActor (UUID) async throws -> UUID
    /// AppModel.connect (`admin/me`, then saving the site); returns the identity's email.
    var connect: @MainActor (ServerProfile, Credential, UUID) async throws -> String?
    var cancelConnection: @MainActor () -> Void
    var didConnect: @MainActor (String?) -> Void
    var now: @MainActor () -> Date = { Date() }
}

/// The login page's flow (60 §4.4; 00 §1.4–§1.6, D32). LoginView only draws it and forwards edits and sheet results.
@MainActor @Observable
final class LoginController {
    var name: String
    var address: String
    var method: LoginMethod
    var email = ""
    var password = ""
    var key = ""
    var code = ""
    var agreementChecked = false
    /// The verification page; its sheet reports through `captchaCompleted` and `captchaDismissed`.
    var captcha: CaptchaRequest?
    private(set) var challenge: TwoFactorChallenge?
    private(set) var agreementPrompt: LoginAgreement?
    /// The latest `settings/public` of `address`: name placeholder, backend-mode hint and agreement row.
    private(set) var site: PublicSettings?
    private(set) var notice: String?
    private(set) var twoFactorNotice: String?
    private(set) var cooldownUntil: Date?
    private(set) var isBusy = false
    let prompt: LoginPrompt?

    /// One address's login: the site id, device ID and client stay until the address changes.
    private struct Attempt {
        let url: URL
        let siteID: UUID
        let deviceID: UUID
        let gateway: any LoginGateway
    }
    /// Ends a step with what to show; a nil failure is a cancelled step, which shows nothing.
    private struct Halt: Error {
        let failure: LoginFailure?
        let stage: LoginStage
        /// A 404 of any kind; only a non-JSON one is `notSub2Site` already (D32).
        let isNotFound: Bool
        init(_ error: any Error, stage: LoginStage) {
            failure = LoginFailure.classify(error, stage: stage); self.stage = stage
            isNotFound = (error as? APIError)?.statusCode == 404
        }
        init(stop message: String, stage: LoginStage) { failure = LoginFailure(message: message, action: .stop); self.stage = stage; isNotFound = false }
    }

    @ObservationIgnored private let environment: LoginEnvironment
    @ObservationIgnored private var attempt: Attempt?
    @ObservationIgnored private var draftDeviceID = UUID()
    /// Replaced by `cancel`, so answers that arrive afterwards are dropped.
    @ObservationIgnored private var run = UUID()
    @ObservationIgnored private var proof: (value: CaptchaProof, expiresAt: Date)?
    @ObservationIgnored private var requirement = CaptchaRequirement.none
    @ObservationIgnored private var signingProfile: ServerProfile?
    @ObservationIgnored private var acceptedRevision: String?
    @ObservationIgnored private var resumesAfterAgreement = false
    /// The page reopens itself at most once per tap on 连接站点.
    @ObservationIgnored private var bridgeReopened = false
    /// The login limit is the site's (per IP, 00 §1.4): each address keeps its wait, so editing the address and back
    /// does not end it.
    @ObservationIgnored private var cooldowns: [URL: Date] = [:]

    init(prompt: LoginPrompt?, environment: LoginEnvironment) {
        self.prompt = prompt; self.environment = environment
        name = prompt?.profile.name ?? ""
        address = prompt?.profile.baseURL.absoluteString ?? ""
        method = prompt.map { LoginMethod($0.profile.authentication) } ?? .password
    }

    /// The agreement applies to the password login only; keys never pass Web's login form.
    var agreement: LoginAgreement? { method == .password ? site.flatMap(LoginAgreement.init) : nil }
    var showsBackendModeHint: Bool { site?.backendModeEnabled == true }
    var namePlaceholder: String { LoginSite.resolvedName(input: "", siteName: site?.siteName) ?? "站点名称" }
    var isReLogin: Bool { prompt != nil }
    var hasProof: Bool { proof != nil }
    func cooldownRemaining(at now: Date) -> Int { LoginCooldown.remainingSeconds(until: cooldownUntil, now: now) }
    /// The page's timer: the button stops counting once the wait is over.
    func cooldownElapsed() { if cooldownRemaining(at: environment.now()) == 0 { cooldownUntil = nil } }

    func addressDidChange() {
        endTwoFactor()
        proof = nil; attempt = nil; site = nil; signingProfile = nil
        acceptedRevision = nil; agreementChecked = false
        let now = environment.now()
        cooldownUntil = (try? ServerProfile.normalizedURL(address)).flatMap { cooldowns[$0] }.flatMap { $0 > now ? $0 : nil }
        // A new address is a new site: its login declares a new device ID (00 §1.2).
        draftDeviceID = UUID()
    }
    func methodDidChange() { endTwoFactor(); proof = nil }
    func keyDidChange() { method = method.adjusted(forKey: key) }

    /// Debounced `settings/public` for the hints above the form; failures say nothing.
    func prefetchSite(after delay: Duration = .milliseconds(600)) async {
        let typed = address
        guard let url = try? ServerProfile.normalizedURL(typed) else { return }
        if delay > .zero { do { try await Task.sleep(for: delay) } catch { return } }
        guard typed == address else { return }
        let gateway = environment.makeGateway(ServerProfile(name: "", baseURL: url, authentication: method.authenticationKind), draftDeviceID)
        guard let settings = try? await gateway.publicSettings(), typed == address else { return }
        site = settings
    }

    func submit() async {
        guard !isBusy, challenge == nil, cooldownRemaining(at: environment.now()) == 0 else { return }
        notice = nil; bridgeReopened = false
        isBusy = true; defer { isBusy = false }
        let run = self.run
        guard let attempt = await startAttempt(run: run) else { return }
        await advance(attempt, run: run)
    }

    func captchaCompleted(_ outcome: CaptchaOutcome) {
        captcha = nil
        switch outcome {
        case .proof(let value): proof = (value, environment.now().addingTimeInterval(CaptchaBridge.proofLifetime))
        case .cancelled: proof = nil
        case .failed(let message): proof = nil; notice = message
        }
    }
    /// Goes on only after the page's sheet is gone, so the next sheet is not dropped by SwiftUI.
    func captchaDismissed() async {
        guard proof != nil, let attempt, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        await advance(attempt, run: run)
    }

    func acceptAgreement() {
        guard let agreementPrompt else { return }
        acceptedRevision = agreementPrompt.revision; resumesAfterAgreement = true
        self.agreementPrompt = nil
    }
    func rejectAgreement() {
        guard agreementPrompt != nil else { return }
        agreementPrompt = nil; resumesAfterAgreement = false
        notice = LoginCopy.agreementRequired
    }
    func agreementDismissed() async {
        guard resumesAfterAgreement, let attempt, !isBusy else { return }
        resumesAfterAgreement = false
        isBusy = true; defer { isBusy = false }
        await advance(attempt, run: run)
    }

    /// 00 §1.4 step 3: six digits submit themselves once.
    func codeDidChange() async {
        // During a 429 the sheet locks the field and keeps the notice; anything typed meanwhile is dropped, not held back.
        guard cooldownRemaining(at: environment.now()) == 0 else { if !code.isEmpty { code = "" }; return }
        let clean = OneTimeCode.sanitize(code)
        if clean != code { code = clean }
        if !clean.isEmpty { twoFactorNotice = nil }
        guard OneTimeCode.isComplete(clean), let challenge, let attempt, let profile = signingProfile, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        let run = self.run
        do {
            let session = try await step(.twoFactor, run: run) { try await attempt.gateway.completeTOTP(tempToken: challenge.tempToken, code: clean) }
            endTwoFactor()
            try await connect(profile, credential: .tokens(session.tokens), attempt)
        } catch { await fail(error, attempt, run: run) }
    }
    /// The sheet's 取消 or a swipe. Not while a code is being checked: the server may already have issued the session, which
    /// this phone could then neither use nor sign out of; the sheet disables both meanwhile.
    func cancelTwoFactor() {
        guard challenge != nil, !isBusy else { return }
        run = UUID()
        endTwoFactor()
    }

    /// Leaving the page: secrets are wiped and the requests of this login are cancelled.
    func cancel() async {
        run = UUID()
        wipeSecrets()
        endTwoFactor(); captcha = nil; agreementPrompt = nil; resumesAfterAgreement = false
        environment.cancelConnection()
        let gateway = attempt?.gateway
        attempt = nil
        await gateway?.cancelAll()
    }

    // MARK: - Steps

    private func startAttempt(run: UUID) async -> Attempt? {
        let url: URL
        do { url = try ServerProfile.normalizedURL(address) } catch { notice = error.localizedDescription; return nil }
        let hasCredentials = method.usesKey ? !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        guard hasCredentials else { notice = LoginCopy.credentialsRequired; return nil }
        if let attempt, attempt.url == url { return attempt }
        // A known site keeps its id only for the same address and without pending records (LoginPrompt, D17).
        let target = prompt?.profile(name: "", url: url, authentication: method.authenticationKind)
            ?? ServerProfile(name: "", baseURL: url, authentication: method.authenticationKind)
        var deviceID = draftDeviceID
        if target.id == prompt?.profile.id {
            do { deviceID = try await environment.storedDeviceID(target.id) }
            catch { notice = LoginFailure.classify(error, stage: .site)?.message; return nil }
            guard run == self.run else { return nil }
        }
        let next = Attempt(url: url, siteID: target.id, deviceID: deviceID, gateway: environment.makeGateway(target, deviceID))
        attempt = next
        return next
    }

    /// From `settings/public` to a connected site, or to the sheet it waits for. Every resume runs it again, so a proof is
    /// checked against the latest settings.
    private func advance(_ attempt: Attempt, run: UUID) async {
        do {
            let settings = try await loadSettings(attempt, run: run)
            if method.usesKey {
                let credential = Credential.fromAPIKey(key)
                method = LoginMethod(credential.authenticationKind)
                try await connect(profile(attempt, settings: settings, kind: credential.authenticationKind), credential: credential, attempt)
            } else if let settings {
                try await signIn(profile(attempt, settings: settings, kind: .password), settings: settings, attempt, run: run)
            }
        } catch { await fail(error, attempt, run: run) }
    }

    /// A password login needs the settings (captcha, agreement), and a 404 of them says the address is no Sub2 site (00 §1.1).
    /// A key login only takes the name from them and goes on past anything but a non-JSON 404, because `admin/me` checks the
    /// site anyway (D32).
    private func loadSettings(_ attempt: Attempt, run: UUID) async throws -> PublicSettings? {
        let settings: PublicSettings
        do { settings = try await step(.site, run: run) { try await attempt.gateway.publicSettings() } }
        catch let halt as Halt where halt.failure != nil && halt.failure != LoginFailure.notSub2Site {
            if method.usesKey { return nil }
            throw halt.isNotFound ? Halt(stop: LoginCopy.notSub2Site, stage: .site) : halt
        }
        site = settings
        guard LoginSite.isSub2(settings) else { throw Halt(stop: LoginCopy.notSub2Site, stage: .site) }
        return settings
    }

    private func profile(_ attempt: Attempt, settings: PublicSettings?, kind: AuthenticationKind) throws -> ServerProfile {
        guard let name = LoginSite.resolvedName(input: name, siteName: settings?.siteName) else {
            throw Halt(stop: LoginCopy.siteNameRequired, stage: .site)
        }
        return ServerProfile(id: attempt.siteID, name: name, baseURL: attempt.url, authentication: kind)
    }

    private func signIn(_ profile: ServerProfile, settings: PublicSettings, _ attempt: Attempt, run: UUID) async throws {
        guard try passesAgreement(settings) else { return }
        signingProfile = profile
        requirement = CaptchaRequirement(settings)
        if let message = requirement.stopMessage { throw Halt(stop: message, stage: .password) }
        let held = usableProof()
        if case .bridge = requirement, held == nil { openBridge(); return }
        // One use, whatever the answer (00 §1.5).
        proof = nil
        let email = self.email.trimmingCharacters(in: .whitespacesAndNewlines), password = self.password, deviceName = environment.deviceName
        let result = try await step(.password, run: run) {
            try await attempt.gateway.login(email: email, password: password, proof: held, deviceName: deviceName,
                                            declaresCaptchaProvider: settings.hasCaptchaProviderKey)
        }
        switch result {
        case .twoFactor(let next): challenge = next; code = ""; twoFactorNotice = nil
        case .authenticated(let session): try await connect(profile, credential: .tokens(session.tokens), attempt)
        }
    }

    /// 00 §1.4 step 1: a checkbox must be ticked; a modal is asked once per page and revision.
    private func passesAgreement(_ settings: PublicSettings) throws -> Bool {
        guard let agreement = LoginAgreement(settings) else { return true }
        switch agreement.mode {
        case .checkbox:
            guard agreementChecked else { throw Halt(stop: LoginCopy.agreementRequired, stage: .password) }
            return true
        case .modal:
            guard acceptedRevision != agreement.revision else { return true }
            agreementPrompt = agreement
            return false
        }
    }

    /// A proof for the provider in force and not yet expired; anything else is dropped.
    private func usableProof() -> CaptchaProof? {
        guard case .bridge(let provider, _, _) = requirement, let held = proof, held.value.provider == provider,
              held.expiresAt > environment.now() else { proof = nil; return nil }
        return held.value
    }
    private func openBridge() {
        guard case .bridge(let provider, let path, let hint) = requirement, let signingProfile else { return }
        captcha = CaptchaRequest(server: signingProfile, provider: provider, path: path, showsFallbackHint: hint)
    }

    /// Connected: the page says so even when it went away meanwhile (the root page is replaced by the tabs).
    private func connect(_ profile: ServerProfile, credential: Credential, _ attempt: Attempt) async throws {
        let email: String?
        do { email = try await environment.connect(profile, credential, attempt.deviceID) } catch { throw Halt(error, stage: .connect) }
        wipeSecrets()
        self.attempt = nil
        environment.didConnect(email)
    }

    private func step<Value: Sendable>(_ stage: LoginStage, run: UUID, _ work: @MainActor () async throws -> Value) async throws -> Value {
        let value: Value
        // After `cancel`, a failure is a cancelled step too: it shows nothing and never goes on to connect.
        do { value = try await work() } catch { throw Halt(run == self.run ? error : CancellationError(), stage: stage) }
        guard run == self.run else { throw Halt(CancellationError(), stage: stage) }
        return value
    }

    // MARK: - Failures

    private func fail(_ error: any Error, _ attempt: Attempt, run: UUID) async {
        guard run == self.run else { return }
        let halt = error as? Halt ?? Halt(error, stage: .connect)
        guard let failure = halt.failure else { return }
        proof = nil
        if halt.stage == .twoFactor { applyTwoFactor(failure, site: attempt.url); return }
        notice = failure.message
        switch failure.action {
        case .clearPassword: password = ""
        case .cooldown(let seconds): startCooldown(seconds, site: attempt.url)
        case .reverify: reopenBridge()
        case .reloadSettings: await reloadSettings(attempt, run: run)
        case .none, .stop, .clearCode, .closeTwoFactor, .restart: break
        }
    }

    private func applyTwoFactor(_ failure: LoginFailure, site: URL) {
        switch failure.action {
        case .closeTwoFactor, .restart, .stop:
            endTwoFactor(); notice = failure.message
        case .cooldown(let seconds):
            startCooldown(seconds, site: site); code = ""; twoFactorNotice = failure.message
        case .none, .clearCode, .clearPassword, .reverify, .reloadSettings:
            code = ""; twoFactorNotice = failure.message
        }
    }

    /// CAPTCHA_PROVIDER_MISMATCH: never resend; read the settings again and verify with the provider now in force.
    private func reloadSettings(_ attempt: Attempt, run: UUID) async {
        guard let settings = try? await step(.site, run: run, { try await attempt.gateway.publicSettings() }) else { return }
        site = settings
        requirement = CaptchaRequirement(settings)
        if let message = requirement.stopMessage { notice = message; return }
        reopenBridge()
    }
    private func reopenBridge() {
        guard !bridgeReopened, case .bridge = requirement else { return }
        bridgeReopened = true
        openBridge()
    }

    private func startCooldown(_ seconds: Int, site: URL) {
        let until = environment.now().addingTimeInterval(TimeInterval(seconds))
        cooldowns[site] = until
        if (try? ServerProfile.normalizedURL(address)) == site { cooldownUntil = until }
    }
    private func endTwoFactor() { challenge = nil; code = ""; twoFactorNotice = nil }
    private func wipeSecrets() { password = ""; key = ""; code = ""; proof = nil }
}
