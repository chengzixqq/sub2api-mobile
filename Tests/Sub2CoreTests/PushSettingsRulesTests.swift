import Foundation
import Testing
@testable import Sub2Core

// 60 §7.3–§7.5 (S6-24): the push page's switch and test availability, subscription edits, quiet-hour clock, scope options
// and how a failed test or write reads.

private let notReady = PushAPNsConfig(enabled: true, ready: false)
private let ready = PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true, ready: true)
private func failure(_ status: Int, _ reason: String?, _ metadata: [String: String] = [:], outcome: SecurityPromptOutcome? = nil) -> APIError {
    let base = APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata))
    return outcome.map(base.withSecurityOutcome) ?? base
}
private let transport = APIError(kind: .transport, message: "网络连接已断开")

// MARK: This phone (7.3, 7.5)

@Test func localControlsFollowConfigListAndState() {
    let off = PushLocalControls(state: .off, config: notReady, configPending: false, listFailed: false, isBusy: false)
    #expect(!off.toggleEnabled); #expect(off.toggleNote == "站点配好 APNs 后才能打开")
    #expect(!off.testEnabled); #expect(!off.showsSubscription)
    let unread = PushLocalControls(state: .off, config: nil, configPending: false, listFailed: false, isBusy: false)
    #expect(unread.toggleEnabled); #expect(unread.toggleNote == nil)
    #expect(!PushLocalControls(state: .off, config: nil, configPending: true, listFailed: false, isBusy: false).toggleEnabled)
    let failed = PushLocalControls(state: .on, config: ready, configPending: false, listFailed: true, isBusy: false)
    #expect(!failed.toggleEnabled); #expect(!failed.testEnabled); #expect(!failed.showsSubscription)
    let stopped = PushLocalControls(state: .disabled, config: ready, configPending: false, listFailed: false, isBusy: false)
    #expect(stopped.toggleEnabled); #expect(stopped.testEnabled); #expect(stopped.showsSubscription)
    // Turned on before the site lost its APNs settings: it can still be turned off.
    let onNotReady = PushLocalControls(state: .on, config: notReady, configPending: false, listFailed: false, isBusy: false)
    #expect(onNotReady.toggleEnabled); #expect(onNotReady.toggleNote == nil); #expect(onNotReady.testEnabled)
    let busy = PushLocalControls(state: .on, config: ready, configPending: false, listFailed: false, isBusy: true)
    #expect(!busy.toggleEnabled); #expect(!busy.testEnabled); #expect(busy.showsSubscription)
}

// MARK: Subscription edits (7.3, 7.4)

@Test func eventEditsKeepBackendOrderAndAllOffPauses() throws {
    let start = PushSubscription.default
    let withTests = PushSubscriptionEdit.setting(.accountTestFinished, on: true, in: start)
    #expect(withTests.events == [.opsAlertFired, .accountError, .accountTestFinished])
    #expect(start.events == [.opsAlertFired, .accountError])
    let withResolved = PushSubscriptionEdit.setting(.opsAlertResolved, on: true, in: withTests)
    #expect(withResolved.events == [.opsAlertFired, .opsAlertResolved, .accountError, .accountTestFinished])
    #expect(PushSubscriptionEdit.setting(.opsAlertFired, on: true, in: withResolved).events == withResolved.events)
    let paused = PushEvent.allCases.reduce(withResolved) { PushSubscriptionEdit.setting($1, on: false, in: $0) }
    #expect(paused.isPaused)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(paused)) as? [String: Any])
    #expect((json["events"] as? [String]) == [])
}

@Test func severityPlatformAndGroupEditsReplaceOnlyTheirField() {
    let quiet = PushQuietHours(startMinute: 1_320, endMinute: 480)
    let start = PushSubscription(events: [.accountError], minSeverity: .p2, groupIDs: [4], platforms: ["gemini"], quietHours: quiet)
    let severe = PushSubscriptionEdit.setting(minSeverity: .p0, in: start)
    #expect(severe == PushSubscription(events: [.accountError], minSeverity: .p0, groupIDs: [4], platforms: ["gemini"], quietHours: quiet))
    let platforms = PushSubscriptionEdit.setting(platforms: ["openai", "anthropic"], in: start)
    #expect(platforms == PushSubscription(events: [.accountError], minSeverity: .p2, groupIDs: [4], platforms: ["openai", "anthropic"], quietHours: quiet))
    let groups = PushSubscriptionEdit.setting(groupIDs: [3, 1], in: start)
    #expect(groups == PushSubscription(events: [.accountError], minSeverity: .p2, groupIDs: [3, 1], platforms: ["gemini"], quietHours: quiet))
}

