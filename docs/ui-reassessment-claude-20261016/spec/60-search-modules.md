# 60 · 搜索目录与其他模块

> 本章覆盖：搜索 Tab（目录首屏 `SearchHome`、全局搜索结果与“查看全部”结果页）；设置（界面模式、外观、安全与 Face ID 覆盖清单、通知、站点与凭据，含添加站点 / 登录页布局、登录设备 A07、管理访问令牌 A08、推送通知 A11）；兑换码（`redeem` 行内展开、`redeemDetail` 深链定位、编辑 `redeemEdit`、批量生成 `redeemGenerate`、待核对 `redeemReconcile`、发放兑换码（补偿）`redeemGrant`，见第 19 节）；代理（`proxies`、`proxyDetail`、被改走的账号、`proxyEdit`）；公告（`announcements`、`announcementDetail`、`announcementEdit`、`announcementReads`）。
>
> 登录流程、验证码桥页、凭据存储、退出顺序、推送协议（注册参数、载荷、深链）以 `00-conventions.md` 为准（§1.3–§1.9、§7），本章只写这些页面的布局与本章特有的行为，不另写一套文案。
>
> 依据：`DECISIONS.md`（第 2 轮“设置入口在搜索目录”“搜索首屏目录”“兑换码、代理、公告都能管理”“删除藏 ··· 最后”“高风险验证”；第 3 轮 Q9–Q12 以更正为准：兑换码 = 行内展开 + 编辑 sheet，代理 / 公告 = 列表 + 详情 + 编辑 sheet，批量生成 = 分步向导）；设计稿 `html-preview/layouts/main/00-core.jsx`（`SearchHome`、`SettingsScreen`、`confirmDelete`）、`v-modules.jsx`（已定变体见 `v-decided.jsx`）、`tools/routes/modules.json`、`core.json`、`zz-cross.json`；后端 sub2 `main` `70116315d`（A02、A04、A07、A08、A09、A11、E02、G01、G03–G08、H01–H08 均已上线，口径以 `BACKEND-API-CHANGES.md` 实现进度表备注为准）；`sub2/docs/API_ERROR_CODES.md`。
>
> 下文接口路径都相对 `/api/v1`，字段名逐个对过后端源码；“后端位置”路径相对 `sub2/backend/internal/`。金额、紧凑数、相对时间格式沿用 10 章 0.4（`DashboardPresentation` 新增函数）；“今天 / 昨天”的日界按服务器时区（10 章 0.3）。
>
> 设计稿里没选中的变体（兑换码 base 列表 + 详情页、批量生成单页表单、代理 / 公告 inline 卡片）不实现。

---

## 0. 本章共用口径

### 0.1 路由（本章新增的 `NavigationStack` 目的地与 sheet）

| 页面 | 路由 | 从哪进 | 设计稿 |
|---|---|---|---|
| 搜索目录 | 搜索 Tab 根视图 | Tab 栏右侧独立搜索按钮 | `SearchHome` |
| 全局搜索结果 | 搜索 Tab 根视图的搜索态 | 点目录顶部“搜索全部对象” | 设计稿只画了输入框，结果按附录 B L21 定 |
| 搜索结果 · 查看全部 | `.searchResults(kind: .accounts \| .users \| .groups \| .proxies, query: String)` | 全局搜索各分区底部“查看全部 N 个 ›” | 设计稿未画（2.1） |
| 设置 | `.settings(focus: .interface \| .sites)` | 目录“界面与模式”“站点与凭据” | `SettingsScreen` |
| 添加站点（登录） | sheet `.addSite`；无活动站点时为根视图 | 设置 → 添加站点 | 现有 `LoginView` |
| 登录设备 | `.sessions` | 设置 → 当前站点 | 设计稿未画（A07） |
| 管理访问令牌 | `.accessTokens` | 设置 → 当前站点 | 设计稿未画（A08） |
| 推送通知 | `.push` | 设置 → 通知 | 设计稿未画（A11） |
| 兑换码 | `.redeem(open: Int?, query: String?, status: String?, type: String?, reconcile: Bool)` | 目录；概览待处理；补偿回执“查看兑换码” | `screen:redeem` = `inline` |
| 兑换码定位（`redeemDetail`） | 统一落到 `.redeem(open: id)` | 深链 | 已定方案没有独立详情页（`vmoShowCode`） |
| 编辑兑换码 | sheet `.redeemEdit(id)` | 卡片按钮 / 滑动“续期” | `sheet:redeemEdit` |
| 生成兑换码 | sheet `.redeemGenerate` | 兑换码 `+` | `sheet:redeemGenerate` = `steps` |
| 核对结果 | sheet `.redeemReconcile(batchID)` | 待核对横幅“核对”、概览待处理 | `sheet:redeemReconcile` |
| 发放兑换码（补偿） | sheet `.redeemGrant(userID: Int64, pendingID: UUID?)` | 用户详情 ··· “发放兑换码（补偿）…”（30 章 §2.4）；设置 → 待核对 · 补偿发放；概览待处理（10 章） | `sheet:redeemGrant`（`v-modules.jsx` `VmoGrantSheet`） |
| 代理 | `.proxies(filter: String?)` | 目录 | `screen:proxies` = `base` |
| 代理详情 | `.proxyDetail(id)` | 代理行；账号详情的代理行；全局搜索 | `screen:proxyDetail` |
| 被改走的账号 | `.proxyFallbackAccounts(id)` | 代理详情 · 有效期分区 | 设计稿未画（H03） |
| 编辑 / 添加 / 续期代理 | sheet `.proxyEdit(id: Int?)` | 代理 `+`、详情按钮与 ··· | `sheet:proxyEdit` |
| 公告 | `.announcements(seg: String?)` | 目录 | `screen:announcements` = `base` |
| 公告详情 | `.announcementDetail(id)` | 公告行 | `screen:announcementDetail` |
| 已读情况 | `.announcementReads(id)` | 公告详情 · 投放 | `screen:announcementReads` |
| 编辑 / 新建公告 | sheet `.announcementEdit(id: Int?)` | 公告 compose、详情“编辑” | `sheet:announcementEdit` |

### 0.2 用到的 capability（`GET /admin/me` → `data.server.capabilities`）

| capability | 后端条目 | 有它时 | 没有时（老服务端） |
|---|---|---|---|
| `redeem_codes.stats` | G08 | `GET /admin/redeem-codes/stats` 是真实计数；同时推断 G03（`batch_id`、`notes` 生成参数与列表过滤）、G04（`types` / `exclude_types`）已部署（G08 的过滤参数就是 G03 / G04 的参数，同一轮上线） | 状态胶囊不显示数字；“全部类型”不带 type、在客户端剔除 `admin_balance` / `admin_concurrency`；生成核对走 11.4 的老退路 |
| `redeem_codes.delete_guard` | G07 | 删除已兑换的码返回 409 `REDEEM_CODE_USED`；不存在返回 404 | App 照样不给已兑换的码“删除”（与 Web 一致），不依赖后端拦截 |
| `proxies.fallback_accounts` | H03 | 代理有 `fallback_account_count`；可列出并批量恢复被改走的账号 | 详情只写“要改回来，在账号详情里点‘恢复原代理’”，不提供批量恢复页 |
| `announcements.read_stats` | H06 | 列表 / 详情显示已读进度；已读名单可按已读 / 未读、是否符合条件筛选，可按阅读时间排序 | 只有“已读情况 ›”入口与按邮箱 / 用户名 / 余额排序的分页名单 |
| `announcements.idempotent_create` | H07 | 新建公告带 `Idempotency-Key`，超时可同 key 重发 | 照常带 key（老服务端忽略）；超时**不要**自动重发，按标题搜最近几条核对 |
| `admin.access_tokens` | A08 | 显示“管理访问令牌”入口（列表与吊销；首版不在 App 内签发，见第 6 节） | 隐藏入口 |
| `push.notifications` | A11 | 显示“推送通知”入口 | 隐藏入口 |
| `auth.captcha_provider` | A09 | 登录请求可带 `captcha_provider` / `aliyun_captcha_param` | 登录前看不到 admin/me，改用公开设置里**有没有 `captcha_provider` 键**判断（API_ERROR_CODES） |

没有 capability、靠响应判断的：A07 会话列表（`GET /auth/sessions` 返回 404 = 老服务端，隐藏“登录设备”）；H01（`latency_checked_at` 键是否存在）；H02（`GET /admin/proxies/:id` 有没有 `account_count` 键）；G03（生成响应头有没有 `X-Redeem-Batch-ID`）。

本章列表接口（兑换码、代理、公告、已读名单、会话、令牌、推送设备）后端都**没有 ETag**（B09 只做了 stats / users / groups），不发 `If-None-Match`。

### 0.3 身份与权限

