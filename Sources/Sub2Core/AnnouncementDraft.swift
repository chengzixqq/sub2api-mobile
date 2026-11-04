import Foundation

/// Who the edit sheet works on (60 §17.1): its title, its buttons and what they say when done. A status this version does
/// not know only saves.
public enum AnnouncementEditRole: Sendable, Equatable {
    case create, draft, live, archived, unknown

    public static let publishReceipt = "已发布公告"

    public init(original: Announcement?) {
        guard let original else { self = .create; return }
        switch original.status {
        case .draft?: self = .draft
        case .active?: self = .live
        case .archived?: self = .archived
        case nil: self = .unknown
        }
    }

    public var sheetTitle: String { self == .create ? "新建公告" : "编辑公告" }
    /// 存草稿 for a new one or a draft, 保存 otherwise.
    public var trailingTitle: String { self == .create || self == .draft ? "存草稿" : "保存" }
    /// The bottom button; a live one has none.
    public var primaryTitle: String? {
        switch self {
        case .create, .draft: "发布"
        case .archived: "重新发布"
        case .live, .unknown: nil
        }
    }
    /// What 存草稿 / 保存 writes as status: a new one is a draft, an edit keeps its status.
    public var trailingStatus: AnnouncementStatus? { self == .create ? .draft : nil }
    public var trailingReceipt: String {
        switch self {
        case .create, .draft: "已存为草稿"
        case .live: "已保存 · 用户看到的是新内容"
        case .archived, .unknown: "已保存"
        }
    }
}

public enum AnnouncementTargetMode: String, CaseIterable, Sendable {
    case all, custom
    public var title: String { self == .all ? "所有用户" : "按条件" }
}

public enum AnnouncementConditionKind: String, CaseIterable, Sendable {
    case subscription, balance
    public var title: String { self == .subscription ? "订阅套餐" : "余额" }
}

/// The comparisons the phone offers; eq stays on Web (60 §17.3).
public enum AnnouncementBalanceOperator: String, CaseIterable, Sendable {
    case gt, gte, lt, lte
    public var symbol: String { AnnouncementPresentation.comparisonSymbol(rawValue) ?? rawValue }
    /// What VoiceOver reads for the symbol.
    public var spokenTitle: String {
        switch self {
        case .gt: "大于"
        case .gte: "大于等于"
        case .lt: "小于"
        case .lte: "小于等于"
        }
    }
}

/// A chip of “持有以下任一套餐”: an enabled subscription group, or a chosen one that is disabled or gone (greyed, kept).
public struct AnnouncementGroupOption: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let isAvailable: Bool
    public init(id: Int, name: String, isAvailable: Bool) { self.id = id; self.name = name; self.isAvailable = isAvailable }
}

/// A line of a read-only targeting: “条件 …”, then “或 …” for each further group.
public struct AnnouncementLockedLine: Sendable, Equatable {
    public let prefix: String
    public let text: String
    public init(prefix: String, text: String) { self.prefix = prefix; self.text = text }
}

/// The edit sheet's form (60 §17.3, §17.4). Start and end are the phone's times (00 §6.3); a pick keeps its value while
/// 立即 / 永久 is chosen. A targeting the phone cannot edit (several groups or conditions, eq, an amount of 0) is kept
/// read-only and never sent.
public struct AnnouncementDraft: Sendable, Equatable {
    public static let amountIntegerDigits = 10, amountFractionDigits = 2
    public var title: String
    public var content: String
    public var notifyMode: AnnouncementNotifyMode
    public var targetMode: AnnouncementTargetMode
    public var conditionKind: AnnouncementConditionKind
    public var groupIDs: Set<Int>
    public var balanceOperator: AnnouncementBalanceOperator
    public var balanceText: String
    public var startsSpecified: Bool
    public var endsSpecified: Bool
    public var startPick: Date
    public var endPick: Date
    public let lockedTargeting: AnnouncementTargeting?

    private static let week: TimeInterval = 7 * 86_400

    /// A new one: 静默, 所有用户 (余额 < 5 ready under 按条件), 立即 – 永久; the picks start at the next whole hour and end a
    /// week later.
    public init(now: Date, timeZone: TimeZone) { self.init(now: now, timeZone: timeZone, locked: nil) }

    /// Filled from an announcement; everyone or one condition the form can save is editable (AnnouncementPresentation.isSimpleTarget).
    public init(announcement: Announcement, now: Date, timeZone: TimeZone) {
        let targeting = announcement.targeting, editable = AnnouncementPresentation.isSimpleTarget(targeting)
        self.init(now: now, timeZone: timeZone, locked: editable ? nil : targeting)
        title = announcement.title; content = announcement.content; notifyMode = announcement.notifyMode
        targetMode = targeting.isEveryone ? .all : .custom
        if editable, let condition = targeting.anyOf.first?.allOf.first { prefill(condition) }
        if let startsAt = announcement.startsAt { startsSpecified = true; startPick = startsAt }
        if let endsAt = announcement.endsAt { endsSpecified = true; endPick = endsAt } else { endPick = startPick.addingTimeInterval(Self.week) }
    }

