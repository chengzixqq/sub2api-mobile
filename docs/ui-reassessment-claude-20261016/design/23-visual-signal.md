# 23 · 视觉方向：暗舱（Dark Cockpit）——灯只为异常而亮

> 日期：2026-10-16 · 基线 `7ccd542` · 种子方向“夜航 / 信号”，本文把它定名为“暗舱”并做深化。
> 前提：`research/00-brief.md`（语义色含义、Liquid Glass 只用于控件层、最低 iOS 26）。本文只定**视觉系统**；信息架构（Tab 集合、模块划分）以 IA 方案为准，样屏里的 Tab 栏只作示意。
> 标注：**【事实】** 指可由 Apple 文档、本仓库代码或调研文档核实的内容；**【推断】** 指设计判断或尚需真机验证的内容。所有对比度都用 WCAG 2.x 相对亮度公式实际算过（计算脚本放在仓库外临时目录，没有写入仓库）。

---

## 0. 一页摘要

- **概念**：借用民航“暗驾驶舱”（dark cockpit / lights-out）原则：系统一切正常时，面板上没有一盏灯亮着；只有需要人处理的东西才会亮，亮得越强越紧急。放到 Sub2 管理端，就是**亮度＝注意力预算**：正常的账号、请求、读数一律“熄灭”（中性、低饱和），限流、错误、告警才“点亮”（饱和色、信号轨、深色下带微光）。
- **色彩**：深色以近黑的墨蓝为底（`#080B11`），浅色以冷雾灰为底（`#EEF1F5`），两套质量对等，并各有一套增强对比度版本。品牌色“航电青”（深色 `#47C8F5` / 浅色 `#0A6FA3`）**只表示“可操作”**，从不表示状态。语义色沿用简报：绿＝正常、琥珀＝限流/临时/接近上限、红＝错误/过载、灰＝停用/暂停/未知、紫＝模型级限流；成本三口径为实际（青玉绿）、成本（铜橙）、标准（灰）。四种模式下共 158 组关键配对全部达标（文字 ≥4.5:1，图形 ≥3:1）。
- **强调四级**：熄灭（正常，6pt 暗点）→ 描边（停用/暂停）→ 着色（会自行恢复的异常，带倒计时）→ 实心（需要人动手的错误）。颜色之外，**形状、文字、信号轨**三重冗余，色弱用户也能分清。
- **字体**：全部使用系统 Text Style 和 Dynamic Type。SF Pro 承担正文；SF Pro Rounded 只用于纯数字“读数”；SF Mono 只用于 ID 和流式输出；New York 不使用。中文交给 PingFang SC，字重上限为 Semibold。
- **Liquid Glass**：外壳全部交给系统（Tab 栏、导航栏、工具栏、搜索、sheet、菜单）；自定义 `.glassEffect` 只有两处：批量选择操作条、操作回执胶囊。内容层全部是不透明实底。
- **可直接用的代码**：第 10 节给出 `Theme`（四态动态色、字体、间距、圆角、状态映射）和三个基础组件（信号徽标、信号轨行背景、容量条样式），按 Swift 6 严格并发、iOS 26 SDK 编写。

---

## 1. 名称、概念与定位

### 1.1 名称与一句话

**暗舱（Dark Cockpit）**——“灯只为异常而亮。”

### 1.2 概念来源（【事实】）

