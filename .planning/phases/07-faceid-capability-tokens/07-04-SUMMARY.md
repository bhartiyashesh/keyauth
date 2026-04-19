---
phase: 07-faceid-capability-tokens
plan: 04
subsystem: relay-silent-send
tags: [relay, silent-send, trust-window, account-resolution, faceid-gate, tests, fido-09, fido-10]
dependency_graph:
  requires:
    - "Shared/RelayClient.swift (base): handleMessage default branch + sendEncryptedCode"
    - "Shared/TrustWindowManager.swift (Plan 07-03): isInWindow + showToast(for:)"
    - "Shared/TrustWindowPreference.swift (Plan 07-02): D-17 redundant gate check"
    - "Shared/AccountStore.swift (Phase 6): accounts store — now extended with resolve(for:)"
    - "Shared/TOTPGenerator.swift: generate(for:) → String? used inside the silent branch"
    - "KeyAuthTests/Fixtures/CodeRequestFixtures.swift (Plan 07-01): make() + empty()"
    - "KeyAuthTests/Fixtures/AccountFixtures.swift (Phase 6): make()"
    - "KeyAuthTests/RelayClientSilentSendTests.swift scaffolds (Plan 07-01): 3 XCTSkip stubs to fill"
  provides:
    - "RelayClient.accountResolver ((CodeRequest) -> Account?)? — injectable seam wired by KeyAuthApp in Plan 07-06"
    - "RelayClient.handleDecodedRequest(_:) internal method — testable silent-send entrypoint"
    - "AccountStore.resolve(for:) Account? — shared account-matching helper (Pattern 2); Plan 07-05 adopts in CodeApprovalView.onAppear"
    - "3 passing unit tests (FIDO-09 happy path, FIDO-10 ambiguous, FIDO-09 out-of-window complement)"
  affects:
    - "Plan 07-05 (CodeApprovalView): may replace inline domain-match with AccountStore.resolve(for:)"
    - "Plan 07-06 (KeyAuthApp wiring): must set RelayClient.shared.accountResolver = { AccountStore.shared.resolve(for: $0) } in onAppear"
    - "Extension bundle (KeyAuthKeyboard): now links TrustWindowManager.swift (implicitly inherited silent-send capability if keyboard ever calls handleDecodedRequest)"
tech_stack:
  added: []
  patterns:
    - "Injectable closure seam for silent-send resolver (no AccountStore dependency in RelayClient — Research Note 1)"
    - "Internal method extraction for direct unit testability without WebSocket/PairingStore plumbing"
    - "Dual guard gate (D-17): TrustWindowManager.isInWindow AND TrustWindowPreference.isEnabled"
    - "Anti-drift account matching via shared extension method (Pattern 2)"
    - "tearDown clears RelayClient singleton state (accountResolver + pendingCodeRequest) to avoid cross-test leakage"
key_files:
  created: []
  modified:
    - "Shared/RelayClient.swift (+38, -1): accountResolver property + handleDecodedRequest extraction + silent branch"
    - "Shared/AccountStore.swift (+37): extension with resolve(for:) helper"
    - "KeyAuthTests/RelayClientSilentSendTests.swift (+67, -5): 3 XCTSkip stubs replaced with real assertions"
    - "KeyAuth.xcodeproj/project.pbxproj (+2): added TrustWindowManager.swift to KeyAuthKeyboard Sources build phase"
