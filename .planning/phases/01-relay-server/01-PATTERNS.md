# Phase 1: Relay Server - Patterns

**Generated:** 2026-04-15
**Phase:** 01-relay-server
**Files identified:** 11 files to create (new Node.js project in `relay/`)

## Files to Create/Modify

### File 1: `relay/package.json`

**Role:** Configuration
**Data Flow:** N/A (build/runtime metadata)
**Operation:** CREATE
**Closest Analog:** `project.yml` (project manifest pattern -- defines targets, dependencies, scripts)

**Why analog is relevant:** `project.yml` is the project-level manifest that defines build targets and scheme configuration. `package.json` serves the same role for the Node.js relay: it declares dependencies, runtime scripts, and project metadata.

**Analog excerpt from `project.yml`:**
```yaml
name: KeyAuth
options:
  bundleIdPrefix: com.keyauth
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "15.0"
```

**Target pattern from RESEARCH.md:**
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

**Dependencies (from CONTEXT.md D-17 and RESEARCH.md):**
- `ws` 8.20.x -- WebSocket server
- `apns2` 12.2.x -- APNs HTTP/2 push client
- `pino` 9.x -- structured JSON logging
- `tsx` 4.21.x (dev) -- TypeScript runner
- `typescript` 5.x (dev) -- type checking only
- `@types/ws` 8.18.x (dev)
- `@types/node` 22.x (dev)
- `pino-pretty` 13.x (dev) -- human-readable dev logs

---

### File 2: `relay/tsconfig.json`

**Role:** Configuration
**Data Flow:** N/A (type checking config)
**Operation:** CREATE
**Closest Analog:** None in codebase (Swift uses `project.yml` for build settings; no TypeScript files exist)

**Target pattern from RESEARCH.md:**
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

**Key decisions:**
- `"noEmit": true` -- tsx handles runtime; tsc is for type checking only
- `"strict": true` -- matches the project's overall strictness (Swift uses strict typing)
- `"module": "ESNext"` + `"type": "module"` in package.json -- ESM throughout

---

### File 3: `relay/.gitignore`

**Role:** Configuration
**Data Flow:** N/A (source control exclusion)
**Operation:** CREATE
**Closest Analog:** None (no `.gitignore` exists at project root)

**Required entries (from CONTEXT.md D-13):**
```
node_modules/
dist/
*.p8
.env
.env.*
```

**Rationale:** D-13 mandates the APNs p8 key file must be in `.gitignore`. PITFALLS.md Pitfall 4 warns about accidentally committing the signing key.

---

### File 4: `relay/.nvmrc`

**Role:** Configuration
**Data Flow:** N/A (runtime version pinning)
**Operation:** CREATE
**Closest Analog:** None

**Content:** `22` (from CONTEXT.md D-17: Node.js 22 LTS)

---

### File 5: `relay/src/types.ts`

**Role:** Type definitions (shared across all modules)
**Data Flow:** Imported by all other `src/` modules
**Operation:** CREATE
**Closest Analog:** `Shared/Account.swift` (canonical data model with serialization)

**Why analog is relevant:** `Account.swift` defines the project's canonical data type (UUID-identified, serializable struct with typed enum fields). `types.ts` serves the same purpose for the relay: defining the message envelope, room, client, and error types that all modules share.

**Analog excerpt from `Shared/Account.swift`:**
```swift
struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var issuer: String
    var label: String
    var secret: String // Base32-encoded
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var sortOrder: Int
    var createdAt: Date
}
```

**Target pattern (from CONTEXT.md D-01, D-02 and RESEARCH.md):**
```typescript
interface MessageEnvelope {
  v: number;
  type: string;
  id: string;      // UUID correlation ID
  payload: Record<string, unknown>;
}

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

type ErrorCode = 'room_full' | 'invalid_message' | 'room_not_found';
```

**Mapping from Swift patterns:**
- Swift `Account.id: UUID` -> TypeScript `Room.id: string` (UUID as string)
- Swift `OTPAlgorithm` enum -> TypeScript `ErrorCode` union type
- Swift `Codable` protocol -> TypeScript `interface` (JSON-native serialization)

---

### File 6: `relay/src/logger.ts`

**Role:** Infrastructure (cross-cutting concern)
**Data Flow:** Imported by all modules for structured logging output
**Operation:** CREATE
**Closest Analog:** None (existing codebase has zero logging -- noted in ARCHITECTURE.md)

**Target pattern (from CONTEXT.md D-15 and RESEARCH.md):**
```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
});

export default logger;
```

