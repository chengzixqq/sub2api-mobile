# Mobile verification bridge validation

Repository: `G:/weixinProject/sub2-mobile-backend`
Branch: `codex/mobile-verification-bridge`
Baseline: `40bee5d2e39393c9d0edf9f9079fc4e4e00af50d`
Implementation commit: `d75c49405d5639a58b0deb821339c3145b22bc52`
Patch: `G:/weixinProject/sub2-mobile-native/integration/mobile-verification.patch`
Patch SHA-256: `c5f0d6199addd0608cd39cd9b929d9a87cb82c987c92a2a2c75804a3bb2f0038`
Patch bytes: 35175

## Implemented contract

Public frontend `GET /mobile/verify?nonce=<UUID>`. Direct entry mounts only the lightweight page, bypassing Web application auth/settings startup. The router also allows this route before auth/backend-mode guards. Public configuration is fetched from same-origin `/api/v1/settings/public` with `credentials: omit`, `cache: no-store`, a 30-second timeout and no Authorization header.

Only `window.webkit.messageHandlers.sub2Captcha.postMessage` receives messages. Success: `{version:1,nonce,provider,proof}`. Turnstile and Aliyun use only `proof.turnstile_token` (Aliyun carries captchaVerifyParam); Tencent uses only `proof.tencent_captcha_ticket` and `proof.tencent_captcha_randstr`. Cancellation: `{version:1,nonce,cancelled:true}`. Only one completed message per nonce/page. Reject insecure/non-HTTPS context, non-main frame, missing native handler, invalid/duplicate nonce, additional URL parameters, userinfo, fragments and wrong path. Recheck nonce/origin at submission. Native must independently enforce exact station scheme/host/effective port, main frame, UUID nonce, version/provider and proof field whitelist.

Providers mount only after user action. Handle expiry, errors, cancellation, two-minute challenge timeout, retry and disabled/incomplete provider configuration. No passwords, API keys or access/refresh tokens enter bridge URLs/messages. Uses existing provider components, no new server authentication bypass.

## Observed verification

All commands ran in `G:/weixinProject/sub2-mobile-backend/frontend` unless stated.

1. `pnpm install --frozen-lockfile --offline`: exit 1; missing cached Vue 3.5.43 tarball (`ERR_PNPM_NO_OFFLINE_TARBALL`). Corrected with `pnpm install --frozen-lockfile`: exit 0; lockfile unchanged.
2. Initial focused tests: 30 passed, 4 failed because Vitest 2.1.9 does not support `toHaveBeenCalledExactlyOnceWith`; changed to supported once/count and argument assertions.
3. Final focused command: `pnpm exec vitest run src/utils/__tests__/mobileCaptchaBridge.spec.ts src/views/public/__tests__/MobileVerifyView.spec.ts src/__tests__/mobileVerificationBootstrap.spec.ts src/router/__tests__/mobile-verification-route.spec.ts src/router/__tests__/feature-access.spec.ts`
   Literal summary: `Test Files  5 passed (5)`; `Tests  47 passed (47)`; exit 0. New tests: 25 helper, 10 view, 1 bootstrap, 1 route. Existing feature-access regression tests: 10.
4. `pnpm run typecheck`: `vue-tsc --noEmit`; exit 0.
5. `pnpm exec eslint src/main.ts src/router/index.ts src/utils/mobileCaptchaBridge.ts src/utils/__tests__/mobileCaptchaBridge.spec.ts src/views/public/MobileVerifyView.vue src/views/public/__tests__/MobileVerifyView.spec.ts src/__tests__/mobileVerificationBootstrap.spec.ts src/router/__tests__/mobile-verification-route.spec.ts`: empty stdout/stderr; exit 0.
6. `pnpm run build`: exit 0. i18n completeness `Test Files  1 passed (1)`, `Tests  3 passed (3)`; `vue-tsc -b` passed; Vite `1160 modules transformed`, `built in 19.12s`. Created ignored local frontend bundle, including `backend/internal/web/dist/assets/MobileVerifyView-C4WpshEP.js` (6776 bytes). Build reports existing broad chunk-size/dynamic-import notices and old Browserslist metadata; no build failure.
7. `git diff --check` in repository root: empty output; exit 0 before commit.
8. After commit, `git status --short` in repository root: empty output (clean). `git apply --reverse --check G:/weixinProject/sub2-mobile-native/integration/mobile-verification.patch`: empty output; exit 0, confirming the exported patch reverses cleanly against the committed implementation.

## Limits and change boundaries

Automated tests use controlled captcha component substitutes; real vendor SDK and actual iPhone WKWebView integration require a deployed test station. Native acceptance must reject subframe/wrong-origin/replayed messages. No production station was modified and no live credentials used. Original `G:/weixinProject/sub2` was not installed into or edited by this bridge task. Commit is local only; no push/deploy performed. Build outputs and node_modules remain ignored local artifacts.

## Changed files

- `.gitignore`: allow the bridge contract document.
- `frontend/src/main.ts`: isolated direct bootstrap.
- `frontend/src/router/index.ts`: unauthenticated route and early route guard.
- `frontend/src/utils/mobileCaptchaBridge.ts`: typed envelope, trust context and proof selection.
- `frontend/src/views/public/MobileVerifyView.vue`: provider lifecycle and native handoff.
- `docs/mobile-verification.md`: deployment and native receiver contract.
- Four focused test files listed in command 3.
