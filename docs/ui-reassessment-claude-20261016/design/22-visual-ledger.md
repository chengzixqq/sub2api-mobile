# 22 · 视觉方向：「核簿」（蓝黑账簿 · Folio）

> 日期：2026-10-16 · 基线 `7ccd542` · 适用：SwiftUI，最低 iOS 26（iOS 27 能力用 `#available` 渐进增强）
> 前提文件：`research/00-brief.md`（最高优先级）、`01`～`05`。本文只定**视觉语言**（色彩、字体、形状、玻璃、图标、图表、动效、样屏、令牌代码）；信息架构、确认分级、文案规范以简报和其他设计稿为准，本文涉及时只做引用。
> 标注约定：**【事实】**＝已由源码、文档或计算核实；**【推断】**＝设计判断或尚待模拟器/真机验证的结论。
> 所有对比度由脚本按 WCAG 2.x 相对亮度公式逐一计算（方法见 §2.6），不是目测估计。

---

## 0. 一页摘要

- **名称**：核簿（Folio）。“核”取自“核对、核讫”——会计在核对过的账目旁打的那个勾；“簿”是账簿。
- **一句话概念**：**一本用蓝黑墨水誊写、在页边用朱笔批注异常的账簿。数字有分量，正常时安静，出事时页边自己会说话。**
- **三条视觉语法**（整套设计都从这三条推出来）：
  1. **字体即类别**：金额用 New York 衬线体（“誊写的钱”），计量（请求、Token、并发、时长）用 SF Pro，标识符（请求 ID、Key）用 SF Mono。不看标签，也能从字形分辨“这是钱还是计数”。
  2. **颜色即批注**：页面主体只有纸色和墨色。语义色只出现在需要人处理的地方，形式是**页边批注线 + 印章**。正常对象不上色，所以异常一眼就能看到。
  3. **线条代替卡片**：用发丝细线分隔行、用双线标出合计（会计的“合计双线”）、用留白分出层次。不再用一格格圆角卡片去模仿设置页。
- **Liquid Glass**：只用在系统外壳上（Tab 栏、工具栏、sheet、菜单、搜索）。自定义 `.glassEffect` **只有 2 处**：撤销回执浮条、批量操作条。内容层一律使用不透明纸面。
- **验收目标**（402×874pt，默认字号 Large）：账号列表全部正常时每屏 ≥9 个；混合视图（2 个带批注、1 个暂停、3 个分组页眉）7 个完整可见，第 8 个露出约 80%；日志每屏 ≥10 条。现状分别是每屏 3–4 个账号、1–3 条日志（01 §2.4、§2.13）。

---

## 1. 概念、适配理由与差异

### 1.1 为什么适合“中文优先的 AI API 中转站运营工具”

| 运营场景（简报 §1） | 账簿语言给出的答案 |
|---|---|
| **救火**：看账号异常和限流 | 页面平时只有墨色，异常出现时，页边会多出一条有颜色的批注线和一枚印章。这是**前注意**层面的信号：手指扫过列表，不用读字就知道哪几行有问题。批注线的线型也带含义：**实线＝持续性故障，要人处理；虚线＝时间窗阻断，会自动恢复**。所以“错误”和“限流中”不靠颜色也能区分（§6.2）。 |
| **账务**：加余额、退款、看营收 | 钱是这个工具里最需要信任感的东西。衬线数字和合计双线借用的是财报和银行对账单的视觉惯例，金额一出现就显得郑重。三口径（实际、成本、标准）始终**并列成栏**、带标签、颜色固定，不会再出现“需要一行图例才能看懂颜色”的情况（01 D18/C18）。 |
| **监控**：早晚看营收用量、渠道监控 | 图表借鉴报纸财经版（FT 的 Visual Vocabulary）：细线、少网格、直接在线尾标数值，不放图例。迷你趋势只放在“账面大数”旁边。 |
| **中文优先** | 账簿、朱批、核讫、大写数字（壹贰叁）都是中文用户熟悉的“账”的符号。中文正文始终用 PingFang SC，衬线只用在数字和拉丁字母上，所以不需要下载宋体，也没有中文衬线渲染的风险（§3.2）。 |
| **写入安全语义** | 现有逻辑层最有价值的语义是“结果不明＝待核对”（01 §7.2）。“核簿”这个名字和视觉语言直接对应它：待核对的项目有专用印章（`doc.text.magnifyingglass`），会常驻在底部附件里，直到核对完成。 |

### 1.2 与另外两种方向的根本区别

三种方向的根本差别在于**由什么承载意义**，而不只是配色不同：

| 维度 | 精密仪器 | **核簿（本方向）** | 夜航信号 |
|---|---|---|---|
| 承载意义的主通道 | 几何与刻度（量规、表格栅格、等宽列） | **排版与批注**（字体分工、页边线、印章、合计线） | 亮度与色光（暗底上的发光信号） |
| 默认姿态 | 测量 | **核对、阅读** | 警戒 |
| 底色 | 冷中性灰 | **暖纸色 / 墨色**（浅色优先，深色是“夜读”） | 近黑（深色优先，浅色常沦为附属） |
| 颜色用量 | 中等（每个指标都有指示灯） | **极少**（只给需要人处理的东西上色） | 高（颜色就是信息本身） |
| 数字字体 | 全部 SF Mono 或等宽 | **金额用衬线，计量用无衬线，标识用等宽** | 无衬线加粗、高亮 |
| 信任从何而来 | 精确 | **可追溯、有记录、经过核对** | 时刻警觉 |
| 主要风险 | 冷、像“按数字堆出来的仪表盘” | 过度装饰、纸色偏黄（§11 有对策） | 白天刺眼、颜色过载、浅色模式质量不足 |

---

## 2. 色彩

### 2.1 色彩原则

1. **墨与纸是主角**：正文和数字都用“蓝黑墨水”色系的墨色（`Ink.*`），底色是暖纸（`Paper.*`）。品牌色是墨水本身的蓝（`Brand.accent`），不额外引入一个装饰色。
2. **语义色含义与简报完全一致**，色值按纸面重新调校：绿＝正常，琥珀（赭）＝限流/临时/接近上限，红（朱）＝错误/过载/不可用，灰（铅）＝停用/暂停/未知，紫＝模型级限流；成本三口径为实际＝绿、成本＝橙、标准＝灰（00 §2，04 §4.1 #12、§5）。
3. **每个语义色调都有三个强度**：`foreground`（文字和图标，对任何纸面 ≥4.5:1）、`fill`（条形、线条、批注线，对纸面和轨道 ≥3:1）、`wash`（印章底，低彩度）。
4. **品牌蓝绝不表示状态**，语义色绝不用作装饰。
5. **金额不用红绿表示涨跌**：在中文语境里，红和绿分别代表涨和跌，这会与状态语义冲突（03 §1.9、§5.3）。差额、退款用正负号（`+`、`−` U+2212）和标签表达，颜色保持墨色。

### 2.2 背景层级、表面与线

| 令牌 | 用途 | 浅色 | 深色（夜读） | 浅·增强对比度 | 深·增强对比度 |
|---|---|---|---|---|---|
| `Paper.canvas` | 页底：所有列表和详情的背景 | `#F4F0E7` | `#13161C` | `#F8F6F0` | `#0B0D11` |
| `Paper.sheet` | 抬起的纸：批注卡、账目块、图表浮签、表单行 | `#FBF9F4` | `#1B1F27` | `#FFFFFF` | `#14171D` |
| `Paper.sunken` | 凹槽：输入框、流式输出、代码块 | `#EDE8DC` | `#0E1015` | `#EFEBE1` | `#07080B` |
| `Paper.track` | 容量条和配额条的轨道 | `#E8E2D6` | `#2A2F38` | `#DDD6C7` | `#2E333D` |
| `Paper.rule` | 发丝分隔线、图表网格 | `#DCD3C2` | `#2B303A` | `#9E937D` | `#4A505C` |
| `Paper.ruleStrong` | 合计双线、图表零基线 | `#B3A891` | `#454B57` | `#6F6656` | `#6B7280` |

- canvas 与 sheet 的对比度只有 1.08（浅色）和 1.10（深色）。这是有意为之：两者都是纸，靠发丝边框和 1pt 纸边阴影区分，不靠色块。
- 深色模式不用纯黑，而是带一点蓝的墨底，与“蓝黑墨水”同源，避免 OLED 上纯黑与玻璃之间出现过硬的边界。

### 2.3 文字、品牌与语义色（含对比度）

下表中的对比度依次为对 canvas / sheet / sunken 三种纸面的比值。正文要求 ≥4.5:1，大字或粗体要求 ≥3:1。**表中所有文字令牌对所有纸面都 ≥4.5:1**，因此可以放心用于 12pt 的中文。

| 令牌 | 含义 | 浅色 HEX | 浅色对比度 | 深色 HEX | 深色对比度 | 浅·增强（最低比） | 深·增强（最低比） |
|---|---|---|---|---|---|---|---|
| `Ink.primary` | 主文字、主数字 | `#1C2230` | 13.98 / 15.11 / 13.00 | `#ECE7DC` | 14.69 / 13.39 / 15.43 | `#0B0F18`（16.10） | `#FBF8F1`（16.92） |
| `Ink.secondary` | 次文字：元信息、页眉 | `#4C5260` | 6.88 / 7.44 / 6.40 | `#B9B3A8` | 8.69 / 7.92 / 9.13 | `#2F3440`（10.46） | `#DAD5CB`（12.27） |
| `Ink.tertiary` | 三级文字：时间、单位、坐标 | `#60646D` | 5.21 / 5.64 / 4.85 | `#948F86` | 5.64 / 5.14 / 5.92 | `#3F434C`（8.33） | `#C0BBB1`（9.39） |
| `Brand.accent` | 墨水蓝：交互色、正常数据线 | `#1A4580` | 8.37 / 9.04 / 7.78 | `#86AEE8` | 7.97 / 7.26 / 8.37 | `#143B6E`（9.38） | `#AFCDF7`（11.02） |
| `Tone.ok` | 正常 | `#2E6A3E` | 5.69 / 6.15 / 5.29 | `#82C493` | 8.86 / 8.07 / 9.30 | `#1C4F2A`（8.01） | `#A3DDB1`（11.57） |
| `Tone.caution` | 限流 / 临时 / 接近上限 | `#8A5400` | 5.51 / 5.96 / 5.13 | `#E9B44C` | 9.57 / 8.73 / 10.06 | `#623A00`（8.30） | `#F6CA6E`（11.62） |
| `Tone.critical` | 错误 / 过载 / 不可用 | `#9C1F16` | 7.04 / 7.61 / 6.55 | `#F2867A` | 7.30 / 6.66 / 7.67 | `#871A12`（8.07） | `#FFA69B`（9.56） |
| `Tone.neutral` | 停用 / 暂停 / 未知 | `#5B6068` | 5.57 / 6.02 / 5.18 | `#A9ACB2` | 7.96 / 7.26 / 8.36 | `#3F434A`（8.35） | `#C6C9CE`（10.81） |
| `Tone.model` | 模型级限流 | `#7448A8` | 5.71 / 6.17 / 5.31 | `#C8A6F0` | 8.77 / 7.99 / 9.21 | `#4E2780`（9.16） | `#D4BFF6`（10.75） |
| `Money.actual` | 实际（扣费） | `#1E6B57` | 5.60 / 6.06 / 5.21 | `#74C9AC` | 9.22 / 8.41 / 9.69 | `#134D3E`（8.17） | `#95DCC3`（11.37） |
| `Money.cost` | 成本（账号成本） | `#A3431A` | 5.47 / 5.91 / 5.09 | `#F29A62` | 8.26 / 7.53 / 8.68 | `#7C2E0D`（7.83） | `#F8B488`（10.15） |
| `Money.standard` | 标准（标准费用） | `#635E54` | 5.66 / 6.12 / 5.27 | `#ABA597` | 7.38 / 6.73 / 7.76 | `#45413A`（8.52） | `#C7C1B4`（10.01） |
| `Ink.disabled` | 仅限禁用控件和占位符 | `#9C978D` | 2.56（禁用状态可豁免） | `#5E5B55` | 2.68（禁用状态可豁免） | — | — |

**图形填充**（条形、图表线、批注线）。非文本图形要求 ≥3:1，下表依次为对 sheet / track 的比值：

