# Requirements: KeyAuth Chrome Extension

**Defined:** 2026-04-15
**Core Value:** One-click TOTP code delivery from phone to browser — secrets never leave the phone

## v1 Requirements

### Relay Infrastructure

- [x] **RELAY-01**: WebSocket relay server accepts connections and routes messages between paired devices via room IDs
- [x] **RELAY-02**: Relay sends APNs alert push to wake iOS app when code is requested and iOS client is absent
- [x] **RELAY-03**: Relay server runs on Railway with automatic TLS termination
- [x] **RELAY-04**: Relay exposes /health endpoint for uptime monitoring
- [x] **RELAY-05**: Relay manages APNs JWT token rotation (refresh at 45-minute intervals)
- [x] **RELAY-06**: Relay enforces max 2 clients per room

### Pairing

- [x] **PAIR-01**: Chrome extension generates a QR code containing roomId and relay URL for one-time pairing
- [x] **PAIR-02**: iOS app scans pairing QR code and joins the relay room
- [x] **PAIR-03**: Pairing tokens are single-use and expire after a TTL (e.g., 5 minutes)
- [x] **PAIR-04**: iOS app sends APNs device token to relay during pairing handshake
- [x] **PAIR-05**: Extension popup shows pairing status indicator (connected/disconnected/paired)

### Code Request & Delivery

- [x] **CODE-01**: User clicks extension popup, selects an account, and initiates a code request
- [x] **CODE-02**: iOS app receives code request and prompts Face ID/Touch ID before generating code
- [ ] **CODE-03**: TOTP code is generated on the phone after biometric approval, then sent via relay to extension
- [ ] **CODE-04**: Extension popup displays the received code with an expiry countdown timer
- [ ] **CODE-05**: Extension surfaces relevant accounts based on the current website domain

### Browser Integration

- [ ] **FILL-01**: Content script detects TOTP input fields using autocomplete attribute and heuristic fallbacks
- [ ] **FILL-02**: Extension auto-fills the detected TOTP field with the received code
- [ ] **FILL-03**: Extension provides clipboard copy with automatic 30-second clear as fallback

### Resilience

- [ ] **RESIL-01**: Chrome extension service worker sends 20-second WebSocket keepalive pings
- [ ] **RESIL-02**: Both clients proactively reconnect before Railway's 15-minute WebSocket timeout
- [ ] **RESIL-03**: Chrome service worker rebuilds state from chrome.storage.session on every wake
- [ ] **RESIL-04**: iOS app registers APNs device token on every launch (handles token refresh)
- [ ] **RESIL-05**: Extension reconnects and rejoins room automatically on WebSocket drop

### iOS App Additions

- [x] **IOS-01**: iOS app includes a WebSocket relay client (URLSessionWebSocketTask, foreground-only)
- [x] **IOS-02**: iOS app registers for and handles APNs alert push notifications
- [ ] **IOS-03**: iOS app presents a TOTP approval sheet (account name, site, approve/deny + Face ID)
- [x] **IOS-04**: iOS app includes a pairing management screen (view paired devices, unpair)

### iCloud Keychain Sync

- [x] **ICLOUD-01**: `KeychainManager.save` accepts a `synchronizable: Bool` parameter and sets `kSecAttrSynchronizable` accordingly on SecItemAdd
- [x] **ICLOUD-02**: All Keychain read queries (`loadAll`, `load`) include `kSecAttrSynchronizable: kSecAttrSynchronizableAny` so both synced and non-synced items are matched
- [x] **ICLOUD-03**: `KeychainManager.delete(id:)` removes both the synced and non-synced copies of the specified account
- [x] **ICLOUD-04**: A Settings screen is accessible from the main toolbar via a gear button and contains a "Sync with iCloud Keychain" toggle with the D-03 disclosure footer verbatim
- [x] **ICLOUD-05**: New users (with no prior `hasSeenSyncFirstLaunchCard` flag) see a first-launch card above the accounts empty state with the D-03 copy and a "Got it" dismiss action
- [x] **ICLOUD-06**: Turning the sync toggle OFF opens a confirmation with two explicit options: "Stop syncing this device" (default) and "Remove from iCloud on all devices" (destructive, `role: .destructive`)
- [x] **ICLOUD-07**: Flipping the toggle OFF→ON migrates all local-only accounts to synced storage by re-saving each with `synchronizable=true` and deleting the original non-sync copy, continuing on partial failure and surfacing the final count
- [x] **ICLOUD-08**: After migration or fresh-sync, accounts with identical `(normalized issuer, normalized label, canonicalized secret)` are deduplicated to the one with the earliest `createdAt`; a toast shows "Merged N duplicate accounts" when N > 0
- [x] **ICLOUD-09**: The "Remove from iCloud on all devices" action executes `SecItemDelete` with `kSecAttrSynchronizable: true` (not `SynchronizableAny`), preserving any non-synchronizable copies on the current device
- [x] **ICLOUD-10**: When the app's `scenePhase` becomes `.active`, `AccountStore.reload()` is invoked and `NSUbiquitousKeyValueStore.synchronize()` is called
- [x] **ICLOUD-11**: On every `KeychainManager.save` or `.delete` with sync enabled, an `accounts-version` Int64 counter in `NSUbiquitousKeyValueStore` is incremented; an observer on `didChangeExternallyNotification` triggers a coalesced (300ms debounce) `AccountStore.reload()` on `ServerChange` or `InitialSyncChange` reasons
- [x] **ICLOUD-12**: After `AccountStore.reload()` completes, the updated account list is written to `SharedDefaults` so the keyboard extension's next activation reads fresh data
- [x] **ICLOUD-13**: `PairingStore`, `CryptoBoxManager`, APNs device token storage, and any other per-device state do NOT set `kSecAttrSynchronizable=true` on their Keychain items; these items remain local to each device
- [x] **ICLOUD-14**: When `FileManager.default.ubiquityIdentityToken` is nil, the sync toggle is disabled and shows the D-11 inline copy with a functional "Open iOS Settings" deep-link button
- [x] **ICLOUD-15**: On `NSUbiquityIdentityDidChangeNotification` when the token becomes nil, the sync toggle flips to OFF and the D-12 inline copy is shown; when the token changes to a different non-nil value, the app treats this as a new iCloud account (clears SyncPreference, shows D-12 copy)
- [x] **ICLOUD-16**: Fresh install with `syncPreference.enabled=true` AND empty accounts list shows "Restoring your accounts from iCloud…" state for up to a configurable timeout (default 30 seconds, overridable for tests via `RestoringFromCloudView.restoringTimeoutSeconds`); if `accounts-version` changes or accounts arrive within the window, transition to normal state; otherwise fall through to normal empty state

