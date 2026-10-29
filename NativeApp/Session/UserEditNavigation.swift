import Foundation

/// 30 §6.4–§6.5 (S3-11): which pages leave the current tab's stack when the edit page saves, or its user is deleted or gone.
enum UserEditNavigation {
    /// Delete or 404: the user's own pages at the end of the stack (its editor and its detail) go; the page that led there
    /// (the list, search results, a log) is where the administrator lands.
    static func removingUserPages(_ path: [AppRoute], userID: Int) -> [AppRoute] {
        var next = path
        while let last = next.last, isPage(last, of: userID) { next.removeLast() }
        return next
    }
    /// A save returns to the page below the editor (30 §6.4 step 6).
    static func closingEditor(_ path: [AppRoute], userID: Int) -> [AppRoute] {
        guard let index = path.lastIndex(where: { if case .userEdit(let id, _) = $0 { id == userID } else { false } }) else { return path }
        return Array(path[..<index])
    }

    private static func isPage(_ route: AppRoute, of userID: Int) -> Bool {
        switch route {
        case .user(let id), .userEdit(let id, _): id == userID
        default: false
        }
    }
}
