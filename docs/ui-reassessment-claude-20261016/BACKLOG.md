# 待以后决定的事项

> 用户要求（2026-10-18）：把“之前、现在、将来还没做但可以做”的事写在这里，**等这次后端源码和 App 全部做完后，再逐条问用户做不做**。新发现的随时追加。

## 后端（sub2api）

| 编号 | 事项 | 为什么暂缓 | 需要什么才能做 |
|---|---|---|---|
| A10 | Passkey / 密码自动填充（apple-app-site-association） | 还没有站点域名和 Apple Team ID | 站点域名、Apple Team ID |
| B10 | 重统计查询提速（throughput-trend 读小时预聚合、跳过附带汇总、models / groups 预聚合表） | 没在生产量级库实测过是否超过手机端 10 秒 | 部署后打开 ENABLE_SERVER_TIMING 实测 throughput-trend 24h / 30d、usage/stats 30d、dashboard/models 30d |
| B01 第二阶段 | 关运维监控时也有首页错误率（网关在开关判断前写 Redis 每秒计数） | Q2 选了显示“—”；每个请求多一次 Redis 写 | 决定要不要为一个格子增加网关开销 |
| 迁移 019 被自己的回滚段撤销 | 迁移执行器把整个文件当一个脚本跑，goose 格式的回滚段紧接着执行：“微信”迁到用户属性又被撤回（属性定义被软删除、属性值被删除，数据仍在 users.wechat 列里，没有丢） | 要不要用新迁移重新把微信号迁到属性、再删旧列，需要维护者决定 |
| 迁移 024 被自己的回滚段撤销 | 同上：Gemini Code Assist 账号的默认 tier_id=LEGACY 加上又被删掉，净效果为零 | 确认代码是否依赖这个默认值，再决定要不要补一个新迁移 |
| 已有的集成测试失败 | TestOpsOutputTPSDistribution 在全新库上自己插入重复 request_id（违反 idx_usage_logs_request_id_api_key_unique）；改动前的代码同样失败 | 修测试数据 |
| 本机缺 Redis，缓存类集成测试跑不了 | 23 个缓存 / 调度集成测试需要 SUB2API_TEST_REDIS_URL 或 Docker | 要不要再装一个免安装版 Redis 跑全 |
| G02 第 D 项 | 按 Idempotency-Key 只查不执行的接口（idempotency-records/lookup，需迁移给幂等记录加 actor_scope） | 文档标为可选；A、B、C 已经能确定核对 |
| A04 方案 B | 会话绑定用 iPhone Secure Enclave 设备密钥签名刷新 | Q4 只做方案 A | 有更高安全需求时再做 |
| E05 可选项 | `GET /admin/users?ids=1,2,3` 批量取用户；用户列表每项加只读 low_balance / effective_threshold | 文档标为可选；头像条接口已带余额与阈值 | App 列表行需要服务端判定“余额低”时再做 |
| C02 存量错误账号 | 迁移 250 前已处于 error 的账号 error_at 为 null（updated_at 不可靠，未回填） | 只影响历史账号的“错误于”显示 | 可接受；或在这些账号下次出错时自然补上 |
| D02 / C04 / B01 对 vendor 开放 | 三个新接口目前不对 vendor 开放（分组名、告警规则、全站速率都没按工作区收窄） | 需要先按工作区收窄 | 决定 vendor 是否需要这些视图 |
| A05 解绑登录方式时保留当前设备 | 解绑第三方登录走“撤销全部会话”，A05 之后当前设备也立即掉线（以前要等 access token 过期，结果相同只是更晚） | 原意就是全部失效，先按原意 | 决定解绑时是否只踢其他设备（需要“撤销全部，除当前会话”） |
| A07 站长查看 / 踢掉某个用户的会话 | `GET /admin/users/:id/sessions`、`DELETE /admin/users/:id/sessions/:sid` | 文档标为可选 | 需要站长替用户下线某台设备时再做 |
| B08 负数 / 0 ID 筛选 | dashboard 筛选里 `user_id=-5`、`group_id=0` 能解析通过，仓库层按 >0 才生效，结果等于全站数据 | 文档没要求；Web 可能用 0 当“全部” | 确认 Web 和 App 都不用 0 作“全部”哨兵后，改成 400 |
| B08 dashboard 筛选 400 的稳定 reason 与 stream 校验统一 | 参数校验 400 仍是 `response.BadRequest` 纯文案，没有 reason；传了 request_type 时，user-breakdown 以外的 dashboard 接口（以及 `/admin/usage`）仍忽略非法 stream | 统一要把 8 个调用点改成 infraerrors，并推翻 TestDashboardTrendRequestTypePriority / TestDashboardModelStatsRequestTypePriority 锁定的行为 | 维护者决定是否需要 App 按 reason 分支、是否统一严格校验 stream |
| B04 可选项 | users-ranking 按 cost / account_cost / 利润排序；user-breakdown 响应补 username、total_users 与范围合计 | 设计稿只要求按实际扣费 / 请求 / Tokens 排；users-ranking 已带成本与用户总数，user-breakdown 替代方案已被取代 | App 需要按成本或利润排行时，在 userSpendingRankingOrder 白名单加一项即可 |
| B12 可选项 | snapshot-v2 增加 users_trend_metric（默认 tokens），users_trend 按所选指标取人 | App 与 Web 调 snapshot-v2 时都固定传 include_users_trend=false，没有使用方 | 有客户端要在 snapshot-v2 里取按实际扣费排名的用户趋势时再做：解析参数、加进 dashboardSnapshotV2CacheKey、改调 GetUserUsageTrendWithFiltersByMetric |
| B03 补漏：dashboard/groups 的 model_source 不生效（高优先级） | getGroupStatsWithFilters 写死 ModelSourceRequested（`repository/usage_log_repo_trend.go:616`），dashboard/groups 与 snapshot-v2 的 groups 带 model_source=upstream / mapping 时仍按请求模型匹配；B03 只测了 handler 透传，没发现 | 不属于 B05 范围，单独修，免得混进 B05 的提交 | 把 filters.ModelFilterSource（空时按 requested）传进 getGroupStatsWithFilters，补 sqlmock 与集成测试 |
| B05 对 vendor 开放 | dashboard/request-types 目前只给站长；SQL 已施加账号白名单，但 cost / actual_cost / account_cost 没按监控档裁剪 | App 面向站长，vendor 没有使用方 | 决定 vendor 是否需要后：登记 vendorAllowedRoutes 与 vendorUsageScopedRoutes，并在 service 层按监控档裁剪金额 |
| B06 可选项 | 带 model 时 throughput-trend 的 by_platform / top_groups 也按模型过滤（目前直接不返回）；dashboard/rates 与 ops realtime-traffic 加 model 筛选 | 文档允许“过滤或跳过”，选了改动最小的跳过；rates / realtime-traffic 不在 B06 的 7 个接口内 | App 需要看某模型的平台 / 分组分布或某模型的实时速率时：给 getThroughputBreakdownByPlatform / getThroughputTopGroupsByPlatform 加模型条件（复用 buildUsageWhere / buildErrorWhere 的模型表达式），并为 ops_error_logs 评估按模型的表达式索引 |
| B07 可选 | openai-token-stats 自定义范围按请求 timezone 回显 start_time / end_time（或响应加 timezone 字段），以及支持 start_date / end_date 日粒度参数 | 文档只要求 start_time / end_time；现在回显 UTC 时刻，App 按 RFC3339 解析即可；不支持日粒度参数可保证旧请求零变化 | App 确实需要按本地时区原样回显或日粒度参数时再做 |
| B09 可选：其他日志列表的 since_id | ops/errors、ops/upstream-errors、ops/requests、用户端 /api/v1/usage 与 /usage/errors 也支持 since_id | 文档只要求 admin/usage 与 request-errors | App 这些页面也要增量轮询时再做，复用 parseSinceIDQuery 与 OpsErrorLogFilter.SinceID |
| B09 可选：since_id 服务端安全水位 | 防止并发 / 批量写入提交乱序导致增量漏行（例如只返回早于 pg_snapshot_xmin 的 id，或只返回 N 秒前已可见的行） | 实现复杂、会让最新行延迟出现；目前靠 App 定期 page=1 校准或回退游标去重 | 实测漏行影响 App 体验时再定方案 |
| B09 可选：真正省数据库的 304 | 用版本计数器或 updated_at 水位在查询前判断是否变化 | 现在的 ETag 在完整查询后按响应内容计算，只省带宽 | 需要降服务端负载时再做，需要给用户 / 分组 / 统计维护变更水位 |
| B09 可选：更多 ETag 与 5 秒节流 | ETag 扩展到 proxies、api-keys、兑换码、settings 等稳定 GET；5 秒取整节流扩展到 latency-histogram、error-trend、error-distribution、openai-token-stats、ops/dashboard/snapshot-v2 | 文档只点名 stats / users / groups 与 overview / throughput / rates | App 对这些接口轮询频繁时再做，复用 conditional_get.go 与 parseOpsDashboardFilterBucketed |
| D06 可选：告警计数的部分索引与静默计数 | counts 按 status='firing' 扫 ops_alert_events（现有索引以 rule_id 开头用不上）；counts 也没有单独返回被静默的 firing 数 | 这张表由清理任务定期修剪、量小；App 可从列表的 silence 字段自己数 | 生产上 ops_alert_events 很大、counts 变慢时加 WHERE status='firing' 的部分索引；App 需要“静默中 N 条”时再加 silenced 字段 |
| D06 可选：PUT 告警状态对不存在的事件返回 404 | PUT /admin/ops/alert-events/:id/status 对不存在的 id 仍返回 {"updated":true}（UPDATE 影响 0 行，既有行为） | 改状态码属于改行为，不在 D06 范围 | 决定是否把 0 行视为 404，并核对 Web 是否依赖现有行为 |
| D07 可选：调整预置延迟规则的数据 | 用迁移把两条预置延迟规则的阈值调到适合 LLM 网关的值（例如 P95 60000ms / P99 120000ms），或默认停用 | Q10 只要求补评估，不改预置规则数据；规则现在可以在 Web 编辑 | 维护者决定统一默认值后加一个幂等 UPDATE 迁移（只改仍是 033 原值的规则） |
| D07 可选：延迟分位的最小样本数 | 窗口内成功请求少于 N 条时不评估 P95 / P99，避免一两个慢请求就构成 breach | 文档没有要求，sustained 与无样本跳过已能缓解 | 实测低流量站点误报明显时再定 N，并考虑做成规则或站点设置 |
| D07 可选：评估周期内复用 overview 查询 | 同一周期内相同 (窗口, 平台, 分组) 的规则共用一次 raw overview 查询，现在每条走 overview 的规则各查一次 | 预置规则只有 5 条走 overview，开销小 | 规则多、评估超时或数据库压力大时再做 |
| D07 可选：指标白名单与评估器单一来源 | 把告警指标白名单收口到 service 层，或加守卫测试保证每个白名单指标在 computeRuleMetric 里都有分支 | 白名单和评估器分叉正是本 bug 的根因，但改动面超出 D07 | 下次增删告警指标时一起做 |
| D07 可选：前端 MetricType 补代理指标 | frontend MetricType 缺 proxy_expired_count / proxy_expiring_soon_count，Web 规则编辑器也没有这两个选项 | 与 D07 无关，不顺手改 | Web 需要编辑代理到期规则时再做 |
| D08 可选：健康分按任务周期判断心跳 | `ops_health_score.go` 仍把“超过 15 分钟没成功”算作任务失败，每小时一次的天预聚合和每日清理在多数时间会拉低 health_score，与新的 status=ok 不一致 | 改了会让 Web 已在显示的健康分数值变化，不符合只增不改 | 维护者确认后，把这条规则改成按 status ∈ {failing, stale} 计数 |
| D08 可选：Web 运维页展示心跳状态与入口拒绝合计 | `frontend/src/api/admin/ops.ts` 的 OpsJobHeartbeat 与入口拒绝列表类型没补新字段，Web 不显示 stale / disabled、预期间隔和 request_count_total | 本条只为 App 补数据，Web 行为不变 | 需要 Web 同步展示时再改类型与运维页组件 |
| D08 可选：系统指标按实例区分 | 多实例部署时每个实例的采集器每分钟各写一行（leader 锁只防同时采集），history 把同桶内不同实例的 CPU / 内存取平均，overview.system_metrics 是最后写入的那个实例 | ops_system_metrics 没有实例维度 | 需要按实例看时给 ops_system_metrics 加 instance_id 列，history 增加按实例分组或筛选 |
| D09 可选：admin/settings 的 ops_monitoring_enabled 口径统一 | `GET /admin/settings` 返回“配置开关 && 设置值”，`PUT /admin/settings` 的响应却是原始设置值；Web 卡片靠“只在改动时提交”绕开，没有改既有字段语义 | 只增不改原则下不改旧字段 | 维护者决定是否让 GET 返回原始值（或新增 ops_monitoring_setting_enabled），确认 Web 与 App 都改读 monitoring-status 后再统一 |
| D09 可选：Web 设置页改用 monitoring-status 写开关（部分已修） | 保存已改为只提交改过的 ops 字段（`d4b8baa24`），未改动的保存不再覆盖 App 刚改的值；但 Web 仍随整页保存经 `PUT /admin/settings` 写开关，不走 monitoring-status 的 409 OPS_CONFIG_DISABLED（配置关闭时靠置灰），两端改同一项时后写者赢 | 影响很小，且需要拆分设置页保存流程 | 设置页把启用 / 实时两个开关改为即时调用 `PUT /admin/ops/monitoring-status` |
| D10 可选：成功那次的精确开始时间与上游状态码 | 合并接口里计费那次的 started_at 用 usage.created_at − duration_ms 估算（created_at 是记账时刻，可能晚几毫秒），upstream_status_code 固定为 200，duration_ms 是 Forward 级耗时；同账号重试后成功时 started_at 已夹到前一次失败的结束时刻（`57f14631b`，不再重叠），但耗时仍含重试退避等待 | 要给 usage_logs 加列（如 attempt_started_at、upstream_status_code），涉及迁移和热路径写入 | 维护者决定是否为精确值加列 |
| D10 可选：WebSocket 等路径的分发打点 | OpenAI WS、各类直连 SDK 不经过 repository/http_upstream，它们的上游尝试没有 started_at / duration_ms | 每条路径要单独找分发点 | 需要这些路径的耗时时，在对应分发处调用 `service.MarkOpsUpstreamAttemptStart` |
| D10 可选：没有上游事件的旧行合成“兜底尝试” | 极少数旧的 ops_error_logs 行没有 upstream_errors，只有顶层 upstream_status_code / duration_ms，合并接口里 attempts 为空，只在 error_log_ids 里列出 | 只影响旧数据 | 需要时按顶层字段合成一项 source=error_log 的尝试 |
| D10 可选：关监控时退化为只返回使用记录 | 文档要求关监控时返回 404 OPS_DISABLED，即使使用记录其实有数据 | 按文档执行 | 维护者决定关监控时是否返回只含计费那次的链 |
| D10 可选：Web 错误详情显示每次尝试耗时 | `frontend/src/api/admin/ops.ts` 的 OpsUpstreamErrorEvent 类型没补 started_at_unix_ms / duration_ms，Web 上游错误弹窗不显示 | 条目没要求改 Web | Web 需要时补类型与展示 |
| D10 既有问题：ops/requests 按 request_id 筛选跨不了表 | `/admin/ops/requests` 用运维 request_id 筛选时，使用记录那一侧按 usage_logs.request_id（client: 前缀格式）匹配，查不到成功行 | 既有问题，不属于本条 | 维护者决定是否让该筛选同时匹配 `client:<client_request_id>` |
| B11 可选：dashboard/stats 本身返回 yesterday_same_time_* | 附录 A S10 的可选 P2：昨天同一时刻的请求、实际扣费、账号成本现在只在 dashboard/home 的 stats 段返回 | 文档标为可选，Web 首页不用 | Web 或其他客户端需要时在 dashboard/stats 加字段（不要放进每次覆写 RPM 的路径） |
| B11 可选：首页聚合冷缓存实测 | 冷缓存一次请求并发约 10 条查询（账号表、usage 零头、ops 概览 / 系统指标 / 心跳 / 告警计数与列表、渠道监控快照），15 秒缓存按管理员身份区分，验收的“冷缓存 p95 < 3s”没有在生产量级上测过 | 本地没有生产量级数据 | 部署后用 `curl -w %{time_total}` 实测；超标时再考虑按站点共享缓存、拉长段超时或改用预聚合 |
| B11 可选：availability / channels 段返回更多明细 | availability 不含 paused / inactive 账号，异常账号超过 100 个只给 accounts_truncated；channels 只给四档计数，不含逐渠道可用率与首字 | 首页只需要待处理与一行渠道摘要 | App 需要时改调 accounts/status-summary?include_accounts=true 与 channel-monitor-v2/overview，或给 home 加字段 |
| D07 延迟查询持续超时时延迟规则不被评估（审查 LOW，部分已修） | 零星超时已不再清零连续越线计数（`2e3b95ebd`），心跳摘要会显示 `latency_timeouts=N`；但高流量站点的大窗口（如 60 分钟）延迟规则若每轮都超过 2 秒上限，规则一直不被评估、计数冻结，Web 规则界面没有提示 | 只影响 P95 / P99 两种延迟规则，且要窗口内数据量很大；评估器每条规则各查一次 overview，放宽超时会增加数据库压力 | 给评估器单独、更长的延迟查询超时（例如经过滤器传入），或限制延迟规则的窗口，或在规则列表显示“最近未评估” |
| D08 运维设置保存时不校验 cron（审查 LOW，部分已修） | 心跳已改为“设置里开启但 cron 非法 → failing”（`d8b4d2d7a`）；但清理 cron 与四种定时报告的 cron 仍是自由文本、保存时不校验，写错后任务不再运行；只有部分报告的 cron 写错时调度器照常运行、心跳为 ok，写错的那份报告不会发送也没有提示 | 保存时拒绝非法 cron 会让 Web 原本能保存的设置返回 400，属于行为变化 | 维护者确认后，在 validateOpsAdvancedSettings 与邮件通知配置更新中用 5 段 cron 解析器校验，返回 400 与稳定 reason，Web 同步显示错误 |
| D10 重试链边界情况（审查 LOW，大部分已修） | 已修（`57f14631b`）：非法 request_id 返回 400、`probe:` 计费 ID 纳入候选、同账号重试成功项不再重叠、409 歧义改为最新在前并带时间。剩余：1）客户端自带 X-Request-ID 的探测合并 leader，计费 request_id 是服务端随机的 `probe:<随机>`（`requestIDForProbe` 故意不信任客户端头），合并接口查不到它的成功项；2）含 `/` 的 X-Request-ID 无法作为路径参数，gin 返回纯文本 404，目前只在 API_ERROR_CODES 里提示改用 client_request_id 查 | 都是少见边界情况；1）要多存一个关联键，2）要新增路由形式 | 1）需要时把 probe 计费 ID 写进运维行（或使用记录存运维 request_id）；2）需要时新增 query 参数形式的同功能接口 |
| C07 可选：其余测试路径的 Token 用量 | Antigravity 非流式、OpenAI / Grok 图片、Grok 视频 / TTS / STT / Realtime / web_search、Bedrock 专有流的 test_result 不带 usage；Chat Completions 测试请求未加 stream_options.include_usage（会改变发往上游的请求，部分兼容上游可能不认） | App 确认需要这些路径的 Token 数，并逐个上游确认 include_usage 兼容性 |
| C08 可选：vendor 使用异步测试 | /accounts/:id/test-runs 与 /account-test-runs/:run_id 暂不对 vendor 开放；vendor 占用每实例有上限的 worker 会挤占站长的测试 | 维护者确定 vendor 的 worker 配额策略；开放时去掉 vendorDeniedRoutes 里那一条，并在白名单登记 account-test-runs/:run_id（permitAccountRead），service 层已按账号归属校验 |
| C08 可选：异步测试支持媒体参数 | async 不接受 image_data_url / audio_data_url（Grok 生成类测试），这类测试仍走 SSE | 确认载荷大小上限与超时（媒体测试可能超过 120 秒）后再加 |
| C08 可选：定时测试也写 account_test_runs（source=scheduled） | 定时测试频繁，会把每账号最近 20 条里的手动结果挤掉，违背“保留最近一次手动测试”；scheduled 只保留为枚举值 | 若 App 需要统一时间线，可改为分来源各自保留 N 条后再写入 |
| C08 可选：优雅停机主动标 interrupted | 进程退出时正在跑的异步测试要等 180 秒过期才变 interrupted（启动清扫或下次读取时） | 要改 provideCleanup 与 wire_gen_test 的参数表；若 App 反馈等待过长再做 |
| C08 可选：批量异步测试与完成推送 | 文档写的是“以后的批量测试”“后端不推送”，本次只做单账号、App 轮询 latest | 批量需自带排队（现在每实例 10 个 worker，占满返回 429）；完成推送依赖 A11，created_by 已落库可用 |
| C05 可选：Web“恢复状态”加“恢复并启用调度”选项 | 条目只要求接口加参数，按只增原则 Web 的 recoverState 仍不带请求体、行为不变 | 维护者决定 Web 是否要这个选项，再在 `frontend/src/api/admin/accounts.ts` 的 recoverState 传 `{schedulable}` 并在确认框加选项 |
| C18 可选：Web 批量清错误加“保留停用账号”选项 | 条目只要求接口加参数，按只增原则 Web 的 clearError / batchClearError 仍不传 preserve_inactive，BatchOperationResult 类型也未加 skipped_inactive_ids | 维护者决定 Web 是否要这个选项，再在 `frontend/src/api/admin/accounts.ts` 传 `preserve_inactive` 并在结果提示里显示跳过的账号数 |
| C18 发现：清错误不清 Redis 临时不可调度缓存与 OpenAI 403 计数 | ClearAccountError（单个 / 批量 clear-error）只清数据库字段，不像 RateLimitService.ClearRateLimit 那样删 tempUnschedCache、重置 OpenAI 403 计数；这是既有行为，本条未扩大范围 | 确认是否需要与 recover-state 对齐；对齐时给 adminServiceImpl 注入这两个缓存或改为复用 RateLimitService.ClearRateLimit |
| C12 可选：Claude 上游 5xx / 429 / 网络错误返回 502 | Claude 换码上游故障仍是 500 "internal error"（无 reason），只有拒码改成了 400 CLAUDE_OAUTH_CODE_REJECTED | 条目没有要求，保持原样 | 做 C11 时可顺带给 Claude 换码故障一个 502 稳定 reason（与 OpenAI / Grok 的 `*_TOKEN_EXCHANGE_FAILED` 对齐） |
| C12 可选：拒码时给出上游 OAuth 错误码 | `*_OAUTH_CODE_REJECTED` 的 metadata 只有 upstream_status，没有 upstream_error（如 invalid_grant / invalid_client） | 文档只要求 upstream_status | App 需要区分“授权码已用过”与“客户端配置错误”时再加 |
| C12 可选：Web 为新 reason 加文案 | Web 的 Claude 换码失败只显示固定的 'Failed to exchange auth code'（读的是不存在的 detail 字段），Gemini / Antigravity / OpenAI / Grok 回退显示 message；没有为 `*_OAUTH_SESSION_NOT_FOUND` / `_INVALID_STATE` / `_CODE_REJECTED` 加 i18n | 按“Web 不动”原则暂缓 | 维护者决定 Web 是否按 reason 显示“授权链接已过期，请重新生成”等文案 |
| C12 可选：OpenAI / Antigravity 拒码 message 里的上游 body 脱敏 | OpenAI、Antigravity 换码失败的 message 原样带上游响应体（Grok 用 logredact，Gemini 用 SanitizeBodyForLogs，Claude 不回显） | 既有行为，不在本条范围 | 统一用 logredact 处理后再拼进 message |
| C12 待验证：Claude #state 校验 | 新增的本地 state 校验依赖控制台回调页把我们生成的 state 原样拼在 `code#` 之后；没有真实 Claude 账号走过 | 测试环境没有 Claude 账号 | 部署后在 Web 上走一遍 Claude OAuth 与 Setup Token；如有误报 CLAUDE_OAUTH_INVALID_STATE 再放宽 |
| C10 可选：Web 构造 OAuth 凭据时带 expires_in | Web 新建 / 重新授权 OpenAI、Gemini、Antigravity、Grok 账号时由前端 useXxxOAuth 的 buildCredentials 拼凭据，不带 expires_in，这类账号的 token_status.lifetime_seconds 要等首次后台刷新后才有 | 文档只要求后端写；原生 App 自己构造凭据、C11 由服务端构造后会自带 | 维护者希望 Web 新建后立即显示寿命时，在四个 composable 的 buildCredentials 里补 expires_in |
| C10 可选：CRS 同步写 _token_refreshed_at | crs_sync_service 创建后立刻刷新令牌（refreshOAuthToken）并直接持久化，不经 updateLoadedAccount，CRS 账号的 refreshed_at 要到首次后台刷新后才有 | 不在文档列出的写点；CRS 路径分支多、缺少可用的刷新桩 | 需要时在 refreshOAuthToken 返回前调用 stampTokenRefreshedAt 并补测试 |
| C10 可选：batch-refresh 逐个账号返回 token_status | 批量刷新的响应只有成功 / 失败计数，App 批量刷新后需重新拉列表（列表项已带 token_status） | 文档只要求账号 DTO | App 反馈批量刷新后需要即时展示时再在响应里逐个带上 |
| C10 可选：expires_in 缺失时推算 lifetime_seconds | 存量非 Claude 账号在下次刷新前 lifetime_seconds 为 null；可用 expires_at − refreshed_at 估算 | 文档明确“有 expires_in 就用，否则 null”，推算值会受安全窗口与时钟影响 | 维护者认可估算口径后再加，且要标注为估计值 |
| C10 可选：Codex 导入用 access_token 的 iat 作为 refreshed_at | Codex auth.json 不带 `_token_version` / `_token_refreshed_at`，新建时 refreshed_at 记为导入时刻，而令牌可能几天前就已签发；JWT 的 iat 才是真实签发时间 | 按 C10 既有口径“新建即写入、令牌被替换即写入”，update_existing 走 updateLoadedAccount 也会记当前时间，只改新建会让两条路径不一致 | 维护者认可“以令牌签发时间为准”后，在 normalizeCodexImportEntry 用 access_token 的 iat 写 `_token_refreshed_at`，并让 updateLoadedAccount 尊重入参里合法的值 |
| C11 高优先级（既有越权）：Claude 授权路由对 vendor 不按工作区校验代理 | `/admin/accounts/generate-auth-url`、`generate-setup-token-url`、`exchange-code`、`exchange-setup-token-code`、`cookie-auth` 走 /admin/accounts 写前缀对有 AccountManage 的 vendor 开放，但请求里的 proxy_id 不经作用域校验（服务层 proxyRepo.GetByID 不过滤工作区），vendor 可借别家代理出网；reauthorize 在账号自己有代理时会覆盖，账号没有代理时仍沿用生成链接时会话里的代理 | 既有问题，不属于 C11 范围；与 C09 发现的越权一起排期 | 参照 constrainGrokReauthProxy：vendor 调这些路由必须带本工作区 account_id，代理取账号自己的；或干脆只给站长，vendor 改走 reauthorize；**已修复**：FIX-C11P `cf575e53f` 改为按工作区校验 vendor 传入的 proxy_id（未要求 account_id，以免 vendor 新建 Claude 账号失效），见实现进度 |
| C11 可选：reauthorize 暂存跨实例共享 | 换码成功、落库失败后的凭据暂存与 Claude / OpenAI / Gemini / Antigravity 的 OAuth 会话一样只在进程内存，多实例时重试要打到同一实例，重启即丢 | 与现有 OAuth 会话的限制一致，单实例部署够用 | 多实例部署、OAuth 会话也改成 Redis 共享时一起做（令牌落 Redis 需加密） |
| C11 可选：Claude Cookie（sessionKey）一步重新授权 | reauthorize 只接授权码；Web 的 cookie-auth 仍是两步（换码 → apply） | 文档没有要求 | App 需要用 sessionKey 重新授权时 |
| C11 可选：Codex PAT 账号用 OAuth 授权码重新授权 | 现在返回 REAUTH_UNSUPPORTED（detail=codex_personal_access_token） | 合并后会残留 PAT 的 auth_mode 等键，账号状态会坏 | 定义 PAT → OAuth 的转换语义（清掉哪些键）后再放开 |
| C11 可选：Web 重新授权改用 reauthorize / 加“保持停用”选项 | Web 的 ReAuthAccountModal 仍走 exchange-code → apply（Gemini / Antigravity 还是 PUT + clear-error），不传 preserve_status | 兼容原则：Web 行为不变 | 维护者决定改 Web 时 |
| FIX-C11P 发现（高优先级，既有越权）：账号新建 / 修改的 proxy_id 不按工作区校验 | `POST /admin/accounts`、`PUT` / `PATCH /admin/accounts/:id` 对有账号管理档的 vendor 开放，但 CreateAccount（buildAccountForCreate 直接取 input.ProxyID）与 UpdateAccount（`account.ProxyID = input.ProxyID`）都不经 GetByIDScoped / requireProxyAccess，vendor 可把自家账号绑到别家工作区或站长的代理，网关出站时就借用了该代理（批量编辑、导入已对 vendor 关闭） | 不属于 OAuth 接口这一条的范围，改的是账号写路径的 service 层，需要单独排期与回归 | 在 CreateAccount / UpdateAccount（含 PATCH 走的路径）写入非 0 的 proxy_id 前对 vendor 调 requireProxyAccess，越权按 404 PROXY_NOT_FOUND；先确认站长给 vendor 账号绑平台代理的存量数据怎么处理（vendor 保存不改代理的编辑时不能被误拒，只校验本次传入且与原值不同的 proxy_id） |
| FIX-C11P 可选：OpenAI / Gemini / Antigravity 授权接口的代理收窄 | 这些平台的 generate-auth-url / exchange-code 等同样按 proxy_id 不过滤工作区取代理，但现在不在 vendor 白名单里（路由守卫测试 TestVendorOAuthProxyHelpersReachability 固定），vendor 到不了 | vendor 当前无法调用，加了也用不到 | 决定让 vendor 新建或重新授权这些平台的账号时，handler 复用 constrainVendorOAuthProxy 再放开路由 |
| C16 可选：Web 账号列表对失败项显示“—” | `frontend/src/api/admin/accounts.ts` 的 BatchTodayStatsResponse 加可选 failed_account_ids / degraded，AccountsView 对失败账号显示“—”而不是 0 | 条目要求 Web 显示不变，本次只改接口 | 维护者确认 Web 也要区分“没有请求”与“查询失败”后改前端（类型 + 单元格），跑 vue-tsc 与相关 vitest |
| C16 可选：按账号返回失败原因 | 像 usage/batch 那样给 errors map（账号 ID → 原因） | 文档只要求 ID 清单；原始错误可能带内部 SQL 信息，不宜对外 | 有排障需求时定义脱敏后的稳定原因码（如 timeout / db_error）再加 |
| C16 可选：客户端取消时不报 503 / 不打 WARN | ctx 取消时逐个查询全部失败，返回 503 并打 WARN，ErrorFrom 再打一行 ERROR；响应其实已无人接收 | 不影响返回语义，只是日志噪音 | 观察生产日志里这类条目多不多，再决定在 ctx.Err()!=nil 时降级日志 |
| C16 审查 LOW：数据库降级时今日统计不再削峰 | 有失败项时完全不写 30 秒快照缓存（C16 字面要求），批量 SQL 超时且部分单查失败期间，每次请求都重跑 1 次批量 SQL 加 N 次逐个查询（并发 8）；多个管理员开 Web 账号页 5 秒自动刷新时，查询量约为旧逻辑（缓存补 0 的结果 30 秒）的十几倍 | 需求标题与验收明确要求“有失败项时不写缓存、30 秒内不命中缓存里的 0”；只在库已降级且有单查失败时出现，回退并发有上限 | 维护者确认可以放宽后二选一：带失败项的结果只缓存几秒且不发 ETag（命中时 failed_account_ids 照样返回）；或批量 SQL 失败后短时间内跳过批量直接回退 |
| C17 发现：vendor 视角分组“今天”与账号今日的起点可能不同 | vendor 调 `GET /admin/groups/usage-summary` 时按请求的 `timezone` 参数算“今天”（`group_handler.go` GetUsageSummary），today-stats/batch（含 group_id）固定用服务器时区；vendor 不传或传的不是服务器时区时，成员行之和与分组今日对不上。站长路径两者同一起点，已有测试锁定 | 统一起点属于改行为，vendor Web 可能依赖请求时区 | 维护者确认 vendor Web 是否依赖请求时区；或给 today-stats/batch 也加可选 timezone |
| C17 可选：站长传不存在的 group_id 返回 404 GROUP_NOT_FOUND | 现在统计全为 0、不报错（省一次查库）；vendor 侧已由分组授权校验返回 404 | 文档没有要求，App 的分组 ID 来自分组列表 | App 需要区分“分组已删除”和“今天没有用量”时 |
| C17 可选：Web 账号接口类型加 group_id | `frontend/src/api/admin/accounts.ts` 的 today-stats/batch 请求不传 group_id | 兼容原则：Web 行为不变，Web 分组页暂不需要按分组的成员今日 | Web 分组详情要显示“本分组今日”时 |
| C17 审查 LOW：不带 group_id 的今日统计缓存键没有日期 | `accounts_today_stats:<ids>`（Web 与 App 不分组路径共用）跨服务器时区零点后，30 秒快照缓存最多 30 秒内仍返回昨天整天的今日统计；分组路径已在 `bb7310d69` 带上日期 | C17 之前的既有行为，C17 要求不带 group_id 时缓存键逐字不变；改键会让所有 Web 实例升级后全部未命中一次，且与 E09 一样属于改行为 | 维护者确认零点附近 30 秒的旧数不可接受时，参照 E09 在不分组键里拼 timezone.Today() 日期，补跨零点测试 |
| C15 可选：runtime/batch 5 秒快照缓存 | 同一组 ID 5 秒内重复轮询时复用上次采样 | 轮询只读 Redis，开销本来就低；包级缓存要按工作区与 include_window_cost 分键，有失败项时还不能写缓存，测试也会互相串扰 | 多设备并发轮询的实测压力（Redis QPS、窗口费用 SQL 次数）证明需要时再加 |
| C15 可选：只读 sat_ 令牌调用 POST accounts/usage/batch | 只读令牌放行表目前只有 runtime/batch 与 today-stats/batch | usage/batch 带 force=true 时会探测上游并落库快照，不算纯读 | 维护者确认只读令牌可以触发上游探测，或把 force 拆成单独的写接口后，在 `adminAccessTokenReadOnlyAllowedWrites` 追加 |
| C14 可选：sort_by=today_cost | 账号列表按今日金额排序（文档写“以后可再加”） | 要在列表 SQL 里关联 C04 的按账号今日聚合，每次翻页都多一次大范围聚合，代价高；App 目前可用 today-stats/batch 在当前页内排序 | App 确实需要跨页按金额排序时，先给按账号今日成本做可索引的物化或缓存，再加排序分支 |
| C14 可选：Web 状态筛选增加新派生值 | Web 账号筛选下拉不提供 overloaded / needs_attention / schedulable_now，也不用 include_counts | 兼容原则：Web 行为不变，本条只为 App 加参数 | 维护者希望 Web 的“正常”筛选排除过载账号（Q18 选 (a) 未改 active）或想加“需处理”筛选时，改 AccountTableFilters.vue 与 accounts.ts 类型，跑 vue-tsc 与 vitest |
| C14 发现：counts.inactive 不含 disabled 等其他停用状态 | counts.inactive 与 status=inactive 一致，只统计 status='inactive'；D02 的 inactive 还包括 disabled 等非 active、非 error 账号，这类账号只计入 all，urgency 排在 inactive 档 | 计数契约是“counts[k] 等于 status=k 的 total”，改 inactive 筛选口径会改变 Web 现有筛选结果 | 维护者确认存量里有 disabled 账号且 App 需要“停用”总数时，新增派生值（如 not_active）及对应计数键 |
| C14 发现：旧派生值用应用时钟、新派生值与计数用数据库时钟 | active / rate_limited / unschedulable 的列表谓词沿用 Go 的 time.Now()（原样保留），计数与新派生值只用 NOW()；应用与数据库时钟有偏差、且账号窗口恰好落在偏差区间时，counts[k] 与 status=k 的 total 可能差 1 | 保留旧谓词逐字不变是只增不改的要求；两次查询之间数据本来也可能变化 | 观察到偏差投诉时，把旧谓词里的 time.Now() 统一改成 NOW()（行为几乎不变，但属于改旧口径，需维护者确认） |
| C13 第二期：credential_fields | meta/catalog 下发每个“平台/认证方式”的凭据字段（key、required、sensitive），App 据此生成表单、校验必填 | 必填规则与 extra 键名只写在 Web 的 credentialsBuilder.ts，后端没有现成常量；逐平台、逐认证方式迁移工作量大 | 维护者确认以后端作为表单规则的唯一来源，再把规则迁成后端常量并加与 credentialsBuilder.ts 的同步测试 |
| C13 可选：Web 运行时拉取目录 | Web 改为调用 meta/catalog，而不是用内置 platformCatalog.builtin.json | Web 随后端一起发布，内置 JSON 已由测试保证与后端一致，运行时拉取没有收益 | Web 与后端分开发布时再做 |
| C13 可选：vendor 收紧到账号管理档 | meta/catalog 现在对所有 vendor 开放（permit 为 nil），文档建议只给账号管理档 | 内容全是编译期常量、已随公开 Web 产物分发，监控档 vendor 也要用平台展示名与枚举 | 维护者坚持最小权限时，把 vendor_routes.go 那条规则的 permit 改成 permitAccountManage |
| C19 可选：账号详情错误本地化 | 深链与列表“编辑”在账号不存在 / 无权限时 toast 显示后端英文 message（如 account not found） | 要给 loadAccountDetails 加 reason → 文案映射，会改变所有调用它的现有 Web 提示，超出本条范围 | 维护者希望 Web 中文界面显示本地化错误时，按 ACCOUNT_NOT_FOUND 等 reason 加 i18n 映射，跑相关 vitest |
| C19 可选：同页 query 变化时响应深链 | 现在只在 AccountsView 挂载时处理一次 edit / search，SPA 内跳到同一页只改 query 不会再弹窗 | Web 内部没有这类跳转；App 打开链接都是整页加载、会重新挂载 | Web 内出现跳到 `/admin/accounts?edit=` 的入口时，加 watch(route.query) 并复用 consumeAccountDeepLink |
| C19 可选：搜索同步到 URL | search 只作一次性预填，随 edit 一起从地址栏去掉，刷新后不保留 | 账号页原本不把任何筛选同步到 URL，改成双向同步会改变 Web 现有行为 | 维护者希望账号页筛选可分享 / 刷新保留时，统一把筛选双向同步到 query |
| C19 发现：ChannelMonitorView 既有前端测试失败 | ChannelMonitorView.checkModeBadge / duplicate / unified 三个 spec 共 9 个用例在 main 上失败：视图 setup 调用 useAuthStore，而 spec 没有 mock @/stores/auth 也没装 Pinia（getActivePinia 报错） | 与 C19 无关（失败点在 ChannelMonitorView.vue:213，b807125c9 引入），不属于本条范围 | 在这三个 spec 里 vi.mock('@/stores/auth') 或 setActivePinia(createPinia())，再跑 npx vitest run src/views/admin/__tests__/ChannelMonitorView |
| C06 可选：Web 新建弹窗非 409 报错文案 | `CreateAccountModal.vue` 的 `submitCreateAccount` 与预检失败分支读 `error.response?.data?.message`，拦截器 reject 的对象没有 response 字段，所以总是显示通用的“创建失败” | 会改变 Web 的报错文案，超出 C06 只修 409 兜底的范围 | 维护者同意后改读 `error.message`，补 vitest |
| C06 可选：Web 用 metadata 拼本地化的混合渠道确认文案 | 新建 / 编辑弹窗的 409 兜底目前显示后端英文原文 message | Web 行为不变优先；预检路径已有本地化文案 | 决定是否让 409 兜底也走 `admin.accounts.mixedChannelWarning` 本地化模板 |
| C06 可选：批量建号 POST /admin/accounts/batch 逐项结果带 reason / details | 批量建号遇到混合渠道时逐项结果只有 error 字符串 | 文档没有要求，App 不走批量建号 | 有客户端需要时给逐项结果加 `reason=MIXED_CHANNEL_WARNING` 与 details |
| H08 发现：账号新建在幂等存储写回失败时返回 503 | 带 key 新建账号时，账号已建好但 mark_succeeded 失败，`AccountHandler.Create` 自己处理错误、返回 503 `IDEMPOTENCY_STORE_UNAVAILABLE`，不像其他接口按 result-committed 降级返回 200 加 `X-Idempotency-Degraded: result-committed`，客户端可能把已建好的账号误判为失败、换新 key 重发后建出第二个 | 既有缺陷，不在 Q16 范围；要改 Create 的错误分支并补测试，可能与 C06 的混合渠道 409 分支交叉 | 维护者确认后，在 Create 里先判断 idempotencyBusinessResultCommitted，命中时照常调度探测并返回 200 加降级头 |
| H08 可选：清理只剩测试在用的幂等 helper | `executeAdminIdempotentJSON`、`executeAdminOptionalMoneyWriteJSON`、`executeAdminIdempotentJSONFailOpenOnStoreUnavailable` 现在只有测试调用 | 删掉要同时改写 fail-close / fail-open / 并发等既有测试，属于清理，与本条行为无关 | 维护者决定是否收敛 helper 时一并处理 |
| G06 可选：PATCH /admin/accounts/:id 支持可选 Idempotency-Key | C03 的按键编辑接口不认 key | 文档清单里没有；If-Match 已让重试结果确定（成功后再发得到 412，App 读回比对即可），重放也补不回 ETag | 有客户端需要时在 Patch 外层套 executeAdminOptionalWrite，并决定重放时如何返回 ETag |
| G06 可选：G06 / H08 这些可选幂等写入支持接管卡住的执行（ReclaimStaleProcessing） | 带 key 的执行进程崩溃后，该 key 会一直返回 IDEMPOTENCY_IN_PROGRESS，直到 24 小时 TTL 过期 | 这些写入没有业务层去重，接管重跑可能重复创建用户 / 分组或二次刷新上游令牌 | 先给用户、分组创建与账号刷新做业务层去重（类似 G03 的 batch_id），再对相应 scope 打开接管 |
| G06 可选：重放快照超过 64KB 被截断后返回 503 | 协调器把响应快照截断到 64KB，超大 bulk-update 结果或 batch-refresh 的 errors 列表重放时解码失败、返回 503 IDEMPOTENCY_STORE_UNAVAILABLE | 协调器层面的改动，影响所有 scope | 维护者决定提高上限、超长时只存摘要，或对这类 scope 放弃存快照 |
| H07 可选：公告正文超过约 64KB 时同 key 重放返回 503 | 带 key 新建超长公告（如 Markdown 内嵌 data URI 图片）首次成功，但快照被截断，同 key 重放解码失败返回 503 `IDEMPOTENCY_STORE_UNAVAILABLE`；不会重复创建，App 只能按标题搜索核对 | 公告正文很少超过 64KB，且超长时也不会重复建公告；通用解法已在上一行（G06 64KB）待定 | 确认是否真有超长公告；或幂等记录只存回执 `{id}`、重放时按 id `GetByID` 回读最新公告（类似 G03 回读兑换码），或给正文加长度上限 |
| H06 可选：公告已读汇总缓存 | 每次 read-summary / include_read_stats 都实时全表扫 users，文档提示可按 announcement_id 加 30–60 秒进程内缓存 | 响应已带 computed_at，几万用户量级毫秒到百毫秒，先不引入缓存失效问题 | 生产库实测汇总耗时，超过可接受范围再加缓存 |
| H06 可选：公告列表 include_read_stats 批量汇总 | 带 include_read_stats 时每条公告一次汇总查询（page_size 最大 1000 时最多 1000 次全表扫）；可让 targeting 为空的公告共用一次 COUNT，或单条语句算出整页 | 只对站长开放、Web 不带这个参数，App 列表默认 20 条 | App 确实在大页列表上带这个参数、实测变慢时再做 |
| H06 可选：Web 已读弹窗接入 read_state / eligible 筛选与 read-summary | 后端已支持，Web 弹窗仍只用 search / sort_by / sort_order | 条目没有要求改 Web | 维护者决定是否给 Web 加已读筛选与汇总 |
| H06 发现：老路径 read-status 搜索会命中已软删除的 API Key | `userRepo.ListWithFilters` 的 search 用 ent `HasAPIKeysWith(KeyContainsFold)`，软删除拦截器不下沉到子查询，已删除 Key 的明文仍能搜出用户；/admin/users 等 Web 搜索同理。H06 新路径已排除 | 改老路径会改变 /admin/users 等既有 Web 搜索的语义，不在本条范围 | 维护者决定是否让用户搜索统一排除已删除 Key（加 `apikey.DeletedAtIsNil()`） |
| E06 可选：Key 列表按 effective_status 筛选 | 现在 status 筛选按库里原值精确匹配：status=inactive 筛不到历史 disabled 行，status=expired 筛不到运行时过期的 active 行；App 只能拿到列表后按 effective_status 自己统计 | 文档没要求；涉及按服务器时间判断过期和额度，要改 SQL | 维护者决定是否给用户 / 分组 Key 列表加 effective_status 筛选参数 |
| E06 可选：Web 前端 ApiKey 类型补 effective_status、用户侧 PUT 接受 disabled | Web 不读该字段，用户侧也从不发 disabled；文档只要求管理端归一 | 不影响现有功能 | Web 需要显示“已过期 / 额度耗尽”徽章时再加 |
| E11 可选：管理端 Key 列表 concurrency_available | Redis 读失败时 current_concurrency 为 0，App 无法区分“0 个并发”和“读不到”；ConcurrencyService.GetAPIKeyConcurrencyBatch 会吞掉错误并返回全 0 | 新增一个返回可用性的批量读取方法（最好与 C15 的账号侧可用性口径一起定），再在三个管理端 Key 读取接口加 concurrency_available |
| E11 可选：GET /admin/users/:id/api-keys 支持 sort_by=current_concurrency | 现在传该值会回落按 id 排序，App 没有提这个需求 | App 需要按当前并发排序时，参考用户侧 listByCurrentConcurrency 的全量排序再分页 |
| F04 可选：idle_account_count 拆成 paused_account_count 与 inactive_account_count | 文档写的是“需要时再拆”，现在色格条只需要四桶 | App 确实要区分暂停与停用时再加一个 FILTER 列（注意停调度但在限时窗口的账号归哪一桶要先定） |
| F04 可选：POST /admin/groups 新建分组的响应回填完整计数 | 该响应以前就不加载计数，新字段为 0，App 不靠它显示分桶 | 需要时在 CreateGroup 末尾改用 GetByID 回读 |
| F04 可选：Web 前端 AdminGroup 类型补 error_account_count、idle_account_count | Web 不读这两个字段，按“Web 行为不变”不改 | Web 分组页要显示四桶时再加 |
| F05 可选：Web 前端 groups.ts 的 getCapacitySummary 支持传分组 ID | Web 分组页一次显示全部分组，用不到按 ID 过滤，按“Web 行为不变”不改 | Web 出现单分组容量视图时再加可选参数 |
| F05 可选：分组存在性与启用状态合并成一条仓储查询 | 现在带参数时是 ExistsByIDs + ListActiveIDs + 容量 SQL 三条小查询，groups 是小表，代价很小 | App 前台轮询量大到这两条查询在库上可见时，再加一个同时返回 id 与 status 的仓储方法 |
| F05 可选：单分组容量结果短 TTL 缓存 | App 前台轮询频率低，已有 panelRateLimiter 兜底 | 生产上同一分组容量被多端高频轮询、Redis 读取压力明显时再加几秒缓存 |
| E07 单平台限额 Idempotency-Key | 单平台 PUT / DELETE / restore 没有接入可选幂等 | PUT 写的是绝对值，重放结果相同；DELETE 重放得到 404、restore 重放得到 409 / 404，App 都能据此判断，不需要幂等 | App 实测发现需要区分“首次成功”与“重放”时，再按 G06 的 executeAdminOptionalWriteJSON 接入 |
| E07 restore 选择指定历史行（含审查 LOW：多级撤销恢复错行） | restore 只能恢复最近一次软删的行，不能按 id 选更早的历史，也没有列出软删历史的接口；连续撤销两步时会恢复错行：DELETE 取消限额（软删带用量的 A）→ PUT 新建 B（previous=null）→ 撤销新建发 DELETE（软删 B）→ 撤销取消发 restore，恢复的是刚删的 B（用量 0），不是 A，用量照样丢了 | 需求原文就是“恢复最近一次软删”，单步撤销没有问题；按 id 恢复要新增读接口、改 App 撤销栈 | 维护者确认需要多级撤销或“限额历史 / 回滚到任意一次”时，加 GET 历史列表与 restore?id=（或让 DELETE / PUT 响应带被软删行的 id，App 撤销时按 id 恢复）；在此之前 App 只撤销最近一步 |
| E07 flusher 开启时 DELETE 先刷用量 | flusher_enabled=true 时 DELETE 随缓存键丢掉 Redis 里未刷进库的用量，restore 恢复的用量最多落后一个刷新周期 | 默认关闭 flusher；要在 DELETE 前同步刷该平台的脏用量，得改 flusher 的单键刷写路径 | 有站点开启 flusher 且在意 restore 后用量精确时，在 SoftDeleteOne 前先 BatchSnapshotUsage 该 (user, platform) |
| E08 可选：rpm-status 不限额时也显示真实用量 | 按 Q14 只加 tracked 标记；“不限额也计数”（cache 新增 IncrementUserAndGroupRPM、配置开关 rpm.track_unlimited 默认关）会让热路径多一次 Redis 往返，“从 usage_logs 估算并标 observed_from”只统计已完成请求、有滞后 | 维护者想在 App 看到不限额用户 / 分组本分钟的真实请求数时，二选一拍板后再做 |
| E08 残留的 RPM 旧口径文案 | Web i18n `frontend/src/i18n/locales/zh/admin/overview.ts` 两处 rpmLimitHint（用户级“仅在分组未设置时兜底”、分组级“覆盖用户级 rpm_limit”）、`ent/schema/user.go` rpm_limit 注释、`ent/schema/group.go` rpm_limit 的 `.Comment()`、迁移 125 / 126 写入的列 COMMENT 仍是旧口径；本条只改 Go 注释，Web 文案按“Web 行为不变”不动，改 `.Comment()` 要重新生成 Ent，列 COMMENT 要新迁移 | 维护者同意改 Web 文案、并接受一次 Ent 生成与一条只改 COMMENT 的迁移时再做 |
| G06 审查 LOW：同 key 只改密码重发得到首次的重放 | POST /admin/users 与 PUT /admin/users/:id 的幂等指纹不含密码（只记 password_set），同一个 key 只改密码重发返回首次的重放，生效的是第一次的密码 | 交叉审查裁定指纹不得含可离线猜测的密码哈希（`9256ccf3c`），行为已写进 sub2 `docs/API_ERROR_CODES.md`；App 按“冻结原请求”重试，改了内容应换新 key；用服务端密钥做 HMAC 要给 UserHandler 注入密钥（改 wire），密钥轮换后已存记录全部冲突 | 维护者认为需要让“同 key 改密码”返回 409 时，选一个稳定的服务端密钥，对 password 做 HMAC-SHA256 后放进 payload，补同 key 换密码为 409 的测试 |
| G07 可选：Web 前端 batchDelete 类型补 skipped_used / skipped_ids | `frontend/src/api/admin/redeem.ts` 的 batchDelete 返回类型没补新字段；Web“删除未使用”只取 status=unused、只显示 deleted，行为不变 | Web 需要提示“有 N 个已使用的码被跳过”时再补类型与文案 |
| G07 可选：清理死代码 RedeemService.Delete | 没有调用方，只判断 status==used（reason `REDEEM_CODE_DELETE_USED`），不覆盖 used_by 与 admin_* 记录；本条只在仓储接口注释写明管理端删除必须走 DeleteUnlessUsed | 维护者确认没有外部调用方后删除，或改为调用 DeleteUnlessUsed |
| G08 可选：Web getStats 返回类型同步 | `frontend/src/api/admin/redeem.ts` 的 getStats 类型仍是旧的 by_type{balance,concurrency,trial}，没有 by_status，by_type 应为 Record<string, number>；Web 没有任何调用方，本条按“Web 不动”未改 | Web 要在兑换码页显示状态计数时再同步类型 |
| G08 可选：兑换码统计提速与单快照 | 不带过滤时 stats 对 redeem_codes 全表 GROUP BY type, status，type 列无索引，admin_* 调整记录随每次调整增长；两条语句（GROUP BY + 已过期 unused 的 COUNT）不在同一快照，并发写入时单个状态可能差几个 | 生产库实测 stats 慢时再加 (type, created_at DESC) 索引的迁移；需要严格一致时改为 REPEATABLE READ 只读事务（仓储测试里 client 本身是事务，要沿用 G07 的 ErrTxStarted 回退） |
| E10 可选：回填历史 users.total_recharged | 部署后管理员充值、新建用户初始余额、注册与首次绑定赠送才开始累加；回填会一次性改变所有老用户的百分比余额提醒阈值和快捷充值 low_balance | 维护者确认要回填后写迁移：按用户累加 admin_balance 正值行（及历史注册赠送，若能可靠识别） |
| E10 可选：旧调整行回填 redeem_code_id | 223 之后、E10 之前的账本行没有 redeem_code_id，balance-history 查询时按（用户、类型、created_at=used_at、delta=value）回退匹配；回填要临时禁用 append-only 触发器改审计表 | 回退匹配出现误配或性能问题时再做 |
| E10 可选：Web 文案与类型同步 | Web 调整面板对 admin_create_user / default_balance 来源显示原始字符串；`frontend/src/api/admin/userAdjustments.ts` 没补 redeem_code_id；Web 余额历史没展示 before / after 与 total_recharged_breakdown；按“Web 行为不变”不改 | Web 需要时补 i18n 来源文案与类型 |
| E10 可选：用户侧充值记录区分注册赠送 | 注册 / 首次绑定赠送与新建用户初始余额在用户自己的 /redeem/history 里是 admin_balance 类型（备注“初始余额”或“首次绑定赠送余额”），用户端会按“管理员调整”展示 | 需要单独展示时新增兑换记录类型或在 DTO 加来源字段 |
| E10 可选：user-adjustments CSV 导出加 redeem_code_id 列 | JSON 已有该字段，CSV 列保持不变 | 有人用 CSV 对账兼容行时再加 |
| E10 可选：新建用户自定义初始余额备注、初始并发入账 | CreateUserRequest 没有 adjustment_notes，初始余额备注固定“初始余额”（请求上下文带了 notes 时用它）；初始并发不写并发账本 | App 需要开户备注或审计初始并发时再加 |
| E10 可选：pending OAuth 注册回滚时冲销赠送记录 | RollbackOAuthEmailAccountCreation 删除半成品账号时，已写的 default_balance 账本行（append-only）与兼容行保留，充值与调整记录里会留一条指向已删除用户的赠送 | 需要严格对账时改为回滚写一条反向记录，或把入账推迟到 FinalizeOAuthEmailAccount |
| E10 审查 LOW：兑换码管理列表与统计里出现站点赠送兼容行 | 站点 default_balance > 0 时每个新注册用户、每次首次绑定赠送都会写一条 admin_balance 兼容行，出现在 Web 兑换码管理列表（type 默认为空，不排除 admin_*）和 `GET /admin/redeem-codes/stats` 的 by_type.admin_balance 计数里；管理员调整本来就在这里，按“Web 行为不变”不改，已写进部署注意（`77ffc3f83`） | 维护者觉得干扰时，Web 兑换码页默认传 `exclude_types=admin_balance,admin_concurrency`（接口已支持），或列表 / 统计默认排除站点赠送 |
| E10 审查 LOW：总充值是否包含站点赠送 | balance-history 的 total_recharged 与 users.total_recharged 都包含注册 / 首次绑定赠送（按编排者裁定 Q12 站点 default_balance 入账并累加）；`77ffc3f83` 已在 total_recharged_breakdown 单列 grant，admin 只含管理员入账 | 维护者认为免费赠送不算充值时，把 total_recharged 改为 redeem + admin 并停止对站点赠送累加 users.total_recharged；属于口径变化（百分比余额提醒阈值随之变小），要写部署注意 |
| A09 可选：受信设备免验证码 / App Attest | 文档明确不建议做：会削弱登录防刷，管理员在 App 上登录频率低，桥页够用 | 先做 A04 方案 B 的设备密钥会话，再允许“已绑定设备密钥 + 仍有效的 refresh 会话”重新登录时免验证码 |
| A09 可选：前端单独部署时也给出 mobile_verify_path | 后端只能检查二进制内嵌的前端，非 embed 构建恒为 "" | 加一个配置或站点设置让管理员声明桥页已部署，或 App 自己探测 /mobile/verify |
| A09 可选：OAuth 启动与待处理 OAuth 接口接受 captcha_provider / aliyun_captcha_param | 这些是浏览器绑定流程，原生 App 不走，文档也没列入 | 原生 App 要支持第三方登录时 |
| A09 可选：桥页 envelope 直接输出 aliyun_captcha_param，Web 类型补 captcha_provider / mobile_verify_path | 要改 Web 前端；原生端把阿里云的 turnstile_token 映射过去即可，旧字段照常可用 | 维护者决定 Web 也改用新字段时 |
| A11 | 可选：APNs 推送中继（公共发行版 App） | 编排者裁定不做：站点直推只适用于站长用自己 Team 的 p8 私钥构建的 App；用公共发行版 App 的站点只能用 Bark / ntfy / Webhook | 需要 App 发行方持有 p8 的独立中继服务与信任模型（站点把消息转给中继） |
| A11 | 可选：推送正文带账号名或分组名 | 编排者裁定默认只带 #ID、平台、错误类别：账号名可能含邮箱等用户数据，会经 Apple / Bark / ntfy / Webhook 第三方服务器 | 维护者决定加站点开关（默认关）后，在 push_sources.go 的文案里加名字 |
| A11 | 可选：Web 管理端“推送 / APNs 配置”卡片 | 本次只提供接口，App 或 curl 可配置；Web 需要 i18n 与 SettingsView 改动 | 维护者要在 Web 上配置 APNs 或管理推送设备时 |
| A11 | 可选：限流类事件推送（account.rate_limited / temp_unschedulable） | 量大，需要聚合策略；错误类已由 account.error 覆盖 | 有实际需求并定好聚合口径时，在 push_sources.go 加数据源 |
| A11 | 可选：每台设备每轮投递上限与“另有 N 个账号异常”合并 | 现在只靠 account.error 的节流（每台设备同一账号 30 分钟内最多一条），上游整体故障时许多账号同时出错，仍可能一次推很多条（每轮扫描最多 500 条） | 先观察真实站点的推送量，再定每设备每轮上限（建议 20）与合并文案 |
| A11 | 可选：P0 告警越过免打扰（quiet_hours_bypass_p0） | 验收要求免打扰时段内不推，时段内的事件直接跳过、不补推 | 订阅里加一个开关 |
| A11 | 可选：APNs 配置的 config.yaml / 环境变量后备（p8 文件路径） | 先只做后台设置（独立设置键 push_apns_config） | 有需要用配置文件下发 p8 的部署时 |
| A11 | 可选：通知点击深链（Bark url / ntfy Click / 自定义 scheme） | App 的 URL scheme 未定；APNs 载荷已带 alert_event_id / account_id / run_id 供 App 自己跳转 | App 定下 scheme 后在 Bark / ntfy 载荷里加跳转地址 |
| A11 | 可选：测试推送限频、退出登录 / 会话吊销时自动清理推送设备 | 测试接口没有单独限频（审查修正后只读 sat_ 只能注册 iOS 设备，但仍能对令牌主人已登记的 Bark / ntfy / Webhook 触发测试）；会话吊销不会删除设备，App 需在退出时调 DELETE | 出现滥用或 App 端清理不可靠时：给 test 加每设备限频，或把设备与会话 / 令牌关联 |
| A11 | 可选：Bark / ntfy / Webhook 经出站代理发送、APNs 未配置期间的 iOS 投递补发 | 通用渠道为保证发送时的私网 IP 校验不走代理，必须经代理出网的部署用不了；APNs 未配置时 iOS 投递直接记失败，配置补全后不补推 | 需要时给通用渠道加“经代理发送”的显式开关（代理侧负责 SSRF 防护），或把未配置期间的投递改为延后重试 |
| A11 | 可选：投递按渠道分队列认领、apns-expiration 按事件发生时间算、Bark / ntfy / Webhook 不回显对端响应正文 | 审查修正已改为一轮内多批认领，并按轮记住不可达设备（一个死目标每轮只耗一次超时），APNs 不再被外部渠道拖住几十分钟；对端原因只出现在 /test 的 502 与设备 last_error 里，只给设备主人看，且内网目标默认已禁止 | 外部渠道慢响应仍明显拖慢 APNs，或站长开了 security.push_targets.allow_private_hosts 又不信任全部管理员时：APNs 与外部渠道分开认领，非 APNs 渠道只回显状态码 |

