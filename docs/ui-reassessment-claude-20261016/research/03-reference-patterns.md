# 03 同类移动运维/管理 App 界面模式 + iOS 26/27 设计规范与 SwiftUI API 调研

> 调研日期：2026-10-16（今天）。调研者：Claude（独立调研，未阅读 `docs/ui-reassessment-20261016/` 下 codex 的方案文档）。
> 适用对象：`G:/weixinProject/sub2-mobile-native`（Sub2API 管理端 iOS 原生客户端，SwiftUI，最低 iOS 17，Xcode 27 SDK，iPhone + iPad）。

---

## 0. 摘要与方法

### 0.1 最关键的结论（先读这一节）

1. **【证实】Liquid Glass 只属于"导航/控件层"，不属于"内容层"。** HIG Materials 原文："Don't use Liquid Glass in the content layer"；"Use Liquid Glass effects sparingly"。高密度管理工具的内容（列表行、指标卡、日志）应使用标准背景/材质，而不是玻璃卡片。（第 1.10 节）
2. **【证实】iOS 26 对列表与表单做了"变松"处理**（行高与内边距增大、Section 圆角增大）。Apple 在 *Adopting Liquid Glass* 中写明 "Lists, tables, and forms have a larger row height and padding"。结论是：如果继续用 `Form` 或 inset grouped `List` 承载只读的高密度数据，在 iOS 26 上会比 iOS 17/18 更占地方、更"稀"，这是用户觉得"丑、反人类"的结构性原因之一。（第 1.3 节、第 4 节）
3. **【证实】同类产品（Datadog、PagerDuty、Grafana、Stripe、AWS Console、GitHub、Linear、阿里云）几乎都遵循同一套骨架**：首页先放"需要处理"的计数，计数可以点进对应列表；列表行先给状态，再给标题，最后给 1 行元数据，右侧放相对时间或金额；筛选用横向胶囊或"我的/全部"分段；详情页先放摘要和主操作，再放键值和时间线；批量操作走选择模式加底部操作条。（第 2 节）
4. **【证实】当前代码有几处与 HIG 明确冲突。** 一是批量"暂停调度"这种可逆操作用了 `role: .destructive` 和"确认执行"按钮（`NativeApp/Features/AccountsView.swift:155`）。二是 sheet 叠 sheet（`AccountsView.swift:616`、`UsersView.swift:356`），HIG 要求 "Display only one sheet at a time"。三是控件和说明文字被塞进了内容列表（`AccountsView.swift:68-89`、`RequestLogsView.swift:30-57`）。四是筛选需要手动输入数字 ID（`RequestLogsView.swift:212-218`）。（第 4 节）
5. **【证实】iOS 27（WWDC26，2026-06）已带来新 API，同时弃用了旧 API。** `tabItem(_:)` 在 iOS 27.2 被标记弃用，Apple 建议改用 `Tab(...)`；当前代码 `Sub2MobileApp.swift:37-41` 仍在用 `.tabItem`。新增的 API 包括 `TabRole.prominent`、`ToolbarOverflowMenu`、`toolbarMinimizationBehavior`、任意视图上的 swipe actions（`swipeActionsContainer()`），以及绑定 item 的 alert/confirmationDialog。（第 1.1 节、第 6 节）
6. **【证实】App Store 官方统计（2026-06-07）显示 79% 的 iPhone 已在 iOS 26。** 最低部署版本保持 iOS 17 的代价，是 `Tab`、`TabSection`、`sidebarAdaptable`、`Tab(role: .search)` 都需要写 `#available` 双分支。是否把最低版本提到 iOS 18 是一项值得单独决策的事。（第 6 节）
7. **【证实/推断】中文数字排版。**
   - 【证实】在 zh-CN 区域，系统 ICU 的默认货币格式会把美元格式化为 `US$1,234.50`；紧凑数字会输出 `1.2万 / 1.2亿`，而不是 `K/M`。
   - 【证实】当前代码的金额字符串没有千分位（`Sources/Sub2Core/DashboardPresentation.swift:53-56, 89-98`）。
   - 【证实】列表行没有使用等宽数字（`RequestLogsView.swift:122-126`）。
   - 【推断】建议统一做成一套格式化器。（第 5 节）
8. **【推断】新首页可以以"待处理"为骨架。** 这和 Grafana mobile 的 Home/Browse 结构、AWS/阿里云的"告警计数卡"高度一致，也最容易平滑扩展到未来的普通用户端（余额、Key、用量、订阅）。

### 0.2 证据等级与来源说明

- 本文用 **【证实】** 标注有原文或代码证据的结论，用 **【推断】** 标注基于证据的推理或建议。
- Apple HIG 原文通过 Apple 文档 JSON 接口抓取（`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`），与网页版内容相同，引用时给出网页版 URL。
- SwiftUI API 的最低版本全部通过 Apple 文档 JSON 的 `metadata.platforms[].introducedAt` 字段逐个核实（2026-10-16 抓取，共 150+ 个符号），没有凭记忆填写。
- 同类产品截图来自 **App Store 营销截图**，通过 `https://itunes.apple.com/lookup?id=<id>&country=us` 获取。营销截图可能落后于真实版本，例如 PagerDuty 的首页截图里出现了 2021 年的日期，所以只用来佐证"模式"，不用来佐证"现状"。
- 当前 Sub2 界面截图（本地）：
  - S1 日志列表：`G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/admin-expansion-20261016/final-evidence/collection/attachments/RequestLogsUITests/E1C59092-83FB-401F-90ED-B201F325CA77.png`
  - S2 请求详情：`.../RequestLogsUITests/9A6FA137-E2D8-4449-9B27-91AD1A8F4DC9.png`
  - S3 账号批量菜单：`.../AccountManagementUITests/0FE95C0E-ADA5-4FF6-BA37-E240ADED809C.png`
  - S4 分组列表：`.../GroupsUITests/DE0E3F98-3FC6-49BD-9FA7-FDAFB09D082A.png`
  - S5 概览下半屏：`G:/weixinProject/sub2-mobile-artifacts/native-ios-rebuild/dashboard-polish/compact-screenshots/dashboard-final-state.png`
  - S6 概览分区：`.../dashboard-polish/compact-screenshots/dashboard-automatic-sections.png`
- **披露**：用 CodeGraph 检索 `TabView` 结构时，返回结果里意外带出了 codex 演示文件 `docs/ui-reassessment-20261016/design-demos/b.jsx` 的片段（Tab 定义与账号页草稿）。本报告的结论都基于 HIG、产品资料和 Sub2 源码，没有以该片段为依据。

### 0.3 时间基线（避免把 iOS 26 当成"最新"）

- 【证实】WWDC26（2026-06-08）发布了 iOS 27。Apple 的 SwiftUI 更新页有 "June 2026" 和 "September 2026" 两个分区，见 https://developer.apple.com/documentation/updates/swiftui 。
- 【证实】Liquid Glass 在 iOS 27 中被"精修"：外观自动更新，并跟随新的 Liquid Glass 色调滑杆。见 WWDC26 "What's new in SwiftUI"：https://developer.apple.com/videos/play/wwdc2026/269/ 。
- 【证实】TechTimes 报道 iOS 27 的调整是对 iOS 26 可读性批评的回应，包括透明度滑杆和搜索回归 Tab 栏。见 https://www.techtimes.com/articles/317975/20260608/apple-liquid-glass-ios-27-wwdc-2026-brings-refinements-developers-must-adopt-today.htm 。这是媒体报道，属于二手来源。
- 【证实】App Store 统计（2026-06-07）：79% 的 iPhone 在 iOS 26，近四年发布的机型中这一比例为 86%。见 https://developer.apple.com/support/app-store/ 。

---

## 1. Apple HIG（Liquid Glass 时代）要点与对 Sub2 的含义

### 1.1 Tab bar（含 search tab、bottom accessory、最小化、iPad 侧栏）

来源：https://developer.apple.com/design/human-interface-guidelines/tab-bars （变更记录：2025-07-28 加入 Liquid Glass 指引，2025-12-16 更新，2026-06-08 更新术语与配图）

【证实】HIG 要点：
- "Use for navigation, not actions"。Tab 只用于在顶层区块之间导航；作用于当前视图的操作应放进 toolbar。
- "Keep the tab bar visible"。只有模态视图可以盖住 Tab 栏。
- "Avoid overflow tabs"。iPhone 上 Tab 过多时末位会变成 More，把内容藏起来。iPad 上如果允许自定义，"keep the default list to five or fewer"。
- "Don't disable or hide tab buttons"。内容为空时应解释原因，而不是禁用 Tab。
- "Use badges only for critical information"。Tab 徽标是红底白字，只用于需要注意的关键信息。
- iOS 的 Tab 栏浮在内容之上，背景是 Liquid Glass。
- **最小化**：只有带附属视图的 Tab 栏（例如 Music 的 MiniPlayer）才建议在下滑时最小化，同时让附属视图内联显示。对应 `TabBarMinimizeBehavior`。
- **Search tab**：Tab 栏末端可以放一个专门的搜索 Tab。
- **iPadOS**：Tab 栏在顶部，可以变成侧栏（`TabViewStyle.sidebarAdaptable`）。如果只需要侧栏，应使用 `NavigationSplitView`。

【证实】Search fields 页（2026-06-08 更新）把 search tab 分成两种外观：
- 标准 Tab：用于发现和浏览类内容。
- 按钮外观：点击后立即聚焦搜索框，用于"快速找到要找的东西"，并能直接返回上一个 Tab。

来源：https://developer.apple.com/design/human-interface-guidelines/search-fields

【证实】API 与版本：
- `Tab`、`TabRole.search`、`TabSection`、`.tabViewStyle(.sidebarAdaptable)`、`.tabViewCustomization`：iOS 18.0。
- `.tabViewBottomAccessory(content:)`、`.tabBarMinimizeBehavior(_:)`、`.tabViewSearchActivation(_:)`、环境值 `tabViewBottomAccessoryPlacement`：iOS 26.0。
- `.tabViewBottomAccessory(isEnabled:content:)`：iOS 26.1。
- `TabRole.prominent`：iOS 27.0。WWDC26 说明它会把一个 Tab 单独放在右下角。
- `tabItem(_:)`：**iOS 27.2 标记弃用**，弃用说明为 "Use `Tab(title:image:value:content:)` and related initializers instead"。

【证实，第三方】在 iOS 27.2 上，`Tab(role: .search)` 如果没有声明 `.tabViewSearchActivation(.searchTabSelection)`，会退化成普通内联 Tab，并在导航栏里显示搜索栏。加上这个修饰符后，才会保留独立的浮动搜索按钮。证据：
- https://github.com/zubair-io/Maple/pull/4409 （2026-10-08 合并）
- https://github.com/NativeScript/NativeScript/pull/11509

**对 Sub2 的含义**
- 【证实】当前是 5 个 Tab，其中"管理"Tab 是一个只有 3 个链接的中转列表（`Sub2MobileApp.swift:34-61`），而且仍在用即将弃用的 `.tabItem`。
- 【推断】"管理"Tab 本身没有违反 HIG，但它是一个低信息密度的"抽屉"，会把日志这种高频功能推到第二层。
- 【推断】更重要的是，没有一个"跨实体搜索"入口。用户想查某个用户邮箱、某个请求 ID、某个账号名时，必须先猜对它在哪个 Tab。
- 【推断】如果要加 Tab 徽标，只适合"异常上游账号数"这类关键信息，不适合"新日志数"。

### 1.2 Toolbars（导航栏/工具栏）

来源：https://developer.apple.com/design/human-interface-guidelines/toolbars （2025-06-09 加入分组指引；2025-12-16 更新 Liquid Glass 指引）

【证实】HIG 要点：
- "Minimize the number of groups. Aim for a maximum of three."
- "Keep actions with text labels separate from symbol-only actions"。相邻的文字按钮看起来会像一个控件，需要插入固定间距。
- "Use the `.prominent` style for key actions such as Done or Submit"；"Specify only one primary action, and place it on the trailing side"。
- "Reduce the use of toolbar backgrounds and tinted controls"。不要加自定义背景，需要区分 toolbar 和内容时使用 `ScrollEdgeEffectStyle`。
- 优先使用简单可识别的符号，而不是文字；"edit"这类符号难以表达的操作例外。
- 标题应简洁，"under 15 characters"。
- iOS 上只把最重要的项目放进主 toolbar，其余放进 More 菜单。使用大标题来帮助定位。
- 返回和关闭使用标准按钮，不要用带 "Back" 文字的胶囊按钮。

