# 首版接口适配边界

源码核对基线：自用 Sub2API `e5ab7e4f4c136a8faf40fd06694ab0a6bf6f6925`；原生 App 阶段 0 起按 sub2 `main` `70116315d` 之后核对（本文其余部分留到阶段 4 按 FINAL-SPEC 统一更新）。新增模块的具体能力、独立日志筛选边界和滚动 RPM 见 [管理模块契约](ADMIN_MODULES.md)。以下路径均以 `/api/v1` 为前缀。传输使用显式 snake_case CodingKeys、`{code,data,reason}` 响应 envelope。Admin Key 与 `sat_` 管理访问令牌使用 `x-api-key`，邮箱会话使用 Bearer；禁止自动跨源重定向和共享 Cookie。

| 能力 | 方法和路径 |
| --- | --- |
| 公开设置 | GET `/settings/public` |
| 邮箱登录 / TOTP | POST `/auth/login`、`/auth/login/2fa` |
| 会话 / 刷新 / 退出 | GET `/auth/me`；POST `/auth/refresh`、`/auth/logout` |
| 二次验证 | POST `/user/totp/step-up` |
| 概览 | GET `/admin/dashboard/home`（`timezone`、可选 `include`、下拉刷新 `nocache=1`；ETag / 304）；平静布局的账号排行 GET `/admin/dashboard/accounts-ranking`；没有 `dashboard.home` 能力，或 home 返回 404 / 网络失败时逐接口退路：`dashboard/stats`、`dashboard/trend`、`dashboard/rates`、`ops/dashboard/overview`、`ops/alert-events`（及 `/counts`）、`accounts/status-summary`（没有时 `groups/all` 加 lite 账号列表）、`channel-monitor-v2/overview` |
| 费用兼容快照 | GET `/admin/dashboard/snapshot-v2`，只开启 `include_stats`，禁用所有趋势和模型/分组统计；只在没有 `dashboard.account_cost` 能力的旧站点退路里补账号成本 |
| 连接探针 | GET `/admin/me`（三种登录方式通用；旧服务端退路见 FINAL-SPEC 00 §1.9） |
| 监控 | GET `/admin/ops/dashboard/overview`、`/admin/ops/dashboard/snapshot-v2`（45 分钟错误率）、`/admin/ops/concurrency`、`/admin/ops/system-metrics/history`、`/admin/ops/system-logs/health`、`/admin/ops/ingress-rejections`；GET / PUT `/admin/ops/monitoring-status`（没有 `ops.monitoring_status` 能力的旧服务端只在站点有 `/admin/me` 时用 PUT `/admin/settings` 开启，正文只带 `ops_monitoring_enabled` 一个键）；渠道 GET `/admin/channel-monitor-v2/overview`；告警 GET `/admin/ops/alert-events`、`/alert-events/counts`、`/alert-events/:id`、`/admin/ops/alert-rules`，PUT `/alert-events/:id/status`，POST `/admin/ops/alert-silences`，PUT / DELETE `/alert-silences/:id`（事件没有 `silence` 键的旧服务端不提供静默）；统计分析过渡页的性能另用 GET `/admin/ops/dashboard/throughput-trend` |
| 账号列表 / 详情 / 今日统计 | GET `/admin/accounts`、`/admin/accounts/:id`、`/admin/accounts/:id/today-stats`；POST `/admin/accounts/today-stats/batch` |
| 调度 / 刷新 / 测试 | POST `/admin/accounts/:id/schedulable`、`/refresh`、`/test` |
| 用户列表 / 详情 / 更新 | GET `/admin/users`、`/admin/users/:id`；POST `/admin/users` 创建；PUT `/admin/users/:id` 只提交变化字段；含并发变更时固定 `Idempotency-Key` |
| 用户用量 | GET `/admin/usage/stats?user_id=:id&start_date=...&end_date=...&timezone=...` |
| 用户密钥 | GET `/admin/users/:id/api-keys` |
| 用户余额 | POST `/admin/users/:id/balance`，`Idempotency-Key` 为持久化 UUID |

用户用量明确显示“本月”；旧 `/admin/users/:id/usage` 在基线中返回占位数据，因此不使用。账号测试使用 POST body 的 `model_id`，SSE 按增量 UTF-8 解析，支持 CRLF/心跳/多行帧；需要明确完成事件，拒绝畸形或过大的事件。

