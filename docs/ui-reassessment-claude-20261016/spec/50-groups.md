# 50 · 分组

> 本章覆盖：分组列表（`groups`）、分组详情（`group`）、编辑 / 新建分组 sheet（`groupEdit`）、添加账号 sheet（`groupPick`）、成员批量写入逐项结果（`groupBatch`）、分组 API 密钥（`groupKeys`）、分组订阅（`groupSubs`）、首页下钻的分组内账号（`vtGroupAccounts`）。
>
> 依据：`DECISIONS.md`（第 2 轮“分组 可查看 + 可编辑”、第 3 轮 Q7 / Q8、“新建分组默认 正常 + 公开”、评审第 3 条状态胶囊、TPM 口径里的“账号成本”措辞）；设计稿 `html-preview/layouts/main/v-groups.jsx`（已定 = 列表 base、详情 base）与 `tools/routes/groups.json`；后端 sub2 `main` `70116315d`（F01–F05、D02、C14、C15、C17、E03、E06、G06 均已上线，口径以 `BACKEND-API-CHANGES.md` 实现进度表备注为准）。
>
> 下文接口路径都相对 `/api/v1`，字段名逐个对过后端源码；“后端位置”一栏的路径相对 `sub2/backend/internal/`。
>
> 设计稿里的对比变体（列表 grid / table、详情 ring / table）不实现；表格样子留给以后的简化模式。

---

## 0. 本章共用口径（各页面引用）

### 0.1 用到的 capability（`GET /admin/me` → `data.server.capabilities`）

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

### 0.2 四个桶、健康判定与 D02 的对账

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

### 0.3 色格条与图例

- 一格一个账号，顺序：可用 → 受限 → 错误 → 暂停·停用。格子不带账号身份，只用四个计数画。
- 列表：96×8 pt，格间距 2 pt，单格最小宽 3 pt；成员数放不下（`n × 5 > 96`，即超过 19 个）时改画四段按比例的条（非 0 的段最小 3 pt）。详情状态卡：满宽 × 12 pt，间距 3 pt，同样放不下时改比例段。
- 着色：可用 `--ok` 实心；受限 `--caution` 实心；错误 `--critical` 实心；暂停·停用为 1.5 pt `--neutral` 描边、60% 不透明。没有成员：一格 1 pt `--critical` 描边。停用分组：所有格子改为 `--neutral` 描边、45% 不透明。
- 无障碍：整条一个元素，标签“可用 x / y”。状态从不只靠颜色：旁边总有“可用 x/y”数字与文字说明。
- 图例：`可用 n · 受限 n · 错误 n · 暂停·停用 n`，为 0 的项变淡。

### 0.4 成员写入协议（F01）

#### 0.4.1 请求

`POST /admin/groups/:id/accounts/batch`（`handler/admin/group_members_handler.go`，`service/admin_group_members.go`）

```json
{"add":[{"account_id":11},{"account_id":12,"priority":2}],"remove":[13],"confirm_mixed_channel_risk":false}
```

- `priority` 可省，省略或 ≤0 时默认 50；撤销“移出”时把响应里的旧 `priority` 传回。
- `add` 与 `remove` 去重后合计 ≤ 200；同一账号不能同时在两边。App 一次超过 200 个时拆批顺序发送。
- 不需要 `Idempotency-Key`：已在组内的加入、不在组内的移出都返回 `unchanged`，原样重放安全。
- 不碰账号行本身，不改该账号在其他分组的优先级。

#### 0.4.2 响应

```json
{"group_id":3,"added":1,"removed":1,"unchanged":1,"failed":1,
 "results":[{"account_id":11,"action":"add","status":"added","priority":50},
            {"account_id":14,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK","message":"…","details":{"current_platform":"Antigravity","other_platform":"Anthropic"}}],
 "counts":{"account_count":6,"active_account_count":4,"rate_limited_account_count":1,"error_account_count":0,"idle_account_count":1}}
```

- `results[]`：`account_id`、`action`（add / remove）、`status`（added / removed / unchanged / failed）、`priority`（added / removed 时有）、`reason` / `message` / `details`（failed 时有）。结果按 action 排序（add 在前）。
- `counts` 可能缺省（回读失败时），缺省就保留旧计数并刷新详情。
- 逐项失败只有两种 reason：`ACCOUNT_NOT_FOUND`（不存在或不属于本工作区）、`MIXED_CHANNEL_RISK`（只在 Anthropic 与 Antigravity 混用时出现，`details` 里的平台名是首字母大写的展示名，不是平台枚举）。

#### 0.4.3 回执与撤销（列表、详情、两个 sheet 共用）

