---
phase: 07-faceid-capability-tokens
plan: 03
subsystem: trust-window-manager
tags: [trust-window, manager, singleton, mainactor, combine, revocation, tests]
dependency_graph:
  requires:
    - "Shared/TrustWindowPreference.swift (Plan 07-02): D-17 gate for mint()"
    - "Shared/ICloudStateObserver.swift (Phase 6): $didAccountChange publisher for D-06 revoke"
    - "KeyAuthTests/TrustWindowManagerTests.swift scaffolds (Plan 07-01): 11 method stubs to fill"
  provides:
    - "TrustWindowManager.shared.isInWindow (Bool) — gate for silent-send branch in Plan 07-04"
    - "TrustWindowManager.shared.mint() — called from CodeApprovalView in Plan 07-05"
    - "TrustWindowManager.shared.showToast(for:) — called from silent-send branch in Plan 07-04"
    - "TrustWindowManager.shared.pendingToast (Published) — bound by ContentView overlay in Plan 07-07"
    - "TrustWindowManager.shared.bootstrap() — wired once in KeyAuthApp in Plan 07-06"
    - "ToastMessage struct (Equatable, Identifiable) — SwiftUI overlay payload"
  affects:
    - "Plan 07-04 (RelayClient silent-send): consumes isInWindow + showToast"
    - "Plan 07-05 (CodeApprovalView mint): calls mint() post-FaceID"
    - "Plan 07-06 (KeyAuthApp wiring): calls bootstrap() once on onAppear"
    - "Plan 07-07 (ContentView toast overlay): binds to pendingToast"
tech_stack:
  added: []
  patterns:
    - "@MainActor singleton with static shared (ICloudStateObserver analog)"
    - "Injectable clock seam: var now: () -> Date = { Date() } for deterministic tests"
    - "Set<AnyCancellable> storage for Combine subscriptions (established idiom)"
    - "Timer.scheduledTimer(withTimeInterval:, repeats: false) + [weak self] + Task @MainActor (RelayClient analog)"
    - "Lazy derived property: var isInWindow: Bool { guard let exp; return now() < exp } (Pitfall 7 belt-and-suspenders)"
    - "#if DEBUG test-only helpers (_fireExpiryTimerNow, _resetForTests) mirroring ICloudStateObserver._primeAsSignedIn"
    - "UIAccessibility.post .announcement for VoiceOver unprompted announcement"
key_files:
  created:
    - "Shared/TrustWindowManager.swift"
  modified:
    - "KeyAuth.xcodeproj/project.pbxproj (wired TrustWindowManager.swift into KeyAuth app target only; NOT keyboard)"
    - "KeyAuthTests/TrustWindowManagerTests.swift (replaced 11 Wave 0 XCTSkip scaffolds with real assertions)"
decisions:
  - "Adopted the research-endorsed Combine .publisher(for:).sink + store(in: &cancellables) pattern for both revocation observers (D-05 + D-06). This keeps lifetime management idiomatic and aligns with ICloudStateObserver usage elsewhere in the codebase."
  - "Implemented belt-and-suspenders: the lazy `isInWindow` getter uses `now() < exp` in addition to the scheduled expiry Timer. This guarantees silent-send can never fire past expiry even if iOS suspends the Timer while the app is backgrounded (Pitfall 7)."
  - "Exposed `_resetForTests()` as a #if DEBUG hook rather than making `init` internal. Keeps the `private init()` invariant for production code while enabling singleton-state hygiene in unit tests."
  - "Used iPhone 17 simulator for verification (plan referenced iPhone 16, which is not installed on this Mac's simulator runtime — see Deviations)."
metrics:
  duration_seconds: 300
  tasks_completed: 2
  tests_passing: 11
  files_created: 1
  files_modified: 2
  completed_date: "2026-04-19"
requirements_verified:
  - FIDO-01
  - FIDO-02
  - FIDO-03
  - FIDO-04
  - FIDO-05
  - FIDO-06
  - FIDO-07
  - FIDO-11
  - FIDO-12
  - FIDO-17
---

# Phase 7 Plan 03: TrustWindowManager Core Summary

In-memory 2-minute trust window singleton with MainActor-isolated expiry state, injectable clock seam, background + iCloud revocation observers, and transient toast publisher — all 11 scaffolded FIDO-01..07/11/12/17 tests now pass.

## One-liner

`@MainActor` singleton `TrustWindowManager` implements the Phase 7 trust-window state machine: fixed-from-mint 120s TTL, three-way revocation (background / iCloud-account-change / Timer), and 2-second transient toast — wired into the KeyAuth app target only.

