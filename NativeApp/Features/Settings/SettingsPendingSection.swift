import SwiftUI
import Sub2Core

/// 60 §3.3 柒 (R01, D16): balance, redeem-batch and compensation records of every site, oldest first, with the shared title
/// and detail line after the site's name. A record of the connected site opens its check (“去核对 ›”); another site's
/// opens that site's Web admin.
struct SettingsPendingRows: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let now = Date()
        ForEach(model.allPendingMoneyWrites, id: \.id) { record in
            row(record, now: now)
        }
    }

    private func row(_ record: any PendingMoneyWrite, now: Date) -> some View {
        let profile = model.profileForRecord(serverID: record.serverID)
        let isCurrentSite = record.serverID == model.activeProfile?.id
        // Day boundaries of the connected site follow its zone (00 §6.3); another site's zone is not known here.
        let zone = isCurrentSite ? model.siteSession?.serverTimeZone.timeZone ?? .current : .current
        let line = SettingsPresentation.pendingRow(siteName: profile?.name ?? "原站点", summary: record.summary, now: now, timeZone: zone)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                if let amount = line.amount { Text(amount).monospacedDigit().foregroundStyle(Palette.ink1) }
            }
            Text(line.detail).font(.footnote).foregroundStyle(Palette.ink2)
            if record is PendingBalanceOperation {
                Text(record.id.uuidString).font(.caption2.monospaced()).foregroundStyle(Palette.ink3).textSelection(.enabled)
            }
            if isCurrentSite {
                Button { open(record) } label: { Text("去核对 ›").frame(minHeight: 44).contentShape(Rectangle()) }
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("settings.pending.check.\(record.id.uuidString)")
            } else if let profile {
                Link(destination: profile.baseURL) { Text("打开原站点核对").frame(minHeight: 44).contentShape(Rectangle()) }
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("settings.pending.web.\(record.id.uuidString)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.pending.\(Self.kind(of: record)).\(record.id.uuidString)")
    }

    /// Stage 0 maps these to the existing user page and the placeholders of the redeem check (60 §11, §19).
    private func open(_ record: any PendingMoneyWrite) {
        switch record {
        case let grant as PendingCompensation: router.present(.redeemGrant(userID: grant.userID, pendingID: grant.id))
        case let batch as PendingRedeemBatch: router.present(.redeemReconcile(batchID: batch.id))
        default: if let userID = record.summary.userID { router.push(.user(id: userID)) }
        }
    }

    private static func kind(of record: any PendingMoneyWrite) -> String {
        switch record {
        case is PendingRedeemBatch: "redeem"
        case is PendingCompensation: "compensation"
        default: "balance"
        }
    }
}
