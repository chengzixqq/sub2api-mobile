import SwiftUI
import Sub2Core

/// 50 §2.3 after 壹 · 成员账号 (design GvDetailRows): 贰 · 用量与容量, 叁 · 记录与关联, 肆 · 配置, numbered the same in every mode
/// (S5D2a-13). The values come from GroupDetailModel and its sections; these views only draw.
struct GroupDetailSections: View {
    let detail: GroupDetailModel
    let group: AdminGroup
    let buckets: GroupBuckets
    let permissions: GroupPermissions
    let fallbackName: String?
    let onEdit: () -> Void
    let onOpenWeb: () -> Void

    var body: some View {
        let sections = detail.sections, keys = detail.keyCounts.state
        let capacity = GroupCapacityDisplay.make(sections.capacity.state, group: group, buckets: buckets)
        GroupUsageSection(usage: sections.usage.state, today: sections.todayUsage.state, capacity: permissions.showsUsageAndCapacity ? capacity : nil)
        GroupRecordsSection(group: RouteObject(id: group.id, name: group.name), showsKeys: permissions.showsKeysAndSubscriptions,
                            showsSubscriptions: permissions.showsKeysAndSubscriptions && GroupRecordValues.showsSubscriptions(group),
                            trailing: .init(errors: GroupRecordValues.logCount(sections.requestErrors.state),
                                            upstream: GroupRecordValues.logCount(sections.upstreamErrors.state),
                                            keys: GroupRecordValues.apiKeys(keys), subscriptions: GroupRecordValues.activeSubscriptions(keys)))
        GroupConfigSection(rows: GroupConfigDisplay.rows(group, fallbackName: fallbackName, showsBilling: permissions.showsBillingRow),
                           opensEditor: permissions.canEdit == .enabled, onEdit: onEdit, onOpenWeb: onOpenWeb)
    }
}

/// 50 §2.3 告警横幅 above the status card (design GvAlertBanner): the whole banner opens the alert; “查看” only shows it can.
struct GroupAlertBanner: View {
    let content: GroupAlertBannerContent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            StatusBanner(tone: content.tone, systemImage: GroupAlertBannerContent.systemImage, title: content.title, detail: content.detail) {
                Text(GroupAlertBannerContent.openTitle).font(.footnote.weight(.semibold)).foregroundStyle(content.tone.ink)
                    .padding(.horizontal, 12).frame(minHeight: 30)
                    .background(Palette.surface, in: Capsule())
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(content.title))
        .accessibilityValue(Text(content.detail ?? ""))
        .accessibilityIdentifier("group.detail.alert")
    }
}

/// 贰 · 用量与容量 (design GvUsageSection): the three amounts, 请求 · Tokens · 账号成本 and the capacity lines; `capacity` nil (simple
/// mode) keeps only the middle line. A failed refresh keeps every figure without a word (S5D2a-15); a first read that failed is “—”.
struct GroupUsageSection: View {
    let usage: BlockState<GroupUsageSummary?>
    let today: BlockState<GroupTodayUsage>
    let capacity: GroupCapacityDisplay?

    var body: some View {
        Section {
            if capacity != nil { amounts }
            todayLine
            if let capacity { capacityLines(capacity) }
        } header: {
            NumberedSectionHeader(title: GroupUsageFigures.title, ordinal: GroupUsageFigures.ordinal, meta: GroupUsageFigures.meta, id: "group.usage.header")
        }
    }

    @ViewBuilder private var amounts: some View {
        switch usage.display {
        case .placeholder: amountColumns(Self.placeholderFigures).redacted(reason: .placeholder).accessibilityHidden(true)
        case .value(let summary, _, _, _): amountColumns(GroupUsageFigures(summary))
        case .failed, .disabled: amountColumns(GroupUsageFigures(nil))
        }
    }
    private func amountColumns(_ figures: GroupUsageFigures) -> some View {
        HStack(alignment: .top, spacing: 12) {
            amount(GroupUsageFigures.todayTitle, figures.today, id: "group.usage.today")
            amount(GroupUsageFigures.yesterdayTitle, figures.yesterday, id: "group.usage.yesterday")
            amount(GroupUsageFigures.totalTitle, figures.total, id: "group.usage.total")
        }
        .padding(.vertical, 6)
    }
    private func amount(_ title: String, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .spokenValue(value)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var todayLine: some View {
        switch today.display {
        case .placeholder: todayFigures(GroupTodayLine(.zero)).redacted(reason: .placeholder).accessibilityHidden(true)
        case .value(let usage, _, _, _): todayFigures(GroupTodayLine(usage))
        case .failed, .disabled: todayFigures(.missing)
        }
    }
    private func todayFigures(_ line: GroupTodayLine) -> some View {
        Group {
            switch line {
            case .figures(let requests, let tokens, let cost):
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { todayPairs(requests, tokens, cost) }
                    VStack(alignment: .leading, spacing: 4) { todayPairs(requests, tokens, cost) }
                }
            case .missing:
                Text(DisplayFormat.missing).font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GroupTodayLine.label))
        .accessibilityValue(Text(line.spoken))
        .accessibilityIdentifier("group.usage.todayLine")
    }
    @ViewBuilder private func todayPairs(_ requests: String, _ tokens: String, _ cost: String) -> some View {
        pair(GroupTodayLine.requestsTitle, requests)
        pair(GroupTodayLine.tokensTitle, tokens)
        pair(GroupTodayLine.accountCostTitle, cost)
    }
    private func pair(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(Palette.ink2)
            Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .font(.subheadline)
        .fixedSize()
    }

