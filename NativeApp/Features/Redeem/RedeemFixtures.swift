import Foundation
import Sub2Core

/// 60 §8 `-ui-testing` fixtures (X05): the design's VMO_CODES on the fixture clock, the four types in the four states, today,
/// yesterday and earlier, the batch 社群活动 · 第 3 批 (2046, 2045, 2044), a user missing from the row (2008), a subscription
/// code whose group comes from the group directory (2012) and an admin_balance row that only an old server returns (2005).
/// S6-05…S6-09 append below and never change these rows.
extension DemoData {
    enum RedeemFixture {
        /// No code at all; every count is 0.
        static let empty = "-ui-redeem-empty"
        /// 60 more balance codes (ids 1001…1060, a month and more ago), so the list has a second page.
        static let many = "-ui-redeem-many"
        /// The session's first page-1 read fails with 502.
        static let listError = "-ui-redeem-list-error"
        /// The first read of a later page fails with 502.
        static let moreError = "-ui-redeem-more-error"
        /// Every count read fails with 502.
        static let statsError = "-ui-redeem-stats-error"
        /// `-ui-redeem-open <id>`: the directory opens `.redeem(open: id)`.
        static let open = "-ui-redeem-open"
        /// The directory opens `.redeem(reconcile: true)`, as the overview's pending row does.
        static let reconcile = "-ui-redeem-reconcile"
        /// 200 admin_balance rows newer than every code (ids 3001…3200): four whole pages an old server returns and the phone drops.
        static let adminFlood = "-ui-redeem-admin-flood"
        /// A list read with a search answers after three seconds, so the field can change while it runs.
        static let slowSearch = "-ui-redeem-slow-search"
        static let slowSearchDelay: Duration = .seconds(3)
        /// The session's first page-1 read answers 429 with a two-second wait; GET :id then takes a second, like a network read.
        static let throttled = "-ui-redeem-throttled"
        static let throttledCodeDelay: Duration = .seconds(1)
        static let sameBatch = UUID(uuidString: "0E000000-0000-4000-8000-000000002046")!
    }

    static func redeemFixtures(base: Date, arguments: [String]) -> [AdminRedeemCode] {
        guard !arguments.contains(RedeemFixture.empty) else { return [] }
        let clock = RedeemFixtureClock(base: base)
        let many = arguments.contains(RedeemFixture.many) ? (1001...1060).map { olderCode($0, clock: clock) } : []
        let flood = arguments.contains(RedeemFixture.adminFlood) ? (3001...3200).map { adminAdjustment($0, clock: clock) } : []
        return flood + baseRedeemCodes(clock) + many
    }

