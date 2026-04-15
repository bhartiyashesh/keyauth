# Phase 1: Relay Server - Research

**Researched:** 2026-04-15
**Domain:** Node.js WebSocket relay server with APNs push integration, deployed to Railway
**Confidence:** HIGH

## Summary

Phase 1 builds a Node.js WebSocket relay server that acts as a dumb pipe between two paired devices (Chrome extension and iOS app) using room-based routing. The relay has no database, no persistent storage, and no knowledge of message contents beyond `join` and `register_token` types. It also integrates with Apple Push Notification service (APNs) to wake the iOS app when it is not connected.

The technology decisions are locked: Node.js 22 LTS, `ws` 8.20.x for WebSocket, `apns2` 12.2.x for APNs, `tsx` 4.x as the runtime, deployed to Railway with TLS termination handled by the platform. The relay lives in a `relay/` directory at the project root. No HTTP framework is needed -- the built-in `http` module handles the `/health` endpoint and WebSocket upgrade.

**Primary recommendation:** Build the relay as a single `src/index.ts` entry point with extracted modules for room management, APNs client, and message handling. Use `pino` for structured JSON logging. Test with two browser tabs before any client code exists.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Messages use a versioned JSON envelope: `{ v: 1, type: string, id: uuid, payload: {...} }`
- **D-02:** Errors use structured type field: `{ type: 'error', code: 'room_full', message: '...' }`
- **D-03:** Relay only understands `join` and `register_token` message types -- everything else is forwarded as opaque encrypted blobs to the other client in the room
- **D-04:** Code requests include a UUID correlation ID (requestId) echoed back in responses
- **D-05:** E2E encryption using tweetnacl (X25519 key exchange at pairing, secretbox for messages) -- relay NEVER sees plaintext TOTP codes. This upgrades the original TLS-only decision.
- **D-06:** Rooms persist in memory with a TTL -- reconnecting clients always find their room
- **D-07:** TTL eviction cleans up rooms with no clients after a configurable period
- **D-08:** Max 2 clients per room (one extension, one iOS)
- **D-09:** iOS device token sent during the `join` message: `{ type: 'join', roomId, deviceToken }`
- **D-10:** Relay sends APNs alert push ONLY when a message arrives and no iOS client is connected to the room
- **D-11:** Alert push type mandatory (not silent) -- silent pushes are throttled at ~3/hour by Apple
- **D-12:** APNs uses p8 JWT auth via apns2 library; JWT token rotated at 45-minute intervals
- **D-13:** APNs p8 key file added to .gitignore
- **D-14:** Relay server lives in `relay/` directory at project root (monorepo alongside iOS app)
- **D-15:** Structured JSON logging (timestamp, level, roomId) for Railway log searchability
- **D-16:** Minimal env vars: `PORT` (Railway), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`
- **D-17:** Node.js 22 LTS runtime, ws 8.20.x WebSocket library, apns2 12.2.x for push
- **D-18:** Railway handles TLS termination -- relay listens on plain ws:// internally

### Claude's Discretion
- Room creation mechanism (likely implicit on first join)
- Room TTL duration (suggest 30-60 minutes)
- Ping/pong strategy (application-level vs protocol-level)
- Health endpoint response format

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RELAY-01 | WebSocket relay server accepts connections and routes messages between paired devices via room IDs | ws 8.20.x WebSocket.Server with `handleUpgrade` on Node.js built-in `http` server; in-memory `Map<string, Room>` for room routing |
| RELAY-02 | Relay sends APNs alert push to wake iOS app when code is requested and iOS client is absent | apns2 12.2.x `Notification` class with alert payload; check room for iOS client presence before sending push |
| RELAY-03 | Relay server runs on Railway with automatic TLS termination | Railway injects PORT env var, terminates TLS at proxy layer; server listens on plain http/ws internally |
| RELAY-04 | Relay exposes /health endpoint for uptime monitoring | Built-in `http` module responds 200 to GET /health; Railway checks this during deploy |
| RELAY-05 | Relay manages APNs JWT token rotation (refresh at 45-minute intervals) | apns2 library auto-rotates JWT tokens at 55-minute intervals internally (verified in source code); no manual rotation needed |
| RELAY-06 | Relay enforces max 2 clients per room | Check `room.clients.size >= 2` before accepting new WebSocket connection; send error and close if full |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ws | 8.20.0 | WebSocket server | 49M weekly downloads, RFC 6455 compliant, zero runtime deps, passes Autobahn test suite. The only serious WS server for Node.js. |
| apns2 | 12.2.0 | APNs HTTP/2 push client | TypeScript-native, p8/JWT only (enforces best practice), auto-rotates JWT at 55min intervals, HTTP/2 persistent connection |
| pino | 9.x | Structured JSON logging | 5-8x faster than winston, outputs JSON by default (ideal for Railway log search), lightweight |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tsx | 4.21.x | TypeScript runner | Production runtime -- JIT strips types via esbuild, zero-config, no build step needed for a small relay |
| @types/ws | 8.18.x | TypeScript types for ws | Always -- required for type-safe WebSocket handling |
| @types/node | 22.x | Node.js type definitions | Always -- required for http, process, Buffer types |
| typescript | 5.x | Type checking | Dev dependency only -- `tsc --noEmit` for type checking, tsx handles runtime |
| pino-pretty | 13.x | Human-readable dev logs | Dev only -- pipe output through pino-pretty for local development |

### Not Needed
| Instead of | Could Use | Why Not |
|------------|-----------|---------|
| Express | Built-in `http` module | Relay has exactly 2 HTTP concerns: /health and WS upgrade. Express adds 50KB for routing a 5-line server handles. |
| Socket.io | ws | Protocol-incompatible with native iOS `URLSessionWebSocketTask` and browser `WebSocket` API. Requires its own client library. |
| uuid npm | `crypto.randomUUID()` | Node.js 22 has built-in v4 UUID generation. 3x faster, zero dependencies. Only generates UUIDv4, which is all we need. |
| winston | pino | Winston is 5-8x slower. Pino outputs structured JSON by default which is exactly what Railway log search needs. |
| dotenv | -- | Railway injects env vars directly. For local dev, pass them via CLI or a shell script. |

**Installation:**
```bash
mkdir relay && cd relay
npm init -y
npm install ws apns2 pino
npm install -D tsx typescript @types/ws @types/node pino-pretty
```

## Architecture Patterns

### Recommended Project Structure
```
relay/
├── src/
│   ├── index.ts          # Entry point: creates HTTP server, WS server, starts listening
│   ├── rooms.ts          # Room manager: Map<string, Room>, join/leave/forward/evict
│   ├── apns.ts           # APNs client wrapper: init, sendWakeup, error handling
│   ├── handlers.ts       # Message handlers: parseMessage, handleJoin, handleRegisterToken, forward
│   ├── logger.ts         # Pino logger instance with base config
│   └── types.ts          # Shared types: Room, Client, MessageEnvelope, ErrorCode
├── package.json
├── tsconfig.json
├── .gitignore            # includes *.p8, .env, node_modules, dist
└── .nvmrc                # "22"
```

### Pattern 1: Manual WebSocket Upgrade with Room Routing
**What:** Use `noServer` mode on `ws.WebSocketServer` and handle the HTTP upgrade manually to extract roomId from the URL query string before accepting the connection.
**When to use:** Always -- this gives control over rejecting connections before the WebSocket handshake completes (e.g., room full, invalid roomId).
**Example:**
```typescript
// Source: ws docs - https://github.com/websockets/ws/blob/master/doc/ws.md
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';

