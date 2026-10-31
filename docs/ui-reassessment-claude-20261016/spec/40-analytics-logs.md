# 40 · 统计分析与日志

本章覆盖 7 个页面：统计分析（`analytics`，卡片流）、更多图表（`analyticsMore`）、单图页（`analyticsChart`）、全部排行（`analyticsRank`）、模型页（`analyticsModel`）、使用记录（`logs`）、请求详情（`request`）。

- 口径：`DECISIONS.md`（第 3 轮以更正后为准，文末 10-18 评审意见与 TPM 口径最新）；后端行为以 `BACKEND-API-CHANGES.md` 进度表备注为准。
- 接口：全部在 sub2 后端 HEAD `70116315d`（2026-10-22）源码里核对过路由、参数、字段名和 reason。下文接口路径省略前缀 `/api/v1`。
- 设计稿对照：`html-preview/layouts/main/v-analytics.jsx`（已定变体都是 base）、`00-core.jsx` 的 `LogsScreen` / `LogRow` / `RequestDetail`。

---

## 0. 本章共用规则

### 0.1 路由

| route | 参数 | 说明 |
|---|---|---|
| `analytics` | `range`：`today` \| `last7`（入口默认值，只在这个站点还没有记忆时生效，见下方“状态共享与记忆”）；`focus`：`perf`（可选）；`metric`：`rpm` \| `tpm`（可选） | 卡片流 |
| `analyticsMore` | `chart`（图表 key，可选）；`topic`：`billing` \| `usage` \| `ops`（可选） | 按主题分组的图表列表 |
| `analyticsChart` | `chart` | 一张图全屏 |
| `analyticsRank` | `dim`：`model` \| `user` \| `group` | 全部排行 |
| `analyticsModel` | `model`（字符串）；`source`：`requested` \| `upstream` \| `mapping` | 模型页 |
| `logs` | `scope`：`usage` \| `errors` \| `upstream`；`account` / `group` / `user`：`{id, name?}`；`model`（字符串）；`modelSource`（默认 `requested`） | 使用记录 |
| `request` | `.usage(record)` \| `.usageRequestID(String)` \| `.error(id, kind: request \| upstream, initial?)` | 请求详情 |

图表 key：`billing`（计费明细）、`profit`（利润明细）、`tokens`、`userTrend`、`endpoints`、`reqType`、`perf`、`switch`、`latency`、`errTrend`、`errDist`、`tokenSpeed`。

**状态共享与记忆**（设计稿 `v-analytics.jsx` 头注释“选过的范围、筛选……在本机记住，二级页沿用”与 `useAxMemo` / `useAxRange`）：

- `analytics` 与它推出的 More / Chart / Rank / Model 共用一个 `AnalyticsSession`（`@Observable`）。其中**各卡的加载状态与数据缓存**只在这一次统计分析导航栈内有效，退出即丢弃。
- **选择项在本机记住**，按站点区分（`UserDefaults`，键 `analytics.<站点 id>.<项>`），二级页与下一次进入都沿用：范围（预设存键名，如 `today` / `last7` / `lastMonth`，进入时按当天重算；自选存起止日期）、筛选（分组 id 或模型名）、排行卡当前分段、全部排行每个维度的排序指标与模型口径。用户改动后立即写入。
- **入口默认值只在第一次用**：进入时先读这个站点的记忆；没有记忆（这个站点第一次进统计分析）才用 route 的 `range`（概览进来“今天”、搜索目录进来“近 7 天”）。有记忆时从概览“今日”格进来也显示记住的范围（设计稿就是这样）。
- 记忆失效：记住的分组在 `groups/all` 里已不存在 → 丢弃这项筛选；自选范围的起点早于 366 天前 → 丢弃范围记忆，改用入口默认值。切换站点读另一套记忆；退出登录不清（只是界面偏好，不含数据），删除站点时一并删除。
- RPM / TPM 卡的窗口（近 1 / 6 / 24 小时）和指标（RPM / TPM）同样按站点存 `@AppStorage`（键里带站点 id），凡是出现这张图的地方共用；`route.metric` 优先于记忆值，并写回记忆。

### 0.2 时区与时间参数

- 站点时区 TZ：`GET /admin/me` → `data.server.server_timezone`；拿不到时用 `GET /settings/public` → `server_timezone`。
- “今天 / 昨天 / 按小时 / 按天”的边界、每个请求的 `timezone=` 参数、横轴标签、日志里显示的时刻，全部按 TZ。理由：首页 6 格的“今日”来自 `dashboard/stats`，后端固定按服务器时区算；统计分析“今天”的利润必须等于首页利润。设备时区与 TZ 不同时，范围说明行和日志副标题末尾加“（站点时间 UTC+8）”。设计稿自定义范围 sheet 里的“按本机时区计算”一律改为“按站点时区计算”。
- 时间参数成对传 `start_time` / `end_time`（RFC3339，统一写 UTC `Z` 形式，省去 `+` 的编码），左闭右开；同时带 `timezone=<TZ>`（决定桶边界与 `date` 标签）。后端 `usagequery.ParseRange` 要求两者成对，只传一个返回 400。
- 日历运算用设了 TZ 的 `Calendar`（夏令时日不能用 86400 秒相加）。
- 后端不补空桶的接口：`dashboard/trend`、`dashboard/users-trend`（只返回有数据的桶），App 按范围补 0。`ops/dashboard/throughput-trend`、`error-trend` 后端已补齐。

### 0.3 能力探测与降级

切站 / 启动时取 `GET /admin/me`（缓存方式见通用约定章节）。本章用到：

| 判断 | 来源 | 用途 |
|---|---|---|
| 运维监控 | `data.features.ops_monitoring_enabled`、`ops_monitoring_disabled_reason`（`config_off` / `setting_off`） | false 时不发 `ops/*` 请求，直接显示“运维监控未开启”；仍要处理 404 `OPS_DISABLED`（多实例间开关最多晚 30 秒同步） |
| vendor | `data.workspace` 非空 | 见 0.7 |
| `dashboard.account_cost` | `data.server.capabilities` | 趋势点带 `account_cost`（B02） |
| `usage.model_source` | 同上 | `admin/usage`、`usage/stats`、`dashboard/*` 接受 `model_source`（B03） |
| `dashboard.users_ranking_sort` | 同上 | users-ranking 的 `sort_by`、`total_users`、成本字段（B04） |
| `dashboard.request_types` | 同上 | `dashboard/request-types`（B05） |
| `ops.dashboard_model_filter` | 同上 | `ops/dashboard/*` 接受 `model` + `model_source`（B06） |
| `ops.token_stats_custom_range` | 同上 | `openai-token-stats` 接受 `start_time` / `end_time`（B07） |
| `dashboard.users_trend_filtered_metric` | 同上 | users-trend 带筛选时 `metric` 生效（B12） |
| `logs.since_id` | 同上 | `admin/usage`、`ops/request-errors` 的 `since_id`（B09） |
| `ops.request_attempts` | 同上 | `ops/requests/:request_id/attempts`（D10） |
| `api_keys.masked_view` | 同上 | `key_view=masked`（E03） |

B01、B02、B03、D03（上游错误身份筛选）、D04（错误日志耗时）、D05（使用记录 `account_cost`）都早于 `/admin/me` 合入（已核对提交顺序），D03 / D04 / D05 没有单独的能力标记：`GET /admin/me` 返回 404 的服务端按“这几项都没有”处理；解码时再按字段兜底一次（键不存在 = 旧服务端，不当作 0）。

### 0.4 口径与措辞

| 名称 | 定义 | 后端字段 |
|---|---|---|
| 实际扣费 | 用户实际被扣的金额 | `actual_cost`、`total_actual_cost` |
| 标准 | 未乘分组倍率的标价 | trend / models / groups 的 `cost`，usage/stats 的 `total_cost`，使用记录的 `total_cost` |
| 账号成本 | 上游账号的成本，只算 `provider_cost_recorded` 的行 | `account_cost`、`total_account_cost` |
| 利润 | 实际扣费 − 账号成本 | App 计算 |
| RPM / TPM（趋势图） | 每桶 数量 × 60 ÷ 这一桶实际覆盖的秒数；RPM 含成功与错误请求，TPM 为成功请求的含缓存 Tokens（input + output + cache_creation + cache_read） | throughput-trend 的 `request_count`、`token_consumed` |
| 错误率 · SLA | SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制 | ops overview 的 `error_rate` |

- 界面上不出现“营收”“上游成本”“差额”“毛利”“实际消费”。卡片名固定：计费趋势、计费明细、利润明细、RPM / TPM 趋势。
- 利润不加“+”，亏损写“−$12.30”；计费数字不着色；增减箭头只表方向，不用红绿。
- 请求类型显示名：`stream` 流式、`sync` 同步（请求详情“方式”里写“非流式”）、`ws_v2` WS（详情写 WebSocket）、`cyber` 安全策略、`live` Live、`unknown` —。
- 阶段 `phase`：request 请求校验、auth 鉴权、account_auth 账号鉴权、routing 路由、upstream 上游、network 网络、internal 网关内部；责任方 `error_owner`：client 客户端、provider 上游服务商、platform 平台配置；未知值原样显示。
- 状态码颜色（codeTone）：2xx ok；429 琥珀（caution）；其余失败（含 504、529）红（critical）；业务限制灰。

### 0.5 数字格式

- 金额：`$1,284.50`；负数用 U+2212 `−$12.30`；日志行的单条金额 < $1 显示 4 位小数（`$0.0124`），否则 2 位；请求详情的三格金额固定 4 位；缺失 `—`，0 显示 `$0.00`。解码用 `Decimal`，显示时四舍五入。
- 计数：千分位 `18,204`；大数 compact：`240K`、`96.4M`（1 位小数，去掉 `.0`）。
- 日志行与请求详情的耗时：秒，1 位小数（`0.6s`、`42.1s`），≥ 100 秒取整（`182s`）。分位数表的耗时：< 1 秒 `820ms`，1–10 秒 `2.4s`，≥ 10 秒 `42s`。
- 百分比：1 位小数（`98.3%`）；占比条上的百分比同。
- RPM：≥ 10 取整，< 10 保留 1 位，0 显示 `0`；TPM 用 compact。
- 增减：`↑ 12.3% · 比昨天同时`。

### 0.6 请求与加载

- 每张卡 / 每张图一个独立加载状态（沿用 `DashboardLoadState` 与 `isCurrent` 守卫），独立超时、失败、重试，一个失败不影响其他。
- 超时：`dashboard/*` 60 秒，`admin/usage/stats` 90 秒，`ops/dashboard/*` 45 秒（范围超过 24 小时时 90 秒），日志列表与详情 45 秒。
- 降级扇出（逐段 usage/stats 等）并发上限 4。
- 本章接口都没有 ETag（后端只给 dashboard/stats、users、groups、snapshot-v2 加了），不发 `If-None-Match`；`URLSessionTransport` 继续禁用 URLCache。
- 错误不回显服务端 message（沿用 `APIError.server`），按 `reason` 分支。

### 0.7 vendor（代运营工作区）

后端只对 vendor（监控档）开放 `GET /admin/usage*`（`search-users`、`search-api-keys`、`cleanup-tasks` 除外）与 `dashboard/trend`、`dashboard/models`、`dashboard/groups`；其余本章接口 403，`ops/*` 全部不开放。vendor 进入统计分析：只有计费趋势、利润明细、排行卡（模型 / 分组两段）；没有 RPM / TPM 卡、更多图表里没有“运行”主题、用户用量趋势和请求类型。使用记录只有“用量明细”一段，筛选 sheet 没有“用户”组；用户邮箱已被后端打码，照原样显示。

---

## 1. 统计分析（`analytics`，卡片流）

### 1.1 入口与导航

- 进入（`range` 只是入口默认值，有记忆时用记忆，见 0.1）：
  - 概览“今日”区的“更多统计 ›”，以及 6 格中的今日实际扣费 / 请求 / 错误率 / 利润 → `analytics(range: today)`。
  - 6 格的 RPM、TPM → `analytics(range: today, focus: perf, metric: rpm | tpm)`：首次出现时滚到 RPM / TPM 卡并切到该指标（只滚一次）。
  - 搜索目录“资源 · 统计分析” → `analytics(range: last7)`。
  - 分组详情没有统计入口（50 章已删除旧的“统计分析”链接），所以 route 不带预置分组筛选。
- 导航栏：标题“统计分析”；副标题“<站点名> · 刚刚更新”（取各卡里最早一次成功加载的时间，写“N 分钟前更新”）；右侧筛选按钮（`line.3.horizontal.decrease`）。
- 卡片顺序：范围条 → 计费趋势 → 利润明细 → 排行 → RPM / TPM 趋势 → 更多图表。
- 去向：计费趋势卡底 → `analyticsChart(billing)`；利润明细卡底 → `analyticsChart(profit)`；排行行 → 模型页 / 用户详情 / 分组详情；排行卡底 → `analyticsRank(dim)`；RPM / TPM 卡底 → “性能明细” sheet；更多图表磁贴 → `analyticsMore(chart:)`；“全部图表” → `analyticsMore()`。