| 令牌 | 浅色 | 浅色对比度 | 深色 | 深色对比度 | 浅·增强（最低比） | 深·增强（最低比） |
|---|---|---|---|---|---|---|
| `Tone.ok.fill` | `#3B8550` | 4.29 / 3.50 | `#5FAE73` | 6.12 / 4.99 | `#25693A`（4.59） | `#77C48A`（6.06） |
| `Tone.caution.fill` | `#AD7006` | 3.92 / 3.19 | `#D99A1E` | 6.75 / 5.50 | `#8F5B00`（3.96） | `#EBB03E`（6.52） |
| `Tone.critical.fill` | `#C2342A` | 5.23 / 4.26 | `#E0574A` | 4.43 / 3.61 | `#A2251B`（5.15） | `#F06A5C`（4.18） |
| `Tone.neutral.fill` | `#7A7F87` | 3.83 / 3.12 | `#7B8088` | 4.16 / 3.38 | `#5E636B`（4.18） | `#9A9EA6`（4.72） |
| `Tone.model.fill` | `#8760C0` | 4.47 / 3.65 | `#A47FDD` | 5.23 / 4.26 | `#6A43A3`（4.93） | `#B293E6`（4.95） |
| `Money.actual.fill` | `#2A836A` | 4.38 / 3.58 | `#3FA585` | 5.45 / 4.44 | `#1D6652`（4.72） | `#55BB98`（5.40） |
| `Money.cost.fill` | `#C0561F` | 4.35 / 3.55 | `#E07A3E` | 5.52 / 4.50 | `#9C4114`（4.57） | `#EE8F55`（5.25） |
| `Money.standard.fill` | `#827C70` | 3.94 / 3.21 | `#857F73` | 4.15 / 3.38 | `#6C665B`（3.94） | `#9F998C`（4.47） |
| `Brand.accent`（作数据墨） | `#1A4580` | 9.04 / 7.38 | `#86AEE8` | 7.26 / 5.91 | — | — |

**印章底色（wash）与对应文字的对比度**：

| 令牌 | 浅色 | 深色 | 浅·增强 | 深·增强 | 文字对 wash 的对比度（浅 / 深 / 浅增强 / 深增强） |
|---|---|---|---|---|---|
| `Brand.wash` | `#E2E8F1` | `#1E2A3D` | `#DCE4F0` | `#1F2C42` | 7.72 / 6.35 / 8.72 / 8.61 |
| `Tone.ok.wash` | `#E2EDDE` | `#1A2A1F` | `#DCEAD7` | `#16261B` | 5.36 / 7.36 / 7.63 / 10.20 |
| `Tone.caution.wash` | `#F6E8CA` | `#2E2614` | `#F3E2BE` | `#2C2310` | 5.17 / 7.91 / 7.73 / 10.03 |
| `Tone.critical.wash` | `#F6E0DB` | `#33201E` | `#F4D9D3` | `#331B19` | 6.33 / 6.20 / 7.19 / 8.52 |
| `Tone.neutral.wash` | `#E7E4DD` | `#24272D` | `#E2DFD7` | `#22252B` | 4.98 / 6.58 / 7.46 / 9.25 |
| `Tone.model.wash` | `#ECE4F3` | `#272035` | `#E6DCF1` | `#251D33` | 5.24 / 7.56 / 8.24 / 9.66 |

**其他关键组合**：

| 组合 | 对比度 |
|---|---|
| 主按钮文字 `Brand.onAccent` `#FFFFFF` 在 `#1A4580` 上（浅） | 9.52 |
| `#0E1A2E` 在 `#86AEE8` 上（深色主按钮用深字，不用白字） | 7.66 |
| `Ink.primary` 在 `Tone.caution.wash` 上（浅色批注卡正文） | 13.11 |
| `Ink.primary` 在 `Tone.critical.wash` 上（浅） | 12.57 |
| `Paper.rule` 在 sheet 上（浅 / 浅·增强 / 深·增强） | 1.41 / 3.03 / 2.22（标准模式下是装饰线；增强模式下成为可感知的分隔） |

### 2.4 语义映射总表（与简报和 04 的术语裁决一致）

| 语义色调 | 适用状态（中文状态词照搬 04 §4.1、§5） | 印章符号 | 批注线 |
|---|---|---|---|
| `ok` 绿 | 账号正常；用户启用；分组正常；渠道可用；告警已恢复；写入成功 | `checkmark.circle` 等 | 无（正常不批注） |
| `caution` 赭 | 限流中、临时不可调度、配额超限、即将过期；渠道性能下降；P2/P3 告警中；待核对；未处理错误 | `hourglass` 等 | **虚线**（时间窗，会自动恢复或等待核对） |
| `critical` 朱 | 错误、过载中、积分耗尽；渠道不可用；P0/P1 告警中；写入被拒绝 | `exclamationmark.octagon` 等 | **实线**（持续性故障，需要人处理） |
| `neutral` 铅 | 停用（账号、分组）、暂停（调度关闭）、禁用（用户）、未知、未执行 | `pause.circle` 等 | 无 |
| `model` 紫 | 模型级限流（`extra.model_rate_limits`） | `brain` | **点线** |

- **用户“禁用”取灰色，不取 Web 的红点**：04 §5 已裁决“红色只用于真正的故障”。禁用是管理员的主动选择，属于“停用/暂停”这一类。
- **并发“使用中”不着琥珀**：Web 把使用中的并发标黄（`AccountCapacityCell.vue:67-73`），放到手机列表里会让大多数在干活的账号都变成琥珀色。本方向只在 ≥75% 时标琥珀、≥90% 或满额时标朱，阈值与 Web 用量条一致（`UsageProgressBar.vue:132-147`）。正常用量用 `Brand.accent` 作“数据墨”。琥珀的含义（接近上限）没有改变，只是不再用它表示“在用”。
- **Token 构成不照搬 Web 的翠绿/紫罗兰/天蓝/琥珀**：紫和琥珀已被状态语义占用。图表中的 Token 构成改用墨水蓝的 4 级明度阶梯，并在图上直接标注名称（§7.1）。这是有意偏离 Web 的决定；如果用户坚持与 Web 一致，可以只在“统计分析”子页切换为 Web 配色。

### 2.5 增强对比度模式（`colorSchemeContrast == .increased`）的调整

1. 所有令牌切换到上表中的“增强”列：墨色更深或更亮，三级文字接近二级文字（≥8.3:1）。
2. `Paper.rule` 从装饰线变为可感知的线（浅 3.03:1），列表分隔和图表网格因此清晰可见。
3. 印章加 1pt 实线描边，颜色取 `tone.foreground`，wash 底不再是唯一边界。
4. 批注线从 3pt 加宽到 4pt；虚线和点线的间隙缩小（`[4,2]`、`[2,2]`），线型仍然可辨。
5. 图表主线从 2pt 加粗到 2.5pt，对比线从 1pt 加粗到 1.5pt。
6. 自定义玻璃（§5.2）加 1pt `Paper.ruleStrong` 描边。

实现方式：令牌由 `UIColor(dynamicProvider:)` 读取 `traitCollection.accessibilityContrast`，自动切换（§10）；线宽类调整读取 `@Environment(\.colorSchemeContrast)`。

### 2.6 计算方法与色弱模拟

- 对比度：sRGB 线性化后计算相对亮度 L，取 (L₁+0.05)/(L₂+0.05)，与 WCAG 2.x 定义一致。脚本在本机临时目录运行，不在仓库内。
- 色弱：采用 Machado 2009 模型（严重度 1.0）模拟后，计算 CIELAB 色差 ΔE。结果中值得注意的几对如下：

| 色对（浅色） | 正常视觉 ΔE | 绿色弱 ΔE | 红色弱 ΔE | 结论 |
|---|---|---|---|---|
| ok vs critical | 82.4 | 25.0 | 15.3 | 可分辨 |
| caution vs critical（文字） | 35.4 | **8.6** | 26.5 | 绿色弱下接近，**靠线型（虚线/实线）和符号区分** |
| model vs accent | 33.3 | 12.9 | 14.7 | 可分辨；而且 accent 从不用于状态 |
| cost vs caution | 21.7 | **4.3** | 14.9 | 绿色弱下几乎相同；两者从不出现在同一语境（一个只出现在金额栏，一个只出现在状态），并且都带文字标签 |

结论：颜色从来不是唯一信号。每个状态都有**符号 + 文字 + 批注线型**三重冗余（§6.2、§10）。

---

## 3. 字体

### 3.1 四种字体的分工

| 字体 | SwiftUI 设计 | 承担的角色 | 不用于 |
|---|---|---|---|
| **SF Pro** | `.default` | 界面骨架：导航、标签、列表标题、元信息；**计量数字**（请求数、Token、并发、RPM、时长、百分比、倒计时、健康分） | 金额 |
| **New York** | `.serif` | **金额专用**（“誊写的钱”）：首页账面大数、三口径栏、列表行尾金额、余额与流水、配额金额；少量拉丁字母装饰（如 `No.`） | 中文、计量数字、按钮 |
| **SF Mono** | `.monospaced` | **标识符**：请求 ID、Key 前缀、上游请求 ID、账号测试的流式输出、HTTP 状态码印章 | 正文、模型名（模型名是名称，用 SF Pro） |
| **SF Pro Rounded** | `.rounded` | 只用于**计数徽记**：筛选胶囊里的计数、站点字母头像、“待处理 3”的计数 | 正文、金额、任何中文 |

设计意图：读者可以从字形分辨数字的类别，衬线表示钱，无衬线表示量，等宽表示编号。这同时也是对 01 D28（数字格式不一致）的结构性修复。

### 3.2 中文（PingFang SC）在各字体设计下的实际表现

| 设计 | 中文实际字形 | 注意事项 |
|---|---|---|
| `.default` | PingFang SC【事实：iOS 系统中文字体】 | PingFang SC 只有 6 个字重（极细、纤细、细体、常规、中黑、中粗），没有 Bold/Heavy。对中文设 `.bold` 及以上时，中文停在中粗，拉丁字母却会变粗，造成同一行内粗细不一。**规则：含中文的文字最高只用 `.semibold`。** |
| `.serif` | New York 不含 CJK 字形【事实，见 Wikipedia/Apple Fonts】。中文会回退到系统 CJK 字体，预计是 PingFang（无衬线），而不是宋体【推断，需在 zh-Hans 模拟器截图核实】 | 同一个 `Text` 里中文为无衬线、数字为衬线，会显得割裂。**规则：衬线只用在纯数字或拉丁文的 `Text` 上；中文标签单独成段**，用 `HStack(alignment: .firstTextBaseline)` 或 Text 插值 `Text("今日实际 \(Text(amount).font(Theme.Typeface.ledgerFigure))")` 拼接。注意：iOS 26 已弃用 `Text + Text`【事实】，应改用插值。 |
| `.rounded` | 回退到 PingFang（不是圆体） | 只用于纯数字计数。 |
| `.monospaced` | 回退到 PingFang，中文字宽约为两个等宽拉丁字符，但不严格对齐网格 | 流式输出里出现模型返回的中文可以接受；界面标签不要放进等宽字体。 |
| 宋体（Songti SC） | 在 iOS 上属于需按需下载的字体，不是预装字体【推断，依据第三方字体清单】 | **本方向不使用宋体**：需要运行时下载，小字号下屏显效果差，授权也不明确。编辑排版的气质由 New York 数字、线条和留白承担。 |

其他中文排版规则：

1. **行高一致**：同一列表里，含中文的行和纯拉丁文的行可能因为字体回退而高度不同（中文的升部和降部更大）【推断，需模拟器核实】。在根视图设置 `.typesettingLanguage(Locale.Language(identifier: "zh-Hans"))`（iOS 17），统一按中文排版规则计算行高。设备语言是英文时也会生效。
2. **最小字号**：中文不小于 `caption`（默认 12pt）。`caption2`（11pt）只用于数字和拉丁文（例如坐标轴）。
3. **多行中文段落**（错误摘要、批注卡正文）加 `.lineSpacing(3)`，使行距接近 1.4 倍。单行元信息不加。
4. **中西文间距**：模板字符串中手动加半角空格（“并发 3 / 4”“近 60 秒”），符合 clreq 中“最多 1/4 em”的建议。
5. **货币符号与数字不能断开**：金额 `Text` 一律加 `.lineLimit(1).fixedSize()`（03 §5.3 引 clreq §6.1.2.2）。
6. **不用斜体**：PingFang 没有斜体，系统合成的倾斜效果很难看。
7. **标点**：中文语句里使用全角标点；分隔符统一为两侧带半角空格的“ · ”。

### 3.3 文字层级（全部基于 Text Style，跟随 Dynamic Type）

默认字号指系统“大”档（Large）。所有含数字的样式**在令牌层就已经带 `.monospacedDigit()`**，视图里不需要再写。