| 身份（`admin/me.auth_method`） | 本章差异 |
|---|---|
| `jwt`（邮箱 + 密码 + TOTP） | 全部可用；本章需要 step-up 的写操作只有改 APNs 配置（`PUT /admin/push/config`），站点开启二次验证时按 00 §2.6 弹 `StepUpView` |
| `admin_api_key` | 以第一个管理员身份操作（附录 B L3）；没有会话 → 隐藏“登录设备”；**站点开启二次验证（`security.step_up_enabled == true`）时**不能改 APNs 配置（403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`），关闭时可以改（step-up 中间件先看站点开关、开关关闭直接放行，之后才拒绝机器凭据，`server/middleware/step_up.go:100,104`）；推送设备登记在第一个管理员名下 |
| `admin_access_token`（`sat_…`） | 以签发人身份操作；APNs 配置同 Admin Key（开启二次验证时不能改）；**只读令牌**（`scope=read`）所有写方法返回 403 `ACCESS_TOKEN_READ_ONLY`，例外：撤销自己、推送设备的登记 / 删除 / 改订阅 / 测试（且只能登记 iOS），改 APNs 配置不在例外里（00 §2.6.3） |

**只读令牌的识别（全 App 通用，不只本章）**：`admin/me` 没有 scope 字段（`handler/admin/me_handler.go:185-193` 的 `meResponse`）。`auth_method == admin_access_token` 时，`AppModel.connect` 在 `admin/me` 之后紧接着调一次 `GET /admin/access-tokens`，取 `current == true` 那项的 `scope`，存进 00 §9.5 的 `SiteSession`（新增 `accessTokenScope: String?`）；全 App 的写按钮按 00 §1.6 第 3 条置灰（旁注“只读令牌”），各页面读 `session.isReadOnlyToken`，不各自请求。这次请求失败时按读写处理（服务端仍会用 `ACCESS_TOKEN_READ_ONLY` 拦下，App 按 00 §2.6.3 提示）。这条规则应收进 00 §1.6（见文末审查记录）。

vendor（`admin/me.workspace != null`）是否允许登录 App 由通用约定章节决定；若允许，本章按下表隐藏（`server/middleware/vendor_routes.go:113-114` 注释：兑换码、公告、用户、运维为站长专属）：

| 模块 | vendor 可见条件（`workspace.permissions`） |
|---|---|
| 兑换码、公告、管理访问令牌、推送通知 | 一律不可见 |
| 代理（只读） | `proxy_manage` 或 `account_manage` |
| 代理写操作（新建、编辑、停用、测试、质量检测、删除） | `proxy_manage` |
| 恢复被改走的账号 | `proxy_manage` 且 `account_manage` |
| 登录设备 | 可见（`/auth/sessions` 对所有 JWT 开放） |
| 全局搜索各分区 | 见 2.2 |

### 0.4 本章复用的交互规则

- **删除确认**（通用组件，设计稿 `confirmDelete`）：标题“删除<对象>「名称」？”，正文第一行“站点 X · 删除后不能恢复。”，第二行写后果；设置里关闭 Face ID 时要输入完整名称（兑换码输入末 4 位，大小写都算对）才能点红色“删除<对象>”；打开 Face ID 时不输入，按钮是“用 Face ID 删除”，点后系统验证。删除一律放 ··· 最后（或详情页最后一行）、红字，不放进滑动操作（推送接收方式也一样，见 7.4）。
- **Face ID 门槛**：覆盖范围以 3.4 的“Face ID 覆盖清单”为准（全 App 唯一来源）；打开后，确认后再验证（`LAPolicy.deviceOwnerAuthentication`，允许回退到锁屏密码）。
- **可逆操作**（启用 / 禁用兑换码、停用 / 启用代理、归档公告）：直接执行，回执 toast 带“撤销”（5 秒，撤销 = 把旧值写回去）。
- **敏感值**：兑换码、代理密码、sat_ 原文（登录时粘贴的）、推送 secret、APNs 私钥只放内存，不落盘、不进缓存、不写日志（凭据本身按 00 §1.1 存 Keychain；发放补偿的待核对记录按 19.4 例外保存 code）；复制用 `UIPasteboard.general.setItems(_:options:)` 带 `.localOnly: true`，代理 URL 另加 `.expirationDate` 120 秒。
- **幂等键**：UUID v4 小写；在用户确认那一刻生成，失败后“原样重试”沿用，改了请求体就换新 key；`IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` 按 `Retry-After` 等待后同 key 重试（规则与解码在通用约定章节）。
- **错误**：按 `reason` 分支（附录 B L1）；下文每页只列本页特有的 reason，401 / 423 / 429 / 网络错误走通用处理。

---

## 1. 搜索 Tab · 目录首屏

### 1.1 入口与导航

- 底部 Tab 栏右侧独立的玻璃搜索按钮（`Tab(role: .search)`，四个主 Tab 为 概览 · 账号 · 用户 · 监控，Tab 结构由导航章节改）。搜索 Tab 自带 `NavigationStack`，根视图就是目录。
- 首屏是目录，**点搜索框才弹键盘**（DECISIONS 第 2 轮）：`.searchable(text:placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全部对象")` 挂在搜索 Tab 内部的根视图上（不挂在 `TabView` 上），`TabView` 设 `.tabViewSearchActivation(.automatic)`。iOS 27 上分离的搜索按钮可能并入 Tab 栏，须实机验证（见未决问题 1）。
- 导航栏：大标题“搜索”，副标题“账号、用户、请求 ID、Key 片段”。
- 目录项去向：

| 分组（序号） | 项 | 去向 |
|---|---|---|
| 壹 记录 | 使用记录 | 日志章节 `.logs(scope: .usage)` |
| | 错误请求 | 日志章节 `.logs(scope: .errors)` |
| | 告警事件 | 切到 监控 Tab 的“告警”分段（设计稿此项未接线，见未决问题 2） |
| 贰 资源 | 分组 | 50 章 `.groups` |
| | 统计分析 | 统计章节 `.analytics` |
| | 兑换码 | 第 8 节 |
| | 代理 | 第 12 节 |
| | 公告 | 第 15 节 |
| 叁 设置 | 界面与模式 | 第 3 节，`focus: .interface` |
| | 站点与凭据 | 第 3 节，`focus: .sites`（滚到“站点”分区） |
| 肆 在 Web 中打开 | 系统设置 | Safari 打开 `<站点>/admin/settings` |
| | 支付与套餐 | Safari 打开 `<站点>/admin/orders/dashboard` |

### 1.2 数据来源

- 目录本身不调接口。
- 可见性读会话级缓存的 `GET /admin/me`：`features.payment_enabled`（“支付与套餐”）、`features.ops_monitoring_enabled`（错误请求、告警事件仍显示，进入后由各章节显示“运维监控未开启”）、`workspace.permissions`（vendor，见 0.3）。

### 1.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 搜索框 | — | 占位“搜索全部对象” | — |
| 分组标题 | 固定 | “记录 / 资源 / 设置 / 在 Web 中打开”，右侧序号“壹 / 贰 / 叁 / 肆” | 某组全被隐藏时整组不显示，序号顺延 |
| 行 | 固定 | 左侧灰色图标 + 名称 + 右侧 chevron（设计稿图标：list、octagon、bell、group、chart、gift、shield、megaphone、sliders、key、web） | — |
| 支付与套餐 | `features.payment_enabled` | — | 为 false 时隐藏 |
| 兑换码、公告 | vendor | — | vendor 隐藏 |
| 代理 | vendor 的 `proxy_manage \|\| account_manage` | — | 都没有时隐藏 |

### 1.4 交互与写操作

- 点行 push 对应页面；“在 Web 中打开”两项用 `openURL` 交给 Safari（复用 Safari 里的 Web 登录态，不用 `SFSafariViewController`）。
- 无写操作。

### 1.5 状态

- `admin/me` 还没取到：先按站长身份显示全部项，取到后按权限收起；`admin/me` 失败不影响目录。

### 1.6 刷新策略

无网络请求，不刷新。`admin/me` 的刷新由通用约定章节负责（切站点、回到前台）。

### 1.7 对现有代码的改动点

- `NativeApp/Sub2MobileApp.swift:ManagementView` → 删除；“请求记录与错误日志”“统计分析”“分组管理”三项并入目录。`MainTabs` 去掉“管理”“设置”两个 Tab（导航章节负责 Tab 结构）。
- 新增 `NativeApp/Features/Search/SearchHomeView.swift`：目录 `List(.insetGrouped)` + `.searchable`；搜索文本为空时显示目录，非空时显示第 2 节的结果视图。
- `NativeApp/Features/SettingsView.swift:SettingsView` 不再作为 Tab 根，改由目录 push（第 3 节）。

---

## 2. 全局搜索结果

### 2.1 入口与导航

- 在目录顶部搜索框输入即进入；清空或点“取消”回到目录。
- 结果行点击：账号 → 账号详情（账号章节）；用户 → 用户详情（用户章节）；分组 → `.group(id)`（50 章）；代理 → `.proxyDetail(id)`；请求 → 请求详情（日志章节）。
- 账号、用户、分组、代理四个分区底部“查看全部 N 个 ›”：在**搜索 Tab 自己的栈里** push `.searchResults(kind:query:)`，不跳到账号 Tab / 用户 Tab / 分组列表 / 代理列表。原因：账号列表不放搜索框（20 章 §1.1），用户、分组、代理列表的路由都没有“预填搜索词”参数，分组与代理列表是本地过滤。结果页见 2.3 末尾。
- 请求分区没有“查看全部”：请求 ID 是精确匹配，正常只有一两条；本分区一次取 20 条（2.2），还有更多时分区底部写“只显示前 20 条”。日志路由（40 章 §0.1）没有 `request_id` 参数，不要跳到 `.logs`。

### 2.2 数据来源

后端没有全局搜索接口（附录 B L21；可选的 `GET /admin/search` 未做）→ App 并发扇出，账号、用户、分组、代理各取前 5 条，使用记录与错误请求各取前 20 条。防抖 300ms；去首尾空白后少于 2 个字符不发；新输入时取消上一轮全部请求（`Task` 取消）。

| 分区 | 接口 | 参数 | 发不发 |
|---|---|---|---|
| 账号 | `GET /admin/accounts` | `search=<q>&lite=1&page=1&page_size=5` | 站长；vendor 需 `account_manage \|\| monitor_view` |
| 用户 | `GET /admin/users` | `search=<q>&page=1&page_size=5`（匹配邮箱、用户名、备注与 Key 片段；Key 片段命中时返回 Key 的所属用户，`repository/user_repo.go:553-561`） | 仅站长（vendor 不能读用户，E02 / L5） |
| 分组 | `GET /admin/groups` | `search=<q>&page=1&page_size=5` | 站长；vendor 需任一分组 / 账号 / 监控档 |
| 代理 | `GET /admin/proxies` | `search=<q>&page=1&page_size=5`（只按名称包含匹配，`repository/proxy_repo.go:398`） | 站长；vendor 需 `proxy_manage \|\| account_manage` |
| 使用记录 | `GET /admin/usage` | `request_id=<q>&page=1&page_size=20&key_view=masked`（精确匹配，`repository/usage_log_repo_query.go:120-123`；不传时间范围 = 全部时间；`total` 为 null，看 `has_more`） | 仅当 q “像请求 ID”；vendor 需 `monitor_view`（结果里的用户已打码，E02） |
| 错误请求 | `GET /admin/ops/request-errors` | `request_id=<q>&view=all&time_range=30d&page=1&page_size=20`（默认窗口只有 1 小时，必须显式传 `time_range`；`view=all` 与“客户端最终收到 ≥ 400”一致） | 仅当 q 像请求 ID 且 `features.ops_monitoring_enabled`；仅站长（ops 不对 vendor 开放） |

“像请求 ID”：去空白后不含空格与 `@`，长度 8–256（见未决问题 13）。

`GET /admin/usage/search-api-keys` 只按 Key **名称**匹配（`repository/api_key_repo.go:705-707`），不能用来按 Key 片段找 Key，不要用。

### 2.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 分区标题 | 固定 | “账号 / 用户 / 分组 / 代理 / 请求”，右侧 `total`（各接口分页信封的 `total`）；请求分区右侧写已显示条数（`admin/usage` 的 `total` 为 null） | 分区无结果时整区不显示 |
| 账号行 | lite 列表项 | 复用账号章节的三行账号行（名称、平台 · 分组、状态徽章与胶囊） | — |
| 用户行 | `username`、`email`、`balance`、`status` | 左：用户名（空时用邮箱）+ 邮箱；右：余额 `$1,284.50`；禁用用户整行变淡并带“禁用”徽章 | 邮箱、用户名、备注都不含 q 时，第二行末尾加“· Key 片段匹配” |
| 分组行 | `name`、`platform`、`status` | 名称 + 平台中文名；停用分组带“停用”徽章 | — |
| 代理行 | 同 12.3 的代理行 | 名称、`协议 · host:port`、延迟或状态 | — |
| 请求行 | 使用记录 / 错误请求列表项 | 复用日志章节的 `LogRow`（左列时间 + 状态码，中间模型 / 用户 · 账号，右列金额 + 首字 / 耗时） | — |
| 查看全部 | 账号 / 用户 / 分组 / 代理分区，`total > 5` | “查看全部 N 个 ›” | `total ≤ 5` 不显示；请求分区没有此行，`has_more == true`（或错误请求 `total > 20`）时写“只显示前 20 条” |
| 底部说明 | vendor 时 | “当前身份看不到用户与错误请求” | — |

**“查看全部”结果页**（`.searchResults(kind:query:)`）：

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 导航栏 | `kind`、`query` | 标题“账号 / 用户 / 分组 / 代理”，副标题“搜索“q” · N 个”（`total`） | — |
| 数据 | 2.2 同一接口、同一 `search`（账号仍带 `lite=1`） | `page_size=20`，触底加载下一页；行组件与本页相同，点行去向同 2.1 | 空：“没有匹配“q”的<对象>” |
| 失败 | — | 首页失败 `FailureView`；翻页失败底部“加载失败 · 重试” | — |

### 2.4 交互与写操作

只读，无写操作。点行 push；滚动时收起键盘（`.scrollDismissesKeyboard(.immediately)`）。

### 2.5 状态

| 情况 | 显示 |
|---|---|
| 搜索中 | 每个将要出现的分区一行占位“搜索中…” |
| 全部为空 | “—”空态 + “没有匹配“q”的账号、用户、分组、代理或请求” + “清除搜索” |
| 某分区失败 | 该分区只剩一行“这一类暂时搜不到 · 重试”（重试只重发这一路） |
| 某分区 403 / `OPS_DISABLED` | 静默不显示该分区 |
| 全部失败 | `FailureView`（“暂时无法加载” + 重试） |

### 2.6 刷新策略

不轮询、不下拉刷新；同一个 q 在本页存活期间缓存 30 秒（返回目录再输入同一个词直接用缓存）。“查看全部”结果页进入时加载第 1 页，支持下拉刷新，不轮询。

### 2.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/GlobalSearch.swift`：`GlobalSearchQuery`（`isRequestIDLike`、各分区是否发送的判定，输入 `admin/me` 的身份与权限）、扇出结果结构 `GlobalSearchResults`（每区 `BlockState`，10 章 0.5）、`SearchResultKind`（`.accounts / .users / .groups / .proxies`，产出各自的分页请求）。
- `Sources/Sub2Core/APIClient.swift:pagination(_:search:status:)` 把 `page_size` 写死为 20 → 加 `pageSize` 参数（默认 20）；`accounts(page:search:status:platform:)` 增加 `lite` 与 `pageSize`。
- 用户列表复用 `users(page:search:status:)`（加 `pageSize`）；分组复用 `GroupManagement.swift:groups(page:search:platform:status:)`；请求复用 `RequestLogs.swift:requestRecords / errorRecords`（`RequestLogFilter` 加 `requestID` 与 `timeRange`，若日志章节尚未加）。
- 新增 `NativeApp/Features/Search/GlobalSearchResultsView.swift`、`SearchResultsListView.swift`（“查看全部”结果页，按 `kind` 复用账号章节的账号行、用户章节的用户行、50 章的分组行、12.3 的代理行）。

---

## 3. 设置（界面与模式 · 站点与凭据）

### 3.1 入口与导航

- 目录“界面与模式”→ 本页顶部；“站点与凭据”→ 同一页，`ScrollViewReader` 滚到“站点”分区。导航栏：返回 + 标题“界面与模式”（focus=sites 时为“站点与凭据”）+ 副标题“设置”。
- 本页去向：添加站点（sheet，第 4 节）、登录设备（第 5 节）、管理访问令牌（第 6 节）、推送通知（第 7 节）、金额门槛（sheet）、打开 Web 后台（Safari）。

### 3.2 数据来源

- 本机设置（`UserDefaults`，不分站点）：`ui.mode`（`main` / `simple`）、`ui.appearance`（`system` / `light` / `dark`）、`security.faceID.enabled`（Bool）、`security.faceID.threshold`（Decimal 字符串，默认 `100`，设计稿 `FACE_ID_LIMIT`）。
- 站点列表：`AppModel.profiles`、`activeProfile`（现有）。
- 当前站点身份：`GET /admin/me` 的 `auth_method`、`user{id,email,username,role}`、`security.totp_enabled`、`server.capabilities`。
- 推送状态行：第 7 节的本机设备记录（本地保存的 device id + `GET /admin/push/devices` 结果）。
- 待核对：`AppModel.pendingBalances`（现有；00 §2.5.5 泛化为 `pendingWrites` 后读其中的余额类）、`AppModel.pendingRedeemBatches`（第 11 节新增）、`pendingWrites` 中 `kind == .redeemGrant` 的补偿发放记录（第 19 节）。

### 3.3 字段 → 显示映射

| 分区 / 行 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 壹 界面模式 · 主模式 | `ui.mode == main` | 单选圆点；副行“概览 · 账号 · 用户 · 监控，适合日常处理” | — |
| 壹 · 简化模式（表格） | — | 副行“视图列表 + 表格，适合快速筛查大量数据”；行置灰，尾部“设计中” | 首版不可选（未决问题 3） |
| 贰 外观 | `ui.appearance` | 跟随系统 / 浅色 / 深色 三个单选 | 默认跟随系统 |
| 叁 安全 · 高风险操作需要 Face ID | `security.faceID.enabled` | 开关；副行“删除、批量操作、更换账号凭据，以及超过门槛的充值 / 退款、新建用户初始余额、余额兑换码和余额补偿”（与 3.4 的覆盖清单一致，清单改了这里跟着改） | 设备不支持生物识别时开关置灰，副行改“这台设备没有设置 Face ID / 触控 ID” |
| 叁 · 金额门槛 | `security.faceID.threshold` | 右侧 `$100`；副行“单笔或合计超过这个金额时验证” | 开关关闭时不显示本行 |
| 肆 通知 · 推送通知 | 第 7 节本机设备状态 | 右侧“已开启” / “未开启” / “已停用”（设备被停用） | 无 `push.notifications` 或 vendor 时整个分区不显示 |
| 伍 站点 · 站点行 | `profile.name`、`profile.baseURL.host` | 头像为名称首字；第二行 host（等宽）；当前站点右侧“当前” | — |
| 伍 · 添加站点 | — | “+ 添加站点” | — |
| 陆 当前站点 · 身份 | `admin/me.user.email`、`role` | “admin@example.com · 管理员” | `admin/me` 未取到时“—” |
| 陆 · 认证方式 | `admin/me.auth_method`（缺失时用 `profile.authentication`）；只读与否读 `SiteSession.accessTokenScope`（0.3） | `jwt`“邮箱和密码”；`admin_api_key`“Admin Key · 以第一个管理员身份操作”；`admin_access_token`“访问令牌 · 只读 / 读写” | scope 未取到时只写“访问令牌” |
| 陆 · 登录设备 | `auth_method == jwt` 且 `GET /auth/sessions` 不是 404 | “登录设备 ›”，右侧数量 | Admin Key / 访问令牌登录时显示为不可点，副行“Admin Key 与访问令牌没有登录会话” |
| 陆 · 管理访问令牌 | `admin.access_tokens` | “管理访问令牌 ›”，右侧有效令牌数 | 无 capability 或 vendor 时隐藏 |
| 陆 · 打开 Web 后台 | `profile.baseURL` | Safari | — |
| 陆 · 退出并清除凭据 | — | 红字 | — |
| 柒 待核对 · 余额请求 | `pendingBalances` | 沿用现有 `SettingsView` 的“待确认余额请求”分区 | 无记录时不显示 |
| 柒 · 兑换码批次 | `pendingRedeemBatches`（全部站点） | “<站点名> · 20 个 × $10.00 · 合计 $200.00 · 5 分钟前”；当前站点的行“去核对 ›”，其他站点的行“打开原站点核对” | 无记录时不显示 |
| 柒 · 补偿发放 | `pendingWrites` 里 `kind == .redeemGrant`（全部站点） | “<站点名> · 向 王小明 发放 $10.00 余额 · 5 分钟前”；当前站点的行“去核对 ›”→ 打开 `.redeemGrant(userID:pendingID:)` 的核对页（19.4）；其他站点的行“打开原站点核对” | 无记录时不显示 |
| 捌 关于 | `CFBundleShortVersionString` | 沿用现有 | — |

### 3.4 交互与写操作

- **界面模式**：点“主模式”无变化；简化模式不可选。
- **外观**：写 `ui.appearance`，`RootView` 上 `.preferredColorScheme(nil / .light / .dark)` 立即生效。
- **Face ID 开关**：打开时先 `LAContext().canEvaluatePolicy(.deviceOwnerAuthentication)`，再 `evaluatePolicy` 验证一次，成功才写入 true；关闭时同样验证一次再写 false（未决问题 9）。验证失败或取消保持原值，不弹错误。
- **金额门槛**：sheet 内大数字键盘（复用用户章节的 KeypadSheet 输入规则，整数美元 1–100000），保存写 `security.faceID.threshold`。
- **切换站点**：点非当前站点 → `AppModel.switchTo(_:)`（现有），切换中行尾转圈，期间禁用其他站点行。
- **删除站点**：站点行 ··· → “删除站点和凭据”（红），确认框沿用现有文案；该站点用管理访问令牌登录时，正文加一行“同时吊销这个管理访问令牌”（00 §1.7.5 第 3 条）。执行顺序按 00 §1.1“删除站点”与 §1.7.5，用该站点的凭据依次：① 本机登记过推送设备 → `DELETE /admin/push/devices/:id`（失败记“待删除”，不阻断）；② `sat_`：`GET /admin/access-tokens` 找 `current == true` 的那条 → `DELETE /admin/access-tokens/:id`（只读令牌也允许吊销自己；失败不阻断，回执加“令牌未能吊销，可用 API 吊销”）；JWT：`POST /auth/logout`（带 `refresh_token` 与 `Authorization`）；Admin Key：无；③ `AppModel.remove(_:)`（删除 Keychain 凭据与 `deviceID`）。
- **退出并清除凭据**：确认框沿用现有文案；顺序按 00 §1.7.5（先删推送设备——会话吊销不会自动删除设备，A11 部署注意；JWT 再调 `auth/logout`；只是退出时**不**吊销 sat_）；最后 `AppModel.logout()` 本地擦除。
- 本页无幂等写入。

**Face ID 覆盖清单**（全 App 唯一来源；设置“高风险操作需要 Face ID”打开时生效，门槛为 `security.faceID.threshold`；各章引用本表，不另列）：

| 操作 | 何时验证 | 所在章节 |
|---|---|---|
| 删除任何对象（账号、用户、Key、分组、兑换码、代理、公告、推送接收方式） | 打开时不输入名称，按钮“用 Face ID 删除”，点后验证 | 0.4 删除确认；20 §0.4、30 §2.4 / §7、50 章、本章 8 / 13 / 16 / 7 |
| 批量操作（账号批量调度、批量编辑等） | 执行前 | 20 §0.4 第 4 条、§8 |
| 更换账号凭据：更换 API Key、重新授权 | 点底部红色按钮后、提交前 | 20 §0.4 第 2 条 |
| 充值 / 退款 | 金额超过门槛 | 30 §3.4 |
| 新建用户初始余额 | 初始余额超过门槛 | 30 §5 |
| 生成余额兑换码 | 合计（面值 × 数量）超过门槛 | 本章 10.3 |
| 发放余额补偿 | 金额超过门槛 | 本章 19.4 |
| 揭示完整 Key | **总是**验证，不受开关影响 | 30 §7 |

开关关闭时以上都不验证（揭示完整 Key 除外）；删除改为输入名称确认。

### 3.5 状态

| 情况 | 显示 |
|---|---|
| `admin/me` 失败 | 身份行“—”，认证方式按本地 `profile.authentication`；其余正常 |
| 切换站点失败 | 根视图通用错误弹窗（现有 `RootView` alert） |
| 待核对文件不可读 | 沿用现有：顶部红字“未决记录无法读取，已暂停新的余额操作 / 兑换码生成 / 补偿发放” |

### 3.6 刷新策略

本地设置即时生效；“登录设备 / 令牌”右侧数量在进入本页时各请求一次（失败不显示数量）；不轮询。

### 3.7 对现有代码的改动点

- `NativeApp/Features/SettingsView.swift:SettingsView` → 重写为上表分区；保留现有“站点”“待确认余额请求”“关于”的逻辑与确认框文案；删除站点 / 退出前插入推送设备清理，删除 sat_ 站点时插入令牌吊销（3.4）。
- `NativeApp/Session/AppModel.swift:remove(_:)`：按 3.4 的顺序先删推送设备、吊销 sat_ / 调 logout，再删凭据；`connect` 里为 sat_ 补取 scope（0.3）。
- 新增 `NativeApp/Session/AppPreferences.swift`（`@Observable`，封装四个 `UserDefaults` 键）与 `NativeApp/Session/BiometricGate.swift`（`func confirm(reason:) async -> Bool`、`func needsVerification(amount: Decimal) -> Bool`，以及按 3.4 覆盖清单定义的 `enum GatedAction`，供全 App 的删除、资金确认调用）。
- `NativeApp/Sub2MobileApp.swift:RootView` 加 `.preferredColorScheme(preferences.colorScheme)`。
- `NativeApp/Resources/Info.plist` 加 `NSFaceIDUsageDescription`：“用于确认删除、批量操作、更换账号凭据和超过门槛的资金操作”。

---

## 4. 添加站点（登录）

> 流程、探测、凭据存储与错误文案一律按 00 §1.3–§1.6、§1.9（旧服务端）、§1.10（合规）执行。本节只写登录页的布局与本章入口相关的部分；00 改了，这里不跟着另写。

### 4.1 入口与导航

- 设置 → 站点 → 添加站点（sheet，带“取消”）；没有活动站点时为根视图（现有 `RootView`）。
- 登录成功后关闭 sheet，切到新站点的概览 Tab。添加失败不替换当前已连接的站点（00 §1.1）。

### 4.2 数据来源

| 用途 | 接口 | 关键参数 / 字段 |
|---|---|---|
| 站点信息与验证码 | `GET /settings/public` | 成功且带 `version` 才算 Sub2 站点（00 §1.1）；`site_name`（名称框为空时预填）、`captcha_provider` 与旧服务端三个开关（00 §1.5）、`mobile_verify_path`、`backend_mode_enabled`、`login_agreement_enabled` / `login_agreement_mode` / `login_agreement_documents`（00 §1.4 第 1 步）、`totp_enabled`（`handler/dto/settings.go:387-436`） |
| 密码登录 / 两步验证 | `POST /auth/login`、`POST /auth/login/2fa` | 请求体与 `client{type,device_id,device_name}` 按 00 §1.2、§1.4；验证码证明的字段映射按 00 §1.5 的表 |
| 校验身份 | `GET /admin/me` | 00 §1.9。404 且不是 JSON = 旧服务端：JWT 并发调 `auth/me`、`settings/public`、`admin/compliance`；**Admin Key / sat_ 调 `GET /admin/compliance`** 当权限探针（不再用 `admin/dashboard/realtime`） |
| sat_ 的 scope | `GET /admin/access-tokens` | 只在 `auth_method == admin_access_token` 时，见 0.3 |

`mobile_verify_path` 的含义（A09 进度表“部署注意”）：非空说明桥页已打包进后端二进制（`web/embed_on.go:462-472`，值固定为 `/mobile/verify`，`web/mobile_verify.go:7`）；为 `""` **不代表没部署**——前端单独部署（非 `-tags embed` 构建）的站点恒为 `""`（`web/embed_off.go:50-53`），桥页可能照样存在。

### 4.3 字段 → 显示映射（登录页布局）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 站点地址 | 用户输入 | 只接受 `https://host[:port]`（00 §1.1） | — |
| 站点名称 | 用户输入；空时用 `site_name` | — | 两者都空时提交报“请填写站点名称” |
| 登录方式 | — | 三个选项，按 00 §1.3 的顺序：“账号和密码（推荐，默认选中）”/“管理访问令牌”/“Admin Key（不推荐）” | — |
| 令牌 / Key 输入框 | 后两个选项共用 | `SecureField`，标签“管理访问令牌或 Admin Key”（00 §1.6）；粘贴的值以 `sat_` 开头时自动切到“管理访问令牌”（00 §1.3） | — |
| 选项说明 | 当前选项 | 管理访问令牌：“以签发它的管理员身份操作，可只读、会过期、能单独吊销。”；Admin Key：00 §1.3 原文“以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。” | — |
| 登录协议 | `login_agreement_*` | 按 00 §1.4 第 1 步（勾选框或弹出确认） | 未开启不显示 |
| 后端模式提示 | `backend_mode_enabled` | 00 §1.4 文案“站点处于后端模式，仅管理员可登录” | — |
| 验证码桥页提示条 | `mobile_verify_path == ""` | 桥页 sheet 顶部一行：“若页面无法完成验证，请改用 Web 登录或 Admin Key”（00 §1.5） | 非空时不显示 |
| 两步验证 | `requires_2fa` | 底部 6 位输入（00 §1.4 第 3 步） | — |
| 登录后身份确认 | `admin/me.user.email` | 回执“已连接 · 以 admin@example.com 身份操作” | — |

### 4.4 交互与写操作

- **提交（账号和密码）**：校验 URL（现有 `AppModel.validatedURL`）→ `settings/public` → 需要验证码时：
  - `captcha_provider == "conflict"`（或旧服务端开了不止一个）：按 00 §1.5 停止登录。
  - 其他需要验证码的情况**一律打开桥页**，不因 `mobile_verify_path == ""` 拒绝：加载 `<站点><path>?nonce=<新 UUID>`，`path` = `mobile_verify_path` 非空时用它，否则用 `/mobile/verify`；为 `""` 时显示 4.3 的提示条；只有页面**加载失败**才提示 00 §1.5 的“站点未部署手机验证页，请改用 Web 或关闭验证码”。
  - 时限按 00 §1.5：桥页自身 2 分钟，App 端 180 秒（现有 `CaptchaView` 已是 180 秒）；证明只用一次。
  - → 登录 → 需要时两步验证 → 角色检查（00 §1.4 第 4 步）→ `admin/me` → `AppModel.connect`。
- **提交（管理访问令牌 / Admin Key）**：按 00 §1.6 带 `x-api-key` 调 `admin/me`；sat_ 再取 scope（0.3）。
- **凭据存储**按 00 §9.4：`AuthenticationKind.accessToken`、`Credential.accessToken(String)`（不再借用 `.adminKey`）；旧数据里 `.adminKey` 的值以 `sat_` 开头时迁移成 `.accessToken`。两者都放 `x-api-key` 头（00 §0 第 2 条）。
- **错误**：全部按 00 §1.4 的错误表与 §1.6 第 2 条的文案处理（含 `CAPTCHA_PROVIDER_MISMATCH` 重新拉公开设置再验证、`TOTP_*`、`BACKEND_MODE_ADMIN_ONLY`、`INVALID_ADMIN_KEY`、`ACCESS_TOKEN_EXPIRED`、`RATE_LIMITED` 倒计时）；`compliance.required == true` 进入 00 §1.10；登录响应 `refresh_token_unavailable == true` 按 00 §1.4 第 5 步在概览顶部显示横幅（概览布局见 10 章）。本节不另写文案。

### 4.5 状态

提交中按钮转圈、表单禁用（现有）；验证码 sheet 不能下滑关闭（现有）。

### 4.6 刷新策略

无。

### 4.7 对现有代码的改动点

- `NativeApp/Features/LoginView.swift:submit()`：去掉“提供方不在 turnstile / tencent / aliyun 里就报‘暂不支持原生验证’”的分支，改为 4.4 的 `conflict` 判断 + 一律打开桥页；登录方式改为三个选项与 sat_ 自动识别；登录成功后用 `admin/me` 的身份做回执；凭据用 `.accessToken`。
- `Sources/Sub2Core/Models.swift:PublicSettings`、`AuthenticationKind`、`Credential`：按 00 §9.4。
- `Sources/Sub2Core/APIClient.swift:LoginBody`、`verifyAdministrator()`：按 00 §9.1（`client`、`captcha_provider`、`aliyun_captcha_param`；改调 `me()`，旧服务端 Admin Key 探针用 `admin/compliance`）。
- `NativeApp/Features/CaptchaView.swift`：`CaptchaRequest` 增加 `path: String`（由 4.4 的规则算出）与 `showsFallbackHint: Bool`（`mobile_verify_path == ""`）；`CaptchaWebView.makeUIView` 的 `components.path` 改用 `request.path`（现在写死 `/mobile/verify`，`CaptchaView.swift:42`，非空的 `mobile_verify_path` 目前也是这个值）；`CaptchaView` 顶部按 `showsFallbackHint` 显示提示条；`didFailProvisionalNavigation` 的文案改为 00 §1.5 的“站点未部署手机验证页，请改用 Web 或关闭验证码”。

---

## 5. 登录设备（会话列表，A07）

### 5.1 入口与导航

- 设置 → 当前站点 → 登录设备（仅 `auth_method == jwt`）。标题“登录设备”，副标题站点名。只读页面，无下钻。

### 5.2 数据来源

- `GET /auth/sessions` → `data.items[]`：`id`、`device_name`、`client_type`、`user_agent`、`ip`、`created_at`、`last_seen_at`、`expires_at`、`current`（`handler/auth_sessions_handler.go:12-22`）；按 `last_seen_at` 倒序，最多 50 条。
- 404 → 老服务端：本页不可进入（设置行已隐藏）。

### 5.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 图标 | `client_type` | `ios` iPhone、`android` 手机、`web` 地球 | 空串（部署前已存在的会话）用问号图标 |
| 标题 | `device_name` | 原样 | 空时：UA 含 `Sub2Mobile` → “Sub2 Mobile（iOS）”；否则 `user_agent` 截前 40 字；都空“未知设备” |
| 本机徽章 | `current` | “本机” | — |
| 第二行 | `ip`、`last_seen_at` | “203.0.113.24 · 3 分钟前活跃”（相对时间） | IP 空时只写活跃时间 |
| 第三行 | `created_at`、`expires_at` | “登录于 10/17 09:41 · 11/16 到期” | — |
| 列表底部说明 | 固定 | “部署新版本前登录的设备，下一次自动续期后才会出现在这里。” | — |

### 5.4 交互与写操作

- **下线某台设备**：非本机行 `.swipeActions(edge: .trailing)` “下线”（红）→ 确认框“让「设备名」下线？该设备需要重新登录。”→ `DELETE /auth/sessions/:id` → 删除该行，toast “已下线「设备名」”。响应 `data.current == true`（理论上不会，本机行不给滑动）时按本机退出处理（3.4 退出流程）。`404 SESSION_NOT_FOUND` → 直接删除该行（已不存在）。
- **本机行**：不给滑动；点按弹说明“这是本机。要退出请用设置里的“退出并清除凭据”。”（未决问题 12）。
- **让其他所有设备下线**：列表底部红字按钮（只有一条以上时显示）→ 确认框“让其他 N 台设备下线？它们需要重新登录，本机不受影响。”→ `POST /auth/revoke-all-sessions`，请求体 `{"keep_current": true}`（`handler/auth_handler.go:851-878`）→ 重新加载列表。
- 不需要 step-up；不需要幂等键（重发结果相同）。

### 5.5 状态

| 情况 | 显示 |
|---|---|
| 加载中 | 列表占位 |
| 只有本机 | 本机一行 + “没有其他设备登录” |
| 失败 | `FailureView` + 重试 |
| 401 | 通用重新登录 |

### 5.6 刷新策略

进入时加载；下拉刷新；写操作后重载。不轮询。

### 5.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/AuthSessions.swift`：`AuthSessionItem`（Decodable）、`APIClient.sessions()`、`revokeSession(id:) -> Bool(current)`、`revokeOtherSessions()`。
- 新增 `NativeApp/Features/Settings/SessionsView.swift`。
- 设备名依赖登录时带 `client.device_name`（4.2），否则 iOS 会话也显示“Sub2 Mobile（iOS）”。

---

## 6. 管理访问令牌（sat_，A08）

> 首版**不在 App 内签发**令牌，只列出与吊销（00 §1.3 与 00 未决问题 3 的默认；本章未决问题 10）。sat_ 只能粘贴使用（第 4 节）。

### 6.1 入口与导航

- 设置 → 当前站点 → 管理访问令牌（`admin.access_tokens`，vendor 不可见）。标题“管理访问令牌”，副标题站点名。没有 `+`、没有新建 sheet。

### 6.2 数据来源

- `GET /admin/access-tokens` → `data.items[]`：`id`、`name`、`prefix`（如 `sat_3f9a`）、`last4`、`scope`（`read` / `write`）、`expires_at`、`last_used_at`、`last_used_ip`、`created_at`、`current`（`handler/admin/access_token_handler.go:28-40`）；只含当前管理员未吊销、未过期的令牌。Admin Key 登录时列的是第一个管理员的令牌。
- `DELETE /admin/access-tokens/:id` → `{message, current}`。
- 不调用 `POST /admin/access-tokens`（签发；路由挂 step-up，且 handler 对 Admin Key / sat_ 一律返回 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`，`access_token_handler.go:58-61`）。

### 6.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 顶部说明 | 固定 | “访问令牌以签发它的管理员身份调用管理接口，可只读、会过期、能单独吊销。比 Admin Key 安全：Admin Key 以第一个管理员身份操作，丢了只能到 Web 重新生成。” | — |
| 行标题 | `name` | 原样 | — |
| 权限徽章 | `scope` | `read` “只读”（neutral）、`write` “读写”（caution） | — |
| 本机徽章 | `current` | “本机”（本 App 正在用这个令牌） | — |
| 掩码 | `prefix`、`last4` | 等宽“sat_3f9a…c71e” | — |
| 使用情况 | `last_used_at`、`last_used_ip` | “最近使用 3 分钟前 · 203.0.113.24” | `last_used_at` 为 null：“从未使用” |
| 到期 | `expires_at` | “2027/01/16 到期 · 还剩 87 天”；≤ 7 天时 caution 色 | — |

### 6.4 交互与写操作

- **吊销**：行滑动“吊销”（红）→ 确认框“吊销「名称」？用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。”；是本机那条（`current == true`）时正文加“本机会退出这个站点。”→ `DELETE /admin/access-tokens/:id` → 删除该行。
  - 吊销本机那条：先按 00 §1.7.5 第 1 步删本机推送设备（令牌吊销后就删不掉了），再发 DELETE；响应 `current == true` → 本机凭据已失效，本地擦除（不再调 logout 接口），提示“已吊销本机正在使用的令牌，请重新登录”。
  - `404 ACCESS_TOKEN_NOT_FOUND` → 删除该行。
- 只读令牌只能吊销自己（00 §2.6.3），其余行不给滑动。
- 吊销可以重发（结果相同），不带幂等键；不需要 step-up。

### 6.5 状态

| 情况 | 显示 |
|---|---|
| 空 | “还没有访问令牌” + 说明“首版 App 不签发访问令牌。” |
| 失败 | `FailureView` |

### 6.6 刷新策略

进入时加载；下拉刷新；吊销后重载。

### 6.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/AccessTokens.swift`（`AdminAccessToken`、`APIClient.accessTokens()` / `revokeAccessToken(id:)`，与 00 §9.1 新增方法同名）。
- 新增 `NativeApp/Features/Settings/AccessTokensView.swift`。不新增签发 sheet。

---

## 7. 推送通知（A11）

> 协议层（注册参数与时机、订阅字段、载荷、深链、退出与多站点）以 00 §7 为准；本节写推送设置页的布局、Bark / ntfy / Webhook 的添加与删除、站点 APNs 配置的编辑。00 §7.1 / §7.4 里“请站长在 Web 设置”“其他渠道 App 只读显示”两句与本节不同，按本节执行（Web 没有推送配置界面，见审查记录）。

### 7.1 入口与导航

- 设置 → 通知 → 推送通知（`push.notifications`；vendor 不可见）。标题“推送通知”。
- 去向：其他接收方式的设备详情（同页 push：订阅编辑 + 测试 + 最后一行红字“删除接收方式…”）、“添加 Bark / ntfy / Webhook”（sheet）、“站点 APNs 配置 · 编辑”（sheet）、系统通知设置（`UIApplication.openNotificationSettingsURLString`）。
- 推送点击后的跳转按 00 §7.5（`site` 匹配 `ServerProfile.id.uuidString`、跨站点先切换、凭据已清除先登录）：`push.test` 进入“设置 → 推送通知”（本页）；`site` 匹配不到本机站点时只打开 App、停在概览。

### 7.2 数据来源

| 用途 | 接口 | 字段 |
|---|---|---|
| 我的推送目标 | `GET /admin/push/devices` | `items[]`：`id`、`platform`（`ios` / `bark` / `ntfy` / `webhook`）、`token_hint`（末 4 位）、`endpoint_host`、`bundle_id`、`environment`、`device_name`、`locale`、`timezone`、`site_tag`、`enabled`、`disabled_reason`、`disabled_at`、`last_success_at`、`last_error`、`last_error_at`、`credentials_encrypted`、`subscription{events,min_severity,group_ids,platforms,quiet_hours{start,end}}`、`created_at`、`updated_at`（`handler/admin/push_handler.go:47-68`） |
| 登记 | `POST /admin/push/devices` | iOS：按 00 §7.2 的请求体 `{platform:"ios", apns_token:<hex>, bundle_id, device_name, locale, timezone, site_tag}`，**默认不传 `environment`**（服务端存空串，发送时跟随站点 `apns_environment`，`service/push_device_service.go:177-183`、`service/push_sender_apns.go:109-111`），只有开发构建传 `"sandbox"`；Bark：`{platform:"bark", endpoint, token:<device key>, device_name}`；ntfy：`{platform:"ntfy", endpoint, token:<topic>, secret?:<access token>, device_name}`；Webhook：`{platform:"webhook", endpoint, secret?:<HMAC 密钥>, device_name}`；201 新建 / 200 已存在（`created`） |
| 删除 | `DELETE /admin/push/devices/:id` | — |
| 改订阅 | `PUT /admin/push/devices/:id/subscription` | 整体替换：`{events:[…], min_severity:"P0".."P3", group_ids:[…], platforms:[…], quiet_hours:{start:"HH:MM", end:"HH:MM"} \| null}` |
| 测试 | `POST /admin/push/devices/:id/test` | 成功 `{delivered:true, provider_status}` |
| 站点 APNs | `GET /admin/push/config` / `PUT /admin/push/config`（PUT 挂 step-up，仅站长） | `apns_enabled`、`apns_team_id`、`apns_key_id`、`apns_private_key`（只写）/ `apns_private_key_configured`、`apns_topic`、`apns_environment`、只读 `encryption_key_configured`、`ready`（`service/push_config_service.go:42-63`） |
| 订阅范围选项 | 分组目录 `GET /admin/groups/all?include_inactive=true`（50 章缓存）；平台目录 `GET /admin/meta/catalog`（`meta.catalog`，否则内置平台表） | — |

本机（iOS）设备 id 按站点存本地：`UserDefaults` 键 `push.deviceID.<profileID>`。

### 7.3 字段 → 显示映射

| 分区 / 行 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| APNs 未就绪横幅 | `config.ready == false` | caution：“站点还没配好 APNs，本机收不到推送。可改用 Bark / ntfy / Webhook，或在下方配置 APNs。” | `ready == true` 不显示；GET config 失败不显示 |
| 本机 · 在本机接收推送 | 本机 device id 存在且列表里该设备 `enabled` | 开关 | `config.ready == false` 时置灰、不发起注册（00 §7.1），副行“站点配好 APNs 后才能打开”；GET config 失败时照常可用 |
| 本机 · 状态行 | `last_success_at` / `disabled_reason` / `last_error` | 正常：“已开启 · 上次送达 10/17 09:41”；`unregistered`“设备令牌已失效，关掉再打开即可恢复”；`bad_device_token`“设备令牌无效”；`topic_mismatch`“App 的包名与站点 APNs 配置不符”；`secret_undecryptable`“站点更换了加密密钥，关掉再打开即可恢复”；`last_error` 非空时追加“最近失败：<last_error>” | 从未送达：“已开启 · 还没有送达记录” |
| 系统权限 | `UNUserNotificationCenter` 授权状态 | 被拒：行内“系统设置里关闭了通知 · 去设置” | — |
| 推送内容 · 事件 | `subscription.events` | 四个开关：告警触发（`ops_alert.fired`）、告警恢复（`ops_alert.resolved`）、账号出错（`account.error`）、账号测试完成（`account.test_finished`） | 全关 = `events: []`，副行“已暂停推送” |
| · 告警级别 | `min_severity` | “P1 及以上”（P0–P3 菜单） | 默认 P1 |
| · 平台范围 | `platforms` | “全部平台” / “Anthropic、OpenAI” | 空数组 = 全部 |
| · 分组范围 | `group_ids` | “全部分组” / “高级组 等 3 个” | 空数组 = 全部；全站告警不受范围限制（副行写明） |
| · 免打扰 | `quiet_hours` | 开关 + 开始 / 结束时间（`DatePicker(.hourAndMinute)`），副行“按本机时区 Asia/Shanghai；时段内的事件不补推” | null = 关 |
| · 分区脚注 | 固定 | “同一账号出错 30 分钟内最多推一次；推送最多晚约 15 秒；测试完成只推给发起测试的人。” | — |
| 其他接收方式 · 行 | 列表里除本机外的设备 | 图标按 `platform`；标题 `device_name`（空时 `endpoint_host`）；副行“iOS · …a3f0” / “ntfy · ntfy.sh”；停用时 neutral 徽章“已停用” | — |
| 添加 Bark / ntfy / Webhook | 只读 sat_ 时隐藏 | “+ 添加其他接收方式” | — |
| 测试 | 本机设备存在 | “发送测试推送” | 未开启时置灰 |
| 站点 APNs 配置 | GET config | Team ID、Key ID、私钥“已配置 / 未配置”、Topic（空时“跟随 App 包名”）、环境、状态“可用 / 未就绪” | “编辑”可用条件：不是只读令牌，且（`security.step_up_enabled == false` 或 `step_up_available == true`），与 30 章揭示 Key 的规则相同。否则置灰并注：开启二次验证时用 Admin Key / 访问令牌登录 →“站点开启了二次验证，需要邮箱和密码登录才能修改”；账号没开 TOTP →“需要先在 Web 端开启二次验证”；只读令牌 →“只读令牌” |

### 7.4 交互与写操作

- **打开本机推送**：① `requestAuthorization(options: [.alert, .sound, .badge])`；拒绝 → 提示去系统设置，开关回到关。② `registerForRemoteNotifications()`，拿到 device token（十六进制小写）。③ `POST /admin/push/devices`，请求体按 00 §7.2：`platform:"ios"`、`apns_token`、`bundle_id: Bundle.main.bundleIdentifier`、`device_name: UIDevice.current.name`、`locale:"zh-Hans"`、`timezone: TimeZone.current.identifier`、`site_tag: profile.id.uuidString`（未决问题 8）；`environment`：Release / TestFlight 构建**不传**（跟随站点 `apns_environment`，站长在站点设置里切换时已登记的设备跟着变），只有带 `aps-environment=development` 的开发构建传 `"sandbox"`；**不要显式传 `"production"`**。首次不带 `subscription`（后端默认告警触发 + 账号出错、P1）。④ 保存返回的 `id`。
- **关闭本机推送**：`DELETE /admin/push/devices/:id`，清本地 id。
- **自动重新登记**：系统回调新 token、或成功连接到一个本机开启过推送的站点时，重发一次 POST（同一令牌返回 200、id 不变、重新启用被停用的设备）。
- **改订阅**：每次修改立即 `PUT …/subscription`（整对象），乐观更新；失败回滚并提示。`INVALID_PUSH_SUBSCRIPTION` 按 `metadata.field` 定位（App 正常不会触发）。
- **测试**：`POST …/:id/test` → “已发送测试推送，请看通知”；`503 PUSH_NOT_CONFIGURED`“站点没有配好 APNs”；`502 PUSH_DELIVERY_FAILED`“推送服务没有接受：<metadata.provider_reason>（<metadata.provider_status>）”，随后重载列表（设备可能已被停用）；`404 PUSH_DEVICE_NOT_FOUND` → 清本地 id、重载。
- **添加其他接收方式**（sheet）：平台分段 Bark / ntfy / Webhook；Bark：服务器（默认 `https://api.day.app`）、设备 Key；ntfy：服务器（默认 `https://ntfy.sh`）、主题（字母、数字、`-`、`_`）、访问令牌（可选）；Webhook：URL、签名密钥（可选，脚注“设置后请求带 `X-Sub2-Signature: sha256=HMAC(secret, 时间戳 + "." + 正文)`”）；名称。提交同一 POST。
  - reason：`INVALID_PUSH_TARGET`“地址不被允许：默认只接受公网 https 地址（局域网或 http 需站长打开 push_targets 配置）”；`INVALID_PUSH_TOKEN`“设备 Key / 主题格式不对”；`PUSH_TARGET_IN_USE`“这个接收地址已由另一位管理员登记”；`PUSH_DEVICE_LIMIT_REACHED`“最多 20 个推送目标，先删除不用的”；`ACCESS_TOKEN_READ_ONLY`（只读 sat_）“只读令牌只能登记本机推送”。
- **删除其他接收方式**：不放滑动操作。设备详情最后一行红字“删除接收方式…”→ 通用删除确认（0.4）：标题“删除接收方式「名称」？”（名称 = `device_name`，空时 `endpoint_host`），正文“站点 X · 删除后不能恢复。\n这个地址不再收到推送，要恢复需重新添加。”；Face ID 关时输入完整名称，开时“用 Face ID 删除”→ `DELETE /admin/push/devices/:id` → 返回本页并重载列表，toast “已删除接收方式「名称」”；`404 PUSH_DEVICE_NOT_FOUND` 视为已删除。（本机设备用“在本机接收推送”开关关闭，不走这条。）
- **编辑站点 APNs 配置**（sheet，可用条件见 7.3）：启用开关、Team ID（10 位）、Key ID、私钥“导入 .p8 文件…”（`.fileImporter`，读成 PEM 文本）或粘贴、Topic、环境（production / sandbox）。只提交改过的字段；私钥不改时不传。保存前按 00 §2.6.1 主动判断：`step_up_enabled == true` 且未在授权期内 → 先弹 `StepUpView`；`step_up_enabled == false` 时直接保存（Admin Key / sat_ 也可以，`server/middleware/step_up.go:100`）。仍收到 `403 STEP_UP_REQUIRED` → `StepUpView` 后用户再点保存；`STEP_UP_ADMIN_API_KEY_FORBIDDEN`（站点刚打开二次验证）→ 重新取 `admin/me` 并把“编辑”置灰；`INVALID_APNS_CONFIG` 按 `metadata.field` 标红对应字段（如“启用需要 Team ID、Key ID 与私钥”）；`SECRET_ENCRYPTION_KEY_NOT_CONFIGURED`“站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存”。`encryption_key_configured == false` 时导入按钮置灰并写明原因。私钥文本提交后立即清空。
- **退出 / 删除站点**：先删本机设备（3.4）。

### 7.5 状态

| 情况 | 显示 |
|---|---|
| 列表加载失败 | 本机分区与其他目标分区各一行“加载失败 · 重试”；开关置灰 |
| 登记失败 | 开关回到关 + 错误文案 |
| GET config 403 / 失败 | 不显示 APNs 分区与横幅 |
| 构建没有推送能力（`registerForRemoteNotifications` 失败） | “这个 App 构建没有开启推送能力；APNs 只适用于用站点同一 Apple Team 的 p8 私钥构建的 App。可改用 Bark / ntfy / Webhook。” |

### 7.6 刷新策略

进入时加载设备列表与 APNs 配置；下拉刷新；App 回到前台且停留在本页时重载一次（捕捉被停用的设备）。不轮询。

### 7.7 对现有代码的改动点

- 新增 entitlements 文件（`aps-environment`；用 `interruption-level: time-sensitive` 需另加 Time Sensitive Notifications 能力），`Sub2Mobile.xcodeproj` 打开 Push Notifications capability。Debug 配置用 `aps-environment=development` 的 entitlements，并在同一配置定义编译条件（如 `APNS_SANDBOX`），`PushDeviceRegistration` 只在该条件下带 `environment:"sandbox"`；Release 配置不定义、不带。
- `NativeApp/Sub2MobileApp.swift` 加 `@UIApplicationDelegateAdaptor`：`didRegisterForRemoteNotificationsWithDeviceToken`、`didFailToRegister…`、`UNUserNotificationCenterDelegate`（前台展示 + 点击路由）。
- 新增 `Sources/Sub2Core/Push.swift`（`PushDevice`、`PushSubscription`、`PushAPNsConfig`、`PushDeviceRegistration`、APIClient 七个方法）、`NativeApp/Session/PushCoordinator.swift`（token、按站点保存 device id、重新登记、点击路由按 00 §7.5）、`NativeApp/Features/Settings/PushSettingsView.swift`、`PushTargetDetailView.swift`（订阅、测试、删除）、`PushTargetSheet.swift`、`APNsConfigSheet.swift`。
- `NativeApp/Session/AppModel.swift:logout()` / `remove(_:)` 在清凭据前调 `PushCoordinator.unregister(profile:)`。

---

## 8. 兑换码列表（行内展开，含 `redeemDetail` 定位）

### 8.1 入口与导航

- 目录 → 兑换码；概览待处理“兑换码生成结果待核对”→ `.redeem(reconcile: true)`（横幅高亮，按钮为主样式）；用户章节补偿回执“查看兑换码”→ `.redeem(open: id)`。
- 导航栏：返回 + 标题“兑换码” + 副标题“<站点名> · N 个”+ 右上 `+`（生成）。
- 去向：编辑 sheet（9）、生成 sheet（10）、核对 sheet（11）、··· → 查看使用者 → 用户详情（用户章节）。
- `redeemDetail` 不是独立页面：任何“打开某个兑换码”的入口都落到 `.redeem(open: id)`：列表滚到该卡片并展开；该码不在已加载的页里时先 `GET /admin/redeem-codes/:id`，把它作为“定位的兑换码”单独显示在列表顶部（展开），下面照常是列表。

### 8.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 列表 | `GET /admin/redeem-codes` | `page`、`page_size=50`、`sort_by=id`、`sort_order=desc`、`types=balance,concurrency,subscription,invitation`（排除管理员调整兼容记录，G04；类型菜单选中某一类时改为 `types=<该类>`；不能与 `type` 同传，否则 400 `REDEEM_CODE_TYPE_CONFLICT`）、`status=unused\|used\|expired\|disabled`（状态胶囊）、`search=<q>`（码值包含或使用者邮箱包含，不分大小写，不搜备注，服务端截到 100 字节）、`batch_id=<uuid>`（“查看同一批”） |
| 列表项字段 | `dto.AdminRedeemCode` | `id`、`code`（32 位小写十六进制）、`type`、`value`、`status`（后端已把“未使用但过期”映射成 `expired`，`dto/mappers.go:716-718`）、`used_by`、`used_at`、`created_at`、`expires_at`（可缺）、`group_id`、`validity_days`、`user{id,email,username,…}`（使用者）、`group{id,name,…}`、`notes`、`batch_id`（老码没有）、`created_by` |
| 计数 | `GET /admin/redeem-codes/stats` | 与列表相同的 `types`、`search`（`status` 被忽略）→ `total_codes`、`by_status{unused,used,expired,disabled}`、`by_type`、`total_value_distributed` |
| 单个 | `GET /admin/redeem-codes/:id` | 定位与写后刷新 |

capability：`redeem_codes.stats`（0.2）。缺失时：列表不带 `types`，“全部类型”在客户端剔除 `admin_balance` / `admin_concurrency`（页可能不满 50，继续“加载更多”）；胶囊不显示数字；副标题不显示数量。vendor 不可见。

### 8.3 字段 → 显示映射

**派生**：`redeemed = status == "used" || used_by != nil`（G05 / G07 的“已使用”口径，兑换后又被改成过期 / 禁用的码也算）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 副标题数量 | 不带 search 的 `stats.total_codes` | “主站 · 128 个” | 计数失败或缺 capability 时只写站点名 |
| 待核对横幅 | 第 11 节本机记录（当前站点） | 见 11.3 | 无记录不显示 |
| 搜索框 | — | 占位“搜索兑换码或邮箱” | — |
| 状态胶囊 | `stats.total_codes`、`by_status.*` | “全部 128 / 未使用 40 / 已使用 70 / 已过期 12 / 已禁用 6”，计数随搜索与类型变化 | 计数失败：只显示名称 |
| 类型胶囊 | 当前类型 | 未选“类型”，选中后显示类型名；菜单：全部类型 / 余额 / 并发数 / 订阅 / 邀请码 | — |
| 组头 | `created_at`（服务器时区日界） | “今天生成 / 昨天生成 / 更早生成”，右侧该组已加载条数 | — |
| 卡片头 · 码值 | `code` | 等宽“a3f0····d4e8”（前 4 + 后 4） | — |
| 卡片头 · 面值（右） | `type` + `value` / `validity_days` | `balance` “$10.00”；`concurrency` “+2 并发”；`subscription` “30 天”（`validity_days`）；`invitation` “注册邀请”（灰） | — |
| 卡片头 · 第二行 | 见右 | 前缀 = 订阅码用 `group.name`，其他用类型名（余额 / 并发数 / 邀请码）；`redeemed`：“前缀 · 使用者 · MM/DD”（`used_at`）；`expired`：“前缀 · MM/DD 已过期”；`disabled`：“前缀 · MM/DD 生成”；`unused`：“前缀 · MM/DD 过期”或“前缀 · 永不过期” | 使用者 = `user.username`，空时 `user.email`，`user` 缺失时“用户 #<used_by>” |
| 卡片头 · 状态徽章 | `status` | 未使用（ok）/ 已使用 / 已过期 / 已禁用（neutral） | — |
| 卡片头 · 变淡 | `status != unused` | 整卡 idle 样式 | — |
| 展开 · 码值框 | `code` | 两行各 16 位、每 4 位留空隙（只是排版，复制的是原码）；默认遮罩“a3f0 •••• •••• ••••”/“•••• •••• •••• d4e8”；眼睛图标切换显示，复制图标；VoiceOver 读“兑换码已遮罩，结尾 d4e8”或完整码 | — |
| 展开 · 使用者 | `user` | 可点 → 用户详情 | 只在 `redeemed` 时显示 |
| 展开 · 使用时间 | `used_at` | “10/16 09:20” | 只在 `redeemed` 时显示 |
| 展开 · 生成时间 | `created_at` | “10/16 09:12” | — |
| 展开 · 过期时间 | `expires_at` | “10/23 09:12 · 还剩 7 天”（未使用 / 已禁用；剩 ≤ 1 天 caution 色）；“今天到期”；已过期写“（已过期）” | 缺失：“永不过期” |
| 展开 · 订阅分组 / 有效天数 | `group.name`、`validity_days` | “企业专线”、“30 天” | 只在订阅码显示；`group` 缺失时用分组目录查 `group_id` |
| 展开 · 备注 | `notes` | 原样 | 空：“—” |
| 展开 · 按钮行 | 状态 | 未使用：“禁用 · 编辑 · ···”；已禁用：“启用 · 编辑 · ···”；已过期且未兑换：“续期（主）· ···”；`redeemed`：“编辑备注 · ···” | 只读令牌：只有 ··· 里的复制 |
| ··· 菜单 | — | 标题“a3f0····d4e8”，说明“余额 · $10.00 · 未使用”；项：复制兑换码；查看使用者 <名>（`redeemed`）；查看同一批（有 `batch_id`，未决问题 11）；删除兑换码…（红，最后；`redeemed` 或类型为 `admin_*` 时不出现） | — |

### 8.4 交互与写操作

- **展开**：点卡片头原地展开，同一时间只展开一张（`@State openID: Int?`），展开后 `ScrollViewReader.scrollTo(id)` 滚到能看全（避开浮动 Tab 栏）。卡片内按钮用 `.buttonStyle(.borderless)`。
- **滑动**（只在收起的卡片上）：`.swipeActions(edge: .trailing)` = 禁用 / 启用（未使用、已禁用）或 续期（已过期 → 编辑 sheet）；`.swipeActions(edge: .leading)` = 复制兑换码。删除不放进滑动。
- **禁用 / 启用**：`POST /admin/redeem-codes/batch-update`，`{"ids":[id],"fields":{"status":"disabled"}}`（启用为 `"unused"`）。乐观更新徽章；toast “已禁用 · 不能再兑换” / “已启用 · 可以兑换”，带撤销（写回旧状态）。失败回滚；`409 REDEEM_CODE_USED`“这个码已被兑换，不能再改状态”并 `GET :id` 刷新该卡。成功后重拉 stats。
- **复制**：toast “已复制兑换码”。
- **删除**：确认框（0.4）：标题“删除兑换码「····d4e8」？”，正文“站点 主站 · 删除后不能恢复。\n余额 · $10.00 · 未使用”，输入框“输入末 4 位确认删除”（占位“末 4 位”，`.textInputAutocapitalization(.never)`，大小写都算对）或 Face ID → `DELETE /admin/redeem-codes/:id` → 移除卡片、收起，toast “已删除兑换码「····d4e8」”，重拉 stats。`404 REDEEM_CODE_NOT_FOUND` 视为已删除；`409 REDEEM_CODE_USED`“已被兑换的兑换码不能删除”并刷新该卡。无撤销。
- **查看同一批**：重新加载列表，参数换成 `batch_id=<该码 batch_id>`（不带 `types` / `status`），顶部出现可移除的筛选胶囊“同一批 · 20 个 ✕”。
- **生成**：`+` → 若当前站点有待核对记录，先确认框“上一批兑换码的生成结果未确认”，正文“20 个 × $10.00 · 合计 $200.00\n5 分钟前发起。先核对，避免重复生成。”，按钮“先核对”（默认）/“仍要生成新的一批”/“取消”；否则直接打开生成 sheet。
- 本页写入都是绝对值（batch-update）或天然幂等（delete），不带幂等键。

### 8.5 状态

| 情况 | 显示 |
|---|---|
| 首次加载 | 卡片占位 |
| 没有任何兑换码 | “还没有兑换码” + “生成兑换码” |
| 筛选后为空 | “—”空态 + 有搜索词时“没有匹配“q”的兑换码” + “清除搜索”；否则“没有这类兑换码” |
| 列表失败 | `FailureView` + 重试（胶囊照常） |
| 计数失败 | 胶囊只显示名称，副标题只写站点名 |
| 加载更多失败 | 列表底部“加载失败 · 重试” |
| 定位的码 `404` | toast “这个兑换码已被删除” |
| `400 REDEEM_CODE_TYPE_INVALID` / `REDEEM_CODE_TYPE_CONFLICT` / `REDEEM_BATCH_ID_INVALID` | App 参数错误，按通用“请求无效”处理并上报日志（不含码值） |

### 8.6 刷新策略

首次进入加载第 1 页 + stats；重新显示时距上次加载超过 60 秒则重载；下拉刷新重载第 1 页 + stats；触底加载下一页；写操作后只刷新该卡（`GET :id`）与 stats；生成 / 核对完成后重载第 1 页。不轮询，无 ETag。

### 8.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/RedeemCodes.swift`：`AdminRedeemCode`（`value` 用 `KeyedDecodingContainer.decimal` 解码，`Models.swift:417-431`）、`RedeemCodeListQuery`（产出 query items，含 `types` 规则）、`RedeemCodeStats`、`RedeemBatchUpdateFields`（`expires_at` / `group_id` 需区分“不传”与 `null`，自定义 `encode(to:)`）、`APIClient` 扩展：`redeemCodes(page:query:)`、`redeemCodeStats(query:)`、`redeemCode(id:)`、`updateRedeemCodes(ids:fields:)`、`deleteRedeemCode(id:)`。
- 新增 `NativeApp/Features/Redeem/RedeemCodesView.swift`（列表、胶囊、横幅、定位）、`RedeemCodeCard.swift`（卡片头 + 展开内容 + 按钮行）、`RedeemCodeBox.swift`（码值框，可在生成结果复用）。
- 删除确认、撤销 toast、Face ID 用通用组件 / `BiometricGate`（3.7）。

---

## 9. 编辑兑换码 sheet（`redeemEdit`）

### 9.1 入口与导航

卡片“编辑 / 编辑备注 / 续期”、收起卡片的滑动“续期”。sheet 左上“取消”，右上“保存”（已过期且选了新时间时为“续期”）。

### 9.2 数据来源

- 打开时用列表里的该码；保存用 `POST /admin/redeem-codes/batch-update`，请求 `{"ids":[id],"fields":{…}}`，`fields` 只放改过的键：`status`（只能 `unused` / `disabled`）、`expires_at`（RFC3339，`null` = 永不过期）、`group_id`（订阅码）、`notes`（`dto/types.go:642-650`；`type` / `value` 不能改，`REDEEM_CODE_CORE_FIELDS_IMMUTABLE`）。响应只有 `{updated, message}`，保存后 `GET /admin/redeem-codes/:id` 取最新。
- 订阅分组选项：分组目录（50 章缓存的 `groups/all?include_inactive=true`）里 `subscription_type == "subscription"` 且 `status == "active"` 的分组。

### 9.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 顶部对象条 | `code`、`type`、面值 | “a3f0····d4e8” + “余额 · $10.00 · 面值生成后不能改” | — |
| 已使用横幅（`redeemed`） | `user`、`used_at` | “已使用的兑换码只能改备注。” + “使用者 小王 · 10/16 09:20” | — |
| 只读行（`redeemed`） | 状态、订阅分组、过期时间 | 只读 | — |
| 状态（未使用 / 已禁用） | `status` | 分段“未使用 / 已禁用”，脚注“禁用后不能再兑换，可以随时重新启用。” | — |
| 状态（已过期且未兑换） | — | 只读“已过期”；选了新过期时间后显示“已过期 → **未使用**” | — |
| 订阅分组 | `group_id` | 选项胶囊 | 只在订阅码且非 `redeemed` 时显示 |
| 过期时间 | `expires_at` | 选项：“保持 10/23 09:12”（或“…（已过期）”，有原过期时间时才有）/ 永不过期 / 1 天 / 3 天 / 7 天 / 30 天 / 自定义（`DatePicker` 日期 + 时间，下限为当前时间） | 已过期码分区标题“新的过期时间”，排在最前；脚注按设计稿：“选一个新的过期时间即可续期；保持原时间只改备注。” / “保存后 10/30 09:41 过期，状态改回“未使用”。” |
| 备注 | `notes` | 多行输入，占位“例如：活动批次、工单号”，脚注“只有管理员看得到。” | — |

### 9.4 交互与写操作

- 计算 `fields`：
  - `redeemed`：只 `notes`。
  - 未使用 / 已禁用：`status`（改了才放）、`group_id`、`expires_at`（选项换算：N 天 = 现在 + N × 24h；永不过期 = `null`；保持 = 不放）、`notes`。
  - 已过期且未兑换：选了新时间 → `expires_at` + `"status":"unused"`；保持 → 只 `notes`。
  - `fields` 为空时“保存”置灰（避免 `REDEEM_CODE_BATCH_UPDATE_EMPTY`）；自定义时间不晚于现在时置灰并在脚注写“过期时间要晚于现在。”
- 成功：关 sheet；toast：续期“已续期 · 10/30 过期，改回未使用”（永不过期写“永不过期”）；只改备注“已保存备注”；其他“已保存兑换码”。刷新该卡与 stats。
- reason：`REDEEM_CODE_USED`（409）→ sheet 不关，切成“只改备注”模式并提示“这个码已被兑换，只能改备注”；`REDEEM_CODE_EXPIRES_AT_INVALID`“过期时间要晚于现在”；`REDEEM_CODE_STATUS_INVALID`、`REDEEM_CODE_GROUP_ID_INVALID`“分组无效，请重新选择”；其余通用。
- 没有幂等键（绝对值写入，超时后重发结果相同）；超时提示“结果未确认”，用户可原样重试。

### 9.5 状态

保存中按钮转圈、表单禁用、`.interactiveDismissDisabled`。

### 9.6 刷新策略

不刷新；打开时以列表数据为准。

### 9.7 对现有代码的改动点

新增 `NativeApp/Features/Redeem/RedeemEditSheet.swift`；接口用 8.7 的 `updateRedeemCodes`。

---

## 10. 批量生成兑换码（分步向导 `redeemGenerate`）

### 10.1 入口与导航

- 兑换码 `+`（8.4 的待核对拦截之后）。sheet 内 `NavigationStack`，步骤条“类型 · 面额与数量 · 有效期”；左上第 1 步“取消”，之后“上一步”。Face ID 验证中不可下滑关闭（`.interactiveDismissDisabled`）。
- 完成后同一 sheet 换成“生成结果”；超时换成“结果待核对”（第 11 节）。

### 10.2 数据来源

- 订阅分组选项：同 9.2。
- 生成：`POST /admin/redeem-codes/generate`，请求头 `Idempotency-Key: <batchID>`，请求体（`handler/admin/redeem_handler.go:37-49`）：

| 类型 | 请求体 |
|---|---|
| 余额 | `{"type":"balance","value":10,"count":20,"expires_in_days":7?,"notes":"…"?,"batch_id":"<batchID>"}` |
| 并发数 | `{"type":"concurrency","value":2,"count":5,…}` |
| 订阅 | `{"type":"subscription","value":0,"group_id":3,"validity_days":30,"count":5,…}` |
| 邀请码 | `{"type":"invitation","value":0,"count":10,…}` |

  `count` 1–100；`expires_in_days` 1–3650，永不过期时不传；`notes` ≤ 1000 字；`batch_id` 与幂等键是同一个 UUID（G03：同一 `batch_id` 且参数一致时直接返回已有整批，不受幂等 24 小时限制）。
- 响应：`AdminRedeemCode` 数组（真实码值，含重放：重放时后端按 `batch_id` 重新查库，`redeem_handler.go:221-228`）；响应头 `X-Redeem-Batch-ID`、`X-Idempotency-Replayed`。请求超时设 45 秒（后端带 key 的资金写执行上限 30 秒，`idempotency_helper.go:155`）。

### 10.3 字段 → 显示映射

| 步骤 / 元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 第 1 步 · 类型磁贴 | 固定 | 余额“余额金额（美元），兑换后计入用户余额。”；并发数“并发数增量，兑换后提高用户的并发上限。”；订阅“兑换后开通或延长所选订阅分组。”；邀请码“邀请码用于限制用户注册，使用后自动标记为已使用。”；点磁贴即进第 2 步；脚注“点一个类型进入下一步；生成前会再确认一次。” | — |
| 第 2 步 · 余额 | 大数字键盘 | 大字“$10”；下方“每个兑换码的面值 · 合计 **$200.00**”；规则同 KeypadSheet：最多 2 位小数、不以 0 开头、最多 6 位数字 | 未输入时“$0”灰色，“下一步”置灰 |
| 第 2 步 · 并发数 | 步进器 1–50 | “增加并发 +2” | — |
| 第 2 步 · 订阅 | 分组胶囊 + 有效天数 | 天数选项 7 / 30（默认）/ 90 / 自定义（1–3650） | 没有订阅分组时“站点还没有订阅类型的分组”，“下一步”置灰 |
| 第 2 步 · 邀请码 | — | 只显示说明 | — |
| 第 2 步 · 数量 | 步进器 1–100 + 快捷 1 / 10 / 20 / 50 / 100 个 | 默认 1（同 Web） | — |
| 第 3 步 · 兑换码过期 | 选项 | 永不过期（默认）/ 1 天 / 3 天 / 7 天 / 自定义天数（1–3650） | — |
| 第 3 步 · 备注 | `notes` | 单行可展开输入，占位“活动批次、工单号（选填）”（G03 新增，设计稿当时后端没有，见未决问题 6） | — |
| 第 3 步 · 收据 | 汇总 | 类型 / 每个“$10.00” / 数量“× 20” / 过期“7 天后过期（10/23）”或“永不过期” / 合计“$200.00”（只余额） | — |
| Face ID 提示 | 余额且 `faceID.enabled` 且合计 > 门槛 | “合计超过 $100，确认后验证 Face ID。” | — |
| 提交按钮 | — | “生成 20 个兑换码”；校验不过时置灰 | — |
| 确认框 | 汇总 | 余额：标题“生成 20 个余额兑换码，合计 $200.00？”，正文“站点 主站 · 每个 $10.00\n7 天后过期（10/23）”（+ Face ID 行），红色按钮“生成 $200.00”；其他类型：标题“生成 5 个并发数兑换码？”，普通按钮“生成 5 个” | — |
| 结果 · 头部 | 响应数组 | 绿色勾 + “已生成 20 个兑换码”；重放时“已生成 20 个兑换码（服务器已有这一批，已取回）”；第二行“余额 · 每个 $10.00 · 10/23 过期” | — |
| 结果 · 全部复制 | 全部 `code` | “全部复制（20 个，每行一个）”，复制后变“已复制全部 20 个” | 只有 1 个时“复制兑换码” |
| 结果 · 码列表 | `code` | 序号 + 完整码（16 + 16 两行，等宽）+ 单个复制 | — |
| 结果 · 脚注 | 固定 | “关闭后在列表的“今天生成”里能找到它们；导出 CSV 请在 Web 操作。” | — |

### 10.4 交互与写操作

1. 点“生成…”→ 确认框 → （需要时）Face ID → 生成 `batchID = UUID()`，**先**写本机待核对记录（第 11 节，状态“发送中”），再发请求。
2. 结果分支：

| 结果 | 动作 |
|---|---|
| 200 | 删除本机记录 → 结果页；列表重载第 1 页 + stats |
| 超时 / 网络错误 / 5xx（含 `503 IDEMPOTENCY_STORE_UNAVAILABLE`） | 保留记录 → “结果待核对”页（11） |
| `409 IDEMPOTENCY_IN_PROGRESS` | 按 `Retry-After`（上限 10 秒）等待后同 key 同体重试，最多 3 次；仍是此码 → 待核对页 |
| `409 IDEMPOTENCY_RETRY_BACKOFF` | 等 `Retry-After` 后同 key 重试一次 |
| `409 REDEEM_BATCH_CONFLICT` | 删除记录，提示“这个编号已用于参数不同的一批兑换码，请重新生成”（App 正常不会触发） |
| `409 REDEEM_CODE_EXPIRED` / 其他 4xx | 删除记录，显示错误（如“过期时间无效”），回到第 3 步 |

3. 结果页“完成”关 sheet。码值只在内存，关闭后丢弃（列表里随时可再看）。
4. 资金确认：余额类按 BUILDER_GUIDE “资金操作必须二次确认，写明对象、站点、金额；不给默认金额”——面值无默认值，数量默认 1。

### 10.5 状态

| 情况 | 显示 |
|---|---|
| 发送中 | 提交按钮“正在生成…”，sheet 不可关闭 |
| Face ID 中 | 覆盖层“Face ID · 验证后生成兑换码”，取消验证 = 不发请求、删掉刚写的记录 |
| 本机待核对文件不可写 | 不发请求，提示“未决记录无法保存，已暂停生成”（同余额调整的现有规则） |

### 10.6 刷新策略

不适用。

### 10.7 对现有代码的改动点

- 新增 `NativeApp/Features/Redeem/RedeemGenerateSheet.swift`（三步 + 结果页 + 待核对页切换）。
- `Sources/Sub2Core/RedeemCodes.swift` 增加 `RedeemGenerateSpec`（Codable，生成请求体，金额用 `Decimal` 编码成 JSON number、最多 2 位小数）与 `APIClient.generateRedeemCodes(spec:batchID:) -> (codes, replayed: Bool)`；`APIClient.request` 需要能返回响应头（`X-Idempotency-Replayed`、`X-Redeem-Batch-ID`、`Retry-After`），由通用约定章节统一加 `requestWithResponse`。
- 键盘复用用户章节 KeypadSheet 的输入规则（提取为 `KeypadInput` 纯函数，便于单测）。

---

## 11. 生成结果待核对（本机记录、横幅、核对 sheet）

### 11.1 入口与导航

- 生成超时后的“结果待核对”页（生成 sheet 内）；兑换码列表顶部横幅“核对”；概览待处理“兑换码生成结果待核对”（10 章）→ `.redeem(reconcile: true)`；设置 → 待核对 → 兑换码批次。
- 核对结果在 sheet 里显示（同 10.3 的结果页，标题“核对结果”）。

### 11.2 数据来源

- **本机记录** `PendingRedeemBatch`（新增，持久化到 `Application Support/Sub2Mobile/pending-redeem-batches.json`，`.completeFileProtection`，读失败时禁止新的生成，同现有 `pendingBalances`）：`id`（= batchID = 幂等键）、`serverID`、`spec`（类型、面值、数量、`group_id`、分组名、有效天数、`expires_in_days`、备注）、`count`、`total`（只余额 = 面值 × 数量，其他为 nil）、`createdAt`。10 章的待处理行读它的 `count`、`total`、`createdAt`。
- **核对**：`GET /admin/redeem-codes?batch_id=<id>&page=1&page_size=100&sort_by=id&sort_order=asc`（G03 过滤；不带 `types` / `status`）。
- **用同一编号重试**：与 10.2 完全相同的请求（同一 key、同一请求体）。

### 11.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 列表横幅 | 当前站点的记录（多条时取最早一条，标题后加“等 N 批”） | caution 横幅 + 图标；标题“兑换码生成结果待核对”；第二行“20 个 × $10.00 · 合计 $200.00”；第三行“5 分钟前发起，未确认是否已生成”；按钮“核对”（从概览进入时为主样式） | 非余额类不写合计 |
| 待核对页 · 头部 | — | 沙漏 + “请求可能已提交” + “没有收到服务器确认。不要重新生成，先核对。” | — |
| 待核对页 · 收据 | 记录 | 内容“20 个 × $10.00”；合计“$200.00”；发起“主站 · 10/16 09:36”；幂等编号（完整 UUID，等宽，可选中） | — |
| 待核对页 · 按钮 | — | “核对生成结果”（主）/“用同一编号重试” | — |
| 待核对页 · 脚注 | 固定 | “编号已保存在本机。核对会按这个编号在服务器上找这一批；用同一编号重试时，服务器生成过就直接返回那一批，不会重复生成。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。” | — |
| 没找到页 | 核对结果 `total == 0` | 放大镜 + “服务器上没有这一批” + “这次生成没有生效。用同一编号重试，或者放弃。”；按钮“用同一编号重试”（主）/“放弃这一批”；脚注“重试用的是本机保存的同一个编号，服务器最多生成一批。” | — |
| 核对结果页 | 核对返回的码 | 同 10.3 结果页，头部“已核对：服务器已生成 20 个”，脚注“这一批是 10/16 09:36 发起时生成的，已在列表的“今天生成”里；导出 CSV 请在 Web 操作。” | — |

### 11.4 交互与写操作

- **核对**：`total == count` → 删除记录 → 核对结果页；`total == 0` → 没找到页；`0 < total < count`（整批一个事务，正常不会出现）→ 显示找到的码 + caution“数量与发起时不符，请到 Web 核对”，记录保留到用户点“我已核对”。
- **用同一编号重试**：同 10.4 第 2 步的分支表；成功（含重放）→ 删除记录 → 结果页。
- **放弃这一批**：删除记录，toast “已放弃这一批 · 不再提醒”。
- 概览待处理、横幅、设置里的同一条记录共用，任何一处核对完成后其余立即消失。
- **老服务端退路**（无 `redeem_codes.stats`、响应没有 `X-Redeem-Batch-ID`）：重试只能同 key 重放，重放里的码值是 `***`，按返回的 `id` 逐个 `GET /admin/redeem-codes/:id` 取真码；核对改为 `sort_by=created_at&sort_order=desc&page_size=100` 后按类型、面值、发起后 2 分钟内、数量启发式匹配，并提示“另一位管理员同时生成时可能分不清”（附录 G03 App 退路）。

### 11.5 状态

核对 / 重试中按钮“正在核对…”/“正在用同一编号重试…”，两个按钮都禁用；核对请求失败 → 提示“核对失败，请稍后再试”，记录保留。

### 11.6 刷新策略

不自动核对（避免在网络恢复前误判“没找到”）；用户点“核对”才发请求。列表横幅随本机记录即时出现 / 消失。

### 11.7 对现有代码的改动点

- `NativeApp/Session/AppModel.swift`：新增 `pendingRedeemBatches`、`rememberRedeemBatch(_:)`、`resolveRedeemBatch(_:)`、持久化文件（照 `remember / resolve / persistPending` 写，独立文件，失败标志与余额共用“未决记录不可读”提示）。
- `Sources/Sub2Core/RedeemCodes.swift`：`PendingRedeemBatch`（Codable）。
- 新增 `NativeApp/Features/Redeem/RedeemReconcileView.swift`（待核对页、没找到页、核对结果页三态）。

---

## 12. 代理列表（`proxies`）

### 12.1 入口与导航

- 目录 → 代理。导航栏：返回 + 标题“代理” + 副标题“<站点名> · N 个” + 右上“全部测试”（文字按钮，测试中为“测试中…”）与 `+`（添加 sheet）。
- 点行 → 代理详情。

### 12.2 数据来源

- `GET /admin/proxies?page=<p>&page_size=200&sort_by=id&sort_order=desc`，循环拉完所有页（代理通常很少；胶囊与横幅需要全集）。
- 列表项 `dto.AdminProxyWithAccountCount`（`handler/dto/types.go:462-531`）：`id`、`name`、`protocol`、`host`、`port`、`username`、`password`（明文，只放内存）、`status`（`active` / `inactive` / `expired`）、`created_at`、`expires_at`（RFC3339，可为 null）、`fallback_mode`（`none` / `proxy` / `direct`）、`backup_proxy_id`、`expiry_warn_days`、`account_count`（`proxy_id` 指向它的账号）、`fallback_account_count`（H03）、`latency_ms`、`latency_status`（`success` / `failed`，未探测过不返回）、`latency_message`、`latency_checked_at`（Unix 秒，H01）、`ip_address`、`country`、`country_code`、`region`、`city`、`quality_status`、`quality_score`、`quality_grade`、`quality_summary`、`quality_checked`（Unix 秒）。
- 测试：`POST /admin/proxies/:id/test` → `{success, message, latency_ms, ip_address, city, region, country, country_code, checked_at}`（`service/admin_service.go:663-673`；失败也是 200 + `success:false`）。
- vendor：读需 `proxy_manage || account_manage`；“全部测试”与 `+` 需 `proxy_manage`。

### 12.3 字段 → 显示映射

**到期计算 `proxyExpiry`**（按服务器时区的自然日差 `d = days(expires_at) − today`，设计稿 `shared/data.jsx:526-535`）：`status == expired` →“MM/DD 已过期”；`expires_at == null` →“永不过期”；`status != active` →“MM/DD 到期”；`d < 0` →“已到期 · 等待处理”（caution）；`d ≤ expiry_warn_days` →“今天到期”/“N 天后到期”（caution，记为 soon）；否则“剩余 N 天”。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 到期横幅（只在“全部”下） | `account_count > 0` 且（`expired` 或 active + soon），已过期排前，再按剩余天数 | 只有 1 个：标题“jp-tokyo-1 已过期，仍有 1 个账号在用” / “hk-02 6 天后到期，3 个账号在用”，第二行“续期，或给这些账号换代理” / “到期前续期，或设置到期回退”；多个：“N 个代理需要处理” + “jp-tokyo-1 已过期仍在用 · hk-02 6 天后到期”；有已过期的为 critical，否则 caution；按钮“查看”→ 切到“已过期”（有已过期仍在用）或“即将到期” | 无命中不显示 |
| 筛选胶囊 | 本地计算 | 全部 / 已过期（有已过期仍在用时带红点）/ 即将到期（active、有账号、soon）/ 链接失败（非停用、`latency_status == failed`、且 active 或有账号）/ 停用；每个带数量 | — |
| 列表头 | 固定 | 左“代理”，右“延迟 / 状态” | — |
| 行 · 状态胶囊 | tone | 停用：无；已过期：有账号 critical，否则无；链接失败：critical；soon：caution | — |
| 行 · 前导字形 | 状态 | 停用 / 已过期无账号：灰；已过期有账号、链接失败：错误；未测试：中性点；其他：正常 | — |
| 行 · 标题 | `name` | 原样 | — |
| 行 · 右侧 | 测试中 / 状态 / 延迟 | 测试中：“测试中”；非 active：状态徽章（正常 / 停用 / 已过期，已过期且无账号为 neutral）；active：`latency_status == success` → “182ms”，`failed` → critical 徽章“链接失败” | active 且未探测：“未测试”（灰） |
| 行 · 地址 | `protocol`、`host`、`port` | 等宽“SOCKS5 · 203.0.113.24:1080”（HTTP / HTTPS / SOCKS5 / SOCKS5H） | — |
| 行 · 底行 | `account_count`、地区、到期 | “3 个账号在用 · 中国香港”；已过期：“1 个账号仍在用 · 10/13 到期” / “没有账号在用 · 10/13 到期”；停用不写地区；soon 时右侧 caution 徽章“6 天后到期”；已过期 + 链接失败 + 有账号时再加“链接失败”徽章 | 地区 = `country_code` 用 `Locale(identifier:"zh_CN").localizedString(forRegionCode:)`，有 `city` 时追加“ · 城市”；都没有就不写 |
| 行 · 变淡 | 停用，或已过期且无账号 | idle | — |

### 12.4 交互与写操作

- **全部测试**：对列表全部代理并发（最多 4 个）`POST /admin/proxies/:id/test`；每行在测试中显示“测试中”；每个返回后按结果更新该行（`success` → `latency_status=success`、`latency_ms`、出口 IP 与地区；失败 → `latency_status=failed`、`latency_message=message`），`latency_checked_at = checked_at`。全部结束 toast “已测试 N 个代理 · M 个失败”（有失败为 critical 色）。HTTP 错误的那一行恢复原值，计入失败。
- **添加**：`+` → 第 14 节 sheet。
- 无滑动操作。

### 12.5 状态

| 情况 | 显示 |
|---|---|
| 加载中 | 行占位 |
| 没有代理 | “还没有代理” + “添加代理” |
| 筛选为空 | “没有这类代理” |
| 失败 | `FailureView`；已拉到部分页时显示已有数据 + 底部“加载失败 · 重试” |

### 12.6 刷新策略

首次进入加载全部页；重新显示时超过 60 秒重载；下拉刷新；写操作 / 测试后更新对应行；不轮询，无 ETag。

### 12.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/Proxies.swift`：`AdminProxy`（全部字段可选解码，`password` 用自定义 `CustomDebugStringConvertible` 屏蔽）、`ProxyTestResult`、`ProxyQualityResult`、`ProxyFallbackAccount`、`ProxyFallbackRevertResult`、`ProxyExpiry`（到期计算纯函数，便于单测）、`APIClient` 扩展（列表、单个、新建、修改、删除、测试、质量检测、账号、回退账号、恢复）。
- 新增 `NativeApp/Features/Proxies/ProxiesView.swift`（列表、胶囊、横幅、全部测试）。
- `Sources/Sub2Core/Models.swift:UpstreamAccount.proxy` 现只解码名称、编号（`docs/API_COMPATIBILITY.md:74`），账号章节的“代理”行改为 push `ProxyDetailView(id:)`。

---

## 13. 代理详情（`proxyDetail`，含被改走的账号）

### 13.1 入口与导航

- 代理行（带上列表那一行，先显示再刷新）；账号详情的代理行（只有 id）；全局搜索。
- 导航栏：返回 + 标题 `name` + 副标题“SOCKS5 · 203.0.113.24:1080” + 右上 ···。
- 去向：“使用该 IP 的账号”行 → 账号详情（账号章节）；“被改走的账号 ›”→ `.proxyFallbackAccounts(id)`；编辑 / 续期 sheet。

### 13.2 数据来源

| 用途 | 接口 | 字段 |
|---|---|---|
| 代理 | `GET /admin/proxies/:id`（H02：与列表同一 DTO，含账号数、延迟、出口 IP、质量、`fallback_account_count`） | 同 12.2；没有 `account_count` 键 = 老服务端，退回 `GET /admin/proxies?search=<名称>&page_size=100` 按 id 找（附录 H02 App 退路） |
| 使用该 IP 的账号 | `GET /admin/proxies/:id/accounts` | `[{id, name, platform, type, notes}]`（只含 `proxy_id` 指向它的账号） |
| 账号状态徽章 | 账号章节的账号状态缓存（`GET /admin/accounts/status-summary?include_accounts=true` 的 `accounts[].state`，或账号 Tab 已加载的列表） | 后端没有“按代理取账号状态” → 缓存里没有该账号就不显示徽章 |
| 备用代理名 | 列表缓存里 `backup_proxy_id` 那一项的 `name` | 不在缓存时 `GET /admin/proxies/:id` |
| 被改走的账号 | `GET /admin/proxies/:id/fallback-accounts` | `[{id, name, platform, type, notes, current_proxy_id, current_proxy_name}]`（`current_proxy_id == null` = 现在直连） |
| 测试 / 质量检测 | `POST /admin/proxies/:id/test`、`POST /admin/proxies/:id/quality-check` | 质量检测返回 `{proxy_id, score, grade, summary, exit_ip, country, country_code, base_latency_ms, passed_count, warn_count, failed_count, challenge_count, checked_at, items[]}` |

### 13.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 状态卡 · 徽章 | `status` | 正常（ok）/ 停用（neutral）/ 已过期（有账号 critical，无账号 neutral） | — |
| 状态卡 · 说明 | 状态 | 测试中“正在测试连通性”；本次会话测过“刚刚测试 09:41”（测试响应的 `checked_at`）；停用：有账号“在用的账号不受影响”，无账号“账号编辑里选不到它” | 其他情况空 |
| 状态卡 · 色调 | 链接失败且（active 或有账号） | critical 底 + 状态胶囊 | — |
| 延迟块 | `latency_status`、`latency_ms`、`latency_message`、`latency_checked_at` | 成功：大字“182 ms” + 0–500ms 游标刻度（超过 500 指针停在最右，墨色无状态色）+ 小字“上次测试 10/16 09:12”（H01）；失败：“链接失败” + `latency_message`（等宽，错误底色） | 未探测：“— 还没测试过”；`latency_checked_at` 缺失时不写测试时间 |
| 事实三格 | `ip_address`、地区、质量 | 出口 IP（等宽）；地区（同 12.3）；质量“A · 92”+ 标签旁日期（`quality_checked` 的 MM/DD）；检测中“检测中…” | 各自“—” |
| 按钮行 | 状态 | 已过期：“续期”（主）+“测试连接”；其他：“测试连接”（主）+“编辑” | 只读身份 / vendor 无 `proxy_manage`：按钮不显示 |
| 壹 有效期 · 说明句 | 见下 | 见下 | 无说明时显示 KV 的“剩余”“到期回退” |
| 壹 · 到期日 | `expires_at` | “2026-10-22” | “永不过期” |
| 壹 · 到期提醒 | `expiry_warn_days` | “提前 7 天” | — |
| 壹 · 剩余 / 到期回退 | `proxyExpiry`、`fallback_mode`、备用名 | “剩余 132 天” / “不限”；“不回退” / “回退直连” / “备用 sg-01” | 有说明句时不显示这两项 |
| 壹 · 被改走的账号 | `fallback_account_count > 0` 且 `proxies.fallback_accounts` | 行“被改走的账号 2 个 ›” | 为 0 不显示 |
| 贰 使用该 IP 的账号 | accounts | 分区 meta“3 个”；行：账号状态字形 + 名称 + 状态徽章，第二行“platform · type” | “暂无账号使用此代理” |
| 叁 连接 | `protocol`、`port`、`host`、`username`、`password`、`created_at` | 协议、端口、主机（等宽）、用户名（等宽）、密码“••••••”、创建时间 | 用户名“—”；密码为空“未设置” |

**说明句**（`vmoExpiryNote`，按 H03 调整）：

| 条件 | tone | 文案 |
|---|---|---|
| 已过期，`account_count > 0`，回退为“不回退” | critical | “已过期，N 个账号仍在用这个代理。到期回退设的是“不回退”，所以账号没被改走；续期，或到账号编辑页换代理。” |
| 已过期，`account_count > 0`，回退不是“不回退” | critical | “已过期，N 个账号仍在用这个代理。续期，或到账号编辑页换代理。” |
| 已过期，`fallback_account_count > 0` | neutral | “到期后已把 N 个账号改为直连 / 备用 sg‑01。续期并启用后，可以在“被改走的账号”里一键恢复。”（无 `proxies.fallback_accounts` 时后半句改为“要改回来，在账号详情里点“恢复原代理”。”） |
| 已过期，其余 | neutral | “已过期，没有账号在用。” |
| 正常，`fallback_account_count > 0`（续期后还没恢复） | caution | “N 个账号在本代理到期时被改走，还没恢复。” |
| 正常，soon，回退“不回退” | caution | “6 天后到期。到期后不回退，在用的 N 个账号会继续挂在这个过期代理上。”（无账号时省略后半句） |
| 正常，soon，其他回退 | caution | “6 天后到期。到期后把在用的账号改为直连 / 备用 sg‑01。” |

（备用名里的连字符用不换行连字符，避免 `sg-01` 在连字符处折行。）

### 13.4 交互与写操作

- **测试连接**：`POST …/test`，按 12.4 更新；说明改为“刚刚测试 HH:MM”。
- **··· 菜单**（标题 `name`，说明“SOCKS5 · host:port”）：编辑代理；复制代理 URL；质量检测；停用代理 / 启用代理 / 续期…（已过期）；删除代理…（红，最后）。
- **复制代理 URL**：本地拼 `protocol://[username[:password]@]host:port`（用户名、密码做 URL 编码），按 0.4 写剪贴板，toast “已复制代理 URL”。
- **质量检测**：`POST …/quality-check`，事实格显示“检测中…”；成功 toast “质量检测完成：评分 92（A）”并更新质量格（`grade`、`score`、`checked_at`）；失败 toast “代理质量检测失败”（critical）。
- **停用 / 启用**：`PUT /admin/proxies/:id`，`{"status":"inactive"}` / `{"status":"active"}`，直接执行；toast “已停用 hk-02 · 在用的 3 个账号不受影响”（无账号时“已停用 hk-02”）/“已启用 hk-02”，带撤销。停用不影响已绑定账号的流量，只是账号编辑里选不到、也不会被选作备用。
- **续期**：打开编辑 sheet（续期模式）。
- **删除**：
  - `account_count > 0` → 说明框“不能删除「hk-02」”：“该代理已有 3 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。”（只有“知道了”）。
  - `fallback_account_count > 0` → 说明框“不能删除「us-east-2」”：“2 个账号到期时从这个代理改走，删除后它们就恢复不了原代理。先恢复这些账号，或在账号详情里处理。”，按钮“查看被改走的账号”/“知道了”。
  - 否则删除确认（输入完整名称 / Face ID）→ `DELETE /admin/proxies/:id` → 返回上一页，toast “已删除代理「名称」”。`409 PROXY_IN_USE` → 有 `metadata.fallback_account_count` 时弹上面第二个说明框，否则弹第一个（重新拉详情取数量）；`404 PROXY_NOT_FOUND` 视为已删除。
- **被改走的账号页**（`.proxyFallbackAccounts(id)`，标题“被改走的账号”，副标题代理名）：
  - 行：名称；第二行“platform · type · 现在：直连”/“现在：备用 sg-01”（`current_proxy_name`）；点行 → 账号详情。
  - 底部主按钮“全部恢复到 hk-02”：仅当代理 `status == active` 且未过期时可点，否则置灰并写“先续期并启用这个代理”。点后确认框“把 N 个账号改回走 hk-02？它们的出口 IP 会变回 203.0.113.24。”→ `POST /admin/proxies/:id/fallback-accounts/revert`，请求体 `{}`（全部，单次最多 500）。
  - 行滑动“恢复”：同一接口，`{"account_ids":[id]}`。
  - 结果 `{reverted_ids, skipped:[{id,code,message}], failed:[{id,code,message}]}`：toast “已恢复 N 个账号到 hk-02”；有 `skipped`（`ACCOUNT_NOT_IN_FALLBACK` / `ACCOUNT_NOT_FALLBACK_OF_PROXY`）时追加“M 个已不在回退状态，已跳过”；有 `failed` 时页内列出失败账号与原因。之后重拉本页、详情与列表。
  - `409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE` →“原代理仍已过期或已停用，请先续期或启用后再恢复”。vendor 需 `proxy_manage && account_manage`。
  - 无 `proxies.fallback_accounts`：没有本页（说明句改写见上）。
- 本页写入都不带幂等键（PUT 绝对值；revert 重复调用安全，H03）。

### 13.5 状态

| 情况 | 显示 |
|---|---|
| 从账号详情进入加载中 | 状态卡占位 |
| `404 PROXY_NOT_FOUND` | “已删除”空页（设计稿 `VmoGone`） |
| 账号列表 / 回退列表失败 | 该分区一行“暂时无法加载 · 重试”，其余照常 |
| 测试请求 HTTP 失败 | toast “测试请求失败，请稍后再试”，延迟块保持原值 |

### 13.6 刷新策略

进入时 `GET :id` + `:id/accounts`；下拉刷新两者；编辑保存后若改了协议、主机、端口、用户名或密码，延迟块改为“地址已修改，正在重新测试”，5 秒后 `GET :id` 一次（H04：后端已自动清缓存并重新探测，App 不要再调 test）；测试 / 质量检测后本地更新。不轮询。

### 13.7 对现有代码的改动点

- 新增 `NativeApp/Features/Proxies/ProxyDetailView.swift`（`init(id:seed:)`，seed 为列表行）、`ProxyFallbackAccountsView.swift`、`ProxyLatencyBlock.swift`（刻度与读数，列表可复用读数格式）。
- 账号状态徽章读账号章节提供的共享状态缓存（不在本章新建请求）。

---

## 14. 编辑 / 添加 / 续期代理 sheet（`proxyEdit`）

### 14.1 入口与导航

- 代理 `+`（添加）、详情“编辑” / ···“编辑代理”（编辑）、已过期代理的“续期”（续期模式）。标题“添加代理 / 编辑代理 / 续期代理”；左上“取消”，右上“添加 / 保存 / 续期”。续期模式顶部对象条“jp-tokyo-1 · SOCKS5H · 192.0.2.88:1080 · 1 个账号仍在用”。

### 14.2 数据来源

- 编辑预填来自详情 / 列表数据（密码不预填）。
- 备用代理候选：代理列表缓存里除自己外的全部代理；可选条件 `status == active` 且未过期（后端回退链会跳过停用或过期的代理），不可选的置灰并标“停用”/“已过期”。
- 添加：`POST /admin/proxies`（可选幂等，scope `admin.proxies.create`），请求体 `{name, protocol, host, port, username, password, expires_at?, fallback_mode, backup_proxy_id?, expiry_warn_days}`；**`expires_at` 是 Unix 秒**（`handler/admin/proxy_handler.go:29-40`），响应 `AdminProxy`（不含延迟；后端新建后异步探测）。
- 编辑：`PUT /admin/proxies/:id`，只放改过的键：`name`、`protocol`、`host`、`port`、`username`（`""` = 清空）、`password`（只在用户输入时放）、`status`（只能 `active` / `inactive`）、`expires_at`（Unix 秒；`null` 或 `0` = 永不过期）、`fallback_mode`、`backup_proxy_id`（`null` = 清除）、`expiry_warn_days`（`proxy_handler.go:43-55`）。

### 14.3 字段 → 显示映射

| 分区 / 元素 | 字段 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 名称与协议 | `name`、`protocol` | 名称（占位“请输入代理名称”）；协议分段 HTTP / HTTPS / SOCKS5（添加默认）/ SOCKS5H；选 SOCKS5H 时脚注“SOCKS5H 由代理服务器解析域名（远程 DNS）。” | — |
| 地址 | `host`、`port` | 主机（等宽，占位“请输入主机地址”）；端口（数字键盘，最多 5 位） | 端口越界脚注“端口必须在 1-65535 之间” |
| 认证（可选） | `username`、`password` | 用户名（等宽）；密码（安全输入，编辑时占位“留空保持不变”） | — |
| 有效期 | `expires_at`、`expiry_warn_days` | 选项：保持 <日期>（编辑且有到期日时；已过期写“（已过期）”）/ 永不过期 / 30 天 / 90 天 / 自定义（天数）；“到期提醒提前”步进器 1–30 天（默认 7）；脚注“到期前按提醒天数在代理列表和告警里提示。”；续期模式标题“有效期 · 续期”，脚注“10/13 已过期。选一个新的有效期来续期。” | 添加默认永不过期 |
| 到期回退 | `fallback_mode`、`backup_proxy_id` | 分段“不回退 / 回退直连 / 备用代理”；选备用代理时出现候选胶囊；脚注：备用“回退链会跳过停用或已过期的代理，所以它们不能选作备用。”；直连“到期后把在用的账号改为直连，可在账号详情里“恢复原代理”。”；不回退“到期后账号留在这个过期代理上，需要手动处理。” | — |
| 状态（仅编辑） | `status` | 分段“正常 / 停用”；已过期代理打开时预设“停用”（PUT 只收 active / inactive，同 Web），选了新有效期自动切回“正常”；脚注按设计稿（`statusFoot`） | — |
| 分区顺序 | 模式 | 续期：有效期 → 状态 → 到期回退 → 名称地址认证；其他：名称地址认证 → 有效期 → 到期回退 → 状态 | — |

### 14.4 交互与写操作

- **校验**：名称、主机非空；端口 1–65535；回退选备用时必须选一个；已过期 + 保持原有效期 + 状态“正常”不允许（脚注“有效期已过，改回“正常”前先在上面选新的有效期。”）。不满足时右上按钮置灰。
- **有效期换算**：N 天 = 现在 + N × 86400 秒；永不过期：添加时不传，编辑时传 `null`。
- **添加**：带 `Idempotency-Key`（sheet 打开时生成；失败后原样重试沿用，改了表单换新 key）→ 成功关 sheet，toast “代理添加成功”带撤销（撤销 = `DELETE /admin/proxies/:id`，此时还没有账号在用）；重载列表，3 秒后 `GET :id` 取探测结果。
- **编辑**：成功关 sheet；toast：续期“已续期 · jp-tokyo-1 恢复正常”，其他“代理更新成功”；改了网络字段时按 13.6 进入“正在重新测试”。
- **reason**：`PROXY_BACKUP_REQUIRED`“选了备用代理回退，请选择一个备用代理”；`PROXY_BACKUP_SELF`“备用代理不能是它自己”；`PROXY_WARN_DAYS_INVALID`、`PROXY_EXPIRY_INVALID`（App 不会发出）；`404 PROXY_NOT_FOUND`（备用代理不存在或不属于本工作区）“备用代理已不存在，请重新选择”；幂等类 reason 走通用处理。编辑超时（无幂等）：提示结果未确认，`GET :id` 读回比对后再决定是否重发。
- 有未保存修改时下滑关闭先确认“放弃修改？”。

### 14.5 状态

保存中右上转圈、表单禁用。

### 14.6 刷新策略

不适用。

### 14.7 对现有代码的改动点

新增 `NativeApp/Features/Proxies/ProxyEditSheet.swift`；`Sources/Sub2Core/Proxies.swift` 的 `ProxyCreateRequest` / `ProxyUpdateRequest`（`username` / `password` / `expires_at` / `backup_proxy_id` 需区分“不传”与 `null`，自定义 `encode(to:)`，参照 `GroupManagement.swift:GroupLimitChange`）。

---

## 15. 公告列表（`announcements`）

### 15.1 入口与导航

- 目录 → 公告。导航栏：返回 + 标题“公告” + 副标题“<站点名> · N 条” + 右上 compose（新建 sheet）。点行 → 公告详情。

### 15.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 列表 | `GET /admin/announcements` | `page`、`page_size=20`、`sort_by=created_at`、`sort_order=desc`、`status=active\|draft\|archived`（分段，“全部”不传）、`include_read_stats=true`（有 `announcements.read_stats` 时） |
| 列表项 | `dto.Announcement`（`handler/dto/announcement.go:9-29`） | `id`、`title`、`content`、`status`（`draft` / `active` / `archived`）、`notify_mode`（`silent` / `popup`）、`targeting{any_of:[{all_of:[{type, operator, group_ids?, value?}]}]}`、`starts_at`、`ends_at`（RFC3339，可缺）、`created_by`、`updated_by`、`created_at`、`updated_at`、`read_stats{eligible_count, read_count, eligible_read_count}`（带参数时） |
| 分段计数 | 同一接口 `page_size=1`，四路并行（不带 status / 各 status）取 `total` | 后端没有公告统计接口 → App 退路 |
| 订阅条件的分组名 | 分组目录缓存（`groups/all?include_inactive=true`） | `group_ids` → 名称 |

vendor 不可见。

### 15.3 字段 → 显示映射

**可见对象文案**：`any_of` 为空 →“所有用户”；否则每组内条件用“ 且 ”连接，组之间用“ 或 ”连接；条件：`subscription` →“订阅 企业专线、高级组”；`balance` →“余额 < $5.00”（`gt` >、`gte` ≥、`lt` <、`lte` ≤、`eq` =）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 分段 | 四路 `total` | 全部 5 / 展示中 2 / 草稿 1 / 已归档 2 | 计数失败只显示名称 |
| 行 · 标题 + 徽章 | `title`、`status` | 草稿（neutral）/ 展示中（ok）/ 已归档（neutral） | — |
| 行 · 第二行 | `targeting` | 可见对象文案（一行截断） | 分组名查不到时“分组 #3” |
| 行 · 第三行 | `notify_mode`、时间 | 图标（弹窗 megaphone / 静默 bell）+ “弹窗 · 10/16 08:00 – 10/18 06:00”（`starts_at` 缺省“立即”，`ends_at` 缺省“永久”）；草稿为“静默 · 更新于 10/16 09:05”；展示中但未到开始时间追加“（未开始）”，已过结束时间追加“（已结束）” | — |
| 行 · 已读进度 | `read_stats`（非草稿） | 第三行右侧“已读 410/1036”（`eligible_read_count / eligible_count`） | 无 capability 不显示（未决问题 5） |
| 行 · 变淡 | `status == archived` | idle | — |

时间按本机时区显示（与编辑页“时间按本机时区”一致）。

### 15.4 交互与写操作

点行 push；compose 新建；无滑动、无写操作。

### 15.5 状态

| 情况 | 显示 |
|---|---|
| 没有公告 | “还没有公告” + “新建公告” |
| 分段为空 | “没有这类公告” |
| 失败 | `FailureView` |

### 15.6 刷新策略

首次进入加载；重新显示超过 60 秒重载；下拉刷新；触底加载下一页；详情 / 编辑写操作后重载第 1 页与计数。不轮询。

### 15.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/Announcements.swift`：`Announcement`、`AnnouncementTargeting` / `ConditionGroup` / `Condition`（Codable，与后端 `domain/announcement.go:40-64` 同形）、`AnnouncementReadStats`、`AnnouncementReadSummary`、`AnnouncementReadStatusRow`、`AnnouncementCreateRequest` / `UpdateRequest`、`AnnouncementPresentation.targetText(_:groupNames:)`、`APIClient` 扩展。
- 新增 `NativeApp/Features/Announcements/AnnouncementsView.swift`。

---

## 16. 公告详情（`announcementDetail`）

### 16.1 入口与导航

- 公告行。导航栏：返回 + 标题“公告” + 副标题“展示中 · 弹窗” + 右上 ···。
- 去向：已读情况（第 18 节）、编辑 sheet（第 17 节）。

### 16.2 数据来源

- `GET /admin/announcements/:id`（有 capability 时带 `include_read_stats=true`）。
- `GET /admin/announcements/:id/read-summary`（有 `announcements.read_stats` 且非草稿）→ `{announcement_id, total_users, eligible_count, read_count, eligible_read_count, computed_at}`（`computed_at` 为 RFC3339 UTC；只统计未删除用户；eligible 按当前余额与当前有效订阅计算；`read_count` 含读后已不符合条件的人）。

### 16.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 预览卡 | `title`、`content`、`notify_mode` | 标签“用户看到的样子 · 弹窗 / 静默”；弹窗：居中卡片 + 底部“知道了”按钮样式；静默：带左侧轨的通知卡；正文按最小 Markdown 渲染（`## 小标题`、`- 列表`、`**粗体**`、`[链接](地址)`、空行分段） | 标题空“未命名公告”；正文空“还没有正文”（灰） |
| 按钮行 | `status` | 草稿：“发布”（主）+“编辑”；展示中：“归档”+“编辑”（主）；已归档：“重新发布”+“编辑”（主） | 只读身份不显示 |
| 壹 投放 · 可见对象 | `targeting` | 15.3 的文案（可换行） | — |
| · 通知方式 | `notify_mode` | 静默 / 弹窗 | — |
| · 开始时间 / 结束时间 | `starts_at` / `ends_at` | “10/16 08:00” | “立即” / “永久” |
| · 已读情况 | read-summary | 有 capability：标题“已读情况”，右侧“已读 410 / 符合条件 1036”，第二行“40% · 另有 2 人读后已不符合条件 · 统计于 09:41”（`read_count − eligible_read_count > 0` 才写中间一句）；无 capability：第二行“逐个用户看：是否符合条件、什么时候读的” | 草稿不显示本行；summary 失败退回无 capability 的文案 |
| 贰 档案 | `created_at`、`updated_at` | 创建时间、更新时间 | — |

### 16.4 交互与写操作

- **发布 / 重新发布**：确认框标题“发布「标题」？”，正文“<可见对象> · 用户打开时弹窗提示 / 静默出现在通知里\n有效期 <开始> – <结束>”，按钮“发布”/“取消” → `PUT /admin/announcements/:id`，`{"status":"active"}` → toast “已发布 · 符合条件的用户能看到”。
- **归档**：直接 `PUT …`，`{"status":"archived"}`；toast “已归档 · 用户不再看到”，撤销 = 写回原状态。
- **··· 菜单**（标题为公告标题，说明“展示中 · 弹窗”）：编辑公告；归档（展示中）/ 发布 / 重新发布；已读情况（非草稿）；删除公告…（红，最后）。
- **删除**：删除确认（输入完整标题 / Face ID）→ `DELETE /admin/announcements/:id` → 返回列表，toast “已删除公告「标题」”；`404 ANNOUNCEMENT_NOT_FOUND` 视为已删除。
- reason：`ANNOUNCEMENT_STATUS_INVALID`（App 不会发出）；其余通用。PUT / DELETE 不带幂等键（天然幂等）。

### 16.5 状态

`404` → “已删除”空页；加载中预览卡占位；写操作中按钮转圈。

### 16.6 刷新策略

进入时加载详情与 summary；下拉刷新；写操作后重载。不轮询。

### 16.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementDetailView.swift`、`AnnouncementPreviewCard.swift`、`MiniMarkdownView.swift`（块级只认 `##`、`-`、空行分段，行内用 `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`）。

---

## 17. 编辑 / 新建公告 sheet（`announcementEdit`）

### 17.1 入口与导航

- 公告列表 compose（新建）；详情“编辑”/ ···“编辑公告”。标题“新建公告 / 编辑公告”；左上“取消”；右上“存草稿”（新建、草稿）或“保存”（展示中、已归档）；底部主按钮“发布”（新建、草稿）/“重新发布”（已归档），展示中没有底部按钮。
- 顶部分段“编辑 / 预览”。

### 17.2 数据来源

- 编辑预填来自详情。订阅分组选项：分组目录里 `subscription_type == "subscription"` 且 `status == "active"`。
- 新建：`POST /admin/announcements`，请求 `{title, content, status, notify_mode, targeting, starts_at?, ends_at?}`（`starts_at` / `ends_at` 为 Unix 秒，缺省 = 立即 / 永久），有 `announcements.idempotent_create` 时带 `Idempotency-Key`（scope `admin.announcements.create`，带 key 时后端执行上限 30 秒）。
- 编辑：`PUT /admin/announcements/:id`，只放改过的键：`title`、`content`、`status`、`notify_mode`、`targeting`、`starts_at`、`ends_at`（`0` = 清空，即改回立即 / 永久）。

### 17.3 字段 → 显示映射

| 分区 / 元素 | 字段 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 内容 · 标题 | `title` | 单行输入，占位“标题” | 超过 200 字节（后端按字节计，`service/announcement_service.go:82`）时脚注“标题太长（最多约 66 个汉字）” |
| 内容 · 格式工具条 | — | 粗体 / 列表 / 小标题 / 链接（在光标处插入 `**粗体**`、`\n- 列表项`、`\n## 小标题`、`[链接文字](https://)` 并选中示例文字）；右侧“N 字” | — |
| 内容 · 正文 | `content` | 多行，占位“写点什么…”；脚注“支持 Markdown：**粗体**、- 列表、## 小标题、[链接](地址)。” | — |
| 可见对象 | `targeting` | 分段“所有用户 / 按条件”；按条件时：分段“订阅套餐 / 余额”；订阅：“持有以下任一套餐”多选胶囊（`{type:"subscription", operator:"in", group_ids:[…]}`）；余额：比较符胶囊 > ≥ < ≤ + “$”金额（`{type:"balance", operator:"lt", value:5}`）。脚注：所有用户“所有用户都能看到。”；按条件“手机上设一个条件；多个条件组合请在 Web 编辑。” | 现有公告是多组 / 多条件：只读显示“条件 … / 或 …”，脚注“这条公告的条件有多组 / 多条，手机上只读；要修改请在 Web 编辑。” |
| 通知方式 | `notify_mode` | 分段“静默 / 弹窗”；脚注“静默：只出现在用户的通知列表里。”/“弹窗模式会自动弹出通知给用户。” | 新建默认静默 |
| 有效期 | `starts_at`、`ends_at` | 开始：“立即 / 指定时间”，结束：“永久 / 指定时间”；指定时间为日期 + 时间两个胶囊（`DatePicker(.compact)`）；脚注“立即 = 开始时间留空；永久 = 结束时间留空。时间按本机时区。” | 结束不晚于开始时脚注“结束时间要晚于开始时间。” |
| 预览 | 当前表单 | 同 16.3 预览卡 | — |

### 17.4 交互与写操作

- **校验**：标题非空且 ≤ 200 字节；正文非空；按条件时订阅至少选一个分组、余额金额 > 0；结束晚于开始。不满足时“存草稿 / 保存 / 发布”置灰。
- **targeting 组装**：所有用户 → `{}`（编辑时从条件改回所有用户也要显式发 `{}`）；单条件 → `{"any_of":[{"all_of":[<条件>]}]}`；多条件只读时编辑**不发** `targeting`（保持原样）。
- **存草稿**（新建 / 草稿）：新建 `status:"draft"`；草稿编辑不改 status → toast “已存为草稿”。
- **保存**（展示中 / 已归档）：不改 status → 展示中 toast “已保存 · 用户看到的是新内容”。
- **发布 / 重新发布**：先确认框（同 16.4，内容取表单）→ 新建 `status:"active"` / 编辑加 `"status":"active"` → toast “已发布公告”。
- **幂等（新建）**：sheet 打开时生成 key；失败后请求体不变就沿用，变了换新 key。`X-Idempotency-Replayed: true` 视为成功；`409 IDEMPOTENCY_KEY_CONFLICT`“该编号已用于另一份公告内容，请重新打开新建页”；`409 IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` 按 `Retry-After` 同 key 重试；超时：有 capability 时同 key 重发一次，仍失败提示结果未确认；无 capability 时**不重发**，`GET /admin/announcements?search=<标题>&sort_by=created_at&sort_order=desc&page_size=5`，最近几分钟有同标题的就提示“上一次可能已经创建成功”，让用户决定（H07 App 退路）。
- **reason**：`ANNOUNCEMENT_TITLE_INVALID`“标题不能为空，最多 200 字节”；`ANNOUNCEMENT_CONTENT_REQUIRED`“请填写正文”；`ANNOUNCEMENT_INVALID_TARGET`“可见对象条件无效，请重新设置”；`ANNOUNCEMENT_TIME_RANGE_INVALID`“结束时间要晚于开始时间”；`ANNOUNCEMENT_NOTIFY_MODE_INVALID` / `ANNOUNCEMENT_STATUS_INVALID`（App 不会发出）；带 key 时业务校验失败会进入 5 秒退避，改内容后必须换 key（已由上面的 key 规则覆盖）。
- 有未保存修改时下滑关闭先确认“放弃修改？”。

### 17.5 状态

保存中按钮转圈、表单禁用。

### 17.6 刷新策略

不适用。

### 17.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementEditSheet.swift`（Markdown 插入用 `TextEditor` + `TextSelection`，iOS 18+ 可用）。

---

## 18. 已读情况（`announcementReads`）

### 18.1 入口与导航

- 公告详情“已读情况”行、··· “已读情况”。导航栏：返回 + 标题“已读情况” + 副标题公告标题。点行 → 用户详情（用户章节）。

### 18.2 数据来源

- `GET /admin/announcements/:id/read-status`：`page`、`page_size=50`、`search`（邮箱、用户名、备注、Key，服务端截到 200 字节）、`sort_by`（`email` 默认 / `username` / `balance` / `read_at`）、`sort_order`（`asc` 默认）；有 `announcements.read_stats` 时可加 `read_state=read|unread`、`eligible=true|false`、`sort_by=read_at`（未读排最后）。行：`user_id`、`email`、`username`、`balance`、`eligible`、`read_at`（可缺）。分页信封 `total` 按过滤后计算。
- 汇总：`GET …/read-summary`（16.2）。
- 无 capability：只有 `search` 与 `sort_by=email|username|balance`；`page_size` 保持 20–50（老路径每页逐用户查订阅，附录 H06 App 退路）。

### 18.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 汇总条 | read-summary | “已读 412 · 符合条件 1036 · 共 1036 位用户 · 统计于 09:41” | 无 capability 或失败：“第 1 页 · 共 1,036 位用户”（用分页 `total`） |
| 搜索框 | — | 占位“搜索邮箱或用户名” | — |
| 筛选（capability） | — | 分段“全部 / 已读 / 未读”；开关“只看符合条件” | 无 capability 不显示 |
| 排序菜单 | — | 按邮箱（升序）/ 按用户名（升序）/ 按余额（从高到低，`sort_order=desc`）/ 按阅读时间（最新在前，`sort_by=read_at&sort_order=desc`，capability） | — |
| 结果数 | `total` | 有筛选或搜索时“找到 N 位” | — |
| 行 · 头像 | `username` 首字 | — | 用户名空时用邮箱首字 |
| 行 · 标题 / 右侧 | `email`、`balance` | 邮箱（截断）；余额“$12.40” | — |
| 行 · 第二行 | `username`、`eligible`、`read_at` | 用户名；徽章“符合条件”（ok）/“不符合”（neutral）；“10/16 08:12” | 未读：“未读”（灰） |
| 行 · 变淡 | `eligible == false` | idle | — |
| 底部 | 还有下一页 | 转圈 + “滚到底自动加载下一页” | — |

### 18.4 交互与写操作

搜索（防抖 300ms）、筛选、排序变化 → 重载第 1 页；触底加载下一页；点行 → 用户详情。只读。

### 18.5 状态

| 情况 | 显示 |
|---|---|
| 无匹配 | “没有匹配的用户” |
| `400 INVALID_READ_STATUS_FILTER` | App 参数错误，按通用“请求无效”处理 |
| 失败 | `FailureView` |

### 18.6 刷新策略

进入时加载第 1 页与汇总；下拉刷新；不轮询。

### 18.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementReadsView.swift`；接口在 15.7 的 `Announcements.swift`。

---

## 19. 发放兑换码（补偿）sheet（`redeemGrant`）

> DECISIONS 第 3 轮文字题：用户详情 ··· 菜单加“发放兑换码（补偿）”，后端 create-and-redeem，可发余额 / 并发 / 订阅，余额类走资金确认与 Face ID 门槛。设计稿 `v-modules.jsx:1358-1560`（`VmoGrantSheet`、`vmoGrantSummary`、`vmoSubPlan`、`vmoConfirmGrant`、`VmoGrantReceipt`），菜单项 `00-core.jsx:1199`。30 章 §2.4 只负责入口与成功后的刷新，sheet、接口、确认与待核对都在本节。

### 19.1 入口与导航

- 用户详情 ··· “发放兑换码（补偿）…”（30 章 §2.4，所有用户都显示，含管理员与已禁用用户）→ sheet `.redeemGrant(userID:pendingID: nil)`，`presentationDetents([.large])`。只读令牌：菜单项置灰，旁注“只读令牌”（0.3）。vendor 看不到（兑换码对 vendor 不开放）。
- **打开前拦截**：当前站点、这个用户有未核对的补偿记录（19.4）时，先弹确认框“上一次补偿的发放结果未确认”，正文“向 王小明 发放 $10.00 余额 · 5 分钟前发起。\n先核对，避免重复发放。”，按钮“先核对”（默认，打开本 sheet 的“结果待核对”页）/“取消”。核对完成前不能发起新的补偿（00 §2.5.4 第 4 条）。
- 从设置 → 待核对 · 补偿发放（3.3）或概览待处理进入时，`pendingID` 有值，sheet 直接显示“结果待核对”页。
- sheet 内步骤条“类型 · 数值 · 备注”。标题：第 1 步“发放兑换码”，第 2 步“余额补偿 / 并发补偿 / 订阅补偿”，第 3 步“备注与确认”。左上第 1 步“取消”，之后“上一步”。发送中、Face ID 验证中、“正在确认结果…”时 `.interactiveDismissDisabled`。
- 成功后关闭 sheet，回到用户详情；回执 toast 的“查看兑换码”→ 在当前导航栈 push `.redeem(open: <redeem_code.id>)`（第 8 节）。

### 19.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 用户 | 用户详情已加载的 `AdminUser` | `id`、显示名（30 §0.3）、`email`、`balance`、`concurrency`、`status`；不另请求 |
| 订阅分组选项 | 分组目录缓存 `GET /admin/groups/all`（`include_inactive=true`，50 章） | `subscription_type == "subscription"` 且 `status == "active"`，同 9.2 |
| 用户现有订阅（订阅类的“现在 / 发放后”） | `GET /admin/users/:id/subscriptions`（`server/routes/admin.go:819`；30 章 §10 的 `userSubscriptions(userID:)`） | 数组：`group_id`、`status`、`expires_at`；选中订阅类时请求一次 |
| 发放 | `POST /admin/redeem-codes/create-and-redeem`（`server/routes/admin.go:660`；`handler/admin/redeem_handler.go:51-63,262-331`） | 头：`Idempotency-Key`（**强制**，缺了 400 `IDEMPOTENCY_KEY_REQUIRED`；scope `admin.redeem_codes.create_and_redeem`，带 key 的执行上限 30 秒，可接管卡住的执行，`idempotency_helper.go:160-163`）、`X-Request-ID`（= key）。请求体见下 |
| 核对 | `GET /admin/redeem-codes` | `search=<code>&page=1&page_size=5`（码值包含匹配，不带 `types` / `status`）；本地按 `items[].code == code` 复核（00 §2.5.5 的“发放补偿”行） |

**请求体**（`CreateAndRedeemCodeRequest`）：

| 类型 | 请求体 |
|---|---|
| 余额 | `{"code":"<32 位小写十六进制>","type":"balance","value":10.5,"user_id":42,"notes":"…"}` |
| 并发 | `{"code":"…","type":"concurrency","value":2,"user_id":42,"notes":"…"}` |
| 订阅 | `{"code":"…","type":"subscription","value":30,"user_id":42,"group_id":3,"validity_days":30,"notes":"…"}` |

- `code`：App 生成，16 字节 `SecRandomCopyBytes` → 32 位小写十六进制，与服务端生成的码同一形态（`service/redeem_code.go:63-69`）；长度要求 3–128。
- `value`：JSON number（字段是 `float64`，不能发字符串；这是 00 §0 第 11 条“金额写入用字符串”的例外），余额最多 2 位小数。`value` 带 `binding:"required"`，**0 会被拒**（`redeem_handler.go:56`），所以订阅类的 `value` 填与 `validity_days` 相同的天数（订阅类不用 `value` 记账；30 §4.3 的记录行在 `validity_days` 为 0 时才用 `value` 显示天数）。
- 订阅类必须带 `group_id` 与非 0 的 `validity_days`（`redeem_handler.go:281-289`）；App 只发 1–3650 的正数（负数是扣减订阅，不提供）。
- 不发 `expires_at` / `expires_in_days`（码当场兑换）。`notes` 选填，App 限 1000 字（后端此接口未设上限，与批量生成一致）。
- 不提供邀请码：邀请码不能通过兑换接口使用（`service/redeem_service.go:523-532`，400 `REDEEM_CODE_UNSUPPORTED_TYPE`），而且码会先建好再失败，留下一个未使用的码。
- 响应：`data.redeem_code` = `AdminRedeemCode`（`id`、`code`、`type`、`value`、`status:"used"`、`used_by`、`used_at`、`group_id`、`validity_days`、`notes` 等）。重放（`X-Idempotency-Replayed: true`）时 `code` 可能是 `***`（logredact），以本机生成的 code 为准，`id` 完整。
- 服务端去重靠 `code`：同一个 code 已被同一用户兑换 → 直接返回原结果；码已建好但没兑换（上次执行中途失败）→ 补兑；码被别的用户用过 → 409 `REDEEM_CODE_CONFLICT`（`redeem_handler.go:334-362`）。所以同 code、同用户重发**不会重复发放**，即使幂等记录已过 24 小时。

### 19.3 字段 → 显示映射

| 步骤 / 元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 对象条 | 显示名 + 随步骤变化 | 头像首字 + “王小明 · …”：第 1 步写 `email`；余额“余额 $12.40”；并发“并发上限 5”；订阅按下面的订阅计划写“企业专线 未订阅 / 企业专线 至 10/30 / 企业专线 10/30 已过期 / 企业专线 已暂停，至 10/30”；禁用用户右侧 neutral 徽章“禁用” | `concurrency == 0` 写“并发上限 不限制” |
| 第 1 步 · 类型磁贴 | 固定三项 | 余额“直接计入余额，按资金操作确认。”；并发“提高这个用户的并发上限。”；订阅“开通或延长一个订阅分组。”；点磁贴即进第 2 步 | 没有订阅分组：订阅磁贴置灰，副行“没有订阅类型的分组”；用户 `concurrency == 0`：并发磁贴置灰，副行“这个用户并发不限制，发放后反而会变成有上限”（0 = 不限制，`service/concurrency_service.go:442-444`；未决问题 14） |
| 第 1 步 · 脚注 | 固定 | “发放会生成一个兑换码并立即替这个用户兑换，记录出现在用户的“充值与调整记录”和兑换码列表里。邀请码只能在注册时使用，不能发放。” | — |
| 第 2 步 · 余额 | 大数字键盘 | 大字“$10”；下方“发放后余额 **$22.40**”；键盘输入规则同 30 章 §3.3（`KeypadInput`）；不给默认金额 | 未输入时“$0”灰色，下方“输入金额”，“下一步”置灰 |
| 第 2 步 · 并发 | 步进器 1–50（默认 1） | 标签“增加并发”；脚注“提高这个用户的并发上限。发放后：并发上限 5 → 7。” | — |
| 第 2 步 · 订阅 | 分组胶囊（默认第一个）+ 有效天数 | 天数选项 7 / 30（默认）/ 90 / 自定义（数字键盘，1–3650）；脚注“只列出订阅类型的分组。”+ 订阅计划的说明句 | 用户订阅请求失败：说明句改“暂时读不到这个用户的订阅，发放后以服务器结果为准”，不阻断 |
| 订阅计划 | 用户订阅里 `group_id` 相同的那行（服务端每个用户、分组一行，`AssignOrExtendSubscription`，`service/subscription_service.go:218-271,291-345`） | 没有 → “新开通 · 到期 <今天 + N 天>”，说明“还没有这个订阅：从今天开通。”；`expires_at` 晚于现在且 `status == active` → “到期 10/30 → 11/29”，说明“已有生效中的订阅：在原到期日 10/30 上延长。”；晚于现在但不是 active（暂停）→ “恢复生效 · 到期 10/30 → 11/29”，说明“订阅暂停中：在原到期日上延长，并恢复为生效。”；`expires_at` 不晚于现在 → “重新开通 · 到期 <今天 + N 天>”，说明“订阅 10/30 已过期：从今天重新算，用量清零。” | 日期按服务器时区（00 §6.3） |
| 第 3 步 · 备注 | `notes` | 多行输入，占位“例如：故障补偿 · 工单 #8812”；脚注“可选。写进兑换码的备注，也显示在用户的“充值与调整记录”里。” | 空则发 `""` |
| 第 3 步 · 收据 | 汇总 | 对象“王小明 · wang@example.com”；站点；类型“余额 / 并发 / 订阅”；数值（非余额）“+2 并发”/“企业专线 · 30 天”；变化（余额“余额 $12.40 → $22.40”，并发“并发上限 5 → 7”，订阅为订阅计划那一句）；兑换码“a3f0····d4e8”；发放（只余额，加粗）“$10.00” | — |
| 第 3 步 · 返利脚注 | 只余额 | “按兑换处理：开启邀请返利时，邀请人会照常得到返利（和用户自己兑换一样，不看“管理员充值参与返利”开关）。”（`service/redeem_service.go:476-482,679-697`：管理员兑换路径不设跳过返利标记，注释写明“affiliate rebate remains enabled”） | — |
| Face ID 提示 | 余额且开关打开且金额 > 门槛 | “超过 $100，确认后验证 Face ID。” | — |
| 提交按钮 | 汇总 | “发放 $10.00” / “发放 +2 并发” / “发放 30 天订阅” | 校验不过置灰 |
| 确认框 | 汇总 | 标题“向「王小明」发放 $10.00 余额？”/“向「王小明」发放 +2 并发？”/“向「王小明」发放 企业专线 30 天订阅？”；正文逐行：“站点 主站 · <变化>”；有备注“备注：<备注>”；禁用用户“该用户已禁用。\n发放后仍不能调用，需先启用。”；需要时 Face ID 行；按钮“发放 $10.00”（余额类 destructive 样式）/ 其他类型普通样式，“取消” | — |
| 成功回执 | 响应 | toast（礼物图标）“已向 王小明 发放 $10.00 余额”，重放时“这笔补偿此前已发放，没有重复执行”；动作“查看兑换码” | — |
| 结果待核对页 | 本机记录 | 沙漏 + “请求可能已提交” + “没有收到服务器确认。不要重新发放，先核对。”；收据（对象、站点、内容、兑换码末 4 位、编号 = 完整 key，等宽可选中）；按钮“核对发放结果”（主）/“用同一编号重试”；脚注“编号和兑换码已保存在本机。用同一编号重试时，服务器发放过就直接返回那一次，不会重复发放。” | — |
| 没找到页 | 核对无此码 | 放大镜 + “服务器上没有这次发放” + “这次发放没有生效。用同一编号重试，或者放弃。”；按钮“用同一编号重试”（主）/“放弃这次发放” | — |
| 未兑换页 | 核对到码但 `status == unused` | “兑换码已创建，还没兑换给 王小明” + “上一次执行中途停了。用同一编号重试会把这个码兑换给他。”；按钮“用同一编号重试”（主）/“放弃这次发放”（脚注“放弃后这个码留在兑换码列表里，未使用，可以删除。”） | — |

### 19.4 交互与写操作

1. **提交**：第 3 步“发放 …”→ 确认框 → 确认 →（余额类、开关打开、金额 > 门槛）Face ID，失败或取消则不发送（3.4 覆盖清单）。
2. **冻结与落盘**（00 §2.5.2、§2.5.5）：确认那一刻生成 `key`（UUID v4 小写，同时作 `X-Request-ID`）；`code` 在 sheet 打开时生成（第 3 步收据要显示末 4 位），随请求体一起冻结。写入 `PendingWrite`：`kind = .redeemGrant`、`id = key`、`serverID`、`actorUserID = me.user.id`、`authMethod`、`method`、`path`、`body`（`.sortedKeys` 编码的原始字节）、`summary{userID, 显示名, email, 类型, 数值文案, code}`、`status = sending`。**落盘失败就不发送**，提示“未决记录无法保存，已暂停发放”。
3. **发送**：客户端超时 40 秒（服务端上限 30 秒，同 30 章 §3.4）。
4. **结果**：

| 结果 | 动作 |
|---|---|
| 200 | 删除记录；关闭 sheet；回执；按 30 章 §2.4 刷新用户资料（余额 / 并发）与记录前 5 条；订阅类另重拉该用户订阅 |
| 200 + `X-Idempotency-Degraded: result-committed` | 同 200 |
| 409 `IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` | 按 00 §2.5.3：显示“正在等待服务器结果…”，等 `Retry-After` 后同 key 同字节重试；累计超过 30 秒 → 转“结果待核对”页 |
| 409 `REDEEM_CODE_LOCKED` | 同一个码正在被另一次请求处理：等 2 秒后同 key 同字节重试一次，仍是此码 → 转“结果待核对” |
| 409 `REDEEM_CODE_CONFLICT` | 这个码已被别的用户用过（随机码撞上，正常不会出现）：确定没发给本用户 → 删除记录；换新 code 和新 key，提示“兑换码编号冲突，已换新编号，请重新确认”，回到第 3 步 |
| 400 `GROUP_NOT_SUBSCRIPTION_TYPE` / 404 `GROUP_NOT_FOUND` | 删除记录；“这个分组不能用于订阅，请重新选择”，回到第 2 步并重拉分组目录 |
| 404 `USER_NOT_FOUND` | 删除记录；关闭 sheet，“用户不存在或已删除” |
| 400 `REDEEM_CODE_UNSUPPORTED_TYPE`、无 reason 的 400（请求体校验） | App 不会发出：删除记录，按 00 §3.3 的“请求无效”处理并上报（不含 code） |
| 400 `IDEMPOTENCY_KEY_REQUIRED` / `IDEMPOTENCY_KEY_INVALID`、409 `IDEMPOTENCY_KEY_CONFLICT` | 程序缺陷，按 00 §2.5.3 |
| 401 / 403（含 `ACCESS_TOKEN_READ_ONLY`）/ 423 | 鉴权或合规在执行前拒绝：删除记录，按全局处理 |
| 503 `IDEMPOTENCY_STORE_UNAVAILABLE` | 没有执行：保留记录，转“结果待核对”，10 秒后才允许“用同一编号重试”（00 §2.5.3） |
| 其他 5xx / 网络错误 / 超时 | 按 00 §2.5.4：同 key 同字节自动重试 2 次（2 秒、5 秒，仅前台），仍未知 → 记录转 `unknown`，sheet 换成“结果待核对”页 |

   业务错误发生在建码之后时（`USER_NOT_FOUND`、分组错误），服务器上会留下一个未使用的码（`redeem_handler.go:307-325`：先建码、后兑换）；App 不自动删除，兑换码列表里可见。
5. **改了内容就换编号**：发送过一次之后（不论结果），再改类型、数值、分组、天数或备注，`code` 和 `key` 一起换新（旧 code 可能已在服务器上以旧参数建好，沿用会兑换出旧参数）。
6. **核对**（“核对发放结果”、设置 → 待核对、概览待处理共用，只查不执行）：`GET …/redeem-codes?search=<code>`，本地找 `code` 完全相等的那项：
   - `status == used` 且 `used_by == userID` → 已发放：删除记录，回执“已核对：已向 王小明 发放 $10.00 余额”，刷新同第 4 步 200；
   - 找到但 `status == unused` → 未兑换页；
   - 没找到 → 没找到页；
   - 被别的用户用了 → 同 `REDEEM_CODE_CONFLICT`；
   - 查询失败 → “核对失败，请稍后再试”，记录保留。
7. **用同一编号重试**：同 key、同 `X-Request-ID`、同字节重发，结果按第 4 步。00 §2.5.5 规定超过 `expiresAt` 后重试按钮置灰；补偿是例外——服务端按 code 去重，过期后同 code 重发也不会重复发放（19.2 末条），按钮保持可用。仍须同一操作者（00 §2.5.2）：发起人不是当前管理员时不给重试，只给“放弃”。
8. **放弃这次发放**：二次确认“放弃后这笔不会再重试；如果服务器其实已经发放，以服务器为准。”→ 删除记录，toast “已放弃 · 不再提醒”。
9. App 回到前台时，对本站点 `unknown` 状态的补偿记录各自动核对一次（只查不执行，同 30 章 §3.6）；查到已发放就删除记录并回执。

### 19.5 状态

| 情况 | 显示 |
|---|---|
| 发送中 | 提交按钮“正在发放…”，sheet 不能关闭 |
| Face ID 中 | 覆盖层“Face ID · 验证后发放”；取消 = 不发请求、删掉刚写的记录 |
| 等待服务器（409 进行中） | “正在等待服务器结果…”+ 已等待秒数 |
| 待核对 | 结果待核对页；关闭 sheet 后在设置 → 待核对、概览待处理（10 章）保留提醒，直到核对或放弃 |
| 核对 / 重试中 | 按钮“正在核对…”/“正在用同一编号重试…”，两个按钮都禁用 |
| 待核对文件不可读 | 同 3.5：已暂停新的余额操作、兑换码生成与补偿发放 |

### 19.6 刷新策略

sheet 内不轮询。打开时用用户详情已有的数据；选订阅类时拉一次用户订阅。成功后刷新用户详情（30 章 §2.4）；兑换码列表下次显示时按 8.6 重载。待核对只在用户点“核对”或回到前台时查。

### 19.7 对现有代码的改动点

- 新增 `NativeApp/Features/Redeem/RedeemGrantSheet.swift`：三步（类型、数值、备注）+ 确认 + “结果待核对 / 没找到 / 未兑换”三个页面；初始化参数 `user: AdminUser`、`pendingID: UUID?`。
- `Sources/Sub2Core/RedeemCodes.swift`：`RedeemGrantSpec`（类型、金额 `Decimal`、并发数、分组 id 与名、天数、备注）、`RedeemGrantRequest`（Encodable，`value` 编码成 JSON number、订阅类 `value = validity_days`）、`RedeemCode.random()`（32 位小写十六进制）、`SubscriptionGrantPlan.make(rows:groupID:days:now:timeZone:)`（新开通 / 延长 / 恢复 / 重新开通，纯函数，便于单测）、`APIClient.createAndRedeem(_:)` 走 00 §9.1 的 `send(_ write: PendingWrite)`，返回 `WriteOutcome<AdminRedeemCode>`。
- `NativeApp/Session/AppModel.swift`：`PendingWrite.Kind` 增加 `.redeemGrant`；`reconcile(_:)` 按 19.4 第 6 步分派；`hasPendingGrant(userID:)` 供 19.1 拦截。
- 30 章 `UserDetailView` 的 ··· 菜单项打开本 sheet，并传入成功回调（刷新资料与记录）。
- 复用：`KeypadInput`（30 章 §3.7）、`BiometricGate`（3.7）、分组目录缓存（50 章）、`userSubscriptions(userID:)`（30 章 §10）。
- 单测（`Tests/Sub2CoreTests`）：请求体（三种类型、订阅 `value` 非 0、金额是 number）；`SubscriptionGrantPlan` 四种情况与服务器时区日界；核对判定（used + 同用户 / unused / 无 / 他人）；改内容后 code 与 key 都变。

---

## 附录 · 本章接口清单（均已在 sub2 `70116315d` 源码核实）

| # | 方法与路径 | 用于 | 后端位置 |
|---|---|---|---|
| 1 | `GET /settings/public` | 4 | `server/routes/auth.go:246`；`handler/dto/settings.go:387-436`（`captcha_provider` / `mobile_verify_path` 在 403-404）；`web/embed_off.go:50-53`、`web/embed_on.go:462-472`、`web/mobile_verify.go:7` |
| 2 | `POST /auth/login` | 4 | `server/routes/auth.go:38`；`handler/auth_handler.go:86-99` |
| 3 | `POST /auth/login/2fa` | 4 | `server/routes/auth.go:41`；`handler/auth_handler.go:335-338` |
| 4 | `POST /auth/logout` | 3 | `server/routes/auth.go:58` |
| 5 | `GET /admin/me` | 0.2、0.3、3、4、7 | `server/routes/admin.go:40`；`handler/admin/me_handler.go:17-75,129-193`（无 scope 字段，185-193） |
| 6 | `GET /auth/sessions` | 5 | `server/routes/auth.go:259`；`handler/auth_sessions_handler.go:37` |
| 7 | `DELETE /auth/sessions/:id` | 5 | `server/routes/auth.go:260`；`handler/auth_sessions_handler.go:69` |
| 8 | `POST /auth/revoke-all-sessions` | 5 | `server/routes/auth.go:262`；`handler/auth_handler.go:858` |
| 9 | `POST /user/totp/step-up` | 7 | `server/routes/user.go:62`；开关关闭时 step-up 直接放行（含机器凭据）：`server/middleware/step_up.go:100,104` |
| 10 | `GET /admin/access-tokens` | 0.3、3、6 | `server/routes/admin.go:212`；`handler/admin/access_token_handler.go:89` |
| 11 | `POST /admin/access-tokens` | 首版不调用（6.2） | `server/routes/admin.go:213`（step-up）；`access_token_handler.go:57-61`（机器凭据一律 403） |
| 12 | `DELETE /admin/access-tokens/:id` | 3、6 | `server/routes/admin.go:214`；`access_token_handler.go:110` |
| 13 | `GET /admin/push/devices` | 7 | `server/routes/admin.go:222`；`handler/admin/push_handler.go:141` |
| 14 | `POST /admin/push/devices` | 7 | `server/routes/admin.go:223`；`push_handler.go:108`；`environment` 省略时存空串、发送跟随站点：`service/push_device_service.go:177-183`、`service/push_sender_apns.go:109-111` |
| 15 | `DELETE /admin/push/devices/:id` | 3、7 | `server/routes/admin.go:224`；`push_handler.go:160` |
| 16 | `PUT /admin/push/devices/:id/subscription` | 7 | `server/routes/admin.go:225`；`push_handler.go:178` |
| 17 | `POST /admin/push/devices/:id/test` | 7 | `server/routes/admin.go:226`；`push_handler.go:202` |
| 18 | `GET /admin/push/config` | 7 | `server/routes/admin.go:227`；`push_handler.go:221` |
| 19 | `PUT /admin/push/config` | 7 | `server/routes/admin.go:228`（step-up）；`push_handler.go:232` |
| 20 | `GET /admin/redeem-codes` | 8、11、19 | `server/routes/admin.go:656`；`handler/admin/redeem_handler.go:91-161` |
| 21 | `GET /admin/redeem-codes/stats` | 8 | `server/routes/admin.go:657`；`redeem_handler.go:478`；`handler/dto/redeem_code_stats.go:15-31` |
| 22 | `GET /admin/redeem-codes/:id` | 8、9、11 | `server/routes/admin.go:659`；`redeem_handler.go:165` |
| 23 | `POST /admin/redeem-codes/generate` | 10、11 | `server/routes/admin.go:661`；`redeem_handler.go:183-260` |
| 24 | `POST /admin/redeem-codes/batch-update` | 8、9 | `server/routes/admin.go:664`；`redeem_handler.go:413`；`service/redeem_service.go:349-389` |
| 25 | `DELETE /admin/redeem-codes/:id` | 8 | `server/routes/admin.go:662`；`redeem_handler.go:368`；`service/redeem_service.go:28-30` |
| 26 | `GET /admin/proxies` | 2、12 | `server/routes/admin.go:633`；`handler/admin/proxy_handler.go:59` |
| 27 | `GET /admin/proxies/:id` | 13 | `server/routes/admin.go:638`；`proxy_handler.go:120` |
| 28 | `POST /admin/proxies` | 14 | `server/routes/admin.go:639`；`proxy_handler.go:139` |
| 29 | `PUT /admin/proxies/:id` | 13、14 | `server/routes/admin.go:640`；`proxy_handler.go:173` |
| 30 | `DELETE /admin/proxies/:id` | 13、14 | `server/routes/admin.go:641`；`service/admin_proxy.go:254-297` |
| 31 | `POST /admin/proxies/:id/test` | 12、13 | `server/routes/admin.go:642`；`service/admin_service.go:663-673` |
| 32 | `POST /admin/proxies/:id/quality-check` | 13 | `server/routes/admin.go:643`；`service/admin_service.go:675-699` |
| 33 | `GET /admin/proxies/:id/accounts` | 13 | `server/routes/admin.go:645`；`handler/dto/types.go:532-538` |
| 34 | `GET /admin/proxies/:id/fallback-accounts` | 13 | `server/routes/admin.go:646`；`handler/dto/types.go:542-546` |
| 35 | `POST /admin/proxies/:id/fallback-accounts/revert` | 13 | `server/routes/admin.go:647`；`service/admin_proxy_fallback.go:18-28` |
| 36 | `GET /admin/announcements` | 15、17 | `server/routes/admin.go:555`；`handler/admin/announcement_handler.go:52` |
| 37 | `GET /admin/announcements/:id` | 16 | `server/routes/admin.go:557`；`announcement_handler.go:91` |
| 38 | `POST /admin/announcements` | 17 | `server/routes/admin.go:556`；`announcement_handler.go:30-38,121` |
| 39 | `PUT /admin/announcements/:id` | 16、17 | `server/routes/admin.go:558`；`announcement_handler.go:40-48,163` |
| 40 | `DELETE /admin/announcements/:id` | 16 | `server/routes/admin.go:559` |
| 41 | `GET /admin/announcements/:id/read-status` | 18 | `server/routes/admin.go:560`；`announcement_handler.go:244` |
| 42 | `GET /admin/announcements/:id/read-summary` | 16、18 | `server/routes/admin.go:561`；`handler/admin/announcement_read_stats_handler.go:56` |
| 43 | `GET /admin/accounts`（`search`、`lite`） | 2 | `handler/admin/account_handler.go:718-727` |
| 44 | `GET /admin/users`（`search`） | 2（含“查看全部”） | `handler/admin/user_handler.go:150`；`repository/user_repo.go:553-561` |
| 45 | `GET /admin/groups`（`search`） | 2 | `handler/admin/group_handler.go:378` |
| 46 | `GET /admin/usage`（`request_id`、`key_view=masked`） | 2 | `handler/admin/usage_handler.go:122,132`；`repository/usage_log_repo_query.go:120-123` |
| 47 | `GET /admin/ops/request-errors`（`request_id`、`view`、`time_range`） | 2 | `handler/admin/ops_handler.go:216-262,344-354,579` |
| 48 | `GET /admin/groups/all`（`include_inactive=true`） | 7、9、10、15、17、19 | `server/routes/admin.go:404`；`group_handler.go:560-569` |
| 49 | `GET /admin/accounts/status-summary`（`include_accounts=true`） | 13（账号状态徽章，账号章节提供） | `server/routes/admin.go:474`；`handler/admin/account_status_summary_handler.go:29-46` |
| 50 | `POST /admin/redeem-codes/create-and-redeem` | 19 | `server/routes/admin.go:660`；`handler/admin/redeem_handler.go:51-63,262-362`；`service/redeem_service.go:476-482,523-532` |
| 51 | `GET /admin/users/:id/subscriptions` | 19 | `server/routes/admin.go:819`；`handler/admin/subscription_handler.go:333`；续期 / 重开语义 `service/subscription_service.go:218-345` |
| 52 | `GET /admin/compliance` | 4（旧服务端 Admin Key / sat_ 探针，00 §1.9） | `server/routes/admin.go:188-190` |

---

## 本章未决问题

1. **搜索 Tab 在 iOS 27 的表现**：DECISIONS 定“目录首屏、点搜索框才弹键盘”，并写了 `.tabViewSearchActivation(.automatic)`；但有报告称 iOS 27 上不声明 `.searchTabSelection` 时分离的搜索按钮会并入 Tab 栏，而 `.searchTabSelection` 会让点 Tab 即激活搜索。**建议默认**：`.searchable` 挂在搜索 Tab 内部根视图、`.automatic`，iOS 26 / 27 实机各验证一次；若 27 上按钮并入，维持目录首屏优先，接受按钮并入。
2. **目录“告警事件”的去向**：设计稿未接线。**建议默认**：切到 监控 Tab 的“告警”分段（不在搜索栈里重复一份告警列表）。
3. **简化模式在首版的呈现**：简化模式尚未设计。**建议默认**：设置里显示该项但置灰并标“设计中”，不可选。
4. **G03 / G04 没有 capability 标记**：App 只能用 `redeem_codes.stats` 推断。**建议默认**：按推断实现；请后端顺手在 capabilities 加 `redeem_codes.batches`（不改行为）。
5. **公告列表 / 详情是否恢复已读进度**：设计稿当时因后端没有数据而降级为只留“已读情况 ›”，H06 已上线，DECISIONS 未再表态。**建议默认**：有 `announcements.read_stats` 时列表行写“已读 N/M”、详情写汇总，已读名单加筛选与按阅读时间排序。
6. **生成向导第 3 步加“备注”**：设计稿因后端当时没有 `notes` 参数而未画，G03 已支持。**建议默认**：加，选填，≤ 1000 字。
7. **APNs 站点配置放进 App**：Web 没有配置界面（BACKLOG A11“本次只提供接口，App 或 curl 可配置”；sub2 `frontend/src` 里没有 `push/config` 调用），设计稿也没画。**建议默认**：放在推送通知页底部，仅站长；可编辑条件同 7.3（非只读令牌，且站点关闭二次验证或本人可做二次验证）。
8. **推送登记的 `site_tag` 取值**：后端用它填载荷里的 `site`。**建议默认**：填 `ServerProfile.id.uuidString`，便于多站点点击路由（代价是载荷里不是域名，对 iOS 无影响）。
9. **关闭 Face ID 开关是否也要验证**：设计稿未说明。**建议默认**：开、关都验证一次。
10. **首版是否在 App 内签发管理访问令牌**：00 未决问题 3 默认“首版不签发”，本章第 6 节已按此只做列表与吊销；但 Web 也没有签发界面（sub2 `frontend/src` 里没有 `access-tokens` 调用），首版里 sat_ 实际只能用 API 签发。**建议默认**：维持首版不签发（与 00 一致）。若改为签发，需同时改 00 §1.3 与未决问题 3，再在第 6 节加新建 sheet（`POST /admin/access-tokens` 挂 step-up；handler 对 Admin Key / sat_ 一律 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`，与站点二次验证开关无关）。
11. **兑换码 ··· 加“查看同一批”**：设计稿没有，G03 提供了 `batch_id` 过滤。**建议默认**：加在 ··· 菜单，复制之后、删除之前。
12. **会话列表里本机行能否下线**：后端允许（等于退出）。**建议默认**：本机行不给“下线”，统一走“退出并清除凭据”（顺带清推送设备）。
13. **全局搜索“像请求 ID”的判定**：后端请求 ID 有 UUID、`client:<uuid>` 等形态，没有统一格式。**建议默认**：去空白后不含空格与 `@`、长度 8–256 就加查使用记录与错误请求（精确匹配，查不到只是少两个分区）。
14. **给并发不限制的用户发放并发补偿**：用户 `concurrency == 0` 表示不限制（`service/concurrency_service.go:442-444`），兑换并发码是在原值上加（`service/redeem_service.go:574-585`、`repository/user_repo.go:1129-1131` `AddConcurrency`），发放 +N 后反而变成上限 N。设计稿只处理了“并发上限未知”的显示，没有定这种情况。**建议默认**：并发磁贴置灰并说明原因（19.3），不提供发放。

---

## 审查记录

- `mobile_verify_path` 为空就拒绝登录、CaptchaView 改加载它（HIGH，两条同类意见）：属实。`web/embed_off.go:50-53` 在非 embed 构建恒返回 `""`，`web/embed_on.go:462-472` 只在内嵌前端里扫到桥页时才返回 `/mobile/verify`（`web/mobile_verify.go:7`）。已改 4.2–4.4、4.7：值为空照样打开桥页（路径 = 非空时用它，否则 `/mobile/verify`），加提示条，只有加载失败才提示未部署；时限统一用 00 §1.5（桥页 2 分钟、App 180 秒），删掉原来的“120 秒”。
- 推送登记一律显式传 `environment`（MEDIUM，及 LOW 第 14 条同项）：属实（`service/push_device_service.go:177-183`、`service/push_sender_apns.go:109-111`；进度表 A11 审查修正）。已改 7.2、7.4、7.7：Release / TestFlight 不传，只有开发构建传 `"sandbox"`，写明不要传 `"production"`。
- 旧服务端 Admin Key 探针、APNs 配置的可改条件（LOW）：两点都属实。① 4.2 改为与 00 §1.9 一致用 `GET /admin/compliance`；② `server/middleware/step_up.go:100,104` 先看站点开关、关闭时连机器凭据也放行，已把 0.3、7.3、7.4 改为“非只读令牌且（`step_up_enabled == false` 或 `step_up_available`）”。签发访问令牌不受这条影响：handler 对机器凭据一律 403（`access_token_handler.go:57-61`），与开关无关。
- 缺“发放兑换码（补偿）”向导（HIGH，两条同类意见）：属实（全部规格里没有 `redeemGrant`）。新增第 19 节，按 7 段结构写全：入口与拦截、create-and-redeem 请求体（含订阅类 `value` 不能为 0、`value` 必须是 JSON number、不提供邀请码）、订阅“新开通 / 延长 / 恢复 / 重新开通”、确认框与 Face ID、PendingWrite 落盘与按 `search=<code>` 核对、错误 reason、回执“查看兑换码”、成功后与 30 章 §2.4 对接；0.1 路由、3.3 待核对行、附录 #50–#51 同步。与意见不同的一处：Idempotency-Key 按 00 §2.5.2 与本章 0.4 在确认那一刻生成，不在 sheet 打开时生成；sheet 打开时生成的是 code（收据要显示），发送过之后改内容 code 与 key 一起换。另外设计稿和 BACKEND S58 认为补偿不需要待核对记录，本章按 00 第 0 节第 4 条与 §2.5.5 仍然冻结落盘（结果不明时 App 被杀也能核对）。意见里“10 §1.3.3 加‘补偿结果待核对’行”不在本文件，未改，需 10 章补一行（读 `pendingWrites` 中 `kind == .redeemGrant`，点按打开本节核对页）。
- 管理访问令牌是否签发、凭据存储、移除站点吊销、只读识别（MEDIUM，两条同类意见）：属实。按 00 §1.3 与 00 未决问题 3 的默认改为首版不签发：第 6 节删掉 `+`、新建 sheet 与结果页，只留列表与吊销；凭据改用 00 §9.4 的 `.accessToken`（4.4）；删除站点补上吊销与确认文案（3.4，按 00 §1.7.5 第 3 条）；只读识别写成在连接时执行一次、存进 `SiteSession.accessTokenScope` 的全局规则（0.3）。把这条规则移进 00 §1.6 需改 00，不在本文件，未改。未决问题 10 改为记录“Web 也没有签发界面”这一事实（sub2 `frontend/src` 无 `access-tokens` 调用）。
- 推送规则与 00 §7 三处矛盾（MEDIUM）：属实。按意见的建议以本章为界面口径：保留 Bark / ntfy / Webhook 的添加与删除、App 内编辑 APNs 配置（Web 没有推送配置界面，sub2 `frontend/src` 无 `push/config` 调用，00 §7.1 的“请站长在 Web 设置”做不到）；`environment` 统一为省略；吸收 00 §7.1 的“`ready=false` 不发起注册”（7.3 本机开关置灰）。00 §7.1、§7.4 那两句要在 00 删改，不在本文件，已在第 7 节开头注明以本节为准。
- 推送接收方式用滑动删除且不输入名称（LOW）：属实。7.4 改为设备详情最后一行红字“删除接收方式…”，走 0.4 的通用删除确认（输入名称或 Face ID）；0.4 写明推送接收方式不例外。
- 登录页与 00 各写一套（MEDIUM）：属实。第 4 节改为只写布局，流程、探测、错误文案全部引用 00 §1.3–§1.6、§1.9、§1.10；登录方式改为 00 的三个选项；`BACKEND_MODE_ADMIN_ONLY` 等文案用 00 的（“仅管理员可登录”）。`refresh_token_unavailable` 按 00 §1.4 第 5 步是概览横幅，10 章需补这个横幅，不在本文件，未改。
- “查看全部”跳到不支持该参数的页面（MEDIUM）：属实（20 章 §1.1 不放搜索框；40 章 §0.1 的 `logs` 路由没有 `request_id`；用户、分组、代理列表的路由也没有预填搜索词参数）。改为在搜索 Tab 栈内 push `.searchResults(kind:query:)` 结果页（2.1、2.3、2.7、0.1）；请求分区不再跳 `.logs`，改为一次取 20 条、不给“查看全部”。所以不需要改 20 / 40 章。
- Face ID 覆盖范围三处说法不同（LOW）：属实。3.4 新增“Face ID 覆盖清单”作全 App 唯一来源（含更换 API Key、重新授权、新建用户初始余额、发放余额补偿、揭示 Key 总是验证），3.3 副文案、0.4、Info.plist 文案照它改。20 / 30 章改为引用本表需在那两章做，不在本文件。
- 推送三处小冲突（LOW）：属实。`environment` 同上；`push.test` 改为进入“设置 → 推送通知”，匹配不到站点改为停在概览，7.1 改为引用 00 §7.5。
