# Feature Landscape: Chrome Extension TOTP Auto-Fill + Phone-to-Browser Relay

**Domain:** Phone-paired browser TOTP delivery
**Researched:** 2026-04-14
**Overall confidence:** HIGH (core feature categories); MEDIUM (UX detail specifics)

---

## Table Stakes

Features users expect from any phone-paired browser TOTP extension. Missing any of these means the product is immediately abandoned or never trusted.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Click-to-fill from popup | Core interaction model. Users click the extension icon, pick an account, code fills. Seen in Bitwarden, 1Password, all standalone authenticators. | Low | The popup opens, shows matched or full account list, user picks; content script fills the field. |
| Auto-detect TOTP fields on the active page | Users expect the extension to know which page they are on and pre-select the matching account. Bitwarden and 1Password both do domain-matched account surfacing. | Medium | Primary heuristic: `autocomplete="one-time-code"` attribute. Fallback heuristics: input type=text with label text containing "code", "otp", "2fa", "authenticator", "verification", 6-digit maxlength. Multi-box OTP layouts (6 separate single-digit inputs) must also be handled. |
| Visual code expiry countdown | Users need to know if the code they received is still valid before they submit. All major TOTP apps (Google Authenticator, Authy, Bitwarden) show a countdown. | Low | A circular progress bar or numeric countdown over the 30s window. Codes arriving with <5s left should be visually flagged or the flow should wait for the next code. |
| One-time QR code pairing (setup) | The security model is based on a phone-browser pairing. Users expect QR-scan-once, never again. Krypton/kr-u2f and Firefox's own pairing flow both use this model. | Medium | Extension displays a QR code embedding a room ID + ephemeral secret. iOS app scans it. Pairing completes. Session persists until explicitly revoked. |
| Biometric gate on phone before code is sent | Users expect the phone to ask for Face ID / Touch ID before transmitting the code. This is the primary security assertion. Microsoft Authenticator and Duo Mobile both gate approvals on biometrics. | Low (iOS side) | Already exists in KeyAuth via LocalAuthentication. This must be preserved and surfaced at every relay code request, not bypassed. |
| Push notification to wake the phone | Users expect to receive a push notification when the desktop requests a code — they should not need the app open. This is the standard flow in Duo Mobile, Microsoft Authenticator, and Krypton. | Medium | APNs required. Relay server must hold the APNs device token and send a content-available push when the extension requests a code. The iOS app wakes, prompts Face ID, sends code. |
| Secure-in-transit relay only (TLS) | Users expect the relay to not be a third party that reads codes. TLS (wss://) is the baseline; codes expire in 30s anyway. | Low | wss:// is mandatory. The relay must never log code payloads. |
| Clipboard fallback / copy button | When auto-fill fails (shadow DOM, non-standard field, SPA that re-renders), users expect to at least copy the code. Bitwarden falls back to clipboard-copy automatically when field-fill fails. | Low | Copy button in popup, auto-clear clipboard after 30s (Keeper does this; it is now expected). |
| Account list with site-based filtering | When the popup opens on a domain that has a saved TOTP account, that account should float to the top. Showing an unfiltered list of all accounts on every page is a friction source. 1Password and Bitwarden both do domain-matched surfacing. | Low | Extension reads the active tab URL, matches hostname against stored account issuer/label, surfaces matches first. |
| Pairing status indicator | Users need to know if the phone is reachable before initiating a code request. Sending a request to an unreachable phone and waiting with no feedback is the top UX complaint in relay extensions (documented in OpenClaw/openclaw issues). | Low | Extension icon badge or popup banner: "Phone connected" / "Phone offline – open KeyAuth". |
| Graceful reconnect on WebSocket drop | MV3 service workers terminate after 30s idle. The WebSocket closes on sleep/wake cycles. Users expect the extension to silently reconnect without requiring a re-pair. Reconnect without re-pairing was a documented pain point in Krypton and openclaw relay. | Medium | Exponential backoff reconnect (1s → 2s → 4s… cap 30s). Re-use stored room ID and auth token. Do not invalidate pairing on reconnect. Keepalive ping every 20s to extend MV3 service worker lifetime (Chrome 116+ behavior). |

---

## Differentiators

Features that are not universally expected but provide meaningful competitive advantage or meaningfully improve the experience over alternatives.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Secrets-never-leave-phone security model | Unlike Bitwarden and 1Password (which store TOTP secrets in the cloud vault), KeyAuth's relay never exposes the TOTP seed. Only the generated 6-digit code travels the wire, and only for 30 seconds. This is a meaningful security claim. | Low (architectural) | Must be prominently communicated. The relay is a dumb pipe — it routes bytes, stores nothing, logs nothing. This is a differentiator over cloud-stored TOTP managers. |
| Auto-fill into the page without user touching the code | The end-to-end flow: user clicks extension icon → picks account → phone buzzes → Face ID → code fills automatically into the page. The user never sees or types the code. Bitwarden's TOTP requires clipboard-paste on most pages. 1Password can auto-fill TOTP but only if secrets are stored in 1Password. | Medium | Content script listens for a "code_ready" message from service worker, then calls `input.value = code; input.dispatchEvent(new Event('input', {bubbles:true})); input.dispatchEvent(new Event('change', {bubbles:true}));` and optionally submits the form. |
| Works across different networks (not local-only) | Bluetooth and local network approaches fail across VPNs, corporate networks, and when the phone is on cellular. A cloud relay works everywhere. | Low (architectural) | Already designed this way. Worth surfacing as a feature claim. |
| No browser secret storage | The extension stores no TOTP seeds, no private keys. If the extension is compromised, the attacker gets nothing of cryptographic value — only session routing tokens that expire. | Low (architectural) | Contrast with Bitwarden/1Password where extension compromise could expose vault. |
| Countdown-aware code delivery | If the current TOTP period has <5s remaining when the request completes, automatically wait for the next code rather than delivering a nearly-expired one. | Low | TOTP period boundary detection: `remaining = 30 - (Math.floor(Date.now()/1000) % 30)`. If remaining < 5, the iOS app waits one period before generating and sending. |
| Multi-account search in popup | When users have many accounts, a search/filter field in the popup with real-time filtering by issuer or label. Bitwarden has this; standalone TOTP extensions often do not. | Low | Client-side filter of the account list by issuer/label string. |

---

## Anti-Features

Features to explicitly NOT build in v1 (or ever). Each entry includes the reason this was deliberately rejected.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Storing TOTP seeds in the browser extension | Completely defeats the security model. If secrets live in the browser, the relay is irrelevant. This is what Bitwarden/1Password do — and why they are meaningfully weaker for TOTP security. | TOTP seeds stay in iOS Keychain. Period. Extension only stores: room ID, connection token, paired device name. |
| Auto-fill on page load without user interaction | Fills TOTP fields before the user intends to complete login. Can accidentally submit or confuse SPA flows. Bitwarden explicitly disables TOTP autofill on page load. Also, Chrome's CSP policies make this unreliable. | Fill only on explicit user action (click in popup or inline fill button click). |
| E2E encryption layer on top of TLS in v1 | Significant added complexity (key exchange, key storage, rotation) for marginal gain when: (a) the relay is user-owned, (b) codes expire in 30s, (c) TLS already encrypts in transit. 1Password uses TLS-only for their relay. | TLS only for v1. Flag E2E as a post-v1 enhancement with proper threat model analysis. |
| Bluetooth / local transport | Chrome extensions cannot use the Web Bluetooth API from a content script or service worker in a meaningful way for this use case. Krypton tried local transport for SSH and it was the #1 source of pairing failures on corporate networks. | WebSocket relay only. Works across all networks including cellular + corporate VPN. |
| Firefox / Safari extension in v1 | Three different extension manifest formats, three CSP models, three WebExtension API surface differences. Triples QA surface. | Chrome only for v1. Extension is MV3-native; Safari and Firefox support is a post-v1 milestone with Manifest V3 alignment becoming viable. |
| Self-hosted relay option in v1 | Doubles the deployment surface, documentation burden, and support surface. The "bring your own relay" use case is real but is a post-v1 power-user feature. | Railway-hosted relay only. Expose relay URL as a configurable setting in the extension options page to make future self-hosted support easier. |
| Auto-push notification on any TOTP field detection | Automatically sending a push notification to the phone every time the extension detects a TOTP field (without user action) is a spam/battery drain anti-pattern. Duo Mobile specifically requires user-initiated approval requests. | User must click in the extension popup to initiate the request. Detection is passive (surfaces matched accounts); push only fires on explicit "request code" action. |
| Copying TOTP seed / QR code export from extension | The extension has no seeds to export, but if a seed-export feature were added it would be a catastrophic security regression. | No seed access in the extension. Account management (add/remove accounts) stays on iOS only. |
| Persistent WebSocket connection when popup is closed | MV3 service workers are terminated after 30s idle. Attempting to maintain a persistent idle connection burns battery, triggers Chrome's idle-kill, and requires the keepalive hack. It also requires an offscreen document workaround that adds complexity. | On-demand connect: WebSocket connects when popup opens or a code request is in flight. Reconnects from stored room ID. 20s keepalive ping only during active sessions. |
| Account sync across multiple browsers | Introduces a sync backend, conflict resolution, and a second credential store. Out of scope entirely. | Single paired device (phone) + single Chrome profile. One-to-one pairing. |

---

## Feature Dependencies

```
QR pairing (setup) ─────────────────────────────────────────────────────────────────┐
     │                                                                               │
     └─→ Room ID + auth token stored in extension                                   │
              │                                                                      │
              └─→ WebSocket reconnect (uses stored room ID, no re-pair)             │
                       │                                                             │
                       └─→ Pairing status indicator (knows if phone is reachable)   │
                                │                                                    │
                                └─→ Click-to-request flow ──────────────────────────┘
                                         │
                                         └─→ APNs push notification to phone
                                                  │
                                                  └─→ Face ID gate on phone
                                                           │
                                                           └─→ Code delivered via relay
                                                                    │
                                                       ┌────────────┴────────────┐
                                                       │                         │
                                              Auto-fill field              Clipboard fallback
                                                       │
                                              TOTP field detection
                                              (must run before fill)

Countdown-aware delivery ── depends on → Code delivered via relay
Multi-account search ─────── depends on → Account list with site-based filtering
```

**Critical path for v1:** QR pairing → WebSocket relay → APNs push → Face ID → code delivery → auto-fill + countdown display

All other features are additive to this path.

---

## MVP Recommendation

**Must ship (table stakes, on critical path):**
1. QR code pairing (one-time setup)
2. WebSocket relay with TLS, reconnect on drop, 20s keepalive in popup
3. APNs push notification to wake phone
4. Face ID gate before code is sent (existing iOS code, must be wired to relay request)
5. TOTP field detection (`autocomplete=one-time-code` + fallback heuristics, single-field and multi-box)
6. Auto-fill into detected field
7. Clipboard copy + 30s auto-clear (fallback for detection failures)
8. Pairing status indicator in popup
9. Expiry countdown on received code
10. Account list with domain-based filtering (matched accounts first)

**Defer (post-MVP):**
- Countdown-aware delivery (wait for next period if <5s remaining): useful but not blocking
- Multi-account search: needed at >~20 accounts; most users start with fewer
- E2E encryption layer: threat model doesn't require it for v1
- Firefox/Safari extension
- Self-hosted relay option
- Configurable relay URL (add the setting now but hide it; enables future self-host without redesign)

---

## Sources

- [1Password TOTP auto-fill documentation](https://support.1password.com/one-time-passwords/)
- [1Password compatible website design (OTP field heuristics)](https://developer.1password.com/docs/web/compatible-website-design/)
- [Bitwarden integrated authenticator](https://bitwarden.com/help/integrated-authenticator/)
- [Bitwarden autofill from browser extensions](https://bitwarden.com/help/auto-fill-browser/)
- [Chrome DevDocs: WebSockets in service workers (MV3 keepalive behavior)](https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets)
- [Chrome service worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
- [Krypton/kr-u2f deprecated repository (architecture reference)](https://github.com/kryptco/kr-u2f)
- [Firefox pairing flow architecture (QR + WebSocket channel architecture)](https://mozilla.github.io/ecosystem-platform/explanation/pairing-flow-architecture)
- [Faktor (macOS native + Chrome extension TOTP relay, Show HN 2024)](https://news.ycombinator.com/item?id=40832206)
- [OpenClaw browser relay disconnect issues (relay UX failure modes)](https://github.com/openclaw/openclaw/issues/32331)
- [Resilient relay fork with exponential backoff pattern](https://github.com/Unayung/openclaw-browser-relay)
- [autocomplete=one-time-code WHATWG spec](https://github.com/whatwg/html/issues/3745)
- [2FA UX patterns: LogRocket (biometric gate, push approval flow)](https://blog.logrocket.com/ux-design/2fa-user-flow-best-practices/)
- [APNs background push (content-available) documentation](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
