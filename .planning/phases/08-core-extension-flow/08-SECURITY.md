---
phase: 08-core-extension-flow
auditor: gsd-secure-phase
asvs_level: 1
completed: 2026-04-21
threats_total: 15
threats_closed: 15
threats_open: 0
---

# Phase 08 Security Audit

## Result: SECURED

All 15 registered threats verified. Zero open threats.

## Threat Verification

| Threat ID | Category | Component | Disposition | Status | Evidence |
|-----------|----------|-----------|-------------|--------|----------|
| T-08-01 | Information Disclosure | domain-match.ts | accept | CLOSED | Accepted: domain matching operates on public issuer name only; no secrets in scope |
| T-08-02 | Tampering | storage.ts (session) | accept | CLOSED | Accepted: chrome.storage.session is same-extension-only; cleared on browser close |
| T-08-03 | Spoofing | AccountList.tsx request_code | accept | CLOSED | Accepted: chrome.runtime.sendMessage is extension-ID-scoped; no external caller path |
| T-08-04 | Denial of Service | AccountList infinite scroll | accept | CLOSED | Accepted: list bounded by phone account count; no pagination surface |
| T-08-05 | Information Disclosure | fill_code dispatch | mitigate | CLOSED | background.ts:288 — `tab.url?.startsWith('http')` guard before chrome.tabs.sendMessage |
| T-08-06 | Tampering | account_list decryption | mitigate | CLOSED | background.ts:313-324 — open() with shared ChaCha20Poly1305 key; tampered ciphertext throws, caught by try/catch |
| T-08-07 | Replay | code_request | mitigate | CLOSED | background.ts:435 — `id: crypto.randomUUID()` included in every encrypted codeRequest payload |
| T-08-08 | Information Disclosure | sendAccountListPayload | mitigate | CLOSED | RelayClient.swift:138-139 — map extracts only id/issuer/label; `secret` field absent; encrypted with CryptoBoxManager.seal (ChaChaPoly) before transit |
| T-08-09 | Spoofing | accountId in CodeRequest | mitigate | CLOSED | AccountStore.swift:241-245 — `UUID(uuidString:)` safe parse; invalid UUID falls through to FaceID approval path |
| T-08-10 | Denial of Service | proactive reconnect | accept | CLOSED | Accepted: single-fire 13-min Timer per connection; Railway rate limiting is server-side control |
| T-08-11 | Tampering | DOM fill | mitigate | CLOSED | WXT default content script world is ISOLATED; no explicit override in wxt.config.ts; page JS cannot intercept fill |
| T-08-12 | Information Disclosure | Code in DOM | accept | CLOSED | Accepted: code written to user-intended input field; equivalent to manual paste |
| T-08-13 | Spoofing | fill_code message | mitigate | CLOSED | content.ts:8 — chrome.runtime.onMessage listener; Chrome enforces same-extension-ID restriction on message delivery |
| T-08-14 | Denial of Service | Reconnect loop | mitigate | CLOSED | background.ts:177 — `Math.min(RECONNECT_BASE_MS * Math.pow(2, reconnectAttempts), RECONNECT_MAX_MS)` caps at 30s |
| T-08-15 | Tampering | shouldBeConnected flag | accept | CLOSED | Accepted: session storage is same-extension-only; cleared on browser close; worst case is a failed reconnect attempt |

## Unregistered Threat Flags

No `## Threat Flags` section present in any SUMMARY.md for this phase. No unregistered flags to record.

## Accepted Risks Log

| Threat ID | Category | Rationale |
|-----------|----------|-----------|
| T-08-01 | Information Disclosure | Issuer name is public metadata (visible in any authenticator app UI). No secret data enters domain-match.ts. |
| T-08-02 | Tampering | chrome.storage.session is inaccessible to any origin other than this extension. Browser close clears the session. |
| T-08-03 | Spoofing | chrome.runtime.sendMessage only routes to the extension matching the caller's ID. No external page can inject a request_code message. |
| T-08-04 | Denial of Service | Practical account count on any device is <100; session storage list write is O(n); no scroll virtualization needed. |
| T-08-10 | Denial of Service | 13-minute timer fires once per WebSocket lifetime. Burst reconnect scenario is bounded by Railway's server-side rate limiter. |
| T-08-12 | Information Disclosure | Writing a TOTP code to the field the user opened the authenticator to fill is the intended action. Risk is identical to copy-paste. |
| T-08-15 | Tampering | An attacker with same-extension-origin access already has full extension trust. Worst-case manipulation of shouldBeConnected triggers one reconnect attempt that fails if pairing is absent. |

## Notes

**T-08-11 (Isolated world):** WXT does not expose a `world` override in wxt.config.ts. The WXT framework defaults all content scripts to `ISOLATED` world per the Manifest V3 specification. The absence of an explicit `world: 'MAIN'` declaration in content.ts confirms isolation is in effect.

**T-08-05 and T-08-13 relationship:** T-08-05 prevents the service worker from dispatching fill_code to privileged pages (chrome://, extension://). T-08-13 prevents external pages from injecting a fill_code message. Together they form a two-sided boundary on the fill code path.

**T-08-06 and T-08-08 relationship:** Both threats operate on the same ChaCha20Poly1305 channel. T-08-08 ensures secrets never enter the ciphertext on the iOS side; T-08-06 ensures tampered ciphertext is rejected on the extension side. The AEAD tag covers both confidentiality and authenticity.