    private static func baseRedeemCodes(_ clock: RedeemFixtureClock) -> [AdminRedeemCode] {
        let batch = RedeemFixture.sameBatch, campaign = "社群活动 · 第 3 批"
        let wang = RedeemCodeUser(id: 3, email: "xm.wang@example.com", username: "王小明")
        return [
            AdminRedeemCode(id: 2046, code: "a3f09c1e7b2d44af90c1e3b75b20d4e8", type: "balance", value: 10, status: "unused", createdAt: clock.today(minutesAgo: 29),
                            expiresAt: clock.base.addingTimeInterval(7 * 86_400), notes: campaign, batchID: batch, createdBy: 1),
            AdminRedeemCode(id: 2045, code: "5d7e21b0c4a9f3e20b88d61c7fa3e519", type: "balance", value: 10, status: "unused", createdAt: clock.today(minutesAgo: 29),
                            expiresAt: clock.base.addingTimeInterval(7 * 86_400), notes: campaign, batchID: batch, createdBy: 1),
            AdminRedeemCode(id: 2044, code: "e81c6a0f339b7d25c0f4a1e82d6b90c3", type: "balance", value: 10, status: "used", usedBy: 3,
                            usedAt: clock.today(minutesAgo: 21), createdAt: clock.today(minutesAgo: 29), expiresAt: clock.base.addingTimeInterval(7 * 86_400),
                            notes: campaign, batchID: batch, createdBy: 1, user: wang),
            AdminRedeemCode(id: 2038, code: "9b4d0e72a1c83f567e2b94d0c5f81a36", type: "subscription", value: 0, status: "unused", createdAt: clock.yesterday(hour: 18),
                            expiresAt: clock.base.addingTimeInterval(15 * 86_400), groupID: 4, validityDays: 30, createdBy: 1,
                            group: RedeemCodeGroup(id: 4, name: "企业专线")),
            AdminRedeemCode(id: 2036, code: "3c0a7f91d25e8b461f9c3a07b8e46d2f", type: "balance", value: 50, status: "used", usedBy: 10,
                            usedAt: clock.yesterday(hour: 21), createdAt: clock.yesterday(hour: 20), notes: "客服补偿 · 工单 #8812", createdBy: 1,
                            user: RedeemCodeUser(id: 10, email: "ops@studio-k.example", username: "Studio-K 团队")),
            AdminRedeemCode(id: 2031, code: "f6b2c8490e7a13d59c4f68b12a0e7d93", type: "concurrency", value: 2, status: "used", usedBy: 5,
                            usedAt: clock.daysAgo(2, hour: 16), createdAt: clock.daysAgo(2, hour: 15), createdBy: 1,
                            user: RedeemCodeUser(id: 5, email: "ting.zhou@example.com", username: "周婷")),
            AdminRedeemCode(id: 2027, code: "72e0d5a3b9c14f863d7a20e5c18b6f04", type: "invitation", value: 0, status: "unused", createdAt: clock.daysAgo(3, hour: 11),
                            notes: "内测邀请", createdBy: 1),
            AdminRedeemCode(id: 2019, code: "0d9f3b6c82a5e147f3c0b9d26e14a8c7", type: "balance", value: 20, status: "expired", createdAt: clock.daysAgo(13, hour: 10),
                            expiresAt: clock.daysAgo(6, hour: 10), createdBy: 1),
            AdminRedeemCode(id: 2015, code: "b5a81e3d6f0c92b74e3d15a90c7f28e6", type: "balance", value: 5, status: "disabled", createdAt: clock.daysAgo(14, hour: 15),
                            notes: "误发，已禁用", createdBy: 1),
            AdminRedeemCode(id: 2012, code: "4e7c0b95d3a26f18b0e95c4a7d21f6e3", type: "subscription", value: 0, status: "used", usedBy: 9,
                            usedAt: clock.daysAgo(7, hour: 13), createdAt: clock.daysAgo(8, hour: 20), groupID: 4, validityDays: 7, createdBy: 1,
                            user: RedeemCodeUser(id: 9, email: "yi.lin@example.com", username: "林一")),
            AdminRedeemCode(id: 2008, code: "c27d90e4b16a3f85d0e2c47a9b13f6d8", type: "balance", value: 15, status: "used", usedBy: 99,
                            usedAt: clock.daysAgo(19, hour: 9), createdAt: clock.daysAgo(20, hour: 9), createdBy: 1),
            AdminRedeemCode(id: 2005, code: "admin-adjust-0000000000000002005", type: "admin_balance", value: 30, status: "used", usedBy: 1,
                            usedAt: clock.daysAgo(25, hour: 9), createdAt: clock.daysAgo(25, hour: 9), notes: "管理员调整",
                            user: RedeemCodeUser(id: 1, email: "alice@example.com", username: "Alice")),
        ]
    }

    private static func olderCode(_ id: Int, clock: RedeemFixtureClock) -> AdminRedeemCode {
        let hex = String(format: "%08x", id * 7_919)
        return AdminRedeemCode(id: id, code: "d0c0" + String(repeating: hex, count: 3) + String(format: "%04x", id), type: "balance", value: 1,
                               status: "unused", createdAt: clock.daysAgo(30 + 1060 - id, hour: 10), notes: "历史批次", createdBy: 1)
    }
    private static func adminAdjustment(_ id: Int, clock: RedeemFixtureClock) -> AdminRedeemCode {
        AdminRedeemCode(id: id, code: String(format: "admin-adjust-%019d", id), type: "admin_balance", value: 1, status: "used", usedBy: 1,
                        usedAt: clock.today(minutesAgo: 5), createdAt: clock.today(minutesAgo: 5), notes: "管理员调整")
    }
}

/// Fixture times on the server's calendar, so a code made “today” stays in 今天生成 whenever the tests run.
private struct RedeemFixtureClock {
    let base: Date
    private let calendar = DemoData.serverTimeZone.calendar
    private var startOfToday: Date { calendar.startOfDay(for: base) }

