---
phase: 01-relay-server
plan: 02
subsystem: infra
tags: [apns, push-notification, message-handler, websocket, routing, apns2]

# Dependency graph
requires:
  - phase: 01-relay-server plan 01
    provides: "RoomManager, MessageEnvelope/Client/Room types, pino logger"
provides:
  - "APNs client wrapper with createApnsClient and sendWakeupPush"
  - "Message handler with parseMessage and handleMessage dispatch"
  - "10-test APNs suite and 15-test handler suite"
affects: [01-relay-server, 03-ios-relay]

# Tech tracking
tech-stack:
  added: []
  patterns: [dependency injection for APNs mocking, switch-based message dispatch, best-effort push delivery]

key-files:
  created:
    - relay/src/apns.ts
    - relay/src/apns.test.ts
    - relay/src/handlers.ts
    - relay/src/handlers.test.ts
  modified: []

key-decisions:
  - "APNs push errors caught and logged, never thrown -- best-effort delivery"
  - "Support both APNS_KEY (base64) and APNS_KEY_PATH (file) for signing key flexibility"
  - "APNS_ENVIRONMENT defaults to production; sandbox via env var toggle"
  - "Dependency injection via _setApnsClientForTesting for testable APNs mocking"

patterns-established:
  - "Best-effort push: catch all APNs errors, log, continue relay operation"
  - "Dependency injection test helpers: _setApnsClientForTesting / _resetForTesting"
  - "Switch-based message dispatch: join/register_token/ping handled, everything else forwarded opaquely"
  - "Mock RoomManager helper for handler testing with configurable overrides"

requirements-completed: [RELAY-02, RELAY-05]

# Metrics
duration: 4min
completed: 2026-04-15
---

# Phase 01 Plan 02: APNs Push Integration & Message Handler Summary

**APNs alert push client with base64/file key loading and best-effort delivery, plus message handler routing join/register_token/ping with opaque forwarding and push-on-absence logic, backed by 25 tests**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-15T06:04:29Z
- **Completed:** 2026-04-15T06:08:16Z
- **Tasks:** 2
- **Files created:** 4

## Accomplishments
- Implemented APNs client wrapper supporting both base64 env var and file path for p8 signing key
- Implemented message handler with parseMessage envelope validation and handleMessage switch dispatch
- APNs push sent only when iOS client absent from room (D-10), with BadDeviceToken/Unregistered error handling
- All 25 new tests pass (10 APNs + 15 handler); 40 total tests pass across relay project

## Task Commits

Each task was committed atomically (TDD RED + GREEN per task):

1. **Task 1: APNs client wrapper RED** - `dc643f5` (test)
2. **Task 1: APNs client wrapper GREEN** - `0170564` (feat)
3. **Task 2: Message handler routing RED** - `1e8a6fe` (test)
4. **Task 2: Message handler routing GREEN** - `368a502` (feat)

_Both tasks used TDD with separate RED and GREEN commits._

## Files Created/Modified
- `relay/src/apns.ts` - APNs client wrapper: createApnsClient, sendWakeupPush, config validation
- `relay/src/apns.test.ts` - 10 tests for APNs client init, env var handling, push, error handling
- `relay/src/handlers.ts` - Message handler: parseMessage, handleMessage with join/register_token/ping/forward
- `relay/src/handlers.test.ts` - 15 tests for message parsing, routing, error responses, push triggering

## Decisions Made
- APNs push errors are caught and logged but never thrown -- push is best-effort, must not block relay operation (per threat model)
- Support both APNS_KEY (base64 for Railway env var) and APNS_KEY_PATH (file for local dev) per RESEARCH.md recommendation
- APNS_ENVIRONMENT defaults to production, sandbox via explicit env var (per RESEARCH.md open question 2)
- Used dependency injection pattern (_setApnsClientForTesting) instead of mock.module for ESM-compatible test mocking
- Device token truncated to first 8 chars in warning logs to prevent exposure

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Used dependency injection instead of mock.module for ESM mocking**
- **Found during:** Task 1 (APNs test RED phase)
- **Issue:** `mock.module()` from node:test requires `--experimental-test-module-mocks` flag on Node.js 23, not available by default with tsx runner
- **Fix:** Added `_setApnsClientForTesting` and `_resetForTesting` exports to apns.ts for test dependency injection
- **Files modified:** relay/src/apns.ts, relay/src/apns.test.ts
- **Verification:** All 10 APNs tests pass without experimental flags
- **Committed in:** 0170564 (Task 1 GREEN commit)

**2. [Rule 1 - Bug] Fixed TypeScript cast narrowing in handler tests**
- **Found during:** Task 2 (handler test verification)
- **Issue:** `tsc --noEmit` reported TS2352 errors on direct cast from mock function to `Mock<Function>` type
- **Fix:** Added intermediate `unknown` cast: `as unknown as ReturnType<typeof mock.fn>`
- **Files modified:** relay/src/handlers.test.ts
- **Verification:** `tsc --noEmit` exits 0
- **Committed in:** 368a502 (Task 2 GREEN commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for test infrastructure compatibility. No scope creep.

## Issues Encountered

None beyond the deviations noted above.

## User Setup Required

None - no external service configuration required. APNs p8 key setup is needed before deployment (documented in existing blocker in STATE.md).

## Next Phase Readiness
- APNs client wrapper ready for index.ts to call createApnsClient() at startup
- Message handler ready for index.ts to call handleMessage() on WebSocket message events
- All relay core modules complete: types, logger, rooms, apns, handlers
- Remaining: index.ts entry point (Plan 03) to wire everything together

## Self-Check: PASSED

All 4 created files verified on disk. All 4 task commits (dc643f5, 0170564, 1e8a6fe, 368a502) verified in git log.

---
*Phase: 01-relay-server*
*Completed: 2026-04-15*
