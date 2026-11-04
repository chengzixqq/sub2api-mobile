# 01 现有原生界面逐页审计（Sub2 Mobile 管理端）

> 审计对象：`G:/weixinProject/sub2-mobile-native`，分支 `codex/native-ios-rebuild`，HEAD `7ccd542`。
> 审计方式：只读通读 `NativeApp/` 全部 Swift 视图代码（17 个文件、4314 行），对照 `Sources/Sub2Core/` 中的展示逻辑，并查看模拟器截图。未阅读 `docs/ui-reassessment-20261016/`（codex 方案），避免被锚定。
> 证据约定：代码写作 `文件:行号`（路径相对 `NativeApp/` 或 `Sources/Sub2Core/`）；截图使用下列缩写。**【事实】** 表示可由代码或截图直接证实；**【推断】** 表示基于证据的判断，尚未经真机或 iPad 验证。

## 截图缩写与版本说明

| 缩写 | 绝对路径 | 对应代码版本 |
|---|---|---|
| `[AE]` | `G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/admin-expansion-20261016/final-evidence/collection/attachments` | `0e33a3d` 之后，即当前 5 Tab 版本 |
| `[R2]` | `G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/dashboard-polish/account-capacity-20261015-r2-screenshots` | `d07091d`，当时为 4 Tab 版本 |
| `[LOGIN]` | `G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/dashboard-timeout/simulator-diagnostic.png` | 早期版本的登录页 |

【事实】`git diff --stat d07091d HEAD -- NativeApp` 显示，`UsersView.swift`、`SettingsView.swift`、`LoginView.swift`、`Components.swift`、`ListFieldEditor.swift` 和 `PerformanceTrendView.swift` 自 `[R2]` 截图后没有改动；`DashboardView.swift` 只改了 12 行（新增右上角“统计分析”入口）。因此，`[R2]` 中的用户、概览、字段编辑器截图仍能代表当前界面。账号列表和账号详情后来又有改动，以 `[AE]` 和当前代码为准。现有截图中没有“设置”“管理 Tab 根页”“用户编辑表单”“余额表单”“日志筛选表单”和“iPad”画面，这几处的结论只依据代码。

---

## 0. 执行摘要（最关键的 8 条结论）

1. **整套 App 几乎都用同一种“iOS 设置页”写法拼成**：页面主体基本是 `List`/`Form` 的 insetGrouped 分区加 `LabeledValue` 键值行。全项目只有概览页的 4 张卡片和 2 个 Swift Charts 图表脱离了这种写法。监控、排障、账务这类需要扫读、对比和跳转的数据，也被做成了“设置项”。`LabeledValue` 把**值**统一设为 `.secondary` 灰色（`Views/Components.swift:22`），结果是标签黑、数据灰，主次颠倒。
2. **工程契约文案直接出现在界面上**：“未以标准费用代替”“不以配置限额或零代替”“前台每 30 秒刷新”“独立自动刷新”“系统不会自动重放写入请求”“应用更新通过重新构建并签名 IPA 完成”等语句，几乎原样来自 `docs/ACCEPTANCE.md`、`docs/ADMIN_MODULES.md` 的验收条款。界面里共有约 93 处 `.caption/.footnote` 小字，其中说明性和契约性文案超过 60 条。
3. **控制项和元信息占据首屏**：按截图估算，日志页首屏约 31% 是控制卡；统计分析约 32%；概览趋势区约 19% 是分段控件和缩放按钮。账号、用户、分组列表顶部也常驻筛选或开关。每个数据分区还各自带“更新于”时间戳和“刷新××”按钮。
4. **信息扁平、没有状态语义**：账号行默认把 8 个字段写成同级灰色 caption 的“标题：值”并流式排列，其中“容量”一项又内嵌 3 到 8 个“·”分隔的子项（`Features/AccountsView.swift:197-209`、`AccountPresentation.swift:114-127`）。“状态：异常”和“状态：正常”颜色相同，只有“调度：参与调度”被染成绿色。详情页还直接显示 `active`、`apikey`、`openai`、`user`、`upstream_error` 等原始枚举。
5. **缺失值以“不可用”三个字就地铺满**：`NativeApp` 中有 25 处、`Sub2Core` 中有 17 处，与真实数值同字号同颜色。一个缺少运行统计的账号行会出现“在用并发：不可用 … 在用 RPM：不可用 容量：并发 不可用 / 2”（`[AE]/AccountManagementUITests/CDDF2D8A-….png`）。
6. **操作与确认分级失当**：15 个 `role: .destructive` 中，有 8 个是笼统的“确认保存/确认发送/确认执行/确认操作”。“启用调度”“保存名称”“创建分组”这类非破坏性操作也会弹出红色确认。真正有风险的“暂停调度/禁用用户”在入口处却只是普通强调色文字。编辑提交存在 3 种不同范式，成功反馈则以常驻的“处理结果”分区呈现。
7. **信息架构碎片化**：“统计分析”有 4 个入口；“管理”Tab 只是一个放了 3 个链接的目录页；切换站点只能去“设置”；日志和分析的筛选靠手输数字 ID；“异常账号 1”不能点；账号行里的“点入查看错误日志”要至少 3 到 4 次点击才能看到错误，而且日志页默认停在“请求记录”而不是错误页签。
8. **没有任何 iPad 适配**：没有 `NavigationSplitView`、`horizontalSizeClass` 或 `sidebarAdaptable`，仅概览页限制了 `maxWidth: 900`（`Features/DashboardView.swift:404`），但工程配置声明支持 iPad（`TARGETED_DEVICE_FAMILY = "1,2"`）。**值得保留的部分**是逻辑层，质量很高：会话代际守卫、写入安全（不自动重放、未决余额持久化、结果不明时锁定表单）、Decimal 精度、各分区独立加载与取消、脱敏，以及图表交互引擎。重构应以“换皮换骨架、保留逻辑”为主。

---

## 1. 完整导航树

```
Sub2MobileApp                                   Sub2MobileApp.swift:4-13
└─ RootView                                     Sub2MobileApp.swift:15-32
   ├─ [恢复/退出中] ProgressView                 Sub2MobileApp.swift:20-21
   ├─ [全局 alert] “操作未完成”                  Sub2MobileApp.swift:28-30
   ├─ [未登录] NavigationStack { LoginView }     Sub2MobileApp.swift:25
   │   └─ LoginView                             Features/LoginView.swift:26-115
   │       ├─ (内联) 两步验证分区                 LoginView.swift:57-63
   │       ├─ sheet CaptchaView                 LoginView.swift:103-111 → Features/CaptchaView.swift:11-28（WKWebView）
   │       ├─ 已保存的站点 → model.switchTo      LoginView.swift:76-84
   │       └─ 待核对余额请求 → Link 打开原站点   LoginView.swift:85-98
   └─ [已登录] MainTabs（TabView + .tabItem）     Sub2MobileApp.swift:34-45
       ├─ Tab1 概览 → NavigationStack{DashboardView}            Sub2MobileApp.swift:37
       │   └─ DashboardView                                     Features/DashboardView.swift:281-558
       │       ├─ toolbar NavigationLink → AnalyticsView        DashboardView.swift:408-413（见 Tab4 子树）
       │       ├─ DashboardTrendChart                           DashboardView.swift:59-279
       │       │   ├─ sheet 逐小时/逐日明细                     DashboardView.swift:159, 241-261
       │       │   └─ [指标=性能指标] PerformanceTrendView      DashboardView.swift:116-117 → Features/PerformanceTrendView.swift:7-134
       │       │       └─ sheet 性能明细                        PerformanceTrendView.swift:71-88
       │       └─ 下拉刷新 / 3 路 30s 轮询                       DashboardView.swift:414-444
       ├─ Tab2 账号 → NavigationStack{AccountsView}             Sub2MobileApp.swift:38
       │   └─ AccountsView                                      Features/AccountsView.swift:22-378
       │       ├─ toolbar 选择/完成选择                          AccountsView.swift:134-137
       │       ├─ toolbar 显示字段 → sheet ListFieldEditor      AccountsView.swift:139, 142 → Views/ListFieldEditor.swift:4-55
       │       ├─ 行“筛选与排序” → sheet filterSheet            AccountsView.swift:69-71, 143, 210-245
       │       ├─ [选择模式] Menu 批量操作                       AccountsView.swift:78-87
       │       │   ├─ confirmationDialog “X：N 个账号？”        AccountsView.swift:154-162（role .destructive）
       │       │   ├─ sheet 批量操作结果                         AccountsView.swift:150, 246-254
       │       │   └─ sheet StepUpView                          AccountsView.swift:151-153
       │       ├─ 行左划/长按 快捷编辑 → sheet AccountEditView   AccountsView.swift:102-105, 144-149
       │       └─ 行 NavigationLink → AccountDetailView          AccountsView.swift:99 → 390-587
       │           ├─ 快捷编辑账号 → sheet AccountEditView       AccountsView.swift:478, 509-513 → Features/AccountEditView.swift:4-172
       │           │   ├─ confirmationDialog “确认修改账号？”    AccountEditView.swift:81-85（.destructive）
       │           │   └─ sheet StepUpView                      AccountEditView.swift:86-88
       │           ├─ 暂停/启用调度、刷新凭据 → confirmationDialog AccountsView.swift:479-480, 505-507（.destructive）
       │           ├─ 手动测试账号 → sheet AccountTestView        AccountsView.swift:481, 508 → 589-654
       │           │   └─ sheet StepUpView                      AccountsView.swift:616
       │           ├─ NavigationLink 请求记录与错误日志 → RequestLogsView(accountID:)  AccountsView.swift:484
       │           ├─ NavigationLink 账号统计分析 → AnalyticsView(accountID:)         AccountsView.swift:486
       │           └─ sheet StepUpView                          AccountsView.swift:514-516
       ├─ Tab3 用户 → NavigationStack{UsersView}                Sub2MobileApp.swift:39
       │   └─ UsersView                                         Features/UsersView.swift:4-115
       │       ├─ toolbar 显示字段 → sheet ListFieldEditor      UsersView.swift:53, 62
       │       ├─ toolbar 创建用户 → sheet UserEditorView       UsersView.swift:55-59, 63 → 247-436
       │       └─ 行 NavigationLink → UserDetailView            UsersView.swift:30 → 117-229
       │           ├─ 编辑用户 → sheet UserEditorView            UsersView.swift:169-173, 190
       │           │   ├─ confirmationDialog 确认创建/修改      UsersView.swift:345-349（.destructive）
       │           │   ├─ alert “请求结果尚未确认”               UsersView.swift:350-355
       │           │   └─ sheet StepUpView                      UsersView.swift:356-361
       │           ├─ 禁用/启用用户 → confirmationDialog         UsersView.swift:174, 186-188（.destructive）
       │           ├─ 调整余额 → sheet BalanceView               UsersView.swift:175, 189 → 438-546
       │           │   ├─ confirmationDialog “确认调整余额？”    UsersView.swift:489-493（.destructive）
       │           │   └─ sheet StepUpView                      UsersView.swift:494
       │           └─ sheet StepUpView                          UsersView.swift:191
       ├─ Tab4 管理 → NavigationStack{ManagementView}           Sub2MobileApp.swift:40, 47-62
       │   ├─ 请求记录与错误日志 → RequestLogsView               Sub2MobileApp.swift:51 → Features/RequestLogsView.swift:4-168
       │   │   ├─ toolbar 筛选 → sheet RequestLogFilterEditor   RequestLogsView.swift:90-98 → 177-263
       │   │   ├─ 请求行 → UsageRequestDetailView               RequestLogsView.swift:61 → 265-303
       │   │   │   ├─ 查看账号 → LogAccountDestination → AccountDetailView（回到 Tab2 子树） 297, 363-382
       │   │   │   └─ 该账号全部请求记录 → RequestLogsView(accountID:)                     299
       │   │   └─ 错误行 → RequestErrorDetailView               RequestLogsView.swift:66 → 305-361
       │   │       └─ 查看账号 → LogAccountDestination           RequestLogsView.swift:333
       │   ├─ 统计分析 → AnalyticsView                            Sub2MobileApp.swift:53 → Features/AnalyticsView.swift:5-175
       │   │   ├─ 时间与筛选 → sheet AnalyticsFilterView        AnalyticsView.swift:35, 105 → 177-225
       │   │   └─ NavigationLink 逐小时/逐日明细（内联 List）   AnalyticsView.swift:87-95
       │   └─ 分组管理 → GroupsView                               Sub2MobileApp.swift:57 → Features/GroupsView.swift:49-141
       │       ├─ toolbar 创建分组 → sheet GroupEditorView      GroupsView.swift:102-109 → 310-483
       │       │   ├─ confirmationDialog 确认创建/修改分组      GroupsView.swift:391-395（.destructive）
       │       │   └─ alert “请求结果尚未确认”                   GroupsView.swift:396-399
       │       └─ 行 NavigationLink → GroupDetailView           GroupsView.swift:80-81 → 143-291
       │           ├─ 查看与管理分组账号 → AccountsView(initialGroupID:)（回到 Tab2 子树） 192
       │           ├─ 统计分析 → AnalyticsView(groupID:)         GroupsView.swift:195
       │           ├─ 请求记录 → RequestLogsView(groupID:)       GroupsView.swift:196
       │           ├─ 编辑分组 → sheet GroupEditorView           GroupsView.swift:199-203, 221
       │           └─ 停用/启用、删除 → confirmationDialog       GroupsView.swift:204-206, 222-226（.destructive）
       └─ Tab5 设置 → NavigationStack{SettingsView}             Sub2MobileApp.swift:41
           └─ SettingsView                                      Features/SettingsView.swift:4-70
               ├─ 站点行点击 → model.switchTo（无确认）           SettingsView.swift:15
               ├─ ⋯ Menu 删除站点和凭据 → confirmationDialog     SettingsView.swift:26-28, 63-65
               ├─ 添加站点 → sheet NavigationStack{LoginView}    SettingsView.swift:31, 62
               ├─ 打开 Web 后台 → openURL                        SettingsView.swift:37
               ├─ 退出并清除当前凭据 → confirmationDialog         SettingsView.swift:38, 66-68
               └─ 待确认余额请求 → Link 打开原站点                SettingsView.swift:41-53
```