| 令牌 | Text Style | 默认 pt | 设计 | 字重 | SwiftUI `Font` | 颜色 | 用途 |
|---|---|---|---|---|---|---|---|
| （系统） | largeTitle / headline | 34 / 17 | 系统 | 系统 | 不覆盖导航栏字体 | 系统 | Tab 根页大标题、行内标题 |
| `ledgerDisplay` | largeTitle | 34 | serif | semibold | `.system(.largeTitle, design: .serif, weight: .semibold).monospacedDigit()` | `Ink.primary` | 首页“实际”、余额页当前余额 |
| `ledgerTitle` | title2 | 22 | serif | semibold | `.system(.title2, design: .serif, weight: .semibold).monospacedDigit()` | `Money.*` | 三口径栏、详情页今日账目 |
| `ledgerFigure` | body | 17 | serif | medium | `.system(.body, design: .serif, weight: .medium).monospacedDigit()` | `Ink.primary` | 列表行尾金额、流水金额 |
| `ledgerFigureSmall` | subheadline | 15 | serif | regular | `.system(.subheadline, design: .serif).monospacedDigit()` | `Ink.secondary` | 配额金额、次要金额 |
| `measureDisplay` | title2 | 22 | default | semibold | `.system(.title2, weight: .semibold).monospacedDigit()` | `Ink.primary` 或色调色 | 倒计时、健康分、请求总数 |
| `measure` | subheadline | 15 | default | medium | `.system(.subheadline, weight: .medium).monospacedDigit()` | `Ink.primary` | 并发 3 / 4、Tokens 6.1M |
| `pageHeading` | title2 | 22 | default | semibold | `.system(.title2, weight: .semibold)` | `Ink.primary` | 详情页的对象名 |
| `rowTitle` | body | 17 | default | semibold | `.system(.body, weight: .semibold)` | `Ink.primary` | 列表行名称 |
| `rowMeta` | subheadline | 15 | default | regular | `.subheadline.monospacedDigit()` | `Ink.secondary` | 平台 · 类型 · 分组 |
| `bodyText` | callout | 16 | default | regular | `.callout` + `.lineSpacing(3)` | `Ink.primary` | 批注卡正文、错误全文 |
| `annotation` | footnote | 13 | default | medium | `.footnote.weight(.medium).monospacedDigit()` | `Tone.*.foreground` | 行内批注（第三行） |
| `sectionLabel` | footnote | 13 | default | semibold | `.footnote.weight(.semibold)` | `Ink.secondary` | 页眉 |
| `stamp` | caption | 12 | default | semibold | `.caption.weight(.semibold)` | `Tone.*.foreground` | 状态印章 |
| `caption` | caption | 12 | default | regular | `.caption.monospacedDigit()` | `Ink.tertiary` | 更新时间、单位 |
| `axis` | caption2 | 11 | default | regular | `.caption2.monospacedDigit()` | `Ink.tertiary` | 图表坐标（只放数字） |
| `code` | footnote | 13 | monospaced | regular | `.system(.footnote, design: .monospaced)` | `Ink.secondary` | 请求 ID、Key 前缀 |
| `codeBody` | callout | 16 | monospaced | regular | `.system(.callout, design: .monospaced)` | `Ink.primary`（sunken 底） | 账号测试流式输出 |
| `count` | footnote | 13 | rounded | semibold | `.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit()` | 随容器 | 筛选胶囊计数、站点字母 |

`Font.system(_:design:weight:)` 为 iOS 16 API【事实，03 §0.2 已核实同类 API 版本】。New York 自带比例和等宽两套数字，`.monospacedDigit()` 会选用其等宽数字【事实：New York 支持 tabular figures；SwiftUI 修饰符对 serif 设计的实际效果需在模拟器确认】。

### 3.4 数字规则

1. **一律等宽数字**：凡是会纵向对齐、会刷新跳动的数字（金额、计数、Token、时长、百分比、HTTP 码、倒计时）都使用带 `.monospacedDigit()` 的令牌字体。**禁止在视图里直接写 `.font(.caption)` 一类的系统字体**，建议用 SwiftLint 自定义规则拦截 `\.font\(\.(caption|footnote|body)` 在 `DesignSystem/` 以外的出现。
2. **列内小数位一致**：同一列金额保留相同位数（列表 2 位），这样等宽数字下小数点自然对齐，右对齐即可。
3. **符号**：负数和退款用真正的减号 `−`（U+2212），不用连字符；差额必须带正负号（`+$772.42`）。
4. **缺失值**：显示 `—`（em dash，`Ink.tertiary`），VoiceOver 读“未返回”（简报 §3.4）。**数字 0 必须显示为 0**，不能用 `—` 代替。
5. **格式化入口唯一**：继续由 `Sub2Core` 的 `DashboardPresentation` 负责（Decimal 舍入已经做对，01 §6.1），需要在其基础上补千分位，并把 Token 改为最多 1 位小数。删除 `Components.money()`（05 §4.6）。

### 3.5 排版样例

**金额（New York，等宽数字）**

| 场景 | 样例 | 说明 |
|---|---|---|
| 首页账面大数 | `$1,284.50` | `ledgerDisplay`，千分位，两位小数，窄货币符号（避免 zh-CN 区域下显示成 `US$`，03 §5.2） |
| 列表行尾 | `$48.20` | `ledgerFigure`，墨色（列表里的单一金额不上口径色，见 §2.4 说明） |
| 不足 1 美分 | 列表 `<$0.01`；详情 `$0.0024` | 详情沿用 `DashboardPresentation.cost` 的 3–4 位规则 |
| 三口径并列 | `实际 $48.20 · 成本 $19.75 · 标准 $61.30` | 标签用 SF Pro `caption` 的 `Ink.tertiary`；数字用 `ledgerTitle`，颜色依次为 `Money.actual/cost/standard` |
| 差额 | `+$772.42` / `−$31.00` | 墨色，带符号，不用红绿 |
| 退款 | `−$20.00` 退款 | 标签说明含义，颜色不变 |

**余额流水（手机版两行账，数据源 `GET admin/users/:id/balance-history`，未接入，见 02 §1.2）**

```
管理员充值                                   +$50.00   ← rowTitle（PingFang） + ledgerFigure
10/16 14:02 · 余额 $62.50                                ← rowMeta / ledgerFigureSmall（Ink.secondary）
─────────────────────────────────────────────────────  ← Paper.rule 发丝线
退款                                          −$20.00
10/16 09:15 · 余额 $12.50
═════════════════════════════════════════════════════  ← Paper.ruleStrong 合计双线
本页合计  收入 $60.00 · 支出 −$20.00
```

**Token 与计量（SF Pro）**：列表 `1.2M`（最多 1 位小数，去掉末尾 0）；详情 `1,204,331`；坐标轴 `1M`。并发 `3 / 4`；RPM `37 / 60 近 60 秒`；健康分 `92`（无单位）；错误率 `0.8%`。

**时间（SF Pro）**：列表 `3分钟前`、`昨天 16:12`、`10/09 16:12`；详情 `2026-10-16 16:12:08（UTC+8）`；倒计时用 `Text(timerInterval: Date.now...resetAt, countsDown: true)`（iOS 16）显示为 `8:32`，系统自动逐秒刷新，**不需要 Timer**；时长 `850ms`、`1.25s`（VoiceOver 读“1.25 秒”）。

**标识（SF Mono）**：`req_8f3a…c21e`，使用 `.truncationMode(.middle)`，长按可复制。

---

## 4. 形状与表面

### 4.1 圆角体系（全部使用 `.continuous` 连续曲率）

| 令牌 | 半径 | 用于 | 意图 |
|---|---|---|---|
| — | 0 | 列表行、分区 | 账簿的行就是行，不做成卡片 |
| `Radius.stamp` | 4 | 状态印章、ID 小块、HTTP 码 | **印章是方的，控件是胶囊**。看形状就知道能不能点：胶囊（系统按钮、筛选胶囊）可以点，方印只是状态 |
| `Radius.bar` | 3 | 容量条（6pt 高） | 小半径，避免变成“药丸” |
| `Radius.field` | 8 | 输入框凹槽、图表浮签 | — |
| `Radius.card` | 12 | 批注卡、账目块 | 少数需要“抬起”的纸 |
| 同心 | 由容器推导 | sheet 内的确认摘要卡、批量操作条 | 使用 `ConcentricRectangle`（iOS 26），让内部形状与 sheet 或屏幕圆角同心。例如 `.background(Theme.Paper.sheet, in: ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))`（签名以 Xcode 27 SDK 为准，见 nilcoalescing 与 swiftui-garden 的说明） |

### 4.2 表面

- **内容层全部不透明**。列表使用 `List` + `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + `.background(Theme.Paper.canvas)`，行使用 `.listRowBackground(Theme.Paper.canvas)`。**继续使用 `List`**，以保留滑动操作、编辑模式、多选（05 §6.3）。
- **抬起的纸**（批注卡、账目块、浮签）：底色 `Paper.sheet`，加 1 发丝 `Paper.rule` 描边。浅色模式再加一道清晰的纸边投影 `shadow(color: .black.opacity(0.05), radius: 0, x: 0, y: 1)`（不模糊）；深色模式不加投影，只保留描边。
- **编辑表单**（账号编辑、充值、退款）**继续使用系统 `Form`**，这是录入数据的正确容器（03 A4 指出的问题是“用 Form 承载只读数据”）。为了与账簿统一：`.scrollContentBackground(.hidden).background(Theme.Paper.canvas)`，行底用 `Paper.sheet`。
- **凹槽**（`Paper.sunken`）：输入框、账号测试的终端输出。

### 4.3 线条与阴影

| 线 | 规格 | 用途 |
|---|---|---|
| 发丝线 | `1 / displayScale`，`Paper.rule` | 行分隔：从文字列开始（`alignmentGuide(.listRowSeparatorLeading)`），不贯穿图标列 |
| 页眉线 | 发丝线，从页眉文字后延伸到行尾 | 分区标题 `壹 待处理 ────── 3` |
| 合计双线 | 两条发丝线，间隔 2pt，`Paper.ruleStrong` | 只出现在“合计”之下，**每屏最多 1 处** |
| 零基线 | 1pt，`Paper.ruleStrong` | 图表 |
| 批注线 | 3pt，`Tone.*.fill`，位于页边栏（行首 8pt 宽的区域） | 实线＝critical，虚线 `[4,3]`＝caution，点线 `[2,3]`＝model |

内容层不使用模糊阴影。层次靠线条和留白表达。玻璃控件的投影由系统负责。

### 4.4 间距与密度

**间距令牌（4pt 网格）**：`xs 4`、`s 8`、`m 12`、`l 16`（页边距）、`xl 24`（分区间距）、`xxl 32`；列表行上下 `rowVertical 8`；日志行上下 10；页边栏 `marginLane 8`；图标列 `iconColumn 22`。iPad 等宽屏用 `.contentMargins(.horizontal, 24, for: .scrollContent)`（iOS 17）并限制可读宽度。

**行高预算**（默认 Large 字号；SF 行高为 body 22、subheadline 20、footnote 18；含中文的行可能再高 1–2pt，需模拟器实测）：

| 行类型 | 构成 | 高度 |
|---|---|---|
| 账号行（正常、暂停、停用） | 8 + 名称 22 + 3 + 元信息 20 + 8 | **≈61pt** |
| 账号行（带批注） | 正常行 + 3 + 批注 18 | **≈82pt** |
| 日志行 | 10 + 状态码与模型 20 + 2 + 元信息 18 + 10 | **≈60pt** |
| 列表分组页眉 | 上 16 + 18 + 下 6 | ≈40pt（首个页眉上边距减为 6，约 30pt） |
| 详情页、首页页眉 | 上 24 + 18 + 下 8 | ≈50pt（首个约 38pt） |

**每屏可见目标**（iPhone 17 Pro，402×874pt；可视区 ≈ 874 − 状态栏 62 − 行内导航栏 44 − 筛选胶囊条 48 − 底部 Tab 区约 90 ≈ **630pt**）：

| 页面 | 现状（01 审计） | 本方向目标（按上表推算） |
|---|---|---|
| 账号列表 · 全部正常（1 个页眉） | 3–4 个 | **≥9 个**（(630−30)/61 ≈ 9.8） |
| 账号列表 · “需处理”视图（全部带批注，1 个页眉） | — | **≥7 个**（(630−30)/82 ≈ 7.3） |
| 账号列表 · 全部视图（见 §9.2：2 个批注、1 个暂停、3 个页眉） | — | **7 个完整可见，第 8 个露出约 80%** |
| 日志（1 个日期页眉） | 1–3 条 | **≥10 条**（(630−30)/60 = 10） |
| iPhone 17e（约 390×844pt，可视区约 600pt） | — | 账号全部正常 ≥9 个 / 日志 ≥9 条 |

暂停、停用的账号**不占第三行**：它们是管理员的主动选择，不需要批注，状态用印章放在元信息行的右侧。

达成手段是**减少每行字段**（最多 3 行，第 3 行只给异常），而不是缩小字号（05 §5.7）。

---

## 5. Liquid Glass 用法

### 5.1 系统玻璃（自动获得，不做定制）

| 位置 | API | 说明 |
|---|---|---|
| Tab 栏（含搜索 Tab） | `TabView` + `Tab(...)`、`Tab(role: .search)`、`.tabViewSearchActivation(.searchTabSelection)` | iOS 27.2 必须加激活修饰符，才能保留独立的搜索按钮（03 §1.1） |
| 导航工具栏、站点切换 | `.toolbar`、`.toolbarTitleMenu`、`ToolbarSpacer`、`.navigationSubtitle` | 站点字母头像放在标题菜单里 |
| sheet、菜单、上下文菜单、确认对话框 | 系统默认 | **不设置 `presentationBackground`**（03 §1.6） |
| “待核对 N 项”常驻提醒 | `.tabViewBottomAccessory(isEnabled:)`（26.1；26.0 用无参版本） | 这是跨页面的进行中状态，符合 HIG 对附件的定位 |
| 筛选胶囊条所在的条 | `.safeAreaBar(edge: .top)` | 由系统提供滚动边缘效果。**胶囊本身不用玻璃**：未选中时用 `.buttonStyle(.bordered).tint(Theme.Ink.secondary)`，选中时用 `.borderedProminent.tint(Theme.Brand.accent)`（白字对墨水蓝 9.52:1） |
| sheet 内的主按钮 | `.buttonStyle(.glassProminent)` + `.tint(Theme.Brand.accent)` | 每屏最多 1 个，例如“充值 $50.00” |

### 5.2 自定义 `.glassEffect`（严格限定 2 处）

| # | 位置 | 实现 | 理由 |
|---|---|---|---|
| ① | **撤销回执浮条**（例如“已停止调度 Claude-官方-03 · 撤销”） | 胶囊形，`.glassEffect(.regular.interactive(), in: .capsule)`；位于 Tab 栏上方 12pt，最大宽度 360pt，4 秒后自动消失（“待核对”不走这里，改用附件） | 这是瞬时控件，属于控件层，系统没有对应组件（05 §6.3） |
| ② | **批量操作条**（选择模式） | `GlassEffectContainer(spacing: 12)` 包住“已选 N 个”计数胶囊和 2–3 个操作按钮，各自 `.glassEffect(.regular.interactive())`；全 App **唯一的着色玻璃**是这里的主操作，用 `.glassEffect(.regular.tint(Theme.Brand.accent).interactive())`；容器使用 `ConcentricRectangle` 与屏幕底角同心 | 选择模式下用 `.toolbarVisibility(.hidden, for: .tabBar)` 隐藏 Tab 栏，**避免玻璃叠在玻璃上**（“glass can not sample other glass”，03 §1.10） |

### 5.3 着色规则

1. 玻璃**从不使用语义色着色**：不会出现红色或琥珀色的玻璃。状态色只出现在玻璃内部的图标和文字上。
2. 着色玻璃只用于“下一步主操作”，颜色固定为 `Brand.accent`，每屏最多 1 个。
3. 破坏性确认使用系统的 `role: .destructive`（系统红），不自绘红色玻璃。

### 5.4 深浅色下与内容的分离

- **浅色**：暖纸底让玻璃略带暖调，与纸面协调。内容区没有大面积饱和色（批注底是低彩度 wash；图表是细线，面积填充 ≤10% 不透明度），所以不会再出现“品红柱状图把 Tab 栏染红”的问题（05 §4.9）。
- **深色**：墨底 `#13161C` 不是纯黑，玻璃的高光边缘依然可见。浮条内的文字使用 `Ink.primary`，系统会让玻璃自动适配。
- **图表不贴底**：图表卡与 Tab 栏之间至少隔一个分区，滚动边缘使用系统默认的 `.soft`。
- **减弱透明度**（`accessibilityReduceTransparency`）：系统玻璃自动变得不透明。两处自定义玻璃降级为 `.background(Theme.Paper.sheet, in: .capsule)` 加 `Paper.ruleStrong` 发丝描边。

