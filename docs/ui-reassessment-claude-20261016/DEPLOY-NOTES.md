# 部署前必读：生产 e5ab7e4f4 → main a4aa1f619（原生 App 后端适配 + 官方 v0.2.18）

## 1. 范围

这次上生产的版本是 sub2 `main` 的 `a4aa1f619`（版本号 0.2.18），生产当前是 `e5ab7e4f4`。两者之间有三部分：

1. `e5ab7e4f4 → 3bcd2577d`：2 个提交，只加了 App 验证码桥页（前端 `MobileVerifyView` 与前端路由），只改了前端、文档和 `.gitignore`，不涉及后端、迁移和配置。
2. `3bcd2577d → 5905b30a9`：“原生 iOS 管理端后端适配清单”的 131 个提交：A 认证与会话、B 仪表盘、C 账号、D 运维监控、E 用户与 Key、F 分组、G 兑换码与资金、H 代理 / 幂等 / 公告、A11 出站推送，最后一个提交是镜像入口脚本权限修正。**第 2–7 节写的主要是这一部分。**
3. 合入官方 v0.2.18（合并提交 `6f2db67bf`，B1–B11 由你拍板）以及审查后的 5 个修正提交，到 `a4aa1f619`。**这一部分单独写在第 8 节**，部署前必做的事已经并入第 2 节（2.13–2.17）。

测试环境验证（2026-10-25，Codex 在 `/opt/sub2test`）：用 `a4aa1f619` 构建的镜像（`deploy/Dockerfile`，Go 1.27.3）跑了三条路径，都通过：现有测试库原地升级、从 `e5ab7e4f4` 带造的数据升级、全新安装。每条路径 25 项接口检查和 10 项断言全部通过，321 个迁移校验和一致，数据行数与内容保留，生产全程未受影响。单个迁移的耗时没有测出来（测试数据很小，日志也没有迁移起止标记），生产上的耗时按第 2.2 节估。

信息来源：进度表备注、迁移原文、`git diff` 中 `deploy/` 与 `backend/internal/config/config.go` 的变化、提交说明与源码核对、官方 v0.2.16→v0.2.18 的提交记录、v0.2.18 审查结论。这里只写部署相关的内容，App 侧的接口细节以 sub2 `docs/API_ERROR_CODES.md` 为准。

大部分改动只是加字段或加路由，老调用方不受影响。下面列的是需要你动手、需要你拍板，或者 Web / 脚本能感知到的变化。

---

## 2. 部署前必须做 / 必须决定的事

按重要性排序。每条都写了“不处理会怎样”和“怎么处理”。

### 2.1 升级步骤：先预检，再起绿色实例，迁移跑完再切流（必须）

生产是自建蓝绿部署（当前在跑的是 `linapi-sub2api-rolling-rpm-60s-20261015-green`），不用 `deploy/upgrade-compose.sh`。这个脚本会对线上库执行 `migration-preflight --require-no-pending`，而这次有 12 个待执行迁移，它一定会拒绝。

1. **构建镜像**：用 `a4aa1f619` 的源码执行 `docker build -f deploy/Dockerfile`。构建阶段用的是 `golang:1.27.3-alpine`；如果构建机缓存了旧的 builder 镜像，先拉新的。
2. **备份**：PostgreSQL（pg_dump）、Redis（RDB）和 data 目录。迁移没有 Down 段，出问题只能从备份恢复数据库。
3. **预检**：用新镜像对生产库跑一次**不带** `--require-no-pending` 的 `/app/migration-preflight`（连接参数与生产实例相同，`--entrypoint /app/migration-preflight`）。期望结果与测试环境一致：
   ```
   status=PASS require_no_pending=false embedded=321 applied=309 pending=12 out_of_order_pending=0 missing=0 extra=0 checksum_mismatches=0
   ```
   pending 依次是 `246_enable_gemini_image_generation_groups.sql`、`247_restore_ops_alert_silences.sql` 到 `257_push_notifications.sql`。只要出现 missing、extra 或 checksum 不一致，就停下，不要继续。`applied` 的数字以实际为准。
4. **执行部署前 SQL**：第 2.3（延迟告警规则）、2.13（记下关着生图的分组）、2.14（易支付商品名、退款中的订单）、2.15（gpt-5.5 映射）。
5. **启动新实例**：新容器启动时先跑迁移，跑完才对外服务（有 advisory lock，同一时间只有一个实例在迁移）。迁移期间旧实例照常服务：这些迁移除了官方 246 那一条改生图开关的 UPDATE，都只是加表、加可空列或带默认值的列、加索引，旧代码在新结构上能正常运行（已核对：旧代码对这些表都是按列名读写，`config_version` 有默认值）。但第 2.2 节列的几个迁移在执行期间会阻塞对应表，**包括 `users` 表的写入（余额扣费会排队）**，所以要挑低峰时段。迁移执行器没有设 `lock_timeout`。
6. **验证新实例**：健康检查通过后，按第 6 节逐项验证。迁移完成后至少等 5 分钟再切流：两个版本共用 Redis 里的 API Key 认证缓存（TTL 300 秒），这段时间新实例可能读到迁移前的生图开关。之后按你平时的方式切流、排空旧实例。
7. **回滚**：切回旧实例即可，数据库不用回滚。注意事项见第 7 节。

### 2.2 迁移在启动时执行，部分迁移会阻塞写入，需要挑低峰时段（必须）

- **不处理会怎样**：进程启动时先跑迁移，跑完才对外服务（`repository/ent.go`，超时 10 分钟；有 advisory lock，多实例同时启动时只有一个在跑）。官方 246 是对 `groups` 表的一条带条件的 UPDATE，只锁命中的几行，瞬间完成（会触发分组的认证缓存失效触发器，因为只改了生图开关，触发器直接返回，没有副作用）。每个 .sql 文件在单独的事务里整份执行，锁要等这个文件提交后才释放。248、249、256、257 用的是普通 `CREATE INDEX`（没有 CONCURRENTLY），建索引期间会阻塞对应表的写入。其中：
  - **257** 一开始建 `push_devices` 时就对 `users` 加了外键锁（SHARE ROW EXCLUSIVE），一直持有到整个文件提交，也就是要等后面 `accounts`、`ops_alert_events` 上的索引建完。这段时间 `users` 不能写入，**网关每次请求的余额扣费都会排队**；`accounts`（网关运行时写得很频繁）和 `ops_alert_events` 也不能写入。
  - **248、256** 先 `ALTER TABLE ... ADD COLUMN`（拿 ACCESS EXCLUSIVE 锁），再在同一个事务里建索引，所以建索引期间 `redeem_codes`、`admin_user_adjustments` 的**读和写都会被挡住**。`redeem_codes` 在兑换、生成码、余额 / 并发调整时都要用。
- **怎么处理**：先看几张表的规模：
  ```sql
  SELECT relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) AS size
  FROM pg_stat_user_tables
  WHERE relname IN ('users', 'redeem_codes', 'admin_user_adjustments', 'accounts', 'ops_alert_events', 'account_test_runs');
  ```
  表都不大的话直接部署。表很大的话，可以在部署前手工用 `CREATE INDEX CONCURRENTLY IF NOT EXISTS` 建好同名索引（必要时先 `ADD COLUMN IF NOT EXISTS` 把新列加上）。迁移文件里写的都是 `IF NOT EXISTS`，遇到已有的同名对象会直接跳过。索引名和定义见第 3 节。

### 2.3 P95 / P99 延迟告警部署后会持续报警（必须）

- **不处理会怎样**：D07 恢复了两条预置规则的评估：`P95延迟过高`（> 2000 ms）和 `P99延迟过高`（> 3000 ms）。两条都是启用状态、开着邮件、级别 P2、窗口 5 分钟、持续 10 分钟才触发。旧版本根本不评估这两个指标，所以你以前没见过它们报警。耗时统计的是整段请求，流式请求包含整个输出过程，所以多数站点部署后大约 10 分钟内就会持续触发 P2；如果开了告警邮件且通知级别包含 P2，还会发邮件。
- **怎么处理**：部署前执行下面的 SQL。评估器每一轮都会重新读规则（`ops_alert_evaluator_service.go`），所以部署后再执行也会在下一轮生效。
  ```sql
  -- 1) 先看现状（如果你自建过同类规则，也会一起列出来）
  SELECT id, name, enabled, threshold, window_minutes, sustained_minutes, severity, notify_email
  FROM ops_alert_rules
  WHERE metric_type IN ('p95_latency_ms', 'p99_latency_ms');

  -- 2a) 直接停用
  UPDATE ops_alert_rules SET enabled = false, updated_at = NOW()
  WHERE metric_type IN ('p95_latency_ms', 'p99_latency_ms');

  -- 2b) 或者保留规则、调高阈值（单位 ms；<...> 换成你按本站耗时定的值）
  UPDATE ops_alert_rules SET threshold = <P95 阈值>, updated_at = NOW() WHERE metric_type = 'p95_latency_ms';
  UPDATE ops_alert_rules SET threshold = <P99 阈值>, updated_at = NOW() WHERE metric_type = 'p99_latency_ms';

  -- 2c) 或者继续评估，只关掉邮件
  UPDATE ops_alert_rules SET notify_email = false, updated_at = NOW()
  WHERE metric_type IN ('p95_latency_ms', 'p99_latency_ms');
  ```
  定阈值时可以参考：评估用的值就是运维看板 overview（raw 模式）里的耗时 P95 / P99，可以先在 Web 运维页看最近的实际数值。部署后也能在 Web 告警规则编辑器里改，那里新增了这两个指标选项。停用一条正在报警的规则后，它的 firing 事件会在一个评估周期内自动关闭（D06）。推送的默认订阅最低级别是 P1，所以这两条 P2 告警默认不会推送到手机。

