import SwiftUI
import Sub2Core

/// C-4, the big-number keypad (design `KeypadSheet` .kp-pad, 30 §3.3): only the 3 × 4 keys, 1–9, “.”, 0 and delete. Every
/// key goes through KeypadInput.apply, so the limits are the caller's numbers and the rules are S0-18's; the large amount,
/// the preview line and any “全部余额” capsule are the caller's. With no decimals the “.” place is left blank, as on the
/// system number pad. Identifiers: “<prefix>.pad”, “<prefix>.key.0”…“9”, “.key.dot”, “.key.delete”. A disabled parent
/// (while submitting) disables every key.
struct AmountKeypad: View {
    @Binding var text: String
    let maxDigits: Int
    let maxFractionDigits: Int
    let maximum: Decimal?
    let identifierPrefix: String

    init(text: Binding<String>, maxDigits: Int, maxFractionDigits: Int, maximum: Decimal? = nil, identifierPrefix: String = "keypad") {
        _text = text
        self.maxDigits = maxDigits
        self.maxFractionDigits = maxFractionDigits
        self.maximum = maximum
        self.identifierPrefix = identifierPrefix
    }

    fileprivate static let keyHeight: CGFloat = 54
    fileprivate static let cornerRadius: CGFloat = 14
    private static let spacing: CGFloat = 6

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 3), spacing: Self.spacing) {
            ForEach(KeypadKey.pad, id: \.self) { cell($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).pad")
    }

    @ViewBuilder private func cell(_ key: KeypadKey) -> some View {
        if key == .decimalPoint && maxFractionDigits == 0 {
            Color.clear.frame(maxWidth: .infinity, minHeight: Self.keyHeight).accessibilityHidden(true)
        } else {
            Button {
                text = KeypadInput.apply(key, to: text, maxDigits: maxDigits, maxFractionDigits: maxFractionDigits, maximum: maximum)
            } label: {
                KeypadKeyFace(key: key)
            }
            .buttonStyle(KeypadKeyStyle())
            .accessibilityLabel(key.spokenLabel)
            .accessibilityIdentifier("\(identifierPrefix).key.\(key.identifierToken)")
        }
    }
}

private struct KeypadKeyFace: View {
    let key: KeypadKey
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if key == .delete { Image(systemName: "delete.left").font(.system(size: 22, weight: .medium)) }
            else { Text(key.glyph).font(.system(size: 26, weight: .medium)).monospacedDigit() }
        }
        .foregroundStyle(isEnabled ? Palette.ink1 : Palette.ink3)
        .frame(maxWidth: .infinity, minHeight: AmountKeypad.keyHeight)
    }
}

/// Pressed: the sunken fill of the design's `.kp-key:active`.
private struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AmountKeypad.cornerRadius, style: .continuous)
        configuration.label
            .background(configuration.isPressed ? Palette.sunken : Color.clear, in: shape)
            .contentShape(shape)
    }
}

fileprivate extension KeypadKey {
    var glyph: String {
        switch self {
        case .digit(let digit): "\(digit)"
        case .decimalPoint: "."
        case .delete, .clear: ""
        }
    }
    var identifierToken: String {
        switch self {
        case .digit(let digit): "\(digit)"
        case .decimalPoint: "dot"
        case .delete: "delete"
        case .clear: "clear"
        }
    }
    var spokenLabel: String {
        switch self {
        case .digit(let digit): "\(digit)"
        case .decimalPoint: "小数点"
        case .delete: "删除"
        case .clear: "清空"
        }
    }
}
