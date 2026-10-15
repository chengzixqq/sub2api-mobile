import SwiftUI
import Sub2Core

func money(_ value: Decimal) -> String { "$" + NSDecimalNumber(decimal: value).stringValue }

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

struct MetricView: View {
    let title: String
    let value: String
    let symbol: String
    var contentHeight: CGFloat = 85
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentHeight, alignment: .topLeading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct StepUpView: View {
    let client: APIClient
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("此操作需要二次验证。验证完成后请重新确认操作；系统不会自动重放写入请求。")
                    TextField("6 位动态验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .accessibilityIdentifier("stepup.code")
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("验证") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await client.stepUp(code: code); onSuccess(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || code.count != 6).frame(minHeight: 44)
                }
            }.navigationTitle("二次验证")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

func needsStepUp(_ error: Error) -> Bool {
    guard let error = error as? APIError else { return false }
    if error.kind == .twoFactor { return true }
    let reason = error.reason?.lowercased() ?? ""
    return reason.contains("step_up") || reason.contains("stepup") || reason.contains("totp_required")
}