【事实】导航中存在环：管理 → 分组详情 → 分组账号（`AccountsView`）→ 账号详情 → 日志 → 请求详情 → 查看账号 → 账号详情……这条链可以在同一个 `NavigationStack` 中无限压栈（`GroupsView.swift:192`、`AccountsView.swift:484`、`RequestLogsView.swift:297`）。
【事实】按修饰符计数（`grep -o`）：`NavigationLink` 18 处，`.sheet(` 25 处（其中 `StepUpView` 被 7 处各自挂载），`.confirmationDialog(` 10 处，`.alert(` 3 处。

---

## 2. 逐页剖析

> 首屏比例按 iPhone 截图像素（显示高度 2000px）估算，以整屏高度为分母，属于【推断】级别的估计值。所有列表页的“导航栏 + 大标题”都约占 19%（0–385px），下文不再重复说明。

### 2.1 全局壳（RootView / MainTabs）

- **容器**：`TabView` 使用旧式 `.tabItem` API，共 5 个 Tab，`.tint(.indigo)`（`Sub2MobileApp.swift:36-43`）。在 iOS 26 上呈现为浮动玻璃 Tab 栏（所有 `[AE]` 截图底部可见）。
- **加载状态**：恢复会话时整屏只有一个 `ProgressView("正在恢复连接…")`（`Sub2MobileApp.swift:20-21`）。
- **错误**：所有经 `model.report` 上报的错误都汇入同一个 alert，标题固定为“操作未完成”，按钮为“知道了”（`Sub2MobileApp.swift:28-30`、`Session/AppModel.swift:198-201`）。启动恢复失败、站点切换失败、退出失败都显示这同一个标题。
- **站点上下文**：【事实】当前站点只出现在概览页的导航标题中（`DashboardView.swift:407`），其他 Tab 都看不到；切换站点只能去“设置”（`SettingsView.swift:12-33`）。

### 2.2 登录（LoginView）

- **容器**：`Form`，共 7 个可能出现的分区（`LoginView.swift:27-99`）。
- **首屏构成**（`[LOGIN]`）：品牌卡（图标、标题、一句说明）约占 21%，“站点”分区（名称、地址、说明脚注）约占 25%；“身份验证”分区和提交按钮在首屏之外，键盘弹出后被完全遮挡。
- **主要操作入口**：“连接站点”是表单内的一行整宽按钮（`LoginView.swift:68-75`），没有放在工具栏或底部固定位置。
- **已保存站点**排在登录表单和提交按钮**之后**（`LoginView.swift:76-84`），回访用户需要先越过整张空表单。
- **必填项**：“站点名称”为必填（`LoginView.swift:127`），不能从域名自动推断。
- **错误、空、加载**：错误显示为红字分区（`LoginView.swift:64`）；提交中按钮内显示 `ProgressView`（`LoginView.swift:70`）；非管理员时出现带图标的说明分区（`LoginView.swift:65-67`）。
- **确认**：无确认。验证码通过 sheet 打开 `CaptchaView`，已用 `interactiveDismissDisabled` 禁止下滑关闭（`CaptchaView.swift:26`）。

### 2.3 概览（DashboardView + DashboardTrendChart + PerformanceTrendView）

- **容器**：`ScrollView` 内放 `VStack`，再分为 `LazyVGrid` 指标卡和 3 个 `GroupBox`（用量趋势、运行健康、运行监控），背景为 `systemGroupedBackground`，最大宽度 900（`DashboardView.swift:301-406`）。这是全 App 唯一不用 `List` 的主页面。
- **首屏构成**（`[R2]/dashboard-top-performance-card.png`）：4 张指标卡约占 27%（数据）；卡下两行说明（“基础统计更新于… · 前台每 30 秒刷新”“绿色为实际费用，黄色为上游成本…”）约占 6%；趋势区标题、4 段分段控件、说明、缩放按钮行约占 19%（控制）；图表仅露出约 12%。**估算：数据约 39%，控制约 19%，说明约 6%。**
- **指标卡**：`MetricView` 由图标标题、大号数值和 footer 组成（`Views/Components.swift:27-49`）。“今日 Tokens”和“总 Tokens”的 footer 是“绿色实际费用 / 金色上游成本”（`DashboardView.swift:460-490`），需要借助下方那行颜色图例才能读懂。
- **趋势区**（`DashboardView.swift:105-160`）：自上而下依次为分段控件、说明、缩放按钮行（两个 bordered 放大镜按钮加“放大 1×”）、250pt 图表、“当前：…”、“全部：…”、部分缺失说明、选中值卡片或操作提示、“逐小时明细”按钮，以及外层的错误、加载、“刷新趋势”和“更新于”（`DashboardView.swift:355-366`）。**一个图表周围有 10 个辅助元素。**
- **性能指标**：选中第 4 段后，`PerformanceTrendView` 在分段控件下面再叠两层分段（时间范围、RPM/TPM），共 3 层分段（`PerformanceTrendView.swift:24-29`、`[R2]/performance-trend-rpm.png`）。
- **运行健康与运行监控**：`GroupBox` 内放 `LabeledValue`（`DashboardView.swift:367-403`）。“用户总数”和“账号总数”被放进了“运行监控”（`DashboardView.swift:381-385`）。“异常账号 1”只是静态文字，不能跳转到对应账号（`DashboardView.swift:370`）。
- **视觉**：【事实】`GroupBox` 背景放在 `systemGroupedBackground` 上几乎看不见，下半屏没有卡片边界，与上方白色指标卡在视觉上割裂（`[R2]/dashboard-automatic-sections.png`）。
- **操作入口**：右上角工具栏有“统计分析”（`DashboardView.swift:408-413`）。下拉刷新之外，每个分区还有自己的“刷新××”按钮。
- **空、错、加载**：首次加载显示居中的 `ProgressView` 和一行说明“大站点首次统计可能较慢…”（`DashboardView.swift:327-335`）；错误时由 `sectionError` 显示红色标签和“重试”按钮（`DashboardView.swift:446-455`）。费用快照出错时，会同时出现“重试”和“刷新费用”两个按钮（`[R2]/dashboard-cost-snapshot-local-error.png`）。性能接口不可用时显示红字加说明（`[R2]/performance-trend-disabled.png`）。
- **明细 sheet**：`List` 的每行是一个 `Button`，整行文字都被染成强调色，日期和金额都显示为紫色（`DashboardView.swift:243-256`、`[R2]/dashboard-trend-amount-details-two-digits.png`）。

### 2.4 账号列表（AccountsView）

- **容器**：insetGrouped `List`，包含控制分区、“上游账号”分区、今日统计状态分区、更新说明分区和批量结果入口分区（`AccountsView.swift:67-131`）。
- **首屏构成**（`[AE]/AccountManagementUITests/CDDF2D8A-….png`）：控制卡（“筛选与排序 N 个”和“前台自动刷新（30 秒）”开关）约占 12%；分区标题约占 2%；单条账号行约占 14%；说明卡（“占用快照更新于…。前台每 30 秒刷新已加载页面；选择账号时暂停。未提供的在用指标显示不可用。”）约占 7%。进入选择模式后，控制卡增加到约 24%（`[AE]/…/0FE95C0E-….png`）。**按真实数据估算，每屏约 3 到 4 个账号。**
- **行信息结构**（`AccountsView.swift:197-209`）：账号名用 headline，下面用 `ListFieldFlow` 流式排列 N 个“标题：值”，全部是 `.caption` 加 `.secondary`。只有“调度：参与调度”被染成绿色（`AccountsView.swift:203`）。默认 8 个字段为平台、认证类型、分组、在用并发、容量、在用 RPM、状态、调度（`ListFields.swift:63`）。“容量”本身是“·”拼接的 1 到 8 段子串（`AccountPresentation.swift:114-127`）。有错误时追加固定红字“上游返回异常，点入查看错误日志。”，但不显示错误内容（`AccountsView.swift:207`）。
- **语义重复**：【事实】同一行会同时出现“在用并发：2”和“容量：并发 2 / 4”，也会同时出现“在用 RPM：37”和“调度 RPM 不可用 / 60（自然分钟）”（`[AE]/…/0FE95C0E-….png`；`AccountPresentation.swift:79-81, 116, 122`）。
- **操作入口**：左上角“选择”，右上角“显示字段”（图标为筛选图标 `line.3.horizontal.decrease`，`AccountsView.swift:139`）。“筛选与排序”是列表首行；左划或长按出现“快捷编辑”（蓝色，与全局 indigo 不一致，`AccountsView.swift:103`）；“加载更多账号”是一行按钮。
- **批量**：“批量操作”菜单放在**列表顶部**的控制卡中（`AccountsView.swift:78-87`），用户向下滚动勾选后需要回到顶部才能操作。“选择已加载账号”会直接选前 50 个。确认框是 `confirmationDialog`，按钮为 `.destructive` 的“确认执行”，message 把所有账号名用“、”串起来（最多 50 个），并附“结果不明的写入不会自动重试。”（`AccountsView.swift:154-162`）。结果 sheet 先展示站点和一段契约说明，再逐条列出结果（`AccountsView.swift:246-254`、`[AE]/…/ADD5F69B-….png`）。
- **筛选 sheet**：一个 `Form` 中有 4 个 Picker、1 个排序 Picker、1 个降序开关、说明“排序应用于全部分页结果。”和“重置”按钮（`AccountsView.swift:210-245`）。
- **空、错、加载**：空态为灰字一行“没有符合条件的账号”；加载时追加一行 `ProgressView("正在加载…")`；出错时为红字加“重试读取”；今日统计出错时单独占一个分区（`AccountsView.swift:107-123`、`[R2]/account-batch-stats-error-keeps-list-runtime.png`）。

### 2.5 账号详情（AccountDetailView）

