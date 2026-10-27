import Foundation

/// C08 run view (`accounts.test_runs`). The raw error and response texts stay private: only their redacted forms leave this type,
/// and verdicts read `status`, `error_kind` and `upstream_status_code` alone.
public struct AccountTestRun: Decodable, Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case running, success, failed, interrupted
        /// A value this App does not know, or none.
        case unknown
    }
    public let runID: String
    public let accountID: Int
    /// manual | async | scheduled.
    public let source: String?
    public let status: Status
    public let model: String?
    public let latencyMs: Int?
    public let firstTokenMs: Int?
    public let upstreamStatusCode: Int?
    public let errorKind: String?
    public let errorSummary: String?
    public let recovery: AccountTestResult.Recovery?
    public let startedAt: Date?
    public let finishedAt: Date?
    private let errorMessage: String?
    private let responseText: String?

    public var sanitizedErrorText: String? { Self.redacted(errorMessage) }
    public var sanitizedResponseText: String? { Self.redacted(responseText) }
    public var isFinished: Bool { status != .running }

    /// Backend `IsAccountTestRunID` (tr_ prefix, at most 40), narrowed to ASCII letters, digits and `_` so the id is safe in a path.
    public static func isValidRunID(_ value: String) -> Bool {
        guard value.hasPrefix(runIDPrefix), (runIDPrefix.count + 1...40).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }
    }
    static let runIDPrefix = "tr_"

    public init(runID: String, accountID: Int, source: String? = nil, status: Status, model: String? = nil, latencyMs: Int? = nil,
                firstTokenMs: Int? = nil, upstreamStatusCode: Int? = nil, errorKind: String? = nil, errorSummary: String? = nil,
                recovery: AccountTestResult.Recovery? = nil, startedAt: Date? = nil, finishedAt: Date? = nil, errorMessage: String? = nil,
                responseText: String? = nil) {
        self.runID = runID; self.accountID = accountID; self.source = source; self.status = status; self.model = model
        self.latencyMs = latencyMs; self.firstTokenMs = firstTokenMs; self.upstreamStatusCode = upstreamStatusCode
        self.errorKind = AccountTestOutput.nonBlank(errorKind); self.errorSummary = AccountTestOutput.nonBlank(errorSummary)
        self.recovery = recovery; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.errorMessage = errorMessage; self.responseText = responseText
    }
    enum CodingKeys: String, CodingKey {
        case runID = "run_id", accountID = "account_id", source, status, model, latencyMs = "latency_ms", firstTokenMs = "first_token_ms"
        case upstreamStatusCode = "upstream_status_code", errorKind = "error_kind", errorSummary = "error_summary", recovery
        case startedAt = "started_at", finishedAt = "finished_at", errorMessage = "error_message", responseText = "response_text"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status = (try? c.decodeIfPresent(String.self, forKey: .status)).flatMap(Status.init(rawValue:)) ?? .unknown
        self.init(runID: try c.decode(String.self, forKey: .runID), accountID: try c.decode(Int.self, forKey: .accountID),
                  source: try? c.decodeIfPresent(String.self, forKey: .source), status: status,
                  model: try? c.decodeIfPresent(String.self, forKey: .model),
                  latencyMs: try? c.decodeIfPresent(Int.self, forKey: .latencyMs),
                  firstTokenMs: try? c.decodeIfPresent(Int.self, forKey: .firstTokenMs),
                  upstreamStatusCode: try? c.decodeIfPresent(Int.self, forKey: .upstreamStatusCode),
                  errorKind: try? c.decodeIfPresent(String.self, forKey: .errorKind),
                  errorSummary: try? c.decodeIfPresent(String.self, forKey: .errorSummary),
                  recovery: try? c.decodeIfPresent(AccountTestResult.Recovery.self, forKey: .recovery),
                  startedAt: try c.optionalTimestamp(.startedAt), finishedAt: try c.optionalTimestamp(.finishedAt),
                  errorMessage: try? c.decodeIfPresent(String.self, forKey: .errorMessage),
                  responseText: try? c.decodeIfPresent(String.self, forKey: .responseText))
    }
    private static func redacted(_ text: String?) -> String? {
        AccountTestOutput.nonBlank(text).map(AccountTestOutput.sanitize)
    }
}

public enum AccountTestRunStart: Sendable, Equatable {
    case started(AccountTestRun)
    /// 409 ACCOUNT_TEST_RUNNING: poll this run instead.
    case alreadyRunning(runID: String)
}

/// The JSON body of `POST :id/test` and `POST :id/test-runs`: `model_id` is always sent (blank → the server's default model),
/// `prompt` and `mode` only when they are not blank.
struct AccountTestBody: Encodable, Sendable {
    let modelID: String
    let prompt: String?
    let mode: String?
    let recoverOnSuccess: Bool?
    init(modelID: String?, prompt: String? = nil, mode: String? = nil, recoverOnSuccess: Bool? = nil) {
        self.modelID = AccountTestOutput.nonBlank(modelID) ?? ""
        self.prompt = AccountTestOutput.nonBlank(prompt); self.mode = AccountTestOutput.nonBlank(mode)
        self.recoverOnSuccess = recoverOnSuccess
    }
    enum CodingKeys: String, CodingKey { case modelID = "model_id", prompt, mode, recoverOnSuccess = "recover_on_success" }
}

extension APIClient {
    /// 202 with the run (status running). An unkeyed write sent once: 409 ACCOUNT_TEST_RUNNING with a usable `metadata.run_id`
    /// reads as `.alreadyRunning`; 429 ACCOUNT_TEST_BUSY is thrown with its wait (00 §2.7.2, 30 seconds when the server sends none).
    public func startTestRun(accountID: Int, modelID: String?, recoverOnSuccess: Bool = true) async throws -> AccountTestRunStart {
        let body = AccountTestBody(modelID: modelID, recoverOnSuccess: recoverOnSuccess)
        do {
            let run: AccountTestRun = try await request(accountPath(accountID, "/test-runs"), method: "POST", body: encode(body))
            return .started(run)
        } catch let error as APIError where error.statusCode == 409 && error.reason == AccountTestRunReason.running {
            guard let runID = error.metadata["run_id"], AccountTestRun.isValidRunID(runID) else { throw error }
            return .alreadyRunning(runID: runID)
        }
    }
    /// The newest run of the account (async or manual); nil for 404 ACCOUNT_TEST_RUN_NOT_FOUND. Other failures, including a
    /// non-JSON 404 from a server without the route, are thrown.
    public func latestTestRun(accountID: Int) async throws -> AccountTestRun? {
        do {
            let run: AccountTestRun = try await request(accountPath(accountID, "/test-runs/latest"))
            return run
        } catch let error as APIError where error.statusCode == 404 && error.reason == AccountTestRunReason.notFound {
            return nil
        }
    }
    /// A malformed id is refused here and never reaches the path.
    public func testRun(runID: String) async throws -> AccountTestRun {
        guard AccountTestRun.isValidRunID(runID) else { throw APIError(kind: .validation, message: "无效的测试编号。") }
        return try await request("admin/account-test-runs/\(runID)")
    }
}

enum AccountTestRunReason {
    static let running = "ACCOUNT_TEST_RUNNING"
    static let notFound = "ACCOUNT_TEST_RUN_NOT_FOUND"
}
