import SwiftUI
import Sub2Core

/// 10 §1.3.2 the six cells in their fixed order, 3 × 2 (two columns at accessibility text sizes, S1-09). Each cell is its own button
/// opening its HomeDestinationAction: several NavigationLinks in one List row would all fire. Identifiers `home.ticker` and
/// `home.ticker.<kind>`.
struct HomeTicker: View {
    let cells: [HomeTickerCell]
    /// Cells whose block is still on its first load: the skeleton, without a number and disabled (10 §1.5).
    var placeholders: Set<HomeTickerKind> = []
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = HomeTickerLayout.columnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let rows = HomeTickerLayout.rows(cells, columns: columns)
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        cell(rows[row][column])
                            .overlay(alignment: .trailing) { if column < columns - 1 { divider.frame(width: 1) } }
                            .overlay(alignment: .bottom) { if row < rows.count - 1 { divider.frame(height: 1) } }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日指标")
        .accessibilityIdentifier("home.ticker")
    }

    private var divider: some View { Palette.hairline.accessibilityHidden(true) }

    private func cell(_ cell: HomeTickerCell) -> some View {
        let isPlaceholder = placeholders.contains(cell.kind)
        return Button { router.open(HomeDestinationAction(cell.destination)) {} } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(cell.label).font(.caption).foregroundStyle(Palette.ink2).lineLimit(2).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(cell.value).font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let mark = cell.footnoteMark { Text(mark).font(.caption).foregroundStyle(Palette.ink2) }
                }
                // ▲ / ▼ in ink: a direction, not a judgement (10 §0.6).
                if let change = cell.change { Text(change.text).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2) }
            }
            // Only the drawing: a redacted subtree would also blank the button's spoken value.
            .redacted(reason: isPlaceholder ? .placeholder : [])
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 9, trailing: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPlaceholder)
        .accessibilityLabel(isPlaceholder ? cell.label : cell.accessibilityLabel)
        .accessibilityValue(isPlaceholder ? "正在加载" : "")
        .accessibilityIdentifier("home.ticker." + cell.kind.rawValue)
    }
}