const server = createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: Date.now() }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const roomId = url.searchParams.get('roomId');

  if (!roomId) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }

  // Check room capacity before upgrade
  const room = rooms.get(roomId);
  if (room && room.clients.size >= 2) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req, roomId);
  });
});
```

### Pattern 2: Room Manager with TTL Eviction
**What:** A `RoomManager` class wrapping a `Map<string, Room>` that handles join, leave, forward, and periodic TTL cleanup.
**When to use:** Always -- centralizes room lifecycle logic.
**Example:**
```typescript
interface Client {
  ws: WebSocket;
  deviceToken?: string;  // APNs token, set during join
}

interface Room {
  id: string;
  clients: Map<string, Client>;  // key: unique client ID
  deviceToken?: string;           // iOS device token for APNs
  lastActivity: number;           // timestamp for TTL
}

class RoomManager {
  private rooms = new Map<string, Room>();
  private ttlMs: number;
  private timer: NodeJS.Timeout;

  constructor(ttlMinutes: number = 30) {
    this.ttlMs = ttlMinutes * 60 * 1000;
    // Sweep every 5 minutes
    this.timer = setInterval(() => this.evict(), 5 * 60 * 1000);
  }

  join(roomId: string, clientId: string, ws: WebSocket, deviceToken?: string): Room {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = { id: roomId, clients: new Map(), lastActivity: Date.now() };
      this.rooms.set(roomId, room);
    }
    room.clients.set(clientId, { ws, deviceToken });
    if (deviceToken) room.deviceToken = deviceToken;
    room.lastActivity = Date.now();
    return room;
  }

  leave(roomId: string, clientId: string): void {
    const room = this.rooms.get(roomId);
    if (!room) return;
    room.clients.delete(clientId);
    room.lastActivity = Date.now();
    // Do NOT delete empty rooms -- TTL handles cleanup
  }

  forward(roomId: string, senderClientId: string, data: string): void {
    const room = this.rooms.get(roomId);
    if (!room) return;
    room.lastActivity = Date.now();
    for (const [id, client] of room.clients) {
      if (id !== senderClientId && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(data);
      }
    }
  }

  private evict(): void {
    const now = Date.now();
    for (const [id, room] of this.rooms) {
      if (room.clients.size === 0 && now - room.lastActivity > this.ttlMs) {
        this.rooms.delete(id);
      }
    }
  }
}
```

### Pattern 3: Message Envelope Parsing
**What:** Parse incoming messages against the versioned envelope schema, handle `join` and `register_token` at the relay, forward everything else.
**When to use:** Every incoming message goes through this.
**Example:**
```typescript
interface MessageEnvelope {
  v: number;
  type: string;
  id: string;      // UUID correlation ID
  payload: Record<string, unknown>;
}