**Key decisions (from CONTEXT.md D-15):**
- Structured JSON logging with timestamp, level, roomId fields
- Pino's default JSON output works directly with Railway log search
- Child loggers with `roomId` context for per-room tracing: `logger.child({ roomId })`

---

### File 7: `relay/src/rooms.ts`

**Role:** Core business logic (state management)
**Data Flow:** Receives join/leave/forward calls from `handlers.ts`; reads/writes in-memory room Map; queried by `index.ts` during upgrade for capacity check
**Operation:** CREATE
**Closest Analog:** `Shared/AccountStore.swift` (in-memory state manager with CRUD operations)

**Why analog is relevant:** `AccountStore` is the single state manager for the iOS app -- it wraps a collection (`[Account]`), exposes CRUD methods (`add`, `delete`, `move`), and triggers side effects after mutations (`reload()` syncs SharedDefaults). `RoomManager` follows the same pattern: wraps a `Map<string, Room>`, exposes join/leave/forward, and triggers side effects (TTL timestamp updates).

**Analog excerpt from `Shared/AccountStore.swift`:**
```swift
@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?
    
    private let keychain = KeychainManager.shared
    
    func add(_ account: Account) {
        do {
            try keychain.save(account)
            reload()
        } catch {
            self.error = "Failed to save account"
        }
    }
    
    func reload() {
        do {
            accounts = try keychain.loadAll()
            SharedDefaults.saveAccounts(accounts)
        } catch {
            self.error = "Failed to load accounts"
        }
    }
}
```

**Target pattern (from RESEARCH.md Pattern 2):**
```typescript
class RoomManager {
  private rooms = new Map<string, Room>();
  private ttlMs: number;
  private timer: NodeJS.Timeout;

  constructor(ttlMinutes: number = 30) {
    this.ttlMs = ttlMinutes * 60 * 1000;
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

  leave(roomId: string, clientId: string): void { /* ... */ }
  forward(roomId: string, senderClientId: string, data: string): void { /* ... */ }
  getRoom(roomId: string): Room | undefined { return this.rooms.get(roomId); }
  private evict(): void { /* ... */ }
  shutdown(): void { clearInterval(this.timer); }
}
```

**Structural parallels:**
- `AccountStore.accounts: [Account]` -> `RoomManager.rooms: Map<string, Room>`
- `AccountStore.add()` -> `RoomManager.join()`
- `AccountStore.delete()` -> `RoomManager.leave()`
- `AccountStore.reload()` (side-effect sync) -> `RoomManager.join/leave` (updates `lastActivity`)
- `KeychainManager` (persistence layer) -> No persistence (in-memory only, per D-06)

**Decisions from CONTEXT.md:**
- D-06: Rooms persist with TTL (not deleted on disconnect)
- D-07: TTL eviction for rooms with no clients (recommended 30 min)
- D-08: Max 2 clients per room

---

### File 8: `relay/src/apns.ts`

**Role:** External integration (APNs push client)
**Data Flow:** Called by `handlers.ts` when a message arrives and no iOS client is connected; sends HTTP/2 push to Apple; receives error responses
**Operation:** CREATE
**Closest Analog:** None (existing iOS app has no server-side push integration)

**Target pattern (from RESEARCH.md verified code example):**
```typescript
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

**Key decisions from CONTEXT.md:**
- D-09: Device token arrives in join message
- D-10: Push sent ONLY when iOS client is absent
- D-11: Alert push type (not silent)
- D-12: p8 JWT auth via apns2; JWT auto-rotated at 55 min internally (RELAY-05)
- D-16: Env vars: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`

**Bundle ID cross-reference from `project.yml`:**
```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.keyauth.app
```
The `defaultTopic` in the APNs client must match this bundle ID exactly.

**RESEARCH.md open question resolution:**
- Support both `APNS_KEY` (base64 env var) and `APNS_KEY_PATH` (file path) for flexibility
- Single `APNS_ENVIRONMENT` env var toggles sandbox/production

---

### File 9: `relay/src/handlers.ts`

**Role:** Core business logic (message routing)
**Data Flow:** Receives raw WebSocket messages from `index.ts`; parses envelope; dispatches to `rooms.ts` (join/forward) or `apns.ts` (push); sends error/pong responses back to client
**Operation:** CREATE
**Closest Analog:** `Shared/Account.swift: Account.from(otpauthURL:)` (input parsing and validation)

**Why analog is relevant:** `Account.from(otpauthURL:)` is the project's canonical input-parsing pattern: receive raw input (URL string), validate structure (scheme, host, query params), extract typed fields, return a validated result or nil. `parseMessage` + `handleJoin` follows the same parse-validate-dispatch pattern for incoming WebSocket messages.

