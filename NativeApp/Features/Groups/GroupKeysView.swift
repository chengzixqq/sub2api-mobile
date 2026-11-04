import SwiftUI
import Sub2Core

/// 50 §6 (.groupKeys): the group's keys, newest first, 20 a page; read-only, a row opens its owner (.user). Never polls; each page's
/// today spend is read once it arrives (GroupKeysModel), never with a read-only token (R14).
struct GroupKeysView: View {
    let groupID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var keys: GroupKeysModel?
    @State private var keysGeneration: UUID?
    @State private var moreAttempt = 0

    var body: some View {
        content
            .navigationTitle(GroupRecordsCopy.keysTitle)
            .navigationSubtitle(keys?.subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            .onChange(of: model.foregroundRevision) { _, _ in
                moreAttempt += 1
                Task { await keys?.start() }
            }
    }

    @ViewBuilder private var content: some View {
        if let keys, let session {
            if keys.page == .deleted {
                GroupRecordsDeletedView(id: "group.keys.deleted")
            } else {
                GroupKeysList(keys: keys, timeZone: session.site.serverTimeZone, now: session.client.serverClock.now(), moreAttempt: moreAttempt)
            }
        } else {
            List { GroupRecordsSkeleton(id: "group.keys.skeleton") }
        }
    }

    /// A new session gets a new model; shown again (back from a user) it reads only what never answered.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if keysGeneration != session.generation {
            let generation = session.generation, clock = session.client.serverClock
            keys = GroupKeysModel(groupID: groupID, snapshot: model.groupStore?.group(id: groupID) ?? model.groupDirectory?.group(id: groupID),
                                  source: GroupRecordsSource.make(model, session: session),
                                  isReadOnlyToken: { [weak model] in model?.siteSession?.isReadOnlyToken != false },
                                  isCurrent: { [weak model] in model?.sessionGeneration == generation }, now: { clock.now() })
            keysGeneration = generation
        }
        await keys?.start()
    }
}

private struct GroupKeysList: View {
    let keys: GroupKeysModel
    let timeZone: ServerTimeZone
    let now: Date
    let moreAttempt: Int

    var body: some View {
        List {
            switch keys.page {
            case .skeleton: GroupRecordsSkeleton(id: "group.keys.skeleton")
            case .failure: failure
            case .content, .deleted: rows
            }
        }
        .refreshable { await keys.reload() }
        .accessibilityIdentifier("group.keys.list")
    }

    private var failure: some View {
        let pager = keys.pager
        return BlockFailureRow(title: GroupRecordsCopy.failureTitle(pager.lastError), error: pager.lastError, refresh: pager.refresh,
                               id: "group.keys.list") { Task { await keys.reload() } }
    }

    @ViewBuilder private var rows: some View {
        let pager = keys.pager
        if case .failed = pager.state {
            GroupRecordsRefreshRow(updatedAt: pager.state.updatedAt, timeZone: timeZone, refresh: pager.refresh, id: "group.keys.refresh.retry") {
                Task { await keys.reload() }
            }
        }
        if keys.hasStaleToday {
            GroupRecordsRefreshRow(title: GroupRecordsCopy.todayStale, systemImage: GroupRecordsRefreshRow.staleImage, updatedAt: nil, timeZone: timeZone,
                                   refresh: keys.todayRefresh, isRefreshing: keys.isRetryingToday, id: "group.keys.today.retry") { keys.retryToday() }
        }
        Section {
            if let feed = pager.feed {
                if feed.rows.isEmpty {
                    GroupRecordsEmptyRow(text: GroupRecordsCopy.keysEmpty, id: "group.keys.empty")
                } else {
                    keyRows(feed.rows)
                    if let hint = feed.moreHint(unit: GroupRecordsCopy.keysUnit) {
                        GroupRecordsMoreFooter(hint: hint, state: pager.nextPage, page: feed.nextPage, attempt: moreAttempt, idPrefix: "group.keys",
                                               load: { await keys.loadMore() }, retry: { await keys.retryMore() })
                    }
                }
            }
        } header: {
            GroupRecordsListHead(leading: GroupRecordsCopy.keysHeadLeading, trailing: GroupRecordsCopy.keysHeadTrailing, id: "group.keys.head")
        } footer: {
            Text(GroupRecordsCopy.keysFootnote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("group.keys.footnote")
        }
    }

    @ViewBuilder private func keyRows(_ items: [AdminAPIKey]) -> some View {
        let rows = items.map { GroupKeyRow($0, today: keys.today(for: $0.id), now: now, timeZone: timeZone) }
        let positions = RailPosition.positions(of: rows) { $0.railTone?.drawsRail == true }
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            GroupRecordsRowLink(userID: row.userID, spokenLabel: row.spokenLabel, id: "group.key.\(row.id)") {
                GroupKeyRowView(row: row, railPosition: positions[index])
            }
        }
    }
}

/// 50 §6.3: the key glyph; name and status badge, the mask on the right; owner · last used and today's spend; the quota bar when
/// the key has one. Exhausted keys ride the caution rail; stopped and expired keys are dimmed. A today amount kept through a failed
/// read says 更新失败 in the caution ink; the strip above the rows reads it again (S5-高-3).
private struct GroupKeyRowView: View {
    let row: GroupKeyRow
    let railPosition: RailPosition?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key").font(.subheadline).foregroundStyle(Palette.ink3).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1)
                    if let badge = row.badge { ToneBadge(text: badge, tone: row.badgeTone) }
                    Spacer(minLength: 8)
                    Text(row.mask).font(.footnote.monospaced()).foregroundStyle(Palette.ink2).lineLimit(1).fixedSize()
                }
                HStack(spacing: 8) {
                    Text(row.secondLine).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(row.today.text).monospacedDigit().lineLimit(1).fixedSize()
                        .foregroundStyle(row.today.isStale ? Tone.caution.ink : Palette.ink2)
                        .redacted(reason: row.today == .pending ? .placeholder : [])
                }
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                if let quota = row.quota { CapacityBar(quota) }
            }
        }
        .opacity(row.isDimmed ? 0.6 : 1)
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .statusCapsule(tone: railPosition == nil ? nil : row.railTone, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spokenLabel))
    }
}
