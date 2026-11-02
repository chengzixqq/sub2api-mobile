import Foundation

/// 3.5 核对's finding while the result stays open.
public enum GroupEditCheck: Sendable, Equatable { case notFound, differs, failed }

/// 50 §3 (S5-10): the group sheet's fixed words. The confirmations and receipts are GroupCopy's, refusals GroupErrorCopy's.
public enum GroupEditCopy {
    public static func title(isNew: Bool) -> String { isNew ? "新建分组" : "编辑分组" }
    public static func submitTitle(isNew: Bool) -> String { isNew ? "创建" : "保存" }
    public static let basicSection = "基本", billingSection = "计费", limitsSection = "订阅限额 · 每个订阅"
    public static let billingFixed = "创建后不能修改"
    public static let namePlaceholder = "必填", descriptionPlaceholder = "可选", rpmPlaceholder = "不限", limitPlaceholder = "无限制"
    public static let rateInvalidHint = "要大于 0"

    /// 3.3 基本区脚注: what 专属 / 公开 means, then the new group's sentence, or 停用's while an edit has it off. A hidden field says
    /// nothing; simple mode creates with a platform only (S5D2a-13).
    public static func basicFootnote(isNew: Bool, isExclusive: Bool, isActive: Bool, showsExclusive: Bool, showsStatus: Bool, isSimpleMode: Bool) -> String {
        if isSimpleMode { return isNew ? "平台创建后不能修改。" : "" }
        var parts: [String] = []
        if showsExclusive { parts.append(isExclusive ? "专属：只有分配了这个分组的用户能选它。" : "公开：所有用户新建 API 密钥时都能选它。") }
        if isNew {
            parts.append("创建后立即可用，需要时可在详情里停用。平台和计费类型创建后不能修改；组合路由（Composite）分组在 Web 中创建。")
        } else if showsStatus, !isActive {
            parts.append("停用：使用这个分组的 API 密钥会被拒绝。")
        }
        return parts.joined()
    }
    public static let billingFootnote = "费率倍数：1.0 = 标准费率，0.5 = 半价，2.0 = 双倍。每用户 RPM：每位用户在本分组每分钟最多请求数，留空或 0 = 不限。"
    /// A vendor that may not change billing reads GroupPermissions.billingNote instead.
    public static func billingFootnote(managedNote: String?) -> String { managedNote ?? billingFootnote }
    public static let limitsFootnote = "留空 = 无限制；超过限额的订阅请求会被拒绝。"
    public static let standardBillingNote = "标准（余额）计费从用户余额扣除，没有订阅限额。"
    public static let webNote = "模型白名单、组合路由、图片计费、客户端限制在 Web 中编辑。"

    public static let loading = "正在读取分组…", saving = "正在保存…", confirming = "正在确认结果…", checking = "正在核对…"
    /// While a keyed write runs: transport retries, then the server still working on the same key.
    public static func savingText(_ event: KeyedWriteEvent?) -> String {
        switch event {
        case .confirming?: confirming
        case .waitingForServer(let seconds)?: "服务器仍在处理 · 已等待 \(seconds) 秒"
        case .actionID?, nil: saving
        }
    }
    public static let reconcile = "读取服务器状态核对", retrySame = "用同一编号重试"
    /// A keyed write offers its own number again (or says to wait for it); an unkeyed one only the check.
    public static func unconfirmedText(_ error: any Error, keyed: Bool) -> String {
        if let failure = error as? KeyedWriteFailure, let text = failure.errorDescription { return text }
        return keyed ? KeyedWriteFailure.unconfirmedMessage : "结果未确认：服务器可能已执行。请先读取服务器状态核对，本页不会再自动发送。"
    }
    public static func checkNote(_ check: GroupEditCheck) -> String {
        switch check {
        case .notFound: "服务器上还没有找到这个分组，可能仍在处理。"
        case .differs: "服务器上的分组还不是这次的修改。"
        case .failed: "核对没有完成，请稍后再试。"
        }
    }
    /// An unkeyed write the check shows did not happen: the form is open again, the next save a new request.
    public static func notApplied(isNew: Bool) -> String { isNew ? "服务器上没有这次的新建，可以重新创建。" : "服务器上没有这次的修改，可以重新保存。" }
    /// The server would not take the number (KEY_CONFLICT and the like): nothing ran.
    public static func reconfirm(isNew: Bool) -> String { isNew ? "请求没有执行，请重新创建。" : "请求没有执行，请重新保存。" }
    public static let discardTitle = "放弃修改？", discardConfirm = "放弃修改", keepEditing = "继续编辑"
    public static let unconfirmedCloseTitle = "结果未确认", keepChecking = "继续核对", checkLater = "稍后核对"
    /// 00 §2.5.4: closing with the result open lets go of the number; the list reads again.
    public static func unconfirmedCloseMessage(isNew: Bool) -> String {
        isNew ? "服务器可能已经创建了这个分组。关闭后不再保留这次的编号，分组列表会重新读取；再次新建前先在列表里核对，避免重复。"
            : "服务器可能已经保存了这次修改。关闭后分组列表会重新读取，再次修改前先在详情里核对。"
    }
}