## v2 Requirements

### Security

- **SEC-01**: E2E encryption layer (X25519 key exchange) on top of TLS
- **SEC-02**: Room ID rotation/revocation mechanism

### Platform Expansion

- **PLAT-01**: Firefox extension (WXT supports cross-browser)
- **PLAT-02**: Safari extension
- **PLAT-03**: Self-hosted relay option with Docker image

### Enhanced UX

- **UX-01**: Multi-account search/filter in extension popup
- **UX-02**: Countdown-aware delivery (wait for next period if <5s remaining)
- **UX-03**: Auto-detect TOTP field and prompt without clicking extension icon

## Out of Scope

| Feature | Reason |
|---------|--------|
| TOTP seed storage in browser | Core security model — seeds never leave the phone |
| Auto-fill on page load | Security risk (confirmed anti-pattern by 1Password, Bitwarden) |
| Bluetooth/local transport | Chrome extensions can't use Web Bluetooth API |
| Account sync across browsers | Each browser must pair independently |
| Persistent iOS WebSocket | iOS kills background WebSocket; APNs wakeup is the correct pattern |
| Silent APNs push | Throttled at ~3/hour by Apple; alert push is mandatory |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RELAY-01 | Phase 1 | Complete |
| RELAY-02 | Phase 1 | Complete |
| RELAY-03 | Phase 1 | Complete |
| RELAY-04 | Phase 1 | Complete |
| RELAY-05 | Phase 1 | Complete |
| RELAY-06 | Phase 1 | Complete |
| IOS-01 | Phase 2 | Complete |
| IOS-02 | Phase 2 | Complete |
| IOS-03 | Phase 2 | Pending |
| IOS-04 | Phase 2 | Complete |
| PAIR-01 | Phase 3 | Complete |
| PAIR-02 | Phase 2 | Complete |
| PAIR-03 | Phase 3 | Complete |
| PAIR-04 | Phase 2 | Complete |
| PAIR-05 | Phase 3 | Complete |
| CODE-01 | Phase 3 | Complete |
| CODE-02 | Phase 2 | Complete |
| CODE-03 | Phase 3 | Pending |
| CODE-04 | Phase 3 | Pending |
| CODE-05 | Phase 4 | Pending |
| FILL-01 | Phase 4 | Pending |
| FILL-02 | Phase 4 | Pending |
| FILL-03 | Phase 3 | Pending |
| RESIL-01 | Phase 5 | Pending |
| RESIL-02 | Phase 5 | Pending |
| RESIL-03 | Phase 5 | Pending |
| RESIL-04 | Phase 5 | Pending |
| RESIL-05 | Phase 5 | Pending |
| ICLOUD-01 | Phase 6 | Complete |
| ICLOUD-02 | Phase 6 | Complete |
| ICLOUD-03 | Phase 6 | Complete |
| ICLOUD-04 | Phase 6 | Complete |
| ICLOUD-05 | Phase 6 | Complete |
| ICLOUD-06 | Phase 6 | Complete |
| ICLOUD-07 | Phase 6 | Complete |
| ICLOUD-08 | Phase 6 | Complete |
| ICLOUD-09 | Phase 6 | Complete |
| ICLOUD-10 | Phase 6 | Complete |
| ICLOUD-11 | Phase 6 | Complete |
| ICLOUD-12 | Phase 6 | Complete |
| ICLOUD-13 | Phase 6 | Complete |
| ICLOUD-14 | Phase 6 | Complete |
| ICLOUD-15 | Phase 6 | Complete |
| ICLOUD-16 | Phase 6 | Complete |

**Coverage:**
- v1 requirements: 44 total
- Mapped to phases: 44
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-15*
*Last updated: 2026-04-18 — added ICLOUD-01..16 for Phase 6*
