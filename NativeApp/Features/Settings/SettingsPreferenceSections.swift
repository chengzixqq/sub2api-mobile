import SwiftUI
import Sub2Core

/// 60 §3.3 壹: the main mode; the simple mode shows greyed and “设计中” (U42).
struct SettingsInterfaceRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsChoiceRow(title: SettingsPresentation.mainModeTitle, subtitle: SettingsPresentation.mainModeSubtitle,
                          isSelected: model.preferences.interfaceMode == .main) { model.preferences.setInterfaceMode(.main) }
            .accessibilityIdentifier("settings.mode.main")
        SettingsChoiceRow(title: SettingsPresentation.simpleModeTitle, subtitle: SettingsPresentation.simpleModeSubtitle, isSelected: false,
                          trailing: SettingsPresentation.simpleModeBadge) {}
            .disabled(true)
            .accessibilityIdentifier("settings.mode.simple")
    }
}

/// 60 §3.3 贰 and §3.4: written at once; RootView applies it.
struct SettingsAppearanceRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(AppPreferences.Appearance.allCases, id: \.self) { appearance in
            SettingsChoiceRow(title: appearance.title, isSelected: model.preferences.appearance == appearance) {
                model.preferences.setAppearance(appearance)
            }
            .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
        }
    }
}

/// 60 §3.3 叁 and §3.4: turning the switch on or off is verified once (U48); while that runs the switch shows the requested
/// value and cannot be touched again. The threshold row shows only while the switch is in force.
struct SettingsSecurityRows: View {
    let editThreshold: () -> Void
    @Environment(AppModel.self) private var model
    @State private var requested: Bool?

    init(editThreshold: @escaping () -> Void) { self.editThreshold = editThreshold }

    private var gate: BiometricGate { model.biometricGate }

    var body: some View {
        let isAvailable = gate.isAvailable
        Toggle(isOn: Binding(get: { requested ?? gate.isRequirementActive }, set: change)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SettingsPresentation.faceIDTitle).foregroundStyle(Palette.ink1)
                Text(isAvailable ? SettingsPresentation.faceIDSubtitle : SettingsPresentation.faceIDUnavailableSubtitle)
                    .font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .tint(Palette.accentFill)
        .frame(minHeight: 44)
        .disabled(!isAvailable || requested != nil)
        .accessibilityIdentifier("settings.faceid")
        if gate.isRequirementActive {
            Button(action: editThreshold) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsPresentation.thresholdTitle).foregroundStyle(Palette.ink1)
                        Text(SettingsPresentation.thresholdSubtitle).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 8)
                    Text(SettingsPresentation.thresholdText(model.preferences.faceIDThreshold)).monospacedDigit().foregroundStyle(Palette.ink2)
                    SettingsChevron()
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.faceid.threshold")
        }
    }

    private func change(_ value: Bool) {
        guard requested == nil, value != gate.isRequirementActive else { return }
        requested = value
        let gate = gate
        Task {
            await gate.setRequirement(value)
            requested = nil
        }
    }
}

/// 60 §3.3 肆: 已开启 / 未开启 / 已停用 of this phone's target (S6-24). With a registered id the list is read each time the row
/// appears, so coming back from 推送通知 shows what changed; until it answers, or when it fails, the id alone reads 已开启.
struct SettingsNotificationRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var devices: [PushDevice]?
    /// Bumped after the source is made: under `-ui-testing` that is when the records are seeded (S6D2b-06).
    @State private var reads = 0

    var body: some View {
        let _ = (model.pushCoordinator.revision, reads)
        let localID = session.flatMap { model.pushCoordinator.registeredDeviceID(serverID: $0.serverID) }
        let state = PushPresentation.localState(registeredID: localID, devices: devices)
        NavigationLink(value: AppRoute.push) {
            HStack {
                Label("推送通知", systemImage: "bell").foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(state.settingsTitle).foregroundStyle(Palette.ink2)
            }
        }
        .accessibilityValue(state.settingsTitle)
        .accessibilityIdentifier("settings.push")
        .task(id: session?.generation) { await readDevices() }
        .onChange(of: model.pushCoordinator.revision) { _, _ in Task { await readDevices() } }
    }

    private func readDevices() async {
        guard let session, session.generation == model.sessionGeneration else { devices = nil; return }
        let source = await PushSettingsSources.make(model: model, context: session)
        reads += 1
        guard model.pushCoordinator.registeredDeviceID(serverID: session.serverID) != nil else { devices = nil; return }
        let list = try? await source.pushDevices()
        guard session.generation == model.sessionGeneration else { return }
        devices = list
    }
}

/// A single-choice row of 60 §3.3: a radio dot, the title, an optional subtitle and trailing note.
struct SettingsChoiceRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var trailing: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(isEnabled ? Palette.ink1 : Palette.ink3)
                    if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Palette.ink3) }
                }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.footnote).foregroundStyle(Palette.ink3) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The chevron of a row that opens a sheet or another app, drawn like the pushed rows' system chevron.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
            .accessibilityHidden(true)
    }
}

extension AppPreferences.Appearance {
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}
