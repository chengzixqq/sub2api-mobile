import Foundation
import Testing
@testable import Sub2Core

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
/// 2026-10-17 09:41:20 in Shanghai (01:41:20Z).
private let now = Date(timeIntervalSince1970: 1_792_201_280)
private let hanzi66 = String(repeating: "公", count: 66), hanzi67 = String(repeating: "公", count: 67)

private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func filled(_ change: (inout AnnouncementDraft) -> Void = { _ in }) -> AnnouncementDraft {
    var draft = AnnouncementDraft(now: now, timeZone: shanghai)
    draft.title = "维护通知"; draft.content = "正文"
    change(&draft)
    return draft
}
private func announcement(status: AnnouncementStatus? = .active, targeting: AnnouncementTargeting = .everyone, startsAt: Date? = nil,
                          endsAt: Date? = nil) -> Announcement {
    Announcement(id: 7, title: "维护通知", content: "正文", status: status, notifyMode: .popup, targeting: targeting, startsAt: startsAt, endsAt: endsAt)
}
private let multiGroup = AnnouncementTargeting(anyOf: [
    AnnouncementConditionGroup(allOf: [.subscription(groupIDs: [4]), .balance("gte", value: 10)]),
    AnnouncementConditionGroup(allOf: [.balance("gte", value: 500)])
])

@Test func roleButtonsAndReceipts() {
    let create = AnnouncementEditRole(original: nil)
    #expect(create == .create && create.sheetTitle == "新建公告" && create.trailingTitle == "存草稿" && create.primaryTitle == "发布")
    #expect(create.trailingStatus == .draft && create.trailingReceipt == "已存为草稿")
    let draft = AnnouncementEditRole(original: announcement(status: .draft))
    #expect(draft == .draft && draft.sheetTitle == "编辑公告" && draft.trailingTitle == "存草稿" && draft.primaryTitle == "发布")
    #expect(draft.trailingStatus == nil && draft.trailingReceipt == "已存为草稿")
    let live = AnnouncementEditRole(original: announcement(status: .active))
    #expect(live == .live && live.trailingTitle == "保存" && live.primaryTitle == nil && live.trailingStatus == nil)
    #expect(live.trailingReceipt == "已保存 · 用户看到的是新内容")
    let archived = AnnouncementEditRole(original: announcement(status: .archived))
    #expect(archived == .archived && archived.trailingTitle == "保存" && archived.primaryTitle == "重新发布" && archived.trailingReceipt == "已保存")
    let unknown = AnnouncementEditRole(original: announcement(status: nil))
    #expect(unknown.trailingTitle == "保存" && unknown.primaryTitle == nil && unknown.trailingReceipt == "已保存")
    #expect(AnnouncementEditRole.publishReceipt == "已发布公告")
}

@Test func newDraftDefaults() {
    let draft = AnnouncementDraft(now: now, timeZone: shanghai)
    #expect(draft.notifyMode == .silent && draft.targetMode == .all && draft.conditionKind == .balance)
    #expect(draft.balanceOperator == .lt && draft.balanceText == "5" && draft.groupIDs.isEmpty && draft.lockedTargeting == nil)
    #expect(draft.startsAt == nil && draft.endsAt == nil && !draft.isValid)
    // 10:00 in Shanghai; Kolkata (+05:30) rounds on its own clock: 07:11:20 → 08:00 local = 02:30Z.
    #expect(draft.startPick == Date(timeIntervalSince1970: 1_792_202_400))
    #expect(draft.endPick == draft.startPick.addingTimeInterval(7 * 86_400))
    #expect(AnnouncementDraft(now: now, timeZone: kolkata).startPick == Date(timeIntervalSince1970: 1_792_204_200))
}

@Test func titleLimitCountsTrimmedUTF8Bytes() {
    #expect(filled { $0.title = hanzi66 }.isValid && filled { $0.title = hanzi66 }.titleFootnote == nil)
    let long = filled { $0.title = hanzi67 }
    #expect(!long.isValid && long.titleFootnote == "标题太长（最多约 66 个汉字）")
    #expect(filled { $0.title = String(repeating: "a", count: 200) }.isValid)
    #expect(!filled { $0.title = String(repeating: "a", count: 201) }.isValid)
    #expect(filled { $0.title = "  " + hanzi66 + "\n" }.isValid)
    let blank = filled { $0.title = "   " }
    #expect(!blank.isValid && blank.titleFootnote == nil)
}