function parseMessage(raw: string): MessageEnvelope | null {
  try {
    const msg = JSON.parse(raw);
    if (msg.v !== 1 || !msg.type || !msg.id) return null;
    return msg as MessageEnvelope;
  } catch {
    return null;
  }
}

// In connection handler:
ws.on('message', (data) => {
  const raw = data.toString();
  const msg = parseMessage(raw);

  if (!msg) {
    ws.send(JSON.stringify({
      v: 1, type: 'error', id: crypto.randomUUID(),
      payload: { code: 'invalid_message', message: 'Malformed message envelope' }
    }));
    return;
  }

  switch (msg.type) {
    case 'join':
      handleJoin(roomId, clientId, ws, msg);
      break;
    case 'register_token':
      handleRegisterToken(roomId, clientId, msg);
      break;
    case 'ping':
      ws.send(JSON.stringify({ v: 1, type: 'pong', id: msg.id, payload: {} }));
      break;
    default:
      // Opaque forward -- relay does not inspect payload
      roomManager.forward(roomId, clientId, raw);
      break;
  }
});
```

### Anti-Patterns to Avoid
- **Using Express for the HTTP layer:** The relay has exactly one GET endpoint (/health) and a WebSocket upgrade. Express adds unnecessary weight and complexity.
- **Storing messages for offline delivery:** The relay is NOT a message queue. If the iOS client is absent, send an APNs push. Do not buffer messages.
- **Parsing encrypted payloads:** The relay MUST NOT attempt to decrypt or interpret forwarded messages. It is a dumb pipe. Only `join`, `register_token`, and `ping` types are understood.
- **Using `ws.Server({ port })` directly:** This prevents sharing the HTTP server for /health. Always use `noServer: true` with `handleUpgrade`.
- **Room cleanup on disconnect:** Do NOT delete a room when a client disconnects. The client may reconnect. Use TTL-based eviction instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| APNs HTTP/2 connection + JWT signing | Custom http2 client + jose JWT | apns2 12.2.x | JWT rotation at 55min, HTTP/2 connection pooling, error mapping to Apple codes -- all handled internally |
| UUID generation | uuid npm package | `crypto.randomUUID()` | Built into Node.js 22. Zero deps, 3x faster, cryptographically secure v4 UUIDs |
| Structured JSON logging | `console.log(JSON.stringify(...))` | pino 9.x | Consistent format, child loggers with roomId context, fast serialization, dev-mode pretty printing |
| WebSocket protocol compliance | Raw net.Socket + frame parsing | ws 8.20.x | RFC 6455 framing, masking, close handshake, ping/pong, backpressure -- all edge cases handled |
| APNs JWT token rotation | Manual timer + jwt.sign | apns2 internal rotation | apns2 caches tokens and regenerates at 55min automatically; also resets on `ExpiredProviderToken` error |

**Key insight:** The relay server is intentionally simple. Its complexity comes from protocol edge cases (WebSocket close races, APNs error codes, JWT timing) that libraries handle correctly and custom code handles incorrectly.

## Common Pitfalls

### Pitfall 1: Railway 15-Minute WebSocket Timeout
**What goes wrong:** Railway terminates any WebSocket connection open longer than 15 minutes, regardless of activity. This is a hard limit at Railway's Cloudflare proxy layer.
**Why it happens:** Platform-level timeout, not configurable. Does not exist in local development, so it only surfaces in production.
**How to avoid:** Clients (extension and iOS app -- built in later phases) must implement reconnection. The relay itself does NOT need to handle this -- it just sees a disconnect and cleans up normally. Room TTL ensures the room persists for reconnecting clients.
**Warning signs:** "Works for a while, then stops" at exactly ~15 minute intervals. No `onclose` reconnect handler in clients.

### Pitfall 2: APNs Sandbox vs Production Endpoint Mismatch
**What goes wrong:** Debug iOS builds register with `api.sandbox.push.apple.com`. Production builds (TestFlight/App Store) use `api.push.apple.com`. A relay hardcoded to one endpoint silently fails for the other.
**Why it happens:** Apple uses separate APNs environments for debug and release builds.
**How to avoid:** Accept an `APNS_ENVIRONMENT` env var (default: `production`). Set host to `api.sandbox.push.apple.com` for development, `api.push.apple.com` for production. In apns2, this is the `host` constructor option.
**Warning signs:** Push works in Xcode debug builds but fails on TestFlight, or vice versa.

### Pitfall 3: APNs Device Token Becomes Stale
**What goes wrong:** The stored device token becomes invalid after app reinstall, iOS upgrade, or token rotation. APNs returns `BadDeviceToken (400)` or `Unregistered (410)`.
**Why it happens:** APNs tokens are not permanent. Apple rotates them under undocumented conditions.
**How to avoid:** The relay must handle 400/410 errors from APNs by logging the error and sending an error message back to the requesting client. The iOS app (Phase 2) will re-register its token on every launch.
**Warning signs:** Pushes work initially then stop after days/weeks. APNs errors are swallowed silently.

### Pitfall 4: .p8 Key Committed to Source Control
**What goes wrong:** The APNs signing key is leaked in the git repository.
**Why it happens:** Developer copies .p8 file into project directory and forgets to gitignore before first commit.
**How to avoid:** Add `*.p8` to `.gitignore` BEFORE creating the relay directory. Load key from `APNS_KEY_PATH` env var pointing to a file outside the repo, or from a base64-encoded `APNS_KEY` env var on Railway.
**Warning signs:** `git status` shows a .p8 file. `.gitignore` does not list `*.p8`.

### Pitfall 5: healthcheck.railway.app Not Allowed
**What goes wrong:** Railway uses hostname `healthcheck.railway.app` when performing health checks. If the server inspects the Host header and rejects unknown hosts, deploys will fail.
**Why it happens:** Railway's health check system uses its own hostname, not the service's public URL.
**How to avoid:** The /health handler must not restrict by hostname. Since we use raw `http.createServer` with no host validation, this is the default behavior. Do NOT add host-based routing.
**Warning signs:** Deploys hang in "checking health" state despite the endpoint working when curled directly.

### Pitfall 6: Not Using process.env.PORT
**What goes wrong:** Hardcoding port 3000 or 8080 causes the Railway deploy to fail silently -- the health check never reaches the server.
**Why it happens:** Railway injects the PORT env var dynamically. It is not 3000.
**How to avoid:** Always use `const port = parseInt(process.env.PORT || '3000', 10)`. The fallback is for local dev only.
**Warning signs:** Server starts but Railway reports it as unhealthy. Works on localhost.

## Code Examples

### APNs Alert Push (Verified Pattern)
```typescript
// Source: https://github.com/AndrewBarba/apns2
import { ApnsClient, Notification, Errors } from 'apns2';
import fs from 'fs';

