# Domain Pitfalls

**Domain:** Chrome MV3 Extension + WebSocket Relay + APNs + iOS App
**Project:** KeyAuth
**Researched:** 2026-04-14

---

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or the core flow silently failing in production.

---

### Pitfall 1: Service Worker State Loss on Every Wake

**What goes wrong:** The MV3 service worker is not persistent. Chrome terminates it after 30 seconds of no extension events. Any in-memory state — the WebSocket object, pending request correlation IDs, pairing metadata — is gone when it wakes up for the next event. Code written assuming the service worker is always alive will silently fail on the first cold start.

**Why it happens:** MV3 explicitly removed persistent background pages. The service worker lifecycle matches web service workers: spin up per-event, spin down when idle. Developers familiar with MV2 background scripts assume persistence that no longer exists.

**Consequences:** WebSocket is `null` when the user clicks the popup after a gap. Correlation IDs for in-flight TOTP requests are lost. The extension appears to hang with no error surfaced to the user.

**Prevention:**
- Treat the service worker as stateless. Rebuild all in-memory state from `chrome.storage.session` on every wake.
- Use `chrome.storage.session` (persists across service worker restarts within a browser session, cleared on browser close) for transient state like active pairing and pending request IDs.
- Use `chrome.storage.local` for durable state like the relay URL and paired device ID.
- Never rely on a global variable surviving between events.

**Warning signs:**
- "Works first time, then stops working until extension is reloaded"
- Code like `let ws = null` at module level with no re-init logic on startup
- Pending request IDs stored only in a JS `Map`, not in `chrome.storage`

**Phase:** Chrome Extension — service worker architecture (before writing any message-passing logic)

---

### Pitfall 2: WebSocket Keepalive Is Required Even in Chrome 116+

**What goes wrong:** Chrome 116 improved WebSocket support so an active connection resets the 30-second idle timer — but only while messages flow. A WebSocket that is connected but silent for more than 30 seconds will still cause the service worker to terminate and the connection to close. Assuming the Chrome 116 fix eliminates the need for keepalive is incorrect.

**Why it happens:** The documentation improvement was real, but the underlying mechanism is "reset idle timer on WS activity." No activity = no reset = termination.

**Consequences:** The relay connection drops silently any time the user is not actively requesting a code. The next request attempt hits a closed socket, has to reconnect, negotiate, and then send — easily exceeding the 30-second TOTP window.

**Prevention:**
- Send a ping message from the service worker to the relay server every 20 seconds (10-second margin before the 30-second cutoff).
- The relay server must respond with a pong. The response message counts as WS activity and resets the timer.
- Add `"minimum_chrome_version": "116"` to `manifest.json` to make the requirement explicit.
- Clear the keepalive interval when the WebSocket closes to avoid orphaned timers.

**Warning signs:**
- No ping/pong logic in the WebSocket client code
- Service worker logs show it restarting frequently
- Users report that a second code request in the same session fails to deliver

**Phase:** Chrome Extension — WebSocket client implementation

---

### Pitfall 3: Railway's 15-Minute WebSocket Timeout Forces Client Reconnection

**What goes wrong:** Railway terminates any WebSocket connection that has been open for more than 15 minutes, regardless of activity. This is a hard platform limit at the Cloudflare/proxy layer. An extension that connects once and never reconnects will silently drop after 15 minutes.

**Why it happens:** Railway routes traffic through a proxy that enforces a 15-minute maximum request duration for both SSE and WebSocket connections. This is documented but easy to miss when testing locally (where no such proxy exists).

**Consequences:** The extension and iOS app both believe they are connected, but the relay has dropped them. The next TOTP request is silently lost. The user sees a spinner with no response.

**Prevention:**
- Implement reconnection logic in both the Chrome extension service worker and the iOS app.
- Reconnect proactively at ~14 minutes (before Railway cuts the connection) rather than reactively on error.
- On reconnect, rejoin the relay room using the stored pairing token so the server re-associates the device.
- Test with a 15-minute clock in CI or manually — the failure only appears in production-like environments.

