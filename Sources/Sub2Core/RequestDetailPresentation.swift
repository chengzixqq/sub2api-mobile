import Foundation

/// The three looks of the request detail (40 §7.1).
public enum RequestDetailStyle: Sendable, Equatable {
    case success
    /// An upstream error the retry recovered: the client got a status below 400.
    case recovered
    case failed
}

/// Which `UsageRequestType` name to use: `title` in lists, `detailTitle` in the detail's “方式” row.
public enum RequestTypeContext: Sendable { case list, detail }

/// The head card's status row (40 §7.3): word, code badge with its tone, and the left capsule (failed look only).
public struct RequestStatusLine: Sendable, Equatable {
    public let label: String
    /// A status code; “鉴权” / “恢复” for a recovered row without one (40 §6.3); “—” when missing.
    public let badge: String
    public let tone: Tone
    public let capsule: Tone?
}

public struct RequestCostCell: Sendable, Equatable {
    public let label: String
    public let value: String
}

/// The timing section (40 §7.3).
public struct RequestTiming: Sendable, Equatable {
    public let firstToken: String
    public let total: String
    /// The total is the sum of the recorded phases and reads “约 3.2s”.
    public let isEstimated: Bool
    /// The first token's part of the bar, at least `minimumFirstTokenShare`; nil draws the total bar only.
    public let firstTokenShare: Double?
}

/// The request detail's rules and wording (40 §0.4, §7.1–§7.3), shared by S4-08 and S4-08b. A `kind` of nil means the
/// usage record (the success look); times follow the site's zone.
public enum RequestDetailPresentation {
    public static let minimumFirstTokenShare = 0.04

    public static func style(kind: ErrorLogKind?, statusCode: Int?) -> RequestDetailStyle {
        guard let kind else { return .success }
        guard kind == .upstream, let statusCode, (100..<400).contains(statusCode) else { return .failed }
        return .recovered
    }
    public static func title(kind: ErrorLogKind?) -> String {
        switch kind {
        case nil: "请求详情"
        case .request?: "失败请求"
        case .upstream?: "上游错误"
        }
    }
    public static func sourceName(kind: ErrorLogKind?) -> String {
        switch kind {
        case nil: "用量明细"
        case .request?: "错误请求"
        case .upstream?: "上游错误"
        }
    }
    /// “10/16 09:41:07 · 错误请求”.
    public static func subtitle(createdAt: Date?, kind: ErrorLogKind?, timeZone: TimeZone) -> String {
        (createdAt.map { stamp($0, timeZone: timeZone, seconds: true) } ?? DisplayFormat.missing) + " · " + sourceName(kind: kind)
    }

    // MARK: Names (40 §0.4): unknown values are shown as they are.