| 结果 | 回执文案 | 回执按钮 |
|---|---|---|
| 全部成功 | `已加入 n 个账号` / `已移出 n 个账号` / `已加入 a 个、已移出 b 个账号`；有变化时后缀 ` · 可用 x → y`（x、y 取写入前与 `counts.active_account_count`） | 撤销（发反向请求：added → remove；removed → add 并带回 priority） |
| 部分失败 | `已加入 a 个，n 个失败`（移出同理） | 查看 → `groupBatch` 结果页 |
| 全部失败 | `加入失败 · n 个账号没有改动` | 查看 → `groupBatch` |
| `unchanged` | 计入成功，不单独说 | — |

前缀：新建时 `已创建「名称」 · …`，编辑保存时 `已保存「名称」 · …`。

#### 0.4.4 退路（没有 `groups.member_batch`）

逐个账号串行：`GET /admin/accounts/:id` 取最新 `group_ids` → 本地加入或去掉本组 → `PUT /admin/accounts/:id` 只带 `group_ids`。每个账号一个结果，遇到 409 `MIXED_CHANNEL_WARNING` 记为该账号失败（reason 记 `MIXED_CHANNEL_RISK`，详情从 409 的 `details` 取）。这条路径有副作用（会按快照写回账号整行、重置该账号在其他分组的优先级），所以退路模式下 sheet 底部提示改为“服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改。”

### 0.5 停用 / 启用 / 复制 / 删除（列表滑动、长按菜单、详情 ⋯ 共用）

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

### 0.6 显示格式

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

### 0.7 权限与运行模式

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

### 0.8 分组相关错误 reason → 文案

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

## 1. 分组列表（`screen:groups`）

### 1.1 入口与导航

- 进入：搜索 Tab 目录“资源 → 分组”（`00-core.jsx:839`）；首页“可用不足 N 个分组”行在 N > 1 时进入本页，并选中“需处理”段（10 章 §1.1）。
- 去向：点行 → 分组详情；右上 + → 新建分组 sheet；右滑“添加账号” → 添加账号 sheet；左滑“编辑” → 编辑分组 sheet，“停用 / 启用” → 0.5；长按 → 上下文菜单（编辑分组、添加账号、停用分组… / 启用分组、复制分组、删除分组…（红字，分隔线后））。

### 1.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| 分组与四桶计数 | `GET /admin/groups` | `page=1&page_size=1000`（默认 `sort_by=sort_order&sort_order=asc`，`status` 不传 = 全部状态） | 带 `If-None-Match`（`lists.etag`），304 时用缓存；`total > 1000` 时继续翻页。`handler/admin/group_handler.go:371-415` |
| 今日实际扣费 | `GET /admin/groups/usage-summary` | 无（站长按服务器时区；vendor 传 `timezone=<server_timezone>` 保持一致） | 返回数组 `[{group_id, today_cost, yesterday_cost, total_cost}]`，按 `group_id` 合并。`:975-1006` |
| 可用偏低判定 | `GET /admin/accounts/status-summary` | 无参数（不带 `include_accounts`） | 取 `data.groups[].shortage.is_short` 按 `group_id` 合并；服务端 10 秒缓存。vendor / 无 `accounts.status_summary` 时按 0.2 本地判定 |

三个请求并发；列表只依赖第一个，其余两个失败只影响对应的格子。

### 1.3 字段 → 显示映射

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

### 1.4 交互与写操作

| 操作 | 条件 | 行为 |
|---|---|---|
| 右滑“添加账号”（accent） | 只对 `status=active` 的分组，且有加减成员权限（0.7） | 打开 4 `groupPick` |
| 左滑“编辑” | 有编辑权限 | 打开 3 `groupEdit` |
| 左滑“停用” / “启用” | 有编辑权限、非简易模式 | 见 0.5 |
| 右上 + | 有新建权限 | 打开 3 `groupEdit`（新建） |
| 长按 | — | 同详情 ⋯ 菜单（`fromList`：删除后留在列表） |

滑动操作同时放进长按菜单，VoiceOver 通过菜单触达。

### 1.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 骨架行 3 条 |
| 空（站点没有分组） | 空态“还没有分组” + “新建分组”按钮（有权限时） |
| 搜索无结果 | “没有匹配的分组” |
| `groups` 失败 | 有缓存：保留旧数据，顶部细条“刷新失败 · 重试”；无缓存：错误态 + 重试 |
| usage-summary 失败 | 各行“今日 —”，不报错 |
| status-summary 失败 / 403 | 静默改用本地阈值判定 |
| 401 / 423 等全局错误 | 交给会话层（通用约定） |

### 1.6 刷新策略

