# 02 · Sub2API 后端与 Web 端全量能力盘点（面向“未来功能”）

> 调研日期：2026-10-16。本次只读，未修改任何源码。
> 标注约定：**【事实】** 表示可以直接在源码中核对的结论；**【推断】** 是基于源码作出的判断，需要设计或产品确认。
> 证据格式：`仓库相对路径:行号`。如无特别说明，后端路径相对 `G:/weixinProject/sub2/backend/`，Web 路径相对 `G:/weixinProject/sub2/frontend/src/`，原生端路径相对 `G:/weixinProject/sub2-mobile-native/`。

---

## 0. 基线、方法与读法

### 0.1 源码基线

- 【事实】本地 `G:/weixinProject/sub2` 工作区的 HEAD 是 `40bee5d2e`（2026-10-12）。原生端文档声明的契约基线是 `e5ab7e4f`（`docs/API_COMPATIBILITY.md:3`），它位于 `origin/main`，时间为 2026-10-16，比本地 HEAD 更新。
- 【事实】两者的 `backend/internal/server/routes/` 中，admin、user、auth、payment 路由文件**完全一致**。唯一差异是 `gateway.go` 新增了 5 个 Gemini `cachedContents` 网关路由（`git diff HEAD e5ab7e4f -- backend/internal/server/routes/`）。因此，本报告的路由清单同时适用于两个提交。
- 【事实】字段层存在差异：账号的 `current_rpm`、`scheduling_rpm` 等字段只在 `e5ab7e4f` 中存在（`e5ab7e4f:backend/internal/handler/admin/account_handler.go:213-238`）。涉及这些字段时，以 `e5ab7e4f` 为准。
- 【事实】`G:/weixinProject/sub2-mobile-backend` 相当于本地 HEAD `40bee5d2e` 加上一个提交 `d75c49405`（feat(mobile): add native captcha verification bridge）。该提交只改动前端：新增公开页面 `/mobile/verify` 和 `mobileCaptchaBridge.ts`，**没有新增任何后端 API**（`sub2-mobile-backend/docs/mobile-verification.md`，`git show --stat d75c49405`）。

### 0.2 规模（【事实】）

| 路由文件 | 注册接口数 | 出处 |
| --- | --- | --- |
| `internal/server/routes/admin.go` | 455（另加 1 个插件 UI 静态资源） | `admin.go:14-142` 为总入口 |
| `internal/server/routes/payment.go` | 37（其中管理端 17，用户端 11，公开 2，Webhook 7） | `payment.go:27-135` |
| `internal/server/routes/user.go` | 62 | `user.go:12-159` |
| `internal/server/routes/auth.go` | 59 | `auth.go:16-262` |
| `internal/server/routes/gateway.go` | 71（`/v1`、`/v1beta`、Codex、Antigravity 网关） | `gateway.go:181-521` |
| 路由总装配 | — | `internal/server/router.go:122-139` |

- 【事实】原生端目前约接入 36 个接口，分布在 `Sources/Sub2Core/APIClient.swift`、`AccountManagement.swift:105-117`、`GroupManagement.swift:174-191`、`RequestLogs.swift:213-219`、`UsageAnalytics.swift:88-102`，约占管理面约 472 个接口的 **7.6%**。
- 【事实】Web 管理端页面体量（`wc -l views/admin/*.vue`）如下：`SettingsView.vue` 13582 行（9 个标签页，`SettingsView.vue:9183-9193`），`GroupsView.vue` 6915 行，`AccountsView.vue` 2627 行，`RiskControlView.vue` 2460 行，`ProxiesView.vue` 2090 行。这些数字说明，Web 端的配置面远大于手机屏幕能够合理承载的范围。

### 0.3 “移动端适合度”定义

- **高频移动**：管理员不在电脑前时也需要立即查看或一键处置，例如告警、账号异常、查日志、查用户、调余额。
- **偶尔**：使用频率低，但有明确的对象上下文，手机上能够安全完成，例如给某个用户延长订阅、发放兑换码、处理一笔退款。
- **仅 Web 合理**：配置面很大、需要批量操作、需要导入或导出文件、依赖浏览器 OAuth 回调或文件上传，或者属于高危操作（需要 step-up，或会覆盖整个库）。

---

## 1. 管理员能力全表

> “原生端”一列的判断依据是原生端代码中的实际调用（`grep 'request("'`），不考虑文档承诺。
> Web 菜单位置来自 `components/layout/AppSidebar.vue:853-963`，中文菜单名来自 `i18n/locales/zh/common.ts:170-225`，路由来自 `router/index.ts:403-770`。

### 1.1 总览与运维

| 路由组 / 功能 | 主要接口（`/api/v1` 前缀） | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **仪表盘** `admin/dashboard`（`admin.go:298-315`） | `GET stats`、`trend`、`models`、`groups`、`snapshot-v2`、`users-ranking`、`users-trend`、`api-keys-trend`、`user-breakdown`；`POST users-usage`、`api-keys-usage`、`aggregation/backfill`；`GET realtime` | 仪表盘 `/admin/dashboard`（仅站长可见，`AppSidebar.vue:857`） | **部分**：已接入 stats、trend、snapshot-v2（仅 stats）、models、groups（`APIClient.swift:88-118`、`UsageAnalytics.swift:88-102`）；`realtime` 只用作 Admin Key 权限探针（`APIClient.swift:66`） | 高频移动 | 首屏需要的数据。排行与按用户/Key 拆分适合放在“分析”二级页面。`backfill` 属于运维动作，只放 Web |
| **运维监控 · 实时信号** `admin/ops`（`admin.go:211-215, 252-256`） | `GET concurrency`、`user-concurrency`、`account-availability`、`realtime-traffic`；`WS ws/qps` | 运维监控 `/admin/ops`（开关 `flagOpsMonitoring`，`AppSidebar.vue:858`） | **未实现** | 高频移动（`account-availability`、`concurrency`） | `account-availability` 能直接给出各平台、分组、账号的可用、限流、错误计数和剩余秒数（`service/ops_realtime_models.go:53-91`），是“待处理事项”最直接的数据源。WebSocket 推送 QPS 比较耗电，手机端用轮询即可（【推断】） |
| **运维监控 · 看板** | `GET dashboard/overview`、`throughput-trend`、`latency-histogram`、`error-trend`、`error-distribution`、`snapshot-v2`、`openai-token-stats`（`admin.go:288-294`） | 同上（`OpsDashboard.vue:45-97` 中依次为并发卡、切换率、吞吐、延迟、错误分布、错误趋势、Token 统计、告警事件） | **部分**：已接入 overview（只取 `error_rate` 和 `qps`，`APIClient.swift:115-120`）和 throughput-trend | 高频移动（overview/健康分）；偶尔（其余图表） | overview 自带 `health_score` 0-100、SLA、上游 429/529 计数、TTFT/时延分位（`service/ops_dashboard_models.go:49-79`）。原生端目前只用了其中两个字段 |
| **运维监控 · 告警** | `GET/POST alert-rules`、`PUT/DELETE alert-rules/:id`；`GET alert-events`、`GET alert-events/:id`、`PUT alert-events/:id/status`；`POST alert-silences`（`admin.go:218-225`） | 运维监控页的“告警事件卡”（`OpsDashboard.vue:97`）和设置对话框里的“告警规则卡”（`OpsDashboard.vue:111`） | **未实现** | 事件：高频移动；规则：仅 Web 合理 | 事件可以确认或手动解决，也可以静默，这正是手机上的处置动作。规则编辑包含阈值、窗口、冷却等表单项，适合在 Web 完成 |
| **运维监控 · 通知与运行时配置** | `GET/PUT email-notification/config`、`runtime/alert`、`runtime/logging`（含 reset）、`advanced-settings`、`settings/metric-thresholds`（`admin.go:228-250`） | 运维监控 → 设置对话框（`OpsDashboard.vue:108`） | 未实现 | 仅 Web 合理 | 属于纯配置 |
| **运维监控 · 错误日志** | `GET request-errors`、`request-errors/:id`、`request-errors/:id/upstream-errors`、`PUT request-errors/:id/resolve`；`GET upstream-errors`、`upstream-errors/:id`、`PUT upstream-errors/:id/resolve`；旧版 `errors` 系列（`admin.go:259-277`） | 运维监控页的错误详情弹窗（`OpsDashboard.vue:114-127`） | **部分**：已接入两类列表和详情（`RequestLogs.swift:213-219`）；**没有接入**“客户端失败 → 上游错误”的下钻，也没有接入 resolve | 高频移动 | 错误日志带有 `resolved` 标记和 resolve 接口，可以当作“待处理”列表使用。下钻接口能把一次失败请求串到多次上游重试 |
| **运维监控 · 请求下钻** | `GET ops/requests`（成功和失败统一列表，`kind=success/error`，`admin.go:280`，`service/ops_request_details.go:11-41`） | 运维监控 → 请求明细弹窗（`OpsDashboard.vue:129`） | 未实现 | 高频移动（候选） | 一个接口就能给出“这段时间所有请求”，并带有 user/key/account/group ID，可以作为日志页的统一入口（【推断】）。原生端目前把 usage 和两类 error 拆成三个来源 |
| **运维监控 · 系统日志与健康** | `GET system-logs`、`POST system-logs/cleanup`、`GET system-logs/health`、`ingress-rejections`、`ingress-rejections/health`、`auth-cache-invalidation/health`（`admin.go:270-285`） | 运维监控页的系统日志表（`OpsDashboard.vue:100`） | 未实现 | 偶尔（只读查询）；cleanup 只放 Web | 系统日志带有 `request_id`、`user_id`、`account_id`（`service/ops_models.go:8-22`），可以按请求串联查看 |

