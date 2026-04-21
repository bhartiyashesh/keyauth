---
phase: 08-core-extension-flow
plan: 03
subsystem: chrome-extension
tags: [service-worker, accounts, reconnect, autofill, resilience]
dependency_graph:
  requires: [08-01]
  provides: [account-list-handling, proactive-reconnect, fill-dispatch, account-specific-code-request]
  affects: [08-04, 08-05, 08-06]
tech_stack:
  added: []
  patterns: [proactive-reconnect, content-script-dispatch, session-account-storage]
key_files:
  created: []
  modified:
    - extension/src/entrypoints/background.ts
decisions:
  - "Proactive reconnect at 13 minutes (2-min buffer before Railway 15-min timeout)"
  - "Fill dispatch checks tab.url starts with http before sending to content script (T-08-05)"
  - "Accounts cleared on any disconnect, not just unpair (D-01 compliance)"
metrics:
  duration: "3 minutes"
  completed: "2026-04-21"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
---

# Phase 08 Plan 03: Service Worker Account + Reconnect + Fill Summary

Extended background.ts to handle account list messages, send account-specific code requests with issuer/label lookup, dispatch fill_code to content scripts for auto-fill, and proactively reconnect at 13 minutes before Railway timeout.

## Task Summary

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add account_list handler, proactive reconnect timer, and domain getter | 32b5c92 | extension/src/entrypoints/background.ts |

## Changes Made

### Task 1: Service Worker Extensions

**account_list handler (D-01):**
- New `handleAccountList()` function decrypts account list from phone using shared key
- Stores accounts via `saveAccounts()` in session storage
- Switch case added in `handleRelayMessage` for `account_list` type
- Accounts cleared on WebSocket close (D-01: accounts only valid while connected)

**Proactive reconnect (D-08/RESIL-02):**
- Added `PROACTIVE_RECONNECT_MS = 13 * 60 * 1000` constant
- Timer starts in `ws.onopen`, closes connection at 13 minutes
- `onclose` handler triggers `scheduleReconnect` with exponential backoff
- `stopTimers()` updated to clear proactive reconnect timeout

**Content script fill dispatch (D-05):**
- After storing received code, queries active tab
- Sends `{ type: 'fill_code', code }` via `chrome.tabs.sendMessage`
- Checks `tab.url?.startsWith('http')` before dispatch (T-08-05 mitigation)
- Gracefully handles content script absence (falls back to popup display)

**Account-specific code request (D-02):**
- `request_code` case reads `message.accountId` and `message.domain` from popup
- Looks up account metadata to include issuer/label in encrypted request
- Falls back to active tab domain detection if popup doesn't provide domain
- Includes `accountId` in the encrypted code request payload

**get_state enrichment:**
- Returns `accounts` array and `domain` string alongside existing state
- Domain detection checks `tab.url?.startsWith('http')` for safety

## Deviations from Plan

None - plan executed exactly as written.

## Threat Surface Verification

| Threat ID | Mitigation | Status |
|-----------|-----------|--------|
| T-08-05 | fill_code only sent to http/https tabs | Implemented |
| T-08-06 | account_list decrypted with ChaCha20Poly1305, tampered data fails auth | Implemented |
| T-08-07 | Each code_request includes crypto.randomUUID() correlation ID | Implemented |

## Known Stubs

None. All data paths are wired to real storage and message handlers.

## Self-Check: PASSED
