# Sub2 Mobile

中文优先的 Sub2API 原生管理员客户端，采用 SwiftUI、Observation、Swift Concurrency、URLSession、Swift Charts 和 Keychain。最低 iOS 26，支持 iPhone、基本 iPad 布局、深浅色和动态字体。

功能和接口说明见 [管理模块契约](docs/ADMIN_MODULES.md) 与 [API 兼容边界](docs/API_COMPATIBILITY.md)。各版本的实际测试、构建、IPA 校验和真机验收结果统一记录在 [验收记录](docs/ACCEPTANCE.md)；功能已实现与真机已验收分别记录。

## 当前功能

| 模块 | 实现范围 |
| --- | --- |
| 站点和认证 | HTTPS 多站点；三种登录方式：账号和密码（含 TOTP 两步验证与验证码桥页）、管理访问令牌（粘贴 `sat_` 自动识别，区分只读与读写）、Admin Key；每个站点固定的设备 ID（`X-Device-ID`）；连接时读 `GET /admin/me`（旧服务端按 capability 降级）；全局合规确认与二次验证 sheet；Keychain、会话恢复、退出与删除站点 |
| 概览 | 顶部 6 格（今日实际扣费、请求、错误率、利润、RPM、TPM）；待处理队列（告警、错误 / 过载 / 受限账号、可用不足分组、余额 / 兑换码批次 / 补偿三类待核对）；今日每小时实际扣费图与运行区（健康分、错误率、上游 429 / 529、渠道）；没有待处理时切换平静布局与按账号排行；登录无法自动续期时顶部横幅。一次 `dashboard/home` 聚合、前台 60 秒刷新，旧站点逐接口退路 |
| 监控 | 概况（运行区，以及仅管理员可见的服务器区：CPU / 内存、并发与排队、QPS、SLA、任务心跳、日志采集与入口拒绝）、渠道（四档计数、18 格时间条、点按进分组）、告警（告警中 / 最近结束、加载更早、行内手动解决与静默）；告警详情；运维监控未开启时的说明与站长开启入口，··· 菜单里二次确认关闭 |
| 上游账号 | 搜索、平台/认证类型/分组/状态筛选、服务端排序和完整分页；可选前台 30 秒刷新已加载页面；自定义列表字段和顺序 |
| 账号详情与操作 | 容量、在用并发/RPM、今日扣费与成本；快捷编辑名称、备注、并发、优先级、倍率、负载因子和分组；调度、凭据刷新、手动 POST SSE 测试；最多 50 个账号批量启停调度或刷新凭据，逐项显示结果 |
| 用户 | 搜索、分页、详情、用量与密钥列表；创建及编辑邮箱、用户名、密码、角色、备注、并发和 RPM；启停、Decimal 余额操作和自定义列表字段 |
| 请求与错误日志 | 请求记录、客户端失败请求和上游错误；时间与关联对象筛选、按需分页、费用/Token/时延详情；默认近 24 小时随下拉刷新推进，历史筛选保留固定范围 |
| 统计分析 | 今日、近 7 天、本月与自定义范围；账号/分组/用户/模型筛选；汇总、实际消费趋势、模型及分组统计，显示实际扣费、上游成本和差额 |
| 分组 | 搜索、筛选、分页、详情与容量；创建、编辑、启停和删除；从详情查看分组账号、日志与分析，账号快捷编辑管理分组归属 |
| 应用结构 | 底部四个 Tab：概览 · 账号 · 用户 · 监控，外加搜索 Tab；使用记录、错误请求、告警事件、分组、统计分析与设置从搜索目录进入，未实现的模块显示“即将推出”；概览与账号标题是站点菜单，可切换或添加站点 |
| 设置 | 分为“界面与模式”（外观、Face ID 与金额门槛）和“站点与凭据”（当前站点身份与认证方式、站点列表、待核对的资金写、退出并清除凭据、关于） |

概览和账号/分组详情也提供到日志、分析和分组的跳转。列表字段偏好按登录身份保存。

复杂上游账号创建、OAuth 导入、分组高级路由/价格配置、完整上游 5h/7d 用量百分比、支付、插件和服务器维护仍使用当前站点 Web 后台。普通用户界面、推送、后台常驻监控和离线写入尚未实现。

