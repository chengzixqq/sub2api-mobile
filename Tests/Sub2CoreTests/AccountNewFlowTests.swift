import Foundation
import Testing
@testable import Sub2Core

private func frozenRequest(groupIDs: [Int] = [1], key: UUID? = UUID()) -> AccountNewFrozenRequest {
    let request = AccountCreateRequest(name: "Claude-03", platform: "anthropic", type: "apikey", credentials: ["api_key": "sk-fixture"],
                                       concurrency: 10, priority: 1, rateMultiplier: 1, groupIDs: groupIDs)
    return AccountNewFrozenRequest(request: request, key: key, submittedAt: Date(timeIntervalSince1970: 1_800_000_000))
}

@Test func subtitlesCountMissingOrNameTheCreatedAccount() {
    #expect(AccountNewFlow.subtitle(site: "演示站", missingCount: 3, createdID: nil, status: .paused) == "演示站 · 还差 3 项")
    #expect(AccountNewFlow.subtitle(site: "演示站", missingCount: 0, createdID: nil, status: .paused) == "演示站 · 必填已填齐")
    let created: [(AccountNewScheduleStatus, String)] = [(.paused, "暂停调度"), (.error, "错误（已停止调度）"), (.unconfirmed, "调度状态待核对"),
                                                         (.active, "参与调度")]
    for (status, tail) in created {
        #expect(AccountNewFlow.subtitle(site: "演示站", missingCount: 2, createdID: 21, status: status) == "演示站 · #21 已创建 · \(tail)")
        #expect(status.title == tail)
    }
}

@Test func dockTitlesFollowCreationAndChanges() {
    #expect(AccountNewFlow.dockActionTitle(isCreated: false, hasChanges: true) == "创建并测试")
    #expect(AccountNewFlow.dockActionTitle(isCreated: false, hasChanges: false) == "创建并测试")
    #expect(AccountNewFlow.dockActionTitle(isCreated: true, hasChanges: true) == "保存并重新测试")
    #expect(AccountNewFlow.dockActionTitle(isCreated: true, hasChanges: false) == "重新测试")
}

struct AccountNewCancelCase: Sendable, CustomTestStringConvertible {
    let hasPlatform, isCreated, isBusy, isTesting, isPassed, pauseUnconfirmed, resultUnconfirmed: Bool
    let expected: AccountNewCancelAction
    var testDescription: String { "\(expected)" }
    init(platform: Bool = true, created: Bool = false, busy: Bool = false, testing: Bool = false, passed: Bool = false, pauseUnconfirmed: Bool = false,
         resultUnconfirmed: Bool = false, _ expected: AccountNewCancelAction) {
        hasPlatform = platform; isCreated = created; isBusy = busy; isTesting = testing; isPassed = passed; self.pauseUnconfirmed = pauseUnconfirmed
        self.resultUnconfirmed = resultUnconfirmed
        self.expected = expected
    }
}

@Test(arguments: [
    AccountNewCancelCase(platform: false, .close),
    AccountNewCancelCase(.confirmDiscard),
    AccountNewCancelCase(busy: true, .blocked),
    AccountNewCancelCase(created: true, busy: true, .blocked),
    AccountNewCancelCase(created: true, busy: true, testing: true, .continueInBackground),
    AccountNewCancelCase(created: true, passed: true, .finish),
    AccountNewCancelCase(created: true, pauseUnconfirmed: true, .resolvePauseFailed),
    AccountNewCancelCase(created: true, busy: true, pauseUnconfirmed: true, .blocked),
    AccountNewCancelCase(created: true, .resolveCreated),
    AccountNewCancelCase(resultUnconfirmed: true, .resolveUnconfirmed),
    AccountNewCancelCase(platform: false, resultUnconfirmed: true, .resolveUnconfirmed),
    AccountNewCancelCase(busy: true, resultUnconfirmed: true, .blocked)
])
func cancelActionFollowsTheFlow(_ item: AccountNewCancelCase) {
    #expect(AccountNewFlow.cancelAction(hasPlatform: item.hasPlatform, isCreated: item.isCreated, isBusy: item.isBusy, isTesting: item.isTesting,
                                        isPassed: item.isPassed, pauseUnconfirmed: item.pauseUnconfirmed,
                                        resultUnconfirmed: item.resultUnconfirmed) == item.expected)
}

@Test func precheckAndTestOutcomeHelpers() {
    #expect(AccountNewFlow.needsMixedChannelPrecheck(platform: "anthropic", groupIDs: [1], hasMixedChannelDetails: false, alreadyConfirmed: false))
    #expect(AccountNewFlow.needsMixedChannelPrecheck(platform: "antigravity", groupIDs: [1, 2], hasMixedChannelDetails: false, alreadyConfirmed: false))
    #expect(!AccountNewFlow.needsMixedChannelPrecheck(platform: "openai", groupIDs: [1], hasMixedChannelDetails: false, alreadyConfirmed: false))
    #expect(!AccountNewFlow.needsMixedChannelPrecheck(platform: "anthropic", groupIDs: [], hasMixedChannelDetails: false, alreadyConfirmed: false))
    #expect(!AccountNewFlow.needsMixedChannelPrecheck(platform: "anthropic", groupIDs: [1], hasMixedChannelDetails: true, alreadyConfirmed: false))
    #expect(!AccountNewFlow.needsMixedChannelPrecheck(platform: "anthropic", groupIDs: [1], hasMixedChannelDetails: false, alreadyConfirmed: true))
    #expect(AccountNewFlow.heldInError(markedError: true, statusAfterTest: nil))
    #expect(AccountNewFlow.heldInError(markedError: nil, statusAfterTest: "error"))
    #expect(!AccountNewFlow.heldInError(markedError: false, statusAfterTest: "active"))
    #expect(!AccountNewFlow.heldInError(markedError: nil, statusAfterTest: nil))
    #expect(AccountNewFlow.mayBeMixedChannelConflict(APIError.server(status: 409, reason: AccountWriteReason.mixedChannelWarning)))
    #expect(!AccountNewFlow.mayBeMixedChannelConflict(APIError.server(status: 409, reason: "ACCOUNT_VERSION_CONFLICT")))
    #expect(!AccountNewFlow.mayBeMixedChannelConflict(APIError(kind: .transport, message: "x")))
}

@Test func confirmingMixedChannelRenewsTheKeyAndKeepsTheFirstSendTime() {
    let frozen = frozenRequest()
    let renewed = UUID()
    let confirmed = frozen.confirmingMixedChannel(renewingKeyWith: renewed)
    #expect(confirmed.key == renewed && confirmed.submittedAt == frozen.submittedAt)
    #expect(confirmed.request == frozen.request.confirmingMixedChannel() && !frozen.request.confirmMixedChannelRisk)
    let unkeyed = frozenRequest(key: nil).confirmingMixedChannel(renewingKeyWith: renewed)
    #expect(unkeyed.key == nil && unkeyed.request.confirmMixedChannelRisk)
}