@Test func contentConditionAndTimeValidation() {
    #expect(!filled { $0.content = " \n " }.isValid)
    #expect(!filled { $0.targetMode = .custom; $0.conditionKind = .subscription }.isValid)
    #expect(filled { $0.targetMode = .custom; $0.conditionKind = .subscription; $0.groupIDs = [4] }.isValid)
    for amount in ["", "0", ".", "0.00"] {
        #expect(!filled { $0.targetMode = .custom; $0.balanceText = amount }.isValid, "\(amount)")
    }
    #expect(filled { $0.targetMode = .custom; $0.balanceText = "0.01" }.isValid)
    #expect(AnnouncementDraft.sanitizedAmount("$1,2a.3.45") == "12.34")
    #expect(AnnouncementDraft.sanitizedAmount("12345678901") == "1234567890")
    let same = filled { $0.startsSpecified = true; $0.endsSpecified = true; $0.endPick = $0.startPick }
    #expect(!same.isValid && !same.isTimeRangeValid && same.scheduleFootnote == "结束时间要晚于开始时间。")
    #expect(filled { $0.startsSpecified = true; $0.endsSpecified = true; $0.endPick = $0.startPick.addingTimeInterval(1) }.isValid)
    // Only one side set is always fine, whatever the other pick says.
    #expect(filled { $0.endsSpecified = true; $0.endPick = $0.startPick.addingTimeInterval(-86_400) }.isValid)
    var locked = AnnouncementDraft(announcement: announcement(targeting: multiGroup), now: now, timeZone: shanghai)
    locked.balanceText = ""
    #expect(locked.isValid)
}

@Test func footnotesFollowSection17_3() {
    var draft = filled()
    #expect(draft.targetFootnote == "所有用户都能看到。")
    draft.targetMode = .custom
    #expect(draft.targetFootnote == "手机上设一个条件；多个条件组合请在 Web 编辑。")
    let locked = AnnouncementDraft(announcement: announcement(targeting: multiGroup), now: now, timeZone: shanghai)
    #expect(locked.targetFootnote == "这条公告的条件有多组 / 多条，手机上只读；要修改请在 Web 编辑。")
    #expect(draft.notifyFootnote == "静默：只出现在用户的通知列表里。")
    draft.notifyMode = .popup
    #expect(draft.notifyFootnote == "弹窗模式会自动弹出通知给用户。")
    #expect(draft.scheduleFootnote == "立即 = 开始时间留空；永久 = 结束时间留空。时间按本机时区。")
}

@Test func targetingAndCreateBodyBytes() throws {
    #expect(filled().targeting() == .everyone)
    let subscription = filled { $0.targetMode = .custom; $0.conditionKind = .subscription; $0.groupIDs = [5, 4] }
    #expect(subscription.targeting() == .single(.subscription(groupIDs: [4, 5])))
    let balance = filled { $0.targetMode = .custom; $0.balanceOperator = .lt; $0.balanceText = "5" }
    let body = try balance.createRequest(status: .draft).requestBody()
    #expect(text(body) == #"{"content":"正文","notify_mode":"silent","status":"draft","targeting":{"any_of":[{"all_of":[{"operator":"lt","type":"balance","value":5}]}]},"title":"维护通知"}"#)
    let locked = AnnouncementDraft(announcement: announcement(targeting: multiGroup), now: now, timeZone: shanghai)
    #expect(locked.targeting() == nil && locked.effectiveTargeting == multiGroup)
    let timed = filled { $0.title = "  维护通知 "; $0.startsSpecified = true; $0.endsSpecified = true }
    let timedBody = text(try timed.createRequest(status: .active).requestBody())
    #expect(timedBody.contains(#""starts_at":1792202400"#) && timedBody.contains(#""ends_at":1792807200"#))
    #expect(timedBody.contains(#""title":"维护通知""#) && timedBody.contains(#""targeting":{}"#))
}

