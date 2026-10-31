import Foundation
import Testing
@testable import Sub2Core

// S5-02: 50 §0.5 confirmations and receipts, §2.3 status card and sections, §3.4 edit confirmation, §0.8 errors (R11).

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }

private func group(_ name: String = "高级组", status: String = "active", type: String = "standard", account: Int = 4, rate: String = "0.8",
                   rpm: Int = 0, exclusive: Bool = false, weekly: Decimal? = nil) -> AdminGroup {
    AdminGroup(id: 7, name: name, platform: "anthropic", status: status, rateMultiplier: Decimal(string: rate), isExclusive: exclusive, subscriptionType: type,
               weeklyLimitUSD: weekly, rpmLimit: rpm, accountCount: account, activeAccountCount: account, rateLimitedAccountCount: 0,
               errorAccountCount: 0, idleAccountCount: 0)
}
private func stats(keys: Int = 0, activeKeys: Int = 0, subscriptions: Int = 0, activeSubscriptions: Int = 0) -> GroupStats {
    GroupStats(totalAPIKeys: keys, activeAPIKeys: activeKeys, subscriptionsTotal: subscriptions, subscriptionsActive: activeSubscriptions)
}
private func buckets(_ available: Int, _ limited: Int = 0, _ error: Int = 0, _ idle: Int = 0) -> GroupBuckets {
    GroupBuckets(GroupAccountCounts(accountCount: available + limited + error + idle, activeAccountCount: available, rateLimitedAccountCount: limited,
                                    errorAccountCount: error, idleAccountCount: idle))
}
private func snapshot(_ id: Int, _ name: String? = nil, status: String = "active", schedulable: Bool = true, overload: String? = nil,
                      rateLimit: String? = nil, temp: String? = nil) -> GroupMemberSnapshot {
    GroupMemberSnapshot(UpstreamAccount(id: id, name: name ?? "账号-\(id)", platform: "anthropic", type: "oauth", status: status, schedulable: schedulable,
                                        rateLimitResetAt: rateLimit, overloadUntil: overload, tempUnschedulableUntil: temp))
}

// MARK: 0.5 停用 / 启用 / 复制 / 删除

@Test func disableConfirmationUsesActiveKeysOrDropsTheNumber() {
    let counted = GroupCopy.disableConfirmation(name: "高级组", siteName: "演示站", activeAPIKeys: 3)
    #expect(counted.title == "停用「高级组」？")
    #expect(counted.lines == ["站点 演示站", "使用这个分组的 3 个 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。"])
    #expect(counted.confirmTitle == "停用分组" && !counted.isDestructive && GroupConfirmation.cancelTitle == "取消")
    #expect(counted.message == counted.lines.joined(separator: "\n"))
    let unknown = GroupCopy.disableConfirmation(name: "高级组", siteName: "演示站", activeAPIKeys: nil)
    #expect(unknown.lines[1] == "使用这个分组的 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。")
}

@Test func statusDuplicateCreatedAndSavedReceipts() {
    #expect(GroupCopy.disabledReceipt(name: "高级组") == "已停用「高级组」" && GroupCopy.enabledReceipt(name: "高级组") == "已启用「高级组」")
    #expect(GroupCopy.duplicateReceipt(newName: "高级组 (Copy)", memberCount: 4) == "已复制为「高级组 (Copy)」 · 停用中 · 4 个成员账号")
    #expect(GroupCopy.createdReceipt(name: "夜间组") == "已创建「夜间组」" && GroupCopy.savedReceipt(name: "夜间组") == "已保存「夜间组」")
    #expect(GroupCopy.savedReceipt(name: "夜间组", droppedFields: true) == "已保存「夜间组」 · 部分字段无权修改，未生效")
    #expect(GroupCopy.objectNoun == "分组")
}

