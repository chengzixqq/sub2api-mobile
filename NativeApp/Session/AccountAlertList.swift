import Foundation
import Sub2Core

extension AccountAlertMatch {
    /// S2-22: whether the account headers may read LiveOpsStore's firing list. LoadState keeps `lastErrorAt` until a read
    /// succeeds, through a retry and a cancelled one, so the old list either carries never brings an alert back (20 §1.5).
    @MainActor static func isListUsable(_ list: LoadState<[AlertEvent]>, opsDisabled: Bool) -> Bool {
        isListUsable(list.state, lastReadFailed: list.lastErrorAt != nil, opsDisabled: opsDisabled)
    }
}
