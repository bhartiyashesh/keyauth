# Technology Stack

**Project:** KeyAuth Chrome Extension + Relay Server
**Researched:** 2026-04-14
**Overall confidence:** HIGH (Chrome MV3, ws, Railway) / MEDIUM (apns2 maintenance trajectory)

---

## Context

The iOS app is already built: Swift 5.9, zero third-party dependencies, URLSessionWebSocketTask for WebSocket, UserNotifications for push. This file covers only the **three new components**: Chrome extension, WebSocket relay server, and APNs push integration.

---

## 1. Chrome Extension (Manifest V3)

### Build Framework

**Use WXT v0.20.x** — not raw Vite + CRXJS, not Plasmo.

| Choice | Version | Why |
|--------|---------|-----|
| WXT | 0.20.22 | File-based entrypoints, vanilla TypeScript support, Vite under the hood, active maintainers as of 2026, framework-agnostic |
| TypeScript | 5.x (via WXT) | WXT ships TypeScript by default; all extension scripts typed without extra setup |
| Vite | 6.x (via WXT) | WXT uses Vite internally; faster builds than webpack, smaller output |

**Why not CRXJS:** Was unmaintained for years. New maintainers took over mid-2025 and shipped 2.0, but its long-term commitment remains uncertain. WXT is healthier.

**Why not Plasmo:** In maintenance mode. React-first. Outdated dependencies flagged in 2025 ecosystem reviews.

**Why not raw Vite + manifest by hand:** WXT auto-generates the `manifest.json` from file-based entrypoints, handles `web_accessible_resources`, and eliminates all the boilerplate pain of MV3 multi-entry builds.

### UI (Popup)

**Use vanilla TypeScript — no React, no Preact.**

The popup for this extension is minimal: list accounts, show a "Request" button, display the received TOTP code. React adds ~130 KB gzipped to a popup that must render in under 50ms. Vanilla TypeScript + DOM APIs is sufficient and keeps the total extension bundle under the Chrome 4 MB limit comfortably.

### WebSocket in the Service Worker

**Critical constraint (Chrome 116+):** MV3 service workers terminate after 30 seconds of inactivity. Since Chrome 116, a WebSocket connection itself extends the service worker lifetime — but only while messages are actively exchanged.

**Approach: ping every 20 seconds via `setInterval`.**

The Chrome extension team explicitly recommends a 20-second keepalive interval (documented at `developer.chrome.com/docs/extensions/how-to/web-platform/websockets`). The service worker sends a lightweight `{"type":"ping"}` message to the relay; the relay responds with `{"type":"pong"}`. This keeps the worker alive without the complexity of the Offscreen Document API.

**Do NOT use the Offscreen Document API for WebSocket keepalive** — it adds an entire hidden HTML document to the extension lifecycle for a problem solved more cleanly by a ping interval. Reserve the Offscreen API for actual audio/clipboard DOM needs.

**Minimum Chrome version in manifest:** Set `"minimum_chrome_version": "116"` to guarantee WebSocket-extends-lifetime behavior.

### Content Script

Plain TypeScript, no framework. The content script detects TOTP input fields by heuristic (label text, `autocomplete="one-time-code"`, `inputmode="numeric"` + short `maxlength`) and auto-fills when the service worker delivers a code via `chrome.runtime.sendMessage`. Runs at `document_idle`.

### Extension Summary Stack

```
WXT          0.20.x   Build framework (Vite-based, file-based entrypoints)
TypeScript   5.x      Language (via WXT)
Vite         6.x      Bundler (via WXT)
chrome.*     MV3      Extension APIs
```

**No npm UI library.** No Socket.io (the extension uses the native `WebSocket` browser API directly — no library needed on the client side).

---

## 2. WebSocket Relay Server (Railway)

### Runtime

**Node.js 22 LTS** — Railway supports specifying major version only. Node.js 22 LTS (active until April 2027) is the correct choice: it ships with native `fetch`, improved ESM support, and the best V8 performance for long-lived WebSocket connections.

**Do not use Node.js 18** — it reaches EOL in April 2025. Node.js 24 (current, unstable) is not LTS yet.

### Language

**TypeScript compiled to JS at build time** — do not run `ts-node` in production. Use `tsc` to emit to `/dist`, then `node dist/index.js` in the Railway start command. Railway's Nixpacks builder handles this automatically if `scripts.build` and `scripts.start` are set correctly in `package.json`.

Alternatively, for a tiny relay server, **`tsx` as a production runner** is acceptable (it JIT-strips types, no separate build step). Railway template for Node.js TypeScript WebSockets uses this pattern. Decision: use `tsx` for simplicity given this is a dumb relay, not a heavy service.

### WebSocket Library

