import SwiftUI
import Sub2Core

// 30 §2.3 the detail's parts, top to bottom: (S3-07's pending banner) → the disabled banner → the balance header → 壹 API Key →
// 贰 充值与调整记录 → 叁 档案. Each block shows its own skeleton, value or “加载失败 · 重试”.

/// “已禁用 · 不能登录，名下的 Key 也不能调用” with 启用, the same action as the ⋯ menu's.
struct UserDisabledBanner: View {
    let isWorking: Bool
    let onEnable: () -> Void

    var body: some View {
        StatusBanner(tone: .neutral, systemImage: "minus.circle", title: UserDetailPresentation.disabledTitle,
                     detail: UserDetailPresentation.disabledDetail) {
            Button(UserDetailPresentation.enableTitle, action: onEnable)
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(isWorking)
                .accessibilityIdentifier("user.disabled.enable")
                .readOnlyGate()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("user.disabled")
    }
}

/// “可用余额”, the amount, “今日消费 · 本月” with 余额低, then ＋ 充值 and 退款 (30 §2.3). A failed today or month read adds its
/// own retry row under them (30 §2.5); a read-only token's “—” has none.
struct UserBalanceHero: View {
    let detail: UserDetailModel
    let user: AdminUser
    let onTopUp: () -> Void
    let onRefund: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            figures
            if !detail.isReadOnlyToken, detail.today.value == nil, detail.today.error != nil {
                BlockFailureRow(detail.today, id: "user.hero.today") { Task { await detail.reloadToday() } }
            }
            if detail.month.value == nil, detail.month.error != nil {
                BlockFailureRow(detail.month, id: "user.hero.month") { Task { await detail.reloadMonth() } }
            }
            HStack(spacing: 10) {
                Button(action: onTopUp) { Text(UserDetailPresentation.topUpTitle).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("user.balance")
                Button(action: onRefund) { Text(UserDetailPresentation.refundTitle).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("user.refund")
            }
            .readOnlyGate()
        }
        .padding(.vertical, 6)
    }

    private var figures: some View {
        let today = detail.todayCost, month = detail.monthCost, low = detail.isLowBalance
        return VStack(alignment: .leading, spacing: 6) {
            Text(UserDetailPresentation.balanceLabel).font(.footnote).foregroundStyle(Palette.ink2)
            Text(DisplayFormat.money(user.balance)).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(UserDetailPresentation.balanceSubline(today: today, month: month)).font(.subheadline).monospacedDigit()
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 0)
                if low { ToneBadge(text: UserListMark.lowBalance.label, tone: .caution) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(UserDetailPresentation.balanceSpoken(balance: user.balance, today: today, month: month, isLow: low)))
        .accessibilityIdentifier("user.hero.balance")
    }
}

/// 壹 · API Key: one summary row into 编辑用户 · Key 与限额, then 使用记录, then the footnote.
struct UserKeySummarySection: View {
    let detail: UserDetailModel
    let displayName: String

    var body: some View {
        Section {
            keys
            NavigationLink(value: AppRoute.logs(LogsRoute(scope: .usage, user: RouteObject(id: detail.userID, name: displayName)))) {
                HStack(alignment: .firstTextBaseline) {
                    Label(UserDetailPresentation.logsTitle, systemImage: "list.bullet.rectangle").foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    Text(UserDetailPresentation.logsDetail).font(.footnote).foregroundStyle(Palette.ink3)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("user.logs")
        } header: {
            UserDetailSectionHeader(title: UserDetailPresentation.keysTitle, ordinal: "壹", meta: detail.keySummary?.meta, id: "user.keys.header") {
                BlockStatusAccessory(detail.keys, id: "user.keys.block") { Task { await detail.reloadKeys() } }
            }
        } footer: {
            Text(UserDetailPresentation.keysFootnote).font(.footnote).foregroundStyle(Palette.ink2)
        }
    }

    @ViewBuilder private var keys: some View {
        if let summary = detail.keySummary {
            NavigationLink(value: AppRoute.userEdit(id: detail.userID, segment: .keys)) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title).font(.body).foregroundStyle(summary.emptyNote == nil ? Palette.ink1 : Palette.ink2)
                        Text(summary.detail).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                } icon: { Image(systemName: "key").foregroundStyle(Palette.ink3) }
                .padding(.vertical, 4)
                .frame(minHeight: 44)
            }
            .accessibilityLabel(Text(summary.spokenLabel))
            .accessibilityIdentifier("user.keys")
        } else if detail.keys.error != nil {
            BlockFailureRow(title: "Key 加载失败", error: detail.keys.lastError, occurredAt: detail.keys.lastErrorAt, refresh: detail.keys.refresh,
                            id: "user.keys") { Task { await detail.reloadKeys() } }
        } else {
            Text("开发密钥、脚本、备用\n标准组 · 最近使用 3 分钟前").font(.footnote).redacted(reason: .placeholder)
                .frame(minHeight: 44).accessibilityLabel(Text("正在加载 API Key")).accessibilityIdentifier("user.keys.skeleton")
        }
    }
}

