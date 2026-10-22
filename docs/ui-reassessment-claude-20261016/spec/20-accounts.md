# 20 · 账号 Tab（最终实现规格）

> 读者：照着实现 SwiftUI（最低 iOS 26）原生管理端的工程师。本章只写“做什么、调什么、显示什么、出错怎么办”。
>
> 依据：`../DECISIONS.md`（第 3 轮以“更正”为准，文末评审意见与 TPM 口径最新）、设计稿 `../html-preview/layouts/main/`（已定变体见 `v-decided.jsx`：`accounts: 'platform'`、`acctOrder: 'group'`、`accountDetail: 'inline'`、`aeCred: 'row'`、`screen:accountNew: 'form'`、`anOauth: 'list'`）、`../BACKEND-API-CHANGES.md`（进度表备注优先于条目原文）、sub2 `docs/API_ERROR_CODES.md`、sub2 后端源码（2026-10-22 核实，main `70116315d`）。
>
> 路径一律相对站点根 `/api/v1`。“能力”指 `GET /admin/me` 返回的 `capabilities` 字符串（`handler/admin/me_handler.go` 的 `adminMeCapabilities`），没有该能力时走本章写的退路。

本章页面：

| # | 页面 / 流程 | 设计稿来源 |
|---|---|---|
| 1 | 账号列表（三行列表 · 按平台分组 · 平台内同分组在一起 · 再按紧急度） | `v-accounts.jsx` `VaByPlatform`，行 = `00-core.jsx` `AccountRow` |
| 2 | 账号详情（状态卡 + 按钮行、容量、今日、记录） | `00-core.jsx` `AccountDetailTop` |
| 3 | 详情内联编辑（基础 / 调度 / 凭据 / 代理 / 模型 / 高级）、⋯ 菜单、删除、在 Web 中编辑 | `v-account-edit.jsx` `AeInline` |
| 4 | 测试连接（SSE + test_result；异步 test-runs） | `shared/core.jsx` `TestSheet`、`v-account-new.jsx` `AnTest` |
| 5 | 恢复状态 / 启用调度 / 停止调度 / 启用账号 | `shared/core.jsx` `confirmRecover` |
| 6 | 凭据：更换 API Key、Base URL、刷新令牌、重新授权 | `v-account-edit.jsx` `AeKeySheet` `AeUrlSheet` `AeReauthSheet` |
| 7 | 新建账号（单页长表单 + 创建并测试 sheet） | `v-account-new.jsx` `AnForm` |
| 8 | 批量操作（选择 + 底部操作坞） | `v-accounts.jsx` `VaShell` dock |
| 9 | 定时测试（只读） | 已定详情页没有画，本章补一行（见 §9） |
| 10 | 共享数据源：账号状态汇总（D02）、账号排行（C04） | — |

---

## 0. 本章通用规则

### 0.1 本章用到的能力与退路

| 能力 | 本章用途 | 没有时 |
|---|---|---|
| `accounts.list_query` | 列表 `status` 多值 / 派生值、`sort_by=urgency`、`include_counts` | 全量 lite 分页拉取（`sort_by=name`），本地推导状态、分组、排序和计数 |
| `accounts.status_summary` | 平台组头计数、Tab 徽标 | 组头用已加载行本地计数；徽标用 `dashboard/stats.error_accounts` |
| `accounts.runtime_batch` | 列表 / 详情 60 秒轻刷新 | 重拉列表当前已加载页 / 重拉 `GET /admin/accounts/:id` |
| `accounts.today_stats_failures` | 区分“今日 0”与“查询失败” | `stats` 原样显示，不能区分 |
| `accounts.structured_error` | `error_kind` / `error_status_code` 判凭据类错误（0.2），`error_summary` 作原因短句，`error_at` 只作状态卡出错时间行的退路（§2.3） | 凭据类错误用正则粗判（0.2）；原因短句写“上游返回异常”；出错时间行只用上游错误日志 |
| `accounts.token_status` | 访问令牌剩余时间 | 兼容解析 `credentials.expires_at`（Unix 秒或 RFC3339），分母未知时不画刻度 |
| `accounts.patch` | 内联编辑全部走 `PATCH` + `If-Match` | `GET :id` 拿整份（已脱敏）`credentials` / `extra` 合并后整份 `PUT`，无并发保护（附录 A S30/S31） |
| `accounts.mixed_channel_details` | 409 直接带 `details` | 提交前先 `POST /admin/accounts/check-mixed-channel` 预检 |
| `accounts.recover_schedulable` | 恢复并启用调度一步完成 | `recover-state` 后再 `POST :id/schedulable {true}` |
| `accounts.clear_error_preserve_inactive` | 批量恢复不重新启用停用账号（只用于 §8.8 扩展，默认不做） | 本地先剔除 `status=inactive`，确认框写明 |
| `accounts.test_result` | 测试结束读服务端计时、上游状态码、测试后状态 | 本机计时并标“本机计时”；流结束后 `GET :id` 与测试前快照比对 |
| `accounts.test_runs` | 测试中断后读结果、后台测试 | 中断即“不能判定是否成功”，给“重新测试” |
| `accounts.reauthorize` / `accounts.oauth_error_reasons` | 一步重新授权、换码错误可识别 | `exchange-code` → `apply-oauth-credentials` 两步；超过 30 分钟或 500 时提示“授权链接可能已过期” |
| `scheduled_tests.upstream_status` | 定时测试结果的状态码、分类 | 正则从 `error_message` 解析 `\((\d{3})\)\|returned (\d{3})` |
| `meta.catalog` | 平台、认证方式、协议的运行时目录 | App 内置一份与 `frontend/src/constants/platformCatalog.builtin.json` 同步的清单；未知值显示原始 id |
| `admin.idempotent_writes` | `PUT :id`、`:id/schedulable`、`bulk-update`、`:id/refresh`、`batch-refresh` 带 `Idempotency-Key`，生成、重试、超时与待核对一律按 00 §2.3–§2.5 | 按“不带 key 的写”处理（00 §2.4）：不自动重发，读回核对（各节“结果不明”行给读回方法） |
| `web.accounts_edit_deep_link` | “在 Web 中编辑”直达编辑弹窗 | 打开 Web 账号列表并复制账号名 |
| `dashboard.accounts_ranking` | 账号排行（给概览用，见 §10） | 全量 ID 交 `today-stats/batch` 本地排序 |

C01（新建时 `schedulable=false`）没有能力标记：以响应的 `data.schedulable` 判断是否生效（§7.4）。

### 0.2 账号显示状态（App 侧唯一推导函数）

新增 `Sub2Core/AccountDisplayState.swift`，所有页面（列表行、详情状态卡、按钮行、批量结果、概览待处理）只用它。判定顺序与后端 `service.AccountScheduleState`（`service/account_status_summary.go:63-82`，即 D02 口径）一致：

| 顺序 | 条件（`now` = ServerTime，见 0.6） | 显示状态 | 色调 | 计时 |
|---|---|---|---|---|
| 1 | `status == "error"` | 错误 | critical | 否 |
| 2 | `status != "active"`（`inactive`、历史值 `disabled`、未知值） | 停用 | neutral | 否 |
| 3 | `overload_until > now` | 过载中 | critical | 到 `overload_until` |
| 4 | `rate_limit_reset_at > now` | 限流中 | caution | 到 `rate_limit_reset_at` |
| 5 | `temp_unschedulable_until > now` | 临时不可调度 | caution | 到 `temp_unschedulable_until` |
| 6 | `schedulable == false` | 暂停 | neutral | 否 |
| 7 | `auto_pause_on_expired && expires_at <= now`（`expires_at` 为 Unix 秒） | 暂停（副文案“已过期”） | neutral | 否 |
| 8 | 其余 | 正常 | ok | 否 |

- **已停止调度**标记：状态是 3–5（限时）且 `schedulable == false`。行和状态卡显示“已停止调度”，与 D02 的 `stopped` 同义。
- **需处理** = 错误 / 过载中 / 限流中 / 临时不可调度；**受限** = 过载中 / 限流中 / 临时不可调度。
- 计时状态的倒计时到 0 时：立即重新推导（可能落到下一个限时状态），并对该账号触发一次 `GET /admin/accounts/:id`（列表里触发一次轻刷新，见 §1.6）。
- 原因短句（行第三行、状态卡标题旁）：
  - 错误：`error_summary`（≤160 字，已脱敏）；为空时“上游返回异常”。**不显示 `error_message` 原文。**
  - 过载中：“上游 529”（后端 `handle529` 设置，`service/ratelimit_service.go:1968`）。
  - 限流中：“上游 429”。
  - 临时不可调度：解析 `temp_unschedulable_reason`（JSON 字符串 `TempUnschedState`，`service/temp_unsched.go:9-21`）：有 `status_code` 写“上游 {status_code}”；`matched_keyword` 非空且 `rule_index >= 0` 时追加“ · 规则 #{rule_index+1}”（与 Web `TempUnschedStatusModal.vue:188-189` 一致）；不是 JSON 时写“临时不可调度”。
- **模型限流**：`extra.model_rate_limits` 是 `{模型: {rate_limit_reset_at: RFC3339, …}}`，只取 `rate_limit_reset_at > now` 的项（与 `activeModelRateLimits` 同口径，`service/account_status_summary.go:413-429`），按模型名排序。
- **凭据类错误**（决定主按钮是“更换 API Key…”还是“重新授权…”）：状态为错误，且 `error_kind ∈ {auth, forbidden, token_refresh}`，或 `error_status_code ∈ {401, 403}`；没有 C02 字段时退回正则 `\b40[13]\b|invalid_api_key|token`（只用于判断，不显示原文）。`error_kind` 取值以后端为准：`auth / forbidden / quota / custom_code / stream_timeout / token_refresh / privacy / rate_limit / other`（`service/account_error_describe.go:14-22`）。
- **令牌账号** = `type ∈ {oauth, setup-token}`（后端 `Account.IsOAuth`）；其余是密钥账号。

### 0.3 显示名

| 值 | 显示 |
|---|---|
| 平台 id | `meta/catalog` 的 `platform_catalog.platforms[].display_name`；没有目录时用现有 `GroupPlatform.title`（`Sources/Sub2Core/GroupManagement.swift:56-66`）；未知值原样 |
| `type`：`oauth` / `setup-token` / `apikey` / `upstream` / `bedrock` / `service_account` | OAuth / Setup Token / API Key / 对接上游 / AWS Bedrock / Vertex。**例外**：`platform == antigravity && type == apikey` 显示“对接上游”（Web 的“上游”选项以 apikey 创建，`service/admin_meta_catalog.go:35-45`） |
| 账号状态词 | 错误、过载中、限流中、临时不可调度、暂停、停用、正常（BUILDER_GUIDE 硬规则） |
| 动作 | 启用调度 / 停止调度、恢复状态、测试连接、刷新令牌、更换 API Key…、重新授权…、启用账号、删除账号… |
| 金额 | `$1,234.56`；负数 `−$`；缺失 `—`；0 显示 `$0.00`；计费数字不着色 |
| 用语 | “实际”“账号成本”“标准”三个口径名；不出现“成本”“营收” |

### 0.4 写操作通用规则（本章）

1. **可逆操作直接执行 + 回执给“撤销”**：调度开关、启用 / 停用账号、内联编辑各分区保存、代理切换。撤销 = 用旧值再提交一次（PATCH 时带最新 ETag）。例外：“恢复原代理”先确认、不给撤销（§3.4）。
2. **不可撤销的凭据操作**：更换 API Key、重新授权、刷新令牌。sheet 底部红色按钮即确认；设置里“高风险操作需要 Face ID”打开时，按下后先验证 Face ID 再提交。回执给“测试”或“启用调度”，不给撤销。
3. **删除**：放在 ⋯ 菜单最后（红字）；Face ID 关闭时须输入完整账号名，打开时为“用 Face ID 删除”（`confirmDelete` 规则）。
4. **批量操作**：Face ID 打开时执行前验证（BUILDER_GUIDE：Face ID 覆盖批量操作）。
5. **PATCH 版本**：`GET /admin/accounts/:id` 与 `PATCH` 响应头 `ETag: "cv-<config_version>"`（`service/account_patch.go:18-21`）。列表项不带版本号，所以任何 PATCH 之前必须已有该账号详情的 ETag。PATCH 不支持 Idempotency-Key（G06 未纳入），按“不带 key 的写”处理（00 §2.4，不自动重发）。超时 / 断开后：`GET :id`，所改字段已等于目标值即视为成功，否则提示“没有保存成功”并给“重试”（用户点按；同一 If-Match 重发安全：若第一次已生效，会得到 412 再走比对，00 §2.5.1 注）。
6. **412 `ACCOUNT_VERSION_CONFLICT`**：`metadata.current_etag` 给新 ETag。处理：`GET :id`；若服务端当前值在本次要改的字段（含 `credentials_patch` / `extra_patch` 的键）上仍等于 sheet 打开时的底值 → 用新 ETag 静默重发一次；否则弹框“账号已被其他人修改”，按钮“用我的修改覆盖”（新 ETag 重发）/“重新载入”（丢弃草稿）。
7. **409 `MIXED_CHANNEL_WARNING`**（新建、PUT、PATCH、bulk-update）：用 `metadata.group_name`、`current_platform`、`other_platform` 弹框（Web 文案）“警告：分组“{group_name}”中同时包含 {current_platform} 和 {other_platform} 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？”，按钮“继续保存 / 继续创建”“取消”；确认后请求体加 `confirm_mixed_channel_risk: true` 重发（请求体变了：带 Idempotency-Key 的必须换新 key，00 §2.5.2）。没有 `metadata` 的老服务端：先调 `check-mixed-channel` 拿 `details`。
8. **App 端错误对象必须保留 `reason` 与 `metadata`**：现有 `APIError` 只有 `reason`（`Sources/Sub2Core/APIError.swift`），本章多处依赖 `metadata`（`current_etag`、`run_id`、`recovered`、`retry_within_seconds`、`upstream_status`、`detail`、`group_name` 等），见 §11。

### 0.5 本章错误 reason → 文案与动作

通用码（401 续期 / 重登、403 `STEP_UP_REQUIRED`、423 合规、429、5xx、`ACCESS_TOKEN_READ_ONLY`、全部 `IDEMPOTENCY_*` 幂等码等）按 00 处理：幂等码的等待时长、何时转“待核对”、`IDEMPOTENCY_KEY_CONFLICT` 回到确认框用新 key 重新确认，都以 00 §2.5.3–§2.5.4 为准，本章不另定数值。下表只列本章特有的：

