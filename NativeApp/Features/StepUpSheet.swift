import SwiftUI
import Sub2Core

/// 00 §2.6.2 and design UeStepUpSheet: six boxes over a one-time-code field that submits when full, or the notice that
/// TOTP must be turned on in Web, with only “知道了”. Shown by SecurityPromptPresenter.
struct StepUpSheet: View {
    let prompt: SecurityPromptCenter.Prompt
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    /// After TOTP_TOO_MANY_ATTEMPTS: the text stays and only “关闭” is left.
    @State private var locked = false
    @State private var showsNotice: Bool
    @FocusState private var focused: Bool

    init(prompt: SecurityPromptCenter.Prompt) {
        self.prompt = prompt
        _showsNotice = State(initialValue: prompt.kind == .stepUpNoTOTP)
    }

    var body: some View {
        NavigationStack {
            Group { if showsNotice { notice } else { entry } }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Palette.sheetBackground)
                .navigationTitle("二次验证")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(showsNotice || locked ? "关闭" : "取消") { finish(showsNotice ? .blocked : .cancelled) }
                            .disabled(busy).accessibilityIdentifier("stepup.cancel")
                    }
                }
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.instruction(purpose: prompt.purpose, isRead: prompt.isRead))
                .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            ZStack {
                HStack(spacing: 8) { ForEach(0..<OneTimeCode.length, id: \.self) { box($0) } }
                    .accessibilityHidden(true)
                // The field covers the boxes so a tap focuses it; its own text and caret are invisible.
                TextField("", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .foregroundStyle(.clear).tint(.clear)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .focused($focused).disabled(locked)
                    .accessibilityLabel("6 位验证码").accessibilityIdentifier("stepup.code")
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("stepup.error")
            } else {
                Text("填满 6 位自动提交；可以从“密码”App 自动填充。").font(.footnote).foregroundStyle(Palette.ink3)
            }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .onChange(of: code) { _, raw in input(raw) }
        .onAppear { focused = true }
    }

    private var notice: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield").font(.system(size: 26)).foregroundStyle(Tone.caution.base).accessibilityHidden(true)
                Text(StepUpPolicy.totpNotEnabledTitle).font(.headline).foregroundStyle(Palette.ink1)
                Text(Self.noticeBody(purpose: prompt.purpose)).font(.subheadline).foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: .infinity)
            .background(Tone.caution.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button { finish(.blocked) } label: { Text("知道了").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).tint(Palette.accentFill).accessibilityIdentifier("stepup.ack")
        }
    }

    private func box(_ index: Int) -> some View {
        let digits = Array(code)
        let isCurrent = index == digits.count && !locked
        let stroke = error != nil ? Tone.critical.base : isCurrent ? Palette.accent : Palette.hairline
        return Text(index < digits.count ? String(digits[index]) : " ")
            .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, lineWidth: isCurrent || error != nil ? 2 : 1))
    }

    private func input(_ raw: String) {
        let clean = OneTimeCode.sanitize(raw)
        guard clean == raw else { code = clean; return }
        if !clean.isEmpty { error = nil }
        guard OneTimeCode.isComplete(clean), !busy, !locked else { return }
        Task { await submit(clean) }
    }
    private func submit(_ value: String) async {
        busy = true; defer { busy = false }
        do { try await model.verifyStepUp(code: value, prompt: prompt) }
        catch {
            switch StepUpFailure(error) {
            case .retype(let text): code = ""; self.error = text; focused = true
            case .keep(let text): self.error = text
            case .close(let text): code = ""; self.error = text; locked = true; focused = false
            case .totpNotEnabled: self.error = nil; showsNotice = true
            case .sessionEnded: finish(.cancelled)
            }
        }
    }
    private func finish(_ outcome: SecurityPromptOutcome) { model.securityPrompts.complete(prompt.id, outcome: outcome) }

    static func instruction(purpose: String?, isRead: Bool) -> String {
        let after = isRead ? "验证通过后自动继续。" : "验证通过后还要再确认一次。"
        guard let purpose, !purpose.isEmpty else { return "继续之前，输入身份验证器里的 6 位验证码。" + after }
        return "\(purpose)前，输入身份验证器里的 6 位验证码。" + after
    }
    static func noticeBody(purpose: String?) -> String {
        let what = purpose.flatMap { $0.isEmpty ? nil : "\($0)需要输入身份验证器里的验证码。" } ?? "这个操作需要输入身份验证器里的验证码。"
        return what + "你的账号还没开启二次验证，请先在 Web 端「个人资料」里启用，再回来操作。"
    }
}
