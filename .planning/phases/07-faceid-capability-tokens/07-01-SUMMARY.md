---
phase: 07-faceid-capability-tokens
plan: 01
subsystem: testing
tags: [xctest, xcodeproj, requirements, faceid, trust-window, scaffolding]

# Dependency graph
requires:
  - phase: 06-icloud-keychain-sync
    provides: ICloudStateObserver (reused by FIDO-07 revocation trigger) + Ruby xcodeproj pbxproj-edit pattern (STATE.md line 108)
provides:
  - REQUIREMENTS.md FIDO-01..19 formal registry + 19 traceability rows (Pending)
  - ROADMAP.md Phase 7 Requirements + Plans lines materialized (no more TBD)
  - Wave 0 XCTest scaffolds: TrustWindowManagerTests (11 methods), TrustWindowPreferenceTests (3 methods), RelayClientSilentSendTests (3 methods)
  - CodeRequestFixtures factory (make/empty) for silent-send test doubles
  - All 4 new Swift files wired into KeyAuthTests target in project.pbxproj
affects: [07-02, 07-03, 07-04, 07-05, 07-06, 07-07, 07-08]

# Tech tracking
tech-stack:
  added: []  # Apple-frameworks-only — no new deps (PROJECT.md constraint honored)
  patterns:
    - "XCTSkip-as-scaffold: empty test bodies use `throw XCTSkip(\"Wave 0 scaffold — filled in Plan 07-0X.\")` so the suite compiles + stays green while downstream plans fill behavior"
    - "UserDefaults-scrub in setUp/tearDown using the `trust_window_enabled` + `hasLaunchedBeforeTrustWindow` key pair (distinct from SyncPreference keys to avoid cross-bootstrap short-circuit)"
    - "CodeRequestFixtures factory mirrors AccountFixtures.make signature with defaulted parameters"
    - "Ruby xcodeproj gem (v1.27.0) for additive `source_build_phase.add_file_reference` edits — reused from Phase 6 Plan 06-01 Task 6"

key-files:
  created:
    - KeyAuthTests/TrustWindowManagerTests.swift
    - KeyAuthTests/TrustWindowPreferenceTests.swift
    - KeyAuthTests/RelayClientSilentSendTests.swift
    - KeyAuthTests/Fixtures/CodeRequestFixtures.swift
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md
    - KeyAuth.xcodeproj/project.pbxproj

key-decisions:
  - "iPhone 17 used as test destination (iPhone 16 simulator unavailable on this machine — plan explicitly permits any iOS 16+ simulator as substitute)"
  - "All 17 new scaffold tests use XCTSkip with plan-citation message (Plan 07-02/03/04) per threat T-7-TS2 mitigation — Plan 07-08 can grep for `XCTSkip(\"Wave 0 scaffold\")` to verify every scaffold got filled"

patterns-established:
  - "Pattern: Wave 0 XCTest scaffolds for a multi-wave phase — pre-create test files with XCTSkip-cited stubs so downstream parallel plans unblock immediately and can reference the files by name in <automated> verify commands"
  - "Pattern: FIDO-NN traceability rows land in a single atomic commit with the REQUIREMENTS.md section headers + ROADMAP.md Requirements/Plans lines so grep-based verification can't see divergent state (T-7-TS1 mitigation)"

requirements-completed: []  # This plan REGISTERS FIDO-01..19 but leaves them Pending — downstream plans flip them to Complete.

# Metrics
duration: 3min
completed: 2026-04-19
---

# Phase 7 Plan 01: Foundation & Requirements Registration Summary

**FIDO-01..19 registered in REQUIREMENTS.md and ROADMAP.md; 4 Wave 0 XCTest scaffold files created with 17 XCTSkip-gated methods and wired into the KeyAuthTests Xcode target so downstream parallel plans can reference them by name.**

## Performance

- **Duration:** ~3 min (Task 1: ~2 min, Task 2: ~1 min incl. xcodebuild ~56s)
- **Started:** 2026-04-19T15:45Z (approx; hard-reset to base 9bba50b at session start)
- **Completed:** 2026-04-19T15:48Z
- **Tasks:** 2
- **Files modified:** 3 (REQUIREMENTS.md, ROADMAP.md, project.pbxproj)
- **Files created:** 4 (3 XCTest classes + 1 fixture)

## Accomplishments

