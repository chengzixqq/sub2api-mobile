import Foundation

/// The site teardowns in progress, by address (MoneyRecordOrigin.addressKey). Deleting a site sends its server steps for up to
/// 20 seconds (SiteTeardown.deadline); logging in again at the same address meanwhile must not register a push device the
/// late DELETE then removes, so PushCoordinator waits here first (BACKLOG “推送登记要等待该站点的收尾结束”). App-level (X03).
@MainActor
final class SiteTeardownTracker {
    private var running: [UUID: (address: String?, done: () async -> Void)] = [:]

    var isIdle: Bool { running.isEmpty }

    /// Runs `work` as one teardown of `address` until it returns; cancelling the caller cancels the work.
    func run<T: Sendable>(address: String?, _ work: @escaping @MainActor @Sendable () async -> T) async -> T {
        let id = UUID()
        let task = Task { await work() }
        running[id] = (address, { _ = await task.value })
        defer { running[id] = nil }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// Returns once every teardown of `address` running now has ended; at once without an address.
    func waitForTeardowns(address: String?) async {
        guard let address else { return }
        for entry in running.values where entry.address == address { await entry.done() }
    }
}
