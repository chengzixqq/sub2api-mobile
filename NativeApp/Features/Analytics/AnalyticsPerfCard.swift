import SwiftUI
import Sub2Core

/// 40 §1.4 RPM / TPM 趋势卡 in the card flow (X44, S4-16): “截至现在 · 运维监控” (only “运维监控” with ops off), the whole-site note when
/// the model filter cannot reach the ops charts, then PerfTrendBody. The session comes from `\.analyticsSession`; AnalyticsView
/// scrolls to this slot for `focus: .perf`. Identifier analytics.perf.
struct AnalyticsPerfCard: View {
    /// The metric the overview's RPM / TPM cell came with (route.metric); preferred to the remembered one and written back.
    let routeMetric: PerfMetric?
    @Environment(AppModel.self) private var model
    @Environment(\.analyticsSession) private var session

    init(routeMetric: PerfMetric? = nil) { self.routeMetric = routeMetric }

    var body: some View {
        let opsDisabled = model.analyticsOpsDisabled
        AnalyticsCard(title: PerfTrendPresentation.cardTitle, id: "analytics.perf") {
            Text(PerfTrendPresentation.cardMeta(opsDisabled: opsDisabled)).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                .accessibilityIdentifier("analytics.perf.meta")
        } content: {
            if !opsDisabled, session?.opsIsSiteWide == true {
                Label(OpsChartCopy.siteWideNote, systemImage: "line.3.horizontal.decrease")
                    .font(.caption).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("analytics.perf.siteWide")
            }
            PerfTrendBody(filter: session?.filter, size: .card, startMetric: routeMetric)
        }
    }
}