### 1.2 范围与筛选（本页与二级页共用）

**范围**：`Picker(.segmented)`：今天 · 7 天 · 30 天 · 自定义（选了预设后显示预设名，如“上月”）。再点已选中的段不动作；说明行是回到自定义 sheet 的入口。

| 选项 | start | end | 粒度 | 范围名 | 对比窗口 | 对比文案 |
|---|---|---|---|---|---|---|
| 今天 | TZ 今日 00:00 | 现在 | hour | 今天 | 昨日 00:00 → 昨日同一时刻 | 比昨天同时 |
| 7 天 | 今日 − 6 天 00:00 | 现在 | day | 近 7 天 | 前推 7 天，止于第 7 天前的同一时刻 | 比前 7 天同期 |
| 30 天 | 今日 − 29 天 00:00 | 现在 | day | 近 30 天 | 前推 30 天同期 | 比前 30 天同期 |
| 本月 | 本月 1 日 00:00 | 现在 | day | 本月 | 上月 1 日 → 上月同日同一时刻（上月没有这天取月末） | 比上月同期 |
| 近 14 天 | 今日 − 13 天 00:00 | 现在 | day | 近 14 天 | 前推 14 天同期 | 比前 14 天同期 |
| 上月 | 上月 1 日 00:00 | 本月 1 日 00:00 | day | 上月 | 上上月整月 | 比 8 月 |
| 自选多天 | 起日 00:00 | 止日次日 00:00；止日是今天时为现在 | day | 自选 N 天 | 紧邻在前、等长的 N 天（含今天时取同期） | 比前 N 天 / 比前 N 天同期 |
| 自选单天 | 当日 00:00 | 次日 00:00；今天为现在 | hour | 今天 / 昨天 / 10月14日 | 前一天（今天时取同期） | 比昨天同时 / 比前一天 |

- 说明行（Button，带日历图标与 ›）：`10月16日 周五 · 00:00 至 09:41 · 按小时`；多天 `10月10日 – 16日（今天到 09:41）· 按天`，跨月写全 `9月17日 – 10月16日`；过去的单天 `10月15日 周四 · 按小时`。
- 自定义 sheet（标题“自定义范围”，右上“应用”）：快捷胶囊 本月 / 近 14 天 / 上月；下面“开始 · 10月1日 周三 00:00”“结束 · 10月16日 周五 现在（09:41）/ 24:00”两行，点一行展开一个 `DatePicker(.graphical)`，一次只选一天，不画区间底色；改了起止后快捷胶囊取消选中，若正好等于某个快捷项则自动选中它；底部说明“共 N 天，按天统计（只选一天按小时）；按站点时区计算。”。可选日期：最早 366 天前，最晚今天；开始晚于结束时把另一端对齐。后端不提供站点开通日期，不写设计稿里“站点 X 月 X 日开通”那句。
- 范围改变：除 RPM / TPM 卡（自有滚动窗口）外，所有卡清空旧值重新加载。

**筛选**：导航栏按钮打开 sheet；同一时间只有一个条件（分组或模型）。

- sheet 标题“筛选”：`Segmented` 分组 / 模型；第一行“全部分组 / 全部模型”（单选圆点）。
  - 分组：`GET /admin/groups/all?include_inactive=true`，按 `sort_order` 排；停用分组加“停用”标签，照样可选。右侧数字为当前范围内该组实际扣费占比（取当前范围 `dashboard/groups` 的结果，没有用量写 `0.0%`）。
  - 模型：当前范围 `dashboard/models?model_source=requested` 的全部模型（等宽字体），按实际扣费降序，右侧占比同理。
  - 底部说明：分组——“筛选后趋势、合计、排行和运行类图表都只算这个分组。分组按请求时 Key 所属的分组算：用户排行只算各用户在这个分组 Key 上的用量，一个用户的 Key 分属几个分组时，会出现在几个分组里。”；模型——有 `ops.dashboard_model_filter` 时“运行类图表也只算这个模型。”，没有时“运行类图表（RPM / TPM、时长、错误）后端不支持按模型，仍显示全站。”
- 选中后范围说明行右侧出现可移除胶囊“分组：高级组 ✕” / “模型：claude-opus-4 ✕”（模型名等宽），点胶囊即清除。
- 参数映射：

| 接口 | 分组筛选 | 模型筛选 |
|---|---|---|
| `admin/usage/stats`、`dashboard/trend`、`dashboard/models`、`dashboard/groups`、`dashboard/users-ranking`、`dashboard/users-trend`、`dashboard/request-types` | `group_id=<id>` | `model=<name>&model_source=<requested \| upstream \| mapping>`（筛选 sheet 选出的是 requested；从上游 / 映射口径的排行进模型页时用那个口径） |
| `ops/dashboard/*`（throughput-trend、overview、latency-histogram、error-trend、error-distribution、openai-token-stats） | `group_id=<id>` | 有 `ops.dashboard_model_filter` 且口径为 requested / upstream：`model=<name>&model_source=<口径>`；mapping 口径或没有该能力：不传 model，卡头加一行“运行类图表不支持按这个模型筛选，这里显示全站” |

注意：`dashboard/models` 的 `model_source` 是“按哪种模型名分组”的维度，不是筛选条件；`ops/dashboard/*` 的 `model_source` 只认 requested / upstream，传 mapping 返回 400。

### 1.3 数据来源

| 区块 | 请求 | 关键参数 | 能力 / 降级 |
|---|---|---|---|
| 计费趋势 · 合计 | `GET /admin/usage/stats` | 范围、筛选、`timezone` | — |
| 计费趋势 · 对比 | `GET /admin/usage/stats` | 对比窗口、同一筛选 | 失败只隐藏增减行 |
| 计费趋势柱图、利润明细 | `GET /admin/dashboard/trend` | 范围、筛选、`granularity=hour \| day` | 点里没有 `account_cost` 键（旧服务端）：利润逐段调 `usage/stats?start_time=&end_time=`（今天每小时一次、30 天 30 次，并发 4），失败的段显示 `—` |
| 排行 · 模型 | `GET /admin/dashboard/models` | 范围、分组筛选、`model_source=requested` | — |
| 排行 · 用户 | `GET /admin/dashboard/users-ranking` | 范围、筛选、`limit=5`、`sort_by=actual_cost` | vendor 不显示；没有 `dashboard.users_ranking_sort` 时不传 `sort_by`，也没有 `total_users` |
| 排行 · 分组 | `GET /admin/dashboard/groups` | 范围、模型筛选 | — |
| RPM / TPM 趋势 | `GET /admin/ops/dashboard/throughput-trend` | 见 1.4 | 运维监控关闭：换成“运维监控未开启” |
| 更多图表磁贴 | 见第 2 节各图 | 磁贴出现在屏幕上时才请求 | — |

排行卡只请求当前选中的那一段；切到另一段时再请求，结果缓存到范围或筛选改变为止。

**响应字段**（本页用到的）：

- `usage/stats`：`total_requests`、`total_tokens`、`total_input_tokens`、`total_output_tokens`、`total_cache_creation_tokens`、`total_cache_read_tokens`、`total_cost`、`total_actual_cost`、`total_account_cost`（可缺省）、`average_duration_ms`、`endpoints[]`、`upstream_endpoints[]`（各 `{endpoint, requests, total_tokens, cost, actual_cost}`，无数据时省略）。
- `dashboard/trend`：`trend[]{date, requests, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, total_tokens, cost, actual_cost, account_cost?}`、`granularity`、`query`。`date`：按小时 `2026-10-16 09:00`，按天 `2026-10-16`（按传入 TZ）。
- `dashboard/models`：`models[]{model, requests, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, total_tokens, cost, actual_cost, account_cost}`；mapping 口径时 `model` 形如 `claude-opus-4 -> claude-opus-4-20250514`。
- `dashboard/groups`：`groups[]{group_id, group_name, requests, total_tokens, cost, actual_cost, account_cost}`。
- `dashboard/users-ranking`：`ranking[]{user_id, email, username, actual_cost, cost, account_cost, requests, tokens}`、`total_users`、`total_actual_cost`、`total_cost`、`total_account_cost`、`total_requests`、`total_tokens`（`limit` 默认 12、最大 50；`sort_by` 非法 400 `INVALID_SORT_BY`）。

### 1.4 字段 → 显示

**计费趋势卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “计费趋势”；右侧图例：灰柱“实际”、点线“标准（点线）” | — |
| 大数标签 | — | “实际扣费 · <范围名>”；选中柱时为该桶全名（`10月16日 8:00–9:00`、当前小时 `9:00–9:41`、按天 `10月14日 周三`） | — |
| 大数 | usage/stats `total_actual_cost`；选中时为该点 `actual_cost` | 金额 | 请求失败 `—`，卡内错误行 |
| 增减 | `total_actual_cost` ÷ 对比窗口 `total_actual_cost` − 1 | `↑ 8.2% · 比昨天同时` | 对比为 0 或缺失：`比昨天同时 —` |
| 选中副行 | 该点 `cost`、`requests` | `标准 $x · 请求 n · 再点一下取消` | — |
| 柱 | 每桶 `actual_cost` | 灰柱；范围含“现在”时最后一根加深，横轴写“现在”（按小时）/“今天”（按天） | 整段都是 0：保留坐标轴，图上写“这个范围内没有用量” |
| 点线 | 每桶 `cost`（标准） | 点线 | — |
| 横轴 | 桶 | 按小时 `0时…9时`，按天 `10/10`；≤ 8 桶每个都标，≤ 12 隔 3，≤ 24 隔 6，更多隔 7（按天从最后一个往前数） | — |
| 账号成本 / 标准 / 利润 三格 | `total_account_cost`；`total_cost`；`total_actual_cost − total_account_cost` | 金额 | `total_account_cost` 缺失：账号成本、利润 `—` |
| 请求 · Tokens · 平均耗时 | `total_requests`；`total_tokens`；`average_duration_ms` | `18,204`；`96.4M`；耗时 | 请求 0 时平均耗时 `—` |
| 卡底 | 桶数 | “全部 10 小时 · 计费明细 ›” / “全部 7 天 · 计费明细 ›” | — |

**利润明细卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “利润明细”；右侧“实际扣费 − 账号成本” | — |
| 大数 | usage/stats `total_actual_cost − total_account_cost`；选中时该桶利润 | 标签“利润 · <范围名>” / 桶全名 | `total_account_cost` 缺失 `—` |
| 增减 | 对比窗口的利润 | 两边都 > 0：百分比；任一边 ≤ 0：金额差 `↑ $86.20 · 比昨天同时` | 对比缺失 `—` |
| 选中副行 | 该桶实际、账号成本 | `实际 $x · 账号成本 $y · 再点一下取消` | — |
| 柱 | 每桶 `actual_cost − account_cost` | 可为负：从 0 往下画，`RuleMark(y: 0)` 零线，y 轴范围含 0，负柱不换颜色 | 整段扣费都为 0 才写“这个范围内没有扣费”；全部亏损不算空 |
| 明细表（最近 4 段，最新在上） | 时段 / 实际 / 账号成本 / 利润 | 时段：按小时 `8:00–9:00`（当前 `9:00–9:41`），按天 `16日 周五`；选中的桶这一行高亮 | 降级时失败段的账号成本、利润 `—` |
| 卡底 | — | “全部 10 小时 · 利润明细 ›” | — |

分段取整：实际、账号成本各自以 usage/stats 的合计（换算成分）为总数，按各桶原值用最大余额法分到分，利润 = 两者之差。这样各行之和等于合计；范围为今天时，合计利润等于首页 6 格的利润（后端统计未过期时）。

**排行卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “排行”；右侧“实际扣费 · 前 5” | — |
| 分段 | — | 模型 · 用户 · 分组（本机记住上次所选，见 0.1） | vendor 无“用户” |
| 分组筛选下的用户说明 | — | “按请求时 Key 所属的分组统计：只算各用户在「高级组」Key 上的用量。” | 无分组筛选不显示 |
| 行 · 序号 | 名次 | 1–3 加粗 | — |
| 行 · 名称 | 模型 `model`（等宽）；用户 `username`，空时 `email`；分组 `group_name` | 单行截断 | — |
| 行 · 占比条 | 该行 `actual_cost` ÷ 合计；模型 / 分组的合计 = 全部行之和；用户的合计 = `total_actual_cost` | 细条 | — |
| 行 · 金额 | `actual_cost` | 金额 | — |
| 当前段正是筛选维度 | — | 不列排行，显示“已筛选分组：高级组　清除筛选” | — |
| 卡底（行数 > 5） | 模型 / 分组的总行数 | “全部 12 个模型 · 含上游口径 ›”、“全部 9 个分组 ›”、“查看前 50 位用户 ›” | — |
| 空 | — | “这个范围内没有模型用量”（用户 / 分组同理） | — |

