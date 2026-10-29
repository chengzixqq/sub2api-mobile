import Foundation
import Testing
@testable import Sub2Core

// S6-06: the check sheet of a pending batch and the result page as text (60 §10.3, §11.3; D17, R03, S6D1-05, S6D1-20).

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let started = ServerTime.parseTimestamp("2026-10-16T09:36:00+08:00")!
private let later = started.addingTimeInterval(300)
private let batchKey = "0a000000-0000-4000-8000-000000000002"
private func batch(_ spec: RedeemGenerateSpec = RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7)) -> PendingRedeemBatch {
    PendingRedeemBatch(id: UUID(uuidString: batchKey)!, serverID: UUID(), actorUserID: 1, createdAt: started, spec: spec)
}
private func context(_ permission: PendingRetryPermission = .allowed, readOnly: Bool = false, heldUntil: Date? = nil, legacy: Bool = false,
                     expired: Bool = false, actor: String? = nil) -> RedeemRetryContext {
    RedeemRetryContext(permission: permission, isReadOnly: readOnly, retryNotBefore: heldUntil, isLegacyServer: legacy, isPastIdempotencyExpiry: expired,
                       actorLabel: actor)
}
private func summary(_ actions: [RedeemReconcileAction]) -> [String] {
    actions.map { "\($0.kind.rawValue):\($0.title)\($0.isPrimary ? "!" : "")\($0.isEnabled ? "" : "(off)")" }
}
private func codes(_ count: Int, expiresAt: Date? = ServerTime.parseTimestamp("2026-10-23T09:36:00+08:00")) -> [AdminRedeemCode] {
    (1...count).map { AdminRedeemCode(id: $0, code: String(format: "%032lx", $0), type: "balance", value: 10, status: "unused", createdAt: started,
                                      expiresAt: expiresAt) }
}

@Test func reconcileHeadersAndFootnotesFollowTheStage() {
    typealias P = RedeemReconcilePresentation
    #expect(P.header(for: .awaitingCheck) == P.Header(systemImage: "hourglass", title: "请求可能已提交", message: "没有收到服务器确认。不要重新生成，先核对。", tone: .caution))
    #expect(P.header(for: .notGenerated(heuristic: false))
            == P.Header(systemImage: "magnifyingglass", title: "服务器上没有这一批", message: "这次生成没有生效。用同一编号重试，或者放弃。", tone: .neutral))
    #expect(P.header(for: .notGenerated(heuristic: true)).title == "服务器上没有这一批")
    #expect(P.header(for: .settled).title == "这一批已核对或已放弃"); #expect(P.header(for: .settled).message == nil)
    #expect(P.header(for: .undetermined).tone == .caution)
    #expect(P.header(for: .refused("过期时间无效")) == P.Header(systemImage: "xmark.octagon", title: "这一批没有生成", message: "过期时间无效", tone: .critical))

    #expect(P.footnote(for: .awaitingCheck, isLegacyServer: false) == "编号已保存在本机。核对会按这个编号在服务器上找这一批；用同一编号重试时，服务器生成过就直接返回那一批，不会重复生成。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。")
    #expect(P.footnote(for: .awaitingCheck, isLegacyServer: true)?.contains("另一位管理员同时生成时可能分不清") == true)
    #expect(P.footnote(for: .notGenerated(heuristic: false), isLegacyServer: false) == "重试用的是本机保存的同一个编号，服务器最多生成一批。")
    #expect(P.footnote(for: .settled, isLegacyServer: false) == nil); #expect(P.footnote(for: .refused("x"), isLegacyServer: false) == nil)
    #expect(P.notes(for: .notGenerated(heuristic: true), retry: context(), now: later) == ["另一位管理员同时生成时可能分不清"])
    #expect(P.notes(for: .notGenerated(heuristic: false), retry: context(), now: later).isEmpty)
}

