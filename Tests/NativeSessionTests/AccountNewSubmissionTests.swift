import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private func newAccount(id: Int = 13, name: String = "Claude-04", platform: String = "anthropic", schedulable: Bool = false) throws -> UpstreamAccount {
    let json = #"{"id":\#(id),"name":"\#(name)","platform":"\#(platform)","type":"apikey","status":"active","schedulable":\#(schedulable)}"#
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func createRequest(platform: String = "anthropic", groups: [Int] = [], name: String = "Claude-04", key: String = "sk-ant-api03-fixture") -> AccountCreateRequest {
    AccountCreateRequest(name: name, platform: platform, type: "apikey", credentials: ["api_key": .string(key), "base_url": "https://api.anthropic.com"],
                         concurrency: 10, priority: 1, rateMultiplier: 1, groupIDs: groups)
}
private func mixedConflict(metadata: [String: String]?) -> APIError {
    APIError.server(status: 409, envelope: ErrorEnvelope(reason: metadata == nil ? nil : AccountWriteReason.mixedChannelWarning, metadata: metadata))
}
private let highGroupMetadata = ["group_id": "1", "group_name": "高级组", "current_platform": "Anthropic", "other_platform": "Antigravity"]
private let unconfirmedFailure = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)

/// Answers each call from its script (the last answer repeats) and records what it was asked, with the generation.
@MainActor private final class FakeCreateSource: AccountCreateSource {
    var accountCreateSession: AccountCreateSession? = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: true,
                                                                          isReadOnlyToken: false)
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    var creates: [Result<UpstreamAccount, any Error>] = []
    var checks: [Result<MixedChannelCheck, any Error>] = [.success(MixedChannelCheck(hasRisk: false))]
    var pauses: [Result<UpstreamAccount, any Error>] = []
    var lookups: [Result<UpstreamAccount?, any Error>] = [.success(nil)]
    private(set) var sentCreates: [(request: AccountCreateRequest, key: UUID?, generation: UUID)] = []
    private(set) var sentChecks: [(platform: String, groups: [Int], accountID: Int?)] = []
    private(set) var sentPauses: [(id: Int, enabled: Bool, key: UUID?, generation: UUID)] = []
    private(set) var sentLookups: [(name: String, platform: String, notBefore: Date)] = []
    /// Ends the session while the create is out.
    var endSessionDuringCreate = false

    func serverNow() -> Date { now }
    func createAccount(_ request: AccountCreateRequest, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler?,
                       generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        sentCreates.append((request, idempotencyKey, generation))
        if endSessionDuringCreate {
            accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: true, isReadOnlyToken: false)
        }
        return WriteOutcome(value: try Self.next(&creates).get())
    }
    func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?, generation: UUID) async throws -> MixedChannelCheck {
        sentChecks.append((platform, groupIDs, accountID))
        return try Self.next(&checks).get()
    }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        sentPauses.append((id, enabled, idempotencyKey, generation))
        return WriteOutcome(value: try Self.next(&pauses).get())
    }
    func findCreatedAccount(name: String, platform: String, notBefore: Date) async throws -> UpstreamAccount? {
        sentLookups.append((name, platform, notBefore))
        return try Self.next(&lookups).get()
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) -> Result<T, any Error> {
        script.count > 1 ? script.removeFirst() : script[0]
    }
}

/// Keys K1, K2, … in the order they are made.
@MainActor private final class KeyMaker {
    private(set) var made: [UUID] = []
    func make() -> UUID { let key = UUID(); made.append(key); return key }
}

@MainActor private func submission(_ source: FakeCreateSource, _ keys: KeyMaker) -> AccountNewSubmission {
    AccountNewSubmission(source: source, makeKey: { keys.make() })
}

