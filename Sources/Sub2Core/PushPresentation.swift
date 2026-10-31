import Foundation

/// This phone's target as the switch and the settings row show it (60 §7.3, §3.3).
public enum PushLocalState: Sendable, Equatable {
    case off, on, disabled

    public var settingsTitle: String {
        switch self {
        case .off: "未开启"
        case .on: "已开启"
        case .disabled: "已停用"
        }
    }
    /// The switch is on only for a stored id whose target is enabled.
    public var isToggleOn: Bool { self == .on }
    /// A test needs the target to exist; testing a disabled one enables it again when it is delivered.
    public var canSendTest: Bool { self != .off }
}

/// One row of 其他接收方式.
public struct PushTargetRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let platform: PushPlatform?
    public let symbolName: String
    public let title: String
    public let subtitle: String
    /// Shows the neutral `PushPresentation.disabledBadge`.
    public let isDisabled: Bool
}

/// 站点 APNs 配置 as shown.
public struct PushAPNsConfigRows: Sendable, Equatable {
    public let teamID: String
    public let keyID: String
    public let privateKey: String
    public let topic: String
    public let environment: String
    public let status: String
    public let statusTone: Tone
}

public enum PushAPNsEditability: Sendable, Equatable {
    case available
    /// Greyed out with this note.
    case disabled(String)
    public var isAvailable: Bool { self == .available }
    public var note: String? { if case .disabled(let note) = self { note } else { nil } }
}

/// The `metadata.field` values of INVALID_APNS_CONFIG that point at a form field.
public enum PushAPNsField: String, CaseIterable, Sendable {
    case enabled = "apns_enabled", teamID = "apns_team_id", keyID = "apns_key_id", privateKey = "apns_private_key"
    case topic = "apns_topic", environment = "apns_environment"

    public var invalidMessage: String {
        switch self {
        case .enabled: "启用需要 Team ID、Key ID 与私钥"
        case .teamID: "Team ID 应为 10 位大写字母或数字"
        case .keyID: "Key ID 应为 10 位大写字母或数字"
        case .privateKey: "私钥应为 APNs 的 .p8（P-256）文件内容"
        case .topic: "Topic 应为 App 的包名（Bundle ID）"
        case .environment: "环境只能是 production 或 sandbox"
        }
    }
}

/// A failed save of the APNs settings: `field` nil is shown for the whole form.
public struct PushFieldFailure: Sendable, Equatable {
    public let field: PushAPNsField?
    public let message: String
    public init(field: PushAPNsField?, message: String) { self.field = field; self.message = message }
}

/// 60 §7.3–§7.5 wording for the push settings page.
public enum PushPresentation {
    public static let notReadyBanner = "站点还没配好 APNs，本机收不到推送。可改用 Bark / ntfy / Webhook，或在下方配置 APNs。"
    public static let localToggleNeedsAPNs = "站点配好 APNs 后才能打开"
    public static let systemPermissionDenied = "系统设置里关闭了通知 · 去设置"
    public static let sendTest = "发送测试推送"
    public static let testSent = "已发送测试推送，请看通知"
    public static let pausedNote = "已暂停推送"
    public static let groupScopeNote = "全站告警不受范围限制"
    public static let footer = "同一账号出错 30 分钟内最多推一次；推送最多晚约 15 秒；测试完成只推给发起测试的人。"
    public static let disabledBadge = "已停用"
    public static let addTarget = "+ 添加其他接收方式"
    public static let loadFailed = "加载失败 · 重试"
    /// 00 §7.6: a deletion that failed when signing out is retried at the next sign-in.
    public static let pendingDeletionNotice = "有设备未能从站点移除，可在 Web 删除"
    public static let buildWithoutPush = "这个 App 构建没有开启推送能力；APNs 只适用于用站点同一 Apple Team 的 p8 私钥构建的 App。可改用 Bark / ntfy / Webhook。"
    /// Also the note on a greyed-out .p8 import while `encryption_key_configured` is false.
    public static let encryptionKeyMissing = "站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存"

    // MARK: This phone

