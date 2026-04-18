---
phase: 06-icloud-keychain-sync
plan: 06
subsystem: phase-validation-gate
tags: [validation, traceability, qa-checklist, two-device, xctest, keyboard-propagation, phase-gate]

requires:
  - plan: 06-05
    provides: "Full phase implementation (MigrationCoordinator + RestoringFromCloudView + AccountStore two-phase dedup + SettingsView stubs replaced); 61-test green baseline; RestoringStateTests providing ICLOUD-16 unit baseline (Blocker-3 resolution); TransientToastOverlay defined but unplaced"
  - plan: 06-04
    provides: "SettingsView with D-05/D-06 dialog copy; FirstLaunchSyncCard; gear toolbar; TransientToastOverlay primitive"
  - plan: 06-03
    provides: "AccountStore with KVS observer; ICloudStateObserver; SyncPreference.bootstrap"
  - plan: 06-02
    provides: "Sync-aware KeychainManager; 11 KeychainManagerSyncTests"
  - plan: 06-01
    provides: "KeyAuthTests target wired as TestableReference in KeyAuth scheme; DedupKey + SyncPreference primitives; MockKeychain + AccountFixtures test harness"

provides:
  - ".planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md — Two-device manual QA checklist with 8 test cases (2-DEV-01..08), tester/device/Apple ID metadata header, setup preconditions, per-test preconditions/steps/expected/result fields, Overall Phase Gate sign-off, SC-1..SC-6 cross-reference table. Verbatim UI copy for D-05 (Merged N, Accounts on this iPhone stay), D-06 (Stop syncing this device), D-09 (Restoring your accounts from iCloud…), D-11 (iCloud Keychain is turned off on this device.), D-12 (iCloud Keychain was disabled — sync stopped., em dash)."
  - ".planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md — Requirement traceability audit. Automated Coverage table names 62+ specific XCTest methods across 10 suites covering all 16 ICLOUD-NN; Manual QA Coverage table maps 2-DEV-01..08 → ICLOUD-NN + SC; explicit Orphan Check section confirms no gaps; SC-1..SC-6 mapping section; Known Gaps & Follow-ups documents TransientToastOverlay placement deferral (not a coverage orphan); Risks Flagged section ties RESEARCH Open Questions to owner decisions including RESOLVED line-459 two-phase dedup via Plan 05 commit 028f091; Sign-off checklist enforces truth-in-claims."
  - "KeyAuthTests/KeyboardPropagationTests.swift — 5 XCTest cases covering ICLOUD-12 SharedDefaults propagation chain. testReloadWritesAccountsToSharedDefaults (reload → round-trip), testAddPropagatesToSharedDefaults (add path), testDeletePropagatesToSharedDefaults (delete path), testReloadAfterDedupWritesDedupedList (ICLOUD-12 ∧ ICLOUD-08), testReloadPreservesSortOrderInSharedDefaults (sort contract)."
  - ".planning/REQUIREMENTS.md — 16 ICLOUD-NN status rows updated per TRACEABILITY audit: 14 rows `Complete (automated)`; ICLOUD-10 `Complete (unit) / Manual QA pending 2-DEV-06`; ICLOUD-16 `Complete (unit: RestoringStateTests.testTimeoutTransition) / Manual QA pending 2-DEV-05` (truth-in-claims gate, Blocker 3 resolution). Checkboxes: 14 `[x]`, 2 `[ ]` (ICLOUD-10, ICLOUD-16 awaiting manual QA). Last-updated line documents delta."
  - "KeyAuth.xcodeproj/project.pbxproj — KeyboardPropagationTests.swift wired into KeyAuthTests target (4 entries: PBXBuildFile, PBXFileReference, KeyAuthTests group child, Sources build phase)."

affects: [phase-verification (orchestrator will decide whether Phase 6 can ship — 14/16 requirements pure-automated, 2/16 hybrid awaiting manual QA on real two-device setup)]

tech-stack:
  added:
    - "Manual QA checklist pattern with tester/device/Apple ID metadata fields, per-test preconditions/steps/expected/result blocks, Overall Phase Gate sign-off, and SC cross-reference — runnable by a tester with no ambient project context"
    - "Traceability audit pattern: Automated Coverage table (requirement → specific test methods), Manual QA Coverage table (QA case → requirements + SC), Orphan Check section, Known Gaps documentation for non-orphan deferrals, Risks Flagged → Open Questions resolution tracking, Sign-off checklist"
    - "Truth-in-claims gate: every 'Complete (unit)' claim names the specific test method by full name (e.g., `RestoringStateTests.testTimeoutTransition`) — regression-guards against unnamed coverage claims"
  patterns:
    - "Hybrid coverage status vocabulary: `Complete (automated)` for pure unit coverage, `Complete (unit) / Manual QA pending X` for cross-device behaviors that need real-iCloud verification, `Complete (unit: TestName) / Manual QA pending X` when the truth-in-claims gate demands a specific test mention"

