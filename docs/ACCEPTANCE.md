# 构建与真机验收

2026 年 10 月 15 日，Mac 执行 `python3 scripts/build.py all` 全流程退出 0，已生成概览超时修复版的未签名 iPhone IPA。构建源码为 `b6c921ba598ec17c50de8875838745dc16581610`，运行记录位于 `build/runs/20261015T052455Z-d83e7150/`。

构建验收和签名后真机验收独立记录。下表未完成项不得以源码存在或静态检查替代。

| 检查 | 当前状态 |
| --- | --- |
| 正式工具链身份 | Mac 和云端报告 Xcode 27.0 / `27A266a` / Swift 6.4；该构建为 Apple 公布的正式版 |
| 工具链守卫 | Mac 正式工具链检查通过；Python 守卫单测 6 项通过 |
| Swift 6.4 核心合同测试 | Mac Apple Swift 6.4 下 27 项通过；含概览独立加载/超时/刷新/取消，以及令牌刷新、身份边界、余额精度/幂等与验证码消息解析 |
| 凭据撤销与并发提交 | 4 项通过；同一 CredentialVault 源码的 memoryOnly 路径，验证旧刷新/旧退出/旧候选不能覆盖或删除新凭据，站点相互隔离 |
| 原生 Swift / Apple SDK 编译 | Debug 模拟器与 Release iPhone 设备构建通过 |
| 验证码桥接 | 37 项新增 + 10 项路由回归通过；typecheck、改动 ESLint、生产构建通过 |
| Xcode 工程与共享 scheme | 实际 xcodebuild 测试、设备构建通过；保留 xcresult |
| iOS 模拟器 UI 测试 | iPhone 18 Pro / iOS 27 下全部 7 项通过；概览明细分别超时后仍保留统计，切回页面正常；使用隔离数据，不连接真实站点 |
| iphoneos arm64 Release / 未签名 IPA | 已产出；设备平台、arm64、ZIP、Bundle ID 和最低 iOS 17 校验通过 |
| 未签名状态 | 无嵌入 provisioning / `_CodeSignature`；codesign 检查退出 1，输出 `code object is not signed at all` |
| 构建源码身份 | manifest 记录干净源码、commit 及 11 项构建输入 Git 对象；构建前后身份一致 |
| GitHub Actions 独立云端构建 | 历史运行 38681297253 全部成功；当前概览修复尚未记录云端结果，本次交付采用完整 Mac 构建证据 |
| 签名后 iPhone | 未运行；证书保留在用户本地 |
| 真实验证码服务 | 未运行；现有验证码测试为受控 proof/组件与路由测试 |
| 测试站点管理写入 | 未运行；当前测试使用受控传输，不操作生产数据 |

交付 IPA：`build/artifacts/Sub2Mobile-unsigned.ipa`，2,807,240 字节，Bundle ID 为 `com.chengzixqq.sub2mobile`。SHA-256：

```text
fc8bc5ff0b4462653a4e00f8b843737146b60f9d2530fd8fa9179fbcd9c122f8
```

同目录保留 `SHA256SUMS`、`manifest.json`、`toolchain.json`。构建输入对象随 manifest 保存；交付文档或辅助脚本之后的提交若与构建 commit 不同，交付检查仍逐项核对这些输入，并明确记录两个 revision。

历史独立云端运行：[38681297253](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38681297253) 于 2026 年 10 月 15 日完成，整体和两个 job 均为 success；对应此前原生构建，不含当前概览修复。更早运行 [38677142697](https://github.com/chengzixqq/sub2api-mobile/actions/runs/38677142697) 曾因旧守卫将 `27A266a` 误判为预发布而失败；[Apple 正式发布记录](https://developer.apple.com/news/releases/?id=09142026h)已确认正式版身份，守卫已修正。

概览故障的受控回归使用同一输入：旧原生版在成功统计与详情超时并存时退出 1；修复版输出 `DASHBOARD_REGRESSION counters=12 details_requested=0 stats_timeout=90.0` 并退出 0；恢复旧版后再次退出 1。此次统计请求独立等待最多 90 秒，趋势和监控按需加载、局部报错；轮询使用同一次可见状态快照，避免首屏任务取消后跳过首轮。真实站点的 SQL、缓存和代理超时尚未测量或优化，不能用受控回归推断实际响应耗时。

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