@Test func createConfirmationOnlyForPublicGroupsWithoutAvailableAccounts() throws {
    let request = GroupCreateRequest(name: "Claude 夜间组")
    let confirmation = try #require(GroupCopy.createConfirmation(request, siteName: "演示站", availableAfter: 0))
    #expect(confirmation.title == "创建公开分组「Claude 夜间组」？")
    #expect(confirmation.lines == ["站点 演示站 · Anthropic · 费率倍数 ×1.0", "创建后所有用户新建 API 密钥时都能选它，但现在没有可用账号，选它的请求会失败。"])
    #expect(confirmation.confirmTitle == "仍然创建" && !confirmation.isDestructive)
    #expect(GroupCopy.createConfirmation(GroupCreateRequest(name: "专属组", isExclusive: true), siteName: "演示站", availableAfter: 0) == nil)
    #expect(GroupCopy.createConfirmation(request, siteName: "演示站", availableAfter: 1) == nil)
}

@Test func deleteConsequencesSkipZeroRows() {
    #expect(GroupCopy.deleteConsequences(stats: stats(keys: 2, activeKeys: 1), group: group()) == [
        "使用这个分组的 2 个 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。", "4 个成员账号移出分组，账号本身保留。"
    ])
    let subscription = group(type: "subscription", account: 0)
    #expect(GroupCopy.deleteConsequences(stats: stats(subscriptions: 5, activeSubscriptions: 3), group: subscription) == ["删除 5 条订阅记录（生效中 3 条）。"])
    #expect(GroupCopy.deleteConsequences(stats: stats(subscriptions: 5), group: subscription) == ["删除 5 条订阅记录。"])
    #expect(GroupCopy.deleteConsequences(stats: stats(subscriptions: 5, activeSubscriptions: 3), group: group(account: 0)).isEmpty)
    #expect(GroupCopy.deleteConsequences(stats: stats(), group: group(account: 0)).isEmpty)
}

@Test func deleteConsequencesWithoutStatsUseWordsWithoutNumbers() {
    #expect(GroupCopy.deleteConsequences(stats: nil, group: group(account: 0)) == ["使用这个分组的 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。"])
    #expect(GroupCopy.deleteConsequences(stats: nil, group: group(type: "subscription", account: 2)) == [
        "使用这个分组的 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。", "删除这个分组的全部订阅记录。", "2 个成员账号移出分组，账号本身保留。"
    ])
}

@Test func deleteConsequencesInSimpleModeSkipTheMemberLine() {
    #expect(GroupCopy.deleteConsequences(stats: nil, group: group(account: 3), isSimpleMode: true) == [
        "使用这个分组的 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。"
    ])
    #expect(GroupCopy.deleteConsequences(stats: stats(), group: group(account: 3), isSimpleMode: true).isEmpty)
}

// MARK: 2.3 状态卡与分区

@Test func statusCardTrailingFigureAndNoneWarnings() {
    let partial = GroupCopy.statusCard(health: .ok, buckets: buckets(2, 0, 0, 1), totalAPIKeys: 3)
    #expect(partial.title == "正常" && partial.trailing == "1 个不可用" && partial.figure == "2 / 3 个账号可用" && partial.warning == nil)
    #expect(partial.available == "2" && partial.total == "3")
    let full = GroupCopy.statusCard(health: .ok, buckets: buckets(3), totalAPIKeys: nil)
    #expect(full.title == "全部可用" && full.trailing == "共 3 个账号")
    let none = GroupCopy.statusCard(health: .noAvailable, buckets: buckets(0, 1, 0, 1), totalAPIKeys: 0)
    #expect(none.title == "无可用账号" && none.warning == "没有可用的账号，这个分组的新请求会失败。先让成员账号恢复或启用调度，或加入同平台的可用账号。")
    let empty = GroupCopy.statusCard(health: .noAvailable, buckets: buckets(0), totalAPIKeys: 0)
    #expect(empty.title == "没有账号" && empty.trailing == "共 0 个账号" && empty.warning == "分组里还没有账号，新请求会失败。目前也没有 API 密钥使用它。")
    #expect(GroupCopy.statusCard(health: .noAvailable, buckets: buckets(0), totalAPIKeys: nil).warning == "分组里还没有账号，新请求会失败。")
    #expect(GroupCopy.statusCard(health: .noAvailable, buckets: buckets(0), totalAPIKeys: 2).warning == "分组里还没有账号，新请求会失败。")
    #expect(GroupCopy.statusCard(health: .low, buckets: buckets(1, 0, 0, 3), totalAPIKeys: 0).warning == nil)
    #expect(GroupCopy.statusCard(health: .low, buckets: buckets(1, 0, 0, 3), totalAPIKeys: 0).title == "可用偏低")
    #expect(GroupCopy.inactiveCard == "已停用 · 使用此分组的 API 密钥会被拒绝")
}