**RPM / TPM 趋势卡**（与第 2 节同一组件 `PerfTrendBody`）

请求 `GET /admin/ops/dashboard/throughput-trend?start_time=&end_time=[&group_id=][&model=&model_source=]`：`end_time` = 现在向下取整到整分钟，`start_time` = `end_time` − N 小时（N = 1 / 6 / 24）。不传 `mode`（后端不读）。后端按窗口定桶长：≤ 2 小时 60 秒、≤ 24 小时 300 秒、更长 3600 秒，响应 `bucket` 为 `1m` / `5m` / `1h`；不认识的值按这条规则从窗口长度推算。响应 `points[]{bucket_start, request_count, token_consumed, switch_count, qps, tps}`（`qps` / `tps` 已四舍五入到 0.1，不用）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “RPM / TPM 趋势”；右侧“截至现在 · 运维监控” | — |
| 模型筛选提示 | 见 1.2 | “运行类图表不支持按模型筛选，这里显示全站” | — |
| 窗口分段 | — | 近 1 小时 · 近 6 小时 · 近 24 小时 | — |
| 指标分段 | — | RPM · TPM（`route.metric` 优先于记忆值） | — |
| 每点覆盖秒数 | `min(bucket_start + 桶秒数, end_time) − max(bucket_start, start_time)` | — | ≤ 0 的点丢弃 |
| 每点速率 | RPM = `request_count × 60 ÷ 覆盖秒数`；TPM = `token_consumed × 60 ÷ 覆盖秒数` | 见 0.5 | — |
| 大数 | 未选中：最新一点；选中：该点 | 标签“RPM · 最新一桶 09:40” / “RPM · 09:12” | — |
| 副行 | 峰值 = 各点最大值；平均 = Σ数量 × 60 ÷ Σ覆盖秒数 | `峰值 52 · 平均 44 · 近 1 小时`；选中时 `09:12 · RPM 47 · 再点一下取消` | — |
| 折线 + 面积 | 每点速率 | `LineMark` + `AreaMark`；选中点画竖线与圆点 | 全为 0：“这个时间范围内没有请求” |
| 横轴 | `bucket_start`（TZ） | 近 1 小时每 15 分钟、近 6 小时每 2 小时、近 24 小时每 6 小时，只标整刻度，`HH:mm` | — |
| 说明 | 桶长、窗口起点 | “每桶 1 分钟，速率 = 数量 × 60 ÷ 这一桶实际覆盖的秒数；窗口从 08:41 到现在，首尾不满一桶的按覆盖时长折算。RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。” | — |
| 更新时间 | 最后一次成功 | “更新于 09:41:00 · 前台每 30 秒刷新” | — |
| 卡底 | 点数 | “性能明细 · 61 桶 · 最新在上 ›” | — |
| 性能明细 sheet | 每点 | 标题“性能明细”，左上“关闭”；说明“最新在上 · 近 1 小时 · 每桶 1 分钟。点一行，图上选中这个时间。”；行：`09:40` / `09:40 · 只覆盖 23 秒`（不满一桶），`RPM 46 · TPM 240K`；点行关闭 sheet 并选中该点 | — |
| 运维监控未开启 | `ops_monitoring_enabled=false` 或 404 `OPS_DISABLED` | 卡体换成“运维监控未开启”组件（10 章 §7.2 的 `OpsDisabledNotice`，按 `disabled_reason` 写原因、是否可在手机上开启；本章所有“运维监控未开启”都用它，不另做） | — |

注意：首页 6 格的 RPM / TPM 取 `dashboard/rates`（近 5 分钟平均），本图每点是一个桶，两者不必相等。

**更多图表卡**

| 界面元素 | 字段 / 计算 | 格式与文案 |
|---|---|---|
| 卡头 | 图表数 | “更多图表”；右侧“12 张”（运维关闭 6 张，vendor 4 张） |
| 4 个磁贴 | 运维开启：Token 使用趋势、用户用量趋势、错误趋势、请求时长分布；运维关闭：Token 使用趋势、用户用量趋势、端点分布、请求类型 | 每块：标题、大数 + 单位、说明、缩略图（定义见第 2 节各图“磁贴”）；运行类图表在当前模型筛选下只能显示全站时，说明前加“全站”标签 |
| 卡底 | — | “全部图表 · 计费 2 · 用量 4 · 运行 6 ›”（运维关闭写“运行 未开启”） |

### 1.5 交互与写操作

- 本页没有写操作。
- 图表点选：整张图是一个点按 / 拖动区（`.chartXSelection`），按 x 坐标落到桶；再点同一桶取消；改范围、窗口、筛选时清除选中。不给每根柱子单独的点按区（30 天时柱宽只有约 10pt）。
- 排行行：模型 → `analyticsModel(model, source: requested)`；用户 → 用户详情（`user_id`）；分组 → 分组详情（`group_id`）。
- VoiceOver：图表提供 `AXChartDescriptor`（x = 桶标签，y = 值）；每根柱 / 点的 `accessibilityLabel` 如“10月16日 9:00 到 9:41，实际扣费 $229.00”。

### 1.6 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 每张卡内 `ProgressView`，卡片保持高度 | — |
| 单卡失败 / 超时 | 卡内“加载失败”或“统计较慢，加载超时”+“重试本项”；有旧数据时保留，并在大数下写“更新失败 · 显示的是 09:40 的数据” | 重试本项 |
| 范围内无用量 | 柱图写“这个范围内没有用量”；合计 `$0.00`、请求 0 | — |
| 400 | 卡内“请求参数无效”，记日志 | 不重试 |
| 404 `OPS_DISABLED` | RPM / TPM 卡、运行类磁贴换成“运维监控未开启” | 见监控章节组件 |
| 403 | 不应出现（0.7 已隐藏）；出现时该卡写“当前身份无权查看” | — |
| 401 / 423 等 | 全局处理（通用约定） | — |

### 1.7 刷新策略

- 进入页面：所有卡并发请求。
- 范围含“现在”时，前台每 60 秒刷新计费趋势、利润明细、排行（只刷当前段）与可见磁贴；过去的范围不自动刷新。刷新时“现在”前移，start 不变。
- RPM / TPM 卡：可见且前台时每 30 秒刷新；切窗口立即重载；离开页面或进入后台停止。
- 下拉刷新：全部卡立即重载。
- 后端 dashboard 查询有 30 秒进程内缓存，throughput-trend / overview 有 5 秒缓存，刷新间隔不短于它们。

### 1.8 对现有代码的改动点

- `NativeApp/Features/AnalyticsView.swift` `AnalyticsView`：重写为卡片流 `AnalyticsView(route:)`。删除 `init(accountID:groupID:)`、“今日 / 近7天 / 本月”按钮、`AnalyticsFilterView`（数字 ID 输入框）；“统计汇总”“实际消费趋势”“模型统计”“分组统计”四个分区由计费趋势卡、利润卡、排行卡取代；删除“上游成本”“扣费与成本差额”“差额仅为…”文案。保留 `load(_:fixture:operation:)` 的独立加载写法与 `isCurrent` 守卫。
- 新建 `NativeApp/Features/Analytics/`：`AnalyticsSession.swift`（范围、筛选、各卡 `DashboardLoadState`，二级页共用；内含 `AnalyticsMemory`：按站点读写 0.1 列出的选择项，初始化顺序“记忆 → route 默认值”，失效规则同 0.1）、`AnalyticsCards.swift`（BillingTrendCard、ProfitCard、RankCard、PerfCard、MoreChartsCard）、`AnalyticsCharts.swift`（柱 + 点线 + 选中、支持负值零线的柱图；堆叠柱；折线面积图）、`AnalyticsSheets.swift`（自定义范围、筛选）。
- `Sources/Sub2Core/UsageAnalytics.swift`
  - `AnalyticsQuery`：新增 `modelSource`、显式 `granularity`（替换 `hourly` 的“≤ 3 天按小时”：只有单日范围按小时）；`timeZone` 改为必传站点时区（删默认值 `TimeZone.current`）；`start_time` / `end_time` 输出 UTC `Z`；`model_source` 只在有 `model` 时传。`accountID`、`userID` 统计页不再使用。
  - `AnalyticsSummary`：新增 `standardCost`（`total_cost`）、`cacheCreationTokens`、`cacheReadTokens`、`endpoints`、`upstreamEndpoints`；`difference` 改名 `profit`，改注释。
  - `AnalyticsBreakdown`：新增 `standardCost`（`cost`）；`usageAnalysisModels(_:)` 增加 `source` 参数（现在写死 requested）。
  - 新增 `UserSpendingRanking` 解码与 `usageAnalysisUsersRanking(_:sortBy:limit:)`。
- `Sources/Sub2Core/Models.swift` `TrendPoint`：新增 `inputTokens`、`outputTokens`、`cacheCreationTokens`、`cacheReadTokens`（缺省 0）与 `accountCost: Decimal?`（键缺失为 nil，表示旧服务端，不能当 0）；注释写明 `cost` 是标准。
- 新建 `Sources/Sub2Core/AnalyticsRange.swift`（纯逻辑）：选项 → start / end / 粒度 / 范围名 / 说明行 / 对比窗口 / 对比文案 / 完整桶列表（补零用）。新建 `Sources/Sub2Core/ProfitRows.swift`：最大余额法分到分。
- `Sources/Sub2Core/DashboardTrend.swift` `DashboardTrendMetric.actualCost.label`：“实际消费”改“实际扣费”（概览也在用）。
- 测试：`Tests/Sub2CoreTests/UsageAnalyticsTests.swift` 补新解码与 `model_source`；新增 `AnalyticsRangeTests`（跨月、2 月、夏令时、单日按小时、上月同期取月末）、`ProfitRowsTests`；`UITests/AnalyticsUITests.swift` 按新标识重写，并覆盖记忆（第一次从搜索进是近 7 天；改成 30 天后从概览进仍是 30 天；换站点回到入口默认值）；AppModel 的 UI 测试桩补齐新接口。

---

## 2. 更多图表（`analyticsMore`）

### 2.1 入口与导航

- 进入：统计分析的更多图表磁贴（`chart` = 该图，进入后滚到它并高亮卡片边框一次）、“全部图表”（停在顶部）、`topic` 参数（滚到该主题）。
- 导航栏：标题“更多图表”；副标题“<站点名> · <范围名>”；右侧筛选按钮（同 1.2）。
- 吸顶条（`safeAreaInset(edge: .top)`）：左侧主题胶囊“计费 2”“用量 4”“运行 6”（运维关闭为“运行 —”；当前所在主题高亮，随滚动更新，滚到底高亮最后一个），点胶囊滚到该主题；右侧范围 `Menu`（今天 / 近 7 天 / 近 30 天 / 自定义…，自定义打开 1.2 的 sheet）。吸顶条下是范围说明行和筛选胶囊。
- 主题与图表（按顺序）：
  - 计费：计费明细、利润明细
  - 用量：Token 使用趋势、用户用量趋势、端点分布、请求类型
  - 运行（主题头右侧小字“需开启运维监控”）：RPM / TPM 趋势、平均账号切换、请求时长分布、错误趋势、错误分布、Token 请求统计
- 运维监控关闭时，“运行”主题整体换成一张“运维监控未开启”卡。vendor 没有“运行”主题、用户用量趋势、请求类型。
- 每张图卡头：标题 + 窗口（范围名；RPM / TPM 写“截至现在”；Token 请求统计写它的统计窗口）+ 运行类加“ · 运维监控”；模型筛选不支持时卡头下一行提示（同 1.2）。
- 去向：用户用量趋势的行 → 用户详情；Token 请求统计无下钻。

### 2.2 数据来源（逐图）

范围、筛选、`timezone` 参数规则见 0.2 与 1.2，下表只写各图特有的部分。运行类图表的桶长由后端按范围长度定：≤ 2 小时 60 秒、≤ 24 小时 300 秒、更长 3600 秒。

