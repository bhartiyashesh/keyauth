# Phase 7: FaceID Capability Tokens - Research

**Researched:** 2026-04-19
**Domain:** iOS biometric trust window + SwiftUI transient UI + transient singleton state on Apple frameworks only
**Confidence:** HIGH (all integration points verified in codebase; Apple behaviors cross-referenced)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Trust Window Behavior**
- **D-01:** A successful FaceID (or passcode-fallback per existing `BiometricAuthManager` policy) on a code request opens a **2-minute trust window**. Any subsequent code request received from the paired extension during the window is approved automatically without prompting FaceID.
- **D-02:** Window scope is **global per pairing** — covers any account and any site. The user explicitly chose simplicity over per-account/per-origin scope refinement.
- **D-03:** TTL is **fixed-from-mint** — exactly 2 minutes from the FaceID approval moment, regardless of how many silent sends occur during the window. Uses do NOT extend the window.
- **D-04:** Each FaceID approval restarts the window from a fresh 2 minutes. There is no way to extend a window without a new FaceID.

**Revocation Triggers (window ends early when ANY of these fire)**
- **D-05:** App enters background (`UIApplication.didEnterBackgroundNotification`). This already triggers `isUnlocked = false` and `RelayClient.disconnect()` in `KeyAuthApp.swift` — the window invalidation hooks into the same lifecycle event.
- **D-06:** iCloud account change (`ICloudStateObserver.didAccountChange` becomes `true` — already wired in Phase 6).
- **D-07:** 2-minute timer expiry (the natural end).
- **D-08:** No "Lock now" button. User explicitly rejected adding one.

**Silent-Send UX**
- **D-09:** When a code is sent during an active window without FaceID, the phone shows a brief transient toast: **"Code sent for [issuer]"** (or "Code sent" if issuer is empty). Toast appears for ~2 seconds, then fades.
- **D-10:** Toast must appear regardless of whether the app is foregrounded with `CodeApprovalView` open or backgrounded-then-foregrounded. If app is backgrounded the window is already revoked (D-05), so this case won't occur, but document the assumption.
- **D-11:** No `CodeApprovalView` sheet appears for silent sends — the toast is the entire UI for an in-window auto-approval. Sheet only appears for the FIRST request that mints the window OR after window expiry.

**Replacement of Existing 5-min Timer**
- **D-12:** The current `CodeApprovalView.startAutoRefresh(account:)` Timer is **removed**. New behavior is purely request-driven.
- **D-13:** Behavior change for existing users: codes no longer auto-arrive in the extension on TOTP rotation. The extension must explicitly request a fresh code if its cached one expires.

**Security Trade-off**
- **D-14:** Global scope means phishing sites can trigger a silent `request_code` within 2 minutes of approval. Visible toast (D-09) is the user's only mitigation.
- **D-15:** Origin is captured via `chrome.tabs.query` and travels in `CodeRequest.domain` but NOT used for window-scope checking in v1.

**Settings Surface**
- **D-16:** Settings toggle "Allow 2-minute trust window after FaceID". Default: **ON** for new users, **ON** for existing users. When OFF, every request requires FaceID.
- **D-17:** When the toggle is OFF, no window is ever minted regardless of FaceID approvals.

### Claude's Discretion

- **In-memory token store architecture:** Singleton (`TrustWindowManager`) on `@MainActor` holding `windowExpiresAt: Date?`. Observes three revocation triggers and exposes `isInWindow: Bool`. NOT persisted.
- **Toast UI implementation:** Reuse the transient-overlay pattern from Phase 6's `TransientToastOverlay`. Apple frameworks only.
- **`LAContext` reuse vs new context per send:** Up to planner: (a) hold one `LAContext` with `touchIDAuthenticationAllowableReuseDuration = 120`, or (b) skip `LAContext.evaluatePolicy` entirely during window. Recommend (b) unless security review surfaces a concrete reason.
- **Background revocation timing:** `didEnterBackgroundNotification` fires when app loses foreground. No grace period.
- **Where to mint the window:** Inside `CodeApprovalView.approveAndSend` immediately after `BiometricAuthManager.shared.authenticate` returns `true`, before `RelayClient.shared.sendEncryptedCode`. Conditional on `SyncPreference`-style enable check (D-17).
- **Where the silent path lives:** `RelayClient.handleMessage` `default:` branch (around line 161-164). If `isInWindow`, resolve account, generate code, send, fire toast. Otherwise fall through to existing `pendingCodeRequest = request`.
- **Account resolution for silent send:** Use same matching logic as `CodeApprovalView.onAppear` (exact issuer+label → domain-match single-result → single-account fallback). If multiple matches AND no exact issuer+label, silent path MUST defer to FaceID (re-prompt).
- **Toast text when issuer is empty:** Use the matched account's issuer for the toast.

### Deferred Ideas (OUT OF SCOPE)

- Per-origin / per-account scoped tokens — deferred to v2
- "Lock now" button — explicitly rejected
- Configurable TTL — fixed at 2 min
- Sliding-window TTL — rejected (D-03)
- Active-tokens UI — not needed for single global window
- `LAContext.touchIDAuthenticationAllowableReuseDuration`-based approach — deferred unless security reviewer requires
- Origin-strength upgrades (eTLD+1, full-URL scoping, tabId binding) — only if per-origin scope reintroduced
- Persisting window across app launches — explicitly NOT done
- Requirements registration — planner registers `FIDO-01` through `FIDO-NN`
</user_constraints>

<phase_requirements>
## Phase Requirements

Phase 7 has no pre-registered REQ-IDs in REQUIREMENTS.md. The research below suggests a complete `FIDO-01..FIDO-19` breakdown below covering all 17 decisions in CONTEXT.md. The **planner** is responsible for registering these IDs; the researcher only proposes them.

| Proposed ID | Description | Testable Behavior | Sources in Research |
|----|-------------|-------------------|---------------------|
| FIDO-01 | `TrustWindowManager.shared` singleton on `@MainActor` exposes `isInWindow: Bool` derived from `windowExpiresAt: Date?`. Not persisted to Keychain/UserDefaults — transient reset on app launch. | Unit: after `init()`, `isInWindow == false` and `windowExpiresAt == nil`. | Integration Points, § Standard Stack |
| FIDO-02 | `TrustWindowManager.mint()` sets `windowExpiresAt = Date().addingTimeInterval(120)` when `TrustWindowPreference.isEnabled`. | Unit: after `mint()`, `isInWindow == true`; `windowExpiresAt - Date() ≈ 120s (±50ms)`. | Pattern 1, § Runtime State Inventory |
| FIDO-03 | When `TrustWindowPreference.isEnabled == false`, `mint()` is a no-op and `isInWindow` remains `false`. | Unit: `TrustWindowPreference.setEnabled(false); mgr.mint(); XCTAssertFalse(mgr.isInWindow)`. | D-17 |
| FIDO-04 | TTL is fixed-from-mint: calling `mint()` twice within 2 minutes replaces the expiry (fresh 2 min), not extended beyond a second mint. | Unit: mint, advance 60s (via injected clock), mint again, verify expiry is now `t2+120s` not `t0+120s`. | D-03, D-04 |
| FIDO-05 | `TrustWindowManager.isInWindow` returns `false` automatically after `windowExpiresAt` passes. | Unit with injected clock: mint, advance 121s, assert `isInWindow == false`. | D-07 |
| FIDO-06 | Receiving `UIApplication.didEnterBackgroundNotification` revokes the window (`windowExpiresAt = nil`). | Unit: mint, post notification, assert `isInWindow == false`. Integration: background the app in UI test, assert window gone on return. | D-05 |
| FIDO-07 | Observing `ICloudStateObserver.shared.$didAccountChange == true` revokes the window. | Unit: mint, inject `_simulateIdentityChange(newToken: nil)`, assert `isInWindow == false`. | D-06 |
| FIDO-08 | `CodeApprovalView.approveAndSend` calls `TrustWindowManager.shared.mint()` iff `BiometricAuthManager.authenticate` returned `true` AND `TrustWindowPreference.isEnabled`. | Unit (extract mint-gating logic to a testable helper OR snapshot-grep the source). | D-01, Integration Points |
| FIDO-09 | `RelayClient.handleMessage` silent-send branch: when `isInWindow == true` AND account resolution succeeds unambiguously, generates code, calls `sendEncryptedCode`, fires toast, and does NOT set `pendingCodeRequest`. | Unit: mock `sharedKey`, inject a decrypted CodeRequest, call branch, assert `sendEncryptedCode` called and `pendingCodeRequest == nil`. | D-09, D-11 |
| FIDO-10 | Silent-send falls back to FaceID (normal `pendingCodeRequest = request` flow) when multiple accounts match domain AND no exact issuer+label match. | Unit: two domain-matching accounts + empty issuer/label; assert `pendingCodeRequest` SET, `sendEncryptedCode` NOT called. | Pattern 2 (Account Resolution) |
| FIDO-11 | Toast emits "Code sent for <issuer>" using matched account issuer; "Code sent" when issuer is empty/unknown. | Unit: toast message string for matched account vs no-match. | D-09 |
| FIDO-12 | Toast self-dismisses after 2 seconds. | Unit: publish toast, advance 2.1s via injected clock, assert `pendingToast == nil`. | Pattern 3 (Toast) |
| FIDO-13 | `CodeApprovalView.startAutoRefresh(account:)` is deleted and no caller remains. | Grep: `rg "startAutoRefresh" -- App/ Shared/` returns zero matches (except tests of the removal). | D-12 |
| FIDO-14 | A new `TrustWindowPreference` enum mirrors `SyncPreference` shape (UserDefaults-backed Bool, `bootstrap`, `setEnabled`, default value). | Unit: bootstrap on first launch sets default `true` for new and existing users. | D-16 |
| FIDO-15 | SettingsView exposes a toggle "Allow 2-minute trust window after FaceID" bound to `TrustWindowPreference.isEnabled`. | Unit/grep: toggle literal present in SettingsView; toggle flip updates the preference. | D-16, Settings integration |
| FIDO-16 | On fresh install, `TrustWindowPreference.bootstrap` defaults toggle to **ON**. | Unit: clear UserDefaults, call bootstrap, assert `isEnabled == true`. | D-16 (new users default ON) |
| FIDO-17 | Window does NOT persist across app launches. | Integration: mint → force-quit (via test harness) → relaunch → assert `isInWindow == false`. | D-05 (background revokes) + Claude's Discretion ("NOT persisted") |
| FIDO-18 | Toast remains visible above/after the `CodeApprovalView` sheet is dismissed from the mint moment. | UI test / manual QA: mint flow → approve → sheet dismisses → toast is still visible until its 2s auto-dismiss. | D-10, Pattern 3 |
| FIDO-19 | Chrome extension source (`background.ts`) is NOT modified. Origin continues to travel in `CodeRequest.domain`; no new fields added. | Grep: diff between Phase 7 branch and pre-Phase-7 on `extension/` is empty. | D-15, canonical-refs |