@MainActor @Test func keyIsMadeAtTapAndCreateSendsItOnce() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    try #require(keys.made.count == 1 && source.sentCreates.count == 1)
    #expect(source.sentCreates.count == 1 && source.sentCreates[0].key == keys.made[0] && source.sentCreates[0].request == createRequest())
    #expect(source.sentCreates[0].generation == source.accountCreateSession?.generation)
    #expect(flow.stage == .created(accountID: 13) && flow.account?.id == 13 && flow.locksForm && flow.scheduleStatus == .paused)
    #expect(source.sentLookups.isEmpty && source.sentChecks.isEmpty)
}

@MainActor @Test func honoredSchedulableFalseSkipsPause() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.success(try newAccount(schedulable: false))]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(source.sentPauses.isEmpty && flow.stage == .created(accountID: 13))
}

@MainActor @Test func ignoredSchedulableIsStoppedWithItsOwnKey() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.success(try newAccount(schedulable: true))]
    source.pauses = [.success(try newAccount(schedulable: false))]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    try #require(source.sentPauses.count == 1 && keys.made.count == 2)
    #expect(source.sentPauses[0].id == 13 && !source.sentPauses[0].enabled)
    #expect(keys.made.count == 2 && source.sentPauses[0].key == keys.made[1] && keys.made[1] != keys.made[0])
    #expect(flow.stage == .created(accountID: 13) && flow.account?.schedulable == false)
}

@MainActor @Test func pauseFailureEntersPauseUnconfirmedAndRetryUsesNewKey() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.success(try newAccount(schedulable: true))]
    source.pauses = [.failure(APIError.server(status: 502, reason: nil)), .success(try newAccount(schedulable: false))]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    guard case .pauseUnconfirmed(13, let reason) = flow.stage else { Issue.record("\(flow.stage)"); return }
    #expect(!reason.isEmpty && flow.locksForm && !flow.isBusy && flow.scheduleStatus == .unconfirmed && flow.createdAccountID == 13)
    await flow.retryPause()
    try #require(source.sentPauses.count == 2 && keys.made.count == 3)
    #expect(source.sentPauses[1].key == keys.made[2] && source.sentPauses[1].key != source.sentPauses[0].key)
    #expect(flow.stage == .created(accountID: 13) && source.sentCreates.count == 1)
}

@MainActor @Test func mixedDetailsCapabilitySubmitsDirectlyAndAsksOn409() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(mixedConflict(metadata: highGroupMetadata))]
    let flow = submission(source, keys)
    await flow.submit(createRequest(groups: [1]))
    #expect(source.sentChecks.isEmpty && source.sentCreates.count == 1)
    guard case .confirmingMixedChannel(let warning) = flow.stage else { Issue.record("\(flow.stage)"); return }
    #expect(warning.groupName == "高级组" && warning.currentPlatform == "Anthropic" && warning.otherPlatform == "Antigravity")
}

@MainActor @Test func withoutMixedDetailsChecksFirstAndDeclineSendsNothing() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: false, isReadOnlyToken: false)
    source.checks = [.success(MixedChannelCheck(hasRisk: true, details: .init(groupID: 1, groupName: "高级组", currentPlatform: "Antigravity",
                                                                              otherPlatform: "Anthropic")))]
    let flow = submission(source, keys)
    await flow.submit(createRequest(platform: "antigravity", groups: [1], name: "Antigravity-01"))
    try #require(source.sentChecks.count == 1)
    #expect(source.sentChecks[0].platform == "antigravity" && source.sentChecks[0].groups == [1])
    #expect(source.sentChecks[0].accountID == nil)
    guard case .confirmingMixedChannel(let warning) = flow.stage else { Issue.record("\(flow.stage)"); return }
    #expect(warning.groupName == "高级组")
    flow.declineMixedChannel()
    #expect(flow.stage == .idle && source.sentCreates.isEmpty)
}

@MainActor @Test func confirmedMixedChannelRenewsKeyAndCarriesFlag() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(mixedConflict(metadata: highGroupMetadata)), .success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest(groups: [1]))
    await flow.confirmMixedChannel()
    try #require(source.sentCreates.count == 2 && keys.made.count == 2)
    #expect(source.sentCreates[1].request.confirmMixedChannelRisk && !source.sentCreates[0].request.confirmMixedChannelRisk)
    #expect(source.sentCreates[1].key == keys.made[1] && source.sentCreates[1].key != source.sentCreates[0].key)
    #expect(source.sentChecks.isEmpty && flow.stage == .created(accountID: 13))
}

