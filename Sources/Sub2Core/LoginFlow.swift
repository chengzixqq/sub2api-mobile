import Foundation

/// The three sign-in choices of the login page, in the order of 00 §1.3; the password is recommended and selected first.
/// These are page texts (60 §4.3); the site list's wording is AuthPresentation's (D10).
public enum LoginMethod: String, CaseIterable, Identifiable, Sendable {
    case password, accessToken, adminKey

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .password: "账号和密码"
        case .accessToken: "管理访问令牌"
        case .adminKey: "Admin Key"
        }
    }
    public var badge: String? {
        switch self {
        case .password: "推荐"
        case .accessToken: nil
        case .adminKey: "不推荐"
        }
    }
    public var note: String? {
        switch self {
        case .password: nil
        case .accessToken: "以签发它的管理员身份操作，可只读、会过期、能单独吊销。"
        case .adminKey: "以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。"
        }
    }
    /// The access token and the Admin Key share one field (00 §1.6).
    public var usesKey: Bool { self != .password }
    public var authenticationKind: AuthenticationKind {
        switch self {
        case .password: .password
        case .accessToken: .accessToken
        case .adminKey: .adminKey
        }
    }
    public init(_ kind: AuthenticationKind) {
        switch kind {
        case .password: self = .password
        case .accessToken: self = .accessToken
        case .adminKey: self = .adminKey
        }
    }
    /// A pasted `sat_` key moves “Admin Key” to “管理访问令牌” (00 §1.3) by the one prefix rule (D14). Typing never moves it
    /// back; the submitted credential follows the prefix either way.
    public func adjusted(forKey key: String) -> LoginMethod {
        guard self == .adminKey else { return self }
        return LoginMethod(Credential.fromAPIKey(key).authenticationKind)
    }
}

/// What `settings/public` asks of a password login (00 §1.5, 60 §4.4).
public enum CaptchaRequirement: Equatable, Sendable {
    case none, conflict
    /// A provider the bridge validator cannot accept: its message would be refused until the timeout.
    case unsupported(provider: String)
    case bridge(provider: String, path: String, showsFallbackHint: Bool)

    public init(_ settings: PublicSettings) {
        guard let provider = settings.captchaProvider else { self = .none; return }
        if provider == "conflict" { self = .conflict; return }
        guard CaptchaBridge.providers.contains(provider) else { self = .unsupported(provider: provider); return }
        // "" (front end deployed apart), a missing key (older server) and an unusable value all still try the page.
        let declared = CaptchaBridge.safePath(settings.mobileVerifyPath)
        self = .bridge(provider: provider, path: declared ?? CaptchaBridge.defaultPath, showsFallbackHint: declared == nil)
    }
    /// The login stops here with this text; nil when it can go on.
    public var stopMessage: String? {
        switch self {
        case .conflict: ReasonCatalog.entry(status: 503, reason: "CAPTCHA_PROVIDER_CONFLICT", context: .login).message
        case .unsupported: LoginCopy.captchaUnsupported
        case .none, .bridge: nil
        }
    }
}

public enum CaptchaBridge {
    public static let defaultPath = "/mobile/verify"
    /// The proof formats CaptchaBridgeValidator accepts.
    public static let providers: Set<String> = ["turnstile", "tencent", "aliyun"]
    /// A proof is used once and only within this time (00 §1.5).
    public static let proofLifetime: TimeInterval = 120
    /// The App's own limit on the page; the page itself gives up after two minutes.
    public static let timeout: TimeInterval = 180

    /// `mobile_verify_path` comes from the server: only a plain same-site path is used, never a host or a query.
    public static func path(from mobileVerifyPath: String?) -> String { safePath(mobileVerifyPath) ?? defaultPath }
    static func safePath(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("/"), !raw.contains("//"), !raw.contains(".."),
              raw.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "/_.-".unicodeScalars.contains($0)) })
        else { return nil }
        return raw
    }
}

