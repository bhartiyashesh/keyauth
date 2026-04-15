---
status: issues_found
phase: 01
depth: standard
files_reviewed: 12
findings:
  critical: 2
  warning: 6
  info: 4
  total: 12
---

# Code Review Report: KeyAuth Relay Server

## EXECUTIVE SUMMARY

- Files analyzed: 12 files (~680 lines of code)
- Overall quality score: 6.5/10
- Critical issues: 2
- Security risk level: High
- Recommendation: Revise

## ANALYSIS SCOPE

- Files reviewed: relay/src/types.ts, relay/src/logger.ts, relay/src/rooms.ts, relay/src/rooms.test.ts, relay/src/apns.ts, relay/src/apns.test.ts, relay/src/handlers.ts, relay/src/handlers.test.ts, relay/src/index.ts, relay/src/server.test.ts, relay/package.json, relay/tsconfig.json
- Review date: 2026-04-15
- Analysis depth: Standard
- Focus areas: Security, Bugs, Code Quality, Type Safety

---

## CRITICAL ISSUES (Priority: Immediate)

### Issue 1: Room ID Spoofing / Client Impersonation via roomId

- **Location**: relay/src/index.ts:38-58, relay/src/handlers.ts:47-52
- **Category**: Security Vulnerability
- **Risk Level**: Critical
- **Description**: The `roomId` is taken directly from the WebSocket upgrade URL query string (`?roomId=<value>`) without any validation, sanitization, or authorization check. Any client that knows (or guesses) a valid room ID can join that room. There is no shared secret, token, or ownership proof. For a 2FA relay this is a direct path to a man-in-the-middle attack: a malicious actor connects to an existing auth room and receives the forwarded key code.
- **Impact**: An attacker can join any room and receive forwarded authentication messages. The 2-client cap (RELAY-06) only partially mitigates this; if the attacker connects before the legitimate iOS client it will occupy the slot and block the real device, or if the cap check has a race (see Issue 2) it may be bypassed entirely.
- **Code Reference**:
  ```typescript
  // relay/src/index.ts:39-44
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const roomId = url.searchParams.get('roomId');
  if (!roomId) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }
  ```
- **Recommendation**: Rooms should be created with a server-generated, high-entropy token (e.g. a 128-bit random hex string). The initiating desktop client should receive this token and share it out-of-band with the iOS app (e.g. via QR code). Both sides then present the same token to join. Additionally, consider adding an HMAC or short-lived signed JWT so the server can verify the join without trusting the raw token alone.

---

### Issue 2: Race Condition in Room Capacity Check (RELAY-06)

- **Location**: relay/src/index.ts:48-57
- **Category**: Bug (Race Condition)
- **Risk Level**: Critical
- **Description**: The capacity check (`clientCount(roomId) >= 2`) and the subsequent WebSocket upgrade/connection happen in two separate non-atomic steps. Between the `clientCount` check and the `wss.handleUpgrade` completion, a second concurrent upgrade request for the same room can pass the check (both see count=1), and both upgrades complete, resulting in 3+ clients in a room that is supposed to be capped at 2. Node.js is single-threaded but the `handleUpgrade` callback is asynchronous; two near-simultaneous upgrade requests will both read `clientCount=1` before either has completed joining.
- **Impact**: The 2-client security boundary can be bypassed. A room meant for exactly one desktop and one mobile device can have a third party snoop on forwarded messages.
- **Code Reference**:
  ```typescript
  // relay/src/index.ts:48-57
  if (roomManager.clientCount(roomId) >= 2) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    const clientId = crypto.randomUUID();
    wss.emit('connection', ws, req, roomId, clientId);
    // <-- clientId not added to room until 'join' message arrives
  });
  ```
- **Additional Detail**: The `clientCount` check uses RoomManager state, but a newly upgraded client is not added to the room until it sends a `join` message. This means three simultaneous upgrade requests will all see `clientCount=0` and all pass. The enforcement gate relies on application-layer messages, not the transport upgrade.
- **Recommendation**: Track in-flight upgrade reservations at the transport layer. Before calling `handleUpgrade`, atomically increment a per-room pending counter and check `current + pending >= 2`. Decrement on connection error or when the `join` message is received. Alternatively, add the client to the room immediately upon upgrade completion (before waiting for a `join` message) and enforce the cap there.

---

## IMPORTANT ISSUES (Priority: High)

### Issue 3: No roomId Format Validation — Path Traversal / Log Injection Risk

