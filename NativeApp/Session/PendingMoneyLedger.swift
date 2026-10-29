import Foundation
import Sub2Core

/// Where the money-write files live (00 §2.5.5): `Application Support/Sub2Mobile/`, one file per kind, written atomically
/// with complete file protection and kept out of backups. `memoryOnly` (UI tests) never touches the disk. Default JSON
/// coding, so the records S0-06 wrote keep reading (D16).
struct PendingMoneyFiles: Sendable {
    let directory: URL?
    let protectsFiles: Bool
    init(directory: URL?, protectsFiles: Bool = true) { self.directory = directory; self.protectsFiles = protectsFiles }
    static let memoryOnly = PendingMoneyFiles(directory: nil)
    static func applicationSupport() -> PendingMoneyFiles {
        PendingMoneyFiles(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sub2Mobile", isDirectory: true))
    }
    /// pending-balances.json is the file of earlier versions and keeps its name (not migrated).
    static func fileName(for kind: PendingMoneyKind) -> String {
        switch kind {
        case .balance: "pending-balances.json"
        case .redeemBatch: "pending-redeem-batches.json"
        case .compensation: "pending-compensations.json"
        }
    }
    func url(for kind: PendingMoneyKind) -> URL? { directory?.appendingPathComponent(Self.fileName(for: kind)) }
    var writeOptions: Data.WritingOptions { protectsFiles ? [.atomic, .completeFileProtection] : [.atomic] }
    /// A missing file is an empty list; one that exists but cannot be read or decoded throws.
    func read<Record: Decodable>(_ kind: PendingMoneyKind, as type: Record.Type) throws -> [Record] {
        guard let url = url(for: kind), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try JSONDecoder().decode([Record].self, from: Data(contentsOf: url))
    }
    func persist<Record: Encodable>(_ records: [Record], to kind: PendingMoneyKind) throws {
        guard let directory, let url = url(for: kind) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(directory)
        try JSONEncoder().encode(records).write(to: url, options: writeOptions)
    }
    /// Compensation codes are bearer credentials and every record has an e-mail: they stay on this device, like the
    /// credentials that could retry them. A failure here never blocks the write it protects.
    private static func excludeFromBackup(_ directory: URL) {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var target = directory
        try? target.setResourceValues(values)
    }
}

struct PendingMoneyError: LocalizedError, Equatable, Sendable {
    enum Reason: Sendable, Equatable {
        /// The kind's file could not be read: nothing of that kind is written (or overwritten) until it can.
        case paused
        case unsaved
        /// The same id with other request bytes would break “one key, one body” (00 §2.5.2).
        case conflictingRecord
    }
    let kind: PendingMoneyKind
    let reason: Reason
    var errorDescription: String? {
        switch reason {
        case .paused: kind.unreadableMessage
        case .unsaved: kind.unsavedMessage
        case .conflictingRecord: "这个操作编号已保存了内容不同的请求，已阻止发送。请重新确认。"
        }
    }
}

/// The three kinds of money-write records awaiting a result (00 §2.5.5, R01). Immutable: every change returns a new
/// ledger, and only after its file was saved, so a failed save leaves nothing to send. A kind whose file could not be read
/// stays empty and is never written until it is read again.
struct PendingMoneyLedger: Sendable {
    private(set) var balances: [PendingBalanceOperation]
    private(set) var redeemBatches: [PendingRedeemBatch]
    private(set) var compensations: [PendingCompensation]
    private(set) var unreadable: Set<PendingMoneyKind>
    init(balances: [PendingBalanceOperation] = [], redeemBatches: [PendingRedeemBatch] = [], compensations: [PendingCompensation] = [],
         unreadable: Set<PendingMoneyKind> = []) {
        self.balances = balances; self.redeemBatches = redeemBatches; self.compensations = compensations; self.unreadable = unreadable
    }

    static func load(from files: PendingMoneyFiles) -> PendingMoneyLedger { PendingMoneyLedger().reading(PendingMoneyKind.allCases, from: files) }
    /// For files the locked device could not open at launch (complete protection); readable kinds are left alone.
    func reloadingUnreadable(from files: PendingMoneyFiles) -> PendingMoneyLedger {
        reading(PendingMoneyKind.allCases.filter(unreadable.contains), from: files)
    }
    func isAvailable(_ kind: PendingMoneyKind) -> Bool { !unreadable.contains(kind) }
    /// 00 §2.5.5, one line per unreadable kind; nil once every file reads.
    var unreadableNotice: String? {
        unreadable.isEmpty ? nil : PendingMoneyKind.allCases.filter(unreadable.contains).map(\.unreadableMessage).joined(separator: "\n")
    }