| HTTP · reason | 出现在 | 文案 | 动作 |
|---|---|---|---|
| 404 `ACCOUNT_NOT_FOUND` | 任何 `:id` 接口 | “这个账号已删除或不在本工作区” | 详情页换成“已删除”空页；列表移除该行并轻刷新；DELETE 遇到它视为已删除 |
| 412 `ACCOUNT_VERSION_CONFLICT` | PATCH | 见 0.4-6 | — |
| 400 `INVALID_IF_MATCH` / `INVALID_PATCH` / `CREDENTIAL_KEY_NOT_DELETABLE` | PATCH | “服务器拒绝了这次修改（{reason}）” | 记日志；属于 App 缺陷，不重试 |
| 409 `MIXED_CHANNEL_WARNING` | 新建 / 编辑分组 | 见 0.4-7 | — |
| 500 `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED` | recover-state | “已恢复 · 仍暂停调度” | 以 `GET :id` 的 `schedulable` 为准；仍暂停时回执给“启用调度” |
| 409 `ACCOUNT_TEST_RUNNING` | test-runs | “这个账号已有测试在运行” | 改为轮询 `metadata.run_id` |
| 429 `ACCOUNT_TEST_BUSY` | test-runs | “站点同时运行的测试已满，请稍后再试”（00 §2.7.2） | 写入 429：不自动重试，按钮按 `Retry-After` 倒计时（00 §2.7.2） |
| 404 `ACCOUNT_TEST_RUN_NOT_FOUND` | test-runs latest / get | “还没有测试记录” | — |
| 503 `ACCOUNT_STATS_UNAVAILABLE` | today-stats/batch | 今日金额全部显示“—” | 下次刷新重试 |
| 400 `TOO_MANY_IDS` | runtime/batch | — | 按 `metadata.max` 拆批（App 每批 ≤200，不应出现） |
| 400 `INVALID_ACCOUNT_STATUS_FILTER` / `INVALID_GROUP_FILTER` | 列表 / 汇总 | — | App 缺陷，去掉该参数重试 |
| 400 `*_OAUTH_SESSION_NOT_FOUND` | 换码 / 重新授权 | “授权链接已过期” | “重新生成链接” |
| 400 `*_OAUTH_INVALID_STATE` | 同上 | “授权码不是这次链接换来的” | “重新打开本次链接”/“重新生成链接” |
| 400 `*_OAUTH_CODE_REJECTED` | 同上 | “授权码无效或已被使用” | 重新授权；Grok 必须重新生成链接（会话已消费） |
| 403 `GROK_OAUTH_ENTITLEMENT_DENIED` | 同上 | “这个 xAI 账号没有授权” | 换账号授权 |
| 502 `OAUTH_EXCHANGE_FAILED` | reauthorize | “服务器连不上 {平台}” | 换代理或稍后重试；Grok 需重新生成链接 |
| 502 `OPENAI_OAUTH_PROXY_REQUIRED` / `*_OAUTH_TOKEN_EXCHANGE_FAILED` / `*_OAUTH_REQUEST_FAILED` | 新建账号换码 | “服务器连不上 {平台}，授权码还没用掉” | “换个代理再试”（不重新授权） |
| 500 `REAUTH_PERSIST_FAILED` | reauthorize | “令牌已换到，但没保存成功” | 不自动重试（00 §2.4、§3.2）。先 `GET :id` 读回：`token_status.refreshed_at` 晚于发起时间（ServerTime）即已保存，按成功处理；否则给“重试保存”（用户点按，同一请求体、同一 `session_id`，服务端已暂存令牌、不重新换码），只在 `metadata.retry_within_seconds` 秒内显示，过期后改为“重新授权” |
| 400 `NOT_OAUTH` / `REAUTH_UNSUPPORTED` | reauthorize | `metadata.detail`：`shadow_account` “影子账号的凭据跟随母账号，请重新授权母账号”；`codex_personal_access_token` “PAT 账号请在 Web 重新导入”；其余“这个账号不能在手机上重新授权” | 给“在 Web 中编辑” |
| 404 `PROXY_NOT_FOUND` | 授权（vendor） | “代理不属于本工作区” | 改选代理或不用代理 |
| 400 `ACCOUNT_NOT_IN_FALLBACK` | 恢复原代理 | “这个账号已不在回退状态” | `GET :id` 刷新，“已回退”行随之消失 |
| 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE` | 恢复原代理 | “原代理已删除、停用或过期，续期并启用后才能恢复” | 给“查看原代理”（push `.proxyDetail(proxy_fallback_origin_id)`，60 章 §13） |
| 404 `RESOURCE_NOT_FOUND` / 403 `WORKSPACE_PERMISSION_DENIED` | vendor 访问 | “没有这个账号的权限” | — |
| 404 `OPS_DISABLED` | 记录区上游错误计数、状态卡“最近上游错误”行、组头告警牌 | 记录区右侧写“运维监控未开启”；状态卡行按 §2.3 退路；告警牌不显示 | 不重试 |

### 0.6 时间与时区（引用 00 §6.3）

- 本章所有 `now`（状态推导、倒计时、“N 分钟前”、“须晚于现在”、“1 个月后”的起点、与服务端时间戳比先后）一律用 **ServerTime** = 本机时间 + 该站点 `Date` 头偏差（00 §6.3）；不直接用设备时钟。
- 所有绝对时间（`HH:MM`、`HH:MM:SS`、`yyyy-MM-dd HH:mm`，含“预计 HH:MM”“HH:MM 恢复”“HH:MM 到期”“更新于 HH:MM:SS”）按服务器时区（`/admin/me` 的 `server.server_timezone`）显示；日历运算用设了该时区的 `Calendar`。
- 时区提示只用 00 §6.3 的那一句“时间按服务器时区（UTC+8）显示”；本章只在过期时间选择器里出现（手机时区与服务器不同时）。
- 只量经过时长的计时（测试的“本机计时”、授权链接 30 分钟有效期）用本机单调时钟，从本次操作起算，不受偏差影响。

---

## 1. 账号列表

### 1.1 入口与导航

- 入口：Tab“账号”；概览“受限 N 个账号”等跳转带初始筛选（`needs` / `limited` / `paused`）；分组详情“查看账号”带平台或分组上下文（分组详情页另章，本页只接受 `platform` 预选）。
- 导航栏：标题“账号”（居中），副标题“{站点名} · {counts.all} 个 · {更新时间}”（“刚刚更新”/“N 分钟前更新”）；左“选择”（选择中变“完成”，突出样式）；右“＋”→ 新建账号（§7，全高 sheet）。站点切换走标题菜单（通用）。
- 点行 → 账号详情（§2）。选择模式下点行 = 勾选，Tab 栏隐藏，底部出现操作坞（§8）。
- 不放搜索框：搜索走搜索 Tab（另章，`GET /admin/accounts?search=&lite=1`）。

### 1.2 数据来源

| 用途 | 请求 | 关键参数 / 说明 |
|---|---|---|
| 列表 | `GET /admin/accounts`（`AccountHandler.List`，`handler/admin/account_handler.go:713`） | `lite=1&page=N&page_size=500&sort_by=urgency&sort_order=asc&include_counts=1`，按筛选胶囊追加 `status=`（见下）、平台菜单追加 `platform=<id>`。`page_size` 上限 1000（`pkg/response/response.go:175-197`）。page 1 返回后若 `total` 大于已加载数，顺序加载后续页，最多加载 2000 行（4 页）；超过时列表底部写“还有 N 个账号未加载，用平台筛选缩小范围”。每页记下响应头 `ETag`，刷新时带 `If-None-Match`，304 时保留该页 |
| 计数 | 同一响应的 `data.counts` | `{all, needs_attention, error, overloaded, rate_limited, temp_unschedulable, unschedulable, inactive, schedulable_now}`（`service/account_list_query.go:86-96`），与当前 `status` 无关、受 `platform` 影响 |
| 组头计数、Tab 徽标 | `GET /admin/accounts/status-summary`（`account_status_summary_handler.go`） | 不带参数；用 `platforms[]`（每项 `platform`、`total`、`available`、`error`、`overloaded`、`rate_limited`、`temp_unschedulable`、`paused`、`inactive`、`stopped`）与 `totals.error`；不依赖运维监控；服务端 10 秒缓存 |
| 每行“今日” | `POST /admin/accounts/today-stats/batch` | `{"account_ids":[…]}`，App 每批 ≤200；`data.stats["<id>"].user_cost`；`data.failed_account_ids`（升序去重，按集合匹配）里的账号显示“—” |
| 实时数（轻刷新） | `POST /admin/accounts/runtime/batch` | `{"account_ids":[…]}`（≤200，超过 400 `TOO_MANY_IDS`），可加 `?include_window_cost=0`；`data.items["<id>"]`：`current_concurrency`（可为 null）、`concurrency_available`、`status`、`schedulable`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`；越权 / 已删的 ID 不出现 |
| 分组名与排序 | `GET /admin/groups/all?include_inactive=true` | 取 `id`、`name`、`platform`、`status`、`sort_order`；站点内缓存，进入 Tab 时后台刷新 |
| 平台显示名 | `GET /admin/meta/catalog` | 带 `If-None-Match` 缓存；切换站点或登录身份后清缓存 |
| 组头告警牌 | `GET /admin/ops/alert-events?status=firing&limit=100`（`OpsHandler.ListAlertEvents`，`handler/admin/ops_alerts_handler.go:612`） | 与 10 章 §6.2“告警中”是同一请求，由账号列表在 Tab 可见时发起；结果写进 `LiveOpsStore` 的告警列表（与首页、监控、告警详情共用一份，10 章 §0.5），`LiveOpsStore` 里这份列表 60 秒内刚取过就直接用、不再发。用到的字段：`id`、`rule_id`、`severity`、`status`、`title`、`description`、`dimensions.platform`、`dimensions.group_id`、`fired_at`、`silence {id, until}`、`rule`、`group_name`。404 `OPS_DISABLED` 或失败 → 不显示告警牌 |

筛选胶囊 → `status` 参数（C14）：

| 胶囊 | `status` | 胶囊上的数字 |
|---|---|---|
| 需处理（有数时红色强调） | `needs_attention` | `counts.needs_attention` |
| 全部（默认） | 不传 | `counts.all` |
| 受限 | `overloaded,rate_limited,temp_unschedulable` | `counts.needs_attention − counts.error`（进度表口径，两者不相交） |
| 暂停·停用 | `unschedulable,inactive` | `counts.unschedulable + counts.inactive` |
| 平台 ▾（菜单） | 追加 `platform=<id>` | 菜单每项右侧写该平台 `status-summary.platforms[].total`；“全部平台”写 `counts.all` |

口径差（写进代码注释，不提示用户）：`unschedulable` 把“过载中又停了调度”的账号算进来，D02 判为过载中；刚到期、尚未被后台任务停调度的自动暂停账号，D02 算暂停而 `unschedulable` 不算；`inactive` 只匹配 `status=inactive`（历史值 `disabled` 只计入全部）。

没有 `accounts.list_query`（老服务端）：不带 `status` / `sort_by=urgency` / `include_counts`，以 `sort_by=name` 全量分页拉取，本地按 0.2 推导状态、筛选、计数、按紧急度排序（紧急度见 1.3）。

没有 `accounts.status_summary` 或 vendor（D02 不对 vendor 开放）：组头计数用已加载行本地统计；此时只在“全部”胶囊下准确，其他胶囊下组头只写个数、不写需处理数。

### 1.3 字段 → 显示映射

**分区（按平台）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 分区顺序 | 平台集合 = 已加载行的 `platform`；排序键：有错误或过载（`error + overloaded > 0`）=0 → 有需处理 =1 → 正常 =2 → 全部是暂停 / 停用 =3；同级按需处理数降序、总数降序 | 列表存活期间**冻结顺序**（push 详情再返回不跳动），下拉刷新时重排 | — |
| 组头标题 | 平台显示名 + `total` | “Anthropic 4” | — |
| 组头右侧 | 需处理 = `error + overloaded + rate_limited + temp_unschedulable`；`stopped`；`paused`、`inactive` | 有需处理：先“已停止调度 N”（neutral，N>0 时），再“需处理 N”（有错误 / 过载用 critical，否则 caution）；无需处理且 `paused + inactive == total`：“暂停 N · 停用 M”（neutral）；其余不写 | 组头数字始终描述整个平台，不受胶囊影响 |
| 组头告警牌 | `LiveOpsStore` 告警列表里 `status == firing` 且 `dimensions.platform`（忽略大小写）等于该平台 id 的事件；多条时取级别最高（P0 → P3）、同级 `fired_at` 最新的一条 | “{severity} 告警”；该事件 `silence` 非 null 时“{severity} 已静默”；色调 `alertTone`（10 章 §0.6，静默中的事件仍是 firing，保持原色）。点按打开“告警”sheet（§1.4） | 运维关闭、请求失败或无匹配时不显示 |
| 收起 / 展开 | 点组头切换；选择模式下组头右侧“全选 / 取消全选”（只作用于该分区已加载的行） | 收起时选择模式下写“已选 N” | 收起状态按站点存在内存，列表存活期间保留 |
| 分区内排序 | 先按“主分组”：账号 `group_ids` 中 `sort_order` 最小的分组（未分组排最后，未知分组排在未分组之前），再保持服务端 `urgency` 顺序（稳定排序） | — | — |

服务端 `urgency` 顺序：错误 > 限时窗口（按最晚解除时间从近到远）> 暂停 > 其他非 active > 正常，同级按 name、id（进度表 C14）。老服务端本地按同样规则排。

**行（三行，`AccountRow`）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 左侧状态胶囊 | 0.2 色调 | 只有 caution / critical 画胶囊；同一列表里紧挨着的有色行连成一根连续状态轨（不同色也连），整段只有最上和最下是圆头（DECISIONS 第 138 行）；宽 4、离左 6、离上下 10 | 正常 / 暂停 / 停用不画 |
| 行首图标 | 状态图标（正常 dot、限流 hourglass、过载 flame、临时 clockAlert、错误 octagon、暂停 pause、停用 minus） | 选择模式下换成勾选圈 | — |
| 第 1 行左 | `name` | 单行省略 | — |
| 第 1 行右 | 状态牌 | 状态词；限时状态在牌内带倒计时 `m:ss` / `h:mm:ss`，每秒走 | — |
| 第 2 行 | 分组名（`group_ids` → 分组目录名，“、”分隔）· 类型显示名 | 平台分区内省略平台：“高级组、Claude Code 组 · OAuth” | 无分组写“未分组”；目录里找不到写“#id” |
| 第 3 行（错误） | `error_summary` | 单行省略 | 空时“上游返回异常” |
| 第 3 行（限时） | [已停止调度 ·] 原因短句 · HH:MM 恢复 [· 模型限流 N] | “已停止调度”打头（只截尾部），393pt 下“HH:MM 恢复”不被截 | 无模型限流不写尾段 |
| 第 3 行（其他） | 左：并发 `current_concurrency / concurrency`；右：“今日” + `user_cost` | 并发用容量条样式；金额 `$x.xx` | `concurrency_available == false` 或 `concurrency == 0` 时“— 并发”；今日失败“—” |
| 暂停 / 停用行 | — | 整行降低不透明度（`is-idle`） | — |
| 尾部 | chevron | 选择模式下不显示 | — |

空态：当前胶囊 / 平台下没有账号 → 分区区域显示一张卡“没有符合条件的账号”。

### 1.4 交互与写操作

- 胶囊切换：立即用新 `status` 重新加载（保留旧列表直到新数据到达，显示进度）；平台菜单选中后胶囊行最前出现可移除的“平台：Anthropic ✕”，横向滚回开头。
- 行右滑（可选，List `.swipeActions(edge: .trailing)`）：正常 / 限时且开关开 →“停止调度”；开关关 →“启用调度”。调 `POST /admin/accounts/:id/schedulable`（§5），回执带撤销。
- 选择模式与操作坞见 §8。
- **组头告警牌 → “告警”sheet**（本章定义，设计稿 `v-accounts.jsx` `useVaAlert`；告警牌是组头里独立的按钮，点它不收起分区）。sheet 标题“告警”，左“关闭”，内容自上而下：
  - 事件卡：标题（10 章 §6.3 `AlertPresentation` 的标题）+ 级别牌（“{severity}”/“{severity} 已静默”，`alertTone`）；下一行范围文案 + 规则文案（同 `AlertPresentation`，规则缺失时 `description` 原文）。
  - 两行键值：“维度”= `AlertPresentation` 的范围文案；“状态”=“告警中”或“告警中 · 已静默至 HH:MM”（`silence.until`）。
  - 说明：“告警只精确到分组或平台，不指向具体账号；先看本组需处理的账号。”
  - 按钮行：“手动解决”（主）、“静默…”（已静默时“改静默时长…”）。两者都调 10 章 §7.1 的 `AlertActions`（确认框文案、时长、请求、回执、撤销、错误 reason 全部照 §7.1，本章不另写）；成功后 `LiveOpsStore` 更新，组头告警牌随之消失或改为“已静默”，sheet 关闭。
  - 两个链接行：“只看需处理的账号 ›”（关闭 sheet，胶囊切到“需处理”）；“告警详情 ›”（关闭 sheet，push `{kind:'alert', id}`，10 章 §3）。
  - 只读访问令牌：两个按钮按 00 §2.6.3 置灰并标“只读令牌”。
- 下拉刷新：完整重载（列表 + 汇总 + 今日）。

### 1.5 状态

| 状态 | 表现 |
|---|---|
| 首次加载 | 骨架行 3 条 + 胶囊占位；组头不画 |
| 加载中（已有数据） | 导航副标题写“正在刷新…”，不清空列表 |
| 后续页加载中 | 列表底部“正在加载更多账号…” |
| 列表失败（已有数据） | 顶部 neutral 横幅“读取失败，显示的是 HH:MM 的数据”+“重试” |
| 列表失败（无数据） | 空页“读取账号失败”+ 原因 + “重试” |
| 汇总失败 | 组头退回本地计数（同 1.2 退路），不提示 |
| 今日失败 | 金额“—”；全部失败（503）时不再单独提示 |
| 运行时失败 | 保留上次值，不提示 |
| 告警列表失败 / 运维关闭 | 不显示组头告警牌，不提示；已打开的“告警”sheet 里的动作失败按 10 章 §7.1 的错误表 |