    func today(minutesAgo minutes: Double) -> Date { max(base.addingTimeInterval(-minutes * 60), startOfToday.addingTimeInterval(30)) }
    func yesterday(hour: Int) -> Date { daysAgo(1, hour: hour) }
    func daysAgo(_ days: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? startOfToday
        return day.addingTimeInterval(TimeInterval(hour) * 3_600)
    }
}

/// The fixture site's codes for one session (`current(for:base:)`), so S6-05…S6-09's write fixtures change what the list
/// reads in that session only. Filters, counts and pages behave like the backend: id descending, `types` or the old `type`,
/// `status`, `batch_id`, and a search in the code or the user's email.
@MainActor
final class RedeemDemoStore {
    let base: Date
    private(set) var codes: [AdminRedeemCode]
    private let arguments: [String]
    private var firstPageReads = 0
    private var laterPageReads = 0
    private static var latest: (generation: UUID, store: RedeemDemoStore)?
    private static let failure = APIError.server(status: 502, reason: nil)
    private static let throttled = APIError.server(status: 429, envelope: nil, retryAfter: 2)
    static let notFound = APIError.server(status: 404, reason: "REDEEM_CODE_NOT_FOUND")

    init(base: Date, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.base = base; self.arguments = arguments
        codes = Self.sorted(DemoData.redeemFixtures(base: base, arguments: arguments))
    }
    /// Only the newest session's store is kept.
    static func current(for generation: UUID, base: @autoclosure () -> Date) -> RedeemDemoStore {
        if let latest, latest.generation == generation { return latest.store }
        let store = RedeemDemoStore(base: base())
        latest = (generation, store)
        return store
    }

    /// `GET admin/redeem-codes`.
    func page(_ page: Int, query: RedeemCodeListQuery) throws -> Page<AdminRedeemCode> {
        _ = try query.queryItems(page: page)
        if page == 1 { firstPageReads += 1 } else { laterPageReads += 1 }
        if arguments.contains(DemoData.RedeemFixture.listError), page == 1, firstPageReads == 1 { throw Self.failure }
        if arguments.contains(DemoData.RedeemFixture.throttled), page == 1, firstPageReads == 1 { throw Self.throttled }
        if arguments.contains(DemoData.RedeemFixture.moreError), page > 1, laterPageReads == 1 { throw Self.failure }
        let matched = matching(query, includingStatus: true)
        let size = PageSize.clamped(query.pageSize)
        return Page(items: Array(matched.dropFirst((page - 1) * size).prefix(size)), total: matched.count, page: page, pageSize: size,
                    pages: max(1, (matched.count + size - 1) / size))
    }
    /// `GET admin/redeem-codes/stats`: the same filters without status.
    func stats(query: RedeemCodeListQuery) throws -> RedeemCodeStats {
        if arguments.contains(DemoData.RedeemFixture.statsError) { throw Self.failure }
        let matched = matching(query, includingStatus: false)
        func count(_ status: String) -> Int { matched.filter { $0.status == status }.count }
        return RedeemCodeStats(total: matched.count, unused: count("unused"), used: count("used"), expired: count("expired"),
                               disabled: count("disabled"), byType: Dictionary(grouping: matched, by: \.type).mapValues(\.count))
    }
    /// `GET admin/redeem-codes/:id`: without user and group, like the server.
    func code(id: Int) throws -> AdminRedeemCode {
        guard let code = codes.first(where: { $0.id == id }) else { throw Self.notFound }
        return AdminRedeemCode(id: code.id, code: code.code, type: code.type, value: code.value, status: code.status, usedBy: code.usedBy,
                               usedAt: code.usedAt, createdAt: code.createdAt, expiresAt: code.expiresAt, groupID: code.groupID,
                               validityDays: code.validityDays, notes: code.notes, batchID: code.batchID, createdBy: code.createdBy)
    }
    /// For the write fixtures of S6-05…S6-09.
    func replace(_ codes: [AdminRedeemCode]) { self.codes = Self.sorted(codes) }

