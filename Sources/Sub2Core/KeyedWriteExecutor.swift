import Foundation

/// One intent, one key (00 §2.5.2): the key is also X-Request-ID and the body bytes are fixed before the first attempt.
struct KeyedWriteRequest: Sendable {
    let path: String
    let method: String
    let body: Data
    let key: UUID
    var timeout: TimeInterval = RequestTimeout.keyedWrite
}

/// What one attempt produced: a reply, or a transient transport error that the confirmation flow may retry.
enum KeyedAttempt: Sendable {
    case reply(HTTPResponse)
    case lost(APIError)
}

/// 00 §2.5.3–§2.5.4 as a state machine: transport failures retry twice (2 s, 5 s); IN_PROGRESS and RETRY_BACKOFF wait
/// Retry-After, at most 30 s counted from the first such reply; key problems need a new key; STORE_UNAVAILABLE is not
/// retried for 10 s. A 429 is a business answer (00 §2.7.2: writes never retry it on their own).
struct KeyedWriteFlow: Sendable {
    enum Step: Sendable {
        case succeeded(HTTPResponse)
        case rejected(HTTPResponse)
        case unresolved(KeyedWriteFailure.Disposition)
        case retry(after: Duration, KeyedWriteEvent)
    }
    /// Turned away by the middleware before the handler and its idempotency record (00 §0 rule 5, §2.4).
    static let refusedBeforeHandler: Set<Int> = [401, 403, 423, 429]
    private(set) var actionID: UUID?
    /// An earlier attempt may have run: lost, 502/504/proxy 503, IN_PROGRESS or RETRY_BACKOFF. From then on only a 2xx or a
    /// business answer settles the write (00 §2.5.4 step 2); a later attempt refused before the handler says nothing about it.
    private(set) var mayHaveRun = false
    private var transportRetries = 0
    private var waitingSince: Date?

    /// The X-Admin-Adjustment-Action-ID the first time a reply carries one.
    mutating func newActionID(in attempt: KeyedAttempt) -> UUID? {
        guard actionID == nil, case .reply(let response) = attempt,
              let id = response.header("X-Admin-Adjustment-Action-ID").flatMap(UUID.init(uuidString:)) else { return nil }
        actionID = id
        return id
    }
    mutating func next(after attempt: KeyedAttempt, now: Date) -> Step {
        guard case .reply(let response) = attempt else { return transportRetry() }
        switch IdempotencyOutcome.classify(response) {
        case .succeeded: return .succeeded(response)
        case .rejected where mayHaveRun && Self.refusedBeforeHandler.contains(response.statusCode):
            return .unresolved(.unconfirmed(.transport, retryNotBefore: nil))
        case .rejected: return .rejected(response)
        case .transportFailure: return transportRetry()
        case .inProgress(let seconds), .retryBackoff(let seconds): return serverWait(seconds, now: now)
        case .unreadableSuccess: return .unresolved(.unconfirmed(.unreadableResponse, retryNotBefore: nil))
        case .storeUnavailable:
            return .unresolved(.unconfirmed(.storeUnavailable, retryNotBefore: now.addingTimeInterval(IdempotencyPolicy.storeUnavailableCooldown)))
        case .keyConflict: return .unresolved(.needsNewKey(.keyConflict))
        case .invalidKeyOrPayload: return .unresolved(.needsNewKey(.invalid))
        case .keyRequired: return .unresolved(.needsNewKey(.keyRequired))
        }
    }
    private mutating func transportRetry() -> Step {
        mayHaveRun = true
        guard IdempotencyPolicy.transportRetryDelays.indices.contains(transportRetries) else {
            return .unresolved(.unconfirmed(.transport, retryNotBefore: nil))
        }
        let delay = IdempotencyPolicy.transportRetryDelays[transportRetries]
        transportRetries += 1
        return .retry(after: delay, .confirming(retry: transportRetries))
    }
    private mutating func serverWait(_ seconds: Int, now: Date) -> Step {
        mayHaveRun = true
        let since = waitingSince ?? now
        waitingSince = since
        let elapsed = now.timeIntervalSince(since), remaining = IdempotencyPolicy.waitBudget - elapsed
        guard remaining > 0 else { return .unresolved(.unconfirmed(.stillProcessing, retryNotBefore: nil)) }
        return .retry(after: .seconds(min(Double(seconds), remaining)), .waitingForServer(elapsedSeconds: Int(elapsed)))
    }
}