/// 贰 · 充值与调整记录: “总充值” in the header, the latest five (S3-04's two-line row), “全部 N 条” past five.
struct UserLedgerPeekSection: View {
    let detail: UserDetailModel
    let timeZone: ServerTimeZone
    let now: Date

    var body: some View {
        Section {
            switch detail.ledger.state.display {
            case .placeholder, .disabled:
                ForEach(0..<2, id: \.self) { _ in UserLedgerRowSkeleton() }
            case .failed:
                BlockFailureRow(detail.ledger, id: "user.ledger.peek") { Task { await detail.reloadLedger() } }
            case .value(let page, _, _, _):
                records(page)
            }
        } header: {
            UserDetailSectionHeader(title: UserDetailPresentation.ledgerTitle, ordinal: "贰", meta: detail.ledger.value.flatMap(UserDetailPresentation.ledgerMeta),
                                    id: "user.ledger.header") {
                BlockStatusAccessory(detail.ledger, id: "user.ledger.block") { Task { await detail.reloadLedger() } }
            }
        }
    }

    @ViewBuilder private func records(_ page: BalanceHistoryPage) -> some View {
        let rows = UserDetailPresentation.ledgerPeek(page)
        if rows.isEmpty {
            Text(UserDetailPresentation.noRecords).foregroundStyle(Palette.ink2).frame(minHeight: 44).accessibilityIdentifier("user.ledger.peek.empty")
        } else {
            ForEach(rows) { UserLedgerRow(item: $0, timeZone: timeZone, now: now) }
        }
        if let more = UserDetailPresentation.ledgerMoreText(total: page.total) {
            NavigationLink(value: AppRoute.userLedger(userID: detail.userID)) {
                Text(more).foregroundStyle(Palette.accent).frame(minHeight: 44)
            }
            .accessibilityIdentifier("user.ledger.all")
        }
    }
}

/// 叁 · 档案: 用户 ID, 状态, 角色, 并发上限 in two columns.
struct UserProfileSection: View {
    let rows: [UserProfileRow]

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { start in
                    GridRow {
                        cell(rows[start])
                        if start + 1 < rows.count { cell(rows[start + 1]) }
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            UserDetailSectionHeader(title: UserDetailPresentation.profileTitle, ordinal: "叁", meta: nil, id: "user.profile.header") { EmptyView() }
        }
    }

    private func cell(_ row: UserProfileRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label).font(.footnote).foregroundStyle(Palette.ink2)
            Text(row.value).font(.body).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.label))
        .accessibilityValue(Text(DisplayFormat.spoken(row.value)))
        .accessibilityIdentifier("user.profile.\(row.id)")
    }
}

/// 30 §2.5 首次加载: the header's shape while the profile is read.
struct UserDetailSkeleton: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(UserDetailPresentation.balanceLabel).font(.footnote)
                    Text("$0,000.00").font(.largeTitle.weight(.semibold))
                    Text("今日消费 $0.00 · 本月 $00.00").font(.subheadline)
                }
                .redacted(reason: .placeholder)
                .padding(.vertical, 6)
            }
            Section { ForEach(0..<3, id: \.self) { _ in UserLedgerRowSkeleton() } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载用户"))
        .accessibilityIdentifier("user.detail.loading")
    }
}

/// The title with its number on the right and an optional meta before it; NumberedSectionHeader takes a meta from S1-09b on,
/// and S6-26 moves these sections over (S3D1-25). VoiceOver reads the title, then the meta as its value.
private struct UserDetailSectionHeader<Accessory: View>: View {
    let title: String
    let ordinal: String
    let meta: String?
    let id: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
                if let meta { Text(meta).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink3) }
                Text(ordinal).font(.subheadline).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(meta ?? ""))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
            accessory
        }
        .textCase(nil)
    }
}
