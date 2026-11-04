import SwiftUI
import Sub2Core

// 60 §19.3, design VmoGrantSheet: the step bar, the subject bar, the three steps and the Face ID overlay of the compensation
// sheet. They read RedeemGrantModel and change it only through its methods, so nothing changes while a request is out.

/// “类型 · 数值 · 备注”; VoiceOver reads “第 2 步，共 3 步”.
struct GrantStepBar: View {
    let step: GrantStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GrantStep.allCases, id: \.self) { item in
                HStack(spacing: 6) {
                    Circle().fill(color(item)).frame(width: 7, height: 7)
                    Text(GrantStep.barTitles[item.rawValue - 1]).font(.footnote.weight(item == step ? .semibold : .regular))
                }
                .foregroundStyle(color(item))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.spokenPosition)
        .accessibilityValue(GrantStep.barTitles[step.rawValue - 1])
        .accessibilityIdentifier("grant.steps")
    }

    private func color(_ item: GrantStep) -> Color {
        item == step ? Palette.accent : item.rawValue < step.rawValue ? Palette.ink2 : Palette.ink3
    }
}

/// “<头像> 王小明 · <随步骤的第二段>”, with the neutral “禁用” badge for a disabled user.
struct GrantSubjectBar: View {
    let user: AdminUser
    let line: String