key-files:
  created:
    - ".planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md — 254 lines, 8 two-device test cases"
    - ".planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md — ~100 lines, audit matrix + SC mapping + gaps + risks + sign-off"
    - "KeyAuthTests/KeyboardPropagationTests.swift — 95 lines, 5 XCTest cases covering ICLOUD-12"
  modified:
    - ".planning/REQUIREMENTS.md — 16 row status updates + 2 checkbox flips ([x]→[ ] for ICLOUD-10, ICLOUD-16) + Last-updated line delta"
    - "KeyAuth.xcodeproj/project.pbxproj — 4 pbxproj entries wiring KeyboardPropagationTests.swift into KeyAuthTests target"

key-decisions:
  - "Adopted hybrid status vocabulary (`Complete (automated)` vs `Complete (unit) / Manual QA pending 2-DEV-NN`) rather than a binary done/pending split. ICLOUD-10 and ICLOUD-16 have real unit baselines (scenePhase-triggered reload path and restoring-state timeout) but their END-TO-END contract requires cross-device observation that cannot be simulator-automated. Forcing them to 'Complete' would violate the truth-in-claims gate; forcing them to 'Pending' would erase the real unit coverage that was written. Hybrid is truthful."
  - "ICLOUD-16 row explicitly names `RestoringStateTests.testTimeoutTransition` rather than just 'Complete (unit)'. Prompted by Blocker 3 in the plan revision: previous phrasing 'Complete (unit) / Manual QA pending' without a named test method was indistinguishable from a fabricated coverage claim. Grep-verified both in REQUIREMENTS.md and TRACEABILITY.md."
  - "KeyboardPropagationTests uses `MockKeychain + injected AccountStore` rather than spawning a real keyboard extension process. Cross-process activation is not unit-testable; 2-DEV-01 step 5 (manual tester switches to KeyAuth keyboard and observes TOTP code) is the canonical SC-5 verification. Unit tests lock down the MAIN-APP side of the chain: any mutation to `AccountStore.accounts` writes to `SharedDefaults`."
  - "TransientToastOverlay placement deferred to a future polish plan. Core dedup behavior is tested via `AccountStore.lastDedupCount` and `DedupTests.testDedupLosersRemovedFromKeychain`; only the visual toast is unwired. Documented in TRACEABILITY.md 'Known Gaps' — NOT an orphan because ICLOUD-08 core behavior IS covered. 2-DEV-02 notes this caveat so the manual tester accepts `lastDedupCount == N` as the acceptance signal pending toast wiring."
  - "`MigrationTests.testStopSyncingFunctionDoesNotCallDeleteAllSynced` remains XCTSkipped on simulator sandbox (Plan 05 precedent — `#filePath` reads blocked). Runtime D-06 safety contract is still enforced by the paired `testStopSyncingPreservesLocalAndDoesNotDeleteSynced` (mock state assertion). TRACEABILITY.md documents this as a non-orphan, non-blocking known condition."
  - "QA checklist opens with 'How to run the automated suite first' paragraph referencing the `KeyAuth` scheme's TestableReference — reuses the corrected wording from 06-VALIDATION.md (Plan 06-01 revision) rather than introducing a new scheme name. Prompt explicitly required this."
  - "xcodebuild destination normalized to `iPhone 15 / OS 18.4` (only locally-available simulator) — matches all prior Plan 06-XX summaries. Plan's `<automated>` verify block specified `iPhone 16 / latest`; the iPhone-15 fallback is sanctioned by every prior-wave summary in the phase."

patterns-established:
  - "Phase-gate plan structure: (1) author manual QA checklist for cross-device behaviors, (2) close remaining unit gaps (KeyboardPropagationTests here), (3) author traceability audit proving no requirement orphans, (4) update REQUIREMENTS.md with specific coverage evidence, (5) final full-suite green run. Each step commits atomically so the audit trail is readable."
  - "Two-device QA checklist runnable without ambient knowledge: Run Record header captures tester + Apple ID + device metadata; Setup Preconditions; per-test preconditions block (not just steps); expected states with verbatim UI copy; result pass/fail + notes + observed-time capture fields; Overall Phase Gate sign-off; SC cross-reference table."
  - "Traceability-audit gap-handling: distinguish 'orphan' (requirement with NO coverage — blocks phase) from 'known gap' (requirement with coverage but a documented limitation — does NOT block phase). Use a Known Gaps & Follow-ups section for the latter; never silently expand a coverage claim to absorb a gap."