### 1.2 核心对象管理

| 路由组 / 功能 | 主要接口 | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **账号 · 查询与运行数据** `admin/accounts`（`admin.go:403-487`） | `GET /`（支持 `platform`、`type`、`status`、`group`、`search`、`privacy_mode`、`sort_by`、`lite`、`include_scheduler_score`）、`GET :id`、`:id/today-stats`、`POST today-stats/batch`、`GET :id/stats`、`:id/usage`、`POST usage/batch`、`GET :id/models`、`:id/temp-unschedulable` | 账号管理 `/admin/accounts`（`AppSidebar.vue:887`） | **部分**：已接入列表（lite）、详情、今日统计（单个和批量）。**没有接入** `:id/usage`（上游 5h/7d 窗口）、`:id/stats`、`:id/temp-unschedulable`、`:id/models` | 高频移动 | 账号是最高频的排障对象 |
| **账号 · 状态恢复动作** | `POST :id/clear-error`、`:id/clear-rate-limit`、`:id/reset-quota`、`:id/recover-state`、`DELETE :id/temp-unschedulable`、`POST :id/revert-proxy-fallback`、`POST batch-clear-error`（`admin.go:442-470`） | 账号管理行内的操作菜单 | **未实现** | **高频移动** | 这些都是“看到异常后一键处置”的动作，最适合放到手机上，原生端目前完全缺失 |
| **账号 · 调度与凭据** | `POST :id/schedulable`、`:id/refresh`、`:id/test`（SSE）、`bulk-update`、`batch-refresh`、`:id/refresh-tier`、`batch-refresh-tier`、`:id/set-privacy`、`:id/apply-oauth-credentials` | 同上 | **部分**：已接入 schedulable、refresh、test（SSE）、bulk-update（仅调度开关，`AccountManagement.swift:117`） | 高频移动（启停调度、刷新、测试）；偶尔（tier、privacy） | — |
| **账号 · 编辑** | `PUT :id`、`GET/PUT :id/customization`、`PUT :id/grok-media-eligibility`、`:id/upstream-billing-probe`（含 POST 探测） | 账号编辑弹窗（`components/account/EditAccountModal.vue`） | **部分**：快捷编辑名称、备注、并发、优先级、倍率、负载因子、分组（`AccountManagement.swift:109`，`docs/ADMIN_MODULES.md:109`） | 偶尔 | 凭据和 provider extra 字段很多，完整编辑放 Web 合理 |
| **账号 · 新建/导入/导出/删除** | `POST /`、`:id/duplicate`、`batch`、`import/codex-session`、`sync/crs`（含 preview）、`GET/POST data`（导出需 step-up）、`batch-update-credentials`、`DELETE :id`、`batch-delete`、`check-mixed-channel` | 账号管理工具菜单（`AccountsView.vue:98, 474-475`） | 未实现 | 仅 Web 合理（删除可以“偶尔”） | 涉及文件导入导出、批量凭据和 step-up（`admin.go:463-464`） |
| **账号 · 平台 OAuth 与额度** | Claude：`accounts/generate-auth-url`、`exchange-code`、`cookie-auth` 等（`admin.go:480-485`）；OpenAI：`admin/openai/*`（`admin.go:501-516`）；Gemini：`admin/gemini/*`（`518-525`）；Antigravity：`admin/antigravity/*`（`527-534`）；Grok：`admin/grok/*`（`536-553`）；国产厂商额度/余额：`admin/cn-providers/accounts/:id/quota`、`/balance`（`556-564`）；Claude reset credits（`418-420`）；Ollama/OpenCode 用量（`411-439`） | 账号新建/重新授权弹窗，以及列表中的各平台额度单元格（`components/account/*Cell.vue`） | 未实现 | 额度查询：偶尔到高频；OAuth 授权：仅 Web 合理（【推断】iOS 可以用 `ASWebAuthenticationSession`，但涉及 code/cookie/SSO 等多种流程，成本很高） | 各平台的“剩余额度”是判断账号是否可用的关键信息 |
| **账号 · 定时测试** `admin/scheduled-test-plans`（`admin.go:781-791`） | `POST`、`PUT/DELETE :id`、`GET :id/results`、`GET accounts/:id/scheduled-test-plans` | 账号管理 → 定时测试面板（`AccountsView.vue:465`） | 未实现 | 偶尔（查看结果）；仅 Web（编辑计划） | 结果中有 `status`、`latency_ms`、`error_message`（`service/scheduled_test_port.go:24-34`） |
| **账号相关规则** | `admin/error-passthrough-rules` CRUD（`admin.go:793-802`）；`admin/tls-fingerprint-profiles` CRUD（`804-813`） | 账号管理工具菜单弹窗（`AccountsView.vue:496-497`） | 未实现 | 仅 Web 合理 | 属于低频的技术配置 |
| **用户** `admin/users`（`admin.go:317-342`） | `GET /`（支持 `search`、`status`、`role`、`group_name`、`api_key_group_id`、`include_deleted`、排序）、`GET/PUT/DELETE :id`、`POST /`、`POST :id/balance`、`GET :id/api-keys`、`GET :id/balance-history`、`POST :id/replace-group`、`GET :id/rpm-status`、`GET/PUT :id/platform-quotas`、`POST :id/platform-quotas/reset`、`POST batch-concurrency`、`batch-limits`、`POST :id/auth-identities`、`GET/PUT :id/attributes`、`GET users/:id/subscriptions`（`admin.go:753`） | 用户管理 `/admin/users` | **部分**：已接入列表、详情、创建、编辑（稀疏提交）、启停、余额调整、Key 只读（`APIClient.swift:161-191`）。**没有接入**余额流水、换分组、平台额度、RPM 状态、删除、订阅 | 高频移动（查找、余额、启停、流水）；偶尔（平台额度、换分组）；仅 Web（批量、属性定义） | 【事实】`GET :id/usage` 是占位实现，固定返回 0（`service/admin_user.go:1151-1160`），原生端已改用 `usage/stats`（`APIClient.swift:176-180`） |
| **用户调整记录** `admin/user-adjustments`（`admin.go:144-151`） | `GET /`、`GET export` | 订单管理页的调整记录面板（`views/admin/orders/AdminOrdersView.vue` → `UserAdjustmentsPanel.vue`） | 未实现 | 偶尔（只读） | 适合作为用户详情里的“余额流水”入口 |
| **用户属性** `admin/user-attributes`（`admin.go:769-779`） | 属性定义 CRUD、`reorder`、`POST batch` | 用户管理 → 属性配置弹窗 | 未实现 | 仅 Web 合理（定义）；偶尔（在用户详情只读展示） | — |
| **分组** `admin/groups`（`admin.go:344-372`），另有 `groups/:id/subscriptions`（`750`） | `GET /`、`all`、`:id`、`usage-summary`、`capacity-summary`、`live-capability`、`:id/api-keys`、`:id/model-allowlist-candidates`；`POST /`、`:id/duplicate`；`PUT :id`、`sort-order`；`DELETE :id`；`rate-multipliers`、`rpm-overrides`（GET/PUT/DELETE）；`composite-routes` CRUD 与 preview | 分组管理 `/admin/groups` | **部分**：已接入列表、all、详情、capacity-summary、创建、编辑、删除（`GroupManagement.swift:174-191`）。**没有接入** usage-summary、live-capability、`:id/api-keys`、订阅、倍率、RPM 覆盖、组合路由 | 偶尔（查看容量、启停、看今日/昨日费用）；仅 Web（模型白名单、组合路由、计费策略） | 【事实】`GET :id/stats` 是占位实现（`handler/admin/group_handler.go:912-932`）。Web 分组页有 6915 行，绝大部分是计费与路由配置 |
| **API Key（管理端）** `admin/api-keys`（`admin.go:201-206`） | `PUT :id`（仅修改所属分组） | 用户管理 → 用户 API Key 弹窗（`components/admin/user/UserApiKeysModal.vue`） | 部分（只读列出用户 Key） | 偶尔 | 适合在 Key 详情中提供“换分组”动作 |
| **代理** `admin/proxies`（`admin.go:566-585`） | `GET /`、`all`、`:id`、`:id/stats`、`:id/accounts`；`POST /`、`:id/test`、`:id/quality-check`、`batch`、`batch-delete`；`PUT/DELETE :id`；`GET/POST data`（导出需 step-up） | IP 管理 `/admin/proxies` | 未实现（账号详情只解码代理名称和 ID，`AccountPresentation.swift:4-13`） | 偶尔（测试、质量检测、查看挂载账号、处理到期） | 代理到期会直接导致账号故障，告警指标中也有 `proxy_expired_count` 和 `proxy_expiring_soon_count`（`handler/admin/ops_alerts_handler.go:19-36`） |
| **工作区 / 结算** `admin/workspaces`（`admin.go:379-401`） | `GET me`；以及仅站长可用的工作区 CRUD、成员管理、分组授权 | 工作区（仅站长）、结算（仅 vendor，`AppSidebar.vue:862-871`） | 未实现 | 仅 Web 合理（授权配置）；偶尔（vendor 查看自身结算） | 见 §1.6 vendor 角色 |

