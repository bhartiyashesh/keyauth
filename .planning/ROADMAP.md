# Roadmap: KeyAuth Chrome Extension

## Milestones

- 🚧 **v1.0 MVP** - Phases 1-7 (in progress, remaining work rolled into v2.0)
- 📋 **v2.0 Beautiful, Seamless, Untouchable** - Phases 8-13 (planned)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-7)</summary>

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
**Plans:** 4 plans

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
  5. If the extension's WebSocket drops unexpectedly, it reconnects and rejoins its room automatically so the next code request succeeds without the user repairing
**Plans**: TBD

### Phase 6: iCloud Keychain Sync
**Goal**: TOTP account secrets sync automatically across the user's Apple devices via iCloud Keychain
**Depends on**: Phase 5
**Requirements**: ICLOUD-01 through ICLOUD-16
**Plans**: 6 plans (06-01..06-06)

### Phase 7: FaceID Capability Tokens
**Goal**: Replace per-fetch FaceID with scoped, TTL'd authorization tokens to eliminate prompts during re-auth loops
**Depends on**: Phase 6
**Requirements**: FIDO-01 through FIDO-19
**Plans**: 8 plans (07-01..07-08)

Plans:
- [x] 07-01-PLAN.md -- Foundation: register FIDO-01..19, create Wave 0 test scaffolds, CodeRequestFixtures
- [x] 07-02-PLAN.md -- TrustWindowPreference helper
- [x] 07-03-PLAN.md -- TrustWindowManager core singleton
- [x] 07-04-PLAN.md -- RelayClient silent-send branch + accountResolver closure
- [x] 07-05-PLAN.md -- TransientToastOverlay + CodeApprovalView mint
- [x] 07-06-PLAN.md -- KeyAuthApp wiring
- [x] 07-07-PLAN.md -- SettingsView toggle + ContentView overlay mount
- [x] 07-08-PLAN.md -- Traceability flip, QA checklist, STATE.md update

</details>

### v2.0 Beautiful, Seamless, Untouchable

**Milestone Goal:** Complete the core extension flow and make KeyAuth the authenticator people actually want to switch to -- smart keyboard, batch import, guided onboarding, encrypted backup.

- [ ] **Phase 8: Core Extension Flow** - Complete v1.0 carry-forward: code display, auto-fill, resilience, and approval sheet
- [ ] **Phase 9: Smart Sort + Extension Accounts** - Account model gains usage tracking; extension gets a synced, searchable account list
- [ ] **Phase 10: Keyboard Filter Bar** - Issuer chip filter and visual grouping for keyboards with many accounts
- [ ] **Phase 11: Google Authenticator Import** - Batch import from Google Auth export QR codes and manual URI entry
- [ ] **Phase 12: Encrypted Backup** - Password-protected export/import of all TOTP accounts
- [ ] **Phase 13: Onboarding** - First-launch keyboard activation guide, import wizard, and pairing walkthrough

## Phase Details

### Phase 8: Core Extension Flow
**Goal**: The full code request, delivery, auto-fill, and resilience pipeline works end-to-end across Chrome extension, relay, and iOS app -- the v1.0 happy path is complete
**Depends on**: Phase 7
**Requirements**: CODE-03, CODE-04, CODE-05, FILL-01, FILL-02, FILL-03, RESIL-01, RESIL-02, RESIL-03, RESIL-04, RESIL-05, IOS-03
**Success Criteria** (what must be TRUE):
  1. User clicks an account in the Chrome extension, approves with Face ID on the phone, and the 6-digit code appears in the extension popup with a countdown timer -- all within the 30-second TOTP window
  2. The extension auto-fills a detected TOTP input field on the active webpage after receiving the code, with no manual copy-paste required
  3. Accounts matching the current website domain appear at the top of the extension popup, reducing the common case to one click
  4. If the WebSocket drops or the Chrome service worker restarts, both clients reconnect and rejoin the room automatically -- the next code request succeeds without re-pairing
  5. The iOS app presents a TOTP approval sheet with account name and site info, requiring biometric approval before generating and sending the code
**Plans:** 6 plans

Plans:
- [x] 08-01-PLAN.md -- Types, domain-match utility, storage helpers (foundation contracts)
- [ ] 08-02-PLAN.md -- Account list popup UI (AccountList, AccountItem, ReconnectingBanner)
- [ ] 08-03-PLAN.md -- Service worker extensions (account_list, proactive reconnect, fill dispatch)
- [ ] 08-04-PLAN.md -- iOS RelayClient (sendAccountList, proactive reconnect, accountId resolve)
- [ ] 08-05-PLAN.md -- Content script (TOTP detection, auto-fill, split-input)
- [ ] 08-06-PLAN.md -- Service worker wake robustness (RESIL-03, RESIL-05)

### Phase 9: Smart Sort + Extension Accounts
**Goal**: The keyboard sorts accounts by how often and recently they are used, and the Chrome extension maintains a synced, searchable copy of account metadata for instant account selection
**Depends on**: Phase 8
**Requirements**: KEYB-01, KEYB-02, KEYB-06, EXT-01, EXT-02, EXT-03, EXT-04, EXT-05
**Success Criteria** (what must be TRUE):
  1. In the keyboard extension, the account the user tapped most recently appears first, with a weighted sort combining recency (70%) and frequency (30%)
  2. Usage data (lastUsed, useCount) persists across keyboard sessions via SharedDefaults and is promoted to Keychain by the companion app
  3. The Chrome extension popup displays the full account list (issuer + label) received from the phone, with a search bar that filters as the user types
  4. User selects a specific account in the extension, which sends a targeted code request for that account ID -- no ambiguity about which account to generate for
  5. Domain matching auto-highlights accounts matching the current tab's domain at the top of the extension list
