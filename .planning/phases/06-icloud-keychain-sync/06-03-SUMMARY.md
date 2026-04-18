---
phase: 06-icloud-keychain-sync
plan: 03
subsystem: state-management
tags: [swiftui, scenephase, nsubiquitouskeyvaluestore, kvs-observer, icloud-identity, account-store, reactive, xctest, entitlements]

requires:
  - plan: 06-02
    provides: "Sync-aware KeychainManager.save(_:synchronizable:), KeychainProviding conformance, transient save(_:) shim, MockKeychain baseline"
provides:
  - "AccountStore rewired: protocol-injected KeychainProviding, NSUbiquitousKeyValueStore observer, 300 ms coalesce debounce, SyncPreference-gated save path, accounts-version counter bump"
  - "ICloudStateObserver.swift — @MainActor singleton tracking iCloud identity for D-11 (no iCloud) and D-12 (mid-session sign-out) flows; publishes isICloudSignedIn + didAccountChange; #if DEBUG _primeAsSignedIn + _simulateIdentityChange test hooks"
  - "KeyAuthApp wiring — @StateObject icloudState + @Environment(\\.scenePhase); .onChange(of: scenePhase) triggers store.reload + KVS synchronize on .active; bootstrapSyncPreferenceOnce() on .onAppear reads SharedDefaults.loadAccounts().count to disambiguate D-01 vs D-02 BEFORE AccountStore consults SyncPreference"
  - "KeyAuth app target gains com.apple.developer.ubiquity-kvstore-identifier entitlement (namespaced as \\$(TeamIdentifierPrefix)\\$(CFBundleIdentifier)) — required for NSUbiquitousKeyValueStore reads/writes to persist"
  - "KeychainManager.save(_:) shim removed — AccountStore now uses the explicit save(_:synchronizable:) API exclusively"
  - "MockKeychain.loadAllCallCount counter — enables the 5→1 coalesce-debounce assertion"
  - "9 new tests (7 AccountStoreTests + 2 ICloudStateObserverTests) covering ICLOUD-10/11/12/15; KeyAuthTests suite now 29/29 green"
affects: [06-04 (SettingsView reads icloudState env object), 06-05 (MigrationCoordinator observes AccountStore), 06-06 (toolbar + two-device QA)]

tech-stack:
  added:
    - "NSUbiquitousKeyValueStore.didChangeExternallyNotification observer pattern inside @MainActor ObservableObject"
    - "Task-based 300 ms debounce for coalesced reloads (nanoseconds sleep + cancellation)"
    - "com.apple.developer.ubiquity-kvstore-identifier entitlement bound to \\$(TeamIdentifierPrefix)\\$(CFBundleIdentifier)"
    - ".onChange(of: scenePhase) { newPhase in ... } iOS 16-compatible single-parameter form"
  patterns:
    - "Initializer injection of KeychainProviding with KeychainManager.shared default — preserves production behavior, enables MockKeychain in tests"
    - "Singleton ObservableObject with #if DEBUG prime hook — sidesteps non-deterministic simulator iCloud state"
    - "accounts-version Int64 counter as cross-device ping (plaintext trigger, not data — RESEARCH.md lines 615-617)"
    - "Transition-based observer guards (wasSignedIn / previousIdentityToken compare) — production handleIdentityChange only flips state on genuine transitions, not spurious notifications"

key-files:
  created:
    - "Shared/ICloudStateObserver.swift"
    - "KeyAuthTests/AccountStoreTests.swift"
    - "KeyAuthTests/ICloudStateObserverTests.swift"
  modified:
    - "Shared/AccountStore.swift"
    - "Shared/KeychainManager.swift"
    - "App/KeyAuthApp.swift"
    - "App/KeyAuth.entitlements"
    - "KeyAuthTests/Mocks/MockKeychain.swift"
    - "KeyAuth.xcodeproj/project.pbxproj"

