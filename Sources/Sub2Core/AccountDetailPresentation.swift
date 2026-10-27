import Foundation

/// 20 §2.3 按钮行 actions, with 20 §0.3's words. The raw value names the button (`account.action.<raw>`).
public enum AccountDetailAction: String, Sendable, CaseIterable, Identifiable {
    case test
    case stopScheduling = "stop"
    case resumeScheduling = "resume"
    case enableAccount = "enable"
    case recover, replaceKey, reauthorize, webCredential
    /// S2D1-20: an account paused by its expiry is fixed by its expiry time, not by the switch.
    case editExpiry

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .test: "测试连接"
        case .stopScheduling: AccountActionKind.setSchedulable(false).verb
        case .resumeScheduling: AccountActionKind.setSchedulable(true).verb
        case .enableAccount: AccountActionKind.enableAccount.verb
        case .recover: AccountActionKind.recover.verb
        case .replaceKey: "更换 API Key…"
        case .reauthorize: "重新授权…"
        case .webCredential: "在 Web 中更换凭据"
        case .editExpiry: "修改过期时间…"
        }
    }
    /// Design ActionButton icons: wave, pauseFill, play, restore, key.
    public var systemImage: String {
        switch self {
        case .test: "waveform.path"
        case .stopScheduling: "pause.fill"
        case .resumeScheduling, .enableAccount: "play.fill"
        case .recover: "arrow.counterclockwise"
        case .replaceKey, .reauthorize: "key"
        case .webCredential: "safari"
        case .editExpiry: "calendar.badge.clock"
        }
    }
}

/// The primary button leads; the rest follow in the design's order.
public struct AccountDetailActionRow: Sendable, Equatable {
    public let primary: AccountDetailAction
    public let secondary: [AccountDetailAction]
    public var actions: [AccountDetailAction] { [primary] + secondary }
    public init(primary: AccountDetailAction, secondary: [AccountDetailAction]) { self.primary = primary; self.secondary = secondary }
}

/// 20 §2.3 状态卡 (`detail-head`): a quiet line for 正常 / 暂停 / 停用, the big badge card for 错误 and the timed states.
public struct AccountStatusCardContent: Sendable, Equatable {
    public enum Style: Sendable, Equatable { case quiet, alert }
    public struct ScheduleNote: Sendable, Equatable {
        /// “已停止调度” / “出错时已自动停止调度”, set in bold.
        public let emphasis: String
        public let detail: String
        public init(emphasis: String, detail: String) { self.emphasis = emphasis; self.detail = detail }
    }
    public struct ModelLimitRow: Sendable, Equatable {
        public let model: String
        /// “12 分钟后” / “1 小时 5 分钟后”.
        public let remaining: String
        public init(model: String, remaining: String) { self.model = model; self.remaining = remaining }
    }
    public let style: Style
    public let state: AccountScheduleState
    public let tone: Tone
    /// Quiet: the whole line; alert: the status word of the big badge.
    public let title: String
    /// Beside the badge: “上游 429”, “上游 529 · 规则 #1”; for 错误 “上游 {error_status_code}” when the server sent one.
    public let cause: String?
    public let countdownTarget: Date?
    public let countdown: String?
    /// “后自动恢复 · 预计 HH:MM” in the server's time zone.
    public let resumeNote: String?
    /// `error_summary`, or “上游返回异常”; never `error_message` (R12).
    public let errorBody: String?
    public let scheduleNote: ScheduleNote?
    /// “模型限流 N”; nil when no model limit is running, on any card (a model limit is not an account state).
    public let modelLimitsTitle: String?
    public let modelLimits: [ModelLimitRow]
}

/// 20 §2.5, in order: removed, then any account (the list's snapshot carries a banner only while it is all there is and the
/// read failed; a failed refresh of server data says nothing, like the list's runtime), then the read's failure, then skeletons.
public enum AccountDetailPageState: Sendable, Equatable {
    case skeleton
    case content(banner: String?)
    case failure(message: String)
    case removed

    public static func resolve(hasAccount: Bool, loadedFromServer: Bool, failure: String?, removed: Bool) -> AccountDetailPageState {
        if removed { return .removed }
        if hasAccount { return .content(banner: !loadedFromServer && failure != nil ? AccountDetailPresentation.snapshotBanner : nil) }
        if let failure { return .failure(message: failure) }
        return .skeleton
    }
}

/// 20 §2.6: the detail's 60-second light refresh, with the list's runtime merge and change rule (AccountListRefresh) for one id.
public enum AccountDetailRefresh {
    public static let interval: TimeInterval = 60

    public enum Outcome: Sendable {
        /// Only the runtime fields changed.
        case merged(UpstreamAccount)
        /// The reply left the account out (deleted, out of scope) or its status or switch changed: read it again.
        case reload
    }

