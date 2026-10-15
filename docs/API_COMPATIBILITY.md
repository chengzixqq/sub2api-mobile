# 首版接口适配边界

源码基线：自用 Sub2API `40bee5d2e`。以下路径均以 `/api/v1` 为前缀。传输使用显式 snake_case CodingKeys、`{code,data,reason}` 响应 envelope。Admin Key 使用 `x-api-key`，邮箱会话使用 Bearer；禁止自动跨源重定向和共享 Cookie。

| 能力 | 方法和路径 |
| --- | --- |
| 公开设置 | GET `/settings/public` |
| 邮箱登录 / TOTP | POST `/auth/login`、`/auth/login/2fa` |
| 会话 / 刷新 / 退出 | GET `/auth/me`；POST `/auth/refresh`、`/auth/logout` |
| 二次验证 | POST `/user/totp/step-up` |
| 概览 / 小时趋势 | GET `/admin/dashboard/stats`、`/admin/dashboard/trend` |
| 费用兼容快照 | GET `/admin/dashboard/snapshot-v2`，只开启 `include_stats`，禁用所有趋势和模型/分组统计 |
| Admin Key 权限探针 | GET `/admin/dashboard/realtime`（仅验证权限，不使用占位指标） |
| 运行监控 | GET `/admin/ops/dashboard/overview` |
| 账号列表 / 详情 / 今日统计 | GET `/admin/accounts`、`/admin/accounts/:id`、`/admin/accounts/:id/today-stats` |
| 调度 / 刷新 / 测试 | POST `/admin/accounts/:id/schedulable`、`/refresh`、`/test` |
| 用户列表 / 详情 / 更新 | GET `/admin/users`、`/admin/users/:id`；PUT `/admin/users/:id` |
| 用户用量 | GET `/admin/usage/stats?user_id=:id&start_date=...&end_date=...&timezone=...` |
| 用户密钥 | GET `/admin/users/:id/api-keys` |
| 用户余额 | POST `/admin/users/:id/balance`，`Idempotency-Key` 为持久化 UUID |

用户用量明确显示“本月”；旧 `/admin/users/:id/usage` 在基线中返回占位数据，因此不使用。账号测试使用 POST body 的 `model_id`，SSE 按增量 UTF-8 解析，支持 CRLF/心跳/多行帧；需要明确完成事件，拒绝畸形或过大的事件。

概览进入前台时，基础统计、小时趋势和运行监控立即发起独立请求，单次等待预算分别为 90 秒、45 秒、15 秒；各分区在自己的请求结束后间隔 30 秒刷新，慢分区不阻塞其他分区。下拉刷新并发更新这三个分区，必要时另行请求费用快照；各分区按钮仍可单独刷新或重试，同一分区的在途趋势、监控请求不重复启动。趋势使用“昨日以来”的小时数据，而非首屏默认查询 7 天历史。每个分区独立处理失败、重试和最后更新时间，刷新失败保留该分区已成功的数据；切站、离开页面或进入后台取消请求和轮询，迟到结果不能写入新会话或覆盖更新的加载结果。

Admin Key 激活连接只通过受相同管理员认证和合规守卫保护的 `/admin/dashboard/realtime` 验证权限；当前后端该接口的指标为占位值，绝不用于显示。当前源码没有 stats lite 模式；添加 `mode=lite` 或 `lite=true` 不会减少计算。`snapshot-v2` 的 `include_stats=true` 会刷新统计，不能当成轻量替代。

概览实际费用表示用户扣费，上游成本表示账号成本；今日和累计分别使用各自字段。基础统计返回 `total_requests`、`total_actual_cost`，当前后端 `/stats` handler 遗漏今日和累计账号成本，客户端独立补取只含 stats 的 snapshot-v2。今日或累计任一费用字段缺失时，仅在该周期快照提供同次响应的完整实际/成本对时整体替换；快照失败或不完整时保留基础统计已知值，缺失项显示不可用，不跨响应拼接成完整对，也不用标准计费或零值代替。费用快照附独立更新时间；视图重绘时判定超过 90 秒为过期，该判断并非严格计时失效。卡片金额使用 `compactCost(Decimal?)`：Decimal 全程舍入，固定两位，>=1000 最高使用 K，例如 `$45.08K`、`$3872.50K`；Tokens 继续使用 K/M/B，原始数值不变。 snapshot-v2 使用 45 秒客户端预算，服务器共享计算预算仍为 30 秒；费用请求不会阻塞基础统计。服务端今日边界由服务器决定，snapshot 请求日期/手机时区不能改变该统计日。

累计 Tokens 使用 `total_tokens`，包含缓存 Tokens；今日请求底部显示 `total_requests: Int?`，保留全站累计整数，缺失或 null 显示不可用。四张概要卡片为今日请求、今日 Tokens、总 Tokens 和性能指标，标准字号实测均为 112pt，辅助功能 XXXL 字号均约 279.333pt，并使用单列布局；标题与数值左上对齐。今日请求底部显示 `total_requests` 全站累计请求，缺失显示不可用。今日/总 Tokens 底部分别显示今日/累计实际费用和上游成本，用绿色/金色区分，并提供“今日/累计实际费用”“今日/累计上游成本”辅助功能文字。费用行空间不足时改为两行；独立费用卡已移除，用量趋势排在运行健康之前。 异常账号与 `average_duration_ms` 累计平均响应时间保留在趋势之后的运行健康。平均响应时间达到 1000ms 时转秒，不套用最近五分钟口径。新可选字段缺失保持不可用，畸形金额仍按协议错误处理。

