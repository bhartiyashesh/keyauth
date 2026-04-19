# Phase 7: FaceID Capability Tokens - Pattern Map

**Mapped:** 2026-04-19
**Files analyzed:** 14 (6 new, 6 modified, 2 registry/doc)
**Analogs found:** 14 / 14 (all files have an in-repo analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Shared/TrustWindowManager.swift` (NEW) | manager (singleton, `@MainActor` observable) | event-driven + UI-publisher | `Shared/ICloudStateObserver.swift` (Combine `@Published` publisher) + `Shared/RelayClient.swift` (Timer-based lifecycle) | hybrid — takes **observable-state shape** from `ICloudStateObserver` and **Timer lifecycle** from `RelayClient` |
| `Shared/TrustWindowPreference.swift` (NEW) | store (UserDefaults wrapper enum) | bootstrap + get/set | `Shared/SyncPreference.swift` | exact (shape-clone target; D-16 says "default ON for everyone" vs SyncPreference's branched default) |
| `App/Views/TrustWindowToastOverlay.swift` *(or reuse existing)* | view (SwiftUI overlay) | consumes window state, self-dismisses | `App/Views/TransientToastOverlay.swift` | exact — UI-SPEC §Component Inventory explicitly says "Reused" and asks for a 1-line `duration` parameterization on the existing file |
| `KeyAuthTests/TrustWindowManagerTests.swift` (NEW) | test (unit, `@MainActor`) | mint/revoke/expiry/toast assertions with injected clock | `KeyAuthTests/ICloudStateObserverTests.swift` + `KeyAuthTests/RestoringStateTests.swift` (injected-timeout mirror pattern) | exact — same `@testable import KeyAuth`, `@MainActor` XCTestCase, `setUp`/`tearDown` UserDefaults scrub, internal `_simulate…` hooks |
| `KeyAuthTests/TrustWindowPreferenceTests.swift` (NEW) | test (unit, UserDefaults bootstrap) | bootstrap first-launch + getter persistence | `KeyAuthTests/KeyAuthTests.swift::testSyncPreferenceBootstrap*` (lines 24-38) | exact — same UserDefaults-scrub-per-test pattern on the `SyncPreference` analog |
| `KeyAuthTests/RelayClientSilentSendTests.swift` (NEW) | test (unit) | silent-send branch + account-resolver closure injection | `KeyAuthTests/AccountStoreTests.swift` (MockKeychain-injected state fixtures) + *no existing RelayClient tests* | partial — there are no pre-existing `RelayClient` tests, so this plan introduces the first. Closest analog is the `AccountStoreTests` dependency-injection pattern (MockKeychain injected into `AccountStore(keychain:)`) |
| `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` (NEW) | fixture | factory returning `CodeRequest` test doubles | `KeyAuthTests/Fixtures/AccountFixtures.swift` | exact — same factory-function shape, same `@testable import KeyAuth`, same optional-parameter defaults-with-overrides style |
| `Shared/RelayClient.swift` (MODIFIED §155-165) | manager (modified) | request-response branch | *self* — the edit is inside the file's own existing `default:` branch (see RESEARCH Code Examples line 534-555) | exact (self-analog) |
| `App/Views/CodeApprovalView.swift` (MODIFIED §163-203 + DELETE §205-240) | view (modified) | post-auth mint + timer deletion | *self* — the edit adds a single `TrustWindowManager.shared.mint()` call and deletes `startAutoRefresh` | exact (self-analog) |
| `App/KeyAuthApp.swift` (MODIFIED §65-72, §40-49) | app entry (modified) | wires StateObject + bootstrap + revocation subscriptions | *self* — uses patterns already present at lines 7-9 (`@StateObject = .shared`), 40-49 (`onAppear` bootstrap), 65-72 (`didEnterBackgroundNotification`) | exact (self-analog; all three patterns already exist in the same file) |
| `App/Views/SettingsView.swift` (MODIFIED — add section) | view (modified) | adds one `Section { Toggle } footer: { Text }` | `App/Views/SettingsView.swift::syncSection` (lines 89-103) | exact (self-analog; UI-SPEC §Component Inventory mandates "visual parity with the Phase 6 Sync toggle") |
| `App/Views/ContentView.swift` (MODIFIED — add `.overlay`) | view (modified) | mounts toast overlay driven by `@EnvironmentObject` | Sheet-modifier pattern at `ContentView.swift:125-130` (same hierarchy level) + `TransientToastOverlay` usage contract (caller-bound `isPresented`) | hybrid — takes placement site from the existing `.sheet(item:)` modifier and overlay-mount call shape from the `TransientToastOverlay` docstring |
| `KeyAuthTests/SettingsViewTests.swift` (EXTEND — add ~2 tests) | test (grep-based copy regression) | source-file literal-string assertions | *self* (existing pattern in same file) — `testToggleLabelMatchesUISpec` (lines 48-52) | exact (self-analog; add two new grep assertions with the same helper `loadBundledSource(named:)`) |
| `.planning/REQUIREMENTS.md` (MODIFIED — add FIDO-01..FIDO-19) | doc (registry) | adds 19 requirement rows | Existing `ICLOUD-01..ICLOUD-16` block at `.planning/REQUIREMENTS.md:56-` | exact — same checkbox list shape, same `**ID**: Description` format |

## Pattern Assignments

### `Shared/TrustWindowManager.swift` (NEW, manager, event-driven + UI-publisher)

**Primary analog:** `Shared/ICloudStateObserver.swift` (lines 1-91) — for the `@MainActor` observable-object + Combine-publisher shape.
**Secondary analog:** `Shared/RelayClient.swift` (lines 184-222) — for the `Timer.scheduledTimer` + `weak self` + `Task { @MainActor [weak self] in … }` reconnection-timer pattern.

**Singleton declaration pattern** (from `ICloudStateObserver.swift:4-9`):
```swift
import Foundation
import Combine

@MainActor
final class ICloudStateObserver: ObservableObject {
    static let shared = ICloudStateObserver()

    @Published private(set) var isICloudSignedIn: Bool
    @Published private(set) var didAccountChange: Bool = false
```
**Apply to Phase 7:** `TrustWindowManager` uses the same `@MainActor final class … ObservableObject { static let shared = … }` shape. Declare `@Published private(set) var windowExpiresAt: Date?` and `@Published var pendingToast: ToastMessage?`.

**NotificationCenter observer pattern (closure retention)** (from `ICloudStateObserver.swift:25-31`):
```swift
identityObserver = NotificationCenter.default.addObserver(
    forName: .NSUbiquityIdentityDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in self?.handleIdentityChange() }
}
```
**Apply to Phase 7:** Same `[weak self]` + `Task { @MainActor in … }` pattern for `UIApplication.didEnterBackgroundNotification` (D-05 revocation trigger). Store the observer token in a `private var backgroundObserver: NSObjectProtocol?` ivar; remove it in `deinit` (see `ICloudStateObserver.swift:34-38`). Alternatively, follow RESEARCH Pattern 1 and use `.publisher(for:).sink` + `Set<AnyCancellable>` — both are in-repo conventions.

**Combine `$publisher.sink` + cancellables storage pattern** (established by RESEARCH §Pattern 1, consistent with Apple Combine idiom — no direct existing `.store(in:)` usage in KeyAuth today, but `Combine` is already imported in `ICloudStateObserver.swift` line 2 and `AccountStore.swift` line 2):
```swift
private var cancellables = Set<AnyCancellable>()

// In bootstrap():
ICloudStateObserver.shared.$didAccountChange
    .sink { [weak self] changed in
        guard changed else { return }
        Task { @MainActor in self?.revoke() }
    }
    .store(in: &cancellables)
```
**Apply to Phase 7:** Store all Combine subscriptions in `cancellables`. This observes D-06 revocation trigger via the Phase 6 observer.

**Timer-based lifecycle pattern** (from `RelayClient.swift:185-201`):
```swift
private func scheduleReconnect() {
    reconnectTimer?.invalidate()
    let delay = min(reconnectBaseInterval * pow(2.0, Double(reconnectAttempts)), reconnectMaxInterval)
    reconnectAttempts += 1
    reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
        Task { @MainActor [weak self] in
            guard let self, let roomId = self.roomId, let relayURL = self.relayURL else { return }
            // ...
        }
    }
}
```
**Apply to Phase 7:** Inside `mint(ttl:)`, invalidate any prior `expiryTimer`, schedule a new non-repeating `Timer.scheduledTimer(withTimeInterval: ttl, repeats: false)` callback that posts back to `@MainActor` and calls `revoke()`. Mirrors the pattern exactly. Invalidate the timer in `revoke()` too (see `RelayClient.swift:217-222 stopTimers()`).

**Test-only helper pattern** (from `ICloudStateObserver.swift:66-90`):
```swift
#if DEBUG
internal func _primeAsSignedIn() {
    isICloudSignedIn = true
    previousIdentityToken = NSString(string: "test-primed-token")
    didAccountChange = false
}

