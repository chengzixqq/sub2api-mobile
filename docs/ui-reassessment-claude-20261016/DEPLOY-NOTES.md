# 部署前必读：原生 iOS 管理端后端适配（3bcd2577d → 70116315d）

## 1. 范围

本文覆盖 sub2 仓库 `main` 分支从基线 `3bcd2577d`（2026-10-18）到当前 HEAD `70116315d`（2026-10-22）之间的 130 个提交，也就是“原生 iOS 管理端后端适配清单”的实现：A 认证与会话、B 仪表盘、C 账号、D 运维监控、E 用户与 Key、F 分组、G 兑换码与资金、H 代理 / 幂等 / 公告，以及 A11 出站推送。

信息来源：进度表备注（51 条）、迁移 247–257 原文、`git diff 3bcd2577d..HEAD -- deploy/` 与 `backend/internal/config/config.go`，以及部分提交说明和源码核对。这里只写部署相关的内容，App 侧的接口细节以 sub2 `docs/API_ERROR_CODES.md` 为准。

大部分改动只是加字段或加路由，老调用方不受影响。下面列的是需要你动手、需要你拍板，或者 Web / 脚本能感知到的变化。

---

## 2. 部署前必须做 / 必须决定的事

按重要性排序。每条都写了“不处理会怎样”和“怎么处理”。

### 2.1 `deploy/upgrade-compose.sh` 会拒绝这次升级（必须）

- **不处理会怎样**：脚本会先用候选镜像对线上库执行 `migration-preflight --require-no-pending`。这次有 11 个待执行迁移（247–257），预检必然失败，脚本输出 `Migration preflight failed; the running service was not changed` 后退出。从脚本里的 `schema_gate: require_no_pending` 看，它是为“不带新迁移的升级”设计的；它的自动回滚也只换回旧镜像，不会撤销数据库改动（`deploy/README.md` 原文写明了这一点）。
- **怎么处理**：这次改为手工升级。
  1. 先用新镜像做一次不带 `--require-no-pending` 的预检，确认只有 pending、没有 missing / extra / checksum 不符：
     `SUB2API_IMAGE=<新镜像> docker compose run --rm --no-deps -T --entrypoint /app/migration-preflight sub2api`
     期望 pending 正好是 247–257 这 11 个。
  2. 备份 PostgreSQL（pg_dump）、Redis（RDB）和 data 目录。
  3. 改 `.env` 里的 `SUB2API_IMAGE`，然后执行 `docker compose up -d sub2api`。迁移会在启动时自动执行，见 2.2。

### 2.2 迁移在启动时执行，部分迁移会阻塞写入，需要挑低峰时段（必须）

- **不处理会怎样**：进程启动时先跑迁移，跑完才对外服务（`repository/ent.go`，超时 10 分钟；有 advisory lock，多实例同时启动时只有一个在跑）。每个 .sql 文件在单独的事务里整份执行，锁要等这个文件提交后才释放。248、249、256、257 用的是普通 `CREATE INDEX`（没有 CONCURRENTLY），建索引期间会阻塞对应表的写入。其中 257 会锁住 `accounts`（网关运行时写得很频繁）和 `ops_alert_events`；248 会锁住 `redeem_codes`（兑换、生成码、余额 / 并发调整都要写这张表）。
- **怎么处理**：先看几张表的规模：
  ```sql
  SELECT relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) AS size
  FROM pg_stat_user_tables
  WHERE relname IN ('redeem_codes', 'admin_user_adjustments', 'accounts', 'ops_alert_events');
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

---

## 3. 数据库迁移

迁移执行器按文件名顺序处理 `backend/migrations/*.sql`。每个文件在一个事务里整份执行（只有 `_notx.sql` 是逐条执行的，这次没有这类文件）。执行器只记录 `schema_migrations(filename, checksum, applied_at)`。这 11 个新迁移都**没有 Down 段**，所以“回滚”只能手工写 SQL。

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
| 257 | `257_push_notifications.sql` | 新表 `push_devices`、`push_deliveries` 及各自的索引；另外在三张现有表上建部分索引：`idx_ops_alert_events_resolved_at`、`idx_accounts_error_at`、`idx_account_test_runs_finished_at` | 新表瞬间完成；三个部分索引都不是 CONCURRENTLY 建的，需要扫描全表，期间 `accounts`、`ops_alert_events` 不能写入，而且整个文件是一个事务，锁要到文件提交才释放 | 可保留；要删除需手工 SQL：`DROP TABLE push_deliveries, push_devices; DROP INDEX IF EXISTS idx_ops_alert_events_resolved_at, idx_accounts_error_at, idx_account_test_runs_finished_at;` |

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
   `SELECT filename, applied_at FROM schema_migrations WHERE filename >= '247' AND filename < '258' ORDER BY filename;`
   期望返回 11 行，从 247 到 257。
2. **版本和能力清单**：
   `curl -s -H "x-api-key: $ADMIN_KEY" "$SITE/api/v1/admin/me"`
   期望 `data.server.version` 是新版本，`data.server.capabilities` 里包含 `ops.alert_latency_metrics`、`users.balance_ledger`、`push.notifications`。
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

---

## 7. 回滚注意

### 7.1 只回滚二进制就可以的部分

- 所有迁移都只是加表、加可空列或带默认值的列、加索引。旧二进制读不到这些新列也能正常运行，新表留在库里不影响它。
- 执行器只遍历二进制自带的迁移文件，库里多出的 247–257 记录不影响旧版本启动（`migrations_runner.go` 只按文件逐个查 `schema_migrations`）。但是旧版本自带的 `migration-preflight` 会把这些记录报成 extra 并判定失败。如果你的流程里会跑预检（比如 `upgrade-compose.sh`），回滚时要跳过预检。
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
