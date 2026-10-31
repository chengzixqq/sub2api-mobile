import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 30 §8.3 / §8.5 (S3-14): window cells, reset moments, which platforms can be added, the sheet's inputs and draft, the copy.

private let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// Friday 2026-10-30 10:00 in Shanghai.
private let now = ServerTime.parseTimestamp("2026-10-30T10:00:00+08:00")!
private func amount(_ raw: String) -> Decimal { Decimal(string: raw)! }
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func limits(_ daily: Decimal?, _ weekly: Decimal?, _ monthly: Decimal?) -> PlatformQuotaLimits {
    PlatformQuotaLimits(daily: daily, weekly: weekly, monthly: monthly)
}
private func quota(daily: PlatformQuotaWindow = PlatformQuotaWindow(), weekly: PlatformQuotaWindow = PlatformQuotaWindow(),
                   monthly: PlatformQuotaWindow = PlatformQuotaWindow(), readable: Bool = true, platform: String = "anthropic") -> UserPlatformQuota {
    UserPlatformQuota(platform: platform, daily: daily, weekly: weekly, monthly: monthly, limitsReadable: readable)
}
private func cell(usage: String, limit: Decimal?) -> PlatformQuotaCell {
    PlatformQuotaPresentation.cell(quota(daily: PlatformQuotaWindow(usage: amount(usage), limit: limit)), kind: .daily)
}

// MARK: - 窗口格

@Test func cellTableCoversNullZeroAndThresholds() {
    let part = cell(usage: "2.8", limit: 10)
    #expect(part.headline == "28.0%" && part.reading == "$2.80 / $10" && part.tone == nil && !part.isBanned && part.kind == .daily)
    #expect(abs((part.progress ?? 0) - 0.28) < 1e-9)
    #expect(cell(usage: "7.49", limit: 10).tone == nil)
    #expect(cell(usage: "37.5", limit: 50).tone == .caution)
    #expect(cell(usage: "8.99", limit: 10).tone == .caution)
    #expect(cell(usage: "9", limit: 10).tone == .critical)
    let over = cell(usage: "3", limit: amount("2.5"))
    #expect(over.headline == "120.0%" && over.reading == "$3.00 / $2.50" && over.progress == 1 && over.tone == .critical)
    #expect(cell(usage: "1.2", limit: nil) == PlatformQuotaCell(kind: .daily, headline: "不限", reading: "已用 $1.20", progress: nil, tone: nil, isBanned: false))
    #expect(cell(usage: "1.2", limit: 0) == PlatformQuotaCell(kind: .daily, headline: "已禁止", reading: "不能使用", progress: nil, tone: .critical, isBanned: true))
    let unreadable = PlatformQuotaPresentation.cell(quota(daily: PlatformQuotaWindow(usage: amount("1.2"), limit: 10), readable: false), kind: .daily)
    #expect(unreadable.headline == "—" && unreadable.reading == "已用 $1.20" && unreadable.progress == nil && unreadable.tone == nil)
    #expect(PlatformQuotaPresentation.cells(quota()).map(\.kind) == [.daily, .weekly, .monthly])
}

@Test func bannedBadgeWhenAnyWindowIsZero() {
    #expect(quota(monthly: PlatformQuotaWindow(limit: 0)).isBanned)
    #expect(!quota(daily: PlatformQuotaWindow(limit: 10), weekly: PlatformQuotaWindow(limit: nil)).isBanned)
    #expect(PlatformQuotaPresentation.bannedBadge == "已禁止使用")
}

