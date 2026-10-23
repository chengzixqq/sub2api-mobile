import Foundation

/// The object kinds of the global search (60 §2) and of its “查看全部” route `.searchResults(kind:query:)`.
/// Stage 6 adds the search fan-out to this file (60 §2.7).
public enum SearchResultKind: String, CaseIterable, Hashable, Sendable {
    case accounts, users, groups, proxies

    public var title: String {
        switch self {
        case .accounts: "账号"
        case .users: "用户"
        case .groups: "分组"
        case .proxies: "代理"
        }
    }
}
