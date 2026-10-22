import Foundation
import Synchronization

/// The site's time zone (00 §6.3). `identifier` goes out verbatim as `timezone=`; calendar math uses `timeZone`.
public struct ServerTimeZone: Equatable, Sendable {
    public let identifier: String
    public let timeZone: TimeZone
    public let rawUTCOffset: String?

    /// nil when the zone cannot be used. A name Apple does not know (the backend's uninitialised "Local") is still sent
    /// as-is, with `server_utc_offset` standing in for local math.
    public init?(identifier: String?, utcOffset: String?) {
        let name = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        // Go's "Local" is the server's own zone; Apple would read it as the phone's.
        let known = name == "Local" ? nil : TimeZone(identifier: name)
        guard let zone = known ?? Self.parseUTCOffset(utcOffset).flatMap(TimeZone.init(secondsFromGMT:)) else { return nil }
        self.init(identifier: name, timeZone: zone, rawUTCOffset: utcOffset)
    }
    private init(identifier: String, timeZone: TimeZone, rawUTCOffset: String?) {
        self.identifier = identifier; self.timeZone = timeZone; self.rawUTCOffset = rawUTCOffset
    }
    /// Until the site reports its zone; the time zone hints stay hidden because the offsets match.
    public static var device: ServerTimeZone { ServerTimeZone(identifier: TimeZone.current.identifier, timeZone: .current, rawUTCOffset: nil) }
    /// `/admin/me` first, then `settings/public`; nil means fall back to `.device`.
    public static func resolve(me: AdminMe?, publicSettings: PublicSettings?) -> ServerTimeZone? {
        if let me, let zone = ServerTimeZone(identifier: me.server.serverTimezone, utcOffset: me.server.serverUTCOffset) { return zone }
        guard let publicSettings else { return nil }
        return ServerTimeZone(identifier: publicSettings.serverTimezone, utcOffset: publicSettings.serverUTCOffset)
    }
    /// "+08:00" → 28800. The backend always writes a sign, two-digit hours and minutes.
    public static func parseUTCOffset(_ raw: String?) -> Int? {
        guard let raw, raw.range(of: #"^[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil,
              let hours = Int(raw.dropFirst().prefix(2)), let minutes = Int(raw.suffix(2)), hours <= 18, minutes < 60 else { return nil }
        let seconds = hours * 3_600 + minutes * 60
        return raw.hasPrefix("-") ? -seconds : seconds
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = timeZone
        return calendar
    }
    /// `yyyy-MM-dd` on the server's calendar with ASCII digits (00 §2.8).
    public func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public func dayQueryItems(from start: Date, to end: Date) -> [URLQueryItem] {
        [URLQueryItem(name: "start_date", value: dayString(start)), URLQueryItem(name: "end_date", value: dayString(end)),
         URLQueryItem(name: "timezone", value: identifier)]
    }
    /// From the same time `days` server days ago through today.
    public func lastDaysQueryItems(_ days: Int, now: Date) -> [URLQueryItem] {
        dayQueryItems(from: calendar.date(byAdding: .day, value: -days, to: now) ?? now, to: now)
    }
    public func monthToDateQueryItems(now: Date) -> [URLQueryItem] {
        dayQueryItems(from: calendar.dateInterval(of: .month, for: now)?.start ?? now, to: now)
    }

    /// "UTC+8", "UTC+5:30", "UTC−3" (U+2212), "UTC+0", taken at `date` so daylight saving is followed.
    public func offsetLabel(at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = abs(seconds) / 3_600, minutes = abs(seconds) % 3_600 / 60
        return "UTC" + (seconds < 0 ? "\u{2212}" : "+") + String(hours) + (minutes == 0 ? "" : String(format: ":%02d", minutes))
    }
    public func differsFromDevice(_ device: TimeZone, at date: Date) -> Bool {
        timeZone.secondsFromGMT(for: date) != device.secondsFromGMT(for: date)
    }
    /// Overview subtitle tail (10 §1).
    public func overviewSuffix(device: TimeZone, at date: Date) -> String? { hint(device, date) { "· 按 \($0)" } }
    /// Analytics range line and log subtitle tail (40 §0.2).
    public func siteTimeSuffix(device: TimeZone, at date: Date) -> String? { hint(device, date) { "（站点时间 \($0)）" } }
    /// Settings → site and credentials, and the account expiry picker footnote.
    public func settingsNote(device: TimeZone, at date: Date) -> String? { hint(device, date) { "时间按服务器时区（\($0)）显示" } }
    private func hint(_ device: TimeZone, _ date: Date, _ text: (String) -> String) -> String? {
        differsFromDevice(device, at: date) ? text(offsetLabel(at: date)) : nil
    }
}

/// 00 §6.4 parsing and §2.8 encoding. Every wire timestamp in Sub2Core goes through these.
public enum ServerTime {
    /// RFC3339 with or without fractional seconds and with any offset (Go writes up to nine digits; they are cut to milliseconds).
    public static func parseTimestamp(_ raw: String?) -> Date? { TimestampParser().date(raw) }
    /// Unix seconds; nil, 0 and negatives mean “not set” (an account saved as never expiring sends 0).
    public static func date(unixSeconds: Int64?) -> Date? {
        guard let unixSeconds, unixSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    }
    /// Always UTC `Z`: `URLQueryItem` leaves "+" unencoded and an offset would reach Go as a space.
    public static func utcTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
    /// The backend requires both or neither.
    public static func timeRangeItems(start: Date, end: Date) -> [URLQueryItem] {
        [URLQueryItem(name: "start_time", value: utcTimestamp(start)), URLQueryItem(name: "end_time", value: utcTimestamp(end))]
    }
    /// The `Date` response header (IMF-fixdate, always GMT).
    public static func parseHTTPDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw)
    }
    /// Trend buckets carry no offset: read them in the reply's `query.timezone`, else in the zone the request sent.
    public static func bucketTimeZone(reported: String?, requested: ServerTimeZone) -> TimeZone {
        guard let reported, !reported.isEmpty else { return requested.timeZone }
        if reported == requested.identifier { return requested.timeZone }
        return ServerTimeZone(identifier: reported, utcOffset: nil)?.timeZone ?? requested.timeZone
    }
}

