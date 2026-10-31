import SwiftUI
import Sub2Core

/// 内容 (60 §17.3): the title with its 200-byte footnote, the format bar with “N 字”, and the body.
struct AnnouncementContentSection: View {
    @Binding var draft: AnnouncementDraft
    @Binding var selection: TextSelection?
    @FocusState private var editingBody: Bool

    var body: some View {
        Section {
            TextField(AnnouncementEditCopy.titlePlaceholder, text: $draft.title)
                .accessibilityIdentifier("announcement.edit.title")
            if let footnote = draft.titleFootnote {
                Text(footnote).font(.footnote).foregroundStyle(Palette.criticalInk)
                    .accessibilityIdentifier("announcement.edit.titleFootnote")
            }
            formatBar
            TextEditor(text: $draft.content, selection: $selection)
                .focused($editingBody)
                .frame(minHeight: 160)
                .accessibilityLabel("正文")
                .accessibilityIdentifier("announcement.edit.content")
                .overlay(alignment: .topLeading) {
                    if draft.content.isEmpty {
                        Text(AnnouncementEditCopy.contentPlaceholder).foregroundStyle(Palette.ink3)
                            .padding(EdgeInsets(top: 8, leading: 5, bottom: 0, trailing: 0)).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        } header: {
            Text("内容")
        } footer: {
            Text(AnnouncementEditCopy.markdownFootnote)
        }
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            ForEach(MarkdownSnippet.allCases, id: \.self) { snippet in
                Button { insert(snippet) } label: {
                    Image(systemName: snippet.systemImage).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(snippet.title)
                .accessibilityIdentifier("announcement.edit.md.\(snippet.rawValue)")
            }
            Spacer(minLength: 8)
            Text(MarkdownEdit.countText(draft.content)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("announcement.edit.count")
        }
    }

    /// At the selection (the end when the body has none), then the inserted example or wrapped text is selected.
    private func insert(_ snippet: MarkdownSnippet) {
        let text = draft.content
        let range = Self.offsets(of: selection, in: text) ?? (text.count..<text.count)
        let edit = MarkdownEdit.insert(snippet, into: text, selection: range)
        draft.content = edit.text
        let lower = edit.text.index(edit.text.startIndex, offsetBy: edit.selection.lowerBound)
        selection = TextSelection(range: lower..<edit.text.index(lower, offsetBy: edit.selection.count))
        editingBody = true
    }
    /// Character offsets of the first selected range; nil when there is none or it no longer fits the text.
    private static func offsets(of selection: TextSelection?, in text: String) -> Range<Int>? {
        guard let selection else { return nil }
        let range: Range<String.Index>
        switch selection.indices {
        case .selection(let selected): range = selected
        case .multiSelection(let set):
            guard let first = set.ranges.first else { return nil }
            range = first
        @unknown default: return nil
        }
        guard let lower = String.Index(range.lowerBound, within: text), let upper = String.Index(range.upperBound, within: text) else { return nil }
        return text.distance(from: text.startIndex, to: lower)..<text.distance(from: text.startIndex, to: upper)
    }
}

/// 可见对象: 所有用户 or one condition — any of the chosen subscription groups, or the balance against an amount. A targeting
/// the phone cannot edit is listed read-only (“条件 … / 或 …”).
struct AnnouncementTargetSection: View {
    @Binding var draft: AnnouncementDraft
    let options: [AnnouncementGroupOption]
    let lockedLines: [AnnouncementLockedLine]

    var body: some View {
        Section {
            if draft.isTargetLocked { locked } else { editable }
        } header: {
            Text("可见对象")
        } footer: {
            Text(draft.targetFootnote).accessibilityIdentifier("announcement.edit.targetFootnote")
        }
    }

    private var locked: some View {
        ForEach(Array(lockedLines.enumerated()), id: \.offset) { index, line in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.prefix).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2).frame(minWidth: 28, alignment: .leading)
                Text(line.text).foregroundStyle(Palette.ink1)
            }
            .frame(minHeight: 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("announcement.edit.locked.\(index)")
        }
    }

    @ViewBuilder private var editable: some View {
        Picker("可见对象", selection: $draft.targetMode) {
            ForEach(AnnouncementTargetMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("announcement.edit.targetMode")
        if draft.targetMode == .custom {
            Picker("条件", selection: $draft.conditionKind) {
                ForEach(AnnouncementConditionKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("announcement.edit.conditionKind")
            if draft.conditionKind == .subscription { subscriptions } else { balance }
        }
    }

    private var subscriptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AnnouncementEditCopy.subscriptionPrompt).font(.subheadline).foregroundStyle(Palette.ink2)
            if options.isEmpty {
                Text(AnnouncementEditCopy.noSubscriptionGroups).font(.footnote).foregroundStyle(Palette.ink3)
                    .accessibilityIdentifier("announcement.edit.noGroups")
            } else {
                ListFieldFlow(spacing: 8) {
                    ForEach(options) { option in
                        let chosen = draft.groupIDs.contains(option.id)
                        AnnouncementChip(title: option.name, isOn: chosen) { toggle(option.id) }
                            .disabled(!option.isAvailable && !chosen)
                            .opacity(option.isAvailable ? 1 : 0.55)
                            .accessibilityIdentifier("announcement.edit.group.\(option.id)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var balance: some View {
        HStack(spacing: 6) {
            ForEach(AnnouncementBalanceOperator.allCases, id: \.self) { comparison in
                AnnouncementChip(title: comparison.symbol, isOn: draft.balanceOperator == comparison) { draft.balanceOperator = comparison }
                    .accessibilityLabel(comparison.spokenTitle)
                    .accessibilityIdentifier("announcement.edit.operator.\(comparison.rawValue)")
            }
            Spacer(minLength: 8)
            Text("$").foregroundStyle(Palette.ink2).accessibilityHidden(true)
            TextField("0.00", text: Binding(get: { draft.balanceText }, set: { draft.balanceText = AnnouncementDraft.sanitizedAmount($0) }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110, minHeight: 44)
                .accessibilityLabel("余额阈值（美元）")
                .accessibilityIdentifier("announcement.edit.amount")
        }
    }

    private func toggle(_ id: Int) {
        if draft.groupIDs.contains(id) { draft.groupIDs.remove(id) } else { draft.groupIDs.insert(id) }
    }
}

/// A selectable capsule of the target section; 44pt to tap.
private struct AnnouncementChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(isOn ? .semibold : .regular))
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

/// 通知方式: new ones are silent.
struct AnnouncementNotifySection: View {
    @Binding var draft: AnnouncementDraft

    var body: some View {
        Section {
            Picker("通知方式", selection: $draft.notifyMode) {
                ForEach(AnnouncementNotifyMode.allCases, id: \.self) { Text(AnnouncementPresentation.notifyTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("announcement.edit.notify")
        } header: {
            Text("通知方式")
        } footer: {
            Text(draft.notifyFootnote).accessibilityIdentifier("announcement.edit.notifyFootnote")
        }
    }
}

/// 有效期: 开始 立即 / 指定时间, 结束 永久 / 指定时间; a chosen time is a date and a time on the phone's clock (00 §6.3).
struct AnnouncementScheduleSection: View {
    @Binding var draft: AnnouncementDraft

    var body: some View {
        Section {
            row("开始", empty: AnnouncementPresentation.startNowText, specified: $draft.startsSpecified, pick: $draft.startPick, id: "start")
            row("结束", empty: AnnouncementPresentation.endNeverText, specified: $draft.endsSpecified, pick: $draft.endPick, id: "end")
        } header: {
            Text("有效期")
        } footer: {
            Text(draft.scheduleFootnote).foregroundStyle(draft.isTimeRangeValid ? Palette.ink2 : Palette.criticalInk)
                .accessibilityIdentifier("announcement.edit.scheduleFootnote")
        }
    }

    private func row(_ label: String, empty: String, specified: Binding<Bool>, pick: Binding<Date>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).foregroundStyle(Palette.ink1)
                Spacer(minLength: 12)
                Picker(label, selection: specified) {
                    Text(empty).tag(false)
                    Text(AnnouncementEditCopy.specifiedTime).tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("announcement.edit.\(id)Mode")
            }
            if specified.wrappedValue {
                DatePicker(label, selection: pick, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.timeZone, .current)
                    .accessibilityIdentifier("announcement.edit.\(id)Pick")
            }
        }
        .padding(.vertical, 2)
    }
}

/// The result of the last save above the bottom button: progress, a refusal, or an unknown result with what can be done
/// about it (60 §17.4, H07; 00 §2.4).
struct AnnouncementEditStatusBar: View {
    let flow: AnnouncementEditFlow
    let now: Date

    var body: some View {
        Group {
            switch flow.phase {
            case .editing: EmptyView()
            case .saving(let event): progress(AnnouncementEditCopy.savingText(event))
            case .checking: progress(AnnouncementEditCopy.checking)
            case .failed(let message): banner(.critical, message)
            case .createUnconfirmed:
                banner(.caution, KeyedWriteFailure.unconfirmedMessage) {
                    button(AnnouncementEditCopy.retrySame, id: "retry") { await flow.retrySameKey() }
                }
            case .maybeCreated(let match):
                banner(.caution, AnnouncementEditCopy.maybeCreatedTitle,
                       detail: AnnouncementEditCopy.maybeCreatedDetail(match, now: now, timeZone: .current)) {
                    button(AnnouncementEditCopy.viewExisting, id: "viewExisting") { flow.viewExisting() }
                    button(AnnouncementEditCopy.createAnyway, id: "createAnyway") { await flow.createAnyway() }
                }
            case .notFoundYet:
                banner(.caution, AnnouncementEditCopy.notFoundTitle, detail: AnnouncementEditCopy.notFoundDetail) {
                    button(AnnouncementEditCopy.recheck, id: "recheck") { await flow.recheck() }
                    button(AnnouncementEditCopy.createAnyway, id: "createAnyway") { await flow.createAnyway() }
                }
            case .updateUnconfirmed:
                banner(.caution, AnnouncementDetailPresentation.unconfirmed) {
                    button(AnnouncementEditCopy.recheck, id: "recheck") { await flow.recheck() }
                }
            case .gone: banner(.critical, AnnouncementEditCopy.gone)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("announcement.edit.status")
    }

    private func banner(_ tone: Tone, _ title: String, detail: String? = nil, @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBanner(tone: tone, systemImage: tone == .critical ? "exclamationmark.triangle" : "questionmark.circle", title: title, detail: detail)
                .accessibilityIdentifier("announcement.edit.status")
            HStack(spacing: 10) { actions() }
        }
    }

    private func button(_ title: String, id: String, perform: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await perform() } } label: { Text(title).frame(minHeight: 30) }
            .buttonStyle(.bordered)
            .disabled(flow.isBusy)
            .accessibilityIdentifier("announcement.edit.\(id)")
    }
}
