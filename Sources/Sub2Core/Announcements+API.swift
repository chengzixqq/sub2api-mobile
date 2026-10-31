import Foundation

/// 60 §15–§18 endpoints. None of the lists has an ETag (60 §0.2), so nothing here goes through ConditionalCache.
extension APIClient {
    public func announcements(page: Int, query: AnnouncementListQuery) async throws -> Page<Announcement> {
        try await request("admin/announcements", query: query.queryItems(page: page))
    }
    /// The segment counts: four `page_size=1` reads of the same list in parallel (60 §15.2, no statistics endpoint). One that
    /// fails leaves its count nil; all four failing throw the first error; a cancelled caller always gets CancellationError.
    public func announcementCounts() async throws -> AnnouncementCounts {
        async let all = announcementTotal(nil)
        async let active = announcementTotal(.active)
        async let draft = announcementTotal(.draft)
        async let archived = announcementTotal(.archived)
        let results = await [all, active, draft, archived]
        try Task.checkCancellation()
        let failures = results.compactMap { result -> (any Error)? in if case .failure(let error) = result { error } else { nil } }
        if failures.contains(where: { $0 is CancellationError }) { throw CancellationError() }
        if failures.count == results.count, let first = failures.first { throw first }
        let totals = results.map { try? $0.get() }
        return AnnouncementCounts(all: totals[0], active: totals[1], draft: totals[2], archived: totals[3])
    }
    /// `include_read_stats=true` only with `announcements.read_stats` (U44).
    public func announcement(id: Int, includeReadStats: Bool) async throws -> Announcement {
        let stats = includeReadStats ? [URLQueryItem(name: "include_read_stats", value: "true")] : []
        return try await request("admin/announcements/\(validID(id))", query: stats)
    }
    /// With `announcements.idempotent_create` the keyed executor retries with the same key (R04). Without it the key still goes
    /// out (an old server ignores it, 00 §2.5.1) but the request is sent once: an unknown result is thrown as
    /// KeyedWriteFailure.unconfirmed so the sheet can look for it by title (60 §17.4, H07).
    public func createAnnouncement(_ announcement: AnnouncementCreateRequest, idempotencyKey: UUID, supportsIdempotentCreate: Bool,
                                   onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<Announcement> {
        let body = try announcement.requestBody()
        guard supportsIdempotentCreate else { return try await createAnnouncementOnce(body: body, key: idempotencyKey) }
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/announcements", method: "POST", body: body, key: idempotencyKey),
                                           onEvent: onEvent)
    }
    /// Absolute values, so no key, sent once and never retried on its own (00 §2.4, 60 §16.4).
    public func updateAnnouncement(id: Int, _ update: AnnouncementUpdateRequest) async throws -> Announcement {
        let id = try validID(id)
        return try await request("admin/announcements/\(id)", method: "PUT", body: update.requestBody())
    }
    /// The backend deletes a missing id without complaint; a 404 ANNOUNCEMENT_NOT_FOUND still counts as deleted (60 §16.4).
    @discardableResult
    public func deleteAnnouncement(id: Int) async throws -> AnnouncementDeleteResult {
        let id = try validID(id)
        do {
            let _: EmptyReply = try await request("admin/announcements/\(id)", method: "DELETE")
            return .deleted
        } catch let error as APIError where error.statusCode == 404 && error.reason == "ANNOUNCEMENT_NOT_FOUND" {
            return .alreadyGone
        }
    }
    public func announcementReadStatus(id: Int, page: Int, query: AnnouncementReadStatusQuery) async throws -> Page<AnnouncementReadStatusRow> {
        let id = try validID(id)
        return try await request("admin/announcements/\(id)/read-status", query: query.queryItems(page: page))
    }
    /// Only with `announcements.read_stats`; the detail asks for it unless the announcement is a draft.
    public func announcementReadSummary(id: Int) async throws -> AnnouncementReadSummary {
        try await request("admin/announcements/\(validID(id))/read-summary")
    }
    /// The H07 fallback (60 §17.4): the five newest whose title or content contains `title`. Whether one of them is the earlier
    /// create (same title, a few minutes old) is the sheet's call.
    public func recentAnnouncements(title: String) async throws -> [Announcement] {
        let query = AnnouncementListQuery(search: title, pageSize: 5)
        let page: Page<Announcement> = try await request("admin/announcements", query: query.queryItems(page: 1))
        return page.items
    }

    private func announcementTotal(_ status: AnnouncementStatus?) async -> Result<Int?, any Error> {
        do {
            let query = AnnouncementListQuery(status: status, pageSize: 1)
            let page: Page<Announcement> = try await request("admin/announcements", query: query.queryItems(page: 1))
            return .success(page.total)
        } catch { return .failure(error) }
    }
    /// One attempt through `sendAttempt` (a TOKEN_EXPIRED refresh resends the same bytes and key), judged like a keyed write;
    /// whatever the keyed flow would retry is left unconfirmed instead.
    private func createAnnouncementOnce(body: Data, key: UUID) async throws -> WriteOutcome<Announcement> {
        let snapshot = currentGeneration(), keyText = key.uuidString.lowercased()
        let spec = OutgoingRequest(path: "admin/announcements", method: "POST", body: body, requestClass: .keyedWrite(key: key))
        let attempt: KeyedAttempt
        do { attempt = .reply(try await sendAttempt(spec, context: .business, generation: snapshot)) }
        catch let error as APIError { throw surfaced(error, context: .business, generation: snapshot) }
        catch is CancellationError { throw CancellationError() }
        catch let error where RequestPolicy.isRetryableNetworkError(error) { attempt = .lost(APIError.transport(error)) }
        catch { throw surfaced(APIError.transport(error), context: .business, generation: snapshot) }
        var flow = KeyedWriteFlow()
        let disposition: KeyedWriteFailure.Disposition
        switch flow.next(after: attempt, now: requestClock.now()) {
        case .succeeded(let response):
            do { return WriteOutcome(value: try Self.decode(response), headers: response.headers) }
            catch {
                throw KeyedWriteFailure(disposition: .unconfirmed(.unreadableResponse, retryNotBefore: nil), key: keyText, actionID: nil,
                                        lastError: error as? APIError ?? .invalidResponse)
            }
        case .rejected(let response):
            throw surfaced(await refusedWrite(failure(response), generation: snapshot), context: .business, generation: snapshot)
        case .unresolved(let unresolved): disposition = unresolved
        case .retry(_, .waitingForServer): disposition = .unconfirmed(.stillProcessing, retryNotBefore: nil)
        case .retry: disposition = .unconfirmed(.transport, retryNotBefore: nil)
        }
        throw KeyedWriteFailure(disposition: disposition, key: keyText, actionID: nil, lastError: createAttemptError(attempt, generation: snapshot))
    }
    /// A reply's error leaves through `surfaced`, so a 401 inside a KeyedWriteFailure still ends the session.
    private func createAttemptError(_ attempt: KeyedAttempt, generation snapshot: UUID) -> APIError {
        switch attempt {
        case .reply(let response): surfaced(failure(response), context: .business, generation: snapshot)
        case .lost(let error): error
        }
    }
}
