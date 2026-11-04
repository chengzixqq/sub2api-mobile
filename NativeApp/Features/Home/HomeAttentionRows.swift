import SwiftUI
import Sub2Core

// 10 §1.3.3 the 待处理 rows other than alerts: each is one button on the status rail, its words from HomePresentation's
// AttentionItem. Countdowns redraw only their own text, each second (AttentionTickingText). Identifiers home.attention.<item id>.

/// 过载, “另有 N 条告警中”, 可用不足, the three money rows (R02) and an alert missing from the list: icon, title with its badge, amount
/// or countdown, and up to two lines of detail, “已停止调度” first.
struct AttentionRow: View {
    let item: AttentionItem
    let railPosition: RailPosition?
    let now: @Sendable () -> Date
    let onOpen: () -> Void
    let onCountdownElapsed: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AttentionIcon(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AttentionTitle(text: item.title)
                        trailing
                    }
                    if let detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2) }
                }
                AttentionChevron()
            }
            .railRowContent()
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .railRow(tone: item.tone, position: railPosition)
    }

    /// The badge in the row's tone, or the amount in ink: amounts are never coloured (10 §0.6).
    @ViewBuilder private var trailing: some View {
        if let badge = item.badge {
            AttentionTickingText(text: badge, now: now, onElapsed: onCountdownElapsed) { ToneBadge(text: $0, tone: item.tone) }
        } else if let amount = item.trailing {
            AttentionTickingText(text: amount, now: now, onElapsed: onCountdownElapsed) {
                Text($0).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
            }
        }
    }

    /// The mark leads, so only the tail is ever cut: “已停止调度 · 上游 529 · 智谱 GLM”.
    private var detail: String? {
        let parts = [item.detailMark, item.detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// An error account: octagon, name and “错误”, the reason in up to two lines, then “平台 · N 分钟前” beside 「测试」. 「测试」 sits over
/// the row's corner as its own button, not inside the row's (a button in a button would fire both); 30pt to see, 44pt to touch.
struct ErrorAccountAttentionRow: View {
    let item: AttentionItem
    let accountID: Int
    let railPosition: RailPosition?
    let onOpen: () -> Void
    let onTest: () -> Void
    @Environment(\.sessionContext) private var session

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AttentionIcon(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AttentionTitle(text: item.title)
                        if let badge = item.badgeText(now: Date()) { ToneBadge(text: badge, tone: item.tone) }
                    }
                    if let detail = item.detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink1).lineLimit(2) }
                    if let footnote {
                        Text(footnote).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1)
                            .padding(.trailing, Self.testWidth)
                            .frame(minHeight: Self.testHeight, alignment: .leading)
                    }
                }
                AttentionChevron()
            }
            .railRowContent()
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.attention." + item.id)
        .overlay(alignment: .bottomTrailing) { testButton }
        .railRow(tone: item.tone, position: railPosition)
    }

    private static let testWidth: CGFloat = 76
    private static let testHeight: CGFloat = 30

    /// A read-only token greys 「测试」 (00 §2.6.3); the bottom line says why, there is no room under the button.
    private var footnote: String? {
        let parts = [item.footnote, session?.isReadOnlyToken == true ? ReadOnlyGate.caption : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var testButton: some View {
        Button(action: onTest) {
            Label("测试", systemImage: "waveform")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: Self.testHeight)
                .background(Palette.sunken, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 4)
        .padding(.bottom, AttentionMetrics.verticalPadding - 7)
        .readOnlyGate(showsCaption: false)
        .accessibilityLabel("测试 " + item.title)
        .accessibilityIdentifier("home.attention.test.\(accountID)")
    }
}

/// 受限 N 个账号: hourglass, “最早 m:ss” on the right, the names on one line cut at the end (“等” from the server's cap), and the
/// stopped ones on a third line whose mark is never cut. The calm layout's “自动恢复中” (S1-11) passes its own identifier.
struct LimitedAttentionRow: View {
    let item: AttentionItem
    let railPosition: RailPosition?
    let now: @Sendable () -> Date
    var identifier = "home.attention.limited"
    let onOpen: () -> Void
    let onCountdownElapsed: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AttentionIcon(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AttentionTitle(text: item.title)
                        if let earliest = item.trailing {
                            AttentionTickingText(text: earliest, now: now, onElapsed: onCountdownElapsed) {
                                Text($0).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(item.tone.ink).lineLimit(1)
                            }
                        }
                    }
                    if let names = item.detail {
                        Text(names).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.tail)
                    }
                    if let stopped = item.stoppedNames {
                        HStack(spacing: 0) {
                            Text(AccountDisplayState.stoppedMark + " · ").fixedSize()
                            Text(stopped).lineLimit(1).truncationMode(.tail)
                        }
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AccountDisplayState.stoppedMark + " · " + stopped)
                    }
                }
                AttentionChevron()
            }
            .railRowContent()
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .railRow(tone: item.tone, position: railPosition)
        .accessibilityIdentifier(identifier)
    }
}

/// An AttentionText: plain words as they are, or a countdown that redraws each second by itself and calls `onElapsed` once it
/// passes zero (10 §1.6; LiveOpsStore keeps that to one read in ten seconds). A target already past when shown waits for the
/// next poll instead of reading at once.
struct AttentionTickingText<Content: View>: View {
    let text: AttentionText
    let now: @Sendable () -> Date
    let onElapsed: () -> Void
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        switch text {
        case .plain(let words):
            content(words)
        case .countdown(_, let until):
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let current = now()
                content(text.text(now: current))
                    .onChange(of: until <= current) { _, elapsed in if elapsed { onElapsed() } }
            }
        }
    }
}

/// The row's symbol: in its tone when the tone draws a rail, otherwise ink.
struct AttentionIcon: View {
    let item: AttentionItem

    var body: some View {
        Image(systemName: item.systemImage)
            .foregroundStyle(item.tone.drawsRail ? item.tone.base : Palette.ink3)
            .frame(width: AttentionMetrics.iconWidth)
            .accessibilityHidden(true)
    }
}

struct AttentionTitle: View {
    let text: String

    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
