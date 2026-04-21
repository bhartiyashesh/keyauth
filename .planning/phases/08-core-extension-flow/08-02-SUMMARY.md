---
phase: 08-core-extension-flow
plan: 02
subsystem: chrome-extension-popup
tags: [ui, accounts, domain-match, react]
dependency_graph:
  requires: [08-01]
  provides: [account-list-ui, domain-matched-sorting, reconnecting-banner]
  affects: [08-03, 08-04]
tech_stack:
  added: []
  patterns: [domain-match-sorting, storage-listener-accounts, confirm-dialog-unpair]
key_files:
  created:
    - extension/src/components/AccountItem.tsx
    - extension/src/components/AccountList.tsx
    - extension/src/components/ReconnectingBanner.tsx
  modified:
    - extension/src/components/ConnectedView.tsx
    - extension/src/entrypoints/popup/App.tsx
    - extension/src/entrypoints/popup/style.css
decisions:
  - "Collapsed three separate ConnectedView renders into a single conditional block with connectionState prop"
  - "Domain field defaults to empty string until Plan 08-03 provides active tab domain from background"
  - "Added dark mode overrides for new account-item and reconnecting-banner classes"
metrics:
  duration: 133s
  completed: "2026-04-21T13:14:09Z"
  tasks: 2
  files: 6
---

# Phase 08 Plan 02: Account List UI Summary

Scrollable account list with domain-matched sorting, per-account code request messaging, and reconnecting banner replacing the single "Request Code" button.

## Task Commits

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Create AccountItem, AccountList, ReconnectingBanner | 63da730 | AccountItem.tsx, AccountList.tsx, ReconnectingBanner.tsx |
| 2 | Refactor ConnectedView + App.tsx + CSS | 1d79b32 | ConnectedView.tsx, App.tsx, style.css |

## What Was Built

**AccountItem.tsx** - Single account row button with issuer badge (hsl color from name hash), domain-match indicator ("Suggested for this site"), and requesting state ("Waiting for approval..."). Uses same badge color formula as CodeView.tsx for consistency.

**AccountList.tsx** - Scrollable container that sorts accounts via `sortAccountsByDomain()`, renders AccountItem for each, sends `chrome.runtime.sendMessage({ type: 'request_code', accountId, domain })` on click. Shows empty state when no accounts synced.

**ReconnectingBanner.tsx** - Conditional amber banner showing "Connection lost. Reconnecting..." when connection state is disconnected or connecting.

**ConnectedView.tsx** - Refactored from single "Request Code" button to embed AccountList and ReconnectingBanner. Added confirm() dialog on unpair per UI-SPEC copywriting. Now accepts accounts and domain props.

**App.tsx** - Extended AppState with `accounts: AccountMetadata[]` and `domain: string`. Added `changes.accounts` storage listener. Clears accounts on disconnect (D-01 compliance). Collapsed three ConnectedView render branches into one.

**style.css** - Added account-item (48px min-height, 10px radius), domain-match accent (2px blue left border), reconnecting banner (amber 8% bg, full-width bleed), unpair button (red, auto margin-left). Dark mode overrides for new classes.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| `domain: ''` default | App.tsx | 36, 51 | Domain comes from background's get_state response; full tab domain detection arrives in Plan 08-03 (same wave). Empty string fallback is intentional progressive enhancement. |
