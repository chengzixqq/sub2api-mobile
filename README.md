# Sub2 Mobile

中文优先的 Sub2API 原生管理员客户端，采用 SwiftUI、Observation、Swift Concurrency、URLSession、Swift Charts 和 Keychain。最低 iOS 26，支持 iPhone、基本 iPad 布局、深浅色和动态字体。

功能和接口说明见 [管理模块契约](docs/ADMIN_MODULES.md) 与 [API 兼容边界](docs/API_COMPATIBILITY.md)。各版本的实际测试、构建、IPA 校验和真机验收结果统一记录在 [验收记录](docs/ACCEPTANCE.md)；功能已实现与真机已验收分别记录。

## 当前功能

| 模块 | 实现范围 |
| --- | --- |
| 站点和认证 | HTTPS 多站点、邮箱密码、TOTP、Admin Key、Keychain、会话恢复和退出；验证通过后激活连接 |
| 概览 | 今日与累计请求、Tokens、实际费用和上游成本；分区独立加载；消费/请求/Tokens 趋势、RPM/TPM 性能趋势和运行健康 |
| 上游账号 | 搜索、平台/认证类型/分组/状态筛选、服务端排序和完整分页；可选前台 30 秒刷新已加载页面；自定义列表字段和顺序 |
| 账号详情与操作 | 容量、在用并发/RPM、今日扣费与成本；快捷编辑名称、备注、并发、优先级、倍率、负载因子和分组；调度、凭据刷新、手动 POST SSE 测试；最多 50 个账号批量启停调度或刷新凭据，逐项显示结果 |
| 用户 | 搜索、分页、详情、用量与密钥列表；创建及编辑邮箱、用户名、密码、角色、备注、并发和 RPM；启停、Decimal 余额操作和自定义列表字段 |
| 请求与错误日志 | 请求记录、客户端失败请求和上游错误；时间与关联对象筛选、按需分页、费用/Token/时延详情；默认近 24 小时随下拉刷新推进，历史筛选保留固定范围 |
| 统计分析 | 今日、近 7 天、本月与自定义范围；账号/分组/用户/模型筛选；汇总、实际消费趋势、模型及分组统计，显示实际扣费、上游成本和差额 |
| 分组 | 搜索、筛选、分页、详情与容量；创建、编辑、启停和删除；从详情查看分组账号、日志与分析，账号快捷编辑管理分组归属 |
| 设置 | 连接切换、删除本机凭据、版本信息和打开当前站点 Web 后台 |

底部“管理”提供日志、分析和分组入口；概览和账号/分组详情也提供对应跳转。列表字段偏好按登录身份保存。

复杂上游账号创建、OAuth 导入、分组高级路由/价格配置、完整上游 5h/7d 用量百分比、支付、插件和服务器维护仍使用当前站点 Web 后台。普通用户界面、推送、后台常驻监控和离线写入尚未实现。

## 数据与操作口径

实际费用表示向用户扣费，上游成本表示账号成本；两者分别展示，缺失显示“不可用”，不使用标准费用或零值补齐。金额使用 Decimal，显示舍入不改变原始值；概览、请求记录和统计分析的费用展示保留两位小数，Tokens 使用 K/M/B。统计中的差额为实际扣费减上游成本，未包含服务器等费用。

概览 `rpm` 与账号 `current_rpm` 沿用现有字段，读取后端近 60 秒成功上游请求数。概览同时读取 `rpm_available`，不可用时明确显示；旧站点未提供该标记时，不宣称其窗口是近 60 秒。TPM 为近 5 分钟均值；账号容量中的 `scheduling_rpm` 为独立自然分钟调度计数。历史性能图按吞吐时间桶计算，与概览实时值的窗口和请求口径不同。

概览各分区独立加载，慢查询不阻塞其他分区。账号列表自动刷新默认关闭；开启后仅在页面前台刷新已加载分页，选择、编辑和批量操作期间暂停。需要统计的列表字段使用批量请求，不逐行加载。切站、切换身份或修改查询后，旧结果不能覆盖当前页面。

管理写操作均需确认站点和对象，不自动重试。余额和受支持的用户并发变更保留固定 UUID 与原始请求；其他写操作结果不明时，先读取或在 Web 核对，再决定后续操作。批量结果区分成功、失败、未执行和结果不明。账号测试只有收到明确的 `test_complete` 成功事件才判成功，连接结束本身不代表成功。

## 工具链与构建

要求 **Xcode 27.1 正式版（`27A9275`，由同号 RC 转正）、自带 Swift 6.4 编译器、Swift 6 语言模式**。Bundle ID 为 `com.chengzixqq.sub2mobile`，最低 iOS 26。工具链守卫核对正式版构建号，拒绝其他版本及 Beta、RC、seed 标记，不自动降级。

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

使用验证码的自用站点需部署配套 `/mobile/verify` 页面，补丁和检查记录见 [`integration/`](integration/)。WKWebView 使用临时数据容器，仅接受 HTTPS 同源主框架、预期 provider 和一次性 UUID nonce 的 proof。已实现 Turnstile、腾讯和阿里云适配；实际服务联调状态见验收记录。密码、Admin Key 和 JWT 不经过消息桥。

## 代码与兼容范围

本项目已接入 CodeGraph，支持 Swift/Python 代码符号和调用关系查询。开发工具版本为 1.6.2，可用 `npm install -g @colbymchenry/codegraph@1.6.2` 安装。在每个源码 checkout 中分别运行：

```sh
codegraph init --yes
codegraph status
codegraph explore "DashboardStats"
```

源码变更后用 `codegraph sync` 更新索引；Codex 已配置 CodeGraph MCP 时也可直接调用 `codegraph_explore`，并指定当前 checkout 的绝对路径。索引位于本机 `.codegraph/`，不提交数据库；新 checkout 需要独立初始化。后续代理的使用约定见 [AGENTS.md](AGENTS.md)。

- `Sources/Sub2Core`：Sendable DTO、API actor、共享令牌刷新、分页、Decimal、POST SSE 和可注入传输层。
- `NativeApp/Session`：MainActor 界面状态、站点配置、Keychain 和会话身份隔离。
- `NativeApp/Features`：SwiftUI 业务页面。
- `Tests/Sub2CoreTests`、`Tests/NativeSessionTests`：接口与会话回归测试；`Fixtures` 为脱敏样例。
- `UITests`：使用隔离 defaults 和内存夹具；`-ui-testing` 不执行真实登录或服务器写入。

当前管理模块按自用 Sub2API 共享源码 `e5ab7e4f4c136a8faf40fd06694ab0a6bf6f6925` 核对接口，不宣称兼容所有官方版本。模块依赖、权限与兼容边界见 [API 兼容说明](docs/API_COMPATIBILITY.md) 和 [管理模块契约](docs/ADMIN_MODULES.md)。

## 分支与许可

原生工程位于 `codex/native-ios-rebuild`；旧版引用 `legacy-expo-3177500` 指向 `3177500f74b005ed32512d3f79a7a24d05eac352`。保留 MIT 许可及原作者 ckken 的归属，现有图标来自旧版。原生版不接入旧版 Expo 更新服务，通过重新构建和签名 IPA 更新。
