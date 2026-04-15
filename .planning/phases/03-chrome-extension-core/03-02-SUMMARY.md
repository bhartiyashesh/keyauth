---
phase: 03-chrome-extension-core
plan: 02
subsystem: extension, ui
tags: [wxt, react, websocket, service-worker, qr-code, manifest-v3, chrome-storage, keepalive]

# Dependency graph
requires:
  - phase: 03-chrome-extension-core
    plan: 01
    provides: CryptoBox (seal, open, deriveSharedKey), types (MessageEnvelope, PairingData, createEnvelope), storage wrappers
  - phase: 01-relay-server
    provides: WebSocket relay with room-based routing, join/ping/opaque forward protocol
provides:
  - Service worker with WebSocket connection, 20s keepalive, message routing, pairing completion
  - Popup UI with QR pairing view, connected view, and status indicator
  - Reactive state machine driven by chrome.storage changes
  - Encrypted code request/response flow between extension and iOS
affects: [03-03, 04-content-script]

# Tech tracking
tech-stack:
  added: []
  patterns: [service worker auto-reconnect on startup, chrome.storage.onChanged for popup reactivity, QR TTL auto-refresh with new keypair]

key-files:
  created:
    - extension/src/entrypoints/background.ts
    - extension/src/components/PairingView.tsx
    - extension/src/components/ConnectedView.tsx
    - extension/src/components/StatusDot.tsx
  modified:
    - extension/src/entrypoints/popup/App.tsx
    - extension/src/entrypoints/popup/style.css

key-decisions:
  - "defineBackground used as WXT auto-imported global (not from wxt/sandbox which does not exist)"
  - "QR payload stored as JSON string matching iOS PairingQRPayload: { roomId, relayURL, publicKey }"
  - "Service worker is sole WebSocket owner; popup communicates via chrome.runtime.sendMessage"

patterns-established:
  - "Service worker message protocol: start_pairing, complete_pairing, request_code, unpair, get_state"
  - "Popup state derived from chrome.storage.onChanged listener, not polling"
  - "Pairing flow: popup generates QR -> SW connects room -> iOS joins -> pairing_ack with publicKey -> deriveSharedKey -> savePairingData"
  - "Code request: seal(JSON(CodeRequest)) -> relay forward -> iOS decrypts -> iOS encrypts response -> relay forward -> SW open() decrypts"

requirements-completed: [PAIR-01, PAIR-03, PAIR-05, CODE-01]

# Metrics
duration: 5min
completed: 2026-04-15
---

# Phase 3 Plan 2: Service Worker and Popup UI Summary

**Service worker with WebSocket keepalive and message routing, React popup with QR pairing (5-min TTL) and Request Code button**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-15T19:50:40Z
- **Completed:** 2026-04-15T19:55:43Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Service worker manages WebSocket to relay with 20s keepalive pings and auto-reconnect
- Pairing flow: QR generation in popup, service worker connects room, key exchange on iOS join
- Encrypted code request/response using CryptoBox seal/open
- Popup renders three states (unpaired/connected/code_received) via reactive chrome.storage listener
- QR codes auto-refresh with new roomId and keypair every 5 minutes
- Dark mode support with prefers-color-scheme media query

## Task Commits

Each task was committed atomically:

1. **Task 1: Service worker with WebSocket, keepalive, and message routing** - `b0be953` (feat)
2. **Task 2: Popup UI with QR pairing, status indicator, and Request Code button** - `1092e5b` (feat)

## Files Created/Modified
- `extension/src/entrypoints/background.ts` - Service worker: WebSocket, keepalive, pairing, code request/response, message routing
- `extension/src/components/PairingView.tsx` - QR code display with 5-min TTL countdown and auto-refresh
- `extension/src/components/ConnectedView.tsx` - Request Code button, status dot, Unpair link
- `extension/src/components/StatusDot.tsx` - 8px colored dot with pulse animation for connecting state
- `extension/src/entrypoints/popup/App.tsx` - State machine: loads state from SW, listens to storage changes, renders views
- `extension/src/entrypoints/popup/style.css` - 320px popup, system-ui font, dark mode, button styles, QR container

## Decisions Made
- Used `defineBackground` as WXT auto-imported global -- `wxt/sandbox` export does not exist in WXT 0.20.x
- QR payload is a JSON string containing `{ roomId, relayURL, publicKey }` matching the iOS `PairingQRPayload` Codable struct
- Service worker owns the WebSocket; popup communicates exclusively via `chrome.runtime.sendMessage`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] WXT defineBackground import path**
- **Found during:** Task 1 (Service worker implementation)
- **Issue:** Plan specified `import { defineBackground } from 'wxt/sandbox'` but WXT 0.20.x does not export from `wxt/sandbox`
- **Fix:** Removed the import; `defineBackground` is auto-imported as a global by WXT
- **Files modified:** extension/src/entrypoints/background.ts
- **Verification:** `npm run build` succeeds
- **Committed in:** b0be953

---

**Total deviations:** 1 auto-fixed (1 blocking -- WXT import path)
**Impact on plan:** Minor fix. WXT auto-imports defineBackground globally; no semantic change.

## Issues Encountered
None beyond the auto-fixed WXT import documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Service worker and popup ready for Plan 03 (code display view with countdown ring and clipboard)
- Code response decryption working -- Plan 03 builds the visual CodeView component
- All five chrome.runtime message types operational for full request flow

## Self-Check: PASSED

All 6 files verified present. Both commits verified in git log.

---
*Phase: 03-chrome-extension-core*
*Completed: 2026-04-15*