requirements-completed:
  - ICLOUD-12

duration: 6min wall-clock (rapid — phase-gate tasks are document-heavy, no new production code beyond the 95-line KeyboardPropagationTests file; dominated by the full-suite xcodebuild run at the end)
completed: 2026-04-18
---

# Phase 06 Plan 06: Phase Validation Gate Summary

**Delivered the phase's ship-gate artifacts: a two-device manual QA checklist with 8 tests covering the cross-device behaviors that CANNOT be unit-tested, a requirement traceability audit proving zero orphans across 16 ICLOUD-NN + 6 success criteria (with ICLOUD-16 explicitly crediting `RestoringStateTests.testTimeoutTransition` by name per Blocker 3 truth-in-claims), a new `KeyboardPropagationTests.swift` suite closing the unit-side of ICLOUD-12 with 5 tests on the SharedDefaults propagation chain, and REQUIREMENTS.md status updates using hybrid vocabulary (14/16 `Complete (automated)`, 2/16 `Complete (unit) / Manual QA pending 2-DEV-NN` for cross-device behaviors). Full suite: 61 → 66 tests passing, 1 skipped, 0 failures.**

## Performance

- **Duration:** ~6 min wall-clock
- **Started:** 2026-04-18T17:22:15Z
- **Completed:** 2026-04-18T17:28:51Z
- **Tasks:** 5 / 5 complete
- **Commits:** 4 (Tasks 1–4; Task 5 is verification-only, no file changes)
- **Files created:** 3
- **Files modified:** 2
- **Tests added:** 5 (KeyAuthTests suite: 61 → 66 passing, 1 skipped)

## Accomplishments

1. **Task 1 — 06-QA-CHECKLIST.md (`e6b10b6`)**

   - `.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md` — 254 lines. 8 two-device test cases `2-DEV-01..08` transcribed from RESEARCH.md § Testing Strategy with preconditions, steps, expected outcomes, pass/fail boxes, and notes fields per test.
   - Run Record header captures tester name, run date, Device A/B model + iOS version, last-4 of Apple ID, iCloud Keychain state on both, network conditions, and build commit SHA — so a run can be audit-reconstructed.
   - Setup Preconditions checklist gates the run.
   - Includes VERBATIM UI copy for the tester to visually verify: `"Merged 2 duplicate accounts"` (D-05 dedup toast), `"Stop syncing this device"` (D-06 default button), `"Remove from iCloud on all devices"` (D-05 destructive), `"Restoring your accounts from iCloud…"` (D-09, ellipsis character `…`), `"iCloud Keychain is turned off on this device."` (D-11), `"iCloud Keychain was disabled — sync stopped."` (D-12, em dash `—`).
   - Overall Phase Gate section with sign-off, tester signature field, and SC-1..SC-6 cross-reference table.
   - "How to run the automated suite first" opens the document referencing the `KeyAuth` scheme's TestableReference — reuses the VALIDATION.md wording corrected in Plan 06-01.

2. **Task 2 — KeyboardPropagationTests (`d869869`)**

   - `KeyAuthTests/KeyboardPropagationTests.swift` — 95 lines. 5 `@MainActor` XCTest cases:
     - `testReloadWritesAccountsToSharedDefaults` — seed 2 accounts → `store.reload()` → `SharedDefaults.loadAccounts()` returns 2 matching issuers.
     - `testAddPropagatesToSharedDefaults` — `store.add(account)` → `SharedDefaults` contains new id.
     - `testDeletePropagatesToSharedDefaults` — seed 1, delete, assert SharedDefaults empty.
     - `testReloadAfterDedupWritesDedupedList` — 3 dupes with different UUIDs but identical DedupKey → `SharedDefaults.loadAccounts().count == 1` (ICLOUD-12 ∧ ICLOUD-08).
     - `testReloadPreservesSortOrderInSharedDefaults` — seed Z(2), Y(1), X(0) → loadAccounts returns `[X, Y, Z]`.
   - Uses `MockKeychain` + `AccountStore(keychain: mock)` test harness. Cleans `SharedDefaults` + SyncPreference in setUp/tearDown.
   - Wired into KeyAuthTests target via 4 pbxproj entries (PBXBuildFile, PBXFileReference, group child, Sources build phase). UUIDs: `D9298754667C669455520CEF` (build file) and `3C42BF0A5EE050AFC308974F` (file reference), matching the 24-char uppercase-hex pattern established by prior plans.
   - Verification: `xcodebuild test -only-testing:KeyAuthTests/KeyboardPropagationTests` → 5/5 pass on iPhone 15 / OS 18.4 in 0.025s.

