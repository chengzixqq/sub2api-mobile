import Foundation

// 60 §10 批量生成兑换码: the wizard's three steps and their inputs. The rules of the values are RedeemGenerateForm's (S6-03);
// the wizard only filters what is typed and says when a step may go on.

/// 60 §10.1: 类型 · 面额与数量 · 有效期.
public enum RedeemGenerateStep: Int, CaseIterable, Sendable {
    case type = 1, value, expiry

    public static let barTitles = ["类型", "面额与数量", "有效期"]
    /// The last step also confirms (design VmoGenSteps).
    public var navigationTitle: String { self == .expiry ? "有效期与确认" : Self.barTitles[rawValue - 1] }
    /// Top left: 取消 on the first step, 上一步 after it.
    public var leadingTitle: String { self == .type ? "取消" : "上一步" }
    public var spokenPosition: String { "第 \(rawValue) 步，共 \(Self.allCases.count) 步" }
}

/// 第 3 步 · 兑换码过期.
public enum RedeemGenerateExpiryChoice: Hashable, Sendable {
    case never, days(Int), custom

    public static let options: [Self] = [.never, .days(1), .days(3), .days(7), .custom]
    public var title: String {
        switch self {
        case .never: "永不过期"
        case .days(let days): "\(days) 天"
        case .custom: "自定义"
        }
    }
    public var identifier: String {
        switch self {
        case .never: "never"
        case .days(let days): "\(days)"
        case .custom: "custom"
        }
    }
}

/// 第 2 步 · 订阅的有效天数, 30 by default.
public enum RedeemSubscriptionDaysChoice: Hashable, Sendable {
    case days(Int), custom

    public static let options: [Self] = [.days(7), .days(30), .days(90), .custom]
    public var title: String {
        switch self {
        case .days(let days): "\(days) 天"
        case .custom: "自定义"
        }
    }
    public var identifier: String {
        switch self {
        case .days(let days): "\(days)"
        case .custom: "custom"
        }
    }
}

/// What the wizard holds (60 §10.3). Every change returns a new value; going back keeps what was filled in. The face value has
/// no default (BUILDER_GUIDE), the count starts at 1 as on the web.
public struct RedeemGenerateWizard: Sendable, Equatable {
    /// The keypad: six digits in all, two of them decimals (60 §10.3, KeypadInput).
    public static let valueMaxDigits = 6
    public static let valueMaxFractionDigits = 2
    public static let countPicks = [1, 10, 20, 50, 100]
    public static let typeFootnote = "点一个类型进入下一步；生成前会再确认一次。"
    public static let noSubscriptionGroups = "站点还没有订阅类型的分组"
    public static let notesPlaceholder = "活动批次、工单号（选填）"
    public static let previewLabel = "每个兑换码的面值 · 合计"
    public static let customDaysPlaceholder = "1–3650"
    /// 1–3650 has at most four digits.
    static let dayDigits = 4
    /// The fields step 2 fills in; the rest are step 3's.
    static let valueFields: Set<RedeemGenerateForm.Field> = [.value, .concurrency, .group, .validityDays, .count]

    public private(set) var step: RedeemGenerateStep = .type
    /// Only highlighted until a tile is tapped.
    public private(set) var type: RedeemCodeType = .balance
    public private(set) var valueText = ""
    public private(set) var concurrency = 1
    public private(set) var groupID: Int?
    public private(set) var subscriptionDays: RedeemSubscriptionDaysChoice = .days(30)
    public private(set) var customSubscriptionDaysText = ""
    public private(set) var count = 1
    public private(set) var expiry: RedeemGenerateExpiryChoice = .never
    public private(set) var customExpiryDaysText = ""
    public private(set) var notes = ""

    public init() {}

    // MARK: Changes

    /// A tile: the type, then step 2.
    public func choosing(_ type: RedeemCodeType) -> Self { with { $0.type = type; $0.step = .value } }
    /// The keypad's new text; one it could not have typed is refused.
    public func editingValueText(_ text: String) -> Self {
        with { $0.valueText = KeypadInput.edit(valueText, to: text, maxDigits: Self.valueMaxDigits, maxFractionDigits: Self.valueMaxFractionDigits) }
    }
    public func settingConcurrency(_ value: Int) -> Self { with { $0.concurrency = Self.clamp(value, RedeemGenerateForm.concurrencyRange) } }
    public func selectingGroup(id: Int) -> Self { with { $0.groupID = id } }
    public func choosingSubscriptionDays(_ choice: RedeemSubscriptionDaysChoice) -> Self { with { $0.subscriptionDays = choice } }
    public func editingCustomSubscriptionDays(_ text: String) -> Self { with { $0.customSubscriptionDaysText = Self.dayText(text) } }
    public func settingCount(_ value: Int) -> Self { with { $0.count = Self.clamp(value, RedeemGenerateForm.countRange) } }
    public func choosingExpiry(_ choice: RedeemGenerateExpiryChoice) -> Self { with { $0.expiry = choice } }
    public func editingCustomExpiryDays(_ text: String) -> Self { with { $0.customExpiryDaysText = Self.dayText(text) } }
    /// The server counts runes, which are Unicode scalars.
    public func editingNotes(_ text: String) -> Self {
        with { $0.notes = String(Substring(text.unicodeScalars.prefix(RedeemGenerateForm.notesLimit))) }
    }
    /// 下一步 of step 2, only when it is filled in.
    public func advancing(subscriptionGroups: [AdminGroup]) -> Self {
        guard step == .value, canAdvance(subscriptionGroups: subscriptionGroups) else { return self }
        return with { $0.step = .expiry }
    }
    /// 上一步; the first step stays.
    public func goingBack() -> Self {
        guard let previous = RedeemGenerateStep(rawValue: step.rawValue - 1) else { return self }
        return with { $0.step = previous }
    }

