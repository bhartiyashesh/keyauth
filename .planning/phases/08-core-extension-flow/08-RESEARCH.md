# Phase 8: Core Extension Flow - Research

**Researched:** 2026-04-20
**Domain:** Chrome extension + iOS app integration via WebSocket relay (code request/delivery/auto-fill pipeline)
**Confidence:** HIGH

## Summary

Phase 8 completes the v1.0 happy path: user clicks an account in the Chrome extension popup, the phone generates a TOTP code after biometric approval, delivers it over the encrypted relay, and the extension displays it with countdown and optionally auto-fills the detected TOTP field on the active webpage. The phase also hardens resilience (reconnection, service worker wake, proactive timeout avoidance).

The codebase is heavily pre-built. The extension already has WebSocket management with keepalive/reconnection (`background.ts`), code display with countdown (`CodeView.tsx`), connection state management, and E2E encryption (`crypto.ts`). iOS has `RelayClient.swift` with the same patterns, `CodeApprovalView.swift` with FaceID-gated approval and domain matching, and `TrustWindowManager` for silent-send. The primary new work is: (1) account list UI in the extension popup, (2) content script for TOTP field detection and auto-fill, (3) wiring account-specific code requests (with account ID), and (4) proactive reconnection at 13 minutes.

**Primary recommendation:** Build in layers -- first wire the account list flow (phone sends accounts on connect, extension displays them, click requests specific code), then add content script auto-fill, then polish resilience (proactive reconnect, service worker wake robustness).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Phone sends account list (issuer, label, ID) to extension when WebSocket connects. No persistent cache -- extension shows accounts only while connected. Phase 9 adds full sync + caching.
- **D-02:** Extension sends account ID + current tab domain when user clicks an account. Phone uses ID to generate the specific code. Domain is passed for future smart sort usage tracking.
- **D-03:** Domain matching uses simple string-contains logic (domain contains issuer name or vice versa, case-insensitive). Same approach as CodeApprovalView.swift -- consistent across platforms.
- **D-04:** Content script uses layered heuristics: (1) `autocomplete="one-time-code"`, (2) input name/id containing 'otp', 'totp', '2fa', 'verification', 'code', (3) single 6-digit maxlength input near a verify/submit button.
- **D-05:** Auto-fill happens immediately on code receive -- no user confirmation step. If no TOTP field detected, falls back to popup display + clipboard copy.
- **D-06:** Content script handles split-input fields (6 separate single-digit inputs) by detecting groups of adjacent single-character inputs and distributing digits across them.
- **D-07:** Reconnection is silent -- existing StatusDot turns yellow/orange during reconnect. No modal or blocking UI. If user requests code while disconnected, show inline "Reconnecting..." message.
- **D-08:** Proactive reconnect at 13 minutes (2-minute buffer before Railway's 15-min WebSocket timeout). Simple timer-based -- gracefully close and re-establish.
- **D-09:** Service worker on wake: read pairing data from chrome.storage.local, read room ID + "should be connected" flag from session storage, auto-reconnect. Account list re-fetched from phone after reconnect.
- **D-10:** CodeApprovalView is already built. Phase 8 wires it up -- ensure relay message triggers it correctly, trust window silent-send path works, and code response gets encrypted and sent back. Minimal visual changes.
- **D-11:** Background behavior: APNs alert push arrives, user taps notification, app opens directly to CodeApprovalView with the pending request. No silent auto-send from background -- user always taps and approves.

### Claude's Discretion
- Content script injection timing (document_idle vs run_at configuration)
- Exact exponential backoff parameters for reconnection (already partially implemented)
- Message format for account list transfer over relay (encrypted envelope structure)
- Error states and edge cases in content script (multiple detected fields, iframes)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CODE-03 | TOTP code generated on phone after biometric approval, sent via relay | CodeApprovalView.swift already handles FaceID + TOTPGenerator. Wire `code_request` with account ID to trigger it. |
| CODE-04 | Extension popup displays received code with expiry countdown | CodeView.tsx already complete -- no new work beyond integration |
| CODE-05 | Extension surfaces relevant accounts based on current website domain | New AccountList component with domain matching (D-03 string-contains logic) |
| FILL-01 | Content script detects TOTP input fields using autocomplete and heuristic fallbacks | New content script entrypoint with D-04 layered heuristics |
| FILL-02 | Extension auto-fills detected TOTP field with received code | Content script fill logic + split-input handling (D-06) |
| FILL-03 | Clipboard copy with automatic 30-second clear as fallback | Already implemented in CodeView.tsx |
| RESIL-01 | Service worker sends 20-second WebSocket keepalive pings | Already implemented in background.ts |
| RESIL-02 | Both clients proactively reconnect before Railway's 15-min timeout | New: 13-minute timer on both extension and iOS (D-08) |
| RESIL-03 | Service worker rebuilds state from chrome.storage.session on every wake | Already partially implemented; strengthen with D-09 account re-fetch |
| RESIL-04 | iOS app registers APNs device token on every launch | AppDelegate.swift handles token registration (verify wiring) |
| RESIL-05 | Extension reconnects and rejoins room on WebSocket drop | Already implemented in background.ts scheduleReconnect() |
| IOS-03 | iOS presents TOTP approval sheet (account name, site, approve/deny + Face ID) | CodeApprovalView.swift is complete; wire relay trigger correctly |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Account list display | Chrome Extension (popup) | -- | UI lives in extension popup; data sourced from phone via relay |
| Domain matching (extension) | Chrome Extension (service worker) | -- | Needs `chrome.tabs` API to get current domain |
| Code request initiation | Chrome Extension (popup -> service worker) | -- | User clicks account, message passes to background for WebSocket send |
| Biometric approval + TOTP generation | iOS App | -- | Secrets never leave phone; FaceID is device-local |
| Code delivery | Relay Server (pass-through) | -- | Relay forwards encrypted envelopes, no decryption |
| TOTP field detection | Chrome Extension (content script) | -- | DOM access required; runs in page context |
| Auto-fill injection | Chrome Extension (content script) | -- | Writes to DOM input fields |
| Reconnection management | Chrome Extension (service worker) + iOS App | Relay (timeout config) | Both clients own their reconnection; relay just closes stale sockets |
| Push notification routing | iOS App (AppDelegate) | APNs infrastructure | Alert push triggers user tap -> CodeApprovalView |
| Account list sync (on connect) | iOS App (RelayClient) | Chrome Extension (service worker) | Phone sends list; extension stores in session state |

## Standard Stack

### Core (Already Installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WXT | ^0.20.0 | Extension framework (entrypoints, HMR, manifest generation) | [VERIFIED: package.json] |
| React | ^19.0.0 | Popup UI | [VERIFIED: package.json] |
| @noble/ciphers | ^2.2.0 | ChaCha20-Poly1305 encryption | [VERIFIED: package.json] |
| @noble/curves | ^2.2.0 | X25519 key exchange | [VERIFIED: package.json] |
| @noble/hashes | ^2.2.0 | HKDF-SHA256 key derivation | [VERIFIED: package.json] |
| vitest | ^3.1.0 | Unit testing | [VERIFIED: package.json] |

### Supporting (No New Dependencies Needed)
This phase requires NO new npm packages. All capabilities (WebSocket, crypto, DOM manipulation, chrome APIs) are available natively or via existing dependencies.

**Installation:** None required -- all dependencies already in place. [VERIFIED: codebase inspection]

## Architecture Patterns

### System Architecture Diagram

```
User clicks account in popup
        |
        v
[Popup (React)] --sendMessage--> [Service Worker (background.ts)]
        |                                    |
        |                          encrypt(accountId + domain)
        |                                    |
        |                                    v
        |                         [WebSocket to Relay Server]
        |                                    |
        |                          forward encrypted envelope
        |                                    |
        |                                    v
        |                         [iOS RelayClient.swift]
        |                                    |
        |                          decrypt -> CodeRequest
        |                                    |
        |                              +-----------+
        |                              | Trust     |
        |                              | Window?   |
        |                              +-----+-----+
        |                            yes/        \no
        |                           /             \
        |                  silent-send      present CodeApprovalView
        |                     code          FaceID -> TOTPGenerator
        |                          \             /
        |                           \           /
        |                            v         v
        |                      encrypt(code + requestId)
        |                                    |
        |                                    v
        |                         [WebSocket to Relay Server]
        |                                    |
        |                          forward encrypted envelope
        |                                    v
        |                         [Service Worker]
        |                          decrypt -> code
        |                                    |
        |               +--------------------+--------------------+
        |               |                                         |
        |               v                                         v
        |    [Content Script]                            [Popup CodeView]
        |    detect TOTP field                           display + countdown
        |    auto-fill if found                          clipboard copy fallback
        v
[User sees code / field auto-filled]
```

### Recommended Project Structure
```
extension/src/
├── entrypoints/
│   ├── background.ts          # WebSocket, message routing (existing, extend)
│   ├── content.ts             # NEW: TOTP field detection + auto-fill
│   └── popup/
│       └── App.tsx            # Popup state machine (existing, refactor)
├── components/
│   ├── AccountList.tsx        # NEW: scrollable account list
│   ├── AccountItem.tsx        # NEW: single account row
│   ├── CodeView.tsx           # Existing (no changes)
│   ├── ConnectedView.tsx      # Existing (replace button with AccountList)
│   ├── StatusDot.tsx          # Existing (minimal changes)
│   └── ReconnectingBanner.tsx # NEW: inline reconnection indicator
├── lib/
│   ├── crypto.ts              # Existing (no changes)
│   ├── storage.ts             # Existing (extend for account list)
│   ├── types.ts               # Existing (add new message types)
│   └── domain-match.ts        # NEW: shared domain matching logic
└── styles/
```

### Pattern 1: WXT Content Script Entrypoint
**What:** File-based content script registration using WXT conventions
**When to use:** Detecting and filling TOTP fields on web pages
**Example:**
```typescript
// Source: Context7 WXT docs - content script entrypoints
// entrypoints/content.ts
export default defineContentScript({
  matches: ['*://*/*'],  // All HTTP/HTTPS pages
  runAt: 'document_idle', // After DOM is ready (Claude's discretion)
  main(ctx) {
    // Listen for fill commands from service worker
    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (message.type === 'fill_code') {
        const filled = attemptFill(message.code);
        sendResponse({ filled });
      }
      return true;
    });

    // Clean up on context invalidation (extension update)
    ctx.onInvalidated(() => {
      // Remove any injected indicators
    });
  },
});
```
[VERIFIED: Context7 WXT docs]

### Pattern 2: Account List Transfer Over Relay
**What:** Phone sends account metadata on WebSocket connect; extension stores in session
**When to use:** After WebSocket joins room and connection is established
**Example:**
```typescript
// New message type for account list
interface AccountMetadata {
  id: string;       // UUID string
  issuer: string;   // e.g., "GitHub"
  label: string;    // e.g., "user@email.com"
}

// Encrypted envelope payload: { accounts: AccountMetadata[] }
// Sent by iOS after joining room, received in handleRelayMessage
```
[ASSUMED -- message format is Claude's discretion per CONTEXT.md]

### Pattern 3: Content Script <-> Service Worker Communication
**What:** Service worker sends fill command to content script on active tab after receiving code
**When to use:** After code_response is decrypted
**Example:**
```typescript
// In background.ts after decrypting code
const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
if (tab?.id) {
  const response = await chrome.tabs.sendMessage(tab.id, {
    type: 'fill_code',
    code: decryptedCode,
  });
  if (!response?.filled) {
    // Fallback: show in popup only (existing CodeView behavior)
  }
}
```
[VERIFIED: chrome.tabs.sendMessage is the standard pattern for service worker -> content script]

### Pattern 4: Proactive Reconnection Timer
**What:** Close and re-establish WebSocket at 13 minutes to avoid Railway's 15-min timeout
**When to use:** Both extension service worker and iOS RelayClient
**Example:**
```typescript
// In background.ts connect() onopen handler
const PROACTIVE_RECONNECT_MS = 13 * 60 * 1000; // 13 minutes
let proactiveTimer: ReturnType<typeof setTimeout> | null = null;

// After successful connect:
proactiveTimer = setTimeout(() => {
  console.log('[KeyAuth] Proactive reconnect (13min timer)');
  ws?.close(1000, 'proactive'); // Normal closure
  // onclose will trigger scheduleReconnect with delay=0 or immediate reconnect
}, PROACTIVE_RECONNECT_MS);
```
[ASSUMED -- exact implementation is Claude's discretion]

### Anti-Patterns to Avoid
- **Caching account list in chrome.storage.local this phase:** D-01 explicitly says no persistent cache -- Phase 9 adds that. Use chrome.storage.session only.
- **Sending TOTP secrets to the extension:** Core security model -- secrets NEVER leave the phone. Only account metadata (id, issuer, label) crosses the relay.
- **Blocking modal for reconnection:** D-07 mandates silent reconnection. StatusDot + inline text only.
- **Auto-fill on page load without user action:** Out of scope per REQUIREMENTS.md (security anti-pattern confirmed by 1Password, Bitwarden).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| E2E encryption | Custom crypto protocol | Existing `crypto.ts` / `CryptoBoxManager.swift` | Already built and tested -- X25519 + ChaCha20Poly1305 with CryptoKit interop |
| TOTP generation | Custom TOTP algorithm | Existing `TOTPGenerator.swift` | RFC 6238 compliant, already handles SHA1/256/512, 6/7/8 digits |
| WebSocket reconnection | Custom reconnect logic | Existing exponential backoff in `background.ts` / `RelayClient.swift` | Both already implement 1s->30s capped backoff with attempt counter |
| Domain matching | Complex URL parsing library | Simple string-contains (D-03) | Proven pattern already in CodeApprovalView.swift; consistency is more important than sophistication |
| Countdown timer | External timer library | Existing `CountdownRing` in CodeView.tsx | Already handles 30s TOTP period, red at <5s, auto-dismiss |

**Key insight:** This phase is primarily integration work -- connecting existing well-built components. Resist the urge to refactor working systems; focus on wiring them together.

## Common Pitfalls

### Pitfall 1: Content Script Injection on Restricted Pages
**What goes wrong:** Content script fails silently on `chrome://`, `chrome-extension://`, `edge://`, and `file://` pages. User gets no auto-fill and no error.
**Why it happens:** Chrome blocks content script injection on privileged URLs for security.
**How to avoid:** In `background.ts`, check `tab.url` starts with `http://` or `https://` before calling `chrome.tabs.sendMessage`. Gracefully fall back to popup-only display.
**Warning signs:** "Could not establish connection" errors in console.

### Pitfall 2: Service Worker Termination Mid-Request
**What goes wrong:** Service worker terminates between sending code_request and receiving code_response (Chrome kills idle workers after ~30s with no events).
**Why it happens:** WebSocket `onmessage` keeps the worker alive, but if there's a gap in messages the worker may die.
**How to avoid:** The 20s keepalive ping (RESIL-01) already prevents this -- pong responses keep the worker alive. Verify the keepalive interval is shorter than Chrome's termination threshold.
**Warning signs:** Code request sent but response never received; user has to re-open popup.

### Pitfall 3: Split-Input Field Detection False Positives
**What goes wrong:** Content script incorrectly identifies non-OTP inputs as split fields (e.g., phone number inputs, credit card number segments).
**Why it happens:** Multiple adjacent single-character inputs are common for phone numbers and credit cards too.
**How to avoid:** Require EXACTLY 6 adjacent single-char inputs (matching 6-digit TOTP). Also check parent container for OTP-related class names or aria-labels. Verify the inputs are of type="text" or type="tel" (not type="password" for credit card CVV).
**Warning signs:** User reports wrong fields being filled on banking sites.

### Pitfall 4: Race Between Popup Close and Code Receive
**What goes wrong:** User opens popup, clicks account, closes popup (impatient), code arrives but popup is gone -- no auto-fill triggered.
**Why it happens:** Popup closing doesn't cancel the service worker flow. Code arrives in background.ts which stores it in session state, but content script fill command is never sent because nothing triggers it.
**How to avoid:** After receiving code in background.ts, ALWAYS attempt content script fill regardless of popup state. Then store code in session state for popup display if user re-opens.
**Warning signs:** Code appears in popup when re-opened but field on page wasn't filled.

### Pitfall 5: Account List Stale After Phone Sleeps
**What goes wrong:** Phone's WebSocket drops (phone sleep, network switch), extension still shows old account list but requests fail.
**Why it happens:** Extension only gets account list on connect. If phone disconnects without extension knowing (relay just drops connection), the accounts shown are stale.
**How to avoid:** Tie account list visibility to connection state (D-01: "shows accounts only while connected"). When connectionState transitions to disconnected, clear the account list from session storage. Re-fetch on reconnect.
**Warning signs:** User sees accounts but clicking shows "Reconnecting..." error.

### Pitfall 6: iOS APNs Token Refresh Not Sent to Relay
**What goes wrong:** APNs token changes (iOS periodically refreshes it). Old token stored in relay means push notification fails silently.
**Why it happens:** Token refresh happens in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` but relay isn't updated.
**How to avoid:** On every token callback, call `RelayClient.shared.registerToken(newToken)`. The relay already supports `register_token` message type. Also register on every app launch (RESIL-04).
**Warning signs:** Background code requests never wake the phone; works fine when app is in foreground.

## Code Examples

### Content Script: TOTP Field Detection (D-04 Heuristics)
```typescript
// Source: D-04 locked decisions + standard TOTP field patterns
function detectTOTPField(): HTMLInputElement | null {
  // Layer 1: autocomplete="one-time-code" (most reliable)
  const autocompleteField = document.querySelector<HTMLInputElement>(
    'input[autocomplete="one-time-code"]'
  );
  if (autocompleteField) return autocompleteField;

  // Layer 2: name/id heuristics
  const otpKeywords = ['otp', 'totp', '2fa', 'verification', 'code'];
  const allInputs = document.querySelectorAll<HTMLInputElement>(
    'input[type="text"], input[type="tel"], input[type="number"], input:not([type])'
  );
  for (const input of allInputs) {
    const identifier = `${input.name} ${input.id} ${input.placeholder}`.toLowerCase();
    if (otpKeywords.some(kw => identifier.includes(kw))) {
      return input;
    }
  }

  // Layer 3: single 6-digit maxlength input near submit button
  for (const input of allInputs) {
    if (input.maxLength === 6 || input.getAttribute('maxlength') === '6') {
      const form = input.closest('form');
      if (form) {
        const hasSubmit = form.querySelector('button[type="submit"], input[type="submit"]');
        if (hasSubmit) return input;
      }
    }
  }

  return null;
}
```
[VERIFIED: patterns from decision D-04; field detection is standard practice]

### Content Script: Split-Input Fill (D-06)
```typescript
// Source: D-06 locked decision + common banking site patterns
function detectSplitInputs(): HTMLInputElement[] | null {
  const allInputs = Array.from(
    document.querySelectorAll<HTMLInputElement>('input[maxlength="1"]')
  );
  
  // Find groups of 6 adjacent single-char inputs
  for (let i = 0; i <= allInputs.length - 6; i++) {
    const group = allInputs.slice(i, i + 6);
    // Check they're visually adjacent (same parent or consecutive siblings)
    const parent = group[0].parentElement;
    const allSameParent = group.every(input => 
      input.parentElement === parent || 
      input.closest('[class*="otp"], [class*="code"], [class*="pin"], [class*="verify"]')
    );
    if (allSameParent || areVisuallyAdjacent(group)) {
      return group;
    }
  }
  return null;
}

function fillSplitInputs(inputs: HTMLInputElement[], code: string): void {
  const digits = code.replace(/\s/g, '');
  inputs.forEach((input, i) => {
    if (i < digits.length) {
      // Use native setter to trigger React/Angular change detection
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype, 'value'
      )?.set;
      nativeInputValueSetter?.call(input, digits[i]);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }
  });
}
```
[VERIFIED: native setter pattern is required for React-controlled inputs]

### Domain Matching (D-03 -- Shared Logic)
```typescript
// Source: mirrors CodeApprovalView.swift domainMatchedAccounts logic
export function domainMatchesIssuer(domain: string, issuer: string): boolean {
  if (!domain || !issuer) return false;
  const domainLower = domain.toLowerCase();
  const issuerLower = issuer.toLowerCase();
  // "github.com" contains "github", or "GitHub" contains "github" (from domain minus .com)
  return domainLower.includes(issuerLower) 
    || issuerLower.includes(domainLower.replace(/\.com$|\.org$|\.io$|\.net$/, ''));
}
```
[VERIFIED: matches CodeApprovalView.swift line 22-25 logic exactly]

### iOS: Send Account List on Connect
```swift
// Source: new functionality required by D-01
// In RelayClient.swift or triggered by WebSocketDelegate.didOpen
func sendAccountList() {
    guard let sharedKey = PairingStore.shared.sharedKey else { return }
    let accounts = AccountStore.shared?.accounts ?? []
    let metadata: [[String: String]] = accounts.map {
        ["id": $0.id.uuidString, "issuer": $0.issuer, "label": $0.label]
    }
    guard let plaintext = try? JSONEncoder().encode(["accounts": metadata]),
          let encrypted = try? CryptoBoxManager.seal(Data(plaintext), using: sharedKey)
    else { return }
    let envelope = MessageEnvelope(
        type: "account_list",
        payload: ["data": encrypted.base64EncodedString()]
    )
    send(envelope)
}
```
[ASSUMED -- exact implementation detail; concept matches D-01 requirement]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `document_start` content scripts | `document_idle` (default in MV3) | Chrome MV3 (2023) | Less blocking, DOM guaranteed ready |
| `chrome.tabs.executeScript` (MV2) | Content script declared in manifest (MV3) | Chrome MV3 | Must declare in manifest or use `scripting` permission |
| Background pages (persistent) | Service workers (ephemeral) | Chrome MV3 | Must reconstruct state on every wake from storage |
| Clipboard API sync (`document.execCommand`) | `navigator.clipboard.writeText` (async) | 2020+ | Already using async API in CodeView.tsx |

**Deprecated/outdated:**
- `chrome.extension.sendMessage`: Use `chrome.runtime.sendMessage` (already correct in codebase)
- MV2 persistent background pages: Codebase already uses MV3 service worker pattern

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Account list message format uses encrypted envelope with type "account_list" | Code Examples (iOS) | Low -- message type naming is arbitrary; just needs to match both sides |
| A2 | Proactive reconnect at 13 min uses setTimeout + graceful close | Architecture Patterns | Low -- approach is sound; exact timer implementation may vary |
| A3 | Railway's WebSocket timeout is 15 minutes | Context (from D-08) | Medium -- if timeout changed, the 13-min proactive reconnect timing would need adjustment |
| A4 | Content script `document_idle` is optimal timing | Claude's Discretion | Low -- document_idle guarantees DOM ready; document_end is alternative if faster detection needed |

## Open Questions (RESOLVED)

1. **Account list message: new envelope type or reuse `forwarded`?**
   - What we know: Relay forwards all unknown message types as-is. Can use custom type "account_list" or generic forwarding.
   - What's unclear: Whether relay needs explicit handling for account_list or if opaque forwarding suffices.
   - Recommendation: Use opaque forwarding (relay doesn't need to know about account_list). Add type to extension's handleRelayMessage switch case.

2. **Content script match patterns: `*://*/*` vs specific patterns?**
   - What we know: `*://*/*` matches all HTTP/HTTPS pages. More specific patterns reduce overhead but may miss sites.
   - What's unclear: Performance impact of running on every page.
   - Recommendation: Use `*://*/*` -- the content script is lightweight (just registers a message listener). Actual detection only runs when code is received.

3. **Should content script proactively scan for TOTP fields on page load?**
   - What we know: D-05 says auto-fill happens on code receive. Requirements say no auto-fill on page load (out of scope, security anti-pattern).
   - Recommendation: Content script is passive -- only scans when service worker sends `fill_code` message. No proactive scanning.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest ^3.1.0 |
| Config file | extension/vitest.config.ts (or default WXT config) |
| Quick run command | `cd extension && npx vitest run` |
| Full suite command | `cd extension && npx vitest run` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CODE-03 | Code request encrypted and sent via relay | unit | `npx vitest run --filter "code request"` | Wave 0 |
| CODE-04 | Code display with countdown | unit | `npx vitest run --filter "CodeView"` | Wave 0 |
| CODE-05 | Domain matching sorts accounts | unit | `npx vitest run --filter "domain match"` | Wave 0 |
| FILL-01 | TOTP field detection heuristics | unit | `npx vitest run --filter "detect"` | Wave 0 |
| FILL-02 | Auto-fill injection (single + split) | unit | `npx vitest run --filter "fill"` | Wave 0 |
| FILL-03 | Clipboard copy + 30s clear | unit | existing CodeView tests | Check |
| RESIL-01 | 20s keepalive pings | unit | `npx vitest run --filter "keepalive"` | Wave 0 |
| RESIL-02 | Proactive 13-min reconnect | unit | `npx vitest run --filter "proactive"` | Wave 0 |
| RESIL-03 | Service worker state rebuild from storage | unit | `npx vitest run --filter "wake"` | Wave 0 |
| RESIL-04 | APNs token registration | manual-only | iOS device testing required | N/A |
| RESIL-05 | Auto-reconnect on drop | unit | `npx vitest run --filter "reconnect"` | Wave 0 |
| IOS-03 | Approval sheet triggers on relay message | manual-only | iOS device testing required | N/A |

### Sampling Rate
- **Per task commit:** `cd extension && npx vitest run`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green + manual e2e test of happy path

### Wave 0 Gaps
- [ ] `extension/src/lib/__tests__/domain-match.test.ts` -- covers CODE-05
- [ ] `extension/src/entrypoints/__tests__/content.test.ts` -- covers FILL-01, FILL-02
- [ ] `extension/src/entrypoints/__tests__/background.test.ts` -- covers RESIL-02, RESIL-03, RESIL-05

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | FaceID/biometric via iOS LocalAuthentication (BiometricAuthManager.swift) |
| V3 Session Management | no | No user sessions -- pairing is device-to-device |
| V4 Access Control | yes | Biometric gate before code generation; trust window time-limited |
| V5 Input Validation | yes | Content script validates DOM inputs before fill; relay validates envelope structure |
| V6 Cryptography | yes | X25519 + ChaCha20Poly1305 + HKDF-SHA256 (existing, no hand-rolling) |

### Known Threat Patterns for Chrome Extension + WebSocket

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Man-in-the-middle on relay | Information Disclosure | E2E encryption -- relay only sees ciphertext [VERIFIED: existing crypto.ts + CryptoBoxManager] |
| Malicious content script injection | Tampering | WXT builds to ISOLATED world (default); no eval() |
| Extension message spoofing | Spoofing | `chrome.runtime.sendMessage` only works within same extension ID |
| Clipboard sniffing by other extensions | Information Disclosure | 30-second clipboard auto-clear (existing in CodeView.tsx) |
| Replay attack on code_response | Tampering | requestId correlation + ChaCha20 nonce uniqueness |

## Sources

### Primary (HIGH confidence)
- Context7 `/websites/wxt_dev` -- content script entrypoint configuration, messaging patterns
- Codebase inspection -- `background.ts`, `RelayClient.swift`, `CodeApprovalView.swift`, `crypto.ts`, `types.ts`, `storage.ts`, `AccountStore.swift`, `Account.swift`
- WXT documentation (via Context7) -- defineContentScript, ctx.onInvalidated, runAt options

### Secondary (MEDIUM confidence)
- Chrome MV3 documentation (training knowledge) -- service worker lifecycle, chrome.tabs.sendMessage, content script messaging

### Tertiary (LOW confidence)
- Railway WebSocket timeout of 15 minutes (from D-08 user decision, not independently verified)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already installed and verified in package.json
- Architecture: HIGH -- existing code patterns are clear; phase is integration of existing components
- Pitfalls: HIGH -- derived from Chrome MV3 known behaviors and codebase-specific patterns

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (stable -- no fast-moving dependencies)
