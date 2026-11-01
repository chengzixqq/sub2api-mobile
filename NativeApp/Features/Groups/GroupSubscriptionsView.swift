import SwiftUI
import Sub2Core

/// 50 §7 (.groupSubscriptions): the group's subscriptions, newest assignment first, 20 a page; read-only, a row opens the user.
/// Never polls. The limits come from the group, the active count from groups/:id/stats (GroupSubscriptionsModel).
struct GroupSubscriptionsView: View {
    let groupID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var subscriptions: GroupSubscriptionsModel?
    @State private var subscriptionsGeneration: UUID?
    @State private var moreAttempt = 0

    var body: some View {
        content
            .navigationTitle(GroupRecordsCopy.subscriptionsTitle)
            .navigationSubtitle(subscriptions?.subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            .onChange(of: model.foregroundRevision) { _, _ in
                moreAttempt += 1
                Task { await subscriptions?.start() }
            }
    }

    @ViewBuilder private var content: some View {
        if let subscriptions, let session {
            if subscriptions.page == .deleted {
                GroupRecordsDeletedView(id: "group.subs.deleted")
            } else {
                GroupSubscriptionsList(subscriptions: subscriptions, timeZone: session.site.serverTimeZone, now: session.client.serverClock.now(),
                                       moreAttempt: moreAttempt)
            }
        } else {
            List { GroupRecordsSkeleton(id: "group.subs.skeleton") }
        }
    }

    /// A new session gets a new model; shown again (back from a user) it reads only what never answered.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if subscriptionsGeneration != session.generation {
            let generation = session.generation, clock = session.client.serverClock
            subscriptions = GroupSubscriptionsModel(groupID: groupID,
                                                    snapshot: model.groupStore?.group(id: groupID) ?? model.groupDirectory?.group(id: groupID),
                                                    source: GroupRecordsSource.make(model, session: session),
                                                    isCurrent: { [weak model] in model?.sessionGeneration == generation }, now: { clock.now() })
            subscriptionsGeneration = generation
        }
        await subscriptions?.start()
    }
}

private struct GroupSubscriptionsList: View {
    let subscriptions: GroupSubscriptionsModel
    let timeZone: ServerTimeZone
    let now: Date
    let moreAttempt: Int

    var body: some View {
        List {
            switch subscriptions.page {
            case .skeleton: GroupRecordsSkeleton(id: "group.subs.skeleton")
            case .failure: failure
            case .content, .deleted: rows
            }
        }
        .refreshable { await subscriptions.reload() }
        .accessibilityIdentifier("group.subs.list")
    }

    private var failure: some View {
        let error = subscriptions.failureError
        return BlockFailureRow(title: GroupRecordsCopy.failureTitle(error), error: error, refresh: subscriptions.pager.refresh,
                               id: "group.subs.list") { Task { await subscriptions.reload() } }
    }

    @ViewBuilder private var rows: some View {
        let pager = subscriptions.pager
        if case .failed = pager.state {
            GroupRecordsRefreshRow(updatedAt: pager.state.updatedAt, timeZone: timeZone, refresh: pager.refresh, id: "group.subs.refresh.retry") {
                Task { await subscriptions.reload() }
            }
        }
        if let group = subscriptions.group, group.subscriptionType == "subscription" { limits(group) }
        Section {
            if let feed = pager.feed, let group = subscriptions.group {
                if feed.rows.isEmpty {
                    GroupRecordsEmptyRow(text: GroupRecordsCopy.subscriptionsEmpty, id: "group.subs.empty")
                } else {
                    subscriptionRows(feed.rows, group: group)
                    if let hint = feed.moreHint(unit: GroupRecordsCopy.subscriptionsUnit) {
                        GroupRecordsMoreFooter(hint: hint, state: pager.nextPage, page: feed.nextPage, attempt: moreAttempt, idPrefix: "group.subs",
                                               load: { await subscriptions.loadMore() }, retry: { await subscriptions.retryMore() })
                    }
                }
            }
        } header: {
            GroupRecordsListHead(leading: GroupRecordsCopy.subscriptionsHeadLeading, trailing: GroupRecordsCopy.subscriptionsHeadTrailing,
                                 id: "group.subs.head")
        } footer: {
            Text(GroupRecordsCopy.subscriptionsFootnote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("group.subs.footnote")
        }
    }

    /// 页头 “每个订阅的限额  每日 $20  每周 $100  每月 $300”.
    private func limits(_ group: AdminGroup) -> some View {
        let limits = GroupRecordsCopy.limits(group)
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(GroupRecordsCopy.limitsCaption).font(.caption).foregroundStyle(Palette.ink3)
                HStack(spacing: 16) {
                    ForEach(limits) { limit in
                        HStack(spacing: 4) {
                            Text(limit.span.label).foregroundStyle(Palette.ink2)
                            Text(limit.value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
                        }
                    }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(GroupRecordsCopy.limitsSpoken(limits)))
            .accessibilityIdentifier("group.subs.limits")
        }
    }

    @ViewBuilder private func subscriptionRows(_ items: [AdminUserSubscription], group: AdminGroup) -> some View {
        let rows = items.map { GroupSubscriptionRow($0, group: group, now: now, timeZone: timeZone) }
        let positions = RailPosition.positions(of: rows) { $0.railTone?.drawsRail == true }
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            GroupRecordsRowLink(userID: row.userID, spokenLabel: row.spokenLabel, id: "group.sub.\(row.id)") {
                GroupSubscriptionRowView(row: row, railPosition: positions[index])
            }
        }
    }
}

/// 50 §7.3: the initial; the name with days left or the status badge; an active subscription's three usage columns; the end
/// date and email. Ending within seven days rides the caution rail; suspended and expired rows are dimmed and show no usage.
private struct GroupSubscriptionRowView: View {
    let row: GroupSubscriptionRow
    let railPosition: RailPosition?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            UserInitialAvatar(initial: row.initial, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    trailing
                }
                if !row.windows.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row.windows) { GroupSubscriptionWindowView(window: $0) }
                    }
                }
                Text(row.detail).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.tail)
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

    @ViewBuilder private var trailing: some View {
        switch row.trailing {
        case .daysLeft(let text, let tone):
            Text(text).font(.caption.weight(tone == nil ? .regular : .semibold)).monospacedDigit().foregroundStyle(tone?.ink ?? Palette.ink2).fixedSize()
        case .badge(let text):
            ToneBadge(text: text, tone: .neutral)
        case .none:
            EmptyView()
        }
    }
}

/// One usage column: the window, “$18.60 / $100” and a thin bar (caution from 75%, critical from 90%); “无限制” without a limit.
private struct GroupSubscriptionWindowView: View {
    let window: GroupSubscriptionWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(window.span.label).font(.caption2).foregroundStyle(Palette.ink3)
            Text(window.readout).font(.caption).monospacedDigit().foregroundStyle(window.tone?.ink ?? Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.7)
            if window.limit == nil {
                Text(GroupSubscriptionWindow.unlimited).font(.caption2).foregroundStyle(Palette.ink3)
            } else {
                Capsule().fill(Palette.sunken).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(window.tone?.base ?? Palette.ink2).frame(width: proxy.size.width * min(max(window.fraction ?? 0, 0), 1))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
