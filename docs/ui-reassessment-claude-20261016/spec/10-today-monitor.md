# 10 · 今日（概览）与监控

> 本章覆盖底部 Tab「概览」（首页，含平静布局）与「监控」（概况 / 渠道 / 告警三段），以及它们的二级页：告警详情、静默与手动解决、运维监控开关。读者是照着实现 SwiftUI App（最低 iOS 26）的工程师。
>
> 口径依据：`../DECISIONS.md`（第 3 轮以“更正”为准，文末“设计稿评审意见”“TPM 口径”最新）、`../BACKEND-API-CHANGES.md` 的“维护者决定”与“实现进度”（进度表备注优先于条目原文）、设计稿 `../html-preview/layouts/main/v-today.jsx`、`00-core.jsx`（`MonitorScreen` / `MonOverview` / `MonServer` / `MonChannels` / `MonAlerts`）、`../html-preview/shared/core.jsx`（`deriveAttention`）、`shared/data.jsx`、sub2 `docs/API_ERROR_CODES.md`。所有接口路径、字段名、reason 都在 sub2 `backend/internal`（main，`70116315d`）源码里核对过；文中写“后端无此能力 → App 退路”的地方是源码里确实没有的。

---

## 0. 本章公共约定

### 0.1 适用身份

- 本章所有接口都只对**站长管理员**开放：`dashboard/home`、`dashboard/rates`、`dashboard/stats`、`accounts/status-summary`、`/admin/ops/*`、`/admin/channel-monitor-v2/*` 都不在 vendor 白名单里（`server/middleware/vendor_routes.go`），vendor 调用一律 403。
- 判定：`GET /api/v1/admin/me` 的 `workspace` 为 null 且 `user.role == "admin"` 才渲染本章内容；`workspace` 非 null（vendor）时，概览只显示占位“代运营工作区不提供全站概览”，监控 Tab 显示“代运营工作区没有运维监控权限”。（vendor 的完整体验不在本章范围。）
- 设计稿里“服务器区仅管理员可见、普通用户端不能有服务器状态”：App 只允许管理员登录，所以服务器区的显示条件就是上面的站长判定。

### 0.2 能力探测（`GET /api/v1/admin/me` → `server.capabilities`）

| capability | 本章用途 | 缺失时 |
|---|---|---|
| `dashboard.home` | 首页一次取回 7 段 | 走 §1.2 的逐接口退路 |
| `dashboard.rates` | 首页退路里的 RPM / TPM / 错误率 | 退到 `ops/dashboard/overview?time_range=5m`，再退到 `dashboard/stats` |
| `dashboard.accounts_ranking` | 平静布局“按账号 · 前 4” | 隐藏该分区（不做全量账号 + 今日统计本地排序，首页不值得） |
| `accounts.status_summary` | 待处理里的账号分档、分组可用、平静判定 | 走 D02 退路（§1.2） |
| `accounts.structured_error` | 错误账号行的 `error_at` / `error_summary`（原因短句由 20 §0.2 的 `AccountDisplayState` 生成） | 原因写“上游返回异常”（不显示 `error_message` 原文，20 §0.2），不显示“N 分钟前” |
| `ops.alert_event_counts` | 精确的告警中条数（含被静默的） | 用 `alert-events?status=firing&limit=500` 的条数 |
| `ops.alert_event_details` | 事件带 `rule` / `group_name` / `resolved_by_*` | 另拉 `ops/alert-rules` 与 `groups/all` 拼；规则已删时用 `description` 原文 |
| `ops.alert_latency_metrics` | 认得 `p95_latency_ms` / `p99_latency_ms` 规则 | 这两种规则显示“不受支持（不会触发）” |
| `ops.job_heartbeat_status` | 心跳的 `status` / `expected_interval_seconds` / `next_expected_at` | 本地判定（§4.3） |
| `ops.system_metrics_history` | CPU / 内存小折线 | 前台轮询 overview 时本机攒点，进页面只有当前值 |
| `ops.ingress_reject_totals` | 入口拒绝 `request_count_total` | 翻页累加 `items[].request_count`（最多 3 页，超出写“≥ N”） |
| `ops.monitoring_status` | 区分配置关闭 / 设置关闭，App 内开启 | 用 `PUT /api/v1/admin/settings {"ops_monitoring_enabled":true}`（§7.2） |

ETag 不看 capability，一律按 00 §4.2 处理：`APIClient` 层的 `ConditionalCache`（00 §9.7）自动带 `If-None-Match`、把 304 换成缓存里的解码结果，页面拿到的始终是模型本身，本章不另定义“未修改”类型。本章用到的接口里带 ETag 的只有 `dashboard/home`（`handler/admin/dashboard_home_handler.go:78`）、退路里的 `dashboard/stats` 与 `dashboard/snapshot-v2`、错误账号补字段用的 `GET /api/v1/admin/accounts`（`account_handler.go:840-857`）、§4 的 `ops/dashboard/snapshot-v2`（`ops_snapshot_v2_handler.go:67-70`）；其余接口（`dashboard/rates`、`accounts/status-summary`、`ops/dashboard/overview`、`alert-events`、`channel-monitor-v2/overview` 等）没有 ETag。

告警静默（D01）没有登记 capability：**以事件 JSON 里是否存在 `silence` 键判定**（D01 起该键始终输出，没有静默时为 null）。键不存在 = 旧服务端，按 §7.1 的旧服务端退路处理。

`features` 同一响应里本章要读：`ops_monitoring_enabled`、`ops_realtime_monitoring_enabled`、`ops_monitoring_disabled_reason`（`config_off` / `setting_off` / null）、`channel_monitor_enabled`、`channel_monitor_mode`。`server.server_timezone`、`server.server_utc_offset` 见 0.3。`/admin/me` 不可用（旧服务端）时：时区读 `GET /api/v1/settings/public` 的 `server_timezone` / `server_utc_offset`，运维开关以接口是否返回 404 `OPS_DISABLED` 为准。

### 0.3 时区

- “今日 / 昨日 / 每小时”一律按**服务器时区**：`dashboard/stats` 与 `dashboard/home` 的 `stats` 段固定按服务器时区，`today-stats` 也是（附录 A S12）。
- 发给 `dashboard/home` 的 `timezone` 只影响 `hourly` 段的分桶；App 传 `server_timezone`，与 stats 段同一天界。`dashboard/trend`、`dashboard/accounts-ranking` 也传 `timezone=<server_timezone>`。
- 小时桶标签形如 `2026-10-16 09:00`，没有时区后缀，按请求时区解析（现有 `DashboardPresentation.trendDate(_:timeZone:)` 可用，传服务器时区）。
- 手机时区与服务器 UTC 偏移不同时，概览导航副标题末尾加“· 按 UTC+8”（取 `server_utc_offset`）。

### 0.4 单位与格式（本章统一，新增到 `DashboardPresentation`）

| 类型 | 规则 | 例 |
|---|---|---|
| 金额 | `$` + 千分位 + 2 位小数，Decimal 四舍五入；负数用 `−$`；不加 `+`；缺失 `—` | `$1,284.50`、`−$12.30` |
| 紧凑数 | ≥ 1e9 `B`、≥ 1e6 `M`、≥ 1e3 `K`，1 位小数并去掉 `.0`；< 1000 原样整数 | `18.2K`、`240K`、`96.4M` |
| RPM | ≥ 10 取整；0 < x < 10 一位小数；0 显示 `0` | `46`、`0.4` |
| 后端比例（`error_rate`、`sla`、`reliability_rate`，0–1） | ×100，1 位小数 + `%` | `0.0086` → `0.9%` |
| 告警值（`metric_value`、阈值，百分比类指标已是百分数） | 按 §6.3 的单位表，不再 ×100。**阈值 = `rule.threshold ?? threshold_value`**：事件顶层的字段名是 `threshold_value`，`threshold` 只在 `rule` 对象里（`service/ops_alert_models.go:50-51`、`:80`）；规则已删且没有快照（`rule == null`）时用事件自带的 `threshold_value`，单位按未知指标处理（§6.3） | `5.2` → `5.2%` |
| 相对时间 | < 1 分钟“刚刚”；< 60 分钟“N 分钟前”；今天“今天 HH:MM”；昨天“昨天 HH:MM”；更早“M月d日 HH:MM” | `12 分钟前` |
| 倒计时 | `m:ss`，≥ 1 小时 `h:mm:ss`；每秒重算（以绝对时间戳减当前时间，不累减） | `4:37` |
| 时刻 | 服务器时区 `HH:MM` | `10:04` |

现有 `DashboardPresentation.compactNumber` 是 2 位小数（`18.20K`）、`money` 没有千分位、`cost` 缺失写“不可用”，都不符合本章；新增 `compact1(_:)`、`moneyGrouped(_:)`、`ratioPercent(_:)`、`rpm(_:)`、`relativeTime(_:now:timeZone:)`，缺失统一返回 `—`（BUILDER_GUIDE：缺失值显示 `—`，0 显示 0）。

### 0.5 共享状态与区块状态

- 新增会话级 `@MainActor @Observable final class LiveOpsStore`（随 `SessionContext` 创建、切站点即丢弃）：持有首页聚合、告警列表与计数、运维开关状态、账号状态汇总。概览、监控、告警详情读同一份，任何一处手动解决 / 静默后其余页面立即一致（设计稿 `ctx.alerts / resolveAlert / silenceAlert` 的同一份状态）。
- 每个区块用同一个状态枚举（建议放 `Sources/Sub2Core/BlockState.swift`）：

```swift
public enum BlockState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?)
    case loaded(Value, at: Date)
    case disabled(reason: String)                       // OPS_DISABLED、CHANNEL_MONITOR_DISABLED
    case failed(reason: String?, previous: Value?, at: Date?)
}
```

- 显示规则：有值（loaded 或 previous 非空）就显示值；刷新失败但有旧值时，区块标题右侧加一个小字“更新失败”（可点重试），不清空数字；没有旧值时数字位显示 `—`，区块内一行“加载失败 · 重试”。
- 现有 `DashboardLoadState`（`NativeApp/Features/DashboardView.swift:8-41`）的“晚到的旧请求不能覆盖新请求”逻辑保留，挪到 `NativeApp/Views/LoadState.swift`，内部改存 `BlockState`。

### 0.6 颜色与状态胶囊

- 账号状态色：错误 / 过载中 = critical；限流中 / 临时不可调度 = caution；暂停 / 停用 = neutral；正常 = ok（`STATE_META`）。
- 告警色 `alertTone`：firing 的 P0 = critical，P1 / P2 = caution，P3 = neutral；不在 firing = 无色（`shared/data.jsx:474-477`）。
- 带状态色的行左侧一律是浮动状态胶囊，相邻行连成一根状态轨（DECISIONS 评审第 3 条与“TPM 口径”末条）；尺寸与粘连规则见 00 §8“状态胶囊”，组件见 §0.7-7，本章只给每行的 tone。
- 金额与涨跌不着色；`▲ / ▼` 用正文墨色。

### 0.7 本章依赖的应用骨架

00–60 章还没有专门写应用骨架（Tab 结构、路由、跨 Tab 跳转、站点菜单、回执、状态轨）的章节（未决问题 Q10）。本节只写本章用到的部分和接口形状，骨架章节写出后以它为准，本节随之删减。

1. **Tab**：`enum MainTab { case today, accounts, users, monitor, search }`，前四个依次为“概览 · 账号 · 用户 · 监控”（DECISIONS 第 2 轮；设计稿 `00-core.jsx:5-10` `TAB_DEFS`），`search` 是 Tab 栏右侧独立的 `Tab(role: .search)`（60 §1.1）。本章负责 `today` 的根视图 `HomeView`（§1、§2）和 `monitor` 的根视图 `MonitorView`（§4–§6）；两个图标按设计稿 `home` / `pulse` 取 SF Symbols（建议 `house`、`waveform.path.ecg`）。账号 Tab 徽标、选择模式下隐藏 Tab 栏（设计稿 `TabBar` 在 `ctx.selecting` 时不渲染）不在本章。
2. **导航栈**：每个 Tab 各自一个 `NavigationStack(path:)`。本章写“推入”的地方都推到**当前 Tab** 的栈。
3. **路由**（本章用到的；参数名沿用各章定义）：