@MainActor @Test func sameGroupsAreNotAskedAgainInTheFlow() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: false, isReadOnlyToken: false)
    let risk = MixedChannelCheck(hasRisk: true, details: .init(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic", otherPlatform: "Antigravity"))
    source.checks = [.success(risk)]
    source.creates = [.failure(APIError.server(status: 400, reason: nil)), .success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest(groups: [1, 5]))
    await flow.confirmMixedChannel()
    guard case .rejected = flow.stage else { Issue.record("\(flow.stage)"); return }
    await flow.submit(createRequest(groups: [1]))
    guard case .confirmingMixedChannel = flow.stage else { Issue.record("\(flow.stage)"); return }
    #expect(source.sentChecks.count == 2)
    flow.declineMixedChannel()
    await flow.submit(createRequest(groups: [5, 1]))
    try #require(source.sentCreates.count == 2)
    #expect(source.sentChecks.count == 2 && source.sentCreates[1].request.confirmMixedChannelRisk)
    #expect(source.sentCreates[1].request.groupIDs == [5, 1] && source.sentCreates[1].key != source.sentCreates[0].key)
    #expect(flow.stage == .created(accountID: 13))
}

@MainActor @Test func otherPlatformsOrNoGroupsSkipCheck() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: false, isReadOnlyToken: false)
    source.creates = [.success(try newAccount(platform: "openai"))]
    await submission(source, keys).submit(createRequest(platform: "openai", groups: [2]))
    await submission(source, keys).submit(createRequest(groups: []))
    #expect(source.sentChecks.isEmpty && source.sentCreates.count == 2)
}

@MainActor @Test func legacy409WithoutMetadataFetchesDetails() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(mixedConflict(metadata: nil))]
    source.checks = [.success(MixedChannelCheck(hasRisk: true, details: .init(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic",
                                                                              otherPlatform: "Antigravity")))]
    let flow = submission(source, keys)
    await flow.submit(createRequest(groups: [1]))
    #expect(source.sentChecks.count == 1)
    guard case .confirmingMixedChannel(let warning) = flow.stage else { Issue.record("\(flow.stage)"); return }
    #expect(warning.groupName == "高级组")

    source.checks = [.success(MixedChannelCheck(hasRisk: false))]
    let quiet = submission(source, keys)
    await quiet.submit(createRequest(groups: [1]))
    #expect(quiet.stage == .rejected(reason: mixedConflict(metadata: nil).localizedDescription))
    let ungrouped = submission(source, keys)
    await ungrouped.submit(createRequest(groups: []))
    #expect(ungrouped.stage == .rejected(reason: mixedConflict(metadata: nil).localizedDescription) && source.sentChecks.count == 2)
}

@MainActor @Test func unconfirmedCreateReconcilesByNameAndContinues() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(unconfirmedFailure)]
    source.lookups = [.success(try newAccount(schedulable: true))]
    source.pauses = [.success(try newAccount(schedulable: false))]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    try #require(source.sentLookups.count == 1)
    #expect(source.sentLookups[0].name == "Claude-04" && source.sentLookups[0].platform == "anthropic")
    #expect(source.sentLookups[0].notBefore == source.now)
    #expect(source.sentPauses.count == 1 && flow.stage == .created(accountID: 13) && source.sentCreates.count == 1)
}

@MainActor @Test func reconcileNotFoundOffersSameKeyRetry() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(unconfirmedFailure), .success(try newAccount())]
    source.lookups = [.success(nil)]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(flow.stage == .notCreated && !flow.locksForm && flow.isKeyed)
    await flow.retrySameKey()
    try #require(source.sentCreates.count == 2)
    #expect(source.sentCreates[1].key == source.sentCreates[0].key && source.sentCreates[1].request == source.sentCreates[0].request)
    #expect(keys.made.count == 1 && flow.stage == .created(accountID: 13))
}