## App 与设计

| 事项 | 说明 |
|---|---|
| 简化模式（C 表格工作台风格） | 双风格应用的第二种模式，主模式定稿并实现后再设计；共享数据、筛选、选中对象与动作 |
| 利润亏损的固定演示状态 | 设计稿演示数据里没有亏损时段，负值柱只临时渲染验证过 |
| 设计稿冒烟工具读取 expect 字段自动断言文案 | 现在文案只靠截图人工核对 |
| 验证码桥页导航回调签名不匹配 | Xcode 27.1 编译 `NativeApp/Features/CaptchaView.swift:91` 报 “`webView(_:decidePolicyFor:decisionHandler:)` nearly matches optional requirement”（S0-03 之前就有，不是新增）。签名不匹配时 WebKit 不会调用它，顶层跨域导航拦截可能已失效；建议 S0-16 重写 CaptchaView 时按新 SDK 修正签名并补测试，或由 S0-19 收口。**S0-16 已处理**：改用 async 版 `webView(_:decidePolicyFor:) async -> WKNavigationActionPolicy`，警告消除；UI 测试用夹具代替 WKWebView，顶层跨域导航拦截还没在真机或测试环境验证，联调时确认 |
| 超过 800 行的设计稿文件拆分 | v-account-new、v-account-edit、v-user-edit、v-analytics、v-groups 等 |
| 监控告警详情里“阈值 5% · 近 5 分钟”的窗口说明 | 这是告警规则自己的窗口，目前保留；如需全应用都不写窗口再去掉 |
| 长超时读请求超时后的自动重试 | S0-04 按 00 §2.4 对所有读请求的超时自动重试 2 次，统计聚合（45 秒）与 dashboard/stats（90 秒）最坏约 4.5 分钟才报错、同一重查询最多跑 3 遍；阶段 1 / U54 在生产量级实测后决定是否对这两类不再重试超时，或改用 count_mode=deferred 缩短 |
| 真机确认 ETag 304 | S0-05 的条件请求只经桩传输层测试：URLSessionTransport（ephemeral、urlCache=nil、reloadIgnoringLocalCacheData）对手动设置的 If-None-Match 收到 304 时应原样返回空体 304。在测试环境连真实站点确认一次账号列表或用户列表的第二次请求得到 304、页面数据不变，并记入进度表 |
| 余额页 UI 测试 | S0-06 给现有 BalanceView 加了“稍后核对”（balance.later），但 -ui-testing 模式在落盘前就拒绝余额写入，按钮不会出现；S0-13 审查修正后“确认并重试原请求”被合规 / 二次验证拒绝时保留记录，这条分支同样没有 UI 测试。阶段 3 重写 BalanceKeypadSheet 时用夹具模拟慢写入（等待中点“稍后核对”→ 记录保留待核对、显示 00 §2.5.4 文案）和重试时收到 423 / STEP_UP_REQUIRED（稍后 → 记录仍在；通过 → 原记录重新确认），补 UI 测试 |
| UI 测试 6 并发下的快照停顿 | S0-07 的 gate 里，Mac 负载 90–170 时模拟器无障碍快照会停顿 15–20 秒（基线 709c047 同样出现）。Sub2MobileUITests.testDashboardSlowTrendDoesNotDelayCountersOrMonitoring 只有夹具 8 秒的趋势延迟作窗口，停顿落在登录后就误报；趋势缩放用例的 5 秒等待同理。S0-19 诊断时考虑：降低默认并发、把慢趋势夹具延迟加长或改为由测试显式放行、等待改为基于状态而不是时间窗。S0-19 结论：基线 7 个不稳定用例里 6 个的失败来自“拖动后列表还在减速就点按”与每步全量快照，已改为点按前等待 frame 稳定（waitUntilSettled）并去掉每步截图与 print，gate 76 / 76 无重跑。**仍依赖快照不停顿、没有修好的两个**（S0-LOW-B 复核更正）：AccountListCustomizationUITests.testSlowTodayStatsAllowsIndependentRuntimeRefresh 不调用 setField / moveFieldToFirst，S0-19 没有改到它，它的等待（assertDetail 10 秒、runtime-updated 5 秒）本来就是按状态的谓词等待，只是负载下快照停顿会吃掉窗口，S0-19 / S0-LOW-A / S0-LOW-B 的 gate 通过只说明没有复现，阶段 2 账号页重写时整体替换；Sub2MobileUITests.testDashboardSlowTrendDoesNotDelayCountersOrMonitoring 的 8 秒夹具窗口同理，如再出现可改为由测试显式放行。在此之前这两个用例再失败按既有不稳定处理，不算新回归 |
| 数值格式里规格没写清的定法 | S0-08 在 DisplayFormat 里按字面或“按舍入后的值”定了这些细节，等用户确认：RPM 小于 10 保留 1 位（2 → 2.0、0.04 → 0.0）；minutesLeft 整点写“2 小时”（设计稿 fmt 会写“2 小时 0 分钟”）；change 舍入为 0 写“0.0%”不带箭头；relativeTime 跨年的日期不带年份、未来 60 秒内也写“刚刚”；跨档按舍入后的值（999,950 → 1M、99.96 秒 → 100s、$999.995 → $1.00K）；countdown 秒数向上取整；compact 不加千分位（1000B 以上才会出现）。要改只改 `Sources/Sub2Core/DisplayFormat.swift` 一处与 DisplayFormatTests。 |
| 缺失值“—”的读屏 | S0-08 把全 App 的缺失值统一为“—”，现有页面的 accessibilityValue 沿用显示文字，VoiceOver 可能读成“破折号”或跳过。各页面重写时决定是否给缺失值单独的朗读文案（如“无数据”）。 |
| 倍率的显示位数 | 账号倍率、分组计费倍率与上游探测倍率规格没有格式规则，S0-08 仍显示服务端原值的全部位数（如 1.234567890123456789×），不走 DisplayFormat。阶段 2 / 5 重写账号、分组页时定位数，届时用 DisplayFormat.decimal。 |
| 区块刷新失败退避的第三档 | 00 §4.6 与 D23 写“连续失败时间隔加倍（60 → 120 → 300 秒封顶）”，S0-09 按加倍实现为 60 → 120 → 240 → 300；如要严格三档（第 3 次直接 300 秒），只改 `BlockRefresh.nextRefreshInterval` 一处并更新 BlockStateTests |
| 区块 429 倒计时文案与重试按钮 | S0-09 的 LoadState 已在 429 后按 retry_after（最长 300 秒）暂停该区块请求并提供“请求过于频繁，N 秒后自动重试”（`BlockRefresh.throttleMessage`），现有页面还没显示它：仍显示目录文案“请求过于频繁，请 N 秒后再试”（等待期内清空或切换范围的 reset() 也保留这条文案；统计分析页换筛选也改用 reset()，不再新建 LoadState 丢掉等待，S0-LOW-A），等待期内点“重试”没有反应；没开自动刷新的页面（如账号今日统计）等待结束后不会自动重发，要手动重试。阶段 1 的区块小视图接入时显示倒计时文案、在等待期内禁用重试，并在等待结束时自动重发 |
| 登录设备名 | 00 §1.2 的 `client.device_name` 首版照规格发 `UIDevice.current.name`；iOS 16 起没有 `com.apple.developer.device-information.user-assigned-device-name` 权限时只返回“iPhone”这类机型名，“登录设备”列表里所有手机同名。待定：申请该权限，或改为“机型 + 用户自定义名称”（S0-10） |
| 重装后的 Keychain 孤儿条目 | Keychain 条目在删除 App 后通常保留，重装后站点列表（UserDefaults）清空、站点 UUID 变化，旧的 `<UUID>` 与 `<UUID>.device` 条目不再被引用（凭据本来也有此问题）。不含可用会话，S0-10 未清理；如需清理，可在首次启动且站点列表为空时按 service 清空 |
| 有待核对记录的站点重新登录会多出一个同名站点 | S0-11 按 D17：站点还有待核对的资金记录时，从该站点登录页重新登录会新建站点 id，旧站点（凭据已清）留在列表里，记录继续挂在旧 id 上。S0-15 重写设置页时没有处理（设置页只列站点，不区分凭据已清的旧站点），留给 S0-16 重写登录页时决定是否提示“旧站点仅供核对”或合并显示 |
| 让其他设备下线可能连本机一起下线 | 后端对部署前签发、令牌里没有 sid 的旧会话，keep_current=true 仍会撤销全部会话，两种结果只有 message 不同。S0-11 的 revokeOtherSessions 不返回结果，本机若被撤销靠下一次 401 TOKEN_REVOKED 回到登录页；阶段 6 登录设备页操作后重载列表即可触发。**S6-01 已处理**：见“App 与设计 · 阶段 6”同名行 |
| 推送登记要等待该站点的收尾结束 | S0-11 删除站点的服务端收尾（最长 20 秒）可能在用户马上用同一地址重新登录后才 DELETE 推送设备；阶段 6 的 PushCoordinator 注册前应等待该站点的收尾任务结束，避免刚登记的同 id 设备被删 |
| UI 测试期间模拟器后台进程暴涨 | S0-11 的三次 gate 中 Mac 负载多次冲到 100–600：模拟器克隆里 PosterBoard / *Poster 扩展与 SetStoreUpdateService 成批启动（按 Home 回桌面时也会触发），单个用例耗时到 5–10 分钟，计时类用例因此偶发失败。S0-19 诊断基线时一并看是否要在模拟器里关掉墙纸 / 海报扩展或降低并发。结论（S0-LOW-B 补记）：S0-19 没有关墙纸 / 海报扩展；mac-test.sh 的 UI 测试已固定为 3 台模拟器并行（6 台时负载过高，S0-07 证实），之后 S0-19、S0-LOW-A 的 gate 都没有重跑。阶段 1 起由集成者的 gate 继续观察，负载再冲高、单个用例超过 5 分钟时，再在模拟器克隆里关掉 PosterBoard 相关扩展 |
| 资金写待核对的界面与回前台自动核对 | S0-12 只建了三类本机记录、AppModel.reconcile 与 R03 门控（moneyWriteGate）、重试权限；概览“待处理”、设置页三类分区、用户详情与兑换码横幅、核对结果页，以及回到前台对本站点记录自动核对一次（30 §3.6、60 §19.4 第 9 步），分别由 S0-15、阶段 1 / 3 / 6 接上。现有余额页仍是旧界面，不调用 moneyWriteGate |
| 余额核对的阶段 3 部分 | BalanceReconciliation 只做 00 §2.5.5 的精确复核（D25）。30 §3.4 的候选匹配、多条候选、X-Request-ID 回显检查与按站点保存 requestIDUnreliable、旧记录（无 createdAt / 邮箱）按用户 ID 查询，在阶段 3 同一文件扩展 |
| 待核对文件锁屏读不出 | completeFileProtection 文件在设备锁定时预热启动会读不出，被标为不可读并暂停该类资金写。S0-12 审查修正后，restore() 开头和每次进入 .active（包括启动后的第一次）都会重读；提示改到 restore 里、在重读之后才弹，读出后会收起或缩短。预热启动的实际表现还没有在真机上验证，验证后再决定是否改成 completeUntilFirstUserAuthentication |
| 待核对门控跨站点 id | **资金安全问题，阶段 3 必做、不能跳过**（S0-19 核对）：同一地址重新登录后新站点 id 可能对同一用户重复发起充值 / 退款，修法牵涉“用当前身份核对旧站点 id 的记录”的界面，随阶段 3 余额核对页实现。R03 门控（PendingMoneyGate / moneyWriteGate）和现有余额页都只按站点 id 判断。按 D17，有待核对记录的站点重新登录会新建站点 id，同一服务器也可以保存多个身份，所以挂在旧站点 id 上、同一服务器同一用户的待核对充值、退款、补偿和兑换码批次，拦不住新站点 id 下的同类写入。旧站点的凭据已经清除，APIClient 的核对又会拒绝其他站点的记录（stationMismatch）；如果直接把同一地址的记录算进门控，没有例外的补偿会被永久拦住。阶段 3 / 6 接入门控时一并决定：同一地址的记录是否计入门控，是否允许用当前身份核对或放弃这类记录 |
| 余额重试后的执行宽限 | **阶段 3 必做**（S0-19 列入阶段 0 未做项）。40 秒执行宽限按 createdAt 计算（30 §3.4、D25）。S0-12 审查修正后，新记录在“确认发送”时取 createdAt；但“用同一编号重试”不更新 createdAt，因为退路查询的时间窗要从第一次发送算起。重试刚发出就核对会判为 notExecuted，并给出“放弃这笔”。阶段 3 实现核对框里的重试时，给记录加“最近一次发送时间”，宽限从这个时间起算（D16 规定 S0-12 不改 Models.swift） |
| 合规确认页的文案与版式 | S0-13 的全局合规页没有设计稿，标题、说明、按钮与读区块失败文案“需要先完成管理员合规确认”都是自拟；用户看过模拟器截图（Mac 上 ui.xcresult 的 compliance-sheet 附件）后再定，可能要补设计稿 |
| 后端文档补两个 reason | step-up 接口在用户关闭 TOTP 后返回 400 TOTP_NOT_SETUP，合规确认语句不一致返回 400 ADMIN_COMPLIANCE_INVALID_PHRASE，sub2 docs/API_ERROR_CODES.md 都没有；App 已分别按“未开 TOTP”与“确认语句不一致，请逐字输入”处理，请后端补进文档 |
| 合规 / 二次验证通过后的回执 | S0-13 通过后只在原页面显示“…已通过，请重新确认后发送”，没有“合规确认已完成”这类回执；S0-14 的回执（ReceiptCenter）建好后补上 |
| 读区块的“完成合规确认”入口 | 用户点“稍后”后，同一会话的后台读请求不再自动弹合规，区块只显示“需要先完成管理员合规确认”；阶段 1 重写概览错误块时加按钮调用 AppModel.presentCompliance()（用户发起，会再次弹出） |
| 覆盖层窗口的外观与读屏 | S0-13 的全局 sheet 在覆盖层 UIWindow 里，S0-15 起每次弹出时按 App 的外观设置取 overrideUserInterfaceStyle（不再复制主窗口）；VoiceOver 焦点进入与离开覆盖层窗口需要真机核对 |
| 读类 POST 的安全重发 | S0-13 的钩子只对 RequestClass.isRead 的请求在验证通过后自动重发；reveal（POST admin/api-keys/:id/reveal）等语义是读的 POST 在阶段 3 / 6 实现时要显式声明请求类别，或发送前先调用 ensureStepUp（30 §7 本来就先主动判断） |
| 站点标题菜单与大标题 | S0-14 在 iOS 27 模拟器上实测：大标题与 `.toolbarTitleDisplayMode(.inlineLarge)` 都打不开 `.toolbarTitleMenu`（标题只是静态文字），所以概览与账号 Tab 的标题改为 inline 显示（系统画下拉箭头，点开就是站点菜单）。10 §0.7-5 要的是“大标题就是站点菜单”，需 iOS 26 / 27 实机确认；要恢复大标题时只改 `NativeApp/Views/SiteMenu.swift` 的 `siteTitleMenu()`（例如 iOS 26 的 `ToolbarItem(placement: .largeTitle)` 放一个以站点名为标签的 `Menu`） |
| 搜索 Tab 在实机上的样子 | S0-14 在 iOS 27 模拟器上：`Tab(role: .search)` 显示为 Tab 栏里的第五项（没有分离成独立玻璃按钮），选中时不自动弹键盘，搜索框在导航栏抽屉里，与 60 §1.1 一致。U40 要求 iOS 26 / 27 实机各验一次 |
| 路由参数在旧页面上不生效 | S0-14 把路由映射到现有页面时，现有页面不支持的参数没有传：`.logs` 的 user / model / modelSource、`.analytics` 的 range / focus / metric（目录进统计仍从“今天”开始，40 §1.1 要近 7 天）、`.groups` 的 segment、`.account` 的 focus（`.settings` 的 focus 已由 S0-15 接上）。各阶段换新页面时生效；`.groupBatch` 的 items 等阶段 5 定义结果类型再加 |
| 跨 Tab 跳转撤不掉视图式推入的页面 | `AppRouter.select` 只清空目标 Tab 的 path；现有页面用 `NavigationLink { 目标 }` 推入的页面不在 path 里，会留在栈上。阶段 0 只有目录“告警事件”切到监控 Tab，监控 Tab 没有这类页面；概览、账号重写时改用 `NavigationLink(value: AppRoute)` |
| Face ID 金额门槛 sheet 的键盘 | S0-15 的门槛 sheet 用大字显示 + 系统 numberPad（D22），S0-18 只把逐键过滤换成 KeypadInput；是否换成阶段 3 KeypadSheet 的大数字键盘界面，阶段 3 做用户余额键盘时一并决定（标识 settings.threshold.field / settings.threshold.save 不变） |
| 站点行的身份邮箱 | 00 §1.1 要求站点行显示登录方式徽章和身份邮箱，Admin Key 站点加“以 <email> 身份操作（第一个管理员）”；admin/me 快照只在内存、只有当前站点有，S0-15 的站点行只显示徽章，邮箱与 Admin Key 说明放在“当前站点”分区。要不要按站点缓存 me 快照、在每个站点行都显示邮箱，待定 |
| 外观切回“跟随系统”的实机核对 | RootView 用 `.preferredColorScheme(nil / .light / .dark)`；SwiftUI 在深色与跟随系统之间来回切换时有“切回 nil 不还原”的已知问题。模拟器 UI 测试只核对了选中状态，需实机确认，必要时改为直接设置窗口的 overrideUserInterfaceStyle |
| 通用删除确认还没有做 | 60 §0.4：Face ID 关闭时要输入完整名称（兑换码末 4 位，不分大小写）才能删除，打开时按钮写“用 Face ID 删除”。S0-15 只提供 BiometricGate.deleteConfirmation / deleteNameMatches，并给现有删除分组接上验证；现有删除确认框仍是旧样式，由首个重写删除流程的阶段做通用组件 |
| “站点与凭据”的滚动位置 | iOS 27 模拟器上 List 的 ScrollViewReader 只按 .top / .center 定位：.top 会把“站点”分区标题藏到导航栏下面（列表延伸到导航栏后），所以 S0-15 把第一个站点行滚到居中，上方仍露出安全、通知分区。实机看效果后再定是否改用其他滚动方式 |
| 登录协议同意是否按 revision 持久化 | Web 把同意记录按 `login_agreement_revision` 存在 localStorage，再次登录不再询问；S0-16 的 App 只在当前登录页内记住同意（登录很少发生，没新增存储键），modal 模式每次打开登录页提交时都会再问。需要时加一个按站点地址 + revision 的本机记录 |
| 第 4 种验证码提供方 | 桥页校验器（CaptchaBridgeValidator / CaptchaBridge.providers）只接受 turnstile / tencent / aliyun；后端新增提供方时 App 会停止登录并提示“站点的验证方式暂不支持，请改用 Web 登录或管理访问令牌”。后端扩展时同步扩展校验器与 00 §1.5 的字段映射 |
| 桥页“未部署”的检测 | 站点没部署 /mobile/verify 时通常由 SPA 回退返回 200 的前端页面，WKWebView 不报加载失败，只能靠提示条（mobile_verify_path 为空时）与 180 秒超时兜底；如后端能让未知路径返回 404 或桥页加一个探测接口，可改为直接提示“站点未部署手机验证页” |
| 登录页、两步验证与协议 sheet 的设计稿 | 60 §4 没有对应设计稿，S0-16 的版式（三行单选、徽章色调、脚注说明、底部两步验证 sheet、协议弹窗）与两步验证 / 冷却按钮文案为自拟，待用户看模拟器截图确认 |
| status-summary 的 accounts[] 缺 auto_pause_on_expired 与 C02 字段 | 后端 AccountStatusItem 没有 auto_pause_on_expired，也没有 error_summary / error_kind / error_status_code / error_at。S0-17 现在按服务端 state == paused 推断“暂停 · 已过期”（10 秒缓存期间刚到期的账号可能短暂显示“正常”）；错误原因要另调 accounts?status=error 按 id 对齐（10 §1.2）。请后端补齐，补齐后去掉这两条退路 |
| status-summary 分组 shortage 的数值单位 | 后端按来源区分：default 的 threshold / current 是 0–1 比例，规则 group_available_ratio 的 current 是 0–100 百分数，group_available_accounts 是个数；20 §10.1 没写。S0-17 保留原始数值与 source / metricType，阶段 1 / 阶段 5 显示时按来源分支格式化 |
| 告警百分数的位数 | 告警百分数按 00 §6.2 为 1 位小数（5.0%），10 §6.3 示例写作 5%；如需改只改 AlertPresentation 的格式调用一处（D21，S0-18） |
| 告警规则缺失时的英文说明 | 规则已删且没有快照（rule 为 null）时，规则文案按 10 §6.3 显示后端 description 原文，它是英文（如 “error_rate > 5.00 (current 5.20) over last 5m (overall)”）；是否改为中文概述（指标名 + 阈值），待用户决定（S0-18） |
| 旧服务端事件缺 group_name | 10 §6.3 说“另拉 groups/all 拼”，S0-18 的 AlertPresentation.scopeText 只用事件自带的 group_name，没有时写“分组 · #12”；阶段 1 可先用分组目录补进 AlertEvent 再显示 |
| 认证方式术语统一 | 同一组登录方式三处三种写法：站点徽章“账号 / 管理访问令牌 / Admin Key”（00 §1.1），设置的认证方式“邮箱和密码 / Admin Key · 以第一个管理员身份操作 / 访问令牌 · 只读或读写”（60 §3.3），登录页“账号和密码（推荐）/ 管理访问令牌 / Admin Key（不推荐）”（60 §4.3）；“访问令牌”与“管理访问令牌”也混用。现在各处照抄所属章节，等用户决定是否统一（S0-19） |
| 错误详情的分享入口 | S0-19 的“错误详情”sheet 只有“复制详情”（本机剪贴板）；是否加“发送给站长 / 分享”，规格没有要求，等用户决定 |
| 现有页面按手机时区显示的时间 | “更新于 HH:MM:SS”、日志与统计的起止时间、ListFields 的时间列仍用 Date.formatted（手机时区），AnalyticsQuery 的默认时区与 RequestLogs 的 usage timezone 也取 TimeZone.current；00 §6.3 要求按服务器时区。阶段 1–4 重写这些页面时改用 DisplayFormat 与 SiteSession.serverTimeZone（S0-19 只改了性能趋势的刻度） |
| 旧服务端的站点时区退路是连接时的手机时区 | 拿不到 server_timezone 的站点（旧服务端），APIClient 与 SiteSession 存的是连接时求出的 `ServerTimeZone.device` 快照（D09），App 驻留期间手机改时区后，概览趋势等仍按旧时区发 timezone=，统计与日志页（TimeZone.current）已按新时区，要等回到前台超过 5 分钟的重新探测或重新连接才一致（S0-LOW-A 复核未改）。阶段 4 统一页面时区时，如需随手机即时变化，可把退路存成“未知”、在调用时取 .device |