### 2.4 JWT access token 默认有效期从 24 小时改为 60 分钟（需确认配置）

- **不处理会怎样**：`jwt.access_token_expire_minutes` 的默认值从 0 改成了 60。0 的含义是回退到 `jwt.expire_hour`，也就是 24 小时。如果你的配置文件里**显式写了** `access_token_expire_minutes: 0`（照旧版 `config.example.yaml` 复制的配置就是 0），部署后仍然是 24 小时，不会自动变成 60 分钟。安装向导生成的 config.yaml 只写 `expire_hour`，不写这一项，所以这类站点会直接用上新默认值 60 分钟。
- **怎么处理**：
  - 想用 60 分钟：删掉这一行，或者改成 60。
  - 想保持 24 小时：显式写 0。
  - 环境变量 `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` 也能生效（viper AutomaticEnv），但 `docker-compose.yml` 的 environment 列表里没有透传它。用 compose 部署时，实际只有 config.yaml 里的值起作用。`.env.example` 里的示例值已经从 0 改成了 60。
  - Web 端在收到 401 时会自动用 refresh token 刷新（`frontend/src/api/client.ts`），用户感觉不到变化。如果有自写脚本用 JWT（而不是 Admin Key）调接口，脚本需要自己用 refresh token 续期。
- **同时上线的刷新令牌规则**（不用配置，但需要知道）：refresh token 轮换后，30 秒宽限期内（`jwt.refresh_reuse_grace_seconds`，默认 30）用旧令牌重试，拿到的是同一个继任令牌；超过宽限期再用旧令牌，会返回 401 `REFRESH_TOKEN_REUSED`，并撤销整个会话。反复使用同一个旧 refresh token 的脚本会把自己踢下线。

### 2.5 固定 `TOTP_ENCRYPTION_KEY`（要用推送时必须）

- **不处理会怎样**：这个变量留空时，每次启动都会随机生成一个密钥。没有固定密钥的情况下：`PUT /api/v1/admin/push/config` 保存 p8 私钥会返回 400 `SECRET_ENCRYPTION_KEY_NOT_CONFIGURED`；Bark / ntfy / Webhook 设备的令牌、secret、endpoint 会以明文存进数据库。如果日后更换密钥，已加密的设备凭据就解不开了，这些设备会被停用（`disabled_reason=secret_undecryptable`），需要重新登记。
- **怎么处理**：用 `openssl rand -hex 32` 生成一个密钥，写进 `TOTP_ENCRYPTION_KEY`（compose 已透传这个变量）或 config.yaml 的 `totp.encryption_key`，之后不要再改。这把密钥同时用于 2FA。对原来留空的站点，按 `.env.example` 的注释，2FA 绑定本来每次重启都会失效，所以改成固定密钥后，已开 2FA 的管理员需要重新绑定一次。
- **验证**：`GET /api/v1/admin/push/config` 返回 `encryption_key_configured: true`。

### 2.6 推送出站开关默认关闭，局域网自建 ntfy / Bark 需要手动打开（按需）

- **不处理会怎样**：推送目标有一套独立的出站策略 `security.push_targets.*`。默认只接受公网主机的 https 地址；真正发送时还会再校验解析出的 IP，不走代理，也不跟随重定向。它和 `security.url_allowlist`（默认允许私网和 http）互不相干。所以即使你的 URL 白名单是放开的，登记局域网 ntfy / Bark 时仍会被拒，返回 `INVALID_PUSH_TARGET`。
- **怎么处理**：设置 `SECURITY_PUSH_TARGETS_ALLOW_PRIVATE_HOSTS=true`；如果目标地址是 `http://`，再加上 `SECURITY_PUSH_TARGETS_ALLOW_INSECURE_HTTP=true`（这时令牌和推送内容都是明文传输）。这两个变量 compose 已经透传。只有在你信任所有管理员的情况下才打开：开启后，任何一个管理员都能让服务器去访问内网地址。

### 2.7 APNs 需要在站点上配置 p8 私钥（要用 iOS 推送时必须）

- **不处理会怎样**：iOS 设备照样能登记，但推送发不出去（`PUSH_NOT_CONFIGURED`，503）。
- **怎么处理**：先完成 2.5。Web 端没有这个配置界面（本次前端没有改推送相关的部分），需要通过 App，或者直接调用 `PUT /api/v1/admin/push/config`（只限站长，并且需要 step-up 二次验证）。字段有：`apns_enabled`、`apns_team_id`、`apns_key_id`、`apns_private_key`（p8 文件内容，只能写入，不会回显，审计日志里做了脱敏）、`apns_topic`（通常就是 App 的 bundle id）、`apns_environment`（`production` 或 `sandbox`）。这套配置只对用同一个 Apple Team 的 p8 签名构建的 App 有效。

### 2.8 余额账本口径变了：总充值会变大，注册赠送会出现在兑换码列表里（需要决定是否接受）

- **会怎样**（E10，`e5e873458` 及后续修正）：
  - 管理员充值（按净增额计）、新建用户时的初始余额、注册和第三方首次登录或首次绑定时按站点 `default_balance` 发放的余额，现在都会累加到 `users.total_recharged`。因此百分比类型的余额提醒、快捷充值里 low_balance 的阈值都会随之变大。历史数据不回填。
  - 站点 `default_balance > 0` 时，每注册一个新用户、每发生一次首次绑定赠送，都会写一条 `admin_balance` 兼容记录。这条记录会出现在三个地方：Web 兑换码管理列表（默认不排除 admin_* 类型）、`/admin/redeem-codes/stats` 的 `by_type.admin_balance` 计数、用户自己的兑换历史（备注是“初始余额”）。
  - 注册和建用户与账本写入在同一个事务里，账本写失败时注册也会失败。这是以前没有的失败场景。
- **怎么处理**：没有配置开关可以关掉。如果不能接受，需要和开发者沟通是否先不上 E10。

### 2.9 依赖旧状态码的脚本或第三方集成要先核对（需要决定）

下面这几条最容易打断现有脚本，完整列表见第 5 节：
- OAuth 换码时授权码被拒：OpenAI / Grok 从 502 `*_TOKEN_EXCHANGE_FAILED` 改为 400 `*_CODE_REJECTED`；Claude 从 500 改为 400。
- `POST /api/v1/admin/accounts/today-stats/batch` 请求的账号全部查询失败时，从 200 + 全 0 改为 503。
- `PUT /api/v1/admin/users/:id` 带 `balance` 字段时，从静默忽略改为 400。
- user-breakdown 的 `limit` 越界改为返回 400；管理端批量今日消费超过 1000 个 ID 时返回 400。
- recover-state / clear-error 带了格式错误的请求体时返回 400。
- 删除不存在的兑换码返回 404，删除已用过的兑换码返回 409。
- 复用已轮换的 refresh token 会导致整个会话被撤销（见 2.4）。

### 2.10 多实例部署（需要决定流量怎么路由）

- reauthorize 换码后的暂存数据，和 OAuth 会话一样只保存在单个实例的内存里：重试必须打到同一个实例，实例重启后数据就没了。
- 运维监控开关的 PUT、sat_ 令牌的吊销，在其他实例上最多约 30 秒后才生效。
- 异步账号测试的 worker 上限按实例计算，每个实例 10 个。系统指标是每个实例每分钟各写一行。
- 推送调度靠 leader 锁协调，多实例部署时同一条推送只发一次。

### 2.11 vendor（工作区）用户的权限收紧了（需要提前通知 vendor）

- vendor 给 Claude 授权接口传了别家或站长的代理时，现在返回 404 `PROXY_NOT_FOUND`。如果你之前把平台代理绑给了 vendor 的账号，vendor 在 Web 重新授权这个 Claude 账号时会失败。解决办法是改绑到该工作区自己的代理，或者由站长代为授权。
- 其他收紧项（使用记录脱敏、共享分组计数、定时测试计划等）见第 5 节，这些都是越权修复，vendor 会看到的数字或可见内容会变少。

### 2.12 前端要和二进制一起更新

- `deploy/Dockerfile` 用 `-tags embed` 把前端打进二进制，用镜像部署不需要额外操作。
- 如果前端是单独部署的：必须重新构建前端，才能用上 D07 规则编辑器的新选项、D09 运维监控卡片和 C19 编辑深链。此外 `/api/v1/settings/public` 的 `mobile_verify_path` 会一直是空字符串，App 拿不到验证码桥页地址；`/admin/me` 也不会下发 `web.accounts_edit_deep_link`。