### 1.3 计费、商业与运营

| 路由组 / 功能 | 主要接口 | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **使用记录** `admin/usage`（`admin.go:756-767`） | `GET /`（支持 `user_id`、`api_key_id`、`account_id`、`group_id`、`model`、`request_id`、`request_type`、`stream`、`billing_type`、`billing_mode`、`upstream_model_mismatch`、排序，`handler/admin/usage_handler.go:71-184`）、`GET stats`、`search-users`、`search-api-keys`；清理任务 `GET/POST cleanup-tasks`、`POST cleanup-tasks/:id/cancel` | 使用记录 `/admin/usage` | **部分**：已接入列表（`count_mode=deferred`）和 stats（`RequestLogs.swift:213`、`UsageAnalytics.swift:88`）。**没有接入** search-users、search-api-keys（筛选器自动补全） | 高频移动（日志）；仅 Web（清理任务） | 两个 search 接口可以让手机筛选改为“输入即搜”，不必再手填 ID（【推断】） |
| **订阅** `admin/subscriptions`（`admin.go:733-754`） | `GET /`（支持 `user_id`、`group_id`、`platform`、`status`）、`GET :id`、`:id/progress`；`POST assign`、`bulk-assign`、`bulk-action`、`:id/extend`、`:id/reset-quota`、`:id/revoke`、`:id/restore`；`DELETE :id` | 订阅管理（仅站长，并受站点计费模式控制，`AppSidebar.vue:886`） | 未实现 | 偶尔（客服场景下给某用户延期、重置额度、撤销） | 应挂在用户详情或分组详情下，不必作为一级入口（【推断】） |
| **兑换码** `admin/redeem-codes`（`admin.go:587-601`） | `GET /`、`stats`、`export`、`:id`；`POST generate`、`create-and-redeem`、`batch-delete`、`batch-update`、`:id/expire`；`DELETE :id` | 兑换码 `/admin/redeem` | 未实现 | 偶尔（生成单张码或直接 create-and-redeem 作为补偿） | 导出与批量操作放 Web |
| **优惠码** `admin/promo-codes`（`admin.go:603-613`） | CRUD、`GET :id/usages` | 优惠码 | 未实现 | 偶尔 / 低 | — |
| **支付管理** `admin/payment`（`payment.go:93-134`） | `GET dashboard`、`GET/PUT config`；订单 `GET orders`（支持 `status`、`user_id`、`order_type`、`payment_type`、`keyword`、`days`）、`GET orders/:id`、`POST :id/cancel`、`:id/retry`、`:id/refund`、`:id/refund/query`；套餐 `plans` CRUD；支付商 `providers` CRUD | 订单管理组：支付概览、订单管理、订阅套餐（`AppSidebar.vue:919-931`）；支付配置在系统设置 → payment 标签页 | 未实现 | 偶尔到高频（**退款申请审批**、补单 retry、查看今日收入）；仅 Web（config、providers、套餐编辑） | 订单状态 `REFUND_REQUESTED` 天然就是“待处理”项（`payment/types.go:33`） |
| **邀请返利** `admin/affiliates`（`admin.go:874-892`） | `GET invites`、`rebates`、`transfers`；`users`（列表、lookup、batch-rate、overview、withdraw、更新、清除） | 邀请返利组（3 个子页面） | 未实现 | 偶尔（线下提现确认 withdraw） | — |
| **渠道（定价）** `admin/channels`（`admin.go:832-843`） | CRUD、`GET model-pricing`、`pricing/sync-models` | 渠道管理 → 渠道定价 | 未实现 | 仅 Web 合理 | 定价表很大（`ChannelsView.vue` 1725 行）。【事实】使用记录中的 `channel_id` 指向渠道（`handler/dto/types.go:699`），可作为日志详情的只读链接 |
| **公告** `admin/announcements`（`admin.go:489-499`） | CRUD、`GET :id/read-status` | 公告（仅站长） | 未实现 | 偶尔（紧急发布或下线公告） | 定向条件（按订阅/余额）比较复杂，手机上只做“发布/归档/查看已读”即可（【推断】） |

### 1.4 渠道监控、安全与审计

| 路由组 / 功能 | 主要接口 | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **渠道监控 V1（主动探测）** `admin/channel-monitors`、`admin/channel-monitor-templates`（`admin.go:845-871`，受功能开关保护 `930-939`） | 监控 CRUD、`:id/duplicate`、`POST :id/run`、`GET :id/history`；模板 CRUD、`:id/monitors`、`:id/apply` | 渠道管理 → 渠道监控 `/admin/channels/monitor` | 未实现 | 高频（看状态、手动 run）；仅 Web（编辑监控和模板） | 结果状态共 4 种（§3.9） |
| **渠道监控 V2（被动观测）** `admin/channel-monitor-v2`（`admin.go:894-928`，`overview` 需要功能开关，读取类接口还要求 `mode=v2`） | `GET/PUT config`、`observation-config`；`GET overview`、`groups/:id/accounts`、`probe-targets`（CRUD/probe）、`probe-budget`；读取类 `dimensions`、`snapshot`、`models`、`matrix`、`errors`、`users` | 同上 | 未实现 | 高频移动（overview、snapshot、errors 只读） | 基于真实流量计算健康度，带 healthy/warning/critical 分级（`service/channel_monitor_v2.go:1125-1152`），很适合做首页的“平台/模型健康”卡片 |
| **风控（内容审计）** `admin/risk-control`（`admin.go:187-199`） | `GET/PUT config`、`POST api-keys/test`、`GET status`、`GET logs`、`POST users/:user_id/unban`、`DELETE hashes`、`hashes/all` | 安全审计 → 内容审计（`AppSidebar.vue:891-902`） | 未实现 | 偶尔（查看命中日志、解封用户） | 日志带有 `user_id`、`api_key_id`、`group_id`、`auto_banned`（`service/content_moderation.go:400-424`） |
| **提示词审计** `admin/prompt-audit`（`admin.go:153-167`） | config、endpoints/probe、runtime、events（列表/详情/删除/按筛选删除） | 安全审计 → 提示词审计 | 未实现 | 偶尔（只读）；仅 Web（配置） | — |
| **操作审计日志** `admin/audit-logs`（`admin.go:169-177`） | `GET /`、`GET :id`、`POST clear`（需要在 handler 内现场校验 TOTP） | 操作日志 `/admin/audit-logs`（仅站长） | 未实现 | 偶尔（安全事件追溯）；clear 只放 Web | 字段见 `service/audit_log.go:43-63` |
| **合规确认** `admin/compliance`（`admin.go:179-185`） | `GET /`、`POST accept` | 全局拦截弹窗（`stores/adminCompliance.ts`） | 部分：只识别 `ADMIN_COMPLIANCE_ACK_REQUIRED` 并引导用户去 Web（`docs/API_COMPATIBILITY.md:46`） | 偶尔（一次性） | 未确认时所有管理接口都返回 423（`server/middleware/vendor_routes.go:100-106` 的注释） |