### App 与设计 · 阶段 1

| 事项 | 说明 |
|---|---|
| 缺失值“—”的读屏 | 替换 App 与设计表中“缺失值“—”的读屏”原行：默认读“无数据”（S1-00 定）。Sources/Sub2Core/DisplayFormat.swift 的 DisplayFormat.missingSpoken 与 DisplayFormat.spoken(_:) 只做整值替换；各页重写时 accessibilityValue 套用，尚未重写的旧页面仍读显示文字。 S3-02（2fba3df）已处理用户列表：余额、今日消费、头像余额读“无数据”，见阶段 3 表同名行。 |
| APP-PROGRESS 中的旧 UI 用例名 | APP-PROGRESS.md 第 73 行“完成标志的 UI 测试”还写着 AppNavigationUITests.testFourTabsAndSearchTabReplaceManagementAndSettings 和 testSearchDirectoryOpensExistingPagesAndPlaceholders。S1-00 已把它们拆成 testTabBarAndTodayTab、testAccountsTabShowsAccounts、testUsersTabShowsUsers、testMonitorTabShowsSegments、testSearchTabShowsDirectory 与 7 个 testSearchDirectory*；Sub2MobileUITests.testLoginDashboardAccountPaginationAndDetails 已拆成 testLoginShowsDashboard 与 testAccountPaginationAndDetails。集成者写入进度行时可顺带更新这些名字。 |
| 首页被拒时区的记忆 | dashboardHome 每次调用都先带 timezone，被 400 INVALID_TIMEZONE 拒绝后再去掉重发，不记住结果。若 S1-05 实测某站点频繁出现，由 LiveOpsStore 记住被拒的时区，改传不带 timezone 的请求（需要再加一个重载）。 |
| 下拉刷新 nocache 的 ETag 键 | nocache=1 的请求与普通轮询是两个 ConditionalCache 键，第一次下拉刷新拿完整响应体，普通轮询的条目也不会因下拉刷新而更新。目前接受；若要让两者共用，需要在 S0-05 的缓存键规则里对 nocache 特判。 |
| 渠道“首字”格式 | 10 §5.3 写“秒，1 位小数”（设计稿 0.9s），按 R10 用 00 §6.2 的毫秒读数：不到 1 秒写 850ms，1–10 秒写 1.4s，10 秒以上取整（12s）；要改只需改 ChannelPresentation.firstTokenNote 里的一处调用（S1-03） |
| 渠道排序的中文顺序 | ChannelPresentation.sorted 同档按标题比较（.caseInsensitive + .numeric，不带 locale），中文按 Unicode 码位而不是拼音排序，测试结果确定；要拼音顺序时改为带 zh_Hans locale 的比较并补测试（S1-03） |
| 首页 accounts_truncated 时错误 / 过载行可能不全 | 后端最多列 100 个异常账号，按账号 id 顺序，上限对 error / overloaded / rate_limited / temp_unschedulable 四种状态合计生效。截断时错误行和过载行也可能漏掉；S1-04 只在受限行改用 totals 数字并加“等”，平静判定看 totals，不受影响。需要时加“另有 N 个异常账号”行，或请后端把 error / overloaded 排在前面 |
| 本机待核对文件读不出时的平静判定 | HomePresentation.isCalm 只看读得出的待核对记录。PendingMoneyLedger 某类文件读不出时，不阻止平静布局（设置页和全局提示已经显示读不出的通知）。如需更保守，再给 isCalm 加一个 hasUnreadablePending 参数 |
| 首页待处理行图标 | S1-04 暂定的 SF Symbol：告警 bell.fill、另有 bell.badge、错误 xmark.octagon.fill、过载 flame.fill、受限 hourglass、分组 square.stack.3d.up.fill、资金待核对 doc.text.magnifyingglass（设计稿 docCheck）、重试 arrow.clockwise。S1-10 视图落地时对照设计稿 v-today.jsx 核对 |
| 首页夹具与账号 Tab 演示数据不一致 | LiveOpsFixtures 的 calm / calm-limited 首页没有错误账号，账号 Tab 仍是 AccountDemoStore 的状态；“可用不足”只列企业专线（真实后端按默认规则还会标 GLM 组、MiniMax 组）；夹具的 status-summary 不按平台 / 分组过滤，alert-events 不按 time_range 过滤。S1-18 核对时注明，后续条目需要时在各自变体里补 |
| 告警乐观更新与在途刷新竞争 | markResolved / applySilence 不取消在途的 firing 刷新，迟到的旧列表可能把已解决事件带回；靠 S1-06 写成功后立即重拉校正（D06） |
| 告警计数读取失败不单独标记 | alert-events/counts 失败时 LiveOpsStore 保留上次计数（并发的列表请求会报失败）；S1-13 若要在监控分段计数旁显示“更新失败”，需要另给计数加状态 |
| LiveOpsFixtures.swift 体量 | 本条约 300 行；S1-06…S1-17 继续扩充时按主题拆到 LiveOpsFixtures+Monitor.swift 等新文件（Session 目录新文件自动进入 NativeSessionSupport，只需重新生成工程），避免超过 800 行 |
| 旧服务端告警静默 | 10 §7.1 退路在缺 ops_alert_silences 表的服务端上必然 500（迁移 247 与事件 silence 键同时上线），阶段 1 改为不提供静默（S1D1-15）；如用户要求按规格实现，加 LegacyAlertSilences 一个文件与 availableActions 一个分支 |
| 告警静默与规则 region | 规则过滤条件带 region 时，App 按规格不传 region 新建的静默匹配不到事件，读回后显示“操作没有生效，可以重试”；需要后端在事件 dimensions 或 rule 摘要里带上 region，或由 App 读取规则后再发 |
| INVALID_RULE_ID 文案 | 后端只在 rule_id ≤ 0 时返回 INVALID_RULE_ID，规则已删除时新建静默照样成功（没有外键，静默无效但无害）；App 已在 rule_id 无效时不给静默，收到时照表显示“规则已删除，无法静默”并在本会话隐藏该规则的静默；文案是否要改，需用户确认 |
| 告警夹具 #35 与 24h 窗口 | FixtureAlertBook 已按 time_range 过滤（相对会话开始的 base）；S1-05 的 #35 在昨天 21:52 触发，服务器时间 21:52 之后不在 24h 列表里。S1-16 等 UI 用例若断言最近结束含 #35，会随运行时段失败，应改用 #37，或把 #35 改为相对 base 的时间 |

