import SwiftUI
import Sub2Core

/// 60 §1: the search tab's root is the directory; typing switches to the results (60 §2), clearing or 取消 back to it.
struct SearchHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    /// 60 §2.6: lives with the tab's root, so a query typed again within 30 seconds reuses its answers; a new site gets a new one.
    @State private var search: GlobalSearchSession?

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { directory }
            else { GlobalSearchResultsView(search: search, text: query, onClear: { query = "" }) }
        }
        .navigationTitle("搜索")
        .navigationSubtitle("账号、用户、请求 ID、Key 片段")
        .navigationBarTitleDisplayMode(.large)
        // On the root inside the tab, not on the TabView: the field opens the keyboard only when tapped (60 §1.1).
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全部对象")
        .onChange(of: query) { _, text in searchTextChanged(text) }
    }

    /// Every change, clearing included, goes to the session (debounce, cancelling and the cache are its own, S6-20).
    private func searchTextChanged(_ text: String) {
        guard let session else { return }
        if search?.generation != session.generation {
            let generation = session.generation
            search = GlobalSearchSession(generation: generation, source: model.globalSearchSource(for: session),
                                         me: { [weak model] in model?.siteSession?.me },
                                         isCurrent: { [weak model] in model?.sessionGeneration == generation })
        }
        search?.update(text: text)
    }

    private var directory: some View {
        List {
            // 60 §1.5: everything shows until admin/me is known.
            ForEach(SearchDirectory.sections(me: session?.site.me)) { section in
                Section {
                    ForEach(section.items) { row($0) }
                } header: { NumberedSectionHeader(title: section.title, ordinal: section.ordinal) }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("search.home")
    }

    /// MainTabs exists only with a connected site; the Web rows open pages of it.
    private var siteURL: URL? { session?.client.server.baseURL ?? model.activeProfile?.baseURL }

    @ViewBuilder private func row(_ item: SearchDirectoryItem) -> some View {
        if let siteURL {
            switch SearchDirectory.destination(for: item, siteURL: siteURL) {
            case .push(let route):
                NavigationLink(value: route) { label(item) }.accessibilityIdentifier("search.item.\(item.rawValue)")
            case .select(let intent):
                Button { router.select(intent) } label: { linkLabel(item) }.accessibilityIdentifier("search.item.\(item.rawValue)")
            case .openURL(let url):
                Button { openURL(url) } label: { linkLabel(item) }.accessibilityIdentifier("search.item.\(item.rawValue)")
            }
        }
    }
    private func label(_ item: SearchDirectoryItem) -> some View {
        Label {
            Text(item.title).foregroundStyle(Palette.ink1)
        } icon: {
            Image(systemName: item.systemImage).foregroundStyle(Palette.ink3)
        }
    }
    /// Buttons that leave the stack still end in a chevron, drawn like the pushed rows' system chevron (60 §1.3).
    private func linkLabel(_ item: SearchDirectoryItem) -> some View {
        HStack {
            label(item)
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