### 1.5 系统级（基本应保持 Web）

| 路由组 / 功能 | 主要接口 | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **系统设置** `admin/settings`（`admin.go:615-663`） | `GET/PUT /`；SMTP 测试、邮件模板、Admin API Key 重新生成与删除、529/429 冷却、面板限流、流超时、整流器、Beta 策略、Claude 魔改预设、Web Search 模拟 | 系统设置（9 个标签页：general/agreement/features/security/users/gateway/payment/email/backup，`SettingsView.vue:9183-9193`）、Claude 魔改设置 | 未实现 | 仅 Web 合理 | `SettingsView.vue` 共 13582 行 |
| **备份 / 数据管理** `admin/backups`（`admin.go:689-719`）、`admin/data-management`（`665-687`） | S3 配置、定时备份、创建/下载/恢复（多处需要 step-up） | 系统设置 → backup 标签页（`SettingsView.vue:9111` 引入了 `BackupView.vue`）；**data-management 在 Web 端没有页面入口**（只有 `api/admin/dataManagement.ts`） | 未实现 | 仅 Web 合理（可选：只读查看“最近备份是否成功”） | 高危操作，会覆盖整个库 |
| **系统版本** `admin/system`（`admin.go:721-731`） | `GET version`、`check-updates`、`rollback-versions`；`POST update`、`rollback`、`restart` | 侧边栏版本徽章（`components/common/VersionBadge.vue`） | 未实现 | 偶尔（只读查看“有新版本”）；仅 Web（update/rollback/restart） | — |
| **插件** `admin/plugins`（`admin.go:815-830`）与 `plugin-ui/:token/*path`（`25`） | 上传、启停、配置、测试（需 step-up）、UI 会话 | 插件管理 | 未实现 | 仅 Web 合理 | 需要上传文件并嵌入第三方 UI |
| **自定义页面** `pages`（`handler/page_handler.go:261-282`） | `GET pages/:slug`、管理端 `GET pages` | 自定义菜单项（`AppSidebar.vue:949-961`） | 未实现 | 仅 Web 合理（或用 WebView 打开） | — |

### 1.6 管理面的横切事实

- 【事实】**三个占位接口**不能直接用于展示：`GET admin/dashboard/realtime`（`handler/admin/dashboard_handler.go:186-194`）、`GET admin/users/:id/usage`（`service/admin_user.go:1151-1160`）、`GET admin/groups/:id/stats`（`handler/admin/group_handler.go:924-931`）。三者都固定返回 0。
- 【事实】**需要 step-up 二次验证的操作**：导出账号或代理、配置 S3、创建/下载/恢复备份、插件写入（`admin.go:463-464, 571-572, 679-717, 820-827`）；创建管理员、把用户提升为管理员（`handler/admin/user_handler.go:303-308, 357-369`）；清空审计日志（`admin.go:174-175`）。手机端设计需要有统一的“现场输入 TOTP 后再确认”的交互。
- 【事实】**存在第三种管理角色 `vendor`（供应商/代运营）**（`domain/constants.go:14-20`）。vendor 只能访问白名单中的路由：账号读写（按工作区权限档）、代理、分组读写、usage，以及 dashboard 的 trend/models/groups 三个接口；用户、订阅、兑换码、公告、ops、设置、审计一律返回 403（`server/middleware/vendor_routes.go:91-176`）。原生端登录时只接受 `role == "admin"`（`APIClient.swift:69, 248`），因此 vendor 目前无法使用 App。【推断】未来的信息架构必须能够**按角色裁剪模块**，不要假设“管理端只有一种权限视图”。
- 【事实】**站点功能开关会决定模块是否存在**：ops 监控（`ops_monitoring_enabled`，`handler/admin/setting_handler.go:125, 293`）、渠道监控（`admin.go:930-962`）、支付、订阅、邀请返利、风控、插件（`AppSidebar.vue:766-787`）。【推断】手机端入口应读取设置后再决定是否显示，而不是写死。

---

## 2. 普通用户（非管理员）能力全表

> 用户路由：`user.go:12-159`；认证：`auth.go:29-261`；支付用户端：`payment.go:40-77`；模型广场：`model_plaza.go:23-29`。Web 菜单来自 `AppSidebar.vue:794-819`。
> 【事实】原生端当前**明确只支持管理员**（`NativeApp/Features/LoginView.swift:66`）。

| 功能 | 主要接口 | Web 菜单位置 | 原生端 | 移动端适合度 | 理由 |
| --- | --- | --- | --- | --- | --- |
| **登录与会话** | `POST auth/login`、`login/2fa`、`refresh`、`logout`；`GET auth/me`；`POST auth/revoke-all-sessions` | `/login` | **部分**：仅管理员可登录（`APIClient.swift:41-83`）；验证码通过 `/mobile/verify` 桥接完成 | 高频移动 | 改成普通用户可用时，主要是放开角色限制，并补上用户端的首屏 |
| **Passkey 登录** | `POST auth/passkey/login/begin`、`finish`（`auth.go:44-49`）；`user/passkeys` CRUD（`user.go:65-72`） | 登录页与个人资料 | 未实现 | 高（【推断】iOS 原生支持 Passkey，但需要站点配置 `apple-app-site-association`，且 RP ID 必须匹配） | — |
| **注册、找回密码、邀请码/优惠码校验** | `POST auth/register`、`send-verify-code`、`forgot-password`、`reset-password`、`validate-promo-code`、`validate-invitation-code` | `/register`、`/forgot-password`、`/reset-password` | 未实现 | 偶尔 | 涉及验证码，可以复用现有桥接 |
| **第三方 OAuth 登录与绑定** | LinuxDo、GitHub、Google、微信、OIDC、钉钉的 `start`/`callback`/`complete-registration`/`bind-login`/`create-account`；`oauth/pending/*`（`auth.go:75-238`） | 登录页、个人资料绑定 | 未实现 | 偶尔（【推断】需要 `ASWebAuthenticationSession`，且回调走 Web 路由，改造成本中等） | — |
| **个人概览** | `GET usage/dashboard/stats`、`trend`、`models`、`snapshot-v2`；`POST usage/dashboard/api-keys-usage`（`user.go:107-112`） | 仪表盘 `/dashboard` | 未实现 | 高频移动 | 用户最常查看的是余额、今日消费和用量 |
| **API Key 管理** | `GET/POST keys`、`GET/PUT/DELETE keys/:id`（`user.go:76-83`）；`GET groups/available`、`groups/rates`（`86-90`）；`GET user/api-keys/:id/usage/daily`（`40`） | API 密钥 `/keys` | 未实现 | 高频移动（查看、复制、启停、看每日用量）；偶尔（新建、改 IP 白名单） | Key 带有配额、5h/1d/7d 限额、到期时间、实时并发（`handler/dto/types.go:56-91`） |
| **用量记录与错误** | `GET usage`、`usage/:id`、`usage/stats`、`usage/errors`、`usage/errors/:id`（`user.go:99-106`，均受 Heavy 限流） | 使用记录 `/usage` | 未实现 | 高频移动 | 用户自查失败原因，可以减少客服工作量 |
| **订阅/套餐进度** | `GET subscriptions`、`active`、`progress`、`summary`（`user.go:130-136`） | 我的订阅 `/subscriptions` | 未实现 | 高频移动 | 日/周/月额度进度很适合做成手机卡片或小组件（【推断】） |
| **充值/购买与订单** | `GET payment/config`、`checkout-info`、`plans`、`limits`；`POST payment/orders`、`verify`；`GET orders/my`、`orders/:id`；`POST :id/cancel`、`:id/refund-request`；`GET refund-eligible-providers`（`payment.go:46-60`） | 充值/订阅 `/purchase`、我的订单 `/orders`，以及支付结果页和二维码页 | 未实现 | 偶尔；建议跳转 Web（【推断】若 App 上架 App Store，应用内用第三方支付购买数字服务受审核指南 3.1.1 限制：<https://developer.apple.com/app-store/review/guidelines/#in-app-purchase>。目前看是自用分发，可以不受此限制，但需确认） | 查看订单、申请退款可以在手机上完成 |
| **兑换** | `POST redeem`、`GET redeem/history`（`user.go:123-127`） | 兑换 `/redeem` | 未实现 | 偶尔（粘贴或扫码兑换，很适合手机） | — |
| **邀请返利** | `GET user/aff`、`POST user/aff/transfer`（`user.go:34-35`） | 邀请返利 `/affiliate` | 未实现 | 偶尔 | — |
| **个人资料与通知邮箱** | `GET user/profile`、`PUT user`、`PUT user/password`、`account-bindings`、`auth-identities/bind/start`、`notify-email/*`、`GET user/platform-quotas`（`user.go:31-50`） | 个人资料 `/profile` | 未实现 | 偶尔 | — |
| **双因素认证** | `GET user/totp/status`、`verification-method`；`POST send-code`、`setup`、`enable`、`disable`、`step-up`（`user.go:53-63`） | 个人资料内 | **部分**：只调用 `step-up`（`APIClient.swift:192-196`） | 偶尔 | — |
| **公告** | `GET announcements`、`POST announcements/:id/read`（`user.go:116-120`） | 页眉铃铛（`components/layout/AppHeader.vue:26-27`） | 未实现 | 高（支持 popup/silent 两种通知模式，`domain/announcement.go:17-18`） | 这是平台唯一面向用户的“站内通知”通道 |
| **渠道状态** | `GET channel-monitors`、`channel-monitors/:id/status`；`GET channel-monitor-v2/overview`、`dimensions`、`snapshot`、`models`、`matrix`、`errors`、`users`（`user.go:139-157`） | 渠道状态 `/monitor` | 未实现 | 高频移动（“服务现在能不能用”） | — |
| **可用渠道与模型广场** | `GET channels/available`（`user.go:93-96`）；`GET model-plaza`（`model_plaza.go:23-29`，允许匿名） | 可用渠道 `/available-channels`、模型广场 `/model-plaza` | 未实现 | 偶尔 | — |
| **Key 额度公开查询** | 网关 `GET /v1/usage`、`/v1/sub2api/billing`，使用 API Key 认证（`gateway.go:188, 212`） | `/key-usage`（`views/KeyUsageView.vue:865`） | 未实现 | 偶尔（【推断】很适合做“只填 Key、不登录”的轻量查询或小组件） | — |
| **批量生图** | 网关 `/v1/images/batches/*`（`gateway.go:260-267`） | 批量生图 `/batch-image` | 未实现 | 仅 Web 合理 | 需要上传文件、批量下载 |
| **自定义页面** | `GET pages/:slug` | 自定义菜单 | 未实现 | 仅 Web（WebView） | — |

