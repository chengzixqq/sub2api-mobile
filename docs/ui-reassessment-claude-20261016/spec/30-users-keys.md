# 30 · 用户与 API Key（用户 Tab）

本章覆盖底部「用户」Tab 下的全部页面：用户列表（含快捷充值头像条）、用户详情、充值 / 退款键盘与待核对、充值与调整记录、新建用户、编辑用户（基础 · 权限与并发 · Key 与限额）。读者是照着实现 SwiftUI 页面的工程师。

- **设计依据**：`DECISIONS.md` 第 2 轮 Q10–Q12、第 3 轮 Q13–Q14 与文字题、整合后文字题、设计稿评审意见；设计稿 `html-preview/layouts/main/v-users.jsx`（列表、详情、记录页）、`v-user-edit.jsx`（新建 / 编辑，已定 `tabs` + `ueKeys: 'cards'`）、`00-core.jsx`（`KeypadSheet`、`UserDetail`、`userMenu`）、`shared/core.jsx`（`submitBalanceChange`、`reconcileUser`）。
- **后端基线**：sub2 `main` `70116315d`（2026-10-22）。本章每个接口路径、字段名、reason 都对过源码：路由 `backend/internal/server/routes/admin.go`（`registerUserManagementRoutes`、`registerAdminAPIKeyRoutes`、`registerUserAdjustmentRoutes`），handler `handler/admin/user_handler.go`、`apikey_handler.go`、`user_adjustment_handler.go`、`quick_topup_handler.go`、`user_platform_quota_item_handler.go`、`user_attribute_handler.go`，DTO `handler/dto/types.go`。
- **口径优先级**：后端适配清单“实现进度”表的备注 > 清单条目原文 > 设计稿注释。设计稿里写“需后端新增”的 Key 新建 / 停用 / 删除，E01 已上线，本章按真实接口写；设计稿“初始余额不会出现在充值与调整记录里”的文案，E10 上线后作废。
- 下文接口路径都写全（`/api/v1/...`）；“回执”指带“撤销”的底部 Toast；“确认框”指 `.alert` / `.confirmationDialog`；“状态胶囊”指全局统一的左侧悬浮胶囊（评审意见第 3 条，相邻粘连）。

---

## 0. 本章共用前提

### 0.1 身份与能力探测

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

### 0.2 写操作通用规则（本章特有的部分，其余见通用约定）

1. **Idempotency-Key**：资金写（余额调整）强制带；新建用户、编辑用户、启用 / 禁用用户、新建 Key、替换分组在有 `admin.idempotent_writes`（替换分组与新建 Key 不需要能力，接口本身接受可选 key）时都带。key 用 UUID（小写），**在请求体冻结时生成**，同一请求体的重试沿用；请求体变了必须换新 key（否则 409 `IDEMPOTENCY_KEY_CONFLICT`）。
2. **响应头**要能读到（`APIClient` 现在只返回 data，需加一个带响应头的变体，见 §10）：`X-Idempotency-Replayed: true`（重放，回执改成“此前已执行，未重复操作”）、`X-Idempotency-Expires-At`、`X-Idempotency-Degraded: result-committed`（结果可信，但之后同 key 重发可能 409，按读回核对）、`X-Admin-Adjustment-Action-ID`、`Retry-After`。
3. **409 的处理按 reason 分**（`docs/API_ERROR_CODES.md`）：`IDEMPOTENCY_IN_PROGRESS` / `IDEMPOTENCY_RETRY_BACKOFF` → 按 `Retry-After` 秒后同 key 原样重试；`IDEMPOTENCY_KEY_CONFLICT` → 不重试，提示“请求已变化，请重新提交”；`IDEMPOTENCY_STORE_UNAVAILABLE`（503）→ 没执行，保留原请求稍后同 key 重试，不换 key。
4. **业务错误没有 reason 的几处**（后端用普通 `errors.New`，经 `ErrorFrom` 变成 500 `internal error`、reason 为空）：不能禁用管理员、不能删除管理员、不能降级最后一个管理员、余额扣成负数、专属倍率 ≤ 0。App 一律**事前拦截**（见各节），收到 500 且无 reason 时显示通用“服务器未能完成请求”，资金写按“结果待核对”处理。
5. **只读管理访问令牌**：写接口返回 403 `ACCESS_TOKEN_READ_ONLY` 时显示“当前登录的是只读令牌，不能修改”，不重试。
6. **Face ID**：设置里“高风险操作需要 Face ID”打开时（默认关，门槛默认 $100，见设置章），本章覆盖：删除用户、删除 Key、超过门槛的充值 / 退款、超过门槛的新建用户初始余额、发放余额补偿超过门槛。揭示完整 Key **总是**先做一次本机身份验证（`LAContext` `.deviceOwnerAuthentication`），不受开关影响。Face ID 打开时删除确认框的按钮写“用 Face ID 删除”，关闭时要输入完整名称才能点。

### 0.3 显示名与文案

- **用户显示名**：`username` 去空白后非空用它，否则用 `email` 的 `@` 之前部分；头像字母取显示名第一个字符（字母转大写）。
- **用户状态词**：`active` →「启用」，`disabled` →「禁用」（句中可写“已禁用”）。用户不写“正常 / 停用”。
- **角色词**：`user` →「用户」，`vendor` →「供应商」，`admin` →「管理员」。（现有 App 的“普通用户 / 代运营”要改。）
- **Key 状态词**：活跃 / 已停用 / 额度耗尽 / 已过期（见 §7.3）。
- 金额显示沿用通用约定（Decimal，两位，`$1,020.00`，负数 `−$3.00`）；缺失值 `—`，0 显示 `$0.00`。

### 0.4 二次验证（step-up）

需要 step-up 的只有两处：把用户设为 / 新建为管理员（`EnforceStepUp`，`user_handler.go:303-307, 398-409`）、揭示完整 Key（`POST /api/v1/admin/api-keys/:id/reveal` 挂 `stepUpAuth`）。