@Test func reconcileReceiptReadsFromTheBatchSummary() {
    typealias P = RedeemReconcilePresentation
    #expect(P.receipt(batch(), siteName: "主站", origin: .currentSite, timeZone: shanghai, now: later) == [
        MoneyReceiptLine(id: "content", label: "内容", value: "20 个 × $10.00"),
        MoneyReceiptLine(id: "total", label: "合计", value: "$200.00"),
        MoneyReceiptLine(id: "started", label: "发起", value: "主站 · 10/16 09:36"),
        MoneyReceiptLine(id: "key", label: "幂等编号", value: batchKey, isKey: true),
    ])
    let concurrency = P.receipt(batch(RedeemGenerateSpec(type: .concurrency, value: 2, count: 5)), siteName: "主站", origin: .currentSite,
                                timeZone: shanghai, now: later)
    #expect(concurrency.map(\.id) == ["content", "started", "key"]); #expect(concurrency[0].value == "5 个 × +2 并发")
    let old = P.receipt(batch(), siteName: "主站", origin: .sameAddressOldLogin, timeZone: shanghai, now: later)
    #expect(old[2].note == "本站点的旧登录下发起"); #expect(old[0].note == nil)
}

@Test func reconcileActionsFollowStageRetryAndBusy() {
    typealias P = RedeemReconcilePresentation
    #expect(summary(P.actions(for: .awaitingCheck, retry: context(), busy: nil, now: later)) == ["check:核对生成结果!", "retry:用同一编号重试"])
    #expect(summary(P.actions(for: .awaitingCheck, retry: context(), busy: .checking, now: later)) == ["check:正在核对…!(off)", "retry:用同一编号重试(off)"])
    #expect(summary(P.actions(for: .awaitingCheck, retry: context(), busy: .retrying, now: later)) == ["check:核对生成结果!(off)", "retry:正在用同一编号重试…(off)"])
    #expect(summary(P.actions(for: .notGenerated(heuristic: false), retry: context(), busy: nil, now: later)) == ["retry:用同一编号重试!", "abandon:放弃这一批"])
    #expect(summary(P.actions(for: .undetermined, retry: context(), busy: nil, now: later))
            == ["check:核对生成结果!", "retry:用同一编号重试", "abandon:放弃这一批"])
    // Another administrator's batch: no retry at all, only abandon.
    #expect(summary(P.actions(for: .awaitingCheck, retry: context(.otherActor), busy: nil, now: later)) == ["check:核对生成结果!", "abandon:放弃这一批"])
    #expect(summary(P.actions(for: .notGenerated(heuristic: false), retry: context(.otherActor), busy: nil, now: later)) == ["abandon:放弃这一批!"])
    // Read-only and the cooldown keep the button, grey.
    #expect(summary(P.actions(for: .notGenerated(heuristic: false), retry: context(readOnly: true), busy: nil, now: later))
            == ["retry:用同一编号重试!(off)", "abandon:放弃这一批"])
    #expect(summary(P.actions(for: .awaitingCheck, retry: context(heldUntil: later.addingTimeInterval(5)), busy: nil, now: later))
            == ["check:核对生成结果!", "retry:用同一编号重试(off)"])
    #expect(P.actions(for: .settled, retry: context(), busy: nil, now: later).isEmpty)
    #expect(P.actions(for: .refused("x"), retry: context(), busy: nil, now: later).isEmpty)
}

@Test func reconcileRetryContextRules() {
    typealias P = RedeemReconcilePresentation
    let unknown = context(.allowedActorUnknown)
    #expect(unknown.offersRetry && unknown.canRetry(now: later)); #expect(unknown.restrictionLines(now: later) == ["无法确认发起人"])
    let readOnly = context(readOnly: true)
    #expect(readOnly.offersRetry && !readOnly.canRetry(now: later)); #expect(readOnly.restrictionLines(now: later) == ["当前登录的是只读令牌，不能修改"])
    let held = context(heldUntil: later.addingTimeInterval(10))
    #expect(!held.canRetry(now: later)); #expect(held.canRetry(now: later.addingTimeInterval(10)))
    #expect(held.restrictionLines(now: later) == ["服务器暂时无法受理，稍后用同一编号重试"]); #expect(held.restrictionLines(now: later.addingTimeInterval(10)).isEmpty)
    let other = context(.otherActor, actor: "bob@example.com")
    #expect(!other.offersRetry); #expect(other.restrictionLines(now: later) == ["这一批由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新生成。"])
    #expect(context(.otherActor).restrictionLines(now: later) == ["这一批由其他管理员发起，只能由同一管理员重试；可以放弃后重新生成。"])
    // An old server keeps no batch: past the idempotency record a retry may make a second one.
    let legacyExpired = context(legacy: true, expired: true)
    #expect(!legacyExpired.offersRetry); #expect(legacyExpired.restrictionLines(now: later) == [P.expiredRetryLine])
    #expect(context(legacy: true).offersRetry && context(expired: true).offersRetry)
}

