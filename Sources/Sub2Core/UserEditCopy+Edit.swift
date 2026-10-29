import Foundation

/// 30 §6 (S3-11, S3D1-01): the edit page's own words, added to S3-10's UserEditCopy.
extension UserEditCopy {
    // MARK: 页面、导航栏与 ⋯
    public static let editTitle = "编辑用户"
    public static let saveButton = "保存"
    public static let saving = "正在保存…"
    public static let idleHint = "基础、权限与并发改完点右上“保存”，两段一起提交"
    public static let copyEmail = "复制邮箱"
    public static let copiedEmail = "已复制邮箱"
    public static let deleteUser = "删除用户…"
    public static let adminCannotDelete = "管理员不能删除"
    public static let loadFailed = "加载用户失败"
    public static let keysPlaceholder = "Key 卡片与平台限额即将在这里管理，目前请在 Web 端操作。"
    /// The step-up sheet's “设为管理员前，输入…”.
    public static let promotePurpose = "设为管理员"
    /// “Key 与限额（2）”, or without the count while the keys are unknown.
    public static func keysSegmentTitle(count: Int?) -> String {
        count.map { "Key 与限额（\(DisplayFormat.grouped($0))）" } ?? "Key 与限额"
    }

    // MARK: 离开
    public static let leaveTitle = "放弃未保存的更改？"
    public static let leaveDiscard = "放弃更改"
    /// A balance written from the identity strip, named in the leave confirmation.
    public static let appliedBalance = "余额"
    /// “邮箱、并发数还没保存，会被放弃。”, then what already took effect.
    public static func leaveMessage(changed: [UserDraftField], applied: [String]) -> String {
        let lost = UserDraftField.names(changed) + "还没保存，会被放弃。"
        guard !applied.isEmpty else { return lost }
        return lost + "\n已经立即生效、不会撤回：" + applied.joined(separator: "、") + "。"
    }

    // MARK: 角色
    public static let promoteConfirm = "设为管理员并保存"
    public static func promoteTitle(name: String) -> String { "把「\(name)」设为管理员？" }
    /// The first sentence only when a code was asked for (S3D1-01).
    public static func promoteMessage(changed: [UserDraftField], verified: Bool) -> String {
        (adminGrantLead(stepUpVerified: verified) ?? "") + adminGrantBody + "\n同时保存：" + UserDraftField.names(changed)
    }
    /// 本人 > 升为管理员 > 降级 > 供应商; nothing otherwise.
    public static func roleFootnote(isSelf: Bool, selfName: String, from: AdminUserRole?, to: AdminUserRole?, stepUpRequired: Bool) -> String? {
        if isSelf { return "这是你当前登录的账号（\(selfName)）：不能把自己降级，也不能禁用或删除。" }
        switch UserRoleChange(from: from, to: to) {
        case .promote: return stepUpRequired ? "保存时需要输入二次验证码，验证后再确认一次。" : "保存时会再确认一次。"
        case .demote: return "降级后会失去后台权限。如果他是站点最后一个管理员，保存会失败。"
        case .none, .other: return to == .vendor ? createRoleFootnote(.vendor) : nil
        }
    }
    public static let lastAdminField = "站点只剩这一位管理员，不能降级"
    public static let lastAdminReceipt = "保存失败：不能降级站点最后一个管理员"

    // MARK: 基础段
    public static let loginStatusSection = "登录与状态"
    public static let passwordFold = "重置密码"
    public static let passwordUnchanged = "不修改"
    public static let passwordWillChange = "保存时修改"
    public static let newPasswordPlaceholder = "留空则保持原密码"
    public static let statusTitle = "状态"
    public static let adminCannotDisable = "管理员不能禁用"
    public static func statusSubtitle(active: Bool, locked: Bool) -> String {
        if locked { return adminCannotDisable }
        return active ? "可以登录，Key 可以调用" : "不能登录，Key 调用会被拒绝"
    }