---

## 6. 图标与插画

### 6.1 SF Symbols 规则

- **渲染模式**：列表行首的状态符号用 `.symbolRenderingMode(.hierarchical)` 加色调色；印章内部用单色（monochrome）加 `.symbolVariant(.fill)` 的实心版；工具栏图标保持系统单色（HIG：tint 只用于表达含义）。
- **字重**：符号字重跟随相邻文字。行首符号 `.fontWeight(.medium)`，印章内 `.semibold`，用 `.imageScale(.small)` 与 12pt 文字匹配。
- **尺寸**：行首图标列固定 22pt 宽，使用 `@ScaledMetric` 跟随字号缩放。
- **动效符号**（iOS 26 / SF Symbols 7）：写入成功时对勾用 `.symbolEffect(.drawOn)` 画出一次；状态切换用 `.contentTransition(.symbolEffect(.replace))`。**页面上不放常驻循环动画**（不用 `.pulse`、`.breathe`）。

### 6.2 状态符号集

| 状态 | 符号 | 色调 | 批注线 |
|---|---|---|---|
| 正常 | `checkmark.circle` | ok | — |
| 限流中（429） | `hourglass` | caution | 虚线 |
| 临时不可调度 | `clock.badge.exclamationmark` | caution | 虚线 |
| 配额超限 / 接近上限 | `gauge.with.dots.needle.100percent` | caution | 虚线 |
| 即将过期 | `calendar.badge.exclamationmark` | caution | 虚线 |
| 错误 | `exclamationmark.octagon` | critical | 实线 |
| 过载中（529） | `thermometer.high` | critical | 实线 |
| 积分耗尽 | `creditcard.trianglebadge.exclamationmark` | critical | 实线 |
| 模型级限流 | `brain` | model | 点线 |
| 暂停（调度关闭） | `pause.circle` | neutral | — |
| 停用 / 禁用 | `minus.circle` / `nosign` | neutral | — |
| 未知 / 未返回 | `questionmark.circle` | neutral | — |
| 渠道可用 / 性能下降 / 不可用 | `dot.radiowaves.left.and.right` / `tortoise` / `antenna.radiowaves.left.and.right.slash` | ok / caution / critical | — / 虚 / 实 |
| 告警中 / 已恢复 / 手动已解决 | `bell.badge` / `checkmark.seal` / `person.fill.checkmark` | critical 或 caution / ok / neutral | 实或虚 / — / — |
| 写入成功 / 被拒绝 / 未执行 / **待核对** | `checkmark.circle.fill` / `xmark.octagon` / `minus.circle` / `doc.text.magnifyingglass` | ok / critical / neutral / caution | — / 实 / — / 虚 |

规则：**同一状态在全 App 只用一个符号**；符号与 `Theme.style(for:)` 一一绑定（§10），视图不能自己选符号。

### 6.3 插画

不做插画，也不用吉祥物。空态使用 `ContentUnavailableView`，配一个 SF Symbol 和一行业务文案，例如“今天还没有需要处理的事”配 `checkmark.seal`，符号为 ok 色调。“全部正常”时，首页的待处理区折叠成一行带“核”字印章的文字：`✓ 已核 · 3 分钟前检查`。

### 6.4 App 图标概念

- **构图**（Icon Composer 三层，iOS 26 图标会自动获得玻璃高光）：
  1. **背景层**：蓝黑墨色 `#16294A` 到 `#0E1A30` 的纵向微渐变。
  2. **中间层**：一张略微右倾（约 −6°）的暖纸 `#F4F0E7` 账页，占画面约 62%，上面印着两条浅蓝横格线，左侧有一条朱色竖向页边线。这是传统会计账页的“蓝格朱边”。
  3. **前景层**：一笔蓝黑墨水写成的“✓”（核讫勾），从页边线左侧起笔、越过页边线收笔，收笔处有一个小墨点。
- **深色图标**：背景改为更深的墨色，账页降亮到 `#2A2F38`，勾改为纸色。
- **着色（tinted）图标**：只保留账页轮廓和勾的单色剪影。
- **含义**：账页代表账务，勾代表核对，越过页边线象征“异常已被批注处理”。图标里不出现字母，也不沿用 Sub2 的“S”（简报：视觉身份完全开放）。
- 现有图标是青绿底白色 S（05 §4.7），替换后主色与 `Brand.accent` 同源。

---

## 7. 数据可视化（Swift Charts）

### 7.1 配色与线型

| 系列 | 颜色 | 线型 | 说明 |
|---|---|---|---|
| 实际（金额趋势主线） | `Money.actual.fill` | 2pt 实线，`.interpolationMethod(.monotone)` | 线下面积用同色，不透明度从 10% 渐变到 0 |
| 成本 | `Money.cost.fill` | 1.5pt 实线 | — |
| 标准 | `Money.standard.fill` | 1pt 虚线 `[3,3]` | **三口径同时靠线型区分，不只靠颜色** |
| 请求量、Token（非金额单系列） | `Brand.accent`（数据墨） | 2pt 实线或柱 | — |
| 对比期（昨日同时段） | `Ink.tertiary` | 1pt 虚线 `[2,3]` | — |
| 失败请求（堆叠柱上段） | `Tone.critical.fill` | — | 成功部分用 `Brand.accent` 的 70% 不透明度 |
| Token 构成（输入、输出、缓存读、缓存写） | 墨水蓝 4 级明度阶梯：浅色为 `#1A4580`、`#4A6FA5`、`#7F9CC4`、`#B4C6DE` | 堆叠面积或柱 | 在图上直接标名称，不用图例 |
| 告警阈值 | `Tone.caution.fill` | 1pt 虚线 `RuleMark`，行尾标注“告警线 5%” | — |

### 7.2 网格、坐标与标注

- 只画水平网格：`AxisGridLine(stroke: StrokeStyle(lineWidth: hairline))`，颜色 `Paper.rule`。不画竖向网格。零基线 1pt，颜色 `Paper.ruleStrong`。
- Y 轴放在右侧（`AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))`），只用数字，单位写在图表标题里（“实际收入（美元）”，HIG Charts）。X 轴 4 个刻度（`00:00 06:00 12:00 18:00`）。坐标字体用 `axis`，并用 `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` 限制坐标的最大字号（只限坐标，03 §5.4）。
- **结论先行**：图表卡的标题写结论（“今日实际 $1,284.50，比昨日同时段 ↑ 8.2%”）。比较值“昨日同时段”由已接入的 `dashboard/trend` 小时数据（含昨日）在客户端累加得到；缺少昨日数据时不显示比较，不补零。
- **直接标注**：在线尾放 `PointMark`（3pt）和 `.annotation(position: .trailing)`，写“实际 $96”，替代图例。
- 柱状图从 0 起，柱宽 `.width(.ratio(0.6))`，顶部圆角 1.5（`BarMark(...).cornerRadius(1.5)`）。

### 7.3 选中态

- 使用 `chartXSelection(value: $selectedDate)`（iOS 17），整个绘图区都可以点或拖。
- 选中时画一条 1pt 的 `Ink.secondary` 竖向 `RuleMark`，各系列在该点放 4pt `PointMark`，带 1.5pt `Paper.sheet` 描边。
- 浮签：`Paper.sheet` 底、`Radius.field`、发丝描边。时间用 `caption`，各口径金额用 `ledgerFigureSmall` 加口径色。浮签用 `.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled))` 防止越界。
- 选中点变化时触发 `.sensoryFeedback(.selection, trigger: selectedDate)`。
- 无障碍：提供 `accessibilityChartDescriptor`（音频图表），每个标记设置 `accessibilityLabel` 和 `accessibilityValue`。保留“逐小时明细”列表作为替代视图。

### 7.4 迷你趋势

- 高 28pt（`@ScaledMetric`），宽 96pt。1.5pt 线，金额趋势用 `Money.actual.fill`，计量趋势用 `Ink.secondary`。最后一个点 3pt。`.chartXAxis(.hidden).chartYAxis(.hidden)`，不交互，`accessibilityHidden(true)`（数值已经由相邻的大数字表达）。
- **只放在首页账面大数和账号详情的“今日”旁边**，列表行里不放（避免噪声，影响密度）。

### 7.5 容量与配额条

- 6pt 高（`@ScaledMetric(relativeTo: .footnote)`），`Radius.bar`，轨道 `Paper.track`。
- 填充色按 `Theme.capacityLevel` 决定：0 只显示轨道；<75% 用 `Brand.accent`；≥75% 用 `caution.fill`；≥90% 或满额用 `critical.fill`。
- **数值始终以文字放在条的右侧**（`measure` 字体，金额用 `ledgerFigureSmall`），所以条本身对 VoiceOver 隐藏。
- 多个窗口（并发、RPM、日/周/总配额、5h/7d 会话窗口）在详情页按行对齐：标签列固定宽度，条和数值左对齐。
- 超出上限时整条填满 `critical.fill`，并在数值后加一枚“超限”印章。

---

## 8. 动效与触觉

### 8.1 动效

| 场景 | 动效 | 减弱动态效果时 |
|---|---|---|
| 导航、sheet | 系统默认 | 系统处理 |
| 数字刷新（账面大数、计数） | `.contentTransition(.numericText(value:))` + `.animation(.snappy(duration: 0.3), value:)` | `.contentTransition(.opacity)`，交叉淡入 |
| 状态切换（例如暂停 → 正常） | 印章 `.contentTransition(.symbolEffect(.replace))`；批注线“落笔”：从上往下伸展 0.25s，easeOut | 直接出现或消失 |
| 写入成功 | 对勾 `.symbolEffect(.drawOn)` 一次 | 静态对勾 |
| 倒计时 | `Text(timerInterval:)` 逐秒更新，无额外动画 | 不变（文字更新不属于动态效果） |
| 新日志插入 | `.transition(.move(edge: .top).combined(with: .opacity))` | 仅 `.opacity` |
| 回执浮条 | 从 Tab 栏上方滑入 8pt 加淡入，使用 `.smooth` | 仅淡入 |
| 下拉刷新 | 系统 `.refreshable`；刷新后副标题改为“刚刚更新” | 同 |
| 告警或异常 | **不闪烁、不脉冲**。依靠批注线和印章的静态对比 | 同 |

读取方式：`@Environment(\.accessibilityReduceMotion)`。

### 8.2 触觉（`.sensoryFeedback`，iOS 17）

