import SwiftUI
import Sub2Core

/// 50 §0.3: one cell per account, or one proportional segment per bucket when they do not fit, on the list row (96 × 8) and the
/// detail's status card (full width × 12). Positions, tones and outlines all come from GroupCellsLayout; the bar is one
/// accessibility element, “可用 x / y”.
struct GroupCellsView: View {
    enum Size { case list, detail }
    private let buckets: GroupBuckets
    private let isActiveGroup: Bool
    private let size: Size
    private let identifier: String?

    init(buckets: GroupBuckets, isActiveGroup: Bool, size: Size = .list, identifier: String? = nil) {
        self.buckets = buckets; self.isActiveGroup = isActiveGroup; self.size = size; self.identifier = identifier
    }

    var body: some View {
        Group {
            switch size {
            case .list:
                GroupCellsBar(layout: .list(buckets, isActive: isActiveGroup))
            case .detail:
                GeometryReader { proxy in
                    GroupCellsBar(layout: .detail(buckets, isActive: isActiveGroup, width: proxy.size.width))
                }
                .frame(height: GroupCellsLayout.detail(buckets, isActive: isActiveGroup, width: 0).height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GroupCellsLayout.list(buckets, isActive: isActiveGroup).accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "")
    }
}

private struct GroupCellsBar: View {
    let layout: GroupCellsLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.cells) { cell in
                shape(cell).frame(width: cell.width, height: layout.height).offset(x: cell.x)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    @ViewBuilder private func shape(_ cell: GroupCellsLayout.Cell) -> some View {
        let rectangle = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        switch cell.style {
        case .solid:
            rectangle.fill(cell.tone.base)
        case .outline(let lineWidth, let opacity):
            rectangle.strokeBorder(cell.tone.base, lineWidth: lineWidth).opacity(opacity)
        }
    }
}

/// 50 §0.3 图例: “可用 n · 受限 n · 错误 n · 暂停·停用 n”, a bucket at 0 dimmed; two rows of two when one row does not fit.
struct GroupLegend: View {
    let buckets: GroupBuckets

    var body: some View {
        let items = buckets.legend
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ForEach(items) { GroupLegendLabel(item: $0) } }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { GroupLegendLabel(item: items[0]); GroupLegendLabel(item: items[1]) }
                GridRow { GroupLegendLabel(item: items[2]); GroupLegendLabel(item: items[3]) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map(\.text).joined(separator: " · "))
    }
}

private struct GroupLegendLabel: View {
    let item: GroupLegendItem
    @ScaledMetric(relativeTo: .caption) private var swatch = 8.0

    var body: some View {
        HStack(spacing: 4) {
            swatchShape.frame(width: swatch, height: swatch)
            Text(item.bucket.label).foregroundStyle(Palette.ink2)
            Text(DisplayFormat.grouped(item.count)).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
        .opacity(item.isDimmed ? 0.45 : 1)
    }

    @ViewBuilder private var swatchShape: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        if item.bucket == .idle { shape.strokeBorder(item.bucket.tone.base, lineWidth: 1.5).opacity(0.6) }
        else { shape.fill(item.bucket.tone.base) }
    }
}
