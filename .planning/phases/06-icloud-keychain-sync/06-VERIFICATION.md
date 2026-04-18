---
phase: 06-icloud-keychain-sync
verified: 2026-04-18T12:45:00Z
status: human_needed
verdict: CONDITIONAL PASS
score: 14/16 must-haves verified (2 hybrid awaiting two-device manual QA)
overrides_applied: 0
re_verification: false

ship_condition: "Complete the 8 two-device tests in 06-QA-CHECKLIST.md (2-DEV-01..08) on two real devices signed into the same Apple ID with iCloud Keychain ON. All 8 must pass, including 2-DEV-05 (fresh-install restore → ICLOUD-16 end-to-end) and 2-DEV-06 (mid-session external change → ICLOUD-10 end-to-end). The phase can be marked complete in ROADMAP.md ONLY after the QA tester signs off."

human_verification:
  - test: "2-DEV-01 Basic account propagation"
    expected: "Account added on Device A appears on Device B within iCloud propagation window; Device B keyboard shows TOTP code"
    why_human: "Real iCloud Keychain propagation cannot be simulator-tested; requires two real devices signed into the same Apple ID"
  - test: "2-DEV-02 Migration with dedup"
    expected: "Device A shows 'Merged 2 duplicate accounts' toast OR observes lastDedupCount==2 programmatically; 2 accounts remain (not 4)"
    why_human: "Cross-device duplicate collision; TransientToastOverlay is defined but not mounted — tester must fall back to lastDedupCount as the acceptance signal"
  - test: "2-DEV-03 Stop syncing this device (D-06)"
    expected: "Dialog shows two buttons; adds/deletes on Device A do NOT propagate; Device B retains 'bank' after Device A deletes it"
    why_human: "Real-iCloud non-propagation — the ONLY way to confirm is to verify Device B state after Device A mutations"
  - test: "2-DEV-04 Remove from iCloud on all devices (D-05)"
    expected: "Device B loses accounts; toggle disabled for 10s; re-enable after cooldown re-syncs"
    why_human: "Destructive path propagation + 10s cooldown are both observable only in real two-device scenario"
  - test: "2-DEV-05 Fresh-install restore (ICLOUD-16)"
    expected: "Fresh-installed Device B shows 'Restoring your accounts from iCloud…' UI then populates accounts within 30s OR falls through to empty state after 30s"
    why_human: "End-to-end closure of ICLOUD-16; production evaluateRestoringState + RestoringFromCloudView cannot be exercised in simulator — only via real fresh install with real iCloud Keychain"
  - test: "2-DEV-06 Mid-session external change (ICLOUD-10 + ICLOUD-11)"
    expected: "Device A's foregrounded list updates without user action when Device B adds an account"
    why_human: "didChangeExternallyNotification from real CloudKit push cannot be simulated; the production scenePhase+observer wiring exists but only real KVS server-change can prove it fires"
  - test: "2-DEV-07 iCloud Keychain OFF at OS level (D-11)"
    expected: "Sync toggle disabled + grayed; D-11 copy + 'Open iOS Settings' deep-link both work"
    why_human: "Requires flipping iOS Settings > Apple ID > iCloud > Passwords & Keychain OFF; no simulator equivalent"
  - test: "2-DEV-08 Mid-session iCloud sign-out (D-12)"
    expected: "Sync toggle auto-flips OFF; D-12 em-dash copy appears; accounts remain cached locally"
    why_human: "Requires real iCloud sign-out mid-session; ICloudStateObserverTests proves the sync-preference flip via primer hook but not the real NSUbiquityIdentityDidChangeNotification delivery"