### App 与设计 · 阶段 2

| 事项 | 说明 |
|---|---|
| ConditionalCache 缓存账号列表原始响应体 | S2-01 解码时剔除了凭据敏感键，但 ConditionalCache 按 00 §4.2 缓存原始响应体；2026-05 以前未脱敏的旧服务端，明文凭据会留在内存缓存里（登出、切站、401 时清空）。是否对 admin/accounts 的缓存体做脱敏或不缓存，由 S2-23 的凭据专项复核决定 |
| UpstreamAccount.credentials 可直接赋值 | credentials 是 public var，只在解码和 init 时剔除敏感键；之后代码直接赋值可以绕过。目前没有这种调用点，S2-05 / S2-10 / S2-12 的夹具若要在本地套用 credentials_patch，应经 init 重建或另加一个会剔除敏感键的辅助方法 |
| 账号平台显示名口径待用户确认 | S2D1-12 采用“App 已知平台用内置中文名（智谱 GLM），目录 display_name 只给后端新登记的平台”，与 20 §0.3 字面“目录 display_name 优先”不同；用户若坚持目录优先，只改 AccountNaming.platformName 一处与 accountNamingPlatformNames 一行断言 |
| MetaCatalog.builtin 需随后端同步重抄 | 内置平台清单是 sub2 main 70116315d 的 platformCatalog.builtin.json 与站长口径 platform_auth 的手抄快照（单测 builtinCatalogMatchesSub2BuiltinJSON 锁住当前值）；后端登记新平台或改官方端点时要重抄 |
| 账号列表超过 2000 行时按平台懒加载（U15） | S2-03 只加载前 2000 行（新服务端按紧急度，旧服务端按名称），底部提示“还有 N 个账号未加载，用平台筛选缩小范围”；旧服务端时 2000 行以外的错误账号看不到。U15 实测后再定是否按平台分区懒加载。 |
| 账号平台分区同级时的最后排序键 | 20 §1.3 只给到“需处理数降序、总数降序”，S2-03 再按平台 id 升序；以后若要按 meta/catalog 的平台顺序排，只改 AccountListLayout.platformOrder 一处。 |
| 账号行暂停 / 停用的降色方式 | S2-04 按设计稿 is-idle 只把名称改为 ink2，没有按 20 §1.3 整行降低不透明度（整行降透明度会让 ink2 / ink3 文字低于 4.5:1）。请看 AccountListUITests 的 account-row-idle 截图确认，要改只动 AccountRow.swift 的 AccountRowTitle |
| 平台菜单的平台个数位置 | iOS 系统菜单项不能放右对齐的自定义文字，S2-04 把“N 个”放在菜单项第二行（同站点菜单写法）；设计稿是右侧数字，实机看过后再决定是否改 |
| 旧接口 APIClient.accounts(page:…) | S2-04 删掉 AppModel 包装后，只剩 CoreTests / AccountRuntimeTests / ConditionalRequestTests 在用，与 managedAccounts 重复（R19）；交 S2-23 删除，并把测试改用 managedAccounts |
| 账号 Tab 意图的端到端 UI 测试 | S2-04 用夹具参数 -ui-accounts-intent 覆盖“从意图进入受限”；概览“受限 N 个账号”等行真正发出 .accounts(filter:) 的端到端测试由 S1-10 的 HomeUITests 补 |
| 进入账号 Tab 的完整刷新判定 | S2-04 以“根视图消失时账号栈为空”视为离开 Tab，下次出现时完整刷新（20 §1.6）；从详情返回不重刷。若以后要求返回也刷新，或改为监听 selectedTab，只改 AccountsView 的 appeared / disappeared |
| 账号写接口 reason 进 ReasonCatalog | CREDENTIAL_KEY_NOT_DELETABLE、ACCOUNT_NOT_IN_FALLBACK、PROXY_FALLBACK_ORIGIN_UNAVAILABLE 现在走 400 / 409 通用兜底文案；页面（S2-10 / S2-11）按 AccountWriteReason 常量给 20 §0.5 的文案。是否要在 ReasonCatalog 补表行，以后再定 |
| DELETE 账号的 ACCOUNT_NOT_FOUND | 核实后端：站长再次 DELETE 已删除的账号返回 200，vendor 越权返回 404 RESOURCE_NOT_FOUND，当前不会返回 ACCOUNT_NOT_FOUND。App 已按规格把 404 ACCOUNT_NOT_FOUND 当已删除，等后端补校验后自然生效 |
| :id/models 不存在时的 404 | 后端用 response.NotFound 返回无 reason 的 JSON 404，App 照抛（kind .notFound）；S2-12 / S2-14 应按 kind 处理，不依赖 reason |
| 错误账号的列表右滑 | 开关关着的错误账号，右滑按 20 §1.4 字面给“启用调度”。打开开关并不清除错误，账号仍不参与调度，回执“已启用调度”可能让人误以为修好了。可改为右滑给“恢复状态…”（打开 AccountRecoverDialog），只需改 AccountActionCopy.swipeAction 一处。需要用户拍板 |
| 账号动作的等待进度 | AccountActions 不订阅 KeyedWriteEvent，带 key 的写最长等待约 35 秒 × 3，期间只靠 isRunning 表示进行中。如果 S2-08 的按钮行要显示“正在确认结果… / 已等待 N 秒”，需要 S2-05 的包装把 onEvent 透传过来，AccountActions 再加一个 confirming 状态 |