| 图 | 请求 | 特有参数 | 能力 / 降级 |
|---|---|---|---|
| 计费明细 | 复用 1.3 的 trend 与 usage/stats | — | — |
| 利润明细 | 复用 1.3 的 trend 与 usage/stats | — | 同 1.3 |
| Token 使用趋势 | 复用 trend | — | — |
| 用户用量趋势 | `GET /admin/dashboard/users-trend` | `granularity`、`limit=12`、`metric=tokens \| actual_cost` | 带筛选且没有 `dashboard.users_trend_filtered_metric`：隐藏“实际扣费”分段，只给 Tokens |
| 端点分布 | 复用计费合计那次 usage/stats 的 `endpoints` / `upstream_endpoints` | — | — |
| 请求类型 | `GET /admin/dashboard/request-types` | 不能带 `request_type` / `stream`（带了 400） | 没有 `dashboard.request_types`：5 次 `usage/stats?request_type=stream \| sync \| ws_v2 \| cyber \| live`（并发 4）取 `total_requests` |
| RPM / TPM 趋势 | 同 1.4 | 自有窗口，不跟页面范围 | — |
| 平均账号切换 | `GET /admin/ops/dashboard/throughput-trend` | 页面范围（end 不取整） | — |
| 请求时长分布 | `GET /admin/ops/dashboard/latency-histogram` + `GET /admin/ops/dashboard/overview` | 页面范围 | — |
| 错误趋势 | `GET /admin/ops/dashboard/error-trend` + overview（与请求时长分布共用一次） | 页面范围 | — |
| 错误分布 | `GET /admin/ops/dashboard/error-distribution` | 页面范围 | — |
| Token 请求统计 | `GET /admin/ops/dashboard/openai-token-stats` | `start_time` / `end_time`（页面范围）、`top_n=100`、`group_id`；不传 model | 跨度超过 31 天 + 1 小时：400 `OPS_TIME_RANGE_TOO_LARGE`（`metadata.max_days=31`）→ 改用 `time_range=30d`；没有 `ops.token_stats_custom_range`：`time_range` 取能盖住“范围首日 00:00 到现在”的最小值（`1d` / `15d` / `30d`），盖不住用 `30d` |

响应字段：

- users-trend：`trend[]{date, user_id, email, username, requests, tokens, cost, actual_cost}`。
- request-types：`request_types[]{request_type, requests, total_tokens, cost, actual_cost, account_cost}`，只含有用量的类型，同数按类型编号升序，没有数据为 `[]`。
- throughput-trend：见 1.4；`switch_count` = 该桶 upstream_errors 里 failover 类事件数。
- latency-histogram：`total_requests`、`buckets[]{range, count}`（只算成功请求；`range` 固定为 `0-100ms`、`100-200ms`、`200-500ms`、`500-1000ms`、`1000-2000ms`、`2000ms+`）。
- overview：`success_count`、`error_count_total`、`business_limited_count`、`error_count_sla`、`request_count_total`、`request_count_sla`、`sla`、`error_rate`、`duration{p50_ms, p90_ms, p95_ms, p99_ms, avg_ms, max_ms}`、`ttft{同上}`。
- error-trend：`bucket`、`points[]{bucket_start, error_count_total, business_limited_count, error_count_sla, upstream_error_count_excl_429_529, upstream_429_count, upstream_529_count}`。
- error-distribution：`total`、`items[]{status_code, total, sla, business_limited}`（只算客户端最终 ≥ 400 的行；`status_code` 取上游状态码，没有时取客户端状态码；按 total 降序，最多 20 行）。
- openai-token-stats：`time_range`（自定义时为 `custom`）、`start_time`、`end_time`（UTC 回显）、`items[]{model, request_count, avg_tokens_per_sec, avg_first_token_ms, total_output_tokens, avg_duration_ms, requests_with_first_token}`、`total`。行按 `usage_logs.model` 分组，有模型映射时行名可能是上游模型名。

### 2.3 字段 → 显示（逐图）

卡片尺寸（列表里）和全屏尺寸（第 3 节单图页）共用同一个 body，区别写在“全屏”列。

**计费明细**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 头行 | 合计 / 选中桶 | `实际 $1,284.50`；选中 `10月16日 8:00–9:00 · $229.00`；右侧图例“实际 · 标准（点线）” | — |
| 图 | 同计费趋势卡 | 高 112pt | 全屏 170pt |
| 三数 | 账号成本、标准、利润（同 1.4） | 金额 | — |
| 表（最新在上） | 时段 / 实际 / 标准 / 请求 | 卡片 6 行 +“展开全部 N 小时 ⌄” | 全屏显示全部 |
| 磁贴 | `total_actual_cost` | `$1,284.50` / “实际扣费” | — |

**利润明细**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 头行 | 合计利润 / 选中桶 | `利润 $772.42`；选中 `10月16日 8:00–9:00 · 利润 $90.12`；右侧“实际扣费 − 账号成本” | — |
| 图 | 同利润卡（可为负） | 高 112pt | 全屏 170pt；“这个范围内没有扣费” |
| 三数 | 实际扣费、账号成本、利润（合计） | 金额 | — |
| 表 | 时段 / 实际 / 账号成本 / 利润（最大余额法） | 卡片 6 行 + 展开 | 全屏全部 + 末行“合计”+ 说明“每小时的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。”（按天写“每天”） |
| 磁贴 | 合计利润 | `$772.42` / “利润” | — |

**Token 使用趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 图例按钮 ×4 | 输入 `input_tokens`、输出 `output_tokens`、缓存读 `cache_read_tokens`、缓存写 `cache_creation_tokens`；数值为合计或选中桶的值 | 色块 + 名称 + compact 数；点一个只看这一项（其余变淡），再点恢复 | — |
| 图 | 每桶四段堆叠；只看一项时为单色柱 | 三种灰 + 描边，缓存读用横纹（Swift Charts 用 `ImagePaint`；做不到改“描边 + 透明度”），相邻段之间留 1.5pt 表面色缝 | 全为 0：“这个范围内没有用量” |
| 底注 | 合计、缓存读占比 = Σcache_read ÷ Σtotal_tokens | 未选中“合计 96.4M · 缓存读占 54% · 点图例只看一项”；选中“10月16日 9时 · 合计 9.8M”；只看一项“只看缓存读，再点一次图例恢复全部” | — |
| 表 | 时段 / 输入 / 输出 / 缓存读 / 缓存写 | — | 只在全屏显示 |
| 磁贴 | 合计 | `96.4M` Tokens / “缓存读占 54%” | — |

**用户用量趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 分段 | — | Tokens · 实际扣费（默认 Tokens） | 降级时只有 Tokens |
| 行 | 按 `user_id` 归并各桶；按 Σ所选指标降序 | 序号、名称（`username`，空时 `email`）、迷你折线（该用户每桶值，缺桶补 0，各用各的纵轴）、合计（Tokens compact / 金额） | 卡片前 5 行，全屏 12 行；无数据“这个范围内没有用户用量” |
| 底注 | — | “按 Tokens 取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。”（全屏去掉“这里显示前 5 位”） | — |
| 点行 | — | 进用户详情 | — |
| 磁贴 | 第 1 名 | `12.4M` Tokens / “第 1 · Nova 工作室”；无数据 `—` / “没有用户用量” | — |

**端点分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 分段 | — | 入站端点 · 上游端点 | — |
| 行 | `endpoints[]` / `upstream_endpoints[]`；占比 = `requests` ÷ Σ`requests` | 路径（等宽）、请求数、占比条 + %、副行“实际 $x”（`actual_cost`） | 数组缺省或空：“这个范围内没有用量” |
| 磁贴 | 入站第一行 | `60%` / “/v1/messages 占请求” | `—` / “没有用量” |

**请求类型**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 构成条 | 5 类请求数占比 | 0 的类型不画 | — |
| 行 ×5（固定顺序） | 流式 `stream`、同步 `sync`、WS `ws_v2`、安全策略 `cyber`、Live `live`；响应里没有的补 0 | 色块（0 为空心）、名称、请求数、占比 | 合计为 0：“这个范围内没有用量” |
| 磁贴 | 流式占比 | `72%` / “流式占请求” | `—` |

**RPM / TPM 趋势**：同 1.4。在列表与全屏都不跟页面范围；全屏页不显示范围条，只保留筛选胶囊。磁贴：近 1 小时最新一点的 RPM / “最新一桶 · 09:40”，缩略图为近 1 小时 RPM 折线。

**平均账号切换**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 三数 | 切换次数 = Σ`switch_count`；平均 · 次/请求 = Σ`switch_count` ÷ Σ`request_count`；最高 · 次/请求 = 有请求的点里 `switch_count ÷ request_count` 的最大值 | 千分位；3 位小数 | 请求为 0：`—` |
| 折线 | 每点 `switch_count ÷ request_count`（`request_count` = 0 的点不画） | 高 96pt；单日每 3 小时（今天，末尾标“现在”）或 6 小时（过去的单天）标“N时”；多日按天标日期，约 4 个刻度 | 全屏 150pt |
| 底注 | 桶长 | “曲线每 5 分钟一点。请求因限流、过载或错误换到另一个账号，记一次切换。”（> 24 小时写“每小时一点”） | — |
| 磁贴 | 平均 | `0.012` / “平均 · 次/请求” | — |

**请求时长分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 直方图 6 列 | `buckets[]`：`0-100ms`→`<100ms`、`100-200ms`→`100–200`、`200-500ms`→`200–500`、`500-1000ms`→`0.5–1s`、`1000-2000ms`→`1–2s`、`2000ms+`→`≥2s`；柱高 = count ÷ 最大 count；柱上 % = count ÷ `total_requests`（0 位小数） | — | `total_requests` = 0：“这个范围内没有成功请求” |
| 底注 | `total_requests` | “成功请求 18,204 次的总耗时分布” | 无请求时不显示 |
| 分位表 | 行“总耗时”= overview `duration`，“首字”= overview `ttft` | 卡片列 P50 · P90 · P95 · P99；全屏另加“平均”“最长” | 无请求或字段 null：`—` |
| 磁贴 | `duration.p50_ms` | `2.4s` / “P50 总耗时” | `—` |

**错误趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 三数 | 错误 = Σ`error_count_total`；错误率 · SLA = overview `error_rate`；SLA 口径 = Σ`error_count_sla` | 千分位；百分比 | — |
| 堆叠柱 | 每段两层：SLA 错误 = `error_count_sla`（红）、业务限制 = `business_limited_count`（灰），两层之和 = `error_count_total`。300 秒桶（范围 ≤ 24 小时）按小时合计；3600 秒桶按天（TZ）合计；60 秒桶（范围 ≤ 2 小时）按 5 分钟合计 | 高 100pt | 全屏 150pt；合计为 0：“这个范围内没有错误” |
| 图例 | Σ各层 | “SLA 错误 317 · 业务限制 80” | — |
| 上游分项行 | Σ`upstream_429_count`、Σ`upstream_529_count`、Σ`upstream_error_count_excl_429_529` | “上游失败（含重试成功）：429 186 · 529 64 · 其他 53” | — |
| 底注 | — | “后端每 5 分钟一桶，这里按小时合计。错误率 = SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制（用户自己的余额、额度、频率限制）。” | — |
| 磁贴 | overview `error_rate` | `1.7%` / “错误率 · SLA” | — |

后端无此能力 → App 退路：设计稿把“上游 429 / 上游 529 / 其他上游 / 非上游 / 业务限制”叠成 `error_count_total`。但 error-trend 的三个上游计数没有 status ≥ 400 条件，包含已重试成功的上游失败行，不是 `error_count_total` 的子集，叠起来会出现负的“非上游”。所以柱子只叠 SLA 错误 + 业务限制，上游分项单列一行文字。“今天”范围的错误率是今日 SLA 口径，首页 6 格错误率是近 5 分钟，两处不同属正常。

**错误分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 行（按 total 降序） | `status_code`、`sla`、`business_limited`、`total`；占比 = `total` ÷ 响应 `total` | 状态码徽章（codeTone）；条：SLA 部分用状态色、业务限制部分灰，长度相对第一行 total；条数；占比（0 位小数） | 响应 total 为 0：“这个范围内没有错误” |
| 图例 | — | “429 限流 · 其他错误（含 504、529）· 业务限制（不计 SLA）” | — |
| 磁贴 | 第一行 | `47%` / “429 占错误”（码随第一行） | `—` |

**Token 请求统计**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 分段 | — | 按请求 · 按速度 · 按首 Token（本地排序：`request_count` 降序 / `avg_tokens_per_sec` 降序 / `avg_first_token_ms` 升序，null 排最后） | — |
| 表 | 模型 / 输出/秒 `avg_tokens_per_sec` / 首 Token `avg_first_token_ms` / 平均时长 `avg_duration_ms` | 模型等宽；数值 1 位小数；耗时按分位格式 | 卡片 5 行，全屏 9 行；null `—`；分组筛选下没有行：“这个分组在窗口内没有模型用量” |
| 模型筛选 | 筛选的模型 | 该行高亮；不在前列时追加到末尾 | — |
| 底注 | 窗口 | 自定义范围生效：“统计窗口与所选范围一致。”；退路：“统计窗口近 15 天，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。”；盖不住：“统计窗口近 30 天，截至现在：后端最长只到 30 天，盖不住所选范围，这里只是最近 30 天的速度。”；分组筛选时加“只列「标准组」用到的模型。” | — |
| 磁贴 | `avg_tokens_per_sec` 最高的一行 | `86` 输出/秒 / “最快 · gpt-4.1-mini” | `—` |

