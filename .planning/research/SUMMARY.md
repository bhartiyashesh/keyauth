# Research Summary — KeyAuth Chrome Extension

## Executive Summary

KeyAuth Chrome Extension is a cross-device TOTP relay: the iOS app holds secrets, a cloud relay routes messages, and a Chrome extension auto-fills OTP fields. The differentiating claim is that TOTP seeds never leave the device — only generated 6-digit codes travel the relay for 30 seconds.

## Recommended Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Extension framework | WXT 0.20.x | Active, Vite-based, MV3-native. Plasmo in maintenance mode, CRXJS had 3-year gap |
| Extension UI | Vanilla TypeScript | React adds 130KB to a two-button popup |
| Relay server | Node.js 22 LTS + ws 8.20.x | Raw RFC 6455 WebSocket — compatible with both iOS URLSessionWebSocketTask and browser WebSocket API |
| APNs client | apns2 12.2.x | HTTP/2 + JWT (p8) auth. node-apn unmaintained since 2021 |
| Relay hosting | Railway | TLS termination automatic, no cert management |
| iOS WebSocket | URLSessionWebSocketTask | Native Apple API, zero dependencies |

## Table Stakes Features (v1)

1. QR code pairing (one-time setup)
2. WebSocket relay with TLS + 20-second keepalive ping
3. APNs alert push to wake backgrounded iOS app
4. Face ID gate before every code transmission
5. TOTP field detection (autocomplete + heuristic fallbacks)
6. Auto-fill into detected field
7. Clipboard copy with 30-second auto-clear (fallback)
8. Pairing status indicator in popup
9. TOTP expiry countdown display
10. Domain-matched account surfacing

## Critical Pitfalls

| Pitfall | Impact | Prevention |
|---------|--------|------------|
| MV3 service worker state loss on wake | WebSocket dies, requests hang | Stateless design; rebuild from chrome.storage.session on every wake |
| Railway 15-minute WebSocket timeout | Silent disconnection in production | Proactive reconnection at ~14 minutes in both clients |
| APNs silent push throttling (~3/hour) | App never wakes for code request | Use alert pushes only (apns-push-type: alert, priority: 10) |
| APNs JWT expires after 60 minutes | Push delivery silently fails | Rotate token at 45-minute mark |
| iOS WebSocket drops on background | Persistent connection impossible | Design as: APNs alert → user taps → app opens → connects → delivers |

## Architecture

Three runtimes, no shared process space, communicate exclusively through the relay over TLS:
- **Relay server** — In-memory `Map<roomId, Set<WebSocket>>`, max 2 clients/room, APNs sender, no database
- **Chrome extension** — Service worker (WebSocket owner), popup (UI), content script (field detection + fill)
- **iOS additions** — RelayClient, PushNotificationHandler, PairingCoordinator, TOTPApprovalSheet (all additive, keyboard extension untouched)

## Recommended Phase Order

1. **Relay Server** — Deploy first; everything else blocked on it
2. **iOS Pairing + Relay Client** — Additive iOS modules against live relay
3. **Chrome Extension Core** — Popup, service worker, basic request→code flow
4. **Auto-Fill Content Script** — Field detection, code injection, clipboard fallback
5. **Resilience + Edge Cases** — Reconnection, countdown, stale token handling
6. **Polish + Store Submission** — Permission audit, production APNs test, submission

## Deferred to v2+

- E2E encryption layer on top of TLS
- Firefox/Safari extension support
- Self-hosted relay option
- Multi-account search in popup
- Countdown-aware delivery (wait for next period if <5s remaining)

## Anti-Features (Never Build)

- TOTP seed storage in browser extension
- Auto-fill on page load (security risk)
- Bluetooth/local transport (Chrome API limitation)
- Account sync across browsers

---
*Synthesized: 2026-04-15 from STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*