/// One opening of the verification page; `id` is the nonce the page must echo.
public struct CaptchaRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let server: ServerProfile
    public let provider: String
    public let path: String
    /// `mobile_verify_path` was "" or unusable: the page may not exist, so the sheet says how to sign in otherwise.
    public let showsFallbackHint: Bool

    public init(id: UUID = UUID(), server: ServerProfile, provider: String, path: String, showsFallbackHint: Bool) {
        self.id = id; self.server = server; self.provider = provider; self.path = path; self.showsFallbackHint = showsFallbackHint
    }
    /// `<site><path>?nonce=<id>`; the page refuses any other query item (sub2 docs/mobile-verification.md).
    public var url: URL? {
        guard var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path
        components.queryItems = [URLQueryItem(name: "nonce", value: id.uuidString)]
        return components.url
    }
}

public enum CaptchaOutcome: Sendable {
    case proof(CaptchaProof), cancelled, failed(String)
}

/// WebKit load failures of the page (00 §1.5). Our own refusals of off-site navigation also arrive here and are ignored.
public enum CaptchaLoadFailure {
    private static let networkCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed,
        NSURLErrorCallIsActive, NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
        NSURLErrorClientCertificateRequired
    ]
    public static func message(domain: String, code: Int) -> String? {
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled { return nil }
        // WebKitErrorFrameLoadInterruptedByPolicyChange: a navigation the delegate cancelled.
        if domain == "WebKitErrorDomain" && code == 102 { return nil }
        if domain == NSURLErrorDomain && networkCodes.contains(code) { return LoginCopy.unreachable }
        return LoginCopy.captchaPageMissing
    }
    /// The page's own response; an SPA fallback answers 200 and is caught by the hint and the timeout instead.
    public static func message(httpStatus: Int) -> String? { httpStatus >= 400 ? LoginCopy.captchaPageMissing : nil }
}

/// `login_agreement_*`, gated the way Web's `applyLoginAgreementSettings` does: on, and at least one titled document.
public struct LoginAgreement: Equatable, Identifiable, Sendable {
    public enum Mode: Equatable, Sendable { case checkbox, modal }
    public let mode: Mode
    public let documents: [LoginAgreementDocument]
    public let revision: String
    public var id: String { revision }

    public init?(_ settings: PublicSettings) {
        let documents = settings.loginAgreementDocuments.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard settings.loginAgreementEnabled == true, !documents.isEmpty else { return nil }
        mode = settings.loginAgreementMode == "checkbox" ? .checkbox : .modal
        self.documents = documents
        let derived = (settings.loginAgreementUpdatedAt ?? "") + ":" + documents.map { "\($0.id):\($0.title)" }.joined(separator: "|")
        revision = settings.loginAgreementRevision.flatMap { $0.isEmpty ? nil : $0 } ?? derived
    }
}

public enum LoginSite {
    /// 00 §1.1: a successful `settings/public` with a version.
    public static func isSub2(_ settings: PublicSettings) -> Bool {
        !(settings.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    /// The typed name wins; an empty field takes `site_name` (60 §4.3).
    public static func resolvedName(input: String, siteName: String?) -> String? {
        for candidate in [input, siteName ?? ""] {
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }
    public static var backendModeHint: String { ReasonCatalog.entry(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .login).message }
}

public enum LoginCooldown {
    public static func remainingSeconds(until: Date?, now: Date) -> Int {
        guard let until else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }
}

/// Login page texts the reason catalog does not have (D32); server answers are worded by ReasonCatalog only.
public enum LoginCopy {
    public static let credentialsRequired = "请完整填写登录凭据"
    public static let siteNameRequired = "请填写站点名称"
    public static let notSub2Site = "该地址不是 Sub2 站点，请检查站点地址"
    public static let agreementRequired = "请先阅读并同意最新条款后再登录"
    public static let captchaUnsupported = "站点的验证方式暂不支持，请改用 Web 登录或管理访问令牌"
    public static let captchaFallbackHint = "若页面无法完成验证，请改用 Web 登录或 Admin Key"
    public static let captchaPageMissing = "站点未部署手机验证页，请改用 Web 或关闭验证码"
    public static let captchaTimeout = "安全验证已超时，请重新开始"
    public static let unreachable = "无法连接站点"
    public static func cooldownButton(_ seconds: Int) -> String { "\(seconds) 秒后重试" }
    /// 60 §4.3: the identity `admin/me` reported.
    public static func connectedReceipt(email: String?) -> String {
        guard let email, !email.isEmpty else { return "已连接" }
        return "已连接 · 以 \(email) 身份操作"
    }
}