| 写法 | 目的页 | 定义处 |
|---|---|---|
| `.analytics()` | 统计分析 | 40 §0.1 `analytics`、§1 |
| `.analytics(focus: .perf, metric: .rpm / .tpm)` | 统计分析，滚到“RPM / TPM 趋势”并切到该指标 | 40 §0.1 |
| `.alert(id:)` | 告警详情 | 本章 §3 |
| `.account(id:)` | 账号详情 | 20 §2 |
| `.group(id:)` | 分组详情 | 50 §2 |
| `.groups(segment: .attention)` | 分组列表，选中“需处理”段 | 50 §1 |
| `.user(id:)` | 用户详情 | 30 §2 |
| `.redeem(reconcile: true)` | 兑换码列表并直接进入核对 | 60 §0.1、§11 |
| `.logs(scope: .errors / .upstream, group: id)` | 使用记录（错误请求 / 上游错误，带分组筛选） | 40 §0.1 `logs`、§6 |
| sheet `.accountTest(id:)` | 测试连接 | 20 §4 |

4. **跨 Tab 跳转**：`router.select(_ intent: TabIntent)`，本章用到 `.monitor(segment: .overview / .channels / .alerts)` 与 `.accounts(filter: .limited)`（筛选值见 20 §1.1 的 `needs` / `limited` / `paused`）。行为：切换 `selectedTab`，目标 Tab 的栈回到根，根视图在出现时取走一次 intent（取走后清空，重复切 Tab 不会再次应用）。建议形状：

```swift
@MainActor @Observable final class AppRouter {
    var selectedTab: MainTab = .today
    var paths: [MainTab: NavigationPath] = [:]
    private(set) var pendingIntent: TabIntent?
    func push(_ route: AppRoute)                          // 推入当前 Tab
    func present(_ sheet: AppSheet)
    func select(_ intent: TabIntent)                      // 切 Tab + 回到根 + 记下 intent
    func takeIntent(for tab: MainTab) -> TabIntent?       // 根视图 onAppear / onChange 调用
}
```

   推送点按的落点按 00 §7.5；本章约定先 `selectedTab = .today`，再 push `.alert(id:)` / `.account(id:)`。
5. **站点菜单**：概览的大标题（当前站点名）就是站点切换菜单（DECISIONS 第 2 轮“标题下拉菜单”），SwiftUI 优先用 `.toolbarTitleMenu { … }`（大标题状态下能否点开须实机确认；不行就在 `ToolbarItem(placement: .principal)` 放一个以站点名为标签的 `Menu`）。菜单内容按设计稿 `shared/core.jsx:77-93` `SiteMenu`：站点列表（每项站点名 + 主机名小字，当前站点前打勾）→ 分隔线 →「添加站点…」（60 §0.1 sheet `.addSite`）→「站点与凭据」（push `.settings(focus: .sites)`，60 §3）。切换行为按 00 §1.1（取消请求、新 generation、`/admin/me`、回到概览），成功后回执“已切换到 {站点名}”（设计稿 `setSite`）。20 §1.1 账号 Tab 的标题菜单用同一个组件。
6. **回执（toast）**：本章 §7.1、§7.2 用。底部玻璃条：图标 + 文字 + 最多一个按钮（「撤销」或一个自定义动作；两者都给时只显示自定义动作，BUILDER_GUIDE `showToast`）；显示 4.2 秒后消失（设计稿 `useAppModel` 的计时），新回执直接替换旧回执；出现时用 `AccessibilityNotification.Announcement(text).post()` 朗读，按钮读屏读按钮文字，点按区 ≥ 44pt。建议 `NativeApp/Views/Receipt.swift`：`Receipt{text, icon, tone, action: ReceiptAction?}` + 会话级 `ReceiptCenter.show(_:)`，由 `MainTabs` 在 Tab 栏上方叠加显示。
7. **状态轨**：画法按 00 §8；由列表容器根据前后行决定每行胶囊的上下内边距与圆角（只有整段最上端和最下端是圆头）。建议 `NativeApp/Views/StatusRail.swift`：`.statusCapsule(tone:position:)`，`position ∈ {single, top, middle, bottom}` 由容器计算。
8. **确认框**：本章只用普通确认框与动作表（`.alert` / `.confirmationDialog`），不涉及输入名称匹配或 Face ID 分支（那是删除确认，见 00 §8、20 §0.4）。

---

## 1. 概览 Tab · 常规布局（有待处理时）

### 1.1 入口与导航

- 入口：底部 Tab 第 1 个「概览」（Tab 名“概览”，DECISIONS 第 2 轮）；冷启动默认 Tab；推送“告警触发 / 账号出错”点按后先切到本 Tab 再推入目标页（00 §7.5，§0.7-4）。
- 导航栏：大标题 = 当前站点名，标题本身是站点切换菜单（§0.7-5）；副标题 = 服务器时区的“10月16日 周五 · 刚刚更新”（规则见 1.3.1）；右上 `···` 菜单：「刷新」「统计分析」。
- 去向（路由写法见 §0.7-3、§0.7-4）：

| 点按 | 去向 |
|---|---|
| 6 格中的今日实际扣费 / 请求 / 错误率 / 利润 | 推入统计分析 `.analytics()`（40 §1） |
| 6 格中的 RPM / TPM | 推入统计分析并滚到“RPM / TPM 趋势”，切到该指标 `.analytics(focus: .perf, metric: .rpm / .tpm)`（40 §0.1） |
| 告警行 | 推入告警详情 `.alert(id:)`（§3） |
| “另有 N 条告警中”行 | `router.select(.monitor(segment: .alerts))` |
| 错误 / 过载账号行 | 推入账号详情 `.account(id:)`（20 §2） |
| 错误账号行内「测试」 | 打开测试连接 sheet `.accountTest(id:)`（20 §4）；sheet 关闭后刷新首页 |
| “受限 N 个账号”行 | `router.select(.accounts(filter: .limited))`（20 §1.1） |
| “可用不足 N 个分组”行 | N = 1 推入分组详情 `.group(id:)`；N > 1 推入分组列表并选中“需处理”段 `.groups(segment: .attention)`（50 §1、§8） |
| 充值 / 退款结果待核对 | 推入用户详情 `.user(id:)`，由 30 §3 完成核对 |
| 兑换码生成结果待核对 | 推入兑换码列表并直接进入核对 `.redeem(reconcile: true)`（60 §11） |
| 今日区“更多统计” | 推入统计分析 `.analytics()` |
| 运行区“渠道”行 | `router.select(.monitor(segment: .channels))` |
| 运维监控未开启提示行 | 打开 §7.2 的开启确认 |

### 1.2 数据来源

**主路径（capability `dashboard.home`）**：一次请求，各段独立成败。

`GET /api/v1/admin/dashboard/home?timezone=<server_timezone>`（不传 `include` = 全部 7 段）

- 鉴权与参数通过即 HTTP 200；每段 `{status: ok|disabled|error|timeout, error?: <reason>, data?: …}`，只有 ok 才有 `data`。
- 段内容（`service/dashboard_home.go`）：

| 段 | data 字段（本章用到的） |
|---|---|
| `stats` | `today_requests`、`today_tokens`、`today_cost`（标准）、`today_actual_cost`、`today_account_cost`、`stats_updated_at`、`stats_stale`、`yesterday_same_time_actual_cost`、`yesterday_same_time_requests`、`yesterday_same_time_account_cost`、`yesterday_same_time_until`（后四个可为 null） |
| `rates` | 近 5 分钟：`rpm`、`tpm`（含缓存 Tokens）、`error_rate`（比例，关监控为 null）、`upstream_429_count`、`upstream_529_count`（关监控为 null）、`ops_monitoring_enabled`、`errors_available`、`rpm_includes_errors`、`start_time`、`end_time` |
| `hourly` | `today[]`、`yesterday[]`，每点 `date`（`YYYY-MM-DD HH:00`）、`actual_cost`、`requests`、`total_tokens`、`account_cost`；没有用量的小时不出现 |
| `ops` | 近 5 分钟 overview 精简：`health_score`、`sla`、`error_rate`、`upstream_429_count`、`upstream_529_count`、`request_count_total`、`token_consumed`；关监控 = `disabled / OPS_DISABLED` |
| `alerts` | `firing_count`、`by_severity{P0..P3}`（含被静默的 firing）、`top[]`（最新 5 条 firing 事件，完整 `OpsAlertEvent`）；关监控 = disabled |
| `availability` | D02 汇总：`collected_at`、`totals{total, available, error, overloaded, rate_limited, temp_unschedulable, paused, inactive, stopped}`、`groups[]`（含 `shortage`）、`accounts[]`（只含 error / overloaded / rate_limited / temp_unschedulable，最多 100 个）、`accounts_truncated`；**不受运维开关影响** |
| `channels` | `total`、`healthy`、`warning`、`critical`、`unknown`（stale 计入 unknown）、`coverage_state`、`collector_state`；渠道监控关闭 = `disabled / CHANNEL_MONITOR_DISABLED` |

**附加请求（与 home 并发，各自独立）**：

| 用途 | 请求 | 条件 |
|---|---|---|
| 今日成功率（今日区 / 平静布局） | `GET /api/v1/admin/ops/dashboard/overview?start_time=<服务器时区今天 00:00，RFC3339>&end_time=<now>` → `sla` | 运维监控开启；关闭时不请求 |
| 错误账号的结构化错误 | `GET /api/v1/admin/accounts?status=error&lite=1&page_size=100` → 每项 `id`、`error_at`、`error_status_code`、`error_kind`、`error_summary`（`dto/types.go:378-381`；status-summary 的 `accounts[]` 只有 `error_message`，没有这几项） | `availability.totals.error > 0` 且有 `accounts.structured_error`；按 id 与 availability 的错误账号对齐 |

过载账号不需要额外请求：后端只在上游返回 529 时设置过载（`service/ratelimit_service.go:358-363` → `handle529` → `SetOverloaded`，`:1968-1999`；`SetOverloaded` 在 `internal/` 里只有这一个调用点），原因固定写“上游 529”（20 §0.2）。

**逐接口退路（没有 `dashboard.home`，或 home 本身 404 / 网络失败）**：各区块独立加载、独立失败。

| 区块 | 退路请求 | 口径说明 |
|---|---|---|
| stats | `GET /api/v1/admin/dashboard/stats` → `today_*`、`stats_updated_at`、`stats_stale`；`today_actual_cost` / `today_account_cost` 缺失的旧站点沿用现有 `dashboardCostSnapshot()`（`dashboard/snapshot-v2` 只开 `include_stats`） | 同 home |
| 昨日同时 | `GET /api/v1/admin/dashboard/trend?start_time=<服务器时区昨天 00:00>&end_time=<昨天此刻>&granularity=day&timezone=<server_timezone>` → `trend[0].actual_cost`；`stats_stale=true` 时 end_time 改为 `stats_updated_at − 24h` | 附录 A S10 |
| rates | ① `GET /api/v1/admin/dashboard/rates?window=5m`（`dashboard.rates`）；② `GET /api/v1/admin/ops/dashboard/overview?time_range=5m`：窗口秒数 = `end_time − start_time`，RPM = `request_count_total × 60 ÷ 秒数`，TPM = `token_consumed × 60 ÷ 秒数`，错误率 = `error_rate`；③ ②返回 404 `OPS_DISABLED` 时：RPM = `dashboard/stats.rpm`（近 60 秒成功上游转发数；`rpm_available == false` 显示 `—`），TPM = `dashboard/stats.tpm`（**只含 input + output，不含缓存**），错误率 `—` | ③ 的 TPM 口径与统计分析图不同，见 1.3.2 脚注 |
| hourly | `GET /api/v1/admin/dashboard/trend?start_date=<昨天>&end_date=<今天>&granularity=hour&timezone=<server_timezone>` → `trend[]` 按日期前缀拆今天 / 昨天 | 同 home |
| ops | `GET /api/v1/admin/ops/dashboard/overview?time_range=5m` → `health_score`、`upstream_429_count`、`upstream_529_count` | 404 `OPS_DISABLED` → disabled |
| alerts | `GET /api/v1/admin/ops/alert-events/counts`（`ops.alert_event_counts`）+ `GET /api/v1/admin/ops/alert-events?status=firing&limit=5`；没有 counts 时 `alert-events?status=firing&limit=500` 自己数 | 404 `OPS_DISABLED` → disabled |
| availability | `GET /api/v1/admin/accounts/status-summary?include_accounts=true`（`accounts.status_summary`）；再旧的站点：`GET /api/v1/admin/groups/all?include_inactive=true`（`account_count`、`active_account_count`、`rate_limited_account_count`，字段缺省按 0）+ `GET /api/v1/admin/accounts?lite=1&page_size=1000` 本地按 D02 的 state 顺序分档；分组“可用不足”按“available < total × 0.5 或 available = 0”判定 | D02 退路 |
| channels | `GET /api/v1/admin/channel-monitor-v2/overview?range=90m` → 按 `items[].current_status.state` 计数（healthy / warning / critical，其余算未知）；403 `CHANNEL_MONITOR_DISABLED` → disabled | 必须显式传 `range`（附录 B L11） |