概览只发一次 `dashboard/home`：客户端超时 15 秒；服务端整体预算 8 秒、各段 3–6 秒，某段超时或失败只把该段标成 timeout / error，整体仍回 200。页面可见且在前台时每 60 秒轮询，失败按 FINAL-SPEC 00 §4.6 退避，429 按 `Retry-After` 推迟；下拉刷新带 `nocache=1`。附加请求只在需要时发：今日 SLA（`ops/dashboard/overview` 的今日窗口）、错误账号的结构化原因（`accounts?status=error&lite=1`）、平静布局的账号排行。没有 `dashboard.home` 的站点按 FINAL-SPEC 10 §1.2 逐接口退路，各区块各自落地、各自退避。切站、离开页面或进入后台取消请求和轮询，迟到结果不能写入新会话。

连接时读 `/admin/me` 验证权限并取得能力集合；只有比合规功能还旧的站点才退回 `/admin/dashboard/realtime` 验证权限，其指标为占位值，绝不用于显示。当前源码没有 stats lite 模式；添加 `mode=lite` 或 `lite=true` 不会减少计算。`snapshot-v2` 的 `include_stats=true` 会刷新统计，不能当成轻量替代。

概览的今日实际扣费与账号成本取 `dashboard/home` 的 stats 段（Decimal）；没有 `dashboard.account_cost` 的旧站点在退路里并发取只含 stats 的 snapshot-v2，只有同次响应给出完整的实际 / 成本对时才整体替换，否则缺失项显示“—”。以下是退路的字段细节：实际费用表示用户扣费，上游成本表示账号成本；今日和累计分别使用各自字段。基础统计返回 `total_requests`、`total_actual_cost`，当前后端 `/stats` handler 遗漏今日和累计账号成本，客户端独立补取只含 stats 的 snapshot-v2。今日或累计任一费用字段缺失时，仅在该周期快照提供同次响应的完整实际/成本对时整体替换；快照失败或不完整时保留基础统计已知值，缺失项显示不可用，不跨响应拼接成完整对，也不用标准计费或零值代替。snapshot-v2 使用 45 秒客户端预算，服务器共享计算预算仍为 30 秒；费用请求不会阻塞基础统计。服务端今日边界由服务器决定，snapshot 请求日期/手机时区不能改变该统计日。

阶段 1 起旧四卡、费用颜色区分与“运行健康”区已删除，概览改为 FINAL-SPEC 10 §1 的 6 格 + 待处理 + 今日 + 运行。

趋势接口继续使用 GET `/admin/dashboard/trend`，查询范围不变；自动加载和前台轮询会发起请求。阶段 1 起这个接口只在统计分析的过渡页 LegacyTrendPage 与首页逐接口退路里使用（过渡页由阶段 4 删除），首页改读 `dashboard/home` 的 hourly 段。后端 `cost` 为标准计费，`actual_cost` 为用户实际消费；原生 `TrendPoint.actualCost` 为可选 Decimal，兼容原初始化接口。`actual_cost` 缺失或 null 时，实际消费显示不可用并跳过对应柱子，不使用 `cost`、零值或推算金额替代；请求数和 Tokens 指标仍可查看。响应中的重复日期桶保留最后一条，不累加重复的消费；非法日期单独提示并跳过。

趋势默认显示“实际消费”，可切换“请求数”和“Tokens”。切换指标、左右滚动、点选柱子、双指缩放及加减按钮均处理已经加载的数据，不发起新请求，也不扩大“昨日以来”的小时查询。缩放改变真实可见时间跨度；上限按总跨度计算，最大放大时窗口为 3 个桶的时长，不足 3 桶时显示全部。极小非零金额使用随数据调整的 Y 轴范围，不用固定最小范围将柱高压成零。

趋势桶 `yyyy-MM-dd HH:00` 按请求时区解析并排序，采用月/日与小时两行刻度，同时显示当前可见范围和完整起止时间。柱标签、点选读数和逐小时明细统一使用 `DashboardTrendMetric.displayValue`：金额通过 Decimal 四舍五入到固定两位小数，极小金额可显示 `$0.00`；Tokens 达到相应阈值后使用 K/M/B，选择和明细也采用相同格式；请求数保持完整整数。Y 轴金额同样显示两位小数；金额不缩写为 K。原始 Decimal 和整数不因显示格式而改变，`exactValue` 仅供原始数据与精度测试使用，只有绘图坐标转换为近似 Double。放大倍数达到 6×，或可见时间窗口不超过 6 个桶时，柱子显示数值；最大放大时仍为 3 个桶窗口，明细不依赖柱内标签的显示空间。

