# Security Policy

## Supported Versions

The native rewrite is developed on `codex/native-ios-rebuild`. It is not yet a verified production release. `main` and `legacy-expo-3177500` preserve the previous Expo implementation.

| Version | Supported |
| ------- | --------- |
| codex/native-ios-rebuild | Development only; release and device checks pending |
| legacy-expo-3177500 | Preserved reference |

Native credentials belong in the device Keychain. Never commit passwords, Admin Keys, JWTs, certificates, private keys or provisioning profiles. Reports must redact full API keys and user data. The verification WebView must remain proof-only, same-origin, main-frame and nonce-bound. Management writes require explicit target confirmation; unknown balance outcomes must retain their original idempotency key and body.

## Reporting a Vulnerability

If you discover a security issue, please report it privately first.

Preferred channels:

1. Open a private security advisory in GitHub (if enabled).
2. If private advisory is not available, open an issue with minimal details and
   request a private follow-up from maintainers.

Please include:

- A clear description of the vulnerability
- Affected files/endpoints/flows
- Reproduction steps or proof of concept
- Potential impact
- Suggested remediation (if available)

## Response Expectations

- Initial triage target: within 3 business days
- Status update target: within 7 business days
- Fix timeline depends on severity and release constraints

We will coordinate disclosure timing after remediation is available.