**Analog excerpt from `Shared/Account.swift`:**
```swift
static func from(otpauthURL url: URL) -> Account? {
    guard url.scheme == "otpauth",
          url.host == "totp",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        return nil
    }

    let params = Dictionary(queryItems.compactMap { item -> (String, String)? in
        guard let value = item.value else { return nil }
        return (item.name.lowercased(), value)
    }, uniquingKeysWith: { _, last in last })

    guard let secret = params["secret"], !secret.isEmpty else { return nil }
    // ... validation and construction ...
    return Account(...)
}
```

**Target pattern (from RESEARCH.md Pattern 3):**
```typescript
function parseMessage(raw: string): MessageEnvelope | null {
  try {
    const msg = JSON.parse(raw);
    if (msg.v !== 1 || !msg.type || !msg.id) return null;
    return msg as MessageEnvelope;
  } catch {
    return null;
  }
}

// Message dispatch (switch on type)
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
```

**Structural parallels:**
- Swift `guard url.scheme == "otpauth"` -> TypeScript `if (msg.v !== 1 || !msg.type || !msg.id) return null`
- Swift returns `Account?` (nil on failure) -> TypeScript returns `MessageEnvelope | null`
- Swift extracts typed fields from URL params -> TypeScript extracts typed fields from JSON

**Key decisions from CONTEXT.md:**
- D-01: Versioned envelope `{ v: 1, type, id, payload }`
- D-02: Error format `{ type: 'error', code, message }`
- D-03: Only `join` and `register_token` understood; everything else forwarded opaquely
- D-04: UUID correlation ID echoed in responses
- D-10: APNs push triggered here when forwarding and no iOS client present

---

### File 10: `relay/src/index.ts`

**Role:** Entry point (application bootstrap and HTTP/WebSocket server setup)
**Data Flow:** Creates HTTP server (serves /health); creates WebSocket server in noServer mode; handles upgrade requests (extracts roomId, checks capacity); delegates to `handlers.ts` on connection; wires graceful shutdown
**Operation:** CREATE
**Closest Analog:** `App/KeyAuthApp.swift` (application entry point that initializes state and wires dependencies)

**Why analog is relevant:** `KeyAuthApp.swift` is the `@main` entry point that creates the `AccountStore` (state), injects it into the view hierarchy, and sets up lifecycle observers. `index.ts` serves the same bootstrapping role: creates the `RoomManager` (state), creates the HTTP and WebSocket servers, wires event handlers, and starts listening.

**Analog excerpt from `App/KeyAuthApp.swift`:**
```swift
@main
struct KeyAuthApp: App {
    @StateObject private var store = AccountStore()
    @State private var isLocked = true
    
    var body: some Scene {
        WindowGroup {
            if isLocked {
                LockScreenView(onUnlock: { isLocked = false })
            } else {
                ContentView()
                    .environmentObject(store)
            }
        }
    }
}
```

**Target pattern (from RESEARCH.md):**
```typescript
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';

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

**Structural parallels:**
- Swift `@StateObject private var store = AccountStore()` -> TypeScript `const roomManager = new RoomManager()`
- Swift `.environmentObject(store)` (dependency injection) -> TypeScript passing `roomManager` to handlers
- Swift `@main` (app lifecycle) -> TypeScript `server.listen()` (server lifecycle)

**Key decisions from CONTEXT.md:**
- D-14: Lives in `relay/` directory
- D-16: Uses `process.env.PORT` (Railway injection)
- D-18: Listens on plain ws:// (Railway handles TLS)
- RELAY-04: /health endpoint returns 200 JSON
- RELAY-06: Reject connections when room has 2 clients

---

### File 11: `relay/src/__tests__/` (test files)

**Role:** Validation
**Data Flow:** Import and test `rooms.ts`, `apns.ts`, `handlers.ts`, and `index.ts` server behavior
**Operation:** CREATE
**Closest Analog:** None (existing codebase has no test targets or test files -- noted in STRUCTURE.md)

**Target test files (from RESEARCH.md Wave 0 Gaps):**

| Test File | Covers | Requirements |
|-----------|--------|-------------|
| `relay/src/rooms.test.ts` | Room join, forward, capacity, TTL eviction | RELAY-01, RELAY-06 |
| `relay/src/apns.test.ts` | APNs client init, push sending, error handling | RELAY-02, RELAY-05 |
| `relay/src/server.test.ts` | HTTP server startup, /health endpoint, WebSocket upgrade | RELAY-03, RELAY-04 |

**Test framework (from RESEARCH.md):**
- Node.js built-in test runner (`node:test` + `node:assert`)
- Run command: `npx tsx --test src/**/*.test.ts`
- No separate test framework dependency needed

**Target test pattern:**
```typescript
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

