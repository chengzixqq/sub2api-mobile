import SwiftUI
import Sub2Core

// 50 §6–§7 (S5-12): the pieces the group's API key page and subscription page share. Identifiers are `<prefix>.*` with the
// page's prefix (group.keys / group.subs).

/// 列表头: what the order is on the left, what the trailing column shows on the right.
struct GroupRecordsListHead: View {
    let leading: String
    let trailing: String
    let id: String

    var body: some View {
        HStack(spacing: 8) {
            Text(leading)
            Spacer(minLength: 8)
            Text(trailing).monospacedDigit()
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink3)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// The last row while more pages exist: “已显示 20 / 38 个 · 滚动到底继续加载” with a spinner, reading the next page once it shows
/// (again after leaving cancelled it, or after the foreground bumped `attempt`); after a failure only 加载失败 · 重试.
struct GroupRecordsMoreFooter: View {
    let hint: String
    let state: GroupRecordsNextPage
    let page: Int
    let attempt: Int
    let idPrefix: String
    let load: @MainActor () async -> Void
    let retry: @MainActor () async -> Void

    var body: some View {
        Group {
            if state == .failed {
                Button { Task { await retry() } } label: {
                    Text(GroupRecordsCopy.moreFailed).font(.subheadline).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(idPrefix + ".more.retry")
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(hint).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(idPrefix + ".more")
            }
        }
        .task(id: Request(page: page, attempt: attempt)) { if state == .idle { await load() } }
    }

    private struct Request: Hashable {
        let page: Int
        let attempt: Int
    }
}

/// 00 §4.6: a failed refresh keeps the rows under “刷新失败 · 重试” and “更新于 HH:MM”. During a 429 wait it counts down instead
/// and reads again by itself once the wait is over (00 §2.7.2). S5-高-3's strips over a kept amount or count use it with their own
/// title and the 更新失败 clock, and stay while that block is read again (a spinner, no tap).
struct GroupRecordsRefreshRow: View {
    var title = GroupRecordsCopy.refreshFailed
    var systemImage = "exclamationmark.triangle"
    let updatedAt: Date?
    let timeZone: ServerTimeZone
    let refresh: BlockRefresh
    var isRefreshing = false
    let id: String
    let retry: @MainActor () -> Void

    /// The 更新失败 strips' icon, as on the group list and detail (S5-高-3).
    static let staleImage = "clock.badge.exclamationmark"

    var body: some View {
        Group {
            if let notBefore = refresh.notBefore, notBefore > Date() {
                TimelineView(.periodic(from: .now, by: 1)) { context in banner(at: context.date) }
            } else {
                banner(at: Date())
            }
        }
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        .task(id: refresh.notBefore) { await retryAfterWait() }
    }

    private func banner(at now: Date) -> some View {
        let throttle = refresh.throttleMessage(at: now)
        let detail = throttle ?? GroupRecordsCopy.updatedText(updatedAt, timeZone: timeZone)
        return Button(action: retry) {
            StatusBanner(tone: .caution, systemImage: systemImage, title: title, detail: detail) {
                if isRefreshing { ProgressView().controlSize(.small) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(throttle != nil || isRefreshing)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: "，"))
        .accessibilityValue(isRefreshing ? BlockStatusPresentation.refreshingLabel : "")
        .accessibilityIdentifier(id)
    }

    private func retryAfterWait() async {
        guard let notBefore = refresh.notBefore else { return }
        let wait = notBefore.timeIntervalSinceNow
        guard wait > 0 else { return }
        do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        retry()
    }
}

/// 空态: a large “—” and the page's sentence.
struct GroupRecordsEmptyRow: View {
    let text: String
    let id: String

    var body: some View {
        VStack(spacing: 6) {
            Text(DisplayFormat.missing).font(.title.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// 首次加载: placeholder rows of a row's height.
struct GroupRecordsSkeleton: View {
    let id: String

    var body: some View {
        ForEach(0..<5, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 6) {
                Text("名称占位 sk-…0000").font(.subheadline.weight(.semibold))
                Text("用户占位 · 00:00").font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载…"))
        .accessibilityIdentifier(id)
    }
}

/// 50 §0.8: the group was deleted (its read answered 404); the whole page.
struct GroupRecordsDeletedView: View {
    let id: String

    var body: some View {
        ContentUnavailableView(GroupErrorCopy.deleted, systemImage: "trash")
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }
}

/// A row's tap target: the owner's page, or nothing for a row without a user id.
struct GroupRecordsRowLink<Label: View>: View {
    let userID: Int?
    let spokenLabel: String
    let id: String
    @ViewBuilder let label: Label

    var body: some View {
        Group {
            if let userID {
                NavigationLink(value: AppRoute.user(id: userID)) { label }
            } else {
                label
            }
        }
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityIdentifier(id)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
    }
}