图表交互使用 iOS 17 的原生 Swift Charts API：`chartScrollableAxes`、`chartXVisibleDomain`、`chartScrollPosition`、`chartXSelection` 和 `chartGesture`；双指手势与按钮共用可见时间窗口。加减按钮通过 `withAnimation` 执行 0.3 秒 ease-in-out 动画，显式 `AnimatableModifier` 插值缩放倍数，再按该倍数计算 `chartXVisibleDomain`；左侧时间边界固定，到达最大放大档时也不主动取整横向位置。系统开启“减弱动态效果”时停用该动画。双指缩放连续更新窗口，不等待按钮动画或轮询。动画实现本次未改；历史 `77a2462` / `20261015T073815Z-46faa0c1` 模拟器录屏观察到第二柱宽 17 → 21 → 29 → 34 → 37 像素、柱顶高度不变，范围左端保持 `10/14 00:00`；这是时间边界固定，首个可见柱栅格边缘仍有 2 像素差异。

共享显示格式仍使用 `NSDecimalRound` 与十进制字符串，金额固定两位；卡片最高 K，趋势和用户列表余额保留两位。历史账号容量版构建自干净源码 `d07091d5da137c3c58dc1a881c354b08c6f4d3ec`，运行 `20261015T115051Z-b20011a3`，Mac 全流程退出 0；81 项核心、4 项凭据、27 项 UI 测试通过，Debug 模拟器和 Release arm64 设备构建成功。未签名 IPA 为 3,324,867 字节，SHA-256 `978cbccbcc6b83028538a43e9e41c91d48e0ee44af5affed6b6bfe75c9ae3a43`。 本轮只验证当前自用后端契约，不扩大官方兼容承诺。

监控各区块独立加载，失败只在该区块显示“加载失败 · 重试”，或保留旧值并标“更新失败”，不伪造零值；运维监控关闭（404 `OPS_DISABLED`）时显示“运维监控未开启”和站长的开启入口；不会让监控失败抹去成功的概览。站点未提供必需字段时返回协议错误，避免默默填充不真实的统计值。服务端趋势查询本身还有 30 秒预算；客户端隔离慢查询不能替代服务器侧数据库优化。自动刷新、格式化与布局的受控测试不替代真实站点响应耗时或签名后 iPhone 验收。

金额用 Decimal 解码，写入为精确十进制字符串。余额原请求保留 `serverID`、`userID`、金额、操作、备注和 UUID。结果不明时仅允许复用原请求；站点身份不匹配会阻断请求。幂等有效期及最终状态以服务端为准，超出服务端记录保留期后应先通过 Web 对账。

会话失效、权限不足、验证码、TOTP/step-up、会话绑定不匹配和 `ADMIN_COMPLIANCE_ACK_REQUIRED` 分别显示中文原因。合规确认与二次验证在 App 内的全局 sheet 完成；Admin Key 与管理访问令牌不能完成需要邮箱会话的 step-up。刷新采用 actor 内共享任务；`TOKEN_EXPIRED` 对所有方法刷新后用同一请求重发一次，写入在合规或二次验证通过后需用户重新确认。

第二阶段再选定明确的官方版本执行兼容测试。新增其他后端支持应在 Sub2Core 适配层处理，不在各页面分散猜测字段。

## 趋势、列表与用户管理

用量趋势逐小时明细按时间倒序，最新桶置顶；图表本身仍按时间正序绘制。第四个“性能指标”趋势按需读取独立吞吐接口，默认近 1 小时，可选 6/24 小时，切换 RPM/TPM、点选和查看最新在上的性能明细；只在该页前台每次请求完成后间隔 30 秒刷新，离开、后台或切站取消。监控禁用、接口不支持、权限和超时在性能区局部显示，不用费用趋势合成性能数据。

