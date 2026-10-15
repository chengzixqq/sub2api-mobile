import Foundation

public struct APIError: LocalizedError, Sendable, Equatable {
    public enum Kind: String, Sendable { case authentication, permission, captcha, twoFactor, sessionBinding, compliance, response, transport, validation, stream }
    public let kind: Kind
    public let reason: String?
    public let statusCode: Int?
    private let message: String
    public var errorDescription: String? { message }
    public init(kind: Kind, reason: String? = nil, statusCode: Int? = nil, message: String) {
        self.kind = kind; self.reason = reason; self.statusCode = statusCode; self.message = message
    }
    public static let invalidServer = APIError(kind: .validation, message: "请输入不含路径、账号或查询参数的 HTTPS 站点地址。")
    public static let invalidAmount = APIError(kind: .validation, message: "金额必须为非负十进制数，用户编号必须有效。")
    public static let invalidResponse = APIError(kind: .response, message: "服务器响应格式不符合当前接口契约。")
    public static let authenticationRequired = APIError(kind: .authentication, statusCode: 401, message: "登录已失效，请重新登录。")
    public static let administratorRequired = APIError(kind: .permission, statusCode: 403, message: "当前版本仅支持管理员账号，普通用户功能尚未开放。")
    public static let stationMismatch = APIError(kind: .validation, message: "该操作属于其他站点，已阻止发送。")
    public static let incompleteStream = APIError(kind: .stream, message: "连接已结束，但未收到测试完成结果；请检查后手动重试。")
    public static let malformedStream = APIError(kind: .stream, message: "账号测试返回了无法解析的数据。")
    public static func server(status: Int, reason: String?) -> APIError {
        // Server messages can contain upstream URLs, credentials or HTML. Never echo them into UI/logs.
        let code = reason?.uppercased() ?? ""
        if code.contains("CAPTCHA") || code.contains("TURNSTILE") { return APIError(kind: .captcha, reason: reason, statusCode: status, message: "验证码未通过或已过期，请重新完成验证。") }
        if code.contains("SESSION_BIND") { return APIError(kind: .sessionBinding, reason: reason, statusCode: status, message: "网络或设备信息变化导致会话失效，请重新登录。") }
        if code.contains("AGREEMENT") || code.contains("COMPLIANCE") { return APIError(kind: .compliance, reason: reason, statusCode: status, message: "请先在本站 Web 后台完成合规或协议确认，再重新登录。") }
        if code.contains("TOTP") || code.contains("STEP_UP") || code.contains("2FA") || status == 423 { return APIError(kind: .twoFactor, reason: reason, statusCode: status, message: "该操作需要有效的双因素验证码，请完成二次验证后手动重试。") }
        if status == 401 { return APIError(kind: .authentication, reason: reason, statusCode: status, message: "认证失败或会话已失效，请检查凭据并重新登录。") }
        if status == 403 { return APIError(kind: .permission, reason: reason, statusCode: status, message: "当前身份没有执行此操作的权限。") }
        if status == 409 { return APIError(kind: .response, reason: reason, statusCode: status, message: "操作存在冲突或尚未完成，请保留原操作编号后重试。") }
        if status == 429 { return APIError(kind: .transport, reason: reason, statusCode: status, message: "请求过于频繁，请稍后手动重试。") }
        return APIError(kind: .response, reason: reason, statusCode: status, message: "服务器未能完成请求（HTTP \(status)）。")
    }
    static func transport(_ error: any Error) -> APIError {
        if let e = error as? APIError { return e }
        let code = (error as NSError).code
        if code == NSURLErrorTimedOut { return APIError(kind: .transport, message: "连接超时；写操作结果可能尚未确认，请勿新建重复操作。") }
        return APIError(kind: .transport, message: "无法连接到站点，请检查网络与服务器状态。")
    }
}