## Tasks Completed

| # | Task | Status | Commit | Duration |
|---|------|--------|--------|----------|
| 1 | Create Shared/TrustWindowManager.swift + pbxproj wiring (KeyAuth app target only) | done | `12d6d58` | ~2m (build) |
| 2 | Replace 11 Wave 0 scaffolds in TrustWindowManagerTests.swift with real assertions | done | `f6fc501` | ~2m (test run) |

## Artifact 1 — Shared/TrustWindowManager.swift (full source)

```swift
import Foundation
import Combine
import UIKit

/// Transient toast payload — driven by `TrustWindowManager.pendingToast` and consumed by
/// `ContentView`'s `.overlay(alignment: .top)` via the shared `TransientToastOverlay` component.
///
/// `Identifiable` + UUID `id` so SwiftUI's `.animation(value:)` crossfades when the text changes
/// mid-display during rapid-fire silent sends (RESEARCH.md Pitfall 4 — latest-wins semantics).
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

/// Holds the 2-minute trust window state granted after a successful FaceID (or passcode fallback)
/// approval. Purely in-memory — NOT persisted. Reset to `nil` on app launch (CONTEXT.md D-17 /
/// FIDO-17).
///
/// Revocation triggers (any one ends the window):
///   - `UIApplication.didEnterBackgroundNotification` (D-05)
///   - `ICloudStateObserver.shared.$didAccountChange == true` (D-06)
///   - 2-minute Timer expiry (D-07)
///
/// Usage:
///   - `KeyAuthApp.onAppear` calls `bootstrap()` once (idempotent — guarded internally by
///     `didBootstrap` so repeat invocations are safe no-ops).
///   - `CodeApprovalView.approveAndSend` calls `mint()` after FaceID success.
///   - `RelayClient.handleMessage` checks `isInWindow` to branch silent-send vs FaceID prompt.
///   - `RelayClient.handleMessage` calls `showToast(for:)` after a silent send.
@MainActor
final class TrustWindowManager: ObservableObject {
    static let shared = TrustWindowManager()

    /// Expiry timestamp for the active window. `nil` when no window is open.
    @Published private(set) var windowExpiresAt: Date?

    /// Transient toast driver. SwiftUI `ContentView.overlay` binds to this.
    @Published var pendingToast: ToastMessage?

    /// Injectable clock seam for deterministic expiry tests (FIDO-04 / FIDO-05).
    /// Defaults to `Date()` in production; tests assign a closure returning a controlled clock.
    var now: () -> Date = { Date() }

    /// Derived — returns `false` if no window OR if `now()` has passed `windowExpiresAt`.
    /// Lazy check guarantees silent-send never fires past expiry even if the scheduled
    /// Timer runs late (RESEARCH.md Pitfall 7 — belt-and-suspenders).
    var isInWindow: Bool {
        guard let exp = windowExpiresAt else { return false }
        return now() < exp
    }

    private var expiryTimer: Timer?
    private var toastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private init() {}

    /// Wire revocation observers. Idempotent — safe to call twice (second call is a no-op).
    /// Call ONCE from KeyAuthApp.onAppear after TrustWindowPreference.bootstrap().
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        // D-05 — background revokes.
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.revoke() }
            }
            .store(in: &cancellables)

        // D-06 — iCloud account change revokes.
        ICloudStateObserver.shared.$didAccountChange
            .sink { [weak self] changed in
                guard changed else { return }
                Task { @MainActor in self?.revoke() }
            }
            .store(in: &cancellables)
    }

    /// Opens a fresh `ttl`-second window iff the user has not disabled the feature (D-17).
    /// A second mint within the window REPLACES the prior expiry with a fresh TTL (D-04 —
    /// FaceID restart; NOT sliding-window). The previous Timer is invalidated first.
    func mint(ttl: TimeInterval = 120) {
        guard TrustWindowPreference.isEnabled else { return }
        expiryTimer?.invalidate()
        let expiry = now().addingTimeInterval(ttl)
        windowExpiresAt = expiry
        expiryTimer = Timer.scheduledTimer(withTimeInterval: ttl, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.revoke() }
        }
    }

    /// Ends the window immediately. Called by: background observer, iCloud-account-change
    /// observer, expiry Timer fire. Does NOT nil `pendingToast` — toast lifecycle is
    /// independent (UI-SPEC: toggle OFF does not force-revoke in-flight toasts).
    func revoke() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        windowExpiresAt = nil
    }

    /// Publishes a 2-second transient toast. Replaces any in-flight toast (Pitfall 4 —
    /// latest-wins). VoiceOver users get an unprompted announcement via UIAccessibility.post.
    func showToast(for issuer: String) {
        let text = issuer.isEmpty ? "Code sent" : "Code sent for \(issuer)"
        pendingToast = ToastMessage(text: text)

        // Accessibility: unprompted announcement so VoiceOver users learn a silent send occurred
        // even when the toast is not focused. UI-SPEC Open Question 3 chose UIAccessibility.post
        // (available since iOS 3) over iOS 17's AccessibilityNotification.Announcement.
        UIAccessibility.post(notification: .announcement, argument: text)

        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pendingToast = nil }
        }
    }

    // MARK: - Test-only helpers (DEBUG-guarded so they cannot ship in release builds)

    #if DEBUG
    /// Forces the expiry Timer to fire now without waiting 120s. Lets tests assert the
    /// post-expiry state machine (FIDO-05 / FIDO-12) without a real-time wait.
    internal func _fireExpiryTimerNow() {
        expiryTimer?.invalidate()
        revoke()
    }

    /// Resets the singleton to a clean state between tests without tearing down the Combine
    /// subscriptions (which other tests depend on for FIDO-06 / FIDO-07).
    internal func _resetForTests() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        toastTimer?.invalidate()
        toastTimer = nil
        windowExpiresAt = nil
        pendingToast = nil
        now = { Date() }
    }
    #endif
}
```