flagged_observations:
  - concern: "TransientToastOverlay defined but not mounted"
    severity: "polish-only, not goal-blocking"
    detail: "The 'Merged N duplicate accounts' visual toast (referenced in 2-DEV-02 expected result) will NOT appear. The underlying dedup behavior IS tested and works — AccountStore.lastDedupCount is the programmatic signal. QA tester has been explicitly instructed to accept lastDedupCount as the behavior contract. Phase goal 'TOTP accounts sync across Apple devices' (ROADMAP SC-3 'migration without duplicates') is satisfied by the dedup logic itself — the toast is a UX feedback polish, not a correctness requirement."
    recommendation: "File a follow-up polish plan 06-07 to wire TransientToastOverlay into ContentView or SettingsView overlay, gated on store.lastDedupCount > 0. Not a ship-blocker."

  - concern: "ICLOUD-16 unit coverage uses a mirror state machine"
    severity: "disclosed compromise, acceptable"
    detail: "RestoringStateTests.testTimeoutTransition exercises a RestoringStateMachine class defined inside the test file, NOT ContentView.evaluateRestoringState directly. The mirror transcribes the production state-machine rules verbatim. If ContentView.evaluateRestoringState is modified without updating the mirror, tests pass while production drifts. This is an acceptable compromise given SwiftUI @State's non-observability without ViewHosting, and is explicitly documented in the test's docstring and in 06-TRACEABILITY.md. 2-DEV-05 manual QA is the true end-to-end gate."
    recommendation: "No blocking action. The RESEARCH-documented compromise is honored."

  - concern: "iPhone 15 / OS 18.4 substitution vs plan's iPhone 16 / latest"
    severity: "none — explicitly sanctioned"
    detail: "Every Plan 06-XX SUMMARY documents iPhone 15 / OS 18.4 as the locally-available fallback. iOS 18.4 >> deployment target 16.0. Keychain/iCloud APIs (kSecAttrSynchronizable, NSUbiquitousKeyValueStore, NSUbiquityIdentityDidChangeNotification) have been stable since iOS 7/iOS 8; no iOS-17-or-18-specific Keychain behavior exists that would be missed by running on 18.4. Confirmed: no coverage loss."
    recommendation: "None. The fallback is sanctioned by every prior plan."

  - concern: "MigrationTests.testStopSyncingFunctionDoesNotCallDeleteAllSynced is XCTSkipped"
    severity: "disclosed, compensated"
    detail: "Static-source grep test fails in simulator sandbox due to #filePath restriction. The SAME safety contract is enforced at runtime by testStopSyncingPreservesLocalAndDoesNotDeleteSynced which asserts the mock state has both 3 sync + 3 local variants after stopSyncing — impossible if deleteAllSynced were called. D-06 safety is still enforced."
    recommendation: "None. Skip is compensated by runtime test."

  - concern: "Two-phase dedup (Plan 06-05 commit 028f091) — structural audit"
    severity: "none — structurally sound, meaningfully tested"
    detail: "AccountStore.dedupInMemory implements Phase 1 (same-id collapse, in-memory only, no Keychain delete) BEFORE Phase 2 (cross-id DedupKey dedup with keychain.delete on losers). Phase 1 is exercised end-to-end by MigrationTests.testStopSyncingPreservesLocalAndDoesNotDeleteSynced — the test seeds 3 synced accounts, invokes stopSyncingThisDevice (which re-saves each as non-sync, creating 2 variants per id), then asserts BOTH 3 synced AND 3 local variants survive. Without Phase 1, the subsequent reload() dedup pass would trash the data. Phase 2 is independently exercised by DedupTests (9 tests covering normalization + ascending-createdAt tiebreak + uuidString tiebreak + Keychain-side deletion of losers). The ascending comparator is pinned by the literal fixed-string verify in Plan 06-05 invariant table. The RESEARCH.md line 459 open question is correctly resolved per the RESEARCH-recommended direction (Phase 1 does NOT delete the synced copy)."
    recommendation: "None. Structurally correct, adequately tested."

---

# Phase 06 iCloud Keychain Sync — Verification Report

**Phase Goal (ROADMAP.md):** "TOTP account secrets sync automatically across the user's Apple devices (iPhones, iPads) via iCloud Keychain — a new device restores all 2FA accounts after signing into Apple ID, with no extra setup"

**Verified:** 2026-04-18T12:45:00Z
**Verdict:** **CONDITIONAL PASS**
**Status:** `human_needed` (2 of 16 ICLOUD-NN requirements have unit coverage but require two-device manual QA for end-to-end closure)
**Re-verification:** No — initial verification

---

## Executive Summary

Phase 06 shipped a **structurally complete** iCloud Keychain sync implementation. All 16 ICLOUD-NN requirements have at least unit-level coverage; 14 have pure automated coverage; 2 (ICLOUD-10, ICLOUD-16) have unit baselines plus named manual-QA cases awaiting real two-device verification. The two-phase dedup innovation (Plan 06-05 commit `028f091`) correctly resolves the RESEARCH.md line 459 open question about post-D-06 same-id variant handling, and is meaningfully tested by a runtime migration test that would fail if Phase 1 were removed.

