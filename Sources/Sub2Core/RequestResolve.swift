import Foundation

// S4-08b: 40 §7.3 / §7.4 标记已处理 and the IDs it copies; the request detail draws them (RequestResolveControls).

/// How a 标记已处理 or its undo ended when it did not land. nil: cancelled, or the security prompt was closed (nothing to say).
/// `resultUnknown`: no answer (transport, a 2xx that broke the contract) or a gateway's 502 / 503 / 504, which the detail read back
/// decides (00 §2.4). The handler's own 400s have no reason, so they are program errors.
public enum RequestResolveFailure: Equatable, Sendable {
    case gone, opsDisabled, readOnly, rateLimited(String), resultUnknown, programError, refused

    public init?(_ error: any Error) {
        guard !(error is CancellationError) else { return nil }
        guard let error = error as? APIError else { self = .resultUnknown; return }
        guard error.securityOutcome != .cancelled else { return nil }
        switch (error.statusCode, error.reason) {
        case (404?, "OPS_ERROR_NOT_FOUND"?): self = .gone
        case (404?, "OPS_DISABLED"?): self = .opsDisabled
        case (403?, "ACCESS_TOKEN_READ_ONLY"?): self = .readOnly
        case (429?, _): self = .rateLimited(error.localizedDescription)
        case (400?, .none): self = .programError
        case (.none, _): self = error.kind == .transport || error == .invalidResponse ? .resultUnknown : .refused
        case (let status?, let reason):
            self = RequestPolicy.isRetryableStatus(status, marker: reason) && SecurityInterruption(error) == nil ? .resultUnknown : .refused
        }
    }
}

/// 40 §7.3 / §7.4 wording of 标记已处理 (S4D2a-08); the design's undone and taken-back marks say nothing.
extension RequestDetailCopy {
    public static let markTitle = "标记已处理"
    /// Drawn as “已处理 ✓”.
    public static let resolvedTitle = "已处理"
    public static let resolvedHint = "点按改回未处理"
    public static let marked = "已标记为已处理"
    public static let markFailed = "标记失败，请重试"
    public static let unmarkFailed = "撤回失败，请重试"
    public static let resolveGone = "记录已不存在"
    public static let resolveOpsDisabled = "运维监控未开启，无法标记"
    /// 00 §2.4: neither the write nor the read-back answered.
    public static let unconfirmed = "结果未确认，请刷新核对后再操作"
    public static let copyHint = "点按复制"
    public static let moreMenu = "更多"
    public static var readOnly: String { ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message }

    /// The same words both ways for a gone record, ops off, a read-only token and 429; otherwise the direction's own.
    public static func failureText(_ failure: RequestResolveFailure, marking: Bool) -> String {
        switch failure {
        case .gone: resolveGone
        case .opsDisabled: resolveOpsDisabled
        case .readOnly: readOnly
        case .rateLimited(let text): text
        case .resultUnknown, .programError, .refused: marking ? markFailed : unmarkFailed
        }
    }
}

extension RequestIdentifierRow.Kind {
    /// 40 §7.1 导航栏 ···: 复制请求 ID and 复制上游请求 ID; 服务端请求 ID is copied from its row only.
    public var menuTitle: String? {
        switch self {
        case .request: "复制请求 ID"
        case .client: nil
        case .upstream: "复制上游请求 ID"
        }
    }
    public var copiedReceipt: String {
        switch self {
        case .request: "已复制请求 ID"
        case .client: "已复制服务端请求 ID"
        case .upstream: "已复制上游请求 ID"
        }
    }
}

extension RequestIdentifierRow {
    /// 请求 ID always shows, as “—” without a value; that copies nothing.
    public var isCopyable: Bool { value != DisplayFormat.missing }
}

extension RequestDetailLayout {
    /// The ··· menu: the rows with a menu title and a value, in `identifiers` order.
    public static func menuIdentifiers(_ rows: [RequestIdentifierRow]) -> [RequestIdentifierRow] {
        rows.filter { $0.kind.menuTitle != nil && $0.isCopyable }
    }
}

extension IncrementalList where Record == RequestErrorRecord {
    /// 40 §7.4: only the row with this id changes; order, cursor and limit stay. nil when the list does not hold it.
    public func settingResolved(_ resolved: Bool, id: Int) -> IncrementalList<RequestErrorRecord>? {
        guard items.contains(where: { $0.id == id }) else { return nil }
        return IncrementalList(items: items.map { $0.id == id ? $0.settingResolved(resolved) : $0 }, cursor: cursor, limit: limit)
    }
}