- **Location**: relay/src/index.ts:39-44, relay/src/rooms.ts:15-27
- **Category**: Security Vulnerability / Input Validation
- **Risk Level**: High
- **Description**: `roomId` is accepted verbatim from the URL query string and is passed directly into log output (`logger.info({ roomId }, ...)`) and used as a Map key. There is no length cap, character allowlist, or format check. This enables log injection (a roomId containing newlines or JSON-breaking characters can corrupt structured log output) and denial-of-service via extremely long room IDs or room ID flooding.
- **Impact**: An attacker can pollute log streams, potentially cause log parsing pipelines to misinterpret entries, or exhaust memory by creating unbounded numbers of rooms (one per unique roomId).
- **Recommendation**: Validate roomId against a strict allowlist pattern (e.g. `/^[a-zA-Z0-9_-]{8,64}$/`) and return HTTP 400 for non-conforming values. Pino's serialization does escape special characters but the allowlist also prevents memory exhaustion.

---

### Issue 4: Unlimited Room Creation / No Rate Limiting

- **Location**: relay/src/index.ts:37-58, relay/src/rooms.ts:15-27
- **Category**: Security Vulnerability (Denial of Service)
- **Risk Level**: High
- **Description**: Any WebSocket client can create an unlimited number of rooms simply by connecting with different `roomId` values. The eviction loop runs every 5 minutes and only clears rooms with 0 clients older than the TTL (30 minutes by default). An attacker can create tens of thousands of rooms per second, filling server memory before eviction runs.
- **Impact**: Memory exhaustion leading to server crash or OOM kill.
- **Code Reference**:
  ```typescript
  // relay/src/rooms.ts:17-20
  if (!room) {
    room = { id: roomId, clients: new Map(), lastActivity: Date.now() };
    this.rooms.set(roomId, room);
  }
  ```
- **Recommendation**: Enforce a global room cap (`MAX_ROOMS` env var, default ~10,000). Reject room creation once the cap is hit. Also add per-IP connection rate limiting at the HTTP upgrade layer (e.g. a sliding window counter in a Map keyed by IP, cleared periodically).

---

### Issue 5: `ws.on('error')` Does Not Prevent Double-Leave

- **Location**: relay/src/index.ts:69-78
- **Category**: Bug
- **Risk Level**: High
- **Description**: Both the `close` event and the `error` event call `roomManager.leave(roomId, clientId)`. In the `ws` library, an error is typically followed by a `close` event. This means `leave` is called twice for the same clientId on an error. While `leave` itself is safe (it calls `Map.delete` which is idempotent), the double log emission is noisy and the pattern is fragile if future code in `leave` is not idempotent.
- **Code Reference**:
  ```typescript
  ws.on('close', () => {
    roomManager.leave(roomId, clientId); // called first on error+close
    log.info('WebSocket connection closed');
  });
  ws.on('error', (err) => {
    log.error({ err }, 'WebSocket error');
    roomManager.leave(roomId, clientId); // called again before close fires
  });
  ```
- **Recommendation**: Remove the `roomManager.leave` call from the `error` handler and keep it only in the `close` handler (which fires after errors). Alternatively, use a `joined` boolean flag per connection and call `leave` only once.

---

### Issue 6: `parseMessage` Accepts Any JSON Object Shape (Missing Payload Validation)

- **Location**: relay/src/handlers.ts:8-16
- **Category**: Security Vulnerability / Type Safety
- **Risk Level**: High
- **Description**: `parseMessage` validates only `v`, `type`, and `id`, and then casts the entire parsed object to `MessageEnvelope`. The `payload` field is typed as `Record<string, unknown>` but no shape check is performed. The `payload` field is never asserted to be an object — if `payload` is missing, `undefined`, or a primitive, the downstream code (`msg.payload.deviceToken as string | undefined`) will throw a runtime TypeError.
- **Code Reference**:
  ```typescript
  // relay/src/handlers.ts:8-16
  const msg = JSON.parse(raw);
  if (msg.v !== 1 || !msg.type || !msg.id) return null;
  return msg as MessageEnvelope;
  // ...
  // relay/src/handlers.ts:49
  const deviceToken = msg.payload.deviceToken as string | undefined;
  // ^ throws if msg.payload is null or a non-object primitive
  ```
- **Recommendation**: Add `typeof msg.payload !== 'object' || msg.payload === null || Array.isArray(msg.payload)` to the null-guard in `parseMessage`. Return `null` for invalid payload shapes. This is also a correctness issue: a crafted message with `"payload": null` will pass `parseMessage` and crash `handleMessage`.

---

### Issue 7: `APNS_KEY_PATH` File Read is Synchronous and Blocking