### 1.6 刷新策略

- 前台且 Tab 可见、不在选择模式、没有打开的 sheet：每 60 秒一次**轻刷新**：`runtime/batch`（已加载 ID，按 200 拆批）+ `status-summary` + `today-stats/batch` + firing 告警列表（1.2；`LiveOpsStore` 60 秒内已取过则跳过）。任一行的 `status` 或 `schedulable` 变化、或有 ID 不在返回里 → 触发一次**完整刷新**（所有已加载页，带 `If-None-Match`）。
- 完整刷新还发生在：进入 Tab、下拉、站点切换、本章任何写操作成功后、每 5 分钟。
- 倒计时本地每秒走；任一行倒计时归零 → 立即轻刷新一次（10 秒内最多一次）。
- App 进后台 / Tab 不可见：停止定时器；回到前台立即轻刷新。
- 没有 `accounts.runtime_batch`：60 秒改为完整刷新。
- 账号 Tab 徽标：`status-summary.totals.error`（没有能力时 `GET /admin/dashboard/stats` 的 `error_accounts`）；任一页取到汇总即更新；另由 AppModel 在前台每 60 秒补取一次（60 秒内已取过则跳过）。

### 1.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountsView.swift` : `AccountsView` | 重写为平台分组三行列表。数据与定时器移到新文件 `NativeApp/Features/Accounts/AccountListModel.swift`（`@Observable`：查询、分页、ETag、计数、汇总、今日、运行时、冻结的平台顺序、收起集合）。去掉“显示字段”工具栏、“筛选与排序”表单、“前台自动刷新”开关（改为默认 60 秒）、“快捷编辑”滑动与上下文菜单 |
| 同文件 : `accountRow(_:)` | 改为新文件 `Accounts/AccountRow.swift`（三行 + 状态胶囊 + 倒计时，倒计时用 `TimelineView(.periodic(from:by: 1))`） |
| 同文件 : 批量相关（`AccountBatchAction` 等） | 移到 §8 的操作坞；保留 `AccountBulkReply.outcome(for:)` 的“缺失 / 重复不算成功”语义 |
| `Sources/Sub2Core/AccountManagement.swift` : `AccountListQuery` | `page_size` 改为可配（默认 500）；`status` 改为 `Set<AccountStatusFilter>`（逗号拼接）；`AccountSort` 增加 `urgency`；新增 `includeCounts`；`queryItems` 输出 `include_counts=1` |
| 同文件 : `managedAccounts` | 返回 `AccountListPage { items, total, page, pageSize, pages, counts?, etag? }`，支持传入 `If-None-Match` 并识别 304 |
| `Sources/Sub2Core/Models.swift` : `UpstreamAccount` | 增字段：`error_at`、`error_status_code`、`error_kind`、`error_summary`、`token_status`、`concurrency_available`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`、`temp_unschedulable_reason`、`auto_pause_on_expired`、`updated_at`、`proxy_id`、`proxy_fallback_origin_id`、`proxy_fallback_origin_name`（`dto/types.go:239-240`）、`credentials`（非敏感键）、`credentials_status`、`session_idle_timeout_minutes`；`extra` 保留整份原始 JSON（新增 `JSONValue`）并派生 `modelRateLimits`、`upstreamBillingProbe` |
| `Sources/Sub2Core/APIClient.swift` : `accountTodayStats(ids:)` | 解码 `failed_account_ids`、`degraded`（返回结构体而非字典），按 200 拆批，支持可选 `group_id` |
| 新增 `Sources/Sub2Core/AccountStatusSummary.swift` | `statusSummary(platform:groupID:includeAccounts:)` 与模型 |
| 新增 `Sources/Sub2Core/AccountRuntimeBatch.swift` | `accountRuntime(ids:)`，`current_concurrency` 可为 null |
| 新增 `Sources/Sub2Core/AccountDisplayState.swift` | 0.2 的推导与文案（纯函数，配表驱动单测） |
| `Sources/Sub2Core/GroupManagement.swift` : `AdminGroup` | 增 `sortOrder`（`sort_order`）；`allGroups()` 增 `includeInactive` 参数（现在没带，附录 B L15） |
| `NativeApp/Sub2MobileApp.swift` : TabView | 账号 Tab 加 `.badge(errorCount)` |
| `NativeApp/Session/LiveOpsStore.swift`（10 章新增） | 账号 Tab 可见时由 `AccountListModel` 调它的 firing 告警刷新方法（与监控 · 告警段同一方法、同一份列表，不另建缓存），并按平台取匹配事件 |
| 新增 `NativeApp/Features/Accounts/AccountAlertSheet.swift` | 1.4 的“告警”sheet；文案用 10 章 `AlertPresentation`，动作调 10 章 §7.1 `AlertActions` |
| 可复用 | `AccountFieldPresentation`（`AccountPresentation.swift`）与 `ListFieldSelection` 留给简化模式，不删；`DashboardLoadState`、`load(nextPage:replace:)` 的“请求票据 + 会话代际”防串写写法沿用 |
| `UITests/AccountListCustomizationUITests.swift`、`AccountManagementUITests.swift` | 按新列表重写；`DemoData` 补 11 个演示账号（与设计稿 `DEMO.accounts` 对应的状态覆盖） |

---

## 2. 账号详情（上半部分）

已定：账号详情就是内联编辑页（§3），上半部分 = 状态卡 + 按钮行、容量、今日、记录，下面接六个编辑分区。本节写上半部分。

### 2.1 入口与导航

- 入口：列表行；概览待处理的账号项；分组详情成员行；搜索结果；请求详情的账号行；推送通知 `account.error` / `account.test_finished`（带 `account_id`，另章）；新建账号完成后的“查看”。
- 只带 id 进入时先显示加载态，`GET /admin/accounts/:id` 后渲染；从列表进入时先用列表行数据渲染，再拉详情。
- 导航栏：返回；标题 = `name`；副标题 = “{平台显示名} · {类型显示名}”；右侧 ⋯ 菜单（§3.4）。
- 去向：记录区“上游错误”→ 使用记录（上游错误段，按本账号筛选，日志章节的 `{kind:'logs', scope:'upstream', account:id}`）；“使用记录”→ 用量明细按本账号筛选；状态卡“最近上游错误 … ›”行 → 那一条上游错误的请求详情（40 章 §7，`request` 路由 `.error(id, kind: upstream)`，与设计稿 `hero-last` 一致）。

### 2.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 账号 | `GET /admin/accounts/:id` | 完整 DTO（含 `groups`、`proxy`、`credentials`（脱敏）、`credentials_status.has_*`、`extra`、`token_status`、运行时字段、`concurrency_available`）；**响应头 `ETag` 记为该账号的编辑版本**。此接口不支持 304，不要带 `If-None-Match` |
| 今日 | `GET /admin/accounts/:id/today-stats` | `data` 直接是 `{requests, tokens, cost, standard_cost, user_cost}`（`service.WindowStats`）；“今日”按服务器时区 |
| 5 小时窗口 | `GET /admin/accounts/:id/usage?source=passive` | 只对 `platform == anthropic && type ∈ {oauth, setup-token}` 调；`five_hour.utilization`（0–100+）÷ 100；`five_hour` 为 null 时不画。必须带 `source=passive`（缺省 active 可能请求上游） |
| 上游错误（计数 + 最近一条） | `GET /admin/ops/upstream-errors?account_id=:id&time_range=24h&page=1&page_size=1`（`OpsHandler.ListUpstreamErrors`，`handler/admin/ops_handler.go:473`） | 一次请求两用：分页 `total` 给记录区计数；`items[0]`（默认按 `created_at` 倒序，即最新一条）给状态卡“最近上游错误”行，取 `id`、`created_at`、`status_code`、`message`、`phase`。列表含已重试成功的恢复行（`IncludeRecoveredUpstream = true`，同文件第 504 行）；运维关闭返回 404 `OPS_DISABLED` |
| 定时测试 | §9 | — |
| 轻刷新 | `POST /admin/accounts/runtime/batch {"account_ids":[id]}` | 60 秒一次，更新容量和状态；`status` / `schedulable` 变了再 `GET :id` |

### 2.3 字段 → 显示映射

**状态卡（`detail-head`）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 正常 | 0.2 = 正常 | 安静卡：图标 + “正常 · 参与调度” | — |
| 暂停 / 停用 | 0.2 = 暂停 / 停用 | “暂停 · 不参与调度”/“停用 · 不参与调度”；到期自动暂停写“暂停 · 已过期，自动暂停调度” | — |
| 状态牌 + 原因 | 0.2 状态词 + 原因短句 | 大号状态牌 + 原因（如“上游 429”“上游 529 · 规则 #1”） | — |
| 大号倒计时（限时） | 该状态窗口结束时间 − now | `m:ss` / `h:mm:ss`，下方“后自动恢复 · 预计 HH:MM” | — |
| 错误正文（错误） | `error_summary` | 多行 | 空时“上游返回异常” |
| 最近上游错误行（错误） | 2.2 上游错误请求的 `items[0]`：时间 `created_at`；状态码按 40 章 §6.3 上游错误行的取法——`status_code ≥ 400` 直接用；`< 400`（已重试成功的恢复行，`status_code` 是客户端最终拿到的码，例如 200）从 `message` 解析 `Recovered upstream error (\d{3})`；解析不到且 `phase == account_auth` 写“鉴权”；都没有时不写状态码段 | 设计稿原文：“最近上游错误 HH:MM · N 分钟前 · 401 ›”（状态码等宽）；不写状态码段时为“最近上游错误 HH:MM · N 分钟前 ›”。点按 → 这一条的请求详情（`.error(id: items[0].id, kind: upstream)`，40 章 §7） | 运维关闭（`OPS_DISABLED`）、请求失败或 24 小时内没有记录：有 C02 且 `error_at` 非 null 时显示不可点（无 chevron）的“出错于 HH:MM · N 分钟前[ · {error_status_code}]”（设计稿之外的退路，见未决问题 8）；否则整行不显示 |
| 已停止调度提示 | 0.2 已停止调度 | “已停止调度 · 到时恢复后也不参与调度” | — |
| 出错停调度提示 | 错误且 `schedulable == false` | “出错时已自动停止调度 · 恢复时可一并启用” | — |
| 模型限流块 | 0.2 模型限流 | 标题“模型限流 N”；每行 `模型（等宽）` + “N 分钟后”（≥60 写“X 小时 Y 分钟”） | 没有时不画 |

**按钮行**（与 `AccountDetailTop` 完全一致，主按钮在前）

| 显示状态 | 按钮 |
|---|---|
| 正常 | **测试连接** · 停止调度 |
| 停用 | **启用账号** · 测试连接 |
| 暂停 | **启用调度** · 测试连接 |
| 错误 · 凭据类 · 未更换 | 令牌账号 **重新授权…**，否则 **更换 API Key…** · 恢复状态 · 测试连接（`bedrock` / `service_account` 账号主按钮改为 **在 Web 中更换凭据**，见未决问题 3） |
| 错误 · 凭据类 · 本次已更换 Key | **测试连接** · 恢复状态 |
| 错误 · 其他 | **恢复状态** · 测试连接 |
| 限时（过载 / 限流 / 临时） | **恢复状态** · 测试连接 · 停止调度（开关已关时为“启用调度”） |

“本次已更换 Key”：App 内存里按账号 id 记一个标记，更换成功时置上，账号 `status` 不再是 `error` 时清除（测试通过会清错误）。

**容量（壹）** — 有一项就画这一节；标题右侧“更新于 HH:MM:SS”

| 行 | 字段 | 格式 | 不显示的条件 |
|---|---|---|---|
| 并发 | `current_concurrency` / `concurrency` | 容量条 + `x/y` | `concurrency == 0` 不画；`concurrency_available == false` 时写“— / y” |
| 调度 RPM | `scheduling_rpm` / `base_rpm` | `x/y`，注“自然分钟” | `base_rpm` 缺失或 0；`scheduling_rpm` 缺失写“—” |
| 会话 | `active_sessions` / `max_sessions` | `x/y`，注“空闲 {session_idle_timeout_minutes} 分钟释放” | `max_sessions` 缺失或 0；注里分钟数缺失时不写注 |
| 日 / 周 / 总配额 | `quota_daily_used`/`quota_daily_limit`、`quota_weekly_used`/`quota_weekly_limit`、`quota_used`/`quota_limit` | 金额容量条 `$96.30 / $150.00` | 对应 limit 缺失或 0 |
| 5 小时窗口 | `usage?source=passive` 的 `five_hour.utilization ÷ 100` | 比例条 + 百分比，注“{resets_at HH:MM} 重置” | 非 Anthropic 令牌账号、`five_hour` 为 null、请求失败 |

**今日（贰）**

| 界面元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 实际 | `user_cost` | 大号金额 | 失败时“—”并在节内写“读取失败 · 重试” |
| 账号成本 | `cost` | 大号金额 | 同上 |
| 标准 | `standard_cost` | 大号金额 | 同上 |
| 请求 / Tokens | `requests` / `tokens`（含缓存） | `4,418` / `27.3M` | 同上 |
| 节脚注 | 附录 B L17 | “账号成本与标准只按真实上游调用计算；实际扣费还含合并探测的跟随请求。” | — |

**记录（叁）**

| 行 | 数据 | 右侧文案 | 不可用 |
|---|---|---|---|
| 上游错误 | 2.2 的 `total` | “近 24 小时 N 条” | 运维关闭写“运维监控未开启”，行仍可点（日志页显示同样提示） |
| 使用记录 | — | 无 | — |
| 定时测试 | §9 | “每 10 分钟 · 上次成功 / 失败” | 见 §9 |

### 2.4 交互与写操作

按钮行动作的接口与回执见 §5（启停调度、恢复、启用账号）、§4（测试连接）、§6（更换 API Key / 重新授权）。

### 2.5 状态

| 状态 | 表现 |
|---|---|
| 只带 id 进入的首次加载 | 状态卡骨架 + 各节占位 |
| `GET :id` 失败（有列表快照） | 用快照渲染，顶部横幅“读取最新数据失败，显示的是列表里的快照”+ 重试；编辑分区的“编辑”按钮置灰（没有 ETag） |
| `GET :id` 失败（无快照） | 空页“读取账号失败”+ 重试 |
| 404 `ACCOUNT_NOT_FOUND` | 整页换成“这个账号已删除。”（`RemovedAccount`） |
| 今日 / 5 小时 / 上游错误失败 | 各自节内降级（上表），不影响其他节 |

### 2.6 刷新策略

- 前台且页面可见、没有打开的 sheet / 确认框：每 60 秒 `runtime/batch`（单 id）+ `today-stats` + `usage?source=passive`（适用账号）+ 上游错误（计数与最近一条，同一请求）；`status` / `schedulable` 有变化或倒计时归零时立即 `GET :id`。没有 `accounts.runtime_batch` 时 60 秒直接 `GET :id`。
- 下拉刷新：全部重拉。
- 打开编辑 sheet 期间暂停定时刷新；sheet 有自己的底值与 ETag，页面轮询**不得**改写 sheet 的底值。
- 写操作成功后：用写接口返回的账号对象替换；需要 ETag 而响应没有带时（`schedulable`、`recover-state`、`refresh`、`reauthorize` 不返回 ETag），在下一次 PATCH 前补一次 `GET :id`。

### 2.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountsView.swift` : `AccountDetailView` | 替换为新文件 `Accounts/AccountDetailScreen.swift`（上半部分 = `AccountDetailTop` 视图，下接 §3 分区）。现有 `reloadAccount` / `reloadStats` 的票据与会话代际校验、`pollAccount` 的循环写法可复用，间隔改 60 秒 |
| 同文件 : “管理操作”“记录与分析”两节 | 删除；“账号统计分析”入口不在已定设计里（统计分析页按账号筛选另章决定） |
| `Sources/Sub2Core/APIClient.swift` : `account(id:)` | 新增返回 `(UpstreamAccount, etag: String?)` 的变体（`request` 要能拿到响应头） |
| 新增 `Sources/Sub2Core/AccountUsageWindow.swift` | `accountPassiveUsage(id:)` → `five_hour {utilization, resets_at, remaining_seconds}` |
| 上游错误（计数 + 最近一条） | 不新建接口方法：调 40 章 §6.7 的 `errorRecords(page: 1, filter:, kind: .upstream)`（`RequestLogFilter` 带 `accountID`、`time = .rolling("24h")`、`pageSize = 1`），`total` 与 `items.first` 一起用。上游状态码的取法写成 `RequestErrorRecord` 上的一个计算属性（返回 `.code(Int)` / `.accountAuth` / `.unknown`），与 40 章 `LogRow` 共用：`LogRow` 把 `.accountAuth`、`.unknown` 渲染成“鉴权”“恢复”，本章状态卡把 `.unknown` 渲染成不写状态码段 |
| `NativeApp/Features/RequestLogsView.swift:371` | 打开账号详情改用 `AccountDetailScreen` |
| `NativeApp/Features/GroupsView.swift:192` | “查看与管理分组账号”入口改为分组详情成员（另章），不再复用列表 `initialGroupID` |

