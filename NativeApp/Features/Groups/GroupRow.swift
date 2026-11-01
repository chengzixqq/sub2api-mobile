import SwiftUI
import Sub2Core

/// 50 §1.3 three-line row (C-8): the health glyph; name, platform, 专属 and the health badge; “可用 2/3”, the cells and the
/// breakdown; “费率倍数 ×0.8 · 标准计费” and today's charge (hidden in simple mode). `.compact` is 60 §2's search row: name,
/// platform and 已停用. The chevron is the enclosing NavigationLink's, whose label is `spokenLabel`; the list sets the row's
/// top, bottom and leading insets to 0 so capsules join.
struct GroupRow: View {
    enum Style { case full, compact }
    private let group: AdminGroup
    private let style: Style
    private let usage: GroupUsageSummary?
    private let buckets: GroupBuckets
    private let health: GroupHealth
    private let railPosition: RailPosition?
    private let showsBillingLine: Bool
    private let catalog: MetaCatalog?

    /// Without `buckets` the group's own counts are used (no fallback); without `health` they decide it by the local half rule.
    init(group: AdminGroup, style: Style = .full, usage: GroupUsageSummary? = nil, buckets: GroupBuckets? = nil, health: GroupHealth? = nil,
         railPosition: RailPosition? = nil, showsBillingLine: Bool = true, catalog: MetaCatalog? = nil) {
        let counted = buckets ?? GroupBuckets(group: group)
        self.group = group; self.style = style; self.usage = usage; self.buckets = counted
        self.health = health ?? GroupHealth.resolve(group: group, buckets: counted, shortage: nil)
        self.railPosition = railPosition; self.showsBillingLine = showsBillingLine; self.catalog = catalog
    }

    var spokenLabel: String {
        switch style {
        case .compact:
            return GroupRowSpeech.compact(name: group.name, platformName: platformName, isInactive: group.status != "active")
        case .full:
            let today: GroupRowSpeech.Today = if !showsBillingLine { .hidden } else { usage?.todayCost.map(GroupRowSpeech.Today.amount) ?? .missing }
            return GroupRowSpeech.full(name: group.name, platformName: platformName, isExclusive: group.isExclusive == true, badge: health.badge(buckets),
                                       available: buckets.available, total: buckets.total, breakdown: buckets.breakdown,
                                       billingLine: showsBillingLine ? GroupFormat.billingLine(group) : nil, today: today)
        }
    }
    private var platformName: String { GroupFormat.platformName(group.platform, catalog: catalog) }
    private var isIdle: Bool { health == .off }

    var body: some View {
        Group {
            switch style {
            case .full: full
            case .compact: compact
            }
        }
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .statusCapsule(tone: railPosition == nil ? nil : health.tone, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }

    private var full: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupHealthGlyph(health: health)
            VStack(alignment: .leading, spacing: 6) {
                titleLine
                availabilityLine
                if showsBillingLine { billingLine }
            }
        }
        .opacity(isIdle ? 0.6 : 1)
    }
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            title
            Spacer(minLength: 6)
            if group.isExclusive == true { GroupExclusiveTag() }
            if let badge = health.badge(buckets) { ToneBadge(text: badge, tone: health.tone) }
        }
    }
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(group.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
            Text(platformName).font(.caption).foregroundStyle(Palette.ink2)
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
    private var availabilityLine: some View {
        HStack(spacing: 8) {
            availability
            GroupCellsView(buckets: buckets, isActiveGroup: group.status == "active")
            if let breakdown = buckets.breakdown {
                Text(breakdown).font(.caption).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
    /// “可用 2/3”, the numerator in the health's colour when none or low.
    private var availability: some View {
        let marked = health == .noAvailable || health == .low
        return HStack(spacing: 0) {
            Text("可用 ").foregroundStyle(Palette.ink2)
            Text(DisplayFormat.grouped(buckets.available)).fontWeight(.semibold).foregroundStyle(marked ? health.tone.ink : Palette.ink1)
            Text("/" + DisplayFormat.grouped(buckets.total)).foregroundStyle(Palette.ink2)
        }
        .font(.caption)
        .monospacedDigit()
        .fixedSize()
    }
    private var billingLine: some View {
        HStack(spacing: 8) {
            Text(GroupFormat.billingLine(group)).lineLimit(1)
            Spacer(minLength: 8)
            Text(GroupFormat.todayText(usage)).monospacedDigit().lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(Palette.ink2)
    }
    private var compact: some View {
        HStack(spacing: 8) {
            title
            Spacer(minLength: 8)
            if group.status != "active" { ToneBadge(text: GroupRowSpeech.inactiveBadge, tone: .neutral) }
        }
    }
}

/// 50 §1.3 行首图形: octagon, gauge, group, minus in the health's tone.
struct GroupHealthGlyph: View {
    let health: GroupHealth
    @ScaledMetric(relativeTo: .body) private var size = 17.0

    var body: some View {
        Image(systemName: health.systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(health.tone.base)
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}

/// “专属”: a quiet outlined tag, apart from the health badge.
private struct GroupExclusiveTag: View {
    var body: some View {
        Text(GroupFormat.exclusiveText(true))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.hairline))
            .fixedSize()
    }
}

/// 50 §1.5 首次加载: a placeholder row of the same height.
struct GroupRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: GroupHealth.ok.systemImage).frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text("分组名称占位 平台").font(.subheadline.weight(.semibold))
                Text("可用 0/0 ▢▢▢▢▢▢").font(.caption)
                Text("费率倍数 ×1.0 · 标准计费   今日 $0.00").font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink3)
        .redacted(reason: .placeholder)
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载分组"))
        .accessibilityIdentifier("groups.skeleton")
    }
}
