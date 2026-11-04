import SwiftUI
import UIKit
import Sub2Core

// Vernier graphite tokens, copied from docs/ui-reassessment-claude-20261016/html-preview/shared/vernier-palette.css
// (.pal-vernier.light / .dark) as listed in 00 §8.2. Change colours only here, one
// `static let name = Color.vernier(light: 0xRRGGBB, dark: 0xRRGGBB)` per line: PaletteParityTests compares these lines with the CSS.
enum Palette {
    // 8.2.1 base
    static let canvas = Color.vernier(light: 0xF1F3F4, dark: 0x0B0E10)
    static let surface = Color.vernier(light: 0xFFFFFF, dark: 0x15191C)
    static let sheetBackground = Color.vernier(light: 0xF1F3F4, dark: 0x15191C)
    static let sunken = Color.vernier(light: 0xEBEEF0, dark: 0x1E2327)
    static let segmentOn = Color.vernier(light: 0xFFFFFF, dark: 0x2B3237)
    static let hairline = Color.vernier(light: 0xD8DDE0, dark: 0x2B3237)
    static let ruleStrong = Color.vernier(light: 0x7F898F, dark: 0x606A71)
    static let ink1 = Color.vernier(light: 0x14181B, dark: 0xE7EBED)
    static let ink2 = Color.vernier(light: 0x4A545A, dark: 0xA8B1B7)
    static let ink3 = Color.vernier(light: 0x5E686F, dark: 0x8B959C)
    static let accent = Color.vernier(light: 0x0B6E85, dark: 0x52CBE6)
    static let accentFill = Color.vernier(light: 0x0B6E85, dark: 0x127A91)
    static let onAccent = Color.vernier(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let accentWash = Color.vernier(light: 0xE2F1F4, dark: 0x203940)

    // 8.2.2 tones: `tone` for dots, icons and capsules, `ink` for text, `wash` for badge and banner backgrounds
    static let ok = Color.vernier(light: 0x288F48, dark: 0x45BE68)
    static let okInk = Color.vernier(light: 0x1B7339, dark: 0x5BCF7E)
    static let okWash = Color.vernier(light: 0xE5F2E9, dark: 0x1E372A)
    static let caution = Color.vernier(light: 0xB87D00, dark: 0xF0B93C)
    static let cautionInk = Color.vernier(light: 0x875200, dark: 0xF5C04F)
    static let cautionWash = Color.vernier(light: 0xF6EFE0, dark: 0x3C3622)
    static let critical = Color.vernier(light: 0xB42318, dark: 0xE5483D)
    static let criticalInk = Color.vernier(light: 0xA61D15, dark: 0xFF7468)
    static let criticalWash = Color.vernier(light: 0xF6E5E3, dark: 0x3A2122)
    static let neutral = Color.vernier(light: 0x7D878D, dark: 0x6E7980)
    static let neutralInk = Color.vernier(light: 0x596369, dark: 0x9CA6AC)
    static let neutralWash = Color.vernier(light: 0xEFF1F1, dark: 0x252A2E)
    static let model = Color.vernier(light: 0x8559E0, dark: 0x9C7CF2)
    static let modelInk = Color.vernier(light: 0x6A3DC2, dark: 0xBBA0FF)
    static let modelWash = Color.vernier(light: 0xF0EBFB, dark: 0x2D2B43)

    // 8.2.3 measures and charts
    static let legendActual = Color.vernier(light: 0x288F48, dark: 0x45BE68)
    static let legendCost = Color.vernier(light: 0xCF5F17, dark: 0xEB8840)
    static let legendStandard = Color.vernier(light: 0x7D878D, dark: 0x6E7980)
    static let chartMain = Color.vernier(light: 0x14181B, dark: 0xE7EBED)
    static let chartBarNow = Color.vernier(light: 0x14181B, dark: 0xE7EBED)
    static let chartCompare = Color.vernier(light: 0x7F898F, dark: 0x606A71)
    static let chartBar = Color.vernier(light: 0x7F898F, dark: 0x606A71)
}

extension Tone {
    var base: Color {
        switch self {
        case .ok: Palette.ok
        case .caution: Palette.caution
        case .critical: Palette.critical
        case .neutral: Palette.neutral
        case .model: Palette.model
        }
    }
    var ink: Color {
        switch self {
        case .ok: Palette.okInk
        case .caution: Palette.cautionInk
        case .critical: Palette.criticalInk
        case .neutral: Palette.neutralInk
        case .model: Palette.modelInk
        }
    }
    var wash: Color {
        switch self {
        case .ok: Palette.okWash
        case .caution: Palette.cautionWash
        case .critical: Palette.criticalWash
        case .neutral: Palette.neutralWash
        case .model: Palette.modelWash
        }
    }
}

private extension Color {
    static func vernier(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
