# 13 · 结构方案 N：Native-maximalist ——“如果 Apple 自己来做这个 App”

> 日期：2026-10-16 · 基线 `7ccd542`（分支 `codex/native-ios-rebuild`）· 最低部署 iOS 26（iOS 27 能力用 `#available` 渐进增强）
> 输入：`research/00-brief.md`（最高优先级）、`01-current-ui-audit.md`、`02-backend-capability-map.md`、`03-reference-patterns.md`、`04-sibling-clients.md`、`05-codex-critique.md`；源码 `Sources/Sub2Core`、`NativeApp`；后端 `G:/weixinProject/sub2`（`40bee5d2e`）。
> 引用写法：`01 §2.4` 表示审计文档第 2.4 节；`02 §1.2` 表示能力盘点第 1.2 节；`03 P12` 表示模式库第 12 条；`04 §4.1#7` 表示对照表第 7 行。
> 本文只做结构设计。凡是需要新接入的接口，都已在 02 中确认存在，并在第 9 节列出。没有写入任何后端不存在的能力（例如推送）。

---

## 0. 一页摘要

| 维度 | 本方案的决定 |
|---|---|
| 核心范式 | 外壳完全交给系统；内容层换成 Apple 数据类 App 的三种容器：**结论先行的摘要卡**（健康/天气）、**状态先行的三行列表**（邮件）、**英雄状态卡 + 少量属性的对象页**（查找/钱包）。表单只用于录入。 |
| 底部 Tab（admin） | `摘要 · 账号 · 用户 · 监控` 加独立的 `Tab(role: .search)`。“监控”只在站点开启渠道监控或运维监控时出现。取消“管理”和“设置”两个 Tab。 |
| 日志 | 不占 Tab。入口有四个：搜索 Tab 的“浏览”目录（2 次点击）、对象详情的“相关错误/请求”、摘要的“未处理错误”、搜索框直接粘贴请求 ID。 |
| 站点切换 | 每个 Tab 根页右上角放站点头像，做法同 App Store 的账户头像。点按打开“站点”面板，长按出现快速切换菜单。站点名放在 `navigationSubtitle` 里常驻显示。 |
| 低频模块 | 放进搜索 Tab 空闲时显示的“浏览”目录，按 排障 / 资源 / 经营 / 在 Web 后台 四类收纳。目录只收录不是 Tab、本轮已原生实现、且当前角色和站点开关都允许的模块。 |
| 语义层 | 在 Sub2Core 建一份唯一的语义词典：状态 → 文案 / 色调 / 符号 / 优先级 / 恢复动作。界面只引用词典，契约由单元测试保证。 |
| 操作 | 确认分四级：即时 / 确认 / 警示 / 验证。成功用 toast 加触觉，可撤销的操作提供“撤销”和 UndoManager。失败在原位提示。结果不明一律常驻显示为“待核对”。同一时间只出现一个 sheet，二次验证改用带输入框的 alert。 |
| iPad | 本轮用 `.sidebarAdaptable` 配合各 Tab 内的 `NavigationSplitView`，保证能用。深度适配（`Table`、`inspector`、多窗口）留到后期。 |

---

## 1. 核心主张

### 1.1 一句话

**系统外壳一处不改；内容层按“指标 / 对象集合 / 单个对象 / 录入”四种内容类型选用 Apple 自家数据类 App 已验证的容器；所有业务语义下沉到 Sub2Core 的一份语义词典里，界面上不再出现任何解释句。**

### 1.2 为什么能根治 R1–R6

| 根因（00 §2） | 现状的症状 | 本方案的结构性解法 | 只换 List 样式为什么不够 |
|---|---|---|---|
| **R1** 用设置页范式承载数据 | 全部是 insetGrouped + 键值行，值是灰色；iOS 26 行高变大后更稀（01 §4 R1，03 §1.3） | **由内容类型决定容器**：指标用 `ScrollView` 摘要卡（健康“摘要”）；对象集合用 `.plain` 列表的三行行（邮件）；单个对象用英雄状态卡 + 不超过 6 行的属性分区（查找/钱包）；`Form` 只用于编辑和金额录入。属性行把**值**设为主色，标签设为次要色。列表页标题用 `.toolbarTitleDisplayMode(.inlineLarge)`，收回大标题约 19% 的首屏占用（01 D41）。 | 换样式改变不了“每个字段一行、操作沉底”的结构。必须改容器，改首屏放什么。 |
| **R2** 界面被当作验收面板 | 60 多条契约原句、185 个标识、UITest 直接断言文案（01 §4 R2） | 界面**零说明**：契约改由 Sub2Core 单元测试和展示层测试保证（§12.4）；口径解释只放进字段旁的 ⓘ 弹层（`TermInfoButton`）；全部文案进 String Catalog，并用禁用词测试防止回流；accessibilityIdentifier 只挂在交互元素和数据容器上。 | 文案一旦被测试断言，就会被“保护”下来。必须先把断言迁走，界面上的说明才能删干净。 |
| **R3** 无语义层 | 原始英文枚举直接显示、“不可用”42 处、6 种以上色相、确认按钮全红（01 §4 R3/R8） | `Glossary` 与 `AccountConditionModel` 进入 Sub2Core：每个后端枚举对应中文文案、5 种色调（正常 / 注意 / 严重 / 中性 / 特殊）、形状不同的 SF Symbol、优先级、可执行的恢复动作。缺失值统一显示“—”，VoiceOver 读作“未返回”。平台不用颜色区分，把颜色留给状态（§附录 A）。 | 没有词典，每个页面会各翻译一次，必然出现漂移（04 §5）。 |
| **R4** 数据层缺口 | 限时运行状态未解码，恢复动作未接入（02 §6.1） | 第 9 节列出 P0 数据依赖，阶段 0 先补数据。界面设计以这些字段为前提，例如倒计时和“恢复状态”主按钮。 | 字段不到位，“限流中 · 3:58 后恢复”画出来也没有数据可填。 |
| **R5** 信息架构碎片化 | 日志藏在目录页、统计分析有 4 个入口、筛选要手输 ID、“异常账号 1”不能点、切站只在设置里（01 §4 R7） | 4 + 1 个 Tab 由角色和开关推导；**搜索即浏览**；对象中心化，跨对象跳转在当前栈内 push，并对重复路由去重；用 Token 加联想替代 ID 输入；所有计数都能点进对应列表。 | 这是导航结构问题，与样式无关。 |
| **R6** 操作语义失当 | 10 个确认全部是 destructive、有 3 种提交范式、成功结果写成常驻分区、sheet 套 sheet、没有触觉（01 §4 R6，05 §4.10） | 四级确认（§5.2）；统一的 `WriteCoordinator` 加两种提交范式（工具栏“保存” / 金额页主按钮）；`FeedbackCenter` 统一 toast、触觉和撤销；“待核对”常驻；单 sheet 规则；二次验证改用 alert。 | 这是交互状态机问题，需要统一组件来承载。 |

### 1.3 “Apple 会怎么做”的参照分工

| Apple App | 借用的范式 | 落点 |
|---|---|---|
| 健康 | “摘要 / 浏览”二分；摘要卡标题、更新时间加下钻箭头；指标详情页“日/周/月”分段，选中的数值显示在头部 | 摘要 Tab、浏览目录、统计分析 |
| 天气 | 结论先行（每张卡第一行是一句话）、地点列表卡片、24 段时间条 | 摘要卡标题、监控 Tab 的渠道卡 |
| 股市 | 顶部大数加涨跌幅，下面是迷你图 | 今日收入卡 |
| 邮件 | 三行行（发件人 / 主题 / 摘要，右上角时间）、按日分节、选择模式加底部工具条、滑动与长按菜单、“只看此发件人” | 账号行、日志行、批量、日志 Token |
| 提醒事项 | 根页的智能列表计数网格（今天 / 计划 / 全部 / 旗标） | 账号 Tab 根页的状态卡 |
| 钱包 / Apple Cash | 大金额输入、交易明细（金额大字 + 分组属性）、最新交易预览 | 充值/退款、余额记录、请求详情 |
| 查找 | 对象头部状态加大按钮操作 | 账号详情的英雄状态卡 |
| 屏幕使用时间 | 排名加横条占比 | 模型 / 分组排名 |
| App Store / 音乐 | 右上角账户头像打开账户面板；搜索 Tab 空闲时显示“浏览类别” | 站点面板、浏览目录 |
| App Store Connect | 分区标题右侧“计数 ›”，只预览前几条 | 用户详情的 Key / 余额记录 |

---

## 2. 信息架构

### 2.1 底部 Tab（admin，本轮）

```
┌─────────────────────────────────────────────────────┐
│  [▦ 摘要]  [⛁ 账号]  [👥 用户]  [〰 监控]      ( 🔍 ) │  ← iOS 26 玻璃 Tab 栏 + 独立搜索按钮
└─────────────────────────────────────────────────────┘
```

| Tab | 根页面 | 为什么是 Tab | 显示条件 |
|---|---|---|---|
| 摘要 `rectangle.3.group` | `SummaryView`：需要处理 → 今日收入 → 用量 / 实时 → 渠道 | 用户确认的高频任务“早晚看营收和用量”，以及救火入口 | 恒有 |
| 账号 `server.rack` | `AccountsHomeView`：提醒事项式状态卡网格 + 全部 + 按分组 | 高频任务“救火：看账号异常/限流” | 恒有 |
| 用户 `person.2` | `UsersView`：最近处理 + 全部用户（搜索栏常驻） | 高频任务“给用户充值/退款”（00 §1；05 §5.1 反对把用户降级） | 恒有 |
| 监控 `waveform.path.ecg` | `MonitorView`：服务健康（运维）+ 渠道卡列表 | 高频任务“看渠道监控” | `channel_monitor_enabled == true` 或 `ops_monitoring_enabled == true` |
| 搜索（`Tab(role: .search)`） | `BrowseView`：空闲时是“最近查看 + 浏览目录”，输入后是跨对象结果 | 解决“先猜对它在哪个 Tab”（03 §1.1），同时给日志和低频模块一个稳定的家 | 恒有 |

**关于 `Tab(role: .search)`：采用。**
- 理由：App Store、音乐、TV 在 iOS 26 都用 4 个 Tab 加 1 个搜索 Tab，搜索 Tab 空闲时展示可浏览的类别。这正好对应“搜索即浏览”。
- 激活方式保持 `.automatic`，不加 `.tabViewSearchActivation(.searchTabSelection)`。原因是我们希望先看到目录，用户点了搜索框才弹出键盘。03 §1.1 记录了 iOS 27.2 上的行为：不加该修饰符时，搜索 Tab 会退化为普通内联 Tab，导航栏里出现搜索栏。这个外观对“浏览优先”反而合适。原型阶段要在 iOS 26.x 和 27.2 上各截一张图确认。
- Tab 徽标只用于关键信息（03 §1.1）：只在“账号”上显示 `.badge(错误数 + 过载数)`，限流不计入，因为它会自动恢复。

**被取消的 Tab**
- “管理”：本身只是一个目录页（01 §2.12），内容并入浏览目录。
- “设置”：站点切换、偏好和退出登录收进站点面板（§4.16），做法同 App Store / 音乐的账户面板。

### 2.2 Tab 由“角色 + 站点功能开关”推导

**能力模型（Sub2Core，新增）**

```swift
public enum StationRole: Sendable, Equatable { case admin, vendor(Set<VendorPermission>), user }
public enum VendorPermission: String, Sendable { case accountManage = "account_manage", groupOps = "group_ops",
                                                 groupBilling = "group_billing", proxyManage = "proxy_manage", monitorView = "monitor_view" }
public enum FlagState: Sendable, Equatable { case on, off, unknown }
public enum ChannelMonitorMode: Sendable, Equatable { case off, v1, v2 }
public struct Capabilities: Sendable, Equatable {
    public var role: StationRole
    public var opsMonitoring: FlagState        // GET admin/settings → ops_monitoring_enabled（只解码这一个字段）
    public var channelMonitor: ChannelMonitorMode // GET settings/public → channel_monitor_enabled + channel_monitor_mode
    public var payment, subscription, riskControl, affiliate: Bool // GET settings/public
}
public enum AppTab: String, Hashable, Sendable { case summary, accounts, users, monitor, groups, usage, search, home, keys, me }
public enum ShellLayout { public static func tabs(for c: Capabilities) -> [AppTab] }   // 纯函数，单元测试覆盖
```

数据来源（都已在 02 中确认）：
- 角色：Admin Key 登录时视为 admin；令牌登录读 `auth/me.role`（02 §3.2）。
- vendor 权限档：`GET admin/workspaces/me`（02 §1.2 工作区）。
- 站点开关：`GET settings/public` 中的 `channel_monitor_enabled / channel_monitor_mode / payment_enabled / subscription_enabled / risk_control_enabled / affiliate_enabled / site_name / site_logo`（后端 `dto/settings.go:399-457`）。
- 运维开关：`ops_monitoring_enabled` 来自 `GET admin/settings`（`dto/settings.go:190`），只有 admin 能读到；vendor 一律视为 `.off`（02 §1.6）。

推导规则：

| 角色 | Tab 集合（按顺序） | 落地页 |
|---|---|---|
| **admin（本轮）** | 摘要 · 账号 · 用户 ·（监控：`channelMonitor != .off` 或 `opsMonitoring == .on`）· 搜索 | 摘要 |
| **vendor（以后）** | （账号：`accountManage`）·（分组：`groupOps` 或 `groupBilling`）· 用量（即日志，vendor 可访问 usage）·（监控：`monitorView` 且渠道监控开启）· 搜索。没有摘要（`dashboard/stats` 对 vendor 返回 403），也没有用户（02 §1.6）。代理（`proxyManage`）放在浏览目录里 | 第一个 Tab，与 Web 的落地顺序“账号 → 分组 → 代理 → 用量”一致（05 §4.1） |
| **普通用户（以后）** | 首页（余额、今日消费、订阅进度）· 密钥 · 用量 ·（状态：渠道监控开启时）· 我的。不设搜索 Tab，因为对象很少 | 首页 |

推导时机与稳定性：
1. 连接站点时（`AppModel.connect` 成功后）并行拉取能力，3 秒超时。超时就用该站点上次缓存的能力（按 profile 存在 `UserDefaults`），从未拉取过的站点按 `.off` 处理。拿到结果后再展示主界面，避免 Tab 闪烁。
2. Tab 集合**只在会话建立时计算**，同一会话内不增减（HIG：“Don't disable or hide tab buttons”针对的是临时空状态）。如果会话中途某个功能被关闭，接口会返回禁用错误，对应页面显示“站点未开启该功能”状态（§6），下一次建立会话时该 Tab 再消失。
3. 切换站点后，如果当前选中的 Tab 在新站点中不存在，回落到落地页，并显示 toast“已切换到 备用站”。

### 2.3 各 Tab 根页面一览

```
摘要  ─ SummaryView（ScrollView + 卡片）
账号  ─ AccountsHomeView（List.insetGrouped：状态卡网格 / 全部 / 按分组）
        └ 搜索时就地换成 plain 结果列表
用户  ─ UsersView（List.plain：最近处理 / 全部用户；搜索栏常驻）
监控  ─ MonitorView（ScrollView：服务健康卡 + 渠道卡列表）
搜索  ─ BrowseView（空闲：最近查看 + 浏览目录；输入：分组结果，带范围切换）
```

### 2.4 站点切换放在哪里

- **位置**：每个 Tab 根页的 `ToolbarItem(placement: .topBarTrailing)` 上放 `SiteAvatarButton`。头像优先用站点的 `site_logo`，没有就用站点名首字母组成的圆形徽标。做法同 App Store / 音乐 / TV 的账户头像。
- **常驻上下文**：根页 `.navigationSubtitle("OpenAI 中转站 · 2 分钟前")`（iOS 26）。进入二级页后，系统返回按钮上方不再重复显示站点；写操作的确认文案里会写站点名（§5.2）。
- **交互**：`Menu(content:label:primaryAction:)`。**点按**打开“站点”面板 sheet（§4.16）；**长按**弹出快速切换菜单，列出其他站点和“添加站点…”。
- **切换守卫**：如果 `WriteCoordinator.hasInflight` 为真，切换会被阻止，并弹出 alert“有操作正在提交，完成后再切换站点”。存在待核对项时**不阻止**切换，因为待核对记录本来就按站点保存（`PendingBalanceOperation.serverID`）。
- 不使用 `toolbarTitleMenu`：标题位置要留给页面名称，而且大标题与标题菜单的组合在 iOS 26 上的表现需要另外验证（05 §5.2）。

### 2.5 低频模块的收纳：浏览目录（搜索 Tab 空闲态）