---

## 3. 详情内联编辑、⋯ 菜单、删除、在 Web 中编辑

### 3.1 入口与导航

- 详情上半部分之下依次是六个分区：**基础 · 调度 · 凭据 · 代理 · 模型 · 高级**（取代原“档案”）。分区里是只读表单行（`List` + `LabeledContent`）。
- 基础 / 调度 / 模型 / 高级：分区右上“编辑”→ 小表单 sheet（左“取消”、右“保存”）；sheet 内的选择器（分组、过期时间、添加模型、添加映射、选项列表）在 sheet 内 push，不叠第二个 sheet。
- 凭据：行内“更换”“修改”或“刷新令牌 / 重新授权…”行（§6）。
- 代理：分区右上“编辑”→ 代理选择 sheet，选中即生效；有代理时点代理行 → push 代理详情 `.proxyDetail(id)`（60 章 §13，与 60 章“账号详情的代理行”入口一致；设计稿里点行也打开选择器，改动见未决问题 9）；无代理时点行同“编辑”。账号处于到期回退状态时，代理行下多一行“已回退 · 恢复原代理”（§3.3、§3.4）。
- 可由 route 带 `focus`（`basic / sched / cred / proxy / models / adv`）进入时滚动到该分区（凭据类错误的退路入口用 `focus: cred`）。

### 3.2 数据来源

| 用途 | 请求 |
|---|---|
| 当前值 + ETag | 已有的 `GET /admin/accounts/:id` |
| 保存 | `PATCH /admin/accounts/:id`（`AccountHandler.Patch`，`account_handler.go:1201`），请求头 `If-Match: <ETag>`（也可在体里传 `expected_config_version`，二者不一致 400） |
| 分组选择器 | `GET /admin/groups/all?include_inactive=true`（缓存） |
| 混合渠道预检（无 `accounts.mixed_channel_details` 时） | `POST /admin/accounts/check-mixed-channel {platform, group_ids, account_id}` → `{has_risk, error, message, details{group_id, group_name, current_platform, other_platform}}` |
| 代理选择器 | `GET /admin/proxies/all?with_count=true`（只返回启用的代理，带 `account_count`） |
| 恢复原代理 | `POST /admin/accounts/:id/revert-proxy-fallback`（`AccountHandler.RevertProxyFallback`，`account_handler.go:1816`；路由 `server/routes/admin.go:511`），无请求体 → `data` = `{"message":"reverted"}`（不返回账号对象）。服务端把 `proxy_id` 改回 `proxy_fallback_origin_id` 并清空后者（`repository/account_repo.go:4196-4215`）；原代理已删除、停用或过期 → 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE`（`service/admin_proxy.go:299-311`）；不在回退状态 → 400 `ACCOUNT_NOT_IN_FALLBACK`。不接受 Idempotency-Key |
| 添加模型 | `GET /admin/accounts/:id/models` → 数组，每项 `id`、`display_name`（显示 `display_name`，缺省用 `id`） |
| 退路（无 `accounts.patch`） | 顶层字段 `PUT /admin/accounts/:id`（稀疏，指针字段只发改过的）；改 `credentials` / `extra` 时以 `GET :id` 的整份为底合并后整份提交（附录 A S30 / S31：非敏感键没带会被删） |

PATCH 请求体（`PatchAccountRequest`，`account_handler.go:194-215`）：顶层 `name`、`notes`、`type`、`proxy_id`、`concurrency`、`priority`、`rate_multiplier`、`load_factor`、`status`（`active|inactive|error`）、`group_ids`、`expires_at`、`auto_pause_on_expired`、`upstream_billing_probe_enabled`、`confirm_mixed_channel_risk`、`expected_config_version`；`credentials_patch` / `extra_patch` 按顶层键合并，值为 `null` 删除该键，嵌套对象整体替换；**不能**带整块 `credentials` / `extra`（400 `INVALID_PATCH`）；敏感键不能用 `null` 删除（400 `CREDENTIAL_KEY_NOT_DELETABLE`）。响应 = 账号对象 + 新 `ETag`。`expires_at ≤ 0` 清除过期时间、`proxy_id = 0` 清除代理（附录 A S30）。

### 3.3 字段 → 显示映射

**基础**

| 行 | 字段 | 显示 | 编辑 sheet |
|---|---|---|---|
| 名称 | `name` | 原样 | 文本框，必填（“请输入账号名称”） |
| 账号状态 | `status` | `active` 正常 / `inactive` 停用（dim）/ `error` 错误（critical） | 分段：非错误账号“正常 \| 停用”；错误账号“错误 \| 停用”，副文案“清除错误用账号详情里的“恢复状态””，非错误账号副文案“限流、过载等运行状态不在这里改” |
| 平台 | `platform` · `type` | 显示名 | 只读 |
| 备注 | `notes` | 多行；空写“—” | 多行文本框，可清空（发空串） |

**调度**

| 行 | 字段 | 显示 | 编辑 sheet |
|---|---|---|---|
| 并发数 | `concurrency` | 数字 | Stepper，最小 1 |
| 优先级 | `priority`，副文案“越小越优先” | 数字 | Stepper，≥0 |
| 账号计费倍率 | `rate_multiplier`，副文案“0 表示不计费，仅影响账号计费” | `×1.2` | 文本框（decimal），`^\d+(\.\d+)?$`，否则“账号计费倍率需要是不小于 0 的数字” |
| 负载因子 | `load_factor`，副文案“越大越常被选中” | 缺失或 0 写“默认” | 文本框（整数），1–10000；留空或 0 = 默认（发 0）；否则“负载因子为 1–10000 的整数；留空或 0 恢复默认” |
| 分组 | `group_ids`（显示用 `groups[].name`） | 胶囊列表；空写“未分组” | push“分组”选择器（见下） |
| 过期时间 | `expires_at`（Unix 秒，按服务器时区显示 `yyyy-MM-dd HH:mm`，0.6） | 空写“不过期”；`auto_pause_on_expired` 为真时副文案“到期自动暂停调度” | push“过期时间”：不过期 / 1 个月后 / 1 年后（以 ServerTime 的现在为起点，在服务器时区日历上加 N 个月，月底对齐）/ 自定义（日历 + 时间，`DatePicker` 加 `.environment(\.timeZone, 服务器时区)`，须晚于 ServerTime 的现在；手机时区与服务器不同时脚注“时间按服务器时区（UTC+8）显示”）；选“不过期”发 `expires_at: 0` |
| 过期自动暂停调度 | `auto_pause_on_expired` | — | 有过期时间时才出现的开关 |
| 日 / 周 / 总限额 | `extra.quota_daily_limit` / `quota_weekly_limit` / `quota_limit`；副文案“已用 $x”（`quota_*_used`） | 只列已设置的；都没设写一行“配额 · 日 / 周 / 总限额 · 不限” | 只有 `type ∈ {apikey, bedrock}` 才有这一组（后端 `IsAPIKeyOrBedrock`，`service/account.go:1326-1329`）；文本框（$，decimal），留空 = 不限（`extra_patch` 里该键发 `null`）；脚注“任一项达到后暂停调度；修改限额不重置已用额度。重置时间和用量提醒在 Web 中设置。” |

分组选择器：列出 `status == active` 且 `platform` 为本账号平台或 `composite` 的分组（Antigravity 账号 `extra.mixed_scheduling == true` 时再加 `anthropic`、`gemini`），按 `sort_order`；账号已在的分组即使停用或别的平台也列出（可移出）。每行：勾选圈、名称、徽章（停用 / 组合 / 订阅 / 专属）、副行“倍率 ×{rate_multiplier} · 可用 {active_account_count}/{account_count}”（停用分组写“分组已停用，不接收请求 · 可以移出”；`account_count` 为 0 写“还没有账号”）。Anthropic / Antigravity 账号底部注“Anthropic 与 Antigravity 账号进同一分组时，保存会先提示混合渠道风险”。

**凭据**（详见 §6）

| 账号 | 行 | 字段 | 显示 |
|---|---|---|---|
| 密钥账号 | API Key | `credentials_status.has_api_key` | 🔒“已设置 · 不可查看”+ 行内“更换”；本次已更换时写“已更换 · HH:MM”；凭据类错误且未更换时行下红字“上游拒绝了这个密钥（{error_status_code}），需要更换”；已更换未测试时写“已更换：测试连接通过后自动清除错误（仍暂停调度）” |
| 密钥账号 | Base URL | `credentials.base_url` | 等宽原样 + “修改”；空写“官方地址” |
| 令牌账号 | 访问令牌 | `token_status.expires_at`（无 C10 时解析 `credentials.expires_at`） | 徽章：剩余 ≥1 小时“有效”（ok）/ >0“即将到期”（caution）/ ≤0“已过期”（critical）；正文“N 小时后（到期 HH:MM）”/“N 分钟后（…）”；`token_status.auto_refresh == false` 时副文案“不会自动刷新” |
| 令牌账号 | 刷新令牌 | — | 动作行，标“立即生效” |
| 令牌账号 | 重新授权… | — | 动作行，标“立即生效” |
| 节脚注 | — | — | 密钥：“已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。”令牌：“令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。” |

**代理**

| 行 | 字段 | 显示 |
|---|---|---|
| 代理 | `proxy {id, name, protocol, host, port, status, expires_at, expiry_warn_days}` | 名称（粗）+ 副行“{协议} · {到期词}”（到期词规则同代理章节 `proxyExpiry`）；下方等宽 `protocol://host:port`；`proxy` 为空写“无代理”。有代理时行尾 chevron，点按 push 代理详情（§3.1） |
| 已回退（`proxy_fallback_origin_id` 非 null 时才有） | `proxy_fallback_origin_id`、`proxy_fallback_origin_name` | 标题“已回退：原代理 {proxy_fallback_origin_name}”（名称缺失写“#{id}”），副行“原代理到期后已改为{当前代理名 / 直连}”；行尾按钮“恢复原代理”（§3.4） |
| 提示 | `proxy.status` | `expired`：“代理已过期，这个账号仍挂在上面。换一个启用中的代理，或改为无代理。”；`inactive`：“代理已停用，不在可选列表里；可以换一个，或改为无代理。” |
| 节脚注 | — | “选中即生效，回执里可撤销。”（有“已回退”行时追加“恢复原代理不能撤销。”） |

代理选择 sheet：首行“无代理 · 直连上游”，其后是 `proxies/all?with_count=true` 的启用代理（按 `created_at` 倒序）：名称 + 到期徽章（进入提醒天数时）、等宽地址、“N 个账号在用 · {region} · {到期词}”。当前代理不在列表里（停用 / 过期）时在列表上方说明。

**模型**（`credentials.model_mapping`）

| 元素 | 计算 | 显示 |
|---|---|---|
| 分区右上 | 映射条数 | “只调度这 N 个”/“未限制” |
| 行 | 每个键 `from`；值 `to` | `from`（等宽）→ `to`；`to == from` 写“原样转发”；该模型在 0.2 模型限流里时加徽章“限流 N 分钟” |
| 空 | 无映射或键不存在 | “支持所有模型” |
| 透传提示 | `extra.openai_passthrough == true` | “已开启自动透传，模型限制不生效” |
| 编辑 sheet | 删除行（−）、“添加模型”（`:id/models` 多选，加入为 `{m: m}`）、“添加映射”（请求模型 → 实际模型，`*` 只能在末尾） | 脚注“列表为空时支持所有模型；列出后，没列出的模型不会调度到这个账号。映射把请求模型换成实际模型，* 只能放在末尾。” |

保存：`credentials_patch: {"model_mapping": {…整张表…}}`；清空时 `{"model_mapping": null}`。

**高级**（只放后端源码核实过键名的开关；其余进“在 Web 中编辑”）

| 适用账号 | 行 | 键 | 编辑控件 |
|---|---|---|---|
| Anthropic `oauth` / `setup-token` | 拦截预热请求 | `credentials.intercept_warmup_requests` | 开关 |
| 同上 | 5h 窗口费用控制 | `extra.window_cost_limit`（关 = 删键） | 开关 + 费用阈值（$） |
| 同上 | 会话数量控制 | `extra.max_sessions`（关 = 删键） | 开关 + 最大会话数 |
| 同上 | RPM 限制 | `extra.base_rpm`（关 = 删键；后端负值归零、超过 10000 截断） | 开关 + 基础 RPM |
| 同上 | TLS 指纹模拟 | `extra.enable_tls_fingerprint` | 开关 |
| 同上 | 会话 ID 伪装 | `extra.session_id_masking_enabled` | 开关 |
| 多协议 API Key 平台（目录里 `multi_protocol` 非空） | 账号类型 | `credentials.account_mode`（取值为该平台 `multi_protocol.modes[].mode`） | 分段（≥2 个模式时） |
| 同上 | API 协议 | `credentials.api_protocol`（`adaptive / chat_completions / anthropic / responses`，按当前模式 `base_urls` 的键过滤） | 选项列表 |
| OpenAI | 自动透传（仅替换认证） | `extra.openai_passthrough`，副文案“开启后模型限制不生效” | 开关 |
| OpenAI `apikey` | Responses API 支持 | `extra.openai_responses_mode`：`auto` 自动 / `force_responses` 强制 Responses / `force_chat_completions` 强制 Chat Completions | 选项列表 |
| `apikey` / `bedrock` | 池模式，副文案“上游是账号池时开启，错误不标记本账号” | `credentials.pool_mode` | 开关 |
| `apikey` / `bedrock` | 自动探测上游声明倍率，副文案“只探测，不改账号计费倍率” | 读 `extra.upstream_billing_probe_enabled`，写顶层 `upstream_billing_probe_enabled` | 开关 |
| 所有账号 | 在 Web 中编辑 | 副文案“自定义错误码、请求头覆写等其余设置” | 动作行（§3.4） |

设计稿里 Anthropic 令牌账号的“客户端亲和调度”：**后端无此能力**（账号级没有对应键，Web 编辑弹窗也没有）→ App 不显示。改国产厂商的接入端点（`api_base_urls` 等）不在手机编辑，放“在 Web 中编辑”。

### 3.4 交互与写操作