【证实】WWDC25-323 "Build a SwiftUI app with the new design"（https://developer.apple.com/videos/play/wwdc2025/323/ ）：
- `ToolbarSpacer(.fixed/.flexible)` 用来分组（iOS 26.0）。
- `sharedBackgroundVisibility(.hidden)` 用来移除单个项目的分组背景（iOS 26.0）。
- toolbar 项目上可以直接使用 `.badge()`。
- 图标默认单色；`tint` 只用来 "convey meaning, like a call to action or next step, but not just for visual effect"。

【证实】iOS 27 新增（WWDC26-269，以及上文的 SwiftUI 更新页）：
- `ToolbarContent.visibilityPriority(_:)`：iOS 27.0。
- `ToolbarOverflowMenu`：iOS 27.0。
- `ToolbarItemPlacement.topBarPinnedTrailing`：iOS 27.0。
- `View.toolbarMinimizationBehavior(_:for:)`：iOS 27.0。

**对 Sub2 的含义**
- 【证实】账号列表的 toolbar 左侧是文字按钮"选择/完成选择"，右侧是图标"显示字段"（`AccountsView.swift:133-141`）。"显示字段"使用了 `line.3.horizontal.decrease` 这个筛选样式的图标（`AccountsView.swift:139`），而真正的"筛选与排序"却放在列表的第一行（`AccountsView.swift:69-71`）。图标语义和功能是错位的（截图见 S3 右上角）。
- 【推断】应把"筛选"放回 toolbar 或筛选胶囊条，"显示字段"放进 More 菜单。

### 1.3 Lists and tables

来源：https://developer.apple.com/design/human-interface-guidelines/lists-and-tables

【证实】HIG 要点：
- "Prefer displaying text in a list or table"。
- "Keep item text succinct ... For large text per item, list only titles and let people open a detail view"。
- 可能被截断的文本，可以用中间省略号同时保留开头和结尾。这非常适合请求 ID、API Key、长账号名。
- 信息按钮只用于展示行内容的补充信息；进入下一层用 disclosure 指示箭头。

【证实】*Adopting Liquid Glass* 说明 "Lists, tables, and forms have a larger row height and padding, and sections have an increased corner radius"，并且 Section 标题不再自动全大写。来源：https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

**对 Sub2 的含义**
- 【证实】账号行把 8 到 12 个"字段：值"平铺换行展示（`AccountsView.swift:197-204`，截图 S3）。
- 【证实】请求日志的一行有 5 行文字（`RequestLogsView.swift:116-128`，截图 S1）。
- 【推断】这两处都与 "Keep item text succinct" 相悖。iOS 26 又进一步放大了行高，导致一屏只能显示 2 到 3 条记录。

### 1.4 Search fields / Tokens / Scope

来源：https://developer.apple.com/design/human-interface-guidelines/search-fields （2025-06-09 加入 tokens 指引；2026-06-08 细化 search tab 指引）

【证实】HIG 要点：
- iOS 上有三种入口：Tab 栏中的搜索 Tab、顶部或底部 toolbar、与内容内联。
- "Place search at the bottom if there's room"。
- "Place search as an inline field when its position alongside the content it searches strengthens that relationship"。
- 搜索最好随输入立即开始。
- 建议在开始前展示最近搜索，在输入时展示预测建议。
- 最相关的结果放在最前，并考虑分类展示。
- Scope bar 用于 "clearly defined search categories"，"Default to a broader scope and let people refine it"。
- Token 用于 "filter by common search terms or items"，并且 "Consider pairing tokens with search suggestions. People may not know which tokens are available."

【证实】API 与版本：
- `.searchable(text:tokens:placement:prompt:token:)`：iOS 16.0。
- `.searchSuggestions(_:)`：iOS 16.0。
- `.searchScopes(_:scopes:)`：iOS 16.0。
- `.searchScopes(_:activation:_:)`：iOS 16.4。
- `ContentUnavailableView.search(text:)`：iOS 17.0。
- `.searchFocused(_:)`：iOS 18.0。
- `.searchToolbarBehavior(_:)`、`DefaultToolbarItem`：iOS 26.0。

文档说明：在 iOS 上，scope 默认在用户输入文字后才出现；可以用 `activation` 参数调整这一行为。

### 1.5 Charts

来源：https://developer.apple.com/design/human-interface-guidelines/charts

【证实】HIG 要点：
- "highlights a few key pieces of information"。
- "Summarize the main message of your chart"。标题和副标题应直接说出结论。
- 在紧凑环境中，"maximize the width of the plot area"，纵轴标签尽量短，"Put units in a title"。
- "Let people interact with the data when it makes sense, but don't require interaction to reveal critical information"。
- 如果标记太小难以点中，"consider expanding the hit target to include the entire plot area"。
- 不要只靠颜色区分数据。
- 柱状图通常以 0 为下界。
- 为 VoiceOver 提供 Audio Graphs 和描述。

【证实】API 与版本：
- `Chart`：iOS 16.0。
- `chartXSelection(value:)`、`chartScrollableAxes(_:)`、`chartXVisibleDomain(length:)`：iOS 17.0。
- `accessibilityChartDescriptor(_:)`：iOS 15.0。

**对 Sub2 的含义**
- 【证实】概览的趋势卡在图下方放了"点选柱子查看数值；放大后可左右滑动，双指缩放或使用按钮调整。"这句操作说明，还有"逐小时明细""刷新趋势"两个按钮和"更新于"（截图 S5、S6）。
- 【推断】这违背了 "don't require interaction to reveal critical information"。说明文字的存在本身，就说明关键信息被藏在了交互后面。

### 1.6 Sheets 与 detents

来源：https://developer.apple.com/design/human-interface-guidelines/sheets （2026-03-24 更新按钮位置）

【证实】HIG 要点：
- Sheet 用于 "a scoped task that's closely related to their current context"。
- iPhone 上 "consider supporting the medium detent to allow progressive disclosure"。可调整高度的 sheet 要显示 grabber。
- 单步 sheet：左侧放 Cancel，右侧放 Done。"Provide an alternative to the Done button"；"Avoid showing all three buttons — Cancel, Done, and Back — together"。
- 有未保存修改时开始下滑关闭，"use an action sheet to let them confirm"。
- **"Display only one sheet at a time from the main interface"**；"If closing a sheet takes people back to another sheet, they can lose track of where they are"。

【证实】iOS 26 的变化（*Adopting Liquid Glass* 与 WWDC25-323）：
- 半高 sheet 会从屏幕边缘内缩，显露下方内容，展开到全高后变得不透明。
- "If you've used the `presentationBackground` modifier ... consider removing that"。

【证实】API 与版本：
- `.presentationDetents(_:)`、`.presentationDetents(_:selection:)`、`.presentationDragIndicator(_:)`：iOS 16.0。
- `.presentationBackgroundInteraction(_:)`、`.presentationContentInteraction(_:)`、`.presentationBackground(_:)`、`.presentationCompactAdaptation(_:)`：iOS 16.4。
- `.presentationSizing(_:)`：iOS 18.0。
- `.interactiveDismissDisabled(_:)`：iOS 15.0。

### 1.7 Menus 与 Context menus

来源：https://developer.apple.com/design/human-interface-guidelines/menus （2026-06-08 更新菜单图标指引）、https://developer.apple.com/design/human-interface-guidelines/context-menus

【证实】Menus 要点：
- 标签用动词。
- 重要项目放前面。
- 相关项目分组。
- 子菜单只用一层，超过约 5 项时考虑拆成新菜单。
- 需要后续输入的项目加省略号（例如"调整余额…"）。
- 同一组里要么全部有图标，要么全部没有。
- 不可用的项目显示为灰色（普通菜单）。

【证实】Context menus 要点：
- "Always make context menu items available in the main interface, too"。
- "Hide unavailable menu items, don't dim them"。
- "you don't want more than about three groups"。
- 破坏性项目放在最后并标记为 destructive。
- 多选时可以用标题说明选中数量，例如 Mail 显示选中邮件数。
- 推荐提供图形化预览。

【证实】*Adopting Liquid Glass*："Match top menu actions to swipe actions"。

【证实】API 与版本：
- `Menu`：iOS 14.0。
- `Menu(content:label:primaryAction:)`：iOS 15.0。
- `.contextMenu(menuItems:preview:)`：iOS 16.0。
- `.contextMenu(forSelectionType:menu:primaryAction:)`：iOS 16.0，支持 List 多选后的上下文菜单。
- `.menuActionDismissBehavior(_:)`：iOS 16.4。
- `.menuOrder(_:)`：iOS 16.0。
- `PalettePickerStyle`：iOS 17.0。

### 1.8 Alerts vs Action sheets（confirmationDialog）vs 撤销

来源：https://developer.apple.com/design/human-interface-guidelines/alerts 、https://developer.apple.com/design/human-interface-guidelines/action-sheets

【证实】Alerts 要点：
- "Avoid using an alert merely to provide information"。
- **"Avoid displaying alerts for common, undoable actions, even when they're destructive"**。
- "when people take an uncommon destructive action that they can't undo ... display an alert"。
- 用户主动选择的破坏性操作，其确认按钮不使用破坏性样式；只有"用户并非有意选择的破坏性操作"才用 destructive。
- 按钮标题要描述结果，"Avoid using OK as the default button title unless the alert is purely informational"。
- 有破坏性操作时必须提供标题为 "Cancel"（中文"取消"）的按钮。
- "Avoid showing an alert when your app starts"。

【证实】Action sheets 要点：
- "Use an action sheet — not an alert — to offer choices related to an intentional action"。
- 破坏性选项放在顶部并使用 destructive 样式。
- 取消按钮放在底部。
- "Avoid letting an action sheet scroll"。
- SwiftUI 对应 `confirmationDialog`，并且 "A SwiftUI confirmation dialog includes a Cancel button by default"。

【证实】iOS 26 的变化：
- WWDC25-356 说明 action sheet 会从触发它的控件处"弹出"（"spring from the action itself"）。
- *Adopting Liquid Glass* 要求 "Specify the source of an action sheet"。

【证实】API 与版本：
- `.confirmationDialog(_:isPresented:titleVisibility:actions:message:)`、`.alert(_:isPresented:actions:message:)`：iOS 16.0（文档页标注版本）。
- WWDC26 新增绑定 item 的 `confirmationDialog(_:item:...)` 与 `alert(_:item:...)`。文档页把它们标为 iOS 15.0，推测是回溯部署，需要在 Xcode 27 中编译验证。
- `.sensoryFeedback(_:trigger:)`：iOS 17.0。
- `dialogSeverity(_:)` 在 iOS 上不可用，仅支持 macOS。

### 1.9 状态、徽标与颜色

来源：https://developer.apple.com/design/human-interface-guidelines/color 、https://developer.apple.com/design/human-interface-guidelines/accessibility 、https://developer.apple.com/design/human-interface-guidelines/gauges

【证实】HIG 要点：
- "Avoid using the same color to mean different things"。
- "Avoid relying solely on color"。
- Color 页以股票 App 为例：涨在英文环境显示为**绿色**，在中文环境显示为**红色**。
- 玻璃上的颜色 "reserve it for elements that truly benefit from emphasis, such as status indicators or primary actions"，并且 "Refrain from adding color to the background of multiple controls"。
- 对比度目标：17pt 以下文字 4.5:1；18pt 文字或粗体 3:1。
- 控件默认 44x44pt，最小 28x28pt。
- Gauge 有 "capacity style"（填充到当前值），标签应说明当前值和两端。

【证实】API 与版本：
- `.badge(_:)`（Int/Text）：iOS 15.0。
- `.badgeProminence(_:)`：iOS 17.0。
- `Gauge`、`.gaugeStyle(.linearCapacity / .accessoryLinearCapacity)`：iOS 16.0。
- `.symbolRenderingMode(_:)`：iOS 15.0。

**对 Sub2 的含义**
- 【证实】请求日志行里，"扣费"用绿色、"成本"用橙色（`RequestLogsView.swift:122-123`）；账号行里"调度：参与调度"用绿色（`AccountsView.swift:203`）。
- 【推断】在中文语境中，绿色既不代表"收入/正向"，也不代表"健康"，含义模糊。这两处都是"仅靠颜色"传达语义，颜色也缺少统一含义。

### 1.10 Materials 与 Liquid Glass 的使用限制

来源：https://developer.apple.com/design/human-interface-guidelines/materials （2025-06-09 加入，2025-09-09 更新）

【证实】原文要点：
- "Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer"。
- **"Don't use Liquid Glass in the content layer."** 例外：滑块、开关等瞬时交互控件可以在被激活时呈现玻璃效果。
- "Use Liquid Glass effects sparingly ... Overusing this material in multiple custom controls can provide a subpar user experience by distracting from that content. Limit these effects to the most important functional elements"。
- Regular 变体用于大多数系统组件。Clear 变体 "Only use clear Liquid Glass for components that appear over visually rich backgrounds"，例如照片和视频。
- 内容层使用标准材质：ultraThin、thin、regular、thick。