@Test func usageLineAndResetMomentFollowServerZone() {
    let daily = PlatformQuotaWindow(usage: amount("2.8"), limit: 10, resetsAt: at("2026-10-31T00:00:00+08:00"))
    #expect(PlatformQuotaPresentation.usageLine(daily, kind: .daily, now: now, zone: zone) == "已用 $2.80 · 明天 00:00 重置")
    let weekly = PlatformQuotaWindow(usage: 41, limit: 50, resetsAt: at("2026-11-02T00:00:00+08:00"))
    #expect(PlatformQuotaPresentation.usageLine(weekly, kind: .weekly, now: now, zone: zone) == "已用 $41.00 · 周一 00:00 重置")
    let monthly = PlatformQuotaWindow(usage: amount("2.8"), limit: 30, resetsAt: at("2026-11-20T00:00:00Z"))
    #expect(PlatformQuotaPresentation.usageLine(monthly, kind: .monthly, now: now, zone: zone) == "已用 $2.80 · 30 天滚动")
    #expect(PlatformQuotaPresentation.usageLine(PlatformQuotaWindow(usage: amount("1.2")), kind: .daily, now: now, zone: zone) == "已用 $1.20")
    #expect(PlatformQuotaPresentation.usageLine(PlatformQuotaWindow(limit: 10), kind: .daily, now: now, zone: zone) == "已用 $0.00")
    #expect(PlatformQuotaPresentation.usageLine(PlatformQuotaWindow(limit: 0, resetsAt: at("2026-10-31T00:00:00+08:00")), kind: .daily, now: now, zone: zone)
            == "已用 $0.00")

    #expect(PlatformQuotaPresentation.resetMoment(at("2026-10-30T18:00:00+08:00"), now: now, zone: zone) == "今天 18:00")
    #expect(PlatformQuotaPresentation.resetMoment(at("2026-10-30T16:00:00Z"), now: now, zone: zone) == "明天 00:00")
    #expect(PlatformQuotaPresentation.resetMoment(at("2026-11-02T00:00:00+08:00"), now: now, zone: zone) == "周一 00:00")
    #expect(PlatformQuotaPresentation.resetMoment(at("2026-11-20T00:00:00Z"), now: now, zone: zone) == "11月20日 08:00")
    #expect(PlatformQuotaPresentation.resetMoment(at("2026-10-30T09:00:00+08:00"), now: now, zone: zone) == nil)
    #expect(PlatformQuotaPresentation.resetMoment(nil, now: now, zone: zone) == nil)
}

@Test func addablePlatformsFollowCatalogOrder() {
    let catalog = MetaCatalog(platforms: ["openai", "composite", "anthropic", "zhipu", "future_ai"].map { MetaCatalog.Platform(id: $0, displayName: $0.uppercased()) },
                              platformAuth: [:])
    let existing = [quota(platform: "anthropic"), quota(platform: "legacy_ai")]
    #expect(PlatformQuotaPresentation.addablePlatforms(catalog: catalog, existing: existing) == ["openai", "zhipu", "future_ai"])
    #expect(PlatformQuotaPresentation.addablePlatforms(catalog: .builtin, existing: []).first == "anthropic")
    #expect(!PlatformQuotaPresentation.addablePlatforms(catalog: .builtin, existing: []).contains("composite"))
    let ordered = PlatformQuotaPresentation.ordered([quota(platform: "legacy_ai"), quota(platform: "zhipu"), quota(platform: "openai")], catalog: catalog)
    #expect(ordered.map(\.platform) == ["openai", "zhipu", "legacy_ai"])
    #expect(PlatformQuotaPresentation.platformName("zhipu", catalog: catalog) == "智谱 GLM")
    #expect(PlatformQuotaPresentation.platformName("future_ai", catalog: catalog) == "FUTURE_AI")
    #expect(PlatformQuotaPresentation.platformName("legacy_ai", catalog: catalog) == "legacy_ai")
}

@Test func activeSubscriptionDetection() {
    let live = AdminUserSubscription(id: 1, groupID: 4, expiresAt: now.addingTimeInterval(86_400), status: "active")
    let lapsed = AdminUserSubscription(id: 2, groupID: 4, expiresAt: now.addingTimeInterval(-60), status: "active")
    let ended = AdminUserSubscription(id: 3, groupID: 4, expiresAt: now.addingTimeInterval(86_400), status: "expired")
    let open = AdminUserSubscription(id: 4, groupID: 4, status: "active")
    #expect(PlatformQuotaPresentation.hasActiveSubscription([lapsed, live], now: now))
    #expect(PlatformQuotaPresentation.hasActiveSubscription([open], now: now))
    #expect(!PlatformQuotaPresentation.hasActiveSubscription([lapsed, ended], now: now))
    #expect(!PlatformQuotaPresentation.hasActiveSubscription([], now: now))
}