本机来源（不调接口）：充值 / 退款待核对 = `AppModel.pendingBalances` 中属于当前站点的记录（30 §3）；兑换码生成待核对 = 60 §11.2 的本机记录 `PendingRedeemBatch`。

### 1.3 字段 → 显示映射

#### 1.3.1 导航栏与整页

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 大标题 | 当前站点名 | 原样 | — |
| 副标题·日期 | 服务器时区的今天 | `M月d日 EEE`（中文星期“周五”） | — |
| 副标题·更新 | 最近一次所有区块都成功的时间 | “刚刚更新” / “N 分钟前更新”；有区块失败时改为“部分数据未更新” | 首次加载中：“正在加载…” |
| 副标题·时区 | `server_utc_offset` ≠ 手机偏移时 | 追加“· 按 UTC+8” | — |
| 统计新鲜度 | `stats.stats_stale == true` | 今日区标题 meta 改为“统计更新于 HH:MM”（`stats_updated_at`） | — |
| 运维监控未开启行 | `rates.ops_monitoring_enabled == false`，或 ops / alerts 段 `disabled / OPS_DISABLED` | 6 格正下方一行 neutral 提示：“运维监控未开启 · 错误率与告警不可用，RPM 只计成功请求”，右侧「开启」（§7.2）；`disabled_reason == config_off` 时文案改为“运维监控已在服务器配置中关闭”，没有按钮 | — |

#### 1.3.2 顶部 6 格（3 × 2，顺序固定）

标签只写名字，**不写“近 5 分钟”**（评审第 1 条；口径不变）。每格是一个 `NavigationLink`；大数字 `.minimumScaleFactor(0.5).lineLimit(1)`。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 今日实际扣费 | `stats.today_actual_cost` | 金额 `$1,284.50`；右侧小字涨跌 `▲7.9%` / `▼3.2%` = `today_actual_cost ÷ yesterday_same_time_actual_cost − 1`，1 位小数，墨色 | stats 不可用 → `—`；昨日值 null 或 0 → 不显示涨跌 |
| 请求 | `stats.today_requests`（今天 00:00 起已计费请求） | 紧凑数 `18.2K` | `—` |
| 错误率 | `rates.error_rate`（近 5 分钟，`error_count_sla ÷ (success_count + error_count_sla)`） | 比例 → `0.9%` | `error_rate == null`（关监控，Q2）或 rates 不可用 → `—` |
| 利润 | `stats.today_actual_cost − stats.today_account_cost` | 金额，亏损显示 `−$`，不加 `+`；叫“利润”，不叫差额 / 毛利 | 任一缺失 → `—` |
| RPM | `rates.rpm`（近 5 分钟：`request_count × 60 ÷ 300`；开监控时 request_count = 成功 + 错误） | RPM 规则 `46` | `—` |
| TPM | `rates.tpm`（近 5 分钟：`token_consumed × 60 ÷ 300`，**含缓存 Tokens**，与统计分析“RPM / TPM 趋势”同口径） | 紧凑数 `240K` | `—` |

- 无障碍：每格 `accessibilityLabel` = “今日实际扣费 $1,284.50，比昨天同时上升 7.9%。打开统计分析”；RPM / TPM 为“… 打开 RPM 趋势”。
- 退路③（关监控 + 旧服务端）时 TPM 不含缓存：TPM 格下沿加一个 `*`，运维监控未开启行改为“… · TPM 不含缓存 Tokens”。B01 上线的站点不会走到这里（rates 的 TPM 不受开关影响）。

#### 1.3.3 待处理（合并队列，DECISIONS 第 2 轮 Q3）

区块标题“待处理”，meta “N 项”（N = 行数），序号“壹”。行顺序固定：

1. 告警行（每条 firing 事件一行）→ 2. 错误账号（每个一行）→ 3. 过载账号（每个一行）→ 4. 受限（合并成一行）→ 5. 可用不足分组（合并成一行）→ 6. 充值 / 退款待核对（每条一行）→ 7. 兑换码生成待核对（每批一行）。

**告警行**（来源 `alerts.top`，按 P0 → P3、同级 `fired_at` 新在前；见 §6.3 的通用文案函数）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态胶囊 / 图标 | `alertTone(severity)`；铃铛图标 | — | — |
| 标题 | `rule.name` + 空格 + `metric_value`（按指标单位） | “标准组错误率 5.2%” | `rule` 为 null：`title` 去掉开头的 `P1: ` 前缀；`metric_value` 缺失不拼 |
| 右侧徽章 | `severity` | `P1` | — |
| 说明行 | 阈值 `rule.threshold ?? threshold_value`（按单位，0.4）+ `fired_at` 相对时间；`silence != null` 时追加 | “阈值 5% · 12 分钟前触发 · 已静默” | 两个阈值字段都缺失时只写“12 分钟前触发” |
| 另有告警 | `firing_count − top.count > 0` | 末尾追加一行“另有 N 条告警中”，tone 取未显示部分的最高级别（`by_severity` 减去已显示的） | — |

**账号行的通用规则**（错误、过载、受限三类）：行归入哪一类看 D02 的 `state`（服务端判定）；状态词、色调、倒计时、“已停止调度”标记和原因短句一律取 20 §0.2 的 `AccountDisplayState`（与 D02 判定顺序一致，可直接互用，20 §10.1），本章不另做推导、不另设 `error_kind` 词表。这样同一个账号在首页和账号页显示的原因相同。

**错误账号行**（来源 `availability.accounts` 中 `state == "error"`，`error_at` / `error_summary` 补自 `admin/accounts?status=error&lite=1`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | critical；八角形 | — | — |
| 标题 | `name` | 原样 | — |
| 徽章 | — | “错误” | — |
| 原因（最多 2 行） | `AccountDisplayState` 的原因短句：`error_summary`（≤ 160 字，已脱敏） | 原样 | `error_summary` 为空或没有 C02 字段：“上游返回异常”；**不显示 `error_message` 原文**（20 §0.2） |
| 底行左 | 平台显示名 + `error_at` 相对时间 | “OpenAI · 1 分钟前” | `error_at` 为 null（存量错误）或没有 C02 字段：只写平台 |
| 底行右 | 「测试」小按钮（视觉 30pt，`.frame(minHeight: 44)` + `.contentShape`，List 内 `.buttonStyle(.borderless)`） | — | — |

**过载账号行**（`state == "overloaded"`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | critical；火焰 | — | — |
| 标题 | `name` | — | — |
| 徽章 | “过载中” + 倒计时 `overload_until − now` | “过载中 1:12” | 倒计时 ≤ 0 显示 `0:00`，按 20 §0.2 重新推导并触发一次刷新 |
| 说明行 | “已停止调度”标记（`stopped == true`）+ 原因短句 + 平台 | “已停止调度 · 上游 529 · 智谱 GLM” | 原因短句固定“上游 529”（过载只来自 `handle529`，见 1.2），不需要额外请求 |

**受限行**（`state ∈ {rate_limited, temp_unschedulable}` 合并为一行）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | caution；沙漏 | — | — |
| 标题 | 账号数 | “受限 N 个账号” | — |
| 右侧 | 最早解除：`min(rate_limit_reset_at, temp_unschedulable_until) − now` | “最早 4:37” | — |
| 第 2 行 | 账号名用“、”连接，单行尾部截断 | — | — |
| 第 3 行（有 `stopped == true` 时） | “已停止调度 · ” + 这些账号名 | 标记在前，只截断名字 | 没有则不显示 |
| 截断提示 | `availability.accounts_truncated == true` | 第 2 行末尾“等”，标题数字改用 `totals.rate_limited + totals.temp_unschedulable` | — |

只有模型限流（`model_rate_limits`）而 `state == available` 的账号不进队列（账号详情里显示）。

**可用不足分组行**（`availability.groups` 中 `group_status == "active"`、`shortage.is_short == true`，且组内 `error + overloaded + rate_limited + temp_unschedulable > 0`；合并为一行，见未决问题 Q1）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 | 任一分组 `available == 0` → critical，否则 caution | — | — |
| 标题 | 分组数 | “可用不足 N 个分组” | — |
| 第 2 行 | 每组 `group_name available/total`，按可用比例升序，“ · ”连接 | “企业专线 0/2 · 标准组 1/3” | — |

一个账号属于多个分组时会计入每个分组（D02），分组之间不相加。

**充值 / 退款待核对行**（本机 `pendingBalances`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | caution；文档勾 | — | — |
| 标题 | `operation`：add “充值结果待核对”、subtract “退款结果待核对”、set “余额设置结果待核对” | — | — |
| 右侧金额 | `amount`（Decimal） | 金额 | — |
| 说明行 | 用户名（本机记录里保存的显示名）+ 提交时间相对值 | “周婷 · 2 小时前 · 未确认是否入账” | 需要 `PendingBalanceOperation` 增加 `createdAt`、`userDisplayName`（30 §3.7） |

**兑换码生成待核对行**（60 §11.2 的本机记录 `PendingRedeemBatch`，读 `count`、`total`、`createdAt`）：标题“兑换码生成结果待核对”；右侧合计金额（余额类才有，并发 / 订阅 / 邀请类 `total == nil` 不显示）；说明行“{count} 个 · {createdAt 相对时间} · 未确认是否生成”，如“20 个 · 5 分钟前 · 未确认是否生成”（已定首页 `v-today.jsx` `VtRedeemRow`；与 60 §11.3 横幅同用“生成”）。

#### 1.3.4 今日区（序号“贰”，meta “00:00 起”）

这一区只放今日口径的数，近 5 分钟的数（RPM、TPM、错误率、健康分）不放进来。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 图表标题 | — | “每小时实际扣费”，右侧图例“今天（实心柱）/ 昨天（虚线）” | — |
| 图表 | 今天：`hourly.today[].actual_cost` 按小时 0…当前小时画柱，当前小时柱高亮；昨天：`hourly.yesterday[]` 24 小时虚线；缺失小时按 0 | X 轴只标“0时 6时 12时 18时”与“现在”，无 Y 轴；`accessibilityLabel` “每小时实际扣费，今天与昨天对比” | hourly 不可用 → 图表区一行“每小时数据加载失败 · 重试”，下面三格照常 |
| 账号成本 | `stats.today_account_cost` | 金额 | `—` |
| 标准 | `stats.today_cost` | 金额 | `—` |
| 利润 | 同 6 格 | 金额 | `—` |
| Tokens | `stats.today_tokens`（含缓存） | 紧凑数 | `—` |
| 成功率 | 今日 overview 的 `sla`（今日 SLA 口径，与统计分析“今天”同一数） | 比例 → `98.3%` | 关监控 → `—`（附录 B L23，不能显示 100% 或 0） |
| 更多统计 | — | “更多统计”，右侧灰字“模型 · 用户 · 分组排行” | — |

三格只写“账号成本 / 标准 / 利润”文字标签，不画线条图例（图上没有这两条线）。

