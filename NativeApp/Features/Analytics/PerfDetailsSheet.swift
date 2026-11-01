import SwiftUI
import Sub2Core

/// 40 §1.4 性能明细: every bucket of the card's window, newest on top, “09:40” or “09:40 · 只覆盖 23 秒” over “RPM 46 · TPM 240K”; a
/// row closes the sheet and selects its bucket on the chart. 关闭 at the top left. Identifiers analytics.perf.sheet, .sheet.note,
/// .sheet.close and analytics.perf.row.<the bucket's start in Unix seconds>.
struct PerfDetailsSheet: View {
    let state: PerfTrendState
    let timeZone: TimeZone
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let trend = state.trend {
                    Section {
                        ForEach(trend.newestFirst) { point in row(point, in: trend) }
                    } header: {
                        Text(PerfTrendPresentation.detailsNote(trend, windowTitle: state.window.title))
                            .textCase(nil)
                            .accessibilityIdentifier("analytics.perf.sheet.note")
                    }
                }
            }
            .accessibilityIdentifier("analytics.perf.sheet")
            .navigationTitle(PerfTrendPresentation.detailsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("analytics.perf.sheet.close")
                }
            }
        }
    }

    private func row(_ point: PerformanceTrend.Point, in trend: PerformanceTrend) -> some View {
        let title = PerfTrendPresentation.rowTitle(point, in: trend, timeZone: timeZone)
        let rates = PerfTrendPresentation.rowRates(point, in: trend)
        return Button {
            state.select(point)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                Text(rates).font(.body).monospacedDigit().foregroundStyle(Palette.ink1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + "，" + rates)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("analytics.perf.row.\(Int(point.date.timeIntervalSince1970))")
    }
}