- **容器**：insetGrouped `List`，共 5 个分区：账号、容量与实时占用、今日用量、管理操作、记录与分析，另有处理中和错误分区（`AccountsView.swift:418-491`）。
- **首屏构成**（`[R2]/account-runtime-missing-rpm.png`）：“账号”分区的 5 行 `LabeledValue` 约占 36%，值分别为 `openai`、`apikey`、`active`、“已启用”；“容量与实时占用”分区从约 60% 处开始。**操作区不在首屏**，需要滚动两屏左右（`[AE]/…/1E04CF24-….png`）。
- **原始值**：【事实】平台、类型、状态直接显示 `account.platform/type/status` 的原文（`AccountsView.swift:421-423`），而列表通过 `AccountFieldPresentation` 把状态映射为“正常/异常/已禁用”（`AccountPresentation.swift:86`），同一账号两处说法不一致。
- **容量分区**：一个复合长串放进 `LabeledContent` 的右侧，多行右对齐，断行位置错乱（`AccountsView.swift:428`、`[R2]/account-stats-failure-keeps-runtime.png`）。其后依次是在用并发（与容量重复）、探测并发、在用 RPM 及其说明、基础 RPM 限额、缺失说明、加载状态、“更新于… · 前台每 30 秒刷新”/“当前显示列表加载时的快照…”、刷新失败说明和“刷新容量与占用”按钮。**一个分区内有 5 行说明或元信息。**
- **今日用量**：4 行数值、1 行术语解释、“刷新今日用量”按钮（`AccountsView.swift:458-476`）。
- **操作区**（`AccountsView.swift:477-482`）：4 行文字按钮，只有“快捷编辑账号”带图标。“暂停调度”与“启用调度”共用同一行，都是普通强调色。
- **确认**：调度和凭据刷新共用一个 `confirmationDialog`，按钮为 `.destructive` 的“确认操作”，message 为“站点：…\n账号：…（#id）”（`AccountsView.swift:505-507`）。启用调度同样是红色确认。
- **错误入口**：有错误时只显示“上游返回异常，可在下方请求记录与错误日志中查看。”（`AccountsView.swift:425`）。点“请求记录与错误日志”后，日志页默认的 `mode` 是 `.requests`（`RequestLogsView.swift:9`），还需要再切换到“上游错误”页签。
- **空、错、加载**：今日用量未加载时显示“暂未加载”；出错时为红字；整页 `busy` 时在末尾追加 `ProgressView("正在处理…")`（`AccountsView.swift:474, 489-490`）。

### 2.6 账号快捷编辑（AccountEditView，sheet）

- **容器**：`NavigationStack` 内放 `Form`，分区为目标、基本信息、调度与成本、所属分组、待核对和错误（`AccountEditView.swift:30-70`）。
- **首屏**：第一个分区是“目标：站点 / 账号”的只读信息；字段占位文字承担了标签作用（“并发上限”“优先级”“成本倍率”“负载因子（留空恢复默认）”），一旦填入值就看不出这是哪个字段（`AccountEditView.swift:43-46`）。分区末尾有一行规则说明（`AccountEditView.swift:47`）。
- **提交**：工具栏“保存”打开 `confirmationDialog`“确认修改账号？”，按钮为 `.destructive` 的“确认保存”，message 列出变更字段（`AccountEditView.swift:73-85`）。**改个名字也要二次确认，而且是红色按钮。**
- **结果不明**：出现“待核对”分区和“读取当前服务器状态”按钮，“保存”被禁用（`AccountEditView.swift:62-67, 76`）。

### 2.7 账号手动测试（AccountTestView，sheet）

- **容器**：`Form`，分区为测试目标、结果、流式输出（`AccountsView.swift:602-612`）。
- **流程**：在表单内点“确认并开始测试”（`AccountsView.swift:608`），没有二次确认，但有“可能产生费用”提示，这一点合理。失败时只显示“测试失败，请在 Web 后台查看详细错误。”（`AccountsView.swift:635`）。流式输出以等宽 caption 文本堆在 Form 行里。

### 2.8 用户列表（UsersView）

- **容器**：insetGrouped `List`，包含状态 Picker 分区和“用户”分区（`UsersView.swift:22-49`）。
- **首屏构成**（`[R2]/users-fields-final.png`）：状态 Picker 约占 6%（控制）；每条用户行约占 14%；“加载更多用户”按钮行约占 8%。
- **行结构**：邮箱用 headline，下面是“角色：普通用户 用户名：Alice 状态：正常 / 余额：$12.50 并发：1 / 2 / 创建时间：… 备注：…”，与账号行同构，状态和余额都没有强调（`UsersView.swift:31-41`）。
- **操作入口**：右上角工具栏有“显示字段”（筛选图标）和“创建用户”（`UsersView.swift:51-61`）。
- **空、错、加载**：同账号列表（`UsersView.swift:44-47`）。

### 2.9 用户详情（UserDetailView）

- **容器**：insetGrouped `List`，分区为用户详情（最多 11 行）、本月用量、API Key、管理操作、处理中和错误（`UsersView.swift:134-182`）。
- **首屏**：首屏全是 11 行属性；本月用量、Key 和操作都在下方（`[R2]/users-validation-final.png` 是滚动后的画面）。
- **原始值与格式不一致**：角色和状态直接显示 `user.role ?? "未知"`、`user.status`（`UsersView.swift:138-139`），列表中则是映射后的值；Key 状态显示为 `active`（`UsersView.swift:161`）；Tokens 显示为“4,200”（`UsersView.swift:151` 使用 `.formatted()`），账号详情则是“4.20K”；`Components.money()` 输出“$2 / 配额 $100”，没有固定精度（`Views/Components.swift:4`、`[R2]/users-validation-final.png`）。导航标题是用户名，列表标题却是邮箱（`UsersView.swift:183` 与 `:32`）。
- **操作区**：“编辑用户”“禁用用户”“调整余额”3 行文字按钮。“禁用用户”是普通强调色（`UsersView.swift:174`）；确认弹窗中无论启用还是禁用，按钮都是 `.destructive` 的“确认操作”（`UsersView.swift:186-188`）。
- **加载**：`reload()` 依次串行请求用户、用量和 Key（`UsersView.swift:193-204`）；用量未加载时显示“暂未加载”。

### 2.10 用户创建/编辑（UserEditorView，sheet）

- **容器**：`Form`，分区为目标（站点、**地址 URL**、用户）、基本信息（带长 footer）、限额（带长 footer）、提交区和处理结果（`UsersView.swift:282-338`）。
- **提交范式**：表单底部按钮“核对并确认”先打开 `confirmationDialog`，按钮为 `.destructive` 的“确认发送”；如果取消弹窗，表单会锁定，底部出现“核对并确认发送”和“返回修改”（`UsersView.swift:318-336, 345-349`）。工具栏只有“关闭”，**没有“保存”**，与账号编辑的范式不同。
- **结果不明**：表单锁定，显示“操作编号：uuid”；点“关闭”会弹出 alert，按钮为“保留原请求 / 关闭并手动核对（.destructive）”（`UsersView.swift:320-327, 350-355`）。

### 2.11 调整余额（BalanceView，sheet）

- **容器**：`Form`，分区为目标、结果待确认的请求（如有）或调整、处理结果（`UsersView.swift:454-485`）。
- **提交**：表单内“核对并确认”打开 `confirmationDialog`，按钮为 `.destructive` 的“确认发送”（`UsersView.swift:480, 489-493`）。**资金操作使用强确认是合理的。** 但结果反馈被写进表单末尾的“处理结果”分区，没有成功态的视觉区分（`UsersView.swift:484, 528`）。

### 2.12 管理 Tab（ManagementView）

- **容器**：insetGrouped `List`，2 个分区共 3 个 `NavigationLink`（`Sub2MobileApp.swift:47-62`）。【事实】这是一个纯目录页，占用了 5 个 Tab 中的 1 个；它的内容与“概览”工具栏、账号详情、分组详情中的入口重复。无截图。

### 2.13 请求与错误日志（RequestLogsView 及其子页）

- **容器**：insetGrouped `List`，包含控制分区、记录分区和说明分区（`RequestLogsView.swift:29-88`）。
- **首屏构成**（`[AE]/RequestLogsUITests/E1C59092-….png`）：控制卡约占 31%，内含 3 段分段控件、完整起止时间、“固定时间范围；下拉刷新保留以上起止时间。”、“查看最新记录（近 24 小时）”按钮、“已加载 1 条 · 更新于…”；单条记录约占 15%；“加载更多记录”约占 8%；底部说明卡（“请求记录按时间倒序。实际扣费与上游成本分别展示；按需翻页，无需等待全站总数。”）约占 6%。**估算：控制和说明约 37%，数据约 23%。**
- **请求行结构**（`RequestLogsView.swift:116-128`）：共 5 行，依次为模型名（headline）、完整日期时间（含年和秒）、“用户 #8 · 账号名”（用户只显示 ID，详情页才显示邮箱，见 `:295`）、绿色“扣费 $x”和橙色“成本 $y”、“1.20M Token · 1.25s”。**没有状态码或成功标记，也没有流式类型标记。**
- **错误行结构**（`RequestLogsView.swift:129-136`）：红色“HTTP 429”加模型名、最多 3 行消息、“日期 · `upstream` · 未处理”，其中 phase 是原始枚举。
- **筛选 sheet**（`RequestLogFilterEditor`，`RequestLogsView.swift:199-247`）：开始和结束 DatePicker、caption 字号的“近 24 小时 / 近 7 天 / 近 30 天”按钮、**用户 ID、账号 ID、分组 ID、API Key ID 4 个数字输入框**、模型（精确匹配）、请求 ID，以及状态码、处理状态、分类或请求类型 Picker。
- **请求详情**（`RequestLogsView.swift:265-303`、`[AE]/RequestLogsUITests/9A6FA137-….png`）：4 个分区共约 20 行 `LabeledValue`；“类型 stream”为原始值；“API Key ID 9”为原始 ID；扣费分区末尾附精度实现说明。
- **错误详情**（`RequestLogsView.swift:305-361`）：“阶段 upstream”“类型 upstream_error”“平台 openai”均为原始值；页尾附说明“仅展示错误摘要与指标，凭据及原始请求、响应正文不进入此页面。”
- **空、错、加载**：空态为一行灰字“当前条件下暂无记录”；错误为红字加“保留上次成功加载的记录。”和“重试”；加载为一行 `ProgressView("正在读取记录…")`（`RequestLogsView.swift:70-82`）。`LogAccountDestination` 是全 App 唯一使用 `FailureView`/`ContentUnavailableView` 的地方（`RequestLogsView.swift:372`）。

### 2.14 统计分析（AnalyticsView）

- **容器**：insetGrouped `List`，分区为范围控制、统计汇总、实际消费趋势、模型统计和分组统计（`AnalyticsView.swift:22-102`）。
- **首屏构成**（`[AE]/GroupsUITests/1FD29EAB-….png`）：控制分区约占 32%，内含完整起止时间、“分组 #10”、3 个预设按钮、“时间与筛选”、一行操作说明；汇总分区约占 35%，为 9 行 `LabeledValue`。**估算：控制和说明约 32%，数据约 35%。**
- **预设没有选中态**：“今日 / 近7天 / 本月”3 个按钮外观完全相同（`AnalyticsView.swift:30-34`），看不出当前用的是哪个范围。
- **颜色反转**：`LabeledValue(...).foregroundStyle(.green/.orange)` 把**标签**染成绿色或橙色，值仍是灰色（`AnalyticsView.swift:47-48`；截图底部“上游成本”标签呈橙色）。
- **图表**：X 轴直接显示原始字符串“2026-10-16 09:00”，`stride(by: 1)` 会给每根柱子都打标签；Y 轴没有货币单位，只显示 0、5、10、15（`AnalyticsView.swift:70-86`、`[AE]/AnalyticsUITests/1D3FE860-….png`）。
- **分区元信息**：每个分区都重复“更新于 hh:mm:ss”，加载中显示“正在独立加载…”（`AnalyticsView.swift:153-157`），截图中可见同一屏重复两次。
- **分组明细**：每项 4 行 footnote 文本（名称、请求与 Tokens、绿色扣费、成本与差额），没有占比条或排序提示（`AnalyticsView.swift:158-174`）。
- **筛选 sheet**：账号 ID、分组 ID、用户 ID 都是手输数字（`AnalyticsView.swift:198-203`）。