| 事件 | 反馈 |
|---|---|
| 单对象写入成功（停止/启用调度、解除限流、标记已处理）；资金写入成功；批量全部成功 | `.success` |
| 写入被拒绝、网络失败、测试失败 | `.error` |
| 结果待核对、批量部分成功、需要二次验证、**手动下拉刷新后待处理数增加** | `.warning` |
| 选择筛选胶囊、切换分段、图表选点、多选勾选 | `.selection` |
| 复制请求 ID 或 Key | `.impact(flexibility: .soft, intensity: 0.6)` |
| 点“撤销” | `.impact(weight: .medium)` |
| 30 秒自动轮询的结果变化 | **无**（后台变化不打扰手指） |

触觉不受“减弱动态效果”影响，遵循系统的“系统触感反馈”开关。

---

## 9. 三个样屏

> 画布为 iPhone 17 Pro（402×874pt），浅色、默认字号。`┃` 表示实线批注（critical），`┆` 表示虚线批注（caution）。图中的 Tab 集合只作示意，最终以信息架构稿为准。

### 9.1 首页「今日账页」

```
┌──────────────────────────────────────────────┐
│ 9:41                                 ▮▮▮ ◔  │
│ (◐ 东京站 ⌄)                       (⟳) (···) │ ①
│ 概览                                          │ ②
│ 周五 10月16日 · 2 分钟前更新                    │ ③
│                                              │
│ 壹  待处理 ─────────────────────────────── 3 │ ④
│┃ ⛔错误    OpenAI-备用-A                    › │ ⑤
│┃           401 凭据失效 · 6 分钟前              │
│┆ ⏳限流中  Claude-官方-03             8:32  › │ ⑥
│┆           12:41 自动恢复 · 另有 2 个模型限流     │
│┃ 🔔告警中  分组「高级」可用账号低于 50%    P1 › │ ⑦
│   查看全部待处理                               │ ⑧
│                                              │
│ 贰  今日账目 ───────────────────────────────  │ ④
│ 实际                                          │ ⑨
│ $1,284.50                       ╱╲_╱‾‾•      │ ⑩
│ 比昨日同时段 ↑ 8.2%                             │ ⑪
│ ──────────────────────────────────────────── │
│ 成本            标准             差额          │ ⑫
│ $512.08         $1,610.00        +$772.42    │
│ ════════════════════════════════════════════ │ ⑬
│ 请求 18,204      Tokens 96.4M      RPM 212   │ ⑭
│                                              │
│ 叁  趋势 · 实际收入（美元）   (实际 ⌄)(24 小时 ⌄)│ ⑮
│                                         120  │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╱╲┄┄┄┄┄┄╱‾‾╲•  80   │ ⑯
│  ┄┄┄┄┄╱‾╲__╱┄┄┄┄╲_╱┄┄┄┄┄┄┄┄┄┄┄┄ 实际 $96 40 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  0   │
│  00:00     06:00     12:00     18:00         │
│                                              │
│ 肆  运行 ─────────────────────────────────── │ ④
│ 健康分 92 健康 · 错误率 0.8% · 上游错误 1.9%     │ ⑰
│ 账号  可用 41 · 限流 3 · 错误 1             ›  │ ⑱
│ 渠道  可用 7 · 性能下降 1                   ›  │ ⑲
╰─( 概览 │ 账号 │ 日志 │ 用户 )───────( ⌕ )──╯ ⑳
```

| # | 元素 | 字体 | 颜色 | 尺寸与间距 | 数据与备注 |
|---|---|---|---|---|---|
| ① | 站点标题菜单、刷新、更多 | 系统 | 系统玻璃，图标单色 | 系统 | `.toolbarTitleMenu` 切换站点；字母头像用 `count` 字体加 `Brand.wash` 圆底；站点 Logo 需要解码 `settings/public` 的 `site_logo`（05 §4.12） |
| ② | 大标题 | 系统 largeTitle | 系统 | 系统 | 不覆盖系统字体 |
| ③ | 日期与新鲜度 | 系统副标题 | 系统次级色 | — | `.navigationSubtitle`（iOS 26）；只有这一处显示更新时间（C17） |
| ④ | 页眉“壹 待处理 ── 3” | `sectionLabel`；页序“壹”同字体 | 页序 `Ink.tertiary`；标题 `Ink.secondary`；计数用 `count` | 上 24（首个为 12）、下 8；线条用 `Paper.rule` | 大写数字页序**只在首页和详情页使用**，`accessibilityHidden(true)`；辅助功能字号下隐藏 |
| ⑤ | 错误批注行 | 印章 `stamp`；名称 `rowTitle`；第二行 `annotation` | 实线批注 `critical.fill` 3pt；印章 `critical` + wash；名称 `Ink.primary`；第二行 `critical` 前景色 | 两行，行高约 61；页边栏 8；图标列 22 | 来源：账号 `status=error` 加 `errorMessage`（已解码），经 `RequestLogPresentation.safeMessage` 脱敏 |
| ⑥ | 限流批注行 | 同上；倒计时用 `measure` | 虚线批注 `caution.fill`；倒计时 `caution` 前景色 | 同上 | **需要新接入**：解码 `rate_limit_reset_at`、`extra.model_rate_limits`（02 §3.1 C，后端已下发，Sub2Core 未解码） |
| ⑦ | 告警行 | 同上；“P1”使用印章样式 | P0/P1 为实线 critical，P2/P3 为虚线 caution | 同上 | **需要新接入**：`GET admin/ops/alert-events?status=firing`（02 §1.1）。告警只能定位到分组或平台（02 §3.8），点入进入分组下的异常账号 |
| ⑧ | 查看全部 | `subheadline` | `Brand.accent` | 44pt 点击区 | 待处理超过 3 项时出现 |
| ⑨ | 标签“实际” | `caption` | `Ink.tertiary` | — | — |
| ⑩ | 账面大数与迷你趋势 | `ledgerDisplay` | 数字 `Ink.primary`；迷你线 `Money.actual.fill` | 大数与迷你图底对齐；迷你图 28×96 | 已接入：`dashboard/stats`（Web 仪表盘同源三口径） |
| ⑪ | 比较 | `footnote` + `arrow.up` 符号 | `Ink.secondary`（**不用红绿**） | — | 由已接入的 `dashboard/trend` 在客户端计算 |
| ⑫ | 三口径栏 | 标签 `caption`；数字 `ledgerTitle` | `Money.cost`、`Money.standard`；差额 `Ink.primary` | 三等分 `Grid`；数字右对齐 | “差额＝实际 − 成本”，口径说明放在 ⓘ 里（C70） |
| ⑬ | 合计双线 | — | `Paper.ruleStrong` | 2 条发丝线，间隔 2；上下各 8 | 全屏唯一一处双线 |
| ⑭ | 计量行 | 标签 `caption`；数字 `measure` | 标签 `Ink.tertiary`；数字 `Ink.primary` | 三等分 | 已接入 |
| ⑮ | 图表页眉与两个菜单胶囊 | `sectionLabel`；胶囊用系统 bordered | 胶囊 `.tint(Ink.secondary)` | — | 指标菜单：实际收入、请求、Tokens、RPM |
| ⑯ | 趋势图 | `axis` | 主线 `Money.actual.fill` 2pt；昨日 `Ink.tertiary` 虚线；网格 `Paper.rule` | 高 160；Y 轴在右 | §7；整个绘图区可选 |
| ⑰ | 运行概况 | `measure` + 印章“健康” | 健康分按 Web 阈值（≥90 ok、60–89 caution、<60 critical） | — | `health_score` **需要解码**：`ops/dashboard/overview` 已接入，但只取了 `error_rate`、`qps`（02 §1.1） |
| ⑱ | 账号计数 | `measure` | 数字为墨色；“限流”“错误”后各带一个对应色调的 6pt 圆点 | 行 44 | 已接入：`dashboard/stats` 的 `ratelimit_accounts`、`error_accounts`；点击后带筛选进入账号 Tab |
| ⑲ | 渠道 | 同上 | 同上 | — | **需要新接入**：`channel-monitor-v2/overview`，受站点功能开关控制，开关关闭时整行不出现（02 §1.4、§1.6） |
| ⑳ | Tab 栏 | 系统 | 系统玻璃 | — | `Tab(...)` 新 API；`tabItem` 在 27.2 弃用 |

“全部正常”时，壹区折叠为一行：`✓ 已核 · 3 分钟前检查`（ok 色调印章，无批注线）。

### 9.2 账号列表（全部视图，按紧急程度排序）

```
┌──────────────────────────────────────────────┐
│ (◐ 东京站 ⌄)                      (选择) (⇅) │ ①
│ 账号                                          │
│ (需处理 2)(全部 52)(限流 1)(平台 ⌄)(分组 ⌄) →  │ ②
│ 需处理 · 2 ───────────────────────────────── │ ③
│┃ ⛔ OpenAI-备用-A                      $0.00 │ ④
│┃    OpenAI · API Key · 标准分组     并发 0 / 4 │
│┃    错误 · 401 Incorrect API key provided…   │
│  ────────────────────────────────────────── │ ⑤
│┆ ⏳ Claude-官方-03                     $48.20 │ ⑥
│┆    Anthropic · OAuth · 高级   ▰▰▰▱  3 / 4    │
│┆    限流中 · 12:41 恢复 · 还剩 8:32            │
│ 已暂停 · 停用 · 1 ─────────────────────────── │ ③
│  ⏸ Gemini-测试-B                      $3.10 │ ⑦
│     Gemini · API Key · 未分组        [⏸ 暂停] │
│ 正常 · 49 ────────────────────────────────── │ ③
│  ✓ Claude-官方-01                   $102.44 │ ⑧
│     Anthropic · OAuth · 高级   ▰▰▱▱  2 / 4    │
│  ────────────────────────────────────────── │
│  ✓ Claude-官方-02                    $96.10 │
│     Anthropic · OAuth · 高级   ▰▱▱▱  1 / 4    │
│  ────────────────────────────────────────── │
│  ✓ OpenAI-主力-01                    $77.35 │
│     OpenAI · API Key · 标准     ▰▰▱▱  2 / 4  │
│  ────────────────────────────────────────── │
│  ✓ Kimi-01                            $12.08 │
│     Kimi · API Key · 标准       ▰▱▱▱  1 / 4  │
╰─( 概览 │ 账号 │ 日志 │ 用户 )───────( ⌕ )──╯
```

按 §4.4 的行高推算：页眉 30 + 2×82 + 页眉 40 + 暂停行 61 + 页眉 40 = 335pt，剩余约 295pt 可放 4 个完整的正常行，再露出第 5 个约 80%。所以本屏是 **7 个完整账号，第 8 个大部分可见**（ASCII 图因字符宽度只画到第 7 个）。

| # | 元素 | 字体 | 颜色 | 尺寸与间距 | 数据与备注 |
|---|---|---|---|---|---|
| ① | 工具栏 | 系统 | 系统玻璃 | — | “选择”进入多选（`List(selection:)` + `EditMode`）；`⇅` 是排序菜单（默认“需处理优先”，04 §4.2 #2）；“显示字段”放进 `···` 菜单，不再占用筛选图标（D24） |
| ② | 筛选胶囊条 | 文字 `subheadline`；计数 `count` | 选中：`borderedProminent` + `Brand.accent`，白字；未选：`bordered` + `Ink.secondary` | 胶囊高 32，点击区 44；间距 8；可横向滚动 | 放在 `.safeAreaBar(edge: .top)`；状态选项与 Web 一一对应（04 §4.1 #8）；计数来自 `dashboard/stats` 与列表筛选 |
| ③ | 分组页眉 | `sectionLabel` + 计数 | `Ink.secondary`；线 `Paper.rule` | 上 16、下 6 | 列表里不用大写页序；分组只在“全部”视图里出现 |
| ④ | 错误行 | 名称 `rowTitle`；金额 `ledgerFigure`；第二行 `rowMeta` 与 `measure`；第三行 `annotation` | 实线 `critical.fill`；符号与第三行 `Tone.critical`；金额 `Ink.primary` | 行高约 82；页边栏 8；图标列 22；第二、三行与名称左对齐 | 金额是今日实际（`today-stats/batch`，已接入）；错误摘要来自 `errorMessage`，经 `safeMessage` 脱敏，`.lineLimit(1)` |
| ⑤ | 分隔线 | — | `Paper.rule` 发丝线 | 从文字列开始（`alignmentGuide(.listRowSeparatorLeading)`） | — |
| ⑥ | 限流行 | 同上；倒计时用 `Text(timerInterval:)` | 虚线 `caution.fill`；容量条 75% 用 `caution.fill` | 同上 | **需要新接入**：`rate_limit_reset_at`；倒计时归零后，下一次刷新时行会移到“正常”分组 |
| ⑦ | 暂停行 | 同上，只有两行；状态用 `LedgerStamp` | **无批注线**；符号与印章 `Tone.neutral` | 约 61 | `schedulable=false`；印章占据元信息行右侧原本放容量的位置（暂停时容量没有参考意义） |
| ⑧ | 正常行 | 同上，只有两行 | 符号 `Tone.ok`（hierarchical）；容量条 `Brand.accent` | 约 61 | 第二行右侧只放**最紧张的一项**容量（03 P19），不再串联 8 项 |

