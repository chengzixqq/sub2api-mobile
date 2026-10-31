# 管理模块与滚动 RPM（2026-10-16）

本次沿用 `codex/native-ios-rebuild` 的同一套原生源码；后端接口参考共享源码 `e5ab7e4f4c136a8faf40fd06694ab0a6bf6f6925`；原生 App 阶段 0 起按 sub2 `main` `70116315d` 之后核对。不更改后端、不部署服务器。以下描述功能与契约；构建和真机结果以 `ACCEPTANCE.md` 的最新记录及交付 manifest 为准。

## 入口与范围

请求与错误日志、统计分析、分组管理从搜索 Tab 的目录进入（阶段 0 起不再有底部“管理”）。概览右上角可以打开统计分析；账号和分组详情可跳转到对应范围的日志、分析及账号列表。

请求记录读取 `GET /admin/usage`，使用 `count_mode=deferred`、每页 100 条、时间倒序、按需分页，`timezone` 为站点时区。`total`/`pages` 可以为 null，按 `has_more` 判断是否继续；不要求大站点先执行全量计数。时间、用户、账号、分组、API Key、模型、请求 ID 等过滤由后端执行。实际扣费读取 `actual_cost`；账号成本优先读取服务端算好的 `account_cost`，旧服务端没有该键时按 `provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0` 计算，保留 Decimal 和缺失值。站点有 `api_keys.masked_view` 时请求带 `key_view=masked`；无论哪种服务端，App 都不解码 `api_key.key` 明文，只读名称与 `key_masked`。详情展示请求 ID、Token 分解、费用、时延及关联账号，不读取请求/响应正文。

日志默认显示最近 24 小时，下拉刷新同时推进开始和结束时间至当前窗口。应用时间与其他筛选后，页面明确切换为固定范围，下拉刷新保留原起止时间；“查看最新记录（近 24 小时）”可恢复滚动窗口，同时保留账号、用户、模型等对象筛选。

错误日志分为客户端失败请求 `/admin/ops/request-errors` 和上游错误 `/admin/ops/upstream-errors`，按需读取同路径 `/:id` 的详情。两种日志都能按时间、账号、分组、用户、API Key、模型（请求模型）与请求 ID 筛选（D03），只有早于 D03 的旧服务端的上游错误仍只认时间、账号、分组与状态，App 对它先套 `upstreamErrorFilter()`。错误日志一律带 `view=all`（包含用户自身余额、额度、频率限制），时间用固定起止或 `time_range`（5m / 30m / 1h / 6h / 24h / 7d / 30d）；各处的“近 24 小时 N 条”用同一组参数加 `page=1&page_size=1` 读 `total`。上游错误包含重试后恢复的请求（`status_code` < 400）；列表项没有上游状态码，App 从 `message` 的 `Recovered upstream error <码>` 解析，解析不到时按阶段显示“鉴权”或“恢复”。站点禁用 Ops 或权限不足时局部报告错误。正文、堆栈、完整 headers 不进入 DTO；可见摘要额外脱敏授权、Cookie、密钥、URL 中的凭据等字段。

## 账号

列表：账号 Tab 按平台分区显示三行列表，请求 `GET admin/accounts?lite=1&page_size=500&sort_by=urgency`，第 1 页带 `include_counts=1`，最多加载 2,000 行，ETag / 304 由 `ConditionalCache` 透明处理。胶囊与平台菜单走服务端 `status` / `platform` 参数；组头计数与 Tab 徽标读 `accounts/status-summary`，没有该能力时本地计数，徽标读 `dashboard/stats` 的 `error_accounts`。组头告警牌与监控 · 告警共用一份告警中列表。每行今日金额读 `today-stats/batch`。前台可见时每 60 秒用 `runtime/batch` 轻刷新；状态或调度开关变化、写操作成功后、每 5 分钟做完整刷新。旧站点按名称全量分页，本地推导状态与排序；`status` 参数被拒（400 `INVALID_ACCOUNT_STATUS_FILTER`）时本会话改走同一条旧站点路径。

