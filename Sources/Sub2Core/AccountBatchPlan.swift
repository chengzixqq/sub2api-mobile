import Foundation

/// One `bulk-update` of a batch: its ids in the order they were picked, and its own key when the site keeps keyed writes.
public struct AccountBatchChunk: Sendable, Equatable {
    public let ids: [Int]
    public let idempotencyKey: UUID?
    public init(ids: [Int], idempotencyKey: UUID?) { self.ids = ids; self.idempotencyKey = idempotencyKey }
}

/// What one chunk ended with.
public enum AccountBatchChunkResult: Sendable, Equatable {
    case replied(AccountBulkReply)
    /// The whole request was refused before it ran.
    case refused(reason: String)
    /// It may have run; `runtime/batch`'s switches by id, nil when that read failed too (20 §8.5).
    case unconfirmed(readback: [Int: Bool]?)
    /// Not sent: an earlier chunk had no definite success, or the batch was cancelled.
    case skipped
}

/// A failed account's reason on the results sheet; the server's `error` text is never shown (20 §8.3).
public enum AccountBatchFailure: Sendable, Equatable, CaseIterable {
    case rejected, unconfirmed, missing, skipped
    public var text: String {
        switch self {
        case .rejected: "服务器拒绝"
        case .unconfirmed: "结果不明"
        case .missing: "未返回此账号的明确结果，请先刷新核对"
        case .skipped: "尚未执行，请重新选择"
        }
    }
}

public struct AccountBatchFailureRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let failure: AccountBatchFailure
    public init(id: Int, failure: AccountBatchFailure) { self.id = id; self.failure = failure }
}

/// The merged result of a batch, both lists in the order the ids were sent.
public struct AccountBatchOutcome: Sendable, Equatable {
    /// The switch the batch set.
    public let enabled: Bool
    public let succeeded: [Int]
    public let failures: [AccountBatchFailureRow]
    /// The first whole-request refusal's words.
    public let refusal: String?
    public init(enabled: Bool, succeeded: [Int], failures: [AccountBatchFailureRow], refusal: String?) {
        self.enabled = enabled; self.succeeded = succeeded; self.failures = failures; self.refusal = refusal
    }
    public var hasUnconfirmed: Bool { failures.contains { $0.failure == .unconfirmed } }
    /// Nothing was sent (the first request was cancelled): no receipt.
    public var isUnsent: Bool { succeeded.isEmpty && failures.allSatisfy { $0.failure == .skipped } }
}

/// How a failed `bulk-update` counts (00 §2.4, §2.5.4).
public enum AccountBatchDisposition: Sendable, Equatable {
    /// Refused before running, with the catalog's words (00 §3.4: never the server's message).
    case refused(String)
    /// It may have run: `runtime/batch` decides.
    case unconfirmed
    /// Cancelled, or the security sheet was closed: nothing is said.
    case cancelled
}

/// The receipt of a batch or its undo (20 §8.4–§8.5). Both buttons may apply; the receipt has one, so 查看 wins and the undo
/// moves to the results sheet (10 §0.7-6).
public struct AccountBatchReceipt: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case done, partial, failed, unconfirmed }
    public let kind: Kind
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let offersUndo: Bool
    /// The button “查看”, which opens the results sheet.
    public let offersDetails: Bool
    /// Nothing succeeded and nothing may have: the selection stays for another try.
    public let keepsSelection: Bool
    public init(kind: Kind, text: String, systemImage: String, tone: Tone, offersUndo: Bool, offersDetails: Bool, keepsSelection: Bool) {
        self.kind = kind; self.text = text; self.systemImage = systemImage; self.tone = tone
        self.offersUndo = offersUndo; self.offersDetails = offersDetails; self.keepsSelection = keepsSelection
    }
}

/// 20 §8: the account list's 停止调度 / 启用调度 on a selection, in requests of 50 sent one after another.
public enum AccountBatchPlan {
    public static let maxPerRequest = 50
    public static let resultsTitle = "批量操作结果"
    public static let detailsAction = "查看"
    public static let confirming = "正在确认结果…"
    private static let warning = "exclamationmark.triangle"

    /// Repeated and non-positive ids are dropped, the rest keep their first place. Keyed: one key per request, made here, at the
    /// tap (R05); `makeKey` is not called otherwise.
    public static func chunks(ids: [Int], keyed: Bool, makeKey: () -> UUID = UUID.init) -> [AccountBatchChunk] {
        var seen = Set<Int>()
        let unique = ids.filter { $0 > 0 && seen.insert($0).inserted }
        return stride(from: 0, to: unique.count, by: maxPerRequest).map { start in
            AccountBatchChunk(ids: Array(unique[start..<min(start + maxPerRequest, unique.count)]), idempotencyKey: keyed ? makeKey() : nil)
        }
    }