const apnsClient = new ApnsClient({
  team: process.env.APNS_TEAM_ID!,
  keyId: process.env.APNS_KEY_ID!,
  signingKey: fs.readFileSync(process.env.APNS_KEY_PATH!),
  defaultTopic: 'com.keyauth.app',
  host: process.env.APNS_ENVIRONMENT === 'sandbox'
    ? 'api.sandbox.push.apple.com'
    : 'api.push.apple.com',
});

// Handle token errors globally
apnsClient.on(Errors.badDeviceToken, (err) => {
  logger.warn({ deviceToken: err.notification.deviceToken }, 'Bad device token -- client must re-register');
});

apnsClient.on(Errors.unregistered, (err) => {
  logger.warn({ deviceToken: err.notification.deviceToken }, 'Device unregistered -- client must re-pair');
});

async function sendWakeupPush(deviceToken: string, roomId: string, requestId: string): Promise<void> {
  const notification = new Notification(deviceToken, {
    alert: {
      title: 'KeyAuth',
      body: 'Approve 2FA request',
    },
    data: { roomId, requestId },
    aps: { sound: 'default' },
  });

  await apnsClient.send(notification);
}
```

### HTTP + WebSocket Server Setup
```typescript
// Source: ws docs + Railway deployment pattern
import { createServer, IncomingMessage } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
});

