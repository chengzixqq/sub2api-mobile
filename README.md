# Sub2 Mobile

中文优先的 Sub2API 原生管理员客户端。使用 SwiftUI、Observation、Swift Concurrency、URLSession、Swift Charts 和 Keychain；最低 iOS 17，支持 iPhone 和基本 iPad 布局、深浅色与动态字体。

本分支是原生重建实现，**尚未完成正式 Xcode 构建和真机验收，不应当作已发布版本**。

## 分支与旧版

- 原生分支：`codex/native-ios-rebuild`。
- 旧版：`main` 保持原状，`legacy-expo-3177500` 指向 `3177500f74b005ed32512d3f79a7a24d05eac352`。
- 保留 MIT 许可和原作者 ckken 的归属。现有图标来自旧版；不使用旧版 Expo 更新服务。

## 首版功能

| 模块 | 实现范围 |
| --- | --- |
| 站点和认证 | HTTPS 多站点、邮箱密码、TOTP、Admin Key、Keychain、会话恢复、退出；验证通过后激活连接 |
| 概览 | 请求、Tokens、费用、趋势、账号异常数量、可选运行监控；仅页面前台每 30 秒刷新 |
| 上游账号 | 搜索、状态/平台筛选、完整分页、详情/今日统计、调度开关、凭据刷新、手动 POST SSE 测试 |
| 用户 | 搜索、状态筛选、分页、详情、本月真实用量、分页密钥列表、状态和 Decimal 余额操作 |
| 设置 | 连接切换、删除本机凭据、版本信息、打开当前站点 Web 后台 |

复杂创建、OAuth 导入、分组编辑、支付、插件和服务器维护通过 Web 完成。普通用户登录会被明确拒绝管理会话；普通用户界面、推送、后台常驻监控和离线写入不在首版范围。

## 工具链与构建

要求 **Xcode 27.0 正式版、自带 Swift 6.4 编译器、Swift 6 语言模式**。Bundle ID 为 `com.chengzixqq.sub2mobile`。不接受 Beta、RC、seed 或旧版本，也不会自动降级。

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

GitHub Actions 的 `xcode-27` 镜像目前实测为 `27A266a`，检查已拒绝该预发布版本。因此当前无已验证的 IPA。镜像提供正式版后可重新运行工作流，也可现在在符合要求的 Mac 上执行同一脚本。独立 Linux 核心测试使用正式 Swift 6.4 镜像，不代替 iOS 构建。

## 验证码桥接

自用站点需部署配套 `/mobile/verify` 页面。补丁和已运行检查见 [`integration/`](integration/)。站点必须使用 HTTPS；WKWebView 使用独立临时数据容器，仅接受同源主框架、预期 provider 和一次性 UUID nonce 的 proof。支持 Turnstile、腾讯和阿里云验证码。密码、Admin Key 和 JWT 不经过消息桥。

## 架构与边界

- `Sources/Sub2Core`：可移植、Sendable 的 DTO、API actor、单次并发令牌刷新、分页、Decimal、POST SSE 和可注入传输层。
- `NativeApp/Session`：MainActor 界面状态、站点配置和 Keychain；新登录分配独立连接身份，页面用会话代数拒绝迟到结果。
- `NativeApp/Features`：原生业务页面。详情按需拉取，不逐行请求统计。
- `Tests/Sub2CoreTests`：受控传输测试；`Fixtures` 为脱敏样例。
- `UITests`：隔离 defaults/内存凭据的界面测试；`-ui-testing` 不执行真实登录或服务器写入。

适配目标是当前自用 Sub2API 源码 `40bee5d2e`，并未宣称兼容所有官方版本。API/错误和兼容边界见 [`docs/API_COMPATIBILITY.md`](docs/API_COMPATIBILITY.md)，验收清单见 [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md)。

余额操作在首次发送前持久化 UUID 和原始 Decimal 请求，网络结果不明时保留并复用原请求；不会对管理写入自动重试。退出后新登录分配新的身份连接，旧身份的未决请求仅供 Web 对账，不会在新身份重放。账号测试只有收到明确 `test_complete` 成功事件才判成功，EOF 不能代表成功。
