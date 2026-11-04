# 05 · 对 codex UI 重构方案的批判性审阅

- 审阅对象：`docs/ui-reassessment-20261016/`（README、ASSESSMENT、DESIGN_BRIEF、design-demos/a|b|c.jsx 与 css、screenshots、VERIFICATION.json）
- 对照基线：分支 `codex/native-ios-rebuild`，提交 `7ccd542`；后端参照 `G:/weixinProject/sub2`（提交 `40bee5d2e`）
- 方法：逐条打开 codex 引用的 `文件:行号`；阅读 `NativeApp/` 全部 Feature 视图与 `Sources/Sub2Core/` 的展示和模型代码；查看 codex 引用的 3 张历史截图和另外 8 张截图；阅读三份原型源码并实测其截图。
- 标注约定：**【事实】** 指已用源码、截图或文档核实的内容；**【推断】** 指基于事实作出的判断，需要用户或真机验证。
- 只读审阅：除本文件外，没有改动任何源码或文档。

---

## 0. 结论速览

1. **事实核查方面，codex 可信度高。** ASSESSMENT 第 3 节的 12 条问题全部属实，行号误差不超过 2 行。不少条目的实际范围比它写的更大，例如全应用 10 个确认对话框全部用了 `.destructive`。
2. **诊断方向正确，处方没有走到底。** “问题不在 SwiftUI，而在于用同一种 List/Form 承载不同任务”这个判断成立。还可以再进一步：多数 P1 问题，用**更完整的原生能力**就能解决，例如 `List(selection:)` 编辑模式、`searchable` tokens、swipe actions。codex 却把方向引向了网页化的自绘组件。
3. **三个“方向”是同一套信息架构换了三层皮。** A、B、C 的 Tab 结构、管理中心条目、详情结构和确认面板几乎一样。真正需要用户拍板的 IA 决策（用户降级、取消设置 Tab、日志的默认形态）被当作前提写死，没有拿出来做比较。
4. **原型避开了最“反人类”的几个界面。** 日志对象筛选（codex 自己列的 P1）、账号编辑表单、余额调整、批量逐项结果、“结果不明/待核对”、加载与失败态，三版都没有画。四屏只覆盖了相对好改的部分。
5. **漏掉了第三种身份：vendor（代运营）。** 移动端代码和 Web 后台都已存在这个身份，Web 会把它导到账号页，概览接口对它返回 403。未来的导航必须按权限动态组合，“管理员 / 普通用户”二分法不够用。
6. **账号状态不止“健康 × 调度”两个维度。** 后端已经下发限流恢复时间、过载截止时间、临时不可调度原因与截止时间，移动端没有解码，原型也没有体现。巡检时最想知道的“什么时候恢复”在新方案里仍然缺失。
7. **对 iPad、Liquid Glass、触觉、数字和金额排版、原始英文枚举直出、“不可用”这个缺失值措辞，codex 要么一字未提，要么只有一句原则。** codex 甚至明确建议“缺失值显示不可用”，我认为这个建议本身就有问题。
8. **建议的处理方式**：采纳 codex 的诊断、问题清单、操作分级和任务链实施顺序。把“选 A/B/C”改为：先确定身份与 IA，再补画难点界面；并直接用 SwiftUI 加现有夹具（`isUITesting`）做原型，不再用 HTML 定稿。

---

## 1. 方案要点复述

| 层面 | codex 的主张 |
| --- | --- |
| 诊断 | SwiftUI 可以继续用；问题在于“日志像设置页、账号像属性清单、详情页像接口字段表”（ASSESSMENT.md:7） |
| 范围 | 本轮只做管理端；普通用户端作为未来约束（ASSESSMENT.md:9，DESIGN_BRIEF.md:5） |
| 问题清单 | 6 条 P1、6 条 P2，按任务影响排序，每条附源码行号（ASSESSMENT.md:31-44） |
| 信息架构 | 4 个 Tab：总览、账号、日志、管理。用户、分组、分析收进管理中心；站点设置改由顶部站点上下文进入，取消“设置”Tab（ASSESSMENT.md:50-59） |
| 页面改法 | 日志压缩头部、筛选可见、详情按“结果→上下文→费用→技术→关联”组织；账号分三层（身份 / 状态与调度 / 容量）、批量独立模式、详情先给当前问题与下一步；用户的资金操作独立；分组和分析分层（ASSESSMENT.md:65-95） |
| 设计系统 | 保留原生导航、Sheet、输入与可访问性；定制 12 个业务组件（StationContext … AsyncSectionState）；确认分级；“结果不明 → 待核对”（ASSESSMENT.md:97-105） |
| 实施 | 共 5 个阶段：先统一基础 → 日志到账号的任务链 → 账号工作流 → 管理与二级页 → 原生回归（ASSESSMENT.md:126-141） |
| 视觉方向 | A 紧凑工作台、B 清晰任务流、C 焦点工作区（深色）；推荐 A 的列表与 B 的详情组合（ASSESSMENT.md:143-151） |

---

## 2. 事实核查：ASSESSMENT 第 3 节问题清单