- 进入时加载；下拉刷新三个请求全刷。
- 前台每 60 秒自动刷新（DECISIONS 第 2 轮“刷新”）；离开页面或进入后台停止。
- `GET /admin/groups` 用 ETag；另外两个没有 ETag，照常请求。
- 写操作成功后：本地先改（停用 / 启用乐观更新），随后静默刷新三个请求；新建、复制、删除、改名后同时刷新分组目录缓存（`groups/all?include_inactive=true`，账号、用户等页面用它显示组名）。

### 1.7 对现有代码的改动点

- `NativeApp/Features/GroupsView.swift:GroupsView` → 重写为 `GroupListView`：去掉“筛选”分区的平台 / 状态 Picker（改为本地搜索 + 三段分区），去掉分页“加载更多”（一次拉全量），行改为三行样式；`.searchable` 提示改为“分组名称或平台”。
- `GroupsView.swift:GroupWorkspace` → 抽成跨页面共享的 `@Observable GroupStore`（列表缓存、usage-summary 缓存、shortage 映射、`revision`），保留 `isUITesting` 的 fixture 分支，fixture 改为设计稿的 10 个分组（`shared/data.jsx` DEMO.groups）。
- `Sources/Sub2Core/GroupManagement.swift:APIClient.groups(page:search:platform:status:)` 保留；新增 `groupList(etag:)`（返回 `.notModified` / `.page(Page<AdminGroup>, etag)`）——依赖通用约定里 APIClient 的条件请求支持。
- 新增 `APIClient.groupUsageSummary() -> [GroupUsageSummary]`、`accountStatusSummary(groupID:)`（D02，可与首页章节共用）。
- 新增 `Sources/Sub2Core/GroupPresentation.swift`：`GroupHealth`（0.2 判定）、`GroupBuckets`、色格条分段计算、`rateText`、`limitText`、`rpmText`、删除后果行、停用确认文案（纯函数，便于单测）。
- 新增 `NativeApp/Features/Groups/GroupCellsView.swift`（色格条 + 图例，列表与详情共用）。
- 入口：`NativeApp/Sub2MobileApp.swift:ManagementView` 的“分组管理”迁到搜索目录（导航章节负责）。
- 新增文件后运行 `scripts/generate_project.py` 重新生成工程（它按目录 `rglob("*.swift")` 收集）。

---

## 2. 分组详情（`screen:group`，route `{kind:'group', id}`）

### 2.1 入口与导航

- 进入：分组列表行；请求详情的“分组”行（`00-core.jsx:995`）；统计分析的分组排行行（`v-analytics.jsx:422`）；首页“可用不足 N 个分组”行（N = 1 时，10 章 §1.1）与告警详情范围区的分组行（10 章 §3.1，见 8）；复制分组回执“查看”。
- 去向：⋯ 菜单（编辑分组、添加账号、停用分组… / 启用分组、复制分组、删除分组…）；告警横幅 → 告警详情 `{kind:'alert', id}`；成员行 → 账号详情；“添加 <平台> 账号”行 → `groupPick`；记录与关联 → 使用记录（带分组筛选）、`groupKeys`、`groupSubs`；“在 Web 中编辑”行 → 浏览器打开 `<站点>/admin/groups`（Web 路由 `frontend/src/router/index.ts:473`）。

### 2.2 数据来源

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

### 2.3 字段 → 显示映射

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

### 2.4 交互与写操作

| 操作 | 请求 | 确认 | 成功后 |
|---|---|---|---|
| 启用 / 停用 / 复制 / 删除 | 0.5 | 0.5 | 0.5；停用 / 启用后重拉本页 |
| 成员左滑 · 状态动作 | 错误、过载、限流、临时不可调度 → “恢复状态”；暂停 → “启用调度”；正常 → “停止调度”（接口与两种恢复选择见账号章节：`recover-state`、`/accounts/:id/schedulable`） | 账号章节 | 回执带撤销；重拉成员、分组计数、容量 |
| 成员左滑 · 移出（critical） | 0.4：`{"remove":[id]}` | 账号正常、分组正常且 `active_account_count == 1` 时确认：标题 `把「账号」移出「分组」？`，正文 `站点 <站点名>`、`它是这个分组唯一可用的账号，移出后这个分组的新请求会失败。账号本身保留。`，按钮“仍然移出”（destructive）/ 取消；其余直接执行 | 乐观移除该行；回执 `已移出「账号」`，账号可用时追加 ` · 可用 x → x−1`；撤销 = `{"add":[{"account_id":id,"priority":<响应里的 priority>}]}`；失败把行放回并提示 |
| 告警横幅 | — | — | push 告警详情；返回时重拉横幅（告警被手动解决后横幅消失） |

