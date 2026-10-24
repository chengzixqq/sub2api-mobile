# Sub2 原生 iOS 管理端 · 最终实现规格

> 2026-10-22 合稿。SwiftUI，最低 iOS 26。后端基线：sub2 `main` `70116315d`。
>
> 本文件由 `spec/00-conventions.md` … `spec/60-search-modules.md` 七章合成：各章正文原样收录（标题统一降一级，章内引用的 `../` 路径改为相对本文件），各章末尾的“审查记录”不收入正文，其中没有照做的意见与跨章没有同步的事项整理在文末“审查未采纳的意见”。`spec/` 下的章节文件保留不动；章节正文与文末“跨章裁定”冲突时，以裁定为准。

---

## 总览

### 范围

| 本版做 | 本版不做 |
|---|---|
| **主模式**（A 收件箱骨架）：底部 4 个 Tab「概览 · 账号 · 用户 · 监控」+ 独立的搜索 Tab，日志不占 Tab（DECISIONS“主模式骨架”、第 2 轮） | **简化模式**（C 表格工作台）：设置里显示该项、置灰并标“设计中”（60 §3、U42） |
| Vernier 石墨黑白浅色 / 深色两套，默认跟随系统，设置里可固定（00 §8.2，60 §3） | **A10** Passkey 与 `apple-app-site-association`（维护者决定 Q8，转 BACKLOG） |
| 管理员身份，三种登录：账号密码（+ TOTP、验证码桥页）、管理访问令牌 `sat_`（粘贴使用）、Admin Key（00 §1） | **B10** 重统计提速（维护者决定 Q17，转 BACKLOG）；App 按“各卡独立加载 + 长超时”的退路处理（U54） |
| 多站点；推送（APNs 与 Bark / ntfy / Webhook，00 §7，60 §7） | vendor（代运营工作区）登录：首版拒绝（00 §1.11，U01），各章写的 vendor 规则是预留 |
| 旧站点按 capability 降级（00 §5） | App 内签发 `sat_`（U02）；设计稿里未选中的变体；告警规则、订阅管理、模型白名单等“在 Web 中编辑”的配置 |

### 页面地图

| 位置 | 页面 / 流程 | 呈现与路由 | 规格 |
|---|---|---|---|
| 全局 | 登录（添加站点）、验证码桥页、两步验证 | 没有活动站点时为根视图，否则 sheet `.addSite` | 00 §1.3–§1.6，60 §4 |
| 全局 | 合规确认、二次验证（step-up） | 全局 sheet，同一时间只弹一个 | 00 §1.10、§2.6 |
| 全局 | 站点切换菜单 | 概览、账号的标题菜单 | 10 §0.7-5，00 §1.1 |
| 全局 | 推送点按落点 | 必要时先切站点 → 切 Tab → push | 00 §7.5，10 §0.7-4 |
| 概览 Tab | 概览（常规布局 / 平静布局，同一页） | Tab 根，大标题 = 站点名 | 10 §1、§2 |
| | 告警详情（手动解决、静默） | push `.alert(id:)` | 10 §3、§7.1 |
| 账号 Tab | 账号列表（按平台分组、组头告警 sheet、选择模式与操作坞） | Tab 根，徽标 = 错误账号数 | 20 §1、§8 |
| | 账号详情（状态卡 + 按钮行、容量、今日、记录，下接六个内联编辑分区，⋯ 菜单） | push `.account(id:)` | 20 §2、§3 |
| | 测试连接 | sheet `.accountTest(id:)` | 20 §4 |
| | 恢复状态 / 启停调度 / 启用账号 | 确认框 + 回执 | 20 §5 |
| | 更换 API Key、Base URL、刷新令牌、重新授权 | sheet / 直接执行 | 20 §6 |
| | 新建账号（单页长表单 + 创建并测试） | 全高 sheet | 20 §7 |
| | 定时测试（只读） | push | 20 §9 |
| 用户 Tab | 用户列表（快捷充值头像条） | Tab 根 | 30 §1 |
| | 用户详情 | push `.user(id:)` | 30 §2 |
| | 充值 / 退款键盘与待核对 | sheet | 30 §3 |
| | 充值与调整记录（全部） | push | 30 §4 |
| | 新建用户（基础 · 权限与并发） | push 全屏 | 30 §5 |
| | 编辑用户（基础 · 权限与并发 · Key 与限额） | push 全屏 | 30 §6–§8 |
| | 发放兑换码（补偿） | sheet `.redeemGrant(userID:pendingID:)` | 60 §19 |
| 监控 Tab | 概况 · 渠道 · 告警（分段） | Tab 根 | 10 §4–§6 |
| | 告警详情 | push `.alert(id:)` | 10 §3 |
| 搜索 Tab | 搜索目录 | Tab 根（`Tab(role: .search)`） | 60 §1 |
| | 全局搜索结果、“查看全部”结果页 | 搜索态；push `.searchResults(kind:query:)` | 60 §2 |
| 目录 · 记录 | 使用记录（用量明细 · 错误请求 · 上游错误） | push `.logs(...)` | 40 §6 |
| | 请求详情（成功 / 上游失败已恢复 / 失败） | push `.request(...)` | 40 §7 |
| | 告警事件 | 切到监控 Tab 的告警段 | 60 §1.1（U41） |
| 目录 · 资源 | 分组列表 | push `.groups(segment:)` | 50 §1 |
| | 分组详情 | push `.group(id:)` | 50 §2 |
| | 编辑 / 新建分组、添加账号 | sheet | 50 §3、§4 |
| | 成员批量写入逐项结果、分组 API 密钥、分组订阅 | push | 50 §5–§7 |
| | 首页下钻的分组内账号（过渡版本；最终版不新增页面） | — | 50 §8 |
| | 统计分析（卡片流） | push `.analytics(...)` | 40 §1 |
| | 更多图表、单图、全部排行、模型页 | push | 40 §2–§5 |
| | 兑换码（行内展开） | push `.redeem(...)` | 60 §8 |
| | 编辑兑换码、批量生成（分步向导）、生成结果核对 | sheet | 60 §9–§11 |
| | 代理列表、代理详情（含被改走的账号） | push | 60 §12、§13 |
| | 编辑 / 添加 / 续期代理 | sheet | 60 §14 |
| | 公告列表、公告详情、已读情况 | push | 60 §15、§16、§18 |
| | 编辑 / 新建公告 | sheet | 60 §17 |
| 目录 · 设置 | 界面与模式 · 站点与凭据（外观、Face ID、通知、站点、当前站点、待核对） | push `.settings(focus:)` | 60 §3 |
| | 登录设备、管理访问令牌、推送通知 | push | 60 §5–§7 |
| 目录 · 在 Web 中打开 | 系统设置、支付与套餐 | Safari | 60 §1 |

按 7 段结构写的页面 / 流程节共 57 个（10 章 6、20 章 9、30 章 8、40 章 7、50 章 8、60 章 19）。

### 阅读顺序

1. 本总览。
2. 文末“审查未采纳的意见 · 一、跨章裁定”（R01–R20）：合稿时发现的跨章不一致，正文与裁定冲突时以裁定为准。
3. **00 通用约定**，全文必读：站点与凭据、请求层、错误、幂等与待核对、列表与增量、capability、数值与时间、推送、视觉令牌。
4. **10 §0.7 应用骨架**（Tab、导航栈、路由、跨 Tab 跳转、站点菜单、回执、状态轨），本版骨架以它为准（U14）；路由的其余目的地看 40 §0.1、50 各节标题、60 §0.1。
5. 按要做的页面读对应章。每章 §0 是本章共用规则，之后每个页面一节，固定 7 段：入口与导航 → 数据来源 → 字段 → 显示映射 → 交互与写操作 → 状态 → 刷新策略 → 对现有代码的改动点。
6. 开工前看“实现顺序建议”和“现有代码改动总表”；遇到没定的事项查“全部未决问题”，先按建议默认值实现。

### 与设计稿、后端清单的关系

- **设计稿** `html-preview/main.html`（源码 `html-preview/layouts/main/00-core.jsx`、`v-*.jsx`，已定变体见 `v-decided.jsx`，演示数据 `html-preview/shared/data.jsx`，路由样例 `html-preview/tools/routes/*.json`，文案规则 `html-preview/BUILDER_GUIDE.md`）：版式、文案与交互的来源，各章“设计稿”栏注明对应组件。未选中的变体不实现；演示数据只是示意，数值口径以后端字段为准。规格与设计稿不同的地方都在正文写明理由，多数是后端源码事实，例如：删除分组后 Key 被拒绝而不是“不再属于任何分组”（50 §0.5）、“客户端亲和调度”后端没有（20 §3.3）、自定义范围按站点时区计算（40 §0.2）、发放补偿仍落盘待核对（60 §19）。
- **DECISIONS.md**：界面决定。第 3 轮以“更正”后为准，文末“设计稿评审意见”“TPM 口径”最新。TPM 口径已定：首页 TPM 取 `dashboard/rates`（B01，含缓存 Tokens、不受运维开关影响），旧站点退路见 00 §5 `dashboard.rates` 一行与 10 §1.2。
- **BACKEND-API-CHANGES.md**：给后端维护者的适配清单。维护者已在 sub2 `main` 实现除 A10、B10 以外的全部条目；本规格写的是**真实实现口径**，“实现进度”表的备注优先于条目原文（例如 C03 的版本号是 `ETag: "cv-N"`，不是 `updated_at`）。附录 A（后端已支持）与附录 B（App 侧处理）的事项已分散写进各章；旧站点缺某条时按 00 §5 的 capability 表降级。接口路径、字段与 reason 都在 `70116315d` 源码里核过（源码位置见 20 章“接口核实清单”、60 章“附录 · 本章接口清单”及各章正文），稳定错误码以 sub2 `docs/API_ERROR_CODES.md` 为准。
- **口径优先级**：DECISIONS ＞ 实现进度表备注 ＞ 清单条目原文 ＞ 设计稿演示数据（00 开头）。本文件内部：通用机制以 00 为准，页面专属事实以所属章为准，跨章冲突以文末裁定为准。

### 写法约定

- “00 §2.5”指第 00 章 2.5 节；章内只写“§x.y”或“x.y”时指本章。章节编号与 `spec/` 文件一致。
- 接口路径：00 章写全 `/api/v1/...`；其他章多数省略 `/api/v1` 前缀（各章开头注明）。
- “回执”= 底部 toast（文字 + 最多一个按钮，“撤销”或一个自定义动作）；“状态胶囊”= 左侧悬浮胶囊，相邻条目连成一根状态轨（00 §8.1）；`—` = 缺失或读取失败，0 照常显示 0（00 §6.5）。

### 目录

1. 00 · 通用约定
2. 10 · 今日（概览）与监控
3. 20 · 账号 Tab
4. 30 · 用户与 API Key（用户 Tab）
5. 40 · 统计分析与日志
6. 50 · 分组
7. 60 · 搜索目录与其他模块
8. 实现顺序建议
9. 现有代码改动总表
10. 全部未决问题
11. 审查未采纳的意见（一、跨章裁定；二、未照做的审查建议）

---

## 00 · 通用约定

> 本章适用于 Sub2 原生 iOS 管理端（SwiftUI，最低 iOS 26）的所有页面。各页面章节直接引用这里的规则，不再重复。
>
> - **后端基线**：sub2 `main` `70116315d`（2026-10-22 对照源码核对）。本章写到的路径、字段、reason、capability 都在这个提交里查过；旧站点按第 5 节降级。
> - **口径优先级**：`DECISIONS.md`（第 3 轮以“更正”为准，文末“设计稿评审意见”和“TPM 口径”最新）＞ `BACKEND-API-CHANGES.md` 实现进度表的备注 ＞ 清单条目原文 ＞ 设计稿演示数据。
> - 路径一律写全（`/api/v1/...`）。“App 动作”指客户端代码要做的事，“文案”指界面上显示的字。

---

### 0. 硬规则速查

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

### 1. 站点与凭据

#### 1.1 站点（ServerProfile）与多站点

| 项 | 规则 |
|---|---|
| 站点地址 | 只接受 `https://host[:port]`，不允许路径、userinfo、查询串和 fragment（沿用 `AppModel.validatedURL`、`ServerProfile.validatedURL`）。主机名转小写。 |
| 添加站点 | ① `GET /api/v1/settings/public`：成功且带 `version` 才算 Sub2 站点，同时取 `site_name`（作为默认站点名）、`site_logo`、`server_timezone`、`captcha_provider`、`totp_enabled`、`backend_mode_enabled`。② 选登录方式（1.3）。③ 登录成功后调 `GET /api/v1/admin/me`（1.9），通过后才写入站点列表。添加失败不能替换当前已连接的站点（沿用 `AppModel.connect` 的 candidate 机制）。 |
| 每站点独立保存 | 凭据（Keychain，service `com.chengzixqq.sub2mobile.credentials`，account = 站点 UUID）、设备标识 `deviceID`（1.2）、待核对写入（2.5.5）、推送设备 id（第 7 节）、ETag 缓存与增量游标（仅内存）、`/admin/me` 快照（仅内存）。 |
| 切换 | 概览标题下拉菜单（DECISIONS 第 2 轮）与“设置 → 站点与凭据”。切换 = 取消当前站点所有请求和定时器 → 新 generation → 读该站点凭据 → `/admin/me` → 进入概览。凭据已清除时进入该站点的登录页。 |
| 删除站点 | 先按“退出”顺序处理（1.7.5），再删除 Keychain 凭据与 `deviceID`；该站点还有待核对写入时，把站点信息留在 `profileArchive` 里（沿用现状），待核对列表仍能显示站点名。 |
| 显示 | 站点行：名称 + 主机（等宽字体）+ 登录方式徽章（账号 / 管理访问令牌 / Admin Key）+ 身份（`/admin/me` 的 `user.email`）。Admin Key 站点加一行“以 <email> 身份操作（第一个管理员）”。 |

#### 1.2 设备标识与会话绑定（A04）

- **`deviceID`**：每个站点生成一个 UUID（小写），存在 Keychain（与凭据同一 service，account = `<站点 UUID>.device`，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）。重装 App 后重新生成（需要重新登录，这是预期行为）。不同站点用不同的值，避免站点之间关联同一台手机。
- **每个请求**都带请求头 `X-Device-ID: <deviceID>`（服务端全局中间件 `SessionBindingContext` 读取，最长 128 字节）。
- **登录时**（`POST /api/v1/auth/login`）在请求体里带 `client`：`{"type":"ios","device_id":"<deviceID>","device_name":"<UIDevice.current.name>"}`。`device_id` 必须与请求头的 `X-Device-ID` 相同。2FA 第二步（`/api/v1/auth/login/2fa`）不需要再带，服务端从临时会话继承。
- **服务端行为**：只有站点开启 `session_binding_enabled` 时才校验。原生会话的绑定方式由站长设置 `session_binding_native_mode` 决定：`strict`（默认，IP + UA）、`device`（只校验 `X-Device-ID`）、`ua_only`、`off`。绑定方式在签发时写进令牌，之后的刷新沿用。
  - `device` 模式下请求缺 `X-Device-ID` 或值不同，会返回 401 `SESSION_BINDING_MISMATCH`，**整个会话家族同时被撤销**。所以 1 号硬规则没有例外。
  - `strict` 模式下切换 Wi-Fi、蜂窝或 VPN 就会掉线。UA 固定为 `Sub2Mobile-iOS`，不带版本号，避免 App 或 iOS 升级导致失效（附录 B L2）。
- **提示**：`/admin/me` 的 `security.session_binding_enabled=true` 时，“站点与凭据”里该站点下显示说明“站点开启了会话绑定；切换网络可能需要重新登录”。admin 角色还可以再读 `GET /api/v1/admin/settings` 的 `session_binding_native_mode`：值为 `device` 或 `off` 时不显示这条说明，值为 `strict` 或 `ua_only` 时补一句“可请站长把原生客户端绑定方式设为 device”。

#### 1.3 登录方式

| 方式 | 请求头 | 以谁的身份 | step-up | 吊销 | 有效期 | 推荐 | 限制 |
|---|---|---|---|---|---|---|---|
| **账号 + 密码（+ TOTP）** | `Authorization: Bearer` | 本人 | 可以 | 单个会话下线、退出后立即失效（1.7、1.8） | access 默认 60 分钟；refresh 30 天，每次刷新重新计时 | **推荐**，登录页默认选中 | 站点开了验证码时走桥页（1.5）；会话绑定见 1.2 |
| **管理访问令牌 `sat_…`**（A08） | `x-api-key: sat_…` | 令牌所属的管理员 | 不可以（403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`） | 在 Web 或 App 里吊销；多实例部署最多 30 秒后生效 | 签发时选 1–365 天（默认 90） | 次选：只看监控、告警的设备用只读令牌 | 需要 capability `admin.access_tokens`；只限 admin 角色；只读令牌的写操作返回 403 `ACCESS_TOKEN_READ_ONLY`（例外见 2.6.3） |
| **Admin Key** | `x-api-key: <key>` | 站点的**第一个管理员** | 不可以 | 只能在 Web 重新生成，全站一起失效 | 不过期 | **不推荐**，选项上标“不推荐” | 丢了手机等于泄露全站最高权限；审计日志都记在第一个管理员名下 |

- 登录页的三个选项按上表顺序排列。Admin Key 选项下写明：“以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。”
- 粘贴的密钥以 `sat_` 开头时，自动按管理访问令牌处理（服务端也是按前缀区分的，`server/middleware/admin_auth.go`）。
- 首版不在 App 内签发 `sat_`（未决问题 3），只支持粘贴使用；“站点与凭据”里可以列出和吊销自己的令牌：`GET /api/v1/admin/access-tokens` 返回 `{items:[{id,name,prefix,last4,scope,expires_at,last_used_at,last_used_ip,created_at,current}]}`，`DELETE /api/v1/admin/access-tokens/:id` 返回 `{message,current}`。`current=true` 表示吊销的就是本机正在用的令牌，App 要立即退出该站点。只读令牌可以吊销自己。

#### 1.4 账号密码登录流程

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

#### 1.5 验证码桥页（A09）

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

#### 1.6 管理访问令牌 / Admin Key 登录

1. 输入框标签“管理访问令牌或 Admin Key”，用 `SecureField`，可粘贴。
2. 带 `x-api-key` 调 `GET /api/v1/admin/me`：
   - 200：读 `auth_method`（`admin_access_token` / `admin_api_key`）和 `user`，写入凭据。
   - 401 `INVALID_ADMIN_KEY`：文案“令牌或 Admin Key 无效（已吊销、已删除，或站点不支持管理访问令牌）”。
   - 401 `ACCESS_TOKEN_EXPIRED`：文案“管理访问令牌已过期，请重新签发”。
   - 403 `FORBIDDEN`：令牌主人已不是管理员。
   - 423：进入合规确认（1.10）。
   - 404 且响应体不是 JSON：旧服务端没有 `/admin/me`，退回 1.9 的旧服务端路径。
3. 这两种凭据没有刷新令牌，也没有会话列表（`/api/v1/auth/*` 只接受 JWT）。`/admin/me` 不返回令牌范围；`auth_method=admin_access_token` 时登录后调一次 `GET /api/v1/admin/access-tokens`，取 `current=true` 那项的 `scope`（`read` / `write`），存进站点会话的 `isReadOnlyToken`；这个请求失败时先按可写处理，收到 `ACCESS_TOKEN_READ_ONLY` 后再改成只读。只读令牌在 App 里所有写操作按钮置灰，旁边小字“只读令牌”；例外与限制见 2.6.3。

#### 1.7 令牌生命周期

##### 1.7.1 有效期

- access token 默认 60 分钟（配置里显式写了 `access_token_expire_minutes: 0` 的站点仍是 24 小时），以登录或刷新响应的 `expires_in`（秒）为准。`expires_in` 缺失时按 300 秒处理（沿用现状）。
- refresh token 30 天，每次刷新重新计满。

##### 1.7.2 刷新（A03）

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

##### 1.7.3 吊销（A05）

- 退出、单个会话下线、撤销全部会话、刷新令牌重放、会话绑定失效、改密之后，已签发的 access token **立即**失效：下一次请求返回 401 `TOKEN_REVOKED`。App 按“会话失效”处理，不尝试刷新。
- Redis 故障时服务端放行（fail-open），所以吊销不是绝对即时，界面文案不要承诺“立即”。

##### 1.7.4 Admin Key / sat_

- 没有刷新流程。任意请求返回 401 `INVALID_ADMIN_KEY` 或 `ACCESS_TOKEN_EXPIRED` 时，清除该站点凭据，进入登录页并预选原来的登录方式。

##### 1.7.5 退出登录（顺序固定）

1. 有推送设备 id 时，先 `DELETE /api/v1/admin/push/devices/:id`（第 7 节）。失败只记下“待删除”，不阻断退出。
2. JWT 会话：`POST /api/v1/auth/logout`，请求体 `{refresh_token}`，**同时带** `Authorization: Bearer <access>`。服务端会删除刷新令牌，并让这个会话的 access token 立即失效。现有代码只带请求体、不带鉴权头，要改。
3. `sat_`：用户选择“移除站点”时，调 `DELETE /api/v1/admin/access-tokens/:id`（先从 `GET /api/v1/admin/access-tokens` 里找 `current=true` 的那条拿到 id），确认框写明“同时吊销这个管理访问令牌”。只是“退出”时不吊销。
4. 不论网络结果如何，都清除 Keychain 凭据、内存状态、ETag 缓存和游标（沿用 `AppModel.logout` 的“本地先擦除”）。

#### 1.8 会话列表（A07）

- 只有 JWT 登录时显示，放在“设置 → 站点与凭据 → <站点> → 登录设备”（页面布局由设置章节定）。
- `GET /api/v1/auth/sessions` → `{items:[{id, device_name, client_type, user_agent, ip, created_at, last_seen_at, expires_at, current}]}`，按最后活跃倒序，最多 50 条。显示：设备名（为空时显示 `client_type` 或“未知设备”）、IP、“最后活跃 <相对时间>”、本机条目标“本机”。部署前就已存在的会话，第一次刷新令牌后才会出现，且没有 `client_type`。
- 单个下线：`DELETE /api/v1/auth/sessions/:id` → `{message, current}`。`current=true` 时 App 立即退出该站点。404 `SESSION_NOT_FOUND`：从列表里移除这一条。
- 踢掉其他设备：`POST /api/v1/auth/revoke-all-sessions {"keep_current":true}`，确认框写“其他设备会立即退出登录”。**必须带请求体**：不带请求体时服务端会撤销包括本机在内的全部会话，那种情况下 App 要随后本地退出。

#### 1.9 启动探测：`GET /api/v1/admin/me`（A02）

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

#### 1.10 合规确认（423）

- 触发：`/admin/me` 的 `compliance.required=true`，或任一 admin 请求返回 423 `ADMIN_COMPLIANCE_ACK_REQUIRED`。请求体 `metadata` 里有 `version`、`document_url_zh`、`document_url_en`、`document_path_*`。
- 流程：全屏 sheet。`GET /api/v1/admin/compliance` → `{required, version, document_url_zh, document_path_zh, ack_phrase_zh, …, acknowledgement?}`。用 `SFSafariViewController` 打开 `document_url_zh`（为空时用 `站点 + document_path_zh`）。输入框要求逐字输入 `ack_phrase_zh`，一致后才能点“确认”。提交 `POST /api/v1/admin/compliance/accept {"phrase":"<输入值>","language":"zh"}`，成功后重调 `/admin/me`，再重发被拦下的读请求；被拦下的写请求回到原确认框。
- 只读 `sat_` 不能提交确认（返回 403 `ACCESS_TOKEN_READ_ONLY`），文案“只读令牌不能完成合规确认，请用账号登录或在 Web 完成”。Admin Key 提交时按第一个管理员记录。

#### 1.11 角色

| `user.role` | 首版行为 |
|---|---|
| `admin` | 全部功能（受 capability 与站点开关约束） |
| `vendor` | 首版拒绝登录，沿用现状：文案“当前版本仅支持管理员账号”（未决问题 2）。将来支持时按 `workspace.permissions` 与服务端白名单降级：非白名单路由返回 403 `FORBIDDEN`（“This operation is not available for your workspace”）；`sat_` 只发给 admin；推送只推给 admin；后端模式下 vendor 不能登录 |
| 其他 | 拒绝，文案同上 |

---

### 2. 请求层

#### 2.1 基础 URL 与会话

- URL = `<站点 origin>/api/v1/<path>`（沿用 `APIClient.makeRequest`）。
- `URLSessionConfiguration.ephemeral`：关闭 Cookie、凭据存储和 `URLCache`，缓存策略 `.reloadIgnoringLocalCacheData`，拒绝一切重定向（沿用 `URLSessionTransport`）。ETag 由 App 自己管理（4.2），不依赖系统缓存。
- 同一站点并发请求不超过 6 个（`httpMaximumConnectionsPerHost` 默认值），首页批量请求排队。

#### 2.2 请求头

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

#### 2.3 超时

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

#### 2.4 重试规则

| 请求类别 | 网络错误 / 超时 | 502 / 503 / 504 | 429 | 401 `TOKEN_EXPIRED` |
|---|---|---|---|---|
| **读**：GET，以及查询类批量 POST（`/api/v1/admin/accounts/runtime/batch`、`/api/v1/admin/accounts/today-stats/batch`、`/api/v1/admin/dashboard/users-usage`、`/api/v1/admin/dashboard/api-keys-usage`；其中后两个对只读 `sat_` 不可用，见 2.6.3） | 自动重试最多 2 次（间隔 1 秒、3 秒，加 0–500 ms 随机抖动） | 同左 | 按 `Retry-After` 推迟该数据块（2.7.2），不阻塞其他块 | 刷新后重发 1 次 |
| **带 key 的写**（2.5） | 进入 2.5.4 的“确认结果”流程：同一 key 自动重试最多 2 次 | 同左 | 同左，退避后用同一 key | 刷新后用同一 key、同一请求体重发 1 次 |
| **不带 key 的写**（含旧站点没有 `admin.idempotent_writes` 时） | **不自动重试**。读回服务器状态逐字段比对（页面章节定义读回接口）；比对不了就提示“结果未确认，请刷新核对后再操作” | 同左 | 提示“操作过于频繁，请 N 秒后再试”，不自动重发 | 刷新后重发 1 次（中间件在执行前拒绝，安全） |
| 登录、2FA | 不重试 | 不重试 | 倒计时 | — |
| 刷新令牌 | 见 1.7.2 | 见 1.7.2 | 见 1.7.2 | — |

- 所有自动重试都绑定在当前会话代号上，切站或退出即取消（沿用 `check(snapshot)`）。
- `STEP_UP_REQUIRED`、423 见 2.6、1.10。它们都在业务执行前返回，所以重发时沿用原来的 Idempotency-Key 和请求体。

#### 2.5 Idempotency-Key

##### 2.5.1 接受 key 的接口

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

##### 2.5.2 生成与冻结

- **一个用户意图 = 一个 key**：用户在确认框里点下确认时生成 UUID v4（小写），同时作为 `X-Request-ID`。
- **冻结**：key 生成后，请求体就固定下来。请求体用 `JSONEncoder` + `.sortedKeys` 生成，金额字段的类型按 6.1（只有余额调整用字符串）。可以保存原始字节，也可以保存字段、每次确定性地重新编码；两种都必须保证重试时字节一致。
- **哪些要落盘**：只有**资金写**（余额调整、批量生成兑换码、发放补偿）要在发送前把记录写进本机文件（2.5.5）。**落盘失败就不发送**（沿用 `AppModel.remember`），提示“未决记录无法保存，已暂停此操作”。新建、编辑类写入（新建用户 / 账号 / 分组 / 代理 / 公告、复制分组等）只在内存里冻结：表单或 sheet 持有 key 和请求体，直到结果确定；App 被杀后 key 丢失，再次提交前按页面章节的读回方法核对。新建用户的初始余额虽然是金额，但邮箱唯一，重复提交只会得到 409 `EMAIL_EXISTS`，不会重复入账，所以不要求落盘。
- 重试必须字节一致，并且由同一个操作者发出：服务端指纹包含方法、路由、操作者和请求体；换了管理员账号再用同一个 key，是另一条记录。
- 用户改了任何内容（金额、备注、勾选“确认混合渠道风险”等），都要换新 key，并重新确认。

##### 2.5.3 响应处理

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

##### 2.5.4 网络中断后的流程

1. 带 key 的写遇到超时、断网、502/504：确认框或 sheet 进入“正在确认结果…”状态（不能关闭，可以“稍后核对”）。
2. 同一 key、同一字节自动重试 2 次（间隔 2 秒、5 秒，仅在前台进行）。得到 2xx 或明确的业务错误就结束。
3. 仍未知：sheet 文案“结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行”。资金写的本机记录转为“待核对”，概览“待处理”和对象详情显示待核对横幅（DECISIONS 第 2 轮、设计稿 `00-core.jsx` 待核对行）；新建、编辑类写入没有本机记录，sheet 停在这个状态，按页面章节的读回方法核对。
4. 待核对的对象（同一用户、同一批次）在核对完成前**禁止发起新的同类写入**（设计稿规则：“答复没回来的生成必须先核对”）。

##### 2.5.5 资金写的本机记录与核对方法

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

#### 2.6 二次验证（step-up）

##### 2.6.1 触发

- **被动**：收到 403 `STEP_UP_REQUIRED`。
- **主动**：对页面章节标注“需要 step-up”的操作，在发送前看 `/admin/me`：`step_up_enabled=true` 且（`step_up_granted=false`，或本地记录的到期时间已过）时，先弹验证，再发请求。当前后端需要 step-up 的、App 会用到的接口：揭示完整 Key（`POST /api/v1/admin/api-keys/:id/reveal`）、签发管理访问令牌（`POST /api/v1/admin/access-tokens`）、修改推送配置（`PUT /api/v1/admin/push/config`）、新建管理员或把用户提升为管理员（`POST /api/v1/admin/users`、`PUT /api/v1/admin/users/:id`，`role=admin` 时）。

##### 2.6.2 流程

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

##### 2.6.3 只读管理访问令牌

只读令牌（`scope=read`）的写方法返回 403 `ACCESS_TOKEN_READ_ONLY`。服务端放行的例外只有这些（方法 + 路由精确匹配）：

- `POST /api/v1/admin/accounts/runtime/batch`、`POST /api/v1/admin/accounts/today-stats/batch`（查询类批量；只有这两个）。
- `DELETE /api/v1/admin/access-tokens/:id`（只能撤销自己）。
- `POST /api/v1/admin/push/devices`（只能 `platform=ios`）、`DELETE /api/v1/admin/push/devices/:id`、`PUT /api/v1/admin/push/devices/:id/subscription`、`POST /api/v1/admin/push/devices/:id/test`。

其他写按钮一律置灰，并标注“只读令牌”。万一收到 `ACCESS_TOKEN_READ_ONLY`，文案“当前管理访问令牌只读，不能执行此操作”，不重试。

**语义上是查询、但用 POST 的接口也会被拒**：`POST /api/v1/admin/dashboard/users-usage`、`POST /api/v1/admin/dashboard/api-keys-usage` 不在放行表里（`server/middleware/admin_access_token_auth.go` 的 `adminAccessTokenReadOnlyAllowedWrites`），只读令牌调用返回 403 `ACCESS_TOKEN_READ_ONLY`。用到它们的数据块（用户列表与详情的今日消费、Key 卡片今日消费、分组 API 密钥页的今日消费）一律这样处理：

- `isReadOnlyToken`（1.6）为真时**不发**这两个请求，对应数字直接显示 `—`，不加错误提示。
- 万一仍收到 403 `ACCESS_TOKEN_READ_ONLY`（例如令牌范围还没读到），只把这个数据块显示为 `—`，并把站点会话标成只读；**不弹**全局错误，也不走 3.2 的“只读”默认动作。

#### 2.7 合规 423 与限流 429

##### 2.7.1 423

见 1.10。任何 admin 请求都可能返回 423，统一由 `APIClient` 抛出 `.compliance`，`AppModel` 弹出全局合规 sheet。同一时间只弹一个。

##### 2.7.2 429

- 秒数 N 的取值顺序：响应头 `Retry-After` → 响应体顶层 `retry_after`（登录 / 刷新限流才有）→ `metadata.retry_after` → 默认 30 秒。
- 数据块收到 429：显示“请求过于频繁，N 秒后自动重试”，这期间不再发这个块的请求。
- 写入收到 429：不自动重试，按钮倒计时。
- `ACCOUNT_TEST_BUSY`（429，实例上同时运行的测试达到 10 个）：提示“站点同时运行的测试已满，请稍后再试”。

#### 2.8 查询参数与时间参数编码

- `start_time` / `end_time` 一律用 UTC 的 RFC3339（`2026-10-18T01:41:00Z`，用默认 GMT 时区的 `ISO8601DateFormatter`）。**不要发 `+08:00` 这种偏移**：`URLQueryItem` 不编码 `+`，Go 端会把它解析成空格，结果是 400。
- 按日期的参数用 `start_date` / `end_date`（`yyyy-MM-dd`，gregorian 历法，`en_US_POSIX`），并同时带 `timezone=<server_timezone>`（IANA 名）。现有 `APIClient.dates` 用的是 `TimeZone.current`，要改。
- 列表参数一律带 `page` 和 `page_size`（4.1）。

---

### 3. 错误处理

#### 3.1 响应信封

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

#### 3.2 reason 总表（App 动作）

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

#### 3.3 未知 reason 的兜底（按 HTTP 状态）

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

#### 3.4 错误展示

- 主文案只用上面的中文文案，**不回显服务端 message**：message 可能含上游 URL、凭据片段或 HTML（沿用 `APIError.server` 的现有原则）。
- 错误态提供“详情”（`DisclosureGroup`）：HTTP 状态、reason、响应头 `X-Request-ID`、时间。方便用户反馈给站长；不写 message。
- 日志（`os.Logger`）只记方法、路径模板、状态、reason、`X-Request-ID`。不记请求体、令牌、Key、验证码证明、`metadata` 的值。

---

### 4. 列表与增量

#### 4.1 分页信封

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

#### 4.2 ETag / If-None-Match / 304

- **支持 ETag 的 GET**：`/api/v1/admin/accounts`（列表）、`/api/v1/admin/users`、`/api/v1/admin/groups`、`/api/v1/admin/dashboard/stats`、`/api/v1/admin/dashboard/home`、`/api/v1/admin/dashboard/snapshot-v2`、`/api/v1/admin/ops/dashboard/snapshot-v2`、`/api/v1/admin/meta/catalog`；另外 `POST /api/v1/admin/accounts/today-stats/batch` 也认 `If-None-Match`（有失败项时不发 ETag）。其中 `users`、`groups`、`dashboard/stats` 需要 `lists.etag`，但对旧站点发 `If-None-Match` 无害。
- **App 自管缓存**：键为 `站点 id + 身份（user.id + auth_method）+ 方法 + 完整 URL（含排序后的查询串）+ 请求体哈希（POST 时）`，值为 `(etag, 解码后的数据, 收到时间)`。请求时带 `If-None-Match: <etag>`；收到 304 就复用缓存数据，把“更新时间”刷新为现在。
- ETag 匹配时服务端照样执行完整查询，304 只省带宽和解码，所以**不能**因为有 ETag 就缩短轮询间隔。
- `dashboard/stats` 在有流量时 `rpm` 每次都变，ETag 很难命中，属正常。`meta/catalog` 的 ETag 按身份区分，切换账号或站点时要清掉。
- 缓存只在内存里，切站、退出、收到 401 时清空；单条缓存超过 10 分钟没用就丢弃。

#### 4.3 since_id 增量拉取（`logs.since_id`）

- 适用：`GET /api/v1/admin/usage`、`GET /api/v1/admin/ops/request-errors`。服务端返回 `id > since_id` 的行，固定按 `id` 降序、第一页、不做 COUNT。`sort_by` / `sort_order` / `exact_total` / `count_mode` 会被忽略，其他筛选照常生效。`since_id=0` 合法。`ops/request-errors` 带 `since_id` 且没有显式时间参数时，不套默认的 1 小时窗口。
- **服务端不保证提交顺序**：小 id 的行可能比大 id 的行晚提交，`latest_id` 只是“本批可见的最大 id”，不是安全水位（B09 审查修正）。所以：

1. **首屏**：`page=1&page_size=100`（不带 `since_id`），得到列表 L。
2. **轮询游标**：取 L 中 `created_at ≤ (L 中最新一行的 created_at − 30 秒)` 的最大 id 作为下一次的 `since_id`；没有这样的行时沿用上一次的游标；`created_at` 解析失败时用 `max(0, latest_id − 200)`。**不能**直接用 `latest_id`。
3. **合并**：新批次与已有列表**按 id 去重**（新数据覆盖旧数据，例如“已处理”状态变了），再按 id 降序排列。只保留最新的 N 条（列表页章节规定 N），超出部分仍可通过“加载更多”按页取。
4. **`has_more=true`**：表示新行超过一页，中间有缺口。放弃增量，改为 `page=1` 全量刷新，并重算游标。
5. **下拉刷新**：一律 `page=1` 全量刷新，用来校准。
6. **400 `SINCE_ID_WITH_PAGE` / `INVALID_SINCE_ID`**：去掉 `since_id`，`page=1` 重来。
7. 没有 capability `logs.since_id` 时的退路：`page=1&count_mode=deferred&start_time=<上次最新 created_at − 120 秒，UTC>&end_time=<现在>`，同样按 id 去重合并。

#### 4.4 include_counts 与派生计数

- `GET /api/v1/admin/accounts?include_counts=1`（需要 `accounts.list_query`）返回 `data.counts{all, needs_attention, error, overloaded, rate_limited, temp_unschedulable, unschedulable, inactive, schedulable_now}`。每一项等于“其他筛选不变、status=该值”时的 total，不受当前 `status` 影响。“受限”数 = `needs_attention − error`。
- 带 `include_counts` 时只要计数变化就不会命中 304。所以只在 `page=1` 的请求上带（首屏、下拉刷新、筛选或平台变化后的第一页）；`page ≥ 2` 的翻页请求**不带**，筛选胶囊上的数字沿用第一页的结果（计数与页码无关）。
- 没有 capability 时，计数由 App 根据全量 lite 列表在本地计算（账号章节）。

#### 4.5 批量 ID 上限（`TOO_MANY_IDS`）

| 接口 | 上限（去重、去掉非正数之后） | App 每批 |
|---|---|---|
| `POST /api/v1/admin/accounts/runtime/batch`（`account_ids`） | 200 | ≤ 200 |
| `POST /api/v1/admin/dashboard/users-usage`、`POST /api/v1/admin/dashboard/api-keys-usage` | 1000 | ≤ 200 |
| `GET /api/v1/admin/groups/capacity-summary`（`group_id` + `group_ids` 合计） | 100 | ≤ 100 |
| `GET /api/v1/admin/accounts` 的 `status` 值个数 | 16（reason 为 `INVALID_ACCOUNT_STATUS_FILTER`） | ≤ 16 |

- 发请求前在本地去重、去掉非正数、排序。仍然收到 `TOO_MANY_IDS` 时，按 `metadata.max`（字符串）拆批重发，结果按 ID 合并。
- 批量结果一律**按 ID 匹配**，不按请求顺序（例如 `failed_account_ids` 是升序集合）。只接受本次请求里有的 ID（沿用 `accountTodayStats(ids:)`）。

#### 4.6 刷新节奏（全局规则）

- **只在前台刷新**。`scenePhase` 变为 `.background` 时取消所有在途请求和定时器；回到 `.active` 时，可见区块立即刷新一次。
- **各区块独立定时**：间隔从“上一次请求结束”开始算，慢区块不阻塞其他区块（沿用现有概览的做法）。默认间隔 60 秒（DECISIONS：前台约 60 秒）；RPM / TPM 趋势和详情页 30 秒；具体数值由页面章节定。倒计时类（限流剩余时间等）每秒在本地递减，不触发请求。
- **下拉刷新**：并发刷新当前页面所有区块；增量列表回到 `page=1`；ETag 照常带。
- **失败**：保留旧数据，区块内显示“刷新失败 · 重试”和“更新于 hh:mm”；下个周期自动再试。连续失败时间隔加倍（60 → 120 → 300 秒封顶），成功后恢复。
- **离开页面、切站、退出**：取消该页面的定时器；迟到的响应不写入（会话代号守卫）。

---

### 5. capability 总表

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

### 6. 数值与时间

#### 6.1 金额（USD）

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

#### 6.2 计数、Token、比率、耗时、时间文字

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

#### 6.3 时区与时钟

- **服务器时区**：取 `/admin/me` 的 `server.server_timezone`（IANA 名）和 `server_utc_offset`；拿不到时取公开设置的同名字段。
- **“今日”**：`dashboard/stats`、账号今日统计、`today-stats/batch` 的“今日”固定按服务器时区，App 改不了。凡是请求“今日 / 昨日 / 小时桶”的接口，都带 `timezone=<server_timezone>`，让口径一致（附录 A S12）。
- **显示规则**（各章引用这一条，不再各写一套）：
  - **默认按服务器时区**：统计与趋势的日界和桶标签、日志与请求详情的时刻、告警触发 / 解决时间、“今天 / 昨天”分组、“剩余 N 天 / 今天到期”这类按自然日的计算（如代理到期、订阅到期）、会话与令牌的时间等，凡是服务端产生或按服务端日界统计的时间，都按服务器时区。统计分析自定义范围也按服务器时区计算（设计稿写的“按本机时区计算”改为“按站点时区计算”）。
  - **例外：管理员在 App 里输入的时间点按本机时区**，编辑控件和这个字段在列表、详情里的回显都用本机时区，并在控件旁或脚注写明“按本机时区 <TZ 名>”。例外只有这些：账号过期时间 `expires_at`（账号章节）；公告有效期 `starts_at` / `ends_at`（模块章节，公告列表与详情同样按本机时区）；兑换码编辑里自定义的过期时间（模块章节，`DatePicker`）；推送免打扰 `quiet_hours`（服务端按设备注册时传的 `timezone` 计算，7.3）。只用“天数”输入的有效期（代理到期、兑换码 N 天）不是时间点，换算后按默认规则显示。
  - 手机时区与服务器偏移不同时，概览副标题末尾加“· 按 UTC+8”（取 `server_utc_offset`），统计分析范围说明行与日志副标题末尾加“（站点时间 UTC+8）”，“设置 → 站点与凭据”写“时间按服务器时区（UTC+8）显示”。时区相同时都不写。
  - “刚刚”“N 分钟前”与倒计时没有时区问题，只用下面的时钟偏差校正；相对时间里的“今天 HH:MM”“昨天 HH:MM”按默认规则。
- **时钟偏差**：每次响应用 `Date` 头计算 `offset = 服务器时间 − 本机时间`（秒级精度，按站点保存）。倒计时和“N 分钟前”都用“本机时间 + offset”计算；`runtime/batch` 返回 `sampled_at` 时，用它作为基准。
- **发出的时间**：见 2.8。

#### 6.4 时间字段格式

| 字段 | 线上格式 | 解析 |
|---|---|---|
| 大多数 `*_at`（`created_at`、`error_at`、`rate_limit_reset_at`、`overload_until`、`last_seen_at` 等）、API Key 的 `expires_at`、代理的 `expires_at` | RFC3339，可能带小数秒，偏移**不一定**是 `Z` | `ISO8601DateFormatter` 依次尝试“带小数秒”和“不带小数秒”；可能为 null |
| 账号的 `expires_at`；代理的 `quality_checked`、`latency_checked_at` | Unix 秒（整数） | `Date(timeIntervalSince1970:)` |
| `token_status.expires_at / refreshed_at`、`sampled_at`、`X-Idempotency-Expires-At`、`computed_at` | RFC3339 UTC | 同第一行 |
| 趋势桶 `date` | `yyyy-MM-dd HH:00` 或 `yyyy-MM-dd`，**不带偏移** | 按响应 `query.timezone` 解析（没有时按请求时带的 timezone）；沿用 `DashboardPresentation.trendDate`，把 timeZone 参数改成服务器时区 |
| 推送免打扰 `quiet_hours.start / end` | `HH:MM` | 按设备注册时传的 `timezone` 计算 |

#### 6.5 “—” 与 0

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

### 7. 推送（A11）

#### 7.1 前提

- capability `push.notifications`，且 `user.role=admin`（vendor 不可用，推送也只发给 active 的 admin）。
- 凭据：JWT、Admin Key（设备记在第一个管理员名下）、`sat_` 都可以；只读 `sat_` 只能注册 iOS 设备（App 本来只注册 iOS）。
- 站点要配置好 APNs：`GET /api/v1/admin/push/config` 的 `ready=true`，而且 p8 私钥必须来自构建本 App 的同一个 Apple Team。`ready=false` 时，推送设置页显示“站点未配置 APNs 推送，请站长在 Web 设置”，不发起注册。
- **通知权限**：用户在“设置 → 推送”里打开开关时，才调用 `UNUserNotificationCenter.requestAuthorization([.alert, .sound, .badge])`，不在启动时请求。拿到授权后调 `registerForRemoteNotifications()`。

#### 7.2 设备注册

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

#### 7.3 订阅

`PUT /api/v1/admin/push/devices/:id/subscription`，请求体：

```json
{"events":["ops_alert.fired","ops_alert.resolved","account.error","account.test_finished"],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":{"start":"23:00","end":"07:00"}}
```

- `events` 只能取这 4 个值，`[]` 表示暂停推送；`min_severity` 取 P0–P3，只作用于告警；`group_ids`（≤ 100 个）和 `platforms`（≤ 20 个）只过滤带分组或平台信息的事件，全站告警照常推送；`account.test_finished` 只推给发起异步测试的人，不受这两项过滤；免打扰按设备 `timezone` 计算，时段内的事件直接跳过、不会补推；`start` 等于 `end` 视为不设免打扰。
- 响应是设备对象。设置页的具体控件由设置章节定义。

#### 7.4 测试与列表

- `POST /api/v1/admin/push/devices/:id/test` → `{delivered:true, provider_status:200}`；成功也会重新启用被停用的设备。错误：503 `PUSH_NOT_CONFIGURED`（站点 APNs 没配好）；502 `PUSH_DELIVERY_FAILED`（`metadata.provider_reason` 例如 `BadDeviceToken`、`Unregistered`，此时设备已被停用）→ 文案“推送服务拒绝了这台设备（<provider_reason>），请重新开启推送”。
- `GET /api/v1/admin/push/devices` → `{items:[…]}`：列出本人的全部推送目标（含 Bark / ntfy / Webhook，App 只读显示）。本机设备 `enabled=false` 时显示 `disabled_reason`，并提供“重新启用”（即重新注册）。

#### 7.5 载荷与深链

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

#### 7.6 退出、换号与多站点

- 退出登录先 `DELETE /api/v1/admin/push/devices/:id`（1.7.5）。会话被吊销**不会**自动删除设备。删除失败时记录“待删除”（按站点保存），下次登录该站点时，先删除再按开关状态重新注册；在“设置 → 推送”里提示“有设备未能从站点移除，可在 Web 删除”。
- 同一台手机在同一站点换了另一个管理员登录：重新注册同一个令牌，设备转给新管理员，订阅和历史重置。
- 多站点：每个站点独立注册、独立保存设备 id，`site_tag` 区分来源。

#### 7.7 限制与退路

- 后台每 15 秒扫描一次，推送最多晚约 15 秒；所有实例停机超过 10 分钟期间的事件不会补推；`account.error` 每台设备、每个账号 30 分钟内最多一条；只有通过 `test-runs` 发起的异步测试才会推送 `account.test_finished`，SSE 测试不推。
- 没有 capability，或站点未就绪：不显示推送开关，只做前台轮询（4.6）。不做后台拉取（BGAppRefresh 不保证执行时间，而且 Keychain 凭据是“解锁时可用”）。

---

### 8. 全局口径、文案与视觉

#### 8.1 口径与文案

各页面章节都遵守下面这些（来自 DECISIONS 与 BUILDER_GUIDE 文案硬规则）：

- **计费**：界面上不出现“营收”，一律叫“计费”（计费趋势、计费明细等）。**账号成本**：“成本”一律叫“账号成本”。**利润** = 实际扣费 − 账号成本，不叫“差额”“毛利”。“实际扣费”“账号成本”“标准”三个口径名保持不变。
- **首页 6 格**：今日实际扣费、请求、错误率、利润、RPM、TPM（3 × 2，按此顺序）。标签只写名字，不写“近 5 分钟”；口径不变：前三类按 00:00 起，错误率、RPM、TPM 是近 5 分钟。**TPM 含缓存 Tokens**，数据源优先 `dashboard/rates?window=5m`（第 5 节 `dashboard.rates` 一行给出退路）。统计分析的“今天”仍是今日 SLA 口径，两处都写明窗口。
- **状态词**：账号为 错误 / 过载中 / 限流中 / 临时不可调度 / 暂停 / 停用 / 正常；用户为 启用 / 禁用（不写“正常”）；“停用”也用于分组、代理、Key。不显示原始枚举。动作：启用调度 / 停止调度、恢复状态、测试连接、刷新令牌、更换 API Key…、重新授权…。告警只有“手动解决”和“静默…”，没有“确认”。
- **状态胶囊**：带状态色的条目，左侧一律用浮动胶囊：宽 4、离左 6、离上下各 10、两端全圆角、颜色取语义色的 `tone`，内容左内边距 ≥ 16。只有 caution、critical、model 三种色调画胶囊，ok、neutral 的条目不画（8.2）。同一列表里紧挨着的几条，不论同色异色，都连成一根连续的状态轨：交界处不缩进、不圆角，颜色直接切换，只有整段的最上端和最下端是圆头。SwiftUI：`.overlay(alignment: .leading) { Capsule().fill(tone).frame(width: 4).padding(.vertical, 10).padding(.leading, 6) }`，相邻粘连由列表容器根据前后条目决定上下内边距与圆角。
- **可逆操作**（调度开关等）直接执行，回执带“撤销”；**资金操作**必须二次确认，写明对象、站点、金额，不给默认金额；删除放在 ⋯ 菜单最后，需要输入对象名称或通过 Face ID。
- 颜色只表达状态；品牌青只表示“可操作 / 已选中”（8.2）。

#### 8.2 视觉令牌（Vernier 石墨黑白）

来源：`html-preview/shared/vernier-palette.css`（`.pal-vernier.light` / `.dark`）、`shared/base.css`、BUILDER_GUIDE“样式”与“文案与语义硬规则”。DECISIONS：配色用游标 Vernier 石墨黑白，浅色、深色两套；第 2 轮 Q1 整体外观是仪器风（`vis-base`）。

**只用下面这些令牌，不自造颜色**（阴影透明度可以调）。浅色、深色两套都要做，默认跟随系统外观。

##### 8.2.1 基础色

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

##### 8.2.2 语义色调

每种色调三个值：`tone` 画圆点、图标、状态胶囊；`ink` 写字；`wash` 做徽章与横幅的底。

| 色调 | 浅色 tone / ink / wash | 深色 tone / ink / wash | 用在 |
|---|---|---|---|
| ok | `#288F48` / `#1B7339` / `#E5F2E9` | `#45BE68` / `#5BCF7E` / `#1E372A` | 账号“正常”、2xx 状态码、测试通过。不画状态胶囊 |
| caution | `#B87D00` / `#875200` / `#F6EFE0` | `#F0B93C` / `#F5C04F` / `#3C3622` | 账号“限流中”“临时不可调度”、429、待核对、≤ 7 天到期 |
| critical | `#B42318` / `#A61D15` / `#F6E5E3` | `#E5483D` / `#FF7468` / `#3A2122` | 账号“错误”“过载中”、其他失败状态码（4xx、5xx、504、529）、危险按钮、“超过当前余额”这类阻止提交的提示 |
| neutral | `#7D878D` / `#596369` / `#EFF1F1` | `#6E7980` / `#9CA6AC` / `#252A2E` | 账号“暂停”“停用”、缺失的状态码。不画状态胶囊 |
| model | `#8559E0` / `#6A3DC2` / `#F0EBFB` | `#9C7CF2` / `#BBA0FF` / `#2D2B43` | **只用于模型限流**：账号行第 3 行的尾段“模型限流 N”（`ink` 色文字）；账号状态卡的“模型限流 N”块（块底 `sunken`，标题和图标用 `ink`，模型名用 `ink1`，剩余时间用 `ink2`）；模型列表、模型映射里被限流模型的“限流 N 分钟”徽章（`wash` 底 + `ink` 字）。账号整体状态不会因为模型限流变成 model 色，行与状态卡的胶囊仍按账号状态取色 |

账号状态 → 色调与设计稿 `STATE_META` 一致：正常 ok；限流中、临时不可调度 caution；过载中、错误 critical；暂停、停用 neutral。状态码 → 色调与 `codeTone` 一致：2xx ok；429 caution；其余失败 critical；缺失 neutral。行和状态卡按客户端最终拿到的码着色，状态码徽章按它自己的码着色。

##### 8.2.3 口径色与图表

| 令牌 | 浅色 | 深色 | 用在 |
|---|---|---|---|
| `legendActual` | `#288F48` | `#45BE68` | “实际扣费”的图例与线 / 柱 |
| `legendCost` | `#CF5F17` | `#EB8840` | “账号成本”的图例与线 / 柱 |
| `legendStandard` | `#7D878D` | `#6E7980` | “标准”的图例与线 / 柱 |
| `chartMain` / `chartBarNow` | `#14181B` | `#E7EBED` | 主线、当前时段的柱 |
| `chartCompare` / `chartBar` | `#7F898F` | `#606A71` | 对比线（如昨日）、其余柱 |

口径色只用在图表上。金额数字一律 `ink1`，不按口径着色，也不用红绿表示涨跌（8.1）。面积图不填色。

##### 8.2.4 用法规则

- 文字要带色调时用该色调的 `ink`，不用 `tone` 本色；`tone` 只画圆点、图标和胶囊。
- 徽章：`wash` 底 + `ink` 字，高 22pt、圆角 6pt、12.5pt semibold。
- 状态横幅：`wash` 底；caution、critical、model 横幅另画状态胶囊（8.1），ok、neutral 横幅只有底色、不画胶囊。
- 玻璃只用于 Tab 栏、工具栏、浮层，用系统 Liquid Glass，不自绘；内容层不透明。列表必须能落到 `List`（滑动操作、多选）。
- Tab 徽标用系统 `.badge(_:)` 的默认样式。

##### 8.2.5 硬规则

- **字号**：正文中文 ≥ 14pt，标签 ≥ 12pt（Tab 栏标签用系统默认）。数字用 `.monospacedDigit()`；模型名、主机、Key 前缀、请求 ID、兑换码用等宽字体 `.monospaced()`。字体用系统字体（设计稿是 `-apple-system` / 苹方，DECISIONS 允许按布局定，主模式不另引字体）。
- **点按区 ≥ 44 × 44pt**：筛选胶囊、分段项、小按钮、回执里的“撤销”、键盘上方的胶囊等，画出来小于 44pt 的控件用 `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` 扩大点按区，画出来的尺寸不变。
- **对比度 ≥ 4.5:1**：文字只用 `ink1` / `ink2` / `ink3` 和各色调的 `ink`，不用 `tone` 写字。
- **危险按钮**（删除、替换令牌等自定义的破坏性按钮）：`criticalWash` 底 + `criticalInk` 字；不用系统红（`#FF3B30`）底白字。系统 `alert` / `confirmationDialog` 里的 `.destructive` 按钮由系统渲染，照常用。

##### 8.2.6 实现

- 新增 `NativeApp/Design/Palette.swift`：每个令牌一个 `Color`，用 `UIColor { $0.userInterfaceStyle == .dark ? dark : light }` 生成，数值逐个照抄 `vernier-palette.css`；文件头注明来源，改色只改这里。
- 同文件定义 `enum Tone { case ok, caution, critical, neutral, model }`，提供 `base` / `ink` / `wash` 和 `drawsRail`（caution、critical、model 为 true）。账号状态、状态码到 `Tone` 的映射放在 `Sub2Core`（不依赖 SwiftUI，便于单测）。
- 现有页面用的系统色（如 `Components.swift` 的 `secondarySystemGroupedBackground`）在改到对应页面时换成令牌。

---

### 9. 对现有代码的改动点

#### 9.1 `Sources/Sub2Core/APIClient.swift`

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

#### 9.2 `Sources/Sub2Core/HTTPTransport.swift`

- `URLSessionTransport`：保留 ephemeral、无缓存、拒绝重定向。`data(for:)` 要让 304 原样返回（现在已经原样返回 statusCode 和 headers，确认 `data` 为空时不报错）。
- 头部键已经转成小写（`headers(_:)`），统一用小写键读 `retry-after`、`x-idempotency-replayed`、`date` 等。
- `StreamingDelegate` 不变；SSE 请求也经过 `makeRequest`，自然带上 `X-Device-ID`。

#### 9.3 `Sources/Sub2Core/APIError.swift`

- `Kind` 增加：`stepUp`、`readOnly`、`rateLimited`、`idempotency`、`conflict`、`notFound`、`unsupported`（非 JSON 404）、`featureDisabled`（`OPS_DISABLED` 等）、`temporary`。
- `server(status:reason:)` 改成**按（HTTP 状态, reason）精确查表**（第 3.2 节），查表键包含状态码：401 `USER_NOT_FOUND` 清除会话，404 `USER_NOT_FOUND` 是对象不存在；`USER_NOT_ACTIVE`（403）再按请求类别（登录 / 刷新 vs 业务接口）区分。不再用 `contains` 子串匹配：现在 `TOTP` / `STEP_UP` / 423 都归成 `.twoFactor`，423 被当成二次验证（附录 B L1），这是错的。
- 增加 `retryAfter: Int?`、`metadata: [String: String]`、`requestID: String?`，供 UI 显示详情、拆批、倒计时。
- 文案沿用“不回显服务端 message”的原则；缺失值文案“不可用”改为 `—`（6.5）。

#### 9.4 `Sources/Sub2Core/Models.swift`

- `AuthenticationKind` 增加 `accessToken`；`Credential` 增加 `case accessToken(String)`。读出旧数据时，`.adminKey` 的值以 `sat_` 开头就迁移成 `.accessToken`。
- `CaptchaProof` 增加 `provider: String?`、`aliyunParam: String?`。
- `PublicSettings` 改为保留原始字段：`captchaProvider` 键是否存在（`hasCaptchaProviderKey`）、`mobileVerifyPath`、`serverTimezone`、`serverUTCOffset`、`version`、`siteName`、`backendModeEnabled`、`totpEnabled`、`loginAgreement*`。`conflict` 不在解码阶段抛错，而是由登录页显示。
- `Page<T>`：`total` / `pages` 允许为 null，新增 `hasMore`、`sinceID`、`latestID`（4.1）。
- `PendingBalanceOperation` 保留（不改名、不迁移文件），按 2.5.5 的共有字段与用户章节 §3.7 扩字段，新字段 `decodeIfPresent` 兼容旧记录；新增 `PendingMoneyWrite` 协议与 `PendingCompensation`。`PendingRedeemBatch` 在 `RedeemCodes.swift`（兑换码章节第 11 节）。

#### 9.5 `NativeApp/Session/AppModel.swift`

- 连接流程：`connect` 里用 `me()` 替换 `verifyAdministrator()`，结果存进 `SiteSession{me, capabilities: Set<String>, serverTimeZone, clockOffset, isReadOnlyToken}`（`isReadOnlyToken` 按 1.6 第 3 步取得），通过 `sessionContext` 下发给页面。页面用 `session.has("dashboard.rates")` 判断能力。
- 全局拦截：`APIClient` 抛出 `.compliance` / `.stepUp` / 会话失效时，`AppModel` 统一弹合规 sheet、step-up sheet，或回到登录页（同一时间只弹一个）。
- 保留 `pendingBalances`，新增 `pendingRedeemBatches`、`pendingCompensations`，各自一个文件、各自的 `pendingPersistenceAvailable` 标记；`remember` / `resolve` 按类型提供（共用一个原子写入的 `persist(_:to:)`）。新增 `pendingMoneyWrites(serverID:) -> [any PendingMoneyWrite]` 供概览“待处理”、平静布局判断和设置页遍历；新增 `reconcile(_:)`，按 2.5.5 的核对方法分派。
- 场景生命周期：监听 `scenePhase`，进入后台时 `client.cancelAll()`、暂停定时器；回到前台时如果距上次 `me()` 超过 5 分钟就重新探测（4.6）。
- 推送：新增 `PushCoordinator`（见 9.7），在 `connect` 成功、`logout` 前后调用。
- `logout`：顺序按 1.7.5；清空 ETag 缓存和游标。
- `report(_:)`：错误 sheet 增加“详情”（3.4）。

#### 9.6 `NativeApp/Session/CredentialVault.swift`

- `KeychainCredentialStore` 增加 `deviceID(serverID:) -> UUID`：读取，不存在时生成并保存（account = `<站点 UUID>.device`，同样是 `WhenUnlockedThisDeviceOnly`）；`remove(serverID:)` 同时删除它。
- `Credential` 的 Codable 增加了 `.accessToken` 分支，`load` 时做旧数据迁移。
- 待删除的推送设备 id 不是敏感数据，可以放在 `UserDefaults`（按站点）。

#### 9.7 建议新增的文件

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

#### 9.8 需要补的测试（`Tests/Sub2CoreTests`）

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

### 10. 本章未决问题

| # | 问题 | 为什么无法从材料推断 | 建议默认值 |
|---|---|---|---|
| 1 | ~~界面上的绝对时间按服务器时区还是手机时区显示~~ | 已定为 6.3 的规则（默认服务器时区，管理员输入的时间点按本机时区）；保留编号，免得其他章节的引用错位 | — |
| 2 | 是否支持 vendor（代运营工作区）登录 | DECISIONS 只说“普通用户端不能有服务器状态”，没有定 vendor 是否进首版；现有 App 拒绝 vendor | **首版拒绝**，文案“当前版本仅支持管理员账号”；1.11 写好了将来的降级规则 |
| 3 | App 内是否提供“签发管理访问令牌”（需要 JWT 会话 + step-up） | A08 后端已就绪，设计稿没有这个页面 | **首版不签发**，只支持粘贴 `sat_` 登录，以及在“站点与凭据”里列出、吊销 |
| 4 | 带 key 的写断网后自动用同一 key 重试几次 | 文档只规定了“连续 IN_PROGRESS 超过约 30 秒转待核对”，没有规定传输失败后的自动重试次数 | **自动 2 次**（间隔 2 秒、5 秒，仅前台），之后转“待核对” |
| 5 | 增量拉取的回退窗口取多大 | B09 只举例“latest_id−200，或比最新一行早 30 秒以上的最大 id” | **按 created_at 回退 30 秒**；解析失败时退 200 个 id（4.3） |

---

## 10 · 今日（概览）与监控

> 本章覆盖底部 Tab「概览」（首页，含平静布局）与「监控」（概况 / 渠道 / 告警三段），以及它们的二级页：告警详情、静默与手动解决、运维监控开关。读者是照着实现 SwiftUI App（最低 iOS 26）的工程师。
>
> 口径依据：`DECISIONS.md`（第 3 轮以“更正”为准，文末“设计稿评审意见”“TPM 口径”最新）、`BACKEND-API-CHANGES.md` 的“维护者决定”与“实现进度”（进度表备注优先于条目原文）、设计稿 `html-preview/layouts/main/v-today.jsx`、`00-core.jsx`（`MonitorScreen` / `MonOverview` / `MonServer` / `MonChannels` / `MonAlerts`）、`html-preview/shared/core.jsx`（`deriveAttention`）、`shared/data.jsx`、sub2 `docs/API_ERROR_CODES.md`。所有接口路径、字段名、reason 都在 sub2 `backend/internal`（main，`70116315d`）源码里核对过；文中写“后端无此能力 → App 退路”的地方是源码里确实没有的。

---

### 0. 本章公共约定

#### 0.1 适用身份

- 本章所有接口都只对**站长管理员**开放：`dashboard/home`、`dashboard/rates`、`dashboard/stats`、`accounts/status-summary`、`/admin/ops/*`、`/admin/channel-monitor-v2/*` 都不在 vendor 白名单里（`server/middleware/vendor_routes.go`），vendor 调用一律 403。
- 判定：`GET /api/v1/admin/me` 的 `workspace` 为 null 且 `user.role == "admin"` 才渲染本章内容；`workspace` 非 null（vendor）时，概览只显示占位“代运营工作区不提供全站概览”，监控 Tab 显示“代运营工作区没有运维监控权限”。（vendor 的完整体验不在本章范围。）
- 设计稿里“服务器区仅管理员可见、普通用户端不能有服务器状态”：App 只允许管理员登录，所以服务器区的显示条件就是上面的站长判定。

#### 0.2 能力探测（`GET /api/v1/admin/me` → `server.capabilities`）

| capability | 本章用途 | 缺失时 |
|---|---|---|
| `dashboard.home` | 首页一次取回 7 段 | 走 §1.2 的逐接口退路 |
| `dashboard.rates` | 首页退路里的 RPM / TPM / 错误率 | 退到 `ops/dashboard/overview?time_range=5m`，再退到 `dashboard/stats` |
| `dashboard.accounts_ranking` | 平静布局“按账号 · 前 4” | 隐藏该分区（不做全量账号 + 今日统计本地排序，首页不值得） |
| `accounts.status_summary` | 待处理里的账号分档、分组可用、平静判定 | 走 D02 退路（§1.2） |
| `accounts.structured_error` | 错误账号行的 `error_at` / `error_summary`（原因短句由 20 §0.2 的 `AccountDisplayState` 生成） | 原因写“上游返回异常”（不显示 `error_message` 原文，20 §0.2），不显示“N 分钟前” |
| `ops.alert_event_counts` | 精确的告警中条数（含被静默的） | 用 `alert-events?status=firing&limit=500` 的条数 |
| `ops.alert_event_details` | 事件带 `rule` / `group_name` / `resolved_by_*` | 另拉 `ops/alert-rules` 与 `groups/all` 拼；规则已删时用 `description` 原文 |
| `ops.alert_latency_metrics` | 认得 `p95_latency_ms` / `p99_latency_ms` 规则 | 这两种规则显示“不受支持（不会触发）” |
| `ops.job_heartbeat_status` | 心跳的 `status` / `expected_interval_seconds` / `next_expected_at` | 本地判定（§4.3） |
| `ops.system_metrics_history` | CPU / 内存小折线 | 前台轮询 overview 时本机攒点，进页面只有当前值 |
| `ops.ingress_reject_totals` | 入口拒绝 `request_count_total` | 翻页累加 `items[].request_count`（最多 3 页，超出写“≥ N”） |
| `ops.monitoring_status` | 区分配置关闭 / 设置关闭，App 内开启 | 用 `PUT /api/v1/admin/settings {"ops_monitoring_enabled":true}`（§7.2） |

ETag 不看 capability，一律按 00 §4.2 处理：`APIClient` 层的 `ConditionalCache`（00 §9.7）自动带 `If-None-Match`、把 304 换成缓存里的解码结果，页面拿到的始终是模型本身，本章不另定义“未修改”类型。本章用到的接口里带 ETag 的只有 `dashboard/home`（`handler/admin/dashboard_home_handler.go:78`）、退路里的 `dashboard/stats` 与 `dashboard/snapshot-v2`、错误账号补字段用的 `GET /api/v1/admin/accounts`（`account_handler.go:840-857`）、§4 的 `ops/dashboard/snapshot-v2`（`ops_snapshot_v2_handler.go:67-70`）；其余接口（`dashboard/rates`、`accounts/status-summary`、`ops/dashboard/overview`、`alert-events`、`channel-monitor-v2/overview` 等）没有 ETag。

告警静默（D01）没有登记 capability：**以事件 JSON 里是否存在 `silence` 键判定**（D01 起该键始终输出，没有静默时为 null）。键不存在 = 旧服务端，按 §7.1 的旧服务端退路处理。

`features` 同一响应里本章要读：`ops_monitoring_enabled`、`ops_realtime_monitoring_enabled`、`ops_monitoring_disabled_reason`（`config_off` / `setting_off` / null）、`channel_monitor_enabled`、`channel_monitor_mode`。`server.server_timezone`、`server.server_utc_offset` 见 0.3。`/admin/me` 不可用（旧服务端）时：时区读 `GET /api/v1/settings/public` 的 `server_timezone` / `server_utc_offset`，运维开关以接口是否返回 404 `OPS_DISABLED` 为准。

#### 0.3 时区

- “今日 / 昨日 / 每小时”一律按**服务器时区**：`dashboard/stats` 与 `dashboard/home` 的 `stats` 段固定按服务器时区，`today-stats` 也是（附录 A S12）。
- 发给 `dashboard/home` 的 `timezone` 只影响 `hourly` 段的分桶；App 传 `server_timezone`，与 stats 段同一天界。`dashboard/trend`、`dashboard/accounts-ranking` 也传 `timezone=<server_timezone>`。
- 小时桶标签形如 `2026-10-16 09:00`，没有时区后缀，按请求时区解析（现有 `DashboardPresentation.trendDate(_:timeZone:)` 可用，传服务器时区）。
- 手机时区与服务器 UTC 偏移不同时，概览导航副标题末尾加“· 按 UTC+8”（取 `server_utc_offset`）。

#### 0.4 单位与格式（本章统一，新增到 `DashboardPresentation`）

| 类型 | 规则 | 例 |
|---|---|---|
| 金额 | `$` + 千分位 + 2 位小数，Decimal 四舍五入；负数用 `−$`；不加 `+`；缺失 `—` | `$1,284.50`、`−$12.30` |
| 紧凑数 | ≥ 1e9 `B`、≥ 1e6 `M`、≥ 1e3 `K`，1 位小数并去掉 `.0`；< 1000 原样整数 | `18.2K`、`240K`、`96.4M` |
| RPM | ≥ 10 取整；0 < x < 10 一位小数；0 显示 `0` | `46`、`0.4` |
| 后端比例（`error_rate`、`sla`、`reliability_rate`，0–1） | ×100，1 位小数 + `%` | `0.0086` → `0.9%` |
| 告警值（`metric_value`、阈值，百分比类指标已是百分数） | 按 §6.3 的单位表，不再 ×100。**阈值 = `rule.threshold ?? threshold_value`**：事件顶层的字段名是 `threshold_value`，`threshold` 只在 `rule` 对象里（`service/ops_alert_models.go:50-51`、`:80`）；规则已删且没有快照（`rule == null`）时用事件自带的 `threshold_value`，单位按未知指标处理（§6.3） | `5.2` → `5.2%` |
| 相对时间 | < 1 分钟“刚刚”；< 60 分钟“N 分钟前”；今天“今天 HH:MM”；昨天“昨天 HH:MM”；更早“M月d日 HH:MM” | `12 分钟前` |
| 倒计时 | `m:ss`，≥ 1 小时 `h:mm:ss`；每秒重算（以绝对时间戳减当前时间，不累减） | `4:37` |
| 时刻 | 服务器时区 `HH:MM` | `10:04` |

现有 `DashboardPresentation.compactNumber` 是 2 位小数（`18.20K`）、`money` 没有千分位、`cost` 缺失写“不可用”，都不符合本章；新增 `compact1(_:)`、`moneyGrouped(_:)`、`ratioPercent(_:)`、`rpm(_:)`、`relativeTime(_:now:timeZone:)`，缺失统一返回 `—`（BUILDER_GUIDE：缺失值显示 `—`，0 显示 0）。

#### 0.5 共享状态与区块状态

- 新增会话级 `@MainActor @Observable final class LiveOpsStore`（随 `SessionContext` 创建、切站点即丢弃）：持有首页聚合、告警列表与计数、运维开关状态、账号状态汇总。概览、监控、告警详情读同一份，任何一处手动解决 / 静默后其余页面立即一致（设计稿 `ctx.alerts / resolveAlert / silenceAlert` 的同一份状态）。
- 每个区块用同一个状态枚举（建议放 `Sources/Sub2Core/BlockState.swift`）：

```swift
public enum BlockState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?)
    case loaded(Value, at: Date)
    case disabled(reason: String)                       // OPS_DISABLED、CHANNEL_MONITOR_DISABLED
    case failed(reason: String?, previous: Value?, at: Date?)
}
```

- 显示规则：有值（loaded 或 previous 非空）就显示值；刷新失败但有旧值时，区块标题右侧加一个小字“更新失败”（可点重试），不清空数字；没有旧值时数字位显示 `—`，区块内一行“加载失败 · 重试”。
- 现有 `DashboardLoadState`（`NativeApp/Features/DashboardView.swift:8-41`）的“晚到的旧请求不能覆盖新请求”逻辑保留，挪到 `NativeApp/Views/LoadState.swift`，内部改存 `BlockState`。

#### 0.6 颜色与状态胶囊

- 账号状态色：错误 / 过载中 = critical；限流中 / 临时不可调度 = caution；暂停 / 停用 = neutral；正常 = ok（`STATE_META`）。
- 告警色 `alertTone`：firing 的 P0 = critical，P1 / P2 = caution，P3 = neutral；不在 firing = 无色（`shared/data.jsx:474-477`）。
- 带状态色的行左侧一律是浮动状态胶囊，相邻行连成一根状态轨（DECISIONS 评审第 3 条与“TPM 口径”末条）；尺寸与粘连规则见 00 §8“状态胶囊”，组件见 §0.7-7，本章只给每行的 tone。
- 金额与涨跌不着色；`▲ / ▼` 用正文墨色。

#### 0.7 本章依赖的应用骨架

00–60 章还没有专门写应用骨架（Tab 结构、路由、跨 Tab 跳转、站点菜单、回执、状态轨）的章节（未决问题 Q10）。本节只写本章用到的部分和接口形状，骨架章节写出后以它为准，本节随之删减。

1. **Tab**：`enum MainTab { case today, accounts, users, monitor, search }`，前四个依次为“概览 · 账号 · 用户 · 监控”（DECISIONS 第 2 轮；设计稿 `00-core.jsx:5-10` `TAB_DEFS`），`search` 是 Tab 栏右侧独立的 `Tab(role: .search)`（60 §1.1）。本章负责 `today` 的根视图 `HomeView`（§1、§2）和 `monitor` 的根视图 `MonitorView`（§4–§6）；两个图标按设计稿 `home` / `pulse` 取 SF Symbols（建议 `house`、`waveform.path.ecg`）。账号 Tab 徽标、选择模式下隐藏 Tab 栏（设计稿 `TabBar` 在 `ctx.selecting` 时不渲染）不在本章。
2. **导航栈**：每个 Tab 各自一个 `NavigationStack(path:)`。本章写“推入”的地方都推到**当前 Tab** 的栈。
3. **路由**（本章用到的；参数名沿用各章定义）：

| 写法 | 目的页 | 定义处 |
|---|---|---|
| `.analytics()` | 统计分析 | 40 §0.1 `analytics`、§1 |
| `.analytics(focus: .perf, metric: .rpm / .tpm)` | 统计分析，滚到“RPM / TPM 趋势”并切到该指标 | 40 §0.1 |
| `.alert(id:)` | 告警详情 | 本章 §3 |
| `.account(id:)` | 账号详情 | 20 §2 |
| `.group(id:)` | 分组详情 | 50 §2 |
| `.groups(segment: .attention)` | 分组列表，选中“需处理”段 | 50 §1 |
| `.user(id:)` | 用户详情 | 30 §2 |
| `.redeem(reconcile: true)` | 兑换码列表并直接进入核对 | 60 §0.1、§11 |
| `.logs(scope: .errors / .upstream, group: id)` | 使用记录（错误请求 / 上游错误，带分组筛选） | 40 §0.1 `logs`、§6 |
| sheet `.accountTest(id:)` | 测试连接 | 20 §4 |

4. **跨 Tab 跳转**：`router.select(_ intent: TabIntent)`，本章用到 `.monitor(segment: .overview / .channels / .alerts)` 与 `.accounts(filter: .limited)`（筛选值见 20 §1.1 的 `needs` / `limited` / `paused`）。行为：切换 `selectedTab`，目标 Tab 的栈回到根，根视图在出现时取走一次 intent（取走后清空，重复切 Tab 不会再次应用）。建议形状：

```swift
@MainActor @Observable final class AppRouter {
    var selectedTab: MainTab = .today
    var paths: [MainTab: NavigationPath] = [:]
    private(set) var pendingIntent: TabIntent?
    func push(_ route: AppRoute)                          // 推入当前 Tab
    func present(_ sheet: AppSheet)
    func select(_ intent: TabIntent)                      // 切 Tab + 回到根 + 记下 intent
    func takeIntent(for tab: MainTab) -> TabIntent?       // 根视图 onAppear / onChange 调用
}
```

   推送点按的落点按 00 §7.5；本章约定先 `selectedTab = .today`，再 push `.alert(id:)` / `.account(id:)`。
5. **站点菜单**：概览的大标题（当前站点名）就是站点切换菜单（DECISIONS 第 2 轮“标题下拉菜单”），SwiftUI 优先用 `.toolbarTitleMenu { … }`（大标题状态下能否点开须实机确认；不行就在 `ToolbarItem(placement: .principal)` 放一个以站点名为标签的 `Menu`）。菜单内容按设计稿 `shared/core.jsx:77-93` `SiteMenu`：站点列表（每项站点名 + 主机名小字，当前站点前打勾）→ 分隔线 →「添加站点…」（60 §0.1 sheet `.addSite`）→「站点与凭据」（push `.settings(focus: .sites)`，60 §3）。切换行为按 00 §1.1（取消请求、新 generation、`/admin/me`、回到概览），成功后回执“已切换到 {站点名}”（设计稿 `setSite`）。20 §1.1 账号 Tab 的标题菜单用同一个组件。
6. **回执（toast）**：本章 §7.1、§7.2 用。底部玻璃条：图标 + 文字 + 最多一个按钮（「撤销」或一个自定义动作；两者都给时只显示自定义动作，BUILDER_GUIDE `showToast`）；显示 4.2 秒后消失（设计稿 `useAppModel` 的计时），新回执直接替换旧回执；出现时用 `AccessibilityNotification.Announcement(text).post()` 朗读，按钮读屏读按钮文字，点按区 ≥ 44pt。建议 `NativeApp/Views/Receipt.swift`：`Receipt{text, icon, tone, action: ReceiptAction?}` + 会话级 `ReceiptCenter.show(_:)`，由 `MainTabs` 在 Tab 栏上方叠加显示。
7. **状态轨**：画法按 00 §8；由列表容器根据前后行决定每行胶囊的上下内边距与圆角（只有整段最上端和最下端是圆头）。建议 `NativeApp/Views/StatusRail.swift`：`.statusCapsule(tone:position:)`，`position ∈ {single, top, middle, bottom}` 由容器计算。
8. **确认框**：本章只用普通确认框与动作表（`.alert` / `.confirmationDialog`），不涉及输入名称匹配或 Face ID 分支（那是删除确认，见 00 §8、20 §0.4）。

---

### 1. 概览 Tab · 常规布局（有待处理时）

#### 1.1 入口与导航

- 入口：底部 Tab 第 1 个「概览」（Tab 名“概览”，DECISIONS 第 2 轮）；冷启动默认 Tab；推送“告警触发 / 账号出错”点按后先切到本 Tab 再推入目标页（00 §7.5，§0.7-4）。
- 导航栏：大标题 = 当前站点名，标题本身是站点切换菜单（§0.7-5）；副标题 = 服务器时区的“10月16日 周五 · 刚刚更新”（规则见 1.3.1）；右上 `···` 菜单：「刷新」「统计分析」。
- 去向（路由写法见 §0.7-3、§0.7-4）：

| 点按 | 去向 |
|---|---|
| 6 格中的今日实际扣费 / 请求 / 错误率 / 利润 | 推入统计分析 `.analytics()`（40 §1） |
| 6 格中的 RPM / TPM | 推入统计分析并滚到“RPM / TPM 趋势”，切到该指标 `.analytics(focus: .perf, metric: .rpm / .tpm)`（40 §0.1） |
| 告警行 | 推入告警详情 `.alert(id:)`（§3） |
| “另有 N 条告警中”行 | `router.select(.monitor(segment: .alerts))` |
| 错误 / 过载账号行 | 推入账号详情 `.account(id:)`（20 §2） |
| 错误账号行内「测试」 | 打开测试连接 sheet `.accountTest(id:)`（20 §4）；sheet 关闭后刷新首页 |
| “受限 N 个账号”行 | `router.select(.accounts(filter: .limited))`（20 §1.1） |
| “可用不足 N 个分组”行 | N = 1 推入分组详情 `.group(id:)`；N > 1 推入分组列表并选中“需处理”段 `.groups(segment: .attention)`（50 §1、§8） |
| 充值 / 退款结果待核对 | 推入用户详情 `.user(id:)`，由 30 §3 完成核对 |
| 兑换码生成结果待核对 | 推入兑换码列表并直接进入核对 `.redeem(reconcile: true)`（60 §11） |
| 今日区“更多统计” | 推入统计分析 `.analytics()` |
| 运行区“渠道”行 | `router.select(.monitor(segment: .channels))` |
| 运维监控未开启提示行 | 打开 §7.2 的开启确认 |

#### 1.2 数据来源

**主路径（capability `dashboard.home`）**：一次请求，各段独立成败。

`GET /api/v1/admin/dashboard/home?timezone=<server_timezone>`（不传 `include` = 全部 7 段）

- 鉴权与参数通过即 HTTP 200；每段 `{status: ok|disabled|error|timeout, error?: <reason>, data?: …}`，只有 ok 才有 `data`。
- 段内容（`service/dashboard_home.go`）：

| 段 | data 字段（本章用到的） |
|---|---|
| `stats` | `today_requests`、`today_tokens`、`today_cost`（标准）、`today_actual_cost`、`today_account_cost`、`stats_updated_at`、`stats_stale`、`yesterday_same_time_actual_cost`、`yesterday_same_time_requests`、`yesterday_same_time_account_cost`、`yesterday_same_time_until`（后四个可为 null） |
| `rates` | 近 5 分钟：`rpm`、`tpm`（含缓存 Tokens）、`error_rate`（比例，关监控为 null）、`upstream_429_count`、`upstream_529_count`（关监控为 null）、`ops_monitoring_enabled`、`errors_available`、`rpm_includes_errors`、`start_time`、`end_time` |
| `hourly` | `today[]`、`yesterday[]`，每点 `date`（`YYYY-MM-DD HH:00`）、`actual_cost`、`requests`、`total_tokens`、`account_cost`；没有用量的小时不出现 |
| `ops` | 近 5 分钟 overview 精简：`health_score`、`sla`、`error_rate`、`upstream_429_count`、`upstream_529_count`、`request_count_total`、`token_consumed`；关监控 = `disabled / OPS_DISABLED` |
| `alerts` | `firing_count`、`by_severity{P0..P3}`（含被静默的 firing）、`top[]`（最新 5 条 firing 事件，完整 `OpsAlertEvent`）；关监控 = disabled |
| `availability` | D02 汇总：`collected_at`、`totals{total, available, error, overloaded, rate_limited, temp_unschedulable, paused, inactive, stopped}`、`groups[]`（含 `shortage`）、`accounts[]`（只含 error / overloaded / rate_limited / temp_unschedulable，最多 100 个）、`accounts_truncated`；**不受运维开关影响** |
| `channels` | `total`、`healthy`、`warning`、`critical`、`unknown`（stale 计入 unknown）、`coverage_state`、`collector_state`；渠道监控关闭 = `disabled / CHANNEL_MONITOR_DISABLED` |

**附加请求（与 home 并发，各自独立）**：

| 用途 | 请求 | 条件 |
|---|---|---|
| 今日成功率（今日区 / 平静布局） | `GET /api/v1/admin/ops/dashboard/overview?start_time=<服务器时区今天 00:00，RFC3339>&end_time=<now>` → `sla` | 运维监控开启；关闭时不请求 |
| 错误账号的结构化错误 | `GET /api/v1/admin/accounts?status=error&lite=1&page_size=100` → 每项 `id`、`error_at`、`error_status_code`、`error_kind`、`error_summary`（`dto/types.go:378-381`；status-summary 的 `accounts[]` 只有 `error_message`，没有这几项） | `availability.totals.error > 0` 且有 `accounts.structured_error`；按 id 与 availability 的错误账号对齐 |

过载账号不需要额外请求：后端只在上游返回 529 时设置过载（`service/ratelimit_service.go:358-363` → `handle529` → `SetOverloaded`，`:1968-1999`；`SetOverloaded` 在 `internal/` 里只有这一个调用点），原因固定写“上游 529”（20 §0.2）。

**逐接口退路（没有 `dashboard.home`，或 home 本身 404 / 网络失败）**：各区块独立加载、独立失败。

| 区块 | 退路请求 | 口径说明 |
|---|---|---|
| stats | `GET /api/v1/admin/dashboard/stats` → `today_*`、`stats_updated_at`、`stats_stale`；`today_actual_cost` / `today_account_cost` 缺失的旧站点沿用现有 `dashboardCostSnapshot()`（`dashboard/snapshot-v2` 只开 `include_stats`） | 同 home |
| 昨日同时 | `GET /api/v1/admin/dashboard/trend?start_time=<服务器时区昨天 00:00>&end_time=<昨天此刻>&granularity=day&timezone=<server_timezone>` → `trend[0].actual_cost`；`stats_stale=true` 时 end_time 改为 `stats_updated_at − 24h` | 附录 A S10 |
| rates | ① `GET /api/v1/admin/dashboard/rates?window=5m`（`dashboard.rates`）；② `GET /api/v1/admin/ops/dashboard/overview?time_range=5m`：窗口秒数 = `end_time − start_time`，RPM = `request_count_total × 60 ÷ 秒数`，TPM = `token_consumed × 60 ÷ 秒数`，错误率 = `error_rate`；③ ②返回 404 `OPS_DISABLED` 时：RPM = `dashboard/stats.rpm`（近 60 秒成功上游转发数；`rpm_available == false` 显示 `—`），TPM = `dashboard/stats.tpm`（**只含 input + output，不含缓存**），错误率 `—` | ③ 的 TPM 口径与统计分析图不同，见 1.3.2 脚注 |
| hourly | `GET /api/v1/admin/dashboard/trend?start_date=<昨天>&end_date=<今天>&granularity=hour&timezone=<server_timezone>` → `trend[]` 按日期前缀拆今天 / 昨天 | 同 home |
| ops | `GET /api/v1/admin/ops/dashboard/overview?time_range=5m` → `health_score`、`upstream_429_count`、`upstream_529_count` | 404 `OPS_DISABLED` → disabled |
| alerts | `GET /api/v1/admin/ops/alert-events/counts`（`ops.alert_event_counts`）+ `GET /api/v1/admin/ops/alert-events?status=firing&limit=5`；没有 counts 时 `alert-events?status=firing&limit=500` 自己数 | 404 `OPS_DISABLED` → disabled |
| availability | `GET /api/v1/admin/accounts/status-summary?include_accounts=true`（`accounts.status_summary`）；再旧的站点：`GET /api/v1/admin/groups/all?include_inactive=true`（`account_count`、`active_account_count`、`rate_limited_account_count`，字段缺省按 0）+ `GET /api/v1/admin/accounts?lite=1&page_size=1000` 本地按 D02 的 state 顺序分档；分组“可用不足”按“available < total × 0.5 或 available = 0”判定 | D02 退路 |
| channels | `GET /api/v1/admin/channel-monitor-v2/overview?range=90m` → 按 `items[].current_status.state` 计数（healthy / warning / critical，其余算未知）；403 `CHANNEL_MONITOR_DISABLED` → disabled | 必须显式传 `range`（附录 B L11） |

本机来源（不调接口）：充值 / 退款待核对 = `AppModel.pendingBalances` 中属于当前站点的记录（30 §3）；兑换码生成待核对 = 60 §11.2 的本机记录 `PendingRedeemBatch`。

#### 1.3 字段 → 显示映射

##### 1.3.1 导航栏与整页

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 大标题 | 当前站点名 | 原样 | — |
| 副标题·日期 | 服务器时区的今天 | `M月d日 EEE`（中文星期“周五”） | — |
| 副标题·更新 | 最近一次所有区块都成功的时间 | “刚刚更新” / “N 分钟前更新”；有区块失败时改为“部分数据未更新” | 首次加载中：“正在加载…” |
| 副标题·时区 | `server_utc_offset` ≠ 手机偏移时 | 追加“· 按 UTC+8” | — |
| 统计新鲜度 | `stats.stats_stale == true` | 今日区标题 meta 改为“统计更新于 HH:MM”（`stats_updated_at`） | — |
| 运维监控未开启行 | `rates.ops_monitoring_enabled == false`，或 ops / alerts 段 `disabled / OPS_DISABLED` | 6 格正下方一行 neutral 提示：“运维监控未开启 · 错误率与告警不可用，RPM 只计成功请求”，右侧「开启」（§7.2）；`disabled_reason == config_off` 时文案改为“运维监控已在服务器配置中关闭”，没有按钮 | — |

##### 1.3.2 顶部 6 格（3 × 2，顺序固定）

标签只写名字，**不写“近 5 分钟”**（评审第 1 条；口径不变）。每格是一个 `NavigationLink`；大数字 `.minimumScaleFactor(0.5).lineLimit(1)`。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 今日实际扣费 | `stats.today_actual_cost` | 金额 `$1,284.50`；右侧小字涨跌 `▲7.9%` / `▼3.2%` = `today_actual_cost ÷ yesterday_same_time_actual_cost − 1`，1 位小数，墨色 | stats 不可用 → `—`；昨日值 null 或 0 → 不显示涨跌 |
| 请求 | `stats.today_requests`（今天 00:00 起已计费请求） | 紧凑数 `18.2K` | `—` |
| 错误率 | `rates.error_rate`（近 5 分钟，`error_count_sla ÷ (success_count + error_count_sla)`） | 比例 → `0.9%` | `error_rate == null`（关监控，Q2）或 rates 不可用 → `—` |
| 利润 | `stats.today_actual_cost − stats.today_account_cost` | 金额，亏损显示 `−$`，不加 `+`；叫“利润”，不叫差额 / 毛利 | 任一缺失 → `—` |
| RPM | `rates.rpm`（近 5 分钟：`request_count × 60 ÷ 300`；开监控时 request_count = 成功 + 错误） | RPM 规则 `46` | `—` |
| TPM | `rates.tpm`（近 5 分钟：`token_consumed × 60 ÷ 300`，**含缓存 Tokens**，与统计分析“RPM / TPM 趋势”同口径） | 紧凑数 `240K` | `—` |

- 无障碍：每格 `accessibilityLabel` = “今日实际扣费 $1,284.50，比昨天同时上升 7.9%。打开统计分析”；RPM / TPM 为“… 打开 RPM 趋势”。
- 退路③（关监控 + 旧服务端）时 TPM 不含缓存：TPM 格下沿加一个 `*`，运维监控未开启行改为“… · TPM 不含缓存 Tokens”。B01 上线的站点不会走到这里（rates 的 TPM 不受开关影响）。

##### 1.3.3 待处理（合并队列，DECISIONS 第 2 轮 Q3）

区块标题“待处理”，meta “N 项”（N = 行数），序号“壹”。行顺序固定：

1. 告警行（每条 firing 事件一行）→ 2. 错误账号（每个一行）→ 3. 过载账号（每个一行）→ 4. 受限（合并成一行）→ 5. 可用不足分组（合并成一行）→ 6. 充值 / 退款待核对（每条一行）→ 7. 兑换码生成待核对（每批一行）。

**告警行**（来源 `alerts.top`，按 P0 → P3、同级 `fired_at` 新在前；见 §6.3 的通用文案函数）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态胶囊 / 图标 | `alertTone(severity)`；铃铛图标 | — | — |
| 标题 | `rule.name` + 空格 + `metric_value`（按指标单位） | “标准组错误率 5.2%” | `rule` 为 null：`title` 去掉开头的 `P1: ` 前缀；`metric_value` 缺失不拼 |
| 右侧徽章 | `severity` | `P1` | — |
| 说明行 | 阈值 `rule.threshold ?? threshold_value`（按单位，0.4）+ `fired_at` 相对时间；`silence != null` 时追加 | “阈值 5% · 12 分钟前触发 · 已静默” | 两个阈值字段都缺失时只写“12 分钟前触发” |
| 另有告警 | `firing_count − top.count > 0` | 末尾追加一行“另有 N 条告警中”，tone 取未显示部分的最高级别（`by_severity` 减去已显示的） | — |

**账号行的通用规则**（错误、过载、受限三类）：行归入哪一类看 D02 的 `state`（服务端判定）；状态词、色调、倒计时、“已停止调度”标记和原因短句一律取 20 §0.2 的 `AccountDisplayState`（与 D02 判定顺序一致，可直接互用，20 §10.1），本章不另做推导、不另设 `error_kind` 词表。这样同一个账号在首页和账号页显示的原因相同。

**错误账号行**（来源 `availability.accounts` 中 `state == "error"`，`error_at` / `error_summary` 补自 `admin/accounts?status=error&lite=1`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | critical；八角形 | — | — |
| 标题 | `name` | 原样 | — |
| 徽章 | — | “错误” | — |
| 原因（最多 2 行） | `AccountDisplayState` 的原因短句：`error_summary`（≤ 160 字，已脱敏） | 原样 | `error_summary` 为空或没有 C02 字段：“上游返回异常”；**不显示 `error_message` 原文**（20 §0.2） |
| 底行左 | 平台显示名 + `error_at` 相对时间 | “OpenAI · 1 分钟前” | `error_at` 为 null（存量错误）或没有 C02 字段：只写平台 |
| 底行右 | 「测试」小按钮（视觉 30pt，`.frame(minHeight: 44)` + `.contentShape`，List 内 `.buttonStyle(.borderless)`） | — | — |

**过载账号行**（`state == "overloaded"`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | critical；火焰 | — | — |
| 标题 | `name` | — | — |
| 徽章 | “过载中” + 倒计时 `overload_until − now` | “过载中 1:12” | 倒计时 ≤ 0 显示 `0:00`，按 20 §0.2 重新推导并触发一次刷新 |
| 说明行 | “已停止调度”标记（`stopped == true`）+ 原因短句 + 平台 | “已停止调度 · 上游 529 · 智谱 GLM” | 原因短句固定“上游 529”（过载只来自 `handle529`，见 1.2），不需要额外请求 |

**受限行**（`state ∈ {rate_limited, temp_unschedulable}` 合并为一行）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | caution；沙漏 | — | — |
| 标题 | 账号数 | “受限 N 个账号” | — |
| 右侧 | 最早解除：`min(rate_limit_reset_at, temp_unschedulable_until) − now` | “最早 4:37” | — |
| 第 2 行 | 账号名用“、”连接，单行尾部截断 | — | — |
| 第 3 行（有 `stopped == true` 时） | “已停止调度 · ” + 这些账号名 | 标记在前，只截断名字 | 没有则不显示 |
| 截断提示 | `availability.accounts_truncated == true` | 第 2 行末尾“等”，标题数字改用 `totals.rate_limited + totals.temp_unschedulable` | — |

只有模型限流（`model_rate_limits`）而 `state == available` 的账号不进队列（账号详情里显示）。

**可用不足分组行**（`availability.groups` 中 `group_status == "active"`、`shortage.is_short == true`，且组内 `error + overloaded + rate_limited + temp_unschedulable > 0`；合并为一行，见未决问题 Q1）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 | 任一分组 `available == 0` → critical，否则 caution | — | — |
| 标题 | 分组数 | “可用不足 N 个分组” | — |
| 第 2 行 | 每组 `group_name available/total`，按可用比例升序，“ · ”连接 | “企业专线 0/2 · 标准组 1/3” | — |

一个账号属于多个分组时会计入每个分组（D02），分组之间不相加。

**充值 / 退款待核对行**（本机 `pendingBalances`）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | caution；文档勾 | — | — |
| 标题 | `operation`：add “充值结果待核对”、subtract “退款结果待核对”、set “余额设置结果待核对” | — | — |
| 右侧金额 | `amount`（Decimal） | 金额 | — |
| 说明行 | 用户名（本机记录里保存的显示名）+ 提交时间相对值 | “周婷 · 2 小时前 · 未确认是否入账” | 需要 `PendingBalanceOperation` 增加 `createdAt`、`userDisplayName`（30 §3.7） |

**兑换码生成待核对行**（60 §11.2 的本机记录 `PendingRedeemBatch`，读 `count`、`total`、`createdAt`）：标题“兑换码生成结果待核对”；右侧合计金额（余额类才有，并发 / 订阅 / 邀请类 `total == nil` 不显示）；说明行“{count} 个 · {createdAt 相对时间} · 未确认是否生成”，如“20 个 · 5 分钟前 · 未确认是否生成”（已定首页 `v-today.jsx` `VtRedeemRow`；与 60 §11.3 横幅同用“生成”）。

##### 1.3.4 今日区（序号“贰”，meta “00:00 起”）

这一区只放今日口径的数，近 5 分钟的数（RPM、TPM、错误率、健康分）不放进来。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 图表标题 | — | “每小时实际扣费”，右侧图例“今天（实心柱）/ 昨天（虚线）” | — |
| 图表 | 今天：`hourly.today[].actual_cost` 按小时 0…当前小时画柱，当前小时柱高亮；昨天：`hourly.yesterday[]` 24 小时虚线；缺失小时按 0 | X 轴只标“0时 6时 12时 18时”与“现在”，无 Y 轴；`accessibilityLabel` “每小时实际扣费，今天与昨天对比” | hourly 不可用 → 图表区一行“每小时数据加载失败 · 重试”，下面三格照常 |
| 账号成本 | `stats.today_account_cost` | 金额 | `—` |
| 标准 | `stats.today_cost` | 金额 | `—` |
| 利润 | 同 6 格 | 金额 | `—` |
| Tokens | `stats.today_tokens`（含缓存） | 紧凑数 | `—` |
| 成功率 | 今日 overview 的 `sla`（今日 SLA 口径，与统计分析“今天”同一数） | 比例 → `98.3%` | 关监控 → `—`（附录 B L23，不能显示 100% 或 0） |
| 更多统计 | — | “更多统计”，右侧灰字“模型 · 用户 · 分组排行” | — |

三格只写“账号成本 / 标准 / 利润”文字标签，不画线条图例（图上没有这两条线）。

##### 1.3.5 运行区（序号“叁”，不写窗口）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 健康分 | `ops.health_score`（0–100） | 刻度条 + 数字 + 词：≥ 90 “良好”（ok）、≥ 60 “风险”（caution）、< 60 “异常”（critical） | ops disabled → 数字 `—`，词“运维监控未开启”；ops error / timeout → `—` + 重试 |
| 错误率 | 同 6 格 `rates.error_rate` | `0.9%` | `—` |
| 上游 429 | `rates.upstream_429_count` | 整数 | null → `—` |
| 529 | `rates.upstream_529_count` | 整数 | null → `—` |
| 渠道行 | `channels.healthy / warning / critical / unknown` | “可用 3 · 性能下降 1 · 不可用 1 · 未知 1”，计数为 0 的项不写；性能下降用 caution 字色、不可用用 critical 字色 | disabled → “渠道监控未开启”；error / timeout → “渠道状态加载失败” |

#### 1.4 交互与写操作

本页本身只有导航与「测试」入口，没有直接写操作：

- 「测试」：打开 20 §4 的测试连接 sheet（`.accountTest(id:)`）；sheet 结束（无论成败）后对首页做一次 `nocache=1` 刷新（测试通过时后端会自动恢复账号状态）。
- 运维监控「开启」：§7.2。
- 告警的手动解决 / 静默只在告警详情与监控 · 告警段里做（§7.1）。
- 不做乐观更新；其他页面完成写操作后通过 `LiveOpsStore` 通知首页刷新（手动解决后告警行立即消失：先本地把该事件状态置为 `manual_resolved`，再后台刷新校正）。

#### 1.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 6 格显示占位骨架（不是 0）；待处理区显示“正在加载…” | — |
| home 整体失败（网络 / 5xx / 超时） | 各区块显示上次成功的值（如有）+ 副标题“部分数据未更新”；完全没有数据时整页空态“无法连接到站点” + 「重试」 | 自动在下一个轮询周期重试；连续失败的退避按 00 §4.6；超时按 00 §2.3 的 `dashboard/home` 一行 |
| 某段 `status == timeout`（`SECTION_TIMEOUT`） | 该区块保留旧值或 `—`，标题旁“加载超时” | 下次轮询自动重试（带 error / timeout 段的响应不进服务端缓存） |
| 某段 `status == error` | 同上，文案“加载失败”；reason 为 `INTERNAL_ERROR`、`SERVICE_UNAVAILABLE`、`OPS_REPO_UNAVAILABLE` 等时不显示原文 | 区块内「重试」= 整个 home 带 `nocache=1` 重拉 |
| `ops` / `alerts` 段 `disabled / OPS_DISABLED` | 1.3.1 的运维监控未开启行；健康分 `—`；告警行不出现 | §7.2 |
| `channels` 段 `disabled / CHANNEL_MONITOR_DISABLED` | 渠道行“渠道监控未开启”（不可点） | — |
| `availability` 不可用 | 待处理区内一行 neutral “账号状态读取失败 · 重试”；**不进入平静布局** | 重试 |
| `alerts` error / timeout（运维开启） | 待处理区内一行 neutral “告警读取失败 · 重试”；不进入平静布局 | 重试 |
| 400 `INVALID_TIMEZONE` | 不传 `timezone` 立即重试一次，并记录日志 | — |
| 400 `INVALID_INCLUDE` | 程序错误：去掉 `include` 重试 | — |
| 401 / 403 / 423 等鉴权类 | 按 00 §2.4、§2.6、§2.7 与 §3.2 处理 | — |
| 403 `ACCESS_TOKEN_READ_ONLY` | 本页只读，不会出现 | — |

#### 1.6 刷新策略

通用节奏（只在前台、各区块独立定时、回到前台立即刷新、失败退避、离开即取消）按 00 §4.6，下面只写本页的取值与特有规则。

- 前台轮询 **60 秒**（00 §4.6 的默认值，DECISIONS：约 60 秒），条件 = 本 Tab 可见且 `scenePhase == .active`；离开 Tab 或进后台立即取消在途请求（沿用现有 `cancelLoads()` 做法）。
- 倒计时每秒走：用 `TimelineView(.periodic(from: .now, by: 1))` 只重绘倒计时文本，不重拉数据；任一倒计时归零时 10 秒内最多触发一次 home 刷新。
- 下拉刷新：`dashboard/home?…&nocache=1`（后端 `nocache` / `force_refresh` 绕过 15 秒缓存，并透传给渠道监控的 refresh），同时重拉附加请求。
- ETag：按 0.2 末段与 00 §4.2，由 `ConditionalCache` 透明处理（轮询和下拉刷新都一样，不受 `lists.etag` 约束）；304 时页面照常拿到数据，“更新于”刷新为现在。服务端 ETag 排除了 `generated_at`、rates / ops 的起止时间、`availability.collected_at`，但 rates 每 5 秒在变，有流量时 304 少见，属正常。
- 本页没有 `since_id`（不是日志列表）。
- 附加请求：今日成功率随 home 每 60 秒；错误账号结构化字段只在错误账号集合变化时重拉。

#### 1.7 对现有代码的改动点

| 位置 | 改法 |
|---|---|
| `NativeApp/Features/DashboardView.swift` · `DashboardView` | 整体替换为新的 `HomeView`：6 格 + 待处理 + 今日 + 运行；平静布局切换见 §2。现有“今日请求 / 今日 Tokens / 总 Tokens / 性能指标”四卡、“运行健康”“运行监控”两个 GroupBox 删除；三个 30 秒轮询 `.task` 合成一个 60 秒轮询 |
| 同文件 · `DashboardTrendChart` | 首页不再放可缩放的大趋势图（DECISIONS：首页不全部显示，二级页显示全部），整体移到统计分析（40 §1）复用；首页换成不可交互的小图 `HomeHourlyChart`（Swift Charts：`BarMark` 今天 + `LineMark` 虚线昨天） |
| 同文件 · `DashboardLoadState` | 保留并挪到 `NativeApp/Views/LoadState.swift`，内部存 `BlockState` |
| 同文件 · `costBreakdown` / `costValue` / `needsCostSnapshot` | 首页不再按绿 / 黄着色金额（计费数字不着色）；“账号成本缺失时取 snapshot-v2”的逻辑移到 `LiveOpsStore` 的 stats 退路里 |
| 同文件 · `performanceCard` | 删除；RPM / TPM 进 6 格，读 `rates` |
| `Sources/Sub2Core/APIClient.swift` · `dashboard()` | 保留作退路；新增 `dashboardHome(timezone:include:noCache:) -> DashboardHome`（ETag / 304 由 `ConditionalCache` 透明处理，0.2 末段） |
| 同文件 · `dashboardTrend()` | `dateRange(days:)` 用的是 `TimeZone.current`，改为接收服务器时区（今日 / 昨日按服务器天界） |
| 同文件 · `dashboardMonitoring()`、`OpsReply`、`Models.swift` · `OpsSnapshot` | 删除，换成 `opsOverview(timeRange:)` / `opsOverview(start:end:)` 返回完整 `OpsOverview`（§4 也用） |
| 同文件 · `request(_:…)` | 条件请求按 00 §9.1（`makeRequest` 带 `If-None-Match`）与 §9.7（`Sources/Sub2Core/ConditionalCache.swift`）统一实现；本章各方法直接返回模型，不另定义 `Conditional<T>` / `.notModified` |
| 同文件 · 新增 | `dashboardRates(window:)`、`accountStatusSummary(includeAccounts:groupID:)`、`errorAccounts()`（`accounts?status=error&lite=1&page_size=100`）、`accountsRanking(limit:timezone:)` |
| 新文件 `Sources/Sub2Core/DashboardHome.swift` | `DashboardHome`、`HomeSection<T>`（`status` 不认识的值按 error 处理）、`HomeStats`、`LiveRates`、`HomeHourly`、`HomeOps`、`HomeAlerts`、`HomeAvailability`、`HomeChannels`；金额字段用 Decimal 解码（沿用 `KeyedDecodingContainer.optionalDecimal`） |
| 新文件 `Sources/Sub2Core/AccountStatusSummary.swift` | `AccountStateCounts`、`AccountStatusGroupSummary`（含 `Shortage`）、`AccountStatusItem`；与 20 §10.3 是同一个文件 |
| 复用 `Sources/Sub2Core/AccountDisplayState.swift`（20 §0.2 新增） | 账号行的状态词、色调、倒计时、“已停止调度”、原因短句都调它；本章不新增账号状态推导或 `error_kind` 词表 |
| 新文件 `Sources/Sub2Core/HomePresentation.swift` | 纯函数：`tickerCells(stats:rates:)`、`attentionItems(…) -> [AttentionItem]`（1.3.3 的顺序与合并规则；账号行文案取 `AccountDisplayState`）、`isCalm(…)`（§2.2）、`yesterdayChange(…)`；全部可单测 |
| `Sources/Sub2Core/DashboardPresentation.swift` | 新增 0.4 的格式函数；`rpmValue` / `performanceWindow` 不再被首页使用（统计分析若不用可删） |
| `NativeApp/Session/AppModel.swift` | 新增上述接口的包装与 UI 测试分支；新增 `LiveOpsStore` 的创建（随 `sessionGeneration` 重建） |
| `NativeApp/Session/DemoData.swift` | UI 测试数据：home 全 ok、ops disabled、availability error、hourly timeout、calm、calm + 限流 |
| 新视图文件（建议） | `NativeApp/Features/Home/HomeView.swift`、`HomeTicker.swift`、`HomeAttentionList.swift`、`HomeTodaySection.swift`、`HomeRunSection.swift`、`HomeHourlyChart.swift`、`OpsDisabledNotice.swift`（§7.2 共用） |
| 测试 | `Tests/Sub2CoreTests/HomePresentationTests.swift`（6 格、`—`、利润为负、涨跌、TPM 退路标记）、`DashboardHomeDecodingTests.swift`（部分成功、未知 status、缺段）、`AttentionItemsTests.swift`（顺序、合并、截断、stopped 第 3 行；错误行原因为空时“上游返回异常”、过载行原因“上游 529”，与 `AccountDisplayState` 输出一致）；现有 `DashboardRPMTests`、`OverviewPresentationTests` 随 `performanceCard` 删除而更新 |

---

### 2. 概览 Tab · 平静布局

#### 2.1 入口与导航

- 与 §1 同一个页面、同一个数据；满足 2.2 的条件时整屏换成平静布局（`withAnimation(.easeInOut)` 交叉淡入），条件不满足时换回常规布局。
- 导航栏同 §1.1。去向：6 格同 §1；“自动恢复中”行 → `router.select(.accounts(filter: .limited))`；“按账号”行 → 账号详情 `.account(id:)`；“更多统计” → `.analytics()`；渠道行 → `router.select(.monitor(segment: .channels))`。

#### 2.2 进入条件（全部满足才进入）

1. `availability` 段 ok（读不到账号状态时不进入）；
2. `totals.error == 0` 且 `totals.overloaded == 0`；
3. 告警：`alerts` 段 ok 且 `firing_count == 0`（被静默的 firing 也算，仍需手动解决），或 `alerts` 段 `disabled / OPS_DISABLED`（运维监控关闭时不阻止平静布局，但页面显示 1.3.1 的运维监控未开启行）；
4. 没有本机的充值 / 退款待核对与兑换码生成待核对；
5. 没有 1.3.3 的“可用不足分组”行。

限流中、临时不可调度（自动恢复类）不阻止平静布局，只加一行“自动恢复中”（DECISIONS 第 2 轮 Q4）。

#### 2.3 数据来源

同 §1.2，另加：

- 按账号前 4：`GET /api/v1/admin/dashboard/accounts-ranking?limit=4&timezone=<server_timezone>`（`dashboard.accounts_ranking`；默认今天）→ `ranking[]` 每项 `account_id`、`account_name`、`platform`、`requests`、`actual_cost`；只在平静布局显示时请求。

#### 2.4 字段 → 显示映射（自上而下）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态旗 | 有受限账号 → “无需处理”，否则 “全部正常”；后接 `totals.available` | “✓ 全部正常 · 15 个账号可调度”（ok 色） | — |
| 6 格 | 同 1.3.2 | 同 | 同 |
| 运维监控未开启行 | 同 1.3.1 | 同 | — |
| “自动恢复中”区（meta “N 个”） | 有受限账号时显示，内容 = 1.3.3 的受限行（含“已停止调度”第 3 行） | 同 | 没有受限账号不显示 |
| “每小时实际扣费”区（序号“壹”，meta “00:00 起”） | 同 1.3.4 的图表，但今天画**折线 + 面积**、当前点圆点，昨天虚线（设计稿 `VtStage`：ticker 方案下用折线） | 同 | 同 |
| 三格 | 账号成本 / 标准 / 利润，同 1.3.4 | 同 | 同 |
| 用量行 | Tokens、成功率（今日 SLA），同 1.3.4 | 同 | 同 |
| “按账号”区（序号“贰”，meta “今日实际扣费 · 前 4”） | `ranking[]` 前 4，只取 `actual_cost > 0` 的 | 每行：账号名 + 右侧金额；下方比例条（宽度 = 本行 ÷ 第一行）；说明“{平台} · {requests 千分位} 次请求” | 接口不可用或没有 > 0 的项：整区隐藏 |
| 更多统计行 | — | 同 1.3.4 | — |
| “渠道”区（序号“叁”） | `channels.total` 与四档计数 | 标题“8 个渠道”，说明同 1.3.5 渠道行 | disabled → “渠道监控未开启” |

平静布局没有“运行”区与健康分（健康分只在常规布局的运行区与监控 · 概况）。

#### 2.5 交互与写操作

无写操作。

#### 2.6 状态

同 §1.5；ranking 失败只影响“按账号”区（隐藏），不改变布局。

#### 2.7 刷新策略

同 §1.6；ranking 随 home 每 60 秒刷新（仅平静布局可见时）。

#### 2.8 对现有代码的改动点

新增 `NativeApp/Features/Home/HomeCalmView.swift`（状态旗、自动恢复中、折线小图、按账号排行）；`HomePresentation.isCalm(...)` 实现 2.2，单测覆盖：只有限流 → 平静；有静默中的 firing → 不平静；运维关闭 + 无异常 → 平静；availability 失败 → 不平静；有本机待核对 → 不平静。

---

### 3. 告警详情页

#### 3.1 入口与导航

- 入口：首页告警行；监控 · 告警段的每一行；推送“告警触发”点按（00 §7.5，§0.7-4）。路由 `.alert(id:)`，推入当前 Tab 的导航栈（§0.7-2）。
- 导航栏：返回 + 标题“告警”，副标题 “{severity} · {范围文案}”（如“P1 · 分组 · 标准组”）。
- 去向：范围区的分组行 → 分组详情 `.group(id:)`（50 §2、§8）；错误请求行 → 使用记录 `.logs(scope: .errors / .upstream, group: id)`（40 §6）；平台渠道行 → `router.select(.monitor(segment: .channels))`；服务器行 → `router.select(.monitor(segment: .overview))`。

#### 3.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 事件 | `GET /api/v1/admin/ops/alert-events/:id` | 进入时先用列表里带来的事件对象渲染，再用本请求校正；字段 `id`、`rule_id`、`severity`、`status`、`title`、`metric_value`、`threshold_value`、`dimensions{platform?, group_id?}`、`fired_at`、`resolved_at`、`silence{id, until}`、`rule{id, name, metric_type, operator, threshold, window_minutes, sustained_minutes, deleted}`、`group_name`、`resolved_by_user_name` |
| 规则摘要（旧服务端） | `GET /api/v1/admin/ops/alert-rules` | 没有 `ops.alert_event_details` 时按 `rule_id` 匹配；规则已删 → 显示 `description` 原文 |
| 分组范围 | `LiveOpsStore` 里的 `availability.groups` 中 `group_id` 那一项；没有时 `GET /api/v1/admin/accounts/status-summary?group_id=<id>` | 不受运维开关影响 |
| 错误请求条数 | `GET /api/v1/admin/ops/request-errors?group_id=<id>&time_range=24h&page_size=1` → `total`（`metric_type` 为 `error_rate` / `success_rate`）；`upstream_error_rate` 用 `GET /api/v1/admin/ops/upstream-errors?group_id=<id>&time_range=24h&page_size=1` | 只在事件有 `group_id` 时 |
| 平台范围 | `LiveOpsStore` 的渠道列表（§5）里 `platform` 相同（忽略大小写）的项；没有缓存时 `GET /api/v1/admin/channel-monitor-v2/overview?range=90m` | 只在事件有 `platform`、没有 `group_id` 时 |

全部需要运维监控开启（事件接口受开关控制）。

#### 3.3 字段 → 显示映射

**状态卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 状态卡胶囊 | firing → `alertTone`；否则无色 | — | — |
| 大徽章 | `status` | firing “告警中”、resolved “已恢复”、manual_resolved “已手动解决” | 未知值：原样 |
| 徽章右侧 | `severity` + `fired_at` 时刻 | “P1 · 09:29 触发” | — |
| 规则名 | `rule.name` | 原样 | `rule` 为 null：`title` 去掉 `P1: ` 前缀 |
| 大数字 | `metric_value`（§6.3 单位） | “5.2%” | 缺失 `—` |
| 大数字旁 | “阈值 {rule.threshold ?? threshold_value}” + `rule.window_minutes > 0` 时“ · 近 {N} 分钟” | “阈值 5% · 近 5 分钟”（规则自己的窗口，保留，BACKLOG 末条） | 两个阈值字段都缺失时不写“阈值”；`rule` 为 null 时不写窗口 |
| 静默说明（firing 且 `silence != null`） | `silence.until` | “⌛ 已静默至 10:41”（跨天写“明天 09:41” / “10月23日 09:41”） | — |
| 结束说明（非 firing） | resolved：`resolved_at` → “1 小时前恢复”；manual_resolved：“{resolved_at} · 由 {resolved_by_user_name} 手动解决” | 例：“昨天 22:10 · 由 admin 手动解决” | 没有解决人：“已手动解决” |

**按钮行**（只在 `status == firing` 时显示）：「手动解决」（主）、「静默…」（`silence == null`）/「改静默时长…」（`silence != null`）。旧服务端且事件没有 `platform` 时隐藏静默按钮（§7.1）。

**范围区**（序号“壹”）

| 事件维度 | 行 | 内容 |
|---|---|---|
| 有 `group_id` | 分组行（可点） | 标题 `group_name`；右侧“{available}/{total} 可用”；说明“{分组平台} · N 个账号受影响”（N = error + overloaded + rate_limited + temp_unschedulable），N = 0 写“账号都可调度” |
| 有 `group_id` 且指标是错误类 | 错误请求行（可点） | 标题“错误请求”（`upstream_error_rate` 为“上游错误”）；右侧“近 24 小时 N 条” |
| 只有 `platform` | 渠道行（可点） | 标题“{platform 显示名} 渠道”；右侧该平台渠道中最差状态的词（可用 / 性能下降 / 不可用 / 未知，非可用着色）；说明“N 个分组渠道 · 最低可用率 x%” | 
| 都没有，且指标是 `cpu_usage_percent` / `memory_usage_percent` / `concurrency_queue_depth` | 服务器行 | 标题“服务器”，右侧灰字“监控 · 概况” |
| 都没有，其他指标（全站规则） | 全站行 | 标题“全站”，右侧灰字“监控 · 概况”；错误类指标再加一行“错误请求 · 近 24 小时 N 条”（不带分组筛选） |

找不到该平台的渠道：说明写“没有这个平台的渠道探测”。分组已删除（`group_name` 仍有，availability 里没有）：右侧写“分组已删除”，不可点。

**规则区**（序号“贰”，键值表）

| 键 | 值 | 空值 |
|---|---|---|
| 条件 | “{指标名} {运算符} {阈值}”，阈值 = `rule.threshold ?? threshold_value`，如“错误率 > 5%” | 规则缺失（没有运算符）→ `description` 原文 |
| 窗口 | “{window_minutes} 分钟” | 0 或缺失 → `—` |
| 级别 | `severity` | — |
| 触发 | “今天 09:29” | — |
| 结束（非 firing） | `resolved_at` 同格式 | `—` |

`rule.deleted == true` 时条件行后加“（规则已删除）”；指标不认识或是 p95 / p99 且缺 `ops.alert_latency_metrics` 时条件行后加“（不受支持，不会触发）”。

#### 3.4 交互与写操作

见 §7.1（手动解决、静默、改时长、结束静默）。成功后：本页用返回结果 / 重新 GET 刷新；`LiveOpsStore` 同步更新告警列表、计数与首页（手动解决后首页告警行立即消失）。

#### 3.5 状态

| 情况 | 显示 |
|---|---|
| 加载中（没有列表带来的对象） | 状态卡骨架 |
| 404 `OPS_ALERT_EVENT_NOT_FOUND` | 空态“这条告警不存在或已被清理” + 「返回」 |
| 404 `OPS_DISABLED` | 空态“运维监控未开启” + §7.2 的开启入口 |
| 范围区子请求失败 | 只该行显示“加载失败 · 重试”，状态卡与规则区照常 |
| 400 `Invalid event ID` | 程序错误，返回上一页 |

#### 3.6 刷新策略

进入时拉一次；可见时 60 秒轮询事件；下拉刷新重拉事件与范围数据；写操作成功后立即重拉。

#### 3.7 对现有代码的改动点

现有 App 没有告警页。新增 `NativeApp/Features/Monitor/AlertDetailView.swift`；模型与文案放 `Sources/Sub2Core/OpsAlerts.swift`（`AlertEvent`、`AlertEventRule`、`AlertSilenceRef`、`AlertCounts`、`AlertSilence`）与 `Sources/Sub2Core/AlertPresentation.swift`（§6.3 的单位、运算符、范围、标题、since 文案）；`APIClient` 新增 `alertEvent(id:)`、`alertRules()`、`requestErrorCount(groupID:range:)`、`upstreamErrorCount(groupID:range:)`。解码注意：`silence` 键存在与否要区分（用 `container.contains(.silence)` 记一个 `silenceSupported` 标记）；`AlertEvent` 保留顶层 `thresholdValue`（`threshold_value`），`AlertEventRule` 保留 `threshold`，显示统一走 `AlertPresentation.threshold(event) = rule?.threshold ?? thresholdValue`。

---

### 4. 监控 Tab · 概况

#### 4.1 入口与导航

- 入口：底部 Tab 第 4 个「监控」；分段控件“概况 / 渠道 / 告警”（DECISIONS 第 2 轮）。默认段 = 概况（见未决问题 Q4），本次会话内记住上次所选段；从首页“渠道”行 / “另有 N 条告警”进入时由 `router.select(.monitor(segment:))` 指定段（§0.7-4）。
- 导航栏：大标题“监控”，副标题随段变化：概况“运行与服务器 · 刚刚更新”、渠道“渠道 · 近 90 分钟 · 刚刚更新”、告警“告警 · N 条进行中”。右上 `···`：「刷新」；站长且运维开启时再加「关闭运维监控…」（§7.2，见未决问题 Q6）。
- 分段计数：渠道段 = 渠道列表里 critical + warning 的数量（0 不显示）；告警段 = 告警中条数（0 不显示）。
- 去向：“告警中 N 条”行 → 本页切到告警段（不走 router）。

#### 4.2 数据来源

全部受运维监控开关控制（404 `OPS_DISABLED`）。

| 区块 | 请求 | 用到的字段 |
|---|---|---|
| 运行 | `GET /api/v1/admin/ops/dashboard/overview?time_range=5m` | `health_score`、`error_rate`、`upstream_429_count`、`upstream_529_count`、`sla`、`qps.current`、`system_metrics`、`job_heartbeats[]` |
| 错误率小折线 | `GET /api/v1/admin/ops/dashboard/snapshot-v2?start_time=<now−45m>&end_time=<now>&mode=raw` | `throughput_trend.points[]{bucket_start, request_count}`、`error_trend.points[]{bucket_start, error_count_sla, business_limited_count}`（附录 A S16） |
| 告警摘要 | `LiveOpsStore` 的告警列表（§6.2）与计数 | firing 条数与标题 |
| 服务器 · 并发 | `GET /api/v1/admin/ops/concurrency` | `enabled`；`platform{<平台>: {current_in_use, max_capacity, waiting_in_queue}}`（平台级可相加，分组级不能） |
| 服务器 · CPU / 内存历史 | `GET /api/v1/admin/ops/system-metrics/history?time_range=1h&max_points=60`（`ops.system_metrics_history`） | `points[]{created_at, cpu_usage_percent, memory_usage_percent}`；无数据为 `[]` |
| 服务器 · 日志采集 | `GET /api/v1/admin/ops/system-logs/health` | `avg_write_delay_ms`、`queue_depth`、`last_error`、`write_failed_count`、`dropped_count` |
| 服务器 · 入口拒绝 | `GET /api/v1/admin/ops/ingress-rejections?time_range=1h&page_size=1`（`ops.ingress_reject_totals`） | `request_count_total`、`by_reason[]{reason, request_count}` |

服务器区的 4 个请求只在站长判定（0.1）通过时发。

#### 4.3 字段 → 显示映射

**运行区**（序号“壹”，不写窗口）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 健康分 | `health_score` | 同 1.3.5 | `—` |
| 错误率 | `error_rate` | 比例 → `%` | `—` |
| 上游 429 / 529 | `upstream_429_count` / `upstream_529_count` | 整数 | `—` |
| 小折线 | 把 45 个 1 分钟桶按 `bucket_start` 对齐、合并成 9 个 5 分钟点：每点 = Σ`error_count_sla` ÷ Σ(`request_count` − `business_limited_count`)；分母为 0 的点留空（断线） | 标签“错误率 · 近 45 分钟”；面积折线，无坐标轴 | 请求失败：小折线位置一行“趋势加载失败” |
| 告警中行 | firing 条数；标题列表 | “告警中 N 条”；说明 = 各条标题用“、”连接（可换行）；有 firing 时 caution 胶囊 | 0 条：“告警中 0 条”，说明“没有告警”，无胶囊 |

**服务器区**（序号“贰”，meta “仅管理员可见”；只在站长判定通过时显示）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| CPU 表 | 当前值 `system_metrics.cpu_usage_percent`；小折线 = history 的 `cpu_usage_percent`（null 断线，Y 轴 0–100） | “CPU 38%”；容量条 ≥ 90 critical、≥ 75 caution | 当前值 null → `—`；没有 history 能力：本机在前台每次轮询追加一个点（最多 60 个，切站点清空） |
| 内存表 | `memory_usage_percent`，同上 | “内存 61%” | 同上 |
| 并发 | Σ`platform[*].current_in_use` / Σ`max_capacity` | “并发 8/50” | `enabled == false`（实时监控关闭）→ `—` |
| 排队 | Σ`platform[*].waiting_in_queue` | 整数 | `enabled == false` 时改用 `system_metrics.concurrency_queue_depth`；都没有 → `—` |
| QPS | `qps.current`（后端已保留 1 位小数） | “0.8” | `—` |
| SLA | `sla` | 比例 → `99.2%` | `—` |
| 任务行（每个心跳一行） | 见下表 | — | 列表为空：一行“还没有后台任务心跳” |
| 日志采集行 | 状态：`last_error` 为空 → 正常图标，否则 error 图标；右侧 `avg_write_delay_ms` | “日志采集”，右侧“延迟 2 秒”（< 1000 写“850 ms”） | 请求失败 → 右侧 `—` |
| 日志采集行说明 | `request_count_total` + 需留意的任务数 | “入口拒绝 3 次（1 小时）· 1 个任务需留意” | 入口拒绝失败 → “入口拒绝 —”；没有需留意的任务不写后半句 |

**任务行**（`job_heartbeats[]`；不要假设固定 6 项，从未运行过的任务不在列表里）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 名称 | `job_name` 映射：`ops_metrics_collector` 指标采集、`ops_alert_evaluator` 告警评估、`ops_preaggregation_hourly` 预聚合（小时）、`ops_preaggregation_daily` 预聚合（天）、`ops_cleanup` 清理、`ops_scheduled_reports` 定时报告 | 排序同此顺序，未知任务按名字排在后面、显示原始 `job_name` | — |
| 图标 / 胶囊 | `status`：ok → 正常；failing / stale → caution；disabled / unknown → 无色 | — | 不认识的 status 按 unknown（D08 进度备注） |
| 右侧 | ok：`last_success_at` 相对时间；failing / stale：“最近成功 {相对时间}”（caution 字色）；disabled：“已关闭”；unknown：“—” | “4 分钟前”、“今天 03:00” | `last_success_at` 为 null：“从未成功” |
| 说明行 | failing：“最近一次失败：{last_error}”（截 1 行）；stale：“超过 {2 × expected_interval_seconds 换算} 没有成功，需要看一下”；cron 任务（`ops_cleanup`）stale：“按计划应在 {next_expected_at} 前完成” | — | 其他状态不显示说明 |

没有 `ops.job_heartbeat_status`（旧服务端）时本地判定：`last_error_at` 晚于 `last_success_at` → failing；指标采集、告警评估超过 3 分钟没成功 → stale；预聚合（小时）超过 30 分钟、预聚合（天）超过 3 小时没成功 → stale；清理、定时报告只看 failing。

“需留意的任务数” = status 为 failing 或 stale 的个数。

#### 4.4 交互与写操作

- 本段只读；运维关闭时的开启见 §7.2。
- 任务行、日志采集行不可点（设计稿没有下钻）。入口拒绝的原因明细（`by_reason`）不在本版显示（见未决问题 Q5）。

#### 4.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 404 `OPS_DISABLED`（任一请求） | 整段替换为 §7.2 的“运维监控未开启”空态 | 开启 |
| overview 失败 | 运行区数字 `—` + “加载失败 · 重试”；服务器区的 CPU / 内存当前值、QPS、SLA、任务行同样 `—` | 重试 |
| 单个服务器子请求失败 | 只影响对应行 | 行内重试 |
| 400 `INVALID_MAX_POINTS` / `OPS_TIME_RANGE_TOO_LARGE` | 程序错误：改回 `time_range=1h&max_points=60` 重试一次 | — |
| 实时监控关闭（concurrency `enabled == false`） | 并发 `—`，并发数字旁小字“实时监控未开启”（与“运维监控未开启”不要判反，附录 A S7） | — |
| 加载中 | 骨架 | — |

#### 4.6 刷新策略

本段可见时 60 秒轮询（overview、snapshot-v2、concurrency、history、logs health、ingress 并发）；下拉刷新全部重拉；离开段或进后台取消；退避与回到前台按 00 §4.6。overview / throughput 服务端按 5 秒取整缓存，snapshot-v2 30 秒缓存。ETag：只有 `ops/dashboard/snapshot-v2` 发 ETag（`ops_snapshot_v2_handler.go:67-70`），由 `ConditionalCache` 透明处理（0.2 末段）；因为 `end_time` 每次都是“现在”、缓存键不同，基本不会命中，属正常；其余 5 个接口没有 ETag。

#### 4.7 对现有代码的改动点

| 位置 | 改法 |
|---|---|
| `NativeApp/Sub2MobileApp.swift` · `MainTabs` | 按 §0.7-1/-2 改为 `TabView(selection: $router.selectedTab)`：概览 Tab 根换成 `HomeView`，新增监控 Tab（根 `MonitorView`，每个 Tab 一个 `NavigationStack(path:)`），Tab 栏上方叠加回执（§0.7-6）。去掉“管理”“设置”两个 Tab、新增搜索 Tab 见 60 §1.7；完整骨架待骨架章节（Q10） |
| 新文件 `NativeApp/Features/Monitor/MonitorView.swift` | 分段容器 + 三段视图 + 副标题 |
| 新文件 `NativeApp/Features/Monitor/MonitorOverviewSection.swift`、`MonitorServerSection.swift` | 运行区、服务器区 |
| 新文件 `Sources/Sub2Core/OpsMonitoring.swift` | `OpsOverview`（含 `OpsSystemMetricsSnapshot`、`OpsJobHeartbeat`、`OpsRateSummary`）、`OpsSnapshotV2`（overview + throughput_trend + error_trend）、`OpsConcurrency`、`SystemMetricsHistory`、`SystemLogHealth`、`IngressRejectList`、`OpsMonitoringStatus` |
| 新文件 `Sources/Sub2Core/MonitorPresentation.swift` | 任务名映射、心跳文案、本地兜底判定、5 分钟合并的错误率序列；单测覆盖 |
| `APIClient` 新增 | `opsSnapshotV2(start:end:)`、`opsConcurrency()`、`systemMetricsHistory(timeRange:maxPoints:)`、`systemLogsHealth()`、`ingressRejections(timeRange:)` |
| 复用 | 现有 Swift Charts 用法（`PerformanceTrendView` 的 `LineMark`）可用于小折线 |

---

### 5. 监控 Tab · 渠道

#### 5.1 入口与导航

- 入口：监控 Tab 分段“渠道”；首页运行区 / 平静布局的渠道行；告警详情的平台渠道行。
- 去向：渠道行 → 分组详情 `.group(id: group_id)`（50 §2；设计稿行带箭头但没有目的页，见未决问题 Q3）。

#### 5.2 数据来源

`GET /api/v1/admin/channel-monitor-v2/overview?range=90m`（只挂功能开关，V1 / V2 模式都能用；不受运维开关影响；必须显式传 `range`）

- 顶层：`refresh_interval_seconds`、`coverage{state, collector_state, …}`、`items[]`。
- 每项（一个分组的渠道）：`platform`、`group_id`、`group_name`、`current_status{state, reason, updated_at}`（state：healthy / warning / critical / unknown / stale）、`metrics{reliability_rate, success_rate, request_count, channel_errors, success_requests, sample_state, ttft{p50_ms}}`、`buckets[]`（90 分钟 × 5 分钟一桶，每桶 `bucket_start`、`health{reliability}`、`metrics{…}`）。

渠道监控关闭：403 `CHANNEL_MONITOR_DISABLED`；`/admin/me` 的 `features.channel_monitor_enabled == false` 时直接显示关闭态、不发请求。

#### 5.3 字段 → 显示映射

**顶部四格**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 可用 | `current_status.state == healthy` 的项数 | 大数字 + “可用”（ok 色） | 加载失败 `—` |
| 性能下降 | `warning` | “性能下降”（caution） | `—` |
| 不可用 | `critical` | “不可用”（critical） | `—` |
| 未知 | `unknown` + `stale` + 其他值 | “未知”（neutral） | `—` |

**渠道区**（标题“渠道”，meta “可用率 · 首字”，序号“壹”）。排序：不可用 → 性能下降 → 未知 → 可用；同档按 `group_name`。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 / 图标 | 状态映射：healthy ok、warning caution、critical critical、其余 neutral | — | — |
| 标题 | `group_name`，后接小字平台显示名 | “标准组  OpenAI” | `group_name` 为空写“分组 #{group_id}” |
| 右侧 | healthy：`metrics.reliability_rate` → “99.6%”；其他：徽章（性能下降 / 不可用 / 未知） | — | 可用率 null 写 `—` |
| 时间条 | 最近 18 个 `buckets[].health.reliability`：healthy 实心 ok、warning caution、critical critical、unknown 空格 | 18 格，不可点；`accessibilityHidden` | 桶数不足 18：左侧补空格 |
| 说明行 | 见右 | healthy / warning：“可用率 {reliability_rate} · 首字 {ttft.p50_ms 秒，1 位小数}”；critical：“错误率 {channel_errors ÷ (success_requests + channel_errors)} · 首字 …”；`sample_state == no_samples`：“无样本”；`insufficient`：“样本不足”；`current_status.reason == collection_unavailable`：“采集不可用”；`state == stale`：“数据已过期” | 首字 p50 为 null：“首字 —” |

**覆盖提示**：`coverage.collector_state != "healthy"` 或 `coverage.state == "stale"` 时，列表上方一行 neutral 提示“渠道数据采集延迟，显示的可能不是最新状态”。

#### 5.4 交互与写操作

只读。行点按见 5.1。

#### 5.5 状态

| 情况 | 显示 |
|---|---|
| 403 `CHANNEL_MONITOR_DISABLED` / features 关闭 | 空态“渠道监控未开启”，说明“可在 Web 后台的渠道监控设置中开启”（App 不提供开关） |
| `items` 为空 | 空态“还没有渠道数据” |
| 请求失败 | 有旧数据保留并标“更新失败”；没有旧数据：空态“渠道加载失败” + 「重试」 |
| 403 其他（vendor） | 0.1 的 vendor 占位 |

#### 5.6 刷新策略

可见时按 `refresh_interval_seconds` 轮询（限制在 30–300 秒，缺省 60）；下拉刷新带 `refresh=true`；离开段取消。结果写入 `LiveOpsStore`，供首页（退路）与告警详情的平台范围使用。

#### 5.7 对现有代码的改动点

新文件 `Sources/Sub2Core/ChannelMonitor.swift`（`ChannelOverview`、`ChannelItem`、`ChannelBucket`、`ChannelMetrics`、`ChannelLatency`），`NativeApp/Features/Monitor/ChannelsSection.swift`；`APIClient.channelOverview(range:refresh:)`。现有 App 无对应代码。

---

### 6. 监控 Tab · 告警

#### 6.1 入口与导航

- 入口：监控 Tab 分段“告警”；首页“另有 N 条告警中”行；概况段“告警中 N 条”行。
- 去向：行点按 → 告警详情 `.alert(id:)`（§3）。

#### 6.2 数据来源

| 用途 | 请求 |
|---|---|
| 告警中 | `GET /api/v1/admin/ops/alert-events?status=firing&limit=100` |
| 最近结束 | `GET /api/v1/admin/ops/alert-events?time_range=24h&limit=50`，客户端过滤 `status != firing` |
| 更早 | 最近结束区末尾「加载更早」：同一请求加 `before_fired_at=<最后一条 fired_at>&before_id=<最后一条 id>`（两者必须同时给） |
| 精确计数 | `GET /api/v1/admin/ops/alert-events/counts` → `firing`、`by_severity`（`ops.alert_event_counts`） |

列表按 `fired_at DESC, id DESC` 返回；limit 上限 500。事件字段同 §3.2。结果写入 `LiveOpsStore`。

#### 6.3 字段 → 显示映射

两个区：“告警中”（序号“壹”，meta “N 条”）、“最近结束”（序号“贰”，meta “N 条”）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 胶囊 | firing → `alertTone`；非 firing 无胶囊、整行降低强调 | — | — |
| 图标 | firing 铃铛；其他 勾选圆 | — | — |
| 标题 | 同首页告警行标题 | “标准组错误率 5.2%” | 同 |
| 徽章 | `severity` + 状态词 | “P1 · 告警中” / “P1 · 已恢复” / “P2 · 已手动解决” | — |
| 第 2 行（完整换行，不截断） | 范围文案 + “ · ” + 规则文案 | “分组 · 标准组 · 错误率 > 5%（5 分钟）” | 规则缺失：`description` 原文 |
| 静默行（firing 且 `silence != null`） | `silence.until` | “⌛ 已静默至 10:41” | — |
| 底行左 | since 文案 | firing：“12 分钟前”；resolved：“1 小时前恢复”；manual_resolved：“昨天 22:10 · 由 admin 手动解决” | — |
| 底行右（仅 firing） | 小按钮「静默…」/「改静默…」、「手动解决」（主） | 同首页小按钮尺寸规则 | — |
| 空区 | — | “没有告警” | — |

**通用文案函数（`AlertPresentation`，首页、详情、列表共用）**

- 范围：有 `group_id` → “分组 · {group_name}”；只有 `platform` → “平台 · {平台显示名}”；都没有且指标为服务器类（cpu / memory / queue）→ “服务器”；其他 → “全站”。
- 规则：“{指标名} {运算符} {阈值}” + `rule.window_minutes > 0` 时“（{N} 分钟）”；阈值 = `rule.threshold ?? threshold_value`（0.4），指标名与运算符来自 `rule`（旧服务端来自 `ops/alert-rules` 匹配，§3.2）；拿不到规则时整段用 `description` 原文。运算符显示：`>` `<` `>=`→`≥` `<=`→`≤` `==`→`=` `!=`→`≠`。
- 指标名与单位（与后端白名单 `handler/admin/ops_alerts_handler.go` 一致，百分比类数值已是百分数）：

| metric_type | 指标名 | 单位 |
|---|---|---|
| success_rate | 成功率 | % |
| error_rate | 错误率 | % |
| upstream_error_rate | 上游错误率 | % |
| p95_latency_ms | P95 延迟 | ms |
| p99_latency_ms | P99 延迟 | ms |
| cpu_usage_percent | CPU | % |
| memory_usage_percent | 内存 | % |
| concurrency_queue_depth | 排队 | 个 |
| group_available_accounts | 可用账号 | 个 |
| group_available_ratio | 可用比例 | % |
| group_rate_limit_ratio | 限流比例 | % |
| account_rate_limited_count | 限流账号 | 个 |
| account_error_count | 错误账号 | 个 |
| account_error_ratio | 错误账号比例 | % |
| account_temp_unscheduled_count | 临时不可调度账号 | 个 |
| overload_account_count | 过载账号 | 个 |
| proxy_expired_count | 已过期代理 | 个 |
| proxy_expiring_soon_count | 即将过期代理 | 个 |

  数值格式：% 类最多 2 位小数并去掉末尾 0（`5` → `5%`，`5.2` → `5.2%`）；ms 类整数加千分位（`2,000 ms`）；个数类整数。未知 `metric_type`：指标名用原值，数值保留 2 位小数，规则文案后加“（不受支持，不会触发）”；`p95_latency_ms` / `p99_latency_ms` 在没有 `ops.alert_latency_metrics` 时同样加这句（D07 退路）。

#### 6.4 交互与写操作

- 「手动解决」「静默…」「改静默…」：§7.1。
- 不提供“确认 / ack”（后端没有，BUILDER_GUIDE：告警只有手动解决和静默）。
- 告警规则的查看与编辑不在本版（Web 管理）。

#### 6.5 状态

| 情况 | 显示 |
|---|---|
| 404 `OPS_DISABLED` | §7.2 空态 |
| 加载失败 | 有旧数据保留并标“更新失败”；否则空态“告警加载失败” + 「重试」 |
| 两个区都为空 | 两个区各显示“没有告警” |
| 400 `before_fired_at and before_id must be provided together` | 程序错误：去掉游标重拉第一页 |

#### 6.6 刷新策略

可见时 60 秒轮询（两条列表 + 计数）；下拉刷新；写操作成功后立即重拉并更新 `LiveOpsStore`；不做 ETag / since_id（告警接口没有）。告警中条数（分段计数、首页、概况）在监控 Tab 不可见时由首页的 home 轮询更新。

#### 6.7 对现有代码的改动点

新文件 `NativeApp/Features/Monitor/AlertsSection.swift`、`AlertRow.swift`（首页告警行复用同一个行视图，参数控制是否显示按钮）；`APIClient.alertEvents(status:timeRange:limit:before:)`、`alertEventCounts()`。

---

### 7. 共用交互

#### 7.1 手动解决与静默（告警详情、监控 · 告警行内）

实现为一个共用的 `AlertActions`（`@MainActor`，持有 `LiveOpsStore` 与 `APIClient`），首页、监控、详情都调它，保证三处状态一致。下文的“回执”都用 §0.7-6 的 toast，“确认框 / 动作表”用 §0.7-8 的系统组件。

**手动解决**

1. 确认框：标题“手动解决这条告警？”，正文“「{标题}」会标记为已手动解决。条件仍满足时，规则会再次触发。”，按钮「手动解决」「取消」。
2. `PUT /api/v1/admin/ops/alert-events/:id/status`，body `{"status":"manual_resolved"}` → `{"updated": true}`。服务端记录解决人（当前登录管理员；Admin Key 记为第一个管理员）。
3. 成功：`LiveOpsStore` 本地把该事件置为 `manual_resolved`、`resolved_at = now`（首页告警行立即消失、监控列表移到“最近结束”），回执“已手动解决”（无撤销：后端没有重新打开的接口）；随后重拉列表与计数校正。
4. 失败：不改本地状态；回执写原因（见下表）。
5. 不需要 step-up；不带 Idempotency-Key（该接口不支持，重复 PUT 是同值写，安全）。超时：重新 GET 该事件，`status != firing` 视为成功。
6. 注意：对不存在的事件后端也返回 `updated: true`（BACKLOG D06），所以成功后必须重拉校正。

**静默 / 改静默时长 / 结束静默**

1. 确认框（动作表）：
   - 未静默：标题“静默这条规则多久？”，正文“静默期间，这条规则{在 <范围名>}不再产生新的告警事件。当前这条仍需手动解决。”，按钮「静默 1 小时」「静默 24 小时」「静默 7 天」「取消」（时长与 Web 一致）。
   - 已静默：标题“改静默时长”，正文首行“当前静默至 {until}”，按钮同上三个时长 + 「结束静默」（destructive）+「取消」。
2. 请求：
   - 新建：`POST /api/v1/admin/ops/alert-silences`，body `{"rule_id": <rule_id>, "platform": "<dimensions.platform 或空串>", "group_id": <dimensions.group_id 或 null>, "until": "<now + 时长，RFC3339 UTC>"}`（`region` 不传；`reason` 不传）→ 静默对象 `{id, rule_id, platform, group_id, until, …}`。空 platform 表示规则作用域没有平台（D01）。
   - 改时长：`PUT /api/v1/admin/ops/alert-silences/:silence.id`，body `{"until": "<now + 时长>"}` → 更新后的静默对象；服务端会把同作用域其他更晚的静默一并截到这个时间，可缩短可延长，上限 30 天。
   - 结束：`DELETE /api/v1/admin/ops/alert-silences/:silence.id` → `{"deleted": true}`；同作用域所有生效中的静默都在此刻结束（保留审计记录）。
3. 成功：本地把事件的 `silence` 设为 `{id, until}`（结束时设为 null），回执“已静默 1 小时” / “静默改为至 10:41” / “已结束静默”；新建静默的回执带「撤销」（调 DELETE 刚建的 id），改时长的回执带「撤销」（PUT 回原 until，原 until 已过去则不提供）。随后重拉事件校正。
4. 失败：不改本地状态，回执写原因。
5. 不需要 step-up；不支持 Idempotency-Key。新建超时：重新 GET 事件，有 `silence` 视为成功；没有再允许重试（重复新建也无害，事件只显示 until 最大的一条）。

**错误 reason → 文案**

| reason / 状态 | 文案 | 动作 |
|---|---|---|
| 404 `OPS_DISABLED` | 运维监控已关闭，无法处理告警 | 刷新页面进入关闭态 |
| 404 `OPS_ALERT_SILENCE_NOT_FOUND` | 这条静默已不存在 | 重拉事件 |
| 404 `OPS_ALERT_EVENT_NOT_FOUND` | 这条告警不存在或已被清理 | 返回列表并重拉 |
| 400 `INVALID_UNTIL` | 静默时间无效（须在 30 天内） | — |
| 400 `INVALID_RULE_ID` | 规则已删除，无法静默 | 隐藏静默按钮 |
| 400 `INVALID_STATUS`、`INVALID_EVENT_ID`、`INVALID_SILENCE_ID`、`Invalid until` | 操作未完成（程序错误） | 记录日志 |
| 403 `ACCESS_TOKEN_READ_ONLY` | 只读访问令牌不能处理告警 | 按钮置灰 |
| 网络 / 超时 | 按上面的超时规则核对 | — |

**旧服务端退路（事件 JSON 没有 `silence` 键，即 D01 之前）**：事件 `dimensions.platform` 为空（含全部预置规则）时隐藏静默按钮，只留手动解决；有 platform 时允许 POST 静默，“已静默至”只存本机（`UserDefaults`，键 = 站点 + rule_id + platform + group_id），并且只能延长不能缩短或结束；换设备、在 Web 操作后可能不一致。

#### 7.2 运维监控未开启（首页提示行、监控各段空态、告警详情空态）

**判定**：任一受控接口返回 404 `OPS_DISABLED`，或 home 的 ops / alerts 段 `disabled`，或 `/admin/me` 的 `features.ops_monitoring_enabled == false`。随后读 `GET /api/v1/admin/ops/monitoring-status`（`ops.monitoring_status`，不受开关影响）→ `{config_enabled, monitoring_enabled, realtime_monitoring_enabled, effective, disabled_reason}`。

**显示**：

| disabled_reason | 文案 | 按钮 |
|---|---|---|
| `setting_off` | 运维监控未开启：错误率、告警、服务器状态与错误日志都不可用 | 「开启运维监控」（站长） |
| `config_off` | 运维监控已在服务器配置中关闭（`ops.enabled=false`），需要在服务器配置中启用 | 无（不要引导去 Web 设置页，也不要重试） |
| 读不到（旧服务端） | 运维监控未开启 | 「开启运维监控」 |

监控 Tab 的空态在文案下补一行“关闭期间不会记录错误请求，开启后也不会补回”（附录 B L12）。

**开启流程**：

1. 确认框：标题“开启运维监控？”，正文“开启后开始记录错误请求、告警与服务器指标；关闭期间的数据不会补回。”，按钮「开启」「取消」。
2. `PUT /api/v1/admin/ops/monitoring-status`，body `{"monitoring_enabled": true}` → 与 GET 同结构。不需要 step-up；不带 Idempotency-Key（同值写）。
3. 结果：`effective == true` → 回执“已开启运维监控”，刷新首页与监控全部区块（其他服务端实例最多约 30 秒后生效，首次刷新仍可能 404，30 秒内再自动重试一次）；`effective == false` 且 `disabled_reason == config_off` → 改显示 config_off 文案。
4. 409 `OPS_CONFIG_DISABLED` → config_off 文案，不重试；403 → “当前身份没有修改运维设置的权限”；403 `ACCESS_TOKEN_READ_ONLY` → “只读访问令牌不能修改设置”。
5. 旧服务端（无 `ops.monitoring_status`）：`PUT /api/v1/admin/settings`，body 只带 `{"ops_monitoring_enabled": true}`（省略的字段保持不变）；之后受控接口仍 404 → 视为配置关闭，显示 config_off 文案（D09 退路）。

---

### 8. 本章新增 / 改动文件汇总

| 类型 | 文件 | 内容 |
|---|---|---|
| 新增 Core | `Sources/Sub2Core/BlockState.swift` | 0.5 区块状态 |
| 新增 Core | `Sources/Sub2Core/DashboardHome.swift` | §1 首页聚合模型 |
| 新增 Core | `Sources/Sub2Core/AccountStatusSummary.swift` | D02 汇总模型（与 20 §10.3 同一个文件） |
| 复用 Core | `Sources/Sub2Core/AccountDisplayState.swift`（20 §0.2） | 首页账号行的状态词、倒计时、原因短句 |
| 新增 Core | `Sources/Sub2Core/OpsMonitoring.swift` | §4 运维模型、监控开关 |
| 新增 Core | `Sources/Sub2Core/OpsAlerts.swift`、`AlertPresentation.swift` | §3、§6 告警模型与文案 |
| 新增 Core | `Sources/Sub2Core/ChannelMonitor.swift` | §5 渠道模型 |
| 新增 Core | `Sources/Sub2Core/HomePresentation.swift`、`MonitorPresentation.swift` | 纯函数：6 格、待处理、平静判定、心跳、错误率序列 |
| 改 Core | `APIClient.swift` | 新接口方法、服务器时区日期；删 `dashboardMonitoring` / `OpsReply`；条件请求用 00 §9.7 的 `ConditionalCache`，本章不另加类型 |
| 改 Core | `Models.swift` | 删 `OpsSnapshot`；`DashboardSummary.monitoring` 删除；`PendingBalanceOperation` 加 `createdAt`、`userDisplayName`（30 §3.7） |
| 改 Core | `DashboardPresentation.swift` | 0.4 格式函数 |
| 新增 App | `NativeApp/Session/LiveOpsStore.swift` | 0.5 共享状态、轮询编排、写后刷新 |
| 新增 App（骨架未写出前由本章先建，§0.7） | `NativeApp/Session/AppRouter.swift`、`NativeApp/Views/Receipt.swift`、`NativeApp/Views/StatusRail.swift` | 路由与跨 Tab 跳转、回执 toast、状态轨 |
| 新增 App | `NativeApp/Features/Home/*.swift` | §1、§2 视图 |
| 新增 App | `NativeApp/Features/Monitor/*.swift` | §3–§7 视图与 `AlertActions` |
| 改 App | `NativeApp/Sub2MobileApp.swift` · `MainTabs` | §4.7：`TabView(selection:)`、概览与监控两个 Tab 的根视图、回执叠加层 |
| 改 App | `NativeApp/Features/DashboardView.swift` | 删除首页旧实现；`DashboardTrendChart` 移交统计分析（40 §1）；`DashboardLoadState` 挪到 `NativeApp/Views/LoadState.swift` |
| 改 App | `NativeApp/Features/PerformanceTrendView.swift` | 首页不再内嵌；由 40 章统计分析承接（6 格 RPM / TPM 只负责跳转） |
| 改 App | `NativeApp/Session/AppModel.swift`、`DemoData.swift` | 包装方法、UI 测试数据 |
| 测试 | `Tests/Sub2CoreTests/` | `HomePresentationTests`、`DashboardHomeDecodingTests`、`AttentionItemsTests`、`AlertPresentationTests`、`MonitorPresentationTests`、`ChannelOverviewDecodingTests` |

`Sources/Sub2Core/PerformanceTrend.swift` 的 `rate(_:metric:)` 统一除以整桶秒数，首尾残桶会骤降（附录 B L7，DECISIONS“TPM 口径”落地提醒）——首页已改读 `rates`，不再受影响；按每桶实际覆盖秒数折算的改法由 40 章负责（40 §0.4 的 RPM / TPM 口径）。

---

### 9. 本章未决问题

| # | 问题 | 建议默认值 |
|---|---|---|
| Q1 | 已定的“合并”待处理（DECISIONS 第 2 轮 Q3）在设计稿里没有分组卡；D02 与本章任务都提到“分组可用偏低”要进待处理。要不要单列？ | 单列一行“可用不足 N 个分组”（1.3.3），只在 `shortage.is_short`、分组启用、且组内有异常账号时出现；出现时不进入平静布局。只因停用 / 暂停账号造成的“不足”不提示 |
| Q2 | 首页一次显示几条告警？设计稿演示只画了 1 条 | 显示 `alerts.top` 的全部（≤ 5 条，按级别再按时间），超出部分合成“另有 N 条告警中”一行 |
| Q3 | 渠道行在设计稿里有箭头但没有目的页 | 点进对应分组详情（渠道按分组统计）；以后若做渠道详情再替换 |
| Q4 | 监控 Tab 默认段：设计稿源码默认“渠道”，DECISIONS 的顺序是“概况 + 渠道 + 告警” | 首次进入默认“概况”，之后在本次会话内记住上次所选段 |
| Q5 | 入口拒绝只显示合计次数；`by_reason` 原因明细要不要做二级 sheet | 本版不做；日志采集行保持不可点 |
| Q6 | App 里是否提供“关闭运维监控” | 只在监控 Tab `···` 菜单放「关闭运维监控…」（站长、二次确认，`PUT ops/monitoring-status {"monitoring_enabled":false}`）；首页不提供 |
| Q7 | 首页 `···` 菜单内容设计稿未定义 | 「刷新」「统计分析」两项 |
| Q8 | 关监控时 RPM 只计成功请求（B01 进度备注），6 格里是否单独标注 | 不在格内加字；由 6 格下方的“运维监控未开启”提示行统一说明 |
| Q9 | “静默中的规则”（当前没有 firing 事件的静默）App 看不到 | 本版不做静默列表页；需要时用 `GET /api/v1/admin/ops/alert-silences?active=true` 加一个只读列表 |
| Q10 | 00–60 章没有应用骨架章节（Tab 结构、路由枚举、每 Tab 导航栈、跨 Tab 带参数跳转、推送落点、站点菜单、回执 toast、状态轨、删除确认组件），本章与 20 / 50 / 60 都依赖它 | 在 00 加一节或新建 `05-shell.md` 统一定义；写出之前按本章 §0.7 的接口实现（`AppRouter`、`AppRoute`、`TabIntent`、`Receipt`、`.statusCapsule`），骨架章节写出后本章 §0.7 删减为引用 |

---

## 20 · 账号 Tab（最终实现规格）

> 读者：照着实现 SwiftUI（最低 iOS 26）原生管理端的工程师。本章只写“做什么、调什么、显示什么、出错怎么办”。
>
> 依据：`DECISIONS.md`（第 3 轮以“更正”为准，文末评审意见与 TPM 口径最新）、设计稿 `html-preview/layouts/main/`（已定变体见 `v-decided.jsx`：`accounts: 'platform'`、`acctOrder: 'group'`、`accountDetail: 'inline'`、`aeCred: 'row'`、`screen:accountNew: 'form'`、`anOauth: 'list'`）、`BACKEND-API-CHANGES.md`（进度表备注优先于条目原文）、sub2 `docs/API_ERROR_CODES.md`、sub2 后端源码（2026-10-22 核实，main `70116315d`）。
>
> 路径一律相对站点根 `/api/v1`。“能力”指 `GET /admin/me` 返回的 `capabilities` 字符串（`handler/admin/me_handler.go` 的 `adminMeCapabilities`），没有该能力时走本章写的退路。

本章页面：

| # | 页面 / 流程 | 设计稿来源 |
|---|---|---|
| 1 | 账号列表（三行列表 · 按平台分组 · 平台内同分组在一起 · 再按紧急度） | `v-accounts.jsx` `VaByPlatform`，行 = `00-core.jsx` `AccountRow` |
| 2 | 账号详情（状态卡 + 按钮行、容量、今日、记录） | `00-core.jsx` `AccountDetailTop` |
| 3 | 详情内联编辑（基础 / 调度 / 凭据 / 代理 / 模型 / 高级）、⋯ 菜单、删除、在 Web 中编辑 | `v-account-edit.jsx` `AeInline` |
| 4 | 测试连接（SSE + test_result；异步 test-runs） | `shared/core.jsx` `TestSheet`、`v-account-new.jsx` `AnTest` |
| 5 | 恢复状态 / 启用调度 / 停止调度 / 启用账号 | `shared/core.jsx` `confirmRecover` |
| 6 | 凭据：更换 API Key、Base URL、刷新令牌、重新授权 | `v-account-edit.jsx` `AeKeySheet` `AeUrlSheet` `AeReauthSheet` |
| 7 | 新建账号（单页长表单 + 创建并测试 sheet） | `v-account-new.jsx` `AnForm` |
| 8 | 批量操作（选择 + 底部操作坞） | `v-accounts.jsx` `VaShell` dock |
| 9 | 定时测试（只读） | 已定详情页没有画，本章补一行（见 §9） |
| 10 | 共享数据源：账号状态汇总（D02）、账号排行（C04） | — |

---

### 0. 本章通用规则

#### 0.1 本章用到的能力与退路

| 能力 | 本章用途 | 没有时 |
|---|---|---|
| `accounts.list_query` | 列表 `status` 多值 / 派生值、`sort_by=urgency`、`include_counts` | 全量 lite 分页拉取（`sort_by=name`），本地推导状态、分组、排序和计数 |
| `accounts.status_summary` | 平台组头计数、Tab 徽标 | 组头用已加载行本地计数；徽标用 `dashboard/stats.error_accounts` |
| `accounts.runtime_batch` | 列表 / 详情 60 秒轻刷新 | 重拉列表当前已加载页 / 重拉 `GET /admin/accounts/:id` |
| `accounts.today_stats_failures` | 区分“今日 0”与“查询失败” | `stats` 原样显示，不能区分 |
| `accounts.structured_error` | `error_kind` / `error_status_code` 判凭据类错误（0.2），`error_summary` 作原因短句，`error_at` 只作状态卡出错时间行的退路（§2.3） | 凭据类错误用正则粗判（0.2）；原因短句写“上游返回异常”；出错时间行只用上游错误日志 |
| `accounts.token_status` | 访问令牌剩余时间 | 兼容解析 `credentials.expires_at`（Unix 秒或 RFC3339），分母未知时不画刻度 |
| `accounts.patch` | 内联编辑全部走 `PATCH` + `If-Match` | `GET :id` 拿整份（已脱敏）`credentials` / `extra` 合并后整份 `PUT`，无并发保护（附录 A S30/S31） |
| `accounts.mixed_channel_details` | 409 直接带 `details` | 提交前先 `POST /admin/accounts/check-mixed-channel` 预检 |
| `accounts.recover_schedulable` | 恢复并启用调度一步完成 | `recover-state` 后再 `POST :id/schedulable {true}` |
| `accounts.clear_error_preserve_inactive` | 批量恢复不重新启用停用账号（只用于 §8.8 扩展，默认不做） | 本地先剔除 `status=inactive`，确认框写明 |
| `accounts.test_result` | 测试结束读服务端计时、上游状态码、测试后状态 | 本机计时并标“本机计时”；流结束后 `GET :id` 与测试前快照比对 |
| `accounts.test_runs` | 测试中断后读结果、后台测试 | 中断即“不能判定是否成功”，给“重新测试” |
| `accounts.reauthorize` / `accounts.oauth_error_reasons` | 一步重新授权、换码错误可识别 | `exchange-code` → `apply-oauth-credentials` 两步；超过 30 分钟或 500 时提示“授权链接可能已过期” |
| `scheduled_tests.upstream_status` | 定时测试结果的状态码、分类 | 正则从 `error_message` 解析 `\((\d{3})\)\|returned (\d{3})` |
| `meta.catalog` | 平台、认证方式、协议的运行时目录 | App 内置一份与 `frontend/src/constants/platformCatalog.builtin.json` 同步的清单；未知值显示原始 id |
| `admin.idempotent_writes` | `PUT :id`、`:id/schedulable`、`bulk-update`、`:id/refresh`、`batch-refresh` 带 `Idempotency-Key`，生成、重试、超时与待核对一律按 00 §2.3–§2.5 | 按“不带 key 的写”处理（00 §2.4）：不自动重发，读回核对（各节“结果不明”行给读回方法） |
| `web.accounts_edit_deep_link` | “在 Web 中编辑”直达编辑弹窗 | 打开 Web 账号列表并复制账号名 |
| `dashboard.accounts_ranking` | 账号排行（给概览用，见 §10） | 全量 ID 交 `today-stats/batch` 本地排序 |

C01（新建时 `schedulable=false`）没有能力标记：以响应的 `data.schedulable` 判断是否生效（§7.4）。

#### 0.2 账号显示状态（App 侧唯一推导函数）

新增 `Sub2Core/AccountDisplayState.swift`，所有页面（列表行、详情状态卡、按钮行、批量结果、概览待处理）只用它。判定顺序与后端 `service.AccountScheduleState`（`service/account_status_summary.go:63-82`，即 D02 口径）一致：

| 顺序 | 条件（`now` = ServerTime，见 0.6） | 显示状态 | 色调 | 计时 |
|---|---|---|---|---|
| 1 | `status == "error"` | 错误 | critical | 否 |
| 2 | `status != "active"`（`inactive`、历史值 `disabled`、未知值） | 停用 | neutral | 否 |
| 3 | `overload_until > now` | 过载中 | critical | 到 `overload_until` |
| 4 | `rate_limit_reset_at > now` | 限流中 | caution | 到 `rate_limit_reset_at` |
| 5 | `temp_unschedulable_until > now` | 临时不可调度 | caution | 到 `temp_unschedulable_until` |
| 6 | `schedulable == false` | 暂停 | neutral | 否 |
| 7 | `auto_pause_on_expired && expires_at <= now`（`expires_at` 为 Unix 秒） | 暂停（副文案“已过期”） | neutral | 否 |
| 8 | 其余 | 正常 | ok | 否 |

- **已停止调度**标记：状态是 3–5（限时）且 `schedulable == false`。行和状态卡显示“已停止调度”，与 D02 的 `stopped` 同义。
- **需处理** = 错误 / 过载中 / 限流中 / 临时不可调度；**受限** = 过载中 / 限流中 / 临时不可调度。
- 计时状态的倒计时到 0 时：立即重新推导（可能落到下一个限时状态），并对该账号触发一次 `GET /admin/accounts/:id`（列表里触发一次轻刷新，见 §1.6）。
- 原因短句（行第三行、状态卡标题旁）：
  - 错误：`error_summary`（≤160 字，已脱敏）；为空时“上游返回异常”。**不显示 `error_message` 原文。**
  - 过载中：“上游 529”（后端 `handle529` 设置，`service/ratelimit_service.go:1968`）。
  - 限流中：“上游 429”。
  - 临时不可调度：解析 `temp_unschedulable_reason`（JSON 字符串 `TempUnschedState`，`service/temp_unsched.go:9-21`）：有 `status_code` 写“上游 {status_code}”；`matched_keyword` 非空且 `rule_index >= 0` 时追加“ · 规则 #{rule_index+1}”（与 Web `TempUnschedStatusModal.vue:188-189` 一致）；不是 JSON 时写“临时不可调度”。
- **模型限流**：`extra.model_rate_limits` 是 `{模型: {rate_limit_reset_at: RFC3339, …}}`，只取 `rate_limit_reset_at > now` 的项（与 `activeModelRateLimits` 同口径，`service/account_status_summary.go:413-429`），按模型名排序。
- **凭据类错误**（决定主按钮是“更换 API Key…”还是“重新授权…”）：状态为错误，且 `error_kind ∈ {auth, forbidden, token_refresh}`，或 `error_status_code ∈ {401, 403}`；没有 C02 字段时退回正则 `\b40[13]\b|invalid_api_key|token`（只用于判断，不显示原文）。`error_kind` 取值以后端为准：`auth / forbidden / quota / custom_code / stream_timeout / token_refresh / privacy / rate_limit / other`（`service/account_error_describe.go:14-22`）。
- **令牌账号** = `type ∈ {oauth, setup-token}`（后端 `Account.IsOAuth`）；其余是密钥账号。

#### 0.3 显示名

| 值 | 显示 |
|---|---|
| 平台 id | `meta/catalog` 的 `platform_catalog.platforms[].display_name`；没有目录时用现有 `GroupPlatform.title`（`Sources/Sub2Core/GroupManagement.swift:56-66`）；未知值原样 |
| `type`：`oauth` / `setup-token` / `apikey` / `upstream` / `bedrock` / `service_account` | OAuth / Setup Token / API Key / 对接上游 / AWS Bedrock / Vertex。**例外**：`platform == antigravity && type == apikey` 显示“对接上游”（Web 的“上游”选项以 apikey 创建，`service/admin_meta_catalog.go:35-45`） |
| 账号状态词 | 错误、过载中、限流中、临时不可调度、暂停、停用、正常（BUILDER_GUIDE 硬规则） |
| 动作 | 启用调度 / 停止调度、恢复状态、测试连接、刷新令牌、更换 API Key…、重新授权…、启用账号、删除账号… |
| 金额 | `$1,234.56`；负数 `−$`；缺失 `—`；0 显示 `$0.00`；计费数字不着色 |
| 用语 | “实际”“账号成本”“标准”三个口径名；不出现“成本”“营收” |

#### 0.4 写操作通用规则（本章）

1. **可逆操作直接执行 + 回执给“撤销”**：调度开关、启用 / 停用账号、内联编辑各分区保存、代理切换。撤销 = 用旧值再提交一次（PATCH 时带最新 ETag）。例外：“恢复原代理”先确认、不给撤销（§3.4）。
2. **不可撤销的凭据操作**：更换 API Key、重新授权、刷新令牌。sheet 底部红色按钮即确认；设置里“高风险操作需要 Face ID”打开时，按下后先验证 Face ID 再提交。回执给“测试”或“启用调度”，不给撤销。
3. **删除**：放在 ⋯ 菜单最后（红字）；Face ID 关闭时须输入完整账号名，打开时为“用 Face ID 删除”（`confirmDelete` 规则）。
4. **批量操作**：Face ID 打开时执行前验证（BUILDER_GUIDE：Face ID 覆盖批量操作）。
5. **PATCH 版本**：`GET /admin/accounts/:id` 与 `PATCH` 响应头 `ETag: "cv-<config_version>"`（`service/account_patch.go:18-21`）。列表项不带版本号，所以任何 PATCH 之前必须已有该账号详情的 ETag。PATCH 不支持 Idempotency-Key（G06 未纳入），按“不带 key 的写”处理（00 §2.4，不自动重发）。超时 / 断开后：`GET :id`，所改字段已等于目标值即视为成功，否则提示“没有保存成功”并给“重试”（用户点按；同一 If-Match 重发安全：若第一次已生效，会得到 412 再走比对，00 §2.5.1 注）。
6. **412 `ACCOUNT_VERSION_CONFLICT`**：`metadata.current_etag` 给新 ETag。处理：`GET :id`；若服务端当前值在本次要改的字段（含 `credentials_patch` / `extra_patch` 的键）上仍等于 sheet 打开时的底值 → 用新 ETag 静默重发一次；否则弹框“账号已被其他人修改”，按钮“用我的修改覆盖”（新 ETag 重发）/“重新载入”（丢弃草稿）。
7. **409 `MIXED_CHANNEL_WARNING`**（新建、PUT、PATCH、bulk-update）：用 `metadata.group_name`、`current_platform`、`other_platform` 弹框（Web 文案）“警告：分组“{group_name}”中同时包含 {current_platform} 和 {other_platform} 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？”，按钮“继续保存 / 继续创建”“取消”；确认后请求体加 `confirm_mixed_channel_risk: true` 重发（请求体变了：带 Idempotency-Key 的必须换新 key，00 §2.5.2）。没有 `metadata` 的老服务端：先调 `check-mixed-channel` 拿 `details`。
8. **App 端错误对象必须保留 `reason` 与 `metadata`**：现有 `APIError` 只有 `reason`（`Sources/Sub2Core/APIError.swift`），本章多处依赖 `metadata`（`current_etag`、`run_id`、`recovered`、`retry_within_seconds`、`upstream_status`、`detail`、`group_name` 等），见 §11。

#### 0.5 本章错误 reason → 文案与动作

通用码（401 续期 / 重登、403 `STEP_UP_REQUIRED`、423 合规、429、5xx、`ACCESS_TOKEN_READ_ONLY`、全部 `IDEMPOTENCY_*` 幂等码等）按 00 处理：幂等码的等待时长、何时转“待核对”、`IDEMPOTENCY_KEY_CONFLICT` 回到确认框用新 key 重新确认，都以 00 §2.5.3–§2.5.4 为准，本章不另定数值。下表只列本章特有的：

| HTTP · reason | 出现在 | 文案 | 动作 |
|---|---|---|---|
| 404 `ACCOUNT_NOT_FOUND` | 任何 `:id` 接口 | “这个账号已删除或不在本工作区” | 详情页换成“已删除”空页；列表移除该行并轻刷新；DELETE 遇到它视为已删除 |
| 412 `ACCOUNT_VERSION_CONFLICT` | PATCH | 见 0.4-6 | — |
| 400 `INVALID_IF_MATCH` / `INVALID_PATCH` / `CREDENTIAL_KEY_NOT_DELETABLE` | PATCH | “服务器拒绝了这次修改（{reason}）” | 记日志；属于 App 缺陷，不重试 |
| 409 `MIXED_CHANNEL_WARNING` | 新建 / 编辑分组 | 见 0.4-7 | — |
| 500 `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED` | recover-state | “已恢复 · 仍暂停调度” | 以 `GET :id` 的 `schedulable` 为准；仍暂停时回执给“启用调度” |
| 409 `ACCOUNT_TEST_RUNNING` | test-runs | “这个账号已有测试在运行” | 改为轮询 `metadata.run_id` |
| 429 `ACCOUNT_TEST_BUSY` | test-runs | “站点同时运行的测试已满，请稍后再试”（00 §2.7.2） | 写入 429：不自动重试，按钮按 `Retry-After` 倒计时（00 §2.7.2） |
| 404 `ACCOUNT_TEST_RUN_NOT_FOUND` | test-runs latest / get | “还没有测试记录” | — |
| 503 `ACCOUNT_STATS_UNAVAILABLE` | today-stats/batch | 今日金额全部显示“—” | 下次刷新重试 |
| 400 `TOO_MANY_IDS` | runtime/batch | — | 按 `metadata.max` 拆批（App 每批 ≤200，不应出现） |
| 400 `INVALID_ACCOUNT_STATUS_FILTER` / `INVALID_GROUP_FILTER` | 列表 / 汇总 | — | App 缺陷，去掉该参数重试 |
| 400 `*_OAUTH_SESSION_NOT_FOUND` | 换码 / 重新授权 | “授权链接已过期” | “重新生成链接” |
| 400 `*_OAUTH_INVALID_STATE` | 同上 | “授权码不是这次链接换来的” | “重新打开本次链接”/“重新生成链接” |
| 400 `*_OAUTH_CODE_REJECTED` | 同上 | “授权码无效或已被使用” | 重新授权；Grok 必须重新生成链接（会话已消费） |
| 403 `GROK_OAUTH_ENTITLEMENT_DENIED` | 同上 | “这个 xAI 账号没有授权” | 换账号授权 |
| 502 `OAUTH_EXCHANGE_FAILED` | reauthorize | “服务器连不上 {平台}” | 换代理或稍后重试；Grok 需重新生成链接 |
| 502 `OPENAI_OAUTH_PROXY_REQUIRED` / `*_OAUTH_TOKEN_EXCHANGE_FAILED` / `*_OAUTH_REQUEST_FAILED` | 新建账号换码 | “服务器连不上 {平台}，授权码还没用掉” | “换个代理再试”（不重新授权） |
| 500 `REAUTH_PERSIST_FAILED` | reauthorize | “令牌已换到，但没保存成功” | 不自动重试（00 §2.4、§3.2）。先 `GET :id` 读回：`token_status.refreshed_at` 晚于发起时间（ServerTime）即已保存，按成功处理；否则给“重试保存”（用户点按，同一请求体、同一 `session_id`，服务端已暂存令牌、不重新换码），只在 `metadata.retry_within_seconds` 秒内显示，过期后改为“重新授权” |
| 400 `NOT_OAUTH` / `REAUTH_UNSUPPORTED` | reauthorize | `metadata.detail`：`shadow_account` “影子账号的凭据跟随母账号，请重新授权母账号”；`codex_personal_access_token` “PAT 账号请在 Web 重新导入”；其余“这个账号不能在手机上重新授权” | 给“在 Web 中编辑” |
| 404 `PROXY_NOT_FOUND` | 授权（vendor） | “代理不属于本工作区” | 改选代理或不用代理 |
| 400 `ACCOUNT_NOT_IN_FALLBACK` | 恢复原代理 | “这个账号已不在回退状态” | `GET :id` 刷新，“已回退”行随之消失 |
| 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE` | 恢复原代理 | “原代理已删除、停用或过期，续期并启用后才能恢复” | 给“查看原代理”（push `.proxyDetail(proxy_fallback_origin_id)`，60 章 §13） |
| 404 `RESOURCE_NOT_FOUND` / 403 `WORKSPACE_PERMISSION_DENIED` | vendor 访问 | “没有这个账号的权限” | — |
| 404 `OPS_DISABLED` | 记录区上游错误计数、状态卡“最近上游错误”行、组头告警牌 | 记录区右侧写“运维监控未开启”；状态卡行按 §2.3 退路；告警牌不显示 | 不重试 |

#### 0.6 时间与时区（引用 00 §6.3）

- 本章所有 `now`（状态推导、倒计时、“N 分钟前”、“须晚于现在”、“1 个月后”的起点、与服务端时间戳比先后）一律用 **ServerTime** = 本机时间 + 该站点 `Date` 头偏差（00 §6.3）；不直接用设备时钟。
- 所有绝对时间（`HH:MM`、`HH:MM:SS`、`yyyy-MM-dd HH:mm`，含“预计 HH:MM”“HH:MM 恢复”“HH:MM 到期”“更新于 HH:MM:SS”）按服务器时区（`/admin/me` 的 `server.server_timezone`）显示；日历运算用设了该时区的 `Calendar`。
- 时区提示只用 00 §6.3 的那一句“时间按服务器时区（UTC+8）显示”；本章只在过期时间选择器里出现（手机时区与服务器不同时）。
- 只量经过时长的计时（测试的“本机计时”、授权链接 30 分钟有效期）用本机单调时钟，从本次操作起算，不受偏差影响。

---

### 1. 账号列表

#### 1.1 入口与导航

- 入口：Tab“账号”；概览“受限 N 个账号”等跳转带初始筛选（`needs` / `limited` / `paused`）；分组详情“查看账号”带平台或分组上下文（分组详情页另章，本页只接受 `platform` 预选）。
- 导航栏：标题“账号”（居中），副标题“{站点名} · {counts.all} 个 · {更新时间}”（“刚刚更新”/“N 分钟前更新”）；左“选择”（选择中变“完成”，突出样式）；右“＋”→ 新建账号（§7，全高 sheet）。站点切换走标题菜单（通用）。
- 点行 → 账号详情（§2）。选择模式下点行 = 勾选，Tab 栏隐藏，底部出现操作坞（§8）。
- 不放搜索框：搜索走搜索 Tab（另章，`GET /admin/accounts?search=&lite=1`）。

#### 1.2 数据来源

| 用途 | 请求 | 关键参数 / 说明 |
|---|---|---|
| 列表 | `GET /admin/accounts`（`AccountHandler.List`，`handler/admin/account_handler.go:713`） | `lite=1&page=N&page_size=500&sort_by=urgency&sort_order=asc&include_counts=1`，按筛选胶囊追加 `status=`（见下）、平台菜单追加 `platform=<id>`。`page_size` 上限 1000（`pkg/response/response.go:175-197`）。page 1 返回后若 `total` 大于已加载数，顺序加载后续页，最多加载 2000 行（4 页）；超过时列表底部写“还有 N 个账号未加载，用平台筛选缩小范围”。每页记下响应头 `ETag`，刷新时带 `If-None-Match`，304 时保留该页 |
| 计数 | 同一响应的 `data.counts` | `{all, needs_attention, error, overloaded, rate_limited, temp_unschedulable, unschedulable, inactive, schedulable_now}`（`service/account_list_query.go:86-96`），与当前 `status` 无关、受 `platform` 影响 |
| 组头计数、Tab 徽标 | `GET /admin/accounts/status-summary`（`account_status_summary_handler.go`） | 不带参数；用 `platforms[]`（每项 `platform`、`total`、`available`、`error`、`overloaded`、`rate_limited`、`temp_unschedulable`、`paused`、`inactive`、`stopped`）与 `totals.error`；不依赖运维监控；服务端 10 秒缓存 |
| 每行“今日” | `POST /admin/accounts/today-stats/batch` | `{"account_ids":[…]}`，App 每批 ≤200；`data.stats["<id>"].user_cost`；`data.failed_account_ids`（升序去重，按集合匹配）里的账号显示“—” |
| 实时数（轻刷新） | `POST /admin/accounts/runtime/batch` | `{"account_ids":[…]}`（≤200，超过 400 `TOO_MANY_IDS`），可加 `?include_window_cost=0`；`data.items["<id>"]`：`current_concurrency`（可为 null）、`concurrency_available`、`status`、`schedulable`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`；越权 / 已删的 ID 不出现 |
| 分组名与排序 | `GET /admin/groups/all?include_inactive=true` | 取 `id`、`name`、`platform`、`status`、`sort_order`；站点内缓存，进入 Tab 时后台刷新 |
| 平台显示名 | `GET /admin/meta/catalog` | 带 `If-None-Match` 缓存；切换站点或登录身份后清缓存 |
| 组头告警牌 | `GET /admin/ops/alert-events?status=firing&limit=100`（`OpsHandler.ListAlertEvents`，`handler/admin/ops_alerts_handler.go:612`） | 与 10 章 §6.2“告警中”是同一请求，由账号列表在 Tab 可见时发起；结果写进 `LiveOpsStore` 的告警列表（与首页、监控、告警详情共用一份，10 章 §0.5），`LiveOpsStore` 里这份列表 60 秒内刚取过就直接用、不再发。用到的字段：`id`、`rule_id`、`severity`、`status`、`title`、`description`、`dimensions.platform`、`dimensions.group_id`、`fired_at`、`silence {id, until}`、`rule`、`group_name`。404 `OPS_DISABLED` 或失败 → 不显示告警牌 |

筛选胶囊 → `status` 参数（C14）：

| 胶囊 | `status` | 胶囊上的数字 |
|---|---|---|
| 需处理（有数时红色强调） | `needs_attention` | `counts.needs_attention` |
| 全部（默认） | 不传 | `counts.all` |
| 受限 | `overloaded,rate_limited,temp_unschedulable` | `counts.needs_attention − counts.error`（进度表口径，两者不相交） |
| 暂停·停用 | `unschedulable,inactive` | `counts.unschedulable + counts.inactive` |
| 平台 ▾（菜单） | 追加 `platform=<id>` | 菜单每项右侧写该平台 `status-summary.platforms[].total`；“全部平台”写 `counts.all` |

口径差（写进代码注释，不提示用户）：`unschedulable` 把“过载中又停了调度”的账号算进来，D02 判为过载中；刚到期、尚未被后台任务停调度的自动暂停账号，D02 算暂停而 `unschedulable` 不算；`inactive` 只匹配 `status=inactive`（历史值 `disabled` 只计入全部）。

没有 `accounts.list_query`（老服务端）：不带 `status` / `sort_by=urgency` / `include_counts`，以 `sort_by=name` 全量分页拉取，本地按 0.2 推导状态、筛选、计数、按紧急度排序（紧急度见 1.3）。

没有 `accounts.status_summary` 或 vendor（D02 不对 vendor 开放）：组头计数用已加载行本地统计；此时只在“全部”胶囊下准确，其他胶囊下组头只写个数、不写需处理数。

#### 1.3 字段 → 显示映射

**分区（按平台）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 分区顺序 | 平台集合 = 已加载行的 `platform`；排序键：有错误或过载（`error + overloaded > 0`）=0 → 有需处理 =1 → 正常 =2 → 全部是暂停 / 停用 =3；同级按需处理数降序、总数降序 | 列表存活期间**冻结顺序**（push 详情再返回不跳动），下拉刷新时重排 | — |
| 组头标题 | 平台显示名 + `total` | “Anthropic 4” | — |
| 组头右侧 | 需处理 = `error + overloaded + rate_limited + temp_unschedulable`；`stopped`；`paused`、`inactive` | 有需处理：先“已停止调度 N”（neutral，N>0 时），再“需处理 N”（有错误 / 过载用 critical，否则 caution）；无需处理且 `paused + inactive == total`：“暂停 N · 停用 M”（neutral）；其余不写 | 组头数字始终描述整个平台，不受胶囊影响 |
| 组头告警牌 | `LiveOpsStore` 告警列表里 `status == firing` 且 `dimensions.platform`（忽略大小写）等于该平台 id 的事件；多条时取级别最高（P0 → P3）、同级 `fired_at` 最新的一条 | “{severity} 告警”；该事件 `silence` 非 null 时“{severity} 已静默”；色调 `alertTone`（10 章 §0.6，静默中的事件仍是 firing，保持原色）。点按打开“告警”sheet（§1.4） | 运维关闭、请求失败或无匹配时不显示 |
| 收起 / 展开 | 点组头切换；选择模式下组头右侧“全选 / 取消全选”（只作用于该分区已加载的行） | 收起时选择模式下写“已选 N” | 收起状态按站点存在内存，列表存活期间保留 |
| 分区内排序 | 先按“主分组”：账号 `group_ids` 中 `sort_order` 最小的分组（未分组排最后，未知分组排在未分组之前），再保持服务端 `urgency` 顺序（稳定排序） | — | — |

服务端 `urgency` 顺序：错误 > 限时窗口（按最晚解除时间从近到远）> 暂停 > 其他非 active > 正常，同级按 name、id（进度表 C14）。老服务端本地按同样规则排。

**行（三行，`AccountRow`）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 左侧状态胶囊 | 0.2 色调 | 只有 caution / critical 画胶囊；同一列表里紧挨着的有色行连成一根连续状态轨（不同色也连），整段只有最上和最下是圆头（DECISIONS 第 138 行）；宽 4、离左 6、离上下 10 | 正常 / 暂停 / 停用不画 |
| 行首图标 | 状态图标（正常 dot、限流 hourglass、过载 flame、临时 clockAlert、错误 octagon、暂停 pause、停用 minus） | 选择模式下换成勾选圈 | — |
| 第 1 行左 | `name` | 单行省略 | — |
| 第 1 行右 | 状态牌 | 状态词；限时状态在牌内带倒计时 `m:ss` / `h:mm:ss`，每秒走 | — |
| 第 2 行 | 分组名（`group_ids` → 分组目录名，“、”分隔）· 类型显示名 | 平台分区内省略平台：“高级组、Claude Code 组 · OAuth” | 无分组写“未分组”；目录里找不到写“#id” |
| 第 3 行（错误） | `error_summary` | 单行省略 | 空时“上游返回异常” |
| 第 3 行（限时） | [已停止调度 ·] 原因短句 · HH:MM 恢复 [· 模型限流 N] | “已停止调度”打头（只截尾部），393pt 下“HH:MM 恢复”不被截 | 无模型限流不写尾段 |
| 第 3 行（其他） | 左：并发 `current_concurrency / concurrency`；右：“今日” + `user_cost` | 并发用容量条样式；金额 `$x.xx` | `concurrency_available == false` 或 `concurrency == 0` 时“— 并发”；今日失败“—” |
| 暂停 / 停用行 | — | 整行降低不透明度（`is-idle`） | — |
| 尾部 | chevron | 选择模式下不显示 | — |

空态：当前胶囊 / 平台下没有账号 → 分区区域显示一张卡“没有符合条件的账号”。

#### 1.4 交互与写操作

- 胶囊切换：立即用新 `status` 重新加载（保留旧列表直到新数据到达，显示进度）；平台菜单选中后胶囊行最前出现可移除的“平台：Anthropic ✕”，横向滚回开头。
- 行右滑（可选，List `.swipeActions(edge: .trailing)`）：正常 / 限时且开关开 →“停止调度”；开关关 →“启用调度”。调 `POST /admin/accounts/:id/schedulable`（§5），回执带撤销。
- 选择模式与操作坞见 §8。
- **组头告警牌 → “告警”sheet**（本章定义，设计稿 `v-accounts.jsx` `useVaAlert`；告警牌是组头里独立的按钮，点它不收起分区）。sheet 标题“告警”，左“关闭”，内容自上而下：
  - 事件卡：标题（10 章 §6.3 `AlertPresentation` 的标题）+ 级别牌（“{severity}”/“{severity} 已静默”，`alertTone`）；下一行范围文案 + 规则文案（同 `AlertPresentation`，规则缺失时 `description` 原文）。
  - 两行键值：“维度”= `AlertPresentation` 的范围文案；“状态”=“告警中”或“告警中 · 已静默至 HH:MM”（`silence.until`）。
  - 说明：“告警只精确到分组或平台，不指向具体账号；先看本组需处理的账号。”
  - 按钮行：“手动解决”（主）、“静默…”（已静默时“改静默时长…”）。两者都调 10 章 §7.1 的 `AlertActions`（确认框文案、时长、请求、回执、撤销、错误 reason 全部照 §7.1，本章不另写）；成功后 `LiveOpsStore` 更新，组头告警牌随之消失或改为“已静默”，sheet 关闭。
  - 两个链接行：“只看需处理的账号 ›”（关闭 sheet，胶囊切到“需处理”）；“告警详情 ›”（关闭 sheet，push `{kind:'alert', id}`，10 章 §3）。
  - 只读访问令牌：两个按钮按 00 §2.6.3 置灰并标“只读令牌”。
- 下拉刷新：完整重载（列表 + 汇总 + 今日）。

#### 1.5 状态

| 状态 | 表现 |
|---|---|
| 首次加载 | 骨架行 3 条 + 胶囊占位；组头不画 |
| 加载中（已有数据） | 导航副标题写“正在刷新…”，不清空列表 |
| 后续页加载中 | 列表底部“正在加载更多账号…” |
| 列表失败（已有数据） | 顶部 neutral 横幅“读取失败，显示的是 HH:MM 的数据”+“重试” |
| 列表失败（无数据） | 空页“读取账号失败”+ 原因 + “重试” |
| 汇总失败 | 组头退回本地计数（同 1.2 退路），不提示 |
| 今日失败 | 金额“—”；全部失败（503）时不再单独提示 |
| 运行时失败 | 保留上次值，不提示 |
| 告警列表失败 / 运维关闭 | 不显示组头告警牌，不提示；已打开的“告警”sheet 里的动作失败按 10 章 §7.1 的错误表 |

#### 1.6 刷新策略

- 前台且 Tab 可见、不在选择模式、没有打开的 sheet：每 60 秒一次**轻刷新**：`runtime/batch`（已加载 ID，按 200 拆批）+ `status-summary` + `today-stats/batch` + firing 告警列表（1.2；`LiveOpsStore` 60 秒内已取过则跳过）。任一行的 `status` 或 `schedulable` 变化、或有 ID 不在返回里 → 触发一次**完整刷新**（所有已加载页，带 `If-None-Match`）。
- 完整刷新还发生在：进入 Tab、下拉、站点切换、本章任何写操作成功后、每 5 分钟。
- 倒计时本地每秒走；任一行倒计时归零 → 立即轻刷新一次（10 秒内最多一次）。
- App 进后台 / Tab 不可见：停止定时器；回到前台立即轻刷新。
- 没有 `accounts.runtime_batch`：60 秒改为完整刷新。
- 账号 Tab 徽标：`status-summary.totals.error`（没有能力时 `GET /admin/dashboard/stats` 的 `error_accounts`）；任一页取到汇总即更新；另由 AppModel 在前台每 60 秒补取一次（60 秒内已取过则跳过）。

#### 1.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountsView.swift` : `AccountsView` | 重写为平台分组三行列表。数据与定时器移到新文件 `NativeApp/Features/Accounts/AccountListModel.swift`（`@Observable`：查询、分页、ETag、计数、汇总、今日、运行时、冻结的平台顺序、收起集合）。去掉“显示字段”工具栏、“筛选与排序”表单、“前台自动刷新”开关（改为默认 60 秒）、“快捷编辑”滑动与上下文菜单 |
| 同文件 : `accountRow(_:)` | 改为新文件 `Accounts/AccountRow.swift`（三行 + 状态胶囊 + 倒计时，倒计时用 `TimelineView(.periodic(from:by: 1))`） |
| 同文件 : 批量相关（`AccountBatchAction` 等） | 移到 §8 的操作坞；保留 `AccountBulkReply.outcome(for:)` 的“缺失 / 重复不算成功”语义 |
| `Sources/Sub2Core/AccountManagement.swift` : `AccountListQuery` | `page_size` 改为可配（默认 500）；`status` 改为 `Set<AccountStatusFilter>`（逗号拼接）；`AccountSort` 增加 `urgency`；新增 `includeCounts`；`queryItems` 输出 `include_counts=1` |
| 同文件 : `managedAccounts` | 返回 `AccountListPage { items, total, page, pageSize, pages, counts?, etag? }`，支持传入 `If-None-Match` 并识别 304 |
| `Sources/Sub2Core/Models.swift` : `UpstreamAccount` | 增字段：`error_at`、`error_status_code`、`error_kind`、`error_summary`、`token_status`、`concurrency_available`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`、`temp_unschedulable_reason`、`auto_pause_on_expired`、`updated_at`、`proxy_id`、`proxy_fallback_origin_id`、`proxy_fallback_origin_name`（`dto/types.go:239-240`）、`credentials`（非敏感键）、`credentials_status`、`session_idle_timeout_minutes`；`extra` 保留整份原始 JSON（新增 `JSONValue`）并派生 `modelRateLimits`、`upstreamBillingProbe` |
| `Sources/Sub2Core/APIClient.swift` : `accountTodayStats(ids:)` | 解码 `failed_account_ids`、`degraded`（返回结构体而非字典），按 200 拆批，支持可选 `group_id` |
| 新增 `Sources/Sub2Core/AccountStatusSummary.swift` | `statusSummary(platform:groupID:includeAccounts:)` 与模型 |
| 新增 `Sources/Sub2Core/AccountRuntimeBatch.swift` | `accountRuntime(ids:)`，`current_concurrency` 可为 null |
| 新增 `Sources/Sub2Core/AccountDisplayState.swift` | 0.2 的推导与文案（纯函数，配表驱动单测） |
| `Sources/Sub2Core/GroupManagement.swift` : `AdminGroup` | 增 `sortOrder`（`sort_order`）；`allGroups()` 增 `includeInactive` 参数（现在没带，附录 B L15） |
| `NativeApp/Sub2MobileApp.swift` : TabView | 账号 Tab 加 `.badge(errorCount)` |
| `NativeApp/Session/LiveOpsStore.swift`（10 章新增） | 账号 Tab 可见时由 `AccountListModel` 调它的 firing 告警刷新方法（与监控 · 告警段同一方法、同一份列表，不另建缓存），并按平台取匹配事件 |
| 新增 `NativeApp/Features/Accounts/AccountAlertSheet.swift` | 1.4 的“告警”sheet；文案用 10 章 `AlertPresentation`，动作调 10 章 §7.1 `AlertActions` |
| 可复用 | `AccountFieldPresentation`（`AccountPresentation.swift`）与 `ListFieldSelection` 留给简化模式，不删；`DashboardLoadState`、`load(nextPage:replace:)` 的“请求票据 + 会话代际”防串写写法沿用 |
| `UITests/AccountListCustomizationUITests.swift`、`AccountManagementUITests.swift` | 按新列表重写；`DemoData` 补 11 个演示账号（与设计稿 `DEMO.accounts` 对应的状态覆盖） |

---

### 2. 账号详情（上半部分）

已定：账号详情就是内联编辑页（§3），上半部分 = 状态卡 + 按钮行、容量、今日、记录，下面接六个编辑分区。本节写上半部分。

#### 2.1 入口与导航

- 入口：列表行；概览待处理的账号项；分组详情成员行；搜索结果；请求详情的账号行；推送通知 `account.error` / `account.test_finished`（带 `account_id`，另章）；新建账号完成后的“查看”。
- 只带 id 进入时先显示加载态，`GET /admin/accounts/:id` 后渲染；从列表进入时先用列表行数据渲染，再拉详情。
- 导航栏：返回；标题 = `name`；副标题 = “{平台显示名} · {类型显示名}”；右侧 ⋯ 菜单（§3.4）。
- 去向：记录区“上游错误”→ 使用记录（上游错误段，按本账号筛选，日志章节的 `{kind:'logs', scope:'upstream', account:id}`）；“使用记录”→ 用量明细按本账号筛选；状态卡“最近上游错误 … ›”行 → 那一条上游错误的请求详情（40 章 §7，`request` 路由 `.error(id, kind: upstream)`，与设计稿 `hero-last` 一致）。

#### 2.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 账号 | `GET /admin/accounts/:id` | 完整 DTO（含 `groups`、`proxy`、`credentials`（脱敏）、`credentials_status.has_*`、`extra`、`token_status`、运行时字段、`concurrency_available`）；**响应头 `ETag` 记为该账号的编辑版本**。此接口不支持 304，不要带 `If-None-Match` |
| 今日 | `GET /admin/accounts/:id/today-stats` | `data` 直接是 `{requests, tokens, cost, standard_cost, user_cost}`（`service.WindowStats`）；“今日”按服务器时区 |
| 5 小时窗口 | `GET /admin/accounts/:id/usage?source=passive` | 只对 `platform == anthropic && type ∈ {oauth, setup-token}` 调；`five_hour.utilization`（0–100+）÷ 100；`five_hour` 为 null 时不画。必须带 `source=passive`（缺省 active 可能请求上游） |
| 上游错误（计数 + 最近一条） | `GET /admin/ops/upstream-errors?account_id=:id&time_range=24h&page=1&page_size=1`（`OpsHandler.ListUpstreamErrors`，`handler/admin/ops_handler.go:473`） | 一次请求两用：分页 `total` 给记录区计数；`items[0]`（默认按 `created_at` 倒序，即最新一条）给状态卡“最近上游错误”行，取 `id`、`created_at`、`status_code`、`message`、`phase`。列表含已重试成功的恢复行（`IncludeRecoveredUpstream = true`，同文件第 504 行）；运维关闭返回 404 `OPS_DISABLED` |
| 定时测试 | §9 | — |
| 轻刷新 | `POST /admin/accounts/runtime/batch {"account_ids":[id]}` | 60 秒一次，更新容量和状态；`status` / `schedulable` 变了再 `GET :id` |

#### 2.3 字段 → 显示映射

**状态卡（`detail-head`）**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 正常 | 0.2 = 正常 | 安静卡：图标 + “正常 · 参与调度” | — |
| 暂停 / 停用 | 0.2 = 暂停 / 停用 | “暂停 · 不参与调度”/“停用 · 不参与调度”；到期自动暂停写“暂停 · 已过期，自动暂停调度” | — |
| 状态牌 + 原因 | 0.2 状态词 + 原因短句 | 大号状态牌 + 原因（如“上游 429”“上游 529 · 规则 #1”） | — |
| 大号倒计时（限时） | 该状态窗口结束时间 − now | `m:ss` / `h:mm:ss`，下方“后自动恢复 · 预计 HH:MM” | — |
| 错误正文（错误） | `error_summary` | 多行 | 空时“上游返回异常” |
| 最近上游错误行（错误） | 2.2 上游错误请求的 `items[0]`：时间 `created_at`；状态码按 40 章 §6.3 上游错误行的取法——`status_code ≥ 400` 直接用；`< 400`（已重试成功的恢复行，`status_code` 是客户端最终拿到的码，例如 200）从 `message` 解析 `Recovered upstream error (\d{3})`；解析不到且 `phase == account_auth` 写“鉴权”；都没有时不写状态码段 | 设计稿原文：“最近上游错误 HH:MM · N 分钟前 · 401 ›”（状态码等宽）；不写状态码段时为“最近上游错误 HH:MM · N 分钟前 ›”。点按 → 这一条的请求详情（`.error(id: items[0].id, kind: upstream)`，40 章 §7） | 运维关闭（`OPS_DISABLED`）、请求失败或 24 小时内没有记录：有 C02 且 `error_at` 非 null 时显示不可点（无 chevron）的“出错于 HH:MM · N 分钟前[ · {error_status_code}]”（设计稿之外的退路，见未决问题 8）；否则整行不显示 |
| 已停止调度提示 | 0.2 已停止调度 | “已停止调度 · 到时恢复后也不参与调度” | — |
| 出错停调度提示 | 错误且 `schedulable == false` | “出错时已自动停止调度 · 恢复时可一并启用” | — |
| 模型限流块 | 0.2 模型限流 | 标题“模型限流 N”；每行 `模型（等宽）` + “N 分钟后”（≥60 写“X 小时 Y 分钟”） | 没有时不画 |

**按钮行**（与 `AccountDetailTop` 完全一致，主按钮在前）

| 显示状态 | 按钮 |
|---|---|
| 正常 | **测试连接** · 停止调度 |
| 停用 | **启用账号** · 测试连接 |
| 暂停 | **启用调度** · 测试连接 |
| 错误 · 凭据类 · 未更换 | 令牌账号 **重新授权…**，否则 **更换 API Key…** · 恢复状态 · 测试连接（`bedrock` / `service_account` 账号主按钮改为 **在 Web 中更换凭据**，见未决问题 3） |
| 错误 · 凭据类 · 本次已更换 Key | **测试连接** · 恢复状态 |
| 错误 · 其他 | **恢复状态** · 测试连接 |
| 限时（过载 / 限流 / 临时） | **恢复状态** · 测试连接 · 停止调度（开关已关时为“启用调度”） |

“本次已更换 Key”：App 内存里按账号 id 记一个标记，更换成功时置上，账号 `status` 不再是 `error` 时清除（测试通过会清错误）。

**容量（壹）** — 有一项就画这一节；标题右侧“更新于 HH:MM:SS”

| 行 | 字段 | 格式 | 不显示的条件 |
|---|---|---|---|
| 并发 | `current_concurrency` / `concurrency` | 容量条 + `x/y` | `concurrency == 0` 不画；`concurrency_available == false` 时写“— / y” |
| 调度 RPM | `scheduling_rpm` / `base_rpm` | `x/y`，注“自然分钟” | `base_rpm` 缺失或 0；`scheduling_rpm` 缺失写“—” |
| 会话 | `active_sessions` / `max_sessions` | `x/y`，注“空闲 {session_idle_timeout_minutes} 分钟释放” | `max_sessions` 缺失或 0；注里分钟数缺失时不写注 |
| 日 / 周 / 总配额 | `quota_daily_used`/`quota_daily_limit`、`quota_weekly_used`/`quota_weekly_limit`、`quota_used`/`quota_limit` | 金额容量条 `$96.30 / $150.00` | 对应 limit 缺失或 0 |
| 5 小时窗口 | `usage?source=passive` 的 `five_hour.utilization ÷ 100` | 比例条 + 百分比，注“{resets_at HH:MM} 重置” | 非 Anthropic 令牌账号、`five_hour` 为 null、请求失败 |

**今日（贰）**

| 界面元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 实际 | `user_cost` | 大号金额 | 失败时“—”并在节内写“读取失败 · 重试” |
| 账号成本 | `cost` | 大号金额 | 同上 |
| 标准 | `standard_cost` | 大号金额 | 同上 |
| 请求 / Tokens | `requests` / `tokens`（含缓存） | `4,418` / `27.3M` | 同上 |
| 节脚注 | 附录 B L17 | “账号成本与标准只按真实上游调用计算；实际扣费还含合并探测的跟随请求。” | — |

**记录（叁）**

| 行 | 数据 | 右侧文案 | 不可用 |
|---|---|---|---|
| 上游错误 | 2.2 的 `total` | “近 24 小时 N 条” | 运维关闭写“运维监控未开启”，行仍可点（日志页显示同样提示） |
| 使用记录 | — | 无 | — |
| 定时测试 | §9 | “每 10 分钟 · 上次成功 / 失败” | 见 §9 |

#### 2.4 交互与写操作

按钮行动作的接口与回执见 §5（启停调度、恢复、启用账号）、§4（测试连接）、§6（更换 API Key / 重新授权）。

#### 2.5 状态

| 状态 | 表现 |
|---|---|
| 只带 id 进入的首次加载 | 状态卡骨架 + 各节占位 |
| `GET :id` 失败（有列表快照） | 用快照渲染，顶部横幅“读取最新数据失败，显示的是列表里的快照”+ 重试；编辑分区的“编辑”按钮置灰（没有 ETag） |
| `GET :id` 失败（无快照） | 空页“读取账号失败”+ 重试 |
| 404 `ACCOUNT_NOT_FOUND` | 整页换成“这个账号已删除。”（`RemovedAccount`） |
| 今日 / 5 小时 / 上游错误失败 | 各自节内降级（上表），不影响其他节 |

#### 2.6 刷新策略

- 前台且页面可见、没有打开的 sheet / 确认框：每 60 秒 `runtime/batch`（单 id）+ `today-stats` + `usage?source=passive`（适用账号）+ 上游错误（计数与最近一条，同一请求）；`status` / `schedulable` 有变化或倒计时归零时立即 `GET :id`。没有 `accounts.runtime_batch` 时 60 秒直接 `GET :id`。
- 下拉刷新：全部重拉。
- 打开编辑 sheet 期间暂停定时刷新；sheet 有自己的底值与 ETag，页面轮询**不得**改写 sheet 的底值。
- 写操作成功后：用写接口返回的账号对象替换；需要 ETag 而响应没有带时（`schedulable`、`recover-state`、`refresh`、`reauthorize` 不返回 ETag），在下一次 PATCH 前补一次 `GET :id`。

#### 2.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountsView.swift` : `AccountDetailView` | 替换为新文件 `Accounts/AccountDetailScreen.swift`（上半部分 = `AccountDetailTop` 视图，下接 §3 分区）。现有 `reloadAccount` / `reloadStats` 的票据与会话代际校验、`pollAccount` 的循环写法可复用，间隔改 60 秒 |
| 同文件 : “管理操作”“记录与分析”两节 | 删除；“账号统计分析”入口不在已定设计里（统计分析页按账号筛选另章决定） |
| `Sources/Sub2Core/APIClient.swift` : `account(id:)` | 新增返回 `(UpstreamAccount, etag: String?)` 的变体（`request` 要能拿到响应头） |
| 新增 `Sources/Sub2Core/AccountUsageWindow.swift` | `accountPassiveUsage(id:)` → `five_hour {utilization, resets_at, remaining_seconds}` |
| 上游错误（计数 + 最近一条） | 不新建接口方法：调 40 章 §6.7 的 `errorRecords(page: 1, filter:, kind: .upstream)`（`RequestLogFilter` 带 `accountID`、`time = .rolling("24h")`、`pageSize = 1`），`total` 与 `items.first` 一起用。上游状态码的取法写成 `RequestErrorRecord` 上的一个计算属性（返回 `.code(Int)` / `.accountAuth` / `.unknown`），与 40 章 `LogRow` 共用：`LogRow` 把 `.accountAuth`、`.unknown` 渲染成“鉴权”“恢复”，本章状态卡把 `.unknown` 渲染成不写状态码段 |
| `NativeApp/Features/RequestLogsView.swift:371` | 打开账号详情改用 `AccountDetailScreen` |
| `NativeApp/Features/GroupsView.swift:192` | “查看与管理分组账号”入口改为分组详情成员（另章），不再复用列表 `initialGroupID` |

---

### 3. 详情内联编辑、⋯ 菜单、删除、在 Web 中编辑

#### 3.1 入口与导航

- 详情上半部分之下依次是六个分区：**基础 · 调度 · 凭据 · 代理 · 模型 · 高级**（取代原“档案”）。分区里是只读表单行（`List` + `LabeledContent`）。
- 基础 / 调度 / 模型 / 高级：分区右上“编辑”→ 小表单 sheet（左“取消”、右“保存”）；sheet 内的选择器（分组、过期时间、添加模型、添加映射、选项列表）在 sheet 内 push，不叠第二个 sheet。
- 凭据：行内“更换”“修改”或“刷新令牌 / 重新授权…”行（§6）。
- 代理：分区右上“编辑”→ 代理选择 sheet，选中即生效；有代理时点代理行 → push 代理详情 `.proxyDetail(id)`（60 章 §13，与 60 章“账号详情的代理行”入口一致；设计稿里点行也打开选择器，改动见未决问题 9）；无代理时点行同“编辑”。账号处于到期回退状态时，代理行下多一行“已回退 · 恢复原代理”（§3.3、§3.4）。
- 可由 route 带 `focus`（`basic / sched / cred / proxy / models / adv`）进入时滚动到该分区（凭据类错误的退路入口用 `focus: cred`）。

#### 3.2 数据来源

| 用途 | 请求 |
|---|---|
| 当前值 + ETag | 已有的 `GET /admin/accounts/:id` |
| 保存 | `PATCH /admin/accounts/:id`（`AccountHandler.Patch`，`account_handler.go:1201`），请求头 `If-Match: <ETag>`（也可在体里传 `expected_config_version`，二者不一致 400） |
| 分组选择器 | `GET /admin/groups/all?include_inactive=true`（缓存） |
| 混合渠道预检（无 `accounts.mixed_channel_details` 时） | `POST /admin/accounts/check-mixed-channel {platform, group_ids, account_id}` → `{has_risk, error, message, details{group_id, group_name, current_platform, other_platform}}` |
| 代理选择器 | `GET /admin/proxies/all?with_count=true`（只返回启用的代理，带 `account_count`） |
| 恢复原代理 | `POST /admin/accounts/:id/revert-proxy-fallback`（`AccountHandler.RevertProxyFallback`，`account_handler.go:1816`；路由 `server/routes/admin.go:511`），无请求体 → `data` = `{"message":"reverted"}`（不返回账号对象）。服务端把 `proxy_id` 改回 `proxy_fallback_origin_id` 并清空后者（`repository/account_repo.go:4196-4215`）；原代理已删除、停用或过期 → 409 `PROXY_FALLBACK_ORIGIN_UNAVAILABLE`（`service/admin_proxy.go:299-311`）；不在回退状态 → 400 `ACCOUNT_NOT_IN_FALLBACK`。不接受 Idempotency-Key |
| 添加模型 | `GET /admin/accounts/:id/models` → 数组，每项 `id`、`display_name`（显示 `display_name`，缺省用 `id`） |
| 退路（无 `accounts.patch`） | 顶层字段 `PUT /admin/accounts/:id`（稀疏，指针字段只发改过的）；改 `credentials` / `extra` 时以 `GET :id` 的整份为底合并后整份提交（附录 A S30 / S31：非敏感键没带会被删） |

PATCH 请求体（`PatchAccountRequest`，`account_handler.go:194-215`）：顶层 `name`、`notes`、`type`、`proxy_id`、`concurrency`、`priority`、`rate_multiplier`、`load_factor`、`status`（`active|inactive|error`）、`group_ids`、`expires_at`、`auto_pause_on_expired`、`upstream_billing_probe_enabled`、`confirm_mixed_channel_risk`、`expected_config_version`；`credentials_patch` / `extra_patch` 按顶层键合并，值为 `null` 删除该键，嵌套对象整体替换；**不能**带整块 `credentials` / `extra`（400 `INVALID_PATCH`）；敏感键不能用 `null` 删除（400 `CREDENTIAL_KEY_NOT_DELETABLE`）。响应 = 账号对象 + 新 `ETag`。`expires_at ≤ 0` 清除过期时间、`proxy_id = 0` 清除代理（附录 A S30）。

#### 3.3 字段 → 显示映射

**基础**

| 行 | 字段 | 显示 | 编辑 sheet |
|---|---|---|---|
| 名称 | `name` | 原样 | 文本框，必填（“请输入账号名称”） |
| 账号状态 | `status` | `active` 正常 / `inactive` 停用（dim）/ `error` 错误（critical） | 分段：非错误账号“正常 \| 停用”；错误账号“错误 \| 停用”，副文案“清除错误用账号详情里的“恢复状态””，非错误账号副文案“限流、过载等运行状态不在这里改” |
| 平台 | `platform` · `type` | 显示名 | 只读 |
| 备注 | `notes` | 多行；空写“—” | 多行文本框，可清空（发空串） |

**调度**

| 行 | 字段 | 显示 | 编辑 sheet |
|---|---|---|---|
| 并发数 | `concurrency` | 数字 | Stepper，最小 1 |
| 优先级 | `priority`，副文案“越小越优先” | 数字 | Stepper，≥0 |
| 账号计费倍率 | `rate_multiplier`，副文案“0 表示不计费，仅影响账号计费” | `×1.2` | 文本框（decimal），`^\d+(\.\d+)?$`，否则“账号计费倍率需要是不小于 0 的数字” |
| 负载因子 | `load_factor`，副文案“越大越常被选中” | 缺失或 0 写“默认” | 文本框（整数），1–10000；留空或 0 = 默认（发 0）；否则“负载因子为 1–10000 的整数；留空或 0 恢复默认” |
| 分组 | `group_ids`（显示用 `groups[].name`） | 胶囊列表；空写“未分组” | push“分组”选择器（见下） |
| 过期时间 | `expires_at`（Unix 秒，按服务器时区显示 `yyyy-MM-dd HH:mm`，0.6） | 空写“不过期”；`auto_pause_on_expired` 为真时副文案“到期自动暂停调度” | push“过期时间”：不过期 / 1 个月后 / 1 年后（以 ServerTime 的现在为起点，在服务器时区日历上加 N 个月，月底对齐）/ 自定义（日历 + 时间，`DatePicker` 加 `.environment(\.timeZone, 服务器时区)`，须晚于 ServerTime 的现在；手机时区与服务器不同时脚注“时间按服务器时区（UTC+8）显示”）；选“不过期”发 `expires_at: 0` |
| 过期自动暂停调度 | `auto_pause_on_expired` | — | 有过期时间时才出现的开关 |
| 日 / 周 / 总限额 | `extra.quota_daily_limit` / `quota_weekly_limit` / `quota_limit`；副文案“已用 $x”（`quota_*_used`） | 只列已设置的；都没设写一行“配额 · 日 / 周 / 总限额 · 不限” | 只有 `type ∈ {apikey, bedrock}` 才有这一组（后端 `IsAPIKeyOrBedrock`，`service/account.go:1326-1329`）；文本框（$，decimal），留空 = 不限（`extra_patch` 里该键发 `null`）；脚注“任一项达到后暂停调度；修改限额不重置已用额度。重置时间和用量提醒在 Web 中设置。” |

分组选择器：列出 `status == active` 且 `platform` 为本账号平台或 `composite` 的分组（Antigravity 账号 `extra.mixed_scheduling == true` 时再加 `anthropic`、`gemini`），按 `sort_order`；账号已在的分组即使停用或别的平台也列出（可移出）。每行：勾选圈、名称、徽章（停用 / 组合 / 订阅 / 专属）、副行“倍率 ×{rate_multiplier} · 可用 {active_account_count}/{account_count}”（停用分组写“分组已停用，不接收请求 · 可以移出”；`account_count` 为 0 写“还没有账号”）。Anthropic / Antigravity 账号底部注“Anthropic 与 Antigravity 账号进同一分组时，保存会先提示混合渠道风险”。

**凭据**（详见 §6）

| 账号 | 行 | 字段 | 显示 |
|---|---|---|---|
| 密钥账号 | API Key | `credentials_status.has_api_key` | 🔒“已设置 · 不可查看”+ 行内“更换”；本次已更换时写“已更换 · HH:MM”；凭据类错误且未更换时行下红字“上游拒绝了这个密钥（{error_status_code}），需要更换”；已更换未测试时写“已更换：测试连接通过后自动清除错误（仍暂停调度）” |
| 密钥账号 | Base URL | `credentials.base_url` | 等宽原样 + “修改”；空写“官方地址” |
| 令牌账号 | 访问令牌 | `token_status.expires_at`（无 C10 时解析 `credentials.expires_at`） | 徽章：剩余 ≥1 小时“有效”（ok）/ >0“即将到期”（caution）/ ≤0“已过期”（critical）；正文“N 小时后（到期 HH:MM）”/“N 分钟后（…）”；`token_status.auto_refresh == false` 时副文案“不会自动刷新” |
| 令牌账号 | 刷新令牌 | — | 动作行，标“立即生效” |
| 令牌账号 | 重新授权… | — | 动作行，标“立即生效” |
| 节脚注 | — | — | 密钥：“已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。”令牌：“令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。” |

**代理**

| 行 | 字段 | 显示 |
|---|---|---|
| 代理 | `proxy {id, name, protocol, host, port, status, expires_at, expiry_warn_days}` | 名称（粗）+ 副行“{协议} · {到期词}”（到期词规则同代理章节 `proxyExpiry`）；下方等宽 `protocol://host:port`；`proxy` 为空写“无代理”。有代理时行尾 chevron，点按 push 代理详情（§3.1） |
| 已回退（`proxy_fallback_origin_id` 非 null 时才有） | `proxy_fallback_origin_id`、`proxy_fallback_origin_name` | 标题“已回退：原代理 {proxy_fallback_origin_name}”（名称缺失写“#{id}”），副行“原代理到期后已改为{当前代理名 / 直连}”；行尾按钮“恢复原代理”（§3.4） |
| 提示 | `proxy.status` | `expired`：“代理已过期，这个账号仍挂在上面。换一个启用中的代理，或改为无代理。”；`inactive`：“代理已停用，不在可选列表里；可以换一个，或改为无代理。” |
| 节脚注 | — | “选中即生效，回执里可撤销。”（有“已回退”行时追加“恢复原代理不能撤销。”） |

代理选择 sheet：首行“无代理 · 直连上游”，其后是 `proxies/all?with_count=true` 的启用代理（按 `created_at` 倒序）：名称 + 到期徽章（进入提醒天数时）、等宽地址、“N 个账号在用 · {region} · {到期词}”。当前代理不在列表里（停用 / 过期）时在列表上方说明。

**模型**（`credentials.model_mapping`）

| 元素 | 计算 | 显示 |
|---|---|---|
| 分区右上 | 映射条数 | “只调度这 N 个”/“未限制” |
| 行 | 每个键 `from`；值 `to` | `from`（等宽）→ `to`；`to == from` 写“原样转发”；该模型在 0.2 模型限流里时加徽章“限流 N 分钟” |
| 空 | 无映射或键不存在 | “支持所有模型” |
| 透传提示 | `extra.openai_passthrough == true` | “已开启自动透传，模型限制不生效” |
| 编辑 sheet | 删除行（−）、“添加模型”（`:id/models` 多选，加入为 `{m: m}`）、“添加映射”（请求模型 → 实际模型，`*` 只能在末尾） | 脚注“列表为空时支持所有模型；列出后，没列出的模型不会调度到这个账号。映射把请求模型换成实际模型，* 只能放在末尾。” |

保存：`credentials_patch: {"model_mapping": {…整张表…}}`；清空时 `{"model_mapping": null}`。

**高级**（只放后端源码核实过键名的开关；其余进“在 Web 中编辑”）

| 适用账号 | 行 | 键 | 编辑控件 |
|---|---|---|---|
| Anthropic `oauth` / `setup-token` | 拦截预热请求 | `credentials.intercept_warmup_requests` | 开关 |
| 同上 | 5h 窗口费用控制 | `extra.window_cost_limit`（关 = 删键） | 开关 + 费用阈值（$） |
| 同上 | 会话数量控制 | `extra.max_sessions`（关 = 删键） | 开关 + 最大会话数 |
| 同上 | RPM 限制 | `extra.base_rpm`（关 = 删键；后端负值归零、超过 10000 截断） | 开关 + 基础 RPM |
| 同上 | TLS 指纹模拟 | `extra.enable_tls_fingerprint` | 开关 |
| 同上 | 会话 ID 伪装 | `extra.session_id_masking_enabled` | 开关 |
| 多协议 API Key 平台（目录里 `multi_protocol` 非空） | 账号类型 | `credentials.account_mode`（取值为该平台 `multi_protocol.modes[].mode`） | 分段（≥2 个模式时） |
| 同上 | API 协议 | `credentials.api_protocol`（`adaptive / chat_completions / anthropic / responses`，按当前模式 `base_urls` 的键过滤） | 选项列表 |
| OpenAI | 自动透传（仅替换认证） | `extra.openai_passthrough`，副文案“开启后模型限制不生效” | 开关 |
| OpenAI `apikey` | Responses API 支持 | `extra.openai_responses_mode`：`auto` 自动 / `force_responses` 强制 Responses / `force_chat_completions` 强制 Chat Completions | 选项列表 |
| `apikey` / `bedrock` | 池模式，副文案“上游是账号池时开启，错误不标记本账号” | `credentials.pool_mode` | 开关 |
| `apikey` / `bedrock` | 自动探测上游声明倍率，副文案“只探测，不改账号计费倍率” | 读 `extra.upstream_billing_probe_enabled`，写顶层 `upstream_billing_probe_enabled` | 开关 |
| 所有账号 | 在 Web 中编辑 | 副文案“自定义错误码、请求头覆写等其余设置” | 动作行（§3.4） |

设计稿里 Anthropic 令牌账号的“客户端亲和调度”：**后端无此能力**（账号级没有对应键，Web 编辑弹窗也没有）→ App 不显示。改国产厂商的接入端点（`api_base_urls` 等）不在手机编辑，放“在 Web 中编辑”。

#### 3.4 交互与写操作

- **分区保存**：sheet 计算与底值的差异，只发改过的字段（顶层直接放，`credentials` / `extra` 子键放 `*_patch`）。无改动时“保存”置灰；校验不过时置灰并在字段下写错误。有改动点“取消”或下滑 → 确认框“放弃未保存的改动？{N} 项改动不会保存：{字段名…}”（“放弃改动”红 /“继续编辑”）。
- 改了 `group_ids`：有 `accounts.mixed_channel_details` 直接 PATCH，按 0.4-7 处理 409；没有则先 `check-mixed-channel`，`has_risk` 时同样弹框。
- 成功：替换账号与 ETag；回执“已保存：{前 3 个字段名}[ 等 N 项]”+“撤销”（PATCH 回旧值，带新 ETag）。撤销失败（412 等）→“撤销没有成功：账号已被修改”+“重新载入”。
- **账号状态**：改为停用 → PATCH `{status: "inactive"}`；改回正常 → `{status: "active"}`（调度开关不变：停用前已停调度的账号回来仍是暂停）。从基础 sheet 或状态卡“启用账号”都可以，回执都带撤销。
- **代理**：选中即 PATCH `{proxy_id: <id>|0}`，回执“已保存：代理 → {名称 / 无代理}”+ 撤销。
- **恢复原代理**（“已回退”行的按钮）：
  1. 确认框：标题“恢复原代理「{原代理名}」？”，正文“账号改回走 {原代理名}，出口 IP 随之改变。恢复后不能撤销。”，按钮“恢复原代理”/“取消”。不需要 Face ID、不需要 step-up。
  2. `POST :id/revert-proxy-fallback`（3.2）。成功 → `GET :id` 取最新账号与 ETag（响应不带账号）→ 回执“已恢复原代理「{原代理名}」”，**不给撤销**：服务端已清空 `proxy_fallback_origin_id`，再用 PATCH 改回备用代理只会让账号停在备用代理上、且不再记得原代理，不等于撤销；需要换代理时用“编辑”。列表完整刷新一次。
  3. 失败：按 0.5 的 `ACCOUNT_NOT_IN_FALLBACK` / `PROXY_FALLBACK_ORIGIN_UNAVAILABLE` 处理；其余通用错误回执“恢复原代理没有成功：{原因}”。
  4. 超时 / 断开：不自动重试（00 §2.4）。`GET :id` 读回：`proxy_fallback_origin_id == null` 且 `proxy_id` 等于原代理 id → 按成功处理；否则提示“结果未确认”并给“重试”（重复调用安全：已恢复时只会得到 `ACCOUNT_NOT_IN_FALLBACK`）。
- **⋯ 菜单**（SwiftUI `Menu`，删除项红字放最后，没有“编辑账号”）：
  - 密钥账号：“更换 API Key…”、“在 Web 中编辑”、“删除账号…”
  - 令牌账号：“刷新令牌”、“重新授权…”、“在 Web 中编辑”、“删除账号…”
- **删除账号…**：确认框标题“删除账号「{name}」？”，正文第一行“站点 {站点名} · 删除后不能恢复。”；Face ID 关闭时须在输入框输入完整账号名，按钮“删除账号”（红）在输入一致前置灰；Face ID 打开时按钮“用 Face ID 删除”，点后验证。`DELETE /admin/accounts/:id` → 成功或 404 → 先 pop 回列表，再回执“已删除账号「{name}」”，列表完整刷新。
- **在 Web 中编辑**（C19）：有 `web.accounts_edit_deep_link` → 用系统浏览器（`openURL`，复用 Safari 里的 Web 登录态；`SFSafariViewController` 不共享 Safari Cookie）打开 `{站点根}/admin/accounts?edit={id}&search={name 百分号编码，按 UTF-8 截到 100 字节}`，回执“已在浏览器打开「{name}」的编辑页”。没有该能力 → 打开 `{站点根}/admin/accounts` 并把账号名放进剪贴板，回执“已打开 Web 账号管理 · 已复制「{name}」，可直接搜索”。

#### 3.5 状态

| 状态 | 表现 |
|---|---|
| 没有 ETag（`GET :id` 失败） | 分区“编辑”、代理行置灰，提示“先刷新账号” |
| 保存中 | sheet 的“保存”变进度，sheet 不可下滑关闭（`.interactiveDismissDisabled`） |
| 超时 / 断开 | 按 0.4-5 读回比对；已生效 → 正常回执；未生效 → sheet 内“没有保存成功”+“重试” |
| 412 / 409 / 400 | 见 0.4、0.5 |
| 删除失败（非 404） | 确认框关闭，回执“删除没有成功：{原因}” |

#### 3.6 刷新策略

sheet 打开期间暂停页面定时刷新；保存成功后用响应替换；sheet 关闭后恢复 60 秒轻刷新。

#### 3.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `NativeApp/Features/AccountEditView.swift` : `AccountEditView` | 拆成 `Accounts/AccountSectionSheet.swift`（basic / sched / models / adv 四种，共用差异计算与校验）。可复用：`integer(_:label:)`、倍率正则、`unresolved`（结果不明时停止提交并读回）思路、step-up 处理 |
| `Sources/Sub2Core/AccountManagement.swift` : `AccountUpdateRequest` / `PendingAccountUpdate` / `updateAccount` | 新增 `AccountPatchRequest`（含 `credentialsPatch` / `extraPatch: [String: JSONPatchValue]`，能编码显式 `null`）与 `patchAccount(id:body:ifMatch:) -> (UpstreamAccount, etag)`；旧 PUT 路径保留为退路（并按 S31 合并整份 credentials / extra） |
| 新增 `Sources/Sub2Core/JSONValue.swift` | 任意 JSON 值（`extra`、`credentials`、`model_mapping` 读写都需要） |
| 新增 `Sources/Sub2Core/AccountMixedChannel.swift` | `checkMixedChannel(platform:groupIDs:accountID:)` 与 409 `details` / `metadata` 解码 |
| 新增 `Accounts/AccountProxyPicker.swift`、`AccountGroupPicker.swift`、`AccountExpiryPicker.swift`、`AccountModelEditor.swift` | 对应选择器；代理到期词复用代理章节的函数 |
| 新增 `Sources/Sub2Core/ProxyManagement.swift`（若代理章节未提供） | `allProxies(withCount:)` |
| `APIClient.swift` | 新增 `deleteAccount(id:)`、`accountModels(id:)`、`revertAccountProxyFallback(id:)`（无体 POST，成功只表示已执行，调用方随后 `account(id:)` 取 ETag） |
| `Accounts/AccountDetailScreen.swift` 代理分区 | 有代理时行 push `ProxyDetailView(id:)`（60 章 §13 新增的视图），“编辑”打开 `AccountProxyPicker`；“已回退”行与确认框 |

---

### 4. 测试连接

#### 4.1 入口与导航

- 详情按钮行“测试连接”；更换 API Key / 重新授权后的回执“测试”；新建账号的“创建并测试”（§7，同一套流程，sheet 样式不同）。
- 呈现：sheet（`.presentationDetents([.large])`），标题“测试连接”，左“关闭”。

#### 4.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 可选模型 | `GET /admin/accounts/:id/models` | 默认选中第一个 `id` 含 `sonnet` 的，否则第一个；点模型名可换 |
| 测试（SSE） | `POST /admin/accounts/:id/test`，体 `{"model_id": "…"}`（还可带 `prompt`、`mode`），`Accept: text/event-stream` | 事件 `type`：`test_start`、`status`、`content`（`text`）、`image` / `audio` / `video`、`test_complete`（`success`）、`error`（`error`）；**之后**还有一条 `test_result`（`data` 见下）。`error` 之后流不结束，仍会写 `test_result` |
| 测试结果 | `test_result.data`（`service.AccountTestResult`） | `success`（以 `data.success` 为准，顶层 `success` 失败时缺省）、`started_at`、`first_token_ms`（可 null）、`total_ms`、`upstream_status`（可 null）、`usage {input_tokens, output_tokens}`（可省略）、`account {status, schedulable, rate_limit_reset_at, temp_unschedulable_until, error_summary, error_kind}`（读失败时 null）、`recovery {cleared_error, cleared_rate_limit}`（失败时 null）、`marked {error, rate_limited, temp_unschedulable}` |
| 中断后核对 | `GET /admin/accounts/:id/test-runs/latest` | SSE 结束时后端尽力写一条 `source=manual` 记录；字段 `run_id, account_id, source, status(running|success|failed|interrupted), model, latency_ms, first_token_ms, upstream_status_code, error_kind, error_summary, error_message, response_text, recovery, started_at, finished_at` |
| 异步测试（重新测试用） | `POST /admin/accounts/:id/test-runs {"model_id", "recover_on_success": true}` → 202，`data` 同上视图；轮询 `GET /admin/account-test-runs/:run_id` | 409 `ACCOUNT_TEST_RUNNING`（`metadata.run_id`）、429 `ACCOUNT_TEST_BUSY`；vendor 不开放 |

#### 4.3 字段 → 显示映射

| 界面元素 | 来源 | 格式与文案 |
|---|---|---|
| 目标行 | 账号名 | 副文案“测试会向上游发送一次真实请求，可能产生少量费用” |
| 输出区（等宽） | `→ 测试 {平台} · {name}`、`→ 模型 {model}`，之后 `content` / `status` 事件文本逐行追加 | 每行经脱敏（现有 `sanitizedTestOutput`：Bearer、`sk-…`、URL 替换为“[已隐藏]”），最多 500 行 |
| 通过结果 | `test_result.data.success == true` | “测试通过 · 首字 {first_token_ms/1000}s · 总耗时 {total_ms/1000}s”；`first_token_ms` 为 null 不写首字；无 C07 时用本机计时并加“本机计时” |
| 通过后的恢复说明 | `recovery.cleared_error` / `cleared_rate_limit` + `account.schedulable` | 清了且开关开：“已自动清除{错误/限流}，账号恢复调度”；清了且开关关：“已自动清除{…}，仍暂停调度”+ 右侧按钮“启用调度”；都没清不写 |
| 失败结果 | `data.success == false` | “测试未通过 · {upstream_status}”（null 时不写码）；副文案：`marked.error` 或测试后 `account.status == error` 且属凭据类（`account.error_kind ∈ {auth, forbidden, token_refresh}` 或码 401/403）→ 令牌账号“令牌无效，账号保持错误。重新授权后再测试连接”、密钥账号“凭据无效，账号保持错误。更换 API Key 后再测试连接”；`marked.rate_limited` →“测试触发了上游限流，账号进入限流中”；`marked.temp_unschedulable` →“测试触发了临时不可调度”；否则“账号状态没有改变，可以稍后重试” |
| Token 用量 | `usage` | 有时在通过结果下写“输入 N · 输出 M tokens” |

#### 4.4 交互与写操作

- 打开即开始测试（与设计一致，无“开始”按钮）；结束后可点模型名换模型再测。
- 结果里的“启用调度”→ `POST :id/schedulable {true}`（§5），回执带撤销，关闭 sheet。
- 测试结束（收到 `test_result` 或流结束）后：用 `test_result.data.account` 更新详情的状态字段，并 `GET :id` 刷新全量与 ETag。
- 进行中点“关闭”：**不取消**——测试作为 AppModel 持有的任务继续跑，sheet 关闭；完成后回执“「{name}」测试通过 / 未通过”+“查看”。App 进入后台时申请 `beginBackgroundTask`；流在收到 `test_result` 之前断开 → `GET test-runs/latest`（`started_at` 不早于本次开始时间；开始时间按 ServerTime 记，0.6）：`success` / `failed` 按结果回执；`interrupted` 或查不到 → 回执“测试被中断，不能判定是否成功”+“重新测试”。
- “重新测试”（中断后、或用户从回执点）：有 `accounts.test_runs` 走 `POST test-runs`（离开也会跑完），前台每 3 秒轮询 `GET /admin/account-test-runs/:run_id` 直到非 `running`；无能力走 SSE。

#### 4.5 状态

| 状态 | 表现 |
|---|---|
| 模型加载中 / 失败 | 失败时用平台默认模型（`claude-sonnet-4-5` 等内置表）并照常测试 |
| 流打开失败（4xx/5xx） | 结果区“测试没有开始：{原因}”；403 `STEP_UP_REQUIRED` 走通用 step-up 后用户手动重试 |
| 只收到 `test_complete` 没有 `test_result`（老服务端） | 以 `test_complete.success` 判断，按 C07 退路比对 |
| 流异常结束 | 见 4.4 |

#### 4.6 刷新策略

无轮询（SSE 推送）；异步测试前台每 3 秒轮询，后台停止，回前台补一次。

#### 4.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `Sources/Sub2Core/SSEParser.swift` : `AccountTestEvent` / `AccountSSEParser` | `isTerminal` 不能再停在 `test_complete` / `error`：有 `accounts.test_result` 时终止事件改为 `test_result`（或 EOF）；`AccountTestEvent` 增 `data`（解码 `AccountTestResult`）、`model`、`status` |
| `Sources/Sub2Core/APIClient.swift` : `testAccount(id:model:)` | 读到 `test_result` 或 EOF 才结束；体保留 `model_id`，可选 `prompt` / `mode` |
| `NativeApp/Features/AccountsView.swift` : `AccountTestView` | 替换为 `Accounts/AccountTestSheet.swift`（模型选择、结果解读、关闭不取消）；脱敏函数 `sanitizedTestOutput` 复用 |
| 新增 `Sources/Sub2Core/AccountTestRuns.swift` | `startTestRun`、`latestTestRun`、`testRun(runID:)` |
| `NativeApp/Session/AppModel.swift` | 持有后台测试任务表（账号 id → 任务），供回执与“查看”使用 |

---

### 5. 恢复状态 / 启用调度 / 停止调度 / 启用账号

#### 5.1 入口与导航

详情按钮行；列表行右滑（启停调度）；概览待处理（另章复用本节动作）。都是确认框或直接执行 + 回执，不进新页面。

#### 5.2 数据来源

| 动作 | 请求 | 说明 |
|---|---|---|
| 停止 / 启用调度 | `POST /admin/accounts/:id/schedulable {"schedulable": bool}` | 返回账号对象；有 `admin.idempotent_writes` 时带 `Idempotency-Key`（新 UUID） |
| 恢复状态 | `POST /admin/accounts/:id/recover-state`，可选体 `{"schedulable": true|false}` | 不带体：清错误、限流、过载、临时不可调度、模型限流并让 OAuth 令牌缓存失效，不改开关；`true`：恢复成功后再启用调度；`false`：先暂停再恢复。体格式错误返回 400 且不做任何写。返回账号对象 |
| 启用账号 | `PATCH /admin/accounts/:id {"status":"active"}` + `If-Match` | 退路 `PUT :id {"status":"active"}` |

#### 5.3 字段 → 显示映射

确认框（`confirmRecover`）：

| 条件 | 标题 | 正文 | 按钮 |
|---|---|---|---|
| 开关已关（错误账号，或手动停调度的限时账号） | 恢复「{name}」？ | 错误：“清除错误状态。出错时账号已被停止调度，恢复后仍是暂停，除非同时启用调度。”；限时：“清除{限流/过载/临时不可调度}[和 N 项模型限流]。这个账号已停止调度，恢复后仍是暂停，除非同时启用调度。” | 恢复并启用调度 · 只恢复状态（保持暂停）· 取消 |
| 开关开着 | 恢复「{name}」？ | “清除{…}[和 N 项模型限流]，账号立即参与调度。” | 恢复状态 · 取消 |

回执：

| 动作 | 回执 | 附加按钮 |
|---|---|---|
| 恢复并启用调度 / 恢复状态（开关开） | 已恢复 · 参与调度 | — |
| 只恢复状态 | 已恢复 · 仍暂停调度 | 启用调度 |
| 停止调度 | 已停止调度 | 撤销 |
| 启用调度 | 已启用调度 | 撤销 |
| 启用账号 | 已启用账号「{name}」 | 撤销 |

#### 5.4 交互与写操作

- “恢复并启用调度”：有 `accounts.recover_schedulable` → `recover-state {"schedulable":true}`；没有 → `recover-state`（无体）成功后再 `POST :id/schedulable {true}`，第二步失败时回执“已恢复 · 仍暂停调度”+“启用调度”。500 `ACCOUNT_RECOVERED_SCHEDULABLE_FAILED` → `GET :id`，以 `schedulable` 为准。
- “只恢复状态”/“恢复状态”：`recover-state` 不带体。
- 恢复不可撤销（不给撤销）。停 / 启调度与启用账号给撤销（反向再调一次）。
- 停止调度只拨开关：正常账号显示为暂停；限时账号保持状态与倒计时，加“已停止调度”。
- 凭据类错误时“恢复状态”仍可用（次要按钮），恢复后下一次请求可能再次出错——不额外提示（设计已把修复动作放主按钮）。

#### 5.5 状态

写请求进行中，按钮行对应按钮显示进度、整行禁用；失败回执“{动作}没有成功：{原因}”。结果不明（超时 / 断开）：`:id/schedulable` 有 `admin.idempotent_writes` 时带 key，按 00 §2.5.4（同 key 自动重试、仍不明转“待核对”）；没有该能力时，以及 `recover-state`、启用账号的 PATCH（都不带 key），按 00 §2.4 不自动重试。核对方法（本章定义，00 §2.5.5“其余”）：`GET :id`，停 / 启调度看 `schedulable` 是否等于目标值；恢复看 `status != error` 且限流 / 过载 / 临时不可调度时间都已过去；启用账号看 `status == active`。核对后再给回执。

#### 5.6 刷新策略

成功后用返回账号替换；列表完整刷新一次；概览待处理下次刷新自然更新。

#### 5.7 对现有代码的改动点

| 文件 : 符号 | 改法 |
|---|---|
| `APIClient.swift` : `setSchedulable(id:enabled:)` | 可选 `Idempotency-Key` |
| 新增 `Sources/Sub2Core/AccountRecovery.swift` | `recoverAccountState(id:schedulable: Bool?)`（`nil` 不带体） |
| `AccountsView.swift` : `AccountDetailView.mutate` | 删除；动作移到 `AccountActions`（详情、列表、概览共用，含回执与撤销） |

---

### 6. 凭据：更换 API Key、Base URL、刷新令牌、重新授权

#### 6.1 入口与导航

- 更换 API Key：凭据区 API Key 行“更换”；⋯“更换 API Key…”；凭据类错误时状态卡主按钮。→ sheet“更换 API Key”。
- Base URL：凭据区“修改”→ sheet“Base URL”。
- 刷新令牌：凭据区动作行、⋯ 菜单，直接执行。
- 重新授权：凭据区动作行、⋯ 菜单、状态卡主按钮 → sheet“重新授权”（tall）。停用账号先弹确认（见 6.4）。

#### 6.2 数据来源

| 动作 | 请求 |
|---|---|
| 更换 API Key | `PATCH :id {"credentials_patch":{"api_key":"<新值>"}}` + `If-Match`；退路：`GET :id` 整份 `credentials` 替换 `api_key` 后整份 `PUT`（附录 A S31） |
| Base URL | `PATCH :id {"credentials_patch":{"base_url":"<url>"}}`；改回官方地址发 `{"base_url": null}` |
| 刷新令牌 | `POST /admin/accounts/:id/refresh`（可带 `Idempotency-Key`）→ 账号对象，或 `{account, message, warning:"missing_project_id_temporary"}` |
| 生成授权链接 | Anthropic OAuth：`POST /admin/accounts/generate-auth-url {proxy_id}`；Anthropic Setup Token：`POST /admin/accounts/generate-setup-token-url {proxy_id}`；OpenAI：`POST /admin/openai/generate-auth-url {proxy_id, redirect_uri?}`；Gemini：`POST /admin/gemini/oauth/auth-url {proxy_id, project_id?, oauth_type, tier_id?}`（`oauth_type` 取账号 `credentials.oauth_type`）；Antigravity：`POST /admin/antigravity/oauth/auth-url {proxy_id}`；Grok：`POST /admin/grok/oauth/auth-url {account_id, proxy_id}`。返回 `{auth_url, session_id[, state]}`（Gemini / Antigravity / Grok 带 `state`）。`proxy_id` 一律传账号自己的 `proxy_id`（没有代理不传） |
| 一步重新授权 | `POST /admin/accounts/:id/reauthorize {session_id, code, state?, redirect_uri?, proxy_id?, auth_kind?, oauth_type?, tier_id?, preserve_status?}`（`ReauthorizeAccountRequest`，`account_reauthorize.go:36-46`）：`auth_kind` 仅 Claude（`oauth|setup-token`，缺省取账号现有 type）；`oauth_type` / `tier_id` 仅 Gemini；返回账号对象（不含令牌）。令牌只在服务端流转 |
| 退路（无 `accounts.reauthorize`） | 各平台 `exchange-code`（Claude：`/admin/accounts/exchange-code` 或 `exchange-setup-token-code {session_id, code, proxy_id}`；OpenAI：`/admin/openai/exchange-code {session_id, code, state, redirect_uri?, proxy_id}`；Gemini：`/admin/gemini/oauth/exchange-code {session_id, state, code, proxy_id, oauth_type, tier_id}`；Antigravity：`/admin/antigravity/oauth/exchange-code {session_id, state, code, proxy_id}`；Grok：`/admin/grok/oauth/exchange-code {account_id, session_id, code, state, redirect_uri?, proxy_id}`）→ 按 Web composables（`useAccountOAuth.ts` 等的 `buildCredentials` / `buildExtraInfo`）构造 → `POST /admin/accounts/:id/apply-oauth-credentials {type, credentials, extra}`。令牌只在内存里保留到 apply 成功，apply 失败用同一份令牌重试，不重新换码 |

#### 6.3 字段 → 显示映射

**更换 API Key sheet**：目标行“{name} · 点按底部按钮后立即生效”；安全输入框“粘贴新的 API Key”（右侧“粘贴”用 `PasteButton`，不触发剪贴板授权弹窗）；粘贴后显示“新密钥 {前缀}••••{末 4 位} · {N} 个字符”（前缀识别 `sk-ant-api03-`、`sk-proj-`、`sk-`、`AIza`、`xai-`、`AKIA`）；未粘贴写“当前密钥已设置，不可查看”；红色按钮“更换 API Key”；按钮下“站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销[。点按后验证 Face ID]”。

**Base URL sheet**：输入框（url 键盘）“留空使用官方地址”+“清空”；校验 `^https?://[^\s/]+`，不过时“地址要以 http:// 或 https:// 开头”；按钮“保存 Base URL”/“改回官方地址”（未改动置灰）。`platform == antigravity && type == apikey`（对接上游）Base URL 必填：不提供“改回官方地址”。

**重新授权 sheet**：

| 元素 | 内容 |
|---|---|
| 目标行 | {name} · 有代理：“授权走已保存的代理 {代理名}；分组、并发和代理设置不变”；无代理：“账号没有代理，授权页直连打开” |
| 第 1 步 授权链接 | Claude 账号先选授权方式（分段 OAuth / Setup Token，按账号 type 预选；说明“完整权限”/“只授予推理权限”；改选另一种时追加“ · 授权后账号类型改为 {方式}”）；按钮“生成授权链接”→ 显示等宽链接、“复制链接”“打开”（`SFSafariViewController`）；有代理时提示“授权页要从代理 {名} 的出口打开；手机做不到时，复制链接到走同一代理的电脑上打开”；链接 30 分钟内有效，显示剩余时间。改选授权方式会作废已生成的链接和已粘贴的码 |
| 第 2 步 | “登录 {平台} 并授权”+ 说明：显示授权码的平台（Claude、Gemini）“登录要授权的那个账号。授权后页面会显示授权码，复制它。”；回调平台（OpenAI `localhost:1455`、Antigravity `localhost:8085`、Grok `127.0.0.1:56121`）“授权后浏览器跳到 {地址} 的页面（打不开是正常的），拷贝地址栏里的链接。” |
| 第 3 步 | 输入框：授权码 / “回调链接或 Code”；回调平台从粘贴内容里解析 `code` 与 `state` 查询参数，Claude 原样传（含 `#state`，服务端会校验） |
| 提交 | 红色“替换令牌”（未生成链接或未粘贴置灰）；下方说明：“点按后立即保存新令牌[，账号类型改为 X][，并重新启用账号 / ，并清除{错误/限流/…}[和 N 项模型限流]]；调度开关不变。[出错时已停止调度，之后仍暂停。]站点不再使用旧令牌，不能撤回[；之后验证 Face ID]” |

回执（按重新授权前后状态比较）：

| 情况 | 回执 | 附加按钮 |
|---|---|---|
| 原状态正常 | 已重新授权 · 令牌已替换 | 测试 |
| 清除了错误 / 限流且开关开 | 已重新授权 · 已清除{…} · 参与调度 | 测试 |
| 清除了错误 / 限流但开关关（错误账号常见） | 已重新授权 · 已清除{…} · 仍暂停调度 | 启用调度 |
| 原状态停用 | 已重新授权 · 已启用账号 · {参与调度 / 仍暂停调度} | 测试 / 启用调度 |
| 改了方式 | 前缀“已重新授权 · 账号类型改为 {方式}” | 同上 |

刷新令牌回执：“已刷新令牌 · 新令牌 HH:MM 到期”（`token_status.expires_at`）；`warning == "missing_project_id_temporary"` →“已刷新令牌，project_id 暂未取到（会自动重试）”。

#### 6.4 交互与写操作

- 更换 API Key：点红色按钮 → Face ID（打开时）→ PATCH。成功：凭据行变“已更换 · HH:MM”，记“本次已更换”标记，回执“已更换 API Key”+“测试”。不可撤销。
- 重新授权：
  1. 账号 `status == inactive` 时先确认：标题“重新授权「{name}」？”，正文“这个账号现在是停用状态。授权后账号会被重新启用{并参与调度 / ，调度仍暂停}。”，按钮“继续授权”/“取消”（DECISIONS 第 113 行；因此 `preserve_status` 不传，保持后端默认重新启用）。
  2. 生成链接（6.2）→ 浏览器授权 → 粘贴 → “替换令牌”→ Face ID（打开时）→ `reauthorize`。
  3. `REAUTH_PERSIST_FAILED`：按 0.5 先读回核对；未保存时给“重试保存”（同一 `session_id`，不重新换码，不自动重试）。
  4. 成功：用返回账号替换，ETag 失效（下次 PATCH 前补 `GET :id`）。
- 刷新令牌：直接执行（不可撤销，无确认），失败回执“刷新令牌没有成功：{原因}”。结果不明：有 `admin.idempotent_writes` 时带 key，按 00 §2.5.4；没有时按 00 §2.4 不自动重试，`GET :id` 看 `token_status.refreshed_at` 是否晚于发起时间（ServerTime）。

#### 6.5 状态

| 状态 | 表现 |
|---|---|
| 生成链接中 / 换码中 | 按钮内进度，sheet 不可下滑关闭 |
| 链接超过 30 分钟（本地计时） | 第 1 步变“授权链接已过期”+“重新生成链接”（不等服务端报错） |
| 换码 / 保存错误 | 0.5 各 reason；错误显示在对应步骤下，红字 + 补救按钮 |
| 结果不明（超时） | 重新授权不接受 Idempotency-Key，按 00 §2.4 不自动重试。`GET :id` 看 `token_status.refreshed_at` 是否晚于发起时间（ServerTime）：是 → 视为成功；否 → “不能确认是否已替换”+“重试”（用户点按；同一 `session_id` 在 5 分钟内重放是安全的：已保存的会直接返回账号） |

#### 6.6 刷新策略

无轮询；成功后详情 `GET :id`。

#### 6.7 对现有代码的改动点

新增 `Sources/Sub2Core/AccountOAuth.swift`（各平台 auth-url / exchange-code、`reauthorize`、`applyOAuthCredentials`、错误 reason 解码）；新增 `NativeApp/Features/Accounts/OAuthFlow.swift`（三步清单 + 回调解析 + 可选本机监听，§7 共用）、`AccountCredentialSheets.swift`（Key / Base URL / 重新授权）。现有 `refreshManagedAccount` 改为解码返回的账号对象与 `warning`。

---

### 7. 新建账号

#### 7.1 入口与导航

- 账号页右上“＋”。全高 sheet（`NavigationStack { Form }`），隐藏 Tab 栏；左“取消”；标题“新建账号”，副标题“{站点} · 还差 N 项 / 必填已填齐”（创建后为“{站点} · #{id} 已创建 · {暂停调度 / 错误（已停止调度）/ 调度状态待核对}”）。
- 分区顺序：平台与认证方式 → 凭据（随方式变化；OAuth 是三步清单）→ 名称 → 分组（胶囊）→ 调度 → 网络 → 更多（折叠）。
- 底部玻璃坞（`.safeAreaInset(edge: .bottom)`）：没填齐时“还差 {项目…}”，点按滚到第一项（`ScrollViewReader.scrollTo`）；填齐后“可以创建了 · 创建后立即停止调度，测试通过再启用”+ 按钮“创建并测试”。失败后改为“保存并重新测试”（有改动）/“重新测试”（无改动）。
- 测试在 sheet（`.large`，进行中 `.interactiveDismissDisabled`）里：进度四行 → 结果 → 折叠的测试输出。
- 去向：完成 → 关闭表单，列表回执“已创建「{name}」· 参与调度”+“查看”（→ 账号详情）。

#### 7.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 平台与方式 | `GET /admin/meta/catalog` | `platform_catalog.platforms`（展示顺序、`display_name`、`cn_provider`、`multi_protocol {default_mode, modes[{mode, base_urls, protocol_rules}]}`）；`platform_auth`（当前身份可新建的平台 → 认证方式，已按 vendor 裁剪）。无能力 / 423 时用内置清单 |
| 分组 | `GET /admin/groups/all` | 只含启用分组，按 `sort_order`；过滤：本平台 + `composite`（Antigravity 打开“在 /v1/messages 中使用”时再加 `anthropic`、`gemini`） |
| 代理 | `GET /admin/proxies/all?with_count=true` | 只含启用代理 |
| 名称建议 | `status-summary.platforms[].total`（没有时用列表计数） | “{短名}-{NN}”，NN = 该平台现有账号数 + 1，两位补零 |
| 混合渠道 | `POST /admin/accounts/check-mixed-channel {platform, group_ids}` | 选中分组时（Anthropic / Antigravity）逐个预检，用于胶囊风险标记；提交时以 409 为准 |
| OAuth | 6.2 各平台 `auth-url` / `exchange-code` | 新建流程不能用 `reauthorize`（还没有账号）；不用 OpenAI / Grok 的 `create-from-oauth`（不支持 `schedulable=false`） |
| 创建 | `POST /admin/accounts` + `Idempotency-Key` | 体 `CreateAccountRequest`（`account_handler.go:145-166`）：`name`、`notes?`、`platform`、`type`、`credentials`、`extra?`、`proxy_id?`、`concurrency`、`priority`、`rate_multiplier?`、`load_factor?`、`group_ids`、`expires_at?`、`auto_pause_on_expired?`、`upstream_billing_probe_enabled?`、`confirm_mixed_channel_risk?`、**`schedulable: false`**、`skip_default_group_bind?` |
| 测试 | §4 | — |
| 失败后保存修改 | `PATCH /admin/accounts/:id`（平台不可改；`type` 可改，切换前确认） | 需要 ETag：创建成功后 `GET :id` 取一次 |
| 测试通过启用 | `POST /admin/accounts/:id/schedulable {true}` | — |
| 处理未通过 | 保存为停用：`PATCH {status:"inactive"}`；删除：`DELETE /admin/accounts/:id` | — |

凭据构造（以 Web `frontend/src/components/account/CreateAccountModal.vue` 提交逻辑为准，主要键已在后端核实）：

| 方式 | `type` | `credentials` 主要键 |
|---|---|---|
| API Key（通用） | `apikey` | `api_key`、`base_url`（留空时填平台官方地址：OpenAI `https://api.openai.com`、Gemini `https://generativelanguage.googleapis.com`、Grok `https://api.x.ai/v1`、TypeSafe `https://api.typesafe.ai`，其余 `https://api.anthropic.com`） |
| 多协议 API Key 平台 | `apikey` | 另加 `account_mode`（所选模式）、`api_protocol`（`adaptive` 或具体协议）；`adaptive` 时 `api_base_urls`（各协议端点）且 `base_url` = 其中 `chat_completions`；具体协议时 `base_url` = 所选端点（预设或自定义） |
| Antigravity 对接上游 | `apikey` | `base_url`、`api_key` |
| AWS Bedrock | `bedrock` | `auth_mode`（`sigv4` / `apikey`）、`aws_region`（缺省 `us-east-1`）；sigv4：`aws_access_key_id`、`aws_secret_access_key`、`aws_session_token?`；apikey：`api_key` |
| Vertex（Service Account） | `service_account` | `service_account_json`（文件原文）、`project_id`、`client_email`（从 JSON 读出）、`location`、`tier_id: "vertex"` |
| OAuth / Setup Token | `oauth` / `setup-token` | 由 `exchange-code` 返回的令牌信息按 Web composables 的 `buildCredentials` 构造，`extra` 按 `buildExtraInfo`（Claude：`org_uuid`、`account_uuid`、`email_address`） |

Antigravity 的“在 /v1/messages 中使用”= `extra.mixed_scheduling`；“允许超量请求（AI Credits）”= `extra.allow_overages`（后端 `service/account.go:2042,2058` 读取）。

#### 7.3 字段 → 显示映射

| 分区 | 元素 | 来源 / 规则 | 文案 |
|---|---|---|---|
| 平台与认证方式 | 平台下拉 | 目录平台按“常用（anthropic、openai、gemini、antigravity、grok）/ 国内厂商（`cn_provider`）/ 更多”分组；只列 `platform_auth` 里有的 | 未选“选择平台”；创建后锁定“已创建，不能更换”+ 锁图标，脚注“要换平台请删除后重建。…” |
| 同上 | 认证方式单选行 | `platform_auth[pid]` 映射为设计行：anthropic → Claude Code（OAuth / Setup Token）· Claude Console（API Key）· AWS Bedrock · Vertex；openai → ChatGPT OAuth · API Key；gemini → Google OAuth（Google One / Code Assist）· AI Studio（API Key）· Vertex；antigravity → Antigravity OAuth · 对接上游；grok → Grok OAuth · API Key；多协议平台 → 每个 `mode` 一行（按量付费 / Coding Plan / Zen / GO，均为 API Key）；其他 → API Key | 每行标题 + 副文案（如“浏览器授权”“粘贴 sk-ant-api03- 开头的 Key”） |
| 凭据 | 随方式 | API Key：安全输入 + 粘贴 + Base URL；多协议：“接入”分区（API 协议、官方端点 / 端点选择、自定义端点）；Bedrock：认证方式分段 + 字段 + Region 选择；Vertex：“从“文件”选择 JSON”（`fileImporter`），显示文件名与 `project_id`；对接上游：上游 Base URL + Key；OAuth：见下 | 脚注“Key 只提交到站点，App 不保存。” |
| 凭据 · OAuth | 三步清单（`anOauth: 'list'`） | ① 生成授权链接（30 分钟内有效，倒计时）② 在浏览器里登录 {Claude/ChatGPT/Google/xAI} 并授权 ③ 粘贴授权码 / 完成授权；Claude 先选“添加方式”OAuth / Setup Token；Gemini 先选“授权类型”Google One / Code Assist（Code Assist 需填 GCP Project ID） | 已完成写“已授权 · {邮箱}” |
| 名称 | 名称、备注 | 自动起名（可改，改后不再自动） | 必填；脚注“按平台自动起名，可以改。” |
| 分组 | 胶囊 | 7.2 过滤；选中带勾 + 强调色；预检有风险时胶囊加铃铛标记，脚注“「{分组}」里已有 {平台} 账号，创建时要确认混合渠道风险。” | 右上“已选 N[ · K 个需确认]”/“可不选”；没有可选分组“没有可选的 {平台} 分组，不分组也能创建。”；不选分组时脚注加“不选分组时，如果站点有「{平台 id}-default」分组会自动加入” |
| 调度 | 并发数（默认 10，1–100）、优先级（默认 1，1–99，“数值越小越优先”）、账号计费倍率（默认 1，“0 表示不计费，只影响账号计费”） | — | — |
| 网络 | 代理 | 选择 sheet 同 §3 | 无代理写“无代理” |
| 更多 | 过期时间、过期自动暂停调度、负载因子（1–10，可空）、Antigravity 的 AI Credits | 折叠，未展开时右侧写“不过期 / {日期} 到期” | 展开后脚注“模型白名单与映射、自定义错误码、配额等，创建后在账号详情里设置。” |
| 坞 | 还差清单 | 顺序：平台 → 认证方式 / 账号类型 → 凭据（“授权”“API Key”“AWS 凭据”“JSON 文件”“上游地址和 Key”“自定义端点”）→ 名称 → 计费倍率 | 标题副行的“还差 N 项”数同一份清单 |

测试 sheet（`AnTest`）：

| 元素 | 内容 |
|---|---|
| 进度四行 | 创建账号（完成写 `#id`）· 停止调度（C01 生效时随创建一起完成，写“不接收请求”；需要单独停调度时显示进行中 / 失败“没有确认”）· 测试连接（右侧写模型名，结束后可点换模型重测）· 启用调度（通过“参与调度”，失败“未启用”）。重试时第一行改为“保存修改”（无改动写“没有改动”） |
| 通过 | “测试通过 · 已启用调度”，副文案“[错误状态已自动清除。]首字 Xs · 总耗时 Ys”（无 C07 时加“本机计时”）；按钮“查看账号”“完成” |
| 失败 | “测试未通过 · {原因}”，等宽原文“上游返回 {upstream_status} · {SSE error 事件文本（脱敏）}”；`marked.error` 或测试后 `account.status == error` →“后端已把账号 #{id} 标为“错误”，并停止调度，不会接收请求。”，否则“账号 #{id} 已停止调度，不会接收请求。”；按钮“修改凭据后重试”（主）、“保留（错误状态）/ 保留，暂停调度”、“保存为停用”；最后一个次要红字按钮“删除账号…”（DECISIONS 第 114 行的例外，仍需输入名称或 Face ID） |
| 停调度失败 | “停止调度没有确认 · 结果待核对”，“账号 #{id} 已创建，可能正在参与调度。凭据还没验证，可能已经在接收请求。重试一次停止调度，成功后自动开始测试。”；按钮“重试停止调度”、“删除账号…” |
| 测试输出 | 进行中展开流式；结束后折叠成一行（显示最后一行与行数） |

原因映射（失败标题里的“{原因}”）：`account.error_kind`（或 `upstream_status`）→ `auth`/401：密钥“API Key 无效或已撤销”、令牌“令牌无效或已撤销”；`forbidden`/403：OAuth“授权的账号没有可用额度或权限”、Vertex“Service Account 没有 Vertex AI 权限”、Bedrock“AWS 凭据无效或没有 Bedrock 权限”；`quota`“上游额度不足”；`rate_limit`/429“上游限流”；其他“上游返回 {code}”；都没有时“上游拒绝了这次测试请求”。

#### 7.4 交互与写操作

1. **创建并测试**：
   - 混合渠道：Anthropic / Antigravity 且选了分组 → 有 `accounts.mixed_channel_details` 直接提交、按 409 弹框；否则先 `check-mixed-channel`。弹框“返回修改分组”滚到分组区；“继续创建”后同一流程内对同一组分组不再询问，请求带 `confirm_mixed_channel_risk: true` 并**换新 Idempotency-Key**。
   - `POST /admin/accounts`（`schedulable: false`）。响应 `data.schedulable == true`（老服务端忽略参数）→ 立即 `POST :id/schedulable {false}`；失败进入“停止调度没有确认”。
   - `GET :id` 取 ETag → 测试（§4，SSE）。
   - 通过（`data.success`）→ `POST :id/schedulable {true}` → “测试通过 · 已启用调度”。启用失败 → “测试通过 · 启用调度没有成功”+“重试启用”。
   - 未通过 → 账号留在暂停或错误（看 `marked.error` / `account.status`）。
2. **修改凭据后重试**：关闭测试 sheet 回到表单，顶部 critical 横幅“测试未通过 · #{id} 已创建 / 已标为错误”+“处理”；凭据区上方说明“账号 #{id} 已创建，暂停调度中 / 已被标为错误（已停止调度）；这里的修改会在“保存并重新测试”时保存到它[，测试通过后错误自动清除]”。坞按钮“保存并重新测试”→ `PATCH :id`（改过的字段；凭据走 `credentials_patch`）→ 测试；无改动“重新测试”直接测试。改认证方式需确认“改成「X」？账号 #{id} 已创建。换认证方式后要重新授权 / 填写凭据，保存时替换原来的凭据。”
3. **处理（横幅 / 取消）**：确认框“账号「{name}」已创建，怎么处理？”，正文说明当前状态；按钮“保存为停用”（`PATCH {status:"inactive"}`，回执“已保存「{name}」为停用 · 不参与调度”+“查看”）、“保留，暂停调度 / 保留（错误状态）”（不发请求，回执带“查看”）、“删除账号…”（红）、“继续修改”。
4. **取消**：未选平台直接关闭；已填写 →“放弃新建账号？已填写的内容（和授权结果）不会保存。”；测试进行中 → 转后台（4.4 规则：任务由 AppModel 持有），回执“「{name}」在后台继续测试，完成后通知你”；通过后回执“测试通过 · 已启用调度”+“查看”（启用调度由后台任务完成），未通过回执“测试未通过 · {已标为错误（已停止调度）/ 仍暂停调度}”+“处理”（→ 账号详情）。
5. **换平台**：已填凭据时确认“换成 {平台}？已填写的{授权 / 凭据}[和选好的分组]会清空，名称、调度和代理保留。”；已授权后换 OAuth / Setup Token 或 Google One / Code Assist 同样确认“切换会丢弃当前授权，需要重新在浏览器里授权。”。Antigravity 关掉“在 /v1/messages 中使用”时移除不再适用的分组，回执“已移除 N 个不再适用的分组”+ 撤销。
6. **OAuth（三步清单）**：
   - 生成链接（6.2，`proxy_id` = 网络区所选代理）。链接 30 分钟倒计时。
   - 打开：`SFSafariViewController`。回调平台（OpenAI 1455、Antigravity 8085、Grok 56121）在 Safari sheet 显示期间用 `Network.framework` `NWListener` 监听本机端口，接到带 `code` 与 `state` 的请求后回一页“已交给 App”、关闭 Safari、自动换码；监听失败（端口被占）退回粘贴（用户在 Safari 错误页“分享 → 拷贝”后回来粘贴）。显示授权码的平台（Claude、Gemini）用粘贴。
   - 完成授权：调对应 `exchange-code`（带当前所选代理，`exchange-code` 的 `proxy_id` 优先于会话里的代理，换代理不重置进度）。失败按 0.5：会话过期 / 拒码 → “重新生成链接”；代理类 502 → “换个代理再试”（选代理后直接重新兑换，不消耗授权码）；浏览器回调带 `error=access_denied` → “你在浏览器里拒绝了授权”+“重新打开链接”。
   - 换到的令牌只在内存；离开表单即丢弃。

#### 7.5 状态

| 状态 | 表现 |
|---|---|
| 目录 / 分组 / 代理加载失败 | 对应区写“读取失败 · 重试”；目录失败用内置清单；分组失败可不选分组创建 |
| 创建失败（4xx，含 409 非混合渠道） | 测试 sheet 第一行“创建账号”标失败 + 原因；坞恢复“创建并测试” |
| 创建结果不明（超时） | 按 00 §2.5.4（新建账号的 key 没有服务端执行上限、“处理中”多久转待核对，见 00 §2.5.1 那一行）。转“待核对”后的核对方法（本章定义）：`GET /admin/accounts?search={name}&lite=1`，按 `name` 完全相等且 `platform` 相同匹配：找到 → 当作已创建，用它的 id 继续流程；找不到 → “没有创建成功”+“用同一编号重试”（同 key 重发；之后的响应仍按 00 §2.5.3 处理） |
| 测试中 / 后台 | 见 4.4 |

#### 7.6 刷新策略

无轮询。表单打开时各拉一次目录、分组、代理；OAuth 倒计时本地每秒走。完成或离开后列表完整刷新。

#### 7.7 对现有代码的改动点

现有 App 没有新建账号。新增 `NativeApp/Features/Accounts/AccountNewView.swift`（表单 + 坞 + 测试 sheet，状态机照 `useAnWizard`：`idle → creating → pausing → testing → passed / failed / pauseFailed`，重试 `saving`）、`AccountNewDraft.swift`（草稿、缺项清单、凭据构造）、复用 §6 的 `OAuthFlow.swift`；`Sources/Sub2Core/AccountCreate.swift`（`createAccount(_:idempotencyKey:)`）、`MetaCatalog.swift`（`metaCatalog()` + 内置兜底清单）。账号列表 `AccountListModel` 提供“新建成功后完整刷新”。

---

### 8. 批量操作

#### 8.1 入口与导航

账号列表左上“选择”→ 选择模式：行首勾选圈、组头“全选 / 取消全选”、Tab 栏隐藏、底部玻璃操作坞；“完成”退出并清空选择。

#### 8.2 数据来源

| 动作 | 请求 | 响应 |
|---|---|---|
| 停止 / 启用调度 | `POST /admin/accounts/bulk-update {"account_ids":[…], "schedulable": bool}`（有 `admin.idempotent_writes` 时带 `Idempotency-Key`，每批一个 key） | `{success, failed, success_ids, failed_ids, results[{account_id, success, error?}]}` |

每次请求最多 50 个账号，超过时分批顺序提交、结果合并（后端不限，App 自限，沿用现有 `setAccountsSchedulable` 的校验）。执行上限与客户端超时见 00 §2.3、§2.5.1。

#### 8.3 字段 → 显示映射

| 元素 | 内容 |
|---|---|
| 坞左侧 | “已选 N 个” |
| 坞按钮 | 只有“停止调度”、“启用调度”（主）两个，与设计稿 `VaShell` 的 dock 一致；未选择时都置灰 |
| 结果 sheet（有失败时） | 标题“批量操作结果”，站点名；每个失败账号一行：名称（#id）+ 原因（`error` 原文不显示，按 HTTP 语义归类为“服务器拒绝 / 结果不明”）；“未返回此账号的明确结果，请先刷新核对”用于缺失或重复的结果 |

#### 8.4 交互与写操作

- Face ID 打开时，任何批量动作先验证。
- **停止 / 启用调度**：可逆，直接执行。回执“已{停止/启用}调度 N 个账号[ · K 个失败]”+“撤销”（对 `success_ids` 按操作前的 `schedulable` 分两组各发一次 `bulk-update`，撤销是新的用户意图、用新 key）；有失败时附“查看”打开结果 sheet。执行后退出选择模式。
- 所有批量写完成后列表完整刷新。

#### 8.5 状态

执行中坞按钮变进度、选择不可改；整体请求失败 → 回执“批量操作没有成功：{原因}”，选择保留。结果不明（超时 / 断开）：带 key 时按 00 §2.5.4（同 key 自动重试、仍不明转“待核对”）；没有 `admin.idempotent_writes` 时按 00 §2.4 不自动重试，回执“结果未确认，请刷新核对后再操作”。核对方法（本章定义，00 §2.5.5“其余”）：对所选 ID 调 `runtime/batch`，`schedulable` 全部等于目标值即成功，不等的列入结果 sheet。

#### 8.6 刷新策略

选择模式期间暂停 60 秒轻刷新；退出后恢复并立即完整刷新。

#### 8.7 对现有代码的改动点

`AccountsView.swift` 的 `prepareBatch` / `executeBatch` / `outcomeSheet` 迁到 `Accounts/AccountBatchDock.swift`；`setAccountsSchedulable` 加 `Idempotency-Key`；去掉“确认执行”确认框（调度开关改为直接执行 + 撤销）；现有 `AccountBatchAction.refresh`（批量“刷新凭据”）按设计稿去掉，是否保留见未决问题 7。

#### 8.8 设计稿之外的扩展（默认不做，见未决问题 7）

设计稿的坞只有两个按钮。下面是“⋯”菜单（“恢复状态…”、“刷新令牌”）的接口与规则，**只在用户看过效果图、决定加上之后才实现**：

| 动作 | 请求 | 响应 |
|---|---|---|
| 恢复状态 | `POST /admin/accounts/batch-clear-error {"account_ids":[…], "preserve_inactive": true}`（不接受 Idempotency-Key） | `{total, success, failed, errors[{account_id, error}] 或 null, skipped_inactive_ids[]}`（`errors` 为 null 时当空数组） |
| 刷新令牌 | `POST /admin/accounts/batch-refresh {"account_ids":[…]}`（有 `admin.idempotent_writes` 时带 `Idempotency-Key`） | `{total, success, failed, errors[{account_id, error}], warnings[{account_id, warning}]}` |

- **恢复状态…**：确认框“恢复 N 个账号？清除错误、限流、过载、临时不可调度和模型限流。[已停用的 M 个账号不会被重新启用。]”按钮“恢复状态”/“取消”。有 `accounts.clear_error_preserve_inactive` 发 `preserve_inactive: true`；没有则本地剔除 `status == inactive` 的账号再发（确认框同样写明）。批量清错误不改调度开关：完成后数出 `status == active && schedulable == false` 的账号 K 个，回执“已恢复 N 个[ · 其中 K 个仍暂停调度]”+“启用调度”（对这 K 个发 `bulk-update schedulable:true`，该回执再给撤销）。不可撤销。结果不明按 00 §2.4（不带 key）读回：`runtime/batch` 看 `status`。
- **刷新令牌**：只提交选中里的令牌账号（其余在确认框里写“N 个非令牌账号跳过”）；确认框“刷新 N 个账号的令牌？”；回执“已刷新 N 个[ · K 个失败]”。结果不明按 00 §2.5.4。
- 代码：新增 `batchClearError(ids:preserveInactive:)`、`batchRefresh(ids:)`（替换现在逐个串行的 `refreshManagedAccount` 循环）。

---

### 9. 定时测试（只读）

已定详情页（inline）没有画定时测试；为 C09 补一行，放在“记录”节最后，只读，计划在 Web 中维护（第 2 轮 `v-detail.jsx` `VdTests` 的文案）。

#### 9.1 入口与导航

详情“记录”节“定时测试”行，点 → push“定时测试”小页（最近结果列表）；不提供新建 / 编辑。

#### 9.2 数据来源

| 用途 | 请求 |
|---|---|
| 计划 | `GET /admin/accounts/:id/scheduled-test-plans` → `[{id, account_id, model_id, cron_expression, enabled, max_results, auto_recover, last_run_at, next_run_at, …}]` |
| 结果 | `GET /admin/scheduled-test-plans/:id/results?limit=20`（缺省 50）→ `[{id, plan_id, status, response_text, error_message, latency_ms, started_at, finished_at, created_at, upstream_status_code, error_kind}]` |

#### 9.3 字段 → 显示映射

| 元素 | 来源 | 格式 | 空值 |
|---|---|---|---|
| 行右侧 | 第一个 `enabled` 计划 + 其最新结果 | “{cron 人话} · {model_id} · 上次{成功/失败}” | 无计划“没有计划 · 在 Web 中添加”；计划都停用“计划已停用” |
| cron 人话 | `cron_expression` | `*/N * * * *` → “每 N 分钟”；`0 */N * * *` → “每 N 小时”；其余原样等宽 | — |
| 结果行 | `started_at`（HH:MM）、`status`、`upstream_status_code`、`latency_ms`、`error_kind` / `error_message` | 成功：“成功 · 1.3s”；失败：状态码徽章（`codeTone`）+ 分类词（auth 凭据无效、forbidden 无权限、quota 额度不足、rate_limit 上游限流、其他写状态码）；不显示 `error_message` 原文 | 无 `upstream_status_code` 时按 0.1 正则从 `error_message` 解析，仍无写“—” |

#### 9.4 交互与写操作

无写操作；小页底部“在 Web 中编辑计划”→ 打开 Web 账号深链（§3.4）。

#### 9.5 状态

读取失败 → 行右侧“读取失败”，小页内“重试”。vendor 只能看自家账号的计划（别家 404 `ACCOUNT_NOT_FOUND`）。

#### 9.6 刷新策略

进入详情时读一次；详情 60 秒轻刷新不含它；小页下拉刷新。

#### 9.7 对现有代码的改动点

新增 `Sources/Sub2Core/ScheduledTests.swift` 与 `Accounts/AccountScheduledTestsView.swift`。

---

### 10. 共享数据源：账号状态汇总（D02）与账号排行（C04）

本章只定义接口与解码；概览、分组、监控章节按各自口径使用。

#### 10.1 状态汇总 `GET /admin/accounts/status-summary`

- 参数：`platform?`、`group_id?`（正整数，否则 400 `INVALID_GROUP_FILTER`）、`include_accounts?`（布尔）、`default_min_ratio?`。
- 响应：`collected_at`；`totals` / `platforms[]` / `groups[]` 都含 `total, available, error, overloaded, rate_limited, temp_unschedulable, paused, inactive, stopped`；`groups[]` 另有 `group_id, group_name, platform, group_status, shortage {is_short, source(alert_rule|default), rule_id?, metric_type?, operator?, threshold?, current?}`；`include_accounts=true` 时 `accounts[]`：`id, name, platform, group_ids, state(available|error|overloaded|rate_limited|temp_unschedulable|paused|inactive), stopped, status, schedulable, error_message, rate_limit_reset_at, overload_until, temp_unschedulable_until, temp_unschedulable_reason, expires_at（RFC3339）, model_rate_limits[{model, reset_at}]`。
- 不依赖运维监控；服务端 10 秒缓存；不对 vendor 开放（vendor 用本地计数）。
- 本章用：平台组头（1.3）与账号 Tab 徽标（`totals.error`）。`state` 与 0.2 推导一致，可直接互用。

#### 10.2 账号排行 `GET /admin/dashboard/accounts-ranking`

- 参数：`start_date` / `end_date`（或 `start_time` / `end_time`，经 `usagequery.ParseRange`）、`timezone`（缺省当天）、`limit`（1–50，缺省 10）、`platform?`、`group_id?`。
- 响应：`ranking[{account_id, account_name, platform, status, requests, tokens, actual_cost, account_cost, standard_cost}]`、`total_actual_cost`、`start_date`、`end_date`、`query`；服务端 30 秒缓存；vendor 不开放。`actual_cost` 与 `today-stats/batch` 的 `user_cost` 同口径。
- 账号 Tab 主模式不使用（已定列表按平台分组，没有“按今日金额”排序）；给概览平静布局“按账号 · 今日实际扣费 · 前 4”和以后的简化模式用。

#### 10.3 改动点

新增 `Sources/Sub2Core/AccountStatusSummary.swift`（已在 §1.7 列出）与 `AccountsRanking.swift`。

---

### 11. 本章对通用层的要求（汇总）

| 位置 | 要求 |
|---|---|
| `Sources/Sub2Core/APIError.swift` | 保留 `metadata: [String: String]`；409 混合渠道另解 `details`（`group_id` 为数字）；412 单独可识别；中间件字符串 `code` 兼容解码（附录 B L1） |
| `Sources/Sub2Core/APIClient.swift` : `request` | 增加返回响应头的变体；支持请求头 `If-Match` / `If-None-Match` 与 304（返回 `.notModified`）；`Idempotency-Key` 与 `X-Idempotency-Replayed` |
| 能力表 | AppModel 启动时读 `GET /admin/me` 的 `capabilities`，以 `Set<String>` 提供给本章判断 |
| 回执 | 统一 toast：文字 + 可选“撤销”或一个自定义按钮（读屏念按钮文字） |
| Face ID | 设置“高风险操作需要 Face ID”的统一门控函数 |
| 状态胶囊 | 列表与卡片共用组件，支持相邻连接（DECISIONS 第 138 行） |

---

### 接口核实清单（2026-10-22，sub2 main `70116315d`）

| 接口 | 源码位置 |
|---|---|
| `GET /admin/accounts`、`GET /admin/accounts/:id`、`POST /admin/accounts`、`PUT` / `PATCH` / `DELETE /admin/accounts/:id`、`POST /admin/accounts/check-mixed-channel` | `server/routes/admin.go:461-499`；`handler/admin/account_handler.go:713-1316` |
| `GET /admin/accounts/status-summary` | `admin.go:474`；`account_status_summary_handler.go` |
| `POST /admin/accounts/today-stats/batch`、`GET /admin/accounts/:id/today-stats` | `admin.go:513,515`；`account_handler.go:2756-2858` |
| `POST /admin/accounts/runtime/batch` | `admin.go:516`；`account_runtime_batch.go` |
| `GET /admin/accounts/:id/usage` | `admin.go:512`；`account_handler.go:2621-2650` |
| `POST /admin/accounts/:id/schedulable`、`:id/recover-state`、`:id/clear-error`、`:id/refresh`、`:id/apply-oauth-credentials`、`:id/reauthorize`、`:id/test`、`:id/test-runs`、`GET :id/test-runs/latest`、`GET :id/models` | `admin.go:500-523`；`account_handler.go`、`account_recover_state.go`、`account_clear_error.go`、`account_reauthorize.go`、`account_test_run_handler.go` |
| `GET /admin/account-test-runs/:run_id`、`GET /admin/accounts/:id/scheduled-test-plans`、`GET /admin/scheduled-test-plans/:id/results` | `admin.go:848-858`；`scheduled_test_handler.go` |
| `POST /admin/accounts/bulk-update`、`batch-clear-error`、`batch-refresh` | `admin.go:531-534` |
| `POST /admin/accounts/generate-auth-url`、`generate-setup-token-url`、`exchange-code`、`exchange-setup-token-code`；`/admin/openai/generate-auth-url`、`exchange-code`；`/admin/gemini/oauth/auth-url`、`exchange-code`；`/admin/antigravity/oauth/auth-url`、`exchange-code`；`/admin/grok/oauth/auth-url`、`exchange-code` | `admin.go:543-546,564-620` |
| `GET /admin/meta/catalog` | `admin.go:41`；`meta_handler.go`；`service/admin_meta_catalog.go` |
| `GET /admin/groups/all`、`GET /admin/proxies/all` | `admin.go:404,634` |
| `GET /admin/ops/upstream-errors` | `admin.go:313`；`ops_handler.go:473-571`（`IncludeRecoveredUpstream = true` 在第 504 行）；恢复行的 `status_code` 与 `message` 拼法 `handler/ops_error_logger.go:1296-1355`（`logOpsRecoveredUpstream`） |
| `POST /admin/accounts/:id/revert-proxy-fallback`；账号 DTO `proxy_fallback_origin_id` / `proxy_fallback_origin_name` | `admin.go:511`；`account_handler.go:1814-1827`；`service/admin_account.go:1572-1597`；`service/admin_proxy.go:271-311`；`service/account_service.go:16`；`dto/types.go:239-240,370-371` |
| `GET /admin/ops/alert-events`（`status`、`limit`、`platform`、`group_id`）；事件字段 `silence`、`rule`、`group_name` | `admin.go:256`；`ops_alerts_handler.go:612`；`repository/ops_repo_alerts.go:320-363,890-938`；`service/ops_alert_models.go:41-100` |
| `GET /admin/dashboard/accounts-ranking`、`GET /admin/dashboard/stats` | `admin.go:349,360`；`dashboard_handler.go:437-486` |
| `GET /admin/me` capabilities | `handler/admin/me_handler.go:17-81` |
| Web `/admin/accounts?edit=&search=` | `frontend/src/utils/accountDeepLink.ts` |

---

### 本章未决问题

1. **列表加载上限**：按平台分组需要全部行，本章定为 `page_size=500`、最多加载 2000 行，超出时提示用平台筛选。**建议默认**：2000；实测大站点（>2000 账号）后再决定是否改为“按平台懒加载分区”。
2. **新建 OAuth 账号的令牌经过手机**：新建流程只能 `exchange-code` 拿到令牌后由 App 构造凭据再 `POST /admin/accounts`（`reauthorize` 只能用于已有账号，`create-from-oauth` 不支持 `schedulable=false`）。**建议默认**：照 Web 做，令牌只在内存、不写日志、离开即丢；另请后端评估给 `create-from-oauth` 加 `schedulable` / `skip_default_group_bind`（或新增“换码并新建”接口）后切换。
3. **Bedrock / Vertex 账号的凭据类错误**：设计只画了 API Key 与 OAuth 的修复主按钮，手机端不编辑 AWS 密钥与 Service Account JSON。**建议默认**：这两类账号凭据类错误时主按钮“在 Web 中更换凭据”（打开 C19 深链），“恢复状态”“测试连接”仍为次要。
4. **新建时不选分组是否跳过默认分组**：后端支持 `skip_default_group_bind`，DECISIONS 未定。**建议默认**：与 Web 一致不传（自动加入 `<platform>-default`），表单脚注写明。
5. **重新授权停用账号**：后端已有 `preserve_status`，但 DECISIONS 第 113 行定为“确认框写明会重新启用”。**建议默认**：照决定，不传 `preserve_status`；如需“授权但保持停用”，以后在确认框加第二个按钮。
6. **定时测试是否进入主模式详情**：已定 inline 详情没有画；本章作为“记录”节的只读一行补上。**建议默认**：保留只读行，计划维护留在 Web。
7. **批量“恢复状态 / 刷新令牌”（设计稿之外的扩展）**：已定设计（DECISIONS 第 38 行，`v-accounts.jsx` 与 `00-core.jsx` 的 dock）只有“已选 N 个 · 停止调度 · 启用调度”；现有 App 另有批量“刷新凭据”。**建议默认**：照设计稿只做两个按钮，现有批量“刷新凭据”去掉；要加“⋯”菜单时按 §8.8 实现，先给用户看效果图再定。
8. **运维关闭时状态卡的出错时间行（设计稿之外的退路）**：设计稿只画了来自上游错误日志、可点进请求详情的“最近上游错误 … ›”；运维关闭或 24 小时内无日志时设计稿没有这一行。**建议默认**：有 C02 `error_at` 时显示不可点的“出错于 HH:MM · N 分钟前[ · {error_status_code}]”，没有就不显示；用户看过效果图后可改为直接不显示。
9. **账号详情代理行的点按去向**：设计稿里点代理行和点“编辑”都打开代理选择器；60 章把“账号详情的代理行”列为代理详情的入口。**建议默认**：本章的做法——有代理时点行 push 代理详情，选择器只从分区右上“编辑”进；用户看过效果图再定。

---

## 30 · 用户与 API Key（用户 Tab）

本章覆盖底部「用户」Tab 下的全部页面：用户列表（含快捷充值头像条）、用户详情、充值 / 退款键盘与待核对、充值与调整记录、新建用户、编辑用户（基础 · 权限与并发 · Key 与限额）。读者是照着实现 SwiftUI 页面的工程师。

- **设计依据**：`DECISIONS.md` 第 2 轮 Q10–Q12、第 3 轮 Q13–Q14 与文字题、整合后文字题、设计稿评审意见；设计稿 `html-preview/layouts/main/v-users.jsx`（列表、详情、记录页）、`v-user-edit.jsx`（新建 / 编辑，已定 `tabs` + `ueKeys: 'cards'`）、`00-core.jsx`（`KeypadSheet`、`UserDetail`、`userMenu`）、`shared/core.jsx`（`submitBalanceChange`、`reconcileUser`）。
- **后端基线**：sub2 `main` `70116315d`（2026-10-22）。本章每个接口路径、字段名、reason 都对过源码：路由 `backend/internal/server/routes/admin.go`（`registerUserManagementRoutes`、`registerAdminAPIKeyRoutes`、`registerUserAdjustmentRoutes`），handler `handler/admin/user_handler.go`、`apikey_handler.go`、`user_adjustment_handler.go`、`quick_topup_handler.go`、`user_platform_quota_item_handler.go`、`user_attribute_handler.go`，DTO `handler/dto/types.go`。
- **口径优先级**：后端适配清单“实现进度”表的备注 > 清单条目原文 > 设计稿注释。设计稿里写“需后端新增”的 Key 新建 / 停用 / 删除，E01 已上线，本章按真实接口写；设计稿“初始余额不会出现在充值与调整记录里”的文案，E10 上线后作废。
- 下文接口路径都写全（`/api/v1/...`）；“回执”指带“撤销”的底部 Toast；“确认框”指 `.alert` / `.confirmationDialog`；“状态胶囊”指全局统一的左侧悬浮胶囊（评审意见第 3 条，相邻粘连）。

---

### 0. 本章共用前提

#### 0.1 身份与能力探测

进入用户 Tab 前，会话层（见“会话与通用约定”章）已取到 `GET /api/v1/admin/me`。本章只读其中这些字段：

| 字段 | 本章用途 |
|---|---|
| `user.id` | 判断“本人”（详情档案“管理员 · 你”、编辑页角色锁定、⋯ 菜单提示）；待核对余额只允许同一管理员重试 |
| `user.role` | `vendor` 时整个用户 Tab 显示“供应商账号不能管理用户”（用户管理为站长专属，`/api/v1/admin/users` 对 vendor 一律 403） |
| `auth_method` | 与 `security.step_up_available` 一起判断揭示 Key、设为管理员能否进行（Admin Key 不能做二次验证） |
| `security.step_up_enabled` / `step_up_available` / `step_up_granted` / `step_up_expires_in` | 二次验证（见 0.4） |
| `server.run_mode` | `simple` 时 Key 的 `expired` / `quota_exhausted` 仍可调用（E06 审查修正），RPM 一律不计数（E08） |
| `server.server_timezone` | “本月消费”的月份边界按服务器时区 |
| `server.capabilities` | 下表的能力开关 |

| 功能 | 判定 | 缺失时（老服务端） |
|---|---|---|
| 管理员替用户新建 / 修改字段（含停用、启用）/ 删除 / 读取单个 Key（E01） | `GET /api/v1/admin/me` 返回 200 即可用（E01 早于 A02 上线，没有单独的 capability） | Key 区按设计稿原样画虚线占位“需后端新增”，点按只弹说明 |
| Key 掩码视图与揭示（E03） | `api_keys.masked_view` | 不带 `key_view`；收到完整 `key` 解码后立即丢弃，只用 `key_masked`（也没有时本地取后 4 位）；不提供“显示完整 Key” |
| Key 换分组 / 替换分组的精确撤销（E04） | 同 E01（`/admin/me` 可用） | 撤销走 0.6 的两步退路 |
| 快捷充值头像条（E05） | `users.quick_topup` | 不显示头像条 |
| `effective_status`（E06） | `api_keys.effective_status` | 本地推导（见 §7.3） |
| 平台限额单平台 PUT / DELETE / restore（E07） | `users.platform_quota_item` | 先 GET 再整表 `PUT .../platform-quotas`；撤销“取消限额”时提示“已用额度会从 0 重新计算” |
| RPM 计数标记 `tracked`（E08） | `users.rpm_tracked` | limit 为 0 的行写“不限 · 不计数”，不显示 used |
| 账本前后余额、总充值拆分、新建用户初始余额入账、`PUT` 带 balance 返回 400（E10） | `users.balance_ledger` | 记录行没有前后余额；新建用户的初始余额确认框改用“创建时直接写入，不会出现在充值与调整记录里” |
| 管理端 Key 列表回填当前并发（E11） | `api_keys.current_concurrency` | “当前并发”显示“—” |
| 用户、分组等写接口接受可选 Idempotency-Key（G06） | `admin.idempotent_writes` | `PUT /api/v1/admin/users/:id` 只在带 `concurrency` 时带 key；创建与其他编辑超时后不自动重发，读回核对 |
| 列表 ETag / 304 | `lists.etag` | 不带 `If-None-Match` |

#### 0.2 写操作通用规则（本章特有的部分，其余见通用约定）

1. **Idempotency-Key**：资金写（余额调整）强制带；新建用户、编辑用户、启用 / 禁用用户、新建 Key、替换分组在有 `admin.idempotent_writes`（替换分组与新建 Key 不需要能力，接口本身接受可选 key）时都带。key 用 UUID（小写），**在请求体冻结时生成**，同一请求体的重试沿用；请求体变了必须换新 key（否则 409 `IDEMPOTENCY_KEY_CONFLICT`）。
2. **响应头**要能读到（`APIClient` 现在只返回 data，需加一个带响应头的变体，见 §10）：`X-Idempotency-Replayed: true`（重放，回执改成“此前已执行，未重复操作”）、`X-Idempotency-Expires-At`、`X-Idempotency-Degraded: result-committed`（结果可信，但之后同 key 重发可能 409，按读回核对）、`X-Admin-Adjustment-Action-ID`、`Retry-After`。
3. **409 的处理按 reason 分**（`docs/API_ERROR_CODES.md`）：`IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` → 按 `Retry-After` 秒后同 key 原样重试；`IDEMPOTENCY_KEY_CONFLICT` → 不重试，提示“请求已变化，请重新提交”；`IDEMPOTENCY_STORE_UNAVAILABLE`（503）→ 没执行，保留原请求稍后同 key 重试，不换 key。
4. **业务错误没有 reason 的几处**（后端用普通 `errors.New`，经 `ErrorFrom` 变成 500 `internal error`、reason 为空）：不能禁用管理员、不能删除管理员、不能降级最后一个管理员、余额扣成负数、专属倍率 ≤ 0。App 一律**事前拦截**（见各节），收到 500 且无 reason 时显示通用“服务器未能完成请求”，资金写按“结果待核对”处理。
5. **只读管理访问令牌**：写接口返回 403 `ACCESS_TOKEN_READ_ONLY` 时显示“当前登录的是只读令牌，不能修改”，不重试。
6. **Face ID**：设置里“高风险操作需要 Face ID”打开时（默认关，门槛默认 $100，见设置章），本章覆盖：删除用户、删除 Key、超过门槛的充值 / 退款、超过门槛的新建用户初始余额、发放余额补偿超过门槛。揭示完整 Key **总是**先做一次本机身份验证（`LAContext` `.deviceOwnerAuthentication`），不受开关影响。Face ID 打开时删除确认框的按钮写“用 Face ID 删除”，关闭时要输入完整名称才能点。

#### 0.3 显示名与文案

- **用户显示名**：`username` 去空白后非空用它，否则用 `email` 的 `@` 之前部分；头像字母取显示名第一个字符（字母转大写）。
- **用户状态词**：`active` →「启用」，`disabled` →「禁用」（句中可写“已禁用”）。用户不写“正常 / 停用”。
- **角色词**：`user` →「用户」，`vendor` →「供应商」，`admin` →「管理员」。（现有 App 的“普通用户 / 代运营”要改。）
- **Key 状态词**：活跃 / 已停用 / 额度耗尽 / 已过期（见 §7.3）。
- 金额显示沿用通用约定（Decimal，两位，`$1,020.00`，负数 `−$3.00`）；缺失值 `—`，0 显示 `$0.00`。

#### 0.4 二次验证（step-up）

需要 step-up 的只有两处：把用户设为 / 新建为管理员（`EnforceStepUp`，`user_handler.go:303-307, 398-409`）、揭示完整 Key（`POST /api/v1/admin/api-keys/:id/reveal` 挂 `stepUpAuth`）。

- `security.step_up_enabled == false`：服务端直接放行（含 Admin Key），App 不弹验证码。
- 开启且 `step_up_granted == true`：直接发请求。
- 开启且未授予：弹设计稿的 6 位验证码 sheet（填满自动提交，`textContentType(.oneTimeCode)`），`POST /api/v1/user/totp/step-up {"code":"123456"}` → `verified` 为 true 后继续原流程（设为管理员还要再确认一次，见 §6.4）。
- 开启且 `step_up_available == false`：Admin Key / 管理访问令牌登录 →“Admin Key 登录不能做二次验证，请改用账号登录后再操作”；账号没开 TOTP →“需要先在 Web 端开启二次验证”（设计稿 `ueNoTotp` 状态），按钮“知道了”。
- 服务端仍返回 403 `STEP_UP_REQUIRED`（授予已过期）：重新弹验证码，验证后用**同一个** Idempotency-Key 重发（step-up 拒绝发生在幂等封装之前，不占用 key）。

#### 0.5 待核对余额（本地状态）

“待核对”只存在本机：余额写请求发出后没拿到确定结果时，原请求保留在 `AppModel.pendingBalances`（文件保护存储，已有）。详情横幅、列表标记、头像条排序、概览“待处理”都读这一份。数据结构与核对流程见 §3。

#### 0.6 回执与撤销的退路（E04 不可用时）

- Key 换分组撤销：先 `PUT /api/v1/admin/api-keys/:id {"group_id": <原分组或 0>}`；当时新授予过专属分组的，再 `GET /api/v1/admin/users/:id` 取最新 `allowed_groups`，去掉该分组后 `PUT /api/v1/admin/users/:id {"allowed_groups": [...]}`；第二步失败提示“Key 已还原，但分组授权没收回，请在权限与并发里手动移除”。
- 替换分组撤销：调反向 `replace-group`；替换前用户已有新分组、或新分组下原本就有 Key 时，回执不给“撤销”。

---

### 1. 用户列表（Tab 首页，含快捷充值头像条）

设计稿：`v-users.jsx` 的 `VuUsersQuick`（`users: 'quick'` + `usersRows: 'cols'`）。DECISIONS 第 2 轮 Q11、Q12，默认处理“最新在前”。

#### 1.1 入口与导航

- 底部 Tab「用户」的根页面；`NavigationStack` 根。
- 导航栏：标题“用户”（居中，不用大标题；与账号页一致，大标题只给概览 / 监控 / 搜索），副标题“<站点名> · N 位”；右上 `+` → 新建用户（§5）。
- 搜索框（`.searchable`，占位“邮箱、用户名或备注”）：点了才弹键盘。
- 点头像条里的头像：没有待核对 → 打开充值键盘 sheet（§3，mode = 充值）；有待核对 → push 用户详情（去核对）。
- 点列表行 → push 用户详情（§2）。
- vendor 身份：整页空态“供应商账号不能管理用户”，不发请求。

#### 1.2 数据来源

| 用途 | 接口 | 关键参数 | 说明 |
|---|---|---|---|
| 用户列表 | `GET /api/v1/admin/users` | `page`、`page_size=20`、`sort_by=created_at`、`sort_order=desc`、`include_subscriptions=false`、`search`（去空白，最多 100 字符，服务端会截断） | 分页信封 `{items,total,page,page_size,pages}`；每项是 `AdminUser` + `current_concurrency`。搜索命中邮箱、用户名、备注与 Key 片段（`repository/user_repo.go:553-559`）。有 `lists.etag` 时第 1 页带 `If-None-Match`，304 保留现有数据 |
| 头像条 | `GET /api/v1/admin/users/quick-topup` | `recent_limit=8`、`low_limit=8`、`recent_days=30`（默认值即这三项，可不传） | `{recent:[...], low_balance:[...], low_balance_enabled}`。需 `users.quick_topup` |
| 每行今日消费 | `POST /api/v1/admin/dashboard/users-usage` | `{"user_ids":[...]}`，每批 ≤ 200（服务端上限 1000，E12） | `{stats:{"<user_id>":{user_id,today_actual_cost,total_actual_cost,by_platform}}}`；服务端 30 秒缓存，缓存键带日期 |
| 全局余额低阈值 | `GET /api/v1/settings/public` | — | `balance_low_notify_enabled`、`balance_low_notify_threshold`；会话内缓存，设置章已在拉 |

列表项用到的 `AdminUser` 字段：`id`、`email`、`username`、`status`、`role`、`balance`、`total_recharged`、`balance_notify_threshold`（可空）、`balance_notify_threshold_type`（`fixed` / `percentage`）、`created_at`。

#### 1.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 副标题 | 站点名 + 第 1 页响应的 `total` | “<站点> · 128 位” | 首次加载前只写站点名 |
| 头像条标题 | 固定 | “快捷充值”，右侧小字“最近调整 · 余额低” | `recent` 与 `low_balance` 都为空、或缺能力、或请求失败：整块不显示（不报错） |
| 头像顺序 | `recent`（服务端已按最近调整倒序）在前，再接 `low_balance` 中未出现过的 `user_id` | 横向 `ScrollView`；本机有待核对的用户挪到最后 | — |
| 头像 | 显示名首字 | 右下角小徽标：普通为 ＋；待核对为 docCheck | — |
| 头像下第一行 | 显示名 | 单行截断 | — |
| 头像下第二行 | 项里的 `balance` | `$12.40`；待核对写“去核对” | — |
| 头像读屏 | — | “给王小明充值，余额 $12.40” / “王小明，上一笔充值待核对，打开详情去核对” | — |
| 列表头 | 固定 | 左侧图例：实心点“余额低”、docCheck“待核对”、减号“禁用”；右侧“余额 / 今日消费” | — |
| 行头像 | 显示名首字 | 圆形字母头像 | — |
| 行第一行 | 显示名 | | — |
| 行第二行 | `email` | 次要色，单行截断 | — |
| 右列第一行 | `balance` + 状态标记 | `$1,020.00`；标记只取一个，优先级 待核对 > 禁用 > 余额低（三种形状不同，不靠颜色区分） | 解码失败 `—` |
| 右列第二行 | `stats[id].today_actual_cost` | “今日 $2.80” | 批量请求失败或还没返回：“今日 —”；响应里没有这个 id：`$0.00` |
| 行状态胶囊 | 本机待核对 | caution 色状态胶囊（与概览待处理同一规格，相邻粘连） | — |
| 行变暗 | `status == "disabled"` | 整行次要色（is-idle） | — |
| 行尾 | — | chevron | — |

**余额低判定**（列表行、详情头部共用一个纯函数，与 `quick-topup` 的 SQL 同口径，`repository/admin_quick_topup_repo.go:77-96`）：

```
仅当 status == "active"：
  base = balance_notify_threshold ?? (全局开关开 && 全局阈值 > 0 ? 全局阈值 : nil)
  base == nil → 不标
  threshold = (balance_notify_threshold_type == "percentage" && total_recharged > 0)
              ? total_recharged × base ÷ 100
              : base
  threshold > 0 && balance < threshold → 标“余额低”
```

注意：用户自己设的阈值在全局开关关闭时也生效；`percentage` 且 `total_recharged` 为 0 时服务端把阈值当美元数使用，App 跟服务端一致（见未决问题 3）。不要用设计稿写死的 $10。

#### 1.4 交互与写操作

- 本页没有直接写操作。充值走 §3 的键盘 sheet；sheet 成功后刷新头像条（重新请求 `quick-topup`）并用响应里的 `balance` 原地更新该用户所在行。
- 搜索：输入防抖 300 ms 后从第 1 页重新请求；搜索非空时隐藏头像条；清空恢复。
- 翻页：滚到最后一行出现时请求下一页（`page < pages`），新页按 `id` 去重追加，并为新页的 id 补一次 `users-usage`。
- 下拉刷新：重新请求第 1 页（带 ETag）、头像条、已加载行的今日消费。

#### 1.5 状态

| 状态 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 列表骨架（3–5 行占位） | — |
| 空（无搜索） | “还没有用户” + 按钮“新建用户” | 进 §5 |
| 空（有搜索） | “没有匹配“<关键词>”的用户” | “清除搜索” |
| 列表加载失败、已有旧数据 | 保留旧数据，顶部横幅“刷新失败 · <时间> 的数据” | “重试” |
| 列表加载失败、没有数据 | 整页错误“加载用户失败” + 原因（按 reason / HTTP 状态取通用约定 §3.2、§3.3 的中文文案，不显示服务端 message） | “重试” |
| 今日消费失败 | 只影响右列第二行“今日 —” | 下次刷新自动重试 |
| 头像条失败 | 不显示头像条 | 下次刷新自动重试 |
| 403 `FORBIDDEN` | “当前身份不能管理用户” | — |
| 401 / 423 | 走全局会话处理 | — |
| 400 `TOO_MANY_IDS`（`users-usage`） | 不会出现（每批 ≤ 200）；万一出现按 `metadata.max` 拆批重试 | — |
| 400 `INVALID_LIMIT` / `INVALID_RECENT_DAYS`（`quick-topup`） | 不会出现（App 用默认值）；出现时隐藏头像条 | — |

#### 1.6 刷新策略

- 进入 Tab、App 回到前台、下拉刷新：刷新第 1 页 + 头像条 + 已加载行的今日消费。
- Tab 可见且 App 在前台时每 60 秒做一次同样的刷新（DECISIONS 第 2 轮“前台自动刷新约 60 秒”）；第 2 页以后不自动刷新。
- 第 1 页带 `If-None-Match`（`lists.etag`），304 时只刷新今日消费；注意用户内嵌的状态在服务器时钟变化时也会让 ETag 变（E06 部署注意），304 命中率不保证。
- 不适用 `since_id`。
- 从详情 / 编辑页返回时：用详情页最后一次拿到的 `AdminUser` 原地替换该行（不整页重拉）。

#### 1.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: UsersView`：
  - 删掉“状态” `Picker` 与工具栏“显示字段”（`ListFieldSelection<UserListField>` 留给以后的简化模式，主模式不用）。
  - 行改为设计稿 `cols` 布局（左：头像 + 显示名 + 邮箱；右：余额 + 标记 / 今日）；`List` 保留（以后的滑动操作、多选）。
  - 加头像条（新视图 `QuickTopupStrip`）、列表头图例、副标题“N 位”。
  - `load(nextPage:)` 增加 `sort_by=created_at&sort_order=desc&include_subscriptions=false`；加 `users-usage` 批量请求与 60 秒前台定时刷新；`.task(id: query)` 的防抖保留。
- `Sources/Sub2Core/APIClient.swift: users(page:search:status:)`：参数改为 `UserListQuery`（search、page、sort），返回同时带 ETag；新增 `quickTopup()`、`usersTodayUsage(ids:)`。
- `Sources/Sub2Core/Models.swift: AdminUser`：补 `totalRecharged`、`balanceNotifyThreshold`、`balanceNotifyThresholdType`、`allowedGroups`、`groupRates`、`restrictPublicGroups`；`init(from:)` 里多余的 `userCost` / `standardCost` 两行（AdminUser 没有这两个键）删掉。
- 新增 `Sources/Sub2Core/UserPresentation.swift`：`displayName(_:)`、`initial(_:)`、`isLowBalance(user:global:)`、`statusWord`、`roleWord`（纯函数，配单测）。
- 新增 `NativeApp/Features/Users/QuickTopupStrip.swift`。

---

### 2. 用户详情

设计稿：`v-users.jsx` 的 `VuHeroDetail`（`userDetail: 'hero'`），⋯ 菜单是 `00-core.jsx` 的 `userMenu`。DECISIONS 第 2 轮 Q10、第 3 轮文字题（“充值与调整记录”改名、发放补偿、停用用户可充值）。

#### 2.1 入口与导航

- 进入：用户列表行、头像条（待核对时）、概览“待处理 · 充值结果待核对”、搜索结果、使用记录 / 请求详情的“用户”行。
- 导航栏：标题 = 显示名，副标题 = 邮箱；返回；右上 ⋯（见 2.4）。
- 页内去处：API Key 摘要行 → 编辑用户并定位到「Key 与限额」段（§7）；“使用记录 ›” → 使用记录页（`{scope: usage, user: id}`，见使用记录章）；“全部 N 条 ›” → 充值与调整记录（§4）；充值 / 退款 → 键盘 sheet（§3）；⋯ → 编辑用户（§6）。

#### 2.2 数据来源

进入页面时并发请求：

| 用途 | 接口 | 关键参数 |
|---|---|---|
| 用户资料 | `GET /api/v1/admin/users/:id` | — | 
| 今日消费 | `POST /api/v1/admin/dashboard/users-usage` | `{"user_ids":[id]}` → `stats[id].today_actual_cost` |
| 本月消费 | `GET /api/v1/admin/usage/stats` | `user_id=<id>`、`start_date=<服务器时区本月 1 日>`、`end_date=<服务器时区今天>`、`timezone=<server.server_timezone>` → `total_actual_cost` |
| Key 摘要 | `GET /api/v1/admin/users/:id/api-keys` | `key_view=masked`（有 `api_keys.masked_view` 时）、`sort_by=id`、`sort_order=asc`、`page_size=100`（`pages > 1` 时继续翻页取全） |
| 记录前 5 条与总充值 | `GET /api/v1/admin/users/:id/balance-history` | `page=1`、`page_size=5` → `items`、`total`、`total_recharged` |
| 余额低阈值 | 同 §1.2（会话缓存） | — |

`GET /api/v1/admin/users/:id` 返回 `AdminUser`（含 `notes`、`last_used_at`、`group_rates`、`restrict_public_groups`、`allowed_groups`），**不含** `current_concurrency`。

#### 2.3 字段 → 显示映射

从上到下：待核对横幅 → 已禁用横幅 → 余额头部 → 壹 API Key → 贰 充值与调整记录 → 叁 档案。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 待核对横幅 | 本机 `pendingBalances` 中 `serverID == 当前站点 && userID == id` 的最早一条 | 标题“充值 $50.00 结果待核对”（退款写“退款”），副文“<相对时间>发起，未收到服务器确认”；caution 状态胶囊；右侧按钮“核对” | 没有待核对：不显示 |
| 已禁用横幅 | `status == "disabled"` | 标题“已禁用”，副文“不能登录，名下的 Key 也不能调用”；按钮“启用” | 不显示 |
| “可用余额” | `balance` | 大号金额（xl） | `—` |
| 余额副行 | 今日 `today_actual_cost`、本月 `total_actual_cost` | “今日消费 $2.80 · 本月 $86.10”；余额低时行尾徽章“余额低”（caution） | 今日失败写“今日消费 —”；本月失败整段“· 本月 …”不显示 |
| 充值按钮 | — | 主按钮“＋ 充值”；有待核对时降为次要样式（点了先问，见 3.4） | — |
| 退款按钮 | — | 次要按钮“退款” | — |
| 壹 · API Key 标题 meta | Key 数、活跃数 | “3 个 · 活跃 2”；没有 Key 时“0 个” | 请求失败：meta 不显示，行内“Key 加载失败 · 重试” |
| Key 摘要行第一行 | 各 Key `name` | 用“、”连接 | 没有 Key：“还没有 Key” |
| Key 摘要行第二行 | 三段，用“ · ”分隔，段内用“、” | ① 去重后的分组名（`group_id` 为空写“未绑定分组”，分组名来自分组目录）② 不能调用的 Key：“<名称> 已停用 / 额度耗尽 / 已过期”③ 最近使用：所有 Key `last_used_at` 的最大值，“最近使用 3 分钟前”，都为空写“未使用” | 没有 Key：E01 可用时“可以在编辑用户里新建”；不可用时“用户在 Web 端创建 Key 后显示在这里” |
| Key 摘要行点按 | — | push 编辑用户 `seg: keys` | — |
| “使用记录”行 | — | 标题“使用记录”，右侧次要字“用量明细 · 错误请求” | — |
| Key 区脚注 | 固定 | “换分组、速率限制、平台限额都在“编辑用户 · Key 与限额”，立即生效。” | — |
| 贰 · 充值与调整记录 meta | `total_recharged` | “总充值 $60.00”（以 balance-history 为准，不用 `users.total_recharged`） | 记录为空：不显示 meta |
| 记录行 | 见 §4.3 的单行映射 | 最多 5 条 | 空：“暂无记录” |
| “全部 N 条 ›” | `total > 5` | — | `total ≤ 5` 不显示 |
| 叁 · 档案 | `id`、`status`、`role`、`concurrency` | 用户 ID（数字）；状态“启用 / 禁用”；角色“用户 / 供应商 / 管理员”，本人加“ · 你”；并发上限（0 写“不限制”） | `concurrency` 缺失 `—` |

不显示：`frozen_balance`、`balance_notify_extra_emails`（隐私）、`allowed_groups`（分组跟着 Key 走，档案里不写分组）。

#### 2.4 交互与写操作

**⋯ 菜单**（SwiftUI `Menu`，删除项红字放最后，不需要“取消”项）：

| 项 | 显示条件 | 动作 |
|---|---|---|
| 编辑用户 | 总是 | push §6 |
| 禁用用户 / 启用用户 | `role != "admin"` | 直接执行（可逆），见下 |
| 发放兑换码（补偿）… | 总是 | 打开发放补偿 sheet（向导与接口见“兑换码”章；本章只负责入口与成功后的刷新） |
| 删除用户… | `role != "admin"` | 确认后删除，见下 |
| 菜单说明 | 本人：“这是你当前登录的账号。管理员不能禁用或删除。”；其他管理员：“管理员不能禁用或删除。” | — |

管理员不显示禁用 / 删除，因为后端对管理员返回无 reason 的 500（`service/admin_user.go:223, 474`）。

**启用 / 禁用**

- 请求：`PUT /api/v1/admin/users/:id`，body `{"status":"disabled"}` 或 `{"status":"active"}`；有 `admin.idempotent_writes` 时带 Idempotency-Key。
- 成功：用响应的 `AdminUser` 替换本页数据；回执：禁用“已禁用 王小明 · 2 个 Key 停止调用”（N = 当前活跃 Key 数，0 时省略后半句），启用“已启用 王小明”；都带“撤销”（再发反向 status）。
- 已禁用横幅里的“启用”同一动作。
- 失败：见 2.5。

**删除用户**

- 确认框：标题“删除用户「王小明」？”，第一行“站点 <站点名>”，第二行“名下 2 个 Key 一并删除。”（后端删除用户时一起删掉 Key；N 为 Key 总数，0 时省略）；Face ID 关：输入框要求输入完整显示名（用户名为空时输入邮箱）后“删除”才可点；Face ID 开：按钮“用 Face ID 删除”。
- 请求：`DELETE /api/v1/admin/users/:id` → `{"message":"User deleted successfully"}`；不带 Idempotency-Key（重发得到 404，可安全判断）。
- 成功：先 pop 回列表，再从列表移除该行；回执“已删除用户「王小明」”，不可撤销。
- 404 `USER_NOT_FOUND`：视为已删除，同成功处理。

**发放补偿成功后**：刷新本页的用户资料（余额 / 并发）与记录前 5 条。

#### 2.5 状态

| 状态 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 头部骨架；各分区各自加载 | — |
| 用户资料失败 | 整页错误“加载用户失败” | “重试” |
| 404 `USER_NOT_FOUND` | “这个用户不存在或已删除” | 返回列表并移除该行 |
| 分区失败（今日 / 本月 / Key / 记录） | 只在该分区显示“加载失败 · 重试”，其他分区照常 | 分区内“重试” |
| 启用 / 禁用 500 且无 reason | 回执“操作失败：服务器未能完成请求”（多为对管理员操作） | 刷新用户资料 |
| 写操作 403 `ACCESS_TOKEN_READ_ONLY` | “当前登录的是只读令牌，不能修改” | — |
| 写操作 409 `IDEMPOTENCY_IN_PROGRESS` / `RETRY_BACKOFF` | 静默按 `Retry-After` 同 key 重试，最多 30 秒；仍失败回执“结果未确认，已刷新为服务器当前状态”并 GET 读回 | — |

#### 2.6 刷新策略

- 进入时加载全部分区；下拉刷新同。
- 页面可见且前台时每 60 秒刷新“用户资料 + 今日消费”（余额、状态会被计费与其他管理员改动）；Key、记录、本月不轮询。
- 写操作后：启用 / 禁用用响应替换资料；充值 / 退款用响应的 `balance` 并重拉记录前 5 条；从编辑页返回时重拉资料、Key、记录。

#### 2.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: UserDetailView` 重写为设计稿 hero 布局；“管理操作”分区（编辑 / 禁用 / 调整余额按钮）删掉，改成 ⋯ 菜单 + 余额头部按钮。
- `reload()` 改为并发加载各分区、分区各自的错误状态；`userUsage(id:)` 改用 `total_actual_cost`（现在读的 `total_cost` 是标准计费，不是实际扣费）并按服务器时区算月份（`APIClient.monthRange()` 现在用手机日历）。
- `changeStatus()`：确认框去掉（可逆操作直接执行 + 回执撤销），加 Idempotency-Key。
- `Sources/Sub2Core/APIClient.swift`：新增 `deleteUser(id:)`、`setUserStatus` 带可选幂等 key；`userKeys(id:page:)` 加 `key_view=masked`、排序与 `page_size=100`。
- 建议拆出 `NativeApp/Features/Users/UserDetailView.swift`。

---

### 3. 充值 / 退款键盘与待核对

设计稿：`00-core.jsx` 的 `KeypadSheet`（第 1 轮 Q“充值 / 退款 = B 大数字键盘”），`shared/core.jsx` 的 `submitBalanceChange`、`reconcileUser`；第 3 轮文字题“键盘上方加一行可选备注”“停用用户可以充值 / 退款”。后端：G01、G02，`POST /api/v1/admin/users/:id/balance`（`executeAdminMoneyWriteJSON`：强制 key、断开后仍执行完、可接管卡住的执行、账本按 action_id 去重）。

#### 3.1 入口与导航

- 用户详情的“充值 / 退款”、编辑用户身份条的“充值 / 退款”胶囊、列表头像条的头像。
- 以 sheet 打开（`presentationDetents([.large])`），顶部分段“充值 | 退款”可切换；关闭回到原页面。

#### 3.2 数据来源

| 用途 | 接口 | 关键参数 |
|---|---|---|
| 余额调整 | `POST /api/v1/admin/users/:id/balance` | 头：`Idempotency-Key: <op.id>`、`X-Request-ID: <op.id>`；body `{"balance":"50","operation":"add","notes":"补偿 10/16 故障"}`（`balance` 是十进制字符串，最多 8 位小数，≤ 999999999999.99999999；`operation` ∈ `add` / `subtract` / `set`） |
| 核对 | `GET /api/v1/admin/user-adjustments` | 第一次：`user_id=<id>`、`kind=balance`，再加 `action_id=<uuid>`（拿到过响应头时）或 `request_id=<op.id>`；`page_size=20`。第二次（第一次没有匹配行时）：`keyword=<邮箱>`、`kind=balance`、`start_time`、`end_time`、`page_size=200`。`request_id` / `action_id` / `user_id` 三个筛选是 G02 才加的，且没有 capability，旧服务端会静默忽略，所以**两次都只按本地复核的结果判定**，不看 `total`（见 3.4“核对”） |

成功响应 data 是 `AdminUser`；响应头 `X-Admin-Adjustment-Action-ID`（带 key 时总有）、`X-Idempotency-Expires-At`、重放时 `X-Idempotency-Replayed: true`、回显的 `X-Request-ID`。

核对接口每项字段：`id`、`action_id`、`kind`、`operation`、`requested_value`、`delta`、`before_value`、`after_value`（金额都是 8 位小数字符串）、`user_id`、`user_email`、`operator_user_id`、`operator_email`、`notes`、`request_id`、`source`、`created_at`。

#### 3.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 分段 | 本地 mode | “充值 / 退款” | — |
| 用户行 | 显示名、`balance`、`status` | “<头像> 王小明 · 余额 $12.40”；禁用用户加徽章“已禁用” | — |
| 备注行 | 本地输入 → body `notes` | 标签“备注”，占位“可选，写进充值记录”，有内容时右侧清除按钮 | 空则发 `""` |
| 金额大字 | 本地输入 | 充值“$50”，退款“−$50”；空时灰色“$0” | — |
| 预览行 | `balance ± 金额` | “充值后余额 $62.40” / “退款后余额 $2.40”；退款超过余额时 critical 色“超过当前余额”；未输入“输入金额” | — |
| “全部余额”胶囊（仅退款） | `balance` | “全部余额 $12.40” | 余额 ≤ 0 时不显示 |
| 数字键盘 | — | 1–9、`.`、0、删除；**数字总数最多 7 位（含小数部分，小数点不算）**，最多 2 位小数（同设计稿 `KeypadSheet`：`cur.replace('.', '').length >= 7` 时不再接受任何数字或小数点）；空时按 `.` 无效；当前是“0”时再按数字替换掉 0 | — |
| 提交按钮 | — | “充值 $50.00” / “退款 $50.00”；金额为 0 或退款超过余额时禁用 | — |

**确认框**（`submitBalanceChange` 原样）：

- 标题：“向「王小明」充值 $50.00？”/“向「王小明」退款 $50.00？”
- 正文逐行：“站点 <站点名> · 余额 $12.40 → $62.40”；有备注时“备注：<备注>”；禁用用户充值“该用户已禁用。\n充值后仍不能调用，需先启用。”，退款“该用户已禁用。”；Face ID 开且金额超过门槛“超过 $100，确认后验证 Face ID。”
- 按钮：“充值 $50.00”（destructive 样式）/“取消”。
- “全部余额”且之后没改过数字：标题“向「王小明」退款全部余额？”，正文“站点 … · 余额 $12.40 → $0.00\n按服务器执行时的余额归零。”；请求改发 `{"balance":"0","operation":"set"}`（原子归零，避免确认期间计费扣款导致 subtract 超额失败）。

#### 3.4 交互与写操作

**提交流程**

1. 点提交 → 确认框 → 确认 →（Face ID 开且金额 > 门槛）本机验证，失败或取消则不发送。
2. 生成 `PendingBalanceOperation`（`id` = UUID，同时作 Idempotency-Key 与 X-Request-ID；记下 `serverID`、`userID`、用户显示名与邮箱、`amount`、`operation`、`notes`、`actorUserID = me.user.id`、`createdAt`），**先落盘**（`AppModel.remember`）再发送；请求体字节冻结。
3. 客户端超时 40 秒（服务端带 key 的执行上限 30 秒）。
4. 任何响应（含 409、5xx）只要带 `X-Admin-Adjustment-Action-ID`，先把它写进 `op.actionID` 并落盘，再按下表判定（服务端在执行前就设这个头，`handler/admin/user_handler.go:488-490`；核对时用它精确查找）。
5. 结果判定：

| 结果 | 处理 |
|---|---|
| 200 | `resolve` 掉待核对；用响应 `balance` 更新详情 / 列表 / 身份条；关闭 sheet；回执“已向 王小明 充值 $50.00”（重放时“这笔此前已入账，没有重复执行”） |
| 200 + `X-Idempotency-Degraded: result-committed` | 同 200 |
| 409 `IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` | sheet 显示“正在等待服务器结果…”，按 `Retry-After` 秒后同 key 同 body 重发，累计等待超过 45 秒仍是这两个码 → 转“结果待核对”（关闭 sheet，回执“结果未确认，已记为待核对”） |
| 400 `INVALID_BALANCE` | 确定未执行：`resolve`，sheet 内提示固定文案“金额不合法，未入账”（服务端三种 message 都是这个 reason、没有 `metadata`，不区分也不回显；本地已按同一规则拦截：最多 8 位小数、≤ 999999999999.99999999、充值 / 退款要 > 0，正常不会出现）；“详情”按通用约定 §3.4 |
| 400 `IDEMPOTENCY_KEY_INVALID` / `IDEMPOTENCY_KEY_REQUIRED` | 确定未执行（App 缺陷）：`resolve`，提示“请求格式错误，未入账” |
| 400 且无 reason（请求体解码失败，handler 在执行前返回 `Invalid request: …`） | 确定未执行（App 缺陷）：`resolve`，提示“请求无效（错误码 HTTP 400），未入账”（通用约定 §3.3 的 400 兜底，不回显 message） |
| 409 `IDEMPOTENCY_KEY_CONFLICT` | 不应出现（body 冻结）；保留待核对，提示“这个操作编号已被另一笔请求占用，请先核对” |
| 404 `USER_NOT_FOUND` | `resolve`，提示“用户不存在或已删除” |
| 401 / 403（含 `ACCESS_TOKEN_READ_ONLY`） | 鉴权在执行前拒绝：`resolve`，按全局 / 只读令牌提示 |
| 503 `IDEMPOTENCY_STORE_UNAVAILABLE` | 没执行但不确定何时恢复：保留待核对，提示“服务器暂时无法受理，稍后用同一编号重试” |
| 500 且无 reason（如退款超额被拒） / 其他 5xx / 网络错误 / 超时 | 保留待核对；回执“结果未确认，已记为待核对”；详情页出现横幅 |

**有待核对时再充值 / 退款**（设计稿 `vuTopup`；这是通用约定 §2.5.4 第 4 条“核对完成前禁止同类写入”的例外，要经两次确认，见 §9）：

- 只拦同方向：该用户有待核对的充值时拦新的充值；有待核对的退款（含“全部余额”）时拦新的退款。反方向不拦（不会重复入账或重复扣款）。设计稿只画了充值，退款按同一规则，文案里的“充值”换成“退款”。
- 第一次确认（点充值按钮、身份条“充值 / 退款”胶囊时）：标题“上一笔 $50.00 充值结果未确认”，正文“先核对可避免重复入账”，按钮“先核对”（执行下面的核对）、“仍要充值”（打开键盘）、“取消”。充值按钮在有待核对时降为次要样式。
- 第二次确认（键盘提交时 3.3 的确认框）：正文第一行加“上一笔 $50.00 充值还没核对。如果它其实已入账，这一笔会再入账一次。”，确认按钮改为“仍要充值 $50.00”（destructive）；其余行与 Face ID 规则不变。键盘打开期间才出现的待核对（另一处发起的）同样加这一行。
- 新的一笔用新编号单独落盘，上一笔保持待核对、单独核对；横幅显示最早的一条，核对完再显示下一条。

**核对**（横幅“核对”、概览待处理、设置里的待核对列表、回到前台的自动核对都调同一个函数，只查不执行）：

判定**只看本地复核，不看 `total`**。`request_id` / `action_id` / `user_id` 三个筛选是 G02 才加的（`handler/admin/user_adjustment_handler.go:170-187`），`/admin/me` 的 capability 清单里没有对应项（`handler/admin/me_handler.go`），旧服务端会静默忽略这三个参数，返回全站最近的余额调整，`total ≥ 1` 不能说明这笔已入账。

匹配规则（纯函数，放 `BalanceReconciliation.swift`）：一行算“就是这笔”，要同时满足 `kind == "balance"`、`user_id == op.userID`，并且满足下面任一条：
- 有 `op.actionID`，且该行 `action_id` 与它相等（按 UUID 比较，不区分大小写）；
- 站点没有标 `requestIDUnreliable`，且该行 `request_id == op.requestID`。

1. 第一次查询：`GET /api/v1/admin/user-adjustments?kind=balance&user_id=<id>&page_size=20`，有 `op.actionID` 时加 `action_id=<op.actionID>`，否则加 `request_id=<op.requestID>`；按匹配规则在 `items` 里找。
2. 第一次没有匹配行（包括 `total ≥ 1` 但都是别的记录）：第二次查询，即通用约定 §2.5.5 的旧服务端退路：`keyword=<op.userEmail>&kind=balance&start_time=<op.createdAt − 2 分钟>&end_time=<现在>&page_size=200`（时间用 UTC `Z`）；仍按匹配规则找。`keyword` 是模糊匹配（也会命中包含这个邮箱的其他邮箱，`repository/admin_user_adjustment_repo.go:112-117`），所以 `user_id` 相等这一条不能省。
3. 找到：服务器已执行。`resolve`；回执“已核对：服务器已入账 $50.00（余额 $12.40 → $62.40）”（退款写“已扣除”；金额与前后余额取该行的 `delta`、`before_value`、`after_value`）；刷新用户资料与记录。
4. 两次都没找到：
   - 距 `op.createdAt` 不到 40 秒（服务端执行上限 30 秒加余量）：提示“服务器可能还在执行，请稍后再核对”，保留待核对，不给重试。
   - 不能用 `request_id` 匹配且没有 `op.actionID`（站点标了 `requestIDUnreliable`，或是升级前落盘的旧记录，见下）：按下面“候选匹配”处理。
   - 其他：弹框“服务器上没有这笔记录”，正文“可能还没执行，或请求没送达。用同一编号重试是安全的：服务器做过会直接返回原结果，不会重复入账。”，按钮：
     - “用同一编号重试”（仅当 `op.actorUserID == me.user.id`）：同 key、同 X-Request-ID、同 body 重发，结果按上表处理。账本按 action_id 去重，即使幂等记录已过 24 小时，同一管理员同 key 同 body 也不会重复入账（`service/admin_user.go:677` `adjustmentActionAlreadyCommitted`）。
     - “放弃这笔”（destructive）：二次确认“放弃后这笔不会再重试；如果服务器其实已经执行，余额以服务器为准。”，确认后 `resolve`。
     - “取消”。
     - 发起人不是当前管理员：不给重试，正文改“这笔由 <邮箱> 发起，只能由同一管理员重试；可以放弃后重新充值。”
5. 任一次查询失败：回执“核对失败，请稍后再试”，保留待核对。

**X-Request-ID 回显检查**：每次余额请求成功后比对响应头回显的 `X-Request-ID` 与发出的值；不一致说明反向代理改写了它（服务端用 `X-Request-ID` 作账本 `request_id`，`server/middleware/request_logger.go:24-28`），给该站点记 `requestIDUnreliable = true`，此后匹配规则不再用 `request_id`。

**候选匹配**（只在第 4 步第二种情况用；用第二次查询的结果）：`user_id == op.userID`、`operation == op.operation`、`requested_value` 等于 `op.amount`（Decimal 比较；“全部余额”是 `set` / `0`）、`notes` 去首尾空白后与 `op.notes` 相同、`operator_user_id == op.actorUserID`（两边都有值时）、`created_at ≥ op.createdAt − 2 分钟`。候选**只给管理员看，不自动 `resolve`**（相同金额、相同备注的另一笔，例如“仍要充值”发出的那笔，也会命中）：
- 恰好 1 条：弹框“找到 1 条可能是这笔的记录”，正文“<时间> · +$50.00 · 余额 $12.40 → $62.40 · 备注：<备注>”，按钮“是这笔，标为已入账”（`resolve`）、“不是，用同一编号重试”（仅同一管理员）、“取消”。
- 0 条：按上面“服务器上没有这笔记录”处理。
- 多条：提示“无法确定这笔是否入账，请在 Web 的“余额调整记录”里核对”，按钮“用同一编号重试”（仅同一管理员；服务端按 action_id 去重，重试不会重复入账）、“放弃这笔”、“取消”。

升级前落盘的旧记录（发送时没带 X-Request-ID，也没有 `createdAt` / `userEmail`）：跳过第一次查询；第二次查询的 `keyword` 用用户 ID 数字、不带 `start_time`，结果同样本地复核 `user_id`，只走候选匹配（候选条件里去掉时间这一条，也不做“不到 40 秒”的判断）。站点标了 `requestIDUnreliable` 且没有 `op.actionID` 时同样跳过第一次查询。

#### 3.5 状态

| 状态 | 显示 |
|---|---|
| 发送中 | 提交按钮变 `ProgressView`“正在提交…”，sheet 不能下滑关闭（`interactiveDismissDisabled`） |
| 等待服务器（409 进行中） | “正在等待服务器结果…”+ 已等待秒数 |
| 待核对 | sheet 关闭；详情横幅、列表 caution 胶囊与 docCheck 标记、头像条“去核对”、概览“待处理”一条 |
| 核对中 | 横幅按钮变进度 |

#### 3.6 刷新策略

不轮询。App 回到前台时对本站点的待核对逐条自动核对一次（只查不执行，即 3.4“核对”第 1、2 步的两次查询）：只有按匹配规则精确找到（action_id / request_id）才自动 `resolve` 并回执；没找到、只有候选、或距发起不到 40 秒，都保留横幅等管理员决定。

#### 3.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: BalanceView` 整个替换为新文件 `NativeApp/Features/Users/BalanceKeypadSheet.swift`（设计稿键盘；不再暴露“设置为”操作，只在“全部余额”时内部用 `set 0`）。键盘输入规则提取为纯函数 `KeypadInput.apply(_ key:to:maxDigits:maxFractionDigits:)`，本章用 `maxDigits = 7`、`maxFractionDigits = 2`（数字总数含小数部分），其他键盘（如兑换码面额）按各自章节传参，配单测。
- `Sources/Sub2Core/Models.swift: PendingBalanceOperation`：新增 `requestID`（= `id` 小写字符串）、`actorUserID`、`createdAt`、`userDisplayName`、`userEmail`、`actionID?`、`idempotencyExpiresAt?`；`init(from:)` 对新字段用 `decodeIfPresent`，兼容已落盘的旧记录（旧记录 `actorUserID` 为空时视为当前管理员可重试，并在核对框里写明“无法确认发起人”；旧记录的核对走 3.4 末尾的旧记录规则）。
- `Sources/Sub2Core/APIClient.swift: updateBalance(_:)`：加 `X-Request-ID` 头，返回 `(AdminUser, ResponseHeaders)`；失败时也要能取到响应头里的 `X-Admin-Adjustment-Action-ID`（放进 `APIError`，见 3.4 第 4 步）；新增 `userAdjustments(query:)`。
- `NativeApp/Features/UsersView.swift: BalanceView.definitelyRejected`（`private` 函数，第 539 行；`AppModel.swift` 里没有这段逻辑）：随 `BalanceView` 一起删掉，判定迁到 `BalanceReconciliation.swift` 的纯函数 `balanceWriteOutcome(for:)`，按 3.4 的结果表重写。现状是：本地 `.validation` 错误、全部 401 / 403、以及 reason 为 `VALIDATION_ERROR` / `INVALID_REQUEST` / `INVALID_AMOUNT` / `BAD_REQUEST` 的 400 当作确定拒绝；服务端真实的 `INVALID_BALANCE`、`IDEMPOTENCY_KEY_*`、无 reason 的 400 都不在其中，会被误记为待核对。
- `NativeApp/Session/AppModel.swift`：新增 `reconcile(_ op:) async -> ReconcileOutcome`（`.executed(UserAdjustment)` / `.notFound` / `.stillRunning` / `.candidates([UserAdjustment])` / `.failed(Error)`）与“回到前台自动核对”。
- 新增 `Sources/Sub2Core/BalanceReconciliation.swift`：账本匹配的纯函数（action_id / request_id 精确匹配、候选匹配、旧记录规则）与 `balanceWriteOutcome(for:)`，配单测。单测至少覆盖：服务端忽略筛选参数、返回 `total ≥ 1` 的无关行 → 不算已入账，转第二次查询；`request_id` 相同但 `user_id` 不同 → 不算；`action_id` 大小写不同 → 算；`requestIDUnreliable` 时同金额同备注的行只作候选、不自动 `resolve`；两条候选 → 多条分支；距发起不到 40 秒 → `.stillRunning`。

---

### 4. 充值与调整记录（全部）

设计稿：`v-users.jsx` 的 `VuLedgerScreen`（`screen:userLedger`）与详情页 `VuLedger`。DECISIONS 第 3 轮文字题“余额流水 → 充值与调整记录”，默认处理“兑换条目显示兑换码前 8 位”。后端：E10（进度表：`adjustment_id` / `before_value` / `after_value` / `operator_email`，`total_recharged_breakdown` 含 `grant`）。

#### 4.1 入口与导航

- 用户详情“充值与调整记录”分区底部“全部 N 条 ›”。
- 导航栏：标题“充值与调整记录”，副标题 = 用户显示名；返回。

#### 4.2 数据来源

`GET /api/v1/admin/users/:id/balance-history`，参数 `page`、`page_size=20`、可选 `type`（本页不用筛选）。

响应 `{items, total, page, page_size, pages, total_recharged, total_recharged_breakdown:{redeem, admin, grant, affiliate, promo}}`。每项（`AdminBalanceHistoryItem`）：`id`、`code`、`type`、`value`、`status`、`used_by`、`used_at`、`created_at`、`group_id`、`validity_days`、`group`（含 `name`）、`notes`（字符串）、`batch_id?`、`created_by?`、`adjustment_id`、`before_value`、`after_value`、`operator_email`（后四个只有 `admin_balance` / `admin_concurrency` 行有值，其余为 null；迁移来的旧行 before / after 也为 null）。

不需要 capability；`total_recharged_breakdown` 与前后余额字段要 `users.balance_ledger`，没有时不显示拆分与前后余额。

#### 4.3 字段 → 显示映射

页面头（分区标题）：左“N 条”（`total`），右“总充值 $60.00”（`total_recharged` = redeem + admin + grant）。有拆分时标题下加一行小字：“兑换 $40.00 · 管理员 $20.00 · 站点赠送 $0.00”（为 0 的项省略），`affiliate` 或 `promo` > 0 时再加“另有返利转入 $5.00、优惠码 $0.00，不计入总充值”。

单条记录（详情页的最近 5 条与本页共用）：

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 第一行左：类型 | `type` + `value` 正负（同 Web `getItemTitle`） | `balance`→“余额充值（兑换）”；`affiliate_balance`→“余额充值（返利转入）”；`admin_balance`→ value ≥ 0 “余额充值（管理员）”/< 0 “余额扣除（管理员）”；`concurrency`→“并发增加（兑换）”；`admin_concurrency`→ ≥ 0 “并发增加（管理员）”/< 0 “并发减少（管理员）”；`subscription`→“订阅已分配” | 其他值：“其他记录” |
| 第一行右：数值 | `value` | 余额类：带符号金额“+$10.00”/“−$5.00”（不着色）；并发类“+2 并发”/“−1 并发”；订阅“<group.name> · N 天”（N = `validity_days`，为 0 时用 `value` 取整） | 订阅没有分组名：“N 天” |
| 第二行左 | `used_at`（没有时 `created_at`）+ `notes` | “10/16 09:20 · 社群活动 · 第 3 批” | 无备注只写时间 |
| 第二行右 | `code` 前 8 位 | 等宽字体“3f9a2c1b...”；只对 `balance`、`concurrency`、`subscription` 显示（兑换得来的条目，同 Web） | `admin_*`、`affiliate_balance` 不显示 |
| 第三行（仅本页、仅管理员调整行） | `before_value`、`after_value`、`operator_email` | “余额 $12.40 → $32.40 · ops@example.com”；并发调整“并发 5 → 7 · …” | 任一为 null 时整行不显示 |

详情页的最近 5 条不显示第三行（保持设计稿两行）。

#### 4.4 交互与写操作

只读。行不可点。长按记录行可“复制兑换码”（只对显示了兑换码的行；复制完整 `code`）。

#### 4.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 列表骨架 |
| 空 | “暂无记录” |
| 第 1 页失败 | 整页错误 + “重试” |
| 翻页失败 | 列表底部“加载更多失败 · 重试” |
| 404 `USER_NOT_FOUND` | “这个用户不存在或已删除”，返回 |

#### 4.6 刷新策略

进入加载第 1 页；滚到底加载下一页（按 `id` 去重）；下拉刷新重拉第 1 页并清掉已加载的后续页。不轮询，无 ETag。

#### 4.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/UserLedger.swift`：`BalanceHistoryPage`、`BalanceHistoryItem`、`RechargeBreakdown` 解码（金额字段 `value` 为 JSON 数字、`before_value` / `after_value` 为字符串，都用 `KeyedDecodingContainer.decimal` / `optionalDecimal`），`title(for:)`、`valueText(for:)`、`codePrefix(for:)` 纯函数配单测。
- 新增 `NativeApp/Features/Users/UserLedgerView.swift`（`List` + `.task` 分页）；详情页的记录分区复用同一个行视图。
- `APIClient`：新增 `balanceHistory(userID:page:pageSize:)`。

---

### 5. 新建用户

设计稿：`v-user-edit.jsx` 的 `UeTabsScreen`（`screen:userNew: 'tabs'`），DECISIONS 第 3 轮 Q13（更正：分段；新建时只有前两段）。后端：`POST /api/v1/admin/users`（G06 可选幂等、30 秒脱离客户端执行；E10 初始余额入账）。

#### 5.1 入口与导航

- 用户列表右上 `+`；列表空态的“新建用户”。
- push 全屏页，隐藏 Tab 栏（`.toolbar(.hidden, for: .tabBar)`）。导航栏：返回（有内容时先确认“放弃新建用户？已填写的内容不会保留。”按钮“放弃”/“继续编辑”）、标题“新建用户”、副标题站点名。
- 顶部固定身份条（新建态）：字母头像（未填时空白）、显示名（用户名 > 邮箱前缀 > “新用户”）、尾部“<角色> · 创建后启用”。
- 分段「基础 | 权限与并发」吸顶；分段下说明行“两段填完后点底部“创建用户””（滚动或输入框获得焦点时收起，见设计稿 `useUeCompact`：滚动 > 24pt 收起、< 2pt 展开，失焦 300 ms 后再展开）。
- 底部操作条（`.safeAreaInset(edge: .bottom)`）：基础段“下一步：权限与并发 →”；权限段“上一步”+“创建用户”。
- 创建成功：从导航栈移除新建页并 push 新用户详情（§2）。

#### 5.2 数据来源

| 用途 | 接口 | 说明 |
|---|---|---|
| 分组目录 | `GET /api/v1/admin/groups/all?include_inactive=true` | 会话内缓存（分组章同一份）；本页只用 `status == "active"` 且 `subscription_type == "standard"` 的分组：`is_exclusive == true` 为专属分组，否则为公开分组；按 `sort_order` 排序 |
| 自定义属性定义 | `GET /api/v1/admin/user-attributes?enabled=true` | 数组：`id`、`key`、`name`、`type`（text / textarea / number / email / url / date / select / multi_select）、`options[{value,label}]`、`required`、`placeholder`、`display_order` |
| 创建 | `POST /api/v1/admin/users` | 见 5.4 |
| 写自定义属性 | `PUT /api/v1/admin/users/:id/attributes` | 创建成功后单独发，见 5.4 |

#### 5.3 字段 → 显示映射

**基础段**

| 分区 / 行 | 请求字段 | 格式与文案 | 校验 |
|---|---|---|---|
| 账户 · 邮箱 | `email` | 占位“必填”；`.emailAddress` 键盘，关闭自动大写 | 必填；`^[^\s@]+@[^\s@]+\.[^\s@]+$`；错误“请输入邮箱”/“邮箱格式不对” |
| 账户 · 用户名 | `username` | 占位“选填” | — |
| 账户 · 备注 | `notes` | 两行，占位“仅管理员可见” | — |
| 账户 · 自定义属性 | 定义的 `name` | 每个启用的定义一行；`select` 用选项 sheet（含“不填”）；text 类单行输入，占位用 `placeholder` 或“选填”；`multi_select` 只读（见未决问题 5） | `required` 的定义为空时“请填写 <名称>” |
| 登录 · 密码 | `password` | 占位“必填，至少 6 位”；“显示 / 隐藏”；下方“生成随机密码”（生成 `xxxx-xxxx-xxxx` 格式 12 位字母数字，生成后自动显示）与“复制” | 必填；≥ 6 个 Unicode 标量、≤ 72 个 UTF-8 字节（沿用现有 `UserWriteValidation.password`）；错误“请输入密码”/“至少 6 位” |
| 余额 · 初始余额 | `balance` | “$”前缀，`.decimalPad`，占位“留空按站点默认”；脚注“选填。填写后创建时会再确认一次金额；以后调整余额用充值键盘。” | 非负十进制、最多 8 位小数；错误“不是合法金额”。留空则**不发** `balance` 字段（服务端用站点 `default_balance`） |

**权限与并发段**

| 分区 / 行 | 请求字段 | 格式与文案 |
|---|---|---|
| 权限 · 角色 | `role` | 分段“用户 / 供应商 / 管理员”，默认“用户”；脚注：选管理员“创建时需要输入二次验证码，验证后再确认一次。”；选供应商“供应商只能访问账号、代理、分组和用量，看不到用户与资金。” |
| 专属分组 | `allowed_groups` 中的专属部分 | 已选分组每行：名称、平台、行尾“默认 ×<rate_multiplier>”；“＋ 添加专属分组”打开多选 sheet；点已选行打开分组 sheet，只有“移除这个专属分组”（新建时不能设专属倍率，行内“专属倍率在创建后设置”）。分区 meta“N 个”；没有任何可授予的专属分组时整个分区写“没有可授予的专属分组”。脚注“专属倍率在创建后设置。”+ 订阅分组说明（见下） |
| 公开分组 | `restrict_public_groups` + `allowed_groups` 中的公开部分 | 开关“限制可访问的公开分组”（副文：开“只能使用下面勾选的公开分组”/关“关闭时可以使用全部公开分组”）；列出全部公开分组；开关打开时每行前有勾选圈，关闭时全部显示为已勾选且不可改；关掉开关时把所有公开分组重新勾上（同 Web） |
| 并发与 RPM · 并发数 | `concurrency` | 步进器，默认 1，0 显示“不限制” |
| 并发与 RPM · RPM 上限 | `rpm_limit` | 步进器步长 10，默认 0（“不限制”）；脚注“0 = 不限制。RPM 上限是这个用户每分钟全部请求的总上限，始终生效；分组的 RPM 限制另外按分组计算。” |

订阅分组说明：分组目录里 `is_exclusive == true` 且 `subscription_type == "subscription"` 的启用分组名，用“、”连接：“企业专线是订阅分组，要在 Web 的订阅管理里开通。”（`allowed_groups` 不能授予订阅分组）。

请求体 `allowed_groups` = 勾选的专属分组 ID +（开关打开时）勾选的公开分组 ID；开关关闭时不写公开分组 ID（同 Web `UserAllowedGroupsModal`）。

分段标记：每段右上角——有校验错误时红色“!”（`exclamationmark.circle.fill`），读屏“基础，有 1 项要修改”。

#### 5.4 交互与写操作

**创建流程**（底部“创建用户”）：

1. 本地校验；有错误：回执“还有 N 项需要填写或修改”，跳到第一个出错字段所在的段并滚到该行（红色标记）。
2. 角色为管理员：按 0.4 做 step-up；通过后确认框“创建管理员「<名>」？”，正文“二次验证已通过。管理员可以管理全部账号、用户和资金。”+（有初始余额时）“\n初始余额 $20.00 · 站点 <站点名>”+ Face ID 行；按钮“创建管理员”（有初始余额时 destructive）/“取消”。
3. 非管理员且初始余额 > 0：确认框“创建「<名>」并入账 $20.00？”，正文“站点 <站点名> · 初始余额 $20.00。会写一条“初始余额”记录到充值与调整记录。”（无 `users.balance_ledger` 时改为“创建时直接写入，不会出现在“充值与调整记录”里。”）+ Face ID 开且 > 门槛时“\n超过 $100，确认后验证 Face ID。”；按钮“创建并入账 $20.00”（destructive）/“取消”。
4. 其他：直接创建。
5. 请求：`POST /api/v1/admin/users`，body：

```json
{"email":"qi.he@example.com","password":"Qm7v-Tr2p-Hx9k","username":"何琪","notes":"","role":"user",
 "balance":20,"concurrency":1,"rpm_limit":0,"allowed_groups":[5],"restrict_public_groups":false}
```

   `balance` 是 JSON 数字（`*float64`），留空时省略该键；有 `admin.idempotent_writes` 时带 Idempotency-Key（请求体冻结时生成；指纹不含密码）。发送后表单冻结，直到结果确定。
6. 成功（200，data 为 `AdminUser`）：有自定义属性值时接着 `PUT /api/v1/admin/users/:id/attributes {"values":{"<attribute_id>":"<值>"}}`（失败只回执“用户已创建，自定义属性没保存成功，可在编辑用户里补填”，不回滚）；然后进入新用户详情，回执“已创建用户「何琪」，初始余额 $20.00”（无初始余额时只写前半句），不给撤销（撤回只能删除用户）。
7. 结果不明（超时 / 网络 / 5xx 无 reason / 409 进行中超过 30 秒）：有幂等能力时同 key 自动重试一次；仍不明时按邮箱核对：`GET /api/v1/admin/users?search=<邮箱>&page_size=20`，在结果里找 `email` 完全相同（不区分大小写）的用户——找到：视为已创建，进入其详情并提示“已在服务器上找到这个用户”；找不到：解冻表单，提示“没有创建成功，可以再试一次”。

**放弃**：返回键有内容时确认（见 5.1）。

#### 5.5 状态

| 情况 | reason / 状态 | 文案 | 动作 |
|---|---|---|---|
| 邮箱已存在 | 409 `EMAIL_EXISTS` | 邮箱字段红字“这个邮箱已被注册”，回执“创建失败：这个邮箱已被注册” | 跳到基础段邮箱行；解冻表单 |
| 服务端字段校验 | 400 且无 reason（请求体绑定失败：邮箱格式、密码少于 6 位、角色不在 `admin` / `user` / `vendor`，`handler/admin/user_handler.go:63-74, 297-299`） | 固定文案“服务器没有接受填写的内容（错误码 HTTP 400），请检查邮箱和密码”，邮箱、密码两行标红；不解析、不显示 message，“详情”按通用约定 §3.4 | 跳到基础段邮箱行；解冻表单 |
| 需要二次验证 | 403 `STEP_UP_REQUIRED` | 弹验证码 | 通过后同 key 重发 |
| 未开 TOTP | 403 `STEP_UP_TOTP_NOT_ENABLED` | “需要先在 Web 端开启二次验证” | 解冻表单，角色保留 |
| Admin Key | 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN` | “Admin Key 登录不能创建管理员，请改用账号登录” | 解冻表单 |
| 幂等冲突 | 409 `IDEMPOTENCY_KEY_CONFLICT` | “请求已变化，请重新提交” | 换新 key，解冻 |
| 幂等存储不可用 | 503 `IDEMPOTENCY_STORE_UNAVAILABLE` | “服务器暂时无法受理，稍后再试” | 解冻（没执行） |
| 只读令牌 | 403 `ACCESS_TOKEN_READ_ONLY` | “当前登录的是只读令牌，不能新建用户” | — |
| 提交中 | — | 底部按钮变进度“正在创建…”，返回键与分段禁用 | — |

#### 5.6 刷新策略

进入时加载分组目录与属性定义（有会话缓存就不重拉）。不轮询。创建成功后用户列表下次出现时刷新第 1 页。

#### 5.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: UserEditorView`（sheet 表单）废弃，改为新文件 `NativeApp/Features/Users/UserEditView.swift`（新建与编辑共用一个视图模型 `UserEditorModel`，`mode: .create | .edit(userID)`）。
- `Sources/Sub2Core/UserManagement.swift: UserCreateRequest`：新增 `allowedGroups: [Int]`、`restrictPublicGroups: Bool`；`balance` 为 nil 时不编码（现在已是 `Decimal?`，确认 `encodeIfPresent`）；`AdminUserRole.title` 改为“用户 / 供应商 / 管理员”。
- `APIClient.createUser(_:identity:)`：带可选 Idempotency-Key，返回响应头；新增 `userAttributeDefinitions()`、`updateUserAttributes(userID:values:)`。
- 去掉现有“核对并确认 → 确认发送”的两步确认（设计稿只在初始余额 / 管理员时确认）。

---

### 6. 编辑用户 · 基础与权限与并发

设计稿：`v-user-edit.jsx` 的 `UeTabsScreen`（`screen:userEdit: 'tabs'`）。前两段要“保存”，第三段立即生效（§7、§8）。后端：`PUT /api/v1/admin/users/:id`（G06 可选幂等、30 秒脱离执行；Q13 带 balance 返回 400），`GET /api/v1/admin/users/:id/rpm-status`（E08）。

#### 6.1 入口与导航

- 用户详情 ⋯ →“编辑用户”（进入「基础」段）；用户详情 Key 摘要行（进入「Key 与限额」段并滚到 Key 区）。
- push 全屏，隐藏 Tab 栏。导航栏：返回（见 6.4“离开”）、标题“编辑用户”、副标题站点名、右上 ⋯（“复制邮箱”；“删除用户…”红字最后，管理员置灰并注“管理员不能删除”）与“保存”（有改动时实心可点，否则灰）。
- 固定身份条：显示名、邮箱、徽章（角色、启用 / 禁用、本人“你”、本机待核对“待核对”）、右侧“可用余额 $12.40”与“充值 / 退款”胶囊（44pt 点按区，打开 §3 键盘，待核对时先问）。滚动 > 24pt 或输入框获得焦点时收成一行（显示名 + 余额 + 胶囊）。
- 分段「基础 | 权限与并发 | Key 与限额（N）」吸顶，N = Key 总数。分段下说明行：无改动“基础、权限与并发改完点右上“保存”，两段一起提交”；有改动 / 错误时改为“基础 已改 2 项 · 权限与并发 1 项要修改”（收起态不显示，标记仍在分段上：改动是圆点，错误是红色“!”）。
- 切换分段时滚动回顶部。

#### 6.2 数据来源

进入时并发：

| 用途 | 接口 | 说明 |
|---|---|---|
| 用户资料（表单基线） | `GET /api/v1/admin/users/:id` | `email`、`username`、`notes`、`role`、`status`、`concurrency`、`rpm_limit`、`allowed_groups`、`group_rates`（`{"<group_id>": rate}`）、`restrict_public_groups`、`last_active_at` |
| 分组目录 | `GET /api/v1/admin/groups/all?include_inactive=true` | 同 §5.2 |
| 自定义属性 | `GET /api/v1/admin/user-attributes?enabled=true` + `GET /api/v1/admin/users/:id/attributes` | 值数组每项 `attribute_id`、`value` |
| RPM 状态 | `GET /api/v1/admin/users/:id/rpm-status` | `{user_rpm_used, user_rpm_limit, user_rpm_tracked, per_group:[{group_id, group_name, used, limit, source, tracked}]}`；`per_group` 可能为 null（用户没有绑定分组的 Key），按空数组处理 |
| Key（算“绑定 N 个 Key”） | 同 §7.2 | 与第三段共用一份 |
| 站点管理员数（降级预检） | `GET /api/v1/admin/users?role=admin&page_size=1&include_subscriptions=false` | 只读 `total`；在角色从管理员改成别的时才请求 |

#### 6.3 字段 → 显示映射

**基础段**

| 分区 / 行 | 字段 | 显示与编辑 | 说明 |
|---|---|---|---|
| 账户 · 邮箱 / 用户名 / 备注 / 自定义属性 | `email` / `username` / `notes` / 属性值 | 同 §5.3 | 用户名、备注可清空（发 `""`） |
| 登录与状态 · 重置密码 | `password` | 折叠行“重置密码 · 不修改 ⌄”；展开后“新密码”输入（占位“留空则保持原密码”）+ 显示 / 隐藏 + “生成随机密码”/“复制”/“不修改” | 留空不发 |
| 登录与状态 · 状态 | `status` | 开关行“状态 · 启用 / 禁用”，副文“可以登录，Key 可以调用”/“不能登录，Key 调用会被拒绝”；原角色是管理员时锁定，副文“管理员不能禁用” | — |

**权限与并发段**

| 分区 / 行 | 字段 | 显示与编辑 |
|---|---|---|
| 权限 · 角色 | `role` | 分段“用户 / 供应商 / 管理员”；本人时只有“管理员”可选（其他置灰）。脚注按情况取一：本人“这是你当前登录的账号（<名>）：不能把自己降级，也不能禁用或删除。”；升为管理员“保存时需要输入二次验证码，验证后再确认一次。”；从管理员降级“降级后会失去后台权限。如果他是站点最后一个管理员，保存会失败。”；供应商“供应商只能访问账号、代理、分组和用量，看不到用户与资金。” |
| 专属分组 | `allowed_groups` ∩ 专属标准启用分组、`group_rates` | 每行：分组名、行尾倍率“专属倍率 ×1.3”（有专属倍率）或“默认 ×1.0”（灰）；副行“<平台> · 绑定 N 个 Key”（新加的写“新添加 · 保存后生效”）。已移除未保存的行显示删除线 + “保存后移除 · N 个 Key 会无法调用”+“撤回”。“＋ 添加专属分组”。分区 meta“N 个”/改动时“已改 N 项”。脚注“倍率、添加、移除在“保存”后生效。”+ 订阅分组说明 |
| 公开分组 | `restrict_public_groups`、`allowed_groups` ∩ 公开分组、`group_rates` | 开关同 §5.3；每行：分组名、副行“<平台>”（限制打开时加“ · 可以使用 / 不能使用”）、行尾倍率；点行打开分组 sheet。meta：限制打开“可用 3 / 5”，关闭“5 个”。脚注“点分组可以设专属倍率；留空用分组默认倍率。” |
| 并发与 RPM · 并发数 | `concurrency` | 步进器；缺失显示“—”，按 ＋ 从 1 开始 |
| 并发与 RPM · 调整备注 | `adjustment_notes` | 只在并发改动后出现，缩进；占位“可选 · 并发 2 → 4 的原因”；脚注追加“调整备注只写进这次的并发流水，不写进用户资料。” |
| 并发与 RPM · RPM 上限 | `rpm_limit` | 步进器步长 10 |
| RPM 状态块 | rpm-status | 见下表 |

**分组 sheet**（点专属 / 公开分组行）：标题分组名；说明行“专属分组 / 公开分组 · <平台> · 默认倍率 ×1.0 · 绑定 N 个 Key”；限制打开时的公开分组有“允许使用”开关；“专属倍率”输入（“×”前缀，占位“默认 1.0”，副文“只对这个用户生效”，> 0 且最多 3 位小数，错误“要大于 0，最多 3 位小数”）；有值时“改回默认倍率 ×1.0”；专属分组多一行“移除这个专属分组”（有绑定 Key 时先确认“移除「X」？绑定在「X」的 N 个 Key 会无法调用。要保留请用替换分组。”按钮“仍要移除”/“改用替换分组”（跳到 §8 替换分组 sheet）/“取消”）。右上“完成”只改本地草稿；脚注“按“完成”回到表单，倍率与移除在“保存”后生效。”

**添加专属分组 sheet**：多选专属标准启用分组中用户还没有的；右上“添加 N 个”；空时“没有其他可授予的专属分组”；脚注“添加后要“保存”才生效。”+ 订阅分组说明。

**RPM 状态块**（标题“RPM 状态 · 本分钟”）：

| 元素 | 字段 | 显示 | 不可用时 |
|---|---|---|---|
| 用户总计 | `user_rpm_used`、`user_rpm_limit`、`user_rpm_tracked` | 右侧“<used> / <limit>”；limit 为 0 写“不限制”；limit > 0 时下方进度条（≥ 90% critical，≥ 75% caution） | `user_rpm_tracked == false`：右侧写“不限 · 不计数”，不显示 used；`run_mode == simple` 时全部写“简易模式不计数” |
| 分组行 | `per_group[]` | 分组名（`group_name`）、标签“专属 RPM”（`source == override`）/“分组 RPM”（`group`）、右侧“<used> / <limit>”，limit 0 写“不限” | `tracked == false`：limit 为 0 且来源是 override 写“免检”，否则“不限 · 不计数”；`source == ""`：标签与数值都写“—”（分组读取失败或已删除，数值不可信） |
| 整块 | — | — | 501 `RPM_STATUS_UNAVAILABLE`：整块换成“RPM 状态暂不可用”；其他错误：“RPM 状态加载失败 · 重试” |

缺 `users.rpm_tracked` 时：limit 为 0 的行按“不限 · 不计数”处理（E08 退路）。

#### 6.4 交互与写操作

**保存**（右上“保存”）：

1. 本地校验（同新建；密码可空）。有错误：回执“还有 N 项需要填写或修改”，跳到第一个错误所在段并滚到该行。
2. 降级预检：原角色 admin、新角色不是 admin 时请求管理员数，`total ≤ 1` → 角色字段红字“站点只剩这一位管理员，不能降级”，回执“保存失败：不能降级站点最后一个管理员”，不发请求（后端此情况返回无 reason 的 500，`service/admin_user.go:180`）。
3. 升为管理员（原角色不是 admin、新角色是 admin）：按 0.4 做 step-up；通过后确认框“把「<名>」设为管理员？”，正文“二次验证已通过。管理员可以管理全部账号、用户和资金。\n同时保存：<已改字段名，用“、”连接>”，按钮“设为管理员并保存”/“取消”。
4. 请求：`PUT /api/v1/admin/users/:id`，**只发改过的字段**：

| 改动 | 请求字段 |
|---|---|
| 邮箱 | `email` |
| 用户名 / 备注 | `username` / `notes`（可为 `""`） |
| 新密码 | `password` |
| 状态 | `status`（`active` / `disabled`） |
| 角色 | `role` |
| 并发 | `concurrency`（+ 非空时 `adjustment_notes`） |
| RPM | `rpm_limit` |
| 专属 / 公开分组或限制开关 | `allowed_groups`（完整列表）+ `restrict_public_groups` |
| 专属倍率 | `group_rates`：改了的 `{"<gid>": 1.3}`，清掉的 `{"<gid>": null}`；移除的专属分组若原来有倍率也发 null |

   `allowed_groups` 的组装：以服务器当前 `allowed_groups` 为底，去掉界面上取消的、加上界面上新增的；**保留界面不认识的 ID**（停用分组等不在目录里的）；限制开关从开改成关时去掉全部公开分组 ID。永不发送 `balance`（服务端 400 `USER_BALANCE_NOT_EDITABLE`）。有 `admin.idempotent_writes` 时带 Idempotency-Key；没有时只在含 `concurrency` 时带（老服务端只在那时认 key）。
5. 自定义属性有改动：用户 PUT 成功后再 `PUT /api/v1/admin/users/:id/attributes {"values":{"<attribute_id>":"<值>"}}`（只发改过的；清空发 `""`）。
6. 成功：回执“已保存 3 项更改”；移除了有绑定 Key 的专属分组时追加“；绑定在「Claude Code 组」的 2 个 Key 将无法调用”（clockAlert 图标、caution）；不给撤销（还原是又一次完整保存）。pop 回详情并刷新。
7. 属性保存失败：用户资料已保存，回执“资料已保存，自定义属性没保存成功”，留在编辑页、属性行保持“已改”。

**离开**（返回键）：没有未保存改动直接返回；有改动时确认框：标题“放弃未保存的更改？”，正文“<已改字段名>还没保存，会被放弃。”，若本次进入后做过立即生效的操作，追加“\n已经立即生效、不会撤回：<操作名列表，如 Key「脚本」换分组、平台限额（Anthropic）、余额>。”；按钮“放弃更改”（destructive）/“继续编辑”。

**⋯ → 删除用户…**：同 §2.4 的删除确认；成功后 pop 两层回到列表。

**⋯ → 复制邮箱**：复制 `email`，回执“已复制邮箱”。

#### 6.5 状态

| 情况 | reason / 状态 | 文案 | 动作 |
|---|---|---|---|
| 邮箱被占用 | 409 `EMAIL_EXISTS` | 邮箱字段“已被其他用户使用”，回执“保存失败：这个邮箱已被其他用户使用” | 跳到基础段邮箱行 |
| 降级自己 / 字段校验失败 | 400 且无 reason（如服务端 `cannot demote yourself from admin`、请求体绑定失败） | 正常不会出现（本人角色已锁定，字段已在本地校验）；万一出现用通用约定 §3.3 的 400 兜底“请求无效（错误码 HTTP 400）”，不回显 message | 重新 GET 资料 |
| 禁用管理员 / 降级最后一位管理员 / 倍率 ≤ 0 | 500 无 reason | 事前已拦截；万一出现：“保存失败：服务器未能完成请求” | 重新 GET 资料 |
| 带了 balance | 400 `USER_BALANCE_NOT_EDITABLE` | 不会出现 | — |
| 二次验证 | 403 `STEP_UP_REQUIRED` / `STEP_UP_TOTP_NOT_ENABLED` / `STEP_UP_ADMIN_API_KEY_FORBIDDEN` | 同 0.4 | — |
| 用户不存在 | 404 `USER_NOT_FOUND` | “这个用户不存在或已删除” | 回到列表并移除 |
| 幂等进行中 / 退避 | 409 `IDEMPOTENCY_IN_PROGRESS` / `RETRY_BACKOFF` | “正在保存…” | 按 `Retry-After` 同 key 重试，最多 30 秒，之后按“结果不明”处理 |
| 结果不明 | 超时 / 网络 / 5xx | “保存结果未确认” | 有幂等能力：同 key 重试一次；仍不明则 GET 资料，与草稿逐字段比对：全部一致 → 视为已保存；否则保留草稿并提示“服务器上的资料与你的修改不一致，请检查后再保存”（用新 key） |
| 只读令牌 | 403 `ACCESS_TOKEN_READ_ONLY` | “当前登录的是只读令牌，不能修改” | — |
| 加载失败 | — | 整页错误“加载用户失败 · 重试”（分组目录 / 属性失败只影响对应分区，“加载失败 · 重试”） | — |

#### 6.6 刷新策略

- 进入时加载一次，表单基线固定，不随轮询覆盖草稿。
- RPM 状态块出现在屏幕上时每 15 秒刷新一次，离开屏幕停止；下拉刷新时也刷新。
- 保存成功后 pop，不在本页重载。
- 立即生效的操作（§7、§8）成功后会改变 `allowed_groups`（换分组自动授予、替换分组）：同步更新表单**基线**与草稿里对应的分组（设计稿 `both()`），已有的其他草稿改动保留。

#### 6.7 对现有代码的改动点

- 新文件 `NativeApp/Features/Users/UserEditView.swift`（分段壳、身份条、吸顶分段、收起逻辑）、`UserEditBasicSection.swift`、`UserEditAccessSection.swift`、`UserGroupSheets.swift`、`UserRPMStatusView.swift`；视图模型 `UserEditorModel`（`@Observable`：`original`、`draft`、`changedFields`、`errors`、`applied`）。
- `Sources/Sub2Core/UserManagement.swift: UserUpdateRequest`：新增 `status`、`allowedGroups`、`restrictPublicGroups`、`groupRates: [Int: Decimal?]`（编码时 nil 值要写成 JSON `null`，需自定义 `encode(to:)`，不能用默认的 `encodeIfPresent`）；`validate()` 的“至少改一个字段”条件同步扩充；倍率校验 > 0、≤ 3 位小数。
- `PendingUserUpdateOperation.supportsSafeRetry`：有 `admin.idempotent_writes` 时恒为 true（现在只在带 concurrency 时为 true）。
- `APIClient`：新增 `userRPMStatus(id:)`、`userAttributes(userID:)`、`adminCount()`。
- 删除旧 `UserEditorView` 与 `PreparedUserMutation`。

---

### 7. 编辑用户 · Key 与限额 · API Key 卡片

设计稿：`v-user-edit.jsx` 的 `UeKeySec`（`ueKeys: 'cards'`）、`UeKeyCard`、`UeKeyGroupSheet`；DECISIONS 第 3 轮 Q14（可展开卡片，第一张默认展开）与文字题（新建 / 停用 / 删除：后端加好后删除放 ⋯ 最后并确认，停用回执可撤销）。后端：E01、E03、E04、E06、E11、E12。

这一段顶部固定说明条：“**这一段立即生效**，不用保存，也不随“放弃更改”撤回”。

#### 7.1 入口与导航

- 编辑用户第三段「Key 与限额」；从用户详情 Key 摘要进入时直接落在这一段。
- 卡片内：换分组 sheet、Key ⋯ 菜单（编辑 Key…、停用 / 启用、显示完整 Key…、删除 Key…）；列表末尾“＋ 新建 Key”→ 新建 Key sheet → 创建结果 sheet。

#### 7.2 数据来源

| 用途 | 接口 | 关键参数 / 说明 |
|---|---|---|
| Key 列表 | `GET /api/v1/admin/users/:id/api-keys` | `key_view=masked`、`sort_by=id`、`sort_order=asc`、`page_size=100`（不够时翻页）；分页信封；每项 `APIKey` |
| 单个 Key 刷新 | `GET /api/v1/admin/api-keys/:id` | `key_view=masked`；回填 `current_concurrency` |
| Key 今日消费 | `POST /api/v1/admin/dashboard/api-keys-usage` | `{"api_key_ids":[...]}`（每批 ≤ 200）→ `stats["<id>"].today_actual_cost` |
| 新建 | `POST /api/v1/admin/users/:id/api-keys` | 见 7.4 |
| 修改 / 停用 / 换分组 / 重置速率 | `PUT /api/v1/admin/api-keys/:id` | `key_view=masked`；见 7.4 |
| 删除 | `DELETE /api/v1/admin/api-keys/:id` | → `{"id":4087,"deleted":true}` |
| 揭示 | `POST /api/v1/admin/api-keys/:id/reveal` | step-up；→ `{"id":4087,"key":"sk-…"}`，`Cache-Control: no-store` |
| 用户订阅（订阅分组可选性） | `GET /api/v1/admin/users/:id/subscriptions` | 数组；用 `group_id`、`status == "active"`、`expires_at` |
| 分组目录、用户资料 | 同 §6.2 | 用 `allowed_groups`、`group_rates`、`restrict_public_groups` |

`APIKey` 字段：`id`、`user_id`、`key`（masked 时为 `""`）、`key_masked`（“sk-…3f9a”；墓碑为 `""`）、`name`、`group_id`（可空）、`status`、`effective_status`、`ip_whitelist`、`ip_blacklist`、`last_used_at`、`last_used_ip`、`quota`（0 = 不限）、`quota_used`、`expires_at`（可空）、`current_concurrency`、`rate_limit_5h` / `_1d` / `_7d`（0 = 不限）、`usage_5h` / `_1d` / `_7d`（过期窗口已归零）、`reset_5h_at` / `_1d_at` / `_7d_at`（窗口未开始或已过期时省略）、`created_at`、`updated_at`。

`key_masked` 为空的项是已删除的墓碑 Key，不显示（E06 说明）。

#### 7.3 字段 → 显示映射

**Key 状态**（`effective_status`；缺能力时本地推导：`status` 不是 active / quota_exhausted / expired → inactive；`status` 是 quota_exhausted / expired 原样；否则 `expires_at` 已过 → expired；`quota > 0 && quota_used ≥ quota` → quota_exhausted；否则 active）：

| 值 | 徽章 | 色调 | 计入“活跃” |
|---|---|---|---|
| `active` | 卡片头不显示（列表摘要里也不写） | ok | 是 |
| `inactive` | “已停用” | neutral | 否 |
| `quota_exhausted` | “额度耗尽” | caution | 否；`run_mode == simple` 时是，徽章写“额度耗尽 · 仍可调用” |
| `expired` | “已过期” | neutral | 否；`simple` 时是，徽章写“已过期 · 仍可调用” |

`effective_status` 只反映 Key 本身；用户被禁用时卡片不改状态，由身份条的“禁用”徽章说明。

**分区头**：标题“API Key”，meta“3 个 · 活跃 2”（0 个时“0 个”）。

**卡片（收起态）**

| 元素 | 字段 / 计算 | 格式 | 空值 |
|---|---|---|---|
| 名称 + 徽章 | `name`、状态 | 加粗；非活跃卡片整体次要色，左侧状态胶囊按色调 | — |
| 掩码 | `key_masked` | 等宽字体 | `—` |
| 展开箭头 | — | ⌄ / ⌃；一次只展开一张，第一张默认展开；展开另一张导致标题滚出屏幕时滚回（`ScrollViewReader.scrollTo(id, anchor: .top)`） | — |
| 用量条 | `quota_used` / `quota` | `quota > 0`：进度条 + “$12.30 / $50.00” + 右侧百分比；`quota == 0`：无进度、“今日 $2.80”+ 右侧“不限额度” | 今日消费失败“今日 —” |
| 元信息行 | 分组、倍率、最近使用 | “<分组名> · 专属倍率 ×1.3 / 默认 ×1.0 · 最近使用 3 分钟前”；倍率取用户 `group_rates[gid]`，没有用分组 `rate_multiplier` | `group_id` 为空：“不绑定分组”，不写倍率；`last_used_at` 为空：“未使用” |

**卡片（展开态，追加）**

| 元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 有效期 | `expires_at` | “至 2026-12-31” | “永久有效” |
| 当前并发 | `current_concurrency` | 数字 | 缺 `api_keys.current_concurrency`：“—”（读不到 Redis 时服务端也给 0，无法区分） |
| 最近 IP | `last_used_ip` | 等宽 | “—” |
| IP 限制 | `ip_whitelist`、`ip_blacklist` | “白名单 198.51.100.0/24 · 黑名单 203.0.113.9”（多个用“、”） | 都为空：“未设置” |
| 速率限制 | `rate_limit_*`、`usage_*`、`reset_*_at` | 标题“速率限制”，小字“滚动窗口 · 0 = 不限”；三格 5 小时 / 1 天 / 7 天：上限 > 0 时百分比 + 进度条 + “$2.10 / $5” + “11:20 重置”（`reset_*_at` 的本地时间；跨天写“明天 08:02”）；上限 0 时“不限”+“已用 $x” | 三个窗口都没上限且都没用量：一行“5 小时、1 天、7 天都不限额” |
| 操作行 | — | “换分组”；任一窗口有上限或有用量时“重置速率限制”；右侧 ⋯ | — |
| 脚注（列表末尾） | — | “换分组、停用的回执里可以撤销；重置速率限制、删除不能撤销。” | — |

**空态**：“还没有 Key”，副文 E01 可用时“可以在这里替用户新建；用户也可以在 Web 端「API 密钥」里自己创建。”；不可用时“用户在 Web 端「API 密钥」里自己创建；创建后可以在这里换分组、重置速率限制。”

**“＋ 新建 Key”**：列表末尾的行按钮；E01 不可用时画成虚线并带标签“需后端新增”，点按只弹说明（设计稿 `keyGap` 文案）。

**换分组 sheet**（标题“换分组 · <Key 名>”，左上“取消”）：第一项“不绑定分组”（副文“这个 Key 不属于任何分组”），后面是全部启用分组（分组目录 `status == "active"`，按 `sort_order`）。每项副文：

- 订阅分组（`subscription_type == "subscription"`）：用户有该分组 `status == "active"` 的订阅 →“<平台> · 订阅分组 · 有效订阅”；没有 → 副文“<平台> · 订阅分组 · 需要这个分组的有效订阅”且整行禁用。
- 标准分组：“<平台> · 专属分组 / 公开分组 · 专属倍率 ×1.3 / 默认倍率 ×1.0”；专属且用户 `allowed_groups` 里没有 → 追加“ · 会同时授予这个分组”；公开、用户开着限制且没勾选 → 追加“ · 用户被限制，调用会被拒绝”（可选，不禁用）。
- 当前分组前打勾。选中即执行（7.4），sheet 关闭。脚注“选中即生效；回执里可以撤销。”

**Key ⋯ 菜单**（E01 可用时）：“编辑 Key…”、“停用 Key”/“启用 Key”（`status` 为 inactive 时显示启用）、“显示完整 Key…”（见 7.4 条件）、“删除 Key…”（红字最后）。E01 不可用时卡片里改画两枚虚线胶囊“停用 / 删除 · 需后端新增”（设计稿原样），不显示 ⋯。

#### 7.4 交互与写操作

所有写成功后：用响应的 `api_key` 替换该卡片（响应里 `current_concurrency` 为 0，随后补一次 `GET /api/v1/admin/api-keys/:id?key_view=masked` 刷新并发），并把这次操作名记入“已立即生效”列表（6.4 离开时列出）。**同一次 PUT 不要同时带字段修改和 `group_id`**：服务端先改字段再换分组，后一步失败时前一步已生效（`apikey_handler.go` `UpdateGroup`），App 分两次发。

**换分组**

- 请求：`PUT /api/v1/admin/api-keys/:id?key_view=masked`，`{"group_id": <新分组 id>}`；“不绑定分组”发 `0`。无 Idempotency-Key（绝对值写，可安全重试）。
- 本地记下撤销所需：`fromGroupID`（原 `group_id`，空记 0）、`newlyGranted` = 目标是专属标准分组且换之前用户 `allowed_groups` 里没有它。**不要用响应的 `auto_granted_group_access` 判断**：只要目标是专属标准分组它就为 true，即使用户原来就有（`service/admin_group.go:1610-1640`）。
- 成功：回执——不绑定“「脚本」已不绑定分组”；有新授予“已改到「Claude Code 组」，并为用户添加了这个分组”；其他“「脚本」已改到「标准组」”；都带“撤销”。有新授予时刷新用户资料，把该分组加入表单基线与草稿的专属分组。
- 撤销：`PUT /api/v1/admin/api-keys/:id {"group_id": fromGroupID, "revoke_group_access_id": <新分组 id>}`（只在 `newlyGranted` 时带后者，E04）→ 响应 `revoked_group_access: true`；成功后同步移除基线里的该分组。409 `GROUP_STILL_IN_USE`（用户另有 Key 绑在该分组）→ 改发不带 `revoke_group_access_id` 的 PUT，回执“Key 已还原；该分组还有其他 Key 在用，授权保留”。E04 不可用时走 0.6 的两步退路。
- 错误：400 `GROUP_NOT_ACTIVE`“这个分组已停用”；400 `SUBSCRIPTION_REQUIRED`“用户没有这个分组的有效订阅”；404 `GROUP_NOT_FOUND`“分组不存在”（刷新分组目录）；404 `API_KEY_NOT_FOUND`“这个 Key 已被删除”（移除卡片）；400 `INVALID_GROUP_ID` 不会出现。

**重置速率限制**

- 确认框：标题“重置「脚本」的速率限制用量？”，正文“5 小时、1 天、7 天三个窗口的已用额度会归零，立即生效，不能撤销。”，按钮“重置用量”（destructive）/“取消”。
- 请求：`PUT /api/v1/admin/api-keys/:id?key_view=masked`，`{"reset_rate_limit_usage": true}`。
- 成功：回执“速率限制已重置”，三窗口用量归零（以响应为准）。

**停用 / 启用**（E01）

- 直接执行（可逆）：`PUT /api/v1/admin/api-keys/:id?key_view=masked`，`{"status":"inactive"}` 或 `{"status":"active"}`。
- 成功：回执“已停用「脚本」”/“已启用「脚本」”，带“撤销”= 再发 `{"status": previous.status}`；`previous.status` 不是 `active` / `inactive`（如库里是 `quota_exhausted`）时回执不给撤销。
- 启用一个已过期或额度用满的 Key：服务端按用户侧规则处理（`applyAPIKeyUpdate`），以响应的 `effective_status` 为准；若仍不是 active，回执改“已启用，但 Key 已过期 / 额度已用完，仍不能调用”。
- 错误：400 `INVALID_API_KEY_STATUS` 不会出现。

**编辑 Key…**（E01；设计稿没有这张表单，本规格给最小实现，见未决问题 1）

- sheet 字段（预填当前值）：名称（必填）、额度（$，0 = 不限）、“重置已用额度”开关（仅 `quota > 0` 时显示）、有效期（永久 / 选择日期）、IP 白名单、IP 黑名单（多行，每行一个 IP 或 CIDR）、速率限制 5 小时 / 1 天 / 7 天（$，0 = 不限）。右上“保存”有改动才可点。
- 请求：`PUT /api/v1/admin/api-keys/:id?key_view=masked`，只发改过的：`name`、`quota`、`reset_quota`、`expires_at`（RFC3339；改成永久发 `""`）、`ip_whitelist`、`ip_blacklist`（数组；清空发 `[]`）、`rate_limit_5h` / `_1d` / `_7d`。
- 成功：回执“已保存「脚本」”，带“撤销”= 用响应 `previous` 里的 `name`、`quota`、`expires_at`（null 发 `""`）、`ip_whitelist`、`ip_blacklist`、`rate_limit_*` 再 PUT 一次；`quota_used` 不能写回，含“重置已用额度”时回执注明“已用额度的重置不能撤销”。
- 错误：400 `API_KEY_NAME_REQUIRED`“名称不能为空”；400 `API_KEY_LIMIT_INVALID`“额度和速率限制必须是非负数”；400 `INVALID_IP_PATTERN`“IP 或 CIDR 格式不对”；400 且无 reason（请求体绑定失败或有效期格式不对，`handler/admin/apikey_handler.go:261, 267`；App 总发 RFC3339 或 `""`，正常不会出现）→ 通用约定 §3.3 的 400 兜底“请求无效（错误码 HTTP 400）”，不按 message 区分；有 reason 的字段错误标在对应行。

**删除 Key…**（E01）

- 确认框：标题“删除 Key「脚本」？”，第一行“站点 <站点名> · 用户 <显示名>”，第二行“删除后这个 Key 立即不能调用，不能撤销。”；Face ID 关时输入完整 Key 名称才能点“删除”，开时“用 Face ID 删除”。
- 请求：`DELETE /api/v1/admin/api-keys/:id` → `{id, deleted: true}`；已删过的再删也返回成功。
- 成功：移除卡片，回执“已删除 Key「脚本」”。404 `API_KEY_NOT_FOUND`：同成功。

**显示完整 Key…**（E03，需 `api_keys.masked_view`）

- 显示条件：`security.step_up_enabled == false`，或 `step_up_available == true`。否则菜单项置灰，副文“Admin Key 登录不能查看完整 Key”/“需要先在 Web 端开启二次验证”。
- 流程：本机身份验证（总是）→ 需要时 step-up（0.4）→ `POST /api/v1/admin/api-keys/:id/reveal`（无请求体）→ sheet 显示完整 Key（等宽、可选择）、“复制”（`UIPasteboard` 设 `localOnly` 与 60 秒过期）、提示“完整 Key 只在这里显示，关闭后不保留”。sheet 关闭、App 进入后台或 30 秒后自动清除内存中的明文。明文不写日志、不落盘、不进状态恢复。
- 错误：403 `STEP_UP_REQUIRED` → 弹验证码后重试；403 `STEP_UP_TOTP_NOT_ENABLED` / `STEP_UP_ADMIN_API_KEY_FORBIDDEN` → 同 0.4；404 `API_KEY_NOT_FOUND` →“这个 Key 已删除，没有可显示的内容”。

**新建 Key**（E01）

- sheet 字段：名称（必填）、分组（单选，选项与换分组 sheet 相同，默认“不绑定分组”）、额度（$，留空 / 0 = 不限）、有效期（永久 / 7 天 / 30 天 / 90 天 / 自定义天数）、IP 白名单、IP 黑名单、速率限制三窗口（留空 / 0 = 不限）。右上“创建”。
- 请求：`POST /api/v1/admin/users/:id/api-keys`，带 Idempotency-Key（sheet 打开时生成，同一表单内容的重试沿用；改了内容换新 key）：

```json
{"name":"脚本","group_id":3,"quota":50,"expires_in_days":30,"ip_whitelist":["198.51.100.0/24"],"ip_blacklist":[],
 "rate_limit_5h":5,"rate_limit_1d":20,"rate_limit_7d":0}
```

  `group_id` 不绑定时省略；`expires_in_days` 永久时省略（传 0 或负数会 400）。不支持自定义 Key。
- 成功：响应 `{api_key:{…含完整 key…}, auto_granted_group_access, granted_group_id, granted_group_name}`（新建接口不读 `key_view`，总是返回明文；同 key 重放也返回同一明文）。关闭表单，打开“Key 已创建”结果 sheet：名称、完整 Key（等宽）、“复制”（同揭示的剪贴板规则）、提示“完整 Key 只在这里显示一次；之后查看需要二次验证。”、“完成”。卡片列表插入新 Key（用 masked 形态），清掉内存明文。有新授予分组时同换分组一样更新基线；回执不给撤销（撤回是删除）。
- 错误：403 `API_KEY_COUNT_EXCEEDED`“这个用户的 Key 数量已达上限，请先删除不用的 Key”；400 `API_KEY_NAME_REQUIRED`、`API_KEY_LIMIT_INVALID`、`API_KEY_EXPIRY_INVALID`、`INVALID_IP_PATTERN`、`GROUP_NOT_ACTIVE`、`SUBSCRIPTION_REQUIRED`（绑定失败时服务端会删掉刚建的 Key，不留残留）；404 `USER_NOT_FOUND` / `GROUP_NOT_FOUND`；409 `IDEMPOTENCY_IN_PROGRESS` 按 `Retry-After` 重试，连续超过 30 秒后刷新 Key 列表，若出现同名且 `created_at` 晚于本次发起时间的 Key 视为已创建（但明文只能通过揭示获得），否则提示“结果未确认，请刷新后检查”。

#### 7.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 卡片骨架 2 张 |
| Key 列表失败 | 分区内“Key 加载失败 · 重试”；平台限额、替换分组照常 |
| 今日消费失败 | 不限额卡片的用量行“今日 —” |
| 写操作进行中 | 该卡片的操作按钮变进度，其他卡片可操作 |
| 写失败 | 回执按上文；卡片恢复原状（无乐观更新——换分组等都等服务端返回再改界面） |
| 404 `API_KEY_NOT_FOUND`（任一操作） | 移除卡片，回执“这个 Key 已被删除” |

#### 7.6 刷新策略

切到「Key 与限额」段时刷新 Key 列表与今日消费（同一次进入只刷一次）；每个写操作成功后只刷新该卡片；下拉刷新全部。不轮询（Key 的并发、用量变化不需要实时）。

#### 7.7 对现有代码的改动点

- `Sources/Sub2Core/Models.swift: UserAPIKey` 扩充为完整 `AdminAPIKey`（上面全部字段；金额用 Decimal；时间用 `Date?`；`key` 解码后若非空立即置空，只保留 `keyMasked`——现在 `UsersView.swift:159` 拿完整 `key` 本地截后 4 位，改用 `key_masked`）。
- 新增 `Sources/Sub2Core/UserKeys.swift`：`AdminAPIKeyStatus` 推导（`effective_status` 优先，缺失时本地推导；`simple` 模式规则）、`AdminAPIKeyCreateRequest`、`AdminAPIKeyUpdateRequest`（字段全可选；`expiresAt` 区分“不改 / 清除 / 设置”三态）、`AdminAPIKeyWriteResult`（`api_key`、`auto_granted_group_access`、`granted_group_id`、`granted_group_name`、`revoked_group_access`、`revoked_group_id`、`previous`），配单测。
- `APIClient`：新增 `apiKey(id:)`、`createUserAPIKey(userID:request:idempotencyKey:)`、`updateAPIKey(id:request:)`、`deleteAPIKey(id:)`、`revealAPIKey(id:)`、`apiKeysTodayUsage(ids:)`、`userSubscriptions(userID:)`。
- 新视图：`NativeApp/Features/Users/UserKeyCards.swift`、`UserKeyGroupSheet.swift`、`UserKeyFormSheet.swift`（新建与编辑共用）、`UserKeyRevealSheet.swift`。

---

### 8. 编辑用户 · Key 与限额 · 平台限额与替换分组

设计稿：`v-user-edit.jsx` 的 `UeQuotaSec`、`UeQuotaSheet`、`UeAddQuotaSheet`、`UeReplaceSec`、`UeReplaceSheet`。后端：E07（单平台 PUT / DELETE / restore）、E04（替换分组精确撤销）。

#### 8.1 入口与导航

- 「Key 与限额」段里 API Key 区之下：平台限额分区；再下：替换分组分区（只在用户有专属分组时出现）。
- 平台限额行 → 平台限额 sheet；“＋ 添加平台限额”→ 平台选择 sheet → 平台限额 sheet。
- 替换分组行“替换「X」…”→ 替换分组 sheet；分组 sheet 的“改用替换分组”也进这里。

#### 8.2 数据来源

| 用途 | 接口 | 说明 |
|---|---|---|
| 限额列表 | `GET /api/v1/admin/users/:id/platform-quotas` | `{platform_quotas:[{platform, daily_usage_usd, daily_limit_usd, daily_window_resets_at, weekly_…, monthly_…, daily_window_start, weekly_window_start, monthly_window_start}]}`；`*_limit_usd` null = 不限，0 = 禁止；过期窗口用量已归零、`*_window_resets_at` 为 null |
| 改一个平台 | `PUT /api/v1/admin/users/:id/platform-quotas/:platform` | body `{"daily_limit_usd":10,"weekly_limit_usd":50,"monthly_limit_usd":null}`（严格解码：只能有这三个键；缺失 = null；三项全空 = 删除）→ `{platform_quota, previous}` |
| 取消一个平台 | `DELETE /api/v1/admin/users/:id/platform-quotas/:platform` | → `{removed:true, previous}` |
| 恢复取消前的那条 | `POST /api/v1/admin/users/:id/platform-quotas/:platform/restore` | → `{platform_quota, restored:true}`（限额、用量、窗口起点原样恢复） |
| 重置一个窗口 | `POST /api/v1/admin/users/:id/platform-quotas/reset` | `{"platform":"anthropic","window":"daily"}`（`daily` / `weekly` / `monthly`）→ 完整列表 |
| 整表替换（退路） | `PUT /api/v1/admin/users/:id/platform-quotas` | `{"quotas":[{platform, daily_limit_usd, weekly_limit_usd, monthly_limit_usd}]}`；没提交的平台被软删 |
| 平台显示名 | `GET /api/v1/admin/meta/catalog` | `data.platform_catalog.platforms[].{id, display_name}`（会话缓存，账号章同一份）；缺失时用内置目录 |
| 有效订阅提示 | `GET /api/v1/admin/users/:id/subscriptions` | 有 `status == "active"` 的订阅时显示提示 |
| 替换分组 | `POST /api/v1/admin/users/:id/replace-group` | `{"old_group_id":12,"new_group_id":10}`，可选 `key_ids`、`keep_old_group_access`；可选 Idempotency-Key → `{migrated_keys, migrated_key_ids, new_group_newly_granted}` |

平台 ID 取 `domain.ConcretePlatformIDs()`：`anthropic`、`openai`、`gemini`、`antigravity`、`grok`、`kimi`、`zhipu`、`deepseek`、`minimax`、`typesafe`、`opencode_go`、`command_code`、`cline`（`composite` 不行）。“添加平台限额”列表 = 目录里的具体平台 − 已有限额的平台，按目录顺序。

#### 8.3 字段 → 显示映射

**平台限额分区**：标题“平台限额”，meta“日 · 周 · 月”；用户有有效订阅时顶部 caution 提示“此用户有活跃订阅：平台限额只在余额模式下生效，订阅模式的请求不受限额约束。”；脚注“留空 = 不限制，0 = 禁止使用该平台。月为 30 天滚动窗口。”

| 元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 平台行标题 | `platform` → `display_name` | 任一窗口 limit 为 0 时加 critical 徽章“已禁止使用” | 目录里没有：显示原 ID |
| 三个窗口格（日 / 周 / 月） | `*_usage_usd`、`*_limit_usd` | limit > 0：百分比 + 进度条（≥ 90% critical，≥ 75% caution）+ “$2.80 / $10”（整数不写小数）；limit null：“不限”+“已用 $1.20”；limit 0：“已禁止”+“不能使用” | — |
| 空 | — | “没有设置，各平台不限制” | — |
| 添加 | — | “＋ 添加平台限额” | 所有平台都有限额时隐藏 |

**平台限额 sheet**（标题“<平台> 限额”，右上“保存”，只有窗口真的变了才亮）：说明“留空 = 不限制；**0 = 禁止使用该平台**。月为 30 天滚动窗口。”；三个输入（“日限额 / 周限额 / 月限额”，“$”前缀，占位“不限制”，非负十进制，< 1e10）；输入 0 时提示“填 0 会完全禁止使用 <平台>，不论其他窗口”；limit > 0 时显示该窗口进度条；每格底部“已用 $2.80 · 明天 00:00 重置”（月写“30 天滚动”，重置时间来自 `*_window_resets_at`）与“重置该窗口”（已有限额且该窗口有上限时）；已有限额时底部“清空三个窗口（取消这个平台的限额）”（只清本地输入，仍要按“保存”）；有效订阅提示同分区；脚注“保存和重置都立即生效。”

**替换分组分区**：标题“替换分组”；每个用户拥有的专属分组一行“替换「Claude Code 组」…”，副文“绑定 N 个 Key”；脚注“把一个专属分组换成另一个：绑定的 Key 一起迁移，旧分组的权限随之移除。”

**替换分组 sheet**（标题“替换专属分组”）：说明“选择新分组替换「X」，将自动迁移绑定的 N 个 Key 并更新分组权限。”；单选：专属标准启用分组中用户既没有、草稿里也没加的（副文“<平台> · 专属分组 · 默认倍率 ×1.0”）；空时“没有其他可用的专属分组”；底部按钮“替换为「Y」”（未选时“选择目标分组”禁用）。

#### 8.4 交互与写操作

**保存平台限额**（有 `users.platform_quota_item`）

- 三项都留空且该平台原来有限额：等同取消 → `DELETE .../:platform`（语义更清楚；服务端对全空 PUT 也会删除）。
- 其他：`PUT .../:platform`，留空的窗口发 `null`。
- 成功：用 `platform_quota` 替换该平台行（`null` 表示已删除，移除该行）；回执“已更新 <平台> 的平台限额”/“已取消 <平台> 的平台限额”，带“撤销”：
  - 原来没有限额（`previous == null`）→ 撤销 = `DELETE .../:platform`。
  - 原来有、现在有 → 撤销 = `PUT .../:platform`，body 为 `previous` 的三个 `*_limit_usd`（用量不受影响）。
  - 原来有、现在取消 → 撤销 = `POST .../:platform/restore`（连用量一起恢复）；409 `USER_PLATFORM_QUOTA_ACTIVE_EXISTS` → 回执“已有人重新设置了这个平台的限额，无法恢复”，刷新列表；404 `USER_PLATFORM_QUOTA_NOT_FOUND` → 刷新列表。
- 无能力退路：先 `GET` 最新列表，在它的基础上改这一个平台，再整表 `PUT`；撤销同样“GET → 改回 → PUT”；撤销“取消限额”时回执注明“已用额度会从 0 重新计算”。

**重置该窗口**：确认框“重置 <平台> 的日用量？”，正文“<显示名>在 <平台> 的日用量（$2.80）会归零。此操作立即生效。”，按钮“重置该窗口”（destructive）/“取消” → `POST .../platform-quotas/reset` → 用返回的完整列表替换；回执“已重置 <平台> 日用量”，不可撤销。

**替换分组**

- 确认框：“把「X」替换为「Y」？”，正文“<显示名>绑定在「X」的 N 个 Key 会迁移到「Y」，并移除「X」的使用权限。立即生效，不经过“保存”。”，按钮“确认替换”/“取消”。
- 请求：`POST .../replace-group {"old_group_id":X,"new_group_id":Y}`，带 Idempotency-Key（确认时生成）。
- 成功：回执“分组替换成功，已迁移 N 个 Key”（N = `migrated_keys`），带“撤销”；本地把 `migrated_key_ids` 里的 Key 改到 Y，基线与草稿的专属分组去掉 X、加上 Y，然后刷新 Key 列表与用户资料。
- 撤销（E04）：
  - `migrated_key_ids` 非空：`POST .../replace-group {"old_group_id":Y,"new_group_id":X,"key_ids":<migrated_key_ids>,"keep_old_group_access": !new_group_newly_granted}`。
  - `migrated_key_ids` 为空：**不能**用 replace-group 撤销（空 `key_ids` 等于“迁移全部”，会把用户原本就在 Y 的 Key 也迁走，`service/admin_api_key_group_undo.go:146-150`），改为 `PUT /api/v1/admin/users/:id {"allowed_groups": <当前列表 + X − (new_group_newly_granted ? Y : 无)>}`（先 GET 最新资料再算）。
  - X 已被停用时撤销会 400 `GROUP_NOT_ACTIVE`：回执“原分组已停用，无法撤销”。
- 错误（按 reason 取固定文案，不回显 message）：400 `SAME_GROUP`“新旧分组不能相同”；400 `GROUP_NOT_EXCLUSIVE`“目标分组不是专属分组”；400 `GROUP_IS_SUBSCRIPTION`“订阅分组不能用于替换”；400 `GROUP_NOT_ACTIVE`“目标分组已停用”（以上四个都刷新分组目录并留在 sheet 重选；撤销时的 `GROUP_NOT_ACTIVE` 见上）；400 `KEY_NOT_IN_GROUP`（撤销时 Key 已被改过）→“有 Key 已不在原分组，无法精确撤销”，刷新；404 `GROUP_NOT_FOUND` / `USER_NOT_FOUND`。

#### 8.5 状态

| 状态 | 显示 |
|---|---|
| 限额加载失败 | 分区内“平台限额加载失败 · 重试” |
| 限额服务未启用 | 503 `SERVICE_UNAVAILABLE`（`platform quota service not available`）：分区写“站点没有启用平台限额” |
| 保存校验失败 | 400 `INVALID_QUOTA_LIMIT`：本地已按同一规则校验（非负、有限、< 1e10），正常不会出现；万一出现 sheet 底部红字“限额要大于等于 0、小于 100 亿”（服务端没有 `metadata` 指明哪一档，不解析 message，不定位到具体窗口）。400 `VALIDATION_ERROR` / `INVALID_PLATFORM` 不应出现，按通用约定 §3.3 显示“请求无效（错误码 VALIDATION_ERROR / INVALID_PLATFORM）”，不显示 message |
| 用户不存在 | 404 `USER_NOT_FOUND`：回到列表 |
| 重置不存在的限额 | 404 `USER_PLATFORM_QUOTA_NOT_FOUND`：刷新列表 |

#### 8.6 刷新策略

切到该段时刷新一次限额列表；每次写后用响应替换；不轮询（窗口用量随计费变化，用户需要时下拉刷新）。

#### 8.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/PlatformQuota.swift`：`UserPlatformQuota`（三个窗口的 usage / limit / resetsAt；limit 区分 null 与 0）、`PlatformQuotaLimits` 编码（null 必须编码成 JSON `null` 或省略，PUT 严格解码不接受未知键）、`PlatformQuotaUndo` 决策纯函数（previous / current → DELETE / PUT / restore），配单测。
- `APIClient`：新增 `platformQuotas(userID:)`、`upsertPlatformQuota(userID:platform:limits:)`、`deletePlatformQuota(userID:platform:)`、`restorePlatformQuota(userID:platform:)`、`resetPlatformQuotaWindow(userID:platform:window:)`、`replaceUserPlatformQuotas(userID:quotas:)`（退路）、`replaceUserGroup(userID:request:idempotencyKey:)`。
- 新视图：`NativeApp/Features/Users/PlatformQuotaSection.swift`（含 sheet）、`ReplaceGroupSheet.swift`。

---

### 9. 本章跨章依赖

- **会话与通用约定**：`/admin/me` 的取得与缓存（capabilities、`user.id`、`run_mode`、`server_timezone`、step-up 状态）；错误解码要保留 `reason`、`metadata` 与 `Retry-After`（现在 `APIError` 只有 reason / status）；`APIClient` 返回响应头的请求变体与 304 处理；Idempotency-Key 生成与重试器（`IDEMPOTENCY_IN_PROGRESS` / `RETRY_BACKOFF` 按 `Retry-After`）；回执（Toast + 撤销）组件与时长；状态胶囊；金额、相对时间格式；只读令牌 `ACCESS_TOKEN_READ_ONLY` 提示；二次验证 sheet（6 位自动提交）。
- **会话与通用约定 §2.5.4 第 4 条**：该条要求“待核对的对象在核对完成前禁止发起新的同类写入”；本章 §3.4 按设计稿 `vuTopup` 允许同方向余额调整经两次确认后“仍要充值 / 仍要退款”，属于例外（兑换码章“仍要生成新的一批”同类）。00 章需要把这个例外和文案登记进去；登记前，余额调整按本章 §3.4 实现。
- **设置**：“高风险操作需要 Face ID”开关与金额门槛；设置里的“待核对余额”列表（调用本章 §3 的核对函数）；分组目录与平台目录的会话缓存。
- **概览**：“待处理 · 充值结果待核对”一项（数据来自 `pendingBalances`，点进用户详情）。
- **使用记录**：用户详情“使用记录 ›”进入 `{scope: usage, user: id}`，`admin/usage` 按 `user_id`、错误请求按 `user_id` 筛选，上游错误胶囊置灰。
- **兑换码**：用户详情 ⋯“发放兑换码（补偿）…”的向导 sheet（`POST /api/v1/admin/redeem-codes/create-and-redeem`，code 由 App 生成，强制 Idempotency-Key）；成功后本章刷新用户资料与记录。
- **分组**：分组目录（`groups/all?include_inactive=true`）同一份缓存；分组详情页的“API 密钥”列表复用本章的 Key 状态映射。
- **搜索**：全局搜索里的“用户”一路（`GET /api/v1/admin/users?search=`）点进本章用户详情。

---

### 10. 新增类型与接口汇总（Sub2Core）

| 方法（建议名） | 接口 |
|---|---|
| `users(query:ifNoneMatch:)` | `GET /api/v1/admin/users` |
| `user(id:)` | `GET /api/v1/admin/users/:id` |
| `createUser(_:idempotencyKey:)` | `POST /api/v1/admin/users` |
| `updateUser(_:)` | `PUT /api/v1/admin/users/:id` |
| `deleteUser(id:)` | `DELETE /api/v1/admin/users/:id` |
| `updateBalance(_:)` | `POST /api/v1/admin/users/:id/balance` |
| `userAdjustments(query:)` | `GET /api/v1/admin/user-adjustments` |
| `quickTopup()` | `GET /api/v1/admin/users/quick-topup` |
| `usersTodayUsage(ids:)` | `POST /api/v1/admin/dashboard/users-usage` |
| `userMonthUsage(id:timezone:)` | `GET /api/v1/admin/usage/stats` |
| `balanceHistory(userID:page:pageSize:)` | `GET /api/v1/admin/users/:id/balance-history` |
| `userAPIKeys(userID:page:)` | `GET /api/v1/admin/users/:id/api-keys` |
| `apiKey(id:)` | `GET /api/v1/admin/api-keys/:id` |
| `createUserAPIKey(userID:_:idempotencyKey:)` | `POST /api/v1/admin/users/:id/api-keys` |
| `updateAPIKey(id:_:)` | `PUT /api/v1/admin/api-keys/:id` |
| `deleteAPIKey(id:)` | `DELETE /api/v1/admin/api-keys/:id` |
| `revealAPIKey(id:)` | `POST /api/v1/admin/api-keys/:id/reveal` |
| `apiKeysTodayUsage(ids:)` | `POST /api/v1/admin/dashboard/api-keys-usage` |
| `userRPMStatus(id:)` | `GET /api/v1/admin/users/:id/rpm-status` |
| `platformQuotas(userID:)` 等 6 个 | `GET`/`PUT /api/v1/admin/users/:id/platform-quotas`、`PUT`/`DELETE .../:platform`、`POST .../:platform/restore`、`POST .../reset` |
| `replaceUserGroup(userID:_:idempotencyKey:)` | `POST /api/v1/admin/users/:id/replace-group` |
| `userSubscriptions(userID:)` | `GET /api/v1/admin/users/:id/subscriptions` |
| `userAttributeDefinitions()` | `GET /api/v1/admin/user-attributes?enabled=true` |
| `userAttributes(userID:)` / `updateUserAttributes(userID:values:)` | `GET` / `PUT /api/v1/admin/users/:id/attributes` |
| `stepUp(code:)`（已有） | `POST /api/v1/user/totp/step-up` |

测试（`Tests/Sub2CoreTests`）至少覆盖：余额低判定（含 percentage、全局关、用户阈值）、Key 状态推导（含 simple 模式）、记录标题与数值文本、`UserUpdateRequest` 的 `group_rates` null 编码、`allowed_groups` 组装（保留未知 ID、关限制去公开分组）、平台限额撤销决策、账本核对匹配（含服务端忽略筛选参数返回无关行、候选匹配不自动 `resolve`，见 §3.7）、余额写结果判定 `balanceWriteOutcome`、键盘输入 `KeypadInput`、`PendingBalanceOperation` 旧记录解码。

---

### 11. 本章未决问题

1. **Key 新建 / 编辑表单没有设计稿**（设计稿只有“需后端新增”占位）。建议默认：按 §7.4 的最小表单实现（与 Web 用户端“创建 Key”同字段，单页 Form，sheet 呈现），上线前请用户看一次效果图再定。
2. **揭示完整 Key 的入口位置**：设计稿没有画。建议默认：放在 Key 卡片 ⋯ 菜单第三项“显示完整 Key…”，每次都要本机身份验证 + 服务端 step-up（开关开时）。
3. **`percentage` 阈值在 `total_recharged` 为 0 时的口径**：服务端 `quick-topup` 把阈值数字当美元用（`admin_quick_topup_repo.go:83-86`），附录 B L22 建议“宁可不标”。建议默认：列表行与详情跟服务端一致（同一屏不出现头像条和列表打标不一致），并请后端确认这是否是有意为之。
4. **“全部余额”退款用 `set 0`**：会在账本里记为 `operation=set`、标题“余额扣除（管理员）”。建议默认：采用（避免确认期间计费扣款导致 subtract 超额、被服务端以无 reason 的 500 拒绝后进入待核对）。
5. **`multi_select` 类型的自定义属性值格式**：本章没核实 Web 写入的值格式。建议默认：App 只读显示原值，编辑提示“在 Web 端修改”。
6. **主模式用户列表是否需要状态筛选（全部 / 启用 / 禁用）**：设计稿没有，现有 App 有。建议默认：主模式去掉（搜索已够用），留给简化模式。
7. **余额扣成负数、禁用 / 删除管理员、降级最后一位管理员等后端返回无 reason 的 500**：App 只能事前拦截。建议默认：按本章事前拦截实现，同时请后端给这几处补稳定 reason（如 `BALANCE_NEGATIVE`、`ADMIN_USER_PROTECTED`、`LAST_ADMIN`），之后 App 改为按 reason 显示。
8. **全部记录页给管理员调整行加第三行“余额 a → b · 操作人”**：设计稿记录行只有两行（设计时还没有前后余额）。建议默认：只在“全部记录”页加，详情页最近 5 条保持两行。

---

## 40 · 统计分析与日志

本章覆盖 7 个页面：统计分析（`analytics`，卡片流）、更多图表（`analyticsMore`）、单图页（`analyticsChart`）、全部排行（`analyticsRank`）、模型页（`analyticsModel`）、使用记录（`logs`）、请求详情（`request`）。

- 口径：`DECISIONS.md`（第 3 轮以更正后为准，文末 10-18 评审意见与 TPM 口径最新）；后端行为以 `BACKEND-API-CHANGES.md` 进度表备注为准。
- 接口：全部在 sub2 后端 HEAD `70116315d`（2026-10-22）源码里核对过路由、参数、字段名和 reason。下文接口路径省略前缀 `/api/v1`。
- 设计稿对照：`html-preview/layouts/main/v-analytics.jsx`（已定变体都是 base）、`00-core.jsx` 的 `LogsScreen` / `LogRow` / `RequestDetail`。

---

### 0. 本章共用规则

#### 0.1 路由

| route | 参数 | 说明 |
|---|---|---|
| `analytics` | `range`：`today` \| `last7`（入口默认值，只在这个站点还没有记忆时生效，见下方“状态共享与记忆”）；`focus`：`perf`（可选）；`metric`：`rpm` \| `tpm`（可选） | 卡片流 |
| `analyticsMore` | `chart`（图表 key，可选）；`topic`：`billing` \| `usage` \| `ops`（可选） | 按主题分组的图表列表 |
| `analyticsChart` | `chart` | 一张图全屏 |
| `analyticsRank` | `dim`：`model` \| `user` \| `group` | 全部排行 |
| `analyticsModel` | `model`（字符串）；`source`：`requested` \| `upstream` \| `mapping` | 模型页 |
| `logs` | `scope`：`usage` \| `errors` \| `upstream`；`account` / `group` / `user`：`{id, name?}`；`model`（字符串）；`modelSource`（默认 `requested`） | 使用记录 |
| `request` | `.usage(record)` \| `.usageRequestID(String)` \| `.error(id, kind: request \| upstream, initial?)` | 请求详情 |

图表 key：`billing`（计费明细）、`profit`（利润明细）、`tokens`、`userTrend`、`endpoints`、`reqType`、`perf`、`switch`、`latency`、`errTrend`、`errDist`、`tokenSpeed`。

**状态共享与记忆**（设计稿 `v-analytics.jsx` 头注释“选过的范围、筛选……在本机记住，二级页沿用”与 `useAxMemo` / `useAxRange`）：

- `analytics` 与它推出的 More / Chart / Rank / Model 共用一个 `AnalyticsSession`（`@Observable`）。其中**各卡的加载状态与数据缓存**只在这一次统计分析导航栈内有效，退出即丢弃。
- **选择项在本机记住**，按站点区分（`UserDefaults`，键 `analytics.<站点 id>.<项>`），二级页与下一次进入都沿用：范围（预设存键名，如 `today` / `last7` / `lastMonth`，进入时按当天重算；自选存起止日期）、筛选（分组 id 或模型名）、排行卡当前分段、全部排行每个维度的排序指标与模型口径。用户改动后立即写入。
- **入口默认值只在第一次用**：进入时先读这个站点的记忆；没有记忆（这个站点第一次进统计分析）才用 route 的 `range`（概览进来“今天”、搜索目录进来“近 7 天”）。有记忆时从概览“今日”格进来也显示记住的范围（设计稿就是这样）。
- 记忆失效：记住的分组在 `groups/all` 里已不存在 → 丢弃这项筛选；自选范围的起点早于 366 天前 → 丢弃范围记忆，改用入口默认值。切换站点读另一套记忆；退出登录不清（只是界面偏好，不含数据），删除站点时一并删除。
- RPM / TPM 卡的窗口（近 1 / 6 / 24 小时）和指标（RPM / TPM）同样按站点存 `@AppStorage`（键里带站点 id），凡是出现这张图的地方共用；`route.metric` 优先于记忆值，并写回记忆。

#### 0.2 时区与时间参数

- 站点时区 TZ：`GET /admin/me` → `data.server.server_timezone`；拿不到时用 `GET /settings/public` → `server_timezone`。
- “今天 / 昨天 / 按小时 / 按天”的边界、每个请求的 `timezone=` 参数、横轴标签、日志里显示的时刻，全部按 TZ。理由：首页 6 格的“今日”来自 `dashboard/stats`，后端固定按服务器时区算；统计分析“今天”的利润必须等于首页利润。设备时区与 TZ 不同时，范围说明行和日志副标题末尾加“（站点时间 UTC+8）”。设计稿自定义范围 sheet 里的“按本机时区计算”一律改为“按站点时区计算”。
- 时间参数成对传 `start_time` / `end_time`（RFC3339，统一写 UTC `Z` 形式，省去 `+` 的编码），左闭右开；同时带 `timezone=<TZ>`（决定桶边界与 `date` 标签）。后端 `usagequery.ParseRange` 要求两者成对，只传一个返回 400。
- 日历运算用设了 TZ 的 `Calendar`（夏令时日不能用 86400 秒相加）。
- 后端不补空桶的接口：`dashboard/trend`、`dashboard/users-trend`（只返回有数据的桶），App 按范围补 0。`ops/dashboard/throughput-trend`、`error-trend` 后端已补齐。

#### 0.3 能力探测与降级

切站 / 启动时取 `GET /admin/me`（缓存方式见通用约定章节）。本章用到：

| 判断 | 来源 | 用途 |
|---|---|---|
| 运维监控 | `data.features.ops_monitoring_enabled`、`ops_monitoring_disabled_reason`（`config_off` / `setting_off`） | false 时不发 `ops/*` 请求，直接显示“运维监控未开启”；仍要处理 404 `OPS_DISABLED`（多实例间开关最多晚 30 秒同步） |
| vendor | `data.workspace` 非空 | 见 0.7 |
| `dashboard.account_cost` | `data.server.capabilities` | 趋势点带 `account_cost`（B02） |
| `usage.model_source` | 同上 | `admin/usage`、`usage/stats`、`dashboard/*` 接受 `model_source`（B03） |
| `dashboard.users_ranking_sort` | 同上 | users-ranking 的 `sort_by`、`total_users`、成本字段（B04） |
| `dashboard.request_types` | 同上 | `dashboard/request-types`（B05） |
| `ops.dashboard_model_filter` | 同上 | `ops/dashboard/*` 接受 `model` + `model_source`（B06） |
| `ops.token_stats_custom_range` | 同上 | `openai-token-stats` 接受 `start_time` / `end_time`（B07） |
| `dashboard.users_trend_filtered_metric` | 同上 | users-trend 带筛选时 `metric` 生效（B12） |
| `logs.since_id` | 同上 | `admin/usage`、`ops/request-errors` 的 `since_id`（B09） |
| `ops.request_attempts` | 同上 | `ops/requests/:request_id/attempts`（D10） |
| `api_keys.masked_view` | 同上 | `key_view=masked`（E03） |

B01、B02、B03、D03（上游错误身份筛选）、D04（错误日志耗时）、D05（使用记录 `account_cost`）都早于 `/admin/me` 合入（已核对提交顺序），D03 / D04 / D05 没有单独的能力标记：`GET /admin/me` 返回 404 的服务端按“这几项都没有”处理；解码时再按字段兜底一次（键不存在 = 旧服务端，不当作 0）。

#### 0.4 口径与措辞

| 名称 | 定义 | 后端字段 |
|---|---|---|
| 实际扣费 | 用户实际被扣的金额 | `actual_cost`、`total_actual_cost` |
| 标准 | 未乘分组倍率的标价 | trend / models / groups 的 `cost`，usage/stats 的 `total_cost`，使用记录的 `total_cost` |
| 账号成本 | 上游账号的成本，只算 `provider_cost_recorded` 的行 | `account_cost`、`total_account_cost` |
| 利润 | 实际扣费 − 账号成本 | App 计算 |
| RPM / TPM（趋势图） | 每桶 数量 × 60 ÷ 这一桶实际覆盖的秒数；RPM 含成功与错误请求，TPM 为成功请求的含缓存 Tokens（input + output + cache_creation + cache_read） | throughput-trend 的 `request_count`、`token_consumed` |
| 错误率 · SLA | SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制 | ops overview 的 `error_rate` |

- 界面上不出现“营收”“上游成本”“差额”“毛利”“实际消费”。卡片名固定：计费趋势、计费明细、利润明细、RPM / TPM 趋势。
- 利润不加“+”，亏损写“−$12.30”；计费数字不着色；增减箭头只表方向，不用红绿。
- 请求类型显示名：`stream` 流式、`sync` 同步（请求详情“方式”里写“非流式”）、`ws_v2` WS（详情写 WebSocket）、`cyber` 安全策略、`live` Live、`unknown` —。
- 阶段 `phase`：request 请求校验、auth 鉴权、account_auth 账号鉴权、routing 路由、upstream 上游、network 网络、internal 网关内部；责任方 `error_owner`：client 客户端、provider 上游服务商、platform 平台配置；未知值原样显示。
- 状态码颜色（codeTone）：2xx ok；429 琥珀（caution）；其余失败（含 504、529）红（critical）；业务限制灰。

#### 0.5 数字格式

- 金额：`$1,284.50`；负数用 U+2212 `−$12.30`；日志行的单条金额 < $1 显示 4 位小数（`$0.0124`），否则 2 位；请求详情的三格金额固定 4 位；缺失 `—`，0 显示 `$0.00`。解码用 `Decimal`，显示时四舍五入。
- 计数：千分位 `18,204`；大数 compact：`240K`、`96.4M`（1 位小数，去掉 `.0`）。
- 日志行与请求详情的耗时：秒，1 位小数（`0.6s`、`42.1s`），≥ 100 秒取整（`182s`）。分位数表的耗时：< 1 秒 `820ms`，1–10 秒 `2.4s`，≥ 10 秒 `42s`。
- 百分比：1 位小数（`98.3%`）；占比条上的百分比同。
- RPM：≥ 10 取整，< 10 保留 1 位，0 显示 `0`；TPM 用 compact。
- 增减：`↑ 12.3% · 比昨天同时`。

#### 0.6 请求与加载

- 每张卡 / 每张图一个独立加载状态（沿用 `DashboardLoadState` 与 `isCurrent` 守卫），独立超时、失败、重试，一个失败不影响其他。
- 超时：`dashboard/*` 60 秒，`admin/usage/stats` 90 秒，`ops/dashboard/*` 45 秒（范围超过 24 小时时 90 秒），日志列表与详情 45 秒。
- 降级扇出（逐段 usage/stats 等）并发上限 4。
- 本章接口都没有 ETag（后端只给 dashboard/stats、users、groups、snapshot-v2 加了），不发 `If-None-Match`；`URLSessionTransport` 继续禁用 URLCache。
- 错误不回显服务端 message（沿用 `APIError.server`），按 `reason` 分支。

#### 0.7 vendor（代运营工作区）

后端只对 vendor（监控档）开放 `GET /admin/usage*`（`search-users`、`search-api-keys`、`cleanup-tasks` 除外）与 `dashboard/trend`、`dashboard/models`、`dashboard/groups`；其余本章接口 403，`ops/*` 全部不开放。vendor 进入统计分析：只有计费趋势、利润明细、排行卡（模型 / 分组两段）；没有 RPM / TPM 卡、更多图表里没有“运行”主题、用户用量趋势和请求类型。使用记录只有“用量明细”一段，筛选 sheet 没有“用户”组；用户邮箱已被后端打码，照原样显示。

---

### 1. 统计分析（`analytics`，卡片流）

#### 1.1 入口与导航

- 进入（`range` 只是入口默认值，有记忆时用记忆，见 0.1）：
  - 概览“今日”区的“更多统计 ›”，以及 6 格中的今日实际扣费 / 请求 / 错误率 / 利润 → `analytics(range: today)`。
  - 6 格的 RPM、TPM → `analytics(range: today, focus: perf, metric: rpm | tpm)`：首次出现时滚到 RPM / TPM 卡并切到该指标（只滚一次）。
  - 搜索目录“资源 · 统计分析” → `analytics(range: last7)`。
  - 分组详情没有统计入口（50 章已删除旧的“统计分析”链接），所以 route 不带预置分组筛选。
- 导航栏：标题“统计分析”；副标题“<站点名> · 刚刚更新”（取各卡里最早一次成功加载的时间，写“N 分钟前更新”）；右侧筛选按钮（`line.3.horizontal.decrease`）。
- 卡片顺序：范围条 → 计费趋势 → 利润明细 → 排行 → RPM / TPM 趋势 → 更多图表。
- 去向：计费趋势卡底 → `analyticsChart(billing)`；利润明细卡底 → `analyticsChart(profit)`；排行行 → 模型页 / 用户详情 / 分组详情；排行卡底 → `analyticsRank(dim)`；RPM / TPM 卡底 → “性能明细” sheet；更多图表磁贴 → `analyticsMore(chart:)`；“全部图表” → `analyticsMore()`。

#### 1.2 范围与筛选（本页与二级页共用）

**范围**：`Picker(.segmented)`：今天 · 7 天 · 30 天 · 自定义（选了预设后显示预设名，如“上月”）。再点已选中的段不动作；说明行是回到自定义 sheet 的入口。

| 选项 | start | end | 粒度 | 范围名 | 对比窗口 | 对比文案 |
|---|---|---|---|---|---|---|
| 今天 | TZ 今日 00:00 | 现在 | hour | 今天 | 昨日 00:00 → 昨日同一时刻 | 比昨天同时 |
| 7 天 | 今日 − 6 天 00:00 | 现在 | day | 近 7 天 | 前推 7 天，止于第 7 天前的同一时刻 | 比前 7 天同期 |
| 30 天 | 今日 − 29 天 00:00 | 现在 | day | 近 30 天 | 前推 30 天同期 | 比前 30 天同期 |
| 本月 | 本月 1 日 00:00 | 现在 | day | 本月 | 上月 1 日 → 上月同日同一时刻（上月没有这天取月末） | 比上月同期 |
| 近 14 天 | 今日 − 13 天 00:00 | 现在 | day | 近 14 天 | 前推 14 天同期 | 比前 14 天同期 |
| 上月 | 上月 1 日 00:00 | 本月 1 日 00:00 | day | 上月 | 上上月整月 | 比 8 月 |
| 自选多天 | 起日 00:00 | 止日次日 00:00；止日是今天时为现在 | day | 自选 N 天 | 紧邻在前、等长的 N 天（含今天时取同期） | 比前 N 天 / 比前 N 天同期 |
| 自选单天 | 当日 00:00 | 次日 00:00；今天为现在 | hour | 今天 / 昨天 / 10月14日 | 前一天（今天时取同期） | 比昨天同时 / 比前一天 |

- 说明行（Button，带日历图标与 ›）：`10月16日 周五 · 00:00 至 09:41 · 按小时`；多天 `10月10日 – 16日（今天到 09:41）· 按天`，跨月写全 `9月17日 – 10月16日`；过去的单天 `10月15日 周四 · 按小时`。
- 自定义 sheet（标题“自定义范围”，右上“应用”）：快捷胶囊 本月 / 近 14 天 / 上月；下面“开始 · 10月1日 周三 00:00”“结束 · 10月16日 周五 现在（09:41）/ 24:00”两行，点一行展开一个 `DatePicker(.graphical)`，一次只选一天，不画区间底色；改了起止后快捷胶囊取消选中，若正好等于某个快捷项则自动选中它；底部说明“共 N 天，按天统计（只选一天按小时）；按站点时区计算。”。可选日期：最早 366 天前，最晚今天；开始晚于结束时把另一端对齐。后端不提供站点开通日期，不写设计稿里“站点 X 月 X 日开通”那句。
- 范围改变：除 RPM / TPM 卡（自有滚动窗口）外，所有卡清空旧值重新加载。

**筛选**：导航栏按钮打开 sheet；同一时间只有一个条件（分组或模型）。

- sheet 标题“筛选”：`Segmented` 分组 / 模型；第一行“全部分组 / 全部模型”（单选圆点）。
  - 分组：`GET /admin/groups/all?include_inactive=true`，按 `sort_order` 排；停用分组加“停用”标签，照样可选。右侧数字为当前范围内该组实际扣费占比（取当前范围 `dashboard/groups` 的结果，没有用量写 `0.0%`）。
  - 模型：当前范围 `dashboard/models?model_source=requested` 的全部模型（等宽字体），按实际扣费降序，右侧占比同理。
  - 底部说明：分组——“筛选后趋势、合计、排行和运行类图表都只算这个分组。分组按请求时 Key 所属的分组算：用户排行只算各用户在这个分组 Key 上的用量，一个用户的 Key 分属几个分组时，会出现在几个分组里。”；模型——有 `ops.dashboard_model_filter` 时“运行类图表也只算这个模型。”，没有时“运行类图表（RPM / TPM、时长、错误）后端不支持按模型，仍显示全站。”
- 选中后范围说明行右侧出现可移除胶囊“分组：高级组 ✕” / “模型：claude-opus-4 ✕”（模型名等宽），点胶囊即清除。
- 参数映射：

| 接口 | 分组筛选 | 模型筛选 |
|---|---|---|
| `admin/usage/stats`、`dashboard/trend`、`dashboard/models`、`dashboard/groups`、`dashboard/users-ranking`、`dashboard/users-trend`、`dashboard/request-types` | `group_id=<id>` | `model=<name>&model_source=<requested \| upstream \| mapping>`（筛选 sheet 选出的是 requested；从上游 / 映射口径的排行进模型页时用那个口径） |
| `ops/dashboard/*`（throughput-trend、overview、latency-histogram、error-trend、error-distribution、openai-token-stats） | `group_id=<id>` | 有 `ops.dashboard_model_filter` 且口径为 requested / upstream：`model=<name>&model_source=<口径>`；mapping 口径或没有该能力：不传 model，卡头加一行“运行类图表不支持按这个模型筛选，这里显示全站” |

注意：`dashboard/models` 的 `model_source` 是“按哪种模型名分组”的维度，不是筛选条件；`ops/dashboard/*` 的 `model_source` 只认 requested / upstream，传 mapping 返回 400。

#### 1.3 数据来源

| 区块 | 请求 | 关键参数 | 能力 / 降级 |
|---|---|---|---|
| 计费趋势 · 合计 | `GET /admin/usage/stats` | 范围、筛选、`timezone` | — |
| 计费趋势 · 对比 | `GET /admin/usage/stats` | 对比窗口、同一筛选 | 失败只隐藏增减行 |
| 计费趋势柱图、利润明细 | `GET /admin/dashboard/trend` | 范围、筛选、`granularity=hour \| day` | 点里没有 `account_cost` 键（旧服务端）：利润逐段调 `usage/stats?start_time=&end_time=`（今天每小时一次、30 天 30 次，并发 4），失败的段显示 `—` |
| 排行 · 模型 | `GET /admin/dashboard/models` | 范围、分组筛选、`model_source=requested` | — |
| 排行 · 用户 | `GET /admin/dashboard/users-ranking` | 范围、筛选、`limit=5`、`sort_by=actual_cost` | vendor 不显示；没有 `dashboard.users_ranking_sort` 时不传 `sort_by`，也没有 `total_users` |
| 排行 · 分组 | `GET /admin/dashboard/groups` | 范围、模型筛选 | — |
| RPM / TPM 趋势 | `GET /admin/ops/dashboard/throughput-trend` | 见 1.4 | 运维监控关闭：换成“运维监控未开启” |
| 更多图表磁贴 | 见第 2 节各图 | 磁贴出现在屏幕上时才请求 | — |

排行卡只请求当前选中的那一段；切到另一段时再请求，结果缓存到范围或筛选改变为止。

**响应字段**（本页用到的）：

- `usage/stats`：`total_requests`、`total_tokens`、`total_input_tokens`、`total_output_tokens`、`total_cache_creation_tokens`、`total_cache_read_tokens`、`total_cost`、`total_actual_cost`、`total_account_cost`（可缺省）、`average_duration_ms`、`endpoints[]`、`upstream_endpoints[]`（各 `{endpoint, requests, total_tokens, cost, actual_cost}`，无数据时省略）。
- `dashboard/trend`：`trend[]{date, requests, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, total_tokens, cost, actual_cost, account_cost?}`、`granularity`、`query`。`date`：按小时 `2026-10-16 09:00`，按天 `2026-10-16`（按传入 TZ）。
- `dashboard/models`：`models[]{model, requests, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, total_tokens, cost, actual_cost, account_cost}`；mapping 口径时 `model` 形如 `claude-opus-4 -> claude-opus-4-20250514`。
- `dashboard/groups`：`groups[]{group_id, group_name, requests, total_tokens, cost, actual_cost, account_cost}`。
- `dashboard/users-ranking`：`ranking[]{user_id, email, username, actual_cost, cost, account_cost, requests, tokens}`、`total_users`、`total_actual_cost`、`total_cost`、`total_account_cost`、`total_requests`、`total_tokens`（`limit` 默认 12、最大 50；`sort_by` 非法 400 `INVALID_SORT_BY`）。

#### 1.4 字段 → 显示

**计费趋势卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “计费趋势”；右侧图例：灰柱“实际”、点线“标准（点线）” | — |
| 大数标签 | — | “实际扣费 · <范围名>”；选中柱时为该桶全名（`10月16日 8:00–9:00`、当前小时 `9:00–9:41`、按天 `10月14日 周三`） | — |
| 大数 | usage/stats `total_actual_cost`；选中时为该点 `actual_cost` | 金额 | 请求失败 `—`，卡内错误行 |
| 增减 | `total_actual_cost` ÷ 对比窗口 `total_actual_cost` − 1 | `↑ 8.2% · 比昨天同时` | 对比为 0 或缺失：`比昨天同时 —` |
| 选中副行 | 该点 `cost`、`requests` | `标准 $x · 请求 n · 再点一下取消` | — |
| 柱 | 每桶 `actual_cost` | 灰柱；范围含“现在”时最后一根加深，横轴写“现在”（按小时）/“今天”（按天） | 整段都是 0：保留坐标轴，图上写“这个范围内没有用量” |
| 点线 | 每桶 `cost`（标准） | 点线 | — |
| 横轴 | 桶 | 按小时 `0时…9时`，按天 `10/10`；≤ 8 桶每个都标，≤ 12 隔 3，≤ 24 隔 6，更多隔 7（按天从最后一个往前数） | — |
| 账号成本 / 标准 / 利润 三格 | `total_account_cost`；`total_cost`；`total_actual_cost − total_account_cost` | 金额 | `total_account_cost` 缺失：账号成本、利润 `—` |
| 请求 · Tokens · 平均耗时 | `total_requests`；`total_tokens`；`average_duration_ms` | `18,204`；`96.4M`；耗时 | 请求 0 时平均耗时 `—` |
| 卡底 | 桶数 | “全部 10 小时 · 计费明细 ›” / “全部 7 天 · 计费明细 ›” | — |

**利润明细卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “利润明细”；右侧“实际扣费 − 账号成本” | — |
| 大数 | usage/stats `total_actual_cost − total_account_cost`；选中时该桶利润 | 标签“利润 · <范围名>” / 桶全名 | `total_account_cost` 缺失 `—` |
| 增减 | 对比窗口的利润 | 两边都 > 0：百分比；任一边 ≤ 0：金额差 `↑ $86.20 · 比昨天同时` | 对比缺失 `—` |
| 选中副行 | 该桶实际、账号成本 | `实际 $x · 账号成本 $y · 再点一下取消` | — |
| 柱 | 每桶 `actual_cost − account_cost` | 可为负：从 0 往下画，`RuleMark(y: 0)` 零线，y 轴范围含 0，负柱不换颜色 | 整段扣费都为 0 才写“这个范围内没有扣费”；全部亏损不算空 |
| 明细表（最近 4 段，最新在上） | 时段 / 实际 / 账号成本 / 利润 | 时段：按小时 `8:00–9:00`（当前 `9:00–9:41`），按天 `16日 周五`；选中的桶这一行高亮 | 降级时失败段的账号成本、利润 `—` |
| 卡底 | — | “全部 10 小时 · 利润明细 ›” | — |

分段取整：实际、账号成本各自以 usage/stats 的合计（换算成分）为总数，按各桶原值用最大余额法分到分，利润 = 两者之差。这样各行之和等于合计；范围为今天时，合计利润等于首页 6 格的利润（后端统计未过期时）。

**排行卡**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “排行”；右侧“实际扣费 · 前 5” | — |
| 分段 | — | 模型 · 用户 · 分组（本机记住上次所选，见 0.1） | vendor 无“用户” |
| 分组筛选下的用户说明 | — | “按请求时 Key 所属的分组统计：只算各用户在「高级组」Key 上的用量。” | 无分组筛选不显示 |
| 行 · 序号 | 名次 | 1–3 加粗 | — |
| 行 · 名称 | 模型 `model`（等宽）；用户 `username`，空时 `email`；分组 `group_name` | 单行截断 | — |
| 行 · 占比条 | 该行 `actual_cost` ÷ 合计；模型 / 分组的合计 = 全部行之和；用户的合计 = `total_actual_cost` | 细条 | — |
| 行 · 金额 | `actual_cost` | 金额 | — |
| 当前段正是筛选维度 | — | 不列排行，显示“已筛选分组：高级组　清除筛选” | — |
| 卡底（行数 > 5） | 模型 / 分组的总行数 | “全部 12 个模型 · 含上游口径 ›”、“全部 9 个分组 ›”、“查看前 50 位用户 ›” | — |
| 空 | — | “这个范围内没有模型用量”（用户 / 分组同理） | — |

**RPM / TPM 趋势卡**（与第 2 节同一组件 `PerfTrendBody`）

请求 `GET /admin/ops/dashboard/throughput-trend?start_time=&end_time=[&group_id=][&model=&model_source=]`：`end_time` = 现在向下取整到整分钟，`start_time` = `end_time` − N 小时（N = 1 / 6 / 24）。不传 `mode`（后端不读）。后端按窗口定桶长：≤ 2 小时 60 秒、≤ 24 小时 300 秒、更长 3600 秒，响应 `bucket` 为 `1m` / `5m` / `1h`；不认识的值按这条规则从窗口长度推算。响应 `points[]{bucket_start, request_count, token_consumed, switch_count, qps, tps}`（`qps` / `tps` 已四舍五入到 0.1，不用）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 卡头 | — | “RPM / TPM 趋势”；右侧“截至现在 · 运维监控” | — |
| 模型筛选提示 | 见 1.2 | “运行类图表不支持按模型筛选，这里显示全站” | — |
| 窗口分段 | — | 近 1 小时 · 近 6 小时 · 近 24 小时 | — |
| 指标分段 | — | RPM · TPM（`route.metric` 优先于记忆值） | — |
| 每点覆盖秒数 | `min(bucket_start + 桶秒数, end_time) − max(bucket_start, start_time)` | — | ≤ 0 的点丢弃 |
| 每点速率 | RPM = `request_count × 60 ÷ 覆盖秒数`；TPM = `token_consumed × 60 ÷ 覆盖秒数` | 见 0.5 | — |
| 大数 | 未选中：最新一点；选中：该点 | 标签“RPM · 最新一桶 09:40” / “RPM · 09:12” | — |
| 副行 | 峰值 = 各点最大值；平均 = Σ数量 × 60 ÷ Σ覆盖秒数 | `峰值 52 · 平均 44 · 近 1 小时`；选中时 `09:12 · RPM 47 · 再点一下取消` | — |
| 折线 + 面积 | 每点速率 | `LineMark` + `AreaMark`；选中点画竖线与圆点 | 全为 0：“这个时间范围内没有请求” |
| 横轴 | `bucket_start`（TZ） | 近 1 小时每 15 分钟、近 6 小时每 2 小时、近 24 小时每 6 小时，只标整刻度，`HH:mm` | — |
| 说明 | 桶长、窗口起点 | “每桶 1 分钟，速率 = 数量 × 60 ÷ 这一桶实际覆盖的秒数；窗口从 08:41 到现在，首尾不满一桶的按覆盖时长折算。RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。” | — |
| 更新时间 | 最后一次成功 | “更新于 09:41:00 · 前台每 30 秒刷新” | — |
| 卡底 | 点数 | “性能明细 · 61 桶 · 最新在上 ›” | — |
| 性能明细 sheet | 每点 | 标题“性能明细”，左上“关闭”；说明“最新在上 · 近 1 小时 · 每桶 1 分钟。点一行，图上选中这个时间。”；行：`09:40` / `09:40 · 只覆盖 23 秒`（不满一桶），`RPM 46 · TPM 240K`；点行关闭 sheet 并选中该点 | — |
| 运维监控未开启 | `ops_monitoring_enabled=false` 或 404 `OPS_DISABLED` | 卡体换成“运维监控未开启”组件（10 章 §7.2 的 `OpsDisabledNotice`，按 `disabled_reason` 写原因、是否可在手机上开启；本章所有“运维监控未开启”都用它，不另做） | — |

注意：首页 6 格的 RPM / TPM 取 `dashboard/rates`（近 5 分钟平均），本图每点是一个桶，两者不必相等。

**更多图表卡**

| 界面元素 | 字段 / 计算 | 格式与文案 |
|---|---|---|
| 卡头 | 图表数 | “更多图表”；右侧“12 张”（运维关闭 6 张，vendor 4 张） |
| 4 个磁贴 | 运维开启：Token 使用趋势、用户用量趋势、错误趋势、请求时长分布；运维关闭：Token 使用趋势、用户用量趋势、端点分布、请求类型 | 每块：标题、大数 + 单位、说明、缩略图（定义见第 2 节各图“磁贴”）；运行类图表在当前模型筛选下只能显示全站时，说明前加“全站”标签 |
| 卡底 | — | “全部图表 · 计费 2 · 用量 4 · 运行 6 ›”（运维关闭写“运行 未开启”） |

#### 1.5 交互与写操作

- 本页没有写操作。
- 图表点选：整张图是一个点按 / 拖动区（`.chartXSelection`），按 x 坐标落到桶；再点同一桶取消；改范围、窗口、筛选时清除选中。不给每根柱子单独的点按区（30 天时柱宽只有约 10pt）。
- 排行行：模型 → `analyticsModel(model, source: requested)`；用户 → 用户详情（`user_id`）；分组 → 分组详情（`group_id`）。
- VoiceOver：图表提供 `AXChartDescriptor`（x = 桶标签，y = 值）；每根柱 / 点的 `accessibilityLabel` 如“10月16日 9:00 到 9:41，实际扣费 $229.00”。

#### 1.6 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 每张卡内 `ProgressView`，卡片保持高度 | — |
| 单卡失败 / 超时 | 卡内“加载失败”或“统计较慢，加载超时”+“重试本项”；有旧数据时保留，并在大数下写“更新失败 · 显示的是 09:40 的数据” | 重试本项 |
| 范围内无用量 | 柱图写“这个范围内没有用量”；合计 `$0.00`、请求 0 | — |
| 400 | 卡内“请求参数无效”，记日志 | 不重试 |
| 404 `OPS_DISABLED` | RPM / TPM 卡、运行类磁贴换成“运维监控未开启” | 见监控章节组件 |
| 403 | 不应出现（0.7 已隐藏）；出现时该卡写“当前身份无权查看” | — |
| 401 / 423 等 | 全局处理（通用约定） | — |

#### 1.7 刷新策略

- 进入页面：所有卡并发请求。
- 范围含“现在”时，前台每 60 秒刷新计费趋势、利润明细、排行（只刷当前段）与可见磁贴；过去的范围不自动刷新。刷新时“现在”前移，start 不变。
- RPM / TPM 卡：可见且前台时每 30 秒刷新；切窗口立即重载；离开页面或进入后台停止。
- 下拉刷新：全部卡立即重载。
- 后端 dashboard 查询有 30 秒进程内缓存，throughput-trend / overview 有 5 秒缓存，刷新间隔不短于它们。

#### 1.8 对现有代码的改动点

- `NativeApp/Features/AnalyticsView.swift` `AnalyticsView`：重写为卡片流 `AnalyticsView(route:)`。删除 `init(accountID:groupID:)`、“今日 / 近7天 / 本月”按钮、`AnalyticsFilterView`（数字 ID 输入框）；“统计汇总”“实际消费趋势”“模型统计”“分组统计”四个分区由计费趋势卡、利润卡、排行卡取代；删除“上游成本”“扣费与成本差额”“差额仅为…”文案。保留 `load(_:fixture:operation:)` 的独立加载写法与 `isCurrent` 守卫。
- 新建 `NativeApp/Features/Analytics/`：`AnalyticsSession.swift`（范围、筛选、各卡 `DashboardLoadState`，二级页共用；内含 `AnalyticsMemory`：按站点读写 0.1 列出的选择项，初始化顺序“记忆 → route 默认值”，失效规则同 0.1）、`AnalyticsCards.swift`（BillingTrendCard、ProfitCard、RankCard、PerfCard、MoreChartsCard）、`AnalyticsCharts.swift`（柱 + 点线 + 选中、支持负值零线的柱图；堆叠柱；折线面积图）、`AnalyticsSheets.swift`（自定义范围、筛选）。
- `Sources/Sub2Core/UsageAnalytics.swift`
  - `AnalyticsQuery`：新增 `modelSource`、显式 `granularity`（替换 `hourly` 的“≤ 3 天按小时”：只有单日范围按小时）；`timeZone` 改为必传站点时区（删默认值 `TimeZone.current`）；`start_time` / `end_time` 输出 UTC `Z`；`model_source` 只在有 `model` 时传。`accountID`、`userID` 统计页不再使用。
  - `AnalyticsSummary`：新增 `standardCost`（`total_cost`）、`cacheCreationTokens`、`cacheReadTokens`、`endpoints`、`upstreamEndpoints`；`difference` 改名 `profit`，改注释。
  - `AnalyticsBreakdown`：新增 `standardCost`（`cost`）；`usageAnalysisModels(_:)` 增加 `source` 参数（现在写死 requested）。
  - 新增 `UserSpendingRanking` 解码与 `usageAnalysisUsersRanking(_:sortBy:limit:)`。
- `Sources/Sub2Core/Models.swift` `TrendPoint`：新增 `inputTokens`、`outputTokens`、`cacheCreationTokens`、`cacheReadTokens`（缺省 0）与 `accountCost: Decimal?`（键缺失为 nil，表示旧服务端，不能当 0）；注释写明 `cost` 是标准。
- 新建 `Sources/Sub2Core/AnalyticsRange.swift`（纯逻辑）：选项 → start / end / 粒度 / 范围名 / 说明行 / 对比窗口 / 对比文案 / 完整桶列表（补零用）。新建 `Sources/Sub2Core/ProfitRows.swift`：最大余额法分到分。
- `Sources/Sub2Core/DashboardTrend.swift` `DashboardTrendMetric.actualCost.label`：“实际消费”改“实际扣费”（概览也在用）。
- 测试：`Tests/Sub2CoreTests/UsageAnalyticsTests.swift` 补新解码与 `model_source`；新增 `AnalyticsRangeTests`（跨月、2 月、夏令时、单日按小时、上月同期取月末）、`ProfitRowsTests`；`UITests/AnalyticsUITests.swift` 按新标识重写，并覆盖记忆（第一次从搜索进是近 7 天；改成 30 天后从概览进仍是 30 天；换站点回到入口默认值）；AppModel 的 UI 测试桩补齐新接口。

---

### 2. 更多图表（`analyticsMore`）

#### 2.1 入口与导航

- 进入：统计分析的更多图表磁贴（`chart` = 该图，进入后滚到它并高亮卡片边框一次）、“全部图表”（停在顶部）、`topic` 参数（滚到该主题）。
- 导航栏：标题“更多图表”；副标题“<站点名> · <范围名>”；右侧筛选按钮（同 1.2）。
- 吸顶条（`safeAreaInset(edge: .top)`）：左侧主题胶囊“计费 2”“用量 4”“运行 6”（运维关闭为“运行 —”；当前所在主题高亮，随滚动更新，滚到底高亮最后一个），点胶囊滚到该主题；右侧范围 `Menu`（今天 / 近 7 天 / 近 30 天 / 自定义…，自定义打开 1.2 的 sheet）。吸顶条下是范围说明行和筛选胶囊。
- 主题与图表（按顺序）：
  - 计费：计费明细、利润明细
  - 用量：Token 使用趋势、用户用量趋势、端点分布、请求类型
  - 运行（主题头右侧小字“需开启运维监控”）：RPM / TPM 趋势、平均账号切换、请求时长分布、错误趋势、错误分布、Token 请求统计
- 运维监控关闭时，“运行”主题整体换成一张“运维监控未开启”卡。vendor 没有“运行”主题、用户用量趋势、请求类型。
- 每张图卡头：标题 + 窗口（范围名；RPM / TPM 写“截至现在”；Token 请求统计写它的统计窗口）+ 运行类加“ · 运维监控”；模型筛选不支持时卡头下一行提示（同 1.2）。
- 去向：用户用量趋势的行 → 用户详情；Token 请求统计无下钻。

#### 2.2 数据来源（逐图）

范围、筛选、`timezone` 参数规则见 0.2 与 1.2，下表只写各图特有的部分。运行类图表的桶长由后端按范围长度定：≤ 2 小时 60 秒、≤ 24 小时 300 秒、更长 3600 秒。

| 图 | 请求 | 特有参数 | 能力 / 降级 |
|---|---|---|---|
| 计费明细 | 复用 1.3 的 trend 与 usage/stats | — | — |
| 利润明细 | 复用 1.3 的 trend 与 usage/stats | — | 同 1.3 |
| Token 使用趋势 | 复用 trend | — | — |
| 用户用量趋势 | `GET /admin/dashboard/users-trend` | `granularity`、`limit=12`、`metric=tokens \| actual_cost` | 带筛选且没有 `dashboard.users_trend_filtered_metric`：隐藏“实际扣费”分段，只给 Tokens |
| 端点分布 | 复用计费合计那次 usage/stats 的 `endpoints` / `upstream_endpoints` | — | — |
| 请求类型 | `GET /admin/dashboard/request-types` | 不能带 `request_type` / `stream`（带了 400） | 没有 `dashboard.request_types`：5 次 `usage/stats?request_type=stream \| sync \| ws_v2 \| cyber \| live`（并发 4）取 `total_requests` |
| RPM / TPM 趋势 | 同 1.4 | 自有窗口，不跟页面范围 | — |
| 平均账号切换 | `GET /admin/ops/dashboard/throughput-trend` | 页面范围（end 不取整） | — |
| 请求时长分布 | `GET /admin/ops/dashboard/latency-histogram` + `GET /admin/ops/dashboard/overview` | 页面范围 | — |
| 错误趋势 | `GET /admin/ops/dashboard/error-trend` + overview（与请求时长分布共用一次） | 页面范围 | — |
| 错误分布 | `GET /admin/ops/dashboard/error-distribution` | 页面范围 | — |
| Token 请求统计 | `GET /admin/ops/dashboard/openai-token-stats` | `start_time` / `end_time`（页面范围）、`top_n=100`、`group_id`；不传 model | 跨度超过 31 天 + 1 小时：400 `OPS_TIME_RANGE_TOO_LARGE`（`metadata.max_days=31`）→ 改用 `time_range=30d`；没有 `ops.token_stats_custom_range`：`time_range` 取能盖住“范围首日 00:00 到现在”的最小值（`1d` / `15d` / `30d`），盖不住用 `30d` |

响应字段：

- users-trend：`trend[]{date, user_id, email, username, requests, tokens, cost, actual_cost}`。
- request-types：`request_types[]{request_type, requests, total_tokens, cost, actual_cost, account_cost}`，只含有用量的类型，同数按类型编号升序，没有数据为 `[]`。
- throughput-trend：见 1.4；`switch_count` = 该桶 upstream_errors 里 failover 类事件数。
- latency-histogram：`total_requests`、`buckets[]{range, count}`（只算成功请求；`range` 固定为 `0-100ms`、`100-200ms`、`200-500ms`、`500-1000ms`、`1000-2000ms`、`2000ms+`）。
- overview：`success_count`、`error_count_total`、`business_limited_count`、`error_count_sla`、`request_count_total`、`request_count_sla`、`sla`、`error_rate`、`duration{p50_ms, p90_ms, p95_ms, p99_ms, avg_ms, max_ms}`、`ttft{同上}`。
- error-trend：`bucket`、`points[]{bucket_start, error_count_total, business_limited_count, error_count_sla, upstream_error_count_excl_429_529, upstream_429_count, upstream_529_count}`。
- error-distribution：`total`、`items[]{status_code, total, sla, business_limited}`（只算客户端最终 ≥ 400 的行；`status_code` 取上游状态码，没有时取客户端状态码；按 total 降序，最多 20 行）。
- openai-token-stats：`time_range`（自定义时为 `custom`）、`start_time`、`end_time`（UTC 回显）、`items[]{model, request_count, avg_tokens_per_sec, avg_first_token_ms, total_output_tokens, avg_duration_ms, requests_with_first_token}`、`total`。行按 `usage_logs.model` 分组，有模型映射时行名可能是上游模型名。

#### 2.3 字段 → 显示（逐图）

卡片尺寸（列表里）和全屏尺寸（第 3 节单图页）共用同一个 body，区别写在“全屏”列。

**计费明细**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 头行 | 合计 / 选中桶 | `实际 $1,284.50`；选中 `10月16日 8:00–9:00 · $229.00`；右侧图例“实际 · 标准（点线）” | — |
| 图 | 同计费趋势卡 | 高 112pt | 全屏 170pt |
| 三数 | 账号成本、标准、利润（同 1.4） | 金额 | — |
| 表（最新在上） | 时段 / 实际 / 标准 / 请求 | 卡片 6 行 +“展开全部 N 小时 ⌄” | 全屏显示全部 |
| 磁贴 | `total_actual_cost` | `$1,284.50` / “实际扣费” | — |

**利润明细**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 头行 | 合计利润 / 选中桶 | `利润 $772.42`；选中 `10月16日 8:00–9:00 · 利润 $90.12`；右侧“实际扣费 − 账号成本” | — |
| 图 | 同利润卡（可为负） | 高 112pt | 全屏 170pt；“这个范围内没有扣费” |
| 三数 | 实际扣费、账号成本、利润（合计） | 金额 | — |
| 表 | 时段 / 实际 / 账号成本 / 利润（最大余额法） | 卡片 6 行 + 展开 | 全屏全部 + 末行“合计”+ 说明“每小时的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。”（按天写“每天”） |
| 磁贴 | 合计利润 | `$772.42` / “利润” | — |

**Token 使用趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 图例按钮 ×4 | 输入 `input_tokens`、输出 `output_tokens`、缓存读 `cache_read_tokens`、缓存写 `cache_creation_tokens`；数值为合计或选中桶的值 | 色块 + 名称 + compact 数；点一个只看这一项（其余变淡），再点恢复 | — |
| 图 | 每桶四段堆叠；只看一项时为单色柱 | 三种灰 + 描边，缓存读用横纹（Swift Charts 用 `ImagePaint`；做不到改“描边 + 透明度”），相邻段之间留 1.5pt 表面色缝 | 全为 0：“这个范围内没有用量” |
| 底注 | 合计、缓存读占比 = Σcache_read ÷ Σtotal_tokens | 未选中“合计 96.4M · 缓存读占 54% · 点图例只看一项”；选中“10月16日 9时 · 合计 9.8M”；只看一项“只看缓存读，再点一次图例恢复全部” | — |
| 表 | 时段 / 输入 / 输出 / 缓存读 / 缓存写 | — | 只在全屏显示 |
| 磁贴 | 合计 | `96.4M` Tokens / “缓存读占 54%” | — |

**用户用量趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 分段 | — | Tokens · 实际扣费（默认 Tokens） | 降级时只有 Tokens |
| 行 | 按 `user_id` 归并各桶；按 Σ所选指标降序 | 序号、名称（`username`，空时 `email`）、迷你折线（该用户每桶值，缺桶补 0，各用各的纵轴）、合计（Tokens compact / 金额） | 卡片前 5 行，全屏 12 行；无数据“这个范围内没有用户用量” |
| 底注 | — | “按 Tokens 取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。”（全屏去掉“这里显示前 5 位”） | — |
| 点行 | — | 进用户详情 | — |
| 磁贴 | 第 1 名 | `12.4M` Tokens / “第 1 · Nova 工作室”；无数据 `—` / “没有用户用量” | — |

**端点分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 分段 | — | 入站端点 · 上游端点 | — |
| 行 | `endpoints[]` / `upstream_endpoints[]`；占比 = `requests` ÷ Σ`requests` | 路径（等宽）、请求数、占比条 + %、副行“实际 $x”（`actual_cost`） | 数组缺省或空：“这个范围内没有用量” |
| 磁贴 | 入站第一行 | `60%` / “/v1/messages 占请求” | `—` / “没有用量” |

**请求类型**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 构成条 | 5 类请求数占比 | 0 的类型不画 | — |
| 行 ×5（固定顺序） | 流式 `stream`、同步 `sync`、WS `ws_v2`、安全策略 `cyber`、Live `live`；响应里没有的补 0 | 色块（0 为空心）、名称、请求数、占比 | 合计为 0：“这个范围内没有用量” |
| 磁贴 | 流式占比 | `72%` / “流式占请求” | `—` |

**RPM / TPM 趋势**：同 1.4。在列表与全屏都不跟页面范围；全屏页不显示范围条，只保留筛选胶囊。磁贴：近 1 小时最新一点的 RPM / “最新一桶 · 09:40”，缩略图为近 1 小时 RPM 折线。

**平均账号切换**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 三数 | 切换次数 = Σ`switch_count`；平均 · 次/请求 = Σ`switch_count` ÷ Σ`request_count`；最高 · 次/请求 = 有请求的点里 `switch_count ÷ request_count` 的最大值 | 千分位；3 位小数 | 请求为 0：`—` |
| 折线 | 每点 `switch_count ÷ request_count`（`request_count` = 0 的点不画） | 高 96pt；单日每 3 小时（今天，末尾标“现在”）或 6 小时（过去的单天）标“N时”；多日按天标日期，约 4 个刻度 | 全屏 150pt |
| 底注 | 桶长 | “曲线每 5 分钟一点。请求因限流、过载或错误换到另一个账号，记一次切换。”（> 24 小时写“每小时一点”） | — |
| 磁贴 | 平均 | `0.012` / “平均 · 次/请求” | — |

**请求时长分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 直方图 6 列 | `buckets[]`：`0-100ms`→`<100ms`、`100-200ms`→`100–200`、`200-500ms`→`200–500`、`500-1000ms`→`0.5–1s`、`1000-2000ms`→`1–2s`、`2000ms+`→`≥2s`；柱高 = count ÷ 最大 count；柱上 % = count ÷ `total_requests`（0 位小数） | — | `total_requests` = 0：“这个范围内没有成功请求” |
| 底注 | `total_requests` | “成功请求 18,204 次的总耗时分布” | 无请求时不显示 |
| 分位表 | 行“总耗时”= overview `duration`，“首字”= overview `ttft` | 卡片列 P50 · P90 · P95 · P99；全屏另加“平均”“最长” | 无请求或字段 null：`—` |
| 磁贴 | `duration.p50_ms` | `2.4s` / “P50 总耗时” | `—` |

**错误趋势**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 三数 | 错误 = Σ`error_count_total`；错误率 · SLA = overview `error_rate`；SLA 口径 = Σ`error_count_sla` | 千分位；百分比 | — |
| 堆叠柱 | 每段两层：SLA 错误 = `error_count_sla`（红）、业务限制 = `business_limited_count`（灰），两层之和 = `error_count_total`。300 秒桶（范围 ≤ 24 小时）按小时合计；3600 秒桶按天（TZ）合计；60 秒桶（范围 ≤ 2 小时）按 5 分钟合计 | 高 100pt | 全屏 150pt；合计为 0：“这个范围内没有错误” |
| 图例 | Σ各层 | “SLA 错误 317 · 业务限制 80” | — |
| 上游分项行 | Σ`upstream_429_count`、Σ`upstream_529_count`、Σ`upstream_error_count_excl_429_529` | “上游失败（含重试成功）：429 186 · 529 64 · 其他 53” | — |
| 底注 | — | “后端每 5 分钟一桶，这里按小时合计。错误率 = SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制（用户自己的余额、额度、频率限制）。” | — |
| 磁贴 | overview `error_rate` | `1.7%` / “错误率 · SLA” | — |

后端无此能力 → App 退路：设计稿把“上游 429 / 上游 529 / 其他上游 / 非上游 / 业务限制”叠成 `error_count_total`。但 error-trend 的三个上游计数没有 status ≥ 400 条件，包含已重试成功的上游失败行，不是 `error_count_total` 的子集，叠起来会出现负的“非上游”。所以柱子只叠 SLA 错误 + 业务限制，上游分项单列一行文字。“今天”范围的错误率是今日 SLA 口径，首页 6 格错误率是近 5 分钟，两处不同属正常。

**错误分布**

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 行（按 total 降序） | `status_code`、`sla`、`business_limited`、`total`；占比 = `total` ÷ 响应 `total` | 状态码徽章（codeTone）；条：SLA 部分用状态色、业务限制部分灰，长度相对第一行 total；条数；占比（0 位小数） | 响应 total 为 0：“这个范围内没有错误” |
| 图例 | — | “429 限流 · 其他错误（含 504、529）· 业务限制（不计 SLA）” | — |
| 磁贴 | 第一行 | `47%` / “429 占错误”（码随第一行） | `—` |

**Token 请求统计**

| 界面元素 | 字段 / 计算 | 格式与文案 | 全屏 / 空值 |
|---|---|---|---|
| 分段 | — | 按请求 · 按速度 · 按首 Token（本地排序：`request_count` 降序 / `avg_tokens_per_sec` 降序 / `avg_first_token_ms` 升序，null 排最后） | — |
| 表 | 模型 / 输出/秒 `avg_tokens_per_sec` / 首 Token `avg_first_token_ms` / 平均时长 `avg_duration_ms` | 模型等宽；数值 1 位小数；耗时按分位格式 | 卡片 5 行，全屏 9 行；null `—`；分组筛选下没有行：“这个分组在窗口内没有模型用量” |
| 模型筛选 | 筛选的模型 | 该行高亮；不在前列时追加到末尾 | — |
| 底注 | 窗口 | 自定义范围生效：“统计窗口与所选范围一致。”；退路：“统计窗口近 15 天，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。”；盖不住：“统计窗口近 30 天，截至现在：后端最长只到 30 天，盖不住所选范围，这里只是最近 30 天的速度。”；分组筛选时加“只列「标准组」用到的模型。” | — |
| 磁贴 | `avg_tokens_per_sec` 最高的一行 | `86` 输出/秒 / “最快 · gpt-4.1-mini” | `—` |

#### 2.4 交互与写操作

- 无写操作。
- 主题胶囊：点按滚到该主题（`ScrollViewReader`）；滚动时按吸顶条下沿所在的主题更新高亮。
- 图表点选同 1.5；Token 图例、各分段只影响本图。

#### 2.5 状态

- 每张图独立：加载中卡内 `ProgressView`；失败“加载失败 · 重试本项”；空态见各图。
- 运维监控关闭：“运行”主题一张“运维监控未开启”卡；主题胶囊“运行 —”仍可点（滚到这张卡）。
- 404 `OPS_DISABLED`（开关刚被关）：运行类各图都换成未开启卡，并刷新 `/admin/me`。
- Token 请求统计 400 `OPS_TIME_RANGE_TOO_LARGE`：自动改用 `time_range=30d` 重试一次，底注写“盖不住”那句。
- 运维错误日志按服务器设置保留（默认 30 天，配置 `ops.cleanup.error_log_retention_days`）。范围起点早于 30 天前时，错误趋势、错误分布、平均账号切换卡头下加一行“运维日志默认只保留 30 天，更早的时段可能没有记录”。

#### 2.6 刷新策略

- 卡片在屏幕上出现时才请求（`LazyVStack` + `onAppear`），结果按（范围、筛选）缓存到会话结束；范围或筛选改变时，已加载过的卡重新请求，没出现过的仍等出现。
- 范围含“现在”：可见卡每 60 秒刷新；RPM / TPM 每 30 秒。
- 下拉刷新：所有已加载的卡重载。

#### 2.7 对现有代码的改动点

- 新建 `NativeApp/Features/Analytics/AnalyticsMoreView.swift`（主题列表、吸顶条、懒加载）与 `AnalyticsChartBodies.swift`（12 个 body，参数 `size: .card | .full`）。
- 新建 `Sources/Sub2Core/OpsAnalytics.swift`：`OpsQuery`（start / end / groupID / model / modelSource，输出 1.2 的参数映射）与 `OpsLatencyHistogram`、`OpsErrorTrend`、`OpsErrorDistribution`、`OpsTokenStats` 解码；`APIClient` 新增 `opsLatencyHistogram(_:)`、`opsErrorTrend(_:)`、`opsErrorDistribution(_:)`、`opsTokenStats(_:)`，参数都是 `OpsQuery`。
- **ops overview 不在本章定义**：方法与模型归 10 章（`OpsOverview`，`Sources/Sub2Core/OpsMonitoring.swift`；10 章 §1.7 已删除 `dashboardMonitoring()` / `OpsReply` / `OpsSnapshot`，去留以 10 章为准）。本章调用 10 章“起止时间 + 筛选”的那个重载，签名以 10 章为准；本章依赖它：① 接受 `start_time` / `end_time` 之外的 `group_id`、`model`、`model_source`（与 `OpsQuery` 同一套映射）；② `OpsOverview` 解码 `success_count`、`error_count_total`、`business_limited_count`、`error_count_sla`、`request_count_total`、`request_count_sla`、`sla`、`error_rate`、`duration` 与 `ttft`（各含 `p50_ms`、`p90_ms`、`p95_ms`、`p99_ms`、`avg_ms`、`max_ms`）。本章不另建 `OpsOverviewWindow` 之类的模型。
- `Sources/Sub2Core/UsageAnalytics.swift`：新增 `UserTrendPoint`、`RequestTypeStat` 解码与 `usageAnalysisUsersTrend(_:metric:limit:)`、`usageAnalysisRequestTypes(_:)`。
- `Sources/Sub2Core/PerformanceTrend.swift`
  - 新增 `windowStart` / `windowEnd`（请求时的窗口，由 `APIClient` 解码后写入）、`Point.switchCount`（`switch_count`，缺省 0）。
  - `rate(_:metric:)` 改为除以覆盖秒数；新增 `coveredSeconds(_:)`、`peak(_:)`、`average(_:)`；`Bucket` 增加未知值兜底（按窗口长度推算）。
- `Sources/Sub2Core/APIClient.swift` `dashboardPerformanceTrend(start:end:)`：改为 `dashboardPerformanceTrend(_ query: OpsQuery)`（去掉 `mode=auto`；带上分组 / 模型筛选）；保留 30 天上限。
- `NativeApp/Session/AppModel.swift` `dashboardPerformanceTrend(hours:)`：`end` 向下取整到整分钟；增加筛选参数；UI 测试桩按覆盖秒数造首尾残桶。
- `NativeApp/Features/PerformanceTrendView.swift` `PerformanceTrendView`：抽成 `PerfTrendBody(filter:size:startMetric:)`，补“最新一桶”大数、峰值 / 平均副行、说明文案、明细里的“只覆盖 N 秒”；错误分支按 `OPS_DISABLED` 显示未开启组件（不再是红字“站点需启用运行监控…”）；`rateLabel` 改用 0.5 的 RPM 格式（现在一律 compact）。概览若保留第 4 个趋势页，也用这个组件（概览章节定）。
- `docs/API_COMPATIBILITY.md:54`“边界桶仍按完整桶宽计算”改为覆盖秒数口径。
- 测试：`Tests/Sub2CoreTests/PerformanceTrendTests.swift` 改为覆盖秒数（1 分钟、5 分钟残桶，首尾都不满）；新增 `OpsAnalyticsTests`（error-trend 按小时 / 按天合计、两层之和等于 total）。

---

### 3. 单图页（`analyticsChart`）

#### 3.1 入口与导航

- 进入：计费趋势卡底“计费明细 ›”（`billing`）、利润明细卡底“利润明细 ›”（`profit`）。其余图在更多图表列表里看，不提供单图入口（目录网格、单图翻页是未选变体）。
- 导航栏：标题为图名；副标题“<主题> · <窗口>”（如“计费 · 今天”）；右侧筛选按钮。
- 页面：范围条（同 1.2）+ 一张全屏 body（第 2.3 节“全屏”列）。

#### 3.2 数据来源

同第 2.2 节对应的图，与 `AnalyticsSession` 共用缓存：从统计分析进来时直接显示已加载的数据，不重复请求。

#### 3.3 字段 → 显示

见 2.3 计费明细、利润明细的“全屏”列：图高 170pt，表格显示全部桶（最新在上），利润明细末行“合计”并带说明。选中某根柱时表格对应行高亮。

#### 3.4 交互与写操作

无写操作；范围、筛选改动写回 `AnalyticsSession` 并按 0.1 写入本机记忆，返回统计分析后保持。

#### 3.5 状态

同 1.6。

#### 3.6 刷新策略

同 1.7；下拉刷新只重载本图用到的请求。

#### 3.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsChartView.swift`，复用 `AnalyticsChartBodies` 的 `.full` 尺寸。现有 `AnalyticsView` 里“逐小时 / 逐日明细”的 `NavigationLink`（标题“消费明细”）由它取代。

---

### 4. 全部排行（`analyticsRank`）

#### 4.1 入口与导航

- 进入：排行卡底（`dim` = 当前段）。
- 导航栏：标题 模型分布 / 用户排行 / 分组使用分布；副标题“<站点名> · <范围名>”；右侧筛选按钮。
- 页面：范围条 → 构成条 → 列表。
- 去向：模型行 → `analyticsModel(model, source: 当前口径)`；用户行 → 用户详情；分组行 → 分组详情。

#### 4.2 数据来源

| 维度 | 请求 | 参数 | 能力 / 降级 |
|---|---|---|---|
| 模型 | `GET /admin/dashboard/models` | 范围、分组筛选、`model_source=requested \| upstream \| mapping`（随口径菜单） | — |
| 用户 | `GET /admin/dashboard/users-ranking` | 范围、筛选、`limit=50`、`sort_by=actual_cost \| requests \| tokens`（随排序菜单，服务端排序） | 没有 `dashboard.users_ranking_sort`：不传 `sort_by`（后端按实际扣费取前 50），App 在这 50 人里本地重排；没有 `total_users`；vendor 无此页 |
| 分组 | `GET /admin/dashboard/groups` | 范围、模型筛选 | — |

模型、分组的接口返回全部行，排序在本地做；用户的排序变化要重新请求。

#### 4.3 字段 → 显示

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 构成条（行数 > 1） | 前 3 名占比 + 其余；按当前指标 | 条上方“前 3 占 62.4%”“合计 $1,284.50”（合计按当前指标格式）；条下图例前 3 个名称 +“其余 9 个模型”/“其余用户 12.3%” | — |
| 列表头 | 行数 | 模型 / 分组：“12 个模型”“9 个分组”，模型非请求口径时加“ · 上游模型 / · 映射”；用户：“前 50 位 · 共 143 位”（`total_users`；降级时只写“前 50 位”） | — |
| 排序菜单（列表头右侧 `Menu`） | — | “按实际扣费 ⌄”；分节“排序”：按实际扣费 / 按请求 / 按 Tokens；模型维度另有分节“模型口径”：请求模型 / 上游模型 / 映射（请求 → 上游） | — |
| 行 · 序号 / 名称 | 同 1.4 排行卡 | 映射口径的 `model` 形如 `a -> b`：名称写 `a`，副行开头写“→ b” | — |
| 行 · 值 | 当前指标：`actual_cost` / `requests` / `tokens`（用户）或 `total_tokens`（模型、分组） | 金额 / 千分位 / compact | — |
| 行 · 占比条 + % | 值 ÷ 合计；用户的合计取 `total_actual_cost` / `total_requests` / `total_tokens` | 1 位小数 | — |
| 行 · 副行 | 用户：`email`（有 username 时）；其余两个指标；“账号成本 $x”（`account_cost`） | 用 ` · ` 连接，如“请求 3,100 · 15M Tokens · 账号成本 $88.20” | — |
| 用户底注 | — | “按<指标>取前 50 位，共 143 位用户有用量。”；降级“用户排行按实际扣费取前 50 位，这里在其中按<指标>重排。”；分组筛选时再加 1.4 那句 Key 分组说明 | — |
| 当前维度是筛选维度 | — | 整页只显示“已筛选分组：高级组　清除筛选” | — |
| 空 | — | “这个范围内没有模型用量” | — |

#### 4.4 交互与写操作

- 无写操作。排序指标（每个维度各记一份）与模型口径按 0.1 在本机记住，返回再进、下次进入都保持。
- 切口径：重新请求 `dashboard/models`；切排序：模型 / 分组本地重排，用户重新请求。

#### 4.5 状态

加载中整页 `ProgressView`；失败“加载失败 · 重试”；400 `INVALID_SORT_BY`（不应出现）按降级重请求一次（不带 `sort_by`）。

#### 4.6 刷新策略

同 1.7（范围含现在时 60 秒）；下拉刷新重载。

#### 4.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsRankView.swift`；依赖 1.8 的 `usageAnalysisModels(_:source:)`、`usageAnalysisUsersRanking(_:sortBy:limit:)`。

---

### 5. 模型页（`analyticsModel`）

#### 5.1 入口与导航

- 进入：排行卡与全部排行的模型行。
- 导航栏：标题 = 模型名（映射口径写“a → b”）；副标题“模型 · <范围名>”。后端 `ModelStat` 没有平台字段 → 不显示设计稿里的平台名。页面没有筛选按钮，但会话里的分组筛选在本页生效。
- 页面：范围条 → 头部大数 → 壹 趋势 → 贰 用量 → 叁 速度 → 肆 用得最多的用户。
- 去向：用户行 → 用户详情；“这个模型的使用记录” → `logs(scope: usage, model, modelSource: source, group: 会话分组筛选)`。

#### 5.2 数据来源

所有请求带 `model=<名称>&model_source=<source>` + 范围 + 会话分组筛选（有的话）。

| 区块 | 请求 | 补充 |
|---|---|---|
| 合计 | `GET /admin/usage/stats` | 占比分母 = 同范围、同分组筛选但不带 model 的 usage/stats（复用统计分析已加载的合计） |
| 对比 | `GET /admin/usage/stats`（对比窗口） | — |
| 趋势 | `GET /admin/dashboard/trend` | — |
| 速度 | `GET /admin/ops/dashboard/openai-token-stats?top_n=10` + 范围（规则同 2.2） | 需要 `ops.dashboard_model_filter`：requested / upstream 口径直接传；mapping 口径传 `model=<b>&model_source=upstream`。没有该能力：不传 model，在返回行里找 `model` 等于名称的那一行，找不到显示 `—`。运维关闭不显示本区块 |
| 用户 | `GET /admin/dashboard/users-ranking?limit=3&sort_by=actual_cost` | vendor 不显示本区块 |

速度区返回多行时（映射后的不同上游名）合并：输出/秒、平均时长按 `request_count` 加权平均，首 Token 按 `requests_with_first_token` 加权平均。

#### 5.3 字段 → 显示

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 头部标签 | 本模型 `total_actual_cost` ÷ 分母 `total_actual_cost` | “实际扣费 · 占全部 12.3%”（分组筛选时“占高级组 …”） | 分母为 0：`—` |
| 头部大数 / 增减 | `total_actual_cost`；对比 | 同 1.4 | — |
| 上游模型行 | mapping 口径的 b | “上游模型 claude-opus-4-20250514”（等宽） | 非映射口径不显示 |
| 壹 趋势 | trend 每桶 `actual_cost` + `cost` 点线 | 分区 meta“实际 / 标准（点线）”；图高 100pt；下面三格 账号成本 / 标准 / 利润（本模型 usage/stats） | “这个范围内没有用量” |
| 贰 用量 | `total_requests`；`total_tokens`；缓存读占比 = `total_cache_read_tokens ÷ total_tokens`；平均每次 = `total_actual_cost ÷ total_requests` | 分区 meta 为范围名；占比 0 位小数；平均每次 3 位小数金额 | 请求为 0：`—` |
| 叁 速度 | `avg_tokens_per_sec`、`avg_first_token_ms`、`avg_duration_ms`（加权后） | 分区 meta“<窗口>”；“输出 Tokens/秒”“平均首 Token”“平均时长”；底注同 2.3 Token 请求统计的窗口说明 | null `—` |
| 肆 用户行 ×3 | `ranking[]` | 同 4.3 行样式（值为实际扣费） | “这个范围内没有用户用量” |
| 使用记录行 | — | 标题“这个模型的使用记录”，副行“近 24 小时 · 带上模型筛选，可以去掉”（有分组筛选写“带上模型和分组筛选”） | — |

#### 5.4 交互与写操作

无写操作。改范围写回会话（同时写入本机记忆，0.1）。

#### 5.5 状态

各区块独立加载、独立失败（同 1.6）；速度区运维关闭时整区隐藏（不占位）。

#### 5.6 刷新策略

同 1.7；下拉刷新重载本页全部请求。

#### 5.7 对现有代码的改动点

新建 `NativeApp/Features/Analytics/AnalyticsModelView.swift`；复用 1.8 的 Query 与 2.7 的 `opsTokenStats`。

---

### 6. 使用记录（`logs`）

#### 6.1 入口与导航

- 进入：
  - 搜索目录“记录 · 使用记录” → `logs(scope: usage)`；“错误请求” → `logs(scope: errors)`。
  - 账号详情“记录”：上游错误 → `logs(scope: upstream, account)`，使用记录 → `logs(scope: usage, account)`。
  - 分组详情：错误请求 / 上游错误 / 使用记录 → 对应 scope + `group`。
  - 用户详情 → `logs(scope: usage, user)`。
  - 模型页 → `logs(scope: usage, model, modelSource, group?)`。
  - 告警详情（错误率类告警）→ `logs(scope: errors, group)`。
- 导航栏：标题“使用记录”；副标题“<站点名> · 近 24 小时”（随时间菜单变）；右侧筛选按钮（打开“按对象筛选” sheet）。
- 页面：分段 → 筛选胶囊行 → （不支持的条件说明）→ 列表。
- 去向：点行 → `request` 详情（带整行数据与 scope）。
- 离开页面清空本页的筛选改动；下次按 route 重新带入。

#### 6.2 数据来源

时间：滚动预设的窗口在每次全量加载时取 `end_time = 现在`、`start_time = 现在 − 窗口`；自定义为固定起止。

| 用途 | 请求 | 参数 |
|---|---|---|
| 用量明细列表 | `GET /admin/usage` | `page`、`page_size=100`（与 00 §4.3 首屏一致，翻页同一页长）、`count_mode=deferred`、`sort_by=created_at`、`sort_order=desc`、`start_time`、`end_time`、`timezone`、`key_view=masked`、`account_id`、`group_id`、`user_id`、`model`、`model_source`（有 model 时） |
| 错误请求列表 | `GET /admin/ops/request-errors` | `page`、`page_size=100`、`view=all`（默认视图只排除业务限制，即用户自己的余额、额度、频率限制；传 all 才包含它们。上游 429 / 529 在默认视图里本来就有）、`start_time`、`end_time`、`account_id`、`group_id`、`user_id`、`model` |
| 上游错误列表 | `GET /admin/ops/upstream-errors` | 同上，`view=all` |
| 计数 · 用量明细 | `GET /admin/usage/stats` | 同一时间窗与筛选 → `total_requests` |
| 计数 · 错误请求 / 上游错误 | 当前段：列表响应的 `total`；其他段：同参数 `page=1&page_size=1` 取 `total` | — |
| 增量（用量明细、错误请求） | 同列表接口 | `since_id=<游标>`、`page_size=100` + 筛选；不传 `page`、时间、排序（算法见 00 §4.3，本页参数见 6.6） |
| 筛选 sheet · 账号 | `GET /admin/accounts?search=<q>&lite=true&sort_by=name&sort_order=asc&page=1&page_size=6` | 用账号章节（20 章）的 `managedAccounts(page:query:)` + `AccountListQuery`，见 6.7 |
| 筛选 sheet · 分组 | 分组目录缓存（`GET /admin/groups/all?include_inactive=true`），本地按名称过滤取前 4 | — |
| 筛选 sheet · 用户 | `GET /admin/usage/search-users?q=<q>` → `[{id, email, deleted}]`，取前 3 | vendor 不可用 |

响应：

- `admin/usage`：`items[]`（AdminUsageLog）、`total=null`、`page`、`page_size`、`has_more`、`total_exact=false`；since_id 时另有 `since_id`、`latest_id`，`has_more=true` 表示新行超过一页。行字段：`id`、`request_id`（形如 `client:<uuid>`）、`created_at`、`model`（请求模型）、`upstream_model`、`user{id,email,username}`、`api_key{id,name,key_masked}`、`group{id,name}`、`account{id,name}`、`input_tokens`、`output_tokens`、`cache_creation_tokens`、`cache_read_tokens`、`total_cost`、`actual_cost`、`account_cost`（D05，`provider_cost_recorded=false` 时为 0）、`provider_cost_recorded`、`request_type`（字符串）、`stream`、`duration_ms`、`first_token_ms`、`inbound_endpoint`、`upstream_request_id`。不读 `api_key.key`（明文）。
- `ops/request-errors`：`items[]`（OpsErrorLog）、`total`、`page`、`page_size`、`pages`、`has_more`、`total_exact=true`；since_id 时同上。`ops/upstream-errors`：`items`、`total`、`page`、`page_size`、`pages`（没有 `has_more`，按 `page < pages` 判断）。行字段：`id`、`created_at`、`phase`、`type`、`error_owner`、`error_source`、`severity`、`status_code`、`platform`、`model`、`requested_model`、`upstream_model`、`resolved`、`resolved_at`、`resolved_by_user_name`、`client_request_id`、`request_id`、`message`、`user_id`、`user_email`、`api_key_id`、`api_key_name`、`account_id`、`account_name`、`group_id`、`group_name`、`stream`、`request_type`（数字）、`duration_ms`、`time_to_first_token_ms`（D04，旧行 null）。列表项没有 `upstream_status_code`（只有详情有）。
- 错误请求与上游错误的 `model` 筛选匹配 `COALESCE(requested_model, model)`，即请求模型；没有 `model_source`。
- 上游错误 = phase 为 upstream / account_auth、责任方 provider 的行，包括已重试成功的恢复行（`status_code` < 400，`message` 为 `Recovered upstream error <上游码>` 或 `Recovered account authentication failure`）。所以同一个请求可能同时出现在错误请求与上游错误里，重试成功的请求也会同时出现在用量明细里。

#### 6.3 字段 → 显示

**分段**：用量明细 N · 错误请求 N · 上游错误 N（`Picker(.segmented)`，数字为计数；拿不到写 `—`）。vendor 只有“用量明细”（隐藏分段控件）。

**筛选胶囊行**（横向滚动）：

| 元素 | 内容 | 动作 |
|---|---|---|
| 时间胶囊 | “近 24 小时 ⌄” | `Menu`：近 1 小时 / 近 24 小时 / 近 7 天 / 近 30 天 / 自定义…（开始、结束两个 DatePicker，最长 366 天） |
| 条件胶囊 | “账号：Claude-官方-01 ✕”“分组：标准组 ✕”“用户：xm.wang@example.com ✕”“模型：claude-opus-4 ✕”（模型等宽） | 点按移除该条件并重新加载 |
| 不生效的胶囊 | 置灰 | 见 6.4 |
| “+ 筛选” | — | 打开“按对象筛选” sheet |

**列表**：按日期（TZ）分节，节头“今天 / 昨天 / 10月14日”，节头右侧“金额 · 首字/耗时”。行布局：左列时间在上、状态码在下；中间模型在上、“用户 · 账号”在下；右列金额在上、“首字/耗时”在下；最右 chevron。

| 位置 | 用量明细 | 错误请求 | 上游错误 |
|---|---|---|---|
| 左上 时间 | `created_at` → `HH:mm`（TZ） | 同左 | 同左 |
| 左下 状态码徽章 | 固定 `200`（使用记录不带状态码） | `status_code` | `status_code` ≥ 400：`status_code`；< 400（已重试成功）：从 `message` 解析 `Recovered upstream error (\d{3})`，解析不到时 account_auth 写“鉴权”、其余写“恢复” |
| 徽章颜色 | ok | codeTone(徽章码) | codeTone(徽章码)（重试成功的 429 仍是琥珀） |
| 中上 模型 | `model`（等宽，单行截断） | `requested_model` 非空用它，否则 `model` | 同左 |
| 中下 用户 · 账号 | `user.email` · `account.name` | `user_email` · `account_name` | 同左 |
| 右上 金额 | `actual_cost`（< $1 显示 4 位） | `—` | `—` |
| 右下 首字/耗时 | `first_token_ms` / `duration_ms` → `1.2s/3.2s`；首字 null（非流式）→ `—/3.2s` | `time_to_first_token_ms` / `duration_ms`；null → `—` | 同左 |
| 状态胶囊 | 无 | codeTone(`status_code`)：429 caution，其余 critical | `status_code` < 400：无（客户端已拿到成功）；≥ 400 同左 |

- 状态胶囊用全局组件：同一列表里紧挨着的带色行连成一根连续状态轨（同色异色都连，交界处直接切色，只有整段最上端和最下端是圆头）；无色的行打断。
- 用户、账号缺失写 `—`；邮箱过长中间省略；vendor 下邮箱是后端打码后的原样。

#### 6.4 交互与写操作

- 分段切换：保留全部条件，加载该段第 1 页；计数不重取。
- 不生效的条件：置灰胶囊不参与请求，胶囊下一行写原因：
  - `modelSource` 不是 requested 时，错误请求 / 上游错误的模型胶囊置灰：“错误记录只能按请求模型筛选，这里显示全部模型”。
  - 旧服务端（`/admin/me` 404，没有 D03）时，上游错误的用户、模型胶囊置灰：“上游错误不能按模型、用户筛选，这里显示全部”。
- “按对象筛选” sheet：顶部搜索框（占位“账号名、邮箱或分组”），输入防抖 300ms；分三组：账号（行：状态图标、名称、`#id`、平台 · 分组）、分组（行：名称、平台）、用户（行：头像首字、邮箱；`deleted=true` 加“已删除”）。搜索框为空时账号、分组显示前几个，用户组不显示（`search-users` 空关键字返回 `[]`）。选中即设置该类条件（同类替换）并关闭 sheet。vendor 没有用户组。
- 点行进入请求详情；返回时保留滚动位置。
- 下拉刷新：第 1 页全量重载 + 计数重取。
- 滚到底：加载下一页（`page + 1`，`page_size=100`），按 `id` 去重（新行插到顶部会让旧行往后挪，只会重复、不会漏）。
- 本页没有写操作（标记已处理在请求详情里；详情里改了 `resolved` 后，返回时就地更新本页那一行）。

#### 6.5 状态

| 情况 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 列表位置 `ProgressView`“正在读取记录…” | — |
| 空（无条件） | 大号“—”+“近 24 小时内没有记录” | — |
| 空（有条件） | 大号“—”+“近 24 小时内，这些条件下没有记录”+“清除筛选”按钮 | 清除全部条件 |
| 加载失败 | 列表末尾“加载失败”+“重试”；已有记录保留并注明“保留上次成功加载的记录” | 重试 |
| 错误请求 / 上游错误段遇到运维监控关闭（`ops_monitoring_enabled=false` 或 404 `OPS_DISABLED`） | 段内容换成“运维监控未开启”组件，并说明“关闭期间不记录错误，开启后也不会补”；计数 `—` | 见监控章节组件 |
| 范围超过 30 天的错误类段 | 列表头下一行“运维错误日志默认只保留 30 天，更早的可能已清理” | — |
| 400 `INVALID_SINCE_ID` / `SINCE_ID_WITH_PAGE` | 不显示，放弃增量改为第 1 页重载（00 §4.3 第 6 步） | — |
| 400 其他（参数） | “请求参数无效” | 清除筛选 |
| 403（vendor 访问错误类接口） | 不应出现（已隐藏） | — |

#### 6.6 刷新策略

- 前台、页面可见、时间为滚动预设时，每 60 秒自动刷新一次；后台或离开页面暂停，回到前台立即刷一次。固定的自定义时间段不自动刷新。
- **用量明细、错误请求的增量**：首屏、游标回退、按 `id` 合并、`has_more`、400 回退、没有 `logs.since_id` 时的退路，**全部按 00 §4.3**，实现只用 00 §9.7 的 `IncrementalList`，本章不另写一套。增量请求只带当前的对象筛选（账号 / 分组 / 用户 / 模型 / `model_source`）+ `since_id` + `page_size=100`，不带 `page`、`start_time` / `end_time`、排序。本页只规定这几个参数：
  - **N = 500**（00 §4.3 第 3 步“只保留最新的 N 条”）。超出时，只在列表停在顶部附近（第一个可见行在前 20 行内）才从尾部裁到 500 行，并把“加载更多”的下一页设为 6（500 ÷ 100 + 1）；用户正往下翻时先不裁，回到顶部再裁。
  - **时间窗裁剪**：每次合并后丢掉 `created_at` 早于窗口起点（现在 − 所选窗口）的行。
  - **校准周期**：每 10 次增量（约 10 分钟）拉一次第 1 页（参数同首屏），按 00 §4.3 第 3 步合并进现有列表（不清掉已加载的更早页），再按第 2 步重算游标。下拉刷新按 00 §4.3 第 5 步。
  - **显示顺序**跟 00 §4.3 第 3 步（`id` 降序）。按日期分节时，每行按自己的 `created_at`（TZ）归到对应日期的节，节按日期降序；`id` 顺序与时间偶有几秒交错，不会因此拆出两个同名的节。
- **上游错误（后端没有 since_id）**：每次自动刷新按 00 §4.3 第 7 步的退路取（`page=1&page_size=100`，`start_time` = 已加载最新一行的 `created_at` − 120 秒，`end_time` = 现在；ops 接口不带 `count_mode`），按 `id` 合并；响应 `pages` > 1（两次刷新之间的新行超过一页）时改为第 1 页全量重载。N、时间窗裁剪同上。
- 计数只在进入、切换条件、下拉刷新时取，自动刷新不重取。

#### 6.7 对现有代码的改动点

本章是 `admin/usage`（列表、按请求 ID 查）、`ops/request-errors`、`ops/upstream-errors`（列表、计数、详情、标记已处理）、`ops/requests/:id/attempts`、`usage/search-users` 在 App 里的**唯一定义处**；10 / 20 / 50 章的“近 24 小时 N 条”计数、60 章的请求 ID 搜索都调这里的方法，不另建。

- `Sources/Sub2Core/RequestLogs.swift`
  - `RequestLogFilter`：
    - 时间条件：`start` / `end` 改为 `time: LogTimeWindow`——`.range(start, end)`（本页；最长 366 天）、`.rolling(String)`（只用于 ops 接口，取后端认的 `5m` / `30m` / `1h` / `6h` / `24h` / `7d` / `30d`；其他章的“近 24 小时”计数、60 章搜索的 `30d` 用它）、`.none`（只允许和 `requestID` 一起用于 `admin/usage`：不带时间 = 全部时间）。ops 接口不带时间时后端默认只查近 1 小时，所以 `queryItems(errors: true)` 遇到 `.none` 抛 `.validation`；`admin/usage` 不认 `time_range`，`queryItems(errors: false)` 遇到 `.rolling` 也抛 `.validation`。
    - 新增 `modelSource`、`pageSize`（默认 100；计数传 1，60 章搜索传 5，按请求 ID 查使用记录传 1）。`requestID` 已有，保留。
    - `queryItems(page:errors:errorKind:)`：`page_size` 取 `pageSize`（现在写死 30）；用量明细加 `key_view=masked`；`timezone` 由设备时区改为站点时区；删掉对上游错误“不支持用户、密钥、模型和请求 ID 筛选”的抛错（D03 已支持），是否置灰由调用方按 0.3 决定；`upstreamErrorFilter()` 只在旧服务端使用。新增 `incrementalQueryItems(sinceID:)`（只带筛选、`since_id`、`page_size=100`）。
    - `category`、`statusCode`、`resolved`、`requestType`、`apiKeyID` 不再出现在界面（已定设计没有这些条件），属性可留作内部用。
  - `RequestLogPage` 删除，改用 00 §9.4 扩展后的 `Page<T>`（可空 `total` / `pages`、`hasMore`、`sinceID`、`latestID`）；`RequestLogPage.init(from:)` 里“没有 `has_more` 时按 `page < pages`、再按 `total` 推算”的逻辑搬进 `Page<T>`（上游错误的响应没有 `has_more`）。`Page` 现在要求 `T: Codable`，而两个记录类型只是 `Decodable`：把 `Page` 的约束放宽为 `Decodable & Sendable`（`Page` 自身的 `Encodable` 只在 `T: Encodable` 时提供）。
  - `UsageRequestRecord`：`accountCost` 优先读 `account_cost`；没有该键时才按公式 `provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0`（现代码漏了 `provider_cost_recorded`，跟随请求会多算）；新增 `providerCostRecorded`、`userName`（`user.username`）、`apiKeyName`、`apiKeyMasked`（`api_key.name` / `key_masked`，永不解码 `key`）。
  - `RequestErrorRecord`：新增 `durationMs`、`errorOwner`、`errorSource`、`severity`、`clientRequestID`、`userEmail`、`apiKeyID`、`apiKeyName`、`stream`、`requestType`（Int16?）、`resolvedAt`、`resolvedByUserName`；`model` 取法不变（requested_model 优先）。
  - 增量合并与游标：用 00 §9.7 的 `Sources/Sub2Core/IncrementalList.swift`，本章不新建合并文件；6.6 的 N = 500、时间窗裁剪、10 次一校准放在 `LogsView` 的 store 里，作为调用 `IncrementalList` 的参数或调用后的裁剪。
  - `APIClient` 方法：列表沿用 `requestRecords(page:filter:)`、`errorRecords(page:filter:kind:)`（返回类型改为 `Page<…>`）；新增 `errorCount(filter:kind:)`（`pageSize = 1` 取 `total`）、`searchUsageUsers(_:)`。
- 账号筛选（筛选 sheet）：调 20 章的 `managedAccounts(page: 1, query:)`，`AccountListQuery` 设 `search = q`、`sort = .name`、升序、`pageSize = 6`（`pageSize` 由 20 章加，lite 是该查询的固定行为）；不用 `APIClient.accounts(page:search:status:platform:)`。
- `NativeApp/Features/RequestLogsView.swift`：拆成 `NativeApp/Features/Logs/LogsView.swift`（分段与计数、胶囊、列表、轮询）、`LogRow.swift`、`LogFilterPickerSheet.swift`；`LogMode` 文案改为 用量明细 / 错误请求 / 上游错误；导航标题“请求与错误日志”改“使用记录”；删除 `RequestLogFilterEditor` 的数字 ID 输入、分类 / 状态码 / 处理状态 / 请求类型选择器，时间范围改为胶囊菜单；`requestRow` / `errorRow` 换成 `LogRow`；`LogFixtures` 按新字段更新；`init(accountID:groupID:)` 改为 `init(route: LogsRoute)`。
- 调用方：`NativeApp/Sub2MobileApp.swift:51-53` 搜索目录条目改为“使用记录”“错误请求”“统计分析”；`NativeApp/Features/AccountsView.swift:484-486`、`NativeApp/Features/GroupsView.swift:195-196` 改传 `LogsRoute`（是否保留“账号统计分析”入口由账号章节定，统计页不再支持按账号筛选）。
- 测试：`Tests/Sub2CoreTests/RequestLogsTests.swift` 补 `account_cost` 与 `provider_cost_recorded`、D04 字段、since_id 信封（`Page<T>` 的 `sinceID` / `latestID`、上游错误无 `has_more` 时按 `pages` 推算）、`LogTimeWindow`（ops 拒绝 `.none`、usage 拒绝 `.rolling`、`.rolling` 只出 `time_range`）；游标与合并的测试在 00 §9.8 的 `IncrementalList` 里，本章不重复；`UITests/RequestLogsUITests.swift` 按新布局与标识重写，并覆盖自动刷新后新行出现在顶部、超过 N 行且停在顶部时裁尾（UI 测试启动参数把 N 调成 5）。
- 文档：`docs/ADMIN_MODULES.md` 里“独立日志筛选边界”按 D03 更新。

---

### 7. 请求详情（`request`）

#### 7.1 入口与导航

- 进入：使用记录的行（带整行与 scope）；账号详情状态卡“最近上游错误 ›”（`.error(id, kind: upstream)`）；搜索里输入请求 ID 命中的使用记录（`.usageRequestID`）或错误请求（`.error(id, kind: request)`）。
- 三种样子：
  - **成功**：来自用量明细。
  - **上游失败已恢复**：来自上游错误、`status_code` < 400。
  - **失败**：来自错误请求或上游错误、`status_code` ≥ 400。
- 导航栏：标题 请求详情 / 上游错误 / 失败请求；副标题“10/16 09:41:07 · 用量明细 / 错误请求 / 上游错误”；右侧 ··· 菜单：复制请求 ID、复制上游请求 ID（有时）。
- 分区按出现顺序编号（壹、贰、叁…）：头部状态卡 → （失败类）按钮行 → 耗时 → 上游尝试（有时）→ Token（成功）→ 关联 → 标识。
- 去向：用户 → 用户详情；分组 → 分组详情；账号 / “查看账号” → 账号详情。

#### 7.2 数据来源

| 用途 | 请求 | 说明 |
|---|---|---|
| 成功 · 行数据 | 进入时已带；只有请求 ID 时 `GET /admin/usage?request_id=<rid>&page=1&page_size=1&key_view=masked`（`requestRecords(page: 1, filter:)`，filter 为 `requestID = rid`、`time = .none`、`pageSize = 1`） | 精确匹配、不需要时间范围；为空时“记录不存在或已清理” |
| 失败类 · 详情 | `GET /admin/ops/request-errors/:id`（错误请求）或 `GET /admin/ops/upstream-errors/:id`（上游错误），同一张表 | 列表字段 + `upstream_status_code`、`upstream_error_message`、`upstream_errors`（JSON 数组字符串）、`auth_latency_ms`、`routing_latency_ms`、`upstream_latency_ms`、`response_latency_ms`、`is_business_limited`、`api_key_prefix`。不解码、不显示 `error_body`、`upstream_error_detail` 和事件里的 `upstream_response_body` |
| 上游尝试 | `GET /admin/ops/requests/<id>/attempts?around=<created_at，UTC Z>` | 有 `ops.request_attempts` 且运维开启。`<id>`：失败类用 `client_request_id`（服务端 UUID，唯一），为空时用 `request_id`；成功用使用记录的 `request_id`（`client:<uuid>` 形式，后端认）。`around` 把两张表收窄到前后 1 小时 |
| 标记已处理 | `PUT /admin/ops/request-errors/:id/resolve` 或 `/admin/ops/upstream-errors/:id/resolve`，body `{"resolved": true \| false}` | 响应 `{"ok": true}` |

attempts 响应：`request_id`、`client_request_id`、`client_status_code`、`attempts[]{index, source（upstream_error / usage）, outcome（failed / success / partial）, platform, account_id, account_name, proxy_id, proxy_name, upstream_status_code, upstream_request_id, kind, stage, message, started_at, ended_at, duration_ms, first_token_ms, error_log_id, usage_id}`、`error_log_ids`、`dropped_earlier_attempts`。成功那次 `upstream_status_code` 固定 200，`started_at` 由 `created_at − duration_ms` 估算；部署前产生的事件没有 `started_at` / `duration_ms`（null）。

attempts 出错与退路：

- 404 `OPS_REQUEST_NOT_FOUND`、400 `INVALID_REQUEST_ID`：成功样子隐藏“上游尝试”；失败类改用退路。
- 409 `OPS_REQUEST_AMBIGUOUS`（只在用 `request_id` 查时可能出现）：从 `metadata.client_request_ids` 与 `metadata.client_request_id_times` 里选时间离 `created_at` 最近的那个 id 重查一次，不原样重试。
- 请求 ID 含 `/`（路由匹配不到，后端返回纯文本 404、没有 reason）：失败类改用 `client_request_id`；成功样子隐藏该区。
- 退路（没有能力或上面失败）：解析详情的 `upstream_errors` 得到失败的尝试（`account_name`、`upstream_status_code`、`at_unix_ms`、`started_at_unix_ms`、`duration_ms`）；`duration_ms` 缺失时用相邻两次 `at_unix_ms` 之差估算（第一次写 `—`），显示加“约”；客户端最终成功时，再用同一个 `requestRecords(page: 1, filter:)`（`requestID = "client:<client_request_id>"`、`time = .none`、`pageSize = 1`）取成功那次（耗时 = 其 `duration_ms`）。

#### 7.3 字段 → 显示

**头部状态卡**（左侧状态胶囊；成功与已恢复无胶囊）

| 界面元素 | 成功 | 上游失败已恢复 | 失败 | 空值 |
|---|---|---|---|---|
| 状态行 | “✓ 成功 200”（ok） | “上游失败 [429]”：码 = 详情 `upstream_status_code`，没有时用列表解析值，徽章按该码着色 | “⛔ 失败 504”：码 = attempts `client_status_code` ?? `status_code` | — |
| 原因 | — | `phase` · `error_owner` · `severity`（显示名见 0.4） | 同左 | 缺项省略 |
| 模型 | `model`（等宽） | `requested_model` ?? `model` | 同左 | — |
| 上游模型 | `upstream_model` 与 `model` 不同时“上游模型 xxx” | `upstream_model`（同左规则） | 同左 | 不显示 |
| 金额三格 | 实际扣费 `actual_cost` / 账号成本 `account_cost` / 标准 `total_cost`，4 位小数 | — | — | `provider_cost_recorded=false`：账号成本 `$0.0000`，下方小字“合并探测的跟随请求，没有上游成本” |
| 恢复说明 | — | “✓ 已自动重试成功，客户端收到 200”（`status_code`） | — | — |
| 错误信息 | — | `upstream_error_message` ?? `message`，经 `RequestLogPresentation.safeMessage` 脱敏，等宽，最多 6 行，点按展开 | 同左 | “上游返回错误” |
| 胶囊颜色 | 无 | 无 | codeTone(最终码) | — |

**按钮行**（只在失败类）：“标记已处理”（主按钮；已处理时变为“已处理 ✓”，点按撤回）、“查看账号”（`account_id` > 0 时）。已处理且详情有 `resolved_at` 时，按钮下小字“已处理 · <resolved_by_user_name> · 10/16 09:52”。

**耗时**

| 界面元素 | 成功 | 失败类 | 空值 |
|---|---|---|---|
| 条 | 首字占总耗时的比例（最少 4%）+ 其余 | 同左 | 首字缺失只画总条 |
| 首字 | `first_token_ms` | `time_to_first_token_ms` | `—` |
| 总耗时 | `duration_ms` | `duration_ms`；为 null 时用 auth + routing + upstream + response 四段之和，写“约 3.2s” | `—` |
| 方式 | `request_type`：stream 流式、sync 非流式、ws_v2 WebSocket、live Live、cyber 安全策略 | `stream` → 流式 / 非流式（`request_type` 数字 1–5 时按同一表） | `—` |

**上游尝试**（失败类有 ≥ 1 次尝试时显示；成功样子在 attempts ≥ 2 次时显示）

| 界面元素 | 字段 / 计算 | 格式与文案 |
|---|---|---|
| 分区 meta | 尝试数、`client_status_code` | “2 次 · 返回客户端 200” |
| 行 · 序号 | `index` | 圆形序号，按 `upstream_status_code` 着色（2xx ok、429 caution、其余 bad、null 中性） |
| 行 · 标题 | `account_name` ?? `#account_id` | 没有账号写“未知账号” |
| 行 · 右侧 | `upstream_status_code` · `duration_ms` | `429 · 0.4s`；缺失写 `—`；退路估算加“约” |
| 行 · 副行 | `outcome` 与下一次尝试 | success“成功，结果返回客户端”；partial“已计费，但请求最终失败”；failed 且是最后一次“失败，错误返回客户端”；failed 且下一次同账号“失败，同一账号重试”；否则“失败，切换到 <下一次的账号> 重试” |
| 行 · 点按 | `account_id` | 进该账号详情 |
| 分区底注 | `dropped_earlier_attempts` > 0 | “更早的 N 次尝试因队列上限没有记录” |

**Token**（成功）：输入 `input_tokens`、输出 `output_tokens`、缓存读 `cache_read_tokens`、缓存写 `cache_creation_tokens`，千分位。

**关联**

| 行 | 成功 | 失败类 | 点按 |
|---|---|---|---|
| 用户 | `user.username` ?? `user.email` | `user_email` | 用户详情（`user_id`；vendor 不可点） |
| Key | `api_key.name` + 右侧 `api_key.key_masked`（等宽） | `api_key_name` + 右侧 `api_key_prefix…` | 不可点 |
| 分组 | `group.name` | `group_name` | 分组详情 |
| 账号 | `account.name` | `account_name` | 账号详情 |

缺失写 `—` 且不可点。

**标识**

| 行 | 字段 | 动作 |
|---|---|---|
| 请求 ID | 成功：`request_id`；失败类：`request_id` | 点按复制，toast“已复制请求 ID” |
| 服务端请求 ID | 失败类：`client_request_id` | 复制 |
| 上游请求 ID | 成功：`upstream_request_id`；失败类：attempts 最后一次的 `upstream_request_id` | 复制；没有时不显示 |

#### 7.4 交互与写操作

- 标记已处理：`PUT .../resolve {"resolved": true}`。不需要 step-up，不带 Idempotency-Key（写的是绝对值，重复提交安全）。
  - 乐观更新：按钮立即变“已处理 ✓”，toast“已标记为已处理”带“撤销”（撤销 = 发 `{"resolved": false}`）。
  - 失败回滚按钮，toast“标记失败，请重试”；404 `OPS_ERROR_NOT_FOUND`：“记录已不存在”，按钮置灰；404 `OPS_DISABLED`：“运维监控未开启，无法标记”。
  - 成功后就地更新使用记录列表里那一行的 `resolved`，不整页重载。
- 复制：`UIPasteboard`，只复制 ID。
- 查看账号 / 关联行导航见 7.1。

#### 7.5 状态

| 情况 | 显示 |
|---|---|
| 进入（带行数据） | 头部、耗时、关联、标识立即用行数据画；详情与尝试到达后补齐，区块内各自 `ProgressView` |
| 只带请求 ID，查询为空 | 整页“记录不存在或已清理” |
| 详情 404 `OPS_ERROR_NOT_FOUND` | 整页“记录不存在或已清理” |
| 详情 404 `OPS_DISABLED` | 保留行数据，详情区写“运维监控未开启，看不到更多信息” |
| 详情加载失败 | 保留行数据，底部“详情加载失败 · 重试” |
| 尝试加载中 / 失败 | 分区内 `ProgressView` / 改用退路；退路也失败时分区写“没能取到重试链” |

#### 7.6 刷新策略

进入时加载详情与尝试；下拉刷新重新加载二者；不自动轮询。

#### 7.7 对现有代码的改动点

- `Sources/Sub2Core/RequestLogs.swift`：新增 `RequestErrorDetail`（列表字段 + 7.2 列出的详情字段；`upstreamEvents: [UpstreamErrorEvent]` 由 `upstream_errors` 字符串解析，解析失败为空数组）；新增 `RequestAttempts` / `RequestAttempt` 解码；`APIClient` 新增 `errorDetail(id:kind:)`（替换返回 `RequestErrorRecord` 的 `errorRecord(id:kind:)`）、`requestAttempts(id:around:)`（路径段百分号编码；对 409 解析 `metadata`）、`setErrorResolved(id:kind:resolved:)`。按请求 ID 查使用记录不另建方法，用 6.7 的 `requestRecords(page:filter:)`（`time = .none`）。
- `NativeApp/Features/RequestLogsView.swift` 的私有 `UsageRequestDetailView`、`RequestErrorDetailView` 删除，换成新文件 `NativeApp/Features/Logs/RequestDetailView.swift`（三种样子共用分区组件）；去掉现有“错误 / 请求上下文 / 延迟”的 LabeledValue 平铺，文案“上游成本”“差额”删除；`LogAccountDestination` 保留或改用账号章节的详情路由。
- 状态卡左侧胶囊、按钮行、toast 带撤销用全局组件。
- 测试：`RequestLogsTests` 补 `upstream_errors` 解析、attempts 解码（含 null 计时的旧事件）、副行文案规则；UI 测试覆盖成功 / 已恢复 / 失败三种样子与标记已处理的撤销。

---

### 8. 本章未决问题

| # | 问题 | 建议默认值 |
|---|---|---|
| 1 | 上游错误列表项不带 `upstream_status_code`（只在详情里有），已重试成功的行 `status_code` 是客户端拿到的 200，行左下的上游码只能从 `message`（`Recovered upstream error 429`）解析，这是后端固定拼接的文字，不是契约 | 先按 6.3 解析，解析不到写“恢复 / 鉴权”；请维护者在 OpsErrorLog 列表项加 `upstream_status_code`（列已存在，只增字段） |
| 2 | 使用记录不下发状态码，也不下发 `billing_provenance`（失败但计费的行区分不出来） | 用量明细行一律显示 200；如需区分，请后端在 AdminUsageLog 只增 `billing_provenance` |
| 3 | error-trend 的上游 429 / 529 / 其他计数包含已重试成功的行，不能和 `error_count_total` 叠成设计稿的五层 | 按 2.3 退路：只叠 SLA 错误 + 业务限制，上游分项单列文字；若要五层，请后端给 error-trend 增加只计 status ≥ 400 的上游分项 |
| 4 | 统计分析与日志的时间按站点时区还是本机时区（设计稿 sheet 写“按本机时区计算”） | 站点时区（为与首页“今日”和利润一致），设备时区不同时在说明行标注 |
| 5 | 运维错误日志默认只保留 30 天（可配置，App 读不到实际值），超过 30 天的范围里错误类图表前段会是 0 | 范围起点早于 30 天前时加 2.5 的提示文案，不截断范围 |
| 6 | 后端没有站点开通日期、模型所属平台 | 自定义范围最早到 366 天前且不写开通日期；模型页副标题不写平台 |

---

## 50 · 分组

> 本章覆盖：分组列表（`groups`）、分组详情（`group`）、编辑 / 新建分组 sheet（`groupEdit`）、添加账号 sheet（`groupPick`）、成员批量写入逐项结果（`groupBatch`）、分组 API 密钥（`groupKeys`）、分组订阅（`groupSubs`）、首页下钻的分组内账号（`vtGroupAccounts`）。
>
> 依据：`DECISIONS.md`（第 2 轮“分组 可查看 + 可编辑”、第 3 轮 Q7 / Q8、“新建分组默认 正常 + 公开”、评审第 3 条状态胶囊、TPM 口径里的“账号成本”措辞）；设计稿 `html-preview/layouts/main/v-groups.jsx`（已定 = 列表 base、详情 base）与 `tools/routes/groups.json`；后端 sub2 `main` `70116315d`（F01–F05、D02、C14、C15、C17、E03、E06、G06 均已上线，口径以 `BACKEND-API-CHANGES.md` 实现进度表备注为准）。
>
> 下文接口路径都相对 `/api/v1`，字段名逐个对过后端源码；“后端位置”一栏的路径相对 `sub2/backend/internal/`。
>
> 设计稿里的对比变体（列表 grid / table、详情 ring / table）不实现；表格样子留给以后的简化模式。

---

### 0. 本章共用口径（各页面引用）

#### 0.1 用到的 capability（`GET /admin/me` → `data.server.capabilities`）

| capability | 后端条目 | 有它时 | 没有时（老服务端）的退路 |
|---|---|---|---|
| `groups.account_buckets` | F04 | 分组对象带 `error_account_count`、`idle_account_count`（不加 omitempty，键一定在） | 按“键是否存在”判断也可以。退路：`GET /admin/accounts?status=error&lite=1&page_size=1000`，按每个账号的 `group_ids` 数出各分组错误数；idle = `account_count − active_account_count − rate_limited_account_count − error`（缺失的计数字段按 0，见附录 B L16） |
| `groups.capacity_filter` | F05 | `GET /admin/groups/capacity-summary?group_id=<id>` 只算这一组 | 不带参数拉全部，本地按 `group_id` 取那一行 |
| `groups.member_batch` | F01 | `POST /admin/groups/:id/accounts/batch` 增量加减成员 | 见 0.4.4 的逐账号退路 |
| `accounts.status_summary` | D02 | `GET /admin/accounts/status-summary` 给每组 `shortage`（“可用偏低”判定） | 本地判定：`available < total × 0.5`（与后端站点默认阈值 `group_shortage_min_ratio` 的默认值 0.5 一致） |
| `accounts.list_query` | C14 | 成员列表 `sort_by=urgency`、`include_counts=1` | 客户端按状态顺序排序；计数本地数 |
| `accounts.today_stats_group` | C17 | 成员“今日”只算本分组（`today-stats/batch` 带 `group_id`） | 显示账号全站今日并换脚注（见 2.3） |
| `lists.etag` | B09 | `GET /admin/groups` 支持 `If-None-Match` / 304 | 每次全量解码 |
| `admin.idempotent_writes` | G06 | 分组新建 / 修改 / 删除接受可选 `Idempotency-Key`，超时可同 key 重发拿回结果 | 照常带 key（老服务端忽略）；超时**不要**自动重发，读回核对 |
| `api_keys.masked_view` | E03 | `groups/:id/api-keys?key_view=masked` 不回传 Key 明文 | 收到的 `key` 明文立刻丢弃、不落盘，界面只显示 `key_masked`（缺失时本地拼“前 3 位…后 4 位”） |
| `api_keys.effective_status` | E06 | Key 行状态读 `effective_status` | 不在本章另写映射，直接用 30 章 §7.3 的推导函数 `AdminAPIKeyStatus`（`Sources/Sub2Core/UserKeys.swift`，两章共用一个实现）：先看 `status`，不是 active / quota_exhausted / expired 的 → inactive；库里已经是 quota_exhausted / expired 的照原样；然后看 `expires_at` 是否已过，过了 → expired；最后看 `quota > 0 && quota_used ≥ quota`，满足 → quota_exhausted；都不满足 → active（E06 进度表的口径） |
| `meta.catalog` | C13 | 新建分组的平台下拉取 `data.platform_catalog.platforms[].id / display_name` | 用内置平台表 |
| `ops.alert_event_details` | D06 | 告警横幅第二行用 `rule`（规则摘要） | 第二行只写触发时间 |

F02（`groups/:id/stats` 返回真实数据）没有 capability：按响应里有没有 `subscriptions_total` 键判断。没有这个键 = 老服务端占位（全 0），不要显示其中的数字，改用 0.6 的退路请求。

`GET /admin/me` 的 `data.server.run_mode == "simple"`（简易模式）与 vendor（`data.workspace != null`）的差异集中写在 0.7。

#### 0.2 四个桶、健康判定与 D02 的对账

**四个桶（列表、详情状态卡、图例、色格条都用它）**：取分组接口（F04）的四个计数，后端 SQL 见 `repository/group_repo.go:991-1022`：

| 桶 | 字段 | 后端口径 | 色调 |
|---|---|---|---|
| 可用 | `active_account_count` | 未删除、`status=active`、`schedulable=true`、未“过期且自动暂停”、不在限流 / 过载 / 临时不可调度窗口 | ok |
| 受限 | `rate_limited_account_count` | 同上前提（`active` + 开着调度 + 未过期暂停），但处在任一限时窗口 | caution |
| 错误 | `error_account_count` | `status=error` | critical |
| 暂停·停用 | `idle_account_count` | 余数：停用（`status` 非 active / error）、停止调度、到期自动暂停，**以及停了调度但仍在限时窗口里的账号** | neutral |

`account_count = 四项之和`，只对 `GET` 与 `PUT` 的响应成立；`POST /admin/groups` 新建响应不加载计数（全 0），新建后以成员批量接口返回的 `counts` 为准。

**与 D02（`accounts/status-summary`）对账**（首页、账号 Tab 组头用 D02；分组页一律以 F04 为准，进度表 F04 审查修正）：

- `active_account_count` = D02 `available`（同一谓词）；`error_account_count` = D02 `error`。
- 通常 `idle_account_count = paused + inactive + stopped`，`rate_limited_account_count = overloaded + rate_limited + temp_unschedulable − stopped`。
- 例外：账号已过期、开了“到期自动暂停”、调度开关仍开着、又在限时窗口里——F04 算 idle，D02 算进限时桶且不记 stopped；到期任务每分钟一次，把它停调度后两边重新对上。这类差异最多持续约 1 分钟，界面不处理。
- 因为“停了调度的限流账号”在分组桶里算暂停·停用，而它的成员行仍显示“限流中 · 已停止调度”，详情页图例下要加一行说明（见 2.3）。

**健康判定**（列表分段、徽章、状态卡）：

| key | 条件（按顺序） | 徽章文案 | 色调 |
|---|---|---|---|
| off | `status != "active"` | 已停用 | neutral |
| none | `active_account_count == 0` | `account_count > 0` 时“无可用账号”，否则“没有账号” | critical |
| low | D02 该组 `shortage.is_short == true`；D02 不可用时 `active < account_count × 0.5` | 可用偏低 | caution |
| ok | 其余 | 列表不显示徽章；状态卡写“全部可用”（可用 = 总数）或“正常” | ok |

D02 的 `shortage` 有分组可用性告警规则时按规则判定（`source=alert_rule`），否则按站点阈值（`source=default`，`available=0` 一定算）。设计稿里的 0.6 只是演示告警规则的值，不要写死。

#### 0.3 色格条与图例

- 一格一个账号，顺序：可用 → 受限 → 错误 → 暂停·停用。格子不带账号身份，只用四个计数画。
- 列表：96×8 pt，格间距 2 pt，单格最小宽 3 pt；成员数放不下（`n × 5 > 96`，即超过 19 个）时改画四段按比例的条（非 0 的段最小 3 pt）。详情状态卡：满宽 × 12 pt，间距 3 pt，同样放不下时改比例段。
- 着色：可用 `--ok` 实心；受限 `--caution` 实心；错误 `--critical` 实心；暂停·停用为 1.5 pt `--neutral` 描边、60% 不透明。没有成员：一格 1 pt `--critical` 描边。停用分组：所有格子改为 `--neutral` 描边、45% 不透明。
- 无障碍：整条一个元素，标签“可用 x / y”。状态从不只靠颜色：旁边总有“可用 x/y”数字与文字说明。
- 图例：`可用 n · 受限 n · 错误 n · 暂停·停用 n`，为 0 的项变淡。

#### 0.4 成员写入协议（F01）

##### 0.4.1 请求

`POST /admin/groups/:id/accounts/batch`（`handler/admin/group_members_handler.go`，`service/admin_group_members.go`）

```json
{"add":[{"account_id":11},{"account_id":12,"priority":2}],"remove":[13],"confirm_mixed_channel_risk":false}
```

- `priority` 可省，省略或 ≤0 时默认 50；撤销“移出”时把响应里的旧 `priority` 传回。
- `add` 与 `remove` 去重后合计 ≤ 200；同一账号不能同时在两边。App 一次超过 200 个时拆批顺序发送。
- 不需要 `Idempotency-Key`：已在组内的加入、不在组内的移出都返回 `unchanged`，原样重放安全。
- 不碰账号行本身，不改该账号在其他分组的优先级。

##### 0.4.2 响应

```json
{"group_id":3,"added":1,"removed":1,"unchanged":1,"failed":1,
 "results":[{"account_id":11,"action":"add","status":"added","priority":50},
            {"account_id":14,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK","message":"…","details":{"current_platform":"Antigravity","other_platform":"Anthropic"}}],
 "counts":{"account_count":6,"active_account_count":4,"rate_limited_account_count":1,"error_account_count":0,"idle_account_count":1}}
```

- `results[]`：`account_id`、`action`（add / remove）、`status`（added / removed / unchanged / failed）、`priority`（added / removed 时有）、`reason` / `message` / `details`（failed 时有）。结果按 action 排序（add 在前）。
- `counts` 可能缺省（回读失败时），缺省就保留旧计数并刷新详情。
- 逐项失败只有两种 reason：`ACCOUNT_NOT_FOUND`（不存在或不属于本工作区）、`MIXED_CHANNEL_RISK`（只在 Anthropic 与 Antigravity 混用时出现，`details` 里的平台名是首字母大写的展示名，不是平台枚举）。

##### 0.4.3 回执与撤销（列表、详情、两个 sheet 共用）

| 结果 | 回执文案 | 回执按钮 |
|---|---|---|
| 全部成功 | `已加入 n 个账号` / `已移出 n 个账号` / `已加入 a 个、已移出 b 个账号`；有变化时后缀 ` · 可用 x → y`（x、y 取写入前与 `counts.active_account_count`） | 撤销（发反向请求：added → remove；removed → add 并带回 priority） |
| 部分失败 | `已加入 a 个，n 个失败`（移出同理） | 查看 → `groupBatch` 结果页 |
| 全部失败 | `加入失败 · n 个账号没有改动` | 查看 → `groupBatch` |
| `unchanged` | 计入成功，不单独说 | — |

前缀：新建时 `已创建「名称」 · …`，编辑保存时 `已保存「名称」 · …`。

##### 0.4.4 退路（没有 `groups.member_batch`）

逐个账号串行：`GET /admin/accounts/:id` 取最新 `group_ids` → 本地加入或去掉本组 → `PUT /admin/accounts/:id` 只带 `group_ids`。每个账号一个结果，遇到 409 `MIXED_CHANNEL_WARNING` 记为该账号失败（reason 记 `MIXED_CHANNEL_RISK`，详情从 409 的 `details` 取）。这条路径有副作用（会按快照写回账号整行、重置该账号在其他分组的优先级），所以退路模式下 sheet 底部提示改为“服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改。”

#### 0.5 停用 / 启用 / 复制 / 删除（列表滑动、长按菜单、详情 ⋯ 共用）

| 动作 | 请求 | 确认 | 回执 / 刷新 |
|---|---|---|---|
| 停用分组… | `PUT /admin/groups/:id`，body `{"status":"inactive"}`，带 `Idempotency-Key` | 弹确认：标题 `停用「名称」？`，正文 `站点 <站点名>`、`使用这个分组的 N 个 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。`；按钮“停用分组”（default）/ 取消。N 在弹框那一刻拉 `GET /admin/groups/:id/stats` 的 `active_api_keys`；拿不到（vendor、老服务端、失败）时去掉数字：“使用这个分组的 API 密钥会被拒绝……” | 乐观更新为停用 → 回执 `已停用「名称」` + 撤销（再 PUT `active`，新 key）。失败回滚并提示。网关拒绝文案已核对（`server/middleware/api_key_auth.go:447` GROUP_DISABLED） |
| 启用分组 | 同上 `{"status":"active"}` | 不确认（可逆） | 回执 `已启用「名称」` + 撤销 |
| 复制分组 | `POST /admin/groups/:id/duplicate`，**必须**带 `Idempotency-Key`（`executeAdminIdempotent` 强制 key） | 不确认 | 响应即新分组（`dto.AdminGroup`）：停用、名称加 ` (Copy)` / ` (Copy n)`、连同成员账号与优先级在同一事务复制，没有部分结果。回执 `已复制为「新名」 · 停用中 · N 个成员账号` + 查看（push 新分组详情）。响应头 `X-Idempotency-Recovered: true` 时同样视为成功 |
| 删除分组… | `DELETE /admin/groups/:id`，带 `Idempotency-Key` | 共用删除确认（通用约定）：标题 `删除分组「名称」？`，正文第一行 `站点 <站点名> · 删除后不能恢复。`，后接下表后果行；Face ID 关闭时输入完整名称才能点“删除分组”，打开时按钮为“用 Face ID 删除” | 详情页先 pop 再删；回执 `已删除分组「名称」`；从列表与分组目录缓存移除 |

删除后果行（弹框那一刻拉 `groups/:id/stats`，为 0 的行不写）：

| 条件 | 文案 | 依据 |
|---|---|---|
| `total_api_keys > 0` | `使用这个分组的 N 个 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。` | 后端删除不清 Key 的 `group_id`，网关见到分组已删返回 GROUP_DELETED（`server/middleware/api_key_auth.go:439-446`）。**与设计稿“将不再属于任何分组”不同，以源码为准** |
| 订阅分组且 `subscriptions_total > 0` | `删除 N 条订阅记录（生效中 M 条）。`（M = `subscriptions_active`，为 0 时省略括号） | `repository/group_repo.go:908-932` 软删除全部订阅 |
| `account_count > 0` | `N 个成员账号移出分组，账号本身保留。` | 同上 :941-943 删除 account_groups |

#### 0.6 显示格式

| 内容 | 规则 | 例 |
|---|---|---|
| 费率倍数 | `×` + 数值；到 0.1 精度时一位小数，否则两位 | ×0.8、×1.0、×1.25 |
| 计费类型 | `standard` → 标准（余额）/ 短写“标准计费”；`subscription` → 订阅（配额）/“订阅计费” | |
| 每用户 RPM | `rpm_limit` 0 → 不限 | 不限、600 |
| 订阅限额 | `daily/weekly/monthly_limit_usd` null → 无限制；金额 0 位小数 | $20、无限制 |
| 金额 | USD，Decimal 四舍五入两位；计费数字不着色 | $933.30 |
| 平台名 | 已知 id 用 App 内置中文名（`zhipu` → 智谱 GLM、`composite` → 组合分组），未知 id 原样显示 | |
| 专属 | `is_exclusive` true → 专属，false → 公开 | |
| 分组状态 | `active` → 正常，`inactive` → 停用（分组用账号那套词，不用“启用 / 禁用”） | |
| 缺失值 | `—`；0 显示 0 | |

“今日 / 昨日”都是服务器时区 00:00 切分（`service/custom_group_usage_rollup.go:23`），按 Key 所属分组（`usage_logs.group_id`）统计**实际扣费**。

#### 0.7 权限与运行模式

| 能力 | 站长（admin） | vendor | 简易模式（`run_mode=simple`） |
|---|---|---|---|
| 列表 / 详情读取 | ✓ | ✓（只看已授权分组，计数按本工作区重算） | ✓（响应只有 id、name、description、platform、status、计数、sort_order） |
| 新建 | ✓ | ✗（POST 被 vendor 白名单拒绝，403 FORBIDDEN）→ 隐藏 + | ✓，只提交名称、描述、平台 |
| 编辑 | ✓ | `permissions.group_ops` 或 `group_billing` 任一才显示“编辑”；没有 `group_ops` 时名称、描述、状态、专属、RPM 只读；没有 `group_billing` 或分组 `billing_locked=true` 时倍率与限额只读并注“计费由站长管理”（后端会静默丢弃越权字段，`service/admin_group_field_scope.go`） | 只有名称、描述（状态等字段后端会丢弃，隐藏停用 / 启用） |
| 加减成员 | ✓ | ✗（POST 403）→ 隐藏，见未决问题 1 | ✓（组合分组 400 `SIMPLE_MODE_GROUP_NOT_BINDABLE`） |
| 复制、用量汇总、容量、stats、API 密钥、订阅 | ✓ | 复制、stats、API 密钥、订阅 ✗（403）；用量、容量按本工作区 | 全部 403 `SIMPLE_MODE_OPERATION_UNSUPPORTED` → 隐藏对应行与菜单项 |
| 删除 | ✓ | ✗ | ✓，但分组里还有账号时 409 `GROUP_NOT_EMPTY` |
| 账号状态汇总（D02） | ✓ | ✗（403）→ 按 0.2 本地判定 | ✓ |

分组接口都**不需要 step-up**（`server/routes/admin.go:400-428` 未挂 stepUpAuth）。删除受 App 本地“高风险操作需要 Face ID”开关控制。

#### 0.8 分组相关错误 reason → 文案

| HTTP / reason | 场景 | 文案与动作 |
|---|---|---|
| 404 `GROUP_NOT_FOUND`、404 `RESOURCE_NOT_FOUND` | 详情、编辑、删除、成员写入 | 详情显示“这个分组已删除”空态并从列表移除；删除时视为已删除 |
| 409 `GROUP_EXISTS` | 新建、改名 | 名称字段下红字“已有同名分组。”，sheet 不关闭 |
| 409 `GROUP_NOT_EMPTY` | 简易模式删除 | “分组里还有账号，先移出成员再删除。” |
| 400 `SIMPLE_MODE_GROUP_NOT_BINDABLE` | 简易模式给组合分组加账号 | “简易模式下不能给组合分组添加账号。” |
| 403 `SIMPLE_MODE_OPERATION_UNSUPPORTED` | 简易模式调高级接口 | 不应出现（已隐藏）；出现时“简易模式下不支持此操作。” |
| 403 `FORBIDDEN` | vendor 调站长专属接口 | 不应出现（已隐藏）；出现时“你的工作区没有这个权限。” |
| 400 `EMPTY_MEMBER_CHANGE`、`TOO_MANY_ACCOUNTS`、`ACCOUNT_IN_BOTH_LISTS`、`INVALID_ACCOUNT_ID`、`INVALID_GROUP_ID` | 成员写入参数 | App 侧已避免；出现时“提交的成员有误，请重试。”并记日志 |
| 400 `INVALID_GROUP_ID`、`TOO_MANY_IDS` | capacity-summary 参数 | 容量区显示“—”并记日志（App 只传 1 个 id，不会超限） |
| 409 `IDEMPOTENCY_*`、503 `IDEMPOTENCY_STORE_UNAVAILABLE` | 带 key 的写 | 按通用约定处理（IN_PROGRESS / RETRY_BACKOFF 按 `Retry-After` 同 key 重试；KEY_CONFLICT 换 key；STORE_UNAVAILABLE 先读回核对） |
| 500 `GROUP_REPOSITORY_UNSUPPORTED` | 成员写入 | “服务器暂不支持批量调整成员。”并改走 0.4.4 退路 |
| 网络错误 / 超时（写） | 新建、修改、删除 | 沿用现有“结果待确认 → 读取服务器状态核对”流程（不自动重发；有 `admin.idempotent_writes` 时可用同 key 重发一次拿回结果） |
| 网络错误 / 超时（成员写入） | 成员批量 | 自动用同一请求体重试 1 次（接口幂等）；仍失败时回执“成员改动未确认 · 重试”，同时刷新详情 |

---

### 1. 分组列表（`screen:groups`）

#### 1.1 入口与导航

- 进入：搜索 Tab 目录“资源 → 分组”（`00-core.jsx:839`）；首页“可用不足 N 个分组”行在 N > 1 时进入本页，并选中“需处理”段（10 章 §1.1）。
- 去向：点行 → 分组详情；右上 + → 新建分组 sheet；右滑“添加账号” → 添加账号 sheet；左滑“编辑” → 编辑分组 sheet，“停用 / 启用” → 0.5；长按 → 上下文菜单（编辑分组、添加账号、停用分组… / 启用分组、复制分组、删除分组…（红字，分隔线后））。

#### 1.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| 分组与四桶计数 | `GET /admin/groups` | `page=1&page_size=1000`（默认 `sort_by=sort_order&sort_order=asc`，`status` 不传 = 全部状态） | 带 `If-None-Match`（`lists.etag`），304 时用缓存；`total > 1000` 时继续翻页。`handler/admin/group_handler.go:371-415` |
| 今日实际扣费 | `GET /admin/groups/usage-summary` | 无（站长按服务器时区；vendor 传 `timezone=<server_timezone>` 保持一致） | 返回数组 `[{group_id, today_cost, yesterday_cost, total_cost}]`，按 `group_id` 合并。`:975-1006` |
| 可用偏低判定 | `GET /admin/accounts/status-summary` | 无参数（不带 `include_accounts`） | 取 `data.groups[].shortage.is_short` 按 `group_id` 合并；服务端 10 秒缓存。vendor / 无 `accounts.status_summary` 时按 0.2 本地判定 |

三个请求并发；列表只依赖第一个，其余两个失败只影响对应的格子。

#### 1.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用 |
|---|---|---|---|
| 导航标题 | — | 分组 | — |
| 导航副标题 | 健康为 none 的分组数 k；总数 n | `<站点名> · k 个分组无可用账号`；k=0 时 `<站点名> · n 个分组` | — |
| 搜索框 | 本地过滤 `name` 与平台中文名，不区分大小写 | 占位“分组名称或平台” | 无匹配时“没有匹配的分组” |
| 分段 | 健康 none+low → 需处理；ok → 正常；off → 停用 | 段头 `需处理 3`，空段不显示 | — |
| 段内排序 | none → low → ok → off；再按可用比例升序；再按 `sort_order`、`id` | — | — |
| 行首图形 | 健康 key | none 八边形、low 仪表、ok 分组、off 减号；色调同健康 | — |
| 第一行左 | `name` + 小字平台名 | `高级组 Anthropic` | — |
| 第一行右 | `is_exclusive` → “专属”标签；健康非 ok → 徽章 | 见 0.2 徽章文案 | — |
| 第二行 | 可用 `active_account_count` / `account_count` | “可用 2/3”，none / low 时分子用对应色 | 计数缺失按 0 |
| 色格条 | 四桶计数 | 见 0.3 | — |
| 分档说明 | 非 0 的受限、错误、暂停·停用 | `受限 1 · 错误 1 · 暂停·停用 2` | 全部可用时不显示 |
| 第三行左 | `rate_multiplier` + `subscription_type` | `费率倍数 ×0.8 · 标准计费` | 简易模式整行隐藏 |
| 第三行右 | usage-summary `today_cost` | `今日 $933.30` | 汇总失败或该组无行时 `今日 —` |
| 状态胶囊 | 健康 none → critical，low → caution | 浮在左侧的胶囊；**相邻行无论同色异色连成一根连续状态轨**，只有整段首尾是圆头（评审第 3 条与 TPM 口径节） | ok / off 不画 |
| 停用行 | `status=inactive` | 整行降低对比（is-idle） | — |
| 底注 | — | `左滑编辑或停用，右滑添加账号；长按看全部操作。今日按 Key 所属分组统计。` | — |

#### 1.4 交互与写操作

| 操作 | 条件 | 行为 |
|---|---|---|
| 右滑“添加账号”（accent） | 只对 `status=active` 的分组，且有加减成员权限（0.7） | 打开 4 `groupPick` |
| 左滑“编辑” | 有编辑权限 | 打开 3 `groupEdit` |
| 左滑“停用” / “启用” | 有编辑权限、非简易模式 | 见 0.5 |
| 右上 + | 有新建权限 | 打开 3 `groupEdit`（新建） |
| 长按 | — | 同详情 ⋯ 菜单（`fromList`：删除后留在列表） |

滑动操作同时放进长按菜单，VoiceOver 通过菜单触达。

#### 1.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 骨架行 3 条 |
| 空（站点没有分组） | 空态“还没有分组” + “新建分组”按钮（有权限时） |
| 搜索无结果 | “没有匹配的分组” |
| `groups` 失败 | 有缓存：保留旧数据，顶部细条“刷新失败 · 重试”；无缓存：错误态 + 重试 |
| usage-summary 失败 | 各行“今日 —”，不报错 |
| status-summary 失败 / 403 | 静默改用本地阈值判定 |
| 401 / 423 等全局错误 | 交给会话层（通用约定） |

#### 1.6 刷新策略

- 进入时加载；下拉刷新三个请求全刷。
- 前台每 60 秒自动刷新（DECISIONS 第 2 轮“刷新”）；离开页面或进入后台停止。
- `GET /admin/groups` 用 ETag；另外两个没有 ETag，照常请求。
- 写操作成功后：本地先改（停用 / 启用乐观更新），随后静默刷新三个请求；新建、复制、删除、改名后同时刷新分组目录缓存（`groups/all?include_inactive=true`，账号、用户等页面用它显示组名）。

#### 1.7 对现有代码的改动点

- `NativeApp/Features/GroupsView.swift:GroupsView` → 重写为 `GroupListView`：去掉“筛选”分区的平台 / 状态 Picker（改为本地搜索 + 三段分区），去掉分页“加载更多”（一次拉全量），行改为三行样式；`.searchable` 提示改为“分组名称或平台”。
- `GroupsView.swift:GroupWorkspace` → 抽成跨页面共享的 `@Observable GroupStore`（列表缓存、usage-summary 缓存、shortage 映射、`revision`），保留 `isUITesting` 的 fixture 分支，fixture 改为设计稿的 10 个分组（`shared/data.jsx` DEMO.groups）。
- `Sources/Sub2Core/GroupManagement.swift:APIClient.groups(page:search:platform:status:)` 保留；新增 `groupList(etag:)`（返回 `.notModified` / `.page(Page<AdminGroup>, etag)`）——依赖通用约定里 APIClient 的条件请求支持。
- 新增 `APIClient.groupUsageSummary() -> [GroupUsageSummary]`、`accountStatusSummary(groupID:)`（D02，可与首页章节共用）。
- 新增 `Sources/Sub2Core/GroupPresentation.swift`：`GroupHealth`（0.2 判定）、`GroupBuckets`、色格条分段计算、`rateText`、`limitText`、`rpmText`、删除后果行、停用确认文案（纯函数，便于单测）。
- 新增 `NativeApp/Features/Groups/GroupCellsView.swift`（色格条 + 图例，列表与详情共用）。
- 入口：`NativeApp/Sub2MobileApp.swift:ManagementView` 的“分组管理”迁到搜索目录（导航章节负责）。
- 新增文件后运行 `scripts/generate_project.py` 重新生成工程（它按目录 `rglob("*.swift")` 收集）。

---

### 2. 分组详情（`screen:group`，route `{kind:'group', id}`）

#### 2.1 入口与导航

- 进入：分组列表行；请求详情的“分组”行（`00-core.jsx:995`）；统计分析的分组排行行（`v-analytics.jsx:422`）；首页“可用不足 N 个分组”行（N = 1 时，10 章 §1.1）与告警详情范围区的分组行（10 章 §3.1，见 8）；复制分组回执“查看”。
- 去向：⋯ 菜单（编辑分组、添加账号、停用分组… / 启用分组、复制分组、删除分组…）；告警横幅 → 告警详情 `{kind:'alert', id}`；成员行 → 账号详情；“添加 <平台> 账号”行 → `groupPick`；记录与关联 → 使用记录（带分组筛选）、`groupKeys`、`groupSubs`；“在 Web 中编辑”行 → 浏览器打开 `<站点>/admin/groups`（Web 路由 `frontend/src/router/index.ts:473`）。

#### 2.2 数据来源

全部并发，各区块独立成败：

| 区块 | 接口 | 参数 | 说明 / 退路 |
|---|---|---|---|
| 分组本身 | `GET /admin/groups/:id` | — | `dto.AdminGroup`；404 → “这个分组已删除” |
| 成员 | `GET /admin/accounts` | `group=<id>&lite=1&sort_by=urgency&page=1&page_size=100` | 不可用在前（C14 urgency：错误 > 限时窗口 > 暂停 > 其他停用 > 正常）；无 `accounts.list_query` 时客户端按 错误 → 过载 → 限流 → 临时不可调度 → 暂停 → 停用 → 正常 排。超过 100 个滚到底继续翻页 |
| 成员今日 | `POST /admin/accounts/today-stats/batch` | `{"account_ids":[…], "group_id":<id>}`，每批 ≤ 200 | 响应 `stats` 以账号 id 字符串为键，取 `user_cost`（实际扣费）；`failed_account_ids` 里的显示“—”；带 `group_id` 时整体失败为 503 `ACCOUNT_STATS_UNAVAILABLE`（不会退回不分组的数）。响应回显 `group_id` 才算分组口径生效，否则按全站口径并换脚注 |
| 容量 | `GET /admin/groups/capacity-summary` | `group_id=<id>`（F05） | 返回数组，停用分组为 `[]`；无 `groups.capacity_filter` 时拉全量取本组 |
| 今日 / 昨日 / 累计 | `GET /admin/groups/usage-summary` | 同 1.2 | 列表页缓存 60 秒内直接复用 |
| 今日请求、Tokens、账号成本 | `GET /admin/dashboard/groups` | `start_date=<今天>&end_date=<今天>&group_id=<id>&timezone=<server_timezone>` | `data.groups[0]` 的 `requests`、`total_tokens`、`account_cost`（注意 `cost` 是标准计费，不用）。`end_date` 含当天（`pkg/usagequery/range.go:65-71`） |
| Key 与订阅数 | `GET /admin/groups/:id/stats` | — | `total_api_keys`、`active_api_keys`、`subscriptions_total`、`subscriptions_active`（`total_requests` 恒为 0，不显示）。退路：`GET /admin/groups/:id/api-keys?page_size=1` 读 `total`；`GET /admin/subscriptions?group_id=<id>&status=active&page_size=1` 读 `total`。vendor 403 → 隐藏这两行 |
| 可用偏低 | `GET /admin/accounts/status-summary` | `group_id=<id>` | 取 `groups[0].shortage`；不可用时本地判定 |
| 告警横幅 | `GET /admin/ops/alert-events` | `status=firing&group_id=<id>&limit=5` | 取第一条；404 `OPS_DISABLED` 或失败 → 不显示横幅 |
| 错误请求数 | `GET /admin/ops/request-errors` | 与日志章节“错误请求”段同一组参数，另加 `group_id=<id>&time_range=24h&page=1&page_size=1` | 读 `data.total` |
| 上游错误数 | `GET /admin/ops/upstream-errors` | `group_id=<id>&time_range=24h&page=1&page_size=1`（默认窗口只有 1h，必须显式传 24h） | 读 `data.total` |

#### 2.3 字段 → 显示映射

**导航**

| 元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 标题 | `name` | — | — |
| 副标题 | 平台、`subscription_type`、`is_exclusive` | `Anthropic · 标准（余额） · 公开` | 简易模式只写平台 |
| ⋯ | — | 见 2.1；按 0.7 隐藏无权项 | — |

**告警横幅**（在状态卡上方）

| 元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 色调 | `severity` | P0 critical，P1 / P2 caution，P3 neutral；`--tone-wash` 底 + 状态胶囊 | — |
| 第一行 | `severity`、`title` | `P1 告警中 · 标准组错误率 5.2%` | — |
| 第二行 | `rule.name` 或规则摘要（`metric_type`、`operator`、`threshold`、`window_minutes`）、`fired_at` | `错误率 > 5%（5 分钟） · 09:29 起`；今天只写 HH:MM，更早写 MM-DD HH:MM | 无 `rule` 时只写时间 |
| 右侧 | — | “查看”小按钮；整条可点（≥ 44pt） | — |

**状态卡**

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 停用分组 | `status=inactive` | 安静卡：停用图形 + `已停用 · 使用此分组的 API 密钥会被拒绝`（不画数字与色格） | — |
| 左上 | 健康 | none / low：大徽章 + 状态胶囊；ok：对勾 + “全部可用” / “正常” | — |
| 右上 | 不可用数 = `account_count − active_account_count` | `1 个不可用`；为 0 时 `共 N 个账号` | — |
| 大数字 | `active_account_count` / `account_count` | `2 / 3 个账号可用`，none / low 时数字用对应色 | — |
| 色格条（大） | 四桶 | 见 0.3 | — |
| 图例 | 四桶 | 见 0.3 | — |
| 停调度说明 | 成员中处于限时状态且 `schedulable=false` 的个数 s | `其中 s 个账号限流中但已停止调度，计入暂停·停用`（s=0 不显示；“限流中”按最常见状态写，混合时写“受限”） | 成员未加载时不显示 |
| 最早恢复 | 成员的 `rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until` 中仍在未来的最小值 | `最早 04:37 后恢复 1 个 · Claude-官方-03`，每秒倒数 | 没有限时成员不显示 |
| none 警示 | `account_count>0` | `没有可用的账号，这个分组的新请求会失败。先让成员账号恢复或启用调度，或加入同平台的可用账号。` | — |
| | `account_count=0` | `分组里还没有账号，新请求会失败。`；`total_api_keys=0` 时追加 `目前也没有 API 密钥使用它。` | — |

**按钮行**（状态卡下）

| 分组状态 | 按钮 |
|---|---|
| 停用 | 启用分组（主）· 编辑分组 |
| 正常且 none / low | 添加账号（主）· 编辑分组 |
| 正常且 ok | 添加账号 · 编辑分组（主） |

无权限的按钮不显示（0.7）。

**壹 · 成员账号**

| 元素 | 字段 / 计算 | 格式 | 空值 |
|---|---|---|---|
| 分区标题 | `account_count` | `成员账号`，meta `3 个 · 不可用在前`（1 个时只写 `1 个`） | — |
| 成员行 | 账号章节的三行账号行组件，`omit: group`、`home: <本组名>` | 第二行写平台与“另属 X、Y”；状态胶囊按账号状态色 | — |
| 行右“今日” | today-stats/batch 的 `user_cost` | 金额 | 失败或在 `failed_account_ids` 里 → `—` |
| 添加行 | `platform` | `添加 Anthropic 账号`（accent，组合分组写“添加账号”） | 无权限不显示 |
| 脚注 | 是否分组口径 | 分组口径：`成员行的“今日”只算这个分组的请求（按 Key 所属分组）。`；全站口径：`成员行的“今日”是账号今日，含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。` | 没有成员不显示 |
| 空 | `account_count=0` | 只有“添加 … 账号”行 | — |

**贰 · 用量与容量**（meta `按 Key 所属分组 · 00:00 切分`）

| 元素 | 字段 | 格式 | 空值 |
|---|---|---|---|
| 今日 / 昨日 / 累计 · 全部时间 | usage-summary `today_cost` / `yesterday_cost` / `total_cost` | 三栏大金额 | `—` |
| 请求 · Tokens · 账号成本 | dashboard/groups `requests` / `total_tokens` / `account_cost` | `请求 10,194  Tokens 62.9M  账号成本 $370.27`（“成本”统一叫“账号成本”） | 该行整行 `—` |
| 容量行 | capacity `concurrency_used/max`、`sessions_used/max`、`rpm_used/max` | 只画 `max > 0` 的行：`并发`、`会话`、`调度 RPM`，用账号章节的容量条 | 一行都没有时：`容量 —` + 说明：停用分组“停用的分组不统计容量”；没有成员“没有成员账号”；`active=0`“没有可调度的账号”；其余“暂无容量数据” |

**叁 · 记录与关联**

| 行 | 数据 | 右侧文案 | 去向 | 不可用 |
|---|---|---|---|---|
| 错误请求 | request-errors `total` | `近 24 小时 N 条` | 使用记录 `{scope: errors, group: id}` | OPS_DISABLED → `运维监控未开启`（仍可点进，由日志页处理）；失败 → `—` |
| 上游错误 | upstream-errors `total` | `近 24 小时 N 条` | `{scope: upstream, group: id}` | 同上 |
| 使用记录 | — | — | `{scope: usage, group: id}` | — |
| API 密钥 | stats `total_api_keys` | `N 个` | `groupKeys` | vendor / 简易模式隐藏；失败 `—` |
| 订阅（仅 `subscription_type=subscription`） | stats `subscriptions_active` | `生效中 N 个` | `groupSubs` | 同上 |

**肆 · 配置**

| 项 | 字段 | 格式 | 点按 |
|---|---|---|---|
| 费率倍数 | `rate_multiplier` | ×0.8 | 打开编辑（有权限时） |
| 计费类型 | `subscription_type` | 标准（余额）/ 订阅（配额） | — |
| 每用户 RPM | `rpm_limit` | 不限 / 数字 | 打开编辑 |
| 类型 | `is_exclusive` | 专属 / 公开 | 打开编辑 |
| 客户端 | `claude_code_only` | 仅限 Claude Code / 所有客户端 | — |
| 降级分组 | `claude_code_only` 为 true 时取 `fallback_group_id` 在分组目录里的名称 | 名称；`fallback_group_id=null` → 直接拒绝；`claude_code_only=false` → — | — |
| 描述 | `description` | 多行 | 空时不显示 |
| 订阅限额 · 每个订阅（仅订阅分组） | `daily_limit_usd` / `weekly_limit_usd` / `monthly_limit_usd` | 每日 / 每周 / 每月，null → 无限制 | — |
| Web 行 | — | `模型白名单、组合路由、图片计费` / `在 Web 中编辑` | 打开浏览器 |

#### 2.4 交互与写操作

| 操作 | 请求 | 确认 | 成功后 |
|---|---|---|---|
| 启用 / 停用 / 复制 / 删除 | 0.5 | 0.5 | 0.5；停用 / 启用后重拉本页 |
| 成员左滑 · 状态动作 | 错误、过载、限流、临时不可调度 → “恢复状态”；暂停 → “启用调度”；正常 → “停止调度”（接口与两种恢复选择见账号章节：`recover-state`、`/accounts/:id/schedulable`） | 账号章节 | 回执带撤销；重拉成员、分组计数、容量 |
| 成员左滑 · 移出（critical） | 0.4：`{"remove":[id]}` | 账号正常、分组正常且 `active_account_count == 1` 时确认：标题 `把「账号」移出「分组」？`，正文 `站点 <站点名>`、`它是这个分组唯一可用的账号，移出后这个分组的新请求会失败。账号本身保留。`，按钮“仍然移出”（destructive）/ 取消；其余直接执行 | 乐观移除该行；回执 `已移出「账号」`，账号可用时追加 ` · 可用 x → x−1`；撤销 = `{"add":[{"account_id":id,"priority":<响应里的 priority>}]}`；失败把行放回并提示 |
| 告警横幅 | — | — | push 告警详情；返回时重拉横幅（告警被手动解决后横幅消失） |

成员行的滑动动作同时放进长按菜单。没有加减成员权限时只保留状态动作。

#### 2.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 状态卡骨架；其余分区各自骨架 |
| 分组 404 | 整页“这个分组已删除”，导航只留返回 |
| 成员失败 | 成员分区“成员加载失败 · 重试”；状态卡仍按分组计数显示 |
| 成员今日失败 | 各行今日 `—` |
| 容量 / 用量 / dashboard/groups 失败 | 对应格 `—` |
| stats 失败或 403 | 停用确认去掉数字；API 密钥 / 订阅行显示 `—`（vendor 隐藏） |
| ops 关闭 | 不显示横幅；两条错误行写“运维监控未开启” |
| 成员数为 0 | 见 2.3 |

#### 2.6 刷新策略

- 进入时全部加载；下拉刷新全部。
- 前台每 60 秒刷新：分组本身、成员、成员今日、容量、告警横幅、可用偏低；stats 与两个 24 小时计数只在进入、下拉、写操作后刷新。
- 最早恢复倒计时每秒本地递减；某个窗口到点后立即重拉成员与分组计数一次。
- 无 ETag、无 since_id。
- 写操作后：成员写入用响应 `counts` 先更新状态卡，再重拉成员、成员今日、容量；改名后同步更新分组目录缓存，账号详情等处随之显示新名称。

#### 2.7 对现有代码的改动点

- `GroupsView.swift:GroupDetailView` → 重写：去掉“分组信息 / 账号与容量 / 用量 / 管理”四个 LabeledValue 分区，改为 横幅 + 状态卡 + 按钮行 + 四个编号分区；`NavigationLink("查看与管理分组账号") { AccountsView(initialGroupID:) }` 删除（成员直接在本页）；`NavigationLink("统计分析")` 删除（设计稿没有）；`NavigationLink("请求记录")` 改为“记录与关联”里的三行。
- 保留并复用：`refresh()` / `refreshCapacity()` 的 `readTicket`、`sessionGeneration` 防串号写法；`perform(_:)` / `reconcile()` 的“结果待确认”流程（停用、删除沿用）；`groupWriteDefinitelyRejected`。
- 文案改动：状态“启用” → “正常”；“计费倍率” → “费率倍数”；“按量 / 订阅” → “标准（余额）/ 订阅（配额）”；“RPM 限额” → “每用户 RPM”。
- `GroupManagement.swift:AdminGroup` 增加 `errorAccountCount`、`idleAccountCount`（`Int?`，nil = 老服务端）、`sortOrder`、`claudeCodeOnly`、`fallbackGroupID`；`GroupCapacitySummary` 不变。
- `GroupManagement.swift:APIClient.groupCapacities()` 增加 `groupCapacities(groupIDs:)`（有 `groups.capacity_filter` 时带 `group_id`，否则全量本地过滤）。
- 新增 `APIClient.groupStats(id:) -> GroupStats?`（无 `subscriptions_total` 键时返回 nil 走退路）、`groupTodayUsage(id:serverTimezone:)`（dashboard/groups）、`accountTodayStats(ids:groupID:)`（扩展 `APIClient.accountTodayStats(ids:)`，回传 `failed_account_ids` 与回显的 `group_id`）、`firingAlerts(groupID:)`（可与监控章节共用）。
- 新增 `NativeApp/Features/Groups/GroupDetailView.swift`；成员行复用账号章节的 `AccountRow`（需支持 `omit/home` 参数）；容量条复用账号详情的容量组件。
- `Tests/Sub2CoreTests/GroupManagementTests.swift` 补：新字段解码（含键缺失）、四桶推导与退路、健康判定、`groupStats` 老服务端识别。

---

### 3. 编辑 / 新建分组（`sheet:groupEdit`）

#### 3.1 入口与导航

- 新建：列表右上 +；`{kind:'groupEdit', isNew:true}`。
- 编辑：列表左滑“编辑”、长按 / ⋯“编辑分组”、详情按钮行“编辑分组”、配置区可编辑项。
- sheet 内两页：表单页 ↔ “添加账号”页（同一 sheet 内导航，左上“新建分组 / 编辑分组”返回）。
- 左上“取消”；右上“创建” / “保存”（未改动或不合法时置灰）。

#### 3.2 数据来源

| 用途 | 来源 |
|---|---|
| 初值 | 编辑：详情已有的 `dto.AdminGroup` 与成员列表；新建：默认值（下表） |
| 平台下拉（仅新建） | `meta.catalog` 的 `platform_catalog.platforms[]`（去掉 `composite`）；无能力时内置表 |
| 同名检查 | 列表缓存里的 `name`（精确比较，排除自己）；最终以服务端 409 `GROUP_EXISTS` 为准 |
| 添加账号页 | 同 4.2 |
| 写入 | 新建 `POST /admin/groups`；编辑 `PUT /admin/groups/:id`；成员 0.4 |

新建默认值（与 Web createForm 一致，DECISIONS“新建分组默认 正常 + 公开”）：名称空、描述空、平台 `anthropic`、状态正常（POST 没有 status 字段，后端总是建成 active）、公开、费率倍数 1.0、标准（余额）、每用户 RPM 0（不限）、订阅限额空、不限 Claude Code。

#### 3.3 字段 → 显示映射（表单）

**基本**

| 控件 | 字段 | 规则 | 备注 |
|---|---|---|---|
| 名称 | `name` | 必填，去首尾空白后 1–100 字符；同名时下方红字“已有同名分组。” | vendor 无 `group_ops` 时只读 |
| 描述 | `description` | 可选 | 同上 |
| 平台 | `platform` | 新建：菜单式 Picker；改平台时清空已选成员。编辑：只读文字 | 后端允许 PUT 改平台，App 与 Web 一样不提供 |
| 状态 | `status` | 新建：只读“正常”；编辑：开关“正常 / 停用” | 简易模式隐藏 |
| 专属分组 | `is_exclusive` | 开关“专属 / 公开” | |
| 基本区脚注 | — | `专属：只有分配了这个分组的用户能选它。` 或 `公开：所有用户新建 API 密钥时都能选它。`；新建追加 `创建后立即可用，需要时可在详情里停用。平台和计费类型创建后不能修改；组合路由（Composite）分组在 Web 中创建。`；编辑且选了停用追加 `停用：使用这个分组的 API 密钥会被拒绝。` | |

**计费**（简易模式整区隐藏）

| 控件 | 字段 | 规则 |
|---|---|---|
| 费率倍数 | `rate_multiplier` | 步进器 ±0.1，最小 0.1，也可直接输入；必须是有限数且 > 0（后端 ≤0 会报无 reason 的错误，App 先拦） |
| 计费类型 | `subscription_type` | 新建：分段“标准（余额）/ 订阅（配额）”；编辑：只读并注“创建后不能修改” |
| 每用户 RPM | `rpm_limit` | 只允许数字；留空 = 0 = 不限；上限 2147483647 |
| 脚注 | — | `费率倍数：1.0 = 标准费率，0.5 = 半价，2.0 = 双倍。每用户 RPM：每位用户在本分组每分钟最多请求数，留空或 0 = 不限。` |

vendor 无 `group_billing` 或 `billing_locked=true` 时费率倍数与限额只读，脚注换成“计费由站长管理。”

**订阅限额 · 每个订阅**（仅订阅计费）

| 控件 | 字段 | 规则 |
|---|---|---|
| 每日 / 每周 / 每月限额 | `daily_limit_usd` / `weekly_limit_usd` / `monthly_limit_usd` | 金额输入，留空 = 无限制（编辑时由有值改为空，发 JSON `null`，后端转为不限）；有值才显示“$”前缀 |
| 脚注 | — | `留空 = 无限制；超过限额的订阅请求会被拒绝。` |

标准计费时这一区换成一行说明 `标准（余额）计费从用户余额扣除，没有订阅限额。`

**成员账号 N**（简易模式下组合分组、vendor 时隐藏整区）

| 元素 | 规则 |
|---|---|
| 成员行 | 左侧“−”移出、状态图形、名称；右侧：本次新加入的标“新加入”，正常的写“可调度”，其余为状态徽章（带倒计时） |
| 将移出 | 有被移出的成员时一行 `将移出：A、B` |
| 添加行 | `添加 <平台> 账号…` → 添加账号页 |
| 脚注（新建、未选成员） | 公开时 `公开分组没有可用账号时，选它的请求会失败。` + `可以现在添加，也可以创建后在详情里添加。` |
| 脚注（其余） | `创建后可用 x / n` 或 `保存后可用 x / n（现在 y）`；x 为 0 且分组正常时红字。x = 成员中当前可调度（账号主状态 available）且平台匹配的个数 |

底部说明：`模型白名单、组合路由、图片计费、客户端限制在 Web 中编辑。`

#### 3.4 交互与写操作

**新建（“创建”）**

1. 若分组公开、正常且创建后可用为 0：确认框 `创建公开分组「名称」？`，正文 `站点 <站点名> · <平台> · 费率倍数 ×1.0`、`创建后所有用户新建 API 密钥时都能选它，但现在没有可用账号，选它的请求会失败。`，按钮“仍然创建” / 取消。其余直接执行。
2. `POST /admin/groups`，body：`name`、`description`、`platform`、`rate_multiplier`、`is_exclusive`、`subscription_type`、`rpm_limit`，订阅计费时加三档限额（空的发 `null`）。带 `Idempotency-Key`（scope `admin.groups.create`，同一份已准备好的请求重试复用同一 key）。
3. 有选中成员时，用返回的 `id` 调 0.4 `add`。
4. 关闭 sheet，回执：`已创建「名称」`，有成员时后缀 0.4.3 的成员文案；部分失败带“查看”。列表、目录刷新。

**编辑（“保存”）**

1. 只提交改动过的字段（沿用现有 `GroupUpdateRequest` 的“nil = 不改”写法）；永不提交 `platform`、`subscription_type`。
2. 需要确认的情况：倍率、RPM、专属、任一限额或停用有变化，或保存后可用将从 >0 变为 0。确认框：标题 `保存「新名称」的修改？`；正文逐行：`站点 <站点名> · 分组「原名称」`、各项变化（`名称 A → B`、`描述已修改`、`费率倍数 ×0.8 → ×0.9`、`每用户 RPM 不限 → 60`、`每日限额 无限制 → $20`、`公开 → 专属：之后只有分配了这个分组的用户能选它` / `专属 → 公开：之后所有用户新建 API 密钥时都能选它`、`停用分组（N 个 API 密钥会被拒绝）`）、成员行 `成员：加入 2 个 · 移出 1 个`、倍率变化时 `此后的请求按新倍率计费，已产生的记录不变。`、可用归零时 `保存后这个分组没有可用的账号，新请求会失败。`。按钮：可用归零时“仍然保存”（destructive），否则“保存修改”；取消。只改名称、描述、成员且不归零时直接执行。
3. 先 `PUT /admin/groups/:id`（有字段改动时；带 `Idempotency-Key`，scope `admin.groups.update`），成功后再发 0.4 成员写入（有成员改动时）。PUT 失败就停下，sheet 保持打开显示错误，不发成员写入。
4. 回执：`已保存「名称」`，后缀成员文案；部分失败带“查看”。详情、列表、目录刷新。
5. vendor：PUT 成功后用响应对比提交字段（现有 `GroupUpdateRequest.matches`），有字段被服务端丢弃时回执改为 `已保存「名称」 · 部分字段无权修改，未生效`。

**取消 / 下滑关闭**：有未保存改动时询问“放弃修改？”。写入进行中禁止关闭（沿用 `interactiveDismissDisabled(busy || uncertain)`）。

#### 3.5 状态

| 状态 | 显示 |
|---|---|
| 校验不通过 | 右上按钮置灰；名称同名红字；倍率非法时字段红框 |
| 提交中 | 右上按钮换转圈，表单禁用 |
| 409 `GROUP_EXISTS` | 名称下红字，保持打开 |
| 其他明确失败（400 / 403 / 404 / 422） | 表单底部红字 message，可修改后重试（新的 key） |
| 不确定（超时、5xx、断网） | 沿用现有“结果待确认”：不自动重发；“读取服务器状态核对”——编辑按字段比对，新建按名称精确搜 `GET /admin/groups?search=<名称>&platform=<平台>`；有 `admin.idempotent_writes` 时先用同一 key 重发一次拿回结果 |
| 成员写入失败 | 不阻塞分组本身的成功回执，按 0.4.3 |

#### 3.6 刷新策略

不轮询。打开时用调用方已有数据；切到添加账号页时按 4.6 拉账号。

#### 3.7 对现有代码的改动点

- `GroupsView.swift:GroupEditorView` → 改写为 `GroupEditSheet`：去掉“目标站点”分区（站点写进确认框第一行）；编辑时平台、计费类型只读（现在可改计费类型，要改）；加状态开关（仅编辑）；费率倍数改为步进器；加“成员账号”区与 sheet 内的添加账号页；按钮从“核对并确认”改为右上“创建 / 保存”，确认框内容按 3.4。
- 保留：`prepare()` / `send()` / `reconcile()` 的待确认流程、`limitChange(_:previous:)`、`decimal(_:label:)`、`isCurrent` 会话检查、`onChange(of: model.sessionGeneration)` 关闭。
- `GroupManagement.swift:GroupCreateRequest` 默认 `platform` 由 `"openai"` 改为 `"anthropic"`。
- `GroupManagement.swift:GroupPlatform.values` 拆出 `concrete`（不含 `composite`）给新建 Picker 用；`title(_:)` 保留。
- `APIClient.createGroup/updateGroup/deleteGroup` 增加 `idempotencyKey: UUID` 参数并写 `Idempotency-Key` 头（参照 `APIClient` 余额写入的写法）；`PreparedGroupWrite` 里保存这个 UUID，重试复用。
- 新增 `Sources/Sub2Core/GroupMembers.swift`：`GroupMemberBatchRequest`（≤200 拆批）、`GroupMemberBatchResult` 解码、`receiptText(...)`、`inverse(of:)`（撤销请求）、0.4.4 退路执行器；配单测。
- `GroupPresentation.swift` 增加 `diffLines(old:new:)`（确认框逐行文案）与 `availableAfter(members:platform:)`。

---

### 4. 添加账号（`sheet:groupPick`，也作为 groupEdit 内的子页）

#### 4.1 入口与导航

- 直接打开：列表右滑“添加账号”、长按 / ⋯“添加账号”、详情按钮行“添加账号”、成员区“添加 <平台> 账号”行。标题 `添加到「分组名」`，左上“取消”。
- 编辑 sheet 内：标题“添加账号”，左上返回“新建分组 / 编辑分组”，右上“添加 N”（只把选中账号加入草稿，不提交）。

#### 4.2 数据来源

| 用途 | 接口 | 参数 |
|---|---|---|
| 候选账号 | `GET /admin/accounts` | `platform=<分组平台>&lite=1&sort_by=urgency&page=1&page_size=200`（组合分组不带 `platform`）；输入搜索时追加 `search=<词>`（防抖 300ms，服务端截到 100 字节） |
| 组名显示 | 分组目录缓存（`groups/all?include_inactive=true`） | 把账号 `group_ids` 换成名称 |

排除当前成员（`group_ids` 含本组 id 的账号；编辑 sheet 内排除草稿里的成员）。

#### 4.3 字段 → 显示映射

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 搜索框 | — | `搜索 <平台> 账号` | — |
| 分组标题 | — | `<平台> 账号` | — |
| 排序 | 可调度在前，其次暂停 / 停用，其余（错误、限时）最后；同档按服务端顺序 | — | — |
| 行首 | 选中状态 | 圆形选择环，选中后打勾（accent） | — |
| 第一行 | `name`；主状态（账号章节判定，同 D02 state） | 可调度写“可调度”（ok 色），其余为状态徽章（限时状态带倒计时） | — |
| 第二行 | 停调度标记、`type`、`group_ids` | `已停止调度 · OAuth · 已在 高级组、Claude Code 组`；没有分组写“未分组” | — |
| 空态 | 平台下没有账号 / 全都已在组里 / 搜索无结果 | `还没有 <平台> 账号` / `<平台> 账号都已在这个分组里` / `没有匹配的账号` | — |
| 底部说明 | — | `只列出 <平台> 账号：其他平台的账号不会被这个分组调度。个别账号失败不影响其他账号。`（组合分组：`组合分组可以加入任意具体平台的账号。`） | — |
| 底部坞（直接打开时） | 选中数 k；加入后可用 = 当前 `active_account_count` + 选中里可调度的个数 | 未选：`选择要加入的账号`；已选：`加入后可用 2 → 3 / 4` + 按钮 `加入 k 个账号` | 未选时按钮置灰 |

#### 4.4 交互与写操作

- 点行切换选中。
- 直接打开时点“加入 k 个账号”：0.4 `add`（不带 priority）；关闭 sheet；回执按 0.4.3（全部成功带撤销，部分失败带查看）。
- 结果里有 `MIXED_CHANNEL_RISK` 时，回执“查看”进 5，在结果页确认后带 `confirm_mixed_channel_risk=true` 重试。
- 编辑 sheet 内点“添加 N”：只并入草稿，回到表单页。

#### 4.5 状态

| 状态 | 显示 |
|---|---|
| 加载中 | 列表骨架 |
| 加载失败 | “账号加载失败 · 重试” |
| 提交中 | 按钮转圈，禁止关闭 |
| 请求级失败 | 0.8“网络错误 / 超时（成员写入）” |

#### 4.6 刷新策略

打开时加载一次；搜索变化重新请求；不轮询；不下拉刷新（sheet 内）。

#### 4.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupAccountPicker.swift`（直接打开与 sheet 内子页共用一个视图，用参数区分“提交”与“并入草稿”）。
- 账号列表请求复用 `APIClient.accounts(page:search:status:platform:...)`（`Sources/Sub2Core/APIClient.swift:136-139`），需要补 `lite`、`sort_by` 参数（账号章节同样需要）。
- 状态徽章、停调度标记复用账号章节组件。

---

### 5. 成员批量写入逐项结果（`screen:groupBatch`）

#### 5.1 入口与导航

- 进入：任一成员写入回执里的“查看”（只有存在失败项时才出现）。route 携带 `{id, name, items}`，items 来自 0.4.2 的 `results`（加上 App 自己记的账号名）。
- 去向：点行 → 账号详情；返回 → 上一页。

#### 5.2 数据来源

不额外请求。重试与撤销调 0.4 接口。账号名、状态取 App 账号缓存；缓存里没有时用提交时记下的名称，状态显示“停用”图形。

#### 5.3 字段 → 显示映射

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 导航 | 分组名、项数 | `逐项结果`，副标题 `高级组 · 3 个账号` | — |
| 状态卡（有失败） | 失败数 f、成功数 s | caution 状态胶囊；大徽章 `f 个失败`，右侧 `s 个成功`；说明 `失败的账号没有改动，可以直接重试，或点开账号单独处理。` | — |
| 状态卡（无失败） | — | 安静卡：`全部完成 · 已加入 2 个账号`；全部撤销后 `已全部撤销` | — |
| 按钮行 | — | `重试 n 个`（主，n = 可重试的失败数）· `撤销成功的 s 个` | n=0 / s=0 时不显示对应按钮 |
| 壹 · 失败 | `status=failed` 的项 | meta `f 个 · 没有改动`；行：状态图形 + 名称，右侧 critical 徽章 `加入失败` / `移出失败`；第二行原因 | — |
| 失败原因 | `reason` | `ACCOUNT_NOT_FOUND` → `账号不存在或已删除`（不可重试）；`MIXED_CHANNEL_RISK` → `分组里已有 <other_platform> 账号，与 <current_platform> 账号混用有风险`（可重试，需确认）；请求级失败 → `请求没有送达，账号没有改动`（可重试） | 其他 reason 显示 `message` |
| 贰 · 成功 | added / removed / unchanged / 已撤销 | meta `s 个`；右侧 `已加入` / `已移出` / `重试后已加入` / `无需改动` / `已撤销`（变淡） | — |

#### 5.4 交互与写操作

- “重试 n 个”：可重试项分两类发送：
  - 请求级失败的项：原样重发（幂等）。
  - `MIXED_CHANNEL_RISK` 的项：先确认 `仍然加入混合渠道账号？`，正文 `分组里已有 <other> 账号。同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。`（据 `service/admin_account.go:1928-1931` 的错误说明），按钮“仍然加入” / 取消；确认后带 `confirm_mixed_channel_risk=true`。
  - 成功的项改到“成功”区并标“重试后已加入 / 已移出”；回执 `重试成功 · 已加入 n 个账号`。
- “撤销成功的 s 个”：0.4.3 的反向请求；成功项标“已撤销”；回执 `已撤销 s 个账号的改动`。
- 写入后刷新分组详情（返回时可见）。

#### 5.5 状态

重试 / 撤销进行中按钮转圈；请求级失败时状态卡下红字 `没有完成，请稍后重试`，项目状态不变。

#### 5.6 刷新策略

不轮询，不下拉刷新。

#### 5.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupBatchResultView.swift`；结果模型、原因文案、重试分组、反向请求放在 `Sources/Sub2Core/GroupMembers.swift`。
- 现有代码没有对应页面。

---

### 6. 分组 API 密钥（`screen:groupKeys`）

#### 6.1 入口与导航

- 进入：详情“记录与关联 → API 密钥”。vendor、简易模式不提供（后端 403）。
- 去向：点行 → 所属用户详情（用户章节）；换分组、重置速率限制都在用户的 Key 卡片里做。

#### 6.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| Key 列表 | `GET /admin/groups/:id/api-keys` | `page=<n>&page_size=20&key_view=masked` | 分页；排序为 id 倒序（handler 不传排序，`repository/api_key_repo.go:651-695` 默认 id desc）；每项 `dto.APIKey` 含 `user`；E11 起回填 `current_concurrency` |
| 今日实际扣费 | `POST /admin/dashboard/api-keys-usage` | `{"api_key_ids":[本页 id]}` | `data.stats` 以 Key id 字符串为键，取 `today_actual_cost`；“今日”为服务器时区（E09） |

#### 6.3 字段 → 显示映射

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 导航 | 分组名、`total` | `API 密钥`，副标题 `高级组 · 共 38 个` | — |
| 列表头 | — | 左 `新建的在前`，右 `所属用户 · 最近使用 · 今日` | — |
| 行首 | — | 钥匙图标 | — |
| 第一行左 | `name` + 状态徽章 | `effective_status`：inactive → 已停用、quota_exhausted → 额度耗尽（caution）、expired → 已过期；active 不显示徽章 | 没有 E06 时用 `AdminAPIKeyStatus` 在本地推导（见 0.1） |
| 第一行右 | `key_masked` | 等宽字体 | 缺失时本地拼掩码；**不显示、不缓存明文 `key`** |
| 第二行左 | `user.username`（空时用 `user.email`）+ 用户禁用标记 + `last_used_at` | `Nova 工作室 · 09:38`；`user.status=disabled` 时名称后加 `（已禁用）`；今天写 HH:mm，更早写 MM-DD | 无 user 时 `用户 #<user_id>`；`last_used_at=null` → `从未使用` |
| 第二行右 | `today_actual_cost` | `今日 $12.40` | 用量请求失败 `今日 —` |
| 第三行（仅 `quota > 0`） | `quota_used` / `quota` | `额度` + 金额容量条 | — |
| 状态胶囊 | 额度耗尽 → caution | — | 其余不画 |
| 已停用 / 已过期 | — | 整行变淡 | — |
| 翻页提示 | 已显示 / `total` | `已显示 10 / 38 个 · 滚动到底继续加载` | 全部显示后不显示 |
| 空态 | `total=0` | `—` + `还没有 API 密钥使用这个分组` | — |
| 底注 | — | `点按进入所属用户。给 Key 换分组、重置速率限制在用户的 Key 里操作。` | — |

简易模式（`run_mode=simple`）不会进入本页；如果以后放开，`expired` / `quota_exhausted` 的 Key 在简易模式下照常可用（E06 审查修正），徽章应隐藏。

#### 6.4 交互与写操作

只读。点行进入用户详情。

#### 6.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 骨架行 |
| 列表失败 | 错误态 + 重试；翻页失败在底部“加载失败 · 重试” |
| 用量失败 | 今日 `—`，不报错 |
| 400 `Invalid key_view, use full/masked` | 这是 App 自己的参数错误：只有 App 发了 full / masked 以外的值，新服务端才会这样回（`handler/admin/api_key_view.go:13-23`）。老服务端不认 `key_view`，会忽略它并回明文，这种情况按 0.1 的退路处理。遇到这个 400：写日志，界面按“列表失败”处理，不重试 |

#### 6.6 刷新策略

进入时加载第一页；滚到底加载下一页（每页拉到后补拉这一页的今日用量，每批 ≤ 200 个 id）；下拉刷新回到第一页；不轮询。

#### 6.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupKeysView.swift`。
- 新增 `APIClient.groupAPIKeys(id:page:) -> Page<AdminAPIKey>`（Key 模型与用户章节共用，需含 `key_masked`、`effective_status`、`quota`、`quota_used`、`expires_at`、`last_used_at`、`user`；解码时丢弃 `key`；状态徽章用 30 章的 `AdminAPIKeyStatus`，本章不另写映射）与 `apiKeysTodayUsage(ids:) -> [Int: Decimal]`（用户章节同样需要）。
- 现有代码没有对应页面。

---

### 7. 分组订阅（`screen:groupSubs`）

#### 7.1 入口与导航

- 进入：详情“记录与关联 → 订阅”（只对订阅计费分组显示）。vendor、简易模式不提供。
- 去向：点行 → 用户详情；调整有效期、重置配额、撤销在 Web 订阅管理里做。

#### 7.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| 订阅列表 | `GET /admin/groups/:id/subscriptions` | `page=<n>&page_size=20` | 按 `created_at` 倒序（`repository/user_subscription_repo.go:215-236`），带 `user`；返回前已把过期窗口清零、已到期的 active 改为 expired（`service/subscription_service.go:811-823,866-874`）；已撤销的是软删除，不会出现 |
| 生效数 | 详情已拿到的 stats `subscriptions_active` | — | 退路 `GET /admin/subscriptions?group_id=<id>&status=active&page_size=1` 的 `total` |
| 每订阅限额 | 分组的 `daily/weekly/monthly_limit_usd` | — | 详情已有 |

#### 7.3 字段 → 显示映射

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 导航 | 分组名、生效数 | `订阅`，副标题 `企业专线 · 生效中 12 个` | 生效数不可用时只写分组名 |
| 页头 | 三档限额 | `每个订阅的限额  每日 $20  每周 $100  每月 $300` | null → 无限制 |
| 列表头 | — | 左 `新分配的在前`，右 `用量 · 到期` | — |
| 行首 | `user.username` 首字 | 圆形头像 | 无 user 时 `?` |
| 第一行左 | `user.username` | — | 空时用 `user.email`；无 user 时 `用户 #<user_id>` |
| 第一行右 | `status`、`expires_at` | active：剩余天数 `剩余 4 天` / `今天到期`（≤ 7 天 caution 色）；suspended → 徽章“已暂停”；expired → 徽章“已过期” | — |
| 用量（仅 active） | `daily_usage_usd` / `weekly_usage_usd` / `monthly_usage_usd` 对分组三档限额 | 三列：标签、`$18.60 / $100`、细进度条（≥ 75% caution，≥ 90% critical）；限额 null 时只写用量与“无限制” | — |
| 第二行 | `expires_at`、`user.email` | active / suspended：`至 2026-10-20 · lin@…`；expired：`2026-10-09 已到期 · …` | — |
| 状态胶囊 | active 且剩余 ≤ 7 天 → caution | — | — |
| 非生效行 | suspended / expired | 整行变淡，不显示用量 | — |
| 翻页提示 | 已显示 / `total` | `已显示 4 / 15 条 · 滚动到底继续加载` | — |
| 空态 | `total=0` | `—` + `这个分组还没有订阅` | — |
| 底注 | — | `点按进入用户。调整有效期、重置配额、撤销在 Web 订阅管理中操作。` | — |

剩余天数：服务器时区下“今天”到 `expires_at` 所在日期的整天数；0 写“今天到期”。

#### 7.4 交互与写操作

只读。点行进入用户详情。

#### 7.5 状态

同 6.5（没有用量子请求）。

#### 7.6 刷新策略

进入时加载第一页；滚到底翻页；下拉刷新；不轮询。

#### 7.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupSubscriptionsView.swift`。
- 新增 `APIClient.groupSubscriptions(id:page:) -> Page<AdminUserSubscription>`（模型字段：`id`、`user_id`、`group_id`、`starts_at`、`expires_at`、`status`、`daily_usage_usd`、`weekly_usage_usd`、`monthly_usage_usd`、`user`；与用户章节的订阅模型共用）与 `activeSubscriptionCount(groupID:)`（退路）。
- 现有代码没有对应页面。

---

### 8. 首页下钻：分组内账号（`vtGroupAccounts`）

#### 8.1 入口与导航

设计稿的路由规则（`v-today.jsx:195-197`，`vtGroupRoute`）：有分组详情页时进分组详情 `{kind:'group', id}`，没有时才进 `vtGroupAccounts`。最终 App 有分组详情，所以本页不作为主入口。实际进分组的入口只有两个：

- 首页“可用不足 N 个分组”行（10 章 §1.1）：N = 1 时直接用该行的 `group_id` push 分组详情（第 2 节）；N > 1 时推入分组列表并选中“需处理”段（第 1 节）。
- 告警详情范围区的分组行（10 章 §3.1、§3.3）：用事件的 `dimensions.group_id` push 分组详情。分组已删除（事件仍有 `group_name`，但 availability 里没有这个分组）时，这一行显示“分组已删除”且不可点（10 章 §3.3）。
- 进入详情后才发现分组已删（`GET /admin/groups/:id` 返回 404），显示 2.5 的“这个分组已删除”整页空态，不进本页。

已定首页的待处理是合并粒度（DECISIONS 第 2 轮 Q3），没有分组卡；平静布局也没有“其他分组”行（那是未选的 homePend `group` 变体，`v-today.jsx:411` 的 `vtGroupItems`）。若要在分组详情上线前先出过渡版本，按下面的规格用账号列表加分组筛选实现。

#### 8.2 数据来源（过渡版本）

`GET /admin/accounts?group=<id>&lite=1&sort_by=urgency&include_counts=1&page=1&page_size=100`；需处理数 = `data.counts.needs_attention`，全部 = `data.counts.all`（C14；无该能力时本地数 错误 + 限时状态）。

#### 8.3 字段 → 显示映射（过渡版本）

| 元素 | 内容 |
|---|---|
| 导航 | 标题为分组名（移除分组筛选后为“账号”）；副标题 `<站点名> · n 个 · a 个可用` |
| 筛选胶囊 | `分组：<名称> ✕`（可移除）、`需处理 n`（有需处理时用警示样式）、`全部 n` |
| 行 | 账号章节三行行；有分组筛选时 `omit: group`、`home: <名称>` |
| 空态 | `没有需要处理的账号` |

#### 8.4 交互、8.5 状态、8.6 刷新

同账号 Tab 列表（账号章节）。

#### 8.7 对现有代码的改动点

- 过渡版本直接复用 `NativeApp/Features/AccountsView.swift:AccountsView(initialGroupID:)`（已支持初始分组筛选，`AccountsView.swift:61-62`），补“需处理 / 全部”胶囊。
- 最终版本：首页“可用不足 N 个分组”行与告警范围区分组行按 8.1 路由到分组详情 / 分组列表；不新增本页文件。

---

### 9. 本章新增 / 改动文件汇总

| 文件 | 动作 |
|---|---|
| `Sources/Sub2Core/GroupManagement.swift` | 扩展 `AdminGroup` 字段；新增 `GroupUsageSummary`、`GroupStats`；新增 `groupList(etag:)`、`allGroups(includeInactive:)`、`groupUsageSummary()`、`groupCapacities(groupIDs:)`、`groupStats(id:)`、`groupTodayUsage(id:serverTimezone:)`、`duplicateGroup(id:idempotencyKey:)`、`groupAPIKeys(id:page:)`、`groupSubscriptions(id:page:)`；写接口加 `Idempotency-Key`；`GroupPlatform.concrete` |
| `Sources/Sub2Core/GroupMembers.swift`（新） | 成员批量请求 / 结果 / 回执文案 / 撤销 / 老服务端退路 |
| `Sources/Sub2Core/GroupPresentation.swift`（新） | 健康判定、四桶与退路、色格分段、格式化、确认框文案、删除后果行 |
| `NativeApp/Features/GroupsView.swift` | 拆分后删除，内容迁到 `NativeApp/Features/Groups/` |
| `NativeApp/Features/Groups/GroupListView.swift`、`GroupDetailView.swift`、`GroupEditSheet.swift`、`GroupAccountPicker.swift`、`GroupBatchResultView.swift`、`GroupKeysView.swift`、`GroupSubscriptionsView.swift`、`GroupCellsView.swift`、`GroupStore.swift`（新） | 各页面 |
| `Tests/Sub2CoreTests/GroupManagementTests.swift` 与新增 `GroupMembersTests.swift`、`GroupPresentationTests.swift` | 解码（含字段缺失）、F04 退路、健康判定、拆批、回执文案、反向请求、删除后果行 |
| `scripts/generate_project.py` | 新增文件后运行，重新生成 `Sub2Mobile.xcodeproj` |

QA 对账（可写成单测）：同一分组 `active + rate_limited + error + idle = account_count`；F04 与 D02 满足 0.2 的公式（除到期自动暂停的过渡账号）；分组详情“今日”= 列表同组“今日”；成员“今日”（分组口径）之和 ≤ 分组今日。

---

### 本章未决问题

1. **vendor 能否在分组页加减成员。** 后端 `POST /admin/groups/:id/accounts/batch` 对 vendor 一律 403（vendor 白名单只放行 `/admin/groups` 的 GET、PUT、PATCH），而 vendor 有账号管理权限时可以用 `PUT /admin/accounts/:id` 改 `group_ids`（F01 的逐账号退路）。设计稿只按站长设计。
   建议默认：vendor 视角隐藏分组页的所有成员写入口（添加账号、移出、编辑 sheet 的成员区），成员分区底部注“调整成员请在账号详情里修改分组”；需要时再给 vendor 开逐账号退路，或请后端对有账号管理档的 vendor 开放批量接口。

2. **成员行“今日”的口径。** 设计稿用账号全站今日并加脚注（当时后端不能按分组统计）；C17 上线后 `today-stats/batch` 可以只算本分组，`BACKEND-API-CHANGES.md` 的 C17 正是为这个页面做的。
   建议默认：有 `accounts.today_stats_group` 时用分组口径（成员今日之和与分组今日对得上），脚注写“只算这个分组的请求”；没有时退回全站口径并用设计稿原脚注。

3. **停用确认里的 Key 数用哪个数。** 设计稿用分组绑定的 Key 总数；但“会被拒绝”只对原本可用的 Key 有意义，`groups/:id/stats` 同时给了 `total_api_keys` 与 `active_api_keys`。
   建议默认：停用确认用 `active_api_keys`；详情“API 密钥 N 个”与删除确认用 `total_api_keys`（与 API 密钥页 `total` 一致）。

---

## 60 · 搜索目录与其他模块

> 本章覆盖：搜索 Tab（目录首屏 `SearchHome`、全局搜索结果与“查看全部”结果页）；设置（界面模式、外观、安全与 Face ID 覆盖清单、通知、站点与凭据，含添加站点 / 登录页布局、登录设备 A07、管理访问令牌 A08、推送通知 A11）；兑换码（`redeem` 行内展开、`redeemDetail` 深链定位、编辑 `redeemEdit`、批量生成 `redeemGenerate`、待核对 `redeemReconcile`、发放兑换码（补偿）`redeemGrant`，见第 19 节）；代理（`proxies`、`proxyDetail`、被改走的账号、`proxyEdit`）；公告（`announcements`、`announcementDetail`、`announcementEdit`、`announcementReads`）。
>
> 登录流程、验证码桥页、凭据存储、退出顺序、推送协议（注册参数、载荷、深链）以 `00-conventions.md` 为准（§1.3–§1.9、§7），本章只写这些页面的布局与本章特有的行为，不另写一套文案。
>
> 依据：`DECISIONS.md`（第 2 轮“设置入口在搜索目录”“搜索首屏目录”“兑换码、代理、公告都能管理”“删除藏 ··· 最后”“高风险验证”；第 3 轮 Q9–Q12 以更正为准：兑换码 = 行内展开 + 编辑 sheet，代理 / 公告 = 列表 + 详情 + 编辑 sheet，批量生成 = 分步向导）；设计稿 `html-preview/layouts/main/00-core.jsx`（`SearchHome`、`SettingsScreen`、`confirmDelete`）、`v-modules.jsx`（已定变体见 `v-decided.jsx`）、`tools/routes/modules.json`、`core.json`、`zz-cross.json`；后端 sub2 `main` `70116315d`（A02、A04、A07、A08、A09、A11、E02、G01、G03–G08、H01–H08 均已上线，口径以 `BACKEND-API-CHANGES.md` 实现进度表备注为准）；`sub2/docs/API_ERROR_CODES.md`。
>
> 下文接口路径都相对 `/api/v1`，字段名逐个对过后端源码；“后端位置”路径相对 `sub2/backend/internal/`。金额、紧凑数、相对时间格式沿用 10 章 0.4（`DashboardPresentation` 新增函数）；“今天 / 昨天”的日界按服务器时区（10 章 0.3）。
>
> 设计稿里没选中的变体（兑换码 base 列表 + 详情页、批量生成单页表单、代理 / 公告 inline 卡片）不实现。

---

### 0. 本章共用口径

#### 0.1 路由（本章新增的 `NavigationStack` 目的地与 sheet）

| 页面 | 路由 | 从哪进 | 设计稿 |
|---|---|---|---|
| 搜索目录 | 搜索 Tab 根视图 | Tab 栏右侧独立搜索按钮 | `SearchHome` |
| 全局搜索结果 | 搜索 Tab 根视图的搜索态 | 点目录顶部“搜索全部对象” | 设计稿只画了输入框，结果按附录 B L21 定 |
| 搜索结果 · 查看全部 | `.searchResults(kind: .accounts \| .users \| .groups \| .proxies, query: String)` | 全局搜索各分区底部“查看全部 N 个 ›” | 设计稿未画（2.1） |
| 设置 | `.settings(focus: .interface \| .sites)` | 目录“界面与模式”“站点与凭据” | `SettingsScreen` |
| 添加站点（登录） | sheet `.addSite`；无活动站点时为根视图 | 设置 → 添加站点 | 现有 `LoginView` |
| 登录设备 | `.sessions` | 设置 → 当前站点 | 设计稿未画（A07） |
| 管理访问令牌 | `.accessTokens` | 设置 → 当前站点 | 设计稿未画（A08） |
| 推送通知 | `.push` | 设置 → 通知 | 设计稿未画（A11） |
| 兑换码 | `.redeem(open: Int?, query: String?, status: String?, type: String?, reconcile: Bool)` | 目录；概览待处理；补偿回执“查看兑换码” | `screen:redeem` = `inline` |
| 兑换码定位（`redeemDetail`） | 统一落到 `.redeem(open: id)` | 深链 | 已定方案没有独立详情页（`vmoShowCode`） |
| 编辑兑换码 | sheet `.redeemEdit(id)` | 卡片按钮 / 滑动“续期” | `sheet:redeemEdit` |
| 生成兑换码 | sheet `.redeemGenerate` | 兑换码 `+` | `sheet:redeemGenerate` = `steps` |
| 核对结果 | sheet `.redeemReconcile(batchID)` | 待核对横幅“核对”、概览待处理 | `sheet:redeemReconcile` |
| 发放兑换码（补偿） | sheet `.redeemGrant(userID: Int64, pendingID: UUID?)` | 用户详情 ··· “发放兑换码（补偿）…”（30 章 §2.4）；设置 → 待核对 · 补偿发放；概览待处理（10 章） | `sheet:redeemGrant`（`v-modules.jsx` `VmoGrantSheet`） |
| 代理 | `.proxies(filter: String?)` | 目录 | `screen:proxies` = `base` |
| 代理详情 | `.proxyDetail(id)` | 代理行；账号详情的代理行；全局搜索 | `screen:proxyDetail` |
| 被改走的账号 | `.proxyFallbackAccounts(id)` | 代理详情 · 有效期分区 | 设计稿未画（H03） |
| 编辑 / 添加 / 续期代理 | sheet `.proxyEdit(id: Int?)` | 代理 `+`、详情按钮与 ··· | `sheet:proxyEdit` |
| 公告 | `.announcements(seg: String?)` | 目录 | `screen:announcements` = `base` |
| 公告详情 | `.announcementDetail(id)` | 公告行 | `screen:announcementDetail` |
| 已读情况 | `.announcementReads(id)` | 公告详情 · 投放 | `screen:announcementReads` |
| 编辑 / 新建公告 | sheet `.announcementEdit(id: Int?)` | 公告 compose、详情“编辑” | `sheet:announcementEdit` |

#### 0.2 用到的 capability（`GET /admin/me` → `data.server.capabilities`）

| capability | 后端条目 | 有它时 | 没有时（老服务端） |
|---|---|---|---|
| `redeem_codes.stats` | G08 | `GET /admin/redeem-codes/stats` 是真实计数；同时推断 G03（`batch_id`、`notes` 生成参数与列表过滤）、G04（`types` / `exclude_types`）已部署（G08 的过滤参数就是 G03 / G04 的参数，同一轮上线） | 状态胶囊不显示数字；“全部类型”不带 type、在客户端剔除 `admin_balance` / `admin_concurrency`；生成核对走 11.4 的老退路 |
| `redeem_codes.delete_guard` | G07 | 删除已兑换的码返回 409 `REDEEM_CODE_USED`；不存在返回 404 | App 照样不给已兑换的码“删除”（与 Web 一致），不依赖后端拦截 |
| `proxies.fallback_accounts` | H03 | 代理有 `fallback_account_count`；可列出并批量恢复被改走的账号 | 详情只写“要改回来，在账号详情里点‘恢复原代理’”，不提供批量恢复页 |
| `announcements.read_stats` | H06 | 列表 / 详情显示已读进度；已读名单可按已读 / 未读、是否符合条件筛选，可按阅读时间排序 | 只有“已读情况 ›”入口与按邮箱 / 用户名 / 余额排序的分页名单 |
| `announcements.idempotent_create` | H07 | 新建公告带 `Idempotency-Key`，超时可同 key 重发 | 照常带 key（老服务端忽略）；超时**不要**自动重发，按标题搜最近几条核对 |
| `admin.access_tokens` | A08 | 显示“管理访问令牌”入口（列表与吊销；首版不在 App 内签发，见第 6 节） | 隐藏入口 |
| `push.notifications` | A11 | 显示“推送通知”入口 | 隐藏入口 |
| `auth.captcha_provider` | A09 | 登录请求可带 `captcha_provider` / `aliyun_captcha_param` | 登录前看不到 admin/me，改用公开设置里**有没有 `captcha_provider` 键**判断（API_ERROR_CODES） |

没有 capability、靠响应判断的：A07 会话列表（`GET /auth/sessions` 返回 404 = 老服务端，隐藏“登录设备”）；H01（`latency_checked_at` 键是否存在）；H02（`GET /admin/proxies/:id` 有没有 `account_count` 键）；G03（生成响应头有没有 `X-Redeem-Batch-ID`）。

本章列表接口（兑换码、代理、公告、已读名单、会话、令牌、推送设备）后端都**没有 ETag**（B09 只做了 stats / users / groups），不发 `If-None-Match`。

#### 0.3 身份与权限

| 身份（`admin/me.auth_method`） | 本章差异 |
|---|---|
| `jwt`（邮箱 + 密码 + TOTP） | 全部可用；本章需要 step-up 的写操作只有改 APNs 配置（`PUT /admin/push/config`），站点开启二次验证时按 00 §2.6 弹 `StepUpView` |
| `admin_api_key` | 以第一个管理员身份操作（附录 B L3）；没有会话 → 隐藏“登录设备”；**站点开启二次验证（`security.step_up_enabled == true`）时**不能改 APNs 配置（403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`），关闭时可以改（step-up 中间件先看站点开关、开关关闭直接放行，之后才拒绝机器凭据，`server/middleware/step_up.go:100,104`）；推送设备登记在第一个管理员名下 |
| `admin_access_token`（`sat_…`） | 以签发人身份操作；APNs 配置同 Admin Key（开启二次验证时不能改）；**只读令牌**（`scope=read`）所有写方法返回 403 `ACCESS_TOKEN_READ_ONLY`，例外：撤销自己、推送设备的登记 / 删除 / 改订阅 / 测试（且只能登记 iOS），改 APNs 配置不在例外里（00 §2.6.3） |

**只读令牌的识别（全 App 通用，不只本章）**：`admin/me` 没有 scope 字段（`handler/admin/me_handler.go:185-193` 的 `meResponse`）。`auth_method == admin_access_token` 时，`AppModel.connect` 在 `admin/me` 之后紧接着调一次 `GET /admin/access-tokens`，取 `current == true` 那项的 `scope`，存进 00 §9.5 的 `SiteSession`（新增 `accessTokenScope: String?`）；全 App 的写按钮按 00 §1.6 第 3 条置灰（旁注“只读令牌”），各页面读 `session.isReadOnlyToken`，不各自请求。这次请求失败时按读写处理（服务端仍会用 `ACCESS_TOKEN_READ_ONLY` 拦下，App 按 00 §2.6.3 提示）。这条规则应收进 00 §1.6（合稿裁定见文末“审查未采纳的意见”R14）。

vendor（`admin/me.workspace != null`）是否允许登录 App 由通用约定章节决定；若允许，本章按下表隐藏（`server/middleware/vendor_routes.go:113-114` 注释：兑换码、公告、用户、运维为站长专属）：

| 模块 | vendor 可见条件（`workspace.permissions`） |
|---|---|
| 兑换码、公告、管理访问令牌、推送通知 | 一律不可见 |
| 代理（只读） | `proxy_manage` 或 `account_manage` |
| 代理写操作（新建、编辑、停用、测试、质量检测、删除） | `proxy_manage` |
| 恢复被改走的账号 | `proxy_manage` 且 `account_manage` |
| 登录设备 | 可见（`/auth/sessions` 对所有 JWT 开放） |
| 全局搜索各分区 | 见 2.2 |

#### 0.4 本章复用的交互规则

- **删除确认**（通用组件，设计稿 `confirmDelete`）：标题“删除<对象>「名称」？”，正文第一行“站点 X · 删除后不能恢复。”，第二行写后果；设置里关闭 Face ID 时要输入完整名称（兑换码输入末 4 位，大小写都算对）才能点红色“删除<对象>”；打开 Face ID 时不输入，按钮是“用 Face ID 删除”，点后系统验证。删除一律放 ··· 最后（或详情页最后一行）、红字，不放进滑动操作（推送接收方式也一样，见 7.4）。
- **Face ID 门槛**：覆盖范围以 3.4 的“Face ID 覆盖清单”为准（全 App 唯一来源）；打开后，确认后再验证（`LAPolicy.deviceOwnerAuthentication`，允许回退到锁屏密码）。
- **可逆操作**（启用 / 禁用兑换码、停用 / 启用代理、归档公告）：直接执行，回执 toast 带“撤销”（5 秒，撤销 = 把旧值写回去）。
- **敏感值**：兑换码、代理密码、sat_ 原文（登录时粘贴的）、推送 secret、APNs 私钥只放内存，不落盘、不进缓存、不写日志（凭据本身按 00 §1.1 存 Keychain；发放补偿的待核对记录按 19.4 例外保存 code）；复制用 `UIPasteboard.general.setItems(_:options:)` 带 `.localOnly: true`，代理 URL 另加 `.expirationDate` 120 秒。
- **幂等键**：UUID v4 小写；在用户确认那一刻生成，失败后“原样重试”沿用，改了请求体就换新 key；`IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` 按 `Retry-After` 等待后同 key 重试（规则与解码在通用约定章节）。
- **错误**：按 `reason` 分支（附录 B L1）；下文每页只列本页特有的 reason，401 / 423 / 429 / 网络错误走通用处理。

---

### 1. 搜索 Tab · 目录首屏

#### 1.1 入口与导航

- 底部 Tab 栏右侧独立的玻璃搜索按钮（`Tab(role: .search)`，四个主 Tab 为 概览 · 账号 · 用户 · 监控，Tab 结构由导航章节改）。搜索 Tab 自带 `NavigationStack`，根视图就是目录。
- 首屏是目录，**点搜索框才弹键盘**（DECISIONS 第 2 轮）：`.searchable(text:placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全部对象")` 挂在搜索 Tab 内部的根视图上（不挂在 `TabView` 上），`TabView` 设 `.tabViewSearchActivation(.automatic)`。iOS 27 上分离的搜索按钮可能并入 Tab 栏，须实机验证（见未决问题 1）。
- 导航栏：大标题“搜索”，副标题“账号、用户、请求 ID、Key 片段”。
- 目录项去向：

| 分组（序号） | 项 | 去向 |
|---|---|---|
| 壹 记录 | 使用记录 | 日志章节 `.logs(scope: .usage)` |
| | 错误请求 | 日志章节 `.logs(scope: .errors)` |
| | 告警事件 | 切到 监控 Tab 的“告警”分段（设计稿此项未接线，见未决问题 2） |
| 贰 资源 | 分组 | 50 章 `.groups` |
| | 统计分析 | 统计章节 `.analytics` |
| | 兑换码 | 第 8 节 |
| | 代理 | 第 12 节 |
| | 公告 | 第 15 节 |
| 叁 设置 | 界面与模式 | 第 3 节，`focus: .interface` |
| | 站点与凭据 | 第 3 节，`focus: .sites`（滚到“站点”分区） |
| 肆 在 Web 中打开 | 系统设置 | Safari 打开 `<站点>/admin/settings` |
| | 支付与套餐 | Safari 打开 `<站点>/admin/orders/dashboard` |

#### 1.2 数据来源

- 目录本身不调接口。
- 可见性读会话级缓存的 `GET /admin/me`：`features.payment_enabled`（“支付与套餐”）、`features.ops_monitoring_enabled`（错误请求、告警事件仍显示，进入后由各章节显示“运维监控未开启”）、`workspace.permissions`（vendor，见 0.3）。

#### 1.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 搜索框 | — | 占位“搜索全部对象” | — |
| 分组标题 | 固定 | “记录 / 资源 / 设置 / 在 Web 中打开”，右侧序号“壹 / 贰 / 叁 / 肆” | 某组全被隐藏时整组不显示，序号顺延 |
| 行 | 固定 | 左侧灰色图标 + 名称 + 右侧 chevron（设计稿图标：list、octagon、bell、group、chart、gift、shield、megaphone、sliders、key、web） | — |
| 支付与套餐 | `features.payment_enabled` | — | 为 false 时隐藏 |
| 兑换码、公告 | vendor | — | vendor 隐藏 |
| 代理 | vendor 的 `proxy_manage \|\| account_manage` | — | 都没有时隐藏 |

#### 1.4 交互与写操作

- 点行 push 对应页面；“在 Web 中打开”两项用 `openURL` 交给 Safari（复用 Safari 里的 Web 登录态，不用 `SFSafariViewController`）。
- 无写操作。

#### 1.5 状态

- `admin/me` 还没取到：先按站长身份显示全部项，取到后按权限收起；`admin/me` 失败不影响目录。

#### 1.6 刷新策略

无网络请求，不刷新。`admin/me` 的刷新由通用约定章节负责（切站点、回到前台）。

#### 1.7 对现有代码的改动点

- `NativeApp/Sub2MobileApp.swift:ManagementView` → 删除；“请求记录与错误日志”“统计分析”“分组管理”三项并入目录。`MainTabs` 去掉“管理”“设置”两个 Tab（导航章节负责 Tab 结构）。
- 新增 `NativeApp/Features/Search/SearchHomeView.swift`：目录 `List(.insetGrouped)` + `.searchable`；搜索文本为空时显示目录，非空时显示第 2 节的结果视图。
- `NativeApp/Features/SettingsView.swift:SettingsView` 不再作为 Tab 根，改由目录 push（第 3 节）。

---

### 2. 全局搜索结果

#### 2.1 入口与导航

- 在目录顶部搜索框输入即进入；清空或点“取消”回到目录。
- 结果行点击：账号 → 账号详情（账号章节）；用户 → 用户详情（用户章节）；分组 → `.group(id)`（50 章）；代理 → `.proxyDetail(id)`；请求 → 请求详情（日志章节）。
- 账号、用户、分组、代理四个分区底部“查看全部 N 个 ›”：在**搜索 Tab 自己的栈里** push `.searchResults(kind:query:)`，不跳到账号 Tab / 用户 Tab / 分组列表 / 代理列表。原因：账号列表不放搜索框（20 章 §1.1），用户、分组、代理列表的路由都没有“预填搜索词”参数，分组与代理列表是本地过滤。结果页见 2.3 末尾。
- 请求分区没有“查看全部”：请求 ID 是精确匹配，正常只有一两条；本分区一次取 20 条（2.2），还有更多时分区底部写“只显示前 20 条”。日志路由（40 章 §0.1）没有 `request_id` 参数，不要跳到 `.logs`。

#### 2.2 数据来源

后端没有全局搜索接口（附录 B L21；可选的 `GET /admin/search` 未做）→ App 并发扇出，账号、用户、分组、代理各取前 5 条，使用记录与错误请求各取前 20 条。防抖 300ms；去首尾空白后少于 2 个字符不发；新输入时取消上一轮全部请求（`Task` 取消）。

| 分区 | 接口 | 参数 | 发不发 |
|---|---|---|---|
| 账号 | `GET /admin/accounts` | `search=<q>&lite=1&page=1&page_size=5` | 站长；vendor 需 `account_manage \|\| monitor_view` |
| 用户 | `GET /admin/users` | `search=<q>&page=1&page_size=5`（匹配邮箱、用户名、备注与 Key 片段；Key 片段命中时返回 Key 的所属用户，`repository/user_repo.go:553-561`） | 仅站长（vendor 不能读用户，E02 / L5） |
| 分组 | `GET /admin/groups` | `search=<q>&page=1&page_size=5` | 站长；vendor 需任一分组 / 账号 / 监控档 |
| 代理 | `GET /admin/proxies` | `search=<q>&page=1&page_size=5`（只按名称包含匹配，`repository/proxy_repo.go:398`） | 站长；vendor 需 `proxy_manage \|\| account_manage` |
| 使用记录 | `GET /admin/usage` | `request_id=<q>&page=1&page_size=20&key_view=masked`（精确匹配，`repository/usage_log_repo_query.go:120-123`；不传时间范围 = 全部时间；`total` 为 null，看 `has_more`） | 仅当 q “像请求 ID”；vendor 需 `monitor_view`（结果里的用户已打码，E02） |
| 错误请求 | `GET /admin/ops/request-errors` | `request_id=<q>&view=all&time_range=30d&page=1&page_size=20`（默认窗口只有 1 小时，必须显式传 `time_range`；`view=all` 与“客户端最终收到 ≥ 400”一致） | 仅当 q 像请求 ID 且 `features.ops_monitoring_enabled`；仅站长（ops 不对 vendor 开放） |

“像请求 ID”：去空白后不含空格与 `@`，长度 8–256（见未决问题 13）。

`GET /admin/usage/search-api-keys` 只按 Key **名称**匹配（`repository/api_key_repo.go:705-707`），不能用来按 Key 片段找 Key，不要用。

#### 2.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 分区标题 | 固定 | “账号 / 用户 / 分组 / 代理 / 请求”，右侧 `total`（各接口分页信封的 `total`）；请求分区右侧写已显示条数（`admin/usage` 的 `total` 为 null） | 分区无结果时整区不显示 |
| 账号行 | lite 列表项 | 复用账号章节的三行账号行（名称、平台 · 分组、状态徽章与胶囊） | — |
| 用户行 | `username`、`email`、`balance`、`status` | 左：用户名（空时用邮箱）+ 邮箱；右：余额 `$1,284.50`；禁用用户整行变淡并带“禁用”徽章 | 邮箱、用户名、备注都不含 q 时，第二行末尾加“· Key 片段匹配” |
| 分组行 | `name`、`platform`、`status` | 名称 + 平台中文名；停用分组带“停用”徽章 | — |
| 代理行 | 同 12.3 的代理行 | 名称、`协议 · host:port`、延迟或状态 | — |
| 请求行 | 使用记录 / 错误请求列表项 | 复用日志章节的 `LogRow`（左列时间 + 状态码，中间模型 / 用户 · 账号，右列金额 + 首字 / 耗时） | — |
| 查看全部 | 账号 / 用户 / 分组 / 代理分区，`total > 5` | “查看全部 N 个 ›” | `total ≤ 5` 不显示；请求分区没有此行，`has_more == true`（或错误请求 `total > 20`）时写“只显示前 20 条” |
| 底部说明 | vendor 时 | “当前身份看不到用户与错误请求” | — |

**“查看全部”结果页**（`.searchResults(kind:query:)`）：

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 导航栏 | `kind`、`query` | 标题“账号 / 用户 / 分组 / 代理”，副标题“搜索“q” · N 个”（`total`） | — |
| 数据 | 2.2 同一接口、同一 `search`（账号仍带 `lite=1`） | `page_size=20`，触底加载下一页；行组件与本页相同，点行去向同 2.1 | 空：“没有匹配“q”的<对象>” |
| 失败 | — | 首页失败 `FailureView`；翻页失败底部“加载失败 · 重试” | — |

#### 2.4 交互与写操作

只读，无写操作。点行 push；滚动时收起键盘（`.scrollDismissesKeyboard(.immediately)`）。

#### 2.5 状态

| 情况 | 显示 |
|---|---|
| 搜索中 | 每个将要出现的分区一行占位“搜索中…” |
| 全部为空 | “—”空态 + “没有匹配“q”的账号、用户、分组、代理或请求” + “清除搜索” |
| 某分区失败 | 该分区只剩一行“这一类暂时搜不到 · 重试”（重试只重发这一路） |
| 某分区 403 / `OPS_DISABLED` | 静默不显示该分区 |
| 全部失败 | `FailureView`（“暂时无法加载” + 重试） |

#### 2.6 刷新策略

不轮询、不下拉刷新；同一个 q 在本页存活期间缓存 30 秒（返回目录再输入同一个词直接用缓存）。“查看全部”结果页进入时加载第 1 页，支持下拉刷新，不轮询。

#### 2.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/GlobalSearch.swift`：`GlobalSearchQuery`（`isRequestIDLike`、各分区是否发送的判定，输入 `admin/me` 的身份与权限）、扇出结果结构 `GlobalSearchResults`（每区 `BlockState`，10 章 0.5）、`SearchResultKind`（`.accounts / .users / .groups / .proxies`，产出各自的分页请求）。
- `Sources/Sub2Core/APIClient.swift:pagination(_:search:status:)` 把 `page_size` 写死为 20 → 加 `pageSize` 参数（默认 20）；`accounts(page:search:status:platform:)` 增加 `lite` 与 `pageSize`。
- 用户列表复用 `users(page:search:status:)`（加 `pageSize`）；分组复用 `GroupManagement.swift:groups(page:search:platform:status:)`；请求复用 `RequestLogs.swift:requestRecords / errorRecords`（`RequestLogFilter` 加 `requestID` 与 `timeRange`，若日志章节尚未加）。
- 新增 `NativeApp/Features/Search/GlobalSearchResultsView.swift`、`SearchResultsListView.swift`（“查看全部”结果页，按 `kind` 复用账号章节的账号行、用户章节的用户行、50 章的分组行、12.3 的代理行）。

---

### 3. 设置（界面与模式 · 站点与凭据）

#### 3.1 入口与导航

- 目录“界面与模式”→ 本页顶部；“站点与凭据”→ 同一页，`ScrollViewReader` 滚到“站点”分区。导航栏：返回 + 标题“界面与模式”（focus=sites 时为“站点与凭据”）+ 副标题“设置”。
- 本页去向：添加站点（sheet，第 4 节）、登录设备（第 5 节）、管理访问令牌（第 6 节）、推送通知（第 7 节）、金额门槛（sheet）、打开 Web 后台（Safari）。

#### 3.2 数据来源

- 本机设置（`UserDefaults`，不分站点）：`ui.mode`（`main` / `simple`）、`ui.appearance`（`system` / `light` / `dark`）、`security.faceID.enabled`（Bool）、`security.faceID.threshold`（Decimal 字符串，默认 `100`，设计稿 `FACE_ID_LIMIT`）。
- 站点列表：`AppModel.profiles`、`activeProfile`（现有）。
- 当前站点身份：`GET /admin/me` 的 `auth_method`、`user{id,email,username,role}`、`security.totp_enabled`、`server.capabilities`。
- 推送状态行：第 7 节的本机设备记录（本地保存的 device id + `GET /admin/push/devices` 结果）。
- 待核对：`AppModel.pendingBalances`（现有；00 §2.5.5 泛化为 `pendingWrites` 后读其中的余额类）、`AppModel.pendingRedeemBatches`（第 11 节新增）、`pendingWrites` 中 `kind == .redeemGrant` 的补偿发放记录（第 19 节）。

#### 3.3 字段 → 显示映射

| 分区 / 行 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 壹 界面模式 · 主模式 | `ui.mode == main` | 单选圆点；副行“概览 · 账号 · 用户 · 监控，适合日常处理” | — |
| 壹 · 简化模式（表格） | — | 副行“视图列表 + 表格，适合快速筛查大量数据”；行置灰，尾部“设计中” | 首版不可选（未决问题 3） |
| 贰 外观 | `ui.appearance` | 跟随系统 / 浅色 / 深色 三个单选 | 默认跟随系统 |
| 叁 安全 · 高风险操作需要 Face ID | `security.faceID.enabled` | 开关；副行“删除、批量操作、更换账号凭据，以及超过门槛的充值 / 退款、新建用户初始余额、余额兑换码和余额补偿”（与 3.4 的覆盖清单一致，清单改了这里跟着改） | 设备不支持生物识别时开关置灰，副行改“这台设备没有设置 Face ID / 触控 ID” |
| 叁 · 金额门槛 | `security.faceID.threshold` | 右侧 `$100`；副行“单笔或合计超过这个金额时验证” | 开关关闭时不显示本行 |
| 肆 通知 · 推送通知 | 第 7 节本机设备状态 | 右侧“已开启” / “未开启” / “已停用”（设备被停用） | 无 `push.notifications` 或 vendor 时整个分区不显示 |
| 伍 站点 · 站点行 | `profile.name`、`profile.baseURL.host` | 头像为名称首字；第二行 host（等宽）；当前站点右侧“当前” | — |
| 伍 · 添加站点 | — | “+ 添加站点” | — |
| 陆 当前站点 · 身份 | `admin/me.user.email`、`role` | “admin@example.com · 管理员” | `admin/me` 未取到时“—” |
| 陆 · 认证方式 | `admin/me.auth_method`（缺失时用 `profile.authentication`）；只读与否读 `SiteSession.accessTokenScope`（0.3） | `jwt`“邮箱和密码”；`admin_api_key`“Admin Key · 以第一个管理员身份操作”；`admin_access_token`“访问令牌 · 只读 / 读写” | scope 未取到时只写“访问令牌” |
| 陆 · 登录设备 | `auth_method == jwt` 且 `GET /auth/sessions` 不是 404 | “登录设备 ›”，右侧数量 | Admin Key / 访问令牌登录时显示为不可点，副行“Admin Key 与访问令牌没有登录会话” |
| 陆 · 管理访问令牌 | `admin.access_tokens` | “管理访问令牌 ›”，右侧有效令牌数 | 无 capability 或 vendor 时隐藏 |
| 陆 · 打开 Web 后台 | `profile.baseURL` | Safari | — |
| 陆 · 退出并清除凭据 | — | 红字 | — |
| 柒 待核对 · 余额请求 | `pendingBalances` | 沿用现有 `SettingsView` 的“待确认余额请求”分区 | 无记录时不显示 |
| 柒 · 兑换码批次 | `pendingRedeemBatches`（全部站点） | “<站点名> · 20 个 × $10.00 · 合计 $200.00 · 5 分钟前”；当前站点的行“去核对 ›”，其他站点的行“打开原站点核对” | 无记录时不显示 |
| 柒 · 补偿发放 | `pendingWrites` 里 `kind == .redeemGrant`（全部站点） | “<站点名> · 向 王小明 发放 $10.00 余额 · 5 分钟前”；当前站点的行“去核对 ›”→ 打开 `.redeemGrant(userID:pendingID:)` 的核对页（19.4）；其他站点的行“打开原站点核对” | 无记录时不显示 |
| 捌 关于 | `CFBundleShortVersionString` | 沿用现有 | — |

#### 3.4 交互与写操作

- **界面模式**：点“主模式”无变化；简化模式不可选。
- **外观**：写 `ui.appearance`，`RootView` 上 `.preferredColorScheme(nil / .light / .dark)` 立即生效。
- **Face ID 开关**：打开时先 `LAContext().canEvaluatePolicy(.deviceOwnerAuthentication)`，再 `evaluatePolicy` 验证一次，成功才写入 true；关闭时同样验证一次再写 false（未决问题 9）。验证失败或取消保持原值，不弹错误。
- **金额门槛**：sheet 内大数字键盘（复用用户章节的 KeypadSheet 输入规则，整数美元 1–100000），保存写 `security.faceID.threshold`。
- **切换站点**：点非当前站点 → `AppModel.switchTo(_:)`（现有），切换中行尾转圈，期间禁用其他站点行。
- **删除站点**：站点行 ··· → “删除站点和凭据”（红），确认框沿用现有文案；该站点用管理访问令牌登录时，正文加一行“同时吊销这个管理访问令牌”（00 §1.7.5 第 3 条）。执行顺序按 00 §1.1“删除站点”与 §1.7.5，用该站点的凭据依次：① 本机登记过推送设备 → `DELETE /admin/push/devices/:id`（失败记“待删除”，不阻断）；② `sat_`：`GET /admin/access-tokens` 找 `current == true` 的那条 → `DELETE /admin/access-tokens/:id`（只读令牌也允许吊销自己；失败不阻断，回执加“令牌未能吊销，可用 API 吊销”）；JWT：`POST /auth/logout`（带 `refresh_token` 与 `Authorization`）；Admin Key：无；③ `AppModel.remove(_:)`（删除 Keychain 凭据与 `deviceID`）。
- **退出并清除凭据**：确认框沿用现有文案；顺序按 00 §1.7.5（先删推送设备——会话吊销不会自动删除设备，A11 部署注意；JWT 再调 `auth/logout`；只是退出时**不**吊销 sat_）；最后 `AppModel.logout()` 本地擦除。
- 本页无幂等写入。

**Face ID 覆盖清单**（全 App 唯一来源；设置“高风险操作需要 Face ID”打开时生效，门槛为 `security.faceID.threshold`；各章引用本表，不另列）：

| 操作 | 何时验证 | 所在章节 |
|---|---|---|
| 删除任何对象（账号、用户、Key、分组、兑换码、代理、公告、推送接收方式） | 打开时不输入名称，按钮“用 Face ID 删除”，点后验证 | 0.4 删除确认；20 §0.4、30 §2.4 / §7、50 章、本章 8 / 13 / 16 / 7 |
| 批量操作（账号批量调度、批量编辑等） | 执行前 | 20 §0.4 第 4 条、§8 |
| 更换账号凭据：更换 API Key、重新授权 | 点底部红色按钮后、提交前 | 20 §0.4 第 2 条 |
| 充值 / 退款 | 金额超过门槛 | 30 §3.4 |
| 新建用户初始余额 | 初始余额超过门槛 | 30 §5 |
| 生成余额兑换码 | 合计（面值 × 数量）超过门槛 | 本章 10.3 |
| 发放余额补偿 | 金额超过门槛 | 本章 19.4 |
| 揭示完整 Key | **总是**验证，不受开关影响 | 30 §7 |

开关关闭时以上都不验证（揭示完整 Key 除外）；删除改为输入名称确认。

#### 3.5 状态

| 情况 | 显示 |
|---|---|
| `admin/me` 失败 | 身份行“—”，认证方式按本地 `profile.authentication`；其余正常 |
| 切换站点失败 | 根视图通用错误弹窗（现有 `RootView` alert） |
| 待核对文件不可读 | 沿用现有：顶部红字“未决记录无法读取，已暂停新的余额操作 / 兑换码生成 / 补偿发放” |

#### 3.6 刷新策略

本地设置即时生效；“登录设备 / 令牌”右侧数量在进入本页时各请求一次（失败不显示数量）；不轮询。

#### 3.7 对现有代码的改动点

- `NativeApp/Features/SettingsView.swift:SettingsView` → 重写为上表分区；保留现有“站点”“待确认余额请求”“关于”的逻辑与确认框文案；删除站点 / 退出前插入推送设备清理，删除 sat_ 站点时插入令牌吊销（3.4）。
- `NativeApp/Session/AppModel.swift:remove(_:)`：按 3.4 的顺序先删推送设备、吊销 sat_ / 调 logout，再删凭据；`connect` 里为 sat_ 补取 scope（0.3）。
- 新增 `NativeApp/Session/AppPreferences.swift`（`@Observable`，封装四个 `UserDefaults` 键）与 `NativeApp/Session/BiometricGate.swift`（`func confirm(reason:) async -> Bool`、`func needsVerification(amount: Decimal) -> Bool`，以及按 3.4 覆盖清单定义的 `enum GatedAction`，供全 App 的删除、资金确认调用）。
- `NativeApp/Sub2MobileApp.swift:RootView` 加 `.preferredColorScheme(preferences.colorScheme)`。
- `NativeApp/Resources/Info.plist` 加 `NSFaceIDUsageDescription`：“用于确认删除、批量操作、更换账号凭据和超过门槛的资金操作”。

---

### 4. 添加站点（登录）

> 流程、探测、凭据存储与错误文案一律按 00 §1.3–§1.6、§1.9（旧服务端）、§1.10（合规）执行。本节只写登录页的布局与本章入口相关的部分；00 改了，这里不跟着另写。

#### 4.1 入口与导航

- 设置 → 站点 → 添加站点（sheet，带“取消”）；没有活动站点时为根视图（现有 `RootView`）。
- 登录成功后关闭 sheet，切到新站点的概览 Tab。添加失败不替换当前已连接的站点（00 §1.1）。

#### 4.2 数据来源

| 用途 | 接口 | 关键参数 / 字段 |
|---|---|---|
| 站点信息与验证码 | `GET /settings/public` | 成功且带 `version` 才算 Sub2 站点（00 §1.1）；`site_name`（名称框为空时预填）、`captcha_provider` 与旧服务端三个开关（00 §1.5）、`mobile_verify_path`、`backend_mode_enabled`、`login_agreement_enabled` / `login_agreement_mode` / `login_agreement_documents`（00 §1.4 第 1 步）、`totp_enabled`（`handler/dto/settings.go:387-436`） |
| 密码登录 / 两步验证 | `POST /auth/login`、`POST /auth/login/2fa` | 请求体与 `client{type,device_id,device_name}` 按 00 §1.2、§1.4；验证码证明的字段映射按 00 §1.5 的表 |
| 校验身份 | `GET /admin/me` | 00 §1.9。404 且不是 JSON = 旧服务端：JWT 并发调 `auth/me`、`settings/public`、`admin/compliance`；**Admin Key / sat_ 调 `GET /admin/compliance`** 当权限探针（不再用 `admin/dashboard/realtime`） |
| sat_ 的 scope | `GET /admin/access-tokens` | 只在 `auth_method == admin_access_token` 时，见 0.3 |

`mobile_verify_path` 的含义（A09 进度表“部署注意”）：非空说明桥页已打包进后端二进制（`web/embed_on.go:462-472`，值固定为 `/mobile/verify`，`web/mobile_verify.go:7`）；为 `""` **不代表没部署**——前端单独部署（非 `-tags embed` 构建）的站点恒为 `""`（`web/embed_off.go:50-53`），桥页可能照样存在。

#### 4.3 字段 → 显示映射（登录页布局）

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 站点地址 | 用户输入 | 只接受 `https://host[:port]`（00 §1.1） | — |
| 站点名称 | 用户输入；空时用 `site_name` | — | 两者都空时提交报“请填写站点名称” |
| 登录方式 | — | 三个选项，按 00 §1.3 的顺序：“账号和密码（推荐，默认选中）”/“管理访问令牌”/“Admin Key（不推荐）” | — |
| 令牌 / Key 输入框 | 后两个选项共用 | `SecureField`，标签“管理访问令牌或 Admin Key”（00 §1.6）；粘贴的值以 `sat_` 开头时自动切到“管理访问令牌”（00 §1.3） | — |
| 选项说明 | 当前选项 | 管理访问令牌：“以签发它的管理员身份操作，可只读、会过期、能单独吊销。”；Admin Key：00 §1.3 原文“以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。” | — |
| 登录协议 | `login_agreement_*` | 按 00 §1.4 第 1 步（勾选框或弹出确认） | 未开启不显示 |
| 后端模式提示 | `backend_mode_enabled` | 00 §1.4 文案“站点处于后端模式，仅管理员可登录” | — |
| 验证码桥页提示条 | `mobile_verify_path == ""` | 桥页 sheet 顶部一行：“若页面无法完成验证，请改用 Web 登录或 Admin Key”（00 §1.5） | 非空时不显示 |
| 两步验证 | `requires_2fa` | 底部 6 位输入（00 §1.4 第 3 步） | — |
| 登录后身份确认 | `admin/me.user.email` | 回执“已连接 · 以 admin@example.com 身份操作” | — |

#### 4.4 交互与写操作

- **提交（账号和密码）**：校验 URL（现有 `AppModel.validatedURL`）→ `settings/public` → 需要验证码时：
  - `captcha_provider == "conflict"`（或旧服务端开了不止一个）：按 00 §1.5 停止登录。
  - 其他需要验证码的情况**一律打开桥页**，不因 `mobile_verify_path == ""` 拒绝：加载 `<站点><path>?nonce=<新 UUID>`，`path` = `mobile_verify_path` 非空时用它，否则用 `/mobile/verify`；为 `""` 时显示 4.3 的提示条；只有页面**加载失败**才提示 00 §1.5 的“站点未部署手机验证页，请改用 Web 或关闭验证码”。
  - 时限按 00 §1.5：桥页自身 2 分钟，App 端 180 秒（现有 `CaptchaView` 已是 180 秒）；证明只用一次。
  - → 登录 → 需要时两步验证 → 角色检查（00 §1.4 第 4 步）→ `admin/me` → `AppModel.connect`。
- **提交（管理访问令牌 / Admin Key）**：按 00 §1.6 带 `x-api-key` 调 `admin/me`；sat_ 再取 scope（0.3）。
- **凭据存储**按 00 §9.4：`AuthenticationKind.accessToken`、`Credential.accessToken(String)`（不再借用 `.adminKey`）；旧数据里 `.adminKey` 的值以 `sat_` 开头时迁移成 `.accessToken`。两者都放 `x-api-key` 头（00 §0 第 2 条）。
- **错误**：全部按 00 §1.4 的错误表与 §1.6 第 2 条的文案处理（含 `CAPTCHA_PROVIDER_MISMATCH` 重新拉公开设置再验证、`TOTP_*`、`BACKEND_MODE_ADMIN_ONLY`、`INVALID_ADMIN_KEY`、`ACCESS_TOKEN_EXPIRED`、`RATE_LIMITED` 倒计时）；`compliance.required == true` 进入 00 §1.10；登录响应 `refresh_token_unavailable == true` 按 00 §1.4 第 5 步在概览顶部显示横幅（概览布局见 10 章）。本节不另写文案。

#### 4.5 状态

提交中按钮转圈、表单禁用（现有）；验证码 sheet 不能下滑关闭（现有）。

#### 4.6 刷新策略

无。

#### 4.7 对现有代码的改动点

- `NativeApp/Features/LoginView.swift:submit()`：去掉“提供方不在 turnstile / tencent / aliyun 里就报‘暂不支持原生验证’”的分支，改为 4.4 的 `conflict` 判断 + 一律打开桥页；登录方式改为三个选项与 sat_ 自动识别；登录成功后用 `admin/me` 的身份做回执；凭据用 `.accessToken`。
- `Sources/Sub2Core/Models.swift:PublicSettings`、`AuthenticationKind`、`Credential`：按 00 §9.4。
- `Sources/Sub2Core/APIClient.swift:LoginBody`、`verifyAdministrator()`：按 00 §9.1（`client`、`captcha_provider`、`aliyun_captcha_param`；改调 `me()`，旧服务端 Admin Key 探针用 `admin/compliance`）。
- `NativeApp/Features/CaptchaView.swift`：`CaptchaRequest` 增加 `path: String`（由 4.4 的规则算出）与 `showsFallbackHint: Bool`（`mobile_verify_path == ""`）；`CaptchaWebView.makeUIView` 的 `components.path` 改用 `request.path`（现在写死 `/mobile/verify`，`CaptchaView.swift:42`，非空的 `mobile_verify_path` 目前也是这个值）；`CaptchaView` 顶部按 `showsFallbackHint` 显示提示条；`didFailProvisionalNavigation` 的文案改为 00 §1.5 的“站点未部署手机验证页，请改用 Web 或关闭验证码”。

---

### 5. 登录设备（会话列表，A07）

#### 5.1 入口与导航

- 设置 → 当前站点 → 登录设备（仅 `auth_method == jwt`）。标题“登录设备”，副标题站点名。只读页面，无下钻。

#### 5.2 数据来源

- `GET /auth/sessions` → `data.items[]`：`id`、`device_name`、`client_type`、`user_agent`、`ip`、`created_at`、`last_seen_at`、`expires_at`、`current`（`handler/auth_sessions_handler.go:12-22`）；按 `last_seen_at` 倒序，最多 50 条。
- 404 → 老服务端：本页不可进入（设置行已隐藏）。

#### 5.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 图标 | `client_type` | `ios` iPhone、`android` 手机、`web` 地球 | 空串（部署前已存在的会话）用问号图标 |
| 标题 | `device_name` | 原样 | 空时：UA 含 `Sub2Mobile` → “Sub2 Mobile（iOS）”；否则 `user_agent` 截前 40 字；都空“未知设备” |
| 本机徽章 | `current` | “本机” | — |
| 第二行 | `ip`、`last_seen_at` | “203.0.113.24 · 3 分钟前活跃”（相对时间） | IP 空时只写活跃时间 |
| 第三行 | `created_at`、`expires_at` | “登录于 10/17 09:41 · 11/16 到期” | — |
| 列表底部说明 | 固定 | “部署新版本前登录的设备，下一次自动续期后才会出现在这里。” | — |

#### 5.4 交互与写操作

- **下线某台设备**：非本机行 `.swipeActions(edge: .trailing)` “下线”（红）→ 确认框“让「设备名」下线？该设备需要重新登录。”→ `DELETE /auth/sessions/:id` → 删除该行，toast “已下线「设备名」”。响应 `data.current == true`（理论上不会，本机行不给滑动）时按本机退出处理（3.4 退出流程）。`404 SESSION_NOT_FOUND` → 直接删除该行（已不存在）。
- **本机行**：不给滑动；点按弹说明“这是本机。要退出请用设置里的“退出并清除凭据”。”（未决问题 12）。
- **让其他所有设备下线**：列表底部红字按钮（只有一条以上时显示）→ 确认框“让其他 N 台设备下线？它们需要重新登录，本机不受影响。”→ `POST /auth/revoke-all-sessions`，请求体 `{"keep_current": true}`（`handler/auth_handler.go:851-878`）→ 重新加载列表。
- 不需要 step-up；不需要幂等键（重发结果相同）。

#### 5.5 状态

| 情况 | 显示 |
|---|---|
| 加载中 | 列表占位 |
| 只有本机 | 本机一行 + “没有其他设备登录” |
| 失败 | `FailureView` + 重试 |
| 401 | 通用重新登录 |

#### 5.6 刷新策略

进入时加载；下拉刷新；写操作后重载。不轮询。

#### 5.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/AuthSessions.swift`：`AuthSessionItem`（Decodable）、`APIClient.sessions()`、`revokeSession(id:) -> Bool(current)`、`revokeOtherSessions()`。
- 新增 `NativeApp/Features/Settings/SessionsView.swift`。
- 设备名依赖登录时带 `client.device_name`（4.2），否则 iOS 会话也显示“Sub2 Mobile（iOS）”。

---

### 6. 管理访问令牌（sat_，A08）

> 首版**不在 App 内签发**令牌，只列出与吊销（00 §1.3 与 00 未决问题 3 的默认；本章未决问题 10）。sat_ 只能粘贴使用（第 4 节）。

#### 6.1 入口与导航

- 设置 → 当前站点 → 管理访问令牌（`admin.access_tokens`，vendor 不可见）。标题“管理访问令牌”，副标题站点名。没有 `+`、没有新建 sheet。

#### 6.2 数据来源

- `GET /admin/access-tokens` → `data.items[]`：`id`、`name`、`prefix`（如 `sat_3f9a`）、`last4`、`scope`（`read` / `write`）、`expires_at`、`last_used_at`、`last_used_ip`、`created_at`、`current`（`handler/admin/access_token_handler.go:28-40`）；只含当前管理员未吊销、未过期的令牌。Admin Key 登录时列的是第一个管理员的令牌。
- `DELETE /admin/access-tokens/:id` → `{message, current}`。
- 不调用 `POST /admin/access-tokens`（签发；路由挂 step-up，且 handler 对 Admin Key / sat_ 一律返回 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`，`access_token_handler.go:58-61`）。

#### 6.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 顶部说明 | 固定 | “访问令牌以签发它的管理员身份调用管理接口，可只读、会过期、能单独吊销。比 Admin Key 安全：Admin Key 以第一个管理员身份操作，丢了只能到 Web 重新生成。” | — |
| 行标题 | `name` | 原样 | — |
| 权限徽章 | `scope` | `read` “只读”（neutral）、`write` “读写”（caution） | — |
| 本机徽章 | `current` | “本机”（本 App 正在用这个令牌） | — |
| 掩码 | `prefix`、`last4` | 等宽“sat_3f9a…c71e” | — |
| 使用情况 | `last_used_at`、`last_used_ip` | “最近使用 3 分钟前 · 203.0.113.24” | `last_used_at` 为 null：“从未使用” |
| 到期 | `expires_at` | “2027/01/16 到期 · 还剩 87 天”；≤ 7 天时 caution 色 | — |

#### 6.4 交互与写操作

- **吊销**：行滑动“吊销”（红）→ 确认框“吊销「名称」？用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。”；是本机那条（`current == true`）时正文加“本机会退出这个站点。”→ `DELETE /admin/access-tokens/:id` → 删除该行。
  - 吊销本机那条：先按 00 §1.7.5 第 1 步删本机推送设备（令牌吊销后就删不掉了），再发 DELETE；响应 `current == true` → 本机凭据已失效，本地擦除（不再调 logout 接口），提示“已吊销本机正在使用的令牌，请重新登录”。
  - `404 ACCESS_TOKEN_NOT_FOUND` → 删除该行。
- 只读令牌只能吊销自己（00 §2.6.3），其余行不给滑动。
- 吊销可以重发（结果相同），不带幂等键；不需要 step-up。

#### 6.5 状态

| 情况 | 显示 |
|---|---|
| 空 | “还没有访问令牌” + 说明“首版 App 不签发访问令牌。” |
| 失败 | `FailureView` |

#### 6.6 刷新策略

进入时加载；下拉刷新；吊销后重载。

#### 6.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/AccessTokens.swift`（`AdminAccessToken`、`APIClient.accessTokens()` / `revokeAccessToken(id:)`，与 00 §9.1 新增方法同名）。
- 新增 `NativeApp/Features/Settings/AccessTokensView.swift`。不新增签发 sheet。

---

### 7. 推送通知（A11）

> 协议层（注册参数与时机、订阅字段、载荷、深链、退出与多站点）以 00 §7 为准；本节写推送设置页的布局、Bark / ntfy / Webhook 的添加与删除、站点 APNs 配置的编辑。00 §7.1 / §7.4 里“请站长在 Web 设置”“其他渠道 App 只读显示”两句与本节不同，按本节执行（Web 没有推送配置界面；合稿裁定见文末“审查未采纳的意见”R15）。

#### 7.1 入口与导航

- 设置 → 通知 → 推送通知（`push.notifications`；vendor 不可见）。标题“推送通知”。
- 去向：其他接收方式的设备详情（同页 push：订阅编辑 + 测试 + 最后一行红字“删除接收方式…”）、“添加 Bark / ntfy / Webhook”（sheet）、“站点 APNs 配置 · 编辑”（sheet）、系统通知设置（`UIApplication.openNotificationSettingsURLString`）。
- 推送点击后的跳转按 00 §7.5（`site` 匹配 `ServerProfile.id.uuidString`、跨站点先切换、凭据已清除先登录）：`push.test` 进入“设置 → 推送通知”（本页）；`site` 匹配不到本机站点时只打开 App、停在概览。

#### 7.2 数据来源

| 用途 | 接口 | 字段 |
|---|---|---|
| 我的推送目标 | `GET /admin/push/devices` | `items[]`：`id`、`platform`（`ios` / `bark` / `ntfy` / `webhook`）、`token_hint`（末 4 位）、`endpoint_host`、`bundle_id`、`environment`、`device_name`、`locale`、`timezone`、`site_tag`、`enabled`、`disabled_reason`、`disabled_at`、`last_success_at`、`last_error`、`last_error_at`、`credentials_encrypted`、`subscription{events,min_severity,group_ids,platforms,quiet_hours{start,end}}`、`created_at`、`updated_at`（`handler/admin/push_handler.go:47-68`） |
| 登记 | `POST /admin/push/devices` | iOS：按 00 §7.2 的请求体 `{platform:"ios", apns_token:<hex>, bundle_id, device_name, locale, timezone, site_tag}`，**默认不传 `environment`**（服务端存空串，发送时跟随站点 `apns_environment`，`service/push_device_service.go:177-183`、`service/push_sender_apns.go:109-111`），只有开发构建传 `"sandbox"`；Bark：`{platform:"bark", endpoint, token:<device key>, device_name}`；ntfy：`{platform:"ntfy", endpoint, token:<topic>, secret?:<access token>, device_name}`；Webhook：`{platform:"webhook", endpoint, secret?:<HMAC 密钥>, device_name}`；201 新建 / 200 已存在（`created`） |
| 删除 | `DELETE /admin/push/devices/:id` | — |
| 改订阅 | `PUT /admin/push/devices/:id/subscription` | 整体替换：`{events:[…], min_severity:"P0".."P3", group_ids:[…], platforms:[…], quiet_hours:{start:"HH:MM", end:"HH:MM"} \| null}` |
| 测试 | `POST /admin/push/devices/:id/test` | 成功 `{delivered:true, provider_status}` |
| 站点 APNs | `GET /admin/push/config` / `PUT /admin/push/config`（PUT 挂 step-up，仅站长） | `apns_enabled`、`apns_team_id`、`apns_key_id`、`apns_private_key`（只写）/ `apns_private_key_configured`、`apns_topic`、`apns_environment`、只读 `encryption_key_configured`、`ready`（`service/push_config_service.go:42-63`） |
| 订阅范围选项 | 分组目录 `GET /admin/groups/all?include_inactive=true`（50 章缓存）；平台目录 `GET /admin/meta/catalog`（`meta.catalog`，否则内置平台表） | — |

本机（iOS）设备 id 按站点存本地：`UserDefaults` 键 `push.deviceID.<profileID>`。

#### 7.3 字段 → 显示映射

| 分区 / 行 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| APNs 未就绪横幅 | `config.ready == false` | caution：“站点还没配好 APNs，本机收不到推送。可改用 Bark / ntfy / Webhook，或在下方配置 APNs。” | `ready == true` 不显示；GET config 失败不显示 |
| 本机 · 在本机接收推送 | 本机 device id 存在且列表里该设备 `enabled` | 开关 | `config.ready == false` 时置灰、不发起注册（00 §7.1），副行“站点配好 APNs 后才能打开”；GET config 失败时照常可用 |
| 本机 · 状态行 | `last_success_at` / `disabled_reason` / `last_error` | 正常：“已开启 · 上次送达 10/17 09:41”；`unregistered`“设备令牌已失效，关掉再打开即可恢复”；`bad_device_token`“设备令牌无效”；`topic_mismatch`“App 的包名与站点 APNs 配置不符”；`secret_undecryptable`“站点更换了加密密钥，关掉再打开即可恢复”；`last_error` 非空时追加“最近失败：<last_error>” | 从未送达：“已开启 · 还没有送达记录” |
| 系统权限 | `UNUserNotificationCenter` 授权状态 | 被拒：行内“系统设置里关闭了通知 · 去设置” | — |
| 推送内容 · 事件 | `subscription.events` | 四个开关：告警触发（`ops_alert.fired`）、告警恢复（`ops_alert.resolved`）、账号出错（`account.error`）、账号测试完成（`account.test_finished`） | 全关 = `events: []`，副行“已暂停推送” |
| · 告警级别 | `min_severity` | “P1 及以上”（P0–P3 菜单） | 默认 P1 |
| · 平台范围 | `platforms` | “全部平台” / “Anthropic、OpenAI” | 空数组 = 全部 |
| · 分组范围 | `group_ids` | “全部分组” / “高级组 等 3 个” | 空数组 = 全部；全站告警不受范围限制（副行写明） |
| · 免打扰 | `quiet_hours` | 开关 + 开始 / 结束时间（`DatePicker(.hourAndMinute)`），副行“按本机时区 Asia/Shanghai；时段内的事件不补推” | null = 关 |
| · 分区脚注 | 固定 | “同一账号出错 30 分钟内最多推一次；推送最多晚约 15 秒；测试完成只推给发起测试的人。” | — |
| 其他接收方式 · 行 | 列表里除本机外的设备 | 图标按 `platform`；标题 `device_name`（空时 `endpoint_host`）；副行“iOS · …a3f0” / “ntfy · ntfy.sh”；停用时 neutral 徽章“已停用” | — |
| 添加 Bark / ntfy / Webhook | 只读 sat_ 时隐藏 | “+ 添加其他接收方式” | — |
| 测试 | 本机设备存在 | “发送测试推送” | 未开启时置灰 |
| 站点 APNs 配置 | GET config | Team ID、Key ID、私钥“已配置 / 未配置”、Topic（空时“跟随 App 包名”）、环境、状态“可用 / 未就绪” | “编辑”可用条件：不是只读令牌，且（`security.step_up_enabled == false` 或 `step_up_available == true`），与 30 章揭示 Key 的规则相同。否则置灰并注：开启二次验证时用 Admin Key / 访问令牌登录 →“站点开启了二次验证，需要邮箱和密码登录才能修改”；账号没开 TOTP →“需要先在 Web 端开启二次验证”；只读令牌 →“只读令牌” |

#### 7.4 交互与写操作

- **打开本机推送**：① `requestAuthorization(options: [.alert, .sound, .badge])`；拒绝 → 提示去系统设置，开关回到关。② `registerForRemoteNotifications()`，拿到 device token（十六进制小写）。③ `POST /admin/push/devices`，请求体按 00 §7.2：`platform:"ios"`、`apns_token`、`bundle_id: Bundle.main.bundleIdentifier`、`device_name: UIDevice.current.name`、`locale:"zh-Hans"`、`timezone: TimeZone.current.identifier`、`site_tag: profile.id.uuidString`（未决问题 8）；`environment`：Release / TestFlight 构建**不传**（跟随站点 `apns_environment`，站长在站点设置里切换时已登记的设备跟着变），只有带 `aps-environment=development` 的开发构建传 `"sandbox"`；**不要显式传 `"production"`**。首次不带 `subscription`（后端默认告警触发 + 账号出错、P1）。④ 保存返回的 `id`。
- **关闭本机推送**：`DELETE /admin/push/devices/:id`，清本地 id。
- **自动重新登记**：系统回调新 token、或成功连接到一个本机开启过推送的站点时，重发一次 POST（同一令牌返回 200、id 不变、重新启用被停用的设备）。
- **改订阅**：每次修改立即 `PUT …/subscription`（整对象），乐观更新；失败回滚并提示。`INVALID_PUSH_SUBSCRIPTION` 按 `metadata.field` 定位（App 正常不会触发）。
- **测试**：`POST …/:id/test` → “已发送测试推送，请看通知”；`503 PUSH_NOT_CONFIGURED`“站点没有配好 APNs”；`502 PUSH_DELIVERY_FAILED`“推送服务没有接受：<metadata.provider_reason>（<metadata.provider_status>）”，随后重载列表（设备可能已被停用）；`404 PUSH_DEVICE_NOT_FOUND` → 清本地 id、重载。
- **添加其他接收方式**（sheet）：平台分段 Bark / ntfy / Webhook；Bark：服务器（默认 `https://api.day.app`）、设备 Key；ntfy：服务器（默认 `https://ntfy.sh`）、主题（字母、数字、`-`、`_`）、访问令牌（可选）；Webhook：URL、签名密钥（可选，脚注“设置后请求带 `X-Sub2-Signature: sha256=HMAC(secret, 时间戳 + "." + 正文)`”）；名称。提交同一 POST。
  - reason：`INVALID_PUSH_TARGET`“地址不被允许：默认只接受公网 https 地址（局域网或 http 需站长打开 push_targets 配置）”；`INVALID_PUSH_TOKEN`“设备 Key / 主题格式不对”；`PUSH_TARGET_IN_USE`“这个接收地址已由另一位管理员登记”；`PUSH_DEVICE_LIMIT_REACHED`“最多 20 个推送目标，先删除不用的”；`ACCESS_TOKEN_READ_ONLY`（只读 sat_）“只读令牌只能登记本机推送”。
- **删除其他接收方式**：不放滑动操作。设备详情最后一行红字“删除接收方式…”→ 通用删除确认（0.4）：标题“删除接收方式「名称」？”（名称 = `device_name`，空时 `endpoint_host`），正文“站点 X · 删除后不能恢复。\n这个地址不再收到推送，要恢复需重新添加。”；Face ID 关时输入完整名称，开时“用 Face ID 删除”→ `DELETE /admin/push/devices/:id` → 返回本页并重载列表，toast “已删除接收方式「名称」”；`404 PUSH_DEVICE_NOT_FOUND` 视为已删除。（本机设备用“在本机接收推送”开关关闭，不走这条。）
- **编辑站点 APNs 配置**（sheet，可用条件见 7.3）：启用开关、Team ID（10 位）、Key ID、私钥“导入 .p8 文件…”（`.fileImporter`，读成 PEM 文本）或粘贴、Topic、环境（production / sandbox）。只提交改过的字段；私钥不改时不传。保存前按 00 §2.6.1 主动判断：`step_up_enabled == true` 且未在授权期内 → 先弹 `StepUpView`；`step_up_enabled == false` 时直接保存（Admin Key / sat_ 也可以，`server/middleware/step_up.go:100`）。仍收到 `403 STEP_UP_REQUIRED` → `StepUpView` 后用户再点保存；`STEP_UP_ADMIN_API_KEY_FORBIDDEN`（站点刚打开二次验证）→ 重新取 `admin/me` 并把“编辑”置灰；`INVALID_APNS_CONFIG` 按 `metadata.field` 标红对应字段（如“启用需要 Team ID、Key ID 与私钥”）；`SECRET_ENCRYPTION_KEY_NOT_CONFIGURED`“站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存”。`encryption_key_configured == false` 时导入按钮置灰并写明原因。私钥文本提交后立即清空。
- **退出 / 删除站点**：先删本机设备（3.4）。

#### 7.5 状态

| 情况 | 显示 |
|---|---|
| 列表加载失败 | 本机分区与其他目标分区各一行“加载失败 · 重试”；开关置灰 |
| 登记失败 | 开关回到关 + 错误文案 |
| GET config 403 / 失败 | 不显示 APNs 分区与横幅 |
| 构建没有推送能力（`registerForRemoteNotifications` 失败） | “这个 App 构建没有开启推送能力；APNs 只适用于用站点同一 Apple Team 的 p8 私钥构建的 App。可改用 Bark / ntfy / Webhook。” |

#### 7.6 刷新策略

进入时加载设备列表与 APNs 配置；下拉刷新；App 回到前台且停留在本页时重载一次（捕捉被停用的设备）。不轮询。

#### 7.7 对现有代码的改动点

- 新增 entitlements 文件（`aps-environment`；用 `interruption-level: time-sensitive` 需另加 Time Sensitive Notifications 能力），`Sub2Mobile.xcodeproj` 打开 Push Notifications capability。Debug 配置用 `aps-environment=development` 的 entitlements，并在同一配置定义编译条件（如 `APNS_SANDBOX`），`PushDeviceRegistration` 只在该条件下带 `environment:"sandbox"`；Release 配置不定义、不带。
- `NativeApp/Sub2MobileApp.swift` 加 `@UIApplicationDelegateAdaptor`：`didRegisterForRemoteNotificationsWithDeviceToken`、`didFailToRegister…`、`UNUserNotificationCenterDelegate`（前台展示 + 点击路由）。
- 新增 `Sources/Sub2Core/Push.swift`（`PushDevice`、`PushSubscription`、`PushAPNsConfig`、`PushDeviceRegistration`、APIClient 七个方法）、`NativeApp/Session/PushCoordinator.swift`（token、按站点保存 device id、重新登记、点击路由按 00 §7.5）、`NativeApp/Features/Settings/PushSettingsView.swift`、`PushTargetDetailView.swift`（订阅、测试、删除）、`PushTargetSheet.swift`、`APNsConfigSheet.swift`。
- `NativeApp/Session/AppModel.swift:logout()` / `remove(_:)` 在清凭据前调 `PushCoordinator.unregister(profile:)`。

---

### 8. 兑换码列表（行内展开，含 `redeemDetail` 定位）

#### 8.1 入口与导航

- 目录 → 兑换码；概览待处理“兑换码生成结果待核对”→ `.redeem(reconcile: true)`（横幅高亮，按钮为主样式）；用户章节补偿回执“查看兑换码”→ `.redeem(open: id)`。
- 导航栏：返回 + 标题“兑换码” + 副标题“<站点名> · N 个”+ 右上 `+`（生成）。
- 去向：编辑 sheet（9）、生成 sheet（10）、核对 sheet（11）、··· → 查看使用者 → 用户详情（用户章节）。
- `redeemDetail` 不是独立页面：任何“打开某个兑换码”的入口都落到 `.redeem(open: id)`：列表滚到该卡片并展开；该码不在已加载的页里时先 `GET /admin/redeem-codes/:id`，把它作为“定位的兑换码”单独显示在列表顶部（展开），下面照常是列表。

#### 8.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 列表 | `GET /admin/redeem-codes` | `page`、`page_size=50`、`sort_by=id`、`sort_order=desc`、`types=balance,concurrency,subscription,invitation`（排除管理员调整兼容记录，G04；类型菜单选中某一类时改为 `types=<该类>`；不能与 `type` 同传，否则 400 `REDEEM_CODE_TYPE_CONFLICT`）、`status=unused\|used\|expired\|disabled`（状态胶囊）、`search=<q>`（码值包含或使用者邮箱包含，不分大小写，不搜备注，服务端截到 100 字节）、`batch_id=<uuid>`（“查看同一批”） |
| 列表项字段 | `dto.AdminRedeemCode` | `id`、`code`（32 位小写十六进制）、`type`、`value`、`status`（后端已把“未使用但过期”映射成 `expired`，`dto/mappers.go:716-718`）、`used_by`、`used_at`、`created_at`、`expires_at`（可缺）、`group_id`、`validity_days`、`user{id,email,username,…}`（使用者）、`group{id,name,…}`、`notes`、`batch_id`（老码没有）、`created_by` |
| 计数 | `GET /admin/redeem-codes/stats` | 与列表相同的 `types`、`search`（`status` 被忽略）→ `total_codes`、`by_status{unused,used,expired,disabled}`、`by_type`、`total_value_distributed` |
| 单个 | `GET /admin/redeem-codes/:id` | 定位与写后刷新 |

capability：`redeem_codes.stats`（0.2）。缺失时：列表不带 `types`，“全部类型”在客户端剔除 `admin_balance` / `admin_concurrency`（页可能不满 50，继续“加载更多”）；胶囊不显示数字；副标题不显示数量。vendor 不可见。

#### 8.3 字段 → 显示映射

**派生**：`redeemed = status == "used" || used_by != nil`（G05 / G07 的“已使用”口径，兑换后又被改成过期 / 禁用的码也算）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 副标题数量 | 不带 search 的 `stats.total_codes` | “主站 · 128 个” | 计数失败或缺 capability 时只写站点名 |
| 待核对横幅 | 第 11 节本机记录（当前站点） | 见 11.3 | 无记录不显示 |
| 搜索框 | — | 占位“搜索兑换码或邮箱” | — |
| 状态胶囊 | `stats.total_codes`、`by_status.*` | “全部 128 / 未使用 40 / 已使用 70 / 已过期 12 / 已禁用 6”，计数随搜索与类型变化 | 计数失败：只显示名称 |
| 类型胶囊 | 当前类型 | 未选“类型”，选中后显示类型名；菜单：全部类型 / 余额 / 并发数 / 订阅 / 邀请码 | — |
| 组头 | `created_at`（服务器时区日界） | “今天生成 / 昨天生成 / 更早生成”，右侧该组已加载条数 | — |
| 卡片头 · 码值 | `code` | 等宽“a3f0····d4e8”（前 4 + 后 4） | — |
| 卡片头 · 面值（右） | `type` + `value` / `validity_days` | `balance` “$10.00”；`concurrency` “+2 并发”；`subscription` “30 天”（`validity_days`）；`invitation` “注册邀请”（灰） | — |
| 卡片头 · 第二行 | 见右 | 前缀 = 订阅码用 `group.name`，其他用类型名（余额 / 并发数 / 邀请码）；`redeemed`：“前缀 · 使用者 · MM/DD”（`used_at`）；`expired`：“前缀 · MM/DD 已过期”；`disabled`：“前缀 · MM/DD 生成”；`unused`：“前缀 · MM/DD 过期”或“前缀 · 永不过期” | 使用者 = `user.username`，空时 `user.email`，`user` 缺失时“用户 #<used_by>” |
| 卡片头 · 状态徽章 | `status` | 未使用（ok）/ 已使用 / 已过期 / 已禁用（neutral） | — |
| 卡片头 · 变淡 | `status != unused` | 整卡 idle 样式 | — |
| 展开 · 码值框 | `code` | 两行各 16 位、每 4 位留空隙（只是排版，复制的是原码）；默认遮罩“a3f0 •••• •••• ••••”/“•••• •••• •••• d4e8”；眼睛图标切换显示，复制图标；VoiceOver 读“兑换码已遮罩，结尾 d4e8”或完整码 | — |
| 展开 · 使用者 | `user` | 可点 → 用户详情 | 只在 `redeemed` 时显示 |
| 展开 · 使用时间 | `used_at` | “10/16 09:20” | 只在 `redeemed` 时显示 |
| 展开 · 生成时间 | `created_at` | “10/16 09:12” | — |
| 展开 · 过期时间 | `expires_at` | “10/23 09:12 · 还剩 7 天”（未使用 / 已禁用；剩 ≤ 1 天 caution 色）；“今天到期”；已过期写“（已过期）” | 缺失：“永不过期” |
| 展开 · 订阅分组 / 有效天数 | `group.name`、`validity_days` | “企业专线”、“30 天” | 只在订阅码显示；`group` 缺失时用分组目录查 `group_id` |
| 展开 · 备注 | `notes` | 原样 | 空：“—” |
| 展开 · 按钮行 | 状态 | 未使用：“禁用 · 编辑 · ···”；已禁用：“启用 · 编辑 · ···”；已过期且未兑换：“续期（主）· ···”；`redeemed`：“编辑备注 · ···” | 只读令牌：只有 ··· 里的复制 |
| ··· 菜单 | — | 标题“a3f0····d4e8”，说明“余额 · $10.00 · 未使用”；项：复制兑换码；查看使用者 <名>（`redeemed`）；查看同一批（有 `batch_id`，未决问题 11）；删除兑换码…（红，最后；`redeemed` 或类型为 `admin_*` 时不出现） | — |

#### 8.4 交互与写操作

- **展开**：点卡片头原地展开，同一时间只展开一张（`@State openID: Int?`），展开后 `ScrollViewReader.scrollTo(id)` 滚到能看全（避开浮动 Tab 栏）。卡片内按钮用 `.buttonStyle(.borderless)`。
- **滑动**（只在收起的卡片上）：`.swipeActions(edge: .trailing)` = 禁用 / 启用（未使用、已禁用）或 续期（已过期 → 编辑 sheet）；`.swipeActions(edge: .leading)` = 复制兑换码。删除不放进滑动。
- **禁用 / 启用**：`POST /admin/redeem-codes/batch-update`，`{"ids":[id],"fields":{"status":"disabled"}}`（启用为 `"unused"`）。乐观更新徽章；toast “已禁用 · 不能再兑换” / “已启用 · 可以兑换”，带撤销（写回旧状态）。失败回滚；`409 REDEEM_CODE_USED`“这个码已被兑换，不能再改状态”并 `GET :id` 刷新该卡。成功后重拉 stats。
- **复制**：toast “已复制兑换码”。
- **删除**：确认框（0.4）：标题“删除兑换码「····d4e8」？”，正文“站点 主站 · 删除后不能恢复。\n余额 · $10.00 · 未使用”，输入框“输入末 4 位确认删除”（占位“末 4 位”，`.textInputAutocapitalization(.never)`，大小写都算对）或 Face ID → `DELETE /admin/redeem-codes/:id` → 移除卡片、收起，toast “已删除兑换码「····d4e8」”，重拉 stats。`404 REDEEM_CODE_NOT_FOUND` 视为已删除；`409 REDEEM_CODE_USED`“已被兑换的兑换码不能删除”并刷新该卡。无撤销。
- **查看同一批**：重新加载列表，参数换成 `batch_id=<该码 batch_id>`（不带 `types` / `status`），顶部出现可移除的筛选胶囊“同一批 · 20 个 ✕”。
- **生成**：`+` → 若当前站点有待核对记录，先确认框“上一批兑换码的生成结果未确认”，正文“20 个 × $10.00 · 合计 $200.00\n5 分钟前发起。先核对，避免重复生成。”，按钮“先核对”（默认）/“仍要生成新的一批”/“取消”；否则直接打开生成 sheet。
- 本页写入都是绝对值（batch-update）或天然幂等（delete），不带幂等键。

#### 8.5 状态

| 情况 | 显示 |
|---|---|
| 首次加载 | 卡片占位 |
| 没有任何兑换码 | “还没有兑换码” + “生成兑换码” |
| 筛选后为空 | “—”空态 + 有搜索词时“没有匹配“q”的兑换码” + “清除搜索”；否则“没有这类兑换码” |
| 列表失败 | `FailureView` + 重试（胶囊照常） |
| 计数失败 | 胶囊只显示名称，副标题只写站点名 |
| 加载更多失败 | 列表底部“加载失败 · 重试” |
| 定位的码 `404` | toast “这个兑换码已被删除” |
| `400 REDEEM_CODE_TYPE_INVALID` / `REDEEM_CODE_TYPE_CONFLICT` / `REDEEM_BATCH_ID_INVALID` | App 参数错误，按通用“请求无效”处理并上报日志（不含码值） |

#### 8.6 刷新策略

首次进入加载第 1 页 + stats；重新显示时距上次加载超过 60 秒则重载；下拉刷新重载第 1 页 + stats；触底加载下一页；写操作后只刷新该卡（`GET :id`）与 stats；生成 / 核对完成后重载第 1 页。不轮询，无 ETag。

#### 8.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/RedeemCodes.swift`：`AdminRedeemCode`（`value` 用 `KeyedDecodingContainer.decimal` 解码，`Models.swift:417-431`）、`RedeemCodeListQuery`（产出 query items，含 `types` 规则）、`RedeemCodeStats`、`RedeemBatchUpdateFields`（`expires_at` / `group_id` 需区分“不传”与 `null`，自定义 `encode(to:)`）、`APIClient` 扩展：`redeemCodes(page:query:)`、`redeemCodeStats(query:)`、`redeemCode(id:)`、`updateRedeemCodes(ids:fields:)`、`deleteRedeemCode(id:)`。
- 新增 `NativeApp/Features/Redeem/RedeemCodesView.swift`（列表、胶囊、横幅、定位）、`RedeemCodeCard.swift`（卡片头 + 展开内容 + 按钮行）、`RedeemCodeBox.swift`（码值框，可在生成结果复用）。
- 删除确认、撤销 toast、Face ID 用通用组件 / `BiometricGate`（3.7）。

---

### 9. 编辑兑换码 sheet（`redeemEdit`）

#### 9.1 入口与导航

卡片“编辑 / 编辑备注 / 续期”、收起卡片的滑动“续期”。sheet 左上“取消”，右上“保存”（已过期且选了新时间时为“续期”）。

#### 9.2 数据来源

- 打开时用列表里的该码；保存用 `POST /admin/redeem-codes/batch-update`，请求 `{"ids":[id],"fields":{…}}`，`fields` 只放改过的键：`status`（只能 `unused` / `disabled`）、`expires_at`（RFC3339，`null` = 永不过期）、`group_id`（订阅码）、`notes`（`dto/types.go:642-650`；`type` / `value` 不能改，`REDEEM_CODE_CORE_FIELDS_IMMUTABLE`）。响应只有 `{updated, message}`，保存后 `GET /admin/redeem-codes/:id` 取最新。
- 订阅分组选项：分组目录（50 章缓存的 `groups/all?include_inactive=true`）里 `subscription_type == "subscription"` 且 `status == "active"` 的分组。

#### 9.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 顶部对象条 | `code`、`type`、面值 | “a3f0····d4e8” + “余额 · $10.00 · 面值生成后不能改” | — |
| 已使用横幅（`redeemed`） | `user`、`used_at` | “已使用的兑换码只能改备注。” + “使用者 小王 · 10/16 09:20” | — |
| 只读行（`redeemed`） | 状态、订阅分组、过期时间 | 只读 | — |
| 状态（未使用 / 已禁用） | `status` | 分段“未使用 / 已禁用”，脚注“禁用后不能再兑换，可以随时重新启用。” | — |
| 状态（已过期且未兑换） | — | 只读“已过期”；选了新过期时间后显示“已过期 → **未使用**” | — |
| 订阅分组 | `group_id` | 选项胶囊 | 只在订阅码且非 `redeemed` 时显示 |
| 过期时间 | `expires_at` | 选项：“保持 10/23 09:12”（或“…（已过期）”，有原过期时间时才有）/ 永不过期 / 1 天 / 3 天 / 7 天 / 30 天 / 自定义（`DatePicker` 日期 + 时间，下限为当前时间） | 已过期码分区标题“新的过期时间”，排在最前；脚注按设计稿：“选一个新的过期时间即可续期；保持原时间只改备注。” / “保存后 10/30 09:41 过期，状态改回“未使用”。” |
| 备注 | `notes` | 多行输入，占位“例如：活动批次、工单号”，脚注“只有管理员看得到。” | — |

#### 9.4 交互与写操作

- 计算 `fields`：
  - `redeemed`：只 `notes`。
  - 未使用 / 已禁用：`status`（改了才放）、`group_id`、`expires_at`（选项换算：N 天 = 现在 + N × 24h；永不过期 = `null`；保持 = 不放）、`notes`。
  - 已过期且未兑换：选了新时间 → `expires_at` + `"status":"unused"`；保持 → 只 `notes`。
  - `fields` 为空时“保存”置灰（避免 `REDEEM_CODE_BATCH_UPDATE_EMPTY`）；自定义时间不晚于现在时置灰并在脚注写“过期时间要晚于现在。”
- 成功：关 sheet；toast：续期“已续期 · 10/30 过期，改回未使用”（永不过期写“永不过期”）；只改备注“已保存备注”；其他“已保存兑换码”。刷新该卡与 stats。
- reason：`REDEEM_CODE_USED`（409）→ sheet 不关，切成“只改备注”模式并提示“这个码已被兑换，只能改备注”；`REDEEM_CODE_EXPIRES_AT_INVALID`“过期时间要晚于现在”；`REDEEM_CODE_STATUS_INVALID`、`REDEEM_CODE_GROUP_ID_INVALID`“分组无效，请重新选择”；其余通用。
- 没有幂等键（绝对值写入，超时后重发结果相同）；超时提示“结果未确认”，用户可原样重试。

#### 9.5 状态

保存中按钮转圈、表单禁用、`.interactiveDismissDisabled`。

#### 9.6 刷新策略

不刷新；打开时以列表数据为准。

#### 9.7 对现有代码的改动点

新增 `NativeApp/Features/Redeem/RedeemEditSheet.swift`；接口用 8.7 的 `updateRedeemCodes`。

---

### 10. 批量生成兑换码（分步向导 `redeemGenerate`）

#### 10.1 入口与导航

- 兑换码 `+`（8.4 的待核对拦截之后）。sheet 内 `NavigationStack`，步骤条“类型 · 面额与数量 · 有效期”；左上第 1 步“取消”，之后“上一步”。Face ID 验证中不可下滑关闭（`.interactiveDismissDisabled`）。
- 完成后同一 sheet 换成“生成结果”；超时换成“结果待核对”（第 11 节）。

#### 10.2 数据来源

- 订阅分组选项：同 9.2。
- 生成：`POST /admin/redeem-codes/generate`，请求头 `Idempotency-Key: <batchID>`，请求体（`handler/admin/redeem_handler.go:37-49`）：

| 类型 | 请求体 |
|---|---|
| 余额 | `{"type":"balance","value":10,"count":20,"expires_in_days":7?,"notes":"…"?,"batch_id":"<batchID>"}` |
| 并发数 | `{"type":"concurrency","value":2,"count":5,…}` |
| 订阅 | `{"type":"subscription","value":0,"group_id":3,"validity_days":30,"count":5,…}` |
| 邀请码 | `{"type":"invitation","value":0,"count":10,…}` |

  `count` 1–100；`expires_in_days` 1–3650，永不过期时不传；`notes` ≤ 1000 字；`batch_id` 与幂等键是同一个 UUID（G03：同一 `batch_id` 且参数一致时直接返回已有整批，不受幂等 24 小时限制）。
- 响应：`AdminRedeemCode` 数组（真实码值，含重放：重放时后端按 `batch_id` 重新查库，`redeem_handler.go:221-228`）；响应头 `X-Redeem-Batch-ID`、`X-Idempotency-Replayed`。请求超时设 45 秒（后端带 key 的资金写执行上限 30 秒，`idempotency_helper.go:155`）。

#### 10.3 字段 → 显示映射

| 步骤 / 元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 第 1 步 · 类型磁贴 | 固定 | 余额“余额金额（美元），兑换后计入用户余额。”；并发数“并发数增量，兑换后提高用户的并发上限。”；订阅“兑换后开通或延长所选订阅分组。”；邀请码“邀请码用于限制用户注册，使用后自动标记为已使用。”；点磁贴即进第 2 步；脚注“点一个类型进入下一步；生成前会再确认一次。” | — |
| 第 2 步 · 余额 | 大数字键盘 | 大字“$10”；下方“每个兑换码的面值 · 合计 **$200.00**”；规则同 KeypadSheet：最多 2 位小数、不以 0 开头、最多 6 位数字 | 未输入时“$0”灰色，“下一步”置灰 |
| 第 2 步 · 并发数 | 步进器 1–50 | “增加并发 +2” | — |
| 第 2 步 · 订阅 | 分组胶囊 + 有效天数 | 天数选项 7 / 30（默认）/ 90 / 自定义（1–3650） | 没有订阅分组时“站点还没有订阅类型的分组”，“下一步”置灰 |
| 第 2 步 · 邀请码 | — | 只显示说明 | — |
| 第 2 步 · 数量 | 步进器 1–100 + 快捷 1 / 10 / 20 / 50 / 100 个 | 默认 1（同 Web） | — |
| 第 3 步 · 兑换码过期 | 选项 | 永不过期（默认）/ 1 天 / 3 天 / 7 天 / 自定义天数（1–3650） | — |
| 第 3 步 · 备注 | `notes` | 单行可展开输入，占位“活动批次、工单号（选填）”（G03 新增，设计稿当时后端没有，见未决问题 6） | — |
| 第 3 步 · 收据 | 汇总 | 类型 / 每个“$10.00” / 数量“× 20” / 过期“7 天后过期（10/23）”或“永不过期” / 合计“$200.00”（只余额） | — |
| Face ID 提示 | 余额且 `faceID.enabled` 且合计 > 门槛 | “合计超过 $100，确认后验证 Face ID。” | — |
| 提交按钮 | — | “生成 20 个兑换码”；校验不过时置灰 | — |
| 确认框 | 汇总 | 余额：标题“生成 20 个余额兑换码，合计 $200.00？”，正文“站点 主站 · 每个 $10.00\n7 天后过期（10/23）”（+ Face ID 行），红色按钮“生成 $200.00”；其他类型：标题“生成 5 个并发数兑换码？”，普通按钮“生成 5 个” | — |
| 结果 · 头部 | 响应数组 | 绿色勾 + “已生成 20 个兑换码”；重放时“已生成 20 个兑换码（服务器已有这一批，已取回）”；第二行“余额 · 每个 $10.00 · 10/23 过期” | — |
| 结果 · 全部复制 | 全部 `code` | “全部复制（20 个，每行一个）”，复制后变“已复制全部 20 个” | 只有 1 个时“复制兑换码” |
| 结果 · 码列表 | `code` | 序号 + 完整码（16 + 16 两行，等宽）+ 单个复制 | — |
| 结果 · 脚注 | 固定 | “关闭后在列表的“今天生成”里能找到它们；导出 CSV 请在 Web 操作。” | — |

#### 10.4 交互与写操作

1. 点“生成…”→ 确认框 → （需要时）Face ID → 生成 `batchID = UUID()`，**先**写本机待核对记录（第 11 节，状态“发送中”），再发请求。
2. 结果分支：

| 结果 | 动作 |
|---|---|
| 200 | 删除本机记录 → 结果页；列表重载第 1 页 + stats |
| 超时 / 网络错误 / 5xx（含 `503 IDEMPOTENCY_STORE_UNAVAILABLE`） | 保留记录 → “结果待核对”页（11） |
| `409 IDEMPOTENCY_IN_PROGRESS` | 按 `Retry-After`（上限 10 秒）等待后同 key 同体重试，最多 3 次；仍是此码 → 待核对页 |
| `409 IDEMPOTENCY_RETRY_BACKOFF` | 等 `Retry-After` 后同 key 重试一次 |
| `409 REDEEM_BATCH_CONFLICT` | 删除记录，提示“这个编号已用于参数不同的一批兑换码，请重新生成”（App 正常不会触发） |
| `409 REDEEM_CODE_EXPIRED` / 其他 4xx | 删除记录，显示错误（如“过期时间无效”），回到第 3 步 |

3. 结果页“完成”关 sheet。码值只在内存，关闭后丢弃（列表里随时可再看）。
4. 资金确认：余额类按 BUILDER_GUIDE “资金操作必须二次确认，写明对象、站点、金额；不给默认金额”——面值无默认值，数量默认 1。

#### 10.5 状态

| 情况 | 显示 |
|---|---|
| 发送中 | 提交按钮“正在生成…”，sheet 不可关闭 |
| Face ID 中 | 覆盖层“Face ID · 验证后生成兑换码”，取消验证 = 不发请求、删掉刚写的记录 |
| 本机待核对文件不可写 | 不发请求，提示“未决记录无法保存，已暂停生成”（同余额调整的现有规则） |

#### 10.6 刷新策略

不适用。

#### 10.7 对现有代码的改动点

- 新增 `NativeApp/Features/Redeem/RedeemGenerateSheet.swift`（三步 + 结果页 + 待核对页切换）。
- `Sources/Sub2Core/RedeemCodes.swift` 增加 `RedeemGenerateSpec`（Codable，生成请求体，金额用 `Decimal` 编码成 JSON number、最多 2 位小数）与 `APIClient.generateRedeemCodes(spec:batchID:) -> (codes, replayed: Bool)`；`APIClient.request` 需要能返回响应头（`X-Idempotency-Replayed`、`X-Redeem-Batch-ID`、`Retry-After`），由通用约定章节统一加 `requestWithResponse`。
- 键盘复用用户章节 KeypadSheet 的输入规则（提取为 `KeypadInput` 纯函数，便于单测）。

---

### 11. 生成结果待核对（本机记录、横幅、核对 sheet）

#### 11.1 入口与导航

- 生成超时后的“结果待核对”页（生成 sheet 内）；兑换码列表顶部横幅“核对”；概览待处理“兑换码生成结果待核对”（10 章）→ `.redeem(reconcile: true)`；设置 → 待核对 → 兑换码批次。
- 核对结果在 sheet 里显示（同 10.3 的结果页，标题“核对结果”）。

#### 11.2 数据来源

- **本机记录** `PendingRedeemBatch`（新增，持久化到 `Application Support/Sub2Mobile/pending-redeem-batches.json`，`.completeFileProtection`，读失败时禁止新的生成，同现有 `pendingBalances`）：`id`（= batchID = 幂等键）、`serverID`、`spec`（类型、面值、数量、`group_id`、分组名、有效天数、`expires_in_days`、备注）、`count`、`total`（只余额 = 面值 × 数量，其他为 nil）、`createdAt`。10 章的待处理行读它的 `count`、`total`、`createdAt`。
- **核对**：`GET /admin/redeem-codes?batch_id=<id>&page=1&page_size=100&sort_by=id&sort_order=asc`（G03 过滤；不带 `types` / `status`）。
- **用同一编号重试**：与 10.2 完全相同的请求（同一 key、同一请求体）。

#### 11.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 列表横幅 | 当前站点的记录（多条时取最早一条，标题后加“等 N 批”） | caution 横幅 + 图标；标题“兑换码生成结果待核对”；第二行“20 个 × $10.00 · 合计 $200.00”；第三行“5 分钟前发起，未确认是否已生成”；按钮“核对”（从概览进入时为主样式） | 非余额类不写合计 |
| 待核对页 · 头部 | — | 沙漏 + “请求可能已提交” + “没有收到服务器确认。不要重新生成，先核对。” | — |
| 待核对页 · 收据 | 记录 | 内容“20 个 × $10.00”；合计“$200.00”；发起“主站 · 10/16 09:36”；幂等编号（完整 UUID，等宽，可选中） | — |
| 待核对页 · 按钮 | — | “核对生成结果”（主）/“用同一编号重试” | — |
| 待核对页 · 脚注 | 固定 | “编号已保存在本机。核对会按这个编号在服务器上找这一批；用同一编号重试时，服务器生成过就直接返回那一批，不会重复生成。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。” | — |
| 没找到页 | 核对结果 `total == 0` | 放大镜 + “服务器上没有这一批” + “这次生成没有生效。用同一编号重试，或者放弃。”；按钮“用同一编号重试”（主）/“放弃这一批”；脚注“重试用的是本机保存的同一个编号，服务器最多生成一批。” | — |
| 核对结果页 | 核对返回的码 | 同 10.3 结果页，头部“已核对：服务器已生成 20 个”，脚注“这一批是 10/16 09:36 发起时生成的，已在列表的“今天生成”里；导出 CSV 请在 Web 操作。” | — |

#### 11.4 交互与写操作

- **核对**：`total == count` → 删除记录 → 核对结果页；`total == 0` → 没找到页；`0 < total < count`（整批一个事务，正常不会出现）→ 显示找到的码 + caution“数量与发起时不符，请到 Web 核对”，记录保留到用户点“我已核对”。
- **用同一编号重试**：同 10.4 第 2 步的分支表；成功（含重放）→ 删除记录 → 结果页。
- **放弃这一批**：删除记录，toast “已放弃这一批 · 不再提醒”。
- 概览待处理、横幅、设置里的同一条记录共用，任何一处核对完成后其余立即消失。
- **老服务端退路**（无 `redeem_codes.stats`、响应没有 `X-Redeem-Batch-ID`）：重试只能同 key 重放，重放里的码值是 `***`，按返回的 `id` 逐个 `GET /admin/redeem-codes/:id` 取真码；核对改为 `sort_by=created_at&sort_order=desc&page_size=100` 后按类型、面值、发起后 2 分钟内、数量启发式匹配，并提示“另一位管理员同时生成时可能分不清”（附录 G03 App 退路）。

#### 11.5 状态

核对 / 重试中按钮“正在核对…”/“正在用同一编号重试…”，两个按钮都禁用；核对请求失败 → 提示“核对失败，请稍后再试”，记录保留。

#### 11.6 刷新策略

不自动核对（避免在网络恢复前误判“没找到”）；用户点“核对”才发请求。列表横幅随本机记录即时出现 / 消失。

#### 11.7 对现有代码的改动点

- `NativeApp/Session/AppModel.swift`：新增 `pendingRedeemBatches`、`rememberRedeemBatch(_:)`、`resolveRedeemBatch(_:)`、持久化文件（照 `remember / resolve / persistPending` 写，独立文件，失败标志与余额共用“未决记录不可读”提示）。
- `Sources/Sub2Core/RedeemCodes.swift`：`PendingRedeemBatch`（Codable）。
- 新增 `NativeApp/Features/Redeem/RedeemReconcileView.swift`（待核对页、没找到页、核对结果页三态）。

---

### 12. 代理列表（`proxies`）

#### 12.1 入口与导航

- 目录 → 代理。导航栏：返回 + 标题“代理” + 副标题“<站点名> · N 个” + 右上“全部测试”（文字按钮，测试中为“测试中…”）与 `+`（添加 sheet）。
- 点行 → 代理详情。

#### 12.2 数据来源

- `GET /admin/proxies?page=<p>&page_size=200&sort_by=id&sort_order=desc`，循环拉完所有页（代理通常很少；胶囊与横幅需要全集）。
- 列表项 `dto.AdminProxyWithAccountCount`（`handler/dto/types.go:462-531`）：`id`、`name`、`protocol`、`host`、`port`、`username`、`password`（明文，只放内存）、`status`（`active` / `inactive` / `expired`）、`created_at`、`expires_at`（RFC3339，可为 null）、`fallback_mode`（`none` / `proxy` / `direct`）、`backup_proxy_id`、`expiry_warn_days`、`account_count`（`proxy_id` 指向它的账号）、`fallback_account_count`（H03）、`latency_ms`、`latency_status`（`success` / `failed`，未探测过不返回）、`latency_message`、`latency_checked_at`（Unix 秒，H01）、`ip_address`、`country`、`country_code`、`region`、`city`、`quality_status`、`quality_score`、`quality_grade`、`quality_summary`、`quality_checked`（Unix 秒）。
- 测试：`POST /admin/proxies/:id/test` → `{success, message, latency_ms, ip_address, city, region, country, country_code, checked_at}`（`service/admin_service.go:663-673`；失败也是 200 + `success:false`）。
- vendor：读需 `proxy_manage || account_manage`；“全部测试”与 `+` 需 `proxy_manage`。

#### 12.3 字段 → 显示映射

**到期计算 `proxyExpiry`**（按服务器时区的自然日差 `d = days(expires_at) − today`，设计稿 `shared/data.jsx:526-535`）：`status == expired` →“MM/DD 已过期”；`expires_at == null` →“永不过期”；`status != active` →“MM/DD 到期”；`d < 0` →“已到期 · 等待处理”（caution）；`d ≤ expiry_warn_days` →“今天到期”/“N 天后到期”（caution，记为 soon）；否则“剩余 N 天”。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 到期横幅（只在“全部”下） | `account_count > 0` 且（`expired` 或 active + soon），已过期排前，再按剩余天数 | 只有 1 个：标题“jp-tokyo-1 已过期，仍有 1 个账号在用” / “hk-02 6 天后到期，3 个账号在用”，第二行“续期，或给这些账号换代理” / “到期前续期，或设置到期回退”；多个：“N 个代理需要处理” + “jp-tokyo-1 已过期仍在用 · hk-02 6 天后到期”；有已过期的为 critical，否则 caution；按钮“查看”→ 切到“已过期”（有已过期仍在用）或“即将到期” | 无命中不显示 |
| 筛选胶囊 | 本地计算 | 全部 / 已过期（有已过期仍在用时带红点）/ 即将到期（active、有账号、soon）/ 链接失败（非停用、`latency_status == failed`、且 active 或有账号）/ 停用；每个带数量 | — |
| 列表头 | 固定 | 左“代理”，右“延迟 / 状态” | — |
| 行 · 状态胶囊 | tone | 停用：无；已过期：有账号 critical，否则无；链接失败：critical；soon：caution | — |
| 行 · 前导字形 | 状态 | 停用 / 已过期无账号：灰；已过期有账号、链接失败：错误；未测试：中性点；其他：正常 | — |
| 行 · 标题 | `name` | 原样 | — |
| 行 · 右侧 | 测试中 / 状态 / 延迟 | 测试中：“测试中”；非 active：状态徽章（正常 / 停用 / 已过期，已过期且无账号为 neutral）；active：`latency_status == success` → “182ms”，`failed` → critical 徽章“链接失败” | active 且未探测：“未测试”（灰） |
| 行 · 地址 | `protocol`、`host`、`port` | 等宽“SOCKS5 · 203.0.113.24:1080”（HTTP / HTTPS / SOCKS5 / SOCKS5H） | — |
| 行 · 底行 | `account_count`、地区、到期 | “3 个账号在用 · 中国香港”；已过期：“1 个账号仍在用 · 10/13 到期” / “没有账号在用 · 10/13 到期”；停用不写地区；soon 时右侧 caution 徽章“6 天后到期”；已过期 + 链接失败 + 有账号时再加“链接失败”徽章 | 地区 = `country_code` 用 `Locale(identifier:"zh_CN").localizedString(forRegionCode:)`，有 `city` 时追加“ · 城市”；都没有就不写 |
| 行 · 变淡 | 停用，或已过期且无账号 | idle | — |

#### 12.4 交互与写操作

- **全部测试**：对列表全部代理并发（最多 4 个）`POST /admin/proxies/:id/test`；每行在测试中显示“测试中”；每个返回后按结果更新该行（`success` → `latency_status=success`、`latency_ms`、出口 IP 与地区；失败 → `latency_status=failed`、`latency_message=message`），`latency_checked_at = checked_at`。全部结束 toast “已测试 N 个代理 · M 个失败”（有失败为 critical 色）。HTTP 错误的那一行恢复原值，计入失败。
- **添加**：`+` → 第 14 节 sheet。
- 无滑动操作。

#### 12.5 状态

| 情况 | 显示 |
|---|---|
| 加载中 | 行占位 |
| 没有代理 | “还没有代理” + “添加代理” |
| 筛选为空 | “没有这类代理” |
| 失败 | `FailureView`；已拉到部分页时显示已有数据 + 底部“加载失败 · 重试” |

#### 12.6 刷新策略

首次进入加载全部页；重新显示时超过 60 秒重载；下拉刷新；写操作 / 测试后更新对应行；不轮询，无 ETag。

#### 12.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/Proxies.swift`：`AdminProxy`（全部字段可选解码，`password` 用自定义 `CustomDebugStringConvertible` 屏蔽）、`ProxyTestResult`、`ProxyQualityResult`、`ProxyFallbackAccount`、`ProxyFallbackRevertResult`、`ProxyExpiry`（到期计算纯函数，便于单测）、`APIClient` 扩展（列表、单个、新建、修改、删除、测试、质量检测、账号、回退账号、恢复）。
- 新增 `NativeApp/Features/Proxies/ProxiesView.swift`（列表、胶囊、横幅、全部测试）。
- `Sources/Sub2Core/Models.swift:UpstreamAccount.proxy` 现只解码名称、编号（`docs/API_COMPATIBILITY.md:74`），账号章节的“代理”行改为 push `ProxyDetailView(id:)`。

---

### 13. 代理详情（`proxyDetail`，含被改走的账号）

#### 13.1 入口与导航

- 代理行（带上列表那一行，先显示再刷新）；账号详情的代理行（只有 id）；全局搜索。
- 导航栏：返回 + 标题 `name` + 副标题“SOCKS5 · 203.0.113.24:1080” + 右上 ···。
- 去向：“使用该 IP 的账号”行 → 账号详情（账号章节）；“被改走的账号 ›”→ `.proxyFallbackAccounts(id)`；编辑 / 续期 sheet。

#### 13.2 数据来源

| 用途 | 接口 | 字段 |
|---|---|---|
| 代理 | `GET /admin/proxies/:id`（H02：与列表同一 DTO，含账号数、延迟、出口 IP、质量、`fallback_account_count`） | 同 12.2；没有 `account_count` 键 = 老服务端，退回 `GET /admin/proxies?search=<名称>&page_size=100` 按 id 找（附录 H02 App 退路） |
| 使用该 IP 的账号 | `GET /admin/proxies/:id/accounts` | `[{id, name, platform, type, notes}]`（只含 `proxy_id` 指向它的账号） |
| 账号状态徽章 | 账号章节的账号状态缓存（`GET /admin/accounts/status-summary?include_accounts=true` 的 `accounts[].state`，或账号 Tab 已加载的列表） | 后端没有“按代理取账号状态” → 缓存里没有该账号就不显示徽章 |
| 备用代理名 | 列表缓存里 `backup_proxy_id` 那一项的 `name` | 不在缓存时 `GET /admin/proxies/:id` |
| 被改走的账号 | `GET /admin/proxies/:id/fallback-accounts` | `[{id, name, platform, type, notes, current_proxy_id, current_proxy_name}]`（`current_proxy_id == null` = 现在直连） |
| 测试 / 质量检测 | `POST /admin/proxies/:id/test`、`POST /admin/proxies/:id/quality-check` | 质量检测返回 `{proxy_id, score, grade, summary, exit_ip, country, country_code, base_latency_ms, passed_count, warn_count, failed_count, challenge_count, checked_at, items[]}` |

#### 13.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 状态卡 · 徽章 | `status` | 正常（ok）/ 停用（neutral）/ 已过期（有账号 critical，无账号 neutral） | — |
| 状态卡 · 说明 | 状态 | 测试中“正在测试连通性”；本次会话测过“刚刚测试 09:41”（测试响应的 `checked_at`）；停用：有账号“在用的账号不受影响”，无账号“账号编辑里选不到它” | 其他情况空 |
| 状态卡 · 色调 | 链接失败且（active 或有账号） | critical 底 + 状态胶囊 | — |
| 延迟块 | `latency_status`、`latency_ms`、`latency_message`、`latency_checked_at` | 成功：大字“182 ms” + 0–500ms 游标刻度（超过 500 指针停在最右，墨色无状态色）+ 小字“上次测试 10/16 09:12”（H01）；失败：“链接失败” + `latency_message`（等宽，错误底色） | 未探测：“— 还没测试过”；`latency_checked_at` 缺失时不写测试时间 |
| 事实三格 | `ip_address`、地区、质量 | 出口 IP（等宽）；地区（同 12.3）；质量“A · 92”+ 标签旁日期（`quality_checked` 的 MM/DD）；检测中“检测中…” | 各自“—” |
| 按钮行 | 状态 | 已过期：“续期”（主）+“测试连接”；其他：“测试连接”（主）+“编辑” | 只读身份 / vendor 无 `proxy_manage`：按钮不显示 |
| 壹 有效期 · 说明句 | 见下 | 见下 | 无说明时显示 KV 的“剩余”“到期回退” |
| 壹 · 到期日 | `expires_at` | “2026-10-22” | “永不过期” |
| 壹 · 到期提醒 | `expiry_warn_days` | “提前 7 天” | — |
| 壹 · 剩余 / 到期回退 | `proxyExpiry`、`fallback_mode`、备用名 | “剩余 132 天” / “不限”；“不回退” / “回退直连” / “备用 sg-01” | 有说明句时不显示这两项 |
| 壹 · 被改走的账号 | `fallback_account_count > 0` 且 `proxies.fallback_accounts` | 行“被改走的账号 2 个 ›” | 为 0 不显示 |
| 贰 使用该 IP 的账号 | accounts | 分区 meta“3 个”；行：账号状态字形 + 名称 + 状态徽章，第二行“platform · type” | “暂无账号使用此代理” |
| 叁 连接 | `protocol`、`port`、`host`、`username`、`password`、`created_at` | 协议、端口、主机（等宽）、用户名（等宽）、密码“••••••”、创建时间 | 用户名“—”；密码为空“未设置” |

**说明句**（`vmoExpiryNote`，按 H03 调整）：

| 条件 | tone | 文案 |
|---|---|---|
| 已过期，`account_count > 0`，回退为“不回退” | critical | “已过期，N 个账号仍在用这个代理。到期回退设的是“不回退”，所以账号没被改走；续期，或到账号编辑页换代理。” |
| 已过期，`account_count > 0`，回退不是“不回退” | critical | “已过期，N 个账号仍在用这个代理。续期，或到账号编辑页换代理。” |
| 已过期，`fallback_account_count > 0` | neutral | “到期后已把 N 个账号改为直连 / 备用 sg‑01。续期并启用后，可以在“被改走的账号”里一键恢复。”（无 `proxies.fallback_accounts` 时后半句改为“要改回来，在账号详情里点“恢复原代理”。”） |
| 已过期，其余 | neutral | “已过期，没有账号在用。” |
| 正常，`fallback_account_count > 0`（续期后还没恢复） | caution | “N 个账号在本代理到期时被改走，还没恢复。” |
| 正常，soon，回退“不回退” | caution | “6 天后到期。到期后不回退，在用的 N 个账号会继续挂在这个过期代理上。”（无账号时省略后半句） |
| 正常，soon，其他回退 | caution | “6 天后到期。到期后把在用的账号改为直连 / 备用 sg‑01。” |

（备用名里的连字符用不换行连字符，避免 `sg-01` 在连字符处折行。）

#### 13.4 交互与写操作

- **测试连接**：`POST …/test`，按 12.4 更新；说明改为“刚刚测试 HH:MM”。
- **··· 菜单**（标题 `name`，说明“SOCKS5 · host:port”）：编辑代理；复制代理 URL；质量检测；停用代理 / 启用代理 / 续期…（已过期）；删除代理…（红，最后）。
- **复制代理 URL**：本地拼 `protocol://[username[:password]@]host:port`（用户名、密码做 URL 编码），按 0.4 写剪贴板，toast “已复制代理 URL”。
- **质量检测**：`POST …/quality-check`，事实格显示“检测中…”；成功 toast “质量检测完成：评分 92（A）”并更新质量格（`grade`、`score`、`checked_at`）；失败 toast “代理质量检测失败”（critical）。
- **停用 / 启用**：`PUT /admin/proxies/:id`，`{"status":"inactive"}` / `{"status":"active"}`，直接执行；toast “已停用 hk-02 · 在用的 3 个账号不受影响”（无账号时“已停用 hk-02”）/“已启用 hk-02”，带撤销。停用不影响已绑定账号的流量，只是账号编辑里选不到、也不会被选作备用。
- **续期**：打开编辑 sheet（续期模式）。
- **删除**：
  - `account_count > 0` → 说明框“不能删除「hk-02」”：“该代理已有 3 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。”（只有“知道了”）。
  - `fallback_account_count > 0` → 说明框“不能删除「us-east-2」”：“2 个账号到期时从这个代理改走，删除后它们就恢复不了原代理。先恢复这些账号，或在账号详情里处理。”，按钮“查看被改走的账号”/“知道了”。
  - 否则删除确认（输入完整名称 / Face ID）→ `DELETE /admin/proxies/:id` → 返回上一页，toast “已删除代理「名称」”。`409 PROXY_IN_USE` → 有 `metadata.fallback_account_count` 时弹上面第二个说明框，否则弹第一个（重新拉详情取数量）；`404 PROXY_NOT_FOUND` 视为已删除。
- **被改走的账号页**（`.proxyFallbackAccounts(id)`，标题“被改走的账号”，副标题代理名）：
  - 行：名称；第二行“platform · type · 现在：直连”/“现在：备用 sg-01”（`current_proxy_name`）；点行 → 账号详情。
  - 底部主按钮“全部恢复到 hk-02”：仅当代理 `status == active` 且未过期时可点，否则置灰并写“先续期并启用这个代理”。点后确认框“把 N 个账号改回走 hk-02？它们的出口 IP 会变回 203.0.113.24。”→ `POST /admin/proxies/:id/fallback-accounts/revert`，请求体 `{}`（全部，单次最多 500）。
  - 行滑动“恢复”：同一接口，`{"account_ids":[id]}`。
  - 结果 `{reverted_ids, skipped:[{id,code,message}], failed:[{id,code,message}]}`：toast “已恢复 N 个账号到 hk-02”；有 `skipped`（`ACCOUNT_NOT_IN_FALLBACK` / `ACCOUNT_NOT_FALLBACK_OF_PROXY`）时追加“M 个已不在回退状态，已跳过”；有 `failed` 时页内列出失败账号与原因。之后重拉本页、详情与列表。
  - `409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE` →“原代理仍已过期或已停用，请先续期或启用后再恢复”。vendor 需 `proxy_manage && account_manage`。
  - 无 `proxies.fallback_accounts`：没有本页（说明句改写见上）。
- 本页写入都不带幂等键（PUT 绝对值；revert 重复调用安全，H03）。

#### 13.5 状态

| 情况 | 显示 |
|---|---|
| 从账号详情进入加载中 | 状态卡占位 |
| `404 PROXY_NOT_FOUND` | “已删除”空页（设计稿 `VmoGone`） |
| 账号列表 / 回退列表失败 | 该分区一行“暂时无法加载 · 重试”，其余照常 |
| 测试请求 HTTP 失败 | toast “测试请求失败，请稍后再试”，延迟块保持原值 |

#### 13.6 刷新策略

进入时 `GET :id` + `:id/accounts`；下拉刷新两者；编辑保存后若改了协议、主机、端口、用户名或密码，延迟块改为“地址已修改，正在重新测试”，5 秒后 `GET :id` 一次（H04：后端已自动清缓存并重新探测，App 不要再调 test）；测试 / 质量检测后本地更新。不轮询。

#### 13.7 对现有代码的改动点

- 新增 `NativeApp/Features/Proxies/ProxyDetailView.swift`（`init(id:seed:)`，seed 为列表行）、`ProxyFallbackAccountsView.swift`、`ProxyLatencyBlock.swift`（刻度与读数，列表可复用读数格式）。
- 账号状态徽章读账号章节提供的共享状态缓存（不在本章新建请求）。

---

### 14. 编辑 / 添加 / 续期代理 sheet（`proxyEdit`）

#### 14.1 入口与导航

- 代理 `+`（添加）、详情“编辑” / ···“编辑代理”（编辑）、已过期代理的“续期”（续期模式）。标题“添加代理 / 编辑代理 / 续期代理”；左上“取消”，右上“添加 / 保存 / 续期”。续期模式顶部对象条“jp-tokyo-1 · SOCKS5H · 192.0.2.88:1080 · 1 个账号仍在用”。

#### 14.2 数据来源

- 编辑预填来自详情 / 列表数据（密码不预填）。
- 备用代理候选：代理列表缓存里除自己外的全部代理；可选条件 `status == active` 且未过期（后端回退链会跳过停用或过期的代理），不可选的置灰并标“停用”/“已过期”。
- 添加：`POST /admin/proxies`（可选幂等，scope `admin.proxies.create`），请求体 `{name, protocol, host, port, username, password, expires_at?, fallback_mode, backup_proxy_id?, expiry_warn_days}`；**`expires_at` 是 Unix 秒**（`handler/admin/proxy_handler.go:29-40`），响应 `AdminProxy`（不含延迟；后端新建后异步探测）。
- 编辑：`PUT /admin/proxies/:id`，只放改过的键：`name`、`protocol`、`host`、`port`、`username`（`""` = 清空）、`password`（只在用户输入时放）、`status`（只能 `active` / `inactive`）、`expires_at`（Unix 秒；`null` 或 `0` = 永不过期）、`fallback_mode`、`backup_proxy_id`（`null` = 清除）、`expiry_warn_days`（`proxy_handler.go:43-55`）。

#### 14.3 字段 → 显示映射

| 分区 / 元素 | 字段 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 名称与协议 | `name`、`protocol` | 名称（占位“请输入代理名称”）；协议分段 HTTP / HTTPS / SOCKS5（添加默认）/ SOCKS5H；选 SOCKS5H 时脚注“SOCKS5H 由代理服务器解析域名（远程 DNS）。” | — |
| 地址 | `host`、`port` | 主机（等宽，占位“请输入主机地址”）；端口（数字键盘，最多 5 位） | 端口越界脚注“端口必须在 1-65535 之间” |
| 认证（可选） | `username`、`password` | 用户名（等宽）；密码（安全输入，编辑时占位“留空保持不变”） | — |
| 有效期 | `expires_at`、`expiry_warn_days` | 选项：保持 <日期>（编辑且有到期日时；已过期写“（已过期）”）/ 永不过期 / 30 天 / 90 天 / 自定义（天数）；“到期提醒提前”步进器 1–30 天（默认 7）；脚注“到期前按提醒天数在代理列表和告警里提示。”；续期模式标题“有效期 · 续期”，脚注“10/13 已过期。选一个新的有效期来续期。” | 添加默认永不过期 |
| 到期回退 | `fallback_mode`、`backup_proxy_id` | 分段“不回退 / 回退直连 / 备用代理”；选备用代理时出现候选胶囊；脚注：备用“回退链会跳过停用或已过期的代理，所以它们不能选作备用。”；直连“到期后把在用的账号改为直连，可在账号详情里“恢复原代理”。”；不回退“到期后账号留在这个过期代理上，需要手动处理。” | — |
| 状态（仅编辑） | `status` | 分段“正常 / 停用”；已过期代理打开时预设“停用”（PUT 只收 active / inactive，同 Web），选了新有效期自动切回“正常”；脚注按设计稿（`statusFoot`） | — |
| 分区顺序 | 模式 | 续期：有效期 → 状态 → 到期回退 → 名称地址认证；其他：名称地址认证 → 有效期 → 到期回退 → 状态 | — |

#### 14.4 交互与写操作

- **校验**：名称、主机非空；端口 1–65535；回退选备用时必须选一个；已过期 + 保持原有效期 + 状态“正常”不允许（脚注“有效期已过，改回“正常”前先在上面选新的有效期。”）。不满足时右上按钮置灰。
- **有效期换算**：N 天 = 现在 + N × 86400 秒；永不过期：添加时不传，编辑时传 `null`。
- **添加**：带 `Idempotency-Key`（sheet 打开时生成；失败后原样重试沿用，改了表单换新 key）→ 成功关 sheet，toast “代理添加成功”带撤销（撤销 = `DELETE /admin/proxies/:id`，此时还没有账号在用）；重载列表，3 秒后 `GET :id` 取探测结果。
- **编辑**：成功关 sheet；toast：续期“已续期 · jp-tokyo-1 恢复正常”，其他“代理更新成功”；改了网络字段时按 13.6 进入“正在重新测试”。
- **reason**：`PROXY_BACKUP_REQUIRED`“选了备用代理回退，请选择一个备用代理”；`PROXY_BACKUP_SELF`“备用代理不能是它自己”；`PROXY_WARN_DAYS_INVALID`、`PROXY_EXPIRY_INVALID`（App 不会发出）；`404 PROXY_NOT_FOUND`（备用代理不存在或不属于本工作区）“备用代理已不存在，请重新选择”；幂等类 reason 走通用处理。编辑超时（无幂等）：提示结果未确认，`GET :id` 读回比对后再决定是否重发。
- 有未保存修改时下滑关闭先确认“放弃修改？”。

#### 14.5 状态

保存中右上转圈、表单禁用。

#### 14.6 刷新策略

不适用。

#### 14.7 对现有代码的改动点

新增 `NativeApp/Features/Proxies/ProxyEditSheet.swift`；`Sources/Sub2Core/Proxies.swift` 的 `ProxyCreateRequest` / `ProxyUpdateRequest`（`username` / `password` / `expires_at` / `backup_proxy_id` 需区分“不传”与 `null`，自定义 `encode(to:)`，参照 `GroupManagement.swift:GroupLimitChange`）。

---

### 15. 公告列表（`announcements`）

#### 15.1 入口与导航

- 目录 → 公告。导航栏：返回 + 标题“公告” + 副标题“<站点名> · N 条” + 右上 compose（新建 sheet）。点行 → 公告详情。

#### 15.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 列表 | `GET /admin/announcements` | `page`、`page_size=20`、`sort_by=created_at`、`sort_order=desc`、`status=active\|draft\|archived`（分段，“全部”不传）、`include_read_stats=true`（有 `announcements.read_stats` 时） |
| 列表项 | `dto.Announcement`（`handler/dto/announcement.go:9-29`） | `id`、`title`、`content`、`status`（`draft` / `active` / `archived`）、`notify_mode`（`silent` / `popup`）、`targeting{any_of:[{all_of:[{type, operator, group_ids?, value?}]}]}`、`starts_at`、`ends_at`（RFC3339，可缺）、`created_by`、`updated_by`、`created_at`、`updated_at`、`read_stats{eligible_count, read_count, eligible_read_count}`（带参数时） |
| 分段计数 | 同一接口 `page_size=1`，四路并行（不带 status / 各 status）取 `total` | 后端没有公告统计接口 → App 退路 |
| 订阅条件的分组名 | 分组目录缓存（`groups/all?include_inactive=true`） | `group_ids` → 名称 |

vendor 不可见。

#### 15.3 字段 → 显示映射

**可见对象文案**：`any_of` 为空 →“所有用户”；否则每组内条件用“ 且 ”连接，组之间用“ 或 ”连接；条件：`subscription` →“订阅 企业专线、高级组”；`balance` →“余额 < $5.00”（`gt` >、`gte` ≥、`lt` <、`lte` ≤、`eq` =）。

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 分段 | 四路 `total` | 全部 5 / 展示中 2 / 草稿 1 / 已归档 2 | 计数失败只显示名称 |
| 行 · 标题 + 徽章 | `title`、`status` | 草稿（neutral）/ 展示中（ok）/ 已归档（neutral） | — |
| 行 · 第二行 | `targeting` | 可见对象文案（一行截断） | 分组名查不到时“分组 #3” |
| 行 · 第三行 | `notify_mode`、时间 | 图标（弹窗 megaphone / 静默 bell）+ “弹窗 · 10/16 08:00 – 10/18 06:00”（`starts_at` 缺省“立即”，`ends_at` 缺省“永久”）；草稿为“静默 · 更新于 10/16 09:05”；展示中但未到开始时间追加“（未开始）”，已过结束时间追加“（已结束）” | — |
| 行 · 已读进度 | `read_stats`（非草稿） | 第三行右侧“已读 410/1036”（`eligible_read_count / eligible_count`） | 无 capability 不显示（未决问题 5） |
| 行 · 变淡 | `status == archived` | idle | — |

时间按本机时区显示（与编辑页“时间按本机时区”一致）。

#### 15.4 交互与写操作

点行 push；compose 新建；无滑动、无写操作。

#### 15.5 状态

| 情况 | 显示 |
|---|---|
| 没有公告 | “还没有公告” + “新建公告” |
| 分段为空 | “没有这类公告” |
| 失败 | `FailureView` |

#### 15.6 刷新策略

首次进入加载；重新显示超过 60 秒重载；下拉刷新；触底加载下一页；详情 / 编辑写操作后重载第 1 页与计数。不轮询。

#### 15.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/Announcements.swift`：`Announcement`、`AnnouncementTargeting` / `ConditionGroup` / `Condition`（Codable，与后端 `domain/announcement.go:40-64` 同形）、`AnnouncementReadStats`、`AnnouncementReadSummary`、`AnnouncementReadStatusRow`、`AnnouncementCreateRequest` / `UpdateRequest`、`AnnouncementPresentation.targetText(_:groupNames:)`、`APIClient` 扩展。
- 新增 `NativeApp/Features/Announcements/AnnouncementsView.swift`。

---

### 16. 公告详情（`announcementDetail`）

#### 16.1 入口与导航

- 公告行。导航栏：返回 + 标题“公告” + 副标题“展示中 · 弹窗” + 右上 ···。
- 去向：已读情况（第 18 节）、编辑 sheet（第 17 节）。

#### 16.2 数据来源

- `GET /admin/announcements/:id`（有 capability 时带 `include_read_stats=true`）。
- `GET /admin/announcements/:id/read-summary`（有 `announcements.read_stats` 且非草稿）→ `{announcement_id, total_users, eligible_count, read_count, eligible_read_count, computed_at}`（`computed_at` 为 RFC3339 UTC；只统计未删除用户；eligible 按当前余额与当前有效订阅计算；`read_count` 含读后已不符合条件的人）。

#### 16.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 预览卡 | `title`、`content`、`notify_mode` | 标签“用户看到的样子 · 弹窗 / 静默”；弹窗：居中卡片 + 底部“知道了”按钮样式；静默：带左侧轨的通知卡；正文按最小 Markdown 渲染（`## 小标题`、`- 列表`、`**粗体**`、`[链接](地址)`、空行分段） | 标题空“未命名公告”；正文空“还没有正文”（灰） |
| 按钮行 | `status` | 草稿：“发布”（主）+“编辑”；展示中：“归档”+“编辑”（主）；已归档：“重新发布”+“编辑”（主） | 只读身份不显示 |
| 壹 投放 · 可见对象 | `targeting` | 15.3 的文案（可换行） | — |
| · 通知方式 | `notify_mode` | 静默 / 弹窗 | — |
| · 开始时间 / 结束时间 | `starts_at` / `ends_at` | “10/16 08:00” | “立即” / “永久” |
| · 已读情况 | read-summary | 有 capability：标题“已读情况”，右侧“已读 410 / 符合条件 1036”，第二行“40% · 另有 2 人读后已不符合条件 · 统计于 09:41”（`read_count − eligible_read_count > 0` 才写中间一句）；无 capability：第二行“逐个用户看：是否符合条件、什么时候读的” | 草稿不显示本行；summary 失败退回无 capability 的文案 |
| 贰 档案 | `created_at`、`updated_at` | 创建时间、更新时间 | — |

#### 16.4 交互与写操作

- **发布 / 重新发布**：确认框标题“发布「标题」？”，正文“<可见对象> · 用户打开时弹窗提示 / 静默出现在通知里\n有效期 <开始> – <结束>”，按钮“发布”/“取消” → `PUT /admin/announcements/:id`，`{"status":"active"}` → toast “已发布 · 符合条件的用户能看到”。
- **归档**：直接 `PUT …`，`{"status":"archived"}`；toast “已归档 · 用户不再看到”，撤销 = 写回原状态。
- **··· 菜单**（标题为公告标题，说明“展示中 · 弹窗”）：编辑公告；归档（展示中）/ 发布 / 重新发布；已读情况（非草稿）；删除公告…（红，最后）。
- **删除**：删除确认（输入完整标题 / Face ID）→ `DELETE /admin/announcements/:id` → 返回列表，toast “已删除公告「标题」”；`404 ANNOUNCEMENT_NOT_FOUND` 视为已删除。
- reason：`ANNOUNCEMENT_STATUS_INVALID`（App 不会发出）；其余通用。PUT / DELETE 不带幂等键（天然幂等）。

#### 16.5 状态

`404` → “已删除”空页；加载中预览卡占位；写操作中按钮转圈。

#### 16.6 刷新策略

进入时加载详情与 summary；下拉刷新；写操作后重载。不轮询。

#### 16.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementDetailView.swift`、`AnnouncementPreviewCard.swift`、`MiniMarkdownView.swift`（块级只认 `##`、`-`、空行分段，行内用 `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`）。

---

### 17. 编辑 / 新建公告 sheet（`announcementEdit`）

#### 17.1 入口与导航

- 公告列表 compose（新建）；详情“编辑”/ ···“编辑公告”。标题“新建公告 / 编辑公告”；左上“取消”；右上“存草稿”（新建、草稿）或“保存”（展示中、已归档）；底部主按钮“发布”（新建、草稿）/“重新发布”（已归档），展示中没有底部按钮。
- 顶部分段“编辑 / 预览”。

#### 17.2 数据来源

- 编辑预填来自详情。订阅分组选项：分组目录里 `subscription_type == "subscription"` 且 `status == "active"`。
- 新建：`POST /admin/announcements`，请求 `{title, content, status, notify_mode, targeting, starts_at?, ends_at?}`（`starts_at` / `ends_at` 为 Unix 秒，缺省 = 立即 / 永久），有 `announcements.idempotent_create` 时带 `Idempotency-Key`（scope `admin.announcements.create`，带 key 时后端执行上限 30 秒）。
- 编辑：`PUT /admin/announcements/:id`，只放改过的键：`title`、`content`、`status`、`notify_mode`、`targeting`、`starts_at`、`ends_at`（`0` = 清空，即改回立即 / 永久）。

#### 17.3 字段 → 显示映射

| 分区 / 元素 | 字段 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 内容 · 标题 | `title` | 单行输入，占位“标题” | 超过 200 字节（后端按字节计，`service/announcement_service.go:82`）时脚注“标题太长（最多约 66 个汉字）” |
| 内容 · 格式工具条 | — | 粗体 / 列表 / 小标题 / 链接（在光标处插入 `**粗体**`、`\n- 列表项`、`\n## 小标题`、`[链接文字](https://)` 并选中示例文字）；右侧“N 字” | — |
| 内容 · 正文 | `content` | 多行，占位“写点什么…”；脚注“支持 Markdown：**粗体**、- 列表、## 小标题、[链接](地址)。” | — |
| 可见对象 | `targeting` | 分段“所有用户 / 按条件”；按条件时：分段“订阅套餐 / 余额”；订阅：“持有以下任一套餐”多选胶囊（`{type:"subscription", operator:"in", group_ids:[…]}`）；余额：比较符胶囊 > ≥ < ≤ + “$”金额（`{type:"balance", operator:"lt", value:5}`）。脚注：所有用户“所有用户都能看到。”；按条件“手机上设一个条件；多个条件组合请在 Web 编辑。” | 现有公告是多组 / 多条件：只读显示“条件 … / 或 …”，脚注“这条公告的条件有多组 / 多条，手机上只读；要修改请在 Web 编辑。” |
| 通知方式 | `notify_mode` | 分段“静默 / 弹窗”；脚注“静默：只出现在用户的通知列表里。”/“弹窗模式会自动弹出通知给用户。” | 新建默认静默 |
| 有效期 | `starts_at`、`ends_at` | 开始：“立即 / 指定时间”，结束：“永久 / 指定时间”；指定时间为日期 + 时间两个胶囊（`DatePicker(.compact)`）；脚注“立即 = 开始时间留空；永久 = 结束时间留空。时间按本机时区。” | 结束不晚于开始时脚注“结束时间要晚于开始时间。” |
| 预览 | 当前表单 | 同 16.3 预览卡 | — |

#### 17.4 交互与写操作

- **校验**：标题非空且 ≤ 200 字节；正文非空；按条件时订阅至少选一个分组、余额金额 > 0；结束晚于开始。不满足时“存草稿 / 保存 / 发布”置灰。
- **targeting 组装**：所有用户 → `{}`（编辑时从条件改回所有用户也要显式发 `{}`）；单条件 → `{"any_of":[{"all_of":[<条件>]}]}`；多条件只读时编辑**不发** `targeting`（保持原样）。
- **存草稿**（新建 / 草稿）：新建 `status:"draft"`；草稿编辑不改 status → toast “已存为草稿”。
- **保存**（展示中 / 已归档）：不改 status → 展示中 toast “已保存 · 用户看到的是新内容”。
- **发布 / 重新发布**：先确认框（同 16.4，内容取表单）→ 新建 `status:"active"` / 编辑加 `"status":"active"` → toast “已发布公告”。
- **幂等（新建）**：sheet 打开时生成 key；失败后请求体不变就沿用，变了换新 key。`X-Idempotency-Replayed: true` 视为成功；`409 IDEMPOTENCY_KEY_CONFLICT`“该编号已用于另一份公告内容，请重新打开新建页”；`409 IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` 按 `Retry-After` 同 key 重试；超时：有 capability 时同 key 重发一次，仍失败提示结果未确认；无 capability 时**不重发**，`GET /admin/announcements?search=<标题>&sort_by=created_at&sort_order=desc&page_size=5`，最近几分钟有同标题的就提示“上一次可能已经创建成功”，让用户决定（H07 App 退路）。
- **reason**：`ANNOUNCEMENT_TITLE_INVALID`“标题不能为空，最多 200 字节”；`ANNOUNCEMENT_CONTENT_REQUIRED`“请填写正文”；`ANNOUNCEMENT_INVALID_TARGET`“可见对象条件无效，请重新设置”；`ANNOUNCEMENT_TIME_RANGE_INVALID`“结束时间要晚于开始时间”；`ANNOUNCEMENT_NOTIFY_MODE_INVALID` / `ANNOUNCEMENT_STATUS_INVALID`（App 不会发出）；带 key 时业务校验失败会进入 5 秒退避，改内容后必须换 key（已由上面的 key 规则覆盖）。
- 有未保存修改时下滑关闭先确认“放弃修改？”。

#### 17.5 状态

保存中按钮转圈、表单禁用。

#### 17.6 刷新策略

不适用。

#### 17.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementEditSheet.swift`（Markdown 插入用 `TextEditor` + `TextSelection`，iOS 18+ 可用）。

---

### 18. 已读情况（`announcementReads`）

#### 18.1 入口与导航

- 公告详情“已读情况”行、··· “已读情况”。导航栏：返回 + 标题“已读情况” + 副标题公告标题。点行 → 用户详情（用户章节）。

#### 18.2 数据来源

- `GET /admin/announcements/:id/read-status`：`page`、`page_size=50`、`search`（邮箱、用户名、备注、Key，服务端截到 200 字节）、`sort_by`（`email` 默认 / `username` / `balance` / `read_at`）、`sort_order`（`asc` 默认）；有 `announcements.read_stats` 时可加 `read_state=read|unread`、`eligible=true|false`、`sort_by=read_at`（未读排最后）。行：`user_id`、`email`、`username`、`balance`、`eligible`、`read_at`（可缺）。分页信封 `total` 按过滤后计算。
- 汇总：`GET …/read-summary`（16.2）。
- 无 capability：只有 `search` 与 `sort_by=email|username|balance`；`page_size` 保持 20–50（老路径每页逐用户查订阅，附录 H06 App 退路）。

#### 18.3 字段 → 显示映射

| 界面元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 汇总条 | read-summary | “已读 412 · 符合条件 1036 · 共 1036 位用户 · 统计于 09:41” | 无 capability 或失败：“第 1 页 · 共 1,036 位用户”（用分页 `total`） |
| 搜索框 | — | 占位“搜索邮箱或用户名” | — |
| 筛选（capability） | — | 分段“全部 / 已读 / 未读”；开关“只看符合条件” | 无 capability 不显示 |
| 排序菜单 | — | 按邮箱（升序）/ 按用户名（升序）/ 按余额（从高到低，`sort_order=desc`）/ 按阅读时间（最新在前，`sort_by=read_at&sort_order=desc`，capability） | — |
| 结果数 | `total` | 有筛选或搜索时“找到 N 位” | — |
| 行 · 头像 | `username` 首字 | — | 用户名空时用邮箱首字 |
| 行 · 标题 / 右侧 | `email`、`balance` | 邮箱（截断）；余额“$12.40” | — |
| 行 · 第二行 | `username`、`eligible`、`read_at` | 用户名；徽章“符合条件”（ok）/“不符合”（neutral）；“10/16 08:12” | 未读：“未读”（灰） |
| 行 · 变淡 | `eligible == false` | idle | — |
| 底部 | 还有下一页 | 转圈 + “滚到底自动加载下一页” | — |

#### 18.4 交互与写操作

搜索（防抖 300ms）、筛选、排序变化 → 重载第 1 页；触底加载下一页；点行 → 用户详情。只读。

#### 18.5 状态

| 情况 | 显示 |
|---|---|
| 无匹配 | “没有匹配的用户” |
| `400 INVALID_READ_STATUS_FILTER` | App 参数错误，按通用“请求无效”处理 |
| 失败 | `FailureView` |

#### 18.6 刷新策略

进入时加载第 1 页与汇总；下拉刷新；不轮询。

#### 18.7 对现有代码的改动点

新增 `NativeApp/Features/Announcements/AnnouncementReadsView.swift`；接口在 15.7 的 `Announcements.swift`。

---

### 19. 发放兑换码（补偿）sheet（`redeemGrant`）

> DECISIONS 第 3 轮文字题：用户详情 ··· 菜单加“发放兑换码（补偿）”，后端 create-and-redeem，可发余额 / 并发 / 订阅，余额类走资金确认与 Face ID 门槛。设计稿 `v-modules.jsx:1358-1560`（`VmoGrantSheet`、`vmoGrantSummary`、`vmoSubPlan`、`vmoConfirmGrant`、`VmoGrantReceipt`），菜单项 `00-core.jsx:1199`。30 章 §2.4 只负责入口与成功后的刷新，sheet、接口、确认与待核对都在本节。

#### 19.1 入口与导航

- 用户详情 ··· “发放兑换码（补偿）…”（30 章 §2.4，所有用户都显示，含管理员与已禁用用户）→ sheet `.redeemGrant(userID:pendingID: nil)`，`presentationDetents([.large])`。只读令牌：菜单项置灰，旁注“只读令牌”（0.3）。vendor 看不到（兑换码对 vendor 不开放）。
- **打开前拦截**：当前站点、这个用户有未核对的补偿记录（19.4）时，先弹确认框“上一次补偿的发放结果未确认”，正文“向 王小明 发放 $10.00 余额 · 5 分钟前发起。\n先核对，避免重复发放。”，按钮“先核对”（默认，打开本 sheet 的“结果待核对”页）/“取消”。核对完成前不能发起新的补偿（00 §2.5.4 第 4 条）。
- 从设置 → 待核对 · 补偿发放（3.3）或概览待处理进入时，`pendingID` 有值，sheet 直接显示“结果待核对”页。
- sheet 内步骤条“类型 · 数值 · 备注”。标题：第 1 步“发放兑换码”，第 2 步“余额补偿 / 并发补偿 / 订阅补偿”，第 3 步“备注与确认”。左上第 1 步“取消”，之后“上一步”。发送中、Face ID 验证中、“正在确认结果…”时 `.interactiveDismissDisabled`。
- 成功后关闭 sheet，回到用户详情；回执 toast 的“查看兑换码”→ 在当前导航栈 push `.redeem(open: <redeem_code.id>)`（第 8 节）。

#### 19.2 数据来源

| 用途 | 接口 | 参数 / 字段 |
|---|---|---|
| 用户 | 用户详情已加载的 `AdminUser` | `id`、显示名（30 §0.3）、`email`、`balance`、`concurrency`、`status`；不另请求 |
| 订阅分组选项 | 分组目录缓存 `GET /admin/groups/all`（`include_inactive=true`，50 章） | `subscription_type == "subscription"` 且 `status == "active"`，同 9.2 |
| 用户现有订阅（订阅类的“现在 / 发放后”） | `GET /admin/users/:id/subscriptions`（`server/routes/admin.go:819`；30 章 §10 的 `userSubscriptions(userID:)`） | 数组：`group_id`、`status`、`expires_at`；选中订阅类时请求一次 |
| 发放 | `POST /admin/redeem-codes/create-and-redeem`（`server/routes/admin.go:660`；`handler/admin/redeem_handler.go:51-63,262-331`） | 头：`Idempotency-Key`（**强制**，缺了 400 `IDEMPOTENCY_KEY_REQUIRED`；scope `admin.redeem_codes.create_and_redeem`，带 key 的执行上限 30 秒，可接管卡住的执行，`idempotency_helper.go:160-163`）、`X-Request-ID`（= key）。请求体见下 |
| 核对 | `GET /admin/redeem-codes` | `search=<code>&page=1&page_size=5`（码值包含匹配，不带 `types` / `status`）；本地按 `items[].code == code` 复核（00 §2.5.5 的“发放补偿”行） |

**请求体**（`CreateAndRedeemCodeRequest`）：

| 类型 | 请求体 |
|---|---|
| 余额 | `{"code":"<32 位小写十六进制>","type":"balance","value":10.5,"user_id":42,"notes":"…"}` |
| 并发 | `{"code":"…","type":"concurrency","value":2,"user_id":42,"notes":"…"}` |
| 订阅 | `{"code":"…","type":"subscription","value":30,"user_id":42,"group_id":3,"validity_days":30,"notes":"…"}` |

- `code`：App 生成，16 字节 `SecRandomCopyBytes` → 32 位小写十六进制，与服务端生成的码同一形态（`service/redeem_code.go:63-69`）；长度要求 3–128。
- `value`：JSON number（字段是 `float64`，不能发字符串；这是 00 §0 第 11 条“金额写入用字符串”的例外），余额最多 2 位小数。`value` 带 `binding:"required"`，**0 会被拒**（`redeem_handler.go:56`），所以订阅类的 `value` 填与 `validity_days` 相同的天数（订阅类不用 `value` 记账；30 §4.3 的记录行在 `validity_days` 为 0 时才用 `value` 显示天数）。
- 订阅类必须带 `group_id` 与非 0 的 `validity_days`（`redeem_handler.go:281-289`）；App 只发 1–3650 的正数（负数是扣减订阅，不提供）。
- 不发 `expires_at` / `expires_in_days`（码当场兑换）。`notes` 选填，App 限 1000 字（后端此接口未设上限，与批量生成一致）。
- 不提供邀请码：邀请码不能通过兑换接口使用（`service/redeem_service.go:523-532`，400 `REDEEM_CODE_UNSUPPORTED_TYPE`），而且码会先建好再失败，留下一个未使用的码。
- 响应：`data.redeem_code` = `AdminRedeemCode`（`id`、`code`、`type`、`value`、`status:"used"`、`used_by`、`used_at`、`group_id`、`validity_days`、`notes` 等）。重放（`X-Idempotency-Replayed: true`）时 `code` 可能是 `***`（logredact），以本机生成的 code 为准，`id` 完整。
- 服务端去重靠 `code`：同一个 code 已被同一用户兑换 → 直接返回原结果；码已建好但没兑换（上次执行中途失败）→ 补兑；码被别的用户用过 → 409 `REDEEM_CODE_CONFLICT`（`redeem_handler.go:334-362`）。所以同 code、同用户重发**不会重复发放**，即使幂等记录已过 24 小时。

#### 19.3 字段 → 显示映射

| 步骤 / 元素 | 字段 / 计算 | 格式与文案 | 空值 / 不可用时 |
|---|---|---|---|
| 对象条 | 显示名 + 随步骤变化 | 头像首字 + “王小明 · …”：第 1 步写 `email`；余额“余额 $12.40”；并发“并发上限 5”；订阅按下面的订阅计划写“企业专线 未订阅 / 企业专线 至 10/30 / 企业专线 10/30 已过期 / 企业专线 已暂停，至 10/30”；禁用用户右侧 neutral 徽章“禁用” | `concurrency == 0` 写“并发上限 不限制” |
| 第 1 步 · 类型磁贴 | 固定三项 | 余额“直接计入余额，按资金操作确认。”；并发“提高这个用户的并发上限。”；订阅“开通或延长一个订阅分组。”；点磁贴即进第 2 步 | 没有订阅分组：订阅磁贴置灰，副行“没有订阅类型的分组”；用户 `concurrency == 0`：并发磁贴置灰，副行“这个用户并发不限制，发放后反而会变成有上限”（0 = 不限制，`service/concurrency_service.go:442-444`；未决问题 14） |
| 第 1 步 · 脚注 | 固定 | “发放会生成一个兑换码并立即替这个用户兑换，记录出现在用户的“充值与调整记录”和兑换码列表里。邀请码只能在注册时使用，不能发放。” | — |
| 第 2 步 · 余额 | 大数字键盘 | 大字“$10”；下方“发放后余额 **$22.40**”；键盘输入规则同 30 章 §3.3（`KeypadInput`）；不给默认金额 | 未输入时“$0”灰色，下方“输入金额”，“下一步”置灰 |
| 第 2 步 · 并发 | 步进器 1–50（默认 1） | 标签“增加并发”；脚注“提高这个用户的并发上限。发放后：并发上限 5 → 7。” | — |
| 第 2 步 · 订阅 | 分组胶囊（默认第一个）+ 有效天数 | 天数选项 7 / 30（默认）/ 90 / 自定义（数字键盘，1–3650）；脚注“只列出订阅类型的分组。”+ 订阅计划的说明句 | 用户订阅请求失败：说明句改“暂时读不到这个用户的订阅，发放后以服务器结果为准”，不阻断 |
| 订阅计划 | 用户订阅里 `group_id` 相同的那行（服务端每个用户、分组一行，`AssignOrExtendSubscription`，`service/subscription_service.go:218-271,291-345`） | 没有 → “新开通 · 到期 <今天 + N 天>”，说明“还没有这个订阅：从今天开通。”；`expires_at` 晚于现在且 `status == active` → “到期 10/30 → 11/29”，说明“已有生效中的订阅：在原到期日 10/30 上延长。”；晚于现在但不是 active（暂停）→ “恢复生效 · 到期 10/30 → 11/29”，说明“订阅暂停中：在原到期日上延长，并恢复为生效。”；`expires_at` 不晚于现在 → “重新开通 · 到期 <今天 + N 天>”，说明“订阅 10/30 已过期：从今天重新算，用量清零。” | 日期按服务器时区（00 §6.3） |
| 第 3 步 · 备注 | `notes` | 多行输入，占位“例如：故障补偿 · 工单 #8812”；脚注“可选。写进兑换码的备注，也显示在用户的“充值与调整记录”里。” | 空则发 `""` |
| 第 3 步 · 收据 | 汇总 | 对象“王小明 · wang@example.com”；站点；类型“余额 / 并发 / 订阅”；数值（非余额）“+2 并发”/“企业专线 · 30 天”；变化（余额“余额 $12.40 → $22.40”，并发“并发上限 5 → 7”，订阅为订阅计划那一句）；兑换码“a3f0····d4e8”；发放（只余额，加粗）“$10.00” | — |
| 第 3 步 · 返利脚注 | 只余额 | “按兑换处理：开启邀请返利时，邀请人会照常得到返利（和用户自己兑换一样，不看“管理员充值参与返利”开关）。”（`service/redeem_service.go:476-482,679-697`：管理员兑换路径不设跳过返利标记，注释写明“affiliate rebate remains enabled”） | — |
| Face ID 提示 | 余额且开关打开且金额 > 门槛 | “超过 $100，确认后验证 Face ID。” | — |
| 提交按钮 | 汇总 | “发放 $10.00” / “发放 +2 并发” / “发放 30 天订阅” | 校验不过置灰 |
| 确认框 | 汇总 | 标题“向「王小明」发放 $10.00 余额？”/“向「王小明」发放 +2 并发？”/“向「王小明」发放 企业专线 30 天订阅？”；正文逐行：“站点 主站 · <变化>”；有备注“备注：<备注>”；禁用用户“该用户已禁用。\n发放后仍不能调用，需先启用。”；需要时 Face ID 行；按钮“发放 $10.00”（余额类 destructive 样式）/ 其他类型普通样式，“取消” | — |
| 成功回执 | 响应 | toast（礼物图标）“已向 王小明 发放 $10.00 余额”，重放时“这笔补偿此前已发放，没有重复执行”；动作“查看兑换码” | — |
| 结果待核对页 | 本机记录 | 沙漏 + “请求可能已提交” + “没有收到服务器确认。不要重新发放，先核对。”；收据（对象、站点、内容、兑换码末 4 位、编号 = 完整 key，等宽可选中）；按钮“核对发放结果”（主）/“用同一编号重试”；脚注“编号和兑换码已保存在本机。用同一编号重试时，服务器发放过就直接返回那一次，不会重复发放。” | — |
| 没找到页 | 核对无此码 | 放大镜 + “服务器上没有这次发放” + “这次发放没有生效。用同一编号重试，或者放弃。”；按钮“用同一编号重试”（主）/“放弃这次发放” | — |
| 未兑换页 | 核对到码但 `status == unused` | “兑换码已创建，还没兑换给 王小明” + “上一次执行中途停了。用同一编号重试会把这个码兑换给他。”；按钮“用同一编号重试”（主）/“放弃这次发放”（脚注“放弃后这个码留在兑换码列表里，未使用，可以删除。”） | — |

#### 19.4 交互与写操作

1. **提交**：第 3 步“发放 …”→ 确认框 → 确认 →（余额类、开关打开、金额 > 门槛）Face ID，失败或取消则不发送（3.4 覆盖清单）。
2. **冻结与落盘**（00 §2.5.2、§2.5.5）：确认那一刻生成 `key`（UUID v4 小写，同时作 `X-Request-ID`）；`code` 在 sheet 打开时生成（第 3 步收据要显示末 4 位），随请求体一起冻结。写入 `PendingWrite`：`kind = .redeemGrant`、`id = key`、`serverID`、`actorUserID = me.user.id`、`authMethod`、`method`、`path`、`body`（`.sortedKeys` 编码的原始字节）、`summary{userID, 显示名, email, 类型, 数值文案, code}`、`status = sending`。**落盘失败就不发送**，提示“未决记录无法保存，已暂停发放”。
3. **发送**：客户端超时 40 秒（服务端上限 30 秒，同 30 章 §3.4）。
4. **结果**：

| 结果 | 动作 |
|---|---|
| 200 | 删除记录；关闭 sheet；回执；按 30 章 §2.4 刷新用户资料（余额 / 并发）与记录前 5 条；订阅类另重拉该用户订阅 |
| 200 + `X-Idempotency-Degraded: result-committed` | 同 200 |
| 409 `IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` | 按 00 §2.5.3：显示“正在等待服务器结果…”，等 `Retry-After` 后同 key 同字节重试；累计超过 30 秒 → 转“结果待核对”页 |
| 409 `REDEEM_CODE_LOCKED` | 同一个码正在被另一次请求处理：等 2 秒后同 key 同字节重试一次，仍是此码 → 转“结果待核对” |
| 409 `REDEEM_CODE_CONFLICT` | 这个码已被别的用户用过（随机码撞上，正常不会出现）：确定没发给本用户 → 删除记录；换新 code 和新 key，提示“兑换码编号冲突，已换新编号，请重新确认”，回到第 3 步 |
| 400 `GROUP_NOT_SUBSCRIPTION_TYPE` / 404 `GROUP_NOT_FOUND` | 删除记录；“这个分组不能用于订阅，请重新选择”，回到第 2 步并重拉分组目录 |
| 404 `USER_NOT_FOUND` | 删除记录；关闭 sheet，“用户不存在或已删除” |
| 400 `REDEEM_CODE_UNSUPPORTED_TYPE`、无 reason 的 400（请求体校验） | App 不会发出：删除记录，按 00 §3.3 的“请求无效”处理并上报（不含 code） |
| 400 `IDEMPOTENCY_KEY_REQUIRED` / `IDEMPOTENCY_KEY_INVALID`、409 `IDEMPOTENCY_KEY_CONFLICT` | 程序缺陷，按 00 §2.5.3 |
| 401 / 403（含 `ACCESS_TOKEN_READ_ONLY`）/ 423 | 鉴权或合规在执行前拒绝：删除记录，按全局处理 |
| 503 `IDEMPOTENCY_STORE_UNAVAILABLE` | 没有执行：保留记录，转“结果待核对”，10 秒后才允许“用同一编号重试”（00 §2.5.3） |
| 其他 5xx / 网络错误 / 超时 | 按 00 §2.5.4：同 key 同字节自动重试 2 次（2 秒、5 秒，仅前台），仍未知 → 记录转 `unknown`，sheet 换成“结果待核对”页 |

   业务错误发生在建码之后时（`USER_NOT_FOUND`、分组错误），服务器上会留下一个未使用的码（`redeem_handler.go:307-325`：先建码、后兑换）；App 不自动删除，兑换码列表里可见。
5. **改了内容就换编号**：发送过一次之后（不论结果），再改类型、数值、分组、天数或备注，`code` 和 `key` 一起换新（旧 code 可能已在服务器上以旧参数建好，沿用会兑换出旧参数）。
6. **核对**（“核对发放结果”、设置 → 待核对、概览待处理共用，只查不执行）：`GET …/redeem-codes?search=<code>`，本地找 `code` 完全相等的那项：
   - `status == used` 且 `used_by == userID` → 已发放：删除记录，回执“已核对：已向 王小明 发放 $10.00 余额”，刷新同第 4 步 200；
   - 找到但 `status == unused` → 未兑换页；
   - 没找到 → 没找到页；
   - 被别的用户用了 → 同 `REDEEM_CODE_CONFLICT`；
   - 查询失败 → “核对失败，请稍后再试”，记录保留。
7. **用同一编号重试**：同 key、同 `X-Request-ID`、同字节重发，结果按第 4 步。00 §2.5.5 规定超过 `expiresAt` 后重试按钮置灰；补偿是例外——服务端按 code 去重，过期后同 code 重发也不会重复发放（19.2 末条），按钮保持可用。仍须同一操作者（00 §2.5.2）：发起人不是当前管理员时不给重试，只给“放弃”。
8. **放弃这次发放**：二次确认“放弃后这笔不会再重试；如果服务器其实已经发放，以服务器为准。”→ 删除记录，toast “已放弃 · 不再提醒”。
9. App 回到前台时，对本站点 `unknown` 状态的补偿记录各自动核对一次（只查不执行，同 30 章 §3.6）；查到已发放就删除记录并回执。

#### 19.5 状态

| 情况 | 显示 |
|---|---|
| 发送中 | 提交按钮“正在发放…”，sheet 不能关闭 |
| Face ID 中 | 覆盖层“Face ID · 验证后发放”；取消 = 不发请求、删掉刚写的记录 |
| 等待服务器（409 进行中） | “正在等待服务器结果…”+ 已等待秒数 |
| 待核对 | 结果待核对页；关闭 sheet 后在设置 → 待核对、概览待处理（10 章）保留提醒，直到核对或放弃 |
| 核对 / 重试中 | 按钮“正在核对…”/“正在用同一编号重试…”，两个按钮都禁用 |
| 待核对文件不可读 | 同 3.5：已暂停新的余额操作、兑换码生成与补偿发放 |

#### 19.6 刷新策略

sheet 内不轮询。打开时用用户详情已有的数据；选订阅类时拉一次用户订阅。成功后刷新用户详情（30 章 §2.4）；兑换码列表下次显示时按 8.6 重载。待核对只在用户点“核对”或回到前台时查。

#### 19.7 对现有代码的改动点

- 新增 `NativeApp/Features/Redeem/RedeemGrantSheet.swift`：三步（类型、数值、备注）+ 确认 + “结果待核对 / 没找到 / 未兑换”三个页面；初始化参数 `user: AdminUser`、`pendingID: UUID?`。
- `Sources/Sub2Core/RedeemCodes.swift`：`RedeemGrantSpec`（类型、金额 `Decimal`、并发数、分组 id 与名、天数、备注）、`RedeemGrantRequest`（Encodable，`value` 编码成 JSON number、订阅类 `value = validity_days`）、`RedeemCode.random()`（32 位小写十六进制）、`SubscriptionGrantPlan.make(rows:groupID:days:now:timeZone:)`（新开通 / 延长 / 恢复 / 重新开通，纯函数，便于单测）、`APIClient.createAndRedeem(_:)` 走 00 §9.1 的 `send(_ write: PendingWrite)`，返回 `WriteOutcome<AdminRedeemCode>`。
- `NativeApp/Session/AppModel.swift`：`PendingWrite.Kind` 增加 `.redeemGrant`；`reconcile(_:)` 按 19.4 第 6 步分派；`hasPendingGrant(userID:)` 供 19.1 拦截。
- 30 章 `UserDetailView` 的 ··· 菜单项打开本 sheet，并传入成功回调（刷新资料与记录）。
- 复用：`KeypadInput`（30 章 §3.7）、`BiometricGate`（3.7）、分组目录缓存（50 章）、`userSubscriptions(userID:)`（30 章 §10）。
- 单测（`Tests/Sub2CoreTests`）：请求体（三种类型、订阅 `value` 非 0、金额是 number）；`SubscriptionGrantPlan` 四种情况与服务器时区日界；核对判定（used + 同用户 / unused / 无 / 他人）；改内容后 code 与 key 都变。

---

### 附录 · 本章接口清单（均已在 sub2 `70116315d` 源码核实）

| # | 方法与路径 | 用于 | 后端位置 |
|---|---|---|---|
| 1 | `GET /settings/public` | 4 | `server/routes/auth.go:246`；`handler/dto/settings.go:387-436`（`captcha_provider` / `mobile_verify_path` 在 403-404）；`web/embed_off.go:50-53`、`web/embed_on.go:462-472`、`web/mobile_verify.go:7` |
| 2 | `POST /auth/login` | 4 | `server/routes/auth.go:38`；`handler/auth_handler.go:86-99` |
| 3 | `POST /auth/login/2fa` | 4 | `server/routes/auth.go:41`；`handler/auth_handler.go:335-338` |
| 4 | `POST /auth/logout` | 3 | `server/routes/auth.go:58` |
| 5 | `GET /admin/me` | 0.2、0.3、3、4、7 | `server/routes/admin.go:40`；`handler/admin/me_handler.go:17-75,129-193`（无 scope 字段，185-193） |
| 6 | `GET /auth/sessions` | 5 | `server/routes/auth.go:259`；`handler/auth_sessions_handler.go:37` |
| 7 | `DELETE /auth/sessions/:id` | 5 | `server/routes/auth.go:260`；`handler/auth_sessions_handler.go:69` |
| 8 | `POST /auth/revoke-all-sessions` | 5 | `server/routes/auth.go:262`；`handler/auth_handler.go:858` |
| 9 | `POST /user/totp/step-up` | 7 | `server/routes/user.go:62`；开关关闭时 step-up 直接放行（含机器凭据）：`server/middleware/step_up.go:100,104` |
| 10 | `GET /admin/access-tokens` | 0.3、3、6 | `server/routes/admin.go:212`；`handler/admin/access_token_handler.go:89` |
| 11 | `POST /admin/access-tokens` | 首版不调用（6.2） | `server/routes/admin.go:213`（step-up）；`access_token_handler.go:57-61`（机器凭据一律 403） |
| 12 | `DELETE /admin/access-tokens/:id` | 3、6 | `server/routes/admin.go:214`；`access_token_handler.go:110` |
| 13 | `GET /admin/push/devices` | 7 | `server/routes/admin.go:222`；`handler/admin/push_handler.go:141` |
| 14 | `POST /admin/push/devices` | 7 | `server/routes/admin.go:223`；`push_handler.go:108`；`environment` 省略时存空串、发送跟随站点：`service/push_device_service.go:177-183`、`service/push_sender_apns.go:109-111` |
| 15 | `DELETE /admin/push/devices/:id` | 3、7 | `server/routes/admin.go:224`；`push_handler.go:160` |
| 16 | `PUT /admin/push/devices/:id/subscription` | 7 | `server/routes/admin.go:225`；`push_handler.go:178` |
| 17 | `POST /admin/push/devices/:id/test` | 7 | `server/routes/admin.go:226`；`push_handler.go:202` |
| 18 | `GET /admin/push/config` | 7 | `server/routes/admin.go:227`；`push_handler.go:221` |
| 19 | `PUT /admin/push/config` | 7 | `server/routes/admin.go:228`（step-up）；`push_handler.go:232` |
| 20 | `GET /admin/redeem-codes` | 8、11、19 | `server/routes/admin.go:656`；`handler/admin/redeem_handler.go:91-161` |
| 21 | `GET /admin/redeem-codes/stats` | 8 | `server/routes/admin.go:657`；`redeem_handler.go:478`；`handler/dto/redeem_code_stats.go:15-31` |
| 22 | `GET /admin/redeem-codes/:id` | 8、9、11 | `server/routes/admin.go:659`；`redeem_handler.go:165` |
| 23 | `POST /admin/redeem-codes/generate` | 10、11 | `server/routes/admin.go:661`；`redeem_handler.go:183-260` |
| 24 | `POST /admin/redeem-codes/batch-update` | 8、9 | `server/routes/admin.go:664`；`redeem_handler.go:413`；`service/redeem_service.go:349-389` |
| 25 | `DELETE /admin/redeem-codes/:id` | 8 | `server/routes/admin.go:662`；`redeem_handler.go:368`；`service/redeem_service.go:28-30` |
| 26 | `GET /admin/proxies` | 2、12 | `server/routes/admin.go:633`；`handler/admin/proxy_handler.go:59` |
| 27 | `GET /admin/proxies/:id` | 13 | `server/routes/admin.go:638`；`proxy_handler.go:120` |
| 28 | `POST /admin/proxies` | 14 | `server/routes/admin.go:639`；`proxy_handler.go:139` |
| 29 | `PUT /admin/proxies/:id` | 13、14 | `server/routes/admin.go:640`；`proxy_handler.go:173` |
| 30 | `DELETE /admin/proxies/:id` | 13、14 | `server/routes/admin.go:641`；`service/admin_proxy.go:254-297` |
| 31 | `POST /admin/proxies/:id/test` | 12、13 | `server/routes/admin.go:642`；`service/admin_service.go:663-673` |
| 32 | `POST /admin/proxies/:id/quality-check` | 13 | `server/routes/admin.go:643`；`service/admin_service.go:675-699` |
| 33 | `GET /admin/proxies/:id/accounts` | 13 | `server/routes/admin.go:645`；`handler/dto/types.go:532-538` |
| 34 | `GET /admin/proxies/:id/fallback-accounts` | 13 | `server/routes/admin.go:646`；`handler/dto/types.go:542-546` |
| 35 | `POST /admin/proxies/:id/fallback-accounts/revert` | 13 | `server/routes/admin.go:647`；`service/admin_proxy_fallback.go:18-28` |
| 36 | `GET /admin/announcements` | 15、17 | `server/routes/admin.go:555`；`handler/admin/announcement_handler.go:52` |
| 37 | `GET /admin/announcements/:id` | 16 | `server/routes/admin.go:557`；`announcement_handler.go:91` |
| 38 | `POST /admin/announcements` | 17 | `server/routes/admin.go:556`；`announcement_handler.go:30-38,121` |
| 39 | `PUT /admin/announcements/:id` | 16、17 | `server/routes/admin.go:558`；`announcement_handler.go:40-48,163` |
| 40 | `DELETE /admin/announcements/:id` | 16 | `server/routes/admin.go:559` |
| 41 | `GET /admin/announcements/:id/read-status` | 18 | `server/routes/admin.go:560`；`announcement_handler.go:244` |
| 42 | `GET /admin/announcements/:id/read-summary` | 16、18 | `server/routes/admin.go:561`；`handler/admin/announcement_read_stats_handler.go:56` |
| 43 | `GET /admin/accounts`（`search`、`lite`） | 2 | `handler/admin/account_handler.go:718-727` |
| 44 | `GET /admin/users`（`search`） | 2（含“查看全部”） | `handler/admin/user_handler.go:150`；`repository/user_repo.go:553-561` |
| 45 | `GET /admin/groups`（`search`） | 2 | `handler/admin/group_handler.go:378` |
| 46 | `GET /admin/usage`（`request_id`、`key_view=masked`） | 2 | `handler/admin/usage_handler.go:122,132`；`repository/usage_log_repo_query.go:120-123` |
| 47 | `GET /admin/ops/request-errors`（`request_id`、`view`、`time_range`） | 2 | `handler/admin/ops_handler.go:216-262,344-354,579` |
| 48 | `GET /admin/groups/all`（`include_inactive=true`） | 7、9、10、15、17、19 | `server/routes/admin.go:404`；`group_handler.go:560-569` |
| 49 | `GET /admin/accounts/status-summary`（`include_accounts=true`） | 13（账号状态徽章，账号章节提供） | `server/routes/admin.go:474`；`handler/admin/account_status_summary_handler.go:29-46` |
| 50 | `POST /admin/redeem-codes/create-and-redeem` | 19 | `server/routes/admin.go:660`；`handler/admin/redeem_handler.go:51-63,262-362`；`service/redeem_service.go:476-482,523-532` |
| 51 | `GET /admin/users/:id/subscriptions` | 19 | `server/routes/admin.go:819`；`handler/admin/subscription_handler.go:333`；续期 / 重开语义 `service/subscription_service.go:218-345` |
| 52 | `GET /admin/compliance` | 4（旧服务端 Admin Key / sat_ 探针，00 §1.9） | `server/routes/admin.go:188-190` |

---

### 本章未决问题

1. **搜索 Tab 在 iOS 27 的表现**：DECISIONS 定“目录首屏、点搜索框才弹键盘”，并写了 `.tabViewSearchActivation(.automatic)`；但有报告称 iOS 27 上不声明 `.searchTabSelection` 时分离的搜索按钮会并入 Tab 栏，而 `.searchTabSelection` 会让点 Tab 即激活搜索。**建议默认**：`.searchable` 挂在搜索 Tab 内部根视图、`.automatic`，iOS 26 / 27 实机各验证一次；若 27 上按钮并入，维持目录首屏优先，接受按钮并入。
2. **目录“告警事件”的去向**：设计稿未接线。**建议默认**：切到 监控 Tab 的“告警”分段（不在搜索栈里重复一份告警列表）。
3. **简化模式在首版的呈现**：简化模式尚未设计。**建议默认**：设置里显示该项但置灰并标“设计中”，不可选。
4. **G03 / G04 没有 capability 标记**：App 只能用 `redeem_codes.stats` 推断。**建议默认**：按推断实现；请后端顺手在 capabilities 加 `redeem_codes.batches`（不改行为）。
5. **公告列表 / 详情是否恢复已读进度**：设计稿当时因后端没有数据而降级为只留“已读情况 ›”，H06 已上线，DECISIONS 未再表态。**建议默认**：有 `announcements.read_stats` 时列表行写“已读 N/M”、详情写汇总，已读名单加筛选与按阅读时间排序。
6. **生成向导第 3 步加“备注”**：设计稿因后端当时没有 `notes` 参数而未画，G03 已支持。**建议默认**：加，选填，≤ 1000 字。
7. **APNs 站点配置放进 App**：Web 没有配置界面（BACKLOG A11“本次只提供接口，App 或 curl 可配置”；sub2 `frontend/src` 里没有 `push/config` 调用），设计稿也没画。**建议默认**：放在推送通知页底部，仅站长；可编辑条件同 7.3（非只读令牌，且站点关闭二次验证或本人可做二次验证）。
8. **推送登记的 `site_tag` 取值**：后端用它填载荷里的 `site`。**建议默认**：填 `ServerProfile.id.uuidString`，便于多站点点击路由（代价是载荷里不是域名，对 iOS 无影响）。
9. **关闭 Face ID 开关是否也要验证**：设计稿未说明。**建议默认**：开、关都验证一次。
10. **首版是否在 App 内签发管理访问令牌**：00 未决问题 3 默认“首版不签发”，本章第 6 节已按此只做列表与吊销；但 Web 也没有签发界面（sub2 `frontend/src` 里没有 `access-tokens` 调用），首版里 sat_ 实际只能用 API 签发。**建议默认**：维持首版不签发（与 00 一致）。若改为签发，需同时改 00 §1.3 与未决问题 3，再在第 6 节加新建 sheet（`POST /admin/access-tokens` 挂 step-up；handler 对 Admin Key / sat_ 一律 403 `STEP_UP_ADMIN_API_KEY_FORBIDDEN`，与站点二次验证开关无关）。
11. **兑换码 ··· 加“查看同一批”**：设计稿没有，G03 提供了 `batch_id` 过滤。**建议默认**：加在 ··· 菜单，复制之后、删除之前。
12. **会话列表里本机行能否下线**：后端允许（等于退出）。**建议默认**：本机行不给“下线”，统一走“退出并清除凭据”（顺带清推送设备）。
13. **全局搜索“像请求 ID”的判定**：后端请求 ID 有 UUID、`client:<uuid>` 等形态，没有统一格式。**建议默认**：去空白后不含空格与 `@`、长度 8–256 就加查使用记录与错误请求（精确匹配，查不到只是少两个分区）。
14. **给并发不限制的用户发放并发补偿**：用户 `concurrency == 0` 表示不限制（`service/concurrency_service.go:442-444`），兑换并发码是在原值上加（`service/redeem_service.go:574-585`、`repository/user_repo.go:1129-1131` `AddConcurrency`），发放 +N 后反而变成上限 N。设计稿只处理了“并发上限未知”的显示，没有定这种情况。**建议默认**：并发磁贴置灰并说明原因（19.3），不提供发放。

---

## 实现顺序建议

按依赖分 7 个阶段。阶段内的顺序就是建议的提交顺序；每个阶段结束时用 `scripts/generate_project.py` 重新生成工程，按现有流程在 Mac 上编译并跑单元测试与 UI 测试。跳转目标页还没做时，先推占位页（路由在阶段 0 就定义好）。

### 阶段 0 · 通用约定、会话与应用骨架（00 全章、10 §0.5 / §0.7、60 §3 / §4 的一部分）

1. **Core 基础**：`ErrorEnvelope`、`ReasonCatalog`、`APIError` 改造（00 §3、§9.3）；`APIClient` 请求层——请求头与 `X-Device-ID`、`TOKEN_EXPIRED` 刷新重发、带响应头的 `requestWithHeaders`、按请求类别自动重试、429（00 §2、§9.1）；`ConditionalCache`（00 §4.2）；`IdempotentWrite`（`WriteOutcome`、`PendingMoneyWrite`、`PendingCompensation`，00 §2.5）；`IncrementalList`（00 §4.3）；`ServerTime`（00 §6.3–§6.4）；`DisplayFormat`（00 §6.1、§6.2、§6.5）；`AdminMe` 与 capability 常量（00 §1.9、§5）；`Page<T>` 放宽（00 §4.1）。
2. **会话**：`AppModel.connect` 改用 `me()`，`SiteSession`（capabilities、服务器时区、时钟偏差、`accessTokenScope` / `isReadOnlyToken`，R14）；`CredentialVault` 的 `deviceID` 与 `.accessToken`；退出与删除站点的顺序；`scenePhase`；三类待核对文件（00 §9.5–§9.6，R01）；全局合规 sheet 与二次验证 sheet（00 §1.10、§2.6）。
3. **应用骨架**：10 §0.7 的 `MainTab`、`AppRouter`、每 Tab 一个 `NavigationStack`、`TabIntent`、站点菜单、`Receipt`、`StatusRail`；`Palette` 与 `Tone`（00 §8.2）；`BlockState` 与 `LoadState`（10 §0.5）；`AppPreferences` 与 `BiometricGate`（60 §3.7，覆盖范围按 60 §3.4）；登录页（60 §4）；设置页的外观、Face ID、站点、退出部分（60 §3）。
4. **跨章共用的纯函数先做**：`AccountDisplayState`（20 §0.2）、`AdminAPIKeyStatus`（30 §7.3）、`KeypadInput`（30 §3.7）、`AlertPresentation`（10 §6.3）、`AccountStatusSummary` 模型（20 §10.1）。
5. 完成标志：00 §9.8 列的测试全过；能用三种方式登录、切站点、退出；四个 Tab 与搜索 Tab 可导航。

### 阶段 1 · 概览与监控（10）

`LiveOpsStore` → `dashboard/home` 与逐接口退路 → 6 格 → 待处理（含三类待核对行，R02）→ 今日区、运行区 → 平静布局 → 告警详情与 `AlertActions` → `OpsDisabledNotice` 与开启流程 → 监控三段。完成标志：10 §1.7 与 §8 列的测试；10 §1.7 的 6 种 UI 测试数据都能渲染。

### 阶段 2 · 账号（20）

账号列表与 `AccountRow` → 详情上半部分 → 恢复 / 启停调度 / 启用账号（§5，`AccountActions` 同时供概览与分组复用）→ 内联编辑与 `PATCH` + `If-Match`（§3）→ 测试连接（§4）→ 凭据与 `OAuthFlow`（§6）→ 新建账号（§7，复用 `OAuthFlow`）→ 批量操作坞（§8）→ 定时测试（§9）。账号详情“最近上游错误”与记录区计数依赖 40 §6.7 的 `errorRecords` / `errorCount`，本阶段先调现有 `errorRecords`，阶段 4 统一。

### 阶段 3 · 用户（30）

用户列表与头像条 → 用户详情 → 充值 / 退款键盘与核对（`BalanceReconciliation` 先写单测再接界面，资金写最关键）→ 充值与调整记录 → 新建用户 → 编辑用户前两段 → Key 卡片（揭示、新建、编辑、换分组、删除）→ 平台限额与替换分组。用户详情 ⋯ 的“发放兑换码（补偿）”先接占位，阶段 6 与兑换码一起完成（60 §19）。

### 阶段 4 · 日志与统计（40）

先日志：`RequestLogFilter` / `LogTimeWindow`、`LogsView`、`LogRow`、增量刷新（接 `IncrementalList`）、`errorCount`（供 10 / 20 / 50 的计数）、请求详情与上游尝试。再统计：`AnalyticsSession` 与范围记忆 → 统计分析卡片流 → 更多图表 → 单图 → 全部排行 → 模型页；`PerformanceTrend` 覆盖秒数口径与 `PerfTrendBody`。

### 阶段 5 · 分组（50）

`GroupStore` 与列表 → 分组详情 → 编辑 / 新建分组 sheet 与成员写入（`GroupMembers`）→ 添加账号 → 逐项结果 → 分组 API 密钥（复用 30 的 `AdminAPIKeyStatus`、`apiKeysTodayUsage`）→ 分组订阅。

### 阶段 6 · 其他（60）

搜索目录与全局搜索（复用 20 / 30 / 40 / 50 的行组件）→ 设置剩余部分（登录设备、管理访问令牌、待核对分区）→ 兑换码列表、编辑、批量生成、生成结果核对 → 发放兑换码（补偿）→ 代理 → 公告 → 推送（entitlements、`PushCoordinator`、推送设置页；需要真机与站点 APNs 配置，放最后）。

---

## 现有代码改动总表

汇总各章“对现有代码的改动点”，路径相对 `sub2-mobile-native/`，按文件排序；括号里是出处。

### 一、修改现有文件

| 文件 | 改动（出处） |
|---|---|
| `NativeApp/Features/AccountEditView.swift` | `AccountEditView` 拆成 `Accounts/AccountSectionSheet.swift`（基础 / 调度 / 模型 / 高级四种，共用差异计算与校验）；可复用 `integer(_:label:)`、倍率正则、`unresolved`（结果不明时停止提交并读回）的思路、step-up 处理（20 §3.7） |
| `NativeApp/Features/AccountsView.swift` | `AccountsView` 重写为平台分组三行列表，数据与定时器移到 `Accounts/AccountListModel.swift`，去掉“显示字段”工具栏、“筛选与排序”表单、“前台自动刷新”开关与“快捷编辑”（20 §1.7）；`accountRow(_:)` → `Accounts/AccountRow.swift`（20 §1.7）；`AccountDetailView` → `Accounts/AccountDetailScreen.swift`，删“管理操作”“记录与分析”两节，沿用票据与会话代际守卫、轮询间隔改 60 秒（20 §2.7）；`AccountDetailView.mutate` 删除，动作移到 `AccountActions`（20 §5.7）；`AccountTestView` → `Accounts/AccountTestSheet.swift`，复用 `sanitizedTestOutput`（20 §4.7）；`prepareBatch` / `executeBatch` / `outcomeSheet` → `Accounts/AccountBatchDock.swift`，去掉“确认执行”确认框与批量“刷新凭据”（20 §8.7）；第 484–486 行改传 `LogsRoute`（40 §6.7）；分组下钻的过渡版本可复用 `AccountsView(initialGroupID:)`（50 §8.7） |
| `NativeApp/Features/AnalyticsView.swift` | 重写为卡片流 `AnalyticsView(route:)`：删 `init(accountID:groupID:)`、“今日 / 近7天 / 本月”按钮、`AnalyticsFilterView`、四个旧分区与“上游成本”“扣费与成本差额”文案，保留 `load(_:fixture:operation:)` 与 `isCurrent` 守卫（40 §1.8）；“消费明细”链接由 `AnalyticsChartView` 取代（40 §3.7） |
| `NativeApp/Features/CaptchaView.swift` | `CaptchaRequest` 加 `path`、`showsFallbackHint`；`CaptchaWebView.makeUIView` 用 `request.path`；`mobile_verify_path` 为空时顶部提示条；加载失败文案改为 00 §1.5 的“站点未部署手机验证页…”（60 §4.7）；`CaptchaView` 与 `CaptchaBridgeValidator` 其余复用（00 §9.7） |
| `NativeApp/Features/DashboardView.swift` | `DashboardView` 整体换成 `Home/HomeView.swift`，三个 30 秒轮询合成一个 60 秒轮询；`DashboardTrendChart` 移交统计分析，首页改用 `HomeHourlyChart`；`DashboardLoadState` 挪到 `NativeApp/Views/LoadState.swift` 并改存 `BlockState`；`costBreakdown` / `costValue` / `needsCostSnapshot` 的账号成本退路移进 `LiveOpsStore`，金额不再按颜色区分；`performanceCard` 删除（10 §1.7、§8） |
| `NativeApp/Features/GroupsView.swift` | 内容迁到 `NativeApp/Features/Groups/` 后删除（50 §9）：`GroupsView` → `GroupListView`（本地搜索 + 三段分区，一次拉全量），`GroupWorkspace` → `GroupStore`（50 §1.7）；`GroupDetailView` 重写，删“查看与管理分组账号”“统计分析”链接，“请求记录”改为“记录与关联”三行，文案改“正常 / 费率倍数 / 标准（余额）/ 每用户 RPM”，保留待确认流程与 `groupWriteDefinitelyRejected`（50 §2.7）；`GroupEditorView` → `GroupEditSheet`（50 §3.7）；第 192 行入口改为分组详情成员（20 §2.7）；第 195–196 行改传 `LogsRoute`（40 §6.7） |
| `NativeApp/Features/LoginView.swift` | `submit()`：去掉“暂不支持原生验证”分支，改为 `conflict` 判断 + 一律打开桥页；三种登录方式与 `sat_` 自动识别；成功回执用 `admin/me` 的身份；凭据用 `.accessToken`（60 §4.7） |
| `NativeApp/Features/PerformanceTrendView.swift` | 抽成 `PerfTrendBody(filter:size:startMetric:)`：“最新一桶”大数、峰值 / 平均副行、说明文案、明细“只覆盖 N 秒”、`OPS_DISABLED` 显示 `OpsDisabledNotice`、RPM 用 00 §6.2 格式（40 §2.7）；首页不再内嵌（10 §8） |
| `NativeApp/Features/RequestLogsView.swift` | 拆成 `Logs/LogsView.swift`、`LogRow.swift`、`LogFilterPickerSheet.swift`：分段改“用量明细 / 错误请求 / 上游错误”，标题改“使用记录”，删数字 ID 输入与分类 / 状态码 / 处理状态 / 请求类型选择器，时间改胶囊菜单，`init(route: LogsRoute)`（40 §6.7）；私有 `UsageRequestDetailView`、`RequestErrorDetailView` 删除，换 `Logs/RequestDetailView.swift`（40 §7.7）；第 371 行打开账号详情改用 `AccountDetailScreen`（20 §2.7） |
| `NativeApp/Features/SettingsView.swift` | 不再作为 Tab 根，由搜索目录 push（60 §1.7）；重写为 60 §3.3 的分区，保留“站点”“待确认余额请求”“关于”的逻辑与确认框文案；删除站点 / 退出前插入推送设备清理与 `sat_` 吊销（60 §3.7） |
| `NativeApp/Features/UsersView.swift` | `UsersView`：删状态 Picker 与“显示字段”，行改设计稿 `cols` 布局，加头像条、列表头图例、副标题，请求加排序与 `include_subscriptions=false`，加 `users-usage` 与 60 秒前台刷新（30 §1.7）；`UserDetailView` 重写为 hero 布局，各分区并发加载、各自错误态，本月消费改读 `total_actual_cost` 并按服务器时区算月份，`changeStatus()` 去掉确认框、加 Idempotency-Key（30 §2.7）；`BalanceView` → `Users/BalanceKeypadSheet.swift`，`definitelyRejected`（第 539 行）随之删除，判定迁到 `BalanceReconciliation.balanceWriteOutcome(for:)`（30 §3.7）；`UserEditorView` 与 `PreparedUserMutation` 删除，改 `Users/UserEditView.swift`（30 §5.7、§6.7）；第 159 行改用 `key_masked`（30 §7.7） |
| `NativeApp/Resources/Info.plist` | 加 `NSFaceIDUsageDescription`：“用于确认删除、批量操作、更换账号凭据和超过门槛的资金操作”（60 §3.7） |
| `NativeApp/Session/AppModel.swift` | `connect` 用 `me()` 替换 `verifyAdministrator()`，结果存 `SiteSession`（`me`、capabilities、服务器时区、时钟偏差、`accessTokenScope` / `isReadOnlyToken`），`sat_` 登录后补取 scope；全局拦截合规、step-up、会话失效；三类待核对 `pendingBalances` / `pendingRedeemBatches` / `pendingCompensations` 各自文件与 `remember` / `resolve`，`pendingMoneyWrites(serverID:)`，`reconcile(_:)` 分派；`scenePhase` 生命周期；`logout` / `remove(_:)` 顺序（先删推送设备，再吊销 `sat_` 或 `auth/logout`，最后擦凭据、ETag 缓存与游标）；`report(_:)` 加“详情”（00 §9.5，60 §3.7、§7.7、§11.7、§19.7，R01、R14）；首页接口包装、UI 测试分支、`LiveOpsStore` 随会话代号重建（10 §1.7）；后台测试任务表（20 §4.7）；余额 `reconcile(_ op:)` 与回到前台自动核对（30 §3.7）；`dashboardPerformanceTrend(hours:)` 的 `end` 向下取整到分钟、加筛选参数（40 §2.7） |
| `NativeApp/Session/CredentialVault.swift` | `KeychainCredentialStore.deviceID(serverID:)`（account = `<站点 UUID>.device`，`WhenUnlockedThisDeviceOnly`），`remove(serverID:)` 一并删除；`Credential` 加 `.accessToken` 并把以 `sat_` 开头的旧 `.adminKey` 迁过去；待删除的推送设备 id 存 `UserDefaults`（00 §9.6） |
| `NativeApp/Session/DemoData.swift` | 首页 6 种 UI 测试数据（10 §1.7）；与设计稿 `DEMO.accounts` 对应的 11 个演示账号（20 §1.7）。分组的 UI 测试 fixture 在 `GroupStore` 里，改为设计稿的 10 个分组（50 §1.7） |
| `NativeApp/Sub2MobileApp.swift` | `MainTabs` 改 `TabView(selection: $router.selectedTab)`：概览（`HomeView`）· 账号 · 用户 · 监控（`MonitorView`）+ 搜索 Tab，每 Tab 一个 `NavigationStack(path:)`，Tab 栏上方叠加回执（10 §0.7、§4.7）；去掉“管理”“设置”两个 Tab，删除 `ManagementView`，其“请求记录与错误日志”“统计分析”“分组管理”三项并入搜索目录（60 §1.7，40 §6.7，50 §1.7）；账号 Tab `.badge(errorCount)`（20 §1.7）；`RootView` 加 `.preferredColorScheme`（60 §3.7）；`@UIApplicationDelegateAdaptor` 处理 APNs 令牌回调与通知点按（60 §7.7） |
| `NativeApp/Views/Components.swift` | 改到对应页面时把系统色（如 `secondarySystemGroupedBackground`）换成 `Palette` 令牌（00 §8.2.6） |
| `Sources/Sub2Core/APIClient.swift` | **通用层**：`makeRequest`（固定 UA、`X-Device-ID`、`X-Request-ID`、`If-None-Match`，`.accessToken` 走 `x-api-key`）、`login` / `LoginBody`（`client`、`captcha_provider`、`aliyun_captcha_param`）、`acceptLogin`、`verifyAdministrator` → `me()`（旧服务端 Admin Key 探针用 `admin/compliance`）、`request`（所有方法 `TOKEN_EXPIRED` 刷新后重发、`APIResponse<T>` 与 `requestWithHeaders`、按 `RequestClass` 自动重试、429）、`ErrorEnvelope` 解码、刷新失败区分清会话与保留会话、`logout` 带 `Authorization`、`stepUp` 返回 `expires_in`、写接口返回 `WriteOutcome`、`dates` / `dateRange` / `monthRange` 改服务器时区、`pagination` 可传 1–1000，新增会话、合规、令牌、推送方法（00 §9.1，60 §4.7、§10.7）。**首页与监控**：新增 `dashboardHome`、`dashboardRates`、`accountStatusSummary`、`errorAccounts`、`accountsRanking`、`opsOverview`、`opsSnapshotV2`、`opsConcurrency`、`systemMetricsHistory`、`systemLogsHealth`、`ingressRejections`、`channelOverview`、`alertEvents`、`alertEventCounts`、`alertEvent`、`alertRules`；删 `dashboardMonitoring()` / `OpsReply`；`dashboardTrend` 改服务器时区（10 §1.7、§3.7、§4.7、§5.7、§6.7，R19）。**账号**：`accountTodayStats` 返回结构体（`failed_account_ids`、`degraded`、可选 `group_id`，按 200 拆批）、`account(id:)` 加返回 ETag 的变体、`deleteAccount`、`accountModels`、`revertAccountProxyFallback`、`testAccount` 读到 `test_result` 或 EOF 才结束、`setSchedulable` 可带 key、`refreshManagedAccount` 解码账号与 `warning`（20 §1.7、§2.7、§3.7、§4.7、§5.7、§6.7）。**用户**：`users(query:)`、`quickTopup`、`usersTodayUsage`、`deleteUser`、`setUserStatus`、`userKeys` 加 masked 与排序、`updateBalance` 加 `X-Request-ID` 并在失败时也取 action id、`userAdjustments`、`balanceHistory`、`createUser` 带 key，以及属性、RPM、Key、平台限额、替换分组等（30 §1.7–§8.7、§10）。**日志与统计**：`requestRecords` / `errorRecords` 返回 `Page<…>`、`errorCount`、`searchUsageUsers`、`errorDetail`、`requestAttempts`、`setErrorResolved`、`dashboardPerformanceTrend(_ query: OpsQuery)`、四个 ops 图表方法（40 §2.7、§6.7、§7.7）。**搜索**：账号、用户列表的 `pageSize` / `lite` 统一走查询结构（60 §2.7，R19） |
| `Sources/Sub2Core/APIError.swift` | `Kind` 加 `stepUp`、`readOnly`、`rateLimited`、`idempotency`、`conflict`、`notFound`、`unsupported`、`featureDisabled`、`temporary`；按（HTTP 状态, reason）精确查表，不再子串匹配（423 不再归为二次验证）；加 `retryAfter`、`metadata`、`requestID`；缺失文案“不可用”改 `—`（00 §9.3）；409 混合渠道另解 `details`、412 可识别（20 §11）；失败响应头里的 `X-Admin-Adjustment-Action-ID` 可取（30 §3.7） |
| `Sources/Sub2Core/AccountManagement.swift` | `AccountListQuery`：`page_size` 可配（默认 500）、`status` 改多值集合、排序加 `urgency`、`includeCounts`（只在第 1 页带，R09），并承担日志筛选、分组添加账号、全局搜索的账号查询（`pageSize`、`lite`、`search`、`platform`、`group`，R19）（20 §1.7）；`managedAccounts` 返回 `AccountListPage { items, total, page, pageSize, pages, counts? }`，ETag 交给 `ConditionalCache`（R08）；新增 `AccountPatchRequest`（`credentialsPatch` / `extraPatch` 能编码显式 `null`）与 `patchAccount(id:body:ifMatch:)`，旧 PUT 留作退路并按附录 A S31 合并整份 `credentials` / `extra`（20 §3.7） |
| `Sources/Sub2Core/AccountPresentation.swift` | `AccountFieldPresentation` 保留，留给简化模式（20 §1.7） |
| `Sources/Sub2Core/DashboardPresentation.swift` | `compactNumber`、`money`、`cost`、`duration` 迁到 `DisplayFormat` 后删除；只保留 `trendDate`（时区参数改服务器时区）、`fixed` 等与格式无关的部分（00 §6.2、§6.4，R10）；`rpmValue` / `performanceWindow` 首页不再使用（10 §1.7） |
| `Sources/Sub2Core/DashboardTrend.swift` | `DashboardTrendMetric.actualCost.label` 由“实际消费”改“实际扣费”（40 §1.8） |
| `Sources/Sub2Core/GroupManagement.swift` | `AdminGroup` 加 `sortOrder`、`errorAccountCount` / `idleAccountCount`（`Int?`，nil = 老服务端）、`claudeCodeOnly`、`fallbackGroupID`；`allGroups(includeInactive:)`（20 §1.7，50 §2.7）；新增 `groupList()`（ETag 走 `ConditionalCache`，R08）、`groupUsageSummary()`、`groupCapacities(groupIDs:)`、`groupStats(id:)`（没有 `subscriptions_total` 键返回 nil）、`groupTodayUsage(id:serverTimezone:)`、`duplicateGroup(id:idempotencyKey:)`、`groupAPIKeys(id:page:)`、`groupSubscriptions(id:page:)`、`activeSubscriptionCount(groupID:)`；`createGroup` / `updateGroup` / `deleteGroup` 加 `idempotencyKey`，`PreparedGroupWrite` 保存这个 key；`GroupCreateRequest` 默认平台改 `anthropic`；`GroupPlatform.values` 拆出 `concrete`（50 §1.7、§2.7、§3.7、§6.7、§7.7、§9） |
| `Sources/Sub2Core/HTTPTransport.swift` | 保留 ephemeral、无缓存、拒绝重定向；304 空响应体不报错；统一用小写键读 `retry-after`、`x-idempotency-replayed`、`date` 等（00 §9.2） |
| `Sources/Sub2Core/ListFields.swift` | `ListFieldSelection` 保留，留给简化模式（30 §1.7） |
| `Sources/Sub2Core/Models.swift` | `AuthenticationKind` / `Credential` 加 `accessToken`；`CaptchaProof` 加 `provider`、`aliyunParam`；`PublicSettings` 保留原始字段（`hasCaptchaProviderKey`、`mobileVerifyPath`、服务器时区、版本、站点名、后端模式、TOTP、登录协议），`conflict` 不在解码阶段抛错；`Page<T>` 的 `total` / `pages` 可空、加 `hasMore` / `sinceID` / `latestID`，约束放宽为 `Decodable & Sendable`；`PendingBalanceOperation` 扩字段（`requestID`、`actorUserID`、`createdAt`、`userDisplayName`、`userEmail`、`actionID?`、`idempotencyExpiresAt?`，`decodeIfPresent` 兼容旧记录）（00 §9.4，30 §3.7，40 §6.7）；删 `OpsSnapshot`、`DashboardSummary.monitoring`（10 §8）；`UpstreamAccount` 加结构化错误、`token_status`、运行时、回退代理、`credentials_status` 等字段，`extra` 保留原始 JSON 并派生 `modelRateLimits`（20 §1.7）；`AdminUser` 补 `totalRecharged`、阈值、`allowedGroups`、`groupRates`、`restrictPublicGroups`，删多余的 `userCost` / `standardCost` 解码（30 §1.7）；`UserAPIKey` 扩为 `AdminAPIKey`，`key` 解码后立即置空（30 §7.7）；`TrendPoint` 加四类 Token 与 `accountCost: Decimal?`（40 §1.8）；`UpstreamAccount.proxy` 现只解码名称与编号，代理行改 push 代理详情（60 §12.7） |
| `Sources/Sub2Core/PerformanceTrend.swift` | `rate(_:metric:)` 按每桶实际覆盖秒数折算；加 `windowStart` / `windowEnd`、`Point.switchCount`、`coveredSeconds` / `peak` / `average`、未知桶长兜底（40 §2.7，10 §8） |
| `Sources/Sub2Core/RequestLogs.swift` | `RequestLogFilter` 的时间改为 `LogTimeWindow`（`.range` / `.rolling` / `.none`），加 `modelSource`、`pageSize`；`queryItems` 改站点时区、加 `key_view=masked`、去掉上游错误的筛选限制；新增 `incrementalQueryItems(sinceID:)`；`RequestLogPage` 删除改用 `Page<T>`；`UsageRequestRecord` 优先读 `account_cost`，加 `providerCostRecorded`、`userName`、`apiKeyName`、`apiKeyMasked`；`RequestErrorRecord` 加 D04 耗时等字段与上游状态码取法计算属性（20 §2.7 状态卡共用）；新增 `RequestErrorDetail`、`RequestAttempts` / `RequestAttempt`（40 §6.7、§7.7，20 §2.7） |
| `Sources/Sub2Core/SSEParser.swift` | 有 `accounts.test_result` 时以 `test_result`（或 EOF）为终止事件；`AccountTestEvent` 加 `data`（`AccountTestResult`）、`model`、`status`（20 §4.7） |
| `Sources/Sub2Core/UsageAnalytics.swift` | `AnalyticsQuery` 加 `modelSource`、显式 `granularity`、站点时区必传、`start_time` / `end_time` 输出 UTC `Z`；`AnalyticsSummary` 加 `standardCost`、缓存 Tokens、`endpoints` / `upstreamEndpoints`，`difference` 改名 `profit`；`AnalyticsBreakdown` 加 `standardCost`；`usageAnalysisModels(_:source:)`；新增用户排行、用户用量趋势、请求类型的解码与方法（40 §1.8、§2.7） |
| `Sources/Sub2Core/UserManagement.swift` | `UserCreateRequest` 加 `allowedGroups`、`restrictPublicGroups`，`balance` 为 nil 时不编码，`AdminUserRole.title` 改“用户 / 供应商 / 管理员”（30 §5.7）；`UserUpdateRequest` 加 `status`、`allowedGroups`、`restrictPublicGroups`、`groupRates`（nil 值编码为 JSON `null`），`validate()` 同步扩充，倍率 > 0 且 ≤ 3 位小数；`PendingUserUpdateOperation.supportsSafeRetry` 在有 `admin.idempotent_writes` 时恒为 true（30 §6.7） |
| `Sub2Mobile.xcodeproj` 与 entitlements | 打开 Push Notifications 能力（用 `interruption-level: time-sensitive` 时另加 Time Sensitive Notifications）；Debug 用 `aps-environment=development` 的 entitlements，并定义编译条件（如 `APNS_SANDBOX`），只在该条件下登记 `environment:"sandbox"`（60 §7.7）；工程文件由 `scripts/generate_project.py` 生成（50 §1.7） |
| `Tests/Sub2CoreTests/DashboardRPMTests.swift`、`OverviewPresentationTests.swift` | 随 `performanceCard` 删除而更新（10 §1.7） |
| `Tests/Sub2CoreTests/GroupManagementTests.swift` | 新字段解码（含键缺失）、四桶推导与退路、健康判定、`groupStats` 老服务端识别（50 §2.7、§9） |
| `Tests/Sub2CoreTests/PerformanceTrendTests.swift` | 改为覆盖秒数口径（1 分钟、5 分钟残桶，首尾都不满）（40 §2.7） |
| `Tests/Sub2CoreTests/RequestLogsTests.swift` | `account_cost` 与 `provider_cost_recorded`、D04 字段、since_id 信封、`LogTimeWindow`、`upstream_errors` 解析、attempts 解码（含 null 计时的旧事件）与副行文案（40 §6.7、§7.7） |
| `Tests/Sub2CoreTests/UsageAnalyticsTests.swift` | 新解码与 `model_source`（40 §1.8） |
| `UITests/AccountListCustomizationUITests.swift`、`AccountManagementUITests.swift` | 按新列表与详情重写（20 §1.7） |
| `UITests/AnalyticsUITests.swift` | 按新标识重写，覆盖范围记忆（第一次从搜索进是近 7 天；改成 30 天后从概览进仍是 30 天；换站点回到入口默认值）（40 §1.8） |
| `UITests/RequestLogsUITests.swift` | 按新布局重写，覆盖自动刷新后新行出现在顶部、超过 N 行且停在顶部时裁尾（40 §6.7）；请求详情三种样子与“标记已处理”的撤销（40 §7.7） |
| `docs/ADMIN_MODULES.md` | “独立日志筛选边界”按 D03 更新（40 §6.7） |
| `docs/API_COMPATIBILITY.md` | 第 54 行“边界桶仍按完整桶宽计算”改为覆盖秒数口径（40 §2.7） |
| `scripts/generate_project.py` | 不改；每次新增 Swift 文件后运行，重新生成 `Sub2Mobile.xcodeproj`（50 §1.7） |

### 二、新增文件

| 文件 | 内容（出处） |
|---|---|
| `NativeApp/Design/Palette.swift` | 颜色令牌与 `Tone`（00 §8.2.6） |
| `NativeApp/Features/Accounts/AccountActions.swift`（建议名） | 恢复、启停调度、启用账号的动作与回执、撤销，详情 / 列表 / 概览 / 分组共用（20 §5.7） |
| `NativeApp/Features/Accounts/AccountAlertSheet.swift` | 组头告警牌的“告警”sheet（20 §1.4、§1.7） |
| `NativeApp/Features/Accounts/AccountBatchDock.swift` | 选择模式操作坞与结果 sheet（20 §8.7） |
| `NativeApp/Features/Accounts/AccountCredentialSheets.swift` | 更换 API Key、Base URL、重新授权（20 §6.7） |
| `NativeApp/Features/Accounts/AccountDetailScreen.swift` | 账号详情（状态卡、容量、今日、记录 + 六个分区）（20 §2.7、§3.7） |
| `NativeApp/Features/Accounts/AccountExpiryPicker.swift`、`AccountGroupPicker.swift`、`AccountModelEditor.swift`、`AccountProxyPicker.swift` | 内联编辑的选择器（20 §3.7） |
| `NativeApp/Features/Accounts/AccountListModel.swift` | 列表的查询、分页、计数、汇总、今日、运行时、冻结的平台顺序（20 §1.7） |
| `NativeApp/Features/Accounts/AccountNewDraft.swift`、`AccountNewView.swift` | 新建账号表单、坞、测试 sheet 与状态机（20 §7.7） |
| `NativeApp/Features/Accounts/AccountRow.swift` | 三行账号行 + 状态胶囊 + 倒计时，分组成员、搜索结果复用（20 §1.7，50 §2.7，60 §2.7） |
| `NativeApp/Features/Accounts/AccountScheduledTestsView.swift` | 定时测试小页（20 §9.7） |
| `NativeApp/Features/Accounts/AccountSectionSheet.swift` | 基础 / 调度 / 模型 / 高级编辑 sheet（20 §3.7） |
| `NativeApp/Features/Accounts/AccountTestSheet.swift` | 测试连接（20 §4.7） |
| `NativeApp/Features/Accounts/OAuthFlow.swift` | OAuth 三步清单、回调解析、可选本机监听（20 §6.7、§7.7） |
| `NativeApp/Features/Analytics/AnalyticsCards.swift`、`AnalyticsCharts.swift`、`AnalyticsSession.swift`、`AnalyticsSheets.swift` | 卡片流、图表组件、会话与本机记忆、范围与筛选 sheet（40 §1.8） |
| `NativeApp/Features/Analytics/AnalyticsChartBodies.swift`、`AnalyticsMoreView.swift` | 12 个图表 body 与更多图表页（40 §2.7） |
| `NativeApp/Features/Analytics/AnalyticsChartView.swift` | 单图页（40 §3.7） |
| `NativeApp/Features/Analytics/AnalyticsModelView.swift` | 模型页（40 §5.7） |
| `NativeApp/Features/Analytics/AnalyticsRankView.swift` | 全部排行（40 §4.7） |
| `NativeApp/Features/Announcements/AnnouncementDetailView.swift`、`AnnouncementPreviewCard.swift`、`MiniMarkdownView.swift` | 公告详情、预览卡、最小 Markdown 渲染（60 §16.7） |
| `NativeApp/Features/Announcements/AnnouncementEditSheet.swift` | 编辑 / 新建公告（60 §17.7） |
| `NativeApp/Features/Announcements/AnnouncementReadsView.swift` | 已读情况（60 §18.7） |
| `NativeApp/Features/Announcements/AnnouncementsView.swift` | 公告列表（60 §15.7） |
| `NativeApp/Features/ComplianceSheet.swift`、`StepUpSheet.swift` | 全局合规确认与二次验证 sheet（00 §9.7） |
| `NativeApp/Features/Groups/GroupAccountPicker.swift` | 添加账号（直接打开与 sheet 内子页共用）（50 §4.7） |
| `NativeApp/Features/Groups/GroupBatchResultView.swift` | 成员批量写入逐项结果（50 §5.7） |
| `NativeApp/Features/Groups/GroupCellsView.swift` | 色格条与图例（50 §1.7） |
| `NativeApp/Features/Groups/GroupDetailView.swift` | 分组详情（50 §2.7） |
| `NativeApp/Features/Groups/GroupEditSheet.swift` | 编辑 / 新建分组（50 §3.7） |
| `NativeApp/Features/Groups/GroupKeysView.swift` | 分组 API 密钥（50 §6.7） |
| `NativeApp/Features/Groups/GroupListView.swift`、`GroupStore.swift` | 分组列表与共享状态（50 §1.7） |
| `NativeApp/Features/Groups/GroupSubscriptionsView.swift` | 分组订阅（50 §7.7） |
| `NativeApp/Features/Home/HomeAttentionList.swift`、`HomeHourlyChart.swift`、`HomeRunSection.swift`、`HomeTicker.swift`、`HomeTodaySection.swift`、`HomeView.swift` | 概览常规布局（10 §1.7） |
| `NativeApp/Features/Home/HomeCalmView.swift` | 平静布局（10 §2.8） |
| `NativeApp/Features/Home/OpsDisabledNotice.swift` | “运维监控未开启”组件，全 App 共用（10 §1.7、§7.2，40 §1.4） |
| `NativeApp/Features/Logs/LogFilterPickerSheet.swift`、`LogRow.swift`、`LogsView.swift` | 使用记录（40 §6.7） |
| `NativeApp/Features/Logs/RequestDetailView.swift` | 请求详情（40 §7.7） |
| `NativeApp/Features/Monitor/AlertDetailView.swift` | 告警详情（10 §3.7） |
| `NativeApp/Features/Monitor/AlertRow.swift`、`AlertsSection.swift` | 告警段与告警行（首页复用）（10 §6.7） |
| `NativeApp/Features/Monitor/AlertActions`（文件名自定） | 手动解决、静默、改时长、结束静默（10 §7.1、§8） |
| `NativeApp/Features/Monitor/ChannelsSection.swift` | 渠道段（10 §5.7） |
| `NativeApp/Features/Monitor/MonitorOverviewSection.swift`、`MonitorServerSection.swift`、`MonitorView.swift` | 监控 Tab 与概况段（10 §4.7） |
| `NativeApp/Features/Proxies/ProxiesView.swift` | 代理列表（60 §12.7） |
| `NativeApp/Features/Proxies/ProxyDetailView.swift`、`ProxyFallbackAccountsView.swift`、`ProxyLatencyBlock.swift` | 代理详情、被改走的账号、延迟块（60 §13.7） |
| `NativeApp/Features/Proxies/ProxyEditSheet.swift` | 编辑 / 添加 / 续期代理（60 §14.7） |
| `NativeApp/Features/Redeem/RedeemCodeBox.swift`、`RedeemCodeCard.swift`、`RedeemCodesView.swift` | 兑换码列表、卡片、码值框（60 §8.7） |
| `NativeApp/Features/Redeem/RedeemEditSheet.swift` | 编辑兑换码（60 §9.7） |
| `NativeApp/Features/Redeem/RedeemGenerateSheet.swift` | 批量生成向导（60 §10.7） |
| `NativeApp/Features/Redeem/RedeemGrantSheet.swift` | 发放兑换码（补偿）（60 §19.7） |
| `NativeApp/Features/Redeem/RedeemReconcileView.swift` | 生成结果待核对 / 没找到 / 核对结果（60 §11.7） |
| `NativeApp/Features/Search/GlobalSearchResultsView.swift`、`SearchResultsListView.swift` | 全局搜索结果与“查看全部”结果页（60 §2.7） |
| `NativeApp/Features/Search/SearchHomeView.swift` | 搜索目录（60 §1.7） |
| `NativeApp/Features/Settings/APNsConfigSheet.swift`、`PushSettingsView.swift`、`PushTargetDetailView.swift`、`PushTargetSheet.swift` | 推送通知设置（60 §7.7） |
| `NativeApp/Features/Settings/AccessTokensView.swift` | 管理访问令牌（60 §6.7） |
| `NativeApp/Features/Settings/SessionsView.swift` | 登录设备（60 §5.7） |
| `NativeApp/Features/Users/BalanceKeypadSheet.swift` | 充值 / 退款键盘（30 §3.7） |
| `NativeApp/Features/Users/PlatformQuotaSection.swift`、`ReplaceGroupSheet.swift` | 平台限额、替换分组（30 §8.7） |
| `NativeApp/Features/Users/QuickTopupStrip.swift` | 快捷充值头像条（30 §1.7） |
| `NativeApp/Features/Users/UserDetailView.swift` | 用户详情（30 §2.7） |
| `NativeApp/Features/Users/UserEditAccessSection.swift`、`UserEditBasicSection.swift`、`UserEditView.swift`、`UserGroupSheets.swift`、`UserRPMStatusView.swift` | 新建 / 编辑用户（`UserEditorModel`）（30 §5.7、§6.7） |
| `NativeApp/Features/Users/UserKeyCards.swift`、`UserKeyFormSheet.swift`、`UserKeyGroupSheet.swift`、`UserKeyRevealSheet.swift` | API Key 卡片、新建 / 编辑表单、换分组、揭示（30 §7.7） |
| `NativeApp/Features/Users/UserLedgerView.swift` | 充值与调整记录（30 §4.7） |
| `NativeApp/Session/AppPreferences.swift`、`BiometricGate.swift` | 本机设置与 Face ID 门控（60 §3.7） |
| `NativeApp/Session/AppRouter.swift` | 路由与跨 Tab 跳转（10 §0.7、§8） |
| `NativeApp/Session/LiveOpsStore.swift` | 首页、监控、告警共享状态（10 §0.5、§8） |
| `NativeApp/Session/PushCoordinator.swift` | 通知权限、APNs 令牌、按站点登记 / 删除、点按路由（00 §9.7，60 §7.7） |
| `NativeApp/Views/LoadState.swift` | 由 `DashboardLoadState` 迁来，内部存 `BlockState`（10 §0.5） |
| `NativeApp/Views/Receipt.swift` | 回执 toast 与 `ReceiptCenter`（10 §0.7-6） |
| `NativeApp/Views/StatusRail.swift` | 状态胶囊与状态轨（10 §0.7-7） |
| `Sources/Sub2Core/AccessTokens.swift` | `AdminAccessToken`、`accessTokens()`、`revokeAccessToken(id:)`（60 §6.7） |
| `Sources/Sub2Core/AccountCreate.swift` | `createAccount(_:idempotencyKey:)`（20 §7.7） |
| `Sources/Sub2Core/AccountDisplayState.swift` | 账号显示状态唯一推导函数（20 §0.2） |
| `Sources/Sub2Core/AccountMixedChannel.swift` | 混合渠道预检与 409 解码（20 §3.7） |
| `Sources/Sub2Core/AccountOAuth.swift` | 各平台授权链接、换码、`reauthorize`、`applyOAuthCredentials`（20 §6.7） |
| `Sources/Sub2Core/AccountRecovery.swift` | `recoverAccountState(id:schedulable:)`（20 §5.7） |
| `Sources/Sub2Core/AccountRuntimeBatch.swift` | `accountRuntime(ids:)`（20 §1.7） |
| `Sources/Sub2Core/AccountStatusSummary.swift` | D02 汇总模型与 `accountStatusSummary(platform:groupID:includeAccounts:)`（20 §10，10 §1.7，R19） |
| `Sources/Sub2Core/AccountTestRuns.swift` | 异步测试（20 §4.7） |
| `Sources/Sub2Core/AccountUsageWindow.swift` | `accountPassiveUsage(id:)`（20 §2.7） |
| `Sources/Sub2Core/AccountsRanking.swift` | 账号排行（20 §10.3） |
| `Sources/Sub2Core/AdminMe.swift` | `AdminMe` 与 capability 常量（00 §9.7） |
| `Sources/Sub2Core/AlertPresentation.swift`、`OpsAlerts.swift` | 告警模型与文案函数（10 §3.7） |
| `Sources/Sub2Core/AnalyticsRange.swift`、`ProfitRows.swift` | 范围计算、最大余额法分到分（40 §1.8） |
| `Sources/Sub2Core/Announcements.swift` | 公告模型、可见对象文案、接口（60 §15.7） |
| `Sources/Sub2Core/AuthSessions.swift` | 会话列表与下线（60 §5.7） |
| `Sources/Sub2Core/BalanceReconciliation.swift` | 账本匹配与 `balanceWriteOutcome(for:)`（30 §3.7） |
| `Sources/Sub2Core/BlockState.swift` | 区块状态（10 §0.5） |
| `Sources/Sub2Core/ChannelMonitor.swift` | 渠道监控模型（10 §5.7） |
| `Sources/Sub2Core/ConditionalCache.swift` | ETag 缓存（00 §4.2、§9.7） |
| `Sources/Sub2Core/DashboardHome.swift` | 首页聚合模型（10 §1.7） |
| `Sources/Sub2Core/DisplayFormat.swift` | 全部格式函数（00 §6、§9.7） |
| `Sources/Sub2Core/ErrorEnvelope.swift` | 错误信封解码（00 §3.1） |
| `Sources/Sub2Core/GlobalSearch.swift` | 全局搜索扇出与判定（60 §2.7） |
| `Sources/Sub2Core/GroupMembers.swift`、`GroupPresentation.swift` | 成员批量写入、健康判定、色格与文案（50 §3.7、§9） |
| `Sources/Sub2Core/HomePresentation.swift` | 6 格、待处理、平静判定（10 §1.7） |
| `Sources/Sub2Core/IdempotentWrite.swift` | `WriteOutcome`、`PendingMoneyWrite`、`PendingCompensation`（00 §2.5、§9.7） |
| `Sources/Sub2Core/IncrementalList.swift` | 增量游标与按 id 合并（00 §4.3） |
| `Sources/Sub2Core/JSONValue.swift` | 任意 JSON 值（20 §3.7） |
| `Sources/Sub2Core/MetaCatalog.swift` | `metaCatalog()` 与内置兜底清单（20 §7.7） |
| `Sources/Sub2Core/MonitorPresentation.swift`、`OpsMonitoring.swift` | 运维模型、心跳文案、错误率序列（10 §4.7） |
| `Sources/Sub2Core/OpsAnalytics.swift` | `OpsQuery` 与四个 ops 图表模型（40 §2.7） |
| `Sources/Sub2Core/PlatformQuota.swift` | 平台限额模型与撤销决策（30 §8.7） |
| `Sources/Sub2Core/Proxies.swift` | 代理模型、到期计算、接口（含 `allProxies(withCount:)`）（60 §12.7，20 §3.7，R19） |
| `Sources/Sub2Core/Push.swift` | 推送设备、订阅、APNs 配置与接口（60 §7.7） |
| `Sources/Sub2Core/ReasonCatalog.swift` | reason → 动作 / 文案表（00 §3.2） |
| `Sources/Sub2Core/RedeemCodes.swift` | 兑换码模型、列表查询、生成、`PendingRedeemBatch`、补偿请求与订阅计划（60 §8.7、§10.7、§11.7、§19.7） |
| `Sources/Sub2Core/ScheduledTests.swift` | 定时测试（20 §9.7） |
| `Sources/Sub2Core/ServerTime.swift` | 服务器时区、`Date` 头偏差、时间解析（00 §6.3–§6.4） |
| `Sources/Sub2Core/UserKeys.swift` | `AdminAPIKeyStatus` 与 Key 写请求 / 结果（30 §7.7） |
| `Sources/Sub2Core/UserLedger.swift` | 充值与调整记录解码与文案（30 §4.7） |
| `Sources/Sub2Core/UserPresentation.swift` | 显示名、余额低判定、状态与角色词（30 §1.7） |
| `Tests/Sub2CoreTests/AlertPresentationTests.swift`、`AttentionItemsTests.swift`、`ChannelOverviewDecodingTests.swift`、`DashboardHomeDecodingTests.swift`、`HomePresentationTests.swift`、`MonitorPresentationTests.swift` | 10 §1.7、§8 |
| `Tests/Sub2CoreTests/AnalyticsRangeTests.swift`、`OpsAnalyticsTests.swift`、`ProfitRowsTests.swift` | 40 §1.8、§2.7 |
| `Tests/Sub2CoreTests/GroupMembersTests.swift`、`GroupPresentationTests.swift` | 50 §9 |
| 其余单测（文件名自定） | 00 §9.8（错误信封、reason 表、刷新、幂等写、格式、金额编码、增量、时间、能力）；20 §0.2 表驱动的 `AccountDisplayState`；30 §10 列的余额、Key、记录、核对等；60 §19.7 的补偿请求体、订阅计划与核对 |

---

## 全部未决问题

各章“本章未决问题”去重汇总，另加合稿时发现的两条（U53、U54）。没有用户决定前，按“建议默认值”实现。已经在别处定下、不再列入的：00 Q1（时区规则，已由 00 §6.3 定）、40 Q4（统计与日志按站点时区，同 00 §6.3）、60 Q10（并入 U02）。

| # | 问题 | 建议默认值 | 出处 |
|---|---|---|---|
| U01 | 是否支持 vendor（代运营工作区）登录 | 首版拒绝，文案“当前版本仅支持管理员账号”；各章 vendor 规则作为预留 | 00 Q2 |
| U02 | App 内是否签发管理访问令牌（Web 也没有签发界面） | 首版不签发，只支持粘贴 `sat_` 登录，以及在设置里列出、吊销 | 00 Q3、60 Q10 |
| U03 | 带 key 的写断网后自动用同一 key 重试几次 | 2 次（间隔 2 秒、5 秒，仅前台），之后转“待核对” | 00 Q4 |
| U04 | 增量拉取的回退窗口 | 按 `created_at` 回退 30 秒；解析失败时退 200 个 id | 00 Q5 |
| U05 | “可用不足分组”是否在待处理里单列 | 单列一行“可用不足 N 个分组”（只在 `shortage.is_short`、分组启用且组内有异常账号时）；出现时不进入平静布局 | 10 Q1 |
| U06 | 首页一次显示几条告警 | `alerts.top` 全部（≤ 5 条），其余合成“另有 N 条告警中” | 10 Q2 |
| U07 | 渠道行的目的页 | 进对应分组详情 | 10 Q3 |
| U08 | 监控 Tab 默认段 | 首次“概况”，本次会话内记住上次所选 | 10 Q4 |
| U09 | 入口拒绝的原因明细 | 本版不做，日志采集行不可点 | 10 Q5 |
| U10 | App 里是否提供“关闭运维监控” | 只在监控 Tab ··· 菜单放「关闭运维监控…」，站长、二次确认；首页不提供 | 10 Q6 |
| U11 | 首页 ··· 菜单内容 | 「刷新」「统计分析」 | 10 Q7 |
| U12 | 关监控时 RPM 只计成功请求，6 格是否单独标注 | 格内不加字，由“运维监控未开启”提示行说明 | 10 Q8 |
| U13 | “静默中的规则”列表 | 本版不做 | 10 Q9 |
| U14 | 应用骨架没有独立章节 | 本版以 10 §0.7 为准，路由合并 40 §0.1、50、60 §0.1；以后另写骨架章节再替换 | 10 Q10 |
| U15 | 账号列表加载上限 | `page_size=500`，最多 2000 行，超出提示用平台筛选；大站点实测后再定是否按平台懒加载 | 20 #1 |
| U16 | 新建 OAuth 账号时令牌经过手机 | 照 Web：令牌只在内存、不写日志、离开即丢；请后端评估给 `create-from-oauth` 加 `schedulable` / `skip_default_group_bind` | 20 #2 |
| U17 | Bedrock / Vertex 账号凭据类错误的主按钮 | “在 Web 中更换凭据”（C19 深链），“恢复状态”“测试连接”为次要 | 20 #3 |
| U18 | 新建时不选分组是否跳过默认分组 | 不传 `skip_default_group_bind`（与 Web 一致），表单脚注写明 | 20 #4 |
| U19 | 重新授权停用账号 | 不传 `preserve_status`，确认框写明“授权后账号会被重新启用” | 20 #5 |
| U20 | 定时测试是否进入详情 | “记录”节只读一行，计划维护留在 Web | 20 #6 |
| U21 | 批量“恢复状态 / 刷新令牌” | 只做“停止调度 / 启用调度”两个按钮，去掉现有批量“刷新凭据”；扩展按 20 §8.8，先给用户看效果图 | 20 #7 |
| U22 | 运维关闭时状态卡的出错时间行 | 有 `error_at` 时显示不可点的“出错于 HH:MM · N 分钟前”，否则不显示 | 20 #8 |
| U23 | 账号详情代理行的点按去向 | 有代理时 push 代理详情，选择器只从分区“编辑”进 | 20 #9 |
| U24 | Key 新建 / 编辑表单没有设计稿 | 按 30 §7.4 的最小表单（单页 Form，sheet），上线前请用户看效果图 | 30 #1 |
| U25 | “显示完整 Key”的入口 | Key 卡片 ⋯ 菜单第三项，每次本机身份验证 + 需要时 step-up | 30 #2 |
| U26 | `percentage` 阈值在 `total_recharged` 为 0 时 | 与服务端 `quick-topup` 一致；请后端确认是否有意为之 | 30 #3 |
| U27 | “全部余额”退款用 `set 0` | 采用 | 30 #4 |
| U28 | `multi_select` 自定义属性值格式 | App 只读显示原值，提示在 Web 修改 | 30 #5 |
| U29 | 主模式用户列表是否要状态筛选 | 去掉，留给简化模式 | 30 #6 |
| U30 | 余额扣成负数、禁用 / 删除管理员、降级最后一位管理员返回无 reason 的 500 | App 事前拦截；请后端补稳定 reason（如 `BALANCE_NEGATIVE`、`ADMIN_USER_PROTECTED`、`LAST_ADMIN`） | 30 #7 |
| U31 | 全部记录页的第三行“余额 a → b · 操作人” | 只在全部记录页显示，详情页最近 5 条保持两行 | 30 #8 |
| U32 | 上游错误列表项没有 `upstream_status_code` | 先从 `message` 解析，解析不到写“恢复 / 鉴权”；请后端在列表项加该字段 | 40 #1 |
| U33 | 使用记录没有状态码与 `billing_provenance` | 用量明细行一律显示 200；需要区分时请后端加 `billing_provenance` | 40 #2 |
| U34 | error-trend 上游分项不能叠成设计稿的五层 | 只叠 SLA 错误 + 业务限制，上游分项单列一行文字 | 40 #3 |
| U35 | 运维错误日志默认只保留 30 天 | 范围起点早于 30 天前时加提示，不截断范围 | 40 #5 |
| U36 | 后端没有站点开通日期、模型所属平台 | 自定义范围最早 366 天前，不写开通日期；模型页不写平台 | 40 #6 |
| U37 | vendor 能否在分组页加减成员 | vendor 隐藏全部成员写入口，注“调整成员请在账号详情里修改分组” | 50 #1 |
| U38 | 成员行“今日”的口径 | 有 `accounts.today_stats_group` 用分组口径，否则全站口径并用设计稿脚注 | 50 #2 |
| U39 | 停用确认里的 Key 数 | 停用确认用 `active_api_keys`；详情“API 密钥 N 个”与删除确认用 `total_api_keys` | 50 #3 |
| U40 | 搜索 Tab 在 iOS 27 的表现 | `.searchable` 挂在搜索 Tab 内部根视图、`.automatic`，iOS 26 / 27 实机各验一次；按钮并入 Tab 栏也接受 | 60 #1 |
| U41 | 目录“告警事件”的去向 | 切到监控 Tab 的“告警”分段 | 60 #2 |
| U42 | 简化模式在首版的呈现 | 设置里显示，置灰并标“设计中” | 60 #3 |
| U43 | G03 / G04 没有 capability 标记 | 用 `redeem_codes.stats` 推断；请后端加 `redeem_codes.batches` | 60 #4 |
| U44 | 公告列表 / 详情是否显示已读进度 | 有 `announcements.read_stats` 时列表写“已读 N/M”、详情写汇总 | 60 #5 |
| U45 | 生成向导第 3 步加“备注” | 加，选填，≤ 1000 字 | 60 #6 |
| U46 | APNs 站点配置放进 App | 放在推送通知页底部，仅站长；可编辑条件同 60 §7.3 | 60 #7 |
| U47 | 推送登记的 `site_tag` | `ServerProfile.id.uuidString`（00 §7.2 同） | 60 #8 |
| U48 | 关闭 Face ID 开关是否也要验证 | 开、关都验证一次 | 60 #9 |
| U49 | 兑换码 ··· 加“查看同一批” | 加，放在复制之后、删除之前 | 60 #11 |
| U50 | 会话列表本机行能否下线 | 不给，统一走“退出并清除凭据” | 60 #12 |
| U51 | 全局搜索“像请求 ID”的判定 | 去空白后不含空格与 `@`、长度 8–256，就加查使用记录与错误请求 | 60 #13 |
| U52 | 给并发不限制的用户发放并发补偿 | 并发磁贴置灰并说明原因，不提供发放 | 60 #14 |
| U53 | 账号过期时间按哪个时区显示与输入：00 §6.3 把账号 `expires_at` 列为“按本机时区”的例外，20 §0.6 / §3.3 却按服务器时区（选择器设 `\.timeZone` 为服务器时区） | 按 00 §6.3：本机时区，与公告起止、兑换码自定义过期一致；20 §3.3 的选择器去掉服务器时区环境值，脚注改“按本机时区 <TZ>”。若用户更看重与服务器判定同一天界，改用 20 的写法并从 00 例外清单删去这一项 | 合稿 |
| U54 | 重统计接口的客户端超时（R07 统一为 00 §2.3，40 §0.6 原值更长） | 先按 00 §2.3（统计聚合 45 秒、`dashboard/stats` 90 秒）；B10 / 维护者决定 Q17 在生产量级实测后，若 30 天范围的 `usage/stats`、`throughput-trend` 超过 45 秒，再把这两类放宽到 90 秒 | 合稿 |

---

## 审查未采纳的意见

各章 `spec/*.md` 末尾的“审查记录”逐条核实了审查意见，绝大多数已在章内改完，正文收录的就是改后的版本。下面只列两类：一是意见要求其他章同步、但其他章文件没有跟着改的（合稿时统一裁定）；二是有意没有照做的部分。

### 一、跨章裁定

正文与下表冲突时以本表为准。原则：通用机制以 00 为准，页面专属事实以所属章为准。

| # | 事项 | 采用的口径 | 受影响的正文 |
|---|---|---|---|
| R01 | 资金写的本机记录 | 以 00 §2.5.5 为准：三类记录 `PendingBalanceOperation` / `PendingRedeemBatch` / `PendingCompensation`，各一个文件，共同协议 `PendingMoneyWrite`。正文里的 `pendingWrites`、`PendingWrite`（`kind == .redeemGrant`、`authMethod` / `method` / `path` / `status` 等）一律读作 `pendingCompensations` / `PendingCompensation`；`PendingRedeemBatch` 补 `actorUserID`、`idempotencyExpiresAt` | 60 §3.2、§3.3、§11.2、§19.4、§19.7 |
| R02 | 待核对在概览与用户详情的显示 | 标题与说明行按 00 §2.5.5（`set` 且金额为 0 写“退款结果待核对”、金额位置写“全部余额”；`set` 且大于 0 才写“余额设置结果待核对”）。10 §1.3.3 在“兑换码生成待核对”之后加第 8 类“补偿结果待核对”：每条一行、caution 胶囊，余额类右侧写金额，说明行“{userDisplayName} · {相对时间} · 未确认是否发放”，点按打开 `.redeemGrant(userID:pendingID:)` 的结果待核对页（60 §19）。10 §2.2 平静布局条件 4 同样包括补偿记录。30 §2.3 用户详情的待核对横幅也显示该用户的补偿记录，按钮“核对”打开同一页 | 10 §1.3.3、§2.2，30 §2.3 |
| R03 | 待核对期间再发起同类写入 | 00 §2.5.4 第 4 条的例外只有两处：30 §3.4“仍要充值 / 仍要退款”（只拦同方向、两次确认）与 60 §8.4“仍要生成新的一批”。发放补偿没有例外（60 §19.1） | 00 §2.5.4 |
| R04 | 带 key 写的超时与重试数值 | 以 00 §2.3–§2.5 为准：资金写客户端超时 35 秒；传输失败同 key 自动重试 2 次（2 秒、5 秒，仅前台）后才转待核对；`IDEMPOTENCY_IN_PROGRESS` 累计 30 秒转待核对；`IDEMPOTENCY_KEY_CONFLICT` 回到确认框用新 key 重新确认。30 §3.4 的 40 秒超时与 45 秒等待、30 §5.4“同 key 自动重试一次”、60 §10.2 的 45 秒、60 §10.4“最多 3 次”、60 §19.4 的 40 秒都按 00 改；各结果表里“超时 → 待核对”发生在 2 次自动重试之后。30 §3.4“距发起不到 40 秒不下结论”是核对规则，保留 | 30 §0.2、§3.4、§5.4，60 §10.2、§10.4、§19.4 |
| R05 | Idempotency-Key 的生成时机 | 00 §2.5.2：在用户最后一次确认时生成（有确认框时是确认框的确认，没有确认框的表单是点“创建 / 保存 / 添加”的那一刻），重试沿用，请求体变了就换新 key。“sheet 打开时生成”“请求体冻结时生成”的写法按此执行。60 §19 的兑换码 `code` 仍在 sheet 打开时生成，与 key 无关 | 30 §0.2、§7.4，50 §3.4，60 §14.4、§17.4 |
| R06 | 不带 key 的写是否自动重试 | 00 §2.4：不自动重试，读回核对。唯一例外：50 §0.8 成员批量写入（服务端对重复请求返回 `unchanged`，50 §0.4.1）可自动同体重试 1 次 | 50 §0.8 |
| R07 | 读请求超时 | 以 00 §2.3 为准；40 §0.6 的超时数值作废（是否放宽见 U54） | 40 §0.6 |
| R08 | ETag 处理 | 00 §4.2 + 10 §0.2 末段：`ConditionalCache` 在 `APIClient` 层透明处理 `If-None-Match` / 304，各方法直接返回模型；20 的 `AccountListPage.etag` 与“每页记 ETag”、30 的“返回同时带 ETag”、50 的 `groupList(etag:)` → `.notModified` 不再单独实现。注意：账号详情 `GET /api/v1/admin/accounts/:id` 的 `ETag`（`"cv-N"`）是 PATCH 的 `If-Match` 版本号，不进 `ConditionalCache`，由 `account(id:)` 返回给调用方（20 §2.2） | 20 §1.2、§1.7，30 §1.7，50 §1.7 |
| R09 | `include_counts` | 只在 `page=1` 的请求上带（00 §4.4）；20 §1.2 参数串里的 `include_counts=1` 只用于第 1 页 | 20 §1.2 |
| R10 | 数字与时间格式 | 全 App 只用 00 §6.1–§6.2 的 `DisplayFormat`；10 §0.4、40 §0.5 的格式表与“新增到 `DashboardPresentation`”作废；10 §4.3 的“850 ms”、§6.3 的“2,000 ms”按 00 写成不带空格（`850ms`、`2,000ms`） | 10 §0.4、§4.3、§6.3，40 §0.5 |
| R11 | 错误展示 | 不回显服务端 `message`（00 §3.4）：50 §3.5“表单底部红字 message”、50 §5.3“其他 reason 显示 message”改为按 reason 的固定文案，没有对应文案时用 00 §3.3 的 HTTP 状态兜底 | 50 §3.5、§5.3 |
| R12 | 账号结构化错误缺失时 | 以 20 §0.2 为准：原因写“上游返回异常”，不显示 `error_message`；00 §5 `accounts.structured_error` 一行的“`error_message` 首行截断 80 字”作废 | 00 §5 |
| R13 | Key 状态推导 | 以 30 §7.3 `AdminAPIKeyStatus` 为准；00 §5 `api_keys.effective_status` 一行的映射作废 | 00 §5 |
| R14 | 只读管理访问令牌 | 用户列表 / 详情的今日消费、Key 卡片今日消费、分组 API 密钥页今日消费，只读时按 00 §2.6.3 不发 `dashboard/users-usage`、`dashboard/api-keys-usage`，显示 `—`。只读标记：`SiteSession` 保存 `accessTokenScope`（60 §0.3），对外提供 `isReadOnlyToken`（00 §1.6、§9.5） | 30 §1.2、§2.2、§7.2，50 §6.2 |
| R15 | 推送设置 | 以 60 §7 为准：App 可添加 / 删除 Bark、ntfy、Webhook，可编辑站点 APNs 配置；00 §7.1“请站长在 Web 设置”与 §7.4“其他渠道 App 只读显示”作废，00 §7 其余协议规则不变 | 00 §7.1、§7.4 |
| R16 | Face ID 覆盖范围 | 60 §3.4 的覆盖清单是全 App 唯一来源，`BiometricGate` 按它实现；20 §0.4、30 §0.2 第 6 条与之一致 | 20 §0.4，30 §0.2 |
| R17 | 回执显示时长 | 10 §0.7-6：4.2 秒，新回执直接替换旧回执；60 §0.4 的“5 秒”作废 | 60 §0.4 |
| R18 | 登录降级横幅 | 00 §1.4 第 5 步的“本次登录无法自动续期，约 <expires_in 换算> 后需要重新登录”横幅放在概览顶部、6 格之上 | 10 §1.3.1 |
| R19 | 共用接口方法只定义一次 | 账号列表：`managedAccounts(page:query:)` + `AccountListQuery`（20 §1.7），日志筛选、分组添加账号、全局搜索都用它（40 §6.7、50 §4.7、60 §2.7）。用户列表：`users(query:)` + `UserListQuery`（30 §1.7，补 `pageSize`）。账号状态汇总：一个方法 `accountStatusSummary(platform:groupID:includeAccounts:)`（20 §10.1 的参数，10 §1.7、50 §1.7 共用）。告警事件：10 §6.7 的 `alertEvents(...)` 补 `groupID`、`platform` 参数，供 50 §2.2 告警横幅与 20 §1.2 组头使用（50 §2.7 的 `firingAlerts(groupID:)` 不另建）。错误计数：40 §6.7 的 `errorCount(filter:kind:)`（10 §3.7 的 `requestErrorCount` / `upstreamErrorCount` 不另建）。代理：60 §12.7 的 `Proxies.swift`（20 §3.7 的 `ProxyManagement.swift` 不建） | 10 §1.7、§3.7，20 §1.7、§3.7，50 §2.7、§4.7，60 §2.7 |
| R20 | 时区 | 除 U53（账号过期时间）外一律按 00 §6.3；各章自带的时区说明以 00 §6.3 为准 | 20 §0.6，40 §0.2，60 各节 |

### 二、未照做的审查建议

| 章 | 意见 | 未照做的部分与现行做法 |
|---|---|---|
| 00 | 时区例外清单加入“代理到期” | 未加：代理编辑只输入天数（30 天 / 90 天 / 自定义天数），列表按服务器时区的自然日计算，属于默认规则 |
| 00 | 资金写记录的存储模型给了两个方案 | 采用方案 (b)：只有资金写落盘，余额、兑换码批次、补偿各一个文件，共有字段统一；60 章残留的 `pendingWrites` / `PendingWrite` 写法按 R01 读 |
| 00 | `page_size` 上限与各章冲突 | 采用“放宽 00、各章不动”：00 §4.1 列出允许用到 500 / 1000 的名单，各章取值不改 |
| 10 | 新建应用骨架章节（00 新节或 `05-shell.md`） | 未做；本版以 10 §0.7 为准（U14） |
| 20 | 幂等与重试参数、时间基准不统一 | 只改了 20 章；00 / 30 / 50 / 60 的同类写法未改，按 R04–R06、R20 执行 |
| 40 | 把 40 原有的游标回退规则（最小 id − 1；空列表用上次 `since_id`）并入 00 §4.3 | 未并入；40 改为完全引用 00 §4.3（`created_at` 回退 30 秒，解析失败退 200 个 id，U04） |
| 60 | 发放补偿的 Idempotency-Key 在 sheet 打开时生成 | 未照做：按 00 §2.5.2 在确认那一刻生成；sheet 打开时生成的是兑换码 `code`（收据要显示），发送过之后改内容时 `code` 与 key 一起换新 |
| 60 | 设计稿与清单 S58 认为发放补偿不需要待核对记录 | 未照做：按 00 §0 第 4 条与 §2.5.5 冻结并落盘，App 被杀后也能核对 |
| 60 | 只读令牌识别移进 00 §1.6、推送规则改回 00 §7、20 / 30 引用 Face ID 覆盖清单、10 补“补偿结果待核对”行与登录降级横幅 | 这些跨章改动没有落到对应章节文件，见 R01、R02、R14、R15、R16、R18 |
| 30 | 10 / 50 / 60 中回显服务端 message 的位置；60 兑换码键盘的位数 | 前者未在那几章改，见 R11；后者不冲突（`KeypadInput` 按各章参数传入：用户键盘 7 位、兑换码面额 6 位） |
| 50 | 00 §5 `api_keys.effective_status` 一行的退路映射 | 00 未改，见 R13 |
| 10 | 00 §5 `accounts.structured_error` 一行；40 / 60 的 ETag 说明与 20 / 30 / 50 各自的返回类型；40 §0.6 与 60 的超时数值 | 都未在对应章改，见 R12、R08、R04、R07 |