decisions:
  - "Injected resolver closure (var accountResolver: ((CodeRequest) -> Account?)?) instead of importing AccountStore.shared directly — keeps RelayClient free of a UI-store dependency (RESEARCH Note 1) and lets the 3 unit tests script return values without a Keychain-backed store."
  - "handleDecodedRequest extracted as internal (not private) so @testable import KeyAuth can call it; documented as the test entrypoint in its doc-comment."
  - "Single-line if-let ladder for the 5-way gate (isInWindow, preference, resolver, account, code) keeps the happy-path visually compact; the fall-through pendingCodeRequest = request remains a single plain assignment exactly like the pre-plan behavior."
  - "toast assertion uses exact string match 'Code sent for GitHub' — lets a future change to TrustWindowManager.showToast format fail loud rather than silent."
  - "Rule 3 deviation: added TrustWindowManager.swift to KeyAuthKeyboard Sources build phase. RelayClient.swift ships in BOTH the main app and the KeyAuthKeyboard extension target; the keyboard target did NOT have TrustWindowManager.swift, so compilation failed after the new reference landed. Fixed by adding one PBXBuildFile + one Sources-phase entry (see deviations)."
metrics:
  tasks_completed: 3
  tasks_total: 3
  duration_minutes: ~25
  completed_date: 2026-04-19
---

# Phase 7 Plan 04: RelayClient Silent-Send Branch + AccountStore.resolve Summary

Phase 7's user-visible payload — the silent-send branch inside `RelayClient.handleMessage` — is live and unit-tested, gated by both `TrustWindowManager.isInWindow` and `TrustWindowPreference.isEnabled` (dual D-17 guard). Account matching for the silent path is routed through an injectable `accountResolver` closure so tests never touch the WebSocket; the same semantics are captured in a new `AccountStore.resolve(for:)` helper so Plan 07-05 and 07-06 can consume them without drift.

## One-liner

Injects the FIDO-09 silent-send branch into RelayClient via an extracted, testable `handleDecodedRequest(_:)` gated by window + preference + injected resolver; ships `AccountStore.resolve(for:)` as the shared matching helper so the silent path and the FaceID path cannot drift apart (Pattern 2).

## What Changed

### Task 1 — `AccountStore.resolve(for:)` extension (commit 5d7b357)

Added a top-level extension on `AccountStore` (verbatim from plan interfaces, placed after the closing brace of `final class AccountStore`) implementing the four-step match hierarchy used by `CodeApprovalView.onAppear`:

1. Non-empty issuer OR label → exact `(issuer, label)` match only.
2. Both empty + non-empty domain → filter by case-insensitive `contains` in either direction after stripping `.com`; single match wins; multiple matches returns `nil` (AMBIGUOUS signal — silent path defers to FaceID).
3. Single-account fallback.
4. Otherwise `nil`.

Returning `nil` is the sanctioned "defer to FaceID" signal per CONTEXT §Claude's Discretion. No new types; no Keychain mutation.

### Task 2 — RelayClient silent-send branch (commit fcd9e65)

Three coordinated edits to `Shared/RelayClient.swift`:

**Edit 1** — added `accountResolver` property next to `onConnected`:

```swift
var accountResolver: ((CodeRequest) -> Account?)?
```

**Edit 2** — the existing `default:` branch now calls `handleDecodedRequest(request)` instead of setting `pendingCodeRequest` directly.

**Edit 3** — new `internal func handleDecodedRequest(_:)`:

```swift
internal func handleDecodedRequest(_ request: CodeRequest) {
    if TrustWindowManager.shared.isInWindow,
       TrustWindowPreference.isEnabled,
       let resolver = accountResolver,
       let account = resolver(request),
       let code = TOTPGenerator.generate(for: account) {
        sendEncryptedCode(code, requestId: request.id,
                          issuer: account.issuer, label: account.label)
        TrustWindowManager.shared.showToast(for: account.issuer)
        return
    }

    pendingCodeRequest = request
}
```

Behavior contract:
- FIDO-09 silent path: all five conditions hold → send code, fire toast, return. `pendingCodeRequest` stays `nil` (no FaceID sheet).
- FIDO-10 fall-through: any condition fails → `pendingCodeRequest = request` (existing CodeApprovalView sheet appears). Toast does not fire.

### Task 3 — RelayClientSilentSendTests (commit b60876c)

