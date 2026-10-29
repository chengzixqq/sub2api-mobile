import Foundation

/// 60 §9.3: what the edit sheet may change. A redeemed code takes only notes (409 REDEEM_CODE_USED for the rest); an unused or
/// disabled one its status, group, expiry and notes; an expired one is renewed by a new expiry.
public enum RedeemEditMode: Sendable, Equatable {
    case notesOnly, toggleable, expired

    public init(code: AdminRedeemCode) {
        guard !code.isRedeemed else { self = .notesOnly; return }
        switch code.codeStatus {
        case .unused?, .disabled?: self = .toggleable
        case .expired?: self = .expired
        case .used?, nil: self = .notesOnly
        }
    }
}

/// 过期时间 (60 §9.3); not RedeemGenerateExpiryChoice (S6D1-06).
public enum RedeemEditExpiryChoice: Hashable, Sendable {
    case keep, never, days(Int), custom
    public static let presetDays = [1, 3, 7, 30]
    /// The `redeem.edit.expiry.<…>` suffix.
    public var identifier: String {
        switch self {
        case .keep: "keep"
        case .never: "never"
        case .days(let days): "d\(days)"
        case .custom: "custom"
        }
    }
}

/// 60 §9.3–§9.4 as a value. `now` is the server-corrected clock; a time point the administrator picks or keeps is shown in the
/// phone's zone (00 §6.3 exception, U53). Only the keys that changed are sent.
public struct RedeemEditDraft: Sendable, Equatable {
    public let original: AdminRedeemCode
    public private(set) var mode: RedeemEditMode
    public var status: RedeemBatchUpdateFields.Status
    public var groupID: Int?
    public var expiry: RedeemEditExpiryChoice
    /// 自定义, to the minute.
    public var customExpiry: Date
    public var notes: String

    private static let day: TimeInterval = 86_400

    public init(code: AdminRedeemCode, now: Date) {
        original = code
        mode = RedeemEditMode(code: code)
        status = code.codeStatus == .disabled ? .disabled : .unused
        groupID = code.groupID
        expiry = code.expiresAt == nil ? .never : .keep
        let future = code.expiresAt.flatMap { $0 > now ? $0 : nil }
        customExpiry = Self.minute(future ?? now.addingTimeInterval(7 * Self.day))
        notes = code.notes ?? ""
    }

    // MARK: Sections

    public var showsStatus: Bool { mode != .notesOnly }
    public var showsExpiry: Bool { mode != .notesOnly }
    public var showsGroup: Bool { mode != .notesOnly && original.codeType == .subscription }
    /// After a 409 REDEEM_CODE_USED on a code the list still showed as unredeemed.
    public var wasSwitchedToNotesOnly: Bool { mode == .notesOnly && RedeemEditMode(code: original) != .notesOnly }
    public var expiryChoices: [RedeemEditExpiryChoice] {
        (original.expiresAt == nil ? [] : [.keep]) + [.never] + RedeemEditExpiryChoice.presetDays.map { .days($0) } + [.custom]
    }
    public func title(for choice: RedeemEditExpiryChoice, now: Date, timeZone: TimeZone) -> String {
        switch choice {
        case .keep:
            guard let expiresAt = original.expiresAt else { return "保持" }
            let pastDue = mode == .expired || expiresAt <= now
            return "保持 " + RedeemPresentation.timestamp(expiresAt, now: now, timeZone: timeZone) + (pastDue ? "（已过期）" : "")
        case .never: return "永不过期"
        case .days(let days): return "\(days) 天"
        case .custom: return "自定义"
        }
    }

    // MARK: Fields (9.4)

    public var isRenewing: Bool { mode == .expired && expiry != .keep }
    public func customIsValid(now: Date) -> Bool { customExpiry > now }
    public func fields(now: Date) -> RedeemBatchUpdateFields {
        var fields = RedeemBatchUpdateFields(notes: notesChange)
        switch mode {
        case .notesOnly: break
        case .toggleable:
            if status.rawValue != original.status { fields.status = status }
            fields.groupID = groupChange
            fields.expiresAt = expiryChange(now: now)
        case .expired:
            fields.groupID = groupChange
            if let renewal = expiryChange(now: now) {
                fields.expiresAt = renewal
                fields.status = .unused
            }
        }
        return fields
    }
    /// Never an empty `fields` (REDEEM_CODE_BATCH_UPDATE_EMPTY) nor a custom time not later than now.
    public func canSave(now: Date) -> Bool { !fields(now: now).isEmpty && !blocksCustom(now: now) }
    public mutating func switchToNotesOnly() { mode = .notesOnly }

