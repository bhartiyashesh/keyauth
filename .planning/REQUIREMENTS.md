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

- [ ] **PAIR-01**: Chrome extension generates a QR code containing roomId and relay URL for one-time pairing
- [x] **PAIR-02**: iOS app scans pairing QR code and joins the relay room
- [ ] **PAIR-03**: Pairing tokens are single-use and expire after a TTL (e.g., 5 minutes)
- [ ] **PAIR-04**: iOS app sends APNs device token to relay during pairing handshake
- [ ] **PAIR-05**: Extension popup shows pairing status indicator (connected/disconnected/paired)

### Code Request & Delivery

- [ ] **CODE-01**: User clicks extension popup, selects an account, and initiates a code request
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
- [ ] **IOS-02**: iOS app registers for and handles APNs alert push notifications
- [ ] **IOS-03**: iOS app presents a TOTP approval sheet (account name, site, approve/deny + Face ID)
- [x] **IOS-04**: iOS app includes a pairing management screen (view paired devices, unpair)

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
| IOS-02 | Phase 2 | Pending |
| IOS-03 | Phase 2 | Pending |
| IOS-04 | Phase 2 | Complete |
| PAIR-01 | Phase 3 | Pending |
| PAIR-02 | Phase 2 | Complete |
| PAIR-03 | Phase 3 | Pending |
| PAIR-04 | Phase 2 | Pending |
| PAIR-05 | Phase 3 | Pending |
| CODE-01 | Phase 3 | Pending |
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

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-15*
*Last updated: 2026-04-14 — corrected count to 28; traceability confirmed against ROADMAP.md*
