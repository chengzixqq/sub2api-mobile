import SwiftUI
import Sub2Core

/// 50 §2.3 状态卡 (design GvHero): a stopped group's quiet line; otherwise the health (a badge on its wash with the status capsule
/// for none / low, a check for ok), the unavailable count, the big “2 / 3 个账号可用” (tinted for none / low), the cells and the
/// legend, then — once the members are in — the stopped note and the earliest recovery, and none's warning. Words are S5-02's.
struct GroupStatusCard: View {
    let group: AdminGroup
    let buckets: GroupBuckets
    let health: GroupHealth
    /// nil until the members are read, or when they failed: no stopped note and no recovery line then.
    let members: [GroupMemberSnapshot]?
    /// stats' `total_api_keys`; only a known 0 adds “目前也没有 API 密钥使用它。”.
    let totalAPIKeys: Int?

    var body: some View {
        Group {
            if group.status != "active" { quiet } else { card(GroupCopy.statusCard(health: health, buckets: buckets, totalAPIKeys: totalAPIKeys)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .statusCapsule(tone: group.status == "active" && health.tone.drawsRail ? health.tone : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group.detail.card")
    }

    /// Design hero-quiet: the stopped glyph and one line, no figures or cells.
    private var quiet: some View {
        HStack(spacing: 10) {
            Image(systemName: AccountRowPresentation.systemImage(for: .inactive))
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Tone.neutral.base)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(GroupCopy.inactiveCard).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("group.detail.card.quiet")
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }

    private func card(_ copy: GroupStatusCardCopy) -> some View {
        let tinted = health.tone.drawsRail
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GroupHealthTitle(health: health, title: copy.title, isBadge: tinted)
                Spacer(minLength: 4)
                Text(copy.trailing).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                    .accessibilityIdentifier("group.detail.card.cause")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(copy.available).font(.system(size: 46, weight: .semibold)).foregroundStyle(tinted ? health.tone.ink : Palette.ink1)
                Text("/ \(copy.total)").font(.title3.weight(.medium)).foregroundStyle(Palette.ink2)
                Text("个账号可用").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.figure)
            .accessibilityIdentifier("group.detail.card.figure")
            GroupCellsView(buckets: buckets, isActiveGroup: true, size: .detail, identifier: "group.detail.cells")
            GroupLegend(buckets: buckets).accessibilityIdentifier("group.detail.legend")
            if let members { GroupMemberWindowLines(members: members) }
            if let warning = copy.warning {
                Text(warning).font(.subheadline).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("group.detail.card.warning")
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 16))
    }
}

/// none / low: the health's icon and word on its wash (the account card's big badge); ok: a check and “全部可用” / “正常”.
private struct GroupHealthTitle: View {
    let health: GroupHealth
    let title: String
    let isBadge: Bool
    @ScaledMetric(relativeTo: .subheadline) private var height = 28.0

    var body: some View {
        if isBadge {
            HStack(spacing: 5) {
                Image(systemName: health.systemImage).accessibilityHidden(true)
                Text(title).accessibilityIdentifier("group.detail.card.badge")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(health.tone.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .background(health.tone.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.ok.base).accessibilityHidden(true)
                Text(title).foregroundStyle(Palette.ink1).accessibilityIdentifier("group.detail.card.badge")
            }
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .frame(minHeight: height)
        }
    }
}

/// 停调度说明 and 最早恢复, from the members on the site clock; while a window runs it counts down every second.
private struct GroupMemberWindowLines: View {
    let members: [GroupMemberSnapshot]
    @Environment(\.sessionContext) private var session

    var body: some View {
        let now = serverNow(Date())
        if GroupRecovery.earliest(members: members, now: now) != nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in lines(now: serverNow(timeline.date)) }
        } else if GroupCopy.stoppedLimitedNote(members: members, now: now) != nil {
            lines(now: now)
        }
    }

    private func lines(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = GroupCopy.stoppedLimitedNote(members: members, now: now) {
                Text(note).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("group.detail.card.stopped")
            }
            if let recovery = GroupRecovery.earliest(members: members, now: now) {
                Text(recovery.text(now: now)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
                    .accessibilityIdentifier("group.detail.card.recovery")
            }
        }
    }
    private func serverNow(_ local: Date) -> Date { local.addingTimeInterval(session?.client.serverClock.offset ?? 0) }
}

/// 50 §2.5 首次加载: the card's and the button row's shapes.
struct GroupStatusCardSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface).frame(height: 176)
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Palette.sunken).frame(height: 46) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在读取分组")
        .accessibilityIdentifier("group.detail.skeleton")
    }
}

/// 50 §2.3 按钮行 (design GvActions) from `GroupPermissions.buttonRow(for:health:)`: equal capsules, the primary filled with the
/// accent; a hidden primary is not handed on. Each is greyed for a read-only token, with one “只读令牌” line under the row.
struct GroupDetailButtonRowView: View {
    let buttons: [GroupButton]
    /// The group's action is running: the row waits and 启用分组 spins.
    let isRunning: Bool
    let perform: (GroupAction) -> Void
    @Environment(\.sessionContext) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(buttons) { button in
                    GroupDetailButton(button: button, isRunning: isRunning && button.action == .enable) { perform(button.action) }
                        .readOnlyGate(showsCaption: false)
                }
            }
            .disabled(isRunning)
            if session?.isReadOnlyToken == true {
                Text(ReadOnlyGate.caption).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("readonly.caption")
            }
        }
    }
}

private struct GroupDetailButton: View {
    let button: GroupButton
    let isRunning: Bool
    let perform: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = 46.0
    @ScaledMetric(relativeTo: .body) private var size = 15.5

    var body: some View {
        let primary = button.isPrimary
        Button(action: perform) {
            HStack(spacing: 6) {
                if isRunning { ProgressView().tint(primary ? Palette.onAccent : Palette.ink1) }
                else { Image(systemName: button.action.systemImage).font(.system(size: size * 0.9, weight: .semibold)) }
                Text(button.action.menuTitle).font(.system(size: size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(primary ? Palette.accentFill : Palette.surface, in: Capsule())
            .overlay { if !primary { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(button.action.menuTitle)
        .accessibilityIdentifier("group.action.\(button.action.rawValue)")
    }
}
