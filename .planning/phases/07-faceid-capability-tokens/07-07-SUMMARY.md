---
phase: 07-faceid-capability-tokens
plan: 07
subsystem: ios-ui
tags: [settings, overlay, toast, trust-window, faceid, copy-regression]
requirements:
  completed:
    - FIDO-11
    - FIDO-12
    - FIDO-15
    - FIDO-18
dependency_graph:
  requires:
    - 07-02 (TrustWindowPreference.isEnabled/setEnabled API)
    - 07-03 (TrustWindowManager.pendingToast @Published)
    - 07-05 (TransientToastOverlay `duration` parameter)
  provides:
    - "Phase 7 'Security' section in SettingsView with 2-minute trust window toggle"
    - "Top-overlay mount of TransientToastOverlay driven by TrustWindowManager.pendingToast"
    - "3 new grep-based copy-regression tests (FIDO-15)"
  affects:
    - App/Views/SettingsView.swift
    - App/Views/ContentView.swift
    - KeyAuthTests/SettingsViewTests.swift
tech-stack:
  added: []
  patterns:
    - "Section { Toggle } header { } footer { } — clone of Phase 6 syncSection shape"
    - ".overlay(alignment: .top) { if let … } driven by an optional @Published ToastMessage"
    - ".animation(.easeInOut(duration: 0.2), value: pendingToast) — latest-wins crossfade"
    - "loadBundledSource(named:) grep-regression test pattern (Phase 6 precedent)"
key-files:
  created: []
  modified:
    - App/Views/SettingsView.swift
    - App/Views/ContentView.swift
    - KeyAuthTests/SettingsViewTests.swift
decisions:
  - "Used plan-specified `isPresented: .constant(true)` to keep overlay visibility driven by `if let toast = …` rather than a parallel @State Bool; TransientToastOverlay's internal asyncAfter is harmless-redundant because TrustWindowManager owns its own 2s dismiss timer and both deadlines target the same 2.0s moment"
  - "Used `Text(\"Security\")` section header per UI-SPEC Open Question 1 recommendation — creates a reusable 'Security' group for future biometric preferences without later rename cost"
  - "Inserted trustWindowSection between syncSection and migrationProgressSection per UI-SPEC Open Question 2 recommendation — keeps syncSection first and securedSection last; conditional sections (migration-progress, iCloud-off) stay below the two primary preferences"
metrics:
  duration: 7min
  completed: 2026-04-19
  tasks: 3
  files: 3
---

# Phase 7 Plan 07: SettingsView Security Toggle + ContentView Overlay Mount Summary

**One-liner:** Mount the two Phase 7 user-visible surfaces — SettingsView `Security` section with 2-min trust window Toggle (FIDO-15) and ContentView top-overlay driven by `TrustWindowManager.pendingToast` (FIDO-12, FIDO-18) — plus 3 verbatim-copy grep regression tests.

## What Was Built

### 1. SettingsView.swift — `Security` section with trust-window toggle (FIDO-15)

Added a fourth `Section` to the existing Phase 6 `Form`, visually identical to `syncSection` but bound to `TrustWindowPreference` instead of `SyncPreference`. No `.disabled` modifier (unlike syncSection — the trust-window feature has no external dependencies); no confirmation dialog (UI-SPEC explicitly rules this out because toggling OFF is reversible and non-destructive); no toast on flip.

```diff
diff --git a/App/Views/SettingsView.swift b/App/Views/SettingsView.swift
--- a/App/Views/SettingsView.swift
+++ b/App/Views/SettingsView.swift
@@ -17,6 +17,7 @@ struct SettingsView: View {
     @EnvironmentObject var icloud: ICloudStateObserver
     @EnvironmentObject var migration: MigrationCoordinator
     @State private var syncEnabled: Bool = SyncPreference.isEnabled
+    @State private var trustWindowEnabled: Bool = TrustWindowPreference.isEnabled
     @State private var showingDisableDialog = false
 
@@ -35,6 +36,7 @@ struct SettingsView: View {
     var body: some View {
         Form {
             syncSection
+            trustWindowSection
 
             if migration.isRunning && migration.progress.total > 10 {
                 migrationProgressSection
@@ -102,6 +104,25 @@ struct SettingsView: View {
         }
     }
 
+    /// Phase 7 FIDO-15: 2-minute trust window after FaceID toggle.
+    /// Copy strings below are VERBATIM from UI-SPEC Copywriting Contract (lines 144-156).
+    /// Changes to these literals MUST update the UI-SPEC in the same commit —
+    /// SettingsViewTests.swift grep-asserts each string.
+    private var trustWindowSection: some View {
+        Section {
+            Toggle("Allow 2-minute trust window after FaceID", isOn: $trustWindowEnabled)
+                .onChange(of: trustWindowEnabled) { newValue in
+                    TrustWindowPreference.setEnabled(newValue)
+                }
+        } header: {
+            Text("Security")
+        } footer: {
+            Text("Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background.")
+                .font(.footnote)
+                .foregroundStyle(.secondary)
+        }
+    }
+
     /// Rendered in `body` when `migration.isRunning && migration.progress.total > 10`.
```

