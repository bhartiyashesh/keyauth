---
phase: 07-faceid-capability-tokens
plan: 06
subsystem: iOS app lifecycle wiring
tags: [lifecycle, trustwindow, environmentobject, resolver]
wave: 5
completed_date: 2026-04-19
duration_minutes: 6
task_count: 1
file_count: 1
requirements_touched: [FIDO-01, FIDO-03, FIDO-06, FIDO-07, FIDO-09, FIDO-10, FIDO-14, FIDO-16]

dependency_graph:
  requires:
    - TrustWindowManager.shared (Plan 07-03 — provides bootstrap() / mint() / revoke() / pendingToast)
    - TrustWindowPreference.bootstrap() (Plan 07-02 — default-ON preference)
    - RelayClient.shared.accountResolver (Plan 07-04 — silent-send resolver slot)
    - AccountStore.resolve(for:) (Plan 07-04 — resolver implementation)
    - ICloudStateObserver.shared.$didAccountChange (Plan 06 — revocation signal; subscribed inside TrustWindowManager.bootstrap)
  provides:
    - Live TrustWindowManager lifecycle — bootstrap fires once at app startup, revocations fire on background / iCloud-account-change / Timer expiry (observers owned by manager)
    - @EnvironmentObject TrustWindowManager visible to ContentView tree — Plan 07-07's toast overlay can now bind to `trustWindow.pendingToast`
    - Wired RelayClient.shared.accountResolver — Plan 07-04's silent-send branch can now resolve CodeRequest → Account end-to-end
  affects:
    - App startup path (.onAppear) — adds exactly one call after bootstrapSyncPreferenceOnce()
    - Background notification handler — UNCHANGED (manager owns its own revoke subscription; no duplicate call added)

tech_stack:
  patterns:
    - "@StateObject-of-shared-singleton (existing KeyAuthApp idiom: store, pairingStore, icloudState)"
    - "bootstrap-once guarded by @State didBootstrap… flag (Phase 6 precedent: bootstrapSyncPreferenceOnce)"
    - "EnvironmentObject injection on ContentView (Phase 6 precedent: store / pairingStore / icloudState / migration)"
    - "Weak-captured class closure ([weak store] request in store?.resolve(for: request))"

key_files:
  modified:
    - path: App/KeyAuthApp.swift
      description: TrustWindowManager lifecycle wiring — @StateObject + @State guard + .environmentObject + bootstrapTrustWindowPreferenceOnce() + accountResolver closure
      lines_added: 17
      lines_removed: 0
  created: []

decisions:
  - "Did NOT add a duplicate trustWindow.revoke() call in the existing didEnterBackgroundNotification .onReceive closure — TrustWindowManager.bootstrap() subscribes to the same notification via its own Combine sink (Plan 07-03). Single ownership inside the manager is the RESEARCH-endorsed pattern (anti-pattern: app-level closures owning manager state). D-05 rationale."
  - "Placed bootstrapTrustWindowPreferenceOnce() IMMEDIATELY after bootstrapSyncPreferenceOnce() (before setupAppDelegate) so the manager's NotificationCenter / iCloud-account-change observers are live before any other app wiring runs — avoids a TOCTOU where an early notification races past the subscription."
  - "Used iPhone 17 simulator (OS=latest, UDID 3CF555B3-FB62-4BAA-92B7-7599451E33E2) as the test destination — iPhone 16 not installed on this host. Precedent set by Plan 07-01 / 07-05 SUMMARY.md. Plan permits any iOS 16+ simulator."

commits:
  - hash: d2fa576
    message: "feat(07-06): wire TrustWindowManager lifecycle into KeyAuthApp"
    task: 1

metrics:
  duration_minutes: 6
  tasks_completed: 1
  files_modified: 1
  tests_passed: "83/83 (1 skipped)"
  build_status: "BUILD SUCCEEDED"
---

# Phase 7 Plan 6: KeyAuthApp Lifecycle Wiring Summary

**One-liner:** Wires TrustWindowManager (bootstrap observers, EnvironmentObject plumbing, silent-send account resolver) into `App/KeyAuthApp.swift` via four coordinated edits so Phase 7's silent-send + toast overlay become end-to-end functional.

## Objective (restated)

Without this plan, Plan 07-04's silent-send branch always falls through (resolver is `nil`) and Plan 07-07's toast overlay has no `EnvironmentObject` to read from — nothing user-visible works. This is the wave-5 glue that closes the loop.