### 2.15 分组列表（GroupsView）

- **容器**：insetGrouped `List`，包含“筛选”分区（平台、状态两个 Picker）和“分组”分区（`GroupsView.swift:68-99`）。
- **首屏构成**（`[AE]/GroupsUITests/DE0E3F98-….png`）：筛选分区约占 15%；每条分组约占 13%。
- **行结构**：名称（headline），“平台 · 启用 · 按量”，“倍率 1.2 · 账号 2 · RPM 限额 不限制”，描述（`GroupsView.swift:83-88`）。启用和停用没有颜色区分。
- **操作入口**：右上角“+”创建；搜索栏默认收起。

### 2.16 分组详情（GroupDetailView）

- **容器**：insetGrouped `List`，分区为分组信息（10 行）、订阅限额、账号与容量、用量、管理、结果待确认和处理结果（`GroupsView.swift:161-216`）。
- **操作位置**：管理分区排在第 5 位（`[AE]/GroupsUITests/2F76EDCA-….png` 是滚动后的画面）。“删除分组”是全 App 唯一在入口处使用 `.destructive` 的业务按钮（`GroupsView.swift:206`）。
- **确认**：停用、启用和删除共用一个 `confirmationDialog`，按钮为 `.destructive` 的“确认发送”，message 含站点名、**完整地址 URL** 和后果说明（`GroupsView.swift:222-226`）。
- **成功反馈**：常驻一个“处理结果”分区，内容为“分组状态已更新。”（`GroupsView.swift:215, 269`；截图可见）。
- **容量缺失**：显示为灰色 caption（`GroupsView.swift:191`），同时“限流账号 不可用”占整行（截图可见）。

### 2.17 分组创建/编辑（GroupEditorView，sheet）

- **容器**：`Form`，分区为目标站点（含 URL）、基本设置、计费与限额（含长 footer）和提交区（`GroupsView.swift:347-384`）。提交范式与用户编辑相同：表单内“核对并确认”，再弹出 `.destructive` 的“确认发送”。结果不明时出现“读取服务器状态核对”。

### 2.18 设置（SettingsView）

- **容器**：insetGrouped `List`，分区为站点、当前连接、待确认余额请求和关于（`SettingsView.swift:11-60`）。无截图。
- **站点行**：名称（headline）、完整 URL、当前站点的对勾，以及行尾“⋯”菜单（只有删除一项）。点行即切换站点，不需要确认（`SettingsView.swift:13-30`）。
- **当前连接**：认证方式、打开 Web 后台、红色“退出并清除当前凭据”。退出和删除站点的确认使用 `.destructive`，这里是恰当的（`SettingsView.swift:38, 63-68`）。
- **待确认余额**：显示原始枚举“add/subtract/set”和完整 UUID（`SettingsView.swift:45-47`）。
- **关于**：附一行面向开发者的说明“原生 iOS 管理客户端。应用更新通过重新构建并签名 IPA 完成。”（`SettingsView.swift:57`）。

### 2.19 字段编辑器（ListFieldEditor，sheet）

- **容器**：`List`，强制 `editMode = .active`（`ListFieldEditor.swift:11-31`）。
- **行结构**（`[R2]/account-field-capacity-before-0--….png`）：账号共 23 个字段，每行有 Toggle、↑、↓ 和拖动柄 **4 个控件**，同时提供两套排序方式（`ListFieldEditor.swift:13-22, 41-54`）。
- 列表末尾附说明 footer 和“恢复默认字段”按钮。

### 2.20 二次验证与验证码

- `StepUpView`：一个 `Form` 中依次放说明、验证码输入框、错误和“验证”按钮（`Views/Components.swift:51-79`）。它被 7 处各自以 sheet 挂载，验证后的提示文案也各不相同。
- `CaptchaView`：`WKWebView` 加载 `/mobile/verify`，有同源校验、180s 超时，并禁止下滑关闭（`CaptchaView.swift:11-103`）。

---

## 3. 缺陷清单

> 严重度说明：**高**＝直接造成“看不懂、找不到、误操作”；**中**＝明显增加认知负担或观感问题；**低**＝一致性或细节问题。根因模式编号见第 4 节。

| # | 严重度 | 现象 | 用户影响 | 证据（代码 + 截图） | 根因 |
|---|---|---|---|---|---|
| D01 | 高 | 账号行把默认 8 个字段以同级 `.caption` 灰字“标题：值”流式排列；“容量”字段内又嵌 3 到 8 个“·”子项，一行有 4 到 6 行文字 | 扫不出哪个账号有问题，每屏只能看约 3 到 4 个账号 | `AccountsView.swift:197-209`；`ListFields.swift:63`；`AccountPresentation.swift:114-127`；`[R2]/account-capacity-and-today-stats-reordered.png`、`[AE]/AccountManagementUITests/0FE95C0E-….png` | R5、R1 |
| D02 | 高 | 同一行同时出现“在用并发：2”和“容量：并发 2/4”，以及“在用 RPM：37”和“调度 RPM 不可用 / 60（自然分钟）” | 管理员无法判断哪个 RPM 才是“当前负载” | `AccountPresentation.swift:79-81, 116, 122`；`[AE]/…/0FE95C0E-….png` | R5、R2 |
| D03 | 高 | 账号异常只显示固定红字“上游返回异常，点入查看错误日志。”，不显示错误摘要；详情页同样如此；点进日志后默认停在“请求记录”页签 | 排障至少需要 4 次点击和 1 次页签切换 | `AccountsView.swift:207, 425, 484`；`RequestLogsView.swift:9` | R7 |
| D04 | 高 | 状态没有语义色或徽标：账号“状态：异常”与“正常”同为灰色，只有“调度：参与调度”被染绿；用户和分组状态也没有颜色 | 异常对象淹没在正常对象中 | `AccountsView.swift:203`；`UsersView.swift:35-36`；`GroupsView.swift:85`；`[R2]/users-fields-final.png`、`[AE]/GroupsUITests/DE0E3F98-….png` | R5 |
| D05 | 高 | `LabeledValue` 把值统一设为 `.secondary`，标签黑、数据灰 | 所有详情页的“数据”都是视觉上最弱的元素 | `Views/Components.swift:22`；`[R2]/account-runtime-missing-rpm.png`、`[AE]/RequestLogsUITests/9A6FA137-….png` | R1 |
| D06 | 高 | 日志页首屏控制卡约占 31%，另有底部说明卡；每条记录 5 行，首屏只见 1 到 3 条 | 日志的核心诉求是“快速扫最新记录”，现在先看到的是控件 | `RequestLogsView.swift:30-57, 84-87, 116-128`；`[AE]/RequestLogsUITests/E1C59092-….png` | R4 |
| D07 | 高 | 8 个“确认保存/发送/执行/操作”按钮使用 `.destructive` 红色，包括“启用调度”“启用用户”“修改账号名”“创建分组”；而“暂停调度”“禁用用户”的入口按钮只是普通强调色 | 红色失去“危险”含义，用户会对所有确认麻木 | `AccountsView.swift:155, 479, 506`；`AccountEditView.swift:82`；`UsersView.swift:174, 187, 346`；`GroupsView.swift:204, 223, 392` | R6 |
| D08 | 高 | 站点切换只在“设置”Tab；其他页面看不到当前站点（概览标题除外）；写操作确认只靠 message 中的“站点：xxx”文字提醒 | 多站点管理员容易在错误站点上操作 | `SettingsView.swift:12-33`；`DashboardView.swift:407`；`AccountsView.swift:160, 507` | R7 |
| D09 | 中 | 账号详情首段显示原始值“openai / apikey / active”，列表却映射为“正常” | 同一对象两处说法不一，看起来像未完成的产品 | `AccountsView.swift:421-423` 对比 `AccountPresentation.swift:86`；`[R2]/account-runtime-missing-rpm.png` | R5 |
| D10 | 中 | 用户详情角色和状态显示 `user/active`，Key 状态显示 `active`；列表则显示“普通用户/正常” | 同上 | `UsersView.swift:138-139, 161` 对比 `:84-85`；`[R2]/users-validation-final.png` | R5 |
| D11 | 中 | 错误行和错误详情直接输出 `phase/type/platform` 原始枚举（如 upstream、upstream_error、openai） | 管理员要自己翻译后端术语 | `RequestLogsView.swift:133, 319-320, 328` | R5 |
| D12 | 中 | 账号详情“容量”复合长串放在 `LabeledContent` 右侧多行右对齐，断行错位 | 观感差，读不出结构 | `AccountsView.swift:428`；`[R2]/account-stats-failure-keeps-runtime.png` | R1 |
| D13 | 中 | 日志请求行没有状态码或成功标识，用户显示为“用户 #8”，时间显示到年和秒 | 看不出哪条失败，也认不出是谁 | `RequestLogsView.swift:116-128`；`RequestLogs.swift:204-208` | R5、R7 |
| D14 | 中 | 日志和分析的筛选靠手输数字 ID（用户、账号、分组、API Key），没有选择器或联想 | 手机上几乎不可用，管理员不会记得 ID | `RequestLogsView.swift:211-219`；`AnalyticsView.swift:198-203` | R7 |
| D15 | 中 | 3 种编辑提交范式并存：账号编辑是工具栏“保存”再确认；用户和分组编辑是表单底部“核对并确认”再确认，再变为“核对并确认发送/返回修改”；余额是表单内“核对并确认” | 每个编辑页都要重新学一遍怎么保存 | `AccountEditView.swift:75-78`；`UsersView.swift:318-336, 480`；`GroupsView.swift:374-383` | R6 |
| D16 | 中 | 批量操作菜单放在列表顶部；确认 message 串接最多 50 个账号名 | 滚动勾选后要回到顶部；确认框可能是一大段文字 | `AccountsView.swift:73-88, 154-162`；`[AE]/…/0FE95C0E-….png` | R6 |
| D17 | 中 | 详情页的“管理操作”都在第 4、5 个分区，首屏不可见，且是无图标的整行文字按钮 | 最常用的操作要滚动才能找到 | `AccountsView.swift:477-482`；`UsersView.swift:168-179`；`GroupsView.swift:198-207`；`[AE]/…/1E04CF24-….png` | R6、R1 |
| D18 | 中 | 成功反馈写成常驻分区，如“处理结果：分组状态已更新。” | 反馈不即时，信息残留在页面上 | `GroupsView.swift:215, 269`；`UsersView.swift:484, 528`；`[AE]/GroupsUITests/2F76EDCA-….png` | R6 |
| D19 | 中 | 概览刷新入口重复：下拉刷新之外还有“刷新趋势、刷新监控、刷新费用、刷新性能”；出错时再加一个“重试”，费用快照出错时“重试”与“刷新费用”并排 | 按钮噪声，用户不知道该点哪个 | `DashboardView.swift:336-363, 397-400, 447-455`；`PerformanceTrendView.swift:53-54`；`[R2]/dashboard-cost-snapshot-local-error.png` | R6、R4 |
| D20 | 中 | 概览有 3 个“更新于”时间戳、2 句“自动刷新”说明和 1 句颜色图例 | 元信息比数据还多 | `DashboardView.swift:112, 337-343, 364, 394, 401`；`[R2]/dashboard-top-performance-card.png` | R2、R4 |
| D21 | 中 | 趋势卡控件过载：4 段指标、缩放按钮行、“当前/全部”两行范围、提示、明细、刷新、更新时间；选中“性能指标”后共有 3 层分段控件 | 一个图表配了 10 个辅助元素 | `DashboardView.swift:105-173`；`PerformanceTrendView.swift:24-29`；`[R2]/performance-trend-rpm.png` | R4 |
| D22 | 中 | “异常账号 1”不能点击 | 看到问题却无处可去 | `DashboardView.swift:370` | R7 |
| D23 | 中 | “统计分析”有 4 个入口；“管理”Tab 只是放了 3 个链接的目录 | Tab 资源浪费，入口心智混乱 | `Sub2MobileApp.swift:47-62`；`DashboardView.swift:408-413`；`AccountsView.swift:486`；`GroupsView.swift:195` | R7 |
| D24 | 中 | 工具栏图标语义冲突：“显示字段”用筛选图标 `line.3.horizontal.decrease`，日志和分析的“筛选”也用相同或相近图标 | 用户点“筛选”结果打开的是字段开关 | `AccountsView.swift:139`；`UsersView.swift:53`；`RequestLogsView.swift:91`；`AnalyticsView.swift:35`；`[AE]/…/CDDF2D8A-….png` | R8 |
| D25 | 中 | 字段编辑器有 23 行，每行 4 个控件（开关、↑、↓、拖动柄） | 设置成本高，界面拥挤 | `ListFieldEditor.swift:13-22, 41-54`；`[R2]/account-field-capacity-before-0--….png` | R4、R8 |
| D26 | 中 | 分析汇总的颜色加在整行上，结果标签变绿或橙，值仍是灰色 | 颜色强调到了错误的对象上 | `AnalyticsView.swift:47-48`；`[AE]/GroupsUITests/1FD29EAB-….png` | R8、R1 |
| D27 | 中 | 分析图表 X 轴显示原始字符串并逐柱打标签；Y 轴没有货币单位；预设按钮没有选中态 | 图表不可读，不知道当前范围 | `AnalyticsView.swift:30-34, 70-86`；`[AE]/AnalyticsUITests/1D3FE860-….png` | R8 |
| D28 | 中 | 数字格式不一致：Tokens 有“4,200”和“4.20K”两种；金额有 `money()` 输出的“$2”和 `DashboardPresentation.money` 输出的“$2.00”两种 | 看起来不专业，也不利于对比 | `UsersView.swift:151, 161`；`Views/Components.swift:4`；`[R2]/users-validation-final.png` | R8 |
| D29 | 中 | 加载、空、错状态都是列表内的一行文字：26 处 `ProgressView("…")`，空态为一行灰字，`ContentUnavailableView` 只用了 1 处 | 页面在加载和出错时显得破碎 | `AccountsView.swift:107-113`；`UsersView.swift:44-47`；`Views/Components.swift:6-16`；`RequestLogsView.swift:372` | R8 |
| D30 | 中 | 列表顶部常驻筛选：用户状态 Picker、分组平台和状态 Picker、账号“自动刷新”开关 | 抢占首屏 | `UsersView.swift:23-27`；`GroupsView.swift:69-77`；`AccountsView.swift:72`；`[R2]/users-fields-final.png`、`[AE]/GroupsUITests/DE0E3F98-….png` | R4 |
| D31 | 中 | 每个写表单都以“目标：站点 / 地址 / 对象”只读分区开头 | 表单首屏被只读信息占据 | `AccountEditView.swift:32-35`；`UsersView.swift:283-287, 455-459`；`GroupsView.swift:348-351`；`AccountsView.swift:603-605` | R6、R2 |
| D32 | 中 | 设置和登录页的“待确认余额请求”显示原始枚举 `add/subtract/set` 和完整 UUID | 不可读 | `SettingsView.swift:46-47`；`LoginView.swift:92-93` | R5、R2 |
| D33 | 中 | 登录页把已保存站点放在空表单之后；“站点名称”必填 | 回访用户路径长 | `LoginView.swift:76-84, 127`；`[LOGIN]` | R4、R7 |
| D34 | 中 | 用户详情首段是 11 行属性；用量、Key 和操作沉底；导航标题用用户名，列表标题用邮箱 | 关键信息和操作不在首屏，身份标识不一致 | `UsersView.swift:135-147, 183` 对比 `:32` | R1、R5 |
| D35 | 中 | 有 14 处文案把用户引向“Web 后台/Web 核对” | 移动端流程不完整的感觉非常明显 | 例如 `AccountsView.swift:635`；`GroupsView.swift:284, 372, 479`；`UsersView.swift:354, 421`；`SettingsView.swift:51`；`LoginView.swift:66, 87` | R2 |
| D36 | 低 | `GroupBox` 在分组背景上几乎看不见，概览下半屏没有卡片边界 | 视觉层级割裂 | `DashboardView.swift:355, 368, 379, 406`；`[R2]/dashboard-automatic-sections.png` | R8 |
| D37 | 低 | 明细 sheet 的行是 `Button`，整行被染成强调色 | 日期和数值都变成紫色，观感廉价 | `DashboardView.swift:243-256`；`PerformanceTrendView.swift:73-84`；`[R2]/dashboard-trend-amount-details-two-digits.png` | R8 |
| D38 | 低 | “用户总数、账号总数”被归入“运行监控” | 分组语义混乱 | `DashboardView.swift:381-385` | R1 |
| D39 | 低 | 命名不一致：Tab“账号”对标题“上游账号”，链接“分组管理”对标题“分组”，链接“请求记录与错误日志”对标题“请求与错误日志”；“扣费 / 实际扣费 / 实际费用 / 实际消费”和“成本 / 上游成本 / 账号成本”混用 | 术语体系不稳定 | `Sub2MobileApp.swift:38, 51, 57`；`AccountsView.swift:132`；`GroupsView.swift:100`；`RequestLogsView.swift:89`；`DashboardView.swift:342`；`AnalyticsView.swift:47` | R8 |
| D40 | 低 | 全局 alert 标题一律为“操作未完成” | 读取失败也叫“操作未完成” | `Sub2MobileApp.swift:28-30` | R6 |
| D41 | 低 | 所有页面都使用大标题，约占首屏 19% | 数据密集型工具的首屏损失较大（【推断】） | 全部 `[AE]` 截图 | R4 |
| D42 | 中 | 无任何 iPad 布局适配（详见第 8 节） | iPad 上是被拉宽的 iPhone 列表 | `Sub2MobileApp.swift:36-42`；全局 grep 无 `NavigationSplitView`/`horizontalSizeClass` | R8 |

