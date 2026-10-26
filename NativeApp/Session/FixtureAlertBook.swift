import Foundation
import Sub2Core

/// S1-06: `-ui-testing`'s alert events and silences. FixtureLiveOpsSource keeps one, so a write shows in every list, the counts
/// and home's alerts block that read after it. Writes follow the server (ops_alerts_handler.go): a status write to an unknown id
/// still succeeds (D06); an event shows the latest-ending silence of its scope (rule, platform, group); changing one cuts the
/// later silences of its scope to the new time; ending one ends its whole scope and keeps the records, so ending again succeeds;
/// an unknown silence id is 404 OPS_ALERT_SILENCE_NOT_FOUND. Silences do not run out here.
struct FixtureAlertBook: Sendable {
    private(set) var events: [AlertEvent]
    private var silences: [Int: AlertSilence]
    private var ended: Set<Int> = []
    private var nextSilenceID = 601
    private let writesFail: Bool

    /// `legacy`: a server before the `silence` key (D01), so no event carries one (S1D1-15). `writesFail`: every write answers
    /// 500 INTERNAL_ERROR.
    init(events: [AlertEvent], legacy: Bool, writesFail: Bool) {
        let active = events.compactMap { event in
            event.silence.map { AlertSilence(id: $0.id, ruleID: event.ruleID, platform: event.platform, groupID: event.groupID, until: $0.until) }
        }
        self.events = legacy ? events.map { Self.rebuilt($0.withSilence(nil), silenceSupported: false) } : events
        silences = legacy ? [:] : Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.writesFail = writesFail
    }

    /// Filtered like the server, newest first, `limit` held to 1…500. `time_range` is not applied: S1-05's #35 fired yesterday
    /// at 21:52, which a 24 hour window would drop late in the day.
    func list(status: String?, limit: Int, before: AlertEventCursor?, groupID: Int?, platform: String?) -> [AlertEvent] {
        let wanted = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = events.filter { event in
            Self.matches(event, status: wanted?.isEmpty == false ? wanted : nil, groupID: groupID, platform: platform, before: before)
        }
        let range = AlertEvent.listLimit
        return Array(LiveOpsFixtures.newestFirst(matches).prefix(min(max(limit, range.lowerBound), range.upperBound)))
    }
    func event(id: Int) throws -> AlertEvent {
        guard let event = events.first(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "OPS_ALERT_EVENT_NOT_FOUND") }
        return event
    }

    /// The resolver is kept only for manual_resolved, as on the server.
    mutating func setStatus(id: Int, status: String, at date: Date) throws {
        try requireWritable()
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let event = events[index]
        events[index] = Self.rebuilt(event, status: status, resolvedAt: date, resolvedBy: status == AlertEvent.manualResolved ? "admin" : nil)
    }
    mutating func createSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) throws -> AlertSilence {
        try requireWritable()
        let silence = AlertSilence(id: nextSilenceID, ruleID: ruleID, platform: platform, groupID: groupID, until: until)
        nextSilenceID += 1
        silences[silence.id] = silence
        reapply(silence)
        return silence
    }
    mutating func updateSilence(id: Int, until: Date) throws -> AlertSilence {
        try requireWritable()
        guard let old = silences[id] else { throw Self.silenceMissing }
        for other in silences.values where Self.sameScope(other, old) && (other.until ?? .distantPast) > until {
            silences[other.id] = Self.moved(other, to: until)
        }
        let updated = Self.moved(old, to: until)
        silences[id] = updated
        ended.remove(id)
        reapply(updated)
        return updated
    }
    mutating func deleteSilence(id: Int) throws {
        try requireWritable()
        guard let silence = silences[id] else { throw Self.silenceMissing }
        ended.formUnion(silences.values.filter { Self.sameScope($0, silence) }.map(\.id))
        reapply(silence)
    }

    private static let silenceMissing = APIError.server(status: 404, reason: "OPS_ALERT_SILENCE_NOT_FOUND")

    private func requireWritable() throws { if writesFail { throw LiveOpsFixtures.alertWriteError } }
    /// Every event of the scope shows its latest-ending silence still running, or none.
    private mutating func reapply(_ scope: AlertSilence) {
        let latest = silences.values.filter { !ended.contains($0.id) && Self.sameScope($0, scope) }
            .max { ($0.until ?? .distantPast, $0.id) < ($1.until ?? .distantPast, $1.id) }
        events = events.map { event in
            guard event.silenceSupported, event.ruleID == scope.ruleID, event.platform == scope.platform, event.groupID == scope.groupID else { return event }
            return event.withSilence(latest?.ref)
        }
    }
    private static func sameScope(_ lhs: AlertSilence, _ rhs: AlertSilence) -> Bool {
        lhs.ruleID == rhs.ruleID && lhs.platform == rhs.platform && lhs.groupID == rhs.groupID
    }
    private static func moved(_ silence: AlertSilence, to until: Date) -> AlertSilence {
        AlertSilence(id: silence.id, ruleID: silence.ruleID, platform: silence.platform, groupID: silence.groupID, until: until)
    }
    private static func matches(_ event: AlertEvent, status: String?, groupID: Int?, platform: String?, before: AlertEventCursor?) -> Bool {
        if let status, event.status.lowercased() != status { return false }
        if let groupID, event.groupID != groupID { return false }
        if let platform, event.platform?.caseInsensitiveCompare(platform) != .orderedSame { return false }
        if let before { return event.cursor.map { $0 < before } ?? false }
        return true
    }
    /// AlertEvent keeps these fields read-only; every other field, the cursor included, is the event's own.
    private static func rebuilt(_ event: AlertEvent, status: String? = nil, resolvedAt: Date? = nil, resolvedBy: String? = nil,
                                silenceSupported: Bool? = nil) -> AlertEvent {
        AlertEvent(id: event.id, ruleID: event.ruleID, severity: event.severity, status: status ?? event.status, title: event.title,
                   description: event.description, metricValue: event.metricValue, thresholdValue: event.thresholdValue, platform: event.platform,
                   groupID: event.groupID, firedAt: event.firedAt, resolvedAt: resolvedAt ?? event.resolvedAt, silence: event.silence,
                   silenceSupported: silenceSupported ?? event.silenceSupported, rule: event.rule, groupName: event.groupName,
                   resolvedByUserName: resolvedBy ?? event.resolvedByUserName, cursor: event.cursor)
    }
}