| # | 级别 | codex 论断（摘要） | 引用 | 结论 | 核查证据与补充 |
| --- | --- | --- | --- | --- | --- |
| 1 | P1 | 5 个 Tab 为概览、账号、用户、管理、设置；日志在“管理”里面 | `Sub2MobileApp.swift:34,47` | **属实** | `MainTabs` 位于 34-45 行，`ManagementView` 位于 47-61 行，日志入口在 51 行 |
| 2 | P1 | 日志按对象筛选时要手填用户、账号、分组、密钥 ID；模型精确匹配 | `RequestLogsView.swift:212` | **属实** | 212-218 行全部是 `TextField(... ID)`，217 行写着“模型（精确匹配）”。**补充**：统计分析的筛选也是手填 ID（`AnalyticsView.swift:199-201`），codex 没有列出 |
| 3 | P1 | 生效的筛选条件比列表回显的多 | `RequestLogsView.swift:48,212` | **属实，且更严重** | 回显只有账号、分组、模型三项（48-50 行）。用户、API Key、请求 ID、请求类型、状态码、处理状态、分类都不回显。**补充事实**：在“上游错误”模式下，编辑器拿到的初始值是剥离过的 `effectiveFilter`（95 行，剥离逻辑见 `RequestLogs.swift:44-47`），一点“应用”就把剥离后的值写回 `filter`（96 行）。也就是说，切到上游错误再改一次筛选，原来的用户、模型等条件会被**静默删除**。另外，任何一次“应用”都会把滚动 24 小时变成固定时间范围（96 行）。这是 `ADMIN_MODULES.md:11` 里写明的设计，但不符合直觉 |
| 4 | P1 | 选择模式下，点圆圈是选中，点整行仍会进入详情 | `AccountsView.swift:93` | **属实** | 93-99 行，圆圈按钮与 `NavigationLink` 并列。**补充**：超过 50 个后再点会被静默忽略，没有任何提示（256 行）；批量菜单放在列表顶部（78-87 行），不是底部操作条 |
| 5 | P1 | 用户详情串行读取资料、用量、密钥；用量失败时会显示“暂无 API Key” | `UsersView.swift:164,193` | **属实** | 193-204 行串行执行，用量抛错后 `loadKeys` 不会执行，164 行就显示“暂无 API Key”。**补充**：密钥加载失败与资料加载失败写进同一个 `error`（203、215 行），用户分不清是哪一块出错 |
| 6 | P1 | 普通保存、启用调度、创建用户都用了 destructive 确认 | `AccountEditView.swift:82` 等 | **属实，范围更大** | 全应用 10 个 `confirmationDialog` 的确认按钮**全部**是 `.destructive`：`AccountsView.swift:155,506`、`AccountEditView.swift:82`、`GroupsView.swift:223,392`、`UsersView.swift:187,346,490`、`SettingsView.swift:64,67` |
| 7 | P2 | 编辑页没有未保存草稿的退出保护 | `AccountEditView.swift:74,89`、`UsersView.swift:342` | **属实** | 74 行点“取消”直接 dismiss；89 行只在保存中禁止下滑关闭。`UsersView.swift:342`、`GroupsView.swift:388` 只在“结果不明”时才弹提示 |
| 8 | P2 | 账号行默认 8 个字段，以近似 caption 的样式流式排列 | `ListFields.swift:63`、`AccountsView.swift:197` | **属实，且有重复** | 默认字段同时包含“在用并发”和“容量”，而“容量”里又有“并发 x / y”（`AccountPresentation.swift:114-127`），同一个数字出现两次。平台和认证类型直接显示英文原值（`AccountPresentation.swift:73-74`），截图中可见“平台：anthropic　认证类型：oauth”（`…/AccountManagementUITests/EAAED920….png`） |
| 9 | P2 | 账号编辑把所有分组展开成一排 Toggle | `AccountEditView.swift:49` | **属实** | 49-53 行。Toggle 标题中的 `group.platform` 也是英文原值 |
| 10 | P2 | 账号、用户、分组详情先铺属性，后放操作 | `AccountsView.swift:419`、`UsersView.swift:135`、`GroupsView.swift:160` | **属实** | GroupsView 的 160 行是 `body` 起点，Section 在 162 行，误差可以接受。**补充**：详情页直接显示原始枚举，`account.platform/type/status`（`AccountsView.swift:421-423`）和 `user.role/status`（`UsersView.swift:138-139`）都是英文。列表里同样的字段已经翻成中文（`AccountPresentation.swift:85`、`UsersView.swift:84-85`），同一字段在两处显示不一致 |
| 11 | P2 | 概览用多张指标卡和多段解释承载统计口径 | `DashboardView.swift:297` | **属实（行号偏宽）** | 297 行是 `body` 起点。指标卡在 304-325 行；解释文案在 112、332、338、342、374 行等处 |
| 12 | P2 | 分析汇总把 Token、金额、时延逐行平铺 | `AnalyticsView.swift:40` | **属实** | 40-54 行，9 行 `LabeledValue` 加一条脚注 |

**其他论断**

- 第 2 节三张截图的描述**属实**。日志截图里，第一条记录出现在屏幕约 60% 的高度；账号截图里，8 个字段挤在 3 行灰色小字里；分组截图里，筛选区占据了上部。
- 第 7 节说普通用户需要先处理 `acceptLogin`、`verifyAdministrator` 和 `AppModel.connect` 的管理员限定，**属实**：`APIClient.swift:60-69,245-248`、`AppModel.swift:110`。

**小结**：codex 的事实层面没有出现“不属实”的条目。它的弱点在于对已发现的问题挖得还不够深（第 3、6、8、10 条），而不在准确性。

---

## 3. 优点：判断准确、值得吸收的部分