/// Keeps its two formatters for many rows; create one per call, never share it between tasks.
struct TimestampParser {
    private let plain = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let range = raw.range(of: #"\.\d+"#, options: .regularExpression) else { return plain.date(from: raw) }
        let millis = String((raw[range].dropFirst() + "000").prefix(3))
        return fractional.date(from: raw.replacingCharacters(in: range, with: "." + millis))
    }
}

/// The reply's `query` block (00 §4.1); every field may be missing or malformed.
public struct QueryMetadata: Decodable, Sendable {
    public let timezone: String?
    public let startTime: Date?
    public let endTime: Date?
    public let generatedAt: Date?
    enum CodingKeys: String, CodingKey { case timezone, startTime = "start_time", endTime = "end_time", generatedAt = "generated_at" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try? c.decodeIfPresent(String.self, forKey: .timezone)
        startTime = try c.optionalTimestamp(.startTime); endTime = try c.optionalTimestamp(.endTime)
        generatedAt = try c.optionalTimestamp(.generatedAt)
    }
}

/// One server timestamp and when it arrived: a block such as `runtime/batch` counts down from its own `sampled_at`.
public struct ClockSample: Equatable, Sendable {
    public let serverTime: Date
    public let localTime: Date
    public var offset: TimeInterval { serverTime.timeIntervalSince(localTime) }
    public func serverNow(localNow: Date) -> Date { serverTime.addingTimeInterval(localNow.timeIntervalSince(localTime)) }
}

/// Server minus phone time from each reply's `Date` header (00 §6.3), one per APIClient and so per site; kept in memory only.
/// Countdowns and “N 分钟前” read `now()`. Token expiry uses the request clock, not this one.
public final class ServerClock: Sendable {
    private let state: Mutex<TimeInterval>
    private let local: @Sendable () -> Date
    public init(offset: TimeInterval = 0, localNow: @escaping @Sendable () -> Date = { Date() }) {
        state = Mutex(offset); local = localNow
    }
    public var offset: TimeInterval { state.withLock { $0 } }
    public func localNow() -> Date { local() }
    public func now() -> Date { local().addingTimeInterval(offset) }
    /// A missing or unreadable header leaves the offset alone.
    public func recordDateHeader(_ raw: String?, receivedAt: Date) {
        guard let server = ServerTime.parseHTTPDate(raw) else { return }
        state.withLock { $0 = server.timeIntervalSince(receivedAt) }
    }
    @discardableResult public func record(sampledAt: Date, receivedAt: Date) -> ClockSample {
        let sample = ClockSample(serverTime: sampledAt, localTime: receivedAt)
        state.withLock { $0 = sample.offset }
        return sample
    }
}

extension KeyedDecodingContainer {
    /// 00 §6.4 RFC3339 field; missing, null or malformed is nil rather than a decoding failure.
    func optionalTimestamp(_ key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return ServerTime.parseTimestamp(try? decode(String.self, forKey: key))
    }
    /// 00 §6.4 Unix-seconds field (account `expires_at`, proxy check times).
    func optionalUnixTime(_ key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return ServerTime.date(unixSeconds: try? decode(Int64.self, forKey: key))
    }
}
