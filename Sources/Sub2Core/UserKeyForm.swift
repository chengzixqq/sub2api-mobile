import Foundation

/// The rows of the new / edit key form (30 §7.4), in form order.
public enum UserKeyField: String, CaseIterable, Sendable {
    case name, group, quota, resetQuota, expiry, ipWhitelist, ipBlacklist, rateLimit5h, rateLimit1d, rateLimit7d
}

/// 新建 Key 的有效期.
public enum UserKeyExpiryChoice: String, CaseIterable, Hashable, Sendable {
    case never, days7, days30, days90, custom
    public var title: String {
        switch self {
        case .never: "永久"
        case .days7: "7 天"
        case .days30: "30 天"
        case .days90: "90 天"
        case .custom: "自定义"
        }
    }
    var days: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .never, .custom: nil
        }
    }
}

/// 编辑 Key 的有效期: never, or a day on the server's calendar (sent as its 23:59:59, R20).
public enum UserKeyEditExpiry: Hashable, Sendable {
    case never
    case on(Date)
}

public struct UserKeyIssue: Sendable, Equatable {
    public let field: UserKeyField
    public let message: String
    public init(field: UserKeyField, message: String) { self.field = field; self.message = message }
}

/// What the form holds, as typed. Amounts are text: empty and 0 are both “不限”.
public struct UserKeyDraft: Sendable, Equatable {
    public var name = ""
    /// nil: 不绑定分组 (new keys only; an existing key changes group from its card).
    public var groupID: Int?
    public var quota = ""
    public var resetQuota = false
    public var expiryChoice = UserKeyExpiryChoice.never
    public var customDays = ""
    public var editExpiry = UserKeyEditExpiry.never
    /// One IP or CIDR per line.
    public var ipWhitelist = ""
    public var ipBlacklist = ""
    public var rateLimit5h = ""
    public var rateLimit1d = ""
    public var rateLimit7d = ""

    public init() {}
    /// The key as it is: the name unescaped (S3D1-12), 0 left empty, one IP per line.
    public init(editing key: AdminAPIKey) {
        name = key.displayName
        quota = Self.text(key.quota)
        editExpiry = key.expiresAt.map(UserKeyEditExpiry.on) ?? .never
        ipWhitelist = key.ipWhitelist.joined(separator: "\n")
        ipBlacklist = key.ipBlacklist.joined(separator: "\n")
        rateLimit5h = Self.text(key.rateLimit5h)
        rateLimit1d = Self.text(key.rateLimit1d)
        rateLimit7d = Self.text(key.rateLimit7d)
    }
    private static func text(_ value: Decimal) -> String { value > 0 ? "\(value)" : "" }
}

/// 30 §7.4 新建 / 编辑 Key: checks in form order, the requests, the undo and the read-back. Pure, so the sheet only binds.
public enum UserKeyForm {
    public static let maxCustomDays = 36_500
    /// ent `MaxLen(100)` counts the stored, escaped name in bytes; beyond it the server answers 500 without a reason.
    public static let nameMaxBytes = 100

    // MARK: - 输入