- 【事实】Web 端有一处多余调用：`api/subscriptions.ts:61-68` 调用了 `GET /subscriptions/:id/progress`，但后端没有注册这个路由（只有 `/subscriptions/progress`，`user.go:134`），而且这个函数没有任何调用方。实现用户端时不要照搬。

---

## 3. 关键对象与状态词典（UI 状态徽章的依据）

### 3.1 上游账号 Account

**A. 持久状态 `status`**
- 【事实】后端常量为 `active`、`disabled`、`error`（`domain/constants.go:4-11`），但管理端写接口只允许 `active`、`inactive`、`error`（`handler/admin/account_handler.go:168, 187`）。
- 【事实】CRS 同步会写入 `inactive`（`service/crs_sync_service.go:1300-1302`）。ent schema 注释写的是 `"active", "error", "disabled"`（`ent/schema/account.go:123`）。
- 【事实】`SetError` 会同时把 `status` 置为 `error` 并把 `schedulable` 置为 `false`（`repository/account_repo.go:1514-1520`）。
- Web 文案：active 显示“正常”，inactive 显示“停用”，error 显示“错误”（`i18n/locales/zh/admin/accounts.ts:443-465`）。
- 【推断】徽章至少要兼容 `active`、`inactive`、`disabled`、`error` 四个值。原生端目前只映射了 `active`、`inactive`、`error`（`Sources/Sub2Core/AccountPresentation.swift:86`），遇到 `disabled` 会直接显示原始英文。

**B. 调度意图 `schedulable`（bool）**
- 这是管理员的手动开关。关闭后 Web 显示“暂停”（`AccountStatusIndicator.vue:333-334, 353-354`）。

**C. 运行时阻断（时间窗，到期自动恢复）**

| 字段 | 含义 | 恢复接口 | 出处 |
| --- | --- | --- | --- |
| `rate_limit_reset_at` | 429 限流，到该时间前不参与调度 | `POST :id/clear-rate-limit` | `service/account.go:51-52, 221-226`；`dto/types.go:238-239` |
| `overload_until` | 529 过载 | （随 recover-state 一起清除）`POST :id/recover-state` | `service/account.go:53, 228-233` |
| `temp_unschedulable_until` + `temp_unschedulable_reason` | 临时不可调度；reason 是 JSON 格式的 `TempUnschedState`，包含 `status_code`、`matched_keyword`、`rule_index`、`error_message`、`trigger_count` 等 | `GET`、`DELETE :id/temp-unschedulable` | `service/temp_unsched.go:9-19`；`service/ratelimit_service.go:2730-2760` |
| `extra.model_rate_limits`（按模型） | 单个模型限流；键 `AICredits` 表示积分耗尽 | — | `components/account/AccountStatusIndicator.vue:191-226`；`service/ratelimit_service.go:2742-2751`（已知模型失败只写入模型级） |
| `quota_*_used` ≥ `quota_*_limit`（API Key/Bedrock 账号） | 日/周/总配额超限 | `POST :id/reset-quota` | `service/account.go:189-190`；`AccountStatusIndicator.vue:287-296` |
| `expires_at` + `auto_pause_on_expired` | 过期后自动暂停 | — | `service/account.go:177-178` |
| `session_window_status` | Anthropic 5h 会话窗口：`allowed`、`allowed_warning`（约 80%）、`rejected`（100%） | — | `service/account_usage_service.go:1736-1740`；`service/ratelimit_service.go:2044-2073` |

- 【事实】综合判定逻辑是 `Account.IsSchedulable()`：要求 active、schedulable 为真，且未过期、未过载、未限流、未临时不可调度、配额未超限（`service/account.go:172-193`）。
- 【事实】列表筛选中的 `status` 是派生值：`active` 表示可调度（同时满足 active、schedulable 且没有限流或临时阻断），另有 `rate_limited`、`temp_unschedulable`、`unschedulable`，其他值按原值匹配（`repository/account_repo.go:1062-1122`）。过载（overload）**没有**对应的筛选值。
- 【事实】Web 徽章的优先级为：error → 临时不可调度 → 非 active → 配额超限 → 暂停（`!schedulable`）→ 正常。429 倒计时、529 过载和模型级限流作为附加标签并列显示（`AccountStatusIndicator.vue:320-355`）。
- 【事实】**原生端缺口**：`UpstreamAccount` 没有解码 `rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`、`temp_unschedulable_reason`、`extra.model_rate_limits`（见 `Sources/Sub2Core/Models.swift:188-199` 的 CodingKeys）。因此原生端无法显示“限流中，X 分钟后恢复”这类最关键的状态。截图也印证了这一点：账号行只有“状态：正常 / 调度：参与调度”两段文字（`sub2-mobile-artifacts/native-ios-rebuild/admin-expansion-20261016/final-evidence/collection/attachments/AccountManagementUITests/0FE95C0E-ADA5-4FF6-BA37-E240ADED809C.png`）。
- 【推断】徽章建议分三层：①持久状态（正常/停用/错误）；②调度意图（参与/暂停）；③运行时阻断（限流、过载、临时不可调度、模型限流、配额超限、即将过期），带倒计时，并可以一键恢复。

**D. 分类维度**
- 平台（13 个具体平台加 `composite`）：anthropic、openai、gemini、antigravity、grok、kimi、zhipu、deepseek、minimax、opencode_go、typesafe、command_code、cline（`domain/platforms.go:37-51`；`domain/constants.go:35-56`）。
- 认证类型 `type`：`oauth`、`setup-token`、`apikey`、`upstream`、`bedrock`、`service_account`（`domain/constants.go:79-86`）。
- 国产厂商接入模式 `credentials.account_mode`：`payg`、`coding`、`zen`、`go`；上游协议 `credentials.api_protocol`：`chat_completions`、`anthropic`、`responses`、`adaptive`（`domain/constants.go:59-76`）。
- 隐私模式 `extra.privacy_mode`：OpenAI 为 `training_off`、`training_set_failed`、`training_set_cf_blocked`；Antigravity 为 `privacy_set`、`privacy_set_failed`（`service/openai_privacy_service.go:20-22`；`service/antigravity_privacy_service.go:13-14`）。
- 影子账号：`parent_account_id` 加 `quota_dimension`（`""`、`global`、`spark`）（`service/account.go:69-70`）。
- 代理回退：`proxy_fallback_origin_id` 和 `proxy_fallback_origin_name`，可通过 `POST :id/revert-proxy-fallback` 恢复（`dto/types.go:222-223`）。
- 容量与实时数据：`current_concurrency`、`probe_concurrency`、`current_rpm`（近 60 秒）、`scheduling_rpm`（自然分钟）、`current_window_cost`、`active_sessions`（`e5ab7e4f:handler/admin/account_handler.go:213-238`）。

