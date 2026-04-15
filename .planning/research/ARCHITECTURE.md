# Architecture Patterns

**Project:** KeyAuth Chrome Extension + WebSocket Relay
**Domain:** Cross-device TOTP delivery (iOS authenticator → Chrome browser)
**Researched:** 2026-04-14

---

## System Overview

The system has three runtime environments that never share process space. They communicate exclusively over the network through the relay. The iOS app is the single source of truth for secrets and code generation; the Chrome extension and relay are code-delivery infrastructure only.

```
[Chrome Extension]  <---WebSocket (TLS)--->  [Railway Relay Server]  <---WebSocket (TLS)--->  [iOS App]
  - Popup UI                                    - Room router                                   - URLSessionWebSocketTask
  - Content Script                              - APNs push sender                              - UNUserNotificationCenter
  - Service Worker                              - No secret storage                             - Face ID gate
```

---

## Component Definitions

### Component 1: Chrome Extension (Manifest V3)

Three distinct JS execution contexts within the extension, each with different lifetimes and API access:

| Context | Lifetime | Owns |
|---------|----------|------|
| Service Worker (background.js) | Ephemeral — lives as long as there is active WebSocket traffic (keepalive ping every 20s resets the 30s idle timer); wakes on alarms and messages | WebSocket connection to relay, room state in chrome.storage, message dispatch to popup and content scripts |
| Popup (popup.js) | Open only while user has the popup open | Account list UI, code request initiation, pairing QR display |
| Content Script (content.js) | Per-page, injected at page load | TOTP input field detection, code insertion into focused field |

**Service worker WebSocket strategy (Chrome 116+, HIGH confidence):**
Active WebSocket connections in an MV3 service worker reset the 30-second idle timer. The keepalive pattern — sending a ping frame every 20 seconds — is the officially documented approach. This replaces the MV2 persistent background page. `"minimum_chrome_version": "116"` must be declared in the manifest.

**Alternative for extremely long idle periods:** An offscreen document (chrome.offscreen API) can host a WebSocket with no lifetime limit. However, for this use case the popup is user-initiated and the connection only needs to live for one request-response cycle (< 30 seconds). The service worker + 20s ping approach is simpler and sufficient.

**Pairing flow in the extension:** The popup generates a random `roomId` (UUID v4) on first launch, stores it in `chrome.storage.local`, and displays it as a QR code. The iOS app scans this QR code to learn the `roomId`, then both sides connect to `wss://relay.railway.app/ws?room=<roomId>`. After pairing, the `roomId` is the permanent shared identifier for this browser-phone pair.

**Auto-fill detection in content script:** The content script queries the active page for input elements whose `autocomplete` attribute contains `one-time-code`, or whose `type` is `text`/`tel` and whose `name`/`id`/`aria-label` matches patterns like `otp`, `totp`, `2fa`, `code`, `token`. When a matching field is found and focused, the content script notifies the service worker, which optionally pre-fetches or pre-prompts. When a code arrives from the relay, the content script dispatches an `InputEvent` with the code into the focused field.

---

### Component 2: WebSocket Relay Server (Node.js on Railway)

The relay is intentionally stateless beyond in-memory room membership. It has no database. It routes messages between two WebSocket clients that share a `roomId`.

**Core responsibilities:**
- Accept WebSocket upgrades at `wss://<host>/ws?room=<roomId>`
- Maintain an in-memory `Map<roomId, Set<WebSocket>>` of active connections
- Enforce a maximum of 2 clients per room (browser + phone); reject a third connection
- Forward any message received from one client to the other client in the same room
- Send an APNs push when the browser side connects to a room where the iOS side is absent

**APNs integration:** The relay holds APNs credentials (`.p8` key file path, Key ID, Team ID, bundle ID) as environment variables on Railway. When a code-request message arrives and the iOS client is not currently connected, the relay issues an APNs alert push (not background/silent — see APNs section below) using the `apn` npm package. The device push token is registered by the iOS app at pairing time: the iOS app sends a `register` message containing its device token, and the relay stores it in its room map for the duration of the process lifetime (or until the room reconnects).