#### 1.3.5 运行区（序号“叁”，不写窗口）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 健康分 | `ops.health_score`（0–100） | 刻度条 + 数字 + 词：≥ 90 “良好”（ok）、≥ 60 “风险”（caution）、< 60 “异常”（critical） | ops disabled → 数字 `—`，词“运维监控未开启”；ops error / timeout → `—` + 重试 |
| 错误率 | 同 6 格 `rates.error_rate` | `0.9%` | `—` |
| 上游 429 | `rates.upstream_429_count` | 整数 | null → `—` |
| 529 | `rates.upstream_529_count` | 整数 | null → `—` |
| 渠道行 | `channels.healthy / warning / critical / unknown` | “可用 3 · 性能下降 1 · 不可用 1 · 未知 1”，计数为 0 的项不写；性能下降用 caution 字色、不可用用 critical 字色 | disabled → “渠道监控未开启”；error / timeout → “渠道状态加载失败” |

### 1.4 交互与写操作

本页本身只有导航与「测试」入口，没有直接写操作：

- 「测试」：打开 20 §4 的测试连接 sheet（`.accountTest(id:)`）；sheet 结束（无论成败）后对首页做一次 `nocache=1` 刷新（测试通过时后端会自动恢复账号状态）。
- 运维监控「开启」：§7.2。
- 告警的手动解决 / 静默只在告警详情与监控 · 告警段里做（§7.1）。
- 不做乐观更新；其他页面完成写操作后通过 `LiveOpsStore` 通知首页刷新（手动解决后告警行立即消失：先本地把该事件状态置为 `manual_resolved`，再后台刷新校正）。

### 1.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 6 格显示占位骨架（不是 0）；待处理区显示“正在加载…” | — |
| home 整体失败（网络 / 5xx / 超时） | 各区块显示上次成功的值（如有）+ 副标题“部分数据未更新”；完全没有数据时整页空态“无法连接到站点” + 「重试」 | 自动在下一个轮询周期重试；连续失败的退避按 00 §4.6；超时按 00 §2.3 的 `dashboard/home` 一行 |
| 某段 `status == timeout`（`SECTION_TIMEOUT`） | 该区块保留旧值或 `—`，标题旁“加载超时” | 下次轮询自动重试（带 error / timeout 段的响应不进服务端缓存） |
| 某段 `status == error` | 同上，文案“加载失败”；reason 为 `INTERNAL_ERROR`、`SERVICE_UNAVAILABLE`、`OPS_REPO_UNAVAILABLE` 等时不显示原文 | 区块内「重试」= 整个 home 带 `nocache=1` 重拉 |
| `ops` / `alerts` 段 `disabled / OPS_DISABLED` | 1.3.1 的运维监控未开启行；健康分 `—`；告警行不出现 | §7.2 |
| `channels` 段 `disabled / CHANNEL_MONITOR_DISABLED` | 渠道行“渠道监控未开启”（不可点） | — |
| `availability` 不可用 | 待处理区内一行 neutral “账号状态读取失败 · 重试”；**不进入平静布局** | 重试 |
| `alerts` error / timeout（运维开启） | 待处理区内一行 neutral “告警读取失败 · 重试”；不进入平静布局 | 重试 |
| 400 `INVALID_TIMEZONE` | 不传 `timezone` 立即重试一次，并记录日志 | — |
| 400 `INVALID_INCLUDE` | 程序错误：去掉 `include` 重试 | — |
| 401 / 403 / 423 等鉴权类 | 按 00 §2.4、§2.6、§2.7 与 §3.2 处理 | — |
| 403 `ACCESS_TOKEN_READ_ONLY` | 本页只读，不会出现 | — |

### 1.6 刷新策略

通用节奏（只在前台、各区块独立定时、回到前台立即刷新、失败退避、离开即取消）按 00 §4.6，下面只写本页的取值与特有规则。

- 前台轮询 **60 秒**（00 §4.6 的默认值，DECISIONS：约 60 秒），条件 = 本 Tab 可见且 `scenePhase == .active`；离开 Tab 或进后台立即取消在途请求（沿用现有 `cancelLoads()` 做法）。
- 倒计时每秒走：用 `TimelineView(.periodic(from: .now, by: 1))` 只重绘倒计时文本，不重拉数据；任一倒计时归零时 10 秒内最多触发一次 home 刷新。
- 下拉刷新：`dashboard/home?…&nocache=1`（后端 `nocache` / `force_refresh` 绕过 15 秒缓存，并透传给渠道监控的 refresh），同时重拉附加请求。
- ETag：按 0.2 末段与 00 §4.2，由 `ConditionalCache` 透明处理（轮询和下拉刷新都一样，不受 `lists.etag` 约束）；304 时页面照常拿到数据，“更新于”刷新为现在。服务端 ETag 排除了 `generated_at`、rates / ops 的起止时间、`availability.collected_at`，但 rates 每 5 秒在变，有流量时 304 少见，属正常。
- 本页没有 `since_id`（不是日志列表）。
- 附加请求：今日成功率随 home 每 60 秒；错误账号结构化字段只在错误账号集合变化时重拉。

### 1.7 对现有代码的改动点

| 位置 | 改法 |
|---|---|
| `NativeApp/Features/DashboardView.swift` · `DashboardView` | 整体替换为新的 `HomeView`：6 格 + 待处理 + 今日 + 运行；平静布局切换见 §2。现有“今日请求 / 今日 Tokens / 总 Tokens / 性能指标”四卡、“运行健康”“运行监控”两个 GroupBox 删除；三个 30 秒轮询 `.task` 合成一个 60 秒轮询 |
| 同文件 · `DashboardTrendChart` | 首页不再放可缩放的大趋势图（DECISIONS：首页不全部显示，二级页显示全部），整体移到统计分析（40 §1）复用；首页换成不可交互的小图 `HomeHourlyChart`（Swift Charts：`BarMark` 今天 + `LineMark` 虚线昨天） |
| 同文件 · `DashboardLoadState` | 保留并挪到 `NativeApp/Views/LoadState.swift`，内部存 `BlockState` |
| 同文件 · `costBreakdown` / `costValue` / `needsCostSnapshot` | 首页不再按绿 / 黄着色金额（计费数字不着色）；“账号成本缺失时取 snapshot-v2”的逻辑移到 `LiveOpsStore` 的 stats 退路里 |
| 同文件 · `performanceCard` | 删除；RPM / TPM 进 6 格，读 `rates` |
| `Sources/Sub2Core/APIClient.swift` · `dashboard()` | 保留作退路；新增 `dashboardHome(timezone:include:noCache:) -> DashboardHome`（ETag / 304 由 `ConditionalCache` 透明处理，0.2 末段） |
| 同文件 · `dashboardTrend()` | `dateRange(days:)` 用的是 `TimeZone.current`，改为接收服务器时区（今日 / 昨日按服务器天界） |
| 同文件 · `dashboardMonitoring()`、`OpsReply`、`Models.swift` · `OpsSnapshot` | 删除，换成 `opsOverview(timeRange:)` / `opsOverview(start:end:)` 返回完整 `OpsOverview`（§4 也用） |
| 同文件 · `request(_:…)` | 条件请求按 00 §9.1（`makeRequest` 带 `If-None-Match`）与 §9.7（`Sources/Sub2Core/ConditionalCache.swift`）统一实现；本章各方法直接返回模型，不另定义 `Conditional<T>` / `.notModified` |
| 同文件 · 新增 | `dashboardRates(window:)`、`accountStatusSummary(includeAccounts:groupID:)`、`errorAccounts()`（`accounts?status=error&lite=1&page_size=100`）、`accountsRanking(limit:timezone:)` |
| 新文件 `Sources/Sub2Core/DashboardHome.swift` | `DashboardHome`、`HomeSection<T>`（`status` 不认识的值按 error 处理）、`HomeStats`、`LiveRates`、`HomeHourly`、`HomeOps`、`HomeAlerts`、`HomeAvailability`、`HomeChannels`；金额字段用 Decimal 解码（沿用 `KeyedDecodingContainer.optionalDecimal`） |
| 新文件 `Sources/Sub2Core/AccountStatusSummary.swift` | `AccountStateCounts`、`AccountStatusGroupSummary`（含 `Shortage`）、`AccountStatusItem`；与 20 §10.3 是同一个文件 |
| 复用 `Sources/Sub2Core/AccountDisplayState.swift`（20 §0.2 新增） | 账号行的状态词、色调、倒计时、“已停止调度”、原因短句都调它；本章不新增账号状态推导或 `error_kind` 词表 |
| 新文件 `Sources/Sub2Core/HomePresentation.swift` | 纯函数：`tickerCells(stats:rates:)`、`attentionItems(…) -> [AttentionItem]`（1.3.3 的顺序与合并规则；账号行文案取 `AccountDisplayState`）、`isCalm(…)`（§2.2）、`yesterdayChange(…)`；全部可单测 |
| `Sources/Sub2Core/DashboardPresentation.swift` | 新增 0.4 的格式函数；`rpmValue` / `performanceWindow` 不再被首页使用（统计分析若不用可删） |
| `NativeApp/Session/AppModel.swift` | 新增上述接口的包装与 UI 测试分支；新增 `LiveOpsStore` 的创建（随 `sessionGeneration` 重建） |
| `NativeApp/Session/DemoData.swift` | UI 测试数据：home 全 ok、ops disabled、availability error、hourly timeout、calm、calm + 限流 |
| 新视图文件（建议） | `NativeApp/Features/Home/HomeView.swift`、`HomeTicker.swift`、`HomeAttentionList.swift`、`HomeTodaySection.swift`、`HomeRunSection.swift`、`HomeHourlyChart.swift`、`OpsDisabledNotice.swift`（§7.2 共用） |
| 测试 | `Tests/Sub2CoreTests/HomePresentationTests.swift`（6 格、`—`、利润为负、涨跌、TPM 退路标记）、`DashboardHomeDecodingTests.swift`（部分成功、未知 status、缺段）、`AttentionItemsTests.swift`（顺序、合并、截断、stopped 第 3 行；错误行原因为空时“上游返回异常”、过载行原因“上游 529”，与 `AccountDisplayState` 输出一致）；现有 `DashboardRPMTests`、`OverviewPresentationTests` 随 `performanceCard` 删除而更新 |

---

## 2. 概览 Tab · 平静布局

### 2.1 入口与导航

- 与 §1 同一个页面、同一个数据；满足 2.2 的条件时整屏换成平静布局（`withAnimation(.easeInOut)` 交叉淡入），条件不满足时换回常规布局。
- 导航栏同 §1.1。去向：6 格同 §1；“自动恢复中”行 → `router.select(.accounts(filter: .limited))`；“按账号”行 → 账号详情 `.account(id:)`；“更多统计” → `.analytics()`；渠道行 → `router.select(.monitor(segment: .channels))`。

### 2.2 进入条件（全部满足才进入）

1. `availability` 段 ok（读不到账号状态时不进入）；
2. `totals.error == 0` 且 `totals.overloaded == 0`；
3. 告警：`alerts` 段 ok 且 `firing_count == 0`（被静默的 firing 也算，仍需手动解决），或 `alerts` 段 `disabled / OPS_DISABLED`（运维监控关闭时不阻止平静布局，但页面显示 1.3.1 的运维监控未开启行）；
4. 没有本机的充值 / 退款待核对与兑换码生成待核对；
5. 没有 1.3.3 的“可用不足分组”行。

限流中、临时不可调度（自动恢复类）不阻止平静布局，只加一行“自动恢复中”（DECISIONS 第 2 轮 Q4）。

### 2.3 数据来源

同 §1.2，另加：

- 按账号前 4：`GET /api/v1/admin/dashboard/accounts-ranking?limit=4&timezone=<server_timezone>`（`dashboard.accounts_ranking`；默认今天）→ `ranking[]` 每项 `account_id`、`account_name`、`platform`、`requests`、`actual_cost`；只在平静布局显示时请求。

