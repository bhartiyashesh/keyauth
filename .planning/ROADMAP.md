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
- [ ] **Phase 6: iCloud Keychain Sync** - Sync TOTP seeds across Apple devices via iCloud Keychain with user opt-in and migration

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
- [x] 02-01-PLAN.md -- Core services: CryptoBoxManager (E2E encryption), PairingStore (Keychain), RelayClient (WebSocket)
- [x] 02-02-PLAN.md -- APNs AppDelegate, push entitlement, pairing views (scan QR, manage, unpair)
- [x] 02-03-PLAN.md -- Code approval sheet with biometric gate, ContentView + KeyAuthApp wiring

### Phase 3: Chrome Extension Core
**Goal**: The Chrome extension popup lets the user pick an account, request a code from the phone, and receive the code with an expiry countdown -- the full request-to-code flow works end-to-end
**Depends on**: Phase 2
**Requirements**: PAIR-01, PAIR-03, PAIR-05, CODE-01, CODE-03, CODE-04, FILL-03
**Success Criteria** (what must be TRUE):
  1. The extension popup displays a QR code containing the room ID and relay URL so the user can pair their phone by scanning once
  2. Pairing tokens shown in the QR code are single-use and expire after their TTL; a second scan of the same QR fails
  3. The popup shows a connected, disconnected, or paired status indicator that reflects the actual relay connection state
  4. The user selects an account in the popup, the request reaches the phone, Face ID approves it, and the 6-digit code appears in the popup within the 30-second TOTP window
  5. The popup displays the received code alongside a live expiry countdown timer, and a clipboard copy button clears the clipboard after 30 seconds
**Plans:** 3 plans

Plans:
- [x] 03-01-PLAN.md -- WXT project scaffold, CryptoBox module (X25519+ChaCha20 interop with CryptoKit), types, and storage wrappers
- [x] 03-02-PLAN.md -- Service worker (WebSocket, keepalive, message routing) and popup UI (QR pairing, status indicator, Request Code)
- [ ] 03-03-PLAN.md -- Code display with countdown ring, clipboard copy with 30s auto-clear, end-to-end verification

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
**Goal**: The extension and iOS app recover automatically from WebSocket drops, service worker restarts, and APNs token refreshes -- the happy path survives production network conditions
**Depends on**: Phase 4
**Requirements**: RESIL-01, RESIL-02, RESIL-03, RESIL-04, RESIL-05
**Success Criteria** (what must be TRUE):
  1. The Chrome service worker sends WebSocket keepalive pings every 20 seconds so the relay connection does not go silent and trigger a server-side timeout
  2. Both the extension and iOS app reconnect to the relay before the 15-minute Railway WebSocket timeout expires, so a long idle session does not result in a silent disconnection
  3. After the Chrome service worker wakes from sleep, it rebuilds its in-memory state from chrome.storage.session and rejoins the relay room without user intervention
  4. The iOS app re-registers its APNs device token on every launch so a token refresh (issued by APNs) does not break push delivery
  5. If the extension's WebSocket drops unexpectedly, it reconnects and rejoins its room automatically so the next code request succeeds without the user reparing
**Plans**: TBD

### Phase 6: iCloud Keychain Sync
**Goal**: TOTP account secrets sync automatically across the user's Apple devices (iPhones, iPads) via iCloud Keychain — a new device restores all 2FA accounts after signing into Apple ID, with no extra setup
**Depends on**: Phase 5 (can be executed in parallel if isolated to iOS components)
**Requirements**: ICLOUD-01, ICLOUD-02, ICLOUD-03, ICLOUD-04, ICLOUD-05, ICLOUD-06, ICLOUD-07, ICLOUD-08, ICLOUD-09, ICLOUD-10, ICLOUD-11, ICLOUD-12, ICLOUD-13, ICLOUD-14, ICLOUD-15, ICLOUD-16
**Success Criteria** (what must be TRUE):
  1. With iCloud sync enabled, TOTP accounts added on device A appear on device B (same Apple ID) within typical iCloud Keychain propagation time, without re-pairing or re-scanning QR codes
  2. The user is shown a clear disclosure of what iCloud sync means (secrets stored in iCloud, protected by Apple ID + device passcode) before enabling, and can toggle it off at any time in Settings
  3. Existing users who already have local-only accounts can migrate them to iCloud sync with a single confirmation, without losing any accounts or creating duplicates
  4. Disabling sync gives the user a clear choice: stop syncing this device only, or remove all synced copies from iCloud across all devices
  5. The keyboard extension continues to see the same accounts as the app (via shared App Group) whether sync is enabled or not
  6. Device-bound data (pairings, identity keys, APNs tokens) explicitly does NOT sync — only TOTP account secrets do