**收纳规则（写进 `AppModule` 注册表，代码评审时逐条检查）**
1. 目录只收录**不是 Tab** 的模块，任何对象都不在目录和 Tab 中重复出现（05 §5.3 指出 codex 原型重复列了账号和日志）。
2. 模块出现的三个前提：角色允许、站点开关开启、本轮已原生实现。**还没实现的模块不出现**，不放空壳入口（00 §3.7）。
3. 固定 4 个分类：**排障 / 资源 / 经营 / 在 Web 后台**。新模块必须声明分类和可用性，才能出现在目录里。
4. **作用于某个对象的模块不进目录**，而是挂在对象详情里。例如订阅挂在用户或分组详情下，API Key 和余额记录挂在用户详情下，定时测试结果挂在账号详情下。
5. 目录行只有符号、名称，以及可选的**关键计数**（目前只有“告警触发中 n”），不写描述。
6. “在 Web 后台”分类只放精选的配置入口，用 `arrow.up.forward.app` 表示外链，用 `openURL` 打开站点后台对应路径。

**模块清单**

| 模块 | 分类 | 条件 | 本轮形态 | 依据 |
|---|---|---|---|---|
| 日志（错误请求 / 用量明细 / 上游错误） | 排障 | admin、vendor | **原生** | 00 §1 用户原话 |
| 告警事件 | 排障 | admin 且运维开启 | **原生**（P1 数据） | 02 §1.1 告警、§3.8 |
| 分组 | 资源 | admin；vendor 按权限 | **原生**（admin 放在目录，vendor 是 Tab） | 01 §2.15 |
| 代理 | 资源 | admin；vendor `proxyManage` | 后续，本轮不显示 | 02 §6.2 B |
| 统计分析 | 经营 | admin | **原生**（唯一入口，另有对象详情里的“统计分析”作用域入口） | 01 D23 |
| 订单与退款申请 | 经营 | `payment_enabled` | 后续 | 02 §1.3 |
| 兑换码 / 公告 / 风控 / 操作审计 | 经营 / 资源 | 各自开关 | 后续 | 02 §6.2 B |
| 系统设置、告警规则、渠道定价、支付配置 | 在 Web 后台 | admin | **外链** | 02 §6.2 D |
| 备份、插件、系统更新、账号导入导出与 OAuth 授权、错误透传、TLS 指纹、分组计费/路由/白名单 | — | — | **只在 Web**，目录里不列，在相关对象页按需提供“在 Web 中打开” | 02 §6.2 D |

### 2.6 导航图

```
RootView
├─ [未登录] SiteOnboarding（NavigationStack）
│   ├─ 已保存站点列表（有站点时放在最前）
│   ├─ 站点地址 → 公开设置 → 登录方式 → 两步验证
│   └─ 验证码 sheet（CaptchaView，复用）
└─ [已登录] RootTabs（TabView + Tab API + .sidebarAdaptable）
    ├─ 摘要 NavigationStack(path)
    │   SummaryView ─push→ AccountList(scope) / AlertList / Logs(query) / Channel(ref) / Analytics(query) / PendingList
    ├─ 账号 NavigationStack(path)
    │   AccountsHomeView ─push→ AccountList(scope) ─push→ AccountDetail ─push→ Logs / Analytics / GroupDetail
    ├─ 用户 NavigationStack(path)
    │   UsersView ─push→ UserDetail ─push→ BalanceHistory / UserKeys / Logs / Analytics
    ├─ 监控 NavigationStack(path)
    │   MonitorView ─push→ ChannelDetail / AlertList ─push→ Logs / AccountList(group)
    └─ 搜索 NavigationStack(path)
        BrowseView ─push→ Logs / AlertList / GroupList / Analytics / 任意对象详情
   全局：SiteSheet（sheet）· StepUpPresenter（alert）· FeedbackCenter（toast 覆盖层）
         · PendingAccessory（tabViewBottomAccessory，iOS 26.1+）
```

- 所有 push 都使用值路由 `Route`（§5.7），并做去重，从结构上消除 01 §1 发现的“无限压栈环”。

---

## 3. 高频任务的完整路径与点击步数

计数口径：点按、滑动加点按、确认都各计 1 步；输入文字不计；启动落在摘要页计 0 步。

| # | 任务 | 新路径 | 步数 | 现状（01 / 05） |
|---|---|---|---|---|
| T1-a | **救火：看到受限并恢复** | 启动（摘要）→ 点“3 个账号受限”(1) → 行右滑“恢复状态”(2) → toast“已恢复 · 测试上游 A”+ 成功触觉 | **2** | 概览“异常账号 1”不能点；账号 Tab → 筛选 sheet → 选状态 → 点行 → 详情没有恢复动作。**无法完成** |
| T1-b | 救火：先看原因再处理 | 摘要 → “账号受限”(1) → 点行(2) → 详情首屏即可看到“限流中 · 3:58 后自动恢复”和错误摘要 → “恢复状态”(3)，或“测试连接”(3) → “开始测试”(4) | 3–4 | 详情页首屏全是属性，错误原文不显示（01 D03） |
| T1-c | 救火：批量止血 | 账号 Tab(1) → “限流中”卡(2) → “选择”(3) → “全选”(4) → 底栏“停止调度”(5) → 确认“停止调度 6 个账号”(6) | 6 | 要先回到列表顶部操作，确认按钮是红色（01 D16） |
| T1-d | 从告警进入 | 摘要 → “2 条告警触发中”(1) → 告警行(2) → “查看分组账号”(3)，到达已按分组筛选的账号列表 | 3 | 未实现 |
| T2-a | **给用户充值** | 用户 Tab(1) → 在常驻搜索栏输入邮箱 → 点用户(2) → “充值”(3) → 输入金额 → “充值 $20.00”(4) → 确认“充值 $20.00”(5) | **5** | 用户 Tab → 搜索 → 用户 → 滚动到操作区 → 调整余额 → 选操作 → 输金额 → 核对并确认 → 确认发送：约 7 步，外加滚动 |
| T2-b | 充值（最近处理过的用户） | 用户 Tab(1) → “最近”中的行右滑“充值”(2) → 输入金额 → 主按钮(3) → 确认(4) | 4 | 同上 |
| T2-c | 退款 | 同 T2-a，第 3 步改点“退款”，可用“全部退款”一键填入 | 5 | “调整余额 → 减少”，没有“全部退款” |
| T3 | **早晚看营收和用量** | 启动即见“今日收入 $1,234.50 · 比昨日同时段多 8.2% · 昨日全天 $1,890.12”，以及成本、差额、请求数、Token | **0** | 指标卡要靠颜色图例才能读懂（01 D20） |
| T3-b | 看近 7 天 | 摘要 → 今日收入卡(1) → 统计分析的分段控件“7 天”(2) | 2 | 有 4 个入口，预设按钮没有选中态（01 D27） |
| T4 | **看渠道监控** | 监控 Tab(1) → 一屏看完所有渠道卡（问题渠道排在前面）→ 点渠道(2) → “错误请求”(3) | 1–3 | 未实现 |
| T5-a | 日志排障：某用户说请求失败 | 搜索 Tab(1) → 输入邮箱 → 点用户结果(2) → “错误请求”(3) → 点错误行(4) | 4 | 管理 Tab → 日志 → 切换页签 → 筛选 → **手输用户 ID** → 应用 → 点行：约 7 步，还要先知道 ID |
| T5-b | 按请求 ID 查 | 搜索 Tab(1) → 粘贴 → “请求 req_7f3a…”结果(2) | 2 | 日志 → 筛选 → 请求 ID 输入框 → 应用 → 点行：约 5 步 |
| T5-c | 从账号进入错误 | 账号详情 → “错误请求 12”(1) → 错误行(2)；日志已默认停在“错误请求”分段，并带上账号 Token | 2 | 4 步以上，还要切换页签（01 D03） |
| T5-d | 日志中按对象缩小范围 | 日志里在搜索框输入“ali” → 联想“用户：alice@example.com”(1) 变成 Token；或长按某行 → “只看此账号”(2) | 1–2 | 手输数字 ID |

验收指标（沿用 codex 的度量，05 §3.2）：上面每条路径都要在模拟器上用演示数据实测步数；首屏有效内容在 393pt 宽、默认字号下，列表页至少显示 6 个对象，日志首条记录出现在屏幕 30% 以内。

---

## 4. 逐屏规格

> 线框中 `(S)` 表示站点头像，`›` 表示可下钻，`⋯` 表示工具栏更多菜单。线框只画结构，不代表最终像素。**线框里没有任何说明句**，这本身就是规格的一部分。

### 4.1 摘要（Summary）

**目的**：打开 App 后 3 秒内回答两个问题：有没有坏掉的东西？今天赚了多少？

```
┌──────────────────────────────────────────────┐
│ 摘要                                      (S) │ ← inlineLarge 标题
│ OpenAI 中转站 · 2 分钟前                       │ ← navigationSubtitle
│ ┌ 需要处理 ──────────────────────────────┐   │
│ │ ⛔ 3 个账号受限                        › │   │
│ │    错误 1 · 限流 2 · 最早 3:58 后恢复      │   │
│ │ ─────────────────────────────────────  │   │
│ │ 🔔 2 条告警触发中                      › │   │
│ │    P1 错误率高于 5% · 标准分组             │   │
│ │ ─────────────────────────────────────  │   │
│ │ ⚠ 近 1 小时 12 条错误请求未处理          › │   │
│ │ ─────────────────────────────────────  │   │
│ │ ⏱ 1 笔余额操作待核对                    › │   │
│ └────────────────────────────────────────┘   │
│ ┌ 今日收入 ─────────────────── 16:20  › ┐   │
│ │ $1,234.50                               │   │ ← 圆体大数
│ │ 比昨日同时段多 8.2% · 昨日全天 $1,890.12     │   │
│ │ ▂▃▅▆▇█▆▅▃  ┈┈┈ 昨日                      │   │ ← 今日柱 + 昨日虚线
│ │ 成本 $812.30            差额 $422.20  ⓘ   │   │
│ └────────────────────────────────────────┘   │
│ ┌ 用量 ───────────┐ ┌ 实时 ────────────────┐   │
│ │ 12.3K 次请求      │ │ RPM 37 · TPM 45.2K  │   │
│ │ 45.6M Token       │ │ 错误率 0.4%          │   │
│ └─────────────────┘ └─────────────────────┘   │
│ ┌ 渠道 ─────────────────────────────── › ┐   │
│ │ ● 9 可用  ◐ 1 性能下降  ○ 0 不可用          │   │
│ └────────────────────────────────────────┘   │
│   [摘要] [账号] [用户] [监控]            (🔍)   │
└──────────────────────────────────────────────┘
```

- **首屏**：需要处理、今日收入，以及用量和实时卡的上半部分。没有需要处理的事项时，该卡收成一行“✓ 一切正常 · 2 分钟前检查”，今日收入随之上移。
- **需要处理的规则**（`AttentionRule`，Sub2Core，按严重度排序。**不完整的数据不下结论**，吸取 04 §2.5 中 RN 的教训）：

| 规则 | 数据源（02 章节） | 触发条件 | 点按跳转（在摘要栈内 push） |
|---|---|---|---|
| 余额操作待核对 | 本机 `pendingBalances`（当前站点） | 至少 1 笔 | `PendingList` |
| 告警触发中 | `ops/alert-events?status=firing`（§1.1 告警） | 运维开启且至少 1 条 | `AlertList(.firing)` |
| 账号受限 | `dashboard/stats` 的 `error_accounts + ratelimit_accounts + overload_accounts`（§5）。“最早 x 后恢复”**只在**运维开启、能拿到完整的 `ops/account-availability` 时显示 | 合计至少 1 | `AccountList(.attention)` |
| 渠道异常 | `channel-monitor-v2/overview` 中 warning 和 critical 的数量（§1.4） | 至少 1 | `ChannelList(.problems)` |
| 错误请求未处理 | `ops/request-errors?resolved=false`，起点为 1 小时前，`page_size=1`，取 `total`（§5） | 至少 1 | `Logs(.errors, unresolved, 1h)` |

- **卡片标题行**：符号 + 名称 + 右侧更新时间 + `›`（健康 App 写法）。卡片第一行内容就是结论句（天气 App 写法）。
- **口径**：“差额”旁的 ⓘ 弹出词典定义“差额 = 实际扣费 − 账号成本，不含服务器等其他费用”（01 C70），不在卡面上常驻。
- **“比昨日同时段”**：用现有 `dashboard/trend`（昨日以来的逐小时数据）本地累加得到，不需要新接口。
- **状态**：每张卡有独立的 `LoadState`（复用 `DashboardLoadState`）。加载中显示卡片骨架（`.redacted(.placeholder)`）；单卡失败时只在该卡显示一行“今日收入未能载入 · 重试”，其他卡不受影响。整页刷新失败但已有数据时，副标题变成“显示 10:24 的数据”，并带琥珀色图标（§6）。
- **SwiftUI**：`NavigationStack(path: $router.summaryPath)` → `ScrollView { VStack(spacing: 16) { AttentionCard; RevenueCard; Grid { GridRow { UsageTile; LiveTile } }; ChannelSummaryCard } .padding(.horizontal) }` · `.background(Color(.systemGroupedBackground))` · `.toolbarTitleDisplayMode(.inlineLarge)` · `.navigationSubtitle` · `.refreshable` · `.task(id: scenePhase)` 负责前台 30 秒轮询 · `.navigationDestination(for: Route.self)` · 数值用 `.contentTransition(.numericText(value:))` 和 `.monospacedDigit()`。图表用 Swift Charts 的 `BarMark` 加 `LineMark`（`.lineStyle(StrokeStyle(dash:))`），隐藏坐标轴，配 `accessibilityChartDescriptor`。辅助功能字号下，`Grid` 改为单列（`AnyLayout`）。

### 4.2 账号列表

账号部分分两层：**账号 Tab 根页（状态总览）** 和 **筛选后的账号列表**。

#### 4.2.1 账号 Tab 根页（提醒事项式）

```
┌──────────────────────────────────────────────┐
│ 账号                                [⋯]  (S) │
│ OpenAI 中转站                                  │
│ 🔍 搜索账号名称                                  │
│ ┌──────────────────┐ ┌──────────────────┐     │
│ │ ⛔             1 │ │ ⏳             2 │     │
│ │ 错误             │ │ 限流中            │     │
│ └──────────────────┘ └──────────────────┘     │
│ ┌──────────────────┐ ┌──────────────────┐     │
│ │ ⚠             0 │ │ ⏸             4 │     │
│ │ 临时不可调度      │ │ 暂停              │     │
│ └──────────────────┘ └──────────────────┘     │
│ ┌────────────────────────────────────────┐    │
│ │ ▤ 全部账号                       128  › │    │
│ │ ⊖ 停用                             3  › │    │
│ └────────────────────────────────────────┘    │
│ 按分组                                          │
│ ┌────────────────────────────────────────┐    │
│ │ 标准分组    可用 10 · 限流 2         12  › │    │
│ │ 高级分组    可用 5                    5  › │    │
│ │ 未分组                                3  › │    │
│ └────────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
```

- **首屏**：4 张状态卡加“全部账号”。每张卡对应**一个服务端筛选值**（`error`、`rate_limited`、`temp_unschedulable`、`unschedulable`），计数取自 `GET admin/accounts?status=…&page_size=1&lite=true` 返回的 `total`。计数和列表来自同一个数据源，不会出现 RN 那种“计数是错的”（04 §2.5）。
- 计数为 0 的卡保持显示，只是置灰。卡片位置保持稳定，方便肌肉记忆。
- “过载”没有服务端筛选值（02 §3.1）。运维开启时，第 5 张卡“过载中 n”取自 `ops/account-availability`；运维关闭时不显示这张卡，过载账号仍然通过行内徽标和摘要中的计数呈现。
- “按分组”数据来自 `admin/groups/all`，已有 `account_count`、`active_account_count`、`rate_limited_account_count` 三个字段。
- 输入搜索词后，根页内容就地替换为 plain 结果列表（提醒事项 / 邮件的行为）。
- `⋯` 菜单：“选择账号”（进入全部列表的选择模式）、“在 Web 中新建账号 ↗”（新建账号只在 Web，04 §2.6#6）。
- **SwiftUI**：`List { Section { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())]) { SmartCountCard… } }.listRowBackground(Color.clear).listRowInsets(.init()) ; Section { NavigationLink(value: Route.accountList(.all)) {…} } ; Section("按分组") {…} }.listStyle(.insetGrouped)` · `.searchable(text:prompt:)` · `@Environment(\.isSearching)` 控制是否切换为结果列表 · `SmartCountCard` 是 `NavigationLink(value:)` 加 `.buttonStyle(.plain)`，背景 `secondarySystemGroupedBackground`，圆角使用 `ConcentricRectangle`（iOS 26）或连续圆角 · 计数用 `.contentTransition(.numericText)`。

#### 4.2.2 筛选后的账号列表（邮件式）

```
┌──────────────────────────────────────────────┐
│ ‹ 账号        限流中                [选择] [⋯] │
│ 🔍 搜索 · [平台：OpenAI ×]                     │ ← 生效的筛选以 Token 显示
│ ─────────────────────────────────────────── │
│ ⏳ 测试上游 A                          3:58   │ ← 第 1 行：状态符号 · 名称 · 恢复倒计时
│    OpenAI · API Key · 标准分组                 │ ← 第 2 行：平台 · 认证类型 · 分组
│    上游返回 429 · Rate limit exceeded for…     │ ← 第 3 行：原因（严重色，1 行）
│ ─────────────────────────────────────────── │
│ ⏳ claude-pro-07                      12:40   │
│    Anthropic · OAuth · 高级分组                │
│    并发 1/4 ▕██░░░░▏ · 今日 $3.45              │
│ ─────────────────────────────────────────── │
│ ✓ gemini-01                        3 分钟前   │ ← 正常账号右侧显示最近使用时间
│    Gemini · API Key · 标准分组                 │
│    RPM 37/60 ▕██████░░▏ · 今日 1.2K 次         │
└──────────────────────────────────────────────┘
```