Replaced three `XCTSkip` scaffolds with real assertions. All use `CodeRequestFixtures` for input and script the resolver closure directly on the singleton:

- **`testSilentSendInWindow`** (FIDO-09): preference ON + `mint()` + resolver returns GitHub account + exact-match request → asserts `pendingCodeRequest == nil` AND `pendingToast.text == "Code sent for GitHub"`.
- **`testAmbiguousResolutionSetsPendingCodeRequest`** (FIDO-10): preference ON + `mint()` + resolver returns `nil` + empty-issuer/label request → asserts `pendingCodeRequest.id == request.id` AND `pendingToast == nil`.
- **`testOutOfWindowAlwaysSetsPendingCodeRequest`** (FIDO-09 complement): preference ON + NO `mint()` + resolver would succeed → asserts `pendingCodeRequest != nil` AND `pendingToast == nil`.

`tearDown` clears `RelayClient.shared.accountResolver`, `pendingCodeRequest`, and calls `TrustWindowManager.shared._resetForTests()` so no state leaks between cases.

## Unified Diff — Shared/RelayClient.swift

```diff
@@ -16,6 +16,12 @@ final class RelayClient: ObservableObject {
     /// Called once after WebSocket connection is established. Set by pairing flow to send ack.
     var onConnected: (() -> Void)?
 
+    /// Resolves a decoded `CodeRequest` to a concrete `Account`. Set ONCE by KeyAuthApp.onAppear.
+    /// Returns `nil` when the request is ambiguous — the silent-send branch falls through to FaceID.
+    /// Anti-drift with `CodeApprovalView.onAppear` is guaranteed by Plan 07-05 routing both
+    /// call sites through `AccountStore.resolve(for:)`.
+    var accountResolver: ((CodeRequest) -> Account?)?
+
     private var webSocketTask: URLSessionWebSocketTask?
@@ -161,7 +167,7 @@ final class RelayClient: ObservableObject {
                       let request = try? JSONDecoder().decode(CodeRequest.self, from: plaintext)
                 else { return }
 
-                pendingCodeRequest = request
+                handleDecodedRequest(request)
             }
 
         case .data:
@@ -172,6 +178,34 @@ final class RelayClient: ObservableObject {
         }
     }
 
+    /// Silent-send gate (Phase 7 FIDO-09 / FIDO-10). Extracted from the `default:` clause so
+    /// unit tests can call it directly with a CodeRequestFixtures-built `CodeRequest` without
+    /// needing a live WebSocket or PairingStore.
+    ...
+    internal func handleDecodedRequest(_ request: CodeRequest) {
+        if TrustWindowManager.shared.isInWindow,
+           TrustWindowPreference.isEnabled,
+           let resolver = accountResolver,
+           let account = resolver(request),
+           let code = TOTPGenerator.generate(for: account) {
+            sendEncryptedCode(code, requestId: request.id,
+                              issuer: account.issuer, label: account.label)
+            TrustWindowManager.shared.showToast(for: account.issuer)
+            return
+        }
+
+        pendingCodeRequest = request
+    }
+
     // MARK: - Reconnection
```

## Full Extension Block — Shared/AccountStore.swift

