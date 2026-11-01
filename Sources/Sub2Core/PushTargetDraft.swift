import Foundation

// 60 §7.4 (S6-25): the add-target form and the site APNs form, their checks against the backend's rules, the request each
// one sends and how a failed send reads. Secrets and the private key never show in a description, mirror or dump, and the
// form forgets them once sent; the wording is in PushEditCopy.swift.

/// The add-target form's inputs: `endpoint` is Bark's or ntfy's server or the Webhook URL, `token` the Bark device key or the
/// ntfy topic, `secret` the ntfy access token or the Webhook signing secret.
public enum PushTargetField: String, CaseIterable, Sendable {
    case endpoint, token, secret, name
}

/// 添加其他接收方式. Each platform keeps its own fields, so switching does not lose what was typed; only the chosen platform's
/// fields are checked and sent.
public struct PushTargetDraft: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let platforms: [PushPlatform] = [.bark, .ntfy, .webhook]
    /// Backend `pushDeviceNameMaxRunes`, in Unicode scalars.
    public static let maxNameLength = 64
    /// Backend `pushSecretMaxLen`, in UTF-8 bytes.
    public static let maxSecretBytes = 512
    public static let maxEndpointLength = 2_048

    public var platform: PushPlatform
    public var name = ""
    public var barkEndpoint = PushDeviceRegistration.defaultBarkEndpoint
    public var barkKey = ""
    public var ntfyEndpoint = PushDeviceRegistration.defaultNtfyEndpoint
    public var ntfyTopic = ""
    public var ntfyAccessToken = ""
    public var webhookURL = ""
    public var webhookSecret = ""
    /// A secret went out with a failed send and is gone: type it again or choose 不设置.
    public private(set) var needsSecretAgain = false

    /// iOS is this phone's switch, not this form: it reads as Bark.
    public init(platform: PushPlatform = .bark) {
        self.platform = Self.platforms.contains(platform) ? platform : .bark
    }

    public static func fields(for platform: PushPlatform) -> [PushTargetField] {
        switch platform {
        case .ntfy: [.endpoint, .token, .secret, .name]
        case .webhook: [.endpoint, .secret, .name]
        case .bark, .ios: [.endpoint, .token, .name]
        }
    }

    /// The chosen platform's problems, each with its text.
    public var issues: [PushTargetField: String] {
        var found: [PushTargetField: String] = [:]
        for field in Self.fields(for: platform) {
            if let issue = issue(field) { found[field] = issue }
        }
        return found
    }
    public var isComplete: Bool { issues.isEmpty }
    /// An http address is not refused here: the site's push_targets settings may allow it. A note says so instead.
    public var usesInsecureHTTP: Bool { URLComponents(string: endpoint.pushTrimmed)?.scheme?.lowercased() == "http" }
    /// Something typed that 取消 would lose; the prefilled servers do not count.
    public var hasInput: Bool {
        [name, barkKey, ntfyTopic, ntfyAccessToken, webhookURL, webhookSecret].contains { !$0.pushTrimmed.isEmpty }
            || barkEndpoint.pushTrimmed != PushDeviceRegistration.defaultBarkEndpoint
            || ntfyEndpoint.pushTrimmed != PushDeviceRegistration.defaultNtfyEndpoint
    }

    /// The POST body; empty optional values are left out.
    public func registration(timezone: String) throws -> PushDeviceRegistration {
        guard isComplete else { throw APIError(kind: .validation, message: PushEditCopy.fixFields) }
        let name = name.pushTrimmed, endpoint = endpoint.pushTrimmed
        switch platform {
        case .ntfy: return .ntfy(endpoint: endpoint, topic: ntfyTopic.pushTrimmed, accessToken: secret, deviceName: name, timezone: timezone)
        case .webhook: return .webhook(endpoint: endpoint, secret: secret, deviceName: name, timezone: timezone)
        case .bark, .ios: return .bark(endpoint: endpoint, deviceKey: barkKey.pushTrimmed, deviceName: name, timezone: timezone)
        }
    }
    /// As the request leaves (60 §0.4): both secrets are forgotten; one that was sent must be typed again or dropped.
    public mutating func didSubmit(_ registration: PushDeviceRegistration) {
        ntfyAccessToken = ""
        webhookSecret = ""
        needsSecretAgain = registration.hasSecret
    }
    /// 不设置: send without a secret.
    public mutating func dropSecret() { needsSecretAgain = false }

    public var description: String { "PushTargetDraft(\(platform.rawValue), <redacted>)" }
    public var debugDescription: String { description }
    /// A Webhook URL's path may carry the peer's token, so no address shows either.
    public var customMirror: Mirror {
        Mirror(self, children: ["platform": platform, "hasName": !name.pushTrimmed.isEmpty, "hasSecret": !secret.pushTrimmed.isEmpty],
               displayStyle: .struct)
    }

    private var endpoint: String {
        switch platform {
        case .ntfy: ntfyEndpoint
        case .webhook: webhookURL
        case .bark, .ios: barkEndpoint
        }
    }
    private var token: String {
        switch platform {
        case .ntfy: ntfyTopic
        case .webhook: ""
        case .bark, .ios: barkKey
        }
    }
    private var secret: String {
        switch platform {
        case .ntfy: ntfyAccessToken
        case .webhook: webhookSecret
        case .bark, .ios: ""
        }
    }
    private func issue(_ field: PushTargetField) -> String? {
        switch field {
        case .endpoint: return Self.endpointIssue(endpoint, platform: platform)
        case .token: return Self.tokenIssue(token, platform: platform)
        case .secret:
            let secret = secret.pushTrimmed
            if secret.utf8.count > Self.maxSecretBytes { return PushEditCopy.secretTooLong }
            return needsSecretAgain && secret.isEmpty ? PushEditCopy.secretClearedNote : nil
        case .name: return name.pushTrimmed.unicodeScalars.count > Self.maxNameLength ? "名称最多 \(Self.maxNameLength) 个字" : nil
        }
    }
    private static func endpointIssue(_ raw: String, platform: PushPlatform) -> String? {
        let text = raw.pushTrimmed
        if text.isEmpty { return platform == .webhook ? "填写 Webhook URL" : "填写服务器地址" }
        if text.utf8.count > maxEndpointLength { return "地址太长" }
        return isHTTPURL(text) ? nil : "地址格式不对，要以 https:// 开头"
    }
    private static func tokenIssue(_ raw: String, platform: PushPlatform) -> String? {
        let text = raw.pushTrimmed
        if platform == .ntfy {
            if text.isEmpty { return "填写主题" }
            return isTokenText(text, limit: 64) ? nil : "主题只能包含字母、数字、- 和 _，最多 64 个"
        }
        if text.isEmpty { return "填写 Bark App 里的设备 Key" }
        return isTokenText(text, limit: 128) ? nil : "设备 Key 只能包含字母、数字、- 和 _"
    }
    /// An absolute http(s) address with a host and no whitespace.
    private static func isHTTPURL(_ text: String) -> Bool {
        guard !text.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains), let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return !(parts.host ?? "").isEmpty
    }
    /// Backend `^[A-Za-z0-9_-]{1,limit}$`.
    private static func isTokenText(_ text: String, limit: Int) -> Bool {
        (1...limit).contains(text.utf8.count) && text.utf8.allSatisfy { $0.isASCIIAlphanumeric || $0 == 45 || $0 == 95 }
    }
}

