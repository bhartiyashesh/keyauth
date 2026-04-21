# Phase 8: Core Extension Flow - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 08-core-extension-flow
**Areas discussed:** Account selection & domain matching, Auto-fill detection & injection, Resilience UX, iOS approval sheet behavior

---

## Account Selection & Domain Matching

### How should the extension get account metadata?

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch on connect (Recommended) | Phone sends account list when WebSocket connects. Simple, no persistent cache. Phase 9 adds caching + search later. | ✓ |
| Skip account list for now | Phase 8 uses generic 'Request Code' button. Domain matching deferred to Phase 9. | |
| Minimal cache in chrome.storage | Phone sends list on connect AND extension persists it. Basically doing part of Phase 9 early. | |

**User's choice:** Fetch on connect
**Notes:** None

### What gets sent to the phone when user clicks an account?

| Option | Description | Selected |
|--------|-------------|----------|
| Account ID + current domain | Extension sends selected account ID and active tab's domain. Phone uses ID to generate code. Domain logged for future smart sort. | ✓ |
| Account ID only | Just sends account ID. Simpler message. | |
| Domain only (phone picks) | Extension sends domain. Phone does matching and picks account. | |

**User's choice:** Account ID + current domain
**Notes:** None

### How should domain matching work?

| Option | Description | Selected |
|--------|-------------|----------|
| Simple string contains (Recommended) | Match if domain contains issuer name or vice versa. Same approach as CodeApprovalView.swift. | ✓ |
| Curated domain map | Lookup table mapping domains to issuers. More accurate but needs maintenance. | |
| You decide | Claude picks based on codebase patterns. | |

**User's choice:** Simple string contains
**Notes:** None

---

## Auto-Fill Detection & Injection

### How should the content script detect TOTP input fields?

| Option | Description | Selected |
|--------|-------------|----------|
| Layered heuristics (Recommended) | Check: (1) autocomplete='one-time-code', (2) name/id containing otp/totp/2fa/verification/code, (3) single 6-digit maxlength near verify button. | ✓ |
| Autocomplete attribute only | Only fill inputs with autocomplete='one-time-code'. Safest but misses many sites. | |
| You decide | Claude picks detection strategy. | |

**User's choice:** Layered heuristics
**Notes:** None

### When should the content script fill the detected field?

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-fill immediately on code receive (Recommended) | Fill detected field as soon as code arrives. No extra user action. Falls back to popup + clipboard if no field detected. | ✓ |
| Fill on user click | Show inline badge near field. User clicks to fill. | |
| Auto-fill + toast notification | Fill automatically but show brief toast confirming 'Code filled'. | |

**User's choice:** Auto-fill immediately on code receive
**Notes:** None

### Handle split-input fields?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, handle split inputs | Detect groups of 6 adjacent single-character inputs and distribute digits. Covers banking sites. | ✓ |
| Single input only for now | Only fill single <input> fields. Simpler, covers majority of sites. | |
| You decide | Claude evaluates complexity vs coverage. | |

**User's choice:** Yes, handle split inputs
**Notes:** None

---

## Resilience UX

### What should the user see during reconnection?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent with status dot (Recommended) | StatusDot turns yellow/orange. No modal or blocking UI. Inline 'Reconnecting...' if user tries to request code while disconnected. | ✓ |
| Explicit reconnecting state | Dedicated 'Reconnecting...' view with spinner, replacing account list. | |
| Fully silent | No visual indicator. Retry silently after reconnect. | |

**User's choice:** Silent with status dot
**Notes:** None

### Proactive reconnect before Railway's 15-min timeout?

| Option | Description | Selected |
|--------|-------------|----------|
| Reconnect at 13 minutes (Recommended) | Timer-based. Gracefully close and re-establish at 13 minutes. 2-minute buffer. | ✓ |
| Pong-based detection | Track last pong. If no pong for 60s, reconnect. More reactive. | |
| You decide | Claude picks based on existing code. | |

**User's choice:** Reconnect at 13 minutes
**Notes:** None

### Service worker state rebuild on wake?

| Option | Description | Selected |
|--------|-------------|----------|
| Pairing + room + connection intent | Read pairing from local storage, room ID + 'should be connected' flag from session, auto-reconnect. Account list re-fetched after reconnect. | ✓ |
| You decide | Claude reviews storage.ts and decides what's missing. | |
| Full state snapshot | Persist everything. Restore exactly where left off. | |

**User's choice:** Pairing + room + connection intent
**Notes:** None

---

## iOS Approval Sheet Behavior

### What changes are needed for Phase 8?

| Option | Description | Selected |
|--------|-------------|----------|
| Wire it up, minimal changes (Recommended) | View is built. Just ensure relay message triggers it, trust window works, code response encrypted and sent back. | ✓ |
| Visual refresh needed | UI polish — better info display, loading states, animations. | |
| Add request queuing | Handle multiple rapid code requests. Queue and process sequentially. | |

**User's choice:** Wire it up, minimal changes
**Notes:** None

### Background push behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Push opens app to approval sheet | APNs alert push arrives, user taps notification, app opens to CodeApprovalView. Already partially wired in AppDelegate. | ✓ |
| Push + trust window auto-send | Silent push if within trust window, alert push otherwise. | |
| Alert push only (no silent path) | Always alert push, always require tap + FaceID. | |

**User's choice:** Push opens app to approval sheet
**Notes:** None

---

## Claude's Discretion

- Content script injection timing
- Exact exponential backoff parameters
- Account list message envelope format
- Edge cases (multiple fields, iframes)

## Deferred Ideas

None
