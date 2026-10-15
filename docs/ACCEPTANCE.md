# 构建与真机验收

2026 年 10 月 15 日，Mac 执行 `python3 scripts/build.py all` 最终全流程退出 0，已生成概览自动分区加载、统一卡片和趋势显示优化版的未签名 iPhone IPA。构建源码为 `0de008d7f146f1820ae3becc79cbf33be7eb7824`，运行记录位于 `build/runs/20261015T070133Z-141fcdc1/`。

构建验收和签名后真机验收独立记录。下表未完成项不得以源码存在或静态检查替代。

| 检查 | 当前状态 |
| --- | --- |
| 正式工具链身份 | Mac 和云端报告 Xcode 27.0 / `27A266a` / Swift 6.4；该构建为 Apple 公布的正式版 |
| 工具链守卫 | Mac 正式工具链检查通过；Python 守卫单测 6 项通过 |
| Swift 6.4 核心合同测试 | Mac Apple Swift 6.4 下 52 项通过；新增 4 项测试函数覆盖 Decimal 两位金额舍入、原值精度与 Tokens K/M/B；此前认证、费用、时间桶与缩放等回归保留 |
| 凭据撤销与并发提交 | 4 项通过；同一 CredentialVault 源码的 memoryOnly 路径，验证旧刷新/旧退出/旧候选不能覆盖或删除新凭据，站点相互隔离 |
| 原生 Swift / Apple SDK 编译 | Debug 模拟器与 Release iPhone 设备构建通过 |
| 验证码桥接 | 37 项新增 + 10 项路由回归通过；typecheck、改动 ESLint、生产构建通过 |
| Xcode 工程与共享 scheme | 实际 xcodebuild 测试、设备构建通过；保留 xcresult |
| iOS 模拟器 UI 测试 | iPhone 18 Pro / iOS 27 下全部 15 项通过；新增自动加载、慢趋势独立显示、辅助大字体等高测试，更新趋势金额与 Tokens 断言；保留站点/身份、分页、退出及费用回归 |
| 本次最终截图人工复核 | 28 张截图与 30 份文本附件已导出并重开校验；标准和辅助 XXXL 字号六卡等高，8× 已有两位金额标签，Tokens 的柱上、点选和明细使用 M 单位，慢趋势不阻塞统计和监控 |
| 本次按钮动画核验 | 模拟器录屏逐帧确认缩放中间态：第二柱宽 17 → 33 → 36 → 37 像素；不是仅比较缩放前后截图 |
| iphoneos arm64 Release / 未签名 IPA | 已产出；设备平台、arm64、ZIP、Bundle ID 和最低 iOS 17 校验通过 |
| 未签名状态 | 无嵌入 provisioning / `_CodeSignature`；codesign 检查退出 1，输出 `code object is not signed at all` |
| 构建源码身份 | manifest 记录干净源码、commit 及 11 项构建输入 Git 对象；构建前后身份一致 |
| GitHub Actions 独立云端构建 | 历史运行 38681297253 全部成功；当前概览修复尚未记录云端结果，本次交付采用完整 Mac 构建证据 |
| 签名后 iPhone | 未运行；证书保留在用户本地 |
| 真实验证码服务 | 未运行；现有验证码测试为受控 proof/组件与路由测试 |
| 测试站点管理写入 | 未运行；当前测试使用受控传输，不操作生产数据 |

交付 IPA：`build/artifacts/Sub2Mobile-unsigned.ipa`，2,956,956 字节，Bundle ID 为 `com.chengzixqq.sub2mobile`。SHA-256：

```text
2b7b7c0d6a6251b866f849858ce2a78e849d825947d5a4b4b6bcd148f097365c
```

同目录保留 `SHA256SUMS`、`manifest.json`、`toolchain.json`。构建输入对象随 manifest 保存；交付文档或辅助脚本之后的提交若与构建 commit 不同，交付检查仍逐项核对这些输入，并明确记录两个 revision。