1. **重新定义了问题。** 把“原生 UI 很丑”拆成“容器错配 + 信息层级缺失 + 操作语义失真”，避免了“换框架或换 UIKit”这种高成本却打不中要害的方向。我同意这个判断，见第 5.7 节。
2. **问题清单可以验证。** 每条都有行号和影响说明，并且主动声明“难看”和“反人类”不能作为验收名称，改用首屏有效内容、筛选可见性、任务步骤数和误操作反馈来衡量（ASSESSMENT.md:46,137）。这套度量值得直接采用。
3. **把账号状态与调度状态分开**（ASSESSMENT.md:78、DESIGN_BRIEF.md:21）。这是账号列表最核心的信息架构修正。不过它还不完整，见第 4.2 节。
4. **操作分级加“待核对”结果态**（ASSESSMENT.md:105）。与现有代码里谨慎的写入安全工程（例如 `accountWriteFailure`，`AccountsView.swift:380-386`；余额幂等）一脉相承，没有为了好看牺牲正确性。
5. **按任务链实施**：日志 → 错误详情 → 关联账号 → 操作 → 结果 → 返回（ASSESSMENT.md:132）。这比按页面重画风险小，也更容易验收。
6. **尊重接口现实**：不虚构跨日志源的因果关系；名称选择器要先核对 API；不预先摆出“用户模式”这种空壳入口（ASSESSMENT.md:61-63,73）。
7. **业务组件清单**（StationContext、StatusBadge、MetricPair、AccountRow、LogRow、FilterSummary、ObjectPicker、DetailSection、BatchActionBar、ChangeSummary、OperationResult、AsyncSectionState）可以直接作为设计系统的起点。
8. **状态覆盖清单**（ASSESSMENT.md:139）：390pt、最大字号、长模型名、30+ 分组、50 项批量、过期快照、会话过期等。这份清单很专业。
9. **对验证边界坦诚**：反复声明 HTML 不等于原生验收（README.md:9、VERIFICATION.json `limitations`）。

---

## 4. 遗漏：codex 没有发现或没有重视的问题

### 4.1 身份模型漏掉了 vendor（代运营），而这决定未来的导航结构

- 【事实】移动端已经定义三种角色：`AdminUserRole { user, vendor, admin }`，其中 vendor 显示为“代运营”（`Sources/Sub2Core/UserManagement.swift:4-6`）。`docs/API_COMPATIBILITY.md:62` 写明角色只允许 `admin/user/vendor`，第 84 行写着“服务端先按工作区过滤”。
- 【事实】Web 端的落地规则是：普通用户进用户面板，站长进 `/admin/dashboard`，vendor 进自己权限档允许的第一个管理页，顺序为账号 → 分组 → 代理 → 用量。注释原文：管理端总览“页内多个端点对 vendor 是 403”（`sub2/frontend/src/router/landing.ts:1-35`）。权限档有 `account_manage / group_ops / group_billing / proxy_manage / monitor_view`。
- 【事实】codex 在 DESIGN_BRIEF.md:11 和 ASSESSMENT.md:63,120 只讨论了“管理员 / 普通用户”二分法。
- 【事实】vendor 当前登录时会看到“普通用户功能尚未开放”（`APIError.swift:17`），这句提示对 vendor 来说是错的。
- 【推断】影响：如果未来支持 vendor，“总览”就不能固定当第一个 Tab，“用户”也不该出现。所以 Tab 集合应当是**由权限推导出来的**，不能写死成 4 个。这也部分改变了对“管理中心”的评价，见第 5.3 节。

### 4.2 账号状态至少有三个维度，原型只画了两个