- `security.step_up_enabled == false`：服务端直接放行（含 Admin Key），App 不弹验证码。
- 开启且 `step_up_granted == true`：直接发请求。
- 开启且未授予：弹设计稿的 6 位验证码 sheet（填满自动提交，`textContentType(.oneTimeCode)`），`POST /api/v1/user/totp/step-up {"code":"123456"}` → `verified` 为 true 后继续原流程（设为管理员还要再确认一次，见 §6.4）。
- 开启且 `step_up_available == false`：Admin Key / 管理访问令牌登录 →“Admin Key 登录不能做二次验证，请改用账号登录后再操作”；账号没开 TOTP →“需要先在 Web 端开启二次验证”（设计稿 `ueNoTotp` 状态），按钮“知道了”。
- 服务端仍返回 403 `STEP_UP_REQUIRED`（授予已过期）：重新弹验证码，验证后用**同一个** Idempotency-Key 重发（step-up 拒绝发生在幂等封装之前，不占用 key）。

### 0.5 待核对余额（本地状态）

“待核对”只存在本机：余额写请求发出后没拿到确定结果时，原请求保留在 `AppModel.pendingBalances`（文件保护存储，已有）。详情横幅、列表标记、头像条排序、概览“待处理”都读这一份。数据结构与核对流程见 §3。

### 0.6 回执与撤销的退路（E04 不可用时）

- Key 换分组撤销：先 `PUT /api/v1/admin/api-keys/:id {"group_id": <原分组或 0>}`；当时新授予过专属分组的，再 `GET /api/v1/admin/users/:id` 取最新 `allowed_groups`，去掉该分组后 `PUT /api/v1/admin/users/:id {"allowed_groups": [...]}`；第二步失败提示“Key 已还原，但分组授权没收回，请在权限与并发里手动移除”。
- 替换分组撤销：调反向 `replace-group`；替换前用户已有新分组、或新分组下原本就有 Key 时，回执不给“撤销”。

---

## 1. 用户列表（Tab 首页，含快捷充值头像条）

设计稿：`v-users.jsx` 的 `VuUsersQuick`（`users: 'quick'` + `usersRows: 'cols'`）。DECISIONS 第 2 轮 Q11、Q12，默认处理“最新在前”。

### 1.1 入口与导航

- 底部 Tab「用户」的根页面；`NavigationStack` 根。
- 导航栏：标题“用户”（居中，不用大标题；与账号页一致，大标题只给概览 / 监控 / 搜索），副标题“<站点名> · N 位”；右上 `+` → 新建用户（§5）。
- 搜索框（`.searchable`，占位“邮箱、用户名或备注”）：点了才弹键盘。
- 点头像条里的头像：没有待核对 → 打开充值键盘 sheet（§3，mode = 充值）；有待核对 → push 用户详情（去核对）。
- 点列表行 → push 用户详情（§2）。
- vendor 身份：整页空态“供应商账号不能管理用户”，不发请求。

### 1.2 数据来源

| 用途 | 接口 | 关键参数 | 说明 |
|---|---|---|---|
| 用户列表 | `GET /api/v1/admin/users` | `page`、`page_size=20`、`sort_by=created_at`、`sort_order=desc`、`include_subscriptions=false`、`search`（去空白，最多 100 字符，服务端会截断） | 分页信封 `{items,total,page,page_size,pages}`；每项是 `AdminUser` + `current_concurrency`。搜索命中邮箱、用户名、备注与 Key 片段（`repository/user_repo.go:553-559`）。有 `lists.etag` 时第 1 页带 `If-None-Match`，304 保留现有数据 |
| 头像条 | `GET /api/v1/admin/users/quick-topup` | `recent_limit=8`、`low_limit=8`、`recent_days=30`（默认值即这三项，可不传） | `{recent:[...], low_balance:[...], low_balance_enabled}`。需 `users.quick_topup` |
| 每行今日消费 | `POST /api/v1/admin/dashboard/users-usage` | `{"user_ids":[...]}`，每批 ≤ 200（服务端上限 1000，E12） | `{stats:{"<user_id>":{user_id,today_actual_cost,total_actual_cost,by_platform}}}`；服务端 30 秒缓存，缓存键带日期 |
| 全局余额低阈值 | `GET /api/v1/settings/public` | — | `balance_low_notify_enabled`、`balance_low_notify_threshold`；会话内缓存，设置章已在拉 |

列表项用到的 `AdminUser` 字段：`id`、`email`、`username`、`status`、`role`、`balance`、`total_recharged`、`balance_notify_threshold`（可空）、`balance_notify_threshold_type`（`fixed` / `percentage`）、`created_at`。

### 1.3 字段 → 显示映射

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

### 1.4 交互与写操作

- 本页没有直接写操作。充值走 §3 的键盘 sheet；sheet 成功后刷新头像条（重新请求 `quick-topup`）并用响应里的 `balance` 原地更新该用户所在行。
- 搜索：输入防抖 300 ms 后从第 1 页重新请求；搜索非空时隐藏头像条；清空恢复。
- 翻页：滚到最后一行出现时请求下一页（`page < pages`），新页按 `id` 去重追加，并为新页的 id 补一次 `users-usage`。
- 下拉刷新：重新请求第 1 页（带 ETag）、头像条、已加载行的今日消费。

### 1.5 状态

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

### 1.6 刷新策略

- 进入 Tab、App 回到前台、下拉刷新：刷新第 1 页 + 头像条 + 已加载行的今日消费。
- Tab 可见且 App 在前台时每 60 秒做一次同样的刷新（DECISIONS 第 2 轮“前台自动刷新约 60 秒”）；第 2 页以后不自动刷新。
- 第 1 页带 `If-None-Match`（`lists.etag`），304 时只刷新今日消费；注意用户内嵌的状态在服务器时钟变化时也会让 ETag 变（E06 部署注意），304 命中率不保证。
- 不适用 `since_id`。
- 从详情 / 编辑页返回时：用详情页最后一次拿到的 `AdminUser` 原地替换该行（不整页重拉）。

