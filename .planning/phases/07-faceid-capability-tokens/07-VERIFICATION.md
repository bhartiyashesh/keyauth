---
phase: 07-faceid-capability-tokens
verified: 2026-04-19T17:30:00Z
status: human_needed
score: 9/9 must-haves verified (automated); 2 manual QA items pending signoff
overrides_applied: 0
human_verification:
  - test: "2-DEV-TW-01 — Toast visible above ContentView after FaceID mint flow (FIDO-18)"
    expected: "Second request within 2 min of approval sends code with NO FaceID prompt; toast 'Code sent for <issuer>' appears at the top of ContentView above the safe area, renders with paperplane.fill icon in both Light and Dark mode, and auto-dismisses in ~2 seconds."
    why_human: "SwiftUI `.overlay(alignment: .top)` rendering, safe-area layout, LAContext prompt absence, and Light/Dark mode legibility can only be observed on a physical device (or simulator with Matching Face enabled). Unit tests cover the state machine but cannot assert pixel-level overlay presentation."
  - test: "2-DEV-TW-02 — Chrome extension source unchanged (FIDO-19)"
    expected: "`git diff main...HEAD -- extension/` returns zero lines of change."
    why_human: "Cross-source diff check against main branch — a runtime assertion cannot observe the state of the main ref at QA time. A smoke check at Phase-7 tip shows zero Phase-7 commits under extension/ (verified below), but the formal signoff still requires the solo developer to execute the diff at merge time."
---

# Phase 7: FaceID Capability Tokens — Verification Report

**Phase Goal:** Replace per-fetch FaceID with scoped, TTL'd authorization tokens (CTAP-inspired) to eliminate prompts during re-auth loops on the same login page, without weakening phishing resistance.

