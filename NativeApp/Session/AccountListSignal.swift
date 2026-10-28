import Foundation
import Observation

/// X03, contracts §3: the session's “账号列表需要完整刷新”. A detail write the list cannot see (删除账号, 恢复原代理, 换代理)
/// bumps it; the account tab reloads when it moves (20 §1.6, §3.4). AppModel makes one per session.
@MainActor @Observable
final class AccountListSignal {
    private(set) var revision = 0
    func bump() { revision &+= 1 }
}
