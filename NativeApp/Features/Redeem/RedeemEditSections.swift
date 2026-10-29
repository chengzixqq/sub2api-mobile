import SwiftUI
import Sub2Core

/// What the edit sheet says above the form: a refusal, a lost reply, or the 409 that turned it into notes only.
struct RedeemEditNotice: Equatable {
    let text: String
    let tone: Tone
}

/// 60 §9.3: the object bar, then by mode — a redeemed code's banner and read-only rows; 状态 · 订阅分组 · 过期时间 for an unused
/// or disabled code; 新的过期时间 first for an expired one — and 备注. Times the administrator picks or keeps are on the phone's
/// clock (00 §6.3); the redeemed time is the server's.
struct RedeemEditForm: View {
    @Binding var draft: RedeemEditDraft
    /// The server-corrected clock.
    let now: Date
    let serverZone: ServerTimeZone
    /// The session's group directory (X11).
    let groups: [AdminGroup]
    let notice: RedeemEditNotice?

    private var code: AdminRedeemCode { draft.original }

    var body: some View {
        Form {
            targetSection
            if let notice { noticeSection(notice) }
            if code.isRedeemed { usedSections }
            switch draft.mode {
            case .toggleable:
                statusSection
                groupSection
                expirySection
            case .expired:
                expirySection
                statusSection
                groupSection
            case .notesOnly:
                EmptyView()
            }
            notesSection
        }
        .accessibilityIdentifier("redeem.edit.sheet")
    }

    // MARK: Head

    private var targetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(RedeemPresentation.shortCode(code.code)).font(.system(.headline, design: .monospaced)).foregroundStyle(Palette.ink1)
                Text(RedeemEditCopy.targetLine(code)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("兑换码结尾 \(RedeemPresentation.tail(code.code))，\(RedeemEditCopy.targetLine(code))")
            .accessibilityIdentifier("redeem.edit.target")
        }
    }

    private func noticeSection(_ notice: RedeemEditNotice) -> some View {
        Section {
            StatusBanner(tone: notice.tone, systemImage: "exclamationmark.triangle", title: notice.text)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("redeem.edit.message")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    // MARK: Redeemed

    @ViewBuilder private var usedSections: some View {
        Section {
            let time = DisplayFormat.monthDayClock(code.usedAt, timeZone: serverZone, now: now)
            StatusBanner(tone: .ok, systemImage: "checkmark.circle", title: RedeemEditCopy.usedBanner,
                         detail: RedeemEditCopy.usedBy(name: RedeemPresentation.userName(code), at: time))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("redeem.edit.usedBanner")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        Section(RedeemEditCopy.objectNoun) {
            readOnlyRow("状态", RedeemCodeStatus.used.label)
            if code.codeType == .subscription { readOnlyRow("订阅分组", RedeemPresentation.prefix(code, groupName: groupName(code.groupID))) }
            readOnlyRow("过期时间", code.expiresAt.map { RedeemPresentation.timestamp($0, now: now, timeZone: .current) } ?? "永不过期")
        }
    }

    private func readOnlyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Palette.ink1).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 状态

    @ViewBuilder private var statusSection: some View {
        if draft.mode == .toggleable {
            Section {
                Picker("状态", selection: $draft.status) {
                    Text(RedeemCodeStatus.unused.label).tag(RedeemBatchUpdateFields.Status.unused)
                    Text(RedeemCodeStatus.disabled.label).tag(RedeemBatchUpdateFields.Status.disabled)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("redeem.edit.status")
            } header: {
                Text("状态")
            } footer: {
                Text(RedeemEditCopy.statusFootnote)
            }
        } else {
            Section("状态") {
                HStack(spacing: 6) {
                    Text("状态").foregroundStyle(Palette.ink2)
                    Spacer(minLength: 8)
                    ForEach(Array(draft.statusTitles.enumerated()), id: \.offset) { index, title in
                        if index > 0 { Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Palette.ink2) }
                        Text(title).fontWeight(index > 0 ? .semibold : .regular).foregroundStyle(Palette.ink1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("状态")
                .accessibilityValue(draft.statusTitles.joined(separator: " → "))
                .accessibilityIdentifier("redeem.edit.statusReadonly")
            }
        }
    }

    // MARK: 订阅分组

    @ViewBuilder private var groupSection: some View {
        if draft.showsGroup {
            Section("订阅分组") {
                ListFieldFlow(spacing: 8) {
                    ForEach(groupOptions, id: \.id) { option in
                        RedeemEditChip(title: option.title, isOn: draft.groupID == option.id) { draft.groupID = option.id }
                            .accessibilityIdentifier("redeem.edit.group.\(option.id)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Active subscription groups in the directory's order (60 §9.2); the code's own group stays shown, marked, when it is
    /// no longer one of them.
    private var groupOptions: [(id: Int, title: String)] {
        let active = groups.filter(\.isActiveSubscriptionGroup).map { (id: $0.id, title: $0.name) }
        guard let current = code.groupID, !active.contains(where: { $0.id == current }) else { return active }
        let name = groupName(current) ?? code.group?.name ?? "分组 #\(current)"
        return [(id: current, title: RedeemEditCopy.groupDisabled(name))] + active
    }
    private func groupName(_ id: Int?) -> String? { id.flatMap { id in groups.first { $0.id == id }?.name } }

    // MARK: 过期时间

    @ViewBuilder private var expirySection: some View {
        Section {
            ListFieldFlow(spacing: 8) {
                ForEach(draft.expiryChoices, id: \.self) { choice in
                    RedeemEditChip(title: draft.title(for: choice, now: now, timeZone: .current), isOn: draft.expiry == choice) { draft.expiry = choice }
                        .accessibilityIdentifier("redeem.edit.expiry.\(choice.identifier)")
                }
            }
            .padding(.vertical, 4)
            if draft.expiry == .custom {
                DatePicker(RedeemEditCopy.customLabel, selection: $draft.customExpiry, in: now..., displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, .current)
                    .accessibilityIdentifier("redeem.edit.expiry.picker")
                if let note = AccountExpiry.timeZoneNote(device: .current, server: serverZone, at: now) {
                    Text(note).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("redeem.edit.expiry.timezone")
                }
            }
        } header: {
            Text(draft.expirySectionTitle)
        } footer: {
            Text(draft.expiryFootnote(now: now, timeZone: .current))
                .foregroundStyle(draft.expiry == .custom && !draft.customIsValid(now: now) ? Palette.criticalInk : Palette.ink2)
                .accessibilityIdentifier("redeem.edit.expiry.footnote")
        }
    }

    // MARK: 备注

    private var notesSection: some View {
        Section {
            TextField(RedeemEditCopy.notesPlaceholder, text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
                .frame(minHeight: 44)
                .accessibilityLabel("备注")
                .accessibilityIdentifier("redeem.edit.notes")
        } header: {
            Text("备注")
        } footer: {
            Text(RedeemEditCopy.notesFootnote)
        }
    }
}

/// A selectable capsule (design `VmoChoice`); 44pt to tap.
private struct RedeemEditChip: View {
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
