import SwiftUI
import Sub2Core

/// 30 §7.3 one key card (design UeKeyCard): collapsed, the name with its badge, the mask, the usage line and the meta line;
/// expanded, the facts, 速率限制 and the actions. One row, so the status capsule runs along the whole card.
struct UserKeyCard: View {
    let key: AdminAPIKey
    let isExpanded: Bool
    let isBusy: Bool
    let today: UserKeyTodayCost
    let context: UserKeysContext
    let access: UserKeyAccess
    let groups: [AdminGroup]
    /// “保存” is not out (S3D1-11).
    let canChangeGroup: Bool
    let onToggle: () -> Void
    let onChangeGroup: () -> Void
    let onReset: () -> Void
    let onSetStatus: (AdminAPIKeyUpdateRequest.Status) -> Void
    let onGap: (String) -> Void

    private var now: Date { context.now() }
    private var status: AdminAPIKeyStatus { key.status(now: now) }
    private var isIdle: Bool { UserKeyPresentation.isIdle(key, now: now, simpleMode: context.simpleMode) }
    private var prefix: String { "keys.card.\(key.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            usage
            Text(UserKeyPresentation.metaLine(key, groups: groups, access: access, now: now, zone: context.serverTimeZone))
                .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2)
                .accessibilityIdentifier(prefix + ".meta")
            if isExpanded { expanded }
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 0))
        .statusCapsule(tone: status.tone)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(prefix)
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Text(key.displayName).font(.body.weight(.semibold)).foregroundStyle(isIdle ? Palette.ink2 : Palette.ink1).lineLimit(1)
                if let badge = UserKeyPresentation.badge(key, now: now, simpleMode: context.simpleMode) { ToneBadge(text: badge, tone: status.tone) }
                Spacer(minLength: 8)
                Text(UserKeyPresentation.mask(key)).font(.footnote.monospaced()).foregroundStyle(Palette.ink2).lineLimit(1)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(UserKeyPresentation.spokenHeader(key, now: now, simpleMode: context.simpleMode)))
        .accessibilityValue(Text(isExpanded ? "已展开" : "已收起"))
        .accessibilityIdentifier(prefix + ".toggle")
    }

    private var usage: some View {
        let line = UserKeyPresentation.usageLine(key, today: today)
        return VStack(alignment: .leading, spacing: 4) {
            if let progress = line.progress { ProgressView(value: progress).tint(line.tone?.base ?? Palette.accent).accessibilityHidden(true) }
            HStack {
                Text(line.text).monospacedDigit().foregroundStyle(isIdle ? Palette.ink2 : Palette.ink1)
                Spacer(minLength: 8)
                Text(line.trailing).font(.footnote).monospacedDigit().foregroundStyle(line.tone?.ink ?? Palette.ink2)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(prefix + ".usage")
    }

    @ViewBuilder private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            fact("有效期", UserKeyPresentation.expiryText(key.expiresAt, zone: context.serverTimeZone), id: "expiry")
            fact("当前并发", UserKeyPresentation.concurrencyText(key.currentConcurrency, supported: context.refreshesConcurrency), id: "concurrency")
            fact("最近 IP", UserKeyPresentation.lastIPText(key.lastUsedIP), id: "ip", monospaced: true)
            fact("IP 限制", UserKeyPresentation.ipRuleText(whitelist: key.ipWhitelist, blacklist: key.ipBlacklist), id: "iprule")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(prefix + ".expanded")
        UserKeyRateLimitsView(limits: UserKeyPresentation.rateLimits(key, now: now, zone: context.serverTimeZone), prefix: prefix)
        actions
    }

    private func fact(_ label: String, _ value: String, id: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(value).font(monospaced ? .subheadline.monospaced() : .subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(prefix + "." + id)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(UserKeyPresentation.changeGroupAction, systemImage: "square.stack.3d.up", action: onChangeGroup)
                    .frame(minHeight: 44)
                    .disabled(!canChangeGroup)
                    .accessibilityIdentifier(prefix + ".group")
                if UserKeyPresentation.showsResetAction(key) {
                    Button(UserKeyPresentation.resetAction, systemImage: "arrow.counterclockwise", action: onReset)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(prefix + ".reset")
                }
                Spacer(minLength: 0)
                if isBusy { ProgressView().accessibilityIdentifier(prefix + ".busy") }
                if UserKeyPresentation.showsStatusMenu(key, adminKeyWrites: context.adminKeyWrites) { menu }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            .disabled(isBusy)
            .readOnlyGate()
            if !context.adminKeyWrites { gaps }
        }
    }

    /// S3-13 adds 编辑 Key…, 显示完整 Key… and 删除 Key… to this menu.
    private var menu: some View {
        Menu {
            let target = UserKeyPresentation.statusTarget(key)
            Button(UserKeyPresentation.statusMenuTitle(key), systemImage: target == .active ? "play.circle" : "pause.circle") { onSetStatus(target) }
        } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("更多操作"))
        .accessibilityIdentifier(prefix + ".more")
    }

    /// E01 missing: the design's two dashed capsules, explaining instead of acting.
    private var gaps: some View {
        HStack(spacing: 8) {
            UserKeyGapChip(title: "停用", systemImage: "pause.fill") { onGap(UserKeyPresentation.gapDisable) }
                .accessibilityIdentifier(prefix + ".gap.disable")
            UserKeyGapChip(title: "删除", systemImage: "xmark") { onGap(UserKeyPresentation.gapDelete) }
                .accessibilityIdentifier(prefix + ".gap.delete")
        }
    }
}