- 【事实】后端账号 DTO 下发 `rate_limited_at`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`、`temp_unschedulable_reason`、`expires_at`、`auto_pause_on_expired`（`sub2/backend/internal/handler/dto/types.go:230-243`）。
- 【事实】移动端的 `UpstreamAccount` 没有解码这些限时状态字段（`Models.swift:124-164`），但筛选面板里有“限流中”“临时不可调度”两个选项（`AccountsView.swift:216`）。也就是说能按这两种状态筛，却在行里显示不出来，更看不到何时恢复。
- 【事实】`account.errorMessage` 被解码了，但界面从不显示原文，只写“上游返回异常，点入查看错误日志”（`AccountsView.swift:207,425`）。原型里那句“凭据失效”的原因文字，在当前的数据契约下并没有来源。
- 【推断】巡检时最常问的是“这个号还能不能用、什么时候恢复”。状态模型应当是：管理状态（启用 / 禁用 / 错误）× 调度开关 × 限时运行状态（限流到几点、过载到几点、临时不可调度原因）× 有效期。这需要先在 Sub2Core 补字段，UI 才有内容可画。

### 4.3 原始英文枚举直接显示在界面上，不是“缺一本词典”这么简单

【事实】以下位置把后端原值直接显示给用户：

| 位置 | 原值示例 |
| --- | --- |
| `AccountPresentation.swift:73-74`（列表）、`AccountsView.swift:421-423`（详情） | `anthropic`、`oauth`、`apikey`、`active` |
| `UsersView.swift:138-139,161` | `admin`、`active`、密钥 `status` |
| `RequestLogsView.swift:133,319-320,328` | 错误的 `phase`、`type`（如 `upstream_error`）、`platform` |
| `RequestLogsView.swift:273` | 请求类型 `stream`（截图 `RequestLogsUITests/9A6FA137….png` 可见“类型 stream”） |
| `SettingsView.swift:46`、`LoginView.swift:162` | 余额操作 `add/subtract/set`（`BalanceOperation` 的 rawValue，见 `Models.swift:388`） |
| `AccountEditView.swift:51` | 分组 platform |

codex 只在第 10 条里写了一句“统一中文状态展示词典”，没有指出：**同一个字段，列表已翻译、详情没翻译**；日志错误的 phase、type 也没有中文。

### 4.4 “工程契约语言”是系统性问题，codex 的原型也沿用了这个习惯

- 【事实】`NativeApp/Features` 里有 **46 处**写成完整句子的静态说明文案（含句号），分布在 10 个视图文件中，例如：
  - 「请求记录按时间倒序。实际扣费与上游成本分别展示；按需翻页，无需等待全站总数。」（`RequestLogsView.swift:85`）
  - 「成本使用该记录保存的定价与账号倍率快照。金额按两位小数显示，不改变原始精度。」（同文件 283 行）
  - 「站点未返回此账号的在用 RPM……未提供时不以配置限额或零代替。」（`AccountsView.swift:440`）
  - 「原生 iOS 管理客户端。应用更新通过重新构建并签名 IPA 完成。」（`SettingsView.swift:57`）
  - 「操作编号：<UUID>」「核对并确认发送」「重试原请求」（`UsersView.swift:321-324,467`）
- 【推断】根源是这些文案几乎是从验收契约里逐句转写过来的。对照 `docs/ADMIN_MODULES.md:11,25` 的原文可以看出来。界面上的话应该说用户的业务，不应该说接口契约。
- 【事实】codex 只在概览一条里点到了这个问题。它的 DESIGN_BRIEF.md:27 要求“产品界面内避免解释实现原理”，但原型自己也放了不少说明块：A 有 12 处、B 有 7 处、C 有 10 处（含演示脚注）。例如 C 的「未返回的金额显示为“—”」「凭据状态与调度开关分开判断……」，A 的「状态与调度分别显示：正常账号也可以暂停调度」。
- 建议：建立文案规范。动词用业务词（“保存”“暂停调度”，而不是“确认发送”）；口径说明收进字段旁的 ⓘ 弹层或帮助页；UUID 只在“待核对”详情里提供复制，不放在主界面。

### 4.5 用“不可用”表示缺失值有歧义，codex 还明确推荐了它

- 【事实】代码里有 **42 处**“不可用”，分布在 9 个文件中。截图中的“在用并发：不可用”“调度 RPM 不可用 / 60”（`AccountManagementUITests/0FE95C0E….png`）就是例子。
- 【事实】ASSESSMENT.md:77 写的是“缺失值显示不可用”；三个原型却分别用了“—”（A、C）和“不可用”（B），彼此不一致。
- 【推断】在运维语境里，“并发不可用”很容易被读成“这个号的并发坏了”。它把“接口没返回”和“资源故障”混为一谈，对一款以巡检为核心的 App 是实打实的误导源。建议界面上用“—”，VoiceOver 读“未返回”；只有确实需要解释时，才在详情里写“站点未提供此数据”。

### 4.6 数字与金额排版

- 【事实】存在两套金额格式化函数：`Components.swift:4` 的 `money()` 直接拼接 Decimal 原值，可能显示成“$128.5”或很长的小数；`DashboardPresentation.money()` 固定两位小数（`DashboardPresentation.swift:53-56`）。用户列表用后者，用户详情和余额页用前者（`UsersView.swift:140,152,161,458`），同一个余额在两页显示不一样。
- 【事实】日志行的“扣费”和“成本”固定保留两位小数（`RequestLogsView.swift:122-123`）。【推断】低价模型单次请求的费用常常不到 1 美分，在列表里会一律显示成“$0.00”，这一列基本失去信息量。C 原型写成“$0.0024”，反而更合理。
- 【事实】每一条日志都显示带秒的完整日期，例如“2026年10月16日 16:12:00”（`RequestLogs.swift:204-207`）。没有“今天”分组，也没有相对时间。
- 【事实】请求行显示“用户 #8”（`RequestLogsView.swift:120`），而同一条记录已经带了 `userEmail`，详情页也在用（295 行）。
- 【事实】`monospacedDigit` 只在概览和性能趋势里用到，而日志、账号列表都开着 30 秒自动刷新，数字刷新时会左右跳动。图表柱顶标签写死为 10pt 等宽打字机字体（`DashboardView.swift:184`），不跟随 Dynamic Type。
- codex 只写了一句“数值用等宽数字”，没有覆盖以上具体问题。

### 4.7 颜色体系与品牌不一致

- 【事实】AppIcon 是青绿色底配白色 S（`Assets.xcassets/AppIcon.appiconset/icon-1024.png`），全局主色却是 `.tint(.indigo)`（`Sub2MobileApp.swift:43`）。概览柱状图是紫色或靛蓝渐变（`DashboardView.swift:181`），TPM 用品红（509 行），金额用绿色和橙色（`RequestLogsView.swift:122-123`，`AnalyticsView.swift:47-48`）。
- 【事实】概览卡片里，“实际费用”和“上游成本”只靠颜色区分（466-469 行），所以不得不再加一行图例：“绿色为实际费用，黄色为上游成本”（342 行）。
- 【推断】这正是“丑”的主要来源之一：至少 6 种色相，却没有一套语义。A 方向的深绿色恰好和图标一致，但 codex 没有把“主色回归品牌”作为一项明确结论写出来。

### 4.8 iPad 完全没有考虑

- 【事实】`TARGETED_DEVICE_FAMILY = "1,2"`（`project.pbxproj:74-75`），Info.plist 声明支持 iPad 全部方向。代码里没有任何 `horizontalSizeClass`、`NavigationSplitView` 或 `sidebarAdaptable`。codex 的文档对 iPad 的提及次数为 0，原型也只有 393pt 宽这一种。
- 【推断】日志和账号是最典型的“列表 + 详情”场景，iPad 横屏用 `NavigationSplitView` 收益最大。要么本轮把 iPad 列入“不支持”并在工程上收窄设备范围，要么在 IA 里给出 iPad 的布局。两者都比“不提”好。

### 4.9 Liquid Glass 时代的原生能力与 iOS 17 兜底

- 【事实】codex 的文档没有出现“Liquid Glass”或“玻璃”。三个原型都是扁平的网页底栏。实际 App 用新版 SDK 编译后，`TabView` 会自动变成浮动玻璃底栏（当前截图已是这样），原型里的底栏不代表用户最终看到的样子。
- 【事实】最低系统版本是 iOS 17（`IPHONEOS_DEPLOYMENT_TARGET = "17.0"`），所以同一套设计需要在 iOS 17/18 的不透明底栏和 iOS 26 的玻璃底栏下都成立。
- 【事实】从现有截图能看到两个具体问题：
  - 账号页右上角玻璃按钮“显示字段”（`line.3.horizontal.decrease`，`AccountsView.swift:139`）和列表里“筛选与排序”（`line.3.horizontal.decrease.circle`，69-70 行）几乎是同一个图标，干的却是两件事。
  - 品红色柱状图透过玻璃底栏，把整个底栏染红（`dashboard-polish/screenshots/dashboard-running-health.png`）。
- 【推断，有外部依据】按 Apple 的指引，Liquid Glass 属于浮在内容之上的导航和控件层，不应该铺进内容层（[WWDC25 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Design Group Lab 摘要](https://developer.apple.com/forums/thread/791070)）。对应的建议是：系统负责外壳（玻璃底栏和工具栏），业务卡片保持实底。还可以加上 iOS 26 的原生能力，并为 iOS 17 准备兜底：
  - `tabViewBottomAccessory`：放批量操作栏或“有 N 条待核对”提醒；iOS 17 退回 `safeAreaInset(edge: .bottom)`。
  - `tabBarMinimizeBehavior`：滚动长日志时收起底栏。
  - `Tab(role: .search)`：做全局查找，按请求 ID、用户邮箱、账号名搜索。
  - `toolbarTitleMenu`：做站点切换，比自绘顶栏更原生。
  - 参考：[Donny Wals: Tab bars on iOS 26](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)、[HWS: TabView accessory](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-a-tabview-accessory)

### 4.10 操作反馈与触觉

- 【事实】全项目没有用到 `sensoryFeedback` 或任何触觉 API（grep 结果为 0）。codex 只把“触觉”列为待验收项（ASSESSMENT.md:19）。
- 【事实】成功反馈的方式不统一：
  - 单账号暂停或启用调度成功后，只有字段值悄悄改变（`AccountsView.swift:577-581`）。
  - 编辑账号保存后直接关闭页面（`AccountEditView.swift:163`）。
  - 分组状态更新成功，结果写进页面最底部的“处理结果”区（`GroupsView.swift:215,269`），用户停在页面上方时看不到。
- 【事实】原型的写操作结果只是一条 toast。**批量结果在原型里反而退步了**：当前实现有逐项结果页（`AccountsView.swift:246-254`），A、B、C 都只显示“N 个账号已暂停调度”。
- 建议：成功用 `.success` 触觉加非阻塞提示；失败用 `.error` 加原位说明；“待核对”用持久的状态条，不能做成会自动消失的 toast。

### 4.11 没有利用原生交互词汇

- 【事实】swipe actions 只有“快捷编辑”一项（`AccountsView.swift:102-105`），暂停、启用调度和刷新凭据都没有放上去；codex 文档里“滑动”“长按”出现 0 次。
- 【推断】codex 提出的 P1 修法，在 SwiftUI 里都有现成的原生做法：
  - “选择模式下整行切换选中”就是 `List(selection:)` 加 `EditMode` 的默认行为，还附带双指滑动连选。
  - “每个生效筛选都变成可移除的标签”可以用 `searchable(text:tokens:)` 的 token 实现，或者在列表头部放一行筛选摘要。
  - 这说明问题出在原生能力**没用全**，并不是原生本身不行。

### 4.12 登录与首次启动

- 【事实】冷启动时先显示一个只有“正在恢复连接…”的 ProgressView（`Sub2MobileApp.swift:20-21`）。登录页要求先填“站点名称”再填地址（`LoginView.swift:107-108`），页头用的是 SF Symbol，不是 App 图标（100 行）。
- 【事实】登录流程本来就会请求 `GET /api/v1/settings/public`（`LoginView.swift:222`），后端在这个接口里返回 `site_name` 和 `site_logo`（`sub2/backend/internal/handler/setting_handler.go:71-72`、`dto/settings.go:399-400`）。移动端的 `PublicSettings` 只解码了验证码相关字段（`Models.swift:367-379`）。
- 【推断】站点名可以自动填好，站点 Logo 也可以直接作为 StationContext 的身份标识，不必用原型里的字母“S”。codex 对登录只给了“连接 → 认证 → 验证结果”这一条原则。

### 4.13 概览：异常项不能点

- 【事实】“运行健康”里的“异常账号 1”只是一个 `LabeledValue`，不能点击（`DashboardView.swift:370`），而且排在趋势图下面。页面上有“刷新费用 / 刷新趋势 / 刷新监控”三个手动按钮，外加下拉刷新、30 秒轮询和每个分区各自的“更新于”（338、351、362、399 行）。`AccountsView` 只支持按分组预置筛选（`init(initialGroupID:)`，61 行），无法从概览直接跳到“异常账号”。
- 【事实】概览不在 codex 重点展示的四屏之内，三版里的总览都只是 Tab 背后的简版。【推断】概览是现有代码量最大的页面（558 行），说明文案也最多，应当和日志一样被当作一等公民重新设计。

### 4.14 告警与推送

- codex 把推送、后台监控列为“不纳入本轮”（ASSESSMENT.md:122），这个判断合理。
- 【推断】但 IA 应当现在就定义“待处理事项”的数据模型，即哪些规则会产生一条待处理项，并把它作为将来推送深链的落点。三版原型的“需要关注”都是写死的演示数据，没有规则定义。

### 4.15 UITest 迁移成本

- 【事实】`UITests/` 共 1,617 行、35 个测试方法，大量按控件类型查询元素：`textFields` 25 次、`switches` 15 次、`segmentedControls` 6 次。例如日志筛选测试直接断言 `app.textFields["logs.filter.user"]`（`RequestLogsUITests.swift:37,42`）。
- 【推断】把 ID 输入框换成 ObjectPicker、把分段控件换成标签行，会直接打断这些测试。codex 提到了“保留 accessibility identifiers 的必要映射”，但只保留 ID 不够，测试必须随控件类型一起重写，阶段 2 和阶段 3 的工期应当把这部分算进去。

---

## 5. 存疑之处：可能有问题，或代价被低估的建议

### 5.1 把“用户”从一级 Tab 降级

- 【事实】codex 的依据是“日志比用户更常用”，它自己也承认“需以用户日常使用验证；必要时允许固定快捷入口”（ASSESSMENT.md:59）。
- 【事实】用户模块里有资金操作：余额调整，以及一整套跨站点持久化的“待确认余额”机制（`AppModel.swift:26,61,172`），还要在设置页和登录页单独展示。可见资金操作被当作高风险、高频的事。
- 【推断】对小型中转站来说，站外收款后手动给用户加余额可能是**每天都做**的移动端任务，频率未必低于翻日志。另外，iPhone 上的 SwiftUI `TabView` 不支持用户自定义固定哪些 Tab（`TabViewCustomization` 主要用于 iPad 侧栏），所以“固定快捷入口”需要自己实现，落地方式不明。
- 建议：在拿到使用频率之前，把下面三种方案并列画出来，让用户自己选：
  - 5 Tab：总览 / 账号 / 日志 / 用户 / 管理（设置收进站点标题菜单）
  - 4 Tab：codex 的方案
  - 4 Tab 加 iOS 26 搜索 Tab：用全局搜索直达用户和请求

### 5.2 取消“设置”Tab，改用顶部站点栏

- 【事实】App 支持多站点、多身份（`AppModel.profiles`，`SettingsView.swift:13-31`），切站本身就是一个高频动作。
- 【推断】A 原型在每一屏的大标题上方加了一条约 50pt 高的站点栏。这和它要解决的“首屏有效内容”目标相冲突，而且在 SwiftUI 里，大标题上方不是可以随便放内容的位置，只能借助 `safeAreaInset` 或自定义标题，和系统导航栏会互相打架。更原生的做法是在导航标题上挂 `toolbarTitleMenu` 做切站，或者放一个 leading 工具栏按钮。

### 5.3 “管理中心”会不会变成新的杂物抽屉

- 【事实】Web 管理端的路由超过 25 个，包括 ops、审计、工作区、结算、渠道、渠道定价、渠道监控、订阅、插件、公告、代理、兑换码、优惠码、设置、自定义、风控、Prompt 审计、用量、返利三页、订单三页（`sub2/frontend/src/router/index.ts:403-761`）。凡是不能当 Tab 的未来模块，都会流进“管理”。
- 【事实】A 原型的管理中心已经重复列出了“上游账号”和“请求日志”（`a.jsx` 中 `showManage`），而这两个本身就是一级 Tab。抽屉化在第一版就出现了。
- 【推断】需要事先定下收纳规则：管理中心只放不是 Tab 的对象；按“对象 / 财务 / 站点”最多分三组；每个模块在“原生 / 仅 Web”之间明确归类；vendor 身份按权限裁剪。没有这些规则，它注定会变成第二个“设置”页。

### 5.4 日志的默认形态：“全部来源”合并流的代价被低估

- 【事实】三种日志来自三个独立端点：`admin/usage`、`admin/ops/request-errors`、`admin/ops/upstream-errors`（`RequestLogs.swift:212-219`）。它们的筛选能力不同，分页和总数语义也不同：usage 用 `count_mode=deferred`，见 `RequestLogs.swift:78`。上游错误还包含“重试后已恢复”的请求（`RequestLogsView.swift:85`）。
- 【事实】A、C 的日志默认停在“全部来源”，B 默认是“全部”。codex 只在页脚注了一句“跨来源合并为概念演示”。
- 【推断】真要做成合并流，需要对三路分页做归并，要处理游标和去重，而且同一次请求可能同时出现在 usage 和 upstream-errors 两边，会被重复计数。在移动端做这件事成本很高，语义也说不清。更务实的做法：默认显示“失败请求”，或者只把两种错误源合并成“异常”视图；成功的请求记录作为第二选项。

### 5.5 B 方向按“需要处理 / 正常完成”分组

- 【推断】日志是分页的时间序列。按结果分组会打乱时间顺序；每加载一页，上方的“需要处理”组都会插入新行，已经读过的位置会跳动。这种组织方式更适合待办列表（B 借鉴 Things 3 正是因为这个），不适合日志。账号列表按“需要处理 / 正常”分组的问题小一些，但同样受分页影响。

### 5.6 跨 Tab 跳转破坏返回栈，与 codex 自己的原则相反

- 【事实】在 B、C 原型里，从账号详情点“关联日志”，会**切到日志 Tab**，并把账号名填进搜索框（`b.jsx` AccountDetail 中的 `setTab('logs');setLogSearch(a.name)`；`c.jsx` 中的 `setLogSearch(...);go('logs')`）。A 原型从日志详情点用户，会跳到管理 Tab 的用户列表，而不是这个用户的详情。
- 【事实】当前实现是在同一个 NavigationStack 里 push 一个 `RequestLogsView(accountID:)`（`AccountsView.swift:484`），返回时能回到账号。日志接口按 `account_id` 过滤，并不支持按名称模糊搜索。
- 结论：这一点原型是在**倒退**，违背了 ASSESSMENT.md:61 的“返回保留上下文”。

### 5.7 “A 列表 + B 详情”的组合是不是折中

- 【推断】因为三版 IA 相同，组合起来很容易，所以这个推荐并不是在两种 IA 之间和稀泥，只是在两种密度和两种详情排版之间各取一半。我不反对组合本身，问题在于真正的分歧点没有被拿出来比较：IA、错误分类与措辞、缺失值、筛选模型。
- 【事实】A 的“紧凑”在相当程度上靠小字号：a.css 里 `font-size:12px` 出现 52 次，正文多为 14px，而 iOS 默认 body 是 17pt。在 Dynamic Type 默认档下照搬，行高会变大，“紧凑”的优势会明显缩水。如果硬保密度，只能大量用 `.caption`，又回到了 codex 批评现状的“灰色小字流”。真正有效的手段是**减少每行字段数，并把数字右对齐成列**，而不是缩小字号。

### 5.8 首屏有效内容：只有 B 有明显改善，C 反而更差

以下是从截图估算的“第一条日志出现的位置”占可视区高度的比例，只是粗略的视觉估算：

| 版本 | 约值 | 依据 |
| --- | --- | --- |
| 现状（固定范围状态） | ≈60% | `RequestLogsUITests/E1C59092….png` |
| A | ≈46% | `screenshots/a-log.png` |
| B | ≈40% | `screenshots/b-log.png` |
| C | ≈66% | `screenshots/c-log.png`；顶部的“2 条失败记录”汇总卡、来源标签、搜索框和快筛叠在一起 |

codex 把“默认字号下无需先滚过多段说明才见首条记录”列为验收目标（ASSESSMENT.md:137），C 达不到这个目标；而且上面的数字还是在网页小字号下测得的。

### 5.9 VERIFICATION 的“PASS”有盲区

- 【事实】VERIFICATION.json 记录“no horizontal overflow”为通过，但 `a-log.png` 里第四个来源标签“上游错误”被截断。来源条用的是 `overflowX:auto`，溢出被滚动容器藏住了，所以检测不到。
- 【推断】4 个中文分段在 393pt 宽、默认字号下已经放不下，到了大字号必然出问题。
- 【事实】“PASS”只说明原型脚本能点通，codex 自己也在 `limitations` 里写明了这一点。用户读到时需要知道，它不代表设计通过了验证。

### 5.10 三个版本的错误分类彼此矛盾，“同内容对比”并不同内容

- 【事实】同一条 14:32 的 504 超时：A 归为“上游错误 / 上游响应超时”，B 是“客户端失败 · 超时 504”，C 是“客户端失败 TIMEOUT”。同一条 14:30 的 429：A 是“客户端失败 / 客户端请求被限流”，B 和 C 是“上游错误”。
- 【事实】同一个账号动作：A、B 叫“刷新凭据”，C 叫“重新验证”。后者没有对应的 API，实际只有刷新凭据（`refreshAccount`）和测试（`testAccount`）。C 连“保存站点显示名称”这种本地偏好都要弹确认，和 codex 自己的确认分级原则矛盾。
- 【推断】这说明错误分类和动作措辞**还没有设计**。它们本应是三版共用的前置约定，现在却在不同版本里被随手写成了不同的样子。

---

## 6. 三个方向的实质差异评估

### 6.1 差异在哪一层

| 维度 | A 紧凑工作台 | B 清晰任务流 | C 焦点工作区 | 是否实质差异 |
| --- | --- | --- | --- | --- |
| 一级导航 | 总览 / 账号 / 日志 / 管理 | 相同 | 相同 | 否 |
| 管理中心条目 | 用户、分组、（账号、日志）、分析、站点 | 用户、分组、分析、日志、站点 | 用户、分组、分析、站点 | 否（A 多了重复项） |
| 日志列表组织 | 时间序，左侧时间和状态码列 | **按结果分组的卡片** | 汇总卡加时间序 | B 是结构性差异，但不适合日志（5.5） |
| 账号列表 | 表头 + 三列（状态 / 并发 / 调度） | 分组卡片，状态和调度标签 | 三格汇总数 + 两列 | 主要是密度不同；C 的汇总数可当筛选入口，值得吸收 |
| 账号详情 | 健康横幅 → 三格指标 → 主按钮 → 属性表 | 行动卡 → 容量 → 操作列表 → 折叠属性 | 焦点卡 → 容量条 → 两个大按钮 → 链接 | 顺序相同（状态 → 容量 → 动作 → 其余），只是排版不同 |
| 写操作确认 | Sheet：站点 / 对象 / 影响 / 主按钮 / 取消 | 相同 | 相同 | 否 |
| 主题 | 浅色，深绿 | 暖白，蓝 | 深色，青绿配琥珀 | 皮肤 |

**结论**：三版大约九成共享同一套 IA、同一种详情顺序和同一个确认模型，差别集中在密度、分组方式和配色。所以这实际上是在选皮肤和密度，不是在选方向。B 的“按结果分组”和 C 的“汇总卡”是仅有的结构性差异，各有缺陷或局限，见 5.5 和 5.8。

### 6.2 四屏是否覆盖了用户最痛的地方

| 痛点（用户和 codex 已确认的范围） | 原型覆盖情况 |
| --- | --- |
| 日志列表与详情 | ✓ |
| **日志对象筛选**（codex 的 P1 第 2、3 条） | ✗ A 只有“时间范围 + 仅看异常”；B 只有一行摘要；C 的日志没有筛选面板。没有 ObjectPicker，也没有可移除的筛选标签 |
| 账号列表、快筛、选择 | ✓（A、B、C 的选择模式都改成了整行切换，对应 P1 第 4 条） |
| 账号详情 | ✓ |
| 批量逐项结果 | ✗ 只有一条 toast（相对现状是退步） |
| **账号编辑表单**（P2 第 7、9 条） | ✗ A 只有一张只读的“基础设置”表 |
| 账号测试（SSE 流式输出） | ✗ B 用 toast 代替 |
| 用户详情、密钥分区加载、**余额调整** | ✗ 或极薄（B 有一页简版用户详情） |
| 分组详情、分析 | 极薄 |
| 结果不明 / 待核对、加载、失败、空状态 | ✗ 原型里没有任何加载、重试或待核对状态（grep 结果为 0） |
| 登录、站点切换 | ✗ 或极薄 |

结论：原型选的是最容易画得好看的四屏，最反人类的表单、筛选和异常态全部没有触及。

### 6.3 从原型到 SwiftUI 的落差

| 原型做法 | SwiftUI 实际情况 | 难度与建议 |
| --- | --- | --- |
| 自绘扁平底栏 | 系统 `TabView`，iOS 26 自动变为玻璃浮动底栏 | 不要复刻，接受系统外观 |
| 大标题上方的站点栏或 eyebrow | 大标题由系统管理，上方没有合适位置 | 改用 `toolbarTitleMenu` 或 leading 按钮 |
| 正文 14px、辅助文字 12px | 默认 body 17pt，并要支持 Dynamic Type | 密度会下降；应靠减少字段和列对齐来补 |
| 跨行对齐的列（A） | List 行之间无法共享列宽 | 固定列宽，并用 `ViewThatFits` 在大字号下退化为堆叠布局 |
| 卡片式分组（B） | List 里可以靠 `listRowBackground` 和间距实现；改用 ScrollView 会失去 swipe 和编辑模式 | 建议继续用 List |
| 自绘确认 Sheet（结构化内容） | `confirmationDialog` 只能放纯文本 | 用 `.sheet` + `presentationDetents([.medium])`；可行 |
| toast | 没有原生组件 | 自建 overlay；iOS 26 可用 `tabViewBottomAccessory` 承载持久状态 |
| 筛选标签 | `searchable` tokens 或自建标签行 | 可行 |
| 只有深色（C） | 必须补一套同等质量的浅色；玻璃在深色下对比度不同 | 工作量翻倍 |
| 来源合并流 | 不是 UI 问题，是数据层问题 | 见 5.4 |

---

## 7. 总评：如果我是用户

**会采纳**

1. 诊断结论：继续用 SwiftUI；容器错配是根本问题。
2. 12 条问题清单，P1 优先，加上本文第 2 节的补充事实，尤其是“上游模式静默丢弃筛选条件”和“全部确认都用 destructive”。
3. 操作分级、“待核对”结果态、按任务链实施，以及 ASSESSMENT.md:137-139 的验收度量和状态覆盖清单。
4. 账号状态与调度分开展示；B 的详情顺序“当前问题 → 下一步”；C 的“账号池汇总数兼作快筛”。
5. 业务组件清单，作为设计系统的骨架。

**会补充**

1. **身份与权限模型**：加入 vendor，并按权限推导 Tab 集合（4.1）。
2. **账号状态模型**：补齐限时运行状态和恢复时间、有效期，以及经过处理、可以展示的错误原因；先改 Sub2Core，再改 UI（4.2）。
3. **文案规范**：枚举中文词典且列表和详情统一；动词用业务词；禁止在界面上写契约脚注；缺失值改用“—”（4.3-4.5）。
4. **数字和金额规范**：只保留一套格式化函数；小额自适应精度；列表时间相对化并按日期分组；数字统一等宽（4.6）。
5. **颜色系统**：主色回归图标的青绿；金额与状态色要有语义；不靠颜色单独传达信息（4.7）。
6. **平台层面**：明确 iPad 是支持还是不支持；Liquid Glass 只用在外壳层；按 iOS 26 能力加 iOS 17 兜底来设计（4.8、4.9）。
7. **原生交互**：`List(selection:)` 编辑模式、swipe actions、searchable tokens、`sensoryFeedback`（4.10、4.11）。
8. **概览**：“待处理事项”要有规则模型，异常项可以直接跳到预置筛选（4.13、4.14）。
9. **UITest 重写**的工期纳入计划（4.15）。

**会要求改变的做法**

- 不再在 A、B、C 三套皮肤之间选。先让用户决定 IA，把 5.1 里的三种 Tab 方案并列；再决定日志的默认形态（5.4）。
- 第二轮原型必须覆盖难点界面：日志筛选的 ObjectPicker、账号编辑、余额调整、批量逐项结果、待核对、加载与失败、登录和切站。
- 第二轮原型改用 **SwiftUI 加现有夹具**（`model.isUITesting` 的数据路径已经存在）。这样默认字号、Dynamic Type、玻璃底栏和深浅色都是真实效果，HTML 原型无法验证这些。

---

## 参考来源

- Apple WWDC25《Meet Liquid Glass》：https://developer.apple.com/videos/play/wwdc2025/219/
- Apple Developer Forums，WWDC25 Design Group Lab 摘要：https://developer.apple.com/forums/thread/791070
- Donny Wals, Exploring tab bars on iOS 26 with Liquid Glass：https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/
- Hacking with Swift, How to add a TabView accessory：https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-a-tabview-accessory
- Apple HIG Tab bars（codex 原引用）：https://developer.apple.com/design/human-interface-guidelines/tab-bars

注：`toolbarTitleMenu`（iOS 16+）、`sensoryFeedback`（iOS 17+）、`sidebarAdaptable`（iOS 18+）的版本要求来自已有知识，没有逐一在官方文档上核对，实施前请核对。
