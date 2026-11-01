import Foundation
import Observation
import Sub2Core

/// The push page's endpoints (60 §7.2): the site's client, or the `-ui-testing` PushDemoStore. Registering comes from
/// PushDeviceAPI, so S6-25's add sheet uses the same source.
protocol PushSettingsSource: PushDeviceAPI {
    func pushDevices() async throws -> [PushDevice]
    func pushConfig() async throws -> PushAPNsConfig
    func updatePushSubscription(id: Int, _ subscription: PushSubscription) async throws -> PushDevice
    func testPushDevice(id: Int) async throws -> PushTestResult
}
extension APIClient: PushSettingsSource {}

enum PushDeleteOutcome: Equatable, Sendable {
    /// Deleted, already gone, or not in the list read back.
    case deleted
    /// Still there; the reason is shown.
    case failed
    /// Neither the DELETE's answer nor the list read back; said so.
    case unconfirmed
    /// Another delete running, the session ended, or cancelled.
    case ignored
}

/// 60 §7 (S6-24): the caller's push targets and the site's APNs settings, read together on entry, on a pull and back in
/// the foreground (7.6). A subscription change shows at once and is sent as a whole; edits made while one is out go in
/// one more PUT, and a failure goes back to the last confirmed value (7.4). Writes are sent once (R06); a lost DELETE is read
/// back, never resent. Answers of an older read or session are dropped.
@MainActor @Observable
final class PushSettingsModel {
    private(set) var devices: BlockState<[PushDevice]> = .idle
    private(set) var config: BlockState<PushAPNsConfig> = .idle
    private(set) var testingID: Int?
    private(set) var deletingID: Int?
    /// Shown but not yet confirmed by the server's echo.
    private(set) var pendingSubscriptions: [Int: PushSubscription] = [:]
    private(set) var savingIDs: Set<Int> = []
    let source: any PushSettingsSource

    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var devicesTicket = UUID()
    @ObservationIgnored private var configTicket = UUID()
    /// Echoes and removals while a list read is out, laid over its answer.
    @ObservationIgnored private var editsDuringLoad: [Edit] = []
    private enum Edit { case replace(PushDevice), remove(Int) }

    init(source: any PushSettingsSource, receipts: ReceiptCenter, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.source = source; self.receipts = receipts; self.isCurrent = isCurrent; self.now = now
    }

    // MARK: Reading

    var deviceList: [PushDevice]? { devices.value }
    /// 7.5: no list at all; the local and other sections each offer “加载失败 · 重试”.
    var listFailed: Bool { devices.value == nil && devices.failureReason != nil }
    /// 00 §4.6: an older list stays under “刷新失败 · 重试”.
    var refreshFailed: Bool { devices.value != nil && devices.failureReason != nil }
    /// nil while unread, refused (403) or failed: no APNs section and no banner, and the switch stays usable (7.5).
    var shownConfig: PushAPNsConfig? { config.value }
    /// The first read of the settings is out: the switch waits for it.
    var isConfigPending: Bool { config.value == nil && config.isLoading }
    var showsNotReadyBanner: Bool { PushPresentation.showsNotReadyBanner(shownConfig) }
    func device(id: Int) -> PushDevice? { deviceList?.first { $0.id == id } }
    func subscription(for id: Int) -> PushSubscription? { pendingSubscriptions[id] ?? device(id: id)?.effectiveSubscription }
    func isSavingSubscription(id: Int) -> Bool { savingIDs.contains(id) }

    func load() async {
        async let deviceRead: Void = reloadDevices()
        async let configRead: Void = reloadConfig()
        _ = await (deviceRead, configRead)
    }
    func reloadDevices() async {
        guard isCurrent() else { return }
        let ticket = UUID(), source = source
        devicesTicket = ticket; editsDuringLoad = []
        devices = devices.withLoading()
        let result = await Self.result { try await source.pushDevices() }
        guard devicesTicket == ticket, isCurrent() else { return }
        switch result {
        case .success(let list): devices = .loaded(editsDuringLoad.reduce(Self.ordered(list), Self.applying), at: now())
        case .failure(let error) where error is CancellationError: devices = devices.withCancelledLoad()
        case .failure(let error): devices = devices.withFailure(error.localizedDescription)
        }
        editsDuringLoad = []
    }
    func reloadConfig() async {
        guard isCurrent() else { return }
        let ticket = UUID(), source = source
        configTicket = ticket
        config = config.withLoading()
        let result = await Self.result { try await source.pushConfig() }
        guard configTicket == ticket, isCurrent() else { return }
        switch result {
        case .success(let value): config = .loaded(value, at: now())
        case .failure(let error) where error is CancellationError: config = config.withCancelledLoad()
        case .failure(let error): config = config.withFailure(error.localizedDescription)
        }
    }

    // MARK: Local changes

    /// A server's answer for one target: replaced, or inserted in id order.
    func replace(_ device: PushDevice) { apply(.replace(device)) }
    func remove(id: Int) { apply(.remove(id)) }
    /// S6-25's saved APNs settings: the banner and section follow at once.
    func replaceConfig(_ value: PushAPNsConfig) {
        configTicket = UUID()
        config = .loaded(value, at: now())
    }

