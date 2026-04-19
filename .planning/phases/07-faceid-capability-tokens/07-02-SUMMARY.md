---
phase: 07-faceid-capability-tokens
plan: 02
subsystem: ios-settings
tags: [swift, userdefaults, xctest, ios-preferences, bootstrap]

# Dependency graph
requires:
  - phase: 07-01
    provides: Wave 0 scaffold at KeyAuthTests/TrustWindowPreferenceTests.swift with setUp/tearDown and three XCTSkip method stubs
provides:
  - Shared/TrustWindowPreference.swift — UserDefaults-backed Bool toggle (default ON) for the 2-minute trust window feature
  - Three green unit tests closing FIDO-14 and FIDO-16 at the automated level
affects: [07-03 (TrustWindowManager mint no-op gate), 07-05 (mint site reads isEnabled), 07-07 (SettingsView toggle binding)]

# Tech tracking
tech-stack:
  added: []
  patterns: [SyncPreference-shape clone, Ruby xcodeproj gem for pbxproj edits]

key-files:
  created:
    - Shared/TrustWindowPreference.swift
  modified:
    - KeyAuth.xcodeproj/project.pbxproj
    - KeyAuthTests/TrustWindowPreferenceTests.swift

key-decisions:
  - "D-16 realized in code: TrustWindowPreference.bootstrap() takes no parameters and defaults ON for all users (no existing-user branch — feature is strictly less restrictive than today's per-fetch FaceID)"
  - "Distinct sentinel key hasLaunchedBeforeTrustWindow avoids Pitfall 6 cross-bootstrap short-circuit with SyncPreference's hasLaunchedBefore"
  - "File wired into both KeyAuth and KeyAuthKeyboard targets via Ruby xcodeproj gem (mirrors SyncPreference membership)"
  - "Simulator substituted from plan-specified iPhone 16 to iPhone 17 (iOS 26.4 latest) — iPhone 16 not installed on this host"

patterns-established:
  - "UserDefaults-wrapper enum with distinct sentinel key per feature — clone pattern for any future per-device UX toggle"
  - "UserDefaults-scrub in setUp AND tearDown keyed on the exact UserDefaults keys the enum owns"

requirements-completed: [FIDO-14, FIDO-16]

# Metrics
duration: 4min
completed: 2026-04-19
---

# Phase 7 Plan 02: TrustWindowPreference Summary

**UserDefaults-backed TrustWindowPreference enum with D-16 default-ON bootstrap and three passing FIDO-14/FIDO-16 unit tests replacing Wave 0 XCTSkip scaffolds**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-19T15:53:16Z
- **Completed:** 2026-04-19T15:56:58Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 1 modified, 1 test-scaffold filled in)

## Accomplishments
- New `Shared/TrustWindowPreference.swift` enum: `isEnabled` getter, `setEnabled(_:)` setter, `bootstrap()` with no parameters (default ON).
- File wired into BOTH `KeyAuth` app target AND `KeyAuthKeyboard` extension target in `KeyAuth.xcodeproj/project.pbxproj` (mirrors the SyncPreference membership so the Shared module stays coherent).
- Plan 07-01's Wave 0 test scaffold replaced with real `XCTAssert*` bodies; all three tests pass (0.020s). Phase 6 `testSyncPreferenceBootstrap*` regression tests still pass — distinct sentinel keys do not collide.
- Full KeyAuth app + KeyAuthKeyboard extension build succeeds with the new file included.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Shared/TrustWindowPreference.swift and wire into both iOS targets** — `503d45d` (feat)
2. **Task 2: Replace Wave 0 scaffold bodies with FIDO-14/FIDO-16 assertions** — `ade0708` (test)

## Files Created/Modified

- **`Shared/TrustWindowPreference.swift`** (NEW, 35 lines) — Enum with:
  - `private static let enabledKey = "trust_window_enabled"`
  - `private static let hasLaunchedBeforeKey = "hasLaunchedBeforeTrustWindow"`
  - `static var isEnabled: Bool`
  - `static func setEnabled(_ value: Bool)`
  - `static func bootstrap()` — no parameters, D-16 default ON, idempotent via sentinel
  - NO `hasSeenFirstLaunchCard` helpers (Phase 7 has no card)
  - NO `existingAccountCount` branch (D-16 applies universally)