成员行的滑动动作同时放进长按菜单。没有加减成员权限时只保留状态动作。

### 2.5 状态

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

### 2.6 刷新策略

- 进入时全部加载；下拉刷新全部。
- 前台每 60 秒刷新：分组本身、成员、成员今日、容量、告警横幅、可用偏低；stats 与两个 24 小时计数只在进入、下拉、写操作后刷新。
- 最早恢复倒计时每秒本地递减；某个窗口到点后立即重拉成员与分组计数一次。
- 无 ETag、无 since_id。
- 写操作后：成员写入用响应 `counts` 先更新状态卡，再重拉成员、成员今日、容量；改名后同步更新分组目录缓存，账号详情等处随之显示新名称。

### 2.7 对现有代码的改动点

- `GroupsView.swift:GroupDetailView` → 重写：去掉“分组信息 / 账号与容量 / 用量 / 管理”四个 LabeledValue 分区，改为 横幅 + 状态卡 + 按钮行 + 四个编号分区；`NavigationLink("查看与管理分组账号") { AccountsView(initialGroupID:) }` 删除（成员直接在本页）；`NavigationLink("统计分析")` 删除（设计稿没有）；`NavigationLink("请求记录")` 改为“记录与关联”里的三行。
- 保留并复用：`refresh()` / `refreshCapacity()` 的 `readTicket`、`sessionGeneration` 防串号写法；`perform(_:)` / `reconcile()` 的“结果待确认”流程（停用、删除沿用）；`groupWriteDefinitelyRejected`。
- 文案改动：状态“启用” → “正常”；“计费倍率” → “费率倍数”；“按量 / 订阅” → “标准（余额）/ 订阅（配额）”；“RPM 限额” → “每用户 RPM”。
- `GroupManagement.swift:AdminGroup` 增加 `errorAccountCount`、`idleAccountCount`（`Int?`，nil = 老服务端）、`sortOrder`、`claudeCodeOnly`、`fallbackGroupID`；`GroupCapacitySummary` 不变。
- `GroupManagement.swift:APIClient.groupCapacities()` 增加 `groupCapacities(groupIDs:)`（有 `groups.capacity_filter` 时带 `group_id`，否则全量本地过滤）。
- 新增 `APIClient.groupStats(id:) -> GroupStats?`（无 `subscriptions_total` 键时返回 nil 走退路）、`groupTodayUsage(id:serverTimezone:)`（dashboard/groups）、`accountTodayStats(ids:groupID:)`（扩展 `APIClient.accountTodayStats(ids:)`，回传 `failed_account_ids` 与回显的 `group_id`）、`firingAlerts(groupID:)`（可与监控章节共用）。
- 新增 `NativeApp/Features/Groups/GroupDetailView.swift`；成员行复用账号章节的 `AccountRow`（需支持 `omit/home` 参数）；容量条复用账号详情的容量组件。
- `Tests/Sub2CoreTests/GroupManagementTests.swift` 补：新字段解码（含键缺失）、四桶推导与退路、健康判定、`groupStats` 老服务端识别。

---

## 3. 编辑 / 新建分组（`sheet:groupEdit`）

### 3.1 入口与导航

- 新建：列表右上 +；`{kind:'groupEdit', isNew:true}`。
- 编辑：列表左滑“编辑”、长按 / ⋯“编辑分组”、详情按钮行“编辑分组”、配置区可编辑项。
- sheet 内两页：表单页 ↔ “添加账号”页（同一 sheet 内导航，左上“新建分组 / 编辑分组”返回）。
- 左上“取消”；右上“创建” / “保存”（未改动或不合法时置灰）。

### 3.2 数据来源

| 用途 | 来源 |
|---|---|
| 初值 | 编辑：详情已有的 `dto.AdminGroup` 与成员列表；新建：默认值（下表） |
| 平台下拉（仅新建） | `meta.catalog` 的 `platform_catalog.platforms[]`（去掉 `composite`）；无能力时内置表 |
| 同名检查 | 列表缓存里的 `name`（精确比较，排除自己）；最终以服务端 409 `GROUP_EXISTS` 为准 |
| 添加账号页 | 同 4.2 |
| 写入 | 新建 `POST /admin/groups`；编辑 `PUT /admin/groups/:id`；成员 0.4 |

新建默认值（与 Web createForm 一致，DECISIONS“新建分组默认 正常 + 公开”）：名称空、描述空、平台 `anthropic`、状态正常（POST 没有 status 字段，后端总是建成 active）、公开、费率倍数 1.0、标准（余额）、每用户 RPM 0（不限）、订阅限额空、不限 Claude Code。

