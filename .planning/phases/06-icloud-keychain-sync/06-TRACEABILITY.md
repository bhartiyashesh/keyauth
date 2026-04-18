---
phase: 06-icloud-keychain-sync
document: traceability-audit
status: final
---

# Phase 6 — Requirement Traceability Audit

> Every ICLOUD-NN requirement mapped to an automated test, manual QA test, or both. No orphans.
> Every "Complete (unit)" claim names a specific test method (truth-in-claims gate).

## Automated Coverage (XCTest)

| Requirement | Behavior | Automated Test(s) | Status |
|-------------|----------|-------------------|--------|
| ICLOUD-01 | `save(_:synchronizable:)` persists sync attr | `KeychainManagerSyncTests.testSaveSynchronizableTrue`, `.testSaveSynchronizableFalse`, `.testSaveSetsAccessibleAfterFirstUnlock` | Complete (automated) |
| ICLOUD-02 | `loadAll()` uses SynchronizableAny | `KeychainManagerSyncTests.testLoadAllIncludesBothVariants`, `.testLoadAllWithOnlyLocalVariant`, `.testLoadAllWithOnlySyncVariant` | Complete (automated) |
| ICLOUD-03 | `delete(id:)` removes both variants | `KeychainManagerSyncTests.testDeleteRemovesBothVariants`, `.testDeleteNonSyncOnlyLeavesSyncedCopy` | Complete (automated) |
| ICLOUD-04 | Settings surface + D-03 disclosure | `SettingsViewTests.testSyncSectionFooterContainsD03Verbatim`, `.testToggleLabelMatchesUISpec`, `.testHowSecuredDisclosureGroup`, `.testSettingsViewInstantiationDoesNotCrash` | Complete (automated) |
| ICLOUD-05 | First-launch card for new users | `SettingsViewTests.testFirstLaunchCardTitle`, `.testFirstLaunchCardBodyIsD03Verbatim`, `.testFirstLaunchCardCTAs`; `KeyAuthTests.testSyncPreferenceBootstrapNewUser`, `.testSyncPreferenceBootstrapExistingUser` | Complete (automated) |
| ICLOUD-06 | Two-option disable confirmation + D-05 per-option descriptions in message | `SettingsViewTests.testDisableDialogTwoOptions`, `.testDisableDialogMessageBodyVerbatim`, `.testDisableDialogOptionDescriptionsVerbatim` | Complete (automated) |
| ICLOUD-07 | Migration forward + reverse + partial failure | `MigrationTests.testMigrateAllToSyncForwardPath`, `.testMigrateAllToSyncPartialFailure`, `.testMigrateAllToSyncSafeOrdering`, `.testStopSyncingPreservesLocalAndDoesNotDeleteSynced`, `.testStopSyncingFunctionDoesNotCallDeleteAllSynced` (XCTSkip in simulator sandbox — static source grep), `.testRemoveFromICloudSetsCooldown`; `KeychainManagerSyncTests.testMigrationSafeOrdering` | Complete (automated) |
| ICLOUD-08 | Dedup normalization + tiebreaker | `DedupTests.testDedupKeyCaseInsensitiveIssuer`, `.testDedupKeyTrimsIssuerWhitespace`, `.testDedupKeyUnicodeNFC`, `.testDedupKeyStripsAllSecretWhitespace`, `.testDedupKeySecretCaseInsensitive`, `.testDedupPassEarliestCreatedAtWins`, `.testDedupPassTiebreakByUUIDAscending`, `.testDedupSilentWhenNoDuplicates`, `.testDedupLosersRemovedFromKeychain`; `KeyAuthTests.testDedupKeyNormalization` | Complete (automated) |
| ICLOUD-09 | `deleteAllSynced` uses synchronizable=true not Any | `KeychainManagerSyncTests.testDeleteAllSyncedPreservesLocalVariants`; `MigrationTests.testRemoveFromICloudAllDevicesDeletesSyncedPreservesLocal` | Complete (automated) |
| ICLOUD-10 | scenePhase .active triggers reload | `AccountStoreTests.testReloadPopulatesAccountsFromKeychain` (baseline reload path); scenePhase wiring on `App/KeyAuthApp.swift` is covered indirectly via build success + `SettingsViewTests.testSettingsViewInstantiationDoesNotCrash`. End-to-end cross-device active-phase reload is covered by manual QA `2-DEV-06`. | Complete (unit baseline) / Manual QA pending 2-DEV-06 |
| ICLOUD-11 | KVS observer + 300ms coalesce + counter bump | `AccountStoreTests.testCoalescedReloadDebounces300ms`, `.testBumpCounterSkippedWhenSyncDisabled`, `.testBumpCounterIncrementsWhenSyncEnabled`, `.testAddPassesSyncPreferenceIsEnabled`, `.testAddPassesSyncPreferenceFalseWhenDisabled` | Complete (automated) |
| ICLOUD-12 | SharedDefaults propagation for keyboard | `KeyboardPropagationTests.testReloadWritesAccountsToSharedDefaults`, `.testAddPropagatesToSharedDefaults`, `.testDeletePropagatesToSharedDefaults`, `.testReloadAfterDedupWritesDedupedList`, `.testReloadPreservesSortOrderInSharedDefaults`; `AccountStoreTests.testReloadWritesToSharedDefaults` | Complete (automated) |
| ICLOUD-13 | PairingStore + CryptoBox do NOT sync | `SyncScopeIsolationTests.testPairingStoreSourceContainsNoSynchronizableTrue`, `.testPairingStoreRuntimeSavePreservesNonSync`, `.testCryptoBoxManagerHasNoKeychainCalls`, `.testPairingServiceNameDoesNotOverlapWithAccountsService` | Complete (automated) |
| ICLOUD-14 | iCloud-off deep-link + D-11 copy | `SettingsViewTests.testD11CopyAndDeepLink` | Complete (automated) |
| ICLOUD-15 | Identity change flips toggle OFF + D-12 copy | `ICloudStateObserverTests.testSignOutSimulationFlipsSyncPreferenceOff`, `.testInitialStateIsBooleanValid`; `SettingsViewTests.testD12CopyWithEmDash` | Complete (automated) |
| ICLOUD-16 | Restoring state + 30s timeout | `RestoringStateTests.testProductionConstantIs30Seconds`, `.testTimeoutTransition` (50ms injected timeout deterministically verifies `.restoring → .timedOut`), `.testRestoredTransitionOnAccountsArrive`, `.testEvaluatorIdempotentWhenSyncOff`. Cross-device fresh-install real-iCloud propagation end-to-end is covered by manual QA `2-DEV-05`. | Complete (unit: RestoringStateTests.testTimeoutTransition) / Manual QA pending 2-DEV-05 |