3. **Task 3 — 06-TRACEABILITY.md (`4f61e74`)**

   - `.planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md`. Automated Coverage table enumerates all 16 ICLOUD-NN rows, each citing specific XCTest method names from the 10 test suites (counts verified via Grep against the live test files, not approximated).
   - ICLOUD-16 row explicitly names `RestoringStateTests.testTimeoutTransition` (Blocker 3 truth-in-claims gate).
   - ICLOUD-10 row explicitly names `2-DEV-06` as the pending manual-QA case.
   - Manual QA Coverage table maps every `2-DEV-NN` to the ICLOUD-NN + SC it covers.
   - **Orphan Check** section explicitly asserts "No orphans detected. 14 of 16 requirements have pure automated coverage; 2 of 16 (ICLOUD-10, ICLOUD-16) have a named unit baseline PLUS a named manual-QA case."
   - SC-1..SC-6 mapping ties every success criterion to at least one automated test or manual QA case.
   - **Known Gaps & Follow-ups** section documents two non-orphan deferrals: (a) `TransientToastOverlay` placement deferred to a polish plan, but core behavior tested via `AccountStore.lastDedupCount`; (b) `testStopSyncingFunctionDoesNotCallDeleteAllSynced` XCTSkip on simulator sandbox, runtime behavior still enforced by paired test.
   - **Risks Flagged** section ties RESEARCH.md Open Questions to owner decisions, including the RESOLVED line-459 dedup safety (Plan 05 commit `028f091`, two-phase `AccountStore.dedupInMemory`).
   - Sign-off checklist enforces truth-in-claims and manual-QA gating.

4. **Task 4 — REQUIREMENTS.md status updates (`e9db687`)**

   - Updated 16 status rows in the traceability table:
     - 14 rows: `Complete` → `Complete (automated)` (ICLOUD-01, 02, 03, 04, 05, 06, 07, 08, 09, 11, 12, 13, 14, 15)
     - ICLOUD-10 row: `Complete` → `Complete (unit) / Manual QA pending 2-DEV-06`
     - ICLOUD-16 row: `Complete` → `Complete (unit: RestoringStateTests.testTimeoutTransition) / Manual QA pending 2-DEV-05`
   - Flipped checkboxes for ICLOUD-10 and ICLOUD-16 from `[x]` → `[ ]` (manual QA still required). 14 remain `[x]` (pure automated coverage).
   - Updated Last-updated line: "2026-04-18 — Phase 6 automated coverage complete (14 of 16 ICLOUD-NN `Complete (automated)`; ICLOUD-10 and ICLOUD-16 remain `Complete (unit) / Manual QA pending` for 2-DEV-06 and 2-DEV-05 respectively). ICLOUD-16 unit baseline provided by RestoringStateTests.testTimeoutTransition (Plan 06-05 Task 7)."

5. **Task 5 — Final full-suite green run (no file changes)**

   - `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' -only-testing:KeyAuthTests` → `** TEST SUCCEEDED **`
   - **66 tests executed, 1 skipped, 0 failures.** (Up from 61 → 66; delta = 5 new KeyboardPropagationTests.)
   - 10 test suites all green: `AccountStoreTests` (7), `DedupTests` (9), `ICloudStateObserverTests` (2), `KeyAuthTests` (5), `KeyboardPropagationTests` (5), `KeychainManagerSyncTests` (11), `MigrationTests` (7 — 1 skipped), `RestoringStateTests` (4), `SettingsViewTests` (12), `SyncScopeIsolationTests` (4).
   - Execution time: 0.897s total across all tests; 11.6s including simulator boot.
   - Log captured at `/tmp/keyauth-phase6-final.log` for audit reference.

## Task Commits

