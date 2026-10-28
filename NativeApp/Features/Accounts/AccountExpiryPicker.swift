import SwiftUI
import Sub2Core

/// 20 §3.3 过期时间, pushed inside the sheet (S2-19 reuses it), in the phone's time zone (U53): 保持当前 when the value is no
/// preset, 不过期, 1 个月后 and 1 年后 from the site clock's now with their dates, and the custom date and time. Picking one goes
/// back to the form. A footnote names the phone's zone when it differs from the site's.
struct AccountExpiryPicker: View {
    @Binding var expiresAt: Int64?
    /// ServerTime (20 §0.6).
    let now: Date
    let serverTimeZone: ServerTimeZone
    let onCustom: () -> Void
    let onDone: () -> Void

    var body: some View {
        let calendar = AccountExpiry.calendar(.current)
        let month = AccountExpiry.seconds(adding: AccountExpiry.Preset.oneMonth.rawValue, to: now, calendar: calendar)
        let year = AccountExpiry.seconds(adding: AccountExpiry.Preset.oneYear.rawValue, to: now, calendar: calendar)
        List {
            Section {
                if let current = expiresAt, current != month, current != year {
                    row(AccountExpiry.keepCurrent, value: current, id: "keep")
                }
                row(AccountExpiry.never, value: nil, id: "never")
                row(AccountExpiry.Preset.oneMonth.title, value: month, id: "month")
                row(AccountExpiry.Preset.oneYear.title, value: year, id: "year")
                Button(action: onCustom) {
                    HStack {
                        Text(AccountExpiry.custom).foregroundStyle(Palette.ink1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.expiry.custom")
            } footer: {
                if let note = AccountExpiry.timeZoneNote(device: .current, server: serverTimeZone, at: now) {
                    Text(note).accessibilityIdentifier("account.expiry.timezone")
                }
            }
        }
        .navigationTitle(AccountExpiry.pickerTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, value: Int64?, id: String) -> some View {
        let selected = expiresAt == value
        return Button {
            expiresAt = value
            onDone()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Palette.accent).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(title).foregroundStyle(Palette.ink1)
                Spacer()
                if let value { Text(AccountExpiry.text(value, timeZone: .current)).monospacedDigit().foregroundStyle(Palette.ink3) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("account.expiry.\(id)")
    }
}

/// 自定义日期和时间…: the calendar and the time in the phone's zone; the button names the moment and stays greyed until it lies
/// ahead of the site clock's now.
struct AccountExpiryCustomPage: View {
    @Binding var expiresAt: Int64?
    let now: Date
    let onDone: () -> Void
    @State private var date: Date

    init(expiresAt: Binding<Int64?>, now: Date, onDone: @escaping () -> Void) {
        _expiresAt = expiresAt; self.now = now; self.onDone = onDone
        let start = expiresAt.wrappedValue.map(AccountExpiry.date)
            ?? AccountExpiry.date(AccountExpiry.seconds(adding: 1, to: now, calendar: AccountExpiry.calendar(.current)))
        _date = State(initialValue: start)
    }

    /// Whole minutes, as the picker shows them.
    private var seconds: Int64 {
        let value = AccountExpiry.seconds(of: date)
        return value - value % 60
    }
    private var isFuture: Bool { AccountExpiry.isFuture(seconds, now: now) }

    var body: some View {
        Form {
            DatePicker(AccountEditField.expiresAt.title, selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("account.expiry.date")
            Section {
                Button {
                    expiresAt = seconds
                    onDone()
                } label: {
                    Text(isFuture ? AccountExpiry.confirmTitle(seconds, timeZone: .current) : AccountEditCopy.futureRequired)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFuture)
                .accessibilityIdentifier("account.expiry.confirm")
            }
        }
        .navigationTitle(AccountExpiry.custom)
        .navigationBarTitleDisplayMode(.inline)
    }
}