- Formal registration of 19 FIDO requirement IDs (FIDO-01..FIDO-19) in `.planning/REQUIREMENTS.md` under a new `### FaceID Capability Tokens` section
- 19 pipe-delimited traceability rows mapping each FIDO-NN to Phase 7 / Pending
- Coverage totals bumped 44 → 63 with `Last updated:` line updated to 2026-04-19
- ROADMAP.md Phase 7 `**Requirements:**` line replaced (was "TBD") and `**Plans:**` expanded to `8 plans (07-01..07-08)` with the full plan bullet list
- 4 new Swift files under `KeyAuthTests/` compile and run under `xcodebuild test -only-testing:KeyAuthTests` with all 17 new methods reported as *skipped* (0 failures)
- `KeyAuth.xcodeproj/project.pbxproj` updated via the Ruby xcodeproj gem — PBXBuildFile, PBXFileReference, group children, and Sources build phase entries all present for each new file

## Task Commits

Each task was committed atomically (worktree mode, `--no-verify`):

1. **Task 1: Register FIDO-01..FIDO-19 in REQUIREMENTS.md and ROADMAP.md** — `5721878` (docs)
2. **Task 2: Create Wave 0 test scaffolds and CodeRequestFixtures; wire into KeyAuthTests target** — `ee31332` (test)

**Plan metadata:** appended to this SUMMARY in a final commit (see below).

## (1) FIDO-01..19 Registration Delta

### REQUIREMENTS.md

Added `### FaceID Capability Tokens` section after the `### iCloud Keychain Sync` block and before `## v2 Requirements`. 19 checkboxed entries verbatim from the plan's `<action>` step 1:

```
- [ ] **FIDO-01**: TrustWindowManager.shared is an @MainActor ObservableObject singleton …
- [ ] **FIDO-02**: TrustWindowManager.mint() sets windowExpiresAt = Date().addingTimeInterval(120) …
… (through FIDO-19) …
```

Added 19 traceability-table rows after `ICLOUD-16`:

```
| FIDO-01 | Phase 7 | Pending |
| FIDO-02 | Phase 7 | Pending |
… (through FIDO-19) …
```

Coverage totals: `v1 requirements: 44 total` → `v1 requirements: 63 total`; `Mapped to phases: 44` → `Mapped to phases: 63`.

Last-updated line: `*Last updated: 2026-04-19 — added FIDO-01..19 for Phase 7 (FaceID Capability Tokens).*`

### ROADMAP.md Phase 7 entry

- `**Requirements:** TBD (...)` → `**Requirements:** FIDO-01, FIDO-02, FIDO-03, …, FIDO-19`
- `**Plans:** 0 plans` → `**Plans:** 8 plans (07-01..07-08)`
- `- [ ] TBD (run \`/gsd-plan-phase 7\` to break down)` → 8 dedicated plan bullets (07-01..07-08) with one-line descriptions
- The Phase 7 row in the tracking table at the bottom (`| 7. FaceID Capability Tokens | 0/TBD | Not planned | - |`) was intentionally left unchanged per plan instructions — execute-phase flips that row as plans complete.

### Grep-level verification (Task 1 `<automated>` command)

```
FIDO row count OK        (grep -c '| FIDO-' REQUIREMENTS.md >= 19)
FIDO-19 present
Roadmap FIDO line OK
No Requirements TBD
No Plans 0 plans
Roadmap Plans line OK    (8 plans (07-01..07-08) present)
Coverage total updated   (v1 requirements: 63 total)
Section header OK        (### FaceID Capability Tokens)
```

## (2) Wave 0 Test Scaffold Inventory

| File | Path | Method Count | Requirements Covered | Downstream Plan Cited |
|------|------|--------------|----------------------|-----------------------|
| TrustWindowManagerTests | `KeyAuthTests/TrustWindowManagerTests.swift` | 11 | FIDO-01, FIDO-02, FIDO-03, FIDO-04, FIDO-05, FIDO-06, FIDO-07, FIDO-11 (×2), FIDO-12, FIDO-17 | 07-03 |
| TrustWindowPreferenceTests | `KeyAuthTests/TrustWindowPreferenceTests.swift` | 3 | FIDO-14 (×2 — persist + idempotency), FIDO-16 | 07-02 |
| RelayClientSilentSendTests | `KeyAuthTests/RelayClientSilentSendTests.swift` | 3 | FIDO-09 (×2 — in-window + out-of-window complement), FIDO-10 | 07-04 |
| CodeRequestFixtures (fixture) | `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` | `make(...)` + `empty(domain:)` factories | n/a (support code) | consumed by silent-send tests |

**Total new methods:** 17 (all `throw XCTSkip("Wave 0 scaffold — filled in Plan 07-0X.")`)