### 3.3 字段 → 显示映射（表单）

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

### 3.4 交互与写操作

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

### 3.5 状态

| 状态 | 显示 |
|---|---|
| 校验不通过 | 右上按钮置灰；名称同名红字；倍率非法时字段红框 |
| 提交中 | 右上按钮换转圈，表单禁用 |
| 409 `GROUP_EXISTS` | 名称下红字，保持打开 |
| 其他明确失败（400 / 403 / 404 / 422） | 表单底部红字 message，可修改后重试（新的 key） |
| 不确定（超时、5xx、断网） | 沿用现有“结果待确认”：不自动重发；“读取服务器状态核对”——编辑按字段比对，新建按名称精确搜 `GET /admin/groups?search=<名称>&platform=<平台>`；有 `admin.idempotent_writes` 时先用同一 key 重发一次拿回结果 |
| 成员写入失败 | 不阻塞分组本身的成功回执，按 0.4.3 |

### 3.6 刷新策略

不轮询。打开时用调用方已有数据；切到添加账号页时按 4.6 拉账号。

### 3.7 对现有代码的改动点

- `GroupsView.swift:GroupEditorView` → 改写为 `GroupEditSheet`：去掉“目标站点”分区（站点写进确认框第一行）；编辑时平台、计费类型只读（现在可改计费类型，要改）；加状态开关（仅编辑）；费率倍数改为步进器；加“成员账号”区与 sheet 内的添加账号页；按钮从“核对并确认”改为右上“创建 / 保存”，确认框内容按 3.4。
- 保留：`prepare()` / `send()` / `reconcile()` 的待确认流程、`limitChange(_:previous:)`、`decimal(_:label:)`、`isCurrent` 会话检查、`onChange(of: model.sessionGeneration)` 关闭。
- `GroupManagement.swift:GroupCreateRequest` 默认 `platform` 由 `"openai"` 改为 `"anthropic"`。
- `GroupManagement.swift:GroupPlatform.values` 拆出 `concrete`（不含 `composite`）给新建 Picker 用；`title(_:)` 保留。
- `APIClient.createGroup/updateGroup/deleteGroup` 增加 `idempotencyKey: UUID` 参数并写 `Idempotency-Key` 头（参照 `APIClient` 余额写入的写法）；`PreparedGroupWrite` 里保存这个 UUID，重试复用。
- 新增 `Sources/Sub2Core/GroupMembers.swift`：`GroupMemberBatchRequest`（≤200 拆批）、`GroupMemberBatchResult` 解码、`receiptText(...)`、`inverse(of:)`（撤销请求）、0.4.4 退路执行器；配单测。
- `GroupPresentation.swift` 增加 `diffLines(old:new:)`（确认框逐行文案）与 `availableAfter(members:platform:)`。

---

## 4. 添加账号（`sheet:groupPick`，也作为 groupEdit 内的子页）

### 4.1 入口与导航

- 直接打开：列表右滑“添加账号”、长按 / ⋯“添加账号”、详情按钮行“添加账号”、成员区“添加 <平台> 账号”行。标题 `添加到「分组名」`，左上“取消”。
- 编辑 sheet 内：标题“添加账号”，左上返回“新建分组 / 编辑分组”，右上“添加 N”（只把选中账号加入草稿，不提交）。

### 4.2 数据来源

| 用途 | 接口 | 参数 |
|---|---|---|
| 候选账号 | `GET /admin/accounts` | `platform=<分组平台>&lite=1&sort_by=urgency&page=1&page_size=200`（组合分组不带 `platform`）；输入搜索时追加 `search=<词>`（防抖 300ms，服务端截到 100 字节） |
| 组名显示 | 分组目录缓存（`groups/all?include_inactive=true`） | 把账号 `group_ids` 换成名称 |

排除当前成员（`group_ids` 含本组 id 的账号；编辑 sheet 内排除草稿里的成员）。

### 4.3 字段 → 显示映射

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

### 4.4 交互与写操作

- 点行切换选中。
- 直接打开时点“加入 k 个账号”：0.4 `add`（不带 priority）；关闭 sheet；回执按 0.4.3（全部成功带撤销，部分失败带查看）。
- 结果里有 `MIXED_CHANNEL_RISK` 时，回执“查看”进 5，在结果页确认后带 `confirm_mixed_channel_risk=true` 重试。
- 编辑 sheet 内点“添加 N”：只并入草稿，回到表单页。

### 4.5 状态

| 状态 | 显示 |
|---|---|
| 加载中 | 列表骨架 |
| 加载失败 | “账号加载失败 · 重试” |
| 提交中 | 按钮转圈，禁止关闭 |
| 请求级失败 | 0.8“网络错误 / 超时（成员写入）” |

