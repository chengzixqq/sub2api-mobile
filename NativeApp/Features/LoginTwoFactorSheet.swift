import SwiftUI
import Sub2Core

/// 00 §1.4 step 3: the bottom sheet of the password login. Six digits submit themselves; a swipe down is 取消.
struct LoginTwoFactorSheet: View {
    @Bindable var controller: LoginController
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(instruction).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                TextField("6 位验证码", text: $controller.code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .font(.title2.weight(.semibold).monospacedDigit()).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(controller.twoFactorNotice == nil ? Palette.hairline : Tone.critical.base))
                    .focused($focused).disabled(controller.isBusy)
                    .accessibilityLabel("6 位验证码").accessibilityIdentifier("login.totp")
                if let notice = controller.twoFactorNotice {
                    Text(notice).font(.footnote).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("login.totp.error")
                } else {
                    Text("填满 6 位自动提交").font(.footnote).foregroundStyle(Palette.ink3)
                }
                if controller.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.sheetBackground)
            .navigationTitle("两步验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { controller.cancelTwoFactor() }.accessibilityIdentifier("login.totp.cancel")
                }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: controller.code) { Task { await controller.codeDidChange() } }
        .onAppear { focused = true }
    }

    private var instruction: String {
        let action = "输入身份验证器里的 6 位验证码"
        guard let masked = controller.challenge?.maskedEmail, !masked.isEmpty else { return action }
        return "\(masked) · \(action)"
    }
}