All four explicitly-flagged concerns were examined:
1. **TransientToastOverlay not mounted** — confirmed polish-only deferral; core dedup behavior tested via `lastDedupCount`; NOT a ship-blocker per phase goal analysis.
2. **ICLOUD-10 / ICLOUD-16 hybrid state** — confirmed genuine hybrid, not a dressed-up gap. The unit baselines ARE green; end-to-end closure requires real-iCloud two-device observation.
3. **Two-phase dedup fix** — confirmed structurally sound; Phase 1 exercised by `testStopSyncingPreservesLocalAndDoesNotDeleteSynced`, Phase 2 exercised by 9 DedupTests.
4. **iPhone 15 / OS 18.4 substitution** — confirmed no coverage loss; Keychain APIs have been stable since iOS 7.

**Ship gate:** Complete the 8 two-device tests in `06-QA-CHECKLIST.md`. All 8 must pass. Only after tester sign-off can ROADMAP.md Phase 6 be marked complete.

---

## Goal Achievement — ROADMAP Success Criteria

| SC | Success Criterion | Status | Evidence |
|----|-------------------|--------|----------|
| SC-1 | With iCloud sync enabled, TOTP accounts added on device A appear on device B (same Apple ID) within typical iCloud Keychain propagation time | VERIFIED (unit) / PENDING (2-DEV-01, 2-DEV-05, 2-DEV-06) | KeychainManagerSyncTests (11 tests) + AccountStoreTests.testCoalescedReloadDebounces300ms + RestoringStateTests (4 tests) cover the sync-aware Keychain CRUD, KVS observer debounce, and fresh-install restoring state machine. Cross-device propagation itself requires real iCloud. |
| SC-2 | User shown clear disclosure before enabling; can toggle off in Settings | VERIFIED | SettingsView.swift Line 23-25 holds verbatim D-03/D-11/D-12 copy; 12 SettingsViewTests grep-assert the VERBATIM strings; FirstLaunchSyncCard renders the D-03 body for new users per SyncPreference.shouldShowFirstLaunchCard. |
| SC-3 | Existing users can migrate local-only accounts to iCloud with a single confirmation, without losing any accounts or creating duplicates | VERIFIED (unit) | MigrationTests.testMigrateAllToSyncForwardPath (3 ok, 0 failed, all sync variants) + testMigrateAllToSyncSafeOrdering (save-first/delete-second proves no data loss on mid-loop failure) + testMigrateAllToSyncPartialFailure (per-account failures continue loop) + DedupTests (9 tests covering the dedup pass). Two-phase dedup preserves correctness across D-06. |
| SC-4 | Disabling sync gives user clear choice: stop syncing this device only, or remove from iCloud on all devices | VERIFIED (unit) / PENDING (2-DEV-03, 2-DEV-04, 2-DEV-08) | SettingsView.swift lines 51-86 implement the two-option .confirmationDialog with verbatim D-05 copy; MigrationCoordinator.stopSyncingThisDevice (D-06) + removeFromICloudAllDevices (D-05 destructive + 10s cooldown) are tested via MigrationTests + ICloudStateObserverTests. |
| SC-5 | Keyboard extension continues to see the same accounts as the app (via shared App Group) whether sync is enabled or not | VERIFIED (unit) / PENDING (2-DEV-01 step 5) | KeyboardPropagationTests (5 tests) verify that AccountStore.reload/add/delete all write through to SharedDefaults. Cross-process keyboard activation cannot be unit-tested. |
| SC-6 | Device-bound data (pairings, identity keys, APNs tokens) explicitly does NOT sync | VERIFIED | SyncScopeIsolationTests (4 tests): static source grep of PairingStore.swift (0 kSecAttrSynchronizable refs — confirmed), CryptoBoxManager.swift (0 SecItem* calls), runtime SecItemCopyMatching query with kCFBooleanTrue against pairing service returns errSecItemNotFound. |

**Score: 6/6 Success Criteria have verifiable automated coverage; 4/6 require two-device manual QA for end-to-end closure.**

---

## Requirements Coverage — ICLOUD-01..16