const port = parseInt(process.env.PORT || '3000', 10);

const server = createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const roomId = url.searchParams.get('roomId');

  if (!roomId) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }

  const room = roomManager.getRoom(roomId);
  if (room && room.clients.size >= 2) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    const clientId = crypto.randomUUID();
    wss.emit('connection', ws, req, roomId, clientId);
  });
});

server.listen(port, () => {
  logger.info({ port }, 'Relay server listening');
});
```

### package.json Scripts
```json
{
  "name": "keyauth-relay",
  "version": "1.0.0",
  "type": "module",
  "engines": { "node": ">=22" },
  "scripts": {
    "start": "tsx src/index.ts",
    "dev": "tsx watch src/index.ts | pino-pretty",
    "typecheck": "tsc --noEmit",
    "test": "node --test"
  }
}
```

### tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "noEmit": true
  },
  "include": ["src/**/*.ts"]
}
```

## Claude's Discretion Recommendations

### Room Creation: Implicit on First Join
**Recommendation:** Create the room automatically when the first client sends a `join` message with a roomId that does not exist. No separate "create room" API needed.
**Rationale:** The roomId is generated by the Chrome extension (UUID v4) and shared via QR code. The relay does not need to validate or pre-create rooms. This simplifies the protocol -- there is no race condition because both clients join the same roomId independently.