### 3.2 用户 User

| 维度 | 取值 / 字段 | 出处 |
| --- | --- | --- |
| 角色 `role` | `admin`、`user`、`vendor` | `domain/constants.go:14-20` |
| 状态 `status` | `active`、`disabled`（写接口的 oneof 限定）。风控自动封禁会写入 `disabled` | `handler/admin/user_handler.go:88`；`service/content_moderation.go:1985` |
| 软删除 | `deleted_at`；列表通过 `include_deleted` 参数查看 | `dto/types.go:25` |
| 资金 | `balance`、`frozen_balance`、`total_recharged`；余额提醒 `balance_notify_*` | `dto/types.go:17-33` |
| 限额 | `concurrency`、`rpm_limit`（0 表示不限）、`allowed_groups`、`group_rates`、`restrict_public_groups` | `dto/types.go:19-21, 36, 47-53` |
| 活跃 | `last_active_at`、`last_used_at` | `dto/types.go:22, 47` |
| 余额流水类型 | `balance`、`concurrency`、`subscription`、`invitation`、`affiliate_balance`、`admin_balance`、`admin_concurrency` | `service/domain_constants.go:172-176, 187-188`；`handler/admin/user_handler.go:516` |

### 3.3 分组 Group

| 维度 | 取值 / 字段 | 出处 |
| --- | --- | --- |
| 状态 | `active`、`inactive`（复制出的分组默认为 inactive） | `handler/admin/group_handler.go:268`；`service/admin_group_duplicate.go:15` |
| 平台 | 同账号平台，另加 `composite`（组合路由） | `domain/constants.go:56` |
| 计费类型 `subscription_type` | `standard`（按余额扣费）、`subscription`（按限额） | `domain/constants.go:108-112` |
| 访问控制 | `is_exclusive`、`claude_code_only`、`require_oauth_only`、`require_privacy_set`、`fallback_group_id`、`fallback_group_id_on_invalid_request` | `dto/types.go:98-152` |
| 限额 | `rpm_limit`、`daily/weekly/monthly_limit_usd` | `dto/types.go:102-104, 155` |
| 管理端运行计数 | `account_count`、`active_account_count`、`rate_limited_account_count`、`billing_locked` | `dto/types.go:181, 200-202` |

### 3.4 API Key

| 维度 | 取值 / 字段 | 出处 |
| --- | --- | --- |
| 状态 | `active`、`disabled`、`quota_exhausted`、`expired` | `service/api_key.go:11-14` |
| 配额 | `quota`（0 表示不限）、`quota_used`、`expires_at` | `dto/types.go:66-68` |
| 滚动限额 | `rate_limit_5h/1d/7d`，以及对应的 `usage_*`、`window_*_start`、`reset_*_at` | `dto/types.go:73-85` |
| 访问控制 | `ip_whitelist`、`ip_blacklist`、`group_id` | `dto/types.go:60-63` |
| 实时 | `current_concurrency`、`last_used_at`、`last_used_ip` | `dto/types.go:64-65, 72` |

### 3.5 订阅 UserSubscription

- 【事实】状态取值为 `active`、`expired`、`suspended`、`revoked`（`domain/constants.go:115-119`；`service/domain_constants.go:199-203`）。
- 用量字段：`daily/weekly/monthly_usage_usd` 和各窗口起点；限额来自所属分组；`revoked_at`；管理端额外有 `assigned_by`、`notes`（`dto/types.go:765-800`）。

### 3.6 请求日志 UsageLog（成功请求）

| 维度 | 取值 / 字段 | 出处 |
| --- | --- | --- |
| `request_type` | `unknown`、`sync`、`stream`、`ws_v2`、`cyber`（命中上游安全策略）、`live` | `service/usage_log.go:16-79` |
| `billing_type` | `0`=余额、`1`=订阅 | `service/usage_log.go:9-12` |
| 费用 | `total_cost`（标准）、`actual_cost`（用户实际扣费）；上游成本为 `(account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1)` | `dto/types.go:623-624, 708-710`；`docs/ADMIN_MODULES.md:97` |
| 模型映射 | `model`（请求模型）、`upstream_model`、`upstream_response_model`、`upstream_model_mismatch`、`model_mapping_chain` | `dto/types.go:689-702` |
| 特殊标记 | `probe_coalesced`、`provider_cost_recorded`、`long_context_billing_applied`、`cache_ttl_overridden` | `dto/types.go:626, 660, 667-673` |
| 时延 | `duration_ms`、`first_token_ms` | `dto/types.go:635-636` |

### 3.7 错误日志 OpsErrorLog（客户端失败 / 上游错误）

| 维度 | 取值 | 出处 |
| --- | --- | --- |
| `phase` | `request`、`auth`、`account_auth`、`routing`、`upstream`、`network`、`internal` | `service/ops_models.go:29-33`；`handler/ops_error_logger.go:2170-2203` |
| `error_owner` | `client`、`provider`、`platform` | `service/ops_models.go:31` |
| `error_source` | `client_request`、`upstream_http`、`gateway` | `service/ops_models.go:32` |
| `severity` | 分类器只产出 `P1`（5xx/429）、`P2`（其他 4xx）、`P3`（参数/鉴权/计费类） | `handler/ops_error_logger.go:2205-2220` |
| 处置 | `resolved`、`resolved_at`、`resolved_by_user_name` | `service/ops_models.go:45-49` |
| 业务限流 | `is_business_limited`（列表 `view=errors` 时默认排除） | `service/ops_models.go:98, 153-157` |
| 统一请求下钻 | `kind`：`success` 或 `error` | `service/ops_request_details.go:11-12` |

### 3.8 告警 OpsAlertRule / OpsAlertEvent

- 【事实】事件状态有 `firing`、`resolved`、`manual_resolved`（`service/ops_alert_models.go:10-14`）。
- 【事实】严重级别为 `P0` 到 `P3`。发邮件时 P0 映射为 critical，P1 映射为 warning，其余映射为 info（`service/ops_alert_evaluator_service.go:847-855`）。
- 【事实】指标白名单共 16 项：`success_rate`、`error_rate`、`upstream_error_rate`、`cpu_usage_percent`、`memory_usage_percent`、`concurrency_queue_depth`、`group_available_accounts`、`group_available_ratio`、`group_rate_limit_ratio`、`account_rate_limited_count`、`account_error_count`、`account_error_ratio`、`account_temp_unscheduled_count`、`overload_account_count`、`proxy_expired_count`、`proxy_expiring_soon_count`（`handler/admin/ops_alerts_handler.go:19-36`）。
- 【事实】事件维度只包含 `platform` 和 `group_id`，**没有账号 ID**（`service/ops_alert_evaluator_service.go:640-652`）。因此告警只能导航到平台或分组，不能直接跳到具体账号。

### 3.9 渠道监控结果

- 【事实】V1 主动探测的状态有 `operational`、`degraded`（任一用量窗口超过 90%）、`failed`、`error`（`service/channel_monitor_const.go:96-107`）。`check_mode` 可以是 `probe`、`quota`、`quota_probe`（`service/channel_monitor_types.go:54`）。
- 【事实】V2 被动观测有四个健康维度：`overall`、`error_rate`、`ttft`、`cache`，每个维度的取值为 `healthy`、`warning`、`critical`、`unknown`（`service/channel_monitor_v2.go:126-129, 1014, 1125-1152`）。
- 【事实】V2 错误分类共 13 类：`content_policy`、`authentication`、`context_limit`、`invalid_request`、`model_unsupported`、`group_access`、`quota_or_balance`、`account_pool_unavailable`、`rate_or_capacity`、`timeout`、`transport_or_stream`、`upstream_forbidden`、`not_found`（`service/channel_monitor_v2_error_taxonomy.go:22-58`）。

### 3.10 代理 Proxy

- 【事实】状态为 `active` 或 `inactive`（`handler/admin/proxy_handler.go:50`）；导入时 `disabled` 和 `expired` 都会归一为 `inactive`（`handler/admin/account_data.go:770-785`）。
- 【事实】`fallback_mode` 可以是 `none`、`proxy`、`direct`（`service/proxy.go:10-14`）；测试结果 `latency_status` 为 `success` 或 `failed`（`service/admin_proxy.go:646-649`）。
- 其他字段：`quality_status`、`quality_score`、`quality_grade`，以及 `expires_at`、`expiry_warn_days`（`dto/types.go:447-472`）。

