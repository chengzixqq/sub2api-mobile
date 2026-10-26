import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 00 §2.5.5, §9.8 (a money write that cannot be saved is not sent), D16.

/// A fresh directory per test (removed by the test's `defer`); file protection is off because macOS test volumes may not
/// support it.
private struct Scratch {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pending-money-\(UUID().uuidString)", isDirectory: true)
    var files: PendingMoneyFiles { PendingMoneyFiles(directory: directory, protectsFiles: false) }
    func url(_ kind: PendingMoneyKind) -> URL { directory.appendingPathComponent(PendingMoneyFiles.fileName(for: kind)) }
    func bytes(_ kind: PendingMoneyKind) -> Data? { try? Data(contentsOf: url(kind)) }
    func write(_ text: String, to kind: PendingMoneyKind) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(kind))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let site = UUID(uuidString: "5B6C7D8E-9F0A-4B1C-8D2E-3F4A5B6C7D8E")!
private func balance(_ amount: Decimal = 50, serverID: UUID = site, createdAt: Date = Date(timeIntervalSince1970: 1_800_000_100)) -> PendingBalanceOperation {
    PendingBalanceOperation(serverID: serverID, userID: 42, amount: amount, operation: .add, notes: "补偿", actorUserID: 7, createdAt: createdAt,
                            userDisplayName: "王小明", userEmail: "wang@example.invalid")
}
private func batch(serverID: UUID = site, createdAt: Date = Date(timeIntervalSince1970: 1_800_000_200)) -> PendingRedeemBatch {
    PendingRedeemBatch(serverID: serverID, actorUserID: 7, createdAt: createdAt, spec: RedeemGenerateSpec(type: .balance, value: 10, count: 20, notes: "活动"))
}
private func grant(serverID: UUID = site, createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> PendingCompensation {
    PendingCompensation(serverID: serverID, actorUserID: 7, createdAt: createdAt, userID: 42, userDisplayName: "王小明", userEmail: "wang@example.invalid",
                        code: "0123456789abcdef0123456789abcdef", type: .balance, value: 10)
}
private func pendingError(_ operation: () throws -> Void) -> PendingMoneyError? {
    do { try operation(); return nil } catch { return error as? PendingMoneyError }
}

@Test func eachKindPersistsToItsOwnFile() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    let ledger = try PendingMoneyLedger().remembering(balance(), in: files).remembering(batch(), in: files).remembering(grant(), in: files)
    for kind in PendingMoneyKind.allCases { #expect(scratch.bytes(kind) != nil) }
    #expect(PendingMoneyFiles.fileName(for: .balance) == "pending-balances.json")
    #expect(PendingMoneyFiles.fileName(for: .redeemBatch) == "pending-redeem-batches.json")
    #expect(PendingMoneyFiles.fileName(for: .compensation) == "pending-compensations.json")
    let loaded = PendingMoneyLedger.load(from: files)
    #expect(loaded.balances == ledger.balances); #expect(loaded.redeemBatches == ledger.redeemBatches); #expect(loaded.compensations == ledger.compensations)
    #expect(loaded.unreadable.isEmpty)
}

@Test func corruptFilePausesOnlyThatKindAndIsNeverOverwritten() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    try scratch.write("not json", to: .redeemBatch)
    let ledger = PendingMoneyLedger.load(from: files)
    #expect(ledger.unreadable == [.redeemBatch]); #expect(!ledger.isAvailable(.redeemBatch)); #expect(ledger.isAvailable(.balance))
    #expect(ledger.unreadableNotice == PendingMoneyKind.redeemBatch.unreadableMessage)
    #expect(pendingError { _ = try ledger.remembering(batch(), in: files) } == PendingMoneyError(kind: .redeemBatch, reason: .paused))
    #expect(try ledger.resolving(id: UUID(), in: files).unreadable == [.redeemBatch])
    let updated = try ledger.remembering(balance(), in: files).remembering(grant(), in: files)
    #expect(updated.balances.count == 1); #expect(updated.compensations.count == 1)
    #expect(scratch.bytes(.redeemBatch) == Data("not json".utf8))
    // A site may have records in the unreadable file, so its id is not reused (D17).
    #expect(updated.mayHaveRecords(serverID: UUID()))
}

