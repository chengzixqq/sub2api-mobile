import SwiftUI
import Sub2Core

/// What every row of one search list shares.
struct SearchRowContext {
    /// The searched text: user rows add “· Key 片段匹配” when only a key matched (60 §2.3).
    let query: GlobalSearchQuery
    let catalog: MetaCatalog
    /// C-10 names for the lite account rows, which carry group ids only.
    let groupNames: [Int: String]
    /// The site clock, as the account and proxy pages use it.
    let now: Date
    let timeZone: ServerTimeZone
    /// `search` on the results, `search.list` on a “查看全部” page.
    let idPrefix: String

    /// 00 §8.1 within one section: accounts and proxies by their tone, request rows by their capsule; users and groups draw none.
    func railPositions(_ hits: [SearchHit]) -> [RailPosition?] {
        RailPosition.positions(of: hits) { hit in
            switch hit {
            case .account(let row): AccountDisplayState(row, now: now).tone.drawsRail
            case .proxy(let row): ProxyPresentation.row(row, now: now, timeZone: timeZone).tone?.drawsRail == true
            case .usage, .error: logRow(hit)?.drawsRail == true
            case .user, .group: false
            }
        }
    }
    func logRow(_ hit: SearchHit) -> LogRowPresentation? {
        switch hit {
        case .usage(let record): LogRowPresentation(record, timeZone: timeZone)
        case .error(let record): LogRowPresentation(record, kind: .request, timeZone: timeZone)
        default: nil
        }
    }
}

/// 60 §2.3: a search row drawn by its own chapter's row (C-8), opened on the search tab's own stack (60 §2.1). The account row and
/// the request rows go through the router like their lists (the account row draws its own chevron); the others are links.
struct SearchHitLink: View {
    let hit: SearchHit
    let context: SearchRowContext
    let railPosition: RailPosition?
    @Environment(AppRouter.self) private var router

    private static let linkInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)

    var body: some View {
        switch hit {
        case .account(let account):
            Button { router.push(hit.route) } label: {
                AccountRow(account: account, today: .hidden, railPosition: railPosition, groupName: { context.groupNames[$0] }, catalog: context.catalog)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .listRowInsets(EdgeInsets())
        case .user(let user):
            let row = UserRow(user: user, today: .hidden, mark: nil, railPosition: nil, showsDisabledBadge: user.status == "disabled",
                              trailingNote: context.query.matchesOnlyByKey(user) ? GlobalSearchCopy.keyFragmentNote : nil)
            link(label: row.spokenLabel) { row }
        case .group(let group):
            let row = GroupRow(group: group, style: .compact, catalog: context.catalog)
            link(label: row.spokenLabel) { row }
        case .proxy(let proxy):
            let row = ProxyRow(proxy: proxy, now: context.now, timeZone: context.timeZone, railPosition: railPosition)
            link(label: row.spokenLabel) { row }
        case .usage, .error:
            if let presentation = context.logRow(hit) { logButton(presentation) }
        }
    }

    /// `search.user.3`, `search.list.usage.1040`.
    private var identifier: String {
        let kind = switch hit {
        case .account: "account"
        case .user: "user"
        case .group: "group"
        case .proxy: "proxy"
        case .usage: "usage"
        case .error: "error"
        }
        return "\(context.idPrefix).\(kind).\(hit.objectID)"
    }

    private func link<Row: View>(label: String, @ViewBuilder row: () -> Row) -> some View {
        NavigationLink(value: hit.route, label: row)
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier(identifier)
            .listRowInsets(Self.linkInsets)
    }
    /// As the log page's rows (40 §6.3): the row, then the chevron.
    private func logButton(_ presentation: LogRowPresentation) -> some View {
        let content = LogRow(presentation, railPosition: railPosition)
        return Button { router.push(hit.route) } label: {
            HStack(spacing: 8) {
                content
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(content.spokenLabel))
        .accessibilityIdentifier(identifier)
        .listRowInsets(EdgeInsets())
    }
}