### 2.13 官方迁移 246 会打开 gemini / antigravity 分组的生图开关，而且不可撤销（必须先记录）

- **会怎样**：`246_enable_gemini_image_generation_groups.sql` 把所有 platform 为 `gemini` 或 `antigravity`、`allow_image_generation = false` 的分组改成 `true`。同时，“允许当前分组生图”这个开关从 v0.2.18 起也管 Gemini 系入口（`/v1/messages`、`/v1/chat/completions`、`/v1/responses`、`/v1beta`）；新建 gemini / antigravity 分组一律默认开启，建分组时传 false 也不生效，要关只能事后编辑。你在 B10 选择了接受官方这个行为。
- **生产上原来是什么情况**：生产版本 `e5ab7e4f4` 里，这个开关只对 OpenAI / Grok 入口起作用，Gemini / Antigravity 的入口根本不检查它（在 gemini / antigravity 分组上只影响批量生图资格）。所以生产上那些 `false` 的 gemini / antigravity 分组，本来就能正常生图，这个 `false` 多半只是旧版本建分组时的默认值。迁移改成 `true` 后，实际生图行为不变。
- **怎么处理**：部署前先查出现在是 `false` 的分组，记下 ID。上线后**不是“关回去恢复原状”**：只有从现在起确实想禁止 Gemini 生图的分组才需要关；关掉之后，这个分组的 Gemini 生图请求会返回 400，这是新增的限制。
  ```sql
  SELECT id, name, platform FROM groups
  WHERE deleted_at IS NULL AND platform IN ('gemini', 'antigravity') AND allow_image_generation = false
  ORDER BY id;
  ```
- **composite 分组**：迁移不会改 composite 分组。composite 分组的这个开关默认是关的，并且同时管 OpenAI 生图。升级后，没开生图的 composite 分组如果收到 Gemini 生图请求，会直接返回 400（升级前能出图）。如果为了恢复 Gemini 生图打开这个开关，这个分组的 OpenAI 生图也会一起放开。先看看有哪些：
  ```sql
  SELECT id, name FROM groups
  WHERE deleted_at IS NULL AND platform = 'composite' AND allow_image_generation = false
  ORDER BY id;
  ```

### 2.14 支付与退款：上线前查两处配置和数据（必须）

- **易支付商品名不能含 `&` 或 `=`**（B9 选②，这次升级没有行为变化）：这条规则生产版本已经在执行（定制提交 `a077aa233` 引入），B9 选②就是保留它；官方原版反而不限制商品名。规则是 EasyPay 旧版（legacy）参与签名的非空参数（包括商品名 name）不能含 `&`、`=` 或控制字符，并强制 MD5、拒绝重复参数。建单时就会校验，所以商品名含这些字符时，用户**下单会直接失败**。商品名来自套餐的 `product_name`（为空时是 `Sub2API Subscription <套餐名>`），再加上后台设置的商品名前缀 / 后缀。作为检查项查一下：
  ```sql
  SELECT id, name, product_name FROM subscription_plans
  WHERE product_name ~ '[&=]' OR name ~ '[&=]';
  SELECT key, value FROM settings
  WHERE key IN ('PRODUCT_NAME_PREFIX', 'PRODUCT_NAME_SUFFIX') AND value ~ '[&=]';
  ```
  两条都应该查不到结果。查到了说明这些套餐现在就下不了单，在后台改掉即可，和这次升级无关。
- **处在“退款中”（`REFUND_PENDING`）的订单**（B8 选③）：这是部署前**必须先查、查到了就要先处理**的一项。
  - v0.2.18 起，`PrepareRefund` / `ExecuteRefund` 不再接受 `REFUND_PENDING` 状态的订单，这类订单只能在管理端用“查询退款”收尾。
  - **生产遗留的支付宝退款订单在新版里没有收尾办法**：生产版本记下的支付宝退款号是支付宝交易号或 `<订单号>-refund`，新版查询退款要求前缀是 `<订单号>-refund-`，所以这些订单点“查询退款”一律返回 `REFUND_QUERY_UNSUPPORTED`。新版也没有人工收尾的接口，订单会一直卡在 `REFUND_PENDING`。
  - 卡住的订单还会让对应的支付实例**无法停用、删除，也改不了受保护的配置**（返回 `PENDING_ORDERS`）。
  - 部署前先查：
    ```sql
    SELECT id, out_trade_no, payment_type, provider_key, refund_amount, refund_requested_at
    FROM payment_orders WHERE status = 'REFUND_PENDING' ORDER BY id;
    ```
  - **查到了怎么办**：最好在升级前，用当前版本对这些订单执行“查询退款”收尾。收尾不了的（特别是支付宝），先到支付宝后台核对退款是否到账，再请开发者给出收尾 SQL（改订单状态，并按旧版本的口径补扣余额或订阅天数），不要重发退款。查不到就没有这个问题。
- **上线后**：用一笔测试订单走一遍 EasyPay 下单、回调和对账（第 6 节第 13 项）。

### 2.15 GPT-5.5 已从 ChatGPT 账号退役，相关映射要先改（需要检查）

- **会怎样**：OpenAI 在 2026-10-15（北京时间）把 GPT-5.5 从 ChatGPT 登录的 Codex 下线了。v0.2.18 起，OpenAI OAuth / SetupToken 账号不再调度 gpt-5.5，公开模型列表也会把它过滤掉；`gateway.openai_compact_model: gpt-5.5` 对 ChatGPT 账号不再生效。API Key 账号不受影响。已存的设置都不会被自动改写。
- **怎么处理**：排查分组和账号的模型映射、客户端默认模型、定时任务里有没有指向 gpt-5.5、又只能落到 OAuth 账号的情况，按 sub2 `docs/OPENAI_GPT55_RETIREMENT.md` 换成上游实际可用的模型。账号的模型映射存在 `accounts.credentials` 的 `model_mapping` 里，可以这样粗查：
  ```sql
  SELECT id, name, platform, type FROM accounts
  WHERE deleted_at IS NULL AND platform = 'openai' AND type IN ('oauth', 'setup-token')
    AND credentials::text LIKE '%gpt-5.5%';
  ```
  分组上的默认映射模型也可能指向 gpt-5.5：
  ```sql
  SELECT id, name, platform FROM groups
  WHERE deleted_at IS NULL
    AND (default_mapped_model LIKE '%gpt-5.5%' OR messages_dispatch_model_config::text LIKE '%gpt-5.5%');
  ```

### 2.16 composite 分组里的重叠映射会直接返回 400（需要检查）

- **会怎样**：composite 分组中，如果 OpenAI 网关族的 OAuth / setup-token 账号（包括 Grok OAuth）和另一个平台的任意账号同时显式映射同一个模型，而按模型名兜底又落在 OpenAI 网关，v0.2.18 起这类请求直接返回 400（WebSocket 入口是直接关闭连接），提示配置显式路由。以前会把 ChatGPT token 误发到 Anthropic，上游 401 后逐个把账号打成临时不可调度。
- **怎么处理**：上线前检查 composite 分组里有没有这种重叠映射，有的话配置显式路由（见 sub2 `docs/COMPOSITE_GROUPS.md`）。上线后观察这类分组有没有 400。

### 2.17 新配置项 `gateway.min_output_tokens` 不能小于 16（需确认配置）

- 控制 Chat Completions / Anthropic 请求转成 Responses 时 `max_output_tokens` 的下限，默认 128（以前写死 128）。配置里设了小于 16 的值时，启动校验会直接失败（`gateway.min_output_tokens must be at least 16`）。没设这一项的不用管。

---

## 3. 数据库迁移

迁移执行器按文件名顺序处理 `backend/migrations/*.sql`。每个文件在一个事务里整份执行（只有 `_notx.sql` 是逐条执行的，这次没有这类文件）。执行器只记录 `schema_migrations(filename, checksum, applied_at)`。这次生产要执行 12 个迁移：下表的 247–257，加上官方 v0.2.18 的 `246_enable_gemini_image_generation_groups.sql`（见第 2.13 节）。官方 246 和生产已经执行过的 `246_dashboard_hourly_invalidation.sql` 同号，两个文件并存，按文件名排在后面，所以在生产上是正常的待执行项，不是乱序。这些迁移都**没有 Down 段**，所以“回滚”只能手工写 SQL；官方 246 改过的生图开关也无法自动还原，只能按第 2.13 节记下的 ID 手工改回。

