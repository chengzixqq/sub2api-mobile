import Foundation

/// Where the check sheet of a pending batch stands (60 §11.3).
public enum RedeemReconcileStage: Sendable, Equatable {
    /// Before a check: 请求可能已提交.
    case awaitingCheck
    /// The check found nothing; `heuristic` when an old server's newest codes stood in for its batch_id.
    case notGenerated(heuristic: Bool)
    /// An old server's newest page could not tell.
    case undetermined
    /// The record is gone: checked, given up or settled elsewhere.
    case settled
    /// A retry was refused for its body: nothing was generated and the record is gone.
    case refused(String)
}

/// The result page shared by the generate sheet (S6-07) and the check sheet (60 §10.3, §11.3).
public enum RedeemResultKind: Sendable, Equatable {
    case generated, replayed
    /// Found whole under its batch_id; the record is settled.
    case checked
    /// Under its batch_id but fewer than asked for: kept until “我已核对”.
    case countMismatch(expected: Int)
    /// An old server's newest codes that look like the batch: kept until “我已核对”.
    case probable(expected: Int)
    public var needsConfirmation: Bool {
        switch self {
        case .countMismatch, .probable: true
        case .generated, .replayed, .checked: false
        }
    }
}

/// One row of a pending money write's receipt (60 §11.3; S6-09 shows its compensations with it): a note under the value, and
/// the record's number drawn monospaced and selectable.
public struct MoneyReceiptLine: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let note: String?
    public let isKey: Bool
    public init(id: String, label: String, value: String, note: String? = nil, isKey: Bool = false) {
        self.id = id; self.label = label; self.value = value; self.note = note; self.isKey = isKey
    }
}

/// Whether “用同一编号重试” is offered and may be tapped now (00 §2.5.2, D17, R03, X34): only the sender at this address,
/// not with a read-only token, not during STORE_UNAVAILABLE's cooldown, and on a server without batches not once its
/// idempotency record may be gone (a retry there could make a second batch).
public struct RedeemRetryContext: Sendable, Equatable {
    public let permission: PendingRetryPermission
    public let isReadOnly: Bool
    public let retryNotBefore: Date?
    public let isLegacyServer: Bool
    public let isPastIdempotencyExpiry: Bool
    /// The sender's email or “管理员 #7”, read only for another administrator's record.
    public let actorLabel: String?
    public init(permission: PendingRetryPermission, isReadOnly: Bool, retryNotBefore: Date?, isLegacyServer: Bool, isPastIdempotencyExpiry: Bool,
                actorLabel: String? = nil) {
        self.permission = permission; self.isReadOnly = isReadOnly; self.retryNotBefore = retryNotBefore; self.isLegacyServer = isLegacyServer
        self.isPastIdempotencyExpiry = isPastIdempotencyExpiry; self.actorLabel = actorLabel
    }
    public var offersRetry: Bool { permission != .otherActor && !(isLegacyServer && isPastIdempotencyExpiry) }
    public func isHeld(now: Date) -> Bool { retryNotBefore.map { now < $0 } ?? false }
    public func canRetry(now: Date) -> Bool { offersRetry && !isReadOnly && !isHeld(now: now) }
    /// Why the retry is missing or grey; read-only says it all.
    public func restrictionLines(now: Date) -> [String] {
        if permission == .otherActor { return [RedeemReconcilePresentation.otherActorLine(actorLabel)] }
        if !offersRetry { return [RedeemReconcilePresentation.expiredRetryLine] }
        var lines: [String] = []
        if permission == .allowedActorUnknown { lines.append(BalanceReconcilePresentation.unknownActorLine) }
        if isReadOnly { lines.append(BalanceReconcilePresentation.readOnlyLine) } else if isHeld(now: now) { lines.append(BalanceReconcilePresentation.heldLine) }
        return lines
    }
}

public struct RedeemReconcileAction: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case check, retry, abandon }
    public let kind: Kind
    public let title: String
    public let isPrimary: Bool
    public let isEnabled: Bool
    public var id: Kind { kind }
}

/// 60 §10.3 and §11.3 as text, word for word: the check sheet's header, receipt, buttons and footnotes, and the result page.
public enum RedeemReconcilePresentation {
    public struct Header: Sendable, Equatable {
        public let systemImage: String
        public let title: String
        public let message: String?
        public let tone: Tone
        public init(systemImage: String, title: String, message: String?, tone: Tone) {
            self.systemImage = systemImage; self.title = title; self.message = message; self.tone = tone
        }
    }
    /// One request at a time: both buttons wait, the running one says so.
    public enum Busy: Sendable, Equatable { case checking, retrying }