@Test func capacityEmptyNoteChoosesOneOfFour() {
    #expect(GroupCopy.capacityEmptyNote(group: group(status: "inactive"), buckets: buckets(3)) == "停用的分组不统计容量")
    #expect(GroupCopy.capacityEmptyNote(group: group(), buckets: buckets(0)) == "没有成员账号")
    #expect(GroupCopy.capacityEmptyNote(group: group(), buckets: buckets(0, 2)) == "没有可调度的账号")
    #expect(GroupCopy.capacityEmptyNote(group: group(), buckets: buckets(2)) == "暂无容量数据")
    #expect(GroupCopy.capacityMissing == "容量 —")
}

@Test func memberSectionMetaFootnotesAndAddRow() {
    #expect(GroupCopy.membersMeta(count: 0) == nil && GroupCopy.membersMeta(count: 1) == "1 个" && GroupCopy.membersMeta(count: 3) == "3 个 · 不可用在前")
    #expect(GroupCopy.membersTodayFootnote(isGroupScoped: true) == "成员行的“今日”只算这个分组的请求（按 Key 所属分组）。")
    #expect(GroupCopy.membersTodayFootnote(isGroupScoped: false) == "成员行的“今日”是账号今日，含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。")
    #expect(GroupCopy.addAccountsRow(platform: "anthropic") == "添加 Anthropic 账号" && GroupCopy.addAccountsRow(platform: "zhipu") == "添加 智谱 GLM 账号")
    #expect(GroupCopy.addAccountsRow(platform: "composite") == "添加账号")
}

@Test func stoppedLimitedNoteNamesTheStateOrSaysLimited() {
    let twoLimited = [snapshot(1, schedulable: false, rateLimit: at(60)), snapshot(2, schedulable: false, rateLimit: at(90)), snapshot(3)]
    #expect(GroupCopy.stoppedLimitedNote(members: twoLimited, now: now) == "其中 2 个账号限流中但已停止调度，计入暂停·停用")
    #expect(GroupCopy.stoppedLimitedNote(members: [snapshot(1, schedulable: false, overload: at(30))], now: now) == "其中 1 个账号过载中但已停止调度，计入暂停·停用")
    let mixed = [snapshot(1, schedulable: false, rateLimit: at(60)), snapshot(2, schedulable: false, temp: at(600))]
    #expect(GroupCopy.stoppedLimitedNote(members: mixed, now: now) == "其中 2 个账号受限但已停止调度，计入暂停·停用")
    let none = [snapshot(1, rateLimit: at(60)), snapshot(2, schedulable: false), snapshot(3, schedulable: false, rateLimit: at(-5))]
    #expect(GroupCopy.stoppedLimitedNote(members: none, now: now) == nil)
    #expect(GroupCopy.stoppedLimitedNote(members: [], now: now) == nil)
}

