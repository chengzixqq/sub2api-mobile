# Sub2 Mobile

中文优先的 Sub2API 原生管理员客户端。使用 SwiftUI、Observation、Swift Concurrency、URLSession、Swift Charts 和 Keychain；最低 iOS 17，支持 iPhone 和基本 iPad 布局、深浅色与动态字体。

本分支已在正式 Xcode 27 上完成原生构建：57 项核心测试、4 项凭据协调测试和 15 项 iPhone 模拟器界面测试通过，已产出可自行签名的 iPhone IPA。**签名后真机、真实验证码服务及测试站点管理写入尚未验收**。

## 分支与旧版

- 原生分支：`codex/native-ios-rebuild`。
- 旧版：`main` 保持原状，`legacy-expo-3177500` 指向 `3177500f74b005ed32512d3f79a7a24d05eac352`。
- 保留 MIT 许可和原作者 ckken 的归属。现有图标来自旧版；不使用旧版 Expo 更新服务。

## 首版功能

| 模块 | 实现范围 |
| --- | --- |
| 站点和认证 | HTTPS 多站点、邮箱密码、TOTP、Admin Key、Keychain、会话恢复、退出；验证通过后激活连接 |
| 概览 | 四张等高卡片：今日请求附累计请求，今日/总 Tokens 底部嵌入绿色实际费用和金色上游成本；金额 Decimal 两位、最高 K，Tokens K/M/B；性能 RPM/TPM；趋势在运行健康前，保留缩放、滚动、点选与明细；统计/趋势/监控独立自动加载与前台 30 秒刷新 |
| 上游账号 | 搜索、状态/平台筛选、完整分页、详情/今日统计、调度开关、凭据刷新、手动 POST SSE 测试 |
| 用户 | 搜索、状态筛选、分页、详情、本月真实用量、分页密钥列表、状态和 Decimal 余额操作 |
| 设置 | 连接切换、删除本机凭据、版本信息、打开当前站点 Web 后台 |

复杂创建、OAuth 导入、分组编辑、支付、插件和服务器维护通过 Web 完成。普通用户登录会被明确拒绝管理会话；普通用户界面、推送、后台常驻监控和离线写入不在首版范围。

## 工具链与构建

要求 **Xcode 27.0 正式版（`27A266a`）、自带 Swift 6.4 编译器、Swift 6 语言模式**。Bundle ID 为 `com.chengzixqq.sub2mobile`。工具链守卫按 Apple 公布的正式版构建号核验，并拒绝其他构建及显式 Beta、RC、seed 标记，不会自动降级。

在已安装正式工具链和 iOS 模拟器 runtime 的 Mac 上：

```sh
git clone --branch codex/native-ios-rebuild https://github.com/chengzixqq/sub2api-mobile.git
cd sub2api-mobile
python3 scripts/build.py all
```

这个命令依次核验工具链、运行 Swift Testing 核心测试、运行 iPhone 模拟器 XCUITest、构建 `iphoneos` arm64 Release，核验设备平台后封装未签名 IPA。也可用 `unit`、`simulator`、`package` 分阶段执行；每阶段都先核验工具链。

- 标准工程：`Sub2Mobile.xcodeproj`，共享 scheme：`Sub2Mobile`。
- IPA：`build/artifacts/Sub2Mobile-unsigned.ipa`。
- 校验：`build/artifacts/SHA256SUMS`、`manifest.json`、`toolchain.json`。
- 日志：`build/runs/<run>/` 中独立保存 stdout、stderr、`commands.jsonl` 和 `UITests.xcresult`，重复运行不会覆盖历史证据。
- 新增 Swift 文件后运行 `python3 scripts/generate_project.py` 更新已提交工程，无需 XcodeGen/CocoaPods。

**未签名 IPA 不能直接安装到 iPhone。** 下载后使用你本地的证书和匹配的 provisioning profile 重签，证书/私钥不进入仓库或 CI。重签工具应同时处理嵌套 Frameworks；安装后的登录、切站、分页及管理写入必须在测试站点验收。构建通过与真机验收分别记录。

Mac 已使用正式 Xcode 27.0 / `27A266a`、Apple Swift 6.4 完成全流程。当前四卡版 IPA 对应干净源码 `e0bf7e54112d7ee695de7b9e85eeb527d03c29f8`，运行记录 `20261015T081613Z-5f322d22`，大小 2,970,688 字节，SHA-256 为 `1ea50fb7d852a38fc39c394583027b3b0b7ecc352e24010d8da30e28bd46d786`。Mac 全流程退出 0：57 项核心、4 项凭据、15 项 UI 测试和 Release arm64 设备构建通过。 manifest 记录源码和 11 项构建输入 Git 对象。同一源码的 GitHub Actions PR [38704373188](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38704373188) 和 push [38704364088](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38704364088) 的 Linux Core job 均成功，各通过 57 项核心、4 项凭据测试及原生语法解析；这不代表云端 iOS job 已完成，IPA 采用完整 Mac 构建证据。 详见 [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md)。

## 验证码桥接

