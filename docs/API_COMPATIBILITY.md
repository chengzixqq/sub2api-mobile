# 首版接口适配边界

源码基线：自用 Sub2API `40bee5d2e`。以下路径均以 `/api/v1` 为前缀。传输使用显式 snake_case CodingKeys、`{code,data,reason}` 响应 envelope。Admin Key 使用 `x-api-key`，邮箱会话使用 Bearer；禁止自动跨源重定向和共享 Cookie。

| 能力 | 方法和路径 |
| --- | --- |
| 公开设置 | GET `/settings/public` |
| 邮箱登录 / TOTP | POST `/auth/login`、`/auth/login/2fa` |
| 会话 / 刷新 / 退出 | GET `/auth/me`；POST `/auth/refresh`、`/auth/logout` |
| 二次验证 | POST `/user/totp/step-up` |
| 概览 / 按需趋势 | GET `/admin/dashboard/stats`、`/admin/dashboard/trend` |
| 费用兼容快照 | GET `/admin/dashboard/snapshot-v2`，只开启 `include_stats`，禁用所有趋势和模型/分组统计 |
| Admin Key 权限探针 | GET `/admin/dashboard/realtime`（仅验证权限，不使用占位指标） |
| 可选监控 | GET `/admin/ops/dashboard/overview` |
| 账号列表 / 详情 / 今日统计 | GET `/admin/accounts`、`/admin/accounts/:id`、`/admin/accounts/:id/today-stats` |
| 调度 / 刷新 / 测试 | POST `/admin/accounts/:id/schedulable`、`/refresh`、`/test` |
| 用户列表 / 详情 / 更新 | GET `/admin/users`、`/admin/users/:id`；PUT `/admin/users/:id` |
| 用户用量 | GET `/admin/usage/stats?user_id=:id&start_date=...&end_date=...&timezone=...` |
| 用户密钥 | GET `/admin/users/:id/api-keys` |
| 用户余额 | POST `/admin/users/:id/balance`，`Idempotency-Key` 为持久化 UUID |

用户用量明确显示“本月”；旧 `/admin/users/:id/usage` 在基线中返回占位数据，因此不使用。账号测试使用 POST body 的 `model_id`，SSE 按增量 UTF-8 解析，支持 CRLF/心跳/多行帧；需要明确完成事件，拒绝畸形或过大的事件。

概览初次加载先请求基础统计，单次请求等待预算为 90 秒；前台等本次请求结束后间隔 30 秒刷新。趋势和详细运行监控通过各自按钮按需加载，分别使用 45 秒、15 秒预算，不参加自动轮询；下拉刷新更新基础统计，必要时独立刷新费用快照。趋势使用“昨日以来”的小时数据，而非首屏默认查询 7 天历史。每个分区独立处理失败、重试和最后更新时间，刷新失败保留该分区已成功的数据，切站或离开页面取消旧请求。

Admin Key 激活连接只通过受相同管理员认证和合规守卫保护的 `/admin/dashboard/realtime` 验证权限；当前后端该接口的指标为占位值，绝不用于显示。当前源码没有 stats lite 模式；添加 `mode=lite` 或 `lite=true` 不会减少计算。`snapshot-v2` 的 `include_stats=true` 会刷新统计，不能当成轻量替代。

概览金额明确区分 `today_actual_cost`（用户实际扣费）、`today_account_cost`（上游账号成本）和 `today_cost`（标准费用）；界面显示前两项，不用标准费用替代缺失值。当前 `/stats` handler 遗漏账号成本，因此仅在该字段缺失时，独立补取只含 stats 的 snapshot-v2（45 秒客户端预算，服务器共享计算预算仍为 30 秒）。费用请求不会阻塞基础统计，每次主统计完成后按 90 秒间隔检查是否需要更新，也可手动刷新；失败局部显示并保留基础数据。费用快照中的实际与成本成对显示，并标注单独更新时间；超过缓存有效期的值在下次页面刷新时显示不可用。服务端今日的边界由服务器决定，snapshot 请求日期/手机时区不能改变该统计日。

累计 Tokens 使用 `total_tokens`，包含缓存 Tokens。今日和累计 Tokens 按 Web 的固定两位 K/M/B 格式缩写。顶部第 6 张卡片显示最近五分钟平均 RPM/TPM，替换原异常账号卡片；异常账号移入“运行健康”，与累计请求平均响应时间并列。后者使用 `average_duration_ms`，单位毫秒，达到 1000 时转秒，不套用最近五分钟口径。新字段可缺，缺失或 null 显示不可用，畸形金额仍按协议错误处理。

趋势接口继续使用 GET `/admin/dashboard/trend`，不增加查询范围或请求数量。后端 `cost` 为标准计费，`actual_cost` 为用户实际消费；原生 `TrendPoint.actualCost` 为可选 Decimal，兼容原初始化接口。`actual_cost` 缺失或 null 时，实际消费显示不可用并跳过对应柱子，不使用 `cost`、零值或推算金额替代；请求数和 Tokens 指标仍可查看。响应中的重复日期桶保留最后一条，不累加重复的消费；非法日期单独提示并跳过。

趋势默认显示“实际消费”，可切换“请求数”和“Tokens”。切换指标、左右滚动、点选柱子、双指缩放及加减按钮均处理已经加载的数据，不发起新请求，也不扩大“昨日以来”的小时查询。缩放改变真实可见时间跨度；上限按总跨度计算，最大放大时窗口为 3 个桶的时长，不足 3 桶时显示全部。极小非零金额使用随数据调整的 Y 轴范围，不用固定最小范围将柱高压成零。

趋势桶 `yyyy-MM-dd HH:00` 按请求时区解析并排序，采用月/日与小时两行刻度，同时显示当前可见范围和完整起止时间。点选后显示对应时段的完整数值，也可打开逐小时明细；请求数与 Tokens 不缩写，金额直接使用 Decimal 全精度，只有绘图坐标转换为近似 Double。缩放到上限时在柱子上显示数值，完整明细不依赖柱内标签的显示空间。

图表交互使用 iOS 17 的原生 Swift Charts API：`chartScrollableAxes`、`chartXVisibleDomain`、`chartScrollPosition`、`chartXSelection` 和 `chartGesture`；双指手势与按钮共用可见时间窗口。

监控接口不可用时显示局部错误，不伪造零值；不会让可选监控失败抹去成功的概览。站点未提供必需字段时返回协议错误，避免默默填充不真实的统计值。服务端趋势查询本身还有 30 秒预算；客户端隔离慢查询不能替代服务器侧数据库优化。

金额用 Decimal 解码，写入为精确十进制字符串。余额原请求保留 `serverID`、`userID`、金额、操作、备注和 UUID。结果不明时仅允许复用原请求；站点身份不匹配会阻断请求。幂等有效期及最终状态以服务端为准，超出服务端记录保留期后应先通过 Web 对账。

会话失效、权限不足、验证码、TOTP/step-up、会话绑定不匹配和 `ADMIN_COMPLIANCE_ACK_REQUIRED` 分别显示中文原因。合规确认在 Web 完成；Admin Key 不能完成需要邮箱会话的 step-up。刷新采用 actor 内共享任务；只对明确令牌过期的安全 GET 自动重试，管理写入需用户重新确认。

第二阶段再选定明确的官方版本执行兼容测试。新增其他后端支持应在 Sub2Core 适配层处理，不在各页面分散猜测字段。