    var body: some View {
        HStack(spacing: 8) {
            UserInitialAvatar(initial: UserPresentation.initial(user.displayName), size: 30)
            Text(user.displayName + " · " + line).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
            Spacer(minLength: 0)
            if user.status == "disabled" { ToneBadge(text: RedeemGrantPresentation.disabledBadge, tone: .neutral) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("grant.subject")
    }
}

// MARK: 第 1 步

/// Three tiles; one that may not be granted is grey with its reason (U52); tapping one goes on to step 2.
struct GrantTypeStep: View {
    let availability: GrantAvailability
    let choose: (CompensationType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CompensationType.allCases, id: \.self) { tile($0) }
                GrantFootnote(text: RedeemGrantPresentation.typeFootnote)
            }
            .padding(16)
        }
    }

    private func tile(_ type: CompensationType) -> some View {
        let reason = availability.reason(for: type)
        return Button { choose(type) } label: {
            HStack(spacing: 12) {
                Image(systemName: type.grantSymbol).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(reason == nil ? Palette.accent : Palette.ink3)
                    .frame(width: 34, height: 34).background(reason == nil ? Palette.accentWash : Palette.sunken, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.grantLabel).font(.headline).foregroundStyle(reason == nil ? Palette.ink1 : Palette.ink3)
                    Text(reason ?? type.grantHint).font(.footnote).foregroundStyle(reason == nil ? Palette.ink2 : Palette.ink3)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if reason == nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(type.grantLabel)
        .accessibilityValue(reason ?? type.grantHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("grant.type.\(type.rawValue)")
    }
}

private extension CompensationType {
    var grantSymbol: String {
        switch self {
        case .balance: "dollarsign"
        case .concurrency: "gauge.with.dots.needle.67percent"
        case .subscription: "rectangle.3.group"
        }
    }
}

// MARK: 第 2 步

/// Balance on the big keypad (7 digits, 2 decimals, no default), concurrency 1–50, or a subscription group and its days.
struct GrantValueStep: View {
    let state: RedeemGrantModel
    let groups: [AdminGroup]
    let now: Date
    let timeZone: TimeZone

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch state.type {
                case .balance?: balance
                case .concurrency?: concurrency
                case .subscription?: subscription
                case nil: EmptyView()
                }
                if let notice = state.notice { MoneyPendingNotice(text: notice, tone: .caution, identifier: "grant.notice") }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            GrantBottomBar {
                Button { state.advance(groups: groups) } label: { Text("下一步").font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(state.draft(groups: groups) == nil)
                    .accessibilityIdentifier("grant.next")
            }
        }
    }

    private var balance: some View {
        let preview = BalanceGrantPreview(text: state.amountText, balance: state.user.balance)
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(preview.amountText)
                    .font(.system(size: 56, weight: .medium)).monospacedDigit()
                    .foregroundStyle(preview.isPlaceholder ? Palette.ink3 : Palette.ink1)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityIdentifier("grant.amount")
                HStack(spacing: 4) {
                    if let after = preview.after {
                        Text("发放后余额")
                        Text(after).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
                    } else {
                        Text(preview.line)
                    }
                }
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("grant.preview")
            }
            .frame(maxWidth: .infinity)
            AmountKeypad(text: Binding(get: { state.amountText }, set: { state.editAmount($0) }), maxDigits: BalanceGrantPreview.maxDigits,
                         maxFractionDigits: BalanceGrantPreview.maxFractionDigits, identifierPrefix: "grant.keypad")
        }
    }

    private var concurrency: some View {
        let change = GrantSummary(draft: RedeemGrantDraft(value: .concurrency(state.concurrency)), user: state.user, groupName: nil, plan: nil,
                                  now: now, timeZone: timeZone).change
        return VStack(alignment: .leading, spacing: 8) {
            GrantCard {
                Stepper(value: Binding(get: { state.concurrency }, set: { state.setConcurrency($0) }), in: RedeemGrantDraft.concurrencyRange) {
                    HStack {
                        Text(RedeemGrantPresentation.concurrencyLabel)
                        Spacer(minLength: 8)
                        Text("+\(state.concurrency)").monospacedDigit().foregroundStyle(Palette.ink2)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("grant.concurrency")
            }
            GrantFootnote(text: RedeemGrantPresentation.concurrencyFootnote(change: change), identifier: "grant.concurrency.footnote")
        }
    }

    @ViewBuilder private var subscription: some View {
        GrantCard(title: "订阅分组") {
            if groups.isEmpty {
                Text(GrantAvailability.noSubscriptionGroups).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                let selected = state.selectedGroup(in: groups)?.id
                ListFieldFlow(spacing: 8) {
                    ForEach(groups) { group in
                        GrantChip(title: group.name, isOn: selected == group.id) { state.selectGroup(group.id) }
                            .accessibilityIdentifier("grant.group.\(group.id)")
                    }
                }
            }
        }
        GrantCard(title: "有效天数") {
            ListFieldFlow(spacing: 8) {
                ForEach(RedeemSubscriptionDaysChoice.options, id: \.self) { choice in
                    GrantChip(title: choice.title, isOn: state.days == choice) { state.chooseDays(choice) }
                        .accessibilityIdentifier("grant.days.\(choice.identifier)")
                }
            }
            if state.days == .custom {
                HStack(spacing: 8) {
                    TextField(RedeemGenerateWizard.customDaysPlaceholder, text: Binding(get: { state.customDaysText }, set: { state.editCustomDays($0) }))
                        .keyboardType(.numberPad).monospacedDigit()
                        .accessibilityLabel("天数")
                        .accessibilityIdentifier("grant.days.field")
                    Text("天").foregroundStyle(Palette.ink2)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        GrantFootnote(text: RedeemGrantPresentation.groupsFootnote)
        if let line = planLine { GrantFootnote(text: line, identifier: "grant.plan") }
    }

    /// The plan's sentence, the line when the subscriptions cannot be read, nothing while they load.
    private var planLine: String? {
        switch state.subscriptions {
        case .failed: return RedeemGrantCopy.subscriptionsUnavailableNote
        case .idle, .loading: return nil
        case .loaded: return state.plan(groups: groups, now: now, timeZone: timeZone).map { RedeemGrantCopy.planNote($0, now: now, timeZone: timeZone) }
        }
    }
}

// MARK: 第 3 步

/// 备注, the receipt (the code's last four only), the balance's rebate note, the Face ID line and 发放 ….
struct GrantNoteStep: View {
    let state: RedeemGrantModel
    let groups: [AdminGroup]
    let now: Date
    let timeZone: TimeZone
    let submit: () -> Void
    @Environment(AppModel.self) private var model
    @FocusState private var notesFocused: Bool

    var body: some View {
        let summary = state.summary(groups: groups, now: now, timeZone: timeZone)
        ScrollView {
            VStack(spacing: 14) {
                GrantCard(title: "备注") {
                    TextField(RedeemGrantPresentation.notesPlaceholder, text: Binding(get: { state.notes }, set: { state.editNotes($0) }), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($notesFocused)
                        .frame(minHeight: 44)
                        .disabled(state.isWorking)
                        .accessibilityLabel("备注")
                        .accessibilityIdentifier("grant.notes")
                }
                GrantFootnote(text: RedeemGrantPresentation.notesFootnote)
                if let summary {
                    MoneyPendingReceipt(lines: receiptLines(summary))
                    if summary.isMoney { GrantFootnote(text: RedeemGrantCopy.rebateFootnote, identifier: "grant.rebate") }
                    if summary.isMoney, let line = model.biometricGate.amountConfirmationLine(amount: summary.amount) {
                        Label(line, systemImage: "faceid").font(.footnote).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("grant.faceid.note")
                    }
                }
                if let notice = state.notice { MoneyPendingNotice(text: notice, tone: .caution, identifier: "grant.notice") }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { submitArea(summary) }
    }

    private func receiptLines(_ summary: GrantSummary) -> [MoneyReceiptLine] {
        let ids = ["对象": "user", "站点": "site", "类型": "type", "数值": "value", "变化": "change", "兑换码": "code", "发放": "amount"]
        let rows = RedeemGrantCopy.receiptRows(summary, user: state.user, siteName: model.activeProfile?.name ?? "", code: state.draftState.code)
        return rows.map { MoneyReceiptLine(id: ids[$0.label] ?? $0.label, label: $0.label, value: $0.value) }
    }

    /// 60 §19.5: “正在发放…” while it runs, “正在等待服务器结果… 已等待 N 秒” while the server holds it, “稍后核对” once saved.
    private func submitArea(_ summary: GrantSummary?) -> some View {
        GrantBottomBar {
            Button { notesFocused = false; submit() } label: {
                HStack(spacing: 8) {
                    if state.isWorking { ProgressView() }
                    Text(state.isWorking ? RedeemGrantPresentation.sendingTitle : summary?.submitTitle ?? "发放")
                }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(state.isWorking || summary == nil)
            .accessibilityIdentifier("grant.submit")
            .readOnlyGate()
            if let progress = state.progress, progress != .submitting {
                Text([progress.title, progress.detail].compactMap { $0 }.joined(separator: " "))
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("grant.waiting")
            }
            if state.isWorking, state.progress != nil {
                Button(BalanceChangeCopy.later) { state.later() }.frame(minHeight: 44).accessibilityIdentifier("grant.later")
            }
        }
    }
}

/// 60 §19.5: “Face ID · 验证后发放” over the sheet while the check runs.
struct GrantFaceIDOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "faceid").font(.system(size: 48, weight: .regular)).foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text("Face ID").font(.headline).foregroundStyle(Palette.ink1)
            Text(RedeemGrantPresentation.faceIDDetail).font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("grant.faceid.overlay")
    }
}

// MARK: Parts

/// A white card with an optional small title (design `.vmo-fsec`).
private struct GrantCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2).accessibilityAddTraits(.isHeader) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GrantFootnote: View {
    let text: String
    var identifier = "grant.footnote"

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}

/// The primary button pinned under the step.
private struct GrantBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Palette.sheetBackground)
    }
}

/// A selectable capsule (design `VmoChoice`); 44pt to tap.
private struct GrantChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(isOn ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(isOn ? Palette.accent : Palette.ink1)
                .padding(.horizontal, 12)
                .frame(minWidth: 36, minHeight: 34)
                .background(isOn ? Palette.accentWash : Palette.sunken, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Palette.accent : Palette.hairline))
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
