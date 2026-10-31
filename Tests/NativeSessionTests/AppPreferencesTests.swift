import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// A private suite per test, removed afterwards.
struct ScratchDefaults {
    let name = "com.chengzixqq.sub2mobile.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: name)! }
    func remove() { defaults.removePersistentDomain(forName: name) }
}

@MainActor @Test func preferencesDefaultWhenNothingIsStored() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let preferences = AppPreferences(defaults: scratch.defaults)
    #expect(preferences.interfaceMode == .main)
    #expect(preferences.appearance == .system)
    #expect(preferences.faceIDEnabled == false)
    #expect(preferences.faceIDThreshold == 100)
}

@MainActor @Test func preferenceWritesUseTheFourSpecKeys() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let preferences = AppPreferences(defaults: scratch.defaults)
    preferences.setAppearance(.dark)
    #expect(preferences.setFaceIDThreshold(250))
    preferences.storeFaceIDRequirement(true)
    preferences.setInterfaceMode(.main)
    #expect(scratch.defaults.string(forKey: "ui.appearance") == "dark")
    #expect(scratch.defaults.string(forKey: "security.faceID.threshold") == "250")
    #expect(scratch.defaults.object(forKey: "security.faceID.enabled") as? Bool == true)
    #expect(scratch.defaults.string(forKey: "ui.mode") == "main")
    #expect(preferences.appearance == .dark && preferences.faceIDThreshold == 250 && preferences.faceIDEnabled)
}

@MainActor @Test func newPreferencesReadWhatWasStored() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let first = AppPreferences(defaults: scratch.defaults)
    first.setAppearance(.light); first.storeFaceIDRequirement(true); first.setFaceIDThreshold(100_000)
    let second = AppPreferences(defaults: scratch.defaults)
    #expect(second.appearance == .light)
    #expect(second.faceIDEnabled)
    #expect(second.faceIDThreshold == 100_000)
}

@MainActor @Test(arguments: ["abc", "0", "100001", "12.5", "-5", ""])
func unknownStoredThresholdReadsAsDefault(stored: String) {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    scratch.defaults.set(stored, forKey: "security.faceID.threshold")
    #expect(AppPreferences(defaults: scratch.defaults).faceIDThreshold == 100)
}

@MainActor @Test func unknownStoredModeAndAppearanceReadAsDefaults() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    scratch.defaults.set("sepia", forKey: "ui.appearance")
    // U42: a simple mode stored by a later version is not selectable here.
    scratch.defaults.set("simple", forKey: "ui.mode")
    let preferences = AppPreferences(defaults: scratch.defaults)
    #expect(preferences.appearance == .system)
    #expect(preferences.interfaceMode == .main)
    preferences.setInterfaceMode(.simple)
    #expect(preferences.interfaceMode == .main)
    #expect(scratch.defaults.string(forKey: "ui.mode") == "simple")
}

@Test(arguments: [("1", Decimal(1)), ("250", 250), ("100000", 100_000), ("000250", 250)])
func thresholdParsingAcceptsWholeDollars(text: String, expected: Decimal) {
    #expect(AppPreferences.parseThreshold(text) == expected)
}

@Test(arguments: ["0", "100001", "12.5", "-5", "", "1e3", "１２", "1,000", " 12", "1000000"])
func thresholdParsingRefusesEverythingElse(text: String) {
    #expect(AppPreferences.parseThreshold(text) == nil)
}

@MainActor @Test func rejectedThresholdKeepsThePreviousValue() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let preferences = AppPreferences(defaults: scratch.defaults)
    #expect(preferences.setFaceIDThreshold(300))
    for invalid: Decimal in [0, 100_001, Decimal(string: "12.5")!, -5] {
        #expect(preferences.setFaceIDThreshold(invalid) == false)
    }
    #expect(preferences.faceIDThreshold == 300)
    #expect(scratch.defaults.string(forKey: "security.faceID.threshold") == "300")
}

/// S3-16: the threshold sheet's keypad takes its three limits from here, and whatever it can type either saves or is "0".
@Test func thresholdKeypadParametersMatchTheSaveRule() {
    #expect(AppPreferences.faceIDThresholdFractionDigits == 0)
    #expect(AppPreferences.faceIDThresholdMaxDigits == 6)
    #expect(AppPreferences.faceIDThresholdRange.upperBound == 100_000)
    func press(_ keys: [KeypadKey], from text: String = "") -> String {
        keys.reduce(text) { typed, key in
            KeypadInput.apply(key, to: typed, maxDigits: AppPreferences.faceIDThresholdMaxDigits,
                              maxFractionDigits: AppPreferences.faceIDThresholdFractionDigits, maximum: AppPreferences.faceIDThresholdRange.upperBound)
        }
    }
    #expect(press([1, 0, 0, 0, 0, 0, 0].map(KeypadKey.digit)) == "100000")
    #expect(press([9, 9, 9, 9, 9, 9].map(KeypadKey.digit)) == "99999")
    #expect(press([.decimalPoint], from: "12") == "12")
    #expect(press([.digit(0), .digit(5)]) == "5")
    #expect(press([.delete, .delete, .delete], from: "100") == "")
    for typed in ["", "0"] { #expect(AppPreferences.parseThreshold(typed) == nil) }
    for (typed, value) in [("1", Decimal(1)), ("99999", 99_999), ("100000", 100_000)] { #expect(AppPreferences.parseThreshold(typed) == value) }
}
