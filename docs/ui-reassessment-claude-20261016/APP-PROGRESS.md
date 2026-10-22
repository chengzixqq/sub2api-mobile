# 原生 App 实现进度

按 [FINAL-SPEC.md](FINAL-SPEC.md)“实现顺序建议”分阶段实现。每个条目一个提交（之后可能跟着审查修正提交），提交前在 Mac 上跑工具链守卫、单元测试、编译与 UI 测试。

## 阶段 0 · 通用约定、会话与应用骨架

| 条目 | 标题 | 状态 | 提交 | 备注（与规格不同的取舍、未做的部分、UI 测试是否运行） |
|---|---|---|---|---|
| S0-01 | 工具链锁定 Xcode 27.1，最低系统 iOS 26 | ✅ | `777623b` | Xcode 27.1 `27A9275` 由同号 RC 转正；单元测试 109 项与编译通过；UI 测试基线见下 |
| S0-02 | 错误信封、reason 总表与 APIError 改造 | ✅ | `145f9de` | 规格写“—/不显示”的组合用过渡文案（页面流程上线前现有页面直接显示错误）：TOKEN_EXPIRED“登录已失效，请重新登录”、STEP_UP_REQUIRED“该操作需要先完成二次验证”、423“需要先完成管理员合规确认”、TOO_MANY_IDS 用参数类文案、ACCOUNT_STATS_UNAVAILABLE 与 OAUTH_EXCHANGE_FAILED 用“站点暂时不可用”（20 章“服务器连不上 {平台}”待页面填平台）、PUSH_DELIVERY_FAILED 暂不带 provider_reason、未知 reason 的 429 写“请求过于频繁，请 N 秒后再试”。规格内冲突的取舍：USER_NOT_ACTIVE / BACKEND_MODE_ADMIN_ONLY 按请求上下文给文案与动作；STEP_UP_UNAVAILABLE 用 3.2 文案（2.6.2 带“，请稍后重试”的留给 S0-13 的验证 sheet）；ACCOUNT_TEST_BUSY 用 2.7.2、PUSH_DEVICE_LIMIT_REACHED 用 7.2、幂等各码用 2.5.4 与 30 章文案；未知 reason 的 400 归 `.response`（不归 `.validation`，资金写待核对判定不变）；其他 4xx 按 400 规则，1xx/3xx 写“服务器未能完成请求（HTTP N）”；不像错误码的 reason 不进主文案。文案暗含的 App 动作现有页面还不会做，留给对应阶段：409 业务冲突与 412 的“已刷新”、TOO_MANY_IDS 拆批、SINCE_ID_WITH_PAGE 退回第 1 页、ACCOUNT_STATS_UNAVAILABLE 显示“—”、非 JSON 404 隐藏功能、OPS_DISABLED 区域显示。“不可用”全局改“—”留给 S0-08（本条只有 diagnostics 用“—”）。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过） |
| S0-03 | AdminMe、capability 常量与模型放宽 | ✅ | `46acec7` | me() 取代 verifyAdministrator，类型名按规格与 D15 用 AdminAccessToken / AdminComplianceStatus（不叫 AccessTokenItem）。对规格的补充：Admin Key / sat_ 旧服务端路径同时并发拉 settings/public（取版本与时区，失败容忍）；admin/compliance 也是非 JSON 404（2026-06 之前、没有合规守卫的站点）时退回 dashboard/realtime 探针，全仓只此一处；JWT 旧服务端三调里 auth/me 失败照抛、settings/public 失败视为未知、admin/compliance 仅非 JSON 404 视为未知。Page.hasMore 保持 Bool（has_more → pages → total），原始值为 reportedHasMore。PublicSettings 另保留 site_logo、渠道监控、支付、订阅字段；冲突改由登录页抛 CAPTCHA_PROVIDER_CONFLICT 的目录文案。D33：未知 AuthenticationKind 按 password 解码，profiles / profileArchive 逐条容错；升级后不支持装回旧版 IPA（旧版读不到 accessToken）。行为变化：合规未确认的 Admin Key 站点现在可连接（以前 realtime 返回 423 连不上），之后的请求按 423 文案提示，全局合规页归 S0-13；账号页重新加载期间总数显示“—”。暂不做（归后续条目）：me 结果存进 SiteSession、sat_ 连接后取 scope（注意 admin/access-tokens 不在合规豁免里，合规未确认时返回 423，S0-10 按可写处理、S0-13 确认后补取）、LoginBody 的 captcha_provider / aliyun_captcha_param、登录页 sat_ 自动识别。S0-02 的 APIErrorMappingTests 冲突断言改为“解码成功且报告冲突”。UI 测试已运行：35 个全部通过（脚本统计 34，漏计的 1 个在日志里折行，已核对通过）；编译输出里 CaptchaView.swift:91 的警告在本条之前就存在，见 BACKLOG |

## UI 测试基线（改动前，`efcb8c1`）

Mac 补装 Xcode 27.1 的 CoreSimulator 组件后，在 iPhone 18 Pro（iOS 27）模拟器上运行旧代码的 35 个 UI 测试：

| 运行 | 方式 | 用时 | 结果 |
|---|---|---|---|
| 1 | 串行 | 57 分钟 | 29 通过、6 失败 |
| 2 | 4 台模拟器并行 | 25 分钟 | 33 通过、2 失败 |

两次失败的用例不同，说明这些旧测试在新模拟器上不稳定。两次合计失败过的 7 个：`AccountListCustomizationUITests` 的字段偏好隔离、容量字段隐藏与排序、今日统计慢、今日统计失败、分组并发与字段顺序，`Sub2MobileUITests` 的趋势图缩放与小时选择，`UserManagementUITests` 的用户字段选择与顺序。之后的检查改为 6 台并行、失败自动重跑一次；这 7 个由 S0-19 统一诊断（App 在 iOS 27 上的真实缺陷就修 App，测试时序问题就修测试，页面会在后续阶段重写的记明原因）。
