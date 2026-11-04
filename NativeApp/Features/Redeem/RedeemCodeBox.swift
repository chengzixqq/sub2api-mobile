import SwiftUI
import Sub2Core

/// 60 §8.3 码值框: two lines of 16, spaced every 4 (layout only, a copy is the raw code), masked until the eye is tapped. The
/// code is never selectable, so it leaves the phone only through the copy button (SensitivePasteboard, `.localOnly`).
/// S6-06 shows generated and reconciled codes with `initiallyRevealed: true`.
struct RedeemCodeBox: View {
    let code: String
    let identifier: String
    let onCopy: () -> Void
    @State private var revealed: Bool

    init(code: String, initiallyRevealed: Bool = false, identifier: String = "redeem.box", onCopy: @escaping () -> Void) {
        self.code = code; self.identifier = identifier; self.onCopy = onCopy
        _revealed = State(initialValue: initiallyRevealed)
    }

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(RedeemPresentation.codeLines(code, revealed: revealed).enumerated()), id: \.offset) { _, groups in
                    Text(groups.joined(separator: " "))
                }
            }
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .foregroundStyle(Palette.ink1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RedeemPresentation.codeSpoken(code, revealed: revealed))
            .accessibilityIdentifier(identifier + ".text")
            iconButton(revealed ? "eye.slash" : "eye", label: revealed ? "隐藏兑换码" : "显示兑换码", id: ".reveal") { revealed.toggle() }
            iconButton("doc.on.doc", label: "复制兑换码", id: ".copy", action: onCopy)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 4))
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(Palette.ink2)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier + id)
    }
}