Planner should refine wording and merge/split as appropriate. FIDO-13 and FIDO-19 are negative-requirements (things that MUST NOT exist or change) — plan-checker should confirm the phrasing can be verified.
</phase_requirements>

## Summary

Phase 7 is a small-surface, high-leverage feature: a `@MainActor` singleton (`TrustWindowManager`) plus a UserDefaults-backed toggle (`TrustWindowPreference`), a SwiftUI overlay (`TrustWindowToastOverlay` — or a reuse of `TransientToastOverlay`), and six narrowly-scoped edits to existing files (`CodeApprovalView`, `RelayClient`, `ContentView`, `SettingsView`, `KeyAuthApp`). No new Apple APIs beyond what Phase 1-6 already introduced. Zero new third-party dependencies (project constraint).

The research confirms:
1. **`touchIDAuthenticationAllowableReuseDuration` is a Touch ID-era property tied to recent device-unlock events**, not a pure "reuse any in-app authentication for N seconds" mechanism. Option (b) from CONTEXT.md Claude's Discretion — skip `LAContext.evaluatePolicy` entirely during the window — is the correct recommendation. [VERIFIED: Microsoft Learn LAContext docs; Apple forum thread 121149]
2. **`UIApplication.didEnterBackgroundNotification` fires on a full background transition (app switcher, lock screen, switch to another app) but NOT on Control Center or Notification Center swipes.** This is the correct trigger for D-05 — opening Control Center should NOT revoke an in-flight window. [VERIFIED: Apple developer forum thread 685317]
3. **Existing `TransientToastOverlay` (`App/Views/TransientToastOverlay.swift`) is a reusable capsule primitive** already in the KeyAuth app target, deferred in Phase 6 because it was never mounted. Phase 7 gets to both *mount* it AND extend it for the new "Code sent for X" toast. [VERIFIED: file read]
4. **Existing test infrastructure** (`KeyAuthTests` target with `MockKeychain`, `AccountFixtures`, full `@testable import KeyAuth` flow) is ready to absorb Phase 7 unit tests without new project-file surgery. [VERIFIED: KeyAuthTests/ listing + xcodeproj grep]
5. **A subtle SwiftUI pitfall applies:** `.sheet` modifiers cover overlays applied to parent views. For D-10 ("toast visible after sheet dismisses") the overlay must be on `ContentView` body at the level where the sheet is ALSO attached — the sheet will cover it while presented, then reveal it when dismissed. The first-request flow naturally sequences "mint → sheet dismisses (onComplete) → subsequent silent sends show toast above now-empty ContentView" so this matches the requirement without extra work. [VERIFIED: simplykyra.com on SwiftUI overlay-sheet interaction]

**Primary recommendation:** Implement as a three-file core (`Shared/TrustWindowManager.swift`, `Shared/TrustWindowPreference.swift`, `App/Views/TrustWindowToastOverlay.swift` — or use existing `TransientToastOverlay` with a new driver property) plus minimal surgical edits to five existing files. Use a `Timer.scheduledTimer` on `@MainActor` for expiry callback (matches existing `RelayClient` Timer pattern). Skip `LAContext` reuse entirely. Mount the overlay on `ContentView` at the same hierarchy level as `.sheet(item: $relayClient.pendingCodeRequest)`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Trust window mint/expiry state | iOS App (main target) | — | Purely in-memory, drives UI; has no business anywhere else |
| Expiry timer | iOS App | — | `Timer` on `@MainActor` for main-thread UI updates |
| Revocation on background | iOS App | — | `NotificationCenter` observer on `UIApplication.didEnterBackgroundNotification` in `KeyAuthApp` |
| Revocation on iCloud account change | iOS App | — | Reuses Phase 6 `ICloudStateObserver` Combine publisher |
| Silent-send branch | iOS App (`RelayClient`) | — | Decision point happens at WebSocket receive-loop; `RelayClient` already lives on `@MainActor` |
| Silent-send code generation | iOS App (`TOTPGenerator`) | — | Same generator used by `CodeApprovalView` |
| Silent-send toast UI | iOS App (SwiftUI view hierarchy) | — | Overlay on `ContentView` |
| Persistent toggle state | iOS App (`UserDefaults.standard`) | — | Per-device UX state (NOT iCloud-synced; matches `SyncPreference` decision) |
| Origin/domain awareness | Chrome Extension (no change) | iOS App (pass-through) | Extension already captures origin; iOS only reads it for display and domain-match account resolution |
| Keyboard extension | Out of scope | — | Phase 7 does not touch the keyboard target |
| Relay server | Out of scope | — | No protocol changes; existing `code_response` envelope suffices |

