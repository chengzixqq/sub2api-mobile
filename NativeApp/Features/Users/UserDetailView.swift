import SwiftUI
import Sub2Core

/// 30 §2: one user, by id (`.user(id:)` from the list, the strip, the overview, search and the logs). Title the display name,
/// subtitle the email, ⋯ on the right. The blocks load together and fail on their own; while shown in the foreground the
/// profile and today's spend are read every 60 seconds (30 §2.6). UserDetailModel holds the state; this view decides when.
struct UserDetailView: View {
    let userID: Int
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var detail: UserDetailModel?
    @State private var detailGeneration: UUID?
    @State private var visible = false
    @State private var editorTarget: UserEditorTarget?
    @State private var deleteRequest: DeleteRequest?

    private var shouldPoll: Bool { visible && scenePhase == .active && detail != nil }

    var body: some View {
        content
            .confirmDelete($deleteRequest)
            .navigationTitle(detail?.user?.displayName ?? UserDetailPresentation.loadingTitle)
            .navigationSubtitle(detail?.user?.email ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let detail, let user = detail.user, !detail.isMissing {
                    ToolbarItem(placement: .topBarTrailing) { menu(detail, user: user) }
                }
            }
            .task(id: session?.generation) { await appeared() }
            .task(id: shouldPoll) { await poll() }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            // A read stopped by the background is read again on return (D18).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await detail?.loadAll() } }
            .onChange(of: model.userChanges?.revision(userID: userID) ?? 0) { _, _ in Task { await detail?.reloadAfterChange() } }
            // 30 §2.4: the page pops once the confirmation has closed; the row and the receipt are already done.
            .onChange(of: deleteRequest == nil) { _, closed in if closed, detail?.didDelete == true { dismiss() } }
            .sheet(item: $editorTarget, onDismiss: { Task { await detail?.reloadAfterEdit() } }) { UserEditorView(target: $0) }
    }

    @ViewBuilder private var content: some View {
        if let detail {
            if detail.isMissing {
                notFound
            } else {
                switch detail.profile.state.display {
                case .placeholder, .disabled:
                    UserDetailSkeleton()
                case .failed(let reason):
                    failure(reason, detail: detail)
                case .value(let user, _, _, _):
                    UserDetailContent(detail: detail, user: user, timeZone: session?.site.serverTimeZone ?? .device,
                                      onEnable: { Task { await detail.setStatus(enable: true) } },
                                      onBalance: { router.present(.balanceKeypad(userID: userID, mode: $0)) })
                        .refreshable { await detail.loadAll() }
                }
            }
        } else {
            UserDetailSkeleton()
        }
    }

    // MARK: - ⋯

    /// 30 §2.4: every item writes, so a read-only token greys them all; the system menu shows no identifiers, so tests find the
    /// items by their words.
    private func menu(_ detail: UserDetailModel, user: AdminUser) -> some View {
        Menu {
            ForEach(UserDetailPresentation.menuItems(for: user), id: \.self) { item in
                Button(role: item.isDestructive ? .destructive : nil) { perform(item, detail: detail, user: user) } label: { Text(item.title) }
                    .disabled(detail.isWritingStatus && item != .edit && item != .compensation)
                    .readOnlyGate(showsCaption: false)
            }
            if let note = UserDetailPresentation.menuNote(for: user, isSelf: detail.isSelf) {
                Section { Text(note) }
            }
        } label: {
            Label("更多操作", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("user.more")
    }

    private func perform(_ item: UserDetailMenuItem, detail: UserDetailModel, user: AdminUser) {
        switch item {
        case .edit:
            // S3-11 replaces the old editor sheet with `.userEdit(id:)`.
            guard let session, session.generation == model.sessionGeneration else { return }
            editorTarget = UserEditorTarget(user: user, context: session, siteName: model.activeProfile?.name ?? "")
        case .setStatus(let enable):
            Task { await detail.setStatus(enable: enable) }
        case .compensation:
            // 60 §19.1; the sheet bumps `userChanges` when it grants, which reloads this page.
            router.present(.redeemGrant(userID: userID, pendingID: nil))
        case .delete:
            deleteRequest = detail.deleteRequest(siteName: model.activeProfile?.name ?? "")
        }
    }

    // MARK: - States

    private func failure(_ reason: String?, detail: UserDetailModel) -> some View {
        ContentUnavailableView {
            Label(UserDetailPresentation.loadFailed, systemImage: "exclamationmark.triangle").accessibilityIdentifier("user.detail.error")
        } description: { Text(reason ?? "") } actions: {
            Button("重试") { Task { await detail.loadAll() } }
                .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("user.detail.retry")
        }
    }
    private var notFound: some View {
        ContentUnavailableView {
            Label(UserDetailPresentation.notFound, systemImage: "person.crop.circle.badge.xmark").accessibilityIdentifier("user.detail.not-found")
        } actions: {
            Button("返回") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("user.detail.back")
        }
    }

    // MARK: - When to read

    /// A new session gets a new model and reads everything; coming back from a pushed page reads only what it interrupted.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let detail, detailGeneration == session.generation {
            await detail.resumeIfInterrupted()
            return
        }
        let created = UserDetailModel(app: model, userID: userID)
        detail = created
        detailGeneration = session.generation
        await created.loadAll()
    }
    /// Checks again on waking: a pull or a failure moved the next read (00 §4.6).
    private func poll() async {
        guard shouldPoll, let detail else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(max(1, detail.nextLiveDelay()))) } catch { return }
            await detail.refreshLive()
        }
    }
}

/// The loaded page: the banners, the balance header and the three numbered sections.
private struct UserDetailContent: View {
    let detail: UserDetailModel
    let user: AdminUser
    let timeZone: ServerTimeZone
    let onEnable: () -> Void
    let onBalance: (BalanceKeypadMode) -> Void

    var body: some View {
        List {
            // 待核对横幅：S3-07
            if user.status == "disabled" {
                Section {
                    UserDisabledBanner(isWorking: detail.isWritingStatus, onEnable: onEnable)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            Section {
                UserBalanceHero(detail: detail, user: user, onTopUp: { onBalance(.topup) }, onRefund: { onBalance(.refund) })
            }
            UserKeySummarySection(detail: detail, displayName: user.displayName)
            UserLedgerPeekSection(detail: detail, timeZone: timeZone, now: detail.serverNow)
            UserProfileSection(rows: UserDetailPresentation.profileRows(user, isSelf: detail.isSelf))
        }
        .accessibilityIdentifier("user.detail")
    }
}
