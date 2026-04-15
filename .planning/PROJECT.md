# KeyAuth Chrome Extension

## What This Is

A Chrome extension that lets users fill TOTP 2FA codes on desktop by requesting them from the KeyAuth iOS app on their phone. The extension connects to the phone via a WebSocket relay server, so users never have to switch devices, copy codes, or race against expiring tokens. This extends the existing KeyAuth iOS app (companion app + keyboard extension) to the desktop browser.

## Core Value

One-click TOTP code delivery from phone to browser — secrets never leave the phone, codes arrive in the browser within seconds.

## Requirements

### Validated

- ✓ TOTP generation (RFC 6238, SHA-1/256/512) — existing iOS app
- ✓ Account management (add/edit/delete, QR scan, manual entry) — existing iOS app
- ✓ Biometric authentication (Face ID/Touch ID) — existing iOS app
- ✓ Keyboard extension with tap-to-insert — existing iOS app
- ✓ Shared data via App Groups + Keychain — existing iOS app

### Active

- [ ] Chrome extension with Manifest V3
- [ ] QR code pairing between extension and phone (one-time setup)
- [ ] Click-to-request flow (pick account in extension → phone Face ID → code arrives)
- [ ] Auto-fill detected TOTP input fields in browser
- [ ] WebSocket relay server on Railway (TLS encrypted)
- [ ] Push notification to phone when code is requested (APNs)
- [ ] Relay server room/channel system for pairing
- [ ] iOS app: relay client + push notification handling
- [ ] iOS app: pairing screen (QR scanner for extension pairing)

### Out of Scope

- E2E encryption layer on top of TLS — deferred, TLS is sufficient for v1 since user owns the relay
- Bluetooth/local communication — Chrome extensions can't use Web Bluetooth API
- Firefox/Safari extension — Chrome only for v1
- Self-hosted relay option — Railway-hosted only for v1
- Syncing secrets to the browser — secrets stay on the phone, only generated codes are transmitted

## Context

**Existing codebase:** KeyAuth is a working iOS app with two targets — a SwiftUI companion app and a UIKit keyboard extension. Zero external dependencies; uses only Apple frameworks. Accounts are stored in the iOS Keychain and bridged to the keyboard extension via App Group UserDefaults (SharedDefaults).

**New components needed:**
1. **Chrome Extension** (Manifest V3) — popup UI, content script for TOTP field detection, WebSocket client
2. **WebSocket Relay Server** (Node.js on Railway) — room-based message routing, APNs push integration
3. **iOS App Changes** — WebSocket client, push notification handling, QR-based pairing flow, relay connection management

**The relay is a dumb pipe:** It routes encrypted-in-transit WebSocket messages between paired devices. It does NOT store codes, secrets, or account data. Codes expire in 30 seconds anyway.

**Push notifications:** Required to wake the iOS app when a code is requested. Uses APNs (Apple Push Notification Service). The relay server sends the push, the iOS app receives it and prompts Face ID.

## Constraints

- **No external iOS dependencies**: The iOS app has zero third-party packages — keep it that way. Use URLSessionWebSocketTask for WebSocket, UserNotifications framework for push.
- **Chrome Manifest V3**: Service workers (not background pages), limited APIs, no persistent background connections — WebSocket must reconnect on demand.
- **Relay hosting**: Railway only (per user preference). Never use Vercel.
- **TOTP code lifetime**: Codes expire in 30 seconds. The full request→approve→deliver flow must complete well within this window.
- **Keyboard extension unchanged**: The existing keyboard extension stays as-is. The Chrome extension is additive.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| TLS-only relay (no E2E) | Simplicity — user owns the relay, codes expire in 30s, E2E can be added later | — Pending |
| WebSocket relay, not Bluetooth | Chrome extensions can't use Web Bluetooth API; relay works across networks | — Pending |
| Click-to-request, not auto-detect-push | User initiates the flow from the extension; auto-detect + auto-fill after code arrives | — Pending |
| Railway for relay hosting | User's preferred deployment platform; Vercel explicitly excluded | — Pending |
| APNs for phone wakeup | Relay server must push to phone; APNs is the standard iOS mechanism | — Pending |

---
*Last updated: 2026-04-14 after initialization*