### 2.4 交互与写操作

- 无写操作。
- 主题胶囊：点按滚到该主题（`ScrollViewReader`）；滚动时按吸顶条下沿所在的主题更新高亮。
- 图表点选同 1.5；Token 图例、各分段只影响本图。

### 2.5 状态

- 每张图独立：加载中卡内 `ProgressView`；失败“加载失败 · 重试本项”；空态见各图。
- 运维监控关闭：“运行”主题一张“运维监控未开启”卡；主题胶囊“运行 —”仍可点（滚到这张卡）。
- 404 `OPS_DISABLED`（开关刚被关）：运行类各图都换成未开启卡，并刷新 `/admin/me`。
- Token 请求统计 400 `OPS_TIME_RANGE_TOO_LARGE`：自动改用 `time_range=30d` 重试一次，底注写“盖不住”那句。
- 运维错误日志按服务器设置保留（默认 30 天，配置 `ops.cleanup.error_log_retention_days`）。范围起点早于 30 天前时，错误趋势、错误分布、平均账号切换卡头下加一行“运维日志默认只保留 30 天，更早的时段可能没有记录”。

### 2.6 刷新策略

- 卡片在屏幕上出现时才请求（`LazyVStack` + `onAppear`），结果按（范围、筛选）缓存到会话结束；范围或筛选改变时，已加载过的卡重新请求，没出现过的仍等出现。
- 范围含“现在”：可见卡每 60 秒刷新；RPM / TPM 每 30 秒。
- 下拉刷新：所有已加载的卡重载。

### 2.7 对现有代码的改动点

- 新建 `NativeApp/Features/Analytics/AnalyticsMoreView.swift`（主题列表、吸顶条、懒加载）与 `AnalyticsChartBodies.swift`（12 个 body，参数 `size: .card | .full`）。
- 新建 `Sources/Sub2Core/OpsAnalytics.swift`：`OpsQuery`（start / end / groupID / model / modelSource，输出 1.2 的参数映射）与 `OpsLatencyHistogram`、`OpsErrorTrend`、`OpsErrorDistribution`、`OpsTokenStats` 解码；`APIClient` 新增 `opsLatencyHistogram(_:)`、`opsErrorTrend(_:)`、`opsErrorDistribution(_:)`、`opsTokenStats(_:)`，参数都是 `OpsQuery`。
- **ops overview 不在本章定义**：方法与模型归 10 章（`OpsOverview`，`Sources/Sub2Core/OpsMonitoring.swift`；10 章 §1.7 已删除 `dashboardMonitoring()` / `OpsReply` / `OpsSnapshot`，去留以 10 章为准）。本章调用 10 章“起止时间 + 筛选”的那个重载，签名以 10 章为准；本章依赖它：① 接受 `start_time` / `end_time` 之外的 `group_id`、`model`、`model_source`（与 `OpsQuery` 同一套映射）；② `OpsOverview` 解码 `success_count`、`error_count_total`、`business_limited_count`、`error_count_sla`、`request_count_total`、`request_count_sla`、`sla`、`error_rate`、`duration` 与 `ttft`（各含 `p50_ms`、`p90_ms`、`p95_ms`、`p99_ms`、`avg_ms`、`max_ms`）。本章不另建 `OpsOverviewWindow` 之类的模型。
- `Sources/Sub2Core/UsageAnalytics.swift`：新增 `UserTrendPoint`、`RequestTypeStat` 解码与 `usageAnalysisUsersTrend(_:metric:limit:)`、`usageAnalysisRequestTypes(_:)`。
- `Sources/Sub2Core/PerformanceTrend.swift`
  - 新增 `windowStart` / `windowEnd`（请求时的窗口，由 `APIClient` 解码后写入）、`Point.switchCount`（`switch_count`，缺省 0）。
  - `rate(_:metric:)` 改为除以覆盖秒数；新增 `coveredSeconds(_:)`、`peak(_:)`、`average(_:)`；`Bucket` 增加未知值兜底（按窗口长度推算）。
- `Sources/Sub2Core/APIClient.swift` `dashboardPerformanceTrend(start:end:)`：改为 `dashboardPerformanceTrend(_ query: OpsQuery)`（去掉 `mode=auto`；带上分组 / 模型筛选）；保留 30 天上限。
- `NativeApp/Session/AppModel.swift` `dashboardPerformanceTrend(hours:)`：`end` 向下取整到整分钟；增加筛选参数；UI 测试桩按覆盖秒数造首尾残桶。
- `NativeApp/Features/PerformanceTrendView.swift` `PerformanceTrendView`：抽成 `PerfTrendBody(filter:size:startMetric:)`，补“最新一桶”大数、峰值 / 平均副行、说明文案、明细里的“只覆盖 N 秒”；错误分支按 `OPS_DISABLED` 显示未开启组件（不再是红字“站点需启用运行监控…”）；`rateLabel` 改用 0.5 的 RPM 格式（现在一律 compact）。概览若保留第 4 个趋势页，也用这个组件（概览章节定）。
- `docs/API_COMPATIBILITY.md:54`“边界桶仍按完整桶宽计算”改为覆盖秒数口径。
- 测试：`Tests/Sub2CoreTests/PerformanceTrendTests.swift` 改为覆盖秒数（1 分钟、5 分钟残桶，首尾都不满）；新增 `OpsAnalyticsTests`（error-trend 按小时 / 按天合计、两层之和等于 total）。

---

## 3. 单图页（`analyticsChart`）

### 3.1 入口与导航

- 进入：计费趋势卡底“计费明细 ›”（`billing`）、利润明细卡底“利润明细 ›”（`profit`）。其余图在更多图表列表里看，不提供单图入口（目录网格、单图翻页是未选变体）。
- 导航栏：标题为图名；副标题“<主题> · <窗口>”（如“计费 · 今天”）；右侧筛选按钮。
- 页面：范围条（同 1.2）+ 一张全屏 body（第 2.3 节“全屏”列）。

### 3.2 数据来源

同第 2.2 节对应的图，与 `AnalyticsSession` 共用缓存：从统计分析进来时直接显示已加载的数据，不重复请求。

### 3.3 字段 → 显示

见 2.3 计费明细、利润明细的“全屏”列：图高 170pt，表格显示全部桶（最新在上），利润明细末行“合计”并带说明。选中某根柱时表格对应行高亮。

### 3.4 交互与写操作

无写操作；范围、筛选改动写回 `AnalyticsSession` 并按 0.1 写入本机记忆，返回统计分析后保持。

### 3.5 状态

同 1.6。

### 3.6 刷新策略

同 1.7；下拉刷新只重载本图用到的请求。

### 3.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsChartView.swift`，复用 `AnalyticsChartBodies` 的 `.full` 尺寸。现有 `AnalyticsView` 里“逐小时 / 逐日明细”的 `NavigationLink`（标题“消费明细”）由它取代。

---

## 4. 全部排行（`analyticsRank`）

### 4.1 入口与导航

- 进入：排行卡底（`dim` = 当前段）。
- 导航栏：标题 模型分布 / 用户排行 / 分组使用分布；副标题“<站点名> · <范围名>”；右侧筛选按钮。
- 页面：范围条 → 构成条 → 列表。
- 去向：模型行 → `analyticsModel(model, source: 当前口径)`；用户行 → 用户详情；分组行 → 分组详情。

### 4.2 数据来源

| 维度 | 请求 | 参数 | 能力 / 降级 |
|---|---|---|---|
| 模型 | `GET /admin/dashboard/models` | 范围、分组筛选、`model_source=requested \| upstream \| mapping`（随口径菜单） | — |
| 用户 | `GET /admin/dashboard/users-ranking` | 范围、筛选、`limit=50`、`sort_by=actual_cost \| requests \| tokens`（随排序菜单，服务端排序） | 没有 `dashboard.users_ranking_sort`：不传 `sort_by`（后端按实际扣费取前 50），App 在这 50 人里本地重排；没有 `total_users`；vendor 无此页 |
| 分组 | `GET /admin/dashboard/groups` | 范围、模型筛选 | — |

模型、分组的接口返回全部行，排序在本地做；用户的排序变化要重新请求。

### 4.3 字段 → 显示

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 构成条（行数 > 1） | 前 3 名占比 + 其余；按当前指标 | 条上方“前 3 占 62.4%”“合计 $1,284.50”（合计按当前指标格式）；条下图例前 3 个名称 +“其余 9 个模型”/“其余用户 12.3%” | — |
| 列表头 | 行数 | 模型 / 分组：“12 个模型”“9 个分组”，模型非请求口径时加“ · 上游模型 / · 映射”；用户：“前 50 位 · 共 143 位”（`total_users`；降级时只写“前 50 位”） | — |
| 排序菜单（列表头右侧 `Menu`） | — | “按实际扣费 ⌄”；分节“排序”：按实际扣费 / 按请求 / 按 Tokens；模型维度另有分节“模型口径”：请求模型 / 上游模型 / 映射（请求 → 上游） | — |
| 行 · 序号 / 名称 | 同 1.4 排行卡 | 映射口径的 `model` 形如 `a -> b`：名称写 `a`，副行开头写“→ b” | — |
| 行 · 值 | 当前指标：`actual_cost` / `requests` / `tokens`（用户）或 `total_tokens`（模型、分组） | 金额 / 千分位 / compact | — |
| 行 · 占比条 + % | 值 ÷ 合计；用户的合计取 `total_actual_cost` / `total_requests` / `total_tokens` | 1 位小数 | — |
| 行 · 副行 | 用户：`email`（有 username 时）；其余两个指标；“账号成本 $x”（`account_cost`） | 用 ` · ` 连接，如“请求 3,100 · 15M Tokens · 账号成本 $88.20” | — |
| 用户底注 | — | “按<指标>取前 50 位，共 143 位用户有用量。”；降级“用户排行按实际扣费取前 50 位，这里在其中按<指标>重排。”；分组筛选时再加 1.4 那句 Key 分组说明 | — |
| 当前维度是筛选维度 | — | 整页只显示“已筛选分组：高级组　清除筛选” | — |
| 空 | — | “这个范围内没有模型用量” | — |

### 4.4 交互与写操作

- 无写操作。排序指标（每个维度各记一份）与模型口径按 0.1 在本机记住，返回再进、下次进入都保持。
- 切口径：重新请求 `dashboard/models`；切排序：模型 / 分组本地重排，用户重新请求。

### 4.5 状态

加载中整页 `ProgressView`；失败“加载失败 · 重试”；400 `INVALID_SORT_BY`（不应出现）按降级重请求一次（不带 `sort_by`）。

### 4.6 刷新策略

同 1.7（范围含现在时 60 秒）；下拉刷新重载。

### 4.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsRankView.swift`；依赖 1.8 的 `usageAnalysisModels(_:source:)`、`usageAnalysisUsersRanking(_:sortBy:limit:)`。

---

## 5. 模型页（`analyticsModel`）

### 5.1 入口与导航

- 进入：排行卡与全部排行的模型行。
- 导航栏：标题 = 模型名（映射口径写“a → b”）；副标题“模型 · <范围名>”。后端 `ModelStat` 没有平台字段 → 不显示设计稿里的平台名。页面没有筛选按钮，但会话里的分组筛选在本页生效。
- 页面：范围条 → 头部大数 → 壹 趋势 → 贰 用量 → 叁 速度 → 肆 用得最多的用户。
- 去向：用户行 → 用户详情；“这个模型的使用记录” → `logs(scope: usage, model, modelSource: source, group: 会话分组筛选)`。

### 5.2 数据来源

所有请求带 `model=<名称>&model_source=<source>` + 范围 + 会话分组筛选（有的话）。

| 区块 | 请求 | 补充 |
|---|---|---|
| 合计 | `GET /admin/usage/stats` | 占比分母 = 同范围、同分组筛选但不带 model 的 usage/stats（复用统计分析已加载的合计） |
| 对比 | `GET /admin/usage/stats`（对比窗口） | — |
| 趋势 | `GET /admin/dashboard/trend` | — |
| 速度 | `GET /admin/ops/dashboard/openai-token-stats?top_n=10` + 范围（规则同 2.2） | 需要 `ops.dashboard_model_filter`：requested / upstream 口径直接传；mapping 口径传 `model=<b>&model_source=upstream`。没有该能力：不传 model，在返回行里找 `model` 等于名称的那一行，找不到显示 `—`。运维关闭不显示本区块 |
| 用户 | `GET /admin/dashboard/users-ranking?limit=3&sort_by=actual_cost` | vendor 不显示本区块 |

速度区返回多行时（映射后的不同上游名）合并：输出/秒、平均时长按 `request_count` 加权平均，首 Token 按 `requests_with_first_token` 加权平均。