### 1.7 对现有代码的改动点

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

## 2. 用户详情

设计稿：`v-users.jsx` 的 `VuHeroDetail`（`userDetail: 'hero'`），⋯ 菜单是 `00-core.jsx` 的 `userMenu`。DECISIONS 第 2 轮 Q10、第 3 轮文字题（“充值与调整记录”改名、发放补偿、停用用户可充值）。

### 2.1 入口与导航

- 进入：用户列表行、头像条（待核对时）、概览“待处理 · 充值结果待核对”、搜索结果、使用记录 / 请求详情的“用户”行。
- 导航栏：标题 = 显示名，副标题 = 邮箱；返回；右上 ⋯（见 2.4）。
- 页内去处：API Key 摘要行 → 编辑用户并定位到「Key 与限额」段（§7）；“使用记录 ›” → 使用记录页（`{scope: usage, user: id}`，见使用记录章）；“全部 N 条 ›” → 充值与调整记录（§4）；充值 / 退款 → 键盘 sheet（§3）；⋯ → 编辑用户（§6）。

### 2.2 数据来源

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

### 2.3 字段 → 显示映射

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

### 2.4 交互与写操作

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

### 2.5 状态

| 状态 | 显示 | 动作 |
|---|---|---|
| 首次加载 | 头部骨架；各分区各自加载 | — |
| 用户资料失败 | 整页错误“加载用户失败” | “重试” |
| 404 `USER_NOT_FOUND` | “这个用户不存在或已删除” | 返回列表并移除该行 |
| 分区失败（今日 / 本月 / Key / 记录） | 只在该分区显示“加载失败 · 重试”，其他分区照常 | 分区内“重试” |
| 启用 / 禁用 500 且无 reason | 回执“操作失败：服务器未能完成请求”（多为对管理员操作） | 刷新用户资料 |
| 写操作 403 `ACCESS_TOKEN_READ_ONLY` | “当前登录的是只读令牌，不能修改” | — |
| 写操作 409 `IDEMPOTENCY_IN_PROGRESS` / `RETRY_BACKOFF` | 静默按 `Retry-After` 同 key 重试，最多 30 秒；仍失败回执“结果未确认，已刷新为服务器当前状态”并 GET 读回 | — |

### 2.6 刷新策略

- 进入时加载全部分区；下拉刷新同。
- 页面可见且前台时每 60 秒刷新“用户资料 + 今日消费”（余额、状态会被计费与其他管理员改动）；Key、记录、本月不轮询。
- 写操作后：启用 / 禁用用响应替换资料；充值 / 退款用响应的 `balance` 并重拉记录前 5 条；从编辑页返回时重拉资料、Key、记录。

### 2.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: UserDetailView` 重写为设计稿 hero 布局；“管理操作”分区（编辑 / 禁用 / 调整余额按钮）删掉，改成 ⋯ 菜单 + 余额头部按钮。
- `reload()` 改为并发加载各分区、分区各自的错误状态；`userUsage(id:)` 改用 `total_actual_cost`（现在读的 `total_cost` 是标准计费，不是实际扣费）并按服务器时区算月份（`APIClient.monthRange()` 现在用手机日历）。
- `changeStatus()`：确认框去掉（可逆操作直接执行 + 回执撤销），加 Idempotency-Key。
- `Sources/Sub2Core/APIClient.swift`：新增 `deleteUser(id:)`、`setUserStatus` 带可选幂等 key；`userKeys(id:page:)` 加 `key_view=masked`、排序与 `page_size=100`。
- 建议拆出 `NativeApp/Features/Users/UserDetailView.swift`。

---

## 3. 充值 / 退款键盘与待核对

设计稿：`00-core.jsx` 的 `KeypadSheet`（第 1 轮 Q“充值 / 退款 = B 大数字键盘”），`shared/core.jsx` 的 `submitBalanceChange`、`reconcileUser`；第 3 轮文字题“键盘上方加一行可选备注”“停用用户可以充值 / 退款”。后端：G01、G02，`POST /api/v1/admin/users/:id/balance`（`executeAdminMoneyWriteJSON`：强制 key、断开后仍执行完、可接管卡住的执行、账本按 action_id 去重）。

### 3.1 入口与导航

- 用户详情的“充值 / 退款”、编辑用户身份条的“充值 / 退款”胶囊、列表头像条的头像。
- 以 sheet 打开（`presentationDetents([.large])`），顶部分段“充值 | 退款”可切换；关闭回到原页面。

### 3.2 数据来源

| 用途 | 接口 | 关键参数 |
|---|---|---|
| 余额调整 | `POST /api/v1/admin/users/:id/balance` | 头：`Idempotency-Key: <op.id>`、`X-Request-ID: <op.id>`；body `{"balance":"50","operation":"add","notes":"补偿 10/16 故障"}`（`balance` 是十进制字符串，最多 8 位小数，≤ 999999999999.99999999；`operation` ∈ `add` / `subtract` / `set`） |
| 核对 | `GET /api/v1/admin/user-adjustments` | 第一次：`user_id=<id>`、`kind=balance`，再加 `action_id=<uuid>`（拿到过响应头时）或 `request_id=<op.id>`；`page_size=20`。第二次（第一次没有匹配行时）：`keyword=<邮箱>`、`kind=balance`、`start_time`、`end_time`、`page_size=200`。`request_id` / `action_id` / `user_id` 三个筛选是 G02 才加的，且没有 capability，旧服务端会静默忽略，所以**两次都只按本地复核的结果判定**，不看 `total`（见 3.4“核对”） |