@MainActor @Test func reconcileFailureStaysUnconfirmed() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(unconfirmedFailure)]
    source.lookups = [.failure(APIError(kind: .transport, message: "网络中断")), .success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(flow.stage == .unconfirmed(reason: KeyedWriteFailure.unconfirmedMessage) && flow.locksForm)
    await flow.reconcile()
    #expect(source.sentLookups.count == 2 && flow.stage == .created(accountID: 13) && source.sentCreates.count == 1)
}

@MainActor @Test func definiteRejectionReturnsToIdleWithNewKeyNextTime() async throws {
    let refusals: [APIError] = [APIError.server(status: 400, reason: nil), APIError.server(status: 409, reason: "ACCOUNT_NAME_EXISTS"),
                                APIError.server(status: 429, reason: nil), APIError(kind: .validation, message: "请输入账号名称")]
    for refusal in refusals {
        let source = FakeCreateSource(), keys = KeyMaker()
        source.creates = [.failure(refusal), .success(try newAccount())]
        let flow = submission(source, keys)
        await flow.submit(createRequest(platform: "openai"))
        #expect(flow.stage == .rejected(reason: AccountActionCopy.reason(for: refusal)) && !flow.locksForm && source.sentLookups.isEmpty)
        await flow.submit(createRequest(platform: "openai"))
        try #require(source.sentCreates.count == 2)
        #expect(source.sentCreates[1].key != source.sentCreates[0].key)
    }
}

@MainActor @Test func needsNewKeyDropsFrozenKey() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    source.creates = [.failure(conflict), .success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(flow.stage == .rejected(reason: conflict.localizedDescription))
    await flow.retrySameKey()
    #expect(source.sentCreates.count == 1)
    await flow.submit(createRequest())
    try #require(source.sentCreates.count == 2 && keys.made.count == 2)
    #expect(source.sentCreates[1].key == keys.made[1])
}

@MainActor @Test func clearedSecurityRefusalReusesKeyOnlyForSameRequest() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    let cleared = APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED").withSecurityOutcome(.passed)
    source.creates = [.failure(cleared), .failure(cleared), .success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    guard case .reconfirm = flow.stage else { Issue.record("\(flow.stage)"); return }
    await flow.submit(createRequest())
    try #require(source.sentCreates.count == 2)
    #expect(source.sentCreates[1].key == source.sentCreates[0].key && keys.made.count == 1)
    flow.draftDidChange(createRequest(name: "Claude-05"))
    #expect(flow.stage == .idle)
    await flow.submit(createRequest(name: "Claude-05"))
    try #require(source.sentCreates.count == 3 && keys.made.count == 2)
    #expect(source.sentCreates[2].key == keys.made[1])
}

@MainActor @Test func unchangedDraftKeepsRefusalAndAnIncompleteOneClearsIt() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.failure(unconfirmedFailure)]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(flow.stage == .notCreated)
    flow.draftDidChange(createRequest())
    #expect(flow.stage == .notCreated)
    flow.draftDidChange(nil)
    #expect(flow.stage == .idle)
}

@MainActor @Test func withoutIdempotentWritesNoKeyIsSent() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: false, mixedChannelDetails: true, isReadOnlyToken: false)
    source.creates = [.failure(APIError(kind: .transport, message: "网络中断")), .success(try newAccount(schedulable: true))]
    source.lookups = [.success(nil)]
    source.pauses = [.success(try newAccount())]
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    try #require(source.sentCreates.count == 1)
    #expect(source.sentCreates[0].key == nil && flow.stage == .notCreated && !flow.isKeyed)
    #expect(AccountNewDockContent.make(stage: flow.stage, missing: [], keyed: flow.isKeyed).primary == .resend)
    await flow.retrySameKey()
    try #require(source.sentCreates.count == 2 && source.sentPauses.count == 1)
    #expect(source.sentPauses[0].key == nil && keys.made.isEmpty && flow.stage == .created(accountID: 13))
}

