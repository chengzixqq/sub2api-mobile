import SwiftUI
import Sub2Core

/// 60 §8.3–§8.4: one code as a card. The head (masked code, face value, second line, badge) toggles it open; an open card
/// shows the code box, its facts, the notes and the button row. Buttons inside are `.borderless`, so a tap reaches only
/// them. A collapsed card copies on a leading swipe; with `onAction` (S6-05) the button row and the trailing swipe carry
/// 禁用 / 启用 / 编辑 / 续期, and with `onDelete` ··· ends with 删除兑换码….
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
    /// A write of this code is running: its buttons and 删除兑换码… wait.
    var isRunning = false
    var onAction: ((RedeemCardAction) -> Void)?
    var onDelete: (() -> Void)?

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
        // 60 §8.4: never delete here.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isOpen, !isRunning, onAction != nil, let swipe = RedeemPresentation.trailingSwipe(code, readOnly: readOnly) {
                Button { onAction?(swipe) } label: { Label(swipe.title, systemImage: Self.symbol(swipe)) }
                    .tint(swipe == .disable ? Palette.neutral : Palette.accentFill)
                    .accessibilityIdentifier("redeem.swipe.\(Self.identifier(swipe)).\(code.id)")
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
            HStack(spacing: 8) {
                ForEach(buttons, id: \.self) { actionButton($0) }
                Spacer(minLength: 0)
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
        case .delete:
            // Waits with the buttons: a delete confirmed while another write of this code runs would be dropped.
            if let onDelete { Button(item.title, systemImage: "trash", role: .destructive, action: onDelete).disabled(isRunning) }
        }
    }

    // MARK: Writes (S6-05)

    /// 未使用 “禁用 · 编辑”, 已禁用 “启用 · 编辑”, 已过期 “续期” (primary), redeemed “编辑备注”; none for a read-only token.
    private var buttons: [RedeemCardAction] {
        guard onAction != nil else { return [] }
        return RedeemPresentation.actions(code, readOnly: readOnly).filter { $0 != .more }
    }
    private func actionButton(_ action: RedeemCardAction) -> some View {
        Button { onAction?(action) } label: {
            Label(action.title, systemImage: Self.symbol(action))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(action.isPrimary ? Palette.onAccent : Palette.ink1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(action.isPrimary ? Palette.accentFill : Palette.sunken, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(isRunning)
        .accessibilityIdentifier("redeem.card.\(code.id).\(Self.identifier(action))")
    }
    private static func identifier(_ action: RedeemCardAction) -> String {
        switch action {
        case .disable, .enable: "toggle"
        case .edit, .editNotes: "edit"
        case .renew: "renew"
        case .more: "more"
        }
    }
    private static func symbol(_ action: RedeemCardAction) -> String {
        switch action {
        case .disable: "minus.circle"
        case .enable: "play.circle"
        case .edit, .editNotes: "square.and.pencil"
        case .renew: "arrow.clockwise"
        case .more: "ellipsis"
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
