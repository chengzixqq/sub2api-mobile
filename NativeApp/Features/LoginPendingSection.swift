import SwiftUI
import Sub2Core

/// The login page's money records awaiting their check, all three kinds and oldest first (R01), with the shared title and
/// detail line after the record's site. With no connected site, where each row leads is OldLoginPresentation.rootAction: a
/// saved site of the record's address signs in there and checks it in 设置 → 待核对 with that identity (C-26); only an
/// address without a saved site opens its Web admin (D17). Settings' own origin note and action do not apply here.
struct LoginPendingSection: View {
    @Environment(AppModel.self) private var model
    /// Saved sites whose credential reads as missing; read again when the list, the session or the login prompt changes.
    @State private var withoutCredential: Set<UUID> = []

    private struct CredentialKey: Hashable {
        let ids: [UUID]
        let generation: UUID?
        let prompt: UUID?
    }

    var body: some View {
        let records = model.allPendingMoneyWrites
        if !records.isEmpty {
            let reusable = Set(model.profiles.map(\.id).filter { !model.hasPendingRecords(serverID: $0) })
            Section(OldLoginPresentation.rootSectionTitle) {
                Text(OldLoginPresentation.rootFootnote).font(.footnote).foregroundStyle(.secondary)
                    .task(id: CredentialKey(ids: model.profiles.map(\.id), generation: model.sessionGeneration, prompt: model.loginPrompt?.id)) {
                        withoutCredential = await model.credentials.siteIDsWithoutCredential(model.profiles.map(\.id))
                    }
                ForEach(records, id: \.id) { record in row(record, reusable: reusable) }
            }
        }
    }

    private func row(_ record: any PendingMoneyWrite, reusable: Set<UUID>) -> some View {
        let site = model.profileForRecord(serverID: record.serverID)
        let line = SettingsPresentation.pendingRow(siteName: site?.name ?? "原站点", summary: record.summary, now: Date(), timeZone: .current)
        let action = OldLoginPresentation.rootAction(recordSite: site, saved: model.profiles, withoutCredential: withoutCredential, reusable: reusable)
        let id = record.id.uuidString
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let amount = line.amount { Text(amount).monospacedDigit() }
            }
            Text(line.detail).font(.footnote).foregroundStyle(.secondary)
            if record is PendingBalanceOperation { Text(id).font(.caption2.monospaced()).textSelection(.enabled) }
            switch action {
            case .signIn(let target):
                Button(OldLoginPresentation.signInTitle(target)) { Task { await model.switchTo(target) } }
                    .frame(minHeight: 44).accessibilityIdentifier("login.pending.signIn.\(id)")
            case .openOriginalSite(let url):
                Link(SettingsPresentation.openOriginalSiteTitle, destination: url).frame(minHeight: 44).accessibilityIdentifier("login.pending.web.\(id)")
            case .none:
                EmptyView()
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("login.pending.\(id)")
    }
}
