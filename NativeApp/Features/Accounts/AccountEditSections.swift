import SwiftUI
import Sub2Core

// 20 §3.1, §3.3: the detail's 基础 and 调度 sections, read-only rows under a title with “编辑”. S2-11, S2-12 and S2-16 put their
// sections in AccountEditSectionBox with the same AccountSectionEdit.

/// The “编辑” at a section's top right: greyed until the page has read the account (S2D1-06), while a write runs, and for a
/// read-only token (C-1); “先刷新账号” beside it when only the list's copy could be shown, or when its version could not be read.
struct AccountSectionEdit {
    let isEnabled: Bool
    let needsRefresh: Bool
    let isPreparing: Bool
    let action: () -> Void
}

/// A section of the detail's lower half: the title and its “编辑” over a surface card, an optional footnote below.
struct AccountEditSectionBox<Content: View>: View {
    let title: String
    /// account.section.<key>, …edit
    let key: String
    let edit: AccountSectionEdit?
    var footnote: String?
    /// Beside the title, before “编辑” (模型's “只调度这 N 个”, S2-12).
    var meta: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(Palette.ink3).padding(.horizontal, 4)
            }
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("account.section.\(key)")
            Spacer(minLength: 8)
            if let meta {
                Text(meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3).accessibilityIdentifier("account.section.\(key).meta")
            }
            if let edit { editControl(edit) }
        }
    }

    @ViewBuilder private func editControl(_ edit: AccountSectionEdit) -> some View {
        if edit.needsRefresh {
            Text(AccountEditCopy.needsRefresh).font(.footnote).foregroundStyle(Palette.ink3)
                .accessibilityIdentifier("account.section.\(key).needsRefresh")
        }
        if edit.isPreparing {
            ProgressView().frame(minWidth: 44, minHeight: 44).accessibilityLabel("正在读取账号")
        } else {
            Button("编辑", action: edit.action)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!edit.isEnabled)
                .accessibilityLabel("编辑\(title)")
                .accessibilityIdentifier("account.section.\(key).edit")
                .readOnlyGate()
        }
    }
}

/// A read-only form row (LabeledContent in the design): label and note on the left, the value on the right; notes run below
/// their label instead. VoiceOver reads the label, then the value (“无数据” for “—”).
struct AccountInfoRow: View {
    let label: String
    var note: String?
    let value: String
    var tone: Color = Palette.ink1
    let id: String
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 4) {
                    labels
                    valueText.multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    labels
                    Spacer(minLength: 12)
                    valueText.multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(DisplayFormat.spoken(value)))
        .accessibilityHint(Text(note ?? ""))
        .accessibilityIdentifier(id)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink2)
            if let note { Text(note).font(.footnote).foregroundStyle(Palette.ink3) }
        }
    }
    private var valueText: some View {
        Text(value).font(.subheadline).monospacedDigit().foregroundStyle(tone)
    }
}

/// 基础: 名称, 账号状态 (停用 dim, 错误 critical), 平台 · 类型, 备注 (“—” when empty).
struct AccountBasicSection: View {
    let account: UpstreamAccount
    let platformText: String
    let edit: AccountSectionEdit

    var body: some View {
        let status = AccountEditStatus(accountStatus: account.status)
        let notes = account.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        AccountEditSectionBox(title: AccountEditSection.basic.title, key: "basic", edit: edit) {
            AccountInfoRow(label: AccountEditField.name.title, value: account.name, id: "account.basic.name")
            AccountInfoRow(label: AccountEditField.status.title, value: status.title, tone: Self.color(status), id: "account.basic.status")
            AccountInfoRow(label: "平台", value: platformText, id: "account.basic.platform")
            AccountInfoRow(label: AccountEditField.notes.title, value: notes.isEmpty ? DisplayFormat.missing : notes,
                           tone: notes.isEmpty ? Palette.ink3 : Palette.ink1, id: "account.basic.notes", stacked: !notes.isEmpty)
        }
    }

