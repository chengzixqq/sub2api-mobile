import Foundation

// 60 §14.4 (S6-14): the add's key, how a save failed, and the sheet's words.

/// R05: the add's Idempotency-Key is made when 添加 is tapped. The same form again (a retry) keeps the key and the very bytes,
/// expires_at included; a changed form gets a new key.
public struct ProxyAddAttempt: Sendable, Equatable {
    /// How much earlier than `madeAt` the server's `created_at` may read: its clock against the corrected one.
    public static let clockSlack: TimeInterval = 15

    public let key: UUID
    public let draft: ProxyEditDraft
    public let request: ProxyCreateRequest
    /// When 添加 made the key, on the server-corrected clock.
    public let madeAt: Date
    /// The proxies listed then: none of them is this add.
    public let existing: Set<Int>

    /// Throws the form's own error before anything is sent.
    public static func next(previous: ProxyAddAttempt?, draft: ProxyEditDraft, now: Date, existing: Set<Int> = [],
                            makeKey: () -> UUID = { UUID() }) throws -> ProxyAddAttempt {
        if let previous, previous.draft == draft { return previous }
        return ProxyAddAttempt(key: makeKey(), draft: draft, request: try draft.createRequest(now: now), madeAt: now, existing: existing)
    }

    /// 00 §2.5.4 核对: the row this add made. Names are not unique, so a row listed before 添加 or created before it is someone
    /// else's; the rest must carry what was sent, as the server trims it (the password is not compared).
    public func matches(_ proxy: AdminProxy) -> Bool {
        guard !existing.contains(proxy.id), let created = proxy.createdAt, created >= madeAt.addingTimeInterval(-Self.clockSlack) else { return false }
        let trim = ProxyWriteCheck.trimmed
        return trim(proxy.name) == trim(request.name) && trim(proxy.scheme).lowercased() == trim(request.scheme)
            && trim(proxy.host) == trim(request.host) && proxy.port == request.port && trim(proxy.username ?? "") == trim(request.username)
            && (proxy.fallbackMode ?? ProxyFallbackMode.none.rawValue) == request.fallbackMode.rawValue
            && proxy.backupProxyID == request.backupProxyID && (proxy.expiryWarnDays ?? request.expiryWarnDays) == request.expiryWarnDays
    }
}

extension ProxyAddAttempt: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ProxyAddAttempt(key: \(key), request: \(request))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["key": key, "request": request.description], displayStyle: .struct) }
}

/// How an add or a save failed (00 §2.4, §2.5.4; R06, R11). Words come from the sheet or the catalog, never from the server.
public enum ProxyWriteFailure: Sendable, Equatable {
    case cancelled
    /// The server may have run it: the add offers the same key again, an edit reads the proxy back.
    case unconfirmed(retryNotBefore: Date?)
    case rejected(message: String, section: ProxyEditSection?)
    /// The add's key cannot be used again: the next 添加 makes a new one.
    case needsNewKey(message: String)
    /// 404 PROXY_NOT_FOUND with no backup sent: the proxy itself is gone.
    case gone
    /// 404 PROXY_NOT_FOUND with a backup sent: the backup, or on an edit possibly the proxy itself, which is read to tell.
    case backupGone

    public static func classify(_ error: any Error, sentBackup: Bool) -> ProxyWriteFailure {
        if error is CancellationError { return .cancelled }
        if let keyed = error as? KeyedWriteFailure {
            switch keyed.disposition {
            case .unconfirmed(_, let notBefore): return .unconfirmed(retryNotBefore: notBefore)
            case .needsNewKey: return .needsNewKey(message: keyed.localizedDescription)
            }
        }
        guard let api = error as? APIError else { return .rejected(message: error.localizedDescription, section: nil) }
        if api.securityOutcome == .cancelled { return .cancelled }
        if api.statusCode == 404, api.reason == ProxyReason.notFound { return sentBackup ? .backupGone : .gone }
        switch api.reason {
        case ProxyReason.backupRequired?: return .rejected(message: ProxyEditCopy.backupRequired, section: .fallback)
        case ProxyReason.backupSelf?: return .rejected(message: ProxyEditCopy.backupSelf, section: .fallback)
        default: break
        }
        // A refresh that failed before sending was never sent.
        guard api != .refreshDeferred else { return .rejected(message: api.localizedDescription, section: nil) }
        guard let status = api.statusCode else {
            let unknown = api.kind == .transport || api == .invalidResponse
            return unknown ? .unconfirmed(retryNotBefore: nil) : .rejected(message: api.localizedDescription, section: nil)
        }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed(retryNotBefore: nil)
            : .rejected(message: api.localizedDescription, section: nil)
    }
}

