import Foundation
import Testing
@testable import Sub2Core

// S3-10: the new user page's words and small rules (30 §5.1–§5.3, design v-user-edit.jsx UeTabsScreen / useUeCompact).

private func group(_ id: Int, _ name: String, platform: String = "anthropic", rate: String? = "0.8", exclusive: Bool = true,
                   type: String = "standard") -> AdminGroup {
    AdminGroup(id: id, name: name, platform: platform, rateMultiplier: rate.flatMap { Decimal(string: $0) }, isExclusive: exclusive, subscriptionType: type)
}

/// 30 §5.1 身份条: 用户名 > 邮箱前缀 > 新用户; the letter follows the name, blank while both are empty.
@Test func identityStripNameInitialAndTail() {
    #expect(UserEditCopy.newUserName(username: "何琪", email: "qi.he@example.com") == "何琪")
    #expect(UserEditCopy.newUserName(username: "  ", email: "qi.he@example.com") == "qi.he")
    #expect(UserEditCopy.newUserName(username: "", email: "") == "新用户")
    #expect(UserEditCopy.newUserName(username: "", email: "@example.com") == "新用户")
    #expect(UserEditCopy.newUserInitial(username: "", email: "qi.he@example.com") == "Q")
    #expect(UserEditCopy.newUserInitial(username: "何琪", email: "") == "何")
    #expect(UserEditCopy.newUserInitial(username: " ", email: "") == nil)
    #expect(UserEditCopy.newUserTail(role: .user) == "用户 · 创建后启用")
    #expect(UserEditCopy.newUserTail(role: .vendor) == "供应商 · 创建后启用")
    #expect(UserEditCopy.newUserTail(role: .admin) == "管理员 · 创建后启用")
    #expect(UserEditCopy.newUserTail(role: nil) == "用户 · 创建后启用")
}

/// 30 §5.1 / §5.3 word for word.
@Test func createCopyMatchesSpec() {
    #expect(UserEditCopy.newTitle == "新建用户")
    #expect(UserEditCopy.createHint == "两段填完后点底部“创建用户”")
    #expect(UserEditCopy.discardNewTitle == "放弃新建用户？")
    #expect(UserEditCopy.discardNewMessage == "已填写的内容不会保留。")
    #expect(UserEditCopy.discardNew == "放弃")
    #expect(UserEditCopy.keepEditing == "继续编辑")
    #expect(UserEditCopy.nextStep == "下一步：权限与并发")
    #expect(UserEditCopy.previousStep == "上一步")
    #expect(UserEditCopy.createButton == "创建用户")
    #expect(UserEditCopy.creating == "正在创建…")
    #expect(UserEditCopy.emailPlaceholder == "必填")
    #expect(UserEditCopy.optionalPlaceholder == "选填")
    #expect(UserEditCopy.notesPlaceholder == "仅管理员可见")
    #expect(UserEditCopy.passwordPlaceholder == "必填，至少 6 位")
    #expect(UserEditCopy.generatePassword == "生成随机密码")
    #expect(UserEditCopy.copyPassword == "复制")
    #expect(UserEditCopy.passwordCopied == "密码已复制")
    #expect(UserEditCopy.balancePlaceholder == "留空按站点默认")
    #expect(UserEditCopy.balanceFootnote == "选填。填写后创建时会再确认一次金额；以后调整余额用充值键盘。")
    #expect(UserEditCopy.attributeNone == "不填")
    #expect(UserEditCopy.attributeReadOnly == "在 Web 端修改")
    #expect(UserEditCopy.restrictPublicTitle == "限制可访问的公开分组")
    #expect(UserEditCopy.restrictPublicSubtitle(true) == "只能使用下面勾选的公开分组")
    #expect(UserEditCopy.restrictPublicSubtitle(false) == "关闭时可以使用全部公开分组")
    #expect(UserEditCopy.noExclusiveGroups == "没有可授予的专属分组")
    #expect(UserEditCopy.rateAfterCreate == "专属倍率在创建后设置")
    #expect(UserEditCopy.removeExclusive == "移除这个专属分组")
}

/// An attribute's own placeholder, “选填” otherwise.
@Test func attributePlaceholderFallsBackToOptional() {
    #expect(UserEditCopy.attributePlaceholder(UserAttributeDefinition(id: 1, key: "company", name: "公司", type: "text", placeholder: "公司全称")) == "公司全称")
    #expect(UserEditCopy.attributePlaceholder(UserAttributeDefinition(id: 1, key: "company", name: "公司", type: "text")) == "选填")
}

/// 30 §5.3 权限 · 角色: only administrator and vendor have a footnote.
@Test func roleFootnotes() {
    #expect(UserEditCopy.createRoleFootnote(.admin) == "创建时需要输入二次验证码，验证后再确认一次。")
    #expect(UserEditCopy.createRoleFootnote(.vendor) == "供应商只能访问账号、代理、分组和用量，看不到用户与资金。")
    #expect(UserEditCopy.createRoleFootnote(.user) == nil)
    #expect(UserEditCopy.createRoleFootnote(nil) == nil)
}

/// S3D1-01: the confirmation's first sentence only when a code was asked for or a grant stands.
@Test func adminGrantLeadOnlyWhenVerified() {
    #expect(UserEditCopy.adminGrantLead(stepUpVerified: true) == "二次验证已通过。")
    #expect(UserEditCopy.adminGrantLead(stepUpVerified: false) == nil)
}