**行解剖（固定，取消“自定义显示字段”）**

| 行 | 内容 | 规则 |
|---|---|---|
| 第 1 行 | `StatusGlyph`（形状 + 色调）· 名称（`.headline`，1 行，尾部截断）· 右侧尾注 | 尾注优先级：限时状态的倒计时（琥珀，`Text(timerInterval:countsDown:)`，`.monospacedDigit()`）→ “停用”“暂停”文字 → 最近使用的相对时间（次要色） |
| 第 2 行 | 平台显示名 · 认证类型显示名 · 分组（超过 2 个时写“标准分组 等 3 个”） | 次要色，1 行，不使用平台色 |
| 第 3 行（按优先级选一项） | ① 错误或临时不可调度的原因（脱敏摘要，严重或注意色，1 行）② 最紧张的一项容量（并发 / RPM / 日配额 / 窗口费用中占用率最高的）+ 今日请求数或扣费 ③ 都没有数据时**省略这一行** | 不再出现“在用并发：不可用”这类文字（01 D01/D02）。容量条用 `Gauge(.accessoryLinearCapacity)`：占用 ≥75% 为琥珀，≥90% 为红（与 Web 阈值一致，04 §4.1#24），同时显示文字数值 |

- 默认字号下每行约 76pt，一屏可显示 8 到 9 个账号；现状是 3 到 4 个（01 §2.4）。
- 辅助功能字号下，第 3 行的容量条改为纯文字；第 2 行在 `isAccessibilitySize` 时隐藏，完整信息放在详情页（03 §5.4）。
- **筛选与排序**：工具栏 `⋯` 菜单里用内联 `Picker` 提供 平台 / 认证类型 / 分组 / 排序（名称、优先级、最近使用、过期时间）。选择后生成 Token 放进搜索框，Token 就是唯一的筛选状态。在“全部账号”里还多一个“状态” Picker，选项与 Web 一一对应：正常 / 停用 / 错误 / 限流中 / 临时不可调度 / 暂停。其中“暂停”对应服务端的 `unschedulable`，这里刻意与徽标用同一个词（04 §4.1#7）。
- **滑动**：前缘（右滑）是“恢复状态”，只在可恢复的状态下出现；后缘（左滑）是“停止调度 / 启用调度”和“测试”。所有写操作都设 `allowsFullSwipe: false`（03 P13）。
- **长按**：`contextMenu(menuItems:preview:)`，预览是迷你状态卡；菜单项与滑动一致，另加“复制名称”和“只看此分组”。
- **分页**：每页 20 条，滚动到底自动加载，加载失败时在底部显示一行“加载失败 · 重试”。
- **自动刷新**：在前台且列表可见时，每 30 秒静默刷新已加载的页。进入选择模式、滑动展开或打开菜单时暂停刷新（01 §2.4）。开关放在站点面板的偏好设置里，不在列表首屏。
- **倒计时到点**：`TimelineView(.explicit([deadline]))` 在到点时触发该账号的单条刷新（`GET admin/accounts/:id`）。刷新前尾注显示“已到恢复时间”。
- **SwiftUI**：`List(selection: $selection) { ForEach(accounts) { AccountRow($0).tag($0.id) } }.listStyle(.plain)` · `.environment(\.editMode, $editMode)` · `.searchable(text:tokens:placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索账号") { token in Label(token.title, systemImage: token.symbol) }` · `.toolbarTitleDisplayMode(.inlineLarge)` · `.swipeActions` · `.contextMenu` · `.refreshable` · `.alignmentGuide(.listRowSeparatorLeading)` 让分隔线与名称左对齐。

### 4.3 账号详情

```
┌──────────────────────────────────────────────┐
│ ‹ 限流中                                  [⋯] │
│ 测试上游 A                                     │ ← inlineLarge 标题
│ OpenAI · API Key · #12                        │ ← navigationSubtitle
│ ┌────────────────────────────────────────┐    │ ← 英雄状态卡（色调底 12%）
│ │ ⏳ 限流中                                │    │
│ │    3:58 后自动恢复                       │    │
│ │    上游返回 429 · Rate limit exceeded…   │    │
│ │    另有：2 个模型限流（紫）                  │    │
│ │  [ ↻ 恢复状态 ]      [ ▶︎ 测试连接 ]       │    │ ← 主按钮由状态决定
│ └────────────────────────────────────────┘    │
│ ┌────────────────────────────────────────┐    │
│ │ 参与调度                         [ ●  ] │    │ ← Toggle，即时执行，可撤销
│ └────────────────────────────────────────┘    │
│ 容量                                            │
│ │ 并发     ▕█████░░░▏           2 / 4    │    │
│ │ RPM      ▕███░░░░░▏          37 / 60   │    │
│ │ 日配额   ▕████░░░░▏   $3.45 / $20.00    │    │
│ │ 5 小时窗口 ▕████████▏   接近上限（80%）   │    │
│ 今日                                            │
│ │ 1,204 次 · 4.5M Token                   │    │
│ │ 实际 $3.45 · 成本 $2.10 · 标准 $3.80  ⓘ   │    │
│ │ 错误请求                         12  › │    │
│ │ 请求记录                              › │    │
│ │ 统计分析                              › │    │
│ │ 分组      标准分组、高级分组            › │    │
│ │ 代理      hk-01 · 6 天后到期            › │    │
│ 设置                                            │
│ │ 优先级                             10   │    │
│ │ 账号倍率                          ×1.0  │    │
│ │ 负载因子                             —  │    │
│ │ 过期时间        2026/12/31 · 到期自动暂停 │    │
│ │ 备注                       主力 · 勿删   │    │
└──────────────────────────────────────────────┘
```

- **首屏**：英雄状态卡、调度开关，以及容量的前两行。动作就在首屏（修复 01 D17）。
- **英雄卡的主按钮由状态决定**（`AccountCondition.recovery`，见 §7）：

| 主状态 | 主按钮 | 次按钮 |
|---|---|---|
| 错误 / 限流中 / 过载中 / 临时不可调度 / 模型限流 | 恢复状态（`POST :id/recover-state`，L0，会返回最新账号） | 测试连接 |
| 配额超限 | 重置配额…（L2，destructive） | 测试连接 |
| 暂停 | 启用调度（L0） | 测试连接 |
| 停用 / 已过期 | 无（在 Web 中处理），只显示原因 | 在 Web 中打开 |
| 正常 | 测试连接 | — |

- **调度开关**：独立的 `Toggle` 行。它本身就是一个设置，用设置范式最合适。拨动后立即执行，成功时显示 toast“已停止调度 · 撤销”，并注册 UndoManager。等待期间 Toggle 显示进行中状态并禁用；如果被拒绝，Toggle 回弹，行内显示原因，同时给失败触觉。
- **容量**：每项用 `Gauge` 加右对齐的数值。没有上限的项不显示；数据缺失时显示“—”。不再用一长串“·”拼接（01 D12）。
- **关联区**：所有跨对象入口集中在一个分区。计数只显示服务端给出的精确值，例如错误请求数取自带 `account_id` 的 `request-errors` 的 `total`。
- **`⋯` 菜单**：编辑…、刷新令牌（仅 OAuth / Setup Token，L1）、重置配额…（有配额时，L2）、复制账号 ID、在 Web 后台打开 ↗。不提供删除，删除只在 Web 做。
- **状态呈现**：首次加载时用列表传入的账号快照立即渲染，然后在后台刷新详情和今日统计（分区独立）。今日统计失败时，该分区显示一行“今日用量未能载入 · 重试”。
- **SwiftUI**：`List { Section { AccountHeroCard }.listRowBackground(tone.background) ; Section { Toggle("参与调度", isOn:) } ; Section("容量") { CapacityRow… } ; Section("今日") {…} ; Section { RelatedLink… } ; Section("设置") { PropertyRow… } }.listStyle(.insetGrouped).listSectionSpacing(.compact)` · 英雄卡按钮用 `.buttonStyle(.borderedProminent)` 和 `.bordered`，`.controlSize(.large)`。内容层不用玻璃按钮。· `.sensoryFeedback(.success, trigger: result)` · `@Environment(\.undoManager)`。

### 4.4 账号编辑（sheet）

```
┌──────────────────────────────────────────────┐
│ 取消            编辑账号                 保存 │ ← 保存在 isDirty 且校验通过时才可用
│ ┌ 基本 ──────────────────────────────────┐  │
│ │ 名称          测试上游 A                  │  │
│ │ 备注          主力 · 勿删                 │  │
│ └────────────────────────────────────────┘  │
│ ┌ 调度 ──────────────────────────────────┐  │
│ │ 优先级                     [ 10 ] [−|+] │  │
│ │ 并发上限                   [  4 ] [−|+] │  │
│ │ 负载因子                     [ 默认 ]    │  │
│ └────────────────────────────────────────┘  │
│   数值越小越优先                                │ ← 字段语义（允许），不是契约
│ ┌ 计费 ──────────────────────────────────┐  │
│ │ 账号倍率                      [ 1.0 ] × │  │
│ └────────────────────────────────────────┘  │
│ ┌ 分组 ──────────────────────────────────┐  │
│ │ 所属分组       标准分组、高级分组        ›  │  │ ← push 到多选列表，不再是 30 个 Toggle
│ └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

- **字段**：只开放安全的快捷字段（现有 `AccountUpdateRequest`）。标签始终可见，占位文字只作示例（修复 01 §2.6）。单位写在后缀，例如“×”。
- **校验**：输入时即时校验，错误显示在字段下方的红色 footnote，同时禁用“保存”。规则复用 `AccountUpdateRequest.validate()`，文案改写成字段级，例如“并发须为 0 或正整数”。
- **分组多选**：push 到 `GroupMultiPicker`，用 `List(selection:)` 加 `.searchable`。与账号平台不兼容的分组置灰，并在行尾写原因。服务端没有返回的原分组单独列在“其他已绑定分组”中，默认保持勾选（替代 01 C45 那句说明）。
- **提交**：“保存”属于 L0，不弹确认（编辑可逆）。成功后关闭 sheet，显示 toast“已保存”。被拒绝时停留在页面，在顶部分区显示原因。
- **结果不明**：整个表单锁定，顶部显示 `PendingVerificationBanner`“未收到站点确认 · 更改可能已生效”，按钮为“读取最新状态”（复用 `PendingAccountUpdate` 的比对逻辑）和“关闭”。
- **草稿保护**：`.interactiveDismissDisabled(isDirty || isSubmitting)`。有改动时点“取消”，弹出 confirmationDialog“放弃更改？”，选项为“放弃更改”（destructive）和“继续编辑”。
- **SwiftUI**：`NavigationStack { Form {…} }` · `LabeledContent("优先级") { TextField(value:format: .number).keyboardType(.numberPad) }` + `Stepper` · `@FocusState` 配合 `.submitLabel(.next)` · `.toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") {…} }; ToolbarItem(placement: .confirmationAction) { Button("保存") {…}.disabled(!canSave) } }`，保存按钮使用系统为 `.confirmationAction` 提供的突出样式，不自定义 · `.presentationDetents([.large])`。

### 4.5 账号测试（流式，sheet）

```
┌──────────────────────────────────────────────┐
│ 完成              测试连接                     │
│ 测试上游 A · OpenAI                            │
│ ┌────────────────────────────────────────┐  │
│ │ 模型                      默认模型  ⌄    │  │ ← Menu：默认 / 可用模型 / 其他…
│ └────────────────────────────────────────┘  │
│   会向上游发送一次真实请求，可能产生费用。           │ ← 业务后果（允许）
│ [              ▶︎ 开始测试              ]       │
│ ─────────── 运行中 ────────────                │
│ ⟳ 正在接收 · 00:03                    [停止]  │
│ ┌────────────────────────────────────────┐  │
│ │ Hello! I'm ready to help you with…▍    │  │ ← 等宽、自动滚动、可选中
│ └────────────────────────────────────────┘  │
│ ─────────── 结束 ──────────────                │
│ ✓ 测试通过 · 首字 1.2s · 总耗时 3.4s             │
│ [ 再测一次 ]   [ 复制输出 ]                      │
└──────────────────────────────────────────────┘
```

- **状态**：准备、连接中（琥珀）、接收中、通过（绿，`.success` 触觉）、失败（红，显示状态码分类和服务端返回的脱敏消息，`.error` 触觉）、未完成（琥珀，“连接中断，未收到完成结果”，`.warning` 触觉）。现状的“请在 Web 后台查看详细错误”删除（01 C43）。
- **模型**：默认使用后端的默认模型；可选列表来自 `GET accounts/:id/models`（P1，02 §1.2）；也可以选“其他…”手动输入。
- **确认级别**：“开始测试”按钮本身就是确认，上方一行写明费用后果，不再另外弹窗。
- **运行中**：`.interactiveDismissDisabled(true)`，“停止”会取消流（复用 `testAccount` 的取消逻辑）。
- **测试后**：测试通过且账号仍处于受限状态时，结果卡下方出现“恢复状态”按钮（L0），因为“测完就恢复”是一个连续的动作。
- **SwiftUI**：`NavigationStack { ScrollView { … } }` · `.presentationDetents([.medium, .large])` · `ScrollView` 加 `.defaultScrollAnchor(.bottom)`（iOS 17）· 输出用 `Text(output).font(.callout.monospaced()).textSelection(.enabled)` · 计时用 `Text(timerInterval:)` · 输出经 `sanitizedTestOutput` 脱敏后再显示（逻辑移入 Core）。

### 4.6 批量选择 + 逐项结果

```
选择模式（邮件式；Tab 栏隐藏，底部工具条出现）
┌──────────────────────────────────────────────┐
│ 全选              已选择 3 个              完成 │
│ ◉ ⏳ 测试上游 A                          3:58  │
│ ◉ ⛔ claude-pro-07                            │
│ ○ ✓ gemini-01                                 │
│ ◉ ✓ openai-key-3                              │
│ ─────────────────────────────────────────── │
│ [ 停止调度 ]      [ 启用调度 ]      [ 更多 ⋯ ]  │ ← bottomBar；更多：恢复状态 / 刷新令牌
└──────────────────────────────────────────────┘

确认（L1，从“停止调度”按钮弹出，非 destructive）
   停止 3 个账号的调度？
   测试上游 A、claude-pro-07 等 3 个 · OpenAI 中转站
   [ 停止调度 3 个账号 ]
   [ 取消 ]

结果（只在不是全部成功时出现；全部成功只显示 toast）
┌──────────────────────────────────────────────┐
│                 处理结果                  完成 │
│ 停止调度 · 1 个失败 · 1 个待核对 · 1 个成功        │
│ ✕ claude-pro-07                               │
│   站点拒绝：账号处于错误状态                       │
│ ? openai-key-3                                │
│   未收到确认                                    │
│ ▸ 1 个成功                                      │ ← DisclosureGroup，默认折叠
│ [ 重试失败的 1 个 ]     [ 刷新待核对的 1 个 ]      │
└──────────────────────────────────────────────┘
```

- **进入**：列表工具栏“选择”，或在列表上双指滑动直接进入（`List(selection:)` 原生支持）。点整行切换选中，不会进入详情（修复 05 §2#4）。
- **上限**：一次最多 50 个（`setAccountsSchedulable` 的约束）。“全选”只选已加载的前 50 个；超出时给 `.warning` 触觉，并显示 toast“一次最多选择 50 个”。不再静默忽略。
- **执行中**：底部工具条换成“正在处理 3 个…”和进度。完成前不能退出选择模式。
- **结果排序**：失败 → 待核对 → 成功。失败项保持选中，便于“重试失败的 n 个”。待核对项可以“刷新”，逐个读取最新状态。
- **数据**：调度用 `bulk-update`（现有，返回逐项结果）；恢复状态逐个调用 `recover-state`，限制并发；刷新令牌沿用现有的逐个调用。
- **SwiftUI**：`List(selection:)` · `.environment(\.editMode, $editMode)` · `.toolbarVisibility(editMode.isEditing ? .hidden : .automatic, for: .tabBar)` · `ToolbarItemGroup(placement: .bottomBar)` · `.navigationTitle(editMode.isEditing ? "已选择 \(n) 个" : title)` · `.contextMenu(forSelectionType: Int.self)` 用于多选后长按 · 确认用 `.confirmationDialog` 挂在底栏按钮上 · 结果用 `.sheet` 加 `.presentationDetents([.medium, .large])`。

### 4.7 用户列表