自用站点需部署配套 `/mobile/verify` 页面。补丁和已运行检查见 [`integration/`](integration/)。站点必须使用 HTTPS；WKWebView 使用独立临时数据容器，仅接受同源主框架、预期 provider 和一次性 UUID nonce 的 proof。已实现 Turnstile、腾讯和阿里云验证码适配，真实服务尚未联调验收。密码、Admin Key 和 JWT 不经过消息桥。

## 架构与边界

- `Sources/Sub2Core`：可移植、Sendable 的 DTO、API actor、单次并发令牌刷新、分页、Decimal、POST SSE 和可注入传输层。
- `NativeApp/Session`：MainActor 界面状态、站点配置和 Keychain；新登录分配独立连接身份，页面用会话代数拒绝迟到结果。
- `NativeApp/Features`：原生业务页面。详情按需拉取，不逐行请求统计。
- `Tests/Sub2CoreTests`：受控传输测试；`Fixtures` 为脱敏样例。
- `UITests`：隔离 defaults/内存凭据的界面测试；`-ui-testing` 不执行真实登录或服务器写入。

适配目标是当前自用 Sub2API 源码 `40bee5d2e`，并未宣称兼容所有官方版本。API/错误和兼容边界见 [`docs/API_COMPATIBILITY.md`](docs/API_COMPATIBILITY.md)，验收清单见 [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md)。

已观察通过：Mac 57 项核心、4 项同源凭据协调、15 项 iPhone 18 Pro / iOS 27 模拟器界面测试，以及 Debug 模拟器和 Release arm64 设备构建。新增核心测试覆盖累计请求精确 Int、可选兼容、累计快照配对和 21 组 Decimal 金额边界；本次界面测试覆盖四卡费用嵌入与总请求，并保留认证、分页、独立加载和图表回归。同一源码的 GitHub Actions PR [38704373188](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38704373188) 和 push [38704364088](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38704364088) 的 Linux Core job 均成功，各通过 57 项核心、4 项凭据测试及原生语法解析；这不代表云端 iOS job 已完成，IPA 采用完整 Mac 构建证据。 配套 Web 桥接此前 47 项测试和生产构建通过，本次未修改桥接。受控测试不代替真实站点、Keychain 持久化和签名后 iPhone 验收。

概览实际费用表示用户扣费，上游成本表示账号成本；今日和累计分别使用各自字段。基础统计返回 `total_requests`、`total_actual_cost`，当前后端 `/stats` handler 遗漏今日和累计账号成本，客户端独立补取只含 stats 的 snapshot-v2。今日或累计任一费用字段缺失时，仅在该周期快照提供同次响应的完整实际/成本对时整体替换；快照失败或不完整时保留基础统计已知值，缺失项显示不可用，不跨响应拼接成完整对，也不用标准计费或零值代替。费用快照附独立更新时间；视图重绘时判定超过 90 秒为过期，该判断并非严格计时失效。卡片金额使用 `compactCost(Decimal?)`：Decimal 全程舍入，固定两位，>=1000 最高使用 K，例如 `$45.08K`、`$3872.50K`；Tokens 继续使用 K/M/B，原始数值不变。

四张概要卡片为今日请求、今日 Tokens、总 Tokens 和性能指标，标准字号实测均为 112pt，辅助功能 XXXL 字号均约 279.333pt，并使用单列布局；标题与数值左上对齐。今日请求底部显示 `total_requests` 全站累计请求，缺失显示不可用。今日/总 Tokens 底部分别显示今日/累计实际费用和上游成本，用绿色/金色区分，并提供“今日/累计实际费用”“今日/累计上游成本”辅助功能文字。费用行空间不足时改为两行；独立费用卡已移除，用量趋势排在运行健康之前。 辅助大字号截图只反映捕获时屏幕范围，完整卡内布局由辅助功能记录核验。

小时趋势默认读取 `actual_cost` 展示实际消费，可切换请求数和 Tokens；缺失实际消费显示不可用，不以标准 `cost` 替代。金额在柱上、点选和逐小时明细中均显示两位小数，Tokens 统一使用 K/M/B，原始 Decimal 与整数保持不变。达到 6× 或可见窗口不超过 6 个桶时即可显示柱上数值，最大放大仍为 3 小时窗口。按钮以 0.3 秒动画插值缩放倍数，再计算可见窗口；左侧时间边界固定，到达最大档时也不主动取整横向位置。双指缩放连续更新；系统“减弱动态效果”开启时尊重该设置。动画实现本次未改；此前 `77a2462` / `20261015T073815Z-46faa0c1` 模拟器录屏观察到第二柱宽 17 → 21 → 29 → 34 → 37 像素、柱顶高度不变，当前范围左端保持 `10/14 00:00`。刻度使用两行日期/时间，并显示当前与全部范围；指标切换、缩放和点选只处理已加载数据，不增加后端调用。基础统计、趋势和监控进入前台后独立请求及刷新，慢分区不会阻塞其他分区；离开页面或进入后台时取消。

余额操作在首次发送前持久化 UUID 和原始 Decimal 请求，网络结果不明时保留并复用原请求；不会对管理写入自动重试。退出后新登录分配新的身份连接，旧身份的未决请求仅供 Web 对账，不会在新身份重放。账号测试只有收到明确 `test_complete` 成功事件才判成功，EOF 不能代表成功。
