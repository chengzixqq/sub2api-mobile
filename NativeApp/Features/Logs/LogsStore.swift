import Foundation
import Sub2Core

/// 40 §6: the page's state lives in NativeApp/Session so it can be tested (S4D2a-01); S4-08b finds a tab's lists with
/// `instances(of: LogsStore.self, tab:in:)`.
typealias LogsStore = LogsStoreState

extension LogsStoreState {
    /// The connected site's list: its zone, `usage.model_source`, `logs.since_id` and clock, the session it belongs to, and the
    /// ops switch as LiveOpsStore has it, admin/me's until then (S4D2a-17). Under `-ui-testing` LogFixtures may tune N and the
    /// poll interval (S4-06).
    convenience init(model: AppModel, context: SessionContext, route: LogsRoute) {
        let client = context.client, generation = context.generation, site = context.site
        let settingOff = site.me.features.opsMonitoringEnabled == false
        let tuning = model.isUITesting ? LogFixtures.RefreshTuning(arguments: ProcessInfo.processInfo.arguments) : nil
        self.init(route: route, generation: generation, source: model.logsSource(for: context), timeZone: site.serverTimeZone,
                  legacyServer: model.logsLegacyServer(for: context), supportsModelSource: context.has(.usageModelSource),
                  isCurrent: { [weak model] in model?.sessionGeneration == generation }, now: { client.serverClock.now() },
                  opsDisabled: { [weak model] in model?.liveOps?.opsDisabled ?? settingOff },
                  reportOps: { [weak model] error in await model?.liveOps?.recordOpsResponse(error) },
                  countSource: model.logsCountSource(for: context), supportsSinceID: context.has(.logsSinceID),
                  policy: tuning?.policy ?? LogListPolicy(), pollInterval: tuning?.interval ?? LogsStoreState.standardPollInterval)
    }
}

extension AppModel {
    /// The site's lists, or under `-ui-testing` LogFixtures with their cursor reads (S4-06).
    func logsSource(for session: SessionContext) -> LogsSource {
        guard isUITesting else { return .live(session.client, site: session.site) }
        let arguments = ProcessInfo.processInfo.arguments, clock = session.client.serverClock
        let lists = LogFixtures.source(arguments: arguments, base: clock.now(), timeZone: session.site.serverTimeZone)
        return LogFixtures.refreshSource(wrapping: lists, arguments: arguments, now: { clock.now() })
    }
    /// `usage/stats` and the error lists' totals, or under `-ui-testing` LogFixtures' counts (S4-05b).
    func logsCountSource(for session: SessionContext) -> LogCountSource {
        guard isUITesting else { return .client(session.client) }
        return LogFixtures.countSource(arguments: ProcessInfo.processInfo.arguments, base: session.client.serverClock.now(),
                                       timeZone: session.site.serverTimeZone)
    }
    /// admin/me's, or under `-ui-testing` also `-ui-logs-legacy-server`.
    func logsLegacyServer(for session: SessionContext) -> Bool {
        guard isUITesting else { return session.site.me.isLegacyServer }
        return LogFixtures.isLegacyServer(session.site, arguments: ProcessInfo.processInfo.arguments)
    }
}
