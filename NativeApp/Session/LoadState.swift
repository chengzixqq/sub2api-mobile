import Foundation
import Observation
import Sub2Core

// A cancelled or late request cannot replace a newer foreground load.
@MainActor @Observable
final class LoadState<Value: Sendable> {
    private(set) var state: BlockState<Value> = .idle
    /// 00 §2.7.2 429 wait and §4.6 failure backoff; kept by `reset()` because both describe the site, not the shown value.
    private(set) var refresh = BlockRefresh()
    /// The last failure while its message shows, for BlockFailureRow's 完成合规确认 and its details (S1-08); nil for anything but
    /// an APIError. BlockState keeps only the text.
    private(set) var lastError: APIError?
    private(set) var lastErrorAt: Date?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var task: Task<Value, any Error>?

    var value: Value? { state.value }
    var error: String? { state.failureReason }
    var updatedAt: Date? { state.updatedAt }
    var isLoading: Bool { state.isLoading }

    func cancel() {
        requestID = nil
        task?.cancel(); task = nil; state = state.withCancelledLoad()
    }
    func reset() {
        cancel(); state = state.withReset(during: refresh, at: Date())
        if state.failureReason == nil { lastError = nil; lastErrorAt = nil }
    }
    /// A local edit of the shown value (a resolved alert, a new silence); its time, the request in flight and the backoff stay.
    func updateValue(_ transform: (Value) -> Value) { state = state.updatingValue(transform) }
    /// The polling delay after this load; pages show `refresh.throttleMessage(at:)` while a 429 wait lasts.
    func nextDelay(base: TimeInterval) -> TimeInterval { refresh.nextDelay(base: base, at: Date()) }
    func load(isCurrent: @MainActor () -> Bool, operation: @escaping @MainActor @Sendable () async throws -> Value) async {
        guard isCurrent(), !Task.isCancelled, refresh.allowsRequest(at: Date()) else { return }
        cancel()
        let id = UUID()
        let current = Task { try await operation() }
        requestID = id; task = current; state = state.withLoading()
        defer {
            if requestID == id { task = nil; requestID = nil; state = state.withCancelledLoad() }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: { current.cancel() }
            guard requestID == id, isCurrent(), !Task.isCancelled else { return }
            state = .loaded(result, at: Date()); refresh = refresh.recordingSuccess()
            lastError = nil; lastErrorAt = nil
        } catch {
            guard requestID == id, isCurrent(), !current.isCancelled, !Task.isCancelled,
                  !(error is CancellationError) else { return }
            state = state.withFailure(error.localizedDescription); refresh = refresh.recordingFailure(error, at: Date())
            lastError = error as? APIError; lastErrorAt = Date()
        }
    }
}