---

## 4. 跨页面根因模式（最重要）

### R1：用“设置页范式”承载监控、排障和业务数据

- **表现**：除概览上半部分外，所有页面都是 insetGrouped `List`/`Form` 加 `Section` 加 `LabeledValue` 行（键左、值右，值为灰色）。这种范式适合“少量、可编辑、无需比较”的偏好项，但它被用在了：
  - 实时占用和容量（需要“用量/上限”的进度感），
  - 金额（需要强调和对比），
  - 日志（需要高密度扫读和状态色），
  - 分析（需要图表和排名）。
- **关键证据**：`Views/Components.swift:18-25` 中 `LabeledValue` 的值为 `.secondary`；账号详情容量长串被塞进右侧值位（`AccountsView.swift:428`）；分析汇总是 9 行键值（`AnalyticsView.swift:42-51`）；请求详情约 20 行键值（`RequestLogsView.swift:268-300`）。
- **受影响页面**：账号详情、用户详情、分组详情、请求详情、错误详情、统计分析汇总、概览“运行健康/运行监控”、各编辑表单的“目标”分区。

### R2：工程契约和实现细节文案泄漏进界面

- **表现**：验收文档中的约束条款被逐句翻译成界面上的 caption 或 footer。例如：
  - “缺失显示不可用，不补零或标准费用”（`docs/ADMIN_MODULES.md:27`）在界面上成了“未以标准费用代替”（`DashboardView.swift:131`、`AnalyticsView.swift:62`）；
  - “未提供时不以配置限额或零代替”（`AccountsView.swift:440`）对应 `docs/ACCEPTANCE.md:41`；
  - 刷新机制（“前台每 30 秒刷新”“独立自动刷新”）、写入幂等语义（“系统不会自动重放写入请求”“原请求仅保留在本页内存中”）、精度实现（“金额按两位小数显示，不改变原始精度”）、安全实现（“凭据及原始请求、响应正文不进入此页面”）、交付方式（“应用更新通过重新构建并签名 IPA 完成”）都出现在界面上。
- 【推断】这些文本很多带有 `accessibilityIdentifier`（全项目共 185 个，例如 `accounts.updated`、`logs.range.rolling`、`dashboard.performance.window`），界面因此被当作“验收面板”使用，每条契约都要在屏幕上可见、可断言。
- **受影响页面**：概览、性能趋势、账号列表、账号详情、账号编辑、批量结果、用户编辑、余额、日志、请求详情、错误详情、统计分析、分组详情、分组编辑、设置、登录、二次验证、字段编辑器，**几乎全部页面**。

### R3：缺失值以“不可用”文字就地铺陈，与真实值同权重

- **表现**：“不可用”在 `NativeApp` 中出现 25 处，在 `Sub2Core` 中出现 17 处，还有“暂无记录”“未设置”“暂未加载”“时间格式不受支持”。它们与真实值同字号、同颜色、同位置，并且常常连续出现（账号行“在用并发：不可用 / 在用 RPM：不可用 / 容量：并发 不可用 / 2”）。字段“缺失”和“为 0”本身区分得正确，但视觉上没有采用“—”占位、弱化或折叠这类处理。
- **证据**：`AccountPresentation.swift:129`（`number()` 返回“不可用”）；`DashboardPresentation.swift:36, 45, 54, 59`；`GroupsView.swift:86, 167-169, 182-184`；`[AE]/…/CDDF2D8A-….png`；`[R2]/dashboard-cost-snapshot-local-error.png`（“$12.34 / 不可用”）。
- **受影响页面**：账号列表和详情、分组列表和详情、概览卡片和监控、统计分析、用户列表、日志详情。

### R4：控制项与元信息占据首屏，数据被挤到后面

- **表现**：筛选器、分段控件、开关、范围文字、操作说明、“已加载 N 条 · 更新于…”、刷新按钮都被放进列表的第一个 Section，或放在图表周围。每个可独立加载的分区都配有自己的“更新于”和“刷新”。
- **证据（首屏估算）**：日志页控制和说明约 37%（`[AE]/RequestLogsUITests/E1C59092`）；分析页约 32%（`[AE]/GroupsUITests/1FD29EAB`）；概览趋势区控件约 19%（`[R2]/dashboard-top-performance-card.png`）；分组列表筛选约 15%；账号列表控制约 12%，选择模式下约 24%；再加上所有页面大标题约 19%。
- **受影响页面**：概览、性能趋势、账号列表（含选择模式）、用户列表、分组列表、日志、统计分析、字段编辑器、登录。

### R5：信息扁平、无主次、无语义状态

- **表现**：
  - 列表行采用“标题加同级 caption 字段流”，用户能配置的只有“显示哪些字段”，无法配置“哪个最重要”；
  - 状态没有徽标或语义色（只有调度为绿色），异常只是一句红字；
  - 原始后端枚举直接输出（active、apikey、openai、user、stream、upstream、upstream_error、add）；
  - 同义数据重复（在用并发与容量、在用 RPM 与调度 RPM）；
  - 对象用 ID 标识（用户 #8、API Key ID 9）。
- **证据**：`AccountsView.swift:197-209`；`UsersView.swift:31-41`；`GroupsView.swift:83-88`；`RequestLogsView.swift:116-136, 273, 296, 319-320`；`UsersView.swift:138-139, 161`；`SettingsView.swift:46`。
- **受影响页面**：账号列表和详情、用户列表和详情、分组列表、日志列表和详情、设置、登录。

### R6：操作与确认分级失当

- **表现**：
  1. **确认的严重度没有分级**：保存、启用、创建和删除使用同一套红色 `.destructive` 确认（15 处 destructive 中有 8 处是“确认××”）；
  2. **入口的严重度也没有分级**：暂停调度、禁用用户等入口是普通强调色的整行文字；
  3. **操作沉底**：详情页的操作区都排在第 4、5 个分区；
  4. **提交范式不一**：存在 3 种编辑提交方式；
  5. **反馈方式错位**：成功结果写进常驻分区，全局错误统一叫“操作未完成”；
  6. **入口重复**：刷新、重试按钮成对出现；
  7. **安全信息展示方式粗糙**：站点、地址、UUID 直接出现在表单首段或确认 message 中。
  
  写入安全的**语义**本身是对的，问题在于**呈现方式**：它被表达成大量文字，而不是用状态、组件和流程来表达。