    /// Lines trimmed, empty ones dropped (the server checks each entry as given, so a stray space would fail it).
    public static func ipLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// Go `net.ParseCIDR` with a "/", else `net.ParseIP` (pkg/ip `ValidateIPPattern`): no zone, no leading zero in an IPv4
    /// field, a prefix of at most 32 / 128 bits.
    public static func isValidIPPattern(_ text: String) -> Bool {
        IPPattern.isValid(text)
    }
    /// "" is 0; otherwise ASCII digits with an optional fraction of at most 8 digits, within the server's limit.
    public static func amount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value <= maximumAmount, value.hasAtMostFractionDigits(8) else { return nil }
        return value
    }
    /// 1–36500 ASCII digits.
    public static func customDays(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^[0-9]{1,5}$"#, options: .regularExpression) != nil, let days = Int(trimmed),
              (1...maxCustomDays).contains(days) else { return nil }
        return days
    }
    /// nil: never expires.
    public static func expiresInDays(_ draft: UserKeyDraft) -> Int? {
        draft.expiryChoice == .custom ? customDays(draft.customDays) : draft.expiryChoice.days
    }
    /// 23:59:59 of that day on the server's calendar.
    public static func endOfDay(_ day: Date, in zone: ServerTimeZone) -> Date {
        let calendar = zone.calendar
        let start = calendar.startOfDay(for: day)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)).addingTimeInterval(-1)
    }

    // MARK: - 校验

    public static func issues(_ draft: UserKeyDraft, editing original: AdminAPIKey?, zone: ServerTimeZone, now: Date) -> [UserKeyIssue] {
        var issues = [UserKeyIssue]()
        if let message = nameIssue(draft.name) { issues.append(UserKeyIssue(field: .name, message: message)) }
        if amount(draft.quota) == nil { issues.append(UserKeyIssue(field: .quota, message: UserKeyFormCopy.amountInvalid)) }
        if let message = expiryIssue(draft, editing: original, zone: zone, now: now) { issues.append(UserKeyIssue(field: .expiry, message: message)) }
        for (field, text) in [(UserKeyField.ipWhitelist, draft.ipWhitelist), (.ipBlacklist, draft.ipBlacklist)] {
            if let line = ipLines(text).firstIndex(where: { !isValidIPPattern($0) }) {
                issues.append(UserKeyIssue(field: field, message: UserKeyFormCopy.ipLineInvalid(line + 1)))
            }
        }
        for (field, text) in [(UserKeyField.rateLimit5h, draft.rateLimit5h), (.rateLimit1d, draft.rateLimit1d), (.rateLimit7d, draft.rateLimit7d)]
            where amount(text) == nil {
            issues.append(UserKeyIssue(field: field, message: UserKeyFormCopy.amountInvalid))
        }
        return issues
    }
    private static func nameIssue(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return UserKeyFormCopy.nameRequired }
        return UserKeyName.escaped(trimmed).utf8.count > nameMaxBytes ? UserKeyFormCopy.nameTooLong : nil
    }
    /// Editing, only a day that was changed must still be ahead.
    private static func expiryIssue(_ draft: UserKeyDraft, editing original: AdminAPIKey?, zone: ServerTimeZone, now: Date) -> String? {
        if let original {
            guard expiryChange(draft.editExpiry, original: original.expiresAt, zone: zone) != .unchanged, case .on(let day) = draft.editExpiry,
                  endOfDay(day, in: zone) <= now else { return nil }
            return UserKeyFormCopy.expiryPast
        }
        return draft.expiryChoice == .custom && customDays(draft.customDays) == nil ? UserKeyFormCopy.customDaysInvalid : nil
    }

    // MARK: - 请求

    /// After `issues` came back empty.
    public static func createRequest(_ draft: UserKeyDraft) throws -> AdminAPIKeyCreateRequest {
        try AdminAPIKeyCreateRequest(name: draft.name, groupID: draft.groupID, quota: try value(draft.quota), expiresInDays: expiresInDays(draft),
                                     ipWhitelist: ipLines(draft.ipWhitelist), ipBlacklist: ipLines(draft.ipBlacklist),
                                     rateLimit5h: try value(draft.rateLimit5h), rateLimit1d: try value(draft.rateLimit1d),
                                     rateLimit7d: try value(draft.rateLimit7d))
    }
    /// Only what differs from the key; nil when nothing does (a name that only gained spaces included).
    public static func updateRequest(_ draft: UserKeyDraft, original: AdminAPIKey, zone: ServerTimeZone) throws -> AdminAPIKeyUpdateRequest? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        func changed(_ text: String, _ old: Decimal) throws -> Decimal? {
            let new = try value(text)
            return new == old ? nil : new
        }
        let white = ipLines(draft.ipWhitelist), black = ipLines(draft.ipBlacklist)
        let quota = try changed(draft.quota, original.quota)
        let limits = (try changed(draft.rateLimit5h, original.rateLimit5h), try changed(draft.rateLimit1d, original.rateLimit1d),
                      try changed(draft.rateLimit7d, original.rateLimit7d))
        let resetQuota = draft.resetQuota && original.quota > 0
        let expiry = expiryChange(draft.editExpiry, original: original.expiresAt, zone: zone)
        let request = (name: name == original.displayName ? nil : name, white: white == original.ipWhitelist ? nil : white,
                       black: black == original.ipBlacklist ? nil : black)
        guard request.name != nil || quota != nil || resetQuota || expiry != .unchanged || request.white != nil || request.black != nil
                || limits.0 != nil || limits.1 != nil || limits.2 != nil else { return nil }
        return try AdminAPIKeyUpdateRequest(name: request.name, quota: quota, resetQuota: resetQuota, expiresAt: expiry, ipWhitelist: request.white,
                                            ipBlacklist: request.black, rateLimit5h: limits.0, rateLimit1d: limits.1, rateLimit7d: limits.2)
    }
    /// The form differs from where it started (for a new key, from an empty form).
    public static func hasChanges(_ draft: UserKeyDraft, original: AdminAPIKey?) -> Bool {
        draft != (original.map(UserKeyDraft.init(editing:)) ?? UserKeyDraft())
    }
    /// The reply's `previous` written back: the name unescaped (the server escapes it again), a missing expiry as "", never
    /// `status` (an automatic reactivation would write quota_exhausted / expired, which PUT refuses; the server derives it again
    /// from what is written back). nil when only `quota_used` (or `status`) changed: a quota reset cannot be undone.
    public static func undoRequest(previous: AdminAPIKeyPrevious) throws -> AdminAPIKeyUpdateRequest? {
        let expiry: AdminAPIKeyUpdateRequest.Expiry = switch previous.expiresAt {
        case nil: .unchanged
        case .never?: .clear
        case .at(let date)?: .set(date)
        }
        let name = previous.name.map(UserKeyName.unescaped)
        guard name != nil || previous.quota != nil || expiry != .unchanged || previous.ipWhitelist != nil || previous.ipBlacklist != nil
                || previous.rateLimit5h != nil || previous.rateLimit1d != nil || previous.rateLimit7d != nil else { return nil }
        return try AdminAPIKeyUpdateRequest(name: name, quota: previous.quota, expiresAt: expiry, ipWhitelist: previous.ipWhitelist,
                                            ipBlacklist: previous.ipBlacklist, rateLimit5h: previous.rateLimit5h,
                                            rateLimit1d: previous.rateLimit1d, rateLimit7d: previous.rateLimit7d)
    }
    /// R06 for an edit nobody saw answered: every field that went out reads back as sent (an expiry within a second).
    public static func readbackMatches(_ sent: AdminAPIKeyUpdateRequest, server key: AdminAPIKey) -> Bool {
        guard !key.isTombstone else { return false }
        var checks: [Bool] = [sent.name.map { $0 == key.displayName } ?? true, sent.quota.map { $0 == key.quota } ?? true,
                              !sent.resetQuota || key.quotaUsed == 0, sent.ipWhitelist.map { $0 == key.ipWhitelist } ?? true,
                              sent.ipBlacklist.map { $0 == key.ipBlacklist } ?? true, sent.rateLimit5h.map { $0 == key.rateLimit5h } ?? true,
                              sent.rateLimit1d.map { $0 == key.rateLimit1d } ?? true, sent.rateLimit7d.map { $0 == key.rateLimit7d } ?? true]
        switch sent.expiresAt {
        case .unchanged: break
        case .clear: checks.append(key.expiresAt == nil)
        case .set(let date): checks.append(key.expiresAt.map { abs($0.timeIntervalSince(date)) <= 1 } ?? false)
        }
        return !checks.contains(false)
    }
    /// A replay whose plaintext the server masked (logredact): the key exists, its plaintext is gone.
    public static func isRedactedPlaintext(_ key: String) -> Bool { !key.isEmpty && key.allSatisfy { $0 == "*" } }

    // MARK: - 内部

    static let maximumAmount = Decimal(string: "999999999999.99999999", locale: Locale(identifier: "en_US_POSIX"))!
    private static func value(_ text: String) throws -> Decimal {
        guard let value = amount(text) else { throw APIError(kind: .validation, message: UserKeyFormCopy.amountInvalid) }
        return value
    }
    private static func expiryChange(_ expiry: UserKeyEditExpiry, original: Date?, zone: ServerTimeZone) -> AdminAPIKeyUpdateRequest.Expiry {
        switch expiry {
        case .never: return original == nil ? .unchanged : .clear
        case .on(let day):
            if let original, zone.calendar.isDate(original, inSameDayAs: day) { return .unchanged }
            return .set(endOfDay(day, in: zone))
        }
    }
}

