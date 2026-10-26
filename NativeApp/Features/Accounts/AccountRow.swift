import SwiftUI
import Sub2Core

/// C-7: the dimension the section header already names, and the group a member row writes “另属” against (50 §2.3 / §8.3).
struct AccountRowContext: Equatable, Sendable {
    typealias Omit = AccountRowOmit
    var omit: Omit = .none
    var home: String? = nil
}

/// 20 §1.3: three lines, the status capsule, the state glyph and badge, and a chevron. States use the site clock (20 §0.6) and
/// absolute times the server's zone. A timed state redraws every second; when its window ends `onCountdownElapsed` runs once.
/// The container wraps the row in its own button or link and gives it the identifier `account.<id>`.
struct AccountRow: View {
    let account: UpstreamAccount
    let today: AccountTodayCell
    let context: AccountRowContext
    let railPosition: RailPosition?
    let groupName: (Int) -> String?
    let catalog: MetaCatalog
    let onCountdownElapsed: (@MainActor () -> Void)?
    private let input: AccountStateInput
    @Environment(\.sessionContext) private var session

    init(account: UpstreamAccount, today: AccountTodayCell, context: AccountRowContext = .init(), railPosition: RailPosition?,
         groupName: @escaping (Int) -> String?, catalog: MetaCatalog = .builtin, onCountdownElapsed: (@MainActor () -> Void)? = nil) {
        self.account = account; self.today = today; self.context = context; self.railPosition = railPosition
        self.groupName = groupName; self.catalog = catalog; self.onCountdownElapsed = onCountdownElapsed
        input = AccountStateInput(account)
    }

    var body: some View {
        let target = AccountDisplayState(input, now: serverNow(Date())).countdownTarget
        Group {
            if target != nil {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in content(now: serverNow(timeline.date)) }
            } else {
                content(now: serverNow(Date()))
            }
        }
        .task(id: target) { await waitForCountdown(target) }
    }

    private func content(now: Date) -> some View {
        let display = AccountDisplayState(input, now: now)
        let second = AccountRowPresentation.secondLine(account, omit: context.omit, home: context.home, catalog: catalog, directory: groupName)
        let third = AccountRowPresentation.thirdLine(account, display: display, today: today, timeZone: timeZone)
        return HStack(alignment: .top, spacing: 10) {
            AccountStateGlyph(state: display.state)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    AccountRowTitle(name: account.name, isIdle: AccountRowPresentation.isIdle(display.state))
                    Spacer(minLength: 4)
                    AccountStatusBadge(state: display, now: now)
                }
                AccountRowSecondLine(text: second)
                AccountRowThirdLineView(line: third, tone: display.tone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                .frame(minHeight: 22)
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 16))
        .contentShape(Rectangle())
        .statusCapsule(tone: railPosition == nil ? nil : display.tone, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccountRowPresentation.accessibilityLabel(name: account.name, display: display, now: now, second: second, third: third))
    }

    /// The window's end is a site clock time; the device sleeps the same span.
    private func waitForCountdown(_ target: Date?) async {
        guard let target, let onCountdownElapsed else { return }
        let wait = max(0, target.timeIntervalSince(serverNow(Date()))) + 0.5
        do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        onCountdownElapsed()
    }
    private func serverNow(_ local: Date) -> Date { local.addingTimeInterval(session?.client.serverClock.offset ?? 0) }
    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
}

/// 00 §8.2.4 badge with the state's icon; a timed state counts down in it (m:ss / h:mm:ss). 正常 draws nothing (design BaseBadge).
/// VoiceOver reads the row as a whole, so the badge is hidden from it.
struct AccountStatusBadge: View {
    let state: AccountDisplayState
    let now: Date
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12.5
    @ScaledMetric(relativeTo: .caption) private var height = 22.0

    var body: some View {
        if let text = AccountRowPresentation.badgeText(state, now: now) {
            HStack(spacing: 4) {
                Image(systemName: AccountRowPresentation.systemImage(for: state.state))
                Text(text).monospacedDigit()
            }
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(state.tone.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minHeight: height)
            .background(state.tone.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
        }
    }
}

/// Design BaseGlyph: an 8pt dot for 正常, a 17pt symbol otherwise, in the state's tone.
private struct AccountStateGlyph: View {
    let state: AccountScheduleState
    @ScaledMetric(relativeTo: .body) private var symbolSize = 17.0
    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0
    @ScaledMetric(relativeTo: .body) private var width = 22.0