    private func matching(_ query: RedeemCodeListQuery, includingStatus: Bool) -> [AdminRedeemCode] {
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return codes.filter { code in
            if !search.isEmpty, !code.code.lowercased().contains(search), !(code.user?.email?.lowercased().contains(search) ?? false) { return false }
            if let batchID = query.batchID { return code.batchID == batchID }
            if let types = query.types, !types.map(\.rawValue).contains(code.type) { return false }
            if query.types == nil, let type = query.type, code.type != type.rawValue { return false }
            return !includingStatus || query.status.map { $0.rawValue == code.status } ?? true
        }
    }
    private static func sorted(_ codes: [AdminRedeemCode]) -> [AdminRedeemCode] { codes.sorted { $0.id > $1.id } }
}

extension RedeemCodesSource {
    static func fixture(_ store: RedeemDemoStore, arguments: [String] = ProcessInfo.processInfo.arguments) -> RedeemCodesSource {
        let searchDelay = arguments.contains(DemoData.RedeemFixture.slowSearch) ? DemoData.RedeemFixture.slowSearchDelay : nil
        let codeDelay = arguments.contains(DemoData.RedeemFixture.throttled) ? DemoData.RedeemFixture.throttledCodeDelay : nil
        return RedeemCodesSource(list: { page, query in
            if let searchDelay, !query.search.isEmpty { try await Task.sleep(for: searchDelay) }
            return try await store.page(page, query: query)
        }, stats: { try await store.stats(query: $0) }, code: { id in
            if let codeDelay { try await Task.sleep(for: codeDelay) }
            return try await store.code(id: id)
        })
    }
}

// MARK: - S6-05 writes

extension DemoData.RedeemFixture {
    /// Every status, expiry or group change answers 409 REDEEM_CODE_USED, as if the code was redeemed while the list showed it
    /// unused; notes still save.
    static let editUsedRace = "-ui-redeem-edit-used-race"
    /// Every status, expiry, group or notes change answers only after half a minute, so the card can be tried while it runs.
    static let slowWrite = "-ui-redeem-slow-write"
    static let slowWriteDelay: Duration = .seconds(30)
}

extension RedeemDemoStore {
    private static let usedRace = APIError.server(status: 409, reason: RedeemWriteFailure.usedReason)

    /// `POST admin/redeem-codes/batch-update` with the backend's refusals (60 §9.4): all ids or none.
    func update(ids: [Int], fields: RedeemBatchUpdateFields, now: Date) throws -> Int {
        guard !fields.isEmpty else { throw APIError.server(status: 400, reason: "REDEEM_CODE_BATCH_UPDATE_EMPTY") }
        if case .at(let date)? = fields.expiresAt, date <= now { throw APIError.server(status: 400, reason: "REDEEM_CODE_EXPIRES_AT_INVALID") }
        let targets = try ids.map { id in
            guard let code = codes.first(where: { $0.id == id }) else { throw Self.notFound }
            return code
        }
        if fields.touchesUsedSensitiveFields, arguments.contains(DemoData.RedeemFixture.editUsedRace) || targets.contains(where: \.isRedeemed) {
            throw Self.usedRace
        }
        let changed = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, Self.applying(fields, to: $0, now: now)) })
        replace(codes.map { changed[$0.id] ?? $0 })
        return targets.count
    }
    /// `DELETE admin/redeem-codes/:id` with `redeem_codes.delete_guard`: a redeemed code or an admin row is refused.
    func delete(id: Int) throws -> RedeemDeleteResult {
        guard let code = codes.first(where: { $0.id == id }) else { return .alreadyGone }
        guard !code.isRedeemed, !code.isAdminAdjustment else { throw Self.usedRace }
        replace(codes.filter { $0.id != id })
        return .deleted
    }

    /// The server stores an expired code as unused and maps it on the way out (dto/mappers.go).
    private static func applying(_ fields: RedeemBatchUpdateFields, to code: AdminRedeemCode, now: Date) -> AdminRedeemCode {
        let expiresAt: Date? = switch fields.expiresAt {
        case nil: code.expiresAt
        case .never?: nil
        case .at(let date)?: date
        }
        let stored = fields.status?.rawValue ?? (code.status == "expired" ? "unused" : code.status)
        let status = stored == "unused" && expiresAt.map({ $0 <= now }) == true ? "expired" : stored
        let groupID: Int? = switch fields.groupID {
        case nil: code.groupID
        case .cleared?: nil
        case .id(let id)?: id
        }
        let group = groupID.flatMap { id in DemoData.accountGroups.first { $0.id == id }.map { RedeemCodeGroup(id: id, name: $0.name) } }
        return AdminRedeemCode(id: code.id, code: code.code, type: code.type, value: code.value, status: status, usedBy: code.usedBy, usedAt: code.usedAt,
                               createdAt: code.createdAt, expiresAt: expiresAt, groupID: groupID, validityDays: code.validityDays,
                               notes: fields.notes ?? code.notes, batchID: code.batchID, createdBy: code.createdBy, user: code.user, group: group)
    }
}

