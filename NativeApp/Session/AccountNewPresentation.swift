import Foundation
import Sub2Core

/// 20 §7.1 / §7.3 the glass dock: what is missing (tapping it scrolls to the first), or the stage of the create, and its buttons.
struct AccountNewDockContent: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case create(enabled: Bool)
        /// The same key and bytes again (a keyed site).
        case retrySameKey
        /// The same bytes again on a site without keys, after the check found nothing.
        case resend
        case reconcile
        case retryPause
        var title: String {
            switch self {
            case .create: AccountNewFlow.dockActionTitle(isCreated: false, hasChanges: false)
            case .retrySameKey: "用同一编号重试"
            case .resend: "重试"
            case .reconcile: "核对"
            case .retryPause: "重试停止调度"
            }
        }
        var isEnabled: Bool { if case .create(let enabled) = self { enabled } else { true } }
    }

    let title: String
    let detail: String?
    let tone: Tone?
    let showsProgress: Bool
    /// The text block is a button that scrolls to the first missing item.
    let jumpsToFirstMissing: Bool
    let primary: Action?
    let secondary: Action?
    let accessibilityLabel: String

    init(title: String, detail: String? = nil, tone: Tone? = nil, showsProgress: Bool = false, jumpsToFirstMissing: Bool = false,
         primary: Action? = nil, secondary: Action? = nil, accessibilityLabel: String? = nil) {
        self.title = title; self.detail = detail; self.tone = tone; self.showsProgress = showsProgress
        self.jumpsToFirstMissing = jumpsToFirstMissing; self.primary = primary; self.secondary = secondary
        self.accessibilityLabel = accessibilityLabel ?? [title, detail].compactMap { $0 }.joined(separator: "，")
    }

    /// `missing` is AccountNewDraft.missing's labels in order; `keyed` says whether the frozen request carries a key.
    static func make(stage: AccountNewSubmission.Stage, missing: [String], keyed: Bool) -> AccountNewDockContent {
        let ready = missing.isEmpty
        switch stage {
        case .idle, .confirmingMixedChannel:
            guard ready else { return missingItems(missing) }
            let isAsking = if case .confirmingMixedChannel = stage { true } else { false }
            return AccountNewDockContent(title: AccountNewCopy.readyTitle, detail: AccountNewCopy.readyDetail, primary: .create(enabled: !isAsking))
        case .checkingMixedChannel, .creating(confirming: false):
            return busy(AccountNewCopy.creating)
        case .creating(confirming: true):
            return busy(AccountNewCopy.confirming)
        case .pausing:
            return busy(AccountNewCopy.pausing)
        case .reconciling:
            return busy(AccountNewCopy.reconciling)
        case .rejected(let reason):
            guard ready else { return missingItems(missing) }
            return AccountNewDockContent(title: AccountNewCopy.rejectedTitle, detail: reason, tone: .critical, primary: .create(enabled: true))
        case .reconfirm(let notice):
            guard ready else { return missingItems(missing) }
            return AccountNewDockContent(title: notice, tone: .caution, primary: .create(enabled: true))
        case .unconfirmed(let reason):
            return AccountNewDockContent(title: AccountNewCopy.unconfirmedTitle, detail: reason, tone: .caution,
                                         primary: keyed ? .retrySameKey : .reconcile, secondary: keyed ? .reconcile : nil)
        case .notCreated:
            return AccountNewDockContent(title: AccountNewCopy.notCreatedTitle, tone: .caution, primary: keyed ? .retrySameKey : .resend)
        case .pauseUnconfirmed(let id, _):
            return AccountNewDockContent(title: AccountNewCopy.pauseUnconfirmedDockTitle, detail: AccountNewCopy.pauseUnconfirmedDockDetail(id: id),
                                         tone: .critical, primary: .retryPause)
        case .created(let id):
            return AccountNewDockContent(title: AccountNewCopy.createdDockTitle(id: id))
        }
    }

    private static func missingItems(_ missing: [String]) -> AccountNewDockContent {
        let names = missing.joined(separator: "、")
        return AccountNewDockContent(title: AccountNewCopy.missingTitle, detail: names, jumpsToFirstMissing: true, primary: .create(enabled: false),
                                     accessibilityLabel: "还差\(names)，跳到\(missing.first ?? "")")
    }
    private static func busy(_ title: String) -> AccountNewDockContent {
        AccountNewDockContent(title: title, showsProgress: true, primary: .create(enabled: false))
    }
}