**Relay is not a message queue:** If the iOS side is connected and available, the relay forwards the request directly over the existing WebSocket. If the iOS side is offline (not connected), the relay sends the APNs push and holds the room open waiting for the iOS client to reconnect. No message is persisted; if the relay restarts, the room state is lost and both sides reconnect using their stored `roomId`.

---

### Component 3: iOS App Changes (additive, no existing code modified)

New modules added to the existing `KeyAuth` app target. The keyboard extension and all existing shared code remain untouched.

| New Module | Responsibility |
|------------|---------------|
| `RelayClient` | Wraps `URLSessionWebSocketTask`; connects to relay with `roomId`; sends/receives messages; reconnects on close |
| `PushNotificationHandler` | Registers with APNs via `UNUserNotificationCenter`; sends device token to relay at pairing; handles incoming alert pushes |
| `PairingCoordinator` | Manages pairing state machine; generates or stores `roomId`; displays QR scanner for extension QR code |
| `TOTPApprovalSheet` | Bottom sheet shown when a code request arrives; triggers `BiometricAuthManager`; calls `TOTPGenerator` and sends code back via `RelayClient` |

**APNs strategy — alert push, not silent/background (HIGH confidence):**
Silent (`background`) pushes are throttled by iOS, not guaranteed, and can be delayed by hours. For a time-sensitive TOTP request (30-second code window), silent pushes are unsuitable. The correct approach is an alert push (`apns-push-type: alert`, `apns-priority: 10`) that wakes the user's screen. The push payload says "KeyAuth: tap to approve 2FA on [site]". The user taps the notification → app foregrounds → `TOTPApprovalSheet` appears → biometric → code sent.

**When the app is already in the foreground:** `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` is called. The app suppresses the banner and instead presents `TOTPApprovalSheet` directly.

**`URLSessionWebSocketTask` reconnect pattern:** The iOS app connects to the relay when:
1. It opens after receiving the APNs push (app delegate / scene delegate connects on foreground)
2. The pairing screen is active
3. The app is in the foreground (optional: maintain a live connection to avoid the APNs round-trip)

The connection is torn down when the app backgrounds (`sceneDidEnterBackground`). This is the standard iOS pattern — background WebSocket connections are killed by the OS anyway.

---

## Data Flow: Full Request Cycle

### Setup (one-time pairing)

```
Chrome Extension                    Relay                        iOS App
     |                                |                               |
     | generates roomId (UUID v4)     |                               |
     | stores in chrome.storage.local |                               |
     | displays QR: {roomId, relayURL}|                               |
     |                                |                               |
     |                                |       <-- user scans QR ----  |
     |                                |                               | stores roomId
     |                                |       -- register message --> |
     |                                | <-- {type:"register",         |
     |                                |      deviceToken:"abc...",    |
     |                                |      roomId:"uuid"} ----------|
     | <-- connects WS to relay ----> |                               |
     |                                | room map: {uuid -> [browser]} |
```

### Code Request (steady-state, iOS app backgrounded)

```
Chrome Extension                    Relay                        iOS App
     |                                |                               |
     | user clicks "Get Code"         |                               |
     | popup opens                    |                               |
     | SW connects WS to relay        |                               |
     | -- {type:"request",            |                               |
     |     roomId, site, accountId}-->|                               |
     |                                | iOS not connected:            |
     |                                | send APNs alert push -------> |
     |                                |                               | user sees banner
     |                                |                               | taps → app foregrounds
     |                                |                               | connects WS to relay
     |                                | <-- {type:"register",token}---|
     |                                | forwards pending request ----> (or re-requests)
     |                                |                               | TOTPApprovalSheet shown
     |                                |                               | Face ID auth
     |                                |                               | TOTPGenerator.generate()
     |                                | <-- {type:"code",             |
     |                                |     code:"482910",            |
     |                                |     accountId,expireAt} ------|
     | <-- forwards code -------------|                               |
     | content script inserts code    |                               |
     | into focused OTP field         |                               |
     | SW closes WS connection        |                               |
```