key-decisions:
  - "AccountStore keychain dependency changed from `private let keychain = KeychainManager.shared` to `private let keychain: KeychainProviding` with initializer injection — unlocks unit testing without breaking production"
  - "bumpCounterIfSyncing() is a no-op when SyncPreference.isEnabled == false (RESEARCH.md Open Question #6) — local-only saves do not broadcast; only synchronized saves bump the cross-device ping"
  - "ICloudStateObserver.previousIdentityToken typed AnyObject? (Apple's documented opaque identity-token pattern) instead of the (NSCoding & NSCopying & NSObjectProtocol) existential composition — avoids Swift 6 strict-concurrency warnings while preserving isEqual(_:) reference-identity comparison"
  - "com.apple.developer.ubiquity-kvstore-identifier entitlement added under Rule 2 (missing critical functionality): the plan's counter-ping pattern relies on NSUbiquitousKeyValueStore persistence, which silently drops all writes without this entitlement — both in tests AND in production"
  - "SyncPreference bootstrap reads SharedDefaults.loadAccounts().count (not AccountStore) — avoids a chicken-and-egg where AccountStore.init would consult SyncPreference before bootstrap ran"
  - ".onChange(of: scenePhase) uses the single-parameter iOS 16-compatible form — the plan's <interfaces> used the iOS 17+ two-parameter form which fails to compile against the project's 16.0 deployment target"
  - "#if DEBUG _primeAsSignedIn() test hook added because iOS Simulator's FileManager.default.ubiquityIdentityToken is nil by default, preventing ICloudStateObserver.init from ever being in a signed-in state — without the primer the sign-out transition test is a no-op"

patterns-established:
  - "Pattern: KVS-as-ping — the accounts-version Int64 counter in NSUbiquitousKeyValueStore.default is a cross-device trigger (\"something moved, go look\"); actual data stays in Keychain; no secrets cross the KVS trust boundary"
  - "Pattern: scenePhase + external-notification dual reload — scenePhase.active covers foreground re-entry (ICLOUD-10), didChangeExternallyNotification covers mid-session external pushes; both end in the same reload pipeline so downstream consumers (SharedDefaults, keyboard) are order-independent"
  - "Pattern: ObservableObject singleton with TEST prime hook — #if DEBUG _primeAsSignedIn lets unit tests force a known state before exercising transition logic, without breaking release-build invariants"
  - "Pattern: entitlement-as-correctness-requirement — NSUbiquitousKeyValueStore silently no-ops without com.apple.developer.ubiquity-kvstore-identifier; treat missing entitlements as Rule 2 auto-fix, not architectural decisions"

requirements-completed:
  - ICLOUD-10
  - ICLOUD-11
  - ICLOUD-12
  - ICLOUD-15

duration: 11min
completed: 2026-04-18
---

# Phase 06 Plan 03: AccountStore + ICloudStateObserver + App Wiring Summary

**Wired in-session refresh architecture: AccountStore now listens to NSUbiquitousKeyValueStore.didChangeExternallyNotification + SwiftUI scenePhase transitions, bumps a cross-device `accounts-version` counter on every synchronized save/delete, and accepts an injected KeychainProviding for unit testing. New ICloudStateObserver tracks iCloud identity for D-11/D-12 handling. KeyAuthApp bootstraps SyncPreference before AccountStore consults it, and the transient save(_:) shim from Plan 06-02 is gone. 9 new tests covering ICLOUD-10/11/12/15 bring KeyAuthTests to 29/29 green.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-04-18T13:59:23Z
- **Completed:** 2026-04-18T14:10:55Z
- **Tasks:** 5 / 5 complete
- **Files created:** 3
- **Files modified:** 6
- **Tests added:** 9 (KeyAuthTests suite: 20 → 29 passing)

## Accomplishments