```swift
extension AccountStore {
    /// Deterministic account resolution for a decoded `CodeRequest`. Mirrors
    /// `CodeApprovalView.onAppear` semantics so FaceID and silent-send paths agree on
    /// which account a request refers to (Phase 7 RESEARCH Pattern 2 — anti-drift).
    ///
    /// Semantics (first match wins):
    ///   1. Exact issuer+label match (when either field is non-empty on the request).
    ///   2. Domain-based matching (only when both issuer AND label are empty):
    ///      a. Single domain match → return it.
    ///      b. Multiple domain matches → return nil (AMBIGUOUS — silent path defers to FaceID).
    ///   3. Single-account fallback (user only has one account configured).
    ///   4. Otherwise → nil (AMBIGUOUS or empty store).
    ///
    /// Returning `nil` is the sanctioned "defer to FaceID" signal — it is NOT an error.
    func resolve(for request: CodeRequest) -> Account? {
        // 1. Exact issuer+label
        if !request.issuer.isEmpty || !request.label.isEmpty {
            return accounts.first { $0.issuer == request.issuer && $0.label == request.label }
        }
        // 2. Domain-based
        if let domain = request.domain, !domain.isEmpty {
            let domainLower = domain.lowercased()
            let matched = accounts.filter { account in
                let issuerLower = account.issuer.lowercased()
                return domainLower.contains(issuerLower)
                    || issuerLower.contains(domainLower.replacingOccurrences(of: ".com", with: ""))
            }
            if matched.count == 1 { return matched[0] }
            if matched.count > 1 { return nil } // AMBIGUOUS — silent path defers
        }
        // 3. Single-account fallback
        if accounts.count == 1 { return accounts[0] }
        // 4. Ambiguous or empty
        return nil
    }
}
```

## Test Pass Log

`xcodebuild test -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeyAuthTests/RelayClientSilentSendTests`

```
Test Case '-[KeyAuthTests.RelayClientSilentSendTests testAmbiguousResolutionSetsPendingCodeRequest]' passed (0.016 seconds).
Test Case '-[KeyAuthTests.RelayClientSilentSendTests testOutOfWindowAlwaysSetsPendingCodeRequest]' passed (0.003 seconds).
Test Case '-[KeyAuthTests.RelayClientSilentSendTests testSilentSendInWindow]' passed (0.005 seconds).
Test Suite 'RelayClientSilentSendTests' passed at 2026-04-19 11:15:52.954.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.024 (0.025) seconds
** TEST SUCCEEDED **
```

Spot-check on adjacent TrustWindow suites (to verify the keyboard-target pbxproj change didn't regress): `xcodebuild test … -only-testing:KeyAuthTests/TrustWindowManagerTests -only-testing:KeyAuthTests/TrustWindowPreferenceTests` → `Executed 14 tests, with 0 failures … ** TEST SUCCEEDED **`.

## Why `sendEncryptedCode` Assertion Is Out of Scope for Unit Tests

The silent-send branch calls `RelayClient.sendEncryptedCode(_:requestId:issuer:label:)` as its side-effect-producing step. That method opens with:

```swift
guard let sharedKey = PairingStore.shared.sharedKey else { return }
```

In the unit-test environment no pairing has happened, so `PairingStore.shared.sharedKey` is `nil` and the method immediately returns without touching the WebSocket. Asserting that bytes reached the wire would therefore require either (a) standing up a real Curve25519 pairing inside the test (substantial scaffolding + crypto dependencies) or (b) introducing a mock `PairingStore` seam that the plan deliberately avoids (RESEARCH Pitfall 5 — "no scope creep in RelayClient's method signatures"). Instead, the unit contract is the *decision* the silent branch makes: "did we take the silent path (no FaceID sheet would appear) AND did we publish a toast?" Both are directly observable through `pendingCodeRequest` (must stay `nil`) and `TrustWindowManager.shared.pendingToast` (must contain the issuer text). The full end-to-end wire integration is covered by the FIDO-18 manual QA flow in `07-VALIDATION.md`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] `TrustWindowManager` not available in KeyAuthKeyboard target**

