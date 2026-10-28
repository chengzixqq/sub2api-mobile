import SwiftUI
import Sub2Core

/// 20 §3.3 模型 on the detail: “只调度这 N 个” / “未限制” beside the title, the passthrough note, each request model with its
/// actual one and limit badge, or “支持所有模型”.
struct AccountModelsSection: View {
    let account: UpstreamAccount
    let now: () -> Date
    let edit: AccountSectionEdit

    var body: some View {
        let mapping = AccountModelMapping(credentials: account.credentials)
        AccountEditSectionBox(title: AccountEditSection.models.title, key: "models", edit: edit, meta: mapping.summary) {
            if AccountModelMapping.passthroughEnabled(account) { AccountModelsPassthroughNote(id: "account.models.passthroughNote") }
            if mapping.isEmpty {
                Text(AccountModelMapping.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("account.models.empty")
            }
            ForEach(mapping.entries) { entry in
                AccountModelRow(entry: entry, limits: account.extra?.modelRateLimits ?? [], now: now, idPrefix: "account.models.row")
            }
        }
    }
}

/// 20 §3.3 高级 on the detail: the account's rows (开 / 关 dimmed, amounts, mode and protocol names) and, for every account, 在 Web
/// 中编辑 for the rest (S2-11's handler; a read-only token keeps it, it writes nothing). No rows, no “编辑”.
struct AccountAdvancedSection: View {
    let account: UpstreamAccount
    let catalog: MetaCatalog
    let edit: AccountSectionEdit
    let onOpenWeb: () -> Void

    var body: some View {
        let draft = AccountAdvancedDraft(account: account, catalog: catalog)
        AccountEditSectionBox(title: AccountEditSection.adv.title, key: "adv", edit: draft.fields.isEmpty ? nil : edit) {
            ForEach(draft.fields) { field in
                let shown = AccountAdvancedDraft.display(field, values: draft.base)
                AccountInfoRow(label: field.title, value: shown.text, tone: shown.isOff ? Palette.ink3 : Palette.ink1, id: "account.adv.\(field.rawValue)")
            }
            if !draft.fields.isEmpty { Rectangle().fill(Palette.hairline).frame(height: 1) }
            webRow
        }
    }

    private var webRow: some View {
        Button(action: onOpenWeb) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AccountAdvancedDraft.webRowTitle).font(.subheadline).foregroundStyle(Palette.ink1)
                    Text(AccountAdvancedDraft.webRowSubtitle).font(.footnote).foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
                Image(systemName: "safari").foregroundStyle(Palette.ink2).accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AccountAdvancedDraft.webRowTitle)
        .accessibilityHint(AccountAdvancedDraft.webRowSubtitle)
        .accessibilityIdentifier("account.adv.web")
    }
}