成功响应 data 是 `AdminUser`；响应头 `X-Admin-Adjustment-Action-ID`（带 key 时总有）、`X-Idempotency-Expires-At`、重放时 `X-Idempotency-Replayed: true`、回显的 `X-Request-ID`。

核对接口每项字段：`id`、`action_id`、`kind`、`operation`、`requested_value`、`delta`、`before_value`、`after_value`（金额都是 8 位小数字符串）、`user_id`、`user_email`、`operator_user_id`、`operator_email`、`notes`、`request_id`、`source`、`created_at`。

### 3.3 字段 → 显示映射

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

### 3.4 交互与写操作

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

### 3.5 状态

| 状态 | 显示 |
|---|---|
| 发送中 | 提交按钮变 `ProgressView`“正在提交…”，sheet 不能下滑关闭（`interactiveDismissDisabled`） |
| 等待服务器（409 进行中） | “正在等待服务器结果…”+ 已等待秒数 |
| 待核对 | sheet 关闭；详情横幅、列表 caution 胶囊与 docCheck 标记、头像条“去核对”、概览“待处理”一条 |
| 核对中 | 横幅按钮变进度 |

### 3.6 刷新策略

不轮询。App 回到前台时对本站点的待核对逐条自动核对一次（只查不执行，即 3.4“核对”第 1、2 步的两次查询）：只有按匹配规则精确找到（action_id / request_id）才自动 `resolve` 并回执；没找到、只有候选、或距发起不到 40 秒，都保留横幅等管理员决定。

### 3.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: BalanceView` 整个替换为新文件 `NativeApp/Features/Users/BalanceKeypadSheet.swift`（设计稿键盘；不再暴露“设置为”操作，只在“全部余额”时内部用 `set 0`）。键盘输入规则提取为纯函数 `KeypadInput.apply(_ key:to:maxDigits:maxFractionDigits:)`，本章用 `maxDigits = 7`、`maxFractionDigits = 2`（数字总数含小数部分），其他键盘（如兑换码面额）按各自章节传参，配单测。
- `Sources/Sub2Core/Models.swift: PendingBalanceOperation`：新增 `requestID`（= `id` 小写字符串）、`actorUserID`、`createdAt`、`userDisplayName`、`userEmail`、`actionID?`、`idempotencyExpiresAt?`；`init(from:)` 对新字段用 `decodeIfPresent`，兼容已落盘的旧记录（旧记录 `actorUserID` 为空时视为当前管理员可重试，并在核对框里写明“无法确认发起人”；旧记录的核对走 3.4 末尾的旧记录规则）。
- `Sources/Sub2Core/APIClient.swift: updateBalance(_:)`：加 `X-Request-ID` 头，返回 `(AdminUser, ResponseHeaders)`；失败时也要能取到响应头里的 `X-Admin-Adjustment-Action-ID`（放进 `APIError`，见 3.4 第 4 步）；新增 `userAdjustments(query:)`。
- `NativeApp/Features/UsersView.swift: BalanceView.definitelyRejected`（`private` 函数，第 539 行；`AppModel.swift` 里没有这段逻辑）：随 `BalanceView` 一起删掉，判定迁到 `BalanceReconciliation.swift` 的纯函数 `balanceWriteOutcome(for:)`，按 3.4 的结果表重写。现状是：本地 `.validation` 错误、全部 401 / 403、以及 reason 为 `VALIDATION_ERROR` / `INVALID_REQUEST` / `INVALID_AMOUNT` / `BAD_REQUEST` 的 400 当作确定拒绝；服务端真实的 `INVALID_BALANCE`、`IDEMPOTENCY_KEY_*`、无 reason 的 400 都不在其中，会被误记为待核对。
- `NativeApp/Session/AppModel.swift`：新增 `reconcile(_ op:) async -> ReconcileOutcome`（`.executed(UserAdjustment)` / `.notFound` / `.stillRunning` / `.candidates([UserAdjustment])` / `.failed(Error)`）与“回到前台自动核对”。
- 新增 `Sources/Sub2Core/BalanceReconciliation.swift`：账本匹配的纯函数（action_id / request_id 精确匹配、候选匹配、旧记录规则）与 `balanceWriteOutcome(for:)`，配单测。单测至少覆盖：服务端忽略筛选参数、返回 `total ≥ 1` 的无关行 → 不算已入账，转第二次查询；`request_id` 相同但 `user_id` 不同 → 不算；`action_id` 大小写不同 → 算；`requestIDUnreliable` 时同金额同备注的行只作候选、不自动 `resolve`；两条候选 → 多条分支；距发起不到 40 秒 → `.stillRunning`。

---

## 4. 充值与调整记录（全部）

设计稿：`v-users.jsx` 的 `VuLedgerScreen`（`screen:userLedger`）与详情页 `VuLedger`。DECISIONS 第 3 轮文字题“余额流水 → 充值与调整记录”，默认处理“兑换条目显示兑换码前 8 位”。后端：E10（进度表：`adjustment_id` / `before_value` / `after_value` / `operator_email`，`total_recharged_breakdown` 含 `grant`）。

### 4.1 入口与导航

- 用户详情“充值与调整记录”分区底部“全部 N 条 ›”。
- 导航栏：标题“充值与调整记录”，副标题 = 用户显示名；返回。

### 4.2 数据来源

`GET /api/v1/admin/users/:id/balance-history`，参数 `page`、`page_size=20`、可选 `type`（本页不用筛选）。

响应 `{items, total, page, page_size, pages, total_recharged, total_recharged_breakdown:{redeem, admin, grant, affiliate, promo}}`。每项（`AdminBalanceHistoryItem`）：`id`、`code`、`type`、`value`、`status`、`used_by`、`used_at`、`created_at`、`group_id`、`validity_days`、`group`（含 `name`）、`notes`（字符串）、`batch_id?`、`created_by?`、`adjustment_id`、`before_value`、`after_value`、`operator_email`（后四个只有 `admin_balance` / `admin_concurrency` 行有值，其余为 null；迁移来的旧行 before / after 也为 null）。

