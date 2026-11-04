import SwiftUI
import Sub2Core

// 40 §7.3: the request detail's numbered sections other than 标识 (RequestDetailView.swift). Each header is a
// NumberedSectionHeader whose id names the section (logs.detail.timing / .attempts / .tokens / .links).

/// What the sections show for either look: the usage record (the success) or the error record with its detail.
extension RequestDetailModel {
    var timing: RequestTiming {
        if let usage { return RequestDetailPresentation.timing(usage) }
        guard let record else { return RequestDetailPresentation.timing(firstTokenMs: nil, durationMs: nil) }
        return RequestDetailPresentation.timing(record, detail: detail.value)
    }
    var method: String {
        if let usage { return RequestDetailPresentation.requestTypeName(usage.requestType, context: .detail) }
        return RequestDetailPresentation.requestTypeName(code: record?.requestType, stream: record?.stream, context: .detail)
    }
    var links: [RequestLinkRow] {
        if let usage { return RequestDetailLayout.links(usage) }
        return record.map { RequestDetailLayout.links($0, detail: detail.value) } ?? []
    }
    var identifiers: [RequestIdentifierRow] {
        if let usage { return RequestDetailLayout.identifiers(usage) }
        return record.map { RequestDetailLayout.identifiers($0, chain: chain) } ?? []
    }
}

/// A small label over its figure, read as one: “总耗时 3.2s”, a missing value as 无数据.
struct RequestDetailFigure: View {
    let label: String
    let value: String
    let id: String
    var isProminent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.ink3)
            Text(value)
                .font(isProminent ? .body.weight(.semibold) : .subheadline.weight(.medium)).monospacedDigit()
                .foregroundStyle(value == DisplayFormat.missing ? Palette.ink3 : Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(DisplayFormat.spoken(value))")
        .accessibilityIdentifier(id)
    }
}

/// 耗时: the first token's share of the total (at least 4%, the total bar alone without one), then 首字, 总耗时 (“约” when
/// summed from the phases) and 方式. Identifiers logs.detail.timing.firstToken / .total / .method.
struct RequestTimingSection: View {
    let timing: RequestTiming
    let method: String
    let ordinal: String?
    /// A failed look's detail is on its way with the phase timings.
    let isLoading: Bool

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                RequestTimingBar(share: timing.firstTokenShare)
                HStack(alignment: .top, spacing: 12) {
                    RequestDetailFigure(label: "首字", value: timing.firstToken, id: "logs.detail.timing.firstToken")
                    RequestDetailFigure(label: "总耗时", value: timing.total, id: "logs.detail.timing.total")
                    RequestDetailFigure(label: "方式", value: method, id: "logs.detail.timing.method")
                }
            }
            .padding(.vertical, 6)
        } header: {
            NumberedSectionHeader(title: RequestDetailLayout.title(.timing), ordinal: ordinal, id: "logs.detail.timing") {
                if isLoading { ProgressView().controlSize(.small).accessibilityLabel("正在读取详情") }
            }
        }
    }
}

private struct RequestTimingBar: View {
    let share: Double?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if let share { Capsule().fill(Palette.accent).frame(width: max(0, proxy.size.width - 2) * share) }
                Capsule().fill(Palette.hairline)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 上游尝试: the tries oldest first, each opening its account; a spinner while the chain loads, “没能取到重试链” when neither the
/// chain nor the fallback could be read, and the dropped tries under it. Identifiers logs.detail.attempt.<index>,
/// logs.detail.attempts.loading / .unavailable / .dropped.
struct RequestAttemptsSection: View {
    let state: RequestDetailModel.Attempts
    let rows: [AttemptRow]
    let meta: String?
    let dropped: String?
    let ordinal: String?

    var body: some View {
        Section {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("logs.detail.attempts.loading")
            case .unavailable:
                Text(RequestDetailCopy.chainUnavailable).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("logs.detail.attempts.unavailable")
            case .hidden, .chain, .fallback:
                ForEach(rows) { row($0) }
            }
        } header: {
            NumberedSectionHeader(title: RequestDetailLayout.title(.attempts), ordinal: ordinal, meta: meta, id: "logs.detail.attempts")
        } footer: {
            if let dropped { Text(dropped).accessibilityIdentifier("logs.detail.attempts.dropped") }
        }
    }

