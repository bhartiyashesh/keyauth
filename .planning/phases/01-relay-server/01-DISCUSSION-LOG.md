# Phase 1: Relay Server - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-15
**Phase:** 01-relay-server
**Areas discussed:** Message protocol, Room lifecycle, APNs integration, Deployment config

---

## Message Protocol

| Option | Description | Selected |
|--------|-------------|----------|
| Simple JSON envelope | { type, payload } — flat, easy to debug | |
| Typed with version | { v, type, id, payload } — versioning + correlation IDs | ✓ |
| You decide | Claude picks simplest | |

**User's choice:** Typed with version
**Notes:** User also confirmed UUID correlation IDs per request for request/response matching.

| Option | Description | Selected |
|--------|-------------|----------|
| Error type field | { type: 'error', code: 'room_full', message } | ✓ |
| HTTP-style codes | { type: 'error', status: 409, message } | |
| You decide | | |

**User's choice:** Error type field

| Option | Description | Selected |
|--------|-------------|----------|
| Relay understands all | Parses every message type | |
| Relay = dumb pipe + join | Only understands join + register_token, forwards rest | ✓ |
| You decide | | |

**User's choice:** Relay = dumb pipe + join

**Major decision change:** User requested E2E encryption (tweetnacl, X25519) — upgrading from original TLS-only plan to zero-knowledge relay.

## Room Lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| On first join | Room created on first client connect | |
| Explicit create | REST endpoint to create room | |
| You decide | Claude picks simplest | ✓ |

**User's choice:** You decide (Claude's discretion)

| Option | Description | Selected |
|--------|-------------|----------|
| TTL eviction | Rooms deleted after N minutes with no clients | ✓ |
| On disconnect | Room deleted when last client disconnects | |
| You decide | | |

**User's choice:** TTL eviction

| Option | Description | Selected |
|--------|-------------|----------|
| Rejoin same room | Client re-sends join with stored roomId | |
| Room persists | Room survives empty with longer TTL | ✓ |
| You decide | | |

**User's choice:** Room persists

## APNs Integration

| Option | Description | Selected |
|--------|-------------|----------|
| During join | iOS sends { type: join, roomId, deviceToken } | ✓ |
| Separate message | Join first, then register_token separately | |
| You decide | | |

**User's choice:** During join

| Option | Description | Selected |
|--------|-------------|----------|
| iOS absent | Push only when no iOS client connected | ✓ |
| Every request | Push on every request regardless | |
| You decide | | |

**User's choice:** iOS absent

| Option | Description | Selected |
|--------|-------------|----------|
| Alert push | Shows notification banner, reliable | ✓ |
| Silent first | Try silent, fall back to alert | |
| Alert is fine | Just use alert | |

**User's choice:** Alert push

## Deployment Config

| Option | Description | Selected |
|--------|-------------|----------|
| Separate directory | relay/ at project root, monorepo | ✓ |
| Separate repo | New git repo | |
| You decide | | |

**User's choice:** Separate directory (relay/)

| Option | Description | Selected |
|--------|-------------|----------|
| Structured JSON | JSON log lines, searchable | ✓ |
| Simple console | console.log, readable | |
| You decide | | |

**User's choice:** Structured JSON

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal | PORT + APNS vars only | ✓ |
| Configurable | Add TTL, max clients, log level | |
| You decide | | |

**User's choice:** Minimal

## Claude's Discretion

- Room creation mechanism
- Room TTL duration
- Ping/pong strategy
- Health endpoint format

## Deferred Ideas

None
