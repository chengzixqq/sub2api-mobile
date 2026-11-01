import SwiftUI
import Sub2Core

/// 60 §7.3 本机: the switch (greyed with its reason), the status line, 去设置 after a refused permission, the switch's last
/// failure and 发送测试推送. A failed list replaces nothing but adds “加载失败 · 重试” and greys the controls (7.5).
struct PushLocalSection: View {
    let isOn: Bool
    let controls: PushLocalControls
    let statusLine: String?
    let permissionDenied: Bool
    let errorText: String?
    let isTesting: Bool
    let listFailed: Bool
    let onToggle: (Bool) -> Void
    let onOpenSystemSettings: () -> Void
    let onTest: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: { onToggle($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PushPresentation.localToggleTitle).foregroundStyle(Palette.ink1)
                    if let note = controls.toggleNote { Text(note).font(.footnote).foregroundStyle(Palette.ink2) }
                }
            }
            .tint(Palette.accentFill)
            .frame(minHeight: 44)
            .disabled(!controls.toggleEnabled)
            .accessibilityIdentifier("push.local.toggle")
            if listFailed { PushRetryRow(identifier: "push.local.retry", action: onRetry) }
            if let statusLine {
                Text(statusLine).font(.subheadline).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("push.local.status")
            }
            if permissionDenied {
                Button(action: onOpenSystemSettings) {
                    Text(PushPresentation.systemPermissionDenied).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .accessibilityIdentifier("push.local.permission")
            }
            if let errorText {
                Text(errorText).font(.subheadline).foregroundStyle(Tone.critical.ink)
                    .accessibilityIdentifier("push.local.error")
            }
            Button(action: onTest) {
                HStack {
                    Text(PushPresentation.sendTest)
                    Spacer(minLength: 8)
                    if isTesting { ProgressView() }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .disabled(!controls.testEnabled)
            .accessibilityIdentifier("push.local.test")
        } header: {
            NumberedSectionHeader(title: PushPresentation.localSectionTitle)
        }
    }
}

/// 60 §7.3 其他接收方式: every target but this phone's, in id order; a row opens its page. A read-only token gets no 添加.
struct PushTargetsSection: View {
    let rows: [PushTargetRow]
    let listFailed: Bool
    let showsAdd: Bool
    let onAdd: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if listFailed || showsAdd || !rows.isEmpty {
            Section {
                if listFailed { PushRetryRow(identifier: "push.targets.retry", action: onRetry) }
                ForEach(rows) { row in
                    NavigationLink(value: AppRoute.pushTarget(id: row.id)) { PushTargetRowLabel(row: row) }
                        .accessibilityIdentifier("push.targets.row.\(row.id)")
                }
                if showsAdd {
                    Button(action: onAdd) {
                        Text(PushPresentation.addTarget).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("push.targets.add")
                }
            } header: {
                NumberedSectionHeader(title: PushPresentation.otherTargetsTitle)
            }
        }
    }
}

/// Icon, name, “Bark · api.day.app” and a neutral 已停用 (60 §7.3); also the head of a target's page.
struct PushTargetRowLabel: View {
    let row: PushTargetRow
    var statusLine: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbolName).font(.body).foregroundStyle(Palette.ink2).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).foregroundStyle(Palette.ink1).lineLimit(1)
                Text(row.subtitle).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                if let statusLine { Text(statusLine).font(.footnote).foregroundStyle(Palette.ink2) }
            }
            Spacer(minLength: 8)
            if row.isDisabled { ToneBadge(text: PushPresentation.disabledBadge, tone: .neutral) }
        }
        .frame(minHeight: 44)
    }
}

/// 60 §7.3 站点 APNs 配置; 编辑 follows the rule for revealing a key, greyed with its reason.
struct PushAPNsSection: View {
    let rows: PushAPNsConfigRows
    let editability: PushAPNsEditability
    let onEdit: () -> Void

    var body: some View {
        Section {
            item("Team ID", rows.teamID, id: "push.apns.teamID")
            item("Key ID", rows.keyID, id: "push.apns.keyID")
            item("私钥", rows.privateKey, id: "push.apns.privateKey")
            item("Topic", rows.topic, id: "push.apns.topic")
            item("环境", rows.environment, id: "push.apns.environment")
            LabeledContent("状态") { Text(rows.status).foregroundStyle(rows.statusTone.ink) }
                .padding(.vertical, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("状态").accessibilityValue(rows.status)
                .accessibilityIdentifier("push.apns.status")
            Button(action: onEdit) {
                Text("编辑").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .disabled(!editability.isAvailable)
            .accessibilityIdentifier("push.apns.edit")
            if let note = editability.note {
                Text(note).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("push.apns.editNote")
            }
        } header: {
            NumberedSectionHeader(title: PushPresentation.apnsSectionTitle)
        }
    }

    private func item(_ label: String, _ value: String, id: String) -> some View {
        LabeledValue(label: label, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(DisplayFormat.spoken(value))
            .accessibilityIdentifier(id)
    }
}

/// “加载失败 · 重试” in place of a section's rows (60 §7.5).
struct PushRetryRow: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(PushPresentation.loadFailed).foregroundStyle(Tone.critical.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }
}
