import Foundation
import Sub2Core

/// X44: `usage/search-users` for the 按对象筛选 sheet under `-ui-testing` (S4-07). Its accounts are AppModel.managedAccounts'
/// AccountDemoStore and its groups the session's group directory (`-ui-account-groups-error` fails them).
extension LogFixtures {
    /// Every search-users answers 502.
    static let pickerUsersError = "-ui-logs-picker-users-error"
    /// A deleted user, only here: DemoData.allUsers has none.
    static let deletedPickerUser = UsageUserMatch(id: 27, email: "former.ops@example.com", deleted: true)
    static let pickerUsersLimit = 30

    /// As the server's SearchUsers: a blank keyword finds no one; otherwise an email or username containing it in any case,
    /// deleted users too, by email, at most 30.
    static func pickerUsers(_ keyword: String, arguments: [String]) async throws -> [UsageUserMatch] {
        if arguments.contains(pickerUsersError) { throw APIError.server(status: 502, reason: nil) }
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let matches: (String) -> Bool = { $0.range(of: text, options: .caseInsensitive) != nil }
        let live = DemoData.allUsers.filter { matches($0.email) || matches($0.username ?? "") }
            .map { UsageUserMatch(id: $0.id, email: $0.email) }
        let deleted = matches(deletedPickerUser.email) ? [deletedPickerUser] : []
        return Array((live + deleted).sorted { $0.email < $1.email }.prefix(pickerUsersLimit))
    }
}