    private init(now: Date, timeZone: TimeZone, locked: AnnouncementTargeting?) {
        title = ""; content = ""; notifyMode = .silent; targetMode = .all; conditionKind = .balance; groupIDs = []
        balanceOperator = .lt; balanceText = "5"; startsSpecified = false; endsSpecified = false
        startPick = Self.nextHour(after: now, timeZone: timeZone); endPick = startPick.addingTimeInterval(Self.week)
        lockedTargeting = locked
    }

    private mutating func prefill(_ condition: AnnouncementCondition) {
        if condition.type == AnnouncementCondition.subscriptionType {
            conditionKind = .subscription; groupIDs = Set(condition.groupIDs)
        } else if let comparison = AnnouncementBalanceOperator(rawValue: condition.operator) {
            conditionKind = .balance; balanceOperator = comparison; balanceText = "\(condition.effectiveValue)"
        }
    }

    // MARK: Input

    /// What the amount field keeps: digits and one point, at most 10 digits before it and 2 after.
    public static func sanitizedAmount(_ raw: String) -> String {
        var whole = "", fraction = "", hasPoint = false
        for character in raw {
            if character == "." { hasPoint = true; continue }
            guard character.isASCII, character.isNumber else { continue }
            if hasPoint {
                if fraction.count < amountFractionDigits { fraction.append(character) }
            } else if whole.count < amountIntegerDigits {
                whole.append(character)
            }
        }
        return hasPoint ? whole + "." + fraction : whole
    }