### 2.4 字段 → 显示映射（自上而下）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态旗 | 有受限账号 → “无需处理”，否则 “全部正常”；后接 `totals.available` | “✓ 全部正常 · 15 个账号可调度”（ok 色） | — |
| 6 格 | 同 1.3.2 | 同 | 同 |
| 运维监控未开启行 | 同 1.3.1 | 同 | — |
| “自动恢复中”区（meta “N 个”） | 有受限账号时显示，内容 = 1.3.3 的受限行（含“已停止调度”第 3 行） | 同 | 没有受限账号不显示 |
| “每小时实际扣费”区（序号“壹”，meta “00:00 起”） | 同 1.3.4 的图表，但今天画**折线 + 面积**、当前点圆点，昨天虚线（设计稿 `VtStage`：ticker 方案下用折线） | 同 | 同 |
| 三格 | 账号成本 / 标准 / 利润，同 1.3.4 | 同 | 同 |
| 用量行 | Tokens、成功率（今日 SLA），同 1.3.4 | 同 | 同 |
| “按账号”区（序号“贰”，meta “今日实际扣费 · 前 4”） | `ranking[]` 前 4，只取 `actual_cost > 0` 的 | 每行：账号名 + 右侧金额；下方比例条（宽度 = 本行 ÷ 第一行）；说明“{平台} · {requests 千分位} 次请求” | 接口不可用或没有 > 0 的项：整区隐藏 |
| 更多统计行 | — | 同 1.3.4 | — |
| “渠道”区（序号“叁”） | `channels.total` 与四档计数 | 标题“8 个渠道”，说明同 1.3.5 渠道行 | disabled → “渠道监控未开启” |

平静布局没有“运行”区与健康分（健康分只在常规布局的运行区与监控 · 概况）。

### 2.5 交互与写操作

无写操作。

### 2.6 状态

同 §1.5；ranking 失败只影响“按账号”区（隐藏），不改变布局。

### 2.7 刷新策略

同 §1.6；ranking 随 home 每 60 秒刷新（仅平静布局可见时）。

### 2.8 对现有代码的改动点

新增 `NativeApp/Features/Home/HomeCalmView.swift`（状态旗、自动恢复中、折线小图、按账号排行）；`HomePresentation.isCalm(...)` 实现 2.2，单测覆盖：只有限流 → 平静；有静默中的 firing → 不平静；运维关闭 + 无异常 → 平静；availability 失败 → 不平静；有本机待核对 → 不平静。

---

## 3. 告警详情页

### 3.1 入口与导航

- 入口：首页告警行；监控 · 告警段的每一行；推送“告警触发”点按（00 §7.5，§0.7-4）。路由 `.alert(id:)`，推入当前 Tab 的导航栈（§0.7-2）。
- 导航栏：返回 + 标题“告警”，副标题 “{severity} · {范围文案}”（如“P1 · 分组 · 标准组”）。
- 去向：范围区的分组行 → 分组详情 `.group(id:)`（50 §2、§8）；错误请求行 → 使用记录 `.logs(scope: .errors / .upstream, group: id)`（40 §6）；平台渠道行 → `router.select(.monitor(segment: .channels))`；服务器行 → `router.select(.monitor(segment: .overview))`。

### 3.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 事件 | `GET /api/v1/admin/ops/alert-events/:id` | 进入时先用列表里带来的事件对象渲染，再用本请求校正；字段 `id`、`rule_id`、`severity`、`status`、`title`、`metric_value`、`threshold_value`、`dimensions{platform?, group_id?}`、`fired_at`、`resolved_at`、`silence{id, until}`、`rule{id, name, metric_type, operator, threshold, window_minutes, sustained_minutes, deleted}`、`group_name`、`resolved_by_user_name` |
| 规则摘要（旧服务端） | `GET /api/v1/admin/ops/alert-rules` | 没有 `ops.alert_event_details` 时按 `rule_id` 匹配；规则已删 → 显示 `description` 原文 |
| 分组范围 | `LiveOpsStore` 里的 `availability.groups` 中 `group_id` 那一项；没有时 `GET /api/v1/admin/accounts/status-summary?group_id=<id>` | 不受运维开关影响 |
| 错误请求条数 | `GET /api/v1/admin/ops/request-errors?group_id=<id>&time_range=24h&page_size=1` → `total`（`metric_type` 为 `error_rate` / `success_rate`）；`upstream_error_rate` 用 `GET /api/v1/admin/ops/upstream-errors?group_id=<id>&time_range=24h&page_size=1` | 只在事件有 `group_id` 时 |
| 平台范围 | `LiveOpsStore` 的渠道列表（§5）里 `platform` 相同（忽略大小写）的项；没有缓存时 `GET /api/v1/admin/channel-monitor-v2/overview?range=90m` | 只在事件有 `platform`、没有 `group_id` 时 |

全部需要运维监控开启（事件接口受开关控制）。

### 3.3 字段 → 显示映射

**状态卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态卡胶囊 | firing → `alertTone`；否则无色 | — | — |
| 大徽章 | `status` | firing “告警中”、resolved “已恢复”、manual_resolved “已手动解决” | 未知值：原样 |
| 徽章右侧 | `severity` + `fired_at` 时刻 | “P1 · 09:29 触发” | — |
| 规则名 | `rule.name` | 原样 | `rule` 为 null：`title` 去掉 `P1: ` 前缀 |
| 大数字 | `metric_value`（§6.3 单位） | “5.2%” | 缺失 `—` |
| 大数字旁 | “阈值 {rule.threshold ?? threshold_value}” + `rule.window_minutes > 0` 时“ · 近 {N} 分钟” | “阈值 5% · 近 5 分钟”（规则自己的窗口，保留，BACKLOG 末条） | 两个阈值字段都缺失时不写“阈值”；`rule` 为 null 时不写窗口 |
| 静默说明（firing 且 `silence != null`） | `silence.until` | “⌛ 已静默至 10:41”（跨天写“明天 09:41” / “10月23日 09:41”） | — |
| 结束说明（非 firing） | resolved：`resolved_at` → “1 小时前恢复”；manual_resolved：“{resolved_at} · 由 {resolved_by_user_name} 手动解决” | 例：“昨天 22:10 · 由 admin 手动解决” | 没有解决人：“已手动解决” |

**按钮行**（只在 `status == firing` 时显示）：「手动解决」（主）、「静默…」（`silence == null`）/「改静默时长…」（`silence != null`）。旧服务端且事件没有 `platform` 时隐藏静默按钮（§7.1）。

**范围区**（序号“壹”）

| 事件维度 | 行 | 内容 |
|---|---|---|
| 有 `group_id` | 分组行（可点） | 标题 `group_name`；右侧“{available}/{total} 可用”；说明“{分组平台} · N 个账号受影响”（N = error + overloaded + rate_limited + temp_unschedulable），N = 0 写“账号都可调度” |
| 有 `group_id` 且指标是错误类 | 错误请求行（可点） | 标题“错误请求”（`upstream_error_rate` 为“上游错误”）；右侧“近 24 小时 N 条” |
| 只有 `platform` | 渠道行（可点） | 标题“{platform 显示名} 渠道”；右侧该平台渠道中最差状态的词（可用 / 性能下降 / 不可用 / 未知，非可用着色）；说明“N 个分组渠道 · 最低可用率 x%” | 
| 都没有，且指标是 `cpu_usage_percent` / `memory_usage_percent` / `concurrency_queue_depth` | 服务器行 | 标题“服务器”，右侧灰字“监控 · 概况” |
| 都没有，其他指标（全站规则） | 全站行 | 标题“全站”，右侧灰字“监控 · 概况”；错误类指标再加一行“错误请求 · 近 24 小时 N 条”（不带分组筛选） |

找不到该平台的渠道：说明写“没有这个平台的渠道探测”。分组已删除（`group_name` 仍有，availability 里没有）：右侧写“分组已删除”，不可点。

**规则区**（序号“贰”，键值表）

| 键 | 值 | 空值 |
|---|---|---|
| 条件 | “{指标名} {运算符} {阈值}”，阈值 = `rule.threshold ?? threshold_value`，如“错误率 > 5%” | 规则缺失（没有运算符）→ `description` 原文 |
| 窗口 | “{window_minutes} 分钟” | 0 或缺失 → `—` |
| 级别 | `severity` | — |
| 触发 | “今天 09:29” | — |
| 结束（非 firing） | `resolved_at` 同格式 | `—` |

`rule.deleted == true` 时条件行后加“（规则已删除）”；指标不认识或是 p95 / p99 且缺 `ops.alert_latency_metrics` 时条件行后加“（不受支持，不会触发）”。

### 3.4 交互与写操作

见 §7.1（手动解决、静默、改时长、结束静默）。成功后：本页用返回结果 / 重新 GET 刷新；`LiveOpsStore` 同步更新告警列表、计数与首页（手动解决后首页告警行立即消失）。

### 3.5 状态

| 情况 | 显示 |
|---|---|
| 加载中（没有列表带来的对象） | 状态卡骨架 |
| 404 `OPS_ALERT_EVENT_NOT_FOUND` | 空态“这条告警不存在或已被清理” + 「返回」 |
| 404 `OPS_DISABLED` | 空态“运维监控未开启” + §7.2 的开启入口 |
| 范围区子请求失败 | 只该行显示“加载失败 · 重试”，状态卡与规则区照常 |
| 400 `Invalid event ID` | 程序错误，返回上一页 |

### 3.6 刷新策略

进入时拉一次；可见时 60 秒轮询事件；下拉刷新重拉事件与范围数据；写操作成功后立即重拉。

### 3.7 对现有代码的改动点

现有 App 没有告警页。新增 `NativeApp/Features/Monitor/AlertDetailView.swift`；模型与文案放 `Sources/Sub2Core/OpsAlerts.swift`（`AlertEvent`、`AlertEventRule`、`AlertSilenceRef`、`AlertCounts`、`AlertSilence`）与 `Sources/Sub2Core/AlertPresentation.swift`（§6.3 的单位、运算符、范围、标题、since 文案）；`APIClient` 新增 `alertEvent(id:)`、`alertRules()`、`requestErrorCount(groupID:range:)`、`upstreamErrorCount(groupID:range:)`。解码注意：`silence` 键存在与否要区分（用 `container.contains(.silence)` 记一个 `silenceSupported` 标记）；`AlertEvent` 保留顶层 `thresholdValue`（`threshold_value`），`AlertEventRule` 保留 `threshold`，显示统一走 `AlertPresentation.threshold(event) = rule?.threshold ?? thresholdValue`。

---

## 4. 监控 Tab · 概况

### 4.1 入口与导航

- 入口：底部 Tab 第 4 个「监控」；分段控件“概况 / 渠道 / 告警”（DECISIONS 第 2 轮）。默认段 = 概况（见未决问题 Q4），本次会话内记住上次所选段；从首页“渠道”行 / “另有 N 条告警”进入时由 `router.select(.monitor(segment:))` 指定段（§0.7-4）。
- 导航栏：大标题“监控”，副标题随段变化：概况“运行与服务器 · 刚刚更新”、渠道“渠道 · 近 90 分钟 · 刚刚更新”、告警“告警 · N 条进行中”。右上 `···`：「刷新」；站长且运维开启时再加「关闭运维监控…」（§7.2，见未决问题 Q6）。
- 分段计数：渠道段 = 渠道列表里 critical + warning 的数量（0 不显示）；告警段 = 告警中条数（0 不显示）。
- 去向：“告警中 N 条”行 → 本页切到告警段（不走 router）。

### 4.2 数据来源

全部受运维监控开关控制（404 `OPS_DISABLED`）。

| 区块 | 请求 | 用到的字段 |
|---|---|---|
| 运行 | `GET /api/v1/admin/ops/dashboard/overview?time_range=5m` | `health_score`、`error_rate`、`upstream_429_count`、`upstream_529_count`、`sla`、`qps.current`、`system_metrics`、`job_heartbeats[]` |
| 错误率小折线 | `GET /api/v1/admin/ops/dashboard/snapshot-v2?start_time=<now−45m>&end_time=<now>&mode=raw` | `throughput_trend.points[]{bucket_start, request_count}`、`error_trend.points[]{bucket_start, error_count_sla, business_limited_count}`（附录 A S16） |
| 告警摘要 | `LiveOpsStore` 的告警列表（§6.2）与计数 | firing 条数与标题 |
| 服务器 · 并发 | `GET /api/v1/admin/ops/concurrency` | `enabled`；`platform{<平台>: {current_in_use, max_capacity, waiting_in_queue}}`（平台级可相加，分组级不能） |
| 服务器 · CPU / 内存历史 | `GET /api/v1/admin/ops/system-metrics/history?time_range=1h&max_points=60`（`ops.system_metrics_history`） | `points[]{created_at, cpu_usage_percent, memory_usage_percent}`；无数据为 `[]` |
| 服务器 · 日志采集 | `GET /api/v1/admin/ops/system-logs/health` | `avg_write_delay_ms`、`queue_depth`、`last_error`、`write_failed_count`、`dropped_count` |
| 服务器 · 入口拒绝 | `GET /api/v1/admin/ops/ingress-rejections?time_range=1h&page_size=1`（`ops.ingress_reject_totals`） | `request_count_total`、`by_reason[]{reason, request_count}` |