```
┌──────────────────────────────────────────────┐
│ 用户                              [+]   (S) │
│ OpenAI 中转站                                  │
│ 🔍 邮箱、用户名、备注或 API Key                    │ ← 搜索栏常驻
│ 最近处理                                        │
│   alice@example.com                 $128.50  │ ← 余额右对齐、等宽数字
│   Alice · 3 小时前使用                          │
│   carol@corp.cn                       $3.20  │
│   Carol · 管理员 · 昨天使用                      │
│ 全部用户 · 1,024                                │
│   bob@corp.cn                        $12.00  │
│   Bob · 昨天使用                                │
│ ⊘ spam@x.io                           $0.00  │ ← 已禁用：符号、文字和余额都置灰
│   已禁用 · 10/02 使用                           │
└──────────────────────────────────────────────┘
```

- **首屏**：“最近处理”最多 5 个，记录本机上查看或调整过余额的用户（只存 ID，按站点身份隔离，复用 `ListFieldSelection` 的存储方式），然后是全部用户。
- **行解剖（2 行）**：第 1 行是邮箱（`.headline`，中间截断）加右侧余额（主色、`.monospacedDigit()`）；第 2 行是用户名 · 角色（普通用户不写）· 最近使用时间。已禁用的用户在前面加 `nosign` 灰色符号，并在第 2 行写“已禁用”。
- **筛选**：`⋯` 中提供状态（启用 / 禁用）和角色（管理员 / 用户 / 代运营），选择后生成 Token。不再在列表顶部常驻 Picker（01 D30）。
- **滑动**：前缘是“充值”；后缘是“禁用 / 启用”（L1）。
- **长按**：充值…、退款…、复制邮箱、请求记录、错误请求、禁用用户。
- **“+”**：新建用户（现有功能，sheet），保持工具栏位置。
- **SwiftUI**：`List { Section("最近处理") {…}; Section("全部用户 · \(total)") {…} }.listStyle(.plain)` · `.searchable(text:tokens:placement: .navigationBarDrawer(displayMode: .always))`，带 300ms 防抖（复用）· `.swipeActions(edge: .leading, allowsFullSwipe: false) { Button("充值", systemImage: "plus.circle") {…}.tint(.accentColor) }`。

### 4.8 用户详情（钱包式）

```
┌──────────────────────────────────────────────┐
│ ‹ 用户                                    [⋯] │
│ alice@example.com                             │
│ Alice · 用户 · 启用                             │
│ ┌ ⚠ 1 笔充值待核对 · $20.00                 › ┐ │ ← 只在有待核对时出现
│ ┌────────────────────────────────────────┐    │
│ │ 余额                                     │    │
│ │ $128.50                                  │    │ ← 圆体大数
│ │ 累计充值 $1,000.00 · 冻结 $0.00             │    │
│ │  [ ＋ 充值 ]              [ − 退款 ]       │    │
│ └────────────────────────────────────────┘    │
│ 本月                                            │
│ │ 3,204 次 · 12.4M Token · 实际 $45.20       │ │
│ 余额记录                              全部 ›    │
│ │ ＋ 管理员充值             +$20.00     今天   │ │
│ │ ＋ 兑换码                 +$50.00    10/12   │ │
│ │ − 管理员退款              −$5.00     10/02   │ │
│ API Key · 3                           全部 ›    │
│ │ ● default        已用 $12.30 · 不限额        │ │
│ │ ● cursor         已用 $3.10 / $50.00        │ │
│ │ 错误请求                                 ›  │ │
│ │ 请求记录                                 ›  │ │
│ │ 统计分析                                 ›  │ │
│ 设置                                            │
│ │ 并发上限                                 2  │ │
│ │ RPM 上限                              不限  │ │
│ │ 最近活跃                          3 小时前   │ │
│ │ 创建时间                        2026/03/02  │ │
│ │ 备注                                  VIP  │ │
└──────────────────────────────────────────────┘
```

- **首屏**：身份、余额卡和充值 / 退款按钮、本月用量。资金操作就在首屏（修复 01 D34）。
- **金额颜色**：一律中性主色，用正负号表达方向。在中文语境中不用红绿区分金额（03 §5.3）。
- **加载**：资料、本月用量、余额记录、API Key **四个分区并行加载**，各自有 `LoadState`。修复现状串行加载以及“用量失败就显示暂无 API Key”的问题（05 §2#5）。
- **余额记录类型**：由词典把 `admin_balance` 映射为“管理员充值 / 管理员退款”（按值的正负决定），`balance` 为“余额充值”，`subscription` 为“订阅”，`invitation` 为“邀请奖励”，`affiliate_balance` 为“返利转入”，等等（02 §3.2）。
- **`⋯` 菜单**：编辑用户…、复制邮箱、禁用用户（L1，放在最后）。管理员账号不显示“禁用”，与 Web 行为一致（04 §3.7）。
- **SwiftUI**：`List(.insetGrouped)`，第一个 Section 是 `BalanceHeroCard`（`.listRowBackground(Color(.secondarySystemGroupedBackground))`）· 余额用 `.font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()`，并加 `.privacySensitive()`；开启“隐藏金额”时显示 `.redacted(reason: .privacy)` · 分区标题右侧“全部 ›”是 `NavigationLink(value:)` · 金额变化用 `.contentTransition(.numericText(value:))`。

### 4.9 充值 / 退款（sheet，Apple Cash 式）

```
┌──────────────────────────────────────────────┐
│ 取消                 充值                      │
│              alice@example.com                │
│              当前余额 $128.50                   │
│                                                │
│                 $ 20.00                        │ ← 大号可编辑金额，自动获得焦点
│                                                │
│ ┌────────────────────────────────────────┐    │
│ │ 备注                          （可选）     │    │
│ └────────────────────────────────────────┘    │
│ 充值后余额                          $148.50     │
│                                                │
│ [             充值 $20.00              ]       │ ← 底部 safeAreaBar，主按钮
│  ┌───┬───┬───┐                                │
│  │ 1 │ 2 │ 3 │   系统 decimalPad                 │
└──────────────────────────────────────────────┘

确认（L2，从主按钮弹出）
   向 alice@example.com 充值 $20.00？
   OpenAI 中转站 · 充值后余额 $148.50
   [ 充值 $20.00 ]        ← role: .destructive（00 §3.5：资金类用 destructive）
   [ 取消 ]
```

- **退款**：同一个组件，`operation = .subtract`，标题和按钮写“退款”。金额旁有“全部退款”按钮（Web 有同名功能，04 §3.7）。金额超过当前余额时，行内提示“超过当前余额 $128.50”，并禁用主按钮。预览行写“退款后余额”。
- **“设为”（set）**：不在 UI 上提供，与 Web 的“充值 / 退款”二分一致。历史上留下的 set 类待核对记录仍会被正确显示为“设为”。
- **金额输入**：`Decimal` 精度，最多 8 位小数（复用 `PendingBalanceOperation.validate()`）。显示时千分位、两位小数、窄货币符号 `$`。**没有默认金额**（吸取 04 §2.5#9 RN 的教训）。
- **结果**：
  - 成功：关闭 sheet，显示 toast“已为 alice 充值 $20.00”，给 `.success` 触觉，详情页余额以数字过渡动画更新。
  - 被拒绝：停留在页面，在金额下方显示原因，给 `.error` 触觉。
  - 结果不明：sheet 原地变为“待核对”状态，并持久化（复用现有机制）：

```
┌──────────────────────────────────────────────┐
│ 关闭               充值待核对                   │
│ ⚠ 未收到站点确认                                 │
│   这笔充值可能已经到账。用“重试这笔充值”不会重复入账。 │
│   alice@example.com · $20.00 · 16:12          │
│   ▸ 操作编号  7F3A…C21   [复制]                  │ ← 折叠
│ [            重试这笔充值             ]          │ ← 沿用同一个幂等编号
│ [            查看最新余额             ]          │
└──────────────────────────────────────────────┘
```

- **二次验证**：服务端要求时，`StepUpPresenter` 在 sheet 上弹出 alert 收验证码（不叠加 sheet）。验证通过后**重新弹出 L2 确认**，不会自动发送（保留现有语义）。
- **SwiftUI**：`NavigationStack { VStack {…} }` · `TextField(value: $amount, format: .number.precision(.fractionLength(0...8))).font(.system(size: 48, design: .rounded)).keyboardType(.decimalPad).focused($amountFocused)` · `.safeAreaBar(edge: .bottom) { Button {…} label: { Text("充值 \(amount.formatted(.sub2Money))").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large) }` · `.confirmationDialog(title, isPresented:, titleVisibility: .visible)` 挂在主按钮上 · `.interactiveDismissDisabled(amount != nil || state != .idle)` · `.sensoryFeedback`。

### 4.10 日志列表 + 对象筛选（替代手输 ID）

```
┌──────────────────────────────────────────────┐
│ ‹ 浏览     日志               [🕘 近 24 小时 ⌄] │
│ OpenAI 中转站                                  │
│ [  错误请求  |  用量明细  |  上游错误  ]          │ ← safeAreaBar 顶部，分段
│ 🔍 [账号：测试上游 A ×] [未处理 ×]  搜索…        │ ← 搜索 Token = 全部筛选条件
│ 今天                                            │ ← 按日分节，吸顶
│ ┌───┐ claude-sonnet-4.5                 16:12  │
│ │429│ 限流 · 测试上游 A · alice@ex…             │
│ └───┘ Rate limit exceeded for organization…   │
│ ┌───┐ gpt-4.1                           16:03  │
│ │502│ 上游错误 · openai-key-3 · bob@…    ✓ 已处理 │ ← 已处理：整行降为次要色
│ └───┘ upstream connect error                  │
│ 昨天                                            │
│ ┌───┐ …                                        │
└──────────────────────────────────────────────┘

输入“ali”时的联想（searchSuggestions）
│ 🔍 ali                                         │
│ 用户                                            │
│   👤 alice@example.com                         │ ← GET admin/usage/search-users
│ 账号                                            │
│   ⛁ alibaba-qwen-01                           │ ← GET admin/accounts?search=
│ API Key                                        │
│   🔑 alice-cursor · alice@example.com          │ ← GET admin/usage/search-api-keys
│ 分组                                            │
│   ▦ （本地 groups/all 匹配）                     │
│ 其他                                            │
│   ◇ 按模型筛选“ali”                              │
│   # 按请求 ID 查找“ali”                          │
```

- **首屏**：分段、Token 条，然后直接是记录。没有任何说明卡（现状控制和说明约占 37%，01 D06）。
- **分段**（名称以 Web 为准，04 §4.1#17）：错误请求 / 用量明细 / 上游错误。从目录进入时默认“错误请求”；从“请求记录”入口进入时默认“用量明细”；同一站点记住上次的选择。
- **Token 类型**（`LogToken`，Sub2Core）：用户、账号、分组、API Key（以上都带 ID 和显示名）、模型（精确）、请求 ID、状态码类别（429 / 5xx / 4xx）、处理状态（未处理 / 已处理）、请求类型（流式 / 同步 / WS / Live / 安全策略，词典映射）。Token 直接映射到 `RequestLogFilter`，不再有自由的 ID 输入框。
- **数据源不支持某些条件时**（修复 05 §2#3 的“静默删除筛选”）：上游错误不支持用户、Key、模型、请求 ID 筛选。此时**条件保留**，切到“上游错误”分段时显示状态视图 `ContentUnavailableView("上游错误不能按用户筛选", systemImage: "line.3.horizontal.decrease.circle")`，按钮为“移除用户条件”。不偷偷改写查询。
- **时间**：工具栏 `Menu` 提供 近 1 小时 / 近 24 小时 / 近 7 天 / 近 30 天（滚动窗口，下拉刷新时把终点更新为当前时间）以及“自定义…”（medium 高度的 sheet，两个 `DatePicker`，属于固定区间）。菜单标签直接显示当前值，例如“近 24 小时”或“10/15 08:00–10/16 08:00”。选中态就是语义本身，不需要说明句（删除 01 C59/C60）。
- **行解剖**：
  - 错误行：左侧是 36pt 状态码方块（429 / 529 琥珀，5xx 红，其他 4xx 灰）· 第 1 行模型 + 右侧时间（今天写 `HH:mm`；跨日的行已有日期分节）· 第 2 行分类（词典的 9 类）· 账号 · 用户（邮箱中间截断）· 第 3 行脱敏消息，1 行。
  - 用量行：左侧是请求类型符号 · 第 1 行模型 + 时间 · 第 2 行用户 · 账号 · 第 3 行“$0.0024 · 1.2K Token · 1.25s · 流式”。金额精度自适应：≥$1 显示两位小数，<$1 最多 4 位有效小数。
- **滑动**：错误行的前缘是“标记已处理 / 标记未处理”（L0，可撤销，`PUT ops/request-errors/:id/resolve`，P0）。用量行没有写操作，所以不设滑动。
- **长按**：标记已处理、复制请求 ID、查看账号、查看用户、**只看此账号**、**只看此用户**（邮件“只看此发件人”的写法，会追加 Token）。
- **分页**：现有的 `RequestLogPage` 延迟计数。总数只在 `totalExact` 时显示在分段下方，例如“共 128 条”，否则不显示。
- **从对象进入**：`Route.logs(LogQuery(scope: .errors, tokens: [.account(id, name)]))` push 到当前栈，返回时回到原对象（修复 05 §5.6）。
- **SwiftUI**：`List { ForEach(daySections) { day in Section(day.title) { ForEach(day.rows) { LogRow($0) } } } }.listStyle(.plain)` · `.safeAreaBar(edge: .top) { Picker("", selection: $scope) {…}.pickerStyle(.segmented).padding(.horizontal) }` · `.searchable(text:tokens:placement: .navigationBarDrawer(displayMode: .always), prompt: "用户、账号、模型或请求 ID") { Label($0.title, systemImage: $0.symbol) }` · `.searchSuggestions { ForEach(suggestions) { Label(…).searchCompletion($0.token) } }` · `.toolbar { ToolbarItem(placement: .topBarTrailing) { TimeRangeMenu(range: $range) } }` · `.refreshable` · 最后一行 `.onAppear` 时加载下一页 · 联想请求 250ms 防抖，并取消上一次请求。

### 4.11 请求详情（钱包交易式）

```
┌──────────────────────────────────────────────┐
│ ‹ 日志                                    [⋯] │
│                     ✓                         │
│                  gpt-4.1                      │
│          成功 · 流式 · 今天 16:12:04             │
│                  $0.0024                      │ ← 实际扣费，大字
│                   实际扣费                       │
│ ┌────────────────────────────────────────┐    │
│ │ 成本                          $0.0011   │    │
│ │ 标准                          $0.0030   │    │
│ │ 差额                          $0.0013 ⓘ │    │
│ └────────────────────────────────────────┘    │
│ Token                                          │
│ │ ▇▇▇▇▇▇▇▇▆▆▆▒▒  （输入 / 输出 / 缓存读 / 缓存写） │ │
│ │ 输入 820 · 输出 312 · 缓存读 104 · 缓存写 0     │ │
│ │ 首字 0.42s                    总耗时 1.25s   │ │
│ 关联                                            │
│ │ 👤 alice@example.com                    › │ │
│ │ ⛁ 测试上游 A               ✓ 正常         › │ │ ← 显示账号的实时状态
│ │ ▦ 标准分组                              › │ │
│ │ 🔑 cursor                               › │ │
│ 详细信息                                         │
│ │ 请求 ID        req_7f3a…c21          ⧉  │ │ ← 中间截断，点按复制
│ │ 上游请求 ID     msg_01…9x             ⧉  │ │
│ │ 上游模型        gpt-4.1-2025-04-14       │ │
│ │ 入口           /v1/chat/completions      │ │
└──────────────────────────────────────────────┘
```

- **首屏**：结果、金额三种口径、Token 和耗时。这些正是“成功还是失败、花了多少”（03 P11）。
- **口径**：使用 实际 / 成本 / 标准 三元，词典短标签写“实际 / 成本 / 标准”，ⓘ 中给出长名“实际扣费 / 账号成本 / 标准费用”（04 §5）。
- **`⋯` 菜单**：复制请求 ID、分享摘要（`ShareLink`，纯文本，不含凭据）、查看同一请求的错误（用 `request_id` 查询 `request-errors`，有结果时才显示）。
- **SwiftUI**：`List(.insetGrouped)`，第一个 Section 是居中的 `TransactionHero`，`.listRowBackground(Color.clear)` · Token 构成用 Swift Charts 的单条堆叠 `BarMark`，颜色与 Web 一致（输入翠绿、输出紫、缓存读天蓝、缓存写琥珀，04 §4.1#13），并配图例文字 · 属性行用 `LabeledContent`，**值为主色** · 复制用 `UIPasteboard`，配 `.sensoryFeedback(.impact(weight: .light))`，再加 toast“已复制”。

### 4.12 错误详情

