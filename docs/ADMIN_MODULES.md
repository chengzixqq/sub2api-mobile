# 管理模块与滚动 RPM（2026-10-16）

本次沿用 `codex/native-ios-rebuild` 的同一套原生源码；后端接口参考共享源码 `e5ab7e4f4c136a8faf40fd06694ab0a6bf6f6925`；原生 App 阶段 0 起按 sub2 `main` `70116315d` 之后核对。不更改后端、不部署服务器。以下描述功能与契约；构建和真机结果以 `ACCEPTANCE.md` 的最新记录及交付 manifest 为准。

## 入口与范围

使用记录、统计分析、分组管理从搜索 Tab 的目录进入（阶段 0 起不再有底部“管理”）。概览右上角可以打开统计分析；告警、账号 / 用户 / 分组详情与模型页可跳到带条件的使用记录，账号详情还可跳到账号列表；分组详情的“记录与关联”另可进入该分组的 API 密钥页与订阅页，成员直接列在详情里。

请求记录读取 `GET /admin/usage`，使用 `count_mode=deferred`、每页 100 条、时间倒序、按需分页，`timezone` 为站点时区。`total`/`pages` 可以为 null，按 `has_more` 判断是否继续；不要求大站点先执行全量计数。时间、用户、账号、分组、API Key、模型、请求 ID 等过滤由后端执行。实际扣费读取 `actual_cost`；账号成本优先读取服务端算好的 `account_cost`，旧服务端没有该键时按 `provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0` 计算，保留 Decimal 和缺失值。站点有 `api_keys.masked_view` 时请求带 `key_view=masked`；无论哪种服务端，App 都不解码 `api_key.key` 明文，只读名称与 `key_masked`。请求详情分成功 / 失败 / 恢复三种样子，展示耗时、Token 分解、费用、上游尝试（没有尝试链能力时按上游错误事件估算）、关联对象与标识，错误可标记已处理并撤销，不读取请求/响应正文。

使用记录默认近 24 小时，时间胶囊另有近 1 小时 / 7 天 / 30 天与自定义（≤ 366 天）。滚动预设每次加载（首屏、下拉、翻到下一页）都取现在重算窗口；自定义是固定起止，不自动刷新。条件胶囊可移除，旧服务端不支持的条件置灰并说明原因；改时间或条件时保留另一方。页面可见且在前台时每 60 秒增量刷新：用量明细与错误请求用 `since_id`，新行插在顶部，停在顶部时才把列表裁到 500 行，每 10 次增量后读一次第 1 页校准；上游错误每次按时间窗读第 1 页。

错误日志分为客户端失败请求 `/admin/ops/request-errors` 和上游错误 `/admin/ops/upstream-errors`，按需读取同路径 `/:id` 的详情。两种日志都能按时间、账号、分组、用户、API Key、模型（请求模型）与请求 ID 筛选（D03），只有早于 D03 的旧服务端的上游错误仍只认时间、账号、分组与状态，App 对它先套 `upstreamErrorFilter()`。错误日志一律带 `view=all`（包含用户自身余额、额度、频率限制），时间用固定起止或 `time_range`（5m / 30m / 1h / 6h / 24h / 7d / 30d）；各处的“近 24 小时 N 条”用同一组参数加 `page=1&page_size=1` 读 `total`。上游错误包含重试后恢复的请求（`status_code` < 400）；列表项没有上游状态码，App 从 `message` 的 `Recovered upstream error <码>` 解析，解析不到时按阶段显示“鉴权”或“恢复”。站点禁用 Ops 或权限不足时局部报告错误。正文、堆栈、完整 headers 不进入 DTO；可见摘要额外脱敏授权、Cookie、密钥、URL 中的凭据等字段。

## 账号

