import Foundation

/// The code a log row's badge and the 20 §2.7 account status card show for an upstream error (40 §6.3, U32). List items
/// carry no `upstream_status_code`, so a row the retry recovered (`status_code` < 400) is read from its message, which the
/// backend does not promise to keep.
public enum UpstreamErrorStatus: Hashable, Sendable {
    case code(Int)
    /// A recovered account authentication failure without a code (“鉴权”).
    case accountAuth
    /// Any other recovered row without a code (“恢复”).
    case unknown
}

extension RequestErrorRecord {
    public var upstreamStatus: UpstreamErrorStatus {
        if statusCode >= 400 { return .code(statusCode) }
        if let match = message.range(of: #"^Recovered upstream error \d{3}\b"#, options: .regularExpression),
           let code = Int(message[match].suffix(3)), (100...599).contains(code) {
            return .code(code)
        }
        return phase == "account_auth" ? .accountAuth : .unknown
    }
}