## 数据与操作口径

实际费用表示向用户扣费，上游成本表示账号成本；两者分别展示，缺失显示“—”，0 显示 0，不使用标准费用或零值补齐。金额使用 Decimal，显示舍入不改变原始值；数值格式统一由 `DisplayFormat` 输出（金额两位小数、Tokens 使用 K/M/B 一位小数）。概览、监控、性能趋势与阶段 0 新写的页面按服务器时区计算“今日”、小时桶与绝对时间；其余现有页面（统计分析的“今日”与起止时间、日志的时区参数、各处“更新于 HH:MM:SS”）仍按手机时区，随阶段 1–4 重写这些页面时切换。发给服务端的时间一律是 UTC `Z`。统计中的差额为实际扣费减上游成本，未包含服务器等费用。

概览 6 格的 RPM / TPM 读 `dashboard/home` 的 `rates` 段（近 5 分钟，TPM 含缓存 Tokens）；运维监控关闭时 RPM 只计成功请求、错误率显示“—”，由 6 格下方的提示行说明。账号 `current_rpm` 仍为近 60 秒成功上游请求数，`scheduling_rpm` 为独立的自然分钟调度计数；统计分析的性能图按吞吐时间桶计算，口径与 6 格不同。

概览一次请求 `dashboard/home`，各段独立给出成功 / 未开启 / 失败 / 超时，失败只影响该段（保留旧值并标“更新失败”）。账号列表自动刷新默认关闭；开启后仅在页面前台刷新已加载分页，选择、编辑和批量操作期间暂停。需要统计的列表字段使用批量请求，不逐行加载。切站、切换身份或修改查询后，旧结果不能覆盖当前页面。

读请求在网络错误、超时、502 / 504 以及没有业务 reason（或 reason 为 `SERVICE_UNAVAILABLE`）的 503 时自动重试最多 2 次，500 与带业务 reason 的 503 不重试；`TOKEN_EXPIRED` 对所有方法刷新后用同一请求重发一次。管理写操作均需确认站点和对象，不带 Idempotency-Key 的写不自动重试。余额调整先把记录落盘再带固定 key 发送（落盘失败就不发送），结果不明时只能核对或用同一编号重试；站点有 `admin.idempotent_writes` 时新建与编辑用户也带 key。其他写操作结果不明时，先读取或在 Web 核对，再决定后续操作。批量结果区分成功、失败、未执行和结果不明。账号测试只有收到明确的 `test_complete` 成功事件才判成功，连接结束本身不代表成功。

## 工具链与构建

要求 **Xcode 27.2 正式版（`27B52`，App Store 发布）、自带 Swift 6.4 编译器、Swift 6 语言模式**。Bundle ID 为 `com.chengzixqq.sub2mobile`，最低 iOS 26。工具链守卫核对正式版构建号，拒绝其他版本及 Beta、RC、seed 标记，不自动降级。

在已安装正式工具链和 iOS 模拟器 runtime 的 Mac 上，进入已同步到所需提交且工作区干净的原生源码目录：

```sh
python3 scripts/build.py all
```

命令依次核验工具链、运行 Swift Package 单元测试与 iPhone 模拟器 XCUITest、构建 `iphoneos` arm64 Release，并封装未签名 IPA。可用 `unit`、`simulator`、`package` 分阶段执行；每阶段都先核验工具链。

- 标准工程：`Sub2Mobile.xcodeproj`，共享 scheme：`Sub2Mobile`。
- IPA：`build/artifacts/Sub2Mobile-unsigned.ipa`。
- 校验和来源：`build/artifacts/SHA256SUMS`、`manifest.json`、`toolchain.json`。
- 运行日志：`build/runs/<run>/`，保留独立 stdout、stderr、`commands.jsonl` 和 `UITests.xcresult`。
- 新增 Swift 文件后运行 `python3 scripts/generate_project.py` 更新已提交工程，无需 XcodeGen 或 CocoaPods。