/// A failed registration (sent once, R06).
public enum PushTargetFailure: Sendable, Equatable {
    /// Cancelled, or the security sheet was closed: nothing to show.
    case cancelled
    case field(PushTargetField, String)
    case form(String)
    /// It may have been registered: the page reads its list again.
    case unconfirmed(String)

    public static func classify(_ error: any Error) -> PushTargetFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .form(error.localizedDescription) }
        switch api.securityOutcome {
        case .cancelled?: return .cancelled
        case .passed?: return .form(api.localizedDescription)
        case .blocked?, nil: break
        }
        if PushEditFailure.mayHaveApplied(api) { return .unconfirmed(PushEditCopy.targetUnconfirmed) }
        let field = api.metadata["field"]
        switch (api.statusCode, api.reason) {
        case (400?, "INVALID_PUSH_TARGET"?) where field == nil || field == "endpoint": return .field(.endpoint, PushPresentation.failureMessage(api))
        case (400?, "INVALID_PUSH_TARGET"?) where field == "secret": return .field(.secret, PushEditCopy.secretTooLong)
        case (400?, "INVALID_PUSH_TOKEN"?) where field == "token": return .field(.token, PushPresentation.failureMessage(api))
        default: return .form(PushPresentation.failureMessage(api))
        }
    }
}