- **分区保存**：sheet 计算与底值的差异，只发改过的字段（顶层直接放，`credentials` / `extra` 子键放 `*_patch`）。无改动时“保存”置灰；校验不过时置灰并在字段下写错误。有改动点“取消”或下滑 → 确认框“放弃未保存的改动？{N} 项改动不会保存：{字段名…}”（“放弃改动”红 /“继续编辑”）。
- 改了 `group_ids`：有 `accounts.mixed_channel_details` 直接 PATCH，按 0.4-7 处理 409；没有则先 `check-mixed-channel`，`has_risk` 时同样弹框。
- 成功：替换账号与 ETag；回执“已保存：{前 3 个字段名}[ 等 N 项]”+“撤销”（PATCH 回旧值，带新 ETag）。撤销失败（412 等）→“撤销没有成功：账号已被修改”+“重新载入”。
- **账号状态**：改为停用 → PATCH `{status: "inactive"}`；改回正常 → `{status: "active"}`（调度开关不变：停用前已停调度的账号回来仍是暂停）。从基础 sheet 或状态卡“启用账号”都可以，回执都带撤销。
- **代理**：选中即 PATCH `{proxy_id: <id>|0}`，回执“已保存：代理 → {名称 / 无代理}”+ 撤销。
- **恢复原代理**（“已回退”行的按钮）：
  1. 确认框：标题“恢复原代理「{原代理名}」？”，正文“账号改回走 {原代理名}，出口 IP 随之改变。恢复后不能撤销。”，按钮“恢复原代理”/“取消”。不需要 Face ID、不需要 step-up。
  2. `POST :id/revert-proxy-fallback`（3.2）。成功 → `GET :id` 取最新账号与 ETag（响应不带账号）→ 回执“已恢复原代理「{原代理名}」”，**不给撤销**：服务端已清空 `proxy_fallback_origin_id`，再用 PATCH 改回备用代理只会让账号停在备用代理上、且不再记得原代理，不等于撤销；需要换代理时用“编辑”。列表完整刷新一次。
  3. 失败：按 0.5 的 `ACCOUNT_NOT_IN_FALLBACK` / `PROXY_FALLBACK_ORIGIN_UNAVAILABLE` 处理；其余通用错误回执“恢复原代理没有成功：{原因}”。
  4. 超时 / 断开：不自动重试（00 §2.4）。`GET :id` 读回：`proxy_fallback_origin_id == null` 且 `proxy_id` 等于原代理 id → 按成功处理；否则提示“结果未确认”并给“重试”（重复调用安全：已恢复时只会得到 `ACCOUNT_NOT_IN_FALLBACK`）。
- **⋯ 菜单**（SwiftUI `Menu`，删除项红字放最后，没有“编辑账号”）：
  - 密钥账号：“更换 API Key…”、“在 Web 中编辑”、“删除账号…”
  - 令牌账号：“刷新令牌”、“重新授权…”、“在 Web 中编辑”、“删除账号…”
- **删除账号…**：确认框标题“删除账号「{name}」？”，正文第一行“站点 {站点名} · 删除后不能恢复。”；Face ID 关闭时须在输入框输入完整账号名，按钮“删除账号”（红）在输入一致前置灰；Face ID 打开时按钮“用 Face ID 删除”，点后验证。`DELETE /admin/accounts/:id` → 成功或 404 → 先 pop 回列表，再回执“已删除账号「{name}」”，列表完整刷新。
- **在 Web 中编辑**（C19）：有 `web.accounts_edit_deep_link` → 用系统浏览器（`openURL`，复用 Safari 里的 Web 登录态；`SFSafariViewController` 不共享 Safari Cookie）打开 `{站点根}/admin/accounts?edit={id}&search={name 百分号编码，按 UTF-8 截到 100 字节}`，回执“已在浏览器打开「{name}」的编辑页”。没有该能力 → 打开 `{站点根}/admin/accounts` 并把账号名放进剪贴板，回执“已打开 Web 账号管理 · 已复制「{name}」，可直接搜索”。

### 3.5 状态

| 状态 | 表现 |
|---|---|
| 没有 ETag（`GET :id` 失败） | 分区“编辑”、代理行置灰，提示“先刷新账号” |
| 保存中 | sheet 的“保存”变进度，sheet 不可下滑关闭（`.interactiveDismissDisabled`） |
| 超时 / 断开 | 按 0.4-5 读回比对；已生效 → 正常回执；未生效 → sheet 内“没有保存成功”+“重试” |
| 412 / 409 / 400 | 见 0.4、0.5 |
| 删除失败（非 404） | 确认框关闭，回执“删除没有成功：{原因}” |

### 3.6 刷新策略

sheet 打开期间暂停页面定时刷新；保存成功后用响应替换；sheet 关闭后恢复 60 秒轻刷新。

### 3.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountEditView.swift` : `AccountEditView` | 拆成 `Accounts/AccountSectionSheet.swift`（basic / sched / models / adv 四种，共用差异计算与校验）。可复用：`integer(_:label:)`、倍率正则、`unresolved`（结果不明时停止提交并读回）思路、step-up 处理 |
| `Sources/Sub2Core/AccountManagement.swift` : `AccountUpdateRequest` / `PendingAccountUpdate` / `updateAccount` | 新增 `AccountPatchRequest`（含 `credentialsPatch` / `extraPatch: [String: JSONPatchValue]`，能编码显式 `null`）与 `patchAccount(id:body:ifMatch:) -> (UpstreamAccount, etag)`；旧 PUT 路径保留为退路（并按 S31 合并整份 credentials / extra） |
| 新增 `Sources/Sub2Core/JSONValue.swift` | 任意 JSON 值（`extra`、`credentials`、`model_mapping` 读写都需要） |
| 新增 `Sources/Sub2Core/AccountMixedChannel.swift` | `checkMixedChannel(platform:groupIDs:accountID:)` 与 409 `details` / `metadata` 解码 |
| 新增 `Accounts/AccountProxyPicker.swift`、`AccountGroupPicker.swift`、`AccountExpiryPicker.swift`、`AccountModelEditor.swift` | 对应选择器；代理到期词复用代理章节的函数 |
| 新增 `Sources/Sub2Core/ProxyManagement.swift`（若代理章节未提供） | `allProxies(withCount:)` |
| `APIClient.swift` | 新增 `deleteAccount(id:)`、`accountModels(id:)`、`revertAccountProxyFallback(id:)`（无体 POST，成功只表示已执行，调用方随后 `account(id:)` 取 ETag） |
| `Accounts/AccountDetailScreen.swift` 代理分区 | 有代理时行 push `ProxyDetailView(id:)`（60 章 §13 新增的视图），“编辑”打开 `AccountProxyPicker`；“已回退”行与确认框 |

---

## 4. 测试连接

### 4.1 入口与导航

- 详情按钮行“测试连接”；更换 API Key / 重新授权后的回执“测试”；新建账号的“创建并测试”（§7，同一套流程，sheet 样式不同）。
- 呈现：sheet（`.presentationDetents([.large])`），标题“测试连接”，左“关闭”。

### 4.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 可选模型 | `GET /admin/accounts/:id/models` | 默认选中第一个 `id` 含 `sonnet` 的，否则第一个；点模型名可换 |
| 测试（SSE） | `POST /admin/accounts/:id/test`，体 `{"model_id": "…"}`（还可带 `prompt`、`mode`），`Accept: text/event-stream` | 事件 `type`：`test_start`、`status`、`content`（`text`）、`image` / `audio` / `video`、`test_complete`（`success`）、`error`（`error`）；**之后**还有一条 `test_result`（`data` 见下）。`error` 之后流不结束，仍会写 `test_result` |
| 测试结果 | `test_result.data`（`service.AccountTestResult`） | `success`（以 `data.success` 为准，顶层 `success` 失败时缺省）、`started_at`、`first_token_ms`（可 null）、`total_ms`、`upstream_status`（可 null）、`usage {input_tokens, output_tokens}`（可省略）、`account {status, schedulable, rate_limit_reset_at, temp_unschedulable_until, error_summary, error_kind}`（读失败时 null）、`recovery {cleared_error, cleared_rate_limit}`（失败时 null）、`marked {error, rate_limited, temp_unschedulable}` |
| 中断后核对 | `GET /admin/accounts/:id/test-runs/latest` | SSE 结束时后端尽力写一条 `source=manual` 记录；字段 `run_id, account_id, source, status(running|success|failed|interrupted), model, latency_ms, first_token_ms, upstream_status_code, error_kind, error_summary, error_message, response_text, recovery, started_at, finished_at` |
| 异步测试（重新测试用） | `POST /admin/accounts/:id/test-runs {"model_id", "recover_on_success": true}` → 202，`data` 同上视图；轮询 `GET /admin/account-test-runs/:run_id` | 409 `ACCOUNT_TEST_RUNNING`（`metadata.run_id`）、429 `ACCOUNT_TEST_BUSY`；vendor 不开放 |

### 4.3 字段 → 显示映射

| 界面元素 | 来源 | 格式与文案 |
|---|---|---|
| 目标行 | 账号名 | 副文案“测试会向上游发送一次真实请求，可能产生少量费用” |
| 输出区（等宽） | `→ 测试 {平台} · {name}`、`→ 模型 {model}`，之后 `content` / `status` 事件文本逐行追加 | 每行经脱敏（现有 `sanitizedTestOutput`：Bearer、`sk-…`、URL 替换为“[已隐藏]”），最多 500 行 |
| 通过结果 | `test_result.data.success == true` | “测试通过 · 首字 {first_token_ms/1000}s · 总耗时 {total_ms/1000}s”；`first_token_ms` 为 null 不写首字；无 C07 时用本机计时并加“本机计时” |
| 通过后的恢复说明 | `recovery.cleared_error` / `cleared_rate_limit` + `account.schedulable` | 清了且开关开：“已自动清除{错误/限流}，账号恢复调度”；清了且开关关：“已自动清除{…}，仍暂停调度”+ 右侧按钮“启用调度”；都没清不写 |
| 失败结果 | `data.success == false` | “测试未通过 · {upstream_status}”（null 时不写码）；副文案：`marked.error` 或测试后 `account.status == error` 且属凭据类（`account.error_kind ∈ {auth, forbidden, token_refresh}` 或码 401/403）→ 令牌账号“令牌无效，账号保持错误。重新授权后再测试连接”、密钥账号“凭据无效，账号保持错误。更换 API Key 后再测试连接”；`marked.rate_limited` →“测试触发了上游限流，账号进入限流中”；`marked.temp_unschedulable` →“测试触发了临时不可调度”；否则“账号状态没有改变，可以稍后重试” |
| Token 用量 | `usage` | 有时在通过结果下写“输入 N · 输出 M tokens” |

### 4.4 交互与写操作

- 打开即开始测试（与设计一致，无“开始”按钮）；结束后可点模型名换模型再测。
- 结果里的“启用调度”→ `POST :id/schedulable {true}`（§5），回执带撤销，关闭 sheet。
- 测试结束（收到 `test_result` 或流结束）后：用 `test_result.data.account` 更新详情的状态字段，并 `GET :id` 刷新全量与 ETag。
- 进行中点“关闭”：**不取消**——测试作为 AppModel 持有的任务继续跑，sheet 关闭；完成后回执“「{name}」测试通过 / 未通过”+“查看”。App 进入后台时申请 `beginBackgroundTask`；流在收到 `test_result` 之前断开 → `GET test-runs/latest`（`started_at` 不早于本次开始时间；开始时间按 ServerTime 记，0.6）：`success` / `failed` 按结果回执；`interrupted` 或查不到 → 回执“测试被中断，不能判定是否成功”+“重新测试”。
- “重新测试”（中断后、或用户从回执点）：有 `accounts.test_runs` 走 `POST test-runs`（离开也会跑完），前台每 3 秒轮询 `GET /admin/account-test-runs/:run_id` 直到非 `running`；无能力走 SSE。

### 4.5 状态

| 状态 | 表现 |
|---|---|
| 模型加载中 / 失败 | 失败时用平台默认模型（`claude-sonnet-4-5` 等内置表）并照常测试 |
| 流打开失败（4xx/5xx） | 结果区“测试没有开始：{原因}”；403 `STEP_UP_REQUIRED` 走通用 step-up 后用户手动重试 |
| 只收到 `test_complete` 没有 `test_result`（老服务端） | 以 `test_complete.success` 判断，按 C07 退路比对 |
| 流异常结束 | 见 4.4 |

### 4.6 刷新策略

无轮询（SSE 推送）；异步测试前台每 3 秒轮询，后台停止，回前台补一次。

### 4.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `Sources/Sub2Core/SSEParser.swift` : `AccountTestEvent` / `AccountSSEParser` | `isTerminal` 不能再停在 `test_complete` / `error`：有 `accounts.test_result` 时终止事件改为 `test_result`（或 EOF）；`AccountTestEvent` 增 `data`（解码 `AccountTestResult`）、`model`、`status` |
| `Sources/Sub2Core/APIClient.swift` : `testAccount(id:model:)` | 读到 `test_result` 或 EOF 才结束；体保留 `model_id`，可选 `prompt` / `mode` |
| `NativeApp/Features/AccountsView.swift` : `AccountTestView` | 替换为 `Accounts/AccountTestSheet.swift`（模型选择、结果解读、关闭不取消）；脱敏函数 `sanitizedTestOutput` 复用 |
| 新增 `Sources/Sub2Core/AccountTestRuns.swift` | `startTestRun`、`latestTestRun`、`testRun(runID:)` |
| `NativeApp/Session/AppModel.swift` | 持有后台测试任务表（账号 id → 任务），供回执与“查看”使用 |

---

## 5. 恢复状态 / 启用调度 / 停止调度 / 启用账号

### 5.1 入口与导航

详情按钮行；列表行右滑（启停调度）；概览待处理（另章复用本节动作）。都是确认框或直接执行 + 回执，不进新页面。

### 5.2 数据来源

| 动作 | 请求 | 说明 |
|---|---|---|
| 停止 / 启用调度 | `POST /admin/accounts/:id/schedulable {"schedulable": bool}` | 返回账号对象；有 `admin.idempotent_writes` 时带 `Idempotency-Key`（新 UUID） |
| 恢复状态 | `POST /admin/accounts/:id/recover-state`，可选体 `{"schedulable": true|false}` | 不带体：清错误、限流、过载、临时不可调度、模型限流并让 OAuth 令牌缓存失效，不改开关；`true`：恢复成功后再启用调度；`false`：先暂停再恢复。体格式错误返回 400 且不做任何写。返回账号对象 |
| 启用账号 | `PATCH /admin/accounts/:id {"status":"active"}` + `If-Match` | 退路 `PUT :id {"status":"active"}` |

### 5.3 字段 → 显示映射

确认框（`confirmRecover`）：

| 条件 | 标题 | 正文 | 按钮 |
|---|---|---|---|
| 开关已关（错误账号，或手动停调度的限时账号） | 恢复「{name}」？ | 错误：“清除错误状态。出错时账号已被停止调度，恢复后仍是暂停，除非同时启用调度。”；限时：“清除{限流/过载/临时不可调度}[和 N 项模型限流]。这个账号已停止调度，恢复后仍是暂停，除非同时启用调度。” | 恢复并启用调度 · 只恢复状态（保持暂停）· 取消 |
| 开关开着 | 恢复「{name}」？ | “清除{…}[和 N 项模型限流]，账号立即参与调度。” | 恢复状态 · 取消 |

回执：

| 动作 | 回执 | 附加按钮 |
|---|---|---|
| 恢复并启用调度 / 恢复状态（开关开） | 已恢复 · 参与调度 | — |
| 只恢复状态 | 已恢复 · 仍暂停调度 | 启用调度 |
| 停止调度 | 已停止调度 | 撤销 |
| 启用调度 | 已启用调度 | 撤销 |
| 启用账号 | 已启用账号「{name}」 | 撤销 |

### 5.4 交互与写操作

- “恢复并启用调度”：有 `accounts.recover_schedulable` → `recover-state {"schedulable":true}`；没有 → `recover-state`（无体）成功后再 `POST :id/schedulable {true}`，第二步失败时回执“已恢复 · 仍暂停调度”+“启用调度”。500 `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED` → `GET :id`，以 `schedulable` 为准。
- “只恢复状态”/“恢复状态”：`recover-state` 不带体。
- 恢复不可撤销（不给撤销）。停 / 启调度与启用账号给撤销（反向再调一次）。
- 停止调度只拨开关：正常账号显示为暂停；限时账号保持状态与倒计时，加“已停止调度”。
- 凭据类错误时“恢复状态”仍可用（次要按钮），恢复后下一次请求可能再次出错——不额外提示（设计已把修复动作放主按钮）。

### 5.5 状态

写请求进行中，按钮行对应按钮显示进度、整行禁用；失败回执“{动作}没有成功：{原因}”。结果不明（超时 / 断开）：`:id/schedulable` 有 `admin.idempotent_writes` 时带 key，按 00 §2.5.4（同 key 自动重试、仍不明转“待核对”）；没有该能力时，以及 `recover-state`、启用账号的 PATCH（都不带 key），按 00 §2.4 不自动重试。核对方法（本章定义，00 §2.5.5“其余”）：`GET :id`，停 / 启调度看 `schedulable` 是否等于目标值；恢复看 `status != error` 且限流 / 过载 / 临时不可调度时间都已过去；启用账号看 `status == active`。核对后再给回执。

