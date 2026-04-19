# Phase 7: FaceID Capability Tokens - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 07-faceid-capability-tokens
**Areas discussed:** Auto-refresh reconciliation, Token scope & origin trust, Revocation triggers + Lock Now, UX during silent reuse

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-refresh reconciliation | Existing 5-min Timer vs new tokens | ✓ |
| Token scope & origin trust | eTLD+1 vs full origin vs hostname; account_id source; chrome:// fallback | ✓ |
| Revocation triggers + Lock Now | Background, iCloud change, screen lock, biometric failure, manual lock | ✓ |
| UX during silent reuse | Silent vs toast vs auto-dismissing sheet | ✓ |

**User's choice:** All four selected.

---

## Initial framing (before user simplification)

Claude initially proposed three multi-option questions for Area 1 (Timer relationship, send trigger, scope-miss behavior). The user rejected the framing with: *"keep it simple, if we request code and we approve with face id on the phone and we request again we should not need to have face id on the phone again, the app should share the code without faceid for 2 minutes."*

This single sentence collapsed Areas 1, 2, and most of 3 into a simpler model: 2-min global window per pairing, request-driven, no per-account/per-origin scope. The remaining decisions were window scope, revocation triggers, and silent-send UX.

---

## Window scope (collapsed Area 1 + Area 2)

| Option | Description | Selected |
|--------|-------------|----------|
| Any account, any site | One global window per pairing | ✓ |
| Same account only | Per-account isolation | |
| Same site (origin) only | Per-origin isolation | |

**User's choice:** Any account, any site.
**Notes:** User favored simplicity over scope refinement. Documented security trade-off in CONTEXT.md D-14 (phishing exposure mitigated only by visible toast).

---

## Revocation triggers (Area 3)

| Option | Description | Selected |
|--------|-------------|----------|
| App goes to background | Window ends instantly when app loses foreground | ✓ |
| iCloud account changes | Wired via existing `ICloudStateObserver.didAccountChange` | ✓ |
| Manual 'Lock now' button | Explicit lock UI | ✓ (initially) |
| Nothing — pure 2-min timer | No early revocation | |

**User's choice:** Background + iCloud change + Lock Now.
**Notes:** "Lock Now" was selected here, then immediately rejected in the follow-up placement question (see below).

---

## Silent-send UX (Area 4)

| Option | Description | Selected |
|--------|-------------|----------|
| Brief toast 'Code sent for [issuer]' | Visible signal, non-interrupting | ✓ |
| Nothing — truly silent | Zero feedback | |
| Approval sheet auto-dismissing after 1 sec | Sheet still appears, no FaceID | |

**User's choice:** Brief toast.
**Notes:** Toast becomes the user's only signal that a silent send happened — load-bearing for both UX trust and the documented phishing mitigation in D-14.

---

## 'Lock Now' placement follow-up

| Option | Description | Selected |
|--------|-------------|----------|
| Settings screen, top of screen | Prominent row when window active | |
| Main screen toolbar (lock icon) | Always-visible toolbar lock | |
| Both — toolbar + Settings row | Belt and suspenders | |

**User's choice:** "we dont need this" (free text)
**Notes:** User reversed the earlier Lock-Now selection, removing it as a revocation trigger. CONTEXT.md D-08 reflects this.

---

## Existing Timer disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Remove it | Pure request-driven sends, Timer deleted | ✓ |
| Keep it for originating account | Timer + tokens coexist | |

**User's choice:** Remove the Timer.
**Notes:** Aligns with "keep it simple" framing. Documented behavior change in CONTEXT.md D-13.

---

## Claude's Discretion

The following were not asked of the user and are flagged as Claude's discretion in CONTEXT.md:

- In-memory token store architecture (singleton vs `@StateObject`-injected)
- Toast UI implementation (SwiftUI overlay vs UIKit window)
- `LAContext` reuse vs pure timer flag (recommend skipping `LAContext` in window path)
- Background revocation timing (no grace period)
- Mint site (post-`authenticate` in `CodeApprovalView.approveAndSend`)
- Silent-send branch site (`RelayClient.handleMessage` `default:` clause)
- Account resolution fallback (multi-match → re-prompt FaceID)
- Toast text when issuer is empty (use matched account's issuer)

## Deferred Ideas

- Per-origin / per-account scope (deferred to v2)
- "Lock now" button (rejected, reconsider only after security incident)
- Configurable TTL (locked at 2 min)
- Sliding-window TTL (rejected for simplicity)
- Active-tokens UI (not needed for global single-window model)
- Origin-strength upgrades (only relevant if per-origin scope returns)
- Persisting window across launches (explicitly never done)