### App 与设计 · 阶段 3

| 事项 | 说明 |
|---|---|
| 待核对门控跨站点 id | S3-06（d2dbc57）已完成 Core 与 AppModel 的同地址口径：门控、三类核对、重试权限、checkSender、sameAddressServerIDs、pendingMoneyWrites(sameAddressAs:)。显示与入口还要接入：S1-10 / S1-11 概览、S3-07 设置与用户详情、S6-04 / S6-06 兑换码、S6-09 补偿，最后由 S6-26 逐处复核。这一行可改为“Core 已完成，入口接入见各条” |
| 余额核对的阶段 3 部分 | S3-06（d2dbc57）已完成：候选匹配、多条候选、requestIDUnreliable 与回显检查、旧记录按用户 ID 查询、退路截断时不下结论。核对流程界面由 S3-07 做，提交后的回显检查由 S3-08 做（经 noteRequestIDEcho） |
| 余额重试后的执行宽限 | S3-06（d2dbc57）已完成：lastSentAt 与 graceStart = max(createdAt, lastSentAt)，AppModel.persisted 在重发时自动写入；退路时间窗仍从 createdAt 起算。S3-07 的 retrySameNumber 不用再自己写 lastSentAt |
| requestIDUnreliable 标记的残留与丢失 | 标记按站点 id 存在 UserDefaults。留档站点的标记在它的记录核对完后不会清除（只多几个键）。删掉同地址里唯一被标记的站点后，这个地址的标记就没了，要等下一次余额写回显不一致才会重新标记。以后决定是否在 profileArchive 清理时一并清除，或改为按地址存 |
| 旧记录按用户 ID 查询的截断 | 旧记录的退路查询用 keyword=用户 ID 子串匹配、不带开始时间，可能超过 200 行被截断。截断且没有命中时判 notFound，不下结论；以后可以考虑翻页或加 user_id 筛选（旧服务端会忽略） |
| 删除确认输入框禁止粘贴 | S3-00 按规格允许粘贴（SwiftUI 的 TextField 没有禁止粘贴的接口）；如果用户要禁止，需要换成 UIKit 的 UITextField 子类。待用户拍板（_decisions-S3“需要用户拍板”第 2 条，同时拍板删除确认用 sheet 而不是 alert） |
| 敏感值复制的剪贴板类型真机验证 | SensitivePasteboard 用 UTType.plainText 作键；S3-13 首次接入时在真机把复制的 Key 粘贴到备忘录和 Safari 验证一次，不行就把键换成 UTType.utf8PlainText（只改这一处） |
| AdminUser.balance 坏值整项解码失败 | 30 §1.3 写“余额解码失败显示 —”，但 AdminUser.balance 仍是严格的非可选 Decimal，坏值会让整个用户项解码失败。后端是 float64，实际不会出坏值；S3D1-25 已裁定不放宽。以后要放宽，得同时改 BalanceView、Face ID 门槛计算等所有调用点 |
| users-usage 的 total_actual_cost 是近 30 天 | UserTodayUsage.totalActualCost 的口径是近 30 天，不是本月；详情页的“本月消费”仍走 usage/stats（S3-05）。另外后端给每个请求的 id 都建了条目，“响应里没有这个 id 时显示 $0.00”这条规则基本不会触发 |
| 用户行余额坏值显示“—” | 30 §1.3 右列“解码失败 —”未做：AdminUser.balance 不可缺失，余额坏值会让整页解码失败。由 S3-01 / S3-16 决定是否改为可缺失；UserRow 已按 DisplayFormat.money 的可选值画“—” |
| 头像条待核对读屏按方向写 | 规格原文只写“上一笔充值待核对”，S3-02 按 R02 写“充值 / 退款 / 余额设置”，需确认是否回写规格 |
| 缺失值“—”的读屏（用户列表部分已处理） | BACKLOG 原有一行；用户列表的余额、今日消费、头像余额已统一读“无数据”（DisplayFormat.missingSpoken），其余页面仍待处理，请集成者在原行备注 |