历史独立云端运行：[38681297253](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38681297253) 于 2026 年 10 月 15 日完成，整体和两个 job 均为 success；对应此前原生构建，不含当前概览修复。更早运行 [38677142697](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38677142697) 曾因旧守卫将 `27A266a` 误判为预发布而失败；[Apple 正式发布记录](https://developer.apple.com/news/releases/?id=09142026h)已确认正式版身份，守卫已修正。

此前概览超时故障的受控回归使用同一输入：旧原生版在成功统计与详情超时并存时退出 1；当时修复版输出 `DASHBOARD_REGRESSION counters=12 details_requested=0 stats_timeout=90.0` 并退出 0；恢复旧版后再次退出 1。该历史回归保留，当前版本继续独立等待基础统计最多 90 秒，趋势和监控各自自动加载、局部报错；轮询使用同一次可见状态快照，避免首屏任务取消后跳过首轮。真实站点的 SQL、缓存和代理超时尚未测量或优化，不能用受控回归推断实际响应耗时。

此前概览字段回归使用相同脱敏输入：BASELINE 和 ROLLBACK 均丢失实际费用、账号成本、累计实际费用、累计账号成本、总 Tokens 和平均响应时间 6 个字段，退出 1；当时 MODIFIED 保留全部字段并退出 0，输出：

```text
OVERVIEW_REGRESSION actual=12.34567891 account_cost=4.56789123 total_tokens=9876543210 average_duration_ms=1250.25
```

上一版源码 `9665772` 的受控截图曾人工复核通过：费用为 `$12.34` / `$4.56`，Tokens 为 `1.23M` / `9.88B`，性能为 `1.23K RPM` / `987.65K TPM` / `1.25s`；跨日刻度完整、无重叠。该历史记录不替代本次新增布局和图表交互的最终截图复核。

上一轮趋势字段回归复用同一测试和脱敏输入：BASELINE `e6aa7b6` 输出实际消费不可用并退出 1；MODIFIED 保留实际消费 Decimal 原值并退出 0；ROLLBACK 再次不可用并退出 1。对应输出为：

```text
BASELINE: TREND_REGRESSION actual=unavailable standard=99.99
MODIFIED: TREND_REGRESSION actual=12.345678910123456789 standard=99.99
ROLLBACK: TREND_REGRESSION actual=unavailable standard=99.99
```

当前模拟器测试通过：基础统计、小时趋势和监控无需点击即独立加载；延迟趋势不会阻塞已成功的统计和监控。各分区前台完成后间隔 30 秒独立刷新，下拉并发刷新；离开或后台取消旧请求，局部错误仍可单独重试。六张概要卡片标准字号和辅助功能 XXXL 字号下均等高。

本次最终画面已人工核验：标准字号六卡均为 136pt，辅助 XXXL 均约 325pt，并切换单列；8× 的非最大缩放已显示 `$0.12` 等两位金额，点选与明细显示 `$0.10` / `$0.11`，Tokens 柱上、点选及明细显示 `1.00M` / `1.01M` 等。慢趋势用例在趋势仍加载时已显示请求数 128 与 QPS 0.2，随后趋势自动出现。录屏在实际解码时间 21.181667、21.425000、21.471667、21.530000 秒可见柱宽 17、33、36、37 像素，包含明确动画中间态。静态截图本身不证明计时器；B 值趋势由核心格式测试覆盖，长趋势截图使用 M 值。证据保留在外部 `dashboard-polish/screenshots/` 和 `dashboard-polish/animation/20261015T070133Z-141fcdc1/`；少量部分可见的边缘柱标签会随滚动裁切，完整桶仍可通过点选和明细查看。

趋势仍默认实际消费，`DashboardTrendMetric.displayValue` 将所有可见金额以 Decimal 四舍五入到两位小数，Tokens 使用 K/M/B，请求数为整数；原始金额和计数保留。达到 6× 或可见窗口不超过 6 个桶时显示柱标签，最大放大仍为 3 桶；横滑、双指、点选及明细回归通过。按钮使用 0.3 秒显式可见域插值动画，“减弱动态效果”开启时不播放。

本次格式回归以相同冻结 Python 命令和 JSON 输入运行归档内真实 UI 所调用的格式函数：BASELINE 输出长金额和完整 Tokens、退出 1；MODIFIED 输出 `$12.35` / `$0.00` 和 `9.88B` / `12.35K`、退出 0；可执行回退后恢复旧显示、退出 1，恢复 ZIP 哈希与 baseline 相等。生成的 Swift 测试绑定各版本真实调用，方法名从 `exactValue` 变为 `displayValue`，故生成测试字节不同；冻结 Python、输入和断言完全相同。此回归只证明显示格式，自动加载、等高和交互由本次 15 项界面测试另行验证。

初次完整构建 `20261015T065947Z-6e56d794` 的动画组件触发 Swift 6 actor 隔离编译错误，退出 65；改为 nonisolated 值类型、保留 MainActor 的 body 后，当前完整构建退出 0。原错误日志保留。

基础统计缺少账号成本时仍独立请求仅含 stats 的 snapshot，失败保留基础统计并在费用区重试。费用快照显示独立更新时间，视图重绘时按 90 秒检查过期，并非严格计时失效。上述结果来自受控测试，真实站点显示与签名后 iPhone 仍待验收。

可在相同正式工具链上运行 `python3 scripts/build.py all` 复验，保存 `build/` 中的日志、工具链和 xcresult。任何测试或平台校验失败都阻断 IPA 交付。当前 IPA 需本地签名后安装，以下真机和真实服务清单仍待完成。

签名后，使用专用测试站点和测试账号依次记录：

1. 密码登录、验证码成功/取消/超时、TOTP 错误和成功、普通用户拒绝、Admin Key 验证、重启恢复、退出擦除。
2. 多个站点/身份之间切换；慢网络中切换，确认旧页面结果和确认框不进入新身份，不跨站写入。
3. 概览前台刷新，后台和离开页面后停止；监控无权限时保留概览并显示不可用。
4. 超过一页的账号、用户和密钥：搜索、筛选、拉取全部页、刷新、断网和超时后的重试。
5. 测试账号调度启停、凭据刷新、手动 SSE：明确成功/明确失败/中途断流/取消；测试仅由手动点击触发。
6. 测试用户禁用/启用、step-up、Decimal 余额、双击提交、断网后复用同 UUID/原始请求，以及服务器幂等窗口内核对只入账一次。
7. 真机深浅色、大字体、横屏、基本 iPad 布局和 Web 后台入口。

每项记录站点（脱敏）、操作、预期、实际、日期、设备/iOS、App commit 和问题。不得把真实密码、令牌或完整 API Key 放入记录。

回退：保留 `main` 与 `legacy-expo-3177500`。原生分支和验证码桥接分开提交，可独立审查/回退；不在此任务中合并主分支或部署服务器。
