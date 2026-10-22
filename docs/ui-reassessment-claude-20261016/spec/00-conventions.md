# 00 · 通用约定

> 本章适用于 Sub2 原生 iOS 管理端（SwiftUI，最低 iOS 26）的所有页面。各页面章节直接引用这里的规则，不再重复。
>
> - **后端基线**：sub2 `main` `70116315d`（2026-10-22 对照源码核对）。本章写到的路径、字段、reason、capability 都在这个提交里查过；旧站点按第 5 节降级。
> - **口径优先级**：`DECISIONS.md`（第 3 轮以“更正”为准，文末“设计稿评审意见”和“TPM 口径”最新）＞ `BACKEND-API-CHANGES.md` 实现进度表的备注 ＞ 清单条目原文 ＞ 设计稿演示数据。
> - 路径一律写全（`/api/v1/...`）。“App 动作”指客户端代码要做的事，“文案”指界面上显示的字。

---

## 0. 硬规则速查

1. 每个请求都带 `X-Device-ID`（该站点固定的 UUID）和固定 UA `Sub2Mobile-iOS`；刷新令牌、退出、SSE 也要带（1.2）。
2. 鉴权头只能二选一：`Authorization: Bearer <access>`，或 `x-api-key: <Admin Key | sat_…>`。两个都带时服务端只认 `x-api-key`。
3. 识别错误只看 `reason`，没有 `reason` 时退回字符串 `code`；`code` 可能是整数，也可能是字符串。查表键是（HTTP 状态, reason），同一个 reason 在不同状态码下含义可能不同（3.2）。界面上不回显服务端 `message`（3.4）。
4. 资金写（余额调整、批量生成兑换码、发放补偿）带 `Idempotency-Key`，先把记录落盘再发，落盘失败就不发；新建类写入在接口接受时带 key，key 与请求体在表单里冻结到结果确定，不要求落盘。结果不明时只允许“核对”或“用同一编号重试”（2.5）。
5. `TOKEN_EXPIRED`、`STEP_UP_REQUIRED`、`ADMIN_COMPLIANCE_ACK_REQUIRED` 都在业务执行前返回：读请求处理后自动重发；写请求重发前回到确认框（2.4、2.6）。
6. 403 `ACCESS_TOKEN_READ_ONLY` 不弹二次验证，只提示“当前令牌只读”。只读 `sat_` 不发 `dashboard/users-usage`、`dashboard/api-keys-usage`（它们是 POST，不在放行表里），对应数字显示 `—`（2.6.3）。
7. 增量拉取（`since_id`）必须把游标往回退一段，再按 `id` 去重；`latest_id` 不是安全水位（4.3）。
8. 旧服务端会**静默忽略**不认识的查询参数和请求体字段。新参数只在对应 capability 存在时发送；没有 capability 时，响应要在本地复核（第 5 节）。
9. 缺失值显示 `—`，0 显示 0；“读取失败”与“真的是 0”不能混用（6.5）。
10. “今日”“小时桶”和界面上的绝对时间默认按**服务器时区**；只有管理员在 App 里输入的时间点（账号过期、公告起止、兑换码自定义过期、免打扰）按本机时区（6.3）。发给服务端的绝对时间一律用 UTC `Z` 格式。
11. 金额读出时用 `Decimal` 解码（字符串或数字都接受）。写入时只有 `POST /api/v1/admin/users/:id/balance` 的 `balance` 用字符串，其余接口按后端类型发 JSON number（由 `Decimal` 编码）；显示前在 `Decimal` 里舍入（6.1）。
12. 运维监控关闭（404 `OPS_DISABLED`）不算错误，显示“运维监控未开启”。实时监控关闭（200 + `enabled:false`）显示“实时监控未开启”，两者不能判反。
13. 切换站点或退出时，作废会话代号（generation）、取消在途请求、清空 ETag 缓存与增量游标；迟到的响应一律丢弃（沿用现有 `AppModel.sessionGeneration`）。

---

## 1. 站点与凭据

### 1.1 站点（ServerProfile）与多站点

| 项 | 规则 |
|---|---|
| 站点地址 | 只接受 `https://host[:port]`，不允许路径、userinfo、查询串和 fragment（沿用 `AppModel.validatedURL`、`ServerProfile.validatedURL`）。主机名转小写。 |
| 添加站点 | ① `GET /api/v1/settings/public`：成功且带 `version` 才算 Sub2 站点，同时取 `site_name`（作为默认站点名）、`site_logo`、`server_timezone`、`captcha_provider`、`totp_enabled`、`backend_mode_enabled`。② 选登录方式（1.3）。③ 登录成功后调 `GET /api/v1/admin/me`（1.9），通过后才写入站点列表。添加失败不能替换当前已连接的站点（沿用 `AppModel.connect` 的 candidate 机制）。 |
| 每站点独立保存 | 凭据（Keychain，service `com.chengzixqq.sub2mobile.credentials`，account = 站点 UUID）、设备标识 `deviceID`（1.2）、待核对写入（2.5.5）、推送设备 id（第 7 节）、ETag 缓存与增量游标（仅内存）、`/admin/me` 快照（仅内存）。 |
| 切换 | 概览标题下拉菜单（DECISIONS 第 2 轮）与“设置 → 站点与凭据”。切换 = 取消当前站点所有请求和定时器 → 新 generation → 读该站点凭据 → `/admin/me` → 进入概览。凭据已清除时进入该站点的登录页。 |
| 删除站点 | 先按“退出”顺序处理（1.7.5），再删除 Keychain 凭据与 `deviceID`；该站点还有待核对写入时，把站点信息留在 `profileArchive` 里（沿用现状），待核对列表仍能显示站点名。 |
| 显示 | 站点行：名称 + 主机（等宽字体）+ 登录方式徽章（账号 / 管理访问令牌 / Admin Key）+ 身份（`/admin/me` 的 `user.email`）。Admin Key 站点加一行“以 <email> 身份操作（第一个管理员）”。 |

### 1.2 设备标识与会话绑定（A04）

- **`deviceID`**：每个站点生成一个 UUID（小写），存在 Keychain（与凭据同一 service，account = `<站点 UUID>.device`，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）。重装 App 后重新生成（需要重新登录，这是预期行为）。不同站点用不同的值，避免站点之间关联同一台手机。
- **每个请求**都带请求头 `X-Device-ID: <deviceID>`（服务端全局中间件 `SessionBindingContext` 读取，最长 128 字节）。
- **登录时**（`POST /api/v1/auth/login`）在请求体里带 `client`：`{"type":"ios","device_id":"<deviceID>","device_name":"<UIDevice.current.name>"}`。`device_id` 必须与请求头的 `X-Device-ID` 相同。2FA 第二步（`/api/v1/auth/login/2fa`）不需要再带，服务端从临时会话继承。
- **服务端行为**：只有站点开启 `session_binding_enabled` 时才校验。原生会话的绑定方式由站长设置 `session_binding_native_mode` 决定：`strict`（默认，IP + UA）、`device`（只校验 `X-Device-ID`）、`ua_only`、`off`。绑定方式在签发时写进令牌，之后的刷新沿用。
  - `device` 模式下请求缺 `X-Device-ID` 或值不同，会返回 401 `SESSION_BINDING_MISMATCH`，**整个会话家族同时被撤销**。所以 1 号硬规则没有例外。
  - `strict` 模式下切换 Wi-Fi、蜂窝或 VPN 就会掉线。UA 固定为 `Sub2Mobile-iOS`，不带版本号，避免 App 或 iOS 升级导致失效（附录 B L2）。
- **提示**：`/admin/me` 的 `security.session_binding_enabled=true` 时，“站点与凭据”里该站点下显示说明“站点开启了会话绑定；切换网络可能需要重新登录”。admin 角色还可以再读 `GET /api/v1/admin/settings` 的 `session_binding_native_mode`：值为 `device` 或 `off` 时不显示这条说明，值为 `strict` 或 `ua_only` 时补一句“可请站长把原生客户端绑定方式设为 device”。

### 1.3 登录方式

