import SwiftUI
import Sub2Core

/// 60 §16.3: the preview and, unless the token is read-only, the button row. The running write's button spins; the others wait.
struct AnnouncementDetailHeader: View {
    let announcement: Announcement
    let showsButtons: Bool
    let inFlight: AnnouncementDetailAction?
    let isBusy: Bool
    let onAction: (AnnouncementDetailAction) -> Void

    var body: some View {
        VStack(spacing: 12) {
            AnnouncementPreviewCard(title: announcement.title, content: announcement.content, notifyMode: announcement.notifyMode)
            if showsButtons {
                HStack(spacing: 10) {
                    ForEach(AnnouncementDetailPresentation.buttons(for: announcement.status), id: \.action) { button($0) }
                }
            }
        }
    }

    @ViewBuilder private func button(_ item: AnnouncementDetailButton) -> some View {
        let action = item.action
        let base = Button { onAction(action) } label: {
            ZStack {
                Label(action.title, systemImage: action.systemImage).opacity(inFlight == action ? 0 : 1)
                if inFlight == action { ProgressView() }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .controlSize(.large)
        .disabled(isBusy)
        .accessibilityIdentifier("announcement.detail.\(action.rawValue)")
        if item.isPrimary { base.buttonStyle(.borderedProminent) } else { base.buttonStyle(.bordered) }
    }
}

/// 壹 投放: who sees it (wrapping), how, from and until when (the phone's zone, 00 §6.3), and 已读情况 unless a draft.
struct AnnouncementDeliverySection: View {
    let announcement: Announcement
    let targetText: String
    let readLine: AnnouncementReadLine?
    let zoneNote: String?
    let now: Date

    var body: some View {
        Section {
            row("可见对象", targetText, id: "target")
            row("通知方式", AnnouncementPresentation.notifyTitle(announcement.notifyMode), id: "notify")
            row("开始时间", AnnouncementPresentation.startText(announcement.startsAt, now: now, timeZone: .current), id: "starts")
            row("结束时间", AnnouncementPresentation.endText(announcement.endsAt, now: now, timeZone: .current), id: "ends")
            if let readLine { readsLink(readLine) }
        } header: {
            NumberedSectionHeader(title: "投放", ordinal: "壹")
        } footer: {
            if let zoneNote { Text(zoneNote).accessibilityIdentifier("announcement.detail.zoneNote") }
        }
    }

    private func row(_ label: String, _ value: String, id: String) -> some View {
        LabeledValue(label: label, value: value)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("announcement.detail.\(id)")
    }

    private func readsLink(_ line: AnnouncementReadLine) -> some View {
        NavigationLink(value: AppRoute.announcementReads(announcementID: announcement.id)) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(line.title).foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    if let value = line.value { Text(value).monospacedDigit().foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing) }
                }
                Text(line.detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("announcement.detail.reads")
    }
}

/// 贰 档案: when it was created and last updated, in the site's zone (R20).
struct AnnouncementArchiveSection: View {
    let createdAt: Date?
    let updatedAt: Date?
    let now: Date
    let timeZone: TimeZone

    var body: some View {
        Section {
            LabeledValue(label: "创建时间", value: AnnouncementPresentation.timestamp(createdAt, now: now, timeZone: timeZone))
                .accessibilityElement(children: .combine).accessibilityIdentifier("announcement.detail.created")
            LabeledValue(label: "更新时间", value: AnnouncementPresentation.timestamp(updatedAt, now: now, timeZone: timeZone))
                .accessibilityElement(children: .combine).accessibilityIdentifier("announcement.detail.updated")
        } header: {
            NumberedSectionHeader(title: "档案", ordinal: "贰")
        }
    }
}

/// 60 §16.4 ···: the title as the section's header with the status line under it, then the entries; writes are greyed for a
/// read-only token (00 §1.6) and while another write runs; 删除公告… comes last, in red.
struct AnnouncementDetailMenu: View {
    let title: String
    let subtitle: String
    let items: [AnnouncementMenuItem]
    let isBusy: Bool
    let onSelect: (AnnouncementMenuItem) -> Void

    var body: some View {
        Section(title) {
            Text(subtitle)
            ForEach(items.filter { !$0.isDestructive }, id: \.title) { entry($0) }
        }
        Section {
            ForEach(items.filter(\.isDestructive), id: \.title) { entry($0) }
        }
    }

    @ViewBuilder private func entry(_ item: AnnouncementMenuItem) -> some View {
        let button = Button(item.title, role: item.isDestructive ? .destructive : nil) { onSelect(item) }
        if item.isWrite { button.disabled(isBusy).readOnlyGate(showsCaption: false) } else { button }
    }
}