- **Location**: relay/src/apns.ts:19
- **Category**: Code Quality / Performance
- **Risk Level**: Warning
- **Description**: `fs.readFileSync` is used to read the APNs private key. While this occurs only at startup, it blocks the event loop during initialization. On slow file systems or containerized environments with mounted secrets this can delay startup noticeably and, more importantly, introduces a non-graceful failure mode (throws synchronously, uncaught by the `try/catch` in `index.ts`... actually it is caught, but the blocking nature is still an anti-pattern for a server).
- **Recommendation**: Not a blocker, but prefer `fs.promises.readFile` and make `createApnsClient` async to align with Node.js best practices.

---

## MINOR ISSUES (Priority: Medium)

### Issue 8: `apnsClient` Module-Level Singleton Creates Test Isolation Hazard

- **Location**: relay/src/apns.ts:5
- **Category**: Code Quality / Testability
- **Risk Level**: Info
- **Description**: The module-level `apnsClient` variable is mutable shared state. The test file correctly uses `_resetForTesting()` and `_setApnsClientForTesting()`, but these are exported from production code, which is an anti-pattern. If module caching is not correctly cleared between test runs (especially with `import()` caching in Node.js ESM), test state can leak between test files.
- **Recommendation**: Encapsulate APNs client in a class or use dependency injection (pass the client as a parameter to `sendWakeupPush`) instead of relying on module-level state and test-only backdoor exports.

---

### Issue 9: `hardcoded` APNs Topic `com.keyauth.app`

- **Location**: relay/src/apns.ts:32
- **Category**: Code Quality / Configuration
- **Risk Level**: Info
- **Description**: The APNs `defaultTopic` is hardcoded to `'com.keyauth.app'`. If the iOS bundle ID changes or the relay is reused for another app, this requires a code change rather than a configuration change.
- **Code Reference**:
  ```typescript
  defaultTopic: 'com.keyauth.app',
  ```
- **Recommendation**: Read from `process.env.APNS_BUNDLE_ID` with a fallback, and throw or warn if not set in production environments.

---

### Issue 10: `shutdown()` Does Not Close Active WebSocket Connections

- **Location**: relay/src/index.ts:85-90
- **Category**: Bug / Resource Management
- **Risk Level**: Warning
- **Description**: The `shutdown` function calls `wss.close()` and `server.close()`, but `wss.close()` only stops accepting new connections — it does not terminate existing open WebSocket connections. Active connections will keep the `server.close()` callback from firing until clients disconnect naturally, potentially causing the process to hang during a graceful shutdown (e.g. SIGTERM from Railway/container orchestrator).
- **Code Reference**:
  ```typescript
  function shutdown() {
    logger.info('Shutting down relay server');
    roomManager.shutdown();
    wss.close();   // does not close existing connections
    server.close(); // will not complete until all connections close
  }
  ```
- **Recommendation**: Iterate over `wss.clients` and call `ws.terminate()` (or `ws.close()`) on each before calling `wss.close()`.

---

### Issue 11: No Maximum Message Size Enforcement

- **Location**: relay/src/index.ts:35, relay/src/handlers.ts:8-16
- **Category**: Security Vulnerability (DoS)
- **Risk Level**: Warning
- **Description**: The `WebSocketServer` is created without a `maxPayload` option. The default in the `ws` library is 100 MB. A client can send a single 100 MB message that will be buffered in memory before `handleMessage` is called. Since messages are forwarded opaquely (`roomManager.forward(roomId, clientId, raw)`), both the incoming and outgoing buffers are at risk.
- **Code Reference**:
  ```typescript
  const wss = new WebSocketServer({ noServer: true });
  // missing: maxPayload option
  ```
- **Recommendation**: Set `maxPayload` to a sensible limit matching the actual maximum message size (e.g. 64 KB for encrypted key payloads): `new WebSocketServer({ noServer: true, maxPayload: 65536 })`.

---

### Issue 12: `server.test.ts` Calls `server.close()` Twice in `afterEach`

- **Location**: relay/src/server.test.ts:136-147
- **Category**: Test Quality
- **Risk Level**: Info
- **Description**: The `afterEach` block calls `testServer.shutdown()` (which internally calls `server.close()`) and then calls `testServer.server.close(() => resolve())` again. Calling `server.close()` on an already-closed server emits an error event or silently no-ops depending on Node.js version. While this does not affect test outcomes today, it is fragile.
- **Code Reference**:
  ```typescript
  afterEach(async () => {
    // ...
    testServer.shutdown();            // calls server.close() internally
    await new Promise<void>((resolve) => {
      testServer.server.close(() => resolve()); // second close()
    });
  });
  ```