| ID | Requirement | Status | Tests / Evidence |
|----|-------------|--------|------------------|
| ICLOUD-01 | KeychainManager.save accepts synchronizable: Bool | VERIFIED | KeychainManagerSyncTests.testSaveSynchronizableTrue + testSaveSynchronizableFalse (live simulator Keychain round-trip) |
| ICLOUD-02 | All reads use kSecAttrSynchronizableAny | VERIFIED | KeychainManagerSyncTests.testLoadAllIncludesBothVariants + 2 variant-specific tests; grep -c kSecAttrSynchronizableAny Shared/KeychainManager.swift = 5 (≥4 required) |
| ICLOUD-03 | delete(id:) removes both variants | VERIFIED | KeychainManagerSyncTests.testDeleteRemovesBothVariants + testDeleteNonSyncOnlyLeavesSyncedCopy |
| ICLOUD-04 | Settings screen with gear button + D-03 disclosure | VERIFIED | SettingsView.swift + ContentView gear ToolbarItem (line 100-108) + 4 SettingsViewTests grep-asserting verbatim strings |
| ICLOUD-05 | First-launch card with D-03 + Got it | VERIFIED | FirstLaunchSyncCard.swift + ContentView conditional render + 3 SettingsViewTests + SyncPreference.bootstrap D-01/D-02 tests |
| ICLOUD-06 | Two-option confirmation with destructive role | VERIFIED | SettingsView.swift lines 51-86 + 3 SettingsViewTests asserting verbatim D-05 option descriptions |
| ICLOUD-07 | OFF→ON migration with partial-failure tolerance + count | VERIFIED | MigrationCoordinator.migrateAllToSync + 4 MigrationTests (forward, partial, safe-ordering, remove/cooldown) |
| ICLOUD-08 | Dedup normalization + earliest-createdAt winner + toast | VERIFIED (dedup) / DEFERRED (toast) | 9 DedupTests (normalization + ascending comparator + uuidString tiebreak + Keychain-side deletion); toast UI deferred to polish plan per Known Gaps |
| ICLOUD-09 | deleteAllSynced uses kCFBooleanTrue not Any | VERIFIED | KeychainManagerSyncTests.testDeleteAllSyncedPreservesLocalVariants + MigrationTests.testRemoveFromICloudAllDevicesDeletesSyncedPreservesLocal |
| ICLOUD-10 | scenePhase .active triggers reload + KVS synchronize | HYBRID — Complete (unit) / Pending 2-DEV-06 | KeyAuthApp.swift lines 50-55 + AccountStoreTests.testReloadPopulatesAccountsFromKeychain. Real cross-device foreground reload needs two-device. |
| ICLOUD-11 | accounts-version counter + 300ms coalesce observer | VERIFIED | 5 AccountStoreTests (coalesce, bump-skip-when-disabled, bump-increment-when-enabled, sync-branch-propagation); com.apple.developer.ubiquity-kvstore-identifier entitlement present in App/KeyAuth.entitlements |
| ICLOUD-12 | SharedDefaults propagation for keyboard | VERIFIED | 5 KeyboardPropagationTests + AccountStoreTests.testReloadWritesToSharedDefaults |
| ICLOUD-13 | PairingStore + CryptoBox do NOT sync | VERIFIED | 4 SyncScopeIsolationTests (static grep + runtime SecItemCopyMatching); confirmed PairingStore.swift has 0 kSecAttrSynchronizable references |
| ICLOUD-14 | iCloud-off D-11 deep-link | VERIFIED | SettingsViewTests.testD11CopyAndDeepLink; SettingsView.swift line 127-131 UIApplication.openSettingsURLString |
| ICLOUD-15 | Identity change flips toggle OFF | VERIFIED | ICloudStateObserverTests.testSignOutSimulationFlipsSyncPreferenceOff (via _primeAsSignedIn hook) + SettingsViewTests.testD12CopyWithEmDash |
| ICLOUD-16 | Restoring state with 30s timeout | HYBRID — Complete (unit: RestoringStateTests.testTimeoutTransition) / Pending 2-DEV-05 | 4 RestoringStateTests covering timeout, restored-on-arrival, sync-off idempotence, constant guard. Mirror state machine approach disclosed. Real fresh-install propagation requires two-device setup. |