## Artifact 2 — project.pbxproj wiring confirmation

Wired into the **KeyAuth app target only**, NOT the KeyAuthKeyboard extension (confirmed via Ruby xcodeproj gem inspection at write-time and grep count afterward):

```
$ grep -n "TrustWindowManager.swift" KeyAuth.xcodeproj/project.pbxproj
49:  70A1D62A984AB106092D2C9B /* TrustWindowManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 4A5BC8822DEB7279C12015C4 /* TrustWindowManager.swift */; };
124: 4A5BC8822DEB7279C12015C4 /* TrustWindowManager.swift */ = {isa = PBXFileReference; ...};
225: 4A5BC8822DEB7279C12015C4 /* TrustWindowManager.swift */,       ← Shared group
550: 70A1D62A984AB106092D2C9B /* TrustWindowManager.swift in Sources */,  ← KeyAuth app Sources phase (FD172B49...)
```

Single `PBXBuildFile` entry (line 49) and single `PBXSourcesBuildPhase` membership (line 550, inside `FD172B49298DD9FC691EA8DE /* Sources */` — the KeyAuth app target's Sources phase). Matches the plan's architectural responsibility map: keyboard extension does not participate in the relay flow, so the manager is not linked into it.

## Artifact 3 — xcodebuild test pass log (11/11)

```
Test Suite 'TrustWindowManagerTests' started at 2026-04-19 11:05:38.926.
Test Case '-[KeyAuthTests.TrustWindowManagerTests testBackgroundNotificationRevokes]' passed (0.062 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testICloudAccountChangeRevokes]' passed (0.054 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testInitialState_isInWindowIsFalse]' passed (0.001 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testIsInWindowLazyExpiryCheck]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testMintNoOpWhenPreferenceDisabled]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testMintSetsExpiryTo120sFromNow]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testReMintReplacesExpiry]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testSingletonStateIsNotPersisted]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testToastAutoDismissAfter2s]' passed (2.316 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testToastTextFallbackEmpty]' passed (0.002 seconds).
Test Case '-[KeyAuthTests.TrustWindowManagerTests testToastTextForMatchedIssuer]' passed (0.001 seconds).
Test Suite 'TrustWindowManagerTests' passed at 2026-04-19 11:05:41.375.
  Executed 11 tests, with 0 failures (0 unexpected) in 2.446 (2.449) seconds
** TEST SUCCEEDED **
```

FIDO-mapping verified per-test:

| Test | FIDO | Assertion |
|------|------|-----------|
| testInitialState_isInWindowIsFalse | FIDO-01 | isInWindow == false, windowExpiresAt == nil, pendingToast == nil at clean state |
| testMintSetsExpiryTo120sFromNow | FIDO-02 | clock-injected mint sets windowExpiresAt = t0 + 120, accuracy 0.5 |
| testMintNoOpWhenPreferenceDisabled | FIDO-03 / T-7-06 | setEnabled(false) + mint() leaves isInWindow false |
| testReMintReplacesExpiry | FIDO-04 | mint at t0 → mint at t0+60 → secondExpiry - firstExpiry == 60s (not 0, not 120) |
| testIsInWindowLazyExpiryCheck | FIDO-05 / Pitfall 7 | clock += 121s → isInWindow false even before Timer fires |
| testBackgroundNotificationRevokes | FIDO-06 / D-05 | post didEnterBackgroundNotification → 50ms hop → isInWindow false |
| testICloudAccountChangeRevokes | FIDO-07 / D-06 | _primeAsSignedIn + _simulateIdentityChange(nil) → 50ms hop → isInWindow false |
| testToastTextForMatchedIssuer | FIDO-11 | showToast("GitHub") → pendingToast?.text == "Code sent for GitHub" |
| testToastTextFallbackEmpty | FIDO-11 | showToast("") → pendingToast?.text == "Code sent" |
| testToastAutoDismissAfter2s | FIDO-12 | pendingToast non-nil immediately, nil after 2.3s wall-clock |
| testSingletonStateIsNotPersisted | FIDO-17 | mint → _resetForTests → isInWindow false, windowExpiresAt nil |

## Pitfall 7 narrative (how Timer + lazy isInWindow cooperate)

Phase 7's trust window has two independent mechanisms for expiry, and the belt-and-suspenders design ensures the window never outlives its intent even when iOS misbehaves:

**Mechanism A — scheduled `Timer`:** `mint()` schedules a `Timer.scheduledTimer(withTimeInterval: 120, repeats: false)` whose fire block calls `revoke()`, which clears `windowExpiresAt`. On the happy path (app stays foregrounded, RunLoop runs), this fires exactly 120s after mint and the window dies cleanly. But Timer is tied to the main RunLoop, which iOS suspends when the app goes to background — and a suspended process can resume minutes or hours later, with the Timer then firing "late". During that delay, any code that reads `windowExpiresAt` directly would falsely conclude the window is still open. D-05's background revoke guards against this in production (the notification fires before suspension), but a defensive second layer costs almost nothing.

**Mechanism B — lazy `isInWindow` getter:** The public gate callers use is `var isInWindow: Bool { guard let exp = windowExpiresAt else { return false }; return now() < exp }`. Every read compares `now()` against the stored expiry. Even if the Timer is asleep and `windowExpiresAt` is still set to a past timestamp, the getter returns `false`. Silent-send branches in `RelayClient` gate on `isInWindow`, so a code can never be emitted outside the 120s envelope regardless of Timer state. The injectable `var now: () -> Date` makes this directly testable: `testIsInWindowLazyExpiryCheck` advances the clock past expiry without triggering the Timer and asserts `isInWindow == false`.

Together the two mechanisms form a three-belt safety system: (1) `didEnterBackgroundNotification` revokes the window the instant the app loses foreground (cheapest, fires before Timer matters); (2) the Timer fires eventually and cleans up stored state; (3) the lazy getter refuses to report "in window" if wall-clock has already passed expiry. Any single failure is harmless — all three would need to fail simultaneously for a stale window to leak a code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] iPhone 16 simulator unavailable, used iPhone 17 instead**
- **Found during:** Task 1 build verification
- **Issue:** The plan's verify command hardcodes `'platform=iOS Simulator,name=iPhone 16,OS=latest'` but the local Xcode only has iPhone 15, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone 17e, and iPhone Air simulators installed. `xcodebuild` returned the full runtime list with no iPhone 16 entry.
- **Fix:** Substituted `iPhone 17` (latest non-Pro) for both the build and the test run. Build succeeded; 11/11 tests pass.
- **Files modified:** none — this is a verification-environment substitution, not a code deviation.
- **Commit:** N/A (not a code change)

No other deviations. The production code matches the plan's `<interfaces>` contract verbatim. The test method bodies match the plan's per-test assertion spec verbatim.

## Auth Gates

None encountered. Plan is fully autonomous and purely local.

## Self-Check: PASSED

- `Shared/TrustWindowManager.swift` exists and compiles (build succeeded).
- `KeyAuthTests/TrustWindowManagerTests.swift` no longer contains any `XCTSkip("Wave 0 scaffold …")` bodies.
- All 11 tests pass in the iPhone 17 simulator (`** TEST SUCCEEDED **`).
- Commits `12d6d58` (feat) and `f6fc501` (test) present in `git log`.
- `grep` confirms TrustWindowManager.swift appears in the KeyAuth app target Sources phase (line 550) but NOT in the KeyAuthKeyboard target Sources phase (lines 461-488).
- No new external dependencies — Apple frameworks only (Foundation, Combine, UIKit).
- STATE.md and ROADMAP.md untouched (parallel-executor mode honored).
