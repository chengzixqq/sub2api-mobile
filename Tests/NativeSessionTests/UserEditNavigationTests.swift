import Testing
import Sub2Core
@testable import NativeSessionSupport

// S3-11: which pages leave the stack when the edit page saves, or the user is deleted or gone (30 §6.4, §6.5).

@Test func removingUserPages() {
    #expect(UserEditNavigation.removingUserPages([.user(id: 1), .userEdit(id: 1)], userID: 1) == [])
    #expect(UserEditNavigation.removingUserPages([.searchResults(kind: .users, query: "王"), .user(id: 3), .userEdit(id: 3, segment: .keys)], userID: 3)
            == [.searchResults(kind: .users, query: "王")])
    #expect(UserEditNavigation.removingUserPages([.userEdit(id: 3)], userID: 3) == [])
    #expect(UserEditNavigation.removingUserPages([.user(id: 2), .userEdit(id: 3)], userID: 3) == [.user(id: 2)])
    #expect(UserEditNavigation.removingUserPages([.user(id: 3), .sessions], userID: 3) == [.user(id: 3), .sessions])
}

@Test func closingEditorDropsOnlyThatPage() {
    #expect(UserEditNavigation.closingEditor([.user(id: 3), .userEdit(id: 3)], userID: 3) == [.user(id: 3)])
    #expect(UserEditNavigation.closingEditor([.user(id: 3), .userEdit(id: 3, segment: .keys)], userID: 3) == [.user(id: 3)])
    #expect(UserEditNavigation.closingEditor([.user(id: 2)], userID: 3) == [.user(id: 2)])
    #expect(UserEditNavigation.closingEditor([], userID: 3) == [])
}