服务器区的 4 个请求只在站长判定（0.1）通过时发。

### 4.3 字段 → 显示映射

**运行区**（序号“壹”，不写窗口）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 健康分 | `health_score` | 同 1.3.5 | `—` |
| 错误率 | `error_rate` | 比例 → `%` | `—` |
| 上游 429 / 529 | `upstream_429_count` / `upstream_529_count` | 整数 | `—` |
| 小折线 | 把 45 个 1 分钟桶按 `bucket_start` 对齐、合并成 9 个 5 分钟点：每点 = Σ`error_count_sla` ÷ Σ(`request_count` − `business_limited_count`)；分母为 0 的点留空（断线） | 标签“错误率 · 近 45 分钟”；面积折线，无坐标轴 | 请求失败：小折线位置一行“趋势加载失败” |
| 告警中行 | firing 条数；标题列表 | “告警中 N 条”；说明 = 各条标题用“、”连接（可换行）；有 firing 时 caution 胶囊 | 0 条：“告警中 0 条”，说明“没有告警”，无胶囊 |

**服务器区**（序号“贰”，meta “仅管理员可见”；只在站长判定通过时显示）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| CPU 表 | 当前值 `system_metrics.cpu_usage_percent`；小折线 = history 的 `cpu_usage_percent`（null 断线，Y 轴 0–100） | “CPU 38%”；容量条 ≥ 90 critical、≥ 75 caution | 当前值 null → `—`；没有 history 能力：本机在前台每次轮询追加一个点（最多 60 个，切站点清空） |
| 内存表 | `memory_usage_percent`，同上 | “内存 61%” | 同上 |
| 并发 | Σ`platform[*].current_in_use` / Σ`max_capacity` | “并发 8/50” | `enabled == false`（实时监控关闭）→ `—` |
| 排队 | Σ`platform[*].waiting_in_queue` | 整数 | `enabled == false` 时改用 `system_metrics.concurrency_queue_depth`；都没有 → `—` |
| QPS | `qps.current`（后端已保留 1 位小数） | “0.8” | `—` |
| SLA | `sla` | 比例 → `99.2%` | `—` |
| 任务行（每个心跳一行） | 见下表 | — | 列表为空：一行“还没有后台任务心跳” |
| 日志采集行 | 状态：`last_error` 为空 → 正常图标，否则 error 图标；右侧 `avg_write_delay_ms` | “日志采集”，右侧“延迟 2 秒”（< 1000 写“850 ms”） | 请求失败 → 右侧 `—` |
| 日志采集行说明 | `request_count_total` + 需留意的任务数 | “入口拒绝 3 次（1 小时）· 1 个任务需留意” | 入口拒绝失败 → “入口拒绝 —”；没有需留意的任务不写后半句 |

**任务行**（`job_heartbeats[]`；不要假设固定 6 项，从未运行过的任务不在列表里）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 名称 | `job_name` 映射：`ops_metrics_collector` 指标采集、`ops_alert_evaluator` 告警评估、`ops_preaggregation_hourly` 预聚合（小时）、`ops_preaggregation_daily` 预聚合（天）、`ops_cleanup` 清理、`ops_scheduled_reports` 定时报告 | 排序同此顺序，未知任务按名字排在后面、显示原始 `job_name` | — |
| 图标 / 胶囊 | `status`：ok → 正常；failing / stale → caution；disabled / unknown → 无色 | — | 不认识的 status 按 unknown（D08 进度备注） |
| 右侧 | ok：`last_success_at` 相对时间；failing / stale：“最近成功 {相对时间}”（caution 字色）；disabled：“已关闭”；unknown：“—” | “4 分钟前”、“今天 03:00” | `last_success_at` 为 null：“从未成功” |
| 说明行 | failing：“最近一次失败：{last_error}”（截 1 行）；stale：“超过 {2 × expected_interval_seconds 换算} 没有成功，需要看一下”；cron 任务（`ops_cleanup`）stale：“按计划应在 {next_expected_at} 前完成” | — | 其他状态不显示说明 |

没有 `ops.job_heartbeat_status`（旧服务端）时本地判定：`last_error_at` 晚于 `last_success_at` → failing；指标采集、告警评估超过 3 分钟没成功 → stale；预聚合（小时）超过 30 分钟、预聚合（天）超过 3 小时没成功 → stale；清理、定时报告只看 failing。

“需留意的任务数” = status 为 failing 或 stale 的个数。

### 4.4 交互与写操作

- 本段只读；运维关闭时的开启见 §7.2。
- 任务行、日志采集行不可点（设计稿没有下钻）。入口拒绝的原因明细（`by_reason`）不在本版显示（见未决问题 Q5）。

### 4.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 404 `OPS_DISABLED`（任一请求） | 整段替换为 §7.2 的“运维监控未开启”空态 | 开启 |
| overview 失败 | 运行区数字 `—` + “加载失败 · 重试”；服务器区的 CPU / 内存当前值、QPS、SLA、任务行同样 `—` | 重试 |
| 单个服务器子请求失败 | 只影响对应行 | 行内重试 |
| 400 `INVALID_MAX_POINTS` / `OPS_TIME_RANGE_TOO_LARGE` | 程序错误：改回 `time_range=1h&max_points=60` 重试一次 | — |
| 实时监控关闭（concurrency `enabled == false`） | 并发 `—`，并发数字旁小字“实时监控未开启”（与“运维监控未开启”不要判反，附录 A S7） | — |
| 加载中 | 骨架 | — |

### 4.6 刷新策略

本段可见时 60 秒轮询（overview、snapshot-v2、concurrency、history、logs health、ingress 并发）；下拉刷新全部重拉；离开段或进后台取消；退避与回到前台按 00 §4.6。overview / throughput 服务端按 5 秒取整缓存，snapshot-v2 30 秒缓存。ETag：只有 `ops/dashboard/snapshot-v2` 发 ETag（`ops_snapshot_v2_handler.go:67-70`），由 `ConditionalCache` 透明处理（0.2 末段）；因为 `end_time` 每次都是“现在”、缓存键不同，基本不会命中，属正常；其余 5 个接口没有 ETag。

### 4.7 对现有代码的改动点

| 位置 | 改法 |
|---|---|
| `NativeApp/Sub2MobileApp.swift` · `MainTabs` | 按 §0.7-1/-2 改为 `TabView(selection: $router.selectedTab)`：概览 Tab 根换成 `HomeView`，新增监控 Tab（根 `MonitorView`，每个 Tab 一个 `NavigationStack(path:)`），Tab 栏上方叠加回执（§0.7-6）。去掉“管理”“设置”两个 Tab、新增搜索 Tab 见 60 §1.7；完整骨架待骨架章节（Q10） |
| 新文件 `NativeApp/Features/Monitor/MonitorView.swift` | 分段容器 + 三段视图 + 副标题 |
| 新文件 `NativeApp/Features/Monitor/MonitorOverviewSection.swift`、`MonitorServerSection.swift` | 运行区、服务器区 |
| 新文件 `Sources/Sub2Core/OpsMonitoring.swift` | `OpsOverview`（含 `OpsSystemMetricsSnapshot`、`OpsJobHeartbeat`、`OpsRateSummary`）、`OpsSnapshotV2`（overview + throughput_trend + error_trend）、`OpsConcurrency`、`SystemMetricsHistory`、`SystemLogHealth`、`IngressRejectList`、`OpsMonitoringStatus` |
| 新文件 `Sources/Sub2Core/MonitorPresentation.swift` | 任务名映射、心跳文案、本地兜底判定、5 分钟合并的错误率序列；单测覆盖 |
| `APIClient` 新增 | `opsSnapshotV2(start:end:)`、`opsConcurrency()`、`systemMetricsHistory(timeRange:maxPoints:)`、`systemLogsHealth()`、`ingressRejections(timeRange:)` |
| 复用 | 现有 Swift Charts 用法（`PerformanceTrendView` 的 `LineMark`）可用于小折线 |

---

## 5. 监控 Tab · 渠道

### 5.1 入口与导航

- 入口：监控 Tab 分段“渠道”；首页运行区 / 平静布局的渠道行；告警详情的平台渠道行。
- 去向：渠道行 → 分组详情 `.group(id: group_id)`（50 §2；设计稿行带箭头但没有目的页，见未决问题 Q3）。

### 5.2 数据来源

`GET /api/v1/admin/channel-monitor-v2/overview?range=90m`（只挂功能开关，V1 / V2 模式都能用；不受运维开关影响；必须显式传 `range`）

- 顶层：`refresh_interval_seconds`、`coverage{state, collector_state, …}`、`items[]`。
- 每项（一个分组的渠道）：`platform`、`group_id`、`group_name`、`current_status{state, reason, updated_at}`（state：healthy / warning / critical / unknown / stale）、`metrics{reliability_rate, success_rate, request_count, channel_errors, success_requests, sample_state, ttft{p50_ms}}`、`buckets[]`（90 分钟 × 5 分钟一桶，每桶 `bucket_start`、`health{reliability}`、`metrics{…}`）。

渠道监控关闭：403 `CHANNEL_MONITOR_DISABLED`；`/admin/me` 的 `features.channel_monitor_enabled == false` 时直接显示关闭态、不发请求。

### 5.3 字段 → 显示映射

**顶部四格**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 可用 | `current_status.state == healthy` 的项数 | 大数字 + “可用”（ok 色） | 加载失败 `—` |
| 性能下降 | `warning` | “性能下降”（caution） | `—` |
| 不可用 | `critical` | “不可用”（critical） | `—` |
| 未知 | `unknown` + `stale` + 其他值 | “未知”（neutral） | `—` |

**渠道区**（标题“渠道”，meta “可用率 · 首字”，序号“壹”）。排序：不可用 → 性能下降 → 未知 → 可用；同档按 `group_name`。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | 状态映射：healthy ok、warning caution、critical critical、其余 neutral | — | — |
| 标题 | `group_name`，后接小字平台显示名 | “标准组  OpenAI” | `group_name` 为空写“分组 #{group_id}” |
| 右侧 | healthy：`metrics.reliability_rate` → “99.6%”；其他：徽章（性能下降 / 不可用 / 未知） | — | 可用率 null 写 `—` |
| 时间条 | 最近 18 个 `buckets[].health.reliability`：healthy 实心 ok、warning caution、critical critical、unknown 空格 | 18 格，不可点；`accessibilityHidden` | 桶数不足 18：左侧补空格 |
| 说明行 | 见右 | healthy / warning：“可用率 {reliability_rate} · 首字 {ttft.p50_ms 秒，1 位小数}”；critical：“错误率 {channel_errors ÷ (success_requests + channel_errors)} · 首字 …”；`sample_state == no_samples`：“无样本”；`insufficient`：“样本不足”；`current_status.reason == collection_unavailable`：“采集不可用”；`state == stale`：“数据已过期” | 首字 p50 为 null：“首字 —” |

**覆盖提示**：`coverage.collector_state != "healthy"` 或 `coverage.state == "stale"` 时，列表上方一行 neutral 提示“渠道数据采集延迟，显示的可能不是最新状态”。

### 5.4 交互与写操作

只读。行点按见 5.1。

### 5.5 状态

| 情况 | 显示 |
|---|---|
| 403 `CHANNEL_MONITOR_DISABLED` / features 关闭 | 空态“渠道监控未开启”，说明“可在 Web 后台的渠道监控设置中开启”（App 不提供开关） |
| `items` 为空 | 空态“还没有渠道数据” |
| 请求失败 | 有旧数据保留并标“更新失败”；没有旧数据：空态“渠道加载失败” + 「重试」 |
| 403 其他（vendor） | 0.1 的 vendor 占位 |

### 5.6 刷新策略

