import Foundation

/// 30 §5.1–§5.3 / §6 (S3D1-01): the words of the new and edit user page, defined here once. S3-11 adds the edit page's own
/// members in an extension and uses these as they are.
public enum UserEditCopy {
    // MARK: 页面与操作条
    public static let newTitle = "新建用户"
    public static let createHint = "两段填完后点底部“创建用户”"
    public static let nextStep = "下一步：权限与并发"
    public static let previousStep = "上一步"
    public static let createButton = "创建用户"
    public static let creating = "正在创建…"
    public static let discardNewTitle = "放弃新建用户？"
    public static let discardNewMessage = "已填写的内容不会保留。"
    public static let discardNew = "放弃"
    public static let keepEditing = "继续编辑"
    /// The step-up sheet's “创建管理员前，输入…”.
    public static let stepUpPurpose = "创建管理员"

    // MARK: 基础段
    public static let accountSection = "账户"
    public static let loginSection = "登录"
    public static let balanceSection = "余额"
    public static let emailPlaceholder = "必填"
    public static let optionalPlaceholder = "选填"
    public static let notesPlaceholder = "仅管理员可见"
    public static let passwordPlaceholder = "必填，至少 6 位"
    public static let showPassword = "显示"
    public static let hidePassword = "隐藏"
    public static let generatePassword = "生成随机密码"
    public static let copyPassword = "复制"
    public static let passwordCopied = "密码已复制"
    public static let balancePlaceholder = "留空按站点默认"
    public static let balanceFootnote = "选填。填写后创建时会再确认一次金额；以后调整余额用充值键盘。"
    public static let attributeNone = "不填"
    public static let attributeEmpty = "未填"
    public static let attributeReadOnly = "在 Web 端修改"
    public static let attributeSheetFootnote = "选项由站点的用户属性定义（在 Web 端维护）。"
    public static let attributesFailedToLoad = "自定义属性加载失败 · 重试"

    // MARK: 权限与并发段
    public static let accessSection = "权限"
    public static let exclusiveSection = "专属分组"
    public static let publicSection = "公开分组"
    public static let limitSection = "并发与 RPM"
    public static let concurrencyTitle = "并发数"
    public static let rpmTitle = "RPM 上限"
    public static let rpmStep = 10
    public static let limitFootnote = "0 = 不限制。RPM 上限是这个用户每分钟全部请求的总上限，始终生效；分组的 RPM 限制另外按分组计算。"
    public static let groupsFailedToLoad = "分组加载失败 · 重试"
    public static let noExclusiveGroups = "没有可授予的专属分组"
    public static let noExclusiveSelected = "没有专属分组"
    public static let addExclusiveGroup = "添加专属分组"
    public static let rateAfterCreate = "专属倍率在创建后设置"
    public static let publicFootnoteCreate = "专属倍率在创建后设置。"
    public static let removeExclusive = "移除这个专属分组"
    public static let restrictPublicTitle = "限制可访问的公开分组"
    public static let allowPublicTitle = "允许使用"
    public static let addGroupsEmpty = "没有其他可授予的专属分组"
    public static let addGroupsFootnoteCreate = "添加后随“创建用户”一起提交。"
    public static let addGroupsFootnoteSave = "添加后要“保存”才生效。"
    public static let groupSheetFootnoteCreate = "按“完成”回到表单，创建时一起提交。"
    public static let groupSheetDone = "完成"

    // MARK: 身份条（新建态）