### Code Request (iOS app in foreground, already connected)

The relay forwards the request directly — no APNs round-trip. The iOS app shows `TOTPApprovalSheet` immediately. Total latency: ~100-300ms relay transit + Face ID (~500ms) + code generation (<1ms).

---

## Message Protocol

All messages are JSON objects sent as WebSocket text frames. There is no binary framing.

### client → relay messages

```json
// Browser: initiate code request
{
  "type": "request",
  "roomId": "uuid-v4",
  "site": "github.com",
  "accountId": "uuid-of-account",
  "accountLabel": "GitHub",
  "requestId": "uuid-v4"
}

// iOS: register device token (sent at connect time)
{
  "type": "register",
  "roomId": "uuid-v4",
  "deviceToken": "hex-apns-token",
  "platform": "ios"
}

// Either side: keepalive ping (browser SW sends every 20s)
{
  "type": "ping"
}
```

### relay → client messages

```json
// Relay → iOS: forwarded code request
{
  "type": "request",
  "site": "github.com",
  "accountId": "uuid-of-account",
  "accountLabel": "GitHub",
  "requestId": "uuid-v4"
}

// Relay → browser: forwarded code response
{
  "type": "code",
  "code": "482910",
  "accountId": "uuid-of-account",
  "requestId": "uuid-v4",
  "expiresAt": 1713100800
}

// Relay → either: error conditions
{
  "type": "error",
  "code": "ROOM_FULL" | "NOT_PAIRED" | "REQUEST_TIMEOUT",
  "message": "human-readable string",
  "requestId": "uuid-v4"
}

// Relay → browser: acknowledge registration or connect
{
  "type": "pong"
}
```

### APNs payload (relay → APNs → iOS)

```json
{
  "aps": {
    "alert": {
      "title": "KeyAuth",
      "body": "Approve 2FA for GitHub?"
    },
    "sound": "default"
  },
  "requestId": "uuid-v4",
  "roomId": "uuid-v4",
  "site": "github.com",
  "accountLabel": "GitHub"
}
```

`apns-push-type: alert`, `apns-priority: 10`. The custom payload fields (`requestId`, `roomId`, etc.) allow the app to immediately open the correct approval sheet without a relay round-trip to discover what was requested.

---

## Suggested Build Order

Dependencies run bottom-up. Each phase can be tested in isolation before the next is started.

### Phase 1: Relay Server (foundation for everything else)

Nothing else works without the relay. Build and deploy first.

- Node.js WebSocket server (`ws` package) with room map
- `POST /register-token` endpoint for push token storage during development (before iOS client exists, use a test script)
- APNs integration (`apn` package) — can be exercised with `curl` before iOS or extension exists
- Deploy to Railway with TLS (Railway provides TLS termination automatically)
- Health check endpoint `GET /health`
- Test with two browser tabs (no iOS required at this stage)

### Phase 2: iOS Relay Client + Pairing

- `RelayClient` using `URLSessionWebSocketTask`
- APNs registration (`UNUserNotificationCenter.requestAuthorization`, `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`)
- `PairingCoordinator` — QR scanner (reuse existing `QRScannerView` pattern) that reads a `{roomId, relayURL}` payload
- `register` message sent to relay with device token at connection
- Placeholder `TOTPApprovalSheet` that just prints the request (no biometric yet)

Test: relay + iOS pairing works. Can receive forwarded requests from a test script.

### Phase 3: Chrome Extension Core

- Manifest V3 scaffold (manifest.json, service worker, popup, content script)
- Popup: pairing QR generation (display `roomId` as QR using a JS QR library)
- Service worker: WebSocket connection to relay with 20s keepalive ping
- Popup: account list (hardcoded initially) with "Get Code" button
- Service worker: send `request` message, await `code` response, deliver to popup
- Popup: display received code

