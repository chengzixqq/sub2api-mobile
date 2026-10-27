import Foundation

/// 10 §1.3.1, §1.3.2, §7.2, U10, U12: the wording of 运维监控未开启 everywhere in the App (the home line, the monitor's sections, the
/// alert detail, chapter 40), whether to offer the switch, and what a switch write ended with. The reason is S1-02's
/// OpsDisabledReason; which endpoint writes is S1-02's OpsMonitoringWriteRoute (S1D1-01, S1D1-07). No server message is shown.
public enum OpsDisabledPresentation {
    public struct EmptyState: Sendable, Equatable {
        public let title: String
        public let detail: String?
        public let actionTitle: String?
        public init(title: String, detail: String?, actionTitle: String?) { self.title = title; self.detail = detail; self.actionTitle = actionTitle }
    }
    public struct Confirmation: Sendable, Equatable {
        public let title: String
        public let message: String
        public let confirmTitle: String
        public let isDestructive: Bool
        public init(title: String, message: String, confirmTitle: String, isDestructive: Bool) {
            self.title = title; self.message = message; self.confirmTitle = confirmTitle; self.isDestructive = isDestructive
        }
    }
    /// How a switch write ended; each one is shown as a receipt.
    public enum ToggleOutcome: Sendable, Equatable {
        case enabled, disabled, configOff, failed(String), unconfirmed

        public var receiptText: String {
            switch self {
            case .enabled: OpsDisabledPresentation.enabledReceipt
            case .disabled: OpsDisabledPresentation.disabledReceipt
            case .configOff: OpsDisabledPresentation.configOffText
            case .failed(let text): text
            case .unconfirmed: OpsDisabledPresentation.unconfirmedMessage
            }
        }
        public var receiptTone: Tone {
            switch self {
            case .enabled, .disabled: .ok
            case .configOff: .neutral
            case .failed: .critical
            case .unconfirmed: .caution
            }
        }
        public var receiptImage: String {
            switch self {
            case .enabled: "waveform.path.ecg"
            case .disabled: "checkmark.circle"
            case .configOff: "server.rack"
            case .failed, .unconfirmed: "exclamationmark.triangle"
            }
        }
    }

    public static let title = "运维监控未开启"
    public static let inlineActionTitle = "开启"
    public static let emptyStateActionTitle = "开启运维监控"
    public static let dataGapNote = "关闭期间不会记录错误请求，开启后也不会补回"
    public static let configOffText = "运维监控已在服务器配置中关闭"
    public static let enabledReceipt = "已开启运维监控"
    public static let disabledReceipt = "已关闭运维监控"
    public static let readOnlyMessage = "只读访问令牌不能修改设置"
    public static let permissionMessage = "当前身份没有修改运维设置的权限"
    public static let unconfirmedMessage = "结果未确认，请刷新核对后再操作"
    public static let notEnabledMessage = "运维监控未能开启，请重试"
    public static let notDisabledMessage = "运维监控未能关闭，请重试"
    public static let unsupportedMessage = "站点版本较旧，暂不支持此功能"

    private static let homeLine = "运维监控未开启 · 错误率与告警不可用，RPM 只计成功请求"
    private static let tpmNote = " · TPM 不含缓存 Tokens"
    private static let settingOffDetail = "错误率、告警、服务器状态与错误日志都不可用"
    private static let configOffDetail = "需要在服务器配置中启用（ops.enabled=false）"

