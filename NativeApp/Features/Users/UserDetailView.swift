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
    @State private var deleteRequest: DeleteRequest?
    /// This user's editor went onto the stack above; the next appearance reads the profile, the keys and the records (30 §2.6).
    @State private var returnsFromEditor = false
    /// 30 §3.4: the pending banner's checks and their dialogs (S3-07).
    @State private var reconcileFlow = BalanceReconcileFlow()
    /// R03's first confirmation before the keypad (S3-08).
    @State private var balanceEntry: BalanceKeypadEntry?
    /// X38: “上一次补偿的发放结果未确认” before the compensation sheet (S6-09).
    @State private var grantBlock: GrantBlockPrompt?

    private var shouldPoll: Bool { visible && scenePhase == .active && detail != nil }
    /// `.userEdit` of this user, any segment, on the stack in front: the key summary's push and ⋯ 编辑用户 (S3-11).
    private var editorAbove: Bool {
        router.path(for: router.selectedTab).contains { if case .userEdit(let id, _) = $0 { id == userID } else { false } }
    }

    var body: some View {
        content
            .confirmDelete($deleteRequest)
            .balanceReconcileFlow(reconcileFlow)
            .balanceKeypadEntry($balanceEntry) { [reconcileFlow, model, detail] op in
                Task { await reconcileFlow.reconcile(op, model: model, balance: detail?.user?.balance) }
            }
            .redeemGrantBlockAlert($grantBlock, userID: userID, router: router)
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
            .onChange(of: editorAbove) { _, above in if above { returnsFromEditor = true } }
            // A read stopped by the background is read again on return (D18).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await detail?.loadAll() } }
            .onChange(of: model.userChanges?.revision(userID: userID) ?? 0) { _, _ in Task { await detail?.reloadAfterChange() } }
            // 30 §2.4: the page pops once the confirmation has closed; the row and the receipt are already done.
            .onChange(of: deleteRequest == nil) { _, closed in if closed, detail?.didDelete == true { dismiss() } }
    }

    @ViewBuilder private var content: some View {
        if let detail {
            if detail.isMissing {
                pendingBanner(over: notFound)
            } else {
                switch detail.profile.state.display {
                case .placeholder, .disabled:
                    UserDetailSkeleton()
                case .failed(let reason):
                    pendingBanner(over: failure(reason, detail: detail))
                case .value(let user, _, _, _):
                    UserDetailContent(detail: detail, user: user, timeZone: session?.site.serverTimeZone ?? .device, reconcileFlow: reconcileFlow,
                                      topUpHeldBack: BalanceKeypadEntry.holdsBack(userID: userID, mode: .topup, model: model),
                                      onEnable: { Task { await detail.setStatus(enable: true) } },
                                      onBalance: { balanceEntry = BalanceKeypadEntry.open(userID: userID, mode: $0, model: model, router: router) })
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
            router.push(.userEdit(id: userID))
        case .setStatus(let enable):
            Task { await detail.setStatus(enable: enable) }
        case .compensation:
            // 60 §19.1, X38: a compensation of this user awaiting its check asks first; the sheet bumps `userChanges` when it
            // grants, which reloads this page.
            grantBlock = RedeemGrantEntry.open(userID: userID, model: model, router: router, timeZone: (session?.site.serverTimeZone ?? .device).timeZone)
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
    /// The banner is the only place a pending record is checked or abandoned, so it stays over a deleted user and a failed
    /// profile; a set's Face ID amount is then unknown (D26).
    private func pendingBanner(over state: some View) -> some View {
        state.safeAreaInset(edge: .top, spacing: 0) {
            if model.hasPendingBanner(userID: userID) {
                PendingBalanceBanner(userID: userID, balance: nil, flow: reconcileFlow)
                    .padding(.horizontal).padding(.top, 8)
            }
        }
    }

    // MARK: - When to read

    /// A new session gets a new model and reads everything; coming back from a pushed page reads only what it interrupted, and
    /// from the editor also the profile, the keys and the records. A read cut short by another push is read on the next return.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if let detail, detailGeneration == session.generation {
            await detail.resumeIfInterrupted(afterEditor: returnsFromEditor)
            if !Task.isCancelled { returnsFromEditor = false }
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
    let reconcileFlow: BalanceReconcileFlow
    /// 30 §3.4: 充值 loses its fill while a top-up awaits its check.
    let topUpHeldBack: Bool
    let onEnable: () -> Void
    let onBalance: (BalanceKeypadMode) -> Void

    var body: some View {
        List {
            PendingBalanceBanner(userID: user.id, balance: user.balance, flow: reconcileFlow)
            if user.status == "disabled" {
                Section {
                    UserDisabledBanner(isWorking: detail.isWritingStatus, onEnable: onEnable)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            Section {
                UserBalanceHero(detail: detail, user: user, topUpIsSecondary: topUpHeldBack, onTopUp: { onBalance(.topup) }, onRefund: { onBalance(.refund) })
            }
            UserKeySummarySection(detail: detail, displayName: user.displayName)
            UserLedgerPeekSection(detail: detail, timeZone: timeZone, now: detail.serverNow)
            UserProfileSection(rows: UserDetailPresentation.profileRows(user, isSelf: detail.isSelf))
        }
        .accessibilityIdentifier("user.detail")
    }
}