- **受影响页面**：账号详情、批量、账号编辑、用户详情、用户编辑、余额、分组详情、分组编辑、概览、设置、全局 alert。

### R7：信息架构碎片化（入口重复、ID 驱动、死胡同、站点上下文弱）

- **表现**：
  - “统计分析”有 4 个入口；“管理”Tab 是一个只有 3 个链接的目录；
  - 站点切换只在“设置”；
  - 筛选靠手输 ID；
  - 指标不可下钻（如“异常账号 1”）；
  - 从账号异常到错误详情的路径过长，且日志默认页签不对；
  - 导航存在可无限压栈的环。
- **证据**：`Sub2MobileApp.swift:47-62`；`DashboardView.swift:370, 408-413`；`SettingsView.swift:12-33`；`RequestLogsView.swift:9, 211-219`；`AnalyticsView.swift:198-203`；`GroupsView.swift:192`；`AccountsView.swift:207, 484`。
- **受影响页面**：全局 Tab 结构、概览、账号、日志、分析、分组、设置。

### R8：缺少设计系统，样式就地拼装，状态视图没有组件化

- **表现**：
  - `Views/Components.swift` 只有 86 行，含 4 个组件；
  - 页面里有 93 处就地写的 `.caption/.footnote`；
  - 颜色随手取用：日志金额用 `.green/.orange`，概览费用用自定义绿金色（`DashboardView.swift:481-483`），图表用 purple 或 indigo 渐变，账号行用 `.green`，快捷编辑用 `.blue`；
  - 图标语义冲突（筛选图标被用作“显示字段”）；
  - 数字格式有两套（`Components.money` 和 `DashboardPresentation.money`，`.formatted()` 和 `compactNumber`）；
  - `GroupBox` 不可见；`Button` 行被染色；
  - 加载、空、错状态各自手写（26 个文字 ProgressView，`ContentUnavailableView` 只用 1 次）；
  - 7 处重复挂载 `StepUpView`；
  - 无 iPad 和宽屏适配。
- **受影响页面**：全部。

---

## 5. 界面文案普查

> 判断标准：**保留**＝对决策必要且措辞可接受；**改写**＝信息有用但措辞冗长、技术化或位置不当；**移入帮助**＝术语解释或口径说明，放进“ⓘ”或帮助页；**删除**＝实现细节、开发者信息或可被组件状态替代的内容。同类文案已合并为一行。

| # | 位置 | 原文 | 判断 | 理由 |
|---|---|---|---|---|
| C01 | `LoginView.swift:32` | 管理站点、上游账号与用户。凭据仅保存在本机安全存储。 | 改写 | 只保留安全承诺一句，作为副标题 |
| C02 | `LoginView.swift:41` | 同一站点可保存多个身份，建议为每个账号使用不同名称。新增登录将建立独立身份。 | 移入帮助 | 解释的是多身份机制；名称应默认取域名 |
| C03 | `LoginView.swift:66` | 当前版本仅支持管理员。普通用户功能将在后续版本提供，请使用站点 Web 后台。 | 保留（改写更短） | 用户需要知道为什么不能登录 |
| C04 | `LoginView.swift:87` | 以下请求保留原操作编号。退出后新增登录属于独立身份；请在原站点 Web 后台核对账务，勿新建重复操作。 | 改写 | 保留“请先在原站点核对，勿重复操作”，删去身份机制说明 |
| C05 | `LoginView.swift:156` | 此站点的验证码暂不支持原生验证，请使用 Web 后台。 | 保留 | 必要的阻断原因 |
| C06 | `CaptchaView.swift:97` | 验证码页面无法打开，请确认站点已部署 /mobile/verify。 | 改写 | 面向管理员可保留路径，但应折叠为“详情” |
| C07 | `AppModel.swift:81` | 请输入完整 HTTPS 站点地址，例如 …；不支持路径、账号或查询参数。 | 改写 | 改为字段级即时校验，并缩短 |
| C08 | `Sub2MobileApp.swift:28` | 操作未完成（全局 alert 标题） | 改写 | 按场景区分为“连接失败”“退出失败”等 |
| C09 | `DashboardView.swift:112` | 昨日以来的小时趋势，独立自动刷新。 | 删除 | “独立自动刷新”是实现细节；范围用 chip 或副标题表达 |
| C10 | `DashboardView.swift:119` | 暂无可绘制的用量趋势，请检查加载状态或稍后重试。 | 改写 | 改为空态组件“暂无趋势数据” |
| C11 | `DashboardView.swift:124, 127` | 当前：… — … ／ 全部：… — … | 删除 | 坐标轴已经表达范围；两行时间范围是图表调试信息 |
| C12 | `DashboardView.swift:131`；`AnalyticsView.swift:62, 65` | 部分时段未返回实际消费，显示为不可用；未以标准费用代替。／站点未提供该范围的实际消费…未以标准费用代替。／部分时段的实际消费不可用，图表只绘制已返回的金额。 | 改写 | 用图表缺口或灰柱加一句“部分时段无费用数据”；删除“未以标准费用代替”这一契约语句 |
| C13 | `DashboardView.swift:143` | 点选柱子查看数值；放大后可左右滑动，双指缩放或使用按钮调整。 | 删除 | 手势提示可做成一次性引导，不必常驻 |
| C14 | `DashboardView.swift:150` | N 个时间点无法解析，未绘入图表。 | 移入帮助/诊断 | 面向开发者的数据质量信息 |
| C15 | `DashboardView.swift:167` | 放大 N× | 删除 | 缩放倍率没有业务意义 |
| C16 | `DashboardView.swift:332` | 大站点首次统计可能较慢，各分区会独立加载并显示。 | 删除 | 用骨架屏表达加载 |
| C17 | `DashboardView.swift:338`；`PerformanceTrendView.swift:56`；`AccountsView.swift:445` | 基础统计/性能/（账号）更新于 … · 前台每 30 秒刷新 | 改写 | 页面级只保留一个相对时间“刚刚更新”；删除刷新机制说明 |
| C18 | `DashboardView.swift:342` | 绿色为实际费用，黄色为上游成本；分别显示今日和累计统计。 | 删除 | 改为内联标签“扣费 $x · 成本 $y”，不再需要颜色图例 |
| C19 | `DashboardView.swift:348` | 费用快照更新于 …（· 已过期） | 删除 | “快照”是补取机制，用户不关心 |
| C20 | `DashboardView.swift:374` | 平均响应时间为累计请求平均值。 | 移入帮助 | 口径说明 |
| C21 | `DashboardView.swift:394` | 运行监控独立自动刷新。 | 删除 | 实现细节 |
| C22 | `DashboardPresentation.swift:11` | RPM 近60秒 · TPM 近5分钟均值／RPM 窗口由站点决定 · TPM 近5分钟均值 | 改写 | 卡片上可保留“近 60 秒”这类短单位注释；“窗口由站点决定”移入帮助 |
| C23 | `PerformanceTrendView.swift:34` | 每桶 X 平均速率；RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。 | 移入帮助 | 口径说明 |
| C24 | `PerformanceTrendView.swift:50` | 站点需启用运行监控并支持吞吐趋势接口。其他概览数据可继续查看。 | 改写 | 空态改为“站点未开启运行监控”，删除“接口”一词 |
| C25 | `PerformanceTrendView.swift:85` | 性能明细 · 最新在上 | 改写 | 标题只写“性能明细” |
| C26 | `AccountsView.swift:72` | 前台自动刷新（30 秒） | 移入菜单/设置 | 不应常驻列表首屏 |
| C27 | `AccountsView.swift:107`；`UsersView.swift:44`；`GroupsView.swift:91`；`RequestLogsView.swift:72` | 没有符合条件的账号/用户/分组；当前条件下暂无记录 | 保留 | 改为统一的空态组件，并附“清除筛选”按钮 |
| C28 | `AccountsView.swift:126` | 占用快照更新于 …。前台每 30 秒刷新已加载页面；选择账号时暂停。／下拉刷新获取最新值。未提供的在用指标显示不可用。 | 删除 | 整句都是机制说明；只保留相对更新时间 |
| C29 | `AccountsView.swift:160` | 站点：…\n（全部账号名）\n结果不明的写入不会自动重试。 | 改写 | 改为“在 <站点> 暂停 N 个账号”，最多列 3 个名称加“等”；删除契约句 |
| C30 | `AccountsView.swift:207, 425` | 上游返回异常，点入查看错误日志。／…可在下方请求记录与错误日志中查看。 | 改写 | 直接显示经 `safeMessage` 脱敏的错误摘要，并配“查看错误”直达链接 |
| C31 | `AccountsView.swift:238` | 排序应用于全部分页结果。 | 删除 | 用户默认就是这样理解的 |
| C32 | `AccountsView.swift:249` | 写操作未自动重试；结果不明时先刷新并核对服务器状态。凭据刷新响应丢失时，无法仅靠读取确认结果。 | 改写 | 仅在存在“结果不明”项时显示一行警示 |
| C33 | `AccountsView.swift:273, 280, 286, 296` | 凭据刷新成功／尚未执行，请完成验证后手动选择。／服务器明确返回失败，请检查账号权限、状态或分组配置。／未返回此账号的明确结果，请先刷新核对。 | 改写 | 改为状态标签（成功/失败/未执行/未知）加可展开原因 |
| C34 | `AccountsView.swift:382, 385` | 服务器拒绝：…未自动覆盖混合渠道限制。／结果不明：… 请先刷新核对，未自动重试。 | 改写 | 删除“未自动××”这类契约表述 |
| C35 | `AccountsView.swift:437` | 在用 RPM 为最近 60 秒成功请求数。 | 移入帮助 | 口径说明 |
| C36 | `AccountsView.swift:440` | 站点未返回此账号的在用 RPM，可能暂时无法读取运行统计；未提供时不以配置限额或零代替。 | 删除 | 用“—”占位，口径放进帮助 |
| C37 | `AccountsView.swift:449` | 当前显示列表加载时的快照，正在读取最新数据。 | 删除 | 用加载指示或 redacted 表达 |
| C38 | `AccountsView.swift:453`；`GroupsView.swift:191` | 刷新失败，保留上次快照：…／容量刷新失败，保留上次数据。… | 改写 | 改为横幅“刷新失败 · 显示 hh:mm 的数据 · 重试” |
| C39 | `AccountsView.swift:466` | 扣费为此账号今日实际向用户收取的费用，成本为账号上游成本。 | 移入帮助 | 术语表 |
| C40 | `AccountsView.swift:474`；`UsersView.swift:153` | 暂未加载 | 删除 | 改用骨架屏 |
| C41 | `AccountsView.swift:507`；`UsersView.swift:188` | 站点：…\n账号/用户：…（#id） | 保留（精简） | 确认对象是必要信息，ID 可以省略 |
| C42 | `AccountsView.swift:606, 607` | 模型（可选，使用后端默认值）／测试会向上游发起实际请求，可能产生费用。 | 保留 | 费用风险提示是必要的 |
| C43 | `AccountsView.swift:635, 638` | 测试失败，请在 Web 后台查看详细错误。／连接结束，但未收到测试完成事件，不能判定成功。 | 改写 | 展示错误事件内容；改为“测试未完成（连接中断）” |
| C44 | `AccountEditView.swift:47` | 并发与优先级为非负整数。负载因子为 1 至 10000，留空或 0 恢复默认。仅提交修改的字段。 | 改写 | 改为字段级校验和单位提示；删除“仅提交修改的字段” |
| C45 | `AccountEditView.swift:59` | 服务器检查分组兼容性；当前未返回的原分组会保留，取消勾选才移除。 | 改写 | 精简为“未列出的原分组将保留” |
| C46 | `AccountEditView.swift:64, 103` | 服务器可能已应用更改。本页已停止提交…／已读取当前状态，请核对以上字段… | 改写 | 改为统一的“结果待确认”状态横幅组件 |
| C47 | `UsersView.swift:177` | 此用户存在结果待确认的余额请求，请打开余额页面处理原请求。 | 保留（改为横幅） | 风险提示是必要的 |
| C48 | `UsersView.swift:301` | 密码只在本次表单和请求内存中保留，关闭后清除。提升或创建管理员时，站点可能要求二次验证。 | 删除前半 / 后半移入帮助 | 前半是实现细节 |
| C49 | `UsersView.swift:316` | 并发和 RPM 接受非负整数。编辑只提交实际变更的字段；余额调整仍在独立余额页面处理。 | 删除 | 改为字段级校验；“余额”入口本身就能说明 |
| C50 | `UsersView.swift:321`；`UsersView.swift:467` | 操作编号：uuid | 保留（折叠） | 结果不明时核对需要它，但默认应折叠并可复制 |
| C51 | `UsersView.swift:335`；`GroupsView.swift:381`；`UsersView.swift:483` | 正在处理，请勿重复提交…／正在发送原请求，请勿重复操作… | 改写 | 改为按钮内加载态，并禁用按钮 |
| C52 | `UsersView.swift:354`；`GroupsView.swift:399` | 关闭会清除内存中的原始请求和密码…／请先在当前站点确认实际分组状态… | 改写 | 精简为“关闭后无法重试原请求，确定关闭？” |
| C53 | `UsersView.swift:421` | 此敏感操作需要使用已启用双因素验证的管理员账号登录，请在 Web 完成配置后重试。 | 保留 | 必要的阻断原因 |
| C54 | `UsersView.swift:424`；`Components.swift:62` | 站点要求二次验证。验证后仍需手动重新确认原请求，不会自动重发。／此操作需要二次验证。…系统不会自动重放写入请求。 | 改写 | 只保留“请输入验证器中的 6 位验证码” |
| C55 | `UsersView.swift:427, 431-432` | 请求被拒绝，未确认任何修改。／…结果尚未确认。表单已锁定…原始请求仅保留在本页内存中。／…站点未为此请求提供幂等重试… | 改写 | 改为统一的“被拒绝 / 结果不明”状态组件，各一行文案 |
| C56 | `UsersView.swift:462` | 不要重新创建请求。使用原始请求重试会保留相同操作编号及金额，避免重复扣加余额。 | 改写 | 精简为“请重试原请求，避免重复入账” |
| C57 | `UsersView.swift:505, 528, 531, 534-536` | 余额各类结果文案 | 改写 | 成功用 toast；不明用状态横幅 |
| C58 | `UsersView.swift:293, 304, 306, 309`；`GroupsView.swift:365-369`；`AccountEditView.swift:46` | 各类占位文字，如“最大并发（0 表示不限制）”“每日限额 USD（留空不限制）” | 改写 | 占位不应承担标签作用；改为“标签 + 单位 + 占位” |
| C59 | `RequestLogsView.swift:37, 40` | 最近 24 小时；下拉刷新时更新至现在。／固定时间范围；下拉刷新保留以上起止时间。 | 删除 | 用时间 chip（“近 24 小时”或“10/15 01:33–10/16 01:33 ×”）表达 |
| C60 | `RequestLogsView.swift:42` | 查看最新记录（近 24 小时） | 改写 | 改为时间 chip 上的“×”或“回到最新” |
| C61 | `RequestLogsView.swift:51` | 上游错误按时间、账号、分组与状态筛选。用户、密钥和模型条件仅用于请求记录及失败请求。 | 删除 | 筛选表单本来就会隐藏不支持的字段 |
| C62 | `RequestLogsView.swift:54` | 已加载 N 条 / 共 M 条 · 更新于 … | 改写 | 仅在总数精确时显示“共 M 条” |
| C63 | `RequestLogsView.swift:79` | （错误）+ 保留上次成功加载的记录。 | 改写 | 改为列表顶部横幅 |
| C64 | `RequestLogsView.swift:85` | 请求记录按时间倒序。实际扣费与上游成本分别展示；按需翻页，无需等待全站总数。 | 删除 | 实现细节 |
| C65 | `RequestLogsView.swift:85` | 失败请求是客户端可见错误；上游错误包含重试过程中恢复的上游异常。日志监控关闭时，站点可能无法提供错误记录。 | 移入帮助 | 对区分两个页签有价值，适合放在页签“ⓘ”中 |
| C66 | `RequestLogsView.swift:283` | 成本使用该记录保存的定价与账号倍率快照。金额按两位小数显示，不改变原始精度。 | 删除（前半移入帮助） | 精度说明是实现细节 |
| C67 | `RequestLogsView.swift:344` | 仅展示错误摘要与指标，凭据及原始请求、响应正文不进入此页面。 | 移入帮助 | 安全实现说明 |
| C68 | `RequestLogsView.swift:217, 252` | 模型（精确匹配）／ID 和状态码必须为正整数。 | 保留 | 必要的输入约束；ID 输入框本身应被选择器替代 |
| C69 | `AnalyticsView.swift:37` | 下拉刷新上方固定范围；点今日、近7天或本月可更新截止时间至现在。 | 删除 | 预设按钮有选中态后，这句就不需要了 |
| C70 | `AnalyticsView.swift:52` | 差额仅为实际扣费减上游成本，未包含服务器等其他费用。 | 移入帮助 | 术语口径（防止被误认为“净利润”）有价值，但不应常驻 |
| C71 | `AnalyticsView.swift:154, 156` | 正在独立加载…／更新于 …（每分区各一次） | 删除/合并 | 改用骨架屏；页面级只保留一个更新时间 |
| C72 | `AnalyticsView.swift:195-196` | 结束（不含）／按设备时区统计，支持一年内自定义范围。 | 改写 | 保留“时区”一行副标题，“不含”改为范围显示规则 |
| C73 | `GroupsView.swift:210, 376` | 请求不会自动重发。先读取服务器当前状态…／请求结果尚未确认，不会自动重发或新建相同请求。 | 改写 | 统一为“结果待确认”状态组件 |
| C74 | `GroupsView.swift:225` | 站点：…\n地址：URL\n分组：…\n删除将解除此分组的关联，关联订阅等限制由服务器校验。／停用会影响该分组的请求和关联用户。 | 改写 | 保留后果说明；删除 URL 和“由服务器校验” |
| C75 | `GroupsView.swift:269, 283-288, 473-479` | 分组状态已更新。／核对结果类文案 | 改写 | 成功用 toast；核对结果用状态组件 |
| C76 | `GroupsView.swift:372` | 编辑仅提交变更字段。模型路由、模型价格、利润控制等高级配置保留服务器设置；可在当前站点 Web 后台管理。 | 改写 | 删前半；后半改为“高级配置 → 在 Web 中打开”链接行 |
| C77 | `GroupsView.swift:461` | …结果待确认。原请求仅保留在本页内存中，不会自动重试。 | 改写 | 同 C73 |
| C78 | `SettingsView.swift:51` | 仍保存凭据的原身份可切换后打开对应用户，使用原操作编号重试。退出或删除凭据后的旧身份记录仅供 Web 核对；新增登录不能继承旧请求。 | 改写/移入帮助 | 保留“如何处理”一句，机制说明放进帮助 |
| C79 | `SettingsView.swift:57` | 原生 iOS 管理客户端。应用更新通过重新构建并签名 IPA 完成。 | 删除 | 面向开发者 |
| C80 | `SettingsView.swift:65, 68` | …站点配置和本机凭据将被清除。旧身份的未决余额记录仍保留…／此设备上的登录凭据将被清除。 | 保留（条件显示） | 后半句只在存在未决记录时出现 |
| C81 | `ListFieldEditor.swift:24` | 开关控制列表显示内容，拖动右侧手柄或使用上下箭头调整顺序。偏好保存在本机当前登录身份下。 | 删除 | 如果保留字段编辑器，一句“拖动调整顺序”就够了 |
| C82 | `ListFields.swift:115, 122, 126` | 暂无记录／时间格式不受支持／未设置 | 改写 | 统一用“—”；“时间格式不受支持”属于开发者信息 |
| C83 | `Sub2MobileApp.swift:21` | 正在恢复连接…／正在退出并清除凭据… | 保留 | 必要的过渡状态 |
| C84 | `AppModel.swift:62, 185` | 未决余额记录无法读取。请保留应用数据并检查设备存储；已暂停新的余额操作。 | 保留 | 涉及资金安全的关键阻断 |