@Test func earliestRecoveryWaitsForEachMembersLastWindow() throws {
    let two = [snapshot(1, "Claude-官方-03", rateLimit: at(277)), snapshot(2, "Claude-官方-05", temp: at(1_380))]
    let first = try #require(GroupRecovery.earliest(members: two, now: now))
    #expect(first.count == 1 && first.accountName == "Claude-官方-03" && first.text(now: now) == "最早 4:37 后恢复 1 个 · Claude-官方-03")
    #expect(first.text(now: now.addingTimeInterval(37)) == "最早 4:00 后恢复 1 个 · Claude-官方-03")
    let stacked = try #require(GroupRecovery.earliest(members: [snapshot(3, "叠加", overload: at(72), rateLimit: at(300))], now: now))
    #expect(stacked.text(now: now) == "最早 5:00 后恢复 1 个 · 叠加")
    let tied = try #require(GroupRecovery.earliest(members: [snapshot(4, "甲", temp: at(1_000)), snapshot(5, "乙", rateLimit: at(300)),
                                                             snapshot(6, "丙", overload: at(300))], now: now))
    #expect(tied.count == 2 && tied.accountName == "乙" && tied.text(now: now) == "最早 5:00 后恢复 2 个 · 乙 等")
    #expect(GroupRecovery.earliest(members: [snapshot(7, rateLimit: at(-1)), snapshot(8, overload: at(0)), snapshot(9)], now: now) == nil)
    // Nothing comes back to scheduling when its window ends: an error account, one with scheduling off.
    let stuck = [snapshot(10, status: "error", rateLimit: at(60)), snapshot(11, schedulable: false, rateLimit: at(90)), snapshot(12, rateLimit: at(400))]
    #expect(GroupRecovery.earliest(members: stuck, now: now)?.accountName == "账号-12")
}

@Test func recordRowTexts() {
    #expect(GroupCopy.last24Hours(12) == "近 24 小时 12 条" && GroupCopy.last24Hours(1_234) == "近 24 小时 1,234 条" && GroupCopy.last24Hours(nil) == "—")
    #expect(GroupCopy.opsDisabled == "运维监控未开启")
    #expect(GroupCopy.apiKeysValue(38) == "38 个" && GroupCopy.apiKeysValue(nil) == "—")
    #expect(GroupCopy.activeSubscriptionsValue(12) == "生效中 12 个" && GroupCopy.activeSubscriptionsValue(nil) == "—")
}

// MARK: 3.4 编辑确认

@Test func editDiffLinesListEveryChangeInOrder() {
    let original = group(type: "subscription")
    let update = GroupUpdateRequest(name: "高级组二", description: "夜间用", rateMultiplier: Decimal(string: "0.9"), isExclusive: true, status: "inactive",
                                    rpmLimit: 60, dailyLimitUSD: .amount(20))
    let diff = GroupEditDiff(original: original, update: update, membersAdded: 2, membersRemoved: 1)
    #expect(diff.lines(siteName: "演示站", activeAPIKeys: 3) == [
        "站点 演示站 · 分组「高级组」", "名称 高级组 → 高级组二", "描述已修改", "费率倍数 ×0.8 → ×0.9", "每用户 RPM 不限 → 60", "每日限额 无限制 → $20",
        "公开 → 专属：之后只有分配了这个分组的用户能选它", "停用分组（3 个 API 密钥会被拒绝）", "成员：加入 2 个 · 移出 1 个", "此后的请求按新倍率计费，已产生的记录不变。"
    ])
    #expect(diff.lines(siteName: "演示站", activeAPIKeys: nil)[7] == "停用分组（API 密钥会被拒绝）")
    let toPublic = GroupEditDiff(original: group(exclusive: true), update: GroupUpdateRequest(isExclusive: false))
    #expect(toPublic.lines(siteName: "演示站", activeAPIKeys: nil) == ["站点 演示站 · 分组「高级组」", "专属 → 公开：之后所有用户新建 API 密钥时都能选它"])
    let same = GroupEditDiff(original: group(weekly: 50), update: GroupUpdateRequest(name: "高级组", rateMultiplier: Decimal(string: "0.80"), isExclusive: false,
                                                                               status: "active", rpmLimit: 0, weeklyLimitUSD: .amount(50)))
    #expect(same.lines(siteName: "演示站", activeAPIKeys: 3) == ["站点 演示站 · 分组「高级组」"])
    let removedOnly = GroupEditDiff(original: group(weekly: 50), update: GroupUpdateRequest(weeklyLimitUSD: .unlimited), membersRemoved: 2)
    #expect(removedOnly.lines(siteName: "演示站", activeAPIKeys: nil).dropFirst() == ["每周限额 $50 → 无限制", "成员：移出 2 个"])
}