【证实】WWDC25-323 补充：
- "glass can not sample other glass"。相邻的玻璃元素应放进同一个 `GlassEffectContainer`。
- 着色玻璃 `.glassEffect(.regular.tint(.green))` 只用来表达含义。

【证实】WWDC25-356 补充：
- 自定义控件要 "apply the material directly to the control, not its inner views"。
- "Elements using Liquid Glass require clear separation from content to maintain legibility"。

【证实】API 与版本：
- `.glassEffect(_:in:)`、`Glass`（`.regular/.clear/.tint/.interactive`）、`GlassEffectContainer`、`.glassEffectID(_:in:)`、`.glassEffectTransition(_:)`：iOS 26.0。
- `.buttonStyle(.glass / .glassProminent)`：iOS 26.0。
- `ConcentricRectangle`：iOS 26.0。
- `.backgroundExtensionEffect()`：iOS 26.0。
- `.scrollEdgeEffectStyle(_:for:)`、`.scrollEdgeEffectHidden(_:for:)`、`.safeAreaBar(edge:alignment:spacing:content:)`：iOS 26.0。

【证实】外部批评：NN/g 的 "Liquid Glass Is Cracked, and Usability Suffers in iOS 26"（https://www.nngroup.com/articles/liquid-glass/ ）指出几类问题：
- 透明控件压在繁杂背景上导致对比不足。
- 动态缩放和移动的控件 "makes the interface harder to learn and less predictable"。
- 溢出菜单只应放 "nonessential actions"。
- 拆分后的 Tab 栏 "harder to scan at a glance"。

【推断】对高密度数据工具来说，正确的姿态是"少即是多"：
- 系统控件自动获得玻璃效果就足够了。
- 自定义玻璃最多用在 1 到 2 个悬浮控件上，例如底部批量操作条、悬浮主操作。
- 内容区一律使用不透明的系统背景。

### 1.11 Segmented controls（分段控件）

来源：https://developer.apple.com/design/human-interface-guidelines/segmented-controls

【证实】HIG 要点：
- 分段控件用于 "closely related choices"，以及 "switch between closely related subviews"；完全独立的区块应该用 Tab 栏。
- iPhone 上 "no more than about five segments"。
- 同一个控件里要么全用文字，要么全用图标。

**对 Sub2 的含义**
- 【证实】日志页在三种记录（请求、失败、上游错误）之间用 3 段切换（`RequestLogsView.swift:31-33`），符合规范。
- 【推断】问题在于它被放进了一张内容卡片，并和时间文案、说明文字、链接挤在同一个 Section 里（截图 S1）。

### 1.12 Typography 与 Dynamic Type

来源：https://developer.apple.com/design/human-interface-guidelines/typography （2025-12-16 加入强调字重）

【证实】HIG 要点：
- iOS 默认字号 17pt，最小 11pt。
- "When font size increases in a horizontally constrained context ... consider using a stacked layout where text appears above secondary items"。
- "Reduce the number of columns when the font size increases"。
- "Maintain a consistent information hierarchy regardless of the current font size"。
- "Avoid truncating text in scrollable regions unless people can open a separate view to read the rest"。

---

## 2. 同类产品调研

调研对象共 10 个，其中有官方 App 的 9 个，阿里云作为中文参照。另记录 4 个"缺席者"。

### 2.1 Datadog（iOS 6.1.4，2026-10-15）

来源：
- 官方文档 https://docs.datadoghq.com/mobile/
- 小组件文档 https://docs.datadoghq.com/mobile/widgets/
- 博客 https://www.datadoghq.com/blog/mobile-app-reduce-mttr/
- App Store https://apps.apple.com/us/app/datadog/id1391380318 （截图 #1 到 #6）

- **首页组织**：【证实】首页点 "Edit" 可以添加和排列收藏、最近访问、进行中的 incidents、已保存的 monitor 视图和团队资源（官方文档）。小组件覆盖 incidents、on-call、monitors、SLO 和仪表盘数值，提供"首页之外的首页"。
- **列表行解剖**：【证实，截图 #2、#6】
  - Incidents：第 1 行是时间戳加括号里的相对时间，例如 "Aug 7, 2025 at 8:25 AM (4d)"，右上角是 ACTIVE/RESOLVED 实心徽标；第 2 行是严重度图标加 "SEV-3 • Default"；第 3 行是标题；第 4 行是负责人头像和名字。
  - Pages 列表：同样是"时间 + 右上状态徽标（TRIGGERED/ACKNOWLEDGED）+ 浅色 HIGH URGENCY 标签 + 标题 + 负责人"。
  - 列表顶部有 "Showing 50 incidents" 计数，Incidents 顶部还有一行 SEV-1 到 SEV-4 的计数卡，可以横向滚动。
  - Logs 行：时间加右侧级别徽标（INFO/NOTICE），消息用等宽字体。
- **筛选交互**：【证实】基于查询语法的搜索（如 `status:Alert type:Metric team:sre`），自动保存"最近 10 次搜索"，并支持 saved views。Logs 页有 Logs/Patterns 分段。仪表盘的时间范围按钮在右下角，支持模板变量。
- **详情页结构**：【证实，截图 #3、#4】
  - Page 详情：顶部是编号和 "Triggered 3 min ago"，接着是状态徽标和紧急度徽标、大标题。下面是 3 个等宽主操作按钮（Acknowledge 实心为主，Resolve 次之，More），再往下是 Overview/Timeline 分段、两列键值（PAGE TARGET / ASSIGNEE）、触发源卡片，以及 "View Logs""View Traces" 两个跳转胶囊。
  - Monitor 详情：状态徽标、"2 min. ago"、图表，图表上用红色背景带标出告警阈值区；下方是可拖动的 sheet，显示 "3 OF 13 GROUPS SELECTED" 和每组的状态时间条。
- **批量与危险操作**：【证实】从告警可以执行 acknowledge、mute monitor、declare incident（博客）。官方文档没有描述批量与确认流程。
- **图表呈现**：仪表盘逐个控件纵向排列；每个图表有标题，并提供"全屏"和"分享"图标。

### 2.2 PagerDuty（iOS 8.83.1，2026-10-13）

来源：
- 官方文档 https://support.pagerduty.com/main/docs/mobile-app
- App Store https://apps.apple.com/us/app/pagerduty/id594039512 （截图 #1 到 #4，首页截图里有 2021 年的日期，是旧 UI）

- **首页组织**：【证实】底部 Tab 为 Home、Incidents、My Shifts、Services、More。Home 显示 "My Open Incidents"，带总数，展示最近 3 条，可以展开到 10 条，再进入 "View All Open Incidents"。下面依次是值班卡片和"最近受影响服务"（带警告图标和 "3 Impacting Incidents"）。
- **列表行解剖**：【证实，截图】行的左侧有一条红色竖条表示 triggered 状态，接着是标题和 SERVICE 小标签加服务名，右侧是 ASSIGNEE。被分配给自己的 triggered 事件会让顶部横幅变红，确认后变黄（文档）。
- **筛选交互**：【证实】Mine / My Teams / All 三个 Tab，并且 "remember which tab filter you most recently selected"。排序可选 Urgency、Priority、Recent。已解决的事件不在主列表里，放在 More 下面。
- **详情页结构**：【证实】
  - 底部操作栏：Ack，确认后变成 Snooze；Resolve；All Actions。
  - Triage 和 Overview 两个分段。
  - Triage 页是一排图标操作（Status Update、Add Note、Add Priority、Run Play…）。
  - Overview 页包含服务、响应人、时间线、告警、历史事件。
  - 截图里还有 "10 MINUTES TO ESCALATION" 红色倒计时和 "15M AGO"。
- **批量与危险操作**：【证实】左滑后点 Ack 或 Resolve；对已确认的事件左滑是 Snooze，**滑动操作随状态变化**。官方营销页的说法是 "Swipe quickly and confidently to acknowledge and resolve incidents"。文档只给值班覆盖（override）描述了确认弹窗。
- **图表呈现**：移动端基本不放图表，以状态和时间为主。

### 2.3 Grafana mobile（原 Grafana IRM，iOS 2.49.1，2026-10-07）

来源：
- https://grafana.com/docs/grafana-cloud/platform/mobile-app/get-started/
- https://grafana.com/docs/grafana-cloud/platform/mobile-app/irm/respond-to-alerts/
- App Store https://apps.apple.com/us/app/grafana/id1669759048 （截图来自 Android 版，信息架构相同）

- **首页组织**：【证实】4 个 Tab：Home、Browse、Assistant、Settings。
  - Home 汇集用户勾选的产品分区：My schedules、My alert groups、My incidents、Starred dashboards。可以在 Settings 里 "Customize Home" 调整显示和顺序。
  - Browse 列出有权限查看的全部告警组、排班、事件和仪表盘。
  - 截图 #1 中，"My alert groups" 先显示三个状态计数（Firing 10+ 红色、Ack 4 橙色、Silenced 2 灰色），然后是最新一条带内联操作的条目；"My incidents" 为空时显示 "All looks great! You have no active incidents."
- **列表行解剖**：【证实，截图 #4】每张卡片包含状态徽标（Firing / Acknowledged）、标签数、右上角相对时间（"3mo"）、标题，以及一行内联操作（Acknowledge、Resolve、"…"）。
- **筛选交互**：【证实】Mine / All 分段。toolbar 里有"选择模式"图标和"筛选"图标，**筛选图标在有筛选生效时右上角会出现蓝点**（截图 #4）。
- **详情页结构**：【证实】Details 和 Timeline 两个分段。Details 包括元数据、参与者、关联事件和最近一条 payload（可以 View JSON）。Timeline 是 "a chronological record of notifications and status changes"。
- **批量与危险操作**：【证实】在 Browse > Alert groups 里点选择图标进入多选，**底部操作栏**提供 Acknowledge 和 Resolve，More 菜单里有 Silence 和 Restart。组织要求时，Resolve 会提示填写处理说明。"Skip to next escalation" 会先预览接下来的步骤，再确认。推送通知上可以直接执行 Acknowledge 或 "Silence for 30 minutes"。
- **图表呈现**：仪表盘逐面板纵向排列；面板标题可以点击进入，图例放在图下方。

### 2.4 Stripe Dashboard（iOS 2.95.0，2026-10-13）

来源：
- 官方文档 https://docs.stripe.com/dashboard/mobile
- App Store https://apps.apple.com/us/app/stripe-dashboard/id978516833 （截图 #1 到 #6）

- **首页组织**：【证实，文档与截图 #1】
  - 顶部 "Today" 横向指标条：Gross volume $7.8K、Payments 215、Customers 213，可以继续横滑。
  - 接着是 "Reports overview"（右侧有 Edit），下面是时间范围胶囊分段：1W、4W、1Y、MTD、QTD、YTD、ALL。
  - 指标卡显示当前值 $178.02K、与上期对比 +8.3%、对比值 $164.4K，以及双线图（本期和上期）。
  - 文档说明 iOS 上点击 Edit 可以增删和排序图表。
  - 锁屏小组件有 17 种指标。
- **列表行解剖**：【证实，截图 #6】Payments 行：左侧是方形状态图标（绿色对勾）；主行是"金额 + 状态"（"$12.00 succeeded"）；次行依次是邮箱、支付 ID、"Jul 15 at 12:48 PM"；右侧是箭头。Balances 页是键值行，金额右对齐并带千分位（"$39,826.00"）。
- **筛选交互**：【证实，截图 #6、#5】
  - Payments 顶部是二级分类 Tab：Payments、Invoices、Subscriptions、Payment links。
  - 下面一排**下拉胶囊** "Status""Created"。
  - 全局搜索带 **scope 标签**：All、Customers、Payments、Invoices、Subscriptions。结果按类型分组，每组有 "View all"。
- **详情页结构**：【证实，截图 #2】顶部金额摘要，然后是 Products、Latest payments、Details（键值，状态为绿色 "Active"）。**底部操作栏**放一个实心主按钮（Copy link）和一个 "…" 更多按钮。退款流程是进入成功支付后，"Go to the action bar at the bottom, and tap Refund"。
- **批量与危险操作**：【证实】
  - 退款要输入金额，并选择是否部分退款。
  - 取消订阅需要 "Confirm if you want to cancel the subscription immediately or at the end of the billing period"，这是一个**带选项的确认**。
  - 停用支付链接 "immediately deactivates without a confirmation prompt"，误操作可以在底部操作栏点 Activate 恢复，**这是可撤销操作不弹确认的例子**。
  - "View only" 角色无法退款，按权限隐藏操作。
- **图表呈现**：小折线图加对比期，时间范围用胶囊分段，指标值大字显示。