@Test func quietHoursToggleUsesTheDefaultWindowAndOffIsNull() throws {
    let none = PushSubscription.default
    #expect(PushSubscriptionEdit.setting(quietHours: true, in: none).quietHours == PushQuietHours(start: "23:00", end: "07:00"))
    let set = PushSubscription(events: [.accountError], quietHours: PushQuietHours(start: "22:00", end: "08:00"))
    #expect(PushSubscriptionEdit.setting(quietHours: true, in: set).quietHours == set.quietHours)
    let cleared = PushSubscriptionEdit.setting(quietHours: false, in: set)
    #expect(cleared.quietHours == nil)
    let json = try #require(String(data: JSONEncoder().encode(cleared), encoding: .utf8))
    #expect(json.contains("\"quiet_hours\":null"))
    let start = PushSubscriptionEdit.setting(quietStart: 1_350, in: set)
    #expect(start.quietHours == PushQuietHours(start: "22:30", end: "08:00"))
    let end = PushSubscriptionEdit.setting(quietEnd: 390, in: set)
    #expect(end.quietHours == PushQuietHours(start: "22:00", end: "06:30"))
    #expect(PushSubscriptionEdit.setting(quietStart: 1_440, in: set) == set)
    #expect(PushSubscriptionEdit.setting(quietEnd: -1, in: set) == set)
}