**Warning signs:**
- "Works for a while, then stops responding" reported exactly around 15-minute intervals
- No `onclose` reconnect handler in the WebSocket client
- Testing only against local relay (which has no timeout)

**Phase:** Relay server + both clients (design the reconnection protocol before implementing it)

---

### Pitfall 4: iOS WebSocket Drops When App Goes to Background

**What goes wrong:** `URLSessionWebSocketTask` cannot maintain an active connection when the iOS app is backgrounded. iOS suspends the process shortly after it leaves the foreground. The socket is closed by the OS. This is by design and cannot be worked around without background modes.

**Why it happens:** iOS has strict background execution limits. The standard URL session APIs — including WebSocket tasks — are not eligible for background operation. Only background URL session (download/upload tasks), VoIP PushKit, and a small set of background modes survive suspension.

**Consequences:** If the design assumes the iOS app maintains a persistent relay connection, it will work only when the app is in the foreground. Every use case where the phone is sitting idle (locked, home screen) will fail — which is the majority of actual usage.

**Prevention:**
- Do not design around a persistent iOS WebSocket. Design around APNs wakeup.
- The correct flow: relay server receives a code request from Chrome extension → relay calls APNs → APNs delivers an alert push notification to the iOS app → the user taps it (or it wakes the app in foreground) → the app opens, connects WebSocket, authenticates, sends code → relay forwards code to extension.
- Keep `URLSessionWebSocketTask` as a foreground-only connection. Connect on app launch/foreground transition; disconnect cleanly on background.
- Use `applicationDidEnterBackground` / `sceneDidEnterBackground` to close the WebSocket gracefully.

**Warning signs:**
- Simulator testing works but real device testing fails when the phone is locked
- The iOS app tries to `.resume()` a task in a background URLSession configured for WebSocket

**Phase:** iOS app — relay client design (must be settled before any iOS WebSocket code is written)

---

### Pitfall 5: Silent APNs Pushes Are Throttled and Cannot Be Used for TOTP Wakeup

**What goes wrong:** `content-available: 1` (silent / background) push notifications are throttled by iOS at approximately 3 per hour per device. Apple's throttling logic is undocumented and based on battery state, usage patterns, and app behavior. For a TOTP flow that must wake the app reliably on demand, silent pushes are not reliable.

**Why it happens:** Silent pushes are designed for eventual consistency use cases (syncing data, prefetching content) — not real-time, user-initiated triggers. Apple intentionally limits them to prevent background battery drain.

**Consequences:** The user requests a TOTP code; the relay sends a silent push; iOS decides not to deliver it (or delays it by minutes). The extension shows no response. The code window expires. The user has no idea why it failed.

**Prevention:**
- Use **alert push notifications** (with `alert.title` and `alert.body`) for the TOTP code request. Alert pushes have higher delivery priority and are not subject to the same throttle limits.
- The relay server sends: `{ "aps": { "alert": { "title": "KeyAuth", "body": "Code requested for [site]" }, "sound": "default" } }`.
- The iOS app handles `userNotificationCenter(_:didReceive:withCompletionHandler:)` to present the Face ID prompt when the user taps the notification.
- Do not use `content-available: 1` as the primary wakeup signal. If silent pushes are used at all, they must be treated as optional hints.

**Warning signs:**
- APNs payload contains only `content-available: 1` with no `alert` key
- Flow design says "app wakes in background to handle request" (not possible without VoIP / PushKit)
- Testing in simulator passes (simulators deliver silent pushes differently than real devices)

**Phase:** Relay server — APNs integration; iOS app — push notification handling

---

### Pitfall 6: APNs JWT Provider Token Expires After One Hour