## Manual QA Coverage (06-QA-CHECKLIST.md)

| Test | Covers (ICLOUD-NN) | Covers (SC) |
|------|--------------------|-------------|
| 2-DEV-01 Basic propagation | 01, 02, 10, 11 | SC-1, SC-5 (keyboard step) |
| 2-DEV-02 Migration + dedup | 07, 08 | SC-3 |
| 2-DEV-03 Stop syncing (D-06) | 06 | SC-4, SC-6 (side-observe pairings do NOT propagate) |
| 2-DEV-04 Destructive remove (D-05) | 09 | SC-4 |
| 2-DEV-05 Fresh-install restore | 16 | SC-1 |
| 2-DEV-06 Mid-session external change | 10, 11 | SC-1 |
| 2-DEV-07 iCloud Keychain OFF (D-11) | 14 | SC-2 |
| 2-DEV-08 Mid-session sign-out (D-12) | 15 | SC-4 |

**Keyboard extension manual verification (SC-5):** `2-DEV-01` step 5 ("Switch to the KeyAuth keyboard in any text field → observe test-alpha TOTP code appears") validates SC-5 end-to-end. Cross-process keyboard activation cannot be unit-tested; the unit-side propagation chain is covered by `KeyboardPropagationTests`.

**Device-bound isolation (SC-6):** Validated end-to-end by observing that pairings on Device A do NOT appear on Device B after sync; covered by 2-DEV-03 side-observation. Unit-side covered by `SyncScopeIsolationTests` (4 tests asserting `PairingStore` / `CryptoBoxManager` do NOT set `kSecAttrSynchronizable=true`).

## Orphan Check

Every `ICLOUD-NN` (01 through 16) appears at least once in either the Automated Coverage or Manual QA Coverage table above.

**No orphans detected.** 14 of 16 requirements have pure automated coverage; 2 of 16 (ICLOUD-10, ICLOUD-16) have a named unit baseline PLUS a named manual-QA case for end-to-end closure (hybrid).

Every Phase 6 Success Criterion (SC-1 through SC-6 from ROADMAP.md) maps to at least one automated test or manual QA test:

