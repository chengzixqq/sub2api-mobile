import Foundation

public struct APIError: LocalizedError, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case authentication, permission, captcha, twoFactor, sessionBinding, compliance, response, transport, validation, stream
        case stepUp, readOnly, rateLimited, idempotency, conflict, notFound, unsupported, featureDisabled, temporary
    }
    /// One row of the error “details” disclosure (00 §3.4); the time row is added by the UI.
    public struct Diagnostic: Sendable, Equatable {
        public let label: String
        public let value: String
    }
    public let kind: Kind
    public let reason: String?
    public let statusCode: Int?
    /// Catalog classification for server errors; nil for locally raised errors.
    public let category: ReasonCatalog.Category?
    public let action: ReasonCatalog.Action?
    public let retryAfter: Int?
    public let metadata: [String: String]
    /// Response header `X-Request-ID`.
    public let requestID: String?
    private let message: String
    public var errorDescription: String? { message }
    public init(kind: Kind, reason: String? = nil, statusCode: Int? = nil, message: String, category: ReasonCatalog.Category? = nil,
                action: ReasonCatalog.Action? = nil, retryAfter: Int? = nil, metadata: [String: String] = [:], requestID: String? = nil) {
        self.kind = kind; self.reason = reason; self.statusCode = statusCode; self.message = message
        self.category = category; self.action = action; self.retryAfter = retryAfter; self.metadata = metadata; self.requestID = requestID
    }
    public static let invalidServer = APIError(kind: .validation, message: "请输入不含路径、账号或查询参数的 HTTPS 站点地址。")
    public static let invalidAmount = APIError(kind: .validation, message: "金额最多 8 位小数且不得超过 999999999999.99999999；增加或减少金额必须大于零。")
    public static let invalidResponse = APIError(kind: .response, message: "服务器响应格式不符合当前接口契约。")
    public static let authenticationRequired = APIError(kind: .authentication, statusCode: 401, message: "登录已失效，请重新登录",
                                                        category: .sessionExpired, action: .clearSession)
    public static let administratorRequired = APIError(kind: .permission, statusCode: 403, message: "当前版本仅支持管理员账号，普通用户功能尚未开放。")
    public static let stationMismatch = APIError(kind: .validation, message: "该操作属于其他站点，已阻止发送。")
    public static let incompleteStream = APIError(kind: .stream, message: "连接已结束，但未收到测试完成结果；请检查后手动重试。")
    public static let malformedStream = APIError(kind: .stream, message: "账号测试返回了无法解析的数据。")

    /// Classifies a server error that had a JSON body with this reason.
    public static func server(status: Int, reason: String?, context: ReasonCatalog.Context = .business) -> APIError {
        server(status: status, envelope: ErrorEnvelope(reason: reason), context: context)
    }
    /// `envelope == nil` means the body was not JSON. Server messages can contain upstream URLs, credentials
    /// or HTML, so the text always comes from the catalog and never from the response.
    public static func server(status: Int, envelope: ErrorEnvelope?, context: ReasonCatalog.Context = .business,
                              requestID: String? = nil, retryAfter: Int? = nil) -> APIError {
        let reason = envelope?.marker
        let seconds = retryAfter ?? RetryAfter.resolve(headers: [:], envelope: envelope)
        let entry = ReasonCatalog.entry(status: status, reason: reason, context: context, bodyIsJSON: envelope != nil, retryAfter: seconds)
        return APIError(kind: entry.kind, reason: reason, statusCode: status, message: entry.message, category: entry.category,
                        action: entry.action, retryAfter: seconds, metadata: envelope?.metadata ?? [:], requestID: requestID)
    }
    /// 00 §3.1: 304 is never decoded; 2xx with a non-zero code is handled as 500; 2xx without a code breaks the contract.
    public static func from(_ response: HTTPResponse, context: ReasonCatalog.Context = .business) -> APIError {
        let requestID = response.header("X-Request-ID")
        guard response.statusCode != 304 else { return server(status: 304, envelope: nil, context: context, requestID: requestID) }
        let envelope = ErrorEnvelope.decode(response.data)
        var status = response.statusCode
        if (200..<300).contains(status) {
            guard let envelope, envelope.code != nil, !envelope.isSuccess else { return .invalidResponse }
            status = 500
        }
        return server(status: status, envelope: envelope, context: context, requestID: requestID,
                      retryAfter: RetryAfter.resolve(headers: response.headers, envelope: envelope))
    }
    public var diagnostics: [Diagnostic] {
        [Diagnostic(label: "HTTP 状态", value: statusCode.map(String.init) ?? "—"),
         Diagnostic(label: "错误码", value: reason ?? "—"),
         Diagnostic(label: "请求 ID", value: requestID ?? "—")]
    }
    static func transport(_ error: any Error) -> APIError {
        if let e = error as? APIError { return e }
        let code = (error as NSError).code
        if code == NSURLErrorTimedOut { return APIError(kind: .transport, message: "连接超时；写操作结果可能尚未确认，请勿新建重复操作。") }
        return APIError(kind: .transport, message: "无法连接站点")
    }
}