不需要 capability；`total_recharged_breakdown` 与前后余额字段要 `users.balance_ledger`，没有时不显示拆分与前后余额。

### 4.3 字段 → 显示映射

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

### 4.4 交互与写操作

只读。行不可点。长按记录行可“复制兑换码”（只对显示了兑换码的行；复制完整 `code`）。

### 4.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 列表骨架 |
| 空 | “暂无记录” |
| 第 1 页失败 | 整页错误 + “重试” |
| 翻页失败 | 列表底部“加载更多失败 · 重试” |
| 404 `USER_NOT_FOUND` | “这个用户不存在或已删除”，返回 |

### 4.6 刷新策略

进入加载第 1 页；滚到底加载下一页（按 `id` 去重）；下拉刷新重拉第 1 页并清掉已加载的后续页。不轮询，无 ETag。

### 4.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/UserLedger.swift`：`BalanceHistoryPage`、`BalanceHistoryItem`、`RechargeBreakdown` 解码（金额字段 `value` 为 JSON 数字、`before_value` / `after_value` 为字符串，都用 `KeyedDecodingContainer.decimal` / `optionalDecimal`），`title(for:)`、`valueText(for:)`、`codePrefix(for:)` 纯函数配单测。
- 新增 `NativeApp/Features/Users/UserLedgerView.swift`（`List` + `.task` 分页）；详情页的记录分区复用同一个行视图。
- `APIClient`：新增 `balanceHistory(userID:page:pageSize:)`。

---

## 5. 新建用户

设计稿：`v-user-edit.jsx` 的 `UeTabsScreen`（`screen:userNew: 'tabs'`），DECISIONS 第 3 轮 Q13（更正：分段；新建时只有前两段）。后端：`POST /api/v1/admin/users`（G06 可选幂等、30 秒脱离客户端执行；E10 初始余额入账）。

### 5.1 入口与导航

- 用户列表右上 `+`；列表空态的“新建用户”。
- push 全屏页，隐藏 Tab 栏（`.toolbar(.hidden, for: .tabBar)`）。导航栏：返回（有内容时先确认“放弃新建用户？已填写的内容不会保留。”按钮“放弃”/“继续编辑”）、标题“新建用户”、副标题站点名。
- 顶部固定身份条（新建态）：字母头像（未填时空白）、显示名（用户名 > 邮箱前缀 > “新用户”）、尾部“<角色> · 创建后启用”。
- 分段「基础 | 权限与并发」吸顶；分段下说明行“两段填完后点底部“创建用户””（滚动或输入框获得焦点时收起，见设计稿 `useUeCompact`：滚动 > 24pt 收起、< 2pt 展开，失焦 300 ms 后再展开）。
- 底部操作条（`.safeAreaInset(edge: .bottom)`）：基础段“下一步：权限与并发 →”；权限段“上一步”+“创建用户”。
- 创建成功：从导航栈移除新建页并 push 新用户详情（§2）。

### 5.2 数据来源

| 用途 | 接口 | 说明 |
|---|---|---|
| 分组目录 | `GET /api/v1/admin/groups/all?include_inactive=true` | 会话内缓存（分组章同一份）；本页只用 `status == "active"` 且 `subscription_type == "standard"` 的分组：`is_exclusive == true` 为专属分组，否则为公开分组；按 `sort_order` 排序 |
| 自定义属性定义 | `GET /api/v1/admin/user-attributes?enabled=true` | 数组：`id`、`key`、`name`、`type`（text / textarea / number / email / url / date / select / multi_select）、`options[{value,label}]`、`required`、`placeholder`、`display_order` |
| 创建 | `POST /api/v1/admin/users` | 见 5.4 |
| 写自定义属性 | `PUT /api/v1/admin/users/:id/attributes` | 创建成功后单独发，见 5.4 |

### 5.3 字段 → 显示映射

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

### 5.4 交互与写操作

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

### 5.5 状态

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

### 5.6 刷新策略

进入时加载分组目录与属性定义（有会话缓存就不重拉）。不轮询。创建成功后用户列表下次出现时刷新第 1 页。

### 5.7 对现有代码的改动点

- `NativeApp/Features/UsersView.swift: UserEditorView`（sheet 表单）废弃，改为新文件 `NativeApp/Features/Users/UserEditView.swift`（新建与编辑共用一个视图模型 `UserEditorModel`，`mode: .create | .edit(userID)`）。
- `Sources/Sub2Core/UserManagement.swift: UserCreateRequest`：新增 `allowedGroups: [Int]`、`restrictPublicGroups: Bool`；`balance` 为 nil 时不编码（现在已是 `Decimal?`，确认 `encodeIfPresent`）；`AdminUserRole.title` 改为“用户 / 供应商 / 管理员”。
- `APIClient.createUser(_:identity:)`：带可选 Idempotency-Key，返回响应头；新增 `userAttributeDefinitions()`、`updateUserAttributes(userID:values:)`。
- 去掉现有“核对并确认 → 确认发送”的两步确认（设计稿只在初始余额 / 管理员时确认）。

---

## 6. 编辑用户 · 基础与权限与并发

设计稿：`v-user-edit.jsx` 的 `UeTabsScreen`（`screen:userEdit: 'tabs'`）。前两段要“保存”，第三段立即生效（§7、§8）。后端：`PUT /api/v1/admin/users/:id`（G06 可选幂等、30 秒脱离执行；Q13 带 balance 返回 400），`GET /api/v1/admin/users/:id/rpm-status`（E08）。

### 6.1 入口与导航