describe('RoomManager', () => {
  let manager: RoomManager;

  beforeEach(() => {
    manager = new RoomManager(30);
  });

  afterEach(() => {
    manager.shutdown();
  });

  it('creates room on first join', () => {
    const room = manager.join('room-1', 'client-1', mockWs());
    assert.equal(room.id, 'room-1');
    assert.equal(room.clients.size, 1);
  });

  it('rejects third client in a room', () => {
    manager.join('room-1', 'client-1', mockWs());
    manager.join('room-1', 'client-2', mockWs());
    const room = manager.getRoom('room-1');
    assert.equal(room!.clients.size, 2);
    // Capacity check happens in index.ts upgrade handler
  });
});
```

---

## Cross-File Data Flow

```
                       WebSocket Client (browser or iOS)
                               |
                               | ws:// upgrade with ?roomId=<uuid>
                               v
                        +--------------+
                        | index.ts     |  HTTP /health endpoint
                        | (entry point)|  WebSocket upgrade handler
                        +--------------+  Capacity check via rooms.getRoom()
                               |
                               | on 'connection' event
                               v
                        +--------------+
                        | handlers.ts  |  parseMessage() -> MessageEnvelope | null
                        | (routing)    |  switch on msg.type:
                        +--------------+    join -> rooms.join()
                          /         \       register_token -> rooms.updateToken()
                         /           \      ping -> send pong
                        v             v     default -> rooms.forward() + apns check
                 +----------+   +----------+
                 | rooms.ts |   | apns.ts  |
                 | (state)  |   | (push)   |
                 +----------+   +----------+
                 Map<Room>      ApnsClient.send()
                               |
                               v
                 +----------+  +----------+
                 | types.ts |  | logger.ts|
                 | (shared) |  | (infra)  |
                 +----------+  +----------+
```

## Dependency Graph

```
index.ts
  ├── rooms.ts     (RoomManager instance)
  ├── handlers.ts  (message dispatch functions)
  ├── apns.ts      (sendWakeupPush function)
  ├── logger.ts    (pino logger instance)
  └── types.ts     (type imports)

handlers.ts
  ├── rooms.ts     (join, leave, forward, getRoom)
  ├── apns.ts      (sendWakeupPush)
  ├── logger.ts    (child loggers with roomId)
  └── types.ts     (MessageEnvelope, ErrorCode)

rooms.ts
  ├── logger.ts    (eviction logging)
  └── types.ts     (Room, Client)

apns.ts
  ├── logger.ts    (push error logging)
  └── types.ts     (N/A -- uses apns2 types)

logger.ts
  └── (no internal deps -- pino only)

types.ts
  └── (no internal deps -- pure type definitions)
```

## Anti-Patterns to Avoid (from RESEARCH.md)

| Anti-Pattern | Correct Approach | Files Affected |
|-------------|-----------------|----------------|
| Using Express for HTTP layer | Built-in `http` module (only /health + WS upgrade) | `relay/src/index.ts` |
| Storing messages for offline delivery | Send APNs push; do NOT buffer messages | `relay/src/handlers.ts` |
| Parsing encrypted payloads | Forward opaquely; only understand `join`, `register_token`, `ping` | `relay/src/handlers.ts` |
| Using `ws.Server({ port })` directly | Use `noServer: true` with `handleUpgrade` to share HTTP server | `relay/src/index.ts` |
| Deleting room on client disconnect | Keep room alive; TTL eviction handles cleanup (D-06) | `relay/src/rooms.ts` |
| Hardcoding port | Use `process.env.PORT` with fallback (D-16) | `relay/src/index.ts` |
| Using uuid npm package | Use `crypto.randomUUID()` (built into Node.js 22) | all files |

## iOS Compatibility Notes

The relay must speak standard RFC 6455 WebSocket to be compatible with the iOS app's `URLSessionWebSocketTask`. Key compatibility points:

- **Text frames only:** All messages are JSON strings sent as WebSocket text frames (not binary). `URLSessionWebSocketTask` receives these via `.receive()` -> `.string(String)` case.
- **No custom subprotocol:** Do not use `Sec-WebSocket-Protocol` headers. `URLSessionWebSocketTask` does not require them.
- **Standard close handshake:** The `ws` library handles RFC 6455 close frames correctly, which `URLSessionWebSocketTask` expects.
- **Room ID in query string:** iOS will connect to `wss://relay-host/?roomId=<uuid>`. The relay extracts this in the upgrade handler.

---

*Patterns analysis: 2026-04-15*
*Source: 01-CONTEXT.md, 01-RESEARCH.md, existing codebase analysis*