| Task | Description                                                      | Commit    | Files Changed |
| ---- | ---------------------------------------------------------------- | --------- | ------------- |
| 1    | docs(06-06): two-device manual QA checklist                      | `e6b10b6` | 1             |
| 2    | test(06-06): KeyboardPropagationTests for ICLOUD-12              | `d869869` | 2             |
| 3    | docs(06-06): requirement traceability audit (no orphans)         | `4f61e74` | 1             |
| 4    | docs(06-06): update REQUIREMENTS.md status per TRACEABILITY      | `e9db687` | 1             |
| 5    | (verification-only; no commit)                                   | —         | 0             |

Total: 4 task commits.

## Files Created / Modified

### Created
- `.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md` — 254 lines; 8 two-device test cases with metadata header, setup gate, per-test preconditions/steps/expected/result blocks, Overall Phase Gate sign-off, SC cross-reference.
- `.planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md` — audit matrix covering all 16 ICLOUD-NN + 8 2-DEV-NN + SC-1..SC-6; Orphan Check section; Known Gaps; Risks Flagged; Sign-off.
- `KeyAuthTests/KeyboardPropagationTests.swift` — 95 lines; 5 XCTest cases for ICLOUD-12 SharedDefaults propagation.

### Modified
- `.planning/REQUIREMENTS.md` — 16 status-row updates + 2 checkbox flips + Last-updated line delta.
- `KeyAuth.xcodeproj/project.pbxproj` — 4 pbxproj entries for KeyboardPropagationTests (PBXBuildFile, PBXFileReference, group child, Sources build phase).

## Deviations from Plan

None. Plan executed exactly as written.