internal func _simulateIdentityChange(newToken: AnyObject?) {
    // ... mirrors handleIdentityChange but takes caller-supplied token
}
#endif
```
**Apply to Phase 7:** `TrustWindowManager` exposes (a) `var now: () -> Date = { Date() }` as a test-injection seam (RESEARCH §Pattern 1 line 254) — prefer this over `#if DEBUG` because the research treats it as production-visible injection, but keep the API `internal` so `@testable import KeyAuth` reaches it; (b) an optional `#if DEBUG internal func _fireExpiryTimerNow()` if the test needs to force the timer callback without waiting 120s.

**Lazy `isInWindow` derivation** (from the research-endorsed belt-and-suspenders pattern; no direct analog in the repo — this is net-new but matches the "derived `isPaired: Bool { pairingData != nil }`" computed-property style in `PairingStore.swift:12`):
```swift
// Source: PairingStore.swift:12
var isPaired: Bool { pairingData != nil }
```
**Apply to Phase 7:** `var isInWindow: Bool { guard let exp = windowExpiresAt else { return false }; return now() < exp }` — pure computed property derived from stored state, consistent with the `isPaired` pattern.

---

### `Shared/TrustWindowPreference.swift` (NEW, store, bootstrap + get/set)

**Primary analog:** `Shared/SyncPreference.swift` (lines 1-41) — shape-clone target.