### 2.5 AWS Console（iOS 3.24.0，2026-10-06）

来源：
- 官方指南 https://docs.aws.amazon.com/consolemobileapp/latest/userguide/what-is-consolemobileapp.html
- App Store https://apps.apple.com/us/app/aws-console/id580990573 （截图 #1 到 #4）

- **首页组织**：【证实】
  - 文档："overview of the account status with real-time data on Amazon CloudWatch, AWS Personal Health Dashboard, AWS Billing and Cost Management, and Recently Visited Services"。
  - 截图 #1 中，CloudWatch 卡显示 "2 In alarm" 为红色、"0 Insufficient data" 为绿色；AWS Health 卡显示 "1 Open issues"、"0 Scheduled changes"、"3 Other notifications"；账单卡显示本月至今费用 $1,234.56；最后是"最近访问"胶囊。
  - 底部 Tab：Home、Notifications、Services、Resources。
- **列表行解剖**：截图里没有完整的资源列表，不作结论。
- **筛选交互**：【证实，截图】
  - 导航栏有区域切换器 "N. Virginia ▾"，**环境切换放在导航层**。
  - 仪表盘有时间范围胶囊：1h、3h、12h、1d、1w、Custom，外加刷新图标。
  - 账单页有 Bills、Payments、Credits 横向按钮，Cost Explorer 有 Daily/Monthly 分段。
- **详情页结构**：【证实，截图 #2】Cost Summary 中，金额大字左对齐，右侧显示 "↓11% Over last month"，上方小字写明日期范围和 "(UTC) (Refunds excluded)" 口径。
- **批量与危险操作**：【证实】可以 "perform some actions"。第三方资料提到 EC2 的启动、停止、重启、终止，但官方指南没有描述确认方式，不作结论。
- **图表呈现**：【证实，截图 #3】每个图表卡的标题是指标名，**单位单独写在图上方**（Bytes、Percent），图例在下方。

### 2.6 GitHub Mobile（iOS 1.281.0，2026-10-15；截图已是 iOS 26 Liquid Glass 风格）

来源：
- App Store https://apps.apple.com/us/app/github/id1477376905 （截图 #1 到 #4）
- https://github.blog/changelog/2021-05-25-new-filtering-and-metadata-experience-on-github-mobile/
- https://github.blog/changelog/2026-07-10-github-mobile-improved-filters-and-sorting-for-copilot-sessions/
- 滑动设置讨论 https://github.com/orgs/community/discussions/18623
- 误触讨论 https://devactivity.com/insights/github-app-s-mobile-ux-addressing-accidental-swipes-for-better-developer-productivity/

- **首页组织**：【证实，截图 #1】
  - 大标题 "Home"，右上角是 + 和搜索两个玻璃圆按钮。
  - 下面依次是 "My Work"（Issues、Pull Requests、Discussions…，每项有彩色方形图标）、"Favorites"、"Shortcuts"，每个分区标题右侧都有 "…" 可以自定义。
  - Tab 栏有 4 个 Tab（Home、Inbox、Explore、Profile），**另有一个独立的圆形 Copilot 按钮**，形式与 iOS 26 的 search tab 或 iOS 27 的 prominent tab 相同。
- **列表行解剖**：【证实，截图 #2 Inbox】
  - 左侧是类型或状态图标（Issue 和 PR 的状态色），下方有未读蓝点。
  - 第 1 行是次要信息 "repo / repo #编号"，**右侧是相对时间 "17m / 3h"**。
  - 第 2 行是标题。
  - 第 3 行是头像加最近一条评论摘要，右侧是评论数小徽标。
- **筛选交互**：【证实，截图 #2】
  - 大标题下面是一排**可横滑的筛选胶囊**："Bandeja de entrada ▾"（收件箱下拉）、"Prioritarias Nuevo"、"Sin leer"、"Repos…"。
  - 左上角是"Seleccionar"（选择）。
  - 2026-07 的更新把"为移动端设计的轻量筛选"（Active、Status、Repository、Type、Agent、Sort）扩展到了 Copilot 会话。
  - 社区讨论确认移动端会**按仓库记住筛选和排序**。
- **详情页结构**：【证实，截图 #3、#4】
  - PR 详情：导航栏标题带副标题（仓库名），然后是 Merged 状态徽标和分支胶囊；正文过长时折叠，并提供 "Read more"；"Changes" 行右侧用红绿数字显示 +599 -274。
  - **悬浮操作**："Comment" 胶囊和 ⓘ 浮在 Tab 栏上方。
  - 在 Files Changed 页，Tab 栏最小化成单个图标，悬浮显示绿色 "Finish Review" 主操作。
- **批量与危险操作**：【证实】Inbox 支持选择模式，左右滑动的动作可以在设置里配置。社区反馈 Android 上滚动时容易误触 "Mark as done"，有人建议提高滑动阈值或提供关闭开关，这说明**全滑执行写操作有误触风险**。
- **图表呈现**：无。

### 2.7 Linear Mobile（iOS 1.104.0，2026-10-13）

来源：
- https://linear.app/mobile
- App Store https://apps.apple.com/us/app/linear-mobile/id1645587184 （截图 #1、#2，iOS 26 风格）

- **首页组织**：【证实】Inbox 优先："surfaces high-priority tasks and projects that need your attention"。
- **列表行解剖**：【证实，截图 #2】头像右下角叠加类型角标，标题前有未读蓝点，副标题是"谁做了什么"，右侧是相对时间（1h、1d、2d、1w）。
- **筛选交互**：【证实】Inbox 顶部有 "Priority 1 / Other" 两枚胶囊，带计数（截图）。项目详情有 Overview、Activity、Projects、Top Priority 胶囊分段。
- **详情页结构**：项目详情按状态分组（In Progress、Discovery、Idea），每行右侧是健康度小图标（绿、红、黄）。
- **批量与危险操作**：【证实】"Tap to take action, swipe to delete, snooze to deal with it later"；截图里有左滑出现的 "Unread" 操作。
- **导航**：【证实，截图】底部是**纯图标**玻璃 Tab 栏（4 个），右侧有独立的创建按钮。

### 2.8 App Store Connect（iOS 3.3，2026-09-23）

来源：
- App Store https://apps.apple.com/us/app/app-store-connect/id1234793120 （截图 #1、#2、#4）
- AppleInsider https://appleinsider.com/articles/26/03/25/developers-finally-get-more-app-store-data-from-apple

- **首页组织**：【证实，截图 #1】没有 Tab 栏，是单一的 "Apps" 列表。顶部有 "Trends" 入口，**底部是常驻的 iOS 26 搜索框**（"Search Apps"）。
- **列表行解剖**：【证实】App 图标、名称，下方每个平台一行，用**小的彩色符号加文字状态**表示（绿色对勾 "iOS 4.1"，黄色时钟 "iOS 3.2.1"）。收藏的项目右侧显示星标。
- **详情页结构**：【证实，截图 #4】
  - TestFlight 群组页顶部是大头像、名称和摘要（"External Group · 10 Builds · 24 Testers"），下面是两个等宽次级按钮（Add Build、Add Tester）。
  - 分区标题右侧是**计数加箭头**（"Builds 10 >"、"Testers 24 >"），分区里只预览前几条。
- **图表呈现**：【证实，二手】AppleInsider 截图描述 Trends 视图 "with selectable metrics in a bottom sheet"，即**用 sheet 选择图表指标**。

### 2.9 Tailscale（iOS 1.104.1，2026-10-08）

来源：
- 更新日志 https://tailscale.com/changelog
- App Store https://apps.apple.com/us/app/tailscale/id1470499037 （截图 #1）

- **首页组织**：【证实】顶部是 tailnet 切换器（"● Connected ▾" 加域名），接着是出口节点卡片（带开关），然后是搜索框（"Search machines"）和按所有者分组的设备列表。
- **列表行解剖**：【证实】左侧是**在线状态圆点**（绿色或灰色），然后是设备名、设备类型小图标，第二行是 IP（等宽风格）。
- **筛选**：【证实】可以按 tag 搜索设备（v1.66.0）。v1.104.1 支持在 iOS 上**置顶设备**。
- **iPad 适配**：【证实】v1.102.1 在 iPad 横竖屏以及足够宽的横屏 iPhone 上启用了"split-plane layout"。

### 2.10 阿里云 App（中文参照，iOS 7.12.0）

来源：App Store 中国区 https://apps.apple.com/cn/app/id981011420 （截图 #1、#2）

- **首页组织**：【证实，截图 #1】
  - 依次是搜索框、宫格工具入口、"待处理事件"横滑卡片："急需续费 28"（橙色，下有小字"其中 5 个实例 3 日内即将到期"）、"严重事件 7"、"正在报警 3"，右侧有"全部 >"。
  - 接着是"费用监控"，**标题旁有一个"眼睛"开关，金额被遮罩为 `***`**；单位写在标签里，例如"账户余额（元）"。
  - 然后是"最近使用"胶囊。
- **列表行解剖**：【证实，截图 #2】图标、名称，名称下方是红色小标签"1个即将过期"，右侧是数量和箭头。
- **筛选交互**：【证实】顶部是下拉胶囊"全部时间 ▾""手动续费 ▾"。

### 2.11 缺席者（同样是证据）

- **Sentry**：【证实】官方移动 App 仓库 `getsentry/sentry-mobile-release-health-app` 的定位是 "focus on Release Health"，README 写明 "currently not actively maintained"。见 https://github.com/getsentry/sentry-mobile-release-health-app 。
- **Vercel**：【证实】官方社区回复 "We don't have an official iOS widget or app"。见 https://community.vercel.com/t/deployments-on-the-ios-homescreen-as-a-widget/4897 。第三方开源的 "Rev for Vercel" 填补了这个空缺，见 https://apps.apple.com/us/app/rev-for-vercel/id6740740427 。
- **Cloudflare**：【证实】检索结果中只有第三方 App，例如 "Dashboard for Cloudflare"（https://apps.apple.com/us/app/dashboard-for-cloudflare/id6766168875 ）。该 App 的商店描述写着 "No official mobile app from Cloudflare?"。
- **Railway、OpenAI/Anthropic 控制台**：本次未检索，不作结论。

【推断】开发者平台的移动端普遍只做"监控 + 少量快速操作"，复杂配置留给 Web。Datadog 文档明确写道 "To set up or edit monitors ... you must use the Datadog web app"。Sub2 也应该明确把"复杂配置交给 Web 后台"作为一项设计约束，而不是在移动端复刻完整表单。

### 2.12 横向对比

| 维度 | 主流做法（≥3 个产品采用） | 代表 | Sub2 现状（证据） |
|---|---|---|---|
| 首页第一屏 | "需要处理"的计数，按状态着色，可点击进入 | AWS、Grafana、PagerDuty、阿里云、Datadog | 第一屏是指标卡和趋势图，告警/异常不在首屏（S5、S6；`DashboardView.swift:301-318`） |
| 列表行 | 状态符号或徽标 + 标题 + 1 行元数据 + 右侧相对时间或金额 | Stripe、Datadog、GitHub、Linear、Tailscale、ASC | "字段：值"平铺 3 到 6 行（S1、S3；`AccountsView.swift:197-204`） |
| 范围切换 | 我的/全部、优先/其他（2 到 3 段） | PagerDuty、Grafana、Linear、GitHub | 没有"需要处理"视角 |
| 筛选 | 横向下拉胶囊，或带激活指示的筛选按钮 | Stripe、GitHub、阿里云、Grafana | 筛选放在列表首行或 Form sheet 里，需要输入数字 ID（`RequestLogsView.swift:212-218`） |
| 搜索 | 全局搜索带 scope，结果分组并提供"查看全部" | Stripe、Datadog（查询语法与最近搜索）、ASC（底部搜索） | 只有列表内的 `.searchable`（账号、用户、分组） |
| 详情页 | 头部摘要（状态、相对时间）+ 主操作行 + 分段（概览/时间线）+ 键值 + 跳转胶囊 | Datadog、PagerDuty、GitHub、Stripe | 逐字段一行的设置样式列表（S2；`RequestLogsView.swift:265-294`） |
| 主操作 | 底部操作条或头部 2 到 3 个等宽按钮，1 个主按钮 | Stripe、PagerDuty、Datadog、Grafana、ASC | "管理操作"作为一个 Section 里的按钮行（`AccountsView.swift:477`、`UsersView.swift:168`） |
| 批量 | 选择模式 + 底部操作条 + More | Grafana、GitHub | 选择控件放在列表首个 Section 里，用菜单执行批量（S3；`AccountsView.swift:73-88`） |
| 可逆操作 | 不确认，可以恢复或撤销 | Stripe（停用链接）、Linear（snooze） | 暂停调度也走 destructive 确认（`AccountsView.swift:155`） |
| 环境切换 | 导航层的区域、组织或站点切换器 | AWS、Grafana、Tailscale | 站点切换在"设置"Tab 里（`SettingsView.swift:12-35`） |
| 图表 | 时间范围胶囊 + 对比期 + 单位写进标题，交互可选 | Stripe、AWS、Datadog | 有操作说明文字和多个刷新按钮（S5、S6） |

