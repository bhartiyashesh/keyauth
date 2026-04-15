# Roadmap: KeyAuth Chrome Extension

## Overview

Build the Chrome extension and relay server that bridge the existing KeyAuth iOS app to the desktop browser. The relay is built first because every other component depends on it. iOS pairing and relay client come next as additive modules to the existing app. The Chrome extension then completes the full request-to-fill flow. Auto-fill field detection is layered on after the happy path works. Resilience hardening closes out the build before submission.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Relay Server** - Deploy the WebSocket relay to Railway; everything else blocks on this
- [ ] **Phase 2: iOS Relay Client + Pairing** - Add additive relay and push notification modules to the existing iOS app
- [ ] **Phase 3: Chrome Extension Core** - Build the popup, service worker, and full request-to-code flow end-to-end
- [ ] **Phase 4: Auto-Fill + Domain Matching** - Detect TOTP fields in the browser and inject received codes automatically
- [ ] **Phase 5: Resilience** - Harden reconnection, session rebuild, and stale token handling across all three runtimes

## Phase Details

### Phase 1: Relay Server
**Goal**: A live Railway deployment routes WebSocket messages between paired devices and wakes the iOS app via APNs push
**Depends on**: Nothing (first phase)
**Requirements**: RELAY-01, RELAY-02, RELAY-03, RELAY-04, RELAY-05, RELAY-06
**Success Criteria** (what must be TRUE):
  1. Two WebSocket clients can join the same room ID and exchange messages through the relay without client-to-client direct connection
  2. The relay sends an APNs alert push to a registered device token when a message arrives and no iOS client is in the room
  3. The relay is reachable at its Railway URL over TLS (wss://) with no manual certificate configuration
  4. The /health endpoint returns HTTP 200 so uptime monitoring tools can confirm the server is alive
  5. A third client attempting to join a room with two existing clients is rejected
**Plans:** 4 plans (3 complete, 1 gap closure pending)

Plans:
- [x] 01-01-PLAN.md -- Scaffold relay project, types, logger, and RoomManager with tests
- [x] 01-02-PLAN.md -- APNs client wrapper and message handler routing with tests
- [x] 01-03-PLAN.md -- Server entry point, health endpoint, WebSocket wiring, and local verification
- [x] 01-04-PLAN.md -- Gap closure: Railway deployment configuration and provisioning (RELAY-03)

### Phase 2: iOS Relay Client + Pairing
**Goal**: The iOS app can connect to the relay, register for push notifications, handle a code request, and display a pairing management screen
**Depends on**: Phase 1
**Requirements**: IOS-01, IOS-02, IOS-03, IOS-04, PAIR-02, PAIR-04, CODE-02
**Success Criteria** (what must be TRUE):
  1. The iOS app connects to the relay room when the user opens a paired session (foreground-only, no background socket)
  2. The iOS app receives an APNs alert push when the relay has a pending code request, and tapping the notification opens the app to the approval screen
  3. The TOTP approval sheet shows the account name and site, and Face ID or Touch ID must pass before a code is generated and sent
  4. The iOS app sends its APNs device token to the relay during the pairing handshake so future pushes reach the correct device
  5. The pairing management screen lists paired devices and allows the user to unpair any of them
**Plans:** 3 plans

Plans:
- [ ] 02-01-PLAN.md -- Core services: CryptoBoxManager (E2E encryption), PairingStore (Keychain), RelayClient (WebSocket)
- [ ] 02-02-PLAN.md -- APNs AppDelegate, push entitlement, pairing views (scan QR, manage, unpair)
- [ ] 02-03-PLAN.md -- Code approval sheet with biometric gate, ContentView + KeyAuthApp wiring

### Phase 3: Chrome Extension Core
**Goal**: The Chrome extension popup lets the user pick an account, request a code from the phone, and receive the code with an expiry countdown — the full request-to-code flow works end-to-end
**Depends on**: Phase 2
**Requirements**: PAIR-01, PAIR-03, PAIR-05, CODE-01, CODE-03, CODE-04, FILL-03
**Success Criteria** (what must be TRUE):
  1. The extension popup displays a QR code containing the room ID and relay URL so the user can pair their phone by scanning once
  2. Pairing tokens shown in the QR code are single-use and expire after their TTL; a second scan of the same QR fails
  3. The popup shows a connected, disconnected, or paired status indicator that reflects the actual relay connection state
  4. The user selects an account in the popup, the request reaches the phone, Face ID approves it, and the 6-digit code appears in the popup within the 30-second TOTP window
  5. The popup displays the received code alongside a live expiry countdown timer, and a clipboard copy button clears the clipboard after 30 seconds
**Plans**: TBD

### Phase 4: Auto-Fill + Domain Matching
**Goal**: The browser auto-fills TOTP fields with received codes and surfaces relevant accounts by matching the current domain
**Depends on**: Phase 3
**Requirements**: CODE-05, FILL-01, FILL-02
**Success Criteria** (what must be TRUE):
  1. When a webpage has a TOTP input field (detected by autocomplete attribute or heuristic), the content script identifies it without any user action
  2. After a code is received, the content script fills the detected TOTP field automatically so the user does not have to copy or paste
  3. The extension popup shows accounts that match the current website domain at the top of the list, reducing the need to scroll or search
**Plans**: TBD

### Phase 5: Resilience
**Goal**: The extension and iOS app recover automatically from WebSocket drops, service worker restarts, and APNs token refreshes — the happy path survives production network conditions
**Depends on**: Phase 4
**Requirements**: RESIL-01, RESIL-02, RESIL-03, RESIL-04, RESIL-05
**Success Criteria** (what must be TRUE):
  1. The Chrome service worker sends WebSocket keepalive pings every 20 seconds so the relay connection does not go silent and trigger a server-side timeout
  2. Both the extension and iOS app reconnect to the relay before the 15-minute Railway WebSocket timeout expires, so a long idle session does not result in a silent disconnection
  3. After the Chrome service worker wakes from sleep, it rebuilds its in-memory state from chrome.storage.session and rejoins the relay room without user intervention
  4. The iOS app re-registers its APNs device token on every launch so a token refresh (issued by APNs) does not break push delivery
  5. If the extension's WebSocket drops unexpectedly, it reconnects and rejoins its room automatically so the next code request succeeds without the user reparing
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Relay Server | 4/4 | Complete | 2026-04-15 |
| 2. iOS Relay Client + Pairing | 0/3 | Planned | - |
| 3. Chrome Extension Core | 0/TBD | Not started | - |
| 4. Auto-Fill + Domain Matching | 0/TBD | Not started | - |
| 5. Resilience | 0/TBD | Not started | - |
