# Phase 1: Relay Server - Context

**Gathered:** 2026-04-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Deploy a WebSocket relay server to Railway that routes encrypted messages between paired devices (Chrome extension + iOS app) and sends APNs alert pushes to wake the iOS app when it's not connected. The relay is a dumb pipe — it does NOT decrypt, store, or interpret message payloads beyond `join` and `register_token`.

</domain>

<decisions>
## Implementation Decisions

### Message Protocol
- **D-01:** Messages use a versioned JSON envelope: `{ v: 1, type: string, id: uuid, payload: {...} }`
- **D-02:** Errors use structured type field: `{ type: 'error', code: 'room_full', message: '...' }`
- **D-03:** Relay only understands `join` and `register_token` message types — everything else is forwarded as opaque encrypted blobs to the other client in the room
- **D-04:** Code requests include a UUID correlation ID (requestId) echoed back in responses
- **D-05:** E2E encryption using tweetnacl (X25519 key exchange at pairing, secretbox for messages) — relay NEVER sees plaintext TOTP codes. This upgrades the original TLS-only decision.

### Room Lifecycle
- **D-06:** Rooms persist in memory with a TTL — reconnecting clients always find their room
- **D-07:** TTL eviction cleans up rooms with no clients after a configurable period
- **D-08:** Max 2 clients per room (one extension, one iOS)

### APNs Integration
- **D-09:** iOS device token sent during the `join` message: `{ type: 'join', roomId, deviceToken }`
- **D-10:** Relay sends APNs alert push ONLY when a message arrives and no iOS client is connected to the room
- **D-11:** Alert push type mandatory (not silent) — silent pushes are throttled at ~3/hour by Apple
- **D-12:** APNs uses p8 JWT auth via apns2 library; JWT token rotated at 45-minute intervals
- **D-13:** APNs p8 key file added to .gitignore

### Deployment
- **D-14:** Relay server lives in `relay/` directory at project root (monorepo alongside iOS app)
- **D-15:** Structured JSON logging (timestamp, level, roomId) for Railway log searchability
- **D-16:** Minimal env vars: `PORT` (Railway), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`
- **D-17:** Node.js 22 LTS runtime, ws 8.20.x WebSocket library, apns2 12.2.x for push
- **D-18:** Railway handles TLS termination — relay listens on plain ws:// internally

### Claude's Discretion
- Room creation mechanism (likely implicit on first join)
- Room TTL duration (suggest 30-60 minutes)
- Ping/pong strategy (application-level vs protocol-level)
- Health endpoint response format

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research Files
- `.planning/research/STACK.md` — WXT, ws, apns2 library choices with version numbers and rationale
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flow, message protocol design
- `.planning/research/PITFALLS.md` — Railway 15-min timeout, APNs JWT expiry, service worker state loss

### Project Context
- `.planning/PROJECT.md` — Updated E2E encryption decision (overrides original TLS-only)
- `.planning/REQUIREMENTS.md` — RELAY-01 through RELAY-06 requirement definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — relay is a new Node.js project, no existing server code

### Established Patterns
- iOS app uses `URLSessionWebSocketTask` for WebSocket — relay must speak raw RFC 6455 (ws library does this)
- Existing `SharedDefaults.swift` bridges data via App Group UserDefaults — relay communication is a new parallel channel

### Integration Points
- Relay URL will be hardcoded or configured in the Chrome extension and iOS app in later phases
- APNs device token flows: iOS app → relay (during join) → relay stores in room → relay uses for push
- Pairing QR code (Phase 3) will encode `{ roomId, relayURL, publicKey }` — relay must accept these roomIds

</code_context>

<specifics>
## Specific Ideas

- E2E encryption via tweetnacl was an explicit upgrade from the original TLS-only plan — the user wants zero-knowledge relay where codes are never visible to the server
- The relay should be deployable and testable with two browser tabs or curl before any client code exists

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-relay-server*
*Context gathered: 2026-04-15*