- **Found during:** Task 2 build
- **Issue:** `Shared/RelayClient.swift` is a member of BOTH the `KeyAuth` app target AND the `KeyAuthKeyboard` extension target. The new `handleDecodedRequest` method references `TrustWindowManager.shared` — but `TrustWindowManager.swift` (added in Plan 07-03) was wired only into the app target. Compilation failed with `cannot find 'TrustWindowManager' in scope` at two call sites inside RelayClient when building the keyboard target.
- **Fix:** Added `TrustWindowManager.swift` to `KeyAuthKeyboard`'s Sources build phase in `KeyAuth.xcodeproj/project.pbxproj`. Concretely: one new `PBXBuildFile` row (`70A1D62A984AB106092D2C9C`) pointing at the existing `TrustWindowManager.swift` fileRef, and one line added to the `8EAEA92F87BDAB2F34B0312E /* Sources */` files-array for the keyboard target. `TrustWindowPreference.swift` was already wired into both targets, so only TrustWindowManager needed the fix.
- **Files modified:** `KeyAuth.xcodeproj/project.pbxproj`
- **Commit:** `fcd9e65` (folded into the RelayClient task commit because the build cannot succeed without both edits)
- **Why Rule 3, not Rule 4:** The fix is additive — one file added to one extra build phase with a deterministic, reversible pbxproj patch. No architectural change (the keyboard still does not *call* silent-send today; it merely *compiles* the code path that references the type). The alternative (making `RelayClient.swift` member-of-app-target-only) would be architectural and is not appropriate without planner involvement.

No other deviations. Plan 07-04 Tasks 1 and 3 executed exactly as written.

### Authentication Gates

None.

## Threat Flags

None. The change is a pure refactor + feature gate; no new network surface, no new auth path, no new file access. The threat model in `07-04-PLAN.md` is exhaustive for this plan's scope and all mitigations are in place (dual-guard for T-7-05; MainActor serialization for T-7-03; `isInWindow` gate for T-7-01).

## Known Stubs

None. The silent-send path delivers full observable behavior (code send + toast + early return); the resolver closure injection point will be wired live in Plan 07-06. That is a separate plan's responsibility, not a stub — `accountResolver == nil` is a deliberate fall-through condition tested by `testAmbiguousResolutionSetsPendingCodeRequest` (via `{ _ in nil }`) and is the same as "resolver not yet wired."

## TDD Gate Compliance

Not applicable — this plan is `type: execute`, not `type: tdd`. The test scaffolds existed in Plan 07-01 (`test(...)` commit already in history from that plan) and this plan's `test(07-04): ...` commit fills their bodies; the `feat(07-04): ...` commits for RelayClient and AccountStore are the implementation pair. Sequence in git log: two `feat` commits (Tasks 1 + 2) followed by one `test` commit (Task 3) — filling pre-existing scaffolds is post-hoc relative to Plan 07-01 RED, which is correct for an execute-type plan.

## Self-Check: PASSED

- FOUND: `.planning/phases/07-faceid-capability-tokens/07-04-SUMMARY.md` (this file, created by Write)
- FOUND: commit `5d7b357` (Task 1 — AccountStore.resolve)
- FOUND: commit `fcd9e65` (Task 2 — RelayClient silent-send + pbxproj keyboard target fix)
- FOUND: commit `b60876c` (Task 3 — RelayClientSilentSendTests real assertions)
- FOUND: `Shared/RelayClient.swift` contains `var accountResolver: ((CodeRequest) -> Account?)?` (line 20)
- FOUND: `Shared/RelayClient.swift` contains `internal func handleDecodedRequest(_ request: CodeRequest)` (line 194)
- FOUND: `Shared/AccountStore.swift` contains `extension AccountStore` and `func resolve(for request: CodeRequest) -> Account?`
- FOUND: `KeyAuthTests/RelayClientSilentSendTests.swift` contains all 3 `RelayClient.shared.handleDecodedRequest(request)` calls, no remaining `XCTSkip("Wave 0 scaffold …")` strings
- FOUND: `KeyAuth.xcodeproj/project.pbxproj` contains `70A1D62A984AB106092D2C9C /* TrustWindowManager.swift in Sources */` in the KeyAuthKeyboard Sources phase
- Build: `** BUILD SUCCEEDED **` on iPhone 17 sim (OS 26.4.1)
- Tests: 3/3 RelayClientSilentSendTests passed; 14/14 TrustWindow* suites still pass