```
┌──────────────────────────────────────────────┐
│ ‹ 日志                            [标记已处理] │ ← 工具栏主动作（L0，可撤销）
│ ┌─────┐                                       │
│ │ 429 │  限流                                  │
│ └─────┘  上游 · 服务商 · 今天 16:12             │ ← 阶段 · 归属方（词典）
│ claude-sonnet-4.5 → claude-sonnet-4-5-20250… │ ← 请求模型 → 上游模型
│ ┌────────────────────────────────────────┐    │
│ │ Rate limit exceeded for organization     │    │ ← 已脱敏，等宽，可选中
│ │ org-****. Please retry after 20s.         │    │
│ │                                  [复制]   │    │
│ └────────────────────────────────────────┘    │
│ 上游尝试 · 3 次                                  │
│ │ 1  ✕ 429   测试上游 A           0.31s      │ │ ← request-errors/:id/upstream-errors
│ │ 2  ✕ 429   claude-pro-07        0.28s      │ │
│ │ 3  ✕ 529   openai-key-3         1.02s      │ │
│ 耗时                                            │
│ │ 上游 0.31s · 响应 0.35s · 首字 —             │ │
│ 关联                                            │
│ │ ⛁ 测试上游 A          ⏳ 限流中 3:58       › │ │ ← 实时状态，一步去恢复
│ │ 👤 alice@example.com                      › │ │
│ │ ▦ 标准分组                                › │ │
│ 详细信息                                         │
│ │ 请求 ID     req_…                     ⧉   │ │
│ │ 平台        Anthropic                     │ │
│ │ 处理状态     未处理                          │ │
└──────────────────────────────────────────────┘
```

- **首屏**：状态码、分类、阶段、归属方和错误原文。原始枚举（upstream、upstream_error、openai）全部经过词典（修复 01 D11）。
- **已处理时**：工具栏改为“已处理”（禁用态），属性行显示“由 admin 于 16:20 标记”。`⋯` 菜单里提供“标记为未处理”。
- **上游尝试**：只有客户端失败（request-errors）才有这一节（P0 接口）。上游错误本身没有这一节。
- **SwiftUI**：同 4.11 · 消息块使用 `Text(message).font(.callout.monospaced()).textSelection(.enabled)`，放在 `secondarySystemBackground` 圆角容器里 · 工具栏 `ToolbarItem(placement: .confirmationAction)`。

### 4.13 渠道监控（监控 Tab）

```
┌──────────────────────────────────────────────┐
│ 监控                    [🕘 24 小时 ⌄]    (S) │
│ OpenAI 中转站 · 1 分钟前                        │
│ ┌ 服务健康 ─────────────────────────── › ┐   │ ← 运维开启时显示
│ │ 92 · 健康                                │   │ ← ≥90 健康 / 60–89 风险 / <60（04 §4.1#18）
│ │ 错误率 0.4% · SLA 99.8% · 上游 429 12 次   │   │
│ │ ─────────────────────────────────────  │   │
│ │ 🔔 2 条告警触发中                       › │   │
│ └────────────────────────────────────────┘   │
│ 渠道 · 10                                       │
│ ┌────────────────────────────────────────┐   │
│ │ ◐ Anthropic · 高级分组          性能下降  │   │ ← 问题渠道排在前面
│ │   成功率 96.1% · 首字 4.8s · 缓存 61%     │   │
│ │   ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮               │   │ ← 24 段状态条
│ ├────────────────────────────────────────┤   │
│ │ ● OpenAI · 标准分组                 可用  │   │
│ │   成功率 99.7% · 首字 0.9s · 缓存 72%     │   │
│ │   ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮               │   │
│ └────────────────────────────────────────┘   │
└──────────────────────────────────────────────┘

渠道详情（push）
│ ‹ 监控   Anthropic · 高级分组                    │
│ ◐ 性能下降 · 近 24 小时                          │
│ 成功率 96.1%   首字 P50 4.8s   缓存 61%          │
│ ▁▂▂▃▅▃▂▁ （成功率 / 首字趋势，chartXSelection）   │
│ 模型                                            │
│ │ ◐ claude-sonnet-4.5     成功率 95.0%        │ │
│ │ ● claude-haiku-4.5      成功率 99.9%        │ │
│ 错误分类                                         │
│ │ 限流或容量      ████████   62%               │ │ ← 13 类（02 §3.9）→ 中文
│ │ 超时           ███        21%               │ │
│ │ 该分组的账号                              › │ │ ← AccountList(group)
│ │ 错误请求                                  › │ │ ← Logs(group token)
```

- **数据**：
  - V2 模式：`channel-monitor-v2/overview`（02 §1.4）。每个渠道（平台 · 分组）有 `health`（reliability / latency）、`metrics`（success_rate、ttft、cache_rate）、`buckets`（状态条）和 `models`。后端 `service/channel_monitor_overview.go` 已确认这些字段。
  - V1 模式：`channel-monitors` 列表加 `:id/history`。行状态取 operational / degraded / failed / error，词典映射为“可用 / 性能下降 / 不可用 / 检测出错”。行滑动提供“立即检测”（`POST :id/run`，L0）。
- **排序**：不可用 → 性能下降 → 未知 → 可用。概览一次返回全部渠道，不分页，所以客户端排序在这里是正确的。
- **词典**：healthy = 可用、warning = 性能下降、critical = 不可用、unknown = 未知（04 §5 的裁决）。状态条颜色用语义色，无样本的段画为空心。VoiceOver 读作“过去 24 小时：22 段可用，2 段性能下降”。
- **时间**：90 分钟 / 24 小时 / 7 天 / 30 天，与 Web 渠道监控的预设一致（04 §4.1#25）。
- **只开了运维**：只显示服务健康卡、告警和吞吐趋势（复用 `PerformanceTrend`，只保留一层分段）。**只开了渠道监控**：不显示服务健康卡。
- **告警列表**（从这里或摘要进入）：行写“P1 · 错误率高于 5% · 标准分组 · 12 分钟前”，后缘滑动提供“标记已解决”（`PUT alert-events/:id/status`，L0）和“静默 1 小时”（`POST alert-silences`，L1）。告警只能定位到分组或平台（02 §3.8），所以详情里的动作是“查看分组账号”。
- **SwiftUI**：`ScrollView { VStack { OpsHealthCard; LazyVStack { ForEach(channels) { ChannelCard } } } }` · `ChannelCard` 用 `NavigationLink(value: Route.channel(ref))` · 状态条用 Swift Charts 的 `RectangleMark` 加 `.chartXAxis(.hidden)` · 详情趋势用 `LineMark` 加 `.chartXSelection(value:)`，选中值显示在头部（健康 App 写法，不需要“点选柱子查看数值”的提示）· 错误分类用 `RankingList`（屏幕使用时间式横条）。

### 4.14 分组列表 / 详情

```
分组列表（浏览 → 分组）
│ ‹ 浏览     分组                       [+] [⋯] │
│ 🔍 搜索分组                                     │
│ ● 标准分组                              ×1.2  │ ← 右侧是费率倍数
│   OpenAI · 按量 · 可用 10/12 · 限流 2           │
│ ● 高级分组                              ×2.0  │
│   Anthropic · 订阅 · 独占 · 可用 5/5            │
│ ⊖ 测试分组                              ×1.0  │ ← 停用：灰色（不是红色，04 §5）
│   OpenAI · 停用                                │

分组详情
│ ‹ 分组                                    [⋯] │
│ 标准分组                                        │
│ OpenAI · 按量 · 公开 · 费率 ×1.2                 │
│ ┌ 账号 ──────────────────────────────── › ┐  │
│ │ 可用 10 · 限流 2 · 共 12                  │  │
│ │ ▕██████████░░▏                           │  │
│ └────────────────────────────────────────┘  │
│ 容量                                            │
│ │ 并发   ▕████░░░▏            18 / 40        │ │
│ │ 会话   ▕██░░░░░▏             6 / 30        │ │
│ │ RPM    ▕███░░░░▏           120 / 400       │ │
│ 费用                                            │
│ │ 今日 $123.40 · 昨日 $310.20 · 累计 $9,812   │ │ ← groups/usage-summary（P1）
│ 限额                                            │
│ │ 日 $100.00 · 周 — · 月 $2,000.00 · RPM 不限   │ │
│ │ 错误请求                                  › │ │
│ │ 请求记录                                  › │ │
│ │ 统计分析                                  › │ │
│ │ 高级配置                       在 Web 中打开 ↗│ │ ← 模型路由、价格等（01 C76）
```

- 列表筛选（平台、状态）改为 Token，不再常驻在顶部（01 D30）。
- **`⋯` 菜单**：编辑…（sheet，沿用 §4.4 的范式）、停用分组 / 启用分组（L1；停用的确认写明“该分组的请求将无法调度”）、删除分组…（L2，destructive，放在最后）。
- 成功反馈用 toast，不再写成常驻的“处理结果”分区（01 D18）。
- **SwiftUI**：列表 `List.plain` 加 Token；详情 `List.insetGrouped`，容量用 `Gauge`。

### 4.15 统计分析

```
┌──────────────────────────────────────────────┐
│ ‹ 浏览     统计分析                         [⋯] │
│ [  今日  |  7 天  |  30 天  |  本月  ]          │ ← 分段带选中态（01 D27）
│ 🔍 [分组：标准分组 ×]  按账号、分组或用户…        │ ← 与日志共用的对象 Token
│ 实际收入                                         │
│ $8,420.15                                      │ ← 选中某个柱子时换成该时段的值
│ 10月10日–16日 · 日均 $1,202.88                   │
│ ▆▅▇▆█▇▆  ┈ 成本                                  │ ← 柱：实际；线：成本（单位写在标题里）
│ 成本 $5,210.00 · 差额 $3,210.15 · 标准 $9,800.00 │
│ 84.2K 次请求 · 312.4M Token · 平均 1.8s            │
│ 模型                                  全部 ›    │
│ │ claude-sonnet-4.5  ███████████  $4,210  50% │ │
│ │ gpt-4.1            █████        $1,980  24% │ │
│ 分组                                  全部 ›    │
│ │ 标准分组           ████████     $3,100  37% │ │
└──────────────────────────────────────────────┘
```

- **只有一个页面，带作用域**：从摘要的“今日收入”进入时预设为“今日”；从账号、分组或用户详情进入时，预先带上对象 Token。浏览目录是它唯一的独立入口（修复 01 D23 的 4 个入口）。
- “自定义范围…”放在 `⋯` 菜单里（medium 高度的 sheet），时区作为 sheet 的副标题写一行（01 C72）。
- 每个分区不再单独显示“更新于”，页面只在副标题保留一个更新时间。
- **SwiftUI**：`ScrollView` · `Picker(.segmented)` 放在 `safeAreaBar(edge: .top)` · Token 用 `.searchable` · `Chart { BarMark; LineMark }`，配 `.chartXSelection(value: $selected)`、`.chartYAxis { AxisMarks(format: .currency(code: "USD").presentation(.narrow)) }`，X 轴用 `AxisMarks(values: .stride(by: .day))` 并用格式化后的日期，修复 01 D27 原始字符串标签和逐柱标签的问题 · `RankingList`。

### 4.16 站点切换与登录

```
首次启动（没有已保存站点）
┌──────────────────────────────────────────────┐
│                  [App 图标]                     │
│               连接 Sub2 站点                     │
│ ┌────────────────────────────────────────┐    │
│ │ 站点地址      https://api.example.com     │    │ ← .textContentType(.URL)，域名即时校验
│ └────────────────────────────────────────┘    │
│ [               继续               ]           │
│ 凭据只保存在这台设备的钥匙串中。                      │ ← 唯一一句承诺（01 C01）
└──────────────────────────────────────────────┘

第 2 步（已读取 settings/public）
│ ‹                                              │
│        [站点 Logo]  OpenAI 中转站                 │ ← site_logo / site_name 自动带出（05 §4.12）
│                api.example.com                 │
│ [  账号密码  |  Admin Key  ]                     │
│ │ 邮箱        admin@example.com              │ │ ← .username，支持密码自动填充
│ │ 密码        ••••••••                        │ │ ← .password
│ [                登录                ]          │
│ （需要验证码时 → 单个 sheet：CaptchaView，复用）     │

第 3 步（两步验证）
│ 两步验证                                        │
│ 输入 a***@example.com 验证器中的 6 位验证码        │
│ [ _ _ _ _ _ _ ]                                 │ ← .oneTimeCode（“密码”App 可自动填充）

回访（有已保存站点：站点列表放在最前，修复 01 D33）
│ 选择站点                                        │
│ │ (O) OpenAI 中转站   admin@…    需重新登录   › │ │
│ │ (B) 备用站          ops@corp.cn            › │ │
│ [ 添加站点 ]                                     │
```

**站点面板（从头像打开，替代设置 Tab）**

```
┌──────────────────────────────────────────────┐
│                    站点                   完成 │
│ ┌────────────────────────────────────────┐    │
│ │ (O) OpenAI 中转站                          │    │
│ │     admin@example.com · 管理员              │    │
│ │     api.example.com                       │    │
│ │     在 Web 后台打开 ↗                        │    │
│ └────────────────────────────────────────┘    │
│ 切换站点                                         │
│ │ (B) 备用站                ops@corp.cn       │ │ ← 点按即切换（L0）
│ │ ＋ 添加站点                                   │ │
│ 待核对 · 1                                       │ ← 只在有待核对项时出现
│ │ 充值 $20.00 · alice@…        2 小时前      › │ │
│ 偏好设置                                         │
│ │ 隐藏金额                            [  ●]   │ │
│ │ 前台自动刷新                         [●  ]   │ │
│ ┌────────────────────────────────────────┐    │
│ │              退出登录                      │    │ ← L2 destructive
│ └────────────────────────────────────────┘    │
│ Sub2 Mobile 1.0.0                              │
└──────────────────────────────────────────────┘
```

- **站点名**：不再要求必填，默认取 `site_name`，没有就用域名，可以在站点面板长按改名（本地偏好，L0，不弹确认）。
- **角色提示**：vendor 或普通用户登录时，显示“这是代运营身份，当前版本暂只支持管理员”，或对应的普通用户文案。修复 05 §4.1 中 vendor 被误报为“普通用户”的问题。这类分流在 Sub2Core 的 `StationRole` 中完成。
- **切换**：点按其他站点后，关闭面板，主界面显示一个短暂的连接覆盖层“正在连接 备用站…”，随后重新推导 Tab，显示 toast“已切换到 备用站”。失败时 alert 标题为“无法连接 备用站”（不再统一叫“操作未完成”，01 D40），并保持在原站点。
- **删除站点**：站点行后缘滑动“删除”，L2，确认文案写明“将删除该站点和这台设备上的凭据”。
- **退出登录**：L2 confirmationDialog“退出 OpenAI 中转站？”。存在待核对项时，message 追加一句“这台设备上有 1 笔待核对的余额操作”，这是对资金安全必要的业务事实。
- **SwiftUI**：登录 `NavigationStack(path:)` 分步 push · `TextField(…).textContentType(.URL / .username / .password / .oneTimeCode)` · `SecureField` · 站点面板 `.sheet` 加 `NavigationStack { List(.insetGrouped) }` · `.presentationDetents([.large])` · 头像 `Menu(content:label:primaryAction:)` · `AsyncImage(url: siteLogo)`，失败时回退到首字母徽标。

### 4.17 设置 / 更多 → 浏览（搜索 Tab）

```
空闲态
┌──────────────────────────────────────────────┐
│ 搜索                                      (S) │
│ 🔍 账号、用户、分组或请求 ID                       │
│ 最近查看                                        │
│ [⛁ 测试上游 A] [👤 alice@…] [▦ 标准分组]  →       │ ← 横向胶囊，按站点保存
│ 排障                                            │
│ │ ≡ 日志                                    › │ │
│ │ 🔔 告警事件                            2   › │ │ ← 唯一允许的计数：触发中
│ 资源                                            │
│ │ ▦ 分组                                    › │ │
│ 经营                                            │
│ │ 📊 统计分析                                › │ │
│ 在 Web 后台                                      │
│ │ 系统设置                                  ↗ │ │
│ │ 告警规则                                  ↗ │ │
│ │ 渠道定价与支付配置                           ↗ │ │
│   [摘要] [账号] [用户] [监控]            (🔍)     │
└──────────────────────────────────────────────┘

输入态（范围：全部 / 账号 / 用户 / 分组 / 请求）
│ 🔍 alice                                       │
│ [ 全部 | 账号 | 用户 | 分组 | 请求 ]              │ ← searchScopes
│ 用户                                    全部 ›  │
│ │ 👤 alice@example.com            $128.50    │ │
│ 账号                                    全部 ›  │
│ │ ⛁ alice-relay-01           ✓ 正常          │ │
│ 请求                                            │
│ │ # 按请求 ID 查找“alice”                       │ │
```

- **结果来源**：用户用 `admin/users?search=`（可搜邮箱、用户名、备注、API Key）；账号用 `admin/accounts?search=`；分组用本地的 `groups/all`。识别到请求 ID 模式时，并行查询 `admin/usage?request_id=` 和 `ops/request-errors?request_id=`，只有一个结果时直接给出“打开”。
- 每个分组最多显示 3 条，“全部 ›”进入对应的列表页，并带上搜索词。
- 空结果用 `ContentUnavailableView.search(text:)`。
- “设置”这个概念消失：站点相关的设置在站点面板，App 偏好（隐藏金额、自动刷新）也在站点面板，按站点身份保存。
- **SwiftUI**：`Tab(value: .search, role: .search) { NavigationStack(path:) { BrowseView() } }` · 在 NavigationStack 内挂 `.searchable(text: $query, prompt:)` · `.searchScopes($scope, activation: .onSearchPresentation) {…}` · 根据 `@Environment(\.isSearching)` 切换目录和结果 · “最近查看”用 `ScrollView(.horizontal)` 加 `.buttonStyle(.bordered)`、`.buttonBorderShape(.capsule)`。

