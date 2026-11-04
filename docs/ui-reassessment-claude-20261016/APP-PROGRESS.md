# 原生 App 实现进度

按 [FINAL-SPEC.md](FINAL-SPEC.md)“实现顺序建议”分阶段实现。每个条目一个提交（之后可能跟着审查修正提交），提交前在 Mac 上跑工具链守卫、单元测试、编译与 UI 测试。

## 阶段 0 · 通用约定、会话与应用骨架

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S0-01 | 工具链锁定 Xcode 27.1，最低系统 iOS 26 | ✅ | `777623b` | Xcode 27.1 `27A9275` 由同号 RC 转正；单元测试 109 项与编译通过；UI 测试基线见下 |
| S0-02 | 错误信封、reason 总表与 APIError 改造 | ✅ | `145f9de` | 规格写“—/不显示”的组合用过渡文案（页面流程上线前现有页面直接显示错误）：TOKEN_EXPIRED“登录已失效，请重新登录”、STEP_UP_REQUIRED“该操作需要先完成二次验证”、423“需要先完成管理员合规确认”、TOO_MANY_IDS 用参数类文案、ACCOUNT_STATS_UNAVAILABLE 与 OAUTH_EXCHANGE_FAILED 用“站点暂时不可用”（20 章“服务器连不上 {平台}”待页面填平台）、PUSH_DELIVERY_FAILED 暂不带 provider_reason、未知 reason 的 429 写“请求过于频繁，请 N 秒后再试”。规格内冲突的取舍：USER_NOT_ACTIVE / BACKEND_MODE_ADMIN_ONLY 按请求上下文给文案与动作；STEP_UP_UNAVAILABLE 用 3.2 文案（2.6.2 带“，请稍后重试”的留给 S0-13 的验证 sheet）；ACCOUNT_TEST_BUSY 用 2.7.2、PUSH_DEVICE_LIMIT_REACHED 用 7.2、幂等各码用 2.5.4 与 30 章文案；未知 reason 的 400 归 `.response`（不归 `.validation`，资金写待核对判定不变）；其他 4xx 按 400 规则，1xx/3xx 写“服务器未能完成请求（HTTP N）”；不像错误码的 reason 不进主文案。文案暗含的 App 动作现有页面还不会做，留给对应阶段：409 业务冲突与 412 的“已刷新”、TOO_MANY_IDS 拆批、SINCE_ID_WITH_PAGE 退回第 1 页、ACCOUNT_STATS_UNAVAILABLE 显示“—”、非 JSON 404 隐藏功能、OPS_DISABLED 区域显示。“不可用”全局改“—”留给 S0-08（本条只有 diagnostics 用“—”）。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过） |
| S0-03 | AdminMe、capability 常量与模型放宽 | ✅ | `46acec7` | me() 取代 verifyAdministrator，类型名按规格与 D15 用 AdminAccessToken / AdminComplianceStatus（不叫 AccessTokenItem）。对规格的补充：Admin Key / sat_ 旧服务端路径同时并发拉 settings/public（取版本与时区，失败容忍）；admin/compliance 也是非 JSON 404（2026-06 之前、没有合规守卫的站点）时退回 dashboard/realtime 探针，全仓只此一处；JWT 旧服务端三调里 auth/me 失败照抛、settings/public 失败视为未知、admin/compliance 仅非 JSON 404 视为未知。Page.hasMore 保持 Bool（has_more → pages → total），原始值为 reportedHasMore。PublicSettings 另保留 site_logo、渠道监控、支付、订阅字段；冲突改由登录页抛 CAPTCHA_PROVIDER_CONFLICT 的目录文案。D33：未知 AuthenticationKind 按 password 解码，profiles / profileArchive 逐条容错；升级后不支持装回旧版 IPA（旧版读不到 accessToken）。行为变化：合规未确认的 Admin Key 站点现在可连接（以前 realtime 返回 423 连不上），之后的请求按 423 文案提示，全局合规页归 S0-13；账号页重新加载期间总数显示“—”。暂不做（归后续条目）：me 结果存进 SiteSession、sat_ 连接后取 scope（注意 admin/access-tokens 不在合规豁免里，合规未确认时返回 423，S0-10 按可写处理、S0-13 确认后补取）、LoginBody 的 captcha_provider / aliyun_captcha_param、登录页 sat_ 自动识别。S0-02 的 APIErrorMappingTests 冲突断言改为“解码成功且报告冲突”。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过）；编译输出里 CaptchaView.swift:91 的警告在本条之前就存在，见 BACKLOG |
| S0-04 | 请求层：请求头、X-Device-ID、续期重发、自动重试、429、超时 | ✅ | `8bbffb6` | 按 D01 分层：requestWithHeaders → send（读重试）→ sendAttempt（刷新重发）→ transmit（唯一传输出口，刷新也经它），failure / surfaced 是唯一的错误构造与出口（surfaced 本条原样返回，S0-11 接上报），pause / check / currentGeneration / endpointURL / sendAttempt 留作 S0-05 / 06 / 07 / 11 / 13 / 19 挂点；request<T> 保留为薄包装，现有调用点不改。与规格不同的取舍：00 §0 硬规则 5“写请求重发前回到确认框”只用于 STEP_UP_REQUIRED 与 423，TOKEN_EXPIRED 与 reason 未知的 401 按 §1.7.2 / §2.4 / §3.3 / §9.1 在请求层刷新后同字节、同 X-Request-ID / Idempotency-Key 重发 1 次（.auth 除外）；读请求的 503 只在 reason 为空或 SERVICE_UNAVAILABLE 时自动重试（ACCOUNT_STATS_UNAVAILABLE 等交给区块下个周期）；所有非 GET（含登录、2FA、刷新、退出、SSE）都带 X-Request-ID；SSE 超时沿用传输层 30 / 180 秒。刷新判定只看 ReasonCatalog 的 .refresh 行（D06），清会话后同一 client 不再联网、直接抛同一错误；保留会话按 2 / 5 / 15 / 30 秒退避，access 已过期时抛 refreshDeferred“暂时无法续期登录，正在重试”。超时按 R07 / U54 统一为 RequestTimeout：日志列表 45 → 20 秒、错误详情 30 → 20 秒、usage/stats 90 → 45 秒（用户详情本月用量原先漏改、仍为读请求 20 秒，审查修正后同为 45 秒）、统计页 trend / models / groups 60 → 45 秒、概览监控 15 → 45 秒；统计聚合 45 秒、dashboard/stats 90 秒超时后仍会自动重试 2 次（最坏约 4.5 分钟），待阶段 1 / U54 实测后评估。已知代价：UA 改为 Sub2Mobile-iOS 后，开启会话绑定且原生模式为 strict / ua_only 的站点需重新登录一次。未做（归后续条目）：deviceID 由 S0-10 从 Keychain 传入（之前为 nil，不发 X-Device-ID）、清会话后的 Keychain 擦除与回登录页归 S0-11、带 key 写的确认结果流程归 S0-06、ETag 归 S0-05、Date 头偏差归 S0-07、请求日志归 S0-19；页面上 refreshDeferred 横幅与区块 429 推迟归 S0-09（D23）。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过）；CaptchaView.swift:91 警告为既有 |
| S0-05 | ConditionalCache：ETag 缓存与 304 透明处理 | ✅ | `353e913` | 按 R08 在 APIClient 层透明处理：白名单为 00 §4.2 的 8 个 GET 与 POST accounts/today-stats/batch，各页面方法签名不变、不感知 ETag；20 §1.2 / §1.7 的 AccountListPage.etag 与“每页记 ETag”、30 §1.7“返回同时带 ETag”、50 §1.7 groupList(etag:) 后续条目一律不实现。不按 lists.etag 门控（旧站点不发 ETag 就不存条目、不发 If-None-Match），也不因有 ETag 缩短任何轮询。与规格不同的取舍：缓存原始成功响应体与响应头，304 时合成 200 重新走原解码（省带宽、不省解码）；POST 键用请求体原字节代替哈希；只在最终 401 时清空本站缓存（TOKEN_EXPIRED 刷新成功不清）；没有缓存条目可用的 304 按 invalidResponse 抛出；304 返回时 APIResponse.status 为 304、响应头以 304 的新头为准。身份 = user.id + auth_method，由 me() 设置（缺 auth_method 时用新增的 AdminAuthMethod.resolved 按凭据推断，旧服务端 Admin Key 为 (nil, admin_api_key)）；身份未知时不发条件请求、不存缓存，-ui-testing 路径因此不受影响。AppModel.connect 把候选 client 的身份传给正式 client（最小接线），S0-10 重写 connect 时由 ClientWiring 继承，不得丢失。requestClock 由 private 改为 internal（扩展文件取当前时间，S0-06 同样要用）。未做（归后续条目）：账号详情 "cv-N" 不进缓存、可从 requestWithHeaders 的响应头取得，account(id:) 返回 ETag 的变体与 PATCH If-Match 留到阶段 2（20 §2.7、§3.7）；切站、会话失效时调用 clearConditionalCache() 归 S0-11；dashboard/home、ops/dashboard/snapshot-v2、meta/catalog 的方法在阶段 1 / 2 建，建好后自动走缓存。给后续页面的提醒：304 复用的响应体里，被后端排除在 ETag 计算之外的字段是旧值（dashboard/stats 的 uptime；dashboard/snapshot-v2 的 generated_at、query.generated_at、stats.uptime；dashboard/home 的 generated_at、rates 与 ops 的 start_time / end_time、availability.collected_at），阶段 1 的“更新于”一律用本机拿到响应的时间，S0-07 的时钟偏差只用 Date 头。URLSession 对手动 If-None-Match 的 304 只经桩测试覆盖，真机确认见 BACKLOG。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过）；CaptchaView.swift:91 警告为既有 |
| S0-06 | 幂等写：WriteOutcome、结果判定、PendingMoneyWrite 与金额编码 | ✅ | `270212b` | 按 D01 / D03 / D04 / D12 / D15 接 S0-04 原语：执行器每次尝试走 sendAttempt，等待用 pause 与 requestClock，业务错误经 failure → surfaced，超时用 RequestTimeout.keyedWrite，可重试状态用 RequestPolicy.isRetryableStatus，Retry-After 用 S0-02 的 RetryAfter.resolve；未新建 RetryClock / ManualRetryClock。与规格不同的取舍：PendingMoneyWrite 的 createdAt 与用户字段经 summary 读（D16，Swift 协议属性类型须一致，旧余额记录 createdAt 为 nil）；503 按 marker 分三种（IDEMPOTENCY_STORE_UNAVAILABLE 不重试、10 秒后才允许同编号重试；无 reason 或 SERVICE_UNAVAILABLE 按传输失败同 key 重试；其他 503 按业务错误）；带 key 写收到 429 不自动重试（按 00 §2.7.2，2.4 表“退避后用同一 key”读作手动重试不换 key）；RETRY_BACKOFF 与 IN_PROGRESS 共用“首次收到起 30 秒”预算；X-Idempotency-Degraded 任意非空值都算降级（后端还会发 store-unavailable）；按 00 §9.1 返回 WriteOutcome（不按 30 §3.7 的元组），失败时 action id 在 KeyedWriteFailure.actionID 或 APIError.actionID；后端只在 2xx 发 X-Idempotency-Expires-At，待核对记录实际拿不到，effectiveExpiresAt 回退 createdAt + 24 小时，解析暂用 ISO8601DateFormatter（S0-07 落地后可换 ServerTime）；R05：现有用户编辑页与余额页仍在“核对并确认”时生成编号（之后表单锁定、确认框不改内容，与确认时生成等价），阶段 3 重写时改到确认那一刻。有意的行为变化：余额调整与带 key 的用户编辑（含并发修改）遇超时、断网、502 / 504 / 代理 503 会自动同 key 重试 2 次，IN_PROGRESS 最多再等 30 秒，最坏约 2 分钟；按 D31 余额页发送中改为“正在确认结果…”并加“稍后核对”（balance.later，取消本地任务、记录保留待核对）；用户编辑页 409 EMAIL_EXISTS 归入明确拒绝。未做（归后续条目）：新记录 actorUserID 与重试权限 → S0-12（D17）；新建 / 编辑用户按 admin.idempotent_writes 带 key → S0-10（D24，现在都传 false）；“仅前台”重试（suspend 打断等待转待核对）→ S0-11（D18，挂点 waitToRetry）；三类文件、PendingRedeemBatch 与 generate 金额 JSON number 的测试 → S0-12；STORE_UNAVAILABLE 冷却期按钮置灰、余额结果判定重写（INVALID_BALANCE、无 reason 的 400、404、429 视为未执行）、已等待秒数显示 → 阶段 3；登录页 / 设置页待核对列表改用 PendingMoneyWriteLine → S0-15。审查修正：同一次发送里前面的尝试结果不明（超时、断网、502 / 504 / 代理 503、IN_PROGRESS、RETRY_BACKOFF）后，后面的重试在执行前被拒（取不到有效凭据或刷新被拒、401 / 403 / 423 / 429）不再当作明确拒绝，改为 KeyedWriteFailure.unconfirmed(.transport)，lastError 带原错误（经 surfaced），余额页因此保留待核对记录、用户编辑页保留冻结的请求；业务错误（如 INVALID_BALANCE）经过幂等层，仍按明确结果处理。30 §3.4、60 §19.4 的“401 / 403 / 423 删除记录”只适用于前面没有结果不明的尝试。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过）；-ui-testing 下余额写入不执行，“稍后核对”按钮没有 UI 测试覆盖，见 BACKLOG；CaptchaView.swift:91 警告为既有 |
| S0-07 | 服务器时间、时间解析、查询编码与 since_id 增量 | ✅ | `6aae86d` | 新增 ServerTime.swift（ServerTimeZone / ServerTime / QueryMetadata / ClockSample / ServerClock / optionalTimestamp / optionalUnixTime，名字按 D15）与 IncrementalList.swift（00 §4.3 纯逻辑）。APIClient 按 D02 / D03 在 init 末尾追加 serverTimeZone（默认 .device）与 serverClock，新增 setServerTimeZone / serverTimeZone；me() 拿到可解析的时区即更新；dates / dateRange / monthRange 改为服务器日历 + serverClock.now()；Date 头只在 transmit 与 openStream 记录（含错误、304、刷新，D01 ②）；"+" → %2B 只写在 endpointURL（D01 ⑧，缓存键一致）。dashboardTrend 返回 DashboardTrendReply（时区 = query.timezone，退回请求时的时区，在 await 前捕获）；trendDate 与 series 去掉 .current 默认值，概览趋势图按回执时区解析、分桶、标注（Chart 加 \.timeZone / \.calendar）。AccountBillingProbe、ListFieldPresentation.timestamp、PerformanceTrend.Point、RequestLogPresentation.date、WriteOutcome 的 X-Idempotency-Expires-At（S0-06 留的替换点）改调 parseTimestamp；AnalyticsQuery、RequestLogFilter、性能趋势的 start_time / end_time 改调 utcTimestamp，输出字节不变。与规格不同的取舍："+" 编码作用于所有查询值（规格只禁 +08:00，搜索词里的 + 以前被 Go 解成空格）；"Local" 等 Apple 不认识的时区名原样发送、本地运算按 server_utc_offset；偏移与“UTC+8”标签按 TimeZone 在当时计算（跟随夏令时），格式 UTC+8 / UTC+5:30 / UTC−3（U+2212）/ UTC+0；两处都拿不到时区时用设备时区、三种提示都不显示；时钟偏差只放内存、每个 APIClient 一个，sampled_at 同时更新全局偏差；游标在合并后的列表上计算且只进不退，没有足够旧的行且没有上次游标时下一次退回 page=1，首屏没有 latest_id 时用本批最大 id − 200；Unix 秒 0 与负数视为未设置；400 since_id 回退按 ReasonCatalog 的 restartFromFirstPage 判定；trendAxisLabel 保留 .current 默认值供 PerformanceTrendView 暂用。最小接线：AppModel.connect 让正式 client 继承候选的 serverTimeZone 与 serverClock，S0-10 并入 ClientWiring（D13）；DemoData.serverTimeZone（Asia/Shanghai，+08:00）是 UI 夹具唯一的服务器时区（D30）。未做（归后续条目）：SiteSession 保存时区与旧站点 Admin Key 的公开设置退路 → S0-10；AnalyticsQuery 默认时区、usage 列表 timezone、PerformanceTrendView 轴标签、日志页接入 IncrementalList（N=500、时间窗裁剪、10 次校准）→ 阶段 4（D29 白名单）；“· 按 UTC+8”等提示显示 → 阶段 1 / S0-15 / 阶段 4；ServerClock.now() 的消费 → S0-08 / S0-17 / 阶段 2。审查修正：IncrementalList 的 limit 在每次合并与重置时生效，“加载更多”超出 N 的行只保留到下一次合并（注释原先写反）；日志页按 40 §6.6 只在列表靠近顶部时裁尾，应传 limit: nil 并自行调用 trimmed(to: 500)，补了“加载更多后再合并”的测试（审查修正的 gate：unit 331 + 4、build 通过；UI 31 / 35，两次都失败的 Sub2MobileUITests 趋势缩放、AccountList 的 testCapacityAndNewFields… 与 testTodayStatsFailure… 在基线名单内，testAccountRuntimeUsesOccupancyAndSeparatesUserChargeFromCost 是等待行标签超时、失败信息里标签已含期望值，属于负载下快照停顿，本修正只改 Sub2Core 注释与单元测试）。单元测试 310 + 4 通过（原 267 + 4）。UI 测试已运行：gate 6 并发两次均 UI_EXIT=65，最终代码 33 / 35 通过；两次都失败的是 AccountListCustomizationUITests.testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs（基线名单内）与 Sub2MobileUITests.testDashboardSlowTrendDoesNotDelayCountersOrMonitoring（登录后第一次无障碍快照停顿 16–20 秒，超过夹具 8 秒的趋势延迟，于是断言“趋势未到”失败）；同一台 Mac、同样负载下基线 709c047 也出现 15–19 秒停顿（基线全量 32 通过，趋势缩放用例两次失败），最终代码单跑该用例、以及 3 并发跑 Sub2MobileUITests（17 个全部通过，含趋势缩放）都通过，判定为负载下的既有不稳定，见 BACKLOG；重跑后通过的：AccountList 三个、UserManagement 字段顺序；CaptchaView.swift:91 警告为既有 |
| S0-08 | DisplayFormat：全 App 唯一的数值与时间格式 | ✅ | `776ecb9` | 新增 DisplayFormat.swift（money / moneyCompact / moneyLineItem / moneyExact / grouped / compact / rpm / ratioPercent / percent / change / decimal / duration 三种样式 / relativeTime / countdown / minutesLeft / clock），缺失、NaN、非有限值一律“—”，金额在 Decimal 里 .plain 舍入、千分位固定“,”、U+2212 负号、舍入为 0 不带负号；DashboardPresentation 只留 performanceWindow 与趋势日期，compactNumber / cost / compactCost / money / duration / rpmValue / fixed 与 NativeApp 全局 money(_:) 删除，新增 DashboardStats.availableRPM、DashboardTrendMetric.axisLabel、PerformanceMetric.format；概览、性能趋势、统计、账号、日志、用户、分组与登录 / 设置 / 余额页的待核对行全部改用。规格没写清、本条定下的取舍：跨档按舍入后的值（999,950 → 1M、99.96 秒 → 100s、RPM 9.96 → 10、999.6ms → 1.0s、$999.995 → $1.00K）；RPM 小于 10 照字面保留 1 位（2 → 2.0、0.04 → 0.0）；.percentile 与 .millis 规则相同、共用实现，平均响应与日志总耗时 / 首 Token 用 .list，错误详情的上游 / 响应耗时用 .millis；moneyCompact 只用 K 且 K 前加千分位，compact 不加千分位（1000B）；change 舍入为 0 写“0.0%”不带箭头；minutesLeft 整点写“2 小时”；relativeTime 未来 60 秒内写“刚刚”、跨年不带年份；countdown 秒数向上取整（设计稿是四舍五入）。规格之外新增：moneyLineItem（日志行单条，先舍入到 4 位，0 写 $0.00，≥ $1 用 2 位）、moneyExact（确认框与待核对行回显管理员输入的金额，不舍入、至少 2 位）、decimal(_:minFractionDigits:maxFractionDigits:)（D15 唯一十进制格式：调度权值 2 位去尾零、QPS 2 位、趋势 Y 轴小于 1000 用 1 位）。其他可见变化：请求详情金额固定 4 位、脚注改“四位小数”；用户本月 Tokens 改紧凑数；分组的绑定 / 活跃 / 限流账号数缺失显示 0（6.5）；两处说明句“显示不可用”改“显示 —”。有意不改：账号、分组、上游探测的倍率仍显示服务端原值全部位数（规格无倍率格式，见 BACKLOG）；原 DashboardPresentation.fixed 不保留，Decimal 舍入并入 DisplayFormat 的 internal rounded / number。未做（归后续条目）：告警数值按 D21 由 S0-18 用 percent / grouped / decimal；relativeTime / countdown / minutesLeft / clock 本阶段还没有页面调用（now 由调用方传 ServerClock.now()、时区传服务器时区），归 S0-17 与阶段 1–4；绝对时间戳（ListFieldPresentation.timestamp、RequestLogPresentation.date）仍按设备时区与地区设置，归阶段 2 / 3 / 4；术语改名（差额 → 利润等）归页面重写。单元测试 330 + 4 通过（原 310 + 4）。UI 测试已运行：gate（开始时脚本默认 6 并发）UI_EXIT=65，32 / 35 通过，重跑后通过的是 AccountListCustomizationUITests.testMissingRuntimeRPMStaysUnavailableDespiteConfiguredLimit（本条改了它的“—”断言）与 Sub2MobileUITests.testDashboardSlowTrendDoesNotDelayCountersOrMonitoring；两次都失败的 3 个都在基线名单内、失败点与本条改动无关：Sub2MobileUITests.testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection（第 210 行放大、第 233 行回滑等待超时，在本条改过的断言之前）、AccountListCustomizationUITests.testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs（字段开关未切换 / 点按后未移动）、testTodayStatsFailureDoesNotBlockListOrDetailRuntime（等待“在用并发、2”“在用 RPM、37”超时）。随后按新默认 3 并发单跑 Sub2MobileUITests：17 / 17 通过（UI_EXIT=0，含趋势缩放用例里本条改的 $0.14、1.4M、205 次与性能明细 TPM 690K；testDashboardMissingAccountCostLoadsIndependentSnapshot 重跑后通过）。CaptchaView.swift:91 警告为既有 |
| S0-09 | 视觉令牌 Palette / Tone 与区块状态 BlockState / LoadState | ✅ | `516f5a3` | 新增 Tone.swift（Tone 与 drawsRail、Tone.httpStatus、Tone.alert(severity:status:)、AccountScheduleState 的状态词与色调，rawValue 对齐后端 7 个常量，allCases 按 STATE_ORDER）、BlockState.swift（BlockState、BlockDisplay 显示规则、D23 的 BlockRefresh）、Palette.swift（36 个令牌照抄 vernier-palette.css，PaletteParityTests 逐值比对浅色与深色）、LoadState.swift、ToneViews.swift（StatusCapsuleMetrics、ToneBadge、StatusBanner，本条不接页面）。与规格不同的取舍：Tone 只有 Sub2Core 一个枚举，Palette.swift 用 extension 补 base / ink / wash（D20，00 §8.2.6 字面写在 Palette.swift）；BlockState.loading 加 at，loading / failed 里的 previous 与 at 都是上一次成功的值和时间；类型名用 LoadState，后续章节里的 DashboardLoadState 一律按 LoadState 读；不在 100…599 的状态码按缺失归 neutral，3xx 照设计稿归 critical；disabled(reason:) 存后端 reason 码、failed(reason:) 存目录文案；退避按“加倍、300 秒封顶”实现（60 → 120 → 240 → 300，规格示例写 60 → 120 → 300，见 BACKLOG）；横幅图标用 tone 本色（00 §8.2.2，设计稿 CSS 用 ink）；徽章字号与高度随动态字体缩放。D23 接入：LoadState 记录 BlockRefresh，429 后在 retry_after（缺省 30 秒）内 load 直接返回、不发请求、不改状态，throttleMessage 给出“请求过于频繁，N 秒后自动重试”；DashboardView 三个 30 秒轮询改为 nextDelay(base: 30)（连续失败 30 → 60 → 120 → 240 → 300 秒，成功恢复；429 按剩余等待）；其他页面轮询不变，60 秒基准、倒计时文案与区块小视图留给阶段 1 的 LiveOpsStore。行为变化：账号今日统计两处与性能趋势切换时间范围改用 reset()，旧错误一并清掉；429 等待期内手动重试不发请求（页面仍显示目录文案“请求过于频繁，请 N 秒后再试”）。审查修正：429 等待期内 reset() 保留失败文案（只清旧值），不再留下既无数据也无提示的空白区块；429 等待最长 300 秒（与退避封顶一致），超大 Retry-After 不再让轮询长期停住或在 Task.sleep / throttleMessage 处溢出。未做：现有页面系统色换令牌（改到对应页面时做）、StatusRail 归 S0-14、AccountDisplayState 归 S0-17、AlertPresentation 归 S0-18。单元测试 347 + 4 通过（原 331 + 4）。UI 测试已运行：gate（3 并发）UI_EXIT=65，33 / 35 通过；两次都失败的是 AccountListCustomizationUITests.testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs（基线名单内，字段开关未切换）与 testAccountRuntimeUsesOccupancyAndSeparatesUserChargeFromCost（等待行标签含“在用 RPM、37”超时，失败信息里标签已含期望值，与 S0-07 记录的负载下快照停顿相同）；重跑后通过的：testMissingRuntimeRPMStaysUnavailableDespiteConfiguredLimit、testSlowTodayStatsAllowsIndependentRuntimeRefresh、Sub2MobileUITests.testDashboardSlowTrendDoesNotDelayCountersOrMonitoring。随后单跑 AccountListCustomizationUITests 7 / 7 通过（UI_EXIT=0，testAccountGroupsConcurrencyAndFieldOrderPersistAcrossTabs 重跑后通过），单跑 Sub2MobileUITests 16 / 17，唯一失败的 testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection 在基线名单内（缩放 / 回滑等待超时，与 S0-08 相同）。CaptchaView.swift:91 警告为既有 |
| S0-10 | 会话：deviceID、凭据迁移、登录请求体、me() 连接与 SiteSession | ✅ | `7690208` | CredentialVault 加可注入的 SecureItems 层（真机 KeychainItems、内存模式 MemorySecureItems，字节编解码相同）；deviceID 存 `<站点 UUID>.device`（WhenUnlockedThisDeviceOnly、小写），只在不存在或内容不是 UUID 时重新生成，其他 Keychain 错误照抛。删除语义按 D07：remove = 删站点（凭据 + deviceID + 租约），eraseCredential = 只删凭据（退出、revoke(erase:)、LeasedCredentialStore.remove），退出后再登录同一站点 deviceID 不变；commit 带草稿 deviceID 时先写设备 ID 再写凭据，失败或被取代的尝试经 abandon 收回（站点未保存且没有更新租约时删草稿 ID）。Sub2Core 新增 LoginWire.swift（LoginClient / LoginBody / LoginReply）、AuthPresentation.swift（D10 文案）与唯一的 postLogout（D15）；login 增加 deviceName、declaresCaptchaProvider，client.device_id 与 X-Device-ID 同取 deviceIDHeader，2FA 第二步不带 client；非 admin 先丢弃刚签发的会话再抛 administratorRequired；deviceID 按 D02 改为必填（测试用 internal 构造、testingDeviceID）。NativeApp/Session 新增 SiteSession（establish：me → isAdministrator → sat_ 取 current 项 scope → 时区 → Date 头偏差 → 由凭据推导 refreshTokenUnavailable）与 ClientWiring（D13，S0-05 / S0-07 的接线已并入）；AppModel 新增 siteSession、SessionContext.site / has / isReadOnlyToken、reloadSiteSession、markAccessTokenReadOnly、deviceName，connect 拆为 probe / commit / publish，先生成 generation 再造 client、同步发布。D24：用户编辑页按 admin.idempotent_writes 带 Idempotency-Key。与规格不同的取舍：00 §9.6“remove 同时删 deviceID”按 D07 拆分，退出不删 deviceID；只读判定按后端 ReadOnly()（scope 已知且不等于 write），scope 未知按可写；me 显示 compliance.required=true 时不请求 admin/access-tokens（受合规守卫必为 423），S0-13 确认后调 reloadSiteSession 补取；时区只用 ServerTimeZone.resolve（D09），只有 server_utc_offset 没有时区名时退回设备时区；administratorRequired 文案改为 1.11 原文“当前版本仅支持管理员账号”；登录页删去已不可能触发的角色检查；RequestLayerTests 原“不传 deviceID 不发头”改为“测试构造固定发 testingDeviceID”。UI 夹具：密码方式改为 .tokens 夹具（DemoData.passwordCredential），Key 方式用 Credential.fromAPIKey；DemoData.adminMe 全部能力、Asia/Shanghai（D30）、合规已确认、step-up 关；预留 -ui-readonly-token；-ui-testing 下 logout 不再发网络退出请求（S0-11 重写退出时须保留这层保护）。旧版保存的 sat_ 站点要等下一次连接才把 profile.authentication 改为 accessToken，未连接时设置页兜底文案暂显示 Admin Key。重装后 Keychain 里旧站点 UUID 的凭据与 .device 条目成为孤儿（站点列表已清空），不含可用会话，未清理。sat_ 主人被禁用时登录返回 401 USER_INACTIVE，本条原样抛出，文案映射归 S0-16。未做（归后续条目）：退出顺序与 logout 带 Authorization（复用 postLogout）、删除 sat_ 站点吊销令牌、回前台超过 5 分钟重探测 → S0-11；合规 / step-up / ACCESS_TOKEN_READ_ONLY 全局处理 → S0-13；登录页重写 → S0-16；设置页重写 → S0-15；R18 横幅 → 阶段 1（SiteSession 已提供 refreshTokenUnavailable、accessTokenExpiresAt）。单元测试 360 + 30 通过（原 347 + 4）。UI 测试已运行：gate（3 并发）UI_EXIT=65，32 / 35 通过；两次都失败的 Sub2MobileUITests.testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection 与 AccountListCustomizationUITests.testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs 在基线名单内，testMissingRuntimeRPMStaysUnavailableDespiteConfiguredLimit 两次都是等待行标签超时、失败信息里标签已含期望的“在用 RPM：—”（负载下快照停顿，本机基线 base-ui 也失败过一次），随后单跑 AccountListCustomizationUITests 时该用例通过；单跑中失败的 testAccountFieldPreferencesAreIsolatedBetweenSameSiteIdentities、testCapacityAndNewFields…、testTodayStatsFailure…（基线名单内）与 testAccountRuntimeUsesOccupancy…（标签已含“$0.12”仍超时，S0-07 / S0-09 记录过）都与账号页之外的会话改动无关；会话相关的 testLogoutErasesCredentialInsteadOfRestoringSession、testSameStationKeepsNewLoginAsSeparateIdentity、用户管理 3 个用例全部通过。CaptchaView.swift:91 警告为既有。审查修正：reloadSiteSession 改在第一次 await 之前读会话代号（此前切站可让旧站点的探测结果写到新会话上），代号已变就不再用旧 client 探测；探测期间收到的 ACCESS_TOKEN_READ_ONLY 标记不再被回退 scope 覆盖（SiteSession.keepingReadOnlyMark，访问令牌 scope 不可改）；代号顺序在 AppModel.swift，没有单元测试覆盖。审查修正的 gate：unit 394 + 47、build 通过；UI 37 / 38，两次都失败的 testAccountRuntimeUsesOccupancyAndSeparatesUserChargeFromCost 失败信息里标签已含期望值（Mac 负载 57–134 下快照停顿），随后带本修正单跑通过。 |
| S0-11 | 会话：退出与删除站点顺序、切站、前后台、会话失效处理 | ✅ | `9b2091d` `68010bf` `e8f4c38` | 按 D28 拆三次提交。11a（Sub2Core）：SessionInvalidation 只看 APIError.action（clearSession / clearCredential），cause 由 category 推出、文案取错误自身；APIClient.init 末尾加 onSessionInvalid，只在 surfaced 上报、每个代号一次、cancelAll 后不报；logout 的 JWT 分支改用 postLogout（带 Bearer 与 X-Device-ID，refresh 为空发 {} 也照发）；新增 AuthSessions.swift（sessions / revokeSession(id:) -> Bool / revokeOtherSessions 固定 {"keep_current":true}，非账号登录本地拒绝）、revokeAccessToken(id:) -> Bool、Push.swift 的 deletePushDevice(id:)；D06 一致性测试覆盖 1.7.2 各行与刷新 400、refresh token 为空。11b：APIClient.suspend() / resume()（epoch 栅栏，只停读、批量读、读与带 key 写的等待、账号测试 SSE；不改 generation、不取消刷新单飞与已发出的写），带 key 写在等待中被 suspend 打断 → unconfirmed(.transport)；SessionLifecycle（只有后台暂停，回前台距 SiteSession.probedAt 超过 300 秒才 reloadSiteSession）；RootView 唯一的 scenePhase 处理；foregroundRevision 让用户、分组、请求记录、统计分析 4 页回前台重载第 1 页。11c：SiteTeardown（推送设备 → sat_ 删除站点时吊销 current / JWT logout，20 秒总时限，两种备注）、PushDeviceRecords（UserDefaults 按站点）、LoginPrompt（D17：地址不变且无待核对记录才沿用站点 id，沿用时用该站点原 deviceID 登录）；AppModel 的 endActiveSession 统一本地擦除，AppModel+Session.swift 放 logout / remove -> TeardownReport? / switchTo / connectionFailed / invalidateSession / forgetActiveSession；凭据已清除或会话失效进入该站点的预填登录页（根页面或 sheet），不再弹 alert；站点 ··· 标识 settings.site.more.<名称>，sat_ 删除确认加“同时吊销这个管理访问令牌”。与规格不同的取舍：进入后台用 suspend 而非 cancelAll（cancelAll 会换掉写身份、取消刷新单飞）；退出与删除站点都先本地擦除、再用凭据与 deviceID 副本建无 store 无回调的收尾 client 发网络请求（60 §3.4 把删 Keychain 写在网络之后）；收尾总时限 20 秒为本条自定；切站沿用候选机制（先验证再换代号）；服务端退出失败不再弹窗，只记 os.Logger；SessionInvalidation 显式构造要传 message（不内置文案）。为扩展文件可写，AppModel 的 isSigningOut、profileArchive、persistProfiles、lifecycle、sceneTask 改为 internal。未做 / 留给后续：删除站点备注暂用根视图 alert（标题“操作未完成”），S0-15 改回执；设置页删除中的行尾进度留给 S0-15；hasPendingRecords 只看余额记录，S0-12 扩到三类；增量游标阶段 0 没有全局存储，阶段 4 日志页把游标绑在会话代号上；ETag 缓存每个 client 各有一份，结束会话时显式清空。单元测试 394 + 46 通过（原 362 + 30）。UI 测试已运行：11a gate 33 / 35（第一次 SSH 超时重跑；两次都失败的 testCapacityAndNewFields…（基线名单）与 testDashboardSlowTrendDoesNotDelayCountersOrMonitoring，后者单独重跑通过，当时 Mac 负载 28）；11b gate 33 / 36，两次都失败的 3 个都在 AccountListCustomizationUITests 基线名单内；11c gate 35 / 38，两次都失败的 testDashboardTrendSupportsMetricsZoomScrollingAndExactHourlySelection、testCapacityAndNewFields…、testTodayStatsFailureDoesNotBlockListOrDetailRuntime 均在基线名单内，新增的 testBackgroundAndForegroundKeepsSession、testRemovingActiveStationReturnsToLoginWithoutIt、testRevokedSessionReturnsToPrefilledLogin 与改写的 testLogoutErasesCredentialInsteadOfRestoringSession 都通过。gate 期间 Mac 负载多次冲到 100–600（模拟器 PosterBoard / SetStoreUpdateService 大量进程），见 BACKLOG。 审查修正：scenePhase 处理从 RootView 移到 Sub2MobileApp，读全 App 汇总阶段（iPad 多窗口时一个窗口进后台不再暂停仍在前台的窗口共用的 client；仍是全 App 唯一一处）；用户详情、分组详情、错误详情与请求记录的“查看账号”页也随 foregroundRevision 重读（此前进后台时在途读被 suspend 取消，回来停在转圈或“暂未加载”）；删除 sat_ 站点时只有 clearCredential（INVALID_ADMIN_KEY / ACCESS_TOKEN_EXPIRED）与 404 算令牌已失效，USER_INACTIVE、兜底 401、WORKSPACE_DISABLED 等记为未吊销并加备注；删除本机已无凭据的站点时按确认框的承诺报告未完成的吊销与推送设备移除（SiteTeardown.unsentReport，服务端清除凭据后的 sat_ 站点也会提示）。单元测试 419 + 58 通过；详情页重载与多窗口没有 UI 测试（夹具不经过 client）。gate：UI 34 / 38，两次都失败的 testCapacityAndNewFields…、testSlowTodayStats…、testTodayStatsFailure…、testDashboardTrendSupportsMetrics… 都在基线名单内；重跑后通过的 testAccountGroupsConcurrency…、testAccountRuntimeUsesOccupancy…、testDashboardSlowTrend… 与 testCreateThenEditUserFieldsAndLeavePasswordUnchanged（首次为密码框拿不到键盘焦点，Mac 负载约 80，脚本因日志折行未计入 UI_FLAKY）。 |
| S0-12 | 资金写待核对：三类本机记录、持久化与核对 | ✅ | `9d5e5f0` | PendingMoneyLedger（NativeApp/Session，macOS 可测）：pending-balances.json（不迁移）、pending-redeem-batches.json、pending-compensations.json 共用 persist(_:to:)（原子写入 + completeFileProtection，UI 测试 memoryOnly），不可变账本落盘成功才替换；某类读不出只暂停这一类，且该类不 remember 也不 resolve、绝不覆盖原文件；同 id 同请求体可更新元数据、不同请求体报冲突。AppModel 只保留 pendingMoney 与 updatePendingMoney，包装放 AppModel+Pending.swift（列入 Package.swift exclude）：三类计算属性、persisted / remember 三个重载、resolve(any)、pendingMoneyWrites(serverID:)、moneyWriteGate、retryPermission、reconcile（只有确认已执行才自动 resolve）、reloadUnreadablePendingRecords（回到前台调用）；hasPendingRecords 扩到三类。Sub2Core：UserAdjustments（R19 唯一的 userAdjustments(query:)）、RedeemCodes（RedeemCodeType、AdminRedeemCode、RedeemCodeListQuery 最小版、RedeemGenerateSpec 只做请求体与基本校验、PendingRedeemBatch、redeemCodes(page:query:)）、BalanceReconciliation（D25：action_id / request_id 查询 + 邮箱时间窗退路，只做本地精确复核；executed / stillRunning / notExecuted / notFound）、PendingMoneyRules（分类文案、批次与补偿判定、confirmsExecution、R03 门控、重试权限、按类型分派的 reconcile）。余额页（D17）：新记录填 actorUserID；其他管理员发起的待核对隐藏“确认并重试原请求”，旧记录加“无法确认发起人”。与规格不同的取舍：退路时间窗按服务器时间（加 ServerClock 偏差）；没有邮箱的记录不发退路查询；批次多出 countMismatch / unverifiable，补偿以 used_by 判定、多出 createdNotRedeemed / redeemedByOther / unverifiable；set>0 的旧记录两个方向都拦；reconcile 用 async throws；任一类文件读不出时 hasPendingRecords 对所有站点为真（不复用站点 id）。未做：候选匹配、ambiguous、X-Request-ID 回显与 requestIDUnreliable、旧记录 keyword=用户 ID（阶段 3）；回前台自动核对（阶段 3 / 6）；三类待核对界面与 UI 夹具（S0-15、阶段 1 / 3 / 6）。单元测试 419 + 56 通过（原 394 + 46）。UI 测试已运行：gate 35 / 38，两次都失败的 testCapacityAndNewFields…、testSlowTodayStatsAllowsIndependentRuntimeRefresh 在基线名单内，testDashboardSlowTrendDoesNotDelayCountersOrMonitoring 单独重跑 Sub2MobileUITests 时通过（gate 时 Mac 负载高；同一次重跑里基线的 testDashboardTrendSupportsMetrics… 失败）；重跑后才通过的 testAccountRuntimeUsesOccupancy…、testUserFieldSelectionAndOrderRemainAfterReopening。 审查修正：读不出的待核对文件以前只在 .resume 时重读，冷启动或锁屏预热后的第一次 .active 不算 resume，所以不会重读。现在每次进入 .active 都重读，restore() 开头也重读一次（在登录页判断是否复用站点 id 之前）；启动提示从 init 移到 restore 的重读之后，读出后收起或缩短（unreadableNotice）。余额页新记录在“确认发送”时用 confirmed(at:) 重新取 createdAt（30 §3.4 第 2 步、R05），编号、请求体和 action id 都不变；已保存的记录重试时不改 createdAt。没有采纳的两项记入 BACKLOG：门控按服务器地址跨站点 id 拦截；重试后从最近一次发送起算宽限。单元测试 445 + 65 通过。 |
| S0-13 | 全局合规确认与二次验证（step-up）sheet | ✅ | `938af4f` `2eb1b53` | 按 D28 拆两次提交。13a（Sub2Core）：SecurityInterruption 按（状态, reason）精确分类（任何 423 都是合规），SecurityPromptOutcome / SecurityInterceptor；APIError 加 securityOutcome 与 withSecurityOutcome（kind、状态、reason 不变，只有 passed 时文案改为“…已通过，请重新确认后发送”）；APIClient.init 末尾加 securityInterceptor（D02），钩子按 D01 放在 failure 与 surfaced 之间（requestWithHeaders、带 key 执行器的 rejected、账号测试 SSE 打开失败），每次调用最多问一次、等待后核对代号；只有 RequestClass.isRead 且 passed 时经 sendAttempt 重发 1 次（用等待期间轮换后的新令牌），写请求永不自动重发，写等待中会话结束记为 cancelled；StepUpPolicy（开关 → 机器凭据 → TOTP → 授权，开关未知不主动验证）、grantExpiry、StepUpGrant（stepUp 返回 expires_in）、StepUpFailure、OneTimeCode；合规复用 S0-03 的 AdminComplianceStatus（D15），在 AdminCompliance.swift 加 acceptCompliance、phraseMatches（去首尾空白后逐字节，不做 Unicode 归一化）、documentURL(site:)、acceptFailureMessage。13b：SecurityPromptCenter（单一 active、同类合并、异类排队、等待者恰好唤醒一次、reset、complianceRevision、本地授权按代号）；AppModel+Security.swift（列入 exclude）；正式 client 经 ClientWiring.makeClient 注入（D13），publish 与 endActiveSession 先 reset，connect 后 Task 触发 presentComplianceIfRequired；StepUpSheet 按设计稿 UeStepUpSheet；ComplianceSheet；7 处页面迁移并删除 StepUpView / needsStepUp（passed → 重新打开原确认框，prepared / pending 不变；BalanceView 先 resolve 记录，passed 后同一条记录重新确认）；概览三区块、账号与用户列表在 complianceRevision 变化时重载。与规格不同的取舍：① 全局 sheet 用 windowLevel = normal + 1 的覆盖层 UIWindow 呈现（页面 sheet 已弹出时根视图弹不出第二个），窗口建在任一已连接 scene 上，后台发起的 prompt 回前台即可见，因此没有在 sceneDidChange 里另做分发（D18）；② 用户点“稍后”后同一会话的后台读请求不再自动弹合规（写仍弹）；合规 10 秒内刚通过、step-up 本地授权 5 秒内的迟到拒绝直接放行，超过 5 秒再收到 STEP_UP_REQUIRED 作废本地授权重新弹；③ 合规页无设计稿，标题“合规确认”、说明“站点要求管理员先阅读并确认《Sub2API 部署与运营合规承诺》（版本 {version}），确认前其他管理功能暂不可用。”、按钮“阅读合规文件 / 确认 / 稍后”均为自拟，请用户看 Mac 上 ui.xcresult 的 compliance-sheet、step-up-sheet-error、step-up-no-totp-notice 截图；两个地址都不是合法 https 时隐藏“阅读合规文件”，改写“请在 Web 后台查看合规文件”；④ 被保护接口的 503 STEP_UP_UNAVAILABLE、STEP_UP_ADMIN_API_KEY_FORBIDDEN 不弹 sheet，显示目录文案；step-up 接口的任何 5xx（后端写授权失败时是无 reason 的 500）在 sheet 内显示“二次验证服务暂时不可用，请稍后重试”并保留；TOTP_NOT_SETUP 按未开 TOTP 切到说明；收到 ADMIN_COMPLIANCE_INVALID_PHRASE 显示“确认语句不一致，请逐字输入”并保留输入；⑤ TOTP_TOO_MANY_ATTEMPTS 不立即关闭 sheet，而是锁住输入、保留“尝试次数过多，请稍后再试”，只剩“关闭”（直接关掉会丢文案）；⑥ 机器凭据：主动判断（ensureStepUp）用 2.6.2 文案，服务端拒绝用 ReasonCatalog（3.2）文案，30 §0.4 的写法不用；⑦ reveal 是 POST，钩子以 RequestClass.isRead 为准，阶段 3 实现时要显式声明读类或先 ensureStepUp；⑧ 合规确认成功后 reloadSiteSession 失败不影响确认结果；⑨ 用户编辑原先对 STEP_UP_ADMIN_API_KEY_FORBIDDEN / STEP_UP_TOTP_NOT_ENABLED 的特判并入统一处理（表单保留，可再编辑）。未做（见 BACKLOG）：通过后的回执（S0-14）、读区块“完成合规确认”入口（阶段 1，已有 presentCompliance）、只读令牌写按钮置灰（阶段 3 / 5 / 6）、各页主动 ensureStepUp 接入（阶段 3 / 6）。单元测试 13a 后 444 + 58、13b 后 444 + 65 通过；先确认新测试失败：去掉钩子时拦截器测试失败，关掉短路规则时会话层测试失败（等待型用例设 1 分钟上限）。UI 测试已运行：13a gate 36 / 38，两次都失败的 testDashboardTrendSupportsMetrics…、testCapacityAndNewFields… 在基线名单内（13a 不改界面），重跑后才通过的 testAccountRuntimeUsesOccupancy…、testMissingRuntimeRPMStaysUnavailable…、testTodayStatsFailureDoesNotBlock…；13b gate 39 / 41，两次都失败的 testCapacityAndNewFields…、testSlowTodayStatsAllowsIndependentRuntimeRefresh 在基线名单内；新增 SecurityPromptUITests 3 个在 gate 与单独运行中都通过。 审查修正：重试一笔可能已执行的写（余额页的待核对记录、用户编辑锁定后的“核对并重试原请求”）时，合规 423、二次验证、只读令牌、401 / 403 / 429 这类执行前拒绝不能证明上一次没执行：余额页不再删除记录，passed 时用原记录重新确认（不改 createdAt），cancelled / blocked 时保留记录并显示“结果未确认”；用户编辑保持锁定，passed 只重新打开同编号确认框。首次发送的用户编辑把 423 与 503 STEP_UP_UNAVAILABLE 归入明确拒绝（解锁表单）。判定统一为 Sub2Core 的 APIError.isRefusedBeforeHandler，与执行器同一次调用内的规则共用；执行器同时把同一次调用中可能已执行之后的 503 STEP_UP_UNAVAILABLE 也记为未确认（之前会被当作拒绝）。合规 sheet 读取被挂起取消后不再停在转圈，回前台重读。页面层的分支没有自动化测试（-ui-testing 不执行余额写，已并入 BACKLOG“余额页 UI 测试”一行）。 |
| S0-14 | 应用骨架：MainTab、AppRouter、路由、站点菜单、回执、状态轨、搜索 Tab | ✅ | `70e1e4a` `11fd203` | 按 D28 拆两次提交。14a：五个 Tab（概览 · 账号 · 用户 · 监控 + `Tab(role: .search)`，`.tabViewSearchActivation(.automatic)`，tint 由 .indigo 改为 Palette.accent），AppRoute 一次定义 32 个路由与 12 个 AppSheet（整行数据用 RoutePreload 按实例比较，id 一律 Int，60 §0.1 的 Int64 不用），AppRouter 的 paths 用 `[MainTab: [AppRoute]]` 而不是 10 §0.7-4 的 NavigationPath（放 NativeApp/Session 可单测）；日志（新增 scope）、统计、分组、分组详情（GroupDestination）、账号详情（LogAccountDestination 迁为 AccountDestination）、用户详情、设置映射到现有页面，其余 25 个路由与 11 个 sheet 为“即将推出”占位，addSite 显示现有登录页；搜索目录按 60 §1（四组、序号顺延、按 admin/me 收起，文本非空显示“搜索即将推出”，告警事件切到监控“告警”分段 U41，Web 两项交给 Safari）；监控 Tab 先放分段 + 占位；删除 ManagementView 与“管理”“设置”Tab，UI 测试入口改走搜索目录（UITestNavigation 的 openSearchTab / openSearchItem / openSitesSettings，后者等 settings.add，D27）；NumberedSectionHeader 随目录放进 14a（D28 原列 14b）。14b：ReceiptCenter 放 NativeApp/Session、由 AppModel 持有（10 §0.7-6 建议 Views 里的会话级，改为 App 级，切站后 MainTabs 重建回执仍在），4.2 秒、新替旧、旧计时撤不掉新回执、朗读一次，会话在本机结束时清空；切站回执“已切换到 {站点名}”在 AppModel.switchTo 成功后显示（站点菜单与设置页共用）；站点菜单（Toggle 打勾、主机名小字、添加站点…、站点与凭据推入当前 Tab）；Sub2Core 的 RailPosition 与 View.statusCapsule(tone:position:)，S0-09 的 StatusBanner 改用。与规格不同：iOS 27 模拟器上大标题与 `.inlineLarge` 都打不开 `.toolbarTitleMenu`，概览与账号 Tab 的标题改为 inline（系统下拉箭头），待实机确认；系统菜单项不带标识，UI 测试按文字找；现有页面不支持的路由参数（logs 的 user / model、analytics 的 range 等、settings 的 focus）暂不生效，select 撤不掉视图式推入的页面（均记入 BACKLOG）。单元测试 452 + 94 通过（两次都先确认新测试编译失败）。UI 测试：14a gate 41 / 45，两次都失败的 4 个都在 AccountListCustomizationUITests（testAccountRuntimeUsesOccupancy…、testCapacityAndNewFields…、testMissingRuntimeRPM…、testSlowTodayStats…），失败点都是 XCTNSPredicateExpectation 在标签已满足时仍超时；在未改动的 `b7e8d40` 上单独对照运行，testAccountRuntimeUsesOccupancy… 与 testCapacityAndNewFields… 同样两次都失败，另两个单独运行通过，判定为既有不稳定，交 S0-19；新增 AppNavigationUITests 在 14a 4 个全过。14b：gate 的工具链、单元测试、编译通过、无新增 warning，UI 全量跑到中途 Mac 断开（ssh 连接被重置，之后约 90 分钟 ping 不通），没有结果；14b 新增与改动的 3 个用例（两个标题菜单用例、testAddAndSwitchStations 的回执断言）此前单独运行通过，全量需 Mac 恢复后补跑 |
| S0-15 | 设置页、AppPreferences 与 Face ID（BiometricGate） | ✅ | `8b36009` `a58e6a9` | 按 D28 拆两次提交。15a：AppPreferences（四个键，不分站点，ui.mode 一律 main（U42），门槛只收 1–100000 的整数，非法值回退）、BiometricGate（LAPolicy.deviceOwnerAuthentication，System / Fixed 两种认证器，GatedAction 按 60 §3.4 覆盖清单，开关开、关都验证（U48），失败静默保持原值），NSFaceIDUsageDescription 加在 generate_project.py，RootView 外观、全局安全 sheet 的覆盖层窗口按外观设置取样式；现有四个确认点先接门控（账号批量、删除分组、余额调整按 D26 的实际变动额、新建用户初始余额，PendingUserCreateOperation 加 initialBalance）。15b：设置页按 60 §3.3 重写（Settings/ 下 5 个文件 + SettingsPresentation、SiteSettings 的 sessionBindingNativeMode），“站点与凭据”滚到站点分区、序号顺延，删除非当前站点给“已删除站点”回执（D19，删当前站点仍用 alert），待核对三类覆盖全部站点。与规格不同：提高金额门槛也先验证（用户 2026-10-22 决定，D36，60 §3.4 / U48 只要求开关验证）；设备不能再验证时存的开关保留但按未开启处理（开关置灰，删除改输入名称），避免卡死；会话绑定提示只对 jwt；当前站点补“站点版本”（00 §1.9）、Admin Key 说明行、时区说明行（00 §6.3）；站点行加登录方式徽章但不显示邮箱（me 快照只有当前站点）；门槛 sheet 用 numberPad（D22，S0-18 换 KeypadInput）；兑换码批次行按 D16 的共用说明行写“20 个 · 5 分钟前 · 未确认是否生成”，合计放右侧，不写“× $10.00”；“站点与凭据”把第一个站点行滚到居中（List 只认 .top / .center，.top 会把分区标题藏到导航栏下）；登录设备、管理访问令牌、推送通知、兑换码核对与补偿核对的目标页仍是阶段 6 占位；退出行文字按规格改为“退出并清除凭据”，与确认按钮同名，Sub2MobileUITests 用谓词区分。单元测试 467 + 115 通过（两次都先确认新测试编译失败）。UI 测试：15a gate 48 / 48、15b gate 59 / 59，均无重跑。mac-test.sh 第 14 行的默认仓库路径被写成了一个不存在的路径，本条运行时用 APP_REPO 指定主工作区 审查修正：余额页“设置为”的 Face ID 门控原先用 sheet 打开时的余额快照计算变动额，同一 sheet 里前一笔写入成功后不更新，后续“设置为”会少算（例如 $10 先增加 $500 再设置为 0，按 $10 判断而不验证）。现在 BalanceView 记下 currentBalance：初值为打开时的余额，每笔成功后取 GatedAction.balanceAfter(outcome)（重放 / 找回的结果可能过时，按未知处理，开关生效时一律验证），父页面重读用户时同步更新；单测覆盖 balanceAfter，页面层仍无 UI 测试（见 BACKLOG“余额页 UI 测试”）。 |
| S0-16 | 登录页：三种登录方式、验证码桥页、两步验证与错误表 | ✅ | `8d8e4bb` `b096977` | 按 D28 拆两次提交。16a：Sub2Core 的 LoginFlow（LoginMethod、CaptchaRequirement、CaptchaBridge、CaptchaRequest 移入 Sub2Core、CaptchaOutcome、CaptchaLoadFailure、LoginAgreement、LoginSite、LoginCooldown、LoginCopy）与 LoginFailure（只决定动作，文案取 ReasonCatalog 的 .login / .twoFactor，D32），ServerProfile.normalizedURL 从 AppModel.validatedURL 平移，LoginController（NativeSessionSupport 编译，23 个单测）。16b：LoginView 重写为薄视图，新增两步验证底部 sheet、登录协议勾选行 / 弹窗 / 正文 sheet，CaptchaView 改造，DemoLoginGateway 夹具，LoginUITests 14 个用例。与规格不同的取舍：① 规格没给“不是 Sub2 站点”的文案，定为“该地址不是 Sub2 站点，请检查站点地址”，三种方式都先拉 settings/public（00 §1.1 第 ① 步）；Key 方式只有非 JSON 404 或没有 version 才停，暂时性失败跳过 site_name 回退继续 connect（D32），密码方式拉不到就停止。② 验证码冲突统一用 00 §1.4 表的文案（不用 §1.5 的“站点验证码配置冲突”）；未知提供方停止并提示“站点的验证方式暂不支持，请改用 Web 登录或管理访问令牌”（桥页校验器只认三种）。③ 桥页“未部署”实际检测不到（SPA 回退返回 200），加载失败按 CaptchaLoadFailure 分类：-999 与 WebKit 102 忽略、网络类“无法连接站点”、其余临时失败与主框架 HTTP ≥ 400“站点未部署手机验证页，请改用 Web 或关闭验证码”；超时文案“安全验证已超时，请重新开始”。④ mobile_verify_path 是服务端值，经净化（以单个 / 开头、只含字母数字 /_.-、无 // 与 ..）后才用，不合法时用 /mobile/verify 并显示提示条；URL 只带 nonce。CaptchaRequest 移入 Sub2Core（改动总表写在 CaptchaView.swift），为了让 LoginController 能在 macOS 单测。⑤ 登录协议文案照抄 Web 的 zh i18n（“我已阅读并同意《…》”“登录条款”“拒绝 / 同意并继续”“请先阅读并同意最新条款后再登录”），modal 按规格在点登录后弹出，同意只在本页有效、不按 revision 持久化（BACKLOG）；协议只用于账号和密码方式。⑥ 两步验证 sheet 文案自拟：标题“两步验证”、正文“{掩码邮箱} · 输入身份验证器里的 6 位验证码”、脚注“填满 6 位自动提交”；TOTP_TOO_MANY_ATTEMPTS 关闭 sheet 并在表单显示文案，不进入冷却；2FA 阶段的 RATE_LIMITED 进入冷却。冷却按钮“N 秒后重试”。⑦ 403 FORBIDDEN（令牌主人已不是管理员）显示“当前版本仅支持管理员账号”；401 USER_INACTIVE 在登录页显示“该账号已被禁用”，INVALID_ADMIN_KEY 用 00 §1.6 的长文案（会话中途失效仍按 3.2，S0-11）。⑧ 选了“管理访问令牌”却粘贴非 sat_ 值时，凭据按前缀当 Admin Key，提交时把显示的方式同步修正（与服务端一致）。⑨ CAPTCHA_PROVIDER_MISMATCH 重新拉公开设置、以最新设置为准；验证失败与 MISMATCH 每次提交最多自动重开一次桥页；网络错误与 5xx 不自动重试，证明一律只用一次。⑩ CaptchaView 的导航决策改用 async 版委托方法，消除 Xcode 27.1 的 decidePolicyFor 签名不匹配警告（BACKLOG 原有条目已处理，见该行）；新增 decidePolicyFor navigationResponse。⑪ 回执没有按钮时不拦截点击（ReceiptOverlay 加 allowsHitTesting），登录后的回执不再挡住标签栏。⑫ 标题：根视图“Sub2 Mobile”，sheet 为“添加站点”，有 prompt 时为“重新登录”。未做：refresh_token_unavailable 横幅（R18，阶段 1 概览）；README 登录方式描述与 AppModel.validatedURL 包装的清理（S0-19）。UI 测试已运行：16a gate 59/59 通过；16b gate 73/73 通过（含新增 LoginUITests 14 个），无 flaky。审查修正：两步验证收到 429 RATE_LIMITED 后，sheet 的输入框在冷却期间禁用并每秒显示“N 秒后重试”，冷却期间输入的验证码直接丢弃且不清除提示，冷却结束后输入框重新可用并获得焦点；新增单元测试与 LoginUITests 用例。 |
| S0-17 | 跨章纯函数：账号显示状态 AccountDisplayState 与状态汇总模型 | ✅ | `5626ec3` | 新增 AccountDisplayState.swift（AccountStateInput 两个入口：账号 DTO 与 status-summary 项；严格按后端 D02 顺序 1–8、Go 的比较方式；状态与色调复用 S0-09 的 AccountScheduleState / Tone；倒计时目标、已停止调度、到期暂停“已过期”、原因短句、凭据类错误、模型限流；now 由调用方传 ServerClock.now()，无默认值）与 AccountStatusSummary.swift（计数、平台、分组与 shortage、账号项、汇总，全部宽松解码、坏行只丢该行；同一模型也解码 dashboard/home 的 availability；R19 唯一的 accountStatusSummary(platform:groupID:includeAccounts:)，groupID 非正数本地拒绝，不发 default_min_ratio，不进 ConditionalCache）。UpstreamAccount 按可缺失补 C02 / C10 / C15 与 D02 输入字段（时间存原始字符串）；AccountExtra 宽松解码 model_rate_limits；新增 AccountTokenStatus（只解码，显示归阶段 2）。与规格不同的取舍：① 任务范围写的 accounts_truncated 在 status-summary 里不存在（只在 availability 里），而漏写的 platforms[] 存在，两者都解码、缺失为默认值；② status-summary 项没有 auto_pause_on_expired，缺失时第 7 行只在第 1–6 行都不成立且服务端 state == paused 时成立；③ TempUnschedState 的 status_code 为 0 视为没有状态码，主体写“临时不可调度”，规则后缀照加；④ 凭据类错误正则大小写不敏感，只在 error_kind 与 error_status_code 都没有时使用；⑤ 00 §5 的“error_message 首行截断 80 字”按 R12 作废，任何情况都不显示 error_message，汇总项也不解码它；⑥ AccountFieldPresentation.value 的 now 改为必填（签名变化）。可见变化：账号列表“状态”字段与详情“状态”行改为 00 §8.1 状态词（“已禁用”→“停用”、“异常”→“错误”、disabled 与未知值→“停用”、active 但暂停调度→“暂停”、限时窗口内“过载中 / 限流中 / 临时不可调度”、到期自动暂停“暂停 · 已过期”；详情原来显示原始枚举）。gate 全过：单元测试 509 + 138；UI 测试 73 个全部通过，其中 Sub2MobileUITests.testPerformanceTrendFourthTabShowsRealRatesAndNewestDetails 重跑一次后通过（概览性能趋势页，与本条无关）。 |
| S0-18 | 跨章纯函数：Key 状态、金额键盘输入、告警文案 | ✅ | `315216a` | 新增 UserKeys.swift（AdminAPIKeyStatus：effective_status 为四个已知值时直接用，缺失 / 空串 / 不认识的值按后端 EffectiveStatusAt 顺序本地推导；状态词、徽章含简易模式“· 仍可调用”并计入活跃、色调用 S0-09 的 Tone 且不随模式变化、分区头“3 个 · 活跃 2”）、KeypadInput.swift（KeypadKey 与 pad；apply(_:to:maxDigits:maxFractionDigits:maximum:) 照设计稿 press() / vmoKeypadNext，maximum 为可选参数；value(of:) 直接解析 Decimal；retype 供系统文本框逐字符按键）、OpsAlerts.swift（AlertEvent / AlertEventRule / AlertSilenceRef，只有 id 必填，silenceSupported 记录 silence 键，时间用 S0-07 的 optionalTimestamp，replacingRule）与 AlertPresentation.swift（18 行指标目录、数值、阈值、运算符、标题、范围、规则 / 条件、不受支持、状态词与徽章、首页说明行、since、静默行、色调调 Tone.alert；全部走 DisplayFormat，没有新增格式函数）。D22：Face ID 金额门槛 sheet 的逐键过滤改用 KeypadInput.retype（6 位、0 位小数、上限 100000），parseThreshold 只在保存时校验；可见变化：输入“100001”原来显示 100001 且不能保存，现在第 6 位被拒绝、停在“10000”，SettingsUITests 同步断言显示值。与规格不同的取舍：① 告警百分数按 D21 为 1 位小数（10 §6.3 示例写作 5%）；② since 用 relativeTime 加动词，没有“1 小时前”一档（“今天 08:29 恢复”）；③ 手动解决没有解决人时“昨天 22:10 · 已手动解决”；④ 缺 group_name 时范围写“分组 · #12”；⑤ 不认识的 effective_status 视为缺失；⑥ 50 §6.3“简易模式徽章隐藏”按 R13 以 30 §7.3 为准；⑦ 键盘允许“0.5”、禁止“05”；⑧ 规则缺失时规则文案是后端英文 description 原文。未做：Key DTO 扩充、Key 卡片与 BalanceKeypadSheet（阶段 3），告警 APIClient 方法与页面（阶段 1），兑换码面额键盘（阶段 6）。gate 全过：单元测试 549 + 139；UI 测试 74 个全部通过、没有重跑。 |
| S0-19 | 阶段 0 完成度核查与补测 | ✅ | `45f95a5` | 缺口补齐：错误“详情”（复用 S0-02 的 diagnostics，加 UTC“时间”行；ErrorDetails 只认 APIError，report 保存、文字被换掉时丢弃；alert 多“详情”按钮，打开“错误详情”sheet，复制只放本机剪贴板；ErrorDetailsDisclosure 留给阶段 1–6 的区块错误态）；RequestLog 挂在 transmit / openStream，每次尝试一行（方法、路径模板、状态、错误体里的 reason、X-Request-ID，按服务端 64 字节规则清洗，取消的尝试不记）；CapabilityGateTests 从旧服务端空能力集合串到 Idempotency-Key 与 since_id（D24 的页面接线 S0-10 已做，只核对）；-ui-switch-rejected 夹具与 AppShellUITests（令牌读写 / 只读、Admin Key 第一个管理员说明、切站失败详情与“当前站点不变”）。清理：AppModel.validatedURL 包装（S0-16 留下）、trendAxisLabel 的手机时区默认值（性能趋势改按服务器时区）、UI 测试里的调试 print；其余清单项 grep 为 0（见下方小结）。README 与 NATIVE_CONTRACT / API_COMPATIBILITY / ADMIN_MODULES 只改被阶段 0 推翻的句子。与规格不同：时间行用 UTC Z（D29 二选一）；日志的 reason 只取错误响应体。UI 测试基线 7 个用例诊断为测试时序问题（见小结），修测试后连同全部用例在 gate 里 76 / 76 通过、没有重跑。gate：单元测试 557 + 143，编译无新增 warning，UI 76 / 76 |
| S0-LOW-A | 阶段 0 低优先级意见复核（一）：S0-02 至 S0-12 的 27 条 | ✅ | `f7b1af9` | 修 20 条（含重复意见）：批量刷新凭据按 SessionInvalidation + 安全拒绝停止（含 SESSION_BINDING_MISMATCH）；settings/public 的协议文档逐条容错；恢复 / 切站失败文案用 APIError.forConnection（刷新暂时失败写“请稍后重试”，admin/me 403 FORBIDDEN 写“当前版本仅支持管理员账号”；登录页 S0-16 起已按 .login 显示，所以不给 me() 加 context 参数）；条件缓存两个挂起点后补代号检查；带 key 写业务错误补 actionID；settingsNote 注释；性能趋势 Y 轴 axisLabel（1000 以下最多 2 位）与日志 / 账号总数千分位；统计页换筛选用 reset() 保留 429 等待；删除确认框按已存凭据类型提示吊销；待核对目录排除备份、写入选项可测、重试权限站点限定移入 Sub2Core；补登录负向、装配回调、核对错误分类等单测，回前台重载与余额页 D17 重试权限补 UI 测试（-ui-count-user-loads、-ui-pending-other-actor / -ui-pending-actor-unknown）。AppModel.reconcile 的自动 resolve 与代号检查不在 SwiftPM 编译范围，仍无自动化测试。不改 7 条：5 条已被 2cfa217 / 6d4a64d / e04377b（两条）/ 9d5e5f0 修正，用户编辑页 423 已由 2eb1b53 / 9758e41 处理，服务器时区退路不随手机时区变化记入 BACKLOG（阶段 4）。与规格不同的取舍：“暂时无法续期登录，请稍后重试”为自拟文案（00 §1.7.2 只给了页面用的“正在重试”）。gate：单元 565 + 146、编译无新增警告、UI 77 / 77 无重跑 |
| S0-LOW-B | 阶段 0 低优先级意见复核（二）：S0-13 至 S0-19 的 28 条 | ✅ | `dfdc691` | 修 26 条（含重复意见）：全局 sheet 的覆盖层一次只做一个转场（SecurityPromptOverlay），呈现中结束会话或收起途中来新 prompt 不再留下吞触摸的透明窗口；回执按钮按回执 id 执行（performAction(id:)），发布新会话时清空旧回执，AppModel.switchTo 对当前站点直接返回；删除站点的结果按 SiteRemovalNotice（收尾结束时没有活动站点就用 alert，备注不再丢失），收尾期间设置页显示“正在删除…”行（-ui-slow-teardown）；会话绑定方式只由 admin 角色读取（vendor 不再请求 admin/settings）；当前站点的余额待核对行恢复“打开原站点核对”；登录 Retry-After 截到 300 秒、冷却按站点地址记录、离开页面后迟到的失败按取消处理、两步验证校验中不可取消、密码方式 settings/public 的 JSON 404 判为非 Sub2 站点；accountStatusSummary 注释改为必须按 capability 门控并补旧站点 400 用例；门槛 sheet 改用 KeypadInput.edit（中间插入 / 删除只接受键盘能打出的结果）；RequestLog 可注入 Sink 并补“每次尝试一行、取消不记”的行为测试，账号测试流的拒绝在读完错误体后记日志（带 reason）；补 page_size 超限的 Debug 退出测试；README 的重试与时区描述改准确；阶段 0 小结与 BACKLOG 更正 testSlowTodayStats… 不在 S0-19 修法范围内。不改 2 条：用户编辑页重试遇到安全拒绝已由 `9758e41` 修正，余额页“设置为”按过期余额判断门槛已由 `c8a0f1f` 修正。与规格不同：“正在删除…”为自拟文案；登录冷却 300 秒上限与区块一致（00 §2.7.2 未写上限）。gate：单元 571 + 156、编译无新增警告、UI 77 / 77 无重跑 |
| U-01 | 状态胶囊两端内缩改为 22pt，矮行保底 16pt（用户真机反馈） | ✅ | `6014be1` `5f1e9a3` | 两次改动：6014be1 把 StatusCapsuleMetrics.verticalInset 由 10 改为 22，行、卡片、横幅统一（用户看 10/14/18/22 对比图后选定）；5f1e9a3 加矮行保底，Sub2Core 新增 RailPosition.insets(height:)（endInset 22、minimumLength 16；两端封口每端 min(22,(h−16)/2)，单端 min(22,h−16)，中间 0，h&lt;16 占满）及 5 个单测，statusCapsule 与公告预览卡片的中性胶囊改用 StatusCapsuleShape 按实际行高算内缩（没用 GeometryReader，不撑大行），删去 verticalInset。对比截图在 sub2-testenv/scratch/capsule-compare/：选长度用的 index.html 与 *-10/14/18/22.png；保底验证用的 min16-users.png、min16-group-batch.png（含 -row 局部），用户列表 Alice 单行 56pt 胶囊 16pt（原 12pt），分组批量结果失败行 61.7pt 胶囊 17.7pt（失败行总带原因文案，未触发保底）。规格同步：00 §8.1 与 FINAL-SPEC“状态胶囊”条改为 22 并补“行高不足时两端少缩，保证胶囊至少 16pt（2026-11-03 用户定）”；20-accounts.md 第 199 行与 FINAL-SPEC.md 第 2233 行的“离上下 10”改为“离上下见 00 §8.1”；html-preview 设计稿未改。check：TOOLCHAIN、UNIT、BUILD 均为 0，无新 warning；UI 8 个类 215/215，无 flaky。 |
| U-02 | 全 App 费率倍数统一：三位小数四舍五入、去尾 0、至少一位、× 在前；分组保存确认两侧三位相同而实际不同时写完整精度 | ✅ | `5c97a43` | 新增 DisplayFormat+Multiplier.swift（multiplier / multiplierNumber / multiplierChange）；三个旧包装改为转调，调用点不动；账号列表字段“1.5×”改为“×1.5”，删掉私有 decimal(_:)；占位与骨架改为 ×1.0。方案测试表里 (0.1254, 0.1256) 一例与用户裁定不符，按裁定显示“×0.125 → ×0.126”，完整精度只在按三位显示相同时才用。分组新建确认照规则四舍五入、不设例外；编辑框回填与默认输入没改。check：单元 2760 + 1366 个、编译无 warning、10 个 UI 类 201 个用例全部通过 |

## 阶段 0 小结（S0-19）

### 完成项

| 条目 | 提交（功能 · 审查修正） |
|---|---|
| S0-01 工具链 Xcode 27.1、最低 iOS 26 | `777623b` |
| S0-02 错误信封、reason 总表、APIError | `145f9de` |
| S0-03 AdminMe、capability 常量、模型放宽 | `46acec7` |
| S0-04 请求层（请求头、设备 ID、续期重发、自动重试、429、超时） | `8bbffb6` |
| S0-05 ConditionalCache（ETag / 304） | `353e913` |
| S0-06 幂等写、WriteOutcome、PendingMoneyWrite、金额编码 | `270212b` · `025ecad` |
| S0-07 服务器时间、时间编码、since_id 增量 | `6aae86d` · `2cfa217` |
| S0-08 DisplayFormat | `776ecb9` |
| S0-09 Palette / Tone、BlockState / LoadState | `516f5a3` · `6d4a64d` |
| S0-10 deviceID、凭据迁移、登录请求体、me() 连接、SiteSession | `7690208` |
| S0-11 退出与删除站点、切站、前后台、会话失效 | `9b2091d` `68010bf` `e8f4c38` · `c3ea406` |
| S0-12 资金写待核对三类记录 | `9d5e5f0` · `b7e8d40` |
| S0-13 全局合规确认与二次验证 sheet | `938af4f` `2eb1b53` · `9758e41` |
| S0-14 应用骨架（Tab、路由、搜索目录、站点菜单、回执、状态轨） | `70e1e4a` `11fd203` |
| S0-15 设置页、AppPreferences、Face ID | `8b36009` `a58e6a9` · `c8a0f1f` |
| S0-16 登录页（三种方式、验证码桥页、两步验证） | `8d8e4bb` `b096977` · `d310677` |
| S0-17 AccountDisplayState 与状态汇总 | `5626ec3` |
| S0-18 Key 状态、KeypadInput、告警文案 | `315216a` |
| S0-19 阶段 0 收口 | `45f95a5` |

完成标志（FINAL-SPEC 实现顺序 · 阶段 0 第 5 条）：00 §9.8 的测试都已在单元测试里（下表）；三种方式登录、切站点、退出、四个 Tab 与搜索 Tab 可导航都有 UI 测试，在 S0-19 的 gate 里全部通过。

### 00 §9.8 测试对照

| 清单项 | 测试文件 · 用例 |
|---|---|
| ErrorEnvelope 六个样例 | ErrorEnvelopeTests：decodesHandlerEnvelopeWithIntegerCode、decodesMiddlewareEnvelopeWithStringCode、decodesComplianceLockedBody（423）、decodesLoginRateLimitWithTopLevelRetryAfter、nonJSONBodiesYieldNoEnvelope（纯文本 404 与 HTML 502）；APIErrorMappingTests：nonJSON404IsUnsupportedButJSON404IsNotFound、htmlBadGatewayIsTemporaryWithoutReason |
| ReasonCatalog 每一类、401 / 404 USER_NOT_FOUND、未知组合兜底 | ReasonCatalogTests：catalogRowsMatchSpec（3.2 全表，25 个类别都有行）、userNotFoundDependsOnStatus、unknownCombinationsFallBackByHTTPStatus、knownReasonUnderOtherStatusUsesFallback；404 OPS_DISABLED → featureDisabled 在 APIErrorMappingTests.legacyServerFactoryKeepsWorking |
| 刷新：写请求同 key 重发、429 / 503 / 网络错误保留会话、REFRESH_TOKEN_REUSED 清会话 | RequestLayerTests.expiredTokenResendsEveryMethodOnceWithIdenticalBytes；KeyedWriteExecutorTests.expiredTokenDuringKeyedWriteResendsSameKeyAndBytes；TokenRefreshTests.transientRefreshFailureKeepsSessionAndBacksOff、refreshRejectionEndsSessionWithoutFurtherNetwork |
| 幂等写：字节一致、IN_PROGRESS 30 秒转待核对、KEY_CONFLICT 换 key、Recovered 按成功、落盘失败不发、旧记录解码、set 0 标题 | KeyedWriteExecutorTests：keyedWriteRetriesTransportFailuresWithSameKeyAndBytes、inProgressHonoursRetryAfterAndStopsAfterThirtySeconds、keyProblemsRequireReconfirmationWithoutRetry、recoveredReplayedAndDegradedResponsesCountAsSuccess；IdempotentWriteTests：persistFailureNeverProducesSendableWrite、legacyPendingBalanceRecordDecodesWithoutNewFields、pendingLineTitlesFollowOperationAndR02；PendingMoneyLedgerTests.unwritableDirectoryRejectsRememberAndKeepsLedger |
| DisplayFormat 6.2 每一行 | DisplayFormatTests 23 个用例（含 rpmKeepsOneDecimalOnlyBelowTen、ratioPercentMultipliesByHundredWithOneDecimal、三种 duration、zeroIsNotMissing） |
| 金额编码 | IdempotentWriteTests：balanceBodyIsDecimalStringWithoutExponent、compensationBodyEncodesValueAsJSONNumber、createUserInitialBalanceIsJSONNumber；RedeemCodesTests.generateSpecEncodesSortedKeysAndJSONNumber（generate 与 create-and-redeem 的方法级请求测试在阶段 6 建方法时补） |
| IncrementalList 乱序、去重、has_more | IncrementalListTests：outOfOrderCommitDoesNotLoseRows、mergeDeduplicatesNewerWinsAndSortsByIDDescending、hasMoreAbandonsIncrementForFirstPageReload |
| 时间：无 +08:00、趋势桶按服务器时区、Unix 秒 | ServerTimeTests：timeQueryNeverContainsPlusOffset、dashboardTrendParsesBucketsInResponseOrRequestZone、unixSecondsAndLenientContainerDecoding |
| 能力：没有 capability 时不发新参数 | CapabilityGateTests（S0-19）：legacyServerReportsNoCapabilityAndSendsNoNewParameters、userWritesCarryIdempotencyKeyOnlyWithTheCapability、incrementalReadsSendSinceIDOnlyWithTheCapability；另有 KeyedWriteExecutorTests.userWritesSendKeyOnlyWhenOperationAllows、IncrementalListTests.missingCapabilityUsesTimeWindowFallback |

完成标志的 UI 测试：三种方式登录 → LoginUITests.testPasswordLoginShowsConnectedReceipt、testLoginMethodNotesAndSatPasteSwitchesToAccessToken、testAdminKeyLogin；认证方式文案 → SettingsUITests.testCurrentSiteShowsIdentitySignInAndEntries（密码）与 AppShellUITests（令牌读写 / 只读、Admin Key）；切站点 → AppNavigationUITests.testSiteMenuSwitchesStationWithReceipt、Sub2MobileUITests.testAddAndSwitchStations；退出 → Sub2MobileUITests.testLogoutErasesCredentialInsteadOfRestoringSession；四个 Tab 与搜索 Tab → AppNavigationUITests.testFourTabsAndSearchTabReplaceManagementAndSettings、testSearchDirectoryOpensExistingPagesAndPlaceholders、testAlertEventsSelectsMonitorAlertsSegment；错误详情 → AppShellUITests.testSignInMethodsAreLabelledAndARefusedSwitchOffersDetails。

### 核查结果（00 §9.1–§9.7、改动总表阶段 0 行、R01–R20、D15 定型表）

- 清理清单 grep 为 0：verifyAdministrator、DashboardPresentation 的 compactNumber / cost / compactCost / money / duration / rpmValue、全局 money(_:)、StepUpView、needsStepUp、ManagementView、management.*、tab.settings / tab.management、DashboardLoadState、独立的“不可用”字面量（只剩“站点暂时不可用”“服务不可用”等句子）、has("…") 字面量、Sources 与 NativeApp 里的 print / NSLog（UI 测试里的调试 print 由本条删除；Tests 里三个历史回归用例的 print 是 docs/ACCEPTANCE.md 引用的受控输出，保留）、Sources 里的 +08:00（只剩 ServerTime 的注释）。
- APIError.Kind.twoFactor 按 D29 保留，只用于 TOTP_* 与本地 6 位校验；423 归 .compliance、STEP_UP_* 归 .stepUp（APIErrorMappingTests.lockedIsComplianceAndNeverStepUp）。
- dashboard/realtime 只在 me() 的最后一级退路（admin/compliance 也是非 JSON 404 时）。TimeZone.current 只剩 ServerTimeZone.device、UsageAnalytics 的 AnalyticsQuery 默认值与 RequestLogs 的 usage timezone（后两处见未做项）。
- D15 重名：RetryAfter、ReasonCatalog.Context、Tone、AdminAccessToken、AdminComplianceStatus / complianceStatus() / acceptCompliance、requestClock / serverClock、Credential.fromAPIKey、AuthPresentation、PendingMoneyWriteLine、postLogout、DisplayFormat.decimal、accountStatusSummary、userAdjustments、KeychainCredentialStore.remove / eraseCredential 都只有一个定义；StatusTone、AccessTokenItem、ComplianceStatus、ReasonContext、pastedKey、removeSite（方法）、redeemBatchRow、compensationRow、loginKindBadge、queryTimestamp、writeTimeout 均不存在。SiteSession.authMethodLabel 只是转发 AuthPresentation.methodLabel，不是另一套文案。
- D13 装配点：NativeApp 里 `APIClient(` 只在 ClientWiring.makeClient、AppModel.connect 的候选 client、LoginView 的登录网关、AppModel+Session 的收尾 client 四处；ClientWiringTests.activeClientInheritsCandidateCacheIdentityClockAndSiteZone 守住装配。D02 的 deviceID 必填与 internal 测试构造已在 S0-10 完成。
- D11：AppModel.swift 442 行；AppModel+Pending / +Security / +Session 都在 Package.swift 的 exclude 里。全部 Swift 文件都不超过 800 行（最大 APIClient.swift 716 行）。NSFaceIDUsageDescription 在 generate_project.py。
- D27 静态核查（scratch 脚本，按 UITests 里引用的 accessibilityIdentifier 在 NativeApp 字面量与插值模板里查）：218 个标识全部能找到；management.*、tab.settings 不再出现，tabBars.buttons["设置"] / ["管理"] 只在断言“不存在”的地方出现。
- 00 §9.1 新增方法：me、sessions、revokeSession、revokeOtherSessions、complianceStatus、acceptCompliance、accessTokens、revokeAccessToken、deletePushDevice 已有；registerPushDevice、updatePushSubscription、testPushDevice、pushConfig 与 PushCoordinator 按实现顺序归阶段 6。

### 未做项及原因

- **待核对门控跨站点 id（资金安全，阶段 3 必做、不能跳过）**：同一地址重新登录后，新站点 id 可能对同一用户重复发起充值 / 退款；修法需要“用当前身份核对旧站点 id 的记录”的界面，留到阶段 3 余额核对页（BACKLOG 同名行）。
- **余额重试后的执行宽限**：“用同一编号重试”不更新 createdAt，刚重试就核对会误判为未执行；阶段 3 实现核对框里的重试时给记录加“最近一次发送时间”（BACKLOG 同名行）。
- TimeZone.current 的两处退路：UsageAnalytics.swift 的 AnalyticsQuery 默认时区、RequestLogs.swift 的 usage timezone，阶段 4 重写统计与日志时改为服务器时区。现有页面里“更新于 HH:MM:SS”等按手机时区格式化的时间同样随页面重写改用 DisplayFormat（BACKLOG）。
- 推送接口与 PushCoordinator → 阶段 6；各页面区块错误态接入 ErrorDetailsDisclosure → 阶段 1–6；redeem-codes/generate 与 create-and-redeem 的方法级请求测试 → 阶段 6。
- 需要实机验证的：iOS 27 搜索 Tab 形态（U40）、大标题下的站点标题菜单、Face ID 真实弹窗、ETag 304 经 URLSession 原样返回（均已在 BACKLOG）。

### UI 测试运行情况

S0-19 的 gate（3 台模拟器并行、失败重跑一次）：76 个用例全部通过、没有重跑，包括新增的 AppShellUITests 2 个。此前单独运行 AccountListCustomizationUITests、UserManagementUITests、Sub2MobileUITests 三个类，30 / 30 也全部通过。

基线 7 个不稳定用例的诊断（失败信息取自 Mac 上 base-ui.xcresult 与 ui-base.xcresult）：
- 失败点只有两类：① 列表字段开关“The rendered field switch did not change value”与字段上移“Field did not move after tapping its visible center”；② 谓词等待超时，而失败信息里的标签已经包含期望值（如“在用 RPM：37”“扣费、$0.31”）。趋势缩放用例同样是第 210 行放大、第 233 行回滑的 5 秒等待超时。
- ① 是测试问题：reveal 的拖动结束时列表还在减速，紧接着的点按只让滚动停下，开关与排序按钮没有收到点击（ListFieldEditor 的 Toggle 与上下移按钮在 S0-14 之后没有改过）。② 是负载问题：setField 每次前后各取一次全量截图、界面树并 print(app.debugDescription)，一次字段编辑就有十几次完整无障碍快照，Mac 负载高时单次快照会停顿十几秒（S0-07 已证实），等待窗口被吃掉。
- 修法只改测试：UITestNavigation 新增 XCUIElement.waitUntilSettled()（两次读到相同 frame 才继续，最多 2 秒），用在账号 / 用户字段开关、字段上移与趋势缩放、滑动之前；删掉每次开关前后的截图、界面树与 print，只在等待失败时保存证据。没有加长任何超时。
- 不是 App 在 iOS 27 上的缺陷，没有改 App。账号列表与用户列表的字段编辑会在阶段 2 / 3 随页面重写（20 §1.7、30 §1.7 去掉“显示字段”），这些用例届时整体替换。
- 更正（S0-LOW-B 复核）：上面的修法只覆盖 7 个里的 6 个。AccountListCustomizationUITests.testSlowTodayStatsAllowsIndependentRuntimeRefresh 不调用 setField / moveFieldToFirst，用到的 login、openAccountDetail、assertDetail、reveal 在 S0-19 都没有改；它只有失败形态 ②（负载下快照停顿吃掉 assertDetail 的 10 秒与 runtime-updated 的 5 秒谓词等待），原因没有消除，之后几次 gate 通过只说明没有复现。阶段 2 账号页重写时整体替换；在此之前它再失败按既有不稳定处理，不算新回归（BACKLOG“UI 测试 6 并发下的快照停顿”一行同步改写）。

## UI 测试基线（改动前，`efcb8c1`）

Mac 补装 Xcode 27.1 的 CoreSimulator 组件后，在 iPhone 18 Pro（iOS 27）模拟器上运行旧代码的 35 个 UI 测试：

| 运行 | 方式 | 用时 | 结果 |
|---|---|---|---|
| 1 | 串行 | 57 分钟 | 29 通过、6 失败 |
| 2 | 4 台模拟器并行 | 25 分钟 | 33 通过、2 失败 |

两次失败的用例不同，说明这些旧测试在新模拟器上不稳定。两次合计失败过的 7 个：`AccountListCustomizationUITests` 的字段偏好隔离、容量字段隐藏与排序、今日统计慢、今日统计失败、分组并发与字段顺序，`Sub2MobileUITests` 的趋势图缩放与小时选择，`UserManagementUITests` 的用户字段选择与顺序。之后的检查改为 6 台并行、失败自动重跑一次；这 7 个由 S0-19 统一诊断（App 在 iOS 27 上的真实缺陷就修 App，测试时序问题就修测试，页面会在后续阶段重写的记明原因）。

## 阶段 1 · 概览与监控

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S1-00 | 并行开工准备：热点文件按区域分区（路由映射分文件、AppModel 分阶段锚点、Package.swift exclude 每项一行、无能力夹具参数、缺失值读屏常量） | ✅ | `97038af` | 只调整结构，页面行为、文案与标识不变。新增 11 个 Destinations 区域文件（11 个 Route、6 个 Sheet 分派视图，每个 case 一行加段注释）、ComingSoonSheet（sheet 占位共用）、UITestArguments.swift（S1D1-22，-ui-without-capabilities 的唯一解析入口，有单测）；AppModel 加会话级锚点 18 个、App 级锚点 12 个；DisplayFormat.missingSpoken / spoken(_:)。UI 测试拆分：AppNavigationUITests 由 2 个用例拆成 12 个，Sub2MobileUITests 由 1 个拆成 2 个，另新增 testWithheldCapabilitiesStillOpenEveryTab，按方案多带 admin.access_tokens 以便先红后绿。git merge-file 模拟 29 组相邻分区改动，全部无冲突。check 六类 UI 测试 55/55 通过，无重跑。 |
| S1-01 | 首页聚合模型与首页接口（DashboardHome、dashboardHome、dashboardRates、accountsRanking） | ✅ | `d8608c6` | 不建 HomeAvailability，直接用 S0-17 的 AccountStatusSummary；接口写在 DashboardHome.swift / AccountsRanking.swift 的 extension APIClient，不改 APIClient.swift；dashboard/rates 用普通读 20 秒；带 include 时未请求的段也解码为 error，调用方只读请求过的段；nocache=1 是独立的 ETag 缓存键；firing_count 缺失取 top.count；INVALID_TIMEZONE / INVALID_INCLUDE 各重发一次，被拒时区不做记忆；排行收到无 reason 的 400 时去掉 timezone 重发一次（S1D1-25）；RequestLog.logger 是 private，新建 DashboardLog；errorAccounts() 留给 S1-05；UI 测试未涉及（check 只跑工具链、单元与编译，全部通过） |
| S1-03 | 告警与渠道监控的模型和接口 | ✅ | `bac53e6` | 与规格不同：alertEvents 的 before 用 AlertEventCursor（保留服务端 fired_at 小数位、UTC Z、可比较，S1D1-04；按 Date 回传会漏掉同一轮评估的事件）；首字按 00 §6.2 毫秒读数（850ms / 1.4s，10 §5.3 写 1 位小数秒，R10）；说明行判定顺序自定（采集不可用 → 数据已过期 → 可用 / 性能下降 / 不可用 → 无样本 → 样本不足）；ReasonCatalog 补 403 CHANNEL_MONITOR_DISABLED；setAlertEventStatus 只收 manual_resolved / resolved；alertEvents / alertRules 逐条宽松解码；AlertEvent 增加 replacingGroupName(_:)，replacingRule 等复制函数保留游标。纯 Sub2Core，check 不带 UI 类，UI 测试未运行 |
| S1-04 | 首页纯函数 HomePresentation：6 格、待处理队列（含三类资金待核对，R02）、平静判定与副标题 | ✅ | `a5a7854` | 涨跌用 ▲ / ▼ 紧贴数字（不用 DisplayFormat.change 的 ↑），数字走 DisplayFormat，舍入为 0 写“0.0%”无箭头，昨日值不大于 0 不显示；告警行最多 5 条，其余计入“另有 N 条”，本地已手动解决的不计入；重试行放在各自槽位最前，有旧值时旧行照常显示，availability 段 disabled 按失败；accounts_truncated 只影响受限行标题与“等”；状态旗两种状态都带“· N 个账号可调度”；超过 60 分钟写“更新于 今天 HH:MM”；只新增 Sub2Core 与单元测试，没有视图和数据加载；ui_test_classes 为空，没跑 UI 测试（check：工具链、单元测试、编译通过） |
| S1-02 | 运维监控模型、接口与 MonitorPresentation | ✅ | `807a76f` | 与规格不同的取舍：opsOverview(timeRange:) 按 X08 包 opsOverview(_:supportsModelFilter:)，发 start_time / end_time（服务器时间截到整秒），不发 time_range；opsSnapshotV2 也走 OpsQuery.validate；日志采集延迟按 R10 写 850ms / 2.0s（规格示例“2 秒”）；CPU / 内存按 00 §6.2 保留 1 位小数（38.2%）；心跳本地判定 stale 优先于 failing（与后端 D08 一致）；unknown 任务右侧一律“—”，缺值不显示说明行；新增 OpsMonitoringWriteRoute（没有 /admin/me 的站点不走 PUT admin/settings）；接口拆到 OpsMonitoring+API.swift；ChannelMonitor.swift 的 lenientValue 改为模块内可见供复用；MonitorPresentation 的结果类型都嵌套在 MonitorPresentation 下。未做：页面（S1-13 / S1-14）、开关流程（S1-08）、删旧 dashboardMonitoring / OpsReply / OpsSnapshot（S1-09b）。UI 测试未运行（本条无界面改动，ui_test_classes 为空） |
| S1-05 | LiveOpsStore：会话级共享状态、首页主路径、告警列表与轮询编排 | ✅ | `61fb705` | 七段改为 HomeBlocks + 一个 homeRequest，不各配 LoadState（S1D1-03）；opsDisabled 以最新响应证据为准，没有响应前读 /admin/me，ops 段 error/timeout（带 reason）也算“已开启”（S1D1-02）；运维关闭时 firingAlerts / alertCounts / todaySLA 由计算属性返回空；徽标经闭包取 AppModel 当前实例（X16）；BlockState 不加 mapValue，复用 S2-03 的 updatingValue，items.json 补登的 BlockState.swift / BlockStateTests.swift 未改；夹具 id 表 LiveOpsFixtureIDs（S1D1-11），可用不足只列企业专线；未接视图；check 跑 Sub2MobileUITests、AppNavigationUITests、AnalyticsUITests、AccountListUITests（替代已删的 AccountListCustomizationUITests，X30）共 52 个全部通过（审查修正 ac54a3b）审查修正 ac54a3b：homePolling 拆成 home、今日 SLA、平静排行三个各自计时的循环，慢的 SLA 不再拖住 home 的 60 秒节奏；countdownElapsed 只刷新 home；SLA 和排行在途时，下拉刷新和轮询都不取消重发。新增 internal 的 pollHomeBlocks() 和 nextHomeDelay()：S1-07 退路时改 nextHomeDelay() 的函数体，把“请求 home 并落地”换成退路时改 refreshHomeBlocks(noCache:) 这一处（refreshHome、pollHomeBlocks、countdownElapsed 都经过它）。错误账号结构化字段仍作为 home 的后续请求留在 home 循环里。 |
| S1-06 | AlertActions：手动解决与静默 | ✅ | `6f1e62b` `4678cd1` | 旧服务端（事件没有 silence 键）只给手动解决，不做本机静默（S1D1-15，待用户确认）；Core 签名为 availableActions(event:silenceRejected:)，只读令牌只给文案、置灰靠入口 readOnlyGate；400 且 reason 为空或 INVALID_STATUS / INVALID_EVENT_ID / INVALID_SILENCE_ID 按程序错误处理（只记日志）；补充文案“操作没有生效，可以重试”「重试」“撤销没有成功：…”；FixtureAlertBook 为值类型，events(...) 多一个 now 参数，已做齐 status / time_range / 游标 / limit；S1-05 夹具测试的两次读取改用 7d（#35 昨天 21:52 触发，晚间不在 24h 内）；没有宿主页面，UI 用例随 S1-12 / S1-16 / S2-22，本次 check 跑了 AppNavigationUITests、Sub2MobileUITests 共 39 个，全部通过（审查修正 84057e5）审查修正 84057e5：①写后读回期间点回执「撤销 / 重试」改为排队，等当前写入结束后发出，不再被悄悄丢弃；②upsertAlert 改为 async 并先经 normalizeReceivedAlerts（S1D1-16），S1-07 在 legacyEventsGetRuleAndGroupNameOncePerSession 里请补一条“写后读回 upsertAlert 也补齐规则与分组名”的断言；③夹具 #35 在 24h 列表里的时段依赖交接给 S1-16（见待办）。 |
| S1-07 | 首页逐接口退路（没有 dashboard.home、home 404 或网络失败） | ✅ | `c1e07f8` | 404 与网络失败走退路（404 本会话不再请求 home），5xx / 429 / 鉴权仍按整体失败；七段并发、逐个落地，用轮次 UUID 丢弃迟到结果，退路结果写进 HomeBlocks，按段 fallbackStatus 做 429 与退避，轮询取最短；ops overview 与 dashboard/stats 各只请求一次，同时喂 rates 的 ② / ③；RPM / TPM 来源用 S1-04 的 HomeRatesSource（没建 HomeRatesLevel），告警计数复用 AlertCounts.counting；S1-05 的 needsFallback 改为 isOnFallback，LiveOpsStoreTests 两个用例随之调整；昨日同时按后端口径（day 桶求和、减 1 个日历日、stale 时夹到今天 00:00 至现在，区间为空不请求）；② 的非 JSON 404 也降到 ③；渠道非 JSON 404 记为 disabled(UNSUPPORTED)；成本快照只在没有 dashboard.account_cost 时并发请求；本地分档的分组 total / available 取分组字段，账号只取 1000 个；500 条上限不加“≥”；normalizeReceivedAlerts 已实现旧服务端补规则与分组名（会话内各取一次）；夹具 -ui-home-legacy 与主路径数字一致；check 跑 Sub2MobileUITests、AppNavigationUITests 共 39 个，全部通过（审查修正 326e15e）审查修正 326e15e：home 在网络失败转入退路后，再返回 5xx 或 429 时，改回按 home 自己的退避和 429 等待计时；告警补规则和分组名、可用性后续读取改为任务组子任务，不再挡住其他区块落地。 |
| S1-08 | 区块状态小视图、运维监控未开启组件（OpsDisabledNotice）与开启 / 关闭流程 | ✅ | `36bb886` | 新增 OpsDisabledPresentation、BlockStatusPresentation（scope 未列，为了单测）、LiveOpsStore+OpsSwitch.swift、BlockStatusViews、OpsDisabledNotice；与 contracts C-5 的差别：诊断用已合入的 ErrorDetails / ErrorDetailsDisclosure；30 秒复查在 enableOpsMonitoring 同一次调用里完成，不另建可取消的 Task；LiveOpsFixtures.Options 的 opsDisabled 改为 ops: OpsFixtureSwitch（新增 -ui-ops-config-off）；没有 /admin/me 的旧站点不提供开启（S1D1-07）；两步关闭确认文案待用户看效果图；界面 UI 用例随 S1-09 / S1-13；check 跑 AppNavigationUITests 17/17 通过（审查修正 c13c064）审查修正 c13c064：开启运维监控后，区块显示已开启的那一刻起，到写入满 30 秒为止，不再相信“关闭”信号（OpsSwitchState.enabledAt，与关闭一侧的 disabledAt 对称），没刷新开关的实例回的 OPS_DISABLED 不会再让提示和「开启」按钮重新出现；开启流程进行中的复查逻辑不变。 |
| S1-09 | 概览常规布局（一）：HomeView 骨架、6 格、R18 横幅与运维提示行，换根并把旧趋势图迁到过渡页 | ✅ | `5246947` | 本条到 S1-09b 之间概览只有横幅、6 格与运维提示行（同一线紧接）。R18 横幅兑现 S0-10 留给阶段 1 的事项（caution 色，按本机时钟每分钟重算）；首次加载 6 格为骨架；home 整体失败且没有值时整页“无法连接到站点”+ BlockFailureRow；轮询由 .task(id:) 驱动 homePolling，回前台与合规确认通过时 task 重启，不挂 scenePhase onChange（D18）。与规格不同：辅助功能字号 2 列；6 格用 Button + router.push（List 行内多个 NavigationLink 会一起触发）；过渡页标题“用量与性能趋势”；HomeScreenState 多一个 requestFailed 参数（home 整体 5xx 时各段仍是 idle）；vendor 占位按 U01 不可达，只有单测。删除 DashboardView.swift（S0-09 记录的三个 30 秒轮询随之消失）与 MetricView（改动总表 Components.swift 一行由此处理）。LegacyTrendPage、LegacyTrendUITests 与 .analytics 的 focus 分流由 S4-13 删除；.analytics 的 focus / metric 已在过渡页生效，range 仍未生效。旧接口、模型与 AppModel 包装留给 S1-09b。check 跑 HomeUITests、LegacyTrendUITests、Sub2MobileUITests、AppNavigationUITests、AccountListUITests（X30 替代）、SecurityPromptUITests、AnalyticsUITests、LoginUITests 共 80 个，全部通过，没有重跑（审查修正 e8dfe42）审查修正 e8dfe42：概览轮询 task 只按“可见且前台”启停（去掉 HomePollKey 里的 complianceRevision 和 foregroundRevision），合规确认改为 onChange 重读；6 格骨架改为按 stats、rates 各自区块逐格判断，HomeTicker 的参数改为 placeholders: Set<HomeTickerKind>（S1-10、S1-11 复用时以此为准）；新增夹具 -ui-home-stats-pending 和 HomeUITests.testFallbackKeepsCellsOfAPendingBlockAsSkeleton；check 通过，5 个 UI 类 49/49 通过。 |
| S1-09b | 概览常规布局（二）：今日区与每小时图、运行区，删除旧概览接口与模型 | ✅ | `6107758`、`a36f79a` | 按 D28 分视图、删除两次提交，各自通过 check。取舍：AppModel.dashboard() 没删（AppModel+Accounts.accountErrorCount 在没有 accounts.status_summary 的站点仍用它取账号角标数），只删了它的 -ui-missing-account-cost 分支；NumberedSectionHeader 按 C-33 改为泛型，另加可选 id 给标题挂 UI 测试标识；新增 HealthScoreBar（S1-13 复用）与 Sub2Core 的 HomeHourlySeries、HomeRunPresentation；“现在”落在某固定刻度前 1 小时到后 2 小时之间时省略该刻度；今日区头跟 stats、图表标题行跟 hourly、运行区头跟 ops；0 个渠道显示“还没有渠道数据”仍可点；标准格标识是 home.today.standardCost；OverviewPresentationTests 核对后未改；NATIVE_CONTRACT.md 两行留给 S1-18。过渡状态：S1-10 合入前概览没有“壹”待处理区。UI 测试：HomeUITests、Sub2MobileUITests、AppNavigationUITests（第二次加跑 LegacyTrendUITests）50 / 52 个用例全过，没有不稳定用例（审查修正 5e26c54）审查修正 5e26c54：rates 段的区块状态（有旧值时“加载超时 / 更新失败”，没有旧值时“加载超时 / 加载失败 · 重试”）统一放在运行区“错误率 / 429 / 529”这一行。6 格没有可放状态的标题行，所以不另挂；它们的错误率、RPM、TPM 也由这一行的状态说明。原方案 spec_issues 第 6 条“rates 的状态由 S1-09 的 6 格负责”作废。夹具新增 -ui-home-rates-timeout。 |
| S1-10 | 概览待处理区：告警行、账号行、合并行与三类资金待核对行 | ✅ | `0ed4a0d` | 取舍：LimitedAttentionRow 的时钟参数名用 now:（方案写的是 clock:）；HomePresentation 加 alertsFailedText / availabilityFailedText（BlockFailureRow 自己加“ · 重试”）；三个首页变体夹具放在 LiveOpsFixtures+Attention.swift，只改首页数据，账号 Tab 不变；只读令牌下「测试」置灰，底行加“只读令牌”。未做：告警行按钮（S1-16）、.accountTest 过渡映射（X18）、补偿行与旧登录加注的概览 UI 用例（S1-18）。UI 测试：check HomeUITests、AppNavigationUITests、Sub2MobileUITests 共 61 个全部通过（新增 10 个） |
| S1-11 | 概览平静布局与“按账号”排行 | ✅ | `3a38b05` | 新 HomeCalmView，HomeView 按 isCalm 整屏交叉淡入，pendingMoneyWrites(sameAddressAs:) 只算一次（X34）。Sub2Core 新增 HomePresentation+Calm（calmOutline、calmRecoveringMeta、calmRanking）。从 HomeTodaySection 拆出 HomeHourlyBlock、HomeTodayFigures、HomeMoreStatsRow，HomeRunSection.summary 改为 internal，常规布局行为与标识不变。LiveOpsStore 未改（S1-05 已实现 setCalmVisible 与排行轮询）。新夹具 -ui-home-calm-then-error，平静两变体的渠道为 8 个。取舍：按账号隐藏时渠道序号顺延为“贰”、更多统计行移到每小时区；排行失败即使有旧值也隐藏（10 §2.6）；平静图表不重复标题；未加平静滞后。UI 用例单独成类 HomeCalmUITests（7 个），因为 HomeUITests 接近 800 行。check：HomeCalmUITests、HomeUITests、AppNavigationUITests、Sub2MobileUITests、LegacyTrendUITests 共 70 个全部通过 |
| S1-12 | 告警详情页 AlertDetailView（状态卡、按钮行、范围区、规则区；错误请求计数行除外） | ✅ | `6ba5598`、`20d2a5c` | 按 S1D1-26 分两次提交：①Sub2Core 纯函数 AlertScopePresentation、DisplayFormat.dayTime，会话层 LiveOpsStore 详情副本与修订号、LiveOpsStore+AlertDetail、AlertDetailModel；②视图 AlertDetailView、AlertStatusCard，TodayDestinations 的 .alert 段，夹具与 UI 测试。与方案不同：阈值按 D21 写“5.0%”；结束说明用 AlertPresentation.sinceText；读到已结束按 upsertAlert 规则移出列表并让下次首页读取绕过缓存；去掉“P1: ”前缀写了私有实现（AlertPresentation 那份是 private）；-ui-alert-detail-ops-disabled 是第一次读事件时服务器关闭运维监控、App 开启后恢复；渠道监控关闭只看 403 CHANNEL_MONITOR_DISABLED；旧服务端分组名由 S1-07 的收事件处补，不另拉。未做：错误请求计数行（S1-17）、推送落点（阶段 6）。UI 测试：AlertDetailUITests（10 个）与 HomeUITests 已运行，43/43 通过，无 flaky。（审查修正 0ec7452）审查修正 0ec7452：分组行按 accounts.status_summary 能力门控，缺能力的旧站点改走 D02（groups/all + 账号第一页）判定分组计数和是否已删除，不再请求 status-summary。 |
| S1-13 | 监控 Tab：分段容器与概况 · 运行区（含「关闭运维监控…」入口） | ✅ | `1c3cc13`、`0a7c6fa` | 按 S1D1-26 分两次提交，各自通过 check。分段计数写进段标题（“告警 2”，0 不显示），UI 测试改用前缀 helper XCUIElement.segment(_:) 找段（AppNavigation / Home / HomeCalm / AlertDetail 各用例只换查找、断言不变）。与规格不同：错误率窗口 end 截到服务器整分钟（与 now 最多差 59 秒，正好 45 个完整桶）；运行区夹具沿用首页近 5 分钟数字（94 / 0.8% / 12 / 3）；告警中条数已知但列表未到时说明留空；离开概况不足 10 秒回来先补足再读；健康分行另写一份私有视图（统一留给 S1-18）；告警段「刷新」暂只重读 firing 列表，渠道段暂不刷新。vendor 分支（U01 下不可达）没有 UI 用例。未做：服务器区（S1-14）、渠道段（S1-15）、告警段（S1-16）。UI 测试：MonitorUITests（12 个，含只读令牌置灰）、AppNavigationUITests、HomeUITests、AlertDetailUITests、HomeCalmUITests 已运行，79/79 通过，无 flaky。（审查修正 77e25a6）审查修正 77e25a6：只有真正拿到应答才算区块的“上一次读取”，被取消的读取不推迟重启后的轮询；开启运维监控后各块立即重读，开启后 30 秒内被忽略的 404 OPS_DISABLED 最晚 30 秒后再读。MonitorState 的按块分派收成 load(_:)，isLoading(_:) 已删除，settledAt 现在返回 MonitorSettle，S1-14 只需在 load(_:) 补服务器区的 case（S1-14 方案里写的 isLoading(_:) / settledAt(_:) 按代码为准）。 |
| S1-14 | 监控 · 概况的服务器区（CPU / 内存、并发与排队、QPS、SLA、任务心跳、日志采集与入口拒绝） | ✅ | `836d01c`、`937a1ed` | 与规格不同的取舍：CPU / 内存保留 1 位小数，延迟写 850ms / 2.0s（R10）；入口拒绝退路每页 200、最多 3 页，有能力但缺合计时也走退路；小折线按时间间隔断线；多块失败合并成一行；非 JSON 404 本会话停发；overview 失败时任务区只显示一行“后台任务 —”；色调写在标识后缀。没做的部分：入口拒绝原因明细（U09）、按实例区分（D08）。UI 测试已运行：MonitorUITests、HomeUITests 共 48 个全部通过 |
| S1-15 | 监控 · 渠道段（ChannelsSection） | ✅ | `debb19e` | 四格计数为 0 不着色（规格四档都标色调，设计稿只给性能下降 / 不可用上色）；首字沿用 S1-03 毫秒读数（900ms / 8.6s）；403 CHANNEL_MONITOR_DISABLED 时丢弃旧列表并继续按退避轮询，成功即恢复；夹具分组 id 对齐 DEMO.groups，但 S5-06 前旧分组详情夹具只有 10 / 11，UI 测试只点 id 10；默认首页渠道计数改为由 9 个渠道派生（3/1/1/4），平静仍 8 个；状态图标暂用文件私有 ChannelGlyph；渠道详情页与 App 内开关不做。check 跑 MonitorUITests、HomeUITests、AlertDetailUITests、HomeCalmUITests、AppNavigationUITests：90 个全部通过，无重跑。（审查修正 548ea86）审查修正 548ea86：旧站点没有渠道路由时（非 JSON 404），渠道段改为置灰空态“站点版本较旧，暂不支持此功能”，本会话内不再请求（00 §3.3）。首页退路仍对同一应答显示“渠道监控未开启”，两处文案不同，留待统一。 |
| S1-16 | 监控 · 告警段（告警中、最近结束、加载更早与行内手动解决 / 静默） | ✅ | `ad165a5`、`54185a1` | 分页按 cross_review 放在 RecentAlerts+Paging 扩展，不改 S1-05 的 recent 类型；游标取原始页最后一条（含 firing）；轮询与写后只合并第一页、下拉重置；告警中去掉已在最近结束的事件；新增截断说明“只显示最新 N 条”（规格没有）；与方案不同：开关显示关闭时下拉仍读一次最近结束（同概况）；无 reason 的 400 一律视为游标被拒；行内按钮为同级 overlay + 隐藏占位，读屏标签带告警标题；改了 S1-06 AlertActionsTests 一处写后计数断言，并给 StubLiveOpsSource 加 alertEventRequests / alertEventPages；UI 测试未运行（UI_UNAVAILABLE），检查时 TOOLCHAIN_EXIT=3（Mac Xcode 已升到 27.2 / 27B52），待环境修好后补跑 check（审查修正 da85a73）审查修正 da85a73：轮询或写操作后拉到的第一页是满页、且最后一条比已加载第一页里最新的一条还新时（两者之间有缺口），改为从新页重来，「加载更早」从缺口往前翻；以前会漏掉缺口里的事件，「加载更早」可能消失或直接跳过缺口。实现上给 S1-05 的 RecentAlerts 加了 head 属性（服务器所给第一页里最新的一条，各方法原样保留），没有改 recent 的类型。从新页重来的效果与下拉相同：会丢掉已加载的更早页，以及本地移入、触发早于 24 小时的手动解决事件。“触发早于第一页、之后才结束”和“24 小时窗口滑出的旧行”两点仍按已知限制处理。UI 测试未运行（UI_UNAVAILABLE），TOOLCHAIN_EXIT=3，原因同前。 |
| S1-17 | 告警详情 · 错误请求计数行（接阶段 4 的 errorCount） | ✅ | `c8bc894` | 只调 S4-01 的 errorCount（R19），经 LiveOpsSource.errorCount 与 controlled(_:)，404 OPS_DISABLED 记运维关闭；计数在事件读完后再发（事件不存在、运维关闭、400 时不发，旧服务端等补上规则），只随 load(refreshScope: true)，不进 60 秒轮询；全站错误类规则也加这一行（不带分组），全站 upstream_error_rate 写“上游错误”；平台告警不加（规格没有，筛选与路由也没有平台条件）；有旧值时失败写“更新失败”、保留数字，没有旧值时失败是“错误请求 · 加载失败 · 重试”；去向映射叫 pushedRoute（方案写 logsRoute），S1-12 的 row() 改为按它判断；夹具测试放在 AlertDetailFixturesTests（方案写 LiveOpsFixturesTests）；-ui-alert-error-count-fails 只让第一次失败（首屏只 load 一次）。移交 S4-05：改写日志页时同步更新 AlertDetailUITests 的 assertErrorLogsOpened。UI 测试未运行（UI_UNAVAILABLE），检查时 TOOLCHAIN_EXIT=3（Mac Xcode 已升到 27.2 / 27B52），待环境修好后补跑 check AlertDetailUITests,HomeUITests |
| S1-18 | 阶段 1 收口：测试清单与夹具核对、旧代码清理、文档与小结 | ✅ | `d293b29`、`b7734f3` | 按 D28 分两次提交，18a 通过 check，18b 只改文档。取舍：参数化 UI 用例做成表驱动的新类 StageOneFixtureUITests（11 个夹具各一个函数，每屏两张截图），覆盖首页 6 种 + 旧站点退路 + 监控 4 种；HomeUITests 末尾补补偿行与本站点旧登录行两个用例（S6-09 已合入，补偿行点按断言 grant.pending，不是占位 sheet）；两条锁定性单测首跑即过；AppModel 只删 -ui-dashboard-slow-trend 三行，不拆、不改 Package.swift；HomeTicker 映射与 monitor.placeholder 已由 S1-10 / S1-16 清理，本条只 grep 核对；没有文件超过 800 行（HomeUITests 774），未拆分；README / API_COMPATIBILITY / NATIVE_CONTRACT 最小修改。未做：U54 与 304 实测（未获授权访问测试环境，S1D1-27）、健康分行合并与 ChannelGlyph 统一（见 BACKLOG）。阶段 1 小结见下节。UI 测试：check 8 类（StageOneFixture、Home、HomeCalm、Monitor、AlertDetail、LegacyTrend、AppNavigation、Sub2Mobile）132/132 通过，无 flaky；单测一次被无关的计时用例 AccountOAuthTests.authURLReplyKeepsStateAndRejectsUnsafeLinks 挤掉，同一提交重跑 UNIT_EXIT=0。建议集成者合入后跑一次全量 gate |

### 阶段 1 小结

#### (1) 完成项

- S1-00 `97038af`；S1-01 `d8608c6`；S1-02 `807a76f`；S1-03 `bac53e6`；S1-04 `a5a7854`
- S1-05 `61fb705`（修正 `ac54a3b`）
- S1-06 `6f1e62b` `4678cd1`（修正 `84057e5`、`274af1f`）
- S1-07 `c1e07f8`（修正 `326e15e`）
- S1-08 `36bb886`（修正 `c13c064`）
- S1-09 `5246947`（修正 `e8dfe42`）
- S1-09b `6107758` `a36f79a`（修正 `5e26c54`）
- S1-10 `0ed4a0d`；S1-11 `3a38b05`
- S1-12 `6ba5598` `20d2a5c`（修正 `0ec7452`）
- S1-13 `1c3cc13` `0a7c6fa`（修正 `77e25a6`）
- S1-14 `836d01c` `937a1ed`
- S1-15 `debb19e`（修正 `548ea86`）
- S1-16 `ad165a5` `54185a1`（修正 `da85a73`）
- S1-17 `c8bc894`
- S1-18 `d293b29` `b7734f3`
- 与阶段 1 相关、提前做的其他阶段条目：S3-07 `0a4db1b`（同地址待核对夹具）、S4-01 `e760dd5`（errorCount）、S4-10 `f785b88`（PerformanceTrend 按覆盖秒数）、S4-11 `5c6897e`、S6-09 `b921f1c`（补偿待核对页）。
- S1-17 随第 1 波完成，不进未做项。

#### (2) 完成标志对照（核查脚本逐个函数对照，全部存在）

- 10 §1.7 HomePresentationTests：
  - 6 格：tickerCellsFollowFixedOrderLabelsAndDestinations、tickerCellsFormatThroughDisplayFormat
  - “—”：tickerCellsShowDashWhenMissing
  - 利润为负：profitIsActualMinusAccountWithUnicodeMinusAndNoPlus
  - 涨跌：yesterdayChangeArrowOneDecimalAndHiddenCases
  - TPM 退路标记：tpmFallbackMarkOnlyForDashboardStats
- DashboardHomeDecodingTests：partialSuccessKeepsEachSectionIndependent、unknownSectionStatusDecodesAsError、missingOrNullSectionDecodesAsError
- AttentionItemsTests：
  - 顺序：itemsFollowFixedSlotOrder、alertsSortedBySeverityThenNewest
  - 合并 / stopped 第 3 行：limitedRowMergesNamesEarliestAndStoppedThirdLine
  - 截断：limitedRowUsesTotalsAndEllipsisWhenTruncated、moreAlertsRowCountAndHighestRemainingTone
  - 上游返回异常：errorRowReasonMatchesAccountDisplayStateAndNeverErrorMessage
  - 上游 529：overloadedRowFixedReasonCountdownAndStoppedMark
  - R02：pendingMoneyRowsTitlesDetailsAmountsAndDestinations，加 S1-18 的 compensationRowSpellsOutR02DetailAndAmount
  - X34 加注：pendingRowsFromAnEarlierLoginOfTheSameSiteAreAnnotated
- §2.8 五条：calmWhenOnlyLimitedAccounts、silencedFiringAlertIsNotCalm、opsDisabledWithoutIssuesIsCalm、availabilityFailureIsNotCalm、localPendingRecordsIncludingCompensationAreNotCalm，加 S1-18 的 calmTreatsPendingRecordsFromAnyServerIDAsNotCalm
- §3.7 / §6.3：OpsAlertsDecodingTests.silenceKeyPresenceIsRecorded；AlertPresentationTests 的 thresholdPrefersRuleThenEventValue、valueFormatsByUnit、operatorSymbolsMapAllBackendOperators、scopeTextFollowsDimensionPriority、titleUsesRuleNameAndStripsSeverityPrefixWithoutRule、sinceTextByStatus
- §4.7 MonitorPresentationTests：jobNamesMapAndSortByTableOrder、jobLineTrailingTextPerState、jobLineDetailTextPerState、localJudgementFollowsFourRules、errorRateSeriesMergesFortyFiveMinuteBucketsIntoNinePoints、errorRateSeriesHandlesResidualSparseAndZeroDenominator
- §5.7 ChannelOverviewDecodingTests：decodesBackendOverviewShape、channelOverviewToleratesMissingAndNullFields（方案写的名字是 toleratesMissingAndNullFields，以代码为准）
- §6.7 OpsAlertsAPITests：alertEventsSendsQueryInFixedOrder、alertReadEndpointsUseTheirPaths
- DashboardRPMTests、OverviewPresentationTests 不再引用 performanceWindow / performanceCard。
- 夹具：LiveOpsFixturesTests 的 allOK / opsDisabled / availabilityError / hourlyTimeout / calmFixturesAreCalm。
- 6 种 UI 数据：StageOneFixtureUITests 的 11 个用例全部通过：testHomeAllOK / OpsDisabled / AvailabilityError / HourlyTimeout / Calm / CalmLimited / LegacyFallbackRenders，testMonitorDefaultRendersEverySegment / OpsDisabledRendersEverySegment / ChannelMonitorOffRendersChannels / NoFiringRendersEmptyAlerts。

#### (3) 改动总表 10 章各行

- 已满足：
  - DashboardView 换成 Home/*，四卡与“运行健康”删除，三个 30 秒轮询合成 60 秒（S1-09 / S1-09b）
  - costBreakdown / performanceCard 删除，snapshot-v2 退路进 LiveOpsStore+Fallback
  - APIClient.dashboard() 保留作退路，新增 dashboardHome
  - dashboardTrend 按服务器时区
  - dashboardMonitoring / OpsReply / OpsSnapshot / DashboardSummary.monitoring 删除（a36f79a）
  - 条件请求走 ConditionalCache
  - dashboardRates / accountStatusSummary / errorAccounts / accountsRanking
  - DashboardHome、AccountStatusSummary、HomePresentation、MonitorPresentation、OpsMonitoring、OpsAlerts、ChannelMonitor 等新文件
  - Sub2MobileApp MainTabs 的概览与监控 Tab
  - AlertRow 首页复用
  - PerformanceTrend 按覆盖秒数（S4-10）
  - DashboardTrendMetric.actualCost 文案已是“实际扣费”
- 位置不同但已满足：
  - DashboardLoadState → NativeApp/Session/LoadState.swift，内部存 BlockState（X27）
  - 6 种 UI 数据 → LiveOpsFixtures*，不在 DemoData（X05）
  - AppModel 包装 → LiveOpsSource / ClientLiveOpsSource（S1-05）
  - DashboardTrendChart → 统计分析过渡页 LegacyTrendPage
  - 0.4 格式函数 → 统一用 DisplayFormat（R10）
  - requestErrorCount / upstreamErrorCount → errorCount(filter:kind:)（R19，S4-01 / S1-17）
- 留给阶段 4：
  - PerformanceTrendView 抽 PerfTrendBody，删除 dashboardPerformanceTrend(hours:)（S4-16）
  - 删除 LegacyTrendPage、LegacyTrendUITests 与 focus 分流（S4-13）

#### (4) 阶段 0 备注里留给阶段 1 的事项

- S0-04：U54 未实测，见 (7)。
- S0-05：dashboard/home 走 ConditionalCache；“更新于”用本机收到响应的时间（HomeView 的 lastFullSuccessAt 按时钟偏移换算）。已满足。
- S0-07：首页副标题设备与服务器偏移不同时加“· 按 UTC+8”（subtitleUsesServerCalendarAndAppendsOffsetOnlyWhenDifferent）。已满足。
- S0-08：relativeTime（待核对行）、countdown（过载 / 受限）、minutesLeft（R18 横幅）已有页面调用，6 格术语“利润”。已满足。
- S0-09：区块小视图 BlockFailureRow / BlockStatusAccessory（S1-08）、LiveOpsStore.pollInterval 60 秒、颜色只用 Palette / Tone（核查 0 处系统色）。已满足。
- S0-10：R18 横幅 home.banner.renewal。已满足。
- S0-12：三类待核对行（S1-10），S1-18 补了补偿行与旧登录行的 UI 用例。已满足。
- S0-13：BlockFailureRow 在 423 时给「完成合规确认」；合规确认后概览重读（e8dfe42）。已满足。
- S0-19：区块错误态接 ErrorDetailsDisclosure（BlockStatusViews.swift:91）。已满足。

#### (5) 核查结果

核查脚本只读，不入库，放在 scratch/s1-18/check_stage1.py。
- R19：Sub2Core 里 func accountStatusSummary( / alertEvents( / errorCount( 各 1 处，struct AlertEventCursor、enum OpsDisabledReason 各 1 处。LiveOpsSource 的协议要求与转发实现不算重复定义。测试 target 里没有 extension LiveOpsSource。
- 旧符号全仓 0 处：requestErrorCount、upstreamErrorCount、firingAlerts(groupID:、dashboardMonitoring、OpsReply、OpsSnapshot、DashboardLoadState、DashboardView、MetricView、performanceCard、performanceWindow、monitor.placeholder、HomeRatesLevel、HomeFallback.alertCounts、LegacyAlertSilences、-ui-dashboard-slow-trend、-ui-missing-account-cost、-ui-cost-snapshot-error。其中 NATIVE_CONTRACT 两处与 slow-trend 分支是本条清掉的。
- HomeDestination → AppRoute 的映射全 App 只有 HomeDestinationAction 一处。
- 格式代码：首页、监控与阶段 1 展示文件（43 个）没有显示用的格式代码。只有两处非显示用途：HomeFallback.swift:182 的 DateFormatter（接口日期键前缀）和 OpsAlerts.swift:210 的 ISO8601DateFormatter（游标）。
- TimeZone.current：只有 ServerTime.swift:24（.device）一处，加上 HomeView 副标题的 deviceTimeZone: .current（白名单）。另有 7 处 `serverTimeZone.timeZone ?? .current` 是没有会话时的退路，与 .device 等价。
- UI 标识：UITests 里 902 个标识，按插值前缀和 "\(id).retry" 之类的后缀识别后，阶段 1 的首页 / 监控标识都能在 NativeApp 找到。剩下 24 个找不到字面量的，都是 capability 名（-ui-without-capabilities 的参数）、邮箱或模型名片段，或其他阶段的键盘 / 菜单前缀，不属于阶段 1。
- tabBars.buttons["管理"] / ["设置"] 只在 AppNavigationUITests 里作“不存在”断言。
- 启动参数：UITests 用到的参数 NativeApp 都有解析。阶段 1 夹具里没有 UI 用例在用的只剩 -ui-performance-error（PerformanceTrendView，S4-16 删除）；-ui-home-legacy 现在由 StageOneFixtureUITests 使用。
- 文件长度：没有超过 800 行的。AppModel 472、HomeUITests 774、MonitorUITests 740、LiveOpsStore 476、LiveOpsFixtures 456 行。
- 其他：generate_project.py 在加新文件前重新生成无差异；Features/Home、Features/Monitor、LegacyTrendPage 没有视图式推入（X39）；Package.swift 的 exclude 完整；build 没有我们源码的 warning。

#### (6) 未做项及原因

- HomeUITests 没抽基类（S1D1-14），774 行，未超过 800。
- 首页与监控的健康分行没合并（方案 out_of_scope，两处已共用 HealthScoreBar 与 HomeRunPresentation.Health）。
- ChannelGlyph 与账号 / 代理图标没统一（留给 S2-23）。
- 概览待处理账号行是否复用 AccountActions：默认不做。
- U07 渠道详情、U13 静默列表、U09 入口拒绝明细：本版不做。
- 需要用户确认的默认值：
  - 没有 /admin/me 的旧服务端不提供开启运维监控
  - 事件没有 silence 键的旧服务端不提供静默（S1D1-15）
  - 旧服务端告警行补规则名与分组名的做法（S1D1-16）
  - 测试环境实测 U54 / 304（S1D1-27）

#### (7) U54 与 304

S1-18 未实测：未获授权访问测试环境（S1D1-27）。U54 维持默认值（客户端超时：home 15 秒、统计聚合 45 秒、dashboard/stats 90 秒）。

#### (8) UI 测试运行情况

- check 跑了 8 个类：StageOneFixtureUITests 11、HomeUITests、HomeCalmUITests、MonitorUITests、AlertDetailUITests、LegacyTrendUITests、AppNavigationUITests、Sub2MobileUITests，共 132/132 通过，没有重跑才过的。
- 本条之前 Mac 上的 Xcode 自动升级到 27.2，第一次 check 被工具链守卫拒绝（TOOLCHAIN_EXIT=3），但 132 个 UI 用例同样全过。合入主分支 b91d265 后在 d293b29 上重跑，全部通过。
- calm 夹具与账号 Tab 的演示数据不一致（S1-05），只影响 UI 测试与截图。
- 建议集成者合入后跑一次全量 gate，作为阶段 1 的收尾。
- 集成者合入后（合并提交 `4c70522`）：check 8 个类 132/132 通过；全量 gate 的 TOOLCHAIN_EXIT=0、UNIT_EXIT=0（2175 + 912）、BUILD_EXIT=0、我们源码无 warning，UI 575 个中 572 个通过、没有重跑才过的。失败的 3 个都是 AccountNewUITests 的既有失败（testCredentialSectionsFollowMethod、testDockListsMissingItemsAndJumpsToFirst、testTurningOffMixedSchedulingRemovesGroupsWithUndo），两次都失败，失败点与 BACKLOG 阶段 2“S2-19 新建账号三个 UI 用例原有失败”一致，与阶段 1 无关。

#### 移交（S1D1-28）

- S2-23：测试连接完成时调用 liveOps?.noteExternalWrite()。
- S4-05：改写日志页时同步 AlertDetailUITests.assertErrorLogsOpened。
- S6-09：已合入，补偿待核对页保留了 sheet.close（RedeemGrantPendingView.swift:42），本条两个 HomeUITests 用例依赖它。
- S4-02：复用 TrendGranularity。
- S4-13 / S4-16 / S4-18：运维关闭一律用 OpsDisabledNotice。

## 阶段 2 · 账号

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S2-01 | 账号模型与列表查询：JSONValue、UpstreamAccount 补字段、AccountListQuery / managedAccounts、分组排序 | ✅ | `9882ca6` | credentials 只含非敏感键且不参与编码（S0-17 用例要求编码不含凭据值），解码与 init 时按后端 17 个敏感键剔除并补 has_<key>，另加 credentialsArrivedUnredacted（S2D1-09）与 parentAccountID（S2D1-21）；extra 整份保留为 JSONValue，不是对象时账号照常解码；AccountProxy 保留地址（scheme 对应 JSON 的 protocol），不解码登录信息；契约按 S2D1-11：search / platform / type 为 String、supportsListQuery 是属性、多 schedulableNow，lite / include_counts / include_scheduler_score 统一发 1；allGroups(includeInactive:) 带 platform 时本地过滤；改了 AccountRuntimeTests 一个旧用例的断言（代理地址与 extra 现在保留）；旧 AccountsView 只做类型适配，状态 / 分组 Picker 未在模拟器手动点验；check 已跑 AccountManagement / AccountListCustomization / Sub2Mobile / AppNavigation 四类，38/38 通过 |
| S2-02 | 账号读接口与平台目录：今日批量、运行时批量、5 小时窗口、带版本号的账号详情、MetaCatalog 与显示名 | ✅ | `9a0448b` | 与规格不同的取舍：平台显示名按 S2D1-12，App 已知 id 用 GroupPlatform.title（zhipu 显示“智谱 GLM”），其余才用目录名，与 20 §0.3 字面“目录优先”不同，待用户确认；今日批量的 stats 不含失败占位；runtime/batch 默认 include_window_cost=0，只对它做 TOO_MANY_IDS 再拆，sampled_at 记入 serverClock、返回类型不变；metaCatalog() 遇非 JSON 404 / 423 返回内置清单，其余错误抛给 S2-03 包装；LenientDecoded 是已有 Lossy 的别名；内置清单并入 MetaCatalog.swift（191 行，没有拆出 +Builtin 文件）。未做：页面接入与 AppModel 包装（S2-03）、删除旧 accountTodayStats(ids:)（S2-04）。UI 测试未涉及（只跑了 check 的单元与编译）。 |
| S2-03 | 账号列表数据层：分区与刷新纯函数、AccountListModel、AppModel+Accounts 与演示夹具、Tab 徽标计数 | ✅ | `5eecbaa` | 取舍：分组排序与主分组沿用 AdminGroup.displayOrder（sort_order 缺失按 0，方案原为排最后）；平台同级最后按 id 升序；组头“暂停 N · 停用 M”零值部分不写；三种定时触发共用一个门控；状态推导用站点时钟，节流与徽标用本机时钟；徽标只丢弃 60 秒内更早的结果；平台顺序在打开或下拉后的第一次完整刷新（含汇总）结束后才冻结；后续页失败保留已加载行且不显示 2000 行提示；加了 -ui-accounts-long-windows。未做：界面、徽标显示与 60 秒补取、dashboard/stats 退路（S2-04）。UI：AppNavigationUITests、Sub2MobileUITests 共 39 个全部通过（审查修正 2437dab）审查修正 2437dab：轻刷新的 runtime、汇总、今日三块各自做 429 等待和失败退避（定时器与倒计时发起的轮次才退避，列表的 429 不拦这三块）；逐页加载被取消后保留部分行，定时器恢复时立即补一次完整刷新；2000 行提示只在读满上限时出现。 |
| S2-04 | 账号列表界面：AccountRow、平台分区三行列表、筛选胶囊与平台菜单、Tab 徽标与跨 Tab 筛选，替换旧列表 | ✅ | `75307e4` | 与规格不同的取舍：正常账号不画状态牌（照设计稿）；暂停 / 停用只把名称改为 ink2，不降整行透明度（保 4.5:1，请看 UI 截图 account-row-idle 确认）；限时第 3 行“只截尾部”（条目正文“只截头部”按笔误处理），“已停止调度”与“HH:MM 恢复”不截；平台菜单数字放在菜单项第二行，“全部平台”取 totals.total；current_concurrency 为 null 也写“— 并发”；副标题超过 1 小时写“今天 HH:MM 更新”；zhipu 按 S2D1-12 显示“智谱 GLM”；无筛选意图回到“全部”；过渡入口点行用 navigationDestination(item:) 视图式推入。徽标由 AppModel 会话级 accountBadgeTask 前台每 60 秒补取（无 status_summary 时退回 dashboard/stats.error_accounts）。旧详情与测试页原样移到 LegacyAccountDetailView.swift。删除 APIClient.accountTodayStats(ids:)、AppModel 旧账号包装与 DemoData 旧账号夹具。未做：右滑调度（S2-06）、选择与操作坞（S2-07，本条到 S2-07 之间列表没有批量与快捷编辑）、右上＋（S2-19）、组头告警牌（S2-22）、新详情（S2-08）、删除 APIClient.accounts(page:…)（S2-23）。UI 测试已运行：check 5 类 55/55 通过，无重跑；删除的 AccountListCustomizationUITests 含 5 个基线不稳定用例，从基线名单中去掉，改跑 AccountListUITests（12 个） |
| S2-05 | 账号写接口：PATCH + If-Match 与 PUT 退路、412 比对、混合渠道、恢复、调度开关带 key、删除、模型列表、恢复原代理 | ✅ | `11968da` | 比较、冲突、读回挪到新文件 AccountPatchCheck.swift（公开签名不变）；412 比对增加 .alreadyApplied；含敏感键 .set 的请求读回一律判为没成功；PUT 退路去掉底里的敏感键和未点名的受管 extra 键，凭据未脱敏的旧站点改凭据本地拦截（LEGACY_CREDENTIALS_PUT）；混合渠道文案用规格的中文引号；ReasonCatalog 没增补 3 个 reason（走通用兜底）；upstream_billing_rate_sync_enabled 与 expected_config_version 不发；旧编辑页改用 fullUpdate、有能力时带 key，旧详情调度开关带 key、结果不明时读回；AccountManagementTests 收窄改名为 accountBatchWritesRejectOldIdentity（S2D1-16/24）；check 时 AccountListUITests 12/12 通过（审查修正 c4bcbf3）审查修正 c4bcbf3：PUT 退路删除最后的非敏感凭据键时，被删的键改为按 null 发出，不再发出会被服务端忽略的空 credentials（后端只在 len(credentials) > 0 时才合并）。 |
| S2-06 | AccountActions：恢复状态、启停调度、启用账号的确认框、回执、撤销与结果核对，列表右滑 | ✅ | `4d1c67c` | 本体在 Session/AccountActionsCore.swift（可单测），App 入口与确认框、右滑在 Features/Accounts/AccountActions.swift；签名比 C-7 多返回 AccountActionOutcome、enableAccount(etag:)、isRunning，写包装带 generation（S2D1-05），serverNow / accountWriteClient 在 AppModel+Accounts。读回不符：带 key 回执“结果未确认，可用同一编号重试”，不带 key 回执“没有生效，可以重试”；撤销成功不出回执；启用账号 412 静默重发一次。到期自动暂停的账号右滑不给“启用调度”（S2D1-20），错误账号开关关时按字面给“启用调度”（待确认）。只读令牌不提供右滑。恢复确认框暂无宿主，UI 测试随 S2-08。不订阅 KeyedWriteEvent。check：AccountListUITests、Sub2MobileUITests 38/38 通过。（审查修正 3d3987f）审查修正 3d3987f：带 key 的调度开关和启用账号 PUT 退路遇到 503 幂等存储不可用时，先读回；没有生效时回执“{动作}没有生效：服务器暂时无法受理，稍后用同一编号重试”，点“重试”后等 10 秒冷却结束才用同一 key 发出（回执只显示 4.2 秒，所以按钮行先显示进行中）。顺带修正：无 ETag 站点走 PUT 退路时，重试沿用原 key。 |
| S2-07 | 批量操作：选择模式与底部操作坞（停止 / 启用调度），分批、Face ID、撤销与结果 sheet | ✅ | `38013a7` | 按方案 spec_issues：部分失败时回执只给“查看”，撤销移到结果 sheet 底部；撤销只针对操作前与目标值不同的成功账号；前一批没有明确成功就停止，后面的写“尚未执行，请重新选择”；成功 0 个按“整批被拒 / 逐项全失败 / 结果不明”三种回执；不带 key 时 30 秒；选择模式下平台菜单置灰。批量“刷新凭据”与 AccountBatchRefresh 已删除（U21），§8.8“⋯”菜单不做。收起分区的“已选 N”只由组头读屏读出。UI 测试：check AccountBatchUITests,AccountListUITests 23/23 通过 |
| S2-08 | 账号详情页骨架：AccountDetailScreen、状态卡与按钮行、加载 / 失败 / 已删除状态、路由替换 | ✅ | `afe1c74` | 与规格不同：错误态牌旁写“上游 {error_status_code}”（没有时不写），正文 error_summary；到期自动暂停的主按钮为“修改过期时间…”（S2D1-20，暂时打开旧编辑页，待用户拍板）；安静卡也画模型限流块；已取到服务器数据后再读失败不提示；无快照失败页带原因；只读令牌下测试连接也置灰；按钮按设计稿 .act 做成横排胶囊，没有用 glass。过渡：测试连接→旧 AccountTestView（S2-14），凭据三按钮→占位 sheet（S2-11/16/17），⋯ 暂放编辑账号（S2-10）/ 刷新令牌（S2-16）。editVersion 留给 S2-10；新增夹具 -ui-account-detail-error / -ui-account-removed / -ui-account-group-transition。UI：check 跑 AccountDetail、AccountList、Sub2Mobile、RequestLogs、AccountBatch、Groups 六类，60/60 通过（审查修正 068203e）审查修正 068203e：读取在途时轮询等满 60 秒，避免主线程空转；门控关闭取消的读取不计为同步，回到页面立即重读，倒计时那次被取消也会重发；S2-06 AccountActions 的回执按钮与重发任务改为强持有，离开详情后撤销 / 启用调度 / 重试仍有效。UI 测试已运行（4 类 41 例全过）。 |
| S2-09 | 账号详情三节：容量（壹）、今日（贰）、记录（叁）与状态卡“最近上游错误”行 | ✅ | `cfc6947` | 逻辑放新文件 AccountDetailSections / DisplayFormat+Clock / AccountActivitySections（S2D1-24），状态卡用 S2-08 的 errorFooter 插槽，已合入的签名不带 clock / timeZone，行视图从 sessionContext 取；mergingCapacity 不覆盖 current_window_cost；刷新块判定多了 inFlight（正在读的块不重复发）；今日 429 只用 throttleMessage，自建小块等 S2-23 换成 BlockFailureRow；夹具 429 等待 8 秒（方案 3 秒）；-ui-ops-disabled 直接用 OpsFixtureSwitch；#2、#3 也补了 scheduling_rpm 和空闲分钟。UI：check 跑了 AccountDetailUITests、RequestLogsUITests、AccountListUITests，35 个全过，无重跑才过的 |
| S2-13 | 测试连接接口层：SSE 读到 test_result、AccountTestResult、异步 test-runs、结果解读与输出脱敏 | ✅ | `43f7877` | 与规格不同：默认模型不建内置表，列表空或失败时发空 model_id，输出区写“默认模型”（S2D1-01，20 §4.5）；输出区另加 error“✕ …”和媒体“← 收到…”行（20 §4.3 只列 content / status）；老服务端读到 EOF 再结束（C07 退路）；testAccount 增加必填参数 expectsTestResult；修订 D18：测试流不随 suspend 停止（S2D1-02）；中断容差 2 秒；文案补充：恢复说明“错误和限流”、Bedrock / Vertex 写“在 Web 中更换凭据”、非凭据类错误写“后端已把账号标为“错误”…”、状态未知不写副文案；API Key 的 403 写“上游返回 403”；计时用 DisplayFormat（1 位小数）；转录拆到 AccountTestTranscript.swift。未做：sheet、后台任务、老服务端读回比对的调用（S2-14）。UI：Sub2MobileUITests、AccountDetailUITests 共 28 个用例全部通过 |
| S2-10 | 内联编辑一：基础与调度分区、AccountSectionSheet、分组与过期时间选择器、PATCH 保存流程（撤销、412、409、读回） | ✅ | `0732035` | AccountPatchFlow 按 S2D1-04 放在 Session 并逐分支单测；与 C-14 相比多 hasMixedChannelDetails、dismissPrompt、reloadedBase / reloadRevision；详情分区用卡片行而不是 List + LabeledContent；过期时间按本机时区（U53），脚注只在过期页、且时区偏移不同时出现；⋯ 只剩令牌账号的“刷新令牌”，密钥账号暂不显示 ⋯（S2-11 / S2-16 再加项）；“修改过期时间…”打开调度 sheet（S2D1-20）；倍率位数账号一侧定为 DisplayFormat.decimal 最多 3 位（BACKLOG 由 S2-23 更新）；GROUP_NOT_FOUND 不进已删除页，但没有自动刷新分组目录；UI：AccountEditUITests、AccountDetailUITests、AccountListUITests 共 49 个全过（审查修正 968b677）审查修正 968b677：“没有保存成功”“结果未确认”期间，分区 sheet 的字段和“保存”一并锁住（AccountPatchFlow.locksForm），只能“重试”“刷新核对”或“取消”，避免重试旧请求后关闭 sheet、悄悄丢掉之后改的字段；S2-11、S2-12、S2-16、S2-20 复用保存流程时，表单同样按 flow.locksForm 置灰。 |
| S2-11 | 内联编辑二：代理分区与选择器、恢复原代理、⋯ 菜单、在 Web 中编辑、删除账号 | ✅ | `5d62dac` | Proxies.swift 首建（AdminProxy 全字段、ProxyExpiryWord / ProxyExpiry、allProxies），新增 AccountWebLink、AccountProxyPresentation、AccountDetailWrites（恢复原代理 / 删除流程）、AccountListSignal（会话级）；与规格不同：删除回执在确认框关闭前出现、关闭后再 pop（同公告删除写法）；删除遇到“需再次确认”只回执、不给重试；停用代理副行写到期词；分区编辑标识为 account.section.proxy.edit；按 S2D1-24 改了 AppModel.swift 锚点三行与 AccountsView 一个 onChange；check 跑了 4 个 UI 类，64 个全部通过（审查修正 9066c22）审查修正 9066c22：代理选择 sheet 在 412 冲突“重新载入”后改用服务器上的最新账号（新增夹具 -ui-account-proxy-conflict 和 UI 测试 testProxyConflictReloadMovesPickerToServerCopy）。（审查修正 7319b0d）审查修正 7319b0d：testSwitchingToNoProxy 失败的原因是带撤销的回执（4.2 秒，可点）盖住了代理行中心，不是 App 回归。改为等回执离开再点行。三处点回执按钮的地方改用一次查询的 receiptButton，避开 4.2 秒内来不及点的问题。改后 AccountDetailMenuUITests 连跑 3 次 check 全过（94/94、17/17、17/17，无 flaky）。 |
| S2-12 | 内联编辑三：模型分区与映射编辑器、高级分区 | ✅ | `f393974`、`f679c34` | Sub2Core 拆成 AccountModelMapping / AccountProtocolEndpoints / AccountAdvancedField / AccountAdvancedDraft 四个文件，测试四个文件（含 PUT 退路安全专项）；草稿产出 AccountEditChange，保存与撤销走 S2-10 的 AccountPatchFlow；与规格不同：模型限流徽章按映射后的实际模型匹配，自动探测上游声明倍率只给 apikey，透传读法同后端、关闭时连旧键 openai_oauth_passthrough 一起删，限额关闭只删主键，基础 RPM 由 App 校验 1–10000，切换账号类型 / API 协议时照 Web 联动官方端点、自定义端点两行只读加脚注；新文案：“实际模型不能用通配符”“这个请求模型已在列表里”“读取模型列表失败”“没有可选的模型，可以用“添加映射”手动填写”、三条限额校验、端点脚注；AccountEditSectionBox 加可选 meta（S2-10 文件 5 行）；分区标识沿用 account.section.models / adv；状态行传 onOpenWeb（S2D1-09）；未做：同步上游模型、凭据分区（S2-16）；UI 测试：f393974 check 4 个类 73/74，S2-11 的 testPickingProxySavesThenUndoRestores 因回执 4.2 秒内来不及点撤销而失败，f679c34 调整其等待顺序后 check AccountEditUITests、AccountDetailMenuUITests 38/38 通过（审查修正 934d43b）审查修正 934d43b：关闭“自动探测上游声明倍率”后点撤销，会一并写回后端顺带关掉的倍率同步（upstream_billing_rate_sync_enabled）。 |
| S2-14 | 测试连接 sheet 与后台测试任务：AccountTestSheet、AccountTestCenter、.accountTest 路由 | ✅ | `986e7c9` | 默认模型按 S2D1-01（列表空或失败发空 model_id，显示“默认模型”，不建内置表）；输出区另有 error 行“✕ …”与媒体行；后台任务在 SSE 开始时申请（不改 sceneDidChange）；sheet 打开时多一次 GET :id；失败结果只能换模型再测，“重新测试”只在中断、没开始和 BUSY 时出现，BUSY 按钮“N 秒后重新测试”默认 30 秒；中断回执照抄规格不带账号名；夹具放新文件 DemoData+AccountTests.swift（Package.swift exclude 一行）；更换 Key / 重新授权回执的“测试”留给 S2-16 / S2-17。UI：check 跑了 AccountTestUITests、AccountDetailUITests、Sub2MobileUITests、HomeUITests、AccountDetailMenuUITests 共 86 个，85 个通过；AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues 两次失败（字典遍历顺序随机，既有不稳定），单独重跑 AccountDetailUITests 20/20 通过 |
| S2-15 | 凭据接口层：各平台授权链接与换码、reauthorize、apply-oauth-credentials、刷新令牌、OAuth 凭据构造与回执文案 | ✅ | `c561924` | OAuth 部分拆成 AccountOAuth / OAuthCredentialBuilder / AccountOAuthErrorCopy 三个文件（签名不变）；读回余量按 S2D1-03 定为 2 秒，并比较提交前的 refreshed_at；Grok 换码或重新授权失败一律只给“重新生成链接”；回执和说明句照设计稿补了“原状态暂停”“只有模型限流”“账号已停止调度，之后仍暂停。”几支；Gemini / Antigravity 构造凭据时丢掉空串；旧服务端的刷新回执退回读 credentials.expires_at；OAuthTokenInfo.fixture 给夹具用；删除旧 refreshAccount(id:) / refreshManagedAccount 和 accountBatchWritesRejectOldIdentity；不含界面（S2-16/17/19）；AccountDetailUITests 20/20 通过 |
| S2-18 | 新建账号接口与草稿：createAccount、AccountNewDraft（方式映射、缺项清单、凭据构造、自动命名、分组过滤）、流程纯函数 | ✅ | `a2b7923` | AccountNewFlow 按 S2D1-13 收缩为命名空间（不含状态机）；AccountNewCancelAction 的 confirmDiscard / finish 不带关联值；新建账号只在有 admin.idempotent_writes 时带 key（与 00 §2.5.1 字面不同）；核对匹配加 created_at ≥ 首次发送 − 120 秒；apikey 默认开上游倍率探测、Vertex location 默认 global、Grok OAuth 不补 base_url（同 Web）；单个原生协议不提供“自适应”（只影响 Cline）；智谱显示“智谱 GLM”（S2D1-12，与 20 §0.3 字面不同）；另拆出 AccountNewMethods.swift、AccountNewCredentials.swift 及其测试；UI 测试未运行（无 ui_test_classes，未改界面）（审查修正 c8cc174）审查修正 c8cc174：旧站点（没有 /admin/me）只对 OpenAI 的 apikey 账号发 upstream_billing_probe_enabled。AccountNewDraft 新增 init(isLegacyServer:)，S2-19 建草稿时必须传入会话的 AdminMe.isLegacyServer。patch(since:) 对不再使用的敏感凭据改发 ""（不发删除），换方式、清空 Session Token、OAuth 换 Setup Token 后，旧密钥都不会再被服务端使用。 |
| S2-16 | 凭据分区：API Key / Base URL / 访问令牌行、更换 API Key 与 Base URL sheet、刷新令牌、凭据类主按钮 | ✅ | `df6b264` | 按 S2D1-03/04/05/06/09/14/22 实现：复用 S2-15 的纯函数与 S2-10 的 AccountPatchFlow（没有自建 AccountSecretPatchReadback，也没改 AccountPatchFlow），刷新包装带 generation，多协议平台的 Base URL 走 Web，旧服务端更换凭据指向 Web。与规格不同：标记按 wasError 翻转或 error_at 晚于更换时间失效；令牌剩余 ≥ 24 小时写“N 天后”，跨天写 yyyy-MM-dd HH:mm；“（仍暂停调度）”只在开关关时写；bedrock / service_account 只读一行加“在 Web 中更换凭据”，脚注为自拟文案；刷新令牌回执不带按钮；Base URL 回执带“测试”不给撤销；刷新接口的 JSON 404 一律按已删除处理。files 之外的改动：Package.swift 加一行；新建 AccountCredentialPresentation、AccountTokenRefresher、DemoData+AccountCredentials；AccountEditUITests 两个撤销用例改为先点撤销（页面变长）；AccountDetailUITests 基础与调度用例改为固定顺序（既有随机顺序问题）。“重新授权…”行暂接占位，菜单项留给 S2-17。UI：check 跑了 6 个类，90/90 通过（审查修正 bd8a7da）审查修正 bd8a7da：凭据类三个要点回执按钮的 UI 用例改为 receiptButton + poll，从提交到点“测试”由 3.03 秒降到 0.91 秒；S6-26 gate 里 237 秒那次查明是 Mac 过载时 XCTest 空闲等待卡死（App 空闲，非 App 缺陷），已记待办；check ×3 全过。 |
| S2-17 | OAuthFlow 三步清单与重新授权 sheet（回调解析、本机回调监听、替换令牌与保存失败核对） | ✅ | `a5eed4c` | 一个提交，没拆 17a / 17b；新建变体（.create、updateProxy、begin / finish / failExchange、accessory、本机监听开关）已交付给 S2-19。错误落点和文案复用 S2-15：换码类 reason 落第 3 步，REAUTH_PERSIST_FAILED 没有 retry_within_seconds 时只给“重新授权”。超时沿用 30 秒，上游慢时会落到“不能确认是否已替换”。复制授权链接不加 .localOnly，到期等于链接剩余时间。影子账号、PAT、非令牌账号打开就只给“在 Web 中编辑”。AccountOAuthErrorCopy.unsupportedText 改为 public；夹具放 DemoData+AccountReauth.swift，并登记进 Package.swift 的 exclude。OAuthCallbackListener 未经真机验证：重新授权不开监听，首个开启方是 S2-19，回环双栈与端口被占时退回粘贴待真机确认。UI：AccountCredential / AccountDetail / AccountDetailMenu / AccountList 四类 71 个全过，无重跑。（审查修正 81bf48e）审查修正 81bf48e：手里有令牌或请求体时，“替换令牌”置灰并拒绝新提交，只能“重试保存 / 重试”，退路不会再拿用过的授权码重新换码；退路 apply 遇到安全提示并放行后，令牌保留，提示下给“重试”。读回不再传 previousRefreshedAt（与 S2D1-03 不同：sheet 打开时的快照不是发送前的值，期间后台刷新会被误判成已替换），只按本次发送时间判定。时钟偏差超过 2 秒时会落到“不能确认 / 重试保存”，重发是安全的。 |
| S2-19 | 新建账号表单：平台与认证方式、凭据（含 OAuth 三步）、名称、分组、调度、网络、更多，底部坞与创建 | ✅ | `c38ab7e` | 一个提交完成（未拆 19a / 19b）。本条为过渡：创建并停调度成功后关闭表单，回执“已创建「{name}」· 暂停调度”+“查看”，测试 sheet 留给 S2-20。与方案不同：坞工厂为 make(stage:missing:keyed:)，Action 加 .resend（无幂等能力的站点核对没找到时用）；缺项清单追加格式错误的地址；协议 / 端点 / Region / Location 用表单内菜单 Picker，端点只有官方与自定义（无 CN 预设）；Vertex 上限 64 KB（沿用 S2-18）；停调度没有确认时取消给“重试停止调度 / 仍然关闭 / 继续处理”，“仍然关闭”回执待用户确认；Gemini 无邮箱写“已授权”；夹具放新文件 DemoData+AccountNew.swift，混合渠道 409 抽成 mixedChannelConflict；OAuthFlowModel 新建 Gemini 账号的 tier 随授权类型变化。未做：“删除账号…”与测试 sheet（S2-20）；本机回调 / Safari / PasteButton / fileImporter 需真机验证。UI 测试未运行（UI_UNAVAILABLE），检查时 TOOLCHAIN_EXIT=3（Mac Xcode 已升到 27.2 / 27B52）；新增 AccountNewUITests 13 个从未在模拟器跑过，待环境修好后补跑 check AccountNewUITests,AccountListUITests,AccountCredentialUITests,AccountEditUITests,AppNavigationUITests（审查修正 1e0dfb6）审查修正 1e0dfb6：建号一律带 key（核实后端 2026-02 起就按 key 去重，推翻 S2-18 方案的前提）；结果未确认时取消改为“可能已经创建”三选一，不再按放弃处理；Session Token 改安全输入；Region / Location / 端点预设照 Web，端点预设只列同模式（Web 列出两种模式，点了会顺带切换账号类型）。UI 30 个中 27 个通过，另有 3 个是 S2-19 原有的失败，见 backlog。 |
| S2-20 | 新建账号：创建并测试 sheet、测试通过启用调度、失败处理（修改后重测、保留、保存为停用、删除）与后台继续 | ✅ | `3315d8b`（合并 `50c3095`） | 取舍：测试 sheet 在账号已存在后才打开，创建失败 / 结果不明仍由 S2-19 的坞处理；后台回执补“启用调度没有成功”“测试被中断”两种；只在测试进行中提供“后台继续”；通过但启用失败时“关闭”即收尾（暂停调度回执）；失败原文用 S2-13 的 errorText，没有加 lastErrorText。顺带修好 S2-19 遗留的 3 个 AccountNewUITests 失败：名称清空是测试 helper 点在词中间；sheet 回执画了两份，ReceiptCenter 加 sheet 宿主，只由最上层画；“更多”的标识盖住了内部各行。UI：check AccountNewUITests、AccountTestUITests、AccountListUITests 41/41 通过，无不稳定。（审查修正 d17380c）审查修正 d17380c：测试通过后（含启用没有成功）测试行不再提供换模型重测，AccountTestCenter 也拒绝重测，避免仍在调度的账号被说成“已停止调度”。这与 20 §7.3“结束后可点换模型重测”和设计稿 AnTest 不同：通过后要换模型，就点“查看账号”，在详情里测试。 |
| S2-22 | 账号列表组头告警牌与“告警”sheet | ✅ | `7e56d1c` | 按 S2D1-17 用 isListUsable + LiveOpsStore.firingAlerts(platform:)，列表失败、未读或运维关闭时不显示告警牌；刷新中带旧值照常显示（监控页按 10 §6.5 保留旧值，两处口径不同）。账号 Tab 可见时，AccountListModel 在完整 / 轻刷新的伴随请求里调 LiveOpsStore.refreshFiringAlerts()，与 10 §0.5 共用一份列表（20 审查记录第 7 条建议在 10 §0.5 补这句，规格没改）；完整刷新只在列表读取成功后才取告警。组头改为底层收起按钮加上层告警牌 / 全选按钮。按钮行复用 S1-12 的 AlertDetailActions（给 AlertStatusCard.swift 加了 identifierPrefix 参数），没有另建 actionTitle。“状态”行跨日写“明天 / M月d日”；“只看需处理的账号”只切胶囊；写失败时 sheet 不关，回执画在 sheet 上；夹具 #40 一开始就已静默，所以静默用例走“改静默时长”。check 跑了 AccountList / AccountBatch / AccountNew / AlertDetail：57/60，失败的 3 个 AccountNewUITests 在主分支 091294f 上同样失败，与本条无关（审查修正 b858763）审查修正 b858763：告警列表读取失败后，在下一次读成功之前不再显示告警牌（重读期间和重读被取消后都不显示）。判定依据是 LoadState.lastErrorAt，见新增的 NativeApp/Session/AccountAlertList.swift。 |
| S2-21 | 定时测试（只读）：计划与结果解码、详情记录区一行、定时测试小页 | ✅ | `707c96b` | 改了 files 外的文件：APIClient.decode 加 decode 段（S2D1-15）、AccountActivitySections.swift、Package.swift 排除表加一行；夹具另建 DemoData+ScheduledTests.swift（DemoData+Accounts 已 735 行）。取舍：cron 人话只在 N 落在分钟 1–59、小时 1–23 时生效，否则原样等宽；“其他”分类词写“上游 {code}”，无码写“失败”；model_id 为空写“默认模型”；vendor 结果被拒（403 FORBIDDEN）时写“没有权限查看测试结果”；小页只列主计划；invalidateReads 不取消定时测试读取。UI 测试已跑：check AccountDetailUITests 24/24 通过，无重跑后才通过的用例。（审查修正 0630966）审查修正 0630966：首次读取被切后台取消后，回前台也会重读定时测试行（readsAgainOnForeground：idle 或 failed 时重读）；小页失败改用 C-5 的 BlockFailureRow / BlockStatusAccessory（429 倒计时并自动重读、423 完成合规确认），状态行不显示“正在刷新”。check AccountDetailUITests 25/25 通过。推送因 GitHub 连接失败未完成。 |
| S2-23 | 阶段 2 收口：完成度核查、首页刷新接线、区块 429 统一、凭据与删除专项复核、ETag 304 确认、文档与小结 | ✅ | `a2d4b50` `abc70de` | 分两次提交（23a 代码与测试，23b 文档）。取舍：首页刷新收口在 AppModel+Accounts 的 11 个账号写包装（recordingAccountWrite + 新文件 Session/AccountWriteMark：成功或可能已生效且会话未变才记，4xx（408 除外）、本地校验、取消、needsNewKey 不记）与 AccountTestCenter.onFinished，没有接在 AccountPatchPrompts 的 convenience init（与依赖图裁定写的位置不同：PATCH / PUT 已经过写包装，onChange 在读回时也会触发；Session/AccountPatchFlow.swift 未改）；列表刷新沿用 S2-11 的 AccountListSignal，由详情 applyWrite、patch flow 的 onChange、测试结束 bump，AccountsView 被盖住时延后到再次出现；今日节没有数值时“读取失败 · 重试”，有数值时节头“更新失败”或 429 倒计时（S2-09 的“刷新失败 · 重试”不再使用），AccountDetailSectionBox 改用 NumberedSectionHeader；删除 APIClient.accounts(page:…)；G2 / G8 / G9 前序已做只核对，补了 G1 / G5 / G6 / G10 与两个空闲夹具的用例，HomeUITests 末尾加错误账号行进入活详情。改了 files 未列的 AppModel+Accounts、AccountTestCenter、AccountActivitySections、DemoData+Accounts、AccountsView（S2D1-24 允许）。ETag 304 未实测（测试环境地址只在主工作区未跟踪目录，线上不进主工作区）。UI：check 14 类 227 例 226 通过；唯一失败 AccountDetailMenuUITests.testSwitchingToNoProxy 在基线 6154134（MAC_REF，不含本条改动）上同样两次失败，属既有问题（审查修正 b66257b）审查修正 b66257b：S1-08 的 ResendAfterWait 改以 (notBefore, isOn) 作 task id，今日节 429 到时自动重读跟随详情页刷新门（sheet、确认框、写进行中、后台时不发，等待期内重新打开会等完剩余时间）；新增夹具 -ui-account-today-throttled-long 和两个 AccountDetailUITests 用例。check 3 个类 58/58 通过。 |
| U-06 | 账号列表 · 批量“停止调度”超过 50 个先确认数量，确认后才 Face ID | ✅ | `420583b` | stopConfirmation 的返回值由方案里的元组改为 Equatable 结构体 AccountBatchStopConfirmation，字段名不变；标题“停止 N 个账号的调度？”与按钮“停止调度 / 取消”是自拟文字，正文用清单原文；不设硬上限，“启用调度”和撤销不确认；新夹具 -ui-accounts-many（Anthropic 多 60 个）；check 通过：AccountBatchUITests 8/8，无重跑才通过的用例 |
| U-08 | 账号详情 · 错误状态牌无状态码时写“上游返回错误”；没有刷新令牌时“刷新令牌”置灰并注明 | ✅ | `0bc1091` | 无状态码时的原因抽成常量 AccountDetailPresentation.upstreamErrorCause；canRefresh 按 token_status.auto_refresh != false 判断，没有 token_status 的旧服务端照旧可刷新，OpenAI 个人访问令牌也会置灰并显示同一句脚注；脚注左缩进 34pt 对齐行标题（自拟版式，等截图确认）；“不会自动刷新”小字与“重新授权…”不变。check（0bc1091）：TOOLCHAIN、UNIT、BUILD 均为 0，无新 warning；UI 3 个类 63/63，无 flaky（审查修正 42a018f）审查修正 42a018f：OpenAI PAT 账号的 auto_refresh 恒为 false，但后端对 PAT 的刷新是一次能成功的校验，App 又不支持给 PAT 重新授权，所以 canRefresh 把 PAT 排除在外（与重新授权预检共用 UpstreamAccount.isOpenAIPersonalAccessToken），PAT 账号的“刷新令牌”照旧可用、不显示脚注。未改动的一类：OpenAI 非 PAT 账号没有刷新令牌但有访问令牌时，后端 /refresh 只是原样回存访问令牌，令牌并不会更新，这类账号仍按裁定置灰并注明。 |
| U-07 | 账号详情 · 模型分区对“按平台默认模型”的账号改空映射文案；高级 sheet 探测行在倍率同步开着时加“关闭后倍率同步也会关闭” | ✅ | `0d1de2f` | 按后端判定：Antigravity / Grok / DeepSeek / Gemini Google One / OpenAI OAuth（未开透传）空映射时写“按平台默认模型”，右上“平台默认”，sheet 脚注换新句；“平台默认”和新脚注是自拟文字。倍率同步提示放在开关正下方作独立元素（开关会把标签合成一个元素，放标签里 UI 测试取不到标识），按已存储状态显示。夹具改用 GLM-直连-01（#11），#4 被改倍率的用例占用。详情页只读行不加说明。check：AccountEditUITests + AccountListUITests 53/53 通过，无重跑 |
| U-04 | 账号列表 · 开关关着的“错误”账号右滑给“恢复状态…”；组头告警窗口“只看需处理的账号”同时筛到该平台并展开分区 | ✅ | `a00c523` | 凭据类错误也给“恢复状态…”，更换凭据仍走详情页；AccountRecoverDialog / accountRecoverDialog 的 actions 改为可选（与 contracts.md 不同，已有调用方不变）；先展开分区再一次读取 select(.needs, platform:)；恢复确认框打开时不暂停轻量刷新；UI：AccountListUITests、GroupMembersUITests、AccountDetailUITests 共 71 个全部通过 |
| U-09 | 定时测试 · 步长 1 写“每分钟 / 每小时”、失败行带耗时、“上游 {码}”只写一次、状态码正则与后端一致 | ✅ | `d34a8bb` | Outcome.failure 改为 (badge: String?, tone:, word:, latency: String?)，新增 failureDetail；兜底“上游 {码}”放进带状态色的码牌、耗时跟在牌后不加“·”（自拟版式，等截图再定）；状态码正则照后端 account_test_trace.go，\d/\s/\b 写成 ASCII 字符类以和 Go 一致，比 20 §0.1 宽（用户裁定 S2-中-36）；“每分钟 / 每小时”只有单元测试覆盖（演示数据没有步长 1 的计划）；check：AccountDetailUITests 28/28 通过 |
| U-05 | 账号测试连接：输出区补脱敏规则；Bedrock / Vertex 认证失败写“凭据无效或已撤销”；后台测试中断回执带账号名 | ✅ | `31beb17` | 脱敏新增 PEM 私钥、密钥键名后的值、JWT、AWS AKIA/ASIA、Google AIza 五类；顺序为 PEM、键值、带形状的令牌、Bearer/sk-/URL。键值规则只换掉值、保留原有分隔符与引号（方案模板“$1: [已隐藏]”会留下多余引号并改写“=”），转义 JSON 显示为 \"x-api-key\":\"[已隐藏]\"；键名边界不用 \b（汉字紧贴时 \b 匹配不到）；值前的“Bearer ”一并遮住，值遇到全角“，；。”停止；正则清单为自拟。已知局限：流式内容里跨多行的 PEM 只遮住 BEGIN 行。中断回执带「账号名」，窗口标题不变。check：AccountTestUITests、AccountNewUITests 共 25/25 通过，无 flaky |

### 阶段 2 小结

文中“材料”指上表各行备注、BACKLOG“App 与设计 · 阶段 2”、阶段 2 方案裁定，以及 S2-23 的方案、提交说明、检查日志和核查记录。下文引用的测试名都已在 `a2d4b50` 上只读核对存在（审查修正新增的两个用例在 `b66257b` 上核对）；注明“整理小结时只读补核”的是材料以外补查的结果。

#### (1) 完成项

- 数据层与读接口：S2-01 `9882ca6`（JSONValue；UpstreamAccount 补字段，credentials 解码时剔除 17 个敏感键并补 has_<key>，加 credentialsArrivedUnredacted 与 parentAccountID；AccountListQuery / managedAccounts）；S2-02 `9a0448b`（今日批量、运行时批量、5 小时窗口、带版本号的账号详情、MetaCatalog 与内置清单、平台显示名）。
- 账号列表：S2-03 `5eecbaa`（修正 `2437dab`）分区与刷新纯函数、AccountListModel、AppModel+Accounts 与演示夹具、Tab 徽标计数；S2-04 `75307e4` AccountRow 平台分区三行列表、筛选胶囊与平台菜单、Tab 徽标与跨 Tab 筛选，替换旧列表；S2-22 `7e56d1c`（修正 `b858763`）组头告警牌与“告警”sheet。
- 写接口与动作：S2-05 `11968da`（修正 `c4bcbf3`）PATCH + If-Match 与 PUT 退路、412 比对、混合渠道、恢复、调度开关带 key、删除、模型列表、恢复原代理；S2-06 `4d1c67c`（修正 `3d3987f`）AccountActions：恢复状态、启停调度、启用账号确认框、回执与撤销、结果核对、列表右滑；S2-07 `38013a7` 批量：选择模式、底部操作坞（停止 / 启用调度）、分批、Face ID、撤销与结果 sheet。
- 详情：S2-08 `afe1c74`（修正 `068203e`）骨架、状态卡与按钮行、加载 / 失败 / 已删除状态、路由替换；S2-09 `cfc6947` 容量（壹）、今日（贰）、记录（叁）三节与状态卡“最近上游错误”行；S2-21 `707c96b`（修正 `0630966`）定时测试（只读）：计划与结果解码、记录区一行、定时测试小页。
- 内联编辑：S2-10 `0732035`（修正 `968b677`）基础与调度分区、AccountSectionSheet、分组与过期时间选择器、AccountPatchFlow 保存流程（撤销、412、409、读回）；S2-11 `5d62dac`（修正 `9066c22`、`7319b0d`；后者在 2026-11-01，晚于 S2-23）代理分区与选择器、恢复原代理、⋯ 菜单、在 Web 中编辑、删除账号；S2-12 `f393974` `f679c34`（修正 `934d43b`）模型分区与映射编辑器、高级分区。
- 测试连接：S2-13 `43f7877` 接口层（SSE 读到 test_result、AccountTestResult、异步 test-runs、结果解读与输出脱敏）；S2-14 `986e7c9` 测试 sheet、后台测试任务 AccountTestCenter、.accountTest 路由。
- 凭据与 OAuth：S2-15 `c561924` 接口层（各平台授权链接与换码、reauthorize、apply-oauth-credentials、刷新令牌、OAuth 凭据构造与回执文案）；S2-16 `df6b264` 凭据分区（API Key / Base URL / 访问令牌行、更换 API Key 与 Base URL sheet、刷新令牌、凭据类主按钮）；S2-17 `a5eed4c`（修正 `81bf48e`）OAuthFlow 三步清单与重新授权 sheet（回调解析、本机回调监听、替换令牌与保存失败核对）。
- 新建账号：S2-18 `a2b7923`（修正 `c8cc174`）createAccount 与 AccountNewDraft（方式映射、缺项清单、凭据构造、自动命名、分组过滤）；S2-19 `c38ab7e`（修正 `1e0dfb6`）新建表单（平台与认证方式、凭据含 OAuth 三步、名称、分组、调度、网络、更多、底部坞）；S2-20 `3315d8b`（合并 `50c3095`，修正 `d17380c`）创建并测试 sheet、测试通过后启用调度、失败处理（修改后重测、保留、保存为停用、删除）与后台继续。
- 收口：S2-23 `a2d4b50`（23a 代码与测试）`abc70de`（23b 文档），审查修正 `b66257b`；合入主分支的合并提交 `6f473fd`、`51fa325`。做了这几块：
  - 首页刷新（X17、10 §1.4）：新文件 NativeApp/Session/AccountWriteMark.swift；AppModel+Accounts 的 11 个账号写包装（恢复状态、启停调度、PATCH、PUT 退路、批量调度、恢复原代理、删除、刷新令牌、重新授权、apply-oauth-credentials、新建）都套 recordingAccountWrite(generation)，写成功或可能已生效且会话未变时调 liveOps?.noteExternalWrite()；AccountTestCenter 加 onFinished，测试结束与新建账号后台流程结束时各调一次。
  - 列表完整刷新（20 §1.6）：AccountDetailModel.noteListNeedsRefresh() 在 applyWrite 末尾与 patch flow 的 onChange 里 bump S2-11 的 AccountListSignal；AccountsView 可见时立即刷新，被盖住时记下、再次出现时刷新一次。
  - 区块 429 统一（X37）：今日节删除自建状态行、TimelineView 与自动重发，没有数值时用 S1-08 的 BlockFailureRow（“读取失败 · 重试”），有数值时节头放 BlockStatusAccessory；AccountDetailSectionBox 改用 NumberedSectionHeader。审查修正 `b66257b` 让共用的 ResendAfterWait 以 (notBefore, isOn) 作 task id，今日节 429 到时自动重读跟随详情页刷新门（sheet、确认框、写进行中、后台时不发）。
  - 清理：删除 APIClient.accounts(page:search:status:platform:includeSchedulerScore:)，全 App 只剩 managedAccounts(page:query:)。
  - 专项锁定用例：AccountSecretHygieneTests、AccountBadgeWiringTests、AccountWriteMarkTests、AccountTestCenterFinishTests；新夹具 -ui-account-today-refresh-throttled、-ui-account-focus、-ui-account-today-throttled-long。
  - 文档：README“当前功能”与账号口径句、docs/ADMIN_MODULES.md 的“## 账号”、docs/NATIVE_CONTRACT.md 的账号签名。

#### (2) 规格测试清单 / 完成标志对照

20 章没有像 00 §9.8、10 §1.7、30 §10 那样单列测试清单；“实现顺序建议”的阶段 2 段只写了实现顺序，没有完成标志（阶段 0、1 有）。下面按 S2-23 条目 refs 列的对照项写。

- U15–U23 与 U53：S2-23 核查记录为“都已实现并有单测或 UI 用例”，逐项内容：U15（500 一页、最多 2,000 行、超出提示用平台筛选）、U16（OAuth 令牌只在内存）、U17（Bedrock / Vertex 主按钮“在 Web 中更换凭据”）、U18（不发 skip_default_group_bind，表单脚注写明）、U19（不发 preserve_status，确认文案写“并重新启用账号”）、U20（定时测试只读一行）、U21（批量只有停止 / 启用调度）、U22（运维关闭时“出错于 …”行）、U23（代理行推入代理详情）、U53（过期时间按本机时区）。材料只给了 U17 的测试名 AccountDetailMenuUITests.testBedrockCredentialErrorOpensWeb，其余各项的测试名材料里没有逐项列出（未核对）。
- R 系列：
  - R08：不实现 AccountListPage.etag，304 由 ConditionalCache 透明处理；单测 ConditionalRequestTests.accountListPageKeepsCountsOn304AndLaterPagesOmitCounts。
  - R09（include_counts 只在第 1 页）：AccountListLayoutTests.listQuerySendsNewParametersOnlyWithListQueryCapability 断言第 2 页不带 include_counts（整理小结时只读补核，`a2d4b50`）。
  - R19：唯一定义见 (5)。
  - R05、R12：S2-23 未逐条核对；前序依据见 S2D1-05（PUT 退路与各写包装在用户确认那一刻生成 key，R05）、阶段 0 表的 S0-17 行⑤（按 R12 任何情况都不显示 error_message）。
  - R06、R11：材料里没有 S2-23 的逐条核对结果（未核对）。
- 阶段 0 留给阶段 2 的三项（S0-05 / S0-07 / S0-08）：见 (4)。
- 20 §1.7 唯一写到 UI 测试的一行（AccountListCustomizationUITests、AccountManagementUITests 按新列表重写，DemoData 补 11 个演示账号）：S2-04 把这两个文件都删除，改为 AccountListUITests；“11 个演示账号”未核对。
- 10 §1.4 账号写后首页刷新：AccountWriteMarkTests（mayHaveAppliedSeparatesSentFromUnsent、runMarksOnceAfterSuccessOrMaybeAppliedFailureInSameSession）、AccountTestCenterFinishTests（finishedTestsCallOnFinishedOnceUnlessSessionChanged、newAccountRunCallsOnFinishedAfterItsBackgroundSwitch、cancelAllCallsNoOnFinished）；没有 UI 层断言（见 (7)）。
- 区块 429（X37）：AccountDetailSectionsTests.todayFailureRowUsesSharedBlockWording；AccountDetailUITests.testTodayRefreshThrottleKeepsFiguresWithHeaderCountdown、testTodayThrottleResendWaitsWhileSheetCoversPage、testTodayThrottleResendGoesOutOnceSheetClosesWithinWait。
- 路由 focus（X39）：AccountDetailUITests.testRouteFocusScrollsToEachSection（夹具 -ui-account-focus，六个分区）。
- 凭据专项：AccountSecretHygieneTests 的 accountTextFormsNeverCarrySecrets、patchRequestAndItsHoldersPrintKeyNamesOnly、putFallbackTouchesOnlyTheTargetKeyAndNeverEchoesSecrets。
- 账号 Tab 徽标：AccountBadgeWiringTests 的 liveOpsHomeWritesSharedBadgeInDeviceTime、refresherSkipsFetchWithinSixtySecondsAfterLiveOps。
- 本阶段裁定的锁定用例：
  - S2D1-02：SuspendTests.suspendKeepsAnOpenAccountTestStream；
  - S2D1-07：AccountEditDraftTests.groupChangeKeepsOrderAndUndoRestoresOriginalOrder；
  - S2D1-11：listQuerySendsNewParametersOnlyWithListQueryCapability；
  - S2D1-12：AccountNamingTests.accountNamingPlatformNames；
  - S2D1-01：AccountTestUITests.testModelListFailureUsesServerDefaultModel；
  - 内置平台清单：MetaCatalogTests.builtinCatalogMatchesSub2BuiltinJSON。
- S2-23 新增的其余 UI 用例：AccountEditUITests.testRenameInDetailShowsNewNameInListAfterBack；AccountListUITests.testReadOnlyTokenGreysNewAccountButton、testEmptySiteShowsEmptyCard、testSummaryFailureKeepsRowsSilently；HomeUITests.testErrorAccountRowOpensLiveAccountDetail。

#### (3) 20 章各节改动点

- §1.7 列表：
  - AccountsView 重写为平台分区三行列表，数据与定时器在 Features/Accounts/AccountListModel（S2-03 / S2-04），行在 AccountRow（S2-04）；“显示字段”“前台自动刷新”“快捷编辑”已删（S2-23 核查）；“筛选与排序”也已删（整理小结时只读补核，`a2d4b50` 的 Sources / NativeApp / Tests / UITests 里 grep 为 0）。
  - AccountListQuery / managedAccounts：page_size 500、多值 status、urgency 排序、include_counts 只在第 1 页、supportsListQuery 能力标记（S2-01、S2D1-11）。ETag 不进 AccountListPage，304 交给 ConditionalCache（R08）。
  - accountTodayStats 改为今日批量（含 failed_account_ids），另加运行时批量（S2-02）；旧 accountTodayStats(ids:) 由 S2-04 删除。AccountStatusSummary 与 AccountDisplayState 由 S0-17 提供。
  - AdminGroup 的 sortOrder 与 allGroups(includeInactive:)：S2-01，带 platform 时本地过滤。
  - Tab 徽标：S2-03 / S2-04，会话级 accountBadgeTask 前台每 60 秒补取，没有 status_summary 时退回 dashboard/stats.error_accounts。
  - 告警 sheet 与组头告警牌：S2-22，经 LiveOpsStore.refreshFiringAlerts() 与 10 §0.5 共用一份列表。
  - AccountFieldPresentation、ListFieldSelection、ListFieldEditor 按 20 §1.7 留给简化模式。
  - 旧 UI 测试 AccountListCustomizationUITests、AccountManagementUITests 都已由 S2-04 删除，改为 AccountListUITests。
- §2.7 详情：AccountDetailScreen（S2-08）；容量 / 今日 / 记录三节（S2-09）；带 ETag 的账号读取、AccountUsageWindow（S2-02）。日志页打开账号详情、分组页“查看与管理分组账号”入口在 S2-23 时仍是过渡，见 (7)。
- §3.7 内联编辑：
  - 旧 AccountEditView 拆为 AccountSectionSheet 的基础 / 调度 / 模型 / 高级四种分区（S2-10 / S2-12）。
  - AccountPatchRequest、patchAccount、PUT 退路、AccountMixedChannel、deleteAccount、accountModels、revertAccountProxyFallback：S2-05；JSONValue：S2-01。
  - 四个选择器：分组与过期时间（S2-10）、代理（S2-11）、模型（S2-12）。
  - Proxies.swift 首建与 allProxies(withCount:)：S2-11。代理行推入代理详情（S2-11），代理详情页由 S6-12 提供。
  - 保存编排 AccountPatchFlow 放在 NativeApp/Session，弹框在 Features/Accounts/AccountPatchPrompts（S2D1-04）。
- §4.7 测试连接：SSE 以 test_result 或 EOF 结束、AccountTestRuns、输出脱敏（转录拆到 AccountTestTranscript）：S2-13。AccountTestSheet 与后台任务 AccountTestCenter：S2-14，AccountTestCenter 在 NativeApp/Session，AppModel 持有 accountTests。
- §5.7：setSchedulable 带 key、AccountRecovery：S2-05。AccountActions 本体在 Session/AccountActionsCore.swift、App 入口在 Features/Accounts/AccountActions.swift：S2-06。
- §6.7：AccountOAuth，另拆出 OAuthCredentialBuilder、AccountOAuthErrorCopy（S2-15）；AccountCredentialSheets（S2-16）；OAuthFlow（S2-17）。旧 refreshAccount(id:) / refreshManagedAccount 已由 S2-15 删除，新的刷新令牌带 key。
- §7.7 新建账号：
  - AccountNewView 与坞：S2-19；AccountNewDraft、AccountCreate：S2-18；MetaCatalog 与内置清单：S2-02，并入 MetaCatalog.swift；复用 S2-17 交付的 OAuthFlow 新建变体。
  - 状态机按 S2D1-13 拆分：创建 / 停调度阶段在 S2-19 的 AccountNewSubmission，测试 / 启用阶段在 S2-20 的 AccountNewTestRun，AccountNewFlow 只剩纯函数。
- §8.7 批量：AccountBatchDock 与 AccountBatchRunner，bulk-update 带 key，去掉“确认执行”，批量“刷新凭据”删除（S2-07，U21）；§8.8 未做。
- §9.7：ScheduledTests、AccountScheduledTestsView（S2-21）。APIClient.decode 加了裸数组分支（S2D1-15）。
- §10.3：AccountStatusSummary（S0-17）、AccountsRanking（S1-01）。

#### (4) BACKLOG 与前序阶段备注里留给本阶段的事项

- 阶段 0：
  - S0-05（账号详情 cv-N 不进缓存；account(id:) 返回 ETag 的变体与 PATCH If-Match）：已满足。带版本号的详情 S2-02，PATCH + If-Match S2-05；锁定用例 AccountReadBatchTests.versionedAccountReadsETagAndNeverSendsIfNoneMatch。
  - S0-07（ServerClock 的消费）：已满足。S2-03 的状态推导用站点时钟，节流与徽标用本机时钟；S2-23 核查确认账号页时间用 ServerClock。
  - S0-08（绝对时间按服务器时区）：S2-23 核查为已满足。例外有两处：简化模式用的 ListFieldPresentation.timestamp；过期时间按 U53 用本机时区。
  - S0-08 / BACKLOG“倍率的显示位数”：账号一侧定为 DisplayFormat.decimal，最多 3 位小数（S2-10 的 AccountEditCopy.rate），BACKLOG 该行已由 S2-23 更新；App 不显示上游探测倍率；分组页归阶段 5。
  - S0-17（AccountTokenStatus 的显示归阶段 2）：S2-16 的访问令牌行。
  - S0-02 留给页面的动作：412“已刷新”由 S2-05 / S2-10 的 412 比对与重新载入做；TOO_MANY_IDS 拆批由 S2-02 的 runtime/batch 再拆做。ACCOUNT_STATS_UNAVAILABLE 显示“—”、“服务器连不上 {平台}”填平台这两项，材料里没有单独记录。
  - S0-19 / S0-LOW-B / BACKLOG“UI 测试 6 并发下的快照停顿”（旧账号列表字段编辑用例、testSlowTodayStatsAllowsIndependentRuntimeRefresh）：已处理。S2-04 删除 AccountListCustomizationUITests（含 5 个基线不稳定用例），整体换成 AccountListUITests。
- BACKLOG 通用行里账号部分的事项：
  - “区块 429 倒计时文案与重试按钮”：已处理。S2-09 先做了自建倒计时，S2-23 换成 BlockFailureRow / BlockStatusAccessory，b66257b 补了刷新门；定时测试小页在 S2-21 修正时已改；账号列表的今日金额只显示“—”（20 §1.5）。
  - “读区块的完成合规确认入口”：账号详情今日节经 BlockFailureRow 也有了（S2-23）。
  - “缺失值“—”的读屏”：S2-09 处理了详情三节；S2-23 grep 核对，阶段 2 账号页的读屏值都经 DisplayFormat.spoken / spokenValue / missingSpoken。
  - “路由参数在旧页面上不生效”（.account 的 focus）：六个分区都能滚到，由 testRouteFocusScrollsToEachSection 锁定。
  - “跨 Tab 跳转撤不掉视图式推入的页面”：账号 Tab 栈上一律 NavigationLink(value: AppRoute) 或 router.push。白名单只有两类：sheet 内自带导航栈的推入；分组过渡入口 AccountsView(initialGroupID:)，S5-13 删除。
  - “通用删除确认还没有做”：账号删除（详情、新建失败后删除）只经 DeleteRequest.account + .confirmDelete（S2-23 核查）。
  - “真机确认 ETag 304”（账号列表的 304 由 S2-23 确认）：未实测，原因见 (7)。
- 阶段 1：
  - S1-18 移交 S2-23、BACKLOG“概览「测试」关闭即刷新与后台测试”：已处理。测试结束（含后台测试、新建账号后台启用调度）经 AccountTestCenter.onFinished 通知概览与列表。
  - 阶段 1 小结 (6)、BACKLOG“渠道行状态图标与账号状态图标统一”（留给 S2-23 评估）：材料里没有评估结论。整理小结时只读补核（`a2d4b50`，主分支 `1e28cbc` 上相同）：ChannelGlyph 仍是 ChannelsSection.swift 的私有类型。
  - BACKLOG“S2-09 的 CapacityBar 合入后统一监控 CPU / 内存条”：材料里没有处理记录。整理小结时只读补核（`a2d4b50`，主分支 `1e28cbc` 上相同）：MonitorServerSection.swift 仍用私有 MeterBar。
  - BACKLOG“首页夹具与账号 Tab 演示数据不一致”：S2-23 加了 HomeUITests.testErrorAccountRowOpensLiveAccountDetail（错误账号行进入的是活账号详情）；其他差异材料里没有新记录。
  - BACKLOG“概览待处理账号行是否复用 AccountActions”：默认不做（S2-23 方案 out_of_scope）。
  - BACKLOG“AccountOAuthTests 计时用例在高负载下偶发失败”（S2-15 的用例）：阶段 2 内没有处理。后来 S5-02 合入时由 `b840ad9`（2026-11-01）改为不依赖耗时。
- BACKLOG 阶段 2 表里交给 S2-23 的：
  - “旧接口 APIClient.accounts(page:…)”：已删除，测试改调 managedAccounts。
  - “S2-23 首页刷新接入点”（AccountBatchRunner）：批量调度经 setAccountsSchedulable 包装，已在 11 个写包装里，没有改 AccountBatchRunner。
  - “详情里写操作后返回列表的即时刷新”“其余详情写操作的列表完整刷新”：已处理，用例 AccountEditUITests.testRenameInDetailShowsNewNameInListAfterBack。
  - “区块 429 倒计时（账号详情今日已处理）”：见上。
  - “ConditionalCache 缓存账号列表原始响应体”（由 S2-23 的凭据专项复核决定）：材料里没有结论，BACKLOG 该行没更新。
  - “跨 Tab 跳转关闭新建表单”（留给 S2-23 或用户决定）：S2-23 不加询问，等用户决定。
  - “新建账号遇到 503 IDEMPOTENCY_STORE_UNAVAILABLE”（S2-20 / S2-23 可统一处理）：材料里没有处理记录。
- BACKLOG 阶段 2 表里前序条目自己的遗留：
  - “S2-19 新建账号三个 UI 用例原有失败”“AccountNewUITests 三个用例在主分支上稳定失败”：已由 S2-20 修好，S2-23 的 check 里 AccountNewUITests 没有失败；这两行 BACKLOG 没标已处理。
  - “AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues 不稳定”：S2-16 改为固定顺序遍历。

#### (5) 核查结果（S2-23 一次性脚本，不入库）

- 改动总表 20 章各行：
  - 列出的新文件全部存在：AccountDisplayState、AccountMixedChannel、AccountRecovery、AccountRuntimeBatch、AccountStatusSummary、AccountTestRuns、AccountUsageWindow、AccountsRanking、JSONValue、MetaCatalog、Proxies、ScheduledTests、AccountCreate、AccountOAuth，以及 Features/Accounts 下 16 个页面文件。
  - 已删：AccountEditView、旧批量、“显示字段”“前台自动刷新”“快捷编辑”。
  - 保留：AccountFieldPresentation / ListFieldSelection / ListFieldEditor 留给简化模式；AccountsView(initialGroupID:) 留给分组过渡入口。
- 旧符号在 Sources / NativeApp / Tests / UITests / scripts 里为 0：accounts(page:…)、accountTodayStats(ids:)、旧 setSchedulable / refreshAccount、refreshManagedAccount、AccountUpdateRequest、PendingAccountUpdate、updateAccount、AccountEditView、LegacyAccountDetailView、AccountTestView、prepareBatch / executeBatch / AccountBatchAction、accounts.more、batch-refresh、batch-clear-error、create-from-oauth。docs/NATIVE_CONTRACT.md 由 23b 更正。skip_default_group_bind、preserve_status 只出现在“从不发送”的注释与断言里。
- R19：managedAccounts、AccountListQuery、accountStatusSummary、alertEvents、errorCount、allProxies、AdminProxy 各一处定义；errorRecords 的两处是 page / sinceID 两个接口（阶段 4 文件），不算重复。
- X39：账号页 Tab 栈上一律 NavigationLink(value: AppRoute) 或 router.push；白名单只有 sheet 内导航栈（AccountNewView、AccountSectionSheet）与分组过渡入口的 navigationDestination(item:)。
- 行数：账号相关源码与测试文件都不超过 800 行（DemoData+Accounts 753、AccountTestCenterTests 785）。`b66257b` 后 DemoData+Accounts 为 756 行（整理小结时用 git show 只读补核）。
- D27：UITests 引用的 301 个账号标识在 NativeApp 都能找到；-ui-account* / -ui-accounts* / -ui-scheduled-tests* 参数两边一一对应。此前没有用例的 -ui-accounts-empty、-ui-accounts-summary-error 由 S2-23 补了用例。
- 安全：
  - 账号文件里没有 print / dump / NSLog；Logger 两处只记方法、路径模板、状态码、reason、请求 ID。
  - Receipt / APIError / Text / Logger 行上的插值逐条核对 31 处，没有凭据。
  - 没有 @AppStorage / UserDefaults 存凭据；UIPasteboard 只在 SensitivePasteboard、OAuthFlow 带过期的链接复制与错误详情。
  - 删除只经 DeleteRequest.account + .confirmDelete。更换 Key 与重新授权在提交前过 BiometricGate.authorize(.replaceCredential)，批量过 .batch。
  - 前序已做、本条只核对的三项：敏感键清单只有一份（G8，S2-05）；AccountPatchRequest / JSONPatchValue / AccountEditChange / AccountPatchAttempt 屏蔽了文本形式（G9，S2-05 / S2-10）；INVALID_ACCOUNT_STATUS_FILTER 退路（G2，S2-03）。
- 能力与格式：账号代码里没有能力字面量；倍率经 DisplayFormat.decimal；读屏值里的“—”经 DisplayFormat.spoken；TimeZone.current 只在过期时间脚注。
- 写包装：AppModel+Accounts 里有 16 个发写请求的包装。11 个账号写套了 recordingAccountWrite；其余 5 个里，checkMixedChannel、generateOAuthLink、exchangeOAuthCode 不改账号，testAccountStream、startAccountTestRun 由 AccountTestCenter.onFinished 收尾。
- 交叉审查新增的七项核对（S2-23 方案 cross_review_notes 第 3 条）：
  - ① 旧服务端凭据 PUT 拦截有单测与 UI 用例（S2D1-09）：整理小结时只读补核（`a2d4b50`），LEGACY_CREDENTIALS_PUT 有 AccountPatchTests、AccountPatchStepTests、AccountPatchFlowTests 等单测，夹具 -ui-account-legacy-server 在 AccountCredentialUITests、AccountEditUITests 里有用例。
  - ② D18 修订在 SuspendTests 体现（S2D1-02）：见 (2) 的 SuspendTests.suspendKeepsAnOpenAccountTestStream。
  - ③ “Zhipu GLM”只出现在 MetaCatalog.builtin 数据里（S2D1-12）：整理小结时只读补核（`a2d4b50`），字面出现在内置清单数据、一处测试断言（MetaCatalogTests）和三处注释（AccountNaming、PlatformQuotaPresentation、AccountNamingTests）里，NativeApp 里没有。
  - ④ 分组过渡入口的视图式推入列入 X39 白名单（S2D1-18）：S2-23 核查有结论，见上面的 X39。
  - ⑤ 阶段 2 的 -ui-* 参数全部在 DemoData.AccountFixture（S2D1-14）：未核对。上面 D27 的“两边一一对应”核的是 UITests 与 NativeApp 之间的参数，不是这一项。
  - ⑥ 到期暂停主按钮为“修改过期时间…”（S2D1-20）：整理小结时只读补核（`a2d4b50`），editExpiry 有 AccountDetailPresentationTests 与 AccountEditUITests 覆盖。
  - ⑦ 影子账号预检（S2D1-21）：整理小结时只读补核（`a2d4b50`），Sources/Sub2Core/OAuthFlowPresentation.swift:105 在 parentAccountID 有值时直接返回不支持文案（shadow_account），单测 OAuthFlowPresentationTests.precheckFailureAndUnconfirmedCopy 断言“影子账号的凭据跟随母账号，请重新授权母账号”。

#### (6) 与规格不同的取舍（阶段汇总，各条目的细项见上表备注）

- 平台显示名：App 已知的平台用内置中文名（zhipu 显示“智谱 GLM”），与 20 §0.3 字面“目录 display_name 优先”不同（S2D1-12，S2-02 / S2-04 / S2-18），待用户确认。
- 到期自动暂停的账号：详情主按钮为“修改过期时间…”，打开调度分区；列表右滑不给“启用调度”。与 20 §2.3 字面不同（S2D1-20，S2-06 / S2-08 / S2-10），待用户拍板。
- 过期时间按本机时区（U53），20 §3.3 的服务器时区作废；脚注只在过期页、且时区偏移不同时出现（S2-10）。
- 列表 ETag 不进 AccountListPage，304 由 ConditionalCache 透明处理（R08）。
- 测试连接：
  - 默认模型不建内置表，发空 model_id、显示“默认模型”（S2D1-01，20 §4.5）。
  - 输出区多出上游错误“✕ …”和媒体“← 收到…”两类行（20 §4.3 只列 content / status）。
  - 测试流不随 suspend 停止（修订 D18，S2D1-02）。
  - “重新测试”只在中断、没开始和 BUSY 时出现，BUSY 默认等 30 秒（S2-14）。
- 列表：
  - S2-04：正常账号不画状态牌（照设计稿）；暂停 / 停用只把名称改为 ink2，不降整行透明度；限时第 3 行“只截尾部”（条目正文写的“只截头部”按笔误处理）；平台菜单的数字放在菜单项第二行。
  - S2-03：分组排序与主分组沿用 AdminGroup.displayOrder（sort_order 缺失按 0，方案原为排最后）；平台同级时按 id 升序。
  - 状态筛选被拒时，本会话退回旧服务端路径；分组筛选被拒不重试（S2D1-11，S2-03）。
- 写：
  - 2026-05 以前的旧站点上，凭据类 PUT 本地拦截，提示去 Web（S2D1-09，S2-05 / S2-10）。
  - ReasonCatalog 没补 CREDENTIAL_KEY_NOT_DELETABLE 等 3 个 reason，走通用兜底（S2-05）。
  - AccountActions.enableAccount 保留自己的单字段 PATCH，不并入 AccountPatchFlow，两者共用 S2-05 的 412 比对（S2-23 核查）。
- 批量（S2-07）：部分失败的回执只给“查看”，撤销移到结果 sheet 底部；撤销只针对操作前与目标值不同的成功账号；前一批没有明确成功就停止。批量“刷新凭据”删除，§8.8 不做（U21）。
- 详情：
  - S2-08：错误态牌旁写“上游 {error_status_code}”；按钮按设计稿做成横排胶囊，不用 glass；安静卡也画模型限流块。
  - S2-11：删除回执在确认框关闭前出现、关闭后再 pop；删除遇到“需再次确认”只回执、不给重试；停用代理的副行写到期词。
- 模型 / 高级（S2-12）：模型限流徽章按映射后的实际模型匹配；自动探测上游声明倍率只给 apikey 账号；透传读法同后端，关闭时连旧键 openai_oauth_passthrough 一起删；限额关闭只删主键；基础 RPM 由 App 校验 1–10000；切换账号类型 / API 协议时照 Web 联动官方端点，自定义端点时两行只读并加脚注。
- 凭据：
  - 多协议平台的 Base URL 只读，走 Web（S2D1-22，S2-16）。
  - S2-16：标记按 wasError 翻转或 error_at 晚于更换时间失效；令牌剩余 ≥ 24 小时写“N 天后”，跨天写 yyyy-MM-dd HH:mm；“（仍暂停调度）”只在开关关时写；bedrock / service_account 只读一行加“在 Web 中更换凭据”，脚注为自拟文案；Base URL 回执带“测试”、不给撤销（20 §0.4-1 写可逆的内联编辑给撤销）；刷新令牌回执不带按钮；刷新接口的 JSON 404 一律按已删除处理。
  - 重新授权的读回不再传 previousRefreshedAt，只按本次发送时间判定，与 S2D1-03 不同（S2-17 修正 81bf48e）。
  - 重新授权、换码、apply 保持 30 秒超时（S2D1-03）。
- 新建：
  - S2-18 曾只在有 admin.idempotent_writes 时带 key（与 00 §2.5.1 不同），S2-19 修正 `1e0dfb6` 改回一律带，现在与规格一致。
  - 测试 sheet 只在账号已存在后打开，20 §7.5 写的是创建失败也打开（S2-20）。
  - 测试通过后不再换模型重测，与 20 §7.3 和设计稿 AnTest 不同（S2-20 修正 d17380c）。
- 告警牌（S2-22）：列表失败、未读或运维关闭时不显示；刷新中带旧值照常显示（监控页按 10 §6.5 保留旧值，两处口径不同）。
- 定时测试（S2-21）：cron 人话只在分钟 1–59、小时 1–23 时生效；vendor 被拒写“没有权限查看测试结果”；小页只列主计划。
- 收口（S2-23）：
  - 首页刷新收口在 11 个写包装与 AccountTestCenter.onFinished，没有接在依赖图裁定写的 AccountPatchPrompts convenience init；可能已生效的失败也记一次。
  - 列表完整刷新只由详情写与测试结束触发，列表被盖住时延后到再次出现。
  - 今日节有数值时失败写节头“更新失败”（00 §4.6），S2-09 的“刷新失败 · 重试”退役。
  - 跨 Tab 跳转直接关掉新建表单，不询问。

#### (7) 未做项及原因

- 批量“恢复状态 / 刷新令牌”（20 §8.8，U21）：默认不做，等用户看过效果图再定。
- 测试环境 ETag 304 未实测：测试环境地址只在主工作区的未跟踪目录里，线上实现者不进入主工作区，而且测试环境与生产同机。按后端源码核对：命中时返回 304、没有响应体，带 ETag 与 Vary: If-None-Match；ETag 覆盖运行时采样，有流量的站点大多会重新下发。URLSession 层仍只有桩测试。
- 需要真机验证、未做：
  - OAuthCallbackListener：回环双栈、端口被占时退回粘贴、是否需要 NSLocalNetworkUsageDescription（S2-17；重新授权不开监听，首个开启方是 S2-19）；
  - 本机回调 / Safari / PasteButton / fileImporter（S2-19）；
  - 更换 API Key 输入框会不会弹“存储密码”（S2-16）；
  - 真机 Face ID；
  - 账号详情的下拉刷新：UI 测试里拉不出，S2-23 的有旧值 429 用例改用回到前台触发。
- 概览“下次可见时绕过缓存”没有 UI 层断言：UI 夹具 FixtureLiveOpsSource 不区分 nocache，只靠单测与静态核查。
- 保存遇到 GROUP_NOT_FOUND 时刷新分组目录（S2-10）：分区 sheet 遇到 404 GROUP_NOT_FOUND 不进已删除页，但没有自动刷新分组目录，分组页要等下次刷新才去掉已删除的分组（BACKLOG 阶段 2 表同名行）。
- 同步上游模型（POST :id/models/sync-upstream）：不在规格内，S2-12 方案写明不做。
- 待实测：账号列表超过 2000 行时是否按平台分区懒加载（U15，S2-03）；定时测试状态码正则是否放宽到和后端一致（S2-21）。BACKLOG 这两行都写明实测后再定，已列入本节末尾的待拍板事项。
- 待定：LoadState 重读被取消后恢复成 loaded，“更新失败”标记随之丢失（S2-22 的组头告警牌已改用 lastErrorAt 绕开，BlockState / LoadState 的共用语义需要另外决定）；复制授权链接不加 .localOnly，会经通用剪贴板同步到其他设备（S2-17，以后需要收紧时再定）。
- vendor 工作区（U01，首版拒绝）。
- 留给简化模式或后续阶段：docs/API_COMPATIBILITY.md 的账号字段说明（讲的是旧列表字段）；AccountFieldPresentation / ListFieldSelection / ListFieldEditor；ListFieldPresentation.timestamp 仍按设备时区。
- S2-23 时的过渡期缺口：
  - 记录区“使用记录 / 上游错误”与“最近上游错误”的请求详情仍由旧日志页承接（S4-05 / S4-08 前）；
  - 分组页“查看与管理分组账号”与过渡入口的行仍是视图式推入（S5-06 / S5-13）；
  - 搜索 Tab 的账号结果在 S6-20 / S6-21；
  - 概览待处理账号行不复用 AccountActions（dag 第 8 节）；
  - 概览与分组页的平台名仍用 GroupPlatform.title。
  - 代理行推入的代理详情此时已由 S6-12 接上。
- 后端事项（只记 BACKLOG，不改后端）：
  - Claude / Gemini / Antigravity 换码时网络失败不带 reason（S2-15）；
  - 定时测试接口没有 {code,data} 信封，vendor 读不到结果（S2-21）；
  - 换认证方式或改 type 后，旧敏感凭据键留在服务端（S2-18 / S2-20）；
  - SPARK_SHADOW_NO_REFRESH 没进错误码文档（S2-16）；
  - 再次 DELETE 已删账号不返回 ACCOUNT_NOT_FOUND。
- BACKLOG 交给 S2-23、但材料里没有处理记录的两项：ConditionalCache 是否对账号列表的缓存体脱敏或不缓存；新建账号遇到 503 IDEMPOTENCY_STORE_UNAVAILABLE 时没有按 retryNotBefore 延后。
- 需要用户拍板的事项按默认值实现，连同下面两组共 36 条：
  - _decisions-S2 末尾七条：平台显示名、到期暂停账号的主按钮、测试默认模型、测试输出区多出的行、老服务端凭据编辑去 Web、多协议 Base URL 只读、重新授权 30 秒超时。
  - 其余 29 条等用户看效果图、决定、实测或真机确认，出处在 BACKLOG 阶段 2 表、上表备注和本节上文：错误账号的列表右滑、账号行暂停 / 停用的降色方式、平台菜单的平台个数位置、账号详情错误态牌旁的原因、停用代理副行写法、批量调度“稍后核对”、批量选择数量是否设上限、批量“恢复状态 / 刷新令牌”（U21）、Bedrock / Vertex 账号 401 的失败原因文案、中断回执是否带账号名、ACCOUNT_TEST_BUSY 的按钮倒计时文案、模型分区空映射的文案、多协议账号切换账号类型 / API 协议时联动接入端点、倍率同步开启时探测行的提示、无刷新令牌时的“刷新令牌”行、bedrock / service_account 凭据区文案、新建账号多协议端点预设表、新建账号停调度没有确认时“仍然关闭”、创建失败时是否也打开测试 sheet、跨 Tab 跳转关闭新建表单、告警 sheet“只看需处理的账号”是否同时展开或筛到该平台、10 §0.5 补一句“账号 Tab 也会刷新告警列表”、vendor 读定时测试结果、定时测试“每 1 分钟”写法与失败行耗时、概览与分组页的平台名（交 S5-13）、测试环境确认 ETag 304、只能真机确认的几项（本机回调监听、Safari 跳回、粘贴按钮与文件导入、“存储密码”弹窗、Face ID、账号详情下拉刷新）、账号列表超过 2000 行时按平台懒加载（U15）、定时测试状态码正则是否放宽。

#### (8) UI 测试运行情况

- 各条目的 check（按上表各行）：
  - S2-01：AccountManagement / AccountListCustomization / Sub2Mobile / AppNavigation 四类 38/38。
  - S2-02、S2-18：UI 测试未运行（S2-02 只跑单元与编译；S2-18 没有 ui_test_classes、未改界面）。
  - S2-03：AppNavigationUITests、Sub2MobileUITests 39/39。
  - S2-04：5 类 55/55，无重跑。删除的 AccountListCustomizationUITests 含 5 个基线不稳定用例，从基线名单中去掉，改跑 AccountListUITests（12 个）。
  - S2-05：AccountListUITests 12/12。
  - S2-06：AccountListUITests、Sub2MobileUITests 38/38。
  - S2-07：AccountBatchUITests、AccountListUITests 23/23。
  - S2-08：六类 60/60；审查修正 068203e 后 4 类 41 例全过。
  - S2-09：AccountDetailUITests、RequestLogsUITests、AccountListUITests 35/35，无重跑。
  - S2-10：AccountEditUITests、AccountDetailUITests、AccountListUITests 49/49。
  - S2-11：4 个 UI 类 64/64。审查修正 7319b0d 后 AccountDetailMenuUITests 连跑 3 次 check 全过（94/94、17/17、17/17，无 FLAKY）；改到一半的一次连跑里，testPickingProxySavesThenUndoRestores 重跑后才通过。
  - S2-12：f393974 的 check 4 个类 73/74，失败的是 S2-11 的 testPickingProxySavesThenUndoRestores（回执 4.2 秒内来不及点撤销）；f679c34 调整等待顺序后，AccountEditUITests、AccountDetailMenuUITests 38/38。
  - S2-13：Sub2MobileUITests、AccountDetailUITests 28/28。
  - S2-14：5 类 86 个中 85 个通过。AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues 两次失败（字典遍历顺序随机，既有不稳定），单独重跑 AccountDetailUITests 20/20；S2-16 把它改为固定顺序。
  - S2-15：AccountDetailUITests 20/20。
  - S2-16：6 个类 90/90。
  - S2-17：AccountCredential / AccountDetail / AccountDetailMenu / AccountList 四类 71/71，无重跑。
  - S2-19：UI 测试未运行（UI_UNAVAILABLE，TOOLCHAIN_EXIT=3，Mac 的 Xcode 已升到 27.2 / 27B52）。审查修正 1e0dfb6 时，AccountNewUITests、AccountListUITests 30 个中 27 个通过；失败的 3 个是 c38ab7e 起就有的：testDockListsMissingItemsAndJumpsToFirst、testTurningOffMixedSchedulingRemovesGroupsWithUndo、testCredentialSectionsFollowMethod。
  - S2-20：AccountNewUITests、AccountTestUITests、AccountListUITests 41/41，无不稳定。顺带修好上面 3 个失败，原因是测试 helper 点在词中间、sheet 回执画了两份、“更多”的标识盖住了内部各行。
  - S2-21：AccountDetailUITests 24/24；审查修正 0630966 后 25/25。
  - S2-22：AccountList / AccountBatch / AccountNew / AlertDetail 57/60。失败的 3 个就是上面那 3 个 AccountNewUITests 用例，在主分支 091294f 上同样失败；当时 S2-22 所在的分支还不含 S2-20（只读核对 3315d8b 不是 7e56d1c 的祖先）。
- S2-23：
  - 线 A 第一次 check（基于 6154134 加本条改动，14 类）：UI 224/227。失败的是本条新增的 testRouteFocusScrollsToEachSection、testTodayRefreshThrottleKeepsFiguresWithHeaderCountdown，以及 testSwitchingToNoProxy。两个新用例改测试后通过（单跑 2/4 → 1/2 → 1/1）：focus 夹具在首次出现时推入的路径被栈丢弃，改为下一轮再设；详情下拉在 UI 测试里拉不出刷新，改用回到前台触发。
  - 基线核对：在 6154134（不含本条改动）上单跑 AccountDetailMenuUITests 16/17，testSwitchingToNoProxy 两次失败。
  - 线 A 第二次 check：工具链 0、单元测试 2240 + 954、编译 0，UI 226/227；唯一失败 testSwitchingToNoProxy，无 FLAKY。
  - 集成者合入后（`6f473fd`）：
    - check（同样 227 个用例）226/227，单元测试 2256 + 955，唯一失败仍是 testSwitchingToNoProxy（两次）。
    - 全量 gate：工具链 0、单元测试 2256 + 955、编译 0，UI 625/625，无 FLAKY；testSwitchingToNoProxy 在全量 gate 里通过了。
  - 审查修正 `b66257b`：
    - 先确认 testTodayThrottleResendWaitsWhileSheetCoversPage 在修复前失败。
    - 第一次 check 57/58：testTodayThrottleResendGoesOutOnceSheetClosesWithinWait 两次失败，testTodayThrottleResendWaitsWhileSheetCoversPage 重跑后通过。
    - 第二次 check 58/58，单元测试 2256 + 956。
    - 合入后（`51fa325`）check 58/58。
    - 上表记的是“3 个类 58/58”，材料里没写是哪 3 个类；`51fa325` 之后没有全量 gate 记录。
- testSwitchingToNoProxy 的后续：阶段 3 的集成 gate 里它也两次失败过（见阶段 3 小结）。S2-11 的审查修正 `7319b0d`（2026-11-01）查明是测试问题：带撤销的回执盖住了代理行中心，点按落在回执上。改为等回执离开再点，App 代码不变。BACKLOG“AccountDetailMenuUITests.testSwitchingToNoProxy 既有失败”一行还没标已处理。
- 计时敏感的单元测试：AccountOAuthTests.authURLReplyKeepsStateAndRejectsUnsafeLinks（S2-15 的用例，只有 1 秒窗口）在 S1-18（check 与一次单元重跑）、S3-13 的检查，以及 S5-02 合入后的 check（连续两次）里都失败过，由 `b840ad9` 修正。

## 阶段 3 · 用户

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S3-06 | 余额核对与写入结果判定 Core | ✅ | `d2dbc57` | 与规格不同的取舍：①旧记录用同一编号重试后从 lastSentAt 起算 40 秒宽限（30 §3.4 写旧记录不做宽限判断，这里按 BACKLOG 的要求）；②已发出过的记录只有由请求体决定的 400 判未执行，404 / 401 / 403 / 423 / 429 等保持待核对；③退路页被截断或发不了退路查询时判 notFound（S3-07 按 ambiguous 呈现）；④KEY_CONFLICT 保留待核对，新编号由 S3-08 处理；⑤X34 按默认口径（同地址旧 id 计入门控，可用当前身份核对或放弃，同编号重试只限同地址同一发起人）。签名差异：PendingRetryPermission 按记录的重载加了 sameAddress 参数并改为转调五参数版，其他站点、没有发起人的记录由 allowedActorUnknown 改为 otherActor；graceStart 放在 BalanceReconciliation.swift。APIClient.updateBalance(_:sameAddress:) 只查地址，调用前必须先经 checkSender（S3-07 的 AppModel+Users.updateBalance 负责）。未做：界面、旧 updateBalance 与 BalanceView（S3-01 / S3-07 / S3-08 / S3-16）。UI 测试：已运行 SettingsUITests、Sub2MobileUITests，共 32 个全部通过（审查修正 a882036）审查修正 a882036：余额写 404 只认 USER_NOT_FOUND，其他 404 保留待核对；retrying 时无 reason 的 400 也保留待核对（与方案取舍不同）；KeyedWriteFlow 在结果不明的尝试之后，非 JSON 回复也转 unconfirmed，影响所有带 key 的写；删除站点时 requestIDUnreliable 标记交给同地址其他站点 id。 |
| S3-00 | 共用小组件：ReadOnlyGate、DeleteConfirmationSheet、SensitivePasteboard、AmountKeypad、UserChangeSignal | ✅ | `68de60c` | 只建组件与单测，未接页面；删除确认用 sheet（设计稿是 alert，为执行中转圈与禁止下滑关闭）；输入框允许粘贴；输入框上方标签与占位分开；Face ID 打开时正文加“确认后验证 Face ID。”，回执不带“已通过 Face ID”前缀；“Key”等拉丁字母对象名与汉字之间加空格；没有小数位时键盘的“.”位留空；UserChangeSignal 按 S3D1-03 分资料与余额两种计数；组件 UI 测试随首个消费方写；check：AppNavigationUITests 与退出、删除当前站点两个用例共 19 个全部通过 |
| S3-01 | 用户 Core：列表查询、用户字段扩充、展示纯函数，用户代码移出热点文件 | ✅ | `c6d8a44` | 用户方法、AdminUser 等结构体、AppModel 用户包装、DemoData 用户夹具已整体搬到 UserManagement.swift、AdminUser.swift、AppModel+Users.swift、DemoData+Users.swift，行为不变；新增唯一的 users(query:)、quickTopup()、usersTodayUsage(ids:)，内部 readInBatches 是唯一拆批实现。取舍：quick-topup 的项按后端真实形状解为 QuickTopupUser，不是 AdminUser；30 §1.7 要删的 userCost / standardCost 在 AccountTodayStats，没删；AdminUser.balance 仍严格解码；pageSize 越界按 00 §9.1 处理（Debug 断言、Release 夹紧）；状态 Picker 暂留到 S3-02，过渡期只过滤夹具，真实站点不发 status。UI 测试：check 跑了 UserManagement、SecurityPrompt、AppNavigation、Sub2Mobile 四个类，45 个全部通过，无 flaky |
| S3-02 | 用户列表页与快捷充值头像条 | ✅ | `2fba3df` | 取舍：头像条待核对读屏按记录方向写“上一笔充值 / 退款 / 余额设置待核对”（R02）；只读令牌时 + 与非待核对头像只置灰不加小字，空态按钮带“只读令牌”；待核对按同地址口径（X34）；刷新只替换第 1 页的行、已加载的后续页保留；夹具顺序与编号和设计稿不同（王小明 3 号，第 2 页 21–26）；头像条状态存 QuickTopupReply，不建 QuickTopupLists；.balanceKeypad 临时接旧余额页，mode 不生效（S3-08 换）。删除了基线不稳定用例 UserManagementUITests.testUserFieldSelectionAndOrderRemainAfterReopening（显示字段已按 U29 删除）；Sub2MobileUITests 前后台用例改读 user.1 的读屏文案。check 运行了 UserListUITests、UserManagementUITests、Sub2MobileUITests、AppNavigationUITests、SecurityPromptUITests、SettingsUITests，68/68 通过，无重跑（审查修正 763cb8b）审查修正 763cb8b：60 秒自动刷新醒来后重新核对是否到期，进入 Tab、回前台、首次加载后约 1 秒不再重复整轮刷新；刷新第 1 页时保留被顶部新增用户挤出第 1 页的边界行，删除场景仍按原规则去掉。 |
| S3-03 | API Key Core：AdminAPIKey、Key 读写请求与接口、今日消费、用户订阅 | ✅ | `7e2de59` | 与规格不同的取舍：<br>① userAPIKeys / apiKey / updateAPIKey 多一个必填参数 maskedView，由调用方按 api_keys.masked_view 传（APIClient 不保存 capability）；<br>② status 只有 now 参数，simple 模式只影响 badge / countsAsActive；<br>③ 没有 key_masked 时按后端 MaskAPIKey 规则在解码当下本地生成掩码，明文不保存；<br>④ 订阅 id 必填；AdminUserSummary 带 status；<br>⑤ reveal 无请求体，显式声明为读类请求（step-up 后自动重发，也会按读类请求自动重试）；<br>⑥ api-keys-usage 复用 S3-01 的 readInBatches；<br>⑦ UpdateRequest 在构造时拒绝换分组与字段修改或重置用量同发、revoke 组合不合法、什么都不改；<br>⑧ Key 名称在 App 里反转义显示（displayName），Web 端显示实体原文；<br>⑨ 旧详情页 Key 行显示 displayName + keyMasked，一次取全，去掉“加载更多密钥”；<br>⑩ CoreTests 移走 UserAPIKey 三行断言，UserManagementTests 改了 userKeys 那一行调用。<br>未做：Key 界面（S3-12 / S3-13）。<br>UI 测试：check 跑了 Sub2Mobile、UserManagement、SecurityPrompt、Settings 四个类，38 个全部通过；SettingsUITests.testDeletingAnotherSiteKeepsTheCurrentOneWithAReceipt 重跑后通过（耗时过长，与本条无关）。 |
| S3-04 | 充值与调整记录：UserLedger 解码与文案、全部记录页、共用记录行 | ✅ | `c63c6a8` | 按 S3D1-28 新建 DisplayFormat+DateTime 的 monthDayClock（跨年加年份），记录第二行用它；与规格不同的取舍：balance-history 对不存在的用户返回空页，副标题与 404 USER_NOT_FOUND 靠并发读 user(id:)，404 时显示“这个用户不存在或已删除”与“返回”按钮；下拉刷新失败按 00 §4.6 保留旧行并显示“刷新失败 · 重试 / 更新于 HH:mm”；拆分小字两句各一行、为 0 的项都省略（规格示例写了 $0.00，自相矛盾）；舍入为 0 不带符号；未知类型（含注册邀请码）写“其他记录”、数值 —；回前台只在首屏没加载成功时重拉并重新触发被打断的翻页；拆分函数名为 breakdownLines（返回数组），secondLine / spokenLabel 多一个 now 参数；第 1 页整页错误照 S3-02 用带标识的 ContentUnavailableView；订阅夹具用 S3D1-04 的 4 号企业专线；UserManagementUITests.confirmWrite 改为等编辑 sheet 关闭（原先滚动手势退化成点按，会误点新的临时入口）。未做：用户不存在态没有 UI 用例（夹具对不存在的 id 不返回 404）。UI 测试：check 跑了 UserLedger、UserList、UserManagement、Sub2Mobile、SecurityPrompt 五个类，48 个全部通过，无重跑 |
| S3-05 | 用户详情：hero 布局、分区并发加载、⋯ 菜单（启用 / 禁用、删除、发放补偿入口） | ✅ | `ee64359` | 编辑用户在 S3-11 前仍开旧编辑器，Key 摘要进 .userEdit 占位页；菜单项按文字定位（系统 Menu 无标识）；本人按 id 判断，夹具用 -ui-users-self 指定；只读令牌今日“—”且写入口全部置灰，只读拒绝用 ReasonCatalog 通用文案；删除站点行按 30 §2.4 写“站点 X”，成功后先移除列表行并出回执、确认 sheet 关闭后再返回；不带 key 的写和结果不明统一回执“结果未确认，已刷新为服务器当前状态”并读回；分区头暂用私有带 meta 版（S6-26 换 NumberedSectionHeader）；不加载订阅；旧 BalanceView 成功后 bumpBalance；check 6 个 UI 类 61 个用例全过、无重跑（审查修正 c1e5b1e）审查修正 c1e5b1e：从编辑页（push 的 .userEdit，任意分段）返回时，按路径观察重拉资料、Key、记录前 5 条（30 §2.6）。S3-11 把“编辑用户”改为 push 后不用再在详情页另做返回刷新，删旧编辑器 sheet 时把 reloadAfterEdit 一并删掉即可。 |
| S3-07 | 待核对横幅、核对流程与回到前台自动核对 | ✅ | `0a4db1b` | 与规格不同的取舍：①发起人邮箱在核对时读 GET admin/users/<id>，读不到写“管理员 #<id>”，没有发起人写“其他管理员”；②按方向换词（退款“重新退款 / 标为已扣除”，旧 set>0“设置余额 / 已执行”），其他管理员的候选用“放弃这笔”代替“不是，用同一编号重试”；③S3-06 的 notFound 与多条候选共用对话；④同编号重试按 D26 走 Face ID，执行前拒绝保留记录，二次验证通过后再确认一次；⑤冷却与只读在对话弹出时把重试置灰加说明，打开期间不会自动变可用；⑥放弃不出回执，回到前台多条命中各出一个回执，不合并；⑦set>0 的横幅标题不带金额；⑧两个对话之间等 0.45 秒；⑨当前站点余额行保留“打开原站点核对”（沿用现有）；⑩夹具的其他管理员沿用用户 2。AppModel+Users.updateBalance 是余额写唯一发送口（先 checkSender），旧 BalanceView 仍直接发送，由 S3-08 删除。UI 测试：check 跑了 BalanceReconcile、UserDetail、UserList、Settings、Sub2Mobile 五个类，75 个全部通过，无重跑；合入主分支后同五个类 check 64 个全部通过、无重跑（S1-09 已从 Sub2MobileUITests 删去 9 个旧概览用例、移出 2 个到 LegacyTrendUITests）（审查修正 824730d）审查修正 824730d：用户已删除（404）或资料读取失败时，详情页顶部仍显示待核对横幅（balance 传 nil），否则已删除用户的余额待核对记录无法核对和放弃；BalanceReconcileUITests 新增 1 个用例，check 两个类 28/28 通过。 |
| S3-09 | 新建 / 编辑用户 Core：请求体扩字段、分组授权组装、自定义属性、RPM 状态、读回核对 | ✅ | `6bcb497` | 纯 Core，不改界面与夹具；读回按 S3D1-18 三态 readback(sent:server:)；RPM 总计行顺序“简易模式不计数 → 不限 · 不计数 → 不限制 → 数值”、编辑态也校验必填属性（待用户拍板第 5、6 条，按默认值）；非 JSON 404 也按“RPM 状态暂不可用”；密码超 72 字节文案“不能超过 72 字节”；新建请求体空分组不发 allowed_groups、总发 restrict_public_groups；check（UserManagementUITests、SecurityPromptUITests）5/5 通过 |
| S3-08 | 充值 / 退款键盘 sheet：AmountKeypad、确认框、Face ID、提交流程与“仍要充值”两次确认 | ✅ | `86b5db6` | D26 唯一定义移到 BalanceChangeDraft.judgedAmount，BiometricGate 改为转调、签名不变；成功后复用 S3-07 的 applyRetried（列表余额或 setNeedsRefresh、quick-topup、bumpBalance、回执）；Outcome.executed 携带 WriteOutcome；退款提醒按字面替换“充值”→“退款”，待用户确认；金额为空一律灰色 $0；全部余额的 Face ID 判定额取打开时重读的余额；KEY_CONFLICT 保留记录、留在 sheet，再次提交用新编号并走两次确认；STORE_UNAVAILABLE 关 sheet 并 holdRetry；禁用用户退款文案只有单测；Sub2MobileUITests.testPendingBalanceRetryFollowsTheSender 随旧余额页删除改为经横幅核对弹框断言；check 六个 UI 类 76/76 通过，没有重跑后才通过的用例（审查修正 fe068c4）审查修正 fe068c4：“全部余额”改按整笔余额判定能否提交与显示，余额不足半美分也能归零，金额不再按舍入后的值多报；“全部余额”胶囊与用户行仍按 00 §6.1 显示 2 位小数。键盘内分段切到有同方向待核对的方向时，先弹 R03 第一次确认。这次确认的“先核对”在 sheet 内核对，出回执后键盘关闭（回执会被 sheet 挡住）。没有在 MainTabs 加核对宿主，因为 Sub2MobileApp.swift 是分区热点文件。 |
| S3-10 | 新建用户页：UserEditView 壳、基础与权限两段、创建流程 | ✅ | `827ef2e` | 取舍：属性定义缓存为 @ObservationIgnored var、加载方法名 loadUserAttributeDefinitions()；400 无 reason 两行红字自拟“请检查邮箱 / 请检查密码”；幂等存储不可用时保留编号并冷却；空表单保留系统返回；结果不明只按邮箱读回、找到时不补写属性；吸顶头按“说明行展开时”口径读滚动距离，修复收起 / 展开互相触发的卡死。UI：check 跑 UserCreate / UserList / UserManagement / SecurityPrompt / UserDetail 共 45 例全过、无重跑（审查修正 a789bd5）审查修正 a789bd5：读回失败改为“结果未确认”，同一草稿再提交前先读回；400 标红按组撤销；读回找到后照样写属性；吸顶头移到表单上方，回到顶部能展开。check 合格（单测 1863+602，UI 33/33）。 |
| S3-11 | 编辑用户 · 基础与权限与并发：保存流程、分组倍率、RPM 状态、离开确认，删除旧编辑器 | ✅ | `082ff96`、`ef13c9f` | 按 S3D1-27 分两次提交。因提交 1 后旧用例已无法通过，SecurityPromptUITests / UserDetailUITests 迁移和 UserManagementUITests 删除都提前到提交 1。保存流程放在 NativeApp/Session/UserUpdateSubmission.swift（可单测）。400 / 500 无 reason 读回不一致时不重建基线，只提示并保留草稿。站点关闭二次验证时，升管理员确认框去掉首句，脚注改为“保存时会再确认一次”。本人角色整段置灰。RPM 刷新失败时保留旧值。只在有改动或保存中时隐藏系统返回（侧滑随之不可用）。第三段“Key 与限额”先放占位，等 S3-12。UI 测试已运行：两次 check 均全过，47/47 与 48/48（审查修正 c06f56f）审查修正 c06f56f：用户资料已保存而自定义属性失败时，用 UserEditSettle 把这次收回的专属分组的倍率也从草稿去掉，避免再点保存时写回；审查提出的 RPM 轮询停止在 iOS 27 模拟器上未复现，视图未改，补了 15 秒轮询 UI 用例；check UserEditUITests 18/18 通过、无重跑。 |
| S3-12 | Key 与限额 · API Key 卡片：展示、换分组（含撤销）、停用 / 启用、重置速率限制 | ✅ | `41b3645` | 结果不明时读回一次（R06），不重发；E01 / E04 可用以 !isLegacyServer 判定，并保留“老服务端忽略 status”的保险；百分比 1 位小数，重置时刻按服务器时区（今天 / 明天 / M月d日）；整数上限不写小数；previous 为 disabled 视为 inactive 给撤销；simple 模式不改写“启用后仍不能调用”；按 S3D1-13 用 applyImmediate / undoImmediate，不新建 withdrawImmediate；Key 名称按反转义显示（与 Web 不同）；4099 有效期改为 2030-12-31 防夹具过期；sheet 与确认框挂在编辑页上；新建 / 编辑 / 删除 / 显示完整 Key、平台限额、替换分组未做（S3-13～S3-15）；UI 测试已跑 UserKeysUITests、UserEditUITests、UserDetailUITests、Sub2MobileUITests、UserCreateUITests 共 76/76 通过（审查修正 0078189）审查修正 0078189：进入第三段的首轮读取改由模型自有任务执行，视图被取消不再导致今日消费和订阅永久缺失；订阅读取被取消时保留已有数据。从基线里已没有的专属标准分组换出时，回执不给撤销，因为后端绑回专属分组会重新授予（与规格不同的取舍：比照 §0.6 替换分组规则；脚注“换分组的回执里可以撤销”在这种情况下不成立）。UI 测试未运行（UI_UNAVAILABLE），Mac 已升级到 Xcode 27.2，工具链守卫报 TOOLCHAIN_EXIT=3。（审查修正 f0e3975）审查修正 f0e3975：用户真机反馈的 Key 卡片展开、收起时抽搐。卡片拆成摘要行与展开行两个 List 行；去掉固定 250ms 的滚动，只在标题被顶出表单时才滚回。修前修后的录屏和逐帧图在 scratch/S3-12-anim；check 87/87 通过。 |
| S3-13 | Key 新建 / 编辑 / 删除与显示完整 Key | ✅ | `40ae8e7` | 最小表单与 ⋯ 第三项（U24 / U25 无设计稿，待看截图）；完整 Key 不可选中，只能复制（localOnly + 60 秒）；两种用途都 30 秒清除、进后台清除、inactive 遮住；撤销不写 status；所有结果不明的新建按同名 + 创建时间找回，找不到保留同一 key；编辑结果不明 GET 读回；有效期按服务器时区取当日 23:59:59；天数 ≤ 36500、名称转义后 ≤ 100 字节；管理模型由页面 UserKeyPrompts 持有，经 UserKeysModel 的 hooks / writeGate 写基线；新建 / 修改 / 删除都记入“已立即生效”；揭示 404 同时移除卡片；UI 测试已运行：UserKeys / SecurityPrompt / UserEdit 50/50 通过；同轮 UNIT 因无关的 AccountOAuthTests 计时断言失败一次，同一提交重跑 TOOLCHAIN / UNIT / BUILD 全 0（审查修正 8f2a3ea）审查修正 8f2a3ea：testNewlyGrantedGroupUpdatesBaselineAndLeaveList 偶发失败的原因是 visibleBand() 先查回执存在再读位置，回执 4.2 秒到时离开时用例会失败；改为先 exists 再从 snapshot 取位置，App 代码不变。check UserKeysUITests 29/29 通过，无不稳定用例。 |
| S3-14 | Key 与限额 · 平台限额（单平台写、撤销、重置窗口、无能力退路） | ✅ | `2708802` | store 挂在 UserKeyPrompts（页面级），签名改为 PlatformQuotaHooks、不收 userName；夹具放新文件 PlatformQuotaDemoStore.swift（DemoData+Users 已 743 行）；另改 UserEditScreen 一处（下拉刷新带上平台限额）；restore 409 与整表撤销回执用规格原文；每页只在首次进入该段时读取；503 读写都显示停用文案；USER_NOT_FOUND 切到“用户不存在”；百分比一位小数与 Key 卡片一致；UI：check 跑 UserQuotaUITests（新 12 个）、UserKeysUITests、UserEditUITests 共 60 个全部通过（审查修正 495633f）审查修正 495633f：整表退路下的保存和撤销跨平台排队执行，避免 A 撤销与 B 保存交错时后落地的 PUT 覆盖另一边（单测 fallbackWritesTakeTurns）。 |
| S3-15 | Key 与限额 · 替换分组（含精确撤销与退路） | ✅ | `6f76414` | E04 响应一律给撤销（迁移为空时 GET 后经 updateUserGroups 整表 PUT allowed_groups，绝不发空 key_ids）；0.6 的“不给撤销”只用于缺 E04 字段的旧响应；选项倍率按 S3D1-21 显示“×1”；Key 列表未读到时替换行和按钮置灰；结果不明先读回，撤销成功不出回执，失败“撤销没有成功：…”（GROUP_NOT_ACTIVE / KEY_NOT_IN_GROUP 用规格原句）；分组 sheet“改用替换分组”经 UserEditSheet.replaceGroup 原位换 sheet（多改 UserEditScreen / UserEditView）；UserEditUITests.removeGroup5 断言随行为改为“有”；已停用的专属分组不进分区；UI：check 5 类 85/85 通过（审查修正 e3702ec）审查修正 e3702ec 改了三处：①替换成功后，基线一律去掉 X、加上 Y，撤销只放回 X；②旧服务端结果不明时，读回按 §0.6 判断撤销；③结果不明时，编号挂到编辑页（UserEditorModel.frozenReplace），关掉 sheet 后再开会用同一编号重发，换目标前先读回核对。另把替换分组夹具从 DemoData+Users.swift（已超 800 行）拆到 Session/ReplaceGroupDemoStore.swift，Package.swift 加了一行排除，并多改了 UserEditorModel.swift 一行。check 三个类 60/60 通过。 |
| S3-16 | 阶段 3 完成度核查、补测与收口（含门槛 sheet 换大数字键盘） | ✅ | `415c38e` | 门槛 sheet 换 S3-00 的 AmountKeypad（6 位、整数、上限 100000，“.”位留空），D36 不变；输入“0”时加自拟提示“门槛要在 $1 至 $100,000 之间”（settings.threshold.hint），sheet 改为 large 档；AppPreferences 加 faceIDThresholdFractionDigits。按 S3D1-26 删除 APIClient 旧 updateBalance(_:onEvent:)，测试 39 处调用只改调用行（含 files 未列的 BalanceWriteOutcomeTests、UserManagementTests）。夹具只删两个无用例使用的参数（-ui-user-email-exists、-ui-user-attrs-empty）。README 用户 / 设置 / 余额口径、NATIVE_CONTRACT 用户签名已更新。30 §10 十项核查都已有测试，没有新增锁定用例；旧符号 grep 为 0。未做：用户详情分区头 meta、同地址旧站点显示（交 S6-26），用户章 Key 卡片 / RPM / 平台限额 / 只读属性 / 完整 Key 框的“—”读屏（记 BACKLOG）。代码与文档合成一个提交。UI：check 跑阶段 3 的 12 个类，166 / 166 通过，无 flaky（审查修正 daac0ff）审查修正 daac0ff：README 和 UserListField 注释写明列表字段选择按 30 §1.7 留给简化模式。（审查修正 3968b1b）审查修正 3968b1b：查明 XCTest 自带等待约 1 秒后才首次检查，回执出现到点撤销之间的等待改为轮询（UITests/XCUIElement+Poll.swift，只用在点撤销之前）；前台核对用例改为等 App 进入后台再拉回。check 四类 74/74；UserKeys + UserReplaceGroup 连跑 3 次 check 均为 41/41，无 FLAKY。 |

### 阶段 3 小结

#### (1) 完成项

- S3-00 `68de60c`；S3-01 `c6d8a44`；S3-03 `7e2de59`；S3-04 `c63c6a8`；S3-09 `6bcb497`
- S3-02 `2fba3df`（修正 `763cb8b`）
- S3-05 `ee64359`（修正 `c1e5b1e`）
- S3-06 `d2dbc57`（修正 `a882036`）
- S3-07 `0a4db1b`（修正 `824730d`）
- S3-08 `86b5db6`（修正 `fe068c4`）
- S3-10 `827ef2e`（修正 `a789bd5`）
- S3-11 `082ff96` `ef13c9f`（修正 `c06f56f`）
- S3-12 `41b3645`（修正 `0078189`）
- S3-13 `40ae8e7`（修正 `8f2a3ea`）
- S3-14 `2708802`（修正 `495633f`）
- S3-15 `6f76414`（修正 `e3702ec`）
- S3-16 `415c38e`（审查修正 `daac0ff`：README 写明列表字段选择留给简化模式，UserListField 加注释）

#### (2) 30 §10 测试清单对照（S3-16 逐项核对，十项都已有测试，没有新增锁定用例）

写流程按 S3D1-17 放在 Session，所以有几项的测试在 `Tests/NativeSessionTests`，不全在 `Sub2CoreTests`。

- 余额低判定（percentage、全局关、用户阈值）：UserPresentationTests.lowBalanceFollowsQuickTopupRules（参数表含百分比、总充值 0 按美元、旧服务端、全局关、用户阈值 0 不回落全局、禁用不标）、globalLowBalanceComesFromPublicSettings、listMarkPrefersPendingThenDisabledThenLowBalance
- Key 状态推导（含 simple）：AdminAPIKeyStatusTests.localDerivationFollowsBackendOrder、effectiveStatusFromServerWinsOverLocalDerivation、simpleModeKeepsExpiredAndExhaustedKeysUsable；UserKeyPresentationTests.badgeFollowsStatusTableIncludingSimpleMode
- 记录标题与数值文本：UserLedgerTests.titleFollowsWebForEveryType、valueTextSignsMoneyAndConcurrencyAndNamesSubscriptionDays、codePrefixCopyAndSpokenOnlyForRedeemedTypes
- `group_rates` null 编码：UserManagementTests.updateRequestEncodesGroupRatesWithExplicitNull、updateRequestDropsEmptyGroupRatesAndNeverCarriesBalance；UserAccessDraftTests.groupRateChangesSendChangedClearedAndRemovedExclusive、unchangedRatesSendNoGroupRatesKey
- `allowed_groups` 组装（保留未知 ID、关限制去公开分组）：UserAccessDraftTests.editAllowedGroupsKeepUnknownIDsAndApplyUIChanges、turningRestrictionOffDropsEveryPublicGroup、createAllowedGroupsAddPublicOnlyWhenRestricted、allowedGroupsAlwaysTravelWithRestrictFlag；UserKeyPresentationTests.allowedGroupsAfterRevokeKeepsUnknownIDs
- 平台限额撤销决策：PlatformQuotaTests.undoPlanCoversThreeBranches、fallbackUndoEntriesRestoreBeforeSnapshot；PlatformQuotaStoreTests.undoUsesPreviousOnItemPath、addedPlatformUndoDeletesIt、cancelDeletesAndUndoRestoresUsage
- 账本核对匹配：BalanceReconciliationTests.ignoredFiltersReturningUnrelatedRowsAreNotExecution（服务端忽略筛选返回无关行）、candidateRequiresUserOperationAmountNotesOperatorAndTime、twoCandidatesAreAmbiguous、legacyCandidatesIgnoreTime；候选不自动 resolve：BalanceReconcileSessionTests.foregroundPassOnlyActsOnExactMatches
- `balanceWriteOutcome`：BalanceWriteOutcomeTests.successfulWritesAreExecuted、definiteRefusalsResolve、otherNotFoundRepliesStayPending、keyedFailuresMapToTheTable、serverAndNetworkFailuresStayPending、refusalAfterUncertainAttemptStaysPending、executorResultsFlowThroughOutcome
- `KeypadInput`：KeypadInputTests.maximumRefusesOnlyTheKeyThatWouldPassIt、deleteAndClearEditTheText、valueParsesExactDecimalWithoutDouble、valueRefusesTextTheKeypadCannotProduce；门槛键盘参数 AppPreferencesTests.thresholdKeypadParametersMatchTheSaveRule
- `PendingBalanceOperation` 旧记录解码：PendingMoneyLedgerTests.legacyBalanceFileLoadsAndSurvivesRewrite；CoreTests.decimalBalanceIsDeterministicStringAndCodableIdentitySurvives；旧记录宽限 BalanceReconciliationTests.legacyRecordGetsGraceOnlyAfterARetry

#### (3) 30 章各节改动点

- §1.7：UsersView.swift 已删，列表是 Features/Users/UserListView（S3-02）；状态 Picker 与“显示字段”已删；`users(query:)`、`quickTopup()`、`usersTodayUsage(ids:)`、AdminUser 新字段、UserPresentation、QuickTopupStrip 都在。`ListFieldSelection<UserListField>` 按 30 §1.7 留给简化模式，主模式不用（README“当前功能”表下一段写明，UserListField 加了注释）。
- §2.6：UserDetailView 重写为 hero 布局，分区并发加载；月份按服务器时区（monthRange 用 serverZone）；`deleteUser(id:)`、`setUserStatus` 带 key（S3-05）。
- §3.7：BalanceView 已删，换成 BalanceKeypadSheet（S3-08）；KeypadInput；PendingBalanceOperation 新字段可缺失解码；`balanceWriteOutcome`、`reconcileBalance` 在 BalanceReconciliation.swift（S3-06）；回前台自动核对（S3-07）；余额只有 `updateBalance(_:sameAddress:onEvent:)` 一个发送口，旧 `updateBalance(_:onEvent:)` 由 S3-16 删除（S3D1-26）。
- §4：UserLedger.swift、UserLedgerView（S3-04）。
- §5 / §6：UserEditorView、PreparedUserMutation 已删；UserEditView / UserEditorModel、基础与权限两段、UserGroupSheets、UserRPMStatusView；UserUpdateRequest 的 `group_rates` 写显式 null；有 `admin.idempotent_writes` 时 supportsSafeRetry 恒为 true；`userRPMStatus`、`userAttributes`、`adminCount`（S3-09 至 S3-11）。
- §7：UserAPIKey 换成 AdminAPIKey，只保留 key_masked；UserKeys.swift；UserKeyCards、UserKeyGroupSheet、UserKeyFormSheet、UserKeyRevealSheet（S3-03、S3-12、S3-13）。
- §8：PlatformQuota.swift、PlatformQuotaSection、ReplaceGroupSheet（S3-14、S3-15）。

#### (4) BACKLOG 与阶段 0 备注里留给阶段 3 的事项

- 待核对门控跨站点 id、余额核对的阶段 3 部分、余额重试后的执行宽限：已完成。S3-06 做了 Core 与同地址口径，S3-07 做了用户详情、设置页的核对流程与回前台自动核对，S3-08 做了键盘内的两次确认。
- 余额页 UI 测试：BalanceKeypadUITests.testLaterKeepsTheRecordAndShowsTheBanner（稍后核对）、BalanceReconcileUITests.testRetryStoppedByStepUpKeepsTheRecord（重试被二次验证拦住时保留记录）。
- 读类 POST 的安全重发：S3-03 把 reveal 声明为读类，S3-13 发送前先 ensureStepUp。只读令牌仍会被 403 拒绝，Key 卡片 ··· 菜单整体置灰。
- 只读令牌写按钮置灰（S0-13 备注）：用户章写入口都挂 S3-00 的 ReadOnlyGate 置灰，不隐藏。UI 用例：UserListUITests.testReadOnlyTokenShowsTodayDashAndGraysCreate、testReadOnlyTokenEmptyStateButtonHasCaption；UserDetailUITests.testReadOnlyTokenGraysWritesAndHidesToday；UserEditUITests.testReadOnlyTokenGraysSave；UserKeysUITests.testReadOnlyTokenShowsTodayDashAndGraysWrites、testReadOnlyTokenGreysKeyManagement；UserQuotaUITests.testReadOnlyTokenDisablesQuotaWrites；UserReplaceGroupUITests.testReadOnlyTokenDisablesReplace。
- 绝对时间戳按服务器时区（S0-08 备注）：Features/Users 与用户 Core 文件里没有 TimeZone.current，也没有 DateFormatter。记录行用 `DisplayFormat.monthDayClock(_:timeZone:now:)`（S3D1-28），Key 重置时刻、有效期、平台限额重置时刻都按服务器时区。
- 缺失值“—”的读屏：用户列表、详情、记录读“无数据”；其余位置见 (7)。
- 倍率的显示位数：用户页统一用 `UserEditCopy.rateText`（DisplayFormat.decimal，最多 3 位小数，S3D1-21），与 S2-10 的 AccountEditCopy.rate 一致；分组页由阶段 5 定。
- 路由参数在旧页面上不生效、跨 Tab 跳转撤不掉视图式推入的页面（X39）：阶段 3 部分已处理。.user、.userLedger、.userNew、.userEdit(segment:)、.balanceKeypad 都由新页面接收；Features/Users 没有推入 Tab path 的视图式 NavigationLink，唯一一处在 Key 表单 sheet 自己的导航栈里。
- Face ID 金额门槛 sheet 的键盘：S3-16 已换成 AmountKeypad，D36 不变（SettingsUITests.testDeniedRaiseKeepsTheOldThreshold）。
- 通用删除确认：S3-00 的 DeleteConfirmationSheet，用户删除（S3-05 / S3-11）与 Key 删除（S3-13）已接入。
- 旧余额页绕过唯一发送口：已处理（S3-08 删 BalanceView，S3-16 删旧 updateBalance）。

#### (5) 核查结果（S3-16 一次性脚本，不入库）

- 旧符号为 0：UserAPIKey、users(page:)、BalanceView、UserEditorView、PreparedUserMutation、UserEditorTarget、LegacyBalanceSheet、definitelyRejected、balance.prepare、user-editor.、updatingSnapshot、APIClient 的旧 updateBalance(_:onEvent:)。角色词“普通用户 / 代运营”在 Sources、NativeApp、UITests 里为 0（测试里的“代运营”是工作区名称夹具）。
- R19 唯一定义：readInBatches、UserEditCopy、monthDayClock、MoneyRecordOrigin.oldLoginNote、UserKeyName 各一处。
- 余额发送口：NativeApp 只有 AppModel+Users.updateBalance 调 client.updateBalance(_:sameAddress:onEvent:)，发送前先调 MoneyRecordOrigin.checkSender。
- AppModel 阶段 3 锚点正好四项：userChanges、userList、pendingChecks、userAttributeDefinitions，publish 与 endActiveSession 各四行。
- Key 名称显示都读 displayName。标识前缀：编辑页只有 user-edit.*，第三段只有 keys.*。UITests 引用的 user.* / keys.* / balance.* / user-edit.* / settings.threshold.* 标识在 NativeApp 都能找到，-ui-* 参数两边对应。
- 阶段 3 文件都不超过 800 行（DemoData+Users 745 行，平台限额与替换分组夹具已拆到 PlatformQuotaDemoStore、ReplaceGroupDemoStore）。

#### (6) 与规格不同的取舍（阶段汇总，各条目的细项见上表备注）

- AdminUser.balance 严格解码：坏值时整页解码失败，不按 30 §1.3 只在该格显示“—”。后端是 float64，实际不会出现坏值（S3D1-25）。
- 回到前台多条精确命中的回执不合并：按 R17 新回执替换旧回执，多条命中时只看到最后一条（S3D1-25）。
- ReasonCatalog 不补 API_KEY_NOT_FOUND、GROUP_NOT_ACTIVE、SUBSCRIPTION_REQUIRED、GROUP_STILL_IN_USE、SAME_GROUP、GROUP_NOT_EXCLUSIVE、GROUP_IS_SUBSCRIPTION、KEY_NOT_IN_GROUP 这 8 个 reason，以各页面按 reason 的固定文案为准（UserKeyPresentation、UserKeyFormCopy、ReplaceGroup 里按 reason 取文案，S3D1-25）。
- Key 名称按反转义后的名称显示，删除确认也按它输入；Web 显示实体原文（S3D1-12）。
- “本人”只按 id 判断，不比邮箱（S3D1-14，30 §0.1）；夹具用 -ui-users-self 指定。
- UserChangeSignal 分资料与余额两种计数，编辑页离开确认里的“余额”只看 balanceRevision（S3D1-03）。
- 平台限额整表退路：任一行限额读不出时中止、不发 PUT，提示“平台限额读取不完整，不能保存，请在 Web 端修改”（S3D1-17）；退路下的保存与撤销跨平台排队执行（S3-14 修正）。
- 只改密码、结果不明时读回无法判定：保留草稿、下次保存换新 key，提示“密码是否已修改无法确认，请再保存一次”（S3D1-18）。
- 删除确认用 sheet（设计稿是 alert），输入框允许粘贴（S3-00）。
- 余额写：已发出过的记录只有由请求体决定的 400 判未执行；旧记录用同一编号重试后从 lastSentAt 起算 40 秒宽限（S3-06）。
- 退款提醒按字面把“充值”换成“退款”，待用户看截图确认（S3-08）。
- Key 新建 / 编辑用最小表单，“显示完整 Key…”放在 ··· 第三项（U24 / U25 没有设计稿，S3-13）。
- 门槛 sheet 输入“0”时加自拟提示“门槛要在 $1 至 $100,000 之间”，sheet 改为 large 档（S3-16）。

#### (7) 未做项及原因

- 用户详情私有分区头换成 NumberedSectionHeader 的 meta 版：S3-16 不依赖 S1-09b，交 S6-26（S3D1-25 ①）。
- 同地址旧站点（凭据已清）在站点列表的显示、LoginView 待核对列表的“打开原站点核对”：不属于阶段 3，交 S6-26（S3D1-25 ③）。
- 用户章其余位置的“—”读屏（Key 卡片事实格、RPM 状态块、平台限额格、编辑页只读属性行、完整 Key 框清除后）：仍读显示文字，已记 BACKLOG，建议并入 S6-26。
- 余额发送没有登记 MoneyWriteInFlight（S3-07 重试、S3-08 首发），由 S6-26 复核时统一登记（BACKLOG）。
- U26（percentage 阈值在总充值为 0 时的口径）请后端确认；U30（退款超额、降级或删除最后一位管理员返回无 reason 的 500）请后端补 reason（BACKLOG）。
- 列表字段选择（ListFieldSelection、UserListField）按 30 §1.7 留给以后的简化模式，主模式不用，不是遗漏也不是死代码。
- 需要用户拍板的六条按默认值实现（_decisions-S3 末尾）：Key 名称实体、删除确认样式、余额坏值、退款提醒措辞、RPM 总计行顺序、编辑老用户时校验新增的必填属性。

#### (8) UI 测试运行情况

- S3-16 check（线 B，基于 `0ed37b4` 加本条改动）：阶段 3 的 12 个类 166 / 166 通过，没有重跑后才通过的用例。按类：UserListUITests 13、UserLedgerUITests 8、UserDetailUITests 14、BalanceReconcileUITests 14、BalanceKeypadUITests 12、UserCreateUITests 15、UserEditUITests 19、UserKeysUITests 29、UserQuotaUITests 12、UserReplaceGroupUITests 12、SecurityPromptUITests 3、SettingsUITests 15。单元测试 2253 + 949 通过，编译无新增 warning。
- 集成者合入后 check 同样 12 个类 166 / 166 通过，BalanceReconcileUITests.testForegroundExactMatchResolvesOnItsOwn 重跑后才通过。
- 集成者全量 gate：627 个用例 626 个通过。UserKeysUITests.testChangeGroupReceiptAndUndo、UserReplaceGroupUITests.testEmptyMigrationUndoUsesAllowedGroups 重跑后通过。两次都失败的只有 AccountDetailMenuUITests.testSwitchingToNoProxy，是阶段 2 的既有问题（基线 `6154134` 上同样失败，BACKLOG 已记），与阶段 3 无关；集成者单独重跑这三个类（58 个用例）时也只有它失败。
- 审查修正 `daac0ff`（README 与注释）：check（工具链、单元测试 2256 + 956、编译无新增 warning、UserListUITests 13 / 13）通过，没有重跑。

## 阶段 4 · 日志与统计

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S4-01 | 日志接口层：LogTimeWindow / RequestLogFilter、Page<T>、记录新字段、errorCount 与 searchUsageUsers | ✅ | `e760dd5` | 按 C-28 定型签名实现，另有：LogTimeWindow / RequestLogFilter / UsageUserMatch 为 Hashable（超集）；key_view 只由 requestRecords 的必填参数 maskedView 决定；errorCount 固定带 view=all（与日志页同口径，比 SLA 口径多算业务限制）；pageSize 超出 1–1000 抛 .validation；provider_cost_recorded 键缺失按已记录处理；超时仍 20 秒（R07）。旧日志页只做编译适配：每页 30 → 100 条，usage 时区改为站点时区，成本优先用 account_cost；上游段仍套 upstreamErrorFilter()，留给 S4-05。Sources 里的 TimeZone.current 只剩 ServerTimeZone.device 与 AnalyticsQuery 默认值。UI：check RequestLogsUITests、AppNavigationUITests 共 19 个全部通过 |
| S4-00 | 导航栈页面状态共享 PageStateRegistry | ✅ | `7e9450b` | 按 S4D1-01 / C-13 定稿：prune 条件改为“新 path 不是旧 path 的延长”（同长度替换也释放）；不改 Sub2MobileApp.swift，页面经 state(_:tab:prunedBy:make:) 登记时把注册表接到 router；多出 existing、instances、PageStateKey、AppRoute.pageStateKeys；AnalyticsSession（S4-12）与 LogsStore（S4-05）本身不在本条；没有界面变化，未新增 UI 测试；check 跑了 AppNavigationUITests、Sub2MobileUITests、SettingsUITests，50/50 通过（审查修正 af21d72）审查修正 af21d72：注册表改为按（窗口的 AppRouter、Tab、键）分区，适配 iPad 多窗口（各窗口互不共享、互不 prune，窗口关闭后状态随 router 释放）。签名与 contracts.md C-13 不同，以代码为准：删除不带 router 的 state(_:tab:make:)；existing、instances、release、prune 增加 `in router: AppRouter` 参数，S4-08b 改用 instances(of: LogsStore.self, tab: tab, in: router)。state(_:tab:prunedBy:make:) 与 AppModel.pageStates 不变。 |
| S4-10 | OpsQuery 与性能趋势覆盖秒数口径 | ✅ | `f785b88` | 上限按 S4D1-10 放宽为 31 天 + 1 小时（40 §2.7 字面是 30 天，待用户确认）；dashboardPerformanceTrend 多一个无默认值的 supportsModelFilter 参数；ops 请求不发 timezone（按 §1.4 请求行）；近 1 小时取整后总是 60 个满桶，残桶只出现在近 6 / 24 小时（§1.4 示例“只覆盖 23 秒 / 61 桶”只当版式示意）；按 X29 不改 APIClient.swift，PerformanceTrend 暂留 Decodable / init(from:) 给旧方法用，由 S1-09b 删除；ACCEPTANCE.md:98 一并改；UI：Sub2MobileUITests 22/22 通过 |
| S4-03 | 请求详情接口与展示规则：RequestErrorDetail、上游尝试、标记已处理 | ✅ | `11ef9e2` | 纯 Core。errorDetail / requestAttempts / setErrorResolved 的唯一定义（R19）；RequestDetailPresentation(+Attempts) 供 S4-08 / S4-08b 使用；ReasonCatalog 加 404 OPS_ERROR_NOT_FOUND；路径模板隐去 ops/requests 后的请求 ID。取舍：日期写“M/d HH:mm(:ss)”，月日不补零；状态行图标由页面画；已恢复没有上游码时写“鉴权 / 恢复”；业务限制为灰；退路耗时 duration → at−started → 相邻 at 差（标“约”）→ —；除 OPS_DISABLED 外的 404 都走退路；没实现 pathSegment（编码交给 URLComponents，避免“%”编码两次）；RequestLogs.swift 未改，errorRecord 留到 S4-08b。UI 测试未运行（ui_test_classes 为空，check 输出 UI_SKIPPED，App 与 UITests 编译通过）（审查修正 ad7d8d4，随 S3-02 合入）审查修正 ad7d8d4：耗时的四段之和中，上游、响应两段优先读详情（列表行不带这两个字段），补了“列表行 + 详情”的测试。 |
| S4-11 | 四个运维图表模型与接口（时长分布、错误趋势、错误分布、Token 请求统计） | ✅ | `5c6897e` | 能力由调用方显式传，不放进 OpsQuery（同 S1-02 / S4-10）；opsTokenStats 的 supportsModelFilter 默认 false（40 §2.2 不传 model）；桶长复用 OpsBucket，没有建 OpsBucketLength（S4D1-09）；bucket_start 必填解析在本文件内联（OpsMonitoring 的 requiredTimestamp 是 private）；错误趋势 60 秒 / 3600 秒桶的底注句式和夏令时回拨日的合计粒度留给 S4-18；规格 40 §5.2“映射后的不同上游名”应为“映射到同一上游名的不同请求模型”；纯 Core，UI 测试未运行（ui_test_classes 为空，check 的 UI_SKIPPED） |
| S4-02 | 统计查询与解码：AnalyticsQuery 改造、汇总 / 趋势 / 排行新字段、用户排行 / 用户趋势 / 请求类型接口 | ✅ | `ab70fc9` | 请求类型用 S4-01 的 UsageRequestType；AnalyticsQuery.model 改 String?、粒度为 TrendGranularity 的 typealias、时区必传站点 ServerTimeZone（“Local”原样发）；usageAnalysisTrend / UsersTrend 返回带桶时区的回执；models 只发一个 model_source；users-ranking limit 本地限 1–50；超时 45 秒（R07 / U54，非 40 §0.6 的 60 / 90 秒）；首页显式范围趋势改为转调 usageAnalysisTrend；旧统计页只做编译适配（请求换站点时区、预设起点用站点日历，初始“今日”仍按设备日历，留给 S4-13）；Sub2MobileUITests / HomeUITests 已无“实际消费”未改；check 在 ab70fc9 上跑 AnalyticsUITests、Sub2MobileUITests、LegacyTrendUITests、HomeUITests、GroupsUITests，39 / 39 通过，无重跑 |
| S4-09 | 范围计算、利润分摊与桶标签（AnalyticsRange、ProfitRows、金额差增减） | ✅ | `e94f71b` | 新增 AnalyticsRange.swift、AnalyticsCustomDraft.swift（自定义 sheet 规则，方案允许的拆分）、ProfitRows.swift、DisplayFormat+AmountChange.swift（X31），以及对应的 3 个测试文件，共 28 个测试；没有改动现有文件。规格未写、本条定下的取舍：自选单天含今天写“比昨天同时”、过去写“比前一天”，多天写“比前 N 天同期 / 比前 N 天”；上月写“比 M 月”，不带年。说明行有一端不在今年时开头带年，跨年时两端都带年；单日的范围名和桶全名不在今年时也带年。按小时且含现在时，末桶不在刻度上就把最后一个刻度换成末桶写“现在”。自选单天的分段标题写“自选 1 天”。从今天 / 7 天 / 30 天打开自定义 sheet 时初值为本月。单天的底部说明照规格固定文案。利润两边都为 0 写“$0.00”（设计稿写“—”）。有缺失段或缺合计的列逐行舍入，isReconciled 为 false。AnalyticsAxisTick 多一个 isNow，AnalyticsRange 多一个 today，AnalyticsDayBounds 多一个 init(today:)。UI 测试未运行：本条无界面改动、无 UI 类；check 结果为单元测试 1735 + 514 全部通过，编译通过，无新增 warning。（审查修正 66da4cb）审查修正 66da4cb：利润合计改按首页口径 round(实际 − 账号成本)，账号成本列总数取 round(实际) − 利润合计，可能比 usage/stats 舍入值差 1 分；自定义范围 sheet 在 14 日“本月”和“近 14 天”起止相同时，优先选用户最后点的那个。 |
| S4-12 | 统计分析会话、本机记忆、范围条与范围 / 筛选 sheet | ✅ | `3b6892a` `a9cc804` | 分两次提交（S4D1-02）：记忆与状态机放在 NativeApp/Session（AnalyticsMemory.swift、AnalyticsSessionState.swift），与 40 §1.8 写在 AnalyticsSession.swift 内不同；AnalyticsSession.swift 只剩 typealias、Scope 与环境值。记忆只在用户改动时写入（S4D1-03），route.metric 优先并写回；分组失效只在目录加载成功后判定。会话签名的取舍：isUITesting 进 init，load 带 refresh 参数，state 无卡时返回 nil，副标题按手机时钟算，AnalyticsCardKey 带 showsInUpdateLine，筛选行函数放 Session 便于单测，当前筛选的模型无用量时补一行 0.0%。PageStateRegistry 签名以已合入的 in router: 为准。筛选底注照抄规格原文，不加设计稿前缀。界面 UI 用例归 S4-13，已预留标识。两次提交前都跑了 check SettingsUITests，13/13 通过。（审查修正 d15867f）审查修正 d15867f：同一张卡的读取改由会话持有（照 GroupDirectory 的 inFlight 写法），后来的页面等进行中那次的结果，发起页的 .task 被取消也不会取消这次读取；改范围 / 筛选、reset、cancelAll 会丢掉进行中的读取并按新选择重读；补单测 aReadOutlivesThePageThatStartedIt 与 aChangeOfChoicesStartsANewReadInsteadOfJoiningTheOldOne。副标题最早时间那条按 S4D2b-14 不改（二级页独有的键由 S4-15 / S4-17b / S4-18 / S4-18b / S4-19 设 showsInUpdateLine: false）。check SettingsUITests 13/13 通过。 |
| S4-04 | 使用记录行展示与列表策略（纯函数） | ✅ | `d3cd265` | 只新增 Sub2Core 纯函数：LogListPresentation.swift、LogListPolicy.swift（scope 允许的拆分）、DisplayFormat+Duration.swift（X31）及两个测试文件，签名照方案、没有改名。与规格字面不同的取舍（S4D2a-18）：首字与总耗时都缺时写一个“—”；自定义时段标题“10/14 09:00 – 10/15 18:00”，空态“所选时间内…”；不在今年的节头带年份，读不出时间的行进末尾“—”节；30 天提示只给起点早于 30 天前的自定义范围（U35）；站点没有 usage.model_source 时用量段非请求口径的模型胶囊置灰（S4D2a-13）；列表行不做业务限制灰（列表项没有 is_business_limited）。视图、轮询、计数取数留给 S4-05 / S4-05b / S4-06。没有界面改动，UI 测试未运行（ui_test_classes 为空，check 输出 UI_SKIPPED） |
| S4-05 | 使用记录页（一）：LogsStore、LogRow、按日期分节的列表与分页、时间菜单，替换旧日志列表 | ✅ | `f603839`、`2b6b598` | 分两次提交（S4D2a-16）：a 是 Session 状态机 LogsStoreState / LogSegment / LogsSource 加 28 个单测，b 是视图、夹具、兼容入口、路由与 UI 测试。分层按 S4D2a-01，本体在 Session/LogsStoreState.swift。X39：.logs 的 user / model / modelSource 已生效。BACKLOG：第 281 行（告警详情日志断言）、第 336 行（账号详情对旧日志页的断言）、第 337 行（夹具上游条数与 AccountDemoStore 一致）已处理；第 332 行（按 id 进入账号详情的用例仍经旧用量详情的“查看账号”视图式链接）和 testErrorAccountLatestUpstreamErrorOpensRequestRoute 的占位断言留给 S4-08；第 491 行改为“兼容入口不登记”。与规格不同：首屏读取改在 onAppear 里用非结构化 Task 触发，store 只把 CancellationError 当作中断（推入时页面先消失再出现，会取消首屏读取）；429 等待中被挡住的读取显示倒计时失败行，结束后自动重读；时间与条件胶囊按设计稿用选中样式；再选同一时间预设不重读；运维关闭说明沿用 S1-08 文案；切段从加载中开始；自定义 sheet 文案按方案；LogRow 不画 chevron。未做：分段计数、胶囊移除与置灰、清除筛选（S4-05b），自动刷新（S4-06），筛选 sheet 与导航栏筛选按钮（S4-07），新请求详情（S4-08）。UI 测试：check 跑 5 个类 86 个用例，全部通过。（审查修正 cf34f8f）审查修正 cf34f8f：429 等待改按设备时钟记录和判定（新增可注入的 phoneNow），与 BlockFailureRow 的倒计时和自动重发一致，修复服务器时钟偏慢时等待结束不自动重读的问题。 |
| S4-13 | 统计分析卡片流（一）：页面骨架、卡片外壳、图表组件与计费趋势卡（替换旧统计页） | ✅ | `b0e64f1`、`fbf5d67` | AnalyticsView 移到 Features/Analytics，保留 X20 兼容构造 AnalyticsView(accountID:groupID:)（参数忽略；过渡期旧分组详情入口进入全站或记忆筛选的卡片流、视图式推入，会话不随出栈释放，S5-06 删链接、S4-20 删构造）；纯逻辑在 Sub2Core 三个新文件，AnalyticsCardLoaders 放 Session，都有单测；BlockFailureRow 加 retryTitle，AnalyticsSessionState.load 的 fixture 改为 async；计费三读取口、AnalyticsCardBody / AnalyticsFigureRow / AnalyticsCardStatusRow、analyticsCardLoading / analyticsPageRefresh、AppModel.analyticsOpsDisabled / recordAnalyticsOpsResponse 已建；整图点选在 .chartXSelection（按住拖动）之外加了同时识别的 SpatialTapGesture 补快速点按，抽成 View.analyticsChartSelection 供 S4-16 / S4-17 复用（没用 .chartGesture，它会取代拖动）；平均耗时用 .list 样式（2.4s）；400 / 403 不给重试；日历跨时区核对（手机 America/Los_Angeles、站点 Asia/Shanghai）“今天”标在站点日期，没有错位；UI 测试 check 两次 64/64、75/75 通过，没有重跑才通过的用例（审查修正 252ebd7）审查修正 252ebd7：对比或合计最近一次读取失败时只隐藏增减行（含失败后重读进行中），不再拿新合计和旧对比这两个时刻的数相除。判定写在 AnalyticsBillingCard.Comparison.init(_:lastReadFailed:totalsLastReadFailed:)，失败标志取 LoadState.lastErrorAt。S4-13b 的利润卡增减行应复用这个判定。与规格的取舍：合计刷新失败时也隐藏增减行（规格只写了对比失败）。 |
| S4-08 | 请求详情页（一）：三种样子、耗时、上游尝试、关联与标识（只读） | ✅ | `aa67dc3` `0e333d3` | 分两次提交（a：RequestDetailLayout、RequestDetailModel 与单测；b：两个视图文件、LogFixtures+Detail、LogDestinations、RequestDetailUITests、AccountDetailUITests），各自通过 check。与规格字面不同：分区编号按设计稿，头部卡和按钮行不编号，从耗时开始编“壹”（S4D2a-14，待用户确认）；已恢复但查不到成功的那次时最后一行写“失败，后续尝试未记录”；成功样子读链不放占位、2 次及以上才显示、读链出错就隐藏；详情 OPS_DISABLED 时尝试区隐藏；详情 404 整页带“返回”；名称缺失的关联行即使有 id 也不可点；服务端请求 ID 为空不显示；从下级页返回不重读；logs.detail.cost 的语义变为“账号成本”。未做：标记已处理、复制、删除旧详情文件（S4-08b）；兼容入口进入时关联行和尝试行会弹掉视图式推入的页面（S4D2a-15）；夹具 requestUsageRecord 还没有脚本。UI：RequestDetailUITests、RequestLogsUITests、AccountDetailUITests 共 49/49 通过，没有重跑才通过的用例。（审查修正 615c3ef）审查修正 615c3ef：请求详情的 429 等待改按设备时钟（phoneNow）记录与判定，和失败行倒计时、自动重发一致（同 cf34f8f）。 |
| S4-05b | 使用记录页（二）：分段计数、条件胶囊（移除、置灰与原因）、清除筛选与 30 天提示 | ✅ | `2b19cad` | 计数状态机 LogSegmentCounter（Session）挂在 LogsStoreState 上（countSource 默认 .unavailable），条件只用 LogConditions、失败只加 isInvalidParameters（S4D2a-01/02/03）；取数中只写分段名、≥ 10,000 写 12.3K；置灰胶囊可移除、读屏“未生效”；只有置灰条件时按无条件空态；400 有生效条件给“清除筛选”、没有给“重试”（方案原写“有任何条件”）；30 天提示和模型胶囊置灰只有单测、没写 UI 用例；分段控件“—”的逐项读屏没处理；S4-05 用例里 logs.empty.clear 的断言改为存在；check 带 RequestLogs / AppNavigation / AccountDetail / AlertDetail / RequestDetail 五个 UI 类 88/88 通过（审查修正 799e1f0）审查修正 799e1f0：离开页面期间被后台打断的计数在回到页面时补取（当前错误段第 1 页被打断且不重读时补发 errorCount）；429 等待期间不发计数，改写“—”。LogsStoreStateTests 已 810 行，新单测放在 LogsStoreCountTests.swift；check RequestLogsUITests 18/18 通过。 |
| S4-13b | 统计分析卡片流（二）：利润明细卡（可为负的柱、逐段利润退路、最近 4 段明细表） | ✅ | `f38a7dd` | 利润“空”= 每个桶实际扣费与账号成本都为 0（S4D2b-09 ②，待用户确认）；旧站点逐段刷新只重读窗口变了的桶（当前桶与读时还在进行的桶）与缺失桶，比裁定“当前与缺失”多一类以免跨小时后停在部分窗口成本（待用户确认）；表头按小时“时段”、按天“日期”；两边利润都为 0 时沿用 S4-09 的“$0.00 · 比昨天同时”；增减行在对比读取中或失败时隐藏（同计费卡）；亏损夹具不改合计（其余桶分摊）；提出 AnalyticsBillingCard.footTitle 与 AnalyticsSession.changeComparison 两卡共用；共用件 DisplayFormat.wholePercent 与 AnalyticsFanOut（results / map）已建；check AnalyticsUITests 22/22 通过（审查修正 9a149f5）审查修正 9a149f5：旧服务端逐段利润遇到 429 后，整块等满 Retry-After 再读，等待期间不发 usage/stats，换范围后仍然等待。卡内显示倒计时，“重试本项”不可点，等待结束自动补读缺失的段，已读到的段保留。改动方式是在 LoadState 加 RateLimitedAnswer 钩子（共用文件，只增不改）；check AnalyticsUITests 23/23 通过。 |
| S4-15 | 排行卡与全部排行页 | ✅ | `347887b` | ① 排行纯逻辑放 NativeApp/Session/AnalyticsRanking.swift、AnalyticsModelName 放 Sub2Core（与 40 §4.7“只新建 AnalyticsRankView.swift”不同）；② 刷新（下拉 / 60 秒 / 回前台）时丢弃另两段缓存，正在被读的键不丢，不严格“缓存到范围或筛选改变为止”（S4D2b-20，待用户确认）；③ 用户卡底没有 total_users 时按“取回满 5 行”判断；④ 构成条不足 3 行写实际行数；⑤ group_id 0 写“未分组”不可点，分组名为空用目录名或“#id”；⑥ 全部排行页“已筛选”时保留导航栏与范围条；⑦ 映射口径每行都写“→ b”；⑧ 页面用 ScrollView + 圆角面板，不用 List；⑨ 分组 / 用户卡底 meta 为空，读屏带“ · ”（AnalyticsCards.swift 归 S4-13，未改）。UI：check AnalyticsRankUITests,AnalyticsUITests 32/32 通过，无重跑（审查修正 ea63652）审查修正 ea63652：排行卡停在筛选维度时，刷新也会丢弃隐藏段（AnalyticsRankCardPlan.read 改为先 dropHidden，再判断筛选维度）；全部排行页读取失败时保留排序与口径菜单，加载中仍整页 ProgressView。 |
| S4-06 | 使用记录自动刷新：since_id 增量、近顶裁尾、时间窗裁剪、定期校准与上游错误退路 | ✅ | `cca32ce` | 按 S4D2a-04 组合 LogListPolicy / LogPollSchedule / IncrementalList，不建 LogRefreshCycle；状态与方法写在 LogsStoreState.swift（587 行），since 读取加到 LogsSource（usageSince / errorsSince）。回前台只改 foregroundResumed() 本体：自动刷新中立即一拍，否则照旧重读第 1 页。用行的 onAppear / onDisappear 近似第一个可见行（List 不支持 onScrollTargetVisibilityChange），与 scope 字面“iOS 26 的滚动位置 / 可见行 API”不同；近顶阈值 20 行，差一两行不影响判定。与裁定不同：加了 pendingTrim，只有轮询合并后超过 N 才裁或挂起到回到顶部；没有可续行时本拍静默读第 1 页（不经 loadFirstPage，避免空列表每分钟闪“正在读取记录…”）；间隔用设备时钟计时。上游错误不校准；自动刷新失败用列表末尾失败行（新 phase refreshFailed），重试立即一拍，间隔按 BlockRefresh 退避；加载更多或下拉刷新失败、末尾已有失败行时暂停轮询，直到用户重试。N = 5 调参下裁尾会删掉屏上可见的行（只在测试）。回前台时当前错误段被打断的第 1 页计数改为补发 errorCount，LogsStoreCountTests 中一个用例随之改名改断言。单测 16 个放新文件 LogsStoreRefreshTests.swift（原测试文件已超 800 行）。UI：check 跑 RequestLogsUITests、AppNavigationUITests、RequestDetailUITests，47/47 通过，无 flaky。（审查修正 d210f18）审查修正 d210f18：当前段“有旧行 + 加载更多 / 第 1 页失败”时自动刷新和回前台不再停住。第 1 页失败的下一拍静默重读第 1 页（不取计数），后面某页失败时顶部照常增量、失败行保留，裁尾时失败页号跟着改成裁尾后的下一页。 |
| S4-14 | 计费明细 / 利润明细图表 body 与单图页 | ✅ | `718325f` | 12 个 body 按主题分三个文件（本条 AnalyticsChartBodies.swift + S4-17 AnalyticsUsageBodies + S4-18 AnalyticsOpsBodies），与改动总表的单文件写法不同；另新增 Sub2Core AnalyticsDetailTable.swift 与 Session AnalyticsChartCatalog.swift；逐段利润未对齐时说明只写前半句（S4D2b-09 ③）；计费页三数的账号成本与利润页合计可能差 $0.01（BACKLOG“利润明细合计口径”）；磁贴值不做（S4D2b-09 ⑤）；其余 10 个 key 显示占位（App 内无入口）；两种尺寸都高亮选中行，选中折起部分的桶不自动展开；vendor 按 U01 不做。check AnalyticsUITests 27/27 通过（含新增 4 个） |
| S4-16 | PerfTrendBody 与 RPM / TPM 趋势卡、性能明细 sheet | ✅ | `70ed798`、`9de80ae` | 分两次提交（S4D2b-17）：a 为 Sub2Core 的 PerfTrendPresentation（含 OpsChartCopy.siteWideNote）和 Session 的 PerfTrendState 及单测；b 为 PerfTrendBody / PerfDetailsSheet / AnalyticsPerfCard 插槽 / AnalyticsFixtures+Perf，删除 PerformanceTrendView.swift 和 AppModel.dashboardPerformanceTrend(hours:)，加 5 个 UI 用例，改两处文档。与规格不同：性能明细照规格写“只覆盖 N 秒”（设计稿写分钟）；桶数取点数（end 取整后近 1 小时总是 60 桶，示例“61 桶 / 23 秒”不会出现）；运维关闭时卡头只写“运维监控”，早于窗口终点当天的桶写“昨天 HH:mm”（都取自设计稿）；改范围不清选中，改指标保留选中。按裁定不建 APIError.isOpsDisabled（用 AccountUpstreamErrors.isOpsDisabled），PerfOpsHooks 只保留两项，选中走共用的 AnalyticsChartSelection；firstDelay / nextDelay 合并为 pollDelay(now:)，nearestPoint 改为 nearestIndex。-ui-performance-error 改名为 -ui-analytics-ops-gone。.analytics 的 metric 自本条起生效（优先并写回记忆）。check AnalyticsUITests、Sub2MobileUITests、HomeUITests：a 71/71、b 76/76，全部通过，没有重跑。（审查修正 f1d4575）审查修正 f1d4575：卡片已有数据时遇到 404 OPS_DISABLED，重新开启运维后立即重读（原先因会话里有旧值跳过，最长约 60 秒仍显示“未开启”）；同步期内 404 每 30 秒读一次，不退避。没有另外接 opsRevision。 |
| S4-19 | 模型页（AnalyticsModelView） | ✅ | `ed28069` | 速度区：有 ops.dashboard_model_filter 时 top_n=10 按口径原样传、映射口径传 b + upstream、多行加权合并；没有该能力时请求口径 top_n=100 找同名行，上游 / 映射口径写 —（规格写 top_n=10 找同名行，后端按请求模型分组，找不到对应行，S4D2b-20）；运维关闭时整区隐藏，用户区改编号“叁”；使用记录行副行按设计稿；用量区请求、Tokens 为 0 写 0；不显示平台名（U36）；vendor 不隐藏用户区（U01）；只用会话的分组筛选；UI：AnalyticsRankUITests、RequestLogsUITests、AnalyticsUITests 共 62 个全过（审查修正 c5c84d3）审查修正 c5c84d3：速度区收到 404 OPS_DISABLED 后，运维重新开启、回前台或再进本页时，不刷新的读取也会重读（loadModelPageSpeed），做法同 f1d4575。开启后 30 秒同步期内如果又碰到 404，过去范围要等下一次回前台、再进本页或下拉刷新才恢复（按 S4D2b-02 ③ 不另加读取循环）。线 C 推送因网络失败，提交只在本地分支上。 |
| S4-07 | 按对象筛选 sheet（LogFilterPickerSheet） | ✅ | `16afeef` | 规则放 Sub2Core/LogFilterPicker，防抖与取消放 Session/LogFilterPickerModel（复用 LoadState），pick 写在 LogsStoreState.swift（S4D2a-02）；AccountRow.swift 的 AccountStateGlyph 改成 internal 以便复用；pick 单测写在 LogFilterPickerModelTests（LogsStoreStateTests 已超过 800 行）；搜索框不自动聚焦；某组 0 行整组隐藏、三组都空时提示“没有匹配的账号、分组或用户”、同一对象只补名称、停用分组不标“停用”（建议默认值）；sheet 选用户写邮箱、用户详情进入写用户名，留给 S4-20；check（RequestLogs / AppNavigation / AlertDetail / RequestDetail）UI 65/65 通过 |
| S4-17 | 更多图表（一）：AnalyticsMoreView 骨架与吸顶条、更多图表卡与磁贴、Token 使用趋势、端点分布 | ✅ | `aaa1d87` | 主题高亮改为按越过吸顶条下沿的可见行判定（LazyVStack 下 scrollPosition(id:) 不随滚动更新），滚到底高亮最后一个；Token 配色按规格（缓存读横纹 ImagePaint，与设计稿不同），选中底注用桶全名；吸顶条只放胶囊与范围菜单；端点卡片与全屏相同；点图例清除选中；用户用量趋势、请求类型、运行类图与对应磁贴先放占位（“这张图会在后续版本提供。”/“— 稍后提供”，S4-17b / S4-18 / S4-18b 替换）；AnalyticsOpsOffCard 内 ops.disabled.empty 标识被外层合并；check 通过，AnalyticsMoreUITests + AnalyticsUITests 共 38 个 UI 用例全过（审查修正 ee8d0cd）审查修正 ee8d0cd：下拉刷新用例偶发失败的根因在测试，不在 App。列表扫回顶部后停在离顶约 30pt 处，说明行中点在吸顶条里，下拉偶尔被“运行”胶囊接走，列表不动。改为从吸顶条下方起手后，连跑 3 次 check 都是 18/18、无 flaky。 |
| S4-08b | 请求详情页（二）：标记已处理与撤销、复制标识，删除旧日志文件 | ✅ | `6f88cff` `244cc67` | 6f88cff 只含删除旧文件（git add 中止，单独不能编译），244cc67 补齐其余改动，需一起合入。规则在 Sub2Core/RequestResolve，状态机在 Session/RequestResolveFlow（闭包式 RequestResolveSource），视图在 Features/Logs/RequestResolveControls，RequestDetailView 只接线；applyResolved 写在 LogsStoreState.swift，单测放在新文件 LogsStoreResolveTests（原测试文件已超 800 行）。与规格不同（S4D2a-18）：撤回与撤销成功不出回执，撤回失败写“撤回失败，请重试”；没应答时读回核对一次；本机标记后小字等下次读到详情才出现；处理人显示邮箱；运维已关时按钮不预先置灰。另外：文案常量名为 resolveGone / resolveOpsDisabled；值为“—”的 ID 不能复制；复制回执用默认色调。UI：check 跑 RequestDetail / RequestLogs / AccountDetail 三个类，65/65 通过，无重跑（审查修正 9325417）审查修正 9325417：跨过写入的详情读取（进页读取或下拉刷新在 PUT 落地前发出、落地后才到）不再盖回按钮，“撤销”照常发出 resolved=false。做法是 RequestResolveFlow.writeEpoch 加上 RequestDetailModel.detailEpoch，丢掉的读取不再补读一次，“已处理 · 人 · 时间”仍等下次读到详情才出现。 |
| S4-17b | 更多图表（二）：用户用量趋势与请求类型（含降级扇出） | ✅ | `1821fd4` | 实际扣费段底注按设计稿写“按实际扣费取前 12 位…”；请求类型降级任一类失败整卡失败（占比依赖五类合计，待用户确认），更早服务端的 cyber / live 回 400 会让降级整卡失败；请求类型磁贴 0 位小数（72%）、行内 1 位小数；第 5 类 Live 用 ink3 点纹 + ink2 描边（设计稿只有 4 种，交 UI 审查）；用户用量磁贴缩略图取第 1 名折线；unknown 与不认识的类型不计入合计；全屏 12 行无界面入口，只有单测覆盖；卡键 more.userTrend.tokens（计入副标题）/ more.userTrend.actual_cost、more.reqType（不计入）；新建夹具 AnalyticsFixtures+More.swift；UI：check AnalyticsMoreUITests,AnalyticsUITests 43/43 通过（新增 5 个用例） |
| S4-18 | 运行类图表（一）：运行主题接入、平均账号切换、请求时长分布、错误趋势 | ✅ | `ac14bea` | 未建 AnalyticsOpsTopic：S4-17 的 AnalyticsMoreView 已按每张卡一个 case 组织，只替换 perf / switch / latency / errTrend 四个 case，运维关闭整主题换卡沿用 S4-17 的分支；错误趋势柱按页面范围的桶给出（空桶也画，单天 3600 秒桶按小时，结清 BACKLOG 359；60 / 3600 秒桶底注结清 BACKLOG 363）；错误率在 request_count_sla 为 0 时写 —；三张图不接点选，全屏尺寸只有单测；overview 失败行标识两卡分开；新增 Sub2Core/OpsChartPresentation.swift 与单测（files 未登记）；check AnalyticsMoreUITests 14/14 通过 |
| S4-18b | 运行类图表（二）：错误分布、Token 请求统计、运行类磁贴补值 | ✅ | `54b78f7` | 错误分布、Token 请求统计两个 body 走 loadOps，卡键都不计入“N 分钟前更新”；更多图表卡只补错误趋势、请求时长分布两块运行类磁贴（含缩略图与“全站”），40 §2.3 其余四行“磁贴”在已定版式没有位置，未做（S4D2b-20）；Token 三个数值不大于 0 写 —，与模型页一致；补了“窗口内没有模型用量”空态文案；磁贴遇 404 OPS_DISABLED 时显示“—/运维监控未开启”；错误分布夹具与错误趋势同口径 397/317/80；full 尺寸无入口、只单测；check AnalyticsMoreUITests,AnalyticsUITests 50/50 通过 |
| S4-20 | 阶段 4 完成度核查与收口 | ✅ | `1f89476` `4498506` | 删除 LegacyLogsEntry（连同 LogsView 的 pushesInPlace、openedRequest、navigationDestination(item:)）、AnalyticsView(accountID:groupID:)、RequestLogPresentation.date、AppModel.dashboardTrend() 及 -ui-dashboard-detail-errors / -ui-trend-long-series 分支、DemoData.longHourlyTrend、DashboardTrendMetric / Sample / Series / series / clampedZoom、trendAxisLabel；字段归并已做（四个详情专有字段移到 RequestErrorDetail 存储，展示层去掉列表退路）；首页退路每小时图接上 accountCost；卡底无 meta 时不再读“ · ”，统计 UI 两处标题断言收紧；LogsStoreStateTests 超 800 行，把桩与夹具搬到新文件 LogsStoreTestSupport.swift；RequestLogFilter 五个旧条件与 cacheTokens 按 S4D2b-18 保留；AnalyticsUITests.swift 830 行未拆（多阶段共用）；README、ADMIN_MODULES、API_COMPATIBILITY 最小修改（API_COMPATIBILITY 另合写了旧趋势四段）；U54 与 30 天实测未做（未获授权）；改了 files 未登记的 LogFixtures+Detail、RequestDetailModelTests、AnalyticsCards、AnalyticsRankUITests、AnalyticsUITests、PerformanceTrend(+Tests) 注释并新增 LogsStoreTestSupport；R19、D29、D27、X39 核查结果见阶段 4 小结；两次 check 各 13 个 UI 类 255/255 通过（20a 有 1 个既有不稳定用例重跑后通过） |

### 阶段 4 小结

依据：进度表阶段 4 各行、BACKLOG“App 与设计 · 阶段 4”、plans/_decisions-S4.md、S4-20 与相关条目的提交说明、scratch 下的核查脚本和 check / gate 日志；标“（复核）”的是在 `c5231df` 上只读核对的。

#### (1) 完成项

按功能块归并，括号里是审查修正提交。S4-20 由合并提交 `c5231df` 合入主分支。

- 共用基础
  - S4-00 `7e9450b`（修正 `af21d72`）：导航栈页面状态共享 PageStateRegistry，新 path 不是旧 path 的延长时释放；修正后按（窗口的 AppRouter、Tab、键）分区，iPad 多窗口互不共享、互不清理。
- 日志与请求详情的接口层（Sub2Core）
  - S4-01 `e760dd5`：LogTimeWindow / RequestLogFilter、Page<T>、使用记录与错误记录的新字段、errorCount（固定带 view=all）与 searchUsageUsers；key_view 只由 requestRecords 的必填参数 maskedView 决定；UsageRequestType 唯一定义。旧日志页只做编译适配。
  - S4-03 `11ef9e2`（修正 `ad7d8d4`，随 S3-02 合入）：errorDetail / requestAttempts / setErrorResolved 的唯一定义与 RequestDetailPresentation(+Attempts)；ReasonCatalog 加 404 OPS_ERROR_NOT_FOUND；日志路径模板隐去 ops/requests 后的请求 ID。
  - S4-04 `d3cd265`：使用记录行展示、分节、时间预设、条件胶囊与列表策略的纯函数（LogListPresentation、LogListPolicy、DisplayFormat+Duration）。
- 使用记录页
  - S4-05 `f603839` `2b6b598`（修正 `cf34f8f`）：Session 状态机 LogsStoreState / LogSegment / LogsSource；LogsView、LogRow、按日期分节的列表与分页、时间菜单与自定义时段、日志夹具，替换旧日志列表；.logs 的 user / model / modelSource 生效。修正后 429 等待按设备时钟记录与判定。
  - S4-05b `2b19cad`（修正 `799e1f0`）：分段计数（LogSegmentCounter）、可移除与置灰的条件胶囊及原因行、清除筛选、请求参数无效与 30 天提示。修正后回到页面时补取被后台打断的计数，429 等待期间不发计数。
  - S4-06 `cca32ce`（修正 `d210f18`）：自动刷新（since_id 增量、近顶裁尾、时间窗退路、定期校准、失败退避），组合 S4-04 的 LogListPolicy / LogPollSchedule。修正后“有旧行 + 加载更多 / 第 1 页失败”时自动刷新和回前台不再停住。
  - S4-07 `16afeef`：按对象筛选 sheet（账号、分组、用户三组搜索，同类替换）。
- 请求详情页
  - S4-08 `aa67dc3` `0e333d3`（修正 `615c3ef`）：RequestDetailLayout、RequestDetailModel；成功 / 已恢复 / 失败三种样子、耗时、上游尝试、关联与标识（只读），.request 改接新页。修正后 429 等待按设备时钟。
  - S4-08b `6f88cff` `244cc67`（修正 `9325417`）：标记已处理与撤销（只读令牌置灰）、复制标识，删除旧日志文件 RequestLogsView.swift；`6f88cff` 单独不能编译，两次提交需一起合入。修正后跨过写入的旧详情读取不再盖回按钮。
- 统计的查询与计算（Sub2Core）
  - S4-02 `ab70fc9`：AnalyticsQuery 改造（model 为 String?、粒度为 TrendGranularity 的 typealias、时区必传站点时区），汇总 / 趋势 / 排行新字段，用户排行 / 用户趋势 / 请求类型接口；统计聚合超时 45 秒；首页显式范围趋势改为转调 usageAnalysisTrend。
  - S4-09 `e94f71b`（修正 `66da4cb`）：AnalyticsRange、AnalyticsCustomDraft、ProfitRows（利润分摊到分）、DisplayFormat+AmountChange。修正后利润合计按首页口径 round(实际 − 账号成本)。
  - S4-10 `f785b88`：OpsQuery 与性能趋势覆盖秒数口径，PerformanceTrend.maximumSpan 为 31 天 + 1 小时。
  - S4-11 `5c6897e`：四个运维图表的模型与接口（时长分布、错误趋势、错误分布、Token 请求统计）。
- 统计分析页
  - S4-12 `3b6892a` `a9cc804`（修正 `d15867f`）：本机记忆 AnalyticsMemory 与会话状态机 AnalyticsSessionState（放 NativeApp/Session），会话挂载、范围条与范围 / 筛选 sheet。修正后同一张卡的读取由会话持有，发起页离开不再取消。
  - S4-13 `b0e64f1` `fbf5d67`（修正 `252ebd7`）：卡片流骨架、卡片外壳、柱图与整图点选、计费趋势卡，替换旧统计页（删除旧 NativeApp/Features/AnalyticsView.swift、LegacyTrendPage.swift、LegacyTrendUITests.swift）。修正后对比或合计最近一次读取失败时隐藏增减行。
  - S4-13b `f38a7dd`（修正 `9a149f5`）：利润明细卡（可为负的柱、旧站点逐段利润、最近 4 段明细表）。修正后旧站点逐段遇到 429 整块等满 Retry-After。
  - S4-15 `347887b`（修正 `ea63652`）：排行卡与全部排行页。
  - S4-16 `70ed798` `9de80ae`（修正 `f1d4575`）：PerfTrendPresentation / PerfTrendState、PerfTrendBody、RPM / TPM 趋势卡与性能明细 sheet；删除 PerformanceTrendView.swift 与 AppModel.dashboardPerformanceTrend(hours:)；.analytics 的 metric 生效。修正后 404 OPS_DISABLED 之后重新开启运维立即重读。
- 二级页
  - S4-14 `718325f`：计费明细 / 利润明细图表 body 与单图页。
  - S4-17 `aaa1d87`：更多图表页骨架与吸顶条、更多图表卡与磁贴、Token 使用趋势、端点分布。
  - S4-17b `1821fd4`：用户用量趋势与请求类型（含旧服务端降级扇出）。
  - S4-18 `ac14bea`：运行主题接入、平均账号切换、请求时长分布、错误趋势。
  - S4-18b `54b78f7`：错误分布、Token 请求统计、运行类磁贴补值。
  - S4-19 `ed28069`（修正 `c5c84d3`）：模型页 AnalyticsModelView。修正后速度区在 404 OPS_DISABLED 之后重新开启运维时重读。
- 收口
  - S4-20 `1f89476` `4498506`：删除 X20 兼容入口（LegacyLogsEntry.swift 连同 LogsView 的 pushesInPlace / openedRequest / navigationDestination(item:)，AnalyticsView(accountID:groupID:)）和只给旧统计 / 旧趋势页用的代码；四个只在错误详情下发的字段归到 RequestErrorDetail；首页退路每小时图带上账号成本；卡底 meta 为空时读屏只读标题；README、ADMIN_MODULES、API_COMPATIBILITY 按现状改写。
- 与阶段 4 相关、记在其他阶段的：S1-17 `c8bc894`（告警详情错误请求计数行，只调 S4-01 的 errorCount）；ops overview 的方法与模型按 40 §2.7 归 10 章（S1-02）。

#### (2) 规格测试清单 / 完成标志对照

- FINAL-SPEC“实现顺序建议 · 阶段 4”没有写完成标志（阶段 0、1 写了），下面按 40 章 §1.8、§2.7、§6.7、§7.7“对现有代码的改动点”里的测试要求对照。
- 函数级对照取自 S4-20 的一次性核查脚本（scratch/s4-20/check_tests.py，输出 tests.txt，不入库）：脚本列的 31 个函数全部找到，没有缺失。UI 部分脚本只数了各类的用例数；下面写到的 UI 用例名是起草时在 `c5231df` 上按函数名核对的（复核），没有逐个读断言。

- 40 §1.8 统计分析：
  - UsageAnalyticsTests（新解码与 model_source）：analyticsSummaryDecodesStandardCostCacheTokensAndEndpoints、trendPointWithoutAccountCostKeyIsNilNotZero、modelSourceOnlyAccompaniesModel、granularityIsExplicitAndOnlyOnTrendEndpoints、analyticsQuerySendsSiteTimeZoneVerbatimAndUTCInstants
  - AnalyticsRangeTests（跨月、2 月与上月同期取月末、夏令时、单日按小时）：analyticsCaptionsFollowTheSpecExamples、analyticsThisMonthComparisonTakesLastMonthsEndWhenTheDayIsMissing、analyticsDayRoundTripsAndValidatesCalendarDays、analyticsHoursFollowDaylightSavingInTheSiteZone、analyticsRangeTableGivesWindowsGranularityAndNames
  - ProfitRowsTests：profitRowsSplitTotalsToCentsByLargestRemainder、profitRowsKeepEveryColumnEqualToItsTotal、profitRowsKeepLossesAndLeaveMissingCostsBlank
  - AnalyticsUITests 的记忆场景（复核）：第一次从搜索进是近 7 天 testFirstEntryFromSearchIsLast7AndShowsTheBillingCard；从搜索改了范围、再从概览进仍保留 testRangeChangedFromSearchIsKeptWhenEnteringFromTheOverview；换站点回到入口默认值 testAnotherSiteStartsFromItsEntryDefault；S4D1-03 加的第四个场景 testOverviewEntryWithoutAChangeIsNotRemembered。
  - “AppModel 的 UI 测试桩补齐新接口”：位置不同，统计的 UI 夹具在 Features/Analytics/AnalyticsFixtures(+Filter/+Model/+More/+Ops/+Perf/+Rank).swift，日志的在 Features/Logs/LogFixtures(+Detail/+Picker/+Refresh).swift，不在 AppModel（X05 / X44；复核：NativeApp 里调用这两组夹具的只有 Features/Analytics、Features/Logs 与 SearchFixtures）。
- 40 §2.7 更多图表：
  - PerformanceTrendTests（覆盖秒数，1 分钟、5 分钟残桶）：throughputOneMinutePartialBucketsDivideByCoveredSeconds、throughputFiveMinutePartialBucketsDivideByCoveredSeconds、throughputPeakAndAverageUseCoveredSeconds
  - OpsAnalyticsTests（error-trend 按小时 / 按天合计）：errorTrendHourlyBarsInSiteZoneStackOnlySLAAndBusinessLimited、errorTrendDailyBarsSplitAtSiteMidnightNotUTC、errorTrendUpstreamCountsStayOutsideTheBars；U35 的 30 天提示 retentionHintWhenRangeStartsBeforeThirtyDays
  - “UI 测试桩按覆盖秒数造首尾残桶”（规格写在 AppModel.dashboardPerformanceTrend(hours:)）：位置不同，在 AnalyticsFixtures+Perf.perfTrend，按每桶覆盖的秒数造数，近 6 / 24 小时的 5 分钟桶首桶 240 秒、末桶 60 秒，近 1 小时是 60 个满桶；AnalyticsUITests.testPerfDetailsShowPartialBucketAndRowSelectsPoint 断言近 6 小时 73 桶、最新一桶“只覆盖 60 秒”（复核）。
- 40 §3.7 / §4.7 / §5.7：只列新文件，没有写测试要求。对应 UI 用例在 AnalyticsUITests（单图页，S4-14）与 AnalyticsRankUITests（全部排行 S4-15、模型页 S4-19），逐项未核对。
- 40 §6.7 使用记录：
  - RequestLogsTests：account_cost 与 provider_cost_recorded → accountCostPrefersServerValue、accountCostFormulaOnlyWhenKeyMissing；D04 字段 → errorRecordDecodesD04FieldsAndOldRowsAsNil；since_id 信封 → incrementalEnvelopeCarriesSinceAndLatestID；上游错误没有 has_more 时按 pages → upstreamErrorPageWithoutHasMoreFollowsPages；LogTimeWindow → rollingWindowOnlyEmitsTimeRangeForOps、timeWindowRejectionsHappenBeforeSending；key_view → usageListSendsKeyViewOnlyWhenMasked
  - 游标与合并按规格不在本章重复，在 IncrementalListTests（S0-07）。
  - RequestLogsUITests 按新布局重写（S4-05）；自动刷新新行在顶部、N = 5 时停在顶部裁尾（复核）：testAutoRefreshPutsNewRowsOnTopAndTrimsAtTheTop、testAutoRefreshHoldsTheTrimWhileScrolledDown。
- 40 §7.7 请求详情：
  - upstream_errors 解析、attempts 含 null 计时的旧事件、副行文案规则三项在 RequestDetailTests（规格写在 RequestLogsTests，位置不同）：upstreamErrorEventsKeepOnlyTheirTimingAndAccount、attemptsDecodeOldEventsAndUnknownValues、attemptRowsFollowTheFiveSubtitleRules
  - UI 三种样子与标记已处理的撤销（复核）：RequestDetailUITests.testSuccessLookShowsCostTimingTokensAndAttempts、testFailedUpstreamErrorFromAccountLoadsDetailAndChain、testRecoveredRowResolvesAmbiguousRequestID、testMarkResolvedUndoAndListRowFollows；只读令牌（S4D1-13）testReadOnlyTokenGreysResolve。
- S4-20 新增的两条用例（都先红后绿，见 `1f89476` 提交说明）：RequestLogsTests.errorDetailOwnsTheDetailOnlyUpstreamFields、HomeFallbackTests.hourlyCarriesTrendAccountCost。
- 核查脚本运行时统计的用例数：UsageAnalyticsTests 20、AnalyticsRangeTests 21、ProfitRowsTests 5、AnalyticsMemoryTests 17、AnalyticsSessionStateTests 19、PerformanceTrendTests 17、OpsAnalyticsTests 38、AnalyticsSeriesTests 27、LogListPresentationTests 33、IncrementalListTests 16、RequestLogsTests 22、RequestDetailTests 19；AnalyticsUITests 32、AnalyticsRankUITests 14、AnalyticsMoreUITests 18、RequestLogsUITests 24、RequestDetailUITests 13。

#### (3) 本章改动点（40 章各节）

- §1.8 统计分析：
  - 旧 NativeApp/Features/AnalyticsView.swift 已删（S4-13 `b0e64f1`），新页面是 Features/Analytics 下的 AnalyticsView(route:) 卡片流；AnalyticsFilterView 在代码（Sources / NativeApp / Tests / UITests）里 0 处（复核；docs 的规格、设计与调研文档里仍有历史记载）；X20 兼容构造 AnalyticsView(accountID:groupID:) 由 S4-20 删除。
  - 位置不同：记忆与会话状态机本体放 NativeApp/Session（AnalyticsMemory.swift、AnalyticsSessionState.swift，可单测；S4-12，S4D1-02）。Features/Analytics/AnalyticsSession.swift 放 typealias、AnalyticsSessionScope 与环境值，以及 S4-13 加的计费三个卡键与 loadBillingSummary / Comparison / Trend、AppModel.analyticsOpsDisabled / recordAnalyticsOpsResponse，S4-18 加的 loadOps（复核：git log -S）。
  - UsageAnalytics.swift：AnalyticsQuery 时区必传站点时区、model 为 String?、粒度用 TrendGranularity；usageAnalysisModels(_:source:)、usageAnalysisUsersRanking(_:sortBy:…)（S4-02）。TrendPoint 的 account_cost 键缺失为 nil，首页退路每小时图由 S4-20 接上。
  - AnalyticsRange.swift、ProfitRows.swift（S4-09）。
  - DashboardTrendMetric.actualCost 的文案由 S4-02 `ab70fc9` 从“实际消费”改为“实际扣费”（复核：git log -S）；DashboardTrendMetric / Sample / Series 只给旧趋势页用，S4-20 整体删除。
- §2.7 更多图表：
  - AnalyticsMoreView（S4-17）；12 个 body 分三个文件：AnalyticsChartBodies（S4-14）、AnalyticsUsageBodies（S4-17）、AnalyticsOpsBodies（S4-18），与改动总表的单文件写法不同。
  - OpsAnalytics.swift：OpsQuery（S4-10）与四个图表方法（S4-11），能力由调用方显式传 supportsModelFilter，不放进 OpsQuery。ops overview 归 10 章，没有 OpsOverviewWindow（复核：代码 0 处）。
  - usageAnalysisUsersTrend、usageAnalysisRequestTypes（S4-02）。
  - PerformanceTrend：覆盖秒数（S4-10）；dashboardPerformanceTrend(_ query: OpsQuery, supportsModelFilter:) 写在 PerformanceTrend.swift（按 X29 不改 APIClient.swift）；上限 31 天 + 1 小时（规格“保留 30 天上限”，待用户确认）；struct PerformanceTrend 已不是 Decodable。
  - AppModel.dashboardPerformanceTrend(hours:) 与 PerformanceTrendView.swift 已删，换成 PerfTrendBody（S4-16 `9de80ae`），运维关闭用 OpsDisabledNotice。
  - 文档：ACCEPTANCE.md 覆盖秒数一段随 S4-10 改（S4D1-16），RPM / TPM 段由 S4-16 改，S4-20 只核对。
- §3.7：AnalyticsChartView（S4-14）取代旧“消费明细”链接。
- §4.7：AnalyticsRankView（S4-15）；排行纯逻辑在 Session/AnalyticsRanking.swift，AnalyticsModelName 在 Sub2Core（与“只新建 AnalyticsRankView.swift”不同）。
- §5.7：AnalyticsModelView（S4-19），复用 opsTokenStats。
- §6.7 使用记录：
  - RequestLogs.swift 是 admin/usage、ops 错误列表与计数的唯一定义处；RequestLogPage 已删（复核：代码 0 处），改用 Page<T>；errorCount(filter:kind:)、searchUsageUsers(_:)（S4-01）。用量明细在有 api_keys.masked_view 时才带 key_view=masked（S4D1-06）。
  - 增量合并用 IncrementalList，N、时间窗裁剪与校准放在 LogsStoreState（S4-06）。
  - 旧 RequestLogsView.swift 拆成 Features/Logs 下的 LogsView、LogRow、LogFilterPickerSheet 等（S4-05、S4-07），旧文件由 S4-08b 删除。页面标题与搜索目录写“使用记录”“错误请求”“统计分析”（复核：LogsView.swift:9、SearchDirectory.swift:14–18）。
  - category / statusCode / resolved / requestType / apiKeyID 不再出现在界面，属性按 40 §6.7 留作内部用（S4D2b-18 ①）。
  - docs/ADMIN_MODULES.md 的日志段由 S4-20 改写（`4498506`）。
- §7.7 请求详情：
  - errorDetail(id:kind:)、setErrorResolved(id:kind:resolved:) 在 RequestErrorDetail.swift，requestAttempts(id:around:) 在 RequestAttempts.swift（规格写在 RequestLogs.swift，位置不同）；errorRecord(id:kind:) 已删（复核：代码 0 处）。
  - 新 RequestDetailView（S4-08）；旧私有详情视图随 RequestLogsView.swift 删除（S4-08b）。
  - S4-20：upstream_status_code、upstream_error_message、upstream_latency_ms、response_latency_ms 从 RequestErrorRecord 移成 RequestErrorDetail 的存储属性（属性名不变，消息照旧脱敏），展示层去掉“detail ?? record”的列表退路。

#### (4) BACKLOG 与前序阶段备注里留给阶段 4 的事项

- 阶段 0 备注：
  - S0-07：AnalyticsQuery 默认时区、usage 列表 timezone、PerformanceTrendView 轴标签、日志页接入 IncrementalList（N = 500、时间窗裁剪、10 次校准）、“（站点时间 UTC+8）”提示。已处理：S4-01 把 usage 时区改为站点时区，S4-02 让 AnalyticsQuery 必传站点时区，PerformanceTrendView 由 S4-16 删除，增量刷新由 S4-06 接 IncrementalList；TimeZone.current 的现状见 (5)。
  - S0-08：RequestLogPresentation.date 仍按设备时区。S4-20 删除。
  - S0-19 小结未做项（TimeZone.current 的两处退路）：已处理，同 S0-07。
  - S0-04 与 BACKLOG“长超时读请求超时后的自动重试”：统计聚合 45 秒超时后仍自动重试 2 次，待实测。未实测（未获授权访问测试环境），见 (7)。
  - S0-11：“阶段 4 日志页把游标绑在会话代号上”。已处理：S4-06 的增量读取回执先核对票据、会话代号与任务是否已取消，再合并到当前列表（`cca32ce` 提交说明）；状态机带建会话时的代号（复核：LogsStoreState.swift:71 的 generation、:132 的 isStale，:489 poll() 回执的 ticket / isCurrent() / Task.isCancelled 检查；isCurrent 比的是会话代号，见 LogsStore.swift:18）。
  - S0-LOW-A 与 BACKLOG“旧服务端的站点时区退路是连接时的手机时区”：材料里没有记录阶段 4 对这一行的处理。
- 阶段 1 备注与移交（S1D1-28）：
  - S4-05 同步 AlertDetailUITests.assertErrorLogsOpened（BACKLOG“S4-05 同步告警详情的日志页断言”）：S4-05 已处理。
  - S4-02 复用 TrendGranularity：已满足（AnalyticsQuery 的粒度是它的 typealias）。
  - S4-13 / S4-16 / S4-18 运维关闭一律用 OpsDisabledNotice：已满足（复核：PerfTrendBody.swift:75、AnalyticsMoreView.swift:241 的 AnalyticsOpsOffCard，日志页 LogsView.swift:124、请求详情 RequestDetailView.swift:110 也用它）。
  - 阶段 1 小结 (3) 留给阶段 4：PerfTrendBody 与删除 dashboardPerformanceTrend(hours:)（S4-16 `9de80ae`）；删除 LegacyTrendPage、LegacyTrendUITests 与 focus 分流（S4-13 `b0e64f1`）。已处理。
  - 阶段 1 核查里的 -ui-performance-error（S4-16 删除）：S4-16 改名为 -ui-analytics-ops-gone，-ui-performance-error 在代码（Sources / NativeApp / Tests / UITests）里 0 处（复核；APP-PROGRESS、BACKLOG 里仍有记载）。
  - BACKLOG“阶段 1 过渡页与旧趋势代码的删除”“AppModel 里随旧概览失去用途的夹具分支”“UI 测试 6 并发下的快照停顿”（趋势缩放用例随 LegacyTrendUITests 退役）：已处理（S4-13、S4-16、S4-20）。
  - BACKLOG“利润亏损的固定演示状态”（统计负值柱留给 S4-13b）：已处理（-ui-analytics-loss，AnalyticsUITests.testProfitLossBucketDrawsBelowZeroAndReadsNegative）。
  - BACKLOG“告警详情‘近 24 小时 N 条’的口径”：口径不变（view=all），阶段 4 子表另记“errorCount 的口径”。
- 阶段 2 留下的 BACKLOG：
  - “日志页旧夹具与账号详情上游错误计数不一致”：S4-05 已处理，夹具按 AccountDemoStore 统一。
  - “账号详情 UI 测试对旧日志页与占位页的断言”：日志页部分 S4-05 已处理；testErrorAccountLatestUpstreamErrorOpensRequestRoute 的占位断言留给 S4-08，S4-08 的进度备注没有写结果。复核：`0e333d3` 改过 AccountDetailUITests，`c5231df` 上该文件已没有 route.placeholder 与 logs.account-filter。
  - “按 id 进入账号详情的 UI 用例路径”：S4-05 交给 S4-08，已处理。`0e333d3` 提交说明写 AccountDetailUITests 只改 openAccountFromRequestLog 查链接的一行，改点请求详情“关联”的 logs.detail.link.account（推入 .account）；复核：AccountDetailUITests.swift:401 用的就是这个标识。
- 通用 BACKLOG（App 与设计）：
  - “路由参数在旧页面上不生效”：阶段 4 部分已处理。.logs 的 user / model / modelSource 经 LogsRoute.conditions 生效（S4-05 起）；.analytics 的 range（S4-12 / S4-13，有记忆时用记忆）、focus（S4-13 首次滚到 RPM / TPM 卡）、metric（S4-16，优先并写回记忆）都已生效。
  - “跨 Tab 跳转撤不掉视图式推入的页面”：阶段 4 部分已处理，见 (5) X39。
  - “现有页面按手机时区显示的时间”：统计与日志已全部按站点时区；剩下的 ListFields 时间列、按规格用本机时区的账号过期时间（U53）与公告起止不属于阶段 4。
  - “区块 429 倒计时文案与重试按钮”：统计各卡经 AnalyticsCardStatusRow 用 BlockFailureRow（按钮“重试本项”，S4-13 有 UI 用例）；使用记录与请求详情的 429 等待改按设备时钟（`cf34f8f`、`615c3ef`）。按请求 ID 查使用记录遇 429 不记等待，留给阶段 6 接入入口时处理（BACKLOG）。
  - “缺失值‘—’的读屏”：统计与使用记录统一读 DisplayFormat.missingSpoken（“无数据”），最终文案待用户确认。
- 阶段 4 子表里早先各条留给收口的行（S4-20 已在 BACKLOG 写补充行）：
  - 已处理、可关闭：页面状态注册表只对 AppRoute 推入的页面生效；删除 PerformanceTrend 的 Decodable 与 init(from:)（S1-09b 已删）；首页退路每小时图的账号成本；旧趋势页的残留清理；AnalyticsCardFoot 的 meta 为空时读屏带“ · ”；AnalyticsUITests 旧用例接受占位标题“图表”；路由参数（X39）补记；自定义范围日历的“今天”高亮（S4-13 截图核对没有错位）；BACKLOG 359、363 两行（S4-18 已实现）。
  - S4-20 决定保留或暂不改：RequestLogFilter 五个旧条件与 cacheTokens；.analyticsChart 非计费键保留占位；OpsErrorTrend.bars(in:) 保留（40 §2.7 点名用例的被测对象）；用户用量趋势按请求时区对齐桶；使用记录用户胶囊文字暂不统一。
  - S4-20 未评估：Token 使用趋势长范围性能（需要真机或模拟器交互测量）。
  - 后端：B03（dashboard/groups 的 model_source）已由后端 dd80618fe 修复，App 无需改动，请集成者核对生产部署后在后端表注明。
  - “LogsStoreStateTests.swift 超过 800 行”：S4-20 把桩与夹具搬到 LogsStoreTestSupport.swift（复核：750 行 + 68 行）。
  - “S4-06 回前台一拍与计数补取”：S4-06 已处理（回前台时补发 errorCount）。
  - “请求详情 429 等待的时钟与失败行不一致”：S4-08 修正 `615c3ef`。
  - “请求详情退路：客户端已成功但查不到成功记录”：S4-08 定为“失败，后续尝试未记录”，待用户确认。
  - “模型胶囊置灰的 UI 用例”（S4-19 接入模型页后补）：材料里没有记录补没补；复核时 `c5231df` 的 UITests 里没有找到原因行文案“使用记录只能按请求模型筛选”。
  - “日志页首屏不再挂在视图的 .task 上”（提醒 S4-06）：已处理。首屏读取仍由 onAppear 起非结构化 Task（S4-05）；S4-06 的轮询挂在 task(id:) 上，键由 scenePhase、store.isVisible 与 store.autoRefreshes 组成，一拍被取消时忽略（`cca32ce` 提交说明；复核：LogsView.swift:43–49）。

#### (5) 核查结果

来源：测试清单与 D27 取自 scratch/s4-20 的一次性脚本输出（check_tests.py / tests.txt，check_d27.py / d27.txt、d27-after.txt，不入库）；D29、X39 取自 BACKLOG 阶段 4 子表里 S4-20 写的补充行；R19、文件长度、格式代码与副标题键是起草时在 `c5231df` 上复核的。

- R19 唯一定义（复核）：
  - 日志类接口：requestRecords(page:filter:maskedView:) 与 requestRecords(sinceID:filter:maskedView:)、errorRecords(page:filter:kind:) 与 errorRecords(sinceID:filter:)、errorCount(filter:kind:)、searchUsageUsers(_:) 都只在 RequestLogs.swift；errorDetail、setErrorResolved 只在 RequestErrorDetail.swift；requestAttempts 只在 RequestAttempts.swift。errorCount 另有 LiveOpsSource 的协议要求、转发实现与夹具，不算重复定义（同阶段 1 口径）。
  - dashboard/trend 的带范围读取只有 usageAnalysisTrend（UsageAnalytics.swift:305）；APIClient.dashboardTrend() 是首页退路的固定窗口读取，S4-20 方案列入白名单。
  - admin/usage/stats 除统计的汇总读取外，另有用户详情“本月消费”用的 UserManagement.userMonthUsage（阶段 3，30 §2.2；复核：UserManagement.swift:226）。R19 清单没有列 usage/stats，S4-20 方案定为只在小结记一笔、不改。
  - 各只有一处声明：UsageRequestType、OpsChartCopy、AnalyticsFanOut、AnalyticsModelName、AnalyticsTileText、AnalyticsCardLoaders、AnalyticsCardBody、AnalyticsFigureRow、BodySize、AnalyticsChartSelection、AnalyticsOpsOffCard、LogListFailure、RequestIdentifierRow、LogConditions、LogChipLabel；DisplayFormat.wholePercent、AppModel.analyticsOpsDisabled / recordAnalyticsOpsResponse、loadBillingSummary / loadBillingComparison / loadBillingTrend 各一处（后五个在 AnalyticsSession.swift）。
  - 404 OPS_DISABLED 的判定只有 AccountUpstreamErrors.isOpsDisabled 一份实现（AccountDetailSections.swift:95），GroupDetailSectionsPresentation 的同名函数只转调；没有 APIError.isOpsDisabled。
  - struct PerformanceTrend 只是 Sendable、Equatable（PerformanceTrend.swift:5），与 S4-20 的 BACKLOG 补充行一致。
  - 代码（Sources / NativeApp / Tests / UITests）0 处，其中不少名字在 docs 的进度表、BACKLOG 与规格里仍有记载：requestErrorCount、usageRecord(requestID:、OpsOverviewWindow、IncrementalLogMerger、RequestLogPage、maskedKeyView、OpsBucketLength、registryKey、errorRecord(id:、LegacyLogsEntry、RequestLogsView、AnalyticsFilterView、LegacyTrendPage、DashboardTrendChart、analyticsCardRefresh、analyticsRefreshRevision、pullRevision、AnalyticsMoreSource、AnalyticsChartScale、AnalyticsErrorStackChart、OpsTileFigure、LogRefreshCycle、LegacyRequestDestination、RequestIdentifierKind、RequestDetailActionCopy、LogConditionKind、DashboardTrendMetric / Sample / Series、clampedZoom、trendAxisLabel、longHourlyTrend、dashboardPerformanceTrend(hours:、pushesInPlace、openedRequest，以及启动参数 -ui-dashboard-detail-errors、-ui-trend-long-series、-ui-performance-error。upstreamErrorCount 只作为 OpsMonitoring 的 upstreamErrorCountExcl429529 字段名出现；PerformanceTrendView 只出现在 PerfTrendPresentationTests 的一行注释里。
  - 统计五个页面（AnalyticsView、AnalyticsChartView、AnalyticsRankView、AnalyticsMoreView、AnalyticsModelView）都挂了 analyticsPageRefresh。
  - 副标题键（S4D2b-14）：ops.switch、ops.errorDistribution、ops.tokenStats、more.reqType 为 showsInUpdateLine: false，more.userTrend.<指标> 只有 tokens 为 true，与 S4-17b、S4-18b 进度备注一致。
  - S4-20 提交说明里的 grep：两个兼容入口在 NativeApp / UITests 没有调用方（S5-06 已删旧分组详情的两个链接）；BACKLOG 行：RequestLogFilter 五个旧条件没有页面设置，cacheTokens 只在 UsageAnalytics.swift 解码。
- D29（BACKLOG 补充行，复核一致）：Sources / NativeApp 的 TimeZone.current 只剩 ServerTimeZone.device 与推送注册上报的设备时区，Calendar.current 0 处，设备时区只用于“（站点时间 UTC+8）”提示；另有两处只出现在注释里（LogsStoreState.swift:166、LogListPresentation.swift:184）。
- 格式代码（复核）：Features/Logs、Features/Analytics 与统计 / 日志的 Session 文件里没有 String(format:、NumberFormatter、.formatted(、DateFormatter()。服务端 message 是否回显（R11）、请求超时是否写死（R07）的检查：材料里没有记录。
- D27：
  - UITests 里 430 个 40 章标识（logs. / analytics. / request. / requestDetail. 前缀），22 个没在 NativeApp 字面量里匹配到。这些多是拼接或插值生成的标识，例如 logs.row.\(scope).… 在 LogsView.swift:213 由 "logs.row.\(store.scope.rawValue).\(row.id)" 生成，analytics.ops.errTrend.* 由 AnalyticsOpsBodies 把 id "analytics.ops.errTrend" 交给 AnalyticsCardBody 拼出（复核）。S4-20 对这 22 个的逐项结论材料里没有记录。
  - 旧标识清单命中 9 处：logs.mode 6 处（AccountDetailUITests:446、AlertDetailUITests:382、AppNavigationUITests:240、RequestDetailUITests:209 / 362、RequestLogsUITests:223），它仍是现用标识（LogsView.swift:143）；analytics.filters 1 处（AnalyticsUITests:78）；group.analytics、group.logs 同在 GroupDetailUITests:34 一行，共 2 处。analytics.filters 与 group.analytics / group.logs 都在 XCTAssertFalse(….exists) 里，是“不存在”断言（复核）。
  - 启动参数：UITests 用到的 -ui-* 在 NativeApp 都有解析。NativeApp 里阶段 4 的 -ui-* 删除前 34 个，其中 -ui-dashboard-detail-errors、-ui-trend-long-series 没有 UI 用例（S4-20 随 dashboardTrend() 删除）；删除后 32 个全部有 UI 用例在用。-ui-analytics-ops-gone、-ui-analytics-refresh-changes、-ui-analytics-loss、-ui-analytics-legacy-trend、-ui-rank-empty、-ui-rank-page-fail 两边都在，-ui-performance-error 两边都是 0。
- X39（BACKLOG 补充行，复核一致）：S4-20 删除 LogsView 的 navigationDestination(item:) 后，Features/Logs、Features/Analytics 没有 NavigationLink { … }、NavigationLink(destination:)、navigationDestination(isPresented:) / (item:)，一律经 AppRoute 推入。
- 文件长度（复核）：Swift 文件里只有 UITests/AnalyticsUITests.swift（830 行）超过 800，多阶段共用，S4-20 不拆、记 BACKLOG。LogsStoreStateTests.swift 拆出 LogsStoreTestSupport.swift 后 750 行。其他阶段 4 的大文件：AnalyticsOpsBodies 659、LogsStoreState 624、RequestLogsUITests 605、AnalyticsMoreUITests 585、AnalyticsCards 577 行；AppModel 455 行。
- 工程文件：S4-20 提交说明写“工程文件随删除重新生成”；generate_project.py 重新生成前后是否无差异、我们源码的 warning 数：材料里没有记录（两次 check 都是 BUILD_EXIT=0）。

#### (6) 与规格不同的取舍（阶段汇总，各条目的细项见上表备注）

- 结构与位置：统计会话状态机与记忆放 NativeApp/Session（40 §1.8 写在 AnalyticsSession.swift 内，S4D1-02）；使用记录页的状态本体在 Session/LogsStoreState.swift（S4D2a-01）；12 个图表 body 分三个文件（S4-14）；排行纯逻辑放 Session、AnalyticsModelName 放 Sub2Core（S4-15）；请求详情接口在 RequestErrorDetail.swift / RequestAttempts.swift（40 §7.7 写在 RequestLogs.swift）；dashboardPerformanceTrend 多一个没有默认值的 supportsModelFilter 参数，写在 PerformanceTrend.swift（S4-10，X29）。
- 超时：统计聚合 45 秒（R07 / U54），不是 40 §0.6 的 60 / 90 秒（S4-02）；超时后仍按读请求自动重试 2 次，待实测。
- errorCount 固定带 view=all，比告警 SLA 口径多算业务限制（S4-01，BACKLOG“errorCount 的口径”）。
- 范围上限：平均账号切换与性能趋势 31 天 + 1 小时（40 §2.7 字面 30 天，S4D1-10，待用户确认）。
- 性能趋势：近 1 小时取整后总是 60 个满桶，规格示例“只覆盖 23 秒 / 61 桶”只当版式示意（S4-10、S4-16）；性能明细照规格写“只覆盖 N 秒”（设计稿写分钟）；运维关闭时卡头只写“运维监控”，早于窗口终点当天的桶写“昨天 HH:mm”（都取自设计稿）。
- 范围与对比文案（S4-09，规格未写）：自选单天含今天写“比昨天同时”、过去写“比前一天”，多天写“比前 N 天同期 / 比前 N 天”；上月写“比 M 月”，不带年；说明行有一端不在今年时开头带年、跨年时两端都带年，单日的范围名和桶全名不在今年时也带年；自选单天的分段标题写“自选 1 天”；从今天 / 7 天 / 30 天打开自定义 sheet 时初值为本月。
- 利润：合计 = round(实际 − 账号成本)，与首页 6 格一致；账号成本列总数 = round(实际) − 利润合计，可能比计费卡的账号成本差 1 分（40 §1.4 与 §0.2 不能同时满足，S4-09 `66da4cb`）；两边利润都为 0 写“$0.00”（设计稿“—”）；“空”= 每个桶实际扣费与账号成本都为 0；旧站点逐段刷新只重读当前、读时还在进行与缺失的桶；逐段失败时全屏说明只写前半句（S4-13b、S4-14，待用户确认）。
- 计费卡：合计刷新失败时也隐藏增减行（规格只写了对比失败，S4-13 `252ebd7`）。
- 统计会话：记忆只在用户改动时写入（S4D1-03，待用户确认）；每个卡键只存当前一份缓存，切回之前的范围会重新请求（40 §2.6 写按（范围、筛选）缓存到会话结束，BACKLOG“统计会话按（范围, 筛选）保留多份缓存”）。
- 排行：刷新时丢弃另两段缓存（S4-15，待用户确认）；旧站点没有 total_users、构成条不足 3 行、未分组、空名称、映射口径未映射行等规格空白处按默认实现（BACKLOG，待用户确认）。
- 更多图表：主题高亮按越过吸顶条下沿的可见行判定（LazyVStack 下 scrollPosition(id:) 不随滚动更新）；Token 配色按规格（缓存读横纹，与设计稿不同）；请求类型降级一类失败整卡失败（更早服务端的 cyber / live 回 400 也会让降级整卡失败），第 5 类 Live 的样式交 UI 审查（S4-17b）；没有“选中”行的图不接点选（S4-18、S4-19）；40 §2.3 六张图的磁贴行不做（S4-14、S4-18b）；错误趋势按页面范围的桶给柱，单天 3600 秒桶按小时，60 秒与 3600 秒桶的底注句式按 BACKLOG 建议（S4-18）。
- 模型页：速度区在没有 ops.dashboard_model_filter 时，请求口径用 top_n=100 找同名行，上游 / 映射口径写 —（规格写 top_n=10，S4-19）；不显示平台名（U36）。
- 使用记录：首屏读取放在 onAppear 的非结构化 Task 里（S4-05）；429 等待期间被挡住的读取显示倒计时失败行；再选同一时间预设不重读；时间与条件胶囊按设计稿用选中样式；LogRow 不画 chevron；用量段模型胶囊的第三种置灰（S4D2a-13）；分段计数取数中只写段名、≥ 10,000 写 12.3K；400 只在有生效条件时给“清除筛选”；首字与总耗时都缺只写一个“—”、自定义时段标题与空态、不在今年的节头带年份、30 天提示只给自定义范围、列表行不做业务限制灰（列表项没有 is_business_limited）（S4-04）。
- 自动刷新（S4-06）：组合 LogListPolicy / LogPollSchedule，不建 LogRefreshCycle；加了 pendingTrim，只有轮询合并后超过 N 才裁尾或挂起到回到顶部；没有可续行时静默读第 1 页；用行的 onAppear / onDisappear 近似第一个可见行（List 不支持 onScrollTargetVisibilityChange）；间隔用设备时钟；上游错误不校准；自动刷新失败用列表末尾失败行并按 BlockRefresh 退避；加载更多或下拉刷新失败时暂停轮询，直到用户重试。
- 按对象筛选（S4-07）：搜索框不自动聚焦；某组 0 行整组隐藏；停用分组不标“停用”。
- 请求详情：分区编号按设计稿，从“耗时”起编“壹”（S4D2a-14，待用户确认）；已恢复但查不到成功那次时写“失败，后续尝试未记录”；成功样子读链时不放占位、2 次及以上才显示、读链出错就隐藏；详情 OPS_DISABLED 时尝试区隐藏；详情 404 整页带“返回”；名称缺失的关联行即使有 id 也不可点；服务端请求 ID 为空不显示；从下级页返回不重读；logs.detail.cost 的语义变为“账号成本”（S4-08）。日期写“M/d HH:mm(:ss)”，月日不补零；退路耗时按 duration → at − started → 相邻 at 差（标“约”）→ — 的顺序取；除 OPS_DISABLED 外的 404 都走退路；没实现 pathSegment（编码交给 URLComponents，避免“%”编码两次）（S4-03）。
- 规格勘误（S4-11）：40 §5.2“映射后的不同上游名”应为“映射到同一上游名的不同请求模型”。
- 标记已处理（S4-08b）：撤回与撤销成功不出回执，撤回失败写“撤回失败，请重试”；没收到应答时读回一次核对；本机标记后“已处理 · 人 · 时间”等下次读到详情才出现；处理人显示后端给的邮箱；详情已知运维关闭时按钮不预先置灰。
- 旧服务端不发 key_view（S4D1-06，待用户确认）。
- vendor 规则按 U01 不做（S4-14、S4-19）。

#### (7) 未做项及原因

- U54 与 30 天 usage/stats、throughput-trend 实测：未获授权访问测试环境（S1D1-27）。客户端超时维持统计聚合 45 秒，实测超过 45 秒时再决定是否放宽到 90 秒、超时后是否还自动重试（BACKLOG“30 天 usage/stats 与 throughput-trend 的实测（U54）”，后端 B10 / 维护者 Q17）。
- RequestLogFilter 的 apiKeyID / requestType / category / resolved / statusCode 与 AnalyticsSummary.cacheTokens 保留：40 §6.7 允许留作内部用，第 2 波其他线可能仍在引用（S4D2b-18 ①）。
- AnalyticsUITests.swift 830 行未拆：多阶段共用测试文件，S4-20 不重构（同 S1D1-14），下次加用例时按主题拆。
- 利润明细卡“最近 4 段”私有表没有换成 AnalyticsDetailTableView(limit: 4)：S4D2b-09 ④ 的可选项。
- 使用记录用户胶囊文字暂不统一：等用户决定。
- .analyticsChart 非计费键保留占位：应用内没有入口（40 §3.1）。
- Token 使用趋势长范围（自选 366 天约 1,500 个 RectangleMark）性能未评估：需要模拟器或真机交互测量，留到真机验收。
- 用户用量趋势回执时区与请求时区不同时没有统一按回执时区重建桶：出现实际案例再改。
- 筛选 sheet 分组占比读取失败没有提示：要改 S4-12 的文件，S4-13 延后到 UI 审查。
- 运行类图表的全屏尺寸、请求类型全屏 12 行没有界面入口，只有单测（40 §3.1 不给运行类图开单图页）。
- 模型页速度区“读到 OPS_DISABLED → 重新开启运维 → 恢复”没有 UI 用例：AnalyticsFixtures.modelSpeed 不认 -ui-analytics-ops-gone，只有单测（BACKLOG）。
- 模型页速度区在运维开启后 30 秒同步期内如果又碰到 404，过去范围要等下一次回前台、再进本页或下拉刷新才恢复：按 S4D2b-02 ③ 不另加读取循环（S4-19 修正 `c5c84d3` 的备注）。
- RPM / TPM 卡在 404 宽限期内的卡头小字：刚开启运维的 30 秒内接口仍可能回 404 OPS_DISABLED，卡体显示“运维监控未开启”组件，卡头小字却仍写“截至现在 · 运维监控”（卡头只读 analyticsOpsDisabled）；要一致需要让卡头读到卡片状态（BACKLOG）。
- Token 请求统计随模型筛选重读：卡键 ops.tokenStats 的 scope 是 .rangeAndFilter，请求本身不带 model，换模型筛选也会重发一次 45 秒聚合查询；要省掉需要给会话加“只跟分组变化”的 scope（BACKLOG）。
- 30 天提示、模型胶囊置灰只有单测（S4-05b）；使用记录分段计数的逐项读屏没处理（SwiftUI 分段控件的逐项 accessibilityLabel 不生效）。
- 请求详情按请求 ID 查使用记录：夹具 requestUsageRecord 还没有脚本、遇 429 不记等待，留给 S6-20 / S6-21 接入搜索入口时处理。
- 后端相关，App 维持默认值，交后端维护者：规格未决问题 U32（错误日志列表项加 upstream_status_code）、U33（使用记录加 billing_provenance）、U34（error-trend 加只计 status ≥ 400 的上游分项）；BACKLOG 里的 resolved_by_user_name 取的是邮箱、PUT …/resolve 不回处理时间与人，Token 速度多行合并只能按 request_count 近似加权（精确需要后端在 items 里加 requests_with_tps），日志列表项加 is_business_limited（BACKLOG“日志列表行的业务限制灰”，现在列表行不做业务限制灰）。错误分布占比的分母是 LIMIT 20 之后的合计：照规格用响应 total，记为已知限制（BACKLOG）。B03 已由后端修复，不列入未做项。
- vendor（代运营工作区）规则：按 U01 首版不支持 vendor 登录，只保证结构不妨碍以后加。
- 需要用户拍板的事项按默认值实现：BACKLOG“阶段 4 待用户拍板的取舍”一行汇总了 20 项（S4D1 三项、批次 2a 七项、批次 2b 九项、dag.md 第 8 节第 8 条长范围计数照取）；BACKLOG 阶段 4 子表另有标了“待用户确认 / 待定 / 留给 UI 审查”的行，以及缺失值读屏的最终文案。

#### (8) UI 测试运行情况

- 各条目自己的 check（取自上表备注）：
  - 没跑 UI（无界面改动、ui_test_classes 为空，check 输出 UI_SKIPPED）：S4-03、S4-04、S4-09（单元 1735 + 514）、S4-11。
  - S4-00：AppNavigationUITests、Sub2MobileUITests、SettingsUITests 50/50。S4-01：RequestLogsUITests、AppNavigationUITests 19/19。S4-02：5 个类 39/39，无重跑。S4-10：Sub2MobileUITests 22/22。S4-12：两次提交前与审查修正后 SettingsUITests 各 13/13。
  - 使用记录与请求详情：S4-05 5 个类 86/86；S4-05b 5 个类 88/88，修正后 RequestLogsUITests 18/18；S4-06 47/47，无 flaky；S4-07 65/65；S4-08 49/49，无重跑；S4-08b 65/65，无重跑。
  - 统计：S4-13 两次 64/64、75/75，无重跑；S4-13b 22/22，修正后 23/23；S4-14 AnalyticsUITests 27/27；S4-15 32/32，无重跑；S4-16 a 71/71、b 76/76，无重跑；S4-17 38/38；S4-17b 43/43；S4-18 AnalyticsMoreUITests 14/14；S4-18b 50/50；S4-19 62/62。
  - 审查修正（scratch 下的 S4-xx-fix-check.log 与 S4-19-review-check.log，SYNCED 都是修正提交的父提交加未提交文件）：S4-05 `cf34f8f` 11/11；S4-06 `d210f18` 38/38；S4-08 `615c3ef` 56/56；S4-08b `9325417` 65/65；S4-13 `252ebd7` 19/19；S4-15 `ea63652` 37/37，AnalyticsUITests.testProfitCardShowsTotalLatestFourRowsAndSelection 重跑后通过；S4-16 `f1d4575` 44/44；S4-19 `c5c84d3` 35 个通过 34 个，RequestLogsUITests.testScrollingToEndLoadsNextPageOnce 两次都失败（check 日志写于 11-02 00:04，正跨零点，对应 BACKLOG“LogFixtures 零点边界”），随后 RequestLogsUITests 单独重跑 21/21 通过（S4-19-review-ui-logs.log）。S4-05b、S4-12、S4-13b 的修正数字见上面各行。
  - 审查修正没有 check 日志、材料里也没有记录 UI 数字的：S4-00 `af21d72`、S4-03 `ad7d8d4`（随 S3-02 合入）、S4-09 `66da4cb`。
- S4-20 的两次 check（13 个 UI 类：RequestLogs、RequestDetail、Analytics、AnalyticsRank、AnalyticsMore、AppNavigation、Home、Sub2Mobile、AccountDetail、AlertDetail、UserDetail、Groups、GroupDetail）：20a（`1f89476`）单元 2700 + 1323、编译通过、UI 255/255，AnalyticsMoreUITests.testMoreChartsPullToRefreshRereadsLoadedCards 重跑后通过（进度备注称为既有不稳定用例）；20b（`4498506`）UI 255/255，没有重跑。
- 集成者合入后（scratch 里的集成日志）：
  - check：S4-01 `cb30803` 19/19；S4-00 `cc430d2` 50/50；S4-10 `beb7f8c` 22/22；S4-03 `1a057d4` 17/17；S4-09 `580a80f` UI_SKIPPED；S4-05 `f4c8e6c` 86/86；S4-13 `21b3ce0` 75/75；S4-05b `add157a` 88/88；S4-15 `0b0b9b0` 33/33；S4-14 `404ac75` 37/37；S4-16 `b055c30` 111/111；S4-19 `2d1bb04` 79/79；S4-07 `94d8f34` 94/94；S4-08b `b4e1b0a` 65/65，修正合入 `65d0aff` 65/65；S4-17b `8128f03` 60/60；S4-18 `7962290` 14/14；S4-18b `ceb95d5` 50/50；都没有重跑。S4-02、S4-04、S4-06、S4-08、S4-11、S4-12、S4-13b、S4-17 的合入后日志 scratch 里没有找到。
  - 全量 gate：S4-00 合入后 `cc430d2` 89/89；S4-09 合入后 `580a80f` 309/309；S4-14 合入后 `404ac75` 724/724，AnalyticsUITests.testProfitCardShowsTotalLatestFourRowsAndSelection 重跑后通过。
  - S4-20 合入后（合并提交 `c5231df`）：check 13 个类 255/255，AnalyticsMoreUITests.testMoreChartsPullToRefreshRereadsLoadedCards 重跑后通过；全量 gate 的 TOOLCHAIN_EXIT=0、UNIT_EXIT=0（2718 + 1342）、BUILD_EXIT=0，UI 829/829，重跑后通过的只有 GroupEditUITests.testDuplicateNameShowsRedTextAndGreysCreate（阶段 5 的用例），没有两次都失败的用例。这次 gate 作为阶段 4 的收尾。
- 已知的不稳定与夹具边界（BACKLOG）：AnalyticsMoreUITests.testMoreChartsPullToRefreshRereadsLoadedCards（S4-20 两次碰到，重跑通过）；UI 测试里自动刷新 2 秒一拍时，时间胶囊菜单的第一次点按偶尔被列表重绘吞掉，用例已改为最多重试三次；RequestLogsUITests.testScrollingToEndLoadsNextPageOnce 在 Mac 本地时间 00:00 后约 1 分钟内运行必定失败（“LogFixtures 零点边界”，S4-19 修正的 check 就碰到了），站点时间 23:58–24:00 之间“今天 / 昨天”断言也可能失败；-ui-testing 下测试组筛选时运行类夹具之间不一致，只影响演示数据。

## 阶段 5 · 分组

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S5-01 | 分组模型、读接口与带幂等键的写接口 | ✅ | `af0c7df`、`2c8f401` | 分读、写两次提交（S5D1-11）。删除遇 404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND 在 Core 映射为 alreadyGone；groupList 最多 20 页；usage-summary 与 dashboard/groups 超时 45 秒；Core 拒绝 composite；旧分组页提示去掉“用同一编号重试”；容量分批复用 readInBatches，serverFiltered 时结果按 id 升序。页面（S5-04 起）、成员批量（S5-03）、groupAPIKeys / groupSubscriptions（S5-12）不在本条。GroupsUITests 两次各 2/2 通过 |
| S5-02 | 分组展示与权限纯函数（GroupPresentation / GroupPermissions） | ✅ | `6cf1c50`、`767f36c` | 分两次提交（S5D2a-18）：GroupPresentation + 25 个用例；GroupCopy + GroupPermissions + 17 / 12 个用例（新增 files 之外的 GroupCopyTests.swift）。取舍：最早恢复按 S5D2a-02 取“每个成员最晚的进行中窗口、再取全组最早”，并列写“恢复 n 个 · X 等”，另外只算开着调度的限时成员（错误、停用、停调度的不会因为窗口结束而恢复）；删除后果行在 stats 拿不到时写不带数字的 Key 行和“删除这个分组的全部订阅记录。”，简易模式不写成员行（S5D2a-03）；删除标题、首行和回执用 S3-00 的 DeleteConfirmationCopy，本条只给 objectNoun 和后果行；订阅限额整数写 0 位、非整数写 2 位；倍率按 0.6 写 ×1.0 / ×1.25，与用户页 ×1 并存；主按钮被隐藏时不改派；编辑时停用改回正常写“启用分组”但不确认，同时停用不算归零；详情副标题里接口没给的字段省略；GroupListSection.Kind 与 AppRoute 的 GroupListSegment raw 值一致（互转和断言归 S5-04）。纯 Core，UI 测试未运行（ui_test_classes 为空，两次 check 均为 UI_SKIPPED） |
| S5-03 | 成员批量写入协议 GroupMembers（请求、结果、回执、撤销、重试、老服务端退路） | ✅ | `e7abfd5` | 拆成三个文件 GroupMembers / GroupMembersLegacy / GroupBatchOutcome，另把 ReasonCatalog.displayCode 移出 private 扩展（行为不变）；R06 的同体重发 1 次范围是传输失败、408、502、504、无 reason 的 503，进后台不重发，换会话取消；超过 200 个按批顺序发，第一批失败照抛，后续批可能已执行的记 REQUEST_UNCONFIRMED（结果未确认，可以重试），被明确拒绝的记其 reason，没发出的批记 REQUEST_NOT_DELIVERED，2xx 答复里缺的账号也记 REQUEST_UNCONFIRMED（S5D2a-17）；退路逐账号 GET 后 PUT 只带 group_ids，已在目标状态不发 PUT，有 admin.idempotent_writes 时每个 PUT 用新 key，老服务端无 reason 的 409 经 check-mixed-channel 取平台，简易模式不得使用退路、由 S5-08 拦截；新增文案列入需要用户拍板第 11 条；纯 Core，未跑 UI 测试（ui_test_classes 为空，check 显示 UI_SKIPPED）；推送时 GitHub 不通，提交只在本地线 A 分支（审查修正 a69ef8a）审查修正 a69ef8a：R06 同体重发如果在处理器之前被拒（401/403/423/429、503 STEP_UP_UNAVAILABLE）、收到没有 reason 的 4xx，或者重发没发出（.refreshDeferred），改抛第一次的错误，即按结果不明处理，后续批次记 REQUEST_UNCONFIRMED；逐账号退路在进后台、读取被取消时保留已经改动的账号，返回部分结果。取舍：APIError 不记录回复体是否为 JSON，所以“没有 reason 的 4xx”一律按非 JSON 处理，只会偏向“结果未确认”。 |
| S5-04 | GroupStore 与分组列表（只读）：三段分区、三行行、色格条、夹具 | ✅ | `9d16582` | 缺失值的读屏：分组行“今日 —”读作“今日无数据”（DisplayFormat.missingSpoken，与用户列表同写法）；不建 -ui-group-legacy，旧服务端用 -ui-without-capabilities（X05）；usage-summary 刷新失败保留上次成功的值，从未成功才显示“今日 —”（S5D2a-15）；status-summary 失败或 403 时 shortage 置空、退回本地 50% 判定；F04 退路还没读到时错误计 0（落在暂停·停用），读失败保留上一次，只读一页 1000 个错误账号；底注先按规格全文显示（滑动和长按由 S5-05 / S5-08 加）；分组目录的 -ui-testing 分支改读 GroupFixtures 的实时计数（S5D2a-11），DemoData 里的静态计数只在会话外使用；.groupEdit 临时接旧编辑器（LegacyGroupEditSheet），id 不在 store 里时显示“找不到这个分组”、不会变成新建；旧写入口作为 extension GroupStore legacy* 留在 GroupsView.swift，随 S5-10 删除；按 S5-02 实际签名消费，没有建 buckets(for:) / health(for:) / entries / isSimpleMode / counts(fromStatus:) / errorAccounts(in:)；AccountDetailUITests 同步了入口标识；check（GroupsUITests、AppNavigationUITests、AccountDetailUITests、AccountEditUITests、HomeUITests）118 个用例全部通过，首次骨架和 60 秒轮询只有单元测试与代码审查覆盖（审查修正 792805c）审查修正 792805c：分组列表的列表、usage-summary、status-summary、F04 退路各自单飞（新增 NativeApp/Session/BlockRead.swift），慢区块和列表的 429 等待不再挡住重试、下拉和其余区块。refreshAll 拿到列表就返回；列表、shortage、退路保证读取不早于调用，写入后的静默刷新拿得到写入后的数据。新增夹具 -ui-group-usage-slow 和两条 UI 测试。usage 与 shortage 区块自身收到 429 时仍没有各自的等待（沿用原状），已记入待办。 |
| S5-05 | 分组动作 GroupActions：停用 / 启用 / 复制 / 删除，接入列表滑动与长按菜单 | ✅ | `5807668` | 结果不明时自动读回一次，定不了再在回执给“用同一编号重试 / 重试 / 核对”（S5D2a-06，拍板第 4 项）；5xx 按结果不明；停用确认与删除后果行的 stats 最多等 2 秒，拿不到时去掉数字，删除时写不带数字的 Key 行与“删除这个分组的全部订阅记录。”，简易模式不写成员行（S5D2a-03，拍板第 2 项）；撤销成功不再出回执；旧详情“管理”分区过渡为 GroupActionMenuItems，删除先出栈（S5-06 换新详情）；首页刷新接线留给 S5-13；GroupActionSource.sendGroupUpdate 多收 request，GroupActionStore 精简为 GroupStore 现有方法，store 改为闭包；GroupStore 的 legacyDelete 已无调用方，留给 S5-10 整文件删除；UI 测试：check 跑 GroupActionsUITests 6 个、GroupsUITests 14 个，以及 AccountDetailUITests 分组过渡、AppNavigationUITests 分组入口各 1 个，共 22 个全部通过（审查修正 9fcf6eb）审查修正 9fcf6eb：不带 key 的删除或停用读回后未生效时，“重试”改为重新弹确认（删除重新输入名称或验证 Face ID，R05 / R16），启用与撤销仍直接用新编号再发；从详情删除时详情已出栈，“没有生效”与“需重新操作”两种回执都不带按钮，从分组菜单重新删除。 |
| S5-06 | 分组详情（一）：数据模型、状态卡、按钮行、成员分区（只读）与 404 | ✅ | `17ccc0f` | 最早恢复按每个成员最晚的进行中窗口再取全组最早（S5D2a-02，S5-02 实现）；主按钮被隐藏不改派，“添加账号”等 S5-08；404 页标题“分组”；分组读取失败有快照时中性横幅、无快照时整页“读取分组失败”；回前台按下拉处理并重读 stats，60 秒轮询从上一轮结束算、被页面取消的一轮不计；可用偏低只在分组正常且 active > 0 时读；成员为 0 时显示“没有成员账号”占位；成员今日夹具按组拆分（高级组 $380.98）；用 GroupStore.fetch(id:)，未建 replaceRead；删除旧详情、GroupDestination 及 AccountsView(initialGroupID:) / AnalyticsView(groupID:) / RequestLogsView(groupID:) 调用，删除 AccountDetailUITests 过渡用例；check 6 个 UI 类 109/109 通过、无 flaky（审查修正 8026f9f）审查修正 8026f9f：详情页进入时加载分组目录，成员行的本组按 id 用页面自己的名称，lite 行没带组名时也不会把本组写进“另属”；老服务端 Key 与订阅数退路改为 stats 返回 nil 后再判断是否订阅分组（Sub2Core GroupKeyCounts.read），类型未知时照读生效订阅数。 |
| S5-07 | 分组详情（二）：告警横幅、用量与容量、记录与关联、配置 | ✅ | `d300fe6` | 简易模式贰只留今日请求行、肆只留描述与 Web 行，序号固定贰叁肆，不建 GroupDetailSectionOrdinals / reloadCapacity（S5D2a-10、13）；横幅更早时间写 MM/dd HH:mm（S5D2a-14），规则摘要按 R10 写“5.0%”；横幅、三栏、今日行、容量刷新失败保留旧值不提示（S5D2a-15），OPS_DISABLED 横幅立即消失；容量按 50 §2.3 顺序并发 · 会话 · 调度 RPM，复用 CapacityBar；横幅与计数经 LiveOpsStore 读 LiveOpsFixtures，手动解决后返回横幅消失；日志页断言接受“使用记录”或“请求与错误日志”；只有 canEdit == .enabled 时配置行可点；UI 用例是实现后补写的；check（GroupDetailUITests、GroupsUITests、GroupActionsUITests）36/36 通过（审查修正 6f25f77）审查修正 6f25f77：从其他页面得知运维监控已关闭（如在监控页关闭）后，分组详情的横幅立即消失，两条错误计数改写“运维监控未开启”，不再等下拉或重进；运维重新开启后先恢复上次读到的值，下次读取再更新。 |
| S5-12 | 分组 API 密钥页与分组订阅页 | ✅ | `e90e4e7` | 最近使用更早写 DisplayFormat.monthDayClock（MM/dd HH:mm，跨年加年份，S5D2a-14），不写规格的 MM-DD；订阅页自己读 groups/:id/stats（路由只带 id），stats 出错不走退路（同 S5-06），老服务端回 nil 才读 activeSubscriptionCount；400 不自动重发但保留手动重试与下拉；刷新失败保留旧行与旧金额（S5D2a-15）；翻页提示按 page_size 20；新增 GroupRecordsPresentation / GroupRecordsModel / GroupRecordsChrome 三个文件；夹具总数取 S5-05 的 stats 表，与用户页 Key 卡片不联动；未加方案里的 usage-failure / key-view-rejected 两个启动参数（单测覆盖）；后端 subscriptions 不拦简易模式（入口已由 S5-07 隐藏，交 S5-13 核对）；check GroupRecordsUITests,GroupDetailUITests：UI 24/24 通过，GroupDetailUITests 未改 |
| S5-08 | 成员写入：成员左滑（状态动作、移出）与添加账号 sheet | ✅ | `f743de1` | 分两次提交（`4eaa907` 写入核心与成员行动作，`f743de1` 添加账号页与入口）；.groupBatch 在 S5-09 之前为占位页；-ui-group-batch-partial 按 S5D2a-12（只对未确认的 add：id 最大的 ACCOUNT_NOT_FOUND，Anthropic / Antigravity 中 id 最小的 MIXED_CHANNEL_RISK）；简易模式不走逐账号退路；首页刷新由 S5-13 接（成员写包装未套 recordingAccountWrite）；vendor 分支（隐藏加减成员入口与底注）只有单测；移出确认框复用 GroupConfirmation；状态动作后靠重拉成员刷新该行；组合分组选择页用“搜索账号”“账号都已在这个分组里”等措辞；选择页候选只拉 200 个；UI：check 实跑，五个类 74/74 通过（审查修正 67f5b62）审查修正 67f5b62：加入的重试被拒时补出回执；回执中的“可用 x”在字段缺失时按 0 计；选择页自己加载分组目录；batch-partial 夹具改按 S5D2a-12（单个加入也会给 MIXED，confirm 为 true 时 NOT_FOUND 规则照旧）。 |
| S5-09 | 成员批量写入逐项结果页（groupBatch）：重试、撤销、混合渠道确认 | ✅ | `a05d198` | .groupBatch 携带 RoutePreload<GroupBatchOutcome>，showGroupBatch 只改函数体，X39 的 .groupBatch 结果已生效（BACKLOG 由 S5-13 收口）；GroupBatchResultModel 先原样重发、再单独发混合渠道批（确认后带 confirm），取消确认整次不发，撤销发反向请求，请求级失败红字取 GroupMemberSendResult；发送只经 GroupMemberWriter.send。取舍：GroupAccountStateGlyph 为 AccountStateGlyph 的别名，不改 AccountRow.swift；无失败时成功区序号为“壹”（同设计稿）；“s 个成功”与成功区 meta 用未撤销成功数，按钮用可撤销数；行状态用提交时快照（无会话级账号缓存）；本页不过 Face ID。UI：check GroupMembersUITests、AppNavigationUITests、GroupDetailUITests 共 48 个全部通过，含新增 3 条 |
| S5-10 | 编辑 / 新建分组 sheet：表单、校验、确认、带 key 写入与核对（成员区除外） | ✅ | `9b91d05` `8089b6f` | 分两次提交（Core+Session；视图+夹具+UI 测试）。GroupEditDraft 放 Sub2Core，另加 GroupEditCopy / GroupEditFlow / GroupEditForm / AppGroupEditSource；名称按 UTF-8 ≤ 100 字节；平台下拉取目录与 App 内置平台的交集；结果不明（含 5xx）自动读回一次，再给手动核对与用同一编号重试；编辑遇 404 锁表单；简易模式新建脚注只写“平台创建后不能修改。”；去掉 onWritten；没建 interruptFirstCreate（S5-05 的 interruptFirstWrite 已覆盖新建）；费率框不设占位；删除 GroupsView.swift；testGroupEditorValidation 并入 GroupEditUITests；GroupDetailUITests 同步两处编辑 sheet 标识；成员区留给 S5-11。UI：check 5 类 65/65 通过（GroupEditUITests 11 个新用例）（审查修正 1101418）审查修正 1101418：编辑分组时，名称只在用户改过之后才提交。存量首尾带空白的名称不会再被悄悄改名，也不会让未改动的表单可以保存。（审查修正 64f8318）审查修正 64f8318：GroupEditUITests 启动后先等登录页，reveal 读导航栏前先判断存在，修掉负载高时启动后窗口还空、读导航栏 frame 约 2 秒后失败的偶发问题（测试时序，App 没改）。check GroupEditUITests 连跑 3 次，都是 17/17。 |
| S5-11 | 编辑 sheet 的成员账号区、内嵌添加账号页与保存后成员写入 | ✅ | `518caa5` | 在 GroupEditFlow 上扩成员（不建 GroupEditCommit，S5D2a-09），合并回执在 GroupEditFlow+Members.swift；编辑 / 新建 sheet 的成员回执全部成功不给撤销（需要用户拍板第 5 条），重试后的回执也不给；“（现在 y）”只在 x ≠ y 时出；成员在 sheet 打开时自读（最多 20 页）；结果不明时先自动读回一次，确认生效才发成员写入，选“稍后核对”关闭时成员改动不发；只改成员时不发 PUT、不生成编号，归零照常 destructive 确认；简易模式不走退路也不显示退路提示；新增文案“<前缀> · 成员没有改动：<原因>”（需要用户拍板第 11 条）；不改 AccountRow.swift，状态图形复用 GroupAccountStateGlyph；添加账号子页用 navigationDestination(isPresented:) 推出，iOS 26 的系统返回按钮可能只画箭头；GroupEditForm 改为泛型接成员区（401 行）；UI 测试 check GroupEditUITests,GroupMembersUITests,GroupsUITests,GroupDetailUITests 60/60 通过（审查修正 a939926）审查修正 a939926：只改成员时，成员写入被拒会留在 sheet 显示红字并保留草稿，不再关闭并显示“已保存「名称」 · 成员没有改动：…”；只改成员且没有任何成员改成功（结果不明 / 全部失败）时，回执去掉“已保存「名称」”前缀。先 PUT 后写成员和新建两条路径不变。check 运行了 GroupEditUITests、GroupMembersUITests，31/31 通过。 |
| S5-13 | 阶段 5 收口：简易模式、只读令牌与旧服务端核查、QA 对账、文档 | ✅ | `81cfa6d` `888ec28` | 分两次提交（13a 夹具 / 接线 / 清理 / 测试，13b README 与 ADMIN_MODULES）；-ui-simple-mode 只改 DemoData.adminMe 的 run_mode，夹具在新文件 GroupFixtures+SimpleMode（白名单响应、不列组合分组、403 / 409 GROUP_NOT_EMPTY / 400 SIMPLE_MODE_GROUP_NOT_BINDABLE、按后端规则清理写入；-ui-group-simple-unbindable 用来验证组合分组文案），接线只在 GroupStore、两个数据源适配层和成员写包装的夹具分支，没改 GroupFixtures.swift；GroupWriteMark 包住六个写方法，用来通知首页刷新（X17），没改 LiveOpsStore 和三个视图文件；删除 AccountsView(initialGroupID:)、AccountListModel.groupID 与 -ui-account-group-transition 夹具（X32）；前序页面没有简易模式缺口，未改页面代码；成员今日对账在 UI 上只核对“不超过”（限流行显示恢复时间）；简易模式新建请求体仍带默认计费字段（后端覆盖），订阅不回 403；静态核查结果见阶段 5 小结；新增 QA 单测 2 条、UI 用例 14 条；check：13a 13 个 UI 类 244/244，13b 9 个类 132/132，没有重跑才通过的用例 |
| U-10 | 分组列表 · 刷新失败时保留上次的“今日”与“可用偏低”判定，顶部细条标“更新失败 · 重试” | ✅ | `419ba44` | shortage 改为 BlockState（shortageState），刷新失败保留上次判定；usageStale / shortagesAreStale 用 GroupStoreRules.isStale（复用 homePhase），刷新进行中不算陈旧；列表细条之下另起一节“更新失败 · 重试”，右侧小字为 staleItems（自拟，待看截图）；偏离清单的“行旁小字”改为顶部细条（行第三行已满，待用户确认）；shortage 单元测试改放 Sub2CoreTests；首读失败不出细条的断言并入 testUsageFailureShowsDashOnEveryRow。check：GroupsUITests、AppNavigationUITests、GroupDetailUITests 共 58/58 通过，无重跑 |

### 阶段 5 小结

#### (1) 完成项

- S5-01 `af0c7df` `2c8f401`：分组模型与接口。AdminGroup 补四桶计数与客户端限制字段；读接口包括 groupList（1000 一页、最多 20 页）、usage-summary 与 dashboard/groups（45 秒）、groupCapacities（按 00 §4.5 拆批）、groupStats（老服务端回 nil）、Key 与订阅退路计数。新文件 GroupWrites.swift 放带编号的 GroupWriteOperation、GroupWriteDraft（最后一次确认时生成编号，R05）、GroupDeleteResult，以及四个只收 operation 的写方法。404 在 Core 里映射为 alreadyGone；新建分组在 Core 里拒绝 composite（GroupPlatform.concrete）。
- S5-02 `6cf1c50` `767f36c`：展示、文案与权限纯函数，分 GroupPresentation、GroupCopy、GroupPermissions 三个文件。内容有四桶与 F04 退路、健康判定、色格条、列表分段与格式、确认框文案、删除后果行和“最早恢复”。菜单、滑动、按钮行和字段权限只在这里定义（S5D2a-01、S5D2a-04）。
- S5-03 `e7abfd5`（修正 `a69ef8a`）：成员批量写入协议，分 GroupMembers、GroupMembersLegacy、GroupBatchOutcome 三个文件。内容有请求去重与每批 200 个、结果解码、回执、撤销用的反向请求、R06 同体重发、REQUEST_UNCONFIRMED / REQUEST_NOT_DELIVERED 两个标记，以及老服务端的逐账号退路。
- S5-04 `9d16582`（修正 `792805c`）：GroupStore 与只读的分组列表：三段分区、三行的行、色格条和分组夹具（GroupFixtures）。分组目录在 -ui-testing 下与分组夹具同源。修正后，列表、usage-summary、status-summary、F04 退路各自单飞（新文件 BlockRead.swift）。
- S5-05 `5807668`（修正 `9fcf6eb`）：GroupActions 的停用、启用、复制、删除，接入列表左滑与长按菜单。5xx 按结果不明处理，结果不明时自动读回一次。修正后，不带 key 的删除或停用读回发现没有生效时，“重试”会重新弹确认。
- S5-06 `17ccc0f`（修正 `8026f9f`）：分组详情（一）：数据模型、状态卡、按钮行、成员分区和 404 整页。删除旧详情、GroupDestination，以及对 AccountsView(initialGroupID:)、AnalyticsView(groupID:)、RequestLogsView(groupID:) 的调用。
- S5-07 `d300fe6`（修正 `6f25f77`）：分组详情（二）：告警横幅，以及“贰 · 用量与容量”“叁 · 记录与关联”“肆 · 配置”三个分区。修正后，会话一旦得知运维监控已关闭，横幅立即消失。
- S5-08 `4eaa907` `f743de1`（修正 `67f5b62`）：成员写入的唯一入口 GroupMemberWriter；成员行左滑（状态动作、移出）；添加账号页及其入口（列表右滑与长按、详情按钮行与 ⋯、成员分区的添加行）。
- S5-09 `a05d198`：成员批量写入的逐项结果页（.groupBatch 携带结果）：重试、撤销、混合渠道确认。
- S5-10 `9b91d05` `8089b6f`（修正 `1101418`）：编辑 / 新建分组 sheet。草稿与校验放在 Sub2Core 的 GroupEditDraft，写入流程放在 Session 的 GroupEditFlow，另有表单、带 key 的写入与结果核对。GroupsView.swift 已删除。
- S5-11 `518caa5`（修正 `a939926`）：编辑 sheet 的成员账号区、sheet 内的添加账号页，以及保存后的成员写入（出一条合并回执）。
- S5-12 `e90e4e7`：分组 API 密钥页与分组订阅页（GroupKeysView、GroupSubscriptionsView，另有 GroupRecordsPresentation、GroupRecordsModel、GroupRecordsChrome）。
- S5-13 `81cfa6d` `888ec28`：阶段收口。内容包括：
  - 简易模式夹具（-ui-simple-mode、GroupFixtures+SimpleMode）；
  - 分组写后的首页刷新（GroupWriteMark 包住六个写方法，X17）；
  - 删除 AccountsView(initialGroupID:) 过渡入口与 -ui-account-group-transition 夹具（X32）；
  - QA 单测 2 条、UI 用例 14 条；
  - README 与 ADMIN_MODULES 的分组部分改写。
  进度表与 BACKLOG 由 `04211b7` 写入。
- 合入时另有一处只改测试的修正：`b840ad9`。S5-02 合入后单元测试变多，AccountOAuthTests 的计时断言连续失败，改成了不依赖耗时的写法。

#### (2) 规格测试清单 / 完成标志对照

50 章没有单独的测试清单小节。下面对照的是 50 §9 末尾的“QA 对账”四条，以及 §9 文件表、§2.7 和改动总表里 GroupManagementTests 那一行列出的测试内容。测试名按 `81cfa6d` 的测试文件核对；全量 gate（`a939926`）的单元测试全部通过。

- QA 对账：
  - 四桶之和等于 account_count：
    - 单测：GroupPresentationTests.qaFourBucketsAlwaysSumToAccountCount、bucketsFallbackClampsAtZeroAndKeepsTheSum（S5-02），qaSimpleModeReplyDecodesAndBucketsAddUp（S5-13，简易模式响应）；
    - UI：GroupsUITests.testQABucketsAddUpOnEveryRow（S5-13，默认夹具逐行核对）；
    - 现状：快照不一致（可用 + 受限已经超过总数）时，四桶之和会大于 account_count，见 bucketsFallbackClampsAtZeroAndKeepsTheSum 里 counts(3, 3, 2) 一例（error、idle 都是 0，cellCount 为 5）；
    - S5-13 方案里的 qaFallbackBucketsAddUpForConsistentSnapshot 写明“S5-02 已有同类用例就不加”，实际没有加。
  - F04 与 D02 满足 0.2 的公式（到期自动暂停的过渡账号除外）：GroupPresentationTests.qaF04MatchesD02ExceptExpiredAutoPauseInAWindow（S5-02）。
  - 详情“今日”等于列表同组“今日”：
    - 单测：qaListAndDetailTodayShareOneAmountText（S5-13）。两处出自同一函数，nil 时分别写“今日 —”与“—”；
    - UI：GroupDetailUITests.testQATodayReconcilesWithListAndMembers（高级组 $933.30、Claude Code 组 $52.75）。
  - 成员“今日”（分组口径）之和不超过分组今日：同一个 UI 用例，只计行上显示“今日”的成员（限流行显示的是恢复时间）。夹具按 S5D2a-12 拆分后，两组的成员之和正好等于分组今日。
- §9 文件表与 §2.7 列出的测试内容（查到的部分）：
  - 解码（含字段缺失）：GroupManagementTests.groupDTOUsesDecimalAndMissingCountersRemainUnavailable、adminGroupDecodesBucketCountsAndClientRestrictionFields、groupAccountCountsDecodesMemberBatchShapeWithMissingFields；GroupMembersTests.memberResultToleratesMissingCountsDetailsAndPriority。
  - F04 退路：GroupPresentationTests.bucketsFallBackToTheErrorListAndTheRemainder、errorCountsCountEachErrorAccountOncePerGroup；GroupStoreRulesTests.errorFallbackFollowsCapabilityThenMissingKey。
  - 健康判定：GroupPresentationTests.healthFollowsTheTableOrder、healthUsesShortageBeforeTheLocalHalfRule。
  - 拆批：
    - 成员：GroupMembersTests.memberRequestSplitsIntoOrderedBatchesOf200、GroupMembersAPITests.memberBatchSendsOver200InOrderAndMerges；
    - 容量：GroupManagementTests.groupCapacitiesSplitOnceOnTooManyIDs。
  - 回执文案：GroupMembersTests.memberReceiptAllSucceededRows、memberReceiptPartialAndAllFailedRows、memberReceiptPrefixesForCreateAndSave、memberReceiptSingleRemovalAndUnconfirmed。
  - 反向请求：GroupMembersTests.memberInverseUndoesOnlyChangedMemberships；GroupBatchOutcomeTests.outcomeUndoPlanRevertsOnlyChanges。
  - 删除后果行：GroupCopyTests.deleteConsequencesSkipZeroRows、deleteConsequencesWithoutStatsUseWordsWithoutNumbers、deleteConsequencesInSimpleModeSkipTheMemberLine。
  - groupStats 的老服务端识别：GroupManagementTests.groupStatsReturnsNilWithoutSubscriptionsTotalKey。
  - 测试文件与规格写的不同：
    - 成员写入的测试分在 GroupMembersTests、GroupMembersAPITests、GroupBatchOutcomeTests 三个文件；
    - 文案与权限另有 GroupCopyTests、GroupPermissionsTests。
- 简易模式、只读令牌、旧服务端（50 §0.7、S5-13 scope）：
  - 单测：GroupPermissionsTests.readOnlyTokenGreysWritesAndOffersNoSwipes、simpleModeHidesAdvancedEntriesAndFields、simpleModeHidesMembersOfACompositeGroup；
  - UI：
    - GroupSimpleModeUITests 6 条：testListHidesBillingRowAndStatusActions、testDetailShowsPlatformOnlyAndHidesAdvancedRows、testInactiveGroupOffersEditOnly、testEditAndCreateSheetsShowOnlyBasicFields、testDeletingGroupWithMembersShowsGroupNotEmpty、testAddingAccountsShowsNotBindableCopy；
    - GroupsUITests：testReadOnlyTokenGreysListWriteEntries、testLegacyServerListFallsBackLocally；
    - GroupDetailUITests：testReadOnlyTokenGreysDetailWriteEntries、testLegacyServerDetailUsesFallbacks。
- 首页下钻（50 §8.1）：
  - UI：GroupDetailUITests.testHomeShortGroupRowOpensGroupDetail（N = 1）、testAlertScopeGroupRowOpensGroupDetail；
  - N > 1 时推 .groups(segment: .attention)，由 AttentionItemsTests、HomeDestinationActionTests 证明，没有 UI 夹具。
- 按 50 §0–§9 逐张表对照（S5-13 方案核查 ①）：材料里没有记录，未核对。

#### (3) 50 章各节改动点

- §1.7 分组列表：
  - GroupsView 换成 Features/Groups/GroupListView（S5-04）：三段分区、三行的 GroupRow、本地搜索（提示“分组名称或平台”）。GroupsView.swift 由 S5-10 删除；核查 ② 中 GroupsView、GroupWorkspace 都是 0 处。
  - GroupWorkspace 换成 GroupStore（S5-04）：列表、usage-summary、shortage、F04 退路，revision 语义见 S5D2a-10。夹具在 GroupFixtures*.swift（X44）。
  - 一次拉全量：groupList() 按 1000 一页读完，最多 20 页（S5-01）。
    - 位置不同：规格里的 groupList(etag:) 没有建，ETag / 304 留在 ConditionalCache 里（GroupManagementTests.groupListRevalidatesThroughConditionalCache；核查 ③“不应存在的接口”通过）。
  - groupUsageSummary(timezone:) 只有 vendor 传时区（S5D1-06）。accountStatusSummary 全仓只有一个定义（核查 ③）。
  - GroupPresentation.swift 由 S5-02 建，另拆出 GroupCopy.swift 与 GroupPermissions.swift。
  - GroupCellsView.swift 由 S5-04 建，列表与详情共用。
  - “分组管理”入口迁到搜索目录：不在阶段 5 条目范围内，未核对。
- §2.7 分组详情：
  - GroupDetailView 重写（S5-06、S5-07）：横幅、状态卡、按钮行和四个编号分区，序号固定为壹贰叁肆（S5D2a-13）。
    - “查看与管理分组账号”“统计分析”已删除，旧标识 group.accounts、group.analytics、group.logs 在 NativeApp 里为 0（核查 ②）；
    - “请求记录”改为“记录与关联”的三行（S5-07）。
  - 文案“正常”“费率倍数”“标准（余额）/ 订阅（配额）”“每用户 RPM”都在 Sub2Core 的 GroupPresentation / GroupCopy 里。
  - 位置不同：规格写的是沿用旧 perform / reconcile 的“结果待确认”流程，实际随旧页面一起删除，换成 GroupActions（S5-05）加 GroupWriteDisposition 分类（S5D2a-06）。
  - 接口：
    - AdminGroup 新字段（S5-01）；
    - groupCapacities(groupIDs:serverFiltered:)，无参版已删除（S5D1-05）；
    - groupStats(id:) 在没有 subscriptions_total 键时回 nil；
    - groupTodayUsage(id:serverTimeZone:) 读 dashboard/groups，超时 45 秒（S5D1-07、S5D1-08）。
  - 位置不同：规格里的 firingAlerts(groupID:) 没有建，横幅经 LiveOpsStore+GroupDetail 读取（S5-07）。核查 ③ 确认没有 firingAlerts(groupID:)，alertEvents 只有一个定义。
  - 成员今日在服务器有 accounts.today_stats_group 时走分组口径（S5-06）。
    - 位置不同：规格写的 accountTodayStats(ids:groupID:) 没有建。成员今日用的是 S2-02（`9a0448b`）建的 accountTodayStatsBatch(ids:groupID:)，可选的 group_id 当时已经带上；GroupDetailModel.swift:26 调用它。
  - 容量条复用 CapacityBar（S5-07）。成员行直接用 AccountRow（GroupMembersSection.swift:81），已复用。
- §3.7 编辑 / 新建分组：
  - GroupEditorView 换成 GroupEditSheet 加 GroupEditForm（S5-10）。草稿、校验、差异放在 Sub2Core/GroupEditDraft.swift，写入流程放在 Session/GroupEditFlow.swift（位置不同，S5D2a-09）。成员区与 sheet 内的添加账号页由 S5-11 做。
  - GroupCreateRequest 默认平台为 anthropic，GroupPlatform.concrete 不含 composite：GroupManagementTests.groupPlatformConcreteDropsCompositeAndCreateDefaultsToAnthropic（S5-01）。
  - 写接口：规格写的是 createGroup / updateGroup / deleteGroup 加 `idempotencyKey: UUID` 参数；实际是四个只收 GroupWriteOperation 的写方法（S5D1-01、S5D1-02）。PreparedGroupWrite 由 GroupWriteDraft 取代（核查 ② 中 PreparedGroupWrite 为 0 处）。
  - 规格写的 GroupMembers.swift 拆成了 GroupMembers、GroupMembersLegacy、GroupBatchOutcome 三个文件（S5-03）。
  - 确认框逐行文案与“保存后可用”：GroupCopyTests.editDiffLinesListEveryChangeInOrder、GroupPresentationTests.availableAfterCountsSchedulableMembersOfThePlatform（函数名与规格的 diffLines / availableAfter 是否一致，未逐一核对）。
- §4.7 添加账号：GroupAccountPicker.swift 加 GroupAccountPickerModel（S5-08），直接打开和编辑 sheet 内的子页用同一个视图（S5-11 用草稿模式）。候选只读第 1 页 200 个。账号查询带 lite=1、sort_by=urgency，每页 200 个：GroupAccountPickerModel.swift 第 6 行注释这样写，第 74 行的 AccountListQuery 也是这样传的。服务器没有 accounts.list_query 时，sort_by 退回 name（AccountListQuery.queryItems）。
- §5.7 逐项结果：GroupBatchResultView.swift 由 S5-09 建。结果模型、原因文案、重试分组和反向请求在 GroupBatchOutcome.swift（S5-03），不在规格写的 GroupMembers.swift；页面状态在 Session/GroupBatchResultModel.swift。
- §6.7 / §7.7 API 密钥与订阅：GroupKeysView.swift、GroupSubscriptionsView.swift 由 S5-12 建。
  - groupAPIKeys(id:page:maskedView:) 比规格多一个 maskedView 参数（S5D1-06）；
  - 不保存 Key 明文：GroupManagementTests.groupAPIKeysNeverKeepsPlaintextKeys，核查 ⑦“分组 Key 页不要明文视图”通过；
  - groupSubscriptions(id:page:)、activeSubscriptionCount(groupID:) 已建。
- §8.7 首页下钻：
  - 最终版本已接上：首页“可用不足 1 个分组”与告警范围区的分组行进新详情（S5-13 两条 UI 用例），N > 1 时推 .groups(segment: .attention)；
  - 过渡版本 AccountsView(initialGroupID:) 与 AccountListModel.groupID 已由 S5-13 删除；核查 ④ 确认 AccountsView 没有 navigationDestination(item:)。
- 改动总表 DemoData.swift 一行：分组夹具不在 DemoData 里（GroupFixtures*.swift，夹具分组 id 1–11）。DemoData.adminMe 只加了 -ui-simple-mode（S5-13）。

#### (4) BACKLOG 与前序阶段备注里留给阶段 5 的事项

- 倍率的显示位数（BACKLOG 阶段 0 行与阶段 2 补充行；阶段 3 小结写“分组页由阶段 5 定”）：S5-02 定为 GroupFormat.rateText，精确到 0.1 时写 1 位，否则最多 2 位（×0.8、×1.0、×1.25）。与用户页的 ×1 不统一，待用户定（拍板第 13 条）。
- 路由参数在旧页面上不生效（.groups 的 segment、.groupBatch 的 items）：已处理。.groups 的 segment 由 S5-04 接上，.groupBatch 由 S5-09 改为携带结果；.group(id:) 的首页与告警入口有 S5-13 的 UI 用例。
- 跨 Tab 跳转撤不掉视图式推入的页面：分组部分已处理。
  - 分组列表改用 NavigationLink(value:)（S5-04）；
  - 旧详情的视图式推入随 S5-06 删除；
  - AccountsView 的 navigationDestination(item:) 与 init(initialGroupID:) 由 S5-13 删除；
  - Features/Groups 里唯一的 navigationDestination(isPresented:) 在编辑 sheet 自带的导航栈里。
- status-summary 分组 shortage 的数值单位：分组页只用 is_short，不显示 threshold / current，所以不需要按来源格式化。
- 渠道行点进旧分组详情（S1-15 备注）：已处理。S5-06 起 .group(id:) 落到新详情，新夹具的 id 1–11 与渠道夹具一致。
- 分组页旧夹具与账号夹具的分组 id 不一致（阶段 2）：已处理。GroupsView 旧夹具随 S5-10 删除，-ui-account-group-transition 由 S5-13 删除。
- 阶段 2 那一行写“第 2 波若在 AppModel+Accounts 新增账号写包装（如 S5-08 改 group_ids），必须同样套 recordingAccountWrite”：
  - 按 S5D2a-07，成员写包装放在 GroupMemberActions.swift，不套 recordingAccountWrite，改由 S5-13 的 GroupWriteMark 包住，口径与 AccountWriteMark 相同；
  - 核查 ⑦：recordingAccountWrite 不出现在 Groups 目录，GroupWriteMark.run 恰好 6 处；
  - GroupWriteMark 只是转调，没有单独的测试，口径由 AccountWriteMarkTests 保证（S5-13 方案）。
- 通用删除确认（阶段 0 行）：分组删除经 S3-00 的 DeleteConfirmationSheet，Face ID 走 BiometricGate.authorize(.delete)（核查 ⑦）。删除标题、首行与回执用 DeleteConfirmationCopy（S5-02）。
- 缺失值“—”的读屏：分组列表行的“今日 —”读作“今日无数据”（S5-04）。分组页其他位置材料里没有记录。
- S4-13 备注“旧分组详情入口……S5-06 删链接”：S5-06 删除了对 AnalyticsView(groupID:)、RequestLogsView(groupID:) 的调用，兼容构造由 S4-20 删除。
- “errorCount 的口径”（BACKLOG 阶段 4 行，BACKLOG.md:490）：要求 S5-07 的文案只写“近 24 小时 N 条”，不当错误率用。已满足：详情“叁 · 记录与关联”的计数用 GroupCopy.last24Hours，写的就是“近 24 小时 N 条”（GroupCopyTests 有断言）。
- 阶段 5 自己的 BACKLOG 行：
  - “AccountsView 手写 composite 过滤”：已处理，S2-04 重写时已经去掉；
  - “线 A 提交 e7abfd5 待推送”：e7abfd5 已经由合并提交 `0a15970` 合入主分支（`0a15970` 上的集成 check 通过），这一行可以关闭，BACKLOG 里还没改；
  - “从详情删除遇 KEY_CONFLICT 时‘重试’无处弹确认”：S5-05 的审查修正 `9fcf6eb` 已改为从详情删除时，“没有生效”与“需重新操作”两种回执都不带按钮，从分组菜单重新删除；S5-06 接入新详情后是否复核过，材料里没有记录，BACKLOG 行也没改。
- 其他阶段的备注：S6-21 行写“分组行点进去仍是旧分组详情（S5-06 未合入）”，那是 S5-06 合入前写的。按 `81cfa6d` 的代码，搜索里的分组命中推 .group(id:)（SearchResultsListModel.swift:21），落到新详情。

#### (5) 核查结果（S5-13 一次性脚本 scratch/s5-13/check.py，不入库，输出在 scratch/s5-13/check-out.txt）

- ② 旧符号与旧标识：
  - GroupsView、GroupWorkspace、GroupEditorView、PreparedGroupWrite、GroupDestination 都是 0 处；
  - 旧标识（group-editor.*、group.analytics、group.accounts、groups.platform、groups.status、groups.more、group.logs、group.result，以及已作废的 group.menu.status、group.swipe.status、group.detail.more、group.detail.action.*、group.menu.add、group.row.<id>.add）在 NativeApp 与 Sources 里为 0；
  - UITests 里只在 GroupDetailUITests 第 34、596 行作否定断言；
  - 没有 vtGroupAccounts 一类的页面文件。
- ③ R19：
  - groups(page:…)、groupCapacities(groupIDs:serverFiltered:)、alertEvents(…)、errorCount(filter:kind:)、accountStatusSummary(…) 各只有 1 处定义；
  - groupList(etag:)、无参 groupCapacities()、firingAlerts(groupID:)、requestErrorCount、upstreamErrorCount 都不存在。
- ④ X39：Features/Groups 只有 GroupEditSheet.swift:123 一处 navigationDestination(isPresented:)，在编辑 sheet 自带的导航栈里（内嵌添加账号页），不推入 Tab path。AccountsView 没有 navigationDestination(item:)。
- ⑤ D27：分组 UITests 引用的标识共 135 个，NativeApp 里只有 group.accounts 找不到，它只用于否定断言；23 个启动参数都能找到。
- ⑥ 文件长度：Features/Groups、Sub2Core/Group*.swift、UITests/Group*.swift 都不超过 800 行。最长的三个是 GroupDetailUITests 650 行、GroupEditUITests 571 行、GroupPresentation.swift 445 行。
- ⑦ 安全：
  - R11（分组页不回显服务端 message）：唯一命中的是 GroupBatchResultView.swift:52 的 Text(prompt.message)。prompt 是混合渠道确认框（S5-03 的 GroupMixedChannelConfirmation，App 自拟文案加平台名），不是服务端 message。另有单测 GroupCopyTests.errorCopyNeverEchoesTheServerMessage。
  - X10（不写 .disabled(…isReadOnlyToken)）：分组目录 0 处，只命中 ComplianceSheet.swift 第 57、63 行（合规确认页）。要不要处理，材料里没有记录。
  - 分组相关文件没有 print / NSLog，日志只用 os.Logger。
  - Features/Groups 里 noteExternalWrite 只出现在 GroupWriteMark。GroupWriteMark.run 共 6 处：AppGroupEditSource.swift:24，GroupActions.swift:35 / 46 / 58，GroupMemberActions.swift:93 / 99。recordingAccountWrite 不出现在 Groups 目录。
  - 成员批量写入（GroupMemberWriter、GroupBatchResult*、GroupEdit*）都不调 BiometricGate。删除经 GroupActions.swift 的 confirmDelete / DeleteRequest，到 DeleteConfirmationSheet.swift:163 的 gate.authorize(.delete)。
  - 分组 Key 页没有 maskedView: false。
- 方案列了但核查输出里没有的两项：① 逐节对照 50 §0–§9 每张表、改动总表 50 章各行、U37–U39、R11 / R14 / R19；⑧ build 输出没有新增 warning。check 日志只有 BUILD_EXIT=0，材料里没有记录 warning 的核对结果。
- S5-13 提交说明：前序页面没有简易模式缺口，没有改页面代码。

#### (6) 与规格不同的取舍（阶段汇总，各条目的细项见上表备注）

- 需要用户拍板的十五条（_decisions-S5 批次 2a），都按默认值实现：
  1. 最早恢复：每个成员取它最晚的进行中窗口，再取全组最早，并列时写“恢复 n 个 · X 等”；另外只算开着调度的限时成员（S5-02）。规格字面是“三个窗口里仍在未来的最小值”。
  2. 删除后果行拿不到 stats 时写不带数字的句子，简易模式不写成员行；停用 / 删除确认的 stats 最多等 2 秒（S5-02、S5-05）。
  3. 区块刷新失败时保留上一次成功的值，不加提示；只有从未读到才写“—”或不显示（S5-04、S5-07、S5-12）。
  4. 分组写遇到 5xx 一律按结果不明；结果不明时自动读回一次，定不了才给“用同一编号重试”与核对（S5-05、S5-10）。
  5. 编辑 / 新建 sheet 的成员回执全部成功时不给撤销，“重试”后的回执也不给（S5-11）。
  6. 更早的时间写 MM/dd HH:mm（DisplayFormat.monthDayClock），不写 MM-DD（S5-07 横幅、S5-12 Key 最近使用）。
  7. 简易模式：详情“贰”只留“请求 · Tokens · 账号成本”，“肆”只留描述与 Web 行；停用分组的按钮行只剩“编辑分组”，不提升为主按钮；新建脚注只写“平台创建后不能修改。”（S5-07、S5-10、S5-13）。
  8. 简易模式不走逐账号退路，直接提示“服务器暂不支持批量调整成员。”（S5-08）。
  9. 成员批量写入（添加、移出、逐项结果页的重试 / 撤销、sheet 保存后的成员写入）不过 Face ID（S5-08、S5-09、S5-11，S5-13 已核查）。
  10. 主按钮被隐藏后不改派（S5-02、S5-06）。
  11. 规格里没有的新增文案：S5-03 的成员写入回执七句、S5-11 的“<前缀> · 成员没有改动：<原因>”、S5-08 组合分组选择页的措辞。
  12. 分组名按 UTF-8 不超过 100 字节（S5-10）。Core 的 GroupWriteValidation.name 仍按字符计，已记 BACKLOG。
  13. 倍率写 ×1.0 / ×1.25，与用户页的 ×1 并存（S5-02）。
  14. 订阅限额允许输入 0，显示 $0（S5-10、S5-12）。0 的语义待后端确认。
  15. 新建分组的平台下拉只列 App 已知的平台（S5-10）。
- 接口与签名（与规格 §3.7、§9 的字面不同，按裁定实现）：
  - 写方法只收 GroupWriteOperation，编号命名照 PendingUser*Operation（S5D1-01、S5D1-02）；
  - 删除结果是 enum，404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND 在 Core 里映射为 alreadyGone（S5D1-03）；
  - groupList 没有 etag 参数；
  - groupCapacities 按 00 §4.5 的批量 ID 规则：去重、去掉非正数、每批不超过 100 个，收到 TOO_MANY_IDS 再拆一次；
  - usage-summary 与 dashboard/groups 超时 45 秒（S5D1-07）；
  - groupAPIKeyCount / groupAPIKeys 带 maskedView 参数（S5D1-06）。
- 展示与文案（S5-02）：
  - 订阅限额整数写 0 位小数，非整数写 2 位；
  - 编辑时把停用的分组改回正常：确认框里写一行“启用分组”，但启用本身不触发确认；同一次保存里停用分组时，可用数降到 0 不算“归零”，由停用那一行说明（GroupEditDiff）；
  - 详情副标题里接口没给的字段省略。
- 成员写入（S5-03）：
  - R06 同体重发 1 次，范围是传输失败、408、502、504、无 reason 的 503，进后台不重发；
  - 新增 REQUEST_UNCONFIRMED（“结果未确认，可以重试”）；REQUEST_NOT_DELIVERED 只给没发出的批；2xx 答复里缺的账号也记 REQUEST_UNCONFIRMED（S5D2a-17）；
  - 没有 reason 的 4xx 一律按非 JSON 处理，只会偏向“结果未确认”（`a69ef8a`）。
- 列表（S5-04）：
  - status-summary 失败或 403 时 shortage 置空，退回本地 50% 判定，不像 usage 那样保留旧值；
  - F04 退路还没读到时错误计 0，错误账号只读一页 1000 个；
  - 旧服务端用 -ui-without-capabilities 模拟，不建 -ui-group-legacy（X05）。
- 动作（S5-05）：撤销成功不再出回执；不带 key 的删除或停用读回发现没有生效时，“重试”重新弹确认（`9fcf6eb`）。
- 详情（S5-06、S5-07）：
  - 404 页标题“分组”；
  - 分组读取失败时，有快照显示中性横幅，没有快照整页“读取分组失败”；
  - 回前台按下拉刷新处理；60 秒轮询从上一轮结束时算起；
  - “可用偏低”只在分组正常且 active > 0 时读；
  - 成员为 0 时显示“没有成员账号”占位；
  - 告警规则摘要按 R10 写“5.0%”；
  - 只有 canEdit == .enabled 时配置行可点。
- 逐项结果页（S5-09）：行上的账号状态用提交时的快照（规格要求取 App 账号缓存，但 App 没有会话级账号缓存）；没有失败时，成功区的序号是“壹”（同设计稿）；“s 个成功”与成功区 meta 用未撤销的成功数，按钮用可撤销数。
- 编辑 sheet（S5-10、S5-11）：
  - 编辑遇 404 时锁住表单；费率框不设占位；
  - 名称只在用户改过之后才提交（`1101418`）；
  - “（现在 y）”只在 x ≠ y 时显示；
  - 只改成员时不发 PUT、不生成编号；
  - 结果不明时选“稍后核对”关闭 sheet，成员改动不发送；
  - sheet 打开时成员最多读 20 页。
- 记录页（S5-12）：订阅页自己读 stats，stats 出错不走退路；400 不自动重发，但保留手动重试与下拉；翻页提示按 page_size 20；夹具的总数与用户页 Key 卡片不联动。
- 收口（S5-13）：
  - 简易模式新建请求体仍带默认计费字段，后端会覆盖为同样的默认值；
  - 简易模式夹具对订阅不回 403，与后端一致（规格 50 §0.7 写 403，App 已隐藏订阅行）；
  - capacity 与 api-keys 不加 403，因为入口已隐藏；
  - 成员今日对账在 UI 上只核对“不超过”；
  - 只读令牌下列表行的右滑会被系统当作返回手势，用例按这个行为写。

#### (7) 未做项及原因

- 只有单测、没有 UI 覆盖的部分：
  - vendor 视角：U01 首版拒绝 vendor 登录，GroupPermissions 的 vendor 分支只有单测；
  - 首页“可用不足 N > 1”：阶段 1 的首页夹具只有 1 个可用不足分组，路由由 AttentionItemsTests、HomeDestinationActionTests 证明；
  - 组合分组在简易模式下隐藏“添加账号”：夹具里没有组合分组，由 GroupPermissionsTests 覆盖；
  - S5-04 的首次骨架与 60 秒轮询（单测与代码审查）；
  - S5-12 没有加 usage-failure / key-view-rejected 两个启动参数（单测覆盖）。
- 已知限制，已记 BACKLOG：
  - 添加账号页只读第 1 页 200 个候选；
  - 编辑 sheet 最多读 2000 个成员；
  - 成员行状态动作后靠重拉成员刷新该行；
  - 逐项结果页用提交时快照；
  - 分组列表的 usage-summary / status-summary 自身收到 429 时没有区块等待；
  - 大分组详情的轮询请求量随页数线性增长，实测后再定；
  - 分组名的 Core 校验仍按字符计（要改 GroupManagement.swift）；
  - 服务器日历整天数有三份相同算法，建议在 S6-26 收口时统一，S6-26 行里没有提到。
- 已知限制，只写在进度行、BACKLOG 没有记：编辑 sheet 内的添加账号子页用 navigationDestination(isPresented:) 推出，iOS 26 的系统返回按钮可能只画箭头（S5-11）。
- 简易模式新建请求体只发名称、描述、平台三个键：要另立条目给 GroupCreateRequest 加简易模式编码。
- 简易模式组合分组详情的专门整页文案：待用户定，现在按读取失败页显示。
- ETag 304 实测：S5-13 方案列在范围外（需要用户授权访问测试环境）。
- 静态核查 ① 与 ⑧ 没有输出，见 (5)。
- BACKLOG 整理：
  - 阶段 5 有两组重复行（“订阅限额 0”两行，“添加账号页超过 200 个候选”两行），待集成者合并；
  - 阶段 5 表的“服务器日历整天数的多份同算法”（BACKLOG.md:617）与阶段 6 表的“服务器日历整天数有三份实现（新增）”（BACKLOG.md:737）内容相同，也待合并；
  - “线 A 提交 e7abfd5 待推送”可以关闭。
- 需要用户确认的默认值：
  - _decisions-S5 批次 2a 的十五条；
  - BACKLOG 阶段 5 表里写“待定 / 待用户决定”的八条：成员退路改用 PATCH + If-Match、shortage 失败时是否保留旧值、“用同一编号重试”的常驻入口、“稍后核对”丢弃成员改动是否写明、简易模式组合分组整页文案、只读令牌右滑返回是否拦截、无 groups.member_batch 的简易模式站点成员入口是否置灰、“最早恢复”只算开着调度的限时成员；
  - 规格未决问题 U37–U39 的建议默认值。

#### (8) UI 测试运行情况

- 各条目提交时的 check（UI_FLAKY 都是“无”，没有重跑才通过的用例）：
  - S5-01：GroupsUITests 两次各 2/2。
  - S5-02、S5-03：纯 Core，UI_SKIPPED。S5-03 审查修正 `a69ef8a` 的 check 也只跑单元测试（2434 + 1006）。
  - S5-04：5 个类 118/118。审查修正 `792805c` 提交前的 check 68/68；新增的两条 UI 用例 testListRetryDoesNotWaitForSlowUsage、testPullReadsListAgainWhileUsageIsSlow 先红后绿。
  - S5-05：22/22；审查修正 `9fcf6eb` 58/58。
  - S5-06：6 个类 109/109；审查修正 `8026f9f` 29/29。
  - S5-07：3 个类 36/36，UI 用例是实现后补写的（不是先红后绿）；审查修正 `6f25f77` 17/17。
  - S5-12（线 C）：GroupRecordsUITests、GroupDetailUITests 24/24。
  - S5-08：5 个类 74/74（在 `4eaa907` 加 11 个未提交文件上，即 `f743de1` 提交前的内容）；审查修正 `67f5b62` 42/42。提交前的第一次 check（`21170e2` 加 15 个未提交文件）67 个中 GroupMembersUITests.testRemovingTheOnlyAvailableAccountAsksFirst 失败，随后单跑 3 个通过。原因未查明，可能是不稳定用例。
  - S5-09：3 个类 48/48。
  - S5-10（线 B）：`9b91d05` 14/14，`8089b6f` 5 个类 65/65；审查修正 `1101418` 24/24。
  - S5-11：4 个类 60/60；审查修正 `a939926` 的 GroupEditUITests、GroupMembersUITests 31/31。
  - S5-13：13a（`81cfa6d`）13 个类 244/244，按方案是 GroupSimpleModeUITests、GroupsUITests、GroupDetailUITests、GroupActionsUITests、GroupMembersUITests、GroupEditUITests、GroupRecordsUITests、AppNavigationUITests、AccountListUITests、AccountDetailUITests、HomeUITests、AlertDetailUITests、MonitorUITests；13b（`888ec28`）9 个类 132/132，类名材料里没有记录。两次的单元测试都是 2737 + 1356 通过。
- 集成者合入后的 check：
  - S5-01（合并提交 `635a8c9`）：GroupsUITests 2/2，单元测试 984 + 232 通过。没有单独的日志文件，记录在 scratch/resume1/state.json 的 integ/S5-01 一项。
  - S5-02（`13600ef`）：单元测试 2344 个连续两次有 1 个失败，是 AccountOAuthTests.authURLReplyKeepsStateAndRejectsUnsafeLinks 的 1 秒计时窗口（BACKLOG 已记的偶发失败）。`b840ad9` 改为不依赖耗时后通过（2344 + 956）。
  - S5-03（`0a15970`）：单元测试通过，UI_SKIPPED。
  - S5-05（`6920286`）：63/63。
  - S5-07（合并提交 `93101c6`，scratch/integrate-a-s5-07-check.log）：单元测试 2619 + 1264，UI 36/36，UI_FLAKY 为“无”。
  - S5-08（`0ec795c`）：74/74；审查修正合入后（`7ab407f`）42/42。
  - S5-10（`5f23b96`）：65/65。
  - S5-11（`22578e7`）：60/60。
  - S5-06（`96cb786`，线 A 在 `17ccc0f` 之上把当时的主分支并进来的合并提交）、S5-09（`a05d198`）、S5-12（`e90e4e7`）快进合入，条目 check 即在同一提交上（各日志 SYNCED 行都是该提交加 0 个未提交文件），没有单独的集成 check。
  - S5-04 也是快进合入，但情况不同：`9d16582` 不是主分支当时提交（`b6669ae`）的后代，主分支快进到的是线 A 把主分支并进来之后的 `34866e1`（第二个父提交就是 `b6669ae`），其上是 S5-03 审查修正 `a69ef8a`。条目 check（118/118）跑在 `9d16582` 上，不含主分支当时的改动。`34866e1` 上只有 S5-03 审查修正的 check（加 3 个未提交文件），只跑了单元测试（2434 + 1006）。合入后第一次跑全量 UI 是 S6-20 合入后的定期 gate（`575f3e3`，673/673，见阶段 6 小结）。
- 全量 gate（三次，TOOLCHAIN、UNIT、BUILD 都为 0）：
  - S5-07 合入后（scratch/gate-fe1e2de.log，`fe1e2de`）：单元测试 2619 + 1264，UI 779/779，UI_FLAKY 为“无”。
  - S5-10 合入后（scratch/gate-ab5b4ce.log，`ab5b4ce`）：单元测试 2725 + 1342，UI 829/829。UI_FLAKY 为 ProxiesUITests.testAddProxyThenUndo()，即重跑后才通过，这是阶段 6 的用例（S6-14 加的）。
  - 阶段收口（scratch/gate-S5-13.log，`a939926`，包含 S5-13 两次提交与 S5-11 审查修正）：单元测试 2737 + 1358，UI 849/849，UI_FLAKY 为“无”，GATE_SCRIPT_EXIT=0。进度表 S5-13 行没有写这次 gate。
- 不稳定用例：
  - 上面的条目 check、集成 check 与三次全量 gate 里，只有 gate-ab5b4ce 里 ProxiesUITests.testAddProxyThenUndo 重跑后才通过（阶段 6 用例，与分组无关）。
  - S5-08 提交前第一次 check 里 GroupMembersUITests.testRemovingTheOnlyAvailableAccountAsksFirst 失败、单跑通过，原因未查明，可能是不稳定用例。
  - 阶段 5 的用例 GroupEditUITests.testDuplicateNameShowsRedTextAndGreysCreate 在 S4-20 合入后的全量 gate（scratch/S4-20-integrate-gate.log，`c5231df`）里重跑后才通过，阶段 4 小结已记。
  - 提交前开发中的失败（先写的红灯用例、改写中的用例）不计在内。阶段 2 记过的既有失败（AccountNewUITests 三个用例、AccountDetailMenuUITests.testSwitchingToNoProxy）在三次 gate 里都没有出现（都是 0 个失败）。

## 阶段 6 · 其他模块

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S6-01 | 登录设备页（A07） | ✅ | `ca8d54f` | 按 X02 只改 SettingsDestinations.swift 的 .sessions 段；activityLine 带 timeZone，“今天 09:41 活跃”数字结尾时加空格；撤销返回本机时走 forgetActiveSession，新定文案“本机已下线，请重新登录。”，不走 logout；“让其他所有设备下线”在非本机条数不少于 1 时显示，N 取非本机条数，按钮为“下线”“全部下线”，全部下线后不出回执、只重载（覆盖 BACKLOG“让其他设备下线可能连本机一起下线”，有 UI 测试）；登录于 / 到期写 MM/dd HH:mm 与 MM/dd 补零，私有实现待 S6-26 收口；设置页数量改为每次出现都重读；DemoData.authSessionCount 已不再被引用，留给 S6-26 删除；check 跑了 SessionsUITests、SettingsUITests、AppNavigationUITests，34/34 通过（审查修正 27e7535）审查修正 27e7535：全部下线成功后立即隐藏他机。重载失败时保留旧列表，并显示“刷新失败 · 重试 / 更新于 hh:mm”（00 §4.6）。新增夹具参数 -ui-sessions-reload-fails 和对应 UI 用例。 |
| S6-22 | 推送模型、展示规则与接口（Sub2Core） | ✅ | `972e43b` | 纯 Core，另拆出 PushRequests.swift 放两个含密钥的请求体（屏蔽描述、不能解码读回）。与规格不同的取舍：Bark / ntfy / Webhook 登记也带 locale zh-Hans 与 timezone；“最近失败”只在 last_error 不早于 last_success_at 时追加；失败文案走 PushPresentation、不改 ReasonCatalog（PUSH_DELIVERY_FAILED 带 provider_reason / provider_status，status 为 0 时不写括号；INVALID_PUSH_TARGET / TOKEN 只在 field 为 endpoint / token 时用页面文案，其余字段保留参数类文案）；只读令牌登记失败按 metadata.field == platform 判定，没有建 PushOperation；APNs 字段错误文案按后端约束补齐；step_up_enabled 缺失按可编辑；名称为空时依次退到 endpoint_host、平台名；没有时区写“按 UTC 时区”；“MM/dd HH:mm”私有实现，S6-26 收口。PushSeverity 未实现 Comparable。UI 测试未运行（ui_test_classes 为空，check 里 TOOLCHAIN / UNIT / BUILD 均为 0）。 |
| S6-02 | 管理访问令牌页（A08，列表与吊销，含吊销本机令牌） | ✅ | `d9c1279` | 路由只改 SettingsDestinations.swift 的 .accessTokens 段（X02）；AppModel+Session 只加 revokeAccessToken(_:context:)。吊销本机令牌时复用 SiteTeardown 的退出流程先删推送设备（失败记待删除、不发 logout），再 DELETE；current == true 时本地擦除，提示“已吊销本机正在使用的令牌，请重新登录”。与规格不同的取舍：吊销他行（含 404）给回执“已吊销「名称」”；当天到期写“今天到期”（caution）；usageLine 带服务器时区；“yyyy/MM/dd”为私有实现，待 S6-26 收口；重载失败时保留旧列表并显示“刷新失败 · 重试”。夹具签名改为接收 SessionContext。DemoData.accessTokenCount 已无引用，留给 S6-26 删除。不签发（U02）。check 跑了 AccessTokensUITests、SettingsUITests、SessionsUITests、LoginUITests，41/41 通过。 |
| S6-03 | 兑换码模型、查询、统计、写接口与生成接口（Sub2Core） | ✅ | `d66c0e0` | 只改 Sub2Core 与 Sub2CoreTests；与方案不同：RedeemBatchUpdateFields.Group 清空值叫 cleared（避免 .none 被读成 Optional.none）；首次发送的其他 4xx 删除记录回第 3 步，408 仍按结果不明；admin_* 写“余额（管理员调整）/ 并发（管理员调整）”；只读令牌 ··· 保留复制、查看使用者、查看同一批；MM/DD 为私有实现，待 S6-26 转调 monthDayClock；UI 测试未运行（本条无 UI 类，check 为 UI_SKIPPED，App 与 UITests 编译通过）（审查修正 5b6e896）审查修正 5b6e896：已禁用的码过了过期时间写“（已过期）”；单卡刷新时，列表里的分组和使用者只在 group_id / used_by 对得上时才沿用 |
| S6-15 | 公告模型、展示规则与接口（Sub2Core） | ✅ | `c2b860c` | 接口方法拆到 Announcements+API.swift（条目 files 外多一个文件）；createAnnouncement 加 supportsIdempotentCreate / onEvent，没有 capability 时带 key 只发一次、结果不明抛 unconfirmed（00 §5 表写“不带 key”，按 60 §0.2 执行）；计数带千分位、详情比例一位小数“39.6%”（示例“40%”）；起止按本机时区，更新于 / 阅读时间 / 统计于按服务器时区；按 S6D1-01 补 navigationSubtitle / displayTitle / detailSubtitle / publishConfirmation；徽章写“不符合”；“MM/dd HH:mm”与首字为私有实现，待 S6-26 收口；未改 ReasonCatalog；条目没有 UI 测试类，check 为 UI_SKIPPED（审查修正 526bc68）审查修正 526bc68：isSimpleTarget 只认手机表单能保存的单条件（订阅，或余额 > ≥ < ≤ 且金额 > 0），eq、阈值 ≤ 0（含后端省略 value）改为只读，S6-18 可以直接用它判断能否编辑。 |
| S6-16 | 公告列表 | ✅ | `b52a4c9` | 分段用 AnnouncementStatus?（S6D1-01，不建分段类型），文案全部调 S6-15 的 AnnouncementPresentation；副标题 N 取全部计数，缺失时“全部”分段用第 1 页 total；哪一路计数失败哪个分段只写名称；规格 15.5 之外补了加载中、刷新失败 · 重试、加载失败 · 重试、429 等待四种状态，429 结束后自动重读一次；已归档标题用 ink2；重载信号 model.announcementChanges（C-34，按会话代号、最多保留 4 个，不改 AppModel.swift）；夹具用 memberwise init 构造（33 / 32 / 21 三条的标题与正文是补写的），缺能力用 -ui-without-capabilities announcements.read_stats；详情、编辑、已读情况仍是占位（S6-17…S6-19）；UI 测试已运行：AnnouncementsUITests 13 例 + AppNavigationUITests，共 30 例全部通过（审查修正 e165253）审查修正 e165253：重载被取消（页面再次被盖住）时保留“需要重载”标记，详情或编辑写操作后返回，仍会重读第 1 页与计数。 |
| S6-17 | 公告详情（预览卡、最小 Markdown、发布 / 归档 / 删除） | ✅ | `0ca73e0` | 取舍：Markdown 认 # / ## / ### 小标题，连续行并成一段并保留换行；inline 在 #if canImport(Darwin) 里（S6D1-14）；··· 菜单用 Section 标题写公告标题、首行放副标题；只读令牌时菜单写项置灰、已读情况可用；本机与服务器偏移不同时加有效期时区脚注；有旧内容时刷新失败显示横幅；写失败与撤销失败的回执按 00 §2.4 补齐，超时读回比对 status；删除确认关闭后再返回列表；已读比例沿用 S6-15 的一位小数。未做：编辑 sheet（S6-18）与已读情况页（S6-19）仍是占位。UI：check AnnouncementsUITests 24/24 通过（审查修正 3742945）审查修正 3742945：从已读情况或别的 Tab 返回时，补读进入时被取消的 read-summary，已读情况行不再停在无能力文案。 |
| S6-18 | 编辑 / 新建公告 sheet | ✅ | `4a64cb1` | 与规格不同：key 按 R05 在点“存草稿”或确认框“发布”那一刻生成（17.4 写 sheet 打开时）；已归档保存回执“已保存”；单条件 eq / 余额 ≤ 0 按只读、编辑不发 targeting；多条件只读时隐藏“所有用户 / 按条件”分段；指定时间初值为下一个整点、结束 +7 天；H07 取 5 分钟窗口 + 60 秒时钟误差、本地精确比标题；PUT 结果不明 GET :id 读回比对，不一致停在“结果未确认，请刷新核对后再操作”；有 capability 时按 R04 自动重试后给“用同一编号重试”；订阅分组筛选直接用已合入的 AdminGroup.isActiveSubscriptionGroup；下滑确认用 fileprivate UIKit 代理桥（S6-26 收口）；新 UI 用例放在 AnnouncementsUITests 末尾（未另建 +Edit 文件）；四个 ANNOUNCEMENT_* reason 只在 AnnouncementEditFailure 映射。UI：check AnnouncementsUITests 30/30 通过（审查修正 573a1b2）审查修正 573a1b2：“用同一编号重试”的 STORE_UNAVAILABLE 冷却改按设备时钟计算，并封顶 10 秒；之前错用服务器校正时钟，时钟偏差时会锁住 sheet 或跳过冷却。 |
| S6-04 | 兑换码列表（展示、筛选、定位、复制、查看同一批、待核对横幅） | ✅ | `7a90a9a` | 纯逻辑放 Sub2Core 的 RedeemListPresentation（按 S6D1-05 收窄，复用 S6-03 的查询、展示、批次行），页面在 Features/Redeem；路由只改 RedeemDestinations 的 .redeem 段；复制走 SensitivePasteboard。与方案不同：RedeemCodeCard 多 readOnly 参数，timeZone 用 ServerTimeZone；RedeemPendingBanner.make 内部判定 origin；卡片按钮行只有 ···（禁用 / 启用 / 编辑 / 续期 / 删除归 S6-05）；查看同一批时清空搜索、隐藏胶囊，移除胶囊恢复原筛选，在同一批里输入搜索会退出同一批；“等 N 批”直接接在标题后；副标题总数只在进入、下拉、外部变更时取；定位码非 404 错误不出回执。概览与补偿回执入口未实现，UI 测试用 -ui-redeem-open / -ui-redeem-reconcile 模拟。UI：check 跑 RedeemCodesUITests（14 个新增）、AppNavigationUITests、SettingsUITests，44/44 通过，无重跑（审查修正 227523f）审查修正 227523f 改了三处。一是定位并入重载第 1 页，首屏失败后点“重试”、429 等待结束、回前台时都会定位目标码。二是老服务端“全部类型”还有下一页时，末尾显示“加载更多”，还有下一页时不再判成空态。三是搜索防抖结束后在独立任务里发请求，继续输入不会再取消它。新增 3 个 UI 用例和 2 个夹具参数（-ui-redeem-admin-flood、-ui-redeem-slow-search）。（审查修正 2517eb3）审查修正 2517eb3：429 等待结束后的自动重读改用独立 Task，第 1 页清空等待时不再取消在途的定位（GET :id）和计数读取；新增夹具 -ui-redeem-throttled 与 UI 用例 testLocateCodeAfterThrottledFirstPageWaitsOut。 |
| S6-19 | 公告已读情况 | ✅ | `9b16f8c` | 按 S6D1-18 直接用 S6-15 的 AnnouncementReadStatusQuery / AnnouncementPresentation，不建 AnnouncementReadsFilter；“已删除”复用 AnnouncementDetailPresentation.gone；徽章“符合条件 / 不符合”沿用 S6-15 文案（scope 写“不符合条件”）；不符合条件的行只把邮箱改 ink2，不整行变淡；缺能力用 -ui-without-capabilities announcements.read_stats（X05）；点行 UI 测试只断言离开本页（S3-05 不在依赖链）。check：unit 1572+466、build 无新 warning、AnnouncementsUITests 38/38，无不稳定用例（审查修正 c734708）审查修正 c734708：已读情况页的搜索防抖结束后改在独立任务里应用，继续输入不再取消已发出的第 1 页请求（同词续敲时不再停在“正在加载…”），换词时由 ticket 丢弃旧回复；补了慢返回桩单测，未加 UI 慢搜索夹具。 |
| S6-08 | 发放补偿：Sub2Core 规则与接口、回到前台自动核对补偿 | ✅ | `d52359a` | 按 R01 / R04 走 performKeyedWrite（35 秒），不用 19.7 的 send(PendingWrite) 与 40 秒；新类型放 RedeemGrant*.swift；REDEEM_CODE_EXPIRED 换编号、REDEEM_CODE_USED 转待核对、首次 429 同 401 / 403 / 423 结案；首次安全确认已通过 → reconfirm 结案沿用同一记录（S6D1-08）；重试时执行前拒绝、本地错误、KEY_CONFLICT、无 reason 400 都保留待核对（无 reason 400 比方案保守）；LOCKED 等 2 秒同 key 同字节再发一次，再次 LOCKED、其他非结论结果或等待中挂起都转 unconfirmed；19.4 第 9 步按 C-26 / X34 改为同地址全部不在发送中的补偿记录；记录不存分组名，显示用 GroupDirectory.name，找不到写“分组 #id”；门控、核对、重试权限单测在 RedeemGrantTests，回前台 UI 用例在新类 CompensationForegroundUITests（S6D1-15）；sheet 界面归 S6-09；UI check：SettingsUITests、CompensationForegroundUITests、BalanceReconcileUITests 30/30 通过，Sub2MobileUITests 留给 gate |
| S6-10 | 代理模型、展示规则与接口（Sub2Core） | ✅ | `86d1565` | Proxies.swift 合计会超 700 行，按方案把新建 / 编辑请求拆到新文件 ProxyWrites.swift；allProxies(withCount:) 保持 S2-11 的 /all 语义，全集由 S6-11 逐页调 proxies(page:query:)；ProxyPresentation.latency 多一个 now 参数，“上次测试”直接用已合入的 DisplayFormat.monthDayClock；H03 前的服务端已过期、无账号、回退不是“不回退”时，说明句用设计稿无计数版；IPv6 主机加方括号；只有“已过期”胶囊带红点（照规格，不照设计稿）；新增 29 个单测；UI 测试未运行（本条无界面改动，check 为 UI_SKIPPED） |
| S6-11 | 代理列表与 ProxyStore（横幅、筛选、全部测试） | ✅ | `6e4e958` | 逐页读 admin/proxies（200 一页、id 倒序、最多 50 页，按 id 去重）；首次加载逐页显示，刷新失败保留旧目录；全部测试最多 4 个在途，HTTP 错误的行恢复原值并计失败，加载期间到达的结果按 checked_at 合入新目录。与方案不同：目录完整时 N 取行数；取消的刷新回到原目录、取消的首次加载回到 idle；夹具探测延时 2.5 秒（方案 0.8 秒），以便 XCUI 稳定看到“测试中”；夹具前 7 个代理取账号夹具的地址（jp-tokyo-1 198.51.100.30、us-east-2 198.51.100.77:8080）；FixtureProxySource.replace 遇到不存在的 id 时追加。没做：429 等待提示、地区短名。UI：check ProxiesUITests,AppNavigationUITests 29/29 通过（审查修正 60484d6）审查修正 60484d6：代理列表补上 00 §2.7.2 的 429 规则（BlockRefresh：等待期内不再读取，显示“请求过于频繁，N 秒后自动重试”，等待结束后自动重读）。新增 -ui-proxies-throttled 夹具与对应 UI 测试；check（ProxiesUITests、AppNavigationUITests）30/30 通过。 |
| S6-05 | 兑换码写操作与编辑 sheet（禁用 / 启用、删除、编辑、续期） | ✅ | `87bdd67` | 取舍：撤销成功不出回执，失败沿用禁用 / 启用的错误表；已过期的订阅码改分组也发 group_id；保持的原时间、自定义时间和续期回执按本机时区，时区不同时写“按本机时区 <TZ>”；停用或非订阅的当前分组显示为已选并标“（已停用）”；保存成功等该卡与计数刷新完再关 sheet；未使用 / 已禁用的过期脚注按设计稿；只读令牌下 ··· 还保留“查看使用者 / 查看同一批”等只读项（S6-03 行为）。多出 4 个文件：RedeemCodeWrites 及其单测、RedeemEditSections、RedeemCodesUITests+Writes。UI：RedeemCodesUITests 25 个全部通过（含新增 7 个），没有重跑才通过的。（审查修正 2b902c8）审查修正 2b902c8：保存 / 删除成功后先关 sheet 并出回执，该卡与 stats 改为后台重读；写入进行中禁用“删除兑换码…”；已过期且 expires_at 为空的码默认“保持”（文案“保持（已过期）”，自拟），不再一打开就续期。check RedeemCodesUITests 26/26 通过。 |
| S6-06 | 兑换码生成结果待核对与结果页（核对 sheet、老服务端退路） | ✅ | `2a1fd29` | 数量不符头部写“已核对：服务器上找到 N 个”，记录保留到“我已核对”；老服务端（无 redeem_codes.stats）按类型、面值、分组天数、过期形态、发起人和时间窗匹配，结果为“可能是这一批”，需要“我已核对”，过幂等保留期后不给重试；满页无法判断时的文案是自拟的；重试遇 CONFLICT 归“结果未确认”，不自动核对；放弃加了二次确认；RedeemResultView 多一个可选参数 startedAt；本次运行的重发时间只存在内存里。check：RedeemReconcileUITests、RedeemCodesUITests、SettingsUITests 共 48/48 通过（审查修正 a71148c）审查修正 a71148c：“没找到”页重试结果仍不明时回到待核对页（含 STORE_UNAVAILABLE 和取码失败）；批次记录持久化 lastSentAt，老服务端退路时间窗不再因 App 被回收而缩回 createdAt ± 2 分钟，删除内存里的 RedeemBatchSendLog；check 三个 UI 类 49/49 通过。 |
| S6-12 | 代理详情（延迟块、··· 菜单、停用 / 启用、删除） | ✅ | `4233786` | 数据源直接用会话 ProxyStore 的 source，没有另建 DemoData.proxyDetailSource；停用 / 启用的写与读回拆到 ProxyStatusWrite.swift；纯逻辑放 Sub2Core/ProxyDetailPresentation.swift、会话逻辑放 Session/ProxyDetailModel.swift；读数写“182ms”（不加空格）；H04 只建了接收入口，由 S6-14 发送；被改走账号页（S6-13）和编辑 sheet（S6-14）不在本条。UI：check ProxiesUITests、AccountDetailMenuUITests 46/46 通过，没有重跑才过的用例（审查修正 5193d28）审查修正 5193d28：回到前台重读代理与账号（D18）；老服务端 GET :id 不带 account_count 时保留已显示的计数（AdminProxy.keepingCounts）；停用后才到期的代理在 ··· 菜单给“续期…”，不再直接启用；ProxiesUITests、AccountDetailMenuUITests 已在模拟器上跑过，全部通过。 |
| S6-07 | 批量生成兑换码向导（含 + 的待核对拦截） | ✅ | `502c8b2` | 进度沿用 BalanceWriteProgress，不另建 RedeemGenerateProgress；批次文件读不出时提示 unreadableMessage（00 §2.5.5），“未决记录无法保存，已暂停生成”用于落盘失败；Face ID 在落盘之前，10.5“删掉刚写的记录”不存在；成功后 resolve 失败只上报、照常显示结果；结果不明直接换成待核对页、不弹回执；自定义过期天数非法时隐藏收据；分组读取中或失败也显示“站点还没有订阅类型的分组”；check 跑 RedeemGenerateUITests、RedeemCodesUITests、RedeemReconcileUITests 共 48 例全过、无重跑 |
| S6-13 | 被改走的账号（批量与单个恢复原代理） | ✅ | `d2e8fff` | 全部恢复确认后过 Face ID（按批量），单个滑动只确认；failed 只按 code 给固定文案，重读后已不在列表的写“可能已恢复”；超时读回判定，未确认的回执带“重试”；夹具剩余数改为恢复时写回 FixtureProxySource 行（没在 proxies / proxy 两处叠加）；UI 测试放 UITests/ProxiesUITests+Fallback.swift（原文件加上会超 800 行）；check ProxiesUITests 40/40 通过，AccountDetailMenuUITests 未跑（审查修正 054e278）审查修正 054e278：恢复后通过 ProxyFallbackSignal 通知代理详情重读 GET :id 与 :id/accounts。从账号或搜索进入、目录里没有这一行的详情，计数和「贰」都会更新。为修这个问题顺带改了 S6-12 的 ProxyDetailView：加一个 onReceive。 |
| S6-09 | 发放兑换码（补偿）sheet 与结果待核对页 | ✅ | `b921f1c` | 与规格不同的取舍：①先 Face ID 后落盘，19.5“删掉刚写的记录”不存在；②码被其他用户用了、编号冲突或失效、分组被拒、key 被拒时，待核对页结案并给“重新发放”（原内容预填、换新编号，只有 key 被拒时沿用原码）；③unverifiable 的页面文案是自拟的“无法确认这次发放 / 我已在 Web 核对”；④按 R04 走 35 秒（S6-08 实现），落盘后可“稍后核对”；⑤待核对页上的重试不叠加 Face ID 覆盖层；⑥UI 夹具在 RedeemGrantEffects 里替换发放结果，不改 S6-08 文件。X38 打开前拦截做在用户详情 ⋯，sheet 首屏只作兜底。check 跑 RedeemGrantUITests、SettingsUITests、UserDetailUITests、BalanceReconcileUITests 共 50 个用例全部通过、无重跑（审查修正 ae418d9）审查修正 ae418d9：发送过之后订阅分组不再悄悄回落到第一个；原分组从列表消失时要重新选择，重新选择会换兑换码（GrantDraftState.group(chosen:in:)，落盘时把实际发出的分组写进 groupID）。分组被拒时按规格不额外换编号。 |
| S6-14 | 编辑 / 添加 / 续期代理 sheet | ✅ | `c554944` | 复用 S6-10 的 ProxyFallbackMode / ProxyStatusChange / ProxyUpdateRequest（S6D1-12）；添加的 key 在点“添加”时生成（R05），结果不明时可核对或用同一编号重试；编辑不自动重试，结果不明时读回比对（R06）；改了网络字段时发 ProxyAddressSignal（H04）；已过期 + 保持原有效期 + 停用的脚注改为“仍是已过期”，此时不发 status；停用且已过到期日的代理也按续期打开；下滑拦截桥暂为 fileprivate 副本（S6D1-16）；FixtureProxySource.updateProxy 改为应用全部字段；新增 UI 用例放在 ProxiesUITests+Edit.swift；ProxiesUITests 47/47 通过（审查修正 7e6283a）审查修正 7e6283a 改了三处。核对只认本次添加建出的代理：排除点“添加”时已列出的 id，created_at 不早于点添加时刻减 15 秒，并比对用户名、回退方式、备用代理、提醒天数。添加或编辑停在“结果未确认”时禁止下滑，取消或下滑改问“结果未确认”（继续核对 / 稍后核对），“稍后核对”关闭 sheet 并重读目录。撤销后等添加后的目录重载结束再移除一次，删掉的代理不会再出现。新增夹具 -ui-proxy-add-lost 和 UI 用例 testUnconfirmedAddAsksBeforeClosing。UI 测试未运行（UI_UNAVAILABLE；TOOLCHAIN_EXIT=3，因为 Mac 已升级到 Xcode 27.2），待补跑 check ProxiesUITests。（审查修正 d97c67f）审查修正 d97c67f：testAddProxyThenUndo 在 ab5b4ce gate 首跑失败，根因是测试时序：三次 XCTest 内置等待用掉约 4.2 秒，点撤销时回执已经在淡出，App 按 R17 忽略了这次点按。从回执到撤销之间改用轮询，并用 receiptButton 点撤销，断言没有放宽；ProxiesUITests 独立跑 3 次都是 48/48 全过。 |
| S6-20 | 全局搜索：判定、并发扇出与会话缓存 | ✅ | `09cc5e1` | Sub2Core GlobalSearch.swift（查询判定、各身份发送矩阵、六路请求只复用 R19 查询结构、searchHits 只分派、结果 / 区块 / 文案）与会话层 GlobalSearchSession（防抖 300ms、取消、并发扇出、单路重试、30 秒缓存、晚到丢弃、429 等待到点补发一次，S6D2b-03）；“查看全部 N 个”不带 ›，少于 2 字的提示文案 tooShort 由 S6-21 显示（S6D2b-02）；错误请求只在 ops_monitoring_enabled 明确为 false 时不发；vendor 发送规则是 U01 预留，只有单测覆盖；界面、“查看全部”页、夹具数据源归 S6-21；check 带 AppNavigationUITests：第一次 testSearchDirectoryOpensErrorLogs 超 10 分钟时限（与本条无关），单独重跑与第二次整类 17/17 都通过（审查修正 c8680b9）审查修正 c8680b9：被挂起（D18）截断的读不再按失败落地，而是保持“搜索中”，回到前台时由 foregroundResumed() 补发。SearchHomeView（S6-21）需要在 foregroundRevision 变化时调用它，否则被截断的那几路会一直显示“搜索中…”。 |
| S6-23 | PushCoordinator、推送能力与通知点按路由（需真机与站点 APNs 配置验收） | ✅ | `8409ce9` | 登记记录键沿用 S0-11 的 push.device.<UUID>（规格写 push.deviceID.<id>），新增本机开关键 push.enabled.<UUID>：退出保留、删除站点清除，退出后再登录会自动恢复本机推送；系统给新令牌只对当前站点立即重登，其他站点下次连接时登记（00 §7.2 的取舍）；连接后的自动重登不看 config.ready（S6D2b-14）；改动总表写“脚本不改”，但工程由脚本生成，改了 scripts/generate_project.py（按配置写 CODE_SIGN_ENTITLEMENTS，生成 production / development 两份 entitlements 且都带 Time Sensitive，app 的 Debug 加 APNS_SANDBOX）；点按遇到全局 sheet 时等它关闭再跳转，页面自己的本地 sheet 会随概览栈替换消失（S6D2b-07，未处理）；account.test_finished 只在本会话有该账号测试状态时弹测试 sheet，否则只进详情（没有按 run_id 只读的结果页）；push.test 落在概览 Tab 的 [设置, 推送通知]；匹配不到或未知 type 不做任何导航；新文案“没有拿到推送令牌，请检查网络后再试”（20 秒超时）；不写 PushCoordinator.unregister（退出与删除站点删设备仍由 SiteTeardown 负责）；items.json 未登记的文件：PushDeviceRecords.swift、SiteTeardownTracker.swift、PushCoordinatorTypes.swift、Tests/NativeSessionTests/PushTestSupport.swift；真机验收未做（真实令牌、站点 ready、点按、Release 不带 environment、time-sensitive 送达、App 切换器遮挡），清单见 BACKLOG；check：unit 全过，build 0 warning，UI 跑 PushRoutingUITests、Sub2MobileUITests、SettingsUITests、AccessTokensUITests 共 41/41 通过、无 flaky（审查修正 b2e2bb6）审查修正 b2e2bb6：点按其他站点的通知，改为由当前站点的标签页在没有全局 sheet 时再切站（S6D2b-07 扩到跨站点路径）；退出和删除当前站点之前，先等在途的推送登记，最多 10 秒；删除同地址的其他登录时，保留当前站点登记的设备。check 的 UI 测试 41/41 通过（PushRoutingUITests、Sub2MobileUITests、SettingsUITests、AccessTokensUITests）。 |
| S6-21 | 全局搜索结果页与“查看全部”结果页 | ✅ | `93131e5` | 取舍：“查看全部”不带“›”，用系统 chevron；不到 2 个字符时显示“至少输入 2 个字符”，为本条补的文案（S6D2b-02）；请求块口径以 S6-20 为准；429 等待期间单区失败行与 FailureView 显示倒计时；用户行沿用 UserRow 的 displayName；“查看全部”页下拉刷新失败保留旧行，底部“加载失败 · 重试”。行组件都复用归属条目，未改它们的文件。分组行点进去仍是旧分组详情（S5-06 未合入）。U40 未实机验证。UI：check GlobalSearchUITests、AppNavigationUITests 共 26/26 通过，无 flaky（审查修正 eb583ca）审查修正 eb583ca：SearchHomeView 补上 foregroundRevision → search.foregroundResumed() 的接线（c8680b9 留给本条的那行）。“查看全部”页回前台只补发被挂起截断的第 1 页或下一页。下一页也遵守 429 等待，等待结束自动重读一次，倒计时用 TimelineView 每秒刷新。回前台补读和 429 倒计时没有加 UI 用例，由单测覆盖。 |
| S6-24 | 推送设置页与接收方式详情（订阅、测试、删除） | ✅ | `b0882f8` | 本机未开启时不显示推送内容分区；平台 / 分组范围在 sheet 里点“完成”才提交，其他控件立即整对象 PUT，保存中途的修改合并为再发一次；停用设备恢复文案、“可在 Web 删除”提示照抄规格（待用户拍板，Web 实际没有推送界面）；已有列表时重读失败保留旧列表并显示“刷新失败 · 重试”；自拟文案：订阅失败回执“推送内容没有保存：<原因>”，INVALID_PUSH_SUBSCRIPTION 写“<控件名>的值不被站点接受”；免打扰默认 23:00–07:00，按 GMT 墙上时间换算；设置页通知行有登记 id 时每次出现读一次设备列表；添加 / 编辑 sheet 暂为 ComingSoonSheet 占位（S6-25）；PushDemoStore 在 actor 声明里加了 arguments / config 存储属性和 init；items.json 未登记的文件：PushPresentation+Settings.swift、PushSettingsRulesTests.swift、PushSettingsModel.swift、PushSettingsModelTests.swift、PushSettingsSections.swift、SettingsPresentation(+Tests).swift；check：unit 全过，build 无 warning，UI 跑 PushSettingsUITests（14）、SettingsUITests、PushRoutingUITests 共 35/35 通过，无 flaky（审查修正 bb147c4）审查修正 bb147c4：订阅保存失败后回读列表期间再改的订阅，回读结束后照常发出，不再一直显示成已保存；测试推送遇 404 后的回读跨过站点切换时返回 .cancelled，不会再清掉新站点的本机登记。check（PushSettingsUITests、SettingsUITests）29 个 UI 用例全部通过。 |
| S6-25 | 添加 Bark / ntfy / Webhook 接收方式与站点 APNs 配置编辑 | ✅ | `1becaba` | 取舍：①http 地址只提示不拦（站长可开 push_targets.allow_insecure_http）；②密钥 / 私钥在请求发出时清空，失败后须重填或点“不设置” / “不更换私钥”；③私钥形态检查接受 PRIVATE KEY 与 EC PRIVATE KEY；④主动 step-up 用 isRead: true（通过后这次保存直接发出），被动 STEP_UP_REQUIRED 验证后由用户再点保存；⑤机器凭据 / 未开 TOTP 的拒绝都 reloadSiteSession（提示被划掉也重读）；⑥encryption_key_configured 为 false 时导入置灰、不显示粘贴框；⑦私钥编辑框用关掉智能标点的 UITextView，识别成 PEM 后收起、不回显；⑧两个 sheet 在 App 非活动时盖遮罩并 redacted（S6D2b-10，切换器遮挡要真机验收）；⑨Webhook 脚注补一行“时间戳为请求头 X-Sub2-Timestamp 的 Unix 秒”。新增文案集中在 PushEditCopy（新文件 PushEditCopy.swift）：添加接收方式 / 添加 / 正在添加、http 提示、密钥已清空提示与“不设置”、两句结果未确认、还有内容需要修改、最多 512 字节、两种添加回执、已保存站点 APNs 配置、启用 APNs 推送、凭据 / 私钥 / 发送分区、导入 .p8 文件…、粘贴占位、清除、不更换私钥、不是 .p8 文件、私钥已清空提示、内容已隐藏、放弃修改？。未做：下滑关闭只禁用、不弹确认（等 S6-26 拦截桥）；PUSH_TARGET_IN_USE 没有夹具（单测覆盖）。UI：check 跑 PushSettingsUITests、SecurityPromptUITests、PushRoutingUITests，31/31 通过（审查修正 b833362）审查修正 b833362：APNs 配置保存“结果未确认”后，表单以重新读取的配置为基准（APNsConfigDraft.rebased(on:)：改过的字段保留填写值，其余跟随服务端，私钥“需重新导入”标记保留）；回到前台重读配置时也同样合入；新增夹具参数 -ui-apns-save-unconfirmed 与对应 UI 用例。 |
| S6-26 | 阶段 6 收口：完成度核查、资金与推送专项复核、文档与小结 | ✅ | `645089f` `32c0cee` `81657e4` `0bab3b4` | 按 D28 分四次提交，各自通过 check：26a 共用下滑拦截桥（四份副本合并，新接 PushTarget / APNs / Key 表单 / 新建账号）与 DemoData 死常量 authSessionCount、accessTokenCount；26b 绝对时间转调 C-30、用户详情分区头、代理写后首页刷新、余额发送登记、读类 POST 显式类别、推送同地址收尾补测、U48 与概览进入兑换码核对补测；26c 同地址旧登录（站点列表与登录页根视图）、补偿放弃后各处同时消失、公告结果未确认时的关闭；26d README / ADMIN_MODULES / API_COMPATIBILITY:74。与规格不同的取舍：令牌到期同年不写年份；请求详情月日补零、跨年加年份；check-mixed-channel 按写处理；⑥ 的旧登录行注、“登录「X」后核对”、根视图说明，以及公告“结果未确认”关闭的文案都是自拟的，待用户看截图；首页刷新判定由单测锁住，三个视图里的闭包只靠代码审查。未做：站点菜单里的旧登录、登录设备名、U40 实机检查、推送真机验收。UI 测试：26a 7 类 199/199，26b 12 类 198/198，26c 阶段 6 全部 25 类 446/446，都没有 FLAKY 和基线失败。需要用户拍板：⑥ 的文案与交互、站点菜单里的旧登录、登录设备名、令牌到期同年不写年份、公告“结果未确认”关闭的文案、check-mixed-channel 在 00 §2.4 里算读还是写 |
| U-16 | 兑换码列表与编辑 · 待核对横幅写“共 N 批”、编辑页标“已停用 / 非订阅分组”、状态值无效单独报错 | ✅ | `3ce0bff` | 按用户裁定改规格原文两处：60 §11.3 横幅“等 N 批”→“ · 共 N 批”；60 §9.4 的 STATUS_INVALID 不再共用“分组无效”，改为“状态无效，请重新选择”（新增 RedeemWriteFailure.statusInvalid，三处 switch 与 groupInvalid 同样处理）。订阅分组选项移到 Sub2Core 的 RedeemEditDraft.groupOptions(directory:)：码当前的分组已停用或目录里没有标“（已停用）”，仍启用但已非订阅类型标“（非订阅分组）”（自拟），目录还没读到或读取失败只写名字；目录里没有的已删除分组仍按“已停用”标，不新增“已删除”。check RedeemCodesUITests 28/28，无 flaky；新增 testEditGroupUnmarkedWhileDirectoryUnread。 |
| U-17 | 兑换码批量生成向导 · 第 2 步订阅分组读取中 / 失败给状态与重试；第 3 步自定义过期天数为空或越界时照常显示收据并给范围提示 | ✅ | `38563ee` | 用户反馈 S6-高-6、S6-中-8。第 2 步按 RedeemGroupsAvailability 分三种：读取中“正在读取分组…”（比方案多省略号）、失败复用 BlockFailureRow 显示“读取失败 · 重试”（标识 redeem.generate.groups.failure / .retry）、读到为空才写“站点还没有订阅类型的分组”（沿用 noGroups 标识）；三种都不能下一步。删掉 subscriptionGroups(model:)，改为 groupsAvailability(model:)。第 3 步用 receiptPreview：天数缺或越界时收据照常、过期行写“—”，天数框下写“填 1–3650 天”；提交校验不变。check：RedeemGenerateUITests 13/13，无 flaky；推送时 GitHub 不通，提交在本地分支。（审查修正 d6bcaea）审查修正 d6bcaea：分组读取被切后台取消后（目录回到 idle 且没有读取在途），向导回到前台时会补读，第 2 步不再一直停在“正在读取分组…”；新增夹具 -ui-redeem-groups-cancelled 和用例 testGroupsCancelledInBackgroundAreReadAgainInForeground。 |
| U-19 | 公告详情 · 结束时间已过时发布确认框加提醒、回执改“用户看不到”；详情读取不再带已读统计 | ✅ | `18c357c` | 确认框提醒与回执文字按 S6-高-10 建议；判定与后端 IsActiveAt 一致（now ≥ endsAt），用服务器时钟；已过时回执色调用 caution（自定，待看截图）；新增公开 helper AnnouncementPresentation.hasEnded；编辑页自己的“已发布公告”回执与默认有效期按 scope 不改；详情 load 一律不带 include_read_stats；check AnnouncementsUITests 40/40 通过，无 flaky |
| U-18 | 兑换码核对与补偿 · “用同一编号重试”时叠 Face ID 覆盖层；分不出这一批的说明补下一步 | ✅ | `0620a61` | 新增 BiometricGate.authorize(_:verifying:)，批次重试与补偿共用（compensationSubmission 原内联逻辑改为调用它，行为不变；生成向导第一次生成时的写法未改）；redeemBatchCheck(verifying:)、两页 isVerifying，覆盖层复用 RedeemFaceIDOverlay（去 private）/ GrantFaceIDOverlay；header(for:retry:) 仅“无法判断”看 offersRetry && !isReadOnly，只补前半句的那版文字为方案自拟；-ui-biometric-slow 夹具（1.5 秒）。补偿夹具记录仅 $10、低于门槛，UI 用例改走“发放 $150 → 结果未确认 → 重试”；“无法判断”状态无 UI 夹具，只有单测覆盖。check：RedeemGrant/RedeemReconcile/RedeemGenerate 三类 38/38 通过 |
| U-20 | 公告列表 · 带已读统计的第一页读失败时，自动去掉统计重读一次 | ✅ | `60a2c3e` | droppedReadStats 只在不带统计的重读成功后才置真（方案原文是重读前就置真），两次都失败时下次刷新仍先带统计；除取消、429、401 / 403 外，还不重读 423 合规、续期暂缓、已走过安全提示的错误和会话 / 身份 / 二次验证 / 只读类错误；第 2 页起带统计失败不重读（在 scope 外）；-ui-announcements-error 改为“第一次加载失败”（含不带统计的重读），两条旧单元测试改用不带统计的模型；check AnnouncementsUITests 41/41 通过，无重跑 |

### 阶段 6 小结（S6-26）

材料说明：S6-26 的汇报（应含 S6D2a-07 的逐条对照表、资金专项对照表、推送专项复核、R19 / D27 / X39 / 文件长度与安全 grep 的结论）没有落盘，scratch/s6-26/ 只有一次性脚本，没有输出。下文 (2)(3)(4)(5) 里标“起草时核对”的内容，是起草这份小结时在 `1e28cbc` 上只读复查的结果（git grep / git show，以及在导出的快照上用 python -I 运行 S6-26 留下的 audit_files.py、d27_identifiers.py、r19_paths.py；快照用后已删除）。其余内容都取自进度表、BACKLOG、_decisions-S6.md、S6-26 方案和提交说明；查不到的写“材料里没有记录”。

#### (1) 完成项

- 设置 · 登录设备与管理访问令牌：S6-01 `ca8d54f`（修正 `27e7535`）；S6-02 `d9c1279`。登录设备页有列表、下线单台、“让其他所有设备下线”。撤销到本机时按本机退出（forgetActiveSession）。全部下线后立即隐藏他机，重载失败时保留旧列表。令牌页有列表与吊销；吊销本机令牌时先删推送设备，再发 DELETE，然后在本地擦除凭据。不签发令牌（U02）。
- 兑换码：
  - S6-03 `d66c0e0`（修正 `5b6e896`）：模型、查询、统计、写接口与生成接口（Sub2Core）。
  - S6-04 `7a90a9a`（修正 `227523f`、`2517eb3`）：列表，含筛选、定位、复制（SensitivePasteboard）、查看同一批、待核对横幅。
  - S6-05 `87bdd67`（修正 `2b902c8`）：禁用 / 启用、删除、编辑与续期 sheet。
  - S6-06 `2a1fd29`（修正 `a71148c`）：生成结果待核对 sheet、结果页、老服务端退路。
  - S6-07 `502c8b2`：批量生成向导，以及“+”的待核对拦截。
- 补偿：
  - S6-08 `d52359a`：Sub2Core 规则与接口（performKeyedWrite、门控、核对、重试权限），以及回到前台时自动核对补偿。
  - S6-09 `b921f1c`（修正 `ae418d9`）：发放兑换码（补偿）sheet 与结果待核对页；打开前的拦截做在用户详情的 ⋯ 菜单（X38）。
- 代理：
  - S6-10 `86d1565`：模型、展示规则与接口。
  - S6-11 `6e4e958`（修正 `60484d6`）：代理列表、ProxyStore、横幅、筛选、全部测试；修正补上了 429 等待。
  - S6-12 `4233786`（修正 `5193d28`）：代理详情，含延迟块、··· 菜单、停用 / 启用、删除。
  - S6-13 `d2e8fff`（修正 `054e278`）：被改走的账号页，可全部恢复或单个恢复原代理。
  - S6-14 `c554944`（修正 `7e6283a`）：编辑 / 添加 / 续期代理 sheet。
- 公告：
  - S6-15 `c2b860c`（修正 `526bc68`）：模型、展示规则与接口。
  - S6-16 `b52a4c9`（修正 `e165253`）：列表。
  - S6-17 `0ca73e0`（修正 `3742945`）：详情、预览卡、最小 Markdown，以及发布 / 归档 / 删除。
  - S6-18 `4a64cb1`（修正 `573a1b2`）：编辑 / 新建 sheet，含新建幂等与 H07 核对、编辑 diff。
  - S6-19 `9b16f8c`（修正 `c734708`）：已读情况。
- 全局搜索：
  - S6-20 `09cc5e1`（修正 `c8680b9`）：判定、并发扇出、会话缓存；某一路收到 429 时，等到点再自动补发。
  - S6-21 `93131e5`（修正 `eb583ca`）：结果页与“查看全部”结果页；修正补上了回到前台补发的接线。
- 推送（真机验收未做，见 (7)）：
  - S6-22 `972e43b`：模型、展示规则与接口。
  - S6-23 `8409ce9`（修正 `b2e2bb6`）：PushCoordinator、entitlements 与通知点按路由。
  - S6-24 `b0882f8`（修正 `bb147c4`）：推送设置页与接收方式详情（本机开关、订阅、测试、删除）。
  - S6-25 `1becaba`（修正 `b833362`）：添加 Bark / ntfy / Webhook 接收方式，编辑站点 APNs 配置。
- 收口 S6-26：按 D28 分四次提交。进度表与 BACKLOG 由 `1e28cbc` 写入。
  - `645089f`：共用下滑拦截桥，删除 DemoData 死常量。
  - `32c0cee`：绝对时间转调、用户详情分区头、代理写后首页刷新、余额发送登记、读类 POST 显式类别，以及补测。
  - `81657e4`：同地址旧登录的站点行与登录页待核对，公告结果未确认时的关闭。
  - `0bab3b4`：README、ADMIN_MODULES、API_COMPATIBILITY:74。
- 与阶段 6 相关、在其他阶段完成的：S3-04 `c63c6a8`（DisplayFormat.monthDayClock，C-30）、S3-06 `d2dbc57`（同地址口径与 MoneyRecordOrigin）、S3-07 `0a4db1b`（设置与用户详情的核对流程）、S1-10 `0ed4a0d`（概览三类待核对行）、S1-18 `d293b29`（概览补偿行与旧登录行的 UI 用例）。

#### (2) 60 §19.7 单测与 S6D2a-07 已知缺口对照

- 60 章没有单列测试清单。“实现顺序建议”的阶段 6 段只写了顺序，没有完成标志（阶段 0、1 有）。改动总表“其余单测”一行里，60 章只点了 §19.7。
- S6D2a-07 要求一张逐条对照表：60 §1.7–§19.7、改动总表 60 章各行、U40–U53、R01–R03、R14–R17、R19，每行写实现位置、测试与结论。这张表材料里没有记录。下面只写查得到的部分。

60 §19.7 单测清单只有四项（起草时核对，函数都在 `1e28cbc`）：
- 请求体（三种类型、订阅 `value` 非 0、金额是 number）：RedeemGrantTests.requestBodiesOfTheThreeTypes。位置不同：规格写的是 RedeemCodes.swift 的 RedeemGrantSpec / RedeemGrantRequest，实际是 RedeemGrant.swift 的 RedeemGrantDraft，请求体由 S0-06 的 PendingCompensation 生成。
- `SubscriptionGrantPlan` 四种情况与服务器时区日界：RedeemGrantTests.subscriptionPlanFourCases、subscriptionPlanUsesServerDayBoundary。
- 核对判定（used + 同用户 / unused / 无 / 他人）：PendingMoneyRulesTests.compensationOutcomes（另外还覆盖 unverifiable）。回前台那一轮：CompensationForegroundPassTests。
- 改内容后 code 与 key 都变：RedeemGrantTests.draftStateChangesCodeOnlyAfterASend。测试锁定的口径是：发出过之后改内容才换码，编号随之清空；没发出前改内容不换码；每次确认都换新编号（R05）。

另有一项出自同一节 RedeemCodes.swift 那条改动点（19.7 改动点，非单测清单项）：`RedeemCode.random()` 32 位小写十六进制，测试是 RedeemGrantTests.redeemCodeIsThirtyTwoLowercaseHex。

S6D2a-07 点名的已知缺口与已核实项。结论取自裁定与 S6-26 提交说明；测试函数是起草时在 `1e28cbc` 核对存在的：
- U48（关闭 Face ID 时验证被拒，开关应保持开启）：原是缺口，`32c0cee` 补 SettingsUITests.testDeniedCheckKeepsTheSwitchOnWhenTurningOff。成功路径原来就有 testFaceIDSwitchVerifiesAndShowsTheThreshold。
- 60 §19.1 补偿回执“查看兑换码”：已满足，RedeemGrantUITests.testBalanceGrantFromUserDetail。
- 从概览待处理行进入兑换码核对：原是缺口（只有 HomeUITests.testEarlierLoginRowsAreAnnotatedAndOpenTheirPages 断言离开概览），`32c0cee` 补 RedeemReconcileUITests.testOverviewRowOpensTheCheckHighlighted。
- X34 补偿放弃后各处同时消失：原是缺口，`81657e4` 补 RedeemGrantUITests.testOldLoginCompensationAbandonedLeavesEveryEntry。
- 00 §2.5.4 第 1 条与 60 §17.4（公告结果未确认时的关闭）：原是缺口，`81657e4` 补 AnnouncementsUITests.testUnconfirmedCreateAsksBeforeClosing，另有 AnnouncementEditFlowTests 两条。
- 60 §12.7 第 3 点（docs/API_COMPATIBILITY.md:74）：文档缺口，`0bab3b4` 已改。
- 已有测试的几项：
  - U42：SettingsUITests.testSimpleModeIsGreyedAndAppearanceIsOneChoice、AppPreferencesTests；
  - U43：RedeemReconcileUITests.testOldServerGuessNeedsConfirmationAndRetryReadsCodes、RedeemBatchFallbackTests；
  - U44：AnnouncementsTests 的 Queries 一段（如 announcementListQueryItemsFollowCapability）；
  - U50：SessionsUITests（如 testCurrentRowHasNoSwipeAndExplains）；
  - U52：RedeemGrantUITests.testUnlimitedConcurrencyAndSubscriptionPlan、RedeemGrantTests.availabilityFollowsU52；
  - U53：AccountEditUITests（裁定只给了行号 :190，函数名未核对）；
  - R17：ReceiptCenter.swift，回执 4.2 秒。
- U40：没有实机验证，BACKLOG“搜索 Tab 在实机上的样子”保留。
- 其余 U4x、R01–R03、R14–R16、R19 的逐行结论：未核对。

#### (3) 60 章各节改动点

- §1–§2 搜索：目录首屏 SearchHomeView 在阶段 0（S0-14）已建，阶段 6 接上全局搜索（S6-20、S6-21）：
  - Sub2Core：GlobalSearch、GlobalSearchListing；
  - Session：GlobalSearchSession、SearchResultsListModel；
  - Features/Search：GlobalSearchResultsView、SearchResultsListView、SearchHitRow、SearchFixtures。
  - `APIClient.searchHits(_:)` 只按枚举分派到已有的列表读接口，作为 R19 的例外（S6D2b 交编排者第 3 条）。
- §3 设置：
  - 登录设备、管理访问令牌、通知三个入口与数量（S6-01、S6-02、S6-24）。
  - 站点列表里，凭据已清除、有待核对记录、且同地址另有可去站点的行标“旧登录”：去向是当前站点时只注明、不能点，否则点按切到同地址的那个站点（S6-26 `81657e4`：OldLoginPresentation、KeychainCredentialStore.siteIDsWithoutCredential）。
  - “打开原站点核对”的唯一字面量是 SettingsPresentation.openOriginalSiteTitle。
- §4 登录：根视图的待核对段移到新文件 LoginPendingSection，改列三类记录（S6-26）。
- §5 登录设备：AuthSessions.swift、SessionsView（S6-01）；lifetimeLine 改为转调共用的绝对时间（S6-26）。
- §6 管理访问令牌：AccessTokens.swift、AccessTokensView、AccessTokenRevocation（S6-02）；expiryLine 同年不写年份（S6-26）。
- §7 推送：
  - Sub2Core：Push、PushRequests、PushPresentation(+Settings)、PushTargetDraft、PushEditCopy（S6-22、S6-24、S6-25）。
  - Session：PushCoordinator、PushCoordinatorTypes、PushDeepLink、PushDeviceRecords、SiteTeardownTracker、PushSettingsModel，以及 NativeApp/PushAppDelegate（S6-23、S6-24）。
  - Features/Settings：PushSettingsView、PushSettingsSections、PushSubscriptionSection、PushTargetDetailView、PushTargetSheet、APNsConfigSheet、PushFixtures（S6-24、S6-25）。
  - 两份 entitlements 与 scripts/generate_project.py（S6-23）。改动总表写“脚本不改”，实际改了。
- §8–§11 兑换码（S6-03～S6-07）：
  - Sub2Core：RedeemCodes、RedeemPresentation、RedeemListPresentation、RedeemEditDraft、RedeemGenerate、RedeemGenerateWizard、RedeemBatchFallback、RedeemReconcilePresentation。
  - Session：RedeemCodeWrites、RedeemGenerateSubmission、RedeemBatchCheck。
  - Features/Redeem：列表（RedeemCodesView、RedeemCodeCard、RedeemCodeBox、RedeemCodesModel）、编辑（RedeemEditSheet / Sections）、生成向导（RedeemGenerateSheet / Steps / Model / Entry）、核对（RedeemReconcileView / Model、RedeemResultView、MoneyPendingViews）。
- §12–§14 代理（S6-10～S6-14）：
  - Sub2Core：Proxies、ProxyWrites、ProxyPresentation、ProxyDetailPresentation、ProxyFallbackPresentation、ProxyEditDraft、ProxyEditOutcome。
  - Session：ProxyStore、ProxyDetailModel、ProxyStatusWrite、ProxyFallbackAccountsModel、ProxyEditFlow。
  - Features/Proxies：ProxiesView、ProxyRow、ProxyDetailView / Sections、ProxyLatencyBlock、ProxyFallbackAccountsView、ProxyEditSheet / Sections、ProxyFixtures。
  - 写后首页刷新由 S6-26 接：入口 AppModel.noteProxyWrite() 写在 ProxyDetailView.swift 末尾，判定只用 AccountWriteMark.mayHaveApplied。
  - 账号详情的代理行点进代理详情（改动总表 Models.swift 一行）；API_COMPATIBILITY.md:74 由 `0bab3b4` 改写。
- §15–§18 公告（S6-15～S6-19）：
  - Sub2Core：Announcements(+API)、AnnouncementPresentation、AnnouncementDetailPresentation、AnnouncementDraft、AnnouncementEditOutcome、MiniMarkdown（行内解析只在 Apple 平台编译，S6D1-14）。
  - Session：AnnouncementChangeSignal、AnnouncementListModel、AnnouncementDetailModel、AnnouncementEditFlow、AnnouncementReadsModel。
  - Features/Announcements：列表、详情、预览卡、MiniMarkdownView、编辑 sheet、已读情况。
- §19 补偿（S6-08、S6-09）：
  - Sub2Core：RedeemGrant、RedeemGrantCopy、RedeemGrantPresentation。
  - Session：CompensationSubmission、CompensationForegroundPass。
  - Features/Redeem：RedeemGrantSheet / Steps / Model / Entry / Effects / PendingView。
  - 位置不同：规格写的是 RedeemCodes.swift 与 AppModel 的 `PendingWrite.Kind.redeemGrant`。实际补偿记录用 S0-06 的 PendingCompensation，发送走 performKeyedWrite（R01 / R04）；起草时核对，代码里已没有 PendingWrite。
- 共用件（S6-26）：
  - 下滑拦截：NativeApp/Views/DismissAttemptBridge.swift 与 View.onDismissAttempt，合并 AccountSectionSheet、GroupEditSheet、ProxyEditSheet、AnnouncementEditSheet 四份副本，新接 PushTargetSheet、APNsConfigSheet、UserKeyFormSheet、AccountNewView。
  - 绝对时间：DisplayFormat+DateTime 加 zone 版的 monthDay / monthDayClock，阶段 6 的私有绝对时间实现都改为转调。
  - 其他：用户详情分区头换成 NumberedSectionHeader；AppModel.updateBalance 包进 moneyWritesInFlight.sending；代理测试 / 质量检测、推送测试、check-mixed-channel 显式写 `requestClass: .unkeyedWrite`；DemoData 删去 authSessionCount、accessTokenCount。
- 文档（`0bab3b4`）：
  - README“当前功能”加兑换码、代理、公告、推送（注明未在真机验收）、全局搜索五行，删去“推送尚未实现”；
  - ADMIN_MODULES 新增六节；
  - API_COMPATIBILITY 只改第 74 行。

#### (4) BACKLOG 与前序阶段备注里留给阶段 6 的事项

阶段 0 备注：
- 推送接口与 PushCoordinator：S6-22、S6-23 完成。
- redeem-codes/generate 与 create-and-redeem 的方法级请求测试：已有（起草时核对）。
  - generate：RedeemCodesTests.generateSendsBatchKeyHeadersAndReturnsBatchID 等；
  - create-and-redeem：RedeemGrantTests.createAndRedeemSendsOneKeyedWrite、createAndRedeemChecksOriginAndBody。
- S0-18 的未做项“兑换码面额键盘（阶段 6）”：S6-07、S6-09 已用 AmountKeypad 完成。起草时核对：S6-07 的 RedeemGenerateSteps 用 AmountKeypad，S6-09 的 RedeemGrantSteps 用 AmountKeypad、RedeemGrantModel 用 KeypadInput。
- S0-15 留下的设置页阶段 6 占位（登录设备、管理访问令牌、推送通知、兑换码核对与补偿核对）：由 S6-01、S6-02、S6-24、S6-06、S6-09 换成正式页面。起草时核对：阶段 6 路由与 sheet 的 case 行里已没有 ComingSoonView / ComingSoonSheet，只剩各区域文件 default 的兜底行。

前序 BACKLOG 的原行，处理文字以 BACKLOG 阶段 6 新增的“改原行”为准：
- 让其他设备下线可能连本机一起下线：S6-01 处理，SessionsUITests.testRevokingAllWithLegacySessionSignsThisDeviceOut，结案。
- 推送登记要等待该站点的收尾结束：S6-23 处理，S6-26 核对并补测，结案。
- 资金写待核对的界面与回前台自动核对：全部完成，结案。
- 待核对门控跨站点 id：阶段 6 部分结案；站点列表与登录页根视图由 `81657e4` 补齐；站点菜单另记一行。对照见本节末“资金专项对照”。
- 读类 POST 的安全重发：已收口（`32c0cee`）。check-mixed-channel 在 00 §2.4 里算读还是写，请规格写明。
- 用户详情分区头 meta：`32c0cee` 处理。
- 余额发送登记 MoneyWriteInFlight：`32c0cee` 处理，重试遇到发送中时说“这笔正在发送，请稍候”。
- 请求详情日期格式归属：`32c0cee` 处理。
- 有待核对记录的站点重新登录会多出同名站点：阶段 6 部分由 `81657e4` 处理；站点菜单没改，见 (7)。
- 搜索 Tab 在实机上的样子：未实机验证，行保留。
- 登录设备名：没改，需要用户拍板。
- 缺失值“—”的读屏（用户章其余位置，阶段 3 小结建议并入 S6-26）：没做，不在收口裁定里，行保留。
- 服务器日历整天数有多份同算法实现（阶段 5 行，建议 S6-26 统一）：没统一，新增一行。
- .proxyDetail 占位断言（阶段 2 行）：S6-12 换成了正式页面。起草时核对：UITests 里 route.placeholder 只剩 AccountDetailMenuUITests:253、AppNavigationUITests:98 两处“不存在”断言。BACKLOG 原行没有标结案。
- 请求详情 UI 夹具按请求 ID 查使用记录（阶段 4 行，点名 S6-20 / S6-21 补脚本）：材料里没有处理记录。起草时看 `1e28cbc`，LogFixtures+Detail.requestUsageRecord 仍然一律返回 nil。
- 请求详情按请求 ID 查使用记录遇 429 不记录等待（阶段 4 行，说阶段 6 的请求 ID 搜索才会接入）：材料里没有处理记录。

阶段 1、3 备注：
- S1-12 的“推送落点（阶段 6）”：S6-23 的点按路由处理，告警类目标替换概览栈为告警详情（PushDeepLinkTests.routerOpenGoesToOverviewAndReplacesItsStack）；点按时有全局 sheet 开着，等它关闭再跳转（同文件 deliverPendingWaitsForTheOpenSheet）。
- 阶段 3 小结 (7) 交给 S6-26 的四项：
  - 分区头：已做；
  - 同地址旧站点的显示：已做，站点菜单除外；
  - 余额发送登记：已做；
  - 用户章“—”读屏：没做。

阶段 6 裁定交给 S6-26 的事项（S6D1-16 与交编排者第 5 条）：
- 私有绝对时间改为转调（S6-01、S6-02、S6-03、S6-15、S6-22）：`32c0cee` 完成。S6-12 核实没有私有实现。代理的“MM/DD”“yyyy-MM-dd”按 60 §12.3 / §13.3 / §14.3 保留。
- 合并下滑拦截桥、删除 DemoData 死常量：`645089f` 完成。
- S6-18 的订阅分组筛选：S6-18 已直接用 AdminGroup.isActiveSubscriptionGroup，S6-26 只 grep 核对。
- 代理详情的账号状态徽章（S6D1-11 原定由 S6-26 补）：S6-26 方案的现状写“S6-12 已画（ProxyDetailView.swift:91 / 111）”，本条不再补。起草时核对，`1e28cbc` 的 ProxyDetailView.swift:91 / :111 确实读 liveOps 的可用性画状态。S6-12 的进度行没提这件事。
- BACKLOG 写入的三行（按 run_id 只读的测试结果 sheet、停用设备的恢复文案、切换器遮挡真机验收）：已写入。

阶段 6 自己的 BACKLOG 行：
- 已在后续条目处理、但 BACKLOG 没标结案的：
  - 吊销本机令牌失败后的推送设备：S6-23 在 revokeAccessToken 之后调 registerAgain，起草时核对 AppModel+Session.swift:138；
  - 代理列表的 429 等待：`60484d6`；
  - 批次重发时间不跨重启保存：`a71148c` 持久化 lastSentAt，起草时核对 RedeemBatchSendLog 已为 0 处；
  - 全局搜索回到前台补发的视图接线：`eb583ca`；
  - 推送两个 sheet 的下滑关闭确认：`645089f`；
  - ProxiesUITests 拆文件：S6-14 的用例放在 ProxiesUITests+Edit.swift。
- 已结案并改原行的：
  - 公告编辑 sheet 结果未确认时仍可关闭：`81657e4`；
  - 合并下滑先确认的 UIKit 桥：`645089f`；
  - 兑换码列表入口的 UI 测试：-ui-redeem-open / -ui-redeem-reconcile 两个参数保留；
  - 代理有效期日期：结论是不改。
- 保留不做的：
  - “刷新失败 · 重试”横幅收口、筛选胶囊样式重复：都是纯重构；
  - 待核对页重试的 Face ID 覆盖层：交互变化，要等用户。
- 公告列表与公告已读在 429 等待后重读也会取消自己（原行写“由公告条目的线处理”）：材料里没有处理记录。起草时看 `1e28cbc`，两个 retryAfterWait 仍在函数内直接 await 重读；问题是否还在，未核对。

资金专项对照（BACKLOG“待核对门控跨站点 id”原行写“对照表与测试名见阶段 6 小结”）。S6-26 汇报里的对照表材料里没有记录。下面按 S6-26 方案现状列出的已有测试和 S6-26 新增的测试整理，函数名起草时在 `1e28cbc` 核对都存在：
- R03 门控按同地址计入，含旧站点 id：PendingMoneyRulesTests.redeemAndCompensationGates、gateCountsSameAddressRecordsByKind、redeemGateCountsSameAddressOldSiteBatches；RedeemGrantTests.compensationGateBlocksAcrossSameAddressSiteIDs。
- 只有批次有“仍要生成新的一批”这个例外，补偿没有例外：
  - PendingMoneyRulesTests.redeemGateKeepsBothBatchesAfterOverride；
  - RedeemGenerateUITests.testPendingBatchInterceptsPlus、testOldLoginBatchAlsoIntercepts；
  - 补偿打开前拦截：RedeemGrantUITests.testOtherAdministratorsOldLoginRecordFromUserDetail。
- 同地址旧站点 id 的核对与重试：RedeemGrantTests.compensationReconcileAcceptsSameAddressOldSite、compensationRetryPermissionAcrossSiteIDs；RedeemCodesTests.generateAcceptsSameAddressRecordAndRejectsOtherAddress。
- 回到前台只核对余额和补偿，不核对批次：CompensationForegroundUITests.testForegroundCheckCoversSameAddressOldLoginOnly。余额正在发送时跳过：BalanceKeypadUITests.testForegroundCheckSkipsTheTopUpGoingOut（`32c0cee`）。
- 同一条记录在多处同时消失：
  - RedeemReconcileUITests.testCheckFindsTheBatchAndClearsBannerAndSettings、testOldLoginBatchRetryClearsEveryEntry；
  - 补偿：RedeemGrantUITests.testOldLoginCompensationAbandonedLeavesEveryEntry（`81657e4`）。
- 设置待核对、站点列表与登录页根视图：SettingsUITests.testSameAddressOldLoginRecordsAreCheckedHere、testOtherAddressRecordStillOpensItsSite、testOldLoginRowAndRootPendingListFollowTheAddress（`81657e4`）。
- 用户详情与概览：BalanceReconcileUITests.testBannerShowsEarliestOldLoginRecordFirst；HomeUITests.testEarlierLoginRowsAreAnnotatedAndOpenTheirPages（方案给的是 HomeUITests:731 / :749 两处行号，另一处的函数名未核对）；概览进兑换码核对：RedeemReconcileUITests.testOverviewRowOpensTheCheckHighlighted。
- 发送中登记：批次与补偿原来已经登记；余额由 `32c0cee` 补，BalanceReconcileSessionTests.retryOfARecordGoingOutSaysSoAndKeepsIt。

推送专项：
- SiteTeardownTracker 按规范化地址等待：PushCoordinatorTests.connectWaitsForTeardownOfSameAddress、teardownTrackerWaitsForSameAddressOnly。S6-26 补 registrationWaitsForTheTeardownOfAnotherSiteIDAtTheSameAddress（`32c0cee`）。
- 方案 risks 里列的安全复核项（日志不出现敏感值、UIPasteboard、description 屏蔽、切换器遮挡、APNS_SANDBOX、深链只认已知 type）：S6-26 的结论材料里没有记录。起草时只查了其中两项，见 (5)。

#### (5) 核查结果

S6-26 自己的核查（对照表、R19、D27、X39、文件长度、安全 grep）：结论材料里没有记录。BACKLOG 与提交说明里能查到的只有这几条：
- 推送收尾等待已核对；
- 门控已逐处复核（明细见 (4)）；
- U40 没有实机；
- 代理日期保留规格写法；
- 读类 POST 已显式声明类别。

起草时在 `1e28cbc` 上只读复查（不是 S6-26 的结论）：
- 改动总表 60 章的文件与符号（audit_files.py）：
  - 列出的 39 个文件都在。
  - 符号有 4 个没命中，都能解释：ManagementView 按规格应删除，没命中是对的；RedeemGrantSpec / RedeemGrantRequest 是名字不同，见 (3) §19；NSFaceIDUsageDescription 在 Info.plist 里，脚本另查 Info.plist 的结果为有。
  - pbxproj 里 APNS_SANDBOX 只出现在 Debug 配置的 SWIFT_ACTIVE_COMPILATION_CONDITIONS（"DEBUG APNS_SANDBOX"）。Release 用 production entitlements，Debug 用 development，两份都带 Time Sensitive。
- R19（r19_paths.py）：
  - 阶段 6 的代理、兑换码、公告、推送、会话、令牌接口路径，每条在 Sub2Core 里各出现 1 处。
  - 例外是 Announcements+API.swift：GET admin/announcements 出现 3 处（列表、分段计数、H07 标题查找，都经 AnnouncementListQuery.queryItems），POST admin/announcements 出现 2 处（有能力的幂等新建，以及无能力时只发一次，都在 createAnnouncement 里）。这几处都是同一组接口的内部实现。
  - searchHits 例外没有另查。
- D27（d27_identifiers.py，粗查）：
  - 12 个阶段 6 UI 测试类里有 387 个标识，49 个没在 App 源码里直接找到字面量或末段插值。
  - 抽查 redeem.card.<id>.*、search.section.*、announcement.markdown.list.*、redeem.result.code.* 等，都是中间段插值，属于脚本漏判。
  - 其余（如 search.user.<id>、alerts.main、*.header.title、*.keypad.key.*）没有逐个复核。这些用例在 `0bab3b4` 的全量 gate 里都通过。
- X39：Features/Redeem、Proxies、Announcements、Search、Settings 与 LoginPendingSection 里，`NavigationLink {` 和 `NavigationLink(destination:` 都是 0 处。
- 占位残留：
  - ComingSoonView / ComingSoonSheet 只出现在 AppDestinations 的定义、各区域文件的 default 兜底行，以及 AnalyticsDestinations 的单图兜底（阶段 4）。
  - UITests 里 route.placeholder 只在两处“不存在”断言里出现。
  - 旧符号 ProxyManagement、AccessTokenItem、PendingWrite、pendingWrites 都是 0 处。
- 文件长度：超过 800 行的只有 UITests/AnalyticsUITests.swift（830 行，阶段 4 的文件，BACKLOG 已新增一行）。其次是 HomeUITests 787、AccountTestCenterTests 785、UserKeysUITests 773、AnnouncementsUITests 753。
- UIPasteboard：阶段 6 的目录里没有直接使用。全仓另有 OAuthFlow、RequestResolveControls、UserEditToolbar、ErrorDetailsView 四个文件直接使用，都不在阶段 6，是否合规未核对。
- 日志不出现敏感值、description 屏蔽、深链只认已知 type：未核对。

#### (6) 与规格不同的取舍（阶段汇总，各条目的细项见上表备注）

- 收口（S6-26）：
  - 令牌到期日同年不写年份；
  - 请求详情月日补零、跨年加年份（“03/05 09:02:03”）；
  - check-mixed-channel 按写处理；
  - 同地址旧登录的行注、“登录「X」后核对”、根视图说明，以及公告“结果未确认”关闭的文案都是自拟的；
  - 首页刷新的判定由单测锁住，三个视图里的闭包只靠代码审查。
- 登录设备与令牌（S6-01、S6-02）：
  - 撤销到本机时走 forgetActiveSession，新拟提示“本机已下线，请重新登录。”，不走 logout；
  - 非本机条数不少于 1 时才显示“让其他所有设备下线”，全部下线后不出回执、只重载；
  - 吊销他行（含 404）给回执“已吊销「名称」”；
  - 当天到期写“今天到期”（caution）；
  - 重载失败时保留旧列表，显示“刷新失败 · 重试”；
  - 不签发令牌（U02）；
  - 登录设备文案按 60 §5 实现，没按 00 §1.8（设备名为空时显示 client_type、“其他设备会立即退出登录”；“立即”也与 00 §1.7.3 的 fail-open 不符），规格待统一（S6-01）。
- 兑换码（S6-03～S6-07）：
  - 首次发送收到其他 4xx 时删除记录、回第 3 步，408 按结果不明；
  - admin_* 写“余额（管理员调整）/ 并发（管理员调整）”；
  - 只读令牌下 ··· 保留复制、查看使用者、查看同一批；
  - 卡片按钮行只有 ···；
  - 查看同一批时清空搜索，在同一批里输入搜索词会退出同一批；
  - “等 N 批”直接接在标题后；
  - 禁用 / 启用的撤销成功不出回执；
  - 已过期的订阅码改分组也发 group_id；
  - 保持的原时间、自定义时间和续期回执按本机时区，时区不同时写“按本机时区 <TZ>”；
  - 当前分组已停用或不是订阅分组时，仍显示为已选并标“（已停用）”；
  - 已过期且没有过期时间的码，默认“保持（已过期）”；
  - 生成数量不符时，记录保留到点“我已核对”；
  - 老服务端退路的结果是“可能是这一批”，须点“我已核对”，过了幂等保留期不给重试；
  - 老服务端满页、分不出这一批时的文案是自拟的（“无法判断这一批是否已生成 / 最近生成的兑换码太多，分不出这一批。请到 Web 的兑换码列表核对。”），待设计确认（S6-06）；
  - 重试遇到 CONFLICT 归“结果未确认”，不自动核对；
  - 放弃加了二次确认；
  - 生成向导先过 Face ID 再落盘（10.5“删掉刚写的记录”不存在）；
  - 结果不明直接换成待核对页；
  - 自定义天数非法时隐藏收据；
  - 分组读取中或失败时，也显示“站点还没有订阅类型的分组”。
- 补偿（S6-08、S6-09）：
  - 发送走 performKeyedWrite（35 秒），不用 19.7 的 send(PendingWrite) 与 40 秒；
  - 19.4 第 9 步改为核对同地址、全部不在发送中的补偿记录（C-26 / X34）；
  - 重试遇到没有 reason 的 400 保留待核对；
  - 记录不存分组名，显示时用 GroupDirectory.name，找不到写“分组 #id”；
  - 先过 Face ID 再落盘；
  - 码被其他用户用了、编号冲突或失效、分组被拒、key 被拒时，待核对页结案并给“重新发放”；
  - unverifiable 的页面文案是自拟的；
  - 待核对页上的重试不叠加 Face ID 覆盖层。
- 代理（S6-10～S6-14）：
  - proxies.fallback_accounts 缺失时按代理章处理（60 §0.2 / §13.4：不提供批量恢复页，改写说明句），没按 00 章 capability 表的“拉全部账号本地筛、逐个恢复”，规格待统一（S6-10）；
  - 质量检测的客户端超时暂定 95 秒、不自动重试，00 §2.3 超时表里没有这一类（S6-10 定，S6-12 的详情页沿用）；
  - H03 之前的服务端，说明句用设计稿的无计数版；
  - 只有“已过期”胶囊带红点（照规格，不照设计稿）；
  - 目录完整时 N 取行数；
  - 读数写“182ms”，不加空格；
  - “全部恢复”确认后过 Face ID，单个滑动恢复只确认；
  - failed 按 code 给固定文案；
  - 添加的 key 在点“添加”时生成；
  - 编辑不自动重试，结果不明时读回比对；
  - 已过期、保持原有效期、停用三者同时成立时，脚注改为“仍是已过期”，不发 status；
  - 停用且已过到期日的代理按续期打开。
- 公告（S6-15～S6-19）：
  - 没有 capability 时新建也带 key、只发一次（按 60 §0.2；00 §5 表写不带）；
  - 已读比例写一位小数；
  - 起止按本机时区，更新于、阅读时间、统计于按服务器时区；
  - 列表补了加载中、刷新失败、加载失败、429 等待四种状态；
  - Markdown 认三级小标题，连续行并成一段；
  - key 在点“存草稿”或确认“发布”时生成（17.4 写的是 sheet 打开时）；
  - eq 与余额 ≤ 0 的单条件只读，编辑不发 targeting；
  - 多条件只读时隐藏分段；
  - 指定时间的初值是下一个整点，结束时间 +7 天；
  - H07 用 5 分钟窗口加 60 秒时钟误差；
  - 编辑结果不明时读回比对；
  - 已读页徽章沿用“符合条件 / 不符合”，不符合条件的行只把邮箱改 ink2。
- 全局搜索（S6-20、S6-21）：
  - “查看全部 N 个”不带“›”；
  - 不足 2 个字符时显示“至少输入 2 个字符”；
  - 错误请求只在 ops_monitoring_enabled 明确为 false 时不发；
  - 某一路收到 429 时，等到点再自动补发一次。
- 推送（S6-22～S6-25）：
  - Bark / ntfy / Webhook 登记也带 locale 与 timezone；
  - “最近失败”只在 last_error 不早于 last_success_at 时追加；
  - 失败文案走 PushPresentation，不改 ReasonCatalog；
  - 登记记录键沿用 push.device.<UUID>（规格写 push.deviceID.<id>），另加本机开关键，退出后再登录会自动恢复本机推送；
  - 系统给新令牌时只对当前站点立即重登；
  - 连接后的自动重登不看 config.ready；
  - 改了 scripts/generate_project.py；
  - 点按遇到全局 sheet 时，等它关闭再跳转；
  - account.test_finished 只在本会话有测试状态时弹 sheet；
  - 未知 type 不导航；
  - 本机未开启时不显示推送内容；
  - 平台 / 分组范围在 sheet 里点“完成”才提交；
  - 停用设备的恢复文案与“可在 Web 删除”照抄规格；
  - 免打扰默认 23:00–07:00；
  - http 地址只提示、不拦；
  - 密钥 / 私钥在请求发出时清空；
  - 私钥接受 PRIVATE KEY 与 EC PRIVATE KEY；
  - 两个 sheet 在 App 非活动时盖遮罩；
  - Webhook 脚注补了时间戳的说明；
  - 自拟或新拟的文案：
    - 订阅失败回执“推送内容没有保存：<原因>”，INVALID_PUSH_SUBSCRIPTION 写“<控件名>的值不被站点接受”（S6-24）；
    - 20 秒拿不到推送令牌时提示“没有拿到推送令牌，请检查网络后再试”（S6-23）；
    - 添加接收方式与 APNs 配置的一批新文案，集中在 PushEditCopy（S6-25）。

#### (7) 未做项及原因

- 站点菜单里的同地址旧登录：裁定只点名站点列表，要用户拍板（建议在 AppModel.switchTo 里统一改去同地址的站点）。
- 登录设备名：仍发 UIDevice.current.name，要用户拍板。
- U40 搜索 Tab 实机检查：没有实机。
- 推送真机验收：需要付费 Apple Team 签名、真机和站点 APNs 配置，清单见 BACKLOG。验收项有：真实令牌登记、冷启动与后台点按、Release 不带 environment、App 切换器遮挡等。
- 按 run_id 只读的测试结果 sheet、“可在 Web 删除”文案改写、停用设备的恢复文案：默认不做或照规格，等用户。
- 用户章其余位置“—”的读屏：不在收口裁定里。
- “刷新失败 · 重试”横幅收口、筛选胶囊抽成共用组件：纯重构。
- 补偿待核对页重试的 Face ID 覆盖层：交互变化，要等用户。
- 服务器日历整天数的三份实现（AccessTokens.daysLeft、ProxyExpiry.days、RedeemPresentation.daysUntil）：没统一，记 BACKLOG。
- 新建类写入（代理、公告、分组）结果未确认、关闭 sheet 后拦截再次新建：由各模块决定。
- 只有单测、没有 UI 用例的：
  - 代理编辑超时读回（ProxyEditFlowTests）；
  - 全局搜索 vendor 发送规则（U01 首版拒绝 vendor 登录）；
  - 全局搜索的 429 等待与回到前台补发：S6D2b-03 写明不加 429 的 UI 用例；`eb583ca` 的回前台补读和 429 倒计时由单测覆盖；
  - 公告已读情况的点行用例只断言离开本页（S6-19，S3-05 不在依赖链）；
  - PUSH_TARGET_IN_USE 没有夹具，只有单测（S6-25）。
- 推送的已知限制：
  - 推送点按替换概览栈时，页面自己弹出的本地 sheet 会跟着消失（S6D2b-07，S6-23 写明未处理）；
  - 推送点按的待跳转目标不过期；
  - 跨站点点按只等 AppRouter 的全局 sheet；
  - 切站时上一站点在途的登记可能留在服务端；
  - 订阅整体 PUT 会丢掉 App 不认识的事件。
- 规格没列、暂不做的：Bark 地址自动拆分与 ntfy 公开主题提示。
- 代理地区短名：没做。用系统全称（香港显示“中国香港特别行政区”），与 60 §12.3 示例“中国香港”不同，待用户定。
- 已记 BACKLOG，待后端或以后处理：
  - 请后端：生成兑换码和发放补偿时订阅分组无效返回 500 且没有 reason（两行）；GET /admin/redeem-codes/:id 不带 user / group；删除不存在的公告返回 200；提供 redeem_codes.batches，以便精确核对批次（U43）。
  - 以后再改：ANNOUNCEMENT_* 收进 ReasonCatalog；补偿记录存 groupName；代理夹具的账号数与账号页不一致。
- docs/NATIVE_CONTRACT.md 的阶段 6 签名：S6-26 方案列为范围外，建议集成者或后续文档条目处理。起草时看，该文件没有兑换码、代理、公告、推送的内容。
- 材料里没有处理记录的前序行：请求详情 UI 夹具按请求 ID 查使用记录、请求 ID 查使用记录遇 429 不记录等待、公告两页 429 等待后重读会取消自己，见 (4)。
- 需要用户拍板、或已按默认值实现等用户确认的，共 47 条，都按默认值实现。来源是 _decisions-S6 批次 2b、2a 末尾的“需要用户拍板”（批次 1 写明没有新增），以及进度备注与 BACKLOG 阶段 6 里标“待用户确认 / 待拍板”、或标“自拟”且明说待确认的地方。分七类：
  - 设置、登录与站点 5 条：撤销本机时的提示文案、同地址旧登录在站点列表和登录页的文案与去向、站点菜单里的旧登录、登录设备名、令牌到期同年不写年份。
  - 兑换码与补偿 13 条：只读令牌的 ··· 菜单、“等 N 批”的写法、同一批里的搜索、REDEEM_CODE_STATUS_INVALID 文案、禁用 / 启用的撤销回执、当前分组已停用时的显示、“保持（已过期）”、老服务端“无法判断这一批”的文案、向导分组读取中 / 失败时的显示、自定义天数非法时的收据、补偿重试遇到没有 reason 的 400、补偿“码被别人用了 / 无法确认”两种页面、待核对页重试的 Face ID 覆盖层。
  - 代理 5 条：巡检间隙“已到期 · 等待处理”的说明句、地区短名、停用后才到期的提示、全部恢复是否过 Face ID、逐项恢复失败的文案。
  - 公告 9 条：已读比例的位数、列表已读统计失败拖垮整页、重新发布已过期的公告、详情是否去掉 include_read_stats、H07 核对时间窗、编辑结果不明时的读回、eq 与余额 ≤ 0 的条件只读、不符合条件行的视觉、“结果未确认”关闭的文案。
  - 推送与搜索 7 条：“可在 Web 删除”提示、按 run_id 只读的测试结果页、停用设备的开关与恢复文案、开启前预设推送内容、待跳转目标不过期、Bark 地址拆分与 ntfy 公开主题提示、全局搜索的两处显示细节。
  - 规格口径要统一的 6 条：check-mixed-channel 算读还是写、无能力时新建公告带不带 key、fallback_accounts 缺失时的口径、质量检测超时、登录设备文案（00 §1.8 与 60 §5）、新建类写入结果未确认后是否拦截再次新建。
  - 需要用户提供条件的验收 2 条：推送真机验收、搜索 Tab 在 iOS 26 / 27 真机上的样子。

#### (8) UI 测试运行情况

各条目的 check（数字取自上表备注）：
- 登录设备与令牌：
  - S6-01：34/34。修正 `27e7535` 新增了夹具与用例，数字材料里没有记录。
  - S6-02：41/41。
- 纯 Core 条目没有 UI 类（UI_SKIPPED，或 TOOLCHAIN / UNIT / BUILD 为 0）：S6-03、S6-10、S6-15、S6-22。
- 公告：
  - S6-16：30/30；
  - S6-17：24/24；
  - S6-18：30/30；
  - S6-19：38/38，单元测试 1572 + 466，没有不稳定用例。
- 兑换码：
  - S6-04：44/44，没有重跑；
  - S6-05：25 个全过，修正后 26/26；
  - S6-06：48/48，修正后 49/49；
  - S6-07：48 个全过，没有重跑。
- 补偿：
  - S6-08：30/30，Sub2MobileUITests 留给 gate；
  - S6-09：50 个全过，没有重跑。
- 代理：
  - S6-11：29/29，修正后 30/30；
  - S6-12：46/46，修正后也全过；
  - S6-13：40/40，AccountDetailMenuUITests 没跑；合入后 check 58/58；
  - S6-14：47/47。审查修正 `7e6283a` 时 UI 没跑（UI_UNAVAILABLE、TOOLCHAIN_EXIT=3），集成 check 也是 UI_UNAVAILABLE。进度表“待补跑 check ProxiesUITests”一直没更新；之后 S6-26 的三次 check 都含 ProxiesUITests，全量 gate 也通过了。
- 全局搜索：
  - S6-20：AppNavigationUITests 第一次 testSearchDirectoryOpensErrorLogs 超过 10 分钟时限，单独重跑和第二次整类 17/17 都通过；合入后 check 36/36；
  - S6-21：26/26，没有不稳定用例。修正 `eb583ca` 没加 UI 用例，由单测覆盖。
- 推送：
  - S6-23：41/41，修正后 41/41，没有不稳定用例；
  - S6-24：35/35，修正后 29/29；
  - S6-25：31/31，修正 `b833362` 合入后 check 32/32。

S6-26 的 check（线 B，scratch 日志）：
- 26a（`645089f`）：7 类 199/199，单元测试 2737 + 1358。
- 26b（`32c0cee`）：12 类 198/198，单元测试 2743 + 1363。
- 26c（`81657e4`）：阶段 6 全部 25 类 446/446，单元测试 2749 + 1366。
- 26d（`0bab3b4`）：不带 UI 类，单元测试 2749 + 1366，编译通过。
- 四次 TOOLCHAIN / UNIT / BUILD 都为 0；前三次 UI_FLAKY 无、没有基线失败；26d 没跑 UI 类（S6-26-tip-quick.log 为 UI_SKIPPED）。
- 另有一次先写测试的红灯记录：CredentialLeaseTests 因 siteIDsWithoutCredential 尚未实现，编译失败。
- 各次 check 跑了哪些类，取自 S6-26 说明，日志里没有逐类数字。

阶段 6 期间的全量 gate（除注明的一次外，取自“进度表记录”提交说明）：
- S6-11 合入后：单元测试 1825 + 569，UI 331/331。AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues 重跑后通过。
- S6-13 合入后：定期 gate 465/465，没有重跑。
- S6-20 合入后：定期 gate 673/673。AccountCredentialUITests.testHealthyKeyAccountReplacesFromMenuAndRow 首次超时失败、重跑通过。
- 2026-11-02 定期 gate（`ab5b4ce`）：单元测试 2725 + 1342，UI 829/829。ProxiesUITests.testAddProxyThenUndo 首跑失败、重跑通过。这次 gate 取自 scratch 日志（gate-ab5b4ce.log），不在“进度表记录”的提交说明里。
- S6-26 合入后（主工作区 `0bab3b4`）：TOOLCHAIN / UNIT / BUILD / UI 全部 EXIT=0，单元测试 2749 + 1366，UI 857/857，没有失败用例。FLAKY 1 个，AccountCredentialUITests.testHealthyKeyAccountReplacesFromMenuAndRow：回执在慢模拟器上先于断言消失，重跑通过。

不稳定用例：
- ProxiesUITests.testAddProxyThenUndo（S6-14 的用例）：`ab5b4ce` 的 gate 里首跑失败、重跑通过。根因记在 scratch/S6-14-fix-commit.txt：测试没能在回执的 4.2 秒内点到“撤销”，属于测试时序问题，App 行为符合 R17。另一条工作流正在修，起草时还没有合入。
- AccountCredentialUITests.testHealthyKeyAccountReplacesFromMenuAndRow（阶段 2 的用例），两次 gate 各重跑一次后通过。
- AppNavigationUITests.testSearchDirectoryOpensErrorLogs 偶发卡死，BACKLOG 已记。
- AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues，一次 gate 里重跑后通过。