---

## 6. 现有可复用资产

### 6.1 逻辑层：建议原样复用（与 UI 解耦，质量高，有测试覆盖）

| 资产 | 位置 | 理由 |
|---|---|---|
| `APIClient` 及各扩展（账号、分组、日志、分析、用户写入） | `Sources/Sub2Core/APIClient.swift`、`AccountManagement.swift:104-123`、`GroupManagement.swift:173-195`、`RequestLogs.swift:211-221`、`UsageAnalytics.swift:87-105` | 接口契约清晰，配有 16 个 Core 测试文件（`Tests/Sub2CoreTests/`） |
| 查询模型 `AccountListQuery`、`AccountSort`、`RequestLogFilter`、`AnalyticsQuery` 及 `queryItems()` | `AccountManagement.swift:4-40`；`RequestLogs.swift:28-84`；`UsageAnalytics.swift:4-34` | 天然适合映射为 URL 化或 chip 化的筛选状态 |
| 写请求模型与校验：`AccountUpdateRequest`、`PendingAccountUpdate`、`GroupCreate/UpdateRequest`（含 `matches()`）、`UserCreate/UpdateRequest`、`PendingUserUpdateOperation`、`PendingBalanceOperation`、`AccountBulkReply.outcome` | `AccountManagement.swift:42-101`；`GroupManagement.swift:81-155`；`UserManagement.swift`；`Models.swift:388-405` | 稀疏更新、幂等 ID、脱敏 `debugDescription` 都做得很好 |
| 数值展示 `DashboardPresentation`（`compactNumber`、`compactCost`、`money`、`duration`、`trendDate`、`trendAxisLabel`） | `DashboardPresentation.swift:5-108` | 全程 Decimal 舍入，跨平台问题已修复（`docs/ACCEPTANCE.md:183`）；应成为**唯一**的格式化入口，取代 `Components.money` |
| 趋势序列 `DashboardTrend.series`、`clampedZoom`；`DashboardTrendMetric.plotValue/displayValue`；`PerformanceTrend.rate` | `DashboardTrend.swift`；`PerformanceTrend.swift:57-67` | 图表数据准备逻辑与视图无关 |
| 脱敏 `RequestLogPresentation.safeMessage`；测试输出脱敏 `sanitizedTestOutput` | `RequestLogs.swift:192-203`；`AccountsView.swift:647-653` | 安全相关，必须保留；后者建议移入 Core |
| 枚举标题映射 `GroupPlatform.title`、`AdminUserRole.title`、`AccountSort.title`、`AccountListField.title` | `GroupManagement.swift:56-66`；`UserManagement.swift:3-9`；`ListFields.swift:64-90` | 可扩展为统一的“枚举到中文标签和语义色”表，用来修复 R5 |
| `ListFieldSelection<Field>` 存储逻辑（版本化、按 profile 隔离、新增字段默认启用） | `ListFields.swift:11-54` | 即使未来不再提供“自定义字段”，也可用于“列表密度、排序偏好”等 |
| 会话与安全：`AppModel` 的连接、代际（`sessionGeneration`）、凭据租约、未决余额持久化（`.completeFileProtection`）、`SessionContext` 环境值 | `Session/AppModel.swift:6-208, 365-374`；`Session/CredentialVault.swift` | 跨站点迟到结果拦截、凭据隔离都已做对 |
| `CaptchaView` 与 `CaptchaBridgeValidator` | `Features/CaptchaView.swift`；`CaptchaBridgeValidator.swift` | 同源校验和超时等安全细节已完善，换外观即可 |

### 6.2 视图内逻辑：建议**抽出**后复用