Every scaffold file is `@MainActor final class … XCTestCase` with `setUp`/`tearDown` that scrubs both `trust_window_enabled` and `hasLaunchedBeforeTrustWindow` UserDefaults keys — matches the RESEARCH-endorsed key pair (distinct from `SyncPreference` keys per RESEARCH line 602).

## (3) xcodeproj Wiring Diff (Ruby script output)

```
Wired 4 Phase 7 Wave 0 files into KeyAuthTests
  added:          ["TrustWindowManagerTests.swift", "TrustWindowPreferenceTests.swift", "RelayClientSilentSendTests.swift", "CodeRequestFixtures.swift"]
  already-wired:  []
```

Post-save `project.pbxproj` grep confirms all four wiring rows:

```
1EF2EEFFCD66040E1644538C /* CodeRequestFixtures.swift in Sources */         = PBXBuildFile fileRef = 58AC46A3D01F68F5421CF7E9;
61CC4E609B27D652D81F9F69 /* TrustWindowManagerTests.swift in Sources */     = PBXBuildFile fileRef = 6753FEAEAA7C45F78993C4CA;
9B85464F34CE6B4994CA0184 /* TrustWindowPreferenceTests.swift in Sources */  = PBXBuildFile fileRef = DA0603D3BB0BC31E8894954A;
A6ABF3F04878C3DA2BA1C9FB /* RelayClientSilentSendTests.swift in Sources */  = PBXBuildFile fileRef = 20B8575CB228C2521A93AF2B;
```

Group children (`KeyAuthTests/Fixtures` + `KeyAuthTests` root) updated to reference the new files; Sources build phase lists all four in the `files = (…)` array.

## (4) `xcodebuild test -only-testing:KeyAuthTests` Pass-Log Tail

Destination: `platform=iOS Simulator,name=iPhone 17,OS=latest` (iPhone 16 unavailable on this host — plan permits any iOS 16+ simulator substitute)

```
Test Suite 'TrustWindowManagerTests' passed at 2026-04-19 10:47:55.320.
     Executed 11 tests, with 11 tests skipped and 0 failures (0 unexpected) in 0.023 (0.025) seconds
Test Suite 'TrustWindowPreferenceTests' passed at 2026-04-19 10:47:55.324.
     Executed 3 tests, with 3 tests skipped and 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'KeyAuthTests.xctest' passed at 2026-04-19 10:47:55.324.
     Executed 83 tests, with 18 tests skipped and 0 failures (0 unexpected) in 0.909 (0.946) seconds
Test Suite 'All tests' passed at 2026-04-19 10:47:55.326.
     Executed 83 tests, with 18 tests skipped and 0 failures (0 unexpected) in 0.909 (0.948) seconds

** TEST SUCCEEDED **
```

83 tests executed / 18 skipped / 0 failures. Breakdown of the 18 skips:
- 17 are the new Wave 0 scaffold methods (11 manager + 3 preference + 3 silent-send).
- 1 pre-existing skip inherited from Phase 6 (unchanged by this plan).

All three new suites compile under `@testable import KeyAuth`; no new linker errors, no new warnings introduced. The RelayClientSilentSendTests class is silent in the stdout tail above because the tail window captured manager + preference logs — suite-level counts show all 3 methods executed + skipped (see `/tmp/xcodebuild_task2.log` intermediate output grepping `RelayClientSilentSendTests` confirms `testAmbiguousResolutionSetsPendingCodeRequest`, `testOutOfWindowAlwaysSetsPendingCodeRequest`, `testSilentSendInWindow` all skipped).

## Files Created/Modified

**Created:**
- `KeyAuthTests/TrustWindowManagerTests.swift` — 11 XCTSkip-gated methods covering FIDO-01..07, FIDO-11 (×2), FIDO-12, FIDO-17
- `KeyAuthTests/TrustWindowPreferenceTests.swift` — 3 XCTSkip-gated methods covering FIDO-14 (×2) + FIDO-16
- `KeyAuthTests/RelayClientSilentSendTests.swift` — 3 XCTSkip-gated methods covering FIDO-09 (×2) + FIDO-10
- `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` — `make(...)` + `empty(domain:)` factories, mirroring `AccountFixtures.swift`

**Modified:**
- `.planning/REQUIREMENTS.md` — Added `### FaceID Capability Tokens` section (19 items), 19 traceability rows, Coverage totals 44→63, Last-updated line
- `.planning/ROADMAP.md` — Phase 7 Requirements line materialized, Plans line expanded to 8 plans with bullet list
- `KeyAuth.xcodeproj/project.pbxproj` — 4 new PBXBuildFile + 4 new PBXFileReference entries; group + source_build_phase updated

## Decisions Made