详情：状态卡与按钮行，加容量 / 今日 / 记录与基础、调度、凭据、代理、模型、高级六个编辑分区。编辑一律 `PATCH` + `If-Match`，版本号是详情 `GET` 的 ETag `cv-N`，不进缓存。412 先比对字段，再静默重发或询问；混合渠道 409 用 Web 的文案确认。没有 `accounts.patch` 时以 `GET :id` 的最新整份为底合并、整份 `PUT`，敏感凭据键不回传，凭据未脱敏的更旧站点改凭据要去 Web。可撤销：调度开关、启用 / 停用、内联编辑；不可撤销：恢复状态、恢复原代理、更换 API Key、刷新令牌、重新授权。带 key 的写按 00 §2.5 同 key 重试，仍不明转待核对；其余写不自动重发，超时先读回核对。任何账号写成功或可能已生效后，概览下次可见时以 `nocache` 刷新。

测试与新建：测试连接读 SSE 的 `test_result`，关闭 sheet 不取消，结束后概览与列表刷新。新建账号以 `schedulable=false` 创建，测试通过再启用。批量只有停止 / 启用调度。删除、批量、更换 API Key 与重新授权受 Face ID 门控。

## 统计分析

今日、近 7 天、本月与一年以内自定义范围，支持账号、分组、用户和模型过滤；详情入口自动绑定对象。界面显示确切时间范围，开始包含、结束不包含；下拉刷新该固定范围，预设按钮更新截止时间到现在。

汇总 `/admin/usage/stats`、消费趋势 `/admin/dashboard/trend`、模型 `/admin/dashboard/models` 和分组 `/admin/dashboard/groups` 独立并发加载，使用同一范围、时区和筛选。显示请求数、K/M/B Token、实际扣费、上游成本、差额及平均时延。差额仅为扣费减成本，不能称为净利润。金额在解码、差额和显示舍入过程中使用 Decimal；只有图表坐标转 Double。缺失成本或实际消费显示不可用，不补零或标准费用。明细最新在上，图表支持横向查看。

## 分组

分页搜索、平台/状态筛选、详情、创建、稀疏编辑、启停和删除均调用 `/admin/groups` 的现有接口。可编辑名称、描述、倍率、专属、计费类型、RPM 及日/周/月限额；创建选择平台，编辑保留平台和未开放的路由/渠道配置。nil 表示不修改，取消限额显式发送 JSON null；删除/停用由服务器校验关联关系。结果不明先读取核对，不自动重发。

容量读取真实 `/admin/groups/capacity-summary`，不使用仍为占位实现的 `/:id/stats`。分组账号跳转到带过滤的账号页，通过账号快捷编辑管理归属；统计/日志使用真实聚合和记录接口。

## 概览 RPM

`/admin/dashboard/stats` 的 `rpm` 是服务端近 60 秒成功上游请求数；同时解码 `rpm_available`：true 的 0 才是真实零，false 显示“不可用”。未带该字段的旧站点保留数值并注明窗口由站点决定，不能宣称它是滚动 60 秒。TPM 仍为近 5 分钟平均，卡片分别标明两个口径。账号 `current_rpm` 已支持各平台/API Key/OAuth，读取同一滚动窗口；缺失值保持不可用。账号容量中的限流使用独立 `scheduling_rpm` 自然分钟计数，不把滚动计数与自然分钟限额作比。历史性能趋势仍按吞吐时间桶计算，统计范围与成功请求口径不同，不要求它与概览实时值相等。

## 验证边界

单元测试覆盖 API 路径和筛选、免计数分页、Decimal 精度、可用性、稀疏更新、null 限额、身份隔离、禁止写入重放与批量部分结果。XCUITest 使用显式 `-ui-testing` 内存数据，不操作生产。模拟器构建和未签名 IPA 不证明真实站点写入、验证码或签名后 iPhone 安装；这些需要在测试站点完成真机验收。