@Test func resetShowsForAnyLimitOfAnExistingQuota() {
    #expect(PlatformQuotaPresentation.showsReset(PlatformQuotaWindow(limit: 10), hasQuota: true))
    #expect(PlatformQuotaPresentation.showsReset(PlatformQuotaWindow(limit: 0), hasQuota: true))
    #expect(!PlatformQuotaPresentation.showsReset(PlatformQuotaWindow(limit: nil), hasQuota: true))
    #expect(!PlatformQuotaPresentation.showsReset(PlatformQuotaWindow(limit: 10), hasQuota: false))
}

// MARK: - 输入与草稿

@Test func inputValidation() {
    #expect(PlatformQuotaInput("") == .empty && PlatformQuotaInput("  ") == .empty)
    #expect(PlatformQuotaInput("10") == .value(10) && PlatformQuotaInput(" 2.5 ") == .value(amount("2.5")) && PlatformQuotaInput("0") == .value(0))
    #expect(PlatformQuotaInput("9999999999.99999999") == .value(amount("9999999999.99999999")))
    for bad in ["1e3", "-1", "1.2.3", "abc", ".", "1.", "１０"] { #expect(PlatformQuotaInput(bad) == .invalid("不是合法数字"), "\(bad)") }
    #expect(PlatformQuotaInput("10000000000") == .invalid("限额要小于 100 亿"))
    #expect(PlatformQuotaInput("0.000000001") == .invalid("最多 8 位小数"))
    #expect(PlatformQuotaInput.sanitized("1,5$ ab") == "1.5")
}

@Test func draftDirtyAndLimits() {
    let draft = PlatformQuotaDraft(original: limits(10, 50, nil))
    #expect(draft.text(.daily) == "10" && draft.text(.weekly) == "50" && draft.text(.monthly) == "")
    #expect(!draft.isDirty && !draft.canSave && draft.limits == limits(10, 50, nil))
    #expect(!draft.setting(.daily, to: "10.00").isDirty)
    let raised = draft.setting(.daily, to: "20")
    #expect(raised.isDirty && raised.canSave && raised.limits == limits(20, 50, nil) && !raised.cancelsQuota)
    #expect(draft.text(.daily) == "10", "setting returns a new draft")
    let broken = raised.setting(.weekly, to: "abc")
    #expect(broken.limits == nil && !broken.canSave && broken.invalidKinds == [.weekly])
    let cleared = draft.clearingAll()
    #expect(cleared.limits == PlatformQuotaLimits() && cleared.cancelsQuota && cleared.canSave)

    let fresh = PlatformQuotaDraft(original: nil)
    #expect(PlatformQuotaWindowKind.allCases.allSatisfy { fresh.text($0).isEmpty } && !fresh.isDirty)
    let banned = fresh.setting(.monthly, to: "0")
    #expect(banned.showsZeroWarning(.monthly) && !banned.showsZeroWarning(.daily) && banned.canSave && !banned.cancelsQuota)
    #expect(!banned.setting(.monthly, to: "").isDirty)
    #expect(PlatformQuotaDraft(original: limits(amount("2.5"), nil, amount("0.00000001"))).text(.monthly) == "0.00000001")
}

// MARK: - 文案与失败分类

@Test func receiptAndDialogCopy() {
    #expect(PlatformQuotaPresentation.updatedReceipt("Anthropic") == "已更新 Anthropic 的平台限额")
    #expect(PlatformQuotaPresentation.cancelledReceipt("Anthropic") == "已取消 Anthropic 的平台限额")
    #expect(PlatformQuotaPresentation.appliedName("Anthropic") == "平台限额（Anthropic）")
    #expect(PlatformQuotaPresentation.resetTitle(platform: "Anthropic", kind: .daily) == "重置 Anthropic 的日用量？")
    #expect(PlatformQuotaPresentation.resetMessage(userName: "Alice", platform: "Anthropic", kind: .daily, usage: amount("2.8"))
            == "Alice在 Anthropic 的日用量（$2.80）会归零。此操作立即生效。")
    #expect(PlatformQuotaPresentation.resetReceipt(platform: "Anthropic", kind: .weekly) == "已重置 Anthropic 周用量")
    #expect(PlatformQuotaPresentation.sheetTitle("OpenAI") == "OpenAI 限额")
    #expect(PlatformQuotaPresentation.zeroWarning("OpenAI") == "填 0 会完全禁止使用 OpenAI，不论其他窗口")
    #expect(PlatformQuotaPresentation.inputTitle(.monthly) == "月限额")
    #expect(PlatformQuotaPresentation.undoResetsUsageReceipt("Anthropic") == "已撤销，Anthropic 的已用额度会从 0 重新计算")
    #expect(PlatformQuotaPresentation.undoFailed("结果未确认，请刷新核对后再操作") == "撤销没有成功：结果未确认，请刷新核对后再操作")
    #expect(PlatformQuotaPresentation.footnote == "留空 = 不限制，0 = 禁止使用该平台。月为 30 天滚动窗口。")
    #expect(PlatformQuotaPresentation.subscriptionNotice == "此用户有活跃订阅：平台限额只在余额模式下生效，订阅模式的请求不受限额约束。")
    #expect(PlatformQuotaPresentation.sheetNoteLead + PlatformQuotaPresentation.sheetNoteBold + PlatformQuotaPresentation.sheetNoteTail
            == "留空 = 不限制；0 = 禁止使用该平台。月为 30 天滚动窗口。")
}