- **Simulator substitution (iPhone 17 in place of iPhone 16):** The local `xcrun simctl list devices available` shows iPhone 15, 17 family, and Air — no iPhone 16. Plan Task 2 step 6 explicitly permits any iOS 16+ simulator substitute, so iPhone 17 with `OS=latest` was used. No semantic impact on compile/skip behavior.
- **Followed threat model T-7-TS1 mitigation verbatim:** REQUIREMENTS.md + ROADMAP.md both updated in Task 1's single commit so grep-verification cannot see divergent state at any point.
- **Followed threat model T-7-TS2 mitigation verbatim:** Every scaffold method body carries a `Plan 07-0X` citation in the XCTSkip message so Plan 07-08 can later grep for `XCTSkip("Wave 0 scaffold")` and prove no empty stubs remain.

## Deviations from Plan

None — plan executed exactly as written. All Task 1 and Task 2 `<automated>` verification commands pass first try. No Rule 1-4 deviations triggered. No auth gates. No architectural questions.

The only minor environmental adaptation was the iPhone 17 simulator substitute documented above, which the plan explicitly sanctions.

## Issues Encountered

None. Note that a Ruby `ffi-1.15.5` extension-build warning is printed at the top of every xcodeproj gem invocation on this machine (unrelated to Phase 7 — carries over from Phase 6 Plan 06-01). It does not affect functionality; the gem operated correctly and `project.save` succeeded.

## TDD Gate Compliance

This plan is not type=tdd at the plan level — it is a scaffolding plan whose whole output *is* pre-RED test stubs. The RED/GREEN/REFACTOR cycle applies within the downstream plans that fill each scaffold:
- Plan 07-02 fills the TrustWindowPreference stubs (RED exists now → GREEN in 07-02)
- Plan 07-03 fills the TrustWindowManager stubs
- Plan 07-04 fills the RelayClient silent-send stubs

Per plan frontmatter, this plan is `type: execute` with `autonomous: true`, so no `test(...)` → `feat(...)` gate is required.

## Known Stubs

- All 17 new test methods bodies are intentional `XCTSkip` stubs. This is the *purpose* of the plan — not a hidden regression. Each stub's skip message cites the downstream plan that will fill it. Plan 07-08 grep-verifies that every stub got filled before Phase 7 is marked complete.

## Threat Flags

None — this plan only touches planning markdown + test-scaffold sources + pbxproj wiring. No production code paths, no new network surface, no new auth paths, no schema changes.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plans 07-02 through 07-07 can now reference the scaffold files by name in their `<automated>` verify commands (e.g., `grep "XCTAssertTrue" KeyAuthTests/TrustWindowManagerTests.swift`).
- Plans 07-02, 07-03, 07-04 can now run in parallel: each one fills the stubs in exactly one of the new test files (no file-level contention).
- REQUIREMENTS.md is ready for Plan 07-08 to flip `Pending` → `Complete (automated)` as each FIDO-NN gets its implementation + automated coverage.
- ROADMAP.md Phase 7 tracking-row (bottom of file, `| 7. FaceID Capability Tokens | 0/TBD | Not planned | - |`) will be updated centrally by the orchestrator / execute-phase — this plan intentionally left it alone per plan instructions.

## Self-Check: PASSED

**Created files verified on disk:**
- `KeyAuthTests/TrustWindowManagerTests.swift` — FOUND
- `KeyAuthTests/TrustWindowPreferenceTests.swift` — FOUND
- `KeyAuthTests/RelayClientSilentSendTests.swift` — FOUND
- `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` — FOUND

**Commits verified in `git log --all`:**
- `5721878` — Task 1 commit (docs(07-01): register FIDO-01..19 …) — FOUND
- `ee31332` — Task 2 commit (test(07-01): add Wave 0 XCTest scaffolds …) — FOUND

**Plan-level automated checks (from `<verification>`):**
- `grep -c '| FIDO-' .planning/REQUIREMENTS.md` → 19 ✓
- ROADMAP.md Phase 7 Requirements line contains all 19 FIDO IDs ✓
- Plans line reads `8 plans (07-01..07-08)` ✓
- 3 new test class files exist in `KeyAuthTests/` + 1 new fixture in `KeyAuthTests/Fixtures/` ✓
- `xcodebuild test … -only-testing:KeyAuthTests` exited 0 with `** TEST SUCCEEDED **` and all 17 new methods reported skipped ✓
- ICLOUD-01..ICLOUD-16 traceability rows and existing test files untouched ✓

---
*Phase: 07-faceid-capability-tokens*
*Completed: 2026-04-19*