### 2. ContentView.swift — top-overlay mount (FIDO-12, FIDO-18 plumbing)

Added `@EnvironmentObject var trustWindow: TrustWindowManager` and a `.overlay(alignment: .top)` modifier as a sibling to the existing `.sheet(item: $relayClient.pendingCodeRequest)` modifier. Overlay body renders `TransientToastOverlay` with the Phase-7 `duration: 2.0`, `paperplane.fill` icon (UI-SPEC §Iconography), and `.secondary` iconColor (keeps the informational toast visually quiet). `.animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)` drives a crossfade when a new ToastMessage replaces an in-flight one (RESEARCH Pitfall 4 — latest-wins).

```diff
diff --git a/App/Views/ContentView.swift b/App/Views/ContentView.swift
--- a/App/Views/ContentView.swift
+++ b/App/Views/ContentView.swift
@@ -7,6 +7,7 @@ enum SyncState { case idle, restoring, restored, timedOut }
 
 struct ContentView: View {
     @EnvironmentObject var store: AccountStore
+    @EnvironmentObject var trustWindow: TrustWindowManager
     @ObservedObject private var relayClient = RelayClient.shared
     @State private var showingScanner = false
     @State private var showingManualEntry = false
@@ -128,6 +129,19 @@ struct ContentView: View {
                 }
                 .environmentObject(store)
             }
+            .overlay(alignment: .top) {
+                if let toast = trustWindow.pendingToast {
+                    TransientToastOverlay(
+                        message: toast.text,
+                        icon: "paperplane.fill",
+                        iconColor: .secondary,
+                        duration: 2.0,
+                        isPresented: .constant(true)
+                    )
+                    .padding(.top, 8)
+                }
+            }
+            .animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)
             .onAppear {
                 evaluateRestoringState()
             }
```

**`isPresented: .constant(true)` rationale:** Visibility is driven by `if let toast = trustWindow.pendingToast`; the overlay's internal `asyncAfter` is redundant-but-harmless because `TrustWindowManager.showToast(for:)` schedules its own 2.0s `Timer` that sets `pendingToast = nil` at the same deadline. Both timers target the same moment; whichever fires first, the result is identical. No semantic conflict.

### 3. SettingsViewTests.swift — 3 new FIDO-15 copy-regression grep tests

Appended three tests inside the existing `SettingsViewTests` class, mirroring the Phase 6 `testToggleLabelMatchesUISpec` shape. Uses the existing `loadBundledSource(named:)` helper — `SettingsView.swift` is already copied into the test bundle by Phase 6's "Copy Shared Sources For Isolation Tests" Run-Script, so no xcodeproj edit was needed.

```swift
// MARK: - FIDO-15: Phase 7 trust-window toggle verbatim copy

func testTrustWindowToggleLabelMatchesUISpec() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Toggle(\"Allow 2-minute trust window after FaceID\""),
        "FIDO-15: Toggle label must be 'Allow 2-minute trust window after FaceID' (UI-SPEC line 148)")
}

func testTrustWindowFooterHelperTextVerbatim() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background."),
        "FIDO-15: Footer helper text must be UI-SPEC Copywriting Contract verbatim (line 150)")
}

func testTrustWindowSectionHeaderIsSecurity() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Text(\"Security\")"),
        "FIDO-15: trustWindowSection header must be 'Security' (UI-SPEC Open Question 1 recommendation)")
}
```

## Test Results

**SettingsViewTests** — 12 Phase 6 tests + 3 new Phase 7 tests = 15 total, all passing.

Observed per-case output:
```
Test Case '-[KeyAuthTests.SettingsViewTests testTrustWindowFooterHelperTextVerbatim]' passed (0.001 seconds).
Test Case '-[KeyAuthTests.SettingsViewTests testTrustWindowSectionHeaderIsSecurity]' passed (0.001 seconds).
Test Case '-[KeyAuthTests.SettingsViewTests testTrustWindowToggleLabelMatchesUISpec]' passed (0.001 seconds).
Test Suite 'SettingsViewTests' passed at 2026-04-19 11:30:52.518.
```

Count before: 12. Count after: 15. The 12 Phase 6 tests are untouched (same bodies, same source-file line numbers for each assertion; the new tests appended inside a new `// MARK:` section between `testD12CopyWithEmDash` and `testSettingsViewInstantiationDoesNotCrash`).