    /// A failed config read (nil) shows no banner and leaves the switch usable.
    public static func showsNotReadyBanner(_ config: PushAPNsConfig?) -> Bool { config?.ready == false }
    public static func canEnableLocal(_ config: PushAPNsConfig?) -> Bool { config?.ready != false }
    public static func localDevice(registeredID: Int?, in devices: [PushDevice]) -> PushDevice? {
        registeredID.flatMap { id in devices.first { $0.id == id } }
    }
    /// `devices` nil is a list not loaded yet: a stored id still counts as on.
    public static func localState(registeredID: Int?, devices: [PushDevice]?) -> PushLocalState {
        guard let registeredID else { return .off }
        guard let devices else { return .on }
        guard let device = localDevice(registeredID: registeredID, in: devices) else { return .off }
        return device.enabled ? .on : .disabled
    }
    /// `timeZone` is the server's (00 §6.3). The backend keeps `last_error` after a later delivery, so an error older than
    /// `last_success_at` is left out.
    public static func statusLine(_ device: PushDevice, timeZone: TimeZone) -> String {
        let delivered = device.lastSuccessAt.map { "上次送达 " + timestamp($0, timeZone: timeZone) } ?? "还没有送达记录"
        let state = device.enabled ? "已开启 · " + delivered : disabledText(device.disabledReason)
        guard let error = device.lastError.flatMap({ singleLine($0, limit: 300) }) else { return state }
        if let failed = device.lastErrorAt, let succeeded = device.lastSuccessAt, failed < succeeded { return state }
        return state + " · 最近失败：" + error
    }
    public static func disabledText(_ reason: PushDisabledReason?) -> String {
        switch reason {
        case .unregistered: "设备令牌已失效，关掉再打开即可恢复"
        case .badDeviceToken: "设备令牌无效"
        case .topicMismatch: "App 的包名与站点 APNs 配置不符"
        case .secretUndecryptable: "站点更换了加密密钥，关掉再打开即可恢复"
        case .endpointGone, .other, nil: disabledBadge
        }
    }

    // MARK: Subscription

    public static func eventTitle(_ event: PushEvent) -> String {
        switch event {
        case .opsAlertFired: "告警触发"
        case .opsAlertResolved: "告警恢复"
        case .accountError: "账号出错"
        case .accountTestFinished: "账号测试完成"
        }
    }
    public static func severityTitle(_ severity: PushSeverity) -> String { severity.rawValue }
    public static func severitySummary(_ severity: PushSeverity) -> String { severity.rawValue + " 及以上" }
    /// `name` is the platform catalog's (S6-24 passes `AccountNaming.platformName`).
    public static func platformScope(_ platforms: [String], name: (String) -> String = GroupPlatform.title) -> String {
        platforms.isEmpty ? "全部平台" : platforms.map(name).joined(separator: "、")
    }
    public static func groupScope(_ groupIDs: [Int], name: (Int) -> String?) -> String {
        guard let first = groupIDs.first else { return "全部分组" }
        let title = name(first) ?? "分组 #\(first)"
        return groupIDs.count == 1 ? title : "\(title) 等 \(groupIDs.count) 个"
    }
    /// The backend reads quiet hours in the target's zone, UTC when it has none.
    public static func quietHoursNote(timezone: String?) -> String {
        let zone = nonBlank(timezone).map { "按本机时区 " + $0 } ?? "按 UTC 时区"
        return zone + "；时段内的事件不补推"
    }

    // MARK: Targets

    /// `device_name`, then `endpoint_host`, then the platform (an iOS target has no host).
    public static func targetName(_ device: PushDevice) -> String {
        nonBlank(device.deviceName) ?? nonBlank(device.endpointHost) ?? platformTitle(device)
    }
    public static func platformTitle(_ device: PushDevice) -> String {
        switch device.platform {
        case .ios: "iOS"
        case .bark: "Bark"
        case .ntfy: "ntfy"
        case .webhook: "Webhook"
        case nil: nonBlank(device.rawPlatform) ?? DisplayFormat.missing
        }
    }
    public static func symbolName(_ platform: PushPlatform?) -> String {
        switch platform {
        case .ios: "iphone"
        case .bark: "app.badge"
        case .ntfy: "bell.badge"
        case .webhook: "link"
        case nil: "bell"
        }
    }
    /// Subtitle “ntfy · ntfy.sh”, or “iOS · …a3f0” for a target without a host.
    public static func targetRow(_ device: PushDevice) -> PushTargetRow {
        let platform = platformTitle(device)
        let detail = nonBlank(device.endpointHost) ?? nonBlank(device.tokenHint).map { "…" + $0 }
        return PushTargetRow(id: device.id, platform: device.platform, symbolName: symbolName(device.platform), title: targetName(device),
                             subtitle: detail.map { platform + " · " + $0 } ?? platform, isDisabled: !device.enabled)
    }
    /// In the server's order (by id), without this phone's target.
    public static func otherTargets(_ devices: [PushDevice], localID: Int?) -> [PushTargetRow] {
        devices.filter { $0.id != localID }.map(targetRow)
    }
    /// A read-only `sat_` may register only this phone.
    public static func showsAddTarget(isReadOnlyToken: Bool) -> Bool { !isReadOnlyToken }

    // MARK: Site APNs settings

