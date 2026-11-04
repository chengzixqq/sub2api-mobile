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

/// A write the global sheet cleared (compliance accepted or step-up verified, S0-13): the page shows the notice and opens
/// its confirmation again with the same key and body (00 §2.6.2 step 4). Other outcomes are ordinary refusals.
func isClearedForReconfirmation(_ error: Error) -> Bool { (error as? APIError)?.securityOutcome == .passed }