manifest 记录 IPA 的构建提交和输入 Git 对象。后续文档提交可能与构建提交不同，应按 manifest 核对来源；实际测试数量、IPA 大小、SHA-256 和验收限制以 [验收记录](docs/ACCEPTANCE.md) 及对应运行证据为准。

**未签名 IPA 需要用本地证书和匹配的 provisioning profile 重签后才能安装到 iPhone。** 重签时同时处理嵌套 Frameworks，证书和私钥留在本地。安装后应在测试站点核对登录、切站、分页和管理写入；模拟器通过和 IPA 构建成功分别记录，不替代真机验收。

## 验证码桥接

使用验证码的站点需部署配套的手机验证页：优先使用公开设置里的 `mobile_verify_path`，为空时仍尝试 `/mobile/verify` 并提示可能未部署；补丁和检查记录见 [`integration/`](integration/)。WKWebView 使用临时数据容器，仅接受 HTTPS 同源主框架、预期 provider 和一次性 UUID nonce 的 proof。已实现 Turnstile、腾讯和阿里云适配；实际服务联调状态见验收记录。密码、管理访问令牌、Admin Key 和 JWT 不经过消息桥。

## 代码与兼容范围

本项目已接入 CodeGraph，支持 Swift/Python 代码符号和调用关系查询。开发工具版本为 1.6.2，可用 `npm install -g @colbymchenry/codegraph@1.6.2` 安装。在每个源码 checkout 中分别运行：

```sh
codegraph init --yes
codegraph status
codegraph explore "DashboardStats"
```

源码变更后用 `codegraph sync` 更新索引；Codex 已配置 CodeGraph MCP 时也可直接调用 `codegraph_explore`，并指定当前 checkout 的绝对路径。索引位于本机 `.codegraph/`，不提交数据库；新 checkout 需要独立初始化。后续代理的使用约定见 [AGENTS.md](AGENTS.md)。

- `Sources/Sub2Core`：Sendable DTO、`APIClient` actor（请求头与设备 ID、续期重发、自动重试、ETag 条件请求、幂等写执行器、请求日志 `RequestLog`）、错误信封与 reason 总表（`ErrorEnvelope`、`ReasonCatalog`）、`AdminMe` 与 capability 常量、`ServerTime`、`DisplayFormat`、`IncrementalList`、资金写待核对规则与各模块的纯函数。
- `NativeApp/Session`：MainActor 界面状态（`AppModel` 及其扩展）、`SiteSession`、Keychain 与设备 ID、登录流程 `LoginController`、路由 `AppRouter`、待核对记录 `PendingMoneyLedger`、本机设置与 Face ID 门控；除 `AppModel*.swift`、`DemoData.swift` 外都由 SwiftPM 在 macOS 上编译测试。
- `NativeApp/Features`、`NativeApp/Views`、`NativeApp/Design`：SwiftUI 页面、通用组件与 `Palette` / `Tone` 视觉令牌。
- `Tests/Sub2CoreTests`、`Tests/NativeSessionTests`：接口与会话回归测试；`Fixtures` 为脱敏样例。
- `UITests`：使用隔离 defaults 和内存夹具；`-ui-testing` 不执行真实登录或服务器写入。夹具能模拟三种登录方式（账号和密码、`sat_` 管理访问令牌、Admin Key），启动参数 `-ui-readonly-token`、`-ui-compliance-required`、`-ui-step-up-required`、`-ui-switch-rejected` 等切换只读令牌、合规、二次验证与切站失败等场景。

阶段 0 起按 sub2 `main` `70116315d` 之后的后端核对接口；更早的站点没有 `/admin/me` 与 capability，App 按 capability 降级（不发新参数、隐藏不支持的功能），不宣称兼容所有官方版本。模块依赖、权限与兼容边界见 [API 兼容说明](docs/API_COMPATIBILITY.md) 和 [管理模块契约](docs/ADMIN_MODULES.md)。

## 分支与许可

原生工程位于 `codex/native-ios-rebuild`；旧版引用 `legacy-expo-3177500` 指向 `3177500f74b005ed32512d3f79a7a24d05eac352`。保留 MIT 许可及原作者 ckken 的归属，现有图标来自旧版。原生版不接入旧版 Expo 更新服务，通过重新构建和签名 IPA 更新。
