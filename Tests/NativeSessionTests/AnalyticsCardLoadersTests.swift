import Foundation
import Testing
@testable import NativeSessionSupport

// 40 §1.7: the reloads of one analytics page's cards (S4-13, S4D2b-02).

@MainActor private final class LoadLog {
    var started: [String] = []
    var refreshes: [Bool] = []
    var finished: [String] = []
    var reloaded = false
}

@MainActor private func record(_ id: String, in log: LoadLog, gate: SessionGate? = nil) -> AnalyticsCardLoaders.Load {
    { refresh in
        log.started.append(id)
        log.refreshes.append(refresh)
        await gate?.wait()
        log.finished.append(id)
    }
}

@MainActor @Test func reloadAllRunsEveryCardConcurrentlyAndWaits() async {
    let loaders = AnalyticsCardLoaders()
    let log = LoadLog(), gate = SessionGate()
    loaders.register("billing", load: record("billing", in: log, gate: gate))
    loaders.register("rank", load: record("rank", in: log, gate: gate))
    let reload = Task { @MainActor in
        await loaders.reloadAll(refresh: true)
        log.reloaded = true
    }
    while log.started.count < 2 { await Task.yield() }
    #expect(Set(log.started) == ["billing", "rank"])
    #expect(log.finished.isEmpty && !log.reloaded)
    await gate.open()
    await reload.value
    #expect(Set(log.finished) == ["billing", "rank"])
    #expect(log.reloaded)
    #expect(log.refreshes == [true, true])
}

@MainActor @Test func foregroundReloadPassesTheRefreshFlag() async {
    let loaders = AnalyticsCardLoaders()
    let log = LoadLog()
    loaders.register("billing", load: record("billing", in: log))
    loaders.register("perf", followsLiveTick: false, load: record("perf", in: log))
    await loaders.reloadAll(refresh: false)
    #expect(Set(log.finished) == ["billing", "perf"])
    #expect(log.refreshes == [false, false])
}

@MainActor @Test func tickRunsOnlyVisibleCardsThatFollowTheLiveTick() async {
    let loaders = AnalyticsCardLoaders()
    let log = LoadLog()
    loaders.register("billing", load: record("billing", in: log))
    loaders.register("perf", followsLiveTick: false, load: record("perf", in: log))
    loaders.register("moreCard.tile.tokens", load: record("tile", in: log))
    loaders.setVisible("moreCard.tile.tokens", false)
    await loaders.tick()
    #expect(log.finished == ["billing"])
    #expect(log.refreshes == [true])
    // Scrolled away is still loaded: pull to refresh and a range change read it again.
    log.finished = []
    await loaders.reloadAll(refresh: true)
    #expect(Set(log.finished) == ["billing", "perf", "tile"])
    loaders.setVisible("moreCard.tile.tokens", true)
    log.finished = []
    await loaders.tick()
    #expect(Set(log.finished) == ["billing", "tile"])
}

@MainActor @Test func registerReplacesAndUnregisterRemoves() async {
    let loaders = AnalyticsCardLoaders()
    let log = LoadLog()
    await loaders.reloadAll(refresh: true)
    await loaders.tick()
    #expect(log.started.isEmpty && loaders.registeredIDs.isEmpty)
    loaders.register("billing", load: record("old", in: log))
    loaders.register("rank", load: record("rank", in: log))
    loaders.register("billing", load: record("new", in: log))
    #expect(loaders.registeredIDs == ["billing", "rank"])
    await loaders.reloadAll(refresh: true)
    #expect(Set(log.finished) == ["new", "rank"])
    loaders.unregister("billing")
    #expect(loaders.registeredIDs == ["rank"])
    log.finished = []
    await loaders.reloadAll(refresh: true)
    await loaders.tick()
    #expect(log.finished == ["rank", "rank"])
    // A hidden card registered again keeps its visibility.
    loaders.setVisible("rank", false)
    loaders.register("rank", load: record("rank2", in: log))
    log.finished = []
    await loaders.tick()
    #expect(log.finished.isEmpty)
}