extension APIClient {
    /// Every attempt goes through `sendAttempt`, so a TOKEN_EXPIRED refresh resends the same bytes without counting as a retry.
    /// Ends as a value, a KeyedWriteFailure, or the catalog APIError (through `surfaced`); waits are bound to the generation.
    /// Stage 2/5/6 keyed endpoints (redeem codes, compensation, groups, accounts, announcements…) reuse this.
    func performKeyedWrite<T: Decodable & Sendable>(_ write: KeyedWriteRequest, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<T> {
        let snapshot = currentGeneration()
        let spec = OutgoingRequest(path: write.path, method: write.method, body: write.body, requestClass: .keyedWrite(key: write.key), timeout: write.timeout)
        let key = write.key.uuidString.lowercased()
        var flow = KeyedWriteFlow()
        while true {
            let attempt: KeyedAttempt
            do { attempt = try await keyedAttempt(spec, generation: snapshot) }
            // No valid credential for a retry (refresh rejected, session ended) leaves an attempt that may have run unconfirmed.
            catch let error as APIError where flow.mayHaveRun {
                throw KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: key, actionID: flow.actionID, lastError: error)
            }
            if let id = flow.newActionID(in: attempt) { await onEvent?(.actionID(id)) }
            switch flow.next(after: attempt, now: requestClock.now()) {
            case .succeeded(let response): return try keyedOutcome(response, key: key, actionID: flow.actionID)
            case .rejected(let response): throw surfaced(failure(response), context: .business, generation: snapshot)
            case .unresolved(let disposition):
                throw KeyedWriteFailure(disposition: disposition, key: key, actionID: flow.actionID, lastError: lastError(of: attempt, generation: snapshot))
            case .retry(let delay, let event): try await waitToRetry(delay, event: event, onEvent: onEvent, generation: snapshot)
            }
        }
    }
    /// A frozen write the site cannot replay: sent once with its operation number as X-Request-ID, never retried (00 §2.4).
    func performUnkeyedWrite<T: Decodable & Sendable>(_ path: String, method: String, body: Data, requestID: String) async throws -> WriteOutcome<T> {
        let response: APIResponse<T> = try await requestWithHeaders(path, method: method, body: body, requestClass: .unkeyedWrite, requestID: requestID)
        return WriteOutcome(value: response.value, headers: response.headers)
    }

    /// The only wait between two attempts; S0-11 turns a wait interrupted by suspend into unconfirmed(.transport) here (D18).
    private func waitToRetry(_ delay: Duration, event: KeyedWriteEvent, onEvent: KeyedWriteEventHandler?, generation snapshot: UUID) async throws {
        await onEvent?(event)
        try await pause(delay, generation: snapshot)
    }
    /// A reply, or a transient transport error handed back for the flow to retry; anything else is thrown.
    private func keyedAttempt(_ spec: OutgoingRequest, generation snapshot: UUID) async throws -> KeyedAttempt {
        do { return .reply(try await sendAttempt(spec, context: .business, generation: snapshot)) }
        catch let error as APIError { throw surfaced(error, context: .business, generation: snapshot) }
        catch is CancellationError { throw CancellationError() }
        catch let error where RequestPolicy.isRetryableNetworkError(error) { return .lost(APIError.transport(error)) }
        catch { throw surfaced(APIError.transport(error), context: .business, generation: snapshot) }
    }
    /// A 2xx whose data cannot be read may still have been executed, so it is unconfirmed rather than an error.
    private func keyedOutcome<T: Decodable & Sendable>(_ response: HTTPResponse, key: String, actionID: UUID?) throws -> WriteOutcome<T> {
        do { return WriteOutcome(value: try Self.decode(response), headers: response.headers) }
        catch {
            throw KeyedWriteFailure(disposition: .unconfirmed(.unreadableResponse, retryNotBefore: nil), key: key, actionID: actionID,
                                    lastError: error as? APIError ?? .invalidResponse)
        }
    }
    /// A reply's error leaves through `surfaced` even inside a KeyedWriteFailure, so S0-11 also sees a 401 that ends a retry.
    private func lastError(of attempt: KeyedAttempt, generation snapshot: UUID) -> APIError {
        switch attempt {
        case .reply(let response): surfaced(failure(response), context: .business, generation: snapshot)
        case .lost(let error): error
        }
    }
}
