import SwiftUI
import Sub2Core

/// 00 §8.1 status capsule: 4pt wide, 6pt from the leading edge, 10pt from the top and bottom; content starts 16pt in.
enum StatusCapsuleMetrics {
    static let width: CGFloat = 4
    static let leadingInset: CGFloat = 6
    static let verticalInset: CGFloat = 10
    static let contentLeadingInset: CGFloat = 16
}

/// 00 §8.2.4 badge: `wash` background and `ink` text, 22pt high, 6pt corners, 12.5pt semibold (scaled with Dynamic Type).
struct ToneBadge: View {
    let text: String
    let tone: Tone
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12.5
    @ScaledMetric(relativeTo: .caption) private var height = 22.0

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold)).monospacedDigit()
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: height)
            .background(tone.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 00 §8.2.4 status banner: `wash` background; caution, critical and model banners also draw the status capsule.
struct StatusBanner<Accessory: View>: View {
    let tone: Tone
    let systemImage: String
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tone.base).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                if let detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            accessory
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 12))
        .background(tone.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            if tone.drawsRail {
                Capsule().fill(tone.base)
                    .frame(width: StatusCapsuleMetrics.width)
                    .padding(.vertical, StatusCapsuleMetrics.verticalInset)
                    .padding(.leading, StatusCapsuleMetrics.leadingInset)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension StatusBanner where Accessory == EmptyView {
    init(tone: Tone, systemImage: String, title: String, detail: String? = nil) {
        self.init(tone: tone, systemImage: systemImage, title: title, detail: detail) { EmptyView() }
    }
}