列表：账号 Tab 按平台分区显示三行列表，请求 `GET admin/accounts?lite=1&page_size=500&sort_by=urgency`，第 1 页带 `include_counts=1`，最多加载 2,000 行，ETag / 304 由 `ConditionalCache` 透明处理。胶囊与平台菜单走服务端 `status` / `platform` 参数；组头计数与 Tab 徽标读 `accounts/status-summary`，没有该能力时本地计数，徽标读 `dashboard/stats` 的 `error_accounts`。组头告警牌与监控 · 告警共用一份告警中列表。每行今日金额读 `today-stats/batch`。前台可见时每 60 秒用 `runtime/batch` 轻刷新；状态或调度开关变化、写操作成功后、每 5 分钟做完整刷新。旧站点按名称全量分页，本地推导状态与排序；`status` 参数被拒（400 `INVALID_ACCOUNT_STATUS_FILTER`）时本会话改走同一条旧站点路径。

详情：状态卡与按钮行，加容量 / 今日 / 记录与基础、调度、凭据、代理、模型、高级六个编辑分区。编辑一律 `PATCH` + `If-Match`，版本号是详情 `GET` 的 ETag `cv-N`，不进缓存。412 先比对字段，再静默重发或询问；混合渠道 409 用 Web 的文案确认。没有 `accounts.patch` 时以 `GET :id` 的最新整份为底合并、整份 `PUT`，敏感凭据键不回传，凭据未脱敏的更旧站点改凭据要去 Web。可撤销：调度开关、启用 / 停用、内联编辑；不可撤销：恢复状态、恢复原代理、更换 API Key、刷新令牌、重新授权。带 key 的写按 00 §2.5 同 key 重试，仍不明转待核对；其余写不自动重发，超时先读回核对。任何账号写成功或可能已生效后，概览下次可见时以 `nocache` 刷新。

测试与新建：测试连接读 SSE 的 `test_result`，关闭 sheet 不取消，结束后概览与列表刷新。新建账号以 `schedulable=false` 创建，测试通过再启用。批量只有停止 / 启用调度。删除、批量、更换 API Key 与重新授权受 Face ID 门控。

## 统计分析

统计分析是一页卡片流：范围条（今天 / 7 天 / 30 天 / 自定义，范围与筛选按站点记在本机）与分组或模型二选一筛选，下面依次是计费趋势、利润明细、排行、RPM / TPM 趋势与更多图表。“今天”、桶边界与横轴按站点时区，设备时区不同时说明行加“（站点时间 UTC+8）”；页面可见时每 60 秒刷新，下拉、回前台也刷新，各卡独立加载、失败与重试。

汇总 `/admin/usage/stats`、趋势 `/admin/dashboard/trend`、排行 `/admin/dashboard/models` / `groups` / `users-ranking` 等使用同一范围、站点时区和筛选。计费卡显示实际扣费、账号成本、标准与利润；利润 = 实际扣费 − 账号成本（不含服务器等费用），可为负，逐段利润按最大余数分到分并与合计对齐；趋势里没有 `account_cost` 的旧站点按段读 `usage/stats` 的账号成本。金额全程 Decimal，只有图表坐标转 Double；缺失值显示“—”、读“无数据”，不补零或标准费用。运行类图表读 `ops/dashboard/*`，运维监控关闭时显示“运维监控未开启”。

## 分组

列表：`GET admin/groups` 按最大页长逐页读完（最多 20 页，ETag / 304 由 `ConditionalCache` 处理），与 `groups/usage-summary`（今日 / 昨日 / 累计实际扣费，按服务器时区 00:00 切分）、`accounts/status-summary` 的分组 shortage 各自读取，后两者失败只影响对应格子，有旧值时保留旧值。四桶（可用 / 受限 / 错误 / 暂停·停用）有 F04 的 `error_account_count` / `idle_account_count` 就直接用；没有时读一页 `status=error` 的账号按 `group_ids` 计错误，其余记暂停·停用。没有 `accounts.status_summary` 时按“可用 < 总数 × 0.5”本地判定可用偏低。列表分需处理 / 正常 / 停用三段，前台每 60 秒刷新。