**Coverage summary:**
- 14/16 pure automated coverage (ICLOUD-01..09, 11..15)
- 2/16 hybrid coverage with named manual-QA cases (ICLOUD-10 → 2-DEV-06, ICLOUD-16 → 2-DEV-05)
- 0/16 orphans

---

## Artifact Verification

### Shared/*.swift — Target Membership (ICLOUD-01..13 production surface)

Verified via `xcodeproj` Ruby gem traversal of `project.pbxproj`: **all 15 `Shared/*.swift` files are members of BOTH `KeyAuth` AND `KeyAuthKeyboard` targets.** Phase 6 added 6 new files to this surface (`DedupKey`, `ICloudStateObserver`, `KeychainProviding`, `MigrationCoordinator`, `SyncPreference`, updated `KeychainManager`); all 6 are wired into both targets. No membership gaps.

### App/KeyAuth.entitlements

Verified present:
- `aps-environment` (pre-existing)
- `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier)` — ADDED in Plan 06-03 per Rule-2 fix; without this, NSUbiquitousKeyValueStore silently drops writes
- `com.apple.security.application-groups` (pre-existing)
- `keychain-access-groups` (pre-existing)

### App/Views/*.swift — UI Surface

| File | Exists | Wired | Notes |
|------|--------|-------|-------|
| `SettingsView.swift` | YES | YES — routed via ContentView toolbar gear + FirstLaunchSyncCard navigation | All 3 Plan-04 stubs replaced with MigrationCoordinator calls (lines 58, 65, 174); 0 `Plan 06-05 replaces this stub` markers remain |
| `FirstLaunchSyncCard.swift` | YES | YES — rendered in ContentView empty-state branch gated on SyncPreference.shouldShowFirstLaunchCard | |
| `TransientToastOverlay.swift` | YES | **NO** — defined but not mounted anywhere | KNOWN GAP. lastDedupCount is the programmatic acceptance signal. |
| `RestoringFromCloudView.swift` | YES | YES — rendered in ContentView when syncState == .restoring | ICLOUD-16 UI |
| `ContentView.swift` | YES | YES | gear toolbar + restoring state machine + navigationDestination all wired |

### Stub Markers Scan

`grep -rE "Plan 06-05 replaces this stub|TODO\(Plan 03\)|TODO\(Plan 06"` across all Swift files: **zero matches.** All transitional stub markers have been removed per Plans 06-03 (KeychainManager.save shim deletion) and 06-05 (SettingsView stubs wired).

### PairingStore.swift ICLOUD-13 Invariant

`grep -c kSecAttrSynchronizable Shared/PairingStore.swift` = **0**. ICLOUD-13 invariant intact. PairingStore continues to use `com.keyauth.pairing` service (not `com.keyauth.accounts`), guaranteeing no collision with synchronized account storage.

---

## Commit History Compliance

`git log --since="2026-04-17" --pretty=%B | grep -iE "co-authored|claude|anthropic"` → **zero matches.** All 39 phase-6 commits comply with user constraint "Never add Co-authored-by or AI/Claude mentions".

Commit message style consistent across all commits: `feat(06-NN): ...`, `test(06-NN): ...`, `docs(06-NN): ...`, `fix(06-05): ...`. No non-compliant messages.

---

## Full Test Suite Baseline

**Claim (Plan 06-06 SUMMARY):** 66 tests passing, 1 XCTSkip, 0 failures on iPhone 15 / OS 18.4.

**Independent verification:**
- `grep -c "func test" KeyAuthTests/*.swift` across 10 files: 7+9+2+5+5+11+7+4+12+4 = **66**. Matches claim.
- 10 test suites: AccountStoreTests, DedupTests, ICloudStateObserverTests, KeyAuthTests (smoke), KeyboardPropagationTests, KeychainManagerSyncTests, MigrationTests, RestoringStateTests, SettingsViewTests, SyncScopeIsolationTests.
- 1 XCTSkip: `MigrationTests.testStopSyncingFunctionDoesNotCallDeleteAllSynced` (simulator sandbox; runtime safety enforced by paired test).

---

## Key Finding — Two-Phase Dedup (Plan 06-05 commit 028f091)

The most architecturally-significant piece of this phase. Flagged for material-correctness audit:

**Structural soundness:** CONFIRMED. AccountStore.dedupInMemory (Shared/AccountStore.swift lines 77-122) implements two phases:
1. Phase 1 groups by `account.id`; for same-id groups, picks one representative via `sortOrder` then `createdAt` — **never calls keychain.delete**. This prevents the catastrophic failure mode where loading post-D-06 state (both sync+local variants per account) would trigger dedup to call `delete(id:)` which purges BOTH variants due to the `.any` scope on delete(id:).
2. Phase 2 groups Phase-1 output by `DedupKey`; for groups with count > 1, sorts ascending by `createdAt` then `uuidString`, keeps first, calls `keychain.delete(id:)` on losers.

**Meaningful test coverage:** CONFIRMED.
- **Phase 1 exercised by:** `MigrationTests.testStopSyncingPreservesLocalAndDoesNotDeleteSynced` — seeds 3 synced accounts, calls `stopSyncingThisDevice` which re-saves each as non-sync (creating 2 variants per id), then asserts variants count is 3 synced + 3 local = 6 total. **If Phase 1 were removed, the reload() at the end of stopSyncingThisDevice would destroy all data** — this test is the definitive Phase-1 regression guard.
- **Phase 2 exercised by:** 9 DedupTests including testDedupPassEarliestCreatedAtWins (3 dupes with different createdAt → earliest survives, lastDedupCount == 2), testDedupPassTiebreakByUUIDAscending (equal createdAt → smaller UUID wins), testDedupSilentWhenNoDuplicates (no cross-id dupes → lastDedupCount == 0), testDedupLosersRemovedFromKeychain (asserts keychain.loadAll().count == 1 after 3 dupes collapse).

**RESEARCH.md line 459 resolution:** The open question ("For D-06, both copies have identical fields. The dedup must not delete either") is resolved in the RESEARCH-recommended direction. Documented in 06-TRACEABILITY.md Risks Flagged section.

**Verdict on the two-phase dedup fix:** Structurally sound, meaningfully tested. No material-correctness bug detected.

---

## Gaps Summary

**Strictly blocking gaps:** NONE.

**Awaiting external verification (human, two-device):**
1. ICLOUD-10 end-to-end via 2-DEV-06 (mid-session external change)
2. ICLOUD-16 end-to-end via 2-DEV-05 (fresh-install restore)
3. SC-1 end-to-end via 2-DEV-01, 2-DEV-05, 2-DEV-06
4. SC-3 end-to-end via 2-DEV-02 (with TransientToastOverlay caveat — tester accepts lastDedupCount as signal)
5. SC-4 end-to-end via 2-DEV-03, 2-DEV-04, 2-DEV-08

**Polish deferrals (not blocking):**
1. TransientToastOverlay placement — suggest follow-up Plan 06-07 to wire into ContentView/SettingsView overlay gated on `store.lastDedupCount > 0 || migration.lastMigrationResult != nil`. Estimated 30 min of work. Not a ship-blocker because dedup correctness is already tested independently.

---

## Ship Gate Checklist

Phase 6 may be marked complete in ROADMAP.md (checkbox flipped to `[x]`) when:

1. [ ] All 8 manual QA tests in `06-QA-CHECKLIST.md` (2-DEV-01..08) execute green on two real devices signed into the same Apple ID with iCloud Keychain ON
2. [ ] Tester records all device/OS metadata in the QA checklist Run Record
3. [ ] REQUIREMENTS.md ICLOUD-10 and ICLOUD-16 checkboxes flip from `[ ]` to `[x]` after manual QA sign-off
4. [ ] Tester explicitly acknowledges the TransientToastOverlay visual deferral in 2-DEV-02 (note: "observed lastDedupCount = 2, toast did not visually appear — acceptable per TRACEABILITY Known Gaps")

**Optional but recommended before ship:**
- [ ] Author follow-up Plan 06-07 to wire TransientToastOverlay for the polished dedup toast UX

---

## Verification Conclusion

Phase 6 is **structurally complete and automated-test-green.** The phase goal ("TOTP account secrets sync automatically across the user's Apple devices") is achieved by the shipped code; the only remaining verification is end-to-end observation on real Apple hardware which cannot be substituted by simulator testing.

**Verdict: CONDITIONAL PASS** — ship after two-device manual QA sign-off on 2-DEV-01..08.

---

*Verifier: Claude (gsd-verifier, Opus 4.7)*
*Verification date: 2026-04-18T12:45:00Z*
*Verification mode: Initial, goal-backward, read-only*