### 3.11 支付订单与其他

| 对象 | 状态取值 | 出处 |
| --- | --- | --- |
| 支付订单 | `PENDING`、`PAID`、`RECHARGING`、`COMPLETED`、`EXPIRED`、`CANCELLED`、`FAILED`、`REFUND_REQUESTED`、`REFUNDING`、`REFUND_PENDING`、`PARTIALLY_REFUNDED`、`REFUNDED`、`REFUND_FAILED` | `payment/types.go:26-38` |
| 兑换码 | 状态 `unused`、`used`、`expired`；类型见 §3.2 | `domain/constants.go:8-10, 89-94` |
| 优惠码 | `active`、`disabled` | `domain/constants.go:97-100` |
| 公告 | `draft`、`active`、`archived`；通知模式 `silent` 或 `popup`；定向条件为订阅或余额 | `domain/announcement.go:11-32` |
| 渠道（定价） | `active`、`disabled` | `handler/admin/channel_handler.go:48` |
| 工作区 | `active`、`disabled` | `domain/constants.go:28-32` |
| 用量清理任务 | `pending`、`running`、`succeeded`、`failed`、`canceled` | `service/usage_cleanup.go:11-15` |
| 定时测试结果 | `status`（字符串）、`latency_ms`、`error_message` | `service/scheduled_test_port.go:24-34` |

---

## 4. 对象关系图（文字版，用于“对象中心”导航）

```
                          ┌──────────── Workspace(vendor) ──grants──▶ Group
                          │                   │members
                          ▼                   ▼
 Proxy ◀─proxy_id── Account ──account_groups──▶ Group ◀──group_id── APIKey ──user_id──▶ User
   │ backup_proxy_id   │ parent_account_id        │ fallback_group_id     ▲                │
   ▼                   ▼ (影子→母账号)              │ channel.group_ids      │                │
 Proxy               Account                      │ plan.group_id          │                ├─▶ UserSubscription ─group_id─▶ Group
                       │                          │ composite-routes       │                ├─▶ PaymentOrder ─plan_id─▶ SubscriptionPlan ─group_id─▶ Group
                       ├─▶ ScheduledTestPlan ─▶ Result                     │                ├─▶ 余额流水(RedeemCode 类记录)
                       └─▶ ChannelMonitor(quota 模式 account_id)           │                ├─▶ Affiliate / PromoCodeUsage
                                                                          │                └─▶ AuditLog(actor_user_id)
 UsageLog ── user_id / api_key_id / account_id / group_id / subscription_id / channel_id / request_id
 OpsErrorLog ── user_id / api_key_id / account_id / group_id / request_id / client_request_id
     └─ request-errors/:id/upstream-errors ─▶ 多条上游错误（同一请求的重试链）
 OpsSystemLog ── request_id / user_id / api_key_id / account_id
 ContentModerationLog ── request_id / user_id / api_key_id / group_id
 OpsAlertEvent ── rule_id / dimensions{platform, group_id}（无账号）
```

**可导航关联与现成的反查接口（【事实】）**

| 起点 → 终点 | 关联字段 | 现成接口（“查看相关…”） | 出处 |
| --- | --- | --- | --- |
| 日志 → 账号/用户/Key/分组/订阅 | `account_id`、`user_id`、`api_key_id`、`group_id`、`subscription_id`；admin DTO 已内嵌 `user`、`api_key`、`group`、`account{id,name}` 摘要 | `GET admin/accounts/:id`、`users/:id`、`groups/:id` | `dto/types.go:590-717` |
| 日志 ↔ 错误 ↔ 系统日志 | `request_id` | `GET admin/usage?request_id=`、`ops/request-errors?request_id=`、`ops/system-logs` | `handler/admin/usage_handler.go:119`；`ops_handler.go`（`request_id` 参数） |
| 客户端失败 → 上游重试 | 错误 ID | `GET ops/request-errors/:id/upstream-errors` | `admin.go:266` |
| 账号 → 日志/错误/分析 | `account_id` 筛选 | `GET admin/usage?account_id=`、`ops/*-errors?account_id=`、`dashboard/trend?account_id=` | `usage_handler.go:100`；`dashboard_handler.go:198` |
| 账号 → 分组 | `group_ids`、`groups` | 详情自带 | `dto/types.go:323-326` |
| 账号 → 代理 | `proxy_id`、`proxy` | `GET admin/proxies/:id` | `dto/types.go:221, 322` |
| 账号 → 母账号（影子） | `parent_account_id` | `GET admin/accounts/:id` | `dto/types.go:312` |
| 账号 → 定时测试 | — | `GET admin/accounts/:id/scheduled-test-plans` | `admin.go:790` |
| 分组 → 账号 | `group` 筛选 | `GET admin/accounts?group=` | `repository/account_repo.go:1126-1130` |
| 分组 → Key / 订阅 / 用户 | — | `GET admin/groups/:id/api-keys`、`groups/:id/subscriptions`、`users?api_key_group_id=` | `admin.go:370, 750`；`user_handler.go` 参数 |
| 用户 → Key / 订阅 / 流水 / 订单 / 平台额度 | `user_id` | `GET users/:id/api-keys`、`users/:id/subscriptions`、`users/:id/balance-history`、`admin/payment/orders?user_id=`、`users/:id/platform-quotas` | `admin.go:327-336, 753`；`payment.go:109` |
| 代理 → 账号 | — | `GET admin/proxies/:id/accounts` | `admin.go:581` |
| 告警 → 分组/平台 | `dimensions` | `GET admin/groups/:id`、`ops/account-availability?group_id=` | `service/ops_alert_evaluator_service.go:640-652` |
| 渠道监控 V2 → 分组下的账号 | — | `GET channel-monitor-v2/groups/:id/accounts` | `admin.go:910` |
| 风控日志 → 用户（解封） | `user_id` | `POST risk-control/users/:user_id/unban` | `admin.go:195` |
| 优惠码 → 使用者 | — | `GET promo-codes/:id/usages` | `admin.go:611` |
| 公告 → 已读用户 | — | `GET announcements/:id/read-status` | `admin.go:497` |

- 【推断】从关系上看，**账号、用户、分组**是三个“枢纽对象”。日志、错误、告警都能落到这三类对象上。“对象中心”只要先实现这三类详情页，并在每个详情页里提供“相关日志/错误/分析/子对象”的过滤跳转，就能覆盖绝大多数排障路径。原生端已经有一部分这类跳转（`docs/ADMIN_MODULES.md:95`），但请求详情页没有提供跳到账号或用户的链接（截图 `.../RequestLogsUITests/9A6FA137-E2D8-4449-9B27-91AD1A8F4DC9.png` 只展示了字段值）。

---

## 5. 监控 / 告警类能力现状

