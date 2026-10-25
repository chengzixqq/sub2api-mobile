# Native implementation contract

This file fixes interfaces shared by the parallel implementation. The source of truth for wire DTOs is the current Sub2API backend, not the legacy mobile client. All public core values are Sendable; decoding uses explicit snake_case CodingKeys (do not combine convertFromSnakeCase with acronym property names).

## Ownership

- Core agent: `Package.swift`, `Sources/Sub2Core/**`, `Tests/Sub2CoreTests/**`, `Fixtures/**`.
- App agent: `NativeApp/**`, `UITests/**`, credential coordination regression tests.
- Root: Xcode project, scripts, CI, documentation, integration, verification artifacts.
- Web bridge agent: isolated `G:/weixinProject/sub2-mobile-backend` worktree only.

## Stable core interface

Use these public names and signatures. Add supporting types as needed and announce changes to the other agent.

```swift
enum AuthenticationKind: String, Codable, Sendable { case adminKey, password }
struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var name: String
  var baseURL: URL
  var authentication: AuthenticationKind
  init(id: UUID = UUID(), name: String, baseURL: URL, authentication: AuthenticationKind)
}
struct TokenPair: Codable, Sendable { var accessToken: String; var refreshToken: String; var expiresAt: Date }
enum Credential: Codable, Sendable { case adminKey(String), tokens(TokenPair) }
protocol CredentialStore: Sendable {
  func load(serverID: UUID) async throws -> Credential?
  func save(_ credential: Credential, serverID: UUID) async throws
  func remove(serverID: UUID) async throws
}
struct CaptchaProof: Codable, Sendable {
  var turnstileToken: String?; var tencentTicket: String?; var tencentRandstr: String?
  init(turnstileToken: String? = nil, tencentTicket: String? = nil, tencentRandstr: String? = nil)
}
struct TwoFactorChallenge: Sendable { let tempToken: String; let maskedEmail: String? }
struct AuthSession: Sendable { let user: AdminUser; let tokens: TokenPair }
enum LoginResult: Sendable { case authenticated(AuthSession), twoFactor(TwoFactorChallenge) }

actor APIClient {
  init(server: ServerProfile, credential: Credential? = nil, credentialStore: (any CredentialStore)? = nil)
  func publicSettings() async throws -> PublicSettings
  func login(email: String, password: String, proof: CaptchaProof? = nil) async throws -> LoginResult
  func completeTOTP(tempToken: String, code: String) async throws -> AuthSession
  func me() async throws -> AdminMe  // 阶段 0 替换 verifyAdministrator()；旧服务端退路见 FINAL-SPEC 00 §1.9
  func currentCredential() -> Credential?
  func logout() async throws
  func cancelAll() async
  func dashboard() async throws -> DashboardSummary
  func accounts(page: Int, search: String, status: String?, platform: String?) async throws -> Page<UpstreamAccount>
  func account(id: Int) async throws -> UpstreamAccount
  func accountTodayStats(id: Int) async throws -> AccountTodayStats
  func setSchedulable(id: Int, enabled: Bool) async throws -> UpstreamAccount
  func refreshAccount(id: Int) async throws
  func testAccount(id: Int, model: String?) async throws -> AsyncThrowingStream<AccountTestEvent, Error>
  func users(page: Int, search: String, status: String?) async throws -> Page<AdminUser>
  func user(id: Int) async throws -> AdminUser
  func userUsage(id: Int) async throws -> UserUsageSummary
  func userKeys(id: Int, page: Int) async throws -> Page<UserAPIKey>
  func setUserStatus(id: Int, status: String) async throws -> AdminUser
  func updateBalance(_ operation: PendingBalanceOperation) async throws -> AdminUser
  func stepUp(code: String) async throws
}
```

## UI-facing values

- `Page<T>`: items, total, page, pageSize, pages; `hasMore: Bool`.
- `AdminUser`: id Int, email String, username String?, balance Decimal, status String, role String?, concurrency Int?.
- `UpstreamAccount`: id Int, name String, platform String, type String, status String, schedulable Bool, errorMessage String?, concurrency Int?.
- `DashboardSummary`: initial stats DashboardStats, empty trend and nil monitoring. `dashboardTrend()` and `dashboardMonitoring()` load details explicitly with independent states/errors; slow or failed details must not delay or discard the counters.
- `DashboardStats`: todayRequests Int, todayTokens Int, todayCost Decimal, totalUsers Int, totalAccounts Int, errorAccounts Int, rpm Double, tpm Double.
- `TrendPoint`: date String, requests Int, totalTokens Int, cost Decimal; Identifiable.
- `OpsSnapshot`: errorRate Double?, qps Double?, activeRequests Int? (missing is unavailable, never fabricated zero).
- `AccountTodayStats`: requests Int, tokens Int, cost Decimal.
- `UserUsageSummary`: totalRequests Int, totalTokens Int, totalCost Decimal.
- `UserAPIKey`: id Int, name String, key String?, status String, quota Decimal, quotaUsed Decimal (UI masks key).
- `PublicSettings`: captchaProvider String? (`turnstile`, `tencent`, `aliyun`, nil), captchaEnabled Bool.
- `AccountTestEvent`: type String, content String?, message String?; `isTerminal`, `isSuccess`.
- `BalanceOperation`: String/Codable/CaseIterable/Sendable enum set/add/subtract.
- `PendingBalanceOperation`: Identifiable/Codable/Sendable, id UUID, serverID UUID, userID Int, amount Decimal, operation BalanceOperation, notes String; public initializer defaults id UUID, notes empty. `id` is the stable Idempotency-Key. Validate nonnegative, finite amount, operation validity; wire amount as exact decimal string. Persist until outcome is known.
- `APIError`: LocalizedError/Sendable with useful Chinese messages; expose `reason: String?` and `statusCode: Int?`. Map CAPTCHA, TOTP/step-up, session binding, compliance, permissions, invalid response and transport errors distinctly. Never put tokens in descriptions.

## Bridge contract

`GET /mobile/verify?nonce=<UUID>` on the configured same-origin HTTPS station. The page posts only through `window.webkit.messageHandlers.sub2Captcha.postMessage({version:1,nonce,provider,proof:{turnstile_token?,tencent_captcha_ticket?,tencent_captcha_randstr?}})`. A cancel envelope may carry `cancelled:true` without proof. Native accepts only expected nonce, main frame, exact station scheme/host/effective port, known provider, and provider-appropriate nonempty proof fields. No credentials/tokens in the URL or message. Reset proof after failed login, cancellation or expiry.

## Isolation and verification

AppModel is MainActor/Observable. Persist profiles separately from credentials; verify before activating; failed add never replaces old active connection. An active-session generation UUID fences all completion writes, lists and detail screens. Use `.id(sessionGeneration)` on the authenticated tree; cancellation alone is insufficient. Sign-out and removal cancel work and erase credentials. Never automatically retry mutation requests; balance retries reuse original operation UUID and body. SSE EOF without `test_complete`/`error` fails. Local tests must use injected URLSession transport or URLProtocol rather than real servers.