**Plans**: TBD
**UI hint**: yes

### Phase 10: Keyboard Filter Bar
**Goal**: Users with many accounts can quickly narrow the keyboard account list using issuer chip filters and visual grouping
**Depends on**: Phase 9
**Requirements**: KEYB-03, KEYB-04, KEYB-05
**Success Criteria** (what must be TRUE):
  1. The keyboard displays a horizontal row of UIButton-based issuer chips (not a UITextField) that filter accounts to a single issuer on tap
  2. The top 5 most-used issuers appear as quick-filter chips, with the rest accessible via a "More" action
  3. When the user has more than 8 accounts, the keyboard groups them by issuer with visible section headers
**Plans**: TBD
**UI hint**: yes

### Phase 11: Google Authenticator Import
**Goal**: Users can migrate all their 2FA accounts from Google Authenticator in one session by scanning export QR codes or pasting URIs
**Depends on**: Phase 9 (needs Base32.encode from KEYB-06)
**Requirements**: IMPORT-01, IMPORT-02, IMPORT-03, IMPORT-04, IMPORT-05
**Success Criteria** (what must be TRUE):
  1. User can scan one or more Google Authenticator export QR codes and see a progress indicator ("QR 2 of 3") for multi-QR batch exports
  2. The protobuf decoder correctly parses Google's MigrationPayload schema (secret, name, issuer, algorithm, digits, type) in pure Swift with no external dependencies
  3. Decoded accounts appear in the main account list immediately after import, with duplicates detected and skipped
  4. Power users can paste an otpauth:// URI directly to add a single account
  5. After import, a summary screen shows counts of imported, skipped (duplicate), and failed accounts
**Plans**: TBD

### Phase 12: Encrypted Backup
**Goal**: Users can export all their TOTP accounts to a password-protected file and restore from it on any device, eliminating the fear of phone loss
**Depends on**: Phase 8 (needs working account model; no dependency on keyboard or import)
**Requirements**: BACKUP-01, BACKUP-02, BACKUP-03, BACKUP-04, BACKUP-05
**Success Criteria** (what must be TRUE):
  1. User can export all accounts to a .keyauth file protected by a user-chosen password, using AES-256-GCM with PBKDF2-SHA256 key derivation
  2. The export file has a cleartext header (magic bytes, version, salt, iteration count) enabling future format upgrades without breaking old files
  3. User can import a .keyauth file by entering the password, with duplicates detected against existing accounts
  4. Settings shows "Last exported" date and nudges the user if they have 3+ accounts but have not exported in 30+ days
  5. All crypto uses only CryptoKit and CommonCrypto -- zero external dependencies
**Plans**: TBD
**UI hint**: yes

### Phase 13: Onboarding
**Goal**: First-time users are guided through keyboard activation, account import, and Chrome extension pairing so they reach value without confusion
**Depends on**: Phase 11 (references import flow), Phase 12 (can mention backup)
**Requirements**: ONBOARD-01, ONBOARD-02, ONBOARD-03, ONBOARD-04, ONBOARD-05
**Success Criteria** (what must be TRUE):
  1. First launch shows a step-by-step keyboard activation guide with illustrations for enabling KeyAuth keyboard in iOS Settings
  2. Onboarding offers an import wizard with "Import from Google Authenticator", "Scan QR Code", and "Enter Manually" as entry points
  3. A pairing walkthrough explains how to connect the Chrome extension (Install extension, Scan QR, Done)
  4. Onboarding state is versioned (integer) in SharedDefaults so both app and keyboard extension can read it, and future additions do not reset completed steps
  5. Existing users upgrading with accounts already present see abbreviated onboarding (keyboard activation + import wizard only, skip intro)
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 8 -> 9 -> 10 -> 11 -> 12 -> 13
(Phase 12 can execute in parallel with 10-11 if desired, as it has no dependency on keyboard or import features)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Relay Server | 4/4 | Complete | 2026-04-15 |
| 2. iOS Relay Client + Pairing | 3/3 | Complete | 2026-04-15 |
| 3. Chrome Extension Core | 2/3 | In Progress | - |
| 4. Auto-Fill + Domain Matching | 0/TBD | Not started | - |
| 5. Resilience | 0/TBD | Not started | - |
| 6. iCloud Keychain Sync | 6/6 | Conditional Pass | - |
| 7. FaceID Capability Tokens | 8/8 | Complete | - |
| 8. Core Extension Flow | 0/TBD | Not started | - |
| 9. Smart Sort + Extension Accounts | 0/TBD | Not started | - |
| 10. Keyboard Filter Bar | 0/TBD | Not started | - |
| 11. Google Authenticator Import | 0/TBD | Not started | - |
| 12. Encrypted Backup | 0/TBD | Not started | - |
| 13. Onboarding | 0/TBD | Not started | - |