### 5.3 字段 → 显示

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 头部标签 | 本模型 `total_actual_cost` ÷ 分母 `total_actual_cost` | “实际扣费 · 占全部 12.3%”（分组筛选时“占高级组 …”） | 分母为 0：`—` |
| 头部大数 / 增减 | `total_actual_cost`；对比 | 同 1.4 | — |
| 上游模型行 | mapping 口径的 b | “上游模型 claude-opus-4-20250514”（等宽） | 非映射口径不显示 |
| 壹 趋势 | trend 每桶 `actual_cost` + `cost` 点线 | 分区 meta“实际 / 标准（点线）”；图高 100pt；下面三格 账号成本 / 标准 / 利润（本模型 usage/stats） | “这个范围内没有用量” |
| 贰 用量 | `total_requests`；`total_tokens`；缓存读占比 = `total_cache_read_tokens ÷ total_tokens`；平均每次 = `total_actual_cost ÷ total_requests` | 分区 meta 为范围名；占比 0 位小数；平均每次 3 位小数金额 | 请求为 0：`—` |
| 叁 速度 | `avg_tokens_per_sec`、`avg_first_token_ms`、`avg_duration_ms`（加权后） | 分区 meta“<窗口>”；“输出 Tokens/秒”“平均首 Token”“平均时长”；底注同 2.3 Token 请求统计的窗口说明 | null `—` |
| 肆 用户行 ×3 | `ranking[]` | 同 4.3 行样式（值为实际扣费） | “这个范围内没有用户用量” |
| 使用记录行 | — | 标题“这个模型的使用记录”，副行“近 24 小时 · 带上模型筛选，可以去掉”（有分组筛选写“带上模型和分组筛选”） | — |

### 5.4 交互与写操作

无写操作。改范围写回会话（同时写入本机记忆，0.1）。

### 5.5 状态

各区块独立加载、独立失败（同 1.6）；速度区运维关闭时整区隐藏（不占位）。

### 5.6 刷新策略

同 1.7；下拉刷新重载本页全部请求。

### 5.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsModelView.swift`；复用 1.8 的 Query 与 2.7 的 `opsTokenStats`。

---

## 6. 使用记录（`logs`）

### 6.1 入口与导航

- 进入：
  - 搜索目录“记录 · 使用记录” → `logs(scope: usage)`；“错误请求” → `logs(scope: errors)`。
  - 账号详情“记录”：上游错误 → `logs(scope: upstream, account)`，使用记录 → `logs(scope: usage, account)`。
  - 分组详情：错误请求 / 上游错误 / 使用记录 → 对应 scope + `group`。
  - 用户详情 → `logs(scope: usage, user)`。
  - 模型页 → `logs(scope: usage, model, modelSource, group?)`。
  - 告警详情（错误率类告警）→ `logs(scope: errors, group)`。
- 导航栏：标题“使用记录”；副标题“<站点名> · 近 24 小时”（随时间菜单变）；右侧筛选按钮（打开“按对象筛选” sheet）。
- 页面：分段 → 筛选胶囊行 → （不支持的条件说明）→ 列表。
- 去向：点行 → `request` 详情（带整行数据与 scope）。
- 离开页面清空本页的筛选改动；下次按 route 重新带入。

### 6.2 数据来源

时间：滚动预设的窗口在每次全量加载时取 `end_time = 现在`、`start_time = 现在 − 窗口`；自定义为固定起止。

| 用途 | 请求 | 参数 |
|---|---|---|
| 用量明细列表 | `GET /admin/usage` | `page`、`page_size=100`（与 00 §4.3 首屏一致，翻页同一页长）、`count_mode=deferred`、`sort_by=created_at`、`sort_order=desc`、`start_time`、`end_time`、`timezone`、`key_view=masked`、`account_id`、`group_id`、`user_id`、`model`、`model_source`（有 model 时） |
| 错误请求列表 | `GET /admin/ops/request-errors` | `page`、`page_size=100`、`view=all`（默认视图只排除业务限制，即用户自己的余额、额度、频率限制；传 all 才包含它们。上游 429 / 529 在默认视图里本来就有）、`start_time`、`end_time`、`account_id`、`group_id`、`user_id`、`model` |
| 上游错误列表 | `GET /admin/ops/upstream-errors` | 同上，`view=all` |
| 计数 · 用量明细 | `GET /admin/usage/stats` | 同一时间窗与筛选 → `total_requests` |
| 计数 · 错误请求 / 上游错误 | 当前段：列表响应的 `total`；其他段：同参数 `page=1&page_size=1` 取 `total` | — |
| 增量（用量明细、错误请求） | 同列表接口 | `since_id=<游标>`、`page_size=100` + 筛选；不传 `page`、时间、排序（算法见 00 §4.3，本页参数见 6.6） |
| 筛选 sheet · 账号 | `GET /admin/accounts?search=<q>&lite=true&sort_by=name&sort_order=asc&page=1&page_size=6` | 用账号章节（20 章）的 `managedAccounts(page:query:)` + `AccountListQuery`，见 6.7 |
| 筛选 sheet · 分组 | 分组目录缓存（`GET /admin/groups/all?include_inactive=true`），本地按名称过滤取前 4 | — |
| 筛选 sheet · 用户 | `GET /admin/usage/search-users?q=<q>` → `[{id, email, deleted}]`，取前 3 | vendor 不可用 |

响应：

- `admin/usage`：`items[]`（AdminUsageLog）、`total=null`、`page`、`page_size`、`has_more`、`total_exact=false`；since_id 时另有 `since_id`、`latest_id`，`has_more=true` 表示新行超过一页。行字段：`id`、`request_id`（形如 `client:<uuid>`）、`created_at`、`model`（请求模型）、`upstream_model`、`user{id,email,username}`、`api_key{id,name,key_masked}`、`group{id,name}`、`account{id,name}`、`input_tokens`、`output_tokens`、`cache_creation_tokens`、`cache_read_tokens`、`total_cost`、`actual_cost`、`account_cost`（D05，`provider_cost_recorded=false` 时为 0）、`provider_cost_recorded`、`request_type`（字符串）、`stream`、`duration_ms`、`first_token_ms`、`inbound_endpoint`、`upstream_request_id`。不读 `api_key.key`（明文）。
- `ops/request-errors`：`items[]`（OpsErrorLog）、`total`、`page`、`page_size`、`pages`、`has_more`、`total_exact=true`；since_id 时同上。`ops/upstream-errors`：`items`、`total`、`page`、`page_size`、`pages`（没有 `has_more`，按 `page < pages` 判断）。行字段：`id`、`created_at`、`phase`、`type`、`error_owner`、`error_source`、`severity`、`status_code`、`platform`、`model`、`requested_model`、`upstream_model`、`resolved`、`resolved_at`、`resolved_by_user_name`、`client_request_id`、`request_id`、`message`、`user_id`、`user_email`、`api_key_id`、`api_key_name`、`account_id`、`account_name`、`group_id`、`group_name`、`stream`、`request_type`（数字）、`duration_ms`、`time_to_first_token_ms`（D04，旧行 null）。列表项没有 `upstream_status_code`（只有详情有）。
- 错误请求与上游错误的 `model` 筛选匹配 `COALESCE(requested_model, model)`，即请求模型；没有 `model_source`。
- 上游错误 = phase 为 upstream / account_auth、责任方 provider 的行，包括已重试成功的恢复行（`status_code` < 400，`message` 为 `Recovered upstream error <上游码>` 或 `Recovered account authentication failure`）。所以同一个请求可能同时出现在错误请求与上游错误里，重试成功的请求也会同时出现在用量明细里。

### 6.3 字段 → 显示

**分段**：用量明细 N · 错误请求 N · 上游错误 N（`Picker(.segmented)`，数字为计数；拿不到写 `—`）。vendor 只有“用量明细”（隐藏分段控件）。

**筛选胶囊行**（横向滚动）：

| 元素 | 内容 | 动作 |
|---|---|---|
| 时间胶囊 | “近 24 小时 ⌄” | `Menu`：近 1 小时 / 近 24 小时 / 近 7 天 / 近 30 天 / 自定义…（开始、结束两个 DatePicker，最长 366 天） |
| 条件胶囊 | “账号：Claude-官方-01 ✕”“分组：标准组 ✕”“用户：xm.wang@example.com ✕”“模型：claude-opus-4 ✕”（模型等宽） | 点按移除该条件并重新加载 |
| 不生效的胶囊 | 置灰 | 见 6.4 |
| “+ 筛选” | — | 打开“按对象筛选” sheet |

**列表**：按日期（TZ）分节，节头“今天 / 昨天 / 10月14日”，节头右侧“金额 · 首字/耗时”。行布局：左列时间在上、状态码在下；中间模型在上、“用户 · 账号”在下；右列金额在上、“首字/耗时”在下；最右 chevron。

| 位置 | 用量明细 | 错误请求 | 上游错误 |
|---|---|---|---|
| 左上 时间 | `created_at` → `HH:mm`（TZ） | 同左 | 同左 |
| 左下 状态码徽章 | 固定 `200`（使用记录不带状态码） | `status_code` | `status_code` ≥ 400：`status_code`；< 400（已重试成功）：从 `message` 解析 `Recovered upstream error (\d{3})`，解析不到时 account_auth 写“鉴权”、其余写“恢复” |
| 徽章颜色 | ok | codeTone(徽章码) | codeTone(徽章码)（重试成功的 429 仍是琥珀） |
| 中上 模型 | `model`（等宽，单行截断） | `requested_model` 非空用它，否则 `model` | 同左 |
| 中下 用户 · 账号 | `user.email` · `account.name` | `user_email` · `account_name` | 同左 |
| 右上 金额 | `actual_cost`（< $1 显示 4 位） | `—` | `—` |
| 右下 首字/耗时 | `first_token_ms` / `duration_ms` → `1.2s/3.2s`；首字 null（非流式）→ `—/3.2s` | `time_to_first_token_ms` / `duration_ms`；null → `—` | 同左 |
| 状态胶囊 | 无 | codeTone(`status_code`)：429 caution，其余 critical | `status_code` < 400：无（客户端已拿到成功）；≥ 400 同左 |

- 状态胶囊用全局组件：同一列表里紧挨着的带色行连成一根连续状态轨（同色异色都连，交界处直接切色，只有整段最上端和最下端是圆头）；无色的行打断。
- 用户、账号缺失写 `—`；邮箱过长中间省略；vendor 下邮箱是后端打码后的原样。

### 6.4 交互与写操作

- 分段切换：保留全部条件，加载该段第 1 页；计数不重取。
- 不生效的条件：置灰胶囊不参与请求，胶囊下一行写原因：
  - `modelSource` 不是 requested 时，错误请求 / 上游错误的模型胶囊置灰：“错误记录只能按请求模型筛选，这里显示全部模型”。
  - 旧服务端（`/admin/me` 404，没有 D03）时，上游错误的用户、模型胶囊置灰：“上游错误不能按模型、用户筛选，这里显示全部”。
- “按对象筛选” sheet：顶部搜索框（占位“账号名、邮箱或分组”），输入防抖 300ms；分三组：账号（行：状态图标、名称、`#id`、平台 · 分组）、分组（行：名称、平台）、用户（行：头像首字、邮箱；`deleted=true` 加“已删除”）。搜索框为空时账号、分组显示前几个，用户组不显示（`search-users` 空关键字返回 `[]`）。选中即设置该类条件（同类替换）并关闭 sheet。vendor 没有用户组。
- 点行进入请求详情；返回时保留滚动位置。
- 下拉刷新：第 1 页全量重载 + 计数重取。
- 滚到底：加载下一页（`page + 1`，`page_size=100`），按 `id` 去重（新行插到顶部会让旧行往后挪，只会重复、不会漏）。
- 本页没有写操作（标记已处理在请求详情里；详情里改了 `resolved` 后，返回时就地更新本页那一行）。

### 6.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 列表位置 `ProgressView`“正在读取记录…” | — |
| 空（无条件） | 大号“—”+“近 24 小时内没有记录” | — |
| 空（有条件） | 大号“—”+“近 24 小时内，这些条件下没有记录”+“清除筛选”按钮 | 清除全部条件 |
| 加载失败 | 列表末尾“加载失败”+“重试”；已有记录保留并注明“保留上次成功加载的记录” | 重试 |
| 错误请求 / 上游错误段遇到运维监控关闭（`ops_monitoring_enabled=false` 或 404 `OPS_DISABLED`） | 段内容换成“运维监控未开启”组件，并说明“关闭期间不记录错误，开启后也不会补”；计数 `—` | 见监控章节组件 |
| 范围超过 30 天的错误类段 | 列表头下一行“运维错误日志默认只保留 30 天，更早的可能已清理” | — |
| 400 `INVALID_SINCE_ID` / `SINCE_ID_WITH_PAGE` | 不显示，放弃增量改为第 1 页重载（00 §4.3 第 6 步） | — |
| 400 其他（参数） | “请求参数无效” | 清除筛选 |
| 403（vendor 访问错误类接口） | 不应出现（已隐藏） | — |