/// 20 §7 copy that S2-18 does not already give (its confirmations, 还差 labels and subtitle are used as they are).
enum AccountNewCopy {
    static let title = "新建账号"
    static let missingTitle = "还差"
    static let readyTitle = "可以创建了"
    static let readyDetail = "创建后立即停止调度，测试通过再启用"
    static let creating = "正在创建账号…"
    static let confirming = "正在确认结果…"
    static let pausing = "账号已创建，正在停止调度…"
    static let reconciling = "正在核对创建结果…"
    static let rejectedTitle = "创建没有成功"
    static let unconfirmedTitle = "结果未确认"
    static let notCreatedTitle = "没有创建成功"
    static let pauseUnconfirmedDockTitle = "停止调度没有确认"
    static func pauseUnconfirmedDockDetail(id: Int) -> String { "账号 #\(id) 可能在接收请求" }
    static func createdDockTitle(id: Int) -> String { "账号 #\(id) 已创建 · \(AccountNewScheduleStatus.paused.title)" }

    // MARK: Sections

    static let selectPlatform = "选择平台"
    static let credentialFootnote = "Key 只提交到站点，App 不保存。"
    static let nameFootnote = "按平台自动起名，可以改。"
    static let pickPlatformFirst = "先选平台"
    static let platformsUnavailable = "当前身份不能新建账号"
    static func credentialsPlaceholder(platformPicked: Bool, isAccountMode: Bool) -> String {
        platformPicked ? "选好\(isAccountMode ? "账号类型" : "认证方式")后，在这里填写凭据" : "先选平台和认证方式"
    }
    static let lockedPlatform = "已创建，不能更换"
    static let lockedFootnote = "要换平台请删除后重建。"
    static func authorized(email: String?) -> String {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "已授权" : "已授权 · \(trimmed)"
    }
    static let loadFailed = "读取失败"
    static let retry = "重试"

    static func groupsTrailing(selected: Int, risky: Int) -> String {
        guard selected > 0 else { return "可不选" }
        return risky > 0 ? "已选 \(selected) · \(risky) 个需确认" : "已选 \(selected)"
    }
    static func riskFootnote(group: String, otherPlatform: String) -> String { "「\(group)」里已有 \(otherPlatform) 账号，创建时要确认混合渠道风险。" }
    static func noGroups(platformName: String) -> String { "没有可选的 \(platformName) 分组，不分组也能创建。" }
    static func groupsScope(platformName: String) -> String { "只列出 \(platformName) 分组和组合分组；停用的分组不列出。" }
    static func defaultGroupFootnote(platformID: String) -> String { "不选分组时，如果站点有「\(platformID)-default」分组会自动加入" }
    static let mixedSchedulingTitle = "在 /v1/messages 中使用"
    static let mixedSchedulingDetail = "开启后可加入 Anthropic / Gemini 分组"
    static let mixedSchedulingFootnote = "Antigravity Claude 和 Anthropic Claude 不能在同一上下文里用。开启后请用分组把两类账号隔开。"

    static let moreFootnote = "模型白名单与映射、自定义错误码、配额等，创建后在账号详情里设置。"
    static func moreLabel(isAntigravity: Bool) -> String { isAntigravity ? "过期时间、负载因子、AI Credits" : "过期时间、负载因子" }
    static func moreSummary(expiry: String?) -> String { expiry.map { "\($0) 到期" } ?? AccountExpiry.never }
    static let noProxy = "无代理"

    // MARK: Questions

    static let mixedTitle = "混合渠道警告"
    static let mixedContinue = "继续创建"
    static let mixedBack = "返回修改分组"
    static func pauseUnconfirmedTitle(name: String) -> String { "账号「\(name)」可能还在参与调度" }
    static func pauseUnconfirmedMessage(id: Int) -> String { "停止调度没有确认，账号 #\(id) 可能正在用未验证的凭据接收请求。" }
    static let pauseRetry = "重试停止调度"
    static let closeAnyway = "仍然关闭"
    static let keepHandling = "继续处理"
    static func createUnconfirmedTitle(name: String) -> String { "账号「\(name)」可能已经创建" }
    static let createUnconfirmedMessage = "创建结果没有确认。关闭后不能再用同一编号重试，再新建前请先到账号列表核对，避免重复创建。"
    static let pauseBannerTitle = "停止调度没有确认 · 结果待核对"
    static func pauseBannerDetail(id: Int) -> String { "账号 #\(id) 可能正在参与调度。" }

    // MARK: Receipts

    static func createdReceipt(name: String) -> (text: String, systemImage: String, tone: Tone) {
        ("已创建「\(name)」· \(AccountNewScheduleStatus.paused.title)", "pause.circle", .neutral)
    }
    static let viewAccount = "查看"
    static func groupsRemovedReceipt(count: Int) -> String { "已移除 \(count) 个不再适用的分组" }
    static func leftUnconfirmedReceipt(name: String) -> String { "「\(name)」停止调度没有确认 · 结果待核对" }
    static func leftCreateUnconfirmedReceipt(name: String) -> String { "「\(name)」创建结果未确认 · 请到账号列表核对" }
}