    @ViewBuilder private func capacityLines(_ display: GroupCapacityDisplay) -> some View {
        switch display {
        case .placeholder:
            CapacityBar(CapacityRow.count(id: "placeholder", title: GroupCapacityDisplay.title, used: 0, limit: 1)).redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .rows(let rows):
            ForEach(rows) { row in CapacityBar(row).accessibilityIdentifier("group.capacity.\(row.id)") }
        case .empty(let note):
            capacityMissing(note: note)
        }
    }
    /// “容量 —” and why; the note is its own element.
    private func capacityMissing(note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 10) {
                Text(GroupCapacityDisplay.title).foregroundStyle(Palette.ink2).frame(width: 80, alignment: .leading)
                Text(DisplayFormat.missing).foregroundStyle(Palette.ink3)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(GroupCapacityDisplay.title))
            .spokenValue(DisplayFormat.missing)
            .accessibilityIdentifier("group.capacity.empty")
            if let note {
                Text(note).font(.footnote).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("group.capacity.note")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private static let placeholderFigures = GroupUsageFigures(GroupUsageSummary(groupID: 0, todayCost: 100, yesterdayCost: 100, totalCost: 10_000))
}

/// 叁 · 记录与关联 (design GvRecordRows): the logs filtered by this group, then the group's keys and subscriptions. A count's
/// first read shows nothing on the right (no flashing “—”).
struct GroupRecordsSection: View {
    struct Trailing: Equatable {
        var errors: String?
        var upstream: String?
        var keys: String?
        var subscriptions: String?
    }
    let group: RouteObject
    let showsKeys: Bool
    let showsSubscriptions: Bool
    let trailing: Trailing

    var body: some View {
        Section {
            row(.errors, .logs(LogsRoute(scope: .errors, group: group)), trailing.errors)
            row(.upstream, .logs(LogsRoute(scope: .upstream, group: group)), trailing.upstream)
            row(.usage, .logs(LogsRoute(scope: .usage, group: group)), nil)
            if showsKeys { row(.keys, .groupKeys(groupID: group.id), trailing.keys) }
            if showsSubscriptions { row(.subscriptions, .groupSubscriptions(groupID: group.id), trailing.subscriptions) }
        } header: {
            NumberedSectionHeader(title: GroupRecordValues.title, ordinal: GroupRecordValues.ordinal, id: "group.records.header")
        }
    }

    private func row(_ kind: GroupRecordRow, _ route: AppRoute, _ trailing: String?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage).foregroundStyle(Palette.ink3).frame(width: 22)
                Text(kind.title).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1) }
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(Text(kind.title))
        .accessibilityValue(Text(trailing.map(DisplayFormat.spoken) ?? ""))
        .accessibilityIdentifier("group.records.\(kind.rawValue)")
    }
}

/// 肆 · 配置 (design GvConfigGrid and GvWebRow): rate, RPM and type open the editor when this identity may edit; the three limits of a
/// subscription group share one row; the Web row opens `<站点>/admin/groups`.
struct GroupConfigSection: View {
    let rows: [GroupConfigRow]
    let opensEditor: Bool
    let onEdit: () -> Void
    let onOpenWeb: () -> Void

    var body: some View {
        Section {
            ForEach(plainRows) { row in configRow(row) }
            if !limits.isEmpty { limitsRow }
            webRow
        } header: {
            NumberedSectionHeader(title: GroupConfigDisplay.title, ordinal: GroupConfigDisplay.ordinal, id: "group.config.header")
        }
    }

    private var plainRows: [GroupConfigRow] { rows.filter { !GroupConfigDisplay.limitKinds.contains($0.kind) } }
    private var limits: [GroupConfigRow] { rows.filter { GroupConfigDisplay.limitKinds.contains($0.kind) } }

    @ViewBuilder private func configRow(_ row: GroupConfigRow) -> some View {
        if row.kind == .description {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.footnote).foregroundStyle(Palette.ink3)
                Text(row.value).font(.subheadline).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.title))
            .accessibilityValue(Text(row.value))
            .accessibilityIdentifier("group.config.description")
        } else if opensEditor && row.opensEditor {
            Button(action: onEdit) { line(row, chevron: true) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(row.title))
                .spokenValue(row.value)
                .accessibilityIdentifier("group.config.\(row.kind.rawValue)")
        } else {
            line(row, chevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(row.title))
                .spokenValue(row.value)
                .accessibilityIdentifier("group.config.\(row.kind.rawValue)")
        }
    }
    private func line(_ row: GroupConfigRow, chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(row.title).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(row.value).monospacedDigit().foregroundStyle(row.value == DisplayFormat.missing ? Palette.ink3 : Palette.ink1).lineLimit(1)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3) }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    private var limitsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GroupConfigDisplay.limitsTitle).font(.footnote).foregroundStyle(Palette.ink3)
            HStack(alignment: .top, spacing: 12) {
                ForEach(limits) { limit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(limit.title).font(.footnote).foregroundStyle(Palette.ink2)
                        Text(limit.value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GroupConfigDisplay.limitsTitle))
        .accessibilityValue(Text(GroupConfigDisplay.limitsSpoken(limits)))
        .accessibilityIdentifier("group.config.limits")
    }
    private var webRow: some View {
        Button(action: onOpenWeb) {
            HStack(spacing: 12) {
                Image(systemName: "safari").foregroundStyle(Palette.ink3).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GroupWebLink.title).font(.subheadline).foregroundStyle(Palette.ink1)
                    Text(GroupWebLink.subtitle).font(.footnote).foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(GroupWebLink.title))
        .accessibilityValue(Text(GroupWebLink.subtitle))
        .accessibilityIdentifier("group.config.web")
    }
}