可见时按 `refresh_interval_seconds` 轮询（限制在 30–300 秒，缺省 60）；下拉刷新带 `refresh=true`；离开段取消。结果写入 `LiveOpsStore`，供首页（退路）与告警详情的平台范围使用。

### 5.7 对现有代码的改动点

新文件 `Sources/Sub2Core/ChannelMonitor.swift`（`ChannelOverview`、`ChannelItem`、`ChannelBucket`、`ChannelMetrics`、`ChannelLatency`），`NativeApp/Features/Monitor/ChannelsSection.swift`；`APIClient.channelOverview(range:refresh:)`。现有 App 无对应代码。

---

## 6. 监控 Tab · 告警

### 6.1 入口与导航

- 入口：监控 Tab 分段“告警”；首页“另有 N 条告警中”行；概况段“告警中 N 条”行。
- 去向：行点按 → 告警详情 `.alert(id:)`（§3）。

### 6.2 数据来源

| 用途 | 请求 |
|---|---|
| 告警中 | `GET /api/v1/admin/ops/alert-events?status=firing&limit=100` |
| 最近结束 | `GET /api/v1/admin/ops/alert-events?time_range=24h&limit=50`，客户端过滤 `status != firing` |
| 更早 | 最近结束区末尾「加载更早」：同一请求加 `before_fired_at=<最后一条 fired_at>&before_id=<最后一条 id>`（两者必须同时给） |
| 精确计数 | `GET /api/v1/admin/ops/alert-events/counts` → `firing`、`by_severity`（`ops.alert_event_counts`） |

列表按 `fired_at DESC, id DESC` 返回；limit 上限 500。事件字段同 §3.2。结果写入 `LiveOpsStore`。

### 6.3 字段 → 显示映射

两个区：“告警中”（序号“壹”，meta “N 条”）、“最近结束”（序号“贰”，meta “N 条”）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 | firing → `alertTone`；非 firing 无胶囊、整行降低强调 | — | — |
| 图标 | firing 铃铛；其他 勾选圆 | — | — |
| 标题 | 同首页告警行标题 | “标准组错误率 5.2%” | 同 |
| 徽章 | `severity` + 状态词 | “P1 · 告警中” / “P1 · 已恢复” / “P2 · 已手动解决” | — |
| 第 2 行（完整换行，不截断） | 范围文案 + “ · ” + 规则文案 | “分组 · 标准组 · 错误率 > 5%（5 分钟）” | 规则缺失：`description` 原文 |
| 静默行（firing 且 `silence != null`） | `silence.until` | “⌛ 已静默至 10:41” | — |
| 底行左 | since 文案 | firing：“12 分钟前”；resolved：“1 小时前恢复”；manual_resolved：“昨天 22:10 · 由 admin 手动解决” | — |
| 底行右（仅 firing） | 小按钮「静默…」/「改静默…」、「手动解决」（主） | 同首页小按钮尺寸规则 | — |
| 空区 | — | “没有告警” | — |

**通用文案函数（`AlertPresentation`，首页、详情、列表共用）**

- 范围：有 `group_id` → “分组 · {group_name}”；只有 `platform` → “平台 · {平台显示名}”；都没有且指标为服务器类（cpu / memory / queue）→ “服务器”；其他 → “全站”。
- 规则：“{指标名} {运算符} {阈值}” + `rule.window_minutes > 0` 时“（{N} 分钟）”；阈值 = `rule.threshold ?? threshold_value`（0.4），指标名与运算符来自 `rule`（旧服务端来自 `ops/alert-rules` 匹配，§3.2）；拿不到规则时整段用 `description` 原文。运算符显示：`>` `<` `>=`→`≥` `<=`→`≤` `==`→`=` `!=`→`≠`。
- 指标名与单位（与后端白名单 `handler/admin/ops_alerts_handler.go` 一致，百分比类数值已是百分数）：

| metric_type | 指标名 | 单位 |
|---|---|---|
| success_rate | 成功率 | % |
| error_rate | 错误率 | % |
| upstream_error_rate | 上游错误率 | % |
| p95_latency_ms | P95 延迟 | ms |
| p99_latency_ms | P99 延迟 | ms |
| cpu_usage_percent | CPU | % |
| memory_usage_percent | 内存 | % |
| concurrency_queue_depth | 排队 | 个 |
| group_available_accounts | 可用账号 | 个 |
| group_available_ratio | 可用比例 | % |
| group_rate_limit_ratio | 限流比例 | % |
| account_rate_limited_count | 限流账号 | 个 |
| account_error_count | 错误账号 | 个 |
| account_error_ratio | 错误账号比例 | % |
| account_temp_unscheduled_count | 临时不可调度账号 | 个 |
| overload_account_count | 过载账号 | 个 |
| proxy_expired_count | 已过期代理 | 个 |
| proxy_expiring_soon_count | 即将过期代理 | 个 |

  数值格式：% 类最多 2 位小数并去掉末尾 0（`5` → `5%`，`5.2` → `5.2%`）；ms 类整数加千分位（`2,000 ms`）；个数类整数。未知 `metric_type`：指标名用原值，数值保留 2 位小数，规则文案后加“（不受支持，不会触发）”；`p95_latency_ms` / `p99_latency_ms` 在没有 `ops.alert_latency_metrics` 时同样加这句（D07 退路）。

### 6.4 交互与写操作

- 「手动解决」「静默…」「改静默…」：§7.1。
- 不提供“确认 / ack”（后端没有，BUILDER_GUIDE：告警只有手动解决和静默）。
- 告警规则的查看与编辑不在本版（Web 管理）。

### 6.5 状态

| 情况 | 显示 |
|---|---|
| 404 `OPS_DISABLED` | §7.2 空态 |
| 加载失败 | 有旧数据保留并标“更新失败”；否则空态“告警加载失败” + 「重试」 |
| 两个区都为空 | 两个区各显示“没有告警” |
| 400 `before_fired_at and before_id must be provided together` | 程序错误：去掉游标重拉第一页 |

### 6.6 刷新策略

可见时 60 秒轮询（两条列表 + 计数）；下拉刷新；写操作成功后立即重拉并更新 `LiveOpsStore`；不做 ETag / since_id（告警接口没有）。告警中条数（分段计数、首页、概况）在监控 Tab 不可见时由首页的 home 轮询更新。

### 6.7 对现有代码的改动点

新文件 `NativeApp/Features/Monitor/AlertsSection.swift`、`AlertRow.swift`（首页告警行复用同一个行视图，参数控制是否显示按钮）；`APIClient.alertEvents(status:timeRange:limit:before:)`、`alertEventCounts()`。

---

## 7. 共用交互

### 7.1 手动解决与静默（告警详情、监控 · 告警行内）

实现为一个共用的 `AlertActions`（`@MainActor`，持有 `LiveOpsStore` 与 `APIClient`），首页、监控、详情都调它，保证三处状态一致。下文的“回执”都用 §0.7-6 的 toast，“确认框 / 动作表”用 §0.7-8 的系统组件。

**手动解决**

1. 确认框：标题“手动解决这条告警？”，正文“「{标题}」会标记为已手动解决。条件仍满足时，规则会再次触发。”，按钮「手动解决」「取消」。
2. `PUT /api/v1/admin/ops/alert-events/:id/status`，body `{"status":"manual_resolved"}` → `{"updated": true}`。服务端记录解决人（当前登录管理员；Admin Key 记为第一个管理员）。
3. 成功：`LiveOpsStore` 本地把该事件置为 `manual_resolved`、`resolved_at = now`（首页告警行立即消失、监控列表移到“最近结束”），回执“已手动解决”（无撤销：后端没有重新打开的接口）；随后重拉列表与计数校正。
4. 失败：不改本地状态；回执写原因（见下表）。
5. 不需要 step-up；不带 Idempotency-Key（该接口不支持，重复 PUT 是同值写，安全）。超时：重新 GET 该事件，`status != firing` 视为成功。
6. 注意：对不存在的事件后端也返回 `updated: true`（BACKLOG D06），所以成功后必须重拉校正。

**静默 / 改静默时长 / 结束静默**

1. 确认框（动作表）：
   - 未静默：标题“静默这条规则多久？”，正文“静默期间，这条规则{在 <范围名>}不再产生新的告警事件。当前这条仍需手动解决。”，按钮「静默 1 小时」「静默 24 小时」「静默 7 天」「取消」（时长与 Web 一致）。
   - 已静默：标题“改静默时长”，正文首行“当前静默至 {until}”，按钮同上三个时长 + 「结束静默」（destructive）+「取消」。
2. 请求：
   - 新建：`POST /api/v1/admin/ops/alert-silences`，body `{"rule_id": <rule_id>, "platform": "<dimensions.platform 或空串>", "group_id": <dimensions.group_id 或 null>, "until": "<now + 时长，RFC3339 UTC>"}`（`region` 不传；`reason` 不传）→ 静默对象 `{id, rule_id, platform, group_id, until, …}`。空 platform 表示规则作用域没有平台（D01）。
   - 改时长：`PUT /api/v1/admin/ops/alert-silences/:silence.id`，body `{"until": "<now + 时长>"}` → 更新后的静默对象；服务端会把同作用域其他更晚的静默一并截到这个时间，可缩短可延长，上限 30 天。
   - 结束：`DELETE /api/v1/admin/ops/alert-silences/:silence.id` → `{"deleted": true}`；同作用域所有生效中的静默都在此刻结束（保留审计记录）。
3. 成功：本地把事件的 `silence` 设为 `{id, until}`（结束时设为 null），回执“已静默 1 小时” / “静默改为至 10:41” / “已结束静默”；新建静默的回执带「撤销」（调 DELETE 刚建的 id），改时长的回执带「撤销」（PUT 回原 until，原 until 已过去则不提供）。随后重拉事件校正。
4. 失败：不改本地状态，回执写原因。
5. 不需要 step-up；不支持 Idempotency-Key。新建超时：重新 GET 事件，有 `silence` 视为成功；没有再允许重试（重复新建也无害，事件只显示 until 最大的一条）。

**错误 reason → 文案**

| reason / 状态 | 文案 | 动作 |
|---|---|---|
| 404 `OPS_DISABLED` | 运维监控已关闭，无法处理告警 | 刷新页面进入关闭态 |
| 404 `OPS_ALERT_SILENCE_NOT_FOUND` | 这条静默已不存在 | 重拉事件 |
| 404 `OPS_ALERT_EVENT_NOT_FOUND` | 这条告警不存在或已被清理 | 返回列表并重拉 |
| 400 `INVALID_UNTIL` | 静默时间无效（须在 30 天内） | — |
| 400 `INVALID_RULE_ID` | 规则已删除，无法静默 | 隐藏静默按钮 |
| 400 `INVALID_STATUS`、`INVALID_EVENT_ID`、`INVALID_SILENCE_ID`、`Invalid until` | 操作未完成（程序错误） | 记录日志 |
| 403 `ACCESS_TOKEN_READ_ONLY` | 只读访问令牌不能处理告警 | 按钮置灰 |
| 网络 / 超时 | 按上面的超时规则核对 | — |

**旧服务端退路（事件 JSON 没有 `silence` 键，即 D01 之前）**：事件 `dimensions.platform` 为空（含全部预置规则）时隐藏静默按钮，只留手动解决；有 platform 时允许 POST 静默，“已静默至”只存本机（`UserDefaults`，键 = 站点 + rule_id + platform + group_id），并且只能延长不能缩短或结束；换设备、在 Web 操作后可能不一致。

### 7.2 运维监控未开启（首页提示行、监控各段空态、告警详情空态）

**判定**：任一受控接口返回 404 `OPS_DISABLED`，或 home 的 ops / alerts 段 `disabled`，或 `/admin/me` 的 `features.ops_monitoring_enabled == false`。随后读 `GET /api/v1/admin/ops/monitoring-status`（`ops.monitoring_status`，不受开关影响）→ `{config_enabled, monitoring_enabled, realtime_monitoring_enabled, effective, disabled_reason}`。

**显示**：

| disabled_reason | 文案 | 按钮 |
|---|---|---|
| `setting_off` | 运维监控未开启：错误率、告警、服务器状态与错误日志都不可用 | 「开启运维监控」（站长） |
| `config_off` | 运维监控已在服务器配置中关闭（`ops.enabled=false`），需要在服务器配置中启用 | 无（不要引导去 Web 设置页，也不要重试） |
| 读不到（旧服务端） | 运维监控未开启 | 「开启运维监控」 |