    // MARK: 分组与倍率
    public static let undoRemove = "撤回"
    public static let removeAnyway = "仍要移除"
    public static let rateTitle = "专属倍率"
    public static let rateSubtitle = "只对这个用户生效"
    public static let publicFootnoteEdit = "点分组可以设专属倍率；留空用分组默认倍率。"
    public static let groupSheetFootnoteEdit = "按“完成”回到表单，倍率与移除在“保存”后生效。"
    public static func exclusiveFootnoteEdit(catalog: UserGroupCatalog) -> String { "倍率、添加、移除在“保存”后生效。" + (catalog.subscriptionNote ?? "") }
    /// “专属倍率 ×1.3”, or the group's “默认 ×0.8”.
    public static func rateLine(_ rate: Decimal?, group: AdminGroup) -> String {
        rate.map { rateTitle + " " + rateText($0) } ?? defaultRate(group)
    }
    /// “Anthropic · 绑定 1 个 Key”, or “Anthropic · 新添加 · 保存后生效”.
    public static func exclusiveRowSubtitle(platformName: String, added: Bool, boundKeys: Int) -> String {
        platformName + (added ? " · 新添加 · 保存后生效" : " · 绑定 \(DisplayFormat.grouped(boundKeys)) 个 Key")
    }
    public static func removedRowSubtitle(boundKeys: Int) -> String {
        boundKeys > 0 ? "保存后移除 · \(DisplayFormat.grouped(boundKeys)) 个 Key 会无法调用" : "保存后移除"
    }
    public static func changedCount(_ count: Int) -> String { "已改 \(count) 项" }
    public static func removeGroupTitle(_ name: String) -> String { "移除「\(name)」？" }
    public static func removeGroupMessage(_ name: String, keys: Int) -> String {
        "绑定在「\(name)」的 \(DisplayFormat.grouped(keys)) 个 Key 会无法调用。要保留请用替换分组。"
    }
    /// The edit sheet's line adds the bound keys.
    public static func groupSheetNote(_ group: AdminGroup, platformName: String, boundKeys: Int) -> String {
        groupSheetNote(group, platformName: platformName) + (boundKeys > 0 ? " · 绑定 \(DisplayFormat.grouped(boundKeys)) 个 Key" : "")
    }
    public static func resetRate(_ group: AdminGroup) -> String { "改回默认倍率 " + rateText(group.rateMultiplier) }
    /// “默认 0.8”, the rate box's placeholder.
    public static func ratePlaceholder(_ group: AdminGroup) -> String {
        group.rateMultiplier.map { "默认 " + DisplayFormat.decimal(NSDecimalNumber(decimal: $0).doubleValue, maxFractionDigits: 3) } ?? "默认"
    }

    // MARK: 并发
    public static let adjustmentTitle = "调整备注"
    public static let adjustmentFootnote = "调整备注只写进这次的并发流水，不写进用户资料。"
    /// “可选 · 并发 2 → 4 的原因”.
    public static func adjustmentPlaceholder(from: Int?, to: Int?) -> String {
        "可选 · 并发 \(from.map(String.init) ?? DisplayFormat.missing) → \(to.map(String.init) ?? DisplayFormat.missing) 的原因"
    }

    // MARK: 保存的结果（30 §6.4、§6.5）
    public static let emailTakenField = "已被其他用户使用"
    public static let emailTakenReceipt = "保存失败：这个邮箱已被其他用户使用"
    public static let serverFailed = "保存失败：服务器未能完成请求"
    public static let attributesFailed = "资料已保存，自定义属性没保存成功"
    public static let attributesOnlyFailed = "保存失败：自定义属性没保存成功"
    public static let readbackMismatch = "服务器上的资料与你的修改不一致，请检查后再保存"
    public static let readbackUndetermined = "密码是否已修改无法确认，请再保存一次"
    public static let unconfirmed = "保存结果未确认"
    public static let readOnly = "当前登录的是只读令牌，不能修改"
    public static let userGone = "这个用户不存在或已删除"
    /// S3D1-11: an immediate write while “保存” is out.
    public static let immediateBlockedBySave = "正在保存，请稍后再试"
}