**What goes wrong:** The relay server authenticates to APNs using a JWT signed with the `.p8` private key (token-based auth). APNs requires this JWT to be issued within the last hour. The server generates one token at startup and reuses it indefinitely. After 60 minutes, APNs returns `ExpiredProviderToken (403)` and all push deliveries silently fail.

**Why it happens:** Token-based APNs authentication uses short-lived JWTs, not persistent certificates. The JWT `iat` (issued-at) claim is validated server-side by Apple. Libraries that don't auto-rotate the token leave this as developer responsibility.

**Consequences:** TOTP code requests from the extension reach the relay. The relay tries to send an APNs push. APNs rejects it. The relay gets a 403 with no visible user-facing error. The extension times out waiting for a response. Fails silently in production.

**Prevention:**
- The relay must generate a new JWT before each APNs HTTP/2 request, or cache the token and regenerate it when it is older than 45-50 minutes (with margin before the 60-minute limit).
- Track the token creation timestamp on the relay. If `Date.now() - tokenCreatedAt > 45 * 60 * 1000`, regenerate.
- Use a library that handles token rotation automatically (e.g., `@parse/node-apn` with token auth configured, or `apns2`). Verify the library actually rotates — some have bugs where they do not (check their GitHub issues before choosing).
- Ensure the relay server's system clock is NTP-synchronized. A clock drift of a few minutes causes `InvalidProviderToken` even when the token was recently generated.

**Warning signs:**
- APNs calls work in testing but fail after the server has been running for an hour
- The relay logs show 403 responses from `api.push.apple.com`
- No token age check in the APNs request code
- Railway restarts fix the problem temporarily (token is regenerated on restart)

**Phase:** Relay server — APNs integration

---

### Pitfall 7: APNs Device Token Goes Stale After App Reinstall or iOS Upgrade

**What goes wrong:** The APNs device token stored on the relay server becomes invalid when the iOS app is reinstalled, restored from backup, or after certain iOS updates. APNs eventually returns `BadDeviceToken (400)` or `Unregistered (410)`, but the timing of this feedback is undocumented and may be delayed by hours or days. Meanwhile, all pushes to that device fail silently.

**Why it happens:** Device tokens are not permanent. APNs rotates them under conditions that Apple does not publish. The relay server has no way to know a token has changed unless the app sends a fresh token after re-registration.

**Consequences:** After the user reinstalls the KeyAuth iOS app (or gets a new device), push notifications stop working. The relay keeps sending to the old token. No error is surfaced. The extension hangs on every code request.

**Prevention:**
- The iOS app must call `UIApplication.shared.registerForRemoteNotifications()` on every app launch (not just first launch) and send the resulting token to the relay whenever it changes.
- Use `UserDefaults` or Keychain to cache the last-sent token. Only call the relay's "register device" endpoint when the token is new or different from the cached value.
- The relay must handle `410 Unregistered` from APNs by treating the stored token as invalid and returning an error to the Chrome extension so the user can re-pair.
- When APNs returns `BadDeviceToken (400)`, log it and surface a re-pairing prompt in the extension popup.

**Warning signs:**
- Users who reinstall the app report the extension stops working
- The relay has no endpoint for updating the device token after initial pairing
- APNs error responses are ignored or not logged

**Phase:** iOS app — device token registration; relay server — token storage and error handling

---

### Pitfall 8: The 30-Second TOTP Window Can Expire During the Relay Round-Trip

**What goes wrong:** The full flow is: user clicks extension → extension sends WS message to relay → relay calls APNs → APNs delivers push → user sees notification, taps, Face ID prompt → Face ID auth → iOS app connects WebSocket → iOS app generates TOTP → sends to relay → relay forwards to extension → extension fills field. If any leg of this chain introduces latency (slow APNs delivery, slow Face ID, slow reconnect), the generated code can be near-expiration or already expired by the time it is filled.

**Why it happens:** TOTP codes have a 30-second step (RFC 6238 default). Codes are valid at generation time but continue aging in transit. A round trip that takes 20+ seconds hands the user a code with 10 seconds left — often not enough to fill and submit it.

