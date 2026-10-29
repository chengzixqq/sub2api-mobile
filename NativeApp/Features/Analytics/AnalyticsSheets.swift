import SwiftUI
import Sub2Core

extension AnalyticsCardKey {
    /// The filter sheet's shares: the whole range, whatever the filter.
    static let filterGroupShares = AnalyticsCardKey("filter.groupShares", scope: .rangeOnly, showsInUpdateLine: false)
    static let filterModels = AnalyticsCardKey("filter.models", scope: .rangeOnly, showsInUpdateLine: false)
}

private enum AnalyticsRangeEnd: String {
    case start, end
    var title: String { self == .start ? "开始" : "结束" }
}

/// 40 §1.2 自定义范围: the shortcuts 本月 / 近 14 天 / 上月, then 开始 and 结束, each opening a calendar for one day on the site's calendar
/// (R20). The rules and wording are AnalyticsCustomDraft's: days from 366 days ago to today, the other end follows, a range equal
/// to a shortcut selects it. 应用 selects the range and remembers it.
struct AnalyticsCustomRangeSheet: View {
    let session: AnalyticsSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AnalyticsCustomDraft
    @State private var editing: AnalyticsRangeEnd?

    init(session: AnalyticsSession) {
        self.session = session
        _draft = State(initialValue: AnalyticsCustomDraft(range: session.currentRange()))
    }

    var body: some View {
        NavigationStack {
            List {
                Section { shortcuts }
                Section {
                    endRow(.start)
                    if editing == .start { calendar(.start) }
                    endRow(.end)
                    if editing == .end { calendar(.end) }
                } footer: {
                    Text(draft.footnote).monospacedDigit()
                }
            }
            .navigationTitle("自定义范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        session.select(draft.selection)
                        dismiss()
                    }
                    .accessibilityIdentifier("analytics.custom.apply")
                }
            }
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsPreset.shortcuts, id: \.self) { preset in
                let isOn = draft.matchedShortcut == preset
                Button {
                    draft = draft.applying(preset)
                    editing = nil
                } label: {
                    AnalyticsCapsuleLabel(isOn: isOn) { Text(preset.title) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("analytics.custom.preset.\(preset.rawValue)")
            }
        }
    }

    private func endRow(_ end: AnalyticsRangeEnd) -> some View {
        let line = end == .start ? draft.startLine : draft.endLine
        let isOpen = editing == end
        return Button {
            withAnimation { editing = isOpen ? nil : end }
        } label: {
            HStack(spacing: 12) {
                Text(end.title).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(line).monospacedDigit().foregroundStyle(isOpen ? Palette.accent : Palette.ink2).multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(end.title)，\(line)")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityIdentifier("analytics.custom.\(end.rawValue)")
    }

    /// One day at a time and no range shading, as the system calendar draws it. The picker works in the site's zone and calendar,
    /// so the day picked is the site's day; only the system's “today” mark follows the phone.
    private func calendar(_ end: AnalyticsRangeEnd) -> some View {
        let zone = session.timeZone, bounds = draft.bounds
        let day = Binding<Date>(
            get: { (end == .start ? draft.from : draft.to).start(in: zone) },
            set: { date in
                let picked = AnalyticsDay(containing: date, in: zone)
                draft = end == .start ? draft.settingFrom(picked) : draft.settingTo(picked)
            })
        let latest = bounds.latest.adding(days: 1).start(in: zone).addingTimeInterval(-1)
        return DatePicker(end.title, selection: day, in: bounds.earliest.start(in: zone)...latest, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.timeZone, zone.timeZone)
            .environment(\.calendar, zone.calendar)
            .accessibilityIdentifier("analytics.custom.calendar.\(end.rawValue)")
    }
}

/// 40 §1.2 筛选: one group or one model. Groups come from the session's group directory in its order (inactive ones marked and
/// still selectable), models from the range's `dashboard/models?model_source=requested`; the right side is each one's share of the
/// range's actual cost. Picking a row applies it and closes the sheet.
struct AnalyticsFilterSheet: View {
    let session: AnalyticsSession
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AnalyticsFilter.Kind

    init(session: AnalyticsSession) {
        self.session = session
        _kind = State(initialValue: session.filter?.kind ?? .group)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("筛选类型", selection: $kind) {
                        ForEach(AnalyticsFilter.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("analytics.filter.kind")
                }
                Section {
                    choice(nil, title: kind == .group ? "全部分组" : "全部模型", id: "analytics.filter.all")
                    switch kind {
                    case .group: groupRows
                    case .model: modelRows
                    }
                } footer: {
                    Text(AnalyticsFilterOptions.note(kind: kind, supportsOpsModelFilter: session.supportsOpsModelFilter))
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
            }
            .task(id: kind) { await load(kind) }
        }
    }

    @ViewBuilder private var groupRows: some View {
        if let directory = session.groups {
            if directory.state.value != nil {
                let usage = session.state(.filterGroupShares, as: [AnalyticsBreakdown].self)?.value
                ForEach(AnalyticsFilterOptions.groupRows(directory: directory.groups, usage: usage)) { choice($0) }
            } else if directory.state.failureReason != nil {
                BlockFailureRow(state: directory.state, refresh: directory.refreshState, id: "analytics.filter.groups") {
                    Task { await directory.refresh() }
                }
            } else {
                loadingRow
            }
        }
    }

    @ViewBuilder private var modelRows: some View {
        let models = session.state(.filterModels, as: [AnalyticsBreakdown].self)
        if let value = models?.value {
            ForEach(AnalyticsFilterOptions.modelRows(value, current: session.filter)) { choice($0) }
        } else if let models, models.error != nil {
            BlockFailureRow(models, id: "analytics.filter.models") { Task { await loadModels(refresh: true) } }
        } else {
            loadingRow
        }
    }

    private var loadingRow: some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
    }

    private func choice(_ row: AnalyticsFilterOptions.Row) -> some View {
        let id: String = switch row.filter {
        case .group(let groupID): "analytics.filter.row.group.\(groupID)"
        case .model(let name): "analytics.filter.row.model.\(name)"
        }
        return choice(row.filter, title: row.title, isInactive: row.isInactive, share: row.share, id: id)
    }

    /// `filter` nil is 全部分组 / 全部模型, chosen while no condition of this kind is set.
    private func choice(_ filter: AnalyticsFilter?, title: String, isInactive: Bool = false, share: String? = nil, id: String) -> some View {
        let isOn = filter.map { session.filter == $0 } ?? (session.filter?.kind != kind)
        return Button {
            session.setFilter(filter)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                Text(title).font(filter?.kind == .model ? .body.monospaced() : .body).foregroundStyle(Palette.ink1)
                    .lineLimit(1).truncationMode(.middle)
                if isInactive {
                    Text("停用").font(.caption).foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.sunken, in: Capsule())
                }
                Spacer(minLength: 8)
                if let share { Text(share).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func load(_ kind: AnalyticsFilter.Kind) async {
        switch kind {
        case .group:
            await session.groups?.ensureLoaded()
            await loadGroupShares()
        case .model:
            await loadModels(refresh: false)
        }
    }
    private func loadGroupShares() async {
        await session.load(.filterGroupShares, fixture: { _ in try AnalyticsFixtures.groupShares() }) { client, session in
            try await client.usageAnalysisGroups(session.query(filtered: false))
        }
    }
    private func loadModels(refresh: Bool) async {
        await session.load(.filterModels, refresh: refresh, fixture: { _ in try AnalyticsFixtures.filterModels() }) { client, session in
            try await client.usageAnalysisModels(session.query(filtered: false), source: .requested)
        }
    }
}
