# Phase 6: iCloud Keychain Sync - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 06-icloud-keychain-sync
**Areas discussed:** Default + opt-in + disclosure, Disable + migration semantics, Multi-device UX + empty state

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Default + opt-in + disclosure | Toggle default, prompt placement, disclosure framing | ✓ |
| Sync scope & granularity | Global vs per-account; what syncs vs what doesn't | |
| Disable + migration semantics | Disable flow, migration of existing accounts, dedup | ✓ |
| Multi-device UX + empty state | Fresh install UX, iCloud state handling | ✓ |

**Notes:** Sync scope deferred to Claude's discretion (global toggle, only `Account` records sync, device-bound items stay local).

---

## Default + opt-in + disclosure

### Q1: Default iCloud sync state for NEW users (fresh install)?

| Option | Description | Selected |
|--------|-------------|----------|
| OFF by default (Recommended) | Privacy-forward; explicit enable | |
| ON by default | Convenience-forward; matches 1Password/Apple Passwords | ✓ |
| Ask during onboarding | Dedicated onboarding step | |

**User's choice:** ON by default.
**Notes:** Combined with the later decision to show a first-launch explainer card for informed consent.

### Q2: Existing users — when and how do they get prompted?

| Option | Description | Selected |
|--------|-------------|----------|
| One-time banner on next launch (Recommended) | Non-modal banner, dismissible | |
| Modal sheet on next launch | Forced engagement | |
| Settings only, no prompt | Conservative; soft-launch | ✓ |

**User's choice:** Settings only, no prompt.
**Notes:** Respects existing users' prior choice of local-only by using the app before sync existed.

### Q3: Disclosure copy tone?

| Option | Description | Selected |
|--------|-------------|----------|
| Plain, trust-focused (Recommended) | Outcome-first, minimal jargon | ✓ |
| Technical, precise | Names E2E encryption, Apple ID, passcode | |
| Minimal / implicit | Short toggle label, no explanation | |

**User's choice:** Plain, trust-focused.

### Q4: Where does the disclosure copy live?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline under the toggle (Recommended) | Always visible near the toggle | ✓ |
| Confirmation sheet on enable | Forces reading before opt-in | |
| Help link / separate page | Cleaner UI, risks skipped link | |

**User's choice:** Inline under the toggle.

### Follow-up Q: New-user ON-by-default needs a disclosure surface before first save

| Option | Description | Selected |
|--------|-------------|----------|
| One-time card above account list (Recommended) | Dismissible card on first launch | ✓ |
| Banner on first QR scan / manual entry | Surfaces at save moment | |
| No extra surface — Settings only | Weakest informed consent | |

**User's choice:** One-time card above account list.

---

## Disable + migration semantics

### Q1: Turning the toggle OFF — what happens?

| Option | Description | Selected |
|--------|-------------|----------|
| Ask each time (Recommended) | Sheet with two explicit choices | |
| Always just stop on this device | Safer; separate destructive button | |
| Always purge from iCloud (scorched earth) | Toggle wipes everywhere | ✓ (initial) |

**Reconciliation Q:** User was shown the downstream consequence of scorched-earth purge (other devices lose accounts on disable). User changed selection to **Ask each time**.

**User's final choice:** Ask each time.

### Q2: Migrating existing local accounts when user enables sync?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent bulk migration (Recommended) | Re-save all, no per-account prompt | ✓ |
| One-tap confirm: 'Sync N accounts?' | Extra confirmation step | |
| Per-account confirmation | Maximum control | |

**User's choice:** Silent bulk migration.

### Q3: Duplicate handling — same account on two devices, both enable sync?

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-dedup on (issuer, label, secret) (Recommended) | Silent merge, one-time toast | |
| Show duplicates, let user choose | Review screen | |
| Keep all — let user clean up manually | No dedup logic | ✓ (initial) |

**Reconciliation Q:** User was shown the consequence of keep-all (20 accounts post-sync for a user with 10 local on each of two devices). User changed selection to **Auto-dedup silently**.

**User's final choice:** Auto-dedup on (issuer, label, secret).

### Q4: When user disables sync on this device — what happens to local copies?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep local copies (Recommended) | Re-save as local-only | ✓ |
| Clear everything on disable | Forces re-authentication | |
| Ask user | Another prompt | |

**User's choice:** Keep local copies.

---

## Multi-device UX + empty state

### Q1: Fresh install empty state during iCloud propagation?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated 'Restoring from iCloud' state (Recommended) | Distinct empty state with spinner | ✓ |
| Normal empty state + toast when accounts arrive | Simpler | |
| Banner above empty state | Hybrid | |

**User's choice:** Dedicated 'Restoring from iCloud' state.

### Q2: How does the app detect new iCloud data?

| Option | Description | Selected |
|--------|-------------|----------|
| Reload on foreground + NSUbiquitousKeyValueStore trigger (Recommended) | Dual signal | ✓ |
| Reload on foreground only | Simplest | |
| Poll every N seconds | Crude, discouraged | |

**User's choice:** Reload on foreground + NSUbiquitousKeyValueStore trigger.

### Q3: iCloud Keychain disabled at OS level — toggle behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Disabled with explainer (Recommended) | Grayed out + deep link to Settings | ✓ |
| Hide the toggle entirely | Cleanest UI | |
| Show toggle, error on enable | Discoverable, delayed error | |

**User's choice:** Disabled with explainer.

### Q4: Mid-session iCloud sign-out — what happens?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep showing them, flag state (Recommended) | Toggle flips off, explainer appears | ✓ |
| Immediately reload from Keychain | Jarring data loss | |
| Force-quit prompt | Heavy-handed | |

**User's choice:** Keep showing them, flag state.

---

## Claude's Discretion

- Sync scope: global toggle, only `Account` records sync, device-bound items (pairings, identity keys, APNs token, biometric prefs) stay local
- Settings screen architecture: entry point TBD by planner (toolbar gear button most likely)
- Migration atomicity on failure: continue-on-error with summary toast
- Testing strategy: two-device manual testing unavoidable; researcher to investigate unit-test viability for sync attribute logic

## Deferred Ideas

- Per-account sync granularity
- User-facing duplicate review screen
- Backup/recovery codes (separate phase)
- CloudKit-based sync (alternative transport)
- Re-pair-on-new-device UX improvements
- PROJECT.md Core Value rewording ("secrets never leave the phone" → more accurate phrasing)
