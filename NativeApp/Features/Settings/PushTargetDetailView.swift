import SwiftUI
import Sub2Core

/// 60 §7.1 / §7.4 (S6-24): one of the other targets — its state, 推送内容, 发送测试推送 and, last, the red “删除接收方式…”
/// through the delete confirmation, back to the push page with a receipt; 404 counts as deleted. No swipe to delete. This
/// phone's target is turned off with the switch, so its page has no delete row.
struct PushTargetDetailView: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var store: PushSettingsModel?
    @State private var storeGeneration: UUID?
    @State private var catalog: MetaCatalog = .builtin
    @State private var deleteRequest: DeleteRequest?
    /// Set once the delete went through; the page pops when its confirmation has closed.
    @State private var popsAfterDelete = false

    init(id: Int) { self.id = id }

    private var device: PushDevice? { store?.device(id: id) }

    var body: some View {
        content
            .navigationTitle(device.map(PushPresentation.targetName) ?? PushPresentation.targetObjectNoun)
            .navigationSubtitle(device.map(PushPresentation.platformTitle) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .task(id: session?.generation) { catalog = await model.metaCatalog() }
            .onChange(of: model.foregroundRevision) { _, _ in Task { await store?.reloadDevices() } }
            .onChange(of: deleteRequest == nil) { _, closed in
                guard closed, popsAfterDelete else { return }
                popsAfterDelete = false
                dismiss()
            }
            .confirmDelete($deleteRequest)
    }

    @ViewBuilder private var content: some View {
        if let store, let session {
            switch store.devices.display {
            case .placeholder, .disabled: loading
            case .failed(let reason): FailureView(message: reason ?? "") { Task { await store.reloadDevices() } }
            case .value:
                if let device { page(device, store: store, session: session) } else { gone }
            }
        } else {
            loading
        }
    }

    private var loading: some View {
        ProgressView("正在读取接收方式…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("push.target.loading")
    }
    private var gone: some View {
        ContentUnavailableView(PushPresentation.targetGone, systemImage: "bell.slash")
            .accessibilityElement(children: .combine).accessibilityIdentifier("push.target.gone")
    }

    private func page(_ device: PushDevice, store: PushSettingsModel, session: SessionContext) -> some View {
        let isLocal = model.pushCoordinator.registeredDeviceID(serverID: session.serverID) == device.id
        let statusLine = PushPresentation.statusLine(device, now: session.client.serverClock.now(), timeZone: session.site.serverTimeZone.timeZone)
        return List {
            Section {
                PushTargetRowLabel(row: PushPresentation.targetRow(device), statusLine: statusLine)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("push.target.header")
            }
            if let subscription = store.subscription(for: device.id) {
                PushSubscriptionSection(subscription: subscription, timezone: device.timezone, catalog: catalog, groups: model.groupDirectory,
                                        isSaving: store.isSavingSubscription(id: device.id)) { next in
                    Task { await store.updateSubscription(id: device.id, to: next) }
                }
            }
            Section {
                Button { test(device.id, store: store, isLocal: isLocal) } label: {
                    HStack {
                        Text(PushPresentation.sendTest)
                        Spacer(minLength: 8)
                        if store.testingID == device.id { ProgressView() }
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .disabled(store.testingID != nil || store.deletingID != nil)
                .accessibilityIdentifier("push.target.test")
            }
            Section {
                if isLocal {
                    Text(PushPresentation.localTargetDeleteHint).font(.footnote).foregroundStyle(Palette.ink2)
                        .accessibilityIdentifier("push.target.localHint")
                } else {
                    Button(role: .destructive) { confirmDelete(device, store: store) } label: {
                        Text(PushPresentation.deleteTargetRow).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .disabled(store.deletingID != nil)
                    .accessibilityIdentifier("push.target.delete")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reloadDevices() }
        .accessibilityIdentifier("push.target.list")
    }

    // MARK: - Actions

    /// A new session gets a new model; the list is read on every appearance.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let store, storeGeneration == session.generation {
            await store.reloadDevices()
            return
        }
        let source = await PushSettingsSources.make(model: model, context: session)
        let generation = session.generation
        guard generation == model.sessionGeneration else { return }
        let next = PushSettingsModel(source: source, receipts: model.receipts, isCurrent: { [weak model] in model?.sessionGeneration == generation })
        store = next; storeGeneration = generation
        await next.reloadDevices()
    }

    /// 404: the page goes back, and the push page reads the list again (7.4).
    private func test(_ id: Int, store: PushSettingsModel, isLocal: Bool) {
        let coordinator = model.pushCoordinator
        Task {
            guard await store.test(id: id) == .gone else { return }
            if isLocal { coordinator.forgetLocalDevice() }
            dismiss()
        }
    }

    /// 60 §7.4: the name (device_name, else the host) is typed, or Face ID; the receipt shows as the page pops.
    private func confirmDelete(_ device: PushDevice, store: PushSettingsModel) {
        let name = PushPresentation.targetName(device), noun = PushPresentation.targetObjectNoun
        let receipts = model.receipts
        deleteRequest = DeleteRequest(objectNoun: noun, displayName: name, siteName: model.activeProfile?.name ?? "",
                                      consequences: [PushPresentation.deleteTargetConsequence]) {
            guard await store.delete(id: device.id) == .deleted else { return }
            receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: noun, displayName: name), systemImage: "trash"))
            popsAfterDelete = true
        }
    }
}