### App 与设计 · 阶段 4

| 事项 | 说明 |
|---|---|
| 使用记录在旧服务端不发 key_view | 没有 api_keys.masked_view 的服务端（早于 2026-10-19）仍会在 admin/usage 响应里下发明文 api_key.key，App 只是不解码；若希望一律发 key_view=masked（旧服务端会忽略），需要为 00 §0 硬规则 8 开一个例外，待用户确认（S4D1 需要拍板第 3 条） |
| errorCount 的口径 | 近 24 小时 N 条一律带 view=all，包含用户自身余额、额度、频率限制，与告警 error_rate 的 SLA 口径不同；S1-17、S2-09、S5-07 的文案只写“近 24 小时 N 条”，不要当作错误率依据 |
| 页面状态注册表只对 AppRoute 推入的页面生效 | PageStateRegistry 按 Tab 的 path 释放状态。视图式 NavigationLink 推入的页面不在 path 里，它登记的状态会在该 Tab 下一次出栈或替换时释放，path 一直不变时留到会话结束。过渡期的旧入口（S4-05 的 LegacyLogsEntry）会这样，S4-20 删掉兼容入口后就没有了。新页面必须经 AppRoute 推入（X39），并一律用 prunedBy 重载登记。 |
| 性能趋势范围上限 31 天 + 1 小时 | S4-10 按 S4D1-10 把 throughput-trend 的本地上限由 40 §2.7 字面的 30 天放宽为 31 天 + 1 小时（PerformanceTrend.maximumSpan），以覆盖“上月”与夏令时；后端没有上限。待用户确认，S4-18 平均账号切换超限时的卡内提示按这个常量走。 |
| 删除 PerformanceTrend 的 Decodable 与 init(from:) | S4-10 按 X29 没改 APIClient.swift，只为旧的 dashboardPerformanceTrend(start:end:) 保留 Decodable 和按点列推窗口的 init(from:)；S1-09b 删除旧方法时同一提交删掉（S1D1-18），漏掉的话由 S4-20 收口。 |
| 请求详情退路：客户端已成功但查不到成功记录 | 已恢复样子走退路时，如果用 client:<client_request_id> 查不到成功那次，fallbackRows 只有失败尝试，最后一次的副行会写“失败，错误返回客户端”，与客户端实际拿到 200 矛盾。S4-08 需要决定此时的写法（例如不显示该副行，或改写成“失败，后续尝试未记录”），规格没有对应文案 |
| 退路尝试行的账号名 | failover 事件常常没有 account_name，退路行的标题会显示“#<id>”。可以借用同 id 的其他事件或成功记录里的名字，需要时再加 |
| 请求详情日期格式归属 | 副标题“M/d HH:mm:ss”和已处理小字“M/d HH:mm”目前是 RequestDetailPresentation 的私有函数。按 R10，若 S4-04 或其他页面也需要“月/日 时刻”格式，应统一放进 DisplayFormat，并确定月日是否补零 |