### 5.6 刷新策略

成功后用返回账号替换；列表完整刷新一次；概览待处理下次刷新自然更新。

### 5.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `APIClient.swift` : `setSchedulable(id:enabled:)` | 可选 `Idempotency-Key` |
| 新增 `Sources/Sub2Core/AccountRecovery.swift` | `recoverAccountState(id:schedulable: Bool?)`（`nil` 不带体） |
| `AccountsView.swift` : `AccountDetailView.mutate` | 删除；动作移到 `AccountActions`（详情、列表、概览共用，含回执与撤销） |

---

## 6. 凭据：更换 API Key、Base URL、刷新令牌、重新授权

### 6.1 入口与导航

- 更换 API Key：凭据区 API Key 行“更换”；⋯“更换 API Key…”；凭据类错误时状态卡主按钮。→ sheet“更换 API Key”。
- Base URL：凭据区“修改”→ sheet“Base URL”。
- 刷新令牌：凭据区动作行、⋯ 菜单，直接执行。
- 重新授权：凭据区动作行、⋯ 菜单、状态卡主按钮 → sheet“重新授权”（tall）。停用账号先弹确认（见 6.4）。

### 6.2 数据来源

| 动作 | 请求 |
|---|---|
| 更换 API Key | `PATCH :id {"credentials_patch":{"api_key":"<新值>"}}` + `If-Match`；退路：`GET :id` 整份 `credentials` 替换 `api_key` 后整份 `PUT`（附录 A S31） |
| Base URL | `PATCH :id {"credentials_patch":{"base_url":"<url>"}}`；改回官方地址发 `{"base_url": null}` |
| 刷新令牌 | `POST /admin/accounts/:id/refresh`（可带 `Idempotency-Key`）→ 账号对象，或 `{account, message, warning:"missing_project_id_temporary"}` |
| 生成授权链接 | Anthropic OAuth：`POST /admin/accounts/generate-auth-url {proxy_id}`；Anthropic Setup Token：`POST /admin/accounts/generate-setup-token-url {proxy_id}`；OpenAI：`POST /admin/openai/generate-auth-url {proxy_id, redirect_uri?}`；Gemini：`POST /admin/gemini/oauth/auth-url {proxy_id, project_id?, oauth_type, tier_id?}`（`oauth_type` 取账号 `credentials.oauth_type`）；Antigravity：`POST /admin/antigravity/oauth/auth-url {proxy_id}`；Grok：`POST /admin/grok/oauth/auth-url {account_id, proxy_id}`。返回 `{auth_url, session_id[, state]}`（Gemini / Antigravity / Grok 带 `state`）。`proxy_id` 一律传账号自己的 `proxy_id`（没有代理不传） |
| 一步重新授权 | `POST /admin/accounts/:id/reauthorize {session_id, code, state?, redirect_uri?, proxy_id?, auth_kind?, oauth_type?, tier_id?, preserve_status?}`（`ReauthorizeAccountRequest`，`account_reauthorize.go:36-46`）：`auth_kind` 仅 Claude（`oauth|setup-token`，缺省取账号现有 type）；`oauth_type` / `tier_id` 仅 Gemini；返回账号对象（不含令牌）。令牌只在服务端流转 |
| 退路（无 `accounts.reauthorize`） | 各平台 `exchange-code`（Claude：`/admin/accounts/exchange-code` 或 `exchange-setup-token-code {session_id, code, proxy_id}`；OpenAI：`/admin/openai/exchange-code {session_id, code, state, redirect_uri?, proxy_id}`；Gemini：`/admin/gemini/oauth/exchange-code {session_id, state, code, proxy_id, oauth_type, tier_id}`；Antigravity：`/admin/antigravity/oauth/exchange-code {session_id, state, code, proxy_id}`；Grok：`/admin/grok/oauth/exchange-code {account_id, session_id, code, state, redirect_uri?, proxy_id}`）→ 按 Web composables（`useAccountOAuth.ts` 等的 `buildCredentials` / `buildExtraInfo`）构造 → `POST /admin/accounts/:id/apply-oauth-credentials {type, credentials, extra}`。令牌只在内存里保留到 apply 成功，apply 失败用同一份令牌重试，不重新换码 |

### 6.3 字段 → 显示映射

**更换 API Key sheet**：目标行“{name} · 点按底部按钮后立即生效”；安全输入框“粘贴新的 API Key”（右侧“粘贴”用 `PasteButton`，不触发剪贴板授权弹窗）；粘贴后显示“新密钥 {前缀}••••{末 4 位} · {N} 个字符”（前缀识别 `sk-ant-api03-`、`sk-proj-`、`sk-`、`AIza`、`xai-`、`AKIA`）；未粘贴写“当前密钥已设置，不可查看”；红色按钮“更换 API Key”；按钮下“站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销[。点按后验证 Face ID]”。

**Base URL sheet**：输入框（url 键盘）“留空使用官方地址”+“清空”；校验 `^https?://[^\s/]+`，不过时“地址要以 http:// 或 https:// 开头”；按钮“保存 Base URL”/“改回官方地址”（未改动置灰）。`platform == antigravity && type == apikey`（对接上游）Base URL 必填：不提供“改回官方地址”。

**重新授权 sheet**：

| 元素 | 内容 |
|---|---|
| 目标行 | {name} · 有代理：“授权走已保存的代理 {代理名}；分组、并发和代理设置不变”；无代理：“账号没有代理，授权页直连打开” |
| 第 1 步 授权链接 | Claude 账号先选授权方式（分段 OAuth / Setup Token，按账号 type 预选；说明“完整权限”/“只授予推理权限”；改选另一种时追加“ · 授权后账号类型改为 {方式}”）；按钮“生成授权链接”→ 显示等宽链接、“复制链接”“打开”（`SFSafariViewController`）；有代理时提示“授权页要从代理 {名} 的出口打开；手机做不到时，复制链接到走同一代理的电脑上打开”；链接 30 分钟内有效，显示剩余时间。改选授权方式会作废已生成的链接和已粘贴的码 |
| 第 2 步 | “登录 {平台} 并授权”+ 说明：显示授权码的平台（Claude、Gemini）“登录要授权的那个账号。授权后页面会显示授权码，复制它。”；回调平台（OpenAI `localhost:1455`、Antigravity `localhost:8085`、Grok `127.0.0.1:56121`）“授权后浏览器跳到 {地址} 的页面（打不开是正常的），拷贝地址栏里的链接。” |
| 第 3 步 | 输入框：授权码 / “回调链接或 Code”；回调平台从粘贴内容里解析 `code` 与 `state` 查询参数，Claude 原样传（含 `#state`，服务端会校验） |
| 提交 | 红色“替换令牌”（未生成链接或未粘贴置灰）；下方说明：“点按后立即保存新令牌[，账号类型改为 X][，并重新启用账号 / ，并清除{错误/限流/…}[和 N 项模型限流]]；调度开关不变。[出错时已停止调度，之后仍暂停。]站点不再使用旧令牌，不能撤回[；之后验证 Face ID]” |

回执（按重新授权前后状态比较）：

| 情况 | 回执 | 附加按钮 |
|---|---|---|
| 原状态正常 | 已重新授权 · 令牌已替换 | 测试 |
| 清除了错误 / 限流且开关开 | 已重新授权 · 已清除{…} · 参与调度 | 测试 |
| 清除了错误 / 限流但开关关（错误账号常见） | 已重新授权 · 已清除{…} · 仍暂停调度 | 启用调度 |
| 原状态停用 | 已重新授权 · 已启用账号 · {参与调度 / 仍暂停调度} | 测试 / 启用调度 |
| 改了方式 | 前缀“已重新授权 · 账号类型改为 {方式}” | 同上 |

刷新令牌回执：“已刷新令牌 · 新令牌 HH:MM 到期”（`token_status.expires_at`）；`warning == "missing_project_id_temporary"` →“已刷新令牌，project_id 暂未取到（会自动重试）”。

### 6.4 交互与写操作

- 更换 API Key：点红色按钮 → Face ID（打开时）→ PATCH。成功：凭据行变“已更换 · HH:MM”，记“本次已更换”标记，回执“已更换 API Key”+“测试”。不可撤销。
- 重新授权：
  1. 账号 `status == inactive` 时先确认：标题“重新授权「{name}」？”，正文“这个账号现在是停用状态。授权后账号会被重新启用{并参与调度 / ，调度仍暂停}。”，按钮“继续授权”/“取消”（DECISIONS 第 113 行；因此 `preserve_status` 不传，保持后端默认重新启用）。
  2. 生成链接（6.2）→ 浏览器授权 → 粘贴 → “替换令牌”→ Face ID（打开时）→ `reauthorize`。
  3. `REAUTH_PERSIST_FAILED`：按 0.5 先读回核对；未保存时给“重试保存”（同一 `session_id`，不重新换码，不自动重试）。
  4. 成功：用返回账号替换，ETag 失效（下次 PATCH 前补 `GET :id`）。
- 刷新令牌：直接执行（不可撤销，无确认），失败回执“刷新令牌没有成功：{原因}”。结果不明：有 `admin.idempotent_writes` 时带 key，按 00 §2.5.4；没有时按 00 §2.4 不自动重试，`GET :id` 看 `token_status.refreshed_at` 是否晚于发起时间（ServerTime）。

### 6.5 状态

| 状态 | 表现 |
|---|---|
| 生成链接中 / 换码中 | 按钮内进度，sheet 不可下滑关闭 |
| 链接超过 30 分钟（本地计时） | 第 1 步变“授权链接已过期”+“重新生成链接”（不等服务端报错） |
| 换码 / 保存错误 | 0.5 各 reason；错误显示在对应步骤下，红字 + 补救按钮 |
| 结果不明（超时） | 重新授权不接受 Idempotency-Key，按 00 §2.4 不自动重试。`GET :id` 看 `token_status.refreshed_at` 是否晚于发起时间（ServerTime）：是 → 视为成功；否 → “不能确认是否已替换”+“重试”（用户点按；同一 `session_id` 在 5 分钟内重放是安全的：已保存的会直接返回账号） |

### 6.6 刷新策略

无轮询；成功后详情 `GET :id`。

### 6.7 对现有代码的改动点

新增 `Sources/Sub2Core/AccountOAuth.swift`（各平台 auth-url / exchange-code、`reauthorize`、`applyOAuthCredentials`、错误 reason 解码）；新增 `NativeApp/Features/Accounts/OAuthFlow.swift`（三步清单 + 回调解析 + 可选本机监听，§7 共用）、`AccountCredentialSheets.swift`（Key / Base URL / 重新授权）。现有 `refreshManagedAccount` 改为解码返回的账号对象与 `warning`。

---

## 7. 新建账号

### 7.1 入口与导航

- 账号页右上“＋”。全高 sheet（`NavigationStack { Form }`），隐藏 Tab 栏；左“取消”；标题“新建账号”，副标题“{站点} · 还差 N 项 / 必填已填齐”（创建后为“{站点} · #{id} 已创建 · {暂停调度 / 错误（已停止调度）/ 调度状态待核对}”）。
- 分区顺序：平台与认证方式 → 凭据（随方式变化；OAuth 是三步清单）→ 名称 → 分组（胶囊）→ 调度 → 网络 → 更多（折叠）。
- 底部玻璃坞（`.safeAreaInset(edge: .bottom)`）：没填齐时“还差 {项目…}”，点按滚到第一项（`ScrollViewReader.scrollTo`）；填齐后“可以创建了 · 创建后立即停止调度，测试通过再启用”+ 按钮“创建并测试”。失败后改为“保存并重新测试”（有改动）/“重新测试”（无改动）。
- 测试在 sheet（`.large`，进行中 `.interactiveDismissDisabled`）里：进度四行 → 结果 → 折叠的测试输出。
- 去向：完成 → 关闭表单，列表回执“已创建「{name}」· 参与调度”+“查看”（→ 账号详情）。

### 7.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 平台与方式 | `GET /admin/meta/catalog` | `platform_catalog.platforms`（展示顺序、`display_name`、`cn_provider`、`multi_protocol {default_mode, modes[{mode, base_urls, protocol_rules}]}`）；`platform_auth`（当前身份可新建的平台 → 认证方式，已按 vendor 裁剪）。无能力 / 423 时用内置清单 |
| 分组 | `GET /admin/groups/all` | 只含启用分组，按 `sort_order`；过滤：本平台 + `composite`（Antigravity 打开“在 /v1/messages 中使用”时再加 `anthropic`、`gemini`） |
| 代理 | `GET /admin/proxies/all?with_count=true` | 只含启用代理 |
| 名称建议 | `status-summary.platforms[].total`（没有时用列表计数） | “{短名}-{NN}”，NN = 该平台现有账号数 + 1，两位补零 |
| 混合渠道 | `POST /admin/accounts/check-mixed-channel {platform, group_ids}` | 选中分组时（Anthropic / Antigravity）逐个预检，用于胶囊风险标记；提交时以 409 为准 |
| OAuth | 6.2 各平台 `auth-url` / `exchange-code` | 新建流程不能用 `reauthorize`（还没有账号）；不用 OpenAI / Grok 的 `create-from-oauth`（不支持 `schedulable=false`） |
| 创建 | `POST /admin/accounts` + `Idempotency-Key` | 体 `CreateAccountRequest`（`account_handler.go:145-166`）：`name`、`notes?`、`platform`、`type`、`credentials`、`extra?`、`proxy_id?`、`concurrency`、`priority`、`rate_multiplier?`、`load_factor?`、`group_ids`、`expires_at?`、`auto_pause_on_expired?`、`upstream_billing_probe_enabled?`、`confirm_mixed_channel_risk?`、**`schedulable: false`**、`skip_default_group_bind?` |
| 测试 | §4 | — |
| 失败后保存修改 | `PATCH /admin/accounts/:id`（平台不可改；`type` 可改，切换前确认） | 需要 ETag：创建成功后 `GET :id` 取一次 |
| 测试通过启用 | `POST /admin/accounts/:id/schedulable {true}` | — |
| 处理未通过 | 保存为停用：`PATCH {status:"inactive"}`；删除：`DELETE /admin/accounts/:id` | — |

凭据构造（以 Web `frontend/src/components/account/CreateAccountModal.vue` 提交逻辑为准，主要键已在后端核实）：

| 方式 | `type` | `credentials` 主要键 |
|---|---|---|
| API Key（通用） | `apikey` | `api_key`、`base_url`（留空时填平台官方地址：OpenAI `https://api.openai.com`、Gemini `https://generativelanguage.googleapis.com`、Grok `https://api.x.ai/v1`、TypeSafe `https://api.typesafe.ai`，其余 `https://api.anthropic.com`） |
| 多协议 API Key 平台 | `apikey` | 另加 `account_mode`（所选模式）、`api_protocol`（`adaptive` 或具体协议）；`adaptive` 时 `api_base_urls`（各协议端点）且 `base_url` = 其中 `chat_completions`；具体协议时 `base_url` = 所选端点（预设或自定义） |
| Antigravity 对接上游 | `apikey` | `base_url`、`api_key` |
| AWS Bedrock | `bedrock` | `auth_mode`（`sigv4` / `apikey`）、`aws_region`（缺省 `us-east-1`）；sigv4：`aws_access_key_id`、`aws_secret_access_key`、`aws_session_token?`；apikey：`api_key` |
| Vertex（Service Account） | `service_account` | `service_account_json`（文件原文）、`project_id`、`client_email`（从 JSON 读出）、`location`、`tier_id: "vertex"` |
| OAuth / Setup Token | `oauth` / `setup-token` | 由 `exchange-code` 返回的令牌信息按 Web composables 的 `buildCredentials` 构造，`extra` 按 `buildExtraInfo`（Claude：`org_uuid`、`account_uuid`、`email_address`） |

Antigravity 的“在 /v1/messages 中使用”= `extra.mixed_scheduling`；“允许超量请求（AI Credits）”= `extra.allow_overages`（后端 `service/account.go:2042,2058` 读取）。