    private var notesChange: String? {
        let typed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed == (original.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) ? nil : typed
    }
    private var groupChange: RedeemBatchUpdateFields.Group? {
        guard original.codeType == .subscription, let groupID, groupID != original.groupID else { return nil }
        return .id(groupID)
    }
    /// 保持 sends nothing, nor 永不过期 on a code that never expires; N 天 counts from now.
    private func expiryChange(now: Date) -> RedeemBatchUpdateFields.Expiry? {
        switch expiry {
        case .keep: nil
        case .never: original.expiresAt == nil && mode != .expired ? nil : .never
        case .days(let days): .at(now.addingTimeInterval(TimeInterval(days) * Self.day))
        case .custom: .at(customExpiry)
        }
    }
    private func blocksCustom(now: Date) -> Bool { showsExpiry && expiry == .custom && !customIsValid(now: now) }

    // MARK: Wording

    public var sheetTitle: String {
        switch mode {
        case .notesOnly: "编辑备注"
        case .expired: "续期兑换码"
        case .toggleable: "编辑兑换码"
        }
    }
    public var saveTitle: String { isRenewing ? "续期" : "保存" }
    public var expirySectionTitle: String { mode == .expired ? "新的过期时间" : "过期时间" }
    /// An expired code's read-only status: “已过期”, or “已过期 → 未使用” once a new time is chosen.
    public var statusTitles: [String] {
        isRenewing ? [RedeemCodeStatus.expired.label, RedeemCodeStatus.unused.label] : [RedeemCodeStatus.expired.label]
    }
    public func expiryFootnote(now: Date, timeZone: TimeZone) -> String {
        if blocksCustom(now: now) { return RedeemEditCopy.customInvalid }
        guard mode == .expired else { return "从现在算起；永不过期 = 一直可兑换。" }
        guard isRenewing else { return "选一个新的过期时间即可续期；保持原时间只改备注。" }
        let when = renewedAt(now: now).map { " " + RedeemPresentation.timestamp($0, now: now, timeZone: timeZone) + " 过期" } ?? "永不过期"
        return "保存后" + when + "，状态改回“未使用”。"
    }
    /// 已续期 · 10/30 过期，改回未使用 / 已保存备注 / 已保存兑换码.
    public func successReceipt(for fields: RedeemBatchUpdateFields, now: Date, timeZone: TimeZone) -> String {
        if mode == .expired, let renewal = fields.expiresAt {
            switch renewal {
            case .never: return "已续期 · 永不过期，改回未使用"
            case .at(let date): return "已续期 · " + RedeemPresentation.day(date, now: now, timeZone: timeZone) + " 过期，改回未使用"
            }
        }
        return fields.touchesOnlyNotes ? "已保存备注" : "已保存兑换码"
    }
    private func renewedAt(now: Date) -> Date? {
        guard case .at(let date)? = expiryChange(now: now) else { return nil }
        return date
    }

    private static func minute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}

/// 60 §8.4 / §9.3 / §9.4 wording that is not a draft's.
public enum RedeemEditCopy {
    public static let objectNoun = "兑换码"
    public static let usedBanner = "已使用的兑换码只能改备注。"
    public static let statusFootnote = "禁用后不能再兑换，可以随时重新启用。"
    public static let notesPlaceholder = "例如：活动批次、工单号"
    public static let notesFootnote = "只有管理员看得到。"
    public static let customInvalid = "过期时间要晚于现在。"
    public static let customLabel = "过期于"
    public static let disabled = "已禁用 · 不能再兑换"
    public static let enabled = "已启用 · 可以兑换"
    public static let toggleUsed = "这个码已被兑换，不能再改状态"
    public static let editUsed = "这个码已被兑换，只能改备注"
    public static let deleteUsed = "已被兑换的兑换码不能删除"
    public static let gone = RedeemListText.locatedGone
    public static let unconfirmed = "结果未确认，请刷新核对后再操作"
    /// The sheet stays open: the same save may be sent again (absolute values, 9.4).
    public static let saveUnconfirmed = "结果未确认，可以原样重试"