| 编号 | 文件名 | 内容 | 是否加锁或耗时 | 可否回滚 |
|---|---|---|---|---|
| 247 | `247_restore_ops_alert_silences.sql` | 重建 `ops_alert_silences` 表和 `idx_ops_alert_silences_lookup` 索引。037 是 goose 格式的文件，执行器整份执行时连回滚段一起跑了，所以这张表在所有库上从来没存在过，Web 告警的“静默”功能一直报错 | 新建空表，瞬间完成，不锁现有表 | 不建议回滚，旧版代码同样会查这张表；一定要删就执行 `DROP TABLE ops_alert_silences;` |
| 248 | `248_redeem_code_batches.sql` | `redeem_codes` 加两个可空列 `batch_id UUID`、`created_by BIGINT`；建 `idx_redeem_codes_batch_id`（部分索引）和 `idx_redeem_codes_created_at (created_at DESC, id DESC)` | 加列只改元数据；两个索引不是 CONCURRENTLY 建的，建索引期间 `redeem_codes` 不能写入，耗时随行数增长 | 仅加列可保留；要删除需手工 SQL：`DROP INDEX IF EXISTS idx_redeem_codes_batch_id, idx_redeem_codes_created_at; ALTER TABLE redeem_codes DROP COLUMN IF EXISTS batch_id, DROP COLUMN IF EXISTS created_by;` |
| 249 | `249_admin_user_adjustments_request_id_index.sql` | `admin_user_adjustments(request_id)` 部分索引，用于按 X-Request-ID 核对余额调整 | 需要扫描全表建索引，期间这张表（余额调整）不能写入，通常表不大 | 可保留；要删除需手工 SQL：`DROP INDEX IF EXISTS idx_admin_user_adjustments_request_id;` |
| 250 | `250_add_account_error_at.sql` | `accounts` 加 `error_at TIMESTAMPTZ NULL`，不回填，存量错误账号为 NULL | 只改元数据，瞬间完成；需要短暂的 ACCESS EXCLUSIVE 锁，如果有长事务占着 `accounts`，会排队等待，并挡住后面的请求 | 仅加列可保留 |
| 251 | `251_add_account_config_version.sql` | `accounts` 加 `config_version BIGINT NOT NULL DEFAULT 0`，作为 PATCH / If-Match 的版本号 | PostgreSQL 11 及以上只改元数据，瞬间完成（compose 用的是 `postgres:18-alpine`）；更老的版本会重写整张表 | 仅加列可保留 |
| 252 | `252_admin_access_tokens.sql` | 新表 `admin_access_tokens`（sat_ 令牌，只存 SHA-256），一个唯一索引加一个普通索引，外键关联 `users` | 新表，瞬间完成；建外键时会对 `users` 短暂加锁 | 可保留；删表会丢掉所有 sat_ 令牌：`DROP TABLE admin_access_tokens;` |
| 253 | `253_ops_alert_event_rule_snapshot.sql` | `ops_alert_events` 加 `rule_snapshot JSONB`、`resolved_by_user_id BIGINT`，不回填 | 只改元数据，瞬间完成 | 仅加列可保留 |
| 254 | `254_add_scheduled_test_result_upstream_status.sql` | `scheduled_test_results` 加 `upstream_status_code INT NULL`，不回填 | 瞬间完成 | 仅加列可保留 |
| 255 | `255_account_test_runs.sql` | 新表 `account_test_runs`（异步测试和手动测试的结果），4 个索引，其中一个是“每个账号最多一条 running”的部分唯一索引；外键关联 `accounts`，ON DELETE CASCADE | 新表，瞬间完成；建外键时会对 `accounts` 短暂加锁 | 可保留；要删除需手工 SQL：`DROP TABLE account_test_runs;`（257 在这张表上建的索引会一起删掉） |
| 256 | `256_admin_user_adjustments_redeem_code_id.sql` | `admin_user_adjustments` 加 `redeem_code_id BIGINT`，并建部分唯一索引；没有外键，不回填，不动 append-only 触发器 | 加列瞬间完成；唯一索引需要扫描全表，期间这张表不能写入 | 仅加列可保留；append-only 触发器会不会拦截 DROP COLUMN 待核实（依据：迁移注释只说“不碰触发器”），建议保留 |
| 257 | `257_push_notifications.sql` | 新表 `push_devices`、`push_deliveries` 及各自的索引；另外在三张现有表上建部分索引：`idx_ops_alert_events_resolved_at`、`idx_accounts_error_at`、`idx_account_test_runs_finished_at` | 新表瞬间完成；三个部分索引都不是 CONCURRENTLY 建的，需要扫描全表，期间 `accounts`、`ops_alert_events` 不能写入；`push_devices` 的外键还会让 `users` 从文件开头起就不能写入（余额扣费排队）；整个文件是一个事务，锁要到文件提交才释放 | 可保留；要删除需手工 SQL：`DROP TABLE push_deliveries, push_devices; DROP INDEX IF EXISTS idx_ops_alert_events_resolved_at, idx_accounts_error_at, idx_account_test_runs_finished_at;` |

注意：
- 如果手工执行了上表里的回滚 SQL，必须同时执行 `DELETE FROM schema_migrations WHERE filename = '<文件名>';`。否则下次升级时执行器认为这个迁移已经跑过，会跳过它，新代码就会因为缺表或缺列报错。
- 不要修改这些 .sql 文件。执行器会校验 checksum，文件内容不一致时启动会直接失败。
- 不在迁移里的 schema 无关变化：D04 开始写入 `ops_error_logs.duration_ms`（这一列早就存在）；D10 只在 JSON 里加字段。

---

## 4. 配置项变化

### 4.1 配置文件 / 环境变量

| 配置键 | 环境变量 | 默认值 | 作用 | 谁需要改 |
|---|---|---|---|---|
| `jwt.access_token_expire_minutes` | `JWT_ACCESS_TOKEN_EXPIRE_MINUTES`（compose 没有透传） | **60**（原来是 0，即 24 小时） | access token 有效期；设为 0 时回退到 `jwt.expire_hour`；超过 720 时启动会打警告 | 配置里显式写了 0、又想用 60 分钟的；想保持 24 小时的要显式写 0（见 2.4） |
| `jwt.refresh_reuse_grace_seconds`（新增） | `JWT_REFRESH_REUSE_GRACE_SECONDS`（compose 没有透传） | 30 | refresh token 轮换后旧令牌的宽限期，0 表示不宽限；超过宽限期再用旧令牌会撤销整个会话 | 一般不用改；移动网络差的话可以适当调大 |
| `security.push_targets.allow_private_hosts`（新增） | `SECURITY_PUSH_TARGETS_ALLOW_PRIVATE_HOSTS`（compose 已透传） | false | 允许本机、局域网、链路本地地址作为推送目标 | 用局域网自建 ntfy / Bark 的 |
| `security.push_targets.allow_insecure_http`（新增） | `SECURITY_PUSH_TARGETS_ALLOW_INSECURE_HTTP`（compose 已透传） | false | 允许 `http://` 推送目标（明文传输） | 推送目标是 http 地址的 |
| `totp.encryption_key`（键没变，新增了用途） | `TOTP_ENCRYPTION_KEY`（compose 已透传） | 空（每次启动随机生成） | 除了 2FA，现在还用来加密 APNs p8 私钥和推送设备凭据；不固定就无法保存 p8 | 要用推送的必须固定（见 2.5） |
| `gateway.min_output_tokens`（新增，v0.2.18） | `GATEWAY_MIN_OUTPUT_TOKENS`（compose 没有透传） | 128 | Chat Completions / Anthropic 请求转成 Responses 时 `max_output_tokens` 的下限；小于 16 时启动失败 | 设过小于 16 的值的（见 2.17） |
| `idempotency.observe_only`（默认值没变，只改了注释） | compose 和 `.env.example` 里都没有 | true | 设为 false 时，强制幂等接口不带 key 会返回 400；本次把 Web 不带 key 的 11 个接口和用户新建 API Key 改成了可选幂等，false 时这些接口照常执行 | 设成 false 的站点不用改配置，只是行为变好了（见第 5 节） |

`docker-compose.yml` 和 `docker-compose.local.yml` 只新增了两个 `SECURITY_PUSH_TARGETS_*` 变量。`.env.example` 改了 `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` 的示例值（0 改为 60），并新增了两个推送开关。`config.example.yaml` 新增了 `security.push_targets` 段，修改了 `observe_only` 的注释和 `access_token_expire_minutes` 的示例值。

### 4.2 站点设置（存在数据库里，在 Web 设置页或接口修改，不在配置文件里）

| 设置键 | 默认值 | 作用 | 谁需要改 |
|---|---|---|---|
| `session_binding_native_mode`（新增） | strict | 原生客户端（App）的会话绑定模式，可选 strict / device / ua_only / off；Web 会话仍按 IP + UA 绑定，不受影响 | App 用户在切换网络时频繁被踢下线的，可以放宽 |
| `group_shortage_min_ratio`（新增） | 0.5 | 账号状态汇总里判定分组“可用不足”的默认比例（0–1） | 按需调整 |
| `push_apns_config`（新增） | 空 | APNs 配置，通过 `PUT /api/v1/admin/push/config` 写入 | 要用 iOS 推送的（见 2.7） |

---

## 5. 行为变化（Web 和 API 调用方能感知到的）

格式统一为“改之前 → 改之后”。只加字段或只加路由的条目用“只增”标出，这类变化不影响老调用方。