---

## 5. 交互规则

### 5.1 滑动、长按和上下文菜单的分配

原则：滑动只放 1 到 2 个最高频、**有明确目标对象**的动作；上下文菜单是滑动的超集，前几项与滑动一一对应（03 §1.7，“Match top menu actions to swipe actions”）；所有写操作都 `allowsFullSwipe: false`；菜单里的动作在详情页也一定能找到（HIG Context menus）。

| 对象行 | 前缘（右滑） | 后缘（左滑） | 上下文菜单（顺序） | 预览 |
|---|---|---|---|---|
| 账号 | 恢复状态（仅可恢复时） | 停止 / 启用调度、测试 | 恢复状态 · 停止/启用调度 · 测试连接… · 编辑… · 复制名称 · 只看此分组 | 迷你状态卡 |
| 用户 | 充值 | 禁用 / 启用 | 充值… · 退款… · 复制邮箱 · 错误请求 · 请求记录 · 禁用用户 | 余额卡 |
| 错误请求 | 标记已处理 / 未处理 | — | 标记已处理 · 复制请求 ID · 查看账号 · 查看用户 · 只看此账号 · 只看此用户 | 消息全文 |
| 用量明细 | — | — | 复制请求 ID · 查看账号 · 查看用户 · 只看此用户 | — |
| 告警事件 | — | 标记已解决、静默 1 小时 | 标记已解决 · 静默 1 小时 · 查看分组账号 | — |
| 渠道（V1） | — | 立即检测 | 立即检测 · 错误请求 | — |
| 分组 | — | 停用 / 启用 | 编辑… · 停用/启用 · 查看账号 · 删除分组…（最后，destructive） | — |
| 站点 | — | 删除 | 切换到此站点 · 重命名… · 删除站点 | — |

- 多选后长按：`contextMenu(forSelectionType:)`，菜单标题写“已选择 3 个账号”（HIG）。
- VoiceOver：`swipeActions` 会自动成为自定义操作；行另外通过 `accessibilityElement(children: .combine)` 合并为一句，例如“测试上游 A，限流中，3 分钟 58 秒后恢复，OpenAI，API Key”。

### 5.2 确认分四级

| 级别 | 适用 | UI | 按钮文案 | 实例 |
|---|---|---|---|---|
| **L0 即时** | 可逆的单对象操作；无副作用的恢复类操作；本地偏好 | 直接执行。成功后显示 toast，有逆操作时带“撤销”；`.sensoryFeedback(.success)`；有逆操作时注册 UndoManager（摇一摇 / iPad ⌘Z） | — | 单个账号停止/启用调度、恢复状态、标记已处理/未处理、渠道立即检测、告警标记已解决、保存编辑、切换站点、站点改名 |
| **L1 确认** | 可逆的批量操作；影响外部客户；会使凭据或令牌轮换 | `confirmationDialog`，**挂在触发控件上**（iOS 26 会从按钮处弹出），按钮**不用 destructive**，标题是“动词 + 对象 + 数量”，message 写站点名和最多 3 个对象名 | “停止调度 3 个账号”“禁用用户”“刷新令牌”“停用分组”“静默 1 小时” | 批量调度、批量恢复、禁用用户、停用分组、刷新令牌、静默告警 |
| **L2 警示** | 资金、不可逆、删除、清除凭据 | 资金类先走专用金额页（§4.9），再弹 destructive 的 `confirmationDialog`，写明对象和金额；删除类用 destructive 的 `confirmationDialog`，写明对象和后果 | “充值 $20.00”“退款 $5.00”“删除分组”“重置配额”“退出登录”“删除站点” | 充值、退款、删除分组、重置账号配额、退出登录、删除站点 |
| **L3 验证** | 服务端要求二次验证（`needsStepUp`） | 全局 `StepUpPresenter`：一个带 `TextField(.oneTimeCode)` 的 alert，不叠加 sheet。验证通过后**回到原来的 L1 或 L2 确认重新确认**，绝不自动重放 | “验证” | 创建或提升管理员（02 §1.6）、以后的导出类操作 |

- 统一实现：Sub2Core 中的 `ConfirmationPolicy.level(for: WriteIntent) -> ConfirmLevel` 是纯函数，有单元测试。UI 层的 `confirmable(_ intent:)` 修饰符根据级别决定弹什么。这样确认级别不会在各个页面里各写一套。
- 删除现状 8 个“确认保存 / 发送 / 执行 / 操作”式按钮。按钮文案一律描述结果（HIG Alerts）。

### 5.3 成功、失败、待核对的反馈（含触觉）

| 结果 | 视觉 | 触觉 | 停留 | VoiceOver |
|---|---|---|---|---|
| 成功 | 底部浮动 toast（胶囊，控件层，可以用 `.glassEffect(.regular, in: .capsule)`），图标 + 一句结果 + 可选“撤销” | `.success` | 4 秒，手指按住时暂停计时 | `AccessibilityNotification.Announcement("已停止调度").post()` |
| 明确失败（被拒绝） | **原位**提示：行内或表单内的错误文本，开关回弹；不用 alert 也不只用 toast | `.error` | 直到用户修改或重试 | 播报错误原因 |
| 结果不明（待核对） | 常驻的 `PendingVerificationBanner`（琥珀）；全局底部附件“1 项操作待核对 ›”（iOS 26.1 `tabViewBottomAccessory(isEnabled:)`）；摘要“需要处理”中也有一项 | `.warning` | 直到核对完成 | 播报“未收到站点确认，需要核对” |
| 批量 | 全部成功显示 toast；否则显示结果 sheet（§4.6） | 依最差结果 | — | — |
| 复制 | toast“已复制” | `.impact(weight: .light)` | 1.5 秒 | — |
| 达到上限 / 不可执行 | toast 说明原因 | `.warning` | 3 秒 | — |

- 只有在**收到服务端确认后**才给成功触觉，点按瞬间不给，避免“假成功”。
- 文案只说结果，不说机制。例如不写“系统不会自动重放写入请求”（01 C54）。机制的保证放在测试里（§12.4）。
- `FeedbackCenter` 是 `@Observable` 的全局对象，挂在 `RootTabs` 的 `.overlay(alignment: .bottom)` 上，位置在 Tab 栏之上，同一时间只显示一条，新的会替换旧的。

### 5.4 撤销

- 只为 **L0 且存在精确逆操作**的写入提供撤销：调度开关（逆操作是反向开关）、标记已处理（逆操作是标记未处理）、告警标记已解决（没有可靠的逆操作，不提供撤销）、恢复状态（没有逆操作，不提供撤销）。
- 撤销本身是一次新的写入，有自己的反馈；如果撤销的结果不明，同样进入待核对。
- 同时注册 `UndoManager`（`@Environment(\.undoManager)`）。iPhone 上摇一摇会弹出系统的“撤销停止调度”，iPad 上支持 ⌘Z。这是“如果 Apple 来做”的原生细节，几乎不需要额外代码。
- toast 消失后，仍然可以通过 UndoManager 撤销，直到发生下一次写入或切换站点（切站时清空撤销栈）。

### 5.5 未保存草稿保护

- 所有编辑 sheet 都使用 `EditSheet` 骨架：`draft` 与 `original` 不同时视为 `isDirty`；`.interactiveDismissDisabled(isDirty || isSubmitting)`。
- 有改动时点“取消”或下滑关闭，弹出 confirmationDialog“放弃更改？”，选项为“放弃更改”（destructive）和“继续编辑”（HIG Sheets）。
- 金额页：输入了金额就算 dirty。
- App 进入后台不丢草稿（内存保留）。被系统杀进程时草稿丢失，这是可以接受的；资金类的待核对记录已经持久化。
- 有编辑中的 sheet 时，站点面板打不开（sheet 是模态的），也就从结构上避免了“草稿属于哪个站点”的问题。

### 5.6 Sheet 使用规则

1. **主界面同一时间只能有一个 sheet**（HIG Sheets）。sheet 内部的后续步骤用 sheet 自己的 `NavigationStack` push（例如分组多选、充值的待核对态）。
2. sheet 只承载**有边界的任务**：编辑、充值/退款、账号测试、批量结果、自定义时间范围、站点面板、新建用户/分组、验证码。查看对象详情一律用 push，不用 sheet。
3. 确认用挂在按钮上的 `confirmationDialog`；二次验证用 alert；筛选用 `Menu` 加 Token，不再有“筛选 sheet”。
4. 高度：编辑和金额页用 `.large`（需要键盘）；测试和批量结果用 `[.medium, .large]`；自定义时间范围用 `.medium`。都不设置 `presentationBackground`（03 §1.6）。
5. 提交后：成功则关闭 sheet 并显示 toast；被拒绝则留在原地；结果不明则锁定并显示待核对。
6. 消除现在 7 处各自挂载的 `StepUpView` sheet，统一由 `StepUpPresenter` 处理（01 §6.2）。

### 5.7 返回栈与跨对象跳转

```swift
enum Route: Hashable {
    case accountList(AccountListScope), account(Int), accountEditHistory(Int)
    case user(Int), balanceHistory(userID: Int), userKeys(userID: Int)
    case group(Int), groupList
    case logs(LogQuery), request(RequestRef), error(ErrorRef)
    case analytics(AnalyticsQuery)
    case channel(ChannelRef), channelList(ChannelScope), alerts(AlertScope), alert(Int)
    case pendingList
}
@Observable final class Router { var selectedTab: AppTab; var paths: [AppTab: NavigationPath]; func open(_ r: Route) }
```

- **规则 1：跨对象跳转在当前 Tab 的栈内 push**，不自动切换 Tab（健康和邮件都是这样）。从摘要点“账号受限”，push 的是摘要栈里的账号列表，返回时回到摘要。只有外部深链（以后的通知或 URL scheme）才切换 Tab。
- **规则 2：去重**。`Router.open(route)` 发现当前路径里已经有同一个对象路由时，就 pop 回那一层，而不是再 push 一层。例如“账号 → 错误 → 该账号”会回到原来的账号页。这从结构上消除了 01 §1 发现的“分组 → 账号 → 日志 → 账号……”环。
- **规则 3**：再次点按当前 Tab 时回到根页（保持系统默认行为）；当前 Tab 用 `@SceneStorage` 恢复。
- **规则 4**：列表行和关联行的点击目标都是 `NavigationLink(value: Route)`，不再写 `NavigationLink { Destination(…) }` 这种闭包式跳转，便于以后接深链和 iPad 分栏。

### 5.8 刷新与新鲜度

- 每个页面只有一种手动刷新方式：下拉刷新（`.refreshable`）。删除所有“刷新××”按钮（01 D19）。
- 前台自动刷新：摘要、监控和可见的账号列表每 30 秒刷新一次；进入选择模式、展开滑动或编辑时暂停；进入后台时停止。站点面板里可以关闭。
- 新鲜度只在一个地方显示：根页的 `navigationSubtitle` 写“站点名 · 2 分钟前”；二级页在数据过期时才显示 `StaleBanner`。每个分区不再各自写“更新于”（01 D20）。

---

## 6. 状态体系（统一组件）

| 状态 | 组件 | 呈现 | 不再出现的写法 |
|---|---|---|---|
| 首次加载 | `SkeletonList(count:)` / 卡片 `.redacted(reason: .placeholder)` | 用真实行组件加占位数据渲染 6 行骨架；摘要卡显示骨架；超过 10 秒仍在加载时，副标题写“仍在载入…” | 26 处 `ProgressView("正在…")`（01 D29） |
| 空 | `EmptyState`（`ContentUnavailableView`） | 标题加一个动作，例如“没有限流中的账号”配“查看全部账号”；有筛选时配“清除筛选”；搜索为空时用 `.search(text:)` | 一行灰字 |
| 一切正常 | `AllClearRow` | 摘要里的一行“✓ 一切正常 · 2 分钟前检查”，不占整页 | — |
| 整页错误 | `ErrorState` | `ContentUnavailableView("无法载入账号", systemImage: "wifi.exclamationmark")`，description 写业务原因（例如“站点没有响应”），按钮“重试” | 红字 + “重试读取” |
| 部分失败 | `SectionFailureRow` | 在失败的分区内显示一行：`Label("今日用量未能载入", systemImage: "exclamationmark.triangle")` 加“重试”，其余分区照常显示 | 同时出现“重试”和“刷新费用”（01 D19） |
| 数据过期（刷新失败但有旧数据） | `StaleBanner`（放在 `safeAreaBar(edge: .top)`） | “未能刷新 · 显示 10:24 的数据”加“重试”，琥珀色图标；旧数据保持完整可用 | “保留上次成功加载的记录。”（01 C63） |
| 待核对 | `PendingVerificationBanner` + `PendingAccessory` | 对象内是琥珀横幅（原因、对象、金额、“核对”）；全局是底部附件；摘要中有对应的需要处理项 | 锁定表单加一大段说明 |
| 权限不足 | `PermissionState` | `ContentUnavailableView("没有权限", systemImage: "lock")`，description 写“当前身份无法查看此内容”；通常不会出现，因为模块已按角色裁剪，只在运行时收到 403 时兜底 | “操作未完成” |
| 站点未开启该功能 | `FeatureOffState` | `ContentUnavailableView("此站点未开启渠道监控", systemImage: "antenna.radiowaves.left.and.right.slash")`，按钮“在 Web 后台开启 ↗”；只在会话中途功能被关闭时出现 | 关于“接口”的说明（01 C24） |
| 字段缺失 | `MissingValue`（`Text("—")`） | “—”使用次要色；`.accessibilityLabel("未返回")`；整行都缺失时省略这一行 | 42 处“不可用” |
| 会话失效 | 全局 | 回到站点选择页，并在对应站点行显示“需重新登录” | 全局 alert |
| 二次验证 | `StepUpPresenter` | 带输入框的 alert（§5.2 L3） | 7 处各自挂载的 sheet |

- 这些组件都以 `LoadState<Value>` 为输入（由 `DashboardLoadState` 抽出并泛化：idle / loading / loaded(value, at) / failed(error, last: value?)）。页面只需要写 `StateContainer(state) { value in … }`。
- 错误文案由 Sub2Core 的 `ErrorPresentation`（合并 01 §6.2 中的 4 套分类规则）根据 `APIError.kind` 给出**业务句**。APIError 现有消息里的契约语（例如“请保留原操作编号后重试”“写操作结果可能尚未确认，请勿新建重复操作”）不直接显示，改由待核对状态机来表达。

---

## 7. 账号状态模型

### 7.1 四个维度

| 维度 | 字段（02 §3.1） | 取值 → 文案 · 色调 · 符号 | 恢复动作 |
|---|---|---|---|
| ① 管理状态 | `status` | active → （不单独显示）· inactive / disabled → **停用** · 中性 · `minus.circle.fill` · error → **错误** · 严重 · `exclamationmark.octagon.fill` | 错误 → 恢复状态（`recover-state`）；停用 → 在 Web 中处理 |
| ② 调度开关 | `schedulable` | false → **暂停** · 中性 · `pause.circle.fill` | 启用调度（`POST :id/schedulable`） |
| ③ 限时运行状态（带截止时间） | `rate_limit_reset_at` | > now → **限流中** · 注意 · `hourglass` · “3:58 后自动恢复” | 恢复状态 |
|  | `overload_until` | > now → **过载中** · 严重 · `flame.fill` · “12:40 后自动恢复” | 恢复状态 |
|  | `temp_unschedulable_until` + `temp_unschedulable_reason`（JSON：status_code、matched_keyword、error_message） | > now → **临时不可调度** · 注意 · `clock.badge.exclamationmark` · 原因“命中关键词 ‘quota’ · 502” | 恢复状态 |
|  | `extra.model_rate_limits[model].rate_limit_reset_at`（键 `AICredits` 表示积分耗尽；`extra.allow_overages`） | 有未到期项 → **n 个模型限流** · 特殊（紫）· `square.stack.3d.down.forward`；积分耗尽 → 严重；正在走积分 → 注意 | 恢复状态 |
|  | `quota_*_used ≥ quota_*_limit` | **配额超限**（写明是日、周还是总配额）· 注意 · `gauge.with.dots.needle.100percent` | 重置配额（`reset-quota`，L2） |
|  | `session_window_status` | allowed_warning → “5 小时窗口接近上限” · 注意；rejected → “5 小时窗口已满” · 注意 | 无（到期恢复） |
| ④ 有效期 | `expires_at` + `auto_pause_on_expired` | 已过期 → **已过期** · 中性 · `calendar.badge.exclamationmark`；7 天内 → 附注“6 天后到期”（注意） | 在 Web 中处理 |

### 7.2 判定（Sub2Core，纯函数）

