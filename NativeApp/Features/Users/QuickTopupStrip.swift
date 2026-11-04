import SwiftUI
import Sub2Core

/// 30 §1.3 快捷充值: recent adjustments, then low balances, users awaiting reconciliation last. The caller leaves it out when
/// there are no entries. A pending avatar opens the detail and stays available to a read-only token; the others open the
/// keypad and are greyed for one (00 §2.6.3).
struct QuickTopupStrip: View {
    let entries: [QuickTopupEntry]
    let onSelect: @MainActor (QuickTopupEntry) -> Void

    init(entries: [QuickTopupEntry], onSelect: @escaping @MainActor (QuickTopupEntry) -> Void) {
        self.entries = entries; self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("快捷充值").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text("最近调整 · 余额低").font(.footnote).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(entries) { avatar($0) }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("users.quick")
    }

    @ViewBuilder private func avatar(_ entry: QuickTopupEntry) -> some View {
        let button = Button { onSelect(entry) } label: { QuickTopupAvatar(entry: entry) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(entry.spokenLabel))
            .accessibilityIdentifier("users.quick.\(entry.id)")
        if entry.isPending { button } else { button.readOnlyGate(showsCaption: false) }
    }
}

private struct QuickTopupAvatar: View {
    let entry: QuickTopupEntry
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 4) {
            UserInitialAvatar(initial: entry.initial, size: 48)
                .overlay(alignment: .bottomTrailing) { badge }
            Text(entry.displayName).font(.caption.weight(.medium)).foregroundStyle(Palette.ink1)
            Text(entry.caption).font(.caption2).monospacedDigit().foregroundStyle(entry.isPending ? Tone.caution.ink : Palette.ink2)
        }
        .lineLimit(1)
        .frame(width: 68)
        .frame(minHeight: 88, alignment: .top)
        .padding(.vertical, 2)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    private var badge: some View {
        Image(systemName: entry.isPending ? "doc.text.magnifyingglass" : "plus")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: 18, height: 18)
            .background(entry.isPending ? Tone.caution.base : Palette.accentFill, in: Circle())
            .overlay(Circle().stroke(Palette.surface, lineWidth: 2))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }
}