@Test func unwritableDirectoryRejectsRememberAndKeepsLedger() throws {
    let scratch = Scratch()
    defer { scratch.remove() }
    try scratch.write("{}", to: .balance)
    let blocked = PendingMoneyFiles(directory: scratch.url(.balance), protectsFiles: false)
    let ledger = PendingMoneyLedger()
    for kind in PendingMoneyKind.allCases {
        let error = pendingError {
            switch kind {
            case .balance: _ = try ledger.remembering(balance(), in: blocked)
            case .redeemBatch: _ = try ledger.remembering(batch(), in: blocked)
            case .compensation: _ = try ledger.remembering(grant(), in: blocked)
            }
        }
        #expect(error == PendingMoneyError(kind: kind, reason: .unsaved))
        #expect(error?.errorDescription == kind.unsavedMessage)
    }
    #expect(ledger.writes(serverID: nil).isEmpty)
}

@Test func legacyBalanceFileLoadsAndSurvivesRewrite() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    let id = UUID()
    try scratch.write(#"[{"id":"\#(id.uuidString)","serverID":"\#(site.uuidString)","userID":42,"amount":12.5,"operation":"add","notes":"旧"}]"#, to: .balance)
    let loaded = PendingMoneyLedger.load(from: files)
    let old = try #require(loaded.balances.first)
    #expect(old.isLegacy); #expect(old.summary.createdAt == nil)
    let body = try old.requestBody()
    _ = try loaded.remembering(balance(), in: files)
    let reloaded = try #require(PendingMoneyLedger.load(from: files).balances.first { $0.id == id })
    #expect(reloaded.isLegacy); #expect(reloaded.summary.createdAt == nil); #expect(reloaded.userEmail == nil)
    #expect(try reloaded.requestBody() == body)
}

@Test func currentRecordsRoundTripThroughDefaultCoding() throws {
    let scratch = Scratch()
    defer { scratch.remove() }
    let record = balance().with(actionID: UUID())
    try scratch.write(String(decoding: try JSONEncoder().encode([record]), as: UTF8.self), to: .balance)
    #expect(PendingMoneyLedger.load(from: scratch.files).balances == [record])
}

@Test func rememberUpsertsMetadataButRejectsChangedBody() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    let original = balance()
    let ledger = try PendingMoneyLedger().remembering(original, in: files)
    let withAction = original.with(actionID: UUID())
    let updated = try ledger.remembering(withAction, in: files)
    #expect(updated.balances == [withAction])
    #expect(PendingMoneyLedger.load(from: files).balances == [withAction])

    let changed = PendingBalanceOperation(id: original.id, serverID: site, userID: 42, amount: 60, operation: .add, notes: "补偿", actorUserID: 7)
    let before = scratch.bytes(.balance)
    #expect(pendingError { _ = try updated.remembering(changed, in: files) } == PendingMoneyError(kind: .balance, reason: .conflictingRecord))
    #expect(scratch.bytes(.balance) == before)
    #expect(updated.balances == [withAction])
}

