import SwiftUI
import Sub2Core

/// 40 §1.4 RPM / TPM 趋势卡's slot in the card flow (X44): S4-16 fills this file only. The session comes from `\.analyticsSession`;
/// AnalyticsView scrolls to this slot for `focus: .perf`.
struct AnalyticsPerfCard: View {
    /// The metric the overview's RPM / TPM cell came with (route.metric); S4-16 prefers it to the remembered one and writes it back.
    let routeMetric: PerfMetric?

    init(routeMetric: PerfMetric? = nil) { self.routeMetric = routeMetric }

    var body: some View { EmptyView() }
}