@Test func failuresMapToFixedCopy() {
    #expect(PlatformQuotaFailure(APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")) == .unavailable)
    #expect(PlatformQuotaFailure(APIError.server(status: 503, reason: nil)) == .unavailable)
    #expect(PlatformQuotaFailure(APIError.server(status: 400, reason: "INVALID_QUOTA_LIMIT")) == .invalidLimit)
    #expect(PlatformQuotaFailure(APIError.server(status: 404, reason: "USER_NOT_FOUND")) == .userGone)
    #expect(PlatformQuotaFailure(APIError.server(status: 404, reason: "USER_PLATFORM_QUOTA_NOT_FOUND")) == .quotaGone)
    #expect(PlatformQuotaFailure(APIError.server(status: 409, reason: "USER_PLATFORM_QUOTA_ACTIVE_EXISTS")) == .activeExists)
    #expect(PlatformQuotaFailure(APIError.transport(URLError(.timedOut))) == .unconfirmed)
    #expect(PlatformQuotaFailure(APIError.server(status: 502, reason: nil)) == .unconfirmed)
    #expect(PlatformQuotaFailure(APIError.invalidResponse) == .unconfirmed)
    #expect(PlatformQuotaFailure(CancellationError()) == nil)
    #expect(PlatformQuotaFailure(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == nil)
    let rejected = PlatformQuotaFailure(APIError.server(status: 400, reason: "VALIDATION_ERROR"))
    #expect(rejected?.message.contains("VALIDATION_ERROR") == true)
    #expect(PlatformQuotaFailure.invalidLimit.message == "限额要大于等于 0、小于 100 亿")
    #expect(PlatformQuotaFailure.unavailable.message == "站点没有启用平台限额")
    #expect(PlatformQuotaFailure.activeExists.message == "已有人重新设置了这个平台的限额，无法恢复")
    #expect(PlatformQuotaFailure.unconfirmed.message == "结果未确认，请刷新核对后再操作")
}