- The iPhone-15 / OS-18.4 simulator substitution (vs the plan's `iPhone 16 / latest`) is not a deviation — every prior Plan 06-XX SUMMARY documents the same locally-available-only substitution. The full suite runs end-to-end green on iPhone 15.
- REQUIREMENTS.md grep threshold `>= 14` for `Complete (automated)` is satisfied by 15 occurrences (14 table rows + 1 mention in the Last-updated prose line). Both the row count and grep count match the plan's stated contract.

## Known Stubs

None. The plan did not call for any new stubs. KeyboardPropagationTests uses the real `MockKeychain` + real `AccountStore` — no mocks left as TODOs.

**Pre-existing stub documented as non-orphan in TRACEABILITY.md:** `TransientToastOverlay` (defined in Plan 06-04) is still unplaced in the view hierarchy. This is tracked in `06-TRACEABILITY.md` § Known Gaps & Follow-ups as a documented deferral, not a coverage gap. Core dedup-count behavior (which the toast would visualize) IS tested via `AccountStore.lastDedupCount` + `DedupTests.testDedupLosersRemovedFromKeychain`. Manual QA 2-DEV-02 notes this caveat.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. The plan is audit/traceability work on existing production code; no new trust boundaries.

## TDD Gate Compliance

Task 2 (KeyboardPropagationTests) is the only TDD-tagged task in this plan. The tests exercise existing production contracts (`AccountStore.reload/add/delete` → `SharedDefaults.saveAccounts`) that were already implemented in Plans 06-01..05. Since the implementation predates the tests, the GREEN-first commit order applies: the test file was added and passed immediately on the existing implementation. No RED cycle is warranted — this is coverage backfill of an already-correct chain, not a feature being driven.

## Plan-Level Invariant Checks

| Invariant | Required | Actual |
| --------- | -------- | ------ |
| `.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md` exists | pass | pass |
| QA checklist has 8 test sections `2-DEV-01..08` | pass | pass (grep count = 8) |
| QA checklist VERBATIM D-11 copy | pass | pass |
| QA checklist VERBATIM D-12 copy (em dash) | pass | pass |
| QA checklist VERBATIM D-09 restoring copy (ellipsis char) | pass | pass |
| QA checklist VERBATIM "Merged 2 duplicate accounts" | pass | pass |
| QA checklist Run Record header captures tester/device/Apple ID metadata | pass | pass |
| QA checklist Overall Phase Gate sign-off section | pass | pass |
| `.planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md` exists | pass | pass |
| TRACEABILITY has all 16 ICLOUD-NN rows | pass | pass (grep loop 01..16 all found) |
| TRACEABILITY has SC-1..SC-6 mapping | pass | pass |
| TRACEABILITY has Orphan Check section | pass | pass |
| TRACEABILITY has all 2-DEV-01..08 references | pass | pass |
| TRACEABILITY ICLOUD-16 row names `RestoringStateTests.testTimeoutTransition` (Blocker 3) | pass | pass |
| `KeyAuthTests/KeyboardPropagationTests.swift` exists | pass | pass |
| KeyboardPropagationTests has 5 named test methods | pass | pass |
| KeyboardPropagationTests wired in pbxproj (4 entries) | pass | pass |
| KeyboardPropagationTests passes | pass | pass (5/5 in 0.025s) |
| REQUIREMENTS.md has `>= 14` `Complete (automated)` | pass | pass (15) |
| REQUIREMENTS.md ICLOUD-10 row names 2-DEV-06 | pass | pass |
| REQUIREMENTS.md ICLOUD-16 row names `RestoringStateTests.testTimeoutTransition` | pass | pass |
| REQUIREMENTS.md `>= 14` `[x]` ICLOUD checkboxes | pass | pass (14) |
| REQUIREMENTS.md Last-updated line reflects Plan 06 completion | pass | pass |
| Full KeyAuthTests suite exits 0 | pass | pass (`** TEST SUCCEEDED **`, 66 tests, 1 skipped) |
| Full suite has `>= 10` test-suite pass lines | pass | pass (12) |

## Self-Check

- `.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md`: FOUND
- `.planning/phases/06-icloud-keychain-sync/06-TRACEABILITY.md`: FOUND
- `KeyAuthTests/KeyboardPropagationTests.swift`: FOUND
- `.planning/REQUIREMENTS.md` (14 automated + 2 hybrid + checkbox flips): VERIFIED
- `KeyAuth.xcodeproj/project.pbxproj` (4 KeyboardPropagationTests entries): VERIFIED (grep = 4 refs)
- commit `e6b10b6` (Task 1 QA checklist): FOUND
- commit `d869869` (Task 2 KeyboardPropagationTests): FOUND
- commit `4f61e74` (Task 3 TRACEABILITY): FOUND
- commit `e9db687` (Task 4 REQUIREMENTS updates): FOUND
- `xcodebuild test` full-suite result: TEST SUCCEEDED (66 tests, 1 skipped, 0 failures)

## Self-Check: PASSED

## Phase 6 Close-Out Checklist

This plan completes the **automated** half of Phase 6. The phase is shippable contingent on:

1. **Manual QA still required on 2 real devices.** The 8-case `06-QA-CHECKLIST.md` must be executed by a tester with two iCloud-signed-in devices (same Apple ID, iCloud Keychain ON). No amount of simulator testing can substitute — real iCloud Keychain propagation is the contract under test.

2. **ICLOUD-10 and ICLOUD-16 remain `Complete (unit) / Manual QA pending` in REQUIREMENTS.md** until the 2-DEV-06 (mid-session external change) and 2-DEV-05 (fresh-install restore) cases are signed off by the tester. Their unit baselines ARE green (`AccountStoreTests.testReloadPopulatesAccountsFromKeychain` + `.testCoalescedReloadDebounces300ms` for ICLOUD-10; `RestoringStateTests` 4-test suite for ICLOUD-16) — this is end-to-end closure, not coverage backfill.

3. **ROADMAP.md Phase 6 checkbox can only flip to `[x]` AFTER manual QA passes.** Do not pre-mark the phase complete based on automated coverage alone. The Success Criteria SC-1, SC-3, SC-4, SC-5 all explicitly require two-device observation per their definitions in ROADMAP.md lines 102-108.

4. **TransientToastOverlay placement** is a known polish task documented in `06-TRACEABILITY.md` Known Gaps. If the manual QA tester notes 2-DEV-02's "Merged N duplicate accounts" toast does not visually appear, this is expected per the phase's current state — they should verify behavior via log output / inspecting `AccountStore.lastDedupCount` instead. A follow-up plan should wire the overlay.

5. **Coverage snapshot for orchestrator phase-verify decision:**
   - 16 of 16 ICLOUD-NN requirements have at least some coverage (no orphans)
   - 14 of 16 have pure automated coverage (`Complete (automated)`)
   - 2 of 16 have hybrid coverage (`Complete (unit: TEST) / Manual QA pending 2-DEV-NN`)
   - 0 of 16 are uncovered or only partially implemented
   - 6 of 6 Success Criteria map to at least one test
   - 62+ automated test methods (66 tests − 1 XCTSkip − 3 unrelated baseline tests = 62 covering phase 6)
   - 8 manual QA cases defined

The orchestrator should decide: **ship Phase 6 when manual QA runs green** (per `06-QA-CHECKLIST.md`), or spawn a follow-up plan to wire `TransientToastOverlay` before the QA run if visual toast is a hard requirement for 2-DEV-02 sign-off.