### 5.1 认证与会话

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| access token 有效期 | 默认 24 小时 → 默认 60 分钟（显式配置 0 的仍是 24 小时） | 用 JWT 调接口的脚本；Web 会自动续期，用户无感 |
| 复用已轮换的 refresh token | 返回 `REFRESH_TOKEN_INVALID`，并且并发刷新可能分叉出两条都有效的令牌链 → 30 秒内重试拿到同一个继任令牌；超过 30 秒返回 401 `REFRESH_TOKEN_REUSED`，并撤销整个会话 | 自己保存 refresh token 的脚本 |
| 登出或撤销会话后的 access token | 到期前一直可用 → 立即返回 401 `TOKEN_REVOKED`（依赖 Redis，Redis 读取失败时放行） | 所有客户端 |
| 会话管理 | 无 → 新增 `GET /api/v1/auth/sessions`、`DELETE /api/v1/auth/sessions/:id`；`revoke-all-sessions` 可以带 `{"keep_current":true}`，请求体格式错误返回 400；撤销操作记入审计 | 用户、管理员 |
| 错误响应 | 部分错误只有 code 和 message → 统一带字符串 `reason`；登录 / 刷新限流的 429 增加 `code`、`reason=RATE_LIMITED`、`retry_after`（原有 error 字段和 Retry-After 头保留）；合规 423、后端模式 403、2FA 临时会话过期都加了 reason | 解析错误体的调用方（只增） |
| 验证码提供方声明 | 无 → 登录、注册、发验证码、找回密码、Passkey 登录开始这几个接口可以带 `captcha_provider`；与站点实际生效的提供方不一致时返回 400 `CAPTCHA_PROVIDER_MISMATCH`（站点没开验证码时带了声明也返回 400）；不带声明时行为不变 | 只影响带声明的客户端 |
| 公开设置 | → `GET /api/v1/settings/public` 增加 `captcha_provider`、`mobile_verify_path` | 只增 |
| 审计日志脱敏 | `tencent_captcha_ticket`、`tencent_captcha_randstr` 以明文入库 → 与新增的 `aliyun_captcha_param` 一起记为 `***` | 查审计日志的人 |
| 管理访问令牌 sat_ | 无 → 支持 `x-api-key: sat_...`，默认只读、有效期 90 天；只读令牌调写接口返回 403 `ACCESS_TOKEN_READ_ONLY`（例外：撤销自己、`POST accounts/runtime/batch`、`POST accounts/today-stats/batch`、4 条推送设备路由）；创建令牌需要登录会话加 step-up；审计记录令牌所属的真实用户 | 站长 |
| 管理端身份接口 | 无 → 新增 `GET /api/v1/admin/me`（身份、能力清单、各项开关），不受合规守卫限制 | 只增 |
| Web 会话失效后跳登录页 | 登录后回到默认首页 → `/admin` 下的页面会带上 `redirect`，登录后回到原来的页面 | Web 管理员 |

### 5.2 账号

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| Claude OAuth 换码失败 | 会话过期和授权码被拒都返回 500 "internal error" → 400，带 `*_OAUTH_SESSION_NOT_FOUND` / `*_CODE_REJECTED` | Web（显示 message）、脚本 |
| OpenAI / Grok OAuth 换码被拒 | 502 `*_TOKEN_EXCHANGE_FAILED` → 400 `*_CODE_REJECTED`；被拒时不再写 [ERROR] 日志，改为一条脱敏的 WARN | 依赖旧错误码的脚本 |
| Claude 粘贴的授权码带 `#state` | 不校验 → 与会话里的 state 不一致时直接拒绝，不调用上游（不带 `#` 的粘贴方式仍不校验）；这一条没有在真实 Claude 账号上走过 | 站长、vendor（上线后需要手工验证，见第 6 节） |
| Gemini 换码的配置类错误 | message 是 "error: code=… reason=…" 这样的调试串 → 干净的文字说明 | 显示 message 的地方 |
| recover-state / clear-error 的请求体 | 任何内容都忽略 → 格式错误或类型不对时返回 400，且不做任何读写；不带请求体、`{}` 时与以前完全一致 | 发送垃圾请求体的第三方脚本 |
| `today-stats/batch` 全部账号查询失败 | 200 + 全 0 → 503 `ACCOUNT_STATS_UNAVAILABLE`，Web 账号列表的今日统计进入错误态（只查 1 个账号且失败也算这种情况）；部分失败仍返回 200 | Web 账号页 |
| 账号列表的 `status` 参数带逗号 | 按原字符串匹配，结果必然为空 → 按多个值取并集；去重后超过 16 个值返回 400；账号导出、upstream-billing-rates 等共用这套筛选的路径也一样 | 脚本 |
| 账号列表和详情的字段 | → 增加 `concurrency_available`、`token_status`、`error_at`、`error_kind` 等字段（只增）；列表 ETag 会因此变化一次；并发读取失败时 `current_concurrency` 填 0 占位 | 只增 |
| OAuth 账号的凭据 | → 令牌被替换时多写 `_token_refreshed_at`、`expires_in` 两个不敏感的键 | 导出凭据的人 |
| 混合渠道冲突的 409 | 只有 error 和 message → 增加 `code=409`、`reason=MIXED_CHANNEL_WARNING`、metadata、details；Web 拦截器里的 `error.code` 从 undefined 变成 409（三个账号弹窗不读这个字段，不受影响） | 读取 error.code 的代码 |
| 定时测试结果的上游状态码 | 网络错误导致的失败会沿用前一次请求的 2xx → 改为 null；Antigravity 遇到 429 从 null / other → 429 / rate_limit | 看测试结果的人 |
| 账号测试的首字时间 | 6 条会先发本地提示的测试路径，first_token_ms 约为 0 → 改为上游真实的首字时间（数值变大），失败时为 null | 看测试结果的人 |
| SSE 手动测试 | 结果不落库 → 每次测试多写一行 `account_test_runs`（每个账号保留最近 20 条）；SSE 末尾追加 `test_result` 事件，已有事件的内容和顺序不变 | 数据库（只增） |
| vendor 读别家账号的定时测试计划 | 200 → 404 `ACCOUNT_NOT_FOUND` | vendor |
| vendor 新建账号时绑了未授权的分组 | 带别家分组名的 409 → 404 `RESOURCE_NOT_FOUND` | vendor |
| vendor 调 Claude 授权接口时传别家或站长的代理 | 放行 → 404 `PROXY_NOT_FOUND`，不发上游请求（见 2.11） | vendor |
| 新建账号 | → 可选 `schedulable=false`、`skip_default_group_bind`；不传时行为不变 | 只增 |

### 5.3 运维监控（含仪表盘统计）

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| P95 / P99 延迟规则 | 不评估 → 评估，并会持续报警（见 2.3） | 开了运维监控的站点 |
| 已停用或已删除规则的 firing 事件 | 一直处于 firing，并常驻在计数里 → 每轮评估时置为 resolved；部署后第一轮就会关闭存量的这类事件 | 看告警列表的人 |
| 告警静默 | Web 上点“静默”一直报错（表不存在），没有平台作用域的规则（包括全部预置规则）也无法静默 → 可以正常使用，并新增列表、修改、撤销接口；被静默的告警不推送（与邮件同样的口径） | 站长 |
| 运维看板带 `model` 参数 | → 即使 `mode=preagg` 也按 raw 查询，不再返回 409；`model_source=mapping` 或其他非法值，即使不带 model 也返回 400（Web 不发这个参数） | 脚本 |
| openai-token-stats | → `?start_time=&end_time=` 这种空串占位返回 400；自定义时间跨度上限 31 天 | 脚本 |
| ops overview / throughput-trend 的相对时间窗口 | 实时计算 → 结束时间向下取整到 5 秒，并缓存 5 秒，数据最多晚 5 秒；响应头增加 `X-Snapshot-Cache` | Web 运维页 |
| ETag / 304 | → dashboard/stats、admin/users、admin/groups、snapshot-v2、dashboard/home、today-stats/batch 等接口带强 ETag，加上 `Cache-Control: private, no-cache` 和 `Vary: If-None-Match`；304 只省带宽，服务端仍跑完整查询 | 反向代理、浏览器（对 Web 透明） |
| Web 运维监控设置 | 保存时提交整张表单 → 只提交改动过的字段（两端改同一项时，后写入的生效）；设置页“功能” tab 新增运维监控卡片；运维页和 404 拦截器改为跳转到 `/admin/settings?tab=features` | Web 管理员 |
| 错误日志的耗时 | `ops_error_logs.duration_ms` 从来没写入过 → 开始写入，三个错误列表增加耗时和首字时间（历史数据为 null） | 只增 |
| 上游重试链 | → 新产生的 upstream_errors 事件带 `started_at_unix_ms`、`duration_ms`；重试链接口遇到非法 request_id 从 500 改为 400，409 返回的列表改为最新的在前 | 只增 / 脚本 |
| 用户排行 users-ranking | 成本按 SUM(total_cost) 计算 → 只算 provider_cost_recorded 的行（数字变小）；total_users 和各项合计在 LIMIT 之前计算；`sort_by` 非法时返回 400 `INVALID_SORT_BY` | 看排行的人 |
| user-breakdown | `limit` 超出 1–200 或不是数字时静默回落到 50 → 返回 400；同时传 request_type 和 stream 时不再按 AND 组合（排行数字可能略有变化）；`model_source=` 空串按默认值 requested 处理 | 脚本 |
| dashboard 共用筛选参数的 400 文案 | → 统一为 `Invalid <参数名>`（trend、models、groups、users-trend 等一起变） | 匹配错误文案的脚本 |
| dashboard/groups 带 model 且 `model_source=upstream/mapping` | 实际仍按请求模型匹配 → 按所选口径匹配，数字会变 | 看统计的人 |
| users-trend 带筛选且 `metric=actual_cost` | 按 tokens 选前 N 个用户 → 按成本选前 N 个，返回的用户会变 | 看统计的人 |
| 管理端批量今日消费（users-usage / api-keys-usage） | 不限数量 → 去重后有效 ID 超过 1000 个时返回 400 `TOO_MANY_IDS`（Web 每页最多 1000 条，不受影响） | 脚本 |

