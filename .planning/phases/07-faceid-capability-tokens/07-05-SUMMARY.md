---
phase: 07-faceid-capability-tokens
plan: 05
subsystem: ui
tags: [swiftui, trust-window, transient-toast, xcodeproj, timer-removal, faceid]

# Dependency graph
requires:
  - phase: 07-faceid-capability-tokens Plan 03
    provides: TrustWindowManager.shared singleton with mint() / isInWindow / showToast API and self-guard via TrustWindowPreference.isEnabled
  - phase: 07-faceid-capability-tokens Plan 02
    provides: TrustWindowPreference UserDefaults wrapper (the guard consulted by mint())
  - phase: 06-icloud-keychain-sync Plan 06
    provides: Reusable TransientToastOverlay component (Phase 6 authored but never mounted)
  - phase: 06-icloud-keychain-sync Plan 04
    provides: "Copy Shared Sources For Isolation Tests" Run-Script build phase pattern (established Ruby xcodeproj edit convention)
provides:
  - Parameterized TransientToastOverlay with `duration: Double = 3.0` default, enabling Phase 7's 2.0s silent-send caller (FIDO-12)
  - Post-FaceID trust-window mint at the single canonical site inside CodeApprovalView.approveAndSend (FIDO-08 / D-01)
  - Full deletion of the 5-minute startAutoRefresh Timer — method body + caller both removed (FIDO-13 / D-12)
  - CodeApprovalView.swift copied into KeyAuthTests test bundle as CodeApprovalView.swift.txt, unblocking Plan 07-08 grep assertions
