---
phase: 01-relay-server
verified: 2026-04-15T06:41:21Z
status: gaps_found
score: 4/5 success criteria verified
re_verification: false
gaps:
  - truth: "The relay is reachable at its Railway URL over TLS (wss://) with no manual certificate configuration"
    status: failed
    reason: "No Railway project has been created. No deployment configuration exists (no railway.json, Dockerfile, nixpacks.toml, or Procfile). STATE.md explicitly lists this as a blocker: 'Railway project must be created and CLI configured before Phase 1 deploy step.'"
    artifacts:
      - path: "relay/"
        issue: "Server code is complete and Railway-ready (PORT env var, /health endpoint, tsx start script) but no Railway project has been provisioned or deployed"
    missing:
      - "Create a Railway project linked to the repo (railway login && railway init in the relay/ directory)"
      - "Configure env vars in the Railway dashboard: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY (base64), APNS_ENVIRONMENT"
      - "Confirm the Railway-assigned wss:// URL is reachable and /health returns 200"
human_verification:
  - test: "Railway deployment is live and /health responds"
    expected: "curl https://<railway-url>/health returns HTTP 200 with {\"status\":\"ok\",\"uptime\":<n>,\"timestamp\":\"...\"}"
    why_human: "Requires a live Railway deployment — cannot verify programmatically without a provisioned project"
  - test: "Two browser tabs exchange messages through the deployed relay"
    expected: "Message sent from Tab 1 is received by Tab 2 over wss://<railway-url>/?roomId=<uuid>. Tab 1 does not receive its own message."
    why_human: "Requires a live Railway deployment and end-to-end wss:// connectivity"
  - test: "APNs push is sent when a code request arrives with no iOS client in room"
    expected: "When a message is forwarded to an empty room with a stored deviceToken, the iOS device receives an APNs alert push titled 'KeyAuth' with body 'Approve 2FA request'"
    why_human: "Requires a real APNs p8 key, a physical iOS device with deviceToken registered, and a live Railway deployment"
---

# Phase 1: Relay Server Verification Report