### 5.4 用户与 Key

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| `PUT /admin/users/:id` 带 `balance` | 静默忽略 → 返回 400 `USER_BALANCE_NOT_EDITABLE`（传 0 也算；传 null 等于不传）；Web 不发这个字段 | 脚本 |
| 管理端 `PUT /admin/api-keys/:id` 带 `status=disabled` | 400 → 接受，并归一为 inactive 写入数据库 | 脚本 |
| Key 对象 | → 增加 `effective_status`、`key_masked`；带 ETag 的用户列表在内嵌 Key 到期前后 ETag 会变化 | 只增 |
| 管理端 Key 列表的 `current_concurrency` | 一直是 0 → 回填真实值（每次多一次 Redis 管道读取，读取失败按 0 处理） | Web |
| Key 明文 | → 带 `key_view=masked` 时 key 返回空串；`POST /admin/api-keys/:id/reveal` 需要 step-up，记入审计，响应带 `Cache-Control: no-store`；默认仍是 full，Web 不变 | 只增 |
| 平台限额 | 整表 PUT 时限额 ≥ 1e10 返回 500 → 返回 400 `INVALID_QUOTA_LIMIT`；`platform-quotas/reset` 的 404 增加 reason；新增单个平台的 PUT / DELETE / restore | 脚本 |
| 平台限额 DELETE（开启 flusher 时） | 开了 `flusher_enabled=true` 时，DELETE 会丢掉 Redis 里还没刷进库的用量，restore 恢复的是库里稍旧的用量；默认关闭 flusher 时没有这个问题 | 开了 flusher 的站点 |
| 用户侧 `POST /api/v1/keys` | `observe_only=false` 时不带 key 返回 400 → 照常新建 | observe_only=false 的站点 |
| vendor 看使用记录 | 内嵌完整的 Key 明文、用户资料、IP、UA → 用户只保留 id 和打码后的邮箱，Key 只保留 id、名称和掩码，IP 和 UA 返回空；`usage/search-users`、`usage/search-api-keys` 和用量清理对 vendor 关闭 | vendor |
| rpm-status | → 增加 `user_rpm_tracked`、`per_group[].tracked`（简易模式下一律为 false） | 只增 |
| 管理员管理用户的 Key、快捷充值头像条 | 无 → 新增替用户新建、修改、删除、读取 Key 的接口，以及 `GET /admin/users/quick-topup` | 只增 |

### 5.5 分组

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| 分组对象 | → 增加 `error_account_count`、`idle_account_count`；POST 新建分组的响应里这两项为 0 | 只增 |
| vendor 看共享分组的账号计数 | 显示全站账号数 → 只算本工作区的账号（数字变小）；vendor 的 PUT 分组在写库前多一次聚合查询，这次查询失败则整个 PUT 报错且不写库 | vendor |
| `GET /admin/groups/:id/stats` | 任意 id 都返回 200 + 全 0 → 返回真实数据；分组不存在时返回 404 `GROUP_NOT_FOUND`；对 vendor 拒绝 | 脚本、vendor |
| vendor 读分组的订阅列表 | 能读任意分组 → 拒绝 | vendor |
| capacity-summary、批量成员、today-stats 按分组 | → 可选 `group_id` / `group_ids`，新增批量加入或移出成员的接口；不带新参数时行为不变；升级后第一次按分组请求 today-stats 时缓存全部未命中一次 | 只增 |

### 5.6 兑换码与资金（含幂等）

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| 删除已用过的兑换码或 admin_* 记录 | 可以删除 → 409 `REDEEM_CODE_USED`；used_by 不为空但状态不是 used 的历史码也删不掉（Web 上“删除未使用”提示的数量会变少） | Web 兑换码页 |
| 单个删除不存在的码 | 200 → 404 `REDEEM_CODE_NOT_FOUND` | Web（只在两人同时删同一个码时会看到）、脚本 |
| batch-delete | `deleted` 把不存在或重复的 ID 也算进去 → 改为实际删除的行数，并增加 `skipped_used`、`skipped_ids`；数据库出错时从“吞掉错误、少算数量”改为整批回滚并返回 500 | 脚本 |
| 作废已用的码 / 批量修改已用的码 | 可以先把 used 改成 expired、再改回 unused，然后被别人重复兑换 → 返回 409 或整批拒绝（只改备注仍然可以） | 安全修复 |
| 兑换码统计 `/admin/redeem-codes/stats` | 写死全 0，忽略所有参数 → 返回真实计数；非法的 types、batch_id、created_* 参数返回 400（Web 没有调用这个接口） | 脚本 |
| 批量生成兑换码 | 逐个插入、没有事务，重放时码值显示为 *** → 整批一个事务、按 batch_id 去重，重放返回真实码值；响应头增加 `X-Redeem-Batch-ID` | Web、脚本 |
| 资金写操作（余额调整、生成兑换码、create-and-redeem） | 跟随请求上下文执行，客户端断网时会回滚，或者幂等记录卡在 processing 长达 24 小时 → 受理后脱离客户端连接执行（30 秒），租约过期的记录可以被同一个 key 接管 | 所有客户端 |
| 余额调整核对 | → user-adjustments 支持按 request_id、action_id、user_id 精确筛选；响应头增加 `X-Admin-Adjustment-Action-ID`；带 key 的管理端写接口增加 `X-Idempotency-Expires-At` | 只增 |
| 总充值 total_recharged | 见 2.8；balance-history 增加 before / after 和 `total_recharged_breakdown{redeem,admin,affiliate,promo,grant}` | 余额提醒、快捷充值 |
| 首次绑定赠送 | → 已透支的用户也照常加上（例如 -5 + 2 = -3），账本里的 before / after 可以是负数 | 透支用户 |
| `observe_only=false` 时 Web 不带 key 的接口（代理新建、账号新建 / 批量新建 / 数据导入 / Codex 导入、用量清理、订阅续期、系统更新 / 回滚 / 重启、生成兑换码） | 400 `IDEMPOTENCY_KEY_REQUIRED` → 照常执行 | observe_only=false 的站点 |
| 带 key 的写接口（users、groups、账号编辑等 10 个接口，以及公告新建） | → 业务出错后 5 秒内用同一个 key 重发，返回 409 `IDEMPOTENCY_RETRY_BACKOFF`；带 key 时脱离客户端连接执行，上限分别为 30 / 60 / 120 秒；batch-refresh 到时还没完成的账号记为失败；重放快照超过 64KB 时返回 503 | 带 key 的客户端（Web 修改并发时会带 key 调 PUT users） |
| 幂等指纹 | PUT users 的指纹不再包含明文密码；PUT groups 的指纹多了 `"video_model_prices":null` → 升级前 24 小时内存下的记录，用同一个 key 重发会返回 409，换一个新 key 即可 | 在升级窗口内重试的客户端 |

### 5.7 推送（新功能）

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| 推送渠道 | 无 → 支持 APNs、Bark、ntfy、Webhook；后台每 15 秒扫描一次最近 10 分钟内的事件，推送延迟最多约 15 秒；所有实例都停机超过 10 分钟时，这段时间的事件不会补推 | 站长 |
| 默认订阅 | → `ops_alert.fired` + `account.error`，最低级别 P1；account.error 对同一台设备、同一个账号 30 分钟内最多推一条 | 站长 |
| 同一个 Bark / ntfy / Webhook 目标被另一位管理员注册 | 200，并把设备转给新管理员 → 409 `PUSH_TARGET_IN_USE`（原主人已经不是 active 管理员时可以接管；iOS 令牌仍照旧转移） | 多管理员站点 |
| 审计 | → 设备注册的请求体整体不写入审计；APNs 私钥按 privatekey 规则脱敏 | 查审计日志的人 |
| 会话吊销 | → 不会自动删除推送设备，App 退出登录时需要自己调用 DELETE | 站长 |
| 资源占用 | → 有设备时，每 15 秒执行 4 条扫描查询；vendor 一律不开放 | 数据库 |

### 5.8 其他（代理、公告）