### 4.6 刷新策略

打开时加载一次；搜索变化重新请求；不轮询；不下拉刷新（sheet 内）。

### 4.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupAccountPicker.swift`（直接打开与 sheet 内子页共用一个视图，用参数区分“提交”与“并入草稿”）。
- 账号列表请求复用 `APIClient.accounts(page:search:status:platform:...)`（`Sources/Sub2Core/APIClient.swift:136-139`），需要补 `lite`、`sort_by` 参数（账号章节同样需要）。
- 状态徽章、停调度标记复用账号章节组件。

---

## 5. 成员批量写入逐项结果（`screen:groupBatch`）

### 5.1 入口与导航

- 进入：任一成员写入回执里的“查看”（只有存在失败项时才出现）。route 携带 `{id, name, items}`，items 来自 0.4.2 的 `results`（加上 App 自己记的账号名）。
- 去向：点行 → 账号详情；返回 → 上一页。

### 5.2 数据来源

不额外请求。重试与撤销调 0.4 接口。账号名、状态取 App 账号缓存；缓存里没有时用提交时记下的名称，状态显示“停用”图形。

### 5.3 字段 → 显示映射

| 元素 | 字段 / 计算 | 格式与文案 | 空值 |
|---|---|---|---|
| 导航 | 分组名、项数 | `逐项结果`，副标题 `高级组 · 3 个账号` | — |
| 状态卡（有失败） | 失败数 f、成功数 s | caution 状态胶囊；大徽章 `f 个失败`，右侧 `s 个成功`；说明 `失败的账号没有改动，可以直接重试，或点开账号单独处理。` | — |
| 状态卡（无失败） | — | 安静卡：`全部完成 · 已加入 2 个账号`；全部撤销后 `已全部撤销` | — |
| 按钮行 | — | `重试 n 个`（主，n = 可重试的失败数）· `撤销成功的 s 个` | n=0 / s=0 时不显示对应按钮 |
| 壹 · 失败 | `status=failed` 的项 | meta `f 个 · 没有改动`；行：状态图形 + 名称，右侧 critical 徽章 `加入失败` / `移出失败`；第二行原因 | — |
| 失败原因 | `reason` | `ACCOUNT_NOT_FOUND` → `账号不存在或已删除`（不可重试）；`MIXED_CHANNEL_RISK` → `分组里已有 <other_platform> 账号，与 <current_platform> 账号混用有风险`（可重试，需确认）；请求级失败 → `请求没有送达，账号没有改动`（可重试） | 其他 reason 显示 `message` |
| 贰 · 成功 | added / removed / unchanged / 已撤销 | meta `s 个`；右侧 `已加入` / `已移出` / `重试后已加入` / `无需改动` / `已撤销`（变淡） | — |

### 5.4 交互与写操作

- “重试 n 个”：可重试项分两类发送：
  - 请求级失败的项：原样重发（幂等）。
  - `MIXED_CHANNEL_RISK` 的项：先确认 `仍然加入混合渠道账号？`，正文 `分组里已有 <other> 账号。同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。`（据 `service/admin_account.go:1928-1931` 的错误说明），按钮“仍然加入” / 取消；确认后带 `confirm_mixed_channel_risk=true`。
  - 成功的项改到“成功”区并标“重试后已加入 / 已移出”；回执 `重试成功 · 已加入 n 个账号`。
- “撤销成功的 s 个”：0.4.3 的反向请求；成功项标“已撤销”；回执 `已撤销 s 个账号的改动`。
- 写入后刷新分组详情（返回时可见）。

### 5.5 状态

重试 / 撤销进行中按钮转圈；请求级失败时状态卡下红字 `没有完成，请稍后重试`，项目状态不变。

### 5.6 刷新策略

不轮询，不下拉刷新。

### 5.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupBatchResultView.swift`；结果模型、原因文案、重试分组、反向请求放在 `Sources/Sub2Core/GroupMembers.swift`。
- 现有代码没有对应页面。

---

## 6. 分组 API 密钥（`screen:groupKeys`）

### 6.1 入口与导航

- 进入：详情“记录与关联 → API 密钥”。vendor、简易模式不提供（后端 403）。
- 去向：点行 → 所属用户详情（用户章节）；换分组、重置速率限制都在用户的 Key 卡片里做。