@Test func resolveAndWritesAcrossKinds() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    let other = UUID()
    let old = try JSONDecoder().decode(PendingBalanceOperation.self, from: Data(
        #"{"id":"\#(UUID().uuidString)","serverID":"\#(site.uuidString)","userID":42,"amount":"1","operation":"add","notes":""}"#.utf8))
    let first = grant(), second = balance(), third = batch(), elsewhere = balance(serverID: other)
    let ledger = try PendingMoneyLedger().remembering(second, in: files).remembering(third, in: files).remembering(first, in: files)
        .remembering(old, in: files).remembering(elsewhere, in: files)
    #expect(ledger.writes(serverID: site).map(\.id) == [old.id, first.id, second.id, third.id])
    #expect(ledger.writes(serverID: other).map(\.id) == [elsewhere.id])
    #expect(ledger.writes(serverID: nil).count == 5)
    let found = ledger.record(id: third.id) as? PendingRedeemBatch
    #expect(found == third)
    #expect(ledger.mayHaveRecords(serverID: other)); #expect(!ledger.mayHaveRecords(serverID: UUID()))

    let untouched = scratch.bytes(.balance)
    let resolved = try ledger.resolving(id: third.id, in: files).resolving(id: first.id, in: files)
    #expect(resolved.redeemBatches.isEmpty); #expect(resolved.compensations.isEmpty)
    #expect(scratch.bytes(.balance) == untouched)
    #expect(PendingMoneyLedger.load(from: files).writes(serverID: site).map(\.id) == [old.id, second.id])
    let unchanged = try resolved.resolving(id: UUID(), in: files)
    #expect(unchanged.writes(serverID: nil).count == 3)
    let cleared = try resolved.resolving(id: elsewhere.id, in: files)
    #expect(!cleared.mayHaveRecords(serverID: other))
}

@Test func reloadingUnreadableRecoversAfterRepair() throws {
    let scratch = Scratch(), files = scratch.files
    defer { scratch.remove() }
    try scratch.write("[{", to: .compensation)
    try scratch.write("[{", to: .redeemBatch)
    let ledger = try PendingMoneyLedger.load(from: files).remembering(balance(), in: files)
    #expect(ledger.unreadable == [.redeemBatch, .compensation])
    #expect(ledger.unreadableNotice == PendingMoneyKind.redeemBatch.unreadableMessage + "\n" + PendingMoneyKind.compensation.unreadableMessage)
    #expect(ledger.reloadingUnreadable(from: files).unreadable == [.redeemBatch, .compensation])
    let saved = grant()
    try scratch.write(String(decoding: try JSONEncoder().encode([saved]), as: UTF8.self), to: .compensation)
    try scratch.write("[]", to: .balance)
    let recovered = ledger.reloadingUnreadable(from: files)
    #expect(recovered.unreadable == [.redeemBatch]); #expect(recovered.compensations == [saved])
    // The launch notice shrinks to what is still unreadable, and goes once every file reads (a launch while locked).
    #expect(recovered.unreadableNotice == PendingMoneyKind.redeemBatch.unreadableMessage)
    // Readable kinds keep what is in memory; only the unreadable file was read again.
    #expect(recovered.balances == ledger.balances)
    try scratch.write("[]", to: .redeemBatch)
    let readable = recovered.reloadingUnreadable(from: files)
    #expect(readable.unreadable.isEmpty); #expect(readable.unreadableNotice == nil)
}

@Test func memoryOnlyAndProductionFiles() throws {
    let memory = try PendingMoneyLedger().remembering(balance(), in: .memoryOnly).remembering(batch(), in: .memoryOnly)
    #expect(memory.writes(serverID: site).count == 2)
    #expect(PendingMoneyFiles.memoryOnly.url(for: .balance) == nil)
    #expect(try memory.resolving(id: memory.balances[0].id, in: .memoryOnly).balances.isEmpty)
    #expect(PendingMoneyLedger.load(from: .memoryOnly).writes(serverID: nil).isEmpty)
    let production = PendingMoneyFiles.applicationSupport()
    #expect(production.protectsFiles)
    #expect(production.directory?.lastPathComponent == "Sub2Mobile")
    // Written atomically with complete protection; the test scratch files only atomically.
    #expect(production.writeOptions == [.atomic, .completeFileProtection])
    #expect(PendingMoneyFiles(directory: production.directory, protectsFiles: false).writeOptions == [.atomic])
}

/// Redeem codes and e-mails stay on this device: the directory is excluded from iCloud and computer backups (a restored
/// record has no credential to retry with anyway).
@Test func pendingMoneyDirectoryIsExcludedFromBackup() throws {
    let scratch = Scratch()
    defer { scratch.remove() }
    let ledger = try PendingMoneyLedger().remembering(balance(), in: scratch.files)
    #expect(ledger.balances.count == 1)
    let values = try scratch.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
}
