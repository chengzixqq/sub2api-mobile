import SwiftUI

/// The monitor tab's root (10 §4–§6). Stage 0 has only the segments and a placeholder; stage 1 rewrites this file.
struct MonitorView: View {
    @Environment(AppRouter.self) private var router
    @State private var segment = MonitorSegment.overview

    var body: some View {
        VStack(spacing: 0) {
            Picker("监控分段", selection: $segment) {
                ForEach(MonitorSegment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)
            .accessibilityIdentifier("monitor.segment")
            ContentUnavailableView("即将推出", systemImage: MainTab.monitor.systemImage, description: Text("\(segment.title)会在后续版本提供。"))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("monitor.placeholder")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle(MainTab.monitor.title)
        // 10 §0.7-4: the intent is taken once, so coming back to the tab keeps the segment chosen since.
        .onAppear(perform: applyIntent)
        .onChange(of: router.pendingIntent) { _, _ in applyIntent() }
    }

    private func applyIntent() {
        if case .monitor(let target)? = router.takeIntent(for: .monitor) { segment = target }
    }
}
