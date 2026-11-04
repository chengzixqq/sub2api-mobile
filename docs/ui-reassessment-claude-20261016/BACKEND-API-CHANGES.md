# Sub2API 后端适配清单 · 原生 iOS 管理端

这份文档列出原生 iOS 管理端（SwiftUI，最低 iOS 26）为了做出已定稿的界面，需要 Sub2API 后端（少数几条是 Web 前端）专门适配的接口。每条写明：为 App 的哪个页面、现状（源码证据）、建议改法、实现提示、后端改好之前 App 的退路、验收方法。读者是 sub2api 的维护者，照着改即可；App 侧细节只在影响接口设计时提及。

- **后端基线**：`G:/weixinProject/sub2/backend`，提交 `40bee5d2e`（本地 main，落后 origin/main 89 个提交）。`G:/weixinProject/sub2-mobile-backend` 是同仓 worktree（分支 `codex/mobile-verification-bridge`）= `40bee5d2e` + `d75c49405`；`d75c49405` 只改前端（手机验证码桥页），后端代码与 `40bee5d2e` 相同。
- **origin/main** 当前为 `e5ab7e4f4`，已补上首页账号成本与全账号 RPM（见 A01）。建议先做 A01，其余条目都在这个基线上改。
- **设计稿**：`G:/weixinProject/sub2-mobile-native/docs/ui-reassessment-claude-20261016/html-preview/main.html`（源码 `html-preview/layouts/main/00-core.jsx`、`v-*.jsx`、`v-decided.jsx`，演示数据 `html-preview/shared/data.jsx`）。
- **界面决定**：`G:/weixinProject/sub2-mobile-native/docs/ui-reassessment-claude-20261016/DECISIONS.md`（第 3 轮以“更正”后为准，文末“设计稿评审意见”“TPM 口径”最新）。
- **核实**：2026-10-18。每条“现状”都对过源码；证据不足、需要维护者先确认的放在附录 C，标“待核实”。
- **规模**：需要改的共 85 条——P0 5 条、P1 30 条、P2 50 条；另有附录 A（已支持、直接用）64 项，附录 B（只在 App 侧处理）23 项，附录 C（待拍板）19 项。

## 维护者决定（2026-10-18）

范围：**除 A10、B10 外全部 83 条都做**（A10 Passkey 等有站点域名和 Apple Team ID 再做；B10 重统计提速等生产库实测后再定，见 `BACKLOG.md`）。在 sub2 的 `main`（`3bcd2577d`，已含 origin/main `e5ab7e4f4` 与验证码桥页）上改，每条一个提交并推送到 origin；部署由维护者自己做。

| 附录 C | 决定 | 落到哪条 |
|---|---|---|
| Q1 | 新增独立速率接口 dashboard/rates（TPM 含缓存、不受运维开关影响；关监控时 RPM 只含成功请求） | B01 |
| Q2 | 关监控时首页错误率显示“—”，后端不做网关计数 | B01（关监控时 error_rate 返回 null） |
| Q3 | 新建账号时加参数 schedulable=false | C01 |
| Q4 | 只做方案 A：原生客户端可选 device / ua_only 绑定，默认 strict 不变 | A04 |
| Q5 | 两者都做：默认 access token 有效期缩短到 60 分钟以内 + Redis 按会话吊销（Redis 故障放行并记日志） | A05、A03 |
| Q6 | 做 sat_ 按设备管理访问令牌 | A08 |
| Q7 | APNs 推送 **和** 通用 Webhook / Bark / ntfy 出站都做 | A11 |
| Q8 | Passkey 暂不做（没有域名与 Team ID） | A10 → BACKLOG |
| Q9 | 清错误加可选 preserve_inactive，默认行为不变 | C18 |
| Q10 | 补上 P95 / P99 延迟规则的评估 | D07 方案 A |
| Q11 | 分组“可用偏低”兜底阈值做成站点设置（默认 0.5，available = 0 一定算） | D02 |
| Q12 | 管理员正向充值也累加 total_recharged；对外以 balance-history 的总充值为准；站点 default_balance 入账 | E05、E10 |
| Q13 | `PUT /admin/users/:id` 带 balance 返回 400 | 随 E10 |
| Q14 | rpm-status 只加 tracked 标记 | E08 |
| Q15 | 已由维护者合入 main | A01 |
| Q16 | 11 个强制幂等写接口改为可选幂等，Web 不动 | H08（G01 generate、G03 同一变体） |
| Q17 | 暂不做，实测后再定 | B10 → BACKLOG |
| Q18 | 新增派生值 schedulable_now，active 不变 | C14 |
| Q19 | vendor 只看到用户 ID + 打码邮箱；Key 明文、余额一律不给 | E02 |
| D02 补充 | 账号状态汇总不对 vendor 开放 | D02 |

## 实现进度（sub2 main，逐条提交并推送到 origin）

| 条目 | 状态 | 提交 |
|---|---|---|
| E02 vendor 使用记录脱敏 + 关闭全站用户 / Key 搜索 | ✅ | `f6b1614f8`、`e4e8ce451`（另隐去 IP、UA） |
| F03 vendor 读分组订阅越权 | ✅ | `73cf00398` |
| D01 告警静默 | ✅ | `1da0577ae`（无平台规则可静默）、`a6e3607aa`（**修复：静默表从未存在**，迁移 247）、`b04f8d1ce`（列表 / 修改 / 撤销）、`442bc3f06`（事件带静默） |
| E01 管理员管理用户 Key | ✅ | `23bb213a9`（删除）、`d5283f502`（修改与启停）、`cead4ae2a`（新建）、`57845f2cc`（读取单个） |
| G01 资金写不随断开中断、卡住可接管 | ✅ | `7469c854d`（另修：断开时邀请返利丢失） |
| G05 已兑换的码不能改回未使用再兑换 | ✅ | `fade04cba` |
| G04 兑换码多类型过滤 | ✅ | `71cfa7c3b` |
| G03 批量生成按批次去重、重放返回真码 | ✅ | `944a3fb54`（迁移 248） |
| G02 余额调整可确定核对 | ✅ | `3293b6b48`（迁移 249；可选的 D 按 key 只查不执行暂不做） |
| C01 新建账号可先不进调度池 | ✅ | `c00fc3dc9`（另加 skip_default_group_bind） |
| C02 账号结构化错误字段 | ✅ | `7e494e789`（迁移 250；存量错误账号 error_at 为 null） |
| C03 PATCH 按键编辑账号 + If-Match | ✅ | `e0eddb0f5`（迁移 251；**与原方案不同**：版本号用新增的 config_version，ETag 形如 `"cv-12"`，不用 updated_at——后者每 10 秒被 last_used 等运行态写入刷新，If-Match 会频繁误报 412；412 的 metadata 为 current_config_version / current_etag；请求体可用 expected_config_version 代替 If-Match） |
| C04 账号实际扣费排行 | ✅ | `1780664a3`（默认今天；vendor 不开放） |
| D02 账号状态汇总（不依赖运维） | ✅ | `5c94dbcfa`（站点设置 group_shortage_min_ratio；vendor 不开放；默认来源时 threshold / current 为 0–1 比例，规则来源时与规则同单位） |
| D03 上游错误列表补筛选参数 | ✅ | `09c4c827c`（三个错误列表共用解析，均支持 client_request_id） |
| D04 错误日志总耗时与首字 | ✅ | `e6e01c747`（另修：duration_ms 列从未写入） |
| D05 使用记录返回账号成本 | ✅ | `6432d7dbc` |
| B01 近 N 分钟速率 | ✅ | `4060973c2`（阶段一；vendor 不开放；关监控时错误计数器仍在 BACKLOG） |
| B02 趋势点带账号成本 | ✅ | `68485a1bd`（用户侧在 UsageService 统一剥离） |
| B03 模型筛选接受 model_source | ✅ | `400f9c9e9` |
| E03 Key 掩码视图与揭示 | ✅ | `74934faf0`（GET api-keys/:id 也支持 key_view） |
| E04 换分组 / 替换分组精确撤销 | ✅ | `dc0aa63d7`（Key 换分组的 PUT 未加幂等：重复撤销是安全的同值写） |
| E05 快捷充值头像条 | ✅ | `3c77dc085`（可选的 users?ids= 与列表行 low_balance 未做） |
| F01 分组批量加减成员 | ✅ | `7caa076b4`（建议顺带的“UpdateAccount 只改分组走快速路径”未做） |
| F02 分组统计返回真实数据 | ✅ | `3ae297f32`（total_requests 仍为 0：rollup 无请求数） |
| H01 代理延迟探测时间 | ✅ | `99dee56f1` |
| H02 代理详情完整 DTO | ✅ | `b05406aa4`（同时完成 H03 第 C 项 fallback_account_count；:id/stats 假数据未动） |
| H05 删除 / 恢复原代理的回退检查 | ✅ | `404247cab`（删除选“有回退账号即 409”，不清空其 origin） |
| H03 回退账号查询与批量恢复 | ✅ | `e1f430a4b` |
| H04 改代理地址后重新探测 | ✅ | `e97f0c7bf` |
| A02 GET /admin/me | ✅ | `7dcb6b860`（capabilities 列出本轮已上线的接口能力；features 未含 risk_control_enabled） |
| A03 刷新令牌宽限与重放检测 | ✅ | `602136e50`（另：宽限期内旧令牌在继任令牌已被使用后再出现也按重放撤销） |
| A04 原生客户端会话绑定模式 | ✅ | `4c913cbb6`（方案 A：device / ua_only；App 每个请求带 `X-Device-ID`，登录带 `client{type,device_id}`；Passkey 登录未接 client） |
| A05 撤销会话后 access token 立即失效 | ✅ | `3f9ea6fba`（默认有效期改为 60 分钟；配置里显式写了 `access_token_expire_minutes: 0` 的部署仍是 24 小时，需改为 60 或删掉该行；access token 新增毫秒级 `iat_ms`；登出带 Authorization 头时也吊销该会话） |
| A06 错误响应补齐 reason | ✅ | `b512d506c`（清单写在 sub2 `docs/API_ERROR_CODES.md`；后端模式下注册类接口与用户自助接口都用 BACKEND_MODE_SELF_SERVICE_DISABLED） |
| A07 会话列表与单独下线 | ✅ | `3b2b5231d`（DELETE 响应带 current，删的是本机会话时 App 应退出登录；部署前已存在的会话第一次刷新后才出现在列表里，且没有 client_type；站长视角的 users/:id/sessions 未做） |
| A08 管理访问令牌 sat_ | ✅ | `cf2d6259e`（迁移 252；默认只读、90 天；只读令牌可撤销自己；吊销在其他实例最多 30 秒后生效；`/admin/me` capabilities 含 `admin.access_tokens`） |
| A01 移动端基线（桥页合入 main） | ✅ | 维护者已合入（Q15，main 基线 `3bcd2577d` 含 `d75c49405`）；部署由维护者负责 |
| E09 api-keys-usage 缓存键带日期 | ✅ | `22b0bae67`（上游已完成，在 main 基线 `3bcd2577d` 内，无需改动；未加 V 字段：响应结构未变；`TestDashboardBatchUsageCache_TodayChangesAtServerMidnight/keys` 覆盖零点切换） |
| B08 user-breakdown 参数校验收尾 | ✅ | `c70594935`（dashboard 共用筛选的 400 文案统一为 `Invalid <参数名>` / `Invalid <参数名>, use true or false`，trend、models、groups、users-trend、users-ranking、api-keys-trend、snapshot-v2 一起变；request_type、model_source 文案不变，也没加稳定 reason；“传了 request_type 时也校验 stream”只加在 user-breakdown，其余 dashboard 接口按既有测试仍忽略；`model_source=` 空串改为默认 requested；负数 / 0 ID 仍视同未传。**部署注意**：user-breakdown 的 limit 超出 1-200 或非数字从静默回落 50 改为 400；同时传 request_type 和 stream 时不再 AND，stream 与 request_type 不一致的旧数据行会让用户排行数字略有变化） |
| B04 用户排行排序与成本合计 | ✅ | `5784fd3a7`（sort_by 只接受 actual_cost / requests / tokens，非法时 400 reason=INVALID_SORT_BY；cost、account_cost 只算 provider_cost_recorded 的行，与 usage/stats、user-breakdown 一致，比原始 SUM(total_cost) 小；total_users 与三项合计用窗口函数在 LIMIT 之前算，不受 limit 影响；requests / tokens 排序的次序键是 actual_cost DESC、user_id ASC；vendor 仍不开放；capabilities 含 `dashboard.users_ranking_sort`；文档提的 user-breakdown 替代方案与 cost / account_cost 排序未做，见 BACKLOG。部署注意：无迁移；不带 sort_by 时排序与原字段不变；进程内 30 秒缓存键格式变化，旧条目自然过期） |
| B12 users-trend 带筛选按 metric 取前 N | ✅ | `bfbde1d0b`（仓储与 DashboardService 新增 GetUserUsageTrendWithFiltersByMetric，原 GetUserUsageTrendWithFilters 不变；**与方案不同**：仓储缺该方法时（只有测试替身）metric=actual_cost 报错而不是回落按 tokens 取人，沿用 B04 写法；带筛选的缓存维度为 granularity:limit:metric；capabilities 含 `dashboard.users_trend_filtered_metric`；可选的 snapshot-v2 users_trend_metric 未做，仍按 tokens 排，见 BACKLOG；与 user-breakdown 比对时排名边界上同额用户可能不同：users-trend 按 user_id 升序打破平局，user-breakdown 没有第二排序键。部署注意：带筛选且 metric=actual_cost 的返回用户会变；metric=tokens / 不传 / 不带筛选与以前一致；无迁移；进程内 30 秒缓存键格式变化，旧条目自然过期） |
| B05 按请求类型拆分合计 | ✅ | `8da6d6006`（vendor 不开放；带非空 request_type / stream 返回 400，App 调这个接口时要去掉这两个参数；只返回有用量的类型，App 自己补 0，没有数据时为 []；同数按类型编号升序；model_source 生效；旧数据（request_type=0）按 openai_ws_mode → ws_v2、stream → stream、其余 → sync 归类，每类与 usage/stats?request_type= 相等；capabilities 含 `dashboard.request_types`；Web 不改，ETag 属于 B09 未做。部署注意：无迁移，只新增路由；大范围查询直接聚合 usage_logs，靠 30 秒缓存兜底） |
| B03 补漏 dashboard/groups 的 model_source 生效 | ✅ | `dd80618fe`（getGroupStatsWithFilters 原先写死按请求模型匹配，dashboard/groups 与 snapshot-v2 的 groups 部分收到 model_source=upstream / mapping 不生效，现在按 ModelFilterSource 匹配，与 usage/stats 请求数一致；核查其余 dashboard 统计（trend、models、request-types、api-keys-trend、users-trend、users-ranking、user-breakdown）均已按口径匹配，accounts-ranking 无 model 筛选，user-breakdown 的 requested_model 本来就是请求模型维度，无别处写死；不新增 capability：`usage.model_source` 已宣告，B03 后无发布标签。部署注意：带 model 且 model_source=upstream / mapping 时分组统计数字会变（以前实际按请求模型匹配）；不带 model_source 不变；无迁移） |
| E12 批量今日消费限制 ID 数量 | ✅ | `f7c61c474`（管理端 users-usage / api-keys-usage 按去重、过滤非正数之后的有效 ID 计数，超过 1000 返回 400，reason=TOO_MANY_IDS，metadata 带 field（user_ids / api_key_ids）与 max（"1000"），文案与用户侧一致；用户侧 usage/dashboard/api-keys-usage 复用同一常量与错误，状态码、文案不变，仍按原始长度计数（含重复），只多出 reason 与 metadata，两边口径差为保持只增不改有意保留；错误定义在 service/usage_batch_limits.go，已登记 TestStableErrorReasons 与 sub2 `docs/API_ERROR_CODES.md`；不加 capability（App 每批不超过 200 个，老服务端不拒也不影响）；vendor 不开放，沿用现状。部署注意：直接调管理端接口、一次传超过 1000 个不重复 ID 的脚本会从 200 变为 400；Web 每页最多 1000 条且只传当前页 ID，不受影响；无迁移、无新路由） |
| B06 运维看板按模型筛选 | ✅ | `ec2284937`（7 个接口共用 parseOpsDashboardFilter / parseOpsModelFilter，B07、B09 在其上扩展；capabilities 含 `ops.dashboard_model_filter`；使用记录侧与 usage/stats 同一模型表达式，错误日志 upstream 口径为 upstream_model → requested_model → model；带 model 时 throughput-trend 不返回 by_platform / top_groups（可选的“按模型过滤这两个汇总”未做，见 BACKLOG）；openai-token-stats 仍按 usage_logs.model 分组，有模型映射时行的 model 列可能不等于所筛模型；400 不带 reason，与 B03 一致。**部署注意**：带 model 时即使传 mode=preagg 也按 raw 查询，不再返回 409；ops 看板上 model_source=mapping 及其他非法值即使不带 model 也返回 400（Web 不发此参数）；错误日志没有模型索引，长窗口带 model 靠时间范围扫描） |
| B07 openai-token-stats 自定义时间范围 | ✅ | `6bee839a1`（start_time / end_time 任一键存在即走自定义范围，复用 usagequery.ParseRange 的成对 / 格式 / timezone 校验与报错文案，优先于 time_range（忽略 time_range，含非法值）；响应 time_range="custom"，start_time / end_time 以 UTC 回显；跨度上限 31 天 + 1 小时夏令时容差，超出 400 `OPS_TIME_RANGE_TOO_LARGE`（metadata.max_days=31，构造函数 newOpsTimeRangeTooLargeError 供 D08 复用）；不支持 start_date / end_date，不按请求时区回显；capability `ops.token_stats_custom_range`；成对 / 格式类 400 不带 reason。**部署注意**：`?start_time=&end_time=` 空串占位返回 400；上限对所有请求生效，原 time_range 最长 30d 不受影响） |
| B09 since_id 增量拉取与 ETag / 304 | ✅ | `6f225f8ff`、`cbed53a2b`（审查修正：只改注释，说明 latest_id 不是提交水位；since_id 只做 admin/usage 与 ops/request-errors：id > since_id、固定 id 降序第一页、不 COUNT，sort_by / sort_order / exact_total / count_mode 忽略，其他筛选和 vendor 账号白名单 / 脱敏照常；响应在 deferred 信封上加 since_id、latest_id（无新行时等于 since_id），has_more=true 表示新行超过 page_size、中间有缺口，App 应改用 page=1 全量刷新；since_id=0 合法；400 `INVALID_SINCE_ID` / `SINCE_ID_WITH_PAGE`（handler 内联，已写入 API_ERROR_CODES.md）。与文档不同的取舍：request-errors 带 since_id 且未显式传时间窗时不套默认 1h，范围只由 id 限定（离线超过 1 小时回来不漏），query.start/end 为 null。ETag 由 conditional_get.go 统一（writeConditionalETag / writeSuccessWithETag / writePaginatedWithETag，强 ETag + `Cache-Control: private, no-cache` + `Vary: If-None-Match`），用于 dashboard/stats（排除 uptime）、admin/users、admin/groups（含简易模式）；dashboard/snapshot-v2 的 ETag 改为排除 generated_at、query.generated_at、stats.uptime；response.PaginatedPayload 供后续条目复用。ops overview / throughput-trend 相对窗口 end 向下取整 5 秒并按 filter（含 B06 的 model）做 5 秒缓存，返回 X-Snapshot-Cache；显式 start/end 不取整；新增 parseOpsDashboardFilterBucketed / parseOpsTimeRangeAt 与包级时钟 opsNow，parseOpsTimeRange 名称保留。capabilities `lists.etag`、`logs.since_id`。**部署注意**：304 只省带宽和解码，服务端仍跑完整查询；dashboard/stats 的 rpm 每次取实时值，有流量时 ETag 难命中属正常；浏览器收到 no-cache 会自动带 If-None-Match 验证，对 Web XHR 透明；ops 看板 overview / throughput 数据最多晚 5 秒。**App 必须**：id 按分配顺序单调，但提交顺序不一定（ops 错误日志由多个 worker 各开事务逐行写入、每批最多 32 行；usage 有两条批量通道和带余额更新的单条事务；多实例各一套），小 id 的行可能比大 id 的行晚提交，窗口等于写入事务时长（通常毫秒级，库压力大时可达秒级）。latest_id 是“本批可见的最大 id”，不是安全水位，has_more 也不覆盖这种情况；只拿 latest_id 当下次游标会永久漏掉这些行。轮询时把 since_id 回退一段（如 latest_id−200，或上一批中 created_at 比最新一行早 30 秒以上的最大 id）再按 id 去重合并，下拉刷新用 page=1 校准。服务端有意不做补偿：pg_snapshot_xmin 判断不了 xid 与 id 交错的情况（逐行插入的批事务正是这样），还会被库里任何长事务卡住游标；按 created_at 留余量不可靠（created_at 在入队前取值，队列积压时远早于插入）；按 id 缺口回退会在高流量下反复重发近期行、让 has_more 常为 true） |
| D06 告警事件规则摘要、分组名、解决人与计数 | ✅ | `28d94b7bb`、`fbbd7ed29`（审查修正：评估器每轮把规则已删除或已停用的 firing 事件置为 resolved（resolved_by 为空，没有规则的事件不动），counts 不再常驻孤儿事件，口径仍等于 status=firing 的事件数；指标取不到时仍保持 firing；部署注意：行为变化，部署后第一轮评估会关闭存量的这类事件，之后停用 / 删除正在告警的规则，其事件在一个评估周期内自动关闭）（迁移 253：rule_snapshot + resolved_by_user_id，不回填；rule 优先取触发时快照，存量事件回退到当前规则（可能已被改过），规则已删且无快照时 rule=null，有快照而规则已删时 deleted=true；group_name 不过滤已删除分组；resolved_by_* 只在 manual_resolved 时写入，Admin Key 记为第一个管理员，评估器自动恢复为 null，之后再改为 resolved 会清空；counts 含被静默的 firing，P0–P3 始终存在且各键之和等于 firing，受监控开关控制，B11 首页聚合应直接复用 OpsService.GetFiringAlertEventCounts；仓库计数方法命名为通用的 CountAlertEventsBySeverity（按传入 filter 计数，service 固定 status=firing），与方案里的 CountFiringAlertEventsBySeverity 不同；CreateAlertEvent 返回的事件带上 Rule，供 A11 推送标题使用；capabilities 为 `ops.alert_event_counts`、`ops.alert_event_details`；vendor 不开放；未加 status='firing' 部分索引、PUT 对不存在的事件仍返回 updated:true，见 BACKLOG；部署注意：执行迁移 253） |
| D07 P95 / P99 延迟告警恢复评估 | ✅ | `675ad0d02`（方案 A，有意撤回上游 182683814 的删除；评估用 raw 模式窗口内成功请求 duration 的 P95 / P99，没有样本或延迟查询超时降级时跳过、不计入 evaluated、不自动恢复已有事件，不当 0；审查修正 `2e3b95ebd`：窗口内有成功请求但延迟查询超时的一轮保留连续越线计数（不清零），心跳摘要追加 `latency_timeouts=N`，没有成功请求的窗口仍清零；超时一直持续时计数冻结、规则不被评估（见 BACKLOG）；不加迁移，不改预置规则数据；Web 规则编辑器加两个选项（单位 ms，推荐 2000 / 3000）；`/admin/me` capabilities 含 `ops.alert_latency_metrics`，App 有此标记时才把这两种指标当作受支持。**部署注意（行为变化）：两条预置规则（P95 > 2000ms、P99 > 3000ms，启用且开邮件，sustained 10 分钟）部署后开始评估；duration 是整段耗时（流式含整个输出），多数站点约 10 分钟内会持续触发 P2 告警，开了告警邮件且级别含 P2 时还会发邮件。部署后请立即在 Web 调高阈值或停用，或部署前执行 `UPDATE ops_alert_rules SET threshold = … WHERE metric_type IN ('p95_latency_ms','p99_latency_ms')`**） |
| D08 服务器区补数据：CPU / 内存历史、任务心跳状态、入口拒绝合计 | ✅ | `acfd8670d`（新路由 `GET /api/v1/admin/ops/system-metrics/history`：time_range 默认 1h（非法值照旧回落 1h，另支持 7d / 30d）或成对 start_time / end_time；max_points 默认 60、1–1440，否则 400 `INVALID_MAX_POINTS`；跨度上限 31 天 + 1 小时，超出 400 `OPS_TIME_RANGE_TOO_LARGE`（复用 B07 的 newOpsTimeRangeTooLargeError，metadata.max_days=31）；bucket_seconds 为 60 的整数倍且点数 ≤ max_points，桶以 start 为锚、覆盖 (start, end]，只读 window_minutes=1 且无平台 / 分组的行；CPU、内存 % 取平均不舍入（60 秒桶时最后一点与 overview.system_metrics 相同），memory_used_mb、goroutine_count、concurrency_queue_depth 取四舍五入平均，db_ok / redis_ok 桶内任一次失败即 false，created_at 为桶内最新样本；响应比文档多 start_time、end_time、每点 sample_count 与 memory_used_mb，无数据时 points 为 []；受监控开关控制（关闭 404 OPS_DISABLED）；vendor 不开放。overview（含 snapshot-v2）job_heartbeats 每项加 expected_interval_seconds、next_expected_at（UTC）、status；**与文档不同**：status 多一个 `disabled`（设置里关闭清理、预聚合关闭、没有开启任何带 cron 的定时报告），App 遇到不认识的值按 unknown 处理；设置里已开启但 cron 非法、任务不会运行时（清理 cron 起不来，或已开启的报告 cron 全部非法）为 failing，expected_interval_seconds / next_expected_at 为 null，last_error 不写原因（`d8b4d2d7a` 审查修正：原来显示 disabled，像是主动关闭）；next_expected_at 取 last_run_at 与 last_success_at 中较晚者 + 间隔（cron 任务为其后的下一次计划时间），stale 时可能早于当前时间；stale：间隔类 now − last_success_at > 2×间隔 + 运行超时 + 1 分钟（指标采集 60 秒时约 190 秒），cron 类（ops_cleanup，按清理实际使用的时区）为“上次成功后的第一次计划时间 + 31 分钟”已过，凌晨的清理白天为 ok；stale 优先于 failing（`3398e1ae7` 审查修正：原实现 failing 优先，持续失败的任务永远停在 failing；现为窗口内最近错误晚于最近成功 → failing，超过 stale 窗口仍无成功 → stale，从未成功过的为 failing / unknown；验收注意：停掉 Redis 不会让指标采集失败——leader 锁回退到 DB advisory lock，只把 redis_ok 记为 false——可在测试库事务里 `LOCK TABLE ops_error_logs IN ACCESS EXCLUSIVE MODE` 并保持超过 10 秒采集超时来制造失败）；未登记的任务只判 failing / unknown、间隔为 null；从未运行过的任务不出现在列表里，App 不要假设固定 6 项；间隔来源：采集器读 ops_metrics_interval_seconds、告警评估读 evaluation_interval_seconds（两者抽出共用纯函数，调度行为不变），清理读正在运行的 cron（新增 OpsCleanupService.CurrentSchedule）；健康分的“15 分钟没成功算失败”未改（见 BACKLOG）。ingress-rejections 加 request_count_total 与 by_reason（与列表同一组筛选、不受分页影响，按 request_count 降序、reason 升序，始终为数组），total 仍是行数；原 COUNT(*) 换成一条按 reject_reason 分组的查询。capabilities 含 `ops.system_metrics_history`、`ops.job_heartbeat_status`、`ops.ingress_reject_totals`（方案只列第一项，按全局约定新字段也登记）。部署注意：无迁移、无 wire 改动，Web 不读新字段；overview 缓存未命中时多读 3 个设置；多实例部署时每个实例每分钟各写一行指标（leader 锁只防同时采集），history 同桶取平均，overview.system_metrics 是最后写入的那一行，两者不一定完全相同） |
| D09 运维监控开关 | ✅ | `bb6470c72`、`d4b8baa24`（审查修正：Web 设置页的实时监控、默认查询模式、采集频率也改为只在与加载 / 上次保存值不同时提交，未改动的保存不再用旧表单覆盖 App 经 monitoring-status 改过的值）（新路由 `GET/PUT /api/v1/admin/ops/monitoring-status` 不受运维开关控制；monitoring / realtime 返回设置表持久值（缺失按 true，realtime 不被总开关屏蔽），effective = config_enabled && monitoring_enabled，disabled_reason 先 config_off 后 setting_off；配置关闭时 PUT 一律 409 OPS_CONFIG_DISABLED 且不写库，{} 直接返回当前状态；PUT 只即时更新本实例快照，其他实例最多约 30 秒后生效；vendor 不开放；`/admin/me` 增加 features.ops_monitoring_disabled_reason（按本实例快照）与 capability `ops.monitoring_status`。Web：设置页“功能”tab 新增运维监控卡片，配置关闭时启用开关置灰并提示，ops_monitoring_enabled 只在改动且配置未关闭时提交，另外三项只在改动时提交（采集频率夹在 60–3600）；设置页支持 `?tab=`，运维页与 404 拦截器跳转改为 `/admin/settings?tab=features`。**部署注意**：无迁移、无 wire；Web 保存只带页面上改过的 ops 字段，两端改同一项时后写者赢；GET/PUT `/admin/settings` 的 ops_monitoring_enabled 口径不一致按只增不改保留，见 BACKLOG） |
| D10 上游重试链：每次尝试的开始时间与耗时 + 按请求合并接口 | ✅ | `782e631d7`（upstream_errors 事件新增 `started_at_unix_ms` / `duration_ms`，只增 JSON 字段、不迁移，部署后新产生的事件才有，历史数据为 null；**与原方案不同**：没有存进 GatewayRequestTiming（只在 /v1/messages 安装），改为运维错误中间件给每个网关请求装一个尝试时钟，http_upstream 的 Do / DoWithTLS 每次分发打点，事件向同账号、未领用的那次分发领用开始时刻；耗时含取连接与读响应体 / 流式时间，WebSocket 等不走 http_upstream 的路径没有耗时。新路由 `GET /api/v1/admin/ops/requests/:request_id/attempts`（可选 `around`=RFC3339，两表收窄到 ±1 小时），参数可传运维 request_id、client_request_id 或使用记录的 `client:<client_request_id>`；**文档前提更正**：usage_logs.request_id 是 `client:<client_request_id>` 不是运维 request_id，App 退路要用 `admin/usage?request_id=client:<client_request_id>`；成功那次 upstream_status_code 固定 200、started_at 按 created_at − duration_ms 估算，最终仍失败时为 outcome=partial；client_status_code 取最新失败行，其次恢复行，只有使用记录时为 200；流错误行与恢复行共有的事件只保留一次；failover 事件按账号 ID 回查补名字（含软删除账号）；新 reason 404 `OPS_REQUEST_NOT_FOUND`、409 `OPS_REQUEST_AMBIGUOUS`（客户端复用 X-Request-ID 命中多条链，metadata.client_request_ids 逗号分隔最多 5 个）、400 `INVALID_REQUEST_ID` / `INVALID_AROUND`；关监控时 404 OPS_DISABLED；vendor 不开放；capabilities 含 `ops.request_attempts`；Web 不改；**审查修正 `57f14631b`**：request_id 含 NUL 或非法 UTF-8 时返回 400 INVALID_REQUEST_ID（原为 500）；探测合并 leader 的计费 ID `probe:<运维 request_id>` 纳入候选，参数也可传 `probe:<id>`；同账号重试后成功时，成功项 started_at 夹到前一次失败的结束时刻，duration_ms / first_token_ms 同步扣减（仍含退避等待，partial 项不夹）；409 的 client_request_ids 改为最新在前，并新增 metadata.client_request_id_times；含 `/` 的 X-Request-ID 无法作路径参数，文档提示改用 client_request_id 查。**部署注意**：上述非法 ID 由 500 变 400，409 列表顺序反转） |
| B11 首页聚合接口 dashboard/home | ✅ | `613f9b029`（新路由 `GET /api/v1/admin/dashboard/home?timezone=&include=`，七段 stats / rates / hourly / ops / alerts / availability / channels 并发构建，每段独立超时 3–6 秒、整体预算 8 秒，不响应 ctx 的源也不拖住整包；鉴权与参数通过即 200，每段 status 为 ok / disabled / error / timeout；参数错误 400 `INVALID_TIMEZONE` / `INVALID_INCLUDE`（include 不传为全部，只有逗号也算非法）；段 error 沿用源错误的稳定 reason，没有则 `INTERNAL_ERROR`（原始错误只写日志），超时 `SECTION_TIMEOUT`，panic 记为 INTERNAL_ERROR，取值写入 sub2 `docs/API_ERROR_CODES.md`。**与文档不同**：availability 用 D02 状态汇总，不依赖运维，关监控时仍为 ok（文档示例为 disabled），只列 error / overloaded / rate_limited / temp_unschedulable 账号（AccountStatusItem 原样），最多 100 个，超出时 accounts_truncated=true；timezone 只影响 hourly（按请求时区拆 today / yesterday，不补零桶），stats 的今日与 yesterday_same_time_* 固定按服务器时区，与 dashboard/stats 一致；yesterday_same_time_*（requests / actual_cost / account_cost / until）截止点在开预聚合时为 stats_updated_at（聚合水位，夹在今日 00:00 与 now 之间）减一天，否则 now 减一天，查询失败时为 null 而 stats 段仍为 ok；alerts 用 D06 GetFiringAlertEventCounts 给精确 firing_count 与 by_severity（含被静默的），top 为最新 5 条 firing 事件，没有方案里的 limit=100 近似；channels 为 total / healthy / warning / critical / unknown（stale 计入 unknown）加 coverage_state、collector_state，不是示例里的 failing；rates 为 B01 原样（关监控时 error_rate 为 null，不会是 disabled）；ops 为近 5 分钟 raw 概览精简字段，与 rates 共用 5 秒取整的结束时间。15 秒进程内缓存（scopedUsageCacheKey，键含身份、作用域、时区与 include），带 error / timeout 段的响应不进缓存；ETag 排除 generated_at、rates / ops 的 start_time / end_time、availability.collected_at，带 `Cache-Control: private, no-cache` 与 `Vary`，支持 304；nocache / force_refresh 绕过缓存并透传给渠道监控 refresh；vendor 不开放（守卫测试）；capability `dashboard.home`。部署注意：无迁移；wire 新增 DashboardHomeService（wire_gen 已重新生成）；冷缓存时一次请求并发约 10 条查询，缓存按管理员身份区分，“冷缓存 p95 < 3s”需在生产量级实测（见 BACKLOG）；Web 不改） |
| C07 账号测试末尾 test_result 事件 | ✅ | `ddb472895`、`60d64c1fc`（审查修正：请求上游前的本地提示——OpenAI OAuth 图片的 Calling Codex、Grok 源图 / 首帧 / 上传音频、realtime 拨号目标——仍照常下发但不计首字，上游失败时 first_token_ms 为 null）、`2f913514a`（审查修正：Antigravity OAuth / Upstream 的非流式测试成功时也记录上游状态码，此前成功项 upstream_status 恒为 null、只有失败时靠错误文本兜底；定时测试与 test-runs 的 upstream_status_code 同样受益）（现有事件不变，流末追加一条；顶层 success 失败时缺省，App 以 data.success 为准；usage 只覆盖 Claude / 自适应 Anthropic / Responses / Chat Completions（上游主动返回才有）/ Gemini 流与 TypeSafe，其他路径省略；upstream_status 取最后一次上游响应，拿不到时从错误文本兜底解析，再拿不到为 null；first_token_ms / total_ms 从 TestAccountConnection 入口起算，含 token 刷新等前置耗时，不含恢复耗时；客户端断开时不发；测试后读账号失败时 account、marked 为 null；marked 是测试前后快照对比，测试期间真实流量改了账号状态时可能误报；trace 导出 AccountTestTraceFrom 供 C08 / C09 读取状态码、首字、模型与输出文本；account 暂不含 schedulable_now（归 C14）；capabilities 含 `accounts.test_result`） |
| C09 定时测试结果 upstream_status_code / error_kind | ✅ | `9de06cf53`、`3e4dbdbda`（审查修正：一次测试发多次上游请求时，后一次请求无响应（dial / TLS / 传输错误）会沿用前一次的 200 / 202，失败行落库为 failed + 2xx；现在所有无响应分支先清空 trace 状态码，自适应测试每个原生端点前也清空，网络错误类失败的 upstream_status_code 与 C07 的 test_result.upstream_status 由 2xx 变为 null）、`59e8d34c2`（审查修正：Antigravity OAuth / Upstream 账号测试遇上游 429（retryDelay ≥ 7 秒或智能重试耗尽）时，重试循环转成账号切换信号，错误文本“该账号模型 X 当前限流中”里没有状态码，此前落库为 null / other；现在切换信号带触发它的上游状态码，文本不变，失败项为 429 / rate_limit（503 仍为 other），C07 test_result 与 C08 test-runs 同样受益；账号已处于本地模型限流、测试未发上游请求时仍为 null / other）（迁移 254 只加 upstream_status_code INT NULL，不回填旧行，旧结果为 null、随 max_results 滚动淘汰；状态码直接读 C07 的 trace，未记录时用 C07 的同一正则从错误文本兜底；**与原方案不同**：没有再给 TestEvent / SSE error 事件加字段、没有改约 22 处调用点（C07 已覆盖），成功项也带 trace 记录到的真实状态码（通常 200，合成账号等没有上游响应时为 null）；可选的 error_kind 已做，但不落库、读时派生：先按 C02 前缀分类，分到 other 时再按 401→auth、402→quota、403→forbidden、429→rate_limit 映射，C02 枚举新增 rate_limit，状态码为空的旧行从文本解析一个码只用于分类、不回写；AccountTestErrorKind 供 C08 复用；capabilities 追加 scheduled_tests.upstream_status；Web 列表与 TS 类型不改；部署注意：需执行迁移 254） |
| C09 发现的越权：vendor 跨工作区读取定时测试计划 | ✅ | `ba97910c5`（GET /api/v1/admin/accounts/:id/scheduled-test-plans 经 /admin/accounts 的 GET 前缀对 vendor 放行而不校验归属，现在 handler 先用 adminService.GetAccount（GetByIDScoped）校验，别家账号 404 `ACCOUNT_NOT_FOUND`；其余四条路由（POST /scheduled-test-plans、PUT / DELETE /scheduled-test-plans/:id、GET /scheduled-test-plans/:id/results）不在 vendor 白名单里，路由层本就 403，当前不可利用，handler 一并补兜底：新建按 account_id 校验，修改 / 删除 / 结果列表经计划所属账号校验，计划不存在与属于别家都返回 404 `RESOURCE_NOT_FOUND`；读需要账号管理或监控档，写需要账号管理档，缺作用域 403 `WORKSPACE_PERMISSION_DENIED`；站长不做额外查询，行为不变；新增 vendor 路由守卫测试锁住现状。与方案不同：没有把列表路径加入 vendorDeniedRoutes——vendor 看自家账号的计划是合理能力，改为在 handler 校验归属。部署注意：vendor 对别家账号的计划列表由 200 变为 404；无迁移，wire_gen 只改 NewScheduledTestHandler 一行（新增 adminService 参数），Web 不改，没有新 capability（只收紧权限，不是新能力）） |
| C08 异步账号测试 test-runs + 手动测试落库 | ✅ | `cf63db138`、`80ce434c0`（审查修正：worker 占满时先查该账号的 running 行，同账号已有运行中的测试仍返回 409 ACCOUNT_TEST_RUNNING + run_id，此前返回 429；CreateRunning 冲突后回读时若那次测试恰好结束，改为重新插入（最多 3 轮），不再让 POST 返回 404 ACCOUNT_TEST_RUN_NOT_FOUND；running 行的 model_id 去掉 NUL，此前含 NUL（\u0000）时返回 500）（POST /admin/accounts/:id/test-runs 返回 202，后台以 context.Background() + 120 秒超时运行，成功且 recover_on_success（不传按 true）时恢复；GET /accounts/:id/test-runs/latest 与 GET /account-test-runs/:run_id 读结果；409 `ACCOUNT_TEST_RUNNING`（metadata.run_id）、429 `ACCOUNT_TEST_BUSY`（每实例 10 个 worker）、404 `ACCOUNT_TEST_RUN_NOT_FOUND`（无记录 / 越权一律此码，latest 无记录不返回 200 + null）；迁移 255 新建 account_test_runs，部分唯一索引保证每账号最多一条 running，每账号保留最近 20 条已结束记录，error_message 脱敏截 2000 字、response_text 截 2000 字、prompt 不落库；SSE 手动测试在 test_result 之后尽力写一条 source=manual（WithoutCancel + 5 秒，失败只记日志，SSE 输出不变；客户端已断开且失败时记 interrupted，已成功的仍记 success）；崩溃 / 重启遗留的 running 按数据库时间超过 180 秒标 interrupted（启动清扫一次 + start / latest / 按 run 读取时），多实例安全；首字、状态码、模型、文本复用 C07 trace，error_kind 复用 C09 的 AccountTestErrorKind，RunTestBackground 改为 RunTestCaptured 薄包装、定时测试结果不变；与文档不同：视图多给 error_message、response_text，recovery 同时含 cleared_rate_limit；async 不支持 image / audio 媒体参数；scheduled 只保留枚举值，定时结果仍在 scheduled_test_results；vendor 不开放（vendorDeniedRoutes 拒绝 /accounts/:id/test-runs，service 层另按账号归属兜底），vendor 的 SSE 测试不变；capabilities 追加 `accounts.test_runs`；部署注意：需执行迁移 255，每次 SSE 手动测试多写一行库，worker 上限按实例计，突发时 App 需按 429 重试；Web 不改） |
| C05 恢复状态时一并设置调度开关 | ✅ | `0d70c6854`、`25a85d2bf`（审查修正：false 改为先暂停再恢复，见下）（recover-state 新增可选请求体 `{"schedulable": bool}`：不带体、空体、`{}`、null 与原来完全一致；true 恢复成功后再启用调度，恢复失败不碰开关；false 在恢复之前写入暂停（`25a85d2bf` 起；原先先恢复后暂停，限流 / 过载 / 临时不可调度账号的 schedulable 本来是 true，两步之间会进调度池，暂停写失败还会停在“已恢复且可调度”），暂停写失败时不做恢复、返回原错误，恢复失败时账号已暂停，两种都可整体重试；启用（true）写失败返回 500 `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED` + `metadata.recovered="true"`，只有 true 会返回此码，开关可能已写入（写库成功、回读失败时），App 以 GET 读回的 schedulable 为准、再单独重试 `/schedulable`，文案不要写死“仍暂停”；**与文档不同**：请求体格式错误或类型不对返回 400 且不做任何读写（文档原建议静默忽略），现有 Web 不带请求体不受影响，部署注意：带垃圾请求体的第三方脚本会被拒；新建 `bindOptionalJSON`（handler/admin/request_binding.go）供 C18、C11 复用；capabilities 含 `accounts.recover_schedulable`；vendor 路由不变，守卫测试锁定 recover-state 与 /schedulable 同受 AccountManage 约束；`25a85d2bf` 部署注意（行为变化）：带 false 且恢复失败时账号留在 schedulable=false，暂停写失败由 500 ACCOUNT_RECOVERED_SCHEDULABLE_FAILED 改为原错误；Web 不改） |
| C18 清除错误时可选不重新启用停用账号 | ✅ | `9b023fb9d`、`b4fedfca9`（审查修正：只补测试，锁定 vendor 清除其他工作区账号带 / 不带 preserve_inactive 都返回作用域越权且零写入）（单个 `POST /admin/accounts/:id/clear-error` 新增可选请求体 `{"preserve_inactive":true}`（复用 C05 的 bindOptionalJSON），batch-clear-error 请求体只增 preserve_inactive；不带参数时与原来完全一致（Q9）。preserve 时“停用”口径为 status 既不是 active 也不是 error（inactive 加历史值 disabled，与 D02 一致，比文档字面的 inactive 略宽），这类账号不改 status、error_message、error_at，只清限流、Antigravity 配额、模型限流、临时不可调度与运行时调度阻断；单个接口响应仍是账号对象，App 看 status；batch 响应只增 `skipped_inactive_ids`（始终输出，按 ID 升序，没有时为 `[]`），被跳过的也计入 success，errors 照旧（无错误为 null），请求里有重复 ID 时该列表也会重复。**与文档不同**：没有用“先读状态再跳过”或 ClearErrorIfError，而是仓储可选窄接口 AccountErrorClearerPreservingInactive，一条 `UPDATE … WHERE id=? AND status IN ('active','error')` 判断并写入，无竞态，未命中时不写调度 outbox、不同步快照；仓储没实现该接口时在任何写之前报错。服务层 ClearAccountErrorWithOptions / ClearAccountErrorOptions / ClearAccountErrorResult 供 C11 直接复用，原 ClearAccountError 以零值选项调用它，刷新凭据、apply-oauth-credentials 行为不变。capabilities 含 `accounts.clear_error_preserve_inactive`：旧服务端会静默忽略该参数并照样启用停用账号，App 必须先确认此能力，否则继续本地过滤 inactive。部署注意（行为变化）：单个 clear-error 带格式错误或类型不对的请求体（如 `"preserve_inactive":"yes"`）返回 400 且不做任何写，现有 Web 不带请求体不受影响；无迁移、无 wire 改动；vendor 路由不变（单个接口仍按 AccountManage 开放并有归属校验，batch 仍只限站长）；Web 不改，未加 Web 选项（见 BACKLOG）） |
| C12 OAuth 换码错误统一 400 + reason | ✅ | `640e5b688`、`a89b52fbd`（审查修正：拒码判定收窄，见下）、`2a7779100`（审查修正：OpenAI / Grok 拒码改 400 后不再进 ErrorFrom 的 [ERROR] 日志，仓库层补一条脱敏的 WARN “token exchange rejected”）（三类 reason：`<平台>_OAUTH_SESSION_NOT_FOUND`、`_INVALID_STATE`、`_CODE_REJECTED`，新增 CLAUDE_ / GEMINI_ / ANTIGRAVITY_ 的会话与 state 两类，五个平台都有 CODE_REJECTED；拒码判定（`a89b52fbd` 收窄）为上游 4xx（不含 408 / 429）且响应 `error` 为 `invalid_grant`，或不带 invalid_client / unauthorized_client / unsupported_grant_type / invalid_scope 的 400；不带 invalid_grant 的 401 / 403 / 404（Cloudflare 拦截、地区封锁、client_secret 配错）不算拒码，保持各平台原样，授权码与会话仍可原样重试；`metadata.upstream_status` 为上游状态码，上游 5xx / 408 / 429 / 网络错误保持各平台原样（Claude 500、OpenAI / Grok 502 `*_TOKEN_EXCHANGE_FAILED`、Gemini / Antigravity 400 无 reason），Grok 明确授权拒绝仍是 403 ENTITLEMENT_DENIED；Gemini / Antigravity 的 message 前缀与文字不变、状态码仍 400，只补 reason 与 metadata；Claude 拒码 message 固定为 "authorization code was rejected by upstream"，不回显上游 body；**与文档不同 / 补充**：Claude 没有单独的 state 参数，新增本地校验只在粘贴的授权码带 `#state` 时生效（不一致时不调上游、保留会话），不带 # 的旧粘贴方式不校验；Gemini、Antigravity 的 state 比较改为常量时间；仓库层非 2xx 改返回类型化错误（`oauth.TokenExchangeError`、`antigravity.TokenExchangeError`，文本逐字不变），service 层 `oauthCodeRejected` 判定、`NewOAuthCodeRejectedError` 供 OpenAI / Grok 仓库层复用，C11 的 reauthorize 可直接透传这些 reason；capabilities 含 `accounts.oauth_error_reasons`；拒码后 Claude / Gemini / Antigravity / OpenAI 会话仍在可换新码重试，Grok 换码前已消费会话需重新生成链接；**部署注意（行为变化）**：Claude 两个换码接口的会话过期与拒码从 500 "internal error" 变为 400（拒码不再进 ErrorFrom 的 [ERROR] 日志，仓库层 Step 3 仍记脱敏响应），Cookie 自动授权不变；OpenAI / Grok 上游拒码（同上判定）从 502 `*_TOKEN_EXCHANGE_FAILED` 变为 400 `*_CODE_REJECTED`，依赖旧码的外部脚本需调整；Gemini 换码时本来带 reason 的配置类错误 message 从 "error: code=… reason=…" 调试串变成干净文字；Claude 的 #state 校验依赖控制台回调页原样回显 state，未在真实 Claude 账号上手工走过，上线后在 Web 走一遍 Claude OAuth 与 Setup Token；Web 不改，回退显示 message） |
| C10 账号 token_status + Setup Token 寿命文案 | ✅ | `fae67f652`（详情 dto.Account 与列表项都带 `token_status {expires_at, lifetime_seconds, refreshed_at, auto_refresh}`，只给 oauth / setup-token 账号（spark 影子除外），详情里其他类型为 null、列表里省略；字段只含时间与布尔值，不含剩余秒数一类随时间变化的值，列表 ETag / 304 不受影响；expires_at 兼容 Unix 秒与 RFC3339，统一输出 UTC；lifetime_seconds 只取 credentials.expires_in，缺失为 null、不推算；refreshed_at 读新键 `_token_refreshed_at`，读不到时用 `_token_version` 截到秒兜底；auto_refresh = 有 refresh_token 且不是 OpenAI PAT（PAT 账号也给对象，auto_refresh=false）。**与文档不同 / 补充**：`_token_refreshed_at` 的管理端写点不是分别改 refreshSingleAccount 与 ApplyOAuthCredentials，而是统一放在 updateLoadedAccount——oauth / setup-token 账号的 access_token 变化即写入，同时覆盖手动刷新、apply-oauth-credentials、Web 对 Gemini / Antigravity 走 PUT 的重新授权、PATCH 换令牌和以后 C11 的 reauthorize，语义是“令牌被替换的时间”，只改 base_url 等的编辑不写；后台统一刷新与降级刷新和 `_token_version` 取同一时刻（含 Grok CAS 分支）；新建 OAuth 账号写入，导入数据已带合法值则保留；复制账号不经写入点，凭据与源账号完全一致。expires_in 由 OpenAI / Gemini / Antigravity / Grok 的 BuildAccountCredentials 在 ExpiresIn>0 时写入（字符串），OpenAI 只在带 refresh_token 时写；Gemini / Antigravity 的 expires_at 已减约 300 秒安全窗口，刚刷新时刻度条约从 92% 起；Grok 上游不给 expires_in 时按后端默认 6 小时写入。Web 只改文案取值不改 key：“Setup Token（访问令牌 8 小时，自动刷新）”/ “Setup Token (8-hour access token, auto-refreshed)”；capabilities 追加 `accounts.token_status`。部署注意：无迁移、无新路由、无 wire 改动；账号详情 JSON 多一个 token_status 键（非 OAuth 为 null），OAuth 账号凭据此后多出 `_token_refreshed_at` 与 expires_in 两个非敏感键；存量账号 refreshed_at 只能从 `_token_version` 兜底（从未后台刷新过的为 null），非 Claude 账号的 lifetime_seconds 要等下一次带 refresh_token 的刷新后才有；CRS 同步与 Web 前端构造凭据未写这两个键，见 BACKLOG；审查修正 `dd2f61c55`：expires_at / refreshed_at 换算后年份不在 1..9999（如 expires_at 存成毫秒、超大 `_token_version`）时输出 null，避免 time.Time.MarshalJSON 报错导致账号详情 / 列表整页无 JSON；`_token_refreshed_at` 越界时回落 `_token_version`，新建账号导入的越界值重新写入当前时间；审查修正 `4043251e6`：新建账号时凭据里已有可换算的 `_token_version`（C10 之前实例的导出数据）也不再写入 `_token_refreshed_at`，refreshed_at 保留原刷新时间而不是导入时刻；Codex auth.json 导入仍记导入时刻，见 BACKLOG） |
| C11 一步重新授权 reauthorize + apply 的 preserve_status | ✅ | `3012f696d`、`a8dd35346`（审查修正：OpenAI / Grok 上游与网络失败统一为 OAUTH_EXCHANGE_FAILED，见下）、`4522c8d71`（审查修正：保存成功后的重放改为重新读取账号再返回，不再返回校验阶段读到的旧快照；完成标记从保存成功起保留完整 5 分钟；落库失败时重新暂存，retry_within_seconds 从这次 500 起算、每次失败重新计时；补 vendor 代理不在本工作区与访问其他工作区账号的越权反向测试，补 OpenAI / Gemini / Antigravity 成功路径的凭据与 extra 测试）（新路由 `POST /api/v1/admin/accounts/:id/reauthorize`，请求体 session_id、code 必填，state、redirect_uri、proxy_id、auth_kind（oauth / setup-token，仅 Claude，缺省取账号现有 type）、oauth_type / tier_id（仅 Gemini，tier_id 缺省取现有凭据）、preserve_status 可选；支持 anthropic / openai / gemini / antigravity / grok，凭据用后端 Build*Credentials 构造，extra 与 Web 一致（Gemini 的 Drive 信息写 extra），Grok 不写 base_url、保留原值；响应与 apply 相同，令牌不出服务端。apply-oauth-credentials 只增可选 `preserve_status`（缺省 false 不变），两者都复用 C18 的 ClearAccountErrorWithOptions(PreserveInactive)：停用口径同 C18（status 既不是 active 也不是 error），error 账号仍恢复 active；apply 的后半段抽成 persistOAuthCredentials 两边共用，apply 的校验、错误与日志事件名不变。错误：换码阶段带 reason 的非 502 错误原样透传（C12 的会话过期 / state 不符 / 拒码、Grok 403 授权拒绝等，状态码随原错误）；上游与网络失败五个平台统一为 502 `OAUTH_EXCHANGE_FAILED`（metadata.platform，message 带脱敏原因）——`a8dd35346` 起 OpenAI / Grok 换码层自带 reason 的 502（`*_OAUTH_TOKEN_EXCHANGE_FAILED`、`*_OAUTH_REQUEST_FAILED`、`OPENAI_OAUTH_PROXY_REQUIRED`、`*_OAUTH_CLIENT_INIT_FAILED`、`GROK_OAUTH_INVALID_TOKEN_RESPONSE`）也归一，原 reason 放 `metadata.cause_reason`（其他平台无此键），此前这两个平台会透传自己的 502 reason，App 认不出；400 `NOT_OAUTH`；400 `REAUTH_UNSUPPORTED`（metadata.detail = shadow_account / codex_personal_access_token / unsupported_platform / auth_kind_not_supported）；500 `REAUTH_PERSIST_FAILED`（metadata.retry_within_seconds=300、cause_reason）。**与文档不同 / 补充**：没有用文档建议的 RecoverAccountState，改用 C18 的服务函数；换码与落库脱离客户端取消（换码 2 分钟、落库 30 秒）；换码成功后凭据按平台 + session_id + 账号暂存在进程内存 5 分钟（最多 256 条），落库失败用同一 session_id 重试直接落库，成功后只留完成标记、5 分钟内重放直接返回账号（200）；另加了方案里原本不做的单飞：同一会话与账号的并发请求共用一次换码，避免 App 在换码未完成时重试被判拒码。vendor：沿用 /admin/accounts 写前缀，需 AccountManage，账号按工作区校验，代理强制用账号自己的代理并经带作用域的 GetProxy 校验、忽略请求 proxy_id；vendor 拿不到 OpenAI / Gemini / Antigravity 的授权链接（那些 auth-url 路由不对 vendor 开放），实际只能重新授权 Claude 与 Grok 账号。capabilities 追加 `accounts.reauthorize`、`accounts.apply_oauth_preserve_status`。部署注意：无迁移、无 wire 改动；暂存与 OAuth 会话一样只在单实例内存，多实例时重试要打到同一实例、重启即丢；UpdateAccount 整行写入会递增 config_version（ETag 变）；Gemini 换码后探测 project_id 失败时令牌丢失（既有行为）只能重新生成链接；Claude generate-auth-url / exchange-code 对 vendor 的 proxy_id 不按工作区校验仍是既有越权，见 BACKLOG（高优先级）；Web 不改） |
| C11 发现的越权：Claude 授权接口不按工作区校验 vendor 的 proxy_id | ✅ | `cf575e53f`（/admin/accounts 下 generate-auth-url、generate-setup-token-url、exchange-code、exchange-setup-token-code、cookie-auth、setup-token-cookie-auth 经账号写前缀对有账号管理档的 vendor 开放，而 OAuthService 按 proxy_id 用不过滤工作区的 GetByID 取代理，vendor 可借别家或站长代理出网，生成链接时的代理还会存进会话被后续换码沿用。现在六个接口先过 handler 的 constrainVendorOAuthProxy：站长原样放行；vendor 需账号管理档，proxy_id 经带作用域的 AdminService.GetProxy 校验，不属于本工作区返回 404 `PROXY_NOT_FOUND` 且不发上游请求；不传、null 或 <=0 视为不用代理；缺作用域 403。OAuthHandler 注入 AdminService，wire_gen 重新生成，go.sum 无变化。其他平台：OpenAI / Gemini / Antigravity 同类接口本就不对 vendor 开放，Grok 已强制用账号代理，新增路由守卫测试固定开放范围。与规划方案不同的取舍：没有照 BACKLOG 建议改成“vendor 必须带 account_id、代理取账号自己的”或“只给站长”，因为 vendor 现在能用这些接口新建 Claude 账号，那两种做法会让 Web 上 vendor 新建 Claude OAuth 账号失效；按工作区校验 proxy_id 已堵住借用。部署注意：vendor 传别家或站长代理由放行变为 404；站长把平台代理绑给 vendor 账号的存量情况下，vendor 在 Web 重新授权该 Claude 账号会带上账号 proxy_id 而失败，需改绑本工作区代理或站长代为授权（与 Grok 重新授权、reauthorize 规则一致）；站长不变，无迁移，Web 不改。另发现账号新建 / 修改的 proxy_id 同样不按工作区校验，已记 BACKLOG 高优先级） |
| C16 today-stats/batch 返回 failed_account_ids / degraded，有失败项时不写缓存 | ✅ | `9a26a1a55`、`2d67183f3`（审查修正：只改说明与测试，failed_account_ids 实际按账号 ID 升序去重（handler 先用 normalizeInt64IDList 排序），不是请求顺序，已加测试锁定并写进 API_ERROR_CODES；降级时不写缓存导致查询放大一条按需求保留，记入 BACKLOG）（服务层新增 GetTodayStatsBatchDetailed 返回 (stats, failedIDs, degraded, err)，旧 GetTodayStatsBatch 签名与“永远成功、失败补 0”语义不变、内部改调新方法；data 只增 `failed_account_ids`（非 nil，按账号 ID 升序去重、与请求顺序无关，App 应按 ID 集合匹配，只含按工作区收窄后的账号）与 `degraded`，stats 结构不变、失败项仍补 0；有失败项时跳过 30 秒快照缓存、不发 ETag（X-Snapshot-Cache=miss），没有失败项时照常缓存与 304；全部失败返回 503 `ACCOUNT_STATS_UNAVAILABLE`（已登记 stable_error_codes_test 与 docs/API_ERROR_CODES.md）；ID 为空、收窄后为空的早返回也带两个新字段；批量 SQL 失败与部分失败各打一条聚合 WARN，不再静默吞错。**与文档不同 / 补充**：degraded 按“走了逐个查询的回退路径”定义（含仓储不支持批量，生产仓储都支持，等价于批量 SQL 失败）；回退后全部成功时 degraded=true 且照常缓存，30 秒内命中缓存的响应 degraded 仍为 true（数据准确）；批量 SQL 成功但结果里没有某账号按“今天没有请求”补 0、不算失败；capabilities 追加 `accounts.today_stats_failures`。部署注意：无迁移、无新路由、无 wire 改动，vendor 开放范围不变；**行为变化**：请求的账号全部查询失败时由 200 + 全 0 改为 503，Web 账号列表的今日统计进入错误态而不是显示 0（只请求 1 个账号且失败也属于此情况）；部分失败时 Web 显示不变；客户端断开导致 ctx 取消时同样走 503 并打 WARN / ERROR 日志） |
| C17 today-stats/batch 可按分组统计 | ✅ | `7a216b09f`、`bb7310d69`（审查修正：带 group_id 的缓存键改为 `accounts_today_stats:g<group_id>:<YYYY-MM-DD>:<ids>`，日期取服务器时区 timezone.Today()，跨零点不再复用昨天的分组今日，已加 synctest 跨零点测试；不带 group_id 的键保持原样（既有行为，记入 BACKLOG）；共享分组越权测试改为桩真正剔除别家账号，并断言仓储与响应只含本家账号、vendor 不命中站长写入的缓存。部署注意：仅进程内缓存键变化，升级后首次分组请求全部未命中一次）（请求体只增可选 `group_id`，带上时只统计 usage_logs.group_id（请求时 Key 所属分组）等于它的今日行，与 groups/usage-summary 同口径，data 另回显 `group_id`；不带或传 null 时取数路径、缓存键、响应与原来逐字一致，Web 不动；仓储新增 GetAccountWindowStatsBatchByGroup（同列同口径，只多 `AND group_id = $3`，非正数直接报错），服务层新增 GetTodayStatsBatchByGroup，与 C16 的 Detailed 同形返回、通过可选接口读仓储；“今天”仍是 timezone.Today()，已用测试锁定与站长分组汇总的 GroupUsageTodayStart 同一时刻（含夏令时切换日）；缓存键 `accounts_today_stats:g<group_id>:<ids>`，分组之间、分组与不分组之间不串用；group_id ≤ 0 返回 400 `INVALID_GROUP_FILTER`（新 service 变量，与 D02 同 reason，已登记 stable_error_codes_test 与 docs/API_ERROR_CODES.md）；vendor 先经 FilterGroupIDsByScope 校验分组授权，未授权返回 404 `RESOURCE_NOT_FOUND`、不收窄账号也不取数，授权后仍按工作区收窄账号，共享分组里也只含本工作区账号的用量；capabilities 追加 `accounts.today_stats_group`。**与文档不同 / 补充**：按交叉审查裁定，分组路径不做逐个回退，SQL 失败或仓储不支持分组读取时整体返回 503 `ACCOUNT_STATS_UNAVAILABLE`、不缓存，绝不退回不分组或补 0 的数字，成功时 `failed_account_ids=[]`、`degraded=false`；站长传不存在的分组不报错、统计为 0（省一次查库）；vendor 视角的 groups/usage-summary 仍按请求 timezone 算“今天”，与本接口（服务器时区）可能不同，记入 BACKLOG。部署注意：无迁移、无新路由、无 wire 改动，vendor 开放范围不变；老服务端会静默忽略 group_id 并返回不分组的数据，App 以 capabilities 或响应回显的 group_id 判断过滤是否生效） |
| C15 账号实时数据批量接口 runtime/batch | ✅ | `7d85650e4`、`552fe4a44`（审查修正：GetAccountConcurrencyBreakdownBatch 原先忽略探测槽位读取错误，普通槽位读成功、探测读失败时报 probe=0 且 current 含探测占用；现在探测读失败也整体返回错误，runtime/batch 两个并发字段为 null、列表与详情 concurrency_available=false；行为变化：仅这种情况下列表与详情的 current_concurrency 由原始槽位数变为 0 占位，调度器不受影响）（新路由 `POST /api/v1/admin/accounts/runtime/batch`，请求体 `{"account_ids":[...]}`，查询参数可选 `include_window_cost`（默认 1，传 0 跳过窗口费用 SQL）；data 为 `{sampled_at, items:{"<id>":{...}}}`，sampled_at 为 RFC3339 UTC，时间字段统一 UTC；**口径**：本接口并发读取失败时 `current_concurrency` / `probe_concurrency` 为 null 且 `concurrency_available=false`，列表 full / lite 与详情（含新建、更新等返回）只增 `concurrency_available`，失败时 `current_concurrency` 仍为 0（兼容 Web），App 两处都以 `concurrency_available` 为准；current_rpm、scheduling_rpm、active_sessions、current_window_cost 失败或不适用时省略；先 FilterAccountIDsByScope 收窄、再 GetAccountsByIDs 复核，不存在或越权的 ID 直接不出现在 items 里；List 的采样抽成 sampleRuntime 与新接口共用，每页每类计数仍只读一次；vendor 按开放方案：登记进 vendorBatchAccountRoutes，exact POST + permitAccountRead（AccountManage 或 MonitorView 任一）；只读 sat_ 令牌新增「方法 + FullPath」精确放行表，放行 POST runtime/batch 与 POST today-stats/batch，usage/batch 仍拒绝；capabilities 追加 `accounts.runtime_batch`。**与文档不同 / 补充**：超过 200 个返回 400 `TOO_MANY_IDS`（metadata.max=200、field=account_ids），沿用 E12 批量读上限的同一 helper，而不是规划里的 TOO_MANY_ACCOUNTS（那是写接口的 reason、不带 metadata）；handler 调 SkipAudit，这个只读轮询 POST 不写审计日志；5 秒快照缓存未做（见 BACKLOG）。部署注意：无迁移、无 wire 改动，新增一条路由；**行为变化**：列表与详情响应多一个字段（列表 ETag 随之变化一次）；只读 sat_ 令牌现在可调用 today-stats/batch；runtime/batch 不进审计日志） |
| C14 账号列表多值 / 派生状态筛选、urgency 排序、include_counts | ✅ | `c9df0a52f`（`GET /api/v1/admin/accounts` 只增参数：status 支持逗号分隔多值（并集，去空白、去重，大小写敏感），单个值（不含逗号）原样走旧谓词，只有逗号与空白时仍按原样匹配、结果为空；新增派生值 `overloaded`（active 且 overload_until>NOW()）、`needs_attention`（error，或 active 且处于过载 / 限流 / 临时不可调度任一窗口）、`schedulable_now`（按 Q18，等于分组“可用”数 groupAccountAvailableSQL 与 D02 available），`active` 含义不变、仍包含过载账号；`unschedulable` 仍是旧口径（过载又停调度的账号也算进来，D02 判为 overloaded），App 胶囊与组头计数在这类边角账号上可能差一；去重后超过 16 个值返回 400 `INVALID_ACCOUNT_STATUS_FILTER`（metadata.max=16，已登记 stable_error_codes_test 与 sub2 `docs/API_ERROR_CODES.md`）。`sort_by=urgency`：error=0 > 限时窗口=1（按 GREATEST(overload_until, rate_limit_reset_at, temp_unschedulable_until) 从近到远，即按最晚解除的窗口）> 暂停=2（schedulable=false 或到期自动暂停，按 D02 口径）> 其他非 active=3 > 正常=4，同级按 name、id，判定顺序同 D02（error 与非 active 先于窗口）；`sort_order=desc` 整体反转。`include_counts=1`（true / yes / on 同义）时 data 追加 `counts{all, needs_attention, error, overloaded, rate_limited, temp_unschedulable, unschedulable, inactive, schedulable_now}`（**比文档多 5 个键**，每个状态值都有对应计数；App 的“受限”数 = needs_attention − error，两者不相交），契约为 counts[k] 等于其他筛选不变、status=k 时的 total，all 等于不带 status 的 total，不受当前 status 影响；计数复用 accountListFilteredQuery（平台、类型、搜索、分组含 ungrouped、隐私、工作区收窄与软删除）一条 `COUNT(*) FILTER` SQL（ent Aggregate），已用集成测试锁定逐项等于列表 total、vendor 只计本工作区；counts.inactive 只算 status='inactive'（与筛选一致，disabled 等只计入 all，见 BACKLOG）；仓储不支持计数（测试替身）时省略 counts；计数失败整页返回错误。ETag 只在带 counts 时把它算进去，不带 include_counts 时 payload 与旧版逐字节一致（测试按旧结构手算 sha256 对比），老客户端 304 不受影响；带 counts 时只要计数变化就不会 304。计数走可选接口 AccountListCountsRepository（未改 5 个 AccountRepository 桩），AdminService 新增 CountAccountsForList（站长 / vendor 带分组时先做分组绑定校验，与 ListAccounts 一致），stubAdminService 同步；状态与排序常量 `service.AccountListStatus*`、`AccountListSortUrgency` 供 C13 引用；capabilities 追加 `accounts.list_query`。**与方案不同**：pages 复用 B09 的 response.PaginatedPayload，带 counts 时用内嵌 PaginatedData 的结构，保证分页字段序列化与 Paginated 一致；sort_by=today_cost、Web 筛选新选项未做（见 BACKLOG）。部署注意：无迁移、无新路由、无 wire 改动，vendor 开放范围不变（GET /admin/accounts 原本就按 permitAccountRead 开放，新参数只作用于已收窄结果）；**行为变化**：status 带逗号的请求原来按原样匹配、必然为空，现在返回并集；账号导出、upstream-billing-rates、调度分过滤池等共用列表筛选的路径同样获得多值、派生值与 urgency；超过 16 个不同值的请求由 200 空结果改为 400；旧派生值仍用应用时钟、计数用数据库时钟，时钟偏差时 counts 与 total 可能差 1（见 BACKLOG）） |
| C13 运行时平台目录与枚举 meta/catalog | ✅ | `1b1c2cc20`、`74855fff3`（审查修正：vendor 版 platform_auth 去掉授权接口对 vendor 不开放的 OAuth 方式——openai、antigravity 只剩 apikey，gemini 为 apikey+service_account，anthropic 的 oauth / setup-token 走 /admin/accounts、仍保留；新增中间件测试按 vendorRouteAllowed 核对 vendor 版下发的 OAuth 方式与授权接口可达性一致。部署注意：vendor 的 ETag 随之变化，站长版不变）（新路由 `GET /api/v1/admin/meta/catalog`，纯内存、不查库；data 为 platform_catalog（BuildPlatformCatalog() 原样，测试锁定与 platformCatalog.builtin.json 一致）、account_types、platform_auth、account_status_filters、request_types、error_phases、user_roles、api_protocols。**与文档不同**：account_status_filters 共 9 项，直接含 C14 的 overloaded / needs_attention / schedulable_now；user_roles 多了 vendor（与 CreateUserRequest 的 oneof 一致）；另加 api_protocols（adaptive / chat_completions / anthropic / responses）；error_phases 为 7 个标准 phase（request / auth / account_auth / routing / upstream / network / internal）；account_types、user_roles 由反射读 binding 标签的测试锁定。platform_auth 是照 Web CreateAccountModal 新建的显式表（anthropic 5 种、openai 与 grok 为 oauth+apikey、gemini 加 service_account、antigravity 为 oauth+apikey——Web 的“上游”选项以 apikey 创建，App 要把 antigravity+apikey 显示为“上游中转”；其余具体平台默认 [apikey]），只是表单提示、不参与建号校验；按作用域裁剪为“当前身份可新建的平台及认证方式”：站长完整、有账号管理档的 vendor 去掉 grok（与 WORKSPACE_GROK_ACCOUNT_CREATE_FORBIDDEN 共用 accountCreatePlatformAllowed）并去掉走不通的 OAuth 方式（见上）、无账号管理档或缺少作用域为 {}，因此不同身份 ETag 不同，App 切换账号或站点后应清掉目录缓存。ETag 复用 B09 的 writeSuccessWithETag（Cache-Control: private, no-cache；Vary: If-None-Match；支持 W/），没有另加长期 max-age。**vendor 开放且 permit 为 nil**，比文档建议的 permitAccountManage 更宽（内容是编译期常量，已随公开 Web 产物分发，不含工作区数据）；维护者要收紧时把 vendor_routes.go 那条规则的 permit 改成 permitAccountManage 即可。不豁免合规守卫，未确认合规时 423，App 用内置目录兜底。capabilities 追加 `meta.catalog`。第二期 credential_fields 未做、Web 不改（见 BACKLOG）。部署注意：无迁移，新增一条路由与 wire 改动，无新错误 reason） |
| C19 账号页编辑深链（Web） | ✅ | `1ef27faaf`、`4320919e8`（审查修正：search 改为按完整字符、以 UTF-8 字节计截到 100，与后端 `search[:100]` 字节口径一致，以前按 UTF-16 码元截断会劈开 emoji 代理对，axios 编码参数抛 URIError、列表加载失败；深链在等待期间若用户已打开任何弹窗或已离开本页就放弃，不再覆盖用户正在编辑的另一账号；axios 拦截器在会话失效硬跳登录页时，/admin 下的页面带上 `redirect=当前路径+query`，浏览器留着过期或已吊销会话时深链登录后也能弹出（同一次失效以第一次 401 的地址为准），非管理端页面仍跳 /login；`/admin/me` 新增能力 `web.accounts_edit_deep_link`，只在二进制内嵌前端（-tags embed）时下发，前端单独部署时不下发，App 照退路处理。部署注意：管理端页面会话失效后登录完成回到原页面而不是默认首页。以下为首个提交的说明：只改 Web 前端，后端不动：无新路由、无新错误 reason、无迁移、vendor 白名单不变。`/admin/accounts?edit=<id>[&search=<名称>]`：edit 只接受十进制正整数（安全整数，允许首尾空白与前导零），数组取第一个非空值；search 去首尾空白后截到 100 个字符（与后端截断一致），挂载时预填列表筛选，首次列表请求即带搜索；随后 router.replace 把 edit 与 search 一起从地址栏去掉（无论成败，其余 query 保留），所以搜索只是一次性预填、刷新后不保留；代理与分组加载完成后再调 handleEdit 打开编辑弹窗，账号不存在或 vendor 越权时沿用现有提示（toast 显示后端 message，如英文 account not found），id 非法时提示“链接中的账号 ID 无效：{id}”（超过 32 个字符截断）；只在挂载时处理一次，SPA 内同页改 query 不响应。**与文档不同**：route / router 用 `inject(routeLocationKey / routerKey, null)` 取得而不是 useRoute / useRouter，语义相同，但未安装 router 时为 null 且不产生注入告警。首个提交未加能力标记（已由审查修正补上，见上）。验证时发现 ChannelMonitorView 的 3 个既有 spec（9 个用例）在 main 上本来就因缺少 Pinia 失败，与本条无关，见 BACKLOG。部署注意：只需重新构建前端，无迁移、无配置变化） |
| C06 混合渠道 409 补 code、reason、metadata、details | ✅ | `4f0634ee7`（新建 POST、编辑 PUT 与 PATCH（C03 新增，App 编辑分组走它）、批量编辑 bulk-update 四处 409 只增字段：保留 `error="mixed_channel_warning"` 与原文 message，新增 `code`=409、`reason`=`MIXED_CHANNEL_WARNING`、`metadata`（全字符串，group_id 为十进制字符串）与 `details`（group_id 为数字，与 check-mixed-channel 同形）；check-mixed-channel 的 200 结构不变。与文档不同：`current_platform` / `other_platform` 沿用现有的首字母大写取值 `Antigravity` / `Anthropic`，不是文档示例的小写，App 不要拿它当平台枚举；PATCH 也覆盖（文档写成时还没有）。新增能力 `accounts.mixed_channel_details`，看到它可省掉 check-mixed-channel 预检、直接用 409 的 details 弹框。新建接口仍强制 Idempotency-Key（H08 之前），确认后带 `confirm_mixed_channel_risk=true` 重发时请求体指纹变了，必须换新 key，否则 409 `IDEMPOTENCY_KEY_CONFLICT`；按 reason 区分各种 409。顺带修越权探测：CreateAccount 的分组授权校验提到混合渠道检查之前（默认分组解析之后），vendor 绑定未授权分组时由带别家分组名的 409 改为 404 `RESOURCE_NOT_FOUND`，站长不变。Web 新建弹窗 409 兜底改读 `error.status` / `error.error` / `error.message`（以前读 `error.response` 永远走不到）。部署注意：Web 拦截器 reject 的 `error.code` 在这几个 409 上从 undefined 变为 409，三个账号弹窗只读 status / error / message，不受影响；无迁移、无新路由。未做的可选项见 BACKLOG） |
| H08 Web 不带 key 的强制幂等写接口改为可选幂等 | ✅ | `a11ad54f1`（11 个接口中兑换码生成已由 G03 改为可选（`executeAdminOptionalBatchMoneyWrite`），本条改其余 10 个：代理新建、账号新建 / 批量新建 / 数据导入 / Codex 会话导入、用量清理任务新建、订阅续期、系统更新 / 回滚 / 重启，scope、payload、TTL 不变；不带 key 时即使 `observe_only=false` 也直接执行，带 key 时重放、409 冲突、进行中、存储不可用 fail-close 照旧；Web 与 App 都不用改，不加能力标记。helper：新增返回结果的 `executeAdminOptionalIdempotent`（账号新建用，混合渠道 409 仍走 C06 的 respondMixedChannelConflict，重放不重复调度探测）；`executeAdminOptionalIdempotentJSONWithOptions` 改为复用 `writeAdminIdempotentResult`，可选与强制共用一条响应路径，后续 G06 / H07 / E10 直接在其上加变体。**与文档不同**：存储不可用改按 reason `IDEMPOTENCY_STORE_UNAVAILABLE` 判断而不是 503 状态码，业务自身的 503（如 `USAGE_CLEANUP_DISABLED`）不再计入存储不可用指标；go/ast 守卫测试覆盖全部 11 个 handler 方法（含 restart、generate），防止改回强制版本；`executeAdminIdempotentJSON` / `executeAdminIdempotent` 保留并注释为只用于调用方都带 key 的接口。既有限制：带 key 的大响应（数据导入、批量新建）存进幂等表时超过 64KB 会被截断，重放解码失败返回 503，与以前相同。部署注意：`observe_only=false` 时这 10 个接口不再对不带 key 的请求返回 400 `IDEMPOTENCY_KEY_REQUIRED`；账号新建带 key 时响应多一个 `X-Idempotency-Expires-At` 头；可选幂等接口（含 users.update 等既有调用方）在存储不可用时多记一次 handler_fail_close 指标与日志，HTTP 响应不变；`deploy/config.example.yaml` 的 observe_only 注释与 `docs/API_ERROR_CODES.md` 混合渠道条目的 key 说明已同步。无迁移、无新路由、无新 reason。审查修正 `e5124dd97`：Q16 的 11 个漏了用户端 `POST /api/v1/keys`（新建 API Key，Web 不带 key），`executeUserIdempotentJSON`（唯一调用方）改为可选幂等，scope `user.api_keys.create`、payload、TTL 不变；部署注意：`observe_only=false` 时该接口不再对不带 key 的请求返回 400 `IDEMPOTENCY_KEY_REQUIRED`，`deploy/config.example.yaml` 注释与 sub2 `docs/API_ERROR_CODES.md` 已同步。其余读取 key 的接口（batch image、渠道监控探测、Claude 重置兑换、返利提取）Web 调用时都带 key，不受影响。未做的可选项见 BACKLOG） |
| G06 其余管理写接口支持可选 Idempotency-Key | ✅ | `cfb902f5b`（10 个接口：POST / PUT users、POST / PUT / DELETE groups、PUT accounts/:id、:id/schedulable、bulk-update、:id/refresh、batch-refresh，scope 为 admin.users.* / admin.groups.* / admin.accounts.*；不带 key 时行为与响应不变。新增 helper `executeAdminOptionalWrite`（返回结果）/ `executeAdminOptionalWriteJSON` 与 `keyedExecutionTimeout`：只有带 key 才脱离客户端连接执行，并受 30 秒（用户、分组、单账号编辑、启停调度）/ 60 秒（bulk-update、单账号刷新）/ 120 秒（batch-refresh）上限约束，不接管卡住的执行；后续 H07 / E10 直接复用。PUT users 去掉“只在带 concurrency 时”的条件，scope、payload 不变；**与文档不同**：POST users 的指纹 payload 去掉 password（交叉审查要求，E10 只在闭包里加账本），同 key 只改密码重发得到首次创建的重放。另修：分组请求的 optionalLimitField 序列化恒为 {}，同 key 只改限额会被当成重放，已加 MarshalJSON 与反射守卫测试。混合渠道 409 带不带 key 信封一致（C06 的 respondMixedChannelConflict）；Refresh 的 404 预检、BatchRefresh 空 ID 的 400、step-up 与 simple-mode 校验都在封装之前。新增能力 `admin.idempotent_writes`；6 个 IDEMPOTENCY_* reason 登记进 TestStableErrorReasons 与 sub2 `docs/API_ERROR_CODES.md`（含响应头说明与接口表）。部署注意：带 key 时业务错误记为可重试失败，5 秒内同 key 重发返回 409 `IDEMPOTENCY_RETRY_BACKOFF`，确认混合渠道后请求体变了必须换 key；带 key 的 batch-refresh 120 秒到时未完成的账号记为失败；重放快照超过 64KB 返回 503，只能读回核对；Web 改并发时本来就带 key 调 PUT users，这类请求现在脱离客户端连接执行、受 30 秒上限约束，响应不变。无迁移、无新路由、无新 reason，vendor 路由权限不变。PATCH accounts/:id 未纳入，见 BACKLOG。审查修正 `9256ccf3c`：PUT users 的指纹（及调整账本 action id）同样不再含明文新密码，改为只记 `password_set`；不带密码时 payload 与旧结构序列化逐字节一致，Web 改并发的已存记录照常重放。部署注意：同 key 只改密码重发为首次修改的重放，同 key 去掉或加上密码为 409 `IDEMPOTENCY_KEY_CONFLICT`；升级前已存的带密码记录在 24 小时 TTL 内过期，期间同 key 重发会冲突。审查修正 `dbd37e949`：PUT groups 的 `video_model_prices` 去掉 omitempty，不传（不改）与 `{}`（清空按模型视频价）的指纹不再相同，同 key 在两者之间切换为 409 `IDEMPOTENCY_KEY_CONFLICT`；新增反射守卫：指纹 payload 里带 omitempty 的 map / slice 必须登记为“nil 与空值同义”。部署注意：带 key 的 PUT groups 指纹多了 `"video_model_prices":null`，升级前 24 小时内存下的记录同 key 重发为 409，换新 key 即可。未改：POST / PUT users 不用 HMAC 把密码纳入指纹（按交叉审查裁定与 `9256ccf3c`，指纹不含密码，同 key 只改密码为首次的重放，已写进 sub2 `docs/API_ERROR_CODES.md`）） |
| H07 公告新建支持可选 Idempotency-Key | ✅ | `5e5b1549c`（`POST /api/v1/admin/announcements` 改用 G06 的 `executeAdminOptionalWriteJSON`，scope `admin.announcements.create`，指纹 payload 即请求体，TTL 24 小时。不带 key 时每次照常新建、跟随请求上下文、无额外时限、无幂等响应头，`observe_only=false` 也不返回 `IDEMPOTENCY_KEY_REQUIRED`，Web 不变；带 key 时同 key 同体重放首次那条公告（`X-Idempotency-Replayed: true`），不同体或另一个管理员复用 key 为 409 `IDEMPOTENCY_KEY_CONFLICT`，存储不可用 503 fail-close。**与文档不同**：文档建议的 `executeAdminOptionalIdempotentJSON` 没有执行上限，手机断线会让记录停在 processing、同 key 重试长时间 IN_PROGRESS；按交叉审查裁定改用 G06 的 keyed 变体：只有带 key 才脱离客户端连接、上限 30 秒，不接管卡住的执行（业务层无去重），没有另建 helper。请求绑定、subject 校验在封装之前，绑定失败的 400 不占用 key。新增能力 `announcements.idempotent_create`；G06 的 AST 守卫与指纹不透明字段守卫纳入公告新建；vendor 守卫补 POST（仍为站长专属）；sub2 `docs/API_ERROR_CODES.md` 幂等键一节补公告说明；IDEMPOTENCY_* reason 已由 G06 登记。部署注意：带 key 时业务校验失败（如 `ANNOUNCEMENT_TITLE_INVALID`）记为可重试失败，5 秒内同 key 重发 409 `IDEMPOTENCY_RETRY_BACKOFF`，改了内容必须换 key；正文超过约 64KB 时同 key 重放返回 503（已在 BACKLOG 的 G06 64KB 条目覆盖）。无迁移、无新路由、无新 reason） |
| H06 公告已读汇总与已读名单筛选 | ✅ | `3f0c855bb`（新路由 `GET /api/v1/admin/announcements/:id/read-summary`，data 为 `{announcement_id,total_users,eligible_count,read_count,eligible_read_count,computed_at}`，computed_at 为 RFC3339 UTC；只统计未删除用户，eligible 按当前余额与当前有效订阅（status=active、未过期、未软删除）计算，read_count 含读后已不符合条件的人；草稿照常返回；404 ANNOUNCEMENT_NOT_FOUND、id 非法 400。`GET /admin/announcements` 与 `/:id` 可选 `include_read_stats=true`（parseBoolQueryWithDefault，1 / yes / on 也算），每项多 `read_stats{eligible_count,read_count,eligible_read_count}`，不带时响应逐字不变。read-status 可选 `read_state=read|unread`（不区分大小写）、`eligible=true|false`（strconv.ParseBool）与 `sort_by=read_at`（未读排最后，同时间按用户 id，sort_order 照常）；带任一参数时走单条 SQL（COUNT 一条、列表一条），total / pages 按过滤后计算，行字段不变；非法取值 400 `INVALID_READ_STATUS_FILTER`（已登记 TestStableErrorReasons 与 sub2 `docs/API_ERROR_CODES.md`）。投放条件翻译成 SQL 的 `announcementTargetingSQL`，余额按 double precision 比较以与 Go float64 逐位一致，集成测试 18 组条件逐用户对比 Matches。不带新参数时仍走原 ListWithFilters 路径（排序、搜索、total 与原来一致），只消除 N+1：eligible 改用批量预加载的订阅并按 IsActive 过滤到期，每次请求查询数固定、与 page_size 无关。新增能力 `announcements.read_stats`；vendor 不开放（补守卫测试）。**与文档不同 / 注意**：新路径的搜索排除已软删除的 API Key，老路径（ent HasAPIKeysWith）不排除，按已删除 Key 明文搜索时带不带新参数结果不同；新路径未知 sort_by 回落到 id（与老路径一致，不报错）；list 带 include_read_stats 时按公告逐条汇总、不缓存（见 BACKLOG）。部署注意：无迁移；NewAnnouncementReadRepository 改为注入 *sql.DB（wire 已重新生成）；新增一条路由；**行为变化**：老路径 read-status 不再逐用户调 ListActiveByUserID，eligible 结果不变；每次汇总全表扫 users，几万用户量级为毫秒到百毫秒） |
| E06 Key 状态枚举固定 + effective_status | ✅ | `173dc7a95`、`18bba07f0`（审查修正：只改注释与测试，计算不变——effective_status 只反映标准模式（run_mode=standard）的鉴权结果；RUN_MODE=simple 时主鉴权与 Gemini 鉴权在过期、额度检查之前就放行，只拦 inactive，effective_status 为 expired / quota_exhausted 的 Key 照常可用；App 在 `/admin/me` 的 server.run_mode 为 simple 时应把 expired / quota_exhausted 当作可用并计入“活跃 N”；新增 simple 模式对拍测试锁定这一点）（dto.APIKey 新增只读 `effective_status`，所有经 APIKeyFromService 的接口自动带上（用户侧 /api/v1/keys、管理端 users/:id/api-keys、groups/:id/api-keys、GET / PUT / POST api-keys、使用记录与用户内嵌 Key）；status 原值不变、不迁移数据。**与文档第 4 点不同**：按鉴权实际顺序计算——status 不是 active / quota_exhausted / expired（含 inactive、历史 disabled、未知值）→ inactive；库里 quota_exhausted / expired 原样；再判运行时过期 → expired；最后判额度用满 → quota_exhausted；所以已过期且额度用满的 active Key 返回 expired，不是 quota_exhausted；主鉴权与 Gemini 鉴权都有对拍测试锁定。管理端 `PUT api-keys/:id` 收到 `status=disabled` 归一为 inactive 写库（previous 照常是旧值），其他非法值仍 400 INVALID_API_KEY_STATUS；用户侧仍只接受 active / inactive。只反映 Key 自身：用户 / 分组停用、IP 限制、余额与订阅额度不算在内；墓碑 Key（key_masked 为空）的 effective_status 可能是 active，App 以 key_masked 为空判断已删除。vendor 经使用记录脱敏后的 Key 不带该字段（空字符串，Q19）。列表 status 筛选仍按库里原值，“活跃 N”由 App 按 effective_status 自己统计。capabilities 新增 `api_keys.effective_status`。部署注意：管理端 PUT 从拒绝 disabled 改为接受（放宽输入）；读取时按服务器时钟计算，带 ETag 的用户列表在内嵌 Key 到期前后 ETag 会变化） |
| E11 管理端 Key 列表回填 current_concurrency | ✅ | `e52309724`（GET /admin/users/:id/api-keys、/admin/groups/:id/api-keys 每页一次批量读取，与用户侧 GET /keys 同源；**有意扩展**：GET /admin/api-keys/:id 也回填（E01 刷新 Key 卡片用），PUT / POST 写接口响应不回填；Redis 读失败按 0 并记 Warning，列表照常 200，App 无法区分“0 并发”与“读不到”；NewGroupHandlerWithConfig 改为 5 个参数（concurrencyService 在 cfg 前），AdminAPIKeyHandler 改用 wire 提供者 ProvideAdminAPIKeyHandler，后续条目按新签名写；未做可选的 concurrency_available 与管理端按 current_concurrency 排序（见 BACKLOG）；`/admin/me` capabilities 含 `api_keys.current_concurrency`；部署注意：管理端打开 Key 列表时多一次 Redis 管道读取，每个 Key 4 条命令、3 秒超时，与用户侧相同） |
| F04 分组四类成员计数 | ✅ | `ca0fd305a`（GET /admin/groups、/groups/all、/groups/:id 与 PUT /groups/:id 的分组对象（admin DTO 与 simple 模式）新增 `error_account_count`、`idle_account_count`，不加 omitempty；account_count = active + rate_limited + error + idle。error 与 D02 的 state=error 同口径；idle 为减法余数（最小 0），含停用、停止调度、到期自动暂停，**也含停了调度但仍在限流 / 过载 / 临时不可调度窗口的账号**（分组列表按调度口径，D02 把它算进限时桶并另记 stopped）。与 D02 对账：通常 idle = D02 的 paused + inactive + stopped；例外是已到期、开了到期自动暂停、调度开关仍开着又在限时窗口里的账号，分组列表算 idle，D02 先判窗口算进 rate_limited 等限时桶且不记 stopped，到期任务（每分钟一次）把它停调度之前 idle 比 paused + inactive + stopped 多出这类账号数（审查修正 `52e577589` 补反例测试、改正注释），App 色格条以分组接口为准。分组批量成员接口的 counts 也带这两项；capabilities 含 `groups.account_buckets`。**部署注意**：顺带修复 vendor 越权——/groups/all 三条路径与 PUT /groups/:id 响应此前回显共享分组的全站账号计数，现在按本工作区重算，vendor 看到的数字会变小（admin 不变）；vendor 的 PUT 在写库前多一次聚合查询，失败则整个 PUT 报错且不写库。POST 新建分组的响应不加载计数，新字段为 0，四项之和等式只对 GET 与 PUT 成立；idle 未拆成 paused / inactive，见 BACKLOG） |
| F05 capacity-summary 按分组过滤 | ✅ | `13682ad0e`（`GET /api/v1/admin/groups/capacity-summary` 新增可选 `group_id`（可重复，每个值是单个正整数）与 `group_ids`（逗号分隔，可重复），两者取并集去重；响应仍是数组、形状不变，行顺序与全量一致（sort_order, id）；停用分组略去，全部停用时 data 为 `[]`；启用但没有可调度账号的分组返回全 0 行；参数只有空值或逗号（如 `?group_id=`）等于不带参数、返回全量，App 在 id 列表为空时不要发这个参数；非正整数、group_id 里带逗号返回 400 `INVALID_GROUP_ID`；任一分组不存在或已删除整次 404 `GROUP_NOT_FOUND`（metadata.group_id 为第一个缺失的 ID，不做部分成功）；vendor 先授权、后查存在性，未授权 404 `RESOURCE_NOT_FOUND`（不带 metadata）；service 新增 GetGroupCapacityByIDs，与全量共用抽出的 capacitiesForGroups（vendor 走 Scoped 批量 SQL 收窄，降级逐组路径对 vendor 拒绝不变），结果仍经 filterByGroupScope 行过滤；capabilities 追加 `groups.capacity_filter`。**与方案不同**：去重后超过 100 个返回 400 `TOO_MANY_IDS`（metadata.field=group_ids、max=100，复用 E12 的批量上限 helper），不是方案写的 INVALID_GROUP_ID；仓储不支持批量存在性读取时逐个用 GetByIDLite（不加载账号计数）回退，而不是 GetByID；INVALID_GROUP_ID、GROUP_NOT_FOUND 定义为 service 变量登记进 TestStableErrorReasons，并写入 sub2 `docs/API_ERROR_CODES.md`（方案原本不登记）。部署注意：无迁移、无新路由、无 wire 改动，vendor 路由权限不变，Web 不改；不带参数时响应与错误逐字不变；带参数时出错改走带 reason 的错误信封（vendor 落到降级逐组路径时为 404 RESOURCE_NOT_FOUND，不带参数时仍是 500，生产仓储实现了批量接口，走不到）；带参数时多一次存在性查询与一次启用分组列表查询，但只聚合请求的分组） |
| E07 平台限额单平台 PUT / DELETE 与恢复 | ✅ | `b8cccb51d`（新路由 `PUT` / `DELETE /api/v1/admin/users/:id/platform-quotas/:platform` 与可选的 `POST .../:platform/restore`（**已做**），原有整表 PUT 不变、Web 不改；PUT 是替换该平台三档限额而不是合并补丁：缺字段等于 null（不限），0 为禁止，三项全空等于删除（本来没有活跃限额时什么也不做、返回 200，platform_quota 为 null）；没有活跃行时新建一行、用量从 0 起算，不复活软删的旧行（那是 restore 的事）；响应 `{platform_quota, previous}`，单项与 GET 同结构（含 *_window_start，过期窗口按 D14 归零），previous 带写入前的用量，没有则为 null；DELETE 响应 `{removed:true, previous}`，没有活跃限额 404 `USER_PLATFORM_QUOTA_NOT_FOUND`；restore 恢复 deleted_at 最新（同时间取 id 大）的软删行，限额、用量、窗口起点原样保留（含整表 PUT 软删的、很久以前的行；过期窗口在读取与计费时自动归零），响应 `{platform_quota, restored:true}`，已有活跃限额 409 `USER_PLATFORM_QUOTA_ACTIVE_EXISTS`、从没取消过 404 `USER_PLATFORM_QUOTA_NOT_FOUND`；**与文档不同 / 补充**：PUT 请求体严格解码（必须是单个 JSON 对象、拒绝未知字段与尾随数据、上限 1KB），防止字段名拼错被当成三项全空而删掉限额；新接口错误全部带 reason：400 `INVALID_USER_ID` / `INVALID_PLATFORM`（message 仍为 `invalid platform: foo`，composite 也拒绝）/ `INVALID_QUOTA_LIMIT`（`daily_limit_usd must be >= 0`、`must be a finite number`）/ `VALIDATION_ERROR`，503 `SERVICE_UNAVAILABLE`（message 仍为 platform quota service not available），已写入 sub2 `docs/API_ERROR_CODES.md`；service.ErrUserPlatformQuotaNotFound 改为 infraerrors.NotFound（errors.Is 不变）并与新增的 ErrUserPlatformQuotaActiveExists 登记 TestStableErrorReasons；仓储新增 UpsertOneForUser / SoftDeleteOne / RestoreLatestDeleted（事务内 FOR UPDATE 锁住该平台活跃行，写入复用 updateLimitsRow / insertLimitsRow，并发恢复撞部分唯一索引也映射为 409）；整表 PUT 的三档校验抽成 validateQuotaLimitFields 两处共用，文案与状态码不变；成功后只失效该平台的限额缓存；审计 slog `admin.quota_updated`（mode=single，带 before_* 与 removed）与 `admin.quota_restored`；vendor 不开放（/admin/users/* 默认拒绝，加守卫测试）；不加 Idempotency-Key（PUT 写绝对值，DELETE / restore 重放得到 404 / 409，都能安全判断）；capabilities 追加 `users.platform_quota_item`。部署注意：无迁移、无 wire 改动；**行为变化**仅一处：`POST /admin/users/:id/platform-quotas/reset` 的 404 多带 reason=USER_PLATFORM_QUOTA_NOT_FOUND，状态码与 message 不变；开启用量 flusher（flusher_enabled=true）时 DELETE 会随缓存键丢掉 Redis 里还没刷进库的用量，restore 恢复的是库里稍旧的用量（最多落后一个刷新周期），默认关闭 flusher 时没有这个问题；flushOneBatch 记的绝对值覆盖竞态对新写入同样适用；未做的可选项见 BACKLOG；审查修正 `54eee45c4`：三档限额加上限，必须小于 1e10（限额列 decimal(20,10) 的上限），超出时单平台 PUT 返回 400 `INVALID_QUOTA_LIMIT`（message `daily_limit_usd must be less than 10000000000`），原来写库报 numeric field overflow 变成 500；**行为变化**：整表 PUT 共用同一校验，同样的输入由 500 改为 400（只有 message）；单元测试日窗口起点改为当天 0 点，午夜刚过运行不再偶发失败；多级撤销时 restore 恢复到刚删的新行的问题记入 BACKLOG） |
| E08 rpm-status 标明计数是否生效 | ✅ | `fbd178ca7`（`GET /api/v1/admin/users/:id/rpm-status` 只增 `user_rpm_tracked` 与 `per_group[].tracked`，不加 omitempty、false 也返回；口径与网关 checkRPM 一致：分组 tracked = override>0，或没有 override 且分组 rpm_limit>0（override=0 免检为 false），用户 tracked = 用户 rpm_limit>0，不新增查询；**简易模式下一律 false**（比文档字面多一层：CheckBillingEligibility 提前返回、checkRPM 不执行、计数器从不累加）；tracked=true 只表示网关会计数，不保证 used 非零（Redis 故障放行、在 RPM 检查前被拒或分组级先超限的请求不累加用户级计数）；rpm-status 读库里的 override，网关优先用 auth cache 快照，管理员刚改 override 后到缓存失效前可能短暂不一致；按 Q14 **未做**可选的“不限额也计数”（rpm.track_unlimited）与 usage_logs 估算，记入 BACKLOG；顺带把 dto / service 的 User、Group rpm_limit 注释改为“用户级上限始终生效、分组级不覆盖用户级”，Web i18n 文案、Ent schema 注释与列 COMMENT 未动（记入 BACKLOG）；vendor 仍无权访问；/admin/me capabilities 含 `users.rpm_tracked`；部署注意：无迁移、无新路由、无新设置，Web 行为不变；审查修正 `03edad91a`：读分组或 override 失败时接口照常返回（既有行为），tracked 与 limit / source 同为降级值——`source` 为空表示分组读取失败（或已删除）且没读到 override，此时 limit=0、tracked=false 不可信；override 读取失败时回退分组 rpm_limit，网关若有 auth cache 快照里的 override 以快照为准，tracked 可能与实际计数相反；只写进注释并补降级测试，未加错误标记字段） |
| G07 禁止删除已使用的兑换码与 admin_* 记录 | ✅ | `c791938fc`（`DELETE /admin/redeem-codes/:id` 与 `POST /admin/redeem-codes/batch-delete` 改走仓储新方法 `DeleteUnlessUsed` / `BatchDeleteUnlessUsed`，可删条件写在 DELETE 语句里：status<>used、used_by 为空、type 不是 admin_balance / admin_concurrency。**与文档不同**：可删条件额外加了 used_by IS NULL，与 G05 口径一致（G05 之前兑换后又被改成过期 / 禁用的码也受保护）；batch-delete 没有用一条 `DELETE … RETURNING`，而是整批一个事务、每 1000 个 ID 一块“带条件删除 + 查剩余”，剩下的即被跳过的 ID；受保护的单删用新变量 `ErrRedeemCodeDeleteUsed`（与 ErrRedeemCodeUsed 同为 409 `REDEEM_CODE_USED`，errors.Is 互通，message 为 `used redeem codes cannot be deleted`）。batch-delete 响应新增 `skipped_used`、`skipped_ids`（升序，没有时为 `[]`），原有 deleted、message 保留。新增能力 `redeem_codes.delete_guard`；REDEEM_CODE_USED、REDEEM_CODE_NOT_FOUND 登记进 TestStableErrorReasons 与 sub2 `docs/API_ERROR_CODES.md`。部署注意：单删不存在的码由 200 改为 404 `REDEEM_CODE_NOT_FOUND`（Web 只在两人并发删同一个码时会看到报错）；batch-delete 的 deleted 改为实际删除行数，不存在、重复的 ID 不再计入；数据库错误由“吞掉后少计数”改为整批回滚并返回 500；G05 之前遗留的 used_by 不为空但状态不是 used 的码以后删不掉，Web“删除未使用”的提示数量会如实变少。无迁移、无新路由、vendor 仍默认拒绝，Web 前端不改。RedeemCodeRepository 主接口加了两个方法，同步了 6 个测试桩。未做的可选项见 BACKLOG） |
| G08 兑换码真实统计 | ✅ | `92c68a456`（`GET /admin/redeem-codes/stats` 原地改为真实统计，路由不变；查询参数复用列表的 parseRedeemCodeListFilter，type / types / exclude_types / search / batch_id / created_by / created_from / created_to / notes 与列表一致，非法值返回同样的 400 reason；**status 参数忽略**（统计就是状态分布）。保留原字段并填真实值，active_codes = by_status.unused，total_value_distributed 为已使用 balance 码面额净额合计（不含 admin_balance 调整记录，保留 8 位小数）；新增 `by_status{unused,used,expired,disabled}`，口径与列表相同（unused 但已过 expires_at 算 expired，disabled 不看过期），四项之和等于 total_codes。by_type 固定含 balance / concurrency / subscription / invitation / admin_balance / admin_concurrency（缺省 0），trial 为兼容旧响应恒为 0，库里有其他类型时追加键。**与文档不同**：没有手写 `COUNT(*) FILTER` 的一条 SQL，而是从 ListWithFilters 抽出共用谓词（redeemCodeFilterPredicates / redeemCodeStatusPredicate / redeemCodeLapsed），用一条 ent GROUP BY type, status 加一条“已过期仍为 unused”的 COUNT，保证 search 的 ILIKE 转义与 HasUserWith 和列表逐字一致；两条语句不是同一快照，并发写入时单个状态可能有个位误差，挪动数量有上限，四项之和恒等于总数。仓储走可选接口 RedeemCodeStatsRepository（不改 6 个仓储测试桩），不支持时 503 `SERVICE_UNAVAILABLE`。capabilities 含 `redeem_codes.stats`；vendor 不开放（补守卫测试）。部署注意：行为变化——由写死的全 0 改为真实计数；以前任何参数都被忽略并返回 200，现在非法的 types / exclude_types / batch_id / created_by / created_from / created_to 返回 400。Web 没有调用 getStats，不受影响；无迁移、无新路由。未做的可选项见 BACKLOG） |
| E10 充值与调整记录补齐、初始余额入账 | ✅ | `e5e873458`（迁移 256：admin_user_adjustments 加可空 redeem_code_id 与部分唯一索引，无外键、不回填、不碰 append-only 触发器；第 2 点 user-adjustments?user_id= 精确筛选已由 G02 `3293b6b48` 完成，本条不改，列表每行多 `redeem_code_id`（E10 之后的新行才有值）。balance-history 每项新增 `adjustment_id`、`before_value`、`after_value`（8 位小数字符串）、`operator_email`，只有 admin_balance / admin_concurrency 行有值，其余行这四个键为 null；关联顺序：redeem_code_id → legacy_redeem_code_id（223 迁移来的行，before / after 为 null）→ 223 之后、E10 之前的旧行按（用户、类型、created_at=used_at、delta=value）回退匹配，匹配不到为 null；type 过滤分支同样带。新增 `total_recharged_breakdown{redeem,admin,affiliate,promo}`：redeem 为 balance 兑换码正值（含支付订单入账），admin 为 admin_balance 正值，affiliate 为返利转余额，promo 为优惠码赠送；`total_recharged` 语义不变、恒等于 redeem+admin，“总充值”以它为准（不是 users.total_recharged）。Q12：管理员余额净增（add 或 set 上调）在同一事务累加 users.total_recharged，减少不扣。POST /admin/users 沿用 G06 的可选幂等封装（不改成 money write，不带 key 时仍跟随请求上下文），闭包里加账本：初始余额 > 0 时与用户同一事务写账本 + 兼容 admin_balance 行并累加 total_recharged（operation=set、before 0、after 为读回的库内值，source 为 `admin_create_user`，省略 balance 用站点默认值时为 `default_balance`，备注默认“初始余额”），账本写失败则用户不创建；带 key 时响应头 `X-Admin-Adjustment-Action-ID`。**按编排者裁定（Q12 站点 default_balance 入账）已做注册路径**：邮箱注册（含邀请码事务）、第三方首次登录（LoginOrRegisterOAuth 与带 token pair 的两条分支）、pending OAuth 邮箱注册两处、邮箱 OAuth 自动注册，在建用户的同一事务写账本（source=`default_balance`、无操作者、带请求 ID），失败则注册失败；**比裁定多做**：第三方首次绑定按来源赠送的余额改走 AdjustBalanceExact 并入账（operation=add，备注“首次绑定赠送余额”，同样累加 total_recharged）。AuthService 经 wire（ProvideAuthService 多一个参数）注入账本仓储，未注入时（单测、jwtgen）照旧直接写余额。Q13：PUT /admin/users/:id 带 balance（含 0，null 等于不传）返回 400 `USER_BALANCE_NOT_EDITABLE`，在幂等封装之前拦截、不占用 key；服务层 UpdateUser 同样拒绝。**与文档不同**：E05 快捷充值“最近充值”排除无操作者的 default_balance 行，否则新注册用户会挤满头像条（管理员新建用户的初始余额照常出现）。能力 `users.balance_ledger`；新 reason 登记 TestStableErrorReasons 与 sub2 `docs/API_ERROR_CODES.md`；无新路由，vendor 仍拒绝（补了守卫测试）。部署注意：PUT users 带 balance 由静默忽略改为 400（Web 不发这个字段）；部署后管理员充值、新建用户初始余额、注册与首次绑定赠送都会累加 users.total_recharged，百分比余额提醒与快捷充值 low_balance 的阈值随之变大，历史不回填，老用户的 users.total_recharged 仍可能小于 balance-history 的总充值；注册赠送与新建用户初始余额会出现在充值与调整记录、user-adjustments 汇总、用户自己的 /redeem/history（admin_balance 类型，备注“初始余额”）里；pending OAuth 注册回滚删除半成品账号时，已写的赠送记录保留（append-only）。未做的可选项见 BACKLOG：历史 total_recharged 回填、旧行回填 redeem_code_id、Web 来源文案与类型、用户侧区分注册赠送、CSV 加列、开户备注与初始并发入账、回滚冲销。审查修正 `10fdd962a`：首次绑定赠送不再走 AdjustBalanceExact（它要求结果不得为负，而用量计费允许透支，透支用户首次绑定会报 `BALANCE_NEGATIVE`，绑定整体失败且赠送再也补不上），改为同一事务内不带非负约束的精确加余额，透支用户照常加上（-5 + 2 = -3），账本 before / after 可为负值，补了回归测试；管理员余额调整“结果不得为负”的规则不变。审查修正 `77ffc3f83`：`total_recharged_breakdown` 新增 `grant`（注册、第三方首次登录、首次绑定按站点默认值发放的余额，判定与快捷充值“最近充值”相同：source=`default_balance` 且无操作者），`admin` 只含管理员入账（管理员新建用户的初始余额，含取站点默认值的，仍算 admin），`total_recharged` 取值不变，恒等于 redeem + admin + grant；sub2 `docs/API_ERROR_CODES.md` 写明新建用户带 key 时 `X-Admin-Adjustment-Action-ID` 在执行前算出、总会返回，初始余额为 0 或负数时没有对应记录，409 冲突时对应的操作没有执行，App 以响应里新用户的 balance 判断该不该有记录；补了带邀请码注册、token pair 第三方首次登录（含占用失败时用户与赠送一起回滚）、pending OAuth 邮箱注册、邮箱 OAuth 自动注册的账本集成测试；快捷充值测试改用大 limit。部署注意：`total_recharged_breakdown.admin` 不再含站点赠送，多一个 `grant` 键（只有 `e5e873458` 的服务端没有这个键，那时 admin 含赠送）；站点 default_balance > 0 时每个新注册用户与每次首次绑定赠送都会写一条 admin_balance 兼容行，出现在 Web 兑换码管理列表（默认不排除 admin_* 类型）和 `GET /admin/redeem-codes/stats` 的 by_type.admin_balance 计数里；新用户的总充值包含站点赠送。未改：兑换码列表默认排除站点赠送、总充值是否排除赠送，见 BACKLOG） |
| A09 验证码提供方声明与阿里云参数 | ✅ | `641f4d5b5`（登录、注册、发送邮箱验证码、找回密码、Passkey 登录开始五个接口新增可选 `captcha_provider`、`aliyun_captcha_param`（找回密码是顺带加的）；OAuth 启动与待处理 OAuth 流程不加。阿里云优先读 aliyun_captcha_param，去空白后为空才回退 turnstile_token。声明值去空白、不区分大小写比较，与生效值不一致返回 400 `CAPTCHA_PROVIDER_MISMATCH`，`metadata.captcha_provider` 带当前生效值；**严格取舍**：站点没开验证码时带了声明也返回 400（metadata 为 ""），App 收到后按 metadata 或重新拉公开设置再验证；多个提供方同时开启时 503 `CAPTCHA_PROVIDER_CONFLICT` 优先；不带声明不校验，旧行为逐字段不变。注册走邮箱验证码时整体跳过验证码，声明也不校验（与原有不重复校验一致）。`GET /settings/public` 新增 `captcha_provider`（"" / turnstile / tencent / aliyun / conflict，键始终存在，App 据此判断后端是否支持）与 `mobile_verify_path`。**部署注意**：`mobile_verify_path` 只检查二进制内嵌前端里有没有 `assets/MobileVerifyView-*.js` 分片，需用 `-tags embed` 构建且前端为含桥页的新包；前端单独部署（非 embed 构建）时恒为 ""。`/admin/me` capabilities 加 `auth.captcha_provider`。桥页 envelope 不变，阿里云仍输出 turnstile_token，App 映射为 aliyun_captcha_param；Web 前端与 TS 类型不改。受信设备免验证码 / App Attest 等可选项见 BACKLOG。审查修正 `6018d7b18`：审计日志 request_body 里 aliyun_captcha_param 与既有的 tencent_captcha_ticket / tencent_captcha_randstr 改为 ***（原先明文入库），captcha_provider 与验证码配置项照旧可见；补注册、找回密码的 handler 级声明用例） |
| A11 出站推送（APNs / Bark / ntfy / Webhook） | ✅ | `97040127a`、`4737725f8`、`70116315d`（审查 LOW 修正 `70116315d`：Bark / ntfy / Webhook 目标已由另一位在职管理员注册时返回 409 PUSH_TARGET_IN_USE，不再转移设备、覆盖原主人的 secret 与订阅（原主人已不是 active 的 admin 时可接管，iOS 令牌照旧转移）；account.error 改为每台设备同一账号 30 分钟内最多一条（写投递前读近 30 分钟的 account.error 投递，免打扰跳过的不算），error_at 跨 30 分钟分桶不再重复推；APNs 发送时读站点设置失败按退避重试，last_error 只写 APNs settings unavailable；handler 越权测试改为共用同一仓库。部署注意：同一通用目标的跨管理员注册由 200 转移变为 409。审查修正：通用渠道改用独立的 security.push_targets.allow_private_hosts / allow_insecure_http，默认关闭，不再沿用默认放开的 url_allowlist；只读 sat_ 注册时只能 platform=ios，其他渠道 403 ACCESS_TOKEN_READ_ONLY；iOS 省略 environment 存空串、发送时跟随站点 apns_environment；apns-collapse-id 改为站点标识与去重键的哈希；调度一轮内多批认领（≤20 批、30 秒预算），本轮网络不可达的设备只拨一次、其余投递沿用该失败按退避重试。部署注意：局域网 / 本机推送目标需设 SECURITY_PUSH_TARGETS_ALLOW_PRIVATE_HOSTS=true，新登记 http 目标需 SECURITY_PUSH_TARGETS_ALLOW_INSECURE_HTTP=true。原实现：Q7 四种渠道共用一套设备、订阅、免打扰、去重与停用逻辑，platform 取 ios / bark / ntfy / webhook；新路由 `GET/POST /api/v1/admin/push/devices`、`DELETE /api/v1/admin/push/devices/:id`、`PUT .../:id/subscription`、`POST .../:id/test`、`GET/PUT /api/v1/admin/push/config`（PUT 挂 step-up、只限站长），vendor 一律不开放；注册新建 201、同一令牌再注册 200 且 id 不变（重新启用设备，省略 subscription 时保留原订阅），另一位管理员注册同一 iOS 令牌时设备转给他、订阅与历史重置（通用目标见审查 LOW 修正），单人最多 20 台（409 PUSH_DEVICE_LIMIT_REACHED）；返回值不含令牌 / secret / 完整 endpoint，只有 token_hint（末 4 位）与 endpoint_host；默认订阅 ops_alert.fired + account.error、P1，`events:[]` 表示暂停；**与文档不同**：不在业务热路径挂钩子、不用 Redis 队列，改为后台 PushDispatcherService 每 15 秒取 leader 锁扫描最近 10 分钟的告警触发 / 恢复、账号出错、异步测试完成，写 push_deliveries（(device_id, dedup_key) 唯一，SKIP LOCKED 认领，多实例只发一次）；account.error 每台设备同一账号 30 分钟最多一条，正文只有 #ID · 平台 · 错误类别（C02 error_kind）；account.test_finished 只推 C08 异步测试的发起人（created_by），不受分组 / 平台过滤，定时测试与 SSE 手动测试不推；告警标题取 D06 rule_snapshot 的规则名，被运行时静默或 D01 范围静默覆盖的告警不推（与邮件同口径）；免打扰时段内的事件记 skipped、不补推；只推给 active 的 admin；失败 30 秒、2 分钟重试共 3 次；APNs 用标准库 HTTP/2 + golang-jwt ES256（provider token 缓存 50 分钟，未引入新依赖），410 / BadDeviceToken / DeviceTokenNotForTopic 停用设备，403 InvalidProviderToken 只记日志；其他渠道 410 停用；Webhook 带 X-Sub2-Event / Delivery / Timestamp，有 secret 时 X-Sub2-Signature: sha256=HMAC(secret, ts+"."+body)；APNs 配置为独立设置键 push_apns_config，p8 私钥要求固定 TOTP_ENCRYPTION_KEY（否则 400 SECRET_ENCRYPTION_KEY_NOT_CONFIGURED）、只写不回显、审计按 privatekey 脱敏；设备凭据（令牌 / secret / endpoint）有固定密钥时加密保存，否则明文，解不开时停用为 secret_undecryptable；设备注册请求体整体不入审计；Bark / ntfy / Webhook 提交按 security.push_targets 的 allow_insecure_http / allow_private_hosts 校验，发送时 safeDialContext 再校验真实 IP、不走代理、不跟随重定向；只读 sat_ 令牌放行表加 4 条推送设备精确路由（含 test），PUT push/config 仍拒绝；capabilities 追加 `push.notifications`；新稳定错误码 INVALID_PUSH_TOKEN、INVALID_PUSH_TARGET、INVALID_PUSH_SUBSCRIPTION、INVALID_APNS_CONFIG、PUSH_DEVICE_NOT_FOUND、PUSH_DEVICE_LIMIT_REACHED、PUSH_DELIVERY_FAILED（502，metadata.provider_status / provider_reason）、PUSH_NOT_CONFIGURED（503），载荷与签名格式写在 sub2 `docs/API_ERROR_CODES.md`；按编排者裁定不做推送中继、推送不带账号名（见 BACKLOG）；**部署注意**：需执行迁移 257（新建 push_devices / push_deliveries，并在 accounts、ops_alert_events、account_test_runs 上建部分索引，非 CONCURRENTLY）；wire 已重新生成，dispatcher 在 provideCleanup 中停止；APNs 只适用于用同一 Apple Team p8 私钥构建的 App；局域网 ntfy / Bark 需打开 security.push_targets.allow_private_hosts（http 还需 security.push_targets.allow_insecure_http）；有设备时每 15 秒 4 条扫描查询，推送延迟最多约 15 秒；所有实例停机超过 10 分钟期间的事件不补推；App 退出登录时应自己调 DELETE，会话吊销不会自动删除设备） |

实现中发现的既有问题：迁移执行器把 goose 格式文件整个执行，037 的回滚段把静默表删掉了（已用 247 修复）；019、024 同样被自己的回滚段撤销，记在 `BACKLOG.md` 待定。

---

## 1. 约定

### 1.1 优先级

| 级别 | 含义 |
|---|---|
| **P0** | 首版必须：不改则对应页面做不出来或结果不可靠；或是已存在、可被直接利用的安全漏洞 |
| **P1** | 首版强烈建议：App 有退路，但准确性、体验或安全明显受损（多次请求拼数据、口径对不上、要用户去 Web） |
| **P2** | 增强：退路可以接受，可后排 |

### 1.2 兼容原则

1. **只增不改**：新字段、新参数、新路由；已有字段的名字、类型、语义不变。少数必须改行为的条目，类型标“改行为”，并写明对 Web 的影响。
2. **Web 不受影响**：不带新参数时，响应与现在逐字段一致；新字段 Web 不读也不出错。涉及 Web 前端改动的条目单独写明：必须改 Web 的是 C19、D09；要同步改 Web 的是 C10（Setup Token 文案）、D07 方案 A（规则编辑器的指标选项）；可选的 Web 改动是 C06 的顺手修复、H08 的备选方案（Web 补 Idempotency-Key 头）。
3. **新接口挂在 `/api/v1/admin/*`**（会话类在 `/api/v1/auth/*`），沿用现有中间件链 `adminAuth → VendorScope → panelRateLimiter → auditLog → AdminComplianceGuard`（`server/routes/admin.go:28-36`）。管理员 JWT 与 Admin Key（`x-api-key`）都能调，条目另说的除外。
4. **vendor（代运营工作区）**：不在 `server/middleware/vendor_routes.go:98-153` 白名单里的路由一律 403。但白名单按路径前缀匹配（`:230-252,267-272`）：`/api/v1/admin/accounts`（GET 与写方法）、`/proxies`（GET 与写方法）、`/groups`（GET、PUT、PATCH）下新增的子路由会自动继承放行（`:117-143`），并不是默认拒绝。批量扇出类端点要显式登记到 vendorBatchAccountRoutes（`:155-166`）或 `vendorDeniedRoutes`（`:40-83`）。看板路由逐条精确登记（`:147-153`），会查 usage_logs 的还要同时登记 vendorUsageScopedRoutes（`:168-178`），否则会在没有账号白名单的情况下查全站用量。需要对 vendor 开放、或必须防 vendor 的条目，会写明这几处怎么改。

### 1.3 格式

- **字段命名**沿用后端 snake_case；错误 `reason` 用 UPPER_SNAKE_CASE。
- **响应信封**沿用 `pkg/response/response.go:15-21`：成功 `{"code":0,"message":"success","data":…}`；错误 `{"code":<HTTP 状态>,"message","reason","metadata"}`。新错误一律用 `infraerrors.*` 带 reason。中间件的字符串 code 格式见 A06。
- **时间**：新增时间字段用 RFC3339（UTC，`Z` 结尾）；与已有 Unix 秒字段并列的（代理 `quality_checked`、账号 `expires_at`）沿用 Unix 秒，条目里写明。
- **金额**：读出沿用 float64 JSON 数字（USD，不改，见附录 B L18）；资金写入与账本沿用 8 位小数的十进制字符串（`handler/admin/user_handler.go:99-100`、`service/admin_user_adjustment.go:75-97`）。新增统计金额用 float64，新增账本金额用字符串。
- **幂等**：写接口用 `Idempotency-Key` 请求头（UUID），重放语义见 G01。App 对所有资金、新建类写入都带 key。
- **迁移编号**：origin/main 当前最大是 `246_dashboard_hourly_invalidation.sql`（本地 40bee5d2e 停在 242）。本文要加迁移的条目（C02、C08、C09、D06、D07 方案 B、E10、G02、G03 等）都从 247 起按实际落地顺序编号，不要用 243–246：runner 按文件名排序执行并按文件名记录（`repository/migrations_runner.go:174-180`），重号虽然能执行，但会排到已发布的迁移前面，容易混乱。

### 1.4 证据写法

- 后端路径相对 `sub2/backend/internal/`：`handler/…`、`service/…`、`repository/…`、`server/routes/…`、`server/middleware/…`、`middleware/rate_limiter.go`（登录限流，另一个目录）、`pkg/…`、`config/…`、`web/…`。`ent/…`、`migrations/…`、`cmd/…` 相对 `sub2/backend/`。
- Web 前端写 `frontend/src/…`（相对 `sub2/`）；原生 App 写 `sub2-mobile-native/…`；设计稿与调研写 `html-preview/…`、`research/…`（相对本目录）；`DECISIONS.md:行号` 指本目录的决定文档。
- 行号以 `40bee5d2e` 为准；写成 `origin/main:<路径>:<行>` 的以 `e5ab7e4f4` 为准。
- 每条详述按“页面 / 背景 / 现状 / 建议改法 / 实现提示 / App 退路 / 验收”组织。验收命令里 `$BASE` 是站点根地址，`$KEY` / `$ADMIN_KEY` 是 Admin Key，`$T` / `$TOKEN` 是管理员 JWT。

---

## 2. 总表

按优先级、再按领域排序。领域编号：**A** 认证与会话 · **B** 概览与统计 · **C** 账号 · **D** 日志与监控 · **E** 用户与 API Key · **F** 分组 · **G** 资金与兑换码 · **H** 代理与公告。

| 编号 | 标题 | 优先级 | 类型 | 涉及页面 | 后端未改前 App 的退路 |
|---|---|---|---|---|---|
| A01 | 移动端基线：origin/main 合入桥页提交 d75c49405 并部署 | P0 | 合并部署 | 概览 6 格、账号容量、登录验证码 | snapshot-v2 取账号成本；RPM 字段缺失显示“—”；无桥页时提示改用 Web |
| D01 | 告警静默放开无平台作用域，补列表 / 修改 / 撤销，事件带静默信息 | P0 | 改行为 + 新接口 | 监控 · 告警、告警详情、首页告警行 | 无平台规则只留“手动解决”；静默状态只存本机 |
| E01 | 管理员替用户新建 / 修改 / 停用 / 删除 API Key | P0 | 新接口 | 编辑用户 · Key 与限额 | 虚线占位“需后端新增” |
| E02 | vendor 经使用记录拿到终端用户 API Key 明文与用户资料 | P0 | 安全修复 | 无 App 依赖 | 不适用 |
| G01 | 资金写接口脱离请求上下文执行，失去租约的 processing 记录可接管 | P0 | 改行为 | 充值 / 退款、批量生成兑换码、发放补偿、待核对 | IN_PROGRESS 超 30 秒转“待核对”，按 X-Request-ID 查账本 |
| A02 | 新增 `GET /admin/me`：身份、权限、开关、版本、能力一次返回 | P1 | 新接口 | 启动、各 Tab 可用性、写操作前、vendor 登录 | 并发 /auth/me、settings/public、compliance、admin/settings |
| A03 | 刷新令牌宽限期 + 原子轮换 + 重放检测；降级登录补 expires_in | P1 | 改行为 | 登录、恢复会话、自动续期 | actor 内合并刷新；暂时性错误保留会话；响应丢失只能重登 |
| A04 | 会话绑定的原生客户端模式（device / ua_only / 设备密钥） | P1 | 新能力 | 登录后全部页面 | 固定 UA；失效时提示重新登录 |
| A05 | 撤销会话后已签发的 access token 立即失效 | P1 | 新能力 | 退出、退出其他设备 | 提示其他设备最多 24 小时内仍可用 |
| B01 | 不受运维开关限制的近 N 分钟速率 `dashboard/rates` | P1 | 新接口 | 概览 6 格、运行区、监控概况 | 开监控用 overview?time_range=5m；关监控退回 stats，错误率“—” |
| B02 | `dashboard/trend` 每点加 account_cost（用户侧剥离） | P1 | 加字段 | 统计分析 · 利润明细 | 每个时段一次 usage/stats |
| B03 | 用量与看板的 model 筛选接受 model_source | P1 | 加参数 | 模型排行（上游口径）→ 模型页 | 只开放“用户拆分”，其余标口径 |
| C01 | 新建账号可选 schedulable=false、skip_default_group_bind | P1 | 加参数 | 新建账号“创建并测试” | 创建后立即停调度（有空窗） |
| C02 | 账号 DTO 加 error_at、error_status_code、error_kind、error_summary | P1 | 加字段 | 账号详情状态卡、账号行、待处理 | 取最近一条上游错误代替（依赖运维监控） |
| C03 | `PATCH /admin/accounts/:id`：凭据与 extra 按键合并 + If-Match | P1 | 新接口 | 账号详情内联编辑各分区、撤销 | GET 后整份 PUT（无并发保护） |
| C04 | 新增 `dashboard/accounts-ranking` 账号今日实际扣费排行 | P1 | 新接口 | 平静布局“按账号前 4”、账号按金额排序 | 全量账号 + today-stats/batch 本地排序 |
| D02 | 新增不依赖运维监控的 `accounts/status-summary` | P1 | 新接口 | 概览待处理、平静布局、账号组头、分组列表 | groups/all 计数 + 全量 lite 列表本地分档 |
| D03 | ops/upstream-errors 补 user_id、api_key_id、model、request_id 筛选 | P1 | 加参数 | 使用记录三段筛选胶囊、成功请求的上游尝试 | 用户 / 模型胶囊置灰；q 模糊搜 request_id |
| D04 | 错误日志补写 duration_ms，列表直接返回耗时与首字 | P1 | 加字段 | 错误请求 / 上游错误行“首字/耗时” | 行内“—”，详情用阶段耗时之和 |
| D05 | 管理端使用记录每条返回 account_cost | P1 | 加字段 | 成功请求详情、请求记录 | 客户端按公式算 |
| E03 | Key 列表与使用记录可只返回掩码，揭示需 step-up | P1 | 加参数 | Key 摘要 / 卡片、分组密钥页、请求详情 | 只显示名称与后 4 位，明文不落盘 |
| E04 | Key 换分组撤销时收回自动授权；replace-group 返回明细并可精确反向 | P1 | 加参数 | Key 卡片“换分组”、替换分组的撤销 | 两步还原；有风险时撤销置灰 |
| E05 | 新增快捷充值头像数据源 `users/quick-topup` | P1 | 新接口 | 用户列表顶部头像条 | user-adjustments 去重 + 逐个 GET |
| F01 | 新增 `groups/:id/accounts/batch` 增量加入 / 移出成员 | P1 | 新接口 | 分组详情成员、添加账号、批量结果页 | 逐账号 GET + PUT group_ids（有覆盖风险） |
| F02 | `groups/:id/stats` 返回真实 Key 数、订阅数 | P1 | 改行为 | 分组详情、停用 / 删除确认 | 3–4 个 page_size=1 请求读 total |
| F03 | vendor 可读任意分组的订阅列表（越权） | P1 | 安全修复 | 无 App 依赖 | 不适用 |
| G02 | 写入结果可确定核对：账本精确过滤、余额接口回传 action_id | P1 | 加参数 | 待核对横幅、核对按钮 | 带 X-Request-ID，按邮箱 + 时间窗拉账本本地匹配 |
| G03 | 批量生成兑换码：事务 + batch_id 去重 + 备注；重放返回真码 | P1 | 改行为 | 批量生成向导、生成待核对 | 按 id 回查真码；时间窗启发式匹配 |
| G04 | 兑换码列表 / 导出 / 统计支持 types、exclude_types | P1 | 加参数 | 兑换码列表与状态胶囊 | 四类各请求一次再归并 |
| G05 | 已使用的兑换码不能被作废后改回未使用（防重复兑换） | P1 | 改行为 | 兑换码作废 / 续期 | 对已使用的码不提供作废、续期 |
| H01 | 代理 DTO 加 latency_checked_at，测试响应加 checked_at | P1 | 加字段 | 代理列表延迟、代理详情延迟块 | 不写测量时间；本次测过的标“本次测试结果” |
| H02 | `GET /admin/proxies/:id` 返回与列表一致的完整 DTO | P1 | 改行为 | 代理详情（跳转进入、刷新） | 按名称搜列表再按 id 找 |
| H03 | 查询因到期被回退走的账号，批量恢复原代理 | P1 | 新接口 | 代理详情 · 有效期、到期横幅 | 全量账号本地过滤，逐个恢复 |
| H04 | 编辑代理地址后延迟缓存失效并重新探测 | P1 | 改行为 | 代理列表 / 详情的延迟与出口 IP | 编辑后自动调一次测试连接 |
| H05 | 删除代理检查回退引用；恢复原代理前校验原代理可用 | P1 | 改行为 | 删除代理、账号“恢复原代理” | 删除 / 恢复前 App 自查原代理状态 |
| A06 | 错误响应统一带 reason，公布稳定错误码清单 | P2 | 加字段 | 全局错误处理 | App 兼容 Int / String code 解码 |
| A07 | 会话列表与单独下线 | P2 | 新接口 | 设置 → 安全 | revoke-all-sessions 全踢 |
| A08 | 可选：按设备签发的管理访问令牌 sat_ | P2 | 新能力 | 登录（Admin Key）、站点与凭据 | 推荐账号 + TOTP 登录 |
| A09 | 验证码可选 captcha_provider、aliyun_captcha_param，公开设置给生效提供方 | P2 | 加参数 | 登录 | 阿里云继续用 turnstile_token |
| A10 | 提供 `/.well-known/apple-app-site-association` | P2 | 新接口 | 登录（Passkey、自动填充） | 反向代理放静态文件；不提供 Passkey |
| A11 | 可选：APNs 出站推送 | P2 | 新能力 | 告警、待处理、测试完成 | 前台轮询 + 本地通知 |
| B04 | users-ranking 加 sort_by、成本字段与用户总数 | P2 | 加字段 | 统计分析 · 用户排行 | 改用 user-breakdown |
| B05 | 新增 `dashboard/request-types` | P2 | 新接口 | 统计分析 · 请求类型图 | usage/stats?request_type= 并发 5 次 |
| B06 | ops/dashboard/* 增加 model 筛选 | P2 | 加参数 | 统计分析按模型筛选、模型页 | 运行类图表标“仍显示全站” |
| B07 | openai-token-stats 接受任意 start_time / end_time | P2 | 加参数 | 统计分析 · Token 请求统计 | 取盖住所选范围的最小窗口并写明 |
| B08 | user-breakdown 参数校验收尾：去掉二次解析、统一报错文案、补 stream 与 limit 校验 | P2 | 改行为 | 用户排行、用户拆分 | App 本地校验参数、不带空格 |
| B09 | 日志 since_id 增量；稳定 GET 加 ETag / 304 | P2 | 新能力 | 概览、用户、分组、请求记录、错误日志 | 时间窗回看 120 秒 + 按 id 去重 |
| B10 | 重统计提速：throughput-trend 可选读小时预聚合、可跳过附带汇总 | P2 | 加参数 | 概览性能趋势、统计分析 | 独立加载 + 长超时 |
| B11 | 可选：可部分成功的首页聚合 `dashboard/home` | P2 | 新接口 | 概览首页 | 并发 5 路独立加载 |
| B12 | users-trend 带筛选时按 metric 取前 N 位 | P2 | 改行为 | 统计分析 · 用户用量趋势（带筛选） | user-breakdown 取人 + 逐个 dashboard/trend；或带筛选时只给 Tokens |
| C05 | recover-state 可选 `{"schedulable":true}` | P2 | 加参数 | 账号详情“恢复并启用调度” | 两次请求 |
| C06 | 账号混合渠道 409 补 reason、metadata、details | P2 | 改行为 | 新建 / 编辑账号 | 提交前 check-mixed-channel 预检 |
| C07 | 账号测试 SSE 末尾追加 test_result 事件 | P2 | 加字段 | 测试结果 sheet、待处理“测试” | 本机计时，流结束后 GET 对比 |
| C08 | 异步账号测试 `accounts/:id/test-runs` | P2 | 新能力 | 手动测试、待处理 | 关闭弹窗即取消 |
| C09 | 定时测试结果加 upstream_status_code | P2 | 加字段 | 账号详情定时测试结果 | 正则解析 error_message |
| C10 | 账号 DTO 加 token_status；Setup Token 寿命以后端为准 | P2 | 加字段 | 凭据区令牌剩余时间、新建账号说明 | 兼容两种 expires_at，分母写死 |
| C11 | 新增 `accounts/:id/reauthorize`；apply 加 preserve_status | P2 | 新接口 | 凭据区“重新授权…” | exchange-code + apply 两步 |
| C12 | OAuth 换码失败统一 400 + reason | P2 | 改行为 | OAuth 第 3 步、重新授权 | 超 30 分钟或 500 时提示重新生成链接 |
| C13 | 新增 `admin/meta/catalog`（平台目录与枚举） | P2 | 新接口 | 新建账号表单、筛选、角色 | App 内置清单，未知值显示原始 id |
| C14 | 账号列表 status 多值与派生值、urgency 排序、计数 | P2 | 加参数 | 账号 Tab 分组排序、筛选胶囊 | 全量 lite 本地分组排序 |
| C15 | 新增 `accounts/runtime/batch`，读取失败返回“不可用” | P2 | 新接口 | 账号列表、详情容量、分组成员 | 重拉当前页；0 视为“0 或未知” |
| C16 | today-stats/batch 返回 failed_account_ids，失败不缓存 | P2 | 加字段 | 账号列表今日统计 | 单账号接口确认 |
| C17 | today-stats/batch 可选 group_id | P2 | 加参数 | 分组详情成员 | 注明“含其他分组用量” |
| C18 | 清错误可选不重新启用停用账号 | P2 | 加参数 | 账号批量“恢复状态” | 先排除 inactive 账号 |
| C19 | Web 账号页支持 `?edit=<id>` 深链 | P2 | Web 前端 | 账号详情“在 Web 中编辑” | 打开列表并复制账号名 |
| D06 | 告警事件附规则摘要、分组名、解决人；告警计数接口 | P2 | 加字段 | 告警行与详情 | 另拉规则、分组拼；数 firing 列表 |
| D07 | 修复预置 P95 / P99 延迟告警规则 | P2 | 改行为 | 监控 · 告警 | 显示“不受支持（不会触发）” |
| D08 | CPU / 内存历史、任务心跳 stale 判定、入口拒绝合计 | P2 | 新接口 | 监控 · 概况 · 服务器区 | 前台自攒点；本地写死周期；翻页累加 |
| D09 | 运维监控开关：Web 补开关，后端 `ops/monitoring-status` | P2 | 新接口 | “运维监控未开启”提示 | PUT admin/settings 只带开关字段 |
| D10 | 上游重试链记录每次耗时，按 request_id 合并整条链 | P2 | 加字段 | 失败请求“上游尝试” | 失败链 + usage?request_id= 估算 |
| E06 | 固定 Key 状态枚举，新增 effective_status | P2 | 加字段 | Key 摘要、Key 卡片、分组密钥页 | App 自己映射停用 / 过期 / 耗尽 |
| E07 | 平台限额支持单平台 PUT / DELETE | P2 | 新接口 | 平台限额保存与撤销 | GET 后整表 PUT |
| E08 | rpm-status 标明计数是否生效（tracked） | P2 | 加字段 | 权限与并发 · RPM 状态 | limit=0 写“不限 · 不计数” |
| E09 | api-keys-usage 快照缓存键加日期 | P2 | 改行为 | Key 今日消费 | 零点附近延迟几秒再刷新 |
| E10 | 充值记录带前后余额、user_id 精确筛选、总充值口径、初始余额入账 | P2 | 加字段 | 充值与调整记录、新建用户 | 不显示余额；keyword 后本地过滤 |
| E11 | 管理端 Key 列表回填 current_concurrency | P2 | 修 bug | Key 卡片“当前并发” | 显示“—” |
| E12 | users-usage / api-keys-usage 限制 ID 数量 | P2 | 改行为 | 用户列表、Key 今日消费 | 每批 ≤ 200 个 |
| F04 | 分组 DTO 加 error_account_count、idle_account_count | P2 | 加字段 | 分组列表色格条、分组详情 | 拉错误账号本地分桶 |
| F05 | capacity-summary 可选 group_id / group_ids | P2 | 加参数 | 分组详情容量 | 拉全部本地过滤 |
| G06 | 其余管理写接口支持可选 Idempotency-Key | P2 | 新能力 | 用户 / 分组 / 账号的编辑与启停 | 冻结原请求，读回比对 |
| G07 | 禁止删除已使用的兑换码与 admin_* 记录 | P2 | 改行为 | 兑换码 ⋯ → 删除 | 已使用的码不提供删除 |
| G08 | 兑换码统计返回真实值 | P2 | 改行为 | 兑换码状态胶囊计数 | 每个状态一次 page_size=1 |
| H06 | 公告已读汇总、已读名单筛选与 read_at 排序 | P2 | 新接口 | 公告列表、详情、已读情况页 | 只放“已读情况 ›”分页名单 |
| H07 | 公告新建支持可选 Idempotency-Key | P2 | 新能力 | 公告新建 sheet | 超时后按标题搜最近几条再决定 |
| H08 | Web 不带 key 的强制幂等写接口改为可选幂等（代理、账号新建与导入、兑换码生成等 11 个） | P2 | 改行为 | 代理新建、账号新建（Web 兼容） | App 始终带 key |

---

## 3. 逐条详述

### A 认证与会话

#### A01 · 移动端基线：在 origin/main 上合入桥页提交 d75c49405 并部署 〔P0 · 合并部署〕

**页面**：概览 6 格（今日实际扣费、利润 = 实际扣费 − 账号成本、RPM）；账号列表三行与账号详情 · 容量（近 60 秒 RPM、调度 RPM）；登录（验证码）。

**背景**：App 的接口契约按 origin/main 核对（`sub2-mobile-native/README.md:79`、`sub2-mobile-native/docs/API_COMPATIBILITY.md:3`）。利润要今日 / 累计账号成本；RPM 格要知道实时计数是否可用；容量区要所有账号的近 60 秒 RPM 和调度 RPM；开了验证码的站点要靠 `/mobile/verify` 桥页拿到验证码 token 才能登录。

**现状**：
- 本地 sub2 main 停在 `40bee5d2e`，落后 origin/main 89 个提交；sub2-mobile-backend = `40bee5d2e` + `d75c49405`。
- `40bee5d2e` 的 `GET /api/v1/admin/dashboard/stats`（`handler/admin/dashboard_handler.go:85-134`）不输出 `today_account_cost`、`total_account_cost`、`rpm_available`。DashboardStats 里两个成本字段本来就有（`pkg/usagestats/usage_log_types.go:61,72`），只是 handler 漏写。
- `40bee5d2e` 的 `current_rpm` 只对 base_rpm>0 的 Anthropic OAuth / SetupToken 账号返回（`handler/admin/account_handler.go:400,419-420`），没有 `scheduling_rpm`。
- origin/main 已补齐：`origin/main:handler/admin/dashboard_handler.go:111,122,130`；`origin/main:handler/admin/account_handler.go:224-225,238`（SchedulingRPM）；List 对整页账号做 GetRPMBatch + RollingRPMCache.GetRollingRPMBatch（`origin/main:repository/rpm_rolling_cache.go:62-67`、`origin/main:service/rpm_cache.go:26`）。
- `d75c49405` 只改前端 10 个文件（`frontend/src/main.ts`、`frontend/src/router/index.ts`、`frontend/src/utils/mobileCaptchaBridge.ts`、`frontend/src/views/public/MobileVerifyView.vue` 及测试、`docs/mobile-verification.md`），不是 origin/main 的祖先；`git merge-tree --write-tree origin/main d75c49405` 无冲突（结果树 `16c5f4250`）。

**建议改法**：不写新代码，合并 + 部署。
1. `git checkout -b mobile-baseline origin/main && git cherry-pick d75c49405`（或开 PR 合入 main）。
2. 重新构建前端（桥页打进 `web/dist`），重新构建并部署后端。
3. 字段约定（e5ab7e4f4 已实现，只增）：

```jsonc
// GET /api/v1/admin/dashboard/stats → data 增加
{ "today_account_cost": 12.34, "total_account_cost": 5678.9, "rpm_available": true }
// GET /api/v1/admin/accounts、GET /api/v1/admin/accounts/:id → 每个账号增加
{ "current_rpm": 7, "scheduling_rpm": 5 }
```

   - `rpm_available` 可缺省；`false` 表示实时计数不可用（不是 0）。
   - `current_rpm` 是近 60 秒成功上游请求数，`scheduling_rpm` 是自然分钟调度计数；Redis 读失败时两者都缺省。
   - `GET /mobile/verify?nonce=<UUID>` 是公开前端页，消息协议 version 1，见 `docs/mobile-verification.md`。
4. 配合 A02 的 `server.capabilities` 声明 `dashboard.account_cost`、`dashboard.rpm_available`、`accounts.rolling_rpm`、`accounts.scheduling_rpm`、`mobile.verify_bridge`，App 不再靠“字段在不在”猜站点版本。

**实现提示**：d75c49405 自带 4 个 vitest（`mobileCaptchaBridge.spec.ts`、`MobileVerifyView.spec.ts`、`mobileVerificationBootstrap.spec.ts`、`mobile-verification-route.spec.ts`），再跑 `pnpm run typecheck && pnpm run build`；后端跑 `go test ./internal/handler/admin/... ./internal/repository/...`。桥页在 main.ts 里按 pathname 直接挂载，router 在 beforeEach 中提前放行 MobileVerify，不受后端模式和登录守卫影响。List 对整页 accountIDs 只做两次 Redis 批量读。部署后确认 `/api/v1/settings/public` 的 `version` 反映新版本。

**App 退路**：账号成本缺失时另调 `GET /api/v1/admin/dashboard/snapshot-v2?include_stats=true&include_trend=false&include_model_stats=false&include_group_stats=false&include_users_trend=false` 取 `data.stats.today_account_cost`（40bee5d2e 的 snapshot-v2 嵌入整个 DashboardStats，`handler/admin/dashboard_snapshot_v2_handler.go:21-24,181-190`），超过 90 秒标过期；`rpm_available` 缺失时显示“RPM 窗口由站点决定”；没有 `scheduling_rpm` 时调度 RPM 显示“不可用”；`current_rpm` 缺失的账号不显示 RPM；`/mobile/verify` 打开得到 Web 首页或 404 时提示“站点未部署手机验证页，请改用 Web 或关闭验证码”。

**验收**：

```bash
curl -s -H "x-api-key: $KEY" "$BASE/api/v1/admin/dashboard/stats" | jq '.data|{today_account_cost,total_account_cost,rpm_available}'
curl -s -H "x-api-key: $KEY" "$BASE/api/v1/admin/accounts?page=1&page_size=50" | jq '[.data.items[]|{platform,type,current_rpm,scheduling_rpm}]'
curl -s "$BASE/mobile/verify?nonce=3a006827-701c-44e8-b153-cef42dc70234"
git merge-base --is-ancestor d75c49405 <部署提交> && git merge-base --is-ancestor e5ab7e4f4 <部署提交>
```

stats 三个字段都在；OpenAI、Gemini 等非 Anthropic 账号也有 `current_rpm`、`scheduling_rpm`；桥页返回 HTML 且引用 MobileVerifyView 分片，App 的 WKWebView 收到 `{version:1,nonce,provider,proof}`；两条 ancestor 判断都成立。

---

#### A02 · 新增 `GET /api/v1/admin/me`：一次返回身份、认证方式、工作区权限、step-up、合规、功能开关、版本与能力 〔P1 · 新接口〕

**页面**：启动与切换站点；概览（RPM / TPM / 错误率的数据源选择）；监控 Tab 三段；使用记录的错误请求、上游错误段；账号详情“最近上游错误”；各写操作之前；vendor 登录。

**背景**：进入页面前就要知道哪些区域可用，直接显示“运维监控未开启”，而不是靠 404 / 403 / 423 一次次试；还要区分新旧版本站点。

**现状**：
- `/api/v1/auth/me` 返回 role、run_mode，vendor 还有 `workspace.permissions` 五档（account_manage、group_ops、group_billing、proxy_manage、monitor_view）（`handler/auth_handler.go:427-504`）；但只挂 jwtAuth（`server/routes/auth.go:250-257`），Admin Key 调不了（`server/middleware/jwt_auth.go:40-44`）。
- 公开设置 `/api/v1/settings/public` 有 version、channel_monitor_enabled、channel_monitor_mode、backend_mode_enabled、totp_enabled、server_timezone（`handler/dto/settings.go:383,414-446`；`handler/setting_handler.go:99,107-108`）。
- 合规状态 `GET /api/v1/admin/compliance`（`handler/admin/compliance_handler.go:27-40`），vendor 也放行（`server/middleware/vendor_routes.go:104`）。
- ops_monitoring_enabled、ops_realtime_monitoring_enabled、step_up_enabled、session_binding_enabled 只在 `GET /api/v1/admin/settings` 的大响应里（`handler/admin/setting_handler.go:112,159-160,293-294`），vendor 不能访问。
- step-up 剩余时间查不到：授权固定 15 分钟（`service/totp_service.go:404`），只在 POST step-up 的响应里给 expires_in。
- `/api/v1/admin/dashboard/realtime` 是固定返回 0 的占位（`handler/admin/dashboard_handler.go:184-194`），现有 App 拿它当 Admin Key 探针。
- 两个开关决定 ops 接口的行为，客户端现在只能靠试：运维监控关闭时，所有 ops 接口（包括 account-availability、concurrency、realtime-traffic）都先过 RequireMonitoringEnabled，返回 404 OPS_DISABLED（`service/ops_service.go:19,146-151`）；运维开着、但实时监控关闭时，这三个实时接口返回 200 `enabled:false`（`handler/admin/ops_realtime_handler.go:22-36,122-136,210-251`）。两种状态要靠 features 里的 ops_monitoring_enabled 与 ops_realtime_monitoring_enabled 区分。
- vendor 的可用路由只写在代码白名单里（`server/middleware/vendor_routes.go:98-153`）；后端模式下 vendor 既不能登录（`handler/auth_handler.go:156`），也过不了 BackendModeUserGuard（`server/middleware/backend_mode_guard.go:20-26`）。
- Admin Key 一律映射为第一个管理员（`server/middleware/admin_auth.go:139-153`）。

**建议改法**：`GET /api/v1/admin/me`，挂在 admin 路由组；Admin Key、admin JWT、vendor JWT 都能调；免合规守卫（未确认合规也返回 200）。

```json
{"code":0,"message":"success","data":{
  "auth_method":"jwt",
  "user":{"id":1,"email":"admin@example.com","username":"admin","role":"admin"},
  "workspace":null,
  "security":{"totp_enabled":true,"step_up_enabled":true,"step_up_available":true,"step_up_granted":false,"step_up_expires_in":0,"session_binding_enabled":false},
  "compliance":{"required":false,"version":"v2026.06.10"},
  "features":{"ops_monitoring_enabled":true,"ops_realtime_monitoring_enabled":true,"channel_monitor_enabled":true,"channel_monitor_mode":"v1","backend_mode_enabled":false,"payment_enabled":true,"subscription_enabled":true,"risk_control_enabled":false},
  "server":{"version":"0.2.16","run_mode":"standard","server_timezone":"Asia/Shanghai","server_utc_offset":"+08:00",
            "capabilities":["dashboard.account_cost","dashboard.rpm_available","accounts.rolling_rpm","accounts.scheduling_rpm","mobile.verify_bridge"]}
}}
```

- `auth_method`：`jwt` | `admin_api_key`（A08 做了再加 `admin_access_token`）。Admin Key 时 `user` 是第一个管理员，App 据此显示“以 xxx 身份操作”。
- `workspace`：vendor 时为 `{"id":3,"name":"…","permissions":{"account_manage":true,"group_ops":false,"group_billing":false,"proxy_manage":true,"monitor_view":true}}`，admin 时为 null。
- `step_up_available` = auth_method 为 jwt 且用户已启用 TOTP；Admin Key 恒为 false。
- `features.ops_monitoring_enabled` 是生效值；做了 D09 后可再加 `ops_monitoring_disabled_reason`（`config_off` / `setting_off`）。
- `capabilities` 是静态列表，以后每加一项能力（如 A03、A07、B01）就追加一个字符串。
- 错误：只有标准 401 / 403，不返回 423。现有的 realtime 占位、ops 404 与 `enabled:false` 行为都不改。

**实现提示**：新增 `handler/admin/me_handler.go`。数据来源：
- 身份：`c.GetString("auth_method")`、ContextKeyUser、ContextKeyUserRole、GetVendorScopeFromContext；
- 合规：`settingService.GetAdminComplianceStatus`（`service/admin_compliance.go:92`）；
- 安全开关：IsStepUpEnabled、IsSessionBindingEnabled（`service/setting_features.go`）；
- 公开设置：`settingService.GetPublicSettings`（已有缓存）；
- 运维开关：`opsService.IsMonitoringEnabled / IsRealtimeMonitoringEnabled`（`service/ops_service.go:153-165`，读内存快照）；
- step-up：`totpService.HasStepUpGrant`，剩余秒数要在 `repository/totp_cache.go:156-170` 加一个 PTTL 查询；
- 版本：与 `handler/setting_handler.go:99` 的 `h.version` 同源。

全部是缓存或内存读，不做数据库聚合。注册在 `server/routes/admin.go` 的 registerAdminComplianceRoutes 旁边；`vendorAllowedRoutes` 加 `{prefix:"/api/v1/admin/me",methods:["GET"],exact:true}`；`server/middleware/admin_compliance.go:50-53` 的 isAdminComplianceBypassPath 放行该路径（只读、无敏感数据）。

**App 退路**：JWT 会话并发请求 `/auth/me`、`/settings/public`、`/admin/compliance`；admin 角色启动时读一次 `GET /admin/settings` 取 ops_monitoring_enabled、ops_realtime_monitoring_enabled、step_up_enabled 并缓存；vendor 按 `/auth/me` 的 workspace.permissions 对照白名单在本地映射可用模块；Admin Key 继续用 realtime 当权限探针，开关同样读 `/admin/settings`。之后遇到 reason=OPS_DISABLED，就把对应区域标成“运维监控未开启”；实时接口返回 200 `enabled:false` 时标成“实时监控未开启”。

**验收**：
1. `curl -s -H "x-api-key: $KEY" "$BASE/api/v1/admin/me"` → `auth_method=admin_api_key`、`security.step_up_available=false`。
2. admin JWT 返回真实 user；vendor JWT 返回 `workspace.permissions`。
3. 关闭运维监控后 `features.ops_monitoring_enabled=false`；只关实时监控时 `ops_monitoring_enabled=true`、`ops_realtime_monitoring_enabled=false`。
4. 未确认合规的新管理员调用返回 200 且 `compliance.required=true`，不是 423。
5. 完成 step-up 后 `step_up_granted=true`、`step_up_expires_in` 约 900。
6. p95 < 20ms。

---

#### A03 · 刷新令牌轮换：加宽限期、原子化并真正做重放检测；登录降级补 expires_in 并标出 refresh 不可用 〔P1 · 改行为〕

**页面**：登录、启动时恢复会话、每次请求前的自动续期。

**背景**：手机网络经常在请求中途断开。服务器已经刷新成功、只是响应没送到时，不应该逼用户重新登录（还要再过验证码和 TOTP）。

**现状**：
- RefreshTokenPair（`service/auth_service.go:1777-1862`）：GetRefreshToken（1793）→ 各种检查 → 立即 DeleteRefreshToken（1847-1851）→ GenerateTokenPair，中间没有宽限期。
- 旧令牌再用只返回 REFRESH_TOKEN_INVALID，并记一条“possible reuse attack”日志（1795-1798），不撤销会话家族；`ErrRefreshTokenReused` 有定义（38）却从未使用。
- 读取和删除不是原子操作：两个并发请求拿同一个令牌刷新会都成功，在同一家族里分叉出两条有效链。
- Redis 出错返回 503 SERVICE_UNAVAILABLE（1800-1801）；刷新路由的限流在 Redis 故障时直接拒绝（`server/routes/auth.go:53-56`）。
- 登录时 GenerateTokenPair 失败会回退成只返回 access_token（`handler/auth_handler.go:127-141`），refresh_token 和 expires_in 都因 omitempty 被省略（99-100）。
- 默认 access token 24 小时、refresh token 30 天（`config/config.go:2332-2334`）。

**建议改法**：
1. **轮换宽限期**：新增配置 `jwt.refresh_reuse_grace_seconds`，默认 30，设为 0 与现状相同。轮换时不立即删旧令牌，而是原子地改成“已轮换”记录 `{family_id, binding_hash, successor_enc, rotated_at}`，TTL = 宽限期。
   - 宽限期内用同一个旧令牌再刷新、且绑定指纹一致：返回同一个新 refresh_token，并新签一个 access_token，HTTP 200。`successor_enc` 是新 refresh_token 的密文（用旧令牌原文经 HKDF-SHA256 派生的密钥做 AES-GCM），服务端不存明文。
   - 超过宽限期再用：401 `REFRESH_TOKEN_REUSED`，并 DeleteTokenFamily（真正的重放检测）。
   - 响应格式不变：`{"access_token","refresh_token","expires_in","token_type":"Bearer"}`。
2. **登录降级（只增）**：回退分支补上 expires_in，并加标记：

```json
{"access_token":"…","expires_in":86400,"token_type":"Bearer","refresh_token_unavailable":true,"user":{"id":1,"email":"admin@example.com"}}
```

3. 文档写明：503 SERVICE_UNAVAILABLE 和 429 RATE_LIMITED 属于暂时性错误，客户端不应清除会话。

**实现提示**：
- `service/auth_service.go:1792-1851`：用 Redis Lua，或 `SET NX refresh_lock:{hash}`（5 秒）把“读取 + 改写为已轮换”做成原子；并发的第二个请求拿不到锁就短暂等待，读到“已轮换”记录后走宽限分支。
- `repository/refresh_token_cache.go` 新增 MarkRotated、GetRotated（键 `refresh_rotated:{hash}`）。宽限分支校验 binding_hash（与 A04 一致），用 GenerateToken 新签 access token；超期调 DeleteTokenFamily 并返回 ErrRefreshTokenReused（做了 A05 就顺带写 revoked_sid）。
- AuthResponse（`handler/auth_handler.go:96-141`）加 `RefreshTokenUnavailable bool json:"refresh_token_unavailable,omitempty"`，回退分支填 `ExpiresIn: authService.GetAccessTokenExpiresIn()`（`service/auth_service.go:1455-1460`）。
- 配置加在 `config/config.go` 的 JWT 段并给默认值。测试覆盖：grace=0 与现状一致；并发 N 次只产生一个继任令牌；超过宽限期撤销家族。Web 的 refreshAuthTokens 也会受益，行为兼容。

**App 退路**：actor 内合并并发刷新（已做，`sub2-mobile-native/Sources/Sub2Core/APIClient.swift:271-291`）；expires_in 缺失按 300 秒猜（:249）；refresh_token 为空直接要求重新登录（:269）。刷新遇到网络错误 / 429 / 5xx 视为暂时失败，保留会话稍后重试；只有 401 `REFRESH_TOKEN_*` 才要求重新登录。后端改好之前，响应丢失只能重新登录。

**验收**：
1. 同一个 refresh_token 在 30 秒内连续 `POST /api/v1/auth/refresh` 两次，都返回 200，且 refresh_token 相同。
2. 35 秒后第三次返回 401 REFRESH_TOKEN_REUSED；之后第二次拿到的令牌再刷新也返回 401（家族已撤销）。
3. 并发 10 个相同请求全部 200，Redis 中这个家族只多出一个新令牌。
4. 模拟 refresh 存储失败时登录：200，带 expires_in，且 `refresh_token_unavailable=true`。
5. grace 设为 0 时现有 go test 全部通过。

---

#### A04 · 会话绑定给原生客户端单独的模式：按会话选“只绑设备 / 只绑 UA / 设备密钥”，Web 会话保持 IP+UA 〔P1 · 新能力〕

**页面**：登录后的所有页面；App 从后台回到前台恢复会话。

**背景**：手机在 Wi-Fi、蜂窝和 VPN 之间切换，IP 变化是常态。站点一旦开启会话绑定，每换一次网络就被踢下线，重新登录还要过验证码和 TOTP。指纹里还包含完整 UA，App 或 iOS 升级让版本号变化，也会触发失效。

**现状**：
- 会话指纹 = SHA-256(IP + "\n" + UA) 的前 16 字节（`service/session_binding.go:12-34`）；IP 取 GetSecurityClientIP，UA 取完整 User-Agent（`server/middleware/session_binding.go:18-31`）。
- access token 校验时指纹不一致，就撤销整个会话家族、写审计、返回 401 SESSION_BINDING_MISMATCH（`server/middleware/session_binding.go:55-103`）；refresh 时同样检查并撤销（`service/auth_service.go:1837-1845`，旧路径 1506-1511）。
- 开关只有全站一个 `session_binding_enabled`，默认关（`service/domain_constants.go:287`、`service/setting_features.go:240-244`、`service/setting_parse.go:337`），没有按客户端或按模式的选项，也没有设备密钥或 App Attest。

**建议改法**：

方案 A（建议先做，只增）：
- 站点设置新增 `session_binding_native_mode`：`strict`（默认，同现在的 IP+UA）| `device` | `ua_only` | `off`。只在 `session_binding_enabled=true` 时生效，且只作用于登录时声明为原生客户端的会话；`GET/PUT /api/v1/admin/settings` 增加该字段。
- 登录请求（`POST /api/v1/auth/login`、`/api/v1/auth/login/2fa`、`/api/v1/auth/passkey/login/finish`）新增可选字段：

```json
{"client":{"type":"ios","device_id":"6F1C2A7E-9B1D-4F0B-8C55-0E0B2B3C4D5E","device_name":"我的 iPhone"}}
```

- 签发时把模式写进令牌和 refresh 数据，例如 `bnd="d1:<hash(device_id)>"`、`"u1:<hash(UA)>"`；没有前缀的旧值按 IP+UA 处理。会话签发后模式不能再改，偷到 Web 令牌的人无法把它降级。Web 不传 client，行为完全不变。
- 不匹配时仍返回 401 SESSION_BINDING_MISMATCH。

方案 B（P2，可选，更安全）：`device_key` 模式。登录时附 `client.device_public_key`（Secure Enclave 生成的 P-256 公钥，SPKI base64url）；这类会话不再校验 IP，刷新必须带签名：

```json
{"refresh_token":"rt_…","device_signature":"<对 sha256(refresh_token)+'.'+ts 的 ES256 签名>","ts":1760750000}
```

（上例为 `POST /api/v1/auth/refresh` 的请求体）ts 允许 ±60 秒；缺签名 401 `DEVICE_PROOF_REQUIRED`，签名错误 401 `DEVICE_PROOF_INVALID`。以后可以再升级为逐请求 DPoP（RFC 9449）。

**实现提示**：
- `service/session_binding.go` 加 BindingMode 与 `HashFor(mode, binding, deviceID)`，哈希串带模式前缀；`server/middleware/session_binding.go:55-103` 的 enforceSessionBinding 按 claims.BindingHash 的前缀选算法，无前缀走旧逻辑；`service/auth_service.go:1837-1845` 的 refresh 检查同样按前缀判断。
- generateRefreshToken（`service/auth_service.go:1725-1775`）的 RefreshTokenData（`service/refresh_token_cache.go:14-21`）新增 BindingMode、DeviceID、DevicePublicKey（omitempty，兼容 Redis 旧数据）。
- `handler/auth_handler.go:80-86` 的 LoginRequest 加 `Client *ClientInfo json:"client,omitempty"`；TotpLoginSession（`service/totp_service.go:64-69`）也要带上 client，保证 2FA 第二步继承；client 经 ctx 传给 GenerateTokenPair（新增 `service.WithSessionClient`）。client 结构与 A07 共用。
- 设置：`service/domain_constants.go` 加 key，`setting_parse.go`、`setting_update.go`、`handler/dto/settings.go` 的 SystemSettings 加字段，`setting_handler_audit.go` 记录变更。设置说明写清 `ua_only`、`device` 是降级选项；device_id 由客户端声明，只能防令牌被换 UA 或换设备后直接复用，真正防盗靠方案 B。

**App 退路**：发送固定、不带版本号的 User-Agent（例如 `Sub2Mobile-iOS`），至少避免升级导致失效；收到 SESSION_BINDING_MISMATCH 时提示“网络或设备信息变化导致会话失效，请重新登录”，设置页说明“站点开启了会话绑定，切换网络会掉线，可请站长关闭”。

**验收**：
1. 开启 `session_binding_enabled`、设 `session_binding_native_mode=device`，用 `client.type=ios` 登录后，从另一个 IP（经可信代理的 X-Forwarded-For）调 `GET /api/v1/admin/dashboard/stats` 返回 200。
2. Web 方式登录（不带 client），换 IP 后返回 401 SESSION_BINDING_MISMATCH，与现在一致。
3. 升级前签发的旧令牌（bnd 无前缀）仍按 IP+UA 校验。
4. 方案 B：refresh 不带签名返回 401 DEVICE_PROOF_REQUIRED，带正确签名返回 200。
5. 单元测试覆盖三种前缀与旧格式。

---

#### A05 · 退出、撤销会话后，已签发的 access token 立即失效（按 sid 吊销） 〔P1 · 新能力〕

**页面**：设置 → 安全“退出其他设备”（A07 的前提）；退出登录；会话绑定失效后；丢手机后“全部踢下线”。

**背景**：现在“踢下线”只删 refresh token，被踢的设备在 access token 过期之前（默认 24 小时）仍能调接口。

**现状**：
- jwtAuth 与 validateJWTForAdmin 只检查签名、TokenVersion 和绑定指纹（`server/middleware/jwt_auth.go:59-104`；`server/middleware/admin_auth.go:166-202`），没有按 sid 的吊销表。
- RevokeAllUserTokens 只删 refresh session（`service/auth_service.go:1902-1911`）；1895-1901 的注释写明 users 表没有 token_version 列、自增无效已移除，只有改密会因 password_hash 指纹变化让旧 token 失效。
- logout 只删传入的那个 refresh token（`service/auth_service.go:1864-1875`）；JWT 的 sid 就是会话家族 family_id（`service/auth_service.go:60-70,1689-1722`），RevokeSessionFamily 在 1877-1884。
- access token 默认 24 小时（`config/config.go:2332-2333`，`jwt.access_token_expire_minutes=0` 时回退 expire_hour）。

**建议改法**（只改校验，不改接口）：
- Redis `revoked_sid:{sid}`，TTL = access token 有效期；`user_tokens_valid_after:{user_id}` = 撤销全部的时间点，TTL 同上。
- 写入：logout、RevokeSessionFamily、DeleteTokenFamily（含 A03 重放检测、会话绑定失效、A07 的 DELETE）写 revoked_sid；RevokeAllUserTokens 与 `POST /api/v1/auth/revoke-all-sessions` 写 valid_after。
- 校验：jwtAuth 与 validateJWTForAdmin 在验签之后用一次 pipeline 读两个键；命中 sid，或 `claims.IssuedAt < valid_after`，返回 401 `TOKEN_REVOKED`（这个码已存在，`server/middleware/jwt_auth.go:91`）。
- Redis 读失败时放行并记日志：access token 本来会过期，fail-close 会在 Redis 故障时把所有管理员踢下线。这一取舍写进文档（另一条路见附录 C Q5）。

**实现提示**：新增 `repository/session_revocation_cache.go`（RevokeSID、SetValidAfter、Check），两个中间件共用一个 `service.SessionRevocationChecker`；可加 5 秒进程内缓存，只缓存“未吊销”结果，本实例写吊销时清缓存（多实例最多延迟 5 秒）。valid_after 若按秒比较，撤销那一秒内新签的 token 会被误杀：写入 `now − 1 秒`，或改用毫秒级 iat。

**App 退路**：退出时只撤销本机 refresh token；“退出其他设备”提示“其他设备最多 24 小时内仍可能保持登录”。

**验收**：
1. 设备 A、B 登录；B 调 `POST /api/v1/auth/revoke-all-sessions` 后，A 的旧 access token 立即返回 401 TOKEN_REVOKED。
2. logout 后同一 access token 返回 401。
3. 撤销之后新登录不受影响。
4. 停掉 Redis 时请求照常放行，并有日志。
5. `GET /api/v1/admin/dashboard/stats` 的 p95 增量 < 2ms。

---

#### A06 · 错误响应补齐 reason：中间件、合规 423、限流 429 都带字符串 reason，并公布稳定错误码清单 〔P2 · 加字段〕

**页面**：全局：令牌过期自动续期、step-up 二次验证弹窗、合规确认、会话绑定失效提示、Admin Key 被拒提示、限流提示。

**背景**：App 要按错误类型决定下一步：刷新令牌、弹 TOTP、引导合规确认、提示改用账号登录，或者要求重新登录。

**现状**：三种错误格式并存。
1. 中间件 AbortWithError 返回 `{"code":"<字符串>","message"}`，没有 reason（`server/middleware/middleware.go:63-81`）。调用点（均在 `server/middleware/`）：`jwt_auth.go:43-91`（TOKEN_EXPIRED 在 64）、`admin_auth.go:66-207`（INVALID_ADMIN_KEY 在 135，TOKEN_EXPIRED 在 169）、`step_up.go:105,122,131,135`、`session_binding.go:102`、`vendor_scope.go:73-203`、`panel_rate_limit.go:162`。
2. handler 用信封 `{"code":<HTTP 整数>,"message","reason","metadata"}`（`pkg/response/response.go:15-21,71-96`），例如 REFRESH_TOKEN_INVALID（`service/auth_service.go:35`）、OPS_DISABLED（`service/ops_service.go:19`）。
3. 其他：合规 423 返回 `{"code":"ADMIN_COMPLIANCE_ACK_REQUIRED","message","metadata"}`，没有 reason（`server/middleware/admin_compliance.go:35-45`）；登录 / 刷新限流 429 返回 `{"error":"rate limit exceeded","message"}`，code、reason 都没有（`middleware/rate_limiter.go:169-181`）；后端模式 403 用 response.Forbidden，没有 reason（`server/middleware/backend_mode_guard.go:25,90`；`handler/auth_handler.go:747`；登录路径 159 行有 BACKEND_MODE_ADMIN_ONLY）；2FA 临时会话过期返回 400，也没有 reason（`handler/auth_handler.go:325`）。

Web 两种格式都认：`frontend/src/composables/useStepUp.ts:46-50` 同时看 code 和 reason，`frontend/src/api/client.ts:146` 按字符串 code 识别合规。App 现在解码失败是客户端问题，见附录 B L1。

**建议改法**（code 保持原类型，所有错误一律加字符串 reason）：
1. middleware.ErrorResponse 加 `reason`（值同 code）和可选 `metadata`：`{"code":"TOKEN_EXPIRED","message":"Token has expired","reason":"TOKEN_EXPIRED"}`。
2. 合规 423 加 `"reason":"ADMIN_COMPLIANCE_ACK_REQUIRED"`（metadata 保留）。
3. 限流 429 加 `"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":<秒>`，保留 error、message 字段和 Retry-After 头。
4. 补上缺失的 reason：后端模式 403 用 `BACKEND_MODE_ADMIN_ONLY` 或 `BACKEND_MODE_SELF_SERVICE_DISABLED`；2FA 临时会话失效用 400 `TOTP_LOGIN_SESSION_EXPIRED`。
5. 公布稳定错误码清单（写进 `docs/`）：

| HTTP | reason | App 处理 |
|---|---|---|
| 401 | TOKEN_EXPIRED | 刷新令牌后重试 |
| 401 | INVALID_TOKEN、TOKEN_REVOKED、USER_NOT_FOUND、USER_INACTIVE、SESSION_BINDING_MISMATCH、REFRESH_TOKEN_INVALID、REFRESH_TOKEN_EXPIRED、REFRESH_TOKEN_REUSED（A03 新增）；UNAUTHORIZED、INVALID_AUTH_HEADER、EMPTY_TOKEN（缺少或格式错误的 Authorization 头，`server/middleware/jwt_auth.go:43,50,56`；`admin_auth.go:66,78`） | 重新登录 |
| 401 | INVALID_ADMIN_KEY | 重新输入 Key |
| 401 | INVALID_CREDENTIALS | 提示密码错误 |
| 403 | STEP_UP_REQUIRED | 弹 TOTP，`POST /api/v1/user/totp/step-up` 后重试 |
| 403 | STEP_UP_TOTP_NOT_ENABLED | 提示先在 Web 启用 2FA |
| 403 | STEP_UP_ADMIN_API_KEY_FORBIDDEN | 提示改用账号登录 |
| 403 | FORBIDDEN、WORKSPACE_DISABLED、BACKEND_MODE_ADMIN_ONLY、USER_NOT_ACTIVE | 无权限 |
| 423 | ADMIN_COMPLIANCE_ACK_REQUIRED | App 内展示协议，`POST /api/v1/admin/compliance/accept {phrase,language}` |
| 404 | OPS_DISABLED | 显示“运维监控未开启” |
| 400 | TOTP_INVALID_CODE、*_CAPTCHA_VERIFICATION_FAILED | 重新输入 |
| 429 | RATE_LIMITED、TOTP_TOO_MANY_ATTEMPTS | 稍后再试 |
| 503 | STEP_UP_UNAVAILABLE、SERVICE_UNAVAILABLE、CAPTCHA_PROVIDER_CONFLICT | 暂时性错误，不清除会话 |

**实现提示**：`server/middleware/middleware.go:63-81` 的 ErrorResponse 加 `Reason string json:"reason,omitempty"`，AbortWithError 填 Reason=code，所有调用点自动生效（含网关 `api_key_auth.go`，对 /v1 网关客户端只多一个字段）。`admin_compliance.go:35` 的 gin.H 加 reason；`middleware/rate_limiter.go:177` 的 gin.H 加 code、reason、retry_after；`backend_mode_guard.go:25,90` 与 `handler/auth_handler.go:747` 改成 `response.ErrorWithDetails(c,403,msg,"BACKEND_MODE_…",nil)`；`handler/auth_handler.go:325` 改成 `response.ErrorFrom(c, infraerrors.BadRequest("TOTP_LOGIN_SESSION_EXPIRED", …))`。在 handler 层加一个表驱动测试，防止错误码被改名。Web 回归：useStepUp.ts 先看 code 再看 reason，client.ts:146 用字符串 code，都不受影响。

**App 退路**：ErrorReply 的 code 按 Int 或 String 兼容解码，marker = reason ?? 字符串 code（Web 就是这样做的），不等后端就能识别全部中间件错误码。改之前仍拿不到 marker 的只有：限流 429（按 HTTP 状态处理）、后端模式 403（按普通“无权限”处理）、2FA 临时会话过期 400（提示“验证超时，请重新登录”）。

**验收**：
1. 过期 access token 访问 `GET /api/v1/admin/dashboard/stats`：401，reason=TOKEN_EXPIRED，code 仍是字符串 `"TOKEN_EXPIRED"`。
2. step_up_enabled 开启时 `curl -s -H "x-api-key: $KEY" "$BASE/api/v1/admin/accounts/data"`：403，reason=STEP_UP_ADMIN_API_KEY_FORBIDDEN。
3. 新管理员未确认合规时请求任意 admin 接口：423，reason=ADMIN_COMPLIANCE_ACK_REQUIRED。
4. 同一 IP 一分钟内 `POST /api/v1/auth/login` 21 次：第 21 次 429，reason=RATE_LIMITED，并带 Retry-After 头。
5. Web 的 client 与 useStepUp 相关 vitest 全部通过，合规跳转和 step-up 弹窗行为不变。

---

#### A07 · 会话列表与单独下线：`GET /api/v1/auth/sessions`、`DELETE /api/v1/auth/sessions/:id` 〔P2 · 新接口〕

**页面**：设置 → 安全（设计稿目前只有 Face ID 开关，没有会话列表，属后续能力）。

**背景**：管理员想看哪些设备在登录；手机丢了能只踢那一台；App 登录时给会话起个名字。

**现状**：只有 `POST /api/v1/auth/revoke-all-sessions` 和 `POST /api/v1/auth/logout`（`server/routes/auth.go:58,259`；`handler/auth_handler.go:771-814`）。logout 只删传入的那一个 refresh token（`service/auth_service.go:1864-1875`）。服务内部已有会话家族（family_id = JWT sid，`service/auth_service.go:60-70,1689-1722`）和 RevokeSessionFamily（1877-1884），但没有列出会话、按会话撤销的接口；RefreshTokenData 没有设备名、平台、最后活跃时间（`service/refresh_token_cache.go:14-21`）；LoginRequest 不接受 device_name（`handler/auth_handler.go:80-86`）。

**建议改法**：
1. 登录接受 A04 的 `client` 字段；device_name 最长 64 字符，过滤控制字符。
2. `GET /api/v1/auth/sessions`（JWT）：

```json
{"code":0,"message":"success","data":{"items":[{"id":"9f3c1a…","device_name":"我的 iPhone","client_type":"ios","user_agent":"Sub2Mobile-iOS","ip":"203.0.113.24","created_at":"2026-10-17T09:41:00Z","last_seen_at":"2026-10-18T08:02:11Z","expires_at":"2026-11-16T09:41:00Z","current":true}]}}
```

3. `DELETE /api/v1/auth/sessions/:id`：撤销该会话家族，并让该 sid 的 access token 立即失效（依赖 A05）；删当前会话等于 logout；只能删自己的，id 不存在或属于他人都返回 404 `SESSION_NOT_FOUND`。
4. `POST /api/v1/auth/revoke-all-sessions` 加可选请求体 `{"keep_current":true}`，用于“踢掉其他设备”；不传时行为不变。
5. 可选（站长视角）：`GET /api/v1/admin/users/:id/sessions`、`DELETE /api/v1/admin/users/:id/sessions/:sid`。
6. Admin Key 没有会话，调用这些接口返回 403 FORBIDDEN。

**实现提示**：Redis `session_meta:{family_id}` HASH 存 user_id、device_name、client_type、ua、ip、created_at、last_seen_at（TTL = refresh TTL）；`user_sessions:{user_id}` ZSET 存 family_id，score = last_seen。GenerateTokenPair 在 familyID=="" 时写入（新会话；IP / UA 取 `service.SessionBindingFromContext`）；RefreshTokenPair 每次轮换更新 last_seen 并续期，不要每个请求都写；DeleteTokenFamily、DeleteUserRefreshTokens 同时清理元数据。`current` 用 ContextKeySessionID 判断（`server/middleware/jwt_auth.go:104`）。路由挂在 `server/routes/auth.go` 的 authenticated 组（已有 jwtAuth、BackendModeUserGuard、面板限流），DELETE 记入审计。列表按 last_seen 倒序，最多 50 条。

**App 退路**：退出时只撤销本机 refresh token；要踢其他设备只能 `POST /api/v1/auth/revoke-all-sessions` 全部踢掉（App 可以先接），并提示 A05 的 24 小时窗口。

**验收**：
1. 带 device_name 登录后，`GET /api/v1/auth/sessions` 有这一条且 current=true。
2. 另一台设备登录后列表 2 条；DELETE 另一条后，那台设备的 refresh 返回 401 REFRESH_TOKEN_INVALID，下一次 API 请求返回 401（需 A05）。
3. DELETE 不存在的 id 或他人的 id，返回 404 SESSION_NOT_FOUND。
4. Web 不带 client 登录也出现在列表中，client_type=web，device_name 为空。

---

#### A08 · 可选：按设备签发、可命名、可限权、会过期、能单独吊销的管理访问令牌（sat_），与 Admin Key 并存 〔P2 · 新能力〕

**页面**：登录（Admin Key 方式）、设置 → 站点与凭据。

**背景**：手机里存的是全站唯一的 Admin Key，丢手机就等于泄露全站最高权限；Admin Key 做不了 step-up，敏感操作一律被拒；审计里所有 Admin Key 操作都记在第一个管理员名下。

**现状**：后端只有一把 Admin Key：`GET/POST/DELETE /api/v1/admin/settings/admin-api-key`（`server/routes/admin.go:628-630`）。匹配成功后一律映射为第一个管理员（`server/middleware/admin_auth.go:121-154`，140 行 GetFirstAdmin），auth_method=admin_api_key；合规也按第一个管理员判定（`server/middleware/admin_compliance.go:25`）。step-up 对 Admin Key 一律拒绝（`server/middleware/step_up.go:104-107`）。`/auth/me` 不接受 Admin Key（`server/routes/auth.go:250-257`）。替代路径已存在：账号 + 密码 + TOTP 登录得到的 JWT 会话天然按设备（每次登录一个 sid），可单独 logout，支持 step-up（`handler/totp_handler.go:206-230`，授权按 sid 绑定，`server/middleware/step_up.go:32-37`）。

**建议改法**（可选，优先级低于 A07）：
- `POST /api/v1/admin/access-tokens`：只允许 JWT 会话调用且要求 step-up，Admin Key 不能创建。请求 `{"name":"我的 iPhone","expires_in_days":90,"scope":"write"}`（scope 取 `read` 或 `write`），返回 201：

```json
{"code":0,"message":"success","data":{"id":12,"name":"我的 iPhone","token":"sat_3f…（只显示这一次）","scope":"write","expires_at":"2027-01-16T00:00:00Z"}}
```

- `GET /api/v1/admin/access-tokens` → `[{id,name,prefix:"sat_3f9a",last4,scope,expires_at,last_used_at,last_used_ip,created_at}]`，不含令牌原文。
- `DELETE /api/v1/admin/access-tokens/:id`：立即吊销。
- 使用：请求头 `x-api-key: sat_…`；主体是令牌所属的管理员，不再是第一个管理员；auth_method=`admin_access_token`。
- 错误码：scope=read 时写方法返回 403 `ACCESS_TOKEN_READ_ONLY`；过期 401 `ACCESS_TOKEN_EXPIRED`；已吊销或不存在 401 INVALID_ADMIN_KEY；访问 step-up 接口仍 403 STEP_UP_ADMIN_API_KEY_FORBIDDEN。
- 现有 Admin Key 不变，Web 不受影响。

**实现提示**：ent 新表 `admin_access_tokens(id, user_id, name, token_hash sha256, prefix, scope, expires_at, last_used_at, last_used_ip, revoked_at, created_at)`，配 migration 和 repository。`server/middleware/admin_auth.go:121-154` 的 validateAdminAPIKey 先按 `sat_` 前缀分流到新表；令牌哈希查询结果本地 LRU 缓存 30–60 秒，吊销时主动失效；last_used_at 每 5 分钟最多更新一次。`step_up.go:104` 的判断扩展为同时拒绝 admin_access_token。审计（AuditAuthMethod 常量）加新类型并记录真实用户。read scope 在 adminAuth 之后加一个中间件拦截 POST / PUT / PATCH / DELETE。创建路由挂 stepUpAuth。

**App 退路**：默认推荐“账号 + 密码 + TOTP”登录；Admin Key 登录保留但标“不推荐”，敏感操作提示改用账号登录；设置页注明“Admin Key 以第一个管理员身份操作，丢失设备请到 Web 重新生成 Key”。

**验收**：
1. JWT 会话完成 step-up 后 POST 返回 sat_ 令牌。
2. `curl -H 'x-api-key: sat_…' "$BASE/api/v1/admin/dashboard/stats"` 返回 200，审计操作人是令牌所属管理员。
3. scope=read 的令牌执行 `PUT /api/v1/admin/users/1` 返回 403 ACCESS_TOKEN_READ_ONLY。
4. DELETE 该令牌后再用返回 401 INVALID_ADMIN_KEY。
5. 旧 Admin Key 照常可用。

---

#### A09 · 验证码字段语义与提供方声明：可选 `aliyun_captcha_param` / `captcha_provider`，公开设置给出生效的提供方 〔P2 · 加参数〕

**页面**：登录（以及以后的注册、找回密码、Passkey 登录）。

**背景**：开了验证码的站点，原生 App 也要能登录。桥页并入主线已在 A01；本条处理剩下的字段语义和提供方声明。

**现状**：
- LoginRequest 只有 turnstile_token、tencent_captcha_ticket、tencent_captcha_randstr（`handler/auth_handler.go:80-94`）；阿里云的 captchaVerifyParam 塞在 turnstile_token 里（`service/auth_service.go:433-437`；d75c49405 的 `docs/mobile-verification.md` 写明是有意复用）。
- 公开设置分别给三个 enabled（`handler/dto/settings.go:390-398`），没有“实际生效的是哪一个”。
- 同时开启多个时后端本身就拒绝登录：503 CAPTCHA_PROVIDER_CONFLICT（`service/auth_service.go:50,416-426,452-460`）；Web 设置页也是互斥的（`frontend/src/i18n/locales/zh/admin/settings.ts:245`）。这部分不用改。
- Passkey 登录开始接口在开启腾讯或阿里云验证码时也要验证码（`handler/passkey_handler.go:83-86` → `service/auth_service.go:464-497`）。

**建议改法**（只增）：
1. `POST /api/v1/auth/login`、`/auth/register`、`/auth/send-verify-code`、`/auth/passkey/login/begin` 新增可选字段 `captcha_provider`（`turnstile` | `tencent` | `aliyun`）与 `aliyun_captcha_param`。阿里云启用时优先读 aliyun_captcha_param，为空才回退 turnstile_token，Web 继续用旧字段。声明的 provider 与站点当前生效的不一致时返回 400 `CAPTCHA_PROVIDER_MISMATCH`（“站点验证码已变更，请重新验证”）。
2. `GET /api/v1/settings/public` 新增 `{"captcha_provider":"aliyun","mobile_verify_path":"/mobile/verify"}`：`captcha_provider` 取 `""` | `turnstile` | `tencent` | `aliyun` | `conflict`，判定逻辑与 VerifyCaptcha 相同；`mobile_verify_path` 只在前端包含桥页时给出，App 据此判断桥页是否已部署。
3. 受信设备免验证码、App Attest 暂不建议做：会削弱登录防刷，管理员在 App 上登录的频率很低，桥页够用。以后要做，可以在 A04 方案 B 的设备密钥会话上允许“已绑定设备密钥 + 仍有效的 refresh 会话”重新登录时免验证码。

**实现提示**：`handler/auth_handler.go` 的 LoginRequest、RegisterRequest、SendVerifyCodeRequest（53-86）加两个 omitempty 字段；captchaProof（88-94）接收阿里云参数，service.CaptchaProof 加 AliyunParam；`service/auth_service.go:433-437` 与 482-486 改为 `param := proof.AliyunParam; if param == "" { param = proof.TurnstileToken }`；provider 不一致的校验放在 VerifyCaptcha 开头。`handler/passkey_handler.go:82-86` 同样处理。公开设置：`handler/setting_handler.go:46` 起的 dto.PublicSettings 加 CaptchaProvider，复用 GetCaptchaProviderConfig 的判定；mobile_verify_path 由构建时注入的常量决定，或检查嵌入的 dist 里有没有 MobileVerifyView 分片。

**App 退路**：WKWebView 加载 `/mobile/verify`，经 messageHandler 拿到证明（120 秒有效）；阿里云继续用 turnstile_token 提交；多个验证码同时开启时拒绝登录，提示“站点验证码配置冲突，请在 Web 后台修正”（与 CAPTCHA_PROVIDER_CONFLICT 一致）；页面不存在时让用户改用 Web。

**验收**：
1. 阿里云站点：只带 aliyun_captcha_param、不带 turnstile_token 的 `POST /api/v1/auth/login` 能通过验证码校验；Web 旧方式照常可用。
2. `GET /api/v1/settings/public` 返回 `captcha_provider="aliyun"`。
3. 带 `captcha_provider="turnstile"` 登录阿里云站点返回 400 CAPTCHA_PROVIDER_MISMATCH。
4. 同时开启两个提供方时 `captcha_provider="conflict"`，登录仍返回 503 CAPTCHA_PROVIDER_CONFLICT。

---

#### A10 · 后端提供 `/.well-known/apple-app-site-association`（App ID 可在设置里配），支持原生 Passkey 与密码自动填充 〔P2 · 新接口〕

**页面**：登录（Passkey、钥匙串自动填充）。

**背景**：后端已有 Passkey 登录。iOS 原生用 ASAuthorization 发起 Passkey，需要站点用 webcredentials 声明关联的 App；钥匙串按站点自动填密码也依赖这个声明。

**现状**：Passkey 登录接口 `POST /api/v1/auth/passkey/login/begin`、`/finish`（`server/routes/auth.go:44-49`）；RP 由配置 webauthn.rp_id、rp_origins 决定（`service/passkey.go:122-130`；`config/config.go:718-725`）；公开设置有 passkey_enabled（`handler/dto/settings.go:384`）。前后端都没有 apple-app-site-association（本地与 origin/main 都搜不到），也没有配置 App ID 的地方。不能靠覆盖目录补这个文件：FrontendServer 对 dist 里不存在的路径一律回落 index.html（`web/embed_on.go:101-105`），`data/public` 覆盖目录只对 dist 已有的文件生效（`web/embed_on.go:107-111,131-143`）。

**建议改法**：
- `GET /.well-known/apple-app-site-association`：无扩展名、不重定向、不需要认证，`Content-Type: application/json`，`Cache-Control: max-age=3600`。内容按设置生成：`{"webcredentials":{"apps":["ABCDE12345.com.example.sub2mobile"]}}`，以后需要时再加 applinks。
- `GET/PUT /api/v1/admin/settings` 新增 `apple_app_ids`（字符串数组，每项匹配 `^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$`）；为空时该路径返回 404。
- 部署文档写明：webauthn.rp_id 必须等于站点域名；rp_origins 要包含 `https://<域名>`（iOS 原生断言的 clientDataJSON.origin 就是它）；开启腾讯或阿里云验证码时，原生 Passkey 也要先经 `/mobile/verify` 拿到验证码证明再调 begin。

**实现提示**：在路由初始化处（`server/routes/common.go` 或 server 的 router 装配）、前端中间件之前注册 `r.GET("/.well-known/apple-app-site-association", h)`；`web/embed_on.go:355-385` 的 shouldBypassEmbeddedFrontend 加前缀 `/.well-known/`，否则会被 SPA 吞掉，ServeEmbeddedFrontend 中 303-339 那段同理。设置：`service/domain_constants.go` 加 key，`setting_parse.go`、`setting_update.go`、`handler/dto/settings.go` 加字段，修改记入审计。handler 读的是已缓存的设置。

**App 退路**：站长可以直接在反向代理上返回静态文件（`location = /.well-known/apple-app-site-association { default_type application/json; … }`），不必改后端。在此之前 App 只支持邮箱 + 密码 + TOTP 或 Admin Key 登录，不提供 Passkey。iOS 的 Associated Domains 要在构建时写死域名，而 App 支持任意添加站点，所以 Passkey 只能用于构建时列入的站点（见附录 C Q8）。

**验收**：
1. `curl -sI "https://<站点>/.well-known/apple-app-site-association"`：200、Content-Type: application/json、没有 3xx。
2. body 的 webcredentials.apps 包含配置的 App ID。
3. `https://app-site-association.cdn-apple.com/a/v1/<域名>` 能拿到同样的内容。
4. App 用 `ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp_id)` 走完 passkey/login/begin 和 finish 后拿到令牌对。
5. apple_app_ids 为空时返回 404，Web 首页不受影响。

---

#### A11 · 可选 / 未来：出站推送（APNs）——设备注册与订阅接口，推送只带可跳转的 ID 〔P2 · 新能力〕

**页面**：监控 Tab 告警；概览待处理；账号异常与限流；新建账号“后台继续”与账号测试完成。（余额待核对是 App 本地状态，不在此列。）

**背景**：告警、账号异常、测试完成要在 App 不在前台时也能送达，点开通知直接进对应的告警或账号。当前的设计决定是前台约 60 秒自动刷新加下拉刷新（`DECISIONS.md:46`），没有决定做推送。

**现状**：后端只有邮件通知：告警规则只有 notify_email，告警事件只记 email_sent（`service/ops_alert_models.go:32,58`）；告警生成后只调 maybeSendAlertEmail（`service/ops_alert_evaluator_service.go:287-297,678-745`）；邮件事件有 13 类（`service/notification_email_service.go:23-35`）。全仓库的 webhook 只有支付回调入站，没有 APNs 等出站推送，也没有设备注册或订阅接口（`research/02-backend-capability-map.md:347-348,360`）。账号出错的写入点在 `service/ratelimit_service.go:971-973`。

**建议改法**：
- 设备：`POST /api/v1/admin/push/devices`，请求体 `{"platform":"ios","apns_token":"<hex>","bundle_id":"com.example.sub2mobile","environment":"production","device_name":"我的 iPhone","locale":"zh-Hans","timezone":"Asia/Shanghai"}`，返回 201 `{"id":7}`；同一 token 重复注册时幂等更新。另有 `GET /api/v1/admin/push/devices`（只返回自己的）、`DELETE /api/v1/admin/push/devices/:id`、`POST /api/v1/admin/push/devices/:id/test`。
- 订阅：`PUT /api/v1/admin/push/devices/:id/subscription`

```json
{"events":["ops_alert.fired","ops_alert.resolved","account.error","account.test_finished"],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":{"start":"23:00","end":"07:00"}}
```

- 站点配置：admin settings 新增 apns_enabled、apns_team_id、apns_key_id、apns_private_key（p8，只写不回显，写入需要 step-up）、apns_topic、apns_environment。
- 推送内容只带 ID，不带凭据或用户数据；App 收到后用现有接口（如 `GET /api/v1/admin/ops/alert-events/:id`）取详情：

```json
{"aps":{"alert":{"title":"[P1] 错误率 12.3%","body":"Claude 分组 · 持续 5 分钟"},"thread-id":"ops-alert","interruption-level":"time-sensitive"},"site":"api.example.com","type":"ops_alert.fired","alert_event_id":881}
```

- 错误码：400 `INVALID_PUSH_TOKEN`；503 `PUSH_NOT_CONFIGURED`。
- 更轻的 MVP：先做通用 Webhook 或 Bark / ntfy 出站通道，站点上不放 Apple 私钥。

**实现提示**：新表 `push_devices(user_id, platform, token_hash, token_enc, bundle_id, env, device_name, locale, tz, prefs JSON, last_success_at, disabled_reason, created_at)`；Redis 列表做发送队列，带重试和按事件去重；APNs 用 HTTP/2 + ES256 JWT（例如 `github.com/sideshow/apns2`），返回 410 Unregistered 时停用设备；多实例复用 `service/ops_alert_evaluator_service.go:906` 的 tryAcquireLeaderLock 避免重复发送。挂钩点：`ops_alert_evaluator_service.go:287-297`（新告警）与告警解决处；`ratelimit_service.go:971-973`（凭据错误）；`account_test_service.go` 与 `scheduled_test_runner_service.go`（测试完成）。限流类事件量大，需要聚合或节流；免打扰按设备时区计算。

**App 退路**：前台 30–60 秒自动刷新加下拉刷新，进后台就停止；BGAppRefreshTask 尽力拉取 alert-events（系统不保证执行时间）；账号测试“后台继续”只在 App 存活期间有效（beginBackgroundTask 约 30 秒，结束时发本地通知）。Info.plist 暂不申请推送权限。

**验收**：
1. 注册设备返回 201，重复注册幂等。
2. 触发一条 P1 测试告警，APNs sandbox 收到带 alert_event_id 的推送，点开进入告警详情。
3. 免打扰时段内不推送。
4. APNs 返回 410 后设备变为停用。
5. 双实例部署只发送一次。
6. 未配置 APNs 时 `POST /api/v1/admin/push/devices/:id/test` 返回 503 PUSH_NOT_CONFIGURED。

---

### B 概览与统计

#### B01 · 新增不受运维监控开关限制的近 N 分钟速率 `GET /api/v1/admin/dashboard/rates` 〔P1 · 新接口〕

**页面**：概览 6 格（错误率、RPM、TPM）与平静布局顶部 6 格；运行区；监控 · 概况；统计分析 RPM / TPM 趋势。

**背景**：用户 2026-10-18 确认：6 格 = 今日实际扣费、请求、错误率、利润、RPM、TPM；错误率 / RPM / TPM 都是近 5 分钟但不写后缀；TPM 含缓存 Tokens，首页格子要和点进去的 RPM / TPM 趋势同口径；站点没开运维监控时也要有同口径的值（`DECISIONS.md:120-121,132-137`；`html-preview/layouts/main/v-today.jsx:23-35`；`html-preview/shared/data.jsx:154-156`）。

**现状**：
1. dashboard/stats：tpm = 近 5 分钟 SUM(input_tokens + output_tokens) ÷ 5，整数除法截断、不含缓存（`repository/usage_log_repo_dashboard.go:14-35`，GetDashboardStats 在 93-98 写入）。40bee5d2e 的 rpm = 近 5 分钟 usage_logs 条数 ÷ 5；origin/main 改成 Redis 近 60 秒成功上游转发数，并加了 rpm_available（`origin/main:service/dashboard_runtime_rpm.go:19-62`、`origin/main:repository/rpm_rolling_cache.go:96-118`、`origin/main:handler/admin/dashboard_handler.go:129-131`）。DashboardStats 没有错误数或错误率（`pkg/usagestats/usage_log_types.go:28-80`）。Web 首页读 stats.rpm / stats.tpm（`frontend/src/views/admin/DashboardView.vue:184,190`），这两个字段不能改语义。
2. 开监控时已有完全同口径的一次请求：`GET /api/v1/admin/ops/dashboard/overview?time_range=5m` 返回 start_time、end_time、success_count、error_count_total、error_count_sla、request_count_total、token_consumed、error_rate（`service/ops_dashboard_models.go:41-80`；`repository/ops_repo_dashboard.go:95-200`）。用量 = SUM(input + output + cache_creation + cache_read)（`ops_repo_dashboard.go:836-855`），错误 = status_code ≥ 400 且 is_count_tokens = FALSE（:915-948，buildErrorWhere :1057-1091），与 throughput-trend 用同一组 where（`repository/ops_repo_trends.go:35-98`）。5 分钟窗口里没有整小时，preagg 模式也回落 raw（`ops_repo_dashboard.go:239-242`）。现有 App 已经在调它，只取了 error_rate（`sub2-mobile-native/Sources/Sub2Core/APIClient.swift:115-120`）。
3. 关监控时拿不到值：overview、throughput-trend、realtime-traffic 都先走 RequireMonitoringEnabled，返回 404 OPS_DISABLED（`handler/admin/ops_dashboard_handler.go:22-25,63-66`；`service/ops_service.go:19,146-165`；`handler/admin/ops_realtime_handler.go:210-213`）。更根本的是关监控时错误根本不写库：OpsErrorLoggerMiddleware 直接 return（`handler/ops_error_logger.go:1101-1103`），prepareErrorLogInput 也直接返回（`service/ops_service.go:465-467`），重新开启后也补不回来。realtime-traffic 的 qps / tps 四舍五入到 0.1（`repository/ops_repo_realtime_traffic.go:95-100`），换算成 RPM 精度只有 ±6。

**建议改法**：

一、新接口（只增，不动 dashboard/stats 的 rpm / tpm）：`GET /api/v1/admin/dashboard/rates?window=5m[&platform=][&group_id=]`。window = `1m` | `5m` | `15m`，默认 5m；platform、group_id 规则同 ops/dashboard/*；不调用 RequireMonitoringEnabled。

```json
{"code":0,"message":"success","data":{
  "window_seconds":300,"start_time":"2026-10-18T01:36:23Z","end_time":"2026-10-18T01:41:23Z",
  "success_count":230,"error_count":2,"error_count_sla":2,"request_count":232,"token_consumed":1200000,
  "rpm":46.4,"tpm":240000.0,"error_rate":0.0086,"upstream_429_count":1,"upstream_529_count":0,
  "ops_monitoring_enabled":true,"errors_available":true,"rpm_includes_errors":true}}
```

- 口径：request_count = success_count + error_count（error_count 与 throughput-trend 一致：status ≥ 400、排除 count_tokens、含业务限流）；rpm = request_count × 60 ÷ window_seconds，tpm = token_consumed × 60 ÷ window_seconds，都用浮点、不截断；error_rate = error_count_sla ÷ (success_count + error_count_sla)，与 overview.error_rate 一致。
- 关监控时：error_count、error_count_sla、error_rate、upstream_* 为 null，errors_available=false，rpm_includes_errors=false，request_count = success_count；tpm 不受影响（usage_logs 一直在写）。
- 错误码：400 "Invalid window"、400 "Invalid group_id"；401 / 403 沿用 admin 鉴权。不加入 vendor 白名单（默认 403）。

二、可选（用户坚持“关监控也要错误率”时才做，见附录 C Q2）：在 OpsErrorLoggerMiddleware 的开关判断之前做最小分类（status ≥ 400 或流式失败；业务限流单独计），写 Redis 每秒计数桶；关监控时 rates 改读计数，返回 `"errors_source":"counter"`。

三、可选：dashboard/snapshot-v2 增加 `include_rates=true`，把同一对象放到 `stats.rates`，首页少一次请求。

**实现提示**：
- `repository/ops_repo_dashboard.go` 新增导出方法 `GetLiveRates(ctx, filter, includeErrors bool)`，直接复用 queryUsageCounts（:836）与 queryErrorCounts（:915），保证与 overview、throughput-trend 同口径。service.OpsService 加 GetLiveRates，不调 RequireMonitoringEnabled，用 IsMonitoringEnabled（`service/ops_service.go:153`）决定 includeErrors。handler 放在 OpsHandler（或给 DashboardHandler 注入 opsService），路由加在 `server/routes/admin.go` registerDashboardRoutes（:298-315）：`dashboard.GET("/rates", …)`。
- end 取请求时刻截到整秒，start = end − window。缓存用 `usagequery.NewCache(5*time.Second)` + scopedUsageCacheKey（`handler/admin/usage_query_context.go:21-36`），key = window + platform + group_id + end 截到 5 秒，避免多端 60 秒轮询打库。只扫最近 5 分钟，走 usage_logs(created_at) 与 ops_error_logs(created_at DESC) 索引。
- buildUsageWhere / buildErrorWhere 目前不处理 `service.UsageAccountScopeFrom`；以后若要对 vendor 开放，要像 appendUsageAccountScope 一样加账号白名单。
- 第二阶段计数：Redis key 例如 `rate:{live}:sec:<unix>`，HINCRBY total / err / err_sla，EXPIRE 900，多实例共享；写失败只记日志，不影响网关；分类逻辑从 `handler/ops_error_logger.go:1112-1176` 抽出能在开关判断前运行的部分（status、stream failure、classifyOpsErrorLog 的 isBusinessLimited）。

**App 退路**：开监控时（默认开：`config/config.go:2316` ops.enabled=true）首页只用已在调用的 overview?time_range=5m：窗口秒数 = end_time − start_time；RPM = round(request_count_total × 60 ÷ 窗口秒数)，TPM = token_consumed × 60 ÷ 窗口秒数，错误率 = error_rate（比 `DECISIONS.md:137` 与 `v-today.jsx:28-31` 写的“throughput-trend 最近 5 桶之和 ÷ 5”准：末桶不满时那种算法偏低，平均约 10%、最多 20%）。overview 返回 404 OPS_DISABLED 时，RPM / TPM 退回 dashboard/stats 的 rpm / tpm（只算成功、不含缓存，规格里注明口径），错误率显示“—”。

**验收**：

```bash
curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/dashboard/rates?window=5m" | jq .data
curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/ops/dashboard/overview?time_range=5m" | jq '.data|{request_count_total,token_consumed,error_rate}'
```

1. 同一时刻两者对比：request_count ≈ request_count_total、token_consumed 相等、error_rate 相等（只差窗口边界）。
2. 系统设置 ops_monitoring_enabled 设为 false 后 rates 仍返回 200，error_* 为 null，errors_available=false，tpm 仍含缓存。
3. dashboard/stats 的 rpm / tpm 与改动前一致（Web 不受影响）。
4. 单测：非法 window 返回 400；无流量时计数为 0 而不是 null。

---

#### B02 · dashboard/trend（及 snapshot-v2 的 trend）每个点加 account_cost，利润明细一次取回；用户侧趋势必须剥离 〔P1 · 加字段〕

**页面**：统计分析 · 利润明细卡、利润明细单图页（按小时 / 按天的利润柱图与明细表）；计费趋势卡的利润合计。

**背景**：评审意见第 4 条：加“利润明细”，按小时 / 按天显示实际扣费、账号成本、利润（`DECISIONS.md:123`；`html-preview/layouts/main/v-analytics.jsx:16-22`）。

**现状**：
- TrendDataPoint 只有 cost（标准）和 actual_cost（实际），没有 account_cost（`pkg/usagestats/usage_log_types.go:82-93`）；ModelStat、GroupStat、UserBreakdownItem 都有 account_cost（:95-107、126-135、167-179）。
- 原始趋势 SQL 在 `repository/usage_log_repo_trend.go:316-332`，预聚合趋势在 :410-476，共用 scanTrendRows（:912-935）。预聚合表 usage_dashboard_hourly 已有 account_cost 列（`migrations/107_add_account_cost_to_dashboard_tables.sql:4`），口径与 ModelStat 一致（`repository/dashboard_aggregation_repo.go:439`）。
- 用户侧 `GET /api/v1/usage/dashboard/trend` 复用同一个 repo 方法和结构体（`handler/usage_handler.go:465-488,556`）。

**建议改法**：`GET /api/v1/admin/dashboard/trend`（参数不变）每个点增加 `account_cost`，口径 = provider_cost_recorded 时 COALESCE(account_stats_cost, total_cost) × COALESCE(account_rate_multiplier, 1)，与 dashboard/models 的 account_cost 相同：

```json
{"date":"2026-10-18 09:00","requests":2290,"total_tokens":12000000,"cost":160.2,"actual_cost":128.45,"account_cost":51.2}
```

dashboard/snapshot-v2 的 trend 同样带上。用户侧 `/api/v1/usage/dashboard/trend` 不能出现这个字段。

**实现提示**：
1. TrendDataPoint 加 `AccountCost *float64 json:"account_cost,omitempty"`（用指针，用户侧置 nil 后字段直接消失）。
2. 原始查询加 `COALESCE(SUM(CASE WHEN provider_cost_recorded THEN COALESCE(account_stats_cost, total_cost) * COALESCE(account_rate_multiplier, 1) ELSE 0 END), 0) AS account_cost`；预聚合查询的 valid_buckets 与 raw 两段 pieces 都加（`usage_log_repo_trend.go:442-458`）。
3. scanTrendRows 被 GetUserUsageTrendByUserID（:254-293）共用：要么三条 SQL 都加这一列，要么另写 scanTrendRowsWithAccountCost。
4. 安全：在 `handler/usage_handler.go` 的 DashboardTrend（:465-488）和 :556 那条路径里，参照 :415 对 stats 的做法把每点 AccountCost 置 nil。
5. origin/main 的趋势 SQL 已重构（`origin/main:repository/usage_log_repo_trend.go:340,442,961`），在 A01 基线上改。缓存 key 不用改。

**App 退路**：每个时段调一次 `usage/stats?start_time=&end_time=` 取 total_account_cost（今天 10 次、近 7 天 7 次、近 30 天 30 次），客户端并发上限 4；失败的段显示“—”，不补零。

**验收**：
1. `curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/dashboard/trend?start_date=2026-10-11&end_date=2026-10-17&granularity=day" | jq '[.data.trend[].account_cost]|add'` 等于同范围 usage/stats 的 total_account_cost（误差 < 0.01）。
2. 普通用户 token 调 `/api/v1/usage/dashboard/trend`，`jq '.data.trend[0]|has("account_cost")'` 为 false。
3. granularity=hour 走预聚合与走原始表（加 force_refresh=true）结果一致。

---

#### B03 · 使用记录、usage/stats、dashboard 趋势 / 分组 / 用户排行的 model 筛选接受 `model_source` 〔P1 · 加参数〕

**页面**：统计分析 · 模型排行（上游口径）→ 模型对象页 →“这个模型的使用记录”、趋势、用户拆分。

**背景**：排行切到“上游模型”口径后点进去，趋势、用户拆分、使用记录要用同一口径，否则数字对不上（`html-preview/shared/data.jsx:418-424`；`html-preview/layouts/main/v-analytics.jsx:9,39`）。

**现状**：repo 层已支持按口径匹配：appendUsageLogModelWhereCondition / appendUsageLogModelQueryFilter 接受 source（`repository/usage_log_repo.go:109-119,133-143`），表达式在 `repository/usage_log_repo_trend.go:889-910`。问题在 handler 把口径写死成 requested：admin/usage 列表（`handler/admin/usage_handler.go:193`）、usage/stats（:346）、dashboard 各接口的 usageFilters()（`handler/admin/dashboard_snapshot_v2_handler.go:309-311`）、getUsageTrendCached 等（`handler/admin/dashboard_query_cache.go:68,78,88`）。已经支持的有：dashboard/models（model_source 是分组维度，`handler/admin/dashboard_handler.go:236-240`）和 dashboard/user-breakdown（model_source 是筛选口径，`dashboard_handler.go:518-522` → `usage_log_repo_trend.go:714-717`）。

**建议改法**：`GET /api/v1/admin/usage`、`/admin/usage/stats`、`/admin/dashboard/trend`、`/admin/dashboard/snapshot-v2`、`/admin/dashboard/groups`、`/admin/dashboard/users-ranking`、`/admin/dashboard/users-trend` 都接受 `model_source` = `requested` | `upstream` | `mapping`（默认 requested），只影响 model 参数的匹配口径。mapping 的取值形如 `"claude-opus-4 -> claude-opus-4-20250514"`（与 dashboard/models?model_source=mapping 返回的 model 一致）。非法值返回 400 "Invalid model_source, use requested/upstream/mapping"（与 `dashboard_handler.go:238` 同文案）。dashboard/models 不变。

**实现提示**：dashboardSnapshotV2Filters 加 ModelSource，在 parseDashboardSnapshotV2Filters（`dashboard_snapshot_v2_handler.go:227-307`）里用 usagestats.IsValidModelSource 解析和校验，usageFilters() 改为使用它；`usage_handler.go` 的 List（:68）/ Stats（:226）同样解析并填进 ModelFilterSource。缓存 key 已包含 ModelFilterSource（`handler/admin/usage_query_cache.go:27,54`；loadDashboardQuery 序列化整个 filters，`dashboard_query_cache.go:52-65`）。带 model 时趋势本来就不走预聚合（`usage_log_repo_trend.go:387-409`）。COALESCE 表达式用不上 model 索引，但会先按 created_at 过滤；可用 (created_at, requested_model, upstream_model) 索引（`migrations/078_*`）。usage cleanup（`usage_handler.go:545`）保持 requested。

**App 退路**：上游 / 映射口径的排行行只开放“用户拆分”（user-breakdown 已支持 model_source）；趋势和使用记录要么隐藏入口，要么页头写明“按请求模型筛选，可能与上游口径不一致”。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/usage/stats?start_date=2026-10-11&end_date=2026-10-17&model=claude-opus-4-20250514&model_source=upstream" | jq '.data.total_requests'` 等于 `dashboard/models?model_source=upstream` 里该模型行的 requests；不带 model_source 时与改动前一致；model_source=x 返回 400。

---

#### B04 · 用户排行：users-ranking 加 sort_by、成本字段与“有用量的用户总数” 〔P2 · 加字段〕

**页面**：统计分析 · 用户排行卡（前 5）、全部排行（用户，可按实际扣费 / 请求 / Tokens 排）。

**背景**：排行能切指标排序，与模型、分组排行用同一套字段；显示“其余 N 位”；用户维度看利润（`html-preview/layouts/main/v-analytics.jsx:42-45`）。

**现状**：users-ranking 的 SQL 固定 `ORDER BY actual_cost DESC, tokens DESC`（`repository/usage_log_repo_trend.go:202,216`），limit 默认 12、最多 50（`handler/admin/dashboard_handler.go:372-381`），行只有 actual_cost / requests / tokens，响应只有三个合计、没有用户总数（`pkg/usagestats/usage_log_types.go:149-165`；`dashboard_handler.go:404`）。但 `GET /api/v1/admin/dashboard/user-breakdown` 已能满足大部分需求：sort_by 支持 total_tokens | input_tokens | output_tokens | cache_tokens | requests | cost | actual_cost（`dashboard_handler.go:573`；repo 白名单 `usage_log_repo_trend.go:755-760`），limit 最多 200（:575-580），行带 requests、total_tokens、cost、actual_cost、account_cost（`usage_log_types.go:167-179`），接受 start_time / end_time、group_id、model + model_source、user_id、account_id，不传维度就是全站排行。它缺 username、用户总数和范围合计，也不走 30s 查询缓存（直接调 service，`dashboard_handler.go:582-584`）。

**建议改法**（只增）：users-ranking 加可选 `sort_by` = `actual_cost` | `requests` | `tokens`（默认 actual_cost，Web 不变）；每行加 cost、account_cost；响应加 total_users（范围内有用量的用户数）、total_cost、total_account_cost。

```json
{"ranking":[{"user_id":7,"email":"a@x.com","username":"alice","actual_cost":210.5,"cost":260.1,"account_cost":88.2,"requests":3100,"tokens":15000000}],
 "total_users":143,"total_actual_cost":1284.5,"total_cost":1610.14,"total_account_cost":512.08,"total_requests":18204,"total_tokens":96400000}
```

非法 sort_by 返回 400 "Invalid sort_by, use actual_cost/requests/tokens"。也可以只在 user-breakdown 的响应里加 total_users、合计和每行 username。

**实现提示**：在 GetUserSpendingRankingWithFilters 的 user_spend CTE 加 `SUM(total_cost) FILTER (WHERE provider_cost_recorded) AS cost` 与 account_cost 表达式。注意两个基线的 SQL 不同：40bee5d2e 在 user_spend 前面还有一个 `scoped AS MATERIALIZED` CTE，只选了 user_id、四个 token 列和 actual_cost（`repository/usage_log_repo_trend.go:176-177`），要在那里同时补上 total_cost、provider_cost_recorded、account_stats_cost、account_rate_multiplier，否则 user_spend 取不到这些列；origin/main 已去掉 scoped，user_spend 直接聚合 usage_logs（`origin/main:repository/usage_log_repo_trend.go:213-222`），在 A01 基线上改只需动 user_spend。ranked 里加 `COUNT(*) OVER () AS total_users` 以及 `SUM(cost) / SUM(account_cost) OVER ()`；ORDER BY 走白名单映射。窗口函数在 LIMIT 之前计算，total_users 不受 LIMIT 影响。handler 里 loadDashboardQuery 的 dimension 现在是 `strconv.Itoa(limit)`（`dashboard_handler.go:396`），要改成 limit + sort_by，否则不同排序会命中同一份缓存。

**App 退路**：按请求 / Tokens 排、看用户利润，都用 user-breakdown（服务端真实排序）；“其余”的金额 = users-ranking 的 total_* − 前 N 之和，人数写“前 N 位”；user-breakdown 用 limit=200 返回不足 200 行时，行数就是精确人数。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/dashboard/user-breakdown?start_date=2026-10-11&end_date=2026-10-17&sort_by=requests&limit=50" | jq '[.data.users[].requests] | . == (sort | reverse)'` 为 true；改完后 `users-ranking?sort_by=tokens&limit=5` 的 total_users 等于同范围 `SELECT COUNT(DISTINCT user_id)`；不带 sort_by 时与改前一致。

---

#### B05 · 新增按 request_type 拆分的合计 `GET /api/v1/admin/dashboard/request-types` 〔P2 · 新接口〕

**页面**：统计分析 · 更多图表“请求类型”（sync / stream / ws_v2 / live / cyber）。

**背景**：统计分析要“与 Web 一样有全部图表信息”；请求类型图是 App 自拼的，Web 没有这张图（`html-preview/layouts/main/v-analytics.jsx:49`）。

**现状**：UsageStats 只有总计和 endpoints / upstream_endpoints / endpoint_paths 拆分（`pkg/usagestats/usage_log_types.go:298-314`；`repository/usage_log_repo_stats.go:797-802` GROUPING SETS），后端没有任何按 request_type 分组的统计。request_type 枚举：0 unknown、1 sync、2 stream、3 ws_v2、4 cyber、5 live（`service/usage_log.go:14-23`）；旧数据 request_type=0 时按 stream / openai_ws_mode 归类（`repository/usage_log_repo.go:232-249`）。目前只能 `usage/stats?request_type=` 一种一种查。

**建议改法**：`GET /api/v1/admin/dashboard/request-types?start_time=&end_time=`（或 start_date / end_date）`&timezone=&group_id=&model=&user_id=&account_id=…`，筛选沿用 parseDashboardSnapshotV2Filters，不接受 request_type / stream。

```json
{"request_types":[{"request_type":"stream","requests":12010,"total_tokens":70100000,"cost":1100.2,"actual_cost":880.4,"account_cost":350.1},
                  {"request_type":"sync","requests":6194,"total_tokens":26300000,"cost":509.9,"actual_cost":404.1,"account_cost":162.0}],
 "start_date":"2026-10-11","end_date":"2026-10-17","query":{"timezone":"Asia/Shanghai"}}
```

按 requests 降序，总和等于 usage/stats 的总计。错误码：400（时间或筛选参数不合法，与 dashboard/groups 相同）。

**实现提示**：新增 repo 方法 GetRequestTypeStatsWithUsageFilters，分组表达式与筛选条件一致：`CASE WHEN request_type IN (1,2,3,4,5) THEN request_type WHEN openai_ws_mode THEN 3 WHEN stream THEN 2 ELSE 1 END`，输出时转成 `service.RequestType(x).String()`。筛选拼接仿 getGroupStatsWithFilters（`repository/usage_log_repo_trend.go:588-679`，含 appendUsageAccountScope）；handler 仿 GetGroupStats（`handler/admin/dashboard_handler.go:257-278`），用 loadDashboardQuery 加 30s 缓存；路由加在 `server/routes/admin.go:298-315`。可用索引 idx_usage_logs_request_type_created_at（`migrations/061_add_usage_log_request_type.sql:19`）。只给 admin，不暴露到用户侧。

**App 退路**：`usage/stats?request_type=sync|stream|ws_v2|live|cyber` 并发 5 次后拼图；不传 unknown（旧数据已在 sync / stream / ws_v2 筛选里归类）。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/dashboard/request-types?start_date=2026-10-11&end_date=2026-10-17" | jq '[.data.request_types[].requests] | add'` 等于同范围 usage/stats 的 total_requests；每一项与 `usage/stats?request_type=<该类型>` 的合计相等。

---

#### B06 · ops/dashboard/*（overview、throughput-trend、latency-histogram、error-trend、error-distribution、openai-token-stats、snapshot-v2）增加 model（+ model_source）筛选 〔P2 · 加参数〕

**页面**：统计分析按模型筛选时的运行类图表（RPM / TPM、请求时长、错误趋势、错误分布、Token 请求统计）；模型对象页。

**背景**：按模型筛选后，所有图表都只算这个模型（`html-preview/layouts/main/v-analytics.jsx:56-58`）。

**现状**：OpsDashboardFilter 只有 StartTime、EndTime、Platform、GroupID、QueryMode（`service/ops_dashboard_models.go:5-15`）；各 handler 只解析 platform、group_id（`handler/admin/ops_dashboard_handler.go:33-46,74-87,116-129,157-170,199-212`），openai-token-stats 也是（:265-278）；where 构造只认这两项（`repository/ops_repo_dashboard.go:1020-1091`）。数据层够用：usage_logs 有 model / requested_model / upstream_model，ops_error_logs 有 model（`migrations/033_ops_monitoring_vnext.sql:85`）和 requested_model / upstream_model（`migrations/079_ops_error_logs_add_endpoint_fields.sql:15-18`）。预聚合表 ops_metrics_hourly 只有 platform / group_id 维度（`migrations/033_ops_monitoring_vnext.sql:342-372`）。

**建议改法**：上述 7 个接口都接受 `model`（精确匹配）与 `model_source` = `requested` | `upstream`（默认 requested；不支持 mapping）。例：`GET /api/v1/admin/ops/dashboard/throughput-trend?start_time=&end_time=&model=claude-opus-4`。带 model 时响应结构不变，只是数字变成该模型的。错误码：400 "Invalid model_source, use requested/upstream"。不带 model 时行为完全不变。

**实现提示**：
1. OpsDashboardFilter / OpsOpenAITokenStatsFilter 加 Model、ModelSource。
2. buildUsageWhere 里加 `resolveModelDimensionExpressionWithAlias(source, "ul") = $n`（`repository/usage_log_repo_trend.go:893-910`）；buildErrorWhere 里 requested 用 `COALESCE(NULLIF(TRIM(requested_model), ''), model)`，upstream 用 `COALESCE(NULLIF(TRIM(upstream_model), ''), NULLIF(TRIM(requested_model), ''), model)`（写错误日志时 Model 与 RequestedModel 同值：`handler/ops_error_logger.go:1198,1208`）。
3. 带 model 时强制 raw（ops_metrics_hourly 没有模型维度），在 service 层 resolveOpsQueryMode 之后判断。
4. 5 处复制粘贴的 filter 解析抽成一个 `parseOpsDashboardFilter(c)`。
5. ops/dashboard/snapshot-v2 的缓存 key 加 model（`handler/admin/ops_snapshot_v2_handler.go:26-33`）。
6. throughput-trend 的 by_platform / top_groups 在带 model 时也带上 model 过滤，或者跳过（`repository/ops_repo_trends.go:164-176`）。

**App 退路**：按模型筛选时，运行类图表仍显示全站，卡头写“后端不支持按模型，仍显示全站”。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/ops/dashboard/overview?time_range=1h&model=claude-opus-4" | jq '.data.success_count'` 等于 admin/usage/stats 同时段 model=claude-opus-4 的 total_requests；不带 model 时与改动前一致；model_source=bad 返回 400。

---

#### B07 · ops/dashboard/openai-token-stats 接受任意 start_time / end_time（成对，优先于 time_range） 〔P2 · 加参数〕

**页面**：统计分析 · Token 请求统计、模型对象页“速度”区。

**背景**：速度统计跟随页面选的范围（今天 / 近 7 天 / 近 30 天 / 自定义 / 上个月）（`html-preview/layouts/main/v-analytics.jsx:47`）。

**现状**：parseOpsOpenAITokenStatsFilter 只认 time_range = 30m | 1h | 1d | 15d | 30d，start = now − 窗口、end = now（`handler/admin/ops_dashboard_handler.go:249-264,315-330`），不读 start_time / end_time。service 校验（`service/ops_openai_token_stats.go:19-24`）和 repo 查询（`repository/ops_repo_openai_token_stats.go:27-34`）本来就按 StartTime / EndTime 工作，只是 handler 没开放参数。

**建议改法**：`GET /api/v1/admin/ops/dashboard/openai-token-stats?start_time=2026-09-01T00:00:00%2B08:00&end_time=2026-10-01T00:00:00%2B08:00[&timezone=][&group_id=][&top_n=|page=&page_size=]`。start_time / end_time 必须成对（复用 usagequery.ParseRange 的报错信息），优先于 time_range；跨度上限 31 天（覆盖“上个月”和“近 30 天 + 今天”），超出返回 400 `OPS_TIME_RANGE_TOO_LARGE`。响应 time_range = `"custom"`，start_time / end_time 回显实际值。不传时与现在一致（默认 30d）。

**实现提示**：在 parseOpsOpenAITokenStatsFilter 开头调 `usagequery.ParseRange(c.Request.URL.Query(), &start, &end)`（同 `handler/admin/ops_handler.go:720-737` 的 parseOpsTimeRange）：有 start_time 时 TimeRange="custom"，否则走原 time_range 分支。跨度上限放在 `service/ops_openai_token_stats.go`。repo 不用改；查询成本与现在允许的 30d 相同。

**App 退路**：取能盖住所选范围的最小窗口，卡底写明“统计窗口近 N 天，截至现在”；超过 30 天只显示最近 30 天（设计稿 `v-analytics.jsx` 已写好这套文案）。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/ops/dashboard/openai-token-stats?start_time=2026-10-11T00:00:00%2B08:00&end_time=2026-10-18T00:00:00%2B08:00&top_n=10" | jq '.data|{time_range,start_time,end_time,total}'`；某模型的 request_count 等于 admin/usage/stats 同时段、同模型的 total_requests；只传 start_time 返回 400；跨度 40 天返回 400。

---

#### B08 · dashboard/user-breakdown 参数校验收尾：去掉多余的二次解析，统一报错文案，补上 stream 与 limit 的校验 〔P2 · 改行为〕

**页面**：统计分析 · 用户排行（B04 的退路用它）、模型对象页 · 用户拆分。

**背景**：筛选参数写错时要明确报错，不能返回看起来像“筛选生效了”的全站数据。

**现状**：
- 主体已经满足：GetUserBreakdown 先调 parseDashboardSnapshotV2Filters（`handler/admin/dashboard_handler.go:505-509`），user_id、api_key_id、account_id、group_id、request_type、stream、billing_type、billing_mode 任一非法都直接返回 400，空串视同未传（`handler/admin/dashboard_snapshot_v2_handler.go:227-302`）。`group_id=abc` 现在就返回 400。
- 剩下四个小缺口：
  1. 报错文案是 strconv 原文，例如 `strconv.ParseInt: parsing "abc": invalid syntax`，不是 "Invalid group_id" 这种写法（ops 接口都这样写，dashboard 自己也有 "Invalid model_source, use requested/upstream/mapping"，`dashboard_handler.go:238`）。parseDashboardSnapshotV2Filters 是 dashboard 各接口共用的，trend、models、groups、users-trend 等返回的也是这种原文。
  2. 之后又按原始 query 再解析一遍（`dashboard_handler.go:511-515,528-569`），失败就静默跳过。第一遍做 TrimSpace，第二遍不做：带空格的合法值（如 `group_id=%2012`）能过第一遍校验，第二遍却解析失败，筛选被丢掉，返回全站数据。user_id、api_key_id、account_id、stream、billing_type 同理。
  3. 同时传 request_type 时，第一遍不看 stream（`dashboard_snapshot_v2_handler.go:266-276` 的 else if），非法的 stream 被静默忽略。
  4. limit 非数字、≤ 0 或 > 200 时静默回落到 50（`dashboard_handler.go:575-579`）。

**建议改法**：
1. GetUserBreakdown 直接用 filters 的解析结果填 dim（UserID、APIKeyID、AccountID、GroupID、RequestType、Stream、NativeCompactionV2、BillingType），删掉二次解析。同时传 request_type 和 stream 时以 request_type 为准，与 dashboard 其他接口一致（Web 只发 request_type，`frontend/src/components/admin/usage/UsageFilters.vue:127`）。
2. parseDashboardSnapshotV2Filters 的错误统一成 `Invalid <参数名>`，例如 "Invalid group_id"、"Invalid stream, use true or false"。只改 400 的 message，所有 dashboard 接口受益。
3. 同时传 request_type 时，stream 也要校验，非法返回 400。
4. limit 非法返回 400 "Invalid limit, use 1-200"；不传仍默认 50。
合法请求的响应不变。

**实现提示**：改动集中在 `dashboard_handler.go:497-579` 与 `dashboard_snapshot_v2_handler.go:227-302`。Web 的调用方只传数字和布尔值，limit 取 20 / 50 / 100 / 200（`frontend/src/components/admin/usage/UserTokenRanking.vue:92,105`；`frontend/src/api/admin/dashboard.ts:195-216`，axios 会省略 null / undefined），不受影响。sort_by 仍由 repo 白名单静默回退默认排序（:572 的注释说明是有意为之），本条不动。

**App 退路**：App 在本地校验参数后再发，数字参数不带空格。

**验收**：`group_id=abc` 返回 400 且 message 为 "Invalid group_id"；`group_id=%2012` 与 `group_id=12` 结果相同；`request_type=stream&stream=abc` 返回 400；`limit=0`、`limit=201`、`limit=abc` 返回 400，不传 limit 仍最多 50 条；合法参数的结果与改动前一致；Web 用户排行回归正常。

---

#### B09 · 日志类列表加 since_id 增量拉取；稳定数据的 GET 加 ETag / 304，ETag 排除易变字段 〔P2 · 新能力〕

**页面**：概览（统计、趋势、运行监控）、用户、分组、请求记录、错误日志。

**背景**：前台 30 / 60 秒轮询加下拉刷新，流量和耗电偏高；日志页只想拉新来的记录。

**现状**：
- 有 ETag 的只有：账号列表（`handler/admin/account_handler.go:880-909`）、今日统计批量（:2784-2807）、dashboard/snapshot-v2（`handler/admin/dashboard_snapshot_v2_handler.go:153-160`）、ops/dashboard/snapshot-v2（`handler/admin/ops_snapshot_v2_handler.go:79-91,138-142`）、上游计费倍率（`handler/admin/account_upstream_billing_rates.go:82-83`）。
- 滚动窗口下这些 ETag 基本命中不了：dashboard/snapshot-v2 的 payload 有 generated_at（:174）和 query.generated_at（`pkg/usagequery/range.go:26-28`），只在 30s 缓存期内不变；origin/main 每次请求覆写 RPM 后都会重算 ETag（`origin/main:handler/admin/dashboard_snapshot_v2_handler.go:153-168`）；ops/dashboard/snapshot-v2 的缓存 key 用到秒级 start / end（:69-77），payload 也带 start / end，几乎不会回 304。
- 游标：只有 alert-events 有往旧翻的 before_fired_at + before_id（`handler/admin/ops_alerts_handler.go:560-580`）。admin/usage 支持 start_time / end_time、sort_by = id | created_at、count_mode=deferred（`handler/admin/usage_handler.go:168-185`；`repository/usage_log_repo_query.go:230-247`），request-errors 支持 start_time / end_time（`handler/admin/ops_handler.go:227-252`），都没有“比某 id 更新”的参数。

**建议改法**：
- (a) 增量：`GET /api/v1/admin/usage?since_id=123456&page_size=100` 与 `GET /api/v1/admin/ops/request-errors?since_id=…`：返回 id > since_id 的行，按 id 降序，不做 COUNT；响应加 latest_id、has_more，例如 `{"items":[…],"latest_id":123590,"has_more":false}`。since_id 与 page > 1 同时传返回 400 "since_id cannot be combined with page"。其他筛选照常生效。
- (b) ETag：`GET /api/v1/admin/dashboard/stats`、`/admin/users`、`/admin/groups` 加 ETag + If-None-Match → 304；ETag 只对稳定内容计算，排除 uptime、generated_at、query.generated_at。
- (c) 滚动窗口接口（overview、throughput-trend、B01 rates）不做 ETag，改为服务端把 end 向下取整到 5–10 秒做缓存 key，用来节流。

**实现提示**：since_id：UsageLogFilters 加 SinceID，在 `repository/usage_log_repo_query.go` 拼 `id > $n` 并强制 `ORDER BY id DESC`；ops 侧 OpsErrorLogFilter 同理。用 id 而不用 created_at，是因为 usage_logs 走批量写入通道（`repository/usage_log_repo.go:151,153`），created_at 较早的行可能更晚入库，按 created_at 增量会漏，而 id 按入库单调递增。ETag：写一个通用 helper，复用 usagequery.CacheETag（`pkg/usagequery/cache.go:44-51`）与 ifNoneMatchMatched（`account_handler.go:942`），先把易变字段置零再算哈希。Web 不发 If-None-Match / since_id，不受影响。

**App 退路**：日志页 page=1、count_mode=deferred、start_time = 上次最新的 created_at − 120 秒，按 id 去重合并；概览各接口关掉 URLCache 全量拉（现状 `sub2-mobile-native/Sources/Sub2Core/HTTPTransport.swift:29-35`）。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/usage?since_id=123456&page_size=100" | jq '.data|{latest_id,has_more,n:(.items|length)}'`；连续两次 `curl -i -H "If-None-Match: <上次 ETag>" "$BASE/api/v1/admin/users?page=1"`，数据没变时第二次返回 304；stats 在 uptime 增长、数据不变时 ETag 不变。

---

#### B10 · 重统计查询提速：throughput-trend 可选读小时预聚合、可关闭附带汇总；usage/stats 可跳过端点分组集 〔P2 · 加参数〕

**页面**：概览的性能趋势、统计分析。

**背景**：手机端要求 10 秒内出结果；现有 App 为此给这些请求设了 45–90 秒超时（`sub2-mobile-native/Sources/Sub2Core/APIClient.swift:84-136`；`sub2-mobile-native/docs/API_COMPATIBILITY.md:42,54`）。

**现状**：
- throughput-trend 的 repo 完全不读 QueryMode（`repository/ops_repo_trends.go:13-185`）；service 虽然解析了 mode（`service/ops_trends.go:26`），mode=auto / preagg 实际不起作用，每次都扫 usage_logs + ops_error_logs，还要展开 upstream_errors jsonb 算 switch_count。不带 platform / group 时还会额外跑一次全窗口 by_platform 汇总（`ops_repo_trends.go:164-169`），App 用不到。error-trend、error-distribution、latency-histogram 同样不读 QueryMode；只有 overview 读（`repository/ops_repo_dashboard.go:31-48`）。现有 App 与设计稿都写了 `mode=auto`，以为能用上预聚合。
- ops_metrics_hourly 已有 success_count、error_count_total、token_consumed（`migrations/033_ops_monitoring_vnext.sql:342-372`），1 小时桶可以直接用。
- usage/stats 每次算 4 个 GROUPING SETS（`repository/usage_log_repo_stats.go:797-802`）；dashboard/models、groups 全查原始表（`repository/usage_log_repo_trend.go:493-578,588-679`）；dashboard/trend 只有无筛选、且时区等于服务器时区时才走预聚合（:387-420）；user-breakdown 不走查询缓存。服务器共享查询预算 30 秒（`pkg/usagequery/cache.go:137`）。
- 慢查询打点已经有：Server-Timing 中间件对 admin 请求输出 db、redis 耗时（`server/middleware/server_timing.go:30-50,123-127`；`repository/server_timing_sql.go`），默认关闭，配置 `server.enable_server_timing`（环境变量 `ENABLE_SERVER_TIMING`，`config/config.go:692,1854,2056`）。
- 在真实库实测之前，无法断定是否超过 10 秒（见附录 C Q17）。

**建议改法**：
1. throughput-trend 加 `include_breakdown=false`（默认 true，Web 不变）；为 false 时跳过 by_platform / top_groups。
2. throughput-trend 加可选参数 `hourly_preagg=true`（只有 App 传）：桶长为 3600 秒时整小时读 ops_metrics_hourly（request_count = success_count + error_count_total，token_consumed 直接取），首尾零头读原始表；预聚合里没有切换次数，switch_count 填 0 并加 `switch_count_available=false`，字段类型不变。不传时行为完全不变，mode=auto 也照旧走原始表。
   - 不能直接让 mode=auto 走预聚合：Web 运维页默认就发 mode=auto（`frontend/src/views/admin/ops/OpsDashboard.vue:199,552`），`ops.use_preaggregated_tables` 默认 true（`config/config.go:2317`），窗口超过 24h 时桶长正好是 3600（`handler/admin/ops_dashboard_handler.go:332-342`），会直接命中这条改动；SwitchCount 是 int64（`service/ops_trend_models.go:9`），改成 null 属于改类型，Web 切换率图按 `p.switch_count ?? 0` 读（`frontend/src/views/admin/ops/components/OpsSwitchRateTrendChart.vue:53`），切换率会静默显示成 0。
3. usage/stats 加 `include_endpoints=false`，只算总计那一个分组集。
4. 打开 `ENABLE_SERVER_TIMING=true` 做实测，不需要写代码；按实测结果再定 dashboard/models、groups 是否加“小时 × 模型 / 分组”预聚合表。

**实现提示**：(1)(2) 改 `repository/ops_repo_trends.go` 的 GetThroughputTrend：只在 hourly_preagg=true 且桶长 3600 时分支，参照 overview 的 getDashboardOverviewPreaggregated（`ops_repo_dashboard.go:226` 起）切分整小时和零头；preagg 没数据时返回 ErrOpsPreaggregatedNotPopulated，让 service 回落 raw（`service/ops_trends.go:29-31` 已有回落逻辑）。ops_metrics_hourly 有 overall / platform / group 三种维度行，按 filter 选对应行（唯一索引 `migrations/033_ops_monitoring_vnext.sql:377-382`）。ops/dashboard/snapshot-v2 里的 throughput 不加这个参数，保持现状。(3) 在 GetStatsWithFilters 用参数决定 GROUPING SETS 的内容，usageStatsCacheKey 要包含该参数。

**App 退路**：各区块独立加载，超时 45–90 秒；性能趋势默认近 1 小时（1 分钟桶、数据量小）；长范围只在用户主动切换时才请求。

**验收**：在生产量级数据库上对比改动前后的 `EXPLAIN (ANALYZE, BUFFERS)` 与 `curl -s -o /dev/null -w '%{time_total}\n' -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/ops/dashboard/throughput-trend?time_range=24h&include_breakdown=false"`；目标 p95：throughput-trend 24h < 2s、30d < 5s（hourly_preagg=true），usage/stats 30d（include_endpoints=false）< 5s；预聚合路径与 raw 路径的 request_count / token_consumed 一致（零头边界除外）；不带 hourly_preagg 时 `mode=auto&time_range=30d` 的响应与改动前一致，Web 切换率图不变。

---

#### B11 · 可选：可部分成功的移动端首页聚合接口 `GET /api/v1/admin/dashboard/home` 〔P2 · 新接口〕

**页面**：概览首页（前台约 60 秒自动刷新 + 下拉刷新）。

**背景**：首屏要快：6 格、待处理（告警、错误 / 过载 / 受限账号、分组可用数）、今日小时图、运行区、渠道一行（`DECISIONS.md:44,47`；`html-preview/layouts/main/v-today.jsx:8-35`）。

**现状**：现有组合接口能省一部分请求，但都不能部分成功：`GET /api/v1/admin/dashboard/snapshot-v2` 一次可拿 stats 加今天、昨天逐时趋势（`start_date=昨天&end_date=今天&granularity=hour&include_model_stats=false`），30s 缓存 + ETag（`handler/admin/dashboard_snapshot_v2_handler.go:80-163`）；`GET /api/v1/admin/ops/dashboard/snapshot-v2` 返回 overview + throughput + error trend，但 errgroup 任一段失败就整包 500（`handler/admin/ops_snapshot_v2_handler.go:98-129`），并且受开关控制。告警、可用性、并发接口也都受 RequireMonitoringEnabled 控制（`handler/admin/ops_alerts_handler.go:522`；`handler/admin/ops_realtime_handler.go:122`）。账号分组归属要拉全量 admin/accounts。

**建议改法**：`GET /api/v1/admin/dashboard/home?timezone=<IANA，可选，默认服务器时区>[&include=stats,rates,hourly,ops,alerts,availability,channels]`。每段都有 `status` = `ok` | `disabled` | `error` | `timeout`；只要鉴权通过，HTTP 就返回 200。

```json
{"code":0,"message":"success","data":{
  "generated_at":"2026-10-18T01:41:00Z",
  "stats":{"status":"ok","data":{"today_actual_cost":1284.5,"today_account_cost":512.08,"today_requests":18204,"yesterday_same_time_actual_cost":1190.27,"stats_stale":false}},
  "rates":{"status":"ok","data":{"rpm":46.4,"tpm":240000,"error_rate":0.0086}},
  "hourly":{"status":"ok","data":{"today":[],"yesterday":[]}},
  "ops":{"status":"ok","data":{"health_score":94,"error_rate":0.008,"upstream_429_count":12,"upstream_529_count":3}},
  "alerts":{"status":"ok","data":{"firing_count":1,"top":[]}},
  "availability":{"status":"disabled","error":"OPS_DISABLED"},
  "channels":{"status":"ok","data":{"total":8,"failing":1}}}}
```

错误码：400 "invalid timezone"；401 / 403 沿用 admin 鉴权。

**实现提示**：新 handler 用 errgroup 并发，但每个 goroutine 都不 return err，把错误写进本段的 status / error（与 `ops_snapshot_v2_handler.go:126-129` 的整包失败相反）。整体预算 8s，每段独立 `context.WithTimeout`，超时的段标 timeout。复用 DashboardService.GetDashboardStats、GetUsageTrendWithUsageFilters（hour）、B01 的 GetLiveRates、OpsService.GetDashboardOverview（5m）、告警列表（status=firing、limit 5）、D02 的状态汇总（只回分组 available / total 与异常账号 id / 状态）、渠道监控摘要；监控关闭时相关段标 disabled。15s 缓存用 scopedUsageCacheKey，ETag 计算时排除 generated_at。`yesterday_same_time_*` 的口径见附录 A S10。

**App 退路**：并发 5 路，各区块独立加载、独立失败：dashboard/snapshot-v2（stats + 今天和昨天逐时，1 次）+ ops/dashboard/overview?time_range=5m（错误率、RPM、TPM 与运行区，见 B01）+ ops/alert-events?status=firing + ops/account-availability + 渠道监控。运维监控关闭时后三类只显示“未开启”。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/dashboard/home" | jq '.data | map_values(.status?)'`；关掉运维监控后仍返回 200，ops / alerts / availability 为 disabled、stats / hourly 为 ok；用 mock 让 overview 超时，只有 ops 段为 timeout；冷缓存 p95 < 3s。

---

#### B12 · dashboard/users-trend 带筛选时按 metric 取前 N 位（现在带筛选一律按 Tokens 排） 〔P2 · 改行为〕

**页面**：统计分析 · 更多图表「用户用量趋势」（按分组、模型等筛选后切到「实际扣费」）。

**背景**：设计稿在当前筛选范围内按所选指标取前 12 位用户，底部写“按实际扣费取前 12 位”（`html-preview/layouts/main/v-analytics.jsx:1862-1878`，AxUserTrendBody 用 `axRankItems('user', r, metric)` 在筛选结果里排名），并写明 users-trend 接受 group_id、model 与 metric（:48、:57）。

**现状**：
- handler 解析了 metric（tokens | actual_cost，非法回落 tokens，`handler/admin/dashboard_handler.go:336-339`），但只要带了任一筛选（group_id、model、user_id、account_id、request_type 等），就走 getUserUsageTrendCachedWithFilters（:343-344），这条路径不传 metric；它的缓存 dimension 只有 `granularity:limit`（`handler/admin/dashboard_query_cache.go:122-129`）。
- 仓储 GetUserUsageTrendWithFilters 把 metric 写死成 "tokens"（`repository/usage_log_repo_trend.go:97-98`），只有 metric=actual_cost 时才按 SUM(actual_cost) 排名（:103-106）；origin/main 相同（`origin/main:repository/usage_log_repo_trend.go:123-132`）。
- 结果：带筛选切到「实际扣费」时，后端仍按 Tokens 取前 12 位，选出来的人是错的（每人的 actual_cost 数值本身没错）。
- dashboard/snapshot-v2 的 users_trend 总是调 GetUserUsageTrendWithFilters（`handler/admin/dashboard_snapshot_v2_handler.go:217`），完全不看 metric。
- Web 首页的用户趋势不带任何筛选（`frontend/src/views/admin/DashboardView.vue:704-710`），走的是有 metric 的那条路径，不受影响。

**建议改法**：`GET /api/v1/admin/dashboard/users-trend?start_date=&end_date=&group_id=1&metric=actual_cost` 在筛选范围内按 metric 取前 limit 位，参数与响应结构不变。不带筛选时行为不变；带筛选但 metric=tokens 或不传时也与现在一致。可选：snapshot-v2 增加 `users_trend_metric`（默认 tokens）。

**实现提示**：GetUserUsageTrendWithFilters（仓储与 DashboardService 两层）加 metric 参数，透传给 getUserUsageTrendWithFilters；handler 带筛选的分支（:343-344）传入 metric；getUserUsageTrendCachedWithFilters 的 dimension 改成 `granularity:limit:metric`，避免两种指标共用一份缓存。snapshot-v2 的调用处传 "tokens"（或做了可选参数后传它）。在 A01 基线上改。

**App 退路**：带筛选时先用 `GET /admin/dashboard/user-breakdown?…&group_id=&model=&sort_by=actual_cost&limit=12` 取人（已支持这些筛选与按 actual_cost 排序），再对每个 user_id 调 `GET /admin/dashboard/trend?…&user_id=<id>`（同一组筛选，最多 12 次，并发 4）画线；或者带筛选时隐藏「实际扣费」切换，只给 Tokens。

**验收**：`users-trend?start_date=2026-10-11&end_date=2026-10-17&group_id=1&metric=actual_cost&limit=12` 返回的用户集合，等于同范围 `user-breakdown?group_id=1&sort_by=actual_cost&limit=12` 的前 12 位；同参数 metric=tokens 的结果与改动前一致；不带筛选的请求与改动前一致；两种 metric 交替请求时第二次不会命中对方的缓存（看 `X-Snapshot-Cache`）。

---

### C 账号

#### C01 · `POST /api/v1/admin/accounts` 新增可选 schedulable（新建时就停止调度）与 skip_default_group_bind 〔P1 · 加参数〕

**页面**：新建账号（单页长表单 →“创建并测试” sheet）。

**背景**：第 3 轮 Q3（`DECISIONS.md:83`）：新建后先停止调度，测试通过再启用，避免未验证的凭据接到线上流量。设计稿现在按“创建 → 停止调度 → 测试 → 启用调度”四步进度画（`html-preview/layouts/main/v-account-new.jsx:20-22`）。

**现状**：
- CreateAccountRequest 没有 schedulable、status、skip_default_group_bind（`handler/admin/account_handler.go:136-153`）；Create 构造 CreateAccountInput 时也没有（:1059-1076），BatchCreate 同样（:2171-2186）。
- buildAccountForCreate 写死 `Status: StatusActive`、`Schedulable: true`（`service/admin_account.go:507-508`），repo Create 按此落库；可调度 SQL 只选 schedulable=true 的账号（`repository/account_repo.go:2077-2087`），所以账号一入库就会被调度。
- group_ids 为空且 !SkipDefaultGroupBind 时，自动绑定名为 `<platform>-default` 的分组（`service/admin_account.go:600-613`）。service 层已有 SkipDefaultGroupBind（`service/admin_service.go:430-431`），codex 导入、数据导入、openai/create-from-codex-pat 都已对外暴露（`handler/admin/account_codex_import.go:40`、`handler/admin/account_data.go:77`、`handler/admin/openai_oauth_handler.go:190`），只有 `POST /admin/accounts` 和 `/admin/accounts/batch` 没有。

**建议改法**：`POST /api/v1/admin/accounts`（以及 `/api/v1/admin/accounts/batch` 的每一项）请求体只增两个可选字段：`"schedulable": false`（缺省 true，与现在一致）；`"skip_default_group_bind": true`（缺省 false，与现在一致）。

```json
{"name":"Claude-新","platform":"anthropic","type":"apikey","credentials":{"api_key":"sk-ant-..."},"group_ids":[],"schedulable":false,"skip_default_group_bind":true}
```

响应不变，仍是账号对象，其中 `data.schedulable=false`、`data.group_ids=[]`。不新增错误码；类型错误沿用 400 "Invalid request: ..."。

**实现提示**：
1. CreateAccountRequest 加 `Schedulable *bool json:"schedulable"`、`SkipDefaultGroupBind *bool json:"skip_default_group_bind"`，Create（:1059-1076）与 BatchCreate（:2171-2186）透传。
2. CreateAccountInput（`service/admin_service.go`）加 `Schedulable *bool`。
3. buildAccountForCreate（`service/admin_account.go:497-509`）在 `input.Schedulable != nil` 时用该值；DuplicateAccount 也走这个函数，传 nil 保持 true。
- 状态在同一条 INSERT 里写入，没有空窗；调度 outbox 照常入队，快照不会包含 schedulable=false 的账号。幂等：executeAdminIdempotent 以请求体做指纹，新字段自然进入指纹。补测试：schedulable=false 时 ListSchedulable 里没有该账号；不传时行为不变。

**App 退路**：现行多请求做法：POST accounts → 立即 `POST /admin/accounts/:id/schedulable {"schedulable":false}` → 测试 → 再 `{"schedulable":true}`。中间有空窗；停止调度失败时提示“结果待核对 / 账号可能还在参与调度”，给重试和删除。另一个“失败也安全”的临时办法有副作用，见附录 C Q3。分组：App 总是显式传 group_ids，表单提示“不选分组时，若存在 `<platform>-default` 分组会自动加入”。

**验收**：
1. `curl -X POST "$BASE/api/v1/admin/accounts" -H "Authorization: Bearer $T" -d '{"name":"t","platform":"anthropic","type":"apikey","credentials":{"api_key":"sk-x"},"schedulable":false,"skip_default_group_bind":true}'`：返回 `data.schedulable=false`、`data.group_ids` 为空；网关请求不会选到这个账号。
2. 不带新字段：schedulable=true，并自动绑定 -default 分组，与现在一致。
3. Web 新建、批量新建回归通过。

---

#### C02 · 账号 DTO 新增结构化错误字段：error_at、error_status_code、error_kind、error_summary 〔P1 · 加字段〕

**页面**：账号详情状态卡（错误态，“最近上游错误 09:40 · 1 分钟前 · 401”）；账号行 / 首页待处理错误行的“N 分钟前”；凭据区错误条；账号列表的异常标记。

**背景**：管理员要知道账号什么时候、因为哪个状态码、属于哪类原因（认证失败、额度不足、被封等）进入错误状态，并在列表里直接看到安全的原因摘要。设计稿目前用“最近一条上游错误日志”代替（`html-preview/layouts/main/v-account-edit.jsx:26-30`、`html-preview/layouts/main/00-core.jsx:338-345`）。

**现状**：
- accounts 表没有出错时间列（`ent/schema/account.go:124-160`）。SetError 只写 status、error_message、schedulable（`repository/account_repo.go:1514-1520`）；Grok 的三个条件写错误函数同样没有时间（:1531-1545、1584-1600、1704-1721）。
- DTO 有 rate_limited_at、overload_until、temp_unschedulable_until（`handler/dto/types.go:237-242`；lite 列表 :355-368），没有出错时间。updated_at 由 TimeMixin 在每次更新时刷新（`ent/schema/mixins/time.go:27`），不能拿来用。
- error_message 是直接拼接的原文，例如 `"Authentication failed (401): <上游 body>"`（`service/account_test_service.go:991`）、`"Custom error code N: ..."`（`service/ratelimit_service.go:1175`）、`"Privacy not set, required by group [...]"`（`service/gateway_scheduling.go:1979`），没有分类也没有脱敏。
- 现成的脱敏工具：SanitizeUpstreamErrorMessage（`service/gateway_upstream_response.go:373`）、logredact.RedactText（`util/logredact/redact.go:86`）。调度阻断通知有原因码（auth_error、custom_error_code、stream_timeout_error、token_refresh_non_retryable 等，`service/ratelimit_service.go:972,1176,2887`），但没有落库。

**建议改法**：`GET /api/v1/admin/accounts`（full 与 lite）和 `GET /api/v1/admin/accounts/:id` 的账号对象只增以下字段，error_message 保持原样：

```json
{"error_at":"2026-10-17T09:40:12Z","error_status_code":401,"error_kind":"auth","error_summary":"上游返回 401：invalid x-api-key"}
```

- `error_at`：进入 error 的时间，非 error 时为 null。
- `error_status_code`：能解析出的上游 HTTP 状态码，否则 null。
- `error_kind`：`auth` | `forbidden` | `quota` | `rate_limit` | `custom_code` | `stream_timeout` | `token_refresh` | `privacy` | `config` | `other`。这是全文唯一的一套分类，C08、C09 的测试结果也用它。`rate_limit`（上游 429）一般不会让账号进入 error 状态，主要给测试结果用。
- `error_summary`：已脱敏、去掉 HTML、不超过 160 字。

**实现提示**：
1. 新增迁移（编号按 1.3 的约定从 247 起，例如 `migrations/247_add_account_error_at.sql`）：`ALTER TABLE accounts ADD COLUMN IF NOT EXISTS error_at TIMESTAMPTZ NULL;`；ent schema 加 `field.Time("error_at").Optional().Nillable()` 并重新生成。
2. SetError 加 `SetErrorAt(time.Now())`；三处 Grok 原生 SQL 加 `error_at = NOW()`；ClearError（`repository/account_repo.go:1900-1905`）加 ClearErrorAt()；UpdateAccount / BulkUpdate 手工把 status 改成 error 时也写入（可选）。
3. error_kind、error_status_code、error_summary 不落库，在 dto 映射里（`handler/dto/mappers.go:234` AccountFromServiceShallow 与 AccountListItemFromAccount）由 error_message 用纯函数派生：状态码用正则 `\((\d{3})\)|returned (\d{3})|error code (\d{3})`，分类按前缀映射，摘要依次经过 logredact.RedactText → SanitizeUpstreamErrorMessage → 去 HTML → 截断。
4. 存量 error 账号的 error_at 保持 null，不回填（用 updated_at 回填不准）。为分类函数补表驱动单测。

**App 退路**：沿用设计稿做法：`GET /api/v1/admin/ops/upstream-errors?account_id=:id&time_range=24h&page=1&page_size=1` 取最近一条上游错误的时间与状态码（`handler/admin/ops_handler.go:513` 支持 account_id）。这依赖运维监控开启，超过 24 小时拿不到，也不一定是进入错误的那一刻。App 不显示 error_message 原文，只写“上游返回异常，点入查看错误日志”；本地可用同样的正则粗分类（401 / 403 归为凭据类）。

**验收**：让一个 API Key 账号触发 401 后，`GET /api/v1/admin/accounts/:id` 返回 error_at ≈ 触发时间、error_status_code=401、error_kind=auth，error_summary 不含 key 或 URL 里的密钥参数；执行 recover-state 后 error_at=null；Web 账号页显示不变。

---

#### C03 · 新增 `PATCH /api/v1/admin/accounts/:id`：credentials / extra 按顶层键合并（null 表示删除），支持 If-Match 乐观并发 〔P1 · 新接口〕

**页面**：账号详情内联编辑：基础 / 调度 / 凭据（更换 API Key、Base URL）/ 代理 / 模型（model_mapping）/ 高级（extra 开关）各自的小 sheet 保存；回执里的“撤销”。

**背景**：手机端每个分区只改几个键，撤销就是把旧值再提交一次。不能清掉只能在 Web 改的设置，也不能覆盖别人同时做的修改或网关在运行中写入的状态。

**现状**：
- `PUT /api/v1/admin/accounts/:id` → Update（`handler/admin/account_handler.go:1172-1240`）→ UpdateAccount（`service/admin_account.go:687-1040`）。
- credentials 走 MergePreservingSensitiveCreds（`service/admin_account.go:766-769`；`service/account_credentials_redact.go:31-52`）：非敏感键完全以请求为准，请求里没带就会被删掉。
- extra 整块替换（`service/admin_account.go:784-846`），只保留 quota_used 等少数受管键（803-821）。model_rate_limits、antigravity_quota_scopes 等运行态键不在保留名单里，用几秒前 GET 到的快照整块 PUT，会把网关在这期间写入的模型限流等状态回滚。Web 编辑也有同样问题。
- 没有版本号或 If-Match，也不校验 updated_at。
- 已有按键合并的能力：service.UpdateAccountExtra（`service/admin_account.go:1042-1068`）→ repo UpdateExtra 用 `extra || $1::jsonb`（`repository/account_repo.go:2819-2849`），但只在 apply-oauth-credentials 内部使用；bulk-update 对 credentials 和 extra 也是 JSONB 顶层合并（`repository/account_repo.go:3162-3172,3221-3229`）。repo 里有按 UpdatedAt 做 CAS 的先例 SetRateLimitedIfUnchanged（`repository/account_repo.go:2444-2465`）。

**建议改法**：新增 `PATCH /api/v1/admin/accounts/:id`，PUT 保持不变。可选请求头 `If-Match: "2026-10-17T09:40:12.123456Z"`（账号的 updated_at，RFC3339Nano），也可在请求体里传 `expected_updated_at`。

```json
{"name":"Claude-主力","priority":10,
 "credentials_patch":{"base_url":"https://api.example.com","api_key":"sk-new","model_mapping":{"claude-*":"claude-sonnet-4-5"},"custom_error_codes":null},
 "extra_patch":{"pool_mode":true,"temp_unschedulable_rules":null},
 "confirm_mixed_channel_risk":false}
```

- 顶层字段与 PUT 相同，只提交改过的。
- `*_patch` 按顶层键合并；值为 null 表示删除该键；嵌套对象整体替换。
- 敏感键不能用 null 删除，否则 400 `CREDENTIAL_KEY_NOT_DELETABLE`。
- 响应是账号对象，并带响应头 `ETag: "<新的 updated_at>"`；`GET /admin/accounts/:id` 也同步只增 ETag 头。
- 错误码：412 `ACCOUNT_VERSION_CONFLICT`（If-Match 不符，metadata.current_updated_at 给当前值）；400 `INVALID_PATCH`；409 mixed_channel_warning（信封同 C06）。

**实现提示**：
1. 新 handler Patch → service PatchAccount：GetByIDScoped 取当前账号 → 校验期望的 updated_at → 以 DB 当前值为底，用 maps.Clone 合并 credentials 和 extra（null 即 delete）→ 组装成 `UpdateAccountInput{Credentials: 合并后整份, Extra: 合并后整份}`，复用 UpdateAccount 的全部校验与规范化（配额重置、OpenAI 长上下文、Grok media、探针身份、影子账号守卫）。
2. 写库做 CAS：给 repo 的 Update / UpdateWithAccountBillingSettings 增加可选 expectedUpdatedAt（`WHERE id=$ AND updated_at=$`），影响行数为 0 返回 412，参照 SetRateLimitedIfUnchanged。没带 If-Match 时也要在同一事务里 `SELECT ... FOR UPDATE` 后再合并，避免回滚网关写入的运行态键。
3. credentials 有变更时，与 Update 一样调 scheduleOpenAIResponsesProbe（`account_handler.go:1234-1237`）。
4. Postgres 的 updated_at 精度是微秒，统一按 RFC3339Nano 序列化和比较。
5. 路由加在 `server/routes/admin.go:427` 旁边。

**App 退路**：先 GET :id 拿整份（已脱敏的）credentials 和 extra 作底，合并改动后整份 PUT；敏感键不带就保留原值。这样无法防并发，网关在此期间写入的 model_rate_limits 会被回滚。只改 extra 或 credentials 里的开关类键时，可临时用 `POST /api/v1/admin/accounts/bulk-update {"account_ids":[id],"extra":{…}}` 走 JSONB 合并；它不做配额重置的校验和计算、不重新探测 Responses 能力、也不能删键，所以不要用它改 quota_*、base_url、api_key。撤销就是把旧值再提交一次。

**验收**：
1. 账号 extra 里有 pool_mode、custom_error_codes、model_rate_limits，PATCH `extra_patch {"pool_mode":false}` 后其余键不变。
2. `credentials_patch {"custom_error_codes":null}` 能删掉这个键；对 api_key 传 null 返回 400。
3. 用旧的 updated_at 作 If-Match 返回 412；不带 If-Match 正常成功。
4. PUT 行为不变，Web 编辑回归通过。

---

#### C04 · 新增 `GET /api/v1/admin/dashboard/accounts-ranking`：按账号的实际扣费排行（今日前 N） 〔P1 · 新接口〕

**页面**：平静布局“按账号 · 今日实际扣费 · 前 4”；账号列表按“今日金额”排序。

**背景**：没有异常时首页的主角是营收，要列出今天贡献最多的几个账号。首页刷新频繁，现有绕法的成本随账号数线性增长。

**现状**：dashboard 有 users-ranking、groups、models（`server/routes/admin.go:298-315`），没有按账号的排行或聚合。accounts/today-stats/batch 必须传账号 ID 列表（`handler/admin/account_handler.go:2745-2810`）。仓储已有按 account_id 分组的统计 SQL（`repository/usage_log_repo_stats.go:340-357` GetAccountWindowStatsBatch）和索引 idx_usage_logs_account_created_at（`migrations/010_add_usage_logs_aggregated_indexes.sql:2`）。origin/main 上也没有这个能力。

**建议改法**：`GET /api/v1/admin/dashboard/accounts-ranking?start_date=2026-10-17&end_date=2026-10-17&limit=4[&platform=][&group_id=]`

```json
{"ranking":[{"account_id":12,"account_name":"Claude-主力","platform":"anthropic","status":"active","requests":1530,"tokens":8200000,"actual_cost":312.45,"account_cost":201.30,"standard_cost":180.20}],
 "total_actual_cost":980.10,"start_date":"2026-10-17","end_date":"2026-10-17"}
```

口径与 today-stats 一致：actual_cost = SUM(actual_cost)；account_cost、standard_cost 只算 provider_cost_recorded 的行。limit 取 1–50，默认 10。

**实现提示**：仿 GetUserSpendingRanking（`handler/admin/dashboard_handler.go:383-404`）新增 handler、dashboardService 方法与 repo SQL：`SELECT account_id, COUNT(*), SUM(actual_cost) … FROM usage_logs WHERE created_at >= $1 AND created_at < $2 [AND group_id=$3] GROUP BY account_id ORDER BY SUM(actual_cost) DESC LIMIT $n`，再 JOIN accounts 取名称和平台，排除软删账号。按工作区作用域收窄（参照 FilterAccountIDsByScope）；复用 loadDashboardQuery 30 秒缓存；“今天”的起点用 timezone.Today()，与 today-stats 一致。vendor：看板路由逐条精确登记，这条不在白名单里，默认 403。要开放就两处都加：vendorAllowedRoutes 加 `{prefix:"/api/v1/admin/dashboard/accounts-ranking",methods:["GET"],exact:true,permit:permitMonitorView}`，vendorUsageScopedRoutes 加同一路径（`server/middleware/vendor_routes.go:150-153,168-178`）。只加前者，这条会在没有账号白名单的情况下查全站用量（代码注释称“静默越权”）；`server/middleware/vendor_routes_usage_scope_test.go` 的 TestVendorUsageRoutesRequireScope 会拦住这种漏登记。

**App 退路**：拉全量 lite 账号列表，把全部 ID 交给 `POST /api/v1/admin/accounts/today-stats/batch`（服务端缓存 30 秒），本地按 user_cost 排序取前 4。首页每次刷新两次请求，成本随账号数增长。

**验收**：在今天有流量的站点调 limit=4：返回 4 条，按 actual_cost 降序，每条 actual_cost 等于 today-stats/batch 里对应账号的 user_cost；vendor 身份：不开放时返回 403，开放后只看到本工作区的账号，`go test ./internal/server/middleware/...` 通过。

---

#### C05 · `POST /api/v1/admin/accounts/:id/recover-state` 新增可选请求体 `{"schedulable": true}` 〔P2 · 加参数〕

**页面**：账号详情状态卡“恢复状态”确认框（选项“恢复并启用调度”）；概览待处理里的恢复按钮。

**背景**：出错的账号已被 SetError 停止调度，管理员通常想一步恢复并重新启用。设计稿的 confirmRecover 给出“恢复并启用调度 / 只恢复状态（保持暂停）”两个选项（`html-preview/shared/core.jsx:493-528`）。

**现状**：RecoverState handler 不读请求体（`handler/admin/account_handler.go:1350-1385`），只调 `RecoverAccountState(InvalidateToken:true)`（`service/ratelimit_service.go:2163-2196`）：status==error 时调 ClearError（只改 status 和 error_message，`repository/account_repo.go:1900-1905`）；有限流、过载、临时不可调度或模型限流时调 ClearRateLimit（`service/ratelimit_service.go:2129-2151`）。全程不改 schedulable，而 SetError 会写 schedulable=false（`repository/account_repo.go:1514-1520`），所以出错的账号恢复后仍是暂停。Web 调用时不带请求体（`frontend/src/api/admin/accounts.ts:434-436`）。

**建议改法**：可选 JSON 请求体 `{"schedulable": true|false}`：不带请求体或不带该字段，行为与现在完全一致；带 true 时恢复后在同一请求里把调度开关设为 true；带 false 显式保持暂停。响应仍是账号对象（含 status、schedulable、error_message）。恢复成功但设置开关失败时返回 500，reason=`ACCOUNT_RECOVERED_SCHEDULABLE_FAILED`，metadata `{"recovered":"true"}`，App 据此显示“已恢复 · 仍暂停”。

**实现提示**：RecoverState 里加 `var req struct{ Schedulable *bool json:"schedulable" }; _ = c.ShouldBindJSON(&req)`，允许空请求体（写法同 Test handler 的 1328 行）。RecoverAccountState 成功后，如果 `req.Schedulable != nil`，调 `h.adminService.SetAccountSchedulable`（`service/admin_account.go:1507-1520`，已带归属校验和调度快照同步，`repository/account_repo.go:2761-2775`），再 GetAccount 返回。设开关放在最后，部分失败时停在“暂停”一侧，是安全的。路由不变（`server/routes/admin.go:442`）。

**App 退路**：两次请求：recover-state → `POST /admin/accounts/:id/schedulable {"schedulable":true}`；第二次失败时停在“已恢复 · 仍暂停调度”，回执给“启用调度”按钮（设计稿 `shared/core.jsx:493-515` 已这样画）。失败方向是暂停，安全。

**验收**：对 status=error、schedulable=false 的账号 `curl -X POST "$BASE/api/v1/admin/accounts/12/recover-state" -d '{"schedulable":true}'`：返回 status=active、error_message=""、schedulable=true；不带请求体时 schedulable 仍为 false；Web“恢复状态”回归通过。

---

#### C06 · 创建 / 更新账号的混合渠道 409 只增字段：补 code、reason、metadata 和 details 〔P2 · 改行为〕

**页面**：新建账号提交；编辑账号 · 调度分区修改分组。

**背景**：要弹出与 Web 同款的混合渠道确认框，写明哪个分组里同时有哪两个平台；确认后带 `confirm_mixed_channel_risk=true` 重发。

**现状**：Create 遇到 MixedChannelError 时直接 `c.JSON(409, {error:"mixed_channel_warning", message})`（`handler/admin/account_handler.go:1094-1106`），注释写着“详细信息由专门检查接口提供”；Update 同样（:1217-1227）。这两处没有 code、reason，也没有 details。BulkUpdate 的 409 已带 details（:2405-2417）。check-mixed-channel 返回 200 `{has_risk, error, message, details{…}}`（:993-1033）。message 是一句很长的英文（`service/admin_account.go:1868-1871`）。Web 编辑弹窗只读 error.status、error.error、error.message（`frontend/src/components/account/EditAccountModal.vue:5278-5286`），只增字段不影响 Web。顺带：Web 新建弹窗的 409 兜底读的是 `error.response?.status`（`frontend/src/components/account/CreateAccountModal.vue:5406`），而 axios 拦截器 reject 出来的对象没有 response 字段（`frontend/src/api/client.ts:258-265`），这条兜底永远走不到，Web 实际靠提交前的预检（`CreateAccountModal.vue:5339-5347`）。

**建议改法**：Create、Update、BulkUpdate 的 409 保留 error 和 message，只增字段：

```json
{"code":409,"reason":"MIXED_CHANNEL_WARNING","error":"mixed_channel_warning",
 "message":"mixed_channel_warning: Group '高级组' contains both antigravity and anthropic accounts. ...",
 "metadata":{"group_id":"7","group_name":"高级组","current_platform":"antigravity","other_platform":"anthropic"},
 "details":{"group_id":7,"group_name":"高级组","current_platform":"antigravity","other_platform":"anthropic"}}
```

**实现提示**：在 `account_handler.go` 抽一个 `writeMixedChannelConflict(c, mixedErr)` helper，1099、1222、2408 三处共用；metadata 是 map[string]string，details 保留数字类型。Create 外层的 executeAdminIdempotent 在错误路径不缓存。补 handler 测试，断言新字段存在、旧字段不变。Web 新建弹窗的 `error.response?.status` 可顺手改成 `error.status`。

**App 退路**：提交前先 `POST /api/v1/admin/accounts/check-mixed-channel` 预检（Web 也这样做）；收到 409 兜底时再调一次 check-mixed-channel 拿 details，弹框后重发。

**验收**：新建一个 antigravity 账号，group_ids 选一个含 anthropic 账号的分组、不带确认：409，带 reason=MIXED_CHANNEL_WARNING 与 details.group_name；带 confirm_mixed_channel_risk=true 返回 200；Web 新建和编辑回归通过。

---

#### C07 · 账号测试 SSE 末尾追加 test_result 事件：服务端计时、上游状态码、Token 用量、测试后的账号状态与自动恢复结果 〔P2 · 加字段〕

**页面**：新建账号“创建并测试”结果 sheet；账号详情“测试连接” sheet；首页待处理行里的“测试”。

**背景**：结果要写“首字 1.21s · 总耗时 3.42s”，并说明“已自动清除错误或限流，仍暂停调度 / 已恢复调度”或“后端已把账号标为错误”（`html-preview/layouts/main/v-account-new.jsx:27`、`html-preview/shared/core.jsx:222-230`）。

**现状**：
- TestEvent 只有 type、text、model、status、code、image_url、audio_url、video_url、mime_type、data、success、error（`service/account_test_service.go:51-65`），没有耗时和 Token。test_complete 在各平台路径内部发出（如 :391、803、3273）。handler 要等 TestAccountConnection 返回 nil 后才调 RecoverAccountAfterSuccessfulTest（`handler/admin/account_handler.go:1336-1345`），恢复结果不发给客户端。
- 测试失败时会改账号状态的路径：SetError（Claude 403 `account_test_service.go:623-627`、Vertex 403 :696、OpenAI 401 :989-993、Chat Completions / Compact 401 :2183、2344）；OpenAI 429 写限流（:987、2358-2380）；Grok 402、免费额度、计费错误写临时不可调度（:1201、1214、1247）。
- Gin handler 要等恢复完成才返回，所以 SSE 流的 EOF 发生在恢复之后；问题只在于收到 test_complete 就立刻 GET 会读到旧状态。Web 测试弹窗的 switch 对未知事件类型直接忽略（`frontend/src/components/account/AccountTestModal.vue:494-557`）。

**建议改法**：现有事件全部不变，在流的最后（恢复执行之后、handler 返回之前）追加一条：

```json
{"type":"test_result","success":true,"data":{
  "success":true,"started_at":"2026-10-17T09:40:00Z","first_token_ms":1210,"total_ms":3420,"upstream_status":200,
  "usage":{"input_tokens":12,"output_tokens":38},
  "account":{"status":"active","schedulable":false,"rate_limit_reset_at":null,"temp_unschedulable_until":null,"error_summary":""},
  "recovery":{"cleared_error":true,"cleared_rate_limit":false},
  "marked":{"error":false,"rate_limited":false,"temp_unschedulable":false}}}
```

拿不到 usage 时省略。失败时也发这一条（success 为 false，recovery 为空，marked 反映这次测试写入的错误、限流或临时不可调度）。注意 TestEvent.Success 带 `omitempty`（`service/account_test_service.go:64`），success:false 序列化时顶层字段会被省略：data 用单独定义的结构体，里面的 `success` 不带 omitempty，App 以 `data.success` 为准，顶层 success 缺失按 false 处理。

**实现提示**：
1. TestAccountConnection（`account_test_service.go:361`）开头把开始时间存进 gin.Context；sendEvent（:3277-3291）在第一次发出 content 或 image 事件时记首字时间。上游状态码可给 sendErrorAndEnd 加一个可选参数，过渡期从 `"API returned %d"` 文本解析。
2. handler Test（`account_handler.go:1312-1346`）测试前保存账号快照；测试后用 RecoverAccountAfterSuccessfulTest 返回的 SuccessfulTestRecoveryResult（已有 ClearedError、ClearedRateLimit），再 GetAccount 读最新状态，与快照对比得到 marked，最后 sendEvent 写出 test_result。此时 handler 还没返回，c.Writer 仍可写。
3. 后台的 RunTestBackground 不经过 handler，不受影响；parseTestSSEOutput（:3336-3364）会忽略新事件类型。

**App 退路**：按 SSE 事件自己计时并标“本机计时”，不显示 Token；必须等 SSE 流结束（EOF）再 GET :id，与测试前的快照对比，得出“已清除错误 / 仍暂停 / 被标为错误或限流”。各平台差异按设计稿 anFailReason 的兜底文案处理，并补上“测试导致限流 / 临时不可调度”两种。

**验收**：
1. `curl -N -X POST "$BASE/api/v1/admin/accounts/12/test" -d '{}'`：最后一条是 test_result，total_ms>0。
2. 对一个 error 账号测试通过后：recovery.cleared_error=true、account.status=active、account.schedulable=false。
3. OpenAI 401 失败时 `data.success=false`、marked.error=true。
4. Web 测试弹窗表现不变。

---

#### C08 · 新增异步账号测试：`POST /api/v1/admin/accounts/:id/test-runs` 返回 202 后可离开，之后查询结果；手动测试结果落库 〔P2 · 新能力〕

**页面**：账号详情 → 手动测试；以后的批量测试；待处理。

**背景**：一次测试要几十秒，手机切后台、锁屏或关掉弹窗 SSE 就断了。需要“提交后离开，回来看结果”，并保留最近一次手动测试的结果（是否成功、耗时、首字、上游状态码、模型）。

**现状**：`POST /api/v1/admin/accounts/:id/test` 只提供 SSE（`server/routes/admin.go:441`；`handler/admin/account_handler.go:1312-1346`），上游请求绑定 c.Request.Context()，客户端一断开就取消。手动测试不落库。RunTestBackground（`service/account_test_service.go:3302-3333`）已能在内存里跑一次测试并产出 ScheduledTestResult{status, response_text, error_message, latency_ms, started_at, finished_at}，但只给定时测试用（`service/scheduled_test_runner_service.go:122-147`）；结果表 scheduled_test_results 绑定 plan_id（`migrations/066_add_scheduled_test_tables.sql:18-28`）。注意：TestAccountConnection 在没有作用域时用不带作用域的 GetByID 读账号（`account_test_service.go:367-375`），对外暴露异步测试前必须先在 handler 里做归属校验（Test handler 的 1318-1324 就是这么做的）。

**建议改法**：
1. `POST /api/v1/admin/accounts/:id/test-runs`，请求体 `{"model_id":"claude-sonnet-4-5","prompt":"","mode":"","recover_on_success":true}`，返回 202：`{"code":0,"message":"accepted","data":{"run_id":"tr_01J…","status":"running","account_id":12,"started_at":"…"}}`。同一账号已有运行中的测试时返回 409，reason=`ACCOUNT_TEST_RUNNING`，`metadata.run_id` 给现有的 run_id。错误响应走 ErrorFrom / ErrorWithDetails，只有 reason 和 metadata（map[string]string），没有 data（`pkg/response/response.go:15-21,71-96`）。
2. `GET /api/v1/admin/accounts/:id/test-runs/latest` 与 `GET /api/v1/admin/account-test-runs/:run_id`：

```json
{"run_id":"tr_01J…","account_id":12,"source":"async","status":"success","model":"claude-sonnet-4-5","latency_ms":3420,"first_token_ms":1210,"upstream_status_code":200,"error_kind":null,"error_summary":"","recovery":{"cleared_error":true},"started_at":"…","finished_at":"…"}
```

   source = `manual` | `async` | `scheduled`；status = `running` | `success` | `failed` | `interrupted`；error_kind 取值同 C02。
3. 现有 SSE 测试结束时也写一条 source=manual 的记录（只增）。后端不推送，App 轮询 latest。

**实现提示**：新表 account_test_runs（run_id、account_id FK ON DELETE CASCADE、source、status、model_id、latency_ms、first_token_ms、upstream_status_code、error_message（脱敏后）、response_text（截断）、recovery JSONB、started_at、finished_at、created_by），每个账号只留最近 20 条。handler 先 adminService.GetAccount 校验作用域，再用有上限的 worker（参照 scheduled runner 的 semaphore）在 `context.Background()` 加 120 秒超时的上下文里调 RunTestBackground；成功且 recover_on_success=true 时调 RecoverAccountAfterSuccessfulTest。进程重启时把 running 改成 interrupted。状态存在 DB，多实例都能查。首字时间与状态码复用 C07 的埋点。

**App 退路**：关闭测试弹窗就是取消；没收到完成事件时提示“不能判定是否成功”；可用 beginBackgroundTask 争取约 30 秒；失败时引导去 Web 看详细错误。间接办法：给账号建一个定时测试计划（`POST /api/v1/admin/scheduled-test-plans`），结果会落库。

**验收**：POST test-runs 立刻返回 202；断开连接后轮询 GET latest，最终 status 为 success 或 failed，且 latency_ms>0；对其他工作区的账号返回 404 或 403；定时测试不受影响。

---

#### C09 · 定时测试结果新增 upstream_status_code（可选再加 error_kind） 〔P2 · 加字段〕

**页面**：账号详情的定时测试结果行。

**背景**：用状态码给结果着色，并判断是否属于凭据类错误。

**现状**：ScheduledTestResult 只有 id、plan_id、status、response_text、error_message、latency_ms、started_at、finished_at、created_at（`service/scheduled_test_port.go:24-34`），表结构相同（`migrations/066_add_scheduled_test_tables.sql:18-28`）。RunTestBackground 从捕获的 SSE 文本里解析 error（`service/account_test_service.go:3302-3364`），状态码只存在于错误文本里，例如 `"API returned %d: ..."`（:620、994）。相关路由：`GET /api/v1/admin/scheduled-test-plans/:id/results`、`GET /api/v1/admin/accounts/:id/scheduled-test-plans`（`server/routes/admin.go:787,790`）。

**建议改法**：结果对象只增 `"upstream_status_code": 429`（拿不到时 null），可选 `"error_kind": "rate_limit"`（取值以 C02 的 error_kind 枚举为准）。现有字段不变。

**实现提示**：迁移（编号见 1.3）`ALTER TABLE scheduled_test_results ADD COLUMN IF NOT EXISTS upstream_status_code INT NULL`（error_kind 同理）；`scheduled_test_port.go` 的结构体加字段，repo 的 SaveResult 与列表查询读写这两列；RunTestBackground 填值：优先结构化（TestEvent 加 status_code omitempty，在发错误事件处带 resp.StatusCode），过渡期用正则 `returned (\d{3})|\((\d{3})\)` 从错误文本解析。

**App 退路**：直接显示 error_message 文本，用同样的正则粗略解析状态码来着色。

**验收**：让一次定时测试命中 429，results 里 upstream_status_code=429；成功项为 200 或 null；Web 的定时测试列表显示不变。

---

#### C10 · 账号 DTO 新增 token_status：统一的 expires_at、lifetime_seconds、refreshed_at；Setup Token 寿命以后端口径为准 〔P2 · 加字段〕

**页面**：账号详情凭据区“访问令牌剩余时间”与刻度条；新建账号的 Setup Token 说明；批量刷新凭据的结果。

**背景**：刻度条的分母要用真实有效期；刷新响应丢失后，读一下账号就能知道刷新是否生效；Setup Token 的说明文案要准确。

**现状**：
- 凭据脱敏后只剩非敏感键与 credentials_status.has_* 标记（`handler/dto/credentials_redact.go:10-28`）。
- expires_at 格式不统一：Claude、Gemini、Antigravity 存 Unix 秒字符串（`service/oauth_refresh_api.go:453-459`、`service/gemini_oauth_service.go:878-881`、`service/antigravity_oauth_service.go:459-462`）；OpenAI、Grok 存 RFC3339（`service/openai_oauth_service.go:396-399`、`service/grok_oauth_service.go:350-354`）。
- 只有 Claude 存 expires_in（`service/oauth_refresh_api.go:457`；手动刷新 `handler/admin/account_handler.go:1544`）；其他平台没有。
- 后台刷新写 `_token_version = UnixMilli`（`service/oauth_refresh_api.go:293-295`，非敏感，GET 能看到）；手动刷新（refreshSingleAccount，`account_handler.go:1440-1580`）与 apply-oauth-credentials 不写。
- Setup Token：后端 `service/token_refresher.go:41-43` 写明 setup-token 的 access_token 与 OAuth 一样 8 小时（expires_in=28800）、需要刷新；Web 文案“Setup Token（长期有效）”（`frontend/src/i18n/locales/zh/admin/accounts.ts:735`，用在 `CreateAccountModal.vue:1420`、`ReAuthAccountModal.vue:70`）与之矛盾，口径以后端 8 小时为准。

**建议改法**：OAuth 与 Setup Token 账号的 DTO 只增一个对象（其他类型为 null）：

```json
{"token_status":{"expires_at":"2026-10-17T17:40:00Z","lifetime_seconds":28800,"refreshed_at":"2026-10-17T09:40:01Z","auto_refresh":true}}
```

- `expires_at` 统一为 RFC3339，用 Account.GetCredentialAsTime 兼容两种存储格式（`service/account.go:369-384`）。
- `lifetime_seconds`：有 expires_in 就用，否则 null。
- `refreshed_at`：最近一次成功刷新或授权的时间。
- Web 把“Setup Token（长期有效）”改为“访问令牌 8 小时，自动刷新”。

**实现提示**：在三个写凭据的地方统一写入 `credentials._token_refreshed_at`（RFC3339，非敏感）和 expires_in：OAuthRefreshAPI.RefreshIfNeeded（`service/oauth_refresh_api.go:293`）、refreshSingleAccount、ApplyOAuthCredentials；各平台 TokenInfo 都有 ExpiresIn（`service/oauth_service.go:137`、`openai_oauth_service.go:118`、`gemini_oauth_service.go:200`、`antigravity_oauth_service.go:87`、`grok_oauth_service.go:132`）。token_status 在 dto mapper 里计算。存量 OpenAI 等账号要等下一次刷新后才有 lifetime_seconds。

**App 退路**：兼容解析 credentials.expires_at 的两种格式；分母：Claude 与 Setup Token 读 credentials.expires_in，其他平台写死（ChatGPT 10 天只能算估计，标“约”）；刷新前记下 expires_at，响应丢失后 GET :id 看 expires_at 是否后移，后台刷新还可看 _token_version；Setup Token 按后端口径写 8 小时、自动刷新。

**验收**：GET 一个 Claude OAuth 账号，token_status.lifetime_seconds=28800、expires_at 为 RFC3339；手动刷新后 refreshed_at 更新；OpenAI 账号 expires_at 解析正确；Web 新建和重新授权弹窗不再显示“长期有效”。

---

#### C11 · 新增 `POST /api/v1/admin/accounts/:id/reauthorize`（服务端一步换码并落库）；apply-oauth-credentials 增加可选 preserve_status 〔P2 · 新接口〕

**页面**：账号详情 · 凭据区“重新授权…”；凭据类错误时状态卡的主按钮。

**背景**：授权码只能用一次；换码成功但落库失败时，码已用掉、令牌也已发到手机。管理员有时只想换令牌，不想让停用账号上线。用户已决定：在停用账号上先弹确认“授权后账号会被重新启用”（`DECISIONS.md:113`）。

**现状**：重新授权要两次请求：
1. 各平台 exchange-code 把 TokenInfo（含 access_token、refresh_token）原样返回给客户端：Claude `handler/admin/account_handler.go:2493-2534`、OpenAI `handler/admin/openai_oauth_handler.go:146-165`、Gemini `handler/admin/gemini_oauth_handler.go:94-123`、Antigravity `handler/admin/antigravity_oauth_handler.go:48-66`、Grok `handler/admin/grok_oauth_handler.go:91-112`。
2. 客户端再 `POST /admin/accounts/:id/apply-oauth-credentials {type, credentials, extra}` 落库（`account_handler.go:1615-1736`）。apply 末尾调 ClearAccountError（:1716），而 repo ClearError 无条件 SetStatus(active)（`repository/account_repo.go:1900-1905`），所以停用（inactive）账号会被重新启用，没有参数可关。

其他：Grok 的 exchange-code 已接受 account_id 用来约束代理（`grok_oauth_handler.go:82-101`）；OpenAI 有“换码 + 新建账号”的 create-from-oauth（`openai_oauth_handler.go:301-360`），没有“换码 + 写入已有账号”；Claude 只在换码成功时才删除会话（`service/oauth_service.go:166-172`），换码失败可用原会话重试。

**建议改法**：
1. `POST /api/v1/admin/accounts/:id/reauthorize`：

```json
{"session_id":"…","code":"…","state":"…","redirect_uri":"…","proxy_id":3,"auth_kind":"oauth","oauth_type":"code_assist","tier_id":"","preserve_status":true}
```

   服务端按账号 platform 选换码服务，用与 Web 相同的 Build*Credentials 构造凭据，合并后落库，再清除错误和限流，返回账号对象（不含令牌）。auth_kind 只对 Claude 有意义（`oauth` | `setup-token`，决定账号 type）。preserve_status=true 时停用账号保持停用。错误码：400 `*_OAUTH_SESSION_NOT_FOUND` / `*_OAUTH_INVALID_STATE`（见 C12）；400 `NOT_OAUTH`；502 `OAUTH_EXCHANGE_FAILED`（上游拒绝）；500 `REAUTH_PERSIST_FAILED`（换码成功但落库失败——服务端把换到的令牌在会话里暂存 5 分钟，允许用同一 session_id 重试落库，不需要新授权码）。
2. 现有 apply-oauth-credentials 只增可选字段 `"preserve_status": true`，缺省 false（保持现状）。

**实现提示**：AccountHandler 已持有 oauthService、openaiOAuthService、geminiOAuthService、antigravityOAuthService、grokOAuthService（`account_handler.go:101-133`），不用新增依赖。先 adminService.GetAccount 校验归属并确认 IsOAuth；Grok 走与 constrainGrokReauthProxy 相同的代理约束。把 ApplyOAuthCredentials 后半段抽成私有函数复用。preserve_status：existing.Status==inactive 时不调 ClearAccountError，改调 rateLimitService.RecoverAccountState（它只在 status==error 时才 ClearError，`service/ratelimit_service.go:2170`）；Antigravity 账号另调 ClearAntigravityQuotaScopes。令牌只在服务端流转，日志一律脱敏。

**App 退路**：照 Web 两步走：exchange-code → apply-oauth-credentials。令牌只在内存里保留到 apply 成功为止；apply 失败就用同一份令牌重试（refresh_token 仍有效），不要重新换码。停用账号先弹确认“授权后账号会被重新启用”（用户已定），授权完成后如需要再 `PUT status=inactive`。

**验收**：对 inactive 的 Claude OAuth 账号调 reauthorize 带 preserve_status:true：200，status 仍为 inactive，credentials_status.has_access_token=true；响应与服务端日志里都没有令牌原文；上面列出的错误码都能复现。

---

#### C12 · OAuth 换码时会话过期、state 不符、授权码被拒，各平台统一返回 400 与可识别的 reason 〔P2 · 改行为〕

**页面**：新建账号 OAuth 三步（第 3 步粘贴授权码）；账号详情“重新授权…”。

**背景**：授权会话 30 分钟后过期，这时应提示“授权链接已过期，请重新生成”，而不是笼统的服务器错误。

**现状**：
- Claude（accounts/exchange-code、exchange-setup-token-code）：`service/oauth_service.go:149-152` 返回 `fmt.Errorf("session not found or expired")`，handler 用 response.ErrorFrom（`handler/admin/account_handler.go:2493-2534`），经 FromError（`pkg/errors/errors.go:146-158`；`pkg/response/response.go:82-95`）变成 500 "internal error"，原因丢失；上游拒绝授权码同样是 500。
- Gemini：`service/gemini_oauth_service.go:450-453` 是 fmt.Errorf，handler 用 `response.BadRequest("Failed to exchange code: "+err)`（`handler/admin/gemini_oauth_handler.go:118-121`），400、message 有原文、没有 reason。
- Antigravity：`service/antigravity_oauth_service.go:99-102` 返回“session 不存在或已过期”，handler 用 `BadRequest("Token 交换失败: "+err)`（`handler/admin/antigravity_oauth_handler.go:61-64`），同样 400、没有 reason。
- OpenAI、Grok 已经是 400 且带 OPENAI_OAUTH_SESSION_NOT_FOUND / GROK_OAUTH_SESSION_NOT_FOUND（`service/openai_oauth_service.go:137`、`service/grok_oauth_service.go:156`），state 不符时有 *_OAUTH_INVALID_STATE（`openai_oauth_service.go:143`、`grok_oauth_service.go:172`）。
- 会话 TTL 30 分钟，存在内存里（`pkg/oauth/oauth.go:34,87`）。

**建议改法**：统一规则——会话不存在或过期：400，reason=`<PLATFORM>_OAUTH_SESSION_NOT_FOUND`（新增 CLAUDE_、GEMINI_、ANTIGRAVITY_ 三个，与现有 OPENAI_、GROK_ 同一模式，App 按后缀识别）；state 不符：400，`<PLATFORM>_OAUTH_INVALID_STATE`；上游拒绝授权码：400，`<PLATFORM>_OAUTH_CODE_REJECTED`，metadata.upstream_status 给上游状态码。例：`{"code":400,"message":"session not found or expired","reason":"CLAUDE_OAUTH_SESSION_NOT_FOUND"}`。Gemini、Antigravity 的 message 前缀保持不变，只补 reason。

**实现提示**：`oauth_service.go:151` 改为 `infraerrors.New(http.StatusBadRequest, "CLAUDE_OAUTH_SESSION_NOT_FOUND", "session not found or expired")`；exchangeCodeForToken 遇到上游 4xx 包成 CLAUDE_OAUTH_CODE_REJECTED。`gemini_oauth_service.go:452,456` 与 `antigravity_oauth_service.go:101,105` 同理。两个 handler 改为：`infraerrors.Reason(err)` 非空时调 `response.ErrorWithDetails(c, 400, 原前缀+err.Error(), reason, metadata)`，否则保持原 BadRequest，这样 message 不变、Web 显示不受影响。Claude 从 500 改成 400 对 Web 没有破坏（两种情况都是显示错误）。

**App 退路**：App 记下生成授权链接的时间；超过 30 分钟，或收到 500 / 400 时，提示“授权链接可能已过期，请重新生成”并给按钮。后端重启导致内存会话丢失时也走同一提示。

**验收**：用不存在的 session_id 调 Claude 换码：400，reason=CLAUDE_OAUTH_SESSION_NOT_FOUND；Gemini、Antigravity 同理且 message 前缀不变；Web 授权弹窗回归通过。

---

#### C13 · 新增 `GET /api/v1/admin/meta/catalog`：运行时下发平台目录（BuildPlatformCatalog）与各类枚举 〔P2 · 新接口〕

**页面**：新建账号（平台下拉、认证方式、国产厂商 payg / coding 模式、API 协议与端点预设、底部坞“还差什么”）；账号详情 · 高级；账号筛选；创建分组选平台；日志筛选；用户角色。

**背景**：App 要按站点实际支持的平台和模式生成表单、校验必填项；后端新增平台或状态时，App 不发新版也能显示和筛选。

**现状**：后端没有运行时元数据接口。`service.BuildPlatformCatalog()`（`service/platform_catalog.go:44-58`）已能生成 `{platforms[id, display_name, gateway, cn_provider, litellm_provider, multi_protocol{default_mode, routing, modes[{mode, base_urls, protocol_rules}]}], composite_precedence}`，但只被测试用来生成前端的 platformCatalog.builtin.json（`service/platform_catalog_test.go:124-139`；`frontend/src/constants/platformCatalog.ts:1-10`）。其他元数据散落各处：认证方式只写在 binding tag 里（`handler/admin/account_handler.go:139`：`oneof=oauth setup-token apikey upstream bedrock service_account`）；必填字段与 extra 键名只写在 Web 的 credentialsBuilder.ts；状态筛选的派生值写在 repo（`repository/account_repo.go:1062-1115`）；只有 Gemini、Grok 有 oauth/capabilities（`server/routes/admin.go:523,539`）。

**建议改法**：`GET /api/v1/admin/meta/catalog`（带 ETag，客户端可长时间缓存）：

```json
{"platform_catalog":{"platforms":[],"composite_precedence":[]},
 "account_types":["oauth","setup-token","apikey","upstream","bedrock","service_account"],
 "platform_auth":{"anthropic":["oauth","setup-token","apikey"],"openai":["oauth","apikey"]},
 "account_status_filters":["active","inactive","error","rate_limited","temp_unschedulable","unschedulable"],
 "request_types":["sync","stream","ws_v2","cyber","live"],"error_phases":[],"user_roles":["admin","user"],
 "credential_fields":{"anthropic/apikey":[{"key":"api_key","required":true,"sensitive":true},{"key":"base_url","required":false}]}}
```

platform_catalog 是 BuildPlatformCatalog() 的原样输出。分两期：第一期 platform_catalog + 枚举（都是现成常量）；第二期 credential_fields（需先把 credentialsBuilder.ts 的规则迁到后端常量）。

**实现提示**：新建 `handler/admin/meta_handler.go`，直接返回 BuildPlatformCatalog() 与 domain 常量，纯内存不查 DB；ETag 取 JSON 的 sha256；路由挂 admin 组。vendor：`/api/v1/admin/meta` 不在白名单里，默认 403（`server/middleware/vendor_routes.go:98-153`）。要给 vendor 用（它也能新建账号），就加一条 exact 规则 `{prefix:"/api/v1/admin/meta/catalog",methods:["GET"],exact:true,permit:permitAccountManage}`，并按作用域裁剪 platform_auth（vendor 不能新建 Grok 账号，`service/admin_account.go:529-538`）；不开放就不必裁剪。加一个测试保证输出与 platformCatalog.builtin.json 一致。

**App 退路**：内置一份与 platformCatalog.builtin.json 同步的平台清单与枚举，随 App 发版更新；遇到不认识的平台或状态值显示原始 id、归入“其他”，不能崩溃。

**验收**：`GET /api/v1/admin/meta/catalog` 的 platform_catalog 与 `frontend/src/constants/platformCatalog.builtin.json` 完全一致；后端新增一个平台后，App 不发版就能在下拉里看到它（显示名来自接口）。

---

#### C14 · 账号列表只增查询参数：status 多值与派生值（overloaded / needs_attention）、sort_by=urgency、include_counts 〔P2 · 加参数〕

**页面**：账号 Tab（按平台 → 同分组 → 紧急度；不分组时“排序与筛选”可按金额）；筛选胶囊（需处理 / 受限 / 暂停·停用）；首页“受限 N 个账号”跳转；批量“全选”。

**背景**：分组和排序要覆盖全部账号、不受分页影响；账号多时不应拉全量再在本地过滤（分组规则见 `DECISIONS.md:65`）。

**现状**：List 读取 platform、type、status、search、group、privacy_mode、sort_by、sort_order、lite（`handler/admin/account_handler.go:659-694`）。status 的派生值只有 active、rate_limited、temp_unschedulable、unschedulable，其他值按原样匹配（error、inactive）（`repository/account_repo.go:1062-1115`），只能传单个值，没有 overloaded。status=active 不排除过载账号（1064-1078 没有 overload_until 条件），与 IsSchedulable（`service/account.go:172-193`）和调度 SQL（`account_repo.go:2077-2087`）不一致，Web 与 App 的“正常”筛选会混入过载账号。sort_by 只支持 name、id、status、schedulable、priority、rate_multiplier、last_used_at、expires_at、created_at、upstream_billing_rate（:1227-1276）。page_size 上限 1000（`pkg/response/response.go:170-192`）。现有计数来源：dashboard/stats 有 normal / error / ratelimit / overload 账号数（`handler/admin/dashboard_handler.go:96-100`）；ops/account-availability 要开启运维监控（`handler/admin/ops_realtime_handler.go:117-168`）。

**建议改法**：`GET /api/v1/admin/accounts` 只增参数：
- `status` 支持逗号分隔多值，新增两个派生值：`overloaded`（status=active 且 overload_until>NOW()）、`needs_attention`（status=error，或 status=active 且处在过载 / 限流 / 临时不可调度任一窗口中）。
- “暂停”胶囊直接用现有的派生值 `unschedulable`，不另加 paused。它的定义是 status=active、schedulable=false，且不在限流、临时不可调度中（`repository/account_repo.go:1101-1115`），Web 的状态筛选在用（`frontend/src/components/admin/account/AccountTableFilters.vue:54`），保持不动。与 D02 的 state=paused 只在两类账号上不同：过载中又停了调度的账号，unschedulable 会算进来，D02 按“限时状态优先”判为 overloaded；刚到期、还没被后台任务停调度的自动暂停账号，D02 算 paused，unschedulable 不算。App 的胶囊用 unschedulable，组头计数用 D02，两处文案都写“暂停”，差异只影响这两类边角账号。新增的派生值按 D02 的判定顺序实现（inactive、error 先于限时状态，限时状态先于停调度），不再引入第三种口径。
- `sort_by=urgency`：error > 过载 / 限流 / 临时不可调度（按恢复时间由近到远）> 停止调度（unschedulable）> inactive > 正常，同级按 name；以后可再加 today_cost（依赖 C04 的聚合）。
- `include_counts=1`：data 里附带 `"counts":{"all":120,"needs_attention":7,"unschedulable":3,"inactive":2}`，按当前其他筛选条件统计。items、total、page 结构不变。

**实现提示**：在 `account_repo.go` 的 accountListFilteredQuery 里抽出 `statusPredicate(s)`，多值用 OR 组合；active 漏掉 overload_until 的问题，为不影响 Web，新增 `schedulable_now` 派生值而不是改 active（是否改 active 的默认口径见附录 C Q18）。urgency 排序用 entsql.Expr 写 CASE，参照 upstreamBillingRateSortExpression（:1227-1243）。counts 用同一组条件做 `COUNT(*) FILTER`，一条 SQL。buildAccountsListETag（`account_handler.go:882-920`）要把新参数算进去。Web 不传新参数，不受影响。

**App 退路**：拉全量 lite 列表（page_size=1000 翻页），本地按 rate_limit_reset_at、overload_until、temp_unschedulable_until、status、schedulable 推出状态，再分组、排序；按金额排序配合 today-stats/batch；组头计数用 D02 或本地计数；“全选”前先把列表补全。

**验收**：status=overloaded 只返回过载账号；status=error,rate_limited 返回两者并集；status=needs_attention 的 total 等于 include_counts 里的 needs_attention；status=unschedulable 的结果与现在一致；sort_by=urgency 时第一页就是最紧急的账号；不带新参数时结果与现在一致。

---

#### C15 · 新增 `POST /api/v1/admin/accounts/runtime/batch`：按账号 ID 批量取实时数据，读取失败时返回“不可用”而不是 0 〔P2 · 新接口〕

**页面**：账号列表（在用并发、RPM、状态）、账号详情容量区、分组成员。

**背景**：自动刷新时只更新屏幕上这些账号的实时数字，不整页重拉。

**现状**：没有按 ID 批量取实时值的接口。列表的 full 与 lite 每页都会采样实时数据（`handler/admin/account_handler.go:739-841`），开启了窗口费用的 Anthropic 账号还会跑窗口 SQL（:788-813）。Redis 读取并发失败时 concurrencyCounts 不会被填充，而 CurrentConcurrency 是不可为空的 int，结果是 0（列表 :745-753，单个账号 buildAccountResponseWithRuntime :393-398）。40bee5d2e 的 current_rpm 只返回给 Anthropic OAuth / SetupToken 且 base_rpm>0 的账号（:416-421、776-782），origin/main 已改为所有账号返回并在失败时省略（见 A01）。ops/concurrency 也能给按账号的并发，但要开运维监控（`server/routes/admin.go:212`）。

**建议改法**：`POST /api/v1/admin/accounts/runtime/batch`，请求体 `{"account_ids":[12,15]}`，最多 200 个；可选 `include_window_cost=0` 跳过窗口 SQL。

```json
{"sampled_at":"2026-10-17T09:40:00Z",
 "items":{"12":{"current_concurrency":3,"probe_concurrency":0,"concurrency_available":true,"current_rpm":42,"scheduling_rpm":40,"active_sessions":2,"current_window_cost":12.3,"status":"active","schedulable":true,"rate_limit_reset_at":null,"overload_until":null,"temp_unschedulable_until":null}}}
```

读取失败的指标省略或置 null，并且 concurrency_available=false。现有列表和详情项同时只增 `concurrency_available: bool`。

**实现提示**：把 List 里的采样逻辑抽成 `h.sampleRuntime(ctx, accounts)`，列表与新接口共用；状态字段用 accountRepo.GetByIDs 一条 SQL 取回；先 FilterAccountIDsByScope 收窄作用域（handler 里必须保留）；可加 5 秒 snapshotCache；在 A01 基线上改，复用 RollingRPMCache。vendor：这个 POST 会命中 accounts 写方法的前缀规则，持 AccountManage 的 vendor 不改也能调（`server/middleware/vendor_routes.go:120-122`）；它也不在 vendorBatchAccountRoutes（`:155-166`）里，而代码注释要求批量扇出类端点显式登记（`:65-68`）。做法：把 `/api/v1/admin/accounts/runtime/batch` 加进 vendorBatchAccountRoutes，再单独加一条 exact 规则，permit 用 permitAccountRead（与 GET 账号列表同档，只有监控档的 vendor 也能读实时数；today-stats/batch 用的是 permitMonitorView，`:118-119`）；或者明确拒绝 vendor（加进 vendorDeniedRoutes）。补守卫测试。

**App 退路**：每 30 秒重拉已加载的页（lite）或详情；current_concurrency=0 理解为“0 或未知”，不下肯定结论；RPM 缺失时显示“—”。

**验收**：传 3 个 ID 返回 3 项；模拟 Redis 故障时 concurrency_available=false，不用 0 冒充真实值；其他工作区的 ID 被过滤掉；只有 MonitorView 的 vendor 能调（按开放方案）或返回 403（按拒绝方案），守卫测试覆盖。

---

#### C16 · today-stats/batch 只增 failed_account_ids / degraded，有失败项时不写缓存 〔P2 · 加字段〕

**页面**：账号列表的“今日统计”。

**背景**：要能区分“今天确实没有请求”和“统计查询失败”。

**现状**：GetTodayStatsBatch（`service/account_usage_service.go:1413-1468`）在批量 SQL 失败后改为逐个查询；单个查询失败时直接 return nil 吞掉错误；最后对缺失项补全 0 的 `&WindowStats{}`，整体仍返回成功。handler 还会把结果缓存 30 秒（`handler/admin/account_handler.go:2797-2808`；`handler/admin/account_today_stats_cache.go:9`），失败补出来的 0 会被后续请求命中。单账号 `GET :id/today-stats` 失败会直接报错（:2735-2739），这点没问题。

**建议改法**：响应 data 只增 `{"stats":{…不变…},"failed_account_ids":[15],"degraded":true}`。degraded=true 表示批量 SQL 失败、走了逐个查询。为兼容 Web，stats 里失败项仍补 0，App 根据 failed_account_ids 显示“—”。有失败项时不写缓存；全部失败时返回 503，reason=`ACCOUNT_STATS_UNAVAILABLE`。

**实现提示**：新增 GetTodayStatsBatchDetailed 返回 (map, failedIDs, degraded, err)，旧方法签名不变、内部调用新方法；handler 在 failedIDs 非空时跳过 accountTodayStatsBatchCache.Set，并把两个字段写进 payload。

**App 退路**：原样显示；需要确认某个账号时，用单账号 `GET /admin/accounts/:id/today-stats`（失败会报错）。

**验收**：模拟某账号统计查询失败，响应 failed_account_ids 含该 ID；30 秒内重复请求不会命中缓存里的 0；Web 显示不变。

---

#### C17 · today-stats/batch 请求体只增可选 group_id：只统计该分组的今日用量 〔P2 · 加参数〕

**页面**：分组详情成员列表；概览中按分组聚合的待处理卡。

**背景**：成员行要显示“这个账号在本分组的今日”，才能和分组今日对得上。

**现状**：BatchTodayStatsRequest 只有 account_ids（`handler/admin/account_handler.go:2745-2747`），SQL 只按 account_id 与 created_at 过滤（`repository/usage_log_repo_stats.go:340-357`）。usage_logs 有 group_id 列与 (group_id, created_at) 索引（`ent/schema/usage_log.go:71,235-247`）。分组今日来自 groups/usage-summary，按 usage_logs.group_id（Key 所属分组）统计（`handler/admin/group_handler.go:937-968`）。

**建议改法**：`POST /api/v1/admin/accounts/today-stats/batch` 请求体只增可选 `"group_id": 7`；带上时只统计 usage_logs.group_id=7 的行。响应结构不变，另回显 `"group_id":7`。

**实现提示**：BatchTodayStatsRequest 加 `GroupID *int64`；service 新增 GetTodayStatsBatchByGroup；SQL 加 `AND group_id=$3`（先走 idx_usage_logs_account_created_at 再过滤）。缓存键 buildAccountTodayStatsBatchCacheKey 必须带 group_id。vendor 要校验分组授权。统一“今天”的起点：分组汇总用 GroupUsageTodayStart（`group_handler.go:944`），账号统计用 timezone.Today()（`service/account_usage_service.go:1432`），两处应一致，否则对不上。

**App 退路**：成员行下注“账号今日含这个账号在其他分组的用量”，表格变体不显示合计（设计稿 `html-preview/layouts/main/v-groups.jsx:217-221` 已这样处理）。

**验收**：账号 12 同时服务分组 7 和 9：group_id=7 与 group_id=9 两次结果相加约等于不带 group_id 的结果（未分组 Key 产生的用量除外）；Web 不传 group_id，不受影响。

---

#### C18 · 清除错误时可选不重新启用停用账号（clear-error / batch-clear-error 加 preserve_inactive） 〔P2 · 加参数〕

**页面**：账号列表“选择”+ 操作坞的“恢复状态”；首页待处理里合并的受限账号；分组详情成员。

**背景**：批量恢复时选中的账号里可能有停用（inactive）的，现在一恢复就被重新启用、重新接流量。

**现状**：repo ClearError 无条件 `SetStatus(active)`（`repository/account_repo.go:1900-1905`），ClearAccountError 每次都调它（`service/admin_account.go:1468-1475`），所以 `POST /admin/accounts/:id/clear-error`（`server/routes/admin.go:448`）、`POST /admin/accounts/batch-clear-error`（:470）、apply-oauth-credentials（C11）都会把 inactive 账号改成 active；而 recover-state 只在 status==error 时才清（`service/ratelimit_service.go:2170`）。

**建议改法**（只增，默认不变）：两个接口接受可选 `"preserve_inactive": true`（batch 放在请求体，单个接口用可选请求体）。为 true 时，status=inactive 的账号只清限流、过载、临时不可调度与模型限流，不改 status；batch 响应在现有 `{total,success,failed,errors}` 上只增 `"skipped_inactive_ids":[…]`（这些账号也计入 success；新字段初始化为空切片，没有时输出 `[]`，不要像 errors 那样输出 null，见附录 A S27）。是否把默认改成“只在 status=error 时改 active”见附录 C Q9。

**实现提示**：ClearAccountError 加 options 参数（或新增 ClearAccountErrorWithOptions），preserve_inactive 时先读状态，inactive 则跳过 repo.ClearError、其余清理照做；更稳的写法是给 repo 加 `ClearErrorIfError`（`WHERE id=$1 AND status='error'`）。BatchClearError（`handler/admin/account_handler.go:1953-2017`）透传。Web 不传，不受影响。

**App 退路**：批量恢复前先在本地过滤掉 status=inactive 的账号，并在确认框写明“已停用的 N 个账号不会被处理”。

**验收**：选 1 个 inactive + 1 个 error 账号调 batch-clear-error 带 preserve_inactive:true：inactive 账号仍是 inactive 且出现在 skipped_inactive_ids，error 账号变为 active；不带参数时行为与现在一致。

---

#### C19 · （sub2 Web 前端改动，后端不动）账号管理页支持 `/admin/accounts?edit=<id>` 深链，直接打开该账号的编辑弹窗 〔P2 · Web 前端〕

**页面**：账号详情 · 高级区与 ⋯ 菜单里的“在 Web 中编辑”。

**背景**：手机端只编辑常用字段，复杂设置跳到 Web 继续改。

**现状**：AccountsView.vue 没有引入 vue-router（文件里没有 useRoute / useRouter），onMounted（`frontend/src/views/admin/AccountsView.vue:2555-2595`）只加载列表。编辑入口 handleEdit 需要传入列表行（:1859-1864），而它内部用的 loadAccountDetails 只需要 `{id}`（:1845）。路由 `/admin/accounts` 不带参数（`frontend/src/router/index.ts:559`）。未登录时守卫会带上 to.fullPath 跳到登录页（`frontend/src/router/index.ts:940-946`），登录后能回到原地址、query 不会丢。

**建议改法**：支持 `https://<站点>/admin/accounts?edit=<id>`，可选 `&search=<name>` 预填搜索框。挂载后如有 edit 参数，调 `loadAccountDetails({id})` 打开 EditAccountModal；打开后用 router.replace 去掉 edit 参数，避免刷新时重复弹出；账号不存在或无权限时弹 toast。后端不需要改。

**实现提示**：AccountsView.vue 引入 useRoute、useRouter，在 onMounted 末尾解析 route.query.edit 与 route.query.search，复用 loadAccountDetails、edAcc、showEdit。补一个 Vitest：带 edit 参数挂载时会打开弹窗。

**App 退路**：打开 Web 账号列表，同时复制账号名，提示用户自己搜索。

**验收**：已登录的浏览器打开 `/admin/accounts?edit=12` 自动弹出账号 12 的编辑框，地址栏 edit 参数随后消失；未登录时先登录，回到该地址后再弹出；id 无效时显示提示。

---

### D 日志与监控

#### D01 · 告警静默：允许无平台作用域（修复评估器只在有 platform 时才检查静默），新增静默的列表、修改、撤销接口，告警事件返回静默信息 〔P0 · 改行为 + 新接口〕

**页面**：监控 · 告警行与告警详情页（“已静默至 HH:MM”、“改静默时长…”）；首页告警行；账号页按分组时组头的告警牌。

**背景**：用户定了告警只能手动解决，或静默 1 小时 / 24 小时 / 7 天（`DECISIONS.md:44`）。App 要显示静默到什么时候、能改时长，换设备、重装或在 Web 上操作后状态一致；管理员发起的静默必须真的生效。

**现状**：
1. 只有 `POST /api/v1/admin/ops/alert-silences`（`server/routes/admin.go:225`），没有 GET / PUT / DELETE。
2. 服务层要求 platform 非空，否则 400 INVALID_PLATFORM（`service/ops_alerts.go:140-142`），仓储层也拒绝空值（`repository/ops_repo_alerts.go:641-644`）。
3. 评估器只在规则作用域有 platform 时才查静默（`service/ops_alert_evaluator_service.go:252-259`），IsAlertSilenced 遇到空 platform 直接返回 false（`service/ops_alerts.go:164-166`；`repository/ops_repo_alerts.go:717-720`）。所以只配了分组的规则、服务器类规则（CPU、内存、排队）和全局错误率规则都静默不了；迁移预置的 8 条规则全是全局规则（`migrations/033_ops_monitoring_vnext.sql:620-704`）。
4. Web 也受影响：告警详情静默时把空 platform 原样发出（`frontend/src/views/admin/ops/components/OpsAlertEventsCard.vue:283-295`），这类规则一律 400。
5. OpsAlertEvent 没有静默信息（`service/ops_alert_models.go:41-60`）。
6. 静默只拦截新事件：规则已有活跃事件时直接 continue（`ops_alert_evaluator_service.go:246-249`），与设计稿文案“当前这条仍需手动解决”一致，不需要改。
7. 表结构：ops_alert_silences.platform 是 NOT NULL，可以存空串；索引 (rule_id, platform, group_id, region, until) 已有（`migrations/037_ops_alert_silences.sql:5-21`）。

**建议改法**：
1. **改行为**（只放宽，原本能用的调用不受影响）：`POST /api/v1/admin/ops/alert-silences` 允许 platform 为空或缺省，空串表示规则作用域没有平台；评估器对没有 platform 的规则也检查静默。Web 现在报 400 的情况会变成成功。
2. **新接口**：
   - `GET /api/v1/admin/ops/alert-silences?active=true&rule_id=41&limit=100` → `[{"id":7,"rule_id":41,"platform":"","group_id":2,"region":null,"until":"2026-10-18T02:41:00Z","reason":"…","created_by":1,"created_by_name":"admin","created_at":"…"}]`
   - `PUT /api/v1/admin/ops/alert-silences/:id`，body `{"until":"2026-10-19T01:41:00Z","reason":"可选"}` → 更新后的静默对象。
   - `DELETE /api/v1/admin/ops/alert-silences/:id` → `{"deleted":true}`（实现为 until=NOW()，保留审计记录）。
3. **加字段**：`GET /api/v1/admin/ops/alert-events` 与 `/alert-events/:id` 的每条事件增加 `"silence":{"id":7,"until":"2026-10-18T02:41:00Z"}`（没有生效中的静默时为 null）。匹配：rule_id 相同；platform = COALESCE(dimensions->>'platform', '')；group_id / region 用 IS NOT DISTINCT FROM；until > now；有多条时取 until 最大的一条。
4. **可选便捷接口**：`POST /api/v1/admin/ops/alert-events/:id/silence`，body `{"duration":"1h"|"24h"|"7d"}` 或 `{"until":"…"}`；服务端从事件维度推出作用域，客户端不用自己拼。

错误码：400 `INVALID_UNTIL`（until 不是将来时间或超过 30 天）、400 `INVALID_RULE_ID`；404 `OPS_ALERT_SILENCE_NOT_FOUND`、404 `OPS_ALERT_EVENT_NOT_FOUND`；404 OPS_DISABLED（与现有接口一致）。

**实现提示**：
- `service/ops_alerts.go:140-142` 删掉 platform 必填校验，只保留 TrimSpace；:164-166 删掉“空 platform 返回 false”。
- `repository/ops_repo_alerts.go:641-644`、:717-720 同步放开（SQL 的 `platform = $2` 用空串匹配即可，不需要迁移）。
- `service/ops_alert_evaluator_service.go:255` 去掉 `if platform != ""`。
- 列表、修改、撤销：`ops_repo_alerts.go` 新增 ListAlertSilences、UpdateAlertSilenceUntil，查询 LEFT JOIN users 取 created_by_name。
- 事件附带静默：在 ListAlertEvents（:320）与 GetAlertEventByID（:416）的 SQL 上加 `LEFT JOIN LATERAL (SELECT id, until FROM ops_alert_silences s WHERE … ORDER BY until DESC LIMIT 1)`，scanOpsAlertEvent（:746）多扫两列。
- 路由加在 `server/routes/admin.go:225` 旁；所有新接口都走 RequireMonitoringEnabled。
- 同一作用域可能有多条重叠的静默：事件只展示 until 最大的那条，App“改时长”时对它 PUT；缩短时长时，服务端在 PUT 里一并撤销同作用域的其他静默（或由 App 依次 DELETE）。

**App 退路**：无平台规则（含全部预置规则）隐藏“静默…”按钮，只保留“手动解决”。有平台的规则可以 POST 静默，但查不到状态，“已静默至”只能存在本机，换设备、重装或在 Web 操作后对不上；“改静默时长”只能延长（再 POST 一条），不能缩短或撤销。

**验收**：
1. `curl -X POST "$BASE/api/v1/admin/ops/alert-silences" -H "Authorization: Bearer $T" -d '{"rule_id":1,"until":"<1 小时后>"}'` → 200（修复前 400 INVALID_PLATFORM）。
2. 让 1 号规则（全局错误率）满足条件：静默期内不产生新的 firing 事件；到期后的下一次评估会触发。
3. `GET /api/v1/admin/ops/alert-events/:id` 的 silence.until 与静默一致；PUT 改短后 until 变化；DELETE 后 silence 为 null，下一次评估可触发。
4. 带 platform 的旧调用行为不变（回归 IsAlertSilenced 的 platform + group 匹配）。
5. 在 Web 告警详情里静默一条全局规则，不再报错。

---

#### D02 · 新增不依赖运维监控的账号状态汇总 `GET /api/v1/admin/accounts/status-summary`：全站、平台、分组分档计数，逐账号主状态，分组“可用不足”判定 〔P1 · 新接口〕

**页面**：概览待处理队列与平静布局判断（“分组无可用账号”卡、可用 x/y 与色格条、“N 个账号可调度”）；账号 Tab 按分组的组头计数；分组列表“可用 x/y”“需处理”分段。

**背景**：账号与分组是多对多。首页待处理、平静布局、账号 Tab 组头和分组列表都要按“可用 / 错误 / 过载中 / 限流中 / 临时不可调度 / 暂停 / 停用”分档计数（设计稿状态顺序见 `html-preview/shared/data.jsx:55-65,586-599`），并判断分组“可用不足”。站点没开运维监控时，首页也要知道有没有要处理的事。

**现状**：
1. ops/account-availability（`handler/admin/ops_realtime_handler.go:117-168`）先 RequireMonitoringEnabled（:122），实时监控关闭时直接返回 enabled:false 与空 map（:127-136）；service 层也要求开启监控（`service/ops_account_availability.go:19-21`）。
2. Platform / Group 级只有 total / available / rate_limit / error 四个数（`service/ops_realtime_models.go:51-69`），rate_limit 只看 rate_limit_reset_at（`service/ops_account_availability.go:58,81-86`），过载、临时不可调度、暂停（schedulable=false）、停用（inactive）都没有计数；status=error 时把 rate_limited / overloaded 清零（:63-66）。
3. 逐账号只给第一个分组（:113-125；`ops_realtime_models.go:72-77`），没有 schedulable、temp_unschedulable_reason、model_rate_limits；取数查询也没选这些列（`repository/account_repo.go:1205-1218`）。
4. is_available 不看账号过期（`ops_account_availability.go:68`），而分组列表的 groupAccountAvailableSQL 排除 expires_at 已过且 auto_pause_on_expired 的账号（`repository/group_repo.go:980-987`）；分组列表的 rate_limited_account_count 把过载、临时不可调度也算进去（:989-997）。两套口径同一分组可能对不上，告警指标 group_available_* 按运维口径评估。
5. 已有且不依赖运维监控的：admin/groups 与 groups/all 带 account_count、active_account_count（调度口径的“可用”）、rate_limited_account_count（`repository/group_repo.go:671-699,989-997`；`handler/dto/types.go:199-202`）；dashboard/stats 有全站 total / normal / error / ratelimit / overload 账号数（`handler/admin/dashboard_handler.go:96-100`；`repository/usage_log_repo_dashboard.go:173-174`）；admin/accounts 的 status 筛选（`repository/account_repo.go:1062-1120`），但没有计数接口，也没有 overloaded 筛选。
6. “可用不足”只能另读 ops/alert-rules 里的 group_available_ratio / group_available_accounts，该接口也要求开启运维监控（`service/ops_alerts.go:13-21`）。
7. 首页错误率、账号详情“最近上游错误”只能来自运维数据（监控关闭时网关不写 ops_error_logs，`handler/ops_error_logger.go:1101`），不在本接口范围内。

**建议改法**（只新增，不改 ops/account-availability 现有语义）：`GET /api/v1/admin/accounts/status-summary?platform=&group_id=&include_accounts=false&default_min_ratio=0.5`

```json
{"code":0,"message":"success","data":{
  "collected_at":"2026-10-18T01:41:00Z",
  "totals":{"total":24,"available":15,"error":2,"overloaded":1,"rate_limited":3,"temp_unschedulable":1,"paused":1,"inactive":1,"stopped":1},
  "platforms":[{"platform":"anthropic","total":10,"available":6,"error":1,"overloaded":1,"rate_limited":2,"temp_unschedulable":0,"paused":0,"inactive":0,"stopped":1}],
  "groups":[{"group_id":3,"group_name":"高级组","platform":"anthropic","group_status":"active","total":4,"available":2,"error":1,"overloaded":0,"rate_limited":1,"temp_unschedulable":0,"paused":0,"inactive":0,"stopped":0,
             "shortage":{"is_short":true,"source":"alert_rule","rule_id":35,"metric_type":"group_available_ratio","operator":"<","threshold":60,"current":50}}],
  "accounts":[{"id":1,"name":"Claude-官方-01","platform":"anthropic","group_ids":[3,5],"state":"rate_limited","status":"active","schedulable":false,"error_message":"","rate_limit_reset_at":"2026-10-18T02:10:00Z","overload_until":null,"temp_unschedulable_until":null,"temp_unschedulable_reason":"","expires_at":null,"model_rate_limits":[{"model":"claude-opus-4","reset_at":"2026-10-18T02:00:00Z"}]}]}}
```

- `state` 每个账号只取一个，按顺序判定：status=inactive → inactive；status=error → error；overload_until>now → overloaded；rate_limit_reset_at>now → rate_limited；temp_unschedulable_until>now → temp_unschedulable；schedulable=false 或已过期且自动暂停 → paused；其余 → available。available 与 groupAccountAvailableSQL 完全一致。账号列表筛选用的 unschedulable 与这里的 paused 口径差异见 C14。
- `stopped` = 处于限时状态且 schedulable=false 的账号（App 的“已停止调度”标记），同时计入对应的限时档。
- 一个账号属于多个分组时计入每个分组，分组之间不可相加。
- `shortage`：分组上有已启用的 group_available_ratio / group_available_accounts 规则时，按规则的 operator / threshold 判定（source=alert_rule）；没有规则时，available < total × default_min_ratio 或 available=0 即为不足（source=default，默认阈值见附录 C Q11）。
- `include_accounts=true` 才返回 accounts。错误：400 `INVALID_GROUP_FILTER`；不返回 OPS_DISABLED，与运维开关无关。
- 可选（P2）：ops/account-availability 只增字段（group / platform 级 overloaded_count、temp_unschedulable_count、paused_count、inactive_count；账号级 group_ids、schedulable、temp_unschedulable_reason），现有字段语义不变。

**实现提示**：
- handler：`handler/admin/account_status_summary_handler.go`，挂成 AccountHandler 的方法；路由 `accounts.GET("/status-summary", …)` 加在 `server/routes/admin.go:406` 附近。gin v1.9.1（`go.mod:21`）的路由树里静态段优先于 `/:id`，与注册顺序无关（同 E05）。
- repository：新增 ListAccountsForStatusSummary，在 ListOpsAccountsForStats（`repository/account_repo.go:1187-1225`）基础上多选 expires_at、auto_pause_on_expired、temp_unschedulable_reason，用 `extra->'model_rate_limits'` 只取这一个 JSON 子键；工作区作用域照抄 :1201-1203 的 ScopeFromContextOrDeny。
- service：抽出纯函数 `AccountScheduleState(acc, now)`，口径与 `group_repo.go:980-997` 一致，新接口用它；以后 ops 可用性也改用它以统一口径。
- 分组名称与状态取 groupRepo.ListActive，停用分组另外补。告警规则直接调 opsRepo.ListAlertRules，不经过 OpsService，以免受 RequireMonitoringEnabled 限制；threshold 单位与评估器一致（`service/ops_alert_evaluator_service.go:463-489`）。
- 性能：整个请求只查一次账号表、不访问 Redis；可按作用域加 10 秒内存缓存（参考 snapshot-v2 的 newSnapshotCache）。
- vendor：这个路径落在 `/api/v1/admin/accounts` 的 GET 前缀规则下（permitAccountRead，`server/middleware/vendor_routes.go:117`），不改的话持 AccountManage 或 MonitorView 的 vendor 默认就能调。而上面的分组取自 groupRepo.ListActive（全站分组名与状态），shortage 读的是运维告警规则（运维为站长专属，`vendor_routes.go:96-97`），都没有按工作区收窄，vendor 会看到未授权分组的名称、状态和告警阈值。二选一：(a) 首版不对 vendor 开放（建议）：在 vendorDeniedRoutes 加 `{prefix:"/api/v1/admin/accounts/status-summary",methods:allMethods,exact:true}`；(b) 要开放：groups 只列 vendor 已授权的分组（复用 adminService 的 grantedGroupIDs / filterGroupsByScope，`service/admin_service.go:790-835`），vendor 请求的 shortage 一律按 source=default 判定、不读告警规则，账号照常按 ScopeFromContextOrDeny 收窄。两种都要在 `server/middleware/vendor_routes_guard_test.go` 补守卫测试。

**App 退路**：分组“可用 x/y”与受限数用 `GET /admin/groups/all`（或 `/admin/groups`）的 active_account_count / account_count / rate_limited_account_count；分档明细与逐账号状态分页拉 `GET /admin/accounts?lite=1&page_size=1000`（可加 group=）在客户端统计；全站计数用 dashboard/stats 的 error_accounts / ratelimit_accounts / overload_accounts；不足判定在运维开启时读 ops/alert-rules，否则按“不到一半”兜底；错误率、最近上游错误在运维关闭时显示“运维监控未开启”。

**验收**：`curl -H "Authorization: Bearer $T" "$BASE/api/v1/admin/accounts/status-summary?include_accounts=true"`
1. 关闭 ops_monitoring_enabled 后仍返回 200 且有数据。
2. 某分组的 available 与 `GET /admin/groups/all` 的 active_account_count 相等。
3. 把一个限流账号手动停调度：state 仍为 rate_limited，stopped+1。
4. 已过期且 auto_pause_on_expired 的账号计入 paused，不计入 available。
5. 分组配 group_available_ratio < 60 的规则：available/total=50% 时 shortage.is_short=true、source=alert_rule。
6. 跨两个分组的账号在两个分组里都计数。
7. 按 (a)：vendor JWT 调用返回 403；按 (b)：vendor 只看到本工作区的账号和已授权的分组，shortage.source 恒为 default。

---

#### D03 · ops/upstream-errors 补筛选参数 user_id、api_key_id、model（精确）、request_id（精确）、client_request_id 〔P1 · 加参数〕

**页面**：使用记录三段（用量明细 / 错误请求 / 上游错误）的筛选胶囊（从用户详情、模型对象页、筛选胶囊进入）；成功请求详情的上游尝试。

**背景**：日志要能从模型、用户、分组、账号任一对象下钻，三个分段用同一组条件；成功但经过重试的请求要显示上游尝试链。

**现状**：
- request-errors 已支持：ListRequestErrors 解析 model（精确）、request_id、user_id、api_key_id（`handler/admin/ops_handler.go:259-272`），还有 user_query、platform、group_id、account_id 等。设计稿注释“request-errors 只能用 user_query 筛用户”已过时（`html-preview/shared/data.jsx:418-424`）。
- upstream-errors 缺：ListUpstreamErrors 只解析 time、view、error_source、q、platform、group_id、account_id、resolved、status_codes（`ops_handler.go:466-560`）。
- 底层都支持：OpsErrorLogFilter 有 UserID、APIKeyID、Model、RequestID、ClientRequestID（`service/ops_models.go:103-140`），SQL 构建也支持（`repository/ops_repo.go:989-1025`），只是 handler 没解析。
- 重试成功的请求会写一行状态 < 400 的恢复行（`handler/ops_error_logger.go:1117-1130`），upstream-errors 会把它列出（IncludeRecoveredUpstream，`ops_handler.go:497`），但目前只能用 q 对 request_id 模糊匹配，默认时间窗只有 1 小时。

**建议改法**：`GET /api/v1/admin/ops/upstream-errors` 新增可选参数（与 request-errors 同名同义）：user_id（正整数）、api_key_id（正整数）、model（精确匹配 COALESCE(requested_model, model)）、request_id（精确）、client_request_id（精确）。响应结构不变；错误码 400 "Invalid user_id" / "Invalid api_key_id"，与 request-errors 一致。用法（成功请求的上游尝试）：`GET /api/v1/admin/ops/upstream-errors?request_id=<rid>&start_time=<created_at−10m>&end_time=<created_at+10m>`，再用 `GET /api/v1/admin/ops/upstream-errors/:id` 取 upstream_errors 链。

**实现提示**：在 `ops_handler.go:497-523` 之间照抄 :259-272 的解析代码（filter.Model、filter.RequestID、user_id / api_key_id），再加 `filter.ClientRequestID = c.Query("client_request_id")`；建议抽成 `parseOpsErrorIdentityFilters(c, filter)` 共用。索引已有：idx_ops_error_logs_request_id 与 client_request_id（`migrations/033_ops_monitoring_vnext.sql:494-497`）；user_id 与 model 在时间范围内走 created_at 索引。

**App 退路**：上游错误分段的“用户”“模型”胶囊置灰，注明“上游错误不能按模型、用户筛选，这里显示全部”；成功请求的重试链用 q=<request_id> 模糊搜索并扩大时间窗；错误请求分段直接用 user_id。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/ops/upstream-errors?user_id=12&model=claude-opus-4&time_range=24h"` 只返回该用户、该模型的行；request_id=<某个重试成功的 rid> 只返回 1 行且状态 < 400；user_id=abc 返回 400；不带新参数时结果不变。

---

#### D04 · 错误日志补写总耗时 duration_ms，错误请求与上游错误列表直接返回 duration_ms 与 time_to_first_token_ms 〔P1 · 加字段〕

**页面**：使用记录 · 错误请求、上游错误分段的行右侧“首字/耗时”；失败请求详情耗时条。

**背景**：用户已定日志行右侧第二行是“首字/耗时”，成功和失败的行都要显示（`DECISIONS.md:21-29,35`）。

**现状**：
1. 列表项 OpsErrorLog 没有任何耗时字段（`service/ops_models.go:25-77`），列表 SQL 也没选（`repository/ops_repo.go:235-279`）。
2. 详情 OpsErrorLogDetail 有 auth / routing / upstream / response 各阶段耗时和 time_to_first_token_ms，没有总耗时（`service/ops_models.go:79-101`）。
3. 更根本：ops_error_logs 表有 duration_ms 列（`migrations/033_ops_monitoring_vnext.sql:116`），插入语句根本不写它（`repository/ops_repo.go:19-61` 的列清单里没有），所以 ops/requests 的 error 行 duration_ms 恒为 null（`repository/ops_repo_request_details.go:120`），Web 请求明细按耗时排序对错误行无效。time_to_first_token_ms 是写了的（`ops_repo.go:56`；`handler/ops_error_logger.go:1670-1674`）。
4. 逐条取详情是 N+1；include_detail 只在 request-errors/:id/upstream-errors 上有，而且也是逐条查（`handler/admin/ops_handler.go:436-452`）。

**建议改法**：
1. 改行为：网关写错误日志（含重试成功的恢复行）时写入 duration_ms = 请求开始到写日志时的毫秒数。
2. 加字段：`GET /api/v1/admin/ops/request-errors`、`/ops/upstream-errors`、`/ops/errors` 的列表项增加 `"duration_ms":3200,"time_to_first_token_ms":1200`（都可为 null；历史行为 null）。ops/requests 的 error 行 duration_ms 也随之有值。只增不改，Web 不受影响。

**实现提示**：insertOpsErrorLogSQL（`repository/ops_repo.go:19-61`）加 duration_ms 列与参数；OpsInsertErrorLogInput（`service/ops_port.go:110-120` 附近）加 `DurationMs *int64`；在 `handler/ops_error_logger.go:1670` 一带调 `service.GatewayRequestTimingFromContext(c.Request.Context())`，用 `Snapshot().TotalMS` 填值，拿不到计时就用请求开始时间计算。ListErrorLogs 的 SELECT（`ops_repo.go:235-279`）加 `e.duration_ms, e.time_to_first_token_ms`，OpsErrorLog 加两个 `*int64`。batch insert 路径（如有）同步改。列已存在，不需要迁移。

**App 退路**：列表行“首字/耗时”显示“—”；失败请求详情用各阶段耗时之和（auth + routing + upstream + response）作近似总耗时，首字取 time_to_first_token_ms；也可以用 ops/requests?kind=error 拿列表级 first_token_ms，但总耗时同样是 null。

**验收**：制造一条上游 502 的请求：ops/request-errors 中该行 duration_ms 与网关日志 timing.TotalMS 接近；ops/requests?kind=error 同一请求 duration_ms 不再是 null；Web 错误列表渲染正常。

---

#### D05 · 管理端使用记录每条直接返回 account_cost（账号成本），由服务端统一计算 〔P1 · 加字段〕

**页面**：成功请求详情（实际扣费 / 账号成本 / 标准）；请求记录列表与详情（成本、扣费与成本差额）。

**背景**：每条请求都要显示账号成本，口径要与账号今日统计、利润一致（利润 = 实际扣费 − 账号成本）。

**现状**：
1. AdminUsageLog 只给原料：account_stats_cost、account_rate_multiplier（nil 按 1.0）、total_cost、provider_cost_recorded（`handler/dto/types.go:670-673,684-718`；映射 `handler/dto/mappers.go:765-786`），没有算好的 account_cost。
2. 后端各处的统一公式：provider_cost_recorded 为真时 COALESCE(account_stats_cost, total_cost) × COALESCE(account_rate_multiplier, 1)，否则 0（`repository/usage_log_repo_stats.go:283`；`repository/usage_log_repo_trend.go:500`；`repository/usage_log_repo_dashboard.go:295`）。
3. usage_logs 表没有 account_cost 列；该列只在 usage_dashboard_hourly / usage_dashboard_daily 聚合表里（`migrations/107_add_account_cost_to_dashboard_tables.sql:1-5`）。
4. 现有 App 没处理 provider_cost_recorded=false，会多算（`sub2-mobile-native/Sources/Sub2Core/RequestLogs.swift:133-135`）。

**建议改法**：`GET /api/v1/admin/usage` 的每条记录（以及将来的单条详情）增加 `"account_cost": 0.5395`（float，provider_cost_recorded=false 时为 0）。现有字段全部保留，Web 不受影响。

**实现提示**：service 的 UsageLog 加方法 `AccountCost() float64` 实现上述公式，在 `handler/dto/mappers.go:771-785` 的 UsageLogFromServiceAdmin 里填 AccountCost。建议把三处 SQL 片段的口径写在同一个常量旁注释，以后改公式不漏改。不需要迁移，没有性能影响。

**App 退路**：客户端复刻公式：`provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0`；现有 App 要补上 provider_cost_recorded 的判断。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/usage?page_size=50"`：Σ account_cost 与同时段 dashboard 的 total_account_cost 一致；probe_coalesced 的跟随请求（provider_cost_recorded=false）account_cost=0。

---

#### D06 · 告警事件附带规则摘要（metric_type、operator、threshold、window_minutes）、分组名、手动解决人，并新增告警计数接口 〔P2 · 加字段〕

**页面**：监控 · 告警列表行（“分组 · 标准组 · 错误率 > 5%（5 分钟）”）；告警详情“规则”区（条件、窗口、级别、触发、结束）；已解决告警“昨天 22:10 · 由 admin 手动解决”。

**背景**：每条告警要显示条件、阈值单位（% 还是个数）、窗口、作用范围名称，手动解决的还要显示处理人；概况和 Tab 上要显示“告警中 N 条”。

**现状**：
1. OpsAlertEvent 只有 rule_id、severity、status、title（"P1: 规则名"）、description、metric_value、threshold_value、dimensions{platform, group_id}、fired_at、resolved_at、email_sent（`service/ops_alert_models.go:41-60`）。
2. description 是半结构化文本，形如 `"error_rate > 5.00 (current 5.20) over last 5m (platform=… group_id=…)"`（`service/ops_alert_evaluator_service.go:654-676`），可以显示但不宜解析。
3. 表里没有 resolved_by 列（`migrations/033_ops_monitoring_vnext.sql:293-312`）；`PUT /admin/ops/alert-events/:id/status` 只更新 status 与 resolved_at（`handler/admin/ops_alerts_handler.go:416-462`；`repository/ops_repo_alerts.go:594-613`），不记录是谁处理的。对比：错误日志有 resolved_by_user_name（`service/ops_models.go:45-48`）。
4. 列表返回裸数组，游标分页，limit 最大 500（`ops_alerts_handler.go:517-610`；`ops_repo_alerts.go:328-334`），没有总数。
5. 规则在事件触发后被编辑，客户端联表看到的是当前规则；规则被删除后事件上就拿不到 metric_type。

**建议改法**：
1. 加字段：`GET /api/v1/admin/ops/alert-events` 与 `/alert-events/:id` 每条事件增加：

```json
{"rule":{"id":41,"name":"标准组错误率","metric_type":"error_rate","operator":">","threshold":5,"window_minutes":5,"sustained_minutes":5,"deleted":false},
 "group_name":"标准组","resolved_by_user_id":1,"resolved_by_user_name":"admin"}
```

   resolved_by_* 只有 manual_resolved 才有，其他为 null。静默信息见 D01 的 silence 字段。
2. 新接口：`GET /api/v1/admin/ops/alert-events/counts?platform=&group_id=` → `{"firing":2,"by_severity":{"P0":0,"P1":1,"P2":1,"P3":0}}`。现有列表保持裸数组，不改结构。

**实现提示**：迁移 `ALTER TABLE ops_alert_events ADD COLUMN IF NOT EXISTS resolved_by_user_id BIGINT, ADD COLUMN IF NOT EXISTS rule_snapshot JSONB`。评估器创建事件时（`ops_alert_evaluator_service.go:276-288`）把 metric_type、operator、threshold、window_minutes、sustained_minutes、name 写进 rule_snapshot。读取：ListAlertEvents（`ops_repo_alerts.go:320`）与 GetAlertEventByID（:416）LEFT JOIN ops_alert_rules，结果取 COALESCE(rule_snapshot, 当前规则)；LEFT JOIN groups ON g.id = (e.dimensions->>'group_id')::bigint；LEFT JOIN users 取解决人名。UpdateAlertEventStatus：handler 从 middleware.GetAuthSubjectFromContext 取 UserID 传到 repo 写入；评估器自动 resolved 时留空。counts 用 `SELECT severity, COUNT(*) … WHERE status='firing' GROUP BY severity`，已有索引 idx_ops_alert_events_rule_status。

**App 退路**：另拉 ops/alert-rules（数量少、可缓存）与 groups/all，在客户端拼出条件、单位、窗口和分组名；规则已删除时退回 description 文本；“由 admin 手动解决”拿不到，只显示“已手动解决”；告警中条数用 `alert-events?status=firing&limit=500` 再数。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/ops/alert-events?limit=20"`：分组规则的事件带 group_name，rule.operator / window_minutes 与规则一致；修改规则阈值后旧事件的 rule.threshold 仍是触发时的值；PUT status=manual_resolved 后 resolved_by_user_name=当前管理员，评估器自动恢复的为 null；counts.firing 等于 status=firing 的事件数；Web 告警卡渲染不受影响。

---

#### D07 · 修复预置的 P95 / P99 延迟告警规则：补上评估支持，或用迁移停用 〔P2 · 改行为〕

**页面**：监控 · 告警（App 只认后端的 16 种 metric_type）。

**背景**：两条预置规则启用且开了邮件通知，但永远不会触发，管理员会误以为站点有延迟告警。

**现状**：
1. 迁移预置了“P99延迟过高”（p99_latency_ms > 3000）与“P95延迟过高”（p95_latency_ms > 2000），都是 enabled=true、notify_email=true（`migrations/033_ops_monitoring_vnext.sql:643-663`），后续迁移没再处理。
2. 评估器 computeRuleMetric 的 switch 里没有这两种指标，overview 分支的 default 返回 false（`service/ops_alert_evaluator_service.go:600-617`），评估循环随后 resetRuleState 并跳过（:228-231）。
3. 合法指标白名单只有 16 种（`handler/admin/ops_alerts_handler.go:19-36`），UpdateAlertRule 同样走白名单（:331-335 → :128-130），所以这两条规则在 Web 上连编辑或停用都返回 400，只能删除。
4. 数据现成：overview 里有 duration.p95_ms / p99_ms（`service/ops_dashboard_models.go:78`），评估器本来就用 raw 模式取 overview（`ops_alert_evaluator_service.go:586-592`）。

**建议改法**（推荐 A，取舍见附录 C Q10）：
- 方案 A 补支持：p95_latency_ms、p99_latency_ms 加进 validOpsAlertMetricTypes（单位 ms，不属于百分比）；computeRuleMetric 的 overview 分支加两个 case，返回 overview.Duration.P95 / P99，值为 nil（没有样本或延迟查询超时降级）时返回 false；Web 规则编辑器同步加这两个选项。
- 方案 B 停用：新增迁移 `UPDATE ops_alert_rules SET enabled = false, updated_at = NOW() WHERE metric_type IN ('p95_latency_ms','p99_latency_ms');`，并让 UpdateAlertRule 允许“未改动 metric_type 的旧规则”通过校验，至少能停用。
两种方案都不改接口结构。

**实现提示**：方案 A 改 `ops_alerts_handler.go:19-36`（白名单）与 isPercentOrRateMetric（:89-103，不加入）、`ops_alert_evaluator_service.go:600-617`（加 case）。overview 的延迟查询有 opsRawLatencyQueryTimeout，超时时 duration 为空（`repository/ops_repo_dashboard.go:105-117`），这时视为“不可评估”，不能当 0。Web 在 `frontend/src/views/admin/ops/components/OpsAlertRulesCard.vue` 的 metricDefinitions 加两项。方案 B 的迁移编号见 1.3（origin/main 当前最大 246，从 247 起）。

**App 退路**：遇到 16 种以外的 metric_type 时，规则显示“不受支持（不会触发）”，不提供编辑。

**验收**：方案 A：测试环境制造 P99 > 3s 的流量，告警评估心跳的 evaluated 数增加并产生事件；PUT 这两条规则改阈值返回 200。方案 B：迁移后 `GET /api/v1/admin/ops/alert-rules` 中这两条 enabled=false。

---

#### D08 · 服务器区补数据：CPU / 内存近期历史接口；任务心跳加预期间隔与 stale 判定；入口拒绝列表加请求数合计 〔P2 · 新接口〕

**页面**：监控 · 概况 · 服务器区（仅管理员）：CPU、内存数值加小折线，后台任务心跳，日志采集，入口拒绝。

**背景**：管理员要能看出服务器最近是否异常、哪个后台任务“N 分钟没成功，需要看一下”，以及近 1 小时入口拒绝了多少次。

**现状**：
1. overview 的 system_metrics 只是最新一条快照（`service/ops_dashboard.go:46-59`；`repository/ops_repo_metrics.go:152-189` 用 ORDER BY created_at DESC LIMIT 1）。ops_system_metrics 每分钟一行（window_minutes=1，platform、group_id 为 NULL），但没有历史读取接口（`server/routes/admin.go:208-295`）。
2. job_heartbeats 只有 job_name、last_run_at、last_success_at、last_error_at、last_error、last_duration_ms、last_result（`service/ops_port.go:293-304`），没有预期间隔与 stale 标记。各任务周期分散在代码里：指标采集 60s～1h 可配（`service/ops_metrics_collector.go:27-28,130`），告警评估默认 60s（`service/ops_alert_evaluator_service.go:130-132`），小时预聚合 10 分钟、天预聚合 1 小时（`service/ops_aggregation_service.go:22-23`），清理按 cron 默认 `"0 2 * * *"`（`config/config.go:2319`），定时报告每分钟 tick（`service/ops_scheduled_report_service.go:26`）。健康分里另有写死的“超过 15 分钟没成功算失败”（`service/ops_health_score.go:116-125`），每日一次的任务按这条规则大部分时间都被判失败。
3. ingress-rejections 返回聚合行，total 是行数不是请求数（`service/ops_ingress_reject.go:21-53`；`handler/admin/ops_ingress_reject_handler.go:31-101`），“入口拒绝 N 次（1 小时）”要翻页把 request_count 加起来。
4. 日志采集已有 system-logs/health 的 queue_depth、avg_write_delay_ms（`service/ops_system_log_sink.go:18-26`），够用。

**建议改法**（全部只增，Web 不受影响）：
1. 新接口 `GET /api/v1/admin/ops/system-metrics/history?time_range=1h&max_points=60`（time_range 可选 5m / 30m / 1h / 6h / 24h，也支持 start_time + end_time）：

```json
{"window_minutes":1,"bucket_seconds":60,"points":[{"created_at":"2026-10-18T01:40:00Z","cpu_usage_percent":38.2,"memory_usage_percent":61.0,"concurrency_queue_depth":0,"goroutine_count":412,"db_ok":true,"redis_ok":true}]}
```

   点数超过 max_points 时按桶取平均。
2. overview.job_heartbeats[] 每项增加 `"expected_interval_seconds":60,"next_expected_at":"…","status":"ok"|"failing"|"stale"|"unknown"`：最近一次错误晚于最近一次成功 → failing；now − last_success_at > 2 × 预期间隔 + 宽限 → stale；cron 类任务按上一次应运行时间判断。
3. `GET /api/v1/admin/ops/ingress-rejections` 的响应增加 `"request_count_total":3`（与列表同一组筛选），可选 `"by_reason":[{"reason":"invalid_api_key","request_count":2}]`。

**实现提示**：历史接口在 `repository/ops_repo_metrics.go` 新增 ListSystemMetricsHistory(start, end, bucketSeconds)：`SELECT … FROM ops_system_metrics WHERE window_minutes = 1 AND platform IS NULL AND group_id IS NULL AND created_at BETWEEN …`，按 floor(epoch / bucket) 聚合；数据保留期受 minute_metrics_retention_days 限制；handler 放 `ops_dashboard_handler.go`，路由挂 ops 组，走 RequireMonitoringEnabled。心跳：新建 `service/ops_job_registry.go`，登记 job_name → 间隔函数（metrics collector 与 alert evaluator 复用各自 getInterval；cleanup 用 opsCleanupCronParser 解析当前 schedule），在 `service/ops_dashboard.go:62-66` 取到心跳后补字段；顺便把 `ops_health_score.go:116-125` 的 15 分钟规则改成按登记的间隔判断（可选）。入口拒绝：ListIngressRejects（`repository/ops_ingress_reject_repo.go:73`）在同一 where 条件下补一条 `SELECT SUM(request_count)`。

**App 退路**：小折线只能在前台轮询 overview 时自己攒点，进页面时只有当前值；心跳状态由客户端写死各任务周期（清理、每日预聚合按天判断）；入口拒绝数由客户端翻页累加 request_count。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/ops/system-metrics/history?time_range=1h"` 返回约 60 个点，最后一个点与 overview.system_metrics 一致；停掉 Redis 让指标采集失败，该任务 status=failing，5 分钟无成功 → stale；凌晨的 ops_cleanup 在白天为 ok 而不是 stale；`ingress-rejections?time_range=1h` 的 request_count_total 等于各行 request_count 之和。

---

#### D09 · 运维监控开关：Web 设置页补回开关；后端新增 `GET/PUT /api/v1/admin/ops/monitoring-status`，区分“配置文件关闭”和“设置关闭” 〔P2 · 新接口〕

**页面**：统计分析运行类图表、首页 RPM / TPM 与错误率、监控 Tab 的“运维监控未开启”提示。

**背景**：运维监控关闭时，App 要告诉管理员去哪里开启，最好在 App 里直接开启。

**现状**：
1. Web 没有这个开关：SettingsView 只在表单默认值里有 ops_* 字段（`frontend/src/views/admin/SettingsView.vue:10074-10077`），保存时的 payload 不带（:11615 起）；i18n 文案 admin.settings.opsMonitoring.* 现成（`frontend/src/i18n/locales/zh/admin/settings.ts:1023-1038`）但没有组件引用。运维页在监控关闭时跳到 `/admin/settings`（`frontend/src/views/admin/ops/OpsDashboard.vue:810-813`），那里没有开关，用户走进死路。
2. 后端已经能写：`PUT /api/v1/admin/settings` 接受 ops_monitoring_enabled 与 ops_realtime_monitoring_enabled，两者都是指针，省略的字段保持现值（`handler/admin/setting_handler_update.go:231-235,481-489`），写入后立即 SetMonitoringEnabled 生效（:2159-2161）。
3. 配置文件 ops.enabled=false 是硬开关，API 打不开（`service/ops_service.go:153-165`）；`GET /admin/settings` 返回的 ops_monitoring_enabled = 硬开关 && 设置值（`handler/admin/setting_handler.go:125,293`），客户端分不清是哪个关的。
4. 监控关闭时接口统一 404 OPS_DISABLED（`service/ops_service.go:19`）。

**建议改法**：
1. Web：SettingsView 加回“运维监控”卡片（启用、实时监控、默认查询模式、采集频率），直接用现有 i18n；保存时 payload 带上 ops_* 四个字段。
2. 新接口（不经过 RequireMonitoringEnabled）：
   - `GET /api/v1/admin/ops/monitoring-status` → `{"config_enabled":true,"monitoring_enabled":false,"realtime_monitoring_enabled":true,"effective":false,"disabled_reason":"setting_off"}`，disabled_reason 取 `config_off` / `setting_off` / null。
   - `PUT /api/v1/admin/ops/monitoring-status`，body `{"monitoring_enabled":true,"realtime_monitoring_enabled":true}`（都可选）→ 返回与 GET 相同的结构。
   - 错误码：409 `OPS_CONFIG_DISABLED`（配置文件关闭，API 打不开）；403（权限与设置页一致）。

**实现提示**：新 handler 放 `handler/admin/ops_settings_handler.go` 一类文件，路由挂 ops 组（`server/routes/admin.go:208` 起）。读：`s.cfg.Ops.Enabled`、settingRepo 的 SettingKeyOpsMonitoringEnabled 与 SettingKeyOpsRealtimeMonitoringEnabled（读法参考 `service/ops_realtime.go:13-36`）。写：settingRepo.SetMultiple 只写这两个 key，再调 opsService.SetMonitoringEnabled；写审计日志，可复用 `setting_handler_audit.go:392` 的字段名。A02 的 features 可同时返回 disabled_reason。

**App 退路**：`GET /admin/settings` 的 ops_monitoring_enabled=false 时，App 直接 `PUT /api/v1/admin/settings` 只带 `{"ops_monitoring_enabled":true}`（省略的字段保持不变）；之后仍为 false 说明配置文件里 ops.enabled=false，提示“需要在服务器配置中启用运维监控”，不要提示 Web 菜单路径。

**验收**：关掉设置项后 GET monitoring-status 返回 disabled_reason=setting_off，PUT 打开后 effective=true，ops/dashboard/overview 恢复 200；配置文件 ops.enabled=false 时 PUT 返回 409；Web 设置页能看到开关并能保存。

---

#### D10 · 上游重试链：每次尝试记录开始时间和耗时，并新增按 request_id 合并整条链的接口（含最终成功的那次） 〔P2 · 加字段〕

**页面**：失败请求 / 上游错误详情的“上游尝试”分区（1 Claude-官方-03 429 · 0.4s → 2 Claude-官方-01 200 · 9.8s，返回客户端 200）。

**背景**：第 1 轮已定：失败请求的二级详情要有上游重试链，看清每次换到了哪个账号、返回了什么、花了多久、最后哪一次成功（`DECISIONS.md:29`）。

**现状**：
1. OpsUpstreamErrorEvent 每次尝试只有 at_unix_ms（出错时刻）、platform、account_id / account_name、proxy、upstream_status_code、upstream_request_id、kind、stage、message 等，没有开始时间和耗时（`service/ops_upstream_context.go:382-431`）。
2. 网关其实在计时：TraceGatewayUpstream 对每次上游分发都有 started 时间（`service/gateway_request_timing.go:171-215`，调用点 `repository/http_upstream.go:276,376`），只做请求级汇总，没写进事件。
3. 链里只有失败的尝试。request-errors/:id/upstream-errors 按 request_id 关联 provider 行（`handler/admin/ops_handler.go:358-455`），要求先有一条 request-error 的 id；重试成功的那次只在 usage_logs 里，要另按 `admin/usage?request_id=` 查。

**建议改法**：
1. 加字段：OpsUpstreamErrorEvent 增加 `"started_at_unix_ms":1760751660000,"duration_ms":412`（只增 JSON 字段，存在 upstream_errors JSONB 里，不需要迁移；历史数据没有）。
2. 新接口 `GET /api/v1/admin/ops/requests/:request_id/attempts`（可选 `around=<RFC3339>` 收窄时间范围）：

```json
{"request_id":"req_5f3a…","client_status_code":200,
 "attempts":[{"index":1,"account_id":3,"account_name":"Claude-官方-03","upstream_status_code":429,"kind":"failover","started_at":"…","duration_ms":400,"outcome":"failed"},
             {"index":2,"account_id":1,"account_name":"Claude-官方-01","upstream_status_code":200,"started_at":"…","duration_ms":9800,"first_token_ms":1400,"outcome":"success","usage_id":9018}],
 "error_log_ids":[8812]}
```

   错误码：404 `OPS_REQUEST_NOT_FOUND`；404 OPS_DISABLED。

**实现提示**：在 GatewayRequestTiming 里保存当前这次尝试的开始时间（TraceGatewayUpstream 里赋值）；appendOpsUpstreamError（`service/ops_upstream_context.go:444` 起）补 StartedAtUnixMs，并算 DurationMs = AtUnixMs − StartedAtUnixMs，这样 39 个调用点都不用改。合并接口：查 `ops_error_logs WHERE request_id = $1`（走 idx_ops_error_logs_request_id）解析 upstream_errors；再查 `usage_logs WHERE request_id = $1`（走 (request_id, api_key_id) 索引，`migrations/027_usage_billing_consistency.sql:33`），成功那次作为最后一个 attempt，按时间排序。权限照抄 usage 列表的工作区作用域（appendUsageAccountScopeCondition）。

**App 退路**：先调 request-errors/:id/upstream-errors（或上游错误详情的 upstream_errors）拿失败链，再用 `admin/usage?request_id=` 取成功那次。耗时用估算：第一次 ≈ at1 −（usage.created_at − duration_ms），后续 ≈ 相邻 at 之差（会把重试等待也算进去），显示为“约 0.4s”。

**验收**：测试环境构造“第 1 个账号 429、第 2 个账号 200”的请求：attempts 有 2 项，第 1 项 duration_ms ≈ 上游实际响应时间，第 2 项 outcome=success、usage_id 与 admin/usage 一致；旧数据仍可读，只是没有 duration_ms。

---

### E 用户与 API Key

#### E01 · 新增管理员替用户新建 / 修改（含停用、启用）/ 删除 API Key 的接口 〔P0 · 新接口〕

**页面**：编辑用户 · Key 与限额：可展开 Key 卡片里的停用、删除，列表末尾“新建 Key”；用户详情 Key 摘要。

**背景**：第 3 轮选“要，先保留占位”（`DECISIONS.md:99`）。后端加好后，删除放在 ⋯ 最后并要确认，停用的回执可撤销。Key 卡片已经在展示额度、有效期、IP 限制、速率限制，后端支持后可以原处直接改。现在画的是“需后端新增”虚线占位（`html-preview/layouts/main/v-user-edit.jsx:25-27,410-416`）。

**现状**：
1. 管理端只注册了 `PUT /api/v1/admin/api-keys/:id`（`server/routes/admin.go:201-206`），请求体只有 group_id 与 reset_rate_limit_usage（`handler/admin/apikey_handler.go:25-29`），handler 只调 AdminResetAPIKeyRateLimitUsage 与 AdminUpdateAPIKeyGroupID（:46-62；`service/admin_group.go:1528-1655`）。
2. `GET /api/v1/admin/users/:id/api-keys` 只读（`server/routes/admin.go:327` 一带；`handler/admin/user_handler.go:467-490`）。
3. 新建、改状态、删除只在用户侧 `/api/v1/keys`（`server/routes/user.go:78-82`），都以 JWT 主体为所有者：Create 要过 canUserBindGroup 与创建频率限制（`service/api_key_service.go:444-468,492-598`）；Update、Delete 不是本人就返回 ErrInsufficientPerms（:804、955）。后端没有 impersonate 或代登录路由。
4. 管理端 handler 只注入了 AdminService（`handler/admin/apikey_handler.go:14-23`；`cmd/server/wire_gen.go:273`），拿不到 APIKeyService 的 GenerateKey、认证缓存失效和 lastUsedTouchL1。Web 管理端同样没有这些操作（`frontend/src/api/admin/apiKeys.ts:22-31` 只有 updateApiKeyGroup）。
5. sub2-mobile-backend 里这些文件与 sub2 逐字节相同。

**建议改法**（只新增，Web 不受影响）：

① 新建：`POST /api/v1/admin/users/:id/api-keys`，可选请求头 Idempotency-Key（App 必带）。

```json
{"name":"脚本","group_id":3,"quota":50,"expires_in_days":30,"ip_whitelist":["198.51.100.0/24"],"ip_blacklist":[],"rate_limit_5h":5,"rate_limit_1d":20,"rate_limit_7d":0}
```

字段语义同用户侧 CreateAPIKeyRequest，0 表示不限；不开放 custom_key。响应：

```json
{"code":0,"message":"success","data":{"api_key":{"id":4099,"name":"脚本","key":"sk-…完整明文…","key_masked":"sk-…3f9a","status":"active","group_id":3},"auto_granted_group_access":true,"granted_group_id":3,"granted_group_name":"Claude Code 组"}}
```

分组规则与现有 `PUT /admin/api-keys/:id` 一致：分组必须 active；订阅分组要求用户有有效订阅；用户没有的专属标准分组在同一事务里自动授予。

② 修改（含停用、启用）：扩展现有 `PUT /api/v1/admin/api-keys/:id`，新增字段全部可选，null 表示不改（Web 现在只发 group_id，行为不变）：

```json
{"name":"脚本-新","status":"inactive","quota":100,"reset_quota":false,"expires_at":"2026-12-31T23:59:59+08:00","ip_whitelist":[],"ip_blacklist":["203.0.113.9"],"rate_limit_5h":0,"rate_limit_1d":30,"rate_limit_7d":0}
```

status 只接受 active 或 inactive（与用户侧一致，见 E06）；expires_at 传 `""` 表示清除有效期。响应保持现有结构 `{api_key, auto_granted_group_access, granted_group_id, granted_group_name}`，另增 `"previous":{"status":"active","name":"脚本"}`（本次改动字段的旧值），回执“撤销”时原样写回；停用的撤销就是再发 `{"status":"active"}`。

③ 删除：`DELETE /api/v1/admin/api-keys/:id` → `{"code":0,"data":{"id":4087,"deleted":true}}`；重复删除也返回成功（仓储层本来就幂等）。删除不能撤销。

④（可选）`GET /api/v1/admin/api-keys/:id`：读单个 Key，方便操作后刷新卡片。

错误码（reason）：400 `VALIDATION`、`INVALID_IP_PATTERN`、`GROUP_NOT_ACTIVE`、`SUBSCRIPTION_REQUIRED`；404 `USER_NOT_FOUND`、`GROUP_NOT_FOUND`、`API_KEY_NOT_FOUND`；403 `API_KEY_COUNT_EXCEEDED`（仍遵守 api_key_create.max_active_per_user）；409 `IDEMPOTENCY_KEY_CONFLICT`、`IDEMPOTENCY_IN_PROGRESS`。权限只给 admin：vendor 白名单里没有 `/admin/users` 与 `/admin/api-keys`，默认 403，`vendor_routes.go` 不用改。

**实现提示**：
- 路由：`registerAdminAPIKeyRoutes`（`server/routes/admin.go:201-206`）加 `DELETE /:id`（可选 `GET /:id`）；registerUserManagementRoutes（:317 起）加 `users.POST("/:id/api-keys", h.Admin.APIKey.CreateForUser)`。
- handler：AdminAPIKeyHandler 增加注入 `*service.APIKeyService`，改 `handler/wire.go:300` 的 NewAdminAPIKeyHandler 并重新生成 `cmd/server/wire_gen.go`。扩展 AdminUpdateAPIKeyGroupRequest 的字段，数值校验复用 `handler/api_key_handler.go:67-102`。Create 用 `executeAdminOptionalIdempotentJSON(c, "admin.api_keys.create", …)`（`handler/admin/idempotency_helper.go:108`）。
- service：APIKeyService 新增 AdminCreate、AdminUpdate、AdminDelete。把 Update 里的字段应用与自动复活逻辑（`service/api_key_service.go:821-918`）抽成 applyAPIKeyUpdate，用户和管理员两条路径共用；管理员路径去掉所有者校验和 canUserBindGroup，改用 AdminUpdateAPIKeyGroupID 的分组规则（含专属分组授予事务，`service/admin_group.go:1555-1611`）；名称同样 html.EscapeString（`api_key_service.go:572`）。Create 复用 GenerateKey 与 checkAPIKeyCreateLimits 的数量上限，跳过每小时创建计数，也不给用户计数加 1。Delete 复用 DeleteWithAudit、InvalidateAuthCacheByKey、lastUsedTouchL1.Delete（`api_key_service.go:948-970`）。
- 缓存：每次变更都调 InvalidateAuthCacheByKey；改了 IP 规则要调 compileAPIKeyIPRules。
- 审计：`/admin` 已挂 auditLog（`server/routes/admin.go:35`），key、custom_key 在 RedactAuditBody 里按键名脱敏（`service/audit_log.go:139-144`）。
- 幂等记录：create 的响应（含完整 Key）会写进 idempotency_records.response_body（`repository/idempotency_repo.go:180`）；用户侧 user.api_keys.create 现在也是这样，且 api_keys.key 本身就是明文存储，TTL 内可以接受。完整 Key 只在 create 响应里出现，其余响应配合 E03 返回掩码。

**App 退路**：保持虚线占位“需后端新增”，点按只弹说明不执行（`v-user-edit.jsx:410-416`）。需要真的新建、停用、删除时，只能请用户本人登录 Web 用户端去做（Web 管理端也没有这些入口）。

**验收**：
1. `curl -X POST "$BASE/api/v1/admin/users/1/api-keys" -H "Authorization: Bearer $T" -H 'Idempotency-Key: k1' -d '{"name":"脚本","group_id":3,"quota":50}'`：data.api_key.key 是完整 sk-…；同一 Idempotency-Key 重发返回同一个 Key，不新建。
2. `PUT /api/v1/admin/api-keys/4087 -d '{"status":"inactive"}'`：返回 status=inactive、previous.status=active；随后用该 Key 调网关返回 401 API_KEY_DISABLED；再 PUT `{"status":"active"}` 恢复。
3. PUT 只带 `{"group_id":3}`（Web 现有请求）：响应字段与改前一致。
4. `DELETE /api/v1/admin/api-keys/4087` 返回 deleted:true；再删一次仍 200；`GET users/1/api-keys` 里不再有这个 Key。
5. vendor 身份调用以上任一接口返回 403。
6. 单测覆盖：专属分组自动授予的事务回滚、订阅分组被拒、数量上限、删除后缓存失效。

---

#### E02 · （安全）vendor 通过使用记录拿到终端用户 API Key 明文与用户资料 〔P0 · 安全修复〕

**页面**：无 App 依赖（App 只走 admin 身份）；这是核实接口时发现的既有漏洞。

**背景**：vendor 是代运营的外部工作区，按设计“用户管理、订阅为站长专属”（`server/middleware/vendor_routes.go:95-97` 的注释）。

**现状**：
- vendor 白名单放行 `GET /api/v1/admin/usage`（只要开了监控档，`server/middleware/vendor_routes.go:146`）；VendorScope 只按账号收窄行（`server/middleware/vendor_scope.go:198-211`；`repository/usage_scope_sql.go:55-70`）。
- 每一行都经 hydrateUsageLogAssociations 加载整行 api_keys 和 users（`repository/usage_log_repo_query.go:279-297,385-397`），再由 UsageLogFromServiceAdmin 输出（`handler/admin/usage_handler.go:212-215`）：`User: UserFromServiceShallow(l.User)`（含 email、balance 等）、`APIKey: APIKeyFromService(l.APIKey)`（含完整 key）（`handler/dto/mappers.go:746-747`）。usage handler 里没有任何 vendor 脱敏。
- Web 管理端使用记录只读 api_key.name（`frontend/src/components/admin/usage/UsageTable.vue:50`），不读 api_key.key。

**建议改法**（响应结构不变，只清空值）：
1. `GET /api/v1/admin/usage`（以及其他对 vendor 开放、内嵌 user / api_key 的接口）在 vendor 作用域下：api_key 只保留 id、name、key_masked（E03），key 返回 `""`；user 只保留 id 与打码邮箱（如 `a***@example.com`），balance、total_recharged、balance_notify_extra_emails 等置零值或省略。
2. 建议同时把 admin 使用记录内嵌的 `api_key.key` 对所有身份默认置空（Web 不读），与 E03 第 ④ 点一致。

**实现提示**：在 `handler/admin/usage_handler.go:212-215` 组装 out 后判断 `service.ScopeFromContext(ctx).IsVendor()`，或在 dto 层新增 `UsageLogFromServiceVendor`。在 `server/middleware/vendor_routes_usage_scope_test.go` 补一条用例断言 vendor 拿不到 key 明文与余额。顺带排查其他 vendor 白名单路由里是否有内嵌 dto.User / dto.APIKey 的响应。

**App 退路**：不适用。

**验收**：vendor 身份 `curl -s -H "Authorization: Bearer $VENDOR_T" "$BASE/api/v1/admin/usage?page_size=5" | jq '.data.items[]|{k:.api_key.key,b:.user.balance,e:.user.email}'`：key 为 `""`，余额不出现或为 0，邮箱已打码；admin 身份下 Web 使用记录页显示不变。

---

#### E03 · （安全）管理端 Key 列表与使用记录可以只返回掩码：新增 key_masked、key_view=masked 参数和需 step-up 的揭示接口 〔P1 · 加参数〕

**页面**：用户详情 Key 摘要、编辑用户 Key 卡片、分组 API 密钥页；使用记录列表、请求详情“关联”区（Key 名称 + 掩码）。

**背景**：手机端只显示 Key 名称和 `sk-…xxxx`，不需要把用户的完整密钥下载到手机（`html-preview/layouts/main/00-core.jsx:1001-1004` 的关联区也只显示 label 与 masked）。

**现状**：
1. dto.APIKey.Key 原样输出完整密钥（`handler/dto/types.go:59`；`handler/dto/mappers.go:80-87`）。
2. 返回完整密钥的接口：`GET /admin/users/:id/api-keys`（`handler/admin/user_handler.go:467-490`）、`GET /admin/groups/:id/api-keys`（`handler/admin/group_handler.go:1030-1053`）、`PUT /admin/api-keys/:id`（`handler/admin/apikey_handler.go:64-75`）。
3. 使用记录每一行都带完整 Key（见 E02 的现状）。
4. Web 依赖：UserApiKeysModal 用 key.key 自己截取显示（`frontend/src/components/admin/user/UserApiKeysModal.vue:17`），所以不能直接把 key 改成掩码；使用记录只读 api_key.name（`frontend/src/components/admin/usage/UsageTable.vue:50`、`frontend/src/views/admin/UsageView.vue:644`），全前端没有读 api_key.key 的地方。
5. 现有原生 App 也是先收到完整 Key 再本地遮盖（`sub2-mobile-native/NativeApp/Features/UsersView.swift:159`；`sub2-mobile-native/Sources/Sub2Core/Models.swift:349-366`）。

**建议改法**：
1. dto.APIKey 新增 `key_masked`，始终返回，例如 `"sk-…3f9a"`（前 3 位 + “…” + 后 4 位）；已删除的墓碑 Key（`__deleted__` 前缀）返回 `""`。
2. 新增查询参数 `key_view=masked`（默认 full，Web 行为不变），适用：`GET /admin/users/:id/api-keys`、`GET /admin/groups/:id/api-keys`、`PUT /admin/api-keys/:id`（及 E01 的新接口）、`GET /admin/usage`。为 masked 时 key 返回 `""`，结构不变。例：`GET /api/v1/admin/users/1/api-keys?key_view=masked` → `{"items":[{"id":4087,"name":"默认","key":"","key_masked":"sk-…3f9a","status":"active"}],"total":2}`。
3. 按需揭示：`POST /api/v1/admin/api-keys/:id/reveal`，挂 stepUpAuth，响应头 `Cache-Control: no-store`，返回 `{"code":0,"data":{"id":4087,"key":"sk-…完整…"}}`。错误：403 STEP_UP_REQUIRED、STEP_UP_TOTP_NOT_ENABLED、STEP_UP_ADMIN_API_KEY_FORBIDDEN；404 API_KEY_NOT_FOUND。用 POST 是为了保证进审计。
4. 建议（可选）：`/admin/usage` 内嵌的 api_key.key 直接默认置空（Web 不读），顺带堵住 E02。

**实现提示**：`handler/dto/mappers.go:80-123` 的 APIKeyFromService 加 KeyMasked，新增 MaskAPIKey（处理 `repository/api_key_repo.go:381` 的墓碑格式）。在 `user_handler.go:485-489`、`group_handler.go:1048-1051`、`apikey_handler.go:70`、`usage_handler.go:212-215` 读 `c.Query("key_view")`，为 masked 时清空 Key（AdminUsageLog 清 usageLog.APIKey.Key）。reveal 路由：`apiKeys.POST("/:id/reveal", gin.HandlerFunc(stepUpAuth), h.Admin.APIKey.Reveal)`，需要把 stepUpAuth 传进 registerAdminAPIKeyRoutes（写法参照 `server/routes/admin.go:403,464`）。step-up 两个限制：开关关闭时中间件直接放行；Admin Key（x-api-key）一律被拒（`server/middleware/step_up.go:105`），所以 App 侧另加本地 Face ID，Admin Key 登录时揭示不可用。只是内存字符串处理，没有额外查询。

**App 退路**：只显示名称与后 4 位（现有 App 已这样做），解码后丢弃 key 字段，不落盘、不写日志；但完整明文仍会经过网络进入 App 内存，App 侧无法避免。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/users/1/api-keys?key_view=masked"` 每项 key 为 `""`、key_masked 以 “…” 加后 4 位结尾；不带参数时 key 仍是完整值并多出 key_masked；`/admin/usage?key_view=masked&page_size=5` 的 items[].api_key.key 为 `""`；step-up 开启时未验证 TOTP 调 `POST /api/v1/admin/api-keys/4087/reveal` 返回 403 STEP_UP_REQUIRED，完成 `/api/v1/user/totp/step-up` 后返回完整 key，审计日志能查到。

---

#### E04 · Key 换分组撤销时在同一事务收回自动授予的分组；replace-group 返回迁移明细并支持精确反向替换 〔P1 · 加参数〕

**页面**：编辑用户 · Key 卡片“换分组”回执的“撤销”；替换分组回执的“撤销”。

**背景**：回执可撤销是全局规则。Key 换到用户没有的专属标准分组时后端会自动授予这个分组，撤销要把 Key 和授权一起还原（`html-preview/layouts/main/v-user-edit.jsx:381-398`）；替换分组的撤销也要准确还原（:367-380）。

**现状**：
1. `PUT /admin/api-keys/:id` 只接受 group_id 与 reset_rate_limit_usage（`handler/admin/apikey_handler.go:25-29`）。专属标准分组会在事务里 AddGroupToAllowedGroups，并返回 auto_granted_group_access、granted_group_id（`service/admin_group.go:1576-1611`），没有反向收回授权的参数。
2. 收回授权只能 `PUT /admin/users/:id` 提交整张 allowed_groups 表（`handler/admin/user_handler.go:88`；`service/admin_user.go` 的 UpdateUser 整表覆盖），读改写之间有竞态。
3. replace-group 在事务里依次：授予新分组 → UpdateGroupIDByUserAndGroup 迁移所有绑定旧分组的 Key → 移除旧分组（`service/admin_group.go:1657-1717`），响应只有 migrated_keys 数量（`handler/admin/user_handler.go:580-584`）。用反向 replace-group 撤销会出两种错：替换前就绑在新分组的 Key 会被一起迁走；用户替换前就有新分组时，这个原有授权会被删掉。
4. replace-group 不动 group_rates（`admin_group.go:1689-1703` 只操作 user_allowed_groups 与 api_keys），撤销时不需要写回专属倍率（设计稿注释也写了倍率保留，`v-user-edit.jsx:367-369`）。

**建议改法**：
1. `PUT /api/v1/admin/api-keys/:id` 新增可选 `revoke_group_access_id`。请求 `{"group_id":2,"revoke_group_access_id":10}`：同一事务里把 Key 改回分组 2，并把分组 10 从该用户的 allowed_groups 移除。条件：分组 10 必须是专属标准分组，且该用户没有其他未删除的 Key 仍绑定分组 10，否则 409 `GROUP_STILL_IN_USE`、整体回滚。响应在现有结构上加 `"revoked_group_access":true,"revoked_group_id":10`。
2. `POST /api/v1/admin/users/:id/replace-group`：响应新增 `"migrated_key_ids":[4087,4099]`、`"new_group_newly_granted":true`（替换前用户是否没有新分组）；请求新增可选 `key_ids`（只迁移这些 Key，必须当前绑定 old_group_id，否则 400 `KEY_NOT_IN_GROUP`）与 `keep_old_group_access`（默认 false，即现有行为）。撤销请求：`{"old_group_id":12,"new_group_id":10,"key_ids":[4087,4099],"keep_old_group_access":true}`；原响应 new_group_newly_granted=false 时，撤销要传 keep_old_group_access:true 保留用户原来就有的分组 12。
两个接口都支持可选 Idempotency-Key；不带新字段时行为完全一致。

**实现提示**：换分组撤销：`apikey_handler.go:25-29` 加字段；`admin_group.go:1530` 的 AdminUpdateAPIKeyGroupID 改为接收 options 结构，把 revoke 放进同一个 entClient.Tx，复用 `repository/user_repo.go:1499-1505` 的 RemoveGroupFromUserAllowedGroups；“是否还有其他 Key 绑定”在 apiKeyRepo 新增 CountByUserAndGroup（排除当前 Key 与软删 Key）。replace-group：`user_handler.go:553-585` 加字段；ReplaceUserGroup 在 AddGroupToAllowedGroups 之前查 user_allowed_groups 里是否已有新分组；迁移改为返回 ID 列表（UpdateGroupIDByUserAndGroup 加 RETURNING id，或按 ID 迁移 `WHERE id = ANY($ids) AND user_id=$u AND group_id=$old AND deleted_at IS NULL`）；keep_old_group_access=true 时跳过 RemoveGroupFromUserAllowedGroups。事务提交后仍按原逻辑失效该用户所有 Key 的认证缓存（`admin_group.go:1707-1714`）。

**App 退路**：换分组撤销：先 `PUT api-keys {group_id: 原分组}`；当时自动授予过分组的，再 GET users/:id 取最新 allowed_groups，去掉该分组后 PUT 回去；第二步失败提示“Key 已还原，但分组授权未收回，请在权限与并发里手动移除”。替换分组撤销：调用反向 replace-group；替换前用户已有新分组、或新分组下原本就有 Key 时，撤销按钮置灰，或提示“撤销可能多迁移 Key 或删掉原有授权”。

**验收**：用户 1 没有专属分组 10：`PUT api-keys/4087 {"group_id":10}` 返回 auto_granted_group_access:true；再 `PUT {"group_id":2,"revoke_group_access_id":10}` 返回 revoked_group_access:true，`GET users/1` 的 allowed_groups 不再有 10；用户还有另一个 Key 绑定分组 10 时同样请求返回 409 GROUP_STILL_IN_USE、Key 分组不变；replace-group 响应带 migrated_key_ids，按撤销请求回滚后 Key 与 allowed_groups 与替换前完全一致；Web 的 GroupReplaceModal（`frontend/src/components/admin/user/GroupReplaceModal.vue:122`）与 UserApiKeysModal 请求结果不变。

---

#### E05 · 新增用户列表“快捷充值头像”数据源：最近调整过余额的用户（去重、带当前余额）+ 余额低的用户 〔P1 · 新接口〕

**页面**：用户列表顶部的快捷充值头像条。（列表每一行和用户详情头部的“余额低”标记用同一套判定，见附录 B L22。）

**背景**：第 2 轮 Q12 选“要”（`DECISIONS.md:71`）：列表顶部一排“最近调整 · 余额低”的用户，带当前余额，点头像直接开大数字键盘；禁用用户不出现，待核对的用户排在最后（`html-preview/layouts/main/v-users.jsx:467-501`）。

**现状**：
1. `GET /api/v1/admin/user-adjustments`（`server/routes/admin.go:144-151`，AdminOnly）返回逐条记录（`service/admin_user_adjustment.go:75-97`），不按用户去重、不带当前余额；筛选只有 kind、operation、direction、keyword、operator、时间（`handler/admin/user_adjustment_handler.go:137-173`）。
2. `/admin/users` 的筛选只有 status、role、search、group_name、api_key_group_id、attr（`handler/admin/user_handler.go:139-176`；`service/user_service.go:67-84`）：不能按一组 id 批量取，没有“余额低”过滤，只能 sort_by=balance（`repository/user_repo.go:661-700`）。
3. 余额低阈值：全局 balance_low_notify_enabled / threshold（`service/balance_notify_service.go:253-267`）；用户自己的 balance_notify_threshold 优先；percentage 类型要乘 users.total_recharged（:61-68、95-115）。这些字段 DTO 已返回（`handler/dto/types.go:27-32`）。

**建议改法**：`GET /api/v1/admin/users/quick-topup?recent_limit=8&low_limit=8&recent_days=30`（AdminOnly，与 user-adjustments 同权限）：

```json
{"recent":[{"user_id":1,"email":"wxm@example.com","username":"王小明","status":"active","balance":12.4,"last_adjusted_at":"2026-10-17T09:12:00Z","last_delta":"20.00000000","last_operation":"add"}],
 "low_balance":[{"user_id":7,"email":"…","username":"…","status":"active","balance":3.1,"effective_threshold":10,"threshold_source":"user","threshold_type":"fixed"}],
 "low_balance_enabled":true}
```

- recent：admin_user_adjustments 里 kind=balance 的记录按 user_id 去重后取最近 N 个用户，JOIN users 拿当前余额，排除已删除和禁用的用户。
- low_balance：status=active 且 balance 低于有效阈值；有效阈值 = 用户阈值优先，否则全局阈值；percentage 类型 = total_recharged × 阈值 / 100；按 balance / 阈值升序。全局提醒关闭且用户没设阈值时不算余额低，并返回 low_balance_enabled=false。
- （可选，通用）`GET /api/v1/admin/users?ids=1,2,3`（最多 100 个）按 id 批量取用户，方便刷新头像条。
- （可选）`GET /api/v1/admin/users` 每项只增只读的 `low_balance`、`effective_threshold`，口径同上，列表行与用户详情直接用；不做时 App 按附录 B L22 本地计算。
- 错误：400（limit 越界）；403 FORBIDDEN（非 admin）。

**实现提示**：路由 `users.GET("/quick-topup", middleware.AdminOnly(), h.Admin.User.QuickTopup)`，gin 支持静态段与 `/:id` 并存。recent 的 SQL：`SELECT DISTINCT ON (user_id) user_id, created_at, delta, operation FROM admin_user_adjustments WHERE kind='balance' AND user_id IS NOT NULL AND created_at >= now()-$days ORDER BY user_id, created_at DESC`，外层按 created_at DESC LIMIT n，再 JOIN users WHERE deleted_at IS NULL AND status='active'；可用索引 idx_admin_user_adjustments_user_created / kind_created（`migrations/223_admin_user_adjustments.sql:47-54`）。low_balance 在 users 上用 CASE 表达式（balance_notify_threshold_type、balance_notify_threshold、total_recharged 列，`ent/schema/user.go:105-116`），全局阈值作参数传入，ORDER BY 后 LIMIT n；万级用户全表扫描可接受，也可加 30 秒 snapshot 缓存。percentage 阈值依赖 users.total_recharged，而管理员充值不累加这一列（见 E10、附录 C Q12），阈值会偏低。

**App 退路**：recent：`GET user-adjustments?kind=balance&page_size=50`，客户端按 user_id 去重取前 8，再逐个 `GET users/:id`（最多 8 次）。low：`GET users?status=active&sort_by=balance&sort_order=asc&page_size=20`，再读 `GET /api/v1/settings/public` 的 balance_low_notify_enabled / balance_low_notify_threshold（`handler/dto/settings.go:435-437`），客户端按每个人的阈值计算；percentage 阈值不准时宁可不标“余额低”。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/users/quick-topup"`：recent 里没有重复 user_id，balance 与 `GET users/:id` 一致，没有禁用用户；把某用户 balance_notify_threshold 设为 50、余额 30，该用户出现在 low_balance，effective_threshold=50、threshold_source=user；vendor 调用返回 403。

---

#### E06 · 固定 API Key 状态枚举为 active / inactive / quota_exhausted / expired（停用 = inactive），补常量并新增 effective_status 〔P2 · 加字段〕

**页面**：用户详情 Key 摘要（“活跃 N”）、编辑用户 Key 卡片徽章、分组 API 密钥页。

**背景**：App 要按状态区分“活跃 / 已停用 / 额度耗尽 / 已过期”并统计活跃数；E01 上线前要先定停用写哪个值。

**现状**：
1. 常量只有 active、disabled、quota_exhausted、expired（`service/api_key.go:10-15`）；生产代码里没有地方写入 disabled，只有集成测试 SQL 里出现（`repository/auth_cache_invalidation_outbox_integration_test.go:69`）。
2. 用户侧停用写的是 inactive：`binding:"oneof=active inactive"`（`handler/api_key_handler.go:53`），service 原样写库（`service/api_key_service.go:855-858`）；Web 类型是 `'active'|'inactive'|'quota_exhausted'|'expired'`（`frontend/src/types/index.ts:764`），切换停用写 inactive（`frontend/src/views/user/KeysView.vue:1755`）。
3. 鉴权时非 active 且不是 expired / quota_exhausted 的一律按停用拦截（`server/middleware/api_key_auth.go:122-130`），所以 inactive 与 disabled 效果相同。
4. quota_exhausted 由计费 SQL 写入（`repository/usage_billing_repo.go:417-433`、`repository/api_key_repo.go:783-800`）；expired 从没被写库，过期只靠运行时 IsExpired() 拦截（`server/middleware/api_key_auth.go:228`），这种 Key 的 status 仍是 active。
5. 设计稿按 disabled 映射“已停用”、漏了 inactive（`html-preview/layouts/main/00-core.jsx:469`、`v-user-edit.jsx:64-65`、`v-groups.jsx:1045`），用户自己停用的 Key、过期 Key 会被算成“活跃”。

**建议改法**（不改已有值，不迁移数据）：
1. `service/api_key.go` 增加常量 `StatusAPIKeyInactive = "inactive"`，注释写明 disabled 是历史常量、读取时与 inactive 同义。
2. E01 的管理端接口只接受、只写入 inactive；收到 disabled 先归一成 inactive。
3. 接口文档固定枚举：status ∈ {active, inactive, quota_exhausted, expired}。
4. dto.APIKey 新增只读 `effective_status`，按鉴权顺序计算：inactive 或 disabled → inactive；status=quota_exhausted 或 IsQuotaExhausted() → quota_exhausted；IsExpired() → expired；其余 active。例：`{"id":4099,"status":"active","effective_status":"expired","expires_at":"2026-10-01T00:00:00Z"}`。

**实现提示**：`handler/dto/types.go:56` 的 APIKey 加 `EffectiveStatus string json:"effective_status"`；在 `handler/dto/mappers.go:80` 的 APIKeyFromService 里用 k.IsExpired()、k.IsQuotaExhausted()（`service/api_key.go:77` 起）计算，纯内存。所有返回 dto.APIKey 的接口（用户侧、管理端 users / groups 的 api-keys、PUT api-keys、usage 内嵌）自动带上，Web 不受影响。

**App 退路**：App 自己映射：inactive 与 disabled 都显示“已停用”；status=active 但 expires_at 早于现在显示“已过期”；quota>0 且 quota_used ≥ quota 显示“额度耗尽”；“活跃 N”按映射后的结果统计。

**验收**：用户在 Web 停用 Key 后，`GET /api/v1/admin/users/:id/api-keys` 里这个 Key 的 status 与 effective_status 都是 inactive；把 expires_at 设为过去时间，status 仍是 active、effective_status 为 expired；通过 E01 的 PUT 发 `{"status":"disabled"}`，库里写入 inactive。

---

#### E07 · 平台限额支持单个平台的 PUT / DELETE（可选恢复用量） 〔P2 · 新接口〕

**页面**：编辑用户 · Key 与限额 · 平台限额（保存、撤销）。

**背景**：一次只改一个平台、或撤销一次修改，都不应影响其他平台（`html-preview/layouts/main/v-user-edit.jsx:418-428` 的 saveQuota 现在撤销时整表写回）。

**现状**：
1. `PUT /api/v1/admin/users/:id/platform-quotas` 是全量替换（`handler/admin/user_handler.go:806-822,823-990`）；仓储 UpsertForUser 会软删所有没提交的平台（`repository/user_platform_quota_repo.go:318-353`；softDeleteMissingPlatforms :357-380），必须先读后写，多个管理员并发编辑时后写覆盖前写。
2. 清空某个平台的限额就是软删这一行并放弃已累计的用量，之后再配置会新建一行、从新窗口重新计算（`user_platform_quota_repo.go:318-319`），所以“撤销取消限额”即使整表写回，用量也已经丢了。
3. GET 返回 platform_quotas 数组（`user_handler.go:774-804`）；重置单个窗口已有 `POST /api/v1/admin/users/:id/platform-quotas/reset`（`server/routes/admin.go:336`）。

**建议改法**（平台 ID 用 domain.platformList 里的 ID，如 anthropic、zhipu；原有整表 PUT 保留不变）：
1. `PUT /api/v1/admin/users/:id/platform-quotas/:platform`，请求 `{"daily_limit_usd":10,"weekly_limit_usd":50,"monthly_limit_usd":null}`（null = 不限，0 = 禁止该平台，三项全为 null 等于删除）；只 upsert 这一个平台。响应 `{"platform_quota":{…与 GET 单项结构相同…},"previous":{…旧限额，没有则为 null}}`。
2. `DELETE /api/v1/admin/users/:id/platform-quotas/:platform` → `{"removed":true,"previous":{…}}`；不存在返回 404 `USER_PLATFORM_QUOTA_NOT_FOUND`。
3. （可选）`POST /api/v1/admin/users/:id/platform-quotas/:platform/restore`：该平台没有活跃行时，把最近一次软删的行恢复（deleted_at 置空），用于撤销“取消限额”而不丢用量。
错误：400 invalid platform、*_limit_usd must be >= 0、must be a finite number；404 USER_NOT_FOUND；503 platform quota service not available。

**实现提示**：handler 在 `user_handler.go` 新增 UpsertUserPlatformQuota、DeleteUserPlatformQuota，复用 :842-883 的校验与 :930-964 的审计 slog 结构。仓储在 `user_platform_quota_repo.go` 新增 UpsertOneForUser（withTx 里先 updateLimitsRow，没更新到再 insertLimitsRow，见 :390-437）与 SoftDeleteOne。缓存只失效这一个平台：`billingCache.DeleteUserPlatformQuotaCache(ctx, userID, platform)`（参照 :966-975）。路由加在 `server/routes/admin.go:334-336` 旁，与 `POST /:id/platform-quotas/reset` 方法不同，不冲突。flusher 绝对值覆盖的竞态说明（`user_platform_quota_repo.go:436-438`）同样适用于新写入。

**App 退路**：每次提交前先 GET 最新列表，在它的基础上改一个平台再整表 PUT；撤销同样“GET → 改回 → PUT”；撤销“取消限额”时提示“已用额度会从 0 重新计算”。

**验收**：用户有 anthropic 与 zhipu 两条限额：`PUT …/platform-quotas/anthropic {"daily_limit_usd":20}` 后 GET，两条都在且 zhipu 用量不变；`DELETE …/platform-quotas/zhipu` 后只剩 anthropic，previous 是旧值；platform=foo 返回 400；整表 PUT 行为不变。

---

#### E08 · rpm-status 标明计数是否生效（tracked），可选在不限额时也计数，并修正 DTO 注释 〔P2 · 加字段〕

**页面**：编辑用户 · 权限与并发 · RPM 状态（用户总计与逐分组的 used / limit）。

**背景**：即使没设上限，管理员也想看到这个用户本分钟、按分组实际发了多少请求（`html-preview/layouts/main/v-user-edit.jsx:809-835`）。

**现状**：
1. checkRPM 只在有上限时才自增计数（`service/billing_cache_service.go:812-893`）：分组计数只在 override>0（:846-848），或没有 override 且 group.RPMLimit>0（:861-863）时才计，override=0（免检）也不计；用户计数只在 user.RPMLimit>0 时才计（:878-879）。
2. GetUserRPMStatus 只读这些 Redis 键（`service/admin_user.go:1076-1150`；`repository/user_rpm_cache.go:76-108`），键不存在返回 0，不限额的行永远显示 0，会被误读成“本分钟没有请求”。
3. DTO 注释说 rpm_limit“仅在所用分组未设置 rpm_limit 时作为兜底生效”（`handler/dto/types.go:34`），与 checkRPM 实现（第二层始终生效，`billing_cache_service.go:876-891`）不符。

**建议改法**：
1. 只增字段：rpm-status 响应新增 `user_rpm_tracked`（= user_rpm_limit>0）与 `per_group[].tracked`（override>0，或没有 override 且分组 rpm_limit>0）。例：`{"user_rpm_used":0,"user_rpm_limit":0,"user_rpm_tracked":false,"per_group":[{"group_id":1,"group_name":"默认","used":0,"limit":0,"source":"group","tracked":false}]}`。
2. （可选，想看真实用量时，取舍见附录 C Q14）二选一：不限额时也计数（cache 新增 IncrementUserAndGroupRPM，用一个 TxPipeline 同时 INCR 两个键，热路径多 1 次 Redis 往返；配置开关 `rpm.track_unlimited` 默认关）；或对 tracked=false 的项从 usage_logs 估算本分钟请求数并标 `"observed_from":"usage_logs"`（只统计已完成请求，有滞后）。
3. 把 `handler/dto/types.go:34` 的注释改成“用户级全局上限，始终生效”。

**实现提示**：`service/admin_service.go:516-530` 的 UserRPMStatus、UserGroupRPMStatus 加 Tracked，在 `service/admin_user.go:1076-1150` 里根据 user.RPMLimit、override、group.RPMLimit 计算，不增加查询。选做的计数改 `billing_cache_service.go:844-891` 与 `repository/user_rpm_cache.go`；选做的估算可用 usage_logs(user_id, created_at) 索引（`ent/schema/usage_log.go:244`），按 group_id 计数。

**App 退路**：tracked 上线前，用户或分组 limit==0 的行不显示已用数，写“不限 · 不计数”；来源是 override 且 limit 为 0 的写“免检”。

**验收**：用户 rpm_limit=0、分组 rpm_limit=0：`GET /api/v1/admin/users/:id/rpm-status` 返回 user_rpm_tracked=false、per_group[].tracked=false；用户 rpm_limit 设为 60 后发几次请求，user_rpm_tracked=true 且 user_rpm_used 增加；打开选做开关后，不限额时 used 也会增加。

---

#### E09 · dashboard/api-keys-usage 的快照缓存键加上当天日期 〔P2 · 改行为〕

**页面**：编辑用户 Key 卡片的今日消费、分组 API 密钥页的今日花费。

**背景**：零点以后，“今日”不能显示昨天的数。

**现状**：`POST /api/v1/admin/dashboard/users-usage` 的缓存键带当天日期，注释写明必须带（`handler/admin/dashboard_handler.go:422-431`）；`POST /api/v1/admin/dashboard/api-keys-usage` 的缓存键只有 api_key_ids（:471-476），快照缓存有效期 30 秒（:370），跨零点后最多 30 秒内同一组 ID 会拿到昨天的 today_actual_cost。

**建议改法**：缓存键加 `V` 与 `Day: timezone.Today().Format("2006-01-02")`，写法与 users-usage 一样。接口、参数、响应都不变。

**实现提示**：`dashboard_handler.go:471-476` 的匿名 struct 里加 `V int`、`Day string`，照抄 :423-431；补一个与 users-usage 同类的单测。

**App 退路**：影响很小；如在意，00:00–00:01 之间收到 `X-Snapshot-Cache: hit` 时延迟几秒再刷新一次。

**验收**：单测：日期切换前后，相同 api_key_ids 生成不同 cacheKey；手测：23:59:50 请求一次，00:00:05 再请求，响应头为 `X-Snapshot-Cache: miss`，today_actual_cost 从当天重新计算。

---

#### E10 · 充值与调整记录补齐：balance-history 带管理员调整的前后余额，user-adjustments 支持 user_id 精确筛选，明确“总充值”口径，新建用户的初始余额入账并支持 Idempotency-Key 〔P2 · 加字段〕

**页面**：用户详情 · 充值与调整记录（最近 5 条 + 分页全部、总充值）；新建用户 · 基础（初始余额）。

**背景**：用户已接受暂时没有“变动后余额”，分区改名为“充值与调整记录”（`DECISIONS.md:102`）；但核对时仍希望管理员调整能看到前后余额、总充值只有一个数、所有资金进出都能在记录和审计里查到（`html-preview/layouts/main/v-users.jsx:9-11`、`html-preview/layouts/main/v-user-edit.jsx:302-317`）。

**现状**：
1. balance-history 返回 redeem_codes 兼容行（AdminRedeemCode），没有 before / after（`handler/admin/user_handler.go:512-551`；`handler/dto/types.go:506-534`），还会合并 affiliate 流水（`service/admin_user.go:1162-1300`）。
2. admin_user_adjustments 有 before_value / after_value（`migrations/223_admin_user_adjustments.sql:1-45`；`service/admin_user_adjustment.go:75-97`），写入时与兼容 redeem_codes 行在同一事务、用同一个 now（`service/admin_user.go:880-929`），但两张表之间没有关联列，legacy_redeem_code_id 只给迁移来的历史行用（`migrations/223_admin_user_adjustments.sql:64-97`）。
3. user-adjustments 没有 user_id 参数；keyword 对 `user_id::text ILIKE '%x%'`（`repository/admin_user_adjustment_repo.go:111-116`），搜 1 会同时命中 10、21、100。
4. “总充值”两个来源范围不同：balance-history 的 total_recharged 是 redeem_codes 中 type 为 balance 或 admin_balance 且 value>0 的总和（`repository/redeem_code_repo.go:432-452`）；users.total_recharged 列只在 UpdateBalance(amount>0) 时累加（`repository/user_repo.go:842-848`，含兑换码、优惠码 `service/promo_service.go:127`、支付订单经兑换码入账）以及返利转余额时累加（`repository/affiliate_repo.go:289-293`），管理员充值走 AdjustBalanceExact / SetBalanceExact 不累加（`repository/user_repo.go:960-1050`）。结果管理员充值只算进前者，返利和优惠码只算进后者。DTO 的 User.total_recharged 返回列值（`handler/dto/types.go:32`），余额提醒的百分比阈值也用这一列（`service/balance_notify_service.go:109`）。
5. CreateUser 直接把 balance（或站点 default_balance）写进 users（`service/admin_user.go:122-160`），不写 adjustments、不写 redeem_codes、也不累加 total_recharged，“充值与调整记录”看不到这笔钱，也无法按 request_id 核对。`POST /admin/users` 没走幂等封装（`handler/admin/user_handler.go:296-329`），而 PUT users 与批量接口已用 executeAdminOptionalIdempotentJSON（:401、661、730）。

**建议改法**：
1. balance-history 每一项新增可选字段（只有管理员调整行有值，其他为 null）：`{"id":901,"type":"admin_balance","value":20,"notes":"补偿","used_at":"…","adjustment_id":5521,"before_value":"12.40000000","after_value":"32.40000000","operator_email":"ops@example.com"}`。
2. `GET /api/v1/admin/user-adjustments?user_id=1`：精确筛选（`user_id = $n`），非法值 400。（与 G02 的 request_id / action_id 过滤一起做。）
3. 总充值口径：balance-history 保留现有 total_recharged，并新增 `"total_recharged_breakdown":{"redeem":40,"admin":20,"affiliate":5,"promo":0}`；文档写明“总充值”以 balance-history 为准。是否让管理员 add 方向的正向调整也累加 users.total_recharged（会影响余额提醒的百分比阈值），见附录 C Q12。
4. 新建用户：balance>0 时在同一事务写一条 admin_user_adjustments（kind=balance、operation=set、before 0、after=balance、source=`admin_create_user`、notes=“初始余额”）以及对应的兼容 redeem_codes(admin_balance) 行；`POST /admin/users` 改用 `executeAdminOptionalIdempotentJSON(scope "admin.users.create")`，不带 key 时行为不变。站点 default_balance 自动发放是否也入账（source=`default_balance`）见附录 C Q12。

**实现提示**：两表关联：新迁移给 admin_user_adjustments 加 `redeem_code_id BIGINT NULL` 与索引；createAdjustmentRecords（`service/admin_user.go:880-929`）改为 redeem_codes 插入后返回 id（`repository/redeem_code_repo.go:47` 的 CreateBatch / createBatchExact 加 RETURNING id），再写 adjustments。历史回填：legacy 行用 legacy_redeem_code_id，223 迁移之后的行按 (user_id, created_at=used_at, delta=value, 类型映射) 匹配；append-only 触发器（`migrations/223_admin_user_adjustments.sql:99-111`）会拦截 UPDATE，迁移里要临时禁用。不想加列也可在查询时用同样条件 LEFT JOIN，但依赖两个时间戳完全相等。balance-history：`admin_user.go:1162-1213` 查出结果后按 redeem_code_id 批量取 adjustments，AdminRedeemCode（`handler/dto/types.go:530`）加字段。user_id 筛选：AdminUserAdjustmentFilter（`service/admin_user_adjustment.go:99-107`）加 UserID，adjustmentWhere（`repository/admin_user_adjustment_repo.go:92-129`）加条件，parseUserAdjustmentFilter（`handler/admin/user_adjustment_handler.go:137`）解析，(user_id, created_at) 索引可用。CreateUser：`admin_user.go:122-160` 用 entClient.Tx 把 userRepo.Create 与 createAdjustmentRecords 包在一起；`user_handler.go:310` 包一层 executeAdminOptionalIdempotentJSON。

**App 退路**：记录行只写时间与备注，不写“余额 $X”，分区名用“充值与调整记录”；总充值统一取 balance-history 的 total_recharged，不用 users.total_recharged；按用户查 user-adjustments 用 keyword=<id> 再本地过滤 user_id 相等的记录；新建用户确认框写明“初始余额创建时直接写入，不会出现在充值与调整记录里”，或建议先建 0 余额用户再用充值键盘充值（会留下记录）。

**验收**：管理员给用户充值 $20 后，`GET users/1/balance-history` 第一条 before_value / after_value 有值且差为 20，兑换码行这两个字段为 null；`GET user-adjustments?user_id=1` 只返回 user_id=1 的记录，user_id=abc 返回 400；同一 Idempotency-Key 两次 `POST users {"balance":50,…}` 只创建一个用户，新用户 balance-history 有一条 +50（初始余额），user-adjustments 有一条 source=admin_create_user；不带新参数的旧请求，响应字段只增不减。

---

#### E11 · 管理端 Key 列表回填 current_concurrency（现在恒为 0） 〔P2 · 修 bug〕

**页面**：编辑用户 · Key 卡片“当前并发”；分组 API 密钥页。

**背景**：设计稿 Key 卡片有“当前并发”一栏（`html-preview/layouts/main/v-user-edit.jsx:24`）。

**现状**：`GET /admin/users/:id/api-keys` 走 adminService.GetUserAPIKeys → apiKeyRepo.ListByUserID（`service/admin_user.go:1067-1074`），`GET /admin/groups/:id/api-keys` 走 GetGroupAPIKeys（`service/admin_group.go:1406-1416`），都不填充并发数；只有用户侧 APIKeyService.List 会调 fillCurrentConcurrency（`service/api_key_service.go:683-700`）。

**建议改法**：两个管理端列表在返回前回填 current_concurrency，响应结构不变。

**实现提示**：在 `handler/admin/user_handler.go:479-489` 与 `handler/admin/group_handler.go:1042-1051` 拿到 keys 后，调 `ConcurrencyService.GetAPIKeyConcurrencyBatch`（`service/concurrency_service.go:513`）回填；UserHandler 已注入 concurrencyService（`user_handler.go:34`），GroupHandler 需要新注入（改 wire）。Redis 读失败时保持 0 并记日志（或配合 C15 的思路加 `concurrency_available`）。

**App 退路**：“当前并发”显示“—”。

**验收**：一个 Key 正在跑 2 个并发请求时，`GET /api/v1/admin/users/:id/api-keys` 该 Key 的 current_concurrency=2，与用户侧 `GET /api/v1/keys` 一致。

---

#### E12 · users-usage / api-keys-usage 限制 ID 数量 〔P2 · 改行为〕

**页面**：用户列表“今日消费”、Key 卡片今日消费。

**背景**：防止一次超大请求拖慢 usage_logs 聚合。

**现状**：管理端 `POST /admin/dashboard/users-usage`、`/admin/dashboard/api-keys-usage` 对 ID 数量没有上限（`handler/admin/dashboard_handler.go:410-414,460-464` 只做 normalizeInt64IDList 去重）；用户侧同类接口最多 1000 个（`handler/usage_handler.go:640,662-665`，"Too many API key IDs (maximum 1000 allowed)"）。

**建议改法**：超过 1000 个返回 400，文案与用户侧一致（"Too many user IDs (maximum 1000 allowed)" / "Too many API key IDs (maximum 1000 allowed)"）。Web 每次只传一页的 ID，不受影响。

**实现提示**：在 normalizeInt64IDList 之后判断长度，常量复用或新增 maxDashboardUserUsageIDs。

**App 退路**：每批不超过 200 个 ID。

**验收**：传 1001 个 ID 返回 400；1000 个以内结果不变。

---

### F 分组

#### F01 · 新增 `POST /api/v1/admin/groups/:id/accounts/batch`：按分组增量加入 / 移出成员账号，逐项返回结果（幂等，可重试、可撤销） 〔P1 · 新接口〕

**页面**：分组详情（成员列表、添加账号 sheet:groupPick、滑动移出）；编辑 / 新建分组 sheet:groupEdit；成员批量写入结果页 screen:groupBatch。

**背景**：第 2 轮决定分组“可查看 + 可编辑（加减账号）”（`DECISIONS.md:52`）。一次加入或移出多个账号后，回执显示“已加入 n 个，m 个失败 ›”，结果页可以“重试失败的 n 个”和“撤销成功的 n 个”（`html-preview/layouts/main/v-groups.jsx:1153-1215`）；编辑分组 sheet 保存时改名和成员增减一起提交（:1418-1446）。设计稿注释写的是现状：成员变更要对每个账号发一次 PUT admin/accounts/:id（:14、48-50、303-306）。

**现状**：
1. 分组路由下没有成员写接口（`server/routes/admin.go:344-371`）；分组创建 / 更新只接受 copy_accounts_from_group_ids（`handler/admin/group_handler.go:258,333`），更新时会先清空再复制（`service/admin_group_field_scope.go:217`；`service/admin_group.go:1222-1283`）。
2. 成员关系只能用 `PUT /admin/accounts/:id` 的 group_ids 整体替换（`server/routes/admin.go:427`；`handler/admin/account_handler.go:169`，handler 在 :1198-1210 调 UpdateAccount）。这条路径有副作用：只改分组也会走 UpdateWithAccountBillingSettings（`service/admin_account.go:989`），按请求开始时读到的快照写回整行账号，包括 name、credentials、status、error_message、schedulable（`repository/account_repo.go:576-588`），请求期间调度器把账号标成 error 或刷新了 token，可能被改回去；之后 BindGroups 删除该账号全部绑定再重建，priority 被重置为列表下标 i+1（`repository/account_repo.go:1983-2040`，:2022），会改掉这个账号在其他分组里的优先级（调度、容量按 ag.priority 排序，:2178）。这同样影响 Web 的账号编辑。
3. `POST /admin/accounts/bulk-update` 的 group_ids 是给所有选中账号设成同一份列表（`handler/admin/account_handler.go:189`；`service/admin_account.go:1316-1333` 逐个 BindGroups），没有 add / remove 模式。
4. 仓储层有未暴露的工具，但不能直接用：groupRepository.BindAccountsToGroup 是 `INSERT … ON CONFLICT DO NOTHING`、priority 固定 50（`repository/group_repo.go:1132-1175`）；accountRepository.AddToGroup / RemoveFromGroup（`repository/account_repo.go:1916-1964`）不在 AccountRepository 接口里（`service/account_service.go:92`），AddToGroup 没有 ON CONFLICT、重复加入会报唯一键错误，RemoveFromGroup 没有事务、也不锁分组。

**建议改法**：`POST /api/v1/admin/groups/:id/accounts/batch`（用 POST 而不用 PUT / PATCH：vendor 白名单对 `/admin/groups` 放行了 PUT / PATCH，`server/middleware/vendor_routes.go:140-143`，用 POST 时 vendor 默认被拒）。

```json
{"add":[{"account_id":11},{"account_id":12,"priority":2}],"remove":[13],"confirm_mixed_channel_risk":false}
```

priority 可选，默认 50（与 BindAccountsToGroup 一致），撤销移出时把旧 priority 传回；add 与 remove 合计最多 200 个，服务端先去重。

```json
{"code":0,"message":"success","data":{
  "group_id":3,"added":1,"removed":1,"unchanged":1,"failed":1,
  "results":[
    {"account_id":11,"action":"add","status":"added","priority":50},
    {"account_id":12,"action":"add","status":"unchanged"},
    {"account_id":13,"action":"remove","status":"removed","priority":2},
    {"account_id":14,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK","message":"…","details":{"current_platform":"antigravity","other_platform":"anthropic"}}],
  "counts":{"account_count":6,"active_account_count":4,"rate_limited_account_count":1}}}
```

- 先逐项校验，失败项写进 results（reason 取 `ACCOUNT_NOT_FOUND` 或 `MIXED_CHANNEL_RISK`），不影响其他项；通过校验的项在同一个事务里执行，数据库失败时整批回滚、返回 500。
- 幂等：已在组内的 add、不在组内的 remove 都返回 unchanged，重试安全。
- 撤销：App 对 status=added 的项发 remove，对 status=removed 的项发 add 并带回 priority。
- 不新增平台一致性限制（与现有 PUT 一致）；App 只列同平台账号。
- 请求级错误：400 `INVALID_GROUP_ID`；400 `EMPTY_MEMBER_CHANGE`；400 `TOO_MANY_ACCOUNTS`（> 200）；400 `ACCOUNT_IN_BOTH_LISTS`；400 `SIMPLE_MODE_GROUP_NOT_BINDABLE`（simple 模式下的组合分组）；404 `GROUP_NOT_FOUND`（不存在或已删除，沿用 ErrGroupNotFound / ErrWorkspaceScopeViolation）；403（vendor，路由层默认拒绝）。
- 只新增路由，现有 `PUT /accounts/:id` 与 bulk-update 不变，Web 不受影响。

**实现提示**：
- 路由：`registerGroupRoutes` 在 :370 附近加 `groups.POST("/:id/accounts/batch", h.Admin.Group.BatchUpdateMembers)`。
- Handler（`handler/admin/group_handler.go`）：新增请求结构与 BatchUpdateMembers，参照 GetStats 解析 id；调 rejectUnsupportedSimpleModeOperation（新增一个 operation 常量）；校验数量、去重与交集；把 MixedChannelError 转成逐项结果（字段参照 `account_handler.go` 中 BulkUpdate 的 409 details）。
- Service：AdminService 接口（`service/admin_service.go`）加 UpdateGroupMembers，输入输出类型放在 BulkUpdateAccountsResult（:533）旁；实现放 `service/admin_group.go`：requireGroupAccess(groupID) → validateGroupIDsExist + ValidateAccountGroupBindings(ctx, []int64{groupID})（`service/admin_account.go:1774,1805`，含 vendor 授权与 simple 模式检查）→ accountRepo.GetByIDs 加 scopedAccountIDs（`admin_account.go:103`），找不到的记 ACCOUNT_NOT_FOUND → 混合渠道未确认时检查：checkMixedChannelRisk（`admin_account.go:1699`）每次都调 ListByGroup，所以先读一次组内账号再在内存里逐个判断，避免 N 次查询。
- Repository（`repository/group_repo.go`，接口在 `service/group_service.go:40`）：新增 UpdateGroupMembers(ctx, groupID, adds, removeIDs)，一个事务里 lockLiveGroups(groupID)（`group_repo.go:35`）→ `INSERT INTO account_groups … SELECT unnest … ON CONFLICT (account_id, group_id) DO NOTHING RETURNING account_id`（区分 added / unchanged）→ `DELETE FROM account_groups WHERE group_id=$1 AND account_id=ANY($2) RETURNING account_id, priority`。提交后发 SchedulerOutboxEventGroupChanged（同 `group_repo.go:1167-1170`）；调度快照按账号缓存分组的话，再为每个受影响账号发 AccountGroupsChanged（参照 `account_repo.go:1959-1962`）。返回前用 loadAccountCounts（`group_repo.go:1001`）回填 counts。不要直接复用 AddToGroup / RemoveFromGroup（原因见现状第 4 条），要么修好要么删除。
- 效果：不碰 accounts 行，不重置该账号在其他分组的 priority；按 (account_id, group_id) 行级操作，多人并发编辑不丢更新；POST 自动记审计（`server/routes/admin.go:35`）。
- 建议顺带：UpdateAccount 对“只改分组”的请求走只写绑定的快速路径，消除现状第 2 条对 Web 的影响。
- 测试：仓储集成测试（幂等、其他分组 priority 不变、分组已删除返回 404）、handler 测试、vendor 路由守卫测试断言 403（`server/middleware/vendor_routes_guard_test.go`）。

**App 退路**：逐个账号处理：GET `/admin/accounts/:id` 取最新 group_ids → 本地加入或去掉目标分组 → PUT `/admin/accounts/:id` 只带 group_ids。每个账号 2 个请求、串行，逐项显示“已加入 n 个，m 个失败 ›”；遇到 409 mixed_channel_warning 让用户确认后带 confirm_mixed_channel_risk=true 重发；撤销时对成功的账号反向 PUT。要提示的风险：与他人并发编辑同一账号的分组会互相覆盖；PUT 会按快照写回账号整行，并把该账号在其他分组的 priority 重置成列表顺序。新建分组带成员时，先 POST `/admin/groups` 再逐个 PUT。

**验收**：`curl -X POST "$BASE/api/v1/admin/groups/3/accounts/batch" -H "x-api-key: $ADMIN_KEY" -H 'Content-Type: application/json' -d '{"add":[{"account_id":11},{"account_id":12}],"remove":[13]}'`
1. added、removed、unchanged 计数与 results 正确；原样重放全部返回 unchanged。
2. `GET /admin/accounts/11` 的 group_ids 含 3，account_groups 里其他分组的 priority 不变；账号 13 的 status、credentials、error_message 没被改写。
3. 混合渠道账号返回 failed + MIXED_CHANNEL_RISK，带 confirm_mixed_channel_risk=true 重试后成功；不存在的 account_id 返回 failed ACCOUNT_NOT_FOUND，其余项照常生效。
4. 已删除分组返回 404；同一 id 同时在 add 和 remove 返回 400；超过 200 个返回 400；vendor 返回 403。
5. `GET /admin/groups/3` 的 account_count 同步变化；加入后该分组的新请求能调度到账号 11。

---

#### F02 · `GET /api/v1/admin/groups/:id/stats` 返回真实数据（Key 数、订阅总数与生效数），不存在的分组返回 404 〔P1 · 改行为〕

**页面**：分组详情 · 记录与关联（API 密钥 N 个、订阅生效中 N 个）、用量与容量；停用确认（列表滑动和详情菜单）；删除分组确认框（影响 N 个 Key、N 条订阅、其中生效中 N 条）。

**背景**：分组详情的“API 密钥 N 个”“订阅 · 生效中 N 个”（`html-preview/layouts/main/v-groups.jsx:763-764`）；停用确认“使用这个分组的 N 个 API 密钥会被拒绝”（:295-299，列表滑动入口在 :472）；删除确认要 Key 数、订阅总数和生效数（:385-397，列表入口在 :429）。

**现状**：
1. `GET /admin/groups/:id/stats` 是占位：对任意 id 都返回 200 与全 0 的 total_api_keys、active_api_keys、total_requests、total_cost（`handler/admin/group_handler.go:913-933`，注释 TODO）。Web 只在 `frontend/src/api/admin/groups.ts:248-261` 定义了 getStats，全仓没有调用方，填真实值不影响 Web。该路由目前对 vendor 可达（白名单 GET `/admin/groups` 前缀，`server/middleware/vendor_routes.go:140`）。
2. 计数方法已在仓储层，只是没接上：apiKeyRepository.CountByGroupID（`repository/api_key_repo.go:740-744`，不含软删）；userSubscriptionRepository.CountByGroupID / CountActiveByGroupID（`repository/user_subscription_repo.go:533-549`，active 口径为 status=active 且 expires_at>now），后两者没有在 UserSubscriptionRepository 接口（`service/user_subscription_port.go:10`）里声明。
3. dto.AdminGroup 没有 Key 数和订阅数（`handler/dto/types.go:167-206`）。
4. groups/:id/subscriptions 只支持分页（`handler/admin/subscription_handler.go:307-330` → `repository/user_subscription_repo.go:214-236`），返回全部状态但不含已撤销；`GET /admin/subscriptions` 已支持 group_id 与 status，active 带实时到期判断（`subscription_handler.go:63-99`；`user_subscription_repo.go:238-280`）。
5. 今日用量已支持：`GET /admin/dashboard/groups?start_date&end_date&group_id`（`handler/admin/dashboard_handler.go:257-278`）与 `GET /admin/groups/usage-summary`（`group_handler.go:935-969`）。

**建议改法**：保留原有 4 个字段并填真实值，另增字段：

```json
{"code":0,"message":"success","data":{"total_api_keys":38,"active_api_keys":35,"total_requests":1203344,"total_cost":186420.55,"subscriptions_total":12,"subscriptions_active":9,"generated_at":"2026-10-18T02:00:00Z"}}
```

- total_api_keys：group_id=:id 且未软删，等于 groups/:id/api-keys 的 total；active_api_keys 再要求 status='active'。
- subscriptions_total：未撤销的全部状态，等于 groups/:id/subscriptions 的 total；subscriptions_active：status=active 且 expires_at>now，与 `/admin/subscriptions?status=active` 同口径；标准（余额）分组为 0。
- total_requests / total_cost：全时段，取 usage-summary 同一份 rollup（`repository/usage_log_repo_trend.go:802-804`）；rollup 没有请求数时 total_requests 保持 0 并在文档注明，App 不依赖它。
- 错误：400 Invalid group ID；404 `GROUP_NOT_FOUND`（现在不存在的 id 也返回 200）；403（vendor：Key 数、订阅数属于站长统管的客户数据，与 groups/:id/api-keys 同等对待）。
- 不改 groups/:id/subscriptions：按状态筛选用 `GET /admin/subscriptions?group_id=:id&status=…`；今日用量继续用 dashboard/groups 与 usage-summary。

**实现提示**：`group_handler.go:913-933` 的 GetStats 改调新增的 adminService.GetGroupStats(ctx, id)。实现放 `service/admin_group.go`：requireGroupAccess(id)；像 GetGroupAPIKeys（`admin_group.go:1406-1419`）那样在 `ScopeFromContextOrDeny(ctx).IsVendor()` 时返回 domain.ErrWorkspaceScopeViolation；用 errgroup 并行跑 4 个 COUNT（apiKeyRepo.CountByGroupID、在 `api_key_repo.go` 新增 CountActiveByGroupID、把订阅两个 Count 加进接口、rollup 读取）。路由层把 `"/api/v1/admin/groups/:id/stats"` 加进 vendorDeniedRoutes（`server/middleware/vendor_routes.go:40-43`）。4 个按 group_id 走索引的 COUNT 加一次 rollup，可以不缓存。测试：stats 与 api-keys / subscriptions 的 total 一致；不存在 id 返回 404；vendor 返回 403。

**App 退路**：分组详情和删除确认按需各发几个请求：Key 数 `GET /admin/groups/:id/api-keys?page=1&page_size=1` 读 data.total；订阅总数 `GET /admin/groups/:id/subscriptions?page_size=1` 读 total；生效订阅 `GET /admin/subscriptions?group_id=:id&status=active&page_size=1` 读 total；今日用量 `GET /admin/dashboard/groups?start_date=今天&end_date=今天&group_id=:id` 加 `GET /admin/groups/usage-summary`。列表滑动“停用”“删除”时在弹出确认框那一刻再拉，不为整个列表预取。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/groups/1/stats"`：total_api_keys 等于 `/admin/groups/1/api-keys?page_size=1` 的 total；subscriptions_total 等于 `/admin/groups/1/subscriptions?page_size=1` 的 total；subscriptions_active 等于 `/admin/subscriptions?group_id=1&status=active&page_size=1` 的 total；撤销一条订阅后 subscriptions_total 减 1；不存在的分组 id 返回 404，vendor 返回 403；Web 分组页行为不变。

---

#### F03 · （安全）vendor 可读任意分组的订阅列表（含终端用户信息） 〔P1 · 安全修复〕

**页面**：无 App 依赖；核实分组接口时发现。

**背景**：`server/middleware/vendor_routes.go:95-97` 的注释写明订阅、用户管理为站长专属。

**现状**：`GET /api/v1/admin/groups/:id/subscriptions` 注册在挂了 vendor 中间件的 admin 组下（`server/routes/admin.go:31,750`）。它的 FullPath 命中白名单前缀 `/api/v1/admin/groups` 的 GET 规则（permitGroupRead，`vendor_routes.go:140`），又不在 vendorDeniedRoutes 里（:40-43 只排除了 api-keys、rate-multipliers、rpm-overrides、channel-monitor-v2 等）。handler（`handler/admin/subscription_handler.go:309-330`）、service（`service/subscription_service.go:807-816`）、repo（`repository/user_subscription_repo.go:214-236`，WithUser）都没有 vendor 判断，也没有 requireGroupAccess，连未授权给它的分组也能读。`vendor_routes_guard_test.go` 没覆盖这条路由。

**建议改法**：把 `"/api/v1/admin/groups/:id/subscriptions"` 加进 vendorDeniedRoutes；ListGroupSubscriptions 里加 IsVendor 拒绝（返回 403，与 groups/:id/api-keys 相同）；补守卫测试。admin 行为不变。

**实现提示**：vendorDeniedRoutes 加一行 `{prefix: "/api/v1/admin/groups/:id/subscriptions", methods: allMethods}`；service 层参照 GetGroupAPIKeys（`service/admin_group.go:1406-1419`）的 ScopeFromContextOrDeny 写法。同时检查 `/api/v1/admin/users/:id/subscriptions`（`server/routes/admin.go:753`）——它不在 vendor 白名单前缀里，默认已拒，可在测试里一并断言。

**App 退路**：不适用。

**验收**：vendor JWT 调 `GET /api/v1/admin/groups/<任意 id>/subscriptions` 返回 403；admin 照常返回列表；`go test ./internal/server/middleware/...` 新增用例通过。

---

#### F04 · dto.AdminGroup 增加 error_account_count 与 idle_account_count（暂停 · 停用），四类成员计数一次给齐 〔P2 · 加字段〕

**页面**：分组列表（可用 x/y、逐账号色格条、需处理 / 正常 / 停用分段）；分组详情状态卡与图例（可用 / 受限 / 错误 / 暂停·停用）。

**背景**：每个分组要显示 4 个桶的数量：可用、受限（限流、过载、临时不可调度）、错误、暂停·停用（`html-preview/layouts/main/v-groups.jsx:26-34,185-191`）以及每个账号一格的色格条（:145-151）。色格条按桶排序着色（gvByBucket，:120），格子不带账号身份，4 个计数就能画出来。

**现状**：
1. AdminGroup 只有 account_count、active_account_count、rate_limited_account_count，都带 omitempty，值为 0 时字段不出现（`handler/dto/types.go:199-202`；simple 模式在 `handler/admin/group_handler.go:147-149`）。
2. 口径来自 `repository/group_repo.go:979-998` 的 SQL，聚合在 loadAccountCounts（:1001-1042）与 LoadAccountCountsScoped（:1050-1100）：total = 未删除；active = status=active 且 schedulable、未到期自动暂停、没有限流 / 过载 / 临时不可调度窗口；rate_limited = 同样前提但处在任一窗口中。没有错误数，也没有暂停 / 停用数。
3. ops/account-availability 有 error_count 但不能代替：要开启运维与实时监控（`handler/admin/ops_realtime_handler.go:122-136`）、rate_limit_count 不含过载和临时不可调度（`service/ops_account_availability.go:91-108`）、会全量加载账号（:24）。

**建议改法**：`GET /api/v1/admin/groups`、`/admin/groups/all`、`/admin/groups/:id` 的分组对象（及 simple 模式分组响应）新增 `"error_account_count":1`（deleted_at IS NULL AND status='error'）与 `"idle_account_count":2`（其余：停用、停止调度、到期自动暂停），保证 account_count = active + rate_limited + error + idle。新字段不加 omitempty，App 可按字段是否存在判断后端是否已支持。需要时再把 idle 拆成 paused_account_count 与 inactive_account_count。

**实现提示**：`group_repo.go` 的 loadAccountCounts（:1001）与 LoadAccountCountsScoped（:1050）加一列 `COUNT(*) FILTER (WHERE a.deleted_at IS NULL AND a.status = 'error') AS error_count`，idle 在 Go 里算（total − active − rate_limited − error）。结构体：groupAccountCounts（`group_repo.go:973-977`）、service.GroupAccountCounts（`service/group_service.go:78-82`）、service.Group（`service/group.go:141-144`）；赋值点 `group_repo.go:259-264,517-523,604-608,688-694,761-767`；vendor 重算 rescopeGroupAccountCounts（`service/admin_group.go:150-158`）；输出 dto.AdminGroup（`handler/dto/types.go:199-202`）与 `handler/dto/mappers.go:166-168`、simpleModeGroupResponse 与 groupForSimpleMode（`group_handler.go:147-149,161-163`）。仍是同一条聚合 SQL，只多一个 FILTER；按账号数排序的路径（listWithAccountCountSort，`group_repo.go:530`）不受影响。

**App 退路**：一次请求就能算准：`GET /admin/accounts?status=error&lite=1&page_size=1000`（错误账号通常很少），按每个账号的 group_ids 统计各分组错误数；idle = account_count − active_account_count − rate_limited_account_count − error（缺失的计数字段按 0）。这几个桶两两不相交，结果准确。分组详情本来就要拉 `GET /admin/accounts?group=:id`，可在客户端直接分桶。

**验收**：把分组 3 的一个成员设为 error，`GET /api/v1/admin/groups/3` 返回 error_account_count=1；把一个成员停止调度，idle_account_count 加 1；`/admin/groups/all?include_inactive=true` 每个分组四项之和等于 account_count；计数为 0 时字段仍在；vendor 视角下四项都按本工作区重算。

---

#### F05 · `GET /api/v1/admin/groups/capacity-summary` 增加可选 group_id / group_ids 参数 〔P2 · 加参数〕

**页面**：分组详情容量区（并发 / 会话 / 调度 RPM）。

**背景**：分组详情只需要本组容量（`html-preview/layouts/main/v-groups.jsx:80-91,122-129`），并会在前台轮询刷新。

**现状**：capacity-summary 不接受任何参数（`handler/admin/group_handler.go:970-994`）→ GetAllGroupCapacity 计算所有启用分组（`service/group_capacity_service.go:70-94`，含批量 SQL 与 Redis 批量读）。现有原生 App 拉全部后本地过滤（`sub2-mobile-native/NativeApp/Features/GroupsView.swift:244-255`）。

**建议改法**：`GET /api/v1/admin/groups/capacity-summary?group_id=3`（也支持 `group_ids=1,2,3`）。响应形状不变，仍是数组：`[{"group_id":3,"concurrency_used":5,"concurrency_max":8,"sessions_used":5,"sessions_max":6,"rpm_used":26,"rpm_max":120}]`。停用分组返回 `[]`（与现在全量结果里没有它一致）；启用但没有可调度账号的分组返回全 0 行；参数非法 400 `INVALID_GROUP_ID`；不存在或无权访问 404；不带参数时与现在完全一致。

**实现提示**：handler 解析 group_id / group_ids；`service/group_capacity_service.go` 新增 GetGroupCapacityByIDs(ctx, ids)：与 listActiveGroupIDs（:96-110）取交集；有 groupCapacityAccountLister 时直接调 getGroupCapacitiesBatch(ctx, ids, lister)（:131）；降级路径保持现有 vendor 拒绝逻辑（:88-90）。保留 filterByGroupScope 的 vendor 行过滤；带 id 时先 requireGroupAccess。计算量从“全部启用分组”降到“1 个分组”。

**App 退路**：继续拉全部、按 group_id 本地过滤（数据量很小，代价主要在服务端）。

**验收**：`curl -s -H "x-api-key: $ADMIN_KEY" "$BASE/api/v1/admin/groups/capacity-summary?group_id=3"` 等于全量列表里 group_id=3 那一行；group_ids=1,3 返回两行；停用分组返回 `[]`；group_id=abc 返回 400；不带参数时响应与改前逐字节一致。

---

### G 资金与兑换码

#### G01 · 三个资金写接口（余额调整、批量生成兑换码、create-and-redeem）改为脱离请求上下文执行；失去租约的 processing 幂等记录允许接管 〔P0 · 改行为〕

**页面**：用户详情 / 快捷充值 / 大数字键盘（充值、退款）；批量生成兑换码向导；发放兑换码（补偿）；概览待处理“待核对”。

**背景**：充值、退款、批量生成、发放补偿在手机上最容易遇到超时、切后台、断网。设计稿约定：结果不明时不让用户重新发起，只能核对或用同一编号（Idempotency-Key）重试——服务器做过就返回原结果，没做过就执行一次（`html-preview/shared/core.jsx:461-464`、`html-preview/layouts/main/00-core.jsx:124-143,503-515`、`html-preview/layouts/main/v-modules.jsx:1102-1150`）。这要求客户端断开后服务器仍能把这次执行的结果写进幂等记录。

**现状**：
- 三个接口都用 executeAdminIdempotentJSON，ExecutionTimeout 固定为 0：`handler/admin/user_handler.go:457`、`handler/admin/redeem_handler.go:145`、`handler/admin/redeem_handler.go:203`；helper 在 `handler/admin/idempotency_helper.go:78-86`（:85 传 0）。
- 超时为 0 时 coordinator.Execute 拿到的是 c.Request.Context()（`idempotency_helper.go:57`），不会 WithoutCancel（`service/idempotency.go:208-212` 只在 ExecutionTimeout>0 时生效）；业务执行（:413）与结果保存（`persistCtx := ctx` :414；MarkFailedRetryable :433、MarkSucceeded :450）都用请求上下文。余额事务同样建立在这个 ctx 上（`service/admin_user.go:663` Tx(ctx)，:748 Commit）。断连后要么事务回滚、要么事务已提交，两种情况下记录都可能停在 processing。
- processing 状态不看 locked_until，一律返回 409 IDEMPOTENCY_IN_PROGRESS（`service/idempotency.go:354-357`）；租约过期后 Retry-After 退化为 1 秒（:506-515），要等 expires_at（默认 24 小时：:72、`config/config.go:2423`）过后才走过期接管（:299-314）。
- 现成能力：executeAdminIdempotentJSONWithTimeout（`idempotency_helper.go:88-97`），订阅 bulk-action 在用（`handler/admin/subscription_handler.go:202`，2 分钟）；分离执行、租约续期（`service/idempotency.go:403-406,466-504`）、断开后仍落库（:414-422，5 秒独立上下文）都有测试（`service/idempotency_detached_test.go:35-74`）。
- 临时 overlay 探针（`go test -overlay`，没改源码）：用尊重 ctx 取消的仓储模拟断连，ExecutionTimeout=0 时首个请求得到 IDEMPOTENCY_STORE_UNAVAILABLE，租约过期后重试仍是 IDEMPOTENCY_IN_PROGRESS，记录停在 processing；ExecutionTimeout=30s 时记录为 succeeded，重试返回重放结果，业务只执行 1 次。
- 提交后的副作用也用请求 ctx，断连就丢：afterBalanceAdjustmentCommit 的缓存失效与邀请返利（`service/admin_user.go:748-753,818-835,1049-1065`；AccrueInviteRebate 用这个 ctx 访问数据库，`service/affiliate_service.go:338-354`），失败只记一条日志（`admin_user.go:1058-1060`），不会补发；create-and-redeem 的兑换后返利同理（`service/redeem_service.go:571-616`）。

**建议改法**（不新增接口，不改请求和响应格式，只改执行语义）：
1. 三个接口都改为带 ExecutionTimeout 执行：`POST /api/v1/admin/users/:id/balance` 与 `POST /api/v1/admin/redeem-codes/create-and-redeem` 用 executeAdminIdempotentJSONWithTimeout（30s，仍强制 key：Web 的余额调整本来就带 key，`frontend/src/api/admin/users.ts:25-39`；create-and-redeem 没有 Web 调用方）；`POST /api/v1/admin/redeem-codes/generate` 用不强制 key 的带超时变体（60s，新增，见下），因为 Web 生成兑换码不带 Idempotency-Key（`frontend/src/api/admin/redeem.ts:92`），强制版本在关闭 observe_only 后会让 Web 报 IDEMPOTENCY_KEY_REQUIRED（见 H08）。受理后客户端断开，不再中断业务与结果落库。
2. （建议同批）给业务层自己能去重的 scope 打开“接管失去租约的 processing”：status=processing 且 locked_until ≤ now（执行方已死，活着的执行每 10s 续租）时 TryReclaim(fromStatus=processing) 后重新执行。余额靠 action_id 账本去重，create-and-redeem 靠 code 去重；generate 要等 G03 的 batch_id 去重落地后再打开。

同 key 重试的语义（App 照此实现）：
- 已成功：200，响应头 `X-Idempotency-Replayed: true`，data 为首次结果。
- 仍在执行：409 `{"code":409,"message":"idempotent request is still processing","reason":"IDEMPOTENCY_IN_PROGRESS","metadata":{"retry_after":"12"}}`，响应头 `Retry-After: 12`（剩余租约，最多 30）。
- 执行失败、仍在退避期：409 `IDEMPOTENCY_RETRY_BACKOFF`；退避过后重新执行。
- 同 key 不同请求体：409 `IDEMPOTENCY_KEY_CONFLICT`。
- 租约失效的 processing：做了第 2 步后被接管执行，不再一卡 24 小时。

Web 不受影响：不带 key 时 observe_only=true 下照常直接执行（`service/idempotency.go:221-229`）；generate 改成不强制 key 后，observe_only=false 时 Web 也照常可用；带 key 的语义不变，只是断连后结果也能落库。

**实现提示**：
- 余额与 create-and-redeem 改为 `executeAdminIdempotentJSONWithTimeout(c, <原 scope>, <原 payload>, service.DefaultWriteIdempotencyTTL(), <超时>, <原闭包>)`；generate 新增一个 RequireKey:false 且传 ExecutionTimeout 的 helper（与 G06 建议的“可选幂等 + 超时”变体是同一个；G03 要自己处理重放，所以还需要返回 result 的版本，例如 executeAdminOptionalIdempotentWithTimeout）。现有的 executeAdminOptionalIdempotentJSON 不传 ExecutionTimeout（`handler/admin/idempotency_helper.go:108-145`），不能直接用。scope 与 payload 不变，已有记录照常兼容；可加常量 adminMoneyWriteExecutionTimeout。
- 闭包里继续读 c（withAdminAdjustmentMetadata 读 header、IP，`user_handler.go:740-760`）是安全的：handler 会阻塞到 Execute 返回。分离后的 ctx 用 WithoutCancel，保留 ctxkey.RequestID 等值，账本里的 request_id 不受影响；提交后的副作用随之改用分离 ctx，一并修好（补测试覆盖返利不丢）。
- 第 2 步：IdempotencyExecuteOptions（`service/idempotency.go:81-93`）加 `ReclaimStaleProcessing bool`；在 :354 的 `case IdempotencyStatusProcessing` 里，开启且 existing.LockedUntil 已过期时调 `c.repo.TryReclaim(ctx, existing.ID, IdempotencyStatusProcessing, now, lockedUntil, expiresAt)`（仓储 SQL 已支持 fromStatus + locked_until<=now，`repository/idempotency_repo.go:105-121`），成功后 record.ID=existing.ID 继续执行，失败仍按 in_progress 返回。只能与 ExecutionTimeout>0 一起用（租约续期只在这种情况下启动）；helper 层需要一个能传这个选项的变体，例如 executeAdminIdempotentJSONWithOptions。
- 余额重复执行的保护已有：同一个 key 推导出的 action_id 是确定的（`user_handler.go:762-773`），事务内加 advisory 锁并按 action_id 计数（`service/admin_user.go:849-861`、`repository/admin_user_adjustment_repo.go:63-90`），已存在就直接返回用户。create-and-redeem 按 code 去重（`redeem_handler.go:204-206,239-266`）。
- 租约 30s（processing_timeout_seconds），续租间隔 min(lease/3, ttl/3)。ExecutionTimeout 不要比反向代理超时还长，否则代理先断开，客户端只能靠重试拿结果（这种情况本身也正确）。

**App 退路**：同 key 重试时 IDEMPOTENCY_IN_PROGRESS 连续超过约 30 秒（Retry-After 变成 1）就认定记录卡住，停止自动重试，转为“待核对”。余额：发请求时带 `X-Request-ID=操作 UUID`（≤ 64 字节，服务器会存进账本 request_id：`server/middleware/request_logger.go:24-28`、`user_handler.go:754-758`），核对时 `GET /admin/user-adjustments?keyword=<用户邮箱>&kind=balance&start_time=<发起前 2 分钟>&end_time=<现在>`，在客户端比对 items[].request_id。create-and-redeem：`GET /admin/redeem-codes?search=<App 生成的 code>` 看 status、used_by；也可以换新 key、沿用同一个 code 重发（服务器按 code 去重）。批量生成：只能按 sort_by=created_at 与发起时间在列表里找，找不到就提示去 Web 核对，不能自动重发。

**验收**：
1. Go 测试（仿 `idempotency_detached_test.go`）：在 `internal/handler/admin` 用 gin + 一个检查 ctx.Err() 的幂等仓储，让桩服务在执行中取消请求 ctx；三个接口都断言记录为 succeeded、同 key 第二次请求 200 且带 X-Idempotency-Replayed: true、业务桩只调用 1 次。
2. 第 2 步：手工把记录置为 processing 且 locked_until=过去时间，同 key 重试被接管执行；余额桩看到 action_id 已存在，直接返回、不重复入账。
3. 手工：

```bash
KEY=$(uuidgen)
curl -sS -D - -X POST "$BASE/api/v1/admin/users/42/balance" -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: $KEY" \
  -H 'Content-Type: application/json' -d '{"balance":"1.00","operation":"add","notes":"t"}' --max-time 0.05
```

   再用同样的 key 和 body、不带 --max-time 发一次：200 且带 X-Idempotency-Replayed: true（或先 409、Retry-After ≤ 30，再变 200），不会持续 409。
4. SQL：`SELECT scope,status,locked_until FROM idempotency_records WHERE scope LIKE 'admin.%' AND status='processing' AND locked_until < NOW() - interval '1 minute';` 为空。

---

#### G02 · 写入结果可确定核对：user-adjustments 增加 request_id / action_id / user_id 精确过滤，余额接口回传 action_id 和幂等过期时间（可选：按 Idempotency-Key 只查不执行） 〔P1 · 加参数〕

**页面**：概览待处理“充值结果待核对”“兑换码生成结果待核对”；用户详情核对横幅与核对按钮；兑换码生成待核对 sheet；调整余额“结果待确认的请求”；设置与登录页的待核对余额列表。

**背景**：请求没有应答时（可能隔天才处理），设计稿里的“核对”必须只查不执行，并能确定地回答“这次有没有执行、结果是什么”；“用同一编号重试”才会执行（`html-preview/layouts/main/v-modules.jsx:1102-1150`）。现有原生 App 只能冻结原请求、人工确认后重放（`sub2-mobile-native/NativeApp/Features/UsersView.swift:460-471,513-545`；`sub2-mobile-native/docs/API_COMPATIBILITY.md:44`）。

**现状**：
- 可以利用：管理员余额调整都写进永久、只追加的账本 admin_user_adjustments（`migrations/223_admin_user_adjustments.sql:1-24`，:99-112 用触发器禁止改删），列表返回 action_id、request_id、before_value、after_value、delta（十进制字符串，`service/admin_user_adjustment.go:75-97`）；request_id 取自请求头 X-Request-ID（去空格后 ≤ 64 字节，`server/middleware/request_logger.go:14,24-28`、`server/middleware/request_metadata.go:9,27-30`），经 withAdminAdjustmentMetadata 写入账本（`handler/admin/user_handler.go:754-758`；`service/admin_user.go:921`）。发放补偿：code 由 App 生成，`GET /admin/redeem-codes?search=<code>`（码值包含匹配，`repository/redeem_code_repo.go:178-185`）能永久查到 status、used_by、used_at，已能确定核对。
- 缺口：没有按 Idempotency-Key 查幂等记录的接口（GetByScopeAndKeyHash 只在内部用，`service/idempotency.go:278,316`）；user-adjustments 只能按 kind、operation、direction、keyword、operator、start_time、end_time 过滤（`handler/admin/user_adjustment_handler.go:137-173`、`repository/admin_user_adjustment_repo.go:92-130`），keyword 用 `user_id::text ILIKE '%1%'` 会同时命中 10、21，没有 request_id、action_id、user_id 精确过滤；`POST /admin/users/:id/balance` 只返回用户 DTO（`user_handler.go:457-464`），不带 action_id，action_id 是由 key、操作人和请求指纹推导的 UUIDv5（:762-773），客户端难以自己算；幂等记录默认保留 24 小时（`service/idempotency.go:72`），响应不告诉客户端何时过期。

**建议改法**：

必做（只增）：
- A. `GET /api/v1/admin/user-adjustments` 与 `/export` 增加等值过滤 `request_id`（≤ 64 字符）、`action_id`（UUID）、`user_id`（正整数，与 E10 同一项），与现有参数叠加，summary 按同口径统计。参数错误 400："action_id must be a UUID"、"user_id must be a positive integer"、"request_id cannot exceed 64 characters"。

```json
{"code":0,"data":{"items":[{"id":901,"action_id":"5b1d…","kind":"balance","operation":"add","requested_value":"50.00000000","delta":"50.00000000","before_value":"12.50000000","after_value":"62.50000000","user_id":42,"request_id":"7c0e2f1a-…","notes":"补偿","source":"admin_balance","created_at":"2026-10-17T09:41:02Z"}],"total":1,"page":1,"page_size":20,"pages":1,"summary":{}}}
```

- B. `POST /api/v1/admin/users/:id/balance` 响应头增加 `X-Admin-Adjustment-Action-ID: <uuid>`，首发与重放都带；body 不变。
- C. 带 Idempotency-Key 的写接口响应头增加 `X-Idempotency-Expires-At: <RFC3339>`，App 据此判断何时只能走账本核对。

可选（P2）：
- D. `GET /api/v1/admin/idempotency-records/lookup?scope=admin.users.balance.update`，用请求头 Idempotency-Key 传 key，只查不执行，只返回当前管理员自己的记录：`{"found":true,"status":"succeeded|processing|stale|failed_retryable","created_at":"…","updated_at":"…","expires_at":"…","locked_until":null,"error_reason":null,"response":{…保存的响应，已脱敏…}}`；没有或已过期返回 `{"found":false}`；scope 用白名单限制；key 非法 400 `IDEMPOTENCY_KEY_INVALID`。

后端改完后的核对口径：余额查 request_id（App 带 X-Request-ID=操作 UUID）；批量生成查 G03 的 batch_id；发放补偿查 search=<code>。三条都不受 24 小时限制。

**实现提示**：A：AdminUserAdjustmentFilter（`service/admin_user_adjustment.go:99-107`）加 ActionID、RequestID、UserID；parseUserAdjustmentFilter 解析校验；adjustmentWhere（`repository/admin_user_adjustment_repo.go:92-130`）加 `action_id = $n`、`request_id = $n`、`user_id = $n`，List 与 Stream 共用，导出自动生效。action_id、user_id 已有索引（`migrations/223_admin_user_adjustments.sql:49-59`）；request_id 新增迁移 `CREATE INDEX IF NOT EXISTS idx_admin_user_adjustments_request_id ON admin_user_adjustments (request_id) WHERE request_id IS NOT NULL;`。B：在 `user_handler.go:450-456` 构造好 idempotencyPayload 后调 `adminAdjustmentActionID(c, "admin.users.balance.update", idempotencyPayload)`，拿到确定值先 `c.Header("X-Admin-Adjustment-Action-ID", id.String())` 再进入 executeAdminIdempotentJSON，与 withAdminAdjustmentMetadata 算出的是同一个值；余额没变化（diff=0）不写账本，按 action_id 查不到属正常。C：IdempotencyExecuteResult（`service/idempotency.go:95-98`）加 ExpiresAt，Execute 在 MarkSucceeded 或重放时填上，`idempotency_helper.go:197-200` 设响应头。D：迁移给 idempotency_records 加 `actor_scope VARCHAR(64) NULL`，CreateProcessing（`repository/idempotency_repo.go:21-51`）写入 opts.ActorScope，新增 GetByScopeKeyAndActor，路由放在 registerUserAdjustmentRoutes 旁并挂 AdminOnly；旧记录 actor 为空，一律当作 found:false。D 必须按 actor 过滤，防止管理员互相看到响应体。

**App 退路**：现在就能做的确定核对：余额每次写入都带 X-Request-ID=操作 UUID（App 目前没发这个头，`sub2-mobile-native/Sources/Sub2Core/APIClient.swift:190`），核对时 `GET /admin/user-adjustments?keyword=<完整邮箱>&kind=balance&start_time=<发起前 2 分钟>&end_time=<现在>&page_size=200` 在客户端按 request_id 精确匹配（先确认响应头回显的 X-Request-ID 与发出的一致，排除反向代理覆盖）；发放补偿用 search=<code>；批量生成见 G03；超出幂等保留期又匹配不上时提示去 Web 对账。

**验收**：
- 单测：非法 action_id、user_id=0、超过 64 字符的 request_id 返回 400；仓储测试中 user_id=1 不命中 10、21。
- curl：

```bash
RID=$(uuidgen); KEY=$(uuidgen)
curl -sS -D - -X POST "$BASE/api/v1/admin/users/42/balance" -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: $KEY" -H "X-Request-ID: $RID" \
  -H 'Content-Type: application/json' -d '{"balance":"5","operation":"add","notes":"t"}'
curl -sS "$BASE/api/v1/admin/user-adjustments?request_id=$RID" -H "Authorization: Bearer $TOKEN"
```

  第一条响应头带 X-Admin-Adjustment-Action-ID 与 X-Idempotency-Expires-At；第二条 total=1，items[0].action_id 等于上面的响应头；同 key 重放时 action_id 不变、账本仍只有 1 行；D（如果做）：另一位管理员用同一 key 查询得到 found:false。

---

#### G03 · 批量生成兑换码：整批一个事务 + batch_id 业务去重 + 备注与创建人；列表支持按 batch_id、创建时间、备注过滤；重放返回真实码值 〔P1 · 改行为〕

**页面**：批量生成兑换码分步向导；“生成结果待核对”与核对结果 sheet；兑换码列表“核对”横幅与搜索；概览待处理。

**背景**：向导生成后没收到应答时，要准确找到“这一批”：有没有生成、生成了几个，并完整拿回码值；“用同一编号重试”必须保证不会生成第二批；还希望按活动批次或工单号管理并带备注（`html-preview/layouts/main/v-modules.jsx:46,652-686,1102-1150`；`DECISIONS.md:91`）。

**现状**：
- GenerateRedeemCodes 循环调 redeemCodeRepo.Create，没有开事务（`service/admin_user.go:1738-1763`）：中途失败留下半批、handler 却返回错误，记录随后变为 failed_retryable，同 key 重试会再生成整整一批。
- 业务层没有去重；幂等记录过期后会被接管重新执行（`service/idempotency.go:299-314`；测试 `service/idempotency_test.go:231` TestIdempotencyCoordinator_ReclaimExpiredSucceededRecord）。
- 请求只有 count、type、value、group_id、validity_days、expires_at、expires_in_days（`handler/admin/redeem_handler.go:36-44`）；没有 notes、批次号；表里没有批次和创建人列（`ent/schema/redeem_code.go:38-73`，索引在 :94-97，没有 created_at 索引）。
- 列表只能按 type、status、search 过滤，search 只匹配码值和使用者邮箱，不搜备注（`redeem_handler.go:86-110`、`repository/redeem_code_repo.go:148-185`）；排序支持 created_at（:211-239），但没有 created_after 之类的时间过滤。
- 幂等结果落库前经过 logredact，而 `"code"` 在默认敏感键里（`util/logredact/redact.go:14-23,86-95,198-216`；`service/idempotency.go:517-527`）：用同一编号重试拿到的重放结果里每个码都是 `"code":"***"`，id 等字段完整（临时 overlay 探针已证实）。create-and-redeem 的重放同理。
- 码值是 32 位十六进制（`service/redeem_code.go:53-58`）。

**建议改法**：
1. `POST /api/v1/admin/redeem-codes/generate` 请求体增加可选字段（Web 不传时行为不变）：

```json
{"count":20,"type":"balance","value":10,"expires_in_days":30,"notes":"双 11 活动 #A123","batch_id":"2f6c9a0e-8f1b-4c43-9d0e-6a1b2c3d4e5f"}
```

   notes ≤ 1000 字，写到每个码上；batch_id 为 UUID（由 App 生成，等于操作编号），不传时服务器用 Idempotency-Key 推导确定的 UUIDv5，没有 key 时随机生成。前缀设计已定不做。
2. 语义：整批一个事务。同一 batch_id 已存在、且 type、value、count、group_id、validity_days、创建人都一致时，直接返回已有整批（真实码值），不新建，不受幂等 24 小时限制；参数不一致返回 409 `{"reason":"REDEEM_BATCH_CONFLICT","message":"batch_id already used with different parameters"}`；batch_id 非法 400 `REDEEM_BATCH_ID_INVALID`。
3. 响应仍是数组（Web 依赖数组），每项增加 `batch_id`、`created_by`（管理员 ID），并加响应头 `X-Redeem-Batch-ID`；重放时也返回真实码值。
4. `GET /api/v1/admin/redeem-codes` 与 `/export` 增加 `batch_id`、`created_from`、`created_to`（RFC3339）、`created_by`、`notes`（备注包含匹配，≤ 100 字）参数；search 语义不变。例：`GET /api/v1/admin/redeem-codes?batch_id=2f6c…&page_size=100` → `{items:[{id, code, type, value, status, batch_id, created_by, notes, created_at, …}], total:20, …}`。

**实现提示**：
- 迁移 `migrations/2xx_redeem_code_batches.sql`（编号见 1.3：origin/main 当前最大 246，从 247 起；本文 C02、C09、D06、E10 等也要加迁移，按实际落地顺序顺延）：`ALTER TABLE redeem_codes ADD COLUMN IF NOT EXISTS batch_id UUID, ADD COLUMN IF NOT EXISTS created_by BIGINT;`、`CREATE INDEX IF NOT EXISTS idx_redeem_codes_batch_id ON redeem_codes(batch_id) WHERE batch_id IS NOT NULL;`、`CREATE INDEX IF NOT EXISTS idx_redeem_codes_created_at ON redeem_codes(created_at DESC, id DESC);`；`ent/schema/redeem_code.go` 加 Optional().Nillable() 字段后 `go generate ./ent`。
- service.RedeemCode 加 BatchID、CreatedBy；dto 只在 AdminRedeemCode（`handler/dto/types.go:530-534`）加 batch_id、created_by（omitempty），普通用户接口不暴露；映射在 `handler/dto/mappers.go:634-659`。
- GenerateRedeemCodesRequest / Input 加 Notes、BatchID、CreatedBy（来自 getAdminIDFromContext(c)）；key 推导复用 adminAdjustmentActionID 的算法（`user_handler.go:762-773`），scope 用 admin.redeem_codes.generate。
- GenerateRedeemCodes（`service/admin_user.go:1718-1765`）：分组校验放事务外；`tx := s.entClient.Tx(ctx)`、`opCtx := dbent.NewTxContext(ctx, tx)`；先对 batch_id 加 `pg_advisory_xact_lock(hashtextextended($1::text,0))`（写法同 `repository/admin_user_adjustment_repo.go:86-90`）；按 batch_id 查询，已存在就校验后返回；否则逐个 redeemCodeRepo.Create(opCtx, …)（clientFromContext 会自动走事务，`repository/redeem_code_repo.go:26-45`），最后 Commit。count ≤ 100，逐条插入可接受且能拿回 id。
- handler Generate（`redeem_handler.go:132-164`）改用 G01 新增的“不强制 key、带 ExecutionTimeout、返回 result”的幂等 helper（RequireKey:false，Web 不带 key，理由见 H08）；result.Replayed 为 true 时按事先算好的 batch_id 重新查库返回真实码值（参照 `handler/admin/account_handler.go:1114` 自己处理重放）。batch 去重落地后就可以对这个 scope 打开 G01 第 2 步。create-and-redeem 的重放也按 code 重新查库返回真码。
- 列表过滤：新增 service.RedeemCodeListFilter 与仓储方法 ListWithFilter；旧的 ListWithFilters 保留并委托给新方法，AdminService 接口新增方法而不改旧签名（与 G04 共用）。

**App 退路**：生成前把 Idempotency-Key 与参数保存在本机；无应答时先用同一个 key 重试（G01 修好前可能卡在 409）；重放里的 code 是 `***`，要按返回的 id 再取真码（`GET /admin/redeem-codes/:id`，或 `GET /admin/redeem-codes?sort_by=id&sort_order=desc&page_size=100` 后按 id 匹配）。不想执行时的核对：按 sort_by=created_at 加发起时间窗，用 type、value、数量启发式匹配，并提示另一位管理员同时生成时可能分不清。备注生成后用 batch-update 补写 notes。

**验收**：单测：仓储第 5 次 Create 失败时库里没有这一批的任何行；同一 batch_id 调两次（中间删除幂等记录，模拟 24 小时后）第二次返回相同的 id 列表、行数不变；同 batch_id 不同 value 返回 409 REDEEM_BATCH_CONFLICT；同 key 重放响应里的 code 是 32 位十六进制而不是 `***`。curl：`BID=$(uuidgen); curl -sS -X POST "$BASE/api/v1/admin/redeem-codes/generate" -H "Idempotency-Key: $BID" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"count\":3,\"type\":\"balance\",\"value\":1,\"notes\":\"t\",\"batch_id\":\"$BID\"}"`，然后 `curl -sS "$BASE/api/v1/admin/redeem-codes?batch_id=$BID" -H "Authorization: Bearer $TOKEN"` → total=3。Web 生成表单不传新字段，结果数组照常显示。

---

#### G04 · 兑换码列表、导出、统计支持多类型过滤（types / exclude_types），能排除管理员调整兼容记录 〔P1 · 加参数〕

**页面**：兑换码列表（全部、状态胶囊计数、类型菜单）。

**背景**：手机端兑换码列表只列真正发出去的四类码（余额、并发、订阅、邀请），“全部”与各状态胶囊的数字要准确（`html-preview/layouts/main/v-modules.jsx:589-599`）。

**现状**：每次管理员调整余额或并发，都会往 redeem_codes 写一条 type=admin_balance / admin_concurrency、status=used 的兼容记录（`service/admin_user.go:881-931`，:901-914；兼容路径 :807-812；常量 `domain/constants.go:104-105`）。列表的 type 只能单选（`repository/redeem_code_repo.go:151-153` 用 TypeEQ），不传时全部混在一起，“已使用”的数量随每笔充值增长。Web 也不过滤：filterTypeOptions 只有四类、默认 ''（全部）（`frontend/src/views/admin/RedeemView.vue:750-756`）。返利（affiliate_balance）不在 redeem_codes 表里，是 balance-history 从 user_affiliate_ledger 现拼的（`service/admin_user.go:1273-1306`），不会出现在兑换码列表；污染列表的只有 admin_balance 与 admin_concurrency。

**建议改法**：`GET /api/v1/admin/redeem-codes`、`/export`、`/stats`（见 G08）增加 `types`（逗号分隔，取值限于 balance、concurrency、subscription、invitation、admin_balance、admin_concurrency，查询用 TypeIn）与 `exclude_types`（同上取值，TypeNotIn）。type 与 types 同时传返回 400；非法取值 400 `{"reason":"REDEEM_CODE_TYPE_INVALID","message":"unsupported redeem code type: xxx"}`。响应结构不变。例：`GET /api/v1/admin/redeem-codes?types=balance,concurrency,subscription,invitation&status=used&page=1&page_size=20`。不传新参数时行为完全一致。

**实现提示**：`redeem_handler.go:86-110` 的 List 与 :393-405 的 Export 解析 types、exclude_types（Split 后 TrimSpace、去重、校验白名单）；与 G03 一起引入 RedeemCodeListFilter{Type, Types, ExcludeTypes, Status, Search, …}，`repository/redeem_code_repo.go:148-185` 增加 `redeemcode.TypeIn(...)`、`redeemcode.TypeNotIn(...)`。type 列没有索引，但现在按 type 过滤本来就是全表条件；表大时可加 `CREATE INDEX ON redeem_codes(type, created_at DESC)`（可选）。

**App 退路**：四种类型各请求一次，按 id 倒序多路归并分页（每路游标分别维护，实现复杂）；状态胶囊计数需要 4 类 × 5 状态 = 20 次 page_size=1 请求（G08 先做好并支持 types 就只要 1 次）；也可以客户端过滤，但分页和计数都会不准。

**验收**：准备 2 条 balance 码与 3 条 admin_balance 记录：`?types=balance,concurrency,subscription,invitation` → total=2；`?exclude_types=admin_balance,admin_concurrency` → total=2；不传参数 → total=5（与现在一致）；`?types=foo` → 400 REDEEM_CODE_TYPE_INVALID；Web 兑换码页回归无变化。

---

#### G05 · 已使用的兑换码不能被“作废 → 改回未使用”后再次兑换 〔P1 · 改行为〕

**页面**：兑换码行内展开 ⋯ →“作废”、已过期 →“续期”（batch-update status=unused 加 expires_at）。

**背景**：资金完整性：一个已被用户 A 兑换过的余额码，不应被另一个用户再兑换一次。

**现状**：`POST /api/v1/admin/redeem-codes/:id/expire`（`server/routes/admin.go:599`）不检查状态，会把 used 的码改成 expired、used_by 保留（`service/admin_user.go:1781-1790`）；batch-update 只拦截当前 status==used 的码（`repository/redeem_code_repo.go:327-333`；`service/redeem_service.go:127-129`），于是可以再把它改回 unused。batch-update 是整批全有或全无：只要有一个码 status=used，整批返回一个 ErrRedeemCodeUsed（409），什么都不更新；响应只有 `{updated, message}`，没有逐项结果（`repository/redeem_code_repo.go:327-333,354-357`；`handler/admin/redeem_handler.go:324-336`）。兑换流程只看 CanUse（status unused 且未过期，`service/redeem_service.go:438-450`；`service/redeem_code.go:35-50`），Use() 只要求 status=unused（`repository/redeem_code_repo.go:363-371`），另一个用户就能再兑换一次、余额被重复发放（admin_* 类型兑换时会被类型检查拒绝，balance、concurrency、subscription 不会）。Web 没有调用 expire（`frontend/src/api/admin/redeem.ts:147` 有定义无调用方），但手机设计里“已过期 → 续期”正是 batch-update status=unused 加 expires_at。

**建议改法**：
- `POST /api/v1/admin/redeem-codes/:id/expire`：码 status=used 或 used_by 不为空时返回 409 `REDEEM_CODE_USED`（复用现有 ErrRedeemCodeUsed，`service/redeem_service.go:20`）。
- `POST /api/v1/admin/redeem-codes/batch-update`：沿用现有的整批拒绝语义，只把“已使用”的判定扩成 `status=used 或 used_by 不为空`。设置 status、expires_at 或 group_id 时，批里只要有一个这样的码，整批返回 409 REDEEM_CODE_USED、库内无变化。不做逐项结果：那需要新的响应结构，会影响 Web 调用方；真要逐项，另加可选参数（如 `partial=true`）并返回 results，Web 不传时不变。
- 纵深防御（可选）：Use() 的条件加 `used_by IS NULL`。

**实现提示**：ExpireRedeemCode（`service/admin_user.go:1781`）读到码后先判断 `code.Status == StatusUsed || code.UsedBy != nil`；batch-update 在 `repository/redeem_code_repo.go:327-333` 的循环里把 `code.UsedBy != nil` 一并算作已使用，返回同一个 ErrRedeemCodeUsed。Web 不调用 expire、batch-update 只改未使用的码，不受影响。

**App 退路**：App 对 used_by 不为空的码不提供“作废”“续期”，只保留复制、查看使用者、编辑备注。

**验收**：一个 used 的 balance 码调 expire → 409 REDEEM_CODE_USED；手工把它改成 expired 后，batch-update `{"ids":[该码, 另一个未使用的码],"fields":{"status":"unused"}}` → 整批 409 REDEEM_CODE_USED，两个码都没变；只改备注（fields 只有 notes）仍成功；另一个用户兑换该码失败；未使用的码作废、续期照常。

---

#### G06 · 其余管理端写接口支持可选的 Idempotency-Key（不带 key 时行为不变） 〔P2 · 新能力〕

**页面**：创建 / 编辑 / 启停用户；创建 / 编辑 / 删除分组；快捷编辑账号、启停调度、批量调度、刷新凭据。

**背景**：网络超时后，App 希望用同一个操作编号安全重试并拿回原响应，而不是只能提示“结果不明，请去 Web 核对”。

**现状**：`POST /admin/users`（`handler/admin/user_handler.go:296-331`）没有幂等；`PUT /admin/users/:id` 只有带 concurrency 时才走可选幂等（:400-410）；分组 POST、PUT、DELETE（`handler/admin/group_handler.go:639,794,890`；`server/routes/admin.go:360-363`）没有幂等，只有复制分组有（`group_handler.go:755`）；账号 `PUT /:id`（`handler/admin/account_handler.go:1172`）、`POST /:id/schedulable`（:2866）、`POST /bulk-update`（:2346）、`POST /:id/refresh`（:1582）、`POST /batch-refresh`（:2021）都不认 Idempotency-Key（只有创建 :1065 与复制 :1133 认）。不过这些接口大多天然可安全重试：PUT、启停调度、bulk-update 写的是绝对值；创建有唯一约束兜底（用户邮箱、分组名：`migrations/016_soft_delete_partial_unique_indexes.sql:16-18,30-32`，重复返回 409 EMAIL_EXISTS / GROUP_EXISTS，`service/auth_service.go:29`、`service/group_service.go:13`）；DELETE 重发得到“不存在”。缺的只是“证明是我这一次做的”和“拿回原响应”。

**建议改法**：以下路由接受可选 Idempotency-Key，带了走幂等协调器，没带走原逻辑（Web 不受影响）：
- `POST /api/v1/admin/users` → scope `admin.users.create`（与 E10 第 4 点同一处）
- `PUT /api/v1/admin/users/:id` → `admin.users.update`（去掉“只在带 concurrency 时”的条件，scope 名沿用）
- `POST /api/v1/admin/groups`、`PUT /api/v1/admin/groups/:id`、`DELETE /api/v1/admin/groups/:id` → `admin.groups.create / update / delete`
- `PUT /api/v1/admin/accounts/:id`、`POST /:id/schedulable`、`POST /bulk-update`、`POST /:id/refresh`、`POST /batch-refresh` → `admin.accounts.update / schedulable / bulk_update / refresh / batch_refresh`

语义同 G01：200 + X-Idempotency-Replayed: true；409 IDEMPOTENCY_IN_PROGRESS + Retry-After；409 IDEMPOTENCY_KEY_CONFLICT；400 IDEMPOTENCY_KEY_INVALID。重放返回首次响应的快照（运行时字段如 current_concurrency 可能已过时，敏感字段会被脱敏），App 收到重放后再 GET 一次最新状态。

**实现提示**：用现有 executeAdminOptionalIdempotentJSON（`handler/admin/idempotency_helper.go:106-145`，RequireKey=false）包住各 handler 的执行段；建议新增带超时的变体（同时传 ExecutionTimeout），让这些写入断连后也能落库（同 G01）。payload 用 `{id 路径参数, body}` 结构（参照 `user_handler.go:372-375`）。账号 Update 的返回值经 buildAccountResponseWithRuntime 组装，需要放进闭包。Refresh、BatchRefresh 会调上游 OAuth，ExecutionTimeout 建议 60–120s。先改 PUT users/:id 与 POST users（同一 handler 已有可选幂等，成本最低）。单测参照 `handler/idempotency_helper_test.go:283` 的重放断言。

**App 退路**：不自动重发，冻结原请求。超时后：PUT 类与启停调度读回服务器状态逐字段比对；创建用户收到 EMAIL_EXISTS 后按邮箱搜索比对 created_at 与字段；创建分组收到 GROUP_EXISTS 后按名称核对（同名不能证明是本次创建的，需要提示）；删除收到“不存在”视为已完成；核对不了的提示去 Web。

**验收**：不带 key 时各接口行为与响应一字不差（现有测试全过）；带 key 时同 key 同 body 发两次，第二次 200 且带 X-Idempotency-Replayed: true，数据库只有一次副作用；同 key 不同 body 返回 409 IDEMPOTENCY_KEY_CONFLICT；`KEY=$(uuidgen); curl -sS -D - -X POST "$BASE/api/v1/admin/groups" -H "Idempotency-Key: $KEY" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"t-grp","platform":"anthropic"}'` 执行两次，第二次是重放而不是 409 GROUP_EXISTS。

---

#### G07 · 禁止删除已使用的兑换码和 admin_* 兼容记录（单个和批量删除都在后端拦截） 〔P2 · 改行为〕

**页面**：兑换码行内展开 ⋯ → 删除兑换码。

**背景**：删除兑换码不应改写用户的“充值与调整记录”和“总充值”。

**现状**：`DELETE /api/v1/admin/redeem-codes/:id` 与 `POST /batch-delete` 直接物理删除，不检查状态（`service/admin_user.go:1767-1779`；`repository/redeem_code_repo.go:139-142`）。用户的 balance-history 读 redeem_codes 中 used_by=用户 的记录（`repository/redeem_code_repo.go:405-411`；`service/admin_user.go:1163-1215`），total_recharged = SUM(value) WHERE used_by=? AND value>0 AND type IN (balance, admin_balance)（`redeem_code_repo.go:433-452`）：删掉一个已使用的码，记录就从“充值与调整记录”里消失，总充值也跟着变。管理员调整账本 admin_user_adjustments 是另一张只追加的表，不受影响（`migrations/223_admin_user_adjustments.sql:99-112`）。Web 只在 UI 层限制（单个删除按钮只对 unused 显示，`frontend/src/views/admin/RedeemView.vue:188`；“删除未使用”只取 status=unused，:1120-1133）；设计稿对所有状态都提供删除（`html-preview/layouts/main/v-modules.jsx:580-586`）。

**建议改法**：
- `DELETE /api/v1/admin/redeem-codes/:id`：status=used 或 type 属于 admin_balance、admin_concurrency 时返回 409 `{"reason":"REDEEM_CODE_USED","message":"used redeem codes cannot be deleted"}`（复用 ErrRedeemCodeUsed）；不存在返回 404 `REDEEM_CODE_NOT_FOUND`。
- `POST /api/v1/admin/redeem-codes/batch-delete`：跳过受保护的码，响应增加 `{"deleted":3,"skipped_used":1,"skipped_ids":[88],"message":"Redeem codes deleted successfully"}`。
- 未使用、已过期（从未被使用）、已禁用的码照常可删；Web 只删 unused，不受影响。

**实现提示**：`repository/redeem_code_repo.go` 新增 DeleteUnlessUsed(ctx, id)：`Delete().Where(redeemcode.IDEQ(id), redeemcode.StatusNEQ("used"), redeemcode.TypeNotIn("admin_balance","admin_concurrency")).Exec(ctx)`，影响行数为 0 时再 GetByID 区分 404 与 409；条件写在同一条 SQL 里，避免先查后删的竞态。`service/admin_user.go:1767-1779` 的 DeleteRedeemCode、BatchDeleteRedeemCodes 改用新方法并收集被跳过的 id。可顺手把 BatchDeleteRedeemCodes 的逐条删除且吞错误（:1773-1777）改成一条 `DELETE … WHERE id IN (…) AND status<>'used' AND type NOT IN (…) RETURNING id`。

**App 退路**：与 Web 一致：已使用的码（以及 admin_* 记录，配合 G04 排除后看不到）不提供“删除兑换码…”，只保留复制、查看使用者、编辑备注。

**验收**：准备 1 条 used 的 balance 码与 1 条 unused 码：DELETE used → 409 REDEEM_CODE_USED，用户 balance-history 条数与 total_recharged 不变；DELETE unused → 200；`batch-delete {"ids":[used,unused]}` → deleted=1、skipped_used=1、skipped_ids=[used]；Web“删除未使用”回归正常。

---

#### G08 · 实现真实的兑换码统计：按状态和类型计数，过滤参数与列表一致 〔P2 · 改行为〕

**页面**：兑换码列表状态胶囊（全部 / 未使用 / 已使用 / 已过期 / 已禁用及数量）、导航副标题“N 个”。

**背景**：状态胶囊要显示各状态的真实数量（随搜索、类型变化），而不是只数已加载的那一页（`html-preview/layouts/main/v-modules.jsx:589-599,619-627`）。

**现状**：`GET /api/v1/admin/redeem-codes/stats` 写死返回全 0，注释“Return mock data for now”（`handler/admin/redeem_handler.go:373-389`），by_type 里还有一个不存在的 trial 类型。Web 只定义了 getStats，没有任何调用（`frontend/src/api/admin/redeem.ts:156-171`），改成真实值不影响 Web。状态口径以列表为准：expired 包括 status=expired 以及“unused 且 expires_at<=now”；unused 要求未过期；disabled 不看是否过期（`repository/redeem_code_repo.go:154-177`）。

**建议改法**：`GET /api/v1/admin/redeem-codes/stats` 支持与列表相同的过滤参数（type、types、exclude_types、search；G03 之后还有 batch_id、created_from、created_to）。保留现有字段并填真实值，新增 by_status：

```json
{"code":0,"data":{"total_codes":128,"active_codes":40,"used_codes":70,"expired_codes":12,"total_value_distributed":1234.5,
 "by_type":{"balance":90,"concurrency":20,"subscription":10,"invitation":8,"trial":0},
 "by_status":{"unused":40,"used":70,"expired":12,"disabled":6}}}
```

active_codes 等于 by_status.unused；total_value_distributed 为已使用的 balance 类面额合计；四项状态之和等于 total_codes。

**实现提示**：仓储新增 CountByStatus(ctx, filter)，一条 SQL：

```sql
SELECT COUNT(*) total,
  COUNT(*) FILTER (WHERE status='unused' AND (expires_at IS NULL OR expires_at>NOW())) unused,
  COUNT(*) FILTER (WHERE status='used') used,
  COUNT(*) FILTER (WHERE status='expired' OR (status='unused' AND expires_at IS NOT NULL AND expires_at<=NOW())) expired,
  COUNT(*) FILTER (WHERE status='disabled') disabled,
  COALESCE(SUM(value) FILTER (WHERE status='used' AND type='balance'),0) distributed
FROM redeem_codes rc LEFT JOIN users u ON u.id=rc.used_by WHERE <与 ListWithFilter 相同的条件>
```

by_type 另用一条 GROUP BY type。search 条件要与 `redeem_code_repo.go:178-185` 完全一致，最好复用同一个 filter 构造函数，避免计数与列表口径漂移。handler 在 `redeem_handler.go:373-389` 原地替换，路由不变（`server/routes/admin.go:591`）。

**App 退路**：每个状态各请求一次 `GET /admin/redeem-codes?status=<s>&page_size=1` 读 total（5 次，可并行）；G04 没做时还要乘以 4 种类型，或接受 admin_* 混入计数。

**验收**：固定数据集下 by_status 每一项等于对应 `GET /redeem-codes?status=x` 的 total，四项之和等于 total_codes；带 search 与 types 时同样一致；`curl -s "$BASE/api/v1/admin/redeem-codes/stats?types=balance,concurrency,subscription,invitation" -H "Authorization: Bearer $TOKEN"` 返回非零的真实值。

---

### H 代理与公告

#### H01 · 代理列表 / 详情 / all?with_count 的 DTO 增加 latency_checked_at（上次延迟探测时间），`POST /:id/test` 响应增加 checked_at 〔P1 · 加字段〕

**页面**：代理列表行的延迟读数、代理详情延迟块（VmoLatencyBlock）、行内展开卡片。

**背景**：代理列表和详情用大号数字显示延迟（`html-preview/layouts/main/v-modules.jsx:1770-1777`）。设计稿因为 DTO 没有测试时间，定成不写测量时间，只把本次会话测过的标“本次测试结果”（:1808-1811；`html-preview/shared/data.jsx:298-300`）。管理员需要判断延迟是不是很久以前测的：延迟缓存永不过期，只在手动测试、质量检测或新建时刷新。

**现状**：缓存结构 ProxyLatencyInfo 有 UpdatedAt（`service/proxy_latency_cache.go:8-24`），每次写入都赋 time.Now()：测试连接写在 `service/admin_proxy.go:295-317`，质量检测 :565-593，新建后的异步探测 :111 与 :596-622。Redis 写入 TTL=0、永不过期（`repository/proxy_latency_cache.go:65-74`）。但 attachProxyLatency（`service/admin_proxy.go:624-663`）只把 Success / LatencyMs / Message / IP / 地区 / 质量字段拷进 ProxyWithAccountCount（`service/proxy.go:59-75`），UpdatedAt 没拷；DTO（`handler/dto/types.go:454-470,480-496`）与 mapper（`handler/dto/mappers.go:543-609`）没有时间字段，只有 quality_checked（质量检测时间，Unix 秒）。`POST /:id/test` 返回的 ProxyTestResult（`service/admin_service.go:593-602`）也没有时间。Web 同样不显示测试时间。

**建议改法**（只加字段）：
1. `GET /api/v1/admin/proxies`、`GET /api/v1/admin/proxies/all?with_count=true`、`GET /api/v1/admin/proxies/:id`（见 H02）每项增加 `"latency_checked_at": 1760601600`（Unix 秒，取缓存 UpdatedAt；从没探测过不返回）。含义是“上次连通性探测时间”，测试连接、质量检测、新建后的自动探测都会刷新它；与 quality_checked 一样用 Unix 秒。
2. `POST /api/v1/admin/proxies/:id/test` 响应增加 `"checked_at": 1760601600`（失败时也返回），App 测完直接显示“刚刚测试 HH:MM”。

```json
{"id":1,"name":"hk-02","account_count":3,"latency_ms":182,"latency_status":"success","latency_message":"Proxy is accessible","latency_checked_at":1760601600,"quality_score":92,"quality_grade":"A","quality_checked":1760536800}
```

**实现提示**：`service/proxy.go:59-75` 的 ProxyWithAccountCount 加 `LatencyCheckedAt *int64`；attachProxyLatency（`admin_proxy.go:641-662` 的循环）加 `if !info.UpdatedAt.IsZero() { ts := info.UpdatedAt.Unix(); proxies[i].LatencyCheckedAt = &ts }`；`handler/dto/types.go` 的 ProxyWithAccountCount（:454）与 AdminProxyWithAccountCount（:480）加 `LatencyCheckedAt *int64 json:"latency_checked_at,omitempty"`，两个 mapper（`mappers.go:543,584`）各加一行；`service/admin_service.go:593` 的 ProxyTestResult 加 `CheckedAt int64 json:"checked_at,omitempty"`，TestProxy（`admin_proxy.go:283-327`）在成功和失败分支都用同一个 now 写缓存并回填。缓存里本来就有 updated_at（json 不带 omitempty），老数据能直接读出，不用迁移。编辑代理后缓存不失效的问题见 H04，两条一起做。

**App 退路**：按设计稿现状：不写测量时间；本会话测过的标“本次测试结果 / 刚刚测试”（App 本地记下测试完成时间）；质量评分旁写 quality_checked 日期（质量检测时延迟也会刷新，可当作延迟时间的下界）；想确认最新状态只能逐个点“测试连接”。

**验收**：新建代理几秒后，`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/proxies?page=1&page_size=20" | jq '.data.items[]|{id,latency_status,latency_checked_at}'` 新代理有 latency_checked_at；`POST /api/v1/admin/proxies/1/test` 后响应有 checked_at，列表里该代理的 latency_checked_at 等于它；`POST :id/quality-check` 后 latency_checked_at 也刷新；从没探测过的代理（清空 Redis key `proxy:latency:<id>`）不返回该字段；Web 代理页显示不变。

---

#### H02 · `GET /api/v1/admin/proxies/:id` 返回与列表一致的完整 DTO（账号数、延迟、出口 IP、质量）；`:id/stats` 去掉假数据（可选） 〔P1 · 改行为〕

**页面**：代理详情（从账号详情的代理跳转进入、下拉刷新、测试或编辑后刷新）。

**背景**：代理详情要显示账号数、延迟块、出口 IP 与地区、质量评分（`html-preview/layouts/main/v-modules.jsx:1798-1860`）。从账号详情跳进来时 App 只有 proxy_id（账号 DTO 里的 proxy 只有基础字段，`handler/dto/mappers.go:442,522-541`），下拉刷新也要单独拿这一个代理的完整数据。

**现状**：`GET /admin/proxies/:id`（`server/routes/admin.go:574`）→ ProxyHandler.GetByID（`handler/admin/proxy_handler.go:118-134`）→ adminService.GetProxy → proxyRepo.GetByIDScoped（`service/admin_proxy.go:50-52`、`repository/proxy_repo.go:86-100`），返回的 dto.AdminProxy（`handler/dto/types.go:474-477`）只有基础字段加密码，没有 account_count、latency_*、ip_address、country / region / city、quality_*。完整字段只有列表（`proxy_handler.go:59-83`）和 `/all?with_count=true`（:88-103，只返回 active 代理，停用和已过期的拿不到）。`GET /admin/proxies/:id/stats`（`proxy_handler.go:295-313`）写着“Return mock data for now”，固定返回 total_accounts=0、success_rate=100 等假数据。Web 只在 `frontend/src/api/admin/proxies.ts:84,173` 定义了 getById / getStats，没有视图调用，改这两个接口不影响 Web。usage_logs 里没有代理字段（`ent/schema/usage_log.go`），按代理统计请求数、成功率目前没有数据来源。

**建议改法**：
1. `GET /api/v1/admin/proxies/:id` 的响应从 AdminProxy 改成 AdminProxyWithAccountCount。后者是前者的超集（原有字段含 password 都在，只多出字段），算只增不改：

```json
{"code":0,"message":"success","data":{"id":1,"name":"hk-02","protocol":"socks5","host":"203.0.113.24","port":1080,"username":"relay","password":"<明文>","status":"active","expires_at":"2026-10-22T00:00:00Z","fallback_mode":"proxy","backup_proxy_id":2,"expiry_warn_days":7,
 "account_count":3,"latency_ms":182,"latency_status":"success","latency_message":"Proxy is accessible","latency_checked_at":1760601600,"ip_address":"203.0.113.24","country":"Hong Kong","country_code":"HK","region":"","city":"","quality_score":92,"quality_grade":"A","quality_summary":"…","quality_checked":1760536800,"fallback_account_count":0}}
```

   （latency_checked_at 见 H01，fallback_account_count 见 H03。）password 是明文，不是掩码：AdminProxy 与 AdminProxyWithAccountCount 原样输出密码（`handler/dto/types.go:474-481`；`handler/dto/mappers.go:576-579`），列表现在就是这样，Web 代理列表可切换显示密码、编辑弹窗也靠它回填（`frontend/src/views/admin/ProxiesView.vue:171-172,1425`）。改用 AdminProxyWithAccountCount 后详情仍返回明文；想改成掩码要另立条目，并写明 Web 编辑弹窗怎么回填。错误码不变：404 PROXY_NOT_FOUND（越权也按不存在处理），400 Invalid proxy ID。
2. （可选）`GET /:id/stats` 去掉假数据：total_accounts = 按作用域统计的挂载账号数，active_accounts = 其中 status=active 的数量；没有数据来源的 total_requests / success_rate / average_latency 改为 null，并加 `"request_stats_available": false`。也可以不动它，App 不用这个接口。

**实现提示**：AdminService 接口（`service/admin_service.go:133-147`）加 `GetProxyWithAccountCount(ctx, id int64) (*ProxyWithAccountCount, error)`，实现放 `service/admin_proxy.go` 挨着 GetProxy（:50）：GetByIDScoped → 按作用域计数 → `s.attachProxyLatency(ctx, out)`（:624）。计数必须与列表一样按工作区收窄（理由见 `repository/proxy_repo.go:608-615` 的注释，防止 vendor 从差额推断别家账号）；现有 CountAccountsByProxyID（:556-562）不收窄、供删除校验用，不能直接用，可在 ProxyRepository（`service/proxy_service.go:17-44`）加 CountAccountsByProxyIDScoped，SQL 照 GetAccountCountsForProxies（`proxy_repo.go:616-650`）加 workspace_id 条件。GetByID handler 改调新方法，返回 `dto.ProxyWithAccountCountFromServiceAdmin`；测试桩 `handler/admin/admin_service_stub_test.go` 补新方法。一次主键查询、一次 COUNT（accounts 有 proxy_id 索引，`ent/schema/account.go:247`）、一次 Redis MGET。vendor 的 GET 已被 permitProxyRead 放行（`server/middleware/vendor_routes.go:134`），GetByIDScoped 负责归属校验。

**App 退路**：详情页先用列表传进来的那一行；刷新或从账号跳转进入时，调 `GET /admin/proxies?search=<代理名>&page_size=100`（只按名称包含匹配，`repository/proxy_repo.go:397-399`）在结果里按 id 找，改名或重名会多翻页；停用 / 已过期的代理不能走 `/all?with_count=true`；不要用 `:id/stats`（假数据）。列表和详情里的 password 都是明文，按敏感数据处理：解码后只留在内存，不落盘、不进缓存、不写日志。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/proxies/1" | jq '.data|{account_count,latency_ms,latency_status,ip_address,quality_grade}'` 与列表中同一 id 那行一致；status 为 expired、inactive 的代理也能拿到完整字段；vendor 访问别家代理 id 返回 404 PROXY_NOT_FOUND，自己代理的 account_count 只算自己工作区的账号；password 与列表同一 id 那行一致（明文）；App 侧检查本地缓存与日志里没有代理密码；Web 代理管理页回归正常；（若做 stats）total_accounts 等于 `:id/accounts` 返回条数、request_stats_available=false。

---

#### H03 · 新增“因本代理到期被回退走的账号”查询与批量恢复原代理；代理 DTO 增加 fallback_account_count 〔P1 · 新接口〕

**页面**：代理详情 · 有效期分区的到期回退说明（已过期、已回退到直连 / 备用代理）、代理列表到期横幅。

**背景**：设计稿对已过期、已回退的代理写“到期后已把在用的账号改为直连 / 备用代理。要改回来，在账号详情里点‘恢复原代理’”（`html-preview/layouts/main/v-modules.jsx:250-264,1792-1796`），“使用该 IP 的账号”分区（:1840-1848）这时显示 0 个。管理员不知道是哪些账号被改走了，续期以后也没法一键改回来。

**现状**：到期扫描 ProxyExpiryService（`service/proxy_expiry_service.go:52-63`）→ sweepOneExpiredProxyOnExec（`repository/proxy_repo.go:830-911`）把 proxies.status 改成 expired，再 `UPDATE accounts SET proxy_id=NULL/备用, proxy_fallback_origin_id=COALESCE(proxy_fallback_origin_id,$1)`（:866-887，保留最早的原代理）。`GET /admin/proxies/:id/accounts`（`server/routes/admin.go:581` → `handler/admin/proxy_handler.go:315-335` → `service/admin_proxy.go:258-278` → `repository/proxy_repo.go:564-570`）只查 `WHERE proxy_id=$1`，被回退走的账号不在里面。账号这边只有单个恢复：`POST /admin/accounts/:id/revert-proxy-fallback`（`server/routes/admin.go:449` → `handler/admin/account_handler.go:1803-1814` → `service/admin_account.go:1524-1537` → `repository/account_repo.go:4136-4157`），不在回退状态时 400 ACCOUNT_NOT_IN_FALLBACK（`service/account_service.go:16`）。账号列表不支持按 proxy_id 或 proxy_fallback_origin_id 过滤（`account_handler.go:659-693`、`account_repo.go:1046-1126`），列表项虽带 proxy_fallback_origin_id / name（`handler/dto/mappers.go:470`），但只能把所有账号翻一遍。代理 DTO 没有被回退走的账号数。已有索引 accounts_proxy_fallback_origin_id_idx（`migrations/149_proxy_expiry_fallback.sql:10-11`），反查很便宜。续期（`PUT /admin/proxies/:id`）不会自动把账号改回来（`service/admin_proxy.go:116-193`）。

**建议改法**：
- A. `GET /api/v1/admin/proxies/:id/fallback-accounts`：列出 proxy_fallback_origin_id = :id 的账号（不分页，与 :id/accounts 风格一致）：

```json
{"code":0,"message":"success","data":[{"id":12,"name":"claude-pro-03","platform":"anthropic","type":"oauth","notes":null,"current_proxy_id":2,"current_proxy_name":"sg-01"},
                                      {"id":15,"name":"gpt-team-01","platform":"openai","type":"oauth","current_proxy_id":null,"current_proxy_name":null}]}
```

  current_proxy_id 为 null 表示现在走直连。错误：404 PROXY_NOT_FOUND。
- B. `POST /api/v1/admin/proxies/:id/fallback-accounts/revert`，请求体 `{"account_ids":[12,15]}`（省略或空数组表示全部，单次最多 500）。前置条件：该代理没被删除、status=active、没过期；不满足返回 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE`（“原代理仍已过期或已停用，请先续期或启用后再恢复”）。响应 `{"reverted_ids":[12],"skipped":[{"id":15,"code":"ACCOUNT_NOT_IN_FALLBACK","message":"account is not in proxy fallback state"}],"failed":[]}`；只处理“当前确实以 :id 为原代理”的账号，传进来的其他 id 进 skipped，code 为 `ACCOUNT_NOT_FALLBACK_OF_PROXY`；重复调用安全。
- C. 代理 DTO（列表、`/all?with_count`、`GET :id`）增加 `"fallback_account_count": 2`（按作用域统计 proxy_fallback_origin_id = id 的账号数），到期横幅与详情说明可直接写“2 个账号已被改走”。
以上全是新增，现有 :id/accounts 与单个 revert 接口不变（单个 revert 的前置校验见 H05）。

**实现提示**：
- `repository/proxy_repo.go` 新增 ListFallbackAccountSummariesByOriginProxyID(ctx, proxyID)：`SELECT a.id,a.name,a.platform,a.type,a.notes,a.workspace_id,a.proxy_id,p.name FROM accounts a LEFT JOIN proxies p ON p.id=a.proxy_id AND p.deleted_at IS NULL WHERE a.proxy_fallback_origin_id=$1 AND a.deleted_at IS NULL ORDER BY a.id DESC`（照 :564-604 的写法）；新增 GetFallbackAccountCountsForProxies（GROUP BY proxy_fallback_origin_id，工作区收窄照 :616-650），在 buildProxyWithAccountCountResult（:452-471）与 ListActiveWithAccountCount（:655-683）里填上；接口加到 `service/proxy_service.go:17-44`。
- `service/proxy.go`：ProxyAccountSummary 加 CurrentProxyID / CurrentProxyName；ProxyWithAccountCount 加 FallbackAccountCount。
- `service/admin_proxy.go`：GetProxyFallbackAccounts 照 GetProxyAccounts（:258-278）先 requireProxyAccess 再按 scope.OwnsWorkspaceID 过滤；RevertProxyFallbackAccounts：requireProxyAccess → GetByIDScoped 检查状态与过期 → 回退名单与 ids 取交集 → 逐个调用现有 RevertAccountProxyFallback（`service/admin_account.go:1524`，已含 requireAccountAccess、影子账号同步、scheduler outbox）。逐个提交，单个失败不回滚其他；不要用一条 UPDATE 批量改，否则绕过影子账号同步（propagateProxyToShadows）。
- handler 与 DTO 加在 `handler/admin/proxy_handler.go`、`handler/dto/types.go:498` 附近；路由加在 `server/routes/admin.go:581` 后。
- vendor：GET 已被 `vendor_routes.go:134` 的 permitProxyRead 放行，名单在 service 层按工作区过滤；POST 会改账号，不能只看 ProxyManage：在 :135 那条规则的 exclude 里加 `/api/v1/admin/proxies/:id/fallback-accounts/revert`，再加一条 exact 规则，permit 要求 `p.ProxyManage && p.AccountManage`。POST 自动经过 auditLog（`server/routes/admin.go:35`）。

**App 退路**：在代理详情说明里写清“被改走的账号要在账号详情里点‘恢复原代理’”。要找出是哪些账号，只能 `GET /admin/accounts?lite=true&page_size=1000` 翻完全部账号，本地按 proxy_fallback_origin_id == 当前代理 id 过滤，然后逐个 `POST /admin/accounts/:id/revert-proxy-fallback`。账号多时又慢又费流量，所以只在用户点“查看被改走的账号”时才做。

**验收**：
1. 代理 A 设 fallback_mode=direct、挂 2 个账号，把 expires_at 设成过去并等一轮扫描：`GET …/proxies/A/accounts` 返回 `[]`；`GET …/A/fallback-accounts` 返回这 2 个账号且 current_proxy_id=null；列表里 A 的 fallback_account_count=2。
2. A 仍为 expired 时 `POST …/A/fallback-accounts/revert` 返回 409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE。
3. PUT 续期并设 status=active，再 `POST revert {}`：reverted_ids 含这 2 个账号；之后 :id/accounts 返回 2 条、fallback-accounts 返回 `[]`、账号的 proxy_fallback_origin_id 为 null；再调一次，账号都进 skipped。
4. vendor 只有 ProxyManage 没有 AccountManage 时 POST revert 返回 403；GET fallback-accounts 只返回自己工作区的账号。
5. 有影子账号的母账号恢复后，影子账号的 proxy_id 也跟着改。

---

#### H04 · 编辑代理的地址或认证后，延迟缓存失效并重新探测 〔P1 · 改行为〕

**页面**：代理列表 / 详情的延迟、出口 IP、地区与质量评分；代理编辑 sheet 保存后。

**背景**：改了 host / port / 认证后，界面不能继续显示旧地址测出来的延迟和出口 IP。

**现状**：UpdateProxy（`service/admin_proxy.go:116-193`）改 protocol、host、port、认证后，既不重新探测（只有 CreateProxy 在 :111 异步探测），也不清 Redis 的 `proxy:latency:<id>`。缓存 TTL=0、永不过期（`repository/proxy_latency_cache.go:65-74`），ProxyLatencyCache 接口没有删除方法（`service/proxy_latency_cache.go:26-29`）。结果列表和详情会一直显示旧地址的延迟、出口 IP、地区和质量评分，直到有人手动测试。网络身份比较已有现成函数 proxyProbeIdentity（`repository/proxy_repo.go:175-184`）。

**建议改法**：UpdateProxy 判断网络身份（protocol、host、port、username、password）变了之后：先清掉该代理的延迟缓存（或写入 `latency_status:"pending"`），再像 CreateProxy 一样异步 `go s.probeProxyLatency(context.Background(), proxy)`。接口与响应不变；只改名称、备注、到期等非网络字段时不动缓存。

**实现提示**：ProxyLatencyCache 接口加 `DeleteProxyLatency(ctx, id)`（Redis DEL），在 UpdateProxy 成功写库后、身份变化时调用，再触发异步探测；身份比较复用 proxyProbeIdentity 的字段集合。H01 的 latency_checked_at 会随之更新。

**App 退路**：编辑代理的网络字段保存成功后，App 自动调一次 `POST /admin/proxies/:id/test`，并把旧读数标为“地址已修改，正在重新测试”。

**验收**：改代理 host 后立即 `GET /api/v1/admin/proxies/:id`：延迟字段为空或 pending；几秒后变为新地址的测量结果，latency_checked_at 晚于修改时间；只改名称时延迟与 latency_checked_at 不变。

---

#### H05 · 删除代理时检查“以它为原代理的回退账号”；恢复原代理前校验原代理存在、启用且未过期 〔P1 · 改行为〕

**页面**：代理 ⋯ → 删除；账号详情“恢复原代理”；H03 的批量恢复。

**背景**：数据一致性与出口安全：账号不能被悄悄恢复到一个已删除或已过期的代理上，进而改走直连、暴露服务器出口 IP。

**现状**：
- DeleteProxy（`service/admin_proxy.go:195-206`）只用 CountAccountsByProxyID 统计 proxy_id=id 的账号（`repository/proxy_repo.go:556-562`）。到期回退后 proxy_id 已被改走，所以过期代理可以直接被删除（软删），被改走的账号仍留着 proxy_fallback_origin_id=该 id。
- 之后单个恢复（`repository/account_repo.go:4136-4143`）会把 proxy_id 指向这个已软删的代理；loadProxies 被软删拦截器过滤（`account_repo.go:3533-3553`），account.Proxy 变成 nil，网关按 `account.ProxyID != nil && account.Proxy != nil` 判断（如 `service/antigravity_gateway_service.go:391`、`service/account_usage_service.go:889`），于是静默改走直连。
- 同一段 SQL 也会把账号恢复到仍过期的代理上，而扫描只处理 status=active 的代理（`repository/proxy_repo.go:835-840`），账号会一直留在那个过期代理上。

**建议改法**：
1. `DELETE /api/v1/admin/proxies/:id`：除现有检查外，还要统计 `proxy_fallback_origin_id = id` 的账号；有引用时返回 409 `PROXY_IN_USE`（沿用现有错误），metadata 带 `{"fallback_account_count":"2"}`。也可以选择删除时把这些账号的 proxy_fallback_origin_id 清空（它们保持当前直连 / 备用状态），二选一并在文档写明。
2. `POST /api/v1/admin/accounts/:id/revert-proxy-fallback`（以及 H03 的批量接口）：执行前校验原代理存在、status=active、未过期；不满足返回 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE`。原本合法的恢复不受影响。

**实现提示**：DeleteProxy 增加 `CountAccountsByFallbackOriginProxyID`（`SELECT COUNT(*) FROM accounts WHERE proxy_fallback_origin_id=$1 AND deleted_at IS NULL`，有索引 `migrations/149_proxy_expiry_fallback.sql:10-11`）；RevertAccountProxyFallback（`service/admin_account.go:1524-1537`）在调 repo 前读原代理并校验（Proxy.IsExpired(now)、Status）。错误码与 H03 共用。

**App 退路**：删除代理前先调 H03 的 fallback-accounts（未上线时只能翻全量账号），有回退账号就提示先处理；“恢复原代理”前先读原代理状态（列表或 `GET /admin/proxies/:id`），已过期或停用时提示“请先续期或启用原代理”，不发请求。

**验收**：一个已过期、有 2 个回退账号的代理：DELETE 返回 409 PROXY_IN_USE 且 metadata.fallback_account_count=2；对这 2 个账号单个恢复返回 409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE；续期并启用后恢复成功，再删除仍因账号挂在它上面而返回 409；没有任何引用的代理照常删除。

---

#### H06 · 公告已读汇总（read_count / eligible_count / eligible_read_count），已读名单增加已读 / 未读、符合 / 不符合条件筛选与 read_at 排序，并消除 N+1 〔P2 · 新接口〕

**页面**：公告列表行、公告详情“投放”分区、已读情况页（VmoNoticeReads）。

**背景**：用户希望一眼看到公告的触达情况（已读 N / 符合条件 M），并能只看已读或未读的人。定稿设计稿因为后端没有这些数据，已降级为：列表和详情不画已读进度，只留一行“已读情况 ›”进入全站用户的分页名单，名单不能按已读筛选（`html-preview/layouts/main/v-modules.jsx:32-34,123,2096-2103,2160-2166,2195-2200`）。

**现状**：公告 DTO（`handler/dto/announcement.go:9-26`）没有已读计数。`GET /admin/announcements/:id/read-status`（`server/routes/admin.go:497` → `handler/admin/announcement_handler.go:223-256` → `service/announcement_service.go:337-397`）先用 userRepo.ListWithFilters 对全站用户分页（只传 search），再批量查这一页的已读记录（`repository/announcement_read_repo.go:57-77`），然后对页内每个用户各调一次 userSubRepo.ListActiveByUserID（`service/announcement_service.go:368-377`，N+1；page_size 最大 1000，`pkg/response/response.go:182`），在内存里用 Targeting.Matches（`domain/announcement.go:66-128`）算 eligible。没有 read / eligible 过滤，也没有汇总。sort_by 直接交给 userListOrder（`repository/user_repo.go:661-700`），支持 email/username/role/balance/concurrency/status/created_at/last_active_at/last_used_at，不支持 read_at。search 匹配邮箱、用户名、备注、API Key（`user_repo.go:553-562`）。仓储里已有 CountByAnnouncementID（`announcement_read_repo.go:79-87`、`service/announcement.go:84`），没有调用方，也不排除已删除用户。eligible 按用户当前余额和当前有效订阅动态算，不是阅读时的快照。公告接口只对站长开放（`server/middleware/vendor_routes.go:99-100` 注释）。Web 已读弹窗只用 search / sort_by / sort_order（`frontend/src/api/admin/announcements.ts:54-75`）。

**建议改法**：
- A. 新接口 `GET /api/v1/admin/announcements/:id/read-summary` → `{"code":0,"message":"success","data":{"announcement_id":31,"total_users":1036,"eligible_count":1036,"read_count":412,"eligible_read_count":410,"computed_at":"2026-10-18T02:00:00Z"}}`。computed_at 是 RFC3339 UTC（1.3 的约定；公告 DTO 的时间字段都是 time.Time，`handler/dto/announcement.go:18-25`，没有可并列的 Unix 秒字段）。口径：只统计未删除用户（与名单一致）；eligible 按当前余额与当前有效订阅计算；read_count 是全部已读人数（读完后条件变了仍算已读），eligible_read_count 是“现在符合条件且已读”。草稿照常返回。错误：404 ANNOUNCEMENT_NOT_FOUND，400 Invalid announcement ID。
- B. `GET /api/v1/admin/announcements` 与 `/:id` 增加可选 `include_read_stats=true`，带上时每项多一个 `"read_stats":{"eligible_count":1036,"read_count":412,"eligible_read_count":410}`；不带时响应与现在完全一样。
- C. `GET /api/v1/admin/announcements/:id/read-status` 增加可选参数：`read_state=read|unread`、`eligible=true|false`、`sort_by=read_at`（未读排最后，同一时间按 user id 排，sort_order 照常可用）。total、pages 按过滤后的结果计算，行字段不变（user_id/email/username/balance/eligible/read_at）；非法取值 400 `INVALID_READ_STATUS_FILTER`。例：`GET …/31/read-status?read_state=unread&eligible=true&sort_by=email&page=1&page_size=50`。

**实现提示**：
- 核心是把 Targeting 翻译成 SQL 谓词，语义与 `domain/announcement.go:66-128` 的 Matches 完全一致：空 AnyOf 为 TRUE；空 AllOf 组为 FALSE；balance 条件按 gt/gte/lt/lte/eq 对应 `u.balance >/>=/</<=/= $n`；subscription 条件为 `EXISTS (SELECT 1 FROM user_subscriptions s WHERE s.user_id=u.id AND s.status='active' AND s.expires_at > NOW() AND s.deleted_at IS NULL AND s.group_id = ANY($n))`（与 `repository/user_subscription_repo.go:198-213` 一致）；空 group_ids 或未知 operator 为 FALSE。新增 `announcementTargetingSQL(t) (expr string, args []any)`，写表驱动测试与 Matches 的结果逐条对比。
- 汇总 SQL：`SELECT COUNT(*), COUNT(*) FILTER (WHERE <elig>), COUNT(ar.user_id), COUNT(ar.user_id) FILTER (WHERE <elig>) FROM users u LEFT JOIN announcement_reads ar ON ar.announcement_id=$1 AND ar.user_id=u.id WHERE u.deleted_at IS NULL`；announcement_reads 有 (announcement_id,user_id) 唯一索引（`ent/schema/announcement_read.go:60-63`），user_subscriptions 有 (user_id,status,expires_at) 索引（`ent/schema/user_subscription.go:112`）。
- 名单 SQL：同样的 FROM 与 JOIN，SELECT 带 `<elig> AS eligible`，按参数追加 `ar.user_id IS [NOT] NULL` 与 `<elig> = $b`；search 照抄 `user_repo.go:553-562` 的四个条件（email/username/notes ILIKE 加 EXISTS api_keys，记得 deleted_at IS NULL）；排序复用 userListOrder 白名单，再加 `read_at NULLS LAST, u.id`；LIMIT / OFFSET，COUNT 用同一组 WHERE。一次查询算出 eligible，N+1 消失。
- announcementReadRepository 现在只有 ent client（`announcement_read_repo.go:12-18`），需照 NewProxyRepository / NewUserRepository（`proxy_repo.go:28-34`、`user_repo.go:39-45`）注入 `*sql.DB` 并重新生成 wire（`repository/wire.go:82`）；接口加到 `service/announcement.go:80-85`（同步改 `handler/admin/announcement_handler_sort_test.go` 等测试桩）。ListUserReadStatus 只在带了新参数时走新 SQL，老路径不动最稳。
- handler：`announcement_handler.go:51-83` 的 List、:87-101 的 GetByID 解析 include_read_stats；:225-256 解析 read_state / eligible；新增 ReadSummary，路由加在 `server/routes/admin.go:497` 后。
- 性能：汇总每次全表扫 users、每个用户一次 EXISTS，几万用户量级是毫秒到百毫秒；列表带 include_read_stats 时每条公告一次查询（page_size 默认 20），targeting 为空的公告可共用一次 COUNT；可按 announcement_id 加 30–60 秒进程内缓存，App 显示 computed_at。

**App 退路**：按定稿设计：列表和详情不显示已读进度，只放“已读情况 ›”；名单页用现有 read-status 分页（search、sort_by=email/username/balance，也可用 created_at/last_active_at），每行显示“符合条件 / 不符合”和 read_at 或“未读”，不提供已读筛选；page_size 保持 20–50，避免服务端 N+1 太重；不要为了算汇总把全站用户翻一遍。

**验收**：`curl -s -H "Authorization: Bearer $T" "$BASE/api/v1/admin/announcements/31/read-summary" | jq .data`：read_count 等于 `SELECT COUNT(*) FROM announcement_reads ar JOIN users u ON u.id=ar.user_id AND u.deleted_at IS NULL WHERE ar.announcement_id=31`，eligible_count 等于按 Matches 逐个用户算出的结果（集成测试对比）；`read-status?read_state=read` 每行 read_at 都不为 null、total=read_count，`read_state=unread&eligible=true` 的 total = eligible_count − eligible_read_count；`sort_by=read_at&sort_order=desc` 最新阅读在前、未读在最后；不带新参数时 read-status 与 list 的响应逐字一致，Web 已读弹窗回归正常；page_size=200 时数据库查询次数是常数。

---

#### H07 · `POST /api/v1/admin/announcements` 支持可选的 Idempotency-Key（不带 key 照旧执行） 〔P2 · 新能力〕

**页面**：公告 · 新建 sheet（VmoNoticeEdit 的存草稿 / 发布）。

**背景**：手机网络不稳，新建公告超时后重试可能生成两条一样的公告；弹窗模式下所有用户会被弹两次。App 在 sheet 打开时生成一个 Idempotency-Key，重试时沿用。

**现状**：`POST /admin/announcements`（`server/routes/admin.go:493` → `handler/admin/announcement_handler.go:103-143`）直接调 announcementService.Create（`service/announcement_service.go:71-134`），不读 Idempotency-Key，也没有可用来去重的唯一键。对照：代理新建用 executeAdminIdempotentJSON（`handler/admin/proxy_handler.go:145`，RequireKey:true，`handler/admin/idempotency_helper.go:57-67,78-86`）；可选版本 executeAdminOptionalIdempotentJSON（`idempotency_helper.go:106-145`，RequireKey:false）已用在 admin.users.update / batch_concurrency / batch_limits（`handler/admin/user_handler.go:401,661,730`）。协调器在不带 key 时直接执行（`service/idempotency.go:221-230`）。Web 的公告新建不发这个头（`frontend/src/api/admin/announcements.ts:39-42`，拦截器 `frontend/src/api/client.ts:41-76` 也不会自动加）。

**建议改法**：不新增路由，`POST /api/v1/admin/announcements` 接受可选请求头 `Idempotency-Key: <UUID>`：不带头时行为与现在完全一样（Web 走这条）；带头且首次时正常创建，响应不变；同 key 同请求体重试返回第一次创建的那条公告、不再新建，响应头 `X-Idempotency-Replayed: true`；同 key 不同请求体 409 `IDEMPOTENCY_KEY_CONFLICT`（App 文案“该编号已用于另一份公告内容，请重新打开新建页”）；首次仍在处理 409 `IDEMPOTENCY_IN_PROGRESS` 带 Retry-After；key 非法 400 `IDEMPOTENCY_KEY_INVALID`；幂等存储不可用 503 `IDEMPOTENCY_STORE_UNAVAILABLE`（业务已提交时返回 200 并带 `X-Idempotency-Degraded: result-committed`）。回放有效期用 DefaultWriteIdempotencyTTL。

**实现提示**：Create 里绑定请求、取 subject、组装 input 的代码（`announcement_handler.go:106-134`）保留，把 :136-142 换成 `executeAdminOptionalIdempotentJSON(c, "admin.announcements.create", req, service.DefaultWriteIdempotencyTTL(), func(ctx context.Context) (any, error) { created, err := h.announcementService.Create(ctx, input); if err != nil { return nil, err }; return dto.AnnouncementFromService(created), nil })`。必须用 Optional 版本：RequireKey:true 的版本在运维关掉 observe_only（`config/config.go:2422` 默认 true）后，不带 key 的 Web 新建会报 IDEMPOTENCY_KEY_REQUIRED。指纹已含 method、route、`admin:<userID>`（`idempotency_helper.go:70-76`）与请求体，不同管理员同 key 不会串；payload 直接用 req（starts_at / ends_at 是 Unix 秒，序列化稳定）。补一个 handler 测试：同 key 调两次只建一条，第二次带 X-Idempotency-Replayed。PUT / DELETE 本身幂等，不需要处理。

**App 退路**：新建超时后，先 `GET /admin/announcements?search=<标题>&sort_by=created_at&sort_order=desc&page_size=5`（search 匹配标题和正文，`repository/announcement_repo.go:120-127`）看最近几分钟有没有同标题的，再让用户决定是否重发；重发前提示“上一次可能已经创建成功”。

**验收**：`K=$(uuidgen); curl -s -X POST -H "Authorization: Bearer $T" -H "Idempotency-Key: $K" -H 'Content-Type: application/json' -d '{"title":"t","content":"c"}' "$BASE/api/v1/admin/announcements"` 调两次，两次 data.id 相同、第二次带 X-Idempotency-Replayed: true、数据库只有一条；同一 K 改 title 再发返回 409 IDEMPOTENCY_KEY_CONFLICT；不带头连发两次生成两条（与现在一致）；把 IDEMPOTENCY_OBSERVE_ONLY 设为 false 后不带头仍能创建；Web 公告新建回归正常。

---

#### H08 · Web 不带 Idempotency-Key 的强制幂等写接口改为可选幂等（代理新建、账号新建与导入、兑换码生成等 11 个） 〔P2 · 改行为〕

**页面**：代理新建、新建账号（Web 兼容性问题；App 始终带 key）。

**背景**：这些接口现在能用，只是因为 observe_only 默认开着，运维一旦收紧就会打断 Web 的新建、导入、生成等操作。

**现状**：
- 强制 key 的 helper：executeAdminIdempotent / executeAdminIdempotentJSON 及带超时的变体都设 `RequireKey:true`（`handler/admin/idempotency_helper.go:34-67,78-97`）。协调器在 key 为空且 observe_only=false 时返回 400 IDEMPOTENCY_KEY_REQUIRED（`service/idempotency.go:221-224`）；`idempotency.observe_only` 默认 true（`config/config.go:2422`）。
- 已核实（2026-10-18），用了强制版本、而 Web 调用不带 Idempotency-Key 的接口共 11 个：

| 接口 | 后端 | Web 调用（不带头） |
|---|---|---|
| `POST /admin/proxies` | `handler/admin/proxy_handler.go:145` | `frontend/src/api/admin/proxies.ts:94-97` |
| `POST /admin/accounts` | `handler/admin/account_handler.go:1065` | `frontend/src/api/admin/accounts.ts:202-205` |
| `POST /admin/accounts/batch` | `account_handler.go:2138` | `accounts.ts:512-518` |
| `POST /admin/accounts/data`（数据导入） | `handler/admin/account_data.go:240` | `accounts.ts:772-781` |
| `POST /admin/accounts/import/codex-session` | `handler/admin/account_codex_import.go:155` | `accounts.ts:783-788` |
| `POST /admin/redeem-codes/generate` | `handler/admin/redeem_handler.go:145` | `frontend/src/api/admin/redeem.ts:92` |
| `POST /admin/usage/cleanup-tasks` | `handler/admin/usage_handler.go:588` | `frontend/src/api/admin/usage.ts:213-215` |
| `POST /admin/subscriptions/:id/extend` | `handler/admin/subscription_handler.go:229` | `frontend/src/api/admin/subscriptions.ts:142-150` |
| `POST /admin/system/update`、`/rollback`、`/restart` | `handler/admin/system_handler.go:88,167,206` | `frontend/src/api/admin/system.ts:77,89,100` |

- Web 已经带头的强制接口不受影响：余额调整（`frontend/src/api/admin/users.ts:25-39`）、复制账号（`accounts.ts:244`）、复制分组（`groups.ts:202`）、复制渠道监控（`channelMonitor.ts:299`）、订阅批量操作（`subscriptions.ts:45-50`）。create-and-redeem（`redeem_handler.go:203`）没有 Web 调用方。拦截器（`frontend/src/api/client.ts:41-76`）不会自动加这个头。

**建议改法**：上表 11 个接口改用可选幂等（scope 与 payload 不变）：带 key 时语义不变，不带 key 时直接执行。generate 按 G01 要加执行超时，用 G01 新增的“可选幂等 + 超时”变体；账号新建要自己处理重放（`account_handler.go:1065` 用的是返回 result 的 executeAdminIdempotent），用返回 result 的可选版本。备选：反过来让 Web 给这些请求补上 Idempotency-Key（每次提交生成一个 UUID，重试沿用），二选一。

**实现提示**：逐处替换 helper，补测试：observe_only=false 且不带 key 时这些接口都能成功，带 key 时重放正常。G01 的 generate、G03 与本条用同一个变体，不要两处各写一份。

**App 退路**：App 调这些接口始终带 Idempotency-Key，不受影响。

**验收**：`IDEMPOTENCY_OBSERVE_ONLY=false` 时，Web 新建代理、新建与批量新建账号、导入账号数据与 Codex 会话、生成兑换码、创建用量清理任务、订阅续期、系统更新 / 回滚 / 重启都成功；带同一 key 重发返回重放结果、只执行一次。

---

## 附录 A · 后端已支持、App 直接用的能力

这些不需要改后端。行号以 40bee5d2e 为准；标“需 A01”的要部署移动端基线后才有。

| 编号 | 能力 | 接口与参数 | 说明（证据） |
|---|---|---|---|
| **认证与会话** | | | |
| S1 | 合规确认在 App 内完成 | `GET /admin/compliance` 查状态（协议文案、确认短语）；`POST /admin/compliance/accept {phrase,language}` | GET 不被合规守卫拦截，Admin Key 与 JWT 都能当轻量权限探针（`server/routes/admin.go:182-183`；`server/middleware/admin_compliance.go:14,50-53`）。现有 App 让用户去 Web 确认（`sub2-mobile-native/Sources/Sub2Core/APIError.swift:26`），可以改成 App 内完成 |
| S2 | step-up 剩余窗口 | `POST /api/v1/user/totp/step-up` 响应带 expires_in（15 分钟） | `handler/totp_handler.go:201,220-228`；`service/totp_service.go:404`。App 现在只解析 verified（`APIClient.swift:424`） |
| S3 | 长会话 | refresh 30 天、每次刷新重新计满（滑动续期）；access 24 小时 | `config/config.go:1691,2332-2334`；`service/auth_service.go:1746` |
| S4 | 踢掉全部会话 | `POST /api/v1/auth/revoke-all-sessions` | `server/routes/auth.go:259`（access token 不会立即失效，见 A05） |
| S5 | 添加站点时自动填信息 | `GET /api/v1/settings/public`：site_name、site_logo、version、server_timezone、server_utc_offset、passkey_enabled、totp_enabled、backend_mode_enabled | `handler/dto/settings.go:384,399,430,433` |
| S6 | vendor 读自己的权限 | `GET /admin/workspaces/me` | `server/routes/admin.go:384`；vendor 可进管理端，按白名单限制（`server/middleware/admin_auth.go:204-209`）。App 目前直接拒绝 vendor |
| S7 | 运维监控 / 实时监控关闭可识别 | 运维监控关闭：所有 ops 接口返回 404，reason=OPS_DISABLED；运维开着、实时监控关闭：account-availability、concurrency、realtime-traffic 返回 200 且 `enabled:false` | `service/ops_service.go:19,146-151`；`handler/admin/ops_realtime_handler.go:22-36,122-136,210-251`（三个实时接口都先 RequireMonitoringEnabled，再判 IsRealtimeMonitoringEnabled）。前者显示“运维监控未开启”，后者显示“实时监控未开启”，不要判反 |
| **概览与统计** | | | |
| S8 | 今日实际扣费、请求、利润 | `GET /admin/dashboard/stats`：today_actual_cost、today_requests、today_account_cost（需 A01；40bee5d2e 用 snapshot-v2 的 stats 取） | `pkg/usagestats/usage_log_types.go:63-72`；`handler/admin/dashboard_snapshot_v2_handler.go:21-24,181-190`。利润 = today_actual_cost − today_account_cost，在 App 里算 |
| S9 | 统计新鲜度 | dashboard/stats 的 stats_updated_at、stats_stale | `handler/admin/dashboard_handler.go:132-133`，可直接显示“统计更新于…” |
| S10 | 昨天同一时刻 | 只比实际扣费：`GET /admin/dashboard/trend?start_time=<昨天 00:00>&end_time=<昨天同一时刻>&granularity=day&timezone=<server_timezone>` → `trend[0].actual_cost`；连利润一起比：`GET /admin/usage/stats` 同参数 → total_actual_cost、total_account_cost | `handler/admin/dashboard_handler.go:38-51`；`handler/admin/usage_handler.go:315-336`；`repository/usage_log_repo_trend.go:308-315,410-476`（整小时走 usage_dashboard_hourly、零头查原始表）；`repository/usage_log_repo_stats.go:766-803,890`。不要用设计稿“昨天该小时 × 41/60”的插值；stats_stale=true 时以 stats_updated_at − 24h 为截止或隐藏涨跌。可选 P2：stats 只增 yesterday_same_time_actual_cost / _account_cost / _requests / _until（在 `usage_log_repo_dashboard.go:232-264` 附近加，不要放进 origin/main 每次覆写 RPM 的路径） |
| S11 | 任意范围的账号成本 | `GET /admin/usage/stats` → total_account_cost；`dashboard/models`、`dashboard/groups` 每行带 account_cost | `repository/usage_log_repo_stats.go:890`（用户端被置空：`handler/usage_handler.go:415`）；`usage_log_types.go:95-135` |
| S12 | 时区口径 | 先取 settings/public 的 server_timezone；涉及今日 / 昨日 / 小时桶的请求都传 `timezone=<server_timezone>`，桶标签按响应的 query.timezone 解析；想看手机时区的今天用 `usage/stats?period=today&timezone=<手机时区>` | `handler/dto/settings.go:431-434`；`handler/setting_handler.go:100-101`；`pkg/usagequery/range.go:19-39`；`repository/usage_query_helpers.go:26-39`；dashboard/stats 与 today-stats 的“今日”固定按服务器时区（`repository/usage_log_repo_dashboard.go:83-84`；`service/account_usage_service.go:1432`）。账号 expires_at 是 Unix 秒（`handler/dto/types.go:231,357`），其余为 RFC3339。可选 P2：stats 回显 today_start、趋势点加 RFC3339 bucket_start（解决夏令时同名小时合并，`usage_log_repo_trend.go:320,363`） |
| S13 | 近 5 分钟运行指标 | `GET /admin/ops/dashboard/overview?time_range=5m`：error_rate、上游 429 / 529、健康分（概览运行区用它的 health_score）、QPS、SLA、TTFT 分位、system_metrics、job_heartbeats | `service/ops_dashboard_models.go:41-80`；`handler/admin/ops_handler.go:739-742`。需运维监控开启（关闭时见附录 B L23） |
| S14 | 今日 SLA 成功率 / 错误率：统计分析“今天”、概览「今日 · 00:00 起」区、平静布局 | `overview?start_time=<今日 00:00>&end_time=<now>` 的 sla（成功率）、error_rate、error_count_sla、request_count_sla | `service/ops_dashboard_models.go:57-72`；设计稿 `html-preview/shared/skin-base.jsx:171-175`、`html-preview/layouts/main/v-today.jsx:26-27,647`。不要把 dashboard/stats 的请求数与 ops 的 error_count_sla 混算；运维关闭时见附录 B L23 |
| S15 | RPM / TPM 趋势 | `GET /admin/ops/dashboard/throughput-trend?start_time=&end_time=[&group_id=][&platform=]`：request_count（成功 + 错误）、token_consumed（含缓存） | `server/routes/admin.go:290`；`repository/ops_repo_trends.go:45,94`；桶长 ≤ 2h 为 60 秒、≤ 24h 为 300 秒（`handler/admin/ops_dashboard_handler.go:332-342`）。残桶折算见附录 B L7；mode 参数目前无效（B10） |
| S16 | 错误率小折线 | `GET /admin/ops/dashboard/snapshot-v2?start_time=<now−45m>&end_time=<now>[&mode=raw]`：按 bucket_start 对齐 throughput_trend 与 error_trend，每桶 error_rate = error_count_sla ÷ (request_count − business_limited_count)，分母为 0 留空；格子用同一响应的 overview.error_rate | 三者同一组 where 与桶表达式（`repository/ops_repo_dashboard.go:124-130,926-935`；`repository/ops_repo_trends.go:40-91,334-355,450-458`；`handler/admin/ops_snapshot_v2_handler.go:18-24,96-130`）。扣掉 business_limited_count 后与 overview 完全同口径 |
| S17 | 统计分析其余图表 | dashboard/trend、models（含 account_cost、model_source）、groups（含 account_cost）、users-trend、users-ranking、user-breakdown、usage/stats；ops/dashboard 的 latency-histogram、error-trend、error-distribution、openai-token-stats | `server/routes/admin.go:288-313`；`pkg/usagestats/usage_log_types.go:95-136`。users-trend 带筛选时 metric 不生效、一律按 Tokens 取前 N 位，见 B12 |
| S18 | 用户 / Key 今日消费 | `POST /admin/dashboard/users-usage`、`POST /admin/dashboard/api-keys-usage` → today_actual_cost、total_actual_cost | `server/routes/admin.go:310-311`；`usage_log_types.go:325-337`（api-keys-usage 零点缓存见 E09） |
| S19 | 组合接口与 ETag | `GET /admin/dashboard/snapshot-v2`（统计、趋势、模型、分组、用户趋势，30 秒缓存 + ETag）；`GET /admin/ops/dashboard/snapshot-v2`；账号列表、today-stats/batch 支持 If-None-Match / 304 | `server/routes/admin.go:301`；`handler/admin/account_handler.go:880-909,2784-2787`。滚动窗口下 304 命中率低，见 B09、附录 B L9 |
| S20 | 免计数分页 | `GET /admin/usage?count_mode=deferred` → has_more、total_exact | `pkg/response/usage.go:11-15` |
| S21 | 慢查询打点 | 配置 `server.enable_server_timing=true`（或环境变量 `ENABLE_SERVER_TIMING`）后，admin 请求的响应头带 Server-Timing（db、redis） | `server/middleware/server_timing.go:30-50,123-127`；`repository/server_timing_sql.go`；`config/config.go:692,1854,2056`（默认关） |
| **账号** | | | |
| S22 | 账号列表运行时字段 | `GET /admin/accounts?lite=1`：rate_limit_reset_at、overload_until、temp_unschedulable_until / reason、extra（含 model_rate_limits）、proxy、group_ids、current_concurrency、current_window_cost、active_sessions、quota_*、credentials.expires_at | `handler/dto/types.go:334-424`；`handler/admin/account_handler.go:844-858`；`handler/dto/mappers.go:468`。current_rpm / scheduling_rpm 见 A01。current_window_cost 是站点自己按 usage_logs 算的窗口费用，不是上游 5 小时窗口占用（后者见 S64） |
| S23 | 账号详情 | `GET /admin/accounts/:id`：完整 DTO，含 groups、account_groups；敏感键不回显，只给 credentials_status.has_* | `handler/dto/types.go:208-327`；`service/account_credentials_redact.go:5-16`。group_ids、groups、account_groups 同源同序（`repository/account_repo.go:3556-3601`），显示用 groups、写入用 group_ids。容量区「5 小时窗口」的数据源见 S64 |
| S24 | 账号今日统计 | `GET /admin/accounts/:id/today-stats`、`POST /admin/accounts/today-stats/batch`：user_cost（实际）/ cost（账号成本）/ standard_cost / requests / tokens（含缓存） | `handler/admin/account_handler.go:2722-2810`；`repository/usage_log_repo_stats.go:277-306`（失败项见 C16） |
| S25 | 启停调度 | `POST /admin/accounts/:id/schedulable`（返回带运行时字段的账号）；批量 `POST /admin/accounts/bulk-update {account_ids, schedulable}`，逐个返回 results、success_ids、failed_ids | `server/routes/admin.go:458,468`；`handler/admin/account_handler.go:2866-2887`；`origin/main:service/admin_service.go:499-542` |
| S26 | 恢复状态 | `POST /admin/accounts/:id/recover-state`：清错误、限流、过载、临时不可调度、模型限流，并让 OAuth 令牌缓存失效；不改调度开关 | `handler/admin/account_handler.go:1350-1385`；`service/ratelimit_service.go:2163-2196`（“恢复并启用调度”见 C05） |
| S27 | 批量恢复 | `POST /admin/accounts/batch-clear-error {"account_ids":[12,15,31]}` → `{"total":3,"success":3,"failed":0,"errors":null}`（没有失败项时 errors 是 nil 切片，JSON 里是 null 而不是 `[]`：`handler/admin/account_handler.go:1974,2011-2016`；App 把 null 当作空数组解码）；要同时启用调度再 `POST bulk-update {account_ids, schedulable:true}` | `server/routes/admin.go:470`；`handler/admin/account_handler.go:1953-2017`（并发 10）；`service/admin_account.go:1468-1491`（ClearError + 清限流 / 过载 / 模型限流 / 临时不可调度 + 运行时阻断）。与 recover-state 的差别：会把 inactive 账号重新启用（C18）、不删 Redis 临时不可调度缓存（只影响 GET temp-unschedulable 的展示，`ratelimit_service.go:2252-2260`）、不重置 OpenAI 403 计数、不改 schedulable、健康账号也会写一次库。Web“批量重置状态”就用它（`frontend/src/views/admin/AccountsView.vue:1909-1919`） |
| S28 | 测试连接与测试模型 | `POST /admin/accounts/:id/test`（SSE，可传 model_id），通过后后端自动 RecoverAccountState；`GET /admin/accounts/:id/models` 取可选模型 | `handler/admin/account_handler.go:1312-1346,2890`；`server/routes/admin.go:441,460`。App 现在让用户手填模型名，可改为选择 |
| S29 | 刷新令牌与重新授权 | `POST /admin/accounts/:id/refresh`；`POST /admin/accounts/batch-refresh`（10 并发，errors 带 account_id）；各平台 auth-url + exchange-code（接受 proxy_id，优先于会话代理）；`POST /admin/accounts/:id/apply-oauth-credentials`（type 可在 oauth 与 setup-token 之间切换，extra 按键合并） | `server/routes/admin.go:443-444,471,480-485,500-553`；`handler/admin/account_handler.go:1615-1736,2021-2109`；`service/oauth_service.go:154-161`。App 现在逐个串行刷新，可改用 batch-refresh |
| S30 | 稀疏 PUT 基础 / 调度字段 | `PUT /admin/accounts/:id`：name、notes、status（active/inactive/error）、concurrency、priority、rate_multiplier、load_factor、group_ids、expires_at（≤0 清除）、auto_pause_on_expired、proxy_id（0 清除）都是指针，可只发改过的 | `handler/admin/account_handler.go:157-175`；`service/admin_account.go:755-958`（credentials / extra 的整块覆盖问题见 C03） |
| S31 | 更换 API Key | 先 `GET /admin/accounts/:id` 拿到脱敏后的整份 credentials，只替换 api_key，再整份 PUT（与 C03 的 App 退路相同）；C03 的 PATCH 上线后改用 `credentials_patch {"api_key":"…"}`。不能只发 `{"credentials":{"api_key":"…"}}`：UpdateAccount 用 MergePreservingSensitiveCreds 合并，只有敏感键“没带就保留”，非敏感键完全以请求为准、没带就删，base_url、model_mapping、custom_error_codes、请求头覆写等会被全部清掉 | `service/account_credentials_redact.go:31-52`（注释写明非敏感键完全由 incoming 决定）；`service/admin_account.go:766-769` |
| S32 | 混合渠道预检 | `POST /admin/accounts/check-mixed-channel` → has_risk、details{group_name, current_platform, other_platform}；确认后带 confirm_mixed_channel_risk=true 重发 | `handler/admin/account_handler.go:993-1033` |
| S33 | 新建账号幂等 | `POST /admin/accounts` 支持 Idempotency-Key（强制 key 的版本；Web 不带，observe_only 关闭后会出问题，见 H08） | `handler/admin/account_handler.go:1065` |
| S34 | 删除账号 | `DELETE /admin/accounts/:id` | `server/routes/admin.go:440`；`handler/admin/account_handler.go:1269-1284` |
| S35 | 代理与分组选择器 | `GET /admin/proxies/all?with_count=true`（只含启用代理，带 account_count）；`GET /admin/groups/all`（include_inactive=true、platform） | `handler/admin/proxy_handler.go:88-116`；`handler/admin/group_handler.go:547-568`（见附录 B L15） |
| S36 | 账号 Tab 徽标 | dashboard/stats 的 error_accounts | `pkg/usagestats/usage_log_types.go:46-50` |
| S37 | 定时测试 | `/admin/scheduled-test-plans`、`/:id/results`、`GET /admin/accounts/:id/scheduled-test-plans`；服务端可后台跑测试 | `server/routes/admin.go:782-790`；`service/account_test_service.go:3302` |
| S38 | 单个账号恢复原代理 | `POST /admin/accounts/:id/revert-proxy-fallback` | `server/routes/admin.go:449`（原代理可用性校验见 H05） |
| **日志与监控** | | | |
| S39 | 使用记录筛选 | `GET /admin/usage`：account_id、group_id、user_id、api_key_id、model（请求模型精确）、request_id、start_time / end_time、count_mode=deferred；行带 user / group / account 摘要、actual_cost、first_token_ms、duration_ms、request_type、tokens、upstream_model | `handler/admin/usage_handler.go:67-208`；`handler/dto/types.go:590-718`（account_cost 见 D05，model_source 见 B03） |
| S40 | 单条成功请求 | `GET /admin/usage?request_id=<rid>&page_size=1`（精确匹配，不需要时间范围），为空时显示“记录不存在或已清理” | `repository/usage_log_repo_query.go:120-123,135-142`；`pkg/usagequery/range.go:39-76`；索引 `migrations/027_usage_billing_consistency.sql:33`。可选 P2：`GET /admin/usage/:id`（复用 `service/usage_service.go:152` 与 UsageLogFromServiceAdmin，加工作区校验，404 USAGE_LOG_NOT_FOUND） |
| S41 | 错误请求 | `GET /admin/ops/request-errors`：account_id、group_id、user_id、user_query、model、request_id、resolved、time_range；要与“客户端最终收到 ≥ 400”一致需传 view=all（默认 errors 视图排除业务限流）。行有 phase、error_owner、error_source、severity、status_code、account_name、group_name、user_email、api_key_name、resolved、resolved_by_user_name | `handler/admin/ops_handler.go:54-69,227-345`；`service/ops_models.go:25-77`；`repository/ops_repo.go:961-977` |
| S42 | 上游错误计数与最近一条 | `GET /admin/ops/upstream-errors?account_id=&group_id=&time_range=24h`（含已重试成功的行），page_size=1 取最近一条 | `handler/admin/ops_handler.go:466-560`（用户 / 模型筛选见 D03） |
| S43 | 失败详情与重试链 | `GET /admin/ops/request-errors/:id`（error_body、upstream_errors JSON、各阶段耗时、api_key_prefix）；`GET /admin/ops/request-errors/:id/upstream-errors` | `server/routes/admin.go:262-277`；`service/ops_models.go:79-101`（每次尝试的耗时见 D10） |
| S44 | 标记已处理 | `PUT /admin/ops/request-errors/:id/resolve`、`PUT /admin/ops/upstream-errors/:id/resolve`，body `{resolved: true\|false}`，可撤销，记录处理人 | `handler/admin/ops_handler.go:460-462,571-575,684-718` |
| S45 | 筛选器选人、选 Key | `GET /admin/usage/search-users`、`GET /admin/usage/search-api-keys` | `server/routes/admin.go:761-762`（App 现在让用户手填数字 ID） |
| S46 | 渠道列表与时间条 | `GET /admin/channel-monitor-v2/overview?range=90m`：items[].group_name、platform、current_status.state（healthy / warning / critical / unknown / stale）、metrics.reliability_rate、metrics.ttft.p50_ms、buckets（18 格，5 分钟一桶） | 只挂功能开关，V1 / V2 模式都能用（`server/routes/admin.go:899-910`）；`service/channel_monitor_v2.go:465-466`；`service/channel_monitor_overview.go:12-70`；`service/channel_monitor_unified.go:23-28,41-82`。必须显式传 range（附录 B L11）；vendor 被拒（`server/middleware/vendor_routes.go:45`）。四档映射：healthy → 可用，warning → 性能下降，critical → 不可用，unknown / stale → 未知。可选 P2：V1 列表加 include_timeline=1（`service/channel_monitor_aggregator.go:104-115`） |
| S47 | 活跃请求与排队 | `GET /admin/ops/concurrency`：活跃 = Σ platform[*].current_in_use，容量 = Σ max_capacity，排队 = Σ waiting_in_queue；实时监控关闭（enabled:false）时排队改用 overview.system_metrics.concurrency_queue_depth，活跃显示“—” | `service/ops_realtime_models.go:5-12`；平台级可相加、分组级不能（`service/ops_concurrency.go:14-16,196-207`）；`service/ops_metrics_collector.go:306,370-410`。现有 App 把 activeRequests 写死为 nil（`APIClient.swift:115-120`） |
| S48 | 告警处理、规则、可用性 | `GET /admin/ops/alert-events?status=firing`（severity、platform、group_id 筛选，before_fired_at + before_id 游标）；`PUT /admin/ops/alert-events/:id/status {status:"manual_resolved"}`；`GET /admin/ops/alert-rules`；`GET /admin/ops/account-availability` | `server/routes/admin.go:214-225`；`handler/admin/ops_alerts_handler.go:416-459,517-610`（静默见 D01，规则摘要见 D06） |
| S49 | 服务器区单点数据 | overview.system_metrics（cpu_usage_percent、memory_usage_percent、concurrency_queue_depth）与 job_heartbeats；ops/concurrency；system-logs/health（avg_write_delay_ms、queue_depth）；ops/ingress-rejections（默认 1 小时） | `service/ops_port.go:251-304`；`service/ops_system_log_sink.go:18-26`；`handler/admin/ops_ingress_reject_handler.go:41`（历史与心跳状态见 D08） |
| S50 | 错误日志入库已脱敏 | 无需参数 | 错误正文与上游消息入库时已脱敏（`service/ops_service.go:400,514-548`），App 再脱敏只是兜底 |
| **用户与 Key** | | | |
| S51 | 用户列表 | `GET /admin/users`：默认 sort_by=created_at、sort_order=desc；搜索覆盖邮箱、用户名、备注、Key；role、group_name 筛选；返回 current_concurrency、last_active_at、last_used_at、balance | `handler/admin/user_handler.go:162-171`；`repository/user_repo.go:550-557` |
| S52 | 充值与调整记录 | `GET /admin/users/:id/balance-history`：code（显示前 8 位）、type、value、notes、used_at、total_recharged；分页 + type 过滤 | `handler/admin/user_handler.go:517-551`（前后余额见 E10） |
| S53 | 余额调整 | `POST /admin/users/:id/balance`：字符串金额、notes、强制 Idempotency-Key（24 小时）；重放带 X-Idempotency-Replayed；账本按 action_id 去重（幂等记录过期后同 key 同请求体也不会重复入账）；`operation=set balance=0` 原子归零；停用用户也能调 | `handler/admin/user_handler.go:99-103,457,762-775`；`service/admin_user.go:654-755,848-860`；`handler/admin/idempotency_helper.go:197-199`（断连问题见 G01，核对见 G02） |
| S54 | 最近调整过的用户 | `GET /admin/user-adjustments`：user_id、user_email、user_name、operator、before_value、after_value | `server/routes/admin.go:144-151`；`service/admin_user_adjustment.go:75-97`（去重与余额见 E05） |
| S55 | Key 卡片字段 | `GET /admin/users/:id/api-keys`：status、quota / quota_used、expires_at、ip_whitelist / ip_blacklist、last_used_at / last_used_ip、rate_limit_5h / 1d / 7d、usage_*、reset_*_at | `handler/dto/types.go:56-89`（current_concurrency 恒为 0，见 E11；状态映射见 E06） |
| S56 | Key 换分组、重置速率用量 | `PUT /admin/api-keys/:id {group_id（0=解绑）, reset_rate_limit_usage}` → auto_granted_group_access、granted_group_id、granted_group_name | `handler/admin/apikey_handler.go:25-79`（撤销见 E04） |
| S57 | 编辑用户其余功能 | `PUT /admin/users/:id`（email、username、password、notes、role、status、concurrency + adjustment_notes、rpm_limit、allowed_groups、restrict_public_groups、group_rates）；`POST /:id/replace-group`；`GET/PUT /:id/platform-quotas`、`POST /:id/platform-quotas/reset`；`GET /:id/rpm-status`；`GET/PUT /:id/attributes`；`GET /admin/users/:id/subscriptions`；禁用 / 启用（PUT status）、`DELETE /admin/users/:id` | `server/routes/admin.go:318-341,753` |
| S58 | 发放补偿 | `POST /admin/redeem-codes/create-and-redeem`：code 由 App 生成；同一码已被同一用户兑换直接返回，只创建未兑换就补兑，被别人用过返回 REDEEM_CODE_CONFLICT；核对用 `GET /admin/redeem-codes?search=<code>` | `handler/admin/redeem_handler.go:203-268`；`repository/redeem_code_repo.go:178-184`。设计稿说补偿不需要“待核对”成立（`html-preview/layouts/main/v-modules.jsx:1505-1506`） |
| **分组** | | | |
| S59 | 分组管理 | 列表、详情、新建、编辑、复制（幂等）、删除、排序；`GET /admin/groups/usage-summary`（今日 / 昨日 / 累计）；`GET /admin/groups/capacity-summary`；`GET /:id/rate-multipliers`（每行带 rate_multiplier 与 rpm_override）；`PUT/DELETE rpm-overrides`；`GET /:id/api-keys`；`GET /admin/groups/:id/subscriptions`；`GET /admin/subscriptions?group_id=&status=` | `server/routes/admin.go:345-371,750`；`handler/admin/group_handler.go:1055-1077`；`handler/admin/subscription_handler.go:65-98`；订阅用量返回前已把过期窗口清零（`service/subscription_service.go` normalizeExpiredWindows） |
| S60 | 分组今日用量 | `GET /admin/dashboard/groups?start_date=&end_date=&group_id=`：requests、total_tokens、cost、actual_cost、account_cost | `handler/admin/dashboard_handler.go:257-278`；`pkg/usagestats/usage_log_types.go:127-135` |
| **兑换码 / 代理 / 公告** | | | |
| S61 | 兑换码 | 列表带使用者 user 与分组 group；`POST /admin/redeem-codes/batch-update` 做启用 / 禁用、续期（新 expires_at + status=unused）、改备注（批里只要有一个当前 status=used 的码，改 status / expires_at / group_id 就整批 409 REDEEM_CODE_USED、一个都不改；只改备注不受限）；单个与批量 DELETE；`POST /:id/expire` | `repository/redeem_code_repo.go:191-194,327-333`；`service/redeem_service.go:279-332`；`server/routes/admin.go:594-599`（已使用码的作废与删除见 G05、G07） |
| S62 | 代理 | 列表带 account_count、latency_ms / status / message、出口 IP 与地区、quality_*、expires_at、fallback_mode、backup_proxy_id、expiry_warn_days；`POST /:id/test`、`POST /:id/quality-check`、`GET /:id/accounts`；新建幂等（强制 key，Web 不带，见 H08）。列表的 password 是明文（见 H02），App 不落盘、不写日志 | `handler/admin/proxy_handler.go:59-83,145`；`handler/dto/types.go:448-496`；`server/routes/admin.go:574-581` |
| S63 | 公告 | 增删改查 + `GET /admin/announcements/:id/read-status`（逐用户 eligible、read_at） | `server/routes/admin.go:490-498`（汇总与筛选见 H06） |
| **账号（补）** | | | |
| S64 | 账号详情 · 容量「5 小时窗口」（Anthropic OAuth / Setup Token 账号） | `GET /api/v1/admin/accounts/:id/usage?source=passive` → five_hour.utilization（0–100+，100 表示用满）、resets_at、remaining_seconds，比例 = utilization ÷ 100；只在详情页调用，只对 Anthropic OAuth / Setup Token 账号调用（其他账号 passive 直接报错）。列表里已有 session_window_status / session_window_end（`handler/dto/types.go:245-247`），只要状态时不必额外请求 | `server/routes/admin.go:450`；`handler/admin/account_handler.go:2587-2616`（先 GetAccount 做归属校验，source 缺省为 active）；`service/account_usage_service.go:151-158,185-189,589-631,1708-1748`（passive 只读 Extra 里响应头采样的 session_window_utilization，不调外部 API）。不用缺省的 active（可能请求上游）。口径定为上游窗口占用，不用 current_window_cost ÷ window_cost_limit：后者是站点自己的费用控制，只在配置了 window_cost_limit 时才有值（`handler/dto/types.go:249-252`），设计稿里被上游 429 限流的账号这一格是 1.0（`html-preview/shared/data.jsx:93`；`html-preview/layouts/main/00-core.jsx:387`），对应的是上游窗口。five_hour 为 null 时不显示这一格 |

---

## 附录 B · 只在 App 侧处理、不需要后端的事项

| 编号 | 事项 | App 做法（证据） |
|---|---|---|
| L1 | 错误响应解码 | ErrorReply 的 code 声明为 Int?（`sub2-mobile-native/Sources/Sub2Core/APIClient.swift:417`），中间件错误的 code 是字符串，整段解码失败，TOKEN_EXPIRED 刷新（:319-320）永远不触发。改成 Int / String 兼容解码，marker = reason ?? 字符串 code。`APIError.swift:27` 把所有 423 当双因素处理，应改为合规确认（S1） |
| L2 | 固定 User-Agent | 发送不带版本号的 UA（如 `Sub2Mobile-iOS`），避免会话绑定在 App 或 iOS 升级后失效（`service/session_binding.go:27-33`） |
| L3 | Admin Key 身份提示 | Admin Key 一律以第一个管理员身份操作、审计也记在其名下（`server/middleware/admin_auth.go:139-153`；`server/middleware/admin_compliance.go:25`），登录页注明“以 <第一个管理员> 身份操作”；A02 上线后直接显示 user |
| L4 | 后端模式下的 vendor | backend_mode_enabled 时 vendor 不能登录（`handler/auth_handler.go:156`），也过不了 BackendModeUserGuard（`server/middleware/backend_mode_guard.go:20-26`）；读 settings/public 的 backend_mode_enabled，提示“站点处于后端模式，仅站长可登录” |
| L5 | vendor 看不到的模块 | 渠道监控 v2 在 vendorDeniedRoutes（`server/middleware/vendor_routes.go:45`）；看板只开放按账号可收窄的三条（:147-153）；运维、用户、兑换码、订阅、公告为站长专属（:95-97）。App 按 workspace.permissions 隐藏对应区域 |
| L6 | 首页 RPM / TPM 算法 | 开监控时用 `overview?time_range=5m` 的 request_count_total、token_consumed 除以 (end_time − start_time)，同一组 where、App 本来就在调；不要用 `DECISIONS.md:137` 与 `html-preview/layouts/main/v-today.jsx:28-31` 写的“throughput-trend 最近 5 桶之和 ÷ 5”——09:41:23 时最近 5 个 1 分钟桶只覆盖 4 分 23 秒，按 5 分钟去除偏低约 12%（平均约 10%，最多 20%）。关监控时退回 dashboard/stats 并注明口径（B01） |
| L7 | RPM / TPM 趋势残桶 | 请求必须显式传 start_time / end_time（不用 time_range），覆盖秒数 = min(bucket_start + bucket_seconds, end) − max(bucket_start, start)，RPM = request_count × 60 ÷ 覆盖秒数；桶长只可能 60 / 300 / 3600（`handler/admin/ops_dashboard_handler.go:332-342`），后端原样采用传入的时间（`handler/admin/ops_handler.go:720-737` → `pkg/usagequery/range.go:40-55`；补桶 `repository/ops_repo_trends.go:385-415`）。现有 App 统一除以整桶秒数（`Sources/Sub2Core/PerformanceTrend.swift:57-60`）要改；也可以把 end_time 向下取整到整分钟消除 1 分钟桶的残桶。可选后端 P2：响应回显 bucket_seconds / start_time / end_time、每点加 covered_seconds（`service/ops_trend_models.go:5-37`；`repository/ops_repo_trends.go:133-140,385`） |
| L8 | 不用 realtime-traffic 显示 RPM | ops/realtime-traffic 的 qps / tps 四舍五入到 0.1（`repository/ops_repo_realtime_traffic.go:95-100`），换算 RPM 精度 ±6，且要求实时监控（`handler/admin/ops_realtime_handler.go:235-251`） |
| L9 | 组合接口的取舍 | ops/dashboard/snapshot-v2 任一段失败整包报错（`handler/admin/ops_snapshot_v2_handler.go:98-129`），缓存 key 用秒级 start / end（:69-77）；dashboard/snapshot-v2 的 ETag 只在 30 秒缓存期内稳定（`handler/admin/dashboard_snapshot_v2_handler.go:174`）。首页各区块用独立请求，不指望 304 |
| L10 | 占位接口不读数值 | dashboard/realtime 固定 0（`handler/admin/dashboard_handler.go:184-194`）、users/:id/usage 固定 0（`handler/admin/user_handler.go:495-511` → `service/admin_user.go:1151-1160`）、groups/:id/stats 是 TODO（见 F02）。用户用量改用 `usage/stats?user_id=&start_time=&end_time=`（App 已这样做，`APIClient.swift:176-180`），realtime 只看是否 200（:64-66）。**后端约束**：不要删除或改坏 `/admin/dashboard/realtime` 的 200，现有 App 的 Admin Key 激活依赖它；可选让它返回 B01 同源真实值并保留原 4 个键 |
| L11 | 渠道 overview 传 range | handler 不传 range 时默认 24h（`handler/channel_monitor_overview_handler.go:178-180`），service 默认 90m（`service/channel_monitor_v2.go:465`），App 必须显式传 `range=90m` |
| L12 | 关监控期间的“没有数据” | 监控关闭时网关不写 ops_error_logs（`handler/ops_error_logger.go:1101`），重开也不回填；错误请求、上游错误、错误率在这段时间显示“未开启 / 无数据”，不能显示为 0 |
| L13 | 错误请求按用户筛选 | request-errors 已支持 user_id、api_key_id、model、request_id 精确筛选（`handler/admin/ops_handler.go:259-272`）；设计稿注释 `html-preview/shared/data.jsx:418-424` 写“只能用 user_query”已过时，规格改用 user_id |
| L14 | Key 状态映射 | inactive 与 disabled 都显示“已停用”；status=active 但已过期显示“已过期”；额度用满显示“额度耗尽”；设计稿三处只认 disabled 的映射要补（`html-preview/layouts/main/00-core.jsx:469`、`v-user-edit.jsx:64-65`、`v-groups.jsx:1045`，后者还漏了 quota_exhausted）。E06 上线后直接用 effective_status |
| L15 | 分组目录 | 用 `GET /admin/groups/all?include_inactive=true` 做分组目录并缓存；现有 App 没带这个参数（`Sources/Sub2Core/GroupManagement.swift:176-177`），停用分组名会显示成 “#id”（`NativeApp/Features/AccountsView.swift:319-326`）。include_inactive=true 时 platform 被忽略（`handler/admin/group_handler.go:556-562`），在本地按平台过滤 |
| L16 | 分组计数字段默认 0 | AdminGroup 的 account_count、active_account_count、rate_limited_account_count 都是 omitempty（`handler/dto/types.go:200-202`），值为 0 时字段不出现，解码时默认 0 |
| L17 | 账号今日卡的口径说明 | “账号成本、标准”只按真实上游调用计算，“实际扣费”含合并探测的跟随请求（这些请求没有上游成本）——这是有意设计（`repository/usage_log_repo_stats.go:277-357`；`migrations/229_probe_coalesced_usage.sql:1-13`；`service/gateway_probe_billing.go:168-170`），利润按“实际 − 账号成本”正好正确，后端不改。卡片加一行说明即可 |
| L18 | 金额精度 | 读出的 float64 对实际金额没有精度损失：余额是 DECIMAL(20,8)（`migrations/001_init.sql:46`），有效数字 ≤ 15 位的值 JSON 文本与库值一致；写入与账本已是字符串（`handler/admin/user_handler.go:99-100`；`service/admin_user_adjustment.go:75-97`）。App 解码同时接受字符串与数字（`Sources/Sub2Core/Models.swift:417-431`），资金核对以账本字符串为准，展示用 Decimal 四舍五入到 2 位。以后真要精确展示千万美元以上余额，再只增 balance_exact 字符串 |
| L19 | 不用 PUT 改余额 | `PUT /admin/users/:id` 的 balance 字段（`handler/admin/user_handler.go:85`）在 UpdateUser 里没被使用（`service/admin_user.go:199` 之后无引用），请求成功但余额不变；改余额只用 `POST /admin/users/:id/balance`（后端是否改为 400 见附录 C Q13） |
| L20 | 纯本地功能 | 界面模式、外观、Face ID 门槛、站点列表都是 App 本地设置；“余额待核对”是 App 本地状态，用本地通知；新建代理、资金写入一律带 Idempotency-Key |
| L21 | 搜索 Tab「搜索全部对象」（账号、用户、请求 ID、Key 片段，`html-preview/layouts/main/00-core.jsx:835-846`） | 没有全局搜索接口。App 防抖（约 300ms）后并发扇出，各取前 5 条：`GET /admin/accounts?search=&lite=1`（`handler/admin/account_handler.go:664`）、`GET /admin/users?search=`（匹配邮箱、用户名、备注与 Key 片段；Key 片段命中时返回的是 Key 的所属用户，`repository/user_repo.go:553-561`）、`GET /admin/groups?search=`（`handler/admin/group_handler.go:361`）、`GET /admin/proxies?search=`（`handler/admin/proxy_handler.go:63`）；输入像请求 ID 时，再精确查 `GET /admin/usage?request_id=`（S40）与 `GET /admin/ops/request-errors?request_id=`（`handler/admin/ops_handler.go:263`，运维关闭时跳过这一路）。`GET /admin/usage/search-api-keys` 只按 Key 名称匹配（`repository/api_key_repo.go:705-707`），不能拿来按 Key 片段找 Key。vendor 看不到用户，跳过这一路（L5）。可选后端 P2：`GET /api/v1/admin/search?q=&limit=5`，按类型各返回前 N 条，少几次往返 |
| L22 | 用户列表每行与用户详情的“余额低”标记 | 与 E05 的 low_balance 同一口径，不要照抄设计稿写死的 $10（`html-preview/layouts/main/v-users.jsx:24-27,278`）：用户自己的 balance_notify_threshold 优先，否则用 `GET /api/v1/settings/public` 的 balance_low_notify_threshold（`handler/dto/settings.go:435-437`；`handler/setting_handler.go:102-104`）；全局提醒关闭且用户没设阈值时不标；threshold_type=percentage 时阈值 = total_recharged × 阈值 ÷ 100（`service/balance_notify_service.go:61-68`），total_recharged 为 0 或不准时（管理员充值不累加这一列，见 E10、附录 C Q12）宁可不标；禁用用户不标。所需字段都在用户 DTO 里（`handler/dto/types.go:27-32`）。这是显示规则；后端发提醒邮件时全局关闭就一律不发（`balance_notify_service.go:97-101`） |
| L23 | 运维监控关闭时的今日成功率与健康分 | 概览「今日 · 00:00 起」区与平静布局的成功率取今日 overview 的 sla（S14），运行区的健康分取 `overview?time_range=5m` 的 health_score（S13），两者都只能从 ops overview 来，B01 rates 也不提供。overview 返回 404 OPS_DISABLED 时，这两个数显示“—”并提示“运维监控未开启”（与 D09 同一套文案），不能显示 100% 或 0（`html-preview/shared/skin-base.jsx:175`；`html-preview/layouts/main/v-today.jsx:564,647`） |

---

## 附录 C · 需要维护者拍板的取舍

| 编号 | 问题 | 选项 | 建议 |
|---|---|---|---|
| Q1 | 首页 RPM / TPM 在站点没开运维监控时的口径（`DECISIONS.md:135` 留给最终规格） | (a) 退回 dashboard/stats 的 rpm / tpm（只算成功、TPM 不含缓存），规格里注明；(b) 做 B01 rates：TPM 含缓存且不受开关影响，RPM 关监控时只含成功；(c) 只在 dashboard/stats 增加含缓存的 tpm 字段 | 做 B01；上线前用 (a)。ops.enabled 默认 true（`config/config.go:2316`），多数站点走 overview，口径一致 |
| Q2 | 关监控时首页要不要有错误率 | (a) 显示“—”并提示开启监控；(b) 做 B01 第二阶段：网关在开关判断前写 Redis 每秒计数（热路径多一次 HINCRBY） | (a)。错误日志在关监控期间本来就不写，(b) 只为一个格子增加网关开销 |
| Q3 | 新建账号“先停调度再测试”的做法 | (a) 后端 C01：创建时一个参数 schedulable=false，无空窗；(b) App 多请求：创建后立刻停调度，中间有空窗，失败要核对；(c) 创建时设 expires_at = now − 60 秒 + auto_pause_on_expired，IsSchedulable 与调度 SQL 会立即排除（`service/account.go:177-179`；`repository/account_repo.go:3525-3531`），但 Web 显示“已过期”，后台 AutoPauseExpiredAccounts 可能把开关关掉（`account_repo.go:2776-2786`），测试通过后要再改回 | (a)；过渡期用 (b)；不用 (c) |
| Q4 | 会话绑定的原生客户端模式做到哪一档（A04） | 方案 A：device / ua_only（降级选项，device_id 由客户端声明）；方案 B：Secure Enclave 设备密钥签名刷新（更安全、工作量大）；或不做，建议站长对管理端不开会话绑定 | 先做 A，默认 strict 不变、由站长自选；B 等有需求再做 |
| Q5 | 让被踢设备尽快失效的方式 | (a) A05：Redis 按 sid 吊销，每个请求多一次 Redis GET；(b) 把 `jwt.access_token_expire_minutes` 调到 15–60 分钟，靠 A03 的宽限期刷新（零代码，refresh 更频繁）；(c) 两者都做。另需定 Redis 故障时 fail-open 还是 fail-close | (b) 先行，(a) 与 A07 一起做；Redis 故障 fail-open 并记日志 |
| Q6 | Admin Key 在 App 里的定位 | (a) 保持现状，App 推荐账号 + 密码 + TOTP，Admin Key 标“不推荐”；(b) 做 A08 的 sat_ 令牌 | (a)，A08 后排 |
| Q7 | 推送 | (a) 不做，前台轮询 + 本地通知；(b) 通用 Webhook / Bark / ntfy 出站；(c) APNs（A11，站点要保存 Apple p8 私钥） | (a)；确有需要先做 (b) |
| Q8 | Passkey 的范围 | iOS Associated Domains 要在构建时写死域名，而 App 支持任意站点。(a) 只对构建时列入的站点提供 Passkey（配合 A10）；(b) 首版不做 Passkey | (b)；自用站点再按 (a) 加 |
| Q9 | 清错误会重新启用停用账号（C18） | (a) 默认不变，只加可选 preserve_inactive；(b) 默认改为只在 status=error 时改 active（行为变更；`DECISIONS.md:113` 用户已接受“重新授权会重新启用”，要确认 Web“批量重置状态”是否依赖） | (a) |
| Q10 | 预置 P95 / P99 延迟规则（D07） | A：补评估支持（数据现成）；B：迁移停用并允许编辑 | A |
| Q11 | 分组“可用不足”的兜底阈值（D02，分组没有可用性告警规则时） | (a) available < total × 0.5 或 available = 0；(b) 只看 available = 0；(c) 做成站点设置 | (a)，用 default_min_ratio 参数可覆盖 |
| Q12 | 总充值与余额提醒的口径（E05、E10） | 管理员正向充值是否也累加 users.total_recharged？累加后余额提醒的百分比阈值随之变化（`service/balance_notify_service.go:109`）。站点 default_balance 自动发放是否也写一条调整记录（source=default_balance）？ | 对外统一以 balance-history 的 total_recharged 为准；users.total_recharged 倾向累加管理员充值，让百分比阈值反映真实充值；default_balance 入账 |
| Q13 | `PUT /admin/users/:id` 的 balance 字段 | (a) 保持静默忽略，文档注明已废弃；(b) 请求带 balance 时返回 400。Web 的 UserEditModal 不发这个字段 | (b)；至少做 (a) |
| Q14 | rpm-status 不限额时是否计数（E08） | (a) 只加 tracked 标记；(b) 配置开关 rpm.track_unlimited，热路径多一次 Redis；(c) 从 usage_logs 估算 | (a) |
| Q15 | 移动端基线的分支策略（A01） | (a) 把 d75c49405 合入 main，后续都在 main 上改；(b) 保持独立分支，长期 rebase | (a)：只改前端、无冲突 |
| Q16 | 强制 Idempotency-Key（RequireKey:true）而 Web 不带头的写接口怎么处理（已核实，2026-10-18） | 共 11 个：代理新建、账号新建、批量新建、账号数据导入、Codex 会话导入、批量生成兑换码、创建用量清理任务、订阅续期、系统更新 / 回滚 / 重启（逐个证据见 H08）。关闭 observe_only 后它们在 Web 上都会报 IDEMPOTENCY_KEY_REQUIRED。(a) 全部改用可选幂等（H08）；(b) Web 给这些请求补上头 | (a)；G01 的 generate、G03 用同一个“可选幂等 + 超时”变体 |
| Q17 | 【待核实】重统计查询是否超过手机端 10 秒（B10） | 没有在生产量级库实测 | 打开 ENABLE_SERVER_TIMING 实测 throughput-trend 24h / 30d、usage/stats 30d、dashboard/models 30d，再决定 B10 的预聚合与 models / groups 预聚合表 |
| Q18 | 账号列表 `status=active` 是否排除过载账号（C14） | (a) 不改 active，新增 schedulable_now 派生值；(b) 让 active 与 IsSchedulable 对齐（Web“正常”筛选的结果会变） | (a) |
| Q19 | vendor 在使用记录里能看到多少终端用户信息（E02） | (a) 只给 user id；(b) user id + 打码邮箱；(c) 原样 | (b) |

