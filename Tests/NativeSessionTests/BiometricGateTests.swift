import Foundation
import Synchronization
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Counts the checks and answers with a fixed result.
final class RecordingAuthenticator: BiometricAuthenticating {
    let isAvailable: Bool
    let succeeds: Bool
    private let reasons = Mutex<[String]>([])
    init(isAvailable: Bool = true, succeeds: Bool = true) { self.isAvailable = isAvailable; self.succeeds = succeeds }
    var calls: Int { reasons.withLock { $0.count } }
    var lastReason: String? { reasons.withLock { $0.last } }
    func canAuthenticate() -> Bool { isAvailable }
    func authenticate(reason: String) async -> Bool {
        reasons.withLock { $0.append(reason) }
        return succeeds
    }
}

@MainActor private func makeGate(enabled: Bool, threshold: Decimal = 100, _ authenticator: RecordingAuthenticator = RecordingAuthenticator(),
                             in scratch: ScratchDefaults) -> BiometricGate {
    let preferences = AppPreferences(defaults: scratch.defaults)
    preferences.storeFaceIDRequirement(enabled)
    preferences.setFaceIDThreshold(threshold)
    return BiometricGate(preferences: preferences, authenticator: authenticator)
}

private let cents = Decimal(string: "100.01")!

@MainActor @Test func coverageListMatchesTheSpecTableWhenOn() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let gate = makeGate(enabled: true, in: scratch)
    for action: GatedAction in [.delete, .batch, .replaceCredential, .revealKey] { #expect(gate.needsVerification(action), "\(action)") }
    let amounts: [(Decimal) -> GatedAction] = [{ .balanceAdjustment($0) }, { .initialBalance($0) }, { .redeemGeneration(total: $0) },
                                                { .compensation($0) }]
    for make in amounts {
        #expect(gate.needsVerification(make(100)) == false, "\(make(100))")
        #expect(gate.needsVerification(make(cents)), "\(make(cents))")
    }
    // D26: a set whose distance from the current balance is unknown is always checked.
    #expect(gate.needsVerification(.balanceAdjustment(nil)))
}

@MainActor @Test func onlyRevealKeyIsCheckedWhenOff() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let gate = makeGate(enabled: false, in: scratch)
    for action: GatedAction in [.delete, .batch, .replaceCredential, .balanceAdjustment(1_000_000), .balanceAdjustment(nil),
                                .initialBalance(1_000_000), .redeemGeneration(total: 1_000_000), .compensation(1_000_000)] {
        #expect(gate.needsVerification(action) == false, "\(action)")
    }
    #expect(gate.needsVerification(.revealKey))
    #expect(gate.needsVerification(amount: 1_000_000) == false)
}

@MainActor @Test func amountsCompareStrictlyAboveACustomThreshold() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let gate = makeGate(enabled: true, threshold: 250, in: scratch)
    #expect(gate.needsVerification(amount: 250) == false)
    #expect(gate.needsVerification(amount: 251))
}

@Test func balanceAdjustmentMeasuresHowFarTheBalanceMoves() {
    #expect(GatedAction.balanceAdjustment(.add, amount: 150, currentBalance: 10) == .balanceAdjustment(150))
    #expect(GatedAction.balanceAdjustment(.subtract, amount: 150, currentBalance: 10) == .balanceAdjustment(150))
    // Setting 0 refunds the whole balance; setting 20 on 500 takes 480 away.
    #expect(GatedAction.balanceAdjustment(.set, amount: 0, currentBalance: 500) == .balanceAdjustment(500))
    #expect(GatedAction.balanceAdjustment(.set, amount: 20, currentBalance: 500) == .balanceAdjustment(480))
    #expect(GatedAction.balanceAdjustment(.set, amount: 520, currentBalance: 500) == .balanceAdjustment(20))
    #expect(GatedAction.balanceAdjustment(.set, amount: 20, currentBalance: nil) == .balanceAdjustment(nil))
}

@MainActor @Test func aSetLaterInTheSameSheetIsMeasuredFromWhatTheLastWriteLeft() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let gate = makeGate(enabled: true, in: scratch)
    // Opened at $10, 增加 $500 succeeded with $510: 设置为 0 now refunds $510, not the $10 the sheet opened with.
    let user = AdminUser(id: 7, email: "user@example.com", balance: 510)
    let after = GatedAction.balanceAfter(WriteOutcome(value: user))
    #expect(after == 510)
    #expect(gate.needsVerification(.balanceAdjustment(.set, amount: 0, currentBalance: after)))
    #expect(gate.needsVerification(.balanceAdjustment(.set, amount: 500, currentBalance: after)) == false)
    // A replayed or recovered result is the first run's and may be stale: unknown, so checked whenever the switch is on.
    #expect(GatedAction.balanceAfter(WriteOutcome(value: user, replayed: true)) == nil)
    #expect(GatedAction.balanceAfter(WriteOutcome(value: user, recovered: true)) == nil)
    #expect(gate.needsVerification(.balanceAdjustment(.set, amount: 505, currentBalance: nil)))
}

@MainActor @Test func turningOnNeedsAnAvailablePhoneAndASuccessfulCheck() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let unavailable = RecordingAuthenticator(isAvailable: false)
    let noDevice = makeGate(enabled: false, unavailable, in: scratch)
    #expect(await noDevice.setRequirement(true) == false)
    #expect(unavailable.calls == 0 && noDevice.preferences.faceIDEnabled == false)

    let denying = RecordingAuthenticator(succeeds: false)
    let denied = makeGate(enabled: false, denying, in: scratch)
    #expect(await denied.setRequirement(true) == false)
    #expect(denying.calls == 1 && denied.preferences.faceIDEnabled == false)

    let passing = RecordingAuthenticator()
    let passed = makeGate(enabled: false, passing, in: scratch)
    #expect(await passed.setRequirement(true))
    #expect(passing.calls == 1 && passed.preferences.faceIDEnabled)
    #expect(passing.lastReason == BiometricGate.enableReason)
    #expect(scratch.defaults.object(forKey: "security.faceID.enabled") as? Bool == true)
}