**Full source of analog** (`Shared/SyncPreference.swift:1-41`):
```swift
import Foundation

/// Per-device iCloud-sync toggle state. NOT stored in iCloud (this is UX state, not data).
enum SyncPreference {
    private static let enabledKey = "sync_enabled"
    private static let hasSeenFirstLaunchCardKey = "hasSeenSyncFirstLaunchCard"
    private static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    static var hasSeenFirstLaunchCard: Bool {
        UserDefaults.standard.bool(forKey: hasSeenFirstLaunchCardKey)
    }

    static func markFirstLaunchCardSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenFirstLaunchCardKey)
    }

    /// Per CONTEXT.md D-01 (new users default sync=ON) vs D-02 (existing users default OFF).
    /// Call ONCE from KeyAuthApp.onAppear before AccountStore init.
    static func bootstrap(existingAccountCount: Int) {
        let defaults = UserDefaults.standard
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedBeforeKey)
        if hasLaunchedBefore { return }

        let isExistingUser = existingAccountCount > 0
        defaults.set(!isExistingUser, forKey: enabledKey)
        defaults.set(true, forKey: hasLaunchedBeforeKey)
    }
}
```

**Apply to Phase 7:** Clone the entire shape. Differences per CONTEXT D-16 and RESEARCH line 600:
1. Keys: `enabledKey = "trust_window_enabled"`, sentinel `hasLaunchedBeforeKey = "hasLaunchedBeforeTrustWindow"` (MUST be distinct from `SyncPreference`'s `hasLaunchedBefore` to avoid cross-bootstrap short-circuit — RESEARCH line 602).
2. `bootstrap()` takes **no parameters** (no existing-user branch; default ON for everyone per D-16):
   ```swift
   static func bootstrap() {
       let defaults = UserDefaults.standard
       if defaults.bool(forKey: hasLaunchedBeforeKey) { return }
       defaults.set(true, forKey: enabledKey)      // default ON (D-16)
       defaults.set(true, forKey: hasLaunchedBeforeKey)
   }
   ```
3. Drop the `hasSeenFirstLaunchCard` / `markFirstLaunchCardSeen` / `shouldShowFirstLaunchCard` helpers — Phase 7 does not introduce a first-launch card (UI-SPEC §Component Inventory is explicitly scoped to Toggle + Toast).

---

### `App/Views/TrustWindowToastOverlay.swift` — *NOT a new file* (view, consumes state)

**Decision from UI-SPEC §Component Inventory:** do NOT introduce a new overlay file. Parameterize the existing `TransientToastOverlay` and mount it on `ContentView` via a caller closure driven by `TrustWindowManager.pendingToast`.

**Primary analog (and edit target):** `App/Views/TransientToastOverlay.swift` (lines 1-42).

**Full existing component** (unchanged chrome — only the 1-line `duration` parameterization changes):
```swift
// App/Views/TransientToastOverlay.swift:1-42
struct TransientToastOverlay: View {
    let message: String
    let icon: String
    let iconColor: Color
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPresented {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(iconColor)
                    Text(message).font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 16)
                .transition(reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel(message)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { isPresented = false }
                    }
                }
            }
        }
    }
}
```

**Edit per UI-SPEC §Component Inventory row 1:**
1. Add `var duration: Double = 3.0` stored property (defaulted — keeps Phase 6 callers source-compatible).
2. Replace the hardcoded `.now() + 3.0` with `.now() + duration` on line 34.
3. Phase 7 callers pass `duration: 2.0` (CONTEXT D-09 + UI-SPEC §Interaction Patterns toast lifecycle).

**Accessibility announcement pattern** (not in existing code — UI-SPEC §Accessibility mandates adding this in `TrustWindowManager.showToast(for:)`, not in the view):
```swift
// UI-SPEC Open Question 3 answer — iOS 16 deployment target
UIAccessibility.post(notification: .announcement, argument: toastText)
```
**Apply to Phase 7:** Fire inside `TrustWindowManager.showToast(for:)` co-located with the `@Published var pendingToast = …` assignment so VoiceOver users are notified even when the toast is not focused.

---

### `KeyAuthTests/TrustWindowManagerTests.swift` (NEW, test)

**Primary analog:** `KeyAuthTests/ICloudStateObserverTests.swift` (lines 1-43) — exact XCTestCase shape.
**Secondary analog:** `KeyAuthTests/RestoringStateTests.swift` (lines 1-116) — for the **injected-timeout mirror state-machine** pattern (crucial for Phase 7 because FIDO-04/05 require simulating 120s passage without actually waiting).

**Test class shape** (from `ICloudStateObserverTests.swift:1-43`):
```swift
import XCTest
import Foundation
@testable import KeyAuth

@MainActor
final class ICloudStateObserverTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        try await super.tearDown()
    }

    func testSignOutSimulationFlipsSyncPreferenceOff() {
        SyncPreference.setEnabled(true)
        // ...
        observer._primeAsSignedIn()
        // ...
        observer._simulateIdentityChange(newToken: nil)
        XCTAssertFalse(SyncPreference.isEnabled, "ICLOUD-15: SyncPreference must flip OFF on sign-out")
        XCTAssertTrue(observer.didAccountChange, "didAccountChange must fire for UI to show D-12 copy")
    }
}
```
**Apply to Phase 7:**
- Same `@MainActor final class TrustWindowManagerTests: XCTestCase` wrapper.
- In `setUp`/`tearDown`, scrub `trust_window_enabled` and `hasLaunchedBeforeTrustWindow` UserDefaults keys (mirrors `sync_enabled` scrub).
- Use the injected `var now: () -> Date` seam on `TrustWindowManager` to deterministically advance the clock (FIDO-04, FIDO-05). Example:
  ```swift
  var clock = Date()
  let mgr = TrustWindowManager()  // or .shared if safe; see note below
  mgr.now = { clock }
  mgr.mint(ttl: 120)
  clock = clock.addingTimeInterval(121)
  XCTAssertFalse(mgr.isInWindow)
  ```
- For FIDO-06 (background-revoke), post `UIApplication.didEnterBackgroundNotification` via `NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)` and assert the revoke took effect.
- For FIDO-07 (iCloud account change), use the existing `ICloudStateObserver.shared._primeAsSignedIn()` + `._simulateIdentityChange(newToken: nil)` hooks from the analog.

**Mirror state-machine pattern for timer-sensitive tests** (from `RestoringStateTests.swift:44-78` — this is the pattern to use when the `@State`/Timer is inside production code and cannot be directly observed):
```swift
// RestoringStateTests.swift:44-78 — mirror of ContentView.evaluateRestoringState(timeout:)
@MainActor
final class RestoringStateMachine {
    enum State { case idle, restoring, restored, timedOut }
    var state: State = .idle
    let isSyncEnabled: Bool
    let accountsEmptyProvider: () -> Bool
    // ...
    func evaluate(timeout: TimeInterval) {
        // Matches ContentView production rules
    }
}
```
**Apply to Phase 7:** If testing the `Timer.scheduledTimer` fire proves flaky, wrap the `mint()` + expiry-check logic in a mirror `TrustWindowStateMachine` with the same rules + injected clock. Most tests should NOT need this — the `var now: () -> Date` seam + lazy `isInWindow` getter is cleaner.

**Singleton-state hygiene note:** `TrustWindowManager.shared` is process-wide state. Tests must either (a) reset it in `setUp` via a `_reset()` DEBUG hook, or (b) instantiate `TrustWindowManager()` directly (init is `private` today — plan must expose an `internal init()` for test access, following the "override `private init` to `internal init` under `@testable`" pattern that Swift allows implicitly. Alternatively, add a `#if DEBUG internal func _resetForTests() { … }` helper following `ICloudStateObserver`'s `_primeAsSignedIn` precedent.

---

### `KeyAuthTests/TrustWindowPreferenceTests.swift` (NEW, test)

**Primary analog:** `KeyAuthTests/KeyAuthTests.swift` (lines 24-38) — SyncPreference bootstrap unit tests.

**Exact pattern** (from `KeyAuthTests.swift:24-38`):
```swift
func testSyncPreferenceBootstrapNewUser() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "hasLaunchedBefore")
    defaults.removeObject(forKey: "sync_enabled")
    SyncPreference.bootstrap(existingAccountCount: 0)
    XCTAssertTrue(SyncPreference.isEnabled, "New user (D-01) must default sync=ON")
}

func testSyncPreferenceBootstrapExistingUser() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "hasLaunchedBefore")
    defaults.removeObject(forKey: "sync_enabled")
    SyncPreference.bootstrap(existingAccountCount: 5)
    XCTAssertFalse(SyncPreference.isEnabled, "Existing user (D-02) must default sync=OFF")
}
```
**Apply to Phase 7:** Same shape, substituting:
- Keys: `"hasLaunchedBeforeTrustWindow"` and `"trust_window_enabled"` scrubbed in `setUp`/each test body.
- Call `TrustWindowPreference.bootstrap()` (no parameter).
- Assert `XCTAssertTrue(TrustWindowPreference.isEnabled)` on fresh install regardless of existing-account count (covers FIDO-16).
- Separate test asserts `setEnabled(false)` persists across a re-read — mirrors `SyncPreference.setEnabled` call-site in `ICloudStateObserverTests.swift:19`.

---

### `KeyAuthTests/RelayClientSilentSendTests.swift` (NEW, test)

**Primary analog:** `KeyAuthTests/AccountStoreTests.swift` (dependency-injection via MockKeychain, lines 1-106). No existing `RelayClientTests` file — this is the first.

**Dependency-injection pattern** (from `AccountStoreTests.swift:33-42`):
```swift
func testReloadPopulatesAccountsFromKeychain() throws {
    let seed = [
        AccountFixtures.make(issuer: "A", sortOrder: 0),
        AccountFixtures.make(issuer: "B", sortOrder: 1),
        AccountFixtures.make(issuer: "C", sortOrder: 2)
    ]
    for a in seed { try mock.save(a, synchronizable: false) }
    let store = AccountStore(keychain: mock)
    XCTAssertEqual(store.accounts.count, 3)
}
```
**Apply to Phase 7:** Instead of mocking WebSocket I/O, follow RESEARCH §Code Examples Note 1 option 3: add an **injected `accountResolver: ((CodeRequest) -> Account?)?`** closure on `RelayClient` (wired once from `KeyAuthApp.onAppear`). Tests inject a canned resolver closure, call the private `handleMessage` decoded-branch logic (extract the silent-send branch into an `internal func handleDecodedRequest(_ request: CodeRequest)` to make it unit-testable without WebSocket plumbing), and assert:
- FIDO-09: When `TrustWindowManager.shared.isInWindow == true` AND resolver returns an account, `sendEncryptedCode` is invoked and `pendingCodeRequest` remains `nil`. Use a test-only spy (`var sendEncryptedCodeCalls: [(String, String, String, String)] = []`) exposed via a DEBUG hook or an injected closure.
- FIDO-10: When resolver returns `nil` (ambiguous), `pendingCodeRequest = request` is set and `sendEncryptedCode` is NOT called.

**Sharing a `PairingStore.sharedKey`:** The silent-send branch reads `PairingStore.shared.sharedKey`. For unit tests without a real pairing, either (a) skip the decryption path and test the post-decrypt branch directly, or (b) seed `PairingStore.shared` via a test-only helper matching `ICloudStateObserver._primeAsSignedIn`. Recommend (a) for simplicity — extract the branch as described above.

---

### `KeyAuthTests/Fixtures/CodeRequestFixtures.swift` (NEW, fixture)

**Primary analog:** `KeyAuthTests/Fixtures/AccountFixtures.swift` (lines 1-40).

**Exact pattern** (from `AccountFixtures.swift:4-39`):
```swift
enum AccountFixtures {
    static func make(
        id: UUID = UUID(),
        issuer: String = "GitHub",
        label: String = "user@example.com",
        secret: String = "JBSWY3DPEHPK3PXP",
        sortOrder: Int = 0,
        createdAt: Date? = nil
    ) -> Account {
        let a = Account(
            id: id,
            issuer: issuer,
            label: label,
            secret: secret,
            sortOrder: sortOrder
        )
        // ...
        return a
    }
}
```
**Apply to Phase 7:**
```swift
enum CodeRequestFixtures {
    static func make(
        id: String = UUID().uuidString,
        issuer: String = "GitHub",
        label: String = "user@example.com",
        domain: String? = "github.com"
    ) -> CodeRequest {
        CodeRequest(id: id, issuer: issuer, label: label, domain: domain)
    }

    static func empty(domain: String? = "github.com") -> CodeRequest {
        CodeRequest(id: UUID().uuidString, issuer: "", label: "", domain: domain)
    }
}
```
`CodeRequest` shape is defined in `Shared/CryptoBoxManager.swift:20-25`.

---

### `Shared/RelayClient.swift` (MODIFIED §155-165, self-analog)

**Edit site** (current code at `Shared/RelayClient.swift:155-165`):
```swift
default:
    // Opaque forwarded message from Chrome extension -- decrypt
    guard let encryptedBase64 = envelope.payload["data"],
          let encryptedData = Data(base64Encoded: encryptedBase64),
          let sharedKey = PairingStore.shared.sharedKey,
          let plaintext = try? CryptoBoxManager.open(encryptedData, using: sharedKey),
          let request = try? JSONDecoder().decode(CodeRequest.self, from: plaintext)
    else { return }

    pendingCodeRequest = request
```

**Silent-send injection pattern** (per RESEARCH Code Examples line 534-555):
```swift
// AFTER the decode, BEFORE `pendingCodeRequest = request`:
if TrustWindowManager.shared.isInWindow,
   let account = self.accountResolver?(request),   // injected closure, see Note 1
   let code = TOTPGenerator.generate(for: account) {
    sendEncryptedCode(code, requestId: request.id,
                      issuer: account.issuer, label: account.label)
    TrustWindowManager.shared.showToast(for: account.issuer)
    return
}

// Existing behavior — presents approval sheet
pendingCodeRequest = request
```

**Resolver-closure declaration pattern** (from `Shared/RelayClient.swift:17`):
```swift
/// Called once after WebSocket connection is established. Set by pairing flow to send ack.
var onConnected: (() -> Void)?
```
**Apply to Phase 7:** Add `var accountResolver: ((CodeRequest) -> Account?)?` as a sibling property to `onConnected`. Wired from `KeyAuthApp.onAppear` with the resolution logic from CodeApprovalView.onAppear (see Pattern 2 below).

**`sendEncryptedCode` — already implemented** (from `RelayClient.swift:106-117`) — call as-is:
```swift
func sendEncryptedCode(_ code: String, requestId: String, issuer: String, label: String) { ... }
```

---

### `App/Views/CodeApprovalView.swift` (MODIFIED §163-203 + DELETE §205-240, self-analog)

**Edit site — mint the window after auth success** (current code at `CodeApprovalView.swift:182-203`):
```swift
let success = await BiometricAuthManager.shared.authenticate(
    reason: "Approve code for \(account.issuer)"
)

guard success else {
    authFailed = true
    return
}

// Generate and send the first code
guard let code = TOTPGenerator.generate(for: account) else { return }
RelayClient.shared.sendEncryptedCode(code, requestId: request.id, issuer: account.issuer, label: account.label)

codeSent = true

// Start auto-refresh: keep sending fresh codes for 5 minutes
startAutoRefresh(account: account)                          // ← DELETE per D-12

// Auto-dismiss after brief confirmation
try? await Task.sleep(nanoseconds: 1_500_000_000)
onComplete()
```

**Apply per RESEARCH Code Examples line 519** — replace `startAutoRefresh(account: account)` with:
```swift
// NEW — mint the 2-min trust window (no-op if TrustWindowPreference.isEnabled == false, per D-17)
TrustWindowManager.shared.mint()
```

**Delete site — remove auto-refresh Timer** (current code at `CodeApprovalView.swift:205-240`):
```swift
private func startAutoRefresh(account: Account) {
    // Track last sent code to avoid sending duplicates
    var lastSentCode = TOTPGenerator.generate(for: account) ?? ""
    // ... 35-line Timer.scheduledTimer loop ...
}
```
**Apply:** Delete entire function. FIDO-13 grep-test asserts the string `startAutoRefresh` no longer appears in `App/` or `Shared/` source.

---

### `App/KeyAuthApp.swift` (MODIFIED §7-9, §40-49, §56-72, self-analog)

**StateObject-of-shared-singleton pattern** (from `KeyAuthApp.swift:7-9`):
```swift
@StateObject private var store = AccountStore()
@StateObject private var pairingStore = PairingStore.shared
@StateObject private var icloudState = ICloudStateObserver.shared
```
**Apply to Phase 7:** Add `@StateObject private var trustWindow = TrustWindowManager.shared` as a fourth sibling.

**EnvironmentObject injection pattern** (from `KeyAuthApp.swift:25-29`):
```swift
ContentView()
    .environmentObject(store)
    .environmentObject(pairingStore)
    .environmentObject(icloudState)
    .environmentObject(migration)
```
**Apply to Phase 7:** Add `.environmentObject(trustWindow)` so `ContentView` can read `pendingToast` via `@EnvironmentObject var trustWindow: TrustWindowManager`.

**Bootstrap-once pattern** (from `KeyAuthApp.swift:13` + `:76-83`):
```swift
@State private var didBootstrapSyncPreference = false
// ...
private func bootstrapSyncPreferenceOnce() {
    guard !didBootstrapSyncPreference else { return }
    didBootstrapSyncPreference = true
    let existingCount = SharedDefaults.loadAccounts().count
    SyncPreference.bootstrap(existingAccountCount: existingCount)
}
```
**Apply to Phase 7:** Add a sibling `@State private var didBootstrapTrustWindowPreference = false` plus:
```swift
private func bootstrapTrustWindowPreferenceOnce() {
    guard !didBootstrapTrustWindowPreference else { return }
    didBootstrapTrustWindowPreference = true
    TrustWindowPreference.bootstrap()
    TrustWindowManager.shared.bootstrap()  // wires NotificationCenter + ICloudStateObserver subscriptions
    // Wire the account-resolver closure so RelayClient silent-send can resolve accounts
    RelayClient.shared.accountResolver = { [weak store] request in
        return store?.resolve(for: request)
    }
}
```
Call from `.onAppear` after `bootstrapSyncPreferenceOnce()` (line 44).

**Background-notification observer pattern** (from `KeyAuthApp.swift:65-72`):
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
**Apply to Phase 7:** No edit needed at this call site — `TrustWindowManager.bootstrap()` subscribes to the same notification via its own Combine sink (research-endorsed pattern). Per D-05, revocation happens inside the manager; the App-level closure stays focused on its existing unlock + disconnect concerns. Keeping the revocation observer *inside* the manager honors the anti-pattern in RESEARCH line 414 ("Subscribing to `ICloudStateObserver.$didAccountChange` inside a SwiftUI `View`" — equivalent concern applies to app-level closures that own unrelated state).

---

### `App/Views/SettingsView.swift` (MODIFIED — add section, self-analog)

**Section shape pattern** (from `SettingsView.swift:89-103`, the Phase 6 `syncSection`):
```swift
private var syncSection: some View {
    Section {
        Toggle("Sync with iCloud Keychain", isOn: $syncEnabled)
            .disabled(!icloud.isICloudSignedIn || isInCooldown || migration.isRunning)
            .onChange(of: syncEnabled) { newValue in
                handleToggleChange(newValue: newValue)
            }
    } header: {
        Text("Sync")
    } footer: {
        Text(footerCopy)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
```

**Apply to Phase 7** per UI-SPEC Copywriting Contract line 147-156:
```swift
@State private var trustWindowEnabled: Bool = TrustWindowPreference.isEnabled

private var trustWindowSection: some View {
    Section {
        Toggle("Allow 2-minute trust window after FaceID", isOn: $trustWindowEnabled)
            .onChange(of: trustWindowEnabled) { newValue in
                TrustWindowPreference.setEnabled(newValue)
            }
    } header: {
        Text("Security")   // UI-SPEC Open Question 1 recommendation
    } footer: {
        Text("Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
```
**Insert position** (per UI-SPEC Open Question 2): in `body`, between `syncSection` and `migrationProgressSection`:
```swift
Form {
    syncSection
    trustWindowSection               // ← NEW
    if migration.isRunning && migration.progress.total > 10 { migrationProgressSection }
    if !icloud.isICloudSignedIn { openSettingsSection }
    securedSection
}
```

**No disabled-state logic** — D-16 specifies the toggle has no external dependencies; no `.disabled(…)` modifier (unlike `syncSection`).

---

### `App/Views/ContentView.swift` (MODIFIED — add `.overlay`, hybrid self-analog)

**Sheet-modifier placement site** (current code at `ContentView.swift:125-130`):
```swift
.sheet(item: $relayClient.pendingCodeRequest) { request in
    CodeApprovalView(request: request) {
        relayClient.pendingCodeRequest = nil
    }
    .environmentObject(store)
}
```
**Apply to Phase 7 per UI-SPEC §Interaction Patterns "Position":** Add `.overlay(alignment: .top) { … }` at the **same hierarchy level** as the existing `.sheet`. Since UI-SPEC Component Inventory reuses the existing `TransientToastOverlay`, the minimal edit is:

```swift
@EnvironmentObject var trustWindow: TrustWindowManager   // NEW stored property

// Inside body, same level as `.sheet(item:)`:
.overlay(alignment: .top) {
    if let toast = trustWindow.pendingToast {
        TransientToastOverlay(
            message: toast.text,
            icon: "paperplane.fill",
            iconColor: .secondary,
            duration: 2.0,                    // UI-SPEC §Interaction Patterns toast lifecycle
            isPresented: .constant(true)      // Visibility is driven by `if let toast`, not a Bool
        )
        .padding(.top, 8)
    }
}
.animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)
```

**Note on `isPresented: .constant(true)`:** The existing `TransientToastOverlay` takes a `@Binding var isPresented: Bool` and self-dismisses via `asyncAfter`. In the Phase 7 flow, `TrustWindowManager` owns dismissal (via its own Timer), so the overlay's internal `asyncAfter` is redundant-but-harmless. If the planner prefers cleaner semantics, invert control: either (a) pass a real `Binding` backed by a private `@State var` on `ContentView` that flips when `trustWindow.pendingToast` changes, or (b) extend `TransientToastOverlay` to accept an optional `duration: Double? = nil` sentinel that disables self-dismiss. Document the choice in PLAN.md.

**EnvironmentObject read pattern** (from `ContentView.swift:9`):
```swift
@EnvironmentObject var store: AccountStore
```

---

### `KeyAuthTests/SettingsViewTests.swift` (EXTEND, self-analog)

**Existing grep-test pattern** (from `SettingsViewTests.swift:48-52`):
```swift
func testToggleLabelMatchesUISpec() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Toggle(\"Sync with iCloud Keychain\""),
        "ICLOUD-04: Toggle label must be 'Sync with iCloud Keychain'")
}
```

**Apply to Phase 7:** Add two sibling tests (FIDO-15):
```swift
func testTrustWindowToggleLabelMatchesUISpec() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Toggle(\"Allow 2-minute trust window after FaceID\""),
        "FIDO-15: Toggle label must match UI-SPEC verbatim")
}

func testTrustWindowFooterHelperTextVerbatim() throws {
    let src = try loadBundledSource(named: "SettingsView.swift")
    XCTAssertTrue(src.contains("Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background."),
        "FIDO-15: Footer helper text must match UI-SPEC Copywriting Contract verbatim")
}
```

**Run-Script dependency:** `SettingsView.swift` is already copied into the test bundle by the existing "Copy Shared Sources For Isolation Tests" Run-Script phase (see `SettingsViewTests.swift:11-17` doc-comment). No build-phase edit needed for SettingsView; FIDO-13 grep for `startAutoRefresh` deletion will require adding `CodeApprovalView.swift` to the same Run-Script (RESEARCH line 724-726).

---

### `.planning/REQUIREMENTS.md` (MODIFIED — register FIDO-01..FIDO-19)

**Analog format** (from `.planning/REQUIREMENTS.md:56-` — iCloud Keychain Sync block):
```markdown
### iCloud Keychain Sync

- [x] **ICLOUD-01**: `KeychainManager.save` accepts a `synchronizable: Bool` parameter and sets `kSecAttrSynchronizable` accordingly on SecItemAdd
- [x] **ICLOUD-02**: All Keychain read queries (`loadAll`, `load`) include `kSecAttrSynchronizable: kSecAttrSynchronizableAny` so both synced and non-synced items are matched
```

**Apply to Phase 7:** Add a `### FaceID Capability Tokens` section after `### iCloud Keychain Sync`, with `[ ] **FIDO-01**:` through `[ ] **FIDO-19**:` rows per the RESEARCH §Phase Requirements table at lines 70-91. Use `- [ ]` (unchecked) — checker will flip to `[x]` during verification.

## Shared Patterns

### Authentication (Biometric Gate)

**Source:** `Shared/BiometricAuthManager.swift` (lines 26-46) — unchanged, already singleton.

**Apply to:** `CodeApprovalView.approveAndSend` (already calls this; Phase 7 adds mint *after* success). No other Phase 7 code calls `BiometricAuthManager` directly.

```swift
// BiometricAuthManager.swift:26-34 — full public API, used as-is
func authenticate(reason: String = "Unlock KeyAuth") async -> Bool {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Passcode"
    do {
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    } catch {
        // Fall back to device passcode (CONTEXT 02 D-08)
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch { return false }
    }
}
```

**Phase 7 contract:** `TrustWindowManager.mint()` is called iff `authenticate()` returned `true` AND `TrustWindowPreference.isEnabled` AND is placed inside the `approveAndSend` flow (CodeApprovalView.swift line 198 post-replacement).

---

### Account Resolution Helper (shared between FaceID path and silent-send path)

**Source:** `App/Views/CodeApprovalView.swift` lines 146-158 (`onAppear` matching logic) — currently inlined inside the view.

**Apply to Phase 7 per RESEARCH §Pattern 2:** Extract to `AccountStore.resolve(for:)` extension (either in `Shared/AccountStore.swift` or a new `Shared/AccountResolver.swift`). Update BOTH call sites in the same commit:

**Existing logic to extract** (`CodeApprovalView.swift:146-158`):
```swift
.onAppear {
    if !needsAccountPicker {
        // Exact issuer/label match
        selectedAccount = store.accounts.first(where: {
            $0.issuer == request.issuer && $0.label == request.label
        })
    } else if domainMatchedAccounts.count == 1 {
        // Single domain match -- auto-select
        selectedAccount = domainMatchedAccounts.first
    } else if store.accounts.count == 1 {
        // Only one account total -- auto-select
        selectedAccount = store.accounts.first
    }
}
```

**Refactored extension** (source — RESEARCH Code Examples line 326-350):
```swift
// New: Shared/AccountStore.swift extension OR Shared/AccountResolver.swift
extension AccountStore {
    /// Deterministic account resolution for a CodeRequest.
    /// Returns nil when ambiguous (multiple matches AND no exact issuer+label).
    /// Matches CodeApprovalView.onAppear semantics (extracted in Phase 7).
    func resolve(for request: CodeRequest) -> Account? {
        if !request.issuer.isEmpty || !request.label.isEmpty {
            return accounts.first { $0.issuer == request.issuer && $0.label == request.label }
        }
        if let domain = request.domain, !domain.isEmpty {
            let domainLower = domain.lowercased()
            let matched = accounts.filter { account in
                let issuerLower = account.issuer.lowercased()
                return domainLower.contains(issuerLower)
                    || issuerLower.contains(domainLower.replacingOccurrences(of: ".com", with: ""))
            }
            if matched.count == 1 { return matched[0] }
            if matched.count > 1 { return nil }
        }
        if accounts.count == 1 { return accounts[0] }
        return nil
    }
}
```

**Used by:**
- `RelayClient.silent-send branch` via the injected `accountResolver: ((CodeRequest) -> Account?)?` closure (wired from `KeyAuthApp.onAppear`).
- `CodeApprovalView.onAppear` (replace the in-line chain with `selectedAccount = store.resolve(for: request)`).

**Anti-pattern warning (RESEARCH line 412):** Do NOT refactor the extraction without updating BOTH call sites in the same task — semantic drift between the two paths would produce silent bugs where FaceID and silent-send disagree on which account to use.

---

### Error Handling — Fire-and-Forget WebSocket Send

**Source:** `Shared/RelayClient.swift:106-117` + `:81-89` (`send`/`sendEncryptedCode` — fire-and-forget callback-error pattern).

**Apply to:** Silent-send branch calls `sendEncryptedCode` without awaiting. Toast fires immediately (RESEARCH Pitfall 5 + Open Question 2 — match existing `CodeApprovalView.approveAndSend` semantics). Any send failure is logged via the existing `print("[RelayClient] Send error: …")` path inside `send(_:)`.

**Do NOT change `sendEncryptedCode` signature** — RESEARCH calls this out as scope creep.

---

### Test-Bundle Source Loading (grep-based View tests)

**Source:** `KeyAuthTests/SettingsViewTests.swift:25-38` — `loadBundledSource(named:)` helper.

**Apply to:** Any Phase 7 test that needs to grep-assert source literal presence (FIDO-13 `startAutoRefresh` deletion, FIDO-15 toggle literal, FIDO-08 mint() call site). Mirrors STATE.md line 108 & line 120 Phase 6 precedent.

**Caveat:** The "Copy Shared Sources For Isolation Tests" Run-Script build phase must be extended to include `App/Views/CodeApprovalView.swift` so FIDO-13's grep-test can read the source inside the sandbox. This is a `project.pbxproj` edit via the Ruby `xcodeproj` gem (STATE.md line 108 pattern).

## No Analog Found

None. All Phase 7 files map to at least one close in-repo analog. The only *partial* match is `KeyAuthTests/RelayClientSilentSendTests.swift` — no pre-existing `RelayClient` tests — but the dependency-injection test pattern from `AccountStoreTests.swift` and the proposed `accountResolver` closure (mirroring `RelayClient.onConnected`) give the planner everything needed.

## Metadata

**Analog search scope:**
- `/Users/yashesh/Documents/indrive-screens/keyboardauth/KeyAuth/Shared/` (16 files)
- `/Users/yashesh/Documents/indrive-screens/keyboardauth/KeyAuth/App/` (6 files + 14 views)
- `/Users/yashesh/Documents/indrive-screens/keyboardauth/KeyAuth/KeyAuthTests/` (12 files + Fixtures + Mocks)
- `/Users/yashesh/Documents/indrive-screens/keyboardauth/KeyAuth/.planning/` (REQUIREMENTS.md, STATE.md, ROADMAP.md, Phase 7 context/research/ui-spec)

**Files scanned:** 48

**Pattern extraction date:** 2026-04-19

**Upstream inputs consulted:**
- `.planning/phases/07-faceid-capability-tokens/07-CONTEXT.md` (17 locked decisions D-01..D-17 + Claude's Discretion + Deferred)
- `.planning/phases/07-faceid-capability-tokens/07-RESEARCH.md` (FIDO-01..FIDO-19, Patterns 1-3, 8 Pitfalls, Security Domain)
- `.planning/phases/07-faceid-capability-tokens/07-UI-SPEC.md` (Component Inventory: 2 items, Copywriting Contract verbatim strings, toast + toggle behavior)
- `.planning/STATE.md` (Phase 6 decisions, Ruby xcodeproj gem pattern, Plan 06 test-bundle-source loader precedent)
- `.planning/ROADMAP.md` Phase 7 entry lines 124-138