---

## 3. 模式库（24 条）

> 每条依次写明：解决什么问题、出处、Sub2 适用页面（带代码位置）、SwiftUI 实现与最低版本、iOS 17 下怎么降级。没有标注的 API 版本都已按第 0.2 节的方法核实。"未来用户端"表示这条模式也适用于以后的普通用户端。

### P1 待处理优先的首页
- **问题**：管理员打开 App 最想知道的是"有没有坏掉的东西"。现在首页先放营收和用量（S5、S6），异常要去各个 Tab 里翻。
- **出处**：AWS（In alarm 计数）、Grafana（Firing/Ack/Silenced）、PagerDuty（My Open Incidents）、阿里云（待处理事件）。
- **Sub2 适用**：概览（`DashboardView.swift`）。顶部放 3 到 4 个"需要处理"计数：异常或限流账号、近 1 小时失败请求、上游错误未处理数、配额将尽的账号或分组。计数为 0 时折叠成一行"全部正常 · 3 分钟前检查"。
- **实现**：
  - `LazyVGrid` 或 `Grid`（iOS 16）放计数卡。
  - 点击后用 `TabView(selection:)` 切换 Tab，同时把预置筛选写进共享状态。
  - 用 `NavigationStack(path:)` 和 `.navigationDestination(for:)`（iOS 16）定位到列表。
  - 计数变化用 `.contentTransition(.numericText(value:))`（iOS 17）。
- **降级**：无，iOS 17 全部可用。
- **未来用户端**：首页改为"余额、今日用量、即将到期的订阅、异常 Key"。

### P2 KPI 条 + 时间范围胶囊 + 对比期
- **问题**：多个指标卡等高等宽地平铺，看不出主次；时间范围藏在设置里。
- **出处**：Stripe（Today 指标条，1W/4W/1Y/MTD）、AWS（1h/3h/12h/1d/1w/Custom，以及 "↓11% Over last month"）。
- **Sub2 适用**：概览的今日请求、Tokens、扣费、成本；统计分析（`AnalyticsView.swift:40-57`）。
- **实现**：
  - 时间范围不超过 5 段时用 `Picker(...).pickerStyle(.segmented)`；更多选项用 `Menu { Picker }` 收起。
  - 主值使用 `.font(.title2.weight(.semibold)).monospacedDigit()`（iOS 15）。
  - 对比值用 `Text` 加箭头符号；**颜色不作为唯一信号**。
- **降级**：无。

### P3 分区预览 + "查看全部（N）"
- **问题**：详情页把所有子列表展开，页面无限变长。
- **出处**：ASC（"Builds 10 >"）、PagerDuty（"View All Open Incidents"）、Stripe 搜索结果（"View all"）。
- **Sub2 适用**：
  - 用户详情的 API Key（`UsersView.swift:155`）。
  - 账号详情的"记录与分析"（`AccountsView.swift:483`）。
  - 分组详情的"账号与容量"（`GroupsView.swift:181`）。
- **实现**：`Section { 前 3 条 } header: { HStack { Text("API Key"); Spacer(); NavigationLink("\(n)") {...} } }`，iOS 15+。
- **降级**：无。**未来用户端**：Key 列表、最近用量。

### P4 状态先行的紧凑列表行
- **问题**：账号和日志的行写成"字段：值"流式文本，一行占 3 到 6 行文字，无法扫读（S1、S3）。
- **出处**：Stripe Payments 行、Datadog Incidents、GitHub Inbox、Linear Inbox、Tailscale、ASC。
- **Sub2 适用**：
  - 账号行（`AccountsView.swift:197-204`）。
  - 请求行和错误行（`RequestLogsView.swift:116-136`）。
  - 用户行（`UsersView.swift:28`）。
  - 分组行（S4）。
- **建议解剖**：
  - **左**：状态符号，用形状加颜色表达（SF Symbols，例如 `checkmark.circle.fill`、`exclamationmark.triangle.fill`、`pause.circle.fill`）。
  - **主行**：名称，或"模型 + HTTP 码"；**右上**是相对时间或关键数值（等宽）。
  - **次行**：最多 2 到 3 个元数据，用 " · " 分隔，例如"OpenAI · 标准分组 · 并发 2/4"。
  - **可选第三行**：容量条（P19）或错误摘要（`.lineLimit(1)`）。
  - 其余字段一律进入详情页。
- **实现**：
  - `HStack(alignment: .firstTextBaseline)`。
  - `Image(systemName:).symbolRenderingMode(.hierarchical)`（iOS 15）。
  - `.monospacedDigit()`（iOS 15）。
  - `.lineLimit(1)` 加 `.truncationMode(.middle)`（用于 ID）。
  - `.alignmentGuide(.listRowSeparatorLeading)`（iOS 16）让分隔线对齐文字。
  - `.listRowInsets` 或 `.listSectionSpacing(.compact)`（iOS 17）控制密度。
- **降级**：无。
- **注意**：现有的"自定义显示字段"（`ListFieldEditor`）可以保留，但应改为"选择次行显示哪 2 到 3 项"，而不是可以无限叠加。

### P5 状态徽标
- **问题**：状态只靠文字颜色区分（"调度：参与调度"为绿色），色盲用户和中文语境都容易误读。
- **出处**：Datadog（ACTIVE/RESOLVED、TRIGGERED）、Grafana（Firing/Acknowledged）、PagerDuty（SEV-1）、GitHub（Merged）。
- **Sub2 适用**：账号状态（正常、异常、限流、已暂停调度）、错误的 HTTP 码与处理状态、分组启用状态、用户禁用状态。
- **实现**：
  - `Text("限流").font(.caption.weight(.semibold)).padding(.horizontal, 6).background(.orange.opacity(0.15), in: .capsule).foregroundStyle(.orange)`（iOS 15）。
  - **不要用玻璃**（内容层）。
  - 同一种语义固定一种颜色，并在文档里写成"状态色表"：
    - 红色：失败或不可用。
    - 橙色：限流或降级。
    - 灰色：暂停或禁用。
    - 系统强调色：进行中。
- **降级**：无。

### P6 横向筛选胶囊条 + 激活指示
- **问题**：筛选器藏在列表首行（`AccountsView.swift:69-71`）或内容 Section 里（`GroupsView.swift:69-77`，S4），既占首屏，也看不出当前生效了哪些条件。
- **出处**：GitHub Inbox 胶囊、Stripe "Status""Created" 下拉胶囊、阿里云"全部时间 ▾"、Grafana 筛选按钮蓝点。
- **Sub2 适用**：账号（平台、状态、分组、类型）、日志（时间、模型、状态码）、用户（角色、状态）、分组（平台、状态）。
- **实现**：
  - `ScrollView(.horizontal) { HStack { Menu { Picker(...) } label: { chipLabel } } }`。`Menu` 是 iOS 14，`Picker` 放在 `Menu` 里作为单选子菜单。
  - 胶囊外观用 `.buttonStyle(.bordered)` 加 `.buttonBorderShape(.capsule)`（iOS 15），激活态用 `.tint`。
  - 胶囊条放在 `.safeAreaInset(edge: .top)`（iOS 15）里；iOS 26 上用 `.safeAreaBar(edge: .top)`，这样能参与 scroll edge effect。
  - toolbar 的筛选按钮可以加 `.badge(activeCount)`（iOS 26 在 toolbar 中渲染徽标，见 WWDC25-323）。
- **降级**：iOS 17 和 18 使用 `safeAreaInset`，toolbar 按钮的徽标改为"图标 + 数字"文字。

### P7 搜索 + Token + Scope（替代"输入数字 ID"）
- **问题**：日志筛选要求输入"用户 ID、账号 ID、分组 ID、API Key ID"（`RequestLogsView.swift:212-218`），管理员记不住 ID。
- **出处**：HIG Search fields（tokens 应与 suggestions 搭配）、Stripe 全局搜索的 scope、Datadog 的查询语法加最近搜索。
- **Sub2 适用**：日志筛选，以及跨实体搜索（P8）。
- **实现**：
  - `.searchable(text:tokens:placement:prompt:token:)`（iOS 16）。Token 示例："账号：上游 A""模型：gpt-4.1""状态：5xx"。
  - `.searchSuggestions { ... }`（iOS 16）：输入时提示匹配的账号、用户、模型，选中后转成 token。
  - `.searchScopes($scope, activation: .onSearchPresentation) { 全部 / 用户 / 账号 / 请求 }`（iOS 16.4）。
  - 没有结果时显示 `ContentUnavailableView.search(text:)`（iOS 17）。
- **降级**：无。从账号或用户详情跳到日志时，自动带上 token（替代当前的 `RequestLogsView(accountID:)` 初始化参数，见 `RequestLogsView.swift:23-25`）。

### P8 搜索放置：Search Tab（跨实体）+ 列表内搜索
- **问题**：要找一个邮箱、请求 ID 或账号名，必须先猜对它在哪个 Tab。
- **出处**：HIG（iOS 上搜索可以作为 Tab）；ASC 底部常驻搜索；GitHub、Linear 的独立圆形入口。
- **Sub2 适用**：主导航。列表内的 `.searchable` 继续保留。
- **实现**：
  - `Tab(role: .search) { NavigationStack { GlobalSearchView() } }`（iOS 18）。
  - 在 TabView 上加 `.tabViewSearchActivation(.searchTabSelection)`（iOS 26）。根据前述第三方证据，iOS 27.2 必须加这个修饰符才能保持按钮外观。
  - 列表内可加 `.searchToolbarBehavior(.minimize)`（iOS 26），减少底部占用。
- **降级**：iOS 17 上作为普通 `.tabItem` 的"搜索"Tab，内部用 `.searchable(placement: .navigationBarDrawer(displayMode: .always))`（iOS 15）。

### P9 已保存视图与记住上次筛选
- **问题**：常用组合（例如"上游错误 · 近 1 小时 · 未处理"）每次都要重新设置。
- **出处**：Datadog saved views 和最近 10 次搜索；PagerDuty "remember which tab filter you most recently selected"；GitHub 按仓库记住筛选，并支持最多 15 个自定义筛选。
- **Sub2 适用**：日志、账号。可以复用现有"按站点身份隔离的字段偏好"（`AccountsView.swift:163-171`）的存储方式。
- **实现**：`@AppStorage`（iOS 14），键名包含站点 profile ID；预设放在胶囊条最左边的 `Menu("视图")` 里。
- **降级**：无。

### P10 "需要处理 / 全部"范围切换
- **问题**：列表默认显示全量，异常淹没在正常项里。
- **出处**：PagerDuty Mine/My Teams/All、Grafana Mine/All、Linear Priority/Other。
- **Sub2 适用**：账号（需要处理 / 全部）、错误日志（未处理 / 全部）。
- **实现**：列表顶部用 2 段 `Picker(.segmented)`，放在 `safeAreaInset(edge: .top)` 里，并在段标题里带上计数，例如"需要处理 3"。
- **降级**：无。

### P11 详情页骨架：摘要头 → 主操作 → 分段 → 键值 → 跳转胶囊
- **问题**：请求和账号的详情是"一个字段一行"的设置样式（S2），首屏只能看到时间、模型、类型、ID，最关键的"成功还是失败、花了多少钱"要往下翻。
- **出处**：Datadog Page 详情、PagerDuty Incident、GitHub PR、Stripe 详情、ASC TestFlight 群组。
- **Sub2 适用**：
  - 账号详情（`AccountsView.swift:419-493`）。
  - 请求详情（`RequestLogsView.swift:265-294`）。
  - 错误详情（`RequestLogsView.swift:317-347`）。
  - 用户详情（`UsersView.swift:135-191`）。
  - 分组详情（`GroupsView.swift:162-222`）。
- **建议结构**：
  1. 摘要头：状态徽标、HTTP 码、相对时间，大字写模型或账号名，一行写"扣费 $0.35 · 成本 $0.12 · 1.2M Token · 1.25s"。
  2. 主操作：2 到 3 个按钮，只有 1 个是主按钮。
  3. 有时间维度的对象（账号、错误）提供"概览 / 记录"分段。
  4. 键值区用两列 `Grid`，长 ID 用中间截断并支持长按复制。
  5. 跳转胶囊："查看该账号的错误""查看该用户的请求"。