## Changes Made (Task 1)

### Unified diff of `App/KeyAuthApp.swift`

```diff
diff --git a/App/KeyAuthApp.swift b/App/KeyAuthApp.swift
index 86bd126..af18a95 100644
--- a/App/KeyAuthApp.swift
+++ b/App/KeyAuthApp.swift
@@ -7,10 +7,12 @@ struct KeyAuthApp: App {
     @StateObject private var store = AccountStore()
     @StateObject private var pairingStore = PairingStore.shared
     @StateObject private var icloudState = ICloudStateObserver.shared
+    @StateObject private var trustWindow = TrustWindowManager.shared
     @Environment(\.scenePhase) private var scenePhase
     @State private var isUnlocked = false
     @State private var deviceToken: String?
     @State private var didBootstrapSyncPreference = false
+    @State private var didBootstrapTrustWindowPreference = false
     // MigrationCoordinator is constructed lazily in `.onAppear` because its init requires
     // AccountStore; @StateObject init cannot reference other @StateObjects (SwiftUI prohibits
     // that access during View init). Once created, we inject it via .environmentObject so
@@ -27,6 +29,7 @@ struct KeyAuthApp: App {
                             .environmentObject(pairingStore)
                             .environmentObject(icloudState)
                             .environmentObject(migration)
+                            .environmentObject(trustWindow)
                     } else {
                         LockScreenView {
                             isUnlocked = true
@@ -42,6 +45,7 @@ struct KeyAuthApp: App {
                     migration = MigrationCoordinator(store: store)
                 }
                 bootstrapSyncPreferenceOnce()
+                bootstrapTrustWindowPreferenceOnce()
                 setupAppDelegate()
                 requestPushPermissionAndRegister()
                 // Ensure KVS has latest state cached locally.
@@ -82,6 +86,19 @@ struct KeyAuthApp: App {
         SyncPreference.bootstrap(existingAccountCount: existingCount)
     }

+    private func bootstrapTrustWindowPreferenceOnce() {
+        guard !didBootstrapTrustWindowPreference else { return }
+        didBootstrapTrustWindowPreference = true
+        TrustWindowPreference.bootstrap()
+        trustWindow.bootstrap()
+        // Wire the silent-send account resolver (Plan 07-04 introduced the property;
+        // this is the one place in the app it's assigned). Weak capture of `store` — it
+        // is a class, and we must not extend its lifetime beyond the KeyAuthApp scene.
+        RelayClient.shared.accountResolver = { [weak store] request in
+            return store?.resolve(for: request)
+        }
+    }
+
     private func setupAppDelegate() {
         appDelegate.onDeviceToken = { token in
             self.deviceToken = token
```

17 lines added, 0 lines removed. All four planned edits applied; zero scope drift.

## Verification

### Grep of all 8 verification strings

| # | Pattern | Count |
|---|---------|-------|
| 1 | `@StateObject private var trustWindow = TrustWindowManager.shared` | 1 |
| 2 | `didBootstrapTrustWindowPreference` | 3 (declaration + guard + assignment) |
| 3 | `.environmentObject(trustWindow)` | 1 |
| 4 | `bootstrapTrustWindowPreferenceOnce()` | 2 (call site + method decl) |
| 5 | `TrustWindowPreference.bootstrap()` | 1 |
| 6 | `trustWindow.bootstrap()` | 1 |
| 7 | `RelayClient.shared.accountResolver` | 1 |
| 8 | `store?.resolve(for: request)` | 1 |

All 8 patterns present. Counts exceed "once" where Swift identifier repetition is expected (guard flag appears 3×, helper name appears 2×) — this matches plan intent.

### Build

```
** BUILD SUCCEEDED **
```

Destination: `platform=iOS Simulator,name=iPhone 17,OS=latest` (iPhone 16 not installed on this host — precedent set by Plan 07-01 SUMMARY.md; any iOS 16+ simulator is permitted).

### Test Suite Tail (last 5 lines)

```
	/Users/yashesh/Library/Developer/Xcode/DerivedData/KeyAuth-fhucqntnxzjqurfwuqkohlxwdxio/Logs/Test/Test-KeyAuth-2026.04.19_11-32-09--0500.xcresult

** TEST SUCCEEDED **

Testing started
```