### 7.3 字段 → 显示映射

| 分区 | 元素 | 来源 / 规则 | 文案 |
|---|---|---|---|
| 平台与认证方式 | 平台下拉 | 目录平台按“常用（anthropic、openai、gemini、antigravity、grok）/ 国内厂商（`cn_provider`）/ 更多”分组；只列 `platform_auth` 里有的 | 未选“选择平台”；创建后锁定“已创建，不能更换”+ 锁图标，脚注“要换平台请删除后重建。…” |
| 同上 | 认证方式单选行 | `platform_auth[pid]` 映射为设计行：anthropic → Claude Code（OAuth / Setup Token）· Claude Console（API Key）· AWS Bedrock · Vertex；openai → ChatGPT OAuth · API Key；gemini → Google OAuth（Google One / Code Assist）· AI Studio（API Key）· Vertex；antigravity → Antigravity OAuth · 对接上游；grok → Grok OAuth · API Key；多协议平台 → 每个 `mode` 一行（按量付费 / Coding Plan / Zen / GO，均为 API Key）；其他 → API Key | 每行标题 + 副文案（如“浏览器授权”“粘贴 sk-ant-api03- 开头的 Key”） |
| 凭据 | 随方式 | API Key：安全输入 + 粘贴 + Base URL；多协议：“接入”分区（API 协议、官方端点 / 端点选择、自定义端点）；Bedrock：认证方式分段 + 字段 + Region 选择；Vertex：“从“文件”选择 JSON”（`fileImporter`），显示文件名与 `project_id`；对接上游：上游 Base URL + Key；OAuth：见下 | 脚注“Key 只提交到站点，App 不保存。” |
| 凭据 · OAuth | 三步清单（`anOauth: 'list'`） | ① 生成授权链接（30 分钟内有效，倒计时）② 在浏览器里登录 {Claude/ChatGPT/Google/xAI} 并授权 ③ 粘贴授权码 / 完成授权；Claude 先选“添加方式”OAuth / Setup Token；Gemini 先选“授权类型”Google One / Code Assist（Code Assist 需填 GCP Project ID） | 已完成写“已授权 · {邮箱}” |
| 名称 | 名称、备注 | 自动起名（可改，改后不再自动） | 必填；脚注“按平台自动起名，可以改。” |
| 分组 | 胶囊 | 7.2 过滤；选中带勾 + 强调色；预检有风险时胶囊加铃铛标记，脚注“「{分组}」里已有 {平台} 账号，创建时要确认混合渠道风险。” | 右上“已选 N[ · K 个需确认]”/“可不选”；没有可选分组“没有可选的 {平台} 分组，不分组也能创建。”；不选分组时脚注加“不选分组时，如果站点有「{平台 id}-default」分组会自动加入” |
| 调度 | 并发数（默认 10，1–100）、优先级（默认 1，1–99，“数值越小越优先”）、账号计费倍率（默认 1，“0 表示不计费，只影响账号计费”） | — | — |
| 网络 | 代理 | 选择 sheet 同 §3 | 无代理写“无代理” |
| 更多 | 过期时间、过期自动暂停调度、负载因子（1–10，可空）、Antigravity 的 AI Credits | 折叠，未展开时右侧写“不过期 / {日期} 到期” | 展开后脚注“模型白名单与映射、自定义错误码、配额等，创建后在账号详情里设置。” |
| 坞 | 还差清单 | 顺序：平台 → 认证方式 / 账号类型 → 凭据（“授权”“API Key”“AWS 凭据”“JSON 文件”“上游地址和 Key”“自定义端点”）→ 名称 → 计费倍率 | 标题副行的“还差 N 项”数同一份清单 |

测试 sheet（`AnTest`）：

| 元素 | 内容 |
|---|---|
| 进度四行 | 创建账号（完成写 `#id`）· 停止调度（C01 生效时随创建一起完成，写“不接收请求”；需要单独停调度时显示进行中 / 失败“没有确认”）· 测试连接（右侧写模型名，结束后可点换模型重测）· 启用调度（通过“参与调度”，失败“未启用”）。重试时第一行改为“保存修改”（无改动写“没有改动”） |
| 通过 | “测试通过 · 已启用调度”，副文案“[错误状态已自动清除。]首字 Xs · 总耗时 Ys”（无 C07 时加“本机计时”）；按钮“查看账号”“完成” |
| 失败 | “测试未通过 · {原因}”，等宽原文“上游返回 {upstream_status} · {SSE error 事件文本（脱敏）}”；`marked.error` 或测试后 `account.status == error` →“后端已把账号 #{id} 标为“错误”，并停止调度，不会接收请求。”，否则“账号 #{id} 已停止调度，不会接收请求。”；按钮“修改凭据后重试”（主）、“保留（错误状态）/ 保留，暂停调度”、“保存为停用”；最后一个次要红字按钮“删除账号…”（DECISIONS 第 114 行的例外，仍需输入名称或 Face ID） |
| 停调度失败 | “停止调度没有确认 · 结果待核对”，“账号 #{id} 已创建，可能正在参与调度。凭据还没验证，可能已经在接收请求。重试一次停止调度，成功后自动开始测试。”；按钮“重试停止调度”、“删除账号…” |
| 测试输出 | 进行中展开流式；结束后折叠成一行（显示最后一行与行数） |

原因映射（失败标题里的“{原因}”）：`account.error_kind`（或 `upstream_status`）→ `auth`/401：密钥“API Key 无效或已撤销”、令牌“令牌无效或已撤销”；`forbidden`/403：OAuth“授权的账号没有可用额度或权限”、Vertex“Service Account 没有 Vertex AI 权限”、Bedrock“AWS 凭据无效或没有 Bedrock 权限”；`quota`“上游额度不足”；`rate_limit`/429“上游限流”；其他“上游返回 {code}”；都没有时“上游拒绝了这次测试请求”。

### 7.4 交互与写操作

1. **创建并测试**：
   - 混合渠道：Anthropic / Antigravity 且选了分组 → 有 `accounts.mixed_channel_details` 直接提交、按 409 弹框；否则先 `check-mixed-channel`。弹框“返回修改分组”滚到分组区；“继续创建”后同一流程内对同一组分组不再询问，请求带 `confirm_mixed_channel_risk: true` 并**换新 Idempotency-Key**。
   - `POST /admin/accounts`（`schedulable: false`）。响应 `data.schedulable == true`（老服务端忽略参数）→ 立即 `POST :id/schedulable {false}`；失败进入“停止调度没有确认”。
   - `GET :id` 取 ETag → 测试（§4，SSE）。
   - 通过（`data.success`）→ `POST :id/schedulable {true}` → “测试通过 · 已启用调度”。启用失败 → “测试通过 · 启用调度没有成功”+“重试启用”。
   - 未通过 → 账号留在暂停或错误（看 `marked.error` / `account.status`）。
2. **修改凭据后重试**：关闭测试 sheet 回到表单，顶部 critical 横幅“测试未通过 · #{id} 已创建 / 已标为错误”+“处理”；凭据区上方说明“账号 #{id} 已创建，暂停调度中 / 已被标为错误（已停止调度）；这里的修改会在“保存并重新测试”时保存到它[，测试通过后错误自动清除]”。坞按钮“保存并重新测试”→ `PATCH :id`（改过的字段；凭据走 `credentials_patch`）→ 测试；无改动“重新测试”直接测试。改认证方式需确认“改成「X」？账号 #{id} 已创建。换认证方式后要重新授权 / 填写凭据，保存时替换原来的凭据。”
3. **处理（横幅 / 取消）**：确认框“账号「{name}」已创建，怎么处理？”，正文说明当前状态；按钮“保存为停用”（`PATCH {status:"inactive"}`，回执“已保存「{name}」为停用 · 不参与调度”+“查看”）、“保留，暂停调度 / 保留（错误状态）”（不发请求，回执带“查看”）、“删除账号…”（红）、“继续修改”。
4. **取消**：未选平台直接关闭；已填写 →“放弃新建账号？已填写的内容（和授权结果）不会保存。”；测试进行中 → 转后台（4.4 规则：任务由 AppModel 持有），回执“「{name}」在后台继续测试，完成后通知你”；通过后回执“测试通过 · 已启用调度”+“查看”（启用调度由后台任务完成），未通过回执“测试未通过 · {已标为错误（已停止调度）/ 仍暂停调度}”+“处理”（→ 账号详情）。
5. **换平台**：已填凭据时确认“换成 {平台}？已填写的{授权 / 凭据}[和选好的分组]会清空，名称、调度和代理保留。”；已授权后换 OAuth / Setup Token 或 Google One / Code Assist 同样确认“切换会丢弃当前授权，需要重新在浏览器里授权。”。Antigravity 关掉“在 /v1/messages 中使用”时移除不再适用的分组，回执“已移除 N 个不再适用的分组”+ 撤销。
6. **OAuth（三步清单）**：
   - 生成链接（6.2，`proxy_id` = 网络区所选代理）。链接 30 分钟倒计时。
   - 打开：`SFSafariViewController`。回调平台（OpenAI 1455、Antigravity 8085、Grok 56121）在 Safari sheet 显示期间用 `Network.framework` `NWListener` 监听本机端口，接到带 `code` 与 `state` 的请求后回一页“已交给 App”、关闭 Safari、自动换码；监听失败（端口被占）退回粘贴（用户在 Safari 错误页“分享 → 拷贝”后回来粘贴）。显示授权码的平台（Claude、Gemini）用粘贴。
   - 完成授权：调对应 `exchange-code`（带当前所选代理，`exchange-code` 的 `proxy_id` 优先于会话里的代理，换代理不重置进度）。失败按 0.5：会话过期 / 拒码 → “重新生成链接”；代理类 502 → “换个代理再试”（选代理后直接重新兑换，不消耗授权码）；浏览器回调带 `error=access_denied` → “你在浏览器里拒绝了授权”+“重新打开链接”。
   - 换到的令牌只在内存；离开表单即丢弃。

### 7.5 状态

| 状态 | 表现 |
|---|---|
| 目录 / 分组 / 代理加载失败 | 对应区写“读取失败 · 重试”；目录失败用内置清单；分组失败可不选分组创建 |
| 创建失败（4xx，含 409 非混合渠道） | 测试 sheet 第一行“创建账号”标失败 + 原因；坞恢复“创建并测试” |
| 创建结果不明（超时） | 按 00 §2.5.4（新建账号的 key 没有服务端执行上限、“处理中”多久转待核对，见 00 §2.5.1 那一行）。转“待核对”后的核对方法（本章定义）：`GET /admin/accounts?search={name}&lite=1`，按 `name` 完全相等且 `platform` 相同匹配：找到 → 当作已创建，用它的 id 继续流程；找不到 → “没有创建成功”+“用同一编号重试”（同 key 重发；之后的响应仍按 00 §2.5.3 处理） |
| 测试中 / 后台 | 见 4.4 |

### 7.6 刷新策略

无轮询。表单打开时各拉一次目录、分组、代理；OAuth 倒计时本地每秒走。完成或离开后列表完整刷新。

### 7.7 对现有代码的改动点

现有 App 没有新建账号。新增 `NativeApp/Features/Accounts/AccountNewView.swift`（表单 + 坞 + 测试 sheet，状态机照 `useAnWizard`：`idle → creating → pausing → testing → passed / failed / pauseFailed`，重试 `saving`）、`AccountNewDraft.swift`（草稿、缺项清单、凭据构造）、复用 §6 的 `OAuthFlow.swift`；`Sources/Sub2Core/AccountCreate.swift`（`createAccount(_:idempotencyKey:)`）、`MetaCatalog.swift`（`metaCatalog()` + 内置兜底清单）。账号列表 `AccountListModel` 提供“新建成功后完整刷新”。

---

## 8. 批量操作

### 8.1 入口与导航

账号列表左上“选择”→ 选择模式：行首勾选圈、组头“全选 / 取消全选”、Tab 栏隐藏、底部玻璃操作坞；“完成”退出并清空选择。

### 8.2 数据来源

| 动作 | 请求 | 响应 |
|---|---|---|
| 停止 / 启用调度 | `POST /admin/accounts/bulk-update {"account_ids":[…], "schedulable": bool}`（有 `admin.idempotent_writes` 时带 `Idempotency-Key`，每批一个 key） | `{success, failed, success_ids, failed_ids, results[{account_id, success, error?}]}` |

每次请求最多 50 个账号，超过时分批顺序提交、结果合并（后端不限，App 自限，沿用现有 `setAccountsSchedulable` 的校验）。执行上限与客户端超时见 00 §2.3、§2.5.1。

### 8.3 字段 → 显示映射

| 元素 | 内容 |
|---|---|
| 坞左侧 | “已选 N 个” |
| 坞按钮 | 只有“停止调度”、“启用调度”（主）两个，与设计稿 `VaShell` 的 dock 一致；未选择时都置灰 |
| 结果 sheet（有失败时） | 标题“批量操作结果”，站点名；每个失败账号一行：名称（#id）+ 原因（`error` 原文不显示，按 HTTP 语义归类为“服务器拒绝 / 结果不明”）；“未返回此账号的明确结果，请先刷新核对”用于缺失或重复的结果 |

### 8.4 交互与写操作

- Face ID 打开时，任何批量动作先验证。
- **停止 / 启用调度**：可逆，直接执行。回执“已{停止/启用}调度 N 个账号[ · K 个失败]”+“撤销”（对 `success_ids` 按操作前的 `schedulable` 分两组各发一次 `bulk-update`，撤销是新的用户意图、用新 key）；有失败时附“查看”打开结果 sheet。执行后退出选择模式。
- 所有批量写完成后列表完整刷新。

### 8.5 状态

执行中坞按钮变进度、选择不可改；整体请求失败 → 回执“批量操作没有成功：{原因}”，选择保留。结果不明（超时 / 断开）：带 key 时按 00 §2.5.4（同 key 自动重试、仍不明转“待核对”）；没有 `admin.idempotent_writes` 时按 00 §2.4 不自动重试，回执“结果未确认，请刷新核对后再操作”。核对方法（本章定义，00 §2.5.5“其余”）：对所选 ID 调 `runtime/batch`，`schedulable` 全部等于目标值即成功，不等的列入结果 sheet。

### 8.6 刷新策略

选择模式期间暂停 60 秒轻刷新；退出后恢复并立即完整刷新。

### 8.7 对现有代码的改动点

`AccountsView.swift` 的 `prepareBatch` / `executeBatch` / `outcomeSheet` 迁到 `Accounts/AccountBatchDock.swift`；`setAccountsSchedulable` 加 `Idempotency-Key`；去掉“确认执行”确认框（调度开关改为直接执行 + 撤销）；现有 `AccountBatchAction.refresh`（批量“刷新凭据”）按设计稿去掉，是否保留见未决问题 7。

### 8.8 设计稿之外的扩展（默认不做，见未决问题 7）

设计稿的坞只有两个按钮。下面是“⋯”菜单（“恢复状态…”、“刷新令牌”）的接口与规则，**只在用户看过效果图、决定加上之后才实现**：

| 动作 | 请求 | 响应 |
|---|---|---|
| 恢复状态 | `POST /admin/accounts/batch-clear-error {"account_ids":[…], "preserve_inactive": true}`（不接受 Idempotency-Key） | `{total, success, failed, errors[{account_id, error}] 或 null, skipped_inactive_ids[]}`（`errors` 为 null 时当空数组） |
| 刷新令牌 | `POST /admin/accounts/batch-refresh {"account_ids":[…]}`（有 `admin.idempotent_writes` 时带 `Idempotency-Key`） | `{total, success, failed, errors[{account_id, error}], warnings[{account_id, warning}]}` |