    public static func phaseName(_ raw: String?) -> String? { trimmed(raw).map { phaseNames[$0] ?? $0 } }
    public static func ownerName(_ raw: String?) -> String? { trimmed(raw).map { ownerNames[$0] ?? $0 } }
    /// “上游 · 上游服务商 · P1”; missing parts are left out.
    public static func causeLine(_ record: RequestErrorRecord) -> String? {
        let parts = [phaseName(record.phase), ownerName(record.errorOwner), trimmed(record.severity)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    /// `admin/usage` names; nil, empty, `unknown` and values this build does not know are “—”.
    public static func requestTypeName(_ raw: String?, context: RequestTypeContext) -> String {
        name(raw.flatMap(UsageRequestType.init(rawValue:)), context: context)
    }
    /// Ops rows: the number 1–5 when it is known, else `stream` (流式 / 非流式 in the detail).
    public static func requestTypeName(code: Int16?, stream: Bool?, context: RequestTypeContext) -> String {
        name(code.flatMap(UsageRequestType.init(code:)) ?? stream.map { $0 ? .stream : .sync }, context: context)
    }

    // MARK: Head card

    public static let successStatusLine = RequestStatusLine(label: "成功", badge: "200", tone: .ok, capsule: nil)
    /// Recovered: the detail's upstream code, else the code parsed from the list row. Failed: the chain's client code, else
    /// `status_code`; a business limit is grey (40 §0.4) and a missing code is “—”.
    public static func errorStatusLine(record: RequestErrorRecord, kind: ErrorLogKind, detail: RequestErrorDetail?, clientStatusCode: Int?) -> RequestStatusLine {
        guard style(kind: kind, statusCode: record.statusCode) != .recovered else {
            let upstream = validCode(detail?.upstreamStatusCode ?? record.upstreamStatusCode).map(UpstreamErrorStatus.code) ?? record.upstreamStatus
            return switch upstream {
            case .code(let code): RequestStatusLine(label: "上游失败", badge: String(code), tone: Tone.httpStatus(code), capsule: nil)
            case .accountAuth: RequestStatusLine(label: "上游失败", badge: "鉴权", tone: .neutral, capsule: nil)
            case .unknown: RequestStatusLine(label: "上游失败", badge: "恢复", tone: .neutral, capsule: nil)
            }
        }
        let code = validCode(clientStatusCode ?? record.statusCode)
        let tone: Tone = detail?.isBusinessLimited == true ? .neutral : Tone.httpStatus(code)
        return RequestStatusLine(label: "失败", badge: code.map(String.init) ?? DisplayFormat.missing, tone: tone, capsule: tone)
    }
    public static func recoveryNote(_ record: RequestErrorRecord) -> String { "已自动重试成功，客户端收到 \(record.statusCode)" }
    /// `upstream_error_message` ?? `message`, both redacted when decoded.
    public static func errorMessage(record: RequestErrorRecord, detail: RequestErrorDetail?) -> String {
        [detail?.upstreamErrorMessage, record.upstreamMessage, record.message].compactMap { $0 }.first { trimmed($0) != nil } ?? "上游返回错误"
    }
    /// Shown only when it differs from the model.
    public static func upstreamModel(model: String, upstream: String?) -> String? {
        guard let upstream = trimmed(upstream), upstream != model else { return nil }
        return upstream
    }
    /// Success look: 实际扣费 / 账号成本 / 标准 with four digits; a follower of a merged probe has no account cost.
    public static func costCells(_ usage: UsageRequestRecord) -> [RequestCostCell] {
        let accountCost = usage.providerCostRecorded == false ? 0 : usage.accountCost
        return [("实际扣费", usage.actualCost), ("账号成本", accountCost), ("标准", usage.standardCost)]
            .map { RequestCostCell(label: $0.0, value: DisplayFormat.money($0.1, digits: 4)) }
    }
    public static func followerCostNote(_ usage: UsageRequestRecord) -> String? {
        usage.providerCostRecorded == false ? "合并探测的跟随请求，没有上游成本" : nil
    }
    /// “已处理 · 值班 · 10/16 09:52” under the buttons, once the detail has `resolved_at`.
    public static func resolvedNote(_ record: RequestErrorRecord, timeZone: TimeZone) -> String? {
        guard record.resolved, let at = record.resolvedAt else { return nil }
        return (["已处理", record.resolvedByUserName].compactMap { $0 } + [stamp(at, timeZone: timeZone, seconds: false)]).joined(separator: " · ")
    }

    // MARK: Timing

    public static func timing(_ usage: UsageRequestRecord) -> RequestTiming {
        timing(firstTokenMs: usage.firstTokenMs, durationMs: usage.durationMs)
    }
    /// `record` may be the list row, which has no phase latencies; they come from the detail once it arrives.
    public static func timing(_ record: RequestErrorRecord, detail: RequestErrorDetail?) -> RequestTiming {
        timing(firstTokenMs: record.firstTokenMs, durationMs: record.durationMs,
               phases: [detail?.authLatencyMs, detail?.routingLatencyMs, detail?.upstreamLatencyMs ?? record.upstreamLatencyMs,
                        detail?.responseLatencyMs ?? record.responseLatencyMs])
    }
    /// Without `duration_ms` the total is the sum of the recorded phases (auth + routing + upstream + response), marked “约”.
    public static func timing(firstTokenMs: Int?, durationMs: Int?, phases: [Int?] = []) -> RequestTiming {
        let recorded = phases.compactMap { $0 }.filter { $0 >= 0 }
        let total = durationMs ?? (recorded.isEmpty ? nil : recorded.reduce(0, +))
        let isEstimated = durationMs == nil && total != nil
        var share: Double?
        if let firstTokenMs, let total, total > 0 {
            share = min(1, max(minimumFirstTokenShare, Double(firstTokenMs) / Double(total)))
        }
        return RequestTiming(firstToken: DisplayFormat.duration(firstTokenMs, style: .list), total: (isEstimated ? "约 " : "") + DisplayFormat.duration(total, style: .list),
                             isEstimated: isEstimated, firstTokenShare: share)
    }
}

extension RequestDetailPresentation {
    static let phaseNames = ["request": "请求校验", "auth": "鉴权", "account_auth": "账号鉴权", "routing": "路由", "upstream": "上游",
                             "network": "网络", "internal": "网关内部"]
    static let ownerNames = ["client": "客户端", "provider": "上游服务商", "platform": "平台配置"]

    static func name(_ type: UsageRequestType?, context: RequestTypeContext) -> String {
        guard let type else { return DisplayFormat.missing }
        return context == .list ? type.title : type.detailTitle
    }
    static func validCode(_ code: Int?) -> Int? { code.flatMap { (100...599).contains($0) ? $0 : nil } }
    static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
    /// “10/16 09:41:07”, or “10/16 09:52” without seconds.
    static func stamp(_ date: Date, timeZone: TimeZone, seconds: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        let clock = ([parts.hour, parts.minute] + (seconds ? [parts.second] : [])).map { value in
            let number = value ?? 0
            return number < 10 ? "0\(number)" : String(number)
        }
        return "\(parts.month ?? 0)/\(parts.day ?? 0) " + clock.joined(separator: ":")
    }
}
