import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every call and answers through closures; `call` counts from 1 per kind.
private actor EditStub {
    struct Create: Sendable { let request: AnnouncementCreateRequest; let key: UUID; let keyed: Bool }
    typealias CreateHandler = @Sendable (_ call: Int, _ onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<Announcement>
    typealias UpdateHandler = @Sendable (_ call: Int, _ request: AnnouncementUpdateRequest) async throws -> Announcement
    typealias LoadHandler = @Sendable (_ call: Int) async throws -> Announcement
    typealias RecentHandler = @Sendable (_ call: Int) async throws -> [Announcement]
    private let onCreate: CreateHandler, onUpdate: UpdateHandler, onLoad: LoadHandler, onRecent: RecentHandler
    private(set) var creates: [Create] = []
    private(set) var updates: [AnnouncementUpdateRequest] = []
    private(set) var loads = 0
    private(set) var recents: [String] = []

    init(create: @escaping CreateHandler = { _, _ in WriteOutcome(value: saved(40)) },
         update: @escaping UpdateHandler = { _, _ in saved(7) }, load: @escaping LoadHandler = { _ in saved(7) },
         recent: @escaping RecentHandler = { _ in [] }) {
        onCreate = create; onUpdate = update; onLoad = load; onRecent = recent
    }
    func create(_ request: AnnouncementCreateRequest, _ key: UUID, _ keyed: Bool, _ onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<Announcement> {
        creates.append(Create(request: request, key: key, keyed: keyed))
        return try await onCreate(creates.count, onEvent)
    }
    func update(_ request: AnnouncementUpdateRequest) async throws -> Announcement {
        updates.append(request)
        return try await onUpdate(updates.count, request)
    }
    func load() async throws -> Announcement {
        loads += 1
        return try await onLoad(loads)
    }
    func recent(_ title: String) async throws -> [Announcement] {
        recents.append(title)
        return try await onRecent(recents.count)
    }
    nonisolated var source: AnnouncementEditSource {
        AnnouncementEditSource(create: { try await self.create($0, $1, $2, $3) }, update: { _, request in try await self.update(request) },
                               load: { _ in try await self.load() }, recent: { try await self.recent($0) })
    }
}

@MainActor private final class Flag { var value = true }
@MainActor private final class Counter {
    private(set) var count = 0
    func hit() { count += 1 }
}
@MainActor private final class DeviceClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}
private actor PauseLog {
    private(set) var seen: [Duration] = []
    func add(_ pause: Duration) { seen.append(pause) }
}
@MainActor private final class PhaseProbe {
    var flow: AnnouncementEditFlow?
    private(set) var seen: [AnnouncementEditFlow.Phase] = []
    func record() { if let phase = flow?.phase { seen.append(phase) } }
}

private let start = Date(timeIntervalSince1970: 1_792_201_280)
private let lost = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
private let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
private let timedOut = APIError(kind: .transport, message: "连接超时")

private func saved(_ id: Int, title: String = "维护通知", status: AnnouncementStatus = .draft, content: String = "正文") -> Announcement {
    Announcement(id: id, title: title, content: content, status: status, createdAt: start.addingTimeInterval(5))
}
private func draft(_ change: (inout AnnouncementDraft) -> Void = { _ in }) -> AnnouncementDraft {
    var value = AnnouncementDraft(now: start, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    value.title = "维护通知"; value.content = "正文"
    change(&value)
    return value
}

@MainActor private struct Bench {
    let flow: AnnouncementEditFlow
    let receipts: ReceiptCenter
    let changed: Counter
    let current: Flag
}

@MainActor private func makeBench(_ stub: EditStub, original: Announcement? = nil, keyed: Bool = true,
                                  deviceNow: @escaping @MainActor () -> Date = { start },
                                  pause: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> Bench {
    let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
    let changed = Counter(), current = Flag()
    let flow = AnnouncementEditFlow(original: original, source: stub.source, keyedCreate: keyed, receipts: receipts,
                                    isCurrent: { current.value }, onChanged: { changed.hit() }, now: { start },
                                    deviceNow: deviceNow, pause: pause)
    return Bench(flow: flow, receipts: receipts, changed: changed, current: current)
}

@MainActor @Test func keyTimingAndKeyedOutcomes() async throws {
    let stub = EditStub(create: { call, _ in
        if call == 1 { throw lost }
        return WriteOutcome(value: saved(40), replayed: true)
    })
    let bench = makeBench(stub)
    #expect(bench.flow.role == .create && bench.flow.phase == .editing)
    #expect(await stub.creates.isEmpty)
    await bench.flow.saveTrailing(draft())
    #expect(bench.flow.phase == .createUnconfirmed(retryNotBefore: nil) && bench.flow.locksForm && bench.flow.exit == nil)
    await bench.flow.retrySameKey()
    let creates = await stub.creates
    #expect(creates.count == 2 && creates[0].key == creates[1].key && creates[0].request == creates[1].request)
    #expect(creates[0].request.status == .draft && creates[0].keyed)
    #expect(bench.flow.exit == .saved && bench.changed.count == 1 && bench.receipts.current?.text == "已存为草稿")

    let publishing = makeBench(EditStub())
    await publishing.flow.publish(draft { $0.notifyMode = .popup })
    #expect(publishing.flow.exit == .saved && publishing.receipts.current?.text == "已发布公告" && publishing.changed.count == 1)

    let conflicting = EditStub(create: { call, _ in
        if call == 1 { throw conflict }
        if call == 2 { throw APIError.server(status: 400, reason: "ANNOUNCEMENT_INVALID_TARGET") }
        return WriteOutcome(value: saved(41))
    })
    let refused = makeBench(conflicting)
    await refused.flow.saveTrailing(draft())
    #expect(refused.flow.phase == .failed("该编号已用于另一份公告内容，请重新打开新建页") && !refused.flow.locksForm)
    await refused.flow.saveTrailing(draft())
    #expect(refused.flow.phase == .failed("可见对象条件无效，请重新设置"))
    await refused.flow.saveTrailing(draft())
    let keys = await conflicting.creates.map(\.key)
    #expect(Set(keys).count == 3 && refused.flow.exit == .saved)

    let probe = PhaseProbe()
    let waiting = EditStub(create: { _, onEvent in
        await onEvent?(.waitingForServer(elapsedSeconds: 3))
        await probe.record()
        return WriteOutcome(value: saved(42))
    })
    let watched = makeBench(waiting)
    probe.flow = watched.flow
    await watched.flow.saveTrailing(draft())
    #expect(probe.seen == [.saving(.waitingForServer(elapsedSeconds: 3))])
}

/// STORE_UNAVAILABLE's cooldown comes from the device clock (RequestClock), so it is counted on that clock, not on the
/// server-corrected `now`, and never for longer than the cooldown: a skewed or reset device clock neither skips nor stretches it.
@MainActor @Test func storeUnavailableCooldownCountsOnTheDeviceClock() async throws {
    // Device clock (seconds from `start`, the server's now) when the reply came and at 用同一编号重试; the wait expected.
    let cases: [(failedAt: TimeInterval, retryAt: TimeInterval, wait: Int64?)] = [
        (300, 300, 10),
        (-60, -60, 10),
        (0, -3_600, 10),
        (0, 11, nil)
    ]
    for item in cases {
        let device = DeviceClock(start.addingTimeInterval(item.failedAt)), pauses = PauseLog()
        let notBefore = device.now.addingTimeInterval(IdempotencyPolicy.storeUnavailableCooldown)
        let unavailable = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: notBefore), key: "k",
                                            actionID: nil, lastError: nil)
        let stub = EditStub(create: { call, _ in
            if call == 1 { throw unavailable }
            return WriteOutcome(value: saved(40))
        })
        let bench = makeBench(stub, deviceNow: { device.now }, pause: { await pauses.add($0) })
        await bench.flow.saveTrailing(draft())
        #expect(bench.flow.phase == .createUnconfirmed(retryNotBefore: notBefore))
        device.now = start.addingTimeInterval(item.retryAt)
        await bench.flow.retrySameKey()
        let waits = await pauses.seen.map(\.components.seconds)
        #expect(waits == (item.wait.map { [$0] } ?? []), "device \(item.failedAt) → \(item.retryAt)")
        let keys = await stub.creates.map(\.key)
        #expect(keys.count == 2 && keys[0] == keys[1] && bench.flow.exit == .saved)
    }
}

@MainActor @Test func unkeyedCreateNeverResendsAndChecksTitle() async throws {
    let stub = EditStub(create: { call, _ in
        if call == 1 { throw lost }
        return WriteOutcome(value: saved(43))
    }, recent: { call in
        switch call {
        case 1: return []
        case 2: throw timedOut
        default: return [saved(40, title: "维护通知（二）"), saved(41)]
        }
    })
    let bench = makeBench(stub, keyed: false)
    await bench.flow.saveTrailing(draft { $0.title = " 维护通知 " })
    #expect(bench.flow.phase == .notFoundYet && bench.flow.locksForm)
    let firstCreates = await stub.creates, recents = await stub.recents
    #expect(firstCreates.count == 1 && firstCreates.first?.keyed == false && recents == ["维护通知"])
    await bench.flow.recheck()
    #expect(bench.flow.phase == .notFoundYet)
    await bench.flow.recheck()
    #expect(bench.flow.phase == .maybeCreated(AnnouncementRecentMatch(id: 41, title: "维护通知", createdAt: start.addingTimeInterval(5), status: .draft)))
    #expect(await stub.creates.count == 1)
    bench.flow.viewExisting()
    #expect(bench.flow.exit == .open(41) && bench.changed.count == 1)

    let again = EditStub(create: { call, _ in
        if call == 1 { throw lost }
        return WriteOutcome(value: saved(44))
    })
    let retried = makeBench(again, keyed: false)
    await retried.flow.saveTrailing(draft())
    #expect(retried.flow.phase == .notFoundYet)
    await retried.flow.createAnyway()
    let creates = await again.creates
    #expect(creates.count == 2 && creates[0].key != creates[1].key && creates[0].request == creates[1].request)
    #expect(retried.flow.exit == .saved && retried.receipts.current?.text == "已存为草稿")
}

@MainActor @Test func updateReadBackRejectAndGuards() async throws {
    let original = Announcement(id: 7, title: "维护通知", content: "正文", status: .active, notifyMode: .silent)
    let stub = EditStub(update: { call, _ in
        if call == 1 { throw timedOut }
        return saved(7, status: .active, content: "新正文")
    }, load: { call in
        call == 1 ? saved(7, status: .active) : saved(7, status: .active, content: "新正文")
    })
    let bench = makeBench(stub, original: original)
    let edited = AnnouncementDraft(announcement: original, now: start, timeZone: .current)
    var changed = edited
    changed.content = "新正文"
    await bench.flow.saveTrailing(changed)
    let sent = await stub.updates
    #expect(bench.flow.phase == .updateUnconfirmed && sent == [AnnouncementUpdateRequest(content: "新正文")])
    await bench.flow.recheck()
    let sentAfterCheck = await stub.updates
    #expect(bench.flow.exit == .saved && bench.receipts.current?.text == "已保存 · 用户看到的是新内容" && sentAfterCheck.count == 1)

    let unchanged = makeBench(EditStub(), original: original)
    await unchanged.flow.saveTrailing(edited)
    #expect(unchanged.flow.exit == .saved && unchanged.changed.count == 0)

    let gone = makeBench(EditStub(update: { _, _ in throw APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND") }), original: original)
    await gone.flow.saveTrailing(changed)
    #expect(gone.flow.phase == .gone && gone.changed.count == 1 && gone.flow.exit == nil)

    let refusing = EditStub(update: { _, _ in throw APIError.server(status: 400, reason: "ANNOUNCEMENT_TIME_RANGE_INVALID") })
    let refused = makeBench(refusing, original: original)
    await refused.flow.saveTrailing(changed)
    #expect(refused.flow.phase == .failed("结束时间要晚于开始时间") && !refused.flow.locksForm && refused.flow.exit == nil)

    let slow = EditStub(update: { _, _ in
        try await Task.sleep(for: .milliseconds(100))
        return saved(7, status: .active, content: "新正文")
    })
    let busy = makeBench(slow, original: original), snapshot = changed
    let first = Task { await busy.flow.saveTrailing(snapshot) }
    let second = Task { await busy.flow.publish(snapshot) }
    _ = await (first.value, second.value)
    #expect(await slow.updates.count == 1)

    let flag = Flag()
    let leaving = EditStub(update: { _, _ in
        await MainActor.run { flag.value = false }
        return saved(7, status: .active, content: "新正文")
    })
    let left = makeBench(leaving, original: original)
    let flow = AnnouncementEditFlow(original: original, source: leaving.source, keyedCreate: true, receipts: left.receipts,
                                    isCurrent: { flag.value }, onChanged: { left.changed.hit() }, now: { start })
    await flow.saveTrailing(changed)
    #expect(flow.exit == nil && left.changed.count == 0 && left.receipts.current == nil)
}