- **恢复状态…**：确认框“恢复 N 个账号？清除错误、限流、过载、临时不可调度和模型限流。[已停用的 M 个账号不会被重新启用。]”按钮“恢复状态”/“取消”。有 `accounts.clear_error_preserve_inactive` 发 `preserve_inactive: true`；没有则本地剔除 `status == inactive` 的账号再发（确认框同样写明）。批量清错误不改调度开关：完成后数出 `status == active && schedulable == false` 的账号 K 个，回执“已恢复 N 个[ · 其中 K 个仍暂停调度]”+“启用调度”（对这 K 个发 `bulk-update schedulable:true`，该回执再给撤销）。不可撤销。结果不明按 00 §2.4（不带 key）读回：`runtime/batch` 看 `status`。
- **刷新令牌**：只提交选中里的令牌账号（其余在确认框里写“N 个非令牌账号跳过”）；确认框“刷新 N 个账号的令牌？”；回执“已刷新 N 个[ · K 个失败]”。结果不明按 00 §2.5.4。
- 代码：新增 `batchClearError(ids:preserveInactive:)`、`batchRefresh(ids:)`（替换现在逐个串行的 `refreshManagedAccount` 循环）。

---

## 9. 定时测试（只读）

已定详情页（inline）没有画定时测试；为 C09 补一行，放在“记录”节最后，只读，计划在 Web 中维护（第 2 轮 `v-detail.jsx` `VdTests` 的文案）。

### 9.1 入口与导航

详情“记录”节“定时测试”行，点 → push“定时测试”小页（最近结果列表）；不提供新建 / 编辑。

### 9.2 数据来源

| 用途 | 请求 |
|---|---|
| 计划 | `GET /admin/accounts/:id/scheduled-test-plans` → `[{id, account_id, model_id, cron_expression, enabled, max_results, auto_recover, last_run_at, next_run_at, …}]` |
| 结果 | `GET /admin/scheduled-test-plans/:id/results?limit=20`（缺省 50）→ `[{id, plan_id, status, response_text, error_message, latency_ms, started_at, finished_at, created_at, upstream_status_code, error_kind}]` |

### 9.3 字段 → 显示映射

| 元素 | 来源 | 格式 | 空值 |
|---|---|---|---|
| 行右侧 | 第一个 `enabled` 计划 + 其最新结果 | “{cron 人话} · {model_id} · 上次{成功/失败}” | 无计划“没有计划 · 在 Web 中添加”；计划都停用“计划已停用” |
| cron 人话 | `cron_expression` | `*/N * * * *` → “每 N 分钟”；`0 */N * * *` → “每 N 小时”；其余原样等宽 | — |
| 结果行 | `started_at`（HH:MM）、`status`、`upstream_status_code`、`latency_ms`、`error_kind` / `error_message` | 成功：“成功 · 1.3s”；失败：状态码徽章（`codeTone`）+ 分类词（auth 凭据无效、forbidden 无权限、quota 额度不足、rate_limit 上游限流、其他写状态码）；不显示 `error_message` 原文 | 无 `upstream_status_code` 时按 0.1 正则从 `error_message` 解析，仍无写“—” |

### 9.4 交互与写操作

无写操作；小页底部“在 Web 中编辑计划”→ 打开 Web 账号深链（§3.4）。

### 9.5 状态

读取失败 → 行右侧“读取失败”，小页内“重试”。vendor 只能看自家账号的计划（别家 404 `ACCOUNT_NOT_FOUND`）。

### 9.6 刷新策略

进入详情时读一次；详情 60 秒轻刷新不含它；小页下拉刷新。

### 9.7 对现有代码的改动点

新增 `Sources/Sub2Core/ScheduledTests.swift` 与 `Accounts/AccountScheduledTestsView.swift`。

---

## 10. 共享数据源：账号状态汇总（D02）与账号排行（C04）

本章只定义接口与解码；概览、分组、监控章节按各自口径使用。

### 10.1 状态汇总 `GET /admin/accounts/status-summary`

- 参数：`platform?`、`group_id?`（正整数，否则 400 `INVALID_GROUP_FILTER`）、`include_accounts?`（布尔）、`default_min_ratio?`。
- 响应：`collected_at`；`totals` / `platforms[]` / `groups[]` 都含 `total, available, error, overloaded, rate_limited, temp_unschedulable, paused, inactive, stopped`；`groups[]` 另有 `group_id, group_name, platform, group_status, shortage {is_short, source(alert_rule|default), rule_id?, metric_type?, operator?, threshold?, current?}`；`include_accounts=true` 时 `accounts[]`：`id, name, platform, group_ids, state(available|error|overloaded|rate_limited|temp_unschedulable|paused|inactive), stopped, status, schedulable, error_message, rate_limit_reset_at, overload_until, temp_unschedulable_until, temp_unschedulable_reason, expires_at（RFC3339）, model_rate_limits[{model, reset_at}]`。
- 不依赖运维监控；服务端 10 秒缓存；不对 vendor 开放（vendor 用本地计数）。
- 本章用：平台组头（1.3）与账号 Tab 徽标（`totals.error`）。`state` 与 0.2 推导一致，可直接互用。

### 10.2 账号排行 `GET /admin/dashboard/accounts-ranking`

- 参数：`start_date` / `end_date`（或 `start_time` / `end_time`，经 `usagequery.ParseRange`）、`timezone`（缺省当天）、`limit`（1–50，缺省 10）、`platform?`、`group_id?`。
- 响应：`ranking[{account_id, account_name, platform, status, requests, tokens, actual_cost, account_cost, standard_cost}]`、`total_actual_cost`、`start_date`、`end_date`、`query`；服务端 30 秒缓存；vendor 不开放。`actual_cost` 与 `today-stats/batch` 的 `user_cost` 同口径。
- 账号 Tab 主模式不使用（已定列表按平台分组，没有“按今日金额”排序）；给概览平静布局“按账号 · 今日实际扣费 · 前 4”和以后的简化模式用。

### 10.3 改动点

新增 `Sources/Sub2Core/AccountStatusSummary.swift`（已在 §1.7 列出）与 `AccountsRanking.swift`。

---

## 11. 本章对通用层的要求（汇总）

| 位置 | 要求 |
|---|---|
| `Sources/Sub2Core/APIError.swift` | 保留 `metadata: [String: String]`；409 混合渠道另解 `details`（`group_id` 为数字）；412 单独可识别；中间件字符串 `code` 兼容解码（附录 B L1） |
| `Sources/Sub2Core/APIClient.swift` : `request` | 增加返回响应头的变体；支持请求头 `If-Match` / `If-None-Match` 与 304（返回 `.notModified`）；`Idempotency-Key` 与 `X-Idempotency-Replayed` |
| 能力表 | AppModel 启动时读 `GET /admin/me` 的 `capabilities`，以 `Set<String>` 提供给本章判断 |
| 回执 | 统一 toast：文字 + 可选“撤销”或一个自定义按钮（读屏念按钮文字） |
| Face ID | 设置“高风险操作需要 Face ID”的统一门控函数 |
| 状态胶囊 | 列表与卡片共用组件，支持相邻连接（DECISIONS 第 138 行） |

---

## 接口核实清单（2026-10-22，sub2 main `70116315d`）

| 接口 | 源码位置 |
|---|---|
| `GET /admin/accounts`、`GET /admin/accounts/:id`、`POST /admin/accounts`、`PUT` / `PATCH` / `DELETE /admin/accounts/:id`、`POST /admin/accounts/check-mixed-channel` | `server/routes/admin.go:461-499`；`handler/admin/account_handler.go:713-1316` |
| `GET /admin/accounts/status-summary` | `admin.go:474`；`account_status_summary_handler.go` |
| `POST /admin/accounts/today-stats/batch`、`GET /admin/accounts/:id/today-stats` | `admin.go:513,515`；`account_handler.go:2756-2858` |
| `POST /admin/accounts/runtime/batch` | `admin.go:516`；`account_runtime_batch.go` |
| `GET /admin/accounts/:id/usage` | `admin.go:512`；`account_handler.go:2621-2650` |
| `POST /admin/accounts/:id/schedulable`、`:id/recover-state`、`:id/clear-error`、`:id/refresh`、`:id/apply-oauth-credentials`、`:id/reauthorize`、`:id/test`、`:id/test-runs`、`GET :id/test-runs/latest`、`GET :id/models` | `admin.go:500-523`；`account_handler.go`、`account_recover_state.go`、`account_clear_error.go`、`account_reauthorize.go`、`account_test_run_handler.go` |
| `GET /admin/account-test-runs/:run_id`、`GET /admin/accounts/:id/scheduled-test-plans`、`GET /admin/scheduled-test-plans/:id/results` | `admin.go:848-858`；`scheduled_test_handler.go` |
| `POST /admin/accounts/bulk-update`、`batch-clear-error`、`batch-refresh` | `admin.go:531-534` |
| `POST /admin/accounts/generate-auth-url`、`generate-setup-token-url`、`exchange-code`、`exchange-setup-token-code`；`/admin/openai/generate-auth-url`、`exchange-code`；`/admin/gemini/oauth/auth-url`、`exchange-code`；`/admin/antigravity/oauth/auth-url`、`exchange-code`；`/admin/grok/oauth/auth-url`、`exchange-code` | `admin.go:543-546,564-620` |
| `GET /admin/meta/catalog` | `admin.go:41`；`meta_handler.go`；`service/admin_meta_catalog.go` |
| `GET /admin/groups/all`、`GET /admin/proxies/all` | `admin.go:404,634` |
| `GET /admin/ops/upstream-errors` | `admin.go:313`；`ops_handler.go:473-571`（`IncludeRecoveredUpstream = true` 在第 504 行）；恢复行的 `status_code` 与 `message` 拼法 `handler/ops_error_logger.go:1296-1355`（`logOpsRecoveredUpstream`） |
| `POST /admin/accounts/:id/revert-proxy-fallback`；账号 DTO `proxy_fallback_origin_id` / `proxy_fallback_origin_name` | `admin.go:511`；`account_handler.go:1814-1827`；`service/admin_account.go:1572-1597`；`service/admin_proxy.go:271-311`；`service/account_service.go:16`；`dto/types.go:239-240,370-371` |
| `GET /admin/ops/alert-events`（`status`、`limit`、`platform`、`group_id`）；事件字段 `silence`、`rule`、`group_name` | `admin.go:256`；`ops_alerts_handler.go:612`；`repository/ops_repo_alerts.go:320-363,890-938`；`service/ops_alert_models.go:41-100` |
| `GET /admin/dashboard/accounts-ranking`、`GET /admin/dashboard/stats` | `admin.go:349,360`；`dashboard_handler.go:437-486` |
| `GET /admin/me` capabilities | `handler/admin/me_handler.go:17-81` |
| Web `/admin/accounts?edit=&search=` | `frontend/src/utils/accountDeepLink.ts` |

---

## 本章未决问题

1. **列表加载上限**：按平台分组需要全部行，本章定为 `page_size=500`、最多加载 2000 行，超出时提示用平台筛选。**建议默认**：2000；实测大站点（>2000 账号）后再决定是否改为“按平台懒加载分区”。
2. **新建 OAuth 账号的令牌经过手机**：新建流程只能 `exchange-code` 拿到令牌后由 App 构造凭据再 `POST /admin/accounts`（`reauthorize` 只能用于已有账号，`create-from-oauth` 不支持 `schedulable=false`）。**建议默认**：照 Web 做，令牌只在内存、不写日志、离开即丢；另请后端评估给 `create-from-oauth` 加 `schedulable` / `skip_default_group_bind`（或新增“换码并新建”接口）后切换。
3. **Bedrock / Vertex 账号的凭据类错误**：设计只画了 API Key 与 OAuth 的修复主按钮，手机端不编辑 AWS 密钥与 Service Account JSON。**建议默认**：这两类账号凭据类错误时主按钮“在 Web 中更换凭据”（打开 C19 深链），“恢复状态”“测试连接”仍为次要。
4. **新建时不选分组是否跳过默认分组**：后端支持 `skip_default_group_bind`，DECISIONS 未定。**建议默认**：与 Web 一致不传（自动加入 `<platform>-default`），表单脚注写明。
5. **重新授权停用账号**：后端已有 `preserve_status`，但 DECISIONS 第 113 行定为“确认框写明会重新启用”。**建议默认**：照决定，不传 `preserve_status`；如需“授权但保持停用”，以后在确认框加第二个按钮。
6. **定时测试是否进入主模式详情**：已定 inline 详情没有画；本章作为“记录”节的只读一行补上。**建议默认**：保留只读行，计划维护留在 Web。
7. **批量“恢复状态 / 刷新令牌”（设计稿之外的扩展）**：已定设计（DECISIONS 第 38 行，`v-accounts.jsx` 与 `00-core.jsx` 的 dock）只有“已选 N 个 · 停止调度 · 启用调度”；现有 App 另有批量“刷新凭据”。**建议默认**：照设计稿只做两个按钮，现有批量“刷新凭据”去掉；要加“⋯”菜单时按 §8.8 实现，先给用户看效果图再定。
8. **运维关闭时状态卡的出错时间行（设计稿之外的退路）**：设计稿只画了来自上游错误日志、可点进请求详情的“最近上游错误 … ›”；运维关闭或 24 小时内无日志时设计稿没有这一行。**建议默认**：有 C02 `error_at` 时显示不可点的“出错于 HH:MM · N 分钟前[ · {error_status_code}]”，没有就不显示；用户看过效果图后可改为直接不显示。
9. **账号详情代理行的点按去向**：设计稿里点代理行和点“编辑”都打开代理选择器；60 章把“账号详情的代理行”列为代理详情的入口。**建议默认**：本章的做法——有代理时点行 push 代理详情，选择器只从分区右上“编辑”进；用户看过效果图再定。

---

## 审查记录

逐条核实后的处理（2026-10-22）：

1. 状态卡上游错误行的状态码（MEDIUM）：属实（恢复行 `status_code` 是客户端最终码，见 `ops_error_logger.go:1296-1355`）。已改 §2.3：按 40 章 §6.3 的取法，`≥ 400` 直接用，否则解析 `Recovered upstream error (\d{3})`，`account_auth` 写“鉴权”，都没有就不写状态码段；取法与 40 章 `LogRow` 共用（§2.7）。
2. 批量操作坞多了“⋯”菜单（LOW）：属实。坞改回设计稿的两个按钮（§8.3）；恢复状态 / 刷新令牌移到 §8.8“设计稿之外的扩展”，列为未决问题 7。
3. 出错时间行改了文案和去向（LOW）：属实。恢复设计稿的“最近上游错误 … ›”与落点（那一条的请求详情，40 章 `.error(id, kind: upstream)`）；运维关闭时用 `error_at` 的不可点退路列为未决问题 8。
4. 幂等与重试参数各章不一（MEDIUM）：本章部分属实。已删掉本章自定的 `IDEMPOTENCY_*` 处理与数值（含 `KEY_CONFLICT` 换新 key 自动重发），改为引用 00 §2.3–§2.5；`REAUTH_PERSIST_FAILED` 的自动重试改为读回核对 + 用户点按“重试保存”；各“结果不明”行改为按是否带 key 引用 00 §2.4 / §2.5.4，并给出读回方法；`ACCOUNT_TEST_BUSY` 改用 00 §2.7.2 的文案与规则。其他章（00、30、50、60）的写法与 00 §2.4 的白名单例外不在本文件内，未改。
5. 时间基准与时区不统一（MEDIUM）：本章部分属实。新增 §0.6：`now` 一律 ServerTime，绝对时间按服务器时区显示，时区提示只用 00 §6.3 那一句；0.2 的“设备时钟”与过期时间的“设备时区”已改（选择器用服务器时区，`DatePicker` 设 `\.timeZone`），不需要 00 另列例外。30 / 60 章的写法不在本文件内，未改。
6. 缺“恢复原代理”、代理行去向不一致（MEDIUM）：属实。§3.2 / §3.3 / §3.4 加了“已回退”行与 `POST :id/revert-proxy-fallback`（先确认、不给撤销并写明理由、错误 reason、超时读回）；代理行改为有代理时 push 代理详情、“编辑”打开选择器，与 60 章一致，与设计稿的差异列为未决问题 9。
7. 组头告警牌依赖 10 章不存在的“处置 sheet”（LOW）：属实。“告警”sheet 本来就是账号页设计稿（`v-accounts.jsx` `useVaAlert`）的内容，已在 §1.4 由本章定义，动作调 10 章 §7.1 `AlertActions`、链接进告警详情；数据由账号列表在 Tab 可见时拉 `alert-events?status=firing&limit=100` 并写进 `LiveOpsStore`（§1.2、§1.6）。建议在 10 章 §0.5 补一句“账号 Tab 也会触发这份列表刷新”，不在本文件内，未改。