### 6.6 刷新策略

- 前台、页面可见、时间为滚动预设时，每 60 秒自动刷新一次；后台或离开页面暂停，回到前台立即刷一次。固定的自定义时间段不自动刷新。
- **用量明细、错误请求的增量**：首屏、游标回退、按 `id` 合并、`has_more`、400 回退、没有 `logs.since_id` 时的退路，**全部按 00 §4.3**，实现只用 00 §9.7 的 `IncrementalList`，本章不另写一套。增量请求只带当前的对象筛选（账号 / 分组 / 用户 / 模型 / `model_source`）+ `since_id` + `page_size=100`，不带 `page`、`start_time` / `end_time`、排序。本页只规定这几个参数：
  - **N = 500**（00 §4.3 第 3 步“只保留最新的 N 条”）。超出时，只在列表停在顶部附近（第一个可见行在前 20 行内）才从尾部裁到 500 行，并把“加载更多”的下一页设为 6（500 ÷ 100 + 1）；用户正往下翻时先不裁，回到顶部再裁。
  - **时间窗裁剪**：每次合并后丢掉 `created_at` 早于窗口起点（现在 − 所选窗口）的行。
  - **校准周期**：每 10 次增量（约 10 分钟）拉一次第 1 页（参数同首屏），按 00 §4.3 第 3 步合并进现有列表（不清掉已加载的更早页），再按第 2 步重算游标。下拉刷新按 00 §4.3 第 5 步。
  - **显示顺序**跟 00 §4.3 第 3 步（`id` 降序）。按日期分节时，每行按自己的 `created_at`（TZ）归到对应日期的节，节按日期降序；`id` 顺序与时间偶有几秒交错，不会因此拆出两个同名的节。
- **上游错误（后端没有 since_id）**：每次自动刷新按 00 §4.3 第 7 步的退路取（`page=1&page_size=100`，`start_time` = 已加载最新一行的 `created_at` − 120 秒，`end_time` = 现在；ops 接口不带 `count_mode`），按 `id` 合并；响应 `pages` > 1（两次刷新之间的新行超过一页）时改为第 1 页全量重载。N、时间窗裁剪同上。
- 计数只在进入、切换条件、下拉刷新时取，自动刷新不重取。

### 6.7 对现有代码的改动点

本章是 `admin/usage`（列表、按请求 ID 查）、`ops/request-errors`、`ops/upstream-errors`（列表、计数、详情、标记已处理）、`ops/requests/:id/attempts`、`usage/search-users` 在 App 里的**唯一定义处**；10 / 20 / 50 章的“近 24 小时 N 条”计数、60 章的请求 ID 搜索都调这里的方法，不另建。

- `Sources/Sub2Core/RequestLogs.swift`
  - `RequestLogFilter`：
    - 时间条件：`start` / `end` 改为 `time: LogTimeWindow`——`.range(start, end)`（本页；最长 366 天）、`.rolling(String)`（只用于 ops 接口，取后端认的 `5m` / `30m` / `1h` / `6h` / `24h` / `7d` / `30d`；其他章的“近 24 小时”计数、60 章搜索的 `30d` 用它）、`.none`（只允许和 `requestID` 一起用于 `admin/usage`：不带时间 = 全部时间）。ops 接口不带时间时后端默认只查近 1 小时，所以 `queryItems(errors: true)` 遇到 `.none` 抛 `.validation`；`admin/usage` 不认 `time_range`，`queryItems(errors: false)` 遇到 `.rolling` 也抛 `.validation`。
    - 新增 `modelSource`、`pageSize`（默认 100；计数传 1，60 章搜索传 5，按请求 ID 查使用记录传 1）。`requestID` 已有，保留。
    - `queryItems(page:errors:errorKind:)`：`page_size` 取 `pageSize`（现在写死 30）；用量明细加 `key_view=masked`；`timezone` 由设备时区改为站点时区；删掉对上游错误“不支持用户、密钥、模型和请求 ID 筛选”的抛错（D03 已支持），是否置灰由调用方按 0.3 决定；`upstreamErrorFilter()` 只在旧服务端使用。新增 `incrementalQueryItems(sinceID:)`（只带筛选、`since_id`、`page_size=100`）。
    - `category`、`statusCode`、`resolved`、`requestType`、`apiKeyID` 不再出现在界面（已定设计没有这些条件），属性可留作内部用。
  - `RequestLogPage` 删除，改用 00 §9.4 扩展后的 `Page<T>`（可空 `total` / `pages`、`hasMore`、`sinceID`、`latestID`）；`RequestLogPage.init(from:)` 里“没有 `has_more` 时按 `page < pages`、再按 `total` 推算”的逻辑搬进 `Page<T>`（上游错误的响应没有 `has_more`）。`Page` 现在要求 `T: Codable`，而两个记录类型只是 `Decodable`：把 `Page` 的约束放宽为 `Decodable & Sendable`（`Page` 自身的 `Encodable` 只在 `T: Encodable` 时提供）。
  - `UsageRequestRecord`：`accountCost` 优先读 `account_cost`；没有该键时才按公式 `provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0`（现代码漏了 `provider_cost_recorded`，跟随请求会多算）；新增 `providerCostRecorded`、`userName`（`user.username`）、`apiKeyName`、`apiKeyMasked`（`api_key.name` / `key_masked`，永不解码 `key`）。
  - `RequestErrorRecord`：新增 `durationMs`、`errorOwner`、`errorSource`、`severity`、`clientRequestID`、`userEmail`、`apiKeyID`、`apiKeyName`、`stream`、`requestType`（Int16?）、`resolvedAt`、`resolvedByUserName`；`model` 取法不变（requested_model 优先）。
  - 增量合并与游标：用 00 §9.7 的 `Sources/Sub2Core/IncrementalList.swift`，本章不新建合并文件；6.6 的 N = 500、时间窗裁剪、10 次一校准放在 `LogsView` 的 store 里，作为调用 `IncrementalList` 的参数或调用后的裁剪。
  - `APIClient` 方法：列表沿用 `requestRecords(page:filter:)`、`errorRecords(page:filter:kind:)`（返回类型改为 `Page<…>`）；新增 `errorCount(filter:kind:)`（`pageSize = 1` 取 `total`）、`searchUsageUsers(_:)`。
- 账号筛选（筛选 sheet）：调 20 章的 `managedAccounts(page: 1, query:)`，`AccountListQuery` 设 `search = q`、`sort = .name`、升序、`pageSize = 6`（`pageSize` 由 20 章加，lite 是该查询的固定行为）；不用 `APIClient.accounts(page:search:status:platform:)`。
- `NativeApp/Features/RequestLogsView.swift`：拆成 `NativeApp/Features/Logs/LogsView.swift`（分段与计数、胶囊、列表、轮询）、`LogRow.swift`、`LogFilterPickerSheet.swift`；`LogMode` 文案改为 用量明细 / 错误请求 / 上游错误；导航标题“请求与错误日志”改“使用记录”；删除 `RequestLogFilterEditor` 的数字 ID 输入、分类 / 状态码 / 处理状态 / 请求类型选择器，时间范围改为胶囊菜单；`requestRow` / `errorRow` 换成 `LogRow`；`LogFixtures` 按新字段更新；`init(accountID:groupID:)` 改为 `init(route: LogsRoute)`。
- 调用方：`NativeApp/Sub2MobileApp.swift:51-53` 搜索目录条目改为“使用记录”“错误请求”“统计分析”；`NativeApp/Features/AccountsView.swift:484-486`、`NativeApp/Features/GroupsView.swift:195-196` 改传 `LogsRoute`（是否保留“账号统计分析”入口由账号章节定，统计页不再支持按账号筛选）。
- 测试：`Tests/Sub2CoreTests/RequestLogsTests.swift` 补 `account_cost` 与 `provider_cost_recorded`、D04 字段、since_id 信封（`Page<T>` 的 `sinceID` / `latestID`、上游错误无 `has_more` 时按 `pages` 推算）、`LogTimeWindow`（ops 拒绝 `.none`、usage 拒绝 `.rolling`、`.rolling` 只出 `time_range`）；游标与合并的测试在 00 §9.8 的 `IncrementalList` 里，本章不重复；`UITests/RequestLogsUITests.swift` 按新布局与标识重写，并覆盖自动刷新后新行出现在顶部、超过 N 行且停在顶部时裁尾（UI 测试启动参数把 N 调成 5）。
- 文档：`docs/ADMIN_MODULES.md` 里“独立日志筛选边界”按 D03 更新。

---

## 7. 请求详情（`request`）

### 7.1 入口与导航

- 进入：使用记录的行（带整行与 scope）；账号详情状态卡“最近上游错误 ›”（`.error(id, kind: upstream)`）；搜索里输入请求 ID 命中的使用记录（`.usageRequestID`）或错误请求（`.error(id, kind: request)`）。
- 三种样子：
  - **成功**：来自用量明细。
  - **上游失败已恢复**：来自上游错误、`status_code` < 400。
  - **失败**：来自错误请求或上游错误、`status_code` ≥ 400。
- 导航栏：标题 请求详情 / 上游错误 / 失败请求；副标题“10/16 09:41:07 · 用量明细 / 错误请求 / 上游错误”；右侧 ··· 菜单：复制请求 ID、复制上游请求 ID（有时）。
- 分区按出现顺序编号（壹、贰、叁…）：头部状态卡 → （失败类）按钮行 → 耗时 → 上游尝试（有时）→ Token（成功）→ 关联 → 标识。
- 去向：用户 → 用户详情；分组 → 分组详情；账号 / “查看账号” → 账号详情。

### 7.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 成功 · 行数据 | 进入时已带；只有请求 ID 时 `GET /admin/usage?request_id=<rid>&page=1&page_size=1&key_view=masked`（`requestRecords(page: 1, filter:)`，filter 为 `requestID = rid`、`time = .none`、`pageSize = 1`） | 精确匹配、不需要时间范围；为空时“记录不存在或已清理” |
| 失败类 · 详情 | `GET /admin/ops/request-errors/:id`（错误请求）或 `GET /admin/ops/upstream-errors/:id`（上游错误），同一张表 | 列表字段 + `upstream_status_code`、`upstream_error_message`、`upstream_errors`（JSON 数组字符串）、`auth_latency_ms`、`routing_latency_ms`、`upstream_latency_ms`、`response_latency_ms`、`is_business_limited`、`api_key_prefix`。不解码、不显示 `error_body`、`upstream_error_detail` 和事件里的 `upstream_response_body` |
| 上游尝试 | `GET /admin/ops/requests/<id>/attempts?around=<created_at，UTC Z>` | 有 `ops.request_attempts` 且运维开启。`<id>`：失败类用 `client_request_id`（服务端 UUID，唯一），为空时用 `request_id`；成功用使用记录的 `request_id`（`client:<uuid>` 形式，后端认）。`around` 把两张表收窄到前后 1 小时 |
| 标记已处理 | `PUT /admin/ops/request-errors/:id/resolve` 或 `/admin/ops/upstream-errors/:id/resolve`，body `{"resolved": true \| false}` | 响应 `{"ok": true}` |

attempts 响应：`request_id`、`client_request_id`、`client_status_code`、`attempts[]{index, source（upstream_error / usage）, outcome（failed / success / partial）, platform, account_id, account_name, proxy_id, proxy_name, upstream_status_code, upstream_request_id, kind, stage, message, started_at, ended_at, duration_ms, first_token_ms, error_log_id, usage_id}`、`error_log_ids`、`dropped_earlier_attempts`。成功那次 `upstream_status_code` 固定 200，`started_at` 由 `created_at − duration_ms` 估算；部署前产生的事件没有 `started_at` / `duration_ms`（null）。

attempts 出错与退路：

- 404 `OPS_REQUEST_NOT_FOUND`、400 `INVALID_REQUEST_ID`：成功样子隐藏“上游尝试”；失败类改用退路。
- 409 `OPS_REQUEST_AMBIGUOUS`（只在用 `request_id` 查时可能出现）：从 `metadata.client_request_ids` 与 `metadata.client_request_id_times` 里选时间离 `created_at` 最近的那个 id 重查一次，不原样重试。
- 请求 ID 含 `/`（路由匹配不到，后端返回纯文本 404、没有 reason）：失败类改用 `client_request_id`；成功样子隐藏该区。
- 退路（没有能力或上面失败）：解析详情的 `upstream_errors` 得到失败的尝试（`account_name`、`upstream_status_code`、`at_unix_ms`、`started_at_unix_ms`、`duration_ms`）；`duration_ms` 缺失时用相邻两次 `at_unix_ms` 之差估算（第一次写 `—`），显示加“约”；客户端最终成功时，再用同一个 `requestRecords(page: 1, filter:)`（`requestID = "client:<client_request_id>"`、`time = .none`、`pageSize = 1`）取成功那次（耗时 = 其 `duration_ms`）。