- **实现**：
  - 摘要头放在 `List` 的第一个 Section，配合 `.listRowBackground(Color.clear)`。
  - `Grid` 和 `LabeledContent`（iOS 16）。
  - `.textSelection(.enabled)`（iOS 15）。
  - `ShareLink`（iOS 16）。
  - `ControlGroup`（iOS 15）放并列操作。
  - iOS 26 用 `.navigationSubtitle(_:)` 显示站点名。
- **降级**：`navigationSubtitle` 在 iOS 17/18 上改用 `ToolbarItem(placement: .principal)` 放一个两行标题。

### P12 底部操作条
- **问题**：写操作散落在详情页中部的"管理操作"Section 里（`AccountsView.swift:477`、`UsersView.swift:168`、`GroupsView.swift:198`），离拇指远，也不醒目。
- **出处**：Stripe（Refund / Copy link + "…"）、PagerDuty（Ack/Resolve/All Actions）、Grafana 批量底部条。
- **Sub2 适用**：账号详情（暂停/启用调度、测试、更多：刷新凭据、编辑）、用户详情（调整余额、更多：禁用、编辑）、选择模式（P14）。
- **实现**：
  - iOS 17 起用 `.safeAreaInset(edge: .bottom) { ActionBar() }`（iOS 15）。
  - iOS 26 改用 `.safeAreaBar(edge: .bottom)`，以获得 scroll edge effect。
  - 主按钮用 `.borderedProminent`（iOS 26 可用 `.glassProminent`）。
  - 需要隐藏 Tab 栏时，用 `.toolbarVisibility(.hidden, for: .tabBar)`（iOS 18）；iOS 17 用 `.toolbar(.hidden, for: .tabBar)`（iOS 16，iOS 27.2 起弃用并改名）。
- **降级**：见上。**未来用户端**：充值、复制 Key。

### P13 行内快捷操作：滑动与上下文菜单一致
- **问题**：账号行的滑动和上下文菜单里只有"快捷编辑"（`AccountsView.swift:102-105`），最常用的"暂停/恢复调度"要进详情才能做。
- **出处**：PagerDuty 随状态变化的滑动（Ack、Snooze、Resolve）、Linear 滑动标记未读、GitHub 可配置滑动；Apple "Match top menu actions to swipe actions"。
- **Sub2 适用**：
  - 账号：右滑"暂停/恢复调度"，左滑"更多"。
  - 错误日志：滑动"标记已处理"。
  - 用户：滑动"调整余额…"。
- **实现**：
  - `.swipeActions(edge:allowsFullSwipe: false)`（iOS 15，只能用于 List）。写操作**关闭全滑**，因为 GitHub 有误触反馈。
  - `.contextMenu(menuItems:preview:)`（iOS 16），菜单前几项与滑动操作一致。
  - iOS 27 可以用 `.swipeActionsContainer()` 把滑动扩展到 `LazyVStack`。
- **降级**：iOS 17 只在 `List` 中使用滑动。

### P14 多选批量 + 结果回执
- **问题**：选择控件、"选择已加载账号"、"已选 2/50"和批量菜单都放在列表的第一个 Section 里（S3，`AccountsView.swift:73-88`），选择模式和浏览模式混在一起。
- **出处**：Grafana（选择图标进入多选，底部 Acknowledge、Resolve、More）、GitHub "Select"；HIG Context menus（多选时标题说明数量）。
- **Sub2 适用**：账号批量暂停、恢复、刷新凭据；未来的用户批量操作。
- **实现**：
  - `List(selection: $selected)` 加 `.environment(\.editMode, $mode)`（`EditMode` 是 iOS 13）。
  - 底部 `safeAreaInset` 操作条，标题写"已选 N 个"。
  - 多选后的上下文菜单用 `.contextMenu(forSelectionType:menu:primaryAction:)`（iOS 16）。
  - 结果回执用 `.sheet` 加 `.presentationDetents([.medium, .large])`（iOS 16）。
  - 成功或失败的触感反馈用 `.sensoryFeedback(.success, trigger:)`（iOS 17）。
- **降级**：无。

### P15 分级确认（可逆不打扰，不可逆才拦截）
- **问题**：
  - 现在几乎所有写操作都会弹 confirmationDialog。
  - "暂停调度"这种可逆操作使用了 `role: .destructive`，确认按钮叫"确认执行"（`AccountsView.swift:154-162`），与 HIG 的 "Avoid displaying alerts for common, undoable actions" 以及"按钮标题描述结果"相悖。
  - 批量确认的 message 里列出了全部账号名（`AccountsView.swift:160`），可能导致 action sheet 需要滚动，而 HIG 要求 "Avoid letting an action sheet scroll"。
- **出处**：HIG Alerts 与 Action sheets；Stripe（停用链接不确认，可以恢复；取消订阅给出"立即 / 周期末"选项）；Grafana（Resolve 时要求填写处理说明）。
- **建议分级**：
  1. **可逆、单个对象**（暂停或恢复调度、标记已处理）：直接执行，底部出现"已暂停 · 撤销"提示 3 到 5 秒，同时给触感反馈。
  2. **可逆、批量**：confirmationDialog 标题写"暂停 5 个账号的调度？"，按钮写"暂停 5 个账号"，**不使用 destructive**，账号名单放进结果回执。
  3. **不可逆或影响资金**（调整余额、删除站点、刷新凭据导致旧凭据失效）：confirmationDialog 或 alert，使用 destructive，并写明金额或影响。
  4. **高风险**：沿用现有的二次验证（`StepUpView`，`Components.swift:51-79`）。
- **实现**：
  - `.confirmationDialog(_:isPresented:titleVisibility:actions:message:)`（iOS 15/16）。**把修饰符挂在触发按钮上**，这样 iOS 26 会从按钮处弹出。
  - iOS 27 可用 `confirmationDialog(_:item:)`。
  - 撤销提示用 `.safeAreaInset(edge: .bottom)` 加 `.transition`。
- **降级**：无。

### P16 Sheet 承载筛选和编辑（detent 渐进展开）
- **问题**：筛选 sheet 和编辑 sheet 都是全屏 Form（`RequestLogsView.swift:199-246`、`AnalyticsView.swift:192-198`），改一个条件也要进入全屏。
- **出处**：HIG（iPhone 上的 medium detent）；Datadog Monitor 群组 sheet；ASC Trends 用 sheet 选择指标。
- **Sub2 适用**：日志和分析的筛选、账号快捷编辑（`AccountsView.swift:144`）、批量结果（`AccountsView.swift:150`）。
- **实现**：
  - `.presentationDetents([.medium, .large])` 和 `.presentationDragIndicator(.visible)`（iOS 16）。
  - 需要边看列表边调整时，用 `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`（iOS 16.4）。
  - 有未保存修改时用 `.interactiveDismissDisabled(isDirty)`（iOS 15）。
  - iOS 26 上**不要设置 `presentationBackground`**。
- **降级**：无。

### P17 时间范围控件 + 新鲜度
- **问题**：日志顶部用 3 到 4 行文字描述时间范围和刷新语义（"固定时间范围；下拉刷新保留以上起止时间。"，`RequestLogsView.swift:34-47`，S1）；概览每个区块各有一个"刷新"按钮和"更新于 HH:mm:ss"（S5）。
- **出处**：AWS 时间胶囊加刷新图标、Datadog 右下角时间范围、Stripe 时间胶囊。
- **Sub2 适用**：日志、概览、统计分析。
- **实现**：
  - 一个时间胶囊："近 24 小时 ▾"，菜单里放预设和"自定义…"（自定义打开 DatePicker sheet）。
  - 整页统一"下拉刷新"（`.refreshable`，iOS 15），去掉分区的刷新按钮。
  - 新鲜度放在导航副标题或底部小字，例如"3 分钟前更新"。iOS 18 用 `Text(.currentDate, format: .reference(to: updatedAt))`，会自动刷新；iOS 17 用 `TimelineView(.periodic(from: .now, by: 60))` 包住 `Text(updatedAt, format: .relative(presentation: .named))`（`Date.RelativeFormatStyle` 是 iOS 15）。
- **降级**：见上。

### P18 结论先行的图表卡
- **问题**：图表靠操作说明和点选才能读到数值（S5）。柱子用紫粉渐变，数据标签字体与正文不一致（S5 上的 `$0.31` 是等宽字体）。
- **出处**：HIG Charts（总结主信息、单位写进标题、交互可选、扩大点击区域）；Stripe（当前值 + 对比 + 双线）；Datadog（阈值区背景带）；AWS（单位标在图上方）。
- **Sub2 适用**：概览趋势、性能趋势（`PerformanceTrendView.swift`）、统计分析。
- **实现**：
  - 标题区写结论，例如"今日扣费 $12.40，比昨天 +8%"，单位写进标题。
  - 图表本身：`Chart`（iOS 16），单色系统强调色，柱状图以 0 为下界。
  - `chartXSelection(value:)`（iOS 17）让整个绘图区都可以选择。
  - `chartScrollableAxes(.horizontal)` 和 `chartXVisibleDomain(length:)`（iOS 17）替代自定义的双指缩放。
  - 阈值用 `RuleMark` 或 `RectangleMark`。
  - 无障碍用 `accessibilityChartDescriptor`（iOS 15）。
  - 列表行里的迷你趋势用隐藏坐标轴的 `Chart`（`.chartXAxis(.hidden)`）。
- **降级**：无。

### P19 容量与配额条
- **问题**：当前的容量信息是"并发 2 / 4 · 探测并发 1 · 调度 RPM 不可用 / 60（自然分钟）· 日配额 $3.45 / $20.00 · 周配额 …"这样一长串文字（S3），无法一眼判断哪个快满了。
- **出处**：HIG Gauges（capacity style）；macOS level indicator（到阈值时变色）；阿里云"即将过期"红色小标签。
- **Sub2 适用**：账号行的第三行（只显示最紧张的一项）、账号详情的"容量与实时占用"（`AccountsView.swift:427`）、分组容量。**未来用户端**：订阅额度和余额。
- **实现**：
  - `Gauge(value:in:) { label } currentValueLabel: { Text("2/4") }.gaugeStyle(.accessoryLinearCapacity)`（iOS 16）。
  - 或者用 `ProgressView(value:total:)`（iOS 14）。
  - 超过 80% 时 `.tint(.orange)`，到 100% 时 `.tint(.red)`，**同时附带文字**。
- **降级**：无。

### P20 站点切换器放在导航层
- **问题**：多站点切换藏在"设置"Tab（`SettingsView.swift:12-35`）。管理员不确定"我现在在哪个站点"，这在写操作前尤其危险。当前代码只能在每个确认文案里重复写"站点：…"来补救（`AccountsView.swift:160`）。
- **出处**：AWS "N. Virginia ▾"、Grafana 点头像切换 stack、Tailscale tailnet 切换器。
- **Sub2 适用**：各 Tab 的根视图。
- **实现**：
  - `.toolbarTitleMenu { ForEach(profiles) { Button(...) } }`（iOS 16），点击导航标题即可切换站点。
  - 也可以用 `ToolbarItem(placement: .topBarLeading) { Menu {...} label: { 站点头像 } }`。
  - iOS 26 用 `navigationSubtitle` 常驻显示站点名。
- **降级**：`navigationSubtitle` 的降级见 P11。

### P21 统一的空态、错误态和部分失败
- **问题**：
  - 已有 `FailureView`（基于 `ContentUnavailableView`，`Components.swift:6-16`），但列表里大量使用行内红字加"重试"按钮（`AccountsView.swift:107-113`、`RequestLogsView.swift:71-82`）。
  - 空态是灰色文字行，例如"没有符合条件的账号"。
- **出处**：HIG Alerts（"prefer finding an alternative way to communicate it within the relevant context"）；Grafana 的 "All looks great!"；SwiftUI 文档推荐在网络错误、空列表、无搜索结果时使用 `ContentUnavailableView`。
- **实现**：
  - 整页失败或为空：`.overlay { if items.isEmpty { ContentUnavailableView(...) } }`（iOS 17）。
  - 部分失败（例如"今日统计"加载失败，见 `AccountsView.swift:115-122`）：在对应区块内用一行 `Label("今日统计暂不可用", systemImage: "exclamationmark.triangle")` 加"重试"。
  - 首次加载用 `.redacted(reason: .placeholder)`（iOS 14）显示骨架，而不是放一行 ProgressView。
- **降级**：无。

### P22 敏感数值遮罩
- **问题**：管理员可能在公共场合打开 App，余额、扣费、Key 会被旁人看到。
- **出处**：阿里云"费用监控"的眼睛开关（`***`）。
- **Sub2 适用**：概览金额、用户余额；**未来用户端** API Key。
- **实现**：
  - `.privacySensitive()`（iOS 15）：在锁屏和小组件等场景自动遮罩。
  - 再加一个可切换的 `@AppStorage("maskAmounts")`，开启时金额显示为 `$•••`。
