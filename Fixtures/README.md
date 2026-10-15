# Sanitized API fixtures

These deterministic examples use reserved `.invalid` domains and placeholder identifiers. They follow the checked-out Sub2API backend's response envelopes and explicit snake_case field names; no live service or account was queried.

- Authentication: `/api/v1/auth/login`, `/auth/login/2fa`, `/auth/refresh`, `/auth/me`, `/auth/logout`.
- Administrator key: `x-api-key`; JWT: `Authorization: Bearer ...`.
- Pagination: `items`, `total`, `page`, `page_size`, `pages`.
- Balance writes: `POST /api/v1/admin/users/:id/balance`, `balance` is an exact decimal **string**, `operation` is `set/add/subtract`, with a stable `Idempotency-Key` UUID. Store the entire pending operation until its outcome is known.
- Account tests: `POST /api/v1/admin/accounts/:id/test`, JSON `model_id`, SSE `data` JSON uses `type`, `text`, `error`, and `success`. Success requires `test_complete` with `success:true`; EOF alone is failure.
- Dashboard initially loads only `/admin/dashboard/stats` (90s). Explicit detail buttons load yesterday-through-today hourly `/admin/dashboard/trend` (45s) and `/admin/ops/dashboard/overview` (15s, `qps.current`) independently. Missing metrics remain unavailable. `/admin/dashboard/realtime` is an authentication probe only; its placeholder zero values are never displayed.
- User usage intentionally queries `/admin/usage/stats?user_id=...&start_date=...&end_date=...&timezone=...`: the current backend's `/admin/users/:id/usage` implementation returns mock zeros and must not be presented as observed usage.

Tests construct equivalent fixtures inline to remain portable in SwiftPM and Xcode without runtime resource-path dependencies.
