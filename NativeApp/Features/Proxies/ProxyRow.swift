import SwiftUI
import Sub2Core

/// 60 §12.3 proxy row (C-8): the leading glyph, the name with the latency or status on the right, the monospaced address, then
/// the accounts, place or expiry with the about-to-expire and 链接失败 badges. Everything comes from `ProxyPresentation.row`
/// (S6-10). The list and the global search (S6-21) share it: new parameters go at the end with defaults. The chevron is the
/// enclosing NavigationLink's; the container sets the row's top, bottom and leading insets to 0 so capsules join.
struct ProxyRow: View {
    let proxy: AdminProxy
    let now: Date
    let timeZone: ServerTimeZone
    let isTesting: Bool
    let railPosition: RailPosition?

    init(proxy: AdminProxy, now: Date, timeZone: ServerTimeZone, isTesting: Bool = false, railPosition: RailPosition? = nil) {
        self.proxy = proxy; self.now = now; self.timeZone = timeZone; self.isTesting = isTesting; self.railPosition = railPosition
    }

    private var content: ProxyRowContent { ProxyPresentation.row(proxy, now: now, timeZone: timeZone, isTesting: isTesting) }

    /// What VoiceOver reads: the name, the right side, the address, the last line and the badges; the enclosing link uses it too.
    var spokenLabel: String {
        let content = content
        let parts: [String?] = [content.title, Self.trailingText(content.trailing), content.address, content.footnote, content.expiryBadge?.text,
                                content.showsLinkFailedBadge ? ProxyPresentation.linkFailedText : nil]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }

    var body: some View {
        let content = content
        HStack(alignment: .top, spacing: 10) {
            ProxyGlyphView(glyph: content.glyph)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(content.title).font(.subheadline.weight(.semibold)).foregroundStyle(content.isDimmed ? Palette.ink3 : Palette.ink1)
                    Spacer(minLength: 4)
                    ProxyRowTrailingView(trailing: content.trailing)
                }
                Text(content.address).font(.footnote.monospaced()).foregroundStyle(content.isDimmed ? Palette.ink3 : Palette.ink2)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(content.footnote).font(.footnote).foregroundStyle(content.isDimmed ? Palette.ink3 : Palette.ink2)
                    if let badge = content.expiryBadge { ToneBadge(text: badge.text, tone: badge.tone) }
                    if content.showsLinkFailedBadge { ToneBadge(text: ProxyPresentation.linkFailedText, tone: .critical) }
                }
            }
            .lineLimit(1)
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 0))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .statusCapsule(tone: content.tone, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }

    static func trailingText(_ trailing: ProxyRowTrailing) -> String {
        switch trailing {
        case .testing: ProxyPresentation.testingText
        case .status(let badge): badge.text
        case .latency(let text): text
        case .linkFailed: ProxyPresentation.linkFailedText
        case .untested: ProxyPresentation.untestedText
        }
    }
}

/// “测试中”, a status badge, “182ms”, the critical 链接失败 badge, or the grey “未测试”.
private struct ProxyRowTrailingView: View {
    let trailing: ProxyRowTrailing

    var body: some View {
        switch trailing {
        case .testing:
            Text(ProxyPresentation.testingText).font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
        case .status(let badge):
            ToneBadge(text: badge.text, tone: badge.tone)
        case .latency(let text):
            Text(text).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
        case .linkFailed:
            ToneBadge(text: ProxyPresentation.linkFailedText, tone: .critical)
        case .untested:
            Text(ProxyPresentation.untestedText).font(.footnote).foregroundStyle(Palette.ink3)
        }
    }
}

/// 12.3 前导字形: a dot for 正常, the error octagon, a grey minus for a stopped (or expired, unused) proxy and a hollow neutral
/// dot for one never probed; the shapes differ, so none relies on colour.
private struct ProxyGlyphView: View {
    let glyph: ProxyGlyph
    @ScaledMetric(relativeTo: .body) private var symbolSize = 17.0
    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0
    @ScaledMetric(relativeTo: .body) private var width = 22.0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: isDot ? dotSize : symbolSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }

    private var isDot: Bool { glyph == .normal || glyph == .untested }
    private var symbol: String {
        switch glyph {
        case .normal: "circle.fill"
        case .error: "exclamationmark.octagon"
        case .idle: "minus"
        case .untested: "circle"
        }
    }
    private var color: Color {
        switch glyph {
        case .normal: Tone.ok.base
        case .error: Tone.critical.base
        case .idle, .untested: Tone.neutral.base
        }
    }
}

/// 12.5 加载中: a placeholder row of the same height.
struct ProxyRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 8)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("proxy-name").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("000ms").font(.subheadline)
                }
                Text("SOCKS5 · 000.000.000.000:0000").font(.footnote.monospaced())
                Text("0 个账号在用").font(.footnote)
            }
        }
        .foregroundStyle(Palette.ink3)
        .redacted(reason: .placeholder)
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载代理"))
    }
}
