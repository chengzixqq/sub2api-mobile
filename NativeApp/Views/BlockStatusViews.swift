import SwiftUI
import Sub2Core

// C-5 (S1-08): a data block's status for the pages rewritten in stages 1–6 (10 §0.5, §1.5; 00 §2.7.2). Pages that poll on their
// own pass `resendsAfterWait: false`, so the end of a 429 wait is left to their timer (S1D1-20).

/// Beside a block's title: 正在刷新, 更新失败 (tap to retry), 加载超时, or the 429 countdown; nothing without a value to show.
/// Identifiers `<id>.status` and, on 更新失败, `<id>.retry`.
struct BlockStatusAccessory<Value: Sendable>: View {
    private let state: BlockState<Value>
    private let refresh: BlockRefresh
    private let id: String
    private let resendsAfterWait: Bool
    private let retry: @MainActor () -> Void

    init(state: BlockState<Value>, refresh: BlockRefresh, id: String = "block", resendsAfterWait: Bool = true,
         retry: @escaping @MainActor () -> Void) {
        self.state = state; self.refresh = refresh; self.id = id; self.resendsAfterWait = resendsAfterWait; self.retry = retry
    }
    init(_ load: LoadState<Value>, id: String = "block", resendsAfterWait: Bool = true, retry: @escaping @MainActor () -> Void) {
        self.init(state: load.state, refresh: load.refresh, id: id, resendsAfterWait: resendsAfterWait, retry: retry)
    }

    var body: some View {
        EverySecondDuringWait(refresh: refresh) { now in content(BlockStatusPresentation.accessory(for: state, refresh: refresh, at: now)) }
            .resendingAfterWait(refresh, isOn: resendsAfterWait && state.value != nil, retry: retry)
    }

    @ViewBuilder private func content(_ accessory: BlockStatusPresentation.Accessory) -> some View {
        switch accessory {
        case .none:
            EmptyView()
        case .refreshing:
            ProgressView().controlSize(.small)
                .accessibilityLabel(BlockStatusPresentation.refreshingLabel)
                .accessibilityIdentifier("\(id).status")
        case .updateFailed:
            Button(action: retry) {
                Label(BlockStatusPresentation.updateFailed, systemImage: "arrow.clockwise")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(BlockStatusPresentation.updateFailed)，\(BlockStatusPresentation.retryTitle)")
            .accessibilityIdentifier("\(id).retry")
        case .timedOut:
            statusText(BlockStatusPresentation.timedOut)
        case .throttled(let message):
            statusText(message)
        }
    }
    private func statusText(_ text: String) -> some View {
        Text(text).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).accessibilityIdentifier("\(id).status")
    }
}

/// A block without an earlier value: one line “加载失败 · 重试”. During a 429 wait the countdown shows and 重试 waits; a
/// compliance refusal offers 完成合规确认 (BACKLOG); an APIError adds its 详情. Identifiers `<id>.failure`, `<id>.retry`,
/// `<id>.compliance`.
struct BlockFailureRow: View {
    @Environment(AppModel.self) private var model
    private let title: String
    private let error: APIError?
    private let occurredAt: Date?
    private let refresh: BlockRefresh
    private let id: String
    private let resendsAfterWait: Bool
    private let retry: @MainActor () -> Void
    /// The time of the details when the caller has none: when this row first showed.
    @State private var shownAt = Date()

    init(title: String = BlockStatusPresentation.loadFailed, error: APIError?, occurredAt: Date? = nil, refresh: BlockRefresh,
         id: String = "block", resendsAfterWait: Bool = true, retry: @escaping @MainActor () -> Void) {
        self.title = title; self.error = error; self.occurredAt = occurredAt; self.refresh = refresh; self.id = id
        self.resendsAfterWait = resendsAfterWait; self.retry = retry
    }
    /// 加载超时 or 加载失败 as the block's failure says.
    init<Value: Sendable>(state: BlockState<Value>, error: APIError? = nil, occurredAt: Date? = nil, refresh: BlockRefresh,
                          id: String = "block", resendsAfterWait: Bool = true, retry: @escaping @MainActor () -> Void) {
        self.init(title: BlockStatusPresentation.failureTitle(for: state), error: error, occurredAt: occurredAt, refresh: refresh, id: id,
                  resendsAfterWait: resendsAfterWait, retry: retry)
    }
    init<Value: Sendable>(_ load: LoadState<Value>, id: String = "block", resendsAfterWait: Bool = true, retry: @escaping @MainActor () -> Void) {
        self.init(state: load.state, error: load.lastError, occurredAt: load.lastErrorAt, refresh: load.refresh, id: id,
                  resendsAfterWait: resendsAfterWait, retry: retry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EverySecondDuringWait(refresh: refresh) { now in line(BlockStatusPresentation.failureRow(title: title, error: error, refresh: refresh, at: now)) }
            if let error, let details = ErrorDetails(error, occurredAt: occurredAt ?? shownAt) { ErrorDetailsDisclosure(details: details) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(id).failure")
        .resendingAfterWait(refresh, isOn: resendsAfterWait, retry: retry)
    }

    private func line(_ row: BlockStatusPresentation.FailureRow) -> some View {
        HStack(spacing: 6) {
            Text(row.text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
            Text("·").foregroundStyle(Palette.ink3).accessibilityHidden(true)
            switch row.action {
            case .retry: rowButton(BlockStatusPresentation.retryTitle, id: "\(id).retry", action: retry)
            case .waiting: rowButton(BlockStatusPresentation.retryTitle, id: "\(id).retry") {}.disabled(true)
            case .completeCompliance: rowButton(BlockStatusPresentation.complianceTitle, id: "\(id).compliance", action: completeCompliance)
            }
            Spacer(minLength: 0)
        }
    }
    private func rowButton(_ title: String, id: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }
    /// Asked by the administrator, so the sheet shows again after 稍后; the block is read again once it passed.
    private func completeCompliance() {
        let model = model, retry = retry
        Task { if await model.presentCompliance() == .passed { retry() } }
    }
}

extension View {
    /// The accessibility value of a shown figure: the missing mark “—” reads as 无数据 (DisplayFormat.spoken).
    func spokenValue(_ displayed: String) -> some View { accessibilityValue(Text(DisplayFormat.spoken(displayed))) }

    fileprivate func resendingAfterWait(_ refresh: BlockRefresh, isOn: Bool, retry: @escaping @MainActor () -> Void) -> some View {
        modifier(ResendAfterWait(notBefore: refresh.notBefore, isOn: isOn, retry: retry))
    }
}

/// 00 §2.7.2: once a 429 wait ends, the block is read again by itself, once. `isOn` may follow a page's refresh gate: closing
/// it during the wait cancels the resend, opening it again before the end waits out the rest.
private struct ResendAfterWait: ViewModifier {
    let notBefore: Date?
    let isOn: Bool
    let retry: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.task(id: Trigger(notBefore: notBefore, isOn: isOn)) { await waitThenRetry() }
    }
    private struct Trigger: Hashable {
        let notBefore: Date?
        let isOn: Bool
    }
    private func waitThenRetry() async {
        guard isOn, let notBefore else { return }
        let wait = notBefore.timeIntervalSinceNow
        guard wait > 0 else { return }
        do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        retry()
    }
}

/// Redrawn every second only while a 429 wait lasts, so the countdown moves without a timer the rest of the time.
private struct EverySecondDuringWait<Content: View>: View {
    let refresh: BlockRefresh
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if let notBefore = refresh.notBefore, notBefore > Date() {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
        } else {
            content(Date())
        }
    }
}
