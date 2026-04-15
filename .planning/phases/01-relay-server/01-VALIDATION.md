---
phase: 1
slug: relay-server
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in test runner (node:test) + assert |
| **Config file** | None needed -- node --test discovers test files |
| **Quick run command** | `npx tsx --test relay/src/**/*.test.ts` |
| **Full suite command** | `cd relay && npx tsx --test src/**/*.test.ts` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx tsx --test relay/src/**/*.test.ts`
- **After every plan wave:** Run `cd relay && npx tsx --test src/**/*.test.ts`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | RELAY-01 | — | N/A | integration | `npx tsx --test relay/src/rooms.test.ts` | No -- W0 | pending |
| 01-01-02 | 01 | 1 | RELAY-06 | — | Third client rejected | integration | `npx tsx --test relay/src/rooms.test.ts` | No -- W0 | pending |
| 01-02-01 | 02 | 1 | RELAY-02 | — | Push only when iOS absent | unit | `npx tsx --test relay/src/apns.test.ts` | No -- W0 | pending |
| 01-02-02 | 02 | 1 | RELAY-05 | — | JWT rotation handled by library | unit | `npx tsx --test relay/src/apns.test.ts` | No -- W0 | pending |
| 01-03-01 | 03 | 1 | RELAY-03 | — | N/A | integration | `npx tsx --test relay/src/server.test.ts` | No -- W0 | pending |
| 01-03-02 | 03 | 1 | RELAY-04 | — | N/A | unit | `npx tsx --test relay/src/server.test.ts` | No -- W0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `relay/src/rooms.test.ts` — stubs for RELAY-01, RELAY-06 (room join, forward, capacity)
- [ ] `relay/src/apns.test.ts` — stubs for RELAY-02, RELAY-05 (push sending, client init)
- [ ] `relay/src/server.test.ts` — stubs for RELAY-03, RELAY-04 (server startup, health endpoint)
- [ ] `relay/tsconfig.json` — TypeScript config for type checking
- [ ] `relay/package.json` — project setup with all dependencies

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Railway TLS termination works | RELAY-03 | Requires live Railway deployment | Deploy to Railway, connect via wss:// URL, verify TLS handshake succeeds |
| APNs push reaches device | RELAY-02 | Requires real APNs credentials + iOS device | Register device token, send test push, verify iOS notification appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