### Room TTL: 30 Minutes
**Recommendation:** Set room TTL to 30 minutes of inactivity (no connected clients).
**Rationale:** 30 minutes is long enough for the iOS app to foreground via APNs push and reconnect (typical APNs delivery is <2 seconds, user tap within seconds to minutes). It is short enough to prevent unbounded memory growth on Railway. Configurable via `ROOM_TTL_MINUTES` env var with 30 as default.

### Ping/Pong: Application-Level JSON Messages
**Recommendation:** Use application-level ping/pong (`{ v: 1, type: 'ping' }` / `{ v: 1, type: 'pong' }`), not WebSocket protocol-level ping frames.
**Rationale:** The Chrome extension service worker needs message-level activity to keep alive (Chrome resets the 30s idle timer on WebSocket message events, not on protocol-level pong frames). Application-level pings are also easier to log and debug. The ws library's `autoPong: true` still handles protocol-level pings from clients that send them, so both layers coexist safely.

### Health Endpoint Format
**Recommendation:** Return `{ "status": "ok", "uptime": <seconds>, "timestamp": "<ISO-8601>" }` with 200 status.
**Rationale:** Railway only checks for HTTP 200 during deploy. The extra fields (uptime, timestamp) are useful for external monitoring tools (e.g., UptimeRobot, Better Uptime) without adding complexity.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| node-apn (TLS sockets) | apns2 (HTTP/2 + JWT) | 2021 (node-apn unmaintained) | Must use apns2 or raw http2; node-apn is dead |
| p12 certificate auth for APNs | p8 token-based JWT auth | Apple recommendation since 2016, enforced by apns2 | No yearly cert rotation; one key covers all apps |
| ts-node for TypeScript execution | tsx (esbuild-based) | 2023-2024 (tsx became dominant) | 25x faster startup, zero config, no tsconfig required for runtime |
| Express for minimal servers | Built-in http module | Always viable, but Express was reflexive | For 1-2 routes, http module is simpler and has zero deps |
| console.log for server logging | pino structured JSON | Industry standard since ~2020 | Machine-parseable logs, child loggers with context, Railway-searchable |

**Deprecated/outdated:**
- **node-apn:** Last meaningful release 2021. Do not use.
- **ts-node:** Still works but tsx is 25x faster and simpler. No reason to choose ts-node for new projects.
- **APNs p12 certificates:** Expire yearly, require manual rotation. Apple recommends p8 exclusively.

## Open Questions

1. **APNs Key Loading: File Path vs Base64 Env Var**
   - What we know: CONTEXT.md specifies `APNS_KEY_PATH` env var. Railway supports both file paths (via volume mounts) and env vars.
   - What's unclear: Whether to read from a file path on disk or decode a base64-encoded env var. The STACK.md research suggests base64 env var.
   - Recommendation: Support both. Check `APNS_KEY` env var first (base64-decoded), fall back to `APNS_KEY_PATH` file read. This supports Railway (env var) and local dev (file path) cleanly.

2. **APNs Environment Toggle**
   - What we know: Debug iOS builds use sandbox APNs, production builds use production APNs.
   - What's unclear: Whether the relay needs to support both simultaneously or toggle via env var.
   - Recommendation: Single `APNS_ENVIRONMENT` env var (`sandbox` or `production`, default `production`). For v1 with one user, no need to support both simultaneously.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in test runner (node:test) + assert |