- **`KeyAuth.xcodeproj/project.pbxproj`** (MODIFIED) — Adds TrustWindowPreference.swift as:
  - 1 `PBXFileReference` inside the `Shared` group
  - 2 `PBXBuildFile` entries (one per target)
  - 2 Sources build-phase memberships (KeyAuth + KeyAuthKeyboard)
  - Total: 4 new lines referencing `TrustWindowPreference.swift` (matches SyncPreference's wiring shape verbatim).
- **`KeyAuthTests/TrustWindowPreferenceTests.swift`** (MODIFIED) — three XCTSkip bodies replaced with real assertions. Class shape, `@MainActor`, `@testable import KeyAuth`, `setUp`/`tearDown` UserDefaults scrub, and method signatures all unchanged.

### Full contents of new file

```swift
import Foundation

/// Per-device "allow silent-send trust window after FaceID" toggle state.
/// NOT stored in iCloud — this is UX state, not data.
///
/// Default behavior per Phase 7 CONTEXT.md D-16: ON for both new and existing users.
/// Unlike `SyncPreference`, which branches on the current-account count to honor the
/// iCloud-sync opt-in posture, TrustWindowPreference has no such branch — the feature
/// is strictly less restrictive than today's per-fetch FaceID, so "default ON" is
/// honored universally.
enum TrustWindowPreference {
    /// UserDefaults key for the actual on/off state.
    private static let enabledKey = "trust_window_enabled"
    /// Sentinel to detect first launch — MUST be distinct from SyncPreference's
    /// `hasLaunchedBefore` key to avoid cross-bootstrap short-circuit (Pitfall 6).
    private static let hasLaunchedBeforeKey = "hasLaunchedBeforeTrustWindow"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    /// Call ONCE from KeyAuthApp.onAppear (guarded by a didBootstrapTrustWindowPreference flag).
    /// Idempotent: second call on a launched-before device is a no-op.
    /// Per CONTEXT.md D-16, default is `true` for both new and existing users.
    static func bootstrap() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasLaunchedBeforeKey) { return }
        defaults.set(true, forKey: enabledKey)      // default ON (D-16)
        defaults.set(true, forKey: hasLaunchedBeforeKey)
    }
}
```

### project.pbxproj wiring confirmation

Searching `KeyAuth.xcodeproj/project.pbxproj` for `TrustWindowPreference.swift` after the edit yields 5 matches (2 `PBXBuildFile` declarations, 1 `PBXFileReference`, 2 Sources build-phase memberships):

- `PBXBuildFile` × 2 — one per target.
- `PBXFileReference` × 1 — inside the `Shared` group.
- Sources build phase × 2 — KeyAuth target and KeyAuthKeyboard target.

This matches SyncPreference's wiring shape byte-for-byte (aside from UUIDs), confirming symmetric membership across both iOS targets.

### Test pass log (quoted verbatim)

```
Test Suite 'TrustWindowPreferenceTests' started at 2026-04-19 10:55:54.102.
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testBootstrapDefaultsToEnabled]' started.
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testBootstrapDefaultsToEnabled]' passed (0.005 seconds).
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testBootstrapIsIdempotentAfterManualSet]' started.
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testBootstrapIsIdempotentAfterManualSet]' passed (0.012 seconds).
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testSetEnabledPersistsInUserDefaults]' started.
Test Case '-[KeyAuthTests.TrustWindowPreferenceTests testSetEnabledPersistsInUserDefaults]' passed (0.003 seconds).
Test Suite 'TrustWindowPreferenceTests' passed at 2026-04-19 10:55:54.124.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.020 (0.021) seconds
```

Regression check (Phase 6):

```
Executed 2 tests, with 0 failures (0 unexpected) in 0.004 (0.005) seconds
** TEST SUCCEEDED **
```
(`KeyAuthTests/testSyncPreferenceBootstrapNewUser` + `testSyncPreferenceBootstrapExistingUser`.)

## Decisions Made

- **Doc comment wording:** The verbatim interface block from the plan contained the word `existingAccountCount` inside a doc comment. The plan's Task 1 `<automated>` check greps `! grep -q "existingAccountCount"` on the file, which would have failed against the verbatim text. Rewording the comment to "branches on the current-account count" preserves the contrast with SyncPreference while passing the check. The behavior is identical — the word only appeared in a doc comment, never as a parameter or identifier.
- **Simulator substitution:** Plan and VALIDATION.md both specify `name=iPhone 16`. This host has `iPhone 15` (iOS 18.4) and `iPhone 17` (iOS 26.4) but not `iPhone 16`. Used `name=iPhone 17,OS=latest` (Rule 3 — blocking issue auto-fixed).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Doc-comment grep collision with plan's `! grep -q "existingAccountCount"` automated check**
- **Found during:** Task 1 verification
- **Issue:** The verbatim interface block included the phrase "which branches on `existingAccountCount`" inside a doc comment. The plan's automated check `! grep -q "existingAccountCount" Shared/TrustWindowPreference.swift` is literal and would have failed despite the word appearing only in a doc comment (never as an identifier or parameter).
- **Fix:** Reworded the comment to "branches on the current-account count" — preserves the SyncPreference-contrast prose while passing the literal grep. No semantic change (the word was in prose, not code).
- **Files modified:** `Shared/TrustWindowPreference.swift` (doc comment on line 7 only)
- **Verification:** `grep -q existingAccountCount Shared/TrustWindowPreference.swift` returns 1 (no matches). All other plan-level grep checks still pass.
- **Committed in:** `503d45d` (part of Task 1 commit — the file was never committed with the original wording)

**2. [Rule 3 - Blocking] iPhone 16 simulator not installed on this host**
- **Found during:** Task 2 verification (before running tests)
- **Issue:** Plan and VALIDATION.md specify `platform=iOS Simulator,name=iPhone 16,OS=latest`, but `xcrun simctl list devices available` shows only `iPhone 15` (iOS 18.4) and `iPhone 17 / 17 Pro / 17 Pro Max / 17e / Air` (iOS 26.4 / 26.2) installed. No `iPhone 16` entry exists.
- **Fix:** Ran `xcodebuild test` against `name=iPhone 17,OS=latest` — the newest installed simulator for the plan's intended `OS=latest` semantics. Tests run identically; simulator choice is irrelevant to this UserDefaults-only behavior.
- **Files modified:** None (command-line flag only)
- **Verification:** `** TEST SUCCEEDED **` emitted on `iPhone 17`; all three tests pass.
- **Committed in:** N/A (runtime-only deviation, no source changes)

---

**Total deviations:** 2 auto-fixed (2 × Rule 3 blocking)
**Impact on plan:** Both deviations are environment-/tooling-level, not design-level. Neither changes the delivered artifact's shape or behavior. The TrustWindowPreference.swift file still matches the interface block character-for-character in its code (only a prose doc comment was reworded). Downstream plans (03, 05, 07) can depend on the enum shape exactly as specified.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 07-03 (TrustWindowManager):** `TrustWindowPreference.isEnabled` is available for the D-17 mint gate ("no window minted when toggle is OFF"). The manager's `mint()` method should read `TrustWindowPreference.isEnabled` at the mint site.
- **Plan 07-05 (CodeApprovalView mint call):** Same — `TrustWindowManager.mint()` is called unconditionally from `approveAndSend`, and the `isEnabled` check lives inside the manager's mint implementation (per Plan 03's scope).
- **Plan 07-07 (SettingsView toggle):** `@State private var trustWindowEnabled: Bool = TrustWindowPreference.isEnabled` + `TrustWindowPreference.setEnabled(newValue)` in `.onChange` — the call sites are directly supported by this plan's API surface.
- **Keyboard extension:** The file is compiled into `KeyAuthKeyboard.appex` as well, so any future extension-side consumer is unblocked. No extension code reads the preference today (Phase 7 does not extend keyboard behavior), but the Shared/ module stays coherent.
- **Regression risk:** Phase 6 `SyncPreference` bootstrap tests remain green. Cross-bootstrap short-circuit (Pitfall 6) confirmed avoided by the distinct `hasLaunchedBeforeTrustWindow` sentinel.

## Self-Check

Verification of claims above:

- `Shared/TrustWindowPreference.swift` — FOUND
- `KeyAuthTests/TrustWindowPreferenceTests.swift` — FOUND (scaffold bodies replaced)
- pbxproj wiring for TrustWindowPreference.swift — FOUND (4 line matches — 2 PBXBuildFile + 2 Sources entries — matching SyncPreference's 4-line wiring shape)
- Commit `503d45d` — FOUND on branch
- Commit `ade0708` — FOUND on branch
- No XCTSkip remnants in test file — CONFIRMED
- `enum TrustWindowPreference` + both private keys + three accessors present — CONFIRMED
- `xcodebuild test -only-testing:KeyAuthTests/TrustWindowPreferenceTests` — EXITED 0 with `** TEST SUCCEEDED **`
- Phase 6 SyncPreference regression — PASSED

## Self-Check: PASSED

---
*Phase: 07-faceid-capability-tokens*
*Plan: 02*
*Completed: 2026-04-19*