- **Recommendation**: Remove the second `server.close()` call and add a `once('close', ...)` listener in the `shutdown()` helper, or resolve the promise based on the shutdown completing.

---

## QUALITY METRICS

- **Cyclomatic Complexity**: Low-to-Medium. `handleMessage` has a switch with 4 branches; all functions are small. Acceptable.
- **Code Duplication**: The server setup code in `index.ts` is duplicated nearly verbatim in `server.test.ts` (`createTestServer`). Approximately 60 lines duplicated.
- **Documentation Coverage**: Minimal inline comments; no JSDoc. The code is readable but lacks contract documentation on public functions.
- **Naming Convention Compliance**: Consistent; no violations.
- **Test Coverage**: High for happy paths. Missing: payload=null crash (Issue 6), race condition (Issue 2), memory exhaustion (Issue 4), shutdown hang (Issue 10).

## SECURITY ASSESSMENT

- **Authentication**: Fail — no room join authentication (Issue 1)
- **Authorization**: Fail — any client can join any room with a known ID (Issue 1)
- **Input Validation**: Fail — roomId not validated, payload shape not validated (Issues 3, 6)
- **Data Sanitization**: Pass — messages are forwarded opaquely without modification
- **Sensitive Data Handling**: Pass — device tokens are partially masked in logs
- **Error Information Disclosure**: Pass — errors return codes, not stack traces

## PERFORMANCE ANALYSIS

- **Algorithm Efficiency**: Optimal — O(n) forward loop where n <= 2 in practice
- **Database Interaction**: Not applicable
- **Memory Management**: Concerning — no room cap, no message size limit (Issues 4, 11)
- **Resource Usage**: Acceptable at low scale; problematic under adversarial load

## POSITIVE PATTERNS OBSERVED

- The opaque forward design (D-03) is correctly implemented: `handlers.ts` does not inspect or modify forwarded message payloads.
- Error responses follow the documented D-02 envelope format consistently.
- APNs push failures are non-fatal and do not interrupt message forwarding — correctly designed.
- Room TTL eviction is properly implemented with the `setInterval` timer cleaned up in `shutdown()`.
- `crypto.randomUUID()` is used for all server-generated IDs — no predictable IDs.
- Pino structured logging throughout provides good observability.
- Test suite is well-organized with isolated per-test server instances and proper `beforeEach`/`afterEach` cleanup.

## RECOMMENDATIONS BY PRIORITY

### Must Fix Before Deployment

1. **Issue 1 (Critical)**: Implement room join authorization — shared secret, signed token, or HMAC-verified room codes to prevent unauthorized room access.
2. **Issue 2 (Critical)**: Fix the race condition in the room capacity check by moving client registration to the upgrade completion step, before any application-layer message is required.
3. **Issue 6 (High)**: Add `payload` shape validation in `parseMessage` to prevent a null/primitive payload from crashing `handleMessage`.
4. **Issue 11 (Warning)**: Set `maxPayload` on the `WebSocketServer` to prevent memory exhaustion from oversized messages.

### Should Fix Soon

1. **Issue 3 (High)**: Add roomId format validation (allowlist regex + length cap) to prevent log injection and unbounded Map key growth.
2. **Issue 4 (High)**: Add a global room count cap and per-IP rate limiting on WebSocket upgrades.
3. **Issue 5 (High)**: Remove the double `roomManager.leave` call from the error handler — keep leave only in the close handler.
4. **Issue 10 (Warning)**: Fix graceful shutdown to terminate active WebSocket connections before calling `server.close()`.

### Consider for Future Improvement

1. **Issue 7 (Info)**: Convert `fs.readFileSync` to `fs.promises.readFile` in APNs client initialization.
2. **Issue 8 (Info)**: Refactor APNs client from module-level singleton to dependency injection to eliminate test-only backdoor exports.
3. **Issue 9 (Info)**: Move APNs bundle ID to `APNS_BUNDLE_ID` environment variable.
4. **Issue 12 (Info)**: Fix double `server.close()` call in test teardown.

## LEARNING OPPORTUNITIES

- For relay servers handling authentication flows, the standard pattern is to have the server generate the room/session ID and return it to the initiating party (never accept client-supplied session identifiers for privileged operations).
- The `ws` library's `maxPayload` option is often overlooked but is a first-line defence against memory exhaustion — it should be set in every production `WebSocketServer` constructor.
- When using Node.js ESM with module-level mutable state, `import()` caching means `_resetForTesting` helpers can fail silently if the module is not re-imported. Consider using explicit dependency injection over module-level singletons for testability.