详情：各区块并发、各自成败。分组本身读 `GET :id`，404 显示“这个分组已删除”。成员读 `accounts?group=<id>` 按 urgency 排序；成员今日读 `today-stats/batch`，有 `accounts.today_stats_group` 时带 `group_id`，响应回显了才算分组口径，否则脚注说明是账号全站今日。贰读 usage-summary 的三栏金额、`dashboard/groups` 的请求 · Tokens · 账号成本和 `groups/capacity-summary?group_id=`（没有 `groups.capacity_filter` 时拉全量后本地过滤）。叁是近 24 小时错误请求 / 上游错误计数（运维监控关闭时写“运维监控未开启”）、使用记录、API 密钥与订阅；Key 与订阅数读 `groups/:id/stats`，旧服务端没有 `subscriptions_total` 键时退回 Key 列表与订阅列表的 total。分组 Key 页带 `key_view=masked`，不解码明文，只读令牌下今日消费显示“—”。告警横幅读告警中列表。

写入：新建、修改、删除、复制走 `admin/groups` 的写接口。有 `admin.idempotent_writes` 时带 Idempotency-Key，编号在最后一次确认时生成，传输失败用同一编号自动重试 2 次；复制一律带 key。删除遇 404 视为已删除；结果不明（5xx、408、传输失败）先自动读服务器核对一次，定不了再给“用同一编号重试”，不自动重发。停用与删除确认读一次 stats 写出受影响的 Key 与订阅数，拿不到时写不带数字的后果；删除走输入完整名称或 Face ID 的删除确认。成员加减用 `POST groups/:id/accounts/batch`，每批 ≤ 200，网络失败同体重试 1 次；逐项结果页可重试、撤销成功的项、确认混合渠道风险。没有 `groups.member_batch`（或收到 500 GROUP_REPOSITORY_UNSUPPORTED）时逐个账号只写 `group_ids`。成员写入不过 Face ID。分组写与成员写成功或可能已生效后，概览下次可见时跳过服务端缓存刷新。

简易模式只有名称、描述、平台与计数：没有停用 / 启用、复制、用量汇总、容量、Key 与订阅行，新建只填名称、描述与平台（请求里的计费等字段由服务端覆盖为默认值），有成员的分组删除被拒（GROUP_NOT_EMPTY），后端不列组合分组、对组合分组的成员写入回 SIMPLE_MODE_GROUP_NOT_BINDABLE，也不走逐个账号的退路。只读管理访问令牌下写入口置灰、不提供滑动操作。模型白名单、组合路由、图片计费、客户端限制仍在 Web 编辑；首版不支持 vendor 登录（U01）。

## 概览 RPM

`/admin/dashboard/stats` 的 `rpm` 是服务端近 60 秒成功上游请求数；同时解码 `rpm_available`：true 的 0 才是真实零，false 显示“不可用”。未带该字段的旧站点保留数值并注明窗口由站点决定，不能宣称它是滚动 60 秒。TPM 仍为近 5 分钟平均，卡片分别标明两个口径。账号 `current_rpm` 已支持各平台/API Key/OAuth，读取同一滚动窗口；缺失值保持不可用。账号容量中的限流使用独立 `scheduling_rpm` 自然分钟计数，不把滚动计数与自然分钟限额作比。历史性能趋势仍按吞吐时间桶计算，统计范围与成功请求口径不同，不要求它与概览实时值相等。

## 验证边界

单元测试覆盖 API 路径和筛选、免计数分页、Decimal 精度、可用性、稀疏更新、null 限额、身份隔离、禁止写入重放与批量部分结果。XCUITest 使用显式 `-ui-testing` 内存数据，不操作生产。模拟器构建和未签名 IPA 不证明真实站点写入、验证码或签名后 iPhone 安装；这些需要在测试站点完成真机验收。