@Test func reconcileResultCopy() {
    typealias P = RedeemReconcilePresentation
    let spec = RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7)
    #expect(P.resultHeader(.generated, spec: spec, codes: codes(20), timeZone: shanghai, now: later)
            == P.Header(systemImage: "checkmark.circle.fill", title: "已生成 20 个兑换码", message: "余额 · 每个 $10.00 · 10/23 过期", tone: .ok))
    #expect(P.resultHeader(.replayed, spec: spec, codes: codes(20), timeZone: shanghai, now: later).title == "已生成 20 个兑换码（服务器已有这一批，已取回）")
    #expect(P.resultHeader(.checked, spec: spec, codes: codes(20), timeZone: shanghai, now: later).title == "已核对：服务器已生成 20 个")
    let mismatch = P.resultHeader(.countMismatch(expected: 20), spec: spec, codes: codes(15), timeZone: shanghai, now: later)
    #expect(mismatch.title == "已核对：服务器上找到 15 个"); #expect(mismatch.tone == .caution)
    #expect(P.resultHeader(.probable(expected: 20), spec: spec, codes: codes(20), timeZone: shanghai, now: later).title == "找到 20 个可能是这一批的兑换码")
    #expect(P.resultHeader(.generated, spec: spec, codes: codes(1, expiresAt: nil), timeZone: shanghai, now: later).message == "余额 · 每个 $10.00 · 永不过期")
    let invitation = RedeemGenerateSpec(type: .invitation, value: 0, count: 2)
    #expect(P.resultHeader(.generated, spec: invitation, codes: codes(2, expiresAt: nil), timeZone: shanghai, now: later).message == "邀请码 · 永不过期")

    #expect(P.resultCaution(.generated, found: 20) == nil); #expect(P.resultCaution(.checked, found: 20) == nil)
    #expect(P.resultCaution(.countMismatch(expected: 20), found: 15) == "数量与发起时不符，请到 Web 核对")
    #expect(P.resultCaution(.probable(expected: 20), found: 20) == "另一位管理员同时生成时可能分不清")
    #expect(P.resultCaution(.probable(expected: 20), found: 15) == "数量与发起时不符，请到 Web 核对\n另一位管理员同时生成时可能分不清")
    #expect(RedeemResultKind.countMismatch(expected: 20).needsConfirmation && RedeemResultKind.probable(expected: 20).needsConfirmation)
    #expect(!RedeemResultKind.checked.needsConfirmation && !RedeemResultKind.replayed.needsConfirmation)

    #expect(P.resultFootnote(.generated, startedAt: nil, codes: codes(2), timeZone: shanghai, now: later) == "关闭后在列表的“今天生成”里能找到它们；导出 CSV 请在 Web 操作。")
    #expect(P.resultFootnote(.checked, startedAt: started, codes: codes(2), timeZone: shanghai, now: later)
            == "这一批是 10/16 09:36 发起时生成的，已在列表的“今天生成”里；导出 CSV 请在 Web 操作。")
    #expect(P.resultFootnote(.checked, startedAt: started, codes: codes(2), timeZone: shanghai, now: later.addingTimeInterval(86_400))
            == "这一批是 10/16 09:36 发起时生成的，已在列表的“昨天生成”里；导出 CSV 请在 Web 操作。")
    #expect(P.resultFootnote(.probable(expected: 20), startedAt: started, codes: codes(2), timeZone: shanghai, now: later) == "找到的兑换码都在列表里；导出 CSV 请在 Web 操作。")

    #expect(P.copyAllTitle(count: 20, copied: false) == "全部复制（20 个，每行一个）"); #expect(P.copyAllTitle(count: 20, copied: true) == "已复制全部 20 个")
    #expect(P.copyAllTitle(count: 1, copied: false) == "复制兑换码"); #expect(P.copyAllTitle(count: 1, copied: true) == "已复制兑换码")
    #expect(P.copyAllText(codes(2)) == String(format: "%032lx", 1) + "\n" + String(format: "%032lx", 2))
}