- 用户详情 ⋯ →“编辑用户”（进入「基础」段）；用户详情 Key 摘要行（进入「Key 与限额」段并滚到 Key 区）。
- push 全屏，隐藏 Tab 栏。导航栏：返回（见 6.4“离开”）、标题“编辑用户”、副标题站点名、右上 ⋯（“复制邮箱”；“删除用户…”红字最后，管理员置灰并注“管理员不能删除”）与“保存”（有改动时实心可点，否则灰）。
- 固定身份条：显示名、邮箱、徽章（角色、启用 / 禁用、本人“你”、本机待核对“待核对”）、右侧“可用余额 $12.40”与“充值 / 退款”胶囊（44pt 点按区，打开 §3 键盘，待核对时先问）。滚动 > 24pt 或输入框获得焦点时收成一行（显示名 + 余额 + 胶囊）。
- 分段「基础 | 权限与并发 | Key 与限额（N）」吸顶，N = Key 总数。分段下说明行：无改动“基础、权限与并发改完点右上“保存”，两段一起提交”；有改动 / 错误时改为“基础 已改 2 项 · 权限与并发 1 项要修改”（收起态不显示，标记仍在分段上：改动是圆点，错误是红色“!”）。
- 切换分段时滚动回顶部。

### 6.2 数据来源

进入时并发：

| 用途 | 接口 | 说明 |
|---|---|---|
| 用户资料（表单基线） | `GET /api/v1/admin/users/:id` | `email`、`username`、`notes`、`role`、`status`、`concurrency`、`rpm_limit`、`allowed_groups`、`group_rates`（`{"<group_id>": rate}`）、`restrict_public_groups`、`last_active_at` |
| 分组目录 | `GET /api/v1/admin/groups/all?include_inactive=true` | 同 §5.2 |
| 自定义属性 | `GET /api/v1/admin/user-attributes?enabled=true` + `GET /api/v1/admin/users/:id/attributes` | 值数组每项 `attribute_id`、`value` |
| RPM 状态 | `GET /api/v1/admin/users/:id/rpm-status` | `{user_rpm_used, user_rpm_limit, user_rpm_tracked, per_group:[{group_id, group_name, used, limit, source, tracked}]}`；`per_group` 可能为 null（用户没有绑定分组的 Key），按空数组处理 |
| Key（算“绑定 N 个 Key”） | 同 §7.2 | 与第三段共用一份 |
| 站点管理员数（降级预检） | `GET /api/v1/admin/users?role=admin&page_size=1&include_subscriptions=false` | 只读 `total`；在角色从管理员改成别的时才请求 |

### 6.3 字段 → 显示映射

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

### 6.4 交互与写操作

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

### 6.5 状态

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

### 6.6 刷新策略

- 进入时加载一次，表单基线固定，不随轮询覆盖草稿。
- RPM 状态块出现在屏幕上时每 15 秒刷新一次，离开屏幕停止；下拉刷新时也刷新。
- 保存成功后 pop，不在本页重载。
- 立即生效的操作（§7、§8）成功后会改变 `allowed_groups`（换分组自动授予、替换分组）：同步更新表单**基线**与草稿里对应的分组（设计稿 `both()`），已有的其他草稿改动保留。

### 6.7 对现有代码的改动点

- 新文件 `NativeApp/Features/Users/UserEditView.swift`（分段壳、身份条、吸顶分段、收起逻辑）、`UserEditBasicSection.swift`、`UserEditAccessSection.swift`、`UserGroupSheets.swift`、`UserRPMStatusView.swift`；视图模型 `UserEditorModel`（`@Observable`：`original`、`draft`、`changedFields`、`errors`、`applied`）。
- `Sources/Sub2Core/UserManagement.swift: UserUpdateRequest`：新增 `status`、`allowedGroups`、`restrictPublicGroups`、`groupRates: [Int: Decimal?]`（编码时 nil 值要写成 JSON `null`，需自定义 `encode(to:)`，不能用默认的 `encodeIfPresent`）；`validate()` 的“至少改一个字段”条件同步扩充；倍率校验 > 0、≤ 3 位小数。
- `PendingUserUpdateOperation.supportsSafeRetry`：有 `admin.idempotent_writes` 时恒为 true（现在只在带 concurrency 时为 true）。
- `APIClient`：新增 `userRPMStatus(id:)`、`userAttributes(userID:)`、`adminCount()`。
- 删除旧 `UserEditorView` 与 `PreparedUserMutation`。

---

## 7. 编辑用户 · Key 与限额 · API Key 卡片

设计稿：`v-user-edit.jsx` 的 `UeKeySec`（`ueKeys: 'cards'`）、`UeKeyCard`、`UeKeyGroupSheet`；DECISIONS 第 3 轮 Q14（可展开卡片，第一张默认展开）与文字题（新建 / 停用 / 删除：后端加好后删除放 ⋯ 最后并确认，停用回执可撤销）。后端：E01、E03、E04、E06、E11、E12。

这一段顶部固定说明条：“**这一段立即生效**，不用保存，也不随“放弃更改”撤回”。

### 7.1 入口与导航

- 编辑用户第三段「Key 与限额」；从用户详情 Key 摘要进入时直接落在这一段。
- 卡片内：换分组 sheet、Key ⋯ 菜单（编辑 Key…、停用 / 启用、显示完整 Key…、删除 Key…）；列表末尾“＋ 新建 Key”→ 新建 Key sheet → 创建结果 sheet。

### 7.2 数据来源

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

### 7.3 字段 → 显示映射

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

### 7.4 交互与写操作

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

### 7.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 卡片骨架 2 张 |
| Key 列表失败 | 分区内“Key 加载失败 · 重试”；平台限额、替换分组照常 |
| 今日消费失败 | 不限额卡片的用量行“今日 —” |
| 写操作进行中 | 该卡片的操作按钮变进度，其他卡片可操作 |
| 写失败 | 回执按上文；卡片恢复原状（无乐观更新——换分组等都等服务端返回再改界面） |
| 404 `API_KEY_NOT_FOUND`（任一操作） | 移除卡片，回执“这个 Key 已被删除” |

### 7.6 刷新策略