**Verified:** 2026-04-19T17:30:00Z
**Status:** human_needed (all 9 automated must-haves verified; 2 manual QA items pending device signoff per 07-QA-CHECKLIST.md)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Second request within 2 min of approval sends code without FaceID prompt (FIDO-01/09/10) | VERIFIED | `RelayClient.handleDecodedRequest` (Shared/RelayClient.swift:194-207) checks `TrustWindowManager.shared.isInWindow` + `TrustWindowPreference.isEnabled` + `accountResolver(request)` + `TOTPGenerator.generate(for: account)` — if all pass, sends silently and returns. `TrustWindowManager.mint()` is called on line 201 of CodeApprovalView.swift right after `BiometricAuthManager.authenticate` success. Unit tests `testSilentSendInWindow` and `testAmbiguousResolutionSetsPendingCodeRequest` assert both branches. |
| 2 | Toast always visible on silent send (FIDO-11/12/18) | VERIFIED (automated) | `RelayClient.handleDecodedRequest:202` calls `TrustWindowManager.shared.showToast(for: account.issuer)`. `showToast` sets `pendingToast = ToastMessage(text: "Code sent for <issuer>")` or `"Code sent"` fallback, posts a VoiceOver announcement, and schedules a 2s auto-dismiss Timer. Tests `testToastTextForMatchedIssuer` (line 149), `testToastTextFallbackEmpty` (160), `testToastAutoDismissAfter2s` (170) all pass. Overlay mounted in ContentView.swift:132-143 via `.overlay(alignment: .top)` with `TransientToastOverlay(message:, icon: "paperplane.fill", iconColor: .secondary, duration: 2.0, ...)`. FIDO-18 visual confirmation is routed to 2-DEV-TW-01 manual QA. |
| 3 | Background / iCloud account change / 2-min expiry each end the window (FIDO-05/06/07) | VERIFIED | `TrustWindowManager.bootstrap()` subscribes to `UIApplication.didEnterBackgroundNotification` and `ICloudStateObserver.shared.$didAccountChange` (TrustWindowManager.swift:66-79), both calling `revoke()`. `mint()` schedules a 120s Timer that also calls `revoke()` on fire (line 90-92). `isInWindow` additionally does a lazy `now() < exp` check for Pitfall-7 safety. Tests `testBackgroundNotificationRevokes`, `testICloudAccountChangeRevokes`, `testIsInWindowLazyExpiryCheck` all pass. |
| 4 | Settings toggle defaults ON and disables feature when OFF (FIDO-16/17) | VERIFIED | `TrustWindowPreference.bootstrap()` (TrustWindowPreference.swift:29-34) sets `trust_window_enabled = true` on fresh install, gated by `hasLaunchedBeforeTrustWindow` sentinel. `mint()` is a no-op when `TrustWindowPreference.isEnabled == false` (TrustWindowManager.swift:86). SettingsView.swift:111-124 renders the Toggle with VERBATIM label "Allow 2-minute trust window after FaceID" and verbatim footer copy. Tests `testBootstrapDefaultsToEnabled`, `testSetEnabledPersistsInUserDefaults`, `testBootstrapIsIdempotentAfterManualSet`, `testMintNoOpWhenPreferenceDisabled`, `testTrustWindowToggleLabelMatchesUISpec`, `testTrustWindowFooterHelperTextVerbatim`, `testTrustWindowSectionHeaderIsSecurity` all pass. |
| 5 | Old 5-min Timer (`startAutoRefresh`) fully removed (D-12) | VERIFIED | `grep -rn "startAutoRefresh" App/ Shared/` returns zero matches. Only references live in `.planning/` and `KeyAuthTests/` (regression tests). `CodeApprovalView.swift:201` replaces the deleted call with `TrustWindowManager.shared.mint()`. Test `testStartAutoRefreshIsAbsent` in CodeApprovalViewTests asserts absence against the test-bundle-copied source via Run-Script build phase. |
| 6 | Every FIDO-01..FIDO-19 has at least one acceptance criterion or automated test proving implementation | VERIFIED (automated) / PARTIAL (manual QA) | 07-VALIDATION.md Per-Task Verification Map enumerates 19 rows. FIDO-01..FIDO-17 are `✅ pass` automated; FIDO-18 and FIDO-19 are documented manual QA routed to 2-DEV-TW-01 and 2-DEV-TW-02. REQUIREMENTS.md Traceability: 17 `Complete (automated)` + 2 `Manual QA pending`. |
| 7 | CONTEXT.md locked decisions (D-01..D-17) all honored | VERIFIED | D-01 mint after FaceID: CodeApprovalView.swift:201 (after `guard success`, after `sendEncryptedCode`). D-02 global scope: no per-origin logic — grep returns zero matches for `originMatch/originScope/per-origin` in Shared/. D-03 fixed-from-mint + D-04 re-mint replaces: `testReMintReplacesExpiry` verifies. D-05/D-06/D-07 revocation triggers: all wired in `bootstrap()` + expiry Timer. D-08 no "Lock now" button: grep returns zero matches. D-09/D-10/D-11 toast UX: SettingsView + ContentView + RelayClient combination. D-12 Timer removed: verified under truth 5. D-13/D-14/D-15 phishing trade-off documented but not enforced at code layer (deliberate). D-16/D-17 default-ON preference + mint gate: TrustWindowPreference.swift. `LAContext` reuse NOT introduced (Claude's Discretion option b chosen — grep for `touchIDAuthenticationAllowableReuseDuration` returns zero matches). |
| 8 | Deferred items NOT implemented | VERIFIED | (a) No per-origin/per-account scope map — Shared/ grep clean. (b) No configurable TTL — `mint(ttl: TimeInterval = 120)` uses a fixed default; no Settings slider. (c) No sliding-window — `testReMintReplacesExpiry` asserts REPLACE semantics. (d) No persistence — `windowExpiresAt` is a `@Published` on a singleton initialized to `nil`; `testSingletonStateIsNotPersisted` asserts. (e) No "Lock now" UI — grep zero matches. (f) No active-tokens UI — none present. |
| 9 | Apple-frameworks-only constraint honored (no new external iOS deps) | VERIFIED | `grep -r "import Alamofire\|import RxSwift\|import SwiftyJSON" Shared/ App/` returns zero matches. No Package.swift or Podfile in the repo root. `TrustWindowManager` imports only `Foundation`, `Combine`, `UIKit`. `TrustWindowPreference` imports only `Foundation`. SUMMARY.md across all 8 plans declares `tech-stack.added: []`. |

**Score:** 9/9 observable truths verified at the code level. 2 manual QA items (FIDO-18, FIDO-19) pending physical-device signoff.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Shared/TrustWindowManager.swift` | @MainActor singleton; mint/revoke/showToast; bootstrap observers; isInWindow lazy check | VERIFIED | 143 lines. `mint(ttl:)` guards on preference, schedules Timer, sets `windowExpiresAt`. `bootstrap()` wires background + iCloud-change Combine sinks. `showToast(for:)` publishes `ToastMessage`, posts VoiceOver, starts 2s dismiss Timer. `isInWindow` does `now() < exp` lazy check. `#if DEBUG` test hooks present. |
| `Shared/TrustWindowPreference.swift` | UserDefaults-backed enum mirroring SyncPreference shape; bootstrap defaults ON | VERIFIED | 35 lines. `isEnabled` getter, `setEnabled(_:)`, `bootstrap()` with `hasLaunchedBeforeTrustWindow` sentinel (distinct from SyncPreference's key per Pitfall 6). Default `true` per D-16. |
| `Shared/RelayClient.swift` — silent-send branch + accountResolver | `var accountResolver: ((CodeRequest) -> Account?)?` + `handleDecodedRequest(_:)` | VERIFIED | Line 23 declares `accountResolver`. Lines 194-207 implement `handleDecodedRequest` with full guard chain (isInWindow, isEnabled, resolver, account, code) → silent send + toast, else `pendingCodeRequest = request` fallthrough. |
| `Shared/AccountStore.swift` — `resolve(for:)` helper | Returns `Account?` with exact/domain/single-account/ambiguous semantics | VERIFIED | Lines 239-259. Exact issuer+label match → domain match (single result wins, multi-match returns nil) → single-account fallback → nil. Doc-comment explicitly marks `nil` as the "defer to FaceID" signal, not an error. |
| `App/KeyAuthApp.swift` — lifecycle wiring | @StateObject trustWindow; environmentObject; bootstrap; resolver install | VERIFIED | Line 10 `@StateObject private var trustWindow = TrustWindowManager.shared`. Line 32 `.environmentObject(trustWindow)`. Lines 89-100 `bootstrapTrustWindowPreferenceOnce()` calls `TrustWindowPreference.bootstrap()`, `trustWindow.bootstrap()`, and installs `RelayClient.shared.accountResolver = { [weak store] request in store?.resolve(for: request) }`. |
| `App/Views/CodeApprovalView.swift` — mint post-FaceID; startAutoRefresh removed | Mint on line 201 after `guard success`, after `sendEncryptedCode`; no `startAutoRefresh` | VERIFIED | Line 201 `TrustWindowManager.shared.mint()` after `guard success else { return }` (186) and after `RelayClient.shared.sendEncryptedCode` (193). `startAutoRefresh` grep returns zero matches across App/ and Shared/. |
| `App/Views/SettingsView.swift` — Security section + toggle | `trustWindowSection` with Toggle, verbatim label + footer + Security header | VERIFIED | Lines 111-124. Section header `Text("Security")`, Toggle label `"Allow 2-minute trust window after FaceID"` (verbatim UI-SPEC), footer `"Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background."` (verbatim). `@State trustWindowEnabled: Bool = TrustWindowPreference.isEnabled`, onChange writes back via `setEnabled`. |
| `App/Views/ContentView.swift` — overlay mount | `.overlay(alignment: .top)` with `TransientToastOverlay` driven by `trustWindow.pendingToast` | VERIFIED | Line 10 `@EnvironmentObject var trustWindow: TrustWindowManager`. Lines 132-143 `.overlay(alignment: .top)` with `TransientToastOverlay(message: toast.text, icon: "paperplane.fill", iconColor: .secondary, duration: 2.0, isPresented: .constant(true))` + `.padding(.top, 8)`. Line 144 `.animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)`. |
| `App/Views/TransientToastOverlay.swift` — duration parameter | `duration: Double = 3.0` with default preserved, Phase 7 caller passes 2.0 | VERIFIED | Line 20 declares `let duration: Double`. Init defaults to 3.0 (line 28). Line 54 `DispatchQueue.main.asyncAfter(deadline: .now() + duration)`. Reduce-motion transition branch present (lines 49-51). |
| `KeyAuthTests/TrustWindowManagerTests.swift` | 11 tests covering FIDO-01..07, 11, 12, 17 | VERIFIED | All 11 tests present and substantive (file reviewed). Each test has explicit FIDO-NN comment. |
| `KeyAuthTests/TrustWindowPreferenceTests.swift` | 3 tests covering FIDO-14, FIDO-16 | VERIFIED | 3 tests: bootstrap-default-ON, setEnabled persistence, bootstrap idempotency (Pitfall 6). |
| `KeyAuthTests/RelayClientSilentSendTests.swift` | 3 tests covering FIDO-09, FIDO-10 | VERIFIED | 3 tests: silent-send-in-window, ambiguous-defers, out-of-window-falls-through. Resolver-injection pattern avoids WebSocket/PairingStore plumbing. |
| `KeyAuthTests/CodeApprovalViewTests.swift` | 2 grep-based tests for FIDO-08, FIDO-13 | VERIFIED | Tests load bundled `CodeApprovalView.swift.txt` (via Run-Script build phase) and assert mint-after-guard-and-send ordering + startAutoRefresh absence. |
| `KeyAuthTests/SettingsViewTests.swift` (Phase 7 additions) | FIDO-15 toggle label, footer helper text, "Security" section header | VERIFIED | 3 Phase-7 tests added at lines 135, 141, 147 (total 15 tests in file, mix of Phase 6 + 7). |
| `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` | Factory `make()` + `empty()` for silent-send tests | VERIFIED | Referenced by RelayClientSilentSendTests; created in Plan 07-01 Wave 0 per SUMMARY. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| CodeApprovalView | TrustWindowManager | `TrustWindowManager.shared.mint()` after FaceID success | WIRED | Line 201 of CodeApprovalView.swift, placed AFTER `guard success else { return }` (L186) and AFTER `sendEncryptedCode` (L193). CodeApprovalViewTests asserts the ordering invariant. |
| RelayClient | TrustWindowManager | `isInWindow` gate + `showToast(for:)` post-send | WIRED | Lines 195 + 202 of RelayClient.swift. |
| RelayClient | AccountStore | `accountResolver` closure installed in KeyAuthApp | WIRED | KeyAuthApp.swift:97-99 `RelayClient.shared.accountResolver = { [weak store] request in store?.resolve(for: request) }`. Weak capture prevents store lifetime extension. |
| TrustWindowManager | ICloudStateObserver | `$didAccountChange` Combine sink in `bootstrap()` | WIRED | TrustWindowManager.swift:74-79. Revocation test `testICloudAccountChangeRevokes` uses `_primeAsSignedIn() + _simulateIdentityChange(nil)`. |
| TrustWindowManager | UIApplication background notification | `.publisher(for: .didEnterBackgroundNotification).sink` in `bootstrap()` | WIRED | TrustWindowManager.swift:66-71. Test `testBackgroundNotificationRevokes` posts the notification and asserts `isInWindow == false`. |
| ContentView | TrustWindowManager | `@EnvironmentObject var trustWindow: TrustWindowManager` + `.overlay { trustWindow.pendingToast }` | WIRED | ContentView.swift:10 + 132-144. |
| KeyAuthApp | TrustWindowManager | `@StateObject` + `.environmentObject(trustWindow)` + `trustWindow.bootstrap()` | WIRED | KeyAuthApp.swift:10, 32, 93. |
| SettingsView | TrustWindowPreference | Toggle bound to `@State trustWindowEnabled`; `onChange` → `TrustWindowPreference.setEnabled` | WIRED | SettingsView.swift:20 + 113-116. |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| ContentView toast overlay | `trustWindow.pendingToast` | `TrustWindowManager.showToast(for:)` set from `RelayClient.handleDecodedRequest` silent branch | Yes — driven by real incoming CodeRequest via WebSocket | FLOWING |
| SettingsView toggle | `trustWindowEnabled: Bool` | Initial: `TrustWindowPreference.isEnabled` (UserDefaults); onChange: `TrustWindowPreference.setEnabled` persists back | Yes — UserDefaults round-trip | FLOWING |
| RelayClient silent branch | `account` | `accountResolver(request)` → `AccountStore.resolve(for:)` | Yes — `AccountStore.accounts` is the Keychain-backed source-of-truth list | FLOWING |
| CodeApprovalView mint | `TrustWindowManager.shared.mint()` | Called after `BiometricAuthManager.authenticate` returns `true` | Yes — mint writes `windowExpiresAt` which `RelayClient.handleDecodedRequest` reads on next request | FLOWING |

All Level-4 data paths are live — no hollow props, no disconnected sources. The silent-send end-to-end contract is unit-tested (`testSilentSendInWindow`) and the remaining visual confirmation (toast overlay on physical device) is routed to 2-DEV-TW-01 manual QA.

---

### Behavioral Spot-Checks

Skipped category: physical-device behavior (manual QA) + LAContext UI prompt absence (unit tests cannot observe). The automatable spot-checks are mirrored by the existing test suite which I cannot execute from this harness. The SUMMARY.md and VALIDATION.md both record `xcodebuild test -only-testing:KeyAuthTests` passing at 88 tests / 0 failures / 1 skipped at plan-closure time.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Test suite green (88/0/1-skipped) | Inferred from 07-08-SUMMARY.md Task 5 full-suite run + STATE.md post-merge record | Recorded green in SUMMARY | PASS (per SUMMARY claim; formally verified by the orchestrator) |
| `startAutoRefresh` grep clean | `grep -rn "startAutoRefresh" App/ Shared/` | Zero matches | PASS |
| `TrustWindowManager.shared.mint()` present post-FaceID | `grep -q "TrustWindowManager.shared.mint" App/Views/CodeApprovalView.swift` | Match at line 201 | PASS |
| `accountResolver` declared in RelayClient | `grep -q "accountResolver" Shared/RelayClient.swift` | Match at lines 23, 188, 189, 197 | PASS |
| `resolve(for:` method on AccountStore | grep with escaped parens | Match at line 239 | PASS |
| Toggle literal in SettingsView | `grep -q "TrustWindowPreference" App/Views/SettingsView.swift` | Match at lines 20, 115 | PASS |
| Toast overlay mounted | `grep -q "TransientToastOverlay" App/Views/ContentView.swift` | Match at line 134 | PASS |
| Trust window envObject wired | `grep "environmentObject(trustWindow" App/KeyAuthApp.swift` | Match at line 32 | PASS |
| `nyquist_compliant: true` | frontmatter check in 07-VALIDATION.md | Line 5 | PASS |
| No external iOS deps | `grep -r "import Alamofire|import RxSwift|import SwiftyJSON" Shared/ App/` | Zero matches | PASS |
| No LAContext reuse in silent path | `grep -r "touchIDAuthenticationAllowableReuseDuration" Shared/ App/` | Zero matches | PASS |
| No "Lock now" UI | `grep -rn "Lock now\|lockNow" App/` | Zero matches | PASS |
| Extension unchanged since 2026-04-19 | `git log --since=2026-04-19 -- extension/` | No commits | PASS (smoke) |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| FIDO-01 | `TrustWindowManager.shared` singleton on `@MainActor`, transient `isInWindow` from `windowExpiresAt` | SATISFIED | TrustWindowManager.swift:31-35, `testInitialState_isInWindowIsFalse` |
| FIDO-02 | `mint()` sets expiry to now+120 when preference ON | SATISFIED | Line 85-92, `testMintSetsExpiryTo120sFromNow` |
| FIDO-03 | `mint()` is no-op when preference OFF (D-17) | SATISFIED | Line 86, `testMintNoOpWhenPreferenceDisabled` |
| FIDO-04 | Re-mint replaces (fresh 120s, not sliding or additive) | SATISFIED | Line 87-89, `testReMintReplacesExpiry` |
| FIDO-05 | Lazy expiry check on `isInWindow` (Pitfall 7 belt-and-suspenders) | SATISFIED | Line 47-50, `testIsInWindowLazyExpiryCheck` |
| FIDO-06 | Background notification revokes | SATISFIED | Lines 66-71, `testBackgroundNotificationRevokes` |
| FIDO-07 | iCloud account change revokes | SATISFIED | Lines 74-79, `testICloudAccountChangeRevokes` |
| FIDO-08 | `CodeApprovalView.approveAndSend` calls `mint()` post-`authenticate` success | SATISFIED | CodeApprovalView.swift:201, `testMintCallAppearsAfterAuthenticateSuccess` |
| FIDO-09 | Silent-send branch in `handleDecodedRequest` with full guard chain | SATISFIED | RelayClient.swift:194-207, `testSilentSendInWindow` |
| FIDO-10 | Ambiguous resolver defers to FaceID | SATISFIED | Line 206 fallthrough, `testAmbiguousResolutionSetsPendingCodeRequest` |
| FIDO-11 | Toast copy: `"Code sent for <issuer>"` / `"Code sent"` fallback | SATISFIED | TrustWindowManager.swift:107, `testToastTextForMatchedIssuer` + `testToastTextFallbackEmpty` |
| FIDO-12 | Toast auto-dismiss 2.0s | SATISFIED | Lines 115-118, `testToastAutoDismissAfter2s` |
| FIDO-13 | `startAutoRefresh` deleted from App/ and Shared/ | SATISFIED | Grep zero matches, `testStartAutoRefreshIsAbsent` |
| FIDO-14 | `TrustWindowPreference` UserDefaults-backed with `isEnabled`/`setEnabled`/`bootstrap` | SATISFIED | TrustWindowPreference.swift, `testSetEnabledPersistsInUserDefaults` |
| FIDO-15 | Toggle label + footer verbatim; "Security" header | SATISFIED | SettingsView.swift:111-124, `testTrustWindowToggleLabelMatchesUISpec` + `testTrustWindowFooterHelperTextVerbatim` + `testTrustWindowSectionHeaderIsSecurity` |
| FIDO-16 | Fresh-install bootstrap defaults ON (D-16) | SATISFIED | TrustWindowPreference.swift:32, `testBootstrapDefaultsToEnabled` |
| FIDO-17 | Window NOT persisted across launches | SATISFIED | In-memory singleton state only; `testSingletonStateIsNotPersisted` |
| FIDO-18 | Toast overlay visible above ContentView post-sheet-dismiss | NEEDS HUMAN | Routed to 2-DEV-TW-01 (07-QA-CHECKLIST.md). Code-level wiring VERIFIED; visual rendering on device is the manual step. |
| FIDO-19 | Chrome extension source NOT modified | NEEDS HUMAN (smoke PASS) | Git log smoke shows zero `extension/` commits since 2026-04-19. Formal `git diff main...HEAD -- extension/` run at merge time is routed to 2-DEV-TW-02. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | — |

No blocker or warning anti-patterns found in the reviewed files. Informational:

- TrustWindowManager exposes `#if DEBUG` test hooks (`_fireExpiryTimerNow`, `_resetForTests`) — appropriately guarded, not shipped in release builds.
- SettingsView `trustWindowSection` duplicates the verbatim-string discipline from Phase 6 (doc-comment + grep-asserting tests), which is the sanctioned pattern, not a smell.
- `var accountResolver: ((CodeRequest) -> Account?)?` on `RelayClient` is a deliberate injection seam. Its sole production setter is KeyAuthApp.swift:97 and tests in RelayClientSilentSendTests clear it in `tearDown`. Singleton mutable state is a smell in general but is appropriately scoped here.

---

### Human Verification Required

Two items remain for the solo developer to sign off before the phase closes. Both are documented in 07-QA-CHECKLIST.md and were explicitly routed to manual QA at plan time (Plan 07-08 frontmatter `requirements-completed: [FIDO-18, FIDO-19]` with "Manual QA pending" annotations).

#### 1. 2-DEV-TW-01 — Toast visible above ContentView after FaceID mint flow (FIDO-18)

**Test:** On a physical iPhone with FaceID (or simulator with "Matching Face" enabled), pair the Chrome extension, request a code, approve via FaceID, and within 2 minutes request a second code. Confirm no FaceID prompt on the second request and that a `"Code sent for <issuer>"` toast with the paperplane icon appears above ContentView and auto-dismisses in ~2 seconds. Verify legibility in both Light and Dark mode.

**Expected:** Steps 1-4 (first FaceID flow) complete; step 6 shows silent send + toast. No FaceID prompt on the second request. Toast is visible above the safe area, paperplane icon rendered, text readable in both appearances, fades after ~2s.

**Why human:** SwiftUI `.overlay` pixel-level rendering, safe-area layout, Light/Dark legibility, and LAContext prompt absence cannot be asserted from unit tests.

#### 2. 2-DEV-TW-02 — Chrome extension source unchanged (FIDO-19)

**Test:** `git diff main...HEAD -- extension/` at merge time.

**Expected:** Zero lines of output.

**Why human:** The assertion is a cross-ref diff against the `main` branch state at merge time — smoke check via `git log --since=2026-04-19 -- extension/` at verification time returns no commits, but the formal signoff belongs to the developer at PR merge.

---

### Gaps Summary

No gaps. All 9 automated must-haves are verified at the code level with substantive implementations, wired end-to-end, and unit-tested at the behavior level. The remaining two items (FIDO-18 visual toast rendering, FIDO-19 extension-source diff) are documented manual QA items intentionally routed to device checks — they are independent of code correctness and were planned as manual from the outset (see 07-QA-CHECKLIST.md and 07-VALIDATION.md Manual-Only Verifications table).

Per the verifier decision tree, because Step 8 produced human verification items, the overall status is `human_needed` — not `passed` — even though all automated must-haves are green. The orchestrator / solo developer signoff on 2-DEV-TW-01 and 2-DEV-TW-02 closes the phase.

---

## Notes on ROADMAP vs. CONTEXT divergence

The ROADMAP Phase 7 `**Description:**` paragraph (lines 127-133) describes per-origin capability tokens, a 5-minute TTL, LAContext reuse, and a "Lock now" action — these were the pre-planning proposals. During CONTEXT capture on 2026-04-19, the user explicitly rejected per-origin/per-account refinement (D-02, D-14), the "Lock now" button (D-08), sliding-window TTL (D-03), and configurable TTL (Deferred Ideas). The 5-minute value was replaced with 2 minutes (D-01). These are documented deviations, not gaps — CONTEXT.md supersedes the ROADMAP description as the locked contract, and the PLAN frontmatter must_haves correctly reflect the post-CONTEXT design. The tracking-table row in ROADMAP.md still reads `0/TBD | Not planned | -` (line 94); updating that to `8/8 | Conditional Pass (manual QA pending) | -` is a ROADMAP-bookkeeping task that belongs to the orchestrator's post-verification pass, not a Phase-7 implementation gap.

---

*Verified: 2026-04-19T17:30:00Z*
*Verifier: Claude (gsd-verifier)*