```swift
public struct AccountCondition: Sendable, Equatable {
    public enum Kind: String, Sendable { case rateLimited, overloaded, error, tempUnschedulable, inactive, expired,
                                         quotaExceeded, paused, modelLimited, sessionWindow, normal }
    public let kind: Kind; public let title: String; public let tone: StatusTone; public let symbol: String
    public let deadline: Date?; public let reason: String?; public let recovery: RecoveryAction?
}
public enum AccountConditionModel {
    /// 主状态的优先级与 Web AccountStatusIndicator 一致：
    /// 限流/过载 > 错误 > 临时不可调度 > 非 active（停用/过期）> 配额超限 > 暂停 > 正常（04 §4.1#6）
    public static func evaluate(_ a: UpstreamAccount, now: Date, serverClockOffset: TimeInterval) -> (primary: AccountCondition, secondary: [AccountCondition])
}
```

- **时钟**：剩余时间按 `deadline − (now + serverClockOffset)` 计算。`serverClockOffset` 取自最近一次响应头 `Date` 与本机时间的差值，避免设备时钟偏差让倒计时出错。
- **测试**：每种组合都有一个 fixture，包括主状态与次要状态并存、截止时间已过、`disabled` 这种未映射值、JSON 原因解析失败（回退为“原因未返回”，界面显示“—”）。这些单元测试替代现在界面上的契约文字（R2）。

### 7.3 在行、详情和筛选中的呈现

| 位置 | 呈现 |
|---|---|
| 列表行 | 第 1 行左侧是主状态的 `StatusGlyph`；右侧尾注是截止倒计时（限流、过载、临时不可调度）或“停用 / 暂停”；第 3 行写原因（错误、临时不可调度）。次要状态不在行里展开，只在主状态是“正常”或“暂停”且存在模型限流时，在第 3 行写“2 个模型限流”。 |
| 详情英雄卡 | 主状态大标题、倒计时、原因、次要状态列表（每个一行，带各自的倒计时）、由 `recovery` 决定的主按钮（§4.3） |
| 调度开关 | 独立的 Toggle，与状态分离（05 §3#3：正常账号也可以暂停调度） |
| 根页状态卡 | 错误 / 限流中 / 临时不可调度 / 暂停（另有：过载中，需运维开启；停用，在“全部”下面） |
| 筛选 Token | 状态：正常 / 停用 / 错误 / 限流中 / 临时不可调度 / 暂停，对应服务端的 `active / inactive / error / rate_limited / temp_unschedulable / unschedulable` |
| 摘要 | “n 个账号受限：错误 a · 限流 b · 过载 c”，数据来自 `dashboard/stats`；“最早 x 后恢复”只在有完整数据时显示 |
| Tab 徽标 | 账号 Tab `.badge(错误 + 过载)` |
| VoiceOver | “限流中，3 分钟 58 秒后自动恢复”。倒计时元素用 `.accessibilityLabel` 给出完整句子，不读秒级的跳动 |

---

## 8. 组件清单

### 8.1 Sub2Core（逻辑与语义，可单测）

| 组件 | 职责 | 输入 → 输出 | 来源 |
|---|---|---|---|
| `Glossary` | 唯一的枚举词典：账号/用户/分组/Key/订阅状态、平台、认证类型、请求类型、错误阶段/归属方/分类、渠道健康、余额记录类型、角色 | rawValue → `Term(title, short, tone, symbol, definition?)` | 由 `AccountPresentation`、`GroupPlatform.title`、`AdminUserRole.title` 合并而来 |
| `StatusTone` | 5 种色调：positive / caution / critical / neutral / special | — | 新增 |
| `AccountConditionModel` | §7 的判定 | `UpstreamAccount, now` → primary + secondary | 新增（需要 P0 字段） |
| `Sub2Format` | 唯一的格式化入口：金额（窄 `$`、千分位、两位小数或小额自适应）、Token（K/M，最多 1 位小数，详情页显示精确值）、相对时间、时长、日期分节标题 | `Decimal / Int / Date` → `String` | 由 `DashboardPresentation` 扩展而来，取代 `Components.money` |
| `Capabilities` + `ShellLayout` | §2.2 的 Tab 推导 | 角色 + 开关 → `[AppTab]` | 新增 |
| `AppModule` 注册表 | 浏览目录的分类、可用性、外链路径 | `Capabilities` → `[CatalogSection]` | 新增 |
| `AttentionRule` | 摘要中“需要处理”的规则与排序 | 各数据源快照 → `[AttentionItem]` | 新增 |
| `ConfirmationPolicy` | §5.2 的级别 | `WriteIntent` → `ConfirmLevel` | 新增 |
| `WriteCoordinator` 状态机 | prepared → confirming → inflight → succeeded / rejected / uncertain → reconciled | — | 由 01 §6.2 中的 4 份状态机抽出合并 |
| `ErrorPresentation` | 错误分类加业务文案（合并 `needsStepUp` 等 4 套规则） | `Error` → `(kind, message, isUncertain, needsStepUp)` | 合并 |
| `LogToken` / `LogQuery` | Token 与 `RequestLogFilter` 双向映射，标记各数据源支持哪些条件 | — | 由 `RequestLogFilter` 扩展而来 |
| `PagedLoader<T>` | 通用分页：刷新已加载的页、去重、请求票据、代际守卫 | — | 合并 4 份实现（01 §6.2） |

### 8.2 NativeApp（视图）

| 组件 | 职责 | 输入 | SwiftUI 实现 |
|---|---|---|---|
| `RootTabs` | 外壳 | `[AppTab]`, `Router` | `TabView(selection:)` + `Tab` / `Tab(role: .search)` + `TabSection` + `.tabViewStyle(.sidebarAdaptable)` + `.tabViewBottomAccessory(isEnabled:)`（26.1） |
| `SiteAvatarButton` / `SiteSheet` | 站点上下文与切换 | profiles, active | `Menu(content:label:primaryAction:)`、`.sheet`、`List(.insetGrouped)` |
| `StatusGlyph` / `StatusBadge` | 状态符号和徽标 | `Term` / `AccountCondition` | `Image(systemName:).symbolRenderingMode(.hierarchical).foregroundStyle(tone.color)`；徽标用 `Text` 加胶囊形 `tone.color.opacity(0.15)` 背景，不用玻璃 |
| `ConditionCountdown` | 截止时间倒计时 | deadline | `Text(timerInterval:countsDown:)` + `TimelineView(.explicit)` |
| `AccountRow` / `UserRow` / `GroupRow` / `ErrorLogRow` / `UsageLogRow` / `ChannelCard` / `TransactionRow` / `AlertRow` / `KeyRow` | 固定解剖的对象行 | 领域模型 | `HStack(alignment: .firstTextBaseline)` + `ViewThatFits` + `.monospacedDigit()` |
| `SmartCountCard` | 提醒事项式计数卡 | `Term`, count, route | `NavigationLink(value:)` + `.contentTransition(.numericText)` |
| `SummaryCard` | 健康式卡片外框（标题、更新时间、`›`） | title, symbol, date, route, content | `VStack` + 连续圆角背景 + `NavigationLink` |
| `HeroMetric` | 大数 + 对比 | value, delta, caption | `.font(.system(.largeTitle, design: .rounded))` + `.privacySensitive()` |
| `CapacityRow` | 用量 / 上限 | used, limit, thresholds | `Gauge(.accessoryLinearCapacity)` + 文字数值 |
| `TrendChart` | 趋势图（保留现有交互引擎，去掉周围 10 个辅助元素） | series | Swift Charts + `chartXSelection` + `chartScrollableAxes` |
| `StatusStrip` | 24 段健康条 | buckets | `Chart { RectangleMark }` |
| `RankingList` | 屏幕使用时间式排名 | items | `Gauge` / `GeometryReader` 横条 + `.monospacedDigit()` |
| `DetailHero` | 对象头部状态卡和动作 | condition, actions | `Section` + `.listRowBackground(tone.background)` + `.bordered` / `.borderedProminent` |
| `PropertyRow` | 属性行（值为主色，缺失显示“—”） | label, value? | `LabeledContent` + `.foregroundStyle(.primary)` |
| `RelatedLink` | 跨对象入口 | symbol, title, count?, route | `NavigationLink(value:)` |
| `TermInfoButton` | 口径弹层 | `Term.definition` | `.popover` + `.presentationCompactAdaptation(.popover)` |
| `TokenSearch` | Token 加联想 | tokens, suggestion provider | `.searchable(text:tokens:)` + `.searchSuggestions` + `.searchCompletion` |
| `TimeRangeMenu` | 时间预设与自定义 | range | `Menu { Picker; Button("自定义…") }` |
| `SelectionToolbar` | 批量底栏 | selection, actions | `ToolbarItemGroup(.bottomBar)` + `.toolbarVisibility(.hidden, for: .tabBar)` |
| `BatchResultSheet` | 逐项结果 | `AccountBulkReply` 等 | `List` + `DisclosureGroup` |
| `AmountEntrySheet` | 充值 / 退款 | user, operation | §4.9 |
| `EditSheet` | 编辑骨架（dirty、保存、放弃确认、待核对锁定） | draft, original, submit | `NavigationStack { Form }` + `.interactiveDismissDisabled` |
| `StepUpPresenter` | 全局二次验证 | 由 `WriteCoordinator` 触发 | `.alert` + `TextField(.oneTimeCode)` |
| `FeedbackCenter` / `Toast` | toast、触觉、撤销 | `FeedbackEvent` | `.overlay` + `.glassEffect(in: .capsule)` + `.sensoryFeedback` + `UndoManager` |
| `PendingVerificationBanner` / `PendingAccessory` | 待核对 | pending items | 横幅：`Section`；附件：`tabViewBottomAccessory` |
| 状态组件 | §6 | `LoadState` | `ContentUnavailableView`、`.redacted` |

### 8.3 复用与废弃

**原样复用**（01 §6.1）：`APIClient` 及各扩展、查询模型、写请求模型与校验（`AccountUpdateRequest`、`PendingBalanceOperation`、`PendingUserUpdateOperation` 等）、`DashboardPresentation`（并入 `Sub2Format`）、`DashboardTrend`、`PerformanceTrend`、`RequestLogPresentation.safeMessage`、`SSEParser`、`CaptchaView` 和 `CaptchaBridgeValidator`、`AppModel` 的会话代际守卫、凭据租约、待核对余额持久化、`ListFieldSelection` 的按身份存储（改用于“最近处理”“最近查看”“日志分段偏好”）。

**抽出后复用**（01 §6.2）：`DashboardLoadState` → `LoadState`；4 份分页 → `PagedLoader`；4 份写入状态机 → `WriteCoordinator`；4 套错误分类 → `ErrorPresentation`；`DashboardTrendChart` 的交互引擎 → `TrendChart`；`StepUpView` 的逻辑 → `StepUpPresenter`；`sanitizedTestOutput` 移入 Core；`FailureView` → `ErrorState`；`ListFieldFlow` → Token 或标签换行。

**废弃**：`LabeledValue`（值被灰化）、`MetricView`（固定高度加 `minimumScaleFactor`，03 A13）、`ManagementView`、`SettingsView`（→ `SiteSheet`）、`ListFieldEditor` 的 UI 和“自定义显示字段”（行解剖固定，01 D25）、`Components.money`、全部 Feature 页的 List/Section 骨架与行、全部 footer 和 caption 说明文字（01 §5）、全局“操作未完成” alert、各页手动“刷新××”按钮、`.tabItem`（iOS 27.2 标记弃用）。

---

## 9. 数据层依赖（按优先级）

> “02 §x”是能力盘点中对应的章节。以下接口都已在后端路由中确认存在（`backend/internal/server/routes/admin.go`）。

### P0：阶段 0–3 必需，没有它们新界面画不出来

| # | 项 | 类型 | 接口 / 字段 | 用于 | 02 章节 |
|---|---|---|---|---|---|
| 1 | 账号限时运行状态 | 新字段 | `UpstreamAccount` 增加 `rate_limited_at`、`rate_limit_reset_at`、`overload_until`、`temp_unschedulable_until`、`temp_unschedulable_reason`（解析 JSON）、`auto_pause_on_expired`、`extra.model_rate_limits`、`extra.allow_overages`；`status` 增加对 `disabled` 的映射。已确认 `lite=true` 列表也带这些字段（`dto.AccountListItem`） | §7 全部、账号行和详情 | §3.1 C、§6.1-1/2 |
| 2 | 统一恢复 | 新接口 | `POST admin/accounts/:id/recover-state`（清除错误、限流、过载、临时不可调度、模型限流，并返回最新账号）；`POST :id/reset-quota` | 恢复状态、重置配额 | §1.2 状态恢复动作 |
| 3 | 账号状态计数 | 参数 | `GET admin/accounts?status=…&page_size=1&lite=true` 读 `total`；`AccountListQuery` 增加可选 `pageSize` | 账号根页状态卡 | §1.2、§3.1（派生筛选值） |
| 4 | 仪表盘账号计数 | 新字段 | `DashboardStats` 增加 `ratelimit_accounts`、`overload_accounts` | 摘要“账号受限” | §5 仪表盘账号计数 |
| 5 | 站点能力 | 新字段 / 新接口 | `PublicSettings` 增加 `site_name`、`site_logo`、`channel_monitor_enabled`、`channel_monitor_mode`、`payment_enabled`、`subscription_enabled`、`risk_control_enabled`、`affiliate_enabled`；`GET admin/settings` 只解码 `ops_monitoring_enabled`，其余字段丢弃；令牌登录读 `auth/me.role` | Tab 推导、登录自动带出站点名和 Logo | §1.6、§6.3 |
| 6 | 日志对象联想 | 新接口 | `GET admin/usage/search-users`、`GET admin/usage/search-api-keys`（另用现有的 `admin/accounts?search=` 和 `groups/all`） | Token 联想替代 ID 输入 | §1.3 使用记录 |
| 7 | 错误处置与重试链 | 新接口 | `PUT admin/ops/request-errors/:id/resolve`、`PUT admin/ops/upstream-errors/:id/resolve`、`GET admin/ops/request-errors/:id/upstream-errors` | 标记已处理、上游尝试 | §1.1 错误日志 |
| 8 | 用户余额记录 | 新接口 / 新字段 | `GET admin/users/:id/balance-history`（items：type、value、notes、created_at；`total_recharged`）；`AdminUser` 增加 `frozen_balance` | 用户详情钱包卡、余额记录 | §1.2 用户、§3.2 |
| 9 | 错误计数 | 参数 | `ops/request-errors?resolved=false&page_size=1`，起点为 1 小时前，读 `total`；账号、分组、用户维度同样处理 | 摘要“未处理错误”、关联行计数 | §5 错误日志待处理 |

### P1：阶段 4–5，监控、告警、分组、分析

| # | 项 | 接口 | 用于 | 02 章节 |
|---|---|---|---|---|
| 10 | 运维总览字段 | `admin/ops/dashboard/overview` 增加解码 `health_score`、SLA、上游 429/529 计数（现在只取了 `error_rate` 和 `qps`） | 监控 Tab 服务健康卡 | §1.1 看板、§5 健康评分 |
| 11 | 告警事件 | `GET ops/alert-events?status=firing`、`GET :id`、`PUT :id/status`、`POST ops/alert-silences` | 摘要、告警列表、监控 | §1.1 告警、§3.8 |
| 12 | 账号可用性 | `GET ops/account-availability` | “最早 x 后恢复”、过载中卡片 | §1.1 实时信号、§5 |
| 13 | 渠道监控 | V2：`channel-monitor-v2/overview`、`snapshot`、`errors`；V1：`channel-monitors`、`:id/history`、`POST :id/run` | 监控 Tab | §1.4、§3.9 |
| 14 | 分组费用 | `GET admin/groups/usage-summary` | 分组列表和详情的“今日 / 昨日 / 累计” | §1.2 分组 |
| 15 | 可测模型 | `GET admin/accounts/:id/models` | 测试 sheet 的模型菜单 | §1.2 账号查询 |

### P2：后续模块

`GET admin/accounts/:id/usage`（上游 5h/7d 窗口）、`scheduled-test-plans` 结果、`proxies`（代理模块）、`users/:id/subscriptions` 与订阅动作、`admin/payment/orders?status=REFUND_REQUESTED`（退款申请会成为“需要处理”的一项）、`admin/workspaces/me`（vendor 的 Tab 推导）、`accounts/batch-refresh`、`batch-clear-error`。

### 不需要接口的 Core 工作（与 P0 同步）

`Glossary`、`AccountConditionModel`、`Sub2Format`、`Capabilities` / `ShellLayout`、`AttentionRule`、`ConfirmationPolicy`、`WriteCoordinator`、`ErrorPresentation`（含把 `APIError` 内置消息改写为业务句）、`LogToken`、`PagedLoader`；`DemoData` 补齐 fixture：每种账号状态各一个账号（截止时间相对当前时间生成）、三种角色、各种开关组合、待核对余额、批量部分失败、流式测试的成功、失败和中断，供下一轮在 Mac 模拟器上做原型。

---

## 10. iPad：本轮“能用”，后期深度适配

### 10.1 本轮