@Test func editDiffNeedsConfirmationOnlyForRiskyChanges() {
    func diff(_ update: GroupUpdateRequest, original: AdminGroup = group(weekly: 50)) -> GroupEditDiff {
        GroupEditDiff(original: original, update: update, membersAdded: 1, membersRemoved: 1, availableNow: 3, availableAfter: 2)
    }
    #expect(!diff(GroupUpdateRequest(name: "新名", description: "新描述")).requiresConfirmation)
    #expect(diff(GroupUpdateRequest(rateMultiplier: 2)).requiresConfirmation)
    #expect(diff(GroupUpdateRequest(rpmLimit: 30)).requiresConfirmation)
    #expect(diff(GroupUpdateRequest(isExclusive: true)).requiresConfirmation)
    #expect(diff(GroupUpdateRequest(weeklyLimitUSD: .unlimited)).requiresConfirmation)
    #expect(diff(GroupUpdateRequest(status: "inactive")).requiresConfirmation)
    #expect(!diff(GroupUpdateRequest(rateMultiplier: Decimal(string: "0.8"))).requiresConfirmation)
    let enabling = diff(GroupUpdateRequest(status: "active"), original: group(status: "inactive"))
    #expect(!enabling.requiresConfirmation && enabling.lines(siteName: "演示站", activeAPIKeys: nil).contains("启用分组"))
    let confirmation = diff(GroupUpdateRequest(name: "高级组二", rpmLimit: 30)).confirmation(siteName: "演示站", activeAPIKeys: nil)
    #expect(confirmation.title == "保存「高级组二」的修改？" && confirmation.confirmTitle == "保存修改" && !confirmation.isDestructive)
    #expect(diff(GroupUpdateRequest(rpmLimit: 30)).confirmation(siteName: "演示站", activeAPIKeys: nil).title == "保存「高级组」的修改？")
}

@Test func editDiffZeroingAvailabilityIsDestructive() {
    let zeroing = GroupEditDiff(original: group(), update: GroupUpdateRequest(name: "高级组二"), membersRemoved: 2, availableNow: 2, availableAfter: 0)
    #expect(zeroing.isDestructive && zeroing.requiresConfirmation)
    #expect(zeroing.lines(siteName: "演示站", activeAPIKeys: nil).last == "保存后这个分组没有可用的账号，新请求会失败。")
    let confirmation = zeroing.confirmation(siteName: "演示站", activeAPIKeys: nil)
    #expect(confirmation.confirmTitle == "仍然保存" && confirmation.isDestructive)
    let disabling = GroupEditDiff(original: group(), update: GroupUpdateRequest(status: "inactive"), membersRemoved: 2, availableNow: 2, availableAfter: 0)
    #expect(!disabling.isDestructive && !disabling.lines(siteName: "演示站", activeAPIKeys: nil).contains("保存后这个分组没有可用的账号，新请求会失败。"))
    #expect(!GroupEditDiff(original: group(status: "inactive"), update: GroupUpdateRequest(name: "甲"), availableNow: 2, availableAfter: 0).isDestructive)
    #expect(!GroupEditDiff(original: group(), update: GroupUpdateRequest(name: "甲"), availableNow: 0, availableAfter: 0).isDestructive)
    #expect(!GroupEditDiff(original: group(), update: GroupUpdateRequest(name: "甲"), membersRemoved: 2).isDestructive)
}

// MARK: 0.8 错误