affects: [07-06-PLAN, 07-07-PLAN, 07-08-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SwiftUI View with explicit memberwise init that adds a defaulted parameter while preserving source-compat for existing callers"
    - "PBXShellScriptBuildPhase edit via Ruby xcodeproj gem — loop-header substitution + inputPaths/outputPaths append (carries Phase 6 Plan 06-04 convention forward)"

key-files:
  created: []
  modified:
    - App/Views/TransientToastOverlay.swift
    - App/Views/CodeApprovalView.swift
    - KeyAuth.xcodeproj/project.pbxproj

key-decisions:
  - "mint() placed AFTER sendEncryptedCode (per plan interfaces + threat model T-7-10), not before — both orderings are functionally equivalent since authenticate-success is already guard-gated, but the plan's explicit ordering was preserved to keep the threat-model assertion valid"
  - "Did NOT wrap mint() in `if TrustWindowPreference.isEnabled { ... }` at the call site — mint() self-guards via `guard TrustWindowPreference.isEnabled else { return }` at TrustWindowManager.swift:86, making an outer guard redundant (plan interfaces block line 147-149 makes this explicit)"
  - "Used the explicit-init form (option b from plan) for TransientToastOverlay.duration — avoids any memberwise-init ambiguity across Swift toolchains and makes the default parameter documentation crystal-clear at the init site"
  - "Removed the word 'startAutoRefresh' from the replacement comment to honor FIDO-13 grep-zero semantics (the success criterion checks App/ broadly, not just non-comment occurrences)"
  - "Used iPhone 17 simulator instead of iPhone 16 because no iPhone 16 simulator was available on the executor host (commit destination was verified for -latest OS only)"

patterns-established:
  - "Pattern: defaulted stored property via explicit init — preserves source-compat for existing call sites while introducing a new parameter"
  - "Pattern: Run-Script loop extension for PBXShellScriptBuildPhase — shell loop header substitution via Ruby xcodeproj `sub()` instead of regenerating the whole script from scratch, keeps the diff minimal"

requirements-completed: [FIDO-08, FIDO-12, FIDO-13]

# Metrics
duration: 4min
completed: 2026-04-19
---

# Phase 07 Plan 05: TransientToastOverlay duration + CodeApprovalView mint + delete Timer + Run-Script extension

**Parameterized the silent-send toast to 2s-capable, wired the 2-minute trust-window mint into the FaceID approval path, deleted the 5-minute auto-refresh Timer (36 LOC gone), and extended the KeyAuthTests Run-Script so Plan 07-08 can grep-assert the deletion.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-19T16:11:00Z
- **Completed:** 2026-04-19T16:14:27Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- **FIDO-12 — TransientToastOverlay.duration parameterized:** Added explicit init with `duration: Double = 3.0` default. The hardcoded `.now() + 3.0` deadline became `.now() + duration`. Phase 6 callers continue to compile unchanged; Phase 7's silent-send caller (Plan 07-07) will pass `duration: 2.0`.
- **FIDO-08 / D-01 — mint() wired at the canonical site:** `TrustWindowManager.shared.mint()` now fires inside `CodeApprovalView.approveAndSend` after `guard success` (line 186-189) and after `sendEncryptedCode` (line 193), exactly where the plan interfaces block and threat register T-7-10 lock it. mint() self-guards via `TrustWindowPreference.isEnabled` inside `TrustWindowManager.swift:86`, so no redundant outer guard was added.
- **FIDO-13 / D-12 — Timer fully removed:** The 36-line `startAutoRefresh(account:)` private method and its single call site both deleted. Grep across App/ and Shared/ returns zero matches for `startAutoRefresh` — the Phase 7 FIDO-13 requirement.
- **Test-bundle source copy extended:** `App/Views/CodeApprovalView.swift` added to the existing "Copy Shared Sources For Isolation Tests" Run-Script build phase. Verified end-to-end: the built test bundle now contains `CodeApprovalView.swift.txt` with zero `startAutoRefresh` hits and one `TrustWindowManager.shared.mint` hit. Plan 07-08's grep-based tests can now read the source inside the simulator sandbox.
- **Zero regressions:** Full KeyAuthTests suite passes — 83 tests executed, 4 skipped, 0 failures.

## Task Commits

Each task committed atomically:

1. **Task 1: Parameterize TransientToastOverlay** — `f755402` (feat)
2. **Task 2: Delete startAutoRefresh + insert mint() call** — `1060918` (feat)
3. **Task 3: Extend Run-Script to copy CodeApprovalView.swift** — `a10a63c` (chore)

(Plan metadata commit will be produced by this SUMMARY.md write + git add below.)

## Files Created/Modified

- `App/Views/TransientToastOverlay.swift` — Added explicit init with `duration: Double = 3.0` stored property; replaced hardcoded `.now() + 3.0` asyncAfter deadline with `.now() + duration`.
- `App/Views/CodeApprovalView.swift` — Inside `approveAndSend`: replaced `startAutoRefresh(account: account)` call with `TrustWindowManager.shared.mint()`. Deleted the entire 36-line `startAutoRefresh(account:)` private method.
- `KeyAuth.xcodeproj/project.pbxproj` — Extended the `PBXShellScriptBuildPhase` named "Copy Shared Sources For Isolation Tests" in the KeyAuthTests target: added `$(SRCROOT)/App/Views/CodeApprovalView.swift` to `inputPaths`, added `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/CodeApprovalView.swift.txt` to `outputPaths`, and extended the shell-script Views loop to include `CodeApprovalView.swift`.

## Decisions Made

- **mint() placement and self-guard:** Followed the plan's interfaces block (mint after sendEncryptedCode, no outer `TrustWindowPreference.isEnabled` guard). The plan explicitly documents that mint() is self-guarded (comment at the replacement site cites FIDO-03 / D-17 gate inside TrustWindowManager.mint). The prompt's "Wrap in `if TrustWindowPreference.isEnabled { ... }`" was treated as a functional guideline already satisfied by the self-guard; placing the outer guard would create dead code and diverge from the plan interfaces block + threat model T-7-10's post-sendEncryptedCode ordering assertion.
- **Explicit init vs implicit memberwise init for `duration`:** Chose the explicit-init form (plan option b). This removes any risk of a toolchain-specific memberwise-init issue and makes the default parameter's role self-documenting at the init declaration.
- **Replacement comment wording:** The initial comment said "Replaces the deleted `startAutoRefresh(account: account)` Timer call (D-12)." — but the plan success criterion and FIDO-13 require the string `startAutoRefresh` to NOT appear anywhere in `App/`. Rephrased to "Replaces the deleted 5-minute auto-refresh Timer (D-12)." so grep returns zero, preserving the FIDO-13 semantics end-to-end.
- **Simulator destination:** iPhone 16 was unavailable on the executor host; used iPhone 17 (available with -latest OS). Both builds and tests succeeded.

## Deviations from Plan

None — plan executed exactly as specified.

The only notable micro-adjustments were:

- Rephrasing the replacement comment to avoid the literal word "startAutoRefresh" (honors FIDO-13 grep-zero — this is a strict reading of the success criterion, not a deviation).
- Using iPhone 17 simulator instead of iPhone 16 (the plan's build commands reference iPhone 16, but that device is not installed on this host; iPhone 17 with latest OS builds and tests succeed identically).

## Issues Encountered

None. All three tasks completed on first attempt. Single post-edit grep showed the word `startAutoRefresh` still present in a replacement comment; edited the comment to remove it and re-verified zero occurrences.

## Verification

- `xcodebuild build` (iPhone 17 simulator, latest OS): `** BUILD SUCCEEDED **` after Task 1 and Task 2.
- `xcodebuild test -only-testing:KeyAuthTests` (iPhone 17 simulator, latest OS) after Task 3: `** TEST SUCCEEDED **` — 83 tests executed, 4 skipped, 0 failures.
- `grep -c "startAutoRefresh" App/Views/CodeApprovalView.swift` → `0`
- `grep -rn "startAutoRefresh" App/ Shared/` → zero matches (FIDO-13 requirement satisfied)
- `grep -n "TrustWindowManager.shared.mint()" App/Views/CodeApprovalView.swift` → `201: TrustWindowManager.shared.mint()` (single occurrence, post-sendEncryptedCode as required by T-7-10)
- `grep -n "let duration: Double" App/Views/TransientToastOverlay.swift` → `20: let duration: Double`
- `grep -n "deadline: .now() + duration" App/Views/TransientToastOverlay.swift` → `54: DispatchQueue.main.asyncAfter(deadline: .now() + duration) {`
- Build artifact check: `$DERIVED_DATA/.../KeyAuthTests.xctest/CodeApprovalView.swift.txt` exists; grep of that file shows zero `startAutoRefresh` and one `TrustWindowManager.shared.mint` — Plan 07-08 grep tests will pass end-to-end.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 07-04 (parallel wave 4 — different agent):** This plan did NOT touch `Shared/RelayClient.swift`, `Shared/AccountStore.swift`, or `KeyAuthTests/RelayClientSilentSendTests.swift`. The two plans land cleanly into the same wave.
- **Plan 07-06:** Will wire the `RelayClient.shared.accountResolver` closure inside KeyAuthApp.onAppear. No dependency on this plan's surface beyond the already-minted window.
- **Plan 07-07:** Will mount `TransientToastOverlay` on `ContentView.body` driven by `TrustWindowManager.pendingToast`, passing `duration: 2.0`. This plan unblocked that caller by adding the `duration` parameter.
- **Plan 07-08:** Will add grep tests over `CodeApprovalView.swift.txt` in the test bundle asserting (a) `TrustWindowManager.shared.mint()` present, (b) `startAutoRefresh` absent. Both assertions are already true of the current source — Task 3 made them reachable from inside the test sandbox.

No blockers, no concerns.

## Self-Check: PASSED

- All claimed files exist on disk (TransientToastOverlay.swift, CodeApprovalView.swift, project.pbxproj, 07-05-SUMMARY.md).
- All claimed commit hashes exist in `git log --all` (f755402, 1060918, a10a63c).
- Full KeyAuthTests suite: 83 tests passed, 4 skipped, 0 failures.
- grep assertions (FIDO-13 zero-match, FIDO-08 one-match, FIDO-12 duration present) all pass in both source and bundled `.swift.txt` artifacts.

---
*Phase: 07-faceid-capability-tokens*
*Completed: 2026-04-19*
