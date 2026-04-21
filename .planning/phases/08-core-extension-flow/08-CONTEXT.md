# Phase 8: Core Extension Flow - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

The full code request, delivery, auto-fill, and resilience pipeline working end-to-end across Chrome extension, relay, and iOS app. This phase completes the v1.0 happy path — user clicks account in extension, approves on phone, code appears and auto-fills.

</domain>

<decisions>
## Implementation Decisions

### Account Selection & Domain Matching
- **D-01:** Phone sends account list (issuer, label, ID) to extension when WebSocket connects. No persistent cache — extension shows accounts only while connected. Phase 9 adds full sync + caching.
- **D-02:** Extension sends account ID + current tab domain when user clicks an account. Phone uses ID to generate the specific code. Domain is passed for future smart sort usage tracking.
- **D-03:** Domain matching uses simple string-contains logic (domain contains issuer name or vice versa, case-insensitive). Same approach as CodeApprovalView.swift — consistent across platforms.

### Auto-Fill Detection & Injection
- **D-04:** Content script uses layered heuristics: (1) `autocomplete="one-time-code"`, (2) input name/id containing 'otp', 'totp', '2fa', 'verification', 'code', (3) single 6-digit maxlength input near a verify/submit button.
- **D-05:** Auto-fill happens immediately on code receive — no user confirmation step. If no TOTP field detected, falls back to popup display + clipboard copy.
- **D-06:** Content script handles split-input fields (6 separate single-digit inputs) by detecting groups of adjacent single-character inputs and distributing digits across them.

### Resilience UX
- **D-07:** Reconnection is silent — existing StatusDot turns yellow/orange during reconnect. No modal or blocking UI. If user requests code while disconnected, show inline "Reconnecting..." message.
- **D-08:** Proactive reconnect at 13 minutes (2-minute buffer before Railway's 15-min WebSocket timeout). Simple timer-based — gracefully close and re-establish.
- **D-09:** Service worker on wake: read pairing data from chrome.storage.local, read room ID + "should be connected" flag from session storage, auto-reconnect. Account list re-fetched from phone after reconnect.

### iOS Approval Sheet
- **D-10:** CodeApprovalView is already built. Phase 8 wires it up — ensure relay message triggers it correctly, trust window silent-send path works, and code response gets encrypted and sent back. Minimal visual changes.
- **D-11:** Background behavior: APNs alert push arrives, user taps notification, app opens directly to CodeApprovalView with the pending request. No silent auto-send from background — user always taps and approves.

### Claude's Discretion
- Content script injection timing (document_idle vs run_at configuration)
- Exact exponential backoff parameters for reconnection (already partially implemented)
- Message format for account list transfer over relay (encrypted envelope structure)
- Error states and edge cases in content script (multiple detected fields, iframes)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Extension Architecture
- `extension/src/entrypoints/background.ts` — Existing WebSocket, reconnection, keepalive, message routing
- `extension/src/entrypoints/popup/App.tsx` — Popup state management and view routing
- `extension/src/components/CodeView.tsx` — Code display with countdown ring (already complete)
- `extension/src/lib/crypto.ts` — X25519 + ChaCha20Poly1305 encryption (interop with CryptoKit)
- `extension/src/lib/storage.ts` — chrome.storage wrappers for pairing and session state
- `extension/src/lib/types.ts` — Message envelope types

### iOS Architecture
- `Shared/RelayClient.swift` — iOS WebSocket client, reconnection, keepalive, message handling
- `App/Views/CodeApprovalView.swift` — FaceID-gated approval sheet with domain matching and account picker
- `Shared/TrustWindowManager.swift` — 2-min FaceID trust window for silent code sends
- `Shared/CryptoBoxManager.swift` — E2E encryption (CryptoKit X25519 + ChaCha20Poly1305)
- `App/AppDelegate.swift` — APNs registration, push notification handling

### Relay Server
- `relay/` — WebSocket relay server (Node.js on Railway)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CodeView.tsx`: Complete code display with countdown ring, clipboard copy, 30s auto-clear — CODE-04 and FILL-03 already implemented
- `StatusDot.tsx`: Connection status indicator — can be extended for reconnection states
- `background.ts`: WebSocket management with 20s keepalive, exponential backoff reconnection, health check — RESIL-01 and RESIL-05 partially done
- `RelayClient.swift`: iOS WebSocket with same reconnection pattern — mirrors extension
- `CodeApprovalView.swift`: Full approval sheet with domain matching, account picker, FaceID gate — IOS-03 mostly done
- `TrustWindowManager.swift`: Silent-send path for trusted window — ready to use

### Established Patterns
- Message passing: `chrome.runtime.sendMessage` between popup and service worker
- State sync: `chrome.storage.session` for ephemeral state, `chrome.storage.local` for persistent
- Encrypted envelopes: `createEnvelope()` → `seal()` → WebSocket send (both directions)
- iOS state: `@Published` properties on singletons, `@EnvironmentObject` injection

### Integration Points
- Content script will need to be registered in WXT config (new entrypoint)
- Content script communicates with service worker via `chrome.runtime.sendMessage`
- Account list message needs new envelope type in `types.ts` and relay protocol
- iOS needs to send account metadata on WebSocket connect (new message in RelayClient)

</code_context>

<specifics>
## Specific Ideas

- Domain matching must be consistent between extension (TypeScript) and iOS (Swift) — both use simple string-contains, same logic as existing `CodeApprovalView.domainMatchedAccounts`
- Split-input handling should cover banking sites (Chase, Coinbase, etc.) where 6 separate `<input>` fields are common
- Trust window (Phase 7) only applies when app is in foreground with active WebSocket — background always requires push notification + user tap

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-core-extension-flow*
*Context gathered: 2026-04-20*