    private static func color(_ status: AccountEditStatus) -> Color {
        switch status {
        case .active: Palette.ink1
        case .inactive: Palette.ink3
        case .error: Tone.critical.ink
        }
    }
}

/// 调度: 并发数, 优先级, ×倍率, 负载因子 (“默认”), 分组 (chips or “未分组”), 过期时间 in the phone's zone (U53), and for API Key and
/// Bedrock accounts the set limits with what is used, or one “配额 · 不限” row.
struct AccountScheduleSection: View {
    let account: UpstreamAccount
    let groupName: (Int) -> String
    let edit: AccountSectionEdit

    var body: some View {
        AccountEditSectionBox(title: AccountEditSection.sched.title, key: "sched", edit: edit) {
            AccountInfoRow(label: AccountEditField.concurrency.title, value: account.concurrency.map(String.init) ?? DisplayFormat.missing,
                           id: "account.sched.concurrency")
            AccountInfoRow(label: AccountEditField.priority.title, note: AccountEditCopy.priorityNote,
                           value: account.priority.map(String.init) ?? DisplayFormat.missing, id: "account.sched.priority")
            AccountInfoRow(label: AccountEditField.rateMultiplier.title, note: AccountEditCopy.rateNote, value: AccountEditCopy.rate(account.rateMultiplier),
                           id: "account.sched.rate")
            loadFactorRow
            AccountGroupChipsRow(names: AccountEditDraft.groupOrder(account).map(groupName))
            expiryRow
            quotaRows
        }
    }

    private var loadFactorRow: some View {
        let factor = account.loadFactor ?? 0
        return AccountInfoRow(label: AccountEditField.loadFactor.title, note: AccountEditCopy.loadFactorNote,
                              value: factor > 0 ? String(factor) : AccountEditCopy.loadFactorDefault, tone: factor > 0 ? Palette.ink1 : Palette.ink3,
                              id: "account.sched.loadFactor")
    }
    private var expiryRow: some View {
        let expires = account.expiresAt.map { $0 > 0 } ?? false
        return AccountInfoRow(label: AccountEditField.expiresAt.title,
                              note: expires && account.autoPauseOnExpired == true ? AccountEditCopy.autoPauseNote : nil,
                              value: AccountExpiry.text(account.expiresAt, timeZone: .current), tone: expires ? Palette.ink1 : Palette.ink3,
                              id: "account.sched.expiry")
    }
    @ViewBuilder private var quotaRows: some View {
        if AccountEditForm.supportsQuota(type: account.type) {
            let limited = AccountQuota.allCases.filter { $0.limit(in: account) != nil }
            if limited.isEmpty {
                AccountInfoRow(label: AccountEditCopy.quotaTitle, note: AccountEditCopy.quotaKinds, value: AccountEditCopy.quotaUnlimited,
                               tone: Palette.ink3, id: "account.sched.quota.none")
            } else {
                ForEach(limited, id: \.self) { quota in
                    AccountInfoRow(label: quota.field.title, note: AccountEditCopy.quotaUsed(quota.used(in: account)),
                                   value: DisplayFormat.money(quota.limit(in: account)), id: "account.sched.quota.\(quota.rawValue)")
                }
            }
        }
    }
}

/// 分组: the group names as chips, or “未分组”.
private struct AccountGroupChipsRow: View {
    let names: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AccountEditField.groups.title).font(.subheadline).foregroundStyle(Palette.ink2)
            Spacer(minLength: 12)
            if names.isEmpty {
                Text(AccountEditCopy.ungrouped).font(.subheadline).foregroundStyle(Palette.ink3)
            } else {
                ListFieldFlow(spacing: 6) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Palette.sunken, in: Capsule())
                    }
                }
                .frame(maxWidth: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AccountEditField.groups.title))
        .accessibilityValue(Text(names.isEmpty ? AccountEditCopy.ungrouped : names.joined(separator: "、")))
        .accessibilityIdentifier("account.sched.groups")
    }
}
