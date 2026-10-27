import SwiftUI
import Sub2Core

/// 60 §3.3 柒 (R01, D16): balance, redeem-batch and compensation records of every site, oldest first, with the shared title
/// and detail line after the site's name. A record of the connected address opens its check with the current identity
/// (“去核对 ›”), an older login's with a note (C-26); only another address opens that site's Web admin, since signing in
/// there again would make a new site id (D17). Balance rows of the connected site keep “打开原站点核对” too (沿用现有).
struct SettingsPendingRows: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let now = Date(), sameAddress = model.sameAddressServerIDs()
        ForEach(model.allPendingMoneyWrites, id: \.id) { record in
            row(record, now: now, sameAddress: sameAddress)
        }
    }

    private func row(_ record: any PendingMoneyWrite, now: Date, sameAddress: Set<UUID>) -> some View {
        let profile = model.profileForRecord(serverID: record.serverID)
        let origin = PendingRecordOrigin(recordServerID: record.serverID, currentServerID: model.activeProfile?.id, sameAddress: sameAddress)
        // Day boundaries at the connected address follow its zone (00 §6.3); another address's zone is not known here.
        let zone = origin == .otherAddress ? .current : model.siteSession?.serverTimeZone.timeZone ?? .current
        let line = SettingsPresentation.pendingRow(siteName: profile?.name ?? "原站点", summary: record.summary, now: now, timeZone: zone, origin: origin)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                if let amount = line.amount { Text(amount).monospacedDigit().foregroundStyle(Palette.ink1) }
            }
            Text(line.detail).font(.footnote).foregroundStyle(Palette.ink2)
            if let note = line.originNote {
                Text(note).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("settings.pending.origin.\(record.id.uuidString)")
            }
            if record is PendingBalanceOperation {
                Text(record.id.uuidString).font(.caption2.monospaced()).foregroundStyle(Palette.ink3).textSelection(.enabled)
            }
            // Borderless, so each control takes only its own taps inside the list row.
            HStack(spacing: 20) {
                if line.action == .check {
                    Button { open(record) } label: { Text("去核对 ›").frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("settings.pending.check.\(record.id.uuidString)")
                }
                if let profile, line.action == .openOriginalSite || (origin == .currentSite && record is PendingBalanceOperation) {
                    Link(destination: profile.baseURL) { Text("打开原站点核对").frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("settings.pending.web.\(record.id.uuidString)")
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.accent)
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