**Tier-correctness sanity check:** The capability to "decide whether FaceID is needed" is correctly placed in the iOS App. Placing it in the Chrome extension or relay would leak trust state off-device — which contradicts PROJECT.md's core value (secrets / auth state on the phone). Placing it in the keyboard extension is wrong because the keyboard does not participate in the relay flow.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Foundation` | iOS 16 SDK | `Date`, `Timer`, `NotificationCenter`, `UserDefaults` | Always available [VERIFIED: project.yml iOS 16 target] |
| `Combine` | iOS 16 SDK | `@Published`, `.sink` subscription to `ICloudStateObserver.$didAccountChange` | Already used in `AccountStore`, `ICloudStateObserver`, `MigrationCoordinator` [VERIFIED: `grep Combine Shared/`] |
| `SwiftUI` | iOS 16 SDK | `.overlay(alignment:)`, `.transition(.move(edge:).combined(with: .opacity))` for toast | Project standard for the app target [CITED: project.yml `platform: iOS`] |
| `LocalAuthentication` | iOS 16 SDK | `BiometricAuthManager` already uses `LAContext`; Phase 7 REUSES, does not extend | Existing `BiometricAuthManager.shared.authenticate(reason:) async -> Bool` [VERIFIED: `Shared/BiometricAuthManager.swift`] |
| `UIKit` (via SwiftUI) | iOS 16 SDK | `UIApplication.didEnterBackgroundNotification` NotificationCenter name | Already used in `KeyAuthApp.swift` §65-72 for `isUnlocked = false` [VERIFIED: `App/KeyAuthApp.swift:66`] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `XCTest` | iOS 16 SDK | Unit tests for `TrustWindowManager`, `TrustWindowPreference`, account-resolution helper | For all FIDO-NN `Unit:` assertions. Already wired in `KeyAuthTests` target with `@testable import KeyAuth`. [VERIFIED: `KeyAuthTests/KeyAuthTests.swift`] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Timer.scheduledTimer` on `@MainActor` for expiry | `Task.sleep(nanoseconds:)` in a stored `Task<Void, Never>` | `Task.sleep` is cancellable and composes cleanly with Swift concurrency, but re-mints require cancelling and restarting a Task. Timer invalidation is idiomatic in this codebase (see `RelayClient.reconnectTimer`, `RelayClient.keepaliveTimer`). Prefer Timer for consistency. |
| `Timer.scheduledTimer` | `DispatchSourceTimer` | `DispatchSourceTimer` has ~10ms vs ~50ms precision but requires explicit strong retention and doesn't integrate with the main RunLoop. For a 2-minute window where ±50ms is invisible to users, Timer wins on simplicity. |
| `Timer` scheduled callback | Pure `Date` arithmetic on every access | "Lazy expiry" (check `Date() >= windowExpiresAt` on each `isInWindow` read) avoids any Timer, but: (a) prevents firing side effects at expiry (like dismissing a visible toast), (b) provides no way to proactively cancel a pending toast if window expires mid-toast. Recommend hybrid: lazy check on every `isInWindow` read (so we never silent-send past expiry even if Timer is slightly late) AND a scheduled Timer callback for proactive state cleanup. |
| New custom `TrustWindowToastOverlay` | Reuse existing `TransientToastOverlay` | `TransientToastOverlay` uses 3s auto-dismiss hardcoded via `DispatchQueue.main.asyncAfter`; D-09 asks for "~2 seconds." Tradeoff: (a) keep the component generic (add `duration: TimeInterval = 3.0` parameter, pass 2.0) — reusable, 1-line change, (b) clone the component with 2s baked in — decoupled but 2x the code. Recommend (a) — parameterize the duration. Phase 6 never mounted the overlay so there's zero regression risk to the parameterization. |
| `@Published var pendingToast: ToastMessage?` | Combine subject with `.debounce` | Debounce is only useful if toast-flood coalescing is needed. With D-02 global scope + single extension + human-scale request cadence, flood is impossible within 2min. Recommend plain `@Published`. |

**Installation:**
No new packages. All frameworks already linked via the existing `KeyAuth` app target.

**Version verification:** Not applicable — no external libraries. Apple framework availability verified against `project.yml` `deploymentTarget: iOS: "16.0"`.

## Architecture Patterns

### System Architecture Diagram

```
  Chrome Ext ─── encrypted CodeRequest (domain, issuer=?, label=?) ───▶  Relay ──▶  APNs push
                                                                                       │
                                                                                       ▼
                                                                          ┌────────────────────────┐
                                                                          │ iOS: RelayClient       │
                                                                          │ .handleMessage default:│
                                                                          └──────────┬─────────────┘
                                                                                     │ decrypted CodeRequest
                                                                                     ▼
                                                                          ┌────────────────────────┐
                                                                          │ TrustWindowManager     │
                                                                          │ .isInWindow ?          │
                                                                          └────┬────────────┬──────┘
                                                                        true  │            │  false
                                                                              ▼            ▼
                                                ┌────────────────────────────────┐   ┌────────────────────────────┐
                                                │ Account resolution (helper)    │   │ pendingCodeRequest = req   │
                                                │ exact issuer+label             │   │   (triggers SwiftUI sheet) │
                                                │   → single domain match        │   └──────────┬─────────────────┘
                                                │   → single-account fallback    │              │
                                                │   → AMBIGUOUS? defer to FaceID │              │ user taps Approve
                                                └────┬──────────────────────┬────┘              ▼
                                                     │ resolved             │ ambiguous   BiometricAuthManager
                                                     ▼                      └───────▶    .authenticate() → true
                                           ┌───────────────────┐                          │
                                           │ TOTPGenerator     │                          ▼
                                           │ .generate(acct)   │                   TrustWindowManager.mint()
                                           └──────────┬────────┘                          │
                                                      ▼                                   ▼
                                           ┌───────────────────┐                   Schedule 120s Timer
                                           │ RelayClient       │                          │
                                           │ .sendEncryptedCode│                          ▼
                                           └──────────┬────────┘               ┌──────────────────────────┐
                                                      │                        │ Revocation observers     │
                                                      ▼                        │ (wired once in KeyAuthApp)│
                                           ┌───────────────────┐               │ • didEnterBackground     │
                                           │ TrustWindowMgr    │               │ • $didAccountChange      │
                                           │ .pendingToast set │               │ • Timer fires            │
                                           │ "Code sent for X" │               └──────────────┬───────────┘
                                           └──────────┬────────┘                              │
                                                      ▼                                       ▼
                                                TransientToastOverlay                 TrustWindowManager
                                                (mounted on ContentView,              .revoke()  → windowExpiresAt=nil
                                                 auto-dismiss 2s)
```

### Recommended Project Structure

```
Shared/
├── TrustWindowManager.swift     # NEW — @MainActor singleton; windowExpiresAt; mint/revoke; Timer; toast publisher
├── TrustWindowPreference.swift  # NEW — enum (mirrors SyncPreference shape)
├── AccountResolver.swift        # NEW (optional) — shared account-matching helper extracted from CodeApprovalView
├── RelayClient.swift            # EDITED — default: branch gains silent-send path
├── BiometricAuthManager.swift   # UNCHANGED
└── ... (Phase 6 files unchanged)

App/
├── KeyAuthApp.swift             # EDITED — instantiate TrustWindowManager as @StateObject; wire ICloudStateObserver subscription
└── Views/
    ├── ContentView.swift        # EDITED — .overlay(alignment: .top) for toast
    ├── CodeApprovalView.swift   # EDITED — startAutoRefresh deleted; mint() added after authenticate success
    ├── SettingsView.swift       # EDITED — add new toggle row
    └── TransientToastOverlay.swift  # EDITED — parameterize `duration`
```

### Pattern 1: `@MainActor` Singleton with `@Published` State + Injected Clock

**What:** Single-instance state holder driving SwiftUI views. Accept an injectable clock to make expiry tests deterministic.

**When to use:** For `TrustWindowManager` (FIDO-01..FIDO-07).

**Example:**
```swift
// Source: established codebase pattern — BiometricAuthManager, RelayClient, PairingStore, AccountStore
// File: Shared/TrustWindowManager.swift (NEW)
import Foundation
import Combine
import UIKit

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class TrustWindowManager: ObservableObject {
    static let shared = TrustWindowManager()

    @Published private(set) var windowExpiresAt: Date?
    @Published var pendingToast: ToastMessage?

    /// Use `Date()` by default; tests can inject a closure to advance time.
    var now: () -> Date = { Date() }
    private var expiryTimer: Timer?
    private var toastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Derived; always checks `now()` so callers never act on a stale window even if the Timer is late.
    var isInWindow: Bool {
        guard let exp = windowExpiresAt else { return false }
        return now() < exp
    }

    private init() {}  // must call bootstrap() from KeyAuthApp.onAppear

    /// Idempotent — safe to call many times. Wires revocation observers.
    func bootstrap() {
        // Background revocation (D-05)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.revoke() } }
            .store(in: &cancellables)

        // iCloud account change (D-06)
        ICloudStateObserver.shared.$didAccountChange
            .sink { [weak self] changed in
                guard changed else { return }
                Task { @MainActor in self?.revoke() }
            }
            .store(in: &cancellables)
    }

    /// D-01/D-02/D-03/D-17 — mint a fresh 2-min window iff the user allows it.
    func mint(ttl: TimeInterval = 120) {
        guard TrustWindowPreference.isEnabled else { return }
        expiryTimer?.invalidate()
        let expiry = now().addingTimeInterval(ttl)
        windowExpiresAt = expiry
        expiryTimer = Timer.scheduledTimer(withTimeInterval: ttl, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.revoke() }
        }
    }

    func revoke() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        windowExpiresAt = nil
    }

    /// D-09 — drive the SwiftUI overlay. Auto-dismiss in ~2s.
    func showToast(for issuer: String) {
        let text = issuer.isEmpty ? "Code sent" : "Code sent for \(issuer)"
        pendingToast = ToastMessage(text: text)
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pendingToast = nil }
        }
    }
}
```

**Notes on Combine subscription lifecycle (Claude's Discretion #3):**
- The existing Phase 6 pattern is to observe `ICloudStateObserver.$didAccountChange` via a `.sink` — but currently `SettingsView` reads `icloud.didAccountChange` synchronously in its computed property (not via Combine). For `TrustWindowManager`, the subscription must be established once at `bootstrap()` time (called from `KeyAuthApp.onAppear`). Storing the `AnyCancellable` in `cancellables: Set<AnyCancellable>` keeps it alive for the singleton's lifetime — no leak, no early cancel.
- `bootstrap()` is idempotent: calling it twice creates two subscriptions. Use a guard flag (`didBootstrap`) if `onAppear` can fire more than once in edge cases. Mirror the `didBootstrapSyncPreference` pattern in `KeyAuthApp`.

### Pattern 2: Account Resolution Helper

**What:** Extract the account-matching logic from `CodeApprovalView.onAppear` (lines 147-158) to a shared function so the silent-send branch uses identical semantics.

**When to use:** In both `CodeApprovalView.onAppear` and `RelayClient.handleMessage` silent-send branch (FIDO-10).

**Example:**
```swift
// Source: extracted from App/Views/CodeApprovalView.swift lines 147-158
// File: Shared/AccountResolver.swift (NEW) OR Shared/AccountStore.swift (extension)
extension AccountStore {
    /// Deterministic account resolution for a CodeRequest.
    /// Returns nil ONLY when ambiguous (multiple matches AND no exact issuer+label).
    /// Semantics mirror CodeApprovalView.onAppear.
    func resolve(for request: CodeRequest) -> Account? {
        // 1. Exact issuer+label match (when present)
        if !request.issuer.isEmpty || !request.label.isEmpty {
            return accounts.first { $0.issuer == request.issuer && $0.label == request.label }
        }
        // 2. Domain-based matching (only when issuer/label absent)
        if let domain = request.domain, !domain.isEmpty {
            let domainLower = domain.lowercased()
            let matched = accounts.filter { account in
                let issuerLower = account.issuer.lowercased()
                return domainLower.contains(issuerLower)
                    || issuerLower.contains(domainLower.replacingOccurrences(of: ".com", with: ""))
            }
            if matched.count == 1 { return matched[0] }
            if matched.count > 1 { return nil } // AMBIGUOUS → silent path defers to FaceID
        }
        // 3. Single-account fallback
        if accounts.count == 1 { return accounts[0] }
        return nil  // AMBIGUOUS or empty → silent path defers to FaceID
    }
}
```

**Silent-send contract (CRITICAL for planner):** `RelayClient.handleMessage` MUST check `resolve(for: request)` and fall through to the existing `pendingCodeRequest = request` branch when `resolve` returns `nil`. This is **NOT** an error path — it is the sanctioned re-prompt behavior from CONTEXT.md Claude's Discretion:
> *"If multiple matches AND no exact issuer+label, the silent path MUST defer to FaceID (re-prompt)."*

### Pattern 3: SwiftUI Transient Toast via Existing `TransientToastOverlay`

**What:** Parameterize the existing `TransientToastOverlay` with a `duration` arg (default 3.0, pass 2.0 for Phase 7), drive it from `TrustWindowManager.pendingToast`, mount on `ContentView`.

**When to use:** In `ContentView.body` body, same hierarchy level as the `.sheet(item: $relayClient.pendingCodeRequest)` modifier.

**Example:**
```swift
// Source: existing App/Views/TransientToastOverlay.swift (modified to accept duration)
// and App/Views/ContentView.swift (add overlay)