- **外壳**：`.tabViewStyle(.sidebarAdaptable)`。侧栏中，4 个主 Tab 之后放一个 `TabSection("浏览") { Tab("日志") ; Tab("分组") ; Tab("统计分析") ; Tab("告警事件") }`，这些 Tab 只在侧栏显示（`.tabPlacement(.sidebarOnly)` 或 `.defaultVisibility(.hidden, for: .tabBar)`，属于 iOS 18 API，实施时在 Xcode 27 核对写法）。这样 iPad 用户不必经过搜索 Tab 就能进入日志；iPhone 上它们仍在浏览目录里。
- **对象 Tab**（账号、用户、日志、分组、监控）：在 Tab 内使用 `NavigationSplitView { 列表列 } detail: { NavigationStack(path:) { 详情 } }`，列表的 `List(selection:)` 驱动详情列。紧凑宽度下自动折叠为单栏栈，iPhone 代码路径不变。
- **摘要**：`LazyVGrid(columns: [GridItem(.adaptive(minimum: 340))])`，宽屏时卡片自动排成两列；内容最大宽度约 1000pt。
- **sheet**：`.presentationSizing(.form)`（iOS 18）。
- **键盘**：⌘R 刷新，⌘F 聚焦搜索，⌘Z 撤销（UndoManager 自动支持），Esc 关闭 sheet。
- **验收**：iPad 模拟器上横竖屏各截一组图；分栏可以使用；没有被拉宽的单列布局；sheet 不会铺满整屏。

### 10.2 后期预留

| 能力 | 预留点 |
|---|---|
| 日志和账号的多列 `Table` | 行组件的数据已经抽成 `LogRowModel` / `AccountRowModel`，`Table` 的列直接取用 |
| 请求详情放在 `.inspector` 侧栏 | `Route.request` 的详情视图不依赖导航栈，可以嵌入 inspector |
| 多窗口（每个窗口一个站点） | `Router` 和 `SessionContext` 已按场景隔离；以后用 `WindowGroup(for: ProfileID.self)` |
| 指针悬停、拖放（拖出请求 ID 或邮箱） | 行组件统一使用 `.hoverEffect` 和 `.draggable(String)` 的挂载点 |
| 侧栏自定义 | `TabViewCustomization`（iOS 18），同时保持 HIG 默认不超过 5 个 |

---

## 11. 未来扩展：普通用户端与 vendor 端

### 11.1 骨架层面

- **外壳**：`ShellLayout.tabs(for:)` 已经覆盖三种角色（§2.2），新增角色只需要新增规则和对应的根视图，不需要改 `RootTabs`。
- **登录**：`StationRole` 取代 `administratorRequired` 的硬拦截。在某个角色的端还没上线前，`AppModule` 中该角色的可用模块为空，登录页给出对应的提示（§4.16）。上线后直接落地到该角色的第一个 Tab。
- **站点面板**：多站点、多身份机制不变，只是在身份行上显示角色。

### 11.2 组件复用表

| 未来页面 | 复用组件 | 数据（02 §2） |
|---|---|---|
| 用户首页：余额、今日消费、订阅进度 | `SummaryCard`、`HeroMetric`、`CapacityRow`（订阅日/周/月额度）、`AttentionRule`（余额不足、Key 即将过期） | `usage/dashboard/*`、`subscriptions/progress` |
| 密钥 | `KeyRow`、`CapacityRow`（5h/1d/7d 限额）、`StatusBadge`（Key 的 4 种状态）、`EditSheet`、复制反馈 | `keys`、`user/api-keys/:id/usage/daily` |
| 用量与错误 | `UsageLogRow`、`ErrorLogRow`（受 `allow_user_view_error_requests` 开关控制）、`TokenSearch`（按 Key、模型）、`TimeRangeMenu`、按日分节 | `usage`、`usage/errors` |
| 渠道状态 | `ChannelCard`、`StatusStrip` | 用户侧 `channel-monitor-v2/*` |
| 余额记录、兑换 | `TransactionRow`、`AmountEntrySheet` 的结构（兑换码输入） | `redeem/history`、`POST redeem` |
| 充值与订单 | 只做“在 Web 中打开”（App Store 审核指南 3.1.1，02 §2） | — |
| vendor：账号、分组、代理、用量 | 与 admin 完全相同的行和详情组件；权限不足的动作按 `VendorPermission` 隐藏，不置灰（HIG Context menus：“Hide unavailable menu items”） | `vendor_routes.go` 白名单（02 §1.6） |

---

## 12. 迁移分期与风险

### 12.1 分期

| 阶段 | 内容 | 交付与验收 | UITest |
|---|---|---|---|
| **0 基础**（界面不变） | 部署目标提到 iOS 26；完成 §8.1 全部 Core 组件；P0 #1–#9 解码与接口；`ErrorPresentation` 改写错误文案；`DemoData` 补 fixture；文案 lint 落地 | Core 单测全部通过；契约测试替代清单（§12.4）完成 | 保持现有 35 个用例可运行 |
| **1 外壳** | `RootTabs`（Tab API、搜索 Tab、`sidebarAdaptable`）、`SiteAvatarButton` / `SiteSheet`（替代设置）、浏览目录、`Router` 与去重、`FeedbackCenter`、`StepUpPresenter`、§6 状态组件。旧页面先挂到新外壳里，ManagementView 的链接并入目录 | 模拟器截图：iPhone 18 Pro、17e、iPad；深浅色；AX5 字号 | 重写 `Sub2MobileUITests` 中与外壳、导航、设置相关的用例 |
| **2 账号救火链** | 账号根页状态卡、列表行、详情、恢复状态、调度开关加撤销、测试 sheet、批量加结果、编辑 sheet；摘要的“账号受限”项 | T1-a 到 T1-d 实测步数达标；一屏至少 8 个账号 | 重写 `AccountManagementUITests`；删除 `AccountListCustomizationUITests`（7 个用例，随“自定义显示字段”一起废弃） |
| **3 用户与资金** | 用户列表（最近处理）、钱包式详情（并行加载）、充值/退款 sheet、余额记录、待核对全链路 | T2 实测；结果不明的演示路径完整 | 重写 `UserManagementUITests`，新增待核对和二次验证流程 |
| **4 日志** | 分段、Token 与联想、按日分节、标记已处理、上游尝试、请求和错误详情、对象内入口 | T5 实测；日志首条记录在 30% 屏高以内 | 重写 `RequestLogsUITests`（现在断言 `textFields["logs.filter.user"]`，05 §4.15） |
| **5 摘要与监控** | 摘要完整版、监控 Tab（运维、告警、渠道 V2/V1）、分组、统计分析 | T3、T4 实测 | 重写 `AnalyticsUITests` 和 `GroupsUITests`；新增监控用例 |
| **6 收尾** | iPad 分栏、无障碍审计（VoiceOver、Dynamic Type、增强对比度、减弱动态效果）、删除废弃代码、截图验收 | 全量截图集 | 全部用例迁移完成 |

每个阶段结束都在 Mac 上（`ssh mac`）用 `-ui-testing` 演示数据编译、运行和截图，与本文的线框逐屏对照。

### 12.2 UITest 重写成本（估算）

- 现状：7 个文件、1,617 行、35 个用例；按控件类型查询的有 `textFields` 25 次、`switches` 15 次、`segmentedControls` 6 次（05 §4.15）。大量用例断言的是将被删除的说明文字或字段编辑器。
- 估算：约 24 个用例需要重写，约 11 个随功能废弃而删除，新增约 20 个流程用例（T1–T5、批量部分失败、待核对、二次验证、登录、切站、Tab 推导的三种开关组合）。新代码量与现在相当，约 1,500 行。**这部分工作量按“每个阶段约三成时间”计入**，不集中到最后。

### 12.3 accessibilityIdentifier 策略

1. **集中定义**：在 Sub2Core 中新增 `public enum AXID`，UITests target 链接 Sub2Core。Sub2Core 只依赖 Foundation，可以链接。界面和测试引用同一个常量，不再手写字符串。
2. **命名**：`<页面>.<元素>[.<对象ID>]`，例如 `summary.attention.accounts`、`accounts.smart.rateLimited`、`account.row.12`、`account.hero.recover`、`account.schedule`、`logs.scope`、`logs.token.account`、`balance.amount`、`balance.submit`、`batch.bar.pause`、`toast`、`toast.undo`、`stepup.code`、`site.avatar`。
3. **只挂两类元素**：交互控件，以及承载数据的容器（行、数值、徽标）。**说明文字没有标识**，因为界面上本来就不再有说明文字。目标是把标识数量从 185 个降到 80 个以内。
4. **断言语义而非文案**：状态断言用 `Glossary.account(.rateLimited).title` 这样的常量，不写死中文；写操作是否发出，由 `DemoData` 的请求日志（仅 `-ui-testing` 下可见的调试面板）验证，不靠检查界面上有没有出现某句话。
5. **控件类型无关**：查询用 `app.descendants(matching: .any)[AXID.x]`，不用 `textFields[...]` 这类依赖控件类型的写法，以后控件换型（例如 TextField 换成 Token）时测试不会断。

### 12.4 如何防止“契约文案”回流

| 机制 | 做法 |
|---|---|
| 契约迁入测试 | 把 `docs/ACCEPTANCE.md` 和 `ADMIN_MODULES.md` 中每条“界面必须显示 X”的条款改写成 Core 测试。例如：缺失值 → `Sub2Format` 返回“—”；不以标准费用代替 → 成本为 nil 时不回退；余额先持久化再发送 → `AppModel` 测试；不自动重放 → `WriteCoordinator` 测试；跨站拦截 → `stationMismatch` 测试 |
| String Catalog | 所有可见文案进 `Localizable.xcstrings`；新增 `CopyLintTests` 扫描目录中的禁用词：接口、契约、快照、自动重放、原请求、幂等、IPA、不可用、未以、不以、独立加载、前台每 |
| 源码 lint | `scripts/lint-copy.sh` 在 CI 中检查 `NativeApp` 里 `.font(.caption)` 或 `.footnote` 修饰的、以句号结尾且超过 12 个字的 `Text` 字面量。白名单只有本文明确允许的三句：登录页的凭据承诺、测试费用提示、待核对说明 |
| 口径的去处 | 术语解释只能写在 `Glossary.definition` 里，通过 `TermInfoButton` 弹出，不进页面正文 |
| 评审清单 | PR 模板增加三问：新增文字是否在说业务？能不能用状态、组件或流程来表达？是否被测试断言？ |
| 标识约束 | `AXID` 只能挂在交互和数据元素上。给静态说明文字加标识，在代码评审中直接拒绝 |

### 12.5 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 最低版本提到 iOS 26 | iOS 26 以下的设备无法更新 | 用户已确认（00 §1）；自用分发 |
| iOS 26.x 与 27.x 的系统行为差异：搜索 Tab（27.2）、底部附件（26.1）、`tabPlacement`、iOS 26 中 `.searchable` 的放置位置 | 外观或行为与设计不一致 | 阶段 1 先在两个版本的模拟器上截图；把差异隔离在 `ShellCompat` 中；底部附件在 26.0 上退回为摘要里的“需要处理”项 |
| 账号根页一次要发 4 到 5 个计数请求 | 大站点上有一定负载 | 只在根页可见时请求；同一站点 30 秒内复用结果；`lite=true` 且 `page_size=1` |
| “过载”没有服务端筛选值 | 运维关闭时无法单独列出过载账号 | 行内徽标照常显示；摘要计数来自 `dashboard/stats`；不在客户端拼凑清单 |
| 倒计时不准 | 显示的恢复时间偏离实际 | 使用 `serverClockOffset`；到点后单条刷新；VoiceOver 不逐秒播报 |
| 资金确认使用 destructive（遵从简报）与 HIG“用户主动选择的操作不用 destructive”相冲突 | “充值”按钮显示为红色 | 以 00 §3.5 为准；用户试用后如果觉得不妥，只需在 `ConfirmationPolicy` 一处修改 |
| 平台不着色，与 Web 的平台色不一致 | 习惯 Web 的管理员需要适应 | 平台显示名与 Web 一致；把颜色留给状态，这是 HIG 的要求（“Avoid using the same color to mean different things”） |
| 渠道监控 V2 的契约演进（`contract_version`） | 解码失败 | 防御式解码；未知字段忽略；只要版本不匹配，就显示 `FeatureOffState` 的变体“请在 Web 中查看” |
| 搜索 Tab 承担“更多”的职责，可发现性如何 | 用户找不到日志 | 摘要、账号详情、用户详情都有指向日志的入口；iPad 侧栏直接列出；原型阶段请用户实际试用 |
| 修改 UITest 期间回归保护出现空窗 | 回归问题漏检 | 按阶段替换，旧用例在对应页面被删除前持续运行；Core 测试先行 |

---

## 附录 A：视觉身份（Apple 式克制，加一处个性）

| 项 | 规格 |
|---|---|
| 强调色 | **“Sub2 青”**，取自 App 图标的青绿色。放在 `AccentColor` 资源中，配浅色、深色和增强对比度三个变体（色值在原型阶段调校，建议起点：浅色 `#0E7C7B`，深色 `#3CC8C0`）。只用于导航、选中态和主按钮 |
| 语义色调 | `positive` = 系统绿（正常、可用）；`caution` = 系统橙（限流、临时、接近上限、性能下降）；`critical` = 系统红（错误、过载、不可用）；`neutral` = 次要灰（停用、暂停、未知、已处理）；`special` = 系统紫（模型级限流）。含义以 04 §4.1 为准，色值使用系统动态色，自动适配深色和增强对比度 |
| 金额 | 列表和卡片中的金额一律用中性主色，用正负号表达方向。只有图表的序列沿用 Web 的颜色：实际用强调青（绿系）、成本用橙、标准用灰，并始终配文字图例 |
| 平台 | 只显示文字名（例如 OpenAI、Anthropic），不用平台色，把颜色留给状态 |
| 字体 | 全部使用系统文字样式，支持 Dynamic Type；英雄大数用 `.fontDesign(.rounded)`（健康和健身 App 的气质）；所有会变化或需要对齐的数字用 `.monospacedDigit()`；ID 只在详情的“详细信息”中使用等宽字体 |
| 材质 | 内容层不透明：`systemGroupedBackground` 加 `secondarySystemGroupedBackground` 卡片。玻璃只出现在系统 Tab 栏和工具栏、toast，以及选择模式下的系统底栏（03 §1.10） |
| 形状 | 卡片使用连续圆角（或 iOS 26 的 `ConcentricRectangle`，与系统同心）；状态符号用 SF Symbols 的 hierarchical 渲染，**每种状态的形状都不同**，不只靠颜色区分 |
| 个性的落点 | 英雄状态卡用该状态色调的 12% 作为底色；每张摘要卡的第一行是结论句；大数用圆体。三处都克制，其余全部交给系统 |
| 无障碍 | 点击区至少 44pt；辅助功能字号下第 2 行元数据隐藏、网格改为单列；减弱动态效果时数字过渡改为直接替换；增强对比度时色调使用系统的高对比变体 |

## 附录 B：文案规范速查

| 规则 | 例 |
|---|---|
| 只说业务，不说实现 | ✗“未以标准费用代替” → 删除（由测试保证）；✗“前台每 30 秒刷新” → 删除（副标题写“2 分钟前”） |
| 缺失值 | “—”（VoiceOver 读“未返回”）；整行缺失就省略这一行 |
| 枚举 | 一律经过 `Glossary`；不允许出现 active、apikey、stream、upstream_error、add 这类原值 |
| 动词 | 启用调度 / 停止调度 / 恢复状态 / 测试连接 / 充值 / 退款 / 标记已处理 / 禁用用户；不用“确认发送”“确认执行” |
| 状态词 | 账号：正常 / 停用 / 错误 / 限流中 / 过载中 / 临时不可调度 / 配额超限 / 暂停 / 已过期；用户：启用 / 禁用；分组：正常 / 停用；渠道：可用 / 性能下降 / 不可用 / 未知；告警：告警中 / 已恢复 / 已手动解决（04 §4.1、§5） |
| 聚合词 | “需要处理”是聚合桶名，包含哪些状态写在 `AttentionRule` 中；“异常”不作为状态徽章使用 |
| 成本口径 | 短标签：实际 / 成本 / 标准；长名（ⓘ 中）：实际扣费 / 账号成本 / 标准费用；差额 = 实际扣费 − 账号成本 |
| 时间 | 列表行：今天写 `16:12`，跨日用分节标题“昨天”“10月14日”；账号最近使用写相对时间“3 分钟前”；详情写到秒并注明时区 |
| 数字 | 金额 `$1,234.50`（窄符号、千分位）；小额自适应到最多 4 位小数；Token 写 `1.2M`（详情页写精确值 `1,204,331`）；耗时写 `850ms`、`1.25s` |
| 确认标题 | 动词 + 对象 + 数量或金额：“停止 3 个账号的调度？”“向 alice@example.com 充值 $20.00？” |
| 允许保留的说明句（白名单） | 登录页“凭据只保存在这台设备的钥匙串中。”；测试页“会向上游发送一次真实请求，可能产生费用。”；待核对“这笔充值可能已经到账。用‘重试这笔充值’不会重复入账。” |
