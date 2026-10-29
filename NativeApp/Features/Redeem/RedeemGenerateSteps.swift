import SwiftUI
import Sub2Core

// 60 §10.3, design VmoGenSteps: the step bar and the three steps of the generate sheet. They read RedeemGenerateModel and change
// it only through `update`, so nothing changes while a request is out.

/// “类型 · 面额与数量 · 有效期”; VoiceOver reads “第 2 步，共 3 步”.
struct RedeemGenerateStepBar: View {
    let step: RedeemGenerateStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RedeemGenerateStep.allCases, id: \.self) { item in
                HStack(spacing: 6) {
                    Circle().fill(color(item)).frame(width: 7, height: 7)
                    Text(RedeemGenerateStep.barTitles[item.rawValue - 1]).font(.footnote.weight(item == step ? .semibold : .regular))
                }
                .foregroundStyle(color(item))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.spokenPosition)
        .accessibilityValue(RedeemGenerateStep.barTitles[step.rawValue - 1])
        .accessibilityIdentifier("redeem.generate.steps")
    }

    private func color(_ item: RedeemGenerateStep) -> Color {
        item == step ? Palette.accent : item.rawValue < step.rawValue ? Palette.ink2 : Palette.ink3
    }
}

// MARK: 第 1 步

/// Four tiles; tapping one goes on to step 2.
struct RedeemTypeStep: View {
    let selected: RedeemCodeType
    let choose: (RedeemCodeType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(RedeemCodeType.allCases, id: \.self) { type in tile(type) }
                }
                RedeemGenerateFootnote(text: RedeemGenerateWizard.typeFootnote)
            }
            .padding(16)
        }
    }

    private func tile(_ type: RedeemCodeType) -> some View {
        let isOn = type == selected
        return Button { choose(type) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: type.generateSymbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.accent)
                    .frame(width: 34, height: 34).background(Palette.accentWash, in: Circle())
                Text(type.label).font(.headline).foregroundStyle(Palette.ink1)
                Text(type.generateHint).font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? Palette.accent : Palette.hairline, lineWidth: isOn ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(type.label)
        .accessibilityHint(type.generateHint)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("redeem.generate.type.\(type.rawValue)")
    }
}

private extension RedeemCodeType {
    var generateSymbol: String {
        switch self {
        case .balance: "dollarsign"
        case .concurrency: "gauge.with.dots.needle.67percent"
        case .subscription: "rectangle.3.group"
        case .invitation: "person.badge.plus"
        }
    }
}

// MARK: 第 2 步

/// The face value by type, then the count; a balance code's value is typed on the big keypad (6 digits, 2 decimals).
struct RedeemValueStep: View {
    let state: RedeemGenerateModel
    let subscriptionGroups: [AdminGroup]