**行内交互**（外观按本方向，确认分级按简报 §3.5）：

- 前导滑动：`停止调度` / `启用调度`，`.tint(Theme.Brand.accent)`，`allowsFullSwipe: false`（03 P13）。
- 尾随滑动：`恢复`（**需要新接入**：`POST :id/clear-rate-limit`、`DELETE :id/temp-unschedulable`、`POST :id/clear-error`、`POST :id/recover-state`，按当前状态显示其中一个，02 §1.2）、`测试`。
- 不使用红色滑动按钮，因为这些都是可逆操作。

**深色模式下**：页底 `#13161C`，行文字 `#ECE7DC`，批注线为 `#E0574A` 和 `#D99A1E`，印章底为 `#33201E` 和 `#2E2614`，容量条轨道为 `#2A2F38`。

### 9.3 账号详情（Claude-官方-03，限流中）

```
┌──────────────────────────────────────────────┐
│ (‹)              Claude-官方-03     (测试)(···)│ ①
│                                              │
│ Claude-官方-03                                │ ②
│ Anthropic · OAuth · 高级分组 · 东京站           │ ③
│                                              │
│ ╭────────────────────────────────────────╮   │
│ ┆ ⏳ 限流中                         8:32   │   │ ④
│ ┆ 上游返回 429，12:41 自动恢复，恢复前不参与   │   │ ⑤
│ ┆ 调度。                                    │   │
│ ┆ 🧠 模型限流 · claude-opus-4 等 2 个        │   │ ⑥
│ ┆ ( 解除限流 )   ( 停止调度 )               │   │ ⑦
│ ╰────────────────────────────────────────╯   │
│                                              │
│ 壹  今日 ─────────────────────────────────── │ ⑧
│ 实际            成本            标准     ╱‾╲_• │
│ $48.20          $19.75          $61.30      │ ⑨
│ ════════════════════════════════════════════ │
│ 请求 1,204     Tokens 6.1M     首字 1.84s     │ ⑩
│                                              │
│ 贰  容量 ─────────────────────────────────── │
│ 并发        ▰▰▰▰▰▰▰▰▰▱▱▱       3 / 4       │ ⑪
│ RPM         ▰▰▰▰▰▰▰▱▱▱▱▱   37 / 60 近60秒  │
│ 日配额      ▰▰▱▱▱▱▱▱▱▱▱▱  $3.45 / $20.00    │
│ 5 小时窗口  ▰▰▰▰▰▰▰▰▰▰▱▱   82% 接近上限     │ ⑫
│                                              │
│ 叁  档案 ─────────────────────────────────── │
│ 状态    正常            调度     参与          │ ⑬
│ 优先级  1               账号倍率 1.0×          │
│ 分组    高级 · 标准                            │
│ 代理    tokyo-03                           ›  │
│ 到期    2026-12-31                           │
│                                              │
│ 肆  记录 ─────────────────────────────────── │
│ 错误请求          近 24 小时 3 条            ›  │ ⑭
│ 请求记录                                    ›  │
│ 统计分析                                    ›  │
╰─( 概览 │ 账号 │ 日志 │ 用户 )───────( ⌕ )──╯
```

| # | 元素 | 字体 | 颜色 | 尺寸与间距 | 数据与备注 |
|---|---|---|---|---|---|
| ① | 工具栏 | 系统 | 系统玻璃 | — | 行内标题在滚过 ② 后出现；“测试”打开测试 sheet（流式输出用 `codeBody`，`Paper.sunken` 底）；`···` 里放刷新凭据和编辑（少量安全字段） |
| ② | 对象名 | `pageHeading` | `Ink.primary` | 页边距 16；上 8 | — |
| ③ | 身份行 | `rowMeta` | `Ink.secondary` | 下 16 | 平台和认证类型用显示名（04 §4.1 #10、#11），不显示原始枚举 |
| ④ | 批注卡头 | 印章 `stamp`；倒计时 `measureDisplay` | 卡底 `Paper.sheet`，发丝描边；虚线批注 `caution.fill` 4pt 贴卡片左缘；倒计时 `Tone.caution` | `Radius.card`；内边距 12/16 | **需要新接入**：`rate_limit_reset_at` |
| ⑤ | 批注正文 | `bodyText`（callout + lineSpacing 3） | `Ink.primary` | 最多 3 行 | 文案只说业务，不写契约（简报 §3.4） |
| ⑥ | 模型级限流 | `annotation` | `Tone.model` 前景色，`brain` 符号 | 点击展开模型清单（sheet，medium detent） | **需要新接入**：`extra.model_rate_limits` |
| ⑦ | 动作按钮 | 系统按钮字体 | `.buttonStyle(.bordered)` + `.tint(Brand.accent)`；**不用玻璃**（属于内容层） | 高 ≥44；间距 12 | “解除限流”需要新接入 `POST :id/clear-rate-limit`；“停止调度”已接入。两者的确认方式按简报 §3.5（可逆，直接执行 + 回执浮条可撤销）。正常账号没有批注卡，这一行按钮会上移到 ③ 下方 |
| ⑧ | 页眉 | `sectionLabel` | 同首页 | 上 24 | — |
| ⑨ | 今日三口径与迷你趋势 | `ledgerTitle` | `Money.actual/cost/standard`；迷你线 `Money.actual.fill` | 三等分 | 已接入 `:id/today-stats`；迷你趋势需要 `dashboard/trend?account_id=`（已接入接口，按账号筛选，02 §4） |
| ⑩ | 计量行 | `measure` | `Ink.primary`；“首字 1.84s”按 Web 延迟分档上色（<10s 墨色，10–60s caution，≥60s critical，04 §4.1 #14） | — | 已接入 |
| ⑪ | 容量条组 | 标签 `subheadline`；数值 `measure`；金额 `ledgerFigureSmall` | 条 75% 用 `caution.fill`，<75% 用 `Brand.accent` | 标签列固定 88pt（`@ScaledMetric`），条高 6；行高 36 | 并发、RPM 已接入；“近60秒”为 `caption` 的 `Ink.tertiary` |
| ⑫ | 会话窗口 | 同上 + “接近上限”文字 | `caution` | — | **需要新接入**：`GET admin/accounts/:id/usage`（02 §1.2），按需加载 |
| ⑬ | 档案键值网格 | 键 `subheadline` + `Ink.tertiary`；值 `subheadline` + `Ink.primary` | — | 两列 `Grid`；值**不再是灰色**（修复 D05） | 三层状态分开展示：持久状态“正常”、调度“参与”、运行时阻断已在 ④ 呈现（02 §3.1 C 的推断模型） |
| ⑭ | 记录链接 | `body` | `Ink.primary`；计数 `measure` | 行 44 | 进入日志时直接定位到“错误请求”页签，并带上账号筛选（修复 D03） |

---

## 10. SwiftUI 设计令牌代码

> 建议位置：`NativeApp/DesignSystem/LedgerTheme.swift`（本轮未创建任何源码）。目标为 iOS 26、Swift 6 严格并发。
> 【推断】本文件在 Windows 上编写，**尚未用 Xcode 27 编译**，下一轮在 Mac 上用 `xcodebuild` 验证。所用 API 均为 iOS 13–17 的稳定 API；`ConcentricRectangle`、`.glassEffect` 只在正文中出现，不在本文件里。
> 生产环境可以把颜色迁移到 Asset Catalog 的 colorset（Any / Dark × High Contrast），便于 Xcode 预览和设计交接；本文件作为原型阶段的单一事实源。