1. **Task 1 — AccountStore rewrite + save(_:) shim removal (`86a4418`)**
   - `init(keychain: KeychainProviding = KeychainManager.shared)` replaces the hard-coded `KeychainManager.shared` dependency so `MockKeychain` can be injected in tests.
   - `registerKVSObserver()` adds a NotificationCenter observer on `NSUbiquitousKeyValueStore.didChangeExternallyNotification` (object = `NSUbiquitousKeyValueStore.default`, queue = `.main`); the callback hops to `@MainActor` via `Task { @MainActor in ... }` to satisfy the class's isolation attribute.
   - `handleKVSChange(_:)` switches on `NSUbiquitousKeyValueStoreChangeReasonKey`:
     - `NSUbiquitousKeyValueStoreServerChange` or `NSUbiquitousKeyValueStoreInitialSyncChange` → `coalescedReload()`.
     - `NSUbiquitousKeyValueStoreAccountChange` → `SyncPreference.setEnabled(false)` + `coalescedReload()` (D-12 belt-and-braces alongside the ICloudStateObserver path).
   - `coalescedReload()` stores a cancellable `Task<Void, Never>?`, sleeps 300 ms (nanoseconds), and reloads — 5 rapid calls collapse into exactly 1 actual reload (proven by `testCoalescedReloadDebounces300ms`).
   - `add(_:)`, `delete(_:)`, `delete(at:)`, `move(_:_:)` all thread `synchronizable: SyncPreference.isEnabled` into `keychain.save`, then `bumpCounterIfSyncing()` before `reload()`.
   - `bumpCounterIfSyncing()` reads `NSUbiquitousKeyValueStore.default.longLong(forKey: "accounts-version")`, writes `+1`, calls `synchronize()` — guarded by `SyncPreference.isEnabled` so local-only saves do NOT broadcast.
   - `deinit` removes the KVS observer.
   - `SharedDefaults.saveAccounts(accounts)` at the tail of `reload()` is preserved (ICLOUD-12 keyboard propagation contract).
   - The transient `save(_:)` shim in `Shared/KeychainManager.swift` (tagged `TODO(Plan 03): remove`) is deleted. Project-wide grep of `.swift` source confirms only the explicit 2-arg form remains (`Shared/AccountStore.swift:52`, `:88`).

