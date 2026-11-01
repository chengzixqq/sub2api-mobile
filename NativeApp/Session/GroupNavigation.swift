import Foundation

/// 50 §0.5: a group deleted from its detail leaves the current tab's stack before the DELETE goes out; 查看 opens a copy.
enum GroupNavigation {
    /// Up to the last `.group(id: groupID)`, which goes with the pages above it; unchanged when it is not there.
    static func leavingGroup(_ path: [AppRoute], groupID: Int) -> [AppRoute] {
        guard let index = path.lastIndex(where: { $0 == .group(id: groupID) }) else { return path }
        return Array(path[..<index])
    }
}

extension AppRouter {
    /// The copy's 查看: not pushed again when the current tab already shows it.
    func showGroup(id: Int) {
        guard path(for: selectedTab).last != .group(id: id) else { return }
        push(.group(id: id))
    }
    /// True when the current tab's stack had the group's detail and left it; the caller dismisses otherwise.
    @discardableResult func leaveGroup(id: Int) -> Bool {
        let path = path(for: selectedTab)
        let next = GroupNavigation.leavingGroup(path, groupID: id)
        guard next.count < path.count else { return false }
        setPath(next, for: selectedTab)
        return true
    }
}
