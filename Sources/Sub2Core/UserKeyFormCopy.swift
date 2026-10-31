import Foundation

/// 30 §7.4 (S3-13): the words of 新建 / 编辑 / 删除 Key and 显示完整 Key. A refusal is placed by its reason, in fixed words;
/// the server's message is never shown (00 §3.4).
public enum UserKeyFormCopy {
    public enum Placement: Sendable, Equatable {
        case field(UserKeyField)
        /// The bottom of the form.
        case form
    }
    public struct Failure: Sendable, Equatable {
        public let placement: Placement
        public let message: String
        public init(placement: Placement, message: String) { self.placement = placement; self.message = message }
    }

    // MARK: 表单

    public static let createTitle = "新建 Key"
    public static let editTitle = "编辑 Key"
    public static let createAction = "创建"
    public static let saveAction = "保存"
    public static let discardTitle = "放弃这次填写？"
    public static let discardConfirm = "放弃"
    public static let discardKeep = "继续填写"
    public static let namePlaceholder = "例如：脚本"
    public static let amountPlaceholder = "0 = 不限"
    public static let customDaysPlaceholder = "天数（1–36500）"
    public static let ipPlaceholder = "每行一个 IP 或 CIDR"
    public static let ipFootnote = "每行一个 IP 或 CIDR，留空表示不限制。设了白名单后只有名单里的地址能调用。"
    public static let rateFootnote = "滚动窗口，单位美元；留空或 0 = 不限。"
    public static let resetQuotaTitle = "重置已用额度"
    public static let resetQuotaFootnote = "已用额度归零，不能撤销。"
    public static let editExpiryNever = "永久"
    public static let editExpiryDate = "选择日期"
    public static let groupFootnote = "选择需要授权的专属分组时，会同时为用户添加这个分组。"

    // MARK: 本地校验

    public static let nameRequired = "名称不能为空"
    public static let nameTooLong = "名称太长：最多 100 个字节，一个汉字算 3 个"
    public static let amountInvalid = "要填非负数，最多 8 位小数"
    public static let customDaysInvalid = "自定义天数要填 1–36500 的整数"
    public static let expiryPast = "有效期要晚于现在"
    public static func ipLineInvalid(_ line: Int) -> String { "第 \(line) 行不是有效的 IP 或 CIDR" }

    // MARK: 服务端拒绝

    public static let countExceeded = "这个用户的 Key 数量已达上限，请先删除不用的 Key"
    public static let createUnconfirmed = "结果未确认，请刷新后检查"
    public static let saveMismatch = "服务器上的 Key 与你的修改不一致，请检查后再保存"

    /// The draft that went out tells which IP list a refused pattern is in.
    public static func failure(_ error: APIError, draft: UserKeyDraft? = nil) -> Failure {
        switch (error.statusCode, error.reason) {
        case (400?, "API_KEY_NAME_REQUIRED"?): Failure(placement: .field(.name), message: nameRequired)
        case (400?, "API_KEY_LIMIT_INVALID"?): Failure(placement: .field(.quota), message: "额度和速率限制必须是非负数")
        case (400?, "API_KEY_EXPIRY_INVALID"?): Failure(placement: .field(.expiry), message: "有效期天数必须大于 0")
        case (400?, "INVALID_IP_PATTERN"?): Failure(placement: .field(ipField(draft)), message: "IP 或 CIDR 格式不对")
        case (_, "GROUP_NOT_ACTIVE"?): Failure(placement: .field(.group), message: "这个分组已停用")
        case (_, "SUBSCRIPTION_REQUIRED"?): Failure(placement: .field(.group), message: "用户没有这个分组的有效订阅")
        case (404?, "GROUP_NOT_FOUND"?): Failure(placement: .field(.group), message: "分组不存在")
        case (403?, "API_KEY_COUNT_EXCEEDED"?): Failure(placement: .form, message: countExceeded)
        case (404?, "USER_NOT_FOUND"?): Failure(placement: .form, message: "用户不存在或已删除")
        case (404?, "API_KEY_NOT_FOUND"?): Failure(placement: .form, message: "这个 Key 已被删除")
        default: Failure(placement: .form, message: error.localizedDescription)
        }
    }
    private static func ipField(_ draft: UserKeyDraft?) -> UserKeyField {
        guard let draft else { return .ipWhitelist }
        let invalid = { (text: String) in UserKeyForm.ipLines(text).contains { !UserKeyForm.isValidIPPattern($0) } }
        if invalid(draft.ipWhitelist) { return .ipWhitelist }
        if invalid(draft.ipBlacklist) || UserKeyForm.ipLines(draft.ipWhitelist).isEmpty { return .ipBlacklist }
        return .ipWhitelist
    }