- Airbus 自 A310 起采用“dark cockpit / lights out”理念：系统正常时开关和指示灯保持熄灭，出现故障才亮灯。A318–A321 FCTM 把它概括为“Light out philosophy. The systems are ready and fit to fly.”（[manualslib A318 手册 p.207](https://www.manualslib.com/manual/2570669/Airbus-A318.html?page=207)、[Aeropeep](https://aeropeep.com/which-aircraft-uses-the-dark-cockpit-concept/)）。
- ECAM 屏幕的颜色约定：红＝需要立即处理，琥珀＝需要注意，绿＝正常运行，**青＝需要执行的操作或可选择的项**，品红＝特殊信息，白＝标题与备注（[Wikipedia: ECAM](https://en.wikipedia.org/wiki/Electronic_centralised_aircraft_monitor)、[A350 安静暗舱](http://bloga350.blogspot.com/2015/06/a350-pilots-first-surprise-quiet-dark.html)；前者是二手资料，FCOM 原文未核对）。
- 这套约定和简报的语义色几乎一一对应：绿正常、琥珀限流、红错误、紫（品红）模型级限流，而品牌青恰好对应“可执行的操作”。所以本方向的品牌色不是装饰，**它在色彩语法里有明确的位置**。

### 1.3 为什么适合“中文优先的 AI API 中转站运营工具”

| 任务（简报 §1） | 暗舱给出的回答 |
|---|---|
| **救火：看账号异常/限流** | 正常账号全部熄灭，异常账号自带左侧信号轨和饱和徽标。翻列表时，用余光扫一眼“左边缘哪里亮了”就能定位，不必逐行阅读。限流等会自行恢复的状态必带倒计时，回答“还能不能用、什么时候恢复”。 |
| **给用户加余额/退款** | 资金动作用品牌青（“可执行”），确认用系统 destructive；金额一律用等宽读数加千分位，三口径颜色固定。界面越安静，资金操作的确认越显眼，误操作的代价越低。 |
| **早晚看营收和用量** | 首页“全部正常”时只剩一行静默状态和几组大号读数，3 秒扫完。深色是默认设计起点，深夜查看不刺眼（【推断】中转站运营者常在夜间被用户反馈叫醒）。 |
| **看渠道监控** | 渠道状态沿用同一套亮度语法：可用＝熄灭的绿点，性能下降＝琥珀点亮，不可用＝红色点亮。 |
| **中文优先** | 暗色开发者产品（Vercel、Raycast 一类）常靠全大写字母、字距和等宽标签建立层级，这些手法对中文全部失效。暗舱改用**亮度层级 + 字重 + 色彩通道**建立层级，不依赖大写和等宽，中文天然适用。 |
| **信任感** | 缺失值统一显示“—”，没有任何地方拿 0 冒充；数字等宽对齐、不跳动；颜色含义全 App 唯一。“安静”本身就是可靠的信号：亮着就一定有事。 |

### 1.4 与另外两种风格的根本区别

> 另外两种风格按名称理解（设计目录下暂无它们的文档），这里只比较**组织原则**，不评判优劣。

| 维度 | **暗舱（本方向）** | 精密仪器 | 账簿编辑 |
|---|---|---|---|
| 组织原则 | **亮度＝注意力**：先决定“哪里该亮”，再决定其余怎么排 | **刻度＝精度**：所有数据同等精确，靠网格、细线、刻度对齐建立秩序 | **版式＝叙事**：靠标题层级、衬线、留白讲“今天发生了什么” |
| 正常态的呈现 | 熄灭（6pt 暗点，甚至不显示文字） | 同样完整地标注 | 作为正文的一部分被叙述 |
| 异常态的呈现 | 点亮：饱和色、信号轨、深色下微光 | 刻度越界、色块标记 | 边注、批注、红字 |
| 默认外观 | 深色优先，浅色等质 | 浅色优先（工程图纸感） | 浅色（纸张感） |
| 数字的气质 | 圆体“读数”，像仪表灯管 | 等宽表格数，像游标卡尺 | 衬线或旧式数字，像账本 |
| 最擅长 | 巡检、救火、夜间值守 | 对比分析、容量规划 | 对账、日报、复盘 |
| 主要风险 | 白天户外偏暗；可能显得冷 | 冷、理性，异常不够跳 | 密度低，不适合扫读 |

**一句话区别**：精密仪器回答“有多准”，账簿编辑回答“意味着什么”，暗舱回答“现在该看哪里”。

### 1.5 五条视觉原则

1. **亮度即优先级**：同一屏里，饱和度和亮度只分配给需要处理的东西。
2. **正常态静默**：绿色只以 6pt 暗点出现；“全部正常”是一行字，不是一张绿卡片。
3. **信号有三重冗余**：颜色 + 形状（八角、沙漏、半圆、暂停、圆点）+ 文字（中文状态词）。任何一重缺失，另外两重都能独立表达。
4. **数字是读数**：大号数字用圆体等宽，单位缩小置灰；缺失值用“—”，不写“不可用”。
5. **控件在玻璃，数据在实底**：系统外壳用 Liquid Glass，内容一律不透明；品牌青只出现在“能点的东西”上。

---

## 2. 色彩

### 2.1 色彩通道分工（先规定“谁能用什么颜色”）

| 通道 | 允许的颜色 | 出现位置 | 不允许 |
|---|---|---|---|
| **结构**（背景、表面、分隔、文字） | 墨蓝灰阶 | 全部 | 带色相的背景卡片 |
| **交互**（可点、可选、主操作） | 品牌青 | 按钮、链接、选中态、Tab 选中、开关、图表选中线 | 表示任何状态 |
| **状态信号** | 绿 / 琥珀 / 红 / 灰 / 紫 | 状态点、徽标、信号轨、容量条填充、告警行 | 大面积背景、金额数字 |
| **金额口径** | 青玉（实际）/ 铜橙（成本）/ 灰（标准） | 金额前的 6pt 色点、图例、图表系列 | 状态徽标、金额数字本身（数字始终用主文字色） |
| **数据序列** | 品牌青单色阶 | 请求量、Token 量等单系列图；Token 构成（见 7.1） | 与状态色混用 |

### 2.2 浅色与深色令牌（标准对比度）

“图形”指信号轨、圆点、容量条填充、图表线（WCAG 1.4.11 要求 ≥3:1）；“徽标字”指着色底上的文字。深色下“文字 / 图形 / 徽标字”三者通常同值，浅色下按需要分为三档。

**背景与结构**

| 令牌 | 用途 | 浅色 | 深色 |
|---|---|---|---|
| `canvas` | 画布：页面底色、列表底色 | `#EEF1F5` 冷雾 | `#080B11` 墨夜（非纯黑，避免 OLED 滚动拖影） |
| `surface` | 内容面：面板、列表行 | `#FFFFFF` | `#0F141C` |
| `surfaceRaised` | 抬升面：面板内的瓦片、选中行、输入框 | `#F6F8FA` | `#161D27` |
| `track` | 轨道：容量条底、开关底、骨架块 | `#E9EDF2` | `#1D2532` |
| `hairline` | 分隔线、深色面板 0.5pt 描边 | `#DDE2E9` | `#232C39` |
| `stroke` | 强描边、刻度线、外框按钮描边 | `#B9C2CE` | `#344155` |
| `text1` | 主文字、所有数值 | `#0B1220` 墨 | `#E6ECF3`（非纯白，减轻光渗） |
| `text2` | 次文字：元数据、标签 | `#4B5565` | `#9DA9B9` |
| `text3` | 三级文字：时间戳、“—”、轴标签 | `#5E697B` | `#7A8699` |
| `brand` | 航电青：交互通道 | `#0A6FA3`（图形 `#1784BA`，徽标字 `#075C88`） | `#47C8F5` |
| `onBrand` | 实心品牌按钮上的文字 | `#FFFFFF` | `#06121A` |

**状态信号**（含义与简报一致，色值按本风格调校）

| 语义 | 中文状态词（以 Web 为准） | 浅色 文字 / 图形 / 徽标字 | 深色（三者同值，正常除外） |
|---|---|---|---|
| **正常** `ok` | 正常、可用 | `#0F7A45` / `#1A9150` / `#0B6638` | 文字 `#3FD47F`，暗点 `#2E9E63` |
| **限流·临时·接近上限** `caution` | 限流中、临时不可调度、配额超限、性能下降 | `#925700` / `#B87900` / `#7A4800` | `#FFB224` |
| **错误·过载·不可用** `critical` | 错误、过载中、不可用 | `#C42B22` / `#DC3A30` / `#A6211A`；实心底上用 `#FFFFFF` | `#FF6259`；实心底上用 `#1A0605` |
| **停用·暂停·未知** `neutral` | 停用、暂停、未知 | `#5E6979` / `#76818F` / `#4B5565` | `#8B97A8` |
| **模型级限流** `model` | 模型限流 | `#7B3BC9` / `#9156E0` / `#6630AE` | `#C08AFF` |
| **静默读数** `quiet` | （无状态词：正常容量、默认迷你趋势） | 图形 `#76818F` | 图形 `#6E7A8C` |

**成本三口径**

| 口径 | 短标签 / 详情标签（04 §5 裁决） | 浅色 | 深色 | 图表线型 |
|---|---|---|---|---|
| 实际 `actual` | 实际 / 实际扣费 | `#0A7660` 青玉 | `#3CCBA6` | 2pt 实线 + 面积渐变 |
| 成本 `cost` | 成本 / 账号成本 | `#B04C14` 铜橙 | `#F08B4F` | 1.5pt 实线 |
| 标准 `standard` | 标准 / 标准费用 | `#5E6979` | `#8B97A8` | 1.5pt 虚线 `[4, 3]` |

**着色底不透明度**（同色相叠在 `surface` 上）：徽标 浅 12% / 深 16%；横幅 浅 10% / 深 22%；图表面积 浅 12% / 深 22%。

**两条硬规则**
- 金额**数字本身**永远用 `text1`，颜色只出现在数字前的 6pt 色点和图表上。这样“绿色金额”不会被误读为“涨”（03 §5.3 引 HIG：中文环境下红涨绿跌），也不会和“正常绿”混淆。
- “正常绿”和“实际青玉”色相相差约 19°（146° 对 165°），而且两者**永远不出现在同一种视觉位置**：前者只做状态点，后者只做金额色点和图表线。

### 2.3 增强对比度（`accessibilityContrast == .high` / `colorSchemeContrast == .increased`）

| 令牌 | 浅色·增强 | 深色·增强 | 调整说明 |
|---|---|---|---|
| `canvas` / `surface` / `surfaceRaised` | `#E6EAF0` / `#FFFFFF` / `#F3F5F8` | `#030407` / `#0B0F15` / `#121821` | 拉开画布和内容面的明度差 |
| `track` | `#D3DAE3` | `#232D3B` | 轨道更明显 |
| `hairline` / `stroke` | `#848F9E` / `#6B7685` | `#56657B` / `#6B7B92` | 分隔线升到 ≥3:1；面板加 1pt 外框 |
| `text1` / `text2` / `text3` | `#000000` / `#323B49` / `#455061` | `#F5F8FC` / `#BCC6D3` / `#9DA9B9` | 次文字 ≥9:1 |
| `brand` | `#06567F` | `#6CD5FA` | — |
| `ok` / `caution` / `critical` | `#0A6236` / `#734300` / `#A11B14` | `#5BE396` / `#FFC24D` / `#FF7D75` | 浅色三档合一（全部按文字标准取值） |
| `neutral` / `model` / `quiet` | `#465060` / `#5F27A8` / `#4F5A6A` | `#A7B2C1` / `#D0ADFF` / `#8B97A8` | — |
| 实际 / 成本 / 标准 | `#075F4D` / `#8F3B0D` / `#465060` | `#5ADBB8` / `#F7A06B` / `#A7B2C1` | — |
| 着色底不透明度 | 徽标 14% | 徽标 20% | 着色更实 |

除色值外，增强对比度下还有以下行为变化：
- 深色微光全部关闭，因为光晕会降低边缘清晰度。
- 面板加 1pt `stroke` 外框。
- 描边徽标的线宽从 1pt 加到 1.5pt。
- 图表面积填充降到浅 8% / 深 14%；网格线改为实线。
- 容量条的阈值刻度改用 `text2`。

### 2.4 对比度核算（节选，四种模式全部配对均通过）

> 算法：WCAG 2.x 相对亮度。着色底按“色值 × 不透明度 + `surface` × (1 − 不透明度)”混合后再计算。全表共 158 组配对，0 组不通过；下表列出最关键、最接近阈值的配对。

| 模式 | 前景 → 背景 | 对比度 | 要求 |
|---|---|---|---|
| 深色 | `text1` `#E6ECF3` → `surface` `#0F141C` | 15.53:1 | 4.5 |
| 深色 | `text2` `#9DA9B9` → `surface` | 7.75:1 | 4.5 |
| 深色 | `text3` `#7A8699` → `surfaceRaised` `#161D27`（最低一组） | 4.60:1 | 4.5 |
| 深色 | `brand` `#47C8F5` → `surface` | 9.54:1 | 4.5 |
| 深色 | `critical` `#FF6259` → `surface` | 6.28:1 | 4.5 |
| 深色 | `critical` 徽标字 → 16% 着色底 `#352026` | 5.15:1 | 4.5 |
| 深色 | 实心错误徽标字 `#1A0605` → `#FF6259` | 6.66:1 | 4.5 |
| 深色 | `caution` `#FFB224` → 16% 着色底 `#352D1D` | 7.54:1 | 4.5 |
| 深色 | `neutral` `#8B97A8` → 16% 着色底 `#232932` | 4.94:1 | 4.5 |
| 深色 | `model` `#C08AFF` → 16% 着色底 `#2B2740` | 5.67:1 | 4.5 |
| 深色 | 正常暗点 `#2E9E63` → `track` `#1D2532` | 4.54:1 | 3（图形） |
| 深色 | `quiet` 容量填充 `#6E7A8C` → `track` | 3.54:1 | 3（图形） |
| 深色 | 主按钮字 `#06121A` → `brand` | 9.78:1 | 4.5 |
| 深色 | 实际 `#3CCBA6` / 成本 `#F08B4F` / 标准 `#8B97A8` → `surface` | 9.04 / 7.48 / 6.23 | 4.5 |
| 浅色 | `text1` `#0B1220` → `surface` `#FFFFFF` | 18.72:1 | 4.5 |
| 浅色 | `text3` `#5E697B` → `canvas` `#EEF1F5`（最低一组） | 4.90:1 | 4.5 |
| 浅色 | `brand` `#0A6FA3` → `canvas` | 4.86:1 | 4.5 |
| 浅色 | `ok` `#0F7A45` → `canvas` | 4.76:1 | 4.5 |
| 浅色 | `caution` `#925700` → `surface` | 5.86:1 | 4.5 |
| 浅色 | `critical` `#C42B22` → `canvas` | 4.99:1 | 4.5 |
| 浅色 | 徽标字 `ok` `#0B6638` → 12% 着色底 `#E2EFE9` | 5.97:1 | 4.5 |
| 浅色 | 徽标字 `caution` `#7A4800` → 12% 着色底 `#F2EBE0` | 6.44:1 | 4.5 |
| 浅色 | 实心错误徽标字 `#FFFFFF` → `#C42B22` | 5.65:1 | 4.5 |
| 浅色 | 图形 `caution` `#B87900` → `track` `#E9EDF2`（最低一组） | 3.09:1 | 3（图形） |
| 浅色 | 图形 `neutral` `#76818F` → `track` | 3.37:1 | 3（图形） |
| 浅色 | 主按钮字 `#FFFFFF` → `brand` | 5.50:1 | 4.5 |
| 浅色 | 实际 `#0A7660` / 成本 `#B04C14` / 标准 `#5E6979` → `surface` | 5.57 / 5.40 / 5.57 | 4.5 |
| 深色·增强 | `text1` → `surface` / `text2` → `surface` | 18.03 / 11.12 | 7 / 4.5 |
| 深色·增强 | `critical` 徽标字 `#FF7D75` → 20% 着色底 | 5.68:1 | 4.5 |
| 深色·增强 | 分隔线 `#56657B` → `surface` | 3.24:1 | 3 |
| 浅色·增强 | `text2` `#323B49` → `canvas` | 9.36:1 | 7 |
| 浅色·增强 | 全部状态色 → `surface` | 7.46–8.97:1 | 6 |
| 浅色·增强 | 分隔线 `#848F9E` → `surface` | 3.28:1 | 3 |

**灰度可分性**（色弱与全色盲的兜底）：深色下各色的相对亮度为：琥珀 0.53、绿 0.50、青 0.49、铜橙 0.38、紫 0.37、红 0.31、灰 0.30。**红与灰亮度几乎相同**，所以错误必须是“实心 + 八角形 + 信号轨”，暂停必须是“描边 + 暂停符号 + 无信号轨”，靠形态而不是颜色区分。浅色下所有状态色为了满足文字对比度，亮度都集中在 0.12–0.15，灰度下更依赖形态。这是本方向刻意设计**强调四级**（2.5）的原因。

### 2.5 强调四级（亮度预算）

| 级别 | 用于 | 徽标形态 | 信号轨（行左缘 3pt） | 深色微光 |
|---|---|---|---|---|
| **L0 熄灭** | 正常、可用、成功请求、无数据“—” | 6pt 暗点，列表里不写“正常” | 无 | 无 |
| **L1 标示** | 停用、暂停、未知；客户端原因的错误请求 | 1pt 描边胶囊 + 灰字 | 无 | 无 |
| **L2 点亮** | 限流中、过载中、临时不可调度、配额超限、模型限流；P1 告警；性能下降 | 着色胶囊 + 同色字，**有截止时间就带倒计时** | 有 | 半径 5、不透明度 35% |
| **L3 主警** | 错误（需要人动手：凭据失效、上游拒绝）；P0 告警 | **实心**胶囊 + 反白字 | 有 | 半径 8、不透明度 55% |

区分规则：**会自行恢复的用着色（L2），需要人动手的用实心（L3）**。所以过载虽然是红色，但它有 `overload_until` 截止时间，属于 L2；错误没有截止时间，属于 L3。

---

## 3. 字体

### 3.1 四种字体的角色

| 字体 | 角色 | 使用范围 | 不使用的地方 |
|---|---|---|---|
| **SF Pro**（系统默认，自动在 Text/Display 光学尺寸间切换） | 全部界面文字，以及中小号数字 | 标题、列表、标签、按钮、徽标、金额（行内） | — |
| **SF Pro Rounded** | **读数**：只用于纯数字 | 首页 KPI 大数、账号详情倒计时、容量读数大字、图表选中读数卡 | 任何含中文的文字串；按钮；正文 |
| **SF Mono** | **标识符与机器输出** | 请求 ID、API Key 前缀、上游模型 ID（详情页）、账号测试的流式输出 | 金额、计数、时间（这些用 `monospacedDigit()` 的 SF Pro） |
| **New York** | 不使用 | — | 衬线属于“账簿编辑”的叙事语气。中文在 `.serif` 设计下回退到什么字形，官方文档没有说明（【推断】需真机核实），本方向不依赖它 |

选择圆体做读数的理由（【推断】）：
- 深色底上的亮字会因光渗效应显得更粗、边缘发虚。圆体端点更柔和，大字号下更接近仪表“灯管数字”的观感。
- 圆体与 SF Pro 同骨架，混排时不会跳风格（03 §5.3 指出 SF Mono 与正文混排会割裂）。

### 3.2 中文（PingFang SC）注意事项

1. **字重上限为 Semibold。**【事实】PingFang SC 只有 Ultralight、Thin、Light、Regular、Medium、Semibold 六个字重。SwiftUI 设为 `.bold` 或更重时，拉丁字母会变成 Bold，中文最多到 Semibold，同一行里出现两种粗细。规范：凡是可能含中文的文字，字重 ≤ `.semibold`。
2. **圆体不含中文。**`design: .rounded` 只作用于拉丁字母和数字，中文会回退到 PingFang 常规字形（【推断】需真机核实具体回退）。所以圆体只用于纯数字 `Text`，单位（“$”“M”）可以一起放进去，中文标签（“实际”“今日”）必须单独成 `Text`。
3. **不用斜体、不加字距、不用全大写。**PingFang 没有斜体；`.tracking` 会破坏汉字等宽节奏。暗色开发者产品惯用的“全大写 + 字距”小标签，在中文里没有对应物，统一改用 `footnote.weight(.semibold)` 加 `text2`。
4. **最小字号。**中文正文不低于 `.footnote`（13pt）。`.caption`（12pt）只用于纯数字或拉丁缩写（坐标轴、单位）；`.caption2`（11pt）不用于中文。
5. **中西文间距。**SwiftUI 不会自动加间距，在模板字符串里手动加半角空格：“今日 1,204 请求”“并发 1 / 4”“近 24 小时”。数字和单位紧贴：“850ms”“1.25s”“126.4M”。
6. **混排对齐。**同一行既有中文标签又有数字时，用 `HStack(alignment: .firstTextBaseline)`。PingFang 的字面框比 SF Pro 高，用 `.center` 对齐会让数字看起来下沉。
7. **系统语言是英文、内容是中文**（例如账号名、备注）：加 `.typesettingLanguage(Locale.Language(identifier: "zh-Hans"))`（iOS 17+），保证行高和断行正确。
8. **标点**：中文句子用全角标点；状态词之间的分隔用“ · ”（前后各一个半角空格）。

### 3.3 文字层级（全部基于 Text Style，随 Dynamic Type 缩放）

| 令牌 | SwiftUI 定义 | 默认字号 / 行高 | 用途 |
|---|---|---|---|
| `readoutHero` | `.system(.largeTitle, design: .rounded, weight: 深色 .medium / 浅色 .semibold).monospacedDigit()` | 34 / 41 | 首页主读数（今日实际）、详情页倒计时 |
| `readout` | `.system(.title2, design: .rounded, weight: 深色 .medium / 浅色 .semibold).monospacedDigit()` | 22 / 28 | 次要 KPI 读数（成本、请求、Token） |
| `readoutUnit` | `.system(.title3, design: .rounded, weight: .regular)` | 20 / 25 | 读数前后的 `$`、`M`（用 `text2`） |
| `screenTitle` | `.title3.weight(.semibold)` | 20 / 25 | 详情页头部对象名 |
| `sectionLabel` | `.footnote.weight(.semibold)` | 13 / 18 | 面板标题（“需要处理”“容量”），`text2`，不大写 |
| `rowTitle` | `.body.weight(.medium)` | 17 / 22 | 列表行主标题（账号名、模型名） |
| `rowFigure` | `.body.weight(.medium).monospacedDigit()` | 17 / 22 | 行尾主数值（今日请求数） |
| `meta` | `.subheadline` | 15 / 20 | 行次要信息（平台 · 分组）、标签 |
| `metaFigure` | `.subheadline.monospacedDigit()` | 15 / 20 | 次要数值（金额、并发 1 / 4） |
| `badge` | `.footnote.weight(.semibold).monospacedDigit()` | 13 / 18 | 状态徽标（含倒计时） |
| `timestamp` | `.footnote.monospacedDigit()` | 13 / 18 | 相对时间、“—”，`text3` |
| `axis` | `.caption.monospacedDigit()` | 12 / 16 | 图表坐标轴（纯数字和时间） |
| `identifier` | `.system(.footnote, design: .monospaced)` | 13 / 18 | 请求 ID、Key 前缀（中间截断） |
| `streamOutput` | `.system(.footnote, design: .monospaced)` | 13 / 18 | 账号测试流式输出 |

导航标题沿用系统样式（根页面 `.inline` 加 `navigationSubtitle` 显示站点），不自定义导航栏字体。

**深色降一级字重**：深色下 `readoutHero` 和 `readout` 从 Semibold 降为 Medium，用来抵消亮字在暗底上的光渗增粗（【推断】排版经验，需真机目测确认）。用户开启“粗体文本”时，系统会自动加粗，不必另做处理。

### 3.4 数字规则

- **一律 `monospacedDigit()`**：所有会纵向对齐、会刷新跳动的数字（金额、计数、Token、延迟、百分比、HTTP 码、倒计时）都要等宽，包括列表行。
- **只有一套格式化入口**（建议在 `Sub2Core/DashboardPresentation` 统一，取代 `Components.money()`）：

| 类型 | 列表 / 卡片 | 详情 | 实现 |
|---|---|---|---|
| 金额 | `$1,284.50`；小于 $0.01 显示 `< $0.01` | 小额保留到有效位：`$0.0024` | `.currency(code: "USD").presentation(.narrow).precision(.fractionLength(2))`，避免 zh-Hans 下出现 `US$` |
| Token | `126.4M`、`845K`、`1.2M`（最多 1 位小数，去掉尾随 0） | `1,204,331` | `.number.notation(.compactName).locale(Locale(identifier: "en_US")).precision(.fractionLength(0...1))` |
| 计数 | `48.2K`（与 Token 同一套 K/M，全 App 不出现“万”） | `48,213` | 同上 |
| 时间 | `3分钟前`、`昨天 16:12`、`10/09 16:12` | `2026-10-16 16:12:07（UTC+8）` | `Text(.currentDate, format: .reference(to: date))`（iOS 18+，自动刷新） |
| 时长 | `850ms`、`1.25s` | 同左 | 现有 `DashboardPresentation.duration` |
| 倒计时 | `4:37`、`1:04:37` | 同左，读数字号 | `Text(timerInterval: now...deadline, countsDown: true)`（iOS 16+） |
| 百分比 | `0.8%`、`+6%`（带符号表示方向） | 同左 | `.percent.precision(.fractionLength(0...1))` |
| 缺失 | `—`（`text3`；VoiceOver 读“未返回”） | 同左 | `.accessibilityLabel("未返回")` |

**排版样例**（`│` 表示 `HStack(alignment: .firstTextBaseline)` 的分段）：

```
读数（首页）      实际                                ← sectionLabel · text2
                  $ │ 1,284.50                        ← readoutUnit text2 │ readoutHero text1
                  ● 标准 $1,402.00                    ← 6pt 灰点 │ meta text2 │ metaFigure text1

行内三口径        ● 实际 $12.40   ● 成本 $7.85   ┄ 标准 $14.02
                  （色点 6pt；标签 meta text2；数字 metaFigure text1；“标准”用虚线短划代替圆点）

Token             126.4M Token        详情：1,204,331 Token（输入 812,004 · 输出 392,327）
时间              3分钟前 ·  昨天 16:12 ·  10/09 16:12
倒计时徽标        [⧗ 限流中 4:37]      ← badge；数字每秒刷新，等宽不抖
缺失              并发  — / 4          ← “—” 用 text3；VoiceOver：“并发，未返回，上限 4”
```

---

## 4. 形状与表面

### 4.1 圆角体系（连续圆角 + 同心）

| 层 | 形状 | 数值 | SwiftUI |
|---|---|---|---|
| 面板（首页、详情的分组块） | 连续圆角矩形 | 22pt | `RoundedRectangle(cornerRadius: 22, style: .continuous)`，并设为 `.containerShape(...)` |
| 面板内瓦片（KPI 瓦片、模型限流子块） | **同心矩形** | 随外层自动计算，最小 12pt | `ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)`（iOS 26） |
| 列表行 | 无圆角（`List(.plain)` 通栏） | — | `.listRowBackground(...)` |
| 徽标、筛选胶囊、容量条 | 胶囊 | — | `Capsule()` |
| 输入框 | 连续圆角 | 12pt | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| sheet、菜单、弹窗、Tab 栏 | 系统决定 | — | 不覆盖 |

【事实】`ConcentricRectangle` 在 iOS 26.0 引入，按 `containerShape(_:)` 设定的容器形状自动计算各角半径，使内外圆角同心（[Apple 文档](https://developer.apple.com/documentation/swiftui/concentricrectangle)）。面板设了 `containerShape` 后，里面的瓦片无论内边距多少都保持同心，与 iOS 26 的 sheet、屏幕圆角是同一种几何语言。

### 4.2 表面策略（内容层一律不透明）

| 元素 | 浅色 | 深色 |
|---|---|---|
| 页面 | `canvas` | `canvas` |
| 面板 | `surface` 实底，**无阴影、无描边** | `surface` 实底 + 0.5pt `hairline` 描边（深色下阴影无效，靠细线勾边） |
| 列表 | `List(.plain)` 通栏：行用 `surface`，分组标题坐在 `canvas` 上 | 同左 |
| 瓦片 | `surfaceRaised` | `surfaceRaised` |
| 告警横幅 | 状态色 10% 着色底 + 左侧 3pt 信号轨 | 状态色 22% 着色底 + 信号轨 |
| 增强对比度 | 面板加 1pt `stroke` 外框 | 面板 1pt `stroke` 外框，关闭微光 |

- **阴影**：内容层不使用投影。唯一的“光”是 L2/L3 徽标在深色下的微光，而且只加在徽标的胶囊底上，不加在文字上。
- **分隔线**：列表行之间用 0.5pt `hairline`，左端对齐到文字起点（`.alignmentGuide(.listRowSeparatorLeading)`），不贯穿状态图标列；面板内部用 `Space.m` 的留白分组，不画线。
- **信号轨**：L2/L3 行的左缘 3pt 竖条，放在 `listRowBackground` 里，所以会贯穿整行高度并贴住屏幕边缘。

### 4.3 间距与密度

**间距刻度**（4pt 网格）：`xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 20 · xxl 28 · section 32`。面板内边距用 `l`，面板之间用 `m`，大区块之间用 `xl`。

**列表行几何**（默认字号 Large）：

| 行类型 | 结构 | 内边距（上/左/下/右） | 行高 |
|---|---|---|---|
| 账号行（正常） | 标题行（17pt）+ 元数据行（15pt），间距 2 | 10 / 16 / 10 / 16 | 22 + 2 + 20 + 20 ≈ **64pt** |
| 账号行（带错误摘要） | 再加一行错误摘要（15pt，限 1 行） | 同上 | ≈ **86pt** |
| 日志行 | 标题行 + 元数据行（数值右对齐） | 8 / 16 / 8 / 16 | ≈ **60pt** |
| 详情属性网格 | 两列 `Grid`，每格“标签 / 值”上下排 | 面板内 `l` | 每行 ≈ 44pt |

**每屏可见目标**（iPhone 6.3 英寸、402×874pt、默认字号；扣除状态栏、导航栏、筛选胶囊条和浮动 Tab 栏遮挡后，约有 600pt 无遮挡内容区）：
- 账号：**≥ 8 个**（现状 3–4 个）。
- 日志：**≥ 10 条**（现状 1–3 条）。
- 辅助功能字号 AX3：账号 ≥ 3 个，日志 ≥ 4 条。

可点区域一律 ≥ 44×44pt：状态徽标本身不可点，整行可点；筛选胶囊高度 36pt，外加 4pt 的 `contentShape` 扩展。

---

## 5. Liquid Glass 用法

### 5.1 交给系统的玻璃（不定制外观）

| 位置 | 实现 | 本方向的设置 |
|---|---|---|
| Tab 栏（含搜索 Tab） | `TabView` + `Tab(...)`、`Tab(role: .search)`、`.tabViewSearchActivation(.searchTabSelection)` | `.tint(Theme.Palette.brand)`；只在“需处理账号数”上用 `.badge(n)`（系统红） |
| 导航栏、工具栏按钮 | `NavigationStack`、`.toolbar`、`ToolbarSpacer` | 图标单色；工具栏分组不超过 3 个 |
| 站点切换 | `.toolbarTitleMenu { … }` + `.navigationSubtitle(站点名 · 更新时间)` | 标题旁 `⌄`，点开即切站 |
| 搜索框 | `.searchable` | 系统默认 |
| sheet、菜单、`confirmationDialog`、alert | 系统 | **不设置** `presentationBackground`（03 §1.6） |
| 筛选胶囊条 | 放在 `.safeAreaBar(edge: .top)` 中，参与滚动边缘效果 | 胶囊本身用 `.buttonStyle(.bordered)` + `.buttonBorderShape(.capsule)`（不是玻璃），激活时着品牌青 |
| 滚动边缘 | `.scrollEdgeEffectStyle(.hard, for: .top)`：用于带胶囊条的列表页，让密集内容与顶栏分界清楚；其他页面保持默认 `.soft` | — |

### 5.2 自定义 `.glassEffect`：只有两处

| # | 位置 | 理由 | 实现要点 |
|---|---|---|---|
| G1 | **批量选择操作条**（账号多选后浮在底部：“已选 5 · 停止调度 · 启用调度 · 更多”） | 跨滚动位置常驻的控件，本质是工具栏 | `.safeAreaBar(edge: .bottom)` 中放 `GlassEffectContainer(spacing: 8)`；主操作 `.buttonStyle(.glassProminent)`（品牌青），其余 `.buttonStyle(.glass)`；选择模式下 `.toolbarVisibility(.hidden, for: .tabBar)` |
| G2 | **操作回执胶囊**（“已停止调度 · 撤销”，4 秒后消失；“结果待核对”不用它，见 8.3） | 瞬时浮层，不属于内容 | `.glassEffect(.regular.interactive(), in: .capsule)`；图标按结果着色（成功 `ok`、失败 `critical`），**玻璃本身不着色** |

### 5.3 着色规则

- 玻璃只允许着**品牌青**，而且只用于“唯一的主操作”（`.glassProminent` 或 `.tint(brand)`）。
- **状态色永远不着在玻璃上**：没有红玻璃、没有琥珀玻璃。状态属于内容层，玻璃属于控件层，两者不混用。
- 系统 Tab 栏上的数字徽标（红底白字）是系统行为，保留。

### 5.4 深浅色下与内容的分离

- **深色**：玻璃压在近黑的内容上，呈烟灰色。风险在于饱和色块滑到 Tab 栏下面会把整个底栏染色（05 §4.9：品红柱状图染红底栏）。对策：
  - 内容层没有大面积饱和填充：图表面积 ≤22%、柱状图改为细线、徽标很小、微光半径 ≤8pt。
  - 列表页顶部用 `.hard` 边缘效果。
- **浅色**：玻璃压在白色和冷雾上，几乎透明，依赖系统的边缘高光区分。对策：页面底色用 `canvas` 冷雾灰（而不是纯白），让浮动 Tab 栏的轮廓更清楚。
- **iOS 27**：用户可以通过 Liquid Glass 色调滑杆调整透明度（03 §0.3）。本方向不对抗这个设置，只要求内容层自身对比度达标。
- **降低透明度**（Reduce Transparency）：系统玻璃和 `.glassEffect` 会自动变得更不透明，无需额外处理。

---

## 6. 图标与插画

### 6.1 SF Symbols 规范

| 场景 | 渲染模式 | 字重 / 尺寸 |
|---|---|---|
| Tab、工具栏、菜单 | `.monochrome`（系统默认） | 跟随系统 |
| 状态符号（行首、徽标内） | `.monochrome` + 状态色。不用 `.hierarchical`，因为它的半透明层在深色上会降低对比度 | 与相邻文字同字重；行首符号 `.imageScale(.medium)`，徽标内 `.imageScale(.small)` |
| 空状态、功能入口 | `.hierarchical` + `text2` | 跟随 `.title2` |
| `.multicolor` | **不使用**，因为系统多色会破坏语义色通道 | — |
| 状态切换 | `.contentTransition(.symbolEffect(.replace))` | 减弱动态效果时去掉 |

### 6.2 状态图标集（形状本身可区分，不依赖颜色）

| 状态 | SF Symbol | 形状特征 | 强调级 | 色调 | VoiceOver |
|---|---|---|---|---|---|
| 正常 | `circle.fill`（6pt） | 实心小圆点 | L0 | `ok` 暗点 | “正常” |
| 限流中 | `hourglass` | 沙漏 | L2 | `caution` | “限流中，4 分钟后恢复” |
| 临时不可调度 | `clock.badge.exclamationmark` | 钟 + 叹号 | L2 | `caution` | “临时不可调度，12 分钟后恢复” |
| 配额超限 | `gauge.with.dots.needle.100percent` | 满刻度表盘 | L2 | `caution` | “配额超限” |
| 过载中 | `flame.fill` | 火焰 | L2 | `critical` | “过载中，2 分钟后恢复” |
| 错误 | `exclamationmark.octagon.fill` | **八角形**（停止标志） | L3 | `critical` 实心 | “错误：认证失败……” |
| 模型限流 | `circle.lefthalf.filled` | 半实心圆＝部分可用 | L2 | `model` | “2 个模型限流” |
| 暂停 | `pause.circle` | 双竖线 | L1 | `neutral` 描边 | “暂停调度” |
| 停用 | `minus.circle` | 横杠 | L1 | `neutral` 描边 | “停用” |
| 未知 | `questionmark.circle` | 问号 | L1 | `neutral` 描边 | “状态未知” |
| 告警（P0 / P1） | `bell.badge.fill` | 铃 | L3 / L2 | `critical` / `caution` | “P1 告警：错误率过高” |
| 渠道不可用 / 性能下降 | `antenna.radiowaves.left.and.right.slash` / `antenna.radiowaves.left.and.right` | 天线 | L3 / L2 | `critical` / `caution` | — |

**操作图标**（都着品牌青，符合“青＝可执行”）：清除限流、恢复状态 `arrow.counterclockwise`；测试 `waveform.path.ecg`；停止调度 `pause.circle`；启用调度 `play.circle`；刷新凭据 `key.horizontal`；撤销 `arrow.uturn.backward`。

> 符号名按 SF Symbols 4 及以上的命名书写，实施前需在 SF Symbols 7 App 中逐一核对是否存在及最低系统版本（【推断】）。

### 6.3 插画

不画吉祥物，也不放装饰插图。空状态只用一个 `.hierarchical` 符号加一行字：
- 全部正常：`checkmark.circle` 暗绿，“全部正常 · 82 个账号在线”。
- 无结果：`ContentUnavailableView.search(text:)`。
- 未开启运维监控：`antenna.radiowaves.left.and.right.slash`，“站点未开启运行监控”。

### 6.4 App 图标概念：“中继航迹”

- **构图**（1024 画布）：
  - 背景：墨夜渐变，自上 `#0B1220` 到下 `#05070B`。
  - 主体：一条 S 形“航迹线”（青色 `#47C8F5`，线宽约 56px），从左下延伸到右上，既是信号轨迹，也是对 Sub2 “S” 的继承。
  - 节点：航迹上有三个节点，分别是来源（左下，暗）、**中继**（正中，最亮，带一圈 12% 不透明度的光环）、上游（右上，暗）。整体隐喻“中转站把请求接力到上游”。
  - 留白：不放文字，不放告警色，因为图标不应永远像在报警。
- **Icon Composer 分层**（Xcode 26，iOS 26 分层 Liquid Glass 图标）：L1 背景渐变，L2 航迹线（玻璃高光），L3 中继节点。
- **外观变体**：
  - 默认（浅色）：冷雾底配深青航迹 `#0A6FA3`。
  - 深色：墨夜底配亮青。
  - 着色：只保留亮度层次。
  - 透明：只保留航迹和节点。
- **小尺寸**（设置页 29pt）：去掉两端节点，只保留 S 航迹和中继点，线宽相对加粗。
- 与现有图标的关系：现图标是青绿底配白色“S”加尖括号。新图标保留“S”和“青”两个可识别特征，换成自己的语言（墨夜底、信号航迹）。

---

## 7. 数据可视化（Swift Charts）

### 7.1 配色

| 图表 | 系列与颜色 | 说明 |
|---|---|---|
| 营收趋势 | 实际（青玉，2pt 实线 + 面积渐变）、成本（铜橙，1.5pt）、标准（灰，1.5pt 虚线） | 三口径颜色固定 |
| 请求、Token、RPM/TPM 单系列 | 品牌青 1.5pt + 面积渐变 | 数据序列通道 |
| Token 构成（输入/输出/缓存读/缓存写） | **品牌青单色四阶**（100% / 70% / 45% / 25%）+ 文字图例 | 【偏离 Web，需用户确认】Web 用翠绿/紫罗兰/天蓝/琥珀（04 §4.1-13），其中紫和琥珀与状态色冲突。如果坚持与 Web 一致，可退回 Web 四色，但需降饱和 |
| 错误数、错误率 | `critical` 细柱，**为 0 的时段不画** | 正常时整张图只有一条贴底的静默线 |
| 延迟分档 | 良好 `quiet`、偏慢 `caution`、慢 `caution`（加双档图标）、严重 `critical`；阈值照搬 Web：首字 10/30/60s，总耗时 60/180/300s | 【偏离 Web】Web 的“良好”是翠绿；暗舱中正常不点亮 |
| 渠道健康矩阵 | 可用 `ok` 暗点、性能下降 `caution`、不可用 `critical`、无样本 `track` 灰块 | — |

### 7.2 线、网格与标注

- **线宽**：主系列 2pt，次系列 1.5pt，迷你趋势 1.25pt；`.interpolationMethod(.monotone)`，线端和拐角都用圆头。
- **面积**：自上而下线性渐变，从系列色（浅 12% / 深 22%）过渡到透明。增强对比度下降到 8% / 14%。
- **网格**：只画水平网格，0.5pt `hairline` 虚线 `[2, 3]`，最多 3 条；不画垂直网格。
- **坐标轴**：Y 轴放在**右侧**（像仪表刻度），只标 3 个刻度；X 轴每 6 小时一个标签；字体为 `axis` + `text3`。单位写进标题，不写在轴上（HIG Charts）。
- **标题即结论**：例如“实际扣费比昨天同时 +6%”，副标题写范围和缺口，例如“今日 00:00 起 · 部分时段无费用数据”。
- **缺失**：缺数据的时段**断开线段**，不连线、不补 0。
- **末端标注**：只在最新一个点画 5pt 实心点，深色下加一圈 30% 光环（“航迹末端”），旁边用 `.annotation(position: .trailing)` 写当前值。全图不标峰值，也不逐柱标值。
- **阈值**：配额、RPM 上限用 `RuleMark`，`stroke` 色 1pt 虚线，右端标“上限 60”。

### 7.3 选中态

- `chartXSelection(value:)` 让整个绘图区都可选。
- 选中时：画一条 1pt `text2` 竖线（`RuleMark`）；各系列交点画 6pt 圆点，外描 2pt `surface` 色环，让点从线上“浮”起来。
- 读数卡放在 `.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled))`，用 `surfaceRaised` 实底和同心圆角，**不用玻璃**；内容为时间加各系列读数（圆体等宽）。
- 选中变化时触发 `.sensoryFeedback(.selection, trigger:)`。
- 关键数字不依赖交互：标题已写结论，末端已标当前值（HIG：“don't require interaction to reveal critical information”）。

```swift
// 示意：营收趋势（iOS 17+ API；Theme 见第 10 节）
Chart {
    ForEach(points) { p in
        AreaMark(x: .value("时间", p.hour, unit: .hour), y: .value("实际", p.actual))
            .foregroundStyle(LinearGradient(colors: [Theme.costColor(.actual).opacity(0.22), .clear],
                                            startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)
        LineMark(x: .value("时间", p.hour, unit: .hour), y: .value("金额", p.actual), series: .value("口径", "实际"))
            .foregroundStyle(Theme.costColor(.actual))
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        LineMark(x: .value("时间", p.hour, unit: .hour), y: .value("金额", p.cost), series: .value("口径", "成本"))
            .foregroundStyle(Theme.costColor(.cost))
            .lineStyle(Theme.strokeStyle(for: .cost))
            .interpolationMethod(.monotone)
    }
    if let selectedHour {
        RuleMark(x: .value("选中", selectedHour, unit: .hour))
            .foregroundStyle(Theme.Palette.text2)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                ReadoutCard(hour: selectedHour)   // surfaceRaised 实底 + 圆体读数
            }
    }
}
.chartXSelection(value: $selectedHour)
.chartYAxis {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.Palette.hairline)
        AxisValueLabel().font(Theme.Typo.axis).foregroundStyle(Theme.Palette.text3)
    }
}
.chartXAxis {
    AxisMarks(values: .stride(by: .hour, count: 6)) {
        AxisValueLabel(format: .dateTime.hour()).font(Theme.Typo.axis).foregroundStyle(Theme.Palette.text3)
    }
}
```

### 7.4 迷你趋势

- 用于首页 KPI 瓦片和账号详情头部，不放进列表行，以保持行简洁。
- 规格：高 28pt；`.chartXAxis(.hidden)`、`.chartYAxis(.hidden)`、`.chartLegend(.hidden)`；1.25pt 线。
- **默认 `quiet` 灰色**：迷你趋势只表达形状，不表达状态。只有当该指标本身处于异常时（例如错误率超阈值），才改用状态色。
- 末端 3pt 圆点。

### 7.5 容量与配额条

- 结构：上方是“标签（`meta` `text2`）……读数（`metaFigure`）”一行，下方是 4pt 高的胶囊轨道（`track`）加填充。
- **阈值刻度**：在 75% 和 90% 处各画一条 1pt × 8pt 的竖刻度（`stroke` 色），像仪表上的红线标记。用户不看颜色也能知道离上限还有多远。
- 填充色：<75% `quiet`；75–90% `caution`；≥90% `critical`，读数也同步变色。阈值与 Web 的用量进度条一致（≥90 红、≥75 琥珀，04 §4.1-24）。
- 上限为 0 或缺失时：不画条，读数写“1 / —”（03、05 已有裁决：缺失不补）。
- 健康分（越高越好）方向相反：≥90 `quiet` 加小字“健康”（`ok` 色）；60–89 `caution`“风险”；<60 `critical`。阈值照搬 Web（04 §4.1-18）。
- 实现：自定义 `GaugeStyle`（第 10 节 `SignalCapacityGaugeStyle`），外层用 `Gauge(value:in:label:currentValueLabel:)`，让 VoiceOver 读到“调度 RPM，58，上限 60”。

---

## 8. 动效与触觉

### 8.1 过渡与动效

| 场景 | 动效 | API | 减弱动态效果时 |
|---|---|---|---|
| 状态**刚变为**异常（L2/L3 出现） | 徽标微光从 0 渐亮到目标值（0.35s，缓出），符号 `.bounce` 一次 | `withAnimation(Theme.Motion.onset)`、`.symbolEffect(.bounce, value: signalChangeID)` | 直接显示终态 |
| 持续异常 | **常亮，不闪烁**。暗舱只在“刚刚发生”时提示一次，持续闪烁会造成疲劳 | — | — |
| 数字刷新（读数、计数） | 数字滚动 | `.contentTransition(.numericText(value:))` + `.animation(.smooth(duration: 0.45), value:)` | `.contentTransition(.opacity)` 或无动画 |
| 倒计时 | 每秒更新，数字滚动方向为递减 | `Text(timerInterval:countsDown:)` + `.contentTransition(.numericText(countsDown: true))` | 照常更新文字，不做滚动 |
| 倒计时归零 | 徽标变为“恢复中…”（`neutral` 描边），并触发一次该账号的静默刷新 | — | 同左 |
| 列表重排（“需处理优先”排序变化） | 行位移 | `.animation(.snappy(duration: 0.28), value: order)` | 无动画 |
| 符号切换（暂停 ↔ 正常） | 符号替换 | `.contentTransition(.symbolEffect(.replace))` | `.symbolEffectsRemoved()` |
| 首次加载 | **静态**占位（`.redacted(reason: .placeholder)`），不做闪光扫过；暗舱的加载也应保持安静 | — | 同左 |
| 下拉刷新 | 系统 `.refreshable`；完成后副标题从“正在更新”变为“刚刚更新” | `.navigationSubtitle` | 同左 |
| 操作回执 G2 | 自底部玻璃胶囊弹入，4s 后淡出 | `.transition(.move(edge: .bottom).combined(with: .opacity))` | 只淡入淡出 |

### 8.2 触觉映射（`sensoryFeedback`，iOS 17+）

| 事件 | 反馈 | 说明 |
|---|---|---|
| 写操作已确认成功（停止调度、充值成功、清除限流） | `.success` | — |
| 被服务器明确拒绝 | `.error` | — |
| 结果待核对、批量部分失败 | `.warning` | 与“失败”区分，提醒用户去核对 |
| 切换筛选胶囊、分段，进入或退出选择模式，图表选中 | `.selection` | — |
| 撤销 | `.impact(flexibility: .soft, intensity: 0.6)` | — |
| 开始账号测试 | `.impact(weight: .light)` | 结果再按成功或失败反馈 |
| **后台轮询发现新异常** | **无触觉** | 触觉只回应用户自己的动作；被动变化只给视觉提示 |

### 8.3 反馈形态

- **成功**：G2 玻璃回执胶囊（4s）加 `.success`。可逆操作带“撤销”。
- **失败**：在原位置显示一行 `critical` 文字说明，加 `.error`；不弹 alert。
- **结果待核对**：常驻的 `caution` 横幅（10%/22% 着色底 + 信号轨），写明“结果待核对 · 读取当前状态”，**不会自动消失**，也不用 G2（05 §4.10）。

---

## 9. 三个样屏

> 设备：iPhone 6.3 英寸（402×874pt），深色，默认字号。浅色版结构相同，只替换令牌。
> 草图符号：`▌` 信号轨；`⬣` 错误八角；`⧗` 沙漏（限流/临时）；`◐` 模型限流半圆；`‖` 暂停；`•` 正常暗点；`△` 告警铃；`⌄` 下拉；`›` 进入；`⌕` 搜索。草图只画左边框，避免中文字宽导致对不齐。
> Tab 栏（概览/账号/日志/用户 + 搜索）只作示意，实际以 IA 方案为准。

### 9.1 样屏 A：概览（有 3 项需处理时）

```
 9:41                                          
                   概览 ⌄                      [chart.xyaxis.line]   ①
                   主站 · 刚刚更新                                   
┌────────────────────────────────────────────
│ 需要处理  3                                                         ②
│▌⬣  错误        1 个账号 · Claude-Max-07          ›                 ③
│▌⧗  限流中      2 个账号 · 最早 4:37 后恢复        ›                 ④
│▌△  P1 告警     错误率过高 · 12 分钟前             ›                 ⑤
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 今日                                                               ⑥
│ 实际                        成本                                   
│ $ 1,284.50                  $ 812.10                               ⑦
│ ┄ 标准 $1,402.00            差额 $472.40                           ⑧
│ ───────────────────────────────────────
│ 请求 48.2K      Token 126.4M      错误率 0.8%                      ⑨
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 实际扣费比昨天同时 +6%                                             ⑩
│ 今日 00:00 起                                                      
│                                     ╭──●  $96                      
│          ╭─╮          ╭──╮     ╭───╯       ┄┄ $80                  ⑪
│  ────────╯ ╰──────────╯  ╰─────╯           ┄┄ $40                  
│  00        06         12         18     现在                       
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 运行                                                               ⑫
│ 健康 96  ▕████████████████████╎██▏  RPM 312   TPM 1.2M             
│ 渠道  • Claude 可用   • GPT 可用   ⧗ Gemini 性能下降  ›             ⑬
└────────────────────────────────────────────
        ╭──────────────────────────────────╮ ╭───╮
        │  概览    账号³    日志    用户    │ │ ⌕ │                     ⑭
        ╰──────────────────────────────────╯ ╰───╯
```

全部正常时，②–⑤ 合并为一行：`•  全部正常 · 82 个账号在线 · 健康 96`（`ok` 暗点 + `meta` `text2`，没有面板、没有信号轨）。首页因此几乎全是读数。

| # | 元素 | 颜色 | 字体 | 尺寸 / 间距 | 数据来源 |
|---|---|---|---|---|---|
| ① | 导航：标题菜单切站，副标题显示站点与新鲜度；右侧“统计分析” | 系统玻璃；`brand` tint | 系统 | `.inline` 标题 | 本地 profile |
| ② | 面板标题“需要处理 3” | `text2`，数字 `text1` | `sectionLabel` | 面板内边距 `l` | ③–⑤ 计数之和 |
| ③ | 错误行：L3 | 轨 `critical`；八角 `critical`；字 `text1`；对象名 `text2` | `rowTitle` / `meta` | 行高 44pt | `dashboard/stats.error_accounts`（已接入接口，字段需确认已解码） |
| ④ | 限流行：L2，“最早 4:37 后恢复”实时倒计时 | 轨 `caution`；倒计时 `caution` | `rowTitle` / `metaFigure` | 同上 | `ops/account-availability` 的剩余秒数（**需新接入**，02 §1.1；受 ops 开关控制） |
| ⑤ | 告警行：P1 → L2 | 轨 `caution`（P0 为 `critical` L3） | 同上 | 同上 | `ops/alert-events?status=firing`（**需新接入**，02 §3.8） |
| ⑥ | 今日面板 | `surface` + 0.5pt `hairline` | `sectionLabel` | 圆角 22，与③所在面板间距 `m` | — |
| ⑦ | 实际 / 成本读数，两列 | 数字 `text1`；`$` `text2`；标签 `text2` | `readoutHero` / `readout` / `readoutUnit` | 两列 `Grid`，列间 `xl` | `dashboard/stats` + 现有费用快照（已接入） |
| ⑧ | 标准、差额 | 虚线短划 `standard`；数字 `text1` | `meta` / `metaFigure` | 读数下方 `xs` | 已接入（差额本地计算） |
| ⑨ | 请求、Token、错误率 | `text1`；错误率超阈值时变 `caution` | `metaFigure` | 三等分，上方 0.5pt 分隔线 | 已接入 |
| ⑩ | 图表标题即结论 | `text1`；副标题 `text3` | `rowTitle` / `timestamp` | — | `dashboard/trend` 小时序列，同比在本地计算（已接入） |
| ⑪ | 实际扣费曲线 | 线 `actual` 2pt；面积 22%；末端光点；右侧刻度 `text3` | `axis` | 绘图区高 160pt | 同上 |
| ⑫ | 运行面板：健康分条，带 75%/90% 刻度 | ≥90 `quiet`；数字 `text1` | `metaFigure` | 条高 4pt | `ops/dashboard/overview.health_score`（**已部分接入**，需补解码） |
| ⑬ | 渠道健康 | 可用 `ok` 暗点；性能下降 `caution` | `meta` | 横排，超出时横滑 | `channel-monitor-v2/overview`（**需新接入**，受开关控制） |
| ⑭ | 系统 Tab 栏 | 系统玻璃；选中 `brand`；徽标系统红 | 系统 | — | 需处理账号数 |

### 9.2 样屏 B：账号列表（含错误、限流倒计时、暂停）

```
 9:41
 [选择]               账号 ⌄                  [arrow.up.arrow.down] [⋯]   ①
                      主站 · 82 个 · 刚刚                                 
 (需处理 3)  (全部 82)  (平台 ⌄)  (分组 ⌄)  (类型 ⌄)                         ②
 需要处理 · 3                                                            ③
▌⬣ Claude-Max-07                          [⬣ 错误]                       ④
▌  Anthropic · 高级分组 · 3分钟前                                        
▌  认证失败：refresh token 已失效                                         ⑤
 ─────────────────────────────────────────
▌⧗ GPT-Pro-12                    [⧗ 限流中 4:37]                         ⑥
▌  OpenAI · 标准分组 · 并发 0 / 4                                        
 ─────────────────────────────────────────
▌◐ Gemini-Flash-03                 [◐ 模型限流 2]                        ⑦
▌  Gemini · 标准分组 · 1分钟前                                           
 其余 · 79                                                               ⑧
 ‖ Kimi-备用-02                         (‖ 暂停)                          ⑨
   Kimi · 备用分组                           今日 0                       
 ─────────────────────────────────────────
 • DeepSeek-01                         1,204 请求                         ⑩
   DeepSeek · 标准分组                     $12.40                         
 ─────────────────────────────────────────
 • GPT-Pro-02                            986 请求                         
   OpenAI · 标准分组                        $9.87                         
 ─────────────────────────────────────────
 • Claude-Max-03                         845 请求                         
   Anthropic · 高级分组                     $8.02                         
        ╭──────────────────────────────────╮ ╭───╮
        │  概览    账号³    日志    用户    │ │ ⌕ │
        ╰──────────────────────────────────╯ ╰───╯
```

| # | 元素 | 颜色 | 字体 | 尺寸 / 间距 | 实现 / 数据 |
|---|---|---|---|---|---|
| ① | 导航：左“选择”，右“排序”“更多（显示偏好、自动刷新）” | 系统玻璃 | 系统 | 工具栏 ≤ 3 组 | `ToolbarItem`、`ToolbarSpacer` |
| ② | 筛选胶囊条：首个“需处理 3”默认选中 | 选中：`brand` 着色底 + `brand` 字；未选：`surfaceRaised` + `text1` | `meta`，计数用 `metaFigure` | 高 36pt，间距 `s` | `.safeAreaBar(edge: .top)` 加横向 `ScrollView`；`.scrollEdgeEffectStyle(.hard, for: .top)` |
| ③ | 分组标题“需要处理 · 3”（吸顶） | `text2`，背景 `canvas` | `sectionLabel` | 上 `m`，下 `xs` | `List(.plain)` 的 `Section` header |
| ④ | 错误行：L3，八角 + 实心红徽标 | 轨 `critical` 3pt；徽标实心 `#FF6259` + `#1A0605` 字 + 半径 8 微光；标题 `text1`；元数据 `text2` | `rowTitle` / `meta` / `badge` | 行高 ≈86pt；内边距 10/16 | `status == error`；`.listRowBackground(SignalRowBackground)` |
| ⑤ | 错误摘要（1 行，尾部截断） | `text1`（不用红字，红色已由轨和徽标承担） | `meta` | `.lineLimit(1)` | `errorMessage` 经 `safeMessage` 脱敏（已解码，界面未展示） |
| ⑥ | 限流行：L2，徽标内倒计时每秒刷新 | 轨 `caution`；着色底 16% + `caution` 字 + 半径 5 微光 | `badge`（等宽） | 行高 64pt | `rate_limit_reset_at`（DTO 已下发，**需在 `UpstreamAccount` 补解码**，02 §3.1C） |
| ⑦ | 模型限流行：L2 紫 | 轨 `model`；徽标 `model` | 同上 | 同上 | `extra.model_rate_limits`（需补解码） |
| ⑧ | 分组标题“其余 · 79” | `text2` | `sectionLabel` | — | — |
| ⑨ | 暂停行：L1，没有信号轨 | 暂停符号 `neutral`；徽标 1pt `neutral` 描边、无填充；标题 `text1`（不置灰，暂停是有意为之，不是失效） | `badge` | 行高 64pt | `schedulable == false` |
| ⑩ | 正常行：L0，6pt 暗点，右侧今日请求与实际 | 点 `ok` 暗点；数值 `text1`；金额 `text2` | `rowFigure` / `metaFigure` | 右列右对齐等宽 | `today-stats/batch`（已接入） |

**行内交互**：
- 前滑（`swipeActions(edge: .leading, allowsFullSwipe: false)`）：“停止调度 / 启用调度”，按钮着品牌青。可逆操作直接执行，然后弹出 G2 回执“已停止调度 · 撤销”。
- 后滑：“测试”、“更多”。
- 长按：`contextMenu`，前两项与滑动操作一致，“清除限流”“恢复状态”按状态显示。
- 选择模式：行首出现系统勾选圈，Tab 栏隐藏，底部浮出 **G1 玻璃操作条**。

**大字号（AX1 及以上）**：徽标从行尾移到标题下方单独一行；右侧数值移到元数据行之后；错误摘要放宽到 2 行。用 `ViewThatFits` 加 `AnyLayout` 切换。

### 9.3 样屏 C：账号详情（限流中，并有模型级限流）

```
 9:41
 [‹ 账号]              GPT-Pro-12                         [⋯]         ①
                       OpenAI · API Key                                 
┌────────────────────────────────────────────  信号舱
│ ⧗ 限流中                                                            ②
│ 4:37                                                                ③
│ 后自动恢复 · 预计 16:42 · 16:37 起限流                               ④
│ ┌──────────────────────────────────────                             
│ │ ◐ 模型限流 2                                                      ⑤
│ │   gpt-5-pro                          至 17:10                     
│ │   o4-mini                            至 16:55                     
│ └──────────────────────────────────────                             
│ [↺ 清除限流]      [∿ 测试]      [‖ 停止调度]                         ⑥
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 容量                                                                ⑦
│ 并发                                            1 / 4               
│ ▕██████▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁╎▁▁▁▁╎▁▁▏                                     
│ 调度 RPM（自然分钟）                           58 / 60              ⑧
│ ▕██████████████████████╎████╎██▏                                     
│ 日配额                                $3.45 / $20.00                
│ ▕████▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁╎▁▁▁▁╎▁▁▏                                     
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 今日                                                                ⑨
│ 请求 1,204                 Token 3.2M                               
│ ● 实际 $12.40   ● 成本 $7.85   ┄ 标准 $14.02                         ⑩
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 错误记录                           3 条未处理    ›                   ⑪
│ 请求记录                                         ›                   
│ 统计分析                                         ›                   
└────────────────────────────────────────────
┌────────────────────────────────────────────
│ 平台       OpenAI            类型     API Key                        ⑫
│ 分组       标准分组          优先级   1                               
│ 账号倍率   1.0×              代理     hk-02                           
│ 过期       —                 备注     —                               
└────────────────────────────────────────────
```

首屏（到⑧为止）回答了三个问题：现在怎么了、什么时候好、我能做什么。

| # | 元素 | 颜色 | 字体 | 尺寸 / 间距 | 实现 / 数据 |
|---|---|---|---|---|---|
| ① | 导航：标题为账号名，副标题为平台 · 类型（中文显示名）；“⋯”菜单放刷新凭据、编辑、在 Web 中打开 | 系统玻璃 | 系统 | — | `.navigationSubtitle`；平台和类型显示名来自统一词典 |
| ② | 信号舱面板首行：状态符号 + 状态词 | `caution` | `rowTitle` | 面板内边距 `l`；面板 `surface` + 0.5pt `hairline` | `Theme.style(for: .rateLimited(...))` |
| ③ | 倒计时大读数 | `caution`；深色下文字不加光（光只在徽标底上） | `readoutHero`（深色 Medium） | 上 `xs` | `Text(timerInterval:countsDown:)`；VoiceOver：“4 分钟后自动恢复” |
| ④ | 恢复时间与起始时间 | `text2`，时间数字 `text1` | `meta` / `metaFigure` | — | `rate_limit_reset_at`、`rate_limited_at`（DTO 已有，需补解码） |
| ⑤ | 模型限流子块：同心瓦片 | `surfaceRaised`；标题 `model`；模型名 `text1`；时间 `text2` | `meta` / `identifier`（模型 ID）/ `metaFigure` | `ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)` | `extra.model_rate_limits`（需补解码） |
| ⑥ | 操作行：主操作“清除限流”实心品牌青，其余描边 | 主：`brand` 底 + `onBrand` 字；次：`.bordered` 着 `brand` | 按钮默认（`body` medium） | 等宽三列，高 44pt，间距 `s` | 清除限流：`POST accounts/:id/clear-rate-limit`（**需新接入**，02 §1.2）；测试：SSE（已接入）；停止调度（已接入） |
| ⑦ | 容量面板 | 标签 `text2`；读数 `text1` | `meta` / `metaFigure` | 项间距 `m`；条高 4pt | `SignalCapacityGaugeStyle` |
| ⑧ | 调度 RPM 58/60 = 97% | 填充与读数均为 `critical`；刻度 `stroke` | 同上 | — | `scheduling_rpm`、`base_rpm`（已接入）。只显示这一个 RPM，不再与“在用 RPM”重复（01 D02） |
| ⑨ | 今日面板 | 数字 `text1` | `metaFigure` | 两列 `Grid` | `today-stats`（已接入） |
| ⑩ | 三口径 | 色点 `actual` / `cost`，“标准”用虚线短划；数字 `text1` | `meta` / `metaFigure` | 色点 6pt，点与字间距 `xs` | 已接入 |
| ⑪ | 关联导航，计数在右 | 标题 `text1`；“3 条未处理”在有未处理时用 `caution` | `rowTitle` / `metaFigure` | 行高 44pt | 计数来自 `ops/request-errors?account_id=&resolved=false`（列表已接入；需确认能取到总数）；点击后在同一栈内 push，默认停在“错误”页签 |
| ⑫ | 属性网格：两列，标签在上、值在下（大字号时变单列） | 标签 `text3`；值 `text1`；缺失“—” `text3` | `timestamp` / `meta` | `Grid`，列间 `xl`，行间 `m` | 已解码字段；枚举一律映射为中文 |

**错误状态的变体**：信号舱换成 L3。首行为实心红“⬣ 错误”；③ 换成错误摘要（`rowTitle` `text1`，最多 3 行）加时间；操作为“清除错误”（主，品牌青，`POST :id/clear-error`，需新接入）、“测试”、“刷新凭据”。正常账号的信号舱缩成一行：“• 正常 · 参与调度”。

---

## 10. SwiftUI 设计令牌代码

> 目标：Swift 6（`SWIFT_STRICT_CONCURRENCY = complete`）、iOS 26 SDK 可直接编译。全部用计算属性或 `Sendable` 常量，避免 Swift 6 的全局可变状态报错。
> 生产环境也可以把颜色迁到 Asset Catalog 的颜色集（勾选 Appearances: Any, Dark 和 High Contrast，共四格）。本代码便于原型阶段集中调参，两者取值相同。如果在 Xcode 27 下 `UIColor(dynamicProvider:)` 闭包里读取 `UITraitCollection` 触发了并发隔离诊断（【推断】未在 Mac 上编译验证），直接改用颜色集即可，上层 API 不变。
> `AccountSignal` 由 Sub2Core 根据 `status / schedulable / rate_limit_reset_at / overload_until / temp_unschedulable_until / quota_* / extra.model_rate_limits` 推导（这些字段需要先补解码），本文件只负责呈现。

```swift
//  Theme.swift — 「暗舱」设计令牌（iOS 26+，Swift 6）
import SwiftUI
import UIKit

// MARK: - 四态动态色

extension UIColor {
    /// 0xRRGGBB → sRGB UIColor
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// 一个颜色令牌在 浅色 / 深色 / 浅色增强对比 / 深色增强对比 下的取值。
struct ColorToken: Sendable, Hashable {
    let light: UInt32
    let dark: UInt32
    let lightHC: UInt32
    let darkHC: UInt32

    init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.light = light
        self.dark = dark
        self.lightHC = lightHC ?? light
        self.darkHC = darkHC ?? dark
    }

    func hex(for traits: UITraitCollection) -> UInt32 {
        let isDark = traits.userInterfaceStyle == .dark
        let isHigh = traits.accessibilityContrast == .high
        switch (isDark, isHigh) {
        case (false, false): return light
        case (false, true): return lightHC
        case (true, false): return dark
        case (true, true): return darkHC
        }
    }

    var color: Color {
        let token = self
        return Color(uiColor: UIColor { traits in UIColor(rgb: token.hex(for: traits)) })
    }

    /// 同色相着色底：按模式取不同不透明度，叠在 surface 上。
    func tint(_ alpha: TintAlpha) -> Color {
        let token = self
        return Color(uiColor: UIColor { traits in
            UIColor(rgb: token.hex(for: traits), alpha: alpha.value(for: traits))
        })
    }
}

struct TintAlpha: Sendable, Hashable {
    let light: CGFloat
    let dark: CGFloat
    let lightHC: CGFloat
    let darkHC: CGFloat

    static let badge = TintAlpha(light: 0.12, dark: 0.16, lightHC: 0.14, darkHC: 0.20)
    static let banner = TintAlpha(light: 0.10, dark: 0.22, lightHC: 0.12, darkHC: 0.24)
    static let chartArea = TintAlpha(light: 0.12, dark: 0.22, lightHC: 0.08, darkHC: 0.14)

    func value(for traits: UITraitCollection) -> CGFloat {
        let isDark = traits.userInterfaceStyle == .dark
        let isHigh = traits.accessibilityContrast == .high
        switch (isDark, isHigh) {
        case (false, false): return light
        case (false, true): return lightHC
        case (true, false): return dark
        case (true, true): return darkHC
        }
    }
}

// MARK: - 语义类型

/// 状态色调（含义与简报一致）。brand 只表示“可操作”，quiet 表示“静默读数”。
enum SignalTone: String, Sendable, CaseIterable {
    case ok, caution, critical, neutral, model, brand, quiet
}

/// 同一色调在不同用途下的取值：文字（≥4.5:1）、图形（≥3:1）、着色底上的文字。
enum ToneRole: Sendable {
    case text, graphic, ink
}

/// 强调四级：熄灭 / 描边 / 着色 / 实心。
enum SignalEmphasis: Sendable {
    case quiet, outline, tint, solid
}

/// 成本三口径。
enum CostTier: Sendable, CaseIterable {
    case actual, cost, standard

    var shortLabel: String {
        switch self {
        case .actual: "实际"
        case .cost: "成本"
        case .standard: "标准"
        }
    }

    var longLabel: String {
        switch self {
        case .actual: "实际扣费"
        case .cost: "账号成本"
        case .standard: "标准费用"
        }
    }
}

/// 账号运行信号（由 Sub2Core 推导）。
enum AccountSignal: Sendable, Hashable {
    case error
    case overloaded(until: Date?)
    case rateLimited(until: Date?)
    case tempUnschedulable(until: Date?)
    case quotaExceeded
    case modelLimited(count: Int)
    case inactive
    case paused
    case unknown
    case normal

    /// 越小越先处理：列表“需处理优先”排序与主徽标选择共用。
    var severity: Int {
        switch self {
        case .error: 0
        case .overloaded: 1
        case .rateLimited: 2
        case .tempUnschedulable: 3
        case .quotaExceeded: 4
        case .modelLimited: 5
        case .inactive: 6
        case .paused: 7
        case .unknown: 8
        case .normal: 9
        }
    }

    var needsAttention: Bool { severity <= 5 }
}

/// 写操作结果（与现有写入安全语义对应）。
enum WriteOutcome: Sendable {
    case confirmed, rejected, pendingVerification, partial
}

struct SignalStyle: Sendable, Hashable {
    let tone: SignalTone
    let emphasis: SignalEmphasis
    let symbol: String
    let label: String
    let deadline: Date?

    var showsRail: Bool { emphasis == .tint || emphasis == .solid }
    var glows: Bool { showsRail }
}

// MARK: - Theme

enum Theme {

    // MARK: 色板
    enum Palette {
        static let canvasToken = ColorToken(light: 0xEEF1F5, dark: 0x080B11, lightHC: 0xE6EAF0, darkHC: 0x030407)
        static let surfaceToken = ColorToken(light: 0xFFFFFF, dark: 0x0F141C, lightHC: 0xFFFFFF, darkHC: 0x0B0F15)
        static let surfaceRaisedToken = ColorToken(light: 0xF6F8FA, dark: 0x161D27, lightHC: 0xF3F5F8, darkHC: 0x121821)
        static let trackToken = ColorToken(light: 0xE9EDF2, dark: 0x1D2532, lightHC: 0xD3DAE3, darkHC: 0x232D3B)
        static let hairlineToken = ColorToken(light: 0xDDE2E9, dark: 0x232C39, lightHC: 0x848F9E, darkHC: 0x56657B)
        static let strokeToken = ColorToken(light: 0xB9C2CE, dark: 0x344155, lightHC: 0x6B7685, darkHC: 0x6B7B92)
        static let text1Token = ColorToken(light: 0x0B1220, dark: 0xE6ECF3, lightHC: 0x000000, darkHC: 0xF5F8FC)
        static let text2Token = ColorToken(light: 0x4B5565, dark: 0x9DA9B9, lightHC: 0x323B49, darkHC: 0xBCC6D3)
        static let text3Token = ColorToken(light: 0x5E697B, dark: 0x7A8699, lightHC: 0x455061, darkHC: 0x9DA9B9)
        static let brandToken = ColorToken(light: 0x0A6FA3, dark: 0x47C8F5, lightHC: 0x06567F, darkHC: 0x6CD5FA)
        static let onBrandToken = ColorToken(light: 0xFFFFFF, dark: 0x06121A, lightHC: 0xFFFFFF, darkHC: 0x000000)
        static let onCriticalToken = ColorToken(light: 0xFFFFFF, dark: 0x1A0605, lightHC: 0xFFFFFF, darkHC: 0x000000)

        static var canvas: Color { canvasToken.color }
        static var surface: Color { surfaceToken.color }
        static var surfaceRaised: Color { surfaceRaisedToken.color }
        static var track: Color { trackToken.color }
        static var hairline: Color { hairlineToken.color }
        static var stroke: Color { strokeToken.color }
        static var text1: Color { text1Token.color }
        static var text2: Color { text2Token.color }
        static var text3: Color { text3Token.color }
        static var brand: Color { brandToken.color }
        static var onBrand: Color { onBrandToken.color }
        static var onCritical: Color { onCriticalToken.color }
    }

    // MARK: 状态色调
    static func token(_ tone: SignalTone, _ role: ToneRole = .text) -> ColorToken {
        switch (tone, role) {
        case (.ok, .text): ColorToken(light: 0x0F7A45, dark: 0x3FD47F, lightHC: 0x0A6236, darkHC: 0x5BE396)
        case (.ok, .graphic): ColorToken(light: 0x1A9150, dark: 0x2E9E63, lightHC: 0x0A6236, darkHC: 0x3FD47F)
        case (.ok, .ink): ColorToken(light: 0x0B6638, dark: 0x3FD47F, lightHC: 0x0A6236, darkHC: 0x5BE396)

        case (.caution, .text): ColorToken(light: 0x925700, dark: 0xFFB224, lightHC: 0x734300, darkHC: 0xFFC24D)
        case (.caution, .graphic): ColorToken(light: 0xB87900, dark: 0xFFB224, lightHC: 0x734300, darkHC: 0xFFC24D)
        case (.caution, .ink): ColorToken(light: 0x7A4800, dark: 0xFFB224, lightHC: 0x734300, darkHC: 0xFFC24D)

        case (.critical, .text): ColorToken(light: 0xC42B22, dark: 0xFF6259, lightHC: 0xA11B14, darkHC: 0xFF7D75)
        case (.critical, .graphic): ColorToken(light: 0xDC3A30, dark: 0xFF6259, lightHC: 0xA11B14, darkHC: 0xFF7D75)
        case (.critical, .ink): ColorToken(light: 0xA6211A, dark: 0xFF6259, lightHC: 0xA11B14, darkHC: 0xFF7D75)

        case (.neutral, .text): ColorToken(light: 0x5E6979, dark: 0x8B97A8, lightHC: 0x465060, darkHC: 0xA7B2C1)
        case (.neutral, .graphic): ColorToken(light: 0x76818F, dark: 0x8B97A8, lightHC: 0x465060, darkHC: 0xA7B2C1)
        case (.neutral, .ink): ColorToken(light: 0x4B5565, dark: 0x8B97A8, lightHC: 0x465060, darkHC: 0xA7B2C1)

        case (.model, .text): ColorToken(light: 0x7B3BC9, dark: 0xC08AFF, lightHC: 0x5F27A8, darkHC: 0xD0ADFF)
        case (.model, .graphic): ColorToken(light: 0x9156E0, dark: 0xC08AFF, lightHC: 0x5F27A8, darkHC: 0xD0ADFF)
        case (.model, .ink): ColorToken(light: 0x6630AE, dark: 0xC08AFF, lightHC: 0x5F27A8, darkHC: 0xD0ADFF)

        case (.brand, .text): Palette.brandToken
        case (.brand, .graphic): ColorToken(light: 0x1784BA, dark: 0x47C8F5, lightHC: 0x06567F, darkHC: 0x6CD5FA)
        case (.brand, .ink): ColorToken(light: 0x075C88, dark: 0x47C8F5, lightHC: 0x06567F, darkHC: 0x6CD5FA)

        case (.quiet, .graphic): ColorToken(light: 0x76818F, dark: 0x6E7A8C, lightHC: 0x4F5A6A, darkHC: 0x8B97A8)
        case (.quiet, .text), (.quiet, .ink): Palette.text2Token
        }
    }

    static func color(_ tone: SignalTone, _ role: ToneRole = .text) -> Color {
        token(tone, role).color
    }

    /// 徽标着色底。
    static func fill(_ tone: SignalTone) -> Color {
        token(tone, .text).tint(.badge)
    }

    /// 横幅着色底（结果待核对、告警横幅）。
    static func bannerFill(_ tone: SignalTone) -> Color {
        token(tone, .text).tint(.banner)
    }

    // MARK: 成本三口径
    static func costToken(_ tier: CostTier) -> ColorToken {
        switch tier {
        case .actual: ColorToken(light: 0x0A7660, dark: 0x3CCBA6, lightHC: 0x075F4D, darkHC: 0x5ADBB8)
        case .cost: ColorToken(light: 0xB04C14, dark: 0xF08B4F, lightHC: 0x8F3B0D, darkHC: 0xF7A06B)
        case .standard: ColorToken(light: 0x5E6979, dark: 0x8B97A8, lightHC: 0x465060, darkHC: 0xA7B2C1)
        }
    }

    static func costColor(_ tier: CostTier) -> Color { costToken(tier).color }

    static func strokeStyle(for tier: CostTier) -> StrokeStyle {
        switch tier {
        case .actual: StrokeStyle(lineWidth: Metrics.lineWidthPrimary, lineCap: .round, lineJoin: .round)
        case .cost: StrokeStyle(lineWidth: Metrics.lineWidthSecondary, lineCap: .round, lineJoin: .round)
        case .standard: StrokeStyle(lineWidth: Metrics.lineWidthSecondary, lineCap: .round, lineJoin: .round, dash: [4, 3])
        }
    }

    // MARK: 状态映射
    static func style(for signal: AccountSignal) -> SignalStyle {
        switch signal {
        case .error:
            SignalStyle(tone: .critical, emphasis: .solid, symbol: "exclamationmark.octagon.fill", label: "错误", deadline: nil)
        case .overloaded(let until):
            SignalStyle(tone: .critical, emphasis: .tint, symbol: "flame.fill", label: "过载中", deadline: until)
        case .rateLimited(let until):
            SignalStyle(tone: .caution, emphasis: .tint, symbol: "hourglass", label: "限流中", deadline: until)
        case .tempUnschedulable(let until):
            SignalStyle(tone: .caution, emphasis: .tint, symbol: "clock.badge.exclamationmark", label: "临时不可调度", deadline: until)
        case .quotaExceeded:
            SignalStyle(tone: .caution, emphasis: .tint, symbol: "gauge.with.dots.needle.100percent", label: "配额超限", deadline: nil)
        case .modelLimited(let count):
            SignalStyle(tone: .model, emphasis: .tint, symbol: "circle.lefthalf.filled", label: count > 0 ? "模型限流 \(count)" : "模型限流", deadline: nil)
        case .inactive:
            SignalStyle(tone: .neutral, emphasis: .outline, symbol: "minus.circle", label: "停用", deadline: nil)
        case .paused:
            SignalStyle(tone: .neutral, emphasis: .outline, symbol: "pause.circle", label: "暂停", deadline: nil)
        case .unknown:
            SignalStyle(tone: .neutral, emphasis: .outline, symbol: "questionmark.circle", label: "未知", deadline: nil)
        case .normal:
            SignalStyle(tone: .ok, emphasis: .quiet, symbol: "circle.fill", label: "正常", deadline: nil)
        }
    }

    /// 多个信号并存时取最需要处理的一个作为主徽标，其余作为附加徽标。
    static func primary(of signals: [AccountSignal]) -> AccountSignal {
        signals.min { $0.severity < $1.severity } ?? .unknown
    }

    /// 容量（越高越紧张）：<75% 静默，75–90% 琥珀，≥90% 红。
    static func capacityTone(fraction: Double) -> SignalTone {
        guard fraction.isFinite else { return .neutral }
        if fraction >= 0.90 { return .critical }
        if fraction >= 0.75 { return .caution }
        return .quiet
    }

    /// 健康分（越高越好，阈值照搬 Web）：≥90 静默，60–89 琥珀，<60 红。
    static func healthTone(score: Double) -> SignalTone {
        guard score.isFinite else { return .neutral }
        if score >= 90 { return .quiet }
        if score >= 60 { return .caution }
        return .critical
    }

    // MARK: 字体（全部基于 Text Style，随 Dynamic Type 缩放）
    enum Typo {
        static func readoutHero(_ scheme: ColorScheme) -> Font {
            .system(.largeTitle, design: .rounded, weight: scheme == .dark ? .medium : .semibold).monospacedDigit()
        }
        static func readout(_ scheme: ColorScheme) -> Font {
            .system(.title2, design: .rounded, weight: scheme == .dark ? .medium : .semibold).monospacedDigit()
        }
        static var readoutUnit: Font { .system(.title3, design: .rounded, weight: .regular) }
        static var screenTitle: Font { .title3.weight(.semibold) }
        static var sectionLabel: Font { .footnote.weight(.semibold) }
        static var rowTitle: Font { .body.weight(.medium) }
        static var rowFigure: Font { .body.weight(.medium).monospacedDigit() }
        static var meta: Font { .subheadline }
        static var metaFigure: Font { .subheadline.monospacedDigit() }
        static var badge: Font { .footnote.weight(.semibold).monospacedDigit() }
        static var timestamp: Font { .footnote.monospacedDigit() }
        static var axis: Font { .caption.monospacedDigit() }
        static var identifier: Font { .system(.footnote, design: .monospaced) }
        static var streamOutput: Font { .system(.footnote, design: .monospaced) }
    }

    // MARK: 间距（4pt 网格）
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let section: CGFloat = 32
    }

    // MARK: 圆角
    enum Radius {
        static let panel: CGFloat = 22
        static let field: CGFloat = 12
        static var panelShape: RoundedRectangle { RoundedRectangle(cornerRadius: panel, style: .continuous) }
        static var fieldShape: RoundedRectangle { RoundedRectangle(cornerRadius: field, style: .continuous) }
        /// 面板内瓦片：与面板同心，最小 12pt（iOS 26）。
        static var tileShape: ConcentricRectangle { ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true) }
    }

    // MARK: 尺寸
    enum Metrics {
        static let railWidth: CGFloat = 3
        static let gaugeHeight: CGFloat = 4
        static let statusDot: CGFloat = 6
        static let costDot: CGFloat = 6
        static let minTapTarget: CGFloat = 44
        static let chipHeight: CGFloat = 36
        static let sparklineHeight: CGFloat = 28
        static let lineWidthPrimary: CGFloat = 2
        static let lineWidthSecondary: CGFloat = 1.5
        static let gridLineWidth: CGFloat = 0.5
        static var rowInsets: EdgeInsets { EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16) }
        static var logRowInsets: EdgeInsets { EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16) }
    }

    // MARK: 微光（仅深色、标准对比度）
    enum Glow {
        static func radius(for emphasis: SignalEmphasis) -> CGFloat {
            switch emphasis {
            case .solid: 8
            case .tint: 5
            case .outline, .quiet: 0
            }
        }
        static func opacity(for emphasis: SignalEmphasis) -> Double {
            switch emphasis {
            case .solid: 0.55
            case .tint: 0.35
            case .outline, .quiet: 0
            }
        }
    }

    // MARK: 动效
    enum Motion {
        static func onset(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.35) }
        static func readout(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }
        static func reorder(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy(duration: 0.28) }
    }

    // MARK: 触觉
    enum Haptics {
        static func feedback(for outcome: WriteOutcome) -> SensoryFeedback {
            switch outcome {
            case .confirmed: .success
            case .rejected: .error
            case .pendingVerification, .partial: .warning
            }
        }
        static var selection: SensoryFeedback { .selection }
        static var undo: SensoryFeedback { .impact(flexibility: .soft, intensity: 0.6) }
        static var testStarted: SensoryFeedback { .impact(weight: .light) }
    }
}

// MARK: - 组件：信号徽标

struct SignalBadge: View {
    let style: SignalStyle

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = Theme.Metrics.statusDot

    var body: some View {
        if style.emphasis == .quiet && !differentiateWithoutColor {
            Circle()
                .fill(Theme.color(style.tone, .graphic))
                .frame(width: dotSize, height: dotSize)
                .accessibilityLabel(style.label)
        } else {
            content
                .font(Theme.Typo.badge)
                .foregroundStyle(foreground)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xxs + 1)
                .background { capsule }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: style.symbol)
                .imageScale(.small)
            Text(style.label)
            if let range = countdownRange {
                Text(timerInterval: range, countsDown: true)
            }
        }
        .lineLimit(1)
    }

    /// 只在截止时间仍在未来时显示倒计时（先取一次 now，避免区间下界大于上界）。
    private var countdownRange: ClosedRange<Date>? {
        let now = Date.now
        guard let deadline = style.deadline, deadline > now else { return nil }
        return now...deadline
    }

    private var foreground: Color {
        style.emphasis == .solid ? Theme.Palette.onCritical : Theme.color(style.tone, .ink)
    }

    @ViewBuilder private var capsule: some View {
        switch style.emphasis {
        case .solid:
            Capsule()
                .fill(Theme.color(style.tone, .text))
                .shadow(color: glowColor, radius: glowRadius)
        case .tint:
            Capsule()
                .fill(Theme.fill(style.tone))
                .shadow(color: glowColor, radius: glowRadius)
        case .outline, .quiet:
            Capsule()
                .strokeBorder(Theme.color(style.tone, .graphic), lineWidth: contrast == .increased ? 1.5 : 1)
        }
    }

    private var glowEnabled: Bool { scheme == .dark && contrast == .standard && style.glows }
    private var glowColor: Color {
        glowEnabled ? Theme.color(style.tone, .graphic).opacity(Theme.Glow.opacity(for: style.emphasis)) : .clear
    }
    private var glowRadius: CGFloat { glowEnabled ? Theme.Glow.radius(for: style.emphasis) : 0 }

    private var accessibilityText: Text {
        if let range = countdownRange {
            return Text("\(style.label)，\(range.upperBound, format: .relative(presentation: .named))恢复")
        }
        return Text(style.label)
    }
}

// MARK: - 组件：列表行背景（含信号轨）

/// 用法：`.listRowBackground(SignalRowBackground(style: style))`
struct SignalRowBackground: View {
    let style: SignalStyle?

    var body: some View {
        Theme.Palette.surface
            .overlay(alignment: .leading) {
                if let style, style.showsRail {
                    Rectangle()
                        .fill(Theme.color(style.tone, .graphic))
                        .frame(width: Theme.Metrics.railWidth)
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: - 组件：面板表面

struct PanelSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: Theme.Radius.panelShape)
            .overlay {
                if contrast == .increased {
                    Theme.Radius.panelShape.strokeBorder(Theme.Palette.stroke, lineWidth: 1)
                } else if scheme == .dark {
                    Theme.Radius.panelShape.strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
                }
            }
            .containerShape(Theme.Radius.panelShape)
    }
}

extension View {
    func panelSurface() -> some View { modifier(PanelSurface()) }
}

// MARK: - 组件：容量条样式（75% / 90% 阈值刻度）

struct SignalCapacityGaugeStyle: GaugeStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.value, 0), 1)
        let tone = Theme.capacityTone(fraction: fraction)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                configuration.label
                    .font(Theme.Typo.meta)
                    .foregroundStyle(Theme.Palette.text2)
                Spacer(minLength: Theme.Space.s)
                configuration.currentValueLabel
                    .font(Theme.Typo.metaFigure)
                    .foregroundStyle(tone == .quiet ? Theme.Palette.text1 : Theme.color(tone, .text))
            }
            CapacityTrack(fraction: fraction, tone: tone)
                .frame(height: Theme.Metrics.gaugeHeight)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CapacityTrack: View {
    let fraction: Double
    let tone: SignalTone

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                Capsule()
                    .fill(Theme.color(tone, .graphic))
                    .frame(width: fraction > 0 ? max(width * fraction, Theme.Metrics.gaugeHeight) : 0)
                ForEach([0.75, 0.90], id: \.self) { mark in
                    Rectangle()
                        .fill(Theme.Palette.stroke)
                        .frame(width: 1, height: Theme.Metrics.gaugeHeight + 4)
                        .offset(x: width * mark)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 预览

#Preview("暗舱 · 信号") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SignalBadge(style: Theme.style(for: .error))
                SignalBadge(style: Theme.style(for: .rateLimited(until: Date.now.addingTimeInterval(277))))
                SignalBadge(style: Theme.style(for: .modelLimited(count: 2)))
                SignalBadge(style: Theme.style(for: .paused))
                SignalBadge(style: Theme.style(for: .normal))
            }
            .panelSurface()

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Gauge(value: 1, in: 0...4) { Text("并发") } currentValueLabel: { Text("1 / 4") }
                Gauge(value: 58, in: 0...60) { Text("调度 RPM（自然分钟）") } currentValueLabel: { Text("58 / 60") }
            }
            .gaugeStyle(SignalCapacityGaugeStyle())
            .panelSurface()
        }
        .padding(Theme.Space.l)
    }
    .background(Theme.Palette.canvas)
    .tint(Theme.Palette.brand)
    .preferredColorScheme(.dark)
}
```

**页面级接入要点**（示意，均为 iOS 26 可用 API）：

```swift
// 根：全局品牌青 tint；外观默认跟随系统，可在设置中提供“跟随系统 / 深色 / 浅色”
TabView { /* Tab(...) */ }
    .tint(Theme.Palette.brand)

// 列表页
List { /* rows */ }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Theme.Palette.canvas)
    .safeAreaBar(edge: .top) { FilterChipBar() }          // 筛选胶囊条
    .scrollEdgeEffectStyle(.hard, for: .top)
    .navigationTitle("账号")
    .navigationBarTitleDisplayMode(.inline)
    .navigationSubtitle("主站 · 82 个")
    .toolbarTitleMenu { StationMenu() }                   // 切站

// 行
AccountRow(account)
    .listRowInsets(Theme.Metrics.rowInsets)
    .listRowBackground(SignalRowBackground(style: style))
    .listRowSeparatorTint(Theme.Palette.hairline)
    .swipeActions(edge: .leading, allowsFullSwipe: false) { /* 停止调度 / 启用调度 */ }

// 写操作结果触觉
.sensoryFeedback(trigger: lastOutcome) { _, outcome in
    outcome.map(Theme.Haptics.feedback(for:))
}
```

`sensoryFeedback(trigger:_:)` 的闭包形式（iOS 17+）返回可选的 `SensoryFeedback`，只在有结果时触发。由于它在 trigger 值变化时才触发，连续两次相同结果需要用“结果 + 操作编号”作为 trigger。

---

## 11. 风险与对策

| # | 风险 | 表现 | 对策 |
|---|---|---|---|
| R1 | **深色在白天、户外可读性下降** | 强光下暗底反光，`text3` 难读 | 外观默认**跟随系统**（深色只是设计起点，不强制）；浅色版质量对等，冷雾底而不是刺眼的纯白；三级文字在四种模式下都 ≥4.5:1；设置里提供“跟随系统 / 深色 / 浅色” |
| R2 | **玻璃叠加** | 饱和色块滑到 Tab 栏下把底栏染色；徽标微光透过玻璃显得脏 | 内容层没有大面积饱和填充（面积 ≤22%、柱改细线）；列表页顶部 `.hard` 边缘；微光只加在小徽标上，半径 ≤8pt；自定义玻璃只有 G1、G2 两处且不着状态色；在 iOS 27 色调滑杆的两端各截图验收 |
| R3 | **中文排版** | 加粗不一致、圆体中文回退、小字糊、中英文挤在一起 | 字重 ≤ Semibold；圆体只用于纯数字；中文 ≥13pt；手动加半角空格；首行基线对齐；英文系统下用 `.typesettingLanguage`；不用全大写、字距、斜体 |
| R4 | **Dynamic Type 大字号** | 行内放不下，读数被压缩 | 行用 `ViewThatFits` 加 `AnyLayout`，从横排切到竖排；徽标移到标题下一行；读数**禁止** `minimumScaleFactor`（03 A13），改为卡片自适应高度、网格减列；属性网格在 AX 字号下变单列；只给坐标轴加 `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` 上限；目标为 AX3 下账号 ≥3 个/屏 |
| R5 | **色弱、色盲** | 红绿、红琥珀难分；深色下红与灰亮度相同 | 三重冗余（形状 + 中文词 + 颜色）；强调四级（实心、着色、描边、暗点）在灰度下仍可分；信号轨只出现在 L2/L3；开启“区分时不仅依赖颜色”（`accessibilityDifferentiateWithoutColor`）时，正常行也显示“正常”描边徽标，容量条在读数旁加百分比，图表系列加不同虚线和点形 |
| R6 | **发光滥用、视觉疲劳** | 一屏多个光点，像霓虹 | 微光只给 L2/L3 徽标，只在深色、标准对比度下开启；持续异常常亮不闪；“刚变异常”只提示一次；后台变化不触发触觉 |
| R7 | **语义冲突** | “实际金额绿”与“正常绿”、“成本橙”与“限流琥珀”被混淆 | 色相错开（青玉 165° 对 146°；铜橙 22° 对 39°，且两者亮度不同）；金额色只出现在 6pt 色点和图表线上，数字本身永远用 `text1`；状态色只出现在点、徽标、轨上，两类颜色永不占用同一种视觉位置 |
| R8 | **偏离 Web 的配色**（Token 构成、延迟良好档、请求类型、错误类型） | 与 Web 后台不一致 | 简报只锁定状态色和成本三口径，以上属于本方向的主动调整，**需用户确认**；如需与 Web 完全一致，可退回 Web 色但统一降饱和 |
| R9 | **OLED 拖影与功耗** | 纯黑底滚动时出现拖影 | 画布用 `#080B11`，不是纯黑（增强对比度用 `#030407`）；近黑底在 OLED 上仍然省电 |
| R10 | **“冷”与品牌温度** | 墨蓝加青可能显得冷漠、像监控软件 | 用实际金额的青玉和成本的铜橙两种暖冷对比给金额区加温度；首页“全部正常”的措辞保持口语化；App 图标保留“S”的继承 |
| R11 | **倒计时与数据真实性** | 倒计时归零但服务器状态没变；手机时钟偏差 | 归零后显示“恢复中…”（L1）并触发一次静默刷新，以服务器结果为准；倒计时以服务器返回的绝对时间为准，不做本地推算 |
| R12 | **测试与验收** | 185 个 accessibilityIdentifier 与新组件不匹配 | 徽标、行背景、容量条都是独立组件，便于做快照测试（四种外观 × 默认/AX3 字号）；UITest 迁移成本见 05 §4.15 |

---

## 12. 数据依赖清单（不虚构后端能力）

| 视觉元素 | 需要的数据 | 状态 | 出处 |
|---|---|---|---|
| 限流、过载、临时不可调度徽标与倒计时 | `rate_limit_reset_at`、`rate_limited_at`、`overload_until`、`temp_unschedulable_until/reason` | **DTO 已下发，需在 `UpstreamAccount` 补解码** | 02 §3.1C；05 §4.2 |
| 模型限流徽标与子块 | `extra.model_rate_limits` | 需补解码 | 02 §3.1C |
| 配额超限 | `quota_*_used / quota_*_limit` | 已解码 | `Models.swift:146-151` |
| “停用”兼容 `disabled` | `status` | 需补映射 | 02 §3.1A |
| 错误摘要 | `errorMessage` + `safeMessage` 脱敏 | 已解码，界面未展示 | 05 §4.2 |
| 清除限流、清除错误、恢复状态、清除临时不可调度、重置配额 | `POST :id/clear-rate-limit`、`clear-error`、`recover-state`、`DELETE :id/temp-unschedulable`、`POST :id/reset-quota` | **需新接入** | 02 §1.2 |
| 首页错误、限流、过载计数 | `dashboard/stats` 的 `error_accounts / ratelimit_accounts / overload_accounts` | 接口已接入，字段需确认已解码 | 02 §5 |
| 首页“最早恢复”倒计时 | `ops/account-availability` | 需新接入（受 ops 开关控制） | 02 §1.1 |
| 首页告警行 | `ops/alert-events?status=firing` | 需新接入（受 ops 开关控制） | 02 §3.8 |
| 健康分条 | `ops/dashboard/overview.health_score` | 已部分接入，需补解码 | 02 §1.1 |
| 渠道健康 | `channel-monitor-v2/overview` | 需新接入（受开关控制） | 02 §1.4 |
| 未处理错误计数 | `ops/request-errors`（`resolved`） | 列表已接入；需确认是否返回总数 | 02 §1.1 |
| 今日读数、趋势、同比 | `dashboard/stats`、`dashboard/trend`、`today-stats/batch` | 已接入（同比在本地计算） | 01 §6.1 |

没有使用推送：后端没有出站推送能力（02 §5），所以本方向的“点亮”只发生在 App 前台。

---

## 13. 参考

- 暗驾驶舱与 ECAM 颜色：[Airbus A318 手册 p.207 · Dark Cockpit Concept](https://www.manualslib.com/manual/2570669/Airbus-A318.html?page=207)、[Wikipedia · ECAM](https://en.wikipedia.org/wiki/Electronic_centralised_aircraft_monitor)、[Aeropeep · dark cockpit](https://aeropeep.com/which-aircraft-uses-the-dark-cockpit-concept/)、[A350 quiet dark cockpit](http://bloga350.blogspot.com/2015/06/a350-pilots-first-surprise-quiet-dark.html)
- Apple：[ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle)、[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)、[HIG Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、[HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)
- 对比度：[WCAG 2.2 · 1.4.3 Contrast (Minimum)](https://www.w3.org/TR/WCAG22/#contrast-minimum)、[1.4.11 Non-text Contrast](https://www.w3.org/TR/WCAG22/#non-text-contrast)
- 中文排版：[W3C clreq](https://www.w3.org/TR/clreq/)
- 暗色产品参照（只借鉴“灰阶承担结构、彩色只承担语义”的分工）：[Vercel Geist Colors](https://vercel.com/geist/colors)
- 本仓库调研：`research/00-brief.md`、`01-current-ui-audit.md`、`02-backend-capability-map.md`、`03-reference-patterns.md`、`04-sibling-clients.md`、`05-codex-critique.md`
