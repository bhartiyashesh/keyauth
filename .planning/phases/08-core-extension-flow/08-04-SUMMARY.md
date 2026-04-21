---
phase: 08-core-extension-flow
plan: 04
subsystem: ios-relay-client
tags: [relay, websocket, account-list, reconnect, apns]
dependency_graph:
  requires: [08-01]
  provides: [sendAccountListPayload, proactiveReconnect, accountId-resolution]
  affects: [Shared/RelayClient.swift, Shared/CryptoBoxManager.swift, Shared/AccountStore.swift, App/KeyAuthApp.swift]
tech_stack:
  added: []
  patterns: [proactive-reconnect, encrypted-metadata-push, uuid-account-lookup]
key_files:
  created: []
  modified:
    - Shared/CryptoBoxManager.swift
    - Shared/AccountStore.swift
    - Shared/RelayClient.swift
    - App/KeyAuthApp.swift
decisions:
  - accountId is optional String on CodeRequest for backward compatibility with existing code_request payloads
  - proactive reconnect uses single-fire Timer (repeats:false) to avoid overlapping reconnects
  - account list payload uses JSONSerialization (not Codable) because payload is [String:Any] with nested array
metrics:
  duration: 118s
  completed: 2026-04-21T13:13:31Z
  tasks_completed: 2
  tasks_total: 2
  files_changed: 4
---

# Phase 08 Plan 04: iOS Relay Enhancements Summary

Extended iOS RelayClient with encrypted account list push, proactive 13-minute reconnect, and accountId-based targeted code generation.

## Task Results

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add accountId to CodeRequest and update AccountStore.resolve | 40ee70f | Shared/CryptoBoxManager.swift, Shared/AccountStore.swift |
| 2 | Add sendAccountListPayload, proactive reconnect, accountListProvider wiring | 8468adb | Shared/RelayClient.swift, App/KeyAuthApp.swift |

## What Was Built

**Task 1 - accountId on CodeRequest:**
- Added optional `accountId: String?` field to `CodeRequest` struct in CryptoBoxManager.swift
- Updated `AccountStore.resolve(for:)` to check accountId UUID first (highest priority), then fall through to existing issuer+label and domain-based resolution
- Uses safe `UUID(uuidString:)` parsing -- invalid IDs fall through gracefully

**Task 2 - Account list push and proactive reconnect:**
- Added `sendAccountListPayload(_:)` method that encrypts account metadata (id, issuer, label only -- secrets never leave the phone) with CryptoBoxManager.seal and sends as `account_list` envelope
- Added `proactiveReconnectTimer` with 13-minute interval to preempt Railway's 15-minute WebSocket timeout (RESIL-02)
- Added `accountListProvider` closure property, wired in KeyAuthApp.onAppear alongside existing accountResolver
- WebSocketDelegate.didOpen now calls `startProactiveReconnect()` and sends account list on every connect
- `stopTimers()` updated to invalidate proactiveReconnectTimer
- APNs token registration verified as already satisfied by existing `requestPushPermissionAndRegister()` in onAppear (RESIL-04)

## Decisions Made

1. **accountId as optional String** -- Backward compatible with existing CodeRequest payloads that lack accountId; decoder treats missing field as nil
2. **Single-fire proactive reconnect timer** -- Uses `repeats: false` to avoid overlapping reconnect attempts; timer restarts on each new connection
3. **JSONSerialization for account list** -- Payload is `[String: Any]` with nested array, which Codable handles less cleanly than JSONSerialization

## Deviations from Plan

None -- plan executed exactly as written.

## Threat Surface Scan

No new threat surfaces beyond those already documented in the plan's threat model (T-08-08, T-08-09, T-08-10). The `sendAccountListPayload` method explicitly excludes the `secret` field and encrypts all metadata before transit.

## Known Stubs

None -- all data sources are wired and functional.

## Self-Check: PASSED

All 4 modified files exist. Both task commits (40ee70f, 8468adb) verified in git log.
