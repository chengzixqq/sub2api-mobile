import Foundation

/// 20 §3.4 “在 Web 中编辑” (C19), the App's one link to an account in the Web console. With `web.accounts_edit_deep_link` it opens
/// the account's edit dialog: `{站点根}/admin/accounts?edit={id}&search={name}`, the name trimmed and cut to 100 UTF-8 bytes on a
/// character boundary (Web's accountDeepLink and the list's search do the same). Without it the account list opens and the
/// whole name goes to the clipboard.
public struct AccountWebLink: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case editor, accountList }
    public static let searchByteLimit = 100
    /// openURL was refused (no browser, or a profile forbids it).
    public static let openFailedReceipt = "没有打开浏览器"

    public let kind: Kind
    public let url: URL
    /// Only for the account list: the trimmed name, whole.
    public let copiedName: String?
    public let receipt: String

    /// nil for an id the Web cannot open. Without a name the editor link carries only `edit`, and the list copies nothing.
    public static func make(siteRoot: URL, accountID: Int, name: String?, supportsDeepLink: Bool) -> AccountWebLink? {
        guard accountID > 0 else { return nil }
        let root = siteRoot.absoluteString.hasSuffix("/") ? String(siteRoot.absoluteString.dropLast()) : siteRoot.absoluteString
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard supportsDeepLink else {
            guard let url = URL(string: root + "/admin/accounts") else { return nil }
            return AccountWebLink(kind: .accountList, url: url, copiedName: trimmed.isEmpty ? nil : trimmed,
                                  receipt: trimmed.isEmpty ? "已打开 Web 账号管理" : "已打开 Web 账号管理 · 已复制「\(trimmed)」，可直接搜索")
        }
        let search = queryValue(truncatedUTF8(trimmed, maxBytes: searchByteLimit))
        guard let url = URL(string: root + "/admin/accounts?edit=\(accountID)" + (search.isEmpty ? "" : "&search=" + search)) else { return nil }
        return AccountWebLink(kind: .editor, url: url, copiedName: nil,
                              receipt: trimmed.isEmpty ? "已在浏览器打开账号 #\(accountID) 的编辑页" : "已在浏览器打开「\(trimmed)」的编辑页")
    }

    /// Whole characters while their UTF-8 bytes fit: an emoji sequence or a Chinese character is never split.
    static func truncatedUTF8(_ text: String, maxBytes: Int) -> String {
        var bytes = 0
        var kept = ""
        for character in text {
            bytes += character.utf8.count
            guard bytes <= maxBytes else { break }
            kept.append(character)
        }
        return kept
    }
    /// RFC 3986 unreserved characters stay; everything else is percent-encoded as UTF-8, “+” too (vue-router reads it as a space).
    static func queryValue(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