    var body: some View {
        let wizard = state.wizard
        ScrollView {
            VStack(spacing: 14) {
                switch wizard.type {
                case .balance: amount(wizard)
                case .concurrency: concurrency(wizard)
                case .subscription: subscription(wizard)
                case .invitation: RedeemGenerateFootnote(text: RedeemCodeType.invitation.generateHint)
                }
                count(wizard)
                if wizard.type == .balance {
                    AmountKeypad(text: Binding(get: { state.wizard.valueText }, set: { text in state.update { $0.editingValueText(text) } }),
                                 maxDigits: RedeemGenerateWizard.valueMaxDigits, maxFractionDigits: RedeemGenerateWizard.valueMaxFractionDigits,
                                 identifierPrefix: "redeem.generate.keypad")
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            RedeemGenerateBottomBar {
                Button { state.update { $0.advancing(subscriptionGroups: subscriptionGroups) } } label: {
                    Text("下一步").font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!wizard.canAdvance(subscriptionGroups: subscriptionGroups))
                .accessibilityIdentifier("redeem.generate.next")
            }
        }
    }

    private func amount(_ wizard: RedeemGenerateWizard) -> some View {
        VStack(spacing: 4) {
            Text(wizard.amountDisplay)
                .font(.system(size: 56, weight: .medium)).monospacedDigit()
                .foregroundStyle(wizard.isAmountEmpty ? Palette.ink3 : Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("redeem.generate.amount")
            HStack(spacing: 4) {
                Text(RedeemGenerateWizard.previewLabel)
                Text(wizard.previewTotal).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
            }
            .font(.subheadline).foregroundStyle(Palette.ink2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("redeem.generate.preview")
        }
        .frame(maxWidth: .infinity)
    }

    private func concurrency(_ wizard: RedeemGenerateWizard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RedeemGenerateCard {
                Stepper(value: Binding(get: { state.wizard.concurrency }, set: { value in state.update { $0.settingConcurrency(value) } }),
                        in: RedeemGenerateForm.concurrencyRange) {
                    Text(wizard.concurrencyLine).monospacedDigit()
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("redeem.generate.concurrency")
            }
            RedeemGenerateFootnote(text: RedeemCodeType.concurrency.generateHint)
        }
    }

    @ViewBuilder private func subscription(_ wizard: RedeemGenerateWizard) -> some View {
        RedeemGenerateCard(title: "订阅分组") {
            if subscriptionGroups.isEmpty {
                Text(RedeemGenerateWizard.noSubscriptionGroups).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("redeem.generate.noGroups")
            } else {
                let selected = wizard.selectedGroup(in: subscriptionGroups)?.id
                ListFieldFlow(spacing: 8) {
                    ForEach(subscriptionGroups) { group in
                        RedeemGenerateChip(title: group.name, isOn: selected == group.id) { state.update { $0.selectingGroup(id: group.id) } }
                            .accessibilityIdentifier("redeem.generate.group.\(group.id)")
                    }
                }
            }
        }
        RedeemGenerateCard(title: "有效天数") {
            ListFieldFlow(spacing: 8) {
                ForEach(RedeemSubscriptionDaysChoice.options, id: \.self) { choice in
                    RedeemGenerateChip(title: choice.title, isOn: wizard.subscriptionDays == choice) { state.update { $0.choosingSubscriptionDays(choice) } }
                        .accessibilityIdentifier("redeem.generate.days.\(choice.identifier)")
                }
            }
            if wizard.subscriptionDays == .custom {
                RedeemDaysField(text: Binding(get: { state.wizard.customSubscriptionDaysText },
                                              set: { text in state.update { $0.editingCustomSubscriptionDays(text) } }),
                                identifier: "redeem.generate.days.field")
            }
        }
        RedeemGenerateFootnote(text: RedeemCodeType.subscription.generateHint)
    }

    /// The keypad owns the amount, so the count is picked: a stepper and the common counts.
    private func count(_ wizard: RedeemGenerateWizard) -> some View {
        RedeemGenerateCard {
            Stepper(value: Binding(get: { state.wizard.count }, set: { value in state.update { $0.settingCount(value) } }), in: RedeemGenerateForm.countRange) {
                HStack {
                    Text("数量")
                    Spacer(minLength: 8)
                    Text("\(wizard.count) 个").monospacedDigit().foregroundStyle(Palette.ink2)
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("redeem.generate.count")
            ListFieldFlow(spacing: 8) {
                ForEach(RedeemGenerateWizard.countPicks, id: \.self) { pick in
                    RedeemGenerateChip(title: "\(pick) 个", isOn: wizard.count == pick) { state.update { $0.settingCount(pick) } }
                        .accessibilityIdentifier("redeem.generate.count.pick.\(pick)")
                }
            }
        }
    }
}

// MARK: 第 3 步

/// 兑换码过期, 备注 (U45), the receipt, the Face ID line and 生成 N 个兑换码.
struct RedeemExpiryStep: View {
    let state: RedeemGenerateModel
    let subscriptionGroups: [AdminGroup]
    let now: Date
    let timeZone: TimeZone
    let submit: () -> Void
    @Environment(AppModel.self) private var model
    @FocusState private var notesFocused: Bool

    var body: some View {
        let wizard = state.wizard
        let summary = wizard.spec(subscriptionGroups: subscriptionGroups).map { RedeemGenerateSummary(spec: $0, now: now, timeZone: timeZone) }
        ScrollView {
            VStack(spacing: 14) {
                expiry(wizard)
                RedeemGenerateCard(title: "备注") {
                    TextField(RedeemGenerateWizard.notesPlaceholder, text: Binding(get: { state.wizard.notes }, set: { text in state.update { $0.editingNotes(text) } }),
                              axis: .vertical)
                        .lineLimit(1...4)
                        .focused($notesFocused)
                        .frame(minHeight: 44)
                        .accessibilityLabel("备注")
                        .accessibilityIdentifier("redeem.generate.notes")
                }
                if let summary { MoneyPendingReceipt(lines: summary.receiptLines) }
                if let line = wizard.total.flatMap({ model.biometricGate.amountConfirmationLine(amount: $0, isTotal: true) }) {
                    Label(line, systemImage: "faceid").font(.footnote).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("redeem.generate.faceid")
                }
                if let notice = state.notice { MoneyPendingNotice(text: notice, tone: .caution, identifier: "redeem.generate.notice") }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { submitArea(wizard, summary: summary) }
    }

    private func expiry(_ wizard: RedeemGenerateWizard) -> some View {
        RedeemGenerateCard(title: "兑换码过期") {
            ListFieldFlow(spacing: 8) {
                ForEach(RedeemGenerateExpiryChoice.options, id: \.self) { choice in
                    RedeemGenerateChip(title: choice.title, isOn: wizard.expiry == choice) { state.update { $0.choosingExpiry(choice) } }
                        .accessibilityIdentifier("redeem.generate.expiry.\(choice.identifier)")
                }
            }
            if wizard.expiry == .custom {
                RedeemDaysField(text: Binding(get: { state.wizard.customExpiryDaysText }, set: { text in state.update { $0.editingCustomExpiryDays(text) } }),
                                identifier: "redeem.generate.expiry.field")
            }
        }
    }

    /// 60 §10.5: “正在生成…” while it runs; “稍后核对” once the record is saved.
    private func submitArea(_ wizard: RedeemGenerateWizard, summary: RedeemGenerateSummary?) -> some View {
        RedeemGenerateBottomBar {
            Button { notesFocused = false; submit() } label: {
                HStack(spacing: 8) {
                    if state.isWorking { ProgressView() }
                    Text(state.isWorking ? "正在生成…" : summary?.submitTitle ?? "生成 \(wizard.count) 个兑换码")
                }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(state.isWorking || summary == nil)
            .accessibilityIdentifier("redeem.generate.submit")
            .readOnlyGate()
            if let detail = state.progress?.detail {
                Text(detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).accessibilityIdentifier("redeem.generate.progress")
            }
            if state.isWorking, state.progress != nil {
                Button(BalanceChangeCopy.later) { state.later() }.frame(minHeight: 44).accessibilityIdentifier("redeem.generate.later")
            }
        }
    }
}

// MARK: Parts

/// A white card with an optional small title (design `.vmo-fsec`).
private struct RedeemGenerateCard<Content: View>: View {
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

private struct RedeemGenerateFootnote: View {
    let text: String

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The primary button pinned under the step.
private struct RedeemGenerateBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Palette.sheetBackground)
    }
}

/// A selectable capsule (design `VmoChoice`); 44pt to tap.
private struct RedeemGenerateChip: View {
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

/// 自定义天数: digits only, 1–3650 (the wizard filters, the form checks the range).
private struct RedeemDaysField: View {
    @Binding var text: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(RedeemGenerateWizard.customDaysPlaceholder, text: $text)
                .keyboardType(.numberPad)
                .monospacedDigit()
                .accessibilityLabel("天数")
                .accessibilityIdentifier(identifier)
            Text("天").foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
