import SwiftUI
import Sub2Core

/// `.balanceKeypad(userID:mode:)`: reads the user by id (D26 measures a set from this balance), then shows the keypad in its
/// own NavigationStack, at the large detent (30 §3.1).
struct BalanceKeypadDestination: View {
    let userID: Int
    let mode: BalanceKeypadMode
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var user: AdminUser?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            if let user {
                BalanceKeypadSheet(user: user, mode: mode)
            } else {
                Group {
                    if let failure { FailureView(message: failure) { self.failure = nil; attempt += 1 } }
                    else { ProgressView("正在读取用户…") }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") } }
            }
        }
        .presentationDetents([.large])
        .task(id: attempt) { await load() }
    }

    private func load() async {
        guard user == nil, let session, session.generation == model.sessionGeneration else { return }
        do {
            let result = try await model.user(id: userID)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            user = result
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}

/// 30 §3.3, design `KeypadSheet`: 充值 | 退款, the user, an optional note, the large amount and its preview, “全部余额” for a
/// refund, the keypad (7 digits, 2 decimals) and the submit button. While a write is out the sheet stays (30 §3.5).
struct BalanceKeypadSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keypad: BalanceKeypadModel
    @FocusState private var notesFocused: Bool

    init(user: AdminUser, mode: BalanceKeypadMode) {
        _keypad = State(initialValue: BalanceKeypadModel(user: user, mode: mode))
    }

    var body: some View {
        let draft = keypad.draft, paused = keypad.pausedMessage(model: model)
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Picker("方式", selection: Binding(get: { keypad.mode }, set: { keypad.setMode($0) })) {
                    Text("充值").tag(BalanceKeypadMode.topup)
                    Text("退款").tag(BalanceKeypadMode.refund)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("balance.mode")
                BalanceKeypadUserLine(user: keypad.user)
                notesRow
                amount(draft)
                if draft.direction == .debit, draft.canChooseAllBalance {
                    Button(BalanceChangeCopy.allBalancePill(draft.currentBalance)) { keypad.chooseAllBalance() }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Palette.ink1)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("balance.all")
                }
                Spacer(minLength: 0)
                if let message = paused ?? keypad.notice { noticeText(message, id: paused == nil ? "balance.notice" : "balance.paused") }
                AmountKeypad(text: Binding(get: { keypad.draft.amountText }, set: { keypad.editAmount($0) }),
                             maxDigits: BalanceChangeDraft.maxDigits, maxFractionDigits: BalanceChangeDraft.maxFractionDigits, identifierPrefix: "balance")
            }
            .disabled(keypad.isWorking)
            submitArea(draft, paused: paused != nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .ignoresSafeArea(.keyboard)
        .background(Palette.sheetBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }.disabled(keypad.isWorking).accessibilityIdentifier("sheet.close")
            }
        }
        .interactiveDismissDisabled(keypad.isWorking)
        .alert(keypad.confirmation?.content.title ?? "", isPresented: confirmationShown, presenting: keypad.confirmation) { shown in
            Button(shown.content.confirmTitle, role: .destructive) { keypad.confirm(shown, model: model) }
            Button("取消", role: .cancel) {}
        } message: { shown in
            Text(shown.content.message)
        }
        .onChange(of: keypad.isFinished) { _, finished in if finished { dismiss() } }
        .onChange(of: model.sessionGeneration) { _, _ in dismiss() }
    }

    private var confirmationShown: Binding<Bool> {
        let id = keypad.confirmation?.id
        return Binding(get: { id != nil && keypad.confirmation?.id == id }, set: { if !$0, let id { keypad.dismissConfirmation(id) } })
    }

    private var notesRow: some View {
        HStack(spacing: 10) {
            Text(BalanceChangeCopy.notesLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextField(BalanceChangeCopy.notesPlaceholder, text: Binding(get: { keypad.draft.notes }, set: { keypad.editNotes($0) }))
                .focused($notesFocused)
                .submitLabel(.done)
                .onSubmit { notesFocused = false }
                .accessibilityLabel("备注（可选）")
                .accessibilityIdentifier("balance.notes")
            if !keypad.draft.notes.isEmpty {
                Button { keypad.editNotes("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("清除备注")
                .accessibilityIdentifier("balance.notes.clear")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 44)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func amount(_ draft: BalanceChangeDraft) -> some View {
        VStack(spacing: 4) {
            Text(draft.amountDisplay)
                .font(.system(size: 60, weight: .medium)).monospacedDigit()
                .foregroundStyle(draft.isAmountEmpty ? Palette.ink3 : Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityLabel(Text(draft.amountDisplay))
                .accessibilityIdentifier("balance.amount")
            Text(draft.previewText)
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(draft.exceedsBalance ? Tone.critical.ink : Palette.ink2)
                .accessibilityIdentifier("balance.preview")
        }
    }

    private func noticeText(_ message: String, id: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote).foregroundStyle(Tone.critical.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }

    @ViewBuilder private func submitArea(_ draft: BalanceChangeDraft, paused: Bool) -> some View {
        if keypad.isWorking {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text((keypad.progress ?? .submitting).title)
                    if let detail = keypad.progress?.detail { Text(detail).foregroundStyle(Palette.ink2).monospacedDigit() }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("balance.status")
                if keypad.progress != nil {
                    // Offered once the record is saved: it only stops waiting, the record stays to be checked.
                    Button(BalanceChangeCopy.later) { keypad.later() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("balance.later")
                }
            }
        } else {
            Button { notesFocused = false; keypad.submit(model: model) } label: {
                Text(draft.submitTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!draft.canSubmit || paused)
            .accessibilityIdentifier("balance.submit")
            .readOnlyGate()
        }
    }
}

/// “<头像> 王小明 · 余额 $12.40”, with “已禁用” for a disabled user.
private struct BalanceKeypadUserLine: View {
    let user: AdminUser

    var body: some View {
        HStack(spacing: 8) {
            UserInitialAvatar(initial: UserPresentation.initial(user.displayName), size: 30)
            Text(BalanceChangeCopy.userLine(name: user.displayName, balance: user.balance))
                .font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
                .lineLimit(1)
            if user.status == "disabled" { ToneBadge(text: BalanceChangeCopy.disabledBadge, tone: .neutral) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("balance.user")
    }
}