### 7.3 字段 → 显示

**头部状态卡**（左侧状态胶囊；成功与已恢复无胶囊）

| 界面元素 | 成功 | 上游失败已恢复 | 失败 | 空值 |
|---|---|---|---|---|
| 状态行 | “✓ 成功 200”（ok） | “上游失败 [429]”：码 = 详情 `upstream_status_code`，没有时用列表解析值，徽章按该码着色 | “⛔ 失败 504”：码 = attempts `client_status_code` ?? `status_code` | — |
| 原因 | — | `phase` · `error_owner` · `severity`（显示名见 0.4） | 同左 | 缺项省略 |
| 模型 | `model`（等宽） | `requested_model` ?? `model` | 同左 | — |
| 上游模型 | `upstream_model` 与 `model` 不同时“上游模型 xxx” | `upstream_model`（同左规则） | 同左 | 不显示 |
| 金额三格 | 实际扣费 `actual_cost` / 账号成本 `account_cost` / 标准 `total_cost`，4 位小数 | — | — | `provider_cost_recorded=false`：账号成本 `$0.0000`，下方小字“合并探测的跟随请求，没有上游成本” |
| 恢复说明 | — | “✓ 已自动重试成功，客户端收到 200”（`status_code`） | — | — |
| 错误信息 | — | `upstream_error_message` ?? `message`，经 `RequestLogPresentation.safeMessage` 脱敏，等宽，最多 6 行，点按展开 | 同左 | “上游返回错误” |
| 胶囊颜色 | 无 | 无 | codeTone(最终码) | — |

**按钮行**（只在失败类）：“标记已处理”（主按钮；已处理时变为“已处理 ✓”，点按撤回）、“查看账号”（`account_id` > 0 时）。已处理且详情有 `resolved_at` 时，按钮下小字“已处理 · <resolved_by_user_name> · 10/16 09:52”。

**耗时**

| 界面元素 | 成功 | 失败类 | 空值 |
|---|---|---|---|
| 条 | 首字占总耗时的比例（最少 4%）+ 其余 | 同左 | 首字缺失只画总条 |
| 首字 | `first_token_ms` | `time_to_first_token_ms` | `—` |
| 总耗时 | `duration_ms` | `duration_ms`；为 null 时用 auth + routing + upstream + response 四段之和，写“约 3.2s” | `—` |
| 方式 | `request_type`：stream 流式、sync 非流式、ws_v2 WebSocket、live Live、cyber 安全策略 | `stream` → 流式 / 非流式（`request_type` 数字 1–5 时按同一表） | `—` |

**上游尝试**（失败类有 ≥ 1 次尝试时显示；成功样子在 attempts ≥ 2 次时显示）

| 界面元素 | 字段 / 计算 | 格式与文案 |
|---|---|---|
| 分区 meta | 尝试数、`client_status_code` | “2 次 · 返回客户端 200” |
| 行 · 序号 | `index` | 圆形序号，按 `upstream_status_code` 着色（2xx ok、429 caution、其余 bad、null 中性） |
| 行 · 标题 | `account_name` ?? `#account_id` | 没有账号写“未知账号” |
| 行 · 右侧 | `upstream_status_code` · `duration_ms` | `429 · 0.4s`；缺失写 `—`；退路估算加“约” |
| 行 · 副行 | `outcome` 与下一次尝试 | success“成功，结果返回客户端”；partial“已计费，但请求最终失败”；failed 且是最后一次“失败，错误返回客户端”；failed 且下一次同账号“失败，同一账号重试”；否则“失败，切换到 <下一次的账号> 重试” |
| 行 · 点按 | `account_id` | 进该账号详情 |
| 分区底注 | `dropped_earlier_attempts` > 0 | “更早的 N 次尝试因队列上限没有记录” |

**Token**（成功）：输入 `input_tokens`、输出 `output_tokens`、缓存读 `cache_read_tokens`、缓存写 `cache_creation_tokens`，千分位。

**关联**

| 行 | 成功 | 失败类 | 点按 |
|---|---|---|---|
| 用户 | `user.username` ?? `user.email` | `user_email` | 用户详情（`user_id`；vendor 不可点） |
| Key | `api_key.name` + 右侧 `api_key.key_masked`（等宽） | `api_key_name` + 右侧 `api_key_prefix…` | 不可点 |
| 分组 | `group.name` | `group_name` | 分组详情 |
| 账号 | `account.name` | `account_name` | 账号详情 |

缺失写 `—` 且不可点。

**标识**

| 行 | 字段 | 动作 |
|---|---|---|
| 请求 ID | 成功：`request_id`；失败类：`request_id` | 点按复制，toast“已复制请求 ID” |
| 服务端请求 ID | 失败类：`client_request_id` | 复制 |
| 上游请求 ID | 成功：`upstream_request_id`；失败类：attempts 最后一次的 `upstream_request_id` | 复制；没有时不显示 |

### 7.4 交互与写操作

- 标记已处理：`PUT .../resolve {"resolved": true}`。不需要 step-up，不带 Idempotency-Key（写的是绝对值，重复提交安全）。
  - 乐观更新：按钮立即变“已处理 ✓”，toast“已标记为已处理”带“撤销”（撤销 = 发 `{"resolved": false}`）。
  - 失败回滚按钮，toast“标记失败，请重试”；404 `OPS_ERROR_NOT_FOUND`：“记录已不存在”，按钮置灰；404 `OPS_DISABLED`：“运维监控未开启，无法标记”。
  - 成功后就地更新使用记录列表里那一行的 `resolved`，不整页重载。
- 复制：`UIPasteboard`，只复制 ID。
- 查看账号 / 关联行导航见 7.1。

### 7.5 状态

| 情况 | 显示 |
|---|---|
| 进入（带行数据） | 头部、耗时、关联、标识立即用行数据画；详情与尝试到达后补齐，区块内各自 `ProgressView` |
| 只带请求 ID，查询为空 | 整页“记录不存在或已清理” |
| 详情 404 `OPS_ERROR_NOT_FOUND` | 整页“记录不存在或已清理” |
| 详情 404 `OPS_DISABLED` | 保留行数据，详情区写“运维监控未开启，看不到更多信息” |
| 详情加载失败 | 保留行数据，底部“详情加载失败 · 重试” |
| 尝试加载中 / 失败 | 分区内 `ProgressView` / 改用退路；退路也失败时分区写“没能取到重试链” |

### 7.6 刷新策略

进入时加载详情与尝试；下拉刷新重新加载二者；不自动轮询。

### 7.7 对现有代码的改动点

- `Sources/Sub2Core/RequestLogs.swift`：新增 `RequestErrorDetail`（列表字段 + 7.2 列出的详情字段；`upstreamEvents: [UpstreamErrorEvent]` 由 `upstream_errors` 字符串解析，解析失败为空数组）；新增 `RequestAttempts` / `RequestAttempt` 解码；`APIClient` 新增 `errorDetail(id:kind:)`（替换返回 `RequestErrorRecord` 的 `errorRecord(id:kind:)`）、`requestAttempts(id:around:)`（路径段百分号编码；对 409 解析 `metadata`）、`setErrorResolved(id:kind:resolved:)`。按请求 ID 查使用记录不另建方法，用 6.7 的 `requestRecords(page:filter:)`（`time = .none`）。
- `NativeApp/Features/RequestLogsView.swift` 的私有 `UsageRequestDetailView`、`RequestErrorDetailView` 删除，换成新文件 `NativeApp/Features/Logs/RequestDetailView.swift`（三种样子共用分区组件）；去掉现有“错误 / 请求上下文 / 延迟”的 LabeledValue 平铺，文案“上游成本”“差额”删除；`LogAccountDestination` 保留或改用账号章节的详情路由。
- 状态卡左侧胶囊、按钮行、toast 带撤销用全局组件。
- 测试：`RequestLogsTests` 补 `upstream_errors` 解析、attempts 解码（含 null 计时的旧事件）、副行文案规则；UI 测试覆盖成功 / 已恢复 / 失败三种样子与标记已处理的撤销。

---

## 8. 本章未决问题

| # | 问题 | 建议默认值 |
|---|---|---|
| 1 | 上游错误列表项不带 `upstream_status_code`（只在详情里有），已重试成功的行 `status_code` 是客户端拿到的 200，行左下的上游码只能从 `message`（`Recovered upstream error 429`）解析，这是后端固定拼接的文字，不是契约 | 先按 6.3 解析，解析不到写“恢复 / 鉴权”；请维护者在 OpsErrorLog 列表项加 `upstream_status_code`（列已存在，只增字段） |
| 2 | 使用记录不下发状态码，也不下发 `billing_provenance`（失败但计费的行区分不出来） | 用量明细行一律显示 200；如需区分，请后端在 AdminUsageLog 只增 `billing_provenance` |
| 3 | error-trend 的上游 429 / 529 / 其他计数包含已重试成功的行，不能和 `error_count_total` 叠成设计稿的五层 | 按 2.3 退路：只叠 SLA 错误 + 业务限制，上游分项单列文字；若要五层，请后端给 error-trend 增加只计 status ≥ 400 的上游分项 |
| 4 | 统计分析与日志的时间按站点时区还是本机时区（设计稿 sheet 写“按本机时区计算”） | 站点时区（为与首页“今日”和利润一致），设备时区不同时在说明行标注 |
| 5 | 运维错误日志默认只保留 30 天（可配置，App 读不到实际值），超过 30 天的范围里错误类图表前段会是 0 | 范围起点早于 30 天前时加 2.5 的提示文案，不截断范围 |
| 6 | 后端没有站点开通日期、模型所属平台 | 自定义范围最早到 366 天前且不写开通日期；模型页副标题不写平台 |

---

## 审查记录

2026-10-22 按审查意见修订，逐条核对出处后处理：

| # | 意见 | 核实 | 处理 |
|---|---|---|---|
| 1 | 增量游标回退算法与 00 §4.3 不一致，两章各建一个实现文件 | 属实 | 6.6 不再写游标、合并、`has_more`、退路的具体规则，改为引用 00 §4.3；实现文件只用 00 §9.7 的 `IncrementalList.swift`，删除本章的 `IncrementalLogMerger.swift`。意见里“把 40 章原有的回退规则（最小 id − 1；空列表用上次 `since_id`）并入 00 §4.3”要改 00，不在本文件范围内；本章既然只引用，00 改成什么，本页就照什么做 |
| 2 | `view=all` 的理由写错 | 属实（`repository/ops_repo.go` 视图过滤：`""` / `errors` 只加 `is_business_limited = false`，注释写明上游 429 / 529 包含在 errors 视图；`parseOpsViewParam` 默认 `errors`） | 6.2 改为“默认视图只排除业务限制……上游 429 / 529 在默认视图里本来就有” |
| 3 | 范围 / 筛选记忆与设计稿不同 | 属实（`v-analytics.jsx` 头注释；`useAxMemo` 按手机存活期存储；`useAxRange` 只在没有记忆时用入口默认值） | 按设计稿改：0.1 改为按站点在本机记住，入口默认值只在第一次用，并写明记忆失效规则；1.1、1.8、3.4、4.4、5.4 同步。分组详情的统计入口已被 50 章删除，route 去掉 `groupID` |
| 4 | since_id 的游标与合并规则两章各写一遍、细节冲突 | 属实 | 同第 1 条；另外列表首屏与翻页的 `page_size` 从 50 改为 100（与 00 §4.3 第 1 步一致），显示顺序改跟 00 的 `id` 降序；本页只规定 N = 500、时间窗裁剪、每 10 次增量校准一次，以及没有 `since_id` 的上游错误怎么刷新 |
| 5 | 同一接口各章定义了不同的方法与模型 | 属实（本章涉及的是 ops overview 与账号列表；status-summary、`requestWithHeaders`、step-up sheet 本章不用） | ops overview 改为调用 10 章的 `opsOverview` / `OpsOverview`，删除本章的 `OpsOverviewWindow` 与“`dashboardMonitoring()` 保持不动”；筛选 sheet 的账号搜索改用 20 章的 `managedAccounts(page:query:)` + `AccountListQuery`。顺带按同一原则收拢本章负责的接口：6.7 写明本章是日志类接口的唯一定义处；按请求 ID 查使用记录并入 `requestRecords`（`RequestLogFilter` 加 `LogTimeWindow`、`pageSize`，供 60 章搜索和其他章的计数共用），去掉单独的 `usageRecord(requestID:)`；`RequestLogPage` 并入 00 §9.4 的 `Page<T>`；`dashboardPerformanceTrend` 改收 `OpsQuery`；“运维监控未开启”统一用 10 章 `OpsDisabledNotice` |
