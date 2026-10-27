import Foundation

/// One 存草稿 / 发布 of a new announcement (R05, 00 §2.5.2): the key is made when the administrator confirms and kept while
/// the same bytes go out again; other bytes get a new key and a new confirmation time.
public struct AnnouncementCreateAttempt: Sendable, Equatable {
    public let key: UUID
    public let request: AnnouncementCreateRequest
    public let body: Data
    /// When the administrator confirmed; the H07 check looks around it.
    public let confirmedAt: Date

    /// Throws the request's own validation error (with the server's reason) before anything is sent.
    public static func next(for request: AnnouncementCreateRequest, previous: AnnouncementCreateAttempt?, now: Date,
                            makeKey: () -> UUID = { UUID() }) throws -> AnnouncementCreateAttempt {
        let body = try request.requestBody()
        if let previous, previous.body == body { return previous }
        return AnnouncementCreateAttempt(key: makeKey(), request: request, body: body, confirmedAt: now)
    }
}

/// How a save of the edit sheet failed (60 §17.4). Catalog or sheet wording only, never the server's message (00 §3.4).
public enum AnnouncementEditFailure: Sendable, Equatable {
    /// The server or the form refused it; the next try gets a new key (a refused keyed write backs off for 5 seconds).
    case rejected(String)
    case keyConflict
    /// The server may have run it.
    case unconfirmed(retryNotBefore: Date?)
    /// 404 ANNOUNCEMENT_NOT_FOUND.
    case gone
    case cancelled

    private static let reasonMessages = [
        "ANNOUNCEMENT_TITLE_INVALID": "标题不能为空，最多 200 字节",
        "ANNOUNCEMENT_CONTENT_REQUIRED": "请填写正文",
        "ANNOUNCEMENT_INVALID_TARGET": "可见对象条件无效，请重新设置",
        "ANNOUNCEMENT_TIME_RANGE_INVALID": "结束时间要晚于开始时间"
    ]

    /// The four reasons of 60 §17.4, which ReasonCatalog leaves to the 400 fallback.
    public static func reasonMessage(_ error: APIError) -> String? { error.reason.flatMap { reasonMessages[$0] } }

    public static func classify(_ error: any Error) -> AnnouncementEditFailure {
        if error is CancellationError { return .cancelled }
        if let keyed = error as? KeyedWriteFailure {
            switch keyed.disposition {
            case .unconfirmed(_, let retryNotBefore): return .unconfirmed(retryNotBefore: retryNotBefore)
            case .needsNewKey(.keyConflict): return .keyConflict
            case .needsNewKey: return .rejected(keyed.localizedDescription)
            }
        }
        guard let api = error as? APIError else { return .rejected(error.localizedDescription) }
        if api.securityOutcome == .cancelled { return .cancelled }
        if AnnouncementWriteFailure.isGone(api) { return .gone }
        if let message = reasonMessage(api) { return .rejected(message) }
        // A refresh that failed before sending was never sent.
        guard api != .refreshDeferred else { return .rejected(api.localizedDescription) }
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? .unconfirmed(retryNotBefore: nil) : .rejected(api.localizedDescription)
        }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed(retryNotBefore: nil) : .rejected(api.localizedDescription)
    }

    public var message: String {
        switch self {
        case .rejected(let message): message
        case .keyConflict: AnnouncementEditCopy.keyConflict
        case .unconfirmed: KeyedWriteFailure.unconfirmedMessage
        case .gone: AnnouncementEditCopy.gone
        case .cancelled: ""
        }
    }
}

/// An announcement the H07 check found: same title, created around the confirmation.
public struct AnnouncementRecentMatch: Sendable, Equatable {
    public let id: Int
    public let title: String
    public let createdAt: Date
    public let status: AnnouncementStatus?
    public init(id: Int, title: String, createdAt: Date, status: AnnouncementStatus?) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.status = status
    }
}

/// 60 §17.4 H07: without `announcements.idempotent_create` an unknown create is never resent; the newest few whose title or
/// content contains the title are read and one with exactly that title, made in the “最近几分钟”, is offered.
public enum AnnouncementRecentCheck {
    /// Five minutes after the confirmation, and one before it for a server clock behind the phone's.
    public static let window: TimeInterval = 300
    public static let clockSlack: TimeInterval = 60

    public static func match(in items: [Announcement], title: String, confirmedAt: Date) -> AnnouncementRecentMatch? {
        let wanted = AnnouncementDraft.trimmed(title)
        let earliest = confirmedAt.addingTimeInterval(-clockSlack), latest = confirmedAt.addingTimeInterval(window)
        return items.compactMap { item -> AnnouncementRecentMatch? in
            guard let createdAt = item.createdAt, createdAt >= earliest, createdAt <= latest,
                  AnnouncementDraft.trimmed(item.title) == wanted else { return nil }
            return AnnouncementRecentMatch(id: item.id, title: item.title, createdAt: createdAt, status: item.status)
        }.max { $0.createdAt < $1.createdAt }
    }
}