| 变化点 | 改之前 → 改之后 | 影响谁 |
|---|---|---|
| 删除仍有到期回退账号引用的代理 | 可以删除（之后“恢复原代理”时账号会静默改走直连） → 409 `PROXY_IN_USE`，metadata 里带 `fallback_account_count` | Web 代理页 |
| 恢复原代理 | 不做校验 → 原代理不存在、已停用或已过期时返回 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE` | Web 账号页 |
| 修改代理的地址或认证信息 | 延迟缓存一直不失效 → 删除缓存并异步重新探测 | Web 代理页 |
| 代理详情、公告已读统计 | → 代理详情返回与列表一致的完整数据；公告新增已读汇总和 read-status 筛选；不带新参数时只消除了 N+1 查询，结果不变 | 只增 |

---

## 6. 部署后验证清单

以下用 `$SITE` 表示站点地址，`$ADMIN_KEY` 表示 Admin API Key。

1. **迁移是否全部执行**：
   `SELECT filename, applied_at FROM schema_migrations WHERE filename >= '246' AND filename < '258' ORDER BY filename;`
   期望返回 13 行：两个 246（`246_dashboard_hourly_invalidation.sql` 是以前执行的，`246_enable_gemini_image_generation_groups.sql` 是这次执行的），以及 247 到 257。
2. **版本和能力清单**：
   `curl -s -H "x-api-key: $ADMIN_KEY" "$SITE/api/v1/admin/me"`
   期望 `data.server.version` 是 `0.2.18`，`data.server.capabilities` 里包含 `ops.alert_latency_metrics`、`users.balance_ledger`、`push.notifications`。Web 后台的版本徽章不应该提示“有更新 v0.2.18”；如果提示了，**不要点在线更新**，它会把容器里的定制程序换成官方原版。
3. **延迟告警没有刷屏**：部署 15 分钟后执行
   `SELECT count(*) FROM ops_alert_events e JOIN ops_alert_rules r ON r.id = e.rule_id WHERE e.status = 'firing' AND r.metric_type IN ('p95_latency_ms','p99_latency_ms');`
   结果应该符合你在 2.3 里的选择：选了停用的应为 0。
4. **access token 有效期**：在 Web 登录，用浏览器开发者工具查看登录响应里的 `expires_in`。用新默认值应为 3600，选择保持 24 小时的应为 86400。
5. **告警静默**：在 Web 运维页打开一条告警事件，点“静默”，不应再报错；之后 `GET /api/v1/admin/ops/alert-silences` 能列出这条静默。
6. **运维监控设置**：打开 `/admin/settings?tab=features`，能看到运维监控卡片；`GET /api/v1/admin/ops/monitoring-status` 返回的 `effective` 与你的实际设置一致。
7. **账号页**：列表和今日统计正常显示；打开 `/admin/accounts?edit=<某个账号 ID>` 会自动弹出这个账号的编辑框。
8. **Claude OAuth 和 Setup Token**：在 Web 上各完整走一遍（新建账号或重新授权都可以）。素材里明确说新增的 `#state` 校验还没有在真实账号上验证过。
9. **兑换码**：`GET /api/v1/admin/redeem-codes/stats` 返回的 `by_status` 不再是全 0；在 Web 上尝试删除一张已经用过的码，应返回 409。
10. **推送**（如果要用）：`GET /api/v1/admin/push/config` 返回 `encryption_key_configured: true`；对一台已登记的设备调用 `POST /api/v1/admin/push/devices/:id/test`，手机能收到推送；登记局域网目标时不再报 `INVALID_PUSH_TARGET`。
11. **生图开关**：按第 2.13 节记下的分组 ID，确认现在都是开启的。只有确实想从现在起禁止 Gemini 生图的分组才去关（关了会返回 400，这是新增的限制）。
12. **计费抽查**：上线后看几笔这几类请求的扣费：Grok 4.7 Fast（价格约为原来的 2 倍）、Antigravity 的 `claude-{opus,sonnet}-5-5-{high,medium,low}`（改按 5.5 基础价，比原来低）、客户端中途断开的流式请求（现在按已收集的真实用量计费，原来可能记 0）、Gemini 生图失败的请求（不应按张扣费）。
13. **支付**：用一笔测试订单走一遍 EasyPay 下单、回调、到账和对账。新版本运行期间产生的退款中订单，可以在管理端执行“查询退款”收尾；生产遗留的支付宝退款中订单会返回 `REFUND_QUERY_UNSUPPORTED`，按第 2.14 节处理。
14. **OpenAI 网关**：观察 `server_is_overloaded` 和 403 的比例（出站默认 Codex 身份从 codex-tui 改成了 codex_cli_rs，上游风控指纹会变），以及 composite 分组有没有新出现的 400（第 2.16 节）。

---

## 7. 回滚注意

### 7.1 只回滚二进制就可以的部分

- 除官方 246 那条改生图开关的 UPDATE 外，所有迁移都只是加表、加可空列或带默认值的列、加索引。旧二进制读不到这些新列也能正常运行，新表留在库里不影响它；被打开的生图开关对旧版本的 Gemini 入口本来就不起作用。
- 执行器只遍历二进制自带的迁移文件，库里多出的官方 246 和 247–257 记录不影响旧版本启动（`migrations_runner.go` 只按文件逐个查 `schema_migrations`）。但是旧版本自带的 `migration-preflight` 会把这些记录报成 extra 并判定失败。如果你的流程里会跑预检（比如 `upgrade-compose.sh`），回滚时要跳过预检。
- 镜像里内嵌了前端，回滚镜像时前端会一起回到旧版。
- 再次升级时，已经记录过的迁移会被跳过；不要修改这些 .sql 文件。

### 7.2 回滚后数据会不一致、或需要额外处理的部分

1. **延迟告警事件**：旧版不评估 p95 / p99，也没有“自动关闭已停用规则的事件”这个逻辑，所以回滚前已经在 firing 的延迟告警会一直挂着。回滚前先执行：
   ```sql
   UPDATE ops_alert_events SET status = 'resolved', resolved_at = NOW()
   WHERE status = 'firing'
     AND rule_id IN (SELECT id FROM ops_alert_rules WHERE metric_type IN ('p95_latency_ms', 'p99_latency_ms'));
   ```
2. **总充值和账本**：新版本累加到 `users.total_recharged` 的金额、注册赠送写下的账本记录和 admin_balance 兼容记录都不会撤销（账本是 append-only 的）。回滚后，百分比余额提醒的阈值仍然是变大之后的值。
3. **安全修复会一起失效**：已用过的兑换码又可以被作废、改回未使用、再次兑换（G05）；vendor 的越权问题会重新出现，包括使用记录里的 Key 明文和用户资料、分组订阅列表、别家账号的定时测试计划、借用别家代理、共享分组显示全站计数。
4. **会话**：旧版不检查 `revoked_sid` / `valid_after`，所以已经登出或被踢下线、但 access token 还没过期的会话会恢复可用（新版签发的 token 最长 60 分钟）。旧版不认识原生客户端带模式前缀的绑定哈希，App 会话可能需要重新登录（待核实，依据 `4c913cbb6`）。Web 会话的 refresh token 键格式没有变（轮换记录存在单独的 `refresh_rotated:` 键里），预计不受影响。
5. **sat_ 令牌**：旧版不认识，App 用它调接口会被拒绝。表会保留下来，再次升级后，没过期、没吊销的令牌会恢复可用。
6. **`accounts.error_at` 和 `config_version`**：旧版不维护这两列。再次升级后，回滚期间进入错误状态的账号 `error_at` 为空，因此不会触发 account.error 推送；回滚期间被修改过的账号 `config_version` 没有递增，App 的 If-Match 检测不到那段时间的改动。
7. **推送**：旧版没有调度器，回滚期间不会推送任何消息。再次升级后只扫描最近 10 分钟的事件，不会补推积压的部分。
8. **异步测试**：回滚时还处于 running 的 `account_test_runs` 记录，再次升级后超过 180 秒会被标记为 interrupted。
9. **幂等记录**：新版写入的指纹和旧版不同（PUT users 去掉了密码，PUT groups 加了 video_model_prices）。在 24 小时 TTL 内用同一个 key 重发可能返回 409，换一个新 key 即可。
10. **手工回滚了迁移**：参照第 3 节执行 SQL，并同时删除 `schema_migrations` 里对应的记录。否则再次升级时不会重建这些表和列，新代码会报错。
11. **v0.2.18 的部分**：回到旧版后，官方 246 打开的生图开关不会关回去；v0.2.18 的计费、支付、网关修复一起失效。
12. **新版本运行期间进入“退款中”的订单（回滚时风险最大的一项）**：新版本对非 V2 渠道（支付宝、Stripe、微信、Airwallex 等，EasyPay V2 除外）的退款，进入 `REFUND_PENDING` 时就已经扣掉了余额或订阅天数，并在审计里记了 `deductionHeld`。旧版本不认识这个字段：
    - 在旧版本上点“查询退款”，成功时会**再扣一次**，失败时**不会归还**已扣的部分；
    - 在旧版本上点“退款”，会重新扣减并重新向支付渠道发起退款。

    所以：**回滚前**先在新版本上对这些订单执行“查询退款”尽量收尾；回滚后还剩下的，**不要在旧版本上点“查询退款”或“退款”**，只能人工核对后处理。回滚前用这条查：
    ```sql
    SELECT id, out_trade_no, payment_type, provider_key, refund_amount, refund_requested_at
    FROM payment_orders WHERE status = 'REFUND_PENDING' ORDER BY id;
    ```