趋势接口继续使用 GET `/admin/dashboard/trend`，查询范围不变；自动加载和前台轮询会发起请求。后端 `cost` 为标准计费，`actual_cost` 为用户实际消费；原生 `TrendPoint.actualCost` 为可选 Decimal，兼容原初始化接口。`actual_cost` 缺失或 null 时，实际消费显示不可用并跳过对应柱子，不使用 `cost`、零值或推算金额替代；请求数和 Tokens 指标仍可查看。响应中的重复日期桶保留最后一条，不累加重复的消费；非法日期单独提示并跳过。

趋势默认显示“实际消费”，可切换“请求数”和“Tokens”。切换指标、左右滚动、点选柱子、双指缩放及加减按钮均处理已经加载的数据，不发起新请求，也不扩大“昨日以来”的小时查询。缩放改变真实可见时间跨度；上限按总跨度计算，最大放大时窗口为 3 个桶的时长，不足 3 桶时显示全部。极小非零金额使用随数据调整的 Y 轴范围，不用固定最小范围将柱高压成零。

趋势桶 `yyyy-MM-dd HH:00` 按请求时区解析并排序，采用月/日与小时两行刻度，同时显示当前可见范围和完整起止时间。柱标签、点选读数和逐小时明细统一使用 `DashboardTrendMetric.displayValue`：金额通过 Decimal 四舍五入到固定两位小数，极小金额可显示 `$0.00`；Tokens 达到相应阈值后使用 K/M/B，选择和明细也采用相同格式；请求数保持完整整数。Y 轴金额同样显示两位小数；金额不缩写为 K。原始 Decimal 和整数不因显示格式而改变，`exactValue` 仅供原始数据与精度测试使用，只有绘图坐标转换为近似 Double。放大倍数达到 6×，或可见时间窗口不超过 6 个桶时，柱子显示数值；最大放大时仍为 3 个桶窗口，明细不依赖柱内标签的显示空间。

图表交互使用 iOS 17 的原生 Swift Charts API：`chartScrollableAxes`、`chartXVisibleDomain`、`chartScrollPosition`、`chartXSelection` 和 `chartGesture`；双指手势与按钮共用可见时间窗口。加减按钮通过 `withAnimation` 执行 0.3 秒 ease-in-out 动画，显式 `AnimatableModifier` 插值缩放倍数，再按该倍数计算 `chartXVisibleDomain`；左侧时间边界固定，到达最大放大档时也不主动取整横向位置。系统开启“减弱动态效果”时停用该动画。双指缩放连续更新窗口，不等待按钮动画或轮询。动画实现本次未改；历史 `77a2462` / `20261015T073815Z-46faa0c1` 模拟器录屏观察到第二柱宽 17 → 21 → 29 → 34 → 37 像素、柱顶高度不变，范围左端保持 `10/14 00:00`；这是时间边界固定，首个可见柱栅格边缘仍有 2 像素差异。

共享显示格式使用 `NSDecimalRound` 与十进制字符串舍入/补零，避免 Linux Foundation 的 `NumberFormatter` 固定小数行为差异。卡片 `compactCost` 金额最高 K，趋势金额仍完整两位；原值和接口精度不变。客户端源码 `e0bf7e54112d7ee695de7b9e85eeb527d03c29f8` 的 Mac 完整运行 `20261015T081613Z-5f322d22` 通过 57 项核心、4 项凭据、15 项 UI 测试和设备构建，同一源码两个 Linux Core job 也各通过 57 + 4。该结果验证受控契约与显示回归，不扩大后端版本兼容承诺。

监控接口不可用时显示局部错误，不伪造零值；不会让监控失败抹去成功的概览。站点未提供必需字段时返回协议错误，避免默默填充不真实的统计值。服务端趋势查询本身还有 30 秒预算；客户端隔离慢查询不能替代服务器侧数据库优化。自动刷新、格式化与布局的受控测试不替代真实站点响应耗时或签名后 iPhone 验收。

金额用 Decimal 解码，写入为精确十进制字符串。余额原请求保留 `serverID`、`userID`、金额、操作、备注和 UUID。结果不明时仅允许复用原请求；站点身份不匹配会阻断请求。幂等有效期及最终状态以服务端为准，超出服务端记录保留期后应先通过 Web 对账。

会话失效、权限不足、验证码、TOTP/step-up、会话绑定不匹配和 `ADMIN_COMPLIANCE_ACK_REQUIRED` 分别显示中文原因。合规确认在 Web 完成；Admin Key 不能完成需要邮箱会话的 step-up。刷新采用 actor 内共享任务；只对明确令牌过期的安全 GET 自动重试，管理写入需用户重新确认。

第二阶段再选定明确的官方版本执行兼容测试。新增其他后端支持应在 Sub2Core 适配层处理，不在各页面分散猜测字段。