切到「Key 与限额」段时刷新 Key 列表与今日消费（同一次进入只刷一次）；每个写操作成功后只刷新该卡片；下拉刷新全部。不轮询（Key 的并发、用量变化不需要实时）。

### 7.7 对现有代码的改动点

- `Sources/Sub2Core/Models.swift: UserAPIKey` 扩充为完整 `AdminAPIKey`（上面全部字段；金额用 Decimal；时间用 `Date?`；`key` 解码后若非空立即置空，只保留 `keyMasked`——现在 `UsersView.swift:159` 拿完整 `key` 本地截后 4 位，改用 `key_masked`）。
- 新增 `Sources/Sub2Core/UserKeys.swift`：`AdminAPIKeyStatus` 推导（`effective_status` 优先，缺失时本地推导；`simple` 模式规则）、`AdminAPIKeyCreateRequest`、`AdminAPIKeyUpdateRequest`（字段全可选；`expiresAt` 区分“不改 / 清除 / 设置”三态）、`AdminAPIKeyWriteResult`（`api_key`、`auto_granted_group_access`、`granted_group_id`、`granted_group_name`、`revoked_group_access`、`revoked_group_id`、`previous`），配单测。
- `APIClient`：新增 `apiKey(id:)`、`createUserAPIKey(userID:request:idempotencyKey:)`、`updateAPIKey(id:request:)`、`deleteAPIKey(id:)`、`revealAPIKey(id:)`、`apiKeysTodayUsage(ids:)`、`userSubscriptions(userID:)`。
- 新视图：`NativeApp/Features/Users/UserKeyCards.swift`、`UserKeyGroupSheet.swift`、`UserKeyFormSheet.swift`（新建与编辑共用）、`UserKeyRevealSheet.swift`。

---

## 8. 编辑用户 · Key 与限额 · 平台限额与替换分组

设计稿：`v-user-edit.jsx` 的 `UeQuotaSec`、`UeQuotaSheet`、`UeAddQuotaSheet`、`UeReplaceSec`、`UeReplaceSheet`。后端：E07（单平台 PUT / DELETE / restore）、E04（替换分组精确撤销）。

### 8.1 入口与导航

- 「Key 与限额」段里 API Key 区之下：平台限额分区；再下：替换分组分区（只在用户有专属分组时出现）。
- 平台限额行 → 平台限额 sheet；“＋ 添加平台限额”→ 平台选择 sheet → 平台限额 sheet。
- 替换分组行“替换「X」…”→ 替换分组 sheet；分组 sheet 的“改用替换分组”也进这里。

### 8.2 数据来源

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

### 8.3 字段 → 显示映射

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

### 8.4 交互与写操作

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

### 8.5 状态

| 状态 | 显示 |
|---|---|
| 限额加载失败 | 分区内“平台限额加载失败 · 重试” |
| 限额服务未启用 | 503 `SERVICE_UNAVAILABLE`（`platform quota service not available`）：分区写“站点没有启用平台限额” |
| 保存校验失败 | 400 `INVALID_QUOTA_LIMIT`：本地已按同一规则校验（非负、有限、< 1e10），正常不会出现；万一出现 sheet 底部红字“限额要大于等于 0、小于 100 亿”（服务端没有 `metadata` 指明哪一档，不解析 message，不定位到具体窗口）。400 `VALIDATION_ERROR` / `INVALID_PLATFORM` 不应出现，按通用约定 §3.3 显示“请求无效（错误码 VALIDATION_ERROR / INVALID_PLATFORM）”，不显示 message |
| 用户不存在 | 404 `USER_NOT_FOUND`：回到列表 |
| 重置不存在的限额 | 404 `USER_PLATFORM_QUOTA_NOT_FOUND`：刷新列表 |

### 8.6 刷新策略

切到该段时刷新一次限额列表；每次写后用响应替换；不轮询（窗口用量随计费变化，用户需要时下拉刷新）。

### 8.7 对现有代码的改动点

- 新增 `Sources/Sub2Core/PlatformQuota.swift`：`UserPlatformQuota`（三个窗口的 usage / limit / resetsAt；limit 区分 null 与 0）、`PlatformQuotaLimits` 编码（null 必须编码成 JSON `null` 或省略，PUT 严格解码不接受未知键）、`PlatformQuotaUndo` 决策纯函数（previous / current → DELETE / PUT / restore），配单测。
- `APIClient`：新增 `platformQuotas(userID:)`、`upsertPlatformQuota(userID:platform:limits:)`、`deletePlatformQuota(userID:platform:)`、`restorePlatformQuota(userID:platform:)`、`resetPlatformQuotaWindow(userID:platform:window:)`、`replaceUserPlatformQuotas(userID:quotas:)`（退路）、`replaceUserGroup(userID:request:idempotencyKey:)`。
- 新视图：`NativeApp/Features/Users/PlatformQuotaSection.swift`（含 sheet）、`ReplaceGroupSheet.swift`。

---

## 9. 本章跨章依赖