/// 速率限制: three cells, or one line when no window has a limit or any use.
struct UserKeyRateLimitsView: View {
    let limits: UserKeyRateLimits
    let prefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(UserKeyPresentation.rateTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(caption).font(.caption).foregroundStyle(Palette.ink3)
            }
            .accessibilityElement(children: .combine)
            switch limits {
            case .none:
                Text(UserKeyPresentation.rateNoneLine).font(.subheadline).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier(prefix + ".rate.none")
            case .windows(let cells):
                HStack(alignment: .top, spacing: 12) { ForEach(cells) { cell($0) } }
            }
        }
    }

    private var caption: String {
        if case .none = limits { return UserKeyPresentation.rateNoneCaption }
        return UserKeyPresentation.rateCaption
    }
    private func cell(_ window: UserKeyRateWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.span.title).font(.caption).foregroundStyle(Palette.ink2)
                Spacer(minLength: 4)
                Text(window.headline).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(window.tone?.ink ?? Palette.ink1)
            }
            ProgressView(value: window.progress ?? 0).tint(window.tone?.base ?? Palette.accent).opacity(window.progress == nil ? 0.3 : 1)
                .accessibilityHidden(true)
            Text(window.reading).font(.caption).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1).minimumScaleFactor(0.8)
            if let reset = window.resetText { Text(reset).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(prefix + ".rate." + window.span.rawValue)
    }
}

/// A dashed placeholder for what the server lacks (design `ue-gap-chip`), tagged “需后端新增”.
struct UserKeyGapChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption).accessibilityHidden(true)
                Text(title).font(.subheadline)
                Text(UserKeyPresentation.gapTag).font(.caption2).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(Palette.ink2)
            .overlay(Capsule().strokeBorder(Palette.ink3, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(title)，\(UserKeyPresentation.gapTag)，点按查看说明"))
    }
}

/// 30 §7.5 first read: two placeholder cards.
struct UserKeyCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Key 名称占位").font(.body.weight(.semibold)); Spacer(); Text("sk-…0000").font(.footnote.monospaced()) }
            Text("今日 $0.00").font(.subheadline)
            Text("分组 · 默认 ×1 · 最近使用").font(.footnote)
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