监控 Tab 的空态在文案下补一行“关闭期间不会记录错误请求，开启后也不会补回”（附录 B L12）。

**开启流程**：

1. 确认框：标题“开启运维监控？”，正文“开启后开始记录错误请求、告警与服务器指标；关闭期间的数据不会补回。”，按钮「开启」「取消」。
2. `PUT /api/v1/admin/ops/monitoring-status`，body `{"monitoring_enabled": true}` → 与 GET 同结构。不需要 step-up；不带 Idempotency-Key（同值写）。
3. 结果：`effective == true` → 回执“已开启运维监控”，刷新首页与监控全部区块（其他服务端实例最多约 30 秒后生效，首次刷新仍可能 404，30 秒内再自动重试一次）；`effective == false` 且 `disabled_reason == config_off` → 改显示 config_off 文案。
4. 409 `OPS_CONFIG_DISABLED` → config_off 文案，不重试；403 → “当前身份没有修改运维设置的权限”；403 `ACCESS_TOKEN_READ_ONLY` → “只读访问令牌不能修改设置”。
5. 旧服务端（无 `ops.monitoring_status`）：`PUT /api/v1/admin/settings`，body 只带 `{"ops_monitoring_enabled": true}`（省略的字段保持不变）；之后受控接口仍 404 → 视为配置关闭，显示 config_off 文案（D09 退路）。

---

## 8. 本章新增 / 改动文件汇总

| 类型 | 文件 | 内容 |
|---|---|---|
| 新增 Core | `Sources/Sub2Core/BlockState.swift` | 0.5 区块状态 |
| 新增 Core | `Sources/Sub2Core/DashboardHome.swift` | §1 首页聚合模型 |
| 新增 Core | `Sources/Sub2Core/AccountStatusSummary.swift` | D02 汇总模型（与 20 §10.3 同一个文件） |
| 复用 Core | `Sources/Sub2Core/AccountDisplayState.swift`（20 §0.2） | 首页账号行的状态词、倒计时、原因短句 |
| 新增 Core | `Sources/Sub2Core/OpsMonitoring.swift` | §4 运维模型、监控开关 |
| 新增 Core | `Sources/Sub2Core/OpsAlerts.swift`、`AlertPresentation.swift` | §3、§6 告警模型与文案 |
| 新增 Core | `Sources/Sub2Core/ChannelMonitor.swift` | §5 渠道模型 |
| 新增 Core | `Sources/Sub2Core/HomePresentation.swift`、`MonitorPresentation.swift` | 纯函数：6 格、待处理、平静判定、心跳、错误率序列 |
| 改 Core | `APIClient.swift` | 新接口方法、服务器时区日期；删 `dashboardMonitoring` / `OpsReply`；条件请求用 00 §9.7 的 `ConditionalCache`，本章不另加类型 |
| 改 Core | `Models.swift` | 删 `OpsSnapshot`；`DashboardSummary.monitoring` 删除；`PendingBalanceOperation` 加 `createdAt`、`userDisplayName`（30 §3.7） |
| 改 Core | `DashboardPresentation.swift` | 0.4 格式函数 |
| 新增 App | `NativeApp/Session/LiveOpsStore.swift` | 0.5 共享状态、轮询编排、写后刷新 |
| 新增 App（骨架未写出前由本章先建，§0.7） | `NativeApp/Session/AppRouter.swift`、`NativeApp/Views/Receipt.swift`、`NativeApp/Views/StatusRail.swift` | 路由与跨 Tab 跳转、回执 toast、状态轨 |
| 新增 App | `NativeApp/Features/Home/*.swift` | §1、§2 视图 |
| 新增 App | `NativeApp/Features/Monitor/*.swift` | §3–§7 视图与 `AlertActions` |
| 改 App | `NativeApp/Sub2MobileApp.swift` · `MainTabs` | §4.7：`TabView(selection:)`、概览与监控两个 Tab 的根视图、回执叠加层 |
| 改 App | `NativeApp/Features/DashboardView.swift` | 删除首页旧实现；`DashboardTrendChart` 移交统计分析（40 §1）；`DashboardLoadState` 挪到 `NativeApp/Views/LoadState.swift` |
| 改 App | `NativeApp/Features/PerformanceTrendView.swift` | 首页不再内嵌；由 40 章统计分析承接（6 格 RPM / TPM 只负责跳转） |
| 改 App | `NativeApp/Session/AppModel.swift`、`DemoData.swift` | 包装方法、UI 测试数据 |
| 测试 | `Tests/Sub2CoreTests/` | `HomePresentationTests`、`DashboardHomeDecodingTests`、`AttentionItemsTests`、`AlertPresentationTests`、`MonitorPresentationTests`、`ChannelOverviewDecodingTests` |

`Sources/Sub2Core/PerformanceTrend.swift` 的 `rate(_:metric:)` 统一除以整桶秒数，首尾残桶会骤降（附录 B L7，DECISIONS“TPM 口径”落地提醒）——首页已改读 `rates`，不再受影响；按每桶实际覆盖秒数折算的改法由 40 章负责（40 §0.4 的 RPM / TPM 口径）。

---

## 9. 本章未决问题

| # | 问题 | 建议默认值 |
|---|---|---|
| Q1 | 已定的“合并”待处理（DECISIONS 第 2 轮 Q3）在设计稿里没有分组卡；D02 与本章任务都提到“分组可用偏低”要进待处理。要不要单列？ | 单列一行“可用不足 N 个分组”（1.3.3），只在 `shortage.is_short`、分组启用、且组内有异常账号时出现；出现时不进入平静布局。只因停用 / 暂停账号造成的“不足”不提示 |
| Q2 | 首页一次显示几条告警？设计稿演示只画了 1 条 | 显示 `alerts.top` 的全部（≤ 5 条，按级别再按时间），超出部分合成“另有 N 条告警中”一行 |
| Q3 | 渠道行在设计稿里有箭头但没有目的页 | 点进对应分组详情（渠道按分组统计）；以后若做渠道详情再替换 |
| Q4 | 监控 Tab 默认段：设计稿源码默认“渠道”，DECISIONS 的顺序是“概况 + 渠道 + 告警” | 首次进入默认“概况”，之后在本次会话内记住上次所选段 |
| Q5 | 入口拒绝只显示合计次数；`by_reason` 原因明细要不要做二级 sheet | 本版不做；日志采集行保持不可点 |
| Q6 | App 里是否提供“关闭运维监控” | 只在监控 Tab `···` 菜单放「关闭运维监控…」（站长、二次确认，`PUT ops/monitoring-status {"monitoring_enabled":false}`）；首页不提供 |
| Q7 | 首页 `···` 菜单内容设计稿未定义 | 「刷新」「统计分析」两项 |
| Q8 | 关监控时 RPM 只计成功请求（B01 进度备注），6 格里是否单独标注 | 不在格内加字；由 6 格下方的“运维监控未开启”提示行统一说明 |
| Q9 | “静默中的规则”（当前没有 firing 事件的静默）App 看不到 | 本版不做静默列表页；需要时用 `GET /api/v1/admin/ops/alert-silences?active=true` 加一个只读列表 |
| Q10 | 00–60 章没有应用骨架章节（Tab 结构、路由枚举、每 Tab 导航栈、跨 Tab 带参数跳转、推送落点、站点菜单、回执 toast、状态轨、删除确认组件），本章与 20 / 50 / 60 都依赖它 | 在 00 加一节或新建 `05-shell.md` 统一定义；写出之前按本章 §0.7 的接口实现（`AppRouter`、`AppRoute`、`TabIntent`、`Receipt`、`.statusCapsule`），骨架章节写出后本章 §0.7 删减为引用 |

---

## 审查记录

- §1.2 过载原因退路取 `ops/upstream-errors` 第一条的 `status_code`：属实。恢复行的 `status_code` 是客户端最终拿到的码（`handler/ops_error_logger.go:1296-1301` 用 `finalStatus`），上游码只拼在 `ErrorMessage` 里（`:1350-1355`），列表又默认带恢复行（`handler/admin/ops_handler.go:504`），过载账号最常见的“529 后换号成功”会显示成“上游 200”。按第 6 条一起处理：这个请求整个删掉，原因固定写“上游 529”，不再需要从 message 解析。
- 告警阈值字段名：属实（`service/ops_alert_models.go:50-51` 为 `threshold_value`，`:80` 的 `rule.threshold`）。§0.4、§1.3.3 告警行、§3.3 大数字旁与规则区、§6.3 规则文案统一写成 `rule.threshold ?? threshold_value`；§3.7 写明两个字段都解码。
- 应用骨架没有章节负责：属实。新建 00 节或 `05-shell.md` 不在本文件范围，没有做。本章新增 §0.7，只写本章依赖的部分（Tab、每 Tab 导航栈、路由、跨 Tab 带参数跳转、推送落点、站点菜单、回执 toast、状态轨、确认框）。站点菜单按设计稿 `SiteMenu` 写，回执按 `Toast` 和 4.2 秒计时写。本章里“导航章节 / 站点章节 / 通用组件章节 / 推送章节”等泛指引用，都改成了 §0.7 或 00 §1.1 / §7.5 / §8 和 20 / 30 / 40 / 50 / 60 的具体小节。另列未决问题 Q10。20 / 50 / 60 里的同类引用要由各章负责人改。
- 兑换码待核对行文案：属实（`v-today.jsx` `VtRedeemRow` 为“{count} 个 · {ago} · 未确认是否生成”）。说明行已改为“20 个 · 5 分钟前 · 未确认是否生成”，和 60 §11.3 横幅一样用“生成”。
- ETag 处理方式不一致：属实。已删掉 §0.2 的 `lists.etag` 行。0.2 末段改为“按 00 §4.2 由 `ConditionalCache` 透明处理”，并列出本章哪些接口带 ETag（都在源码里核对过）。§1.6 改为下拉刷新也照常带 `If-None-Match`。§1.7 和 §8 删掉了 `Conditional<DashboardHome>`、`.notModified`。原 §4.6 写“snapshot-v2 不做 ETag”，与 `ops_snapshot_v2_handler.go:67-70` 不符，也一并改了。40 / 60 的括号说明和 20 / 30 / 50 各自的返回类型不在本文件。
- 首页与账号页显示的原因不一致：属实（`SetOverloaded` 只有 `ratelimit_service.go:1999` 一个调用点，在 `handle529` 里，入口是 `:358-363` 的 `statusCode == 529` 分支）。§1.3.3 新增“账号行的通用规则”：账号行的状态词、倒计时和原因短句一律取 20 §0.2 的 `AccountDisplayState`。错误行原因改为 `error_summary`，为空时写“上游返回异常”，不显示 `error_message` 原文；本章的 `error_kind` 词表已删掉。过载行原因固定“上游 529”，原来的 upstream-errors 请求、§1.6 对应的重拉和原 Q9 都已删掉（原 Q10 改为 Q9）。§0.2 `accounts.structured_error` 缺失时的写法也同步改了。00 §5 同一行仍写“`error_message` 首行截断 80 字”，这一行不在本文件，要由 00 负责人改。`error_kind` 中文词如果要显示，应加到 20 §0.2。
- 导航与路由写法不统一：属实，和第 3 条一起处理。本章路由已从 JS 对象改成 Swift 枚举写法（与 60 §0.1 一致），参数名沿用 40 §0.1、20 §1.1（`limited`）、50 §1（“需处理”段）。跨 Tab 跳转统一走 §0.7-4 的 `router.select(_:)`。合并 40 / 60 路由表、全局推送深链落点要等骨架章节来做。
- 刷新节奏与超时重复：属实。§1.5 删掉了“连续 3 次失败后改为 120 秒”，改为引用 00 §4.6 的退避，超时引用 00 §2.3。§1.6 删掉了“距上次成功 > 30 秒才刷新”，开头注明通用节奏按 00 §4.6，本节只写本页取值。§4.6 补了同样的引用。本章没有自定义超时数值。60 第 599 行、40 §0.6 的数值不在本文件。