@Test func updateDiffOnlyChangedKeys() throws {
    let original = announcement(status: .draft, targeting: .single(.subscription(groupIDs: [4, 5])), startsAt: now)
    let prefilled = AnnouncementDraft(announcement: original, now: now, timeZone: shanghai)
    #expect(prefilled.updateRequest(from: original, status: nil).isEmpty)
    var renamed = prefilled
    renamed.title = " 新标题 "
    #expect(renamed.updateRequest(from: original, status: nil) == AnnouncementUpdateRequest(title: "新标题"))
    var immediate = prefilled
    immediate.startsSpecified = false
    #expect(text(try immediate.updateRequest(from: original, status: nil).requestBody()) == #"{"starts_at":0}"#)
    var everyone = prefilled
    everyone.targetMode = .all
    #expect(text(try everyone.updateRequest(from: original, status: nil).requestBody()) == #"{"targeting":{}}"#)
    var reordered = prefilled
    reordered.groupIDs = [5, 4]
    #expect(reordered.updateRequest(from: original, status: nil).isEmpty)
    let multi = announcement(targeting: multiGroup)
    var lockedEdit = AnnouncementDraft(announcement: multi, now: now, timeZone: shanghai)
    lockedEdit.content = "新正文"
    #expect(lockedEdit.updateRequest(from: multi, status: nil) == AnnouncementUpdateRequest(content: "新正文"))
    #expect(prefilled.updateRequest(from: original, status: .active) == AnnouncementUpdateRequest(status: .active))
    #expect(AnnouncementDraft(announcement: multi, now: now, timeZone: shanghai).updateRequest(from: multi, status: .active).isEmpty)
}

@Test func prefillOptionsAndChanges() {
    let balance = AnnouncementDraft(announcement: announcement(targeting: .single(.balance("gte", value: decimal("10.5")))), now: now, timeZone: shanghai)
    #expect(balance.targetMode == .custom && balance.conditionKind == .balance && balance.balanceOperator == .gte && balance.balanceText == "10.5")
    let subscription = AnnouncementDraft(announcement: announcement(targeting: .single(.subscription(groupIDs: [4]))), now: now, timeZone: shanghai)
    #expect(subscription.conditionKind == .subscription && subscription.groupIDs == [4] && subscription.lockedTargeting == nil)
    let equal = AnnouncementDraft(announcement: announcement(targeting: .single(.balance("eq", value: 5))), now: now, timeZone: shanghai)
    #expect(equal.lockedTargeting != nil && equal.targetMode == .custom)
    let lines = AnnouncementDraft.lockedLines(multiGroup, groupNames: { $0 == 4 ? "企业专线" : nil })
    #expect(lines == [AnnouncementLockedLine(prefix: "条件", text: "订阅 企业专线 且 余额 ≥ $10.00"),
                      AnnouncementLockedLine(prefix: "或", text: "余额 ≥ $500.00")])

    let groups = [AdminGroup(id: 1, name: "高级组"), AdminGroup(id: 4, name: "企业专线", subscriptionType: "subscription"),
                  AdminGroup(id: 6, name: "测试组", status: "inactive", subscriptionType: "subscription")]
    #expect(AnnouncementDraft.subscriptionOptions(groups: groups, selected: [4, 6, 99]) == [
        AnnouncementGroupOption(id: 4, name: "企业专线", isAvailable: true), AnnouncementGroupOption(id: 6, name: "测试组", isAvailable: false),
        AnnouncementGroupOption(id: 99, name: "分组 #99", isAvailable: false)
    ])
    #expect(AnnouncementDraft.subscriptionOptions(groups: groups, selected: []).map(\.id) == [4])

    var changed = balance
    #expect(!changed.hasChanges(comparedTo: balance))
    changed.content = "改了"
    #expect(changed.hasChanges(comparedTo: balance))
    changed.content = balance.content
    #expect(!changed.hasChanges(comparedTo: balance))
    changed.startsSpecified = true
    #expect(changed.hasChanges(comparedTo: balance))
    changed.startsSpecified = false
    changed.balanceText = "10.50"
    #expect(!changed.hasChanges(comparedTo: balance))
    changed.targetMode = .all
    #expect(changed.hasChanges(comparedTo: balance))
}