    @ViewBuilder private func row(_ row: AttemptRow) -> some View {
        let label = [row.title, row.trailing, row.subtitle].joined(separator: "，")
        if let accountID = row.accountID {
            NavigationLink(value: AppRoute.account(id: accountID)) { RequestAttemptRow(row: row) }
                .accessibilityLabel(label)
                .accessibilityIdentifier("logs.detail.attempt.\(row.id)")
        } else {
            RequestAttemptRow(row: row)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier("logs.detail.attempt.\(row.id)")
        }
    }
}

/// The numbered circle in the try's tone, the account, “429 · 0.4s” and what happened next.
private struct RequestAttemptRow: View {
    let row: AttemptRow
    @ScaledMetric(relativeTo: .footnote) private var circle = 26.0

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.id)").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(row.tone.ink)
                .frame(width: circle, height: circle)
                .background(row.tone.wash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.trailing).font(.footnote).monospacedDigit().foregroundStyle(row.tone == .ok ? Palette.ink2 : row.tone.ink)
                }
                Text(row.subtitle).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Token (the success look): 输入 / 输出 / 缓存读 / 缓存写. Identifiers logs.detail.tokens.input / .output / .cacheRead / .cacheWrite.
struct RequestTokensSection: View {
    let cells: [RequestCostCell]
    let ordinal: String?
    private static let ids = ["input", "output", "cacheRead", "cacheWrite"]

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                ForEach(Array(zip(Self.ids, cells)), id: \.0) { id, cell in
                    RequestDetailFigure(label: cell.label, value: cell.value, id: "logs.detail.tokens." + id)
                }
            }
            .padding(.vertical, 6)
        } header: {
            NumberedSectionHeader(title: RequestDetailLayout.title(.tokens), ordinal: ordinal, id: "logs.detail.tokens")
        }
    }
}

/// 关联: user, key, group and account; a row with a page opens it, the key and a missing name never do (40 §7.1).
/// Identifiers logs.detail.link.user / .key / .group / .account.
struct RequestLinksSection: View {
    let rows: [RequestLinkRow]
    let ordinal: String?

    var body: some View {
        Section {
            ForEach(rows) { row($0) }
        } header: {
            NumberedSectionHeader(title: RequestDetailLayout.title(.links), ordinal: ordinal, id: "logs.detail.links")
        }
    }

    @ViewBuilder private func row(_ row: RequestLinkRow) -> some View {
        let label = ([Self.kindName(row.kind), DisplayFormat.spoken(row.title)] + (row.kind == .key ? [row.trailing].compactMap { $0 } : []))
            .joined(separator: " ")
        if let route = Self.route(row) {
            NavigationLink(value: route) { RequestLinkRowContent(row: row) }
                .accessibilityLabel(label)
                .accessibilityIdentifier("logs.detail.link." + row.kind.rawValue)
        } else {
            RequestLinkRowContent(row: row)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier("logs.detail.link." + row.kind.rawValue)
        }
    }
    private static func route(_ row: RequestLinkRow) -> AppRoute? {
        guard let id = row.targetID else { return nil }
        return switch row.kind {
        case .user: .user(id: id)
        case .group: .group(id: id)
        case .account: .account(id: id)
        case .key: nil
        }
    }
    private static func kindName(_ kind: RequestLinkRow.Kind) -> String {
        switch kind {
        case .user: "用户"
        case .key: "Key"
        case .group: "分组"
        case .account: "账号"
        }
    }
}

private struct RequestLinkRowContent: View {
    let row: RequestLinkRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(row.kind)).font(.subheadline).foregroundStyle(Palette.ink3).frame(width: 22).accessibilityHidden(true)
            Text(row.title).font(.subheadline).foregroundStyle(row.title == DisplayFormat.missing ? Palette.ink3 : Palette.ink1).lineLimit(1)
            Spacer(minLength: 8)
            if let trailing = row.trailing {
                Text(trailing).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1)
                    .fontDesign(row.isMonospacedTrailing ? .monospaced : .default)
            }
        }
        .frame(minHeight: 44)
    }
    private static func symbol(_ kind: RequestLinkRow.Kind) -> String {
        switch kind {
        case .user: "person"
        case .key: "key"
        case .group: "square.stack.3d.up"
        case .account: "server.rack"
        }
    }
}