性能读取 `GET /admin/ops/dashboard/throughput-trend`：`start_time` / `end_time` 一律写 UTC `Z`（近 N 小时时，`end_time` 为服务器现在向下取整到整分钟，`start_time` 前推 N 小时）；不传 `mode`（后端不读它，带模型筛选时强制走原始日志）；有分组筛选时带 `group_id`；有模型筛选、站点有 `ops.dashboard_model_filter` 且口径为 requested / upstream 时带 `model` + `model_source`，映射口径或没有该能力时不带模型、按全站显示，卡头会说明。服务端按窗口返回 `1m` / `5m` / `1h` 桶（≤ 2 小时、≤ 24 小时、更长），标签缺失或不认识时 App 按同一规则从窗口推算。RPM = `request_count × 60 ÷ 覆盖秒数`，TPM = `token_consumed × 60 ÷ 覆盖秒数`，覆盖秒数 = `min(bucket_start + 桶秒数, end_time) − max(bucket_start, start_time)`：首尾不满一桶的按实际覆盖时长折算，≤ 0 的点丢弃；峰值取各点最大值，平均 = Σ数量 × 60 ÷ Σ覆盖秒数；不把已舍入的 `qps` / `tps` 乘 60。请求包含成功与错误请求（不含 count_tokens 错误），Tokens 来自成功请求并包含缓存。当前后端此接口仍扫描原始 usage/error 日志，较长范围可能较慢，App 只接受 31 天 + 1 小时以内的范围。

账号和用户列表保留按登录身份保存的字段配置；本轮账号字段与运行数据的边界见下节。用户列表首层余额固定两位，原始 Decimal 不变。

用户支持创建及编辑邮箱、用户名、密码、角色、备注、并发和 RPM；创建可选初始 Decimal 余额，留空使用站点默认余额，既有余额调整保留独立页面。编辑只送实际变化字段，空密码不发送，空用户名/备注可明确清除。密码保留原始输入（不 trim），至少 6 个字符、最多 72 个 UTF-8 字节；仅存在表单和请求内存，不写入偏好、日志或未决文件，关闭即清除。

确认框绑定创建/编辑时的站点、地址、用户和会话身份，迟到结果不能更新新身份。并发变更使用固定 UUID 的 `Idempotency-Key` 和冻结原始正文；结果不明锁定表单，只允许手动确认重试同一请求，不自动重放。创建及不含并发的编辑当前后端不提供幂等重试，结果不明时须先核对列表/Web。二次验证完成仍需重新确认；Admin Key 禁止敏感操作或 TOTP 未启用时明确提示。关闭未决表单会警告原始请求只在内存中，关闭后不能自动恢复。

用户响应兼容字段：`notes`、`rpm_limit`、`current_concurrency`、`created_at`、`updated_at`、`last_used_at`、`last_active_at` 均可缺失/null；`last_login_at` 当前 DTO 不下发，不从活跃时间推断登录。创建和更新的角色只允许 `admin` / `user` / `vendor`；并发/RPM 接受非负整数，0 为不限制。站点有 `admin.idempotent_writes` 时新建与编辑都带 Idempotency-Key；没有时创建不带，PUT 仅在提供 `concurrency` 时带；余额使用原有独立金额幂等协议。

## 账号容量、在用指标与金额

用户列表首层余额使用 Decimal 固定两位小数，例如 `$12.50`；不改变原金额或余额写入精度。账号列表与详情分别显示“在用并发”和“在用 RPM”，前者读取 `current_concurrency`，后者读取 `current_rpm`；配置容量 `concurrency` 和基础 RPM 限额 `base_rpm` 单独展示。缺失在用 RPM 显示不可用，不填零，也不以基础限额代替。

“容量”汇总当前并发/配置容量、独立探测并发，以及已启用的窗口标准费用/限额、活跃会话/上限、RPM 当前值/基础限额和日/周/总配额。未下发的当前值保留不可用。详情账号快照与今日统计独立请求，两路读取由同一页面生命周期任务并行管理，今日慢查或失败不阻塞容量；父任务取消会传播到两路读取。任务使用本次渲染捕获的可见状态，防止初始停用任务迟启动后误发请求并在取消时留下“暂未加载”。详情只在前台每 30 秒刷新账号快照，离开、后台或切站取消，迟到结果不能覆盖新会话。列表支持可选前台每 30 秒刷新全部已加载页；选择、编辑、批量操作、离页和后台期间暂停，失败保留旧值。

账号今日统计将 `user_cost` 显示为“扣费”（向用户/API Key 实际收取），将原 `cost` 明确显示为“成本”（上游账号成本）；`standard_cost` 单独保留，不拿它补齐扣费。金额以 Decimal 解码并固定两位显示。列表仅在显示“今日统计”字段时使用一个当前已加载账号 ID 集合的批量请求，不逐行发起统计；详情使用单账号统计接口。批量失败只在统计区域提示，不清空成功账号快照。

