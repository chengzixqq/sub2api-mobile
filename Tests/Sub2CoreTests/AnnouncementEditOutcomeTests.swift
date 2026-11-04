import Foundation
import Testing
@testable import Sub2Core

private let confirmedAt = Date(timeIntervalSince1970: 1_792_201_280)
private let firstKey = UUID(uuidString: "1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D")!
private let secondKey = UUID(uuidString: "2B3C4D5E-6F7A-4B2C-9D3E-4F5A6B7C8D9E")!
private let request = AnnouncementCreateRequest(title: "维护通知", content: "正文", status: .draft)

private func item(_ id: Int, title: String = "维护通知", content: String = "正文", createdAfter seconds: TimeInterval,
                  status: AnnouncementStatus = .draft) -> Announcement {
    Announcement(id: id, title: title, content: content, status: status, createdAt: confirmedAt.addingTimeInterval(seconds))
}

@Test func createAttemptKeepsKeyForSameBytes() throws {
    var keys = [firstKey, secondKey]
    let make = { keys.removeFirst() }
    let first = try AnnouncementCreateAttempt.next(for: request, previous: nil, now: confirmedAt, makeKey: make)
    #expect(first.key == firstKey && first.confirmedAt == confirmedAt && first.request == request)
    let again = try AnnouncementCreateAttempt.next(for: request, previous: first, now: confirmedAt.addingTimeInterval(30), makeKey: make)
    #expect(again == first)
    let changed = AnnouncementCreateRequest(title: "维护通知", content: "新正文", status: .draft)
    let other = try AnnouncementCreateAttempt.next(for: changed, previous: first, now: confirmedAt.addingTimeInterval(40), makeKey: make)
    #expect(other.key == secondKey && other.confirmedAt == confirmedAt.addingTimeInterval(40))
    #expect(throws: APIError.self) {
        try AnnouncementCreateAttempt.next(for: AnnouncementCreateRequest(title: " ", content: "正文"), previous: nil, now: confirmedAt)
    }
}

/// 00 §2.5.5: an unknown result brings no X-Idempotency-Expires-At, so the key replays for 24 hours from the confirmation;
/// a create has no business-level dedupe, so after that only the check is left.
@Test func createAttemptReplaysForADay() throws {
    let attempt = try AnnouncementCreateAttempt.next(for: request, previous: nil, now: confirmedAt, makeKey: { firstKey })
    #expect(attempt.replayExpiresAt == confirmedAt.addingTimeInterval(86_400))
    #expect(attempt.isReplayable(at: confirmedAt) && attempt.isReplayable(at: confirmedAt.addingTimeInterval(86_399)))
    #expect(!attempt.isReplayable(at: confirmedAt.addingTimeInterval(86_400)) && !attempt.isReplayable(at: confirmedAt.addingTimeInterval(90_000)))
}

@Test func editFailureClassification() {
    let cases: [(String, String)] = [("ANNOUNCEMENT_TITLE_INVALID", "标题不能为空，最多 200 字节"), ("ANNOUNCEMENT_CONTENT_REQUIRED", "请填写正文"),
                                     ("ANNOUNCEMENT_INVALID_TARGET", "可见对象条件无效，请重新设置"),
                                     ("ANNOUNCEMENT_TIME_RANGE_INVALID", "结束时间要晚于开始时间")]
    for (reason, message) in cases {
        let error = APIError.server(status: 400, reason: reason)
        #expect(AnnouncementEditFailure.classify(error) == .rejected(message), "\(reason)")
        #expect(AnnouncementEditFailure.reasonMessage(error) == message && error.localizedDescription != message)
    }
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    #expect(AnnouncementEditFailure.classify(conflict) == .keyConflict)
    #expect(AnnouncementEditFailure.keyConflict.message == "该编号已用于另一份公告内容，请重新打开新建页")
    let later = confirmedAt.addingTimeInterval(10)
    let unknown = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: later), key: "k", actionID: nil, lastError: nil)
    #expect(AnnouncementEditFailure.classify(unknown) == .unconfirmed(retryNotBefore: later))
    #expect(AnnouncementEditFailure.classify(APIError(kind: .transport, message: "超时")) == .unconfirmed(retryNotBefore: nil))
    #expect(AnnouncementEditFailure.classify(APIError.server(status: 502, reason: nil)) == .unconfirmed(retryNotBefore: nil))
    #expect(AnnouncementEditFailure.classify(APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND")) == .gone)
    let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
    #expect(AnnouncementEditFailure.classify(readOnly) == .rejected(readOnly.localizedDescription))
    let locked = APIError.server(status: 423, reason: nil)
    #expect(AnnouncementEditFailure.classify(locked) == .rejected(locked.localizedDescription))
    #expect(AnnouncementEditFailure.classify(CancellationError()) == .cancelled)
    let other = APIError.server(status: 400, reason: "SOMETHING_NEW")
    #expect(AnnouncementEditFailure.classify(other) == .rejected(other.localizedDescription))
    #expect(AnnouncementEditFailure.unconfirmed(retryNotBefore: nil).message == "结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行")
}