- **SC-1** (cross-device propagation): ICLOUD-01, 02, 10, 11, 16 → 2-DEV-01, 2-DEV-05, 2-DEV-06 + `KeychainManagerSyncTests`, `AccountStoreTests`, `RestoringStateTests`
- **SC-2** (honest disclosure of iCloud state): ICLOUD-04, 05, 14 → 2-DEV-07 + `SettingsViewTests`
- **SC-3** (migration without duplicates): ICLOUD-07, 08 → 2-DEV-02 + `MigrationTests`, `DedupTests`
- **SC-4** (clear stop-syncing choice): ICLOUD-06, 09, 15 → 2-DEV-03, 2-DEV-04, 2-DEV-08 + `SettingsViewTests`, `ICloudStateObserverTests`
- **SC-5** (keyboard sees synced accounts): ICLOUD-12 → `KeyboardPropagationTests` + 2-DEV-01 step 5
- **SC-6** (device-bound data does NOT sync): ICLOUD-13 → `SyncScopeIsolationTests` + 2-DEV-03 side observation

## Known Gaps & Follow-ups (documented, not fabricated)

| Gap | Requirement affected | Remediation |
|-----|----------------------|-------------|
| `TransientToastOverlay` component exists in `App/Views/TransientToastOverlay.swift` (Plan 06-04) but is NOT currently mounted in the ContentView / SettingsView hierarchy. The "Merged N duplicate accounts" toast referenced in ICLOUD-08 / 2-DEV-02 will not visually appear until the overlay is placed. | ICLOUD-08 (toast affordance), 2-DEV-02 (visual verification step) | Out of scope for 06-06. Flagged for a polish follow-up plan. Core dedup behavior (`AccountStore.lastDedupCount`) IS tested and correct; only the visual toast presentation is deferred. Manual QA testers should accept `lastDedupCount == N` as the behavior contract during 2-DEV-02 pending toast wiring. |
| `MigrationTests.testStopSyncingFunctionDoesNotCallDeleteAllSynced` uses `#filePath` to read `Shared/MigrationCoordinator.swift` source; this fails on simulator sandbox and is XCTSkipped per Plan 05 summary. | ICLOUD-07 (D-06 safety contract — secondary assertion) | Runtime behavior is still enforced by `MigrationTests.testStopSyncingPreservesLocalAndDoesNotDeleteSynced` (runtime assertion on mock state); if anyone adds `deleteAllSynced` to `stopSyncingThisDevice`, that runtime test fails. Acceptable. |

These are not coverage orphans — they are known, documented conditions that do not prevent phase shipment.

## Risks Flagged (from RESEARCH.md Open Questions)

| Risk | Owner Decision Required |
|------|-------------------------|
| Default-ON for new users vs App Store review 5.1.1 | Accept per CONTEXT D-01; fallback plan ready (switch to default-OFF + opt-in card, zero code impact — `SyncPreference.bootstrap` branch is the single switch) |
| 30-second Restoring timeout may be too short in bad-network conditions | 2-DEV-05 captures "Observed restore time" — if > 30s consistently, bump `RestoringFromCloudView.restoringTimeoutSeconds` to 60s (single-line change, pinned by `testProductionConstantIs30Seconds`) |
| iCloud Keychain state undetectable at runtime (Apple platform limit) | Accept; deep-link to iOS Settings is the industry-standard fallback — documented in RESEARCH.md § D-11 |
| RESEARCH.md line 459 "Open question for the planner" (dedup + D-06 safety) | **RESOLVED** — Plan 06-05 deviation-1 (commit `028f091`) implemented the two-phase `AccountStore.dedupInMemory` pipeline. Phase 1 collapses same-id variants in-memory only (no Keychain delete); Phase 2 runs the plan-specified cross-id DedupKey dedup. Covered by `MigrationTests.testStopSyncingPreservesLocalAndDoesNotDeleteSynced` + full `DedupTests` suite. |

## Sign-off

- [x] All ICLOUD-NN requirements map to at least one test (automated or manual) — no orphans
- [x] Every "Complete (unit)" claim names a specific test method (truth-in-claims gate)
- [x] All SC-1..SC-6 success criteria map to at least one test
- [ ] Automated suite exits 0 (`xcodebuild test -only-testing:KeyAuthTests`) — verified in Plan 06-06 Task 5
- [ ] Manual QA checklist (`06-QA-CHECKLIST.md`) completed and all 8 tests PASS (blocks phase complete) — tester sign-off required

*Traceability audit date: 2026-04-18*
*Phase: 06-icloud-keychain-sync*
*Total automated test methods across suites: 62 (61 running + 1 XCTSkip documented)*
*Total manual QA cases: 8 two-device tests (2-DEV-01..08)*
