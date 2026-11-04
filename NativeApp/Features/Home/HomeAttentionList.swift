import SwiftUI
import Sub2Core

/// 10 §1.3.3 待处理 (壹, “N 项”): alerts, error and overloaded accounts, the limited row, short groups, then the money records of
/// this site's address (X34), in HomePresentation.attentionItems' order; adjacent capsules join into one rail (00 §8.1). A row
/// only opens its page through HomeDestinationAction: money records are read here, never checked or resolved (R02). An empty
/// queue shows nothing (the calm layout is S1-11's); before the first read one 正在加载… row. Identifiers home.attention (the title,
/// its value the meta), home.attention.<item id>, home.attention.test.<account id> and home.attention.loading.
struct HomeAttentionList: View {
    let store: LiveOpsStore
    /// AppModel.pendingMoneyWrites(sameAddressAs:) of the connected site.
    let pending: [any PendingMoneyWrite]
    let currentServerID: UUID?
    /// The account whose 「测试」 sheet this list opened; HomeView reads home again once it closes.
    @Binding var awaitingAccountTest: Int?
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session

    var body: some View {
        let items = HomePresentation.attentionItems(alerts: store.home.alerts, availability: store.home.availability,
                                                    structuredErrors: store.structuredErrors, pending: pending, currentServerID: currentServerID,
                                                    now: store.serverNow(), timeZone: session?.site.serverTimeZone.timeZone ?? .current)
        if !items.isEmpty {
            let positions = RailPosition.positions(of: items) { $0.tone.drawsRail }
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in row(item, position: positions[index]) }
            } header: {
                NumberedSectionHeader(title: Self.title, ordinal: Self.ordinal, meta: "\(items.count) 项", id: "home.attention")
            }
        } else if store.home.availability.display.homePhase == .placeholder {
            Section {
                Text("正在加载…").font(.subheadline).foregroundStyle(Palette.ink3).accessibilityIdentifier("home.attention.loading")
            } header: {
                NumberedSectionHeader(title: Self.title, ordinal: Self.ordinal, id: "home.attention")
            }
        }
    }

    private static let title = "待处理"
    private static let ordinal = "壹"

    @ViewBuilder private func row(_ item: AttentionItem, position: RailPosition?) -> some View {
        switch item.kind {
        case .alert:
            if let event = alertEvent(item.destination) {
                AlertRow(event: event, context: .home, railPosition: position, onOpen: { open(item.destination) })
                    .accessibilityIdentifier(Self.identifier(item))
            } else {
                attentionRow(item, position: position)
            }
        case .errorAccount:
            if case .accountTest(let accountID)? = item.action {
                ErrorAccountAttentionRow(item: item, accountID: accountID, railPosition: position, onOpen: { open(item.destination) },
                                         onTest: { test(accountID) })
            } else {
                attentionRow(item, position: position)
            }
        case .limitedAccounts:
            LimitedAttentionRow(item: item, railPosition: position, now: store.serverNow, identifier: Self.identifier(item),
                                onOpen: { open(item.destination) }, onCountdownElapsed: countdownElapsed)
        case .alertsFailed, .availabilityFailed:
            failureRow(item, position: position)
        default:
            attentionRow(item, position: position)
        }
    }

    private func attentionRow(_ item: AttentionItem, position: RailPosition?) -> some View {
        AttentionRow(item: item, railPosition: position, now: store.serverNow, onOpen: { open(item.destination) },
                     onCountdownElapsed: countdownElapsed)
            .accessibilityIdentifier(Self.identifier(item))
    }

    /// 10 §1.5: neutral, with the block's 429 wait and details; 重试 reads home past the cache, the poll retries by itself (S1D1-20).
    private func failureRow(_ item: AttentionItem, position: RailPosition?) -> some View {
        let key: HomeSectionKey = item.kind == .alertsFailed ? .alerts : .availability
        let words = item.kind == .alertsFailed ? HomePresentation.alertsFailedText : HomePresentation.availabilityFailedText
        let id = Self.identifier(item)
        return BlockFailureRow(title: words, error: store.homeLastError(for: key), refresh: store.homeRefresh(for: key), id: id,
                               resendsAfterWait: false) { open(item.destination) }
            .padding(.leading, StatusCapsuleMetrics.contentLeadingInset)
            .homeFailureContainer(id)
            .railRow(tone: item.tone, position: position)
    }

    private static func identifier(_ item: AttentionItem) -> String { "home.attention." + item.id }

    private func alertEvent(_ destination: HomeDestination) -> AlertEvent? {
        guard case .alert(let id) = destination else { return nil }
        return store.home.alerts.value?.top.first { $0.id == id }
    }

    private func open(_ destination: HomeDestination) {
        router.open(HomeDestinationAction(destination)) { Task { await store.refreshHome(noCache: true) } }
    }

    /// X18: only the sheet; what it shows is S2-14's.
    private func test(_ accountID: Int) {
        awaitingAccountTest = accountID
        open(.accountTest(id: accountID))
    }

    private func countdownElapsed() { Task { await store.countdownElapsed() } }
}

extension View {
    /// 10 §1.4: once the 「测试」 sheet 待处理 opened goes away, however it closed and whatever the result, home is read again past
    /// the server cache (a test that goes on in the background reads it again when it ends, S2-23).
    func refreshesHomeAfterAccountTest(_ awaiting: Binding<Int?>, store: LiveOpsStore) -> some View {
        modifier(AccountTestCloseRefresh(awaiting: awaiting, store: store))
    }
}

private struct AccountTestCloseRefresh: ViewModifier {
    @Binding var awaiting: Int?
    let store: LiveOpsStore
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.onChange(of: router.presentedSheet) { old, new in
            guard HomeDestinationAction.accountTestClosed(from: old, to: new, awaiting: awaiting) else { return }
            awaiting = nil
            Task { await store.refreshHome(noCache: true) }
        }
    }
}