    /// “余额 · $10.00 · 面值生成后不能改”.
    public static func targetLine(_ code: AdminRedeemCode) -> String {
        [RedeemPresentation.typeLabel(code.type), RedeemPresentation.faceValue(code).text, "面值生成后不能改"].joined(separator: " · ")
    }
    public static func usedBy(name: String, at time: String) -> String { "使用者 \(name) · \(time)" }
    /// The delete confirmation's second line: “余额 · $10.00 · 未使用”.
    public static func deleteConsequence(_ code: AdminRedeemCode) -> String { RedeemPresentation.menuMessage(code) }
    /// A current group that is no longer an active subscription group stays selectable as it was.
    public static func groupDisabled(_ name: String) -> String { name + "（已停用）" }
}

/// How a batch-update or delete of one code failed (60 §8.4, §9.4): never resent on its own (00 §2.4).
public enum RedeemWriteFailure: Equatable, Sendable {
    /// 409 REDEEM_CODE_USED.
    case used
    /// 404 REDEEM_CODE_NOT_FOUND.
    case gone
    /// 400 REDEEM_CODE_EXPIRES_AT_INVALID.
    case expiresAtInvalid
    /// 400 REDEEM_CODE_GROUP_ID_INVALID, and REDEEM_CODE_STATUS_INVALID with the same words (9.4).
    case groupInvalid
    /// Lost connection, an unreadable reply, 502 / 504 or a 503 without its own reason: read back.
    case unconfirmed
    case cancelled
    /// Compliance or step-up cleared it: the notice, then the same action again.
    case reconfirm(String)
    /// Catalog text.
    case other(String)

    public static let usedReason = "REDEEM_CODE_USED"
    public static let notFoundReason = "REDEEM_CODE_NOT_FOUND"

    public var message: String {
        switch self {
        case .used: RedeemEditCopy.editUsed
        case .gone: RedeemEditCopy.gone
        case .expiresAtInvalid: "过期时间要晚于现在"
        case .groupInvalid: "分组无效，请重新选择"
        case .unconfirmed: RedeemEditCopy.unconfirmed
        case .cancelled: ""
        case .reconfirm(let text), .other(let text): text
        }
    }

    public static func classify(_ error: any Error) -> RedeemWriteFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .other(error.localizedDescription) }
        switch api.securityOutcome {
        case .passed?: return .reconfirm(api.localizedDescription)
        case .cancelled?: return .cancelled
        case .blocked?, nil: break
        }
        switch (api.statusCode, api.reason) {
        case (409?, Self.usedReason?): return .used
        case (404?, Self.notFoundReason?): return .gone
        case (400?, "REDEEM_CODE_EXPIRES_AT_INVALID"?): return .expiresAtInvalid
        case (400?, "REDEEM_CODE_GROUP_ID_INVALID"?), (400?, "REDEEM_CODE_STATUS_INVALID"?): return .groupInvalid
        default: break
        }
        // A refresh that failed before sending was never sent.
        guard api != .refreshDeferred else { return .other(api.localizedDescription) }
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? .unconfirmed : .other(api.localizedDescription)
        }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed : .other(api.localizedDescription)
    }
}

extension RedeemBatchUpdateFields {
    public var touchesOnlyNotes: Bool { notes != nil && !touchesUsedSensitiveFields }
    /// The read-back after a lost reply: only the keys that were sent, an expiry to the second. An unused code read back as
    /// expired was not renewed.
    public func isReflected(in code: AdminRedeemCode) -> Bool {
        if let status, code.status != status.rawValue { return false }
        switch expiresAt {
        case nil: break
        case .never?: if code.expiresAt != nil { return false }
        case .at(let date)?:
            guard let read = code.expiresAt, abs(read.timeIntervalSince(date)) < 1 else { return false }
        }
        switch groupID {
        case nil: break
        case .cleared?: if code.groupID != nil { return false }
        case .id(let id)?: if code.groupID != id { return false }
        }
        if let notes, (code.notes ?? "") != notes { return false }
        return true
    }
}

extension AdminRedeemCode {
    /// The optimistic badge of 禁用 / 启用; everything else as listed.
    public func replacing(status: String) -> AdminRedeemCode {
        AdminRedeemCode(id: id, code: code, type: type, value: value, status: status, usedBy: usedBy, usedAt: usedAt, createdAt: createdAt,
                        expiresAt: expiresAt, groupID: groupID, validityDays: validityDays, notes: notes, batchID: batchID,
                        createdBy: createdBy, user: user, group: group)
    }
}
