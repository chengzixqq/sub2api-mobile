import Foundation
import Testing
@testable import NativeSessionSupport

/// Counts the reads a block sent.
@MainActor private final class ReadLog {
    var calls = 0
}

/// Each read counts itself, then waits for `gate` when there is one.
@MainActor private func counting(_ log: ReadLog, gate: SessionGate? = nil) -> BlockRead.Read {
    {
        log.calls += 1
        if let gate { await gate.wait() }
    }
}

private func waitForArrival(_ gate: SessionGate) async {
    while !(await gate.arrived) { await Task.yield() }
    for _ in 0..<5 { await Task.yield() }
}

@MainActor private func waitUntilIdle(_ block: BlockRead) async {
    while block.isRunning { await Task.yield() }
}

@MainActor @Test func startSharesTheReadThatIsOutAndReadsAgainAfterIt() async {
    let gate = SessionGate()
    let log = ReadLog(), block = BlockRead()
    block.start(counting(log, gate: gate))
    await waitForArrival(gate)
    block.start(counting(log, gate: gate))
    #expect(log.calls == 1 && block.isRunning)
    await gate.open()
    await waitUntilIdle(block)
    block.start(counting(log))
    await waitUntilIdle(block)
    #expect(log.calls == 2)
}

@MainActor @Test func refreshWithNothingOutReadsAtOnceAndWaitsForIt() async {
    let log = ReadLog(), block = BlockRead()
    await block.refresh(counting(log))
    #expect(log.calls == 1 && !block.isRunning)
    await block.refresh(counting(log))
    #expect(log.calls == 2)
}

/// A refresh after a write never takes the answer of a read sent before it; refreshes meanwhile share one more read.
@MainActor @Test func refreshWhileAReadIsOutReadsOnceMoreAfterIt() async {
    let gate = SessionGate()
    let log = ReadLog(), block = BlockRead()
    block.start(counting(log, gate: gate))
    await waitForArrival(gate)
    let read = counting(log, gate: gate)
    // Main-actor tasks: both are waiting on the block before the gate opens.
    let first = Task { await block.refresh(read) }
    let second = Task { await block.refresh(read) }
    for _ in 0..<10 { await Task.yield() }
    #expect(log.calls == 1)
    await gate.open()
    await first.value
    await second.value
    #expect(log.calls == 2 && !block.isRunning)
}

/// 50 §1.2: 重试 and the pull read the list again while a slow usage-summary is still out.
@MainActor @Test func aSlowBlockHoldsBackNoOtherBlock() async {
    let gate = SessionGate()
    let usageLog = ReadLog(), listLog = ReadLog()
    let usage = BlockRead(), list = BlockRead()
    usage.start(counting(usageLog, gate: gate))
    await waitForArrival(gate)
    await list.refresh(counting(listLog))
    await list.refresh(counting(listLog))
    #expect(listLog.calls == 2 && usageLog.calls == 1 && usage.isRunning)
    await gate.open()
    await waitUntilIdle(usage)
}
