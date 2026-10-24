import SwiftUI
import Sub2Core

/// 60 §3.4 金额门槛: whole dollars 1–100,000 in large type on the number pad (D22: S0-18 moves the key filter to KeypadInput,
/// keeping these identifiers). Raising the threshold is verified first (D36); a failed check keeps the sheet and the old value.
struct FaceIDThresholdSheet: View {
    let gate: BiometricGate
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @FocusState private var focused: Bool

    init(gate: BiometricGate) {
        self.gate = gate
        _text = State(initialValue: AppPreferences.thresholdText(gate.preferences.faceIDThreshold))
    }

    private var value: Decimal? { AppPreferences.parseThreshold(text) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("$").font(.system(size: 40, weight: .semibold)).foregroundStyle(Palette.ink2)
                    TextField("100", text: $text)
                        .keyboardType(.numberPad)
                        .font(.system(size: 56, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Palette.ink1)
                        .fixedSize()
                        .focused($focused)
                        .accessibilityLabel(SettingsPresentation.thresholdTitle)
                        .accessibilityIdentifier("settings.threshold.field")
                }
                .frame(maxWidth: .infinity)
                Text("整数美元，1 至 100,000。单笔或合计超过这个金额时验证；提高门槛前先验证一次。")
                    .font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 24)
            .navigationTitle(SettingsPresentation.thresholdTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(value == nil || saving).accessibilityIdentifier("settings.threshold.save")
                }
            }
            .onChange(of: text) { _, new in
                let digits = String(new.filter { $0.isASCII && $0.isWholeNumber }.prefix(AppPreferences.faceIDThresholdMaxDigits))
                if digits != new { text = digits }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(saving)
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