// MODIFIED (1-line): App/Views/TransientToastOverlay.swift
struct TransientToastOverlay: View {
    let message: String
    let icon: String
    let iconColor: Color
    let duration: Double = 3.0  // NEW default — callers can pass 2.0 for Phase 7
    @Binding var isPresented: Bool
    // ... existing body unchanged; use `duration` in asyncAfter
}

// NEW on ContentView.body: overlay driven by TrustWindowManager
// File: App/Views/ContentView.swift (add @EnvironmentObject + overlay)
@EnvironmentObject var trustWindow: TrustWindowManager  // NEW

// ... in body, at the same level as the existing .sheet modifier:
.overlay(alignment: .top) {
    if let toast = trustWindow.pendingToast {
        HStack(spacing: 8) {
            Image(systemName: "paperplane.fill").foregroundStyle(.blue)
            Text(toast.text).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
.animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)
```

**Sheet-overlay interaction (Claude's Discretion #2):**
- While `CodeApprovalView` sheet is presented, the toast will be OBSCURED by the sheet — this is standard SwiftUI behavior. [CITED: simplykyra.com/blog/swiftui-overlays-and-their-issue-with-sheets]
- In practice this never matters for D-11: silent sends happen ONLY when the window is active, meaning we've already gone through the sheet once and it's dismissed. The toast pattern is purely post-sheet.
- For the mint request itself (when sheet IS visible), toast is NOT fired (mint flow uses the existing "Sent" confirmation inside the sheet at `CodeApprovalView.swift:116-120`). So the sheet-covering behavior is benign.
- If a future requirement asks for toast-above-sheet, the fix is to ALSO mount the overlay on the sheet content view — documented for completeness.

### Anti-Patterns to Avoid

- **Persisting `windowExpiresAt` to Keychain or UserDefaults.** CONTEXT.md Deferred Ideas explicitly forbids this. Persisted window would survive force-quit, violating D-17 enforcement by the background notification.
- **Adding a "Lock now" button.** User rejected it.
- **Per-origin or per-account scoping for v1.** Deferred (D-02, D-14, D-15).
- **Setting `LAContext.touchIDAuthenticationAllowableReuseDuration`.** The property ties reuse to the device-unlock event, not to arbitrary in-app authentications. It would conflate "user unlocked phone recently" with "user approved a code request recently" — not what we want. See Common Pitfall 1.
- **Extending the window on each silent send (sliding TTL).** Explicitly rejected by D-03.
- **Firing the toast BEFORE `RelayClient.sendEncryptedCode` succeeds.** If the send fails, we'd be lying. Fire the toast after the send callback reports no error (or accept that the encode failed and show nothing — see Open Question #3 below).
- **Extracting the matching logic from `CodeApprovalView.onAppear` without updating the onAppear call site too.** If you refactor into `AccountResolver`, update BOTH call sites in the same task to prevent semantic drift.
- **Subscribing to `ICloudStateObserver.$didAccountChange` inside a SwiftUI `View`.** Views are recreated on every state change; subscriptions must live in the singleton or in `KeyAuthApp` @StateObjects.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toast overlay | Your own capsule + animation | Existing `TransientToastOverlay` (parameterize `duration`) | Already in the app target, reduce-motion-aware, 42 LOC; Phase 6 deferred its placement for exactly this moment |
| 2-minute countdown | `while true { sleep; check }` loop | `Timer.scheduledTimer(withTimeInterval: 120, repeats: false)` invalidated on re-mint/revoke | Matches `RelayClient.reconnectTimer` pattern; integrates with main RunLoop for UI side effects |
| Combine subscription storage | Manual ivar + invalidate | `Set<AnyCancellable>` + `.store(in:)` | Idiomatic; auto-releases on deinit |
| Account matching algorithm | Reimplement from scratch in `RelayClient` | Extract `CodeApprovalView.onAppear` logic into `AccountStore.resolve(for:)` extension | Single source of truth prevents semantic drift between FaceID and silent paths |
| Background-notification plumbing | New `AppDelegate` methods | Extend existing `KeyAuthApp.onReceive(...didEnterBackgroundNotification)` (already present at `App/KeyAuthApp.swift:65-72`) | Zero new surface area; one extra line inside the closure |
| UserDefaults-backed boolean toggle | Write the wrapper by hand | Clone `Shared/SyncPreference.swift` shape verbatim; rename key, `bootstrap`, `setEnabled` | Established Phase 6 pattern; tests already exist for it |
| iCloud-account-change observer | Wire `NSUbiquityIdentityDidChange` again | Observe `ICloudStateObserver.shared.$didAccountChange` | Phase 6 is already the canonical source; D-06 says so explicitly |

**Key insight:** Phase 7 adds roughly 200 LOC of production code and 150 LOC of tests. 80% of the complexity is in sequencing (when to mint, when to revoke, when to fire toast, when to defer to FaceID). Every piece of state except the new `TrustWindowPreference` toggle is transient — no migrations, no schema, no new Keychain surface.

## Runtime State Inventory

> Phase 7 is a greenfield feature, not a rename/migration. Still filling in the inventory out of paranoia, because the feature *deletes* an existing behavior (`CodeApprovalView.startAutoRefresh`).

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None.** `TrustWindowManager` state is transient. `TrustWindowPreference` lives in `UserDefaults.standard` (same as `SyncPreference`) — one new key `trust_window_enabled`, no data migration since the default is `true` and absence-of-key is treated as "use default" by `bootstrap()`. | None |
| Live service config | **None.** No relay-server, extension, or APNs config changes. Extension's `request_code` payload format is unchanged. | None |
| OS-registered state | **None.** No new background tasks, no notification categories, no launchd/plist changes. The existing `UIApplication.didEnterBackgroundNotification` is already observed. | None |
| Secrets / env vars | **None.** No new entitlements, no new Keychain access groups. `BiometricAuthManager` is reused as-is. | None |
| Build artifacts / installed packages | **Xcode project file needs three new Swift sources registered** in the `KeyAuth` app target (NOT the `KeyAuthKeyboard` target — the keyboard does not use `TrustWindowManager`): `Shared/TrustWindowManager.swift`, `Shared/TrustWindowPreference.swift`, optional `Shared/AccountResolver.swift`. Also register matching `KeyAuthTests/TrustWindowManagerTests.swift` etc. in the `KeyAuthTests` target. | Follow the Phase 6 Ruby `xcodeproj` pattern (STATE.md line 108: "Ruby xcodeproj gem used for all project.pbxproj edits") — planner should use the same mechanism. |

**Existing behavior removed by D-12:** `CodeApprovalView.startAutoRefresh(account:)` at `App/Views/CodeApprovalView.swift:205-240` is deleted. It does not own any persistent state (the only state is a local `lastSentCode` string). Removing the call site at line 198 and the function definition is sufficient; no cleanup beyond the grep-check in FIDO-13.

## Common Pitfalls

### Pitfall 1: Misinterpreting `touchIDAuthenticationAllowableReuseDuration`
**What goes wrong:** A well-intentioned planner reads "5-minute reuse duration" in the ROADMAP description and wires a long-lived `LAContext` with `touchIDAuthenticationAllowableReuseDuration = 120` expecting that `evaluatePolicy` will silently succeed on subsequent calls within 2 minutes.
**Why it happens:** The property's docstring is misleadingly close to our desired behavior ("the time after a successful Touch ID authentication for which a user will not be challenged for another"). In practice, its original purpose was narrower: avoid re-prompting when the user JUST unlocked the device with biometric. [CITED: Apple developer forum discussion of the property's in-app vs device-unlock semantics, e.g., [forums.developer.apple.com/forums/thread/121149]] Behavior across iOS versions has been inconsistent (GitHub issue square/Valet#167 documents developers getting unexpected prompts even within the reuse window).
**How to avoid:** Use option (b) from CONTEXT.md — skip `LAContext.evaluatePolicy` entirely during the window. `TrustWindowManager.isInWindow` is the gate. `LAContext` is used only on the FIRST request (where FaceID is genuinely needed), via the existing `BiometricAuthManager.authenticate()` call.
**Warning signs:** If a planner-task mentions "reuse the LAContext" or "set allowableReuseDuration = 120" — push back.

### Pitfall 2: `didEnterBackgroundNotification` confusion with Control Center / Notification Center
**What goes wrong:** Planner writes a test that opens Control Center from the iOS simulator and expects the window to revoke. The test fails, planner assumes the observer is broken.
**Why it happens:** `UIApplication.didEnterBackgroundNotification` fires ONLY on a true background transition (app switcher, lock screen, switching to another app). Control Center and Notification Center only transition the app to `.inactive` (`willResignActiveNotification` fires, but NOT `didEnterBackgroundNotification`). [VERIFIED: Apple forums thread 685317]
**How to avoid:** Document this explicitly in the PLAN.md. For QA: window should NOT revoke on Control-Center swipe (deliberate — user is still actively using the phone). For revocation tests, use the app-switcher or lock-screen paths.
**Warning signs:** Test failures on "open Control Center, expect revocation." That's a test-expectation bug, not a code bug.

### Pitfall 3: Sheet covering the overlay during mint flow
**What goes wrong:** Planner writes a test expecting the "Code sent for X" toast to appear WHILE `CodeApprovalView` is still visible.
**Why it happens:** SwiftUI `.sheet` presentation draws above `.overlay` modifiers applied to parent views. [CITED: simplykyra.com/blog/swiftui-overlays-and-their-issue-with-sheets]
**How to avoid:** Phase 7 design explicitly separates the two flows. Mint happens inside the sheet (user sees the existing "Sent" `Label`, line 116-120 of `CodeApprovalView.swift`). Silent sends happen after the sheet is dismissed. Toast is only fired in the silent-send branch. No scenario calls for toast-over-sheet.
**Warning signs:** A requirement like "toast visible during approval sheet" — push back; that's not the spec.

### Pitfall 4: `@Published` toast overwrite during rapid silent sends
**What goes wrong:** Extension fires two `request_code` envelopes 100ms apart within the window. First silent send emits toast; before the 2s timer fires, second silent send emits another toast that replaces the first. User sees only the second issuer's name (or sees a flicker).
**Why it happens:** Each silent send calls `showToast(for:)`, which reassigns `pendingToast`. If Account A's toast is still on screen and Account B's arrives, the user may miss A.
**How to avoid:** The `toastTimer?.invalidate()` in `showToast` ensures only the latest toast's 2s timer runs, but the `pendingToast` value flips atomically — no flicker beyond SwiftUI's own transition. For v1, acceptance is: **users see ALL silent-send toasts, even if rapid fire, with latest-wins replacement.** This matches the user's clear framing ("short, declarative, names the issuer"). If real usage surfaces a "toast queue" need, defer to v2.
**Warning signs:** If the planner proposes a queue/stack of pending toasts, push back — not in scope.

### Pitfall 5: Silent send firing before `sendEncryptedCode` actually succeeds
**What goes wrong:** `sendEncryptedCode` uses `webSocketTask?.send(...)` with a callback-based error handler (RelayClient.swift line 84-88). If the WebSocket is in a bad state, the send may silently fail. We showed a toast but sent nothing.
**Why it happens:** The existing `sendEncryptedCode` is fire-and-forget — it does not `await` or expose success/failure to callers.
**How to avoid:** For v1, accept the trade-off — toast-then-send mirrors today's `CodeApprovalView.approveAndSend` which also shows "Sent" before confirming. If the send fails, the extension eventually times out and re-requests, re-entering the flow. Alternative: pass a completion handler through `sendEncryptedCode` and fire the toast inside that — cleaner but larger edit. Recommend v1 stays with the existing pattern; file a todo for v2.
**Warning signs:** A planner change to `sendEncryptedCode`'s signature — flag as scope creep unless explicitly justified.

### Pitfall 6: Forgetting the `SyncPreference`-style bootstrap
**What goes wrong:** Planner ships `TrustWindowPreference` that reads raw `UserDefaults.standard.bool(forKey:)` without calling `bootstrap()`. Since `bool(forKey:)` returns `false` for missing keys, toggle defaults to OFF — violating D-16.
**Why it happens:** Swift's `Bool`-from-missing-key is `false`, but the spec says default is ON.
**How to avoid:** Mirror `SyncPreference.bootstrap(existingAccountCount:)` — use a `hasLaunchedBeforeTrustWindow` sentinel key; on first launch, explicitly set `trust_window_enabled = true`. Call from `KeyAuthApp.onAppear`, guarded by a `didBootstrapTrustWindowPreference` flag (same pattern as `didBootstrapSyncPreference` at `App/KeyAuthApp.swift:13`).
**Warning signs:** A `TrustWindowPreference.isEnabled` getter without a `bootstrap()` peer.

### Pitfall 7: Running the expiry Timer when app is in background (iOS suspends it)
**What goes wrong:** Window minted → app backgrounded → Timer never fires because iOS suspended the process. App resumes 10 minutes later — `isInWindow` still true because `windowExpiresAt` is set to a past time.
**Why it happens:** `Timer.scheduledTimer` is suspended with the app when the main RunLoop pauses.
**How to avoid:** The hybrid `isInWindow` getter — `now() < exp` — is the belt-and-suspenders fix. Even if the Timer is late, the lazy check prevents silent-sending past expiry. Additionally, D-05 says background revokes the window anyway, so `didEnterBackgroundNotification` fires and `revoke()` runs BEFORE the Timer matters. Belt-and-suspenders-and-third-belt.
**Warning signs:** A planner relying solely on the Timer for expiry semantics without the lazy `now() < exp` check.

### Pitfall 8: `@StateObject` of a singleton in `KeyAuthApp`
**What goes wrong:** Planner writes `@StateObject private var trustWindow = TrustWindowManager.shared`. This works but is subtly unidiomatic — `@StateObject` is for objects the view OWNS. The singleton owns itself.
**Why it happens:** Mimicking `@StateObject private var pairingStore = PairingStore.shared` from `KeyAuthApp.swift:8`.
**How to avoid:** It actually works fine — SwiftUI keeps a reference but doesn't re-init. The existing code does this with `PairingStore.shared`, `ICloudStateObserver.shared`, etc. Use the same pattern for consistency: `@StateObject private var trustWindow = TrustWindowManager.shared`. Inject as `@EnvironmentObject` into `ContentView`.
**Warning signs:** Planner objects to the pattern. Point to `KeyAuthApp.swift:7-9` (existing precedent) and move on.

## Code Examples

### Mint on FaceID success

```swift
// Source: App/Views/CodeApprovalView.swift:182-203 (existing approveAndSend)
// MODIFICATION: replace startAutoRefresh call with mint()
@MainActor
private func approveAndSend() async {
    // ... existing guards / isAuthenticating + account resolution ...
    let success = await BiometricAuthManager.shared.authenticate(
        reason: "Approve code for \(account.issuer)"
    )
    guard success else {
        authFailed = true
        return
    }

    guard let code = TOTPGenerator.generate(for: account) else { return }
    RelayClient.shared.sendEncryptedCode(
        code, requestId: request.id,
        issuer: account.issuer, label: account.label
    )

    codeSent = true

    // NEW — mint the 2-min trust window (no-op if preference is OFF)
    TrustWindowManager.shared.mint()

    // DELETED — startAutoRefresh(account: account)

    try? await Task.sleep(nanoseconds: 1_500_000_000)
    onComplete()
}
```

### Silent-send branch in `RelayClient.handleMessage`

```swift
// Source: Shared/RelayClient.swift:155-165 (existing default: branch)
// MODIFICATION: inject isInWindow check before setting pendingCodeRequest
default:
    // Opaque forwarded message from Chrome extension -- decrypt
    guard let encryptedBase64 = envelope.payload["data"],
          let encryptedData = Data(base64Encoded: encryptedBase64),
          let sharedKey = PairingStore.shared.sharedKey,
          let plaintext = try? CryptoBoxManager.open(encryptedData, using: sharedKey),
          let request = try? JSONDecoder().decode(CodeRequest.self, from: plaintext)
    else { return }

    // NEW — silent-send branch
    if TrustWindowManager.shared.isInWindow,
       let account = AccountStore.shared?.resolve(for: request),  // see Note 1
       let code = TOTPGenerator.generate(for: account) {
        sendEncryptedCode(code, requestId: request.id,
                          issuer: account.issuer, label: account.label)
        TrustWindowManager.shared.showToast(for: account.issuer)
        return
    }

    // Existing behavior — presents approval sheet
    pendingCodeRequest = request
```

**Note 1:** `AccountStore.shared` does NOT currently exist (the store is owned by `KeyAuthApp` as a `@StateObject` and passed down). Three options for wiring:
1. Give `AccountStore` a `static weak var shared: AccountStore?` that `KeyAuthApp.onAppear` sets. Minimal change. Downside: introduces a singleton pattern previously avoided for `AccountStore`.
2. Make `TrustWindowManager` itself hold an injected `AccountStore` reference, set once at bootstrap from `KeyAuthApp`.
3. Give `RelayClient` an `accountResolver: ((CodeRequest) -> Account?)?` closure, set from `KeyAuthApp.onAppear`.

**Recommend option 3** — keeps both `AccountStore` and `RelayClient` agnostic of each other, matches the existing `RelayClient.onConnected` closure pattern (RelayClient.swift:17), and keeps testability high (inject a closure in tests).

### `TrustWindowPreference` (clone of `SyncPreference`)

```swift
// Source: cloned from Shared/SyncPreference.swift (Phase 6)
// File: Shared/TrustWindowPreference.swift (NEW)
import Foundation

enum TrustWindowPreference {
    private static let enabledKey = "trust_window_enabled"
    private static let hasLaunchedBeforeKey = "hasLaunchedBeforeTrustWindow"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    /// D-16 — default ON for both new and existing users.
    /// Call ONCE from KeyAuthApp.onAppear (guarded by a didBootstrapTrustWindow flag).
    static func bootstrap() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasLaunchedBeforeKey) { return }
        defaults.set(true, forKey: enabledKey)      // default ON
        defaults.set(true, forKey: hasLaunchedBeforeKey)
    }
}
```

**Shape comparison vs `SyncPreference`:**
| Property | `SyncPreference` | `TrustWindowPreference` |
|----------|------------------|-------------------------|
| UserDefaults key | `sync_enabled` | `trust_window_enabled` |
| First-launch sentinel | `hasLaunchedBefore` (shared — be careful!) | `hasLaunchedBeforeTrustWindow` (new, separate) |
| `bootstrap` signature | `bootstrap(existingAccountCount:)` (branches on existing vs new user) | `bootstrap()` (no branch — default ON for everyone per D-16) |
| Default value | Branches: new=ON, existing=OFF | Always ON (D-16) |

**Important:** The sentinel key must be SEPARATE from `SyncPreference.hasLaunchedBeforeKey` (`hasLaunchedBefore`). Reusing it would mean that after a Phase 6 install, the Phase 7 bootstrap would incorrectly short-circuit. [VERIFIED: `Shared/SyncPreference.swift:6`]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `CodeApprovalView.startAutoRefresh` — push a fresh code every 30s for 5 min on ONE account | Request-driven: extension asks, iOS answers (silently within 2min window, with FaceID otherwise) | Phase 7 (now) | Removes phantom code pushes. Extension must re-request when cached code expires — already in place via Phase 4 auto-fill trigger. |
| Per-fetch FaceID (no reuse) | 2-min global trust window after first FaceID | Phase 7 (now) | Reduces friction on re-auth loops; preserves "user must be aware" via visible toast. |
| `touchIDAuthenticationAllowableReuseDuration` | Pure timer flag | Phase 7 planning | Cleaner separation between "device unlock reuse" (Apple's mechanism) and "app-level session trust" (ours). |

**Deprecated/outdated:**
- `CodeApprovalView.startAutoRefresh` — delete per D-12
- Any documentation of "5-minute auto-push after FaceID" — update after Phase 7 lands

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `didEnterBackgroundNotification` does NOT fire for Control Center or Notification Center interactions; only for app-switcher, lock, or switch-to-other-app. | Pattern 1 / Pitfall 2 | If Apple has silently changed this, window would over-revoke on Control Center swipes. User-visible annoyance, not a security flaw. `[VERIFIED: Apple developer forum thread 685317]` but Apple's forum text is from 2021 — semantics have been stable since iOS 4. Confidence: HIGH. |
| A2 | SwiftUI `.overlay(alignment: .top)` on `ContentView.body` will be covered by `.sheet(...)` but remains visible after dismiss. | Pattern 3 / Pitfall 3 | If SwiftUI behavior changed in iOS 16+, toast might not show at all. Community reports confirm this is a stable, well-known limitation. Confidence: HIGH. |
| A3 | A `Timer.scheduledTimer` created on `@MainActor` is suspended (not fired late) when the app backgrounds. | Pitfall 7 | If Timer fires during background, `revoke()` runs twice (first from background-notification, then Timer). `Timer` invalidation is idempotent so this is benign — just extra work. Belt-and-suspenders via lazy `now() < exp` check covers the late-Timer case. Confidence: HIGH. |
| A4 | The existing test target (`KeyAuthTests`) can be extended to cover `TrustWindowManager` without project-file surgery for the source files — only for the new test files. `[VERIFIED: KeyAuthTests/Info.plist, KeyAuthTests.swift]` | Validation Architecture | Low — Phase 6 already demonstrated adding Swift files to the target via `xcodeproj` gem (STATE.md line 108). Confidence: HIGH. |
| A5 | `UIApplication.didEnterBackgroundNotification` is the correct trigger semantic for D-05 (NOT `willResignActiveNotification`). | Pattern 1 / D-05 | If user wants "window dies on ANY loss of foreground" (including Control Center swipes), A5 is wrong. CONTEXT.md explicitly references `didEnterBackground`, so treating the current spec as authoritative. Confidence: HIGH. |
| A6 | The visible toast (D-09) is sufficient to satisfy Apple App Review Guideline 5.1.1's "user must be aware" spirit for a silent biometric-bypass feature. | Security Domain / Phase-7 reviewer risk | Apple has no published precedent explicitly blessing or forbidding a time-bound trust window after FaceID. 1Password's "60-minute auto-lock" and Apple's own AutoFill "recently authenticated" semantics suggest this pattern is in wide acceptable use. No known App Store rejections on this pattern surfaced in research. Confidence: MEDIUM — **flag for manual user confirmation** during `/gsd-discuss-phase` if not already addressed. |
| A7 | The `resolve(for:)` helper's deterministic "return nil when ambiguous" behavior matches user intent. | Pattern 2 / FIDO-10 | CONTEXT.md Claude's Discretion says explicitly: "If multiple matches AND no exact issuer+label, the silent path MUST defer to FaceID (re-prompt)." Confidence: HIGH. |
| A8 | Toast text for a resolved issuer ("Code sent for GitHub") is understandable to users without jargon. | D-09 specifics | Opinionated but backed by CONTEXT.md specifics ("Code sent for GitHub — short, declarative, names the issuer. NOT 'Auto-approved' or 'Token reused'"). Confidence: HIGH. |
| A9 | `TrustWindowPreference` defaulting to ON for existing users (already have pairings, already used the app) is non-surprising because it is less restrictive than today's FaceID-every-request, so there's no "feature they already opted out of" to honor. | D-16 | User explicitly chose this in CONTEXT.md. Confidence: HIGH. |
| A10 | Two overlapping mint events (rare, but e.g., user approves, then triggers another FaceID manually from extension within a second) — second mint SHOULD reset the Timer, not compound. | FIDO-04 | CONTEXT.md D-04 is explicit. `expiryTimer?.invalidate()` in `mint()` handles this. Confidence: HIGH. |
| A11 | **Chrome extension currently has no UI affordance to trigger a re-request without the user clicking** — so phishing-via-rapid-fire is less likely than the D-14 worst case implies. | D-14 | Reading `extension/src/entrypoints/background.ts:333-380`, `request_code` is popup-driven only (via `handlePopupMessage`). A phishing site would have to trick the user into clicking the extension popup, which is notably harder than simply re-triggering a fetch. Confidence: HIGH — reduces the practical phishing surface noticeably, though it does NOT change the spec. |

**All `[ASSUMED]` claims above need planner/user confirmation only for A6** — the Apple App Review risk. Everything else is either [VERIFIED] in code/docs or follows directly from CONTEXT.md.

## Open Questions

1. **Where to mount `AccountResolver` access from `RelayClient`?**
   - What we know: `RelayClient` currently has no reference to `AccountStore`. Three options listed in Code Examples Note 1.
   - What's unclear: Which the planner prefers — static `AccountStore.shared`, injected property on `TrustWindowManager`, or injected closure on `RelayClient`.
   - Recommendation: **Injected closure on `RelayClient`** (option 3). Minimal API change, testable without singletons, matches existing `onConnected` closure pattern.

2. **Should `TrustWindowManager.showToast(for:)` fire BEFORE or AFTER `sendEncryptedCode`?**
   - What we know: Existing `CodeApprovalView.approveAndSend` shows `codeSent = true` before the `Task.sleep` that hides the sheet — i.e., it trusts the send. Fire-and-forget WebSocket send.
   - What's unclear: Whether Phase 7 should match this existing behavior OR introduce send-success confirmation.
   - Recommendation: **Match existing — fire toast immediately after calling `sendEncryptedCode`.** If reliability becomes an issue, address via a broader send-success refactor in a future phase (not Phase 7).

3. **Should the silent-send branch consume the FaceID cost if FaceID is required but user has disabled biometric at the OS level?**
   - What we know: `BiometricAuthManager.authenticate` already falls back to passcode via `LAPolicy.deviceOwnerAuthentication`. Within the window, we skip `LAContext.evaluatePolicy` entirely, so this fallback is not engaged.
   - What's unclear: If a user disables FaceID at the OS level AFTER minting a window, next silent send still succeeds without any auth. Is this right?
   - Recommendation: **Yes, by design.** The window was explicitly granted by a successful auth (bio or passcode fallback). Disabling biometric mid-window is equivalent to backgrounding the app from a security standpoint — but CONTEXT.md does not list "biometric disabled at OS level" as a revocation trigger. Document for planner; do NOT add a new trigger without user confirmation.

4. **Toast behavior if `TrustWindowPreference` is OFF?**
   - What we know: D-17 says no mint. `isInWindow` is always false. Silent branch never fires. Toast never appears.
   - What's unclear: Nothing. Confirming default behavior.
   - Recommendation: No action. Existing per-fetch FaceID flow is preserved.

5. **Chrome extension behavior if iOS sends code but extension has navigated away?**
   - Out of scope for Phase 7. Existing `RESIL-01..RESIL-05` handles this at the extension side.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode + Swift 5.9 | Build target | ✓ | project.yml declares 15.0 + Swift 5.9 | — |
| iOS 16.0+ simulator | Tests and manual QA | ✓ | project.yml `iOS: "16.0"` | — |
| `LocalAuthentication.framework` | `BiometricAuthManager` (unchanged reuse) | ✓ | iOS 16 SDK | — |
| `Combine` framework | `AnyCancellable` / `$didAccountChange` subscription | ✓ | iOS 16 SDK | — |
| `KeyAuthTests` scheme / target | Unit tests (FIDO-01..FIDO-19) | ✓ | Pre-existing from Phase 6 | — |
| Physical iPhone with FaceID | End-to-end manual QA of the FaceID prompt + 2-min window | Must be provided by developer | — | Simulator has simulated biometric via `Features → Face ID → Matching Face`, adequate for happy-path testing; 2-min wait test is trivial on device or simulator. |
| Paired Chrome extension + relay | End-to-end manual QA of silent-send branch | ✓ | Phase 1-6 complete | — |
| Ruby + `xcodeproj` gem | project.pbxproj edits for new source files | ✓ | STATE.md line 108 — already used in Phase 6 | Direct XML edit (risk of corruption per Phase 6 notes). Use the gem. |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** Physical iPhone with FaceID (simulator suffices for 95%+ of validation; only behavioral acceptance like "does FaceID physically appear" needs real hardware).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (`@testable import KeyAuth`) |
| Config file | `KeyAuthTests/Info.plist` + `KeyAuth.xcodeproj/project.pbxproj` `KeyAuthTests` target |
| Quick run command | `xcodebuild -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15' test -only-testing:KeyAuthTests/TrustWindowManagerTests` |
| Full suite command | `xcodebuild -project KeyAuth.xcodeproj -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 15' test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command / Test Name | File Exists? |
|--------|----------|-----------|-------------------------------|--------------|
| FIDO-01 | Singleton shape + initial state | unit | `TrustWindowManagerTests.testInitialState_isInWindowIsFalse` | ❌ Wave 0 (new file `KeyAuthTests/TrustWindowManagerTests.swift`) |
| FIDO-02 | Mint sets `windowExpiresAt = now + 120s` | unit | `TrustWindowManagerTests.testMintSetsExpiryTo120sFromNow` | ❌ Wave 0 |
| FIDO-03 | Mint is no-op when preference OFF | unit | `TrustWindowManagerTests.testMintNoOpWhenPreferenceDisabled` | ❌ Wave 0 |
| FIDO-04 | Re-mint replaces (fresh 2 min, not extended) | unit (injected clock) | `TrustWindowManagerTests.testReMintReplacesExpiry` | ❌ Wave 0 |
| FIDO-05 | `isInWindow` flips to false after expiry | unit (injected clock) | `TrustWindowManagerTests.testIsInWindowLazyExpiryCheck` | ❌ Wave 0 |
| FIDO-06 | Background notification revokes | unit | `TrustWindowManagerTests.testBackgroundNotificationRevokes` | ❌ Wave 0 |
| FIDO-07 | iCloud account change revokes | unit | `TrustWindowManagerTests.testICloudAccountChangeRevokes` (uses `_simulateIdentityChange`) | ❌ Wave 0 |
| FIDO-08 | `CodeApprovalView` mint integration | grep + integration | Source-file grep: `TrustWindowManager.shared.mint()` inside `approveAndSend`; integration test via extracted helper | ❌ Wave 0 |
| FIDO-09 | Silent-send happy path (`sendEncryptedCode` called, no `pendingCodeRequest`) | unit | `RelayClientSilentSendTests.testSilentSendInWindow` (inject closure-based resolver) | ❌ Wave 0 (new file) |
| FIDO-10 | Silent-send ambiguity defers to FaceID | unit | `RelayClientSilentSendTests.testAmbiguousResolutionSetsPendingCodeRequest` | ❌ Wave 0 |
| FIDO-11 | Toast text for resolved vs unresolved issuer | unit | `TrustWindowManagerTests.testToastTextForMatchedIssuer` / `testToastTextFallbackEmpty` | ❌ Wave 0 |
| FIDO-12 | Toast auto-dismiss after 2s | unit (injected clock OR `expectation(timeout: 2.5)`) | `TrustWindowManagerTests.testToastAutoDismissAfter2s` | ❌ Wave 0 |
| FIDO-13 | `startAutoRefresh` deleted | grep | `rg -F "startAutoRefresh" -- App/ Shared/ \| wc -l` equals 0 | ❌ Wave 0 — can run via CI shell step or inside a test with `Bundle.main.url` + contents read |
| FIDO-14 | `TrustWindowPreference` shape matches `SyncPreference` | unit | `TrustWindowPreferenceTests.testSetEnabledPersistsInUserDefaults` | ❌ Wave 0 (new file) |
| FIDO-15 | Settings toggle row wired to preference | unit | `SettingsViewTests.testTrustWindowToggleBoundToPreference` (grep-based, matching Phase 6 pattern — see STATE.md line 120) | ❌ Wave 0 (extend existing file) |
| FIDO-16 | Fresh-install default ON | unit | `TrustWindowPreferenceTests.testBootstrapDefaultsToEnabled` | ❌ Wave 0 |
| FIDO-17 | Window does not persist across launches | unit | `TrustWindowManagerTests.testSingletonStateIsNotPersisted` (instantiate a second manager + verify `isInWindow == false`) | ❌ Wave 0 |
| FIDO-18 | Toast visible after sheet dismisses | manual | 2-DEV-TW-01 in future `07-QA-CHECKLIST.md` (test on physical iPhone) | ❌ Wave 0 (QA checklist) |
| FIDO-19 | No extension source changes | grep | `git diff main...phase-7 -- extension/ \| wc -l` equals 0 | ❌ Wave 0 (CI step) |

### Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing:KeyAuthTests/TrustWindowManagerTests` (~2s per unit test; budget <20s total for the window manager suite)
- **Per wave merge:** Full suite `xcodebuild test` (runs the existing 61 Phase 6 tests + new Phase 7 tests; budget <3 min)
- **Phase gate:** Full suite green before `/gsd-verify-work`; also manual QA for FIDO-18 on physical iPhone with FaceID

