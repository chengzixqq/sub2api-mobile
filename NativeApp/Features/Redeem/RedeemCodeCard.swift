import SwiftUI
import Sub2Core

/// 60 §8.3–§8.4: one code as a card. The head (masked code, face value, second line, badge) toggles it open; an open card
/// shows the code box, its facts, the notes and the button row. Buttons inside are `.borderless`, so a tap reaches only
/// them. A collapsed card copies on a leading swipe. S6-05 adds 禁用 / 启用 / 编辑 / 续期, the trailing swipe and delete.
struct RedeemCodeCard: View {
    let code: AdminRedeemCode
    let isOpen: Bool
    /// The server-corrected clock and the server's zone (00 §6.3).
    let now: Date
    let timeZone: ServerTimeZone
    /// A subscription code's group from the group directory when the row has none (X11).
    let groupName: String?
    let readOnly: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onOpenUser: (Int) -> Void
    let onShowBatch: () -> Void

    private var zone: TimeZone { timeZone.timeZone }
    private var face: RedeemFaceValue { RedeemPresentation.faceValue(code) }
    private var subtitle: String { RedeemPresentation.subtitle(code, groupName: groupName, now: now, timeZone: zone) }
    private var badge: RedeemBadge { RedeemPresentation.badge(code) }
    private var isDimmed: Bool { RedeemPresentation.isDimmed(code) }
    private var notes: String? { code.notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
    /// The head for VoiceOver: the tail instead of the dots.
    var spokenLabel: String { ["兑换码结尾 " + RedeemPresentation.tail(code.code), face.text, subtitle, badge.label].joined(separator: "，") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) { head }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(isOpen ? "已展开" : "已收起")
                .accessibilityIdentifier("redeem.card.\(code.id)")
            if isOpen { details.accessibilityElement(children: .contain).accessibilityIdentifier("redeem.card.\(code.id).body") }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading) {
            if !isOpen {
                Button(action: onCopy) { Label("复制兑换码", systemImage: "doc.on.doc") }
                    .tint(Palette.accentFill)
                    .accessibilityIdentifier("redeem.swipe.copy.\(code.id)")
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(code.type))
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(width: 28, height: 28)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(RedeemPresentation.shortCode(code.code)).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(isDimmed ? Palette.ink2 : Palette.ink1).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(face.text).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(face.isMuted || isDimmed ? Palette.ink3 : Palette.ink1).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    ToneBadge(text: badge.label, tone: badge.tone)
                }
            }
            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3)
                .rotationEffect(.degrees(isOpen ? 180 : 0)).padding(.top, 6)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            RedeemCodeBox(code: code.code, identifier: "redeem.card.\(code.id).box", onCopy: onCopy)
            VStack(spacing: 0) { facts }
            HStack {
                Spacer()
                moreMenu
            }
        }
    }

    @ViewBuilder private var facts: some View {
        if code.isRedeemed {
            factRow("使用者", combined: false) {
                if let userID = code.user?.id ?? code.usedBy {
                    Button(RedeemPresentation.userName(code)) { onOpenUser(userID) }
                        .buttonStyle(.borderless).frame(minHeight: 44)
                        .accessibilityIdentifier("redeem.card.\(code.id).user")
                } else {
                    Text(RedeemPresentation.userName(code))
                }
            }
            factRow("使用时间") { Text(DisplayFormat.monthDayClock(code.usedAt, timeZone: timeZone, now: now)).monospacedDigit() }
        }
        factRow("生成时间") { Text(DisplayFormat.monthDayClock(code.createdAt, timeZone: timeZone, now: now)).monospacedDigit() }
        factRow("过期时间") {
            let expiry = RedeemPresentation.expiry(code, now: now, timeZone: zone)
            Text(expiry.text).monospacedDigit().foregroundStyle(expiry.tone?.ink ?? Palette.ink1)
        }
        if code.codeType == .subscription {
            factRow("订阅分组") { Text(RedeemPresentation.prefix(code, groupName: groupName)) }
            factRow("有效天数") { Text(code.validityDays.map { "\($0) 天" } ?? DisplayFormat.missing).monospacedDigit() }
        }
        factRow("备注") {
            Text(notes ?? DisplayFormat.missing).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("redeem.card.\(code.id).notes")
        }
    }

    /// The user row keeps its link a separate element; the others read as “label, value”.
    private func factRow<Value: View>(_ label: String, combined: Bool = true, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            value().foregroundStyle(Palette.ink1)
        }
        .font(.subheadline)
        .frame(minHeight: 32)
        .accessibilityElement(children: combined ? .combine : .contain)
    }

    /// The ··· menu (60 §8.3): the head's code and “余额 · $10.00 · 未使用” on top, then 复制 / 查看使用者 / 查看同一批.
    private var moreMenu: some View {
        Menu {
            Section(RedeemPresentation.shortCode(code.code) + "  " + RedeemPresentation.menuMessage(code)) {
                ForEach(Array(RedeemPresentation.menuItems(code, readOnly: readOnly).enumerated()), id: \.offset) { _, item in menuButton(item) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                .frame(width: 44, height: 44)
                .background(Palette.sunken, in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(RedeemCardAction.more.title)
        .accessibilityIdentifier("redeem.card.\(code.id).more")
    }

    @ViewBuilder private func menuButton(_ item: RedeemMenuItem) -> some View {
        switch item {
        case .copy: Button(item.title, systemImage: "doc.on.doc", action: onCopy)
        case .viewUser(let userID, _): Button(item.title, systemImage: "person") { onOpenUser(userID) }
        case .viewBatch: Button(item.title, systemImage: "square.stack.3d.up", action: onShowBatch)
        // 删除兑换码…：S6-05
        case .delete: EmptyView()
        }
    }

    private static func symbol(_ type: String) -> String {
        switch type {
        case "balance", "admin_balance": "dollarsign.circle"
        case "concurrency", "admin_concurrency": "arrow.up.right.circle"
        case "subscription": "calendar"
        case "invitation": "envelope"
        default: "ticket"
        }
    }
}

/// 60 §8.5 首次加载: cards in the head's shape.
struct RedeemCodeCardSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.sunken).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("a3f0····d4e8").font(.system(.subheadline, design: .monospaced)); Spacer(); Text("$00.00") }
                HStack { Text("余额 · 10/23 过期").font(.footnote); Spacer(); Text("未使用").font(.caption) }
            }
        }
        .foregroundStyle(Palette.ink3)
        .redacted(reason: .placeholder)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RedeemListText.loading))
        .accessibilityIdentifier("redeem.loading")
    }
}