| Config file | None needed -- node --test discovers test files |
| Quick run command | `node --test relay/src/**/*.test.ts` (via tsx loader) |
| Full suite command | `cd relay && npx tsx --test src/**/*.test.ts` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RELAY-01 | Two WS clients join same room, messages route between them | integration | `npx tsx --test src/rooms.test.ts` | No -- Wave 0 |
| RELAY-02 | APNs push sent when message arrives and no iOS client connected | unit | `npx tsx --test src/apns.test.ts` | No -- Wave 0 |
| RELAY-03 | Server starts on PORT env var, responds to HTTP | integration | `npx tsx --test src/server.test.ts` | No -- Wave 0 |
| RELAY-04 | GET /health returns 200 with status JSON | unit | `npx tsx --test src/server.test.ts` | No -- Wave 0 |
| RELAY-05 | APNs client initializes with valid config (rotation is internal to apns2) | unit | `npx tsx --test src/apns.test.ts` | No -- Wave 0 |
| RELAY-06 | Third client rejected from 2-client room | integration | `npx tsx --test src/rooms.test.ts` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `npx tsx --test src/**/*.test.ts` (quick, all unit+integration)
- **Per wave merge:** Same (small codebase, full suite is fast)
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `relay/src/rooms.test.ts` -- covers RELAY-01, RELAY-06 (room join, forward, capacity)
- [ ] `relay/src/apns.test.ts` -- covers RELAY-02, RELAY-05 (push sending, client init)
- [ ] `relay/src/server.test.ts` -- covers RELAY-03, RELAY-04 (server startup, health endpoint)
- [ ] `relay/tsconfig.json` -- TypeScript config for type checking
- [ ] `relay/package.json` -- project setup with all dependencies

## Sources

### Primary (HIGH confidence)
- [ws library API docs](https://github.com/websockets/ws/blob/master/doc/ws.md) -- WebSocket.Server constructor, handleUpgrade, connection/message events, ping/pong
- [ws npm](https://www.npmjs.com/package/ws) -- v8.20.0 confirmed current (published ~22 days ago)
- [apns2 GitHub](https://github.com/AndrewBarba/apns2) -- ApnsClient constructor, Notification class, error handling, JWT rotation source code
- [apns2 source: apns.ts](https://github.com/AndrewBarba/apns2/blob/main/src/apns.ts) -- Confirmed 55-minute token rotation interval (`RESET_TOKEN_INTERVAL_MS = 55 * 60 * 1000`), auto-reset on `ExpiredProviderToken`
- [Railway healthcheck docs](https://docs.railway.com/guides/healthchecks) -- PORT injection, healthcheck.railway.app hostname, 200 response requirement
- [Railway SSE vs WebSockets guide](https://docs.railway.com/guides/sse-vs-websockets) -- 15-minute timeout limit confirmed
- [Apple APNs token-based auth](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns) -- p8 JWT, 60-minute expiry, sandbox vs production endpoints

### Secondary (MEDIUM confidence)
- [tsx npm](https://www.npmjs.com/package/tsx) -- v4.21.0, esbuild-based TypeScript runner
- [Pino vs Winston benchmark (PkgPulse)](https://www.pkgpulse.com/blog/pino-vs-winston-2026) -- 5-8x performance advantage, structured JSON output
- [crypto.randomUUID performance (DEV.to)](https://dev.to/galkin/crypto-randomuuid-vs-uuid-v4-47i5) -- 3x faster than uuid npm, built into Node.js 14.17+

### Tertiary (LOW confidence)
- None -- all findings verified against primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries verified current, APIs confirmed against docs and source code
- Architecture: HIGH -- patterns derived from ws docs, Railway docs, and existing project research files (STACK.md, ARCHITECTURE.md)
- Pitfalls: HIGH -- Railway timeout, APNs JWT rotation, and sandbox/production mismatch all verified against official docs
- APNs token rotation: HIGH -- verified directly in apns2 source code (55-min interval, auto-reset on error)

**Research date:** 2026-04-15
**Valid until:** 2026-05-15 (stable domain, slow-moving dependencies)