```swift
import SwiftUI
import UIKit

// MARK: - 四态动态色（浅 / 深 × 标准 / 增强对比度）

extension Color {
    /// 「核簿」动态色。参数为 0xRRGGBB；未提供增强对比度色值时沿用标准色值。
    static func ledger(
        _ light: UInt32,
        _ dark: UInt32,
        highContrastLight: UInt32? = nil,
        highContrastDark: UInt32? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let hex: UInt32 = switch (isDark, isHighContrast) {
            case (false, false): light
            case (false, true): highContrastLight ?? light
            case (true, false): dark
            case (true, true): highContrastDark ?? dark
            }
            return UIColor(ledgerHex: hex)
        })
    }
}

private extension UIColor {
    convenience init(ledgerHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Theme

enum Theme {

    // MARK: 纸与线
    enum Paper {
        static let canvas = Color.ledger(0xF4F0E7, 0x13161C, highContrastLight: 0xF8F6F0, highContrastDark: 0x0B0D11)
        static let sheet = Color.ledger(0xFBF9F4, 0x1B1F27, highContrastLight: 0xFFFFFF, highContrastDark: 0x14171D)
        static let sunken = Color.ledger(0xEDE8DC, 0x0E1015, highContrastLight: 0xEFEBE1, highContrastDark: 0x07080B)
        static let track = Color.ledger(0xE8E2D6, 0x2A2F38, highContrastLight: 0xDDD6C7, highContrastDark: 0x2E333D)
        static let rule = Color.ledger(0xDCD3C2, 0x2B303A, highContrastLight: 0x9E937D, highContrastDark: 0x4A505C)
        static let ruleStrong = Color.ledger(0xB3A891, 0x454B57, highContrastLight: 0x6F6656, highContrastDark: 0x6B7280)
    }

    // MARK: 墨色文字
    enum Ink {
        static let primary = Color.ledger(0x1C2230, 0xECE7DC, highContrastLight: 0x0B0F18, highContrastDark: 0xFBF8F1)
        static let secondary = Color.ledger(0x4C5260, 0xB9B3A8, highContrastLight: 0x2F3440, highContrastDark: 0xDAD5CB)
        static let tertiary = Color.ledger(0x60646D, 0x948F86, highContrastLight: 0x3F434C, highContrastDark: 0xC0BBB1)
        /// 仅用于禁用控件和占位符（WCAG 对禁用状态豁免对比度要求）
        static let disabled = Color.ledger(0x9C978D, 0x5E5B55)
    }

    // MARK: 品牌（蓝黑墨水）
    enum Brand {
        static let accent = Color.ledger(0x1A4580, 0x86AEE8, highContrastLight: 0x143B6E, highContrastDark: 0xAFCDF7)
        static let onAccent = Color.ledger(0xFFFFFF, 0x0E1A2E, highContrastLight: 0xFFFFFF, highContrastDark: 0x0A1424)
        static let wash = Color.ledger(0xE2E8F1, 0x1E2A3D, highContrastLight: 0xDCE4F0, highContrastDark: 0x1F2C42)
    }

    // MARK: 语义色调（含义与简报一致，不得挪作他用）
    enum Tone: Sendable, CaseIterable {
        case ok        // 正常
        case caution   // 限流 / 临时 / 接近上限 / 待核对
        case critical  // 错误 / 过载 / 不可用
        case neutral   // 停用 / 暂停 / 未知
        case model     // 模型级限流

        /// 文字与图标：对所有纸面 ≥ 4.5:1
        var foreground: Color {
            switch self {
            case .ok: Palette.okText
            case .caution: Palette.cautionText
            case .critical: Palette.criticalText
            case .neutral: Palette.neutralText
            case .model: Palette.modelText
            }
        }

        /// 条形、图表线、批注线：对纸面与轨道 ≥ 3:1
        var fill: Color {
            switch self {
            case .ok: Palette.okFill
            case .caution: Palette.cautionFill
            case .critical: Palette.criticalFill
            case .neutral: Palette.neutralFill
            case .model: Palette.modelFill
            }
        }

        /// 印章底色
        var wash: Color {
            switch self {
            case .ok: Palette.okWash
            case .caution: Palette.cautionWash
            case .critical: Palette.criticalWash
            case .neutral: Palette.neutralWash
            case .model: Palette.modelWash
            }
        }

        /// 只给需要人处理的状态画页边批注线
        var isAnnotated: Bool { self == .caution || self == .critical || self == .model }

        /// 批注线线型：实线＝持续性故障；虚线＝时间窗、会自动恢复；点线＝模型级
        var marginDash: [CGFloat] {
            switch self {
            case .critical: []
            case .caution: [4, 3]
            case .model: [2, 3]
            case .ok, .neutral: []
            }
        }
    }

    // MARK: 成本三口径（实际 / 成本 / 标准）
    enum Money: Sendable, CaseIterable {
        case actual, cost, standard

        var label: String {
            switch self {
            case .actual: "实际"
            case .cost: "成本"
            case .standard: "标准"
            }
        }

        var foreground: Color {
            switch self {
            case .actual: Palette.actualText
            case .cost: Palette.costText
            case .standard: Palette.standardText
            }
        }

        var fill: Color {
            switch self {
            case .actual: Palette.actualFill
            case .cost: Palette.costFill
            case .standard: Palette.standardFill
            }
        }

        /// 图表线型：三口径不只靠颜色区分
        var chartStroke: StrokeStyle {
            switch self {
            case .actual: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            case .cost: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            case .standard: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3])
            }
        }
    }

    private enum Palette {
        static let okText = Color.ledger(0x2E6A3E, 0x82C493, highContrastLight: 0x1C4F2A, highContrastDark: 0xA3DDB1)
        static let okFill = Color.ledger(0x3B8550, 0x5FAE73, highContrastLight: 0x25693A, highContrastDark: 0x77C48A)
        static let okWash = Color.ledger(0xE2EDDE, 0x1A2A1F, highContrastLight: 0xDCEAD7, highContrastDark: 0x16261B)

        static let cautionText = Color.ledger(0x8A5400, 0xE9B44C, highContrastLight: 0x623A00, highContrastDark: 0xF6CA6E)
        static let cautionFill = Color.ledger(0xAD7006, 0xD99A1E, highContrastLight: 0x8F5B00, highContrastDark: 0xEBB03E)
        static let cautionWash = Color.ledger(0xF6E8CA, 0x2E2614, highContrastLight: 0xF3E2BE, highContrastDark: 0x2C2310)

        static let criticalText = Color.ledger(0x9C1F16, 0xF2867A, highContrastLight: 0x871A12, highContrastDark: 0xFFA69B)
        static let criticalFill = Color.ledger(0xC2342A, 0xE0574A, highContrastLight: 0xA2251B, highContrastDark: 0xF06A5C)
        static let criticalWash = Color.ledger(0xF6E0DB, 0x33201E, highContrastLight: 0xF4D9D3, highContrastDark: 0x331B19)

        static let neutralText = Color.ledger(0x5B6068, 0xA9ACB2, highContrastLight: 0x3F434A, highContrastDark: 0xC6C9CE)
        static let neutralFill = Color.ledger(0x7A7F87, 0x7B8088, highContrastLight: 0x5E636B, highContrastDark: 0x9A9EA6)
        static let neutralWash = Color.ledger(0xE7E4DD, 0x24272D, highContrastLight: 0xE2DFD7, highContrastDark: 0x22252B)

        static let modelText = Color.ledger(0x7448A8, 0xC8A6F0, highContrastLight: 0x4E2780, highContrastDark: 0xD4BFF6)
        static let modelFill = Color.ledger(0x8760C0, 0xA47FDD, highContrastLight: 0x6A43A3, highContrastDark: 0xB293E6)
        static let modelWash = Color.ledger(0xECE4F3, 0x272035, highContrastLight: 0xE6DCF1, highContrastDark: 0x251D33)

        static let actualText = Color.ledger(0x1E6B57, 0x74C9AC, highContrastLight: 0x134D3E, highContrastDark: 0x95DCC3)
        static let actualFill = Color.ledger(0x2A836A, 0x3FA585, highContrastLight: 0x1D6652, highContrastDark: 0x55BB98)
        static let costText = Color.ledger(0xA3431A, 0xF29A62, highContrastLight: 0x7C2E0D, highContrastDark: 0xF8B488)
        static let costFill = Color.ledger(0xC0561F, 0xE07A3E, highContrastLight: 0x9C4114, highContrastDark: 0xEE8F55)
        static let standardText = Color.ledger(0x635E54, 0xABA597, highContrastLight: 0x45413A, highContrastDark: 0xC7C1B4)
        static let standardFill = Color.ledger(0x827C70, 0x857F73, highContrastLight: 0x6C665B, highContrastDark: 0x9F998C)
    }

    // MARK: 字体（全部基于 Text Style，跟随 Dynamic Type；含数字者已带等宽数字）
    enum Typeface {
        // 金额：New York
        static var ledgerDisplay: Font { .system(.largeTitle, design: .serif, weight: .semibold).monospacedDigit() }
        static var ledgerTitle: Font { .system(.title2, design: .serif, weight: .semibold).monospacedDigit() }
        static var ledgerFigure: Font { .system(.body, design: .serif, weight: .medium).monospacedDigit() }
        static var ledgerFigureSmall: Font { .system(.subheadline, design: .serif).monospacedDigit() }
        // 计量：SF Pro
        static var measureDisplay: Font { .system(.title2, weight: .semibold).monospacedDigit() }
        static var measure: Font { .system(.subheadline, weight: .medium).monospacedDigit() }
        // 文字骨架（含中文时字重不超过 semibold）
        static var pageHeading: Font { .system(.title2, weight: .semibold) }
        static var rowTitle: Font { .system(.body, weight: .semibold) }
        static var rowMeta: Font { .subheadline.monospacedDigit() }
        static var bodyText: Font { .callout }
        static var annotation: Font { .footnote.weight(.medium).monospacedDigit() }
        static var sectionLabel: Font { .footnote.weight(.semibold) }
        static var stamp: Font { .caption.weight(.semibold) }
        static var caption: Font { .caption.monospacedDigit() }
        static var axis: Font { .caption2.monospacedDigit() }
        // 标识：SF Mono
        static var code: Font { .system(.footnote, design: .monospaced) }
        static var codeBody: Font { .system(.callout, design: .monospaced) }
        // 计数徽记：SF Pro Rounded
        static var count: Font { .system(.footnote, design: .rounded, weight: .semibold).monospacedDigit() }
    }

    // MARK: 间距（4pt 网格）
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16      // 页边距
        static let xl: CGFloat = 24     // 分区间距
        static let xxl: CGFloat = 32
        static let rowVertical: CGFloat = 8       // 账号、用户、分组列表行
        static let logRowVertical: CGFloat = 10   // 日志行
        static let marginLane: CGFloat = 8        // 页边批注栏
        static let iconColumn: CGFloat = 22
    }

    // MARK: 圆角（一律 .continuous）
    enum Radius {
        static let stamp: CGFloat = 4
        static let bar: CGFloat = 3
        static let field: CGFloat = 8
        static let card: CGFloat = 12
    }

    // MARK: 线宽
    enum Stroke {
        static let marginRule: CGFloat = 3
        static let marginRuleIncreased: CGFloat = 4
        static let chartPrimary: CGFloat = 2
        static let chartSecondary: CGFloat = 1.5
        static let chartReference: CGFloat = 1
        static let capacityBarHeight: CGFloat = 6
        static func hairline(displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) }
    }

    // MARK: 状态 → 外观映射（显示优先级由 Sub2Core 计算，这里只管外观）
    struct StatusStyle: Sendable, Equatable {
        let tone: Tone
        let symbol: String
        let label: String
    }

    enum Status: Sendable, Hashable {
        // 账号（术语照搬 04 §4.1）
        case accountNormal, accountInactive, accountError, accountOverloaded
        case accountRateLimited, accountTempUnschedulable, accountQuotaExceeded
        case accountExpiringSoon, accountCreditsExhausted, accountModelRateLimited, accountPaused
        // 用户 / 分组
        case userEnabled, userDisabled, groupActive, groupInactive
        // 渠道监控
        case channelAvailable, channelDegraded, channelUnavailable, channelUnknown
        // 告警 / 错误日志
        case alertFiring(isCritical: Bool), alertResolved, alertManuallyResolved
        case errorUnresolved, errorResolved
        // 写入结果
        case writeSucceeded, writeRejected, writeNotExecuted, writePendingReconcile
        case unknown
    }

    static func style(for status: Status) -> StatusStyle {
        switch status {
        case .accountNormal: StatusStyle(tone: .ok, symbol: "checkmark.circle", label: "正常")
        case .accountInactive: StatusStyle(tone: .neutral, symbol: "minus.circle", label: "停用")
        case .accountError: StatusStyle(tone: .critical, symbol: "exclamationmark.octagon", label: "错误")
        case .accountOverloaded: StatusStyle(tone: .critical, symbol: "thermometer.high", label: "过载中")
        case .accountRateLimited: StatusStyle(tone: .caution, symbol: "hourglass", label: "限流中")
        case .accountTempUnschedulable: StatusStyle(tone: .caution, symbol: "clock.badge.exclamationmark", label: "临时不可调度")
        case .accountQuotaExceeded: StatusStyle(tone: .caution, symbol: "gauge.with.dots.needle.100percent", label: "配额超限")
        case .accountExpiringSoon: StatusStyle(tone: .caution, symbol: "calendar.badge.exclamationmark", label: "即将过期")
        case .accountCreditsExhausted: StatusStyle(tone: .critical, symbol: "creditcard.trianglebadge.exclamationmark", label: "积分耗尽")
        case .accountModelRateLimited: StatusStyle(tone: .model, symbol: "brain", label: "模型限流")
        case .accountPaused: StatusStyle(tone: .neutral, symbol: "pause.circle", label: "暂停")
        case .userEnabled: StatusStyle(tone: .ok, symbol: "checkmark.circle", label: "启用")
        case .userDisabled: StatusStyle(tone: .neutral, symbol: "nosign", label: "禁用")
        case .groupActive: StatusStyle(tone: .ok, symbol: "checkmark.circle", label: "正常")
        case .groupInactive: StatusStyle(tone: .neutral, symbol: "minus.circle", label: "停用")
        case .channelAvailable: StatusStyle(tone: .ok, symbol: "dot.radiowaves.left.and.right", label: "可用")
        case .channelDegraded: StatusStyle(tone: .caution, symbol: "tortoise", label: "性能下降")
        case .channelUnavailable: StatusStyle(tone: .critical, symbol: "antenna.radiowaves.left.and.right.slash", label: "不可用")
        case .channelUnknown: StatusStyle(tone: .neutral, symbol: "questionmark.circle", label: "未知")
        case .alertFiring(let isCritical): StatusStyle(tone: isCritical ? .critical : .caution, symbol: "bell.badge", label: "告警中")
        case .alertResolved: StatusStyle(tone: .ok, symbol: "checkmark.seal", label: "已恢复")
        case .alertManuallyResolved: StatusStyle(tone: .neutral, symbol: "person.fill.checkmark", label: "手动已解决")
        case .errorUnresolved: StatusStyle(tone: .caution, symbol: "exclamationmark.bubble", label: "未处理")
        case .errorResolved: StatusStyle(tone: .neutral, symbol: "checkmark.bubble", label: "已处理")
        case .writeSucceeded: StatusStyle(tone: .ok, symbol: "checkmark.circle.fill", label: "成功")
        case .writeRejected: StatusStyle(tone: .critical, symbol: "xmark.octagon", label: "被拒绝")
        case .writeNotExecuted: StatusStyle(tone: .neutral, symbol: "minus.circle", label: "未执行")
        case .writePendingReconcile: StatusStyle(tone: .caution, symbol: "doc.text.magnifyingglass", label: "待核对")
        case .unknown: StatusStyle(tone: .neutral, symbol: "questionmark.circle", label: "未知")
        }
    }

    // MARK: 容量阈值（与 Web UsageProgressBar 75% / 90% 一致）
    enum CapacityLevel: Sendable { case idle, normal, nearLimit, atLimit }

    static func capacityLevel(used: Double, limit: Double) -> CapacityLevel {
        guard limit > 0, used > 0 else { return .idle }
        let ratio = used / limit
        if ratio >= 0.9 { return .atLimit }
        if ratio >= 0.75 { return .nearLimit }
        return .normal
    }

    static func capacityFill(_ level: CapacityLevel) -> Color {
        switch level {
        case .idle, .normal: Brand.accent        // 正常用量用“数据墨”，不着语义色
        case .nearLimit: Tone.caution.fill
        case .atLimit: Tone.critical.fill
        }
    }

    // MARK: 首字延迟分档（与 Web latencyHealth.ts 10s / 60s 一致；nil 表示墨色）
    static func firstTokenTone(seconds: Double) -> Tone? {
        if seconds >= 60 { return .critical }
        if seconds >= 10 { return .caution }
        return nil
    }
}

// MARK: - 基础组件

/// 状态印章：方形小圆角（控件是胶囊，状态是方印）
struct LedgerStamp: View {
    let style: Theme.StatusStyle
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: style.symbol)
                .imageScale(.small)
                .fontWeight(.semibold)
            Text(style.label)
        }
        .font(Theme.Typeface.stamp)
        .foregroundStyle(style.tone.foreground)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(style.tone.wash, in: RoundedRectangle(cornerRadius: Theme.Radius.stamp, style: .continuous))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: Theme.Radius.stamp, style: .continuous)
                    .strokeBorder(style.tone.foreground, lineWidth: 1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// 页边批注：在行首 8pt 页边栏画语义线（实线 / 虚线 / 点线）
struct MarginNote: ViewModifier {
    let tone: Theme.Tone?
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(.leading, Theme.Space.marginLane)
            .background(alignment: .leading) {
                if let tone, tone.isAnnotated {
                    let width = contrast == .increased ? Theme.Stroke.marginRuleIncreased : Theme.Stroke.marginRule
                    VerticalLine()
                        .stroke(tone.fill, style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: tone.marginDash))
                        .frame(width: width)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

extension View {
    func marginNote(_ tone: Theme.Tone?) -> some View { modifier(MarginNote(tone: tone)) }
}

/// 发丝线 / 合计双线
struct LedgerRule: View {
    var isTotal = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let hairline = Theme.Stroke.hairline(displayScale: displayScale)
        if isTotal {
            VStack(spacing: 2) {
                Rectangle().frame(height: hairline)
                Rectangle().frame(height: hairline)
            }
            .foregroundStyle(Theme.Paper.ruleStrong)
            .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(Theme.Paper.rule)
                .frame(height: hairline)
                .accessibilityHidden(true)
        }
    }
}

/// 页眉：「壹  待处理 ──────── 3」
struct LedgerSectionHeader: View {
    var folio: String? = nil       // 大写页序，纯装饰
    let title: String
    var count: Int? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            if let folio, !typeSize.isAccessibilitySize {
                Text(folio)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(Theme.Ink.secondary)
                .accessibilityAddTraits(.isHeader)
            LedgerRule()
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 4 }
            if let count {
                Text(count, format: .number)
                    .font(Theme.Typeface.count)
                    .foregroundStyle(Theme.Ink.secondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .font(Theme.Typeface.sectionLabel)
    }
}

/// 容量条：数值由相邻文字承担，条本身对 VoiceOver 隐藏
struct CapacityBar: View {
    let used: Double
    let limit: Double
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = Theme.Stroke.capacityBarHeight

    var body: some View {
        let fraction = limit > 0 ? min(max(used / limit, 0), 1) : 0
        let level = Theme.capacityLevel(used: used, limit: limit)
        RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
            .fill(Theme.Paper.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                        .fill(Theme.capacityFill(level))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 预览：账号行（演示数据）

private struct SampleAccountRow: View {
    let name: String
    let meta: String
    let amount: String
    let status: Theme.Status
    var note: String? = nil
    var resetAt: Date? = nil

    var body: some View {
        let style = Theme.style(for: status)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: style.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(style.tone.foreground)
                    .frame(width: Theme.Space.iconColumn)
                    .accessibilityHidden(true)
                Text(name)
                    .font(Theme.Typeface.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(amount)
                    .font(Theme.Typeface.ledgerFigure)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(meta)
                    .font(Theme.Typeface.rowMeta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if style.tone == .neutral {
                    LedgerStamp(style: style)   // 暂停、停用：印章放在元信息行，不占第三行
                }
            }
            .padding(.leading, Theme.Space.iconColumn + Theme.Space.s)
            if style.tone.isAnnotated {
                HStack(spacing: Theme.Space.xs) {
                    Text(style.label).fontWeight(.semibold)
                    if let resetAt, resetAt > Date.now {
                        Text("· 还剩")
                        Text(timerInterval: Date.now...resetAt, countsDown: true)
                    }
                    if let note {
                        Text("· \(note)").lineLimit(1)
                    }
                }
                .font(Theme.Typeface.annotation)
                .foregroundStyle(style.tone.foreground)
                .padding(.leading, Theme.Space.iconColumn + Theme.Space.s)
            }
        }
        .padding(.vertical, Theme.Space.rowVertical)
        .marginNote(style.tone)
        .accessibilityElement(children: .combine)
    }
}

#Preview("核簿 · 账号行") {
    List {
        Section {
            SampleAccountRow(name: "OpenAI-备用-A", meta: "OpenAI · API Key · 标准分组", amount: "$0.00",
                             status: .accountError, note: "401 凭据失效")
            SampleAccountRow(name: "Claude-官方-03", meta: "Anthropic · OAuth · 高级分组", amount: "$48.20",
                             status: .accountRateLimited, resetAt: Date.now.addingTimeInterval(512))
            SampleAccountRow(name: "Gemini-测试-B", meta: "Gemini · API Key · 未分组", amount: "$3.10",
                             status: .accountPaused)
            SampleAccountRow(name: "Claude-官方-01", meta: "Anthropic · OAuth · 高级分组", amount: "$102.44",
                             status: .accountNormal)
        } header: {
            LedgerSectionHeader(title: "需处理", count: 2)
        }
        .listRowBackground(Theme.Paper.canvas)
        .listRowSeparatorTint(Theme.Paper.rule)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.s, bottom: 0, trailing: Theme.Space.l))
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Theme.Paper.canvas)
    .typesettingLanguage(Locale.Language(identifier: "zh-Hans"))
}
```