- **会话与通用约定**：`/admin/me` 的取得与缓存（capabilities、`user.id`、`run_mode`、`server_timezone`、step-up 状态）；错误解码要保留 `reason`、`metadata` 与 `Retry-After`（现在 `APIError` 只有 reason / status）；`APIClient` 返回响应头的请求变体与 304 处理；Idempotency-Key 生成与重试器（`IDEMPOTENCY_IN_PROGRESS` / `RETRY_BACKOFF` 按 `Retry-After`）；回执（Toast + 撤销）组件与时长；状态胶囊；金额、相对时间格式；只读令牌 `ACCESS_TOKEN_READ_ONLY` 提示；二次验证 sheet（6 位自动提交）。
- **会话与通用约定 §2.5.4 第 4 条**：该条要求“待核对的对象在核对完成前禁止发起新的同类写入”；本章 §3.4 按设计稿 `vuTopup` 允许同方向余额调整经两次确认后“仍要充值 / 仍要退款”，属于例外（兑换码章“仍要生成新的一批”同类）。00 章需要把这个例外和文案登记进去；登记前，余额调整按本章 §3.4 实现。
- **设置**：“高风险操作需要 Face ID”开关与金额门槛；设置里的“待核对余额”列表（调用本章 §3 的核对函数）；分组目录与平台目录的会话缓存。
- **概览**：“待处理 · 充值结果待核对”一项（数据来自 `pendingBalances`，点进用户详情）。
- **使用记录**：用户详情“使用记录 ›”进入 `{scope: usage, user: id}`，`admin/usage` 按 `user_id`、错误请求按 `user_id` 筛选，上游错误胶囊置灰。
- **兑换码**：用户详情 ⋯“发放兑换码（补偿）…”的向导 sheet（`POST /api/v1/admin/redeem-codes/create-and-redeem`，code 由 App 生成，强制 Idempotency-Key）；成功后本章刷新用户资料与记录。
- **分组**：分组目录（`groups/all?include_inactive=true`）同一份缓存；分组详情页的“API 密钥”列表复用本章的 Key 状态映射。
- **搜索**：全局搜索里的“用户”一路（`GET /api/v1/admin/users?search=`）点进本章用户详情。

---

## 10. 新增类型与接口汇总（Sub2Core）

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

## 11. 本章未决问题

1. **Key 新建 / 编辑表单没有设计稿**（设计稿只有“需后端新增”占位）。建议默认：按 §7.4 的最小表单实现（与 Web 用户端“创建 Key”同字段，单页 Form，sheet 呈现），上线前请用户看一次效果图再定。
2. **揭示完整 Key 的入口位置**：设计稿没有画。建议默认：放在 Key 卡片 ⋯ 菜单第三项“显示完整 Key…”，每次都要本机身份验证 + 服务端 step-up（开关开时）。
3. **`percentage` 阈值在 `total_recharged` 为 0 时的口径**：服务端 `quick-topup` 把阈值数字当美元用（`admin_quick_topup_repo.go:83-86`），附录 B L22 建议“宁可不标”。建议默认：列表行与详情跟服务端一致（同一屏不出现头像条和列表打标不一致），并请后端确认这是否是有意为之。
4. **“全部余额”退款用 `set 0`**：会在账本里记为 `operation=set`、标题“余额扣除（管理员）”。建议默认：采用（避免确认期间计费扣款导致 subtract 超额、被服务端以无 reason 的 500 拒绝后进入待核对）。
5. **`multi_select` 类型的自定义属性值格式**：本章没核实 Web 写入的值格式。建议默认：App 只读显示原值，编辑提示“在 Web 端修改”。
6. **主模式用户列表是否需要状态筛选（全部 / 启用 / 禁用）**：设计稿没有，现有 App 有。建议默认：主模式去掉（搜索已够用），留给简化模式。
7. **余额扣成负数、禁用 / 删除管理员、降级最后一位管理员等后端返回无 reason 的 500**：App 只能事前拦截。建议默认：按本章事前拦截实现，同时请后端给这几处补稳定 reason（如 `BALANCE_NEGATIVE`、`ADMIN_USER_PROTECTED`、`LAST_ADMIN`），之后 App 改为按 reason 显示。
8. **全部记录页给管理员调整行加第三行“余额 a → b · 操作人”**：设计稿记录行只有两行（设计时还没有前后余额）。建议默认：只在“全部记录”页加，详情页最近 5 条保持两行。

---

## 审查记录

- 回显服务端 message（MEDIUM，两条同类意见）：属实，已改。§3.4 `INVALID_BALANCE`、§5.5 服务端字段校验、§8.4 替换分组错误、§8.5 平台限额校验都改成按 reason 取固定文案，没有 reason 的 400 用 00 §3.3 的兜底；同类的 §1.5 “+ 原因”、§6.5 降级自己、§7.4 有效期格式（原先按 message 识别）一并改掉。意见里 10 / 50 / 60 章的位置不在本文件，未改。
- 用户列表导航栏写成大标题（LOW）：属实（`v-users.jsx` `VuUsersNav` 没有传 `large`），已改为居中标题。
- 键盘位数上限（LOW）：属实（`00-core.jsx` `cur.replace('.', '').length >= 7`），§3.3 已改为“数字总数最多 7 位（含小数部分），最多 2 位小数”，§3.7 把输入规则提成带参数的纯函数 `KeypadInput`。60 章的兑换码键盘不在本文件，未改。
- 核对只看 `total ≥ 1`（HIGH）：属实（`user_adjustment_handler.go:170-187` 的三个筛选是 G02 加的，`me_handler.go` 没有对应 capability）。§3.4 改为按 `kind`、`user_id` 和 action_id / request_id 本地复核，第一次查询没有匹配行时退回 keyword + 时间窗的第二次查询；`requestIDUnreliable` 与旧记录只出候选、由管理员确认，不自动 `resolve`。顺带补了：任何响应里的 `X-Admin-Adjustment-Action-ID` 都先存下（服务端在执行前就设这个头）、距发起不到 40 秒不下结论、多条候选时也给“用同一编号重试”（服务端按 action_id 去重，重试不会重复入账）。§3.6、§3.7、§10 的单测要求同步更新。
- “仍要充值”与 00 §2.5.4 第 4 条冲突（MEDIUM）：属实。本章按建议口径改成“同方向才拦、两次确认”（第二次确认在键盘提交的确认框里写明可能重复入账）。00 §2.5.4 不在本文件，改为在 §9 登记，由 00 章补上例外。
- 改动点位置引用（LOW）：本章这条属实，`definitelyRejected` 是 `UsersView.swift` 里 `BalanceView` 的 private 函数（第 539 行），已改；也更正了对它现状的描述（原文“所有 400”不准）。40 章那条不在本文件，未改。