Test: full flow with hardcoded account IDs. iOS receives request, popup receives code (manual approval on iOS side at this stage).

### Phase 4: Face ID Approval + Full iOS Handler

- `TOTPApprovalSheet` with `BiometricAuthManager.authenticate()`
- `TOTPGenerator.generate()` on approved account
- Send `code` message back to relay
- Handle approval rejection (deny message)

Test: end-to-end flow is complete. User sees code in Chrome popup.

### Phase 5: Auto-Fill + Content Script

- Content script field detection heuristics
- Message passing: content script → service worker → content script (code delivery)
- `InputEvent` dispatch into the detected OTP field

Test: end-to-end with auto-fill. Code arrives in the browser's login form.

### Phase 6: APNs Push Wakeup

- Relay sends APNs push when iOS client is absent from the room
- iOS app handles push in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and in `UNUserNotificationCenterDelegate`
- App foregrounds → connects WebSocket → shows approval sheet

Test: full flow when iOS app is backgrounded.

---

## Component Boundary Rules

| Boundary | What Crosses It | What Does Not Cross It |
|----------|----------------|------------------------|
| Chrome Extension ↔ Relay | `request` message (site, accountId, accountLabel, requestId) | TOTP secrets, full account list, private keys |
| Relay ↔ iOS App | `request` message (forwarded), `code` message (forwarded), APNs push payload | TOTP secrets, raw Base32 seeds |
| Relay internal | roomId → WebSocket map (ephemeral), roomId → deviceToken map (ephemeral) | Nothing persisted to disk |
| iOS App: relay client ↔ existing code | `accountId` lookup in `AccountStore`, TOTP code string | WebSocket connection objects, relay room state |
| iOS App: relay client ↔ keyboard extension | None — keyboard extension unchanged | Relay state should never touch the keyboard extension |

---

## Scalability Note

For v1 (one user, one phone, one browser), the relay is a single Railway instance. The in-memory room map is fine. If this were ever multi-user, the room map would move to Redis. That migration is additive and does not affect the client-side protocol.

---

## Key Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Alert push, not silent push | Silent pushes are throttled and unreliable for time-sensitive TOTP flows (30s window). Alert pushes are guaranteed delivery at high priority. |
| Service worker + 20s ping (not offscreen doc) | The connection only lives for one request cycle, which is well under 30 seconds. Offscreen documents add complexity that is not needed here. |
| roomId as permanent pairing identifier | Simple. No re-pairing needed after app restart. Stored in `chrome.storage.local` (extension) and `UserDefaults` or Keychain (iOS). |
| Relay sends APNs (not iOS-to-iOS) | The relay is the only component that knows both sides are connected. It is the natural trigger for APNs. |
| JSON text frames (not binary/msgpack) | Simpler to debug. Message size is negligible for this use case (< 500 bytes per message). |
| accountId in request, not accountLabel | accountId is the canonical identifier. Label is included only for the APNs push body display. iOS looks up the account by ID in its local store. |

---

## Sources

- [Use WebSockets in service workers | Chrome for Developers](https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets) — HIGH confidence
- [chrome.offscreen API | Chrome for Developers](https://developer.chrome.com/docs/extensions/reference/api/offscreen) — HIGH confidence
- [Firefox Sync Pairing Flow Architecture | Mozilla](https://mozilla.github.io/ecosystem-platform/explanation/pairing-flow-architecture) — HIGH confidence (pairing pattern reference)
- [APNs alert vs background push type](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) — HIGH confidence
- [node-apn library | GitHub](https://github.com/node-apn/node-apn) — MEDIUM confidence (community library, actively maintained)
- [WebSocket room/channel management | OneUptime](https://oneuptime.com/blog/post/2026-01-24-websocket-room-channel-management/view) — MEDIUM confidence
- [Extension service worker lifecycle | Chrome for Developers](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle) — HIGH confidence