    var body: some View {
        Image(systemName: AccountRowPresentation.systemImage(for: state))
            .font(.system(size: state == .available ? dotSize : symbolSize, weight: .semibold))
            .foregroundStyle(state.tone.base)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }
}

/// Paused and disabled rows dim their name to ink2 (design `.is-idle .row-title`), which keeps every text at 4.5:1 (00 §8.2.5).
private struct AccountRowTitle: View {
    let name: String
    let isIdle: Bool
    @ScaledMetric(relativeTo: .body) private var size = 16.5

    var body: some View {
        Text(name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isIdle ? Palette.ink2 : Palette.ink1)
            .lineLimit(1)
    }
}

private struct AccountRowSecondLine: View {
    let text: String
    @ScaledMetric(relativeTo: .subheadline) private var size = 14.0

    var body: some View {
        Text(text).font(.system(size: size)).foregroundStyle(Palette.ink2).lineLimit(1)
    }
}

private struct AccountRowThirdLineView: View {
    let line: AccountRowThirdLine
    let tone: Tone
    @ScaledMetric(relativeTo: .footnote) private var size = 13.5

    var body: some View {
        switch line {
        case .error(let summary):
            Text(summary).font(.system(size: size)).foregroundStyle(Tone.critical.ink).lineLimit(1)
        case .limited(let stopped, let reason, let resume, let limits):
            limited(stopped: stopped, reason: reason, resume: resume, limits: limits)
        case .usage(let concurrency, let today):
            AccountRowUsage(concurrency: concurrency, today: today)
        }
    }

    /// The stop mark leads and “HH:MM 恢复” never truncates; the model-limit tail goes first, then the reason (20 §1.3).
    private func limited(stopped: String?, reason: String, resume: String, limits: String?) -> some View {
        HStack(spacing: 0) {
            if let stopped {
                Text(stopped).fontWeight(.semibold).foregroundStyle(Tone.neutral.ink).fixedSize()
                Text(" · ").fixedSize()
            }
            Text(reason).layoutPriority(1)
            Text(" · \(resume)").monospacedDigit().fixedSize()
            if let limits { Text(" · \(limits)").foregroundStyle(Tone.model.ink) }
        }
        .font(.system(size: size))
        .foregroundStyle(tone.ink)
        .lineLimit(1)
    }
}

/// Concurrency as a small capacity bar (design BaseCapacity, 92 × 6) and today's charge on the right.
private struct AccountRowUsage: View {
    let concurrency: AccountRowConcurrency
    let today: String?
    @ScaledMetric(relativeTo: .footnote) private var size = 13.5
    @ScaledMetric(relativeTo: .caption) private var labelSize = 12.0
    @ScaledMetric(relativeTo: .subheadline) private var moneySize = 14.0

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if let fraction = concurrency.fraction { bar(fraction) }
                Text(concurrency.text).font(.system(size: size)).monospacedDigit()
                    .foregroundStyle(concurrency.isMissing ? Palette.ink2 : Palette.ink1)
            }
            Spacer(minLength: 4)
            if let today {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("今日").font(.system(size: labelSize)).foregroundStyle(Palette.ink3)
                    Text(today).font(.system(size: moneySize)).monospacedDigit().foregroundStyle(Palette.ink1)
                }
            }
        }
        .lineLimit(1)
        .padding(.top, 2)
    }

    private func bar(_ fraction: Double) -> some View {
        Capsule().fill(Palette.sunken)
            .frame(width: 92, height: 6)
            .overlay(alignment: .leading) {
                Capsule().fill(concurrency.tone?.base ?? Palette.ink2).frame(width: 92 * fraction, height: 6)
            }
    }
}

/// 20 §1.5 first load: a row's shape without data.
struct AccountRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Palette.sunken).frame(width: 12, height: 12).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude-官方-01").font(.system(size: 16.5, weight: .semibold))
                Text("高级组、Claude Code 组 · OAuth").font(.system(size: 14))
                Text("2/4 并发 · 今日 $0.00").font(.system(size: 13.5))
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 12, trailing: 16))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