**Consequences:** The autofilled code is rejected by the target site. The user does not understand why and retries, creating a confusing loop.

**Prevention:**
- Generate the TOTP code on the iOS app as **late as possible** — only after Face ID has succeeded and the relay WebSocket is connected. Do not generate eagerly on push receipt.
- Implement ±1 step acceptance (accept the previous step's code) on the server side of the target site — but this is out of scope for KeyAuth. Instead, optimize the flow to complete within 10 seconds.
- Display the TOTP code's remaining lifetime in the extension popup so the user can see if they need to retry.
- Log timestamps at each step in development to identify slow legs. APNs delivery is typically <2 seconds. Face ID is ~1 second. The slow leg is usually iOS reconnect on a cold start.

**Warning signs:**
- Round-trip time is not measured during development
- The code is generated at push receipt time (on the iOS side) before Face ID
- No visual countdown shown to the user in the extension

**Phase:** iOS app — TOTP delivery flow; Chrome extension — popup UI design

---

## Moderate Pitfalls

Mistakes that cause user-facing failures or significant rework, but not a full rewrite.

---

### Pitfall 9: Relay Room Pairing Has No Expiry — Stale Rooms Accumulate

**What goes wrong:** The relay server creates a room when a device pair is established. If rooms are never cleaned up, the server accumulates stale room state from old pairings, test devices, and disconnected clients. On Railway's memory-constrained environment, this will eventually cause OOM restarts.

**Prevention:**
- Assign a TTL to each room. Expire rooms where no client has connected within 24 hours.
- On Railway restart, all in-memory room state is lost anyway — design the client to re-announce its presence on connect rather than assuming the relay remembers it.
- Use a heartbeat from each connected client; remove a client from the room map when their heartbeat stops for >60 seconds.

**Warning signs:**
- Room map grows monotonically in server memory
- No room cleanup code exists
- Memory usage on Railway climbs over days

**Phase:** Relay server — room lifecycle design

---

### Pitfall 10: QR Pairing Code Is Not Time-Limited or Single-Use

**What goes wrong:** The QR code displayed by the Chrome extension encodes a pairing token. If that token has no expiry and can be used multiple times, an attacker who photographs the QR code (shoulder surfing, screen recording) can pair their own device to the user's relay room at any point in the future.

**Prevention:**
- Generate a pairing token with a short TTL (60-120 seconds). The QR code should expire if not scanned within that window.
- Mark the token as consumed on first successful pairing. Reject second-use attempts.
- Show a countdown timer in the extension popup so the user knows the QR is expiring.

**Warning signs:**
- Pairing token is a static UUID derived from a stable device identifier
- No expiry field on the token
- The relay accepts pairing requests for a room that already has two clients connected

**Phase:** Chrome extension — pairing UI; relay server — pairing endpoint

---

### Pitfall 11: Content Script Cannot Detect TOTP Fields in Shadow DOM or iframes

**What goes wrong:** The content script scans the DOM for `<input type="text">` fields that look like TOTP inputs (pattern matching on `maxlength=6`, `autocomplete="one-time-code"`, etc.). Sites using Web Components with Shadow DOM, or sites that render the 2FA field in a cross-origin iframe, will not be detected.

**Prevention:**
- Use `autocomplete="one-time-code"` as the primary detection signal — this is the standard attribute and more reliable than `maxlength` heuristics.
- For Shadow DOM: `document.querySelectorAll('*')` does not pierce shadow roots. You need to walk shadow roots explicitly or use `TreeWalker` with shadow traversal.
- Cross-origin iframes cannot be accessed from a content script at all — this is a hard browser security constraint. For these sites, the user must manually paste the code from the popup.
- Document which sites will not be auto-fillable and surface a fallback copy-to-clipboard button in the popup.

**Warning signs:**
- Auto-fill tested only on simple HTML pages, not on React/Angular/Web Components sites
- No fallback copy button in the extension popup
- Content script uses only `document.querySelector('input[maxlength="6"]')`

**Phase:** Chrome extension — content script detection

---

### Pitfall 12: Chrome Extension Review Rejection for Overbroad Permissions

**What goes wrong:** Requesting `<all_urls>` or `*://*/*` host permissions when the extension only needs to inject a content script for autofill causes immediate reviewer scrutiny and often rejection. Approximately 45% of submissions with issues are rejected due to improperly scoped permissions.

**Prevention:**
- Use `activeTab` permission instead of `<all_urls>` if the autofill only triggers on the currently active tab at the user's explicit request.
- Use `"optional_host_permissions": ["<all_urls>"]` with `chrome.permissions.request()` at runtime if broader access is truly needed — optional permissions require explicit user consent and are viewed more favorably.
- In the "Notes for reviewers" field, explain that the WebSocket connection goes to a user-owned relay server. Provide a test account or setup instructions. Reviewers who cannot reproduce the core flow will reject.
- Do not obfuscate code. Minification (whitespace removal) is fine. Variable renaming that obscures intent is not.

**Warning signs:**
- `manifest.json` has `"host_permissions": ["<all_urls>"]` with no explanation of why
- Extension submitted without "Notes for reviewers" instructions
- Minification tool has obfuscation mode enabled

**Phase:** Chrome extension — manifest configuration and store submission

---

### Pitfall 13: `.p8` Key Committed to Source Control or Included in Extension Bundle

**What goes wrong:** The APNs `.p8` private key file is used on the relay server to sign JWTs. If it is committed to the Git repository or accidentally bundled into the Chrome extension ZIP during build, it is exposed.

**Prevention:**
- Add `*.p8` to `.gitignore` immediately when the relay server directory is created.
- Load the `.p8` contents from a Railway environment variable (`APNS_PRIVATE_KEY`), not from a file path on disk.
- Never store key material in the Chrome extension — the extension has no reason to hold APNs credentials.
- Audit the extension ZIP before submission to ensure it contains no `.p8`, `.env`, or credential files.

**Warning signs:**
- `.p8` file lives in the repo root alongside `package.json`
- Build script uses `cp .env dist/` or similar
- Railway service uses a file mount for the key instead of an environment variable

**Phase:** Relay server — initial setup (before first commit)

---

## Minor Pitfalls

Friction points that can be fixed without architectural changes.

---

### Pitfall 14: Using `ws://` Instead of `wss://` Causes Browser Rejection

The Chrome extension popup and service worker run in a secure context. Browsers block mixed-content WebSocket connections (`ws://`) from secure contexts. The relay must be served over `wss://`. Railway provides TLS termination automatically — the Node.js server binds to HTTP internally and Railway's Cloudflare proxy provides the TLS layer. Do not configure the Node.js server to handle TLS itself; that creates double-TLS which breaks the connection.

**Phase:** Relay server — initial Railway deployment

---

### Pitfall 15: APNs Sandbox vs. Production Endpoint Mismatch

Development builds (Xcode debug scheme) register with the APNs sandbox endpoint (`api.sandbox.push.apple.com`). Production builds (App Store / TestFlight) register with the production endpoint (`api.push.apple.com`). A relay server using only one endpoint will fail for the other environment. This is a common source of "push notifications work in dev, fail in production" bugs.

**Prevention:**
- The relay server must accept an `environment` field when a device registers its token (or derive it from the build type).
- Use separate APNs endpoint URLs per environment on the relay side.
- Test on a production-signed build (TestFlight) before considering push notifications complete.

**Phase:** Relay server — APNs integration; iOS app — token registration endpoint

---

### Pitfall 16: Service Worker Update Race Condition Corrupts storage

When the Chrome extension auto-updates, the old service worker is unregistered and a new one is registered. There is a documented race condition where the old service worker's async storage purge can run after the new service worker has already written fresh data, destroying it. This is a Chromium bug (tracked) but not fixed as of Chrome 116.

**Prevention:**
- Use `chrome.runtime.onInstalled` with `reason === "update"` to re-initialize all storage keys explicitly on update, overwriting whatever state exists.
- Keep stored values small and re-derivable (e.g., store the relay URL and pairing token, not derived state that can be recomputed).

**Phase:** Chrome extension — update handling

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Service worker architecture | State loss on wake (Pitfall 1) | Design stateless from day one; use `chrome.storage.session` |
| WebSocket client in SW | No keepalive → connection drops (Pitfall 2) | Implement 20-second ping before writing other WS logic |
| Relay server deployment to Railway | 15-minute timeout (Pitfall 3) | Write reconnection protocol spec before implementation |
| iOS relay client design | Background socket drops (Pitfall 4) | Decide on APNs-wakeup-then-connect flow before any iOS WS code |
| APNs integration on relay | Silent push throttling (Pitfall 5), JWT expiry (Pitfall 6) | Use alert pushes; implement token rotation from day one |
| iOS device token registration | Stale tokens (Pitfall 7) | Register token on every launch; handle 410 on relay |
| End-to-end flow timing | TOTP window expiry (Pitfall 8) | Measure each leg; generate code post-Face ID, not post-push |
| Pairing flow design | No token expiry (Pitfall 10) | TTL + single-use tokens before pairing UI is built |
| Content script detection | Shadow DOM / iframe gaps (Pitfall 11) | Add copy-to-clipboard fallback from the start |
| Chrome Web Store submission | Overbroad permissions → rejection (Pitfall 12) | Audit manifest permissions; write reviewer notes before submitting |
| Initial relay server commit | `.p8` key in source control (Pitfall 13) | Add `.p8` to `.gitignore` before creating any key files |

---

## Sources

- [Chrome Extensions: WebSockets in Service Workers (official)](https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets) — HIGH confidence
- [Chrome Extensions: Service Worker Lifecycle (official)](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle) — HIGH confidence
- [Railway Guides: SSE vs WebSockets — 15-minute timeout documentation](https://docs.railway.com/guides/sse-vs-websockets) — HIGH confidence
- [Apple: Establishing token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns) — HIGH confidence
- [Apple: URLSessionWebSocketTask](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) — HIGH confidence
- [Chrome 116: WebSocket improvements for extension service workers](https://developer.chrome.google.cn/blog/chrome-116-beta-whats-new-for-extensions) — HIGH confidence
- [APNs Auth Error Troubleshooting Guide (MagicBell)](https://www.magicbell.com/blog/auth-error-from-apns-or-web-push-service-troubleshoot-guide) — MEDIUM confidence
- [iOS Silent Push Limits (Medium)](https://medium.com/@shobhakartiwari/ios-silent-push-limits-7d0c65b642f4) — MEDIUM confidence
- [APNs in 2025: Certificate and Token Updates (Simform)](https://medium.com/simform-engineering/apns-in-2025-apples-major-certificate-shift-must-know-token-updates-df4587582b4c) — MEDIUM confidence
- [Chrome Web Store Pre-Submission Checklist 2026 (AppBooster)](https://appbooster.net/blog/chrome-extension-pre-submission-checklist/) — MEDIUM confidence
- [Chrome Web Store Review Process (official)](https://developer.chrome.com/docs/webstore/review-process) — HIGH confidence
- [Chromium bug: ServiceWorker shutdown every 5 minutes](https://issues.chromium.org/issues/40733525) — HIGH confidence
- [Silent Push Notifications: Opportunities, Not Guarantees (Medium)](https://mohsinkhan845.medium.com/silent-push-notifications-in-ios-opportunities-not-guarantees-2f18f645b5d5) — MEDIUM confidence
- [TOTP Common Mistakes (Authgear, 2026)](https://www.authgear.com/post/5-common-totp-mistakes) — MEDIUM confidence