- **降级**：无。

### P23 iPad：侧栏与分栏
- **问题**：工程已声明支持 iPad（`TARGETED_DEVICE_FAMILY=1,2`），但根视图只有 `TabView`（`Sub2MobileApp.swift:36-43`），iPad 上是被放大的 iPhone 布局。
- **出处**：HIG Tab bars（iPadOS 可转换为侧栏）；Tailscale v1.102.1 的 split-plane 布局；Apple "Use NavigationSplitView ... for sidebar and inspector layouts"。
- **实现**：
  - `.tabViewStyle(.sidebarAdaptable)` 加 `TabSection`（iOS 18）。
  - 列表和详情页在 regular 宽度下用 `NavigationSplitView`（iOS 16）。
  - 日志详情用 `.inspector(isPresented:)`（iOS 17）。
- **降级**：iOS 17 上用 `horizontalSizeClass == .regular` 判断，切换到 `NavigationSplitView`。

### P24 底部附件和首页之外的触达（谨慎使用，后续再做）
- **问题**：长任务（批量执行、账号测试流式输出）没有全局可见的状态；关键告警只有打开 App 才能看到。
- **出处**：
  - HIG Tab bars（附件适用于 MiniPlayer 这类常驻功能）。
  - WWDC25-356："Keep screen-specific actions out of the tab bar"。
  - Datadog、Stripe 的锁屏和主屏小组件；Grafana 的推送操作（Acknowledge、Silence 30 分钟）。
- **Sub2 适用**：
  - `.tabViewBottomAccessory(isEnabled:content:)`（iOS 26.1）只用于"批量任务进行中 3/10"这类**跨页面的进行中状态**，完成后隐藏。
  - 小组件（WidgetKit，iOS 14；交互式小组件 iOS 17）显示今日扣费和异常账号数。
  - 推送需要服务端支持。【推断】当前的 Sub2API 后端可能没有这项能力，需要确认。
- **降级**：iOS 17/18 上用根视图的 `safeAreaInset(edge: .bottom)`，或者不显示。**不要**为没有附件的页面开启 `.tabBarMinimizeBehavior`。

---

## 4. 反模式（高密度数据工具中应避免）

| # | 反模式 | 依据 | Sub2 中的证据 |
|---|---|---|---|
| A1 | 在内容卡片、指标卡、列表行上使用 Liquid Glass（`.glassEffect`） | HIG Materials："Don't use Liquid Glass in the content layer"；NN/g："anything placed on top of something else becomes harder to see" | 目前没有发现，内容卡片使用的是 `secondarySystemGroupedBackground`（`Components.swift:46`）。重构时要防止引入 |
| A2 | 玻璃按钮或着色按钮泛滥，同一屏有多个"主按钮" | HIG Color："Refrain from adding color to the background of multiple controls"；Toolbars："Specify only one primary action" | S5 中"逐小时明细"（着色胶囊）、"刷新趋势"、"刷新监控"同屏，多个强调色控件并存 |
| A3 | 给 toolbar 或 sheet 加自定义背景，导致系统 scroll edge effect 失效 | *Adopting Liquid Glass*："Reduce your use of custom backgrounds"；WWDC25-323："consider removing [presentationBackground]" | 未发现。重构时防止引入 |
| A4 | 用 `Form` 或 inset grouped 列表承载只读的高密度数据（详情页"一个字段一行"） | SwiftUI `Form` 文档："A container for grouping controls used for data entry"；iOS 26 列表行高与内边距增大（*Adopting Liquid Glass*） | 请求详情（S2，`RequestLogsView.swift:265-294`）；`AccountTestView` 用 Form 展示结果和流式输出（`AccountsView.swift:602-612`） |
| A5 | 把控件、状态说明、帮助文字塞进内容列表（"列表里的设置面板"） | HIG Toolbars：作用于视图的操作放在 toolbar；Alerts："prefer ... communicate it within the relevant context"；HIG Charts："don't require interaction" | 账号列表首个 Section 是"筛选与排序"、"前台自动刷新"开关和选择控件（`AccountsView.swift:68-89`）；日志页首个 Section 有 4 到 6 行元信息，末尾 Section 是说明脚注（`RequestLogsView.swift:30-57, 84-87`）；概览图下有操作说明（S5） |
| A6 | 一屏多个 Section 标题，每块都要标题 | 【推断】HIG Toolbars 和 Context menus 都要求分组不超过约 3 个；Datadog、Stripe 的详情页使用"摘要头 + 少量分区" | 请求详情有"请求、扣费与成本、Token 与延迟、关联对象"4 个标题（`RequestLogsView.swift:269-294`）；账号详情有 5 个（`AccountsView.swift:419-483`） |
| A7 | 列表行写成"字段：值"流式文本，行高不可控 | HIG Lists："Keep item text succinct ... list only titles and let people open a detail view" | S3 账号行有 6 行文字（`AccountsView.swift:200-204`） |
| A8 | 只靠颜色表达语义，或同一种颜色表达多种含义 | HIG Color 与 Accessibility；HIG 的"中文环境中涨为红色"示例 | 扣费为绿色、成本为橙色（`RequestLogsView.swift:122-123`）；"调度：参与调度"为绿色（`AccountsView.swift:203`）；HTTP 码为红色（`RequestLogsView.swift:131`）。只有最后一处语义合理 |
| A9 | 列表行使用"年月日 时:分:秒"这类冗长的绝对时间 | Datadog 用"短日期 + (4d)"，GitHub、Linear 用"17m/1d"；HIG Charts 也提醒避免歧义格式 | S1、S2 中的"2026年10月16日 16:12:00"，以及日志时间范围的长日期（`RequestLogsView.swift:34`） |
| A10 | sheet 套 sheet | HIG Sheets："Display only one sheet at a time" | `AccountTestView`（sheet）里再弹 `StepUpView`（`AccountsView.swift:616`）；`UserEditorView`（sheet）里再弹 StepUp（`UsersView.swift:356`）；`BalanceView` 同理（`UsersView.swift:494`） |
| A11 | 可逆操作使用 destructive 确认，确认按钮写"确认执行"或"确定" | HIG Alerts："Avoid displaying alerts for common, undoable actions"；按钮应描述结果，避免 OK | `AccountsView.swift:155`（批量暂停也是 destructive） |
| A12 | 让管理员手动输入内部数字 ID 来筛选 | HIG Search："People may not know which tokens are available"，应搭配建议 | `RequestLogsView.swift:212-218, 223` |
| A13 | 固定高度卡片配合 `minimumScaleFactor`，在 Dynamic Type 下数字被缩小 | HIG Typography："Maintain a consistent information hierarchy regardless of the current font size" | `MetricView` 使用 `.minimumScaleFactor(0.6)` 和固定 `contentHeight`（`Components.swift:40-44`）。不过概览网格已经按 `isAccessibilitySize` 调整列宽（`DashboardView.swift:304`），这一点是正面做法 |
| A14 | 为了"现代感"开启 Tab 栏最小化或导航栏最小化，让控件位置漂移 | HIG：最小化行为针对带附件的 Tab 栏；NN/g："changing the size and location of a target makes the interface harder to learn" | 未开启。重构时如无附件，不要开启 |
| A15 | 把核心操作藏进溢出菜单，或藏在只有上下文菜单才有的入口 | NN/g：溢出菜单只放 "nonessential actions"；HIG Context menus："Always make context menu items available in the main interface, too" | "快捷编辑"同时在滑动和上下文菜单中（`AccountsView.swift:102-105`），但列表上没有可见入口。可以接受，但要确保详情页也有该入口 |
| A16 | 用 alert 承载通用错误 | HIG Alerts："Avoid using an alert merely to provide information" | 根视图的全局 alert"操作未完成"（`Sub2MobileApp.swift:28-30`）。【推断】如果它被用于非阻断错误，应改为行内提示或横幅 |

---

## 5. 中文排版与数字

### 5.1 现状（证据）

- 【证实】Token 与大数：`DashboardPresentation.compactNumber` 固定输出两位小数的 K/M/B，例如 `1.20M`（`Sources/Sub2Core/DashboardPresentation.swift:13-33`；S1 中的"1.20M Token"）。注释说明这样做是为了与管理员 Web 后台一致（第 3-4、43 行）。
- 【证实】金额：`money()` 固定输出"$ + 两位小数"，**没有千分位**，实现上用 `NSDecimalNumber.stringValue` 拼接（第 53-56、89-98 行）。`cost()` 对小额保留 3 到 4 位小数（第 35-40 行）。此外，`NativeApp/Views/Components.swift:4` 还有一个同名的 `money(_:)`，直接用 `stringValue`，不固定小数位，**存在两套金额格式**。
- 【证实】时间：图表坐标轴用 `en_US_POSIX` 的 `M/d HH:mm`（第 77-87 行）；日志使用 `formatted(date: .abbreviated, time: .shortened)` 和自定义的 `RequestLogPresentation.date`（`RequestLogsView.swift:34, 119`）。
- 【证实】等宽数字：概览和性能页部分使用了 `.monospacedDigit()`（`DashboardView.swift:137, 168, 251, 476`；`PerformanceTrendView.swift:38, 81`），列表行和详情页没有使用。

### 5.2 区域格式实测（ICU 78.3 / CLDR 48，Node 运行时；Apple Foundation 同样基于 ICU/CLDR，结果应一致，但需要在设备上复核）

| 输入 | zh-CN 默认格式化结果 | 说明 |
|---|---|---|
| 1234.5 USD（currency） | `US$1,234.50` | 中文区域默认给美元加 "US" 前缀 |
| 1234.5 USD（narrowSymbol） | `$1,234.50` | 需要显式使用窄符号 |
| 12,345 / 1,234,567 / 123,456,789（compact） | `1.2万` / `123.5万` / `1.2亿` | 中文紧凑数字用"万/亿" |
| 同样的数（en-US compact） | `12.3K` / `1.2M` / `123.5M` | — |
| 相对时间 -3 分钟 / -1 天 / -2 小时 | `3分钟前` / `昨天` / `2小时前` | `numeric: auto` |
| 日期 medium + 时间 short | `2026年10月16日 16:12` | — |
| 月日 + 24 小时制 | `10/16 16:12` | — |

### 5.3 建议规范（【推断】，供设计决策）

**1. 等宽数字**
- 所有会纵向对齐或会跳动的数字（金额、计数、Token、延迟、百分比、HTTP 码）都应使用 `.monospacedDigit()`（`View` 和 `Text` 修饰符均为 iOS 15，`Font.monospacedDigit()` 为 iOS 13）。
- 不要用 `.monospaced()` 整体换成等宽字体，因为 SF Mono 和正文混排时风格割裂（S5 中的 `$0.31` 就是例子）。
- 数值变化用 `.contentTransition(.numericText(value:))`（iOS 17）。

**2. 金额（美元）**
- 统一使用一个格式化器，替代两个 `money()`：

  ```swift
  // 显示用：$1,234.50（避免 zh-Hans 下出现 US$）
  value.formatted(.currency(code: "USD").presentation(.narrow).precision(.fractionLength(2)))
  ```

  `CurrencyFormatStyleConfiguration.Presentation.narrow` 已核实为 iOS 15。
- 千分位必须保留。Stripe 和 AWS 都显示 `$39,826.00`。
- 小额保留现有"3 到 4 位小数"的规则（`DashboardPresentation.swift:35-40`），但只在详情和明细中使用；列表行统一保留 2 位，低于 $0.01 时显示"< $0.01"。
- 货币符号和数字不得换行。W3C clreq §6.1.2.2 写明 "There should be no line break between the currency symbol and its associated European numerals"。数字所在的 `Text` 应加 `.lineLimit(1)` 或 `.fixedSize()`。
- "扣费"和"成本"在中文语境中不要用红色或绿色区分。HIG 指出在中文环境中红色表示"涨"，绿色表示"跌"。应该用标签文字区分，颜色保持中性；如果要表达"毛利 = 扣费 − 成本"，用正负号表示方向。

**3. Token 与大数**
- **建议 Token 量继续使用 K/M/B，不用"万/亿"**。理由：一是与 Web 后台和模型定价单位（"每百万 Token"）一致；二是 AI 行业的中文用户也普遍使用 1M、128K 这类写法。
- 精度调整：列表行最多 1 位小数，且去掉末尾的 0（`1.2M`，不是 `1.20M`）；详情页显示精确值加千分位（`1,204,331`）。

  ```swift
  tokens.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")).precision(.fractionLength(0...1)))
  ```

  `.notation(.compactName)` 已核实为 iOS 15。