    public static func apnsRows(_ config: PushAPNsConfig) -> PushAPNsConfigRows {
        PushAPNsConfigRows(teamID: config.teamID ?? DisplayFormat.missing, keyID: config.keyID ?? DisplayFormat.missing,
                           privateKey: config.privateKeyConfigured ? "已配置" : "未配置", topic: config.topic ?? "跟随 App 包名",
                           environment: config.environment.rawValue, status: config.ready ? "可用" : "未就绪", statusTone: config.ready ? .ok : .caution)
    }
    /// The rule for revealing a key (30 章): not a read-only token, and step-up off or possible. An unknown switch (old
    /// server) is editable, as StepUpPolicy sends without asking.
    public static func apnsEditability(isReadOnlyToken: Bool, security: AdminMe.Security, authMethod: AdminAuthMethod?) -> PushAPNsEditability {
        if isReadOnlyToken { return .disabled("只读令牌") }
        if security.stepUpEnabled != true || security.stepUpAvailable == true { return .available }
        if authMethod?.isMachineCredential == true { return .disabled("站点开启了二次验证，需要邮箱和密码登录才能修改") }
        return .disabled(StepUpPolicy.totpNotEnabledTitle)
    }

    // MARK: Failures (60 §7.4)

    /// Registering, testing and subscribing. A reason whose field is a programming error (bundle_id, apns_token, body…) keeps
    /// the catalog's parameter text, as does every answer not listed here.
    public static func failureMessage(_ error: any Error) -> String {
        guard let apiError = error as? APIError, let status = apiError.statusCode else { return error.localizedDescription }
        let field = apiError.metadata["field"]
        switch (status, apiError.reason) {
        case (400, "INVALID_PUSH_TARGET"?) where field == nil || field == "endpoint":
            return "地址不被允许：默认只接受公网 https 地址（局域网或 http 需站长打开 push_targets 配置）"
        case (400, "INVALID_PUSH_TOKEN"?) where field == "token": return "设备 Key / 主题格式不对"
        case (403, "ACCESS_TOKEN_READ_ONLY"?) where field == "platform": return "只读令牌只能登记本机推送"
        case (409, "PUSH_TARGET_IN_USE"?): return "这个接收地址已由另一位管理员登记"
        case (409, "PUSH_DEVICE_LIMIT_REACHED"?):
            let limit = apiError.metadata["max"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil } ?? 20
            return "最多 \(limit) 个推送目标，先删除不用的"
        case (503, "PUSH_NOT_CONFIGURED"?): return "站点没有配好 APNs"
        case (502, "PUSH_DELIVERY_FAILED"?):
            return deliveryFailureText(providerReason: apiError.metadata["provider_reason"], providerStatus: apiError.metadata["provider_status"])
        default: return apiError.localizedDescription
        }
    }
    /// “推送服务没有接受：BadDeviceToken（400）”. The reason may come from any webhook peer, so it is kept to one line of 120
    /// characters; status 0 (a network error) is left out.
    public static func deliveryFailureText(providerReason: String?, providerStatus: String?) -> String {
        let status = providerStatus.flatMap { Int($0) }.flatMap { $0 > 0 ? "（\($0)）" : nil } ?? ""
        guard let reason = providerReason.flatMap({ singleLine($0, limit: 120) }) else { return "推送服务没有接受" + status }
        return "推送服务没有接受：" + reason + status
    }
    public static func apnsConfigFailure(_ error: any Error) -> PushFieldFailure {
        if let apiError = error as? APIError, apiError.statusCode == 400 {
            if apiError.reason == "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED" { return PushFieldFailure(field: .privateKey, message: encryptionKeyMissing) }
            if apiError.reason == "INVALID_APNS_CONFIG", let field = apiError.metadata["field"].flatMap(PushAPNsField.init(rawValue:)) {
                return PushFieldFailure(field: field, message: field.invalidMessage)
            }
        }
        return PushFieldFailure(field: nil, message: failureMessage(error))
    }

    // MARK: Internals

    /// “10/17 09:41” in the server's zone; S6-26 moves this to DisplayFormat.monthDayClock (S6D1-16).
    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.month, .day], from: date)
        return pad(day.month ?? 0) + "/" + pad(day.day ?? 0) + " " + DisplayFormat.clock(date, timeZone: timeZone)
    }
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
    /// Control characters become spaces and whitespace runs one space; nil when nothing is left.
    private static func singleLine(_ text: String, limit: Int) -> String? {
        let words = text.components(separatedBy: .controlCharacters).joined(separator: " ").split(whereSeparator: \.isWhitespace)
        return nonBlank(String(words.joined(separator: " ").prefix(limit)))
    }
    private static func nonBlank(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
