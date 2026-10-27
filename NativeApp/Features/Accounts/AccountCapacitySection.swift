import SwiftUI
import Sub2Core

// 20 §2.3 容量（壹）: one bar per CapacityRow. CapacityBar is the shared capacity line (C-7; S5-07's group detail draws its
// counts with CapacityRow.count).

/// Title · bar · readout, the note under the bar. Over 100% the bar is full and stays critical; an unknown used part draws the
/// track only. VoiceOver reads the title, then the readout and note.
struct CapacityBar: View {
    let row: CapacityRow

    init(_ row: CapacityRow) { self.row = row }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(row.title).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                    .frame(width: Self.titleWidth, alignment: .leading)
                track
                Text(row.readout).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1).fixedSize()
            }
            if let note = row.note {
                Text(note).font(.footnote).foregroundStyle(Palette.ink3).padding(.leading, Self.titleWidth + 10)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.title))
        .accessibilityValue(Text(row.spokenValue))
    }

    private static let titleWidth: CGFloat = 80

    private var track: some View {
        Capsule().fill(Palette.sunken).frame(height: 6)
            .overlay(alignment: .leading) {
                if let fraction = row.fraction, fraction > 0 {
                    GeometryReader { proxy in
                        Capsule().fill(row.tone?.base ?? Palette.ink2).frame(width: proxy.size.width * min(fraction, 1))
                    }
                }
            }
            .frame(maxWidth: .infinity)
    }
}

/// 容量 with “更新于 HH:MM:SS” beside its title; the caller leaves the section out when `rows` is empty.
struct AccountCapacitySection: View {
    let rows: [CapacityRow]
    let ordinal: String
    let updatedText: String?

    var body: some View {
        AccountDetailSectionBox(title: "容量", ordinal: ordinal, meta: updatedText, id: "account.capacity.header") {
            ForEach(rows) { row in
                CapacityBar(row).accessibilityIdentifier("account.capacity.\(row.id)")
            }
        }
    }
}

/// A section of the detail's top half: the numbered title over a surface card. The meta (“更新于 …”) sits before the number;
/// NumberedSectionHeader takes one from S1-09b on, and S2-23 moves these headers over.
struct AccountDetailSectionBox<Content: View>: View {
    let title: String
    let ordinal: String
    var meta: String?
    let id: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            if let meta { Text(meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3) }
            Text(ordinal).font(.subheadline).foregroundStyle(Palette.ink3).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(meta ?? ""))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(id)
    }
}