    public static let checkTitle = "核对生成结果"
    public static let retryTitle = "用同一编号重试"
    public static let abandonTitle = "放弃这一批"
    public static let confirmTitle = "我已核对"
    public static let pendingFootnote = "编号已保存在本机。核对会按这个编号在服务器上找这一批；用同一编号重试时，服务器生成过就直接返回那一批，不会重复生成。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。"
    /// A server without batches is matched by type, face value and time (60 §11.4 末条).
    public static let legacyPendingFootnote = "编号已保存在本机。这个站点的版本较旧，核对会按类型、面值和发起时间在最近生成的兑换码里找这一批，"
        + RedeemBatchFallback.ambiguityNote + "。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。"
    public static let notFoundFootnote = "重试用的是本机保存的同一个编号，服务器最多生成一批。"
    public static let expiredRetryLine = "这一批已超过服务器保留编号的时间，用同一编号重试可能再生成一批；请核对或放弃"
    public static let revealFailedText = "服务器已返回这一批，但没能读出兑换码，请稍后再核对"
    public static let abandonPromptTitle = "放弃这一批？"
    public static let abandonPromptMessage = "放弃后不再提醒，也不会再重试。如果服务器其实已经生成，这些兑换码仍在列表里，可以禁用或删除。"
    public static let abandonReceipt = "已放弃这一批 · 不再提醒"
    public static let confirmedReceipt = "已核对这一批 · 不再提醒"
    static let generatedFootnote = "关闭后在列表的“今天生成”里能找到它们；导出 CSV 请在 Web 操作。"

    /// 00 §2.5.2: “这一批由 <邮箱> 发起，只能由同一管理员重试；可以放弃后重新生成。”; Latin letters next to Chinese get a space.
    public static func otherActorLine(_ label: String?) -> String {
        let name = label ?? "其他管理员"
        let lead = name.first?.isASCII == true ? " " : "", trail = name.last?.isASCII == true ? " " : ""
        return "这一批由\(lead)\(name)\(trail)发起，只能由同一管理员重试；可以放弃后重新生成。"
    }

    // MARK: Check sheet

    public static func header(for stage: RedeemReconcileStage) -> Header {
        switch stage {
        case .awaitingCheck: Header(systemImage: "hourglass", title: "请求可能已提交", message: "没有收到服务器确认。不要重新生成，先核对。", tone: .caution)
        case .notGenerated: Header(systemImage: "magnifyingglass", title: "服务器上没有这一批", message: "这次生成没有生效。用同一编号重试，或者放弃。", tone: .neutral)
        case .undetermined:
            Header(systemImage: "questionmark.circle", title: "无法判断这一批是否已生成", message: "最近生成的兑换码太多，分不出这一批。请到 Web 的兑换码列表核对。",
                   tone: .caution)
        case .settled: Header(systemImage: "checkmark.circle", title: "这一批已核对或已放弃", message: nil, tone: .neutral)
        case .refused(let message): Header(systemImage: "xmark.octagon", title: "这一批没有生成", message: message, tone: .critical)
        }
    }
    public static func footnote(for stage: RedeemReconcileStage, isLegacyServer: Bool) -> String? {
        switch stage {
        case .awaitingCheck: isLegacyServer ? legacyPendingFootnote : pendingFootnote
        case .notGenerated, .undetermined: notFoundFootnote
        case .settled, .refused: nil
        }
    }
    /// Lines under the buttons: the old server's caveat, then why the retry is missing or grey.
    public static func notes(for stage: RedeemReconcileStage, retry: RedeemRetryContext, now: Date) -> [String] {
        switch stage {
        case .settled, .refused: return []
        case .notGenerated(heuristic: true): return [RedeemBatchFallback.ambiguityNote] + retry.restrictionLines(now: now)
        case .awaitingCheck, .notGenerated, .undetermined: return retry.restrictionLines(now: now)
        }
    }
    /// 内容 and 合计 come from the batch's summary (S6D1-05); 发起 is the site and the time on its calendar, with the older
    /// login's note (S6D1-20); the number is the batch_id the server keeps.
    public static func receipt(_ batch: PendingRedeemBatch, siteName: String, origin: MoneyRecordOrigin.Kind, timeZone: ServerTimeZone, now: Date) -> [MoneyReceiptLine] {
        let summary = RedeemGenerateSummary(spec: batch.spec, now: now, timeZone: timeZone.timeZone)
        var lines = [MoneyReceiptLine(id: "content", label: "内容", value: "\(batch.count) 个 × \(summary.each)")]
        if let total = summary.total { lines.append(MoneyReceiptLine(id: "total", label: "合计", value: total)) }
        lines.append(MoneyReceiptLine(id: "started", label: "发起", value: siteName + " · " + DisplayFormat.monthDayClock(batch.createdAt, timeZone: timeZone, now: now),
                                      note: origin == .sameAddressOldLogin ? MoneyRecordOrigin.oldLoginNote : nil))
        lines.append(MoneyReceiptLine(id: "key", label: "幂等编号", value: batch.key, isKey: true))
        return lines
    }
    /// Another administrator's batch is only checked or given up; a grey retry stays where it would be.
    public static func actions(for stage: RedeemReconcileStage, retry: RedeemRetryContext, busy: Busy?, now: Date) -> [RedeemReconcileAction] {
        let idle = busy == nil
        let check = RedeemReconcileAction(kind: .check, title: busy == .checking ? "正在核对…" : checkTitle, isPrimary: true, isEnabled: idle)
        func retryAction(primary: Bool) -> RedeemReconcileAction {
            RedeemReconcileAction(kind: .retry, title: busy == .retrying ? "正在用同一编号重试…" : retryTitle, isPrimary: primary,
                                  isEnabled: idle && retry.canRetry(now: now))
        }
        func abandon(primary: Bool) -> RedeemReconcileAction { RedeemReconcileAction(kind: .abandon, title: abandonTitle, isPrimary: primary, isEnabled: idle) }
        switch stage {
        case .awaitingCheck: return [check, retry.offersRetry ? retryAction(primary: false) : abandon(primary: false)]
        case .notGenerated: return retry.offersRetry ? [retryAction(primary: true), abandon(primary: false)] : [abandon(primary: true)]
        case .undetermined: return [check] + (retry.offersRetry ? [retryAction(primary: false)] : []) + [abandon(primary: false)]
        case .settled, .refused: return []
        }
    }

