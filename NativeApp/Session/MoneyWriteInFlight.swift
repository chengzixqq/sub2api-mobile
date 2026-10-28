import Foundation

/// Money records going out right now (60 §19.4 step 9, S6D1-15): the foreground check leaves them alone, and one record never
/// goes out twice at once. Keyed by record id, so it outlives a session; a leftover id only skips one check.
@MainActor
final class MoneyWriteInFlight {
    struct Busy: LocalizedError, Equatable {
        var errorDescription: String? { "这笔正在发送，请稍候" }
    }

    private(set) var ids: Set<UUID> = []

    init() {}

    func contains(_ id: UUID) -> Bool { ids.contains(id) }
    /// Marks `id` for the whole of `body`, however it ends; refuses at once while the same id is already going out.
    func sending<T>(_ id: UUID, _ body: @MainActor () async throws -> T) async throws -> T {
        guard !ids.contains(id) else { throw Busy() }
        ids.insert(id)
        defer { ids.remove(id) }
        return try await body()
    }
}
