import Foundation

/// What the detail's buttons and ··· menu do (60 §16.3, §16.4).
public enum AnnouncementDetailAction: String, Equatable, Sendable {
    case publish, republish, archive, edit

    public var title: String {
        switch self {
        case .publish: "发布"
        case .republish: "重新发布"
        case .archive: "归档"
        case .edit: "编辑"
        }
    }
    public var systemImage: String {
        switch self {
        case .publish, .republish: "megaphone"
        case .archive: "tray"
        case .edit: "square.and.pencil"
        }
    }
    /// The status the PUT writes; editing goes through the sheet.
    public var targetStatus: AnnouncementStatus? {
        switch self {
        case .publish, .republish: .active
        case .archive: .archived
        case .edit: nil
        }
    }
}

public struct AnnouncementDetailButton: Equatable, Sendable {
    public let action: AnnouncementDetailAction
    public let isPrimary: Bool
    public init(action: AnnouncementDetailAction, isPrimary: Bool) { self.action = action; self.isPrimary = isPrimary }
}

/// One entry of the ··· menu, in the order 60 §16.4 lists them.
public enum AnnouncementMenuItem: Equatable, Sendable {
    case edit, write(AnnouncementDetailAction), reads, delete

    public var title: String {
        switch self {
        case .edit: "编辑公告"
        case .write(let action): action.title
        case .reads: AnnouncementPresentation.readsTitle
        case .delete: "删除公告…"
        }
    }
    public var isDestructive: Bool { self == .delete }
    /// Greyed for a read-only token (00 §1.6); 已读情况 only reads.
    public var isWrite: Bool { self != .reads }
}

/// The detail's own wording (S6D1-01 ④); its title, subtitle, times, read row and publish confirmation come from
/// AnnouncementPresentation.
public enum AnnouncementDetailPresentation {
    public static let emptyBody = "还没有正文", previewDismiss = "知道了", gone = "已删除"
    public static let publishedReceipt = "已发布 · 符合条件的用户能看到", archivedReceipt = "已归档 · 用户不再看到"
    /// 00 §2.4: an unkeyed write whose result could not be read back.
    public static let unconfirmed = "结果未确认，请刷新核对后再操作"
    /// 00 §4.6: a refresh failed while the older detail stays.
    public static let refreshFailed = "刷新失败 · 重试"

    /// 草稿“发布”（主）+“编辑”；展示中“归档”+“编辑”（主）；已归档“重新发布”+“编辑”（主）; a status this version does not
    /// know only edits.
    public static func buttons(for status: AnnouncementStatus?) -> [AnnouncementDetailButton] {
        let edit = AnnouncementDetailButton(action: .edit, isPrimary: status != .draft)
        guard let write = writeAction(for: status) else { return [edit] }
        return [AnnouncementDetailButton(action: write, isPrimary: status == .draft), edit]
    }
    public static func writeAction(for status: AnnouncementStatus?) -> AnnouncementDetailAction? {
        switch status {
        case .draft?: .publish
        case .active?: .archive
        case .archived?: .republish
        case nil: nil
        }
    }
    /// 编辑公告; 归档 / 发布 / 重新发布; 已读情况 (not for a draft); 删除公告… last.
    public static func menuItems(for status: AnnouncementStatus?) -> [AnnouncementMenuItem] {
        [.edit] + [writeAction(for: status).map(AnnouncementMenuItem.write), status == .draft ? nil : .reads].compactMap { $0 } + [.delete]
    }
    public static func previewLabel(_ mode: AnnouncementNotifyMode) -> String { "用户看到的样子 · " + AnnouncementPresentation.notifyTitle(mode) }
    /// A body of white space only reads “还没有正文”.
    public static func hasBody(_ content: String) -> Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// `reason` is catalog text (R11), never the server's message.
    public static func writeFailed(_ action: AnnouncementDetailAction, reason: String) -> String { action.title + "没有成功：" + reason }
    public static func undoFailed(reason: String) -> String { "撤销没有成功：" + reason }
    public static func deleteFailed(reason: String) -> String { "删除没有成功：" + reason }

    /// 00 §6.3: start and end follow the phone's zone; said under 壹 投放 only when it is not the site's offset.
    public static func scheduleZoneNote(device: TimeZone, server: ServerTimeZone, at date: Date) -> String? {
        guard server.differsFromDevice(device, at: date), let phone = ServerTimeZone(identifier: device.identifier, utcOffset: nil) else { return nil }
        return "开始 / 结束时间按本机时区（\(phone.offsetLabel(at: date))）"
    }
}

/// How a publish, archive, undo or delete failed (00 §2.4, §2.6.2; R06): never resent on its own.
public enum AnnouncementWriteFailure: Equatable, Sendable {
    /// 404 ANNOUNCEMENT_NOT_FOUND.
    case gone
    /// Lost connection, an unreadable reply, 502 / 504 or a 503 without its own reason: read back.
    case unconfirmed
    /// Compliance or step-up cleared it; the notice, then the confirmation again.
    case reconfirm(String)
    case cancelled
    /// Catalog text.
    case rejected(String)

    public static let notFoundReason = "ANNOUNCEMENT_NOT_FOUND"

    public static func isGone(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == notFoundReason
    }
    public static func classify(_ error: any Error) -> AnnouncementWriteFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .rejected(error.localizedDescription) }
        switch api.securityOutcome {
        case .passed?: return .reconfirm(api.localizedDescription)
        case .cancelled?: return .cancelled
        case .blocked?, nil: break
        }
        if isGone(api) { return .gone }
        // A refresh that failed before sending was never sent.
        guard api != .refreshDeferred else { return .rejected(api.localizedDescription) }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse ? .unconfirmed : .rejected(api.localizedDescription) }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed : .rejected(api.localizedDescription)
    }
}