extension RedeemWriteSource {
    static func fixture(_ store: RedeemDemoStore, arguments: [String] = ProcessInfo.processInfo.arguments) -> RedeemWriteSource {
        let delay = arguments.contains(DemoData.RedeemFixture.slowWrite) ? DemoData.RedeemFixture.slowWriteDelay : nil
        return RedeemWriteSource(update: { ids, fields in
            if let delay { try await Task.sleep(for: delay) }
            return try await store.update(ids: ids, fields: fields, now: Date())
        }, delete: { try await store.delete(id: $0) }, code: { try await store.code(id: $0) })
    }
}

extension RedeemRouteState {
    /// Under `-ui-testing`, `-ui-redeem-open <id>` and `-ui-redeem-reconcile` stand for the entries the tests cannot reach yet (a
    /// compensation receipt's “查看兑换码”, the overview's pending row); a route that already says where to go is kept.
    func applyingFixtureArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> RedeemRouteState {
        guard open == nil, !reconcile else { return self }
        let open = arguments.firstIndex(of: DemoData.RedeemFixture.open).flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil }
        return RedeemRouteState(open: open, filter: filter, reconcile: arguments.contains(DemoData.RedeemFixture.reconcile))
    }
}

// MARK: - S6-06 reconciliation

extension DemoData.RedeemFixture {
    /// The batch_id query finds the whole pending batch. Without one of these a check finds nothing and a retry generates it.
    static let reconcileGenerated = "-ui-redeem-reconcile-generated"
    /// It finds three quarters of the batch (15 of 20).
    static let reconcileMismatch = "-ui-redeem-reconcile-mismatch"
    /// The check's query fails with 502.
    static let reconcileFailed = "-ui-redeem-reconcile-failed"
    /// With `-ui-without-capabilities redeem_codes.stats`: the newest codes look like the batch.
    static let legacyMatch = "-ui-redeem-legacy-match"
    /// A retry's answer is lost.
    static let retryUnknown = "-ui-redeem-retry-unknown"
    /// A retry meets STORE_UNAVAILABLE: the same number waits `storeCooldown`.
    static let retryStoreUnavailable = "-ui-redeem-retry-store-unavailable"
    static let storeCooldown: TimeInterval = 10
}

