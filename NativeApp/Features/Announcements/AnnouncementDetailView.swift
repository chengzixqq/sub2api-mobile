import SwiftUI
import Sub2Core

/// 60 §16: one announcement. “公告” with its status and notify mode as subtitle and ··· on the right; the preview and button
/// row, 壹 投放 and 贰 档案. 发布 / 重新发布 confirm first, 归档 goes at once with 撤销, 删除 through the delete confirmation and
/// back to the list. AnnouncementDetailModel decides what to read and send; this view reports appearing, pulls, the
/// foreground and `model.announcementChanges`.
struct AnnouncementDetailView: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var detail: AnnouncementDetailModel?
    @State private var detailGeneration: UUID?
    @State private var confirmingPublish = false
    @State private var deleteRequest: DeleteRequest?
    /// Set once the delete went through; the page pops when its confirmation has closed.
    @State private var popsAfterDelete = false

    init(id: Int) { self.id = id }

    private var announcement: Announcement? { detail?.announcement }
    private var isReadOnly: Bool { session?.isReadOnlyToken ?? false }

    var body: some View {
        content
            .navigationTitle("公告")
            .navigationSubtitle(announcement.map { AnnouncementPresentation.detailSubtitle(status: $0.status, notifyMode: $0.notifyMode) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let detail, let announcement, !detail.isGone {
                    ToolbarItem(placement: .topBarTrailing) { moreMenu(announcement, detail: detail) }
                }
            }
            .task(id: session?.generation) { await appeared() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .onChange(of: model.announcementChanges.revision) { _, revision in Task { await detail?.noteRevision(revision) } }
            .onChange(of: model.foregroundRevision) { _, _ in Task { await detail?.load() } }
            .onChange(of: deleteRequest == nil) { _, closed in
                guard closed, popsAfterDelete else { return }
                popsAfterDelete = false
                dismiss()
            }
            .alert(publishConfirmation?.title ?? "", isPresented: $confirmingPublish, presenting: publishConfirmation) { _ in
                Button("发布") { Task { await publish() } }
                Button("取消", role: .cancel) {}
            } message: { Text($0.message) }
            .confirmDelete($deleteRequest)
    }

    @ViewBuilder private var content: some View {
        if let detail {
            if detail.isGone {
                ContentUnavailableView(AnnouncementDetailPresentation.gone, systemImage: "trash")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("announcement.detail.gone")
            } else {
                switch detail.detail.display {
                case .placeholder, .disabled: loading
                case .failed(let reason):
                    FailureView(message: reason ?? "") { Task { await detail.load() } }
                        .accessibilityElement(children: .contain).accessibilityIdentifier("announcement.detail.failure")
                case .value(let announcement, let at, _, let updateFailed):
                    page(announcement, detail: detail, updatedAt: at, refreshFailed: updateFailed)
                }
            }
        } else {
            loading
        }
    }

    /// 60 §16.5: a preview-shaped placeholder while the first read runs.
    private var loading: some View {
        AnnouncementPreviewCard(title: "公告标题", content: "公告正文的第一行\n公告正文的第二行", notifyMode: .silent)
            .redacted(reason: .placeholder)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: .systemGroupedBackground))
            .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在读取公告…")
        .accessibilityIdentifier("announcement.detail.loading")
    }

    private func page(_ announcement: Announcement, detail: AnnouncementDetailModel, updatedAt: Date?, refreshFailed: Bool) -> some View {
        let now = session?.client.serverClock.now() ?? Date()
        let zone = session?.site.serverTimeZone ?? .device
        let readLine = AnnouncementPresentation.detailReadLine(status: announcement.status, supportsReadStats: detail.readStatsEnabled,
                                                               summary: detail.summaryForDisplay, serverTimeZone: zone.timeZone)
        return List {
            if refreshFailed { refreshFailedBanner(updatedAt: updatedAt, zone: zone, detail: detail) }
            Section {
                AnnouncementDetailHeader(announcement: announcement, showsButtons: !isReadOnly, inFlight: detail.inFlight, isBusy: detail.isBusy,
                                         onAction: { perform($0, on: announcement, detail: detail) })
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            AnnouncementDeliverySection(announcement: announcement, targetText: targetText(announcement), readLine: readLine,
                                        zoneNote: AnnouncementDetailPresentation.scheduleZoneNote(device: .current, server: zone, at: now), now: now)
            AnnouncementArchiveSection(createdAt: announcement.createdAt, updatedAt: announcement.updatedAt, now: now, timeZone: zone.timeZone)
        }
        .listStyle(.insetGrouped)
        .refreshable { await detail.load() }
        .accessibilityIdentifier("announcement.detail")
    }

    /// 00 §4.6: the older detail stays; tapping reads again.
    private func refreshFailedBanner(updatedAt: Date?, zone: ServerTimeZone, detail: AnnouncementDetailModel) -> some View {
        let shown = updatedAt.map { $0.addingTimeInterval(session?.site.clockOffset ?? 0) }
        let line = shown.map { "更新于 " + DisplayFormat.clock($0, timeZone: zone.timeZone) }
        let title = AnnouncementDetailPresentation.refreshFailed
        return Section {
            Button { Task { await detail.load() } } label: {
                StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: title, detail: line)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(detail.detail.isLoading)
            .accessibilityLabel([title, line].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("announcement.detail.refreshFailed")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    private func moreMenu(_ announcement: Announcement, detail: AnnouncementDetailModel) -> some View {
        Menu {
            AnnouncementDetailMenu(title: AnnouncementPresentation.displayTitle(announcement.title),
                                   subtitle: AnnouncementPresentation.detailSubtitle(status: announcement.status, notifyMode: announcement.notifyMode),
                                   items: AnnouncementDetailPresentation.menuItems(for: announcement.status), isBusy: detail.isBusy) { item in
                select(item, on: announcement, detail: detail)
            }
        } label: {
            Label("更多操作", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("announcement.detail.more")
    }

    // MARK: - Actions

    private func select(_ item: AnnouncementMenuItem, on announcement: Announcement, detail: AnnouncementDetailModel) {
        switch item {
        case .edit: perform(.edit, on: announcement, detail: detail)
        case .write(let action): perform(action, on: announcement, detail: detail)
        case .reads: router.push(.announcementReads(announcementID: announcement.id))
        case .delete: confirmDelete(announcement, detail: detail)
        }
    }
    private func perform(_ action: AnnouncementDetailAction, on announcement: Announcement, detail: AnnouncementDetailModel) {
        switch action {
        case .edit: router.present(.announcementEdit(id: announcement.id))
        case .publish, .republish: confirmingPublish = true
        case .archive: Task { await detail.archive() }
        }
    }
    /// A cleared compliance or step-up check brings the confirmation back (00 §2.6.2); the model has said so.
    private func publish() async {
        guard let detail, await detail.publish() == .reconfirm else { return }
        confirmingPublish = true
    }
    /// 60 §0.4: the whole title is typed (or Face ID); 404 counts as deleted.
    private func confirmDelete(_ announcement: Announcement, detail: AnnouncementDetailModel) {
        let name = AnnouncementPresentation.displayTitle(announcement.title)
        let receipts = model.receipts
        deleteRequest = DeleteRequest(objectNoun: "公告", displayName: name, siteName: model.activeProfile?.name ?? "") {
            await detail.delete {
                receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: "公告", displayName: name), systemImage: "trash"))
                popsAfterDelete = true
            }
        }
    }

    private var publishConfirmation: AnnouncementPublishConfirmation? {
        guard let announcement else { return nil }
        let now = session?.client.serverClock.now() ?? Date()
        return AnnouncementPresentation.publishConfirmation(title: announcement.title, targetText: targetText(announcement),
                                                           notifyMode: announcement.notifyMode, startsAt: announcement.startsAt,
                                                           endsAt: announcement.endsAt, now: now, timeZone: .current)
    }
    private func targetText(_ announcement: Announcement) -> String {
        AnnouncementPresentation.targetText(announcement.targeting, groupNames: { model.groupDirectory?.name(for: $0) })
    }

    /// A new session gets a new model; back from 已读情况 it reads only what leaving cancelled.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if detailGeneration != session.generation {
            let generation = session.generation
            detail = AnnouncementDetailModel(id: id, source: model.announcementDetailSource(for: session),
                                             readStatsEnabled: session.has(.announcementsReadStats), receipts: model.receipts,
                                             signal: model.announcementChanges, isCurrent: { [weak model] in model?.sessionGeneration == generation })
            detailGeneration = generation
        }
        await detail?.loadIfNeeded()
    }
}

extension AppModel {
    /// The site's announcement, or under `-ui-testing` this session's AnnouncementDemoStore (shared with the list).
    func announcementDetailSource(for session: SessionContext) -> AnnouncementDetailSource {
        guard isUITesting else { return .live(session.client) }
        return .fixture(AnnouncementDemoStore.current(for: session.generation, base: session.client.serverClock.now()))
    }
}
