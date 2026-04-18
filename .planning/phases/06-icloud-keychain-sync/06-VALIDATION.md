---
phase: 6
slug: icloud-keychain-sync
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (via Xcode — target does not yet exist, Wave 0 creates it) |
| **Config file** | `KeyAuth.xcodeproj` (test target to be added in Wave 0) |
| **Quick run command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyAuthTests/{TestClass}` |
| **Full suite command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyAuthTests` |
| **Estimated runtime** | ~30-60 seconds (unit tests only — integration + two-device QA is out-of-band) |

---

## Sampling Rate

- **After every task commit:** Run quick test for the touched unit
- **After every plan wave:** Run full suite
- **Before `/gsd-verify-work`:** Full suite green + manual two-device checklist signed off
- **Max feedback latency:** ~60 seconds for automated; manual QA is gated at phase verification

---

## Per-Task Verification Map

Planner fills this table. Each ICLOUD-NN requirement maps to at least one task with an automated verify OR an explicit manual-only justification. Populated during planning (step 8) and refined during execution.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | — | 0 | WAVE-0 | — | XCTest target exists and builds | infra | `xcodebuild -list -project KeyAuth.xcodeproj \| grep KeyAuthTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] **Create `KeyAuthTests` XCTest target** — project currently has no test target (flagged by Phase 2 research, must be resolved in Phase 6)
- [ ] **Extract `KeychainProviding` protocol** — enables unit testing of sync-branching logic without real Keychain
- [ ] **Create `SyncPreference` helper stub** — single source of truth for the sync toggle state
- [ ] **Test fixtures for `Account` (with/without sync attribute)** — shared test data factory

*Rationale: Phase 6 requires the first real unit-test coverage in the project. Wave 0 installs the test scaffolding so all subsequent waves can commit green.*

---

## Manual-Only Verifications

iCloud Keychain cannot be mocked reliably in simulator. The following behaviors REQUIRE two-device manual QA and feed the `/gsd-verify-work` gate.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cross-device sync propagation (account added on device A appears on device B) | ICLOUD-01 / SC-1 | Real iCloud round-trip not mockable | 1. Sign both devices into same Apple ID with iCloud Keychain ON. 2. Enable sync on device A. 3. Add test account. 4. Observe account appears on device B within ≤15 min (typical) |
| "Restoring from iCloud…" empty state on fresh install | ICLOUD-09 / SC-1 | Requires fresh install + real iCloud fetch | 1. Device A has accounts synced. 2. Fresh-install app on device B signed into same iCloud. 3. Observe spinner state, then account appearance. 4. Confirm 30s timeout fallback copy if nothing arrives |
| Destructive "Remove from iCloud on all devices" propagation | ICLOUD-05 / SC-4 | Requires observing real propagation | 1. Both devices in sync. 2. On device A, toggle OFF → pick destructive option. 3. Verify account list on device B empties within typical sync window |
| Per-device opt-out (D-06) preserves local copies | ICLOUD-06 / SC-4 | Requires observing multi-device state | 1. Both devices in sync. 2. On device A, toggle OFF → "Stop syncing this device". 3. Verify device A retains accounts locally. 4. Verify device B retains accounts (not deleted). 5. Add account on A → does NOT appear on B |
| Mid-session iCloud sign-out handling (D-12) | ICLOUD-12 / SC-4 | Requires changing iCloud state during runtime | 1. App running with sync ON. 2. Sign out of iCloud in iOS Settings. 3. Return to app. 4. Observe: accounts still visible (cached), toggle auto-flips OFF, inline message shown |
| iCloud Keychain disabled at OS level (D-11) | ICLOUD-11 / SC-2 | Requires changing iCloud Keychain toggle in iOS Settings | 1. Settings → Apple ID → iCloud → Passwords & Keychain → OFF. 2. Launch app → Settings. 3. Observe: toggle visible but disabled, deep-link button active, copy matches UI-SPEC |
| Keyboard extension sees synced accounts | ICLOUD-13 / SC-5 | Keyboard is a separate process; must verify end-to-end | 1. Sync ON, add account via main app on device A. 2. Wait for propagation to device B. 3. Open keyboard on device B in a text field. 4. Observe synced account appears in keyboard |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies or explicit manual-only justification
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (test target creation, protocol extraction)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s for unit tier
- [ ] Two-device manual QA checklist signed off by tester (date + devices used recorded)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