    /// A copy taken before a reply keeps the action id and last send saved since (PendingBalanceOperation.merging).
    func remembering(_ record: PendingBalanceOperation, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        let merged = balances.first { $0.id == record.id }.map(record.merging(stored:)) ?? record
        return try remembering(merged, at: \.balances, kind: .balance, in: files)
    }
    /// A copy taken before a retry keeps the last send saved since (PendingRedeemBatch.merging).
    func remembering(_ record: PendingRedeemBatch, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        let merged = redeemBatches.first { $0.id == record.id }.map(record.merging(stored:)) ?? record
        return try remembering(merged, at: \.redeemBatches, kind: .redeemBatch, in: files)
    }
    func remembering(_ record: PendingCompensation, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        try remembering(record, at: \.compensations, kind: .compensation, in: files)
    }
    /// Only the file holding the record is written; an unknown id changes nothing.
    func resolving(id: UUID, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        if balances.contains(where: { $0.id == id }) { return try replacing(\.balances, with: balances.filter { $0.id != id }, kind: .balance, in: files) }
        if redeemBatches.contains(where: { $0.id == id }) {
            return try replacing(\.redeemBatches, with: redeemBatches.filter { $0.id != id }, kind: .redeemBatch, in: files)
        }
        if compensations.contains(where: { $0.id == id }) {
            return try replacing(\.compensations, with: compensations.filter { $0.id != id }, kind: .compensation, in: files)
        }
        return self
    }

    func record(id: UUID) -> (any PendingMoneyWrite)? { writes(serverID: nil).first { $0.id == id } }
    /// One site's records (all sites for nil), oldest first; legacy balance records without createdAt come first (D16).
    func writes(serverID: UUID?) -> [any PendingMoneyWrite] { writes { serverID == nil || $0.serverID == serverID } }
    /// The records of these site ids (one address, C-26), ordered like `writes(serverID:)`.
    func writes(serverIDs: Set<UUID>) -> [any PendingMoneyWrite] { writes { serverIDs.contains($0.serverID) } }
    /// D17: a site keeps its id for a new login only without records; an unreadable file may hold some.
    func mayHaveRecords(serverID: UUID) -> Bool { !unreadable.isEmpty || !writes(serverID: serverID).isEmpty }
    /// A record already saved goes out again: the execution grace restarts now (BACKLOG “余额重试后的执行宽限”), the fallback
    /// window stays at createdAt. A first send is returned unchanged.
    func resendStamped(_ operation: PendingBalanceOperation, at date: Date) -> PendingBalanceOperation {
        balances.contains { $0.id == operation.id } ? operation.with(lastSentAt: date) : operation
    }
    /// A batch already saved goes out again: an old server's fallback window reaches to this send (60 §11.4 末条), also after
    /// the App was closed. A first send is returned unchanged.
    func resendStamped(_ batch: PendingRedeemBatch, at date: Date) -> PendingRedeemBatch {
        redeemBatches.contains { $0.id == batch.id } ? batch.with(lastSentAt: date) : batch
    }

    private func writes(where included: (any PendingMoneyWrite) -> Bool) -> [any PendingMoneyWrite] {
        let kinds: [[any PendingMoneyWrite]] = [balances, redeemBatches, compensations]
        return kinds.joined().filter(included).sorted { ($0.summary.createdAt ?? .distantPast) < ($1.summary.createdAt ?? .distantPast) }
    }

    /// Adds the record, or replaces the one with the same id when its request bytes are unchanged (for example to save the
    /// action id before the result is known).
    private func remembering<Record: PendingMoneyWrite>(_ record: Record, at list: WritableKeyPath<PendingMoneyLedger, [Record]>,
                                                        kind: PendingMoneyKind, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        guard isAvailable(kind) else { throw PendingMoneyError(kind: kind, reason: .paused) }
        var records = self[keyPath: list]
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            guard try records[index].requestBody() == record.requestBody() else { throw PendingMoneyError(kind: kind, reason: .conflictingRecord) }
            records[index] = record
        } else {
            records.append(record)
        }
        return try replacing(list, with: records, kind: kind, in: files)
    }
    private func replacing<Record: PendingMoneyWrite>(_ list: WritableKeyPath<PendingMoneyLedger, [Record]>, with records: [Record],
                                                      kind: PendingMoneyKind, in files: PendingMoneyFiles) throws -> PendingMoneyLedger {
        guard isAvailable(kind) else { throw PendingMoneyError(kind: kind, reason: .paused) }
        do { try files.persist(records, to: kind) } catch { throw PendingMoneyError(kind: kind, reason: .unsaved) }
        var next = self
        next[keyPath: list] = records
        return next
    }
    private func reading(_ kinds: [PendingMoneyKind], from files: PendingMoneyFiles) -> PendingMoneyLedger {
        var next = self
        for kind in kinds {
            do {
                switch kind {
                case .balance: next.balances = try files.read(kind, as: PendingBalanceOperation.self)
                case .redeemBatch: next.redeemBatches = try files.read(kind, as: PendingRedeemBatch.self)
                case .compensation: next.compensations = try files.read(kind, as: PendingCompensation.self)
                }
                next.unreadable.remove(kind)
            } catch {
                next.unreadable.insert(kind)
            }
        }
        return next
    }
}
