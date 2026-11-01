import Foundation

/// 40 §6.4 按对象筛选 sheet: its copy, the three groups' sizes and what each group shows. Accounts are the server's (R19,
/// name match only), groups the session's directory matched here by name, users `usage/search-users` (none for a blank
/// keyword).
public enum LogFilterPicker {
    public static let title = "按对象筛选"
    public static let searchPrompt = "账号名、邮箱或分组"
    public static let accountsTitle = "账号"
    public static let groupsTitle = "分组"
    public static let usersTitle = "用户"
    /// The capsule at the end of the chip row, after a plus.
    public static let addChipTitle = "筛选"
    public static let deletedUser = "已删除"
    public static let noMatches = "没有匹配的账号、分组或用户"
    public static let accountLimit = 6
    public static let groupLimit = 4
    public static let userLimit = 3
    public static let debounce: Duration = .milliseconds(300)

    public static func keyword(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// R19: page 1 of the account list by name, six rows; only parameters an older server knows too (`supportsListQuery` off).
    public static func accountQuery(search: String) -> AccountListQuery {
        AccountListQuery(search: keyword(search), sort: .name, descending: false, pageSize: accountLimit)
    }
    /// In the directory's order; a name containing the keyword in any case, the first four for a blank one.
    public static func groups(_ directory: [AdminGroup], matching search: String) -> [AdminGroup] {
        let text = keyword(search)
        let matched = text.isEmpty ? directory : directory.filter { $0.name.range(of: text, options: .caseInsensitive) != nil }
        return Array(matched.prefix(groupLimit))
    }
    /// None for a blank keyword (the group is hidden); otherwise the server's first three, deleted users included.
    public static func users(_ matches: [UsageUserMatch], matching search: String) -> [UsageUserMatch] {
        keyword(search).isEmpty ? [] : Array(matches.prefix(userLimit))
    }

    /// “Anthropic · 高级组、Claude Code 组”, or “Grok · 未分组”; a group the directory does not know takes the row's name or “#id”.
    public static func accountMeta(_ account: UpstreamAccount, catalog: MetaCatalog?, directory: (Int) -> String?) -> String {
        let groups = AccountRowPresentation.groupNames(account, directory: directory)
        let listed = groups.isEmpty ? AccountRowPresentation.ungrouped : groups.joined(separator: "、")
        return "\(AccountNaming.platformName(account.platform, catalog: catalog)) · \(listed)"
    }
    public static func accountTrailing(_ account: UpstreamAccount) -> String { "#\(account.id)" }
    public static func groupPlatform(_ group: AdminGroup, catalog: MetaCatalog?) -> String {
        AccountNaming.platformName(group.platform, catalog: catalog)
    }
    /// The condition's name; blank is none, so the chip reads “#id”.
    public static func objectName(_ name: String) -> String? {
        let text = keyword(name)
        return text.isEmpty ? nil : text
    }
}
