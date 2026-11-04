import Foundation
import Sub2Core

/// 10 §0.7-4: the chip and platform an account tab intent asks for. Without a filter it is the tab's default view, 全部.
struct AccountsListSelection: Equatable, Sendable {
    let chip: AccountListChip
    /// nil = every platform.
    let platform: String?
}

extension TabIntent {
    /// nil for another tab's intent.
    var accountsListSelection: AccountsListSelection? {
        guard case .accounts(let filter, let platform) = self else { return nil }
        return AccountsListSelection(chip: filter?.chip ?? .all, platform: platform)
    }
}

extension AccountsTabFilter {
    var chip: AccountListChip {
        switch self {
        case .needs: .needs
        case .limited: .limited
        case .paused: .paused
        }
    }
}