    /// 30 §5.1: 用户名 > 邮箱前缀 > “新用户”.
    public static func newUserName(username: String, email: String) -> String {
        let name = UserPresentation.displayName(username: username, email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        return name.isEmpty ? "新用户" : name
    }
    /// The avatar letter (30 §0.3); nil, a blank avatar, while neither the name nor the email is typed.
    public static func newUserInitial(username: String, email: String) -> String? {
        let typed = [username, email].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return typed ? UserPresentation.initial(newUserName(username: username, email: email)) : nil
    }
    /// “用户 · 创建后启用”.
    public static func newUserTail(role: AdminUserRole?) -> String { (role ?? .user).title + " · 创建后启用" }

    // MARK: 角色与二次验证

    public static func createRoleFootnote(_ role: AdminUserRole?) -> String? {
        switch role {
        case .admin?: "创建时需要输入二次验证码，验证后再确认一次。"
        case .vendor?: "供应商只能访问账号、代理、分组和用量，看不到用户与资金。"
        case .user?, nil: nil
        }
    }
    /// The first sentence of “创建管理员「名」？” and S3-11's “把「名」设为管理员？”; left out when the site has step-up off.
    public static func adminGrantLead(stepUpVerified: Bool) -> String? { stepUpVerified ? "二次验证已通过。" : nil }
    public static let adminGrantBody = "管理员可以管理全部账号、用户和资金。"

    // MARK: 分组

    /// The App's one rate format (S3D1-21): “×1.3”, at most three decimals, as S2-10 shows an account's rate.
    public static func rateText(_ value: Decimal?) -> String {
        guard let value else { return DisplayFormat.missing }
        return "×" + DisplayFormat.decimal(NSDecimalNumber(decimal: value).doubleValue, maxFractionDigits: 3)
    }
    /// “默认 ×0.8”.
    public static func defaultRate(_ group: AdminGroup) -> String { "默认 " + rateText(group.rateMultiplier) }
    public static func groupCount(_ count: Int) -> String { "\(DisplayFormat.grouped(count)) 个" }
    /// The public section's meta while restricted: “可用 3 / 7”.
    public static func publicAvailable(allowed: Int, total: Int) -> String { "可用 \(allowed) / \(total)" }
    /// “专属倍率在创建后设置。” and the subscription groups the list cannot grant.
    public static func exclusiveFootnote(catalog: UserGroupCatalog) -> String { "专属倍率在创建后设置。" + (catalog.subscriptionNote ?? "") }
    public static func restrictPublicSubtitle(_ on: Bool) -> String { on ? "只能使用下面勾选的公开分组" : "关闭时可以使用全部公开分组" }
    /// “OpenAI”, and while restricted “OpenAI · 可以使用 / 不能使用”.
    public static func publicRowSubtitle(platformName: String, restricted: Bool, allowed: Bool) -> String {
        restricted ? platformName + (allowed ? " · 可以使用" : " · 不能使用") : platformName
    }
    public static func addGroupsButton(_ count: Int) -> String { count > 0 ? "添加 \(count) 个" : "添加" }
    /// The group sheet's line: “专属分组 · Anthropic · 默认倍率 ×0.8”.
    public static func groupSheetNote(_ group: AdminGroup, platformName: String) -> String {
        (group.isExclusive == true ? "专属分组" : "公开分组") + " · \(platformName) · 默认倍率 " + rateText(group.rateMultiplier)
    }
    public static func allowPublicSubtitle(_ on: Bool) -> String { on ? "这个用户可以用这个公开分组" : "这个用户不能用这个公开分组" }

    // MARK: 并发与 RPM

    /// nil “—”, 0 “不限制”, otherwise grouped.
    public static func limitText(_ value: Int?) -> String {
        guard let value else { return DisplayFormat.missing }
        return value == 0 ? "不限制" : DisplayFormat.grouped(value)
    }

    // MARK: 属性

    public static func attributePlaceholder(_ definition: UserAttributeDefinition) -> String { definition.placeholder ?? optionalPlaceholder }

    // MARK: 吸顶头的收起（设计稿 useUeCompact）

    public static let foldOffset = 24.0
    public static let unfoldOffset = 2.0
    /// A blur waits this long before the header unfolds, so a tap that moved the focus lands first.
    public static let unfoldDelay: Duration = .milliseconds(300)
    /// Two thresholds, so the header never flaps at one edge.
    public static func isScrolledCompact(offset: Double, wasCompact: Bool) -> Bool {
        wasCompact ? offset > unfoldOffset : offset > foldOffset
    }
    /// How far the form is scrolled, read as if the head were unfolded. The head sits in the scroll view's top inset, so
    /// folding it moves the plain reading by the hint row while the rows stay put; read plainly, a fold would undo itself.
    public static func scrollOffset(contentOffset: Double, insetTop: Double, foldedHeight: Double) -> Double {
        contentOffset + insetTop + foldedHeight
    }
}
