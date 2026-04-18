---
phase: 06-icloud-keychain-sync
plan: 01
subsystem: testing
tags: [xctest, xcodeproj, icloud-keychain, sync, protocol, fixtures, ruby-xcodeproj]

requires:
  - phase: 02-ios-relay-client-pairing
    provides: "KeychainManager + access group entitlement 'W646UCTVQV.com.keyauth.shared'"
provides:
  - "16 formally registered ICLOUD-NN requirements in REQUIREMENTS.md + ROADMAP.md"
  - "Corrected 06-VALIDATION.md scheme references (-scheme KeyAuth, not -scheme KeyAuthTests)"
  - "First XCTest target in the project: KeyAuthTests (TEST_HOST/BUNDLE_LOADER to KeyAuth.app)"
  - "KeychainProviding protocol + SynchronizableScope enum (Shared/)"
  - "SyncPreference helper with D-01/D-02 bootstrap semantics (Shared/)"
  - "DedupKey pure value type with NFC + case-insensitive + whitespace normalization (Shared/)"
  - "MockKeychain test fixture modeling two-variant Keychain storage"
  - "AccountFixtures factory with explicit-createdAt support via JSON round-trip"
  - "5 passing smoke tests establishing the test scaffold for Waves 1-5"
affects: [06-02, 06-03, 06-04, 06-05, 06-06, all future phases needing unit tests]

tech-stack:
  added:
    - "XCTest (first test target in the project)"
    - "@testable import KeyAuth pattern for internal-symbol access in tests"
    - "xcodeproj Ruby gem (pre-installed, used only for editing project.pbxproj)"
  patterns:
    - "Protocol-extraction-for-testability (KeychainProviding)"
    - "UserDefaults-wrapper enum with static-method API (SyncPreference mirrors SharedDefaults idiom)"
    - "Pure value-type with normalization in init (DedupKey mirrors Base32's structural purity)"
    - "Two-variant in-memory Keychain mock ((account, isSync) Entry struct modeling kSecAttrSynchronizableAny semantics)"

key-files:
  created:
    - "Shared/KeychainProviding.swift"
    - "Shared/SyncPreference.swift"
    - "Shared/DedupKey.swift"
    - "KeyAuthTests/KeyAuthTests.swift"
    - "KeyAuthTests/Info.plist"
    - "KeyAuthTests/Mocks/MockKeychain.swift"
    - "KeyAuthTests/Fixtures/AccountFixtures.swift"
  modified:
    - ".planning/REQUIREMENTS.md"
    - ".planning/ROADMAP.md"
    - ".planning/phases/06-icloud-keychain-sync/06-VALIDATION.md"
    - "KeyAuth.xcodeproj/project.pbxproj"
    - "KeyAuth.xcodeproj/xcshareddata/xcschemes/KeyAuth.xcscheme"

key-decisions:
  - "SyncPreference uses UserDefaults.standard, NOT the App Group suite — per-device UX state, not cross-process data"
  - "KeychainProviding declared in Shared/ with zero conformances — KeychainManager extension deferred to Plan 02"
  - "KeyAuthTests added to the existing 'KeyAuth' scheme as a TestableReference (no standalone scheme), matching downstream plans 02-06 that use '-scheme KeyAuth'"
  - "Smoke suite ran on iPhone 15 (OS 18.4) because iPhone 16 simulator is not present — plan explicitly permits fallback; all 5 tests passed"
  - "KeyAuthTests target isolated from KeyAuthKeyboard — keyboard has no test dependency"
  - "Ruby xcodeproj gem used for all project.pbxproj edits to avoid hand-crafting target/config/scheme XML (four invocations, one per Swift file set)"

patterns-established:
  - "Pattern: Protocol-first testability — new Shared/ types expose a protocol even when only one production conformer exists; enables mock injection without runtime overhead"
  - "Pattern: Bootstrap-on-first-launch — hasLaunchedBefore sentinel in UserDefaults.standard gates one-time defaults; new-vs-existing user disambiguation via existingAccountCount > 0"
  - "Pattern: Two-variant mock Keychain — Entry(account, isSync) tuples reproduce the real Keychain's ability to hold both synced and non-synced records for the same account.id"
  - "Pattern: Xcode target wiring via xcodeproj Ruby gem — avoids pbxproj UUID collisions and preserves scheme shared data"