### 6.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| Key 列表 | `GET /admin/groups/:id/api-keys` | `page=<n>&page_size=20&key_view=masked` | 分页；排序为 id 倒序（handler 不传排序，`repository/api_key_repo.go:651-695` 默认 id desc）；每项 `dto.APIKey` 含 `user`；E11 起回填 `current_concurrency` |
| 今日实际扣费 | `POST /admin/dashboard/api-keys-usage` | `{"api_key_ids":[本页 id]}` | `data.stats` 以 Key id 字符串为键，取 `today_actual_cost`；“今日”为服务器时区（E09） |

### 6.3 字段 → 显示映射

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

### 6.4 交互与写操作

只读。点行进入用户详情。

### 6.5 状态

| 状态 | 显示 |
|---|---|
| 首次加载 | 骨架行 |
| 列表失败 | 错误态 + 重试；翻页失败在底部“加载失败 · 重试” |
| 用量失败 | 今日 `—`，不报错 |
| 400 `Invalid key_view, use full/masked` | 这是 App 自己的参数错误：只有 App 发了 full / masked 以外的值，新服务端才会这样回（`handler/admin/api_key_view.go:13-23`）。老服务端不认 `key_view`，会忽略它并回明文，这种情况按 0.1 的退路处理。遇到这个 400：写日志，界面按“列表失败”处理，不重试 |

### 6.6 刷新策略

进入时加载第一页；滚到底加载下一页（每页拉到后补拉这一页的今日用量，每批 ≤ 200 个 id）；下拉刷新回到第一页；不轮询。

### 6.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupKeysView.swift`。
- 新增 `APIClient.groupAPIKeys(id:page:) -> Page<AdminAPIKey>`（Key 模型与用户章节共用，需含 `key_masked`、`effective_status`、`quota`、`quota_used`、`expires_at`、`last_used_at`、`user`；解码时丢弃 `key`；状态徽章用 30 章的 `AdminAPIKeyStatus`，本章不另写映射）与 `apiKeysTodayUsage(ids:) -> [Int: Decimal]`（用户章节同样需要）。
- 现有代码没有对应页面。

---

## 7. 分组订阅（`screen:groupSubs`）

### 7.1 入口与导航

- 进入：详情“记录与关联 → 订阅”（只对订阅计费分组显示）。vendor、简易模式不提供。
- 去向：点行 → 用户详情；调整有效期、重置配额、撤销在 Web 订阅管理里做。

### 7.2 数据来源

| 用途 | 接口 | 参数 | 说明 |
|---|---|---|---|
| 订阅列表 | `GET /admin/groups/:id/subscriptions` | `page=<n>&page_size=20` | 按 `created_at` 倒序（`repository/user_subscription_repo.go:215-236`），带 `user`；返回前已把过期窗口清零、已到期的 active 改为 expired（`service/subscription_service.go:811-823,866-874`）；已撤销的是软删除，不会出现 |
| 生效数 | 详情已拿到的 stats `subscriptions_active` | — | 退路 `GET /admin/subscriptions?group_id=<id>&status=active&page_size=1` 的 `total` |
| 每订阅限额 | 分组的 `daily/weekly/monthly_limit_usd` | — | 详情已有 |

### 7.3 字段 → 显示映射

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

### 7.4 交互与写操作

只读。点行进入用户详情。

### 7.5 状态

同 6.5（没有用量子请求）。

### 7.6 刷新策略

进入时加载第一页；滚到底翻页；下拉刷新；不轮询。

### 7.7 对现有代码的改动点

- 新增 `NativeApp/Features/Groups/GroupSubscriptionsView.swift`。
- 新增 `APIClient.groupSubscriptions(id:page:) -> Page<AdminUserSubscription>`（模型字段：`id`、`user_id`、`group_id`、`starts_at`、`expires_at`、`status`、`daily_usage_usd`、`weekly_usage_usd`、`monthly_usage_usd`、`user`；与用户章节的订阅模型共用）与 `activeSubscriptionCount(groupID:)`（退路）。
- 现有代码没有对应页面。

---

## 8. 首页下钻：分组内账号（`vtGroupAccounts`）

### 8.1 入口与导航

设计稿的路由规则（`v-today.jsx:195-197`，`vtGroupRoute`）：有分组详情页时进分组详情 `{kind:'group', id}`，没有时才进 `vtGroupAccounts`。最终 App 有分组详情，所以本页不作为主入口。实际进分组的入口只有两个：

- 首页“可用不足 N 个分组”行（10 章 §1.1）：N = 1 时直接用该行的 `group_id` push 分组详情（第 2 节）；N > 1 时推入分组列表并选中“需处理”段（第 1 节）。
- 告警详情范围区的分组行（10 章 §3.1、§3.3）：用事件的 `dimensions.group_id` push 分组详情。分组已删除（事件仍有 `group_name`，但 availability 里没有这个分组）时，这一行显示“分组已删除”且不可点（10 章 §3.3）。
- 进入详情后才发现分组已删（`GET /admin/groups/:id` 返回 404），显示 2.5 的“这个分组已删除”整页空态，不进本页。