账号共有 23 个可选字段：平台、认证类型、分组、在用并发、优先级、账号倍率、状态、调度、过期时间、最后使用、创建时间、备注、在用 RPM、配额已用、账号 ID、容量、今日统计、用量窗口、代理、负载系数、调度权值、上游声明倍率、基础 RPM 限额。开关、拖动/上下箭头排序和换行继续按登录 profile UUID 保存；名称始终保留。负载系数不是调度权值；只有调度权值列启用时，列表请求才设置 `include_scheduler_score=1`，避免默认计算候选池。详情不冒用列表调度分。

当前“用量窗口”字段显示服务端会话窗口起止时间；完整上游 5h/7d 百分比仍应通过 Web 查看，App 不自动发起 `/usage/batch` 或上游探测。代理仅解码名称、编号等显示数据。上游声明倍率读取已有探测快照，标记“上次探测”和时间；每次渲染检查有效截止，过期、缺失或不受支持时显示不可用，不保证到秒自动隐藏。不触发探测，不宣称它是已核验的当前实际扣费。

## 账号容量与今日统计契约

`GET /admin/accounts` 的 full/lite 列表和 `GET /admin/accounts/:id` 详情自带 `current_concurrency: Int`；full/详情另有 `probe_concurrency: Int`，lite 当前不返回探测数。普通在用并发从 Redis 槽位/租约扣除独立探测计数，并非配置 `concurrency`。后端读取并发失败会静默返回 0，客户端无法把该响应与真实空闲区分；可选字段缺失仍保持不可用。

`current_rpm: Int?` 为所有平台和认证类型的账号返回近 60 秒成功上游请求数，不受 `base_rpm` 是否配置限制。Redis 读取失败时缺失指标显示不可用，不以 0 或基础限额代替。概览 6 格的 RPM / TPM 读 `dashboard/home` 的 `rates`（近 5 分钟，TPM 含缓存 Tokens），与账号 `current_rpm` 的近 60 秒口径不同；`dashboard/stats` 的 `rpm` / `rpm_available` 只在旧站点退路的第三级使用（TPM 加 * 标注）。

容量还读取可选 `current_window_cost` / `window_cost_limit`（标准费用口径）、`active_sessions` / `max_sessions`、`scheduling_rpm` / `base_rpm`（自然分钟调度限流），以及 API Key/Bedrock 的 `quota_daily_used/limit`、`quota_weekly_used/limit`、`quota_used/limit`。窗口、会话、RPM 和日/周/总配额只在对应限额大于 0 时显示；基础并发始终展示，配置 0 保留为 0，不自行解释为无限。后端已处理过期日/周配额，手机不自行重置。`session_window_start/end` 是调度会话窗口，不是完整上游用量百分比。

`POST /admin/accounts/today-stats/batch` 正文 `{"account_ids":[1,2]}`，返回 `data.stats`，键为账号 ID 字符串。客户端去除非正 ID、去重、排序，空集合不发送，只接受本次请求的键；服务端先按工作区过滤，缓存 30 秒。`GET /admin/accounts/:id/today-stats` 返回同一统计对象。`user_cost = SUM(actual_cost)`；`cost = SUM(COALESCE(account_stats_cost,total_cost) × COALESCE(account_rate_multiplier,1))`，后者仅计入 `provider_cost_recorded`；`standard_cost` 是同条件下的标准费。今日起点由服务器时区决定。服务端批量 SQL 失败后回退单账号查询，失败项最终可能被补为零值，App 无法从成功响应识别这种后端降级；缺失键及 HTTP 失败不由 App 补零。

`load_factor` 是负载系数，与 OpenAI `scheduler_score` / `scheduler_scores` 不同。启用对应列才发送 `include_scheduler_score=1`；分组权值为基础分和粘性分，`sticky_score` 已含基础分，不能重复相加，`sticky_score_infinity` 优先显示 ∞。full/lite 都会采样实时数据；开启窗口限额的 Anthropic 账号还会执行窗口 SQL，ETag 在计算后生成，因此不能把列表或 304 宣称为纯轻量实时接口。

`extra.upstream_billing_probe` 是上游自行声明的已有快照；App 仅保留状态、历史倍率、观测时间和有效截止，每次渲染检查后只显示仍有效的历史观测，非严格计时失效；不保留凭据/代理地址/完整后端错误。没有自动调用 POST 探测或用量批量接口。普通字段与列表读取不新增逐行网络请求。
