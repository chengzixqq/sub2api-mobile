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
| 缺失值“—”的读屏 | 替换 App 与设计表中“缺失值“—”的读屏”原行：默认读“无数据”（S1-00 定）。Sources/Sub2Core/DisplayFormat.swift 的 DisplayFormat.missingSpoken 与 DisplayFormat.spoken(_:) 只做整值替换；各页重写时 accessibilityValue 套用，尚未重写的旧页面仍读显示文字。 S3-02（2fba3df）已处理用户列表：余额、今日消费、头像余额读“无数据”，见阶段 3 表同名行。 S2-09（cfc6947）已处理账号详情三节：容量“— / y”读“无数据 / y”，今日各项与记录区的“—”读“无数据”，首次加载读“正在加载”，见阶段 2 表同名行。 |
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
| 旧服务端事件缺 group_name | （补充已有行说明末尾）S1-07 已在收事件处补规则与分组名（会话内各取一次） |
| 首页退路本地分档的边界 | 站点既没有 dashboard.home 也没有 accounts.status_summary 时：账号只取第一页 1000 个，totals 偏小并标 accounts_truncated；按告警规则判定 shortage 的分组退回默认 0.5 判定，可能与服务端不同；是否分页拉全待定 |
| 首页退路的告警 500 条上限 | 没有 ops.alert_event_counts 时 firing 超过 500 条只显示 500，没有“≥”标记；是否要加待定 |
| 首页退路的渠道 UNSUPPORTED 显示 | 比渠道监控更早的站点，channels 段为 disabled(UNSUPPORTED)；S1-09b 决定运行区写“渠道监控未开启”还是隐藏该行 |
| 没有 /admin/me 的旧站点不能在 App 里开启运维监控 | 2026-07-25（0b5903d45）之前的服务端把 PUT admin/settings 当整份文档，只带 ops_monitoring_enabled 会清空注册开关、SMTP、验证码等设置；App 拿不到 /admin/me 时无法判断版本，所以 OpsDisabledNotice 在这类站点不显示开启按钮（标题仍是“运维监控未开启”），与 10 §7.2“读不到 → 「开启运维监控」”不同（S1D1-07、S1-08）。请用户确认 |
| 关闭运维监控两步确认的文案 | S1-08 的 opsDisableConfirmation 先用动作表“关闭运维监控？”（正文写明错误率、告警、监控各段不可用，关闭期间的数据不会补回，按钮「关闭运维监控」），再弹“确认关闭「站点名」的运维监控？ / 这会关闭整个站点的运维监控，对所有管理员生效。 / 「仍要关闭」”。规格只说“二次确认”，没给文案，等 S1-13 接入后请用户看效果图再定 |
| config_off 时首页提示行是否补“RPM 只计成功请求” | 10 §1.3.1 规定 config_off 整句换成“运维监控已在服务器配置中关闭”，这样就没有 U12 要求的 RPM 口径说明；S1-08 按字面实现，退路③时末尾仍接“ · TPM 不含缓存 Tokens”。是否也补 RPM 说明，请用户在 S1-09 截图时决定（只改 OpsDisabledPresentation.inlineText 一处） |
| UI 测试 6 并发下的快照停顿 | （补充已有行）S1-09 删除 testDashboardSlowTrendDoesNotDelayCountersOrMonitoring，慢趋势夹具的用例退役；新首页用例只按元素状态等待，不依赖时间窗。趋势缩放用例已迁到 LegacyTrendUITests，阶段 4 随过渡页一起退役 |
| 利润亏损的固定演示状态 | （补充已有行）首页部分由 LiveOpsFixtures 的 -ui-home-loss 兑现（S1-09，利润 −$115.50，HomeUITests.testLossFixtureShowsNegativeProfit）；统计分析的负值柱留给 S4-13b |
| 路由参数在旧页面上不生效 | （补充已有行）.analytics 的 focus / metric 已在 S1-09 的过渡页 LegacyTrendPage 生效（默认显示性能页，并按 metric 预选 RPM / TPM）；range 仍未生效，留给 S4-12 / S4-13 |
| AppModel 里随旧概览失去用途的夹具分支 | -ui-dashboard-slow-trend、-ui-missing-account-cost、-ui-cost-snapshot-error 在 S1-09 后已没有 UI 用例引用（-ui-trend-long-series、-ui-dashboard-detail-errors、-ui-performance-error 仍被 LegacyTrendUITests 或过渡页使用）；S1-09b 删旧包装时一并删除，S1-18 收口时 grep 核对 |
| 账号角标的 dashboard/stats 退路 | AppModel.dashboard() 只剩 AppModel+Accounts.accountErrorCount() 一个调用方（没有 accounts.status_summary 的站点取账号角标数），S1-09b 因此没有删除它。以后可以把这条退路移进账号段自己的包装，再删 AppModel 概览段的 dashboard() 和 DemoData.dashboard.stats |
| 运行区渠道“更新失败”的写法 | 首页渠道行有旧值但刷新失败时，S1-09b 保留摘要，并在行内用灰字写“更新失败”（不可点，重试靠下次轮询或下拉刷新）。规格没写，等看模拟器截图再定是否改成区块头附件 |
| 夹具 #35 与 24h“最近结束”的时段依赖 | S1-06 让 FixtureAlertBook 按 time_range 过滤（fired_at ∈ [base − 24h, base)，base 为会话开始时的服务器时间）。S1D1-11 冻结的 #35 在“昨天 21:52”（Asia/Shanghai）触发，所以服务器时间 21:52 以后开始的会话，24h 列表里没有 #35（它是唯一的 manual_resolved）。S1-16 的 MonitorUITests（最近结束两区与 meta）以及 base 取当前时间的单测（如 defaultFixtureHasEndedEvents）如果依赖 #35，会在每天 21:52–24:00 固定失败。请 S1-16 或编排者三选一：改 #35 为相对 base 的时间（要改 S1D1-11）；给 UI 测试加固定夹具时钟的启动参数；或让断言不依赖 #35。 |
| 首页轮询重启后第一拍被跳过（残余） | LiveOpsStore.pollHomeBlocks 第一拍遇到 isHomeLoading 为真时跳过，并按 nextHomeDelay 等 60 秒。一次被取消的在途读取也算在途：LoadState 的 onCancel 只取消内层 Task，状态要等退栈后才回到 idle；退路的 fallbackCycle 和今日 SLA 的 todayOps.isLoading 也一样。S1-09 审查修正已经去掉概览 task 的多余重启（合规确认、foregroundRevision），只剩一种情况：在途读取期间可见性极短地抖动（Tab 切走马上切回、控制中心一拉一放），首页仍可能晚一个周期刷新。要彻底修，需要让 LoadState 识别“已被取消的在途读取”（task.isCancelled），并同时覆盖退路轮次和今日 SLA。 |
| 概览「测试」关闭即刷新与后台测试 | S1-10 在「测试」sheet 关闭（或被替换）时对首页 nocache 刷新一次；S2-14 / S2-23 如果让测试在后台继续，测试结束时要再调 model.liveOps?.noteExternalWrite()，否则拿不到自动恢复后的状态（S1D1-28 已移交 S2-23） |
| 平静布局的滞后规则 | 过载或限流在相邻两次轮询之间反复变化时，概览会在常规和平静之间来回切换。规格没有滞后要求，S1-11 未加；如果实际使用中感到闪烁，可以加“连续 N 次满足才进入平静”。 |
| 平静布局排行失败时是否保留旧值 | S1-11 按 10 §2.6 处理：排行刷新失败就隐藏“按账号”区，直到下一次成功，代价是瞬时失败时该区会消失一个轮询周期。若更希望按 00 §0.5 保留旧值，只需改 HomePresentation.calmRanking 一处。 |
| 待核对文件读不出时不阻止平静布局 | pendingPersistenceAvailable == false 时记录列表为空，概览仍可能进入平静布局。资金写入口由 moneyWriteGate 的 unavailable 拦截，设置页有暂停提示。若要保守处理（读不出就不平静），再改 HomeView 的 isCalm 入参。 |
| 告警详情“分组已删除”的误判 | status-summary 的 groups[] 不含“停用且没有账号”的分组（account_status_summary_repo.go:86-105），告警详情只在 status-summary?group_id 成功且没有该组时判为已删除，这种分组仍会显示“分组已删除”、不可点；待后端在汇总里带回指定 group_id 的分组后改判。 |
| 告警详情的分组名来源 | 分组名优先用事件的 group_name；旧服务端没有时用 S1-07 收事件处从 groups/all 补的名字，再没有就用 status-summary 汇总的 group_name，都没有写“分组 #id”。详情页不另拉 groups/all。 |
| 监控分段计数的读屏 | 系统分段控件没有角标，S1-13 把计数写进段标题（“告警 2”），读屏会读“告警 2”；如果要读成“告警，2 条进行中”，需要自绘分段控件 |
| 监控 Tab 的 vendor 分支不可达 | 首版不允许 vendor 登录（U01），“代运营工作区没有运维监控权限”只是防御分支，没有 UI 夹具和用例；开放 vendor 登录时再补 |
| 首页与监控的健康分行合并 | 监控概况的健康分行（MonitorOverviewSection 私有 MonitorHealthRow）和首页 HomeRunSection 的私有健康分行版式一致、各写一份，由 S1-18 收口时合成一个行组件 |
| S2-09 的 CapacityBar 合入后统一监控 CPU / 内存条 | S1-14 在 MonitorServerSection.swift 里用的是私有 MeterBar；S2-09 的通用 CapacityBar（C-7）合入后，评估改用它，避免两套容量条 |
| S1-18 的标识静态核查要接受插值后缀 | S1-14 的读数标识带色调后缀（monitor.server.cpu.<normal\|caution\|critical>），任务行标识带任务名后缀（monitor.server.job.<job_name>）；按字面量 grep 的核查要能识别这类前缀 |
| 后端：/admin/me 布尔功能开关读不到时省略字段 | me_handler.go 在读设置失败时把 features.channel_monitor_enabled 写成 Go 零值 false（无 omitempty），App 按规格直接显示“渠道监控未开启”且不发请求，出现假阴性（回前台重新探测后恢复）。建议后端改为 *bool + omitempty，App 已按 nil = 未知处理（照常请求、靠 403 判定） |
| 渠道四格计数为 0 时的色调 | S1-15 按规格四档各用色调，但计数为 0 时不着色；设计稿只给性能下降 / 不可用的数字上色。要改只改 ChannelSectionPresentation.countCells 的 tone |
| 渠道行状态图标与账号状态图标统一 | S1-15 的 ChannelGlyph（ChannelsSection.swift 私有）与账号行 AccountStateGlyph、代理行 ProxyGlyphView 写法相同但各自一份；S1-18 或阶段 2 收口时评估是否抽成共用组件 |
| 渠道行点进旧分组详情 | S5-06 之前 .group(id:) 落到旧 GroupDestination，-ui-testing 下旧分组夹具只有 id 10 / 11，渠道夹具按 DEMO.groups 取 id 1–10，点其他行会进入“加载失败”的旧详情；S5-06 换页后自然解决，S1-15 的 UI 用例只点 id 10 |
| 渠道监控“站点不支持”文案统一 | 旧站点没有 channel-monitor-v2 路由时（非 JSON 404），首页退路（S1-07，HomeFallback.outcome(unsupportedAsDisabled: true)）显示“渠道监控未开启”，告警详情平台行只认 403 CHANNEL_MONITOR_DISABLED；监控 · 渠道段（S1-15 审查修正）按 00 §3.3 显示“站点版本较旧，暂不支持此功能”并本会话停读。是否让首页渠道行、告警详情平台行共用同一个不支持态与文案，由用户决定。 |
| Mac Xcode 升到 27.2 | 2026-10-31 00:07 起，check 报 TOOLCHAIN_EXIT=3（Toolchain.json 固定 27.1 / 27A9275），UI 测试报 UI_UNAVAILABLE（CoreSimulator 过旧）。需要用户决定回退 Xcode 还是更新固定版本，并在 Mac 上执行 sudo xcodebuild -runFirstLaunch；之后补跑 S1-16 的 check 与 UI 测试（S1-16 检查时发现）。 |
| 最近结束按结束时间筛选 | 后端 alert-events 的 time_range 按 fired_at 过滤，触发早于 24 小时、最近才结束的事件（例如持续两天、刚被手动解决的告警）不会出现在“最近结束”。需要后端支持按 resolved_at 范围筛选；App 暂按规格用 time_range=24h（S1-16）。 |
| 最近结束轮询合并的已知限制 | 轮询与写后只合并第一页：触发时间早于第一页、之后才结束的事件，要等下拉刷新才出现；24 小时窗口滑动后，已加载的旧行保留到下次下拉（S1-16）。 |
| 告警列表游标类 400 没有 reason | before_fired_at / before_id / limit 校验失败都走 response.BadRequest，reason 为空，App 只能把「加载更早」收到的无 reason 400 一律视为游标被拒并重拉第一页。建议后端给这类错误加稳定 reason（S1-16）。 |
| 告警详情“近 24 小时 N 条”的口径 | 按日志页口径计数：errorCount 沿用 view=all，含业务限制、含 429 / 529 和已恢复的上游错误，条数与点进去的日志页一致。它不是告警指标的分子：error_rate 排除业务限制，upstream_error_rate 排除 429 / 529。界面不解释这个差异（S1-17）。 |
| 平台告警的错误计数行 | 只有 platform 的错误类告警（如 Anthropic 上游错误率）不显示“近 24 小时 N 条”：规格没有这一行，RequestLogFilter 和 LogsRoute 也没有平台条件。要加的话，先给 40 章的筛选与路由加上平台条件（S1-17）。 |
| S4-05 同步告警详情的日志页断言 | AlertDetailUITests.assertErrorLogsOpened 现在断言的是旧页“请求与错误日志”、logs.mode 选中“失败请求”和“分组 #<id>”。S4-05 换成 LogsView 时要一并改这个 helper，否则 S1-17 的两个 UI 用例会失败（S1D1-28）。 |
| 长超时读请求超时后的自动重试 | （补充已有行）S1-18 未实测：未获授权访问测试环境（S1D1-27）。U54 维持默认值：客户端超时 dashboard/home 15 秒、统计聚合 45 秒、dashboard/stats 90 秒；后端 dashboard/home 有 8 秒整体预算（各段 3–6 秒），段内超时只把该段标 timeout。统计聚合与 dashboard/stats 超时后是否还自动重试，仍等生产量级实测（后端 B10 / 维护者 Q17） |
| 真机确认 ETag 304 | （补充已有行）S1-18 未实测：未获授权访问测试环境。dashboard/home 走 ConditionalCache（S1-01），URLSession 层的 304 透传仍只有桩测试；账号列表的 304 由 S2-23 确认，真机仍待验 |
| UI 测试 6 并发下的快照停顿 | （补充已有行）S1-18 删除了 AppModel 里残留的 -ui-dashboard-slow-trend 分支；趋势缩放用例随 LegacyTrendUITests 在阶段 4 删除 |
| 缺失值“—”的读屏 | （补充已有行）阶段 1 已统一：概览、监控、告警详情的读屏值经 DisplayFormat.spoken 输出“无数据”（StageOneFixtureUITests 的运维关闭夹具断言 home.today.successRate、home.run.health 读“无数据”）；其余页面重写时套用（X33） |
| 区块 429 倒计时文案与重试按钮 | （补充已有行）阶段 1 的区块都用 S1-08 的 BlockFailureRow / BlockStatusAccessory：显示倒计时、等待期内禁用重试、到时自动重发；账号详情今日节由 S2-23 统一（X37） |
| 有待核对记录的站点重新登录会多出一个同名站点 | （补充已有行）概览已按同一规范化地址合并显示旧站点 id 的记录，加注“本站点的旧登录下发起”并计入平静判定（S1-10 / S1-11，X34）；S1-18 补了 UI 用例 HomeUITests.testEarlierLoginRowsAreAnnotatedAndOpenTheirPages；设置页由 S3-07 处理 |
| 资金写待核对的界面与回前台自动核对 | （补充已有行）概览部分已完成：S1-10 的三类待核对行、S1-11 的平静判定，S1-18 补了补偿行与本站点旧登录行的 UI 用例（补偿行点按打开 S6-09 的补偿待核对 sheet，关闭后记录不变） |
| 读区块的“完成合规确认”入口 | （补充已有行）阶段 1 已处理：S1-08 的 BlockFailureRow 在 423 时显示「完成合规确认」并调 AppModel.presentCompliance()，阶段 1 的区块都用它；合规通过后概览立即重读（e8dfe42）；其他阶段的区块接入时复用 |
| 路由参数在旧页面上不生效 | （补充已有行）阶段 1 部分：.monitor(segment:)、.alert(id:) 已生效；.analytics 的 focus / metric 由过渡页 LegacyTrendPage 生效，range 仍不生效（S4-12 / S4-13）；概览与监控的其余去向都是新页面 |
| 跨 Tab 跳转撤不掉视图式推入的页面 | （补充已有行）阶段 1 部分已处理：grep Features/Home、Features/Monitor 与过渡页 LegacyTrendPage，没有 NavigationLink { 目的视图 }、NavigationLink(destination:)、navigationDestination(isPresented:) / (item:)，一律走 HomeDestinationAction 或 router.push / select / present；其他页面由各阶段收口条目核对（X39） |
| AppModel 里随旧概览失去用途的夹具分支 | （补充已有行）S1-18 已删除 -ui-dashboard-slow-trend；-ui-missing-account-cost、-ui-cost-snapshot-error 已由 S1-09b 删除，全仓 0 处；-ui-trend-long-series、-ui-dashboard-detail-errors 仍给 LegacyTrendUITests，-ui-performance-error 没有 UI 用例（PerformanceTrendView 的失败夹具），三者随 S4-13 / S4-16 删除 |
| 首页与监控的健康分行合并 | （补充已有行）S1-18 未合并（方案 out_of_scope）：两处已共用 HealthScoreBar 与 HomeRunPresentation.Health（MonitorTabPresentation.health 返回同一类型），剩下的只是各自的行布局与标识（home.run.health / monitor.run.health）；合并要同时动 HomeUITests、MonitorUITests、StageOneFixtureUITests 的断言，留给设计复核或阶段收尾统一处理 |
| S1-18 的标识静态核查要接受插值后缀 | （补充已有行）S1-18 的一次性核查脚本已按前缀识别插值与拼接（"\(id).retry"、"x." + kind、monitor.server.cpu.<色调>、monitor.server.job.<任务名>）：UITests 902 个标识中只有 24 个找不到字面量，都是 capability 名、邮箱 / 模型名片段或其他阶段的键盘与菜单前缀，阶段 1 的首页与监控标识全部能找到。脚本不入库（scratch/s1-18/check_stage1.py），阶段收尾要入库时可参考 |
| 渠道行状态图标与账号状态图标统一 | （补充已有行）S1-18 未抽：ChannelGlyph 只在渠道段一处使用，抽共用组件要动阶段 2 的 AccountStateGlyph 与阶段 6 的 ProxyGlyphView，留给 S2-23 收口时评估 |
| 首页夹具与账号 Tab 演示数据不一致 | （补充已有行）S1-18 核对：情况未变，只影响 UI 测试与截图；StageOneFixtureUITests 只断言首页 / 监控自身的元素，不跨 Tab 比对 |
| 概览待处理账号行是否复用 AccountActions | 20 §5.1 写“概览复用”，10 §1.3.3 只给错误行定义了「测试」。阶段 1 默认不做（dag.md 第 8 节第 2 条），处理动作放在账号详情；如要加左滑「恢复状态」/「停止调度」，在 S2-06 与 S1-10 合入后另立约 1.5 小时的小条目（线 A） |
| 阶段 1 过渡页与旧趋势代码的删除 | LegacyTrendPage（含 DashboardTrendChart / AnimatedTrendViewport）、LegacyTrendUITests 与 .analytics 的 focus 分流由 S4-13 删除；PerformanceTrendView 抽 PerfTrendBody、删除 AppModel.dashboardPerformanceTrend(hours:) 由 S4-16 做。在此之前 AppModel 的 -ui-trend-long-series / -ui-dashboard-detail-errors / -ui-performance-error 分支保留（X20）。DashboardTrendMetric.actualCost 的文案已是“实际扣费”，不用再改 |
| 首页可用性退路与 status-summary 的口径差异 | 只影响没有 dashboard.home 的旧站点（S1-07）。有 accounts.status_summary 时用 status-summary（include_accounts）按首页口径裁剪；没有时用 groups/all 的计数加 lite 账号列表本地分档（AccountDisplayState）。账号超过 1000 个时只取第一页并标 accountsTruncated；分组可用不足按后端默认比例 0.5 判定，与服务端按告警规则判定的口径可能不同；status-summary 缺 accounts / shortage 等字段（旧版本）时只给汇总、不出账号行。等真实旧站点有反馈再定 |
| 运行区健康分在 config_off 时的措辞 | disabled_reason 为 config_off 时，6 格下方的提示行写“运维监控已在服务器配置中关闭”，运行区健康分仍写“运维监控未开启”（S1-09b 按规格原文）。两种原因都是“未开启”的事实；要统一只改 HomeRunPresentation 一处，等用户看过截图再定 |
| 阶段 1 需用户确认的默认值 | 没有 /admin/me 的旧服务端不提供开启运维监控入口；事件没有 silence 键的旧服务端不提供静默（S1D1-15）；旧服务端告警行补规则名与分组名的做法（S1D1-16）；是否授权在测试环境实测 U54 与 dashboard/home 的 304（S1D1-27）。均已按默认实现 |
| AccountOAuthTests 计时用例在高负载下偶发失败 | Tests/Sub2CoreTests/AccountOAuthTests.swift:85 的 authURLReplyKeepsStateAndRejectsUnsafeLinks 断言授权链接剩余时间 > 1799 秒，只有 1 秒窗口。Mac 上 3 个检查并行时，S1-18 的 check 与一次 unit 重跑都因此报 UNIT_EXIT=1，再重跑通过。建议归属条目把断言放宽（例如 > 1790 秒）或注入时钟 |

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
| 批量调度“稍后核对” | 带 key 的 bulk-update 最坏要等约 3–4 分钟（65 秒 × 3 次 + 退避 + IN_PROGRESS 最多 30 秒），期间坞锁定、“完成”不可点，坞左侧显示“正在确认结果…”。是否加“稍后核对”（放弃等待、直接 runtime/batch 读回），对应 D31，待定 |
| 批量撤销依据的操作前状态 | 撤销用列表快照里的 schedulable 判断哪些账号真正被改动；选择模式期间轻刷新暂停，快照可能已过时。规格没要求执行前再读一次 runtime，本条没加 |
| 批量选择数量不设上限 | 规格只限每次请求 50 个；全选 2000 行会变成 40 次顺序请求，期间坞一直显示进度。是否要上限或提示，待定 |
| S2-23 首页刷新接入点 | 批量有成功时让首页刷新（model.liveOps?.noteExternalWrite()）要加在 NativeApp/Features/Accounts/AccountBatchRunner.swift 的 run / undo 里，不是 items.json 写的 AccountBatchDock.swift，请集成者告知 S2-23 |
| 到期自动暂停账号的详情主按钮 | S2D1-20 默认“修改过期时间…”，与 20 §2.3 字面的“启用调度”不同；S2-08 暂时打开旧编辑页，S2-10 改为 beginEdit(.sched)。用户若要照字面，只改 AccountDetailPresentation.actionRow 和 AccountActionCopy.swipeAction 两处 |
| 账号详情错误态牌旁的原因 | 按 spec_issues 写“上游 {error_status_code}”，没有时不写；设计稿是 a.cause 或“上游返回错误”。等用户看过效果图再定 |
| 详情里写操作后返回列表的即时刷新 | 列表回到可见时不立刻轻刷新，在详情里停止 / 启用调度后返回列表，最多 60 秒内仍显示旧状态；交 S2-23 收口（noteExternalWrite，或列表 setVisible(true) 时按 marks 补一次轻刷新） |
| 分组页旧夹具与账号夹具的分组 id 不一致 | GroupsView 旧夹具的分组 10、11 在 AccountDemoStore 里没有成员，S2-08 加了 -ui-account-group-transition 让账号 4、7 归入分组 10，供过渡入口用例使用；S5-04 / S5-13 重写分组页、删除过渡入口时一并删掉这个参数和对应用例 |
| 按 id 进入账号详情的 UI 用例路径 | AccountDetailUITests 里两个按 id 进入的用例走旧 RequestLogsView 的“查看账号”视图式链接；S4-05 / S4-08 重写日志页后要改路径（入口应 push .account(id:)） |
| 区块 429 倒计时（账号详情今日已处理） | S2-09 的账号详情今日节已显示“请求过于频繁，N 秒后自动重试”，等待期间重试置灰，到时自动重发一次。用的是自建小块 AccountTodayStatusLine / todayStatusLine，与 BlockFailureRow 的“加载失败”文案不同。S2-23 换成 BlockFailureRow 时删掉这块，并更新原来那行 BACKLOG 的账号部分 |
| 缺失值读屏（账号详情三节已处理） | 容量“— / y”读成“无数据 / y”，今日各项和记录区右侧的“—”读成“无数据”，首次加载时读“正在加载”。请集成者在原来的“缺失值读屏”行加备注 |
| 运维关闭后上游错误计数的恢复 | 账号详情遇到 404 OPS_DISABLED 后，60 秒轻刷新不再请求上游错误。在 Web 开启运维监控后，要下拉刷新、回前台或重新进入详情才会显示计数。如果要自动恢复，可以改成每 N 分钟再试一次 |
| 账号详情 UI 测试对旧日志页与占位页的断言 | 两个用例断言旧 RequestLogsView 的 logs.mode / logs.account-filter：testRecordsRowsOpenLogsFilteredByAccount、testOpsDisabledShowsNoticeRowAndErroredAtLine；testErrorAccountLatestUpstreamErrorOpensRequestRoute 断言 route.placeholder。S4-05 / S4-08 重写日志页和请求详情时要同步改这几处 |
| 日志页旧夹具与账号详情上游错误计数不一致 | RequestLogsView 私有的 LogFixtures 里账号 1 有 1 条错误、账号 7 没有；AccountDemoStore.upstreamErrorPage 给 #1 0 条、#7 3 条。S4-05 重写日志页夹具时按 AccountDemoStore 统一，让“近 24 小时 N 条”与点进去看到的列表一致 |
| 测试输出脱敏规则是否扩展 | 现只覆盖规格列的 Bearer、sk-…、URL（20 §4.3）；x-api-key 原值、JWT、sat_ 令牌、AKIA… 不在规则内。后端 error_message 已做 logredact，残留风险低（S2-13） |
| Bedrock / Vertex 账号 401 的失败原因文案 | 暂按 20 §7.3 写“API Key 无效或已撤销”，措辞不准确，待用户看效果图后再定（S2-13） |
| 老服务端测试结果比对的精度 | AccountTestOutcome.legacy 用 error_summary / error_kind 判断错误是否被改写，App 的快照里没有 error_message / error_at；清除限流按测试前限流或临时不可调度有效、测试后没有来判断（S2-13） |
| 保存遇到 GROUP_NOT_FOUND 时刷新分组目录 | S2-10 的分区 sheet 遇到 404 GROUP_NOT_FOUND 只显示目录文案“对象不存在或已删除”，不进已删除页，但没有自动调用 GroupDirectory.refresh()，分组页要等下次刷新才去掉已删除的分组；需要的话让 AccountPatchFlow 在 failed 里带上 reason，sheet 据此刷新 |
| 密钥账号详情暂时没有 ⋯ 菜单 | S2-10 删掉过渡的“编辑账号”后，⋯ 只剩令牌账号的“刷新令牌”，密钥账号暂不显示 ⋯；S2-11（在 Web 中编辑、删除账号…）和 S2-16（更换 API Key…）加项时恢复，并按 20 §3.4 的顺序排 |
| 账号删除“先 pop 再回执”的顺序 | 现在是回执在确认框关闭前出现、确认框关闭后再 pop（和公告删除一致）。如果要严格按规格先 pop 再回执，需要让 S3-00 的 DeleteConfirmationSheet 在 perform 结束后把关闭交给调用方，各章删除一起改 |
| 账号删除确认框的后果行 | 后端删除账号会级联删除 spark 影子账号和定时测试计划；设计稿没有后果行，目前不写。等 DTO 给出影子数量后再考虑加“影子账号一并删除” |
| 停用代理副行写法 | 规格写到期词（“MM/DD 到期 / 永不过期”），设计稿写“已停用”。用户看效果图后如果要“已停用”，只改 AccountProxyPresentation 的 row |
| 其余详情写操作的列表完整刷新 | S2-06 的状态动作、S2-10 的保存、凭据写入还没有 bump AccountListSignal（本条只接了删除、恢复原代理、换代理），由 S2-23 收口时统一接上 |
| .proxyDetail 占位断言 | S6-12 换上正式代理详情页后，要改 AccountDetailMenuUITests 里 testProxyRowOpensProxyDetail 与 testRevertOriginUnavailableOffersOriginDetail 对 route.placeholder 的断言 |
| 账号模型分区空映射的文案 | Antigravity / Grok / Gemini Google One / OpenAI OAuth / DeepSeek 在映射为空时，后端实际按平台默认列表调度（service/account.go resolveModelMapping / IsModelSupported）；App 照规格写“支持所有模型”“未限制”。是否改成“按平台默认模型”待用户看图决定（S2-12） |
| 多协议账号切换账号类型 / API 协议时联动接入端点 | 规格只写改 account_mode / api_protocol；App 照 Web EditAccountModal，在端点为官方预设或缺省时一并改写 base_url / api_base_urls / protocol_rules；自定义端点时两行只读并加脚注“这个账号用的是自定义接入端点，账号类型和 API 协议请在 Web 中修改。”（新文案，待用户看效果图；S2-12） |
| MetaCatalog 补解码 multi_protocol.routing | S2-12 用“任一模式有 protocol_rules”判断按模型分流（与当前目录一致：opencode_go、command_code）；将来出现没有规则的 by_model 平台会误判，影响未设置 api_protocol 时显示“Chat Completions”还是“自适应”，建议由 S2-02 的目录解码补上 routing |
| 高级分区：倍率同步开启时探测行的提示 | 账号开着“按上游声明倍率同步账号计费倍率”时，关闭“自动探测上游声明倍率”会让后端连同步一起关掉（撤销可以恢复）。规格的副文案“只探测，不改账号计费倍率”没有提到这一点。是否在同步开启时给探测行加一句提示（例如“关闭后倍率同步也会关闭”），等用户定。 |
| 中断回执是否带账号名 | 20 §4.4 的回执“测试被中断，不能判定是否成功”照抄规格，不带账号名；多个账号同时在后台测试时分不清是哪个被中断（点“重新测试”针对的是该任务的账号）。是否改为“「{name}」测试被中断，不能判定是否成功”待定（S2-14） |
| ACCOUNT_TEST_BUSY 的按钮倒计时文案 | 后端对 ACCOUNT_TEST_BUSY 不写 Retry-After，按 00 §2.7.2 默认 30 秒；按钮文案“N 秒后重新测试”和置灰到点为止的做法是 S2-14 定的，规格没给，待设计确认 |
| AccountDetailUITests.testBasicAndScheduleSectionsShowReadOnlyValues 不稳定 | 用例用字典遍历 6 个调度行，Swift 字典顺序每次进程随机，而 reveal 只向下滚，靠上的行排到后面时滚不回去，失败在第 325 行；集成 gate 0fc3f65 记为 FLAKY，S2-14 check 中两次都失败，单独重跑通过。应改为有序的数组遍历（测试文件归 S2-10，S2-14 未改） |
| items.json 补登记 S2-14 的文件外改动 | S2-14 新建了 NativeApp/Session/DemoData+AccountTests.swift（DemoData+Accounts.swift 已有 703 行，放不下），并在 Package.swift 的 NativeSessionSupport exclude 阶段 2 段加了一行；这两个文件都不在条目 files 里，请补进 items.json 并重跑 build.py |
| 后端：Claude / Gemini / Antigravity 换码网络失败缺 reason | 新建账号换码时，Claude 的上游失败是不带 reason 的 500，Gemini / Antigravity 是不带 reason 的 400（oauth_exchange_error.go），App 分不出“授权码还没用掉 · 换个代理再试”，目前退回通用文案；建议后端给这三个平台补上和 OPENAI_OAUTH_TOKEN_EXCHANGE_FAILED 同类的 reason |
| reauthorize / exchange-code / apply 的 30 秒超时 | 按 00 §2.3 保持不带 key 的写 30 秒；后端换码上限 2 分钟、保存 30 秒，上游慢时会先超时、落到“不能确认是否已替换”。建议实测后再决定是否放宽（S2D1-03） |
| items.json files 补登记 | S2-15 实际新增了 OAuthCredentialBuilder.swift、AccountOAuthErrorCopy.swift、OAuthCredentialBuilderTests.swift、AccountOAuthErrorCopyTests.swift（方案已列出拆分），需要补进 items.json 的 files 并重跑 build.py |
| 没有幂等能力时“用同一编号重试”实际是新的创建 | 站点没有 admin.idempotent_writes 时没有 key，核对没找到后的重试是一次新的 POST；如果第一次其实在核对之后才落库，会建出第二个账号。建议 S2-19 在没有 key 时把按钮改成“重新创建”并保留核对说明，文案待用户确认 |
| 创建后换认证方式，旧密钥会留在服务端 | PATCH 不能删除敏感凭据键（CREDENTIAL_KEY_NOT_DELETABLE），PUT 也保留旧敏感键，所以换方式做不到字面上的“替换原来的凭据”（旧密钥对新类型不起作用，且始终脱敏）；建议后端提供换类型时整份替换凭据的方式 |
| 多协议端点预设表（MiniMax Intl 等） | meta/catalog 每个模式的每个协议只有一个官方端点；新建表单目前只提供目录端点和自定义端点。预设表需要后端在目录里提供，或由用户决定是否在 App 内置 |
| Gemini OAuth 档位选择 | 新建时只用默认档位（Google One → google_one_free、Code Assist → gcp_standard），App 不提供档位选择 |
| 新建 apikey 账号默认开启上游倍率探测 | 按 Web 默认发 upstream_billing_probe_enabled: true；如果不想默认开启，只需改 createRequest 一行和一条测试 |
| 无刷新令牌时的“刷新令牌”行 | token_status.auto_refresh == false（没有 refresh_token）时，Claude 刷新会得到不带 reason 的 500。目前照规格保留该行，失败按 500 兜底。待用户决定是否置灰并注“没有刷新令牌，只能重新授权”（S2-16） |
| 后端补 SPARK_SHADOW_NO_REFRESH 文档 | 刷新影子账号返回 400 SPARK_SHADOW_NO_REFRESH，但 docs/API_ERROR_CODES.md 和 20 §0.5 都没有。App 已用“影子账号的凭据跟随母账号，请刷新母账号的令牌”（S2-16） |
| 真机确认更换 API Key 输入框 | SecureField 已加 textContentType(nil)、autocorrectionDisabled、privacySensitive。模拟器测不出真机会不会弹“存储密码”或钥匙串自动填充；若会弹，改用 .oneTimeCode 抑制（S2-16） |
| bedrock / service_account 凭据区文案 | 规格只定了这两类账号的主按钮去 Web（U17）。凭据区目前是“凭据 · 已设置 · 不可查看”加“在 Web 中更换凭据”，脚注“已保存的凭据不可查看；这类凭据请在 Web 中更换。”为自拟，请用户看效果图后确认（S2-16） |
| Base URL 回执的按钮 | 按设计稿给“测试”。按 20 §0.4-1，可逆的内联编辑应给“撤销”；若要撤销，可用 AccountBaseURLDraft.original 发 PATCH 写回旧值（S2-16） |
| 访问令牌剩余比例刻度 | 已定设计稿没有刻度，本条不画。以后要加时用 token_status.lifetime_seconds 作分母，只在它有值时画（S2-16） |
| 重新授权 / 换码 / apply 的超时 | 按 S2D1-03 沿用不带 key 的写 30 秒；服务端换码最长 2 分钟、保存最长 30 秒，客户端断开后仍会继续，所以上游慢时 App 会落到“不能确认是否已替换 + 重试”。建议在真实站点实测后再定是否放宽（例如 150 秒） |
| OAuthCallbackListener 真机验证 | NWListener 加 SFSafariViewController 跳本机端口只能在真机上验证：localhost 先连 ::1 的双栈情况、端口被其他 App 占用时退回粘贴、是否需要 NSLocalNetworkUsageDescription。重新授权不开监听，首个开启方是 S2-19 |
| 复制授权链接不限本机 | 为了能复制到走同一代理的电脑上打开，“复制链接”不加 .localOnly（会经通用剪贴板同步到其他设备），只把到期设为链接剩余时间；链接里没有 code_verifier，风险可接受。以后需要收紧时再定 |
| REAUTH_PERSIST_FAILED 缺 retry_within_seconds | S2-15 的口径是缺省时只给“重新授权”（不给“重试保存”）；后端目前总是带 300。若后端改了，再决定是否按 300 秒兜底 |
| 新建账号 UI 测试补跑 | S2-19 的 AccountNewUITests（13 个）是在 UI_UNAVAILABLE 下写的，从未在模拟器跑过；Mac 修好后（Xcode 27.2 需 runFirstLaunch，Toolchain.json 仍固定 27.1）补跑 check AccountNewUITests,AccountListUITests,AccountCredentialUITests,AccountEditUITests,AppNavigationUITests 并修正 |
| 新建账号停调度没有确认时“仍然关闭” | S2-19 的取消确认框给“重试停止调度 / 仍然关闭 / 继续处理”；“仍然关闭”关闭表单并回执“「{name}」停止调度没有确认 · 结果待核对”+“查看”。规格只写了重试与删除，文案待用户确认；“删除账号…”随 S2-20 加入 |
| 新建账号多协议端点预设 | 新建表单的“端点”只有目录官方端点与“自定义”。Web 的 CN_BASE_URL_PRESETS（kimi / zhipu / deepseek / minimax）不在 S2-18 的数据里，是否补齐待用户决定 |
| 跨 Tab 跳转关闭新建表单 | AppRouter.select 会无确认地关闭新建表单，已填内容和内存里的令牌一并丢弃；已发出的创建与停调度仍会做完并照常发回执。是否在 select 前询问，留给 S2-23 或用户决定 |
| 新建账号遇到 503 IDEMPOTENCY_STORE_UNAVAILABLE | 创建遇到 store-unavailable 时按结果不明核对，找不到就给“用同一编号重试”，没有按 retryNotBefore 延后；S2-20 / S2-23 可统一处理 |
| S2-19 新建账号三个 UI 用例原有失败 | Mac 能跑 UI 后首次跑出，c38ab7e 起就失败，不是这次审查修正带来的：testDockListsMissingItemsAndJumpsToFirst（第 49 行 clear 名称没清掉，坞仍是“还差API Key”）、testTurningOffMixedSchedulingRemovesGroupsWithUndo（第 165 行 sheet 内 ReceiptOverlay 的 receipt.text 找不到）、testCredentialSectionsFollowMethod（第 279 行“更多”里的负载因子行滚不到）。要查是测试辅助方法的问题，还是 sheet 内回执 / 更多分区的实现问题。 |
| 新建账号坞的“重试”（.resend）分支已经走不到 | 建号现在一律带 key，AccountNewDockContent 里无 key 时的“重试”分支不会再出现；S2-20 动这个文件时可以顺手删掉，或保留作兜底。 |
| PATCH 改 type 时清空旧凭据键 | 新建账号测试失败后改认证方式再保存：PATCH 的 credentials_patch 不能删除敏感键（CREDENTIAL_KEY_NOT_DELETABLE），PUT 退路又会保留没有提供的敏感键，旧方式的 api_key / access_token 会留在服务端（不参与新方式）。请后端评估 PATCH 改 type 时允许清空凭据；现在要彻底清除只能删除后重建。 |
| 创建失败时是否也打开测试 sheet | 规格 20 §7.5 写“创建失败 → 测试 sheet 第一行标失败”。S2-20 改为账号存在后才打开 sheet，创建失败 / 结果不明 / 混合渠道确认仍在 S2-19 的坞和弹框里处理，避免确认框和 sheet 同时出现。是否按规格改，待用户决定。 |
| AccountNewUITests 三个用例在主分支上稳定失败 | testCredentialSectionsFollowMethod、testDockListsMissingItemsAndJumpsToFirst（底栏只列“还差API Key”，不列“名称”）、testTurningOffMixedSchedulingRemovesGroupsWithUndo（没有回执）。在 091294f 上用 MAC_REF 复跑同样失败，线 A S2-20 的 check、集成者的 gate 里也一样；不在 app-rules 的基线清单里，需要 S2-19 / S2-20 的线修复或补登基线（S2-22 汇报） |
| 告警 sheet“只看需处理的账号”是否同时展开或筛到该平台 | 规格与设计稿都只切胶囊（S2-22 照做）。有平台筛选、或该平台分区已收起时，切过去可能看不到本平台需处理的账号；要不要同时展开分区或筛到该平台，待用户决定 |
| 10 §0.5 补一句“账号 Tab 也会触发 firing 列表刷新” | 20 审查记录第 7 条的建议；规格文件线上不能改，S2-22 已按这个口径实现（AccountListModel 调 LiveOpsStore.refreshFiringAlerts()） |
| 新建账号测试通过后换模型重测 | S2-20 审查修正后，测试通过（含启用没有成功）时测试行不再可点模型名。规格 20 §7.3 和设计稿允许结束后都能换模型，但通过后账号已参与调度，失败的结论没有正确文案（现有文案都说“已停止调度”）。如果要恢复，需要给“通过后重测失败、仍参与调度”定文案和按钮。 |
| 定时测试接口补信封 | 后端 GET /admin/accounts/:id/scheduled-test-plans 与 /admin/scheduled-test-plans/:id/results 用 c.JSON 返回裸数组（无数据时 null），App 靠 APIClient.decode 的 UnenvelopedReply 分支读取（S2-21）；后端补上 {code,data} 信封后可删掉这个分支 |
| vendor 读定时测试结果 | /admin/scheduled-test-plans/:id/results 不在 vendor 路由白名单，vendor 能看到计划但读结果返回 403 FORBIDDEN；App 目前写“没有权限查看测试结果，在 Web 中查看”。是否给 vendor 放开（只读、限自家账号），待用户决定 |
| 定时测试状态码正则是否放宽 | App 按规格 20 §0.1 用窄正则 \((\d{3})\)\|returned (\d{3})；后端自己用更宽的 (?:returned\|返回\|HTTP)\s*(\d{3})\b\|\((\d{3})\)。旧结果写“返回 429”“HTTP 403”时 App 解析不到码、徽章显示“—”，看实测再决定是否放宽 |
| 定时测试“每 1 分钟”写法与失败行耗时 | cron */1 照规格字面写成“每 1 分钟 / 每 1 小时”；失败结果行照规格不写耗时（设计稿 VdTests 写了）；“其他”分类词写成“529 上游 529”这种重复写法。都等用户看截图后定 |
| LoadState 重读被取消后恢复成 loaded，失败标记随之丢失 | 上次读取失败后，如果下一次重读被取消（下拉刷新、切换胶囊等会取消伴随请求），withCancelledLoad 会把 .loading(旧值) 恢复成 .loaded(旧值, 上次成功时间)。监控页等直接看 BlockState 的地方，“更新失败”标记会跟着消失，要等下一次读取才会回来。S2-22 的组头告警牌已经改用 lastErrorAt 绕开这个问题；BlockState / LoadState 的共用语义要不要改（例如取消时回到 failed），需要另外决定。 |

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
| 读类 POST 的安全重发（更新已有行） | S3-03 已处理 reveal：revealAPIKey 显式声明为 RequestClass.read，step-up 通过后自动重发一次；代价是它也会按读类请求在 502 / 504 时自动重试、进入后台时被取消（最多多一条审计）。阶段 6 其他语义是读的 POST 仍要各自声明。 |
| Key 名称按反转义显示 | 后端存 html.EscapeString(name)。App 统一显示 AdminAPIKey.displayName（反转义 & < > ' " 五个实体），删除确认也按它输入；Web 显示实体原文（A&amp;B）。如要与 Web 一致，只改 S3-03 的 displayName 一处，并撤掉删除比对的反转义（S3D1-12）。 |
| userAPIKeys 翻页期间新建的 Key | 按 id 升序翻页、去重；翻页过程中新建的 Key 最多漏掉几个，下次刷新补上。上限 50 页 × 100 个，超过就当作响应异常抛 invalidResponse。 |
| 充值与调整记录页回前台是否自动重拉 | 00 §4.6 要求回到前台时可见区块立即刷新，30 §4.6 又写本页不轮询。S3-04 只在首屏没加载成功时重拉第 1 页，并重新触发被打断的翻页；已加载过的页等下拉刷新。若评审要求严格按 00 §4.6，改为“只加载了第 1 页时静默重拉”，只动 UserLedgerView |
| 记录页“用户不存在”态的 UI 用例 | -ui-testing 下 AppModel.user(id:) 对不存在的 id 抛 invalidResponse 而不是 404 USER_NOT_FOUND，balance-history 对不存在的用户又返回空页，所以这个分支只有 isUserNotFound 单测和代码覆盖；S3-05 把详情夹具改成 404 时补一个 UI 用例 |
| 30 §4.3 拆分示例与“为 0 的项省略”矛盾 | 规格示例写了“站点赠送 $0.00”“优惠码 $0.00”；S3-04 按“为 0 的项省略”实现，两句各占一行，三项都为 0 时不显示小字；规格示例待更正 |
| UserManagementUITests 的 scroll() 会在 sheet 动画中发出退化手势 | sheet 下滑途中 scroll() 按 sheet 的导航栏取 top，拖动高度退化成 40pt，被夹到屏幕底边成了一次点按。S3-04 只在 confirmWrite 里等 sheet 关闭；S3-11 迁移、删除这个类时，新写的滚动 helper 在高度退化时应不发手势 |
| 用户详情只读拒绝文案 | 30 §0.2 / §2.5 写“当前登录的是只读令牌，不能修改”，S3-05 用的是 ReasonCatalog 通用文案“当前管理访问令牌只读，不能执行此操作”。要统一时改 ReasonCatalog 或规格其中一处 |
| 用户详情删除后的返回顺序 | 规格写“先 pop 再从列表移除”。S3-05 为保证确认 sheet 先关，改为删除成功后先移除列表行并出回执，sheet 关闭后再返回列表；视觉上看不出差别，要严格按规格时再调整 |
| 用户详情分区头 meta | NumberedSectionHeader 还没有 meta 参数（S1-09b），S3-05 先用私有分区头；S6-26 收口时换成 NumberedSectionHeader 的 meta 版（S3D1-25） |
| 待核对记录存发起人邮箱 | 本机记录只存 actorUserID，核对对话里的“这笔由 <邮箱> 发起”现在临时读 GET admin/users/<id>，读不到写“管理员 #<id>”；新记录可以多存 actorEmail（S3-07） |
| 回到前台多条精确命中的回执合并 | 30 §3.6 的自动核对每条命中出一个回执，R17 新回执替换旧回执，多条命中时只看得到最后一条；是否合并为“已核对 N 笔”由 S3-16 决定（S3-07） |
| 冷却中的重试按钮不会自己变可用 | STORE_UNAVAILABLE 的 10 秒冷却在对话弹出时判定，对话打开期间到期不会自动启用重试，需要取消后再核对一次（S3-07） |
| 旧余额页绕过唯一发送口 | S3-07 已建余额写唯一发送口 AppModel+Users.updateBalance（含 checkSender 与回显检查），旧 BalanceView 仍直接调 APIClient.updateBalance；S3-08 删除旧页，S3-16 核对只剩这一处发送 |
| 自定义属性的 validation 本地校验与 ATTRIBUTE_* 文案 | 后端属性定义带 min/max_length、pattern、number 范围、select 选项等校验，App 只校验必填；不合规时服务端返回 400 ATTRIBUTE_VALIDATION_FAILED、404 ATTRIBUTE_DEFINITION_NOT_FOUND，ReasonCatalog 里没有这两个 reason，目前按状态码兜底。规格未要求，是否补本地校验与文案待定（S3-09） |
| 新建用户结果不明时的读回口径 | 30 §5.4 第 7 步只按邮箱找（S3-09 已提供 findUserByEmail）；00 §2.5.5 另要求初始余额 > 0 时再按 action_id 查 user-adjustments。后端用户与初始余额账本在同一事务里写，找到用户即说明已入账，建议只按邮箱，由 S3-10 决定并在进度表注明 |
| findUserByEmail 只看第 1 页 20 条 | 后端 search 同时匹配用户名、备注与 Key，若同一检索词命中 20 个以上比新用户更新的用户，会误判“没有创建成功”；用户再次提交会得到 409 EMAIL_EXISTS，不会重复创建，暂接受（S3-09） |
| 用户列表刷新后残留已删除的边界行 | S3-02 审查修正后，已加载到第 2 页及以后时，刷新第 1 页会保留“新第 1 页仍含有的最后一行”之后的旧行。如果同一轮里既有顶部新增、又有边界附近的行在别处被删除，被删的行会留在列表里，直到换搜索词或换会话；这和 30 §1.6“第 2 页以后不自动刷新”带来的后续页陈旧属于同一类问题。以后若要精确处理，需要按 offset 重读已加载的各页，或改用游标分页。 |
| 退款“仍要退款”提醒措辞 | S3-08 按 30 §3.4 字面把“充值”换成“退款”，第二次确认首行是“上一笔 $12.50 退款还没核对。如果它其实已入账，这一笔会再入账一次。”，读起来像“再扣一次”的意思没写出来；用户确认后只需改 BalanceChangeCopy.pendingWarning 一处 |
| 余额页“稍后核对”的 UI 测试（更新原行） | “稍后核对”部分已由 S3-08 的 BalanceKeypadUITests.testLaterKeepsTheRecordAndShowsTheBanner 补上（-ui-balance-slow）；重试遇到 423 的部分见 S3-07 |
| 键盘内 KEY_CONFLICT 之后再提交只确认一次 | S3-08 scope 写 KEY_CONFLICT 后“按同方向待核对走两次确认”。现在原记录留作待核对、sheet 不关，再提交只出现带提醒行的确认框（第二次确认）。这和 30 §3.4“键盘打开期间才出现的待核对”同类，本次没改；后端冻结了请求体，按理不会出现 KEY_CONFLICT。是否要在 sheet 内补第一次确认，待定 |
| 新建用户：自定义属性的本地校验 | 规格只要求 required 校验；属性定义里的 validation 规则（长度、格式）与 ATTRIBUTE_* 错误码文案未做，属性写入失败目前只回执“用户已创建，自定义属性没保存成功，可在编辑用户里补填” |
| 新建用户：结果不明读回后补写属性 | 结果不明且按邮箱读回找到用户时，目前不补写自定义属性（无法确认首次请求是否已写），要不要在落地详情后补写或提示，待定 |
| 新建用户读回口径（00 §2.5.5 与 30 §5.4 第 7 步） | 00 要求余额 > 0 时再按 action_id 查记录；后端用户与初始余额在同一事务，App 只按邮箱读回。规格两处口径需统一 |
| Admin Key 不能设管理员的文案 | 30 §5.5、30 §0.4、00 §2.6.2 对同一情况有三种文案；目前主动 step-up 用 StepUpPolicy 的说明，服务端返回 STEP_UP_ADMIN_API_KEY_FORBIDDEN 时用 30 §5.5 文案 |
| 编辑用户读回不一致时的基线 | 400 / 500 无 reason 或结果不明后，读回与发送值不一致时，S3-11 只提示并保留草稿，不用 GET 结果重建基线，以免把其他管理员刚改的字段当成本页改动再发回。需要时可做三方合并：本页没改的字段跟随服务器 |
| 编辑用户自定义属性的本地校验 | 属性定义里的 validation（正则、长度）App 没做本地校验，只靠服务端拒绝后提示“资料已保存，自定义属性没保存成功” |
| 编辑页侧滑返回 | 有未保存改动或正在保存时隐藏系统返回，侧滑返回随之不可用（与新建页一致），防止绕过离开确认；是否要用 UIKit 拦截侧滑以保留手势，待定 |
| RPM 状态块刷新失败的提示 | 已显示数据后，某次 15 秒刷新失败时保留旧值、不提示；是否标“数据可能已过时”待定 |
| 编辑用户 RPM 块可见性在 iOS 26 上的回调顺序 | 审查（S3-11）认为 UserRPMStatusView 的 onAppear/onDisappear 挂在随状态换行的内容上，可能停掉 15 秒轮询。iOS 27 模拟器上 testRPMStatusKeepsRefreshingWhileShown 在原代码上通过，所以没改。如果 iOS 26 真机上发现轮询停止，把可见性改挂到固定容器（或改用 onScrollVisibilityChange） |
| Key 名称按反转义显示 | S3D1-12：App 卡片、回执和分组 sheet 标题显示反转义后的名称（“A&B”），Web 显示实体原文（“A&amp;B”）。如要与 Web 一致，只改 AdminAPIKey.displayName 一处。 |
| 老服务端忽略 Key 的 status | 方案补充的保险：停用 / 启用后响应里 status 没变，就回执“这个站点还不支持停用 Key”，不记已立即生效、不给撤销；审查可以决定是否删掉。 |
| Key 列表下拉刷新失败的提示 | 规格没写；目前保留已读的卡片，并给回执“Key 刷新失败，显示的是上次读取的内容”。 |
| 换分组撤销遇到原分组已收回授权 | Key 从基线里已没有的专属标准分组换出时，回执不给撤销（后端把 Key 绑回专属分组会重新授予）；回执没有说明为什么没有撤销，以后可以考虑加一句提示，或把撤销改成一次显式授予（走闸门、同步基线、回执写明会重新授予）。 |
| 工具链守卫与 Mac Xcode 版本 | Mac 已是 Xcode 27.2（27B52），scripts/check_toolchain.py 仍要求 27.1，所有线的 check 都报 TOOLCHAIN_EXIT=3；需要决定是更新守卫还是退回 Xcode。CoreSimulator 也需要执行 sudo xcodebuild -runFirstLaunch，UI 测试才能恢复。 |
| Key 新建 / 编辑表单与显示完整 Key 入口无设计稿（U24、U25） | 最小表单与 ⋯ 第三项按规格实现，上线前请用户看模拟器截图（ui.xcresult 的 user-keys-created-sheet、user-keys-reveal-sheet、user-keys-create-final 等） |
| 完整 Key 不可选中 | 30 §7.4 写“等宽、可选择”；为了不让系统拷贝绕过 localOnly 与 60 秒过期，只给“复制”按钮，待用户看截图确认 |
| Key 名称超长后端返回 500 无 reason | ent MaxLen(100) 在 Save 时校验转义后的名称；App 已在本地拦截（转义后 ≤ 100 字节），请后端补 reason |
| AccountOAuthTests.authURLReplyKeepsStateAndRejectsUnsafeLinks 计时断言偶发失败 | remaining 只留 1 秒窗口，Mac 高负载下在 S3-13 check 中失败一次、重跑通过；建议放宽窗口或改用可注入时钟 |
| UI 测试“先 exists 再读 frame”写法 | 很多 UITests 的 reveal / visibleBand 辅助函数用 `x.exists ? x.frame : …` 读键盘、导航栏、标签栏的位置。元素在两步之间消失时，XCTest 会记失败。UserKeysUITests 已改用 shownFrame()（先 exists 再 try? snapshot()）。其他类目前读的都是不会自己定时消失的元素，暂时没出问题；以后要读回执这类会自动消失的元素时，沿用同样的写法 |
| 平台限额 GET 在服务未启用时返回 200 空数组 | 后端 GetUserPlatformQuotas 在仓储为空时回 200 []，App 要等写入收到 503 才能显示“站点没有启用平台限额”。建议后端读取也返回 503 SERVICE_UNAVAILABLE，App 的读取已按 503 处理 |
| 平台限额整表退路的竞争窗口 | 没有 users.platform_quota_item 时，GET 和整表 PUT 之间别人新加的平台限额会被软删。App 已让两步紧挨执行，并有单测保证只改目标平台；要彻底解决需要后端整表 PUT 支持版本 / If-Match，或站点升级到带单平台接口的版本 |
| 平台限额切段刷新口径 | 目前和 Key 区一致：每个编辑页第一次进入“Key 与限额”读一次，之后靠下拉刷新和写后替换。如果要求每次切回该段都重读，需要在 UserEditScreen 的切段处加钩子 |
| 平台限额百分比小数位 | 窗口格沿用 DisplayFormat.percent 一位小数（28.0%），和 Key 卡片一致；设计稿 UeWin 是取整（28%）。如果改成取整，两处要一起改 |
| 替换分组不含已停用的专属分组 | 用户拥有的已停用专属分组不在替换分区里（UserGroupCatalog 只取启用分组，设计稿也不显示），这类替换留给 Web；需要时再给分区加上停用分组的来源行 |

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
| 错误趋势夏令时回拨日的合计粒度 | 有夏令时的站点时区里，回拨日的“过去单天”范围有 25 小时，后端给 3600 秒桶，按 40 §2.3 会合成 1 根“天”柱，而普通日是 24 根小时柱。中国站点不受影响。如需改善，可在 S4-18 改为“范围 ≤ 25 小时且桶为 3600 秒时按小时合计”（S4-11 方案 spec_issues） |
| 错误趋势按天合计在半小时偏移时区的误差 | 后端 3600 秒桶按 UTC 整点切。站点偏移为半小时或 45 分钟时（如 Asia/Kolkata），一个桶会跨过站点零点，只能按桶起点归到前一天，日柱最多差半小时的量。5 分钟与小时合计不受影响 |
| 错误分布占比的分母 | 后端 error-distribution 的 total 是 LIMIT 20 之后各行之和。状态码超过 20 种时，占比是“前 20 种之内的占比”，不是“占全部错误”。现照规格用响应 total |
| Token 速度多行合并的权重是近似值 | 后端 avg_tokens_per_sec 只对 duration_ms > 0 且 output_tokens > 0 的行求平均，App 只能按 request_count 加权（40 §5.2）。要精确需后端在 items 里加 requests_with_tps（只增字段）。另外 avg_duration_ms 无数据时是 0 而不是 null |
| 错误趋势 60 秒与 3600 秒桶的底注句式 | 40 §2.3 只给了 300 秒桶的文案。建议 S4-18 用同一句式：60 秒“后端每分钟一桶，这里按 5 分钟合计。”，3600 秒“后端每小时一桶，这里按天合计。”，后半句不变 |
| 首页退路每小时图的账号成本 | S4-02 之后 TrendPoint 已解码 account_cost，但 HomeFallback.hourly(_:now:) 构造 HomeHourlyPoint 时仍没带上 accountCost，注释还写着“trend point 里还没有 account_cost（S4-02）”。本条按 S4D1-12 只改了 dashboardTrend 的函数体，没动这里。由首页相关条目或 S4-20 收口时接上并更新注释。 |
| 自定义范围 sheet 单天时的底部说明 | 规格固定写“共 N 天，按天统计（只选一天按小时）；按站点时区计算。”，设计稿单天写“按小时统计”。S4-09 照规格实现，要改只需改 AnalyticsCustomDraft.footnote 一处，留给 UI 审查确认。 |
| 按小时刻度中末桶“现在”的替换规则 | 40 §1.4 按小时从 0 时起每隔 N 个桶标一个刻度，含现在时末桶常常不在刻度上。S4-09 的做法是把最后一个刻度换成末桶写“现在”（例如 11 桶时为 0时 / 3时 / 6时 / 现在），以免两个标签相邻重叠。留给 UI 审查确认。 |
| 利润增减两边都为 0 时的显示 | 规格写“任一边 ≤ 0 用金额差”，所以写“$0.00 · 比昨天同时”；设计稿 AxDelta 在两边都为 0 时写“比昨天同时 —”。S4-09 按规格实现，S4-13 接线时如果要改成“—”，可在调用处判断。 |
| 自定义范围日历的“今天”高亮按手机时区 | S4-12 的 DatePicker(.graphical) 已设站点时区与日历，选出的日期按站点日计算（R20）；但系统控件的“今天”高亮仍按手机时区，跨时区时可能差一天。S4-13 挂载后在模拟器上确认，必要时改成自绘月历。 |
| 筛选 sheet 占比读取失败没有提示 | dashboard/groups 或 dashboard/models 的占比读取失败时：分组行照常显示、右侧没有数字，也没有重试入口；模型列表失败时有 BlockFailureRow。是否给分组占比失败加一行“占比读取失败 · 重试”，待 S4-13 的 UI 用例与设计确认。 |
| 利润明细合计口径（40 §1.4 分段取整与 §0.2 冲突） | 规格要求实际、账号成本各自以 usage/stats 合计舍入到分为总数、利润取两者之差，同时又要求合计利润等于首页 6 格利润。但 round(A) − round(C) 与 round(A − C) 约四次有一次差 $0.01，两条不能同时满足。S4-09 审查修正（66da4cb）保住利润：利润合计 = round(A − C)，与首页、利润卡大数一致；账号成本列总数 = round(A) − round(A − C)，可能比计费卡三数里的账号成本（round(C)）差 1 分。要改回“账号成本严格等于自己的舍入值、利润合计可能与首页差 1 分”，只动 ProfitRows.init 里 costTotal / profitTotal 两行。 |

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
| 推送本机开关在设备停用时显示为关 | 60 §7.3 规定开关按“id 存在且 enabled”显示，所以设备被停用（unregistered / secret_undecryptable）时开关是关的，但状态行写“关掉再打开即可恢复”。S6-22 按字面实现（PushLocalState.isToggleOn 只有 .on），S6-24 实现页面时若觉得别扭，可改为停用时开关保持开、文案改为“重新打开即可恢复”。 |
| 推送订阅整体 PUT 会丢掉 App 不认识的事件 | PushSubscription 解码时丢弃未知事件，整体 PUT 时，服务端以后新增的可订阅事件会被一并去掉。现在后端只有 4 个可订阅事件、未知事件 PUT 也会被拒，暂可接受；后端扩充事件时要同步扩 PushEvent。 |
| 吊销本机令牌失败后的推送设备 | 吊销本机令牌时会先删除本站点推送设备，再发 DELETE。若 DELETE 失败，会话继续，但本机已登记的推送设备已被清空。S6-23 的重新登记要覆盖“会话进行中、登记记录被清空”这种情况，不能只在下次登录时补登。 |
| “刷新失败 · 重试”横幅收口 | SessionsView 和 AccessTokensView 各自写了一份“刷新失败 · 重试 / 更新于 HH:mm”横幅（00 §4.6），文案常量也重复。S6-26 可以合并成一个共用组件。 |
| 生成兑换码时订阅分组无效返回 500 无 reason | 后端 GenerateRedeemCodes 在 group_id 缺失、不存在或不是订阅类型时返回 500 且没有 reason，App 只能按结果不明保留待核对记录。App 只给可用订阅分组（isActiveSubscriptionGroup），建议后端改为 4xx 并带 reason |
| GET /admin/redeem-codes/:id 不带 user / group | 单卡刷新、写后读回和定位都拿不到使用者与分组名，App 用 AdminRedeemCode.keepingRelations(of:) 沿用列表里的值；建议后端 GetByID 补上 WithUser / WithGroup |
| 只读令牌的兑换码 ··· 菜单范围 | 规格 60 §8.3 写“只读令牌：只有 ··· 里的复制”，S6-03 理解为去掉写操作：保留复制、查看使用者、查看同一批这几个读操作，只去掉删除。若要严格只留复制，改 RedeemPresentation.menuItems 即可，请用户确认 |
| 公告删除对不存在的 id 回 200 | 后端 DELETE /admin/announcements/:id 是硬删除，id 不存在也回 200（repository/announcement_repo.go:104-108），不会出现规格 60 §16.4 说的 404 ANNOUNCEMENT_NOT_FOUND；App 仍把这个 404 视为已删除，以兼容以后的改动 |
| ReasonCatalog 缺公告 400 reason 文案 | ANNOUNCEMENT_TITLE_INVALID / ANNOUNCEMENT_CONTENT_REQUIRED / ANNOUNCEMENT_INVALID_TARGET / ANNOUNCEMENT_TIME_RANGE_INVALID 现在落到 400 兜底文案；S6-15 本地预检抛的是带 reason、文案取自 60 §17.4 的 APIError，但服务端返回同名 reason 时仍要由 S6-18 的文案表或目录补齐 |
| 无 capability 新建公告是否带 key：00 与 60 口径不一 | 00 §5 capability 表（第 618 行）写“不带 key”，60 §0.2 写“照常带 key（老服务端忽略）”；S6-15 按 60 §0.2 与 00 §2.5.1 带 key、只发一次，规格待统一 |
| 公告详情已读比例取整还是一位小数 | 规格 60 §16.3 示例写“40%”，按 00 §6.2 实现为一位小数“39.6%”；如果要取整，只改 AnnouncementPresentation.detailReadLine 一处和对应断言 |
| 公告列表已读统计失败会拖垮整页 | 带 include_read_stats 时后端对本页每条公告各跑一次全用户 COUNT，任一失败整页报错。首版照规格走通用失败态，不自动去掉参数重发；生产实测若慢或常失败，再改为失败后去掉 include_read_stats 重取一次（S6-16）。 |
| 重新发布已过期的公告 | 已归档公告的 ends_at 已过时，重新发布后状态是“展示中”，但后端 IsActiveAt 判定用户看不到，回执“符合条件的用户能看到”不准。首版照规格（确认框里能看到已过的结束时间）；等用户决定是否在确认框末尾加“结束时间已过，发布后用户也看不到；请先编辑有效期”，或改写回执 |
| 公告详情去掉 include_read_stats | 详情的已读行只用 read-summary，include_read_stats 在详情上不显示，却让后端多算一次统计，统计失败还会让整个详情请求失败。现在照规格在有能力时带上；建议以后去掉，只靠 read-summary |
| 后端删除不存在的公告返回 200 | announcement_repo.go 的 Delete 删 0 行也不报错，规格说的 404 ANNOUNCEMENT_NOT_FOUND 实际不会出现。App 已把 200、404、读回 404 都当已删除，后端以后改成 404 时 App 不用改 |
| 公告 H07 核对窗口 | 没有 announcements.idempotent_create 时新建结果不明，按标题搜最近 5 条，取确认后 5 分钟内（容许 60 秒时钟误差）、标题去空白后精确相等的最新一条；规格“最近几分钟”没有数值，待产品确认（S6-18） |
| 公告编辑 PUT 结果不明的读回 | 编辑保存结果不明时 GET :id 读回、逐键比对发出的值；不一致或读失败显示“结果未确认，请刷新核对后再操作”与“再次核对”，不重发；60 §17.4 未写，待确认（S6-18） |
| ANNOUNCEMENT_* 收进 ReasonCatalog | ANNOUNCEMENT_TITLE_INVALID / CONTENT_REQUIRED / INVALID_TARGET / TIME_RANGE_INVALID 目前只在 AnnouncementEditFailure 映射规格文案，其他入口仍落 400 兜底；以后由目录修改者收进 ReasonCatalog（S6-18） |
| 公告手机编辑不支持 eq 与余额 ≤ 0 | 手机比较符只有 > ≥ < ≤，Web 建的“余额 = X”或金额 ≤ 0 的单条件在手机只读、编辑不发 targeting；要支持需在表单加 eq（S6-18） |
| 兑换码横幅“等 N 批”的写法 | 60 §11.3 只写“标题后加‘等 N 批’”；S6-04 实现为“兑换码生成结果待核对等 2 批”，不加分隔。如果要改成“ · 等 2 批”或单独一行，只改 RedeemPendingBanner.make 和对应测试 |
| 筛选胶囊样式重复 | S6-04 的 RedeemChipLabel（RedeemCodesView.swift，私有）与账号页的 AccountChipLabel（AccountsView.swift，私有）几乎一样，S6-26 可以抽成共用的胶囊标签组件 |
| 兑换码列表入口的 UI 测试 | 概览待处理行（S1-10）与补偿回执“查看兑换码”（S6-09）合入后，把 RedeemCodesUITests 里靠 -ui-redeem-open / -ui-redeem-reconcile 进入的两条用例改为从真实入口进入，再决定是否删掉这两个夹具参数 |
| 查看同一批时的搜索 | 规格没有写；S6-04 的做法是进入同一批时清空搜索，在同一批里输入搜索词会退出同一批、回到原筛选再加搜索词。需要的话可以改为同一批内搜索（后端 batch_id 与 search 可以同时传） |
| 公告已读情况：不符合条件行的视觉 | 规格 60 §18.3 写“不符合条件变淡”，S6-19 按 S2-04 只把邮箱改 ink2，不降整行不透明度，以保证对比度；需要设计确认是否接受 |
| 余额发送登记 MoneyWriteInFlight | S3-07 的余额重试与 S3-08 的余额首发没有登记 MoneyWriteInFlight，回前台余额核对仍可能与发送并发（只读、不改记录，风险低）；由 S6-26 复核时统一登记 |
| 补偿记录可存 groupName | PendingCompensation（S0-06）没有分组名，回执与待核对页靠 GroupDirectory.name(for:) 现查，查不到写“分组 #id”；以后可以在不改请求字节的前提下给落盘记录加 groupName |
| 资金写待核对的界面与回前台自动核对（补注） | 补偿的回前台自动核对已由 S6-08 完成（与余额同一单飞，同地址、跳过发送中、只认 issued）；补偿的待核对页与 sheet 归 S6-09 |
| 补偿重试遇无 reason 的 400 | S6-08 对已发出过的补偿重试时，无 reason 的 400 保留待核对（方案原写“与首次相同，结案”），因为这次的 400 说明不了前一次是否已执行；若要改回结案，S6-09 实测后再定 |
| 公告列表与公告已读的 429 等待后重读也会取消自己 | AnnouncementsView.retryAfterWait（await list.invalidate()）和 AnnouncementReadsView.retryAfterWait（await reads.reload()）都在 .task(id: refresh.notBefore) 里 await 重读。第 1 页成功后 recordingSuccess() 清空 notBefore，task 被 SwiftUI 取消并重启，同一次重读里仍在途的 async let（公告计数 counted、已读页标题与汇总 header）随之被取消，计数或标题可能要等下次刷新才出现。修法同 S6-04 审查修正 2517eb3：等待结束后用独立 Task 发起重读。不属于 S6-04 范围，由公告条目的线处理。 |
| 代理质量检测的客户端超时 | 00 §2.3 超时表里没有质量检测这一类；后端最坏约 80 秒，App 暂定 ProxyRequestTimeout.qualityCheck = 95 秒、不自动重试。之后要决定是否把这一行补进 00 §2.3 |
| 巡检间隙“已到期 · 等待处理”的说明句与横幅 | active 但已过期、尚未被巡检置为 expired 的代理，按规格记为 soon，会进“即将到期”筛选和横幅，说明句读作“已到期 · 等待处理。到期后不回退…”，语气别扭。要改文案只需改 ProxyPresentation 一处，等用户看效果图后再定 |
| proxies.fallback_accounts 缺失时的口径冲突 | 00 章 capability 表写“全量账号本地过滤，逐个 POST revert-proxy-fallback”，60 §0.2 / §13.4 写“不提供批量恢复页，说明句改写”。S6-10 按 60 章实现（expiryNote 带 supportsFallbackAccounts 参数），以后需在规格里统一 |
| 代理列表的 429 等待 | ProxyStore 没有 BlockRefresh：被 429 时照常显示 FailureView 或“加载失败 · 重试”，不显示“请求过于频繁，N 秒后自动重试”，也不拦截等待期内的重读（其他列表已有这套处理）。需要时在 ProxyStore 加 refresh 状态，并让 ProxiesView 接 throttleMessage |
| 代理地区短名 | AdminProxy.regionText 用 Locale(zh_CN) 的系统名，HK 显示“中国香港特别行政区”，与 60 §12.3 示例“中国香港”不同；UI 测试没有断言地区。要用短名的话只改 regionText 一处（S2-11） |
| 代理夹具账号数与账号页不一致 | ProxyFixtures 里 hk-02 的账号数按规格示例写 3，AccountDemoStore 加上回退账号后是 4；目前没有跨页比较的 UI 测试。要统一时让 ProxyFixtures 的 account_count 从账号夹具派生 |
| 兑换码 REDEEM_CODE_STATUS_INVALID 文案 | 60 §9.4 让它和 GROUP_ID_INVALID 共用“分组无效，请重新选择”，对状态值错误不贴切（App 正常不会触发）。现在按正文实现，建议改为“状态无效，请重新选择”，待用户确认。 |
| 兑换码禁用 / 启用的撤销回执 | 60 §8.4 没写撤销成功或失败时的回执。现在的做法：撤销成功不出回执，徽章自己会变；失败沿用禁用 / 启用的错误表（409 刷新该卡，超时读回一次）。请用户确认。 |
| 后端 GET /admin/redeem-codes/:id 不带 user / group | 写操作后单卡刷新拿不到使用者和分组对象，App 现在用 keepingRelations 保留旧卡的 user / group。建议后端 GetByID 加上 WithUser / WithGroup。 |
| 兑换码编辑 sheet：当前分组已停用或不是订阅分组 | 当前分组不在可选项里时，仍作为已选胶囊显示并标“（已停用）”，不改选就不发 group_id。请用户确认这个显示方式。 |
| 兑换码编辑：已过期且无过期时间的“保持”文案 | Web 端“使过期”只改 status，会留下 expires_at 为空的已过期码。规格 60 §9.3 写的是“有原过期时间时才有保持”，没有覆盖这种码。App 暂时给它“保持（已过期）”并设为初值，避免一打开就续期成永不过期。文案和做法请用户确认。 |
| 后端提供 redeem_codes.batches（按批次精确核对） | 没有 redeem_codes.stats 的老服务端只能按类型、面值、时间等启发式匹配批次，要管理员点“我已核对”；超过幂等保留期后同一编号可能再生成一批，所以 App 不给重试。后端提供批次能力后，可以改成精确核对并放开重试（U43） |
| 老服务端“无法判断这一批是否已生成”的文案 | 60 §11.4 没写最近 100 条都在时间窗内、分不出这一批时怎么显示。现在是自拟的：“无法判断这一批是否已生成 / 最近生成的兑换码太多，分不出这一批。请到 Web 的兑换码列表核对。”，待设计确认 |
| 批次重发时间不跨重启保存 | RedeemBatchSendLog 只在内存里记本次运行的最近一次重发。App 重启后，老服务端退路的时间窗上界退回发起时刻 + 2 分钟，重启前那次重发生成的码可能落在窗外。需要时可以把最近重发时间写进待核对记录 |
| 代理详情：停用后才到期的代理没有专门提示 | 这种代理（status=inactive 且 expires_at 已到，后端到期扫描不处理）现在 ··· 菜单给“续期…”（S6-12 审查修正 5193d28），但按钮行仍是“测试连接 / 编辑”，状态卡仍是“停用”，“壹 有效期”只写到期日，没有说明句。规格 60 §13.3 没有这种状态的文案，要不要像已过期一样把“续期”放进按钮行、加一句说明，待定。 |
| 后端订阅分组错误码 | 订阅类缺 group_id 或分组不是订阅类型时，后端用 errors.New 返回 500 且没有 reason（service/admin_user.go:1710-1720），App 按结果不明转待核对。建议后端改为 400 GROUP_NOT_SUBSCRIPTION_TYPE（subscription_service.go:37 已有该错误）。App 只提供订阅类型且启用的分组，正常不会触发 |
| 生成向导订阅分组读取中 / 读取失败的显示 | 现在分组目录未读完或读取失败时，第 2 步也显示“站点还没有订阅类型的分组”，下一步置灰；规格只定义了没有分组的情况。是否改成“正在读取分组”/“读取失败 · 重试”待定 |
| 生成向导自定义过期天数非法时的收据 | 自定义天数为空或不在 1–3650 时，第 3 步隐藏收据、提交按钮置灰；是否改为保留收据、过期行显示“—”待定 |
| 全部恢复是否要 Face ID | 60 §13.4 没写；S6-13 按 §3.4“批量操作”在全部恢复确认后验证，单个滑动只确认。若不需要，删掉 ProxyFallbackAccountsModel.revert 里 .all 的 authorize 分支和对应测试 |
| 被改走账号逐项失败的文案 | failed 是 200 响应里的逐项结果，没有 HTTP 状态可以兜底；S6-13 按 code 给固定文案，空码写“服务器没能恢复这个账号”，重读后已不在列表的写“已不在被改走列表，可能已恢复，请到账号详情核对”。是否细化由用户定 |
| ProxiesUITests 拆文件 | ProxiesUITests.swift 已 659 行，S6-13 的用例放在 UITests/ProxiesUITests+Fallback.swift（extension）；S6-14 追加 UI 测试时宜同样新建扩展文件，items.json 的 files 需相应补上（S6-13 的 files 也应把 ProxiesUITests.swift 换成这个新文件） |
| 补偿“被其他用户用了 / 无法确认”页面文案 | 60 §19.3 没有写这两种待核对页。S6-09 自拟了“这次没有发给 …”+“重新发放”和“无法确认这次发放”+“我已在 Web 核对”，需要用户确认文案和流程 |
| 待核对页重试的 Face ID 覆盖层 | 补偿待核对页上点“用同一编号重试”时，系统 Face ID 照常弹出，但 sheet 不叠加“Face ID · 验证后发放”覆盖层（向导里的首次发放有）。可在 S6-26 统一 |
| 合并下滑先确认的 UIKit 桥 | S6-14 的 ProxyEditSheet.swift 里又加了一份 fileprivate 的 ProxyDismissAttemptBridge（和 AnnouncementEditSheet、AccountSectionSheet 的写法相同）；S6-26 收口时并成 NativeApp/Views/DismissAttemptBridge.swift 并登记进 contracts.md（S6D1-16） |
| 代理有效期日期改用 monthDayClock | ProxyEditDraft 的“保持 yyyy-MM-dd”用 ServerTimeZone.dayString，续期脚注里的“MM/DD”用 ProxyExpiry.monthDay；S6-26 收口时看是否改为转调 S3-04 的 DisplayFormat.monthDayClock（S3D1-28） |
| 编辑超时读回缺 UI 用例 | 代理编辑超时后的读回（一致 / 不一致 / 读不到）只有 ProxyEditFlowTests 覆盖；要不要加夹具参数（如 -ui-proxy-update-timeout）补 UI 用例，以后再定 |
| 代理编辑对象条地址的写法 | 续期对象条用 ProxyPresentation.addressLine（“SOCKS5H · host:port”），和详情副标题一致；规格示例里的地址是演示数据，夹具实际显示 198.51.100.30 |
| 公告编辑 sheet 结果未确认时仍可关闭 | AnnouncementEditSheet（S6-18）处于 createUnconfirmed 或 updateUnconfirmed 时，只在 isBusy 或 hasChanges 时禁止下滑；取消弹的是“放弃修改？”，关闭后也不重读列表。S6-14 审查修正前的代理 sheet 是同一个问题（00 §2.5.4 第 1 条）。建议 S6-26 合并 DismissAttemptBridge 时，一并改成“结果未确认 / 稍后核对”。 |
| 新建类写入结果未确认、关闭 sheet 后不拦截再次新建 | 00 §2.5.4 第 4 条要求核对完成前不发起同类写入。代理、公告、分组等新建类写入没有本机记录，sheet 关闭后编号也随之丢失。代理 sheet 目前只在关闭前提示，关闭后重读列表，不拦截再次添加。如果要拦截，需要给新建类写入加会话内的待核对记录，是否这样做由各模块决定。 |