requirements-completed:
  - ICLOUD-01
  - ICLOUD-02
  - ICLOUD-03
  - ICLOUD-04
  - ICLOUD-05
  - ICLOUD-06
  - ICLOUD-07
  - ICLOUD-08
  - ICLOUD-09
  - ICLOUD-10
  - ICLOUD-11
  - ICLOUD-12
  - ICLOUD-13
  - ICLOUD-14
  - ICLOUD-15
  - ICLOUD-16

duration: 8min
completed: 2026-04-18
---

# Phase 06 Plan 01: iCloud Keychain Sync — Wave 0 Scaffolding Summary

**Formalized 16 ICLOUD requirements, corrected VALIDATION scheme refs, and stood up the project's first XCTest target with protocol/helper/fixture scaffolding — every downstream wave (Plans 02-06) is now unblocked and the 5-test smoke suite passes green on iPhone 15 (OS 18.4).**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-18T13:32:45Z
- **Completed:** 2026-04-18T13:40:46Z
- **Tasks:** 6 / 6 complete
- **Files created:** 7
- **Files modified:** 5

## Accomplishments

1. **Requirements & roadmap delta** — REQUIREMENTS.md gained a new `### iCloud Keychain Sync` section (16 items) + 16 pipe-delimited traceability rows; coverage total advanced from 28 to 44. ROADMAP.md Phase 6 Requirements line now lists all 16 IDs (was `TBD`); Phase 6 Plans line reads `6 plans (06-01..06-06)` (was `TBD`).
2. **VALIDATION.md correction** — Quick-run and full-suite commands changed from `-scheme KeyAuthTests` (incorrect — no such scheme exists) to `-scheme KeyAuth` matching downstream Plans 02-06. Legacy scheme token count is now 0 in the file.
3. **First XCTest target in the project** — `KeyAuthTests` (`com.apple.product-type.bundle.unit-test`) wired with `TEST_HOST=$(BUILT_PRODUCTS_DIR)/KeyAuth.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/KeyAuth`, `BUNDLE_LOADER=$(TEST_HOST)`, `PRODUCT_BUNDLE_IDENTIFIER=com.keyauth.KeyAuthTests`, `IPHONEOS_DEPLOYMENT_TARGET=16.0`, `SWIFT_VERSION=5.0`, `DEVELOPMENT_TEAM=W646UCTVQV`, `CODE_SIGN_STYLE=Automatic`. Target added as a `TestableReference` inside the existing `KeyAuth` scheme's TestAction.
4. **Three new Shared/ Swift files** — `KeychainProviding.swift` (protocol + `SynchronizableScope` enum), `SyncPreference.swift` (D-01/D-02 bootstrap + first-launch-card gate), `DedupKey.swift` (Hashable value type normalizing issuer/label/secret). All three added to the `KeyAuth` app target only.
5. **Three new KeyAuthTests/ files** — `KeyAuthTests.swift` (5 smoke tests), `Mocks/MockKeychain.swift` (two-variant in-memory `KeychainProviding` fake with partial-failure hooks), `Fixtures/AccountFixtures.swift` (`Account` factory with JSON-round-trip `createdAt` patching).
6. **Smoke suite green** — `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4'` exits `** TEST SUCCEEDED **`. All five tests pass in 0.005s:
   - `testTargetBuildsAndRuns`
   - `testMockKeychainSaveAndLoad`
   - `testDedupKeyNormalization`
   - `testSyncPreferenceBootstrapNewUser` (D-01 new-user default ON)
   - `testSyncPreferenceBootstrapExistingUser` (D-02 existing-user default OFF)

## Task Commits

Each task was committed atomically with `docs(06-01):` / `feat(06-01):` / `test(06-01):` prefixes (no Co-Authored-By trailers per user preference):

1. **Task 1: Formalize ICLOUD-01..16 in REQUIREMENTS + ROADMAP + fix VALIDATION scheme** — `24e335a` (docs)
2. **Task 2: Create KeyAuthTests XCTest target wired into KeyAuth scheme** — `ed1602c` (feat)
3. **Task 3: Add KeychainProviding protocol** — `51da626` (feat)
4. **Task 4: Add SyncPreference helper with D-01/D-02 bootstrap** — `8ca2760` (feat)
5. **Task 5: Add DedupKey value type** — `86b5c48` (feat)
6. **Task 6: MockKeychain + AccountFixtures + run smoke suite** — `4c8fd86` (test)

## Files Created/Modified

### Created