| 能力 | 现状（【事实】） | 出处 | 能否喂给移动端“待处理事项” |
| --- | --- | --- | --- |
| 基础健康检查 | `GET /health` 返回 `{"status":"ok"}` | `server/routes/common.go:12-14` | 只能做连通性检查 |
| Ops 监控总开关 | 同时受配置文件 `cfg.Ops.Enabled` 和站点设置 `ops_monitoring_enabled` 控制；关闭时告警评估器直接退出 | `service/ops_alert_evaluator_service.go:157-168` | 需要先检测开关，并为“未启用”状态设计 UI |
| 健康评分 | overview 返回 0-100 的 `health_score`（由业务健康和基础设施健康计算），并附带 `system_metrics`（CPU/内存）和 `job_heartbeats` | `service/ops_dashboard_models.go:49-55`；`service/ops_health_score.go:15-71` | 可以，适合做首页的“总体健康”卡片 |
| 账号可用性 | 按平台、分组、账号统计 available/rate_limit/error 数量，并给出剩余秒数 | `admin.go:214`；`service/ops_realtime_models.go:53-91` | **可以**，这是“异常账号”待处理列表的主要来源 |
| 仪表盘账号计数 | `/admin/dashboard/stats` 中的 `error_accounts`、`ratelimit_accounts`、`overload_accounts` | `pkg/usagestats/usage_log_types.go:46-50` | 可以，原生端首页已经在读 stats |
| 告警规则与事件 | 规则 CRUD、事件列表（游标分页，支持 status/severity/时间筛选）、事件状态更新、静默 | `admin.go:218-225`；`service/ops_alert_models.go:77-95` | **可以**：`alert-events?status=firing` 即“未解决告警”，并可直接确认或解决 |
| 预置规则 | 迁移脚本预置了错误率 >5%（P1）、成功率 <95%（P0）、P99/P95 延迟（P2）、CPU（P2）、内存（P1）、并发排队（P1）等规则 | `migrations/033_ops_monitoring_vnext.sql:615-700` | 【推断】P95/P99 两条规则的 `metric_type` 不在当前评估器支持的指标中（`ops_alert_evaluator_service.go:600-617` 的 default 分支返回 false），实际上永远不会触发，需要后端确认 |
| 告警通知渠道 | **只有邮件**：规则级 `notify_email`、最低严重级别过滤、静默；邮件事件包括 `ops.alert`、`ops.scheduled_report`、`account.quota_alert`、`balance.low`、`subscription.expiry_reminder` 等 13 类 | `service/ops_alert_evaluator_service.go:678`；`service/notification_email_service.go:23-35` | 不能直接推送到 App |
| Webhook / IM / 移动推送 | **不存在**。全仓库的 webhook 只有支付回调入站（`/payment/webhook/*`）；未发现 APNs、Telegram、飞书、企业微信等出站推送实现 | `server/routes/payment.go:80-90`；`grep -rli webhook/apns/telegram/feishu/wecom` 只在支付相关文件中命中 | 不能 |
| 错误日志待处理 | request/upstream 错误都有 `resolved` 字段和 resolve 接口 | `admin.go:261-277` | 可以：`resolved=false` 即未处理错误 |
| 渠道监控 V1 / V2 | V1 主动探测（4 种状态，含历史）；V2 基于真实流量的健康矩阵（3 级） | §3.9 | 可以：做成“健康度下降”的卡片 |
| 定时测试 | 每个账号的测试计划和结果 | `admin.go:781-791` | 可以：“最近一次测试失败” |
| 代理到期 | 代理有 `expires_at` 和 `expiry_warn_days`，告警指标中有对应项 | `dto/types.go:447-451` | 可以 |
| 退款申请 | 订单状态 `REFUND_REQUESTED` | `payment/types.go:33`；`payment.go:109` | 可以（站点启用支付时） |
| 风控命中 | 风控日志中的 `flagged`、`auto_banned` | `service/content_moderation.go:414-424` | 可以（站点启用风控时） |
| 版本更新 | `GET admin/system/check-updates` | `admin.go:725` | 可以（低优先级） |
| 系统日志与采集健康 | `system-logs/health`、`ingress-rejections/health`、`auth-cache-invalidation/health` | `admin.go:271-285` | 偶尔使用 |

**结论（【推断】）**
1. 后端已经具备做“待处理事项”首页的数据基础：未解决告警、异常/限流/临时不可调度账号、未处理错误、退款申请、代理到期、监控降级，这些都有现成的接口和可执行动作。
2. 这只能是**拉取式**的：App 在前台轮询，或者在后台刷新时（iOS BGAppRefresh，不保证时间）尽力拉取。后端**没有任何出站推送能力**，要实现“告警推到手机”，必须先在后端新增出站通道（APNs、通用 Webhook，或借助 Bark/ntfy 一类的第三方推送）。这属于后端需求，不在本轮 UI 重构范围内，但信息架构应为“通知中心”预留位置。
3. 告警事件只能精确到分组或平台，所以从告警跳转时，应先进入“分组详情中的异常账号列表”，而不是直接打开某个账号。

---

## 6. 结论：未来移动端信息架构需要容纳的对象与模块

### 6.1 原生端现状与本盘点的关键冲突（直接影响 UI 重构）

1. 【事实】账号运行时阻断字段没有解码（§3.1 C），状态只能显示“正常/参与调度”这类静态文字，最重要的“限流/过载/临时不可调度”及其倒计时缺失。**这是“状态徽章”体系的前置数据缺口。**
2. 【事实】账号状态映射缺少 `disabled`（`AccountPresentation.swift:86`）。
3. 【事实】账号的恢复动作（clear-error、clear-rate-limit、temp-unschedulable 清除、recover-state、reset-quota）一个都没有接入。手机上“看到问题却无法处置”。
4. 【事实】登录只放行 admin，vendor 和普通用户都被拒绝（`APIClient.swift:248`）。
5. 【事实】日志分成 usage、request-errors、upstream-errors 三个来源，而后端已有统一的 `ops/requests` 下钻接口和 `request_id` 关联（§1.1、§4）。

### 6.2 分层清单

**A. 本轮管理端必须容纳**（高频移动，且原生端已部分实现或存在关键缺口）

| 模块 / 对象 | 需要容纳的能力 | 依据 |
| --- | --- | --- |
| 首页 · 待处理与健康 | 未解决告警（`ops/alert-events`）、异常账号计数与清单（`dashboard/stats` 加 `ops/account-availability`）、未处理错误数、健康分（`ops/dashboard/overview`），以及现有的费用/请求/Token 卡片 | §5 |
| 对象：上游账号 | 三层状态徽章与倒计时；恢复动作（clear-error、clear-rate-limit、清除临时不可调度、recover-state、reset-quota）；启停调度、刷新、测试；上游额度窗口（`:id/usage`）按需加载；相关日志、错误、分析；分组、代理、母账号跳转 | §1.2、§3.1、§4 |
| 对象：用户 | 查找、详情、启停、余额调整（已有）；**余额流水**（`users/:id/balance-history`）；Key 列表与换分组（`admin/api-keys/:id`）；相关日志与分析 | §1.2 |
| 对象：分组 | 容量、启停（已有）；今日/昨日费用（`groups/usage-summary`）；组内账号、Key、订阅；相关日志与分析 | §1.2 |
| 日志与错误（统一请求流） | 成功与失败统一时间线（`ops/requests` 或保持现有三源），用 `request_id` 串联上游重试和系统日志；错误“标记已处理”；日志中的对象全部可点击跳转 | §1.1、§3.6-3.7、§4 |
| 告警事件 | 列表、详情、确认/解决、静默 | §1.1、§3.8 |
| 角色与开关适配 | 按 `ops_monitoring_enabled`、渠道监控、支付、订阅等设置显示或隐藏模块；step-up 二次验证的统一交互 | §1.6 |

**B. 近期候选**（偶尔使用，但对象上下文清晰，适合在手机上完成）

- 渠道监控：V2 overview、snapshot、errors 只读看板；V1 结果查看与手动 run（§1.4）。
- 代理：列表、测试、质量检测、挂载的账号、到期提醒（§1.2）。
- 订阅：挂在用户或分组详情下，提供延期、重置额度、撤销/恢复（§1.3）。
- 支付订单：退款申请审批、补单 retry、订单查询、支付概览只读（§1.3）。
- 兑换码：单张生成 / create-and-redeem（客服补偿）（§1.3）。
- 公告：发布、归档、查看已读情况（§1.3）。
- 风控日志与解封、操作审计日志只读（§1.4）。
- 定时测试结果只读、系统版本更新提示（§1.2、§1.5）。
- vendor 角色视图：账号、代理、分组，以及受限的看板（§1.6）。

**C. 普通用户端（未来；本轮只作为信息架构约束）**

- 必须容纳的对象：**我的余额/概览、API Key、用量与错误、订阅进度、公告、渠道状态**（§2，均为高频）。
- 偶尔使用：兑换、订单查看与退款申请、个人资料、2FA、Passkey、邀请返利、可用渠道、模型广场、Key 免登录额度查询。
- 【推断】对信息架构的约束：底部导航与“对象中心”的组件（Key 卡片、用量时间线、额度进度条、状态徽章）应设计为**管理端与用户端共用**，只按角色裁剪模块；“充值/购买”建议始终跳转 Web（§2 中关于 App Store 的说明）。

**D. 保持 Web**

系统设置（9 个标签页）与 Claude 魔改设置、备份与数据管理、系统更新/回滚/重启、插件、渠道定价、账号新建/OAuth 授权/批量导入导出/凭据批量更新、错误透传规则、TLS 指纹模板、告警规则与 Ops 运行时配置、分组的计费/模型白名单/组合路由编辑、工作区授权、用户属性定义、用量清理任务、支付商与套餐配置、批量生图、自定义页面。理由见 §1.5 和 §0.2：配置面巨大、需要文件或浏览器回调、需要 step-up 或会覆盖整个库。

### 6.3 需要信息架构“预留但本轮不实现”的位置（【推断】）

- **通知中心**：后端目前只有邮件，没有推送（§5）。预留入口，供日后接入 APNs 或 Webhook。
- **多角色切换**：admin、vendor、user 三种视图（§1.6、§2）。
- **站点功能开关驱动的模块显隐**：渠道监控、支付、订阅、邀请返利、风控、插件、Ops（§1.6）。
