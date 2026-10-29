import Foundation
import Sub2Core

/// One PUT of a proxy's status (停用 / 启用 and their 撤销), sent once without a key (R06; 60 §13.4). The reply is the plain
/// `dto.AdminProxy`, so it is merged onto the shown row to keep its counts, latency and quality. A lost reply is read back.
struct ProxyStatusWrite: Sendable {
    enum Outcome: Sendable {
        case applied(AdminProxy)
        /// `fresh`: what the read-back found when the write did not land.
        case failed(ProxyDetailFailure, fresh: AdminProxy?)
        case ignored
    }

    let id: Int
    let source: any ProxyDetailSource
    let isCurrent: @MainActor @Sendable () -> Bool

    /// Without `base` (the page is gone and the catalog has no row) the reply stands as it came.
    @MainActor func send(_ status: ProxyStatusChange, onto base: AdminProxy?) async -> Outcome {
        guard isCurrent() else { return .ignored }
        do {
            let reply = try await source.updateProxy(id: id, ProxyUpdateRequest(status: status))
            guard isCurrent() else { return .ignored }
            return .applied(base?.mergingConfiguration(from: reply) ?? reply)
        } catch {
            guard isCurrent() else { return .ignored }
            switch ProxyDetailFailure.classify(error) {
            case .cancelled: return .ignored
            case .unconfirmed: return await readBack(status, after: error)
            case let failure: return .failed(failure, fresh: nil)
            }
        }
    }

    /// 00 §2.4: landed when the status reads the target; another status means it did not, in the transport's words; an
    /// unreadable proxy stays unknown.
    @MainActor private func readBack(_ status: ProxyStatusChange, after error: any Error) async -> Outcome {
        do {
            let fresh = try await source.proxy(id: id)
            guard isCurrent() else { return .ignored }
            return fresh.status == status.rawValue ? .applied(fresh) : .failed(.rejected(error.localizedDescription), fresh: fresh)
        } catch {
            guard isCurrent() else { return .ignored }
            return .failed(ProxyDetailFailure.isGone(error) ? .gone : .unconfirmed, fresh: nil)
        }
    }

    /// The receipt of a failed write; `.gone` says nothing here (the page shows “已删除”).
    @MainActor static func report(_ failure: ProxyDetailFailure, to receipts: ReceiptCenter, rejected text: (String) -> String) {
        switch failure {
        case .unconfirmed: receipts.show(Receipt(text: ProxyDetailCopy.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution))
        case .reconfirm(let notice): receipts.show(Receipt(text: notice, systemImage: "checkmark.shield", tone: .caution))
        case .rejected(let reason): receipts.show(Receipt(text: text(reason), systemImage: "exclamationmark.triangle", tone: .critical))
        case .gone, .cancelled: break
        }
    }
}