### App 与设计 · 阶段 5

| 事项 | 说明 |
|---|---|
| AccountsView 手写 composite 过滤改用 GroupPlatform.concrete | AccountsView.swift 约 220 行还自己写了 values.filter { $0 != "composite" }，不在 S5-01 的文件范围内；留给后续改 AccountsView 的条目，或 S5-13 收口时统一 grep 替换 |

### App 与设计 · 阶段 6

| 事项 | 说明 |
|---|---|
| 让其他设备下线可能连本机一起下线 | 已由 S6-01 处理：登录设备页“让其他所有设备下线”后重载列表，本机是部署前签发、没有 sid 的旧会话时，重载收到 401 TOKEN_REVOKED 回到登录页；SessionsUITests.testRevokingAllWithLegacySessionSignsThisDeviceOut 覆盖。集成者可把原行改为已处理 |
| 撤销登录设备时本机被下线的提示文案 | 60 §5.4 只写“按本机退出处理”，没给文案。S6-01 改为调 forgetActiveSession，登录页显示“本机已下线，请重新登录。”（新定）；本机行不给滑动（U50），这条路径实际很少出现。待用户确认文案，或改回 logout |
| 00 §1.8 与 60 §5 的登录设备文案不一致 | 00 §1.8 写“设备名为空时显示 client_type”“其他设备会立即退出登录”，与 60 §5 的 UA 规则和确认框文案冲突，“立即”也与 00 §1.7.3 的 fail-open 矛盾。S6-01 按 60 §5 实现；建议规格维护时把 00 §1.8 改为引用 60 §5 |
| 用户列表刷新后残留已删除的边界行 | S3-02 审查修正后，已加载到第 2 页及以后时，刷新第 1 页会保留“新第 1 页仍含有的最后一行”之后的旧行。如果同一轮里既有顶部新增、又有边界附近的行在别处被删除，被删的行会留在列表里，直到换搜索词或换会话；这和 30 §1.6“第 2 页以后不自动刷新”带来的后续页陈旧属于同一类问题。以后若要精确处理，需要按 offset 重读已加载的各页，或改用游标分页。 |
| 推送本机开关在设备停用时显示为关 | 60 §7.3 规定开关按“id 存在且 enabled”显示，所以设备被停用（unregistered / secret_undecryptable）时开关是关的，但状态行写“关掉再打开即可恢复”。S6-22 按字面实现（PushLocalState.isToggleOn 只有 .on），S6-24 实现页面时若觉得别扭，可改为停用时开关保持开、文案改为“重新打开即可恢复”。 |
| 推送订阅整体 PUT 会丢掉 App 不认识的事件 | PushSubscription 解码时丢弃未知事件，整体 PUT 时，服务端以后新增的可订阅事件会被一并去掉。现在后端只有 4 个可订阅事件、未知事件 PUT 也会被拒，暂可接受；后端扩充事件时要同步扩 PushEvent。 |
| 吊销本机令牌失败后的推送设备 | 吊销本机令牌时会先删除本站点推送设备，再发 DELETE。若 DELETE 失败，会话继续，但本机已登记的推送设备已被清空。S6-23 的重新登记要覆盖“会话进行中、登记记录被清空”这种情况，不能只在下次登录时补登。 |
| “刷新失败 · 重试”横幅收口 | SessionsView 和 AccessTokensView 各自写了一份“刷新失败 · 重试 / 更新于 HH:mm”横幅（00 §4.6），文案常量也重复。S6-26 可以合并成一个共用组件。 |
