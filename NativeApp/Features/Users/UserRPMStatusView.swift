import SwiftUI
import Sub2Core

/// 30 §6.3 RPM 状态 · 本分钟: the user's total with its bar, then one line per group the user's keys use. Read while the block
/// is on screen and the App is in front, every 15 seconds (30 §6.6), and again on a pull (`refreshToken`). 501 (no RPM cache)
/// or an older server says “RPM 状态暂不可用”; other failures offer a retry, while a value already shown stays.
struct UserRPMStatusView: View {
    let userID: Int
    let refreshToken: Int
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = Load.loading
    @State private var visible = false

    private enum Load: Equatable { case loading, loaded(UserRPMStatus), unavailable, failed }
    private struct Poll: Equatable {
        let active: Bool
        let token: Int
    }
    private var context: UserRPMContext { UserRPMContext(me: model.siteSession?.me) }

    var body: some View {
        Section {
            content
                .onAppear { visible = true }
                .onDisappear { visible = false }
                .task(id: Poll(active: visible && scenePhase == .active, token: refreshToken)) { await poll() }
        } header: { Text(UserRPMPresentation.title) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("user-edit.rpm")
        case .unavailable:
            Text(UserRPMPresentation.unavailableText).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                .accessibilityIdentifier("user-edit.rpm.unavailable")
        case .failed:
            Button(UserRPMPresentation.failedText) { Task { await load() } }
                .frame(minHeight: 44)
                .accessibilityIdentifier("user-edit.rpm.retry")
        case .loaded(let status):
            VStack(alignment: .leading, spacing: 10) {
                totalLine(UserRPMPresentation.total(status, context: context))
                ForEach(status.perGroup) { row in groupLine(row) }
            }
            .padding(.vertical, 4)
            // A container keeps its lines' own identifiers.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("user-edit.rpm")
        }
    }

    private func totalLine(_ line: UserRPMLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(UserEditCopy.rpmTotalTitle).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(line.value).monospacedDigit().foregroundStyle(line.tone?.ink ?? Palette.ink1)
            }
            if let progress = line.progress {
                ProgressView(value: progress).tint(line.tone?.base ?? Palette.accent).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-edit.rpm.total")
    }
    private func groupLine(_ row: UserRPMStatus.Group) -> some View {
        let line = UserRPMPresentation.group(row, context: context)
        return HStack(spacing: 8) {
            Text(UserRPMPresentation.groupName(row)).foregroundStyle(Palette.ink1).lineLimit(1)
            if let label = line.label { Text(label).font(.caption).foregroundStyle(Palette.ink2) }
            Spacer(minLength: 8)
            Text(line.value).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-edit.rpm.group.\(row.groupID)")
    }

    /// Every 15 seconds while on screen and in front, from the first read on; leaving or the background cancels it.
    private func poll() async {
        guard visible, scenePhase == .active else { return }
        while !Task.isCancelled {
            await load()
            do { try await Task.sleep(for: UserEditPolicy.rpmRefreshInterval) } catch { return }
        }
    }
    private func load() async {
        let generation = model.sessionGeneration
        do {
            let reply = try await model.userRPMStatus(id: userID)
            guard generation == model.sessionGeneration else { return }
            switch reply {
            case .status(let status): state = .loaded(status)
            case .unavailable: state = .unavailable
            }
        } catch {
            guard generation == model.sessionGeneration, !(error is CancellationError) else { return }
            if case .loaded = state { return }
            state = .failed
        }
    }
}
