---
phase: 01-relay-server
plan: 01
subsystem: infra
tags: [node, typescript, websocket, ws, pino, room-manager, ttl-eviction]

# Dependency graph
requires: []
provides:
  - "relay/ Node.js project with package.json, tsconfig, .gitignore"
  - "MessageEnvelope, Client, Room, ErrorCode type definitions"
  - "Pino structured JSON logger"
  - "RoomManager class with join/leave/forward/evict/getRoom/clientCount/hasIosClient"
  - "15-test suite covering room lifecycle and TTL eviction"
affects: [01-relay-server, 02-chrome-extension, 03-ios-relay]

# Tech tracking
tech-stack:
  added: [ws 8.20.x, apns2 12.2.x, pino 10.x, tsx 4.x, typescript 6.x]
  patterns: [ESM modules, strict TypeScript, node:test runner, pino structured logging]

key-files:
  created:
    - relay/package.json
    - relay/tsconfig.json
    - relay/.gitignore
    - relay/.nvmrc
    - relay/src/types.ts
    - relay/src/logger.ts
    - relay/src/rooms.ts
    - relay/src/rooms.test.ts
  modified: []

key-decisions:
  - "Implicit room creation on first join -- no separate create API"
  - "30-minute TTL default for room eviction, configurable via constructor"
  - "Room NOT deleted on client leave -- TTL handles cleanup per D-06"
  - "deviceToken stored on both Client and Room for APNs lookup flexibility"

patterns-established:
  - "ESM project with type:module and .js import extensions in TypeScript"
  - "node:test + node:assert/strict for test runner (no external test framework)"
  - "Mock WebSocket objects with { readyState, send: mock.fn() } pattern"
  - "Pino default JSON logger with LOG_LEVEL env var override"

requirements-completed: [RELAY-01, RELAY-06]

# Metrics
duration: 3min
completed: 2026-04-15
---

# Phase 01 Plan 01: Relay Project Scaffold & RoomManager Summary

**In-memory RoomManager with join/leave/forward/TTL-eviction, backed by 15 tests using node:test, in a scaffolded Node.js ESM project with ws, apns2, and pino**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-15T05:58:35Z
- **Completed:** 2026-04-15T06:01:53Z
- **Tasks:** 2
- **Files created:** 9

## Accomplishments
- Scaffolded relay/ Node.js project with ESM, strict TypeScript, and all dependencies (ws, apns2, pino)
- Defined shared types (MessageEnvelope, Client, Room, ErrorCode) for relay protocol
- Implemented RoomManager class with full room lifecycle: join, leave, forward, evict, getRoom, clientCount, hasIosClient
- Wrote and passed 15 test cases covering room creation, multi-client join, device token storage, TTL eviction, message forwarding, and capacity checking

## Task Commits

Each task was committed atomically:

1. **Task 1: Scaffold relay project with types and logger** - `dd2cd70` (feat)
2. **Task 2: TDD RED -- Failing tests for RoomManager** - `8aee26a` (test)
3. **Task 2: TDD GREEN -- RoomManager implementation** - `ea2970d` (feat)

_TDD task had separate RED and GREEN commits._

## Files Created/Modified
- `relay/package.json` - Node.js project config with keyauth-relay name, ESM, Node >=22
- `relay/tsconfig.json` - Strict TypeScript config with noEmit (tsx handles runtime)
- `relay/.gitignore` - Excludes node_modules, dist, *.p8, .env files
- `relay/.nvmrc` - Pins Node.js 22 LTS
- `relay/src/types.ts` - Shared type definitions: MessageEnvelope, Client, Room, ErrorCode
- `relay/src/logger.ts` - Pino structured JSON logger instance
- `relay/src/rooms.ts` - RoomManager class with join/leave/forward/evict/getRoom/clientCount/hasIosClient
- `relay/src/rooms.test.ts` - 15 test cases using node:test and node:assert/strict
- `relay/package-lock.json` - Dependency lock file

## Decisions Made
- Implicit room creation on first join -- simplifies protocol, no race condition since both clients join same roomId independently
- 30-minute TTL default -- long enough for APNs-triggered reconnection, short enough to prevent unbounded memory growth
- Room persists after client leave (D-06) -- TTL-based eviction handles cleanup
- deviceToken stored on both Client object and Room object -- enables both per-client and per-room APNs lookup

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- RoomManager ready for handlers.ts to call join/leave/forward
- Types ready for import across all relay modules
- Logger ready for structured logging throughout relay
- Test pattern established for remaining modules (apns.test.ts, server.test.ts)

## Self-Check: PASSED

All 9 created files verified on disk. All 3 task commits (dd2cd70, 8aee26a, ea2970d) verified in git log.

---
*Phase: 01-relay-server*
*Completed: 2026-04-15*