/// The sheet's words (60 §14.3–§14.4).
public enum ProxyEditCopy {
    public static let namePlaceholder = "请输入代理名称", hostPlaceholder = "请输入主机地址", portPlaceholder = "请输入端口"
    public static let usernamePlaceholder = "请输入用户名", passwordPlaceholder = "请输入密码", keepPasswordPlaceholder = "留空保持不变"
    public static let customDaysPlaceholder = "自定义天数", warnDaysLabel = "到期提醒提前", backupLabel = "备用代理"
    public static let socks5hFootnote = "SOCKS5H 由代理服务器解析域名（远程 DNS）。"
    public static let expiryFootnote = "到期前按提醒天数在代理列表和告警里提示。"
    public static let lapsedKeepActive = "有效期已过，改回“正常”前先在上面选新的有效期。"
    public static let renewedStatus = "续期后状态改回“正常”。"
    public static let backupRequired = "选了备用代理回退，请选择一个备用代理"
    public static let backupSelf = "备用代理不能是它自己"
    public static let backupGone = "备用代理已不存在，请重新选择"
    public static let readBackMismatch = "服务器上的代理与这次修改不一致，可以重新保存"
    public static let notFoundYet = "还没找到这个代理，服务器可能仍在处理。"
    public static let added = "代理添加成功", updated = "代理更新成功"
    public static let saving = "正在保存…", confirming = "正在确认结果…", checking = "正在核对…"
    public static let reconcile = "核对", recheck = "再次核对", retrySame = "用同一编号重试"
    public static let discardTitle = "放弃修改？", discardConfirm = "放弃修改", keepEditing = "继续编辑"
    public static let unconfirmedCloseTitle = "结果未确认", keepChecking = "继续核对", checkLater = "稍后核对"
    public static let loading = "正在读取代理…", gone = "代理已删除"
    /// The fallback segments in the design's order.
    public static let fallbackOrder: [ProxyFallbackMode] = [.none, .direct, .proxy]

    public static func title(_ mode: ProxyFallbackMode) -> String {
        switch mode {
        case .none: "不回退"
        case .direct: "回退直连"
        case .proxy: "备用代理"
        }
    }
    public static func title(_ status: ProxyStatusChange) -> String { status == .active ? "正常" : "停用" }
    /// “10/13 已过期。选一个新的有效期来续期。”
    public static func renewFootnote(lapsedOn day: String?) -> String { (day.map { $0 + " " } ?? "") + "已过期。选一个新的有效期来续期。" }
    public static func fallbackFootnote(_ mode: ProxyFallbackMode) -> String {
        switch mode {
        case .proxy: "回退链会跳过停用或已过期的代理，所以它们不能选作备用。"
        case .direct: "到期后把在用的账号改为直连，可在账号详情里“恢复原代理”。"
        case .none: "到期后账号留在这个过期代理上，需要手动处理。"
        }
    }
    /// Kept lapsed and 停用: the server leaves an expired proxy expired (it takes no “expired” in a PUT), a stopped one stopped.
    public static func lapsedKeepIdle(stillExpired: Bool) -> String {
        "已过期的代理保存后仍是" + (stillExpired ? "已过期" : "停用") + "；选新的有效期即可续期。"
    }
    public static func inactiveFootnote(accountCount: Int) -> String {
        "停用后：账号编辑里选不到它，也不会被选作备用代理；"
            + (accountCount > 0 ? "正在用它的 \(accountCount) 个账号照常走这个代理，要更换请到账号编辑页。" : "已经在用它的账号照常走这个代理。")
    }
    public static func renewed(name: String) -> String { "已续期 · \(name) 恢复正常" }
    /// While a keyed add runs: transport retries, then the server still working on the same key.
    public static func savingText(_ event: KeyedWriteEvent?) -> String {
        switch event {
        case .confirming?: confirming
        case .waitingForServer(let seconds)?: "服务器仍在处理 · 已等待 \(seconds) 秒"
        case .actionID?, nil: saving
        }
    }
    /// 00 §2.5.4: closing with the result open lets go of the add's key; the catalog reads again.
    public static func unconfirmedCloseMessage(adding: Bool) -> String {
        adding ? "服务器可能已经添加了这个代理。关闭后不再保留这次的编号，代理列表会重新读取；再次添加前先在列表里核对，避免重复。"
            : "服务器可能已经保存了这次修改。关闭后代理列表会重新读取，再次修改前先在详情里核对。"
    }
    public static func undoFailed(inUse: Bool) -> String { undoFailed(reason: inUse ? "已有账号在用这个代理" : "请稍后再试") }
    public static func undoFailed(reason: String) -> String { "撤销没有成功：" + reason }
}
