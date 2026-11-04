import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 10 §1.4, X17 (S2-23): an account write that ran, or may have run, makes the home page read past the server cache next time.

private let unsent: [(String, any Error)] = [
    ("cancelled", CancellationError()),
    ("local check", APIError(kind: .validation, message: "x")),
    ("old server credentials", APIError(kind: .unsupported, reason: "LEGACY_CREDENTIALS_PUT", message: "x")),
    ("refresh before sending", APIError.refreshDeferred),
    ("412", APIError.server(status: 412, reason: "ACCOUNT_VERSION_CONFLICT")),
    ("409 mixed channel", APIError.server(status: 409, reason: "MIXED_CHANNEL_WARNING")),
    ("404", APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND")),
    ("403 read only", APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")),
    ("423", APIError.server(status: 423, reason: nil)),
    ("429", APIError.server(status: 429, envelope: nil, retryAfter: 3)),
    ("400", APIError.server(status: 400, reason: "CREDENTIAL_KEY_NOT_DELETABLE")),
    ("new key", KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))
]
private let maybeSent: [(String, any Error)] = [
    ("500", APIError.server(status: 500, reason: nil)),
    ("500 persist", APIError.server(status: 500, reason: "REAUTH_PERSIST_FAILED")),
    ("502", APIError.server(status: 502, reason: nil)),
    ("503", APIError.server(status: 503, reason: nil)),
    ("504", APIError.server(status: 504, reason: nil)),
    ("408", APIError.server(status: 408, reason: nil)),
    ("transport", APIError(kind: .transport, message: "x")),
    ("unreadable 2xx", APIError.invalidResponse),
    ("unconfirmed key", KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)),
    ("URLError", URLError(.timedOut))
]

@Test func mayHaveAppliedSeparatesSentFromUnsent() {
    for (name, error) in unsent { #expect(!AccountWriteMark.mayHaveApplied(error), "\(name)") }
    for (name, error) in maybeSent { #expect(AccountWriteMark.mayHaveApplied(error), "\(name)") }
}

@MainActor private final class Marks {
    var current = UUID()
    var count = 0
}

@MainActor @Test func runMarksOnceAfterSuccessOrMaybeAppliedFailureInSameSession() async throws {
    let marks = Marks()
    func run<T: Sendable>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try await AccountWriteMark.run(generation: marks.current, isCurrent: { $0 == marks.current }, mark: { marks.count += 1 }, operation)
    }
    #expect(try await run { 7 } == 7)
    #expect(marks.count == 1)

    let serverError = APIError.server(status: 500, reason: nil)
    await #expect(throws: serverError) { try await run { () throws -> Int in throw serverError } }
    #expect(marks.count == 2)
    let conflict = APIError.server(status: 412, reason: "ACCOUNT_VERSION_CONFLICT")
    await #expect(throws: conflict) { try await run { () throws -> Int in throw conflict } }
    await #expect(throws: CancellationError.self) { try await run { () throws -> Int in throw CancellationError() } }
    #expect(marks.count == 2)

    // The site changed while the write was out: nothing is marked for the new session.
    #expect(try await run { () -> String in marks.current = UUID(); return "ok" } == "ok")
    #expect(marks.count == 2)
    try await run { () }
    try await run { () }
    #expect(marks.count == 4)
}
