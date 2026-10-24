import SwiftUI
import Sub2Core

struct FailureView: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label("暂时无法加载", systemImage: "wifi.exclamationmark")
        } description: { Text(message) } actions: {
            if let retry { Button("重试", action: retry).buttonStyle(.borderedProminent).frame(minHeight: 44) }
        }
    }
}

struct LabeledValue: View {
    let label: String
    let value: String
    var body: some View {
        LabeledContent(label) { Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
            .padding(.vertical, 3)
    }
}

struct MetricView<Footer: View>: View {
    let title: String
    let value: String
    let symbol: String
    let contentHeight: CGFloat
    let footer: Footer
    init(title: String, value: String, symbol: String, contentHeight: CGFloat = 85, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.value = value; self.symbol = symbol
        self.contentHeight = contentHeight; self.footer = footer()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(2)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentHeight, alignment: .topLeading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}

/// A write the global sheet cleared (compliance accepted or step-up verified, S0-13): the page shows the notice and opens
/// its confirmation again with the same key and body (00 §2.6.2 step 4). Other outcomes are ordinary refusals.
func isClearedForReconfirmation(_ error: Error) -> Bool { (error as? APIError)?.securityOutcome == .passed }