/// 站点 APNs 配置 being edited. Only changed fields are sent; the private key is sent only when a new one was given, and it is
/// forgotten as the request leaves (60 §7.4).
public struct APNsConfigDraft: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A .p8 is about 250 bytes; a bigger file is not one.
    public static let maxPrivateKeyBytes = 16_384

    public let original: PushAPNsConfig
    public var enabled: Bool
    public var teamID: String
    public var keyID: String
    /// Empty follows the App's bundle ID.
    public var topic: String
    public var environment: PushAPNsEnvironment
    public private(set) var privateKey = ""
    /// A key went out with a failed save and is gone: give it again or choose 不更换私钥.
    public private(set) var needsPrivateKeyAgain = false

    public init(config: PushAPNsConfig) {
        original = config
        enabled = config.enabled; teamID = config.teamID ?? ""; keyID = config.keyID ?? ""; topic = config.topic ?? ""
        environment = config.environment
    }

    /// Without the site's fixed encryption key no private key can be saved, so none can be given.
    public var canEditPrivateKey: Bool { original.encryptionKeyConfigured }
    public var hasNewPrivateKey: Bool { !privateKey.pushTrimmed.isEmpty }
    /// The editor shows until a key is recognized; a recognized key is never shown back (S6D2b-10).
    public var acceptsPrivateKeyInput: Bool { canEditPrivateKey && !(hasNewPrivateKey && Self.isPrivateKeyPEM(privateKey)) }
    public var privateKeyStatus: String {
        if hasNewPrivateKey { return "已读取新私钥，保存时上传" }
        return original.privateKeyConfigured ? "已配置（不更换就不用填）" : "未配置"
    }

    /// The backend's checks in its terms (push_config_service.go): an empty ID or Topic clears it, which is allowed unless
    /// APNs is on.
    public var issues: [PushAPNsField: String] {
        var found: [PushAPNsField: String] = [:]
        let team = teamID.pushTrimmed, key = keyID.pushTrimmed, topic = topic.pushTrimmed
        if !team.isEmpty, !Self.isAPNsIdentifier(team) { found[.teamID] = PushAPNsField.teamID.invalidMessage }
        if !key.isEmpty, !Self.isAPNsIdentifier(key) { found[.keyID] = PushAPNsField.keyID.invalidMessage }
        if !topic.isEmpty, !Self.isBundleID(topic) { found[.topic] = PushAPNsField.topic.invalidMessage }
        if hasNewPrivateKey {
            if !canEditPrivateKey { found[.privateKey] = PushPresentation.encryptionKeyMissing }
            else if !Self.isPrivateKeyPEM(privateKey) { found[.privateKey] = PushAPNsField.privateKey.invalidMessage }
        } else if needsPrivateKeyAgain {
            found[.privateKey] = PushEditCopy.keyClearedNote
        }
        if enabled, team.isEmpty || key.isEmpty || (!hasNewPrivateKey && !original.privateKeyConfigured) {
            found[.enabled] = PushAPNsField.enabled.invalidMessage
        }
        return found
    }
    public var update: PushAPNsConfigUpdate {
        PushAPNsConfigUpdate(changesFrom: original, enabled: enabled, teamID: teamID, keyID: keyID,
                             privateKey: hasNewPrivateKey ? privateKey.pushTrimmed : nil, topic: topic, environment: environment)
    }
    public var hasChanges: Bool { !update.isEmpty }

    /// Pasted, typed or imported.
    public mutating func setPrivateKey(_ text: String) { privateKey = text }
    public mutating func clearPrivateKey() { privateKey = "" }
    /// As the request leaves (60 §7.4 “私钥文本提交后立即清空”).
    public mutating func didSubmit(_ update: PushAPNsConfigUpdate) {
        privateKey = ""
        needsPrivateKeyAgain = update.includesPrivateKey
    }
    /// 不更换私钥: keep the site's.
    public mutating func keepCurrentPrivateKey() { needsPrivateKeyAgain = false }
    /// The site's settings read again (after a save without an answer, or a refresh): changes count from them. A field
    /// changed here keeps its value, the others follow the server; a new key and the 重新导入 mark stay.
    public func rebased(on config: PushAPNsConfig) -> APNsConfigDraft {
        let changed = update
        var next = APNsConfigDraft(config: config)
        if changed.enabled != nil { next.enabled = enabled }
        if changed.teamID != nil { next.teamID = teamID }
        if changed.keyID != nil { next.keyID = keyID }
        if changed.topic != nil { next.topic = topic }
        if changed.environment != nil { next.environment = environment }
        next.privateKey = privateKey
        next.needsPrivateKeyAgain = needsPrivateKeyAgain
        return next
    }

    /// A PKCS#8 or SEC1 PEM block: matching BEGIN and END lines around base64. The curve is the server's to check.
    public static func isPrivateKeyPEM(_ text: String) -> Bool {
        let text = text.pushTrimmed
        for label in ["PRIVATE KEY", "EC PRIVATE KEY"] {
            let begin = "-----BEGIN \(label)-----", end = "-----END \(label)-----"
            guard text.hasPrefix(begin), text.hasSuffix(end), text.count >= begin.count + end.count else { continue }
            let body = text.dropFirst(begin.count).dropLast(end.count).unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            return !body.isEmpty && body.allSatisfy { $0.isASCII && (UInt8($0.value).isASCIIAlphanumeric || "+/=".unicodeScalars.contains($0)) }
        }
        return false
    }
    /// A .p8 file's content: small, UTF-8 (a BOM is dropped) and a PEM block; nil otherwise.
    public static func privateKey(fromFile data: Data) -> String? {
        guard data.count <= maxPrivateKeyBytes, var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.pushTrimmed
        return isPrivateKeyPEM(text) ? text : nil
    }
    /// Backend `^[A-Z0-9]{10}$` after trimming and upper-casing.
    public static func isAPNsIdentifier(_ raw: String) -> Bool {
        let text = raw.pushTrimmed.uppercased()
        return text.utf8.count == 10 && text.utf8.allSatisfy(\.isASCIIAlphanumeric)
    }
    /// Backend `^[A-Za-z0-9][A-Za-z0-9.-]{0,154}$`.
    public static func isBundleID(_ raw: String) -> Bool {
        let bytes = Array(raw.pushTrimmed.utf8)
        guard let first = bytes.first, first.isASCIIAlphanumeric, bytes.count <= 155 else { return false }
        return bytes.allSatisfy { $0.isASCIIAlphanumeric || $0 == 46 || $0 == 45 }
    }

    public var description: String { "APNsConfigDraft(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["enabled": enabled, "teamID": teamID, "keyID": keyID, "topic": topic, "environment": environment,
                                "hasNewPrivateKey": hasNewPrivateKey], displayStyle: .struct)
    }
}

