import SwiftUI
import Sub2Core

/// 60 §5: the account's signed-in devices. This device has no swipe and only explains how to sign out (U50); another device
/// goes after a confirmation. 让其他所有设备下线 reloads the list: a pre-deployment session (no sid) is revoked with the
/// others, and the reload's 401 then takes this device to the login page (BACKLOG). No step-up, no idempotency key, no polling.
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var list = LoadState<[AuthSessionItem]>()
    /// Revoked rows stay hidden even when a later reload fails and the older list is shown.
    @State private var removedIDs: Set<String> = []
    @State private var revoking: AuthSessionItem?
    @State private var confirmsRevokeOthers = false
    @State private var showsCurrentNote = false
    @State private var isWriting = false
    @State private var writingID: String?

    var body: some View {
        content
            .navigationTitle("登录设备")
            .navigationSubtitle(model.activeProfile?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task { await reload() }
            // A read stopped by the background is read again on return (D18).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await reload() } }
            .confirmationDialog(AuthSessionItem.revokeTitle(revoking?.displayTitle ?? ""), isPresented: revokingBinding, titleVisibility: .visible,
                                presenting: revoking) { item in
                Button(AuthSessionItem.revokeActionTitle, role: .destructive) { Task { await revoke(item) } }
            } message: { _ in Text(AuthSessionItem.revokeMessage) }
            .confirmationDialog(AuthSessionItem.revokeOthersTitle(count: AuthSessionItem.otherDeviceCount(in: shownItems)),
                                isPresented: $confirmsRevokeOthers, titleVisibility: .visible) {
                Button(AuthSessionItem.revokeOthersConfirmTitle, role: .destructive) { Task { await revokeOthers() } }
            } message: { Text(AuthSessionItem.revokeOthersMessage) }
            .alert(AuthSessionItem.currentDeviceNoteTitle, isPresented: $showsCurrentNote) {
                Button("知道了", role: .cancel) {}
            } message: { Text(AuthSessionItem.currentDeviceNoteMessage) }
    }

    private var shownItems: [AuthSessionItem] { (list.value ?? []).filter { !removedIDs.contains($0.id) } }
    private var revokingBinding: Binding<Bool> { Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }) }

    @ViewBuilder private var content: some View {
        switch list.state.display {
        case .placeholder:
            ProgressView("正在读取登录设备…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("sessions.loading")
        case .failed(let reason):
            FailureView(message: reason ?? "") { Task { await reload() } }
        case .value, .disabled:
            sessionList
        }
    }

    private var sessionList: some View {
        let items = shownItems
        let now = session?.client.serverClock.now() ?? Date()
        let timeZone = session?.site.serverTimeZone.timeZone ?? .current
        return List {
            Section { ForEach(items) { row($0, now: now, timeZone: timeZone) } }
            Section {
                if AuthSessionItem.otherDeviceCount(in: items) > 0 { revokeOthersButton } else {
                    Text(AuthSessionItem.noOtherDevicesText).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                        .accessibilityIdentifier("sessions.noOthers")
                }
            } footer: {
                Text(AuthSessionItem.footnote).accessibilityIdentifier("sessions.footnote")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
        .accessibilityIdentifier("sessions.list")
    }

    private var revokeOthersButton: some View {
        Button { confirmsRevokeOthers = true } label: {
            HStack {
                Text(AuthSessionItem.revokeOthersButtonTitle).foregroundStyle(Tone.critical.ink)
                Spacer(minLength: 8)
                if isWriting && writingID == nil { ProgressView() }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWriting)
        .accessibilityIdentifier("sessions.revokeOthers")
    }

    @ViewBuilder private func row(_ item: AuthSessionItem, now: Date, timeZone: TimeZone) -> some View {
        let activity = item.activityLine(now: now, timeZone: timeZone), lifetime = item.lifetimeLine(timeZone: timeZone)
        let parts: [String?] = [item.displayTitle, item.current ? AuthSessionItem.currentBadgeText : nil, DisplayFormat.spoken(activity),
                                DisplayFormat.spoken(lifetime)]
        let spoken = parts.compactMap { $0 }.joined(separator: "，")
        if item.current {
            Button { showsCurrentNote = true } label: { rowContent(item, activity: activity, lifetime: lifetime) }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken)
                .accessibilityIdentifier("sessions.row.\(item.id)")
        } else {
            rowContent(item, activity: activity, lifetime: lifetime)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityIdentifier("sessions.row.\(item.id)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // A tint rather than the destructive role, which would start removing the row before the confirmation.
                    Button(AuthSessionItem.revokeActionTitle) { revoking = item }
                        .tint(Tone.critical.base)
                        .disabled(isWriting)
                        .accessibilityIdentifier("sessions.revoke.\(item.id)")
                }
        }
    }

    private func rowContent(_ item: AuthSessionItem, activity: String, lifetime: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.iconName).font(.title3).foregroundStyle(Palette.ink2).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayTitle).font(.headline).foregroundStyle(Palette.ink1).lineLimit(1)
                    if item.current { ToneBadge(text: AuthSessionItem.currentBadgeText, tone: .neutral) }
                }
                Text(activity).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                Text(lifetime).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if writingID == item.id { ProgressView() }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func reload() async {
        guard let context = session, context.generation == model.sessionGeneration else { return }
        let source = SessionsSource(model: model, context: context)
        await list.load(isCurrent: { context.generation == model.sessionGeneration }) { try await source.list() }
    }

    /// 60 §5.4: removed with a receipt, or silently when already gone; this device's own session signs it out.
    private func revoke(_ item: AuthSessionItem) async {
        guard let context = session, context.generation == model.sessionGeneration, !isWriting else { return }
        isWriting = true; writingID = item.id
        let outcome: Result<Bool, any Error>
        do { outcome = .success(try await SessionsSource(model: model, context: context).revoke(id: item.id)) }
        catch { outcome = .failure(error) }
        isWriting = false; writingID = nil
        guard context.generation == model.sessionGeneration else { return }
        switch outcome {
        case .success(true):
            await model.forgetActiveSession(notice: AuthSessionItem.signedOutNotice)
            return
        case .success(false):
            removedIDs.insert(item.id)
            model.receipts.show(Receipt(text: AuthSessionItem.revokedReceipt(item.displayTitle)))
        case .failure(let error) where AuthSessionItem.isAlreadyGone(error):
            removedIDs.insert(item.id)
        case .failure(let error):
            report(error)
            return
        }
        await reload()
    }

    private func revokeOthers() async {
        guard let context = session, context.generation == model.sessionGeneration, !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        do { try await SessionsSource(model: model, context: context).revokeOthers() }
        catch {
            if context.generation == model.sessionGeneration { report(error) }
            return
        }
        guard context.generation == model.sessionGeneration else { return }
        await reload()
    }

    /// An ended session is the client's to report: the page is about to give way to the login page.
    private func report(_ error: any Error) {
        guard SessionInvalidation(error: error) == nil else { return }
        model.report(error)
    }
}

/// The endpoints, or the `-ui-testing` fixture in SettingsModuleFixtures.
private struct SessionsSource: Sendable {
    let model: AppModel
    let context: SessionContext

    @MainActor func list() async throws -> [AuthSessionItem] {
        guard model.isUITesting else { return try await context.client.sessions() }
        return try await fixture { try DemoData.authSessions(generation: context.generation) }
    }
    @MainActor func revoke(id: String) async throws -> Bool {
        guard model.isUITesting else { return try await context.client.revokeSession(id: id) }
        return try await fixture { try DemoData.revokeAuthSession(id: id, generation: context.generation) }
    }
    @MainActor func revokeOthers() async throws {
        guard model.isUITesting else { return try await context.client.revokeOtherSessions() }
        DemoData.revokeOtherAuthSessions(generation: context.generation)
    }
    /// Stands in for the client's report of an ended session (D06), as AppModel.users does for `-ui-session-revoked`.
    @MainActor private func fixture<Value>(_ read: () throws -> Value) async throws -> Value {
        do { return try read() } catch {
            guard let invalidation = SessionInvalidation(error: error) else { throw error }
            await model.invalidateSession(invalidation, serverID: context.serverID, generation: context.generation)
            throw CancellationError()
        }
    }
}
