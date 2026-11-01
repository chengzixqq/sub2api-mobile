import SwiftUI
import UIKit
import Sub2Core

/// 60 §7 (S6-24): 设置 → 通知 → 推送通知. The banner when the site's APNs is not ready, this phone's switch with its status, the
/// subscription of this phone's target, the other targets and the site's APNs settings. Entering, a pull and the foreground
/// while shown read the list and the settings (7.6); coming back from a target's page reads the list. No polling. A
/// read-only token may still register this phone, edit, test and delete (60 §0.3); it only loses 添加 and 编辑.
struct PushSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.openURL) private var openURL
    @State private var store: PushSettingsModel?
    @State private var storeGeneration: UUID?
    @State private var catalog: MetaCatalog = .builtin
    /// The switch shows the value asked for until its request ends.
    @State private var requestedLocal: Bool?
    @State private var localError: String?
    @State private var sheet: PushSettingsSheet?
    @State private var isVisible = false

    private var coordinator: PushCoordinator { model.pushCoordinator }

    var body: some View {
        content
            .navigationTitle("推送通知")
            .navigationSubtitle(model.activeProfile?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .task(id: session?.generation) { catalog = await model.metaCatalog() }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onChange(of: model.foregroundRevision) { _, _ in
                guard isVisible, let store else { return }
                Task {
                    await coordinator.refreshAuthorization()
                    await store.load()
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                // .addTarget：S6-25
                case .addTarget: ComingSoonSheet(title: "添加接收方式")
                // .apnsConfig：S6-25
                case .apnsConfig: ComingSoonSheet(title: PushPresentation.apnsSectionTitle)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let store, let session {
            page(store, session: session)
        } else {
            ProgressView("正在读取推送设置…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("push.loading")
        }
    }

    private func page(_ store: PushSettingsModel, session: SessionContext) -> some View {
        // The records are not observable; the coordinator's revision says when they changed.
        _ = coordinator.revision
        let localID = coordinator.registeredDeviceID(serverID: session.serverID)
        let state = PushPresentation.localState(registeredID: localID, devices: store.deviceList)
        let local = store.deviceList.flatMap { PushPresentation.localDevice(registeredID: localID, in: $0) }
        let isBusy = requestedLocal != nil || coordinator.isUpdating || store.testingID != nil
        let controls = PushLocalControls(state: state, config: store.shownConfig, configPending: store.isConfigPending,
                                         listFailed: store.listFailed, isBusy: isBusy)
        let zone = session.site.serverTimeZone.timeZone
        return List {
            banners(store, session: session)
            PushLocalSection(isOn: requestedLocal ?? state.isToggleOn, controls: controls,
                             statusLine: local.map { PushPresentation.statusLine($0, timeZone: zone) },
                             permissionDenied: coordinator.authorization == .denied, errorText: localError,
                             isTesting: local.map { store.testingID == $0.id } ?? false, listFailed: store.listFailed,
                             onToggle: { setLocal($0, store: store, localID: localID) }, onOpenSystemSettings: openSystemSettings,
                             onTest: { if let local { test(local.id, store: store) } }, onRetry: { Task { await store.reloadDevices() } })
            if controls.showsSubscription, let local, let subscription = store.subscription(for: local.id) {
                PushSubscriptionSection(subscription: subscription, timezone: local.timezone, catalog: catalog, groups: model.groupDirectory,
                                        isSaving: store.isSavingSubscription(id: local.id)) { next in
                    Task { await store.updateSubscription(id: local.id, to: next) }
                }
            }
            PushTargetsSection(rows: PushPresentation.otherTargets(store.deviceList ?? [], localID: localID), listFailed: store.listFailed,
                               showsAdd: PushPresentation.showsAddTarget(isReadOnlyToken: session.isReadOnlyToken),
                               onAdd: { sheet = .addTarget }, onRetry: { Task { await store.reloadDevices() } })
            if let config = store.shownConfig {
                let editability = PushPresentation.apnsEditability(isReadOnlyToken: session.isReadOnlyToken, security: session.site.me.security,
                                                                   authMethod: session.site.authMethod)
                PushAPNsSection(rows: PushPresentation.apnsRows(config), editability: editability) {
                    if store.shownConfig != nil, editability.isAvailable { sheet = .apnsConfig }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.load() }
        .accessibilityIdentifier("push.list")
    }

    @ViewBuilder private func banners(_ store: PushSettingsModel, session: SessionContext) -> some View {
        if store.showsNotReadyBanner {
            PushNoticeBanner(text: PushPresentation.notReadyBanner, identifier: "push.banner.notReady")
        }
        if !coordinator.pendingDeletions(serverID: session.serverID).isEmpty {
            PushNoticeBanner(text: PushPresentation.pendingDeletionNotice, identifier: "push.pendingDeletion")
        }
        if store.refreshFailed {
            Section {
                Button { Task { await store.load() } } label: {
                    StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: PushPresentation.refreshFailed)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.devices.isLoading)
                .accessibilityLabel(PushPresentation.refreshFailed)
                .accessibilityIdentifier("push.refreshFailed")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Actions

    /// A new session gets a new model; coming back (from a target's page) reads the list again.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let store, storeGeneration == session.generation {
            await coordinator.refreshAuthorization()
            // Leaving cancelled the first read of the settings, or it failed: read both.
            if store.shownConfig == nil { await store.load() } else { await store.reloadDevices() }
            return
        }
        let source = await PushSettingsSources.make(model: model, context: session)
        let generation = session.generation
        guard generation == model.sessionGeneration else { return }
        let next = PushSettingsModel(source: source, receipts: model.receipts, isCurrent: { [weak model] in model?.sessionGeneration == generation })
        store = next; storeGeneration = generation
        requestedLocal = nil; localError = nil
        await coordinator.refreshAuthorization()
        await next.load()
    }

    /// 60 §7.4 / §7.5: a failed registration turns the switch back off with the reason; a refused permission shows 去设置.
    private func setLocal(_ isOn: Bool, store: PushSettingsModel, localID: Int?) {
        guard requestedLocal == nil else { return }
        requestedLocal = isOn
        localError = nil
        let coordinator = coordinator, config = store.shownConfig
        Task {
            if isOn {
                switch await coordinator.enableLocal(config: config) {
                case .enabled: await store.reloadDevices()
                case .notReady: localError = PushPresentation.localToggleNeedsAPNs
                case .failed(let text): localError = text
                case .permissionDenied, .cancelled: break
                }
            } else {
                switch await coordinator.disableLocal() {
                case .disabled:
                    if let localID { store.remove(id: localID) }
                    await store.reloadDevices()
                case .failed(let text): localError = text
                case .cancelled: break
                }
            }
            requestedLocal = nil
        }
    }

    /// 404 PUSH_DEVICE_NOT_FOUND: this phone's id is forgotten and the switch shows off (7.4).
    private func test(_ id: Int, store: PushSettingsModel) {
        let coordinator = coordinator
        Task { if await store.test(id: id) == .gone { coordinator.forgetLocalDevice() } }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }
}

/// The push page's own sheets; S6-25 replaces the placeholders.
enum PushSettingsSheet: String, Identifiable {
    case addTarget, apnsConfig
    var id: String { rawValue }
}

/// The endpoints, or under `-ui-testing` the fixture store, which also seeds the site's records once: callers read the
/// records after this returns (S6D2b-06).
enum PushSettingsSources {
    @MainActor static func make(model: AppModel, context: SessionContext) async -> any PushSettingsSource {
        guard model.isUITesting else { return context.client }
        return await DemoData.pushSettingsSource(serverID: context.serverID, records: model.pushRecords)
    }
}

/// A caution notice at the top of the page.
private struct PushNoticeBanner: View {
    let text: String
    let identifier: String

    var body: some View {
        Section {
            StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: text)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text)
                .accessibilityIdentifier(identifier)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }
}