    // MARK: What the steps show

    /// nil until a face value is typed.
    public var amount: Decimal? { KeypadInput.value(of: valueText) }
    /// Balance codes only.
    public var total: Decimal? { type == .balance ? amount.map { $0 * Decimal(count) } : nil }
    /// “$10”; “$0” in grey before anything is typed.
    public var amountDisplay: String { "$" + (valueText.isEmpty ? "0" : valueText) }
    public var isAmountEmpty: Bool { valueText.isEmpty }
    /// “$200.00” after “每个兑换码的面值 · 合计”.
    public var previewTotal: String { DisplayFormat.moneyExact(total ?? 0) }
    public var concurrencyLine: String { "增加并发 +\(concurrency)" }
    public var validityDays: Int? {
        switch subscriptionDays {
        case .days(let days): days
        case .custom: Int(customSubscriptionDaysText)
        }
    }
    /// nil = never expires.
    public var expiresInDays: Int? {
        switch expiry {
        case .never: nil
        case .days(let days): days
        case .custom: Int(customExpiryDaysText)
        }
    }
    /// A custom expiry needs its number; its range is the form's.
    public var isExpiryValid: Bool { expiry != .custom || Int(customExpiryDaysText) != nil }

    /// The chosen group, or the first option when it is not (or no longer) one of them.
    public func selectedGroup(in options: [AdminGroup]) -> AdminGroup? { options.first { $0.id == groupID } ?? options.first }
    /// `subscriptionGroups`: the directory's active subscription groups, in its order.
    public func form(subscriptionGroups: [AdminGroup]) -> RedeemGenerateForm {
        let group = type == .subscription ? selectedGroup(in: subscriptionGroups) : nil
        return RedeemGenerateForm(type: type, amount: amount, concurrency: concurrency, groupID: group?.id, groupName: group?.name,
                                  validityDays: validityDays, count: count, expiresInDays: expiresInDays, notes: notes)
    }
    public func canAdvance(subscriptionGroups: [AdminGroup]) -> Bool {
        form(subscriptionGroups: subscriptionGroups).invalidFields.isDisjoint(with: Self.valueFields)
    }
    public func canSubmit(subscriptionGroups: [AdminGroup]) -> Bool { spec(subscriptionGroups: subscriptionGroups) != nil }
    /// What the confirmation shows and the record keeps; nil while anything is missing.
    public func spec(subscriptionGroups: [AdminGroup]) -> RedeemGenerateSpec? {
        guard isExpiryValid else { return nil }
        return try? form(subscriptionGroups: subscriptionGroups).validated()
    }

    private func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }
    /// Half-width digits only, at most four.
    private static func dayText(_ text: String) -> String { String(text.filter { $0.isASCII && $0.isNumber }.prefix(dayDigits)) }
}

extension RedeemGenerateSummary {
    /// Step 3's receipt (60 §10.3): 类型 / 每个 / 数量 / 过期, and 合计 for balance codes.
    public var receiptLines: [MoneyReceiptLine] {
        [MoneyReceiptLine(id: "type", label: "类型", value: typeLabel), MoneyReceiptLine(id: "each", label: "每个", value: each),
         MoneyReceiptLine(id: "count", label: "数量", value: quantity), MoneyReceiptLine(id: "expiry", label: "过期", value: expiry)]
            + (total.map { [MoneyReceiptLine(id: "total", label: "合计", value: $0)] } ?? [])
    }
}

// MARK: The + of the list (60 §8.4, R03, X34)

/// “上一批兑换码的生成结果未确认”: the earliest batch of this address awaiting its result, which 先核对 opens.
public struct RedeemGenerateIntercept: Sendable, Equatable {
    public static let title = "上一批兑换码的生成结果未确认"
    public static let reconcileTitle = "先核对"
    public static let overrideTitle = "仍要生成新的一批"
    public static let cancelTitle = "取消"
    public let batchID: UUID
    /// “20 个 × $10.00 · 合计 $200.00\n5 分钟前发起。先核对，避免重复生成。”
    public let message: String
    public init(batchID: UUID, message: String) { self.batchID = batchID; self.message = message }
}

public enum RedeemGenerateEntryDecision: Sendable, Equatable {
    case open
    case intercept(RedeemGenerateIntercept)
    /// The batch file cannot be read (00 §2.5.5): nothing opens.
    case paused(message: String)

    /// `gate`: AppModel.moneyWriteGate(.redeemGenerate), which counts every site id of this address; `batches`: the records
    /// it names are looked up here, and the earliest is asked about (X34, C-26).
    public static func decide(gate: PendingMoneyGate, batches: [PendingRedeemBatch], now: Date, timeZone: TimeZone) -> Self {
        let ids: [UUID]
        switch gate {
        case .clear: return .open
        case .paused(let kind): return .paused(message: kind.unreadableMessage)
        case .overridable(let held), .blocked(let held): ids = held
        }
        let earliest = batches.filter { ids.contains($0.id) }.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard let earliest else { return .open }
        let time = DisplayFormat.relativeTime(earliest.createdAt, now: now, timeZone: timeZone)
        let line = RedeemGenerateSummary(spec: earliest.spec, now: now, timeZone: timeZone).batchLine
        let started = time + (time.last?.isNumber == true ? " " : "") + "发起。先核对，避免重复生成。"
        return .intercept(RedeemGenerateIntercept(batchID: earliest.id, message: line + "\n" + started))
    }
}