**代码要点**

- `Color` 是 `Sendable`，因此颜色用 `static let` 缓存；`Font` 用计算属性，避免 Swift 6 严格并发下的 static 存储检查问题。
- `UIColor(dynamicProvider:)` 的闭包只捕获 `UInt32`，满足 `@Sendable` 要求。
- 倒计时使用 `Text(timerInterval:countsDown:)`。**必须先判断 `resetAt > now`**，否则 `now...resetAt` 是非法区间，会在运行时崩溃。
- 状态的“显示优先级”（错误 > 过载 > 限流 > 临时 > 停用 > 配额 > 暂停 > 正常，04 §4.1 #6）应放在 `Sub2Core` 中，与 Web 的 `AccountStatusIndicator` 保持一致并加单元测试。`Theme.style(for:)` 只负责把状态映射成外观。
- 建议补一条单元测试：遍历 `Theme.Tone.allCases`，在四种 trait 下解析颜色并计算对比度，断言 foreground ≥4.5、fill ≥3.0，防止以后调色时破坏可读性。

---

## 11. 风险与对策

| 风险 | 表现 | 对策 |
|---|---|---|
| **纸色偏黄或显脏** | 在原彩显示（True Tone）、夜览（Night Shift）或低端屏上，`#F4F0E7` 可能显得发黄、发灰 | canvas 的彩度已经压得很低；sheet 更接近白色，承载数据密集区；下一轮在 iPhone 17e 实机截图，对比开启和关闭原彩显示两种情况。若偏黄，可整体把色相向中性移 2–3° |
| **可读性** | 三级文字在凹槽上最低 4.85:1，接近阈值 | 规定 `Ink.tertiary` 只用于 ≥12pt 的时间、单位和坐标，**不用于正文**；增强对比度下升到 8.33:1 |
| **玻璃叠加** | 回执浮条与 Tab 栏、批量条与 Tab 栏同时出现，玻璃叠在玻璃上 | 浮条位于 Tab 栏上方 12pt，不重叠；选择模式下隐藏 Tab 栏；sheet 弹出时立刻收起浮条；自定义玻璃全 App 只有 2 处，并在代码审查清单里列为硬约束 |
| **玻璃被内容染色** | 饱和色内容滚到底栏下方时，会把玻璃染色（05 §4.9） | 内容层没有大面积饱和色：wash 是低彩度，图表面积 ≤10% 不透明度，金额柱不用渐变 |
| **中文排版：衬线回退不确定** | New York 中的中文究竟回退到哪种字体，未经实测 | 设计上已隔离：衬线只用于纯数字和拉丁文；下一轮用 zh-Hans 模拟器截图核实 |
| **中文排版：混排行高抖动** | 中文行与纯英文行高度不同，列表参差 | 根视图设置 `.typesettingLanguage(zh-Hans)`；行高预算按中文行计算 |
| **中文排版：字重错位** | `.bold` 下中文停在中粗、拉丁字母变粗 | 含中文的样式最高只用 `.semibold`（令牌已遵守） |
| **Dynamic Type 大字号**（AX1–AX5） | 三行账号行放不下；三口径栏挤压；页眉线被挤没 | 行内布局用 `ViewThatFits`：先尝试横排，放不下时金额移到名称下方，元信息改为两行；`isAccessibilitySize` 时三口径栏改为纵向三行；隐藏大写页序和迷你趋势；容量条和数字纵向堆叠；**关键数字不使用 `minimumScaleFactor`**（03 A13）；坐标轴最多放大到 accessibility2。AX5 下账面大数约 60pt，`$1,284.50` 约 300pt 宽，单独占一行仍放得下 |
| **色弱** | 绿色弱下 caution 与 critical 的 ΔE 只有 8.6；cost 与 caution 只有 4.3 | 每个状态都是“符号 + 文字 + 批注线型”三重编码（实线、虚线、点线）；cost 与 caution 不会出现在同一语境；`accessibilityDifferentiateWithoutColor` 开启时，印章文字加粗、批注线加宽（与增强对比度相同的处理） |
| **品牌蓝与模型紫** | 绿色弱和红色弱下接近 | 品牌蓝从不用于状态；模型限流始终带 `brain` 符号和“模型限流”文字 |
| **装饰过度** | 大写页序、合计双线、印章用多了，变成“仿古风” | 硬性约束：页序只在首页和详情页出现；双线每屏最多 1 处；印章只出现在状态位置；不使用纸纹贴图、做旧效果或手写体 |
| **语义色被稀释** | 开发时顺手用 `.green`、`.orange`（现状 D26、R8） | 颜色只能通过 `Theme` 取用；SwiftLint 禁止视图里出现 `Color.green/.orange/.red/.purple` 和 `.foregroundStyle(.green)` 一类写法 |
| **自定义色板无法跟随系统演进** | 例如 iOS 27 的玻璃色调滑杆 | 色调滑杆只作用于玻璃，本方向的玻璃全部交给系统或使用默认 `.regular`，不受影响；内容色自主控制正是这个方向的意图 |
| **未编译验证** | 令牌代码在 Windows 编写 | 下一轮在 Mac 上用 Xcode 27 编译，并加对比度单元测试；随后用 `isUITesting` 夹具出四种 trait（浅、深、浅增强、深增强）× 两种字号（Large、AX3）的截图矩阵 |
| **UITest 迁移** | 新组件会改变控件类型 | 本稿只定视觉，迁移成本在实施计划中另算（05 §4.15） |

---

## 12. 与简报硬约束的对照

| 简报约束 | 本方向的落实 |
|---|---|
| 语义色含义稳定 | §2.4 映射表与简报和 04 的术语一一对应；色值只是按纸面重新调校 |
| Liquid Glass 只用于控件层，内容层不透明 | §5：系统外壳之外只有 2 处自定义玻璃；内容一律使用不透明纸面 |
| 不虚构后端能力 | 样屏中每个“需要新接入”都标出了能力盘点的条目（02 §1.1、§1.2、§1.4、§3.1）；推送、通知中心不出现 |
| 文案只说业务；缺失值用“—” | §3.4；样屏中没有契约脚注 |
| 状态不只靠颜色；点击区 ≥44pt；Dynamic Type、增强对比度、减弱动态效果、VoiceOver | §2.5、§2.6、§6.2、§8、§11 |
| 最低 iOS 26 | 所用 API 均 ≤ iOS 26；iOS 27 的 `TabRole.prominent`、`ToolbarOverflowMenu` 等不在视觉层依赖之内 |
| 可用 SwiftUI 加演示数据原型化 | §10 的令牌和组件可以直接接入现有 `isUITesting` 夹具 |

---

## 参考来源

- Apple HIG：[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple Fonts（SF Pro / SF Pro Rounded / SF Mono / New York）](https://developer.apple.com/fonts/)
- [Applying Liquid Glass to custom views（`glassEffect`、`Glass.tint`、`interactive`）](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- ConcentricRectangle：[Nil Coalescing — Corner concentricity in SwiftUI on iOS 26](https://nilcoalescing.com/blog/ConcentricRectangleInSwiftUI/)、[SwiftUI Garden — ConcentricRectangle and ContainerRelativeShape](https://swiftui-garden.com/Shapes/ConcentricRectangle-and-ContainerRelativeShape)、[Apple Developer Forums 794685](https://developer.apple.com/forums/thread/794685)
- New York 与等宽数字：[Wikipedia — New York (2019 typeface)](https://en.wikipedia.org/wiki/New_York_(2019_typeface))、[Use Your Loaf — Monospace Digits](https://useyourloaf.com/blog/monospace-digits/)、[Tabular Numbers in iOS](https://seyfedd.in/writing/tabular-numbers-in-ios)、[Apple System Fonts in SwiftUI](https://bitrig.com/blog/apple-system-fonts)
- iOS 26 弃用 `Text + Text`：[Hacking with Swift 论坛](https://www.hackingwithswift.com/forums/100-days-of-swiftui/day-71-text-interpolation-deprecated-on-ios-26/30390)、[Fatbobman — Mixing Text and Image](https://fatbobman.com/en/posts/mixing_text_and_graphics_with_text_in_swiftui/)
- 宋体在 iOS 上为可下载字体（第三方清单）：[Download-Font-iOS](https://github.com/hisa0507/Download-Font-iOS)
- PingFang 作为系统回退字体：[bitinn 关于 PingFang 的笔记](https://gist.github.com/bitinn/42c95ed95aa3dcf155e2)
- 图表风格参考：[Financial Times — Visual Vocabulary（chart-doctor）](https://github.com/Financial-Times/chart-doctor/tree/main/visual-vocabulary)
- 编辑排版与留白参考：[Stripe Press](https://press.stripe.com/)、[Things 3](https://culturedcode.com/things/)
- 中文排版：[W3C — Requirements for Chinese Text Layout (clreq)](https://www.w3.org/TR/clreq/)
- 对比度标准：[WCAG 2.2 — Contrast (Minimum)](https://www.w3.org/TR/WCAG22/#contrast-minimum)、[Non-text Contrast](https://www.w3.org/TR/WCAG22/#non-text-contrast)
- 项目内依据：`research/00-brief.md`、`01-current-ui-audit.md`（D/C/R 编号）、`02-backend-capability-map.md`、`03-reference-patterns.md`（P/A 编号）、`04-sibling-clients.md`、`05-codex-critique.md`