**Build verification:**
- `xcodebuild -scheme KeyAuth build` (iPhone 17 simulator, iOS 26.4.1) → `** BUILD SUCCEEDED **` after Task 1 (SettingsView) edit.
- `xcodebuild -scheme KeyAuth build` → `** BUILD SUCCEEDED **` after Task 2 (ContentView) edit.
- `xcodebuild test -only-testing:KeyAuthTests/SettingsViewTests` → all 15 tests pass.

**Harness note:** xcodebuild reported `** TEST FAILED **` at the outermost line on one run due to a simulator bootstrap hiccup (`Early unexpected exit, operation never finished bootstrapping`) — this is an outer-harness artifact. The test suite itself reports `Test Suite 'SettingsViewTests' passed` for every invocation observed in this plan's verification. A rerun produced a clean grep-match on `Test Suite 'SettingsViewTests' passed`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add Phase 7 trustWindowSection to SettingsView.swift | 9ccf211 | App/Views/SettingsView.swift |
| 2 | Mount TransientToastOverlay on ContentView driven by TrustWindowManager.pendingToast | 16a1d04 | App/Views/ContentView.swift |
| 3 | Extend SettingsViewTests.swift with 3 Phase 7 copy-regression grep tests | d24da0a | KeyAuthTests/SettingsViewTests.swift |

## Success Criteria Met

- [x] SettingsView.swift has a "Security" section with a Toggle bound to `TrustWindowPreference.isEnabled` / `setEnabled`
- [x] ContentView.swift has `.overlay(alignment: .top) { TransientToastOverlay(...) }` driven by `TrustWindowManager.pendingToast` (read via `@EnvironmentObject`)
- [x] SettingsViewTests has 3 new FIDO-15 tests under a dedicated `// MARK:` section
- [x] `xcodebuild -scheme KeyAuth build` succeeds (iPhone 17 simulator)
- [x] `xcodebuild test -only-testing:KeyAuthTests/SettingsViewTests` passes all 15 tests (12 Phase 6 + 3 Phase 7)
- [x] No modifications to files outside scope (only the 3 target files touched)
- [x] No files in the parallel plan's scope (`App/KeyAuthApp.swift`) touched
- [x] UI-SPEC Copywriting Contract enforcement now has automated CI coverage

## Deviations from Plan

None — plan executed exactly as written. UI-SPEC Open Question 1 and 2 resolutions (Security header, insertion order between syncSection and migrationProgressSection) were both already pre-resolved in the plan's `<action>` blocks, so no planner-discretion calls were needed during execution.

## Threat Model Compliance

| Threat ID | Mitigation delivered |
|-----------|----------------------|
| T-7-05 (toggle OFF does not revoke in-flight) | Honored — Toggle OFF only calls `TrustWindowPreference.setEnabled(false)`; no force-revoke. Aligns with UI-SPEC §Interaction Patterns "the toggle does NOT force-revoke in-flight windows." Any active window continues to expire via its scheduled Timer or the next background/iCloud revocation trigger. |
| T-7-08 (toast vs sheet coverage) | Benign — toast never fires during mint-flow sheet presentation (the sheet dismisses before the window is open enough for a silent-send to arrive). FIDO-18 manual QA verifies the "subsequent request after sheet dismiss" case on a physical device. |
| T-7-CR1 (copy drift) | Mitigated — three grep tests enforce UI-SPEC verbatim strings at CI time. Any refactor that touches the three literals now requires updating the UI-SPEC in the same commit. |

## Known Stubs

None. Both Phase 7 user-visible surfaces are fully wired:
- SettingsView Toggle is a real two-way binding to `TrustWindowPreference` (writes on flip; reads on view init).
- ContentView overlay reads the real `@Published var pendingToast: ToastMessage?` from `TrustWindowManager` injected by Plan 07-06 (wiring happens in `KeyAuthApp.swift`).

The `@EnvironmentObject var trustWindow: TrustWindowManager` resolution at runtime depends on Plan 07-06's `.environmentObject(trustWindow)` wiring in KeyAuthApp. A missing wiring would produce a hard SwiftUI crash rather than a silent stub, which is the intended fail-fast behavior per plan guidance.

## Self-Check: PASSED

- FOUND: App/Views/SettingsView.swift — trustWindowSection present (grep-verified all 6 literals)
- FOUND: App/Views/ContentView.swift — overlay + EnvironmentObject present (grep-verified all 7 literals)
- FOUND: KeyAuthTests/SettingsViewTests.swift — 3 new test methods + FIDO-15 MARK present
- FOUND: commit 9ccf211 (Task 1)
- FOUND: commit 16a1d04 (Task 2)
- FOUND: commit d24da0a (Task 3)
- Out-of-scope files: none touched (`git log base..HEAD --name-only` returned only the 3 in-scope files)