**Use `ws` 8.20.x** — the only serious choice for a Node.js WebSocket server.

| Library | Version | Why |
|---------|---------|-----|
| ws | 8.20.0 | RFC 6455 compliant, zero runtime dependencies, 49M weekly downloads, passes Autobahn test suite, actively maintained |
| @types/ws | 8.18.x | TypeScript definitions, matches ws 8.x |

**Why not Socket.io:** Adds protocol overhead, requires matching Socket.io client on the other end. The iOS app uses `URLSessionWebSocketTask` (native WebSocket) and the Chrome extension uses the browser `WebSocket` API — both are raw WebSocket. Socket.io is incompatible with these clients without its own client library.

**Why not uWebSockets.js:** Native binding, harder to deploy in Railway's Nixpacks environment, no meaningful performance advantage at this traffic volume (two clients per room).

### Room / Pairing System

Implement in plain TypeScript on top of `ws`. The relay is intentionally a "dumb pipe":

- Each connection registers with a `roomId` (derived from the QR pairing code)
- Messages are forwarded to the other peer in the room
- No persistence — rooms live only in memory (`Map<string, Set<WebSocket>>`)
- No database needed

This stateless design means Railway's single-instance deployment is sufficient. If horizontal scaling were needed, Redis pub/sub would be required — but for v1 with one active user, skip it.

### HTTP Framework

**Use `http` (built-in Node.js) + `ws`** — no Express needed.

The relay has exactly two HTTP concerns: a `/health` endpoint for Railway's healthcheck, and the WebSocket upgrade path. Express adds 50 KB for routing that a 5-line `http.createServer` handles. Use the built-in `http` module.

```
Node.js      22 LTS   Runtime
TypeScript   5.x      Language
tsx          4.x      Production runner (JIT type stripping)
ws           8.20.0   WebSocket server
@types/ws    8.18.x   TypeScript types
```

### Railway Configuration

- **PORT:** Always use `process.env.PORT` — Railway injects this automatically. Never hardcode 3000 or 8080.
- **TLS:** Railway's proxy terminates TLS. The server runs plain `ws://` internally; clients connect via `wss://` to the Railway domain. Do not manage certificates in the app.
- **Healthcheck:** Add `GET /health → 200 OK` for Railway's healthcheck. Without it, Railway cannot determine if the deploy succeeded.
- **Dockerfile vs Nixpacks:** Nixpacks works for this project (it auto-detects Node.js + TypeScript). Only switch to Dockerfile if you need OS-level packages (not needed here).

---

## 3. APNs Push Integration (Node.js → iOS)

### Library

**Use `apns2` 12.2.x** — the cleanest, most current HTTP/2 APNs client for Node.js.

| Library | Version | Why |
|---------|---------|-----|
| apns2 | 12.2.0 | TypeScript-native, HTTP/2 persistent connection, JWT/p8 auth only, actively maintained (last release May 2025), requires Node.js 16+ |

**Why not `node-apn`:** Last meaningful release in 2021. Uses TLS socket connections rather than HTTP/2. The repository is effectively unmaintained.

**Why not `node-apn-http2`:** A fork of `node-apn` that adds HTTP/2, but has low adoption and sparse maintenance. `apns2` covers the same ground with a cleaner API.

**Why not raw `http2` module calls to APNs:** Technically possible (APNs is HTTP/2), but you'd reimplement JWT signing, connection management, and error handling that `apns2` already provides correctly.

### Authentication: p8 Token-Based (JWT) — Not p12 Certificate

**Use p8 exclusively.** This is unambiguous in 2025:

- p8 keys do not expire (p12 certificates expire yearly and require annual rotation)
- One p8 key covers all apps under your Apple Developer team
- Apple's own documentation recommends token-based auth for all new APNs integrations
- `apns2` only supports p8 — no p12 support, which enforces the right choice

**What you need from Apple Developer portal:**
1. An APNs Auth Key (`.p8` file) — generate once, store securely
2. Key ID (10-character string shown in the portal)
3. Team ID (10-character string from your Apple Developer account)
4. Bundle ID for the push notification topic (`com.keyauth.app`)

### Push Payload for TOTP Request

The iOS app needs to receive a **background push** (silent push) to wake up and prompt Face ID:

```json
{
  "aps": {
    "content-available": 1
  },
  "type": "totp_request",
  "room": "<roomId>",
  "account": "<accountName>"
}
```

Use `apns2`'s `SilentNotification` class. The relay server sends this when the Chrome extension sends a `{"type":"request","account":"..."}` message. iOS handles it in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.

**APNs environment:** Use `production` environment. The `sandbox` environment is for Xcode debug builds. Since the iOS app will be distributed outside of debug builds (TestFlight or App Store), production APNs is required.

### APNs Summary Stack

