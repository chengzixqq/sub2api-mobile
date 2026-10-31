import Foundation
import Sub2Core

/// 10 §1.4, X17: after an account write wrapper sent its request, whether the home page reads past the server cache the next time
/// it shows. A write that ran, or may have run, marks it; a clear refusal changed nothing and does not.
enum AccountWriteMark {
    /// False for what never ran: a cancel, a local check or a refresh that failed before sending, a 4xx other than 408 (the server
    /// answers those before writing), a key the server will not take. True for the rest: 5xx, 408, a lost connection, an unreadable
    /// reply, a keyed write left unconfirmed, an error of unknown kind.
    static func mayHaveApplied(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? KeyedWriteFailure {
            if case .needsNewKey = failure.disposition { return false }
            return true
        }
        guard let api = error as? APIError else { return true }
        guard let status = api.statusCode else { return api != .refreshDeferred && sentKinds.contains(api.kind) }
        return status == 408 || !(400..<500).contains(status)
    }

    /// Runs the write; on success, or a failure that may have applied, marks once if the session it was sent in is still current.
    /// The value and the error pass through unchanged.
    @MainActor static func run<T: Sendable>(generation: UUID, isCurrent: @MainActor (UUID) -> Bool, mark: @MainActor () -> Void,
                                             _ operation: @MainActor () async throws -> T) async throws -> T {
        do {
            let value = try await operation()
            if isCurrent(generation) { mark() }
            return value
        } catch {
            if mayHaveApplied(error), isCurrent(generation) { mark() }
            throw error
        }
    }

    /// Errors without a status that may come after the request left.
    private static let sentKinds: Set<APIError.Kind> = [.transport, .response, .stream]
}