已定首页的待处理是合并粒度（DECISIONS 第 2 轮 Q3），没有分组卡；平静布局也没有“其他分组”行（那是未选的 homePend `group` 变体，`v-today.jsx:411` 的 `vtGroupItems`）。若要在分组详情上线前先出过渡版本，按下面的规格用账号列表加分组筛选实现。

### 8.2 数据来源（过渡版本）

`GET /admin/accounts?group=<id>&lite=1&sort_by=urgency&include_counts=1&page=1&page_size=100`；需处理数 = `data.counts.needs_attention`，全部 = `data.counts.all`（C14；无该能力时本地数 错误 + 限时状态）。

### 8.3 字段 → 显示映射（过渡版本）

| 元素 | 内容 |
|---|---|
| 导航 | 标题为分组名（移除分组筛选后为“账号”）；副标题 `<站点名> · n 个 · a 个可用` |
| 筛选胶囊 | `分组：<名称> ✕`（可移除）、`需处理 n`（有需处理时用警示样式）、`全部 n` |
| 行 | 账号章节三行行；有分组筛选时 `omit: group`、`home: <名称>` |
| 空态 | `没有需要处理的账号` |

### 8.4 交互、8.5 状态、8.6 刷新

同账号 Tab 列表（账号章节）。

### 8.7 对现有代码的改动点

- 过渡版本直接复用 `NativeApp/Features/AccountsView.swift:AccountsView(initialGroupID:)`（已支持初始分组筛选，`AccountsView.swift:61-62`），补“需处理 / 全部”胶囊。
- 最终版本：首页“可用不足 N 个分组”行与告警范围区分组行按 8.1 路由到分组详情 / 分组列表；不新增本页文件。

---

## 9. 本章新增 / 改动文件汇总

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

## 本章未决问题

1. **vendor 能否在分组页加减成员。** 后端 `POST /admin/groups/:id/accounts/batch` 对 vendor 一律 403（vendor 白名单只放行 `/admin/groups` 的 GET、PUT、PATCH），而 vendor 有账号管理权限时可以用 `PUT /admin/accounts/:id` 改 `group_ids`（F01 的逐账号退路）。设计稿只按站长设计。
   建议默认：vendor 视角隐藏分组页的所有成员写入口（添加账号、移出、编辑 sheet 的成员区），成员分区底部注“调整成员请在账号详情里修改分组”；需要时再给 vendor 开逐账号退路，或请后端对有账号管理档的 vendor 开放批量接口。

2. **成员行“今日”的口径。** 设计稿用账号全站今日并加脚注（当时后端不能按分组统计）；C17 上线后 `today-stats/batch` 可以只算本分组，`BACKEND-API-CHANGES.md` 的 C17 正是为这个页面做的。
   建议默认：有 `accounts.today_stats_group` 时用分组口径（成员今日之和与分组今日对得上），脚注写“只算这个分组的请求”；没有时退回全站口径并用设计稿原脚注。

3. **停用确认里的 Key 数用哪个数。** 设计稿用分组绑定的 Key 总数；但“会被拒绝”只对原本可用的 Key 有意义，`groups/:id/stats` 同时给了 `total_api_keys` 与 `active_api_keys`。
   建议默认：停用确认用 `active_api_keys`；详情“API 密钥 N 个”与删除确认用 `total_api_keys`（与 API 密钥页 `total` 一致）。

---

## 审查记录

- §0.1 `api_keys.effective_status` 的退路：已改。原来的本地映射漏掉了库里 `status` 本身就是 quota_exhausted / expired 的情况，现在改为引用 30 章 §7.3 的 `AdminAPIKeyStatus`，与 E06 进度表的计算顺序一致；§6.3 与 §6.7 也跟着改成引用这个函数。00 章 §5 对应行不在本章文件内，本次没改，需要由 00 章的负责人同步修改。
- §6.5 的 400 `Invalid key_view`：已改。新服务端只在取值不是 ""、full、masked 时返回这个 400（`api_key_view.go:13-23`），老服务端会忽略这个参数，所以现在改为按 App 参数错误处理：写日志，按列表失败显示。
- §8.1 的入口：已改。删掉了“分组卡”和“平静布局的其他分组行”，入口改为首页“可用不足 N 个分组”行和告警详情范围区的分组行。§1.1、§2.1、§8.7 的同类说法一起改了。已删除分组的处理跟 10 章 §3.3 对齐：告警范围区里这一行不可点。
