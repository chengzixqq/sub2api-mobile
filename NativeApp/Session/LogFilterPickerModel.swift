import Foundation
import Observation
import Sub2Core

/// 40 §6.2 the sheet's two reads: R19's account list (page 1, by name, six rows) and `usage/search-users`, or the UI-test
/// fixtures. Groups come from the session's GroupDirectory.
struct LogFilterPickerSource: Sendable {
    let accounts: @Sendable (_ search: String) async throws -> [UpstreamAccount]
    let users: @Sendable (_ keyword: String) async throws -> [UsageUserMatch]
}

/// A row picked in the sheet: it replaces the condition of its kind (40 §6.4); its name is the chip's text.
enum LogFilterPick: Hashable, Sendable {
    case account(LogFilterObject), group(LogFilterObject), user(LogFilterObject)

    init(account: UpstreamAccount) { self = .account(LogFilterObject(id: account.id, name: LogFilterPicker.objectName(account.name))) }
    init(group: AdminGroup) { self = .group(LogFilterObject(id: group.id, name: LogFilterPicker.objectName(group.name))) }
    /// “用户：xm.wang@example.com” (40 §6.3).
    init(user: UsageUserMatch) { self = .user(LogFilterObject(id: user.id, name: LogFilterPicker.objectName(user.email))) }

    var object: LogFilterObject {
        switch self {
        case .account(let object), .group(let object), .user(let object): object
        }
    }
    /// Only its own kind changes; the other objects, the model and its source stay.
    func applied(to conditions: LogConditions) -> LogConditions {
        var next = conditions
        switch self {
        case .account(let object): next.account = object
        case .group(let object): next.group = object
        case .user(let object): next.user = object
        }
        return next
    }
    /// The conditions already hold this object (perhaps without its name).
    func isSameObject(in conditions: LogConditions) -> Bool {
        let current = switch self {
        case .account: conditions.account
        case .group: conditions.group
        case .user: conditions.user
        }
        return current?.id == object.id
    }
}

/// 40 §6.4 按对象筛选: the search field waits 300 ms; a keyword that changed cancels the reads already sent at once. Accounts and
/// users load and fail on their own (each its 429 wait, 00 §2.7.2); groups are the directory's, matched locally. All three follow
/// the one debounced keyword. Opening reads the first accounts and the directory, no users. Replies of an older keyword or
/// session are dropped.
@MainActor @Observable
final class LogFilterPickerModel {
    /// The field as typed.
    private(set) var searchText = ""
    /// The trimmed keyword the groups show, set once the field has stayed the same for the debounce.
    private(set) var query = ""
    let accounts = LoadState<[UpstreamAccount]>()
    let users = LoadState<[UsageUserMatch]>()
    let groups: GroupDirectory?

    @ObservationIgnored private let source: LogFilterPickerSource
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    /// A read of `query` was cancelled by newer input: that keyword is read again when it comes back.
    @ObservationIgnored private var isInterrupted = false

    init(source: LogFilterPickerSource, groups: GroupDirectory?, isCurrent: @escaping @MainActor () -> Bool,
         debounce: Duration = LogFilterPicker.debounce) {
        self.source = source; self.groups = groups; self.isCurrent = isCurrent; self.debounce = debounce
    }

    /// A failed group shows its failure row instead of rows of an earlier keyword.
    var accountRows: [UpstreamAccount] {
        accounts.error == nil ? Array((accounts.value ?? []).prefix(LogFilterPicker.accountLimit)) : []
    }
    var groupRows: [AdminGroup] { LogFilterPicker.groups(groups?.groups ?? [], matching: query) }
    var userRows: [UsageUserMatch] { users.error == nil ? LogFilterPicker.users(users.value ?? [], matching: query) : [] }
    var showsUsers: Bool { !query.isEmpty }
    /// A keyword all three groups answered, with nothing.
    var hasNoMatches: Bool {
        guard showsUsers, Self.isLoaded(accounts.state), Self.isLoaded(users.state) else { return false }
        let groupsLoaded = groups.map { Self.isLoaded($0.state) } ?? true
        return groupsLoaded && accountRows.isEmpty && userRows.isEmpty && groupRows.isEmpty
    }

    /// The sheet appeared: the first accounts and the directory, once.
    func start() async {
        guard !started else { return }
        started = true
        async let directory: Void = loadGroups()
        await loadAccounts()
        await directory
    }
    /// Every change of the field. Only the wait restarts while the keyword stays as it is.
    func searchChanged(_ text: String) {
        searchText = text
        waitTask?.cancel()
        waitTask = nil
        let next = LogFilterPicker.keyword(text)
        if next != query { cancelReads() }
        guard next != query || isInterrupted else { return }
        let delay = debounce
        // Once the wait is over the task is let go, so newer input cancels its reads through `cancelReads`, never the task.
        waitTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            waitTask = nil
            await applySearch()
        }
    }
    /// The field's keyword now (the debounce's end, or the keyboard's search key).
    func applySearch() async {
        let next = LogFilterPicker.keyword(searchText)
        guard next != query || isInterrupted else { return }
        cancelReads()
        query = next
        isInterrupted = false
        async let accountsRead: Void = loadAccounts()
        await loadUsers()
        await accountsRead
    }
    func retryAccounts() async { await loadAccounts() }
    func retryUsers() async { await loadUsers() }
    func retryGroups() async { await groups?.refresh() }
    /// The sheet went: nothing more is read.
    func stop() {
        waitTask?.cancel()
        waitTask = nil
        cancelReads()
    }

    private func loadAccounts() async {
        let read = source.accounts, keyword = query
        await accounts.load(isCurrent: isCurrent) { try await read(keyword) }
    }
    /// A blank keyword asks nothing: `search-users` would answer [] (40 §6.4).
    private func loadUsers() async {
        guard showsUsers else { return users.reset() }
        let read = source.users, keyword = query
        await users.load(isCurrent: isCurrent) { try await read(keyword) }
    }
    private func loadGroups() async { await groups?.ensureLoaded() }
    private func cancelReads() {
        if accounts.isAwaitingAnswer || users.isAwaitingAnswer { isInterrupted = true }
        accounts.cancel()
        users.cancel()
    }
    private static func isLoaded<Value>(_ state: BlockState<Value>) -> Bool {
        if case .loaded = state { true } else { false }
    }
}