**Phase Goal:** A live Railway deployment routes WebSocket messages between paired devices and wakes the iOS app via APNs push
**Verified:** 2026-04-15T06:41:21Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Two WebSocket clients can join the same room ID and exchange messages through the relay without client-to-client direct connection | VERIFIED | `rooms.ts` RoomManager.forward() confirmed wired; server integration Test 7 (two clients join) and Test 8 (third client rejected) pass; Test 8 in handlers.test.ts verifies opaque forwarding; all 11 server integration tests pass |
| 2 | The relay sends an APNs alert push to a registered device token when a message arrives and no iOS client is in the room | VERIFIED | `handlers.ts` lines 85-93 wire `hasIosClient` check to `sendWakeupPush`; `apns.ts` sendWakeupPush constructs alert push with title "KeyAuth", body "Approve 2FA request"; handlers Test 12 verifies push triggered when hasIosClient=false; handlers Test 13 verifies no push when iOS client present; 25 APNs+handler tests pass |
| 3 | The relay is reachable at its Railway URL over TLS (wss://) with no manual certificate configuration | FAILED | No Railway project exists. STATE.md blocker: "Railway project must be created and CLI configured before Phase 1 deploy step." No railway.json, Dockerfile, Procfile, or nixpacks.toml found in relay/ or project root. Code is Railway-ready (PORT env var, /health, tsx runner) but undeployed. |
| 4 | The /health endpoint returns HTTP 200 so uptime monitoring tools can confirm the server is alive | VERIFIED | `index.ts` line 22-31 implements GET /health returning 200 JSON with status/uptime/timestamp; server.test.ts Tests 1-2 confirm 200 response and correct body shape; all tests pass |
| 5 | A third client attempting to join a room with two existing clients is rejected | VERIFIED | `index.ts` line 48-52 checks `roomManager.clientCount(roomId) >= 2` and responds HTTP 403 before completing the handshake; server.test.ts Test 8 confirms rejection; RoomManager.clientCount backed by rooms.test.ts Test 14 |

**Score:** 4/5 success criteria verified (1 blocked on Railway deployment)

---

## Required Artifacts

### Plan 01-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `relay/package.json` | Node.js project config with ws, apns2, pino dependencies | VERIFIED | name=keyauth-relay, type=module, engines.node>=22, all three deps present at expected versions |
| `relay/src/types.ts` | Shared type definitions for MessageEnvelope, Room, Client, ErrorCode | VERIFIED | Exports all 4 types; 22 lines, substantive |
| `relay/src/logger.ts` | Pino structured JSON logger instance | VERIFIED | Imports pino, exports default logger with LOG_LEVEL env var support |
| `relay/src/rooms.ts` | RoomManager class with join/leave/forward/evict/getRoom/clientCount/hasIosClient | VERIFIED | All 9 methods present; 83 lines; TTL eviction comment present |
| `relay/src/rooms.test.ts` | Tests for room join, leave, forward, capacity, TTL eviction (min 50 lines) | VERIFIED | 183 lines; 15 tests; all pass |

### Plan 01-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `relay/src/apns.ts` | APNs client wrapper with createApnsClient and sendWakeupPush | VERIFIED | Exports createApnsClient, sendWakeupPush, getApnsClient, _setApnsClientForTesting, _resetForTesting; 85 lines |
| `relay/src/handlers.ts` | Message parsing, join/register_token/ping handling, opaque forwarding | VERIFIED | Exports parseMessage and handleMessage; switch dispatch with join/register_token/ping/default(forward); 97 lines |
| `relay/src/apns.test.ts` | Tests for APNs client initialization, push sending, error handling (min 30 lines) | VERIFIED | 150 lines; 10 tests; all pass |
| `relay/src/handlers.test.ts` | Tests for message parsing, routing, error responses (min 50 lines) | VERIFIED | 321 lines; 15 tests; all pass |

### Plan 01-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `relay/src/index.ts` | Entry point: HTTP+WebSocket server, /health, upgrade handler, graceful shutdown (min 60 lines) | VERIFIED | 95 lines; all required patterns present; exports server, wss, roomManager, shutdown |
| `relay/src/server.test.ts` | Integration tests for health endpoint, WebSocket upgrade, room capacity rejection (min 50 lines) | VERIFIED | 301 lines; 11 tests (server.test.ts grep shows 12 `it(` calls, 11 unique tests); all pass |

---

## Key Link Verification

### Plan 01-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `relay/src/rooms.ts` | `relay/src/types.ts` | `import type { Room, Client } from './types.js'` | VERIFIED | Line 2 of rooms.ts: `import type { Room, Client } from './types.js'` |
| `relay/src/rooms.ts` | `relay/src/logger.ts` | `import logger from './logger.js'` | VERIFIED | Line 3 of rooms.ts: `import logger from './logger.js'` |

### Plan 01-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `relay/src/apns.ts` | apns2 library | `import { ApnsClient, Notification } from 'apns2'` | VERIFIED | Line 1 of apns.ts — note: Errors not imported (not needed; error shape accessed via `.reason` property cast) |
| `relay/src/handlers.ts` | `relay/src/apns.ts` | `sendWakeupPush` call | VERIFIED | Line 5: `import { sendWakeupPush } from './apns.js'`; lines 89: `sendWakeupPush(room.deviceToken, roomId, requestId)` |
| `relay/src/handlers.ts` | `relay/src/rooms.ts` | `RoomManager.join/forward/hasIosClient` | VERIFIED | Line 4: `import { RoomManager } from './rooms.js'`; roomManager.join (line 50), roomManager.forward (line 81), roomManager.hasIosClient (line 85) all called |

### Plan 01-03 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `relay/src/index.ts` | `relay/src/rooms.ts` | `new RoomManager()` and getRoom/clientCount | VERIFIED | Line 5: `import { RoomManager } from './rooms.js'`; line 12: `new RoomManager(roomTtlMinutes)` |
| `relay/src/index.ts` | `relay/src/handlers.ts` | `handleMessage` call in ws.on('message') | VERIFIED | Line 6: `import { handleMessage } from './handlers.js'`; line 66: `handleMessage(raw, ws, roomId, clientId, roomManager)` |
| `relay/src/index.ts` | `relay/src/apns.ts` | `createApnsClient()` at startup | VERIFIED | Line 7: `import { createApnsClient } from './apns.js'`; line 16: `createApnsClient()` in try/catch |
| `relay/src/index.ts` | `relay/src/logger.ts` | `import logger` | VERIFIED | Line 8: `import logger from './logger.js'` |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RELAY-01 | 01-01 | WebSocket relay server accepts connections and routes messages between paired devices via room IDs | SATISFIED | RoomManager.forward() routes messages between clients in the same room; index.ts wires WebSocket connections to RoomManager; 51 tests pass including server integration Tests 5-9 |
| RELAY-02 | 01-02 | Relay sends APNs alert push to wake iOS app when code is requested and iOS client is absent | SATISFIED | handlers.ts lines 85-93: hasIosClient check + sendWakeupPush call; apns.ts constructs alert push with "KeyAuth"/"Approve 2FA request"; 10 APNs tests + handler Tests 12-13 pass |
| RELAY-03 | 01-03 | Relay server runs on Railway with automatic TLS termination | BLOCKED | index.ts uses process.env.PORT (Railway-compatible), listens on plain ws:// (Railway TLS terminates at proxy per D-18), no manual certificate code. BUT no Railway project has been created. STATE.md confirms blocker. No railway.json/Dockerfile/Procfile exists. |
| RELAY-04 | 01-03 | Relay exposes /health endpoint for uptime monitoring | SATISFIED | index.ts lines 22-31: GET /health returns 200 JSON with {status:"ok", uptime, timestamp}; server.test.ts Tests 1-2 confirm; Tests 3-4 confirm 404 for other paths/methods |
| RELAY-05 | 01-02 | Relay manages APNs JWT token rotation (refresh at 45-minute intervals) | SATISFIED (via library) | apns2 library handles rotation automatically at 55-minute intervals (apns.js line 12: `RESET_TOKEN_INTERVAL_MS = 55 * 60 * 1000`). Note: REQUIREMENTS.md says 45 minutes; library uses 55 minutes. Both are well within Apple's 60-minute JWT expiry. No custom rotation code needed or present. |
| RELAY-06 | 01-01, 01-03 | Relay enforces max 2 clients per room | SATISFIED | index.ts line 48: `roomManager.clientCount(roomId) >= 2` → HTTP 403; rooms.ts clientCount(); server.test.ts Test 8 verifies third client rejected; rooms.test.ts Test 14 verifies clientCount accuracy |

**Orphaned requirements:** None. All 6 Phase 1 requirements (RELAY-01 through RELAY-06) are claimed in plan frontmatter and verified above.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TODO/FIXME/PLACEHOLDER comments, no empty implementations, no stub return values, no console.log-only handlers found in any relay source file.

---

## Human Verification Required

### 1. Railway Deployment Live Check

**Test:** Create a Railway project (`railway login && railway init` in `relay/`), set env vars (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY as base64, APNS_ENVIRONMENT=sandbox for testing), deploy (`railway up`), then run `curl https://<railway-url>/health`
**Expected:** HTTP 200 with `{"status":"ok","uptime":<number>,"timestamp":"<ISO string>"}`
**Why human:** Requires Railway account, project creation, and live deployment — cannot be verified from the codebase alone

### 2. Two-Tab WebSocket Routing Over wss://

**Test:** With the Railway deployment live, open two browser tabs and connect both to `wss://<railway-url>/?roomId=<uuid>`, send a message from Tab 1
**Expected:** Tab 2 receives the message; Tab 1 does not receive its own message back; room capacity (third tab rejected with error)
**Why human:** Requires a live Railway deployment and external wss:// connectivity

### 3. APNs Push Delivery

**Test:** Register a real iOS device token by sending `{v:1,type:"join",id:"<uuid>",payload:{deviceToken:"<real-token>"}}` from one client, then send a non-join message from a second client with no iOS client connected
**Expected:** A real iOS device receives an APNs alert push titled "KeyAuth" with body "Approve 2FA request" containing roomId and requestId in the data payload
**Why human:** Requires a real APNs p8 key (APNS_KEY env var), a physical iOS device, and a live Railway deployment. Cannot be simulated in tests without real credentials.

---

## Gaps Summary

The relay server codebase is complete and functionally correct. All 51 automated tests pass (15 rooms + 10 APNs + 15 handlers + 11 server integration). TypeScript type checking passes with zero errors. All key links are wired. All anti-pattern checks are clean.

The single gap is **operational, not code**: Phase 1's goal states "A live Railway deployment routes WebSocket messages" — this requires a provisioned Railway project. The code is ready to deploy (PORT env var, /health endpoint, tsx start script, no build step required), but the Railway project has never been created.

The STATE.md blocker confirms this explicitly: "Railway project must be created and CLI configured before Phase 1 deploy step." RELAY-03 ("Relay server runs on Railway") is satisfied in design and implementation pattern, but not in the deployed state.

All three human verification items (Railway live check, two-tab routing, APNs push delivery) depend on resolving this single Railway deployment blocker.

---

_Verified: 2026-04-15T06:41:21Z_
_Verifier: Claude (gsd-verifier)_