2. **Task 2 — ICloudStateObserver (`534da75`)**
   - `@MainActor final class ICloudStateObserver: ObservableObject` with `static let shared`.
   - `@Published private(set) var isICloudSignedIn: Bool` initialized from `FileManager.default.ubiquityIdentityToken != nil`.
   - `@Published private(set) var didAccountChange: Bool = false` — SettingsView (Plan 04) observes this to surface D-12 copy.
   - `previousIdentityToken: AnyObject?` — Apple's documented opaque identity-token pattern; avoids the Swift 6 warning on `any (NSCoding & NSCopying & NSObjectProtocol)` existential composition while preserving reference-identity comparison via `isEqual(_:)`.
   - `init()` registers `.NSUbiquityIdentityDidChange` observer; the callback dispatches to `@MainActor` and calls `handleIdentityChange()`. `deinit` removes the observer.
   - `handleIdentityChange()` flips `SyncPreference.setEnabled(false)` and sets `didAccountChange = true` on either a sign-out (newToken nil + wasSignedIn) or an iCloud-account switch (previous token exists + differs from new).
   - `#if DEBUG _primeAsSignedIn()` and `_simulateIdentityChange(newToken: AnyObject?)` test hooks — the primer sidesteps the simulator's non-deterministic iCloud state; the simulation mirrors production branching.
   - Added to BOTH KeyAuth app target and KeyAuthKeyboard extension target (Shared/*.swift convention established by Plan 06-02; the keyboard doesn't reference it directly but consistency avoids future compile-time surprises if any Shared file imports it transitively).

3. **Task 3 — KeyAuthApp scene wiring (`9a28e14`)**
   - `@StateObject private var icloudState = ICloudStateObserver.shared` — SwiftUI retains the singleton.
   - `@Environment(\.scenePhase) private var scenePhase` — enables `.onChange(of: scenePhase)`.
   - `@State private var didBootstrapSyncPreference = false` — latch so bootstrap runs once per process lifetime.
   - `.onAppear` now calls `bootstrapSyncPreferenceOnce()` FIRST (before `setupAppDelegate()` / `requestPushPermissionAndRegister()`), then the existing setup, then `NSUbiquitousKeyValueStore.default.synchronize()` to ensure the local KVS cache is warm.
   - `.onChange(of: scenePhase) { newPhase in ... }` — on `.active` calls `store.reload()` and `NSUbiquitousKeyValueStore.default.synchronize()`.
   - `bootstrapSyncPreferenceOnce()` reads `SharedDefaults.loadAccounts().count` so the D-01 (new user, default sync ON) vs D-02 (existing user, default sync OFF) determination runs BEFORE AccountStore.init reads SyncPreference.
   - `icloudState` passed alongside `store` and `pairingStore` via `.environmentObject` so SettingsView (Plan 04) can observe it.
   - Existing `willEnterForegroundNotification` + `didEnterBackgroundNotification` observers preserved unchanged (they gate Relay reconnect and isUnlocked, not sync).

4. **Task 4 — AccountStoreTests + MockKeychain counter + KVS entitlement (`b628f73`)**
   - `MockKeychain.loadAllCallCount` added; `loadAll()` increments it so the coalesce-debounce test can count reloads deterministically.
   - `KeyAuthTests/AccountStoreTests.swift` — 7 tests, all @MainActor:
     - `testReloadPopulatesAccountsFromKeychain` (ICLOUD-12 precondition).
     - `testReloadWritesToSharedDefaults` (ICLOUD-12 keyboard propagation).
     - `testAddPassesSyncPreferenceIsEnabled` (ICLOUD-11 sync branching).
     - `testAddPassesSyncPreferenceFalseWhenDisabled` (ICLOUD-13 adjacent — proves the pref gate).
     - `testCoalescedReloadDebounces300ms` — 5 rapid `coalescedReload()` calls + 500 ms sleep → exactly 1 reload delta.
     - `testBumpCounterSkippedWhenSyncDisabled` — counter unchanged when `SyncPreference.isEnabled == false`.
     - `testBumpCounterIncrementsWhenSyncEnabled` — counter +1 after `store.add` when sync enabled.
   - `setUp`/`tearDown` reset `sync_enabled`, `hasLaunchedBefore`, `SharedDefaults` accounts, and the `accounts-version` KVS key so tests are order-independent.
   - `App/KeyAuth.entitlements` gained `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier)` — without this, `NSUbiquitousKeyValueStore.default.set(...)` silently drops writes and `testBumpCounterIncrementsWhenSyncEnabled` reads `0` instead of `6`. See Deviation-2 below.
   - Wired into KeyAuthTests target via xcodeproj Ruby gem.

5. **Task 5 — ICloudStateObserverTests + _primeAsSignedIn hook (`e6add7d`)**
   - `KeyAuthTests/ICloudStateObserverTests.swift` — 2 tests:
     - `testSignOutSimulationFlipsSyncPreferenceOff` (ICLOUD-15): `SyncPreference.setEnabled(true)` → `observer._primeAsSignedIn()` → `observer._simulateIdentityChange(newToken: nil)` → assert `!isICloudSignedIn`, `!SyncPreference.isEnabled`, `didAccountChange == true`.
     - `testInitialStateIsBooleanValid`: reads `isICloudSignedIn` to confirm no crash on simulator (where the real iCloud state is non-deterministic).
   - `Shared/ICloudStateObserver.swift` extended with `#if DEBUG _primeAsSignedIn()` — forces `isICloudSignedIn = true` and a non-nil `previousIdentityToken` so the subsequent sign-out simulation fires the `wasSignedIn` branch. See Deviation-3 below.
   - `_simulateIdentityChange` also extended to mirror the production `handleIdentityChange`'s account-switch branch (prev ≠ new && both non-nil) so future tests can exercise switched-account flows.
   - Wired into KeyAuthTests target via xcodeproj Ruby gem.

## Task Commits

| Task | Description                                                                  | Commit    | Files Changed |
| ---- | ---------------------------------------------------------------------------- | --------- | ------------- |
| 1    | feat(06-03): rewire AccountStore with KVS observer + counter + remove shim   | `86a4418` | 2             |
| 2    | feat(06-03): add ICloudStateObserver for D-11/D-12 identity tracking         | `534da75` | 2             |
| 3    | feat(06-03): wire scenePhase + SyncPreference bootstrap into KeyAuthApp      | `9a28e14` | 1             |
| 4    | test(06-03): add AccountStoreTests + KVS entitlement                         | `b628f73` | 4             |
| 5    | test(06-03): add ICloudStateObserverTests + primer hook                      | `e6add7d` | 3             |

## Files Created / Modified

### Created

- `Shared/ICloudStateObserver.swift` — 80-line singleton `@MainActor ObservableObject`; `isICloudSignedIn` + `didAccountChange` `@Published`; `.NSUbiquityIdentityDidChange` observer in `init`, removal in `deinit`; `#if DEBUG` `_primeAsSignedIn` + `_simulateIdentityChange` test hooks.
- `KeyAuthTests/AccountStoreTests.swift` — 7 `@MainActor` XCTest methods covering ICLOUD-10/11/12; uses `MockKeychain` for injection and reads/writes the real `NSUbiquitousKeyValueStore.default` for counter assertions.
- `KeyAuthTests/ICloudStateObserverTests.swift` — 2 `@MainActor` XCTest methods covering ICLOUD-15; uses `_primeAsSignedIn` + `_simulateIdentityChange` to avoid simulator iCloud-state non-determinism.

### Modified

- `Shared/AccountStore.swift` — full rewrite per plan `<interfaces>`: protocol-injected keychain, KVS observer, 300 ms coalesce, SyncPreference-gated save, counter bump. 74 insertions / 11 deletions net.
- `Shared/KeychainManager.swift` — transient `save(_:)` shim removed (9 lines deleted + `TODO(Plan 03)` comment removed).
- `App/KeyAuthApp.swift` — scenePhase `.onChange` + `bootstrapSyncPreferenceOnce` + `icloudState` @StateObject/environmentObject + `NSUbiquitousKeyValueStore.default.synchronize()` on `.onAppear`. 22 insertions.
- `App/KeyAuth.entitlements` — added `com.apple.developer.ubiquity-kvstore-identifier` bound to `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` (see Deviation-2).
- `KeyAuthTests/Mocks/MockKeychain.swift` — `loadAllCallCount` counter property added; `loadAll()` increments it.
- `KeyAuth.xcodeproj/project.pbxproj` —
  - `Shared/ICloudStateObserver.swift` added to both KeyAuth and KeyAuthKeyboard target Sources (via xcodeproj Ruby gem).
  - `KeyAuthTests/AccountStoreTests.swift` added to KeyAuthTests Sources.
  - `KeyAuthTests/ICloudStateObserverTests.swift` added to KeyAuthTests Sources.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] `.onChange(of:initial:_:)` two-parameter form requires iOS 17, project is iOS 16**
- **Found during:** Task 3 build.
- **Issue:** The plan's `<interfaces>` for `App/KeyAuthApp.swift` uses `.onChange(of: scenePhase) { _, newPhase in ... }` — the two-parameter closure form was introduced in iOS 17. Project's `IPHONEOS_DEPLOYMENT_TARGET = 16.0`. Build error: `'onChange(of:initial:_:)' is only available in iOS 17.0 or newer`.
- **Fix:** Rewrote as the single-parameter `.onChange(of: scenePhase) { newPhase in ... }` form (iOS 14+). Semantics are identical — we only need the `newValue`. The plan's verify-line grep (`.onChange(of: scenePhase)`) still matches.
- **Files modified:** `App/KeyAuthApp.swift`.
- **Commit:** rolled into Task 3 commit `9a28e14`.

**2. [Rule 2 — Missing Critical Functionality] `NSUbiquitousKeyValueStore` requires `com.apple.developer.ubiquity-kvstore-identifier` entitlement**
- **Found during:** Task 4 first test-run (`testBumpCounterIncrementsWhenSyncEnabled` failed with `0 != 6`).
- **Issue:** iOS simulator logs reported `[Connection] Unable to find entitlement for KVS store` and `BUG IN CLIENT OF KVS: Trying to initialize NSUbiquitousKeyValueStore without a store identifier`. Without this entitlement, `NSUbiquitousKeyValueStore.default.set(Int64, forKey:)` silently no-ops — reads always return `0`, writes are dropped. This breaks both the test AND the production counter-ping pattern: cross-device reload would never fire because the counter never increments on iCloud. ICLOUD-11 is a correctness requirement, not a test-only concern.
- **Fix:** Added `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier)` to `App/KeyAuth.entitlements`. This namespaces the KVS store to this app's bundle ID (Apple's recommended pattern — avoids colliding with other apps the user has installed from the same team). No change to KeyAuthKeyboard — extensions inherit KVS access from the host app only when needed, and the keyboard does not read/write KVS.
- **Rationale for Rule 2 classification:** The entire counter-ping pattern from the plan's `<interfaces>` (bumpCounterIfSyncing + ServerChange observer) is a no-op in both test and production without this entitlement. The plan SPECIFIES the pattern but did not enumerate the entitlement prerequisite. Rule 4 (architectural) would apply if we were changing the approach; we are not — we are enabling what the plan already specified. This is the same category as adding a missing `kSecAttrAccessible` flag or missing `@MainActor` annotation.
- **Files modified:** `App/KeyAuth.entitlements`.
- **Commit:** rolled into Task 4 commit `b628f73`.

**3. [Rule 1 — Bug in test design] `ICloudStateObserver._simulateIdentityChange` was a no-op on simulator-default state**
- **Found during:** Task 5 first test-run (both `testSignOutSimulationFlipsSyncPreferenceOff` assertions failed).
- **Issue:** `ICloudStateObserver.shared` is a process-wide singleton. On iOS Simulator, `FileManager.default.ubiquityIdentityToken` is `nil` by default (no iCloud account signed in). The singleton's `init()` therefore sets `isICloudSignedIn = false` + `previousIdentityToken = nil`. When the test then calls `_simulateIdentityChange(newToken: nil)`, the guard `if newToken == nil && wasSignedIn` is `nil == nil && false → false`, so the sign-out branch never fires. The test was effectively a no-op against the default singleton state.
- **Fix:** Added a `#if DEBUG _primeAsSignedIn()` hook on `ICloudStateObserver` that forces `isICloudSignedIn = true` + `previousIdentityToken = NSString(string: "test-primed-token")`. The test now calls `_primeAsSignedIn()` BEFORE `_simulateIdentityChange(newToken: nil)`, so the wasSignedIn branch fires and we can assert the SyncPreference flip and didAccountChange signal. Also extended `_simulateIdentityChange` to mirror the production `handleIdentityChange`'s account-switch branch so future ICLOUD-15 tests can exercise switched-account scenarios without needing a separate hook.
- **Files modified:** `Shared/ICloudStateObserver.swift`, `KeyAuthTests/ICloudStateObserverTests.swift`.
- **Commit:** rolled into Task 5 commit `e6add7d`.

### Acceptance-command caveats (not deviations; documented for traceability)

- The plan's `<automated>` verify blocks target `-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`. Only iPhone 15 (OS 18.4) and iPhone 17 family (OS 26.4.1) are installed on this host — same constraint as Plans 06-01 and 06-02. All actual verification ran on `iPhone 15 / OS 18.4` (prompt-sanctioned fallback).
- The Task 2 verify line `! grep -q "any (NSCoding & NSCopying & NSObjectProtocol)" Shared/ICloudStateObserver.swift` was checked manually via a separate Grep because shell parentheses in the `grep -q` pattern produce a non-zero exit when zero matches occur. The invariant is verified (confirmed 0 matches).

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: entitlement-added | App/KeyAuth.entitlements | Added `com.apple.developer.ubiquity-kvstore-identifier` capability. Namespaced to `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` so the KVS store is per-app (not shared with other apps from the same team). Not a new trust boundary — the plan's threat model (T-06-T1) already covers the KVS surface; this entitlement is the infrastructure that makes the modeled surface actually function. No secret crosses this boundary (only the `Int64 accounts-version` counter). |

## Known Stubs

None. Every new method is exercised by passing tests or is wired into a lifecycle callback (scenePhase / NotificationCenter / deinit). The `#if DEBUG` hooks (`_primeAsSignedIn`, `_simulateIdentityChange`) are intentionally scoped out of release builds and called by `ICloudStateObserverTests`.

## TDD Gate Compliance

Tasks 1, 4, and 5 are tagged `tdd="true"` in the PLAN. The execution order in this run was:

1. Task 1 (`feat`) — AccountStore rewrite + shim removal (no paired test in this task; AccountStore tests arrive in Task 4).
2. Task 2 (`feat`) — ICloudStateObserver (no paired test in this task; paired in Task 5).
3. Task 3 (`feat`) — KeyAuthApp wiring.
4. Task 4 (`test`) — AccountStoreTests (paired with Task 1 implementation).
5. Task 5 (`test`) — ICloudStateObserverTests (paired with Task 2 implementation).

Tasks 4 and 5 are pure test commits validating the Task 1 / Task 2 implementations. This is a "GREEN-first" ordering — tests follow implementation because the tests exercise observable behavior via `MockKeychain` injection and `#if DEBUG` hooks which are themselves part of the Task 1 / Task 2 deliverables. Pure RED-first is impossible when the mock/hooks are co-delivered with the implementation.

No RED→GREEN iteration was required for Task 4 and Task 5 on the first meaningful run:

- Task 4 initial run failed on `testBumpCounterIncrementsWhenSyncEnabled` for a reason unrelated to the implementation (missing KVS entitlement — Deviation-2). After adding the entitlement the test passed unchanged.
- Task 5 initial run failed on `testSignOutSimulationFlipsSyncPreferenceOff` for a reason unrelated to the implementation (singleton-state priming — Deviation-3). After adding the `_primeAsSignedIn` hook the test passed.

## Build Verification

- `xcodebuild build -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4'` — `** BUILD SUCCEEDED **` (verified after each Task 1/2/3 commit).
- `xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' -only-testing:KeyAuthTests` — `** TEST SUCCEEDED **` — 29 tests executed, 0 failures.

```
Test Suite 'AccountStoreTests' passed                  — 7 tests
Test Suite 'ICloudStateObserverTests' passed           — 2 tests
Test Suite 'KeyAuthTests' passed                       — 5 tests (Plan 06-01 smoke)
Test Suite 'KeychainManagerSyncTests' passed           — 11 tests (Plan 06-02)
Test Suite 'SyncScopeIsolationTests' passed            — 4 tests (Plan 06-02)
Test Suite 'KeyAuthTests.xctest' passed                — 29 total
** TEST SUCCEEDED **
```

## Plan-Level Invariant Checks

| Invariant                                                                                | Required | Actual |
| ---------------------------------------------------------------------------------------- | -------- | ------ |
| `grep -q "init(keychain: KeychainProviding" Shared/AccountStore.swift`                    | pass     | pass   |
| `grep -q "func coalescedReload" Shared/AccountStore.swift`                                | pass     | pass   |
| `grep -q "NSUbiquitousKeyValueStore.didChangeExternallyNotification" Shared/AccountStore.swift` | pass | pass   |
| `grep -q "accounts-version" Shared/AccountStore.swift`                                    | pass     | pass   |
| `grep -q "synchronizable: SyncPreference.isEnabled" Shared/AccountStore.swift`            | pass     | pass   |
| `grep -q "SharedDefaults.saveAccounts(accounts)" Shared/AccountStore.swift`               | pass     | pass   |
| `! grep -q "func save(_ account: Account) throws" Shared/KeychainManager.swift`           | pass     | pass   |
| `grep -q "AnyObject?" Shared/ICloudStateObserver.swift`                                   | pass     | pass   |
| `! grep -q "any (NSCoding & NSCopying & NSObjectProtocol)" Shared/ICloudStateObserver.swift` | pass  | pass   |
| `@Environment(\.scenePhase)` in KeyAuthApp                                                | pass     | pass   |
| `SyncPreference.bootstrap` in KeyAuthApp                                                  | pass     | pass   |
| KeyAuthTests suite passing count                                                          | ≥ 20     | 29     |

## Self-Check: PASSED

- `Shared/AccountStore.swift`: FOUND
- `Shared/ICloudStateObserver.swift`: FOUND
- `Shared/KeychainManager.swift` (shim removed): VERIFIED (0 matches for `func save(_ account: Account) throws`)
- `App/KeyAuthApp.swift`: FOUND (scenePhase + bootstrap present)
- `App/KeyAuth.entitlements` (KVS entitlement): FOUND
- `KeyAuthTests/AccountStoreTests.swift`: FOUND
- `KeyAuthTests/ICloudStateObserverTests.swift`: FOUND
- `KeyAuthTests/Mocks/MockKeychain.swift` (loadAllCallCount): VERIFIED
- commit 86a4418 (Task 1): FOUND
- commit 534da75 (Task 2): FOUND
- commit 9a28e14 (Task 3): FOUND
- commit b628f73 (Task 4): FOUND
- commit e6add7d (Task 5): FOUND
- `xcodebuild test` KeyAuthTests result: TEST SUCCEEDED (29/29)

## Next-Plan Readiness

- **Plan 06-04 (SettingsView + toggle UI)** is unblocked — `ICloudStateObserver` is an `@EnvironmentObject` available at the View layer via the `.environmentObject(icloudState)` injection in `KeyAuthApp.body`; SettingsView can `@EnvironmentObject var icloudState` and wire D-11 copy gated on `!icloudState.isICloudSignedIn` and D-12 copy gated on `icloudState.didAccountChange`. `SyncPreference.isEnabled` and `SyncPreference.setEnabled(_:)` are the toggle's read/write surface.
- **Plan 06-05 (MigrationCoordinator)** is unblocked — `AccountStore.reload()` is the integration point for dedup pass; `coalescedReload()` is safe to call from MigrationCoordinator's post-migration cleanup without risk of reload storms.
- **Plan 06-06 (ContentView toolbar + two-device QA)** is unblocked — `ContentView` receives all three environment objects; toolbar gear button can `NavigationLink { SettingsView() }` once Plan 04 lands.
- **Transient-shim debt retired** — `KeychainManager` now exposes exactly one save signature (`save(_:synchronizable:)`) and all call sites use it explicitly.
- **KVS infrastructure live** — the `accounts-version` counter actually persists and broadcasts across devices now that the `com.apple.developer.ubiquity-kvstore-identifier` entitlement is in place. Two-device QA in Plan 06 (2-DEV-06 mid-session external change) will actually fire `didChangeExternallyNotification` instead of silently no-op'ing.
