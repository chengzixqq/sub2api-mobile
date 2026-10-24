import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
import Sub2Core

/// Face ID, Touch ID or, failing those, the lock screen code (60 §0.4: `LAPolicy.deviceOwnerAuthentication`). A failed or
/// cancelled check is `false`, never an error: callers keep the old value and say nothing (60 §3.4).
protocol BiometricAuthenticating: Sendable {
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async -> Bool
}

/// A new LAContext for every call; it is never kept or handed across isolation domains.
struct SystemBiometricAuthenticator: BiometricAuthenticating {
    func canAuthenticate() -> Bool {
        #if canImport(LocalAuthentication)
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #else
        return false
        #endif
    }
    func authenticate(reason: String) async -> Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
        #else
        return false
        #endif
    }
}

/// UI tests and unit tests: never shows the system prompt.
struct FixedBiometricAuthenticator: BiometricAuthenticating {
    let isAvailable: Bool
    let succeeds: Bool
    func canAuthenticate() -> Bool { isAvailable }
    func authenticate(reason: String) async -> Bool { isAvailable && succeeds }
}

/// 60 §3.4 Face ID 覆盖清单, the App's only list (R16): pages name what they are about to do, the gate decides.
enum GatedAction: Sendable, Equatable {
    /// Any object; with the switch on, no name is typed and the button reads “用 Face ID 删除” (60 §0.4).
    case delete
    /// Account batches, batch edits.
    case batch
    /// Replacing an API key, authorising again.
    case replaceCredential
    /// 充值 / 退款: how far the balance moves; nil when that is not known, which is verified whenever the switch is on (D26).
    case balanceAdjustment(Decimal?)
    case initialBalance(Decimal)
    /// Face value × count of balance codes.
    case redeemGeneration(total: Decimal)
    case compensation(Decimal)
    /// Always verified, whatever the switch says (30 §7).
    case revealKey

    /// D26: add and subtract move the balance by the amount; set moves it from the current balance to the amount.
    static func balanceAdjustment(_ operation: BalanceOperation, amount: Decimal, currentBalance: Decimal?) -> GatedAction {
        switch operation {
        case .add, .subtract: .balanceAdjustment(amount)
        case .set: .balanceAdjustment(currentBalance.map { abs($0 - amount) })
        }
    }
    /// What the next set in the same sheet is measured from. A replayed or recovered result is the first run's and may be
    /// stale, so the balance counts as unknown.
    static func balanceAfter(_ outcome: WriteOutcome<AdminUser>) -> Decimal? {
        outcome.replayed || outcome.recovered ? nil : outcome.value.balance
    }

    /// The line under the system prompt.
    var defaultReason: String {
        switch self {
        case .delete: "确认删除"
        case .batch: "确认批量操作"
        case .replaceCredential: "确认更换账号凭据"
        case .balanceAdjustment: "确认充值或退款"
        case .initialBalance: "确认新建用户的初始余额"
        case .redeemGeneration: "确认生成余额兑换码"
        case .compensation: "确认发放余额补偿"
        case .revealKey: "显示完整 Key"
        }
    }
}

/// 60 §0.4: with the switch on a delete is verified instead of typing the object's name.
enum DeleteConfirmation: Sendable, Equatable { case typeName, biometric }

/// The setting “高风险操作需要 Face ID” and its threshold applied to the coverage list (60 §3.4). The stored switch is in
/// force only while the phone can still verify: after the lock screen code is removed the switch shows greyed and nothing is
/// gated, so it can never lock the owner out (the stored value stays for when the code comes back).
@MainActor
struct BiometricGate {
    static let enableReason = "打开高风险操作验证"
    static let disableReason = "关闭高风险操作验证"
    static let raiseThresholdReason = "提高 Face ID 金额门槛"

    let preferences: AppPreferences
    let authenticator: any BiometricAuthenticating

    var isAvailable: Bool { authenticator.canAuthenticate() }
    var isRequirementActive: Bool { preferences.faceIDEnabled && isAvailable }

    /// Strictly above the threshold.
    func needsVerification(amount: Decimal) -> Bool { isRequirementActive && amount > preferences.faceIDThreshold }
    func needsVerification(_ action: GatedAction) -> Bool {
        switch action {
        case .revealKey: true
        case .delete, .batch, .replaceCredential: isRequirementActive
        case .balanceAdjustment(let amount): amount.map(needsVerification(amount:)) ?? isRequirementActive
        case .initialBalance(let amount), .redeemGeneration(let amount), .compensation(let amount): needsVerification(amount: amount)
        }
    }

    /// One check; false without asking when the phone cannot verify.
    func confirm(reason: String) async -> Bool {
        guard isAvailable else { return false }
        return await authenticator.authenticate(reason: reason)
    }
    /// After the page's own confirmation and before anything is saved or sent; true at once when the action needs no check.
    func authorize(_ action: GatedAction, reason: String? = nil) async -> Bool {
        guard needsVerification(action) else { return true }
        return await confirm(reason: reason ?? action.defaultReason)
    }

    /// U48: turning the switch on and turning it off are both verified once; a failed or cancelled check keeps the old value.
    /// True when the stored value is now `enabled`.
    @discardableResult
    func setRequirement(_ enabled: Bool) async -> Bool {
        guard enabled != preferences.faceIDEnabled else { return true }
        guard await confirm(reason: enabled ? Self.enableReason : Self.disableReason) else { return false }
        preferences.storeFaceIDRequirement(enabled)
        return true
    }

    /// D36 (the user's decision of 2026-10-22, beyond 60 §3.4 and U48): a higher threshold lets more through, so it is verified
    /// like the switch; an equal or lower one is not.
    nonisolated static func needsVerificationToChangeThreshold(from current: Decimal, to new: Decimal) -> Bool { new > current }
    /// False, keeping the old value, for an invalid amount or a failed check.
    @discardableResult
    func setThreshold(_ value: Decimal) async -> Bool {
        guard AppPreferences.isValidThreshold(value) else { return false }
        if Self.needsVerificationToChangeThreshold(from: preferences.faceIDThreshold, to: value) {
            guard await confirm(reason: Self.raiseThresholdReason) else { return false }
        }
        return preferences.setFaceIDThreshold(value)
    }

    var deleteConfirmation: DeleteConfirmation { isRequirementActive ? .biometric : .typeName }
    /// 60 §0.4: the whole name, or for redeem codes the last four characters in any case.
    nonisolated static func deleteNameMatches(_ typed: String, expected: String, caseInsensitive: Bool = false) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else { return false }
        return caseInsensitive ? typed.caseInsensitiveCompare(expected) == .orderedSame : typed == expected
    }

    /// 30 §3.4 / §5, 60 §10.3 / §19.4: “超过 $100，确认后验证 Face ID。”, or “合计超过…” for a generated batch.
    func amountConfirmationLine(amount: Decimal, isTotal: Bool = false) -> String? {
        guard needsVerification(amount: amount) else { return nil }
        return (isTotal ? "合计超过 " : "超过 ") + DisplayFormat.money(preferences.faceIDThreshold, digits: 0) + "，确认后验证 Face ID。"
    }
}