@Test func recentCheckAndReadBack() {
    let match = AnnouncementRecentCheck.match(in: [item(40, createdAfter: 10)], title: " 维护通知 ", confirmedAt: confirmedAt)
    #expect(match == AnnouncementRecentMatch(id: 40, title: "维护通知", createdAt: confirmedAt.addingTimeInterval(10), status: .draft))
    #expect(AnnouncementRecentCheck.match(in: [item(41, title: "维护通知（二）", createdAfter: 10)], title: "维护通知", confirmedAt: confirmedAt) == nil)
    #expect(AnnouncementRecentCheck.match(in: [item(42, createdAfter: -120)], title: "维护通知", confirmedAt: confirmedAt) == nil)
    #expect(AnnouncementRecentCheck.match(in: [item(43, createdAfter: 301)], title: "维护通知", confirmedAt: confirmedAt) == nil)
    #expect(AnnouncementRecentCheck.match(in: [item(44, createdAfter: -30)], title: "维护通知", confirmedAt: confirmedAt)?.id == 44)
    #expect(AnnouncementRecentCheck.match(in: [item(45, createdAfter: 5), item(46, createdAfter: 20), item(47, createdAfter: 12)],
                                          title: "维护通知", confirmedAt: confirmedAt)?.id == 46)

    let start = Date(timeIntervalSince1970: 1_792_202_400)
    let saved = Announcement(id: 7, title: "新标题", content: "新正文", status: .active, notifyMode: .popup,
                             targeting: .single(.subscription(groupIDs: [4, 5])), startsAt: start.addingTimeInterval(0.4), endsAt: nil)
    #expect(AnnouncementUpdateRequest(title: " 新标题 ", content: "新正文\n").isReflected(in: saved))
    #expect(!AnnouncementUpdateRequest(title: "旧标题").isReflected(in: saved))
    #expect(AnnouncementUpdateRequest(status: .active, notifyMode: .popup).isReflected(in: saved))
    #expect(AnnouncementUpdateRequest(targeting: .single(.subscription(groupIDs: [5, 4]))).isReflected(in: saved))
    #expect(!AnnouncementUpdateRequest(targeting: .everyone).isReflected(in: saved))
    #expect(AnnouncementUpdateRequest(startsAt: .at(start), endsAt: .clear).isReflected(in: saved))
    #expect(!AnnouncementUpdateRequest(startsAt: .clear).isReflected(in: saved))
}

@Test func markdownInsertAndCount() {
    let empty = MarkdownEdit.insert(.bold, into: "", selection: 0..<0)
    #expect(empty == MarkdownEdit(text: "**粗体**", selection: 2..<4))
    let wrapped = MarkdownEdit.insert(.bold, into: "请及时充值", selection: 2..<4)
    #expect(wrapped == MarkdownEdit(text: "请及**时充**值", selection: 4..<6))
    #expect(MarkdownEdit.insert(.list, into: "开头", selection: 2..<2) == MarkdownEdit(text: "开头\n- 列表项", selection: 5..<8))
    #expect(MarkdownEdit.insert(.heading, into: "开头", selection: 2..<2) == MarkdownEdit(text: "开头\n## 小标题", selection: 6..<9))
    #expect(MarkdownEdit.insert(.link, into: "", selection: 0..<0) == MarkdownEdit(text: "[链接文字](https://)", selection: 1..<5))
    let emoji = MarkdownEdit.insert(.bold, into: "👍🏽好", selection: 1..<2)
    #expect(emoji == MarkdownEdit(text: "👍🏽**好**", selection: 3..<4))
    #expect(MarkdownEdit.insert(.bold, into: "abc", selection: 7..<9) == MarkdownEdit(text: "abc**粗体**", selection: 5..<7))
    #expect(MarkdownEdit.countText("👍🏽好") == "2 字" && MarkdownEdit.countText(String(repeating: "字", count: 1_234)) == "1,234 字")
    #expect(MarkdownSnippet.allCases.map(\.title) == ["粗体", "列表", "小标题", "链接"])
}

// MARK: - 新建结果未确认的会话记录（U-21，S6-高-13）

/// 稍后核对 now keeps the number for the session, so the closing words say so.
@Test func closeMessageMentionsRetained() {
    #expect(AnnouncementEditCopy.unconfirmedCloseMessage(creating: true)
            == "服务器可能已经创建了这条公告。关闭后这次的编号在本次使用期间保留，公告列表会重新读取；再次新建时会先提醒你核对，避免重复。")
    #expect(AnnouncementEditCopy.unconfirmedCloseMessage(creating: false) == "服务器可能已经保存了这次修改。关闭后公告列表会重新读取，再次修改前先在详情里核对。")
}

/// The words of the prompt before another 新建: the confirmation on the site's calendar, with the year once it is another.
@Test func interceptCopy() throws {
    let zone = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    let format = ISO8601DateFormatter()
    let confirmed = try #require(format.date(from: "2026-10-13T06:20:00Z"))
    let now = try #require(format.date(from: "2026-10-14T01:00:00Z"))
    #expect(AnnouncementEditCopy.interceptTitle == "上一条公告的新建结果未确认")
    #expect(AnnouncementEditCopy.interceptMessage(title: "维护通知", confirmedAt: confirmed, timeZone: zone, now: now)
            == "「维护通知」· 10/13 14:20 确认\n服务器可能已经创建了它，先核对，避免用户看到重复的公告。")
    let lastYear = try #require(format.date(from: "2025-12-30T15:10:00Z"))
    let message = AnnouncementEditCopy.interceptMessage(title: "维护通知", confirmedAt: lastYear, timeZone: zone, now: now)
    #expect(message == "「维护通知」· 2025/12/30 23:10 确认\n服务器可能已经创建了它，先核对，避免用户看到重复的公告。")
    #expect(message.contains(DisplayFormat.monthDayClock(lastYear, timeZone: zone, now: now)))
    #expect(AnnouncementEditCopy.keepChecking == "继续核对" && AnnouncementEditCopy.createAnyway == "仍要新建")
}
