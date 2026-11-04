import SwiftUI
import UIKit
import Sub2Core

/// 60 §14.3: the renewal's object bar, the result of the last write, then the sections in the mode's order. Each footer shows the
/// section's problem (critical) above its note; a refusal tied to a section (the backup) shows there too.
struct ProxyEditForm: View {
    @Binding var draft: ProxyEditDraft
    let backups: [ProxyBackupCandidate]
    let zone: ServerTimeZone
    let flow: ProxyEditFlow?
    /// A write runs or its result is open.
    let isLocked: Bool

    private var mode: ProxyEditMode { draft.mode }

    var body: some View {
        Form {
            if let target = draft.renewTarget { targetSection(target) }
            if let flow { ProxyEditStatusSection(flow: flow) }
            ForEach(ProxyEditSection.order(for: mode), id: \.self) { section in
                content(section).disabled(isLocked)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("proxyEdit.form")
    }

    private func targetSection(_ target: ProxyRenewTarget) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name).font(.headline).foregroundStyle(Palette.ink1)
                Text(target.detail).font(.footnote.monospaced()).foregroundStyle(Palette.ink2)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(target.line)
            .accessibilityIdentifier("proxyEdit.renewTarget")
        }
    }

    @ViewBuilder private func content(_ section: ProxyEditSection) -> some View {
        Section {
            switch section {
            case .name: nameRows
            case .address: addressRows
            case .auth: authRows
            case .expiry: expiryRows
            case .fallback: fallbackRows
            case .status: statusRows
            }
        } header: {
            Text(section.title(in: mode)).accessibilityIdentifier("proxyEdit.section.\(section.rawValue)")
        } footer: {
            footer(section)
        }
    }

    // MARK: Rows

    @ViewBuilder private var nameRows: some View {
        ProxyEditField(label: "名称", text: $draft.name, prompt: ProxyEditCopy.namePlaceholder, id: "name")
        Picker("协议", selection: $draft.scheme) {
            ForEach(ProxyProtocolChoice.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("proxyEdit.protocol")
    }

    @ViewBuilder private var addressRows: some View {
        ProxyEditField(label: "主机", text: $draft.host, prompt: ProxyEditCopy.hostPlaceholder, id: "host", isMonospaced: true, keyboard: .URL)
        ProxyDigitsField(label: "端口", value: $draft.portText, prompt: ProxyEditCopy.portPlaceholder, id: "port", sanitize: ProxyEditDraft.sanitizePort)
    }

    @ViewBuilder private var authRows: some View {
        ProxyEditField(label: "用户名", text: $draft.username, prompt: ProxyEditCopy.usernamePlaceholder, id: "username", isMonospaced: true)
        ProxyEditField(label: "密码", text: $draft.password, prompt: mode == .add ? ProxyEditCopy.passwordPlaceholder : ProxyEditCopy.keepPasswordPlaceholder,
                       id: "password", isSecure: true)
    }

    @ViewBuilder private var expiryRows: some View {
        ListFieldFlow(spacing: 8) {
            ForEach(draft.expiryOptions(timeZone: zone)) { option in
                ProxyEditChip(title: option.title, isOn: draft.expiry == option.choice) { draft.selectExpiry(option.choice) }
                    .accessibilityIdentifier("proxyEdit.expiry.\(option.id)")
            }
        }
        .padding(.vertical, 4)
        if draft.expiry == .custom {
            ProxyDigitsField(label: "天数", value: $draft.customDaysText, prompt: ProxyEditCopy.customDaysPlaceholder, id: "customDays",
                             sanitize: ProxyEditDraft.sanitizeCustomDays)
        }
        Stepper(value: $draft.warnDays, in: draft.warnDaysRange) {
            HStack {
                Text(ProxyEditCopy.warnDaysLabel).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text("\(draft.warnDays) 天").monospacedDigit().foregroundStyle(Palette.ink2)
            }
        }
        .frame(minHeight: 44)
        .accessibilityValue("\(draft.warnDays) 天")
        .accessibilityIdentifier("proxyEdit.warnDays")
    }

    @ViewBuilder private var fallbackRows: some View {
        Picker("到期回退", selection: $draft.fallback) {
            ForEach(ProxyEditCopy.fallbackOrder, id: \.self) { Text(ProxyEditCopy.title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("proxyEdit.fallback")
        if draft.fallback == .proxy {
            VStack(alignment: .leading, spacing: 6) {
                Text(ProxyEditCopy.backupLabel).font(.subheadline).foregroundStyle(Palette.ink2)
                if backups.isEmpty {
                    Text("没有其他代理").font(.subheadline).foregroundStyle(Palette.ink3)
                } else {
                    ListFieldFlow(spacing: 8) {
                        ForEach(backups) { candidate in backupChip(candidate) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func backupChip(_ candidate: ProxyBackupCandidate) -> some View {
        let isOn = draft.backupID == candidate.id
        let title = candidate.note.map { "\(candidate.name) · \($0)" } ?? candidate.name
        return ProxyEditChip(title: title, isOn: isOn) { draft.backupID = candidate.id }
            .disabled(!candidate.isSelectable)
            .opacity(candidate.isSelectable || isOn ? 1 : 0.5)
            .accessibilityIdentifier("proxyEdit.backup.\(candidate.id)")
    }

    @ViewBuilder private var statusRows: some View {
        Picker("状态", selection: $draft.status) {
            ForEach([ProxyStatusChange.active, .inactive], id: \.self) { Text(ProxyEditCopy.title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("proxyEdit.status")
    }

    // MARK: Footer

    @ViewBuilder private func footer(_ section: ProxyEditSection) -> some View {
        let issue = draft.issueNote(for: section, backups: backups) ?? refusal(in: section)
        let note = draft.footnote(for: section, timeZone: zone)
        let noteIsProblem = section == .status && draft.issues(backups: backups).contains(.lapsedKeepActive)
        if issue != nil || note != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let issue {
                    Text(issue).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("proxyEdit.issue.\(section.rawValue)")
                }
                if let note {
                    Text(note).foregroundStyle(noteIsProblem ? Palette.criticalInk : Palette.ink2)
                        .accessibilityIdentifier("proxyEdit.footnote.\(section.rawValue)")
                }
            }
        }
    }
    /// The last write's refusal when it belongs to this section.
    private func refusal(in section: ProxyEditSection) -> String? {
        guard let phase = flow?.phase, case .failed(let message, let failed?) = phase, failed == section else { return nil }
        return message
    }
}

/// The last write's state above the form (60 §14.5, 00 §2.4–§2.5.4): progress, a refusal not tied to a section, or an unknown
/// result with what can be done about it.
private struct ProxyEditStatusSection: View {
    let flow: ProxyEditFlow

    var body: some View {
        switch flow.phase {
        case .editing, .failed(_, _?): EmptyView()
        case .saving(let event): Section { progress(ProxyEditCopy.savingText(event)) }
        case .checking: Section { progress(ProxyEditCopy.checking) }
        case .failed(let message, nil): Section { banner(.critical, message) }
        case .addUnconfirmed(_, let searched):
            Section {
                banner(.caution, KeyedWriteFailure.unconfirmedMessage, detail: searched ? ProxyEditCopy.notFoundYet : nil)
                button(searched ? ProxyEditCopy.recheck : ProxyEditCopy.reconcile, id: "reconcile") { await flow.reconcileAdd() }
                button(ProxyEditCopy.retrySame, id: "retrySame") { await flow.retrySameKey() }
            }
        case .updateUnconfirmed:
            Section {
                banner(.caution, ProxyDetailCopy.unconfirmed)
                button(ProxyEditCopy.recheck, id: "recheck") { await flow.recheck() }
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
        .accessibilityIdentifier("proxyEdit.progress")
    }
    private func banner(_ tone: Tone, _ title: String, detail: String? = nil) -> some View {
        StatusBanner(tone: tone, systemImage: tone == .critical ? "exclamationmark.triangle" : "questionmark.circle", title: title, detail: detail)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("proxyEdit.error")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
    private func button(_ title: String, id: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("proxyEdit.\(id)")
    }
}

/// A labelled text row: the label on the left, the input on the right (design VmoField).
private struct ProxyEditField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let id: String
    var isMonospaced = false
    var isSecure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Palette.ink1)
            Group {
                if isSecure {
                    SecureField(label, text: $text, prompt: Text(prompt))
                } else {
                    TextField(label, text: $text, prompt: Text(prompt))
                        .font(isMonospaced ? .body.monospaced() : .body)
                        .keyboardType(keyboard)
                }
            }
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(label)
            .accessibilityIdentifier("proxyEdit.\(id)")
        }
        .frame(minHeight: 44)
    }
}

/// Digits only (port, days). The field keeps its own text and cuts it on the next turn: set in the same update, SwiftUI skips a
/// value equal to the one it last showed and the dropped key would stay on screen.
private struct ProxyDigitsField: View {
    let label: String
    @Binding var value: String
    let prompt: String
    let id: String
    let sanitize: (String) -> String
    @State private var text: String

    init(label: String, value: Binding<String>, prompt: String, id: String, sanitize: @escaping (String) -> String) {
        self.label = label; _value = value; self.prompt = prompt; self.id = id; self.sanitize = sanitize
        _text = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        ProxyEditField(label: label, text: $text, prompt: prompt, id: id, isMonospaced: true, keyboard: .numberPad)
            .onChange(of: text) { _, typed in
                let clean = sanitize(typed)
                if value != clean { value = clean }
                if clean != typed { Task { @MainActor in text = clean } }
            }
    }
}

/// A selectable capsule (design VmoChoice); 44pt to tap.
private struct ProxyEditChip: View {
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
