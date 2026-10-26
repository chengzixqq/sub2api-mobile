import SwiftUI
import Sub2Core

/// 00 §1.4 step 3: the bottom sheet of the password login. Six digits submit themselves; a swipe down is 取消, except while
/// the code is checked. During a 429
/// the field is locked and counts down (00 §2.7.2), the login page's timer ends the wait.
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
                    .focused($focused).disabled(controller.isBusy || isCoolingDown)
                    .accessibilityLabel("6 位验证码").accessibilityIdentifier("login.totp")
                if let notice = controller.twoFactorNotice {
                    Text(notice).font(.footnote).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("login.totp.error")
                }
                footnote
                if controller.isBusy { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.sheetBackground)
            .navigationTitle("两步验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A code being checked may already have signed in on the server, so it is not abandoned halfway.
                    Button("取消") { controller.cancelTwoFactor() }.disabled(controller.isBusy).accessibilityIdentifier("login.totp.cancel")
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(controller.isBusy)
        .onChange(of: controller.code) { Task { await controller.codeDidChange() } }
        .onChange(of: isCoolingDown) { if !isCoolingDown { focused = true } }
        .onAppear { focused = true }
    }

    private var isCoolingDown: Bool { controller.cooldownUntil != nil }

    @ViewBuilder private var footnote: some View {
        if isCoolingDown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = controller.cooldownRemaining(at: context.date)
                if remaining > 0 {
                    Text(LoginCopy.cooldownButton(remaining)).font(.footnote).foregroundStyle(Palette.ink3)
                        .accessibilityIdentifier("login.totp.cooldown")
                }
            }
        } else if controller.twoFactorNotice == nil {
            Text("填满 6 位自动提交").font(.footnote).foregroundStyle(Palette.ink3)
        }
    }

    private var instruction: String {
        let action = "输入身份验证器里的 6 位验证码"
        guard let masked = controller.challenge?.maskedEmail, !masked.isEmpty else { return action }
        return "\(masked) · \(action)"
    }
}