| 方式 | 请求头 | 以谁的身份 | step-up | 吊销 | 有效期 | 推荐 | 限制 |
|---|---|---|---|---|---|---|---|
| **账号 + 密码（+ TOTP）** | `Authorization: Bearer` | 本人 | 可以 | 单个会话下线、退出后立即失效（1.7、1.8） | access 默认 60 分钟；refresh 30 天，每次刷新重新计时 | **推荐**，登录页默认选中 | 站点开了验证码时走桥页（1.5）；会话绑定见 1.2 |
| **管理访问令牌 `sat_…`**（A08） | `x-api-key: sat_…` | 令牌所属的管理员 | 不可以（403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`） | 在 Web 或 App 里吊销；多实例部署最多 30 秒后生效 | 签发时选 1–365 天（默认 90） | 次选：只看监控、告警的设备用只读令牌 | 需要 capability `admin.access_tokens`；只限 admin 角色；只读令牌的写操作返回 403 `ACCESS_TOKEN_READ_ONLY`（例外见 2.6.3） |
| **Admin Key** | `x-api-key: <key>` | 站点的**第一个管理员** | 不可以 | 只能在 Web 重新生成，全站一起失效 | 不过期 | **不推荐**，选项上标“不推荐” | 丢了手机等于泄露全站最高权限；审计日志都记在第一个管理员名下 |

- 登录页的三个选项按上表顺序排列。Admin Key 选项下写明：“以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。”
- 粘贴的密钥以 `sat_` 开头时，自动按管理访问令牌处理（服务端也是按前缀区分的，`server/middleware/admin_auth.go`）。
- 首版不在 App 内签发 `sat_`（未决问题 3），只支持粘贴使用；“站点与凭据”里可以列出和吊销自己的令牌：`GET /api/v1/admin/access-tokens` 返回 `{items:[{id,name,prefix,last4,scope,expires_at,last_used_at,last_used_ip,created_at,current}]}`，`DELETE /api/v1/admin/access-tokens/:id` 返回 `{message,current}`。`current=true` 表示吊销的就是本机正在用的令牌，App 要立即退出该站点。只读令牌可以吊销自己。

### 1.4 账号密码登录流程

1. **准备**：`GET /api/v1/settings/public`。
   - `backend_mode_enabled=true`：登录页提示“站点处于后端模式，仅管理员可登录”。
   - `login_agreement_enabled=true`：`login_agreement_mode=checkbox` 时，在登录按钮上方放勾选框（未勾选不能登录）；`modal` 时，点登录后先弹出协议确认。协议正文取 `login_agreement_documents[].title / content_md`（Markdown 渲染）。后端不校验这一步，App 照 Web 的做法执行。
   - 验证码：见 1.5。
2. **登录**：`POST /api/v1/auth/login`，请求体 `{email, password, client{type,device_id,device_name}, captcha_provider?, turnstile_token? | tencent_captcha_ticket?+tencent_captcha_randstr? | aliyun_captcha_param?}`。
   - 200 且 `data.requires_2fa=true`：带着 `temp_token` 和 `user_email_masked` 进入第 3 步。
   - 200 且带 `access_token`：登录成功。`data` 为 `{access_token, refresh_token?, expires_in, token_type:"Bearer", refresh_token_unavailable?, user{id,email,username,role,…}}`，进入第 4 步。
3. **两步验证**：底部弹出 6 位验证码输入（`.textContentType(.oneTimeCode)`，输满 6 位自动提交）→ `POST /api/v1/auth/login/2fa {temp_token, totp_code}`，成功时的响应与第 2 步相同。临时会话 5 分钟有效；15 分钟内最多输错 5 次。
4. **验收身份**：先检查 `user.role`。`admin` 继续；`vendor` 见 1.11；其他角色提示“当前版本仅支持管理员账号”，并调 `POST /api/v1/auth/logout` 丢掉刚拿到的会话。然后调 `/api/v1/admin/me`（1.9），通过后把凭据写入 Keychain。
5. **登录降级**：`refresh_token_unavailable=true`（服务端暂时存不了刷新令牌）时照常登录，但在概览顶部显示横幅“本次登录无法自动续期，约 <expires_in 换算> 后需要重新登录”。

| 错误 reason | 文案 | 动作 |
|---|---|---|
| `INVALID_CREDENTIALS`（401） | 邮箱或密码错误 | 清空密码框；验证码证明作废，需要重新验证 |
| `TURNSTILE_VERIFICATION_FAILED` / `TENCENT_CAPTCHA_VERIFICATION_FAILED` / `ALIYUN_CAPTCHA_VERIFICATION_FAILED`（400） | 安全验证未通过，请重新验证 | 重新打开桥页 |
| `CAPTCHA_PROVIDER_MISMATCH`（400） | 站点验证方式已变更，请重新验证 | 重新拉公开设置，按 `metadata.captcha_provider` 重新验证；不要原样重试 |
| `CAPTCHA_PROVIDER_CONFLICT`（503） | 站点同时开启了多个验证码服务，请在 Web 后台修正 | 停止登录 |
| `TOTP_INVALID_CODE`（400） | 验证码不对，请重新输入 | 清空输入框 |
| `TOTP_TOO_MANY_ATTEMPTS`（429） | 尝试次数过多，请 15 分钟后再试 | 关闭 2FA 弹层 |
| `TOTP_LOGIN_SESSION_EXPIRED`（400） | 验证超时，请重新登录 | 回到第 2 步（验证码要重新做） |
| `BACKEND_MODE_ADMIN_ONLY`（403） | 站点处于后端模式，仅管理员可登录 | 停止 |
| `USER_NOT_ACTIVE`（403） | 该账号已被禁用 | 停止 |
| `RATE_LIMITED`（429） | 登录过于频繁，请 N 秒后再试 | 按钮倒计时 N 秒（N 取 2.7.2 的规则） |
| 网络错误或 5xx | 无法连接站点 / 站点暂时不可用 | 不自动重试：验证码证明只能用一次，重试必须重新验证 |

登录接口按 IP 限流：登录、2FA 各每分钟 20 次，刷新令牌每分钟 30 次。Redis 故障时这些接口一律拒绝（429）。

### 1.5 验证码桥页（A09）

- **判断提供方**：看 `GET /api/v1/settings/public` 的 `captcha_provider`。
  - 键存在（新服务端）：`""` 表示不需要验证码；`turnstile` / `tencent` / `aliyun` 表示需要；`conflict` 直接提示“站点验证码配置冲突”，不能登录。
  - 键不存在（旧服务端）：按 `turnstile_enabled`、`tencent_captcha_enabled`、`aliyun_captcha_enabled` 三个开关推断（沿用 `PublicSettings` 的现有解码）。开了不止一个时按 `conflict` 处理。
- **打开桥页**：在 `.nonPersistent()` 数据存储的 `WKWebView` 里加载 `<站点>/mobile/verify?nonce=<新 UUID>`。只接收主框架、同 scheme、同 host、同有效端口的 `window.webkit.messageHandlers.sub2Captcha` 消息（沿用 `CaptchaView` 与 `CaptchaBridgeValidator`）。
  - `mobile_verify_path` 非空时，说明桥页已打包进后端二进制；为 `""` 时**仍然尝试打开**（前端单独部署的站点也报 `""`），同时在桥页上方提示“若页面无法完成验证，请改用 Web 登录或 Admin Key”。
  - 桥页自身限时 2 分钟，App 端限时 180 秒；加载失败时提示“站点未部署手机验证页，请改用 Web 或关闭验证码”。
- **消息到登录字段的映射**（桥页协议 version 1）：

| 桥页 `provider` | 桥页 `proof` | 登录请求体（服务端有 `captcha_provider` 键时） | 登录请求体（旧服务端） |
|---|---|---|---|
| turnstile | `turnstile_token` | `captcha_provider:"turnstile"`、`turnstile_token` | `turnstile_token` |
| tencent | `tencent_captcha_ticket`、`tencent_captcha_randstr` | `captcha_provider:"tencent"`、两个字段原样 | 两个字段原样 |
| aliyun | `turnstile_token`（里面是 captchaVerifyParam） | `captcha_provider:"aliyun"`、`aliyun_captcha_param:<proof.turnstile_token>` | `turnstile_token:<proof.turnstile_token>` |
| — | `cancelled:true` | 不发登录请求，回到登录页 | 同左 |

- 一个证明只用一次：登录失败、2FA 超时、取消、过期之后都要丢弃，下次重新验证。证明不写日志，也不落盘。
- 需要验证码的接口还有注册、发送验证码、找回密码、Passkey 登录开始，首版 App 都不提供。Passkey（A10）不做。

### 1.6 管理访问令牌 / Admin Key 登录

1. 输入框标签“管理访问令牌或 Admin Key”，用 `SecureField`，可粘贴。
2. 带 `x-api-key` 调 `GET /api/v1/admin/me`：
   - 200：读 `auth_method`（`admin_access_token` / `admin_api_key`）和 `user`，写入凭据。
   - 401 `INVALID_ADMIN_KEY`：文案“令牌或 Admin Key 无效（已吊销、已删除，或站点不支持管理访问令牌）”。
   - 401 `ACCESS_TOKEN_EXPIRED`：文案“管理访问令牌已过期，请重新签发”。
   - 403 `FORBIDDEN`：令牌主人已不是管理员。
   - 423：进入合规确认（1.10）。
   - 404 且响应体不是 JSON：旧服务端没有 `/admin/me`，退回 1.9 的旧服务端路径。
3. 这两种凭据没有刷新令牌，也没有会话列表（`/api/v1/auth/*` 只接受 JWT）。`/admin/me` 不返回令牌范围；`auth_method=admin_access_token` 时登录后调一次 `GET /api/v1/admin/access-tokens`，取 `current=true` 那项的 `scope`（`read` / `write`），存进站点会话的 `isReadOnlyToken`；这个请求失败时先按可写处理，收到 `ACCESS_TOKEN_READ_ONLY` 后再改成只读。只读令牌在 App 里所有写操作按钮置灰，旁边小字“只读令牌”；例外与限制见 2.6.3。

### 1.7 令牌生命周期

#### 1.7.1 有效期

- access token 默认 60 分钟（配置里显式写了 `access_token_expire_minutes: 0` 的站点仍是 24 小时），以登录或刷新响应的 `expires_in`（秒）为准。`expires_in` 缺失时按 300 秒处理（沿用现状）。
- refresh token 30 天，每次刷新重新计满。

#### 1.7.2 刷新（A03）

- **时机**：发请求前发现 `expiresAt − now < 60 秒`时，先刷新；收到 401 `TOKEN_EXPIRED` 时强制刷新一次，再把**原请求**重发一次（读写都可以重发，因为这个错误是鉴权中间件在业务执行前返回的）。
- **单飞**：同一站点同时只有一个刷新请求，其他请求等它的结果（沿用 `APIClient.validCredential` 的 actor 内 `refreshTask`）。
- **请求**：`POST /api/v1/auth/refresh {refresh_token}`，请求头照常带 `X-Device-ID` 和固定 UA，**不带** `Authorization`。响应 `{access_token, refresh_token, expires_in, token_type}`。
- **落盘先于使用**：新令牌对先写 Keychain，再换掉内存里的凭据（沿用 `commitRefresh`）。服务端有 30 秒宽限：30 秒内同一个旧 refresh token 再刷新，返回**同一个**继任令牌。所以 App 在落盘前崩溃、30 秒内重启再刷新，仍能接上；超过 30 秒再用旧令牌会得到 401 `REFRESH_TOKEN_REUSED`，并且整个会话家族被撤销。
- **结果处理**：

| 结果 | 动作 |
|---|---|
| 200 | 替换令牌对 |
| 401 `REFRESH_TOKEN_INVALID` / `REFRESH_TOKEN_EXPIRED` / `REFRESH_TOKEN_REUSED` / `TOKEN_REVOKED` | 清除该站点会话，进入登录页，文案“登录已失效，请重新登录” |
| 401 `SESSION_BINDING_MISMATCH` | 同上，文案“网络或设备信息变化导致会话失效，请重新登录” |
| 403 `USER_NOT_ACTIVE` / `BACKEND_MODE_ADMIN_ONLY` | 清除会话，文案“该账号已被禁用” / “站点处于后端模式，仅管理员可登录” |
| 429 `RATE_LIMITED`、503、5xx、网络错误、超时 | **保留会话**。本次请求按传输失败处理；下一次请求再尝试刷新，失败间隔按 2 秒、5 秒、15 秒、30 秒递增。access 已过期且刷新一直失败时，页面显示“暂时无法续期登录，正在重试” |

#### 1.7.3 吊销（A05）

- 退出、单个会话下线、撤销全部会话、刷新令牌重放、会话绑定失效、改密之后，已签发的 access token **立即**失效：下一次请求返回 401 `TOKEN_REVOKED`。App 按“会话失效”处理，不尝试刷新。
- Redis 故障时服务端放行（fail-open），所以吊销不是绝对即时，界面文案不要承诺“立即”。

#### 1.7.4 Admin Key / sat_

- 没有刷新流程。任意请求返回 401 `INVALID_ADMIN_KEY` 或 `ACCESS_TOKEN_EXPIRED` 时，清除该站点凭据，进入登录页并预选原来的登录方式。

#### 1.7.5 退出登录（顺序固定）

1. 有推送设备 id 时，先 `DELETE /api/v1/admin/push/devices/:id`（第 7 节）。失败只记下“待删除”，不阻断退出。
2. JWT 会话：`POST /api/v1/auth/logout`，请求体 `{refresh_token}`，**同时带** `Authorization: Bearer <access>`。服务端会删除刷新令牌，并让这个会话的 access token 立即失效。现有代码只带请求体、不带鉴权头，要改。
3. `sat_`：用户选择“移除站点”时，调 `DELETE /api/v1/admin/access-tokens/:id`（先从 `GET /api/v1/admin/access-tokens` 里找 `current=true` 的那条拿到 id），确认框写明“同时吊销这个管理访问令牌”。只是“退出”时不吊销。
4. 不论网络结果如何，都清除 Keychain 凭据、内存状态、ETag 缓存和游标（沿用 `AppModel.logout` 的“本地先擦除”）。

### 1.8 会话列表（A07）

- 只有 JWT 登录时显示，放在“设置 → 站点与凭据 → <站点> → 登录设备”（页面布局由设置章节定）。
- `GET /api/v1/auth/sessions` → `{items:[{id, device_name, client_type, user_agent, ip, created_at, last_seen_at, expires_at, current}]}`，按最后活跃倒序，最多 50 条。显示：设备名（为空时显示 `client_type` 或“未知设备”）、IP、“最后活跃 <相对时间>”、本机条目标“本机”。部署前就已存在的会话，第一次刷新令牌后才会出现，且没有 `client_type`。
- 单个下线：`DELETE /api/v1/auth/sessions/:id` → `{message, current}`。`current=true` 时 App 立即退出该站点。404 `SESSION_NOT_FOUND`：从列表里移除这一条。
- 踢掉其他设备：`POST /api/v1/auth/revoke-all-sessions {"keep_current":true}`，确认框写“其他设备会立即退出登录”。**必须带请求体**：不带请求体时服务端会撤销包括本机在内的全部会话，那种情况下 App 要随后本地退出。

### 1.9 启动探测：`GET /api/v1/admin/me`（A02）

**何时调用**：连接站点时（登录后、App 启动恢复会话、切换站点）；回到前台且距上次调用超过 5 分钟；合规确认成功后；二次验证成功后（用来刷新 `step_up_*`）。这个接口不受合规守卫拦截，未确认合规时也返回 200。Admin Key、`sat_`、admin JWT、vendor JWT 都能调用。

| 字段 | 用途 |
|---|---|
| `auth_method` | `jwt` / `admin_api_key` / `admin_access_token`，决定能否做二次验证、是否显示会话列表 |
| `user{id,email,username,role}` | 当前身份；Admin Key 时是第一个管理员。`role` 用于 1.11 |
| `workspace` | vendor 才有：`{id,name,permissions{account_manage,group_ops,group_billing,proxy_manage,monitor_view}}`；admin 为 null |
| `security.totp_enabled` | 本人是否启用了 TOTP |
| `security.step_up_enabled` | 站点是否开了敏感操作二次验证；false 时任何操作都不需要 TOTP |
| `security.step_up_available` | `auth_method=jwt` 且已启用 TOTP |
| `security.step_up_granted` / `step_up_expires_in` | 本会话当前是否在二次验证有效期内、剩余秒数（最长 900） |
| `security.session_binding_enabled` | 见 1.2 |
| `compliance{required,version}` | `required=true` 时先走 1.10，其他 admin 接口在确认前都会返回 423 |
| `features.ops_monitoring_enabled` | false 时监控 Tab、错误请求、上游错误、告警等区域直接显示“运维监控未开启”，不发请求 |
| `features.ops_realtime_monitoring_enabled` | 已经是“运维开 且 实时开”的结果；false 时实时类区域显示“实时监控未开启” |
| `features.ops_monitoring_disabled_reason` | `config_off`：文案“需要在服务器配置中启用运维监控”，不提供开启按钮；`setting_off`：可以引导开启（监控章节） |
| `features.channel_monitor_enabled` / `channel_monitor_mode` | 渠道监控开关与模式 |
| `features.backend_mode_enabled` / `payment_enabled` / `subscription_enabled` | 模块可见性 |
| `server.version` / `run_mode` | 版本显示在“站点与凭据”；`run_mode=simple` 时 Key 的 `effective_status` 为 expired / quota_exhausted 的仍可用（用户章节） |
| `server.server_timezone` / `server_utc_offset` | 第 6.3 节的服务器时区 |
| `server.capabilities` | 第 5 节的能力集合，存成 `Set<String>` |

**错误**：401、403 按第 3 节处理；没有 423。

**旧服务端**（404 且响应体不是 JSON）：

- JWT：并发调 `GET /api/v1/auth/me`（取 `role`、`run_mode`、`workspace`）、`GET /api/v1/settings/public`（取 `server_timezone`、`server_utc_offset`、`version`、`channel_monitor_*`、`backend_mode_enabled`），以及 `GET /api/v1/admin/compliance`。
- Admin Key：调 `GET /api/v1/admin/compliance`（它不受合规守卫拦截，可当权限探针，替代现在的 `dashboard/realtime`）。
- capability 集合视为空，运维开关先当作“开启”，遇到 `OPS_DISABLED` 再把对应区域标成“未开启”。

### 1.10 合规确认（423）

- 触发：`/admin/me` 的 `compliance.required=true`，或任一 admin 请求返回 423 `ADMIN_COMPLIANCE_ACK_REQUIRED`。请求体 `metadata` 里有 `version`、`document_url_zh`、`document_url_en`、`document_path_*`。
- 流程：全屏 sheet。`GET /api/v1/admin/compliance` → `{required, version, document_url_zh, document_path_zh, ack_phrase_zh, …, acknowledgement?}`。用 `SFSafariViewController` 打开 `document_url_zh`（为空时用 `站点 + document_path_zh`）。输入框要求逐字输入 `ack_phrase_zh`，一致后才能点“确认”。提交 `POST /api/v1/admin/compliance/accept {"phrase":"<输入值>","language":"zh"}`，成功后重调 `/admin/me`，再重发被拦下的读请求；被拦下的写请求回到原确认框。
- 只读 `sat_` 不能提交确认（返回 403 `ACCESS_TOKEN_READ_ONLY`），文案“只读令牌不能完成合规确认，请用账号登录或在 Web 完成”。Admin Key 提交时按第一个管理员记录。

### 1.11 角色

| `user.role` | 首版行为 |
|---|---|
| `admin` | 全部功能（受 capability 与站点开关约束） |
| `vendor` | 首版拒绝登录，沿用现状：文案“当前版本仅支持管理员账号”（未决问题 2）。将来支持时按 `workspace.permissions` 与服务端白名单降级：非白名单路由返回 403 `FORBIDDEN`（“This operation is not available for your workspace”）；`sat_` 只发给 admin；推送只推给 admin；后端模式下 vendor 不能登录 |
| 其他 | 拒绝，文案同上 |

---

## 2. 请求层

### 2.1 基础 URL 与会话

- URL = `<站点 origin>/api/v1/<path>`（沿用 `APIClient.makeRequest`）。
- `URLSessionConfiguration.ephemeral`：关闭 Cookie、凭据存储和 `URLCache`，缓存策略 `.reloadIgnoringLocalCacheData`，拒绝一切重定向（沿用 `URLSessionTransport`）。ETag 由 App 自己管理（4.2），不依赖系统缓存。
- 同一站点并发请求不超过 6 个（`httpMaximumConnectionsPerHost` 默认值），首页批量请求排队。

### 2.2 请求头

| 头 | 何时带 | 值 |
|---|---|---|
| `Accept` | 全部 | `application/json`；SSE 用 `text/event-stream` |
| `Content-Type` | 有请求体时 | `application/json` |
| `User-Agent` | 全部 | `Sub2Mobile-iOS`（固定，不带版本号） |
| `Accept-Language` | 全部 | `zh-CN` |
| `X-Device-ID` | **全部**（含刷新、退出、SSE） | 该站点的 `deviceID` |
| `Authorization` | JWT 会话的业务请求、退出 | `Bearer <access_token>` |
| `x-api-key` | Admin Key / `sat_` | 原值；与 `Authorization` 互斥 |
| `X-Request-ID` | 所有写请求（读请求可选） | 本次操作的 UUID（小写，≤ 64 字节）；同一操作重试时不变。服务端写进账本 `request_id`，并在响应头原样回显 |
| `Idempotency-Key` | 2.5 列出的写接口 | 操作 UUID（小写，≤ 128 个可见 ASCII 字符） |
| `If-None-Match` | 4.2 列出的 GET | 上次收到的 `ETag` 原值 |
| `If-Match` | `PATCH /api/v1/admin/accounts/:id` | 详情读到的账号 ETag（形如 `"cv-12"`），细节在账号章节 |

**需要读取的响应头**：`X-Request-ID`（错误详情里显示）、`Retry-After`、`X-Idempotency-Replayed`、`X-Idempotency-Recovered`（服务端接管了卡住的首次执行，并恢复出它的结果；按成功处理，2.5.3）、`X-Idempotency-Expires-At`、`X-Idempotency-Degraded`、`X-Admin-Adjustment-Action-ID`、`X-Redeem-Batch-ID`、`ETag`、`Date`（6.3 时钟偏差）。

### 2.3 超时

| 请求类别 | 客户端超时 | 说明 |
|---|---|---|
| 公开设置、`/admin/me`、合规、会话类 | 15 秒 | |
| 登录、2FA、刷新令牌 | 20 秒 | |
| 普通列表、详情、批量读取 POST | 20 秒 | |
| `dashboard/home` | 15 秒 | 服务端整体预算 8 秒 |
| 统计聚合（`dashboard/trend`、`snapshot-v2`、`ops/dashboard/*`、`usage/stats` 等） | 45 秒 | 沿用现状 |
| `dashboard/stats` | 90 秒 | 沿用现状（大站冷缓存慢） |
| 不带 key 的写 | 30 秒 | |
| 带 key 的写 | 服务端执行上限 + 5 秒：资金写与普通编辑 35 秒，`bulk-update` 与单账号刷新 65 秒，`batch-refresh` 125 秒 | 带 key 的写在服务端脱离连接执行，客户端超时后用同一 key 重试即可拿回结果 |
| SSE（账号测试） | 建连 30 秒；整体资源 180 秒 | 沿用 `timeoutIntervalForResource = 180` |

### 2.4 重试规则

| 请求类别 | 网络错误 / 超时 | 502 / 503 / 504 | 429 | 401 `TOKEN_EXPIRED` |
|---|---|---|---|---|
| **读**：GET，以及查询类批量 POST（`/api/v1/admin/accounts/runtime/batch`、`/api/v1/admin/accounts/today-stats/batch`、`/api/v1/admin/dashboard/users-usage`、`/api/v1/admin/dashboard/api-keys-usage`；其中后两个对只读 `sat_` 不可用，见 2.6.3） | 自动重试最多 2 次（间隔 1 秒、3 秒，加 0–500 ms 随机抖动） | 同左 | 按 `Retry-After` 推迟该数据块（2.7.2），不阻塞其他块 | 刷新后重发 1 次 |
| **带 key 的写**（2.5） | 进入 2.5.4 的“确认结果”流程：同一 key 自动重试最多 2 次 | 同左 | 同左，退避后用同一 key | 刷新后用同一 key、同一请求体重发 1 次 |
| **不带 key 的写**（含旧站点没有 `admin.idempotent_writes` 时） | **不自动重试**。读回服务器状态逐字段比对（页面章节定义读回接口）；比对不了就提示“结果未确认，请刷新核对后再操作” | 同左 | 提示“操作过于频繁，请 N 秒后再试”，不自动重发 | 刷新后重发 1 次（中间件在执行前拒绝，安全） |
| 登录、2FA | 不重试 | 不重试 | 倒计时 | — |
| 刷新令牌 | 见 1.7.2 | 见 1.7.2 | 见 1.7.2 | — |

- 所有自动重试都绑定在当前会话代号上，切站或退出即取消（沿用 `check(snapshot)`）。
- `STEP_UP_REQUIRED`、423 见 2.6、1.10。它们都在业务执行前返回，所以重发时沿用原来的 Idempotency-Key 和请求体。

### 2.5 Idempotency-Key

#### 2.5.1 接受 key 的接口

| 接口 | 需要的 capability | 带 key 时的执行上限 | 业务层去重 | App 规则 |
|---|---|---|---|---|
| `POST /api/v1/admin/users/:id/balance` | 无（一直支持；服务端关闭 `observe_only` 后强制带） | 30 秒，脱离连接执行 | 账本 `action_id` | 必带。响应头 `X-Admin-Adjustment-Action-ID` 存进待核对记录 |
| `POST /api/v1/admin/redeem-codes/create-and-redeem` | 无（强制） | 30 秒 | 兑换码 `code`（由 App 生成） | 必带 |
| `POST /api/v1/admin/redeem-codes/generate` | 无（可选） | 30 秒 | 请求体 `batch_id`（G03） | 必带，`batch_id` 等于 key；响应头 `X-Redeem-Batch-ID` |
| `POST /api/v1/admin/subscriptions/bulk-action` | 无（强制） | 2 分钟 | — | 必带 |
| `POST /api/v1/admin/users`、`PUT /api/v1/admin/users/:id` | `admin.idempotent_writes` | 30 秒 | 邮箱唯一 | 有 capability 就带。新建用户初始余额大于 0 时，响应头 `X-Admin-Adjustment-Action-ID`（`users.balance_ledger`）。指纹不含密码明文 |
| `POST /api/v1/admin/groups`、`PUT` / `DELETE /api/v1/admin/groups/:id` | `admin.idempotent_writes` | 30 秒 | 分组名唯一 | 同上 |
| `POST /api/v1/admin/groups/:id/duplicate` | 无（**强制**，`executeAdminIdempotent`） | **无**：跟随连接 | 服务端按“操作者 + key”记下副本；重试时如果首次执行仍记为处理中，服务端找到已建好的副本就直接返回，并带 `X-Idempotency-Recovered: true` | 必带；不带返回 400 `IDEMPOTENCY_KEY_REQUIRED`。超时后按 2.5.4 用同一 key 重试 |
| `PUT /api/v1/admin/accounts/:id`、`POST /api/v1/admin/accounts/:id/schedulable` | `admin.idempotent_writes` | 30 秒 | — | 同上 |
| `POST /api/v1/admin/accounts/bulk-update`、`POST /api/v1/admin/accounts/:id/refresh` | `admin.idempotent_writes` | 60 秒 | — | 同上 |
| `POST /api/v1/admin/accounts/batch-refresh` | `admin.idempotent_writes` | 120 秒（到时未完成的账号记为失败） | — | 同上 |
| `POST /api/v1/admin/announcements` | `announcements.idempotent_create` | 30 秒 | — | 同上 |
| `POST /api/v1/admin/accounts`、`POST /api/v1/admin/proxies`、`POST /api/v1/admin/users/:id/api-keys`、`POST /api/v1/admin/users/:id/replace-group` | 无（可选） | **无**：仍跟随连接，断开后记录可能停在“处理中” | 账号新建：混合渠道确认改了请求体，必须换新 key | 一律带；超时后按 2.5.4 处理，连续“处理中”超过 30 秒即转“待核对” |

- **不接受 key 的写**（如 `PATCH /api/v1/admin/accounts/:id`、`recover-state`、`clear-error`、上表以外的 `DELETE`；`DELETE /api/v1/admin/groups/:id` 接受 key，见上表）：按“不带 key 的写”处理。`PATCH` 用 `If-Match` 防覆盖：首次已成功时，重发会因为版本号已变而得到 412 `ACCOUNT_VERSION_CONFLICT`，此时读回比对，不要当失败。
- 旧服务端会忽略这个头。没有对应 capability 的“可选”接口照样可以带（无害），但结果不明时不能指望重放，要按“不带 key 的写”核对。

#### 2.5.2 生成与冻结

- **一个用户意图 = 一个 key**：用户在确认框里点下确认时生成 UUID v4（小写），同时作为 `X-Request-ID`。
- **冻结**：key 生成后，请求体就固定下来。请求体用 `JSONEncoder` + `.sortedKeys` 生成，金额字段的类型按 6.1（只有余额调整用字符串）。可以保存原始字节，也可以保存字段、每次确定性地重新编码；两种都必须保证重试时字节一致。
- **哪些要落盘**：只有**资金写**（余额调整、批量生成兑换码、发放补偿）要在发送前把记录写进本机文件（2.5.5）。**落盘失败就不发送**（沿用 `AppModel.remember`），提示“未决记录无法保存，已暂停此操作”。新建、编辑类写入（新建用户 / 账号 / 分组 / 代理 / 公告、复制分组等）只在内存里冻结：表单或 sheet 持有 key 和请求体，直到结果确定；App 被杀后 key 丢失，再次提交前按页面章节的读回方法核对。新建用户的初始余额虽然是金额，但邮箱唯一，重复提交只会得到 409 `EMAIL_EXISTS`，不会重复入账，所以不要求落盘。
- 重试必须字节一致，并且由同一个操作者发出：服务端指纹包含方法、路由、操作者和请求体；换了管理员账号再用同一个 key，是另一条记录。
- 用户改了任何内容（金额、备注、勾选“确认混合渠道风险”等），都要换新 key，并重新确认。

#### 2.5.3 响应处理

| 响应 | 含义 | App 动作 |
|---|---|---|
| 2xx，无 `X-Idempotency-Replayed` | 首次执行成功 | 当成功处理；资金写删除本机记录（`resolve`）。需要时保存 `X-Idempotency-Expires-At` |
| 2xx + `X-Idempotency-Replayed: true` | 这次是重放，服务端没有再执行 | 当成功处理。快照里的运行时字段可能过时，敏感键会被替换成 `***`，需要最新状态时再 GET 一次（兑换码真码按 `batch_id` 或 id 重新取） |
| 2xx + `X-Idempotency-Recovered: true` | 首次执行卡住（服务端本来要返回 `IDEMPOTENCY_IN_PROGRESS` 或 `IDEMPOTENCY_STORE_UNAVAILABLE`），服务端按“操作者 + key”找到了已经完成的业务结果并返回。目前只有复制分组（以及 App 不用的复制账号、复制渠道监控）会这样 | 当成功处理，响应体就是结果 |
| 2xx + `X-Idempotency-Degraded: result-committed` | 已执行成功，但结果没能记进幂等存储 | 当成功处理，并标记“该 key 之后不要再用”；以后同 key 可能返回 `IDEMPOTENCY_IN_PROGRESS`，那时按读回核对 |
| 409 `IDEMPOTENCY_IN_PROGRESS` | 首次请求还在执行 | 等 `Retry-After` 秒（取不到时读 `metadata.retry_after`，再取不到用 2 秒）后，同一 key 原样重试。从第一次收到起累计超过 30 秒，就停止自动重试，转“待核对”。**不要换 key** |
| 409 `IDEMPOTENCY_RETRY_BACKOFF` | 上次执行失败，仍在 5 秒退避期内 | 原请求不变时，等 `Retry-After` 后同 key 重试；要改请求体就换新 key |
| 409 `IDEMPOTENCY_KEY_CONFLICT` | 同一 key 已用于不同的请求体 | 程序缺陷或用户改过内容。不重试；回到确认框，用新 key 重新确认 |
| 400 `IDEMPOTENCY_KEY_INVALID` / `IDEMPOTENCY_PAYLOAD_INVALID` | key 或请求体不合法 | 程序缺陷：上报，并提示“请求无效，请重试”（生成新 key） |
| 400 `IDEMPOTENCY_KEY_REQUIRED` | 强制接口缺 key | 程序缺陷：补上 key 重新确认 |
| 503 `IDEMPOTENCY_STORE_UNAVAILABLE` | 幂等存储不可用，写入**没有执行**（fail-close）；或重放快照超过 64KB 被截断 | 不换 key、不立即重试。先读回核对；10 秒后才允许“用同一编号重试” |
| 业务错误（例如 409 `MIXED_CHANNEL_WARNING`、`GROUP_EXISTS`、`EMAIL_EXISTS`） | 不会被重放，原样返回；同 key 在 5 秒退避后可以重试 | 按该 reason 处理；改了请求体就换 key |

#### 2.5.4 网络中断后的流程

1. 带 key 的写遇到超时、断网、502/504：确认框或 sheet 进入“正在确认结果…”状态（不能关闭，可以“稍后核对”）。
2. 同一 key、同一字节自动重试 2 次（间隔 2 秒、5 秒，仅在前台进行）。得到 2xx 或明确的业务错误就结束。
3. 仍未知：sheet 文案“结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行”。资金写的本机记录转为“待核对”，概览“待处理”和对象详情显示待核对横幅（DECISIONS 第 2 轮、设计稿 `00-core.jsx` 待核对行）；新建、编辑类写入没有本机记录，sheet 停在这个状态，按页面章节的读回方法核对。
4. 待核对的对象（同一用户、同一批次）在核对完成前**禁止发起新的同类写入**（设计稿规则：“答复没回来的生成必须先核对”）。

#### 2.5.5 资金写的本机记录与核对方法

资金写分三类，各用一种记录类型、各存一个文件。文件都放在 `Application Support/Sub2Mobile/`，原子写入，使用 `.completeFileProtection`（沿用 `AppModel.persistPending`）。文件读不出来时，只暂停这一类新的资金写，并提示“未决<余额 / 兑换码 / 补偿>记录无法读取，已暂停新的<余额操作 / 兑换码生成 / 补偿发放>。请保留应用数据并检查设备存储。”（沿用 `AppModel` 里 `pendingPersistenceAvailable` 的现有做法，按文件分开记）。

| 资金写 | 记录类型 | 文件 | 字段细节 | 显示位置 |
|---|---|---|---|---|
| 余额调整 `POST /api/v1/admin/users/:id/balance` | `PendingBalanceOperation`（现有，扩字段） | `pending-balances.json`（现有，不迁移） | 用户章节 §3.7 | 用户详情横幅、用户列表、头像条、概览“待处理”、设置 → 待核对 |
| 批量生成兑换码 `POST /api/v1/admin/redeem-codes/generate` | `PendingRedeemBatch`（新增） | `pending-redeem-batches.json` | 兑换码章节第 11 节 | 兑换码列表横幅、概览“待处理”、设置 → 待核对 |
| 发放补偿 `POST /api/v1/admin/redeem-codes/create-and-redeem` | `PendingCompensation`（新增，本节定义） | `pending-compensations.json` | 下文 | 用户详情横幅（与余额待核对同一位置）、概览“待处理”、设置 → 待核对 |

**三种记录共有的字段**（名字统一，各章都用这一套）：

| 字段 | 含义 |
|---|---|
| `id: UUID` | 操作编号 = `Idempotency-Key` = `X-Request-ID`（发送时用小写字符串）；兑换码批次同时作 `batch_id` |
| `serverID: UUID` | 站点 |
| `actorUserID: Int?` | 发起人 `user.id`；旧记录没有时为 nil，核对框写明“无法确认发起人” |
| `createdAt: Date` | 发起时间（概览、横幅的“N 分钟前发起”） |
| `idempotencyExpiresAt: Date?` | 响应头 `X-Idempotency-Expires-At`；没收到时按 `createdAt + 24 小时` |
| `userID`、`userDisplayName`、`userEmail` | 只有作用于某个用户的两类（余额、补偿）有；显示名统一叫 `userDisplayName`（不用 `userLabel`） |

`PendingCompensation` 另有：`code`（App 生成）、`type`、`value: Decimal`、`groupID?`、`validityDays?`、`notes`。请求体由这些字段确定性编码。

- 三种类型都实现同一个协议 `PendingMoneyWrite`（上面的共有字段 + `requestBody() throws -> Data`），首页“待处理”、设置里的待核对列表、平静布局判断都按协议遍历。
- 记录只在结果未确认期间存在：发送前写入，确定成功或确定未执行后删除（`resolve`）。App 重启后，文件里的记录一律视为“待核对”。
- **概览“待处理”行的标题**：余额按 `operation`：`add` 写“充值结果待核对”；`subtract` 写“退款结果待核对”；`set` 且金额为 0 写“退款结果待核对”，金额位置写“全部余额”（用户章节用 `set 0` 实现“退款全部余额”）；`set` 且金额大于 0 只可能是旧版本留下的记录，写“余额设置结果待核对”。兑换码批次写“兑换码生成结果待核对”；补偿写“补偿结果待核对”。说明行一律是“<对象> · <createdAt 相对时间> · 未确认是否<入账 / 生成 / 发放>”。
- **超过 `idempotencyExpiresAt` 之后**：三类资金写都有业务层去重（余额账本的 `action_id` 由 key、操作者和请求体派生；兑换码按 `batch_id`；补偿按 `code`），所以同一发起人仍可以“用同一编号重试”。没有业务层去重的写入，过期后只剩“核对”。

| 写入类型 | 核对（只查不执行） | 判定 |
|---|---|---|
| 余额调整 | `GET /api/v1/admin/user-adjustments?request_id=<X-Request-ID>&user_id=<id>&kind=balance`（收到过 `X-Admin-Adjustment-Action-ID` 时改用 `action_id=<uuid>`，细节见用户章节 §3.4）；旧服务端忽略这些参数，所以**一律在本地按 `items[].request_id` / `items[].action_id` 复核**（旧服务端退路：`keyword=<完整邮箱>&kind=balance&start_time=<发起前 2 分钟>&end_time=<现在>&page_size=200`） | 找到 → 已入账（显示 `before_value` → `after_value`）；找不到且已超过执行上限 → 未执行，可以用同一编号重试 |
| 批量生成兑换码 | `GET /api/v1/admin/redeem-codes?batch_id=<key>&page_size=100`；本地复核 `items[].batch_id`（旧服务端会忽略这个参数） | 条数等于请求数量 → 已生成；为 0 → 未生成 |
| 发放补偿（create-and-redeem） | `GET /api/v1/admin/redeem-codes?search=<App 生成的 code>` | `status=used` 且 `used_by` 等于该用户 → 已发放 |
| 新建用户 | `GET /api/v1/admin/users?search=<邮箱>` | 有该邮箱 → 已创建；初始余额 > 0 时，再用 action_id 查 `user-adjustments` |
| 其余 | 页面章节定义读回接口与比对字段 | — |

### 2.6 二次验证（step-up）

#### 2.6.1 触发

- **被动**：收到 403 `STEP_UP_REQUIRED`。
- **主动**：对页面章节标注“需要 step-up”的操作，在发送前看 `/admin/me`：`step_up_enabled=true` 且（`step_up_granted=false`，或本地记录的到期时间已过）时，先弹验证，再发请求。当前后端需要 step-up 的、App 会用到的接口：揭示完整 Key（`POST /api/v1/admin/api-keys/:id/reveal`）、签发管理访问令牌（`POST /api/v1/admin/access-tokens`）、修改推送配置（`PUT /api/v1/admin/push/config`）、新建管理员或把用户提升为管理员（`POST /api/v1/admin/users`、`PUT /api/v1/admin/users/:id`，`role=admin` 时）。

#### 2.6.2 流程

1. 先看 `auth_method`。`admin_api_key` / `admin_access_token` 不弹验证，直接提示“Admin Key 与管理访问令牌不能做二次验证，请改用账号登录”（服务端会返回 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`）。
2. 收到 `STEP_UP_TOTP_NOT_ENABLED`，或 `/admin/me` 显示 `totp_enabled=false`：弹“需要先在 Web 端开启二次验证”说明（设计稿 `UeStepUpSheet` 的 ueNoTotp 状态），只有“知道了”。
3. 6 位验证码 sheet（`.oneTimeCode`，输满自动提交）→ `POST /api/v1/user/totp/step-up {"code":"123456"}`（JWT）→ `{verified:true, expires_in:900}`。本地记下到期时间 = now + `expires_in`。
4. 通过后：**读类**（reveal 等）自动重发；**写类**回到最终确认框（“二次验证已通过。…确认后保存”），用户再点一次才发送，沿用原来的 Idempotency-Key 和请求体。

| 验证错误 | 文案 | 动作 |
|---|---|---|
| `TOTP_INVALID_CODE` | 验证码不对，请重新输入 | 清空输入框 |
| `TOTP_TOO_MANY_ATTEMPTS`（429） | 尝试次数过多，请稍后再试 | 关闭 sheet |
| `STEP_UP_UNAVAILABLE`（503） | 二次验证服务暂时不可用，请稍后重试 | 保留会话 |

授权绑定在当前会话（JWT 的 sid）上，15 分钟有效；换设备或重新登录后要重新验证。

#### 2.6.3 只读管理访问令牌

只读令牌（`scope=read`）的写方法返回 403 `ACCESS_TOKEN_READ_ONLY`。服务端放行的例外只有这些（方法 + 路由精确匹配）：

- `POST /api/v1/admin/accounts/runtime/batch`、`POST /api/v1/admin/accounts/today-stats/batch`（查询类批量；只有这两个）。
- `DELETE /api/v1/admin/access-tokens/:id`（只能撤销自己）。
- `POST /api/v1/admin/push/devices`（只能 `platform=ios`）、`DELETE /api/v1/admin/push/devices/:id`、`PUT /api/v1/admin/push/devices/:id/subscription`、`POST /api/v1/admin/push/devices/:id/test`。

其他写按钮一律置灰，并标注“只读令牌”。万一收到 `ACCESS_TOKEN_READ_ONLY`，文案“当前管理访问令牌只读，不能执行此操作”，不重试。

**语义上是查询、但用 POST 的接口也会被拒**：`POST /api/v1/admin/dashboard/users-usage`、`POST /api/v1/admin/dashboard/api-keys-usage` 不在放行表里（`server/middleware/admin_access_token_auth.go` 的 `adminAccessTokenReadOnlyAllowedWrites`），只读令牌调用返回 403 `ACCESS_TOKEN_READ_ONLY`。用到它们的数据块（用户列表与详情的今日消费、Key 卡片今日消费、分组 API 密钥页的今日消费）一律这样处理：

- `isReadOnlyToken`（1.6）为真时**不发**这两个请求，对应数字直接显示 `—`，不加错误提示。
- 万一仍收到 403 `ACCESS_TOKEN_READ_ONLY`（例如令牌范围还没读到），只把这个数据块显示为 `—`，并把站点会话标成只读；**不弹**全局错误，也不走 3.2 的“只读”默认动作。

### 2.7 合规 423 与限流 429

#### 2.7.1 423

见 1.10。任何 admin 请求都可能返回 423，统一由 `APIClient` 抛出 `.compliance`，`AppModel` 弹出全局合规 sheet。同一时间只弹一个。

#### 2.7.2 429

- 秒数 N 的取值顺序：响应头 `Retry-After` → 响应体顶层 `retry_after`（登录 / 刷新限流才有）→ `metadata.retry_after` → 默认 30 秒。
- 数据块收到 429：显示“请求过于频繁，N 秒后自动重试”，这期间不再发这个块的请求。
- 写入收到 429：不自动重试，按钮倒计时。
- `ACCOUNT_TEST_BUSY`（429，实例上同时运行的测试达到 10 个）：提示“站点同时运行的测试已满，请稍后再试”。

### 2.8 查询参数与时间参数编码

- `start_time` / `end_time` 一律用 UTC 的 RFC3339（`2026-10-18T01:41:00Z`，用默认 GMT 时区的 `ISO8601DateFormatter`）。**不要发 `+08:00` 这种偏移**：`URLQueryItem` 不编码 `+`，Go 端会把它解析成空格，结果是 400。
- 按日期的参数用 `start_date` / `end_date`（`yyyy-MM-dd`，gregorian 历法，`en_US_POSIX`），并同时带 `timezone=<server_timezone>`（IANA 名）。现有 `APIClient.dates` 用的是 `TimeZone.current`，要改。
- 列表参数一律带 `page` 和 `page_size`（4.1）。

---

## 3. 错误处理

### 3.1 响应信封

| 来源 | 形状 | 例 |
|---|---|---|
| 成功 | `{"code":0,"message":"success","data":…}`（201、202 同形；202 的 message 为 `accepted`） | |
| handler 错误 | `{"code":<HTTP 整数>,"message":"…","reason":"…","metadata":{"k":"v"}}`。`metadata` 的值**全是字符串**；`reason` 可能为空（如 `Invalid request: …` 这类 400） | `{"code":409,"reason":"IDEMPOTENCY_IN_PROGRESS","metadata":{"retry_after":"12"}}` |
| 中间件错误 | `{"code":"<字符串>","message":"…","reason":"<同 code>"}` | `{"code":"TOKEN_EXPIRED","reason":"TOKEN_EXPIRED","message":"Token has expired"}` |
| 合规 423 | 字符串 `code` + `reason` + `metadata{version,document_url_zh,…}` | |
| 登录 / 刷新 429 | `{"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":12,"error":"rate limit exceeded","message":"…"}` + `Retry-After` 头 | |
| 面板 429 | 中间件格式 + `Retry-After` 头，没有 `retry_after` 字段 | |
| 混合渠道 409 | handler 格式，另有 `error` 和 `details`（`group_id` 为数字） | 账号章节 |
| 网关 404 | 纯文本 `404 page not found`（路由不存在，通常是站点版本较旧） | |
| 反向代理错误 | HTML 或空响应（502 / 504 等） | |

**解码规则**（`Sub2Core` 新增 `ErrorEnvelope`）：

```swift
struct ErrorEnvelope: Decodable {
    enum Code: Decodable { case int(Int), string(String) }   // 先尝试 Int，再尝试 String
    let code: Code?
    let reason: String?
    let metadata: [String: String]?
    let retryAfter: Int?          // "retry_after"
}
// marker = reason（非空时） ?? (code 为 .string 时的值) ?? nil
```

- 2xx 响应但 `code != 0`：按错误处理，HTTP 状态当作 500。
- 4xx / 5xx 响应体不是 JSON：marker 为空，按 3.3 的 HTTP 状态兜底；其中 404 视为“接口不存在”。
- 304：不解码响应体，取 ETag 缓存（4.2）。

### 3.2 reason 总表（App 动作）

稳定错误码清单见 sub2 `docs/API_ERROR_CODES.md`，这里只写 App 该做什么。页面专属的 reason（OAuth、兑换码、限额、推送配置等）在对应章节细化，这里给出默认动作。

**查表键是（HTTP 状态, reason）**，不是只看 reason。同一个 reason 会在不同状态码下表示不同的事：

- `USER_NOT_FOUND`：**401** 来自鉴权中间件（`server/middleware/admin_auth.go`），表示当前会话的主人已被删除 → 清除会话；**404** 来自业务接口（`service/user_service.go` 的 `ErrUserNotFound`），表示被操作的用户不存在 → 按“对象不存在”处理，不能把管理员登出。
- `USER_NOT_ACTIVE`（都是 403）还要看请求类别：登录、2FA、刷新令牌时 → 清除会话；业务接口 → 权限不足。
- 表里没有的（状态, reason）组合，按 3.3 的 HTTP 状态兜底。

| 类别 | reason（HTTP） | App 动作 | 默认文案 |
|---|---|---|---|
| 续期 | `TOKEN_EXPIRED`（401） | 刷新令牌后把原请求重发 1 次（1.7.2） | 不显示 |
| 会话失效 | `INVALID_TOKEN`、`TOKEN_REVOKED`、`USER_NOT_FOUND`、`USER_INACTIVE`、`REFRESH_TOKEN_INVALID`、`REFRESH_TOKEN_EXPIRED`、`REFRESH_TOKEN_REUSED`、`UNAUTHORIZED`、`INVALID_AUTH_HEADER`、`EMPTY_TOKEN`（以上都只在 **401** 时）；`USER_NOT_ACTIVE`（403，只在登录、2FA、刷新时） | 清除该站点会话 → 登录页 | 登录已失效，请重新登录 |
| 会话绑定 | `SESSION_BINDING_MISMATCH`（401） | 同上 | 网络或设备信息变化导致会话失效，请重新登录 |
| 凭据无效 | `INVALID_ADMIN_KEY`（401） | 清除凭据 → 登录页，预选原登录方式 | 令牌或 Admin Key 无效，请重新输入 |
| | `ACCESS_TOKEN_EXPIRED`（401） | 同上 | 管理访问令牌已过期，请重新签发 |
| | `INVALID_CREDENTIALS`（401） | 只在登录时出现 | 邮箱或密码错误 |
| 二次验证 | `STEP_UP_REQUIRED`（403） | 2.6 流程 | — |
| | `STEP_UP_TOTP_NOT_ENABLED`（403） | 说明 sheet | 需要先在 Web 端开启二次验证 |
| | `STEP_UP_ADMIN_API_KEY_FORBIDDEN`（403） | 不重试 | 该操作需要账号登录（Admin Key 与管理访问令牌不能二次验证） |
| | `STEP_UP_UNAVAILABLE`（503） | 保留会话，稍后重试 | 二次验证服务暂时不可用 |
| | `TOTP_INVALID_CODE`（400）、`TOTP_TOO_MANY_ATTEMPTS`（429）、`TOTP_LOGIN_SESSION_EXPIRED`（400） | 见 1.4、2.6 | |
| 只读 | `ACCESS_TOKEN_READ_ONLY`（403） | 不重试，不弹验证；`dashboard/users-usage`、`dashboard/api-keys-usage` 例外：只把数据块显示为 `—`，不提示（2.6.3） | 当前管理访问令牌只读，不能执行此操作 |
| 权限 | `FORBIDDEN`、`WORKSPACE_PERMISSION_DENIED`、`USER_NOT_ACTIVE`（业务接口）（403） | 不重试 | 当前身份没有执行此操作的权限 |
| | `WORKSPACE_DISABLED`（403） | 清除会话 | 你的工作区已被停用 |
| | `BACKEND_MODE_ADMIN_ONLY`、`BACKEND_MODE_SELF_SERVICE_DISABLED`（403） | 不重试 | 站点处于后端模式，仅管理员可用 |
| 合规 | `ADMIN_COMPLIANCE_ACK_REQUIRED`（423） | 1.10 | — |
| 验证码 | `TURNSTILE_VERIFICATION_FAILED`、`TENCENT_CAPTCHA_VERIFICATION_FAILED`、`ALIYUN_CAPTCHA_VERIFICATION_FAILED`、`CAPTCHA_PROVIDER_MISMATCH`（400）；`CAPTCHA_PROVIDER_CONFLICT`（503） | 1.4、1.5 | |
| 限流 | `RATE_LIMITED`（429）、`ACCOUNT_TEST_BUSY`（429） | 2.7.2 | 请求过于频繁，请 N 秒后再试 |
| 暂时性 | `SERVICE_UNAVAILABLE`（503） | 读：自动重试；写：按 2.4 | 站点暂时不可用，请稍后重试 |
| 幂等 | `IDEMPOTENCY_*` | 2.5.3 | |
| 功能未开启 | `OPS_DISABLED`（404） | 不算错误：该区域显示“运维监控未开启”，结合 `ops_monitoring_disabled_reason` 决定是否给开启入口 | 运维监控未开启 |
| | `OPS_CONFIG_DISABLED`（409） | 不重试，不引导去设置页 | 需要在服务器配置中启用运维监控 |
| | 首页聚合段的 `CHANNEL_MONITOR_DISABLED` / `SECTION_TIMEOUT` / `INTERNAL_ERROR` | 只影响该段（概览章节） | |
| | `PUSH_NOT_CONFIGURED`（503） | 第 7 节 | 站点未配置 APNs |
| 参数类（程序缺陷或输入错误） | `INVALID_SORT_BY`、`OPS_TIME_RANGE_TOO_LARGE`、`INVALID_MAX_POINTS`、`INVALID_REQUEST_ID`、`INVALID_AROUND`、`INVALID_SINCE_ID`、`SINCE_ID_WITH_PAGE`、`INVALID_TIMEZONE`、`INVALID_INCLUDE`、`INVALID_GROUP_FILTER`、`INVALID_GROUP_ID`、`INVALID_ACCOUNT_STATUS_FILTER`、`INVALID_READ_STATUS_FILTER`、`INVALID_USER_ID`、`INVALID_PLATFORM`、`INVALID_QUOTA_LIMIT`、`VALIDATION_ERROR`、`INVALID_IF_MATCH`、`INVALID_PATCH`、`USER_BALANCE_NOT_EDITABLE`、`REDEEM_CODE_TYPE_INVALID`、`REDEEM_BATCH_ID_INVALID`（400） | **不原样重试**。用户输入导致的，标出对应字段；否则上报缺陷。`SINCE_ID_WITH_PAGE` / `INVALID_SINCE_ID` 自动退回 `page=1` 全量刷新 | 请求参数有误（错误码 XXX） |
| 批量上限 | `TOO_MANY_IDS`（400） | 按 `metadata.max` 拆成更小的批次自动重发（4.5） | 不显示 |
| 版本冲突 | `ACCOUNT_VERSION_CONFLICT`（412） | 重新 GET，提示“账号已被他人修改，已刷新，请重新编辑”；`metadata.current_etag` 可直接用作新的 If-Match | |
| 业务冲突 | `MIXED_CHANNEL_WARNING`、`ACCOUNT_TEST_RUNNING`、`REDEEM_CODE_USED`、`REDEEM_BATCH_CONFLICT`、`REDEEM_CODE_CONFLICT`、`USER_PLATFORM_QUOTA_ACTIVE_EXISTS`、`GROUP_EXISTS`、`EMAIL_EXISTS`、`PUSH_TARGET_IN_USE`、`PUSH_DEVICE_LIMIT_REACHED`、`OPS_REQUEST_AMBIGUOUS`（409） | 按页面章节处理；默认刷新对象并说明冲突，不原样重试 | 操作与当前状态冲突，已刷新，请确认后重试 |
| 对象不存在 | `USER_NOT_FOUND`（**404**；401 时是会话失效，见上）、`ACCOUNT_NOT_FOUND`、`GROUP_NOT_FOUND`、`RESOURCE_NOT_FOUND`、`PROXY_NOT_FOUND`、`ANNOUNCEMENT_NOT_FOUND`、`REDEEM_CODE_NOT_FOUND`、`USER_PLATFORM_QUOTA_NOT_FOUND`、`ACCOUNT_TEST_RUN_NOT_FOUND`、`PUSH_DEVICE_NOT_FOUND`、`SESSION_NOT_FOUND`、`ACCESS_TOKEN_NOT_FOUND`、`OPS_REQUEST_NOT_FOUND`（404） | 从列表移除该对象，返回上一页并 toast。`DELETE` 时收到“不存在”视为已删除 | 对象不存在或已删除 |
| 部分成功 | `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED`（500，`metadata.recovered="true"`）、`REAUTH_PERSIST_FAILED`（500） | 不整体重试，读回后按账号章节处理 | |
| 统计不可用 | `ACCOUNT_STATS_UNAVAILABLE`（503） | 该批数字显示 `—`，下个周期重试 | |
| OAuth | `*_OAUTH_SESSION_NOT_FOUND`、`*_OAUTH_INVALID_STATE`、`*_OAUTH_CODE_REJECTED`、`NOT_OAUTH`、`REAUTH_UNSUPPORTED`、`OAUTH_EXCHANGE_FAILED`、`GROK_OAUTH_ENTITLEMENT_DENIED` | 按后缀识别，账号章节 | |
| 推送 | `INVALID_PUSH_TOKEN`、`INVALID_PUSH_TARGET`、`INVALID_PUSH_SUBSCRIPTION`、`PUSH_DELIVERY_FAILED`、`INVALID_APNS_CONFIG`、`SECRET_ENCRYPTION_KEY_NOT_CONFIGURED` | 第 7 节 | |

### 3.3 未知 reason 的兜底（按 HTTP 状态）

| HTTP | 动作 | 文案 |
|---|---|---|
| 400 | 不重试 | 请求无效（错误码 <reason 或 HTTP 400>） |
| 401 | 当作会话失效：JWT 先尝试刷新 1 次，仍是 401 就清除会话 | 登录已失效，请重新登录 |
| 403 | 不重试 | 当前身份没有执行此操作的权限 |
| 404 + 非 JSON | 当作“站点不支持”：该功能整体隐藏或置灰，本次会话内不再请求 | 站点版本较旧，暂不支持此功能 |
| 404 + JSON | 当作对象不存在 | 对象不存在或已删除 |
| 409 | 刷新对象，不重试 | 操作冲突，请刷新后重试 |
| 412 | 重新 GET | 数据已被修改，已刷新 |
| 423 | 走合规流程 | — |
| 429 | 2.7.2 | — |
| 5xx / 网络 | 读：自动重试；写：按 2.4 | 站点暂时不可用 / 无法连接站点 |

### 3.4 错误展示

- 主文案只用上面的中文文案，**不回显服务端 message**：message 可能含上游 URL、凭据片段或 HTML（沿用 `APIError.server` 的现有原则）。
- 错误态提供“详情”（`DisclosureGroup`）：HTTP 状态、reason、响应头 `X-Request-ID`、时间。方便用户反馈给站长；不写 message。
- 日志（`os.Logger`）只记方法、路径模板、状态、reason、`X-Request-ID`。不记请求体、令牌、Key、验证码证明、`metadata` 的值。

---

## 4. 列表与增量

### 4.1 分页信封

| 信封 | 形状 | 用在 |
|---|---|---|
| 标准 | `{items, total, page, page_size, pages}` | 大多数 admin 列表 |
| 精确计数的使用记录 | `{items, total, page, page_size, pages, has_more, total_exact:true, query}` | `admin/usage` 默认；`ops/request-errors` |
| 延迟计数 | `{items, total:null, page, page_size, pages:null, has_more, total_exact:false, query}` | `admin/usage?count_mode=deferred` |
| 增量 | 延迟计数信封再加 `since_id`、`latest_id`，`page` 固定为 1 | 带 `since_id` 时 |

- `page` 从 1 开始。`page_size` 合法范围是 1–1000；**超出或不是纯数字时，服务端静默回落 20**（不是截断，`pkg/response/response.go` 的 `ParsePagination`）。所以：
  - 常规分页列表发 ≤ 200。
  - 需要一次拿全的列表可以用到 1000，只限下面这些（页面章节注明的场景）：账号列表 `page_size=500`（账号章节 §1.2，按平台 → 分组 → 紧急度排序需要全量）；分组列表 `page_size=1000`（分组章节 §1.2）；没有 `accounts.status_summary` 时 D02 退路的全量 lite 账号（概览章节 §1.2）、没有 `groups.account_buckets` 时 F04 退路的错误账号（`status=error&lite=1`，分组章节 §0.1），都用 `page_size=1000`。
  - 任何情况都不得超过 1000。`ops/request-errors` 另外限制在 500 以内。
- 现有 `Page<T>` 要求 `total` 非空，要扩展出 `total: Int?`、`pages: Int?`、`hasMore: Bool?`；`total` 为 null 时界面不显示总数，靠 `has_more` 决定是否加载下一页。
- `query`（`{start_time, end_time, timezone, generated_at}`）用于解释桶标签和时区（6.3）。

### 4.2 ETag / If-None-Match / 304

- **支持 ETag 的 GET**：`/api/v1/admin/accounts`（列表）、`/api/v1/admin/users`、`/api/v1/admin/groups`、`/api/v1/admin/dashboard/stats`、`/api/v1/admin/dashboard/home`、`/api/v1/admin/dashboard/snapshot-v2`、`/api/v1/admin/ops/dashboard/snapshot-v2`、`/api/v1/admin/meta/catalog`；另外 `POST /api/v1/admin/accounts/today-stats/batch` 也认 `If-None-Match`（有失败项时不发 ETag）。其中 `users`、`groups`、`dashboard/stats` 需要 `lists.etag`，但对旧站点发 `If-None-Match` 无害。
- **App 自管缓存**：键为 `站点 id + 身份（user.id + auth_method）+ 方法 + 完整 URL（含排序后的查询串）+ 请求体哈希（POST 时）`，值为 `(etag, 解码后的数据, 收到时间)`。请求时带 `If-None-Match: <etag>`；收到 304 就复用缓存数据，把“更新时间”刷新为现在。
- ETag 匹配时服务端照样执行完整查询，304 只省带宽和解码，所以**不能**因为有 ETag 就缩短轮询间隔。
- `dashboard/stats` 在有流量时 `rpm` 每次都变，ETag 很难命中，属正常。`meta/catalog` 的 ETag 按身份区分，切换账号或站点时要清掉。
- 缓存只在内存里，切站、退出、收到 401 时清空；单条缓存超过 10 分钟没用就丢弃。

### 4.3 since_id 增量拉取（`logs.since_id`）

- 适用：`GET /api/v1/admin/usage`、`GET /api/v1/admin/ops/request-errors`。服务端返回 `id > since_id` 的行，固定按 `id` 降序、第一页、不做 COUNT。`sort_by` / `sort_order` / `exact_total` / `count_mode` 会被忽略，其他筛选照常生效。`since_id=0` 合法。`ops/request-errors` 带 `since_id` 且没有显式时间参数时，不套默认的 1 小时窗口。
- **服务端不保证提交顺序**：小 id 的行可能比大 id 的行晚提交，`latest_id` 只是“本批可见的最大 id”，不是安全水位（B09 审查修正）。所以：

1. **首屏**：`page=1&page_size=100`（不带 `since_id`），得到列表 L。
2. **轮询游标**：取 L 中 `created_at ≤ (L 中最新一行的 created_at − 30 秒)` 的最大 id 作为下一次的 `since_id`；没有这样的行时沿用上一次的游标；`created_at` 解析失败时用 `max(0, latest_id − 200)`。**不能**直接用 `latest_id`。
3. **合并**：新批次与已有列表**按 id 去重**（新数据覆盖旧数据，例如“已处理”状态变了），再按 id 降序排列。只保留最新的 N 条（列表页章节规定 N），超出部分仍可通过“加载更多”按页取。
4. **`has_more=true`**：表示新行超过一页，中间有缺口。放弃增量，改为 `page=1` 全量刷新，并重算游标。
5. **下拉刷新**：一律 `page=1` 全量刷新，用来校准。
6. **400 `SINCE_ID_WITH_PAGE` / `INVALID_SINCE_ID`**：去掉 `since_id`，`page=1` 重来。
7. 没有 capability `logs.since_id` 时的退路：`page=1&count_mode=deferred&start_time=<上次最新 created_at − 120 秒，UTC>&end_time=<现在>`，同样按 id 去重合并。

### 4.4 include_counts 与派生计数

- `GET /api/v1/admin/accounts?include_counts=1`（需要 `accounts.list_query`）返回 `data.counts{all, needs_attention, error, overloaded, rate_limited, temp_unschedulable, unschedulable, inactive, schedulable_now}`。每一项等于“其他筛选不变、status=该值”时的 total，不受当前 `status` 影响。“受限”数 = `needs_attention − error`。
- 带 `include_counts` 时只要计数变化就不会命中 304。所以只在 `page=1` 的请求上带（首屏、下拉刷新、筛选或平台变化后的第一页）；`page ≥ 2` 的翻页请求**不带**，筛选胶囊上的数字沿用第一页的结果（计数与页码无关）。
- 没有 capability 时，计数由 App 根据全量 lite 列表在本地计算（账号章节）。

### 4.5 批量 ID 上限（`TOO_MANY_IDS`）

| 接口 | 上限（去重、去掉非正数之后） | App 每批 |
|---|---|---|
| `POST /api/v1/admin/accounts/runtime/batch`（`account_ids`） | 200 | ≤ 200 |
| `POST /api/v1/admin/dashboard/users-usage`、`POST /api/v1/admin/dashboard/api-keys-usage` | 1000 | ≤ 200 |
| `GET /api/v1/admin/groups/capacity-summary`（`group_id` + `group_ids` 合计） | 100 | ≤ 100 |
| `GET /api/v1/admin/accounts` 的 `status` 值个数 | 16（reason 为 `INVALID_ACCOUNT_STATUS_FILTER`） | ≤ 16 |

- 发请求前在本地去重、去掉非正数、排序。仍然收到 `TOO_MANY_IDS` 时，按 `metadata.max`（字符串）拆批重发，结果按 ID 合并。
- 批量结果一律**按 ID 匹配**，不按请求顺序（例如 `failed_account_ids` 是升序集合）。只接受本次请求里有的 ID（沿用 `accountTodayStats(ids:)`）。

### 4.6 刷新节奏（全局规则）

- **只在前台刷新**。`scenePhase` 变为 `.background` 时取消所有在途请求和定时器；回到 `.active` 时，可见区块立即刷新一次。
- **各区块独立定时**：间隔从“上一次请求结束”开始算，慢区块不阻塞其他区块（沿用现有概览的做法）。默认间隔 60 秒（DECISIONS：前台约 60 秒）；RPM / TPM 趋势和详情页 30 秒；具体数值由页面章节定。倒计时类（限流剩余时间等）每秒在本地递减，不触发请求。
- **下拉刷新**：并发刷新当前页面所有区块；增量列表回到 `page=1`；ETag 照常带。
- **失败**：保留旧数据，区块内显示“刷新失败 · 重试”和“更新于 hh:mm”；下个周期自动再试。连续失败时间隔加倍（60 → 120 → 300 秒封顶），成功后恢复。
- **离开页面、切站、退出**：取消该页面的定时器；迟到的响应不写入（会话代号守卫）。

---

## 5. capability 总表

来源：`backend/internal/handler/admin/me_handler.go` 的 `adminMeCapabilities`（57 项）和 `adminMeEmbeddedWebCapabilities`（1 项，只在二进制内嵌前端时下发）。App 用 `Set<String>` 判断，不认识的字符串忽略。

**通用规则**：

1. 没有 capability 时，**不发**对应的新参数。旧服务端会静默忽略它们，返回未经过滤的结果。确实需要发时（例如核对），必须在本地复核结果。
2. 新字段一律按“可能缺失”解码：缺失 = 未知（显示 `—`），不当成 0。
3. 新路由在旧服务端返回非 JSON 的 404。按 3.3 标记“站点不支持”，本次会话内不再请求。

| capability | 条目 | 用在 | 有它时 | 缺失时 |
|---|---|---|---|---|
| `accounts.apply_oauth_preserve_status` | C11 | 账号凭据区（两步授权） | `apply-oauth-credentials` 可带 `preserve_status:true`，停用账号授权后仍保持停用 | 不带该参数；停用账号的确认框写明“授权后账号会被重新启用” |
| `accounts.clear_error_preserve_inactive` | C18 | 账号批量 / 单个清除错误 | `clear-error` / `batch-clear-error` 可带 `preserve_inactive:true`，响应有 `skipped_inactive_ids` | 发请求前在本地剔除 `status=inactive` 的账号，回执写“已跳过 N 个停用账号” |
| `accounts.list_query` | C14 | 账号列表 | `status` 多值与派生值（overloaded / needs_attention / schedulable_now）、`sort_by=urgency`、`include_counts=1` | 拉全量 lite 列表，在本地分组、排序、计数 |
| `accounts.mixed_channel_details` | C06 | 新建 / 编辑账号 | 409 `MIXED_CHANNEL_WARNING` 直接用 `details` 弹确认 | 提交前 `POST /api/v1/admin/accounts/check-mixed-channel` 预检 |
| `accounts.oauth_error_reasons` | C12 | OAuth 第 3 步、重新授权 | 区分会话过期 / state 不符 / 授权码被拒 | 换码失败一律提示“授权失败，请重新生成授权链接” |
| `accounts.patch` | C03 | 账号详情内联编辑 | `PATCH /api/v1/admin/accounts/:id`，按键合并 + `If-Match` | 先 GET 详情，再整份 PUT（非敏感键要带全，附录 A S31），没有并发保护 |
| `accounts.reauthorize` | C11 | 凭据区“重新授权…” | `POST /api/v1/admin/accounts/:id/reauthorize` 一步完成 | `exchange-code` + `apply-oauth-credentials` 两步 |
| `accounts.recover_schedulable` | C05 | 账号详情“恢复并启用调度” | `recover-state` 带 `{"schedulable":true}` 一次完成 | `recover-state` 之后再调 `POST /api/v1/admin/accounts/:id/schedulable` |
| `accounts.runtime_batch` | C15 | 账号列表、详情容量、分组成员 | `POST /api/v1/admin/accounts/runtime/batch` 刷新实时字段；列表与详情带 `concurrency_available` | 重拉当前页；`current_concurrency` 无法区分 0 和读取失败，照常显示数值 |
| `accounts.status_summary` | D02 | 概览待处理、平静布局、账号组头、分组列表 | `GET /api/v1/admin/accounts/status-summary` | `groups/all` 计数 + 全量 lite 列表本地分档 |
| `accounts.structured_error` | C02 | 账号状态卡、账号行、待处理 | `error_at`、`error_status_code`、`error_kind`、`error_summary` | 显示 `error_message` 首行（截断到 80 字），错误时间显示 `—` |
| `accounts.test_result` | C07 | 测试结果 sheet | SSE 末尾的 `test_result` 事件 | 本机计时；流结束后 GET 账号比对状态 |
| `accounts.test_runs` | C08 | 手动测试、待处理“测试” | 异步测试：可离开页面、可推送 | 只用 SSE，关闭 sheet 即取消测试 |
| `accounts.today_stats_failures` | C16 | 账号今日统计 | `failed_account_ids`、`degraded`、503 `ACCOUNT_STATS_UNAVAILABLE` | 无法识别失败项，照常显示数值 |
| `accounts.today_stats_group` | C17 | 分组成员今日 | `today-stats/batch` 请求体带 `group_id` | 分组成员的今日数字标注“含其他分组用量” |
| `accounts.token_status` | C10 | 凭据区令牌剩余时间 | `token_status{expires_at, lifetime_seconds, refreshed_at, auto_refresh}` | 读 `credentials.expires_at`（兼容 Unix 秒与 RFC3339），只显示“到期 hh:mm”，不画剩余刻度 |
| `admin.access_tokens` | A08 | 登录方式、站点与凭据 | `sat_` 登录；列出 / 吊销令牌 | 登录前无法预知，登录页照常提供该方式：旧站点会把 `sat_` 当成 Admin Key，返回 401 `INVALID_ADMIN_KEY`（1.6 的文案已包含“站点不支持”）。登录后没有这项能力时，“站点与凭据”不显示令牌列表 |
| `admin.idempotent_writes` | G06 | 用户 / 分组 / 账号编辑与启停 | 这些写带 Idempotency-Key（2.5.1） | 不带 key；超时后不自动重发，读回逐字段比对 |
| `announcements.idempotent_create` | H07 | 公告新建 | 带 key | 不带 key；超时后按标题搜最近几条核对 |
| `announcements.read_stats` | H06 | 公告列表、详情、已读情况 | `read-summary`、`include_read_stats`、`read_state` / `eligible` 筛选 | 只提供“已读情况 ›”分页名单 |
| `api_keys.current_concurrency` | E11 | Key 卡片“当前并发” | `current_concurrency` 有真实值（Redis 读失败时仍为 0） | 显示 `—` |
| `api_keys.effective_status` | E06 | Key 摘要、卡片、分组密钥页 | 直接用 `effective_status` | App 自己映射：inactive / disabled → 已停用，已过期 → 已过期，额度用满 → 额度耗尽（附录 B L14） |
| `api_keys.masked_view` | E03 | Key 列表、使用记录、请求详情 | 请求带 `key_view=masked`；揭示用 `POST /api/v1/admin/api-keys/:id/reveal`（需要 step-up） | 只显示名称与后 4 位，不提供“显示完整 Key”；明文不落盘、不进日志 |
| `auth.captcha_provider` | A09 | 登录 | 登录前看公开设置有没有 `captcha_provider` 键（这时还拿不到 `/admin/me`） | 1.5“旧服务端”一列 |
| `dashboard.account_cost` | A01 | 概览利润、今日 | `dashboard/stats` 的 `today_account_cost` / `total_account_cost` | `GET /api/v1/admin/dashboard/snapshot-v2?include_stats=true&include_trend=false&include_model_stats=false&include_group_stats=false&include_users_trend=false` 取 `stats` |
| `dashboard.accounts_ranking` | C04 | 平静布局“按账号”、账号按金额排序 | `GET /api/v1/admin/dashboard/accounts-ranking` | 全量账号 + `today-stats/batch` 本地排序 |
| `dashboard.home` | B11 | 概览首页 | `GET /api/v1/admin/dashboard/home` 一次聚合，分段可部分成功 | 各区块独立请求 |
| `dashboard.rates` | B01 | 首页 6 格错误率、RPM、TPM；运行区 | `GET /api/v1/admin/dashboard/rates?window=5m`：TPM 含缓存、不受运维开关影响；关监控时 `error_rate` 为 null | 开监控：`ops/dashboard/overview?time_range=5m`，按 `end_time − start_time` 折算；关监控：RPM / TPM 退回 `dashboard/stats`（TPM 不含缓存，格子下标“不含缓存”），错误率 `—` |
| `dashboard.request_types` | B05 | 统计分析 · 请求类型 | `GET /api/v1/admin/dashboard/request-types` | `usage/stats?request_type=` 逐类型并发 |
| `dashboard.users_ranking_sort` | B04 | 统计分析 · 用户排行 | `users-ranking?sort_by=` 与成本合计 | 改用 `user-breakdown` |
| `dashboard.users_trend_filtered_metric` | B12 | 用户用量趋势（带筛选） | 带筛选时 `metric` 生效 | 带筛选时只提供 Tokens |
| `groups.account_buckets` | F04 | 分组列表色格条、分组详情 | `error_account_count`、`idle_account_count` | 拉该分组的错误账号，在本地分桶 |
| `groups.capacity_filter` | F05 | 分组详情容量 | `capacity-summary?group_id=` | 拉全部分组，在本地过滤（旧服务端会忽略参数返回全部，必须在本地过滤） |
| `groups.member_batch` | F01 | 分组成员增删 | `POST /api/v1/admin/groups/:id/accounts/batch` | 逐个账号 GET + PUT `group_ids`，提示“可能覆盖他人同时的修改” |
| `lists.etag` | B09 | 用户、分组列表，`dashboard/stats` | 这几处返回 ETag | 无影响（照常带 `If-None-Match`，服务端忽略） |
| `logs.since_id` | B09 | 使用记录、错误请求 | 4.3 | 4.3 第 7 步 |
| `meta.catalog` | C13 | 新建账号表单、筛选、角色 | `GET /api/v1/admin/meta/catalog` | App 内置目录；未知值显示原始 id |
| `ops.alert_event_counts` | D06 | 告警计数 | `GET /api/v1/admin/ops/alert-events/counts` | 数 `status=firing` 列表 |
| `ops.alert_event_details` | D06 | 告警行与详情 | 事件带规则快照、分组名、解决人 | 另拉规则与分组拼接 |
| `ops.alert_latency_metrics` | D07 | 告警规则 | P95 / P99 规则会被评估 | 这两类规则显示“不受支持（不会触发）” |
| `ops.dashboard_model_filter` | B06 | 统计分析按模型筛选 | ops 看板接口带 `model` | 运行类图表标注“仍显示全站” |
| `ops.ingress_reject_totals` | D08 | 服务器区入口拒绝 | `request_count_total`、`by_reason` | 翻页累加 |
| `ops.job_heartbeat_status` | D08 | 服务器区后台任务 | `job_heartbeats[].status / expected_interval_seconds / next_expected_at`（不认识的 status 按 unknown） | 按 App 内置周期判断是否过期 |
| `ops.monitoring_status` | D09 | “运维监控未开启”提示 | `GET` / `PUT /api/v1/admin/ops/monitoring-status` | 只用 `/admin/me` 的开关判断；开启引导去 Web |
| `ops.request_attempts` | D10 | 失败请求“上游尝试” | `GET /api/v1/admin/ops/requests/:request_id/attempts` | `request-errors/:id/upstream-errors` + `admin/usage?request_id=client:<client_request_id>` 自己拼 |
| `ops.system_metrics_history` | D08 | 服务器区 CPU / 内存曲线 | `GET /api/v1/admin/ops/system-metrics/history` | 前台运行期间自己攒点 |
| `ops.token_stats_custom_range` | B07 | Token 请求统计 | `openai-token-stats` 接受任意 `start_time` / `end_time` | 取能覆盖所选范围的最小 `time_range`，并写明实际范围 |
| `proxies.fallback_accounts` | H03 | 代理详情 · 有效期、到期横幅 | `GET /api/v1/admin/proxies/:id/fallback-accounts`、`POST …/fallback-accounts/revert` | 全量账号本地过滤，逐个 `POST /api/v1/admin/accounts/:id/revert-proxy-fallback` |
| `push.notifications` | A11 | 推送设置 | 第 7 节 | 不显示推送设置；只做前台轮询 |
| `redeem_codes.delete_guard` | G07 | 兑换码删除 | 已使用的码删除时返回 409 | 已使用的码不提供删除 |
| `redeem_codes.stats` | G08 | 兑换码状态胶囊计数 | `GET /api/v1/admin/redeem-codes/stats` 是真实值 | 每个状态请求一次 `page_size=1` 读 total |
| `scheduled_tests.upstream_status` | C09 | 定时测试结果 | `upstream_status_code`、`error_kind` | 用正则从 `error_message` 里解析状态码 |
| `usage.model_source` | B03 | 模型筛选口径 | `model_source=requested / upstream / mapping` | 只提供请求模型口径，其余选项标注口径不可选 |
| `users.balance_ledger` | E10 | 充值与调整记录、新建用户 | `balance-history` 有前后余额、`total_recharged_breakdown`；新建用户返回 action_id 头；`PUT users/:id` 带 `balance` 会返回 400 | 不显示前后余额；`PUT` 用户时一律不带 `balance` |
| `users.platform_quota_item` | E07 | 平台限额 | 单平台 `PUT` / `DELETE` / `restore` | GET 后整表 PUT |
| `users.quick_topup` | E05 | 用户列表头像条 | `GET /api/v1/admin/users/quick-topup` | `user-adjustments` 去重 + 逐个 GET 用户 |
| `users.rpm_tracked` | E08 | 权限与并发 · RPM 状态 | `user_rpm_tracked`、`per_group[].tracked` | `limit=0` 写“不限 · 不计数” |
| `web.accounts_edit_deep_link` | C19（只在内嵌前端时下发） | 账号详情“在 Web 中编辑” | 打开 `<站点>/admin/accounts?edit=<id>&search=<名称>` | 打开 `<站点>/admin/accounts`，并把账号名复制到剪贴板 |

**已经上线、但没有 capability 的能力**（按下面的方式检测）：

| 能力 | 检测方式 / 退路 |
|---|---|
| A03 刷新宽限、A05 即时吊销、A06 reason 齐全 | 只是行为变化，不需要检测 |
| A04 原生会话绑定、`X-Device-ID` | 一律发送；旧服务端忽略 |
| A07 会话列表 | `GET /api/v1/auth/sessions` 返回非 JSON 404 → 隐藏“登录设备” |
| A09 `mobile_verify_path` | 看公开设置（1.5） |
| C01 新建账号 `schedulable=false` | 看响应里的 `schedulable`：仍为 true 时立即调 `POST …/:id/schedulable {"schedulable":false}`，并提示“已在创建后立即停止调度” |
| D01 告警静默列表 / 修改 / 撤销（`/api/v1/admin/ops/alert-silences`） | 非 JSON 404 → 只保留“手动解决” |
| D03 上游错误筛选、G02 账本精确筛选、G03 `batch_id`、G04 `types` / `exclude_types` | 旧服务端忽略参数：结果**一律在本地复核**筛选条件 |
| D04 / D05 / H01 / B02 等新增字段 | 按字段是否存在判断 |
| E01 管理员替用户建、改、删 Key（`POST /api/v1/admin/users/:id/api-keys` 等） | 非 JSON 404 → 显示虚线占位“需后端新增”（DECISIONS 第 3 轮） |
| A01 账号 `current_rpm` / `scheduling_rpm`、`dashboard/stats` 的 `rpm_available` | 按字段是否存在判断（没有对应 capability） |

---

## 6. 数值与时间

### 6.1 金额（USD）

- **读**：服务端用 JSON 数字（float64）输出金额，账本类字段（`before_value`、`after_value`、`delta` 等）是 8 位小数字符串。一律解码成 `Decimal`，字符串和数字都接受（沿用 `KeyedDecodingContainer.decimal`）。15 位有效数字以内没有精度损失（附录 B L18）。
- **写**：金额字段的线上类型跟着后端请求结构走，不能统一成字符串（Go 端 `float64` 字段收到字符串会绑定失败，返回 400）。

| 接口 | 字段 | 后端类型 | App 发送 |
|---|---|---|---|
| `POST /api/v1/admin/users/:id/balance` | `balance` | `json.RawMessage`（字符串、数字都收，`handler/admin/user_handler.go` 的 `UpdateBalanceRequest`） | **字符串**，最多 8 位小数，用 `NSDecimalNumber(decimal:).stringValue` 生成，不允许科学计数法；校验 0 ≤ 金额 ≤ 999999999999.99999999（沿用 `PendingBalanceOperation.validate`） |
| `POST /api/v1/admin/users` | `balance`（初始余额，可省略） | `*float64`（`CreateUserRequest`） | JSON number |
| `POST /api/v1/admin/redeem-codes/generate` | `value` | `float64`（`handler/admin/redeem_handler.go`） | JSON number |
| `POST /api/v1/admin/redeem-codes/create-and-redeem` | `value` | `float64`（`CreateAndRedeemCodeRequest`） | JSON number |
| 其余带金额或倍率的写：分组 `rate_multiplier` 等倍率、`daily_limit_usd` / `weekly_limit_usd` / `monthly_limit_usd`；Key `quota`；用户平台限额 | 各字段 | 倍率、Key 额度、平台限额是 `float64` / `*float64`；分组三项限额是 `optionalLimitField`（数字、字符串、null 都收，`group_handler.go`） | JSON number；分组限额改为“不限”时发 `null`（分组章节） |

- **JSON number 的生成**：在 `Decimal` 里先按界面允许的位数校验（位数由页面章节定，金额输入一般最多 2 位小数；超过时拒绝提交，不悄悄舍入），再用 `JSONEncoder` 直接编码 `Decimal`（输出十进制数字、不带引号）。不要先转成 `Double`。`PUT /api/v1/admin/users/:id` 的 `balance` App 一律不发（`users.balance_ledger` 一行）。
- **显示**：`$` + 千分位 + 固定位数，在 `Decimal` 里用 `NSDecimalRound(.plain)` 舍入。函数 `DisplayFormat.money(_:digits:small:)`、`moneyCompact(_:)`（6.2 同一文件）。

| 场景 | 位数 | 例 |
|---|---|---|
| 合计、余额、今日、利润 | 2 | `$1,284.50` |
| 日志行的单条金额 | < $1 用 4 位，≥ $1 用 2 位 | `$0.0124`、`$1.30` |
| 请求详情的金额（实际、账号成本、标准三格） | 固定 4 位 | `$0.0123` |
| 平均每次 | 3 | `$0.012` |
| 空间不足的卡片（页面章节注明时） | `K` 缩写，2 位 | `$45.08K` |

- 负数用 U+2212 减号：`−$12.50`；利润亏损照常显示 `−`，正数前**不加** `+`；四舍五入后为 0 时显示 `$0.00`，不显示 `−$0.00`。金额不用红绿表示涨跌，计费数字不着色（BUILDER_GUIDE 文案规则）。
- 页面章节注明的地方，大于 0 且小于 0.01 的值显示 `< $0.01`。

### 6.2 计数、Token、比率、耗时、时间文字

这是全 App 唯一的一份格式表。实现集中在 `Sources/Sub2Core/DisplayFormat.swift`（9.7），概览、统计分析、日志、模块各章只引用这里的函数，不再各写一套，也不往 `DashboardPresentation` 里加新的格式函数。缺失值一律返回 `—`。

| 类型 | 规则 | 例 | 函数 |
|---|---|---|---|
| 请求数、个数 | 整数，千分位 | `1,284` | `DisplayFormat.grouped(_:)` |
| 紧凑数（Token、TPM，以及空间不足处的大计数） | ≥ 1e9 用 `B`、≥ 1e6 用 `M`、≥ 1e3 用 `K`，1 位小数并去掉末尾 `.0`；< 1000 原样整数 | `18.2K`、`240K`、`96.4M` | `compact(_:)` |
| RPM | ≥ 10 取整；0 < x < 10 保留 1 位小数；0 显示 `0` | `46`、`0.4` | `rpm(_:)` |
| TPM | 按紧凑数 | `240K` | `compact(_:)` |
| 后端比例（`error_rate`、`sla`、`reliability_rate` 等 0–1 的值） | ×100，1 位小数 + `%`（BUILDER_GUIDE 的 `99.2%`、`0.8%`、`1.7%`） | `0.0086` → `0.9%` | `ratioPercent(_:)` |
| 已经是百分数的值（告警的 `metric_value`、`threshold` 等） | 不再 ×100，1 位小数 + `%`；单位按监控章节的告警单位表 | `5.2` → `5.2%` | `percent(_:)` |
| 占比条、增减 | 1 位小数；增减写方向箭头，不用红绿 | `38.5%`、`↑ 12.3%` | `percent(_:)`、`change(_:)` |
| 耗时 · 列表与详情（日志行、请求详情的整条请求耗时） | 秒，1 位小数；≥ 100 秒取整 | `0.6s`、`42.1s`、`182s` | `duration(_:style: .list)` |
| 耗时 · 分位数（P50 / P95 / P99 表与图） | < 1 秒用整数毫秒；1–10 秒用 1 位小数秒；≥ 10 秒取整秒 | `820ms`、`2.4s`、`42s` | `duration(_:style: .percentile)` |
| 耗时 · 毫秒读数（代理延迟、日志采集延迟、渠道监控等单次探测值） | < 1000 用整数毫秒；≥ 1000 按分位数一行的秒规则 | `182ms`、`850ms`、`2.0s` | `duration(_:style: .millis)` |
| 相对时间 | < 1 分钟“刚刚”；< 60 分钟“N 分钟前”；今天“今天 HH:MM”；昨天“昨天 HH:MM”；更早“M月d日 HH:MM”（日界与时刻按 6.3 的时区） | `12 分钟前` | `relativeTime(_:now:timeZone:)` |
| 倒计时 | `m:ss`，≥ 1 小时 `h:mm:ss`；每秒用“绝对时间戳 − 当前时间（含 6.3 的偏差）”重算，不累减 | `4:37` | `countdown(_:)` |
| 剩余时长（限流恢复等） | 向上取整到分钟，至少 1 分钟；≥ 60 分钟写“X 小时 Y 分钟” | `12 分钟`、`1 小时 5 分钟` | `minutesLeft(_:)` |
| 时刻 | `HH:MM`，时区按 6.3 | `10:04` | `clock(_:timeZone:)` |

- **数字与单位之间不加空格**：`820ms`、`0.6s`、`182ms`、`240K`。大字读数（如代理详情的延迟大字）把单位用小一号的字排在数字后面，同样不插空格字符。中文量词照常加空格：`12 分钟`、`3 次`。
- 现有 `DashboardPresentation.compactNumber`（2 位小数）、`money`（没有千分位）、`cost` / `duration`（缺失写“不可用”、耗时 2 位小数）都不符合本节，迁到 `DisplayFormat` 后删除；`DashboardPresentation` 只保留趋势日期解析等与格式无关的部分。

### 6.3 时区与时钟

- **服务器时区**：取 `/admin/me` 的 `server.server_timezone`（IANA 名）和 `server_utc_offset`；拿不到时取公开设置的同名字段。
- **“今日”**：`dashboard/stats`、账号今日统计、`today-stats/batch` 的“今日”固定按服务器时区，App 改不了。凡是请求“今日 / 昨日 / 小时桶”的接口，都带 `timezone=<server_timezone>`，让口径一致（附录 A S12）。
- **显示规则**（各章引用这一条，不再各写一套）：
  - **默认按服务器时区**：统计与趋势的日界和桶标签、日志与请求详情的时刻、告警触发 / 解决时间、“今天 / 昨天”分组、“剩余 N 天 / 今天到期”这类按自然日的计算（如代理到期、订阅到期）、会话与令牌的时间等，凡是服务端产生或按服务端日界统计的时间，都按服务器时区。统计分析自定义范围也按服务器时区计算（设计稿写的“按本机时区计算”改为“按站点时区计算”）。
  - **例外：管理员在 App 里输入的时间点按本机时区**，编辑控件和这个字段在列表、详情里的回显都用本机时区，并在控件旁或脚注写明“按本机时区 <TZ 名>”。例外只有这些：账号过期时间 `expires_at`（账号章节）；公告有效期 `starts_at` / `ends_at`（模块章节，公告列表与详情同样按本机时区）；兑换码编辑里自定义的过期时间（模块章节，`DatePicker`）；推送免打扰 `quiet_hours`（服务端按设备注册时传的 `timezone` 计算，7.3）。只用“天数”输入的有效期（代理到期、兑换码 N 天）不是时间点，换算后按默认规则显示。
  - 手机时区与服务器偏移不同时，概览副标题末尾加“· 按 UTC+8”（取 `server_utc_offset`），统计分析范围说明行与日志副标题末尾加“（站点时间 UTC+8）”，“设置 → 站点与凭据”写“时间按服务器时区（UTC+8）显示”。时区相同时都不写。
  - “刚刚”“N 分钟前”与倒计时没有时区问题，只用下面的时钟偏差校正；相对时间里的“今天 HH:MM”“昨天 HH:MM”按默认规则。
- **时钟偏差**：每次响应用 `Date` 头计算 `offset = 服务器时间 − 本机时间`（秒级精度，按站点保存）。倒计时和“N 分钟前”都用“本机时间 + offset”计算；`runtime/batch` 返回 `sampled_at` 时，用它作为基准。
- **发出的时间**：见 2.8。

### 6.4 时间字段格式

| 字段 | 线上格式 | 解析 |
|---|---|---|
| 大多数 `*_at`（`created_at`、`error_at`、`rate_limit_reset_at`、`overload_until`、`last_seen_at` 等）、API Key 的 `expires_at`、代理的 `expires_at` | RFC3339，可能带小数秒，偏移**不一定**是 `Z` | `ISO8601DateFormatter` 依次尝试“带小数秒”和“不带小数秒”；可能为 null |
| 账号的 `expires_at`；代理的 `quality_checked`、`latency_checked_at` | Unix 秒（整数） | `Date(timeIntervalSince1970:)` |
| `token_status.expires_at / refreshed_at`、`sampled_at`、`X-Idempotency-Expires-At`、`computed_at` | RFC3339 UTC | 同第一行 |
| 趋势桶 `date` | `yyyy-MM-dd HH:00` 或 `yyyy-MM-dd`，**不带偏移** | 按响应 `query.timezone` 解析（没有时按请求时带的 timezone）；沿用 `DashboardPresentation.trendDate`，把 timeZone 参数改成服务器时区 |
| 推送免打扰 `quiet_hours.start / end` | `HH:MM` | 按设备注册时传的 `timezone` 计算 |

### 6.5 “—” 与 0

| 情况 | 显示 |
|---|---|
| 字段缺失或为 null | `—` |
| 字段值为 0 | `0`（金额 `$0.00`） |
| 列表或详情 `concurrency_available=false` | 当前并发 `—`（这时的 `current_concurrency` 是 0 占位） |
| `runtime/batch` 的 `current_concurrency` / `probe_concurrency` 为 null | `—` |
| `runtime/batch` 里省略的 `current_rpm` / `scheduling_rpm` / `active_sessions` / `current_window_cost` | 账号配置了对应上限（`base_rpm` / `max_sessions` / `window_cost_limit` > 0）时显示 `—`；没配置时这一行不显示 |
| `today-stats/batch` 的 `failed_account_ids` 里的账号 | 今日各项 `—`（`stats` 里给它们补的 0 是占位，不是“今天没有请求”） |
| `today-stats/batch` 返回 503 `ACCOUNT_STATS_UNAVAILABLE`，或结果里缺某个账号 | 该账号今日各项 `—` |
| `dashboard/stats` 的 `rpm_available=false` | RPM `—`；字段缺失（旧站点）时显示数值，但不标“近 60 秒” |
| `dashboard/rates` 的 `errors_available=false` 或 `error_rate=null` | 错误率 `—` |
| ops 接口返回 `OPS_DISABLED` | 依赖运维的数值 `—`，区块注明“运维监控未开启” |
| `dashboard/home` 某段 `status` 不是 ok | 该段的数值 `—`，并显示该段的状态 |
| `AdminGroup` 的 `account_count`、`active_account_count`、`rate_limited_account_count` 缺失 | **0**（omitempty，缺失就是 0；附录 B L16） |
| API Key `current_concurrency`（有 `api_keys.current_concurrency`） | 照常显示数值（Redis 读失败也是 0，无法区分） |
| 延迟计数的 `total: null` | 不显示总数 |
| 只读 `sat_` 登录时依赖 `dashboard/users-usage`、`dashboard/api-keys-usage` 的数字（用户、Key、分组密钥页的今日消费） | `—`，不加错误提示（2.6.3） |

---

## 7. 推送（A11）

### 7.1 前提

- capability `push.notifications`，且 `user.role=admin`（vendor 不可用，推送也只发给 active 的 admin）。
- 凭据：JWT、Admin Key（设备记在第一个管理员名下）、`sat_` 都可以；只读 `sat_` 只能注册 iOS 设备（App 本来只注册 iOS）。
- 站点要配置好 APNs：`GET /api/v1/admin/push/config` 的 `ready=true`，而且 p8 私钥必须来自构建本 App 的同一个 Apple Team。`ready=false` 时，推送设置页显示“站点未配置 APNs 推送，请站长在 Web 设置”，不发起注册。
- **通知权限**：用户在“设置 → 推送”里打开开关时，才调用 `UNUserNotificationCenter.requestAuthorization([.alert, .sound, .badge])`，不在启动时请求。拿到授权后调 `registerForRemoteNotifications()`。

### 7.2 设备注册

`POST /api/v1/admin/push/devices`：

```json
{"platform":"ios","apns_token":"<设备令牌小写十六进制>","bundle_id":"<Bundle.main.bundleIdentifier>","device_name":"<UIDevice.current.name>","locale":"zh-Hans","timezone":"<TimeZone.current.identifier>","site_tag":"<ServerProfile.id.uuidString>"}
```

- `environment`：默认**省略**，跟随站点的 `apns_environment`。开发构建（entitlement `aps-environment=development`）显式传 `"sandbox"`，否则站点用 production 发送会得到 BadDeviceToken，设备随即被停用。
- `subscription`：首次注册时省略（默认 `ops_alert.fired` + `account.error`，`min_severity` 为 P1）；用户改过订阅后，再次注册时也省略（服务端保留原订阅）。
- `site_tag` 用站点 UUID，用于第 7.5 节深链时找到对应站点（最长 64 字）。
- 响应：新建 201，同一令牌再次注册 200（同一个 id，`created=false`，设备会被重新启用）。`data` 为 `{id, platform, token_hint, bundle_id, environment, device_name, locale, timezone, site_tag, enabled, disabled_reason, disabled_at, last_success_at, last_error, last_error_at, credentials_encrypted, subscription, created_at, updated_at, created}`。按站点保存 `id`。
- **何时注册**：每次连接站点成功（登录、启动恢复、切换站点），且推送开关已打开、拿到 APNs 令牌之后；`didRegisterForRemoteNotificationsWithDeviceToken` 返回的令牌变化时，对所有已开推送的站点重新注册。
- 错误：`INVALID_PUSH_TOKEN` / `INVALID_PUSH_TARGET` / `INVALID_PUSH_SUBSCRIPTION`（400，`metadata.field` 指出字段）→ 程序缺陷，上报；`PUSH_DEVICE_LIMIT_REACHED`（409，上限 `metadata.max`=20）→ 文案“推送设备已达上限，请在 Web 删除不用的设备”；`ACCESS_TOKEN_READ_ONLY` → 只会在注册非 iOS 平台时出现。

### 7.3 订阅

`PUT /api/v1/admin/push/devices/:id/subscription`，请求体：

```json
{"events":["ops_alert.fired","ops_alert.resolved","account.error","account.test_finished"],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":{"start":"23:00","end":"07:00"}}
```

- `events` 只能取这 4 个值，`[]` 表示暂停推送；`min_severity` 取 P0–P3，只作用于告警；`group_ids`（≤ 100 个）和 `platforms`（≤ 20 个）只过滤带分组或平台信息的事件，全站告警照常推送；`account.test_finished` 只推给发起异步测试的人，不受这两项过滤；免打扰按设备 `timezone` 计算，时段内的事件直接跳过、不会补推；`start` 等于 `end` 视为不设免打扰。
- 响应是设备对象。设置页的具体控件由设置章节定义。

### 7.4 测试与列表

- `POST /api/v1/admin/push/devices/:id/test` → `{delivered:true, provider_status:200}`；成功也会重新启用被停用的设备。错误：503 `PUSH_NOT_CONFIGURED`（站点 APNs 没配好）；502 `PUSH_DELIVERY_FAILED`（`metadata.provider_reason` 例如 `BadDeviceToken`、`Unregistered`，此时设备已被停用）→ 文案“推送服务拒绝了这台设备（<provider_reason>），请重新开启推送”。
- `GET /api/v1/admin/push/devices` → `{items:[…]}`：列出本人的全部推送目标（含 Bark / ntfy / Webhook，App 只读显示）。本机设备 `enabled=false` 时显示 `disabled_reason`，并提供“重新启用”（即重新注册）。

### 7.5 载荷与深链

APNs 载荷：

```json
{"aps":{"alert":{"title":"[P1] 错误率","body":"当前 12.3（阈值 > 5） · 近 5 分钟"},"thread-id":"ops-alert","interruption-level":"time-sensitive","sound":"default"},
 "type":"ops_alert.fired","site":"<site_tag>","severity":"P1","alert_event_id":881,"rule_id":3}
```

| `type` | 附带 id | `thread-id` | 点开后进入 |
|---|---|---|---|
| `ops_alert.fired` / `ops_alert.resolved` | `alert_event_id`、`rule_id`；有 `severity` | `ops-alert` | 告警详情 `{kind:'alert', id: alert_event_id}`（`GET /api/v1/admin/ops/alert-events/:id`） |
| `account.error` | `account_id`、`error_kind` | `account` | 账号详情 `{kind:'account', id: account_id}` |
| `account.test_finished` | `account_id`、`run_id`、`status` | `account-test` | 账号详情，并打开测试结果 sheet（`GET /api/v1/admin/account-test-runs/:run_id`） |
| `push.test` | — | `push-test` | 设置 → 推送 |

- **路由**：用 `site` 匹配 `ServerProfile.id.uuidString`。匹配的是当前站点：直接 push 路由。匹配的是其他站点：先切换站点（1.1），成功后再 push。站点凭据已清除：进入该站点的登录页，登录后再跳转。匹配不到：只打开 App，停在概览。
- 载荷里的数字 id 可能被解码成 `Int` 或 `NSNumber`，两种都要接受；未知的 `type` 只打开 App。
- 推送内容里只有 id 和简短文案，不含账号名、用户数据。App 不在通知内容里补拉数据（不做 Notification Service Extension）。
- 前台收到推送：`willPresent` 返回 `.banner, .sound`，同时触发对应区块立即刷新（告警列表、账号列表）。

### 7.6 退出、换号与多站点

- 退出登录先 `DELETE /api/v1/admin/push/devices/:id`（1.7.5）。会话被吊销**不会**自动删除设备。删除失败时记录“待删除”（按站点保存），下次登录该站点时，先删除再按开关状态重新注册；在“设置 → 推送”里提示“有设备未能从站点移除，可在 Web 删除”。
- 同一台手机在同一站点换了另一个管理员登录：重新注册同一个令牌，设备转给新管理员，订阅和历史重置。
- 多站点：每个站点独立注册、独立保存设备 id，`site_tag` 区分来源。

### 7.7 限制与退路

- 后台每 15 秒扫描一次，推送最多晚约 15 秒；所有实例停机超过 10 分钟期间的事件不会补推；`account.error` 每台设备、每个账号 30 分钟内最多一条；只有通过 `test-runs` 发起的异步测试才会推送 `account.test_finished`，SSE 测试不推。
- 没有 capability，或站点未就绪：不显示推送开关，只做前台轮询（4.6）。不做后台拉取（BGAppRefresh 不保证执行时间，而且 Keychain 凭据是“解锁时可用”）。

---

## 8. 全局口径、文案与视觉

### 8.1 口径与文案

各页面章节都遵守下面这些（来自 DECISIONS 与 BUILDER_GUIDE 文案硬规则）：

- **计费**：界面上不出现“营收”，一律叫“计费”（计费趋势、计费明细等）。**账号成本**：“成本”一律叫“账号成本”。**利润** = 实际扣费 − 账号成本，不叫“差额”“毛利”。“实际扣费”“账号成本”“标准”三个口径名保持不变。
- **首页 6 格**：今日实际扣费、请求、错误率、利润、RPM、TPM（3 × 2，按此顺序）。标签只写名字，不写“近 5 分钟”；口径不变：前三类按 00:00 起，错误率、RPM、TPM 是近 5 分钟。**TPM 含缓存 Tokens**，数据源优先 `dashboard/rates?window=5m`（第 5 节 `dashboard.rates` 一行给出退路）。统计分析的“今天”仍是今日 SLA 口径，两处都写明窗口。
- **状态词**：账号为 错误 / 过载中 / 限流中 / 临时不可调度 / 暂停 / 停用 / 正常；用户为 启用 / 禁用（不写“正常”）；“停用”也用于分组、代理、Key。不显示原始枚举。动作：启用调度 / 停止调度、恢复状态、测试连接、刷新令牌、更换 API Key…、重新授权…。告警只有“手动解决”和“静默…”，没有“确认”。
- **状态胶囊**：带状态色的条目，左侧一律用浮动胶囊：宽 4、离左 6、离上下各 10、两端全圆角、颜色取语义色的 `tone`，内容左内边距 ≥ 16。只有 caution、critical、model 三种色调画胶囊，ok、neutral 的条目不画（8.2）。同一列表里紧挨着的几条，不论同色异色，都连成一根连续的状态轨：交界处不缩进、不圆角，颜色直接切换，只有整段的最上端和最下端是圆头。SwiftUI：`.overlay(alignment: .leading) { Capsule().fill(tone).frame(width: 4).padding(.vertical, 10).padding(.leading, 6) }`，相邻粘连由列表容器根据前后条目决定上下内边距与圆角。
- **可逆操作**（调度开关等）直接执行，回执带“撤销”；**资金操作**必须二次确认，写明对象、站点、金额，不给默认金额；删除放在 ⋯ 菜单最后，需要输入对象名称或通过 Face ID。
- 颜色只表达状态；品牌青只表示“可操作 / 已选中”（8.2）。

### 8.2 视觉令牌（Vernier 石墨黑白）

来源：`html-preview/shared/vernier-palette.css`（`.pal-vernier.light` / `.dark`）、`shared/base.css`、BUILDER_GUIDE“样式”与“文案与语义硬规则”。DECISIONS：配色用游标 Vernier 石墨黑白，浅色、深色两套；第 2 轮 Q1 整体外观是仪器风（`vis-base`）。

**只用下面这些令牌，不自造颜色**（阴影透明度可以调）。浅色、深色两套都要做，默认跟随系统外观。

#### 8.2.1 基础色

| 令牌 | 浅色 | 深色 | 用在 |
|---|---|---|---|
| `canvas` | `#F1F3F4` | `#0B0E10` | 页面底色、导航栏底、列表组头底 |
| `surface` | `#FFFFFF` | `#15191C` | 列表行、卡片、状态卡 |
| `sheetBackground` | `#F1F3F4` | `#15191C` | sheet 底 |
| `sunken` | `#EBEEF0` | `#1E2327` | 未选中的胶囊与次要按钮底、进度轨道、卡片里的嵌套块（如“模型限流”块） |
| `segmentOn` | `#FFFFFF` | `#2B3237` | 分段控件选中项底 |
| `hairline` | `#D8DDE0` | `#2B3237` | 分隔线、描边 |
| `ruleStrong` | `#7F898F` | `#606A71` | 刻度、对比线 |
| `ink1` | `#14181B` | `#E7EBED` | 主文字、金额与计费数字 |
| `ink2` | `#4A545A` | `#A8B1B7` | 次要文字 |
| `ink3` | `#5E686F` | `#8B959C` | 第三级文字、占位、缺失值 `—` |
| `accent` | `#0B6E85` | `#52CBE6` | 品牌青：链接、可点的文字、选中胶囊的字与描边、Tab 选中 |
| `accentFill` / `onAccent` | `#0B6E85` / `#FFFFFF` | `#127A91` / `#FFFFFF` | 主按钮底 / 主按钮字 |
| `accentWash` | `#E2F1F4` | `#203940` | 选中的筛选胶囊底 |

#### 8.2.2 语义色调

每种色调三个值：`tone` 画圆点、图标、状态胶囊；`ink` 写字；`wash` 做徽章与横幅的底。

| 色调 | 浅色 tone / ink / wash | 深色 tone / ink / wash | 用在 |
|---|---|---|---|
| ok | `#288F48` / `#1B7339` / `#E5F2E9` | `#45BE68` / `#5BCF7E` / `#1E372A` | 账号“正常”、2xx 状态码、测试通过。不画状态胶囊 |
| caution | `#B87D00` / `#875200` / `#F6EFE0` | `#F0B93C` / `#F5C04F` / `#3C3622` | 账号“限流中”“临时不可调度”、429、待核对、≤ 7 天到期 |
| critical | `#B42318` / `#A61D15` / `#F6E5E3` | `#E5483D` / `#FF7468` / `#3A2122` | 账号“错误”“过载中”、其他失败状态码（4xx、5xx、504、529）、危险按钮、“超过当前余额”这类阻止提交的提示 |
| neutral | `#7D878D` / `#596369` / `#EFF1F1` | `#6E7980` / `#9CA6AC` / `#252A2E` | 账号“暂停”“停用”、缺失的状态码。不画状态胶囊 |
| model | `#8559E0` / `#6A3DC2` / `#F0EBFB` | `#9C7CF2` / `#BBA0FF` / `#2D2B43` | **只用于模型限流**：账号行第 3 行的尾段“模型限流 N”（`ink` 色文字）；账号状态卡的“模型限流 N”块（块底 `sunken`，标题和图标用 `ink`，模型名用 `ink1`，剩余时间用 `ink2`）；模型列表、模型映射里被限流模型的“限流 N 分钟”徽章（`wash` 底 + `ink` 字）。账号整体状态不会因为模型限流变成 model 色，行与状态卡的胶囊仍按账号状态取色 |

账号状态 → 色调与设计稿 `STATE_META` 一致：正常 ok；限流中、临时不可调度 caution；过载中、错误 critical；暂停、停用 neutral。状态码 → 色调与 `codeTone` 一致：2xx ok；429 caution；其余失败 critical；缺失 neutral。行和状态卡按客户端最终拿到的码着色，状态码徽章按它自己的码着色。

#### 8.2.3 口径色与图表

| 令牌 | 浅色 | 深色 | 用在 |
|---|---|---|---|
| `legendActual` | `#288F48` | `#45BE68` | “实际扣费”的图例与线 / 柱 |
| `legendCost` | `#CF5F17` | `#EB8840` | “账号成本”的图例与线 / 柱 |
| `legendStandard` | `#7D878D` | `#6E7980` | “标准”的图例与线 / 柱 |
| `chartMain` / `chartBarNow` | `#14181B` | `#E7EBED` | 主线、当前时段的柱 |
| `chartCompare` / `chartBar` | `#7F898F` | `#606A71` | 对比线（如昨日）、其余柱 |

口径色只用在图表上。金额数字一律 `ink1`，不按口径着色，也不用红绿表示涨跌（8.1）。面积图不填色。

#### 8.2.4 用法规则

- 文字要带色调时用该色调的 `ink`，不用 `tone` 本色；`tone` 只画圆点、图标和胶囊。
- 徽章：`wash` 底 + `ink` 字，高 22pt、圆角 6pt、12.5pt semibold。
- 状态横幅：`wash` 底；caution、critical、model 横幅另画状态胶囊（8.1），ok、neutral 横幅只有底色、不画胶囊。
- 玻璃只用于 Tab 栏、工具栏、浮层，用系统 Liquid Glass，不自绘；内容层不透明。列表必须能落到 `List`（滑动操作、多选）。
- Tab 徽标用系统 `.badge(_:)` 的默认样式。

#### 8.2.5 硬规则

- **字号**：正文中文 ≥ 14pt，标签 ≥ 12pt（Tab 栏标签用系统默认）。数字用 `.monospacedDigit()`；模型名、主机、Key 前缀、请求 ID、兑换码用等宽字体 `.monospaced()`。字体用系统字体（设计稿是 `-apple-system` / 苹方，DECISIONS 允许按布局定，主模式不另引字体）。
- **点按区 ≥ 44 × 44pt**：筛选胶囊、分段项、小按钮、回执里的“撤销”、键盘上方的胶囊等，画出来小于 44pt 的控件用 `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` 扩大点按区，画出来的尺寸不变。
- **对比度 ≥ 4.5:1**：文字只用 `ink1` / `ink2` / `ink3` 和各色调的 `ink`，不用 `tone` 写字。
- **危险按钮**（删除、替换令牌等自定义的破坏性按钮）：`criticalWash` 底 + `criticalInk` 字；不用系统红（`#FF3B30`）底白字。系统 `alert` / `confirmationDialog` 里的 `.destructive` 按钮由系统渲染，照常用。

#### 8.2.6 实现

- 新增 `NativeApp/Design/Palette.swift`：每个令牌一个 `Color`，用 `UIColor { $0.userInterfaceStyle == .dark ? dark : light }` 生成，数值逐个照抄 `vernier-palette.css`；文件头注明来源，改色只改这里。
- 同文件定义 `enum Tone { case ok, caution, critical, neutral, model }`，提供 `base` / `ink` / `wash` 和 `drawsRail`（caution、critical、model 为 true）。账号状态、状态码到 `Tone` 的映射放在 `Sub2Core`（不依赖 SwiftUI，便于单测）。
- 现有页面用的系统色（如 `Components.swift` 的 `secondarySystemGroupedBackground`）在改到对应页面时换成令牌。

---

## 9. 对现有代码的改动点

### 9.1 `Sources/Sub2Core/APIClient.swift`

| 符号 | 改动 |
|---|---|
| `makeRequest` | UA 改为 `Sub2Mobile-iOS`；新增 `X-Device-ID`（`APIClient` 初始化时传入 `deviceID`）；新增可选 `X-Request-ID`、`If-None-Match`；`Authorization` 与 `x-api-key` 互斥（现在已经互斥，保持）；`.accessToken` 凭据也走 `x-api-key` |
| `login` / `LoginBody` | 增加 `client{type,device_id,device_name}`、`captcha_provider`、`aliyun_captcha_param`；阿里云的映射按 1.5 |
| `acceptLogin` / `LoginReply` | 解析 `refresh_token_unavailable`；角色检查按 1.11；成功后由调用方调 `me()` |
| `verifyAdministrator` | 替换为 `me() -> AdminMe`（`GET admin/me`），带 1.9 的旧服务端退路；不再用 `dashboard/realtime` 当探针 |
| `request` | ① 401 `TOKEN_EXPIRED` 时，**所有方法**都刷新后重发 1 次（现在只对 GET）；② 返回值改成 `APIResponse<T>`（值 + 响应头 + 状态），新增 `requestWithHeaders`；③ 按 `RequestClass`（`.read` / `.readBatch` / `.keyedWrite(key)` / `.unkeyedWrite`）执行 2.4 的自动重试；④ 429 读 `Retry-After` |
| `decode` / `responseError` / `ErrorReply` | 换成 `ErrorEnvelope`（`code` 兼容 Int 与 String、`metadata`、`retry_after`），marker 规则见 3.1；304 不解码 |
| `validCredential` / 刷新 Task | 刷新请求带 `X-Device-ID`；按 1.7.2 区分“清会话”和“保留会话”：现在任何刷新错误都包成 `.transport` |
| `logout` | 先删除推送设备，再带 `Authorization` 调 `auth/logout`（1.7.5） |
| `stepUp` | 返回 `expires_in`，供本地记录到期时间 |
| `updateBalance` / `updateUser` / `createUser` | 资金写（`updateBalance`，以及新增的 `generateRedeemCodes`、`createAndRedeem`）接收已落盘的记录（`PendingMoneyWrite`），body 由记录确定性编码，key 与 `X-Request-ID` 取记录 `id`；新建 / 编辑类（`createUser`、`updateUser` 等）接收调用方冻结的 `key` 与 body。都返回 `WriteOutcome{value, replayed, recovered, degraded, expiresAt, actionID, batchID}`（2.5.3） |
| `dates` / `dateRange` / `monthRange` | `timezone` 改为服务器时区（`AdminMe.server.serverTimezone`），不再用 `TimeZone.current` |
| `pagination` | 默认 `page_size=20`；调用方可传 1–1000，常规列表 ≤ 200，4.1 名单里的全量场景才用到 500 / 1000。超过 1000 时 Debug 断言失败、Release 夹到 1000（避免服务端静默回落 20） |
| `dashboardMonitoring` / `dashboard` | 页面章节改用 `dashboard/home` / `dashboard/rates`；本章只要求它们走统一的错误与降级路径 |

新增方法：`me()`、`sessions()`、`revokeSession(id:)`、`revokeOtherSessions()`、`complianceStatus()`、`acceptCompliance(phrase:)`、`accessTokens()`、`revokeAccessToken(id:)`、`registerPushDevice(_:)`、`deletePushDevice(id:)`、`updatePushSubscription(id:_:)`、`testPushDevice(id:)`、`pushConfig()`。

### 9.2 `Sources/Sub2Core/HTTPTransport.swift`

- `URLSessionTransport`：保留 ephemeral、无缓存、拒绝重定向。`data(for:)` 要让 304 原样返回（现在已经原样返回 statusCode 和 headers，确认 `data` 为空时不报错）。
- 头部键已经转成小写（`headers(_:)`），统一用小写键读 `retry-after`、`x-idempotency-replayed`、`date` 等。
- `StreamingDelegate` 不变；SSE 请求也经过 `makeRequest`，自然带上 `X-Device-ID`。

### 9.3 `Sources/Sub2Core/APIError.swift`

- `Kind` 增加：`stepUp`、`readOnly`、`rateLimited`、`idempotency`、`conflict`、`notFound`、`unsupported`（非 JSON 404）、`featureDisabled`（`OPS_DISABLED` 等）、`temporary`。
- `server(status:reason:)` 改成**按（HTTP 状态, reason）精确查表**（第 3.2 节），查表键包含状态码：401 `USER_NOT_FOUND` 清除会话，404 `USER_NOT_FOUND` 是对象不存在；`USER_NOT_ACTIVE`（403）再按请求类别（登录 / 刷新 vs 业务接口）区分。不再用 `contains` 子串匹配：现在 `TOTP` / `STEP_UP` / 423 都归成 `.twoFactor`，423 被当成二次验证（附录 B L1），这是错的。
- 增加 `retryAfter: Int?`、`metadata: [String: String]`、`requestID: String?`，供 UI 显示详情、拆批、倒计时。
- 文案沿用“不回显服务端 message”的原则；缺失值文案“不可用”改为 `—`（6.5）。

### 9.4 `Sources/Sub2Core/Models.swift`

- `AuthenticationKind` 增加 `accessToken`；`Credential` 增加 `case accessToken(String)`。读出旧数据时，`.adminKey` 的值以 `sat_` 开头就迁移成 `.accessToken`。
- `CaptchaProof` 增加 `provider: String?`、`aliyunParam: String?`。
- `PublicSettings` 改为保留原始字段：`captchaProvider` 键是否存在（`hasCaptchaProviderKey`）、`mobileVerifyPath`、`serverTimezone`、`serverUTCOffset`、`version`、`siteName`、`backendModeEnabled`、`totpEnabled`、`loginAgreement*`。`conflict` 不在解码阶段抛错，而是由登录页显示。
- `Page<T>`：`total` / `pages` 允许为 null，新增 `hasMore`、`sinceID`、`latestID`（4.1）。
- `PendingBalanceOperation` 保留（不改名、不迁移文件），按 2.5.5 的共有字段与用户章节 §3.7 扩字段，新字段 `decodeIfPresent` 兼容旧记录；新增 `PendingMoneyWrite` 协议与 `PendingCompensation`。`PendingRedeemBatch` 在 `RedeemCodes.swift`（兑换码章节第 11 节）。

### 9.5 `NativeApp/Session/AppModel.swift`

- 连接流程：`connect` 里用 `me()` 替换 `verifyAdministrator()`，结果存进 `SiteSession{me, capabilities: Set<String>, serverTimeZone, clockOffset, isReadOnlyToken}`（`isReadOnlyToken` 按 1.6 第 3 步取得），通过 `sessionContext` 下发给页面。页面用 `session.has("dashboard.rates")` 判断能力。
- 全局拦截：`APIClient` 抛出 `.compliance` / `.stepUp` / 会话失效时，`AppModel` 统一弹合规 sheet、step-up sheet，或回到登录页（同一时间只弹一个）。
- 保留 `pendingBalances`，新增 `pendingRedeemBatches`、`pendingCompensations`，各自一个文件、各自的 `pendingPersistenceAvailable` 标记；`remember` / `resolve` 按类型提供（共用一个原子写入的 `persist(_:to:)`）。新增 `pendingMoneyWrites(serverID:) -> [any PendingMoneyWrite]` 供概览“待处理”、平静布局判断和设置页遍历；新增 `reconcile(_:)`，按 2.5.5 的核对方法分派。
- 场景生命周期：监听 `scenePhase`，进入后台时 `client.cancelAll()`、暂停定时器；回到前台时如果距上次 `me()` 超过 5 分钟就重新探测（4.6）。
- 推送：新增 `PushCoordinator`（见 9.7），在 `connect` 成功、`logout` 前后调用。
- `logout`：顺序按 1.7.5；清空 ETag 缓存和游标。
- `report(_:)`：错误 sheet 增加“详情”（3.4）。

### 9.6 `NativeApp/Session/CredentialVault.swift`

- `KeychainCredentialStore` 增加 `deviceID(serverID:) -> UUID`：读取，不存在时生成并保存（account = `<站点 UUID>.device`，同样是 `WhenUnlockedThisDeviceOnly`）；`remove(serverID:)` 同时删除它。
- `Credential` 的 Codable 增加了 `.accessToken` 分支，`load` 时做旧数据迁移。
- 待删除的推送设备 id 不是敏感数据，可以放在 `UserDefaults`（按站点）。

### 9.7 建议新增的文件

| 文件 | 内容 |
|---|---|
| `Sources/Sub2Core/AdminMe.swift` | `AdminMe` 模型（1.9 全部字段）、`Capability` 常量（第 5 节字符串） |
| `Sources/Sub2Core/ErrorEnvelope.swift` | 3.1 的解码 |
| `Sources/Sub2Core/ReasonCatalog.swift` | 3.2 的 reason → 动作 / 文案表（纯数据，便于单元测试） |
| `Sources/Sub2Core/IdempotentWrite.swift` | 2.5 的 `WriteOutcome`、按 2.5.3 判定结果（`IdempotencyOutcome`）、`PendingMoneyWrite` 协议、`PendingCompensation` |
| `Sources/Sub2Core/ConditionalCache.swift` | 4.2 的 ETag 缓存（actor） |
| `Sources/Sub2Core/IncrementalList.swift` | 4.3 的游标计算与按 id 合并 |
| `Sources/Sub2Core/ServerTime.swift` | 服务器时区、`Date` 头偏差、6.4 的时间解析 |
| `Sources/Sub2Core/DisplayFormat.swift` | 6.1、6.2、6.5 的全部格式函数（`money`、`moneyCompact`、`grouped`、`compact`、`rpm`、`ratioPercent`、`percent`、`change`、`duration(_:style:)`、`relativeTime`、`countdown`、`minutesLeft`、`clock`）；把 `DashboardPresentation` 里的金额、紧凑数与耗时函数迁过来，缺失返回 `—`。各页面章节只调这里 |
| `NativeApp/Design/Palette.swift` | 8.2 的颜色令牌与 `Tone` |
| `NativeApp/Session/PushCoordinator.swift` | 通知权限、APNs 令牌、按站点注册 / 删除、深链路由（`UNUserNotificationCenterDelegate`） |
| `NativeApp/Features/StepUpSheet.swift`、`ComplianceSheet.swift` | 2.6、1.10 的全局 sheet |

**可以直接复用的部分**：`APIClient` 的会话代号守卫与单飞刷新、`KeychainCredentialStore` 的租约机制、`CaptchaView` / `CaptchaBridgeValidator`、`PendingBalanceOperation` 的金额校验与字符串编码、`URLSessionTransport`、`DashboardPresentation.fixed`（Decimal 舍入）。

### 9.8 需要补的测试（`Tests/Sub2CoreTests`）

- `ErrorEnvelope`：整数 code、字符串 code、423、登录 429（含 `retry_after`）、非 JSON 404、HTML 502。
- `ReasonCatalog`：3.2 每一类至少一个 reason；401 与 404 的 `USER_NOT_FOUND` 走不同动作；未知（状态, reason）按状态兜底。
- 刷新：`TOKEN_EXPIRED` 后写请求用同一 key 重发；429 / 503 / 网络错误时保留会话；`REFRESH_TOKEN_REUSED` 时清除会话。
- 幂等写：字节一致、`IN_PROGRESS` 累计 30 秒后转“待核对”、`KEY_CONFLICT` 要求换 key、`X-Idempotency-Recovered` 按成功、资金写落盘失败不发送、旧版 `PendingBalanceOperation` 解码、`set 0` 的待处理标题是“退款结果待核对”。
- `DisplayFormat`：6.2 每一行的例子（含 RPM < 10、比例 1 位小数、三种耗时、缺失 `—`）。
- 金额编码：余额调整是字符串，`redeem-codes/generate`、`create-and-redeem`、`POST users` 是 JSON number。
- `IncrementalList`：乱序提交（小 id 晚到）不丢行、去重、`has_more` 触发全量刷新。
- 时间：`+08:00` 不出现在查询串里；趋势桶按服务器时区解析；Unix 秒字段。
- 能力：没有 capability 时不发新参数。

---

## 10. 本章未决问题

| # | 问题 | 为什么无法从材料推断 | 建议默认值 |
|---|---|---|---|
| 1 | ~~界面上的绝对时间按服务器时区还是手机时区显示~~ | 已定为 6.3 的规则（默认服务器时区，管理员输入的时间点按本机时区）；保留编号，免得其他章节的引用错位 | — |
| 2 | 是否支持 vendor（代运营工作区）登录 | DECISIONS 只说“普通用户端不能有服务器状态”，没有定 vendor 是否进首版；现有 App 拒绝 vendor | **首版拒绝**，文案“当前版本仅支持管理员账号”；1.11 写好了将来的降级规则 |
| 3 | App 内是否提供“签发管理访问令牌”（需要 JWT 会话 + step-up） | A08 后端已就绪，设计稿没有这个页面 | **首版不签发**，只支持粘贴 `sat_` 登录，以及在“站点与凭据”里列出、吊销 |
| 4 | 带 key 的写断网后自动用同一 key 重试几次 | 文档只规定了“连续 IN_PROGRESS 超过约 30 秒转待核对”，没有规定传输失败后的自动重试次数 | **自动 2 次**（间隔 2 秒、5 秒，仅前台），之后转“待核对” |
| 5 | 增量拉取的回退窗口取多大 | B09 只举例“latest_id−200，或比最新一行早 30 秒以上的最大 id” | **按 created_at 回退 30 秒**；解析失败时退 200 个 id（4.3） |

---

## 审查记录

本轮 11 条审查意见都对照源码核实过，全部属实，已在本章修改。下面只记两件事：没有照原建议做的部分及理由，以及要由其他章节同步的地方（本轮只改本文件）。

| 意见 | 本章改动 | 未照做的部分 / 需要其他章同步 |
|---|---|---|
| 只读 `sat_` 调 `users-usage`、`api-keys-usage` 会被拒（`admin_access_token_auth.go` 放行表只有两条批量读） | §0 第 6 条、§1.6 第 3 步（只读识别）、§2.4、§2.6.3、§3.2“只读”行、§6.5 | 用户章节（列表、详情、Key 卡片的今日消费）和分组章节（API 密钥页今日消费）要引用 §2.6.3：只读时不发请求、显示 `—`，收到 403 只影响该数据块 |
| 接受 key 的表漏了复制分组、DELETE 写法矛盾、缺 `X-Idempotency-Recovered`（两条意见内容相同，合并处理） | §2.2、§2.5.1、§2.5.3 | 无 |
| `page_size` 上限与各章冲突 | §4.1 列出允许用到 500 / 1000 的名单，§9.1 | 无（采用“放宽 00、各章不动”这一种） |
| 缺视觉令牌 | §8.2（色值照抄 `vernier-palette.css`，含 model 色调与用法、字号、44pt、对比度、危险按钮） | 账号章节的“模型限流 N”尾段、状态卡模型限流块、“限流 N 分钟”徽章按 §8.2.2 model 一行取色，可在该章加一句引用 |
| 绝对时间的时区各章不一致 | §0 第 10 条、§6.3 规则 + 例外清单；未决问题 1 标为已定（编号保留，模块章节引用了“00 未决问题 3”） | 建议的例外里有“代理到期”，没有采用：模块章节的代理编辑只输入天数（“30 天 / 90 天 / 自定义天数”），列表到期按服务器时区的自然日计算，属于默认规则；兑换码编辑的自定义过期时间是时间点，补进了例外。账号、模块、统计分析章节可删去各自的时区说明，改为引用 §6.3 |
| `USER_NOT_FOUND` 401 / 404 含义不同 | §0 第 3 条、§3.2（查表键含状态码，`USER_NOT_ACTIVE` 再看请求类别）、§9.3、§9.8 | 无 |
| 资金写记录的存储模型各章矛盾 | 选方案 (b)：§0 第 4 条、§2.5.2、§2.5.4、§2.5.5、§9.1、§9.4、§9.5、§9.7、§9.8。只有资金写落盘，余额、兑换码批次、补偿各一个文件，共有字段统一；`set 0` 的待处理标题为“退款结果待核对” | 概览章节：读 `pendingBalances` 时用 `userDisplayName`（不是 `userLabel`），标题按 §2.5.5；“待处理”加一种“补偿结果待核对”行。兑换码章节：`PendingRedeemBatch` 补 `actorUserID`、`idempotencyExpiresAt`；用户章节 §3 指向的“发放补偿”向导在兑换码章节里还没有细化，记录与核对已在 §2.5.5 定义 |
| 金额写入类型 | §0 第 11 条、§2.5.2、§6.1（按接口列出字符串与 JSON number） | 无 |
| `include_counts` 发送时机 | §4.4 写明只在 `page=1` 带 | 账号章节 §1.2 的列表请求要改成只在第 1 页带 `include_counts=1` |
| 数字格式三章各一套 | §6.1、§6.2 合成一张表，函数集中在 `DisplayFormat.swift`（§9.7） | 概览章节 §0.4、统计分析与日志章节 §0.5、模块章节开头改为引用 00 §6.1 / §6.2，删除各自的格式表和往 `DashboardPresentation` 加函数的说法；“850 ms”“182 ms”统一写成不带空格 |