- **人数、请求数**这类"非技术计量"，如果要本地化，可以使用系统区域的紧凑格式（"1.2万"），但**全 App 只能选一种**，并写进规范，避免同一屏出现"1.2万次请求 · 1.2M Token"。保守做法是全部使用 K/M。
- 无障碍标签读出完整数值和单位，例如 `.accessibilityLabel("120万 Token")`。HIG Charts 要求 "Write ... '60 minutes', not '60m'"。

**4. 时间**
- 列表行用相对时间，超过 7 天后切换为短绝对时间："3分钟前""昨天 16:12""10/09 16:12"。实现方式：
  - iOS 18：`Text(.currentDate, format: .reference(to: date))`，会随时间自动更新，并在超过阈值后自动切换为绝对时间（`SystemFormatStyle.DateReference` 已核实为 iOS 18）。
  - iOS 17：`TimelineView(.periodic(from: .now, by: 60))` 包住 `Text(date, format: .relative(presentation: .named))`。
- 详情页显示绝对时间到秒，并注明时区，例如"2026-10-16 16:12:00（UTC+8）"。AWS 在费用卡上写明了 "(UTC)"，后端时间桶的时区语义也在 `DashboardPresentation.swift:66-75` 中有讨论。
- 延迟统一使用技术单位：`850ms`、`1.25s`，数字和单位之间不加空格，与现有的 `duration()` 保持一致。无障碍标签读作"1.25 秒"。

**5. 中西文混排**
- W3C clreq §6.3.3：汉字与西文字母或数字之间 "tracking or spacing ... of up to 1/4 em"（https://www.w3.org/TR/clreq/ ）。
- SwiftUI 不会自动插入这个间距（【推断】，未找到 Apple 文档说明会自动加），所以在模板字符串里手动加普通空格，例如"已选 2 / 50""今日 Tokens""近 24 小时"。现有代码大多已经这样做了。
- 单位位置：表头或标签式单位用括号写进标签，例如"账户余额（元）"（阿里云写法）；行内数值用前缀符号（`$`）或紧跟的后缀单位（`ms`）。两种不要在同一个区域混用。
- 设备语言是英文、而内容是中文（例如用户名、备注）时，用 `.typesettingLanguage(.init(identifier: "zh-Hans"))`（iOS 17）获得正确的行高和断行。

**6. 截断**
- ID、Key、邮箱用 `.truncationMode(.middle)`。HIG Lists 写道："preserves both the beginning and the end"。
- 模型名用尾部截断。
- 所有截断项都可以长按复制，或进入详情查看完整内容。

### 5.4 Dynamic Type 下的高密度行

【证实】HIG 的建议是：字号变大时改为纵向堆叠，减少列数，保持信息层级。

【推断】实现手法：

```swift
// 1) 行级：放得下就横排，放不下就竖排（ViewThatFits，iOS 16）
ViewThatFits(in: .horizontal) {
    HStack(alignment: .firstTextBaseline) { title; Spacer(); value.monospacedDigit() }
    VStack(alignment: .leading, spacing: 2) { title; value.monospacedDigit() }
}

// 2) 区块级：辅助功能字号时切换布局（AnyLayout，iOS 16；dynamicTypeSize iOS 15）
@Environment(\.dynamicTypeSize) private var typeSize
var layout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout()) }
```

- 状态图标、圆点等尺寸用 `@ScaledMetric`（iOS 14）跟随字号缩放。
- 关键数字**不要**使用 `minimumScaleFactor`（见 A13）。正确做法是让卡片高度自适应，网格减少列数；`DashboardView.swift:304` 已经这样做了，应推广到所有卡片。
- 次要元数据在辅助功能字号下可以整行隐藏，只保留状态、名称和关键值，例如 `if !typeSize.isAccessibilitySize { metadataLine }`。完整信息在详情页提供，这符合 HIG "open a separate view to read the rest"。
- 图表坐标轴标签可以局部限制最大字号：`.dynamicTypeSize(...DynamicTypeSize.accessibility2)`（iOS 15）。这只用于坐标轴，正文不要限制。

---

## 6. iOS 26/27 特性在"最低 iOS 17"下的降级策略

### 6.1 对照表

| 能力 | API（最低 iOS） | iOS 17 降级 |
|---|---|---|
| Tab 新 API、搜索 Tab、侧栏 | `Tab`、`TabRole.search`、`TabSection`、`.sidebarAdaptable`（18.0） | `.tabItem`（27.2 起弃用，仍可编译）加普通"搜索"Tab；iPad 上按 size class 切换到 `NavigationSplitView` |
| 搜索 Tab 激活方式 | `.tabViewSearchActivation`（26.0） | 无 |
| Tab 栏最小化 | `.tabBarMinimizeBehavior`（26.0） | 无，也不建议启用 |
| Tab 底部附件 | `.tabViewBottomAccessory`（26.0）；`isEnabled:` 版本（26.1） | 根视图 `.safeAreaInset(edge: .bottom)` |
| 突出 Tab | `TabRole.prominent`（27.0） | 无 |
| 玻璃效果 | `.glassEffect`、`GlassEffectContainer`、`.glassEffectID`（26.0） | `.background(.regularMaterial, in: .capsule)`，只用于悬浮控件 |
| 玻璃按钮 | `.buttonStyle(.glass/.glassProminent)`（26.0） | `.bordered` / `.borderedProminent` |
| 可滚动边缘栏 | `.safeAreaBar`（26.0）；`.scrollEdgeEffectStyle`（26.0） | `.safeAreaInset`（15.0） |
| toolbar 分组与搜索 | `ToolbarSpacer`、`DefaultToolbarItem`、`.searchToolbarBehavior`、`sharedBackgroundVisibility`（26.0） | `ToolbarItemGroup`；`.searchable` 默认放置 |
| 导航副标题 | `.navigationSubtitle`（26.0） | `ToolbarItem(placement: .principal)` 放两行标题 |
| toolbar 溢出与优先级 | `ToolbarOverflowMenu`、`visibilityPriority`、`topBarPinnedTrailing`、`toolbarMinimizationBehavior`（27.0） | `Menu("更多", systemImage: "ellipsis.circle")` |
| 任意视图的滑动操作 | `swipeActionsContainer()`（27.0） | 只在 `List` 中使用 `.swipeActions`（15.0） |
| 拖动排序 | `reorderable()`、`reorderContainer`（27.0） | `List` 加 `.onMove`（EditMode） |
| 绑定 item 的对话框 | `confirmationDialog(_:item:)`、`alert(_:item:)`（WWDC26 新增，文档标注 15.0） | 若编译验证不可用，改用 `isPresented` 加 `presenting:` |
| 相对时间自动刷新 | `Text(.currentDate, format: .reference(to:))`（18.0） | `TimelineView` 加 `Date.RelativeFormatStyle`（15.0） |

### 6.2 推荐写法（集中封装，避免在页面里散布 `#available`）

```swift
extension View {
    @ViewBuilder func adminBottomBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if #available(iOS 26, *) { safeAreaBar(edge: .bottom) { content() } }
        else { safeAreaInset(edge: .bottom) { content() } }
    }
}
```

### 6.3 决策建议（【推断】）

- `.tabItem` 在 iOS 27.2 被标记弃用；2026-06 的统计显示 79% 的 iPhone 在 iOS 26；`Tab`、`TabSection`、`sidebarAdaptable`、`toolbarVisibility`、`Text(.currentDate, format:)` 都是 iOS 18 才有。综合这几点，**建议在 UI 重构时评估把最低版本提到 iOS 18**，这样可以删掉 TabView 的双分支代码。
- 如果必须保留 iOS 17，就需要维护两套 TabView 根视图。
- 这项决策会影响信息架构的实现成本，应在重构计划中单独列出。

---

## 7. 参考来源

**Apple 设计与文档**
- HIG：
  - Tab bars https://developer.apple.com/design/human-interface-guidelines/tab-bars
  - Toolbars https://developer.apple.com/design/human-interface-guidelines/toolbars
  - Lists and tables https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
  - Search fields https://developer.apple.com/design/human-interface-guidelines/search-fields
  - Charts https://developer.apple.com/design/human-interface-guidelines/charts
  - Sheets https://developer.apple.com/design/human-interface-guidelines/sheets
  - Menus https://developer.apple.com/design/human-interface-guidelines/menus
  - Context menus https://developer.apple.com/design/human-interface-guidelines/context-menus
  - Alerts https://developer.apple.com/design/human-interface-guidelines/alerts
  - Action sheets https://developer.apple.com/design/human-interface-guidelines/action-sheets
  - Materials https://developer.apple.com/design/human-interface-guidelines/materials
  - Color https://developer.apple.com/design/human-interface-guidelines/color
  - Segmented controls https://developer.apple.com/design/human-interface-guidelines/segmented-controls
  - Gauges https://developer.apple.com/design/human-interface-guidelines/gauges
  - Typography https://developer.apple.com/design/human-interface-guidelines/typography
  - Accessibility https://developer.apple.com/design/human-interface-guidelines/accessibility
- Adopting Liquid Glass https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- SwiftUI 更新页（June/September 2026） https://developer.apple.com/documentation/updates/swiftui
- API 页面（举例）：
  - https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
  - https://developer.apple.com/documentation/swiftui/view/tabitem(_:) （弃用于 27.2）
  - https://developer.apple.com/documentation/swiftui/form
  - https://developer.apple.com/documentation/swiftui/viewthatfits
  - https://developer.apple.com/documentation/swiftui/systemformatstyle/datereference
- WWDC：
  - WWDC25-323 https://developer.apple.com/videos/play/wwdc2025/323/
  - WWDC25-356 https://developer.apple.com/videos/play/wwdc2025/356/
  - WWDC26-269 https://developer.apple.com/videos/play/wwdc2026/269/
- App Store 系统版本分布 https://developer.apple.com/support/app-store/

**评论与第三方证据**
- NN/g "Liquid Glass Is Cracked" https://www.nngroup.com/articles/liquid-glass/
- TechTimes（iOS 27 调整） https://www.techtimes.com/articles/317975/20260608/apple-liquid-glass-ios-27-wwdc-2026-brings-refinements-developers-must-adopt-today.htm
- iOS 27.2 搜索 Tab 行为：https://github.com/zubair-io/Maple/pull/4409 、https://github.com/NativeScript/NativeScript/pull/11509
- W3C 中文排版需求 clreq https://www.w3.org/TR/clreq/

**同类产品**
- Datadog：https://docs.datadoghq.com/mobile/ 、https://docs.datadoghq.com/mobile/widgets/ 、https://www.datadoghq.com/blog/mobile-app-reduce-mttr/ 、https://apps.apple.com/us/app/datadog/id1391380318
- PagerDuty：https://support.pagerduty.com/main/docs/mobile-app 、https://www.pagerduty.com/platform/incident-management/on-call-management/mobile/ 、https://apps.apple.com/us/app/pagerduty/id594039512
- Grafana：https://grafana.com/docs/grafana-cloud/platform/mobile-app/get-started/ 、https://grafana.com/docs/grafana-cloud/platform/mobile-app/irm/respond-to-alerts/ 、https://apps.apple.com/us/app/grafana/id1669759048
- Stripe：https://docs.stripe.com/dashboard/mobile 、https://apps.apple.com/us/app/stripe-dashboard/id978516833
- AWS Console：https://docs.aws.amazon.com/consolemobileapp/latest/userguide/what-is-consolemobileapp.html 、https://apps.apple.com/us/app/aws-console/id580990573
- GitHub Mobile：https://apps.apple.com/us/app/github/id1477376905 、https://github.blog/changelog/2021-05-25-new-filtering-and-metadata-experience-on-github-mobile/ 、https://github.blog/changelog/2026-07-10-github-mobile-improved-filters-and-sorting-for-copilot-sessions/ 、https://github.com/orgs/community/discussions/18623 、https://devactivity.com/insights/github-app-s-mobile-ux-addressing-accidental-swipes-for-better-developer-productivity/
- Linear：https://linear.app/mobile 、https://apps.apple.com/us/app/linear-mobile/id1645587184
- App Store Connect：https://apps.apple.com/us/app/app-store-connect/id1234793120 、https://appleinsider.com/articles/26/03/25/developers-finally-get-more-app-store-data-from-apple
- Tailscale：https://tailscale.com/changelog 、https://apps.apple.com/us/app/tailscale/id1470499037
- 阿里云：https://apps.apple.com/cn/app/id981011420
- 缺席者：https://github.com/getsentry/sentry-mobile-release-health-app 、https://community.vercel.com/t/deployments-on-the-ios-homescreen-as-a-widget/4897 、https://apps.apple.com/us/app/rev-for-vercel/id6740740427 、https://apps.apple.com/us/app/dashboard-for-cloudflare/id6766168875
- 商店截图与版本信息获取方式：`https://itunes.apple.com/lookup?id=<id>&country=us`（2026-10-16 抓取）