    public static func apply(_ runtime: [Int: AccountRuntime], to account: UpstreamAccount) -> Outcome {
        guard !AccountListRefresh.needsFullRefresh([account], runtime: runtime),
              let merged = AccountListRefresh.merging([account], runtime: runtime).first else { return .reload }
        return .merged(merged)
    }
    /// Seconds to wait before the next light refresh, from the device time since the last sync (20 §0.6); a clock that moved
    /// back waits a whole interval.
    public static func delay(sinceLastRefresh elapsed: TimeInterval?) -> TimeInterval {
        guard let elapsed else { return 0 }
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}

/// 20 §2.1–§2.5: what the account detail's top half shows. `now` is always the site's ServerClock time (20 §0.6).
public enum AccountDetailPresentation {
    public static let snapshotBanner = "读取最新数据失败，显示的是列表里的快照"
    public static let loadFailedTitle = "读取账号失败"
    public static let removedMessage = "这个账号已删除。"
    public static let removedTitle = "账号"
    public static let removedSubtitle = "已删除"

    public static func statusCard(_ account: UpstreamAccount, now: Date, timeZone: TimeZone) -> AccountStatusCardContent {
        let display = AccountDisplayState(account, now: now)
        let limits = display.modelRateLimits.map {
            AccountStatusCardContent.ModelLimitRow(model: $0.model, remaining: DisplayFormat.minutesLeft($0.resetAt.timeIntervalSince(now)) + "后")
        }
        let limitsTitle = limits.isEmpty ? nil : "模型限流 \(limits.count)"
        func content(_ style: AccountStatusCardContent.Style, title: String, cause: String? = nil, target: Date? = nil, errorBody: String? = nil,
                     note: AccountStatusCardContent.ScheduleNote? = nil) -> AccountStatusCardContent {
            AccountStatusCardContent(style: style, state: display.state, tone: display.tone, title: title, cause: cause, countdownTarget: target,
                                     countdown: target.map { DisplayFormat.countdown(until: $0, now: now) },
                                     resumeNote: target.map { "后自动恢复 · 预计 \(DisplayFormat.clock($0, timeZone: timeZone))" },
                                     errorBody: errorBody, scheduleNote: note, modelLimitsTitle: limitsTitle, modelLimits: limits)
        }
        switch display.state {
        case .available: return content(.quiet, title: "正常 · 参与调度")
        case .paused: return content(.quiet, title: display.isExpiredPause ? "暂停 · 已过期，自动暂停调度" : "暂停 · 不参与调度")
        case .inactive: return content(.quiet, title: "停用 · 不参与调度")
        case .error:
            let note = account.schedulable ? nil : AccountStatusCardContent.ScheduleNote(emphasis: "出错时已自动停止调度", detail: "恢复时可一并启用")
            return content(.alert, title: display.label, cause: account.errorStatusCode.map { "上游 \($0)" },
                           errorBody: display.reason ?? AccountDisplayState.unknownErrorReason, note: note)
        case .overloaded, .rateLimited, .tempUnschedulable:
            let note = display.isStopped ? AccountStatusCardContent.ScheduleNote(emphasis: AccountDisplayState.stoppedMark, detail: "到时恢复后也不参与调度") : nil
            return content(.alert, title: display.label, cause: display.reason, target: display.countdownTarget, note: note)
        }
    }

    /// 20 §2.3 按钮行; `keyReplaced` is S2-16's “本次已更换 Key” mark.
    public static func actionRow(_ account: UpstreamAccount, now: Date, keyReplaced: Bool = false) -> AccountDetailActionRow {
        let display = AccountDisplayState(account, now: now)
        switch display.state {
        case .available: return AccountDetailActionRow(primary: .test, secondary: [.stopScheduling])
        case .inactive: return AccountDetailActionRow(primary: .enableAccount, secondary: [.test])
        case .paused: return AccountDetailActionRow(primary: isPausedByExpiry(account, now: now) ? .editExpiry : .resumeScheduling, secondary: [.test])
        case .error:
            guard display.isCredentialError else { return AccountDetailActionRow(primary: .recover, secondary: [.test]) }
            if keyReplaced { return AccountDetailActionRow(primary: .test, secondary: [.recover]) }
            return AccountDetailActionRow(primary: credentialFix(account), secondary: [.recover, .test])
        case .overloaded, .rateLimited, .tempUnschedulable:
            return AccountDetailActionRow(primary: .recover, secondary: [.test, account.schedulable ? .stopScheduling : .resumeScheduling])
        }
    }

    /// “{平台显示名} · {类型显示名}” (20 §2.1, §0.3).
    public static func subtitle(_ account: UpstreamAccount, catalog: MetaCatalog?) -> String {
        "\(AccountNaming.platformName(account.platform, catalog: catalog)) · \(AccountNaming.typeName(platform: account.platform, type: account.type))"
    }

    /// 404 ACCOUNT_NOT_FOUND only; a vendor's 404 RESOURCE_NOT_FOUND is a permission, and a non-JSON 404 an unsupported site.
    public static func isRemoved(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == AccountWriteReason.notFound
    }

    /// U17: Bedrock and Vertex credentials are changed on the web; token accounts are authorized again.
    private static func credentialFix(_ account: UpstreamAccount) -> AccountDetailAction {
        if account.type == "bedrock" || account.type == "service_account" { return .webCredential }
        return account.isTokenAccount ? .reauthorize : .replaceKey
    }
    /// Whatever the switch: the backend's IsSchedulable stops an expired account with auto-pause on (S2D1-20).
    private static func isPausedByExpiry(_ account: UpstreamAccount, now: Date) -> Bool {
        let input = AccountStateInput(account)
        guard input.autoPauseOnExpired == true, let expiresAt = input.expiresAt else { return false }
        return expiresAt <= now
    }
}
