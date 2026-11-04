import SwiftUI
import Sub2Core

/// C-5 (S1-08), the App's one 运维监控未开启: `.inline` under the overview's six tiles (10 §1.3.1), `.emptyState` for the monitor's
/// sections, the alert detail (pass `notesDataGap: true`) and chapter 40's statistics. Without a `reason` it shows the session's
/// (LiveOpsStore.opsDisabledReason). Only the owner gets the button, on a site with a safe write and not while the server
/// configuration holds monitoring off; it asks first, then turns monitoring on (10 §7.2). Identifiers: ops.disabled.inline,
/// ops.disabled.empty, ops.disabled.enable, ops.disabled.confirm.
struct OpsDisabledNotice: View {
    enum Style { case inline, emptyState }

    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    private let style: Style
    private let reason: OpsDisabledReason?
    private let tpmExcludesCache: Bool
    private let notesDataGap: Bool
    @State private var isConfirming = false

    init(style: Style, reason: OpsDisabledReason? = nil, tpmExcludesCache: Bool = false, notesDataGap: Bool = false) {
        self.style = style; self.reason = reason; self.tpmExcludesCache = tpmExcludesCache; self.notesDataGap = notesDataGap
    }

    var body: some View {
        Group {
            switch style {
            case .inline: inline
            case .emptyState: emptyState
            }
        }
        .alert(confirmation.title, isPresented: $isConfirming) {
            Button("取消", role: .cancel) {}
            Button(confirmation.confirmTitle) {
                let store = model.liveOps
                Task { await store?.enableOpsMonitoring() }
            }
            .accessibilityIdentifier("ops.disabled.confirm")
        } message: {
            Text(confirmation.message)
        }
    }

    private var confirmation: OpsDisabledPresentation.Confirmation { OpsDisabledPresentation.enableConfirmation }
    private var shownReason: OpsDisabledReason { reason ?? model.liveOps?.opsDisabledReason ?? .unknown }
    private var offersEnable: Bool {
        guard let me = session?.site.me else { return false }
        return OpsDisabledPresentation.offersEnable(reason: shownReason, isAdministrator: me.isAdministrator, route: OpsMonitoringWriteRoute.resolve(me: me))
    }
    private var isToggling: Bool { model.liveOps?.isTogglingOps == true }

    private var inline: some View {
        StatusBanner(tone: .neutral, systemImage: "waveform.path.ecg",
                     title: OpsDisabledPresentation.inlineText(reason: shownReason, tpmExcludesCache: tpmExcludesCache)) {
            if offersEnable { enableButton(OpsDisabledPresentation.inlineActionTitle) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ops.disabled.inline")
    }

    private var emptyState: some View {
        let empty = OpsDisabledPresentation.emptyState(reason: shownReason, offersEnable: offersEnable, notesDataGap: notesDataGap)
        return ContentUnavailableView {
            Label(empty.title, systemImage: "waveform.path.ecg")
        } description: {
            if let detail = empty.detail { Text(detail) }
        } actions: {
            if let action = empty.actionTitle { enableButton(action).buttonStyle(.bordered) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ops.disabled.empty")
    }

    /// Waits while a switch write is on its way; greyed for a read-only token (C-1).
    private func enableButton(_ title: String) -> some View {
        Button { isConfirming = true } label: {
            Group {
                if isToggling { ProgressView() } else { Text(title).font(.subheadline.weight(.semibold)) }
            }
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .disabled(isToggling || model.liveOps == nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier("ops.disabled.enable")
        .readOnlyGate()
    }
}

extension View {
    /// U10, for the monitor's ··· menu (S1-13): two confirmations, the second naming the site, then LiveOpsStore turns monitoring off.
    /// Show the entry only when `OpsDisabledPresentation.offersDisable` holds. Identifiers ops.disable.confirm, ops.disable.final.
    func opsDisableConfirmation(isPresented: Binding<Bool>) -> some View { modifier(OpsDisableConfirmation(isPresented: isPresented)) }
}

private struct OpsDisableConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var isConfirmingAgain = false

    func body(content: Content) -> some View {
        let first = OpsDisabledPresentation.disableConfirmation
        let last = OpsDisabledPresentation.disableFinalConfirmation(siteName: model.activeProfile?.name ?? "")
        content
            .confirmationDialog(first.title, isPresented: $isPresented, titleVisibility: .visible) {
                Button(first.confirmTitle, role: .destructive) { isConfirmingAgain = true }
                    .accessibilityIdentifier("ops.disable.confirm")
                Button("取消", role: .cancel) {}
            } message: {
                Text(first.message)
            }
            .alert(last.title, isPresented: $isConfirmingAgain) {
                Button("取消", role: .cancel) {}
                Button(last.confirmTitle, role: .destructive) {
                    let store = model.liveOps
                    Task { await store?.disableOpsMonitoring() }
                }
                .accessibilityIdentifier("ops.disable.final")
            } message: {
                Text(last.message)
            }
    }
}
