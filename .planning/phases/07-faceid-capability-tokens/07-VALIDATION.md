---
phase: 7
slug: faceid-capability-tokens
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-19
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (KeyAuthTests target — wired in Phase 6) |
| **Config file** | KeyAuth.xcodeproj |
| **Quick run command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyAuthTests/TrustWindowManagerTests` |
| **Full suite command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~30 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `quick run command` for the task's target test class
- **After every plan wave:** Run `full suite command`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

> Filled by planner during PLAN.md generation. Each task in PLAN.md should map to one row here.
> Use REQ-IDs from FIDO-01..FIDO-19 (see RESEARCH.md §Suggested REQ-ID Breakdown).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | FIDO-01 | T-7-01 | TBD | unit | TBD | ❌ W0 | ⬜ pending |

---

## Wave 0 Requirements

> Test scaffolds the planner must include in Wave 0. Populated from RESEARCH.md §Validation Architecture.

- [ ] `KeyAuthTests/TrustWindowManagerTests.swift` — stubs for FIDO-01..FIDO-08 (mint, expiry, revocation triggers)
- [ ] `KeyAuthTests/RelayClientSilentSendTests.swift` — stubs for FIDO-09..FIDO-13 (silent-send branch, account resolution)
- [ ] `KeyAuthTests/TrustWindowPreferenceTests.swift` — stubs for FIDO-16..FIDO-17 (settings toggle)
- [ ] `KeyAuthTests/Fixtures/TrustWindowFixtures.swift` — shared fixtures (mock clock, mock ICloudStateObserver)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Toast appears on physical device | FIDO-09 | SwiftUI `.overlay` rendering only verifies in simulator/device | Pair extension, request code, FaceID-approve, request again within 2 min, observe toast |
| FaceID prompt skip on second send | FIDO-01 | LAContext UI prompt cannot be asserted in unit tests | Same as above; visually confirm no FaceID prompt appears for second send |
| App background instantly revokes window | FIDO-05 | UIApplication lifecycle requires real app | Approve, swipe up to home screen, foreground, request code → must re-prompt FaceID |
| Toggle OFF disables window entirely | FIDO-17 | UI interaction + cross-launch state | Toggle OFF in Settings, approve, request again → must re-prompt FaceID |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