| 资产 | 位置 | 建议 |
|---|---|---|
| `DashboardLoadState<Value>`（可取消、防迟到、记录 `updatedAt`） | `DashboardView.swift:6-41` | 移到独立文件，作为全 App 通用的“分区加载状态”，配合统一的骨架、错误、空态组件 |
| 分页加载（含“刷新已加载的所有页”、去重、请求票据） | `AccountsView.swift:349-377`；`UsersView.swift:101-114`；`GroupsView.swift:127-140`；`RequestLogsView.swift:144-167` | 4 份近似实现，应合并为一个通用分页加载器或视图模型 |
| 写入安全状态机（prepared、confirming、uncertain、reconcile；被拒绝与结果不明的分类） | `UsersView.swift:238-245, 374-435`；`GroupsView.swift:305-308, 414-482`；`UsersView.swift:513-545`；`AccountEditView.swift:141-171` | **语义必须保留**；抽成通用的“写操作协调器”，再由统一的提交和状态组件呈现，以解决 R6 |
| 错误分类 `needsStepUp`、`accountWriteFailure`、`groupWriteDefinitelyRejected`、`definitelyRejected` | `Components.swift:81-86`；`AccountsView.swift:380-386`；`GroupsView.swift:485-488`；`UsersView.swift:539-545` | 4 套近似规则，应合并为一个分类器 |
| `DashboardTrendChart` 的交互引擎（锚定左缘缩放、滚动吸附、点选、手势与按钮共用同一 scale、减弱动态效果适配） | `DashboardView.swift:43-279` | 交互质量高，应保留引擎，去掉周围的 10 个辅助元素 |
| `ListFieldFlow` 流式布局 | `ListFieldEditor.swift:59-87` | 可复用于标签和 chip 换行 |
| `StepUpView` 逻辑 | `Components.swift:51-79` | 保留调用逻辑；改为一个全局可呈现的验证面板，而不是 7 处各自挂载 sheet |

### 6.3 视图层：建议废弃或重做

- `LabeledValue`（值灰化，`Components.swift:18-25`）：废弃，由强调数值的指标行或属性网格替代。
- `MetricView`（`Components.swift:27-49`）：概念可以保留，需按新设计系统重做，补充趋势和对比槽位。
- `FailureView`（`Components.swift:6-16`）：可以保留并推广为统一的错误和空态组件（目前只用了 1 次）。
- 所有 Feature 页面的 `List`/`Section` 骨架、`accountRow`、用户行、分组行、日志行：重做。
- `ManagementView`（`Sub2MobileApp.swift:47-62`）：废弃，并入新的信息架构。
- `ListFieldEditor` 的 UI（`ListFieldEditor.swift:4-55`）：是否保留“自定义字段”属于产品决策；如果保留，应改为“预设密度加少量可选列”。
- 所有 footer、caption 说明文本：按第 5 节处理。
- **注意**：185 个 `accessibilityIdentifier` 和 7 个 UITest 文件（35 个用例）依赖现有结构。重构时需要同步迁移标识或改写测试，否则回归保护会失效。

### 6.4 面向未来普通用户端的可复用性（【推断】）

`DashboardPresentation`、趋势和图表引擎、`DashboardLoadState`、写入安全协调器、分页加载器、脱敏和会话代际机制都与角色无关，可以直接服务个人余额、Key、用量、订阅等页面。与管理员绑定的部分只有 `APIClient.verifyAdministrator`（`AppModel.swift:110`）和 `LoginView` 中的角色拦截（`LoginView.swift:169`），扩展普通用户端时需要改成按角色分流。

---

## 7. 值得保留的好做法（公平评价）

1. **跨站点和迟到结果防护**：每个异步结果都会校验 `session.generation == model.sessionGeneration`，例如 `AccountsView.swift:370`、`UsersView.swift:110`、`GroupsView.swift:133`。切换站点后旧请求不会污染新页面，这是管理类 App 最容易出错的地方，这里做对了。
2. **写入安全语义扎实**：
   - 确认内容绑定了站点和目标；
   - 结果不明时锁定表单，禁止自动重放；
   - 余额操作的 UUID 先持久化再发送，并启用文件保护（`AppModel.swift:184-190, 370-374`；`UsersView.swift:518-526`）；
   - 二次验证后要求重新确认；
   - `interactiveDismissDisabled` 防止误关（`UsersView.swift:344`、`GroupsView.swift:390`）。
3. **分区独立加载与部分失败**：概览和分析的各分区使用各自的 `DashboardLoadState`，慢查询或失败不会阻塞其他分区（`DashboardView.swift:288-293`、`AnalyticsView.swift:11-14`）；页面不可见或进入后台时会暂停轮询（`DashboardView.swift:294-295, 420-444`）。
4. **数据真实性原则**：缺失就是缺失，不会用 0 或标准费用冒充（问题只在于**呈现方式**，原则本身正确）；全程使用 Decimal 处理精度。
5. **安全与隐私**：日志和测试输出都经过脱敏；Key 和密码使用 `privacySensitive`（`UsersView.swift:160, 294`）；验证码页面有同源校验（`CaptchaView.swift:70-95`）；凭据只存放在本机。
6. **无障碍基础较好**：
   - 按钮普遍保证 `minHeight: 44`；
   - 图标按钮带 `accessibilityLabel`（`ListFieldEditor.swift:52`、`DashboardView.swift:165`）；
   - 卡片高度使用 `@ScaledMetric`，大字号时网格变为单列（`DashboardView.swift:287, 304`）；
   - 适配减弱动态效果（`DashboardView.swift:270`）；
   - 图表有 AX 标签，并提供明细列表作为可访问的替代。
7. **原生交互的正确使用**：账号行支持左划和长按快捷编辑（`AccountsView.swift:102-105`）；`.searchable` 带 300ms 防抖（`AccountsView.swift:189-195`）；输入框设置了 `textContentType(.oneTimeCode)` 和正确的键盘类型。
8. **图表交互工程质量高**：锚定左缘缩放、滚动吸附到整点、点选与横向拖动互不冲突（`DashboardView.swift:200-238, 266-278`）。
9. **偏好按登录身份隔离**（`ListFields.swift:51-53`）：同一站点的不同管理员互不干扰。

---

## 8. iPad 现状

- 【事实】工程配置声明支持 iPad：`TARGETED_DEVICE_FAMILY = "1,2"`（`Sub2Mobile.xcodeproj/project.pbxproj:74-75`）；`Info.plist` 声明了 iPad 全部 4 个方向（`NativeApp/Resources/Info.plist`，键 `UISupportedInterfaceOrientations~ipad`）。
- 【事实】代码中**没有**任何 `NavigationSplitView`、`horizontalSizeClass`、`userInterfaceIdiom`、`.tabViewStyle(.sidebarAdaptable)`、`Tab(...)` 新 API 或 `.inspector`（全局 grep 只在 `DashboardView.swift:404, 465` 命中 `frame(maxWidth: 900)` 和 `ViewThatFits`）。
- 【事实】仅有的宽屏处理是：概览内容 `maxWidth: 900` 居中，指标网格使用 `.adaptive(minimum: 150)`，大字号时最小宽度改为 300（`DashboardView.swift:304, 404`）；费用小字在空间不足时用 `ViewThatFits` 换行（`DashboardView.swift:465-475`）。
- 【推断】`TabView` 使用旧式 `.tabItem`，没有设置 `sidebarAdaptable`。在 iPadOS 18 及以上，它会显示为顶部浮动 Tab 栏，不能切换为侧边栏（参见 [WWDC24 – Elevate your tab and sidebar experience in iPadOS](https://developer.apple.com/videos/play/wwdc2024/10147/)）。所有 `List` 页面会铺满整屏宽度，形成被拉宽的单列列表；列表到详情不会形成并排双栏；sheet 会显示为表单页。现有证据中**没有 iPad 截图或 iPad UITest**，以上结论均未经验证。
- 【推断】iPad 上缺少键盘快捷键、指针悬停效果、多列表格（日志和账号最适合）、拖放支持，也没有利用宽屏同时显示多个分区的能力。

---

## 附录 A：截图索引（本审计实际查看过的画面）

| 页面 | 截图 |
|---|---|
| 账号列表（自动刷新开启） | `[AE]/AccountManagementUITests/CDDF2D8A-6F77-4DA6-B1C1-3C30C0E15E99.png`、`EAAED920-E1C8-4F6A-8092-4AEC05E38229.png` |
| 账号列表（批量选择 + 菜单） | `[AE]/AccountManagementUITests/0FE95C0E-ADA5-4FF6-BA37-E240ADED809C.png` |
| 批量操作结果 | `[AE]/AccountManagementUITests/ADD5F69B-2641-475C-815E-76DCF80E4E59.png`、`D72B1B48-CEB0-404D-BA7F-3D1CA2A8814C.png` |
| 账号详情（编辑后，下半部分） | `[AE]/AccountManagementUITests/1E04CF24-BFC6-4A94-B784-5769CC0684D7.png`、`9576ADBC-8F63-4379-AACB-737B36E76CD7.png` |
| 账号详情（首屏 / 容量） | `[R2]/account-runtime-missing-rpm.png`、`[R2]/account-stats-failure-keeps-runtime.png`、`[R2]/account-detail-distinct-charge-and-cost.png`、`[R2]/account-runtime-and-billing.png` |
| 账号列表（旧版 Picker、自定义字段、今日统计错误） | `[R2]/account-capacity-field-customization.png`、`[R2]/account-capacity-and-today-stats-reordered.png`、`[R2]/account-fields-persist-across-tabs.png`、`[R2]/account-batch-stats-error-keeps-list-runtime.png` |
| 字段编辑器 | `[R2]/account-field-capacity-before-0--testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs.png` |
| 概览 | `[R2]/dashboard-top-performance-card.png`、`[R2]/dashboard-automatic-sections.png`、`[R2]/performance-trend-rpm.png`、`[R2]/performance-trend-disabled.png`、`[R2]/dashboard-cost-snapshot-local-error.png`、`G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/dashboard-polish/screenshots/dashboard-final-state.png`、`…/screenshots/dashboard-running-health.png`、`…/screenshots/dashboard-trend-chart-tap-selection.png` |
| 趋势明细 sheet | `[R2]/dashboard-trend-amount-details-two-digits.png` |
| 用户列表 / 详情 | `[R2]/users-fields-final.png`、`[R2]/users-validation-final.png`、`[R2]/users-create-edit-final.png` |
| 日志列表 / 请求详情 | `[AE]/RequestLogsUITests/E1C59092-83FB-401F-90ED-B201F325CA77.png`、`9A6FA137-E2D8-4449-9B27-91AD1A8F4DC9.png` |
| 统计分析 | `[AE]/AnalyticsUITests/1D3FE860-E44B-419B-8CA9-D906E9202362.png`、`[AE]/GroupsUITests/1FD29EAB-1EF5-4288-9013-0E26F10F330E.png` |
| 分组列表 / 分组详情 | `[AE]/GroupsUITests/DE0E3F98-3FC6-49BD-9FA7-FDAFB09D082A.png`、`2F76EDCA-FE3C-4526-863B-BCBC0CB994B8.png` |
| 登录 | `[LOGIN]` |
| 无截图（只依据代码） | 设置、管理 Tab 根页、用户编辑表单、余额表单、日志筛选、分析筛选、分组编辑、账号编辑、手动测试、二次验证、iPad |

## 附录 B：量化统计（可复核）

| 指标 | 数值 | 命令或来源 |
|---|---|---|
| NativeApp Swift 行数 | 4314 | `find NativeApp -name "*.swift" \| xargs wc -l` |
| “不可用”出现次数 | NativeApp 25 / Sub2Core 17 | `grep -o '不可用' -r` |
| 就地 `.caption/.footnote/.caption2` | 93 | `grep -rn "font(.caption)\|font(.footnote)\|font(.caption2)" NativeApp` |
| `role: .destructive` | 15（其中 8 个是“确认××”类按钮） | `grep -rn "role: .destructive" NativeApp` |
| 文字型 `ProgressView(` | 26 | `grep -rn "ProgressView(" NativeApp` |
| `ContentUnavailableView`/`FailureView` 使用 | 各 1 | 同上 |
| `accessibilityIdentifier(` | 185 | `grep -o 'accessibilityIdentifier(' -r NativeApp` |
| UITest 用例 | 35（7 个文件） | `grep -c "func test" UITests/*.swift` |
| 指向 Web 后台的文案 | 14 | `grep -rn "Web 后台\|在 Web\|Web 核对\|Web 完成" NativeApp` |