@Test func errorCopyMapsGroupReasonsPerContext() {
    func copy(_ status: Int, _ reason: String, _ context: GroupErrorCopy.Context) -> GroupErrorCopy {
        GroupErrorCopy.resolve(APIError.server(status: status, reason: reason), context: context)
    }
    for context in [GroupErrorCopy.Context.read, .write, .members] {
        for reason in ["GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND"] {
            #expect(copy(404, reason, context) == GroupErrorCopy(message: "这个分组已删除", action: .treatAsDeleted, logs: false))
        }
    }
    #expect(GroupErrorCopy.deleted == "这个分组已删除")
    #expect(copy(409, "GROUP_EXISTS", .write) == GroupErrorCopy(message: "已有同名分组。", action: .nameField, logs: false))
    #expect(copy(409, "GROUP_NOT_EMPTY", .write).message == "分组里还有账号，先移出成员再删除。" && copy(409, "GROUP_NOT_EMPTY", .write).action == .show)
    #expect(copy(400, "SIMPLE_MODE_GROUP_NOT_BINDABLE", .members).message == "简易模式下不能给组合分组添加账号。")
    #expect(copy(403, "SIMPLE_MODE_OPERATION_UNSUPPORTED", .read).message == "简易模式下不支持此操作。")
    #expect(copy(403, "FORBIDDEN", .write).message == "你的工作区没有这个权限。")
    for reason in ["EMPTY_MEMBER_CHANGE", "TOO_MANY_ACCOUNTS", "ACCOUNT_IN_BOTH_LISTS", "INVALID_ACCOUNT_ID", "INVALID_GROUP_ID"] {
        #expect(copy(400, reason, .members) == GroupErrorCopy(message: "提交的成员有误，请重试。", action: .show, logs: true))
    }
    for reason in ["INVALID_GROUP_ID", "TOO_MANY_IDS"] {
        #expect(copy(400, reason, .capacity) == GroupErrorCopy(message: "—", action: .showMissing, logs: true))
    }
    #expect(copy(404, "GROUP_NOT_FOUND", .capacity) == GroupErrorCopy(message: "—", action: .showMissing, logs: false))
    #expect(GroupErrorCopy.resolve(APIError.server(status: 503, reason: nil), context: .capacity).action == .showMissing)
    #expect(copy(500, "GROUP_REPOSITORY_UNSUPPORTED", .members) == GroupErrorCopy(message: "服务器暂不支持批量调整成员。", action: .useLegacyMembers, logs: false))
    #expect(copy(500, "GROUP_REPOSITORY_UNSUPPORTED", .write).action == .show)
    #expect(GroupErrorCopy.reasonText("GROUP_NOT_EMPTY", context: .write) == "分组里还有账号，先移出成员再删除。")
    #expect(GroupErrorCopy.reasonText("TOO_MANY_ACCOUNTS", context: .members) == "提交的成员有误，请重试。")
    #expect(GroupErrorCopy.reasonText("GROUP_NOT_FOUND", context: .members) == "这个分组已删除")
    #expect(GroupErrorCopy.reasonText("ACCOUNT_NOT_FOUND", context: .members) == nil && GroupErrorCopy.reasonText("TOO_MANY_ACCOUNTS", context: .write) == nil)
}

@Test func errorCopyNeverEchoesTheServerMessage() {
    let body = #"{"code":400,"reason":"GROUP_SOMETHING_NEW","message":"upstream https://leak.example.invalid token=abc"}"#
    let unknown = GroupErrorCopy.resolve(APIError.from(HTTPResponse(statusCode: 400, data: Data(body.utf8))), context: .write)
    #expect(unknown.message == "请求无效（错误码 GROUP_SOMETHING_NEW）" && unknown.action == .show)
    #expect(!unknown.message.contains("leak") && !unknown.message.contains("token"))
    let plain = GroupErrorCopy.resolve(APIError.from(HTTPResponse(statusCode: 404, data: Data("404 page not found".utf8))), context: .read)
    #expect(plain.action == .show && plain.message == "站点版本较旧，暂不支持此功能")
    let busy = GroupErrorCopy.resolve(APIError.server(status: 409, reason: "IDEMPOTENCY_IN_PROGRESS"), context: .write)
    #expect(busy.message == ReasonCatalog.entry(status: 409, reason: "IDEMPOTENCY_IN_PROGRESS").message && busy.action == .show)
    let failure = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    #expect(GroupErrorCopy.message(for: failure, context: .write) == failure.errorDescription)
    #expect(GroupErrorCopy.message(for: APIError.server(status: 409, reason: "GROUP_EXISTS"), context: .write) == "已有同名分组。")
}
