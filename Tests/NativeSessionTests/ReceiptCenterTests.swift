import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Hands out one wait per request and wakes them one by one; a cancelled wait still waits, standing in for a timer that
/// fires late.
private actor ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waits: [CheckedContinuation<Void, Never>?] = []
    func sleep(_ duration: Duration) async {
        requests.append(duration)
        await withCheckedContinuation { waits.append($0) }
    }
    var count: Int { waits.count }
    func wake(_ index: Int) { waits[index]?.resume(); waits[index] = nil }
    func wakeAll() { for index in waits.indices { wake(index) } }
}
@MainActor private final class Spoken { var texts: [String] = [] }
@MainActor private final class Calls { var names: [String] = []; var shownDuringCall: [Bool] = [] }

@MainActor private func center(_ sleeper: ManualSleeper, spoken: Spoken = Spoken()) -> ReceiptCenter {
    ReceiptCenter(sleep: { await sleeper.sleep($0) }, announce: { spoken.texts.append($0) })
}
@MainActor private func waitForTimers(_ sleeper: ManualSleeper, count: Int) async {
    var spins = 0
    while await sleeper.count < count, spins < 10_000 { await Task.yield(); spins += 1 }
}
@MainActor private func settle(until done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}

@MainActor @Test func showDisplaysReceiptAndAnnouncesOnce() async {
    let sleeper = ManualSleeper(), spoken = Spoken()
    let receipts = center(sleeper, spoken: spoken)
    receipts.show(Receipt(text: "已复制"))
    #expect(receipts.current?.text == "已复制")
    #expect(spoken.texts == ["已复制"])
    await waitForTimers(sleeper, count: 1)
    await sleeper.wakeAll()
}

@MainActor @Test(.timeLimit(.minutes(1))) func receiptDismissesAfterFourPointTwoSeconds() async {
    let sleeper = ManualSleeper()
    let receipts = center(sleeper)
    receipts.show(Receipt(text: "已保存"))
    await waitForTimers(sleeper, count: 1)
    #expect(await sleeper.requests == [.milliseconds(4200)])
    #expect(ReceiptCenter.displayDuration == .milliseconds(4200))
    await sleeper.wake(0)
    await settle { receipts.current == nil }
    #expect(receipts.current == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func newReceiptReplacesOldAndStaleTimerCannotDismissIt() async {
    let sleeper = ManualSleeper()
    let receipts = center(sleeper)
    receipts.show(Receipt(text: "A"))
    await waitForTimers(sleeper, count: 1)
    receipts.show(Receipt(text: "B"))
    await waitForTimers(sleeper, count: 2)
    #expect(receipts.current?.text == "B")
    // A's timer fires late, as if its cancellation came too late.
    await sleeper.wake(0)
    for _ in 0..<50 { await Task.yield() }
    #expect(receipts.current?.text == "B")
    await sleeper.wake(1)
    await settle { receipts.current == nil }
    #expect(receipts.current == nil)
}

@MainActor @Test func customActionWinsOverUndo() {
    let calls = Calls()
    let receipt = Receipt(text: "已加入", undo: { calls.names.append("undo") }, action: ReceiptAction(title: "查看") { calls.names.append("action") })
    #expect(receipt.action?.title == "查看")
    receipt.action?.perform()
    #expect(calls.names == ["action"])
}

@Test func undoOnlyReceiptOffersUndoAndDefaults() {
    #expect(Receipt(text: "已停止调度", undo: {}).action?.title == "撤销")
    let plain = Receipt(text: "已复制")
    #expect(plain.action == nil)
    #expect(plain.systemImage == "checkmark.circle")
    #expect(plain.tone == .ok)
}

@MainActor @Test func performActionRunsClosureThenDismisses() async {
    let sleeper = ManualSleeper()
    let receipts = center(sleeper)
    let calls = Calls()
    let stopped = Receipt(text: "已停止调度", undo: { calls.shownDuringCall.append(receipts.current != nil) })
    receipts.show(stopped)
    receipts.performAction(id: stopped.id)
    #expect(calls.shownDuringCall == [false])
    #expect(receipts.current == nil)
    // Nothing shown, or nothing to do: no effect.
    receipts.performAction(id: stopped.id)
    let copied = Receipt(text: "已复制")
    receipts.show(copied)
    receipts.performAction(id: copied.id)
    #expect(receipts.current?.text == "已复制")
    #expect(calls.shownDuringCall.count == 1)
    await waitForTimers(sleeper, count: 2)
    await sleeper.wakeAll()
}