@MainActor @Test func serverErrorIsTreatedAsUnconfirmed() async throws {
    let failures: [any Error] = [APIError.server(status: 500, reason: nil), APIError.server(status: 502, reason: nil),
                                 APIError.server(status: 504, reason: nil), APIError(kind: .transport, message: "网络中断")]
    for failure in failures {
        let source = FakeCreateSource(), keys = KeyMaker()
        source.creates = [.failure(failure)]
        let flow = submission(source, keys)
        await flow.submit(createRequest())
        #expect(source.sentLookups.count == 1 && flow.stage == .notCreated)
    }
}

@MainActor @Test func resultsOfAnEndedSessionAreDropped() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.creates = [.success(try newAccount(schedulable: true))]
    source.endSessionDuringCreate = true
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(flow.stage == .creating(confirming: false) && flow.account == nil && source.sentPauses.isEmpty && source.sentLookups.isEmpty)

    let cancelled = FakeCreateSource()
    cancelled.creates = [.failure(CancellationError())]
    let other = submission(cancelled, keys)
    await other.submit(createRequest())
    #expect(other.stage == .idle && cancelled.sentLookups.isEmpty)
}

@MainActor @Test func createWithReadOnlyTokenSendsNothing() async throws {
    let source = FakeCreateSource(), keys = KeyMaker()
    source.accountCreateSession = AccountCreateSession(generation: UUID(), idempotentWrites: true, mixedChannelDetails: true, isReadOnlyToken: true)
    let flow = submission(source, keys)
    await flow.submit(createRequest())
    #expect(source.sentCreates.isEmpty && keys.made.isEmpty && flow.stage == .idle)
}

@Test func failureClassificationTable() {
    let warning = MixedChannelWarning(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic", otherPlatform: "Antigravity")
    let legacy = mixedConflict(metadata: nil)
    let rows: [(any Error, Bool, AccountNewSubmission.Failure)] = [
        (CancellationError(), true, .cancelled),
        (KeyedWriteFailure(disposition: .needsNewKey(.invalid), key: "k", actionID: nil, lastError: nil), false,
         .needsNewKey(KeyedWriteFailure(disposition: .needsNewKey(.invalid), key: "k", actionID: nil, lastError: nil).localizedDescription)),
        (unconfirmedFailure, false, .unconfirmed),
        (APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled), false, .cancelled),
        (mixedConflict(metadata: highGroupMetadata), true, .mixedChannel(warning)),
        (legacy, true, .mixedChannelWithoutDetails(legacy.localizedDescription)),
        (legacy, false, .rejected(AccountActionCopy.reason(for: legacy))),
        (APIError.server(status: 400, reason: nil), true, .rejected(AccountActionCopy.reason(for: APIError.server(status: 400, reason: nil)))),
        (APIError.server(status: 408, reason: nil), false, .unconfirmed),
        (APIError.server(status: 409, reason: "OTHER"), true, .rejected(AccountActionCopy.reason(for: APIError.server(status: 409, reason: "OTHER")))),
        (APIError.server(status: 429, reason: nil), false, .rejected(AccountActionCopy.reason(for: APIError.server(status: 429, reason: nil)))),
        (APIError.server(status: 500, reason: nil), false, .unconfirmed),
        (APIError.server(status: 502, reason: nil), false, .unconfirmed),
        (APIError(kind: .transport, message: "网络中断"), false, .unconfirmed),
        (APIError.refreshDeferred, false, .rejected(APIError.refreshDeferred.localizedDescription)),
        (APIError(kind: .validation, message: "请输入账号名称"), false, .rejected("请输入账号名称"))
    ]
    for (error, mixedPlatform, expected) in rows {
        #expect(AccountNewSubmission.failure(of: error, mixedPlatform: mixedPlatform) == expected, "\(error)")
    }
    let passed = APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED").withSecurityOutcome(.passed)
    #expect(AccountNewSubmission.failure(of: passed, mixedPlatform: false) == .reconfirm(passed.localizedDescription))
}