    /// 10 §1.3.1 under the six tiles; fallback ③ (TPM without cache tokens) adds its footnote whatever the reason (§1.3.2).
    public static func inlineText(reason: OpsDisabledReason, tpmExcludesCache: Bool) -> String {
        (reason == .configOff ? configOffText : homeLine) + (tpmExcludesCache ? tpmNote : "")
    }
    /// 10 §7.2's table as a title and a detail; the monitor and the alert detail add the data gap on its own line.
    public static func emptyState(reason: OpsDisabledReason, offersEnable: Bool, notesDataGap: Bool) -> EmptyState {
        let base: (title: String, detail: String?) = switch reason {
        case .settingOff: (title, settingOffDetail)
        case .configOff: (configOffText, configOffDetail)
        case .unknown: (title, nil)
        }
        let detail = notesDataGap ? [base.detail, dataGapNote].compactMap { $0 }.joined(separator: "\n") : base.detail
        return EmptyState(title: base.title, detail: detail, actionTitle: offersEnable ? emptyStateActionTitle : nil)
    }
    /// 10 §7.2: the owner, unless the server configuration holds it off or the site has no safe write (S1D1-07).
    public static func offersEnable(reason: OpsDisabledReason, isAdministrator: Bool, route: OpsMonitoringWriteRoute) -> Bool {
        isAdministrator && reason != .configOff && route != .unavailable
    }
    /// U10: only the owner, only through `monitoring-status`, only while monitoring is on.
    public static func offersDisable(isAdministrator: Bool, route: OpsMonitoringWriteRoute, isOpsDisabled: Bool) -> Bool {
        isAdministrator && route == .monitoringStatus && !isOpsDisabled
    }
    /// The old-server conclusion (D09) first, then the latest `monitoring-status` reply that says off, then `/admin/me`'s snapshot.
    public static func reason(status: OpsMonitoringStatus?, legacyConfigOff: Bool, features: AdminMe.Features) -> OpsDisabledReason {
        if legacyConfigOff { return .configOff }
        if let status, status.effective != true { return status.reason }
        if features.opsMonitoringEnabled == false { return OpsDisabledReason(rawReason: features.opsMonitoringDisabledReason) }
        return .unknown
    }

    public static let enableConfirmation = Confirmation(title: "开启运维监控？", message: "开启后开始记录错误请求、告警与服务器指标；关闭期间的数据不会补回。",
                                                        confirmTitle: "开启", isDestructive: false)
    public static let disableConfirmation = Confirmation(
        title: "关闭运维监控？", message: "关闭后不再记录错误请求、告警与服务器指标，概览的错误率与告警、监控各段都不可用；关闭期间的数据开启后也不会补回。",
        confirmTitle: "关闭运维监控", isDestructive: true)
    public static func disableFinalConfirmation(siteName: String) -> Confirmation {
        Confirmation(title: "确认关闭「\(siteName)」的运维监控？", message: "这会关闭整个站点的运维监控，对所有管理员生效。", confirmTitle: "仍要关闭", isDestructive: true)
    }

    /// 10 §7.2 step 3.
    public static func enableOutcome(_ status: OpsMonitoringStatus) -> ToggleOutcome {
        if status.effective == true { return .enabled }
        return status.reason == .configOff ? .configOff : .failed(notEnabledMessage)
    }
    public static func disableOutcome(_ status: OpsMonitoringStatus) -> ToggleOutcome {
        status.effective == true ? .failed(notDisabledMessage) : .disabled
    }
    /// 10 §7.2 step 4; nil for a cancellation. Any other failure says the catalog text (a cleared compliance prompt included).
    public static func failureOutcome(_ error: any Error) -> ToggleOutcome? {
        if error is CancellationError { return nil }
        guard let error = error as? APIError, !needsReadBack(error) else { return .unconfirmed }
        switch (error.statusCode, error.reason) {
        case (409?, "OPS_CONFIG_DISABLED"?): return .configOff
        case (403?, "ACCESS_TOKEN_READ_ONLY"?): return .failed(readOnlyMessage)
        case (403?, _): return .failed(permissionMessage)
        default: return .failed(error.localizedDescription)
        }
    }
    /// 00 §2.4, an unkeyed write without an answer: no answer at all, or a gateway's 502 / 503 / 504 (not a security refusal).
    public static func needsReadBack(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        guard let error = error as? APIError else { return true }
        guard let status = error.statusCode else { return error.kind == .transport }
        return [502, 503, 504].contains(status) && SecurityInterruption(error) == nil
    }
}