    // MARK: Writes (7.4)

    func updateSubscription(id: Int, to subscription: PushSubscription) async {
        pendingSubscriptions[id] = subscription
        guard !savingIDs.contains(id) else { return }
        savingIDs.insert(id)
        defer { savingIDs.remove(id) }
        while let next = pendingSubscriptions[id] {
            guard let device = device(id: id), next.normalized != device.effectiveSubscription.normalized else {
                pendingSubscriptions[id] = nil
                return
            }
            do {
                let echo = try await source.updatePushSubscription(id: id, next)
                guard isCurrent() else { return }
                replace(echo)
                if pendingSubscriptions[id] == next { pendingSubscriptions[id] = nil }
            } catch {
                guard isCurrent() else { return }
                pendingSubscriptions[id] = nil
                await subscriptionFailed(error, id: id)
                // An edit made while the failure read the list back goes in the next PUT.
                guard isCurrent() else { return }
            }
        }
    }

    /// One test at a time; a second tap while one runs sends nothing.
    func test(id: Int) async -> PushTestOutcome {
        guard testingID == nil, isCurrent() else { return .cancelled }
        testingID = id
        let outcome: PushTestOutcome
        do {
            _ = try await source.testPushDevice(id: id)
            outcome = .sent
        } catch {
            outcome = PushTestOutcome.classify(error)
        }
        testingID = nil
        guard isCurrent() else { return .cancelled }
        switch outcome {
        case .sent:
            receipts.show(Receipt(text: PushPresentation.testSent, systemImage: "bell.badge"))
            await reloadDevices()
        case .refused(let text):
            showFailure(text)
            await reloadDevices()
        case .gone:
            remove(id: id)
            await reloadDevices()
        case .failed(let text): showFailure(text)
        case .cancelled: break
        }
        // A read back that outlasts the session: `.gone` would make the caller forget the next site's device.
        return isCurrent() ? outcome : .cancelled
    }

    /// The deleted receipt is the page's (DeleteConfirmationCopy.deletedReceipt), shown as it pops.
    func delete(id: Int) async -> PushDeleteOutcome {
        guard deletingID == nil, isCurrent() else { return .ignored }
        deletingID = id
        defer { deletingID = nil }
        do {
            try await source.deletePushDevice(id: id)
        } catch {
            guard isCurrent() else { return .ignored }
            switch PushWriteFailure.classify(error) {
            case .gone: break
            case .cancelled: return .ignored
            case .reconfirm(let text): showFailure(text, tone: .caution); return .ignored
            case .rejected(let text): showFailure(PushPresentation.deleteFailed(reason: text)); return .failed
            case .unconfirmed: return await readBack(deleted: id, after: error)
            }
        }
        guard isCurrent() else { return .ignored }
        remove(id: id)
        return .deleted
    }

    // MARK: Internals

    private func subscriptionFailed(_ error: any Error, id: Int) async {
        switch PushWriteFailure.classify(error) {
        case .cancelled: return
        case .gone:
            remove(id: id)
            await reloadDevices()
        case .unconfirmed:
            showFailure(PushPresentation.subscriptionNotSaved(reason: PushPresentation.failureMessage(error)))
            await reloadDevices()
        case .rejected(let text): showFailure(PushPresentation.subscriptionNotSaved(reason: text))
        case .reconfirm(let text): showFailure(PushPresentation.subscriptionNotSaved(reason: text), tone: .caution)
        }
    }

    /// The list says whether the lost DELETE went through.
    private func readBack(deleted id: Int, after error: any Error) async -> PushDeleteOutcome {
        let source = source
        let result = await Self.result { try await source.pushDevices() }
        guard isCurrent() else { return .ignored }
        guard case .success(let list) = result else {
            showFailure(PushPresentation.deleteUnconfirmed, tone: .caution)
            return .unconfirmed
        }
        devicesTicket = UUID(); editsDuringLoad = []
        devices = .loaded(Self.ordered(list), at: now())
        guard list.contains(where: { $0.id == id }) else { return .deleted }
        showFailure(PushPresentation.deleteFailed(reason: PushPresentation.failureMessage(error)))
        return .failed
    }

    private func showFailure(_ text: String, tone: Tone = .critical) {
        receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: tone))
    }
    private func apply(_ edit: Edit) {
        if devices.isLoading { editsDuringLoad.append(edit) }
        devices = devices.updatingValue { Self.applying($0, edit) }
    }
    private nonisolated static func applying(_ list: [PushDevice], _ edit: Edit) -> [PushDevice] {
        switch edit {
        case .replace(let device): ordered(list.filter { $0.id != device.id } + [device])
        case .remove(let id): list.filter { $0.id != id }
        }
    }
    private nonisolated static func ordered(_ list: [PushDevice]) -> [PushDevice] { list.sorted { $0.id < $1.id } }
    private nonisolated static func result<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