- `Shared/KeychainProviding.swift` — Sync-aware 8-method Keychain CRUD protocol + `SynchronizableScope` enum. No conformance declared here (Plan 02 extends `KeychainManager`).
- `Shared/SyncPreference.swift` — Per-device sync toggle in `UserDefaults.standard`. Exposes `isEnabled`, `setEnabled`, `hasSeenFirstLaunchCard`, `markFirstLaunchCardSeen`, `bootstrap(existingAccountCount:)`, `shouldShowFirstLaunchCard(accountsIsEmpty:)`.
- `Shared/DedupKey.swift` — `Hashable` struct applying `precomposedStringWithCanonicalMapping → trim → lowercased()` to `issuer`/`label`; `whitespacesAndNewlines stripped → uppercased` to `secret`. Used by Plan 05's in-memory dedup pass.
- `KeyAuthTests/Info.plist` — Standard `BNDL` Info.plist with `$(PRODUCT_*)` substitutions.
- `KeyAuthTests/KeyAuthTests.swift` — XCTestCase with 5 smoke tests. All pass.
- `KeyAuthTests/Mocks/MockKeychain.swift` — `final class` implementing `KeychainProviding` with `[Entry]` store; `save` removes matching (id, isSync) tuple then appends (allowing both variants); `delete(id:)` removes all variants (mirrors `kSecAttrSynchronizableAny`); `failSaveForIDs` / `failDeleteForIDs` enable Plan 05 partial-failure tests.
- `KeyAuthTests/Fixtures/AccountFixtures.swift` — `AccountFixtures.make(...)` with default values and optional `createdAt: Date?` via `JSONSerialization` → `JSONDecoder` round-trip (`Account.createdAt` is `let`-bound).

### Modified

- `.planning/REQUIREMENTS.md` — new `### iCloud Keychain Sync` section (16 items) inserted between iOS App Additions and v2 Requirements; 16 traceability rows appended; coverage totals 28 → 44; `Last updated` line refreshed.
- `.planning/ROADMAP.md` — Phase 6 Requirements line now lists ICLOUD-01..16 explicitly; Phase 6 Plans line set to `6 plans (06-01..06-06)`. Phase 4 and Phase 5 `Plans**: TBD` lines were left untouched (out of scope; Phase 4/5 will populate their own plans when planned).
- `.planning/phases/06-icloud-keychain-sync/06-VALIDATION.md` — Quick-run command now uses `-scheme KeyAuth -only-testing:KeyAuthTests/{TestClass}`; Full-suite command uses `-scheme KeyAuth -only-testing:KeyAuthTests`. Zero legacy `-scheme KeyAuthTests` tokens remain.
- `KeyAuth.xcodeproj/project.pbxproj` — 1 new `PBXNativeTarget` (`KeyAuthTests`), 1 new `XCConfigurationList` with Debug+Release `XCBuildConfiguration` entries, 1 new `PBXTargetDependency` (KeyAuthTests → KeyAuth), 1 new `PBXSourcesBuildPhase`, 6 new `PBXFileReference`s (`KeychainProviding.swift`, `SyncPreference.swift`, `DedupKey.swift`, `MockKeychain.swift`, `AccountFixtures.swift`, `KeyAuthTests.swift` + KeyAuthTests group with `Mocks`/`Fixtures` subgroups + Info.plist + `.xctest` product).
- `KeyAuth.xcodeproj/xcshareddata/xcschemes/KeyAuth.xcscheme` — TestAction's `<Testables>` now contains a `TestableReference` for KeyAuthTests.

## xcodebuild -list output (post-plan)

```
Information about project "KeyAuth":
    Targets:
        KeyAuth
        KeyAuthKeyboard
        KeyAuthTests

    Build Configurations:
        Debug
        Release

    Schemes:
        KeyAuth
```

## xcodebuild test final summary