extension DemoData {
    /// The codes the fixture server holds for `batch`: deterministic hex, made at `now`, ids 5000 + 100 × the record id's first
    /// byte on (0A… → 6000, 0B… → 6100).
    static func fixtureBatchCodes(for batch: PendingRedeemBatch, count: Int? = nil, now: Date) -> [AdminRedeemCode] {
        let first = 5_000 + Int(batch.id.uuid.0) * 100, spec = batch.spec
        return (0..<(count ?? batch.count)).map { index in
            let id = first + index
            return AdminRedeemCode(id: id, code: String(format: "%08lx%08lx%08lx%08lx", id, id * 7, id * 13, id * 31), type: spec.type.rawValue,
                                   value: spec.value, status: "unused", createdAt: now,
                                   expiresAt: spec.expiresInDays.map { now.addingTimeInterval(TimeInterval($0) * 86_400) }, groupID: spec.groupID,
                                   validityDays: spec.validityDays, notes: spec.notes.isEmpty ? nil : spec.notes, batchID: batch.id, createdBy: batch.actorUserID)
        }
    }
    /// What the batch_id query finds; the codes found join the session's list.
    @MainActor static func redeemReconcileOutcome(for batch: PendingRedeemBatch, store: RedeemDemoStore, now: Date,
                                                  arguments: [String]) throws -> RedeemBatchReconcileOutcome {
        if arguments.contains(RedeemFixture.reconcileFailed) { throw APIError.server(status: 502, reason: nil) }
        let all = fixtureBatchCodes(for: batch, now: now)
        if arguments.contains(RedeemFixture.reconcileGenerated) { store.insert(all); return .generated(all) }
        guard arguments.contains(RedeemFixture.reconcileMismatch) else { return .notGenerated }
        let some = Array(all.prefix(batch.count * 3 / 4))
        store.insert(some)
        return .countMismatch(some)
    }
    /// An old server's newest codes: the batch with `-ui-redeem-legacy-match`, nothing like it otherwise.
    @MainActor static func redeemFallbackOutcome(for batch: PendingRedeemBatch, store: RedeemDemoStore, now: Date,
                                                 arguments: [String]) throws -> RedeemBatchFallbackOutcome {
        if arguments.contains(RedeemFixture.reconcileFailed) { throw APIError.server(status: 502, reason: nil) }
        guard arguments.contains(RedeemFixture.legacyMatch) else { return .notFound }
        let all = fixtureBatchCodes(for: batch, now: now)
        store.insert(all)
        return .likelyGenerated(all)
    }
    /// `POST admin/redeem-codes/generate` under the record's number. An old server replays what it stored, masked and without
    /// X-Redeem-Batch-ID, so the codes are read again by id.
    @MainActor static func redeemRetryReply(for batch: PendingRedeemBatch, store: RedeemDemoStore, legacy: Bool, now: Date,
                                            arguments: [String]) throws -> WriteOutcome<[AdminRedeemCode]> {
        func failure(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
            KeyedWriteFailure(disposition: disposition, key: batch.key, actionID: nil, lastError: nil)
        }
        if arguments.contains(RedeemFixture.retryUnknown) { throw failure(.unconfirmed(.transport, retryNotBefore: nil)) }
        if arguments.contains(RedeemFixture.retryStoreUnavailable) {
            throw failure(.unconfirmed(.storeUnavailable, retryNotBefore: Date().addingTimeInterval(RedeemFixture.storeCooldown)))
        }
        let all = fixtureBatchCodes(for: batch, now: now)
        store.insert(all)
        guard legacy else { return WriteOutcome(value: all, batchID: batch.id) }
        let masked = all.map { AdminRedeemCode(id: $0.id, code: "***", type: $0.type, value: $0.value, status: $0.status, createdAt: $0.createdAt) }
        return WriteOutcome(value: masked, replayed: true)
    }
}

extension RedeemDemoStore {
    /// Codes the server made for a pending batch, once.
    func insert(_ made: [AdminRedeemCode]) {
        let known = Set(codes.map(\.id))
        replace(codes + made.filter { !known.contains($0.id) })
    }
}

// MARK: - S6-07 generation

extension DemoData.RedeemFixture {
    /// A new batch's answer is lost: the sheet turns into the pending page and the record stays.
    static let generateUnknown = "-ui-redeem-generate-unknown"
    /// The server already had the batch and replays it.
    static let generateReplayed = "-ui-redeem-generate-replayed"
    /// 409 REDEEM_CODE_EXPIRED: nothing generated, back to step 3.
    static let generateRejected = "-ui-redeem-generate-rejected"
    /// The group directory has no active subscription group.
    static let noSubscriptionGroups = "-ui-redeem-no-subscription-groups"
}

extension DemoData {
    /// The wizard's subscription groups: the directory's (the group fixtures stay their only source), or none.
    static func redeemGenerateGroups(_ groups: [AdminGroup], arguments: [String] = ProcessInfo.processInfo.arguments) -> [AdminGroup] {
        arguments.contains(RedeemFixture.noSubscriptionGroups) ? [] : groups
    }
    /// `POST admin/redeem-codes/generate` of a new batch: the codes join the session's list, as the server's would.
    @MainActor static func redeemGenerateReply(for batch: PendingRedeemBatch, store: RedeemDemoStore, now: Date,
                                               arguments: [String]) throws -> WriteOutcome<[AdminRedeemCode]> {
        if arguments.contains(RedeemFixture.generateUnknown) {
            throw KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: batch.key, actionID: nil, lastError: nil)
        }
        if arguments.contains(RedeemFixture.generateRejected) { throw APIError.server(status: 409, reason: "REDEEM_CODE_EXPIRED") }
        let all = fixtureBatchCodes(for: batch, now: now)
        store.insert(all)
        return WriteOutcome(value: all, replayed: arguments.contains(RedeemFixture.generateReplayed), batchID: batch.id)
    }
}