    // MARK: Result page

    /// Green for a batch the server confirmed; caution for one the administrator still has to confirm.
    public static func resultHeader(_ kind: RedeemResultKind, spec: RedeemGenerateSpec, codes: [AdminRedeemCode], timeZone: ServerTimeZone, now: Date) -> Header {
        let count = codes.count
        let title = switch kind {
        case .generated: "已生成 \(count) 个兑换码"
        case .replayed: "已生成 \(count) 个兑换码（服务器已有这一批，已取回）"
        case .checked: "已核对：服务器已生成 \(count) 个"
        case .countMismatch: "已核对：服务器上找到 \(count) 个"
        case .probable: "找到 \(count) 个可能是这一批的兑换码"
        }
        return Header(systemImage: kind.needsConfirmation ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", title: title,
                      message: subline(spec, codes: codes, timeZone: timeZone, now: now), tone: kind.needsConfirmation ? .caution : .ok)
    }
    public static func resultCaution(_ kind: RedeemResultKind, found: Int) -> String? {
        let mismatch = "数量与发起时不符，请到 Web 核对"
        switch kind {
        case .generated, .replayed, .checked: return nil
        case .countMismatch: return mismatch
        case .probable(let expected): return ((found == expected ? [] : [mismatch]) + [RedeemBatchFallback.ambiguityNote]).joined(separator: "\n")
        }
    }
    /// The check's footnote names the section the batch sits in now.
    public static func resultFootnote(_ kind: RedeemResultKind, startedAt: Date?, codes: [AdminRedeemCode], timeZone: ServerTimeZone, now: Date) -> String {
        switch kind {
        case .generated, .replayed: return generatedFootnote
        case .countMismatch, .probable: return "找到的兑换码都在列表里；导出 CSV 请在 Web 操作。"
        case .checked:
            let section = RedeemPresentation.dayGroup(codes.first?.createdAt ?? startedAt, now: now, timeZone: timeZone.timeZone).title
            let start = startedAt.map { "这一批是 " + DisplayFormat.monthDayClock($0, timeZone: timeZone, now: now) + " 发起时生成的，" } ?? "这一批"
            return start + "已在列表的“\(section)”里；导出 CSV 请在 Web 操作。"
        }
    }
    public static func copyAllTitle(count: Int, copied: Bool) -> String {
        guard count > 1 else { return copied ? RedeemListText.copiedReceipt : "复制兑换码" }
        return copied ? "已复制全部 \(count) 个" : "全部复制（\(count) 个，每行一个）"
    }
    /// One code per line, nothing else.
    public static func copyAllText(_ codes: [AdminRedeemCode]) -> String { codes.map(\.code).joined(separator: "\n") }

    /// “余额 · 每个 $10.00 · 10/23 过期”: the expiry the server stamped on the codes.
    private static func subline(_ spec: RedeemGenerateSpec, codes: [AdminRedeemCode], timeZone: ServerTimeZone, now: Date) -> String {
        let each = spec.type == .invitation ? nil : "每个 " + RedeemGenerateSummary(spec: spec, now: now, timeZone: timeZone.timeZone).each
        let expiry = codes.first?.expiresAt.map { RedeemPresentation.day($0, now: now, timeZone: timeZone.timeZone) + " 过期" } ?? "永不过期"
        return [spec.type.label, each, expiry].compactMap { $0 }.joined(separator: " · ")
    }
}