    // MARK: 回执与“已立即生效”

    public static func created(_ name: String) -> String { "已创建「\(name)」" }
    /// Found in the list after a lost reply: its plaintext was never seen.
    public static func createdRecovered(_ name: String) -> String { "已创建「\(name)」；完整 Key 只能通过“显示完整 Key”查看" }
    public static func saved(_ name: String, resetQuota: Bool) -> String { "已保存「\(name)」" + (resetQuota ? "，已用额度的重置不能撤销" : "") }
    public static func savedUndone(_ name: String) -> String { "已撤销对「\(name)」的修改" }
    /// Named in the leave confirmation's “已经立即生效” (30 §6.4), like UserKeyChange.operationName.
    public static func createdOperation(_ name: String) -> String { "新建 Key「\(name)」" }
    public static func editedOperation(_ name: String) -> String { "Key「\(name)」修改" }
    public static func deletedOperation(_ name: String) -> String { "Key「\(name)」删除" }

    // MARK: 删除

    public static let objectNoun = "Key"
    public static func deleteSiteLine(siteName: String, userDisplayName: String) -> String { "站点 \(siteName) · 用户 \(userDisplayName)" }
    public static let deleteConsequence = "删除后这个 Key 立即不能调用，不能撤销。"

    // MARK: ⋯ 菜单与完整 Key

    public static let editAction = "编辑 Key…"
    public static let revealAction = "显示完整 Key…"
    public static let deleteAction = "删除 Key…"
    public static let createdTitle = "Key 已创建"
    public static let revealTitle = "完整 Key"
    public static let createdNotice = "完整 Key 只在这里显示一次；之后查看需要二次验证。"
    public static let revealNotice = "完整 Key 只在这里显示，关闭后不保留"
    public static let expiredNotice = "已超过 30 秒，明文已清除"
    public static let backgroundNotice = "已离开 App，明文已清除"
    public static let copyAction = "复制"
    public static let copiedNotice = "已复制，60 秒后从剪贴板清除"
    public static let doneAction = "完成"
    public static let revealGone = "这个 Key 已删除，没有可显示的内容"
    public static let biometricUnavailable = "这台设备没有设置 Face ID / 触控 ID，不能显示完整 Key"
    public static let stepUpPurpose = "显示完整 Key"
    /// The line under the system prompt.
    public static func revealReason(_ name: String) -> String { "显示「\(name)」的完整 Key" }
}

/// 30 §7.4 显示完整 Key (E03): needs `api_keys.masked_view`, and step-up the administrator can pass when the site has it on.
public enum UserKeyReveal {
    public enum Availability: Sendable, Equatable {
        case hidden, available
        /// Greyed, with the reason as its second line.
        case disabled(String)
    }
    public static let machineCredentialNotice = "Admin Key 登录不能查看完整 Key"
    public static let totpNotice = StepUpPolicy.totpNotEnabledTitle

    /// Step-up off or unknown (an older server decides by refusing), or one this login can pass.
    public static func availability(hasMaskedView: Bool, security: AdminMe.Security, authMethod: AdminAuthMethod?) -> Availability {
        guard hasMaskedView else { return .hidden }
        guard security.stepUpEnabled == true, security.stepUpAvailable != true else { return .available }
        if authMethod?.isMachineCredential == true { return .disabled(machineCredentialNotice) }
        return security.stepUpAvailable == false || security.totpEnabled == false ? .disabled(totpNotice) : .available
    }
}

/// 30 §7.4: a new key whose reply was lost is looked for in the list — same name, created after the send (within the clocks'
/// tolerance), not one of the keys already there; the newest wins.
public enum UserKeyCreateRecovery {
    public static let clockTolerance: TimeInterval = 5
    public static func match(in keys: [AdminAPIKey], request: AdminAPIKeyCreateRequest, startedAt: Date, knownIDs: Set<Int>) -> AdminAPIKey? {
        keys.filter { key in
            guard !knownIDs.contains(key.id), !key.isTombstone, key.displayName == request.name, let created = key.createdAt else { return false }
            return created >= startedAt.addingTimeInterval(-clockTolerance)
        }
        .max { $0.id < $1.id }
    }
}