    public var startsAt: Date? { startsSpecified ? startPick : nil }
    public var endsAt: Date? { endsSpecified ? endPick : nil }
    public var isTargetLocked: Bool { lockedTargeting != nil }
    /// The amount above 0, nil when empty, 0 or not a number.
    public var balanceValue: Decimal? {
        guard balanceText.contains(where: { $0.isASCII && $0.isNumber }),
              let value = Decimal(string: balanceText, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    // MARK: Checks and footnotes (17.3, 17.4)

    /// Over 200 bytes after trimming, as the backend counts.
    public var titleFootnote: String? {
        AnnouncementPresentation.isTitleTooLong(title) ? AnnouncementPresentation.titleTooLongFootnote : nil
    }
    public var targetFootnote: String {
        if isTargetLocked { return AnnouncementEditCopy.lockedFootnote }
        return targetMode == .all ? AnnouncementEditCopy.everyoneFootnote : AnnouncementEditCopy.conditionFootnote
    }
    public var notifyFootnote: String { notifyMode == .popup ? AnnouncementEditCopy.popupFootnote : AnnouncementEditCopy.silentFootnote }
    /// Only both set are compared, in whole seconds as they are sent.
    public var isTimeRangeValid: Bool {
        guard let startsAt, let endsAt else { return true }
        return Self.seconds(endsAt) > Self.seconds(startsAt)
    }
    public var scheduleFootnote: String { isTimeRangeValid ? AnnouncementEditCopy.scheduleFootnote : AnnouncementEditCopy.timeRangeFootnote }
    /// 存草稿 / 保存 / 发布 are greyed otherwise.
    public var isValid: Bool {
        let titleBytes = AnnouncementPresentation.titleByteCount(title)
        return titleBytes > 0 && titleBytes <= AnnouncementCreateRequest.titleByteLimit && !trimmedContent.isEmpty && isTargetValid
            && isTimeRangeValid
    }
    private var isTargetValid: Bool {
        guard !isTargetLocked, targetMode == .custom else { return true }
        return conditionKind == .subscription ? !groupIDs.isEmpty : balanceValue != nil
    }

    // MARK: Requests (17.2, 17.4)

    /// nil for a read-only targeting, which an edit leaves out.
    public func targeting() -> AnnouncementTargeting? { isTargetLocked ? nil : editedTargeting }
    /// What the announcement will have: the read-only one, or the form's.
    public var effectiveTargeting: AnnouncementTargeting { lockedTargeting ?? editedTargeting }
    private var editedTargeting: AnnouncementTargeting {
        guard targetMode == .custom else { return .everyone }
        switch conditionKind {
        case .subscription: return .single(.subscription(groupIDs: groupIDs.sorted()))
        case .balance: return .single(.balance(balanceOperator.rawValue, value: balanceValue ?? 0))
        }
    }

    public func createRequest(status: AnnouncementStatus) -> AnnouncementCreateRequest {
        AnnouncementCreateRequest(title: trimmedTitle, content: trimmedContent, status: status, notifyMode: notifyMode,
                                  targeting: effectiveTargeting, startsAt: startsAt, endsAt: endsAt)
    }
    /// Only the keys that changed; a time set back to 立即 / 永久 is 0, a targeting back to everyone `{}`, `status` only when
    /// it differs.
    public func updateRequest(from original: Announcement, status: AnnouncementStatus?) -> AnnouncementUpdateRequest {
        var request = AnnouncementUpdateRequest()
        if trimmedTitle != Self.trimmed(original.title) { request.title = trimmedTitle }
        if trimmedContent != Self.trimmed(original.content) { request.content = trimmedContent }
        if notifyMode != original.notifyMode { request.notifyMode = notifyMode }
        if let targeting = targeting(), !targeting.isEquivalent(to: original.targeting) { request.targeting = targeting }
        request.startsAt = Self.scheduleChange(startsAt, from: original.startsAt)
        request.endsAt = Self.scheduleChange(endsAt, from: original.endsAt)
        if let status, status != original.status { request.status = status }
        return request
    }
    /// What would be saved differs: a pick behind 立即, a condition behind 所有用户 or “10.50” for “10.5” is no change.
    public func hasChanges(comparedTo baseline: AnnouncementDraft) -> Bool { fingerprint != baseline.fingerprint }

    // MARK: Options (17.2, 17.3)

    /// Enabled subscription groups in the directory's order; a chosen one that is disabled or not a subscription group stays,
    /// greyed, and one missing from the directory follows as “分组 #id”.
    public static func subscriptionOptions(groups: [AdminGroup], selected: Set<Int>) -> [AnnouncementGroupOption] {
        let listed = groups.compactMap { group -> AnnouncementGroupOption? in
            guard group.isActiveSubscriptionGroup || selected.contains(group.id) else { return nil }
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "分组 #\(group.id)" : group.name
            return AnnouncementGroupOption(id: group.id, name: name, isAvailable: group.isActiveSubscriptionGroup)
        }
        let known = Set(groups.map(\.id))
        return listed + selected.subtracting(known).sorted().map { AnnouncementGroupOption(id: $0, name: "分组 #\($0)", isAvailable: false) }
    }
    public static func lockedLines(_ targeting: AnnouncementTargeting, groupNames: (Int) -> String?) -> [AnnouncementLockedLine] {
        targeting.anyOf.enumerated().map { index, group in
            AnnouncementLockedLine(prefix: index == 0 ? "条件" : "或",
                                   text: group.allOf.map { AnnouncementPresentation.conditionText($0, groupNames: groupNames) }.joined(separator: " 且 "))
        }
    }

    // MARK: Helpers

    private enum TargetPrint: Equatable {
        case everyone, locked, subscription([Int]), balance(AnnouncementBalanceOperator, Decimal?)
    }
    private struct Fingerprint: Equatable {
        let title: String, content: String, notifyMode: AnnouncementNotifyMode, target: TargetPrint, startsAt: Int64?, endsAt: Int64?
    }
    private var fingerprint: Fingerprint {
        let target: TargetPrint
        if isTargetLocked { target = .locked }
        else if targetMode == .all { target = .everyone }
        else if conditionKind == .subscription { target = .subscription(groupIDs.sorted()) }
        else { target = .balance(balanceOperator, balanceValue) }
        return Fingerprint(title: trimmedTitle, content: trimmedContent, notifyMode: notifyMode, target: target,
                           startsAt: startsAt.map(Self.seconds), endsAt: endsAt.map(Self.seconds))
    }
    private var trimmedTitle: String { Self.trimmed(title) }
    private var trimmedContent: String { Self.trimmed(content) }
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whole seconds, rounded down, as AnnouncementCreateRequest / UpdateRequest send them.
    static func seconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }
    private static func nextHour(after now: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3_600)
    }
    private static func scheduleChange(_ new: Date?, from old: Date?) -> AnnouncementUpdateRequest.Schedule? {
        guard new.map(seconds) != old.map(seconds) else { return nil }
        return new.map { .at($0) } ?? .clear
    }
}

extension AnnouncementTargeting {
    /// The same audience: group ids in any order, a balance the backend left out read as 0.
    func isEquivalent(to other: AnnouncementTargeting) -> Bool { normalized == other.normalized }

    private var normalized: AnnouncementTargeting {
        AnnouncementTargeting(anyOf: anyOf.map { group in
            AnnouncementConditionGroup(allOf: group.allOf.map { condition in
                let value = condition.type == AnnouncementCondition.balanceType ? condition.effectiveValue : condition.value
                return AnnouncementCondition(type: condition.type, operator: condition.operator, groupIDs: condition.groupIDs.sorted(), value: value)
            })
        })
    }
}