@MainActor @Test func turningOffIsCheckedToo() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let denying = RecordingAuthenticator(succeeds: false)
    let denied = makeGate(enabled: true, denying, in: scratch)
    #expect(await denied.setRequirement(false) == false)
    #expect(denying.calls == 1 && denied.preferences.faceIDEnabled)

    let passing = RecordingAuthenticator()
    let passed = makeGate(enabled: true, passing, in: scratch)
    #expect(await passed.setRequirement(false))
    #expect(passing.calls == 1 && passed.preferences.faceIDEnabled == false)
    #expect(passing.lastReason == BiometricGate.disableReason)
    // Asking for the value it already has checks nothing.
    #expect(await passed.setRequirement(false))
    #expect(passing.calls == 1)
}

@MainActor @Test func authorizeAsksOnlyWhenTheListRequiresIt() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let passing = RecordingAuthenticator()
    let open = makeGate(enabled: true, passing, in: scratch)
    #expect(await open.authorize(.balanceAdjustment(50)))
    #expect(passing.calls == 0)
    #expect(await open.authorize(.balanceAdjustment(150)))
    #expect(passing.calls == 1 && passing.lastReason == GatedAction.balanceAdjustment(150).defaultReason)

    let denying = RecordingAuthenticator(succeeds: false)
    let closed = makeGate(enabled: true, denying, in: scratch)
    #expect(await closed.authorize(.batch) == false)
    #expect(await closed.authorize(.delete, reason: "删除分组「标准」") == false)
    #expect(denying.calls == 2 && denying.lastReason == "删除分组「标准」")
}

@MainActor @Test func anUnavailablePhoneLeavesTheStoredSwitchOutOfForce() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let unavailable = RecordingAuthenticator(isAvailable: false)
    let gate = makeGate(enabled: true, unavailable, in: scratch)
    #expect(gate.preferences.faceIDEnabled)
    #expect(gate.isRequirementActive == false)
    #expect(gate.needsVerification(.delete) == false)
    #expect(gate.needsVerification(amount: 1_000) == false)
    #expect(gate.deleteConfirmation == .typeName)
    #expect(await gate.authorize(.delete))
    // Revealing a key is always checked, and cannot pass without a way to check.
    #expect(gate.needsVerification(.revealKey))
    #expect(await gate.authorize(.revealKey) == false)
    #expect(unavailable.calls == 0)
}

@MainActor @Test func raisingTheThresholdIsCheckedLoweringIsNot() async {
    // D36, the user's decision beyond 60 §3.4.
    #expect(BiometricGate.needsVerificationToChangeThreshold(from: 100, to: 101))
    #expect(BiometricGate.needsVerificationToChangeThreshold(from: 100, to: 100) == false)
    #expect(BiometricGate.needsVerificationToChangeThreshold(from: 100, to: 1) == false)

    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let passing = RecordingAuthenticator()
    let gate = makeGate(enabled: true, threshold: 500, passing, in: scratch)
    #expect(await gate.setThreshold(200))
    #expect(passing.calls == 0 && gate.preferences.faceIDThreshold == 200)
    #expect(await gate.setThreshold(800))
    #expect(passing.calls == 1 && passing.lastReason == BiometricGate.raiseThresholdReason)
    #expect(gate.preferences.faceIDThreshold == 800)
    #expect(await gate.setThreshold(0) == false)
    #expect(passing.calls == 1 && gate.preferences.faceIDThreshold == 800)
}

@MainActor @Test func aFailedCheckKeepsTheLowerThreshold() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let denying = RecordingAuthenticator(succeeds: false)
    let gate = makeGate(enabled: true, threshold: 100, denying, in: scratch)
    #expect(await gate.setThreshold(100_000) == false)
    #expect(denying.calls == 1)
    #expect(gate.preferences.faceIDThreshold == 100)
    #expect(scratch.defaults.string(forKey: "security.faceID.threshold") == "100")
}

@MainActor @Test func deleteConfirmationFollowsTheSwitchAndNamesMatchExactly() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    #expect(makeGate(enabled: true, in: scratch).deleteConfirmation == .biometric)
    #expect(makeGate(enabled: false, in: scratch).deleteConfirmation == .typeName)
    #expect(BiometricGate.deleteNameMatches("分组A", expected: "分组A"))
    #expect(BiometricGate.deleteNameMatches("分组a", expected: "分组A") == false)
    #expect(BiometricGate.deleteNameMatches("分组", expected: "分组A") == false)
    #expect(BiometricGate.deleteNameMatches("", expected: "") == false)
    #expect(BiometricGate.deleteNameMatches("a3f0", expected: "A3F0", caseInsensitive: true))
}

@MainActor @Test func amountConfirmationLineNamesTheThreshold() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let on = makeGate(enabled: true, in: scratch)
    #expect(on.amountConfirmationLine(amount: 150) == "超过 $100，确认后验证 Face ID。")
    #expect(on.amountConfirmationLine(amount: 150, isTotal: true) == "合计超过 $100，确认后验证 Face ID。")
    #expect(on.amountConfirmationLine(amount: 50) == nil)
    #expect(makeGate(enabled: false, in: scratch).amountConfirmationLine(amount: 150) == nil)
    #expect(makeGate(enabled: true, threshold: 100_000, in: scratch).amountConfirmationLine(amount: 100_001) == "超过 $100,000，确认后验证 Face ID。")
}