@Test func switchedReceiptCopy() {
    let receipt = Receipt.switched(to: "站点 B")
    #expect(receipt.text == "已切换到 站点 B")
    #expect(receipt.systemImage == "server.rack")
    #expect(receipt.tone == .ok)
    #expect(receipt.action == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func clearDropsReceiptAndIgnoresLateTimer() async {
    let sleeper = ManualSleeper()
    let receipts = center(sleeper)
    receipts.show(Receipt(text: "A"))
    await waitForTimers(sleeper, count: 1)
    receipts.clear()
    #expect(receipts.current == nil)
    receipts.show(Receipt(text: "B"))
    await waitForTimers(sleeper, count: 2)
    await sleeper.wake(0)
    for _ in 0..<50 { await Task.yield() }
    #expect(receipts.current?.text == "B")
    await sleeper.wake(1)
    await settle { receipts.current == nil }
}

/// D19: deleting another site ends with a receipt that lists what the server side could not do.
@Test func siteRemovedReceiptJoinsTheNotes() {
    #expect(Receipt.siteRemoved(notes: []).text == "已删除站点")
    #expect(Receipt.siteRemoved(notes: ["令牌未能吊销，可用 API 吊销", "推送设备未能从站点移除，可在 Web 删除"]).text
            == "已删除站点 · 令牌未能吊销，可用 API 吊销；推送设备未能从站点移除，可在 Web 删除")
    #expect(Receipt.siteRemoved(notes: ["令牌未能吊销，可用 API 吊销"]).tone == .caution)
    #expect(Receipt.siteRemoved(notes: []).tone == .ok)
}

/// S0-LOW-B: a tap reaches the button of the receipt the administrator saw; one that replaced it in the same frame keeps its
/// action.
@MainActor @Test func actionRunsOnlyForTheReceiptStillShown() async {
    let sleeper = ManualSleeper()
    let receipts = center(sleeper)
    let calls = Calls()
    let first = Receipt(text: "已停止调度", undo: { calls.names.append("A") })
    let second = Receipt(text: "已删除分组", undo: { calls.names.append("B") })
    receipts.show(first)
    receipts.show(second)
    receipts.performAction(id: first.id)
    #expect(calls.names.isEmpty)
    #expect(receipts.current?.id == second.id)
    receipts.performAction(id: second.id)
    #expect(calls.names == ["B"])
    #expect(receipts.current == nil)
    await waitForTimers(sleeper, count: 2)
    await sleeper.wakeAll()
}

/// C-15 (S2-07): a page's own bottom bar lifts the receipt above it; showing or clearing receipts leaves the clearance alone.
@MainActor @Test func bottomClearanceClampsInvalidValuesAndSurvivesClear() {
    let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
    #expect(receipts.bottomClearance == 0)
    receipts.setBottomClearance(64)
    #expect(receipts.bottomClearance == 64)
    receipts.show(Receipt(text: "已停止调度 1 个账号"))
    receipts.clear()
    #expect(receipts.bottomClearance == 64)
    for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
        receipts.setBottomClearance(64)
        receipts.setBottomClearance(invalid)
        #expect(receipts.bottomClearance == 0, "\(invalid)")
    }
}

/// S2-20: a sheet drawing its own receipt takes it from the tabs' overlays under it; the newest sheet draws it and closing it
/// hands it back, so the receipt is drawn (and found by VoiceOver and UI tests) once.
@MainActor @Test func newestSheetHostDrawsTheReceiptAlone() {
    let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
    let form = UUID(), test = UUID()
    #expect(receipts.draws(host: nil))
    receipts.addSheetHost(form)
    #expect(!receipts.draws(host: nil) && receipts.draws(host: form))
    receipts.addSheetHost(test)
    receipts.addSheetHost(test)
    #expect(!receipts.draws(host: form) && receipts.draws(host: test))
    receipts.removeSheetHost(test)
    #expect(receipts.draws(host: form) && !receipts.draws(host: test))
    receipts.show(Receipt(text: "已移除 1 个不再适用的分组"))
    receipts.clear()
    #expect(receipts.draws(host: form))
    receipts.removeSheetHost(form)
    #expect(receipts.draws(host: nil) && !receipts.draws(host: form))
}
