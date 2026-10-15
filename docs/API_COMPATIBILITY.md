# 首版接口适配边界

源码基线：自用 Sub2API `40bee5d2e`。以下路径均以 `/api/v1` 为前缀。传输使用显式 snake_case CodingKeys、`{code,data,reason}` 响应 envelope。Admin Key 使用 `x-api-key`，邮箱会话使用 Bearer；禁止自动跨源重定向和共享 Cookie。

| 能力 | 方法和路径 |
| --- | --- |
| 公开设置 | GET `/settings/public` |
| 邮箱登录 / TOTP | POST `/auth/login`、`/auth/login/2fa` |
| 会话 / 刷新 / 退出 | GET `/auth/me`；POST `/auth/refresh`、`/auth/logout` |
| 二次验证 | POST `/user/totp/step-up` |
| 概览 / 趋势 | GET `/admin/dashboard/stats`、`/admin/dashboard/trend` |
| 可选监控 | GET `/admin/ops/dashboard/overview` |
| 账号列表 / 详情 / 今日统计 | GET `/admin/accounts`、`/admin/accounts/:id`、`/admin/accounts/:id/today-stats` |
| 调度 / 刷新 / 测试 | POST `/admin/accounts/:id/schedulable`、`/refresh`、`/test` |
| 用户列表 / 详情 / 更新 | GET `/admin/users`、`/admin/users/:id`；PUT `/admin/users/:id` |
| 用户用量 | GET `/admin/usage/stats?user_id=:id&start_date=...&end_date=...&timezone=...` |
| 用户密钥 | GET `/admin/users/:id/api-keys` |
| 用户余额 | POST `/admin/users/:id/balance`，`Idempotency-Key` 为持久化 UUID |

用户用量明确显示“本月”；旧 `/admin/users/:id/usage` 在基线中返回占位数据，因此不使用。账号测试使用 POST body 的 `model_id`，SSE 按增量 UTF-8 解析，支持 CRLF/心跳/多行帧；需要明确完成事件，拒绝畸形或过大的事件。

监控接口不可用时显示不可用，不伪造零值；不会让可选监控失败抹去成功的概览。站点未提供必需字段时返回协议错误，避免默默填充不真实的统计值。

金额用 Decimal 解码，写入为精确十进制字符串。余额原请求保留 `serverID`、`userID`、金额、操作、备注和 UUID。结果不明时仅允许复用原请求；站点身份不匹配会阻断请求。幂等有效期及最终状态以服务端为准，超出服务端记录保留期后应先通过 Web 对账。

会话失效、权限不足、验证码、TOTP/step-up、会话绑定不匹配和 `ADMIN_COMPLIANCE_ACK_REQUIRED` 分别显示中文原因。合规确认在 Web 完成；Admin Key 不能完成需要邮箱会话的 step-up。刷新采用 actor 内共享任务；只对明确令牌过期的安全 GET 自动重试，管理写入需用户重新确认。

第二阶段再选定明确的官方版本执行兼容测试。新增其他后端支持应在 Sub2Core 适配层处理，不在各页面分散猜测字段。