extension AnnouncementUpdateRequest {
    /// A PUT whose reply was lost is read back (00 §2.4): every key sent must read as sent — titles and bodies trimmed like
    /// the server, times in whole seconds, 0 as missing, a targeting by its audience.
    public func isReflected(in announcement: Announcement) -> Bool {
        if let title, AnnouncementDraft.trimmed(title) != AnnouncementDraft.trimmed(announcement.title) { return false }
        if let content, AnnouncementDraft.trimmed(content) != AnnouncementDraft.trimmed(announcement.content) { return false }
        if let status, status != announcement.status { return false }
        if let notifyMode, notifyMode != announcement.notifyMode { return false }
        if let targeting, !targeting.isEquivalent(to: announcement.targeting) { return false }
        return Self.matches(startsAt, announcement.startsAt) && Self.matches(endsAt, announcement.endsAt)
    }

    private static func matches(_ schedule: Schedule?, _ value: Date?) -> Bool {
        switch schedule {
        case nil: true
        case .clear?: value == nil
        case .at(let date)?: value.map(AnnouncementDraft.seconds) == AnnouncementDraft.seconds(date)
        }
    }
}

/// 60 §17.3 format bar.
public enum MarkdownSnippet: String, CaseIterable, Sendable {
    case bold, list, heading, link

    public var title: String {
        switch self {
        case .bold: "粗体"
        case .list: "列表"
        case .heading: "小标题"
        case .link: "链接"
        }
    }
    public var systemImage: String {
        switch self {
        case .bold: "bold"
        case .list: "list.bullet"
        case .heading: "textformat.size"
        case .link: "link"
        }
    }
    fileprivate var parts: (before: String, example: String, after: String) {
        switch self {
        case .bold: ("**", "粗体", "**")
        case .list: ("\n- ", "列表项", "")
        case .heading: ("\n## ", "小标题", "")
        case .link: ("[", "链接文字", "](https://)")
        }
    }
}

/// A format-bar insertion: offsets are Characters, so a CJK character or an emoji with its modifier is one.
public struct MarkdownEdit: Sendable, Equatable {
    public let text: String
    /// What to select afterwards: the wrapped text, or the example text that was inserted.
    public let selection: Range<Int>
    public init(text: String, selection: Range<Int>) { self.text = text; self.selection = selection }

    /// Wraps the selection, or inserts the example at the cursor; a range past the end is the end.
    public static func insert(_ snippet: MarkdownSnippet, into text: String, selection: Range<Int>) -> MarkdownEdit {
        let characters = Array(text)
        let lower = min(max(selection.lowerBound, 0), characters.count)
        let upper = min(max(selection.upperBound, lower), characters.count)
        let parts = snippet.parts
        let chosen = String(characters[lower..<upper])
        let body = chosen.isEmpty ? parts.example : chosen
        let result = String(characters[..<lower]) + parts.before + body + parts.after + String(characters[upper...])
        let start = lower + parts.before.count
        return MarkdownEdit(text: result, selection: start..<(start + body.count))
    }
    /// “N 字” beside the format bar.
    public static func countText(_ text: String) -> String { DisplayFormat.grouped(text.count) + " 字" }
}

/// The edit sheet's wording (60 §17).
public enum AnnouncementEditCopy {
    public static let titlePlaceholder = "标题", contentPlaceholder = "写点什么…"
    public static let markdownFootnote = "支持 Markdown：**粗体**、- 列表、## 小标题、[链接](地址)。"
    public static let everyoneFootnote = "所有用户都能看到。"
    public static let conditionFootnote = "手机上设一个条件；多个条件组合请在 Web 编辑。"
    public static let lockedFootnote = "这条公告的条件有多组 / 多条，手机上只读；要修改请在 Web 编辑。"
    public static let silentFootnote = "静默：只出现在用户的通知列表里。", popupFootnote = "弹窗模式会自动弹出通知给用户。"
    public static let scheduleFootnote = "立即 = 开始时间留空；永久 = 结束时间留空。时间按本机时区。"
    public static let timeRangeFootnote = "结束时间要晚于开始时间。"
    public static let subscriptionPrompt = "持有以下任一套餐", noSubscriptionGroups = "没有可选的订阅套餐"
    public static let specifiedTime = "指定时间"
    public static let discardTitle = "放弃修改？", discardConfirm = "放弃修改", keepEditing = "继续编辑"
    public static let keyConflict = "该编号已用于另一份公告内容，请重新打开新建页"
    public static let gone = "这条公告已被删除"
    public static let saving = "正在保存…", confirming = "正在确认结果…", checking = "正在核对…"
    public static let maybeCreatedTitle = "上一次可能已经创建成功"
    public static let notFoundTitle = "结果仍未确认", notFoundDetail = "还没找到刚才那条公告，服务器可能仍在处理。"
    public static let viewExisting = "查看", createAnyway = "仍要新建", recheck = "再次核对", retrySame = "用同一编号重试"
    public static let loading = "正在读取公告…"

    /// While a save runs: transport retries, then the server still working on the same key.
    public static func savingText(_ event: KeyedWriteEvent?) -> String {
        switch event {
        case .confirming?: confirming
        case .waitingForServer(let seconds)?: "服务器仍在处理 · 已等待 \(seconds) 秒"
        case .actionID?, nil: saving
        }
    }
    /// “「维护通知」· 草稿 · 创建于 10/17 09:41”.
    public static func maybeCreatedDetail(_ match: AnnouncementRecentMatch, now: Date, timeZone: TimeZone) -> String {
        let parts = ["「\(AnnouncementPresentation.displayTitle(match.title))」", match.status.map(AnnouncementPresentation.statusTitle),
                     "创建于 " + AnnouncementPresentation.timestamp(match.createdAt, now: now, timeZone: timeZone)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