/// Go `netip.ParseAddr` (no zone) and `net.ParseCIDR`.
private enum IPPattern {
    static func isValid(_ text: String) -> Bool {
        guard text.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        guard let slash = text.firstIndex(of: "/") else { return bits(of: Substring(text)) != nil }
        guard let bits = bits(of: text[..<slash]) else { return false }
        let prefix = text[text.index(after: slash)...]
        guard !prefix.isEmpty, prefix.count <= 6, prefix.allSatisfy(\.isASCIIDigit), let length = Int(prefix) else { return false }
        return length <= bits
    }
    /// 32 or 128; nil when not an address.
    private static func bits(of address: Substring) -> Int? {
        if isIPv4(address) { return 32 }
        return isIPv6(address) ? 128 : nil
    }
    static func isIPv4(_ text: Substring) -> Bool {
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        return fields.count == 4 && fields.allSatisfy { field in
            guard (1...3).contains(field.count), field.allSatisfy(\.isASCIIDigit), field.count == 1 || field.first != "0" else { return false }
            return (Int(field) ?? 256) <= 255
        }
    }
    /// “::” stands for at least one zero group; an IPv4 tail counts as two groups.
    private static func isIPv6(_ text: Substring) -> Bool {
        guard !text.contains("%") else { return false }
        let halves = text.components(separatedBy: "::")
        switch halves.count {
        case 1: return groups(Substring(halves[0]), ipv4Tail: true) == 8
        case 2:
            guard let head = groups(Substring(halves[0]), ipv4Tail: false), let tail = groups(Substring(halves[1]), ipv4Tail: true) else { return false }
            return head + tail <= 7
        default: return false
        }
    }
    private static func groups(_ part: Substring, ipv4Tail: Bool) -> Int? {
        guard !part.isEmpty else { return 0 }
        let fields = part.split(separator: ":", omittingEmptySubsequences: false)
        var count = 0
        for (index, field) in fields.enumerated() {
            if ipv4Tail, index == fields.count - 1, field.contains(".") {
                guard isIPv4(field) else { return nil }
                count += 2
            } else {
                guard (1...4).contains(field.count), field.allSatisfy(\.isHexDigit) else { return nil }
                count += 1
            }
        }
        return count
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
