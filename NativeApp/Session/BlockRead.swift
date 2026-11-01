import Foundation

/// 00 §4.6: one data block's reads, one at a time. Each read is this object's task, so a page or a pull that goes away does not
/// cancel it. A page keeps one per block, so a slow block, or one waiting out a 429, holds back no other block.
@MainActor
final class BlockRead {
    typealias Read = @MainActor @Sendable () async -> Void

    private var running: Task<Void, Never>?
    private var next: Task<Void, Never>?

    init() {}

    var isRunning: Bool { running != nil }

    /// Sends `read` unless a read is out, which then stands for it. Does not wait.
    func start(_ read: @escaping Read) {
        guard running == nil else { return }
        running = Task {
            await read()
            self.running = nil
        }
    }
    /// A read sent no earlier than this call, so a write made before the call is in its answer: at once, or after the read that is
    /// out, shared by every call that comes in the meantime. Returns when that read has ended.
    func refresh(_ read: @escaping Read) async {
        if let next { return await next.value }
        guard let running else {
            start(read)
            await self.running?.value
            return
        }
        let following = Task {
            await running.value
            self.next = nil
            self.start(read)
            await self.running?.value
        }
        next = following
        await following.value
    }
}