---

## 8. 官方 v0.2.18 带来的变化

来自官方 v0.2.16→v0.2.18 的 56 个提交、你对 B1–B11 的选择，以及审查后的 5 个修正。需要部署前动手的已经写在第 2.13–2.17 节，这里是完整清单，供部署后核对。完整背景见 sub2 `docs/upgrade-v0218.md`（含“审查修正”一节）。

- 新迁移 246_enable_gemini_image_generation_groups.sql 会把所有 platform 为 gemini 或 antigravity、且 allow_image_generation=false 的存量分组改成 true。这条迁移不可逆，没有 Down 段。上线前先在生产库查出这些分组 ID 记下来；需要禁止生图的，上线后在后台逐个改回 false。
- 官方 246 和我们自己的 246_dashboard_hourly_invalidation.sql 同号，两个文件并存，按文件名字典序 dashboard 先跑。生产 e5ab7e4f4 只执行到定制 246，升级后会依次补跑官方 246 和 247–257，共 12 条 pending；测试库已经跑到 257 的，会把官方 246 当乱序补跑（out_of_order_pending=1）。
- deploy/upgrade-compose.sh 固定带 --require-no-pending，这次升级 pending 一定不为 0，预检程序以退出码 2 失败，脚本随后退出、不改动运行中的服务。要按第 2.1 节先手动运行 /app/migration-preflight（不带 --require-no-pending），确认 status=PASS、missing=0、checksum_mismatches=0，再启动新版本完成迁移。
- 上线前先备份生产库。原有 309 个已执行的 SQL 文件内容没变；新增的官方 246 和 247–257 会在生产上第一次执行。测试环境验证用的是造的数据，生产上的迁移耗时按第 2.2 节估。
- 新配置项 gateway.min_output_tokens 默认 128，小于 16 时启动校验直接失败（报 'gateway.min_output_tokens must be at least 16'）。它控制 Chat Completions / Anthropic 请求转成 Responses 时 max_output_tokens 的下限，原来写死 128。生产 config.yaml 或环境变量里如果设了这个值，要确认不小于 16。
- Go 工具链升到 1.27.3（go.mod 也是 go 1.27.3），三个 Dockerfile 的构建镜像都已改成 golang:1.27.3-alpine。根 Dockerfile 的 Node 固定为 node:24.19.0-alpine（deploy/Dockerfile 仍是 node:24-alpine，运行镜像 alpine:3.20）；生产如用自建或缓存的 builder 镜像，要先拉新版本。
- VERSION 文件改为 0.2.18（官方 tag 里还是 0.2.17，审查时改掉了），上线后核对后台显示的版本号。
- 前端依赖：dompurify 升到 ^3.4.17，pnpm overrides 新增 follow-redirects>=1.16.1，pnpm-lock.yaml 已同步更新。构建要用 frozen lockfile，避免装出别的版本。
- 计费：Grok 4.7 Fast（含 grok-4.7-build-fast）改按官方 Fast 价卡计费，<200k 每百万 token 输入 $4 / 缓存读 $1 / 输出 $12，≥200k 为 $6 / $1.5 / $18，大约是原来的 2 倍；新增 gemini-4-argon 及其 cyber-permissive 变体的价格；Antigravity 的 claude-{opus,sonnet}-5-5-{high,medium,low} 改按 5.5 基础价计费，不再高收 1.25–3 倍。上线后核对这几类模型的扣费。
- 计费：Anthropic 账号的 chat/responses 兼容流和 Gemini 流式请求，客户端中途断开后会继续把上游读完，按已收集的真实用量计费（原来可能记 0）。上游没正常收尾时返回 error 帧或 response.failed，并按已观测到的用量入账。上线后核对这类请求的扣费。
- 计费（B4 选①）：Gemini 兼容入口失败结算保留真实 usage 和图片数。已切号且 ForceCacheBilling=true、按 token 计价时，可能比官方方案扣得多（差额是缓存读取的单价差）。Antigravity 原生 Gemini 出错时，图片数取已实际回吐的张数，不再按模型名猜一张。
- 账号配额：Vertex service_account 账号也支持总 / 日 / 周配额，设了上限后会累加用量、用满停止调度、跨阈值发通知；管理端账号 DTO 会多出 quota_* 可选字段（App 契约已加回归测试）。账号配额累加 SQL 改成按已设置的维度选择语句，结果和原来一致。
- 生图开关：分组的“允许当前分组生图”开关现在也管 Gemini 系入口（/v1/messages、/v1/chat/completions、/v1/responses、/v1beta）。未开启时返回 400，不换号也不处罚账号。新建 gemini/antigravity 分组一律默认开启，创建时传 false 也不生效，要关只能事后编辑。composite 分组迁移时不回填，未开启的 composite 分组升级后 Gemini 生图会直接 400。 生产版本里这个开关对 Gemini 入口不起作用，所以迁移打开存量 gemini / antigravity 分组的开关后，实际行为不变（见第 2.13 节）。
- 支付（B7 选③）：webhook 验签通过后，用同一个 provider 实例最多查单一次再履约；EasyPay / 彩虹易支付查单参数同时放在 URL query 和表单里，兼容 PHP 返回字符串数字，但仍严格校验成功码和 pid / out_trade_no / trade_no。上线后建议用测试订单走一遍 EasyPay 回调和对账。
- 支付（B9 选②）：保留定制版已有的严格校验（生产版本已经在执行，这次没有行为变化）：EasyPay legacy 参与签名的非空参数（包括商品名 name）含 &、= 或控制字符时，建单直接失败、回调拒绝验签，并强制 MD5、拒绝重复参数。官方原版不限制商品名。见第 2.14 节。
- 支付：订单类型改为白名单，只接受 balance / subscription，其他值建单时返回 INVALID_ORDER_TYPE；已支付但类型不支持的订单标记为 FAILED 并写审计。
- 退款（B8 选③）：非 V2 渠道（支付宝、Stripe、微信、Airwallex 等）的普通退款进入 REFUND_PENDING 时就先扣余额或订阅天数，之后只查询不重发，渠道回报失败时在同一事务内归还；查询报错仍保持 pending；支付宝查不到退款记录要等 10 分钟宽限期后才判失败。生产遗留的支付宝退款中订单没有可查询的退款号，会返回 REFUND_QUERY_UNSUPPORTED，需要人工核对，不能重发。EasyPay V2 仍走原有的 immutable intent 流程。见第 2.14 节、第 7.2 节第 12 项。
- 上线前在生产库查一下当前处于 REFUND_PENDING 的订单。旧格式的 pending 审计按原逻辑处理，但 PrepareRefund / ExecuteRefund 不再接受 REFUND_PENDING 状态的订单，只能通过管理端“查询退款”来收尾。
- OpenAI 网关：出站默认 Codex 身份从 codex-tui 改成 codex_cli_rs，已配对的 TUI originator 和 UA 会被归一成 CLI 身份；后台“Codex UA”留空时拼出的是 CLI UA。上游风控指纹会变，上线后观察 server_is_overloaded 和 403 的比例。
- OpenAI 网关：GPT-5.5 已经从 ChatGPT Codex 退役，OAuth / SetupToken 账号不再调度 gpt-5.5，公开模型列表也会过滤掉；gateway.openai_compact_model=gpt-5.5 对 ChatGPT 账号不再生效。上线前排查有哪些分组和账号的映射、客户端默认值指向 gpt-5.5（参考 docs/OPENAI_GPT55_RETIREMENT.md）。
- 网关路由：composite 分组里，OpenAI OAuth 账号和其他 API Key 账号同时显式映射同一个模型时，现在直接返回 400，要求配置显式路由（原来会把 ChatGPT token 误发到 Anthropic）。上线前检查 composite 分组有没有这种重叠映射。
- 网关：OpenAI API Key 账号可以通过 extra.web_search_emulation 开启 /v1/messages 的 web_search 模拟，OAuth 账号排除在外；Anthropic 协议账号的 base URL 改为优先读取 Anthropic 协议专用 base_url，配了多协议 base_url 的 API Key 账号上线后要复核出站地址。
- 限流 / 账号状态：Cloudflare 1010 的 403 对所有平台都不再处罚账号；Vertex 共享容量不足（RESOURCE_EXHAUSTED、不带明细）的 429 不再冷却账号，改为同号 1/2/4/8 秒退避重试；Vertex SA 换 token 返回 400 invalid_grant 且 account not found 时，账号会被置为 error 并停止调度。
- 调度（B2 选①）：调度快照解码结果常驻进程内存，最长复用 10 秒。滚动发布时，旧版本实例写入不会推进 revision，新实例最多可能延迟 10 秒才看到账号变化，这是已接受的边界。异步生图转存的下载不再访问内网、回环、私网地址，响应不是图片时任务直接失败。
