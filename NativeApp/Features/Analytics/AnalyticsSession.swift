import SwiftUI
import Sub2Core

/// 40 §0.1 / §1.8: the analytics pages call the shared state their session; it lives in NativeApp/Session so it can be tested.
typealias AnalyticsSession = AnalyticsSessionState

extension EnvironmentValues {
    /// Set by AnalyticsSessionScope for the page and its cards.
    @Entry var analyticsSession: AnalyticsSession? = nil
}

extension AnalyticsSessionState {
    /// The connected site's session, with the App's memory and group directory.
    convenience init(model: AppModel, context: SessionContext, entry: AnalyticsEntryRange) {
        let client = context.client, generation = context.generation
        self.init(serverID: context.serverID, generation: generation, client: client, timeZone: context.site.serverTimeZone,
                  supportsModelSource: context.has(.usageModelSource), supportsOpsModelFilter: context.has(.opsDashboardModelFilter),
                  memory: model.analyticsMemory, entry: entry, groups: model.groupDirectory, isUITesting: model.isUITesting,
                  clock: { client.serverClock.now() }, isSessionCurrent: { [weak model] in model?.sessionGeneration == generation })
    }
}

/// The analytics stack's one session (S4D1-01): the first page to appear registers it for its tab, the pages it pushes find the
/// same one, and AppRouter drops it once the stack leaves analytics. `entry` is the route's range, used only before the site
/// remembers one (a page pushed on its own passes `.last7`, the search directory's default).
struct AnalyticsSessionScope<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var context
    private let entry: AnalyticsEntryRange
    private let content: (AnalyticsSession) -> Content
    @State private var tab: MainTab?
    @State private var session: AnalyticsSession?

    init(entry: AnalyticsEntryRange, @ViewBuilder content: @escaping (AnalyticsSession) -> Content) {
        self.entry = entry; self.content = content
    }

    var body: some View {
        Group {
            if let session {
                content(session).environment(\.analyticsSession, session)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: register)
        .onChange(of: model.sessionGeneration) { _, _ in register() }
        .task(id: session.map { ObjectIdentifier($0) }) { await session?.prepare() }
    }

    private func register() {
        guard let context, let pageStates = model.pageStates else { return }
        if let session, !session.isStale(currentGeneration: context.generation) { return }
        let tab = self.tab ?? router.selectedTab
        self.tab = tab
        let model = model, entry = entry
        session = pageStates.state(PageStateKey.analyticsSession, tab: tab, prunedBy: router) {
            AnalyticsSession(model: model, context: context, entry: entry)
        }
    }
}