83 tests executed, 1 skipped, 0 failures — full KeyAuthTests suite green. All Phase 6 + Phase 7 Wave 0-3 tests continue to pass, confirming the wiring change is a pure addition with no behavioral regression.

## Single-Ownership Rationale (explicit)

**No duplicate revoke was added to the background-notification closure.**

The existing closure in `.onReceive(... didEnterBackgroundNotification ...)` at lines 69-76 of the post-edit file remains UNCHANGED:

```swift
.onReceive(
    NotificationCenter.default.publisher(
        for: UIApplication.didEnterBackgroundNotification
    )
) { _ in
    isUnlocked = false
    RelayClient.shared.disconnect()
}
```

`TrustWindowManager.bootstrap()` (Plan 07-03, lines 66-71 of `Shared/TrustWindowManager.swift`) subscribes to the SAME notification via its own Combine sink:

```swift
NotificationCenter.default
    .publisher(for: UIApplication.didEnterBackgroundNotification)
    .sink { [weak self] _ in
        Task { @MainActor in self?.revoke() }
    }
    .store(in: &cancellables)
```

Adding `trustWindow.revoke()` inside the KeyAuthApp closure would be idempotent and functionally harmless (revoke clears state cleanly on second call), but would SPLIT ownership of trust-window revocation across two files — making the manager's subscription optional and inviting future drift. Keeping the manager as the single revocation owner is the RESEARCH-endorsed pattern (see Phase 07 RESEARCH line 414 anti-pattern on View-level subscriptions owning Manager state; equivalent concern applies to app-level closures).

## Deviations from Plan

None — plan executed exactly as written.

The only environmental substitution was the simulator destination (iPhone 17 instead of iPhone 16, precedent set by Plans 07-01 / 07-05 on the same host). This is a host-specific availability note, not a behavioral deviation.

## Threat Model Compliance

| Threat | Status | Notes |
|--------|--------|-------|
| T-7-03 (TOCTOU / duplicate revoke on background) | mitigated | No duplicate path — manager owns its subscription; app-level closure untouched (see above) |
| T-7-12 (onAppear fires twice on some scenes / iOS versions) | mitigated | `didBootstrapTrustWindowPreference` guard + `TrustWindowManager.bootstrap()`'s internal `didBootstrap` guard → dual safety |
| T-7-15 (resolver closure leaks account data) | accepted (non-exploitable) | Closure is in-process only; resolves via the same path FaceID uses; no new disclosure surface |

## Requirements Touched

This plan advances the end-to-end realization of the following Phase 7 requirements (actual completion is claimed by the test-bearing plans; this plan is the glue that makes them exercise in the app):

- **FIDO-01** — TrustWindowManager is now a live `@StateObject` in the app
- **FIDO-03** — `TrustWindowPreference.bootstrap()` runs at startup
- **FIDO-06 / FIDO-07** — background-revocation + iCloud-account-change-revocation observers are installed at startup (via `trustWindow.bootstrap()`)
- **FIDO-09 / FIDO-10** — silent-send account resolver closure is installed, Plan 07-04's branch is now end-to-end functional
- **FIDO-14** — TrustWindowPreference default-ON bootstrap runs at first launch
- **FIDO-16** — app-launch bootstrap of the default-ON preference

## Known Stubs

None. This plan adds exactly the lifecycle wiring the downstream plans expect; no placeholder data flows anywhere.

## Threat Flags

No new security-relevant surface introduced. The only new inter-component link is the closure assigned to `RelayClient.shared.accountResolver`, which is in-process, delegates to existing `AccountStore.resolve(for:)`, and was already threat-modeled by Plan 07-04.

## Self-Check

- [x] `App/KeyAuthApp.swift` modified — FOUND (17-line addition, verified by `git diff --stat`)
- [x] Commit `d2fa576` exists in current branch — FOUND (`git log --oneline -3` shows it at HEAD after `b742dc5`)
- [x] All 8 grep patterns verified present
- [x] Build succeeded for iPhone 17 simulator (OS=latest)
- [x] Full KeyAuthTests suite green: 83 executed, 1 skipped, 0 failures
- [x] No duplicate revoke call added in background-notification closure (single-ownership preserved)
- [x] No files outside `App/KeyAuthApp.swift` modified (parallel agent scope respected: SettingsView, ContentView, SettingsViewTests untouched)

## Self-Check: PASSED