### Wave 0 Gaps

- [ ] `KeyAuthTests/TrustWindowManagerTests.swift` — covers FIDO-01..FIDO-07, FIDO-11, FIDO-12, FIDO-17
- [ ] `KeyAuthTests/TrustWindowPreferenceTests.swift` — covers FIDO-14, FIDO-16
- [ ] `KeyAuthTests/RelayClientSilentSendTests.swift` — covers FIDO-09, FIDO-10 (mock `PairingStore.shared.sharedKey`, inject account-resolver closure)
- [ ] `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` — cheap fixture factory for `CodeRequest` (mirrors `AccountFixtures`)
- [ ] Extension of `KeyAuthTests/SettingsViewTests.swift` — grep assertion for the new toggle (FIDO-15)
- [ ] Phase 7 QA checklist file `.planning/phases/07-faceid-capability-tokens/07-QA-CHECKLIST.md` for FIDO-18 (manual toast-visible-after-sheet verification) and FIDO-19 (extension source unchanged)
- [ ] Injected-clock harness: `TrustWindowManager` exposes `var now: () -> Date`; tests inject to simulate 2-min passage deterministically. Framework install: none (XCTest already present).

**Validation strategy for `startAutoRefresh` deletion (FIDO-13):** A grep-based source-file test inside `KeyAuthTests` mirrors Phase 6's pattern (STATE.md line 108, Plan 06 `SettingsViewTests` grep-asserts). Include `App/Views/CodeApprovalView.swift` in the test bundle via the existing "Copy Shared Sources For Isolation Tests" Run-Script phase (already there per STATE.md line 120) and grep for absence of `startAutoRefresh`.