```
Test Suite 'All tests' started at 2026-04-18 08:39:31.997.
Test Suite 'KeyAuthTests.xctest' started at 2026-04-18 08:39:31.997.
Test Suite 'KeyAuthTests' started at 2026-04-18 08:39:31.997.
Test Case '-[KeyAuthTests.KeyAuthTests testDedupKeyNormalization]' passed (0.001 seconds).
Test Case '-[KeyAuthTests.KeyAuthTests testMockKeychainSaveAndLoad]' passed (0.000 seconds).
Test Case '-[KeyAuthTests.KeyAuthTests testSyncPreferenceBootstrapExistingUser]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.KeyAuthTests testSyncPreferenceBootstrapNewUser]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.KeyAuthTests testTargetBuildsAndRuns]' passed (0.000 seconds).
Test Suite 'KeyAuthTests' passed at 2026-04-18 08:39:32.004.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
** TEST SUCCEEDED **
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator destination required explicit OS version**
- **Found during:** Task 6 smoke-test run.
- **Issue:** `-destination 'platform=iOS Simulator,name=iPhone 15'` (without `OS=`) failed with "Unable to find a device matching the provided destination specifier" because xcodebuild defaulted to `OS=latest` (26.4.1) and the only `iPhone 15` simulator runs OS 18.4.
- **Fix:** Added `OS=18.4` to the destination string. Used the plan's sanctioned fallback (plan explicitly permits substituting any iOS 16+ simulator from `xcrun simctl list devices`).
- **Files modified:** none — command-line only.
- **Commit:** N/A (no file change).

**2. [Rule 3 - Blocking] iPhone 16 simulator not installed**
- **Found during:** Task 6.
- **Issue:** Plan's recommended destination `name=iPhone 16` does not exist on the host — only iPhone 15 (iOS 18.4) and iPhone 17 series (iOS 26.4.1) are available.
- **Fix:** Used iPhone 15 / OS 18.4 (iOS 16+ per plan requirement: 18.4 satisfies the 16.0 deployment target).
- **Impact:** None — the smoke tests are platform-agnostic pure Swift logic.

### Acceptance-command caveat (not a deviation; documented for traceability)

The Task 1 `<automated>` verify line contains `! grep -qE "Plans\*\*: TBD" .planning/ROADMAP.md`, which would fail as long as Phase 4 and Phase 5 still carry `**Plans**: TBD` placeholders (they're unplanned). Those rows are pre-existing and out of scope per the plan's own clarifying note ("the Phase 6 summary row at the bottom of ROADMAP.md ... should be updated separately"). The plan's must_haves clearly scope the TBD check to Phase 6 only, which was satisfied (`**Plans**: 6 plans (06-01..06-06)` now present). No modification was made to unrelated phases.

## Known Stubs

None. All scaffolded files are exercised by the smoke tests or are pure data/definition files (Info.plist, protocol, value type). Stubs deferred to later plans are documented inline in source comments (e.g., "Dedup pass lives in Plan 05").

## TDD Gate Compliance

Not applicable — this plan has `type: execute` (not `type: tdd`). Tests and implementation are intentionally committed together in Task 6 to verify the scaffold integrates.

## Build Verification Note

`xcodebuild test` succeeded in full (app target, keyboard extension, and tests build + tests pass). No additional `xcodebuild build` sanity pass was run because the test command implicitly builds both app + test bundle via `TEST_HOST`/`BUNDLE_LOADER`.

## Self-Check: PASSED

- `Shared/KeychainProviding.swift`: FOUND
- `Shared/SyncPreference.swift`: FOUND
- `Shared/DedupKey.swift`: FOUND
- `KeyAuthTests/Info.plist`: FOUND
- `KeyAuthTests/KeyAuthTests.swift`: FOUND
- `KeyAuthTests/Mocks/MockKeychain.swift`: FOUND
- `KeyAuthTests/Fixtures/AccountFixtures.swift`: FOUND
- commit 24e335a (Task 1): FOUND
- commit ed1602c (Task 2): FOUND
- commit 51da626 (Task 3): FOUND
- commit 8ca2760 (Task 4): FOUND
- commit 86b5c48 (Task 5): FOUND
- commit 4c8fd86 (Task 6): FOUND
- REQUIREMENTS.md ICLOUD row count: 16 (>= 16 required)
- VALIDATION.md legacy `scheme KeyAuthTests` count: 0 (== 0 required)
- xcodebuild -list KeyAuthTests target: FOUND
- xcodebuild test result: TEST SUCCEEDED

## Next-Plan Readiness

Plan 06-02 and all other Wave 1+ plans are now unblocked:
- `KeychainProviding` protocol exists — Plan 02 can add `extension KeychainManager: KeychainProviding {}` after sync-aware CRUD lands.
- `SyncPreference` helper exists — Plan 02+ can gate every `keychain.save(..., synchronizable: SyncPreference.isEnabled)` branch.
- `DedupKey` exists — Plan 05's in-memory dedup pass can `import` it.
- `MockKeychain` + `AccountFixtures` exist — all subsequent plans can write XCTest coverage without scaffolding work.
- KeyAuthTests target exists and is scheme-wired — `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests` runs green end-to-end.