@Test func quietClockRoundTripsMinutesInGMT() {
    #expect(PushQuietClock.timeZone.secondsFromGMT() == 0)
    for minute in [0, 420, 1_380, 1_439] {
        #expect(PushQuietClock.minuteOfDay(PushQuietClock.date(minuteOfDay: minute)) == minute)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = PushQuietClock.timeZone; formatter.dateFormat = "HH:mm"
    #expect(formatter.string(from: PushQuietClock.date(minuteOfDay: 420)) == "07:00")
    // A wall clock in another zone would read another hour; the minutes are always GMT's.
    var shanghai = Calendar(identifier: .gregorian); shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    #expect(shanghai.component(.hour, from: PushQuietClock.date(minuteOfDay: 420)) == 15)
    #expect(PushQuietClock.minuteOfDay(PushQuietClock.date(minuteOfDay: 2_000)) == 1_439)
    #expect(PushQuietClock.minuteOfDay(PushQuietClock.date(minuteOfDay: -5)) == 0)
}

// MARK: Scope options (7.3)

@Test func platformOptionsFollowTheCatalogAndKeepUnknownSelections() {
    let options = PushScopeOptions.platforms(catalog: .builtin, selected: [])
    #expect(options.map(\.id) == MetaCatalog.builtin.platforms.map(\.id))
    #expect(options.first { $0.id == "anthropic" }?.title == "Anthropic")
    #expect(options.first { $0.id == "zhipu" }?.title == "智谱 GLM")
    let kept = PushScopeOptions.platforms(catalog: .builtin, selected: ["legacyx", "openai", " LegacyX "])
    #expect(kept.count == MetaCatalog.builtin.platforms.count + 1)
    #expect(kept.last == PushScopeOption(id: "legacyx", title: "legacyx"))
}

@Test func groupOptionsFollowTheDirectoryAndKeepMissingSelections() {
    let groups = [AdminGroup(id: 2, name: "高级组"), AdminGroup(id: 5, name: "默认组")]
    #expect(PushScopeOptions.groups(groups, selected: []) == [PushScopeOption(id: 2, title: "高级组"), PushScopeOption(id: 5, title: "默认组")])
    let kept = PushScopeOptions.groups(groups, selected: [5, 999])
    #expect(kept.map(\.id) == [2, 5, 999])
    #expect(kept.last?.title == "分组 #999")
}

@Test func togglingRespectsTheLimits() {
    #expect(PushScopeOptions.toggling(5, in: [1, 5], limit: 100) == [1])
    #expect(PushScopeOptions.toggling(7, in: [1], limit: 100) == [1, 7])
    #expect(PushScopeOptions.toggling(101, in: Array(1...100), limit: PushSubscription.maxGroupIDs) == nil)
    let twenty = (1...20).map { "p\($0)" }
    #expect(PushScopeOptions.toggling("p21", in: twenty, limit: PushSubscription.maxPlatforms) == nil)
    #expect(PushScopeOptions.toggling("p3", in: twenty, limit: PushSubscription.maxPlatforms)?.count == 19)
}

// MARK: Failures (7.4)

@Test func testOutcomeClassifiesThePushReasons() {
    #expect(PushTestOutcome.classify(failure(503, "PUSH_NOT_CONFIGURED")) == .refused("站点没有配好 APNs"))
    let refused = failure(502, "PUSH_DELIVERY_FAILED", ["provider_reason": "BadDeviceToken", "provider_status": "400"])
    #expect(PushTestOutcome.classify(refused) == .refused("推送服务没有接受：BadDeviceToken（400）"))
    #expect(PushTestOutcome.classify(failure(404, "PUSH_DEVICE_NOT_FOUND")) == .gone)
    #expect(PushTestOutcome.classify(CancellationError()) == .cancelled)
    #expect(PushTestOutcome.classify(failure(403, "STEP_UP_REQUIRED", outcome: .cancelled)) == .cancelled)
    #expect(PushTestOutcome.classify(transport) == .failed("网络连接已断开"))
    let server = failure(500, nil)
    #expect(PushTestOutcome.classify(server) == .failed(PushPresentation.failureMessage(server)))
}

@Test func writeFailureClassifiesGoneUnconfirmedAndRejected() {
    let gone = failure(404, "PUSH_DEVICE_NOT_FOUND")
    #expect(PushWriteFailure.classify(gone) == .gone); #expect(PushWriteFailure.isGone(gone))
    let otherNotFound = failure(404, "NOT_FOUND")
    #expect(!PushWriteFailure.isGone(otherNotFound))
    #expect(PushWriteFailure.classify(otherNotFound) == .rejected(PushPresentation.failureMessage(otherNotFound)))
    for lost in [transport, APIError.invalidResponse, failure(502, nil), failure(504, nil), failure(503, nil), failure(503, "SERVICE_UNAVAILABLE")] {
        #expect(PushWriteFailure.classify(lost) == .unconfirmed)
    }
    #expect(PushWriteFailure.classify(failure(503, "PUSH_NOT_CONFIGURED")) == .rejected("站点没有配好 APNs"))
    #expect(PushWriteFailure.classify(APIError.refreshDeferred) == .rejected(APIError.refreshDeferred.localizedDescription))
    let passed = failure(403, "STEP_UP_REQUIRED", outcome: .passed)
    #expect(PushWriteFailure.classify(passed) == .reconfirm(passed.localizedDescription))
    #expect(PushWriteFailure.classify(failure(403, "STEP_UP_REQUIRED", outcome: .cancelled)) == .cancelled)
    #expect(PushWriteFailure.classify(CancellationError()) == .cancelled)
    let readOnly = failure(403, "ACCESS_TOKEN_READ_ONLY")
    #expect(PushWriteFailure.classify(readOnly) == .rejected(readOnly.localizedDescription))
}

@Test(arguments: [("events", "推送事件"), ("min_severity", "告警级别"), ("group_ids", "分组范围"), ("platforms", "平台范围"),
                  ("quiet_hours", "免打扰")])
func invalidSubscriptionPointsAtItsControl(field: String, title: String) {
    #expect(PushPresentation.subscriptionFieldTitle(field) == title)
    let error = failure(400, "INVALID_PUSH_SUBSCRIPTION", ["field": field])
    #expect(PushWriteFailure.classify(error) == .rejected(title + "的值不被站点接受"))
}

@Test func invalidSubscriptionWithoutAKnownFieldKeepsTheCatalogText() {
    #expect(PushPresentation.subscriptionFieldTitle("body") == nil); #expect(PushPresentation.subscriptionFieldTitle(nil) == nil)
    for error in [failure(400, "INVALID_PUSH_SUBSCRIPTION", ["field": "body"]), failure(400, "INVALID_PUSH_SUBSCRIPTION")] {
        #expect(PushWriteFailure.classify(error) == .rejected(PushPresentation.failureMessage(error)))
    }
}

@Test func settingsCopyMatchesTheSpec() {
    #expect(PushPresentation.localToggleTitle == "在本机接收推送")
    #expect(PushPresentation.deleteTargetRow == "删除接收方式…")
    #expect(PushPresentation.deleteTargetConsequence == "这个地址不再收到推送，要恢复需重新添加。")
    #expect(PushPresentation.targetObjectNoun == "接收方式")
    #expect(PushPresentation.deleteFailed(reason: "X") == "删除没有成功：X")
    #expect(PushPresentation.subscriptionNotSaved(reason: "X") == "推送内容没有保存：X")
    #expect([PushPresentation.localSectionTitle, PushPresentation.contentSectionTitle, PushPresentation.otherTargetsTitle,
             PushPresentation.apnsSectionTitle] == ["本机", "推送内容", "其他接收方式", "站点 APNs 配置"])
    #expect(PushPresentation.platformLimitNote == "最多选 20 个平台"); #expect(PushPresentation.groupLimitNote == "最多选 100 个分组")
}
