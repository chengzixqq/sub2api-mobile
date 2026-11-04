import Foundation
import Observation

/// 60 §3.2: settings of this phone, not of a site, so signing out and deleting sites keep them. Every value changes through
/// a setter that writes its key at once; a stored value this version does not know reads as the default.
@MainActor @Observable
final class AppPreferences {
    enum InterfaceMode: String, CaseIterable, Sendable { case main, simple }
    enum Appearance: String, CaseIterable, Sendable { case system, light, dark }
    enum Keys {
        static let interfaceMode = "ui.mode"
        static let appearance = "ui.appearance"
        static let faceIDEnabled = "security.faceID.enabled"
        static let faceIDThreshold = "security.faceID.threshold"
    }
    /// Design `FACE_ID_LIMIT`.
    nonisolated static let defaultFaceIDThreshold: Decimal = 100
    /// Whole dollars (60 §3.4, the keypad rule of 30 §3.7: at most six digits).
    nonisolated static let faceIDThresholdRange: ClosedRange<Decimal> = 1...100_000
    nonisolated static let faceIDThresholdMaxDigits = 6
    /// Whole dollars: the threshold keypad has no “.” (KeypadInput).
    nonisolated static let faceIDThresholdFractionDigits = 0

    private(set) var interfaceMode: InterfaceMode
    private(set) var appearance: Appearance
    /// The stored switch; BiometricGate decides whether it is in force on this phone.
    private(set) var faceIDEnabled: Bool
    private(set) var faceIDThreshold: Decimal
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // U42: the simple mode is not selectable in this version, whatever a later version stored.
        interfaceMode = .main
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        faceIDEnabled = defaults.object(forKey: Keys.faceIDEnabled) as? Bool ?? false
        faceIDThreshold = defaults.string(forKey: Keys.faceIDThreshold).flatMap(Self.parseThreshold) ?? Self.defaultFaceIDThreshold
    }

    func setInterfaceMode(_ mode: InterfaceMode) {
        guard mode == .main else { return }
        interfaceMode = mode
        defaults.set(mode.rawValue, forKey: Keys.interfaceMode)
    }
    func setAppearance(_ appearance: Appearance) {
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
    }
    /// False, keeping the old value, for anything but whole dollars from 1 to 100,000. Raising it is verified first
    /// (BiometricGate.setThreshold).
    @discardableResult
    func setFaceIDThreshold(_ value: Decimal) -> Bool {
        guard Self.isValidThreshold(value) else { return false }
        faceIDThreshold = value
        defaults.set(Self.thresholdText(value), forKey: Keys.faceIDThreshold)
        return true
    }
    /// Only BiometricGate calls this, after the check that turning the switch on or off requires (U48).
    func storeFaceIDRequirement(_ enabled: Bool) {
        faceIDEnabled = enabled
        defaults.set(enabled, forKey: Keys.faceIDEnabled)
    }

    /// Half-width digits only, at most six, 1–100,000; signs, separators, decimals and exponents are refused.
    nonisolated static func parseThreshold(_ text: String) -> Decimal? {
        guard (1...faceIDThresholdMaxDigits).contains(text.utf8.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), faceIDThresholdRange.contains(value) else { return nil }
        return value
    }
    nonisolated static func isValidThreshold(_ value: Decimal) -> Bool { parseThreshold(thresholdText(value)) == value }
    nonisolated static func thresholdText(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}