## Security Domain

Phase 7 has `security_enforcement: true` (absent in config.json, so enabled). This section enumerates threats and mitigations the planner MUST address in PLAN.md's `<threat_model>` blocks.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | **yes** | `BiometricAuthManager.authenticate` (existing) — no new auth surface |
| V3 Session Management | **yes** | `TrustWindowManager.windowExpiresAt` IS the session token; lifecycle (revoke on background/account change/timer) matches ASVS 3.3.1 (session termination on sign-out / context change) |
| V4 Access Control | **partial** | Access control decision (silent-send vs FaceID) is encapsulated in `RelayClient.handleMessage`; deterministic based on `isInWindow + resolve(for:)` |
| V5 Input Validation | **yes** | `CodeRequest` is decrypted-then-decoded via `JSONDecoder` (existing, unchanged) |
| V6 Cryptography | **no new** | `CryptoBoxManager` (ChaChaPoly + X25519) is reused as-is — never hand-roll |
| V11 Business Logic | **yes** | Trust window IS business logic; explicit threats (phishing replay, race conditions) enumerated below |

### Known Threat Patterns for this Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| **T1: Phishing-origin replay** — malicious site triggers `request_code` within 2 minutes of a legitimate approval, silently receives a code | Spoofing / Repudiation | **D-14 (deliberate trade-off)** — user sees the toast with issuer name and must notice the mismatch. Mitigated by: (a) visible toast (D-09), (b) Chrome extension popup is user-initiated (A11), (c) 2-min cap limits replay window. **Planner MUST document this trade-off in PLAN.md's `<threat_model>`.** |
| **T2: Token theft via screen recording** — attacker with screen recording captures the window state | Tampering | Not applicable in v1 — there is no token transmitted; the window is a local Boolean. An attacker with screen-record access could see the toast, but cannot extract `windowExpiresAt` remotely. |
| **T3: Race between background-revoke and in-flight `request_code`** — user backgrounds app while an extension request is mid-flight; revoke fires before silent-send branch evaluates | TOCTOU | **Check `isInWindow` AT the moment of send**, not at the moment of request-receive. The `handleMessage` call runs on the main actor, so the state is consistent. If background fires between decoding and `isInWindow` check, `revoke()` runs first → `isInWindow` is false → falls through to FaceID branch → but `RelayClient.disconnect` already ran (`KeyAuthApp.swift:71`), so `pendingCodeRequest` is set but no user sees it until foreground resume. Acceptable — extension eventually re-requests. |
| **T4: iCloud account change race** — user signs out of iCloud during an in-flight silent-send | TOCTOU | `ICloudStateObserver.$didAccountChange` → `revoke()` is wired in `bootstrap`; runs on main actor, same serialization as T3. Acceptable. |
| **T5: Multi-extension pairing surface** | — | **Out of scope.** Phase 2 D-03 locks to single pairing. Phase 7 inherits this constraint — only one Chrome extension can be paired at a time. Planner should flag this in PLAN.md as a known non-issue. |
| **T6: Settings-toggle-OFF not respected on every mint** | Elevation of Privilege | `TrustWindowManager.mint()` MUST check `TrustWindowPreference.isEnabled` EVERY time (FIDO-03). Test coverage required. |
| **T7: App-state restoration after force-quit** | Repudiation / Spoofing | Window is IN-MEMORY ONLY. Force-quit resets to `nil`. Next request always shows FaceID. Enforced by the "NOT persisted" architecture (Claude's Discretion). No code to write — enforced by absence. FIDO-17 verifies. |
| **T8: Toast not visible (user unaware)** | Spoofing / Repudiation | **Partial compliance risk for App Review 5.1.1.** A toast that fails to render due to SwiftUI bug / accessibility setting / state loss leaves user unaware of silent sends. Mitigations: (a) `.transition(.move(edge: .top).combined(with: .opacity))` works in reduce-motion-off, `.opacity` transition works in reduce-motion-on (see `TransientToastOverlay` existing handling), (b) VoiceOver announces via `.accessibilityLabel` (existing in `TransientToastOverlay`). Acceptance: if a user has "Reduce Motion" + silenced audio + screen off, the toast still appears visually on next wake. |
| **T9: Replay across a reboot** | — | IN-MEMORY state means reboot = empty window. Not exploitable. |
| **T10: Compiler/linker reordering placing `mint()` before `authenticate`** | Logic flaw | Source order in `approveAndSend` guarantees ordering at the Swift level. Compiler will not reorder observable effects across awaits. Acceptable. |

**Threat-to-requirement map the planner should include in PLAN.md:**
- T1 → FIDO-11 (toast emission) + D-14 documentation
- T3 → FIDO-06 (background revokes) + `isInWindow` at send-moment
- T4 → FIDO-07 (account change revokes)
- T6 → FIDO-03 (preference check in mint)
- T7 → FIDO-17 (not persisted)
- T8 → FIDO-18 (manual QA) + accessibility via existing `TransientToastOverlay`

### Reviewer-facing risks (Apple App Store)

- **No prior Apple rejection precedent surfaced** for a time-bound silent-biometric-bypass with a visible notification, searching for "App Store 5.1.1 trust window silent auth." Apple's own Safari AutoFill "recently authenticated" UX shows the pattern is in mainstream acceptable use. 1Password's browser extension has an "unlock duration" setting that is de facto the same model. Document the toast as the "user awareness" signal. **[ASSUMED: A6] — flag for discuss-phase confirmation if the user wants additional mitigations (e.g., a one-time onboarding card explaining the feature).**

## Sources

### Primary (HIGH confidence — code in this repo or Apple's own forum threads)
- `Shared/BiometricAuthManager.swift` — `authenticate(reason:) async -> Bool` with biometric → passcode fallback (verified by Read)
- `Shared/RelayClient.swift` lines 137-173 — `handleMessage` decryption + `pendingCodeRequest` assignment
- `App/Views/CodeApprovalView.swift` lines 146-240 — `onAppear` matching logic + `approveAndSend` + `startAutoRefresh`
- `App/KeyAuthApp.swift` lines 65-72 — `didEnterBackgroundNotification` observer + `isUnlocked = false`
- `Shared/ICloudStateObserver.swift` — `@Published didAccountChange` + test-only `_simulateIdentityChange`
- `Shared/SyncPreference.swift` — canonical `UserDefaults`-backed toggle shape to clone
- `App/Views/TransientToastOverlay.swift` — existing 42-line capsule toast component
- `Shared/CryptoBoxManager.swift` — `CodeRequest` struct shape
- `Shared/AccountStore.swift` — `@MainActor ObservableObject` + `reload()` pattern
- `extension/src/entrypoints/background.ts` lines 333-380 — popup-driven `request_code` flow (confirms A11)
- `project.yml` — iOS 16.0 deployment target, Swift 5.9
- `.planning/STATE.md` lines 93-128 — Phase 6 decisions, Ruby `xcodeproj` gem pattern
- Apple Developer Forum thread 685317 — `didEnterBackgroundNotification` vs `willResignActiveNotification` semantics [VERIFIED: https://developer.apple.com/forums/thread/685317]
- Apple Developer Forum thread 121149 — `evaluatePolicy` behavior with `LAContext` reuse [VERIFIED by web search excerpt]

### Secondary (MEDIUM confidence — cross-referenced docs)
- Microsoft Learn LAContext property reference for `TouchIdAuthenticationAllowableReuseDuration` — confirms property not deprecated in iOS 26 SDK and that the reuse is tied to context reuse, not just device-unlock [VERIFIED: https://learn.microsoft.com/en-us/dotnet/api/localauthentication.lacontext.touchidauthenticationallowablereuseduration]
- Hacking With Swift / Avanderlee — `@MainActor` + `Timer` interactions [CITED: https://www.hackingwithswift.com/articles/117/the-ultimate-guide-to-timer, https://www.avanderlee.com/swift/mainactor-dispatch-main-thread/]
- simplykyra.com — SwiftUI overlay-sheet interaction [CITED: https://www.simplykyra.com/blog/swiftui-overlays-and-their-issue-with-sheets/]
- Livsy code / Commit Studio / Medium — SwiftUI transient toast patterns (`.overlay(alignment:)` + `.transition(.move(edge:).combined(with: .opacity))`) [CITED: multiple]
- Apple App Review Guidelines — general 5.1.1 privacy framework [CITED: https://developer.apple.com/app-store/review/guidelines/]

### Tertiary (LOW confidence — community reports, flagged for validation)
- GitHub issue square/Valet#167 — developer reports of `touchIDAuthenticationAllowableReuseDuration` behaving unexpectedly across iOS versions. Supports the recommendation to avoid the property. Not load-bearing for this research — option (b) is chosen regardless.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — all Apple-framework; no third-party; project constraints verified
- Architecture: **HIGH** — all integration points verified by reading the existing code
- Pitfalls: **HIGH** — confirmed via Apple forum threads + existing codebase behavior
- Validation Architecture: **HIGH** — Phase 6 test infrastructure confirmed present and extensible
- Security Domain: **MEDIUM** — threat model is comprehensive but Apple App Review risk (A6) is inherently speculative

**Research date:** 2026-04-19
**Valid until:** 2026-05-19 (30 days — stack is stable, iOS 16+ APIs unlikely to shift)
