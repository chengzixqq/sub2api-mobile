import SwiftUI
import Sub2Core

/// 30 §8.3 平台限额 (S3-14, design UeQuotaSec): under the API Key section of Key 与限额. A row opens the platform's sheet and
/// “＋ 添加平台限额” the picker; the sheets hang on the page (UserKeyPrompts). Everything here takes effect at once.
struct PlatformQuotaSection: View {
    let store: PlatformQuotaStore
    let hasActiveSubscription: Bool
    let onOpen: (PlatformQuotaSheetRoute) -> Void

    var body: some View {
        Section {
            if hasActiveSubscription { PlatformQuotaSubscriptionNotice() }
            content
        } header: {
            NumberedSectionHeader(title: PlatformQuotaPresentation.sectionTitle, meta: PlatformQuotaPresentation.sectionMeta, id: "keys.quota.header")
        } footer: {
            Text(PlatformQuotaPresentation.footnote).accessibilityIdentifier("keys.quota.footnote")
        }
    }

    @ViewBuilder private var content: some View {
        if store.quotas.disabledReason != nil {
            Text(PlatformQuotaFailure.unavailable.message)
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(minHeight: 44)
                .accessibilityIdentifier("keys.quota.unavailable")
        } else if let quotas = store.quotas.value {
            if quotas.isEmpty {
                Text(PlatformQuotaPresentation.empty).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("keys.quota.empty")
            }
            ForEach(store.rows) { quota in
                PlatformQuotaRow(quota: quota, name: store.name(quota.platform)) { onOpen(.edit(quota.platform)) }
            }
            if !store.addablePlatforms.isEmpty { addRow }
        } else if store.quotas.failureReason != nil {
            Button { Task { await store.refresh() } } label: {
                Label(PlatformQuotaPresentation.listFailed + " · 重试", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }
            .accessibilityIdentifier("keys.quota.retry")
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("keys.quota.loading")
        }
    }

    /// Hidden once every platform has a quota.
    private var addRow: some View {
        Button { onOpen(.picker) } label: {
            Label(PlatformQuotaPresentation.add, systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("keys.quota.add")
        .readOnlyGate()
    }
}

/// One platform: its name (critical “已禁止使用” when any window is 0) over the three window cells.
private struct PlatformQuotaRow: View {
    let quota: UserPlatformQuota
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                    if quota.isBanned { ToneBadge(text: PlatformQuotaPresentation.bannedBadge, tone: .critical) }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(PlatformQuotaPresentation.cells(quota)) { PlatformQuotaWindowCell(cell: $0) }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keys.quota.row.\(quota.platform)")
    }
}

/// Design `UeWin`: the window, its share (or 不限 / 已禁止), a meter, and the reading under it.
struct PlatformQuotaWindowCell: View {
    let cell: PlatformQuotaCell

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cell.kind.title).font(.caption).foregroundStyle(Palette.ink2)
                Spacer(minLength: 4)
                Text(cell.headline).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(cell.tone?.ink ?? Palette.ink1)
            }
            ProgressView(value: cell.isBanned ? 1 : cell.progress ?? 0)
                .tint(cell.tone?.base ?? Palette.accent)
                .opacity(cell.progress == nil && !cell.isBanned ? 0.3 : 1)
                .accessibilityHidden(true)
            Text(cell.reading).font(.caption).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 30 §8.3: the caution line for a user with an active subscription, in the section and in the sheet.
struct PlatformQuotaSubscriptionNotice: View {
    var body: some View {
        Label {
            Text(PlatformQuotaPresentation.subscriptionNotice).font(.footnote).foregroundStyle(Palette.ink1)
        } icon: {
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Tone.caution.base)
        }
        .listRowBackground(Tone.caution.wash)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keys.quota.subscription")
    }
}
