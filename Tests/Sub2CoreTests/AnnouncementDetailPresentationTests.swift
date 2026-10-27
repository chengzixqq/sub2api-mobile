import Foundation
import Testing
@testable import Sub2Core

// MARK: 60 §16.3 按钮行与预览卡

@Test func announcementDetailButtonsFollowStatus() {
    func row(_ status: AnnouncementStatus?) -> [AnnouncementDetailButton] { AnnouncementDetailPresentation.buttons(for: status) }
    #expect(row(.draft) == [AnnouncementDetailButton(action: .publish, isPrimary: true), AnnouncementDetailButton(action: .edit, isPrimary: false)])
    #expect(row(.active) == [AnnouncementDetailButton(action: .archive, isPrimary: false), AnnouncementDetailButton(action: .edit, isPrimary: true)])
    #expect(row(.archived) == [AnnouncementDetailButton(action: .republish, isPrimary: false), AnnouncementDetailButton(action: .edit, isPrimary: true)])
    #expect(row(nil) == [AnnouncementDetailButton(action: .edit, isPrimary: true)])
    #expect(AnnouncementDetailPresentation.writeAction(for: .draft) == .publish)
    #expect(AnnouncementDetailPresentation.writeAction(for: .active) == .archive)
    #expect(AnnouncementDetailPresentation.writeAction(for: .archived) == .republish)
    #expect(AnnouncementDetailPresentation.writeAction(for: nil) == nil)
    #expect(AnnouncementDetailAction.publish.targetStatus == .active && AnnouncementDetailAction.republish.targetStatus == .active)
    #expect(AnnouncementDetailAction.archive.targetStatus == .archived && AnnouncementDetailAction.edit.targetStatus == nil)
    #expect([AnnouncementDetailAction.publish, .republish, .archive, .edit].map(\.title) == ["发布", "重新发布", "归档", "编辑"])
}

@Test func announcementDetailPreviewTextsAndEmptyValues() {
    #expect(AnnouncementDetailPresentation.previewLabel(.popup) == "用户看到的样子 · 弹窗")
    #expect(AnnouncementDetailPresentation.previewLabel(.silent) == "用户看到的样子 · 静默")
    #expect(AnnouncementDetailPresentation.emptyBody == "还没有正文")
    #expect(AnnouncementDetailPresentation.previewDismiss == "知道了")
    #expect(AnnouncementDetailPresentation.gone == "已删除")
    #expect(AnnouncementDetailPresentation.hasBody(" \n维护") && !AnnouncementDetailPresentation.hasBody(" \n\t"))
}

// MARK: 60 §16.4 ··· 菜单

@Test func announcementDetailMenuItemsOrderAndKinds() {
    func menu(_ status: AnnouncementStatus?) -> [AnnouncementMenuItem] { AnnouncementDetailPresentation.menuItems(for: status) }
    #expect(menu(.active) == [.edit, .write(.archive), .reads, .delete])
    #expect(menu(.draft) == [.edit, .write(.publish), .delete])
    #expect(menu(.archived) == [.edit, .write(.republish), .reads, .delete])
    #expect(menu(nil) == [.edit, .reads, .delete])
    #expect(menu(.active).map(\.title) == ["编辑公告", "归档", "已读情况", "删除公告…"])
    #expect(menu(.draft).map(\.title) == ["编辑公告", "发布", "删除公告…"])
    #expect(menu(.archived)[1].title == "重新发布")
    #expect(menu(.active).filter(\.isDestructive) == [.delete])
    #expect(menu(.active).map(\.isWrite) == [true, true, false, true])
}

@Test func announcementDetailReceiptsAndFailureCopy() {
    #expect(AnnouncementDetailPresentation.publishedReceipt == "已发布 · 符合条件的用户能看到")
    #expect(AnnouncementDetailPresentation.archivedReceipt == "已归档 · 用户不再看到")
    #expect(AnnouncementDetailPresentation.writeFailed(.publish, reason: "X") == "发布没有成功：X")
    #expect(AnnouncementDetailPresentation.writeFailed(.republish, reason: "X") == "重新发布没有成功：X")
    #expect(AnnouncementDetailPresentation.writeFailed(.archive, reason: "X") == "归档没有成功：X")
    #expect(AnnouncementDetailPresentation.undoFailed(reason: "X") == "撤销没有成功：X")
    #expect(AnnouncementDetailPresentation.deleteFailed(reason: "X") == "删除没有成功：X")
    #expect(AnnouncementDetailPresentation.unconfirmed == "结果未确认，请刷新核对后再操作")
    #expect(AnnouncementDetailPresentation.refreshFailed == "刷新失败 · 重试")
}

// MARK: 写失败分类（00 §2.4、§2.6.2，R06、R11）

@Test func announcementWriteFailuresAreClassified() {
    #expect(AnnouncementWriteFailure.classify(APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND")) == .gone)
    #expect(AnnouncementWriteFailure.isGone(APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND")))
    #expect(!AnnouncementWriteFailure.isGone(APIError.server(status: 404, envelope: nil)))
    #expect(AnnouncementWriteFailure.classify(APIError.transport(URLError(.timedOut))) == .unconfirmed)
    #expect(AnnouncementWriteFailure.classify(APIError.transport(URLError(.networkConnectionLost))) == .unconfirmed)
    #expect(AnnouncementWriteFailure.classify(APIError.invalidResponse) == .unconfirmed)
    for status in [502, 504] { #expect(AnnouncementWriteFailure.classify(APIError.server(status: status, reason: nil)) == .unconfirmed) }
    #expect(AnnouncementWriteFailure.classify(APIError.server(status: 503, reason: nil)) == .unconfirmed)
    let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
    #expect(AnnouncementWriteFailure.classify(readOnly) == .rejected("当前管理访问令牌只读，不能执行此操作"))
    let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(AnnouncementWriteFailure.classify(stepUp) == .reconfirm("二次验证已通过，请重新确认后发送"))
    #expect(AnnouncementWriteFailure.classify(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == .cancelled)
    #expect(AnnouncementWriteFailure.classify(CancellationError()) == .cancelled)
    let badRequest = APIError.server(status: 400, envelope: ErrorEnvelope(reason: nil))
    #expect(AnnouncementWriteFailure.classify(badRequest) == .rejected(badRequest.localizedDescription))
    #expect(AnnouncementWriteFailure.classify(APIError.refreshDeferred) == .rejected(APIError.refreshDeferred.localizedDescription))
}

// MARK: 00 §6.3 有效期按本机时区

@Test func announcementScheduleZoneNoteOnlyWhenOffsetsDiffer() throws {
    let date = try #require(ServerTime.parseTimestamp("2026-10-17T09:41:00+08:00"))
    let shanghai = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    func note(_ device: String) throws -> String? {
        AnnouncementDetailPresentation.scheduleZoneNote(device: try #require(TimeZone(identifier: device)), server: shanghai, at: date)
    }
    #expect(try note("Asia/Shanghai") == nil)
    #expect(try note("Asia/Singapore") == nil)
    #expect(try note("Asia/Tokyo") == "开始 / 结束时间按本机时区（UTC+9）")
    #expect(try note("Asia/Kolkata") == "开始 / 结束时间按本机时区（UTC+5:30）")
}