/// A failed save of the site's APNs settings (sent once, never resent after a security refusal).
public enum APNsConfigFailure: Sendable, Equatable {
    case cancelled
    /// The security sheet cleared it before it ran; the administrator saves again (00 §2.6.2 step 4).
    case reconfirm(String)
    case field(PushAPNsField, String)
    case form(String)
    /// admin/me was out of date (the site turned step-up on, or TOTP went off): the sheet reads it again and 编辑 greys.
    case staleSecurity(String)
    /// It may have been saved: the page reads the settings again; saving once more is harmless (PUT).
    case unconfirmed(String)

    public static func classify(_ error: any Error) -> APNsConfigFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .form(error.localizedDescription) }
        switch SecurityInterruption(api) {
        case .stepUpMachineCredential?, .stepUpTOTPNotEnabled?: return .staleSecurity(api.localizedDescription)
        default: break
        }
        switch api.securityOutcome {
        case .cancelled?: return .cancelled
        case .passed?: return .reconfirm(api.localizedDescription)
        case .blocked?, nil: break
        }
        if PushEditFailure.mayHaveApplied(api) { return .unconfirmed(PushEditCopy.apnsUnconfirmed) }
        let failure = PushPresentation.apnsConfigFailure(api)
        return failure.field.map { .field($0, failure.message) } ?? .form(failure.message)
    }
}

private enum PushEditFailure {
    /// No answer, an unreadable one, 408 or a gateway's: the write may have run. A refresh that failed before sending did not.
    static func mayHaveApplied(_ api: APIError) -> Bool {
        guard api != .refreshDeferred else { return false }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse }
        return status == 408 || RequestPolicy.isRetryableStatus(status, marker: api.reason)
    }
}

private extension String {
    var pushTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension UInt8 {
    var isASCIIAlphanumeric: Bool { (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self) }
}