```
apns2        12.2.0   APNs HTTP/2 client
```

No additional libraries. The `.p8` key file is loaded from an environment variable (base64-encoded) on Railway — never committed to the repository.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Extension framework | WXT 0.20.x | CRXJS 2.x | Maintenance uncertainty after 3-year hiatus; WXT more stable |
| Extension framework | WXT 0.20.x | Plasmo | Maintenance mode, React-first, outdated deps |
| Extension framework | WXT 0.20.x | Raw Vite + manifest | Too much boilerplate for MV3 multi-entry builds |
| Popup UI | Vanilla TS | React 19 | 130 KB overhead for a 2-button popup; overkill |
| WS keepalive | 20s ping | Offscreen Document | Offscreen API adds hidden HTML document; ping is simpler |
| WebSocket server | ws 8.x | Socket.io | Protocol-incompatible with native iOS/Chrome WS clients |
| WebSocket server | ws 8.x | uWebSockets.js | Native bindings complicate Railway Nixpacks builds |
| HTTP server | Node built-in `http` | Express | No routing complexity; Express overhead not justified |
| APNs client | apns2 12.x | node-apn | Unmaintained since 2021; legacy TLS socket protocol |
| APNs auth | p8 JWT tokens | p12 certificates | p12 expires yearly; p8 is Apple's recommended path |
| Node runtime | 22 LTS | 18 LTS | Node 18 reached EOL April 2025 |
| Node runtime | 22 LTS | 24 Current | Not LTS; unstable for production |

---

## Installation

### Chrome Extension (`/extension`)

```bash
npm create wxt@latest
# Choose: TypeScript, no framework (vanilla)

npm install
# WXT pulls in Vite, TypeScript, all extension tooling

# Dev mode (auto-reloads extension in Chrome)
npm run dev

# Production build
npm run build
# Output: .output/chrome-mv3/
```

### Relay Server (`/relay`)

```bash
npm init -y
npm install ws
npm install tsx --save-dev
npm install -D typescript @types/ws @types/node

# APNs
npm install apns2
```

`package.json` scripts:
```json
{
  "scripts": {
    "start": "tsx src/index.ts",
    "build": "tsc",
    "start:prod": "node dist/index.js"
  }
}
```

`.nvmrc` or `package.json#engines`:
```json
{
  "engines": { "node": ">=22" }
}
```

---

## Environment Variables (Railway)

| Variable | Description | Where |
|----------|-------------|-------|
| `PORT` | Auto-injected by Railway | Read via `process.env.PORT` |
| `APNS_KEY` | Base64-encoded `.p8` file content | Set in Railway dashboard |
| `APNS_KEY_ID` | 10-char key ID from Apple portal | Set in Railway dashboard |
| `APNS_TEAM_ID` | 10-char team ID from Apple account | Set in Railway dashboard |
| `APNS_TOPIC` | Bundle ID: `com.keyauth.app` | Set in Railway dashboard or hardcode |

Never commit `.p8` files to the repository.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| WXT as extension framework | HIGH | Verified: v0.20.22 current, active maintenance confirmed April 2026 |
| MV3 WebSocket + 20s ping | HIGH | Verified against official Chrome developer docs (chrome.dev); Chrome 116 behavior confirmed |
| ws 8.20.0 | HIGH | Verified: latest release March 2026, 49M weekly downloads, passes Autobahn suite |
| Railway PORT/TLS behavior | HIGH | Multiple sources + Railway's own docs confirm proxy TLS termination and PORT injection |
| apns2 12.2.0 | MEDIUM | Verified: last release May 2025, actively maintained. Risk: single maintainer (AndrewBarba). Monitor for Node.js compatibility as 22 LTS matures |
| p8 over p12 | HIGH | Apple's explicit recommendation; p12 broadly discouraged in 2025 |
| Node.js 22 LTS | HIGH | Confirmed LTS until April 2027; Railway supports it |

---

## Sources

- Chrome WebSockets in MV3: https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets
- Chrome service worker lifecycle: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
- WXT framework: https://wxt.dev/ and https://github.com/wxt-dev/wxt
- 2025 extension framework comparison: https://redreamality.com/blog/the-2025-state-of-browser-extension-frameworks-a-comparative-analysis-of-plasmo-wxt-and-crxjs/
- ws library: https://github.com/websockets/ws and https://www.npmjs.com/package/ws
- apns2 library: https://github.com/AndrewBarba/apns2 and https://www.npmjs.com/package/apns2
- APNs token-based auth: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
- Railway Node.js WebSocket template: https://railway.com/deploy/DZV--w
- Railway docs: https://docs.railway.com/builds/dockerfiles and https://docs.railway.com/guides/express
- Node.js LTS schedule: https://endoflife.date/nodejs
