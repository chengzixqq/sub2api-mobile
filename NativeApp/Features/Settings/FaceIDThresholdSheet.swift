import SwiftUI
import Sub2Core

/// 60 §3.4 金额门槛: whole dollars 1–100,000 in large type over the AmountKeypad (C-4, S3-16). Every key follows KeypadInput
/// (D22: six digits, no point, a key that would pass 100,000 is refused); saving still checks 1–100,000, and a typed “0”
/// says why it cannot be saved. Raising the threshold is verified first (D36); a failed check keeps the sheet and the old
/// value.
struct FaceIDThresholdSheet: View {
    let gate: BiometricGate
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false

    private static let note = "整数美元，1 至 100,000。单笔或合计超过这个金额时验证；提高门槛前先验证一次。"
    private static let rangeHint = "门槛要在 $1 至 $100,000 之间"

    init(gate: BiometricGate) {
        self.gate = gate
        _text = State(initialValue: AppPreferences.thresholdText(gate.preferences.faceIDThreshold))
    }

    private var value: Decimal? { AppPreferences.parseThreshold(text) }
    private var display: String { DisplayFormat.money(KeypadInput.value(of: text) ?? 0, digits: 0) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                amount
                Text(Self.note)
                    .font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                if !text.isEmpty, value == nil {
                    Text(Self.rangeHint)
                        .font(.footnote).foregroundStyle(Tone.critical.ink)
                        .accessibilityIdentifier("settings.threshold.hint")
                }
                Spacer(minLength: 0)
                AmountKeypad(text: $text, maxDigits: AppPreferences.faceIDThresholdMaxDigits,
                             maxFractionDigits: AppPreferences.faceIDThresholdFractionDigits,
                             maximum: AppPreferences.faceIDThresholdRange.upperBound, identifierPrefix: "settings.threshold")
                    .disabled(saving)
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 8)
            .navigationTitle(SettingsPresentation.thresholdTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(value == nil || saving).accessibilityIdentifier("settings.threshold.save")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
    }

    /// One element for VoiceOver and the UI tests: “金额门槛”, valued “$100,000” or “未输入”.
    private var amount: some View {
        Text(display)
            .font(.system(size: 56, weight: .semibold)).monospacedDigit()
            .foregroundStyle(text.isEmpty ? Palette.ink3 : Palette.ink1)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(SettingsPresentation.thresholdTitle)
            .accessibilityValue(text.isEmpty ? "未输入" : display)
            .accessibilityIdentifier("settings.threshold.field")
    }

    private func save() {
        guard let value, !saving else { return }
        saving = true
        Task {
            let saved = await gate.setThreshold(value)
            saving = false
            if saved { dismiss() }
        }
    }
}
