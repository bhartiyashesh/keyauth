---
phase: 7
slug: faceid-capability-tokens
status: complete
nyquist_compliant: true
wave_0_complete: true
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
| **Quick run command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeyAuthTests/TrustWindowManagerTests` |
| **Full suite command** | `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeyAuthTests` |
| **Estimated runtime** | ~30 seconds (full) |

> Note: Plans executed on a host without the iPhone 16 simulator. iPhone 17 with `OS=latest` is the sanctioned substitute (see Plan 07-01 SUMMARY.md Decisions). Any iOS 16+ simulator is permitted.

---

## Sampling Rate

- **After every task commit:** Run `quick run command` for the task's target test class
- **After every plan wave:** Run `full suite command`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

> One row per FIDO-NN — completed automated coverage from Plans 07-01..07-08.
> Task IDs follow the `7-{plan}-{ordinal}` pattern aligned to each plan's task ordering.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-03-01 | 03 | 2 | FIDO-01 | T-7-07b | isInWindow=false on init | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testInitialState_isInWindowIsFalse | ✅ | ✅ pass |
| 7-03-02 | 03 | 2 | FIDO-02 | — | mint sets 120s expiry | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testMintSetsExpiryTo120sFromNow | ✅ | ✅ pass |
| 7-03-03 | 03 | 2 | FIDO-03 | T-7-06 | mint no-op when pref OFF | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testMintNoOpWhenPreferenceDisabled | ✅ | ✅ pass |
| 7-03-04 | 03 | 2 | FIDO-04 | — | re-mint replaces (fresh 120s) | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testReMintReplacesExpiry | ✅ | ✅ pass |
| 7-03-05 | 03 | 2 | FIDO-05 | — | lazy expiry check | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testIsInWindowLazyExpiryCheck | ✅ | ✅ pass |
| 7-03-06 | 03 | 2 | FIDO-06 | T-7-03 | background revokes | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testBackgroundNotificationRevokes | ✅ | ✅ pass |
| 7-03-07 | 03 | 2 | FIDO-07 | T-7-04 | iCloud change revokes | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testICloudAccountChangeRevokes | ✅ | ✅ pass |
| 7-08-01 | 08 | 6 | FIDO-08 | T-7-10 | mint after authenticate | grep | xcodebuild test -only-testing:KeyAuthTests/CodeApprovalViewTests/testMintCallAppearsAfterAuthenticateSuccess | ✅ | ✅ pass |
| 7-04-01 | 04 | 3 | FIDO-09 | T-7-01 | silent send in window | unit | xcodebuild test -only-testing:KeyAuthTests/RelayClientSilentSendTests/testSilentSendInWindow | ✅ | ✅ pass |
| 7-04-02 | 04 | 3 | FIDO-10 | — | ambiguous defers to FaceID | unit | xcodebuild test -only-testing:KeyAuthTests/RelayClientSilentSendTests/testAmbiguousResolutionSetsPendingCodeRequest | ✅ | ✅ pass |
| 7-03-08 | 03 | 2 | FIDO-11 | — | toast text for matched issuer | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testToastTextForMatchedIssuer | ✅ | ✅ pass |
| 7-03-09 | 03 | 2 | FIDO-12 | — | toast auto-dismiss 2s | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testToastAutoDismissAfter2s | ✅ | ✅ pass |
| 7-08-02 | 08 | 6 | FIDO-13 | T-7-13 | startAutoRefresh deleted | grep | xcodebuild test -only-testing:KeyAuthTests/CodeApprovalViewTests/testStartAutoRefreshIsAbsent | ✅ | ✅ pass |
| 7-02-01 | 02 | 1 | FIDO-14 | T-7-06 | setEnabled persists | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowPreferenceTests/testSetEnabledPersistsInUserDefaults | ✅ | ✅ pass |
| 7-07-01 | 07 | 5 | FIDO-15 | T-7-CR1 | toggle label verbatim | grep | xcodebuild test -only-testing:KeyAuthTests/SettingsViewTests/testTrustWindowToggleLabelMatchesUISpec | ✅ | ✅ pass |
| 7-02-02 | 02 | 1 | FIDO-16 | — | bootstrap defaults ON | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowPreferenceTests/testBootstrapDefaultsToEnabled | ✅ | ✅ pass |
| 7-03-10 | 03 | 2 | FIDO-17 | T-7-07b | not persisted across launches | unit | xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests/testSingletonStateIsNotPersisted | ✅ | ✅ pass |
| 7-QA-01 | 08 | 6 | FIDO-18 | T-7-08 | toast visible above ContentView | manual | 07-QA-CHECKLIST.md 2-DEV-TW-01 | ⚠ QA | ⏳ pending |
| 7-QA-02 | 08 | 6 | FIDO-19 | — | extension source unchanged | manual | 07-QA-CHECKLIST.md 2-DEV-TW-02 | ⚠ QA | ⏳ pending |

---

## Wave 0 Requirements

> Test scaffolds the planner must include in Wave 0. Populated from RESEARCH.md §Validation Architecture.

- [x] `KeyAuthTests/TrustWindowManagerTests.swift` — stubs for FIDO-01..FIDO-08 (mint, expiry, revocation triggers)
- [x] `KeyAuthTests/RelayClientSilentSendTests.swift` — stubs for FIDO-09..FIDO-13 (silent-send branch, account resolution)
- [x] `KeyAuthTests/TrustWindowPreferenceTests.swift` — stubs for FIDO-16..FIDO-17 (settings toggle)
- [x] KeyAuthTests/Fixtures/CodeRequestFixtures.swift — shared CodeRequest factory (mock clock and ICloudStateObserver mocking are handled inline via injected closures + existing DEBUG hooks; no dedicated fixture file needed for those)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Toast appears on physical device | FIDO-18 | SwiftUI `.overlay` rendering only verifies in simulator/device | See 07-QA-CHECKLIST.md §2-DEV-TW-01 |
| Chrome extension source unchanged | FIDO-19 | Cross-source diff check, not a runtime assertion | See 07-QA-CHECKLIST.md §2-DEV-TW-02 |
| FaceID prompt skip on second send | FIDO-01 | LAContext UI prompt cannot be asserted in unit tests | Pair extension, request code, FaceID-approve, request again within 2 min, observe no second FaceID prompt (covered under 2-DEV-TW-01 step 6) |
| Toggle OFF disables window entirely | FIDO-03 / FIDO-15 | UI interaction + cross-launch state | See 07-QA-CHECKLIST.md §2-DEV-TW-03 (optional) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

Approval: complete
