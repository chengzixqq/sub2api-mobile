import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

@Test func everyAccountsTabFilterMapsToAChip() {
    let chips = AccountsTabFilter.allCases.map { TabIntent.accounts(filter: $0).accountsListSelection?.chip }
    #expect(chips == [.needs, .limited, .paused])
    #expect(AccountsTabFilter.allCases.allSatisfy { $0.rawValue == $0.chip.rawValue })
}

@Test func nilFilterSelectsAllAndKeepsPlatform() {
    #expect(TabIntent.accounts(filter: nil, platform: "anthropic").accountsListSelection == AccountsListSelection(chip: .all, platform: "anthropic"))
    #expect(TabIntent.accounts().accountsListSelection == AccountsListSelection(chip: .all, platform: nil))
    #expect(TabIntent.accounts(filter: .limited, platform: "openai").accountsListSelection == AccountsListSelection(chip: .limited, platform: "openai"))
}

@Test func otherTabIntentsHaveNoAccountsSelection() {
    for intent in [TabIntent.today, .users, .monitor(segment: .alerts), .search] { #expect(intent.accountsListSelection == nil) }
}