/// 30 §5.3 专属分组 / 公开分组, the add sheet and the group sheet; rates at most 3 decimals (S3D1-21, same as S2-10).
@Test func groupRowsMetaAndFootnotes() {
    let claude = group(5, "Claude Code 组")
    #expect(UserEditCopy.defaultRate(claude) == "默认 ×0.8")
    #expect(UserEditCopy.rateText(Decimal(string: "1.23456")!) == "×1.235")
    #expect(UserEditCopy.rateText(1) == "×1")
    #expect(UserEditCopy.rateText(nil) == "—")
    #expect(UserEditCopy.groupCount(2) == "2 个")
    #expect(UserEditCopy.publicAvailable(allowed: 3, total: 7) == "可用 3 / 7")
    let catalog = UserGroupCatalog(groups: [claude, group(4, "企业专线", type: "subscription")])
    #expect(UserEditCopy.exclusiveFootnote(catalog: catalog) == "专属倍率在创建后设置。企业专线是订阅分组，要在 Web 的订阅管理里开通。")
    #expect(UserEditCopy.exclusiveFootnote(catalog: UserGroupCatalog(groups: [claude])) == "专属倍率在创建后设置。")
    #expect(UserEditCopy.addGroupsButton(0) == "添加")
    #expect(UserEditCopy.addGroupsButton(2) == "添加 2 个")
    #expect(UserEditCopy.groupSheetNote(claude, platformName: "Anthropic") == "专属分组 · Anthropic · 默认倍率 ×0.8")
    #expect(UserEditCopy.groupSheetNote(group(1, "高级组", exclusive: false), platformName: "Anthropic") == "公开分组 · Anthropic · 默认倍率 ×0.8")
    #expect(UserEditCopy.publicRowSubtitle(platformName: "OpenAI", restricted: false, allowed: true) == "OpenAI")
    #expect(UserEditCopy.publicRowSubtitle(platformName: "OpenAI", restricted: true, allowed: true) == "OpenAI · 可以使用")
    #expect(UserEditCopy.publicRowSubtitle(platformName: "OpenAI", restricted: true, allowed: false) == "OpenAI · 不能使用")
    #expect(UserEditCopy.allowPublicSubtitle(true) == "这个用户可以用这个公开分组")
    #expect(UserEditCopy.allowPublicSubtitle(false) == "这个用户不能用这个公开分组")
}

/// 30 §5.3 并发与 RPM.
@Test func limitTextAndFootnote() {
    #expect(UserEditCopy.limitText(nil) == "—")
    #expect(UserEditCopy.limitText(0) == "不限制")
    #expect(UserEditCopy.limitText(1200) == "1,200")
    #expect(UserEditCopy.rpmStep == 10)
    #expect(UserEditCopy.limitFootnote == "0 = 不限制。RPM 上限是这个用户每分钟全部请求的总上限，始终生效；分组的 RPM 限制另外按分组计算。")
}

/// useUeCompact: folds past 24pt, unfolds at 2pt or less, so it never flaps at one edge; a blur waits 300ms.
@Test func headerFoldHysteresis() {
    #expect(!UserEditCopy.isScrolledCompact(offset: 24, wasCompact: false))
    #expect(UserEditCopy.isScrolledCompact(offset: 25, wasCompact: false))
    #expect(UserEditCopy.isScrolledCompact(offset: 3, wasCompact: true))
    #expect(!UserEditCopy.isScrolledCompact(offset: 2, wasCompact: true))
    #expect(!UserEditCopy.isScrolledCompact(offset: -40, wasCompact: true))
    #expect(UserEditCopy.unfoldDelay == .milliseconds(300))
}

/// The head sits in the scroll view's top inset. Folding takes the hint row out of it: the rows stay put (the plain reading
/// drops by the row) or the scroll view keeps the reading; unfolding is the reverse. Either way the next reading must not
/// flip the fold back, at the design's own 24pt / 2pt (the page hung in a layout loop when it did).
@Test func headerFoldSurvivesItsOwnShrink() {
    let unfolded = 180.0
    for hint in [16.0, 24.3, 40.0] {
        for tenth in 0...1200 {
            let scrolled = Double(tenth) / 10
            func read(_ plain: Double, folded: Bool) -> Double {
                UserEditCopy.scrollOffset(contentOffset: plain - (folded ? unfolded - hint : unfolded),
                                          insetTop: folded ? unfolded - hint : unfolded, foldedHeight: folded ? hint : 0)
            }
            if UserEditCopy.isScrolledCompact(offset: read(scrolled, folded: false), wasCompact: false) {
                for after in [max(scrolled - hint, 0), scrolled] {
                    #expect(UserEditCopy.isScrolledCompact(offset: read(after, folded: true), wasCompact: true), "收起后 \(hint) \(after)")
                }
            }
            if !UserEditCopy.isScrolledCompact(offset: read(scrolled, folded: true), wasCompact: true) {
                for after in [scrolled + hint, scrolled] {
                    #expect(!UserEditCopy.isScrolledCompact(offset: read(after, folded: false), wasCompact: false), "展开后 \(hint) \(after)")
                }
            }
        }
    }
    #expect(UserEditCopy.scrollOffset(contentOffset: -156, insetTop: 156, foldedHeight: 24) == 24)
    #expect(UserEditCopy.scrollOffset(contentOffset: -180, insetTop: 180, foldedHeight: 0) == 0)
}