    /// A keyed write's unconfirmed end, a lost connection, an unreadable reply, 408 and the gateway statuses may have run; a
    /// cleared security prompt is a refusal whose words ask for the tap again.
    public static func disposition(of error: any Error) -> AccountBatchDisposition {
        if let api = error as? APIError, api.statusCode == 408, api.securityOutcome == nil { return .unconfirmed }
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return .cancelled
        case .readBack: return .unconfirmed
        case .reconfirm, .versionConflict, .missing, .failed: return .refused(error.localizedDescription)
        }
    }

    /// The next request goes out only after one that clearly ran: a reply, or a read-back that found every account at the target.
    public static func continues(after result: AccountBatchChunkResult, chunk: AccountBatchChunk, enabled: Bool) -> Bool {
        switch result {
        case .replied: true
        case .unconfirmed(let readback?): chunk.ids.allSatisfy { readback[$0] == enabled }
        case .unconfirmed(.none), .refused, .skipped: false
        }
    }

    /// `results` pairs with `chunks`; a chunk without one counts as not sent. A read-back equal to the target is a success, a
    /// different value is unknown and an account it left out has no clear result.
    public static func merge(chunks: [AccountBatchChunk], results: [AccountBatchChunkResult], enabled: Bool) -> AccountBatchOutcome {
        var succeeded: [Int] = [], failures: [AccountBatchFailureRow] = [], refusal: String?
        for (index, chunk) in chunks.enumerated() {
            let result = index < results.count ? results[index] : .skipped
            if case .refused(let reason) = result, refusal == nil { refusal = reason }
            for id in chunk.ids {
                if let failure = failure(of: id, in: result, enabled: enabled) {
                    failures.append(AccountBatchFailureRow(id: id, failure: failure))
                } else {
                    succeeded.append(id)
                }
            }
        }
        return AccountBatchOutcome(enabled: enabled, succeeded: succeeded, failures: failures, refusal: refusal)
    }
    private static func failure(of id: Int, in result: AccountBatchChunkResult, enabled: Bool) -> AccountBatchFailure? {
        switch result {
        case .replied(let reply):
            switch reply.outcome(for: id) {
            case true?: return nil
            case false?: return .rejected
            case nil: return .missing
            }
        case .refused: return .rejected
        case .skipped: return .skipped
        case .unconfirmed(.none): return .unconfirmed
        case .unconfirmed(let readback?):
            guard let value = readback[id] else { return .missing }
            return value == enabled ? nil : .unconfirmed
        }
    }

    /// 20 §8.4: the undo sets back only the accounts the batch changed, those whose switch was the other way before; one the
    /// snapshot does not know is left alone. Empty: no undo.
    public static func undoIDs(for outcome: AccountBatchOutcome, prior: [Int: Bool]) -> [Int] {
        outcome.succeeded.filter { prior[$0] == !outcome.enabled }
    }

    public static func receipt(for outcome: AccountBatchOutcome, isUndo: Bool, canUndo: Bool) -> AccountBatchReceipt {
        let done = outcome.succeeded.count, failed = outcome.failures.count
        let verb = AccountActionKind.setSchedulable(outcome.enabled).verb
        if done > 0 {
            let text = "已\(verb) \(DisplayFormat.grouped(done)) 个账号"
            guard failed == 0 else {
                return AccountBatchReceipt(kind: .partial, text: text + " · \(DisplayFormat.grouped(failed)) 个失败", systemImage: warning, tone: .caution,
                                           offersUndo: false, offersDetails: true, keepsSelection: false)
            }
            return AccountBatchReceipt(kind: .done, text: text, systemImage: outcome.enabled ? "play.fill" : "pause.fill",
                                       tone: outcome.enabled ? .ok : .neutral, offersUndo: canUndo && !isUndo, offersDetails: false, keepsSelection: false)
        }
        if outcome.hasUnconfirmed {
            return AccountBatchReceipt(kind: .unconfirmed, text: AccountActionCopy.unconfirmed, systemImage: warning, tone: .caution, offersUndo: false,
                                       offersDetails: true, keepsSelection: false)
        }
        let reason = outcome.refusal ?? "\(DisplayFormat.grouped(failed)) 个账号失败"
        return AccountBatchReceipt(kind: .failed, text: "\(isUndo ? "撤销" : "批量操作")没有成功：\(reason)", systemImage: warning, tone: .critical,
                                   offersUndo: false, offersDetails: outcome.refusal == nil, keepsSelection: true)
    }

    /// “名称（#id）”, or “#id” without a name.
    public static func rowTitle(name: String?, id: Int) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "#\(id)" : "\(trimmed)（#\(id)）"
    }

    // MARK: Selection chrome (20 §1.1, §1.3, §8.3)

    public static func selectedCount(_ count: Int) -> String { "已选 \(DisplayFormat.grouped(count)) 个" }
    /// A collapsed section's note in selection mode.
    public static func pickedInSection(_ count: Int) -> String { "已选 \(DisplayFormat.grouped(count))" }
    public static func sectionToggleTitle(allSelected: Bool) -> String { allSelected ? "取消全选" : "全选" }
    /// The results sheet's undo after a partial failure; `original` is the switch the batch set.
    public static func undoTitle(original: Bool, count: Int) -> String {
        "撤销已\(AccountActionKind.setSchedulable(original).verb)的 \(DisplayFormat.grouped(count)) 个"
    }
}