**Plans**: 6 plans (06-01..06-06)

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Relay Server | 4/4 | Complete | 2026-04-15 |
| 2. iOS Relay Client + Pairing | 3/3 | Complete | 2026-04-15 |
| 3. Chrome Extension Core | 2/3 | In Progress | - |
| 4. Auto-Fill + Domain Matching | 0/TBD | Not started | - |
| 5. Resilience | 0/TBD | Not started | - |
| 6. iCloud Keychain Sync | 6/6 | Conditional Pass (manual QA pending) | - |
| 7. FaceID Capability Tokens | 0/TBD | Not planned | - |

### Phase 7: FaceID Capability Tokens

**Goal:** Replace per-fetch FaceID with scoped, TTL'd authorization tokens (CTAP-inspired) to eliminate prompts during re-auth loops on the same login page, without weakening phishing resistance.

**Description:**
After a FaceID-approved fetch, mint an in-memory capability token scoped to `{origin, account_id}` with a 5-minute TTL. Subsequent fetches matching the same scope skip FaceID; any mismatch (different origin, different account, expired TTL) re-prompts. iOS side holds a long-lived `LAContext` using `touchIDAuthenticationAllowableReuseDuration`, with an app-level scope map layered on top. The relay envelope must carry a verified origin captured by the Chrome extension via `chrome.tabs` (not user-supplied) so phishing sites cannot reuse tokens minted for real sites. Revocation paths: app background > N seconds, iCloud account change (already tracked by `ICloudStateObserver` from Phase 6), or explicit "Lock now" action. A Settings toggle disables the feature entirely; per-fetch FaceID remains the default-safe fallback.

**Requirements:** FIDO-01, FIDO-02, FIDO-03, FIDO-04, FIDO-05, FIDO-06, FIDO-07, FIDO-08, FIDO-09, FIDO-10, FIDO-11, FIDO-12, FIDO-13, FIDO-14, FIDO-15, FIDO-16, FIDO-17, FIDO-18, FIDO-19
**Depends on:** Phase 6 (reuses `ICloudStateObserver` for revocation on iCloud account change)
**Directory:** `.planning/phases/07-faceid-capability-tokens/`
**Plans:** 8 plans (07-01..07-08)

Plans:
- [x] 07-01-PLAN.md — Foundation: register FIDO-01..19, create Wave 0 test scaffolds, CodeRequestFixtures
- [ ] 07-02-PLAN.md — TrustWindowPreference helper (UserDefaults-backed toggle state, default ON)
- [ ] 07-03-PLAN.md — TrustWindowManager core singleton (mint, revoke, isInWindow, toast) + fill manager tests
- [ ] 07-04-PLAN.md — RelayClient silent-send branch + accountResolver closure + fill silent-send tests
- [ ] 07-05-PLAN.md — TransientToastOverlay duration parameterization + CodeApprovalView mint + delete startAutoRefresh
- [ ] 07-06-PLAN.md — KeyAuthApp wiring: @StateObject, EnvironmentObject, bootstrap, resolver closure
- [ ] 07-07-PLAN.md — SettingsView toggle + ContentView overlay mount + extend SettingsViewTests
- [ ] 07-08-PLAN.md — Traceability flip, QA checklist, STATE.md update
