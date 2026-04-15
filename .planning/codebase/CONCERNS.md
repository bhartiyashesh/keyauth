# Codebase Concerns

**Analysis Date:** 2026-04-14

---

## Security Considerations

**TOTP secrets stored in SharedDefaults (plaintext exposure):**
- Risk: `Account` is `Codable` and the full `secret` field (Base32 plaintext) is serialized into `UserDefaults` via `SharedDefaults.saveAccounts`. App Groups UserDefaults are stored unencrypted in the container filesystem at `~/Library/Group Containers/group.com.keyauth.shared/Library/Preferences/`. Any app with access to the device filesystem (e.g., via iTunes backup without encryption, MDM tools, or a jailbroken device) can read TOTP secrets.
- Files: `Shared/SharedDefaults.swift`, `Shared/Account.swift`, `Shared/AccountStore.swift:23`
- Current mitigation: None — secrets flow freely into UserDefaults on every `reload()` call.
- Recommendation: Store only account metadata (issuer, label, id) in SharedDefaults. The keyboard extension should read secrets directly from the shared Keychain (it already has `keychain-access-groups` entitlement). Alternatively, encrypt the SharedDefaults payload before writing.

**Keychain items accessible after first unlock, not when unlocked:**
- Risk: `kSecAttrAccessibleAfterFirstUnlock` is used for all new Keychain insertions. This accessibility class allows the Keychain item to be read by background processes after the first device unlock — it does not require the device to be actively unlocked. For a 2FA secrets store this is a broader exposure than necessary.
- Files: `Shared/KeychainManager.swift:32`
- Current mitigation: Biometric lock at the app layer provides some protection, but the Keychain itself is accessible to any process with the correct entitlement without the device being unlocked.
- Recommendation: Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for maximum security. The keyboard extension only runs when the device is actively in use (screen on, unlocked), so this restriction is compatible with the use case. The `ThisDeviceOnly` variant also prevents backup/migration of secrets.

**Keychain `accessGroup` hard-codes Team ID:**
- Risk: `KeychainManager` hard-codes `"W646UCTVQV.com.keyauth.shared"` as the `accessGroup`. This is a private Team ID in source code; if the app is transferred to another developer account or team, Keychain queries will silently fail (returning `errSecItemNotFound`) because the hard-coded group will not match the new provisioning.
- Files: `Shared/KeychainManager.swift:10`
- Current mitigation: Comment notes the issue but it is not resolved structurally.
- Recommendation: Replace the hard-coded string with `$(AppIdentifierPrefix)com.keyauth.shared` resolved at build time (as already done in the entitlements), or dynamically derive the prefix from the main bundle's `appIdentifierPrefix` property.

**TOTP codes copied to system pasteboard without expiry:**
- Risk: `UIPasteboard.general.string = code` writes a live TOTP code to the global pasteboard without setting an expiration date. The code remains accessible to all apps until overwritten. iOS 14+ allows setting `expirationDate` on pasteboard items.
- Files: `App/Views/AccountRowView.swift:119`
- Current mitigation: None.
- Recommendation: Use `UIPasteboard.general.setObjects([code as NSString], localOnly: false, expirationDate: Date().addingTimeInterval(30))` to match the TOTP validity window.

**Background notification uses raw string name (wrong API, and re-locks state never persists):**
- Risk: `KeyAuthApp.swift` observes `"UIApplicationDidEnterBackgroundNotification"` as a raw string. The correct `Notification.Name` is `UIApplication.didEnterBackgroundNotification` (a typed constant). The raw string version is fragile and will silently fail to fire if Apple ever changes the string value, leaving the app perpetually unlocked after backgrounding.
- Files: `App/KeyAuthApp.swift:21`
- Current mitigation: None — the raw string happens to match the underlying value today, but there is no compile-time safety.
- Recommendation: Replace with `.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))`.

---

## Tech Debt

**`AccountStore.move` calls `reload()` which overwrites sort orders just saved:**
- Issue: After `move(from:to:)` saves updated `sortOrder` values to the Keychain, it calls `reload()`, which reads back from the Keychain and then immediately calls `SharedDefaults.saveAccounts`. This is correct logically but creates an unnecessary double-write (Keychain save × N accounts + reload + SharedDefaults write) on every reorder, growing linearly with account count.
- Files: `Shared/AccountStore.swift:54–66`
- Impact: Performance degrades with many accounts; silently swallows errors via `try?` during the per-account save loop.

**`delete(at:)` silently swallows Keychain errors:**
- Issue: The swipe-to-delete path (`AccountStore.delete(at:)`) uses `try? keychain.delete(id:)` without surfacing any error. If a Keychain delete fails, `reload()` is still called and the UI will appear to succeed while the secret remains in the Keychain.
- Files: `Shared/AccountStore.swift:46–52`
- Impact: Data integrity — deleted accounts can reappear on next launch.

**`move` also uses `try?` for per-account saves:**
- Issue: During reorder, `try? keychain.save(account)` swallows errors silently for each account. If any save fails, sort order is corrupted without user feedback.
- Files: `Shared/AccountStore.swift:63`
- Impact: Sort order can diverge between in-memory state and persisted state.

**`SharedDefaults.synchronize()` is deprecated and unnecessary:**
- Issue: `UserDefaults.synchronize()` has been a no-op since iOS 12 and is formally deprecated. Its presence implies the developer was uncertain about write persistence.
- Files: `Shared/SharedDefaults.swift:14`
- Impact: No functional impact today, but generates a deprecation warning and is misleading.

**`loadAll()` in `KeychainManager` silently drops malformed records:**
- Issue: `compactMap { try? decoder.decode(Account.self, from: $0) }` discards any Keychain item that fails to decode (e.g., after a schema change to `Account`). There is no error reporting, so a future `Account` field addition that breaks backward-compat decoding will silently delete accounts from the user's view.
- Files: `Shared/KeychainManager.swift:77`
- Impact: Potential silent data loss on model schema migrations.

**Keyboard extension timer is started in `viewDidLoad` but not restarted after `viewWillAppear`:**
- Issue: `startTimer()` is only called in `viewDidLoad`. The timer is invalidated in `viewDidDisappear`. If the keyboard view controller's view is reloaded by the system (possible under memory pressure), `viewDidLoad` runs again and a second timer is created while the first may still be alive — leading to double refresh rates. However, more commonly, after `viewDidDisappear` the timer is killed and `viewWillAppear` does not restart it, so the countdown ring stops updating after the first hide/show cycle.
- Files: `KeyboardExtension/KeyboardViewController.swift:73,76,83,95`
- Impact: Countdown rings freeze after the keyboard is dismissed and re-shown within the same session.

**`viewWillAppear` calls `loadAccounts()` + `collectionView.reloadData()` but timer is not restarted:**
- Related to above. After the keyboard is shown again, data refreshes but the 1-second timer driving `refreshDisplay()` is gone, so codes and countdown rings become stale.
- Files: `KeyboardExtension/KeyboardViewController.swift:77–80`

---

## Known Bugs

**`UIScreen.main.bounds` used for camera preview layer frame (deprecated in iOS 16):**
- Symptoms: Camera preview may render at wrong size on multi-scene or multi-window environments.
- Files: `App/Views/QRScannerView.swift:103`
- `UIScreen.main` is deprecated starting iOS 16.0, which is exactly the deployment target. The preview layer should use `uiView.bounds` in `updateUIView` instead.
- Workaround: Currently `updateUIView` does update `previewLayer.frame = uiView.bounds` on subsequent layout passes, partially mitigating the initial wrong frame.

**`AVCaptureSession` not stopped on QR scanner dismiss:**
- Symptoms: Camera session started with `session.startRunning()` has no corresponding `session.stopRunning()` called when the sheet is dismissed. The `Coordinator` holds a strong reference to the session via `var session: AVCaptureSession?` but SwiftUI's `UIViewRepresentable` teardown does not guarantee `makeUIView`'s session is stopped.
- Files: `App/Views/QRScannerView.swift:83,107,141`
- Impact: Camera may remain running after the sheet closes, draining battery. On some iOS versions this also blocks other apps from using the camera.

**`scanned` flag prevents recovery from bad QR codes:**
- Symptoms: Once `scanned = true` is set (even momentarily), the scanner is permanently frozen and cannot scan again within the same sheet presentation. Since `scanned` is only set to `true` after a valid account is parsed (`Account.from(otpauthURL:)` succeeds), this is harmless currently — but the guard at the top of `handleCode` (`guard !scanned else { return }`) means a successful scan always dismisses without allowing retry.
- Files: `App/Views/QRScannerView.swift:56`

**`Account` `sortOrder` is set to `accounts.count` at add time, not thread-safely:**
- Symptoms: If two accounts are added rapidly (unlikely in practice), both may receive the same `sortOrder` value since `accounts.count` is read before the Keychain write and `reload()` completes.
- Files: `Shared/AccountStore.swift:27–28`

---

## Performance Bottlenecks

**Per-row timer in `AccountRowView` (N timers for N accounts):**
- Problem: Each `AccountRowView` creates its own `Timer.publish(every: 1, ...)`. With 20 accounts, 20 timers fire every second on the main thread, each calling `TOTPGenerator.generate` and `TOTPGenerator.secondsRemaining` independently.
- Files: `App/Views/AccountRowView.swift:10`
- Cause: Decentralized timer-per-view pattern instead of a single shared clock.
- Improvement path: Move the timer into `AccountStore` or a shared `ClockService` that publishes once per second, and have each row subscribe to the shared publisher. This reduces 20 timer callbacks to 1.

**`SharedDefaults.saveAccounts` encodes full account array (including secrets) on every single mutation:**
- Problem: Every `add`, `delete`, `move`, and `reload` triggers a full JSON encode and UserDefaults write of all accounts including their plaintext secrets.
- Files: `Shared/AccountStore.swift:23`, `Shared/SharedDefaults.swift:11–14`
- Cause: No diffing or partial update; the whole array is re-serialized each time.
- Improvement path: After resolving the security concern (secrets in SharedDefaults), encode only metadata needed by the extension.

---

## Fragile Areas

**Shared Keychain access group depends on provisioning profile matching entitlements:**
- Files: `Shared/KeychainManager.swift:10`, `App/KeyAuth.entitlements`, `KeyboardExtension/KeyAuthKeyboard.entitlements`
- Why fragile: The hard-coded string `"W646UCTVQV.com.keyauth.shared"` must exactly match the `keychain-access-groups` entitlement resolved by the provisioning profile. A mismatch causes all Keychain reads/writes to fail silently (returning `errSecMissingEntitlement` or `errSecItemNotFound`). This is a common source of "accounts disappeared" bugs after re-provisioning or signing changes.
- Safe modification: Always change both the `KeychainManager.accessGroup` constant AND both `.entitlements` files in lockstep. Verify with `security cms -D -i` on the embedded provisioning profile after build.
- Test coverage: None.

**Keyboard extension `loadAccounts()` has no fallback if `group.com.keyauth.shared` is unavailable:**
- Files: `KeyboardExtension/KeyboardViewController.swift:91–93`, `Shared/SharedDefaults.swift:7–9`
- Why fragile: `UserDefaults(suiteName:)` returns `nil` if the App Group entitlement is not provisioned. `SharedDefaults.suite` is `nil`-safe but silently returns an empty array, showing "No accounts" with no diagnostic. This is indistinguishable from the user genuinely having no accounts.
- Safe modification: Add a diagnostic flag or fallback error message distinguishing "no accounts" from "can't reach shared container."
- Test coverage: None.

**`TOTPCodeCell.refreshDisplay` called from a `Timer` closure without account nil-check beyond `guard let account`:**
- Files: `KeyboardExtension/TOTPCodeCell.swift:185`, `KeyboardExtension/KeyboardViewController.swift:97–99`
- Why fragile: The timer iterates `collectionView.visibleCells` and calls `refreshDisplay()` on each. If a cell has been dequeued and its `account` is nil (possible during rapid scrolling while reconfiguration is in progress), the guard returns early safely — but the timer itself has no reference to the collection view's data source state, so it fires even after `viewDidDisappear` if `displayTimer?.invalidate()` races with an in-flight callback.

**`Account.from(otpauthURL:)` accepts any period 10–120 but UI only offers 30 or 60:**
- Files: `Shared/Account.swift:86,90`, `App/Views/ManualEntryView.swift:48–49`
- Why fragile: QR-scanned accounts can have periods of 10, 15, 45, 90, etc. The `AccountRowView` timer and progress ring work with arbitrary periods correctly, but the `ManualEntryView` Picker hard-codes only 30s and 60s. Users cannot manually create accounts with non-standard periods.

---

## Scaling Limits

**Keyboard extension memory budget (~60 MB hard limit for `RequestsOpenAccess: false`):**
- Current capacity: Extension loads all `Account` objects from SharedDefaults into memory as a flat array. Each `Account` struct is small (~200 bytes serialized), so this is not a concern until thousands of accounts exist.
- Limit: iOS terminates keyboard extensions that exceed the memory limit without warning. The `UICollectionView` with cell reuse mitigates rendering cost, but the 1-second timer calling `refreshDisplay()` on all visible cells and the `CAShapeLayer` animations per cell add constant overhead.
- Scaling path: No pagination or lazy loading is implemented; the full account list is always in memory.

---

## Dependencies at Risk

**No third-party dependencies:**
- The project uses only Apple system frameworks (CommonCrypto, LocalAuthentication, AVFoundation, UIKit, SwiftUI). There are no dependency management files (no SPM `Package.swift`, no CocoaPods `Podfile`, no Carthage `Cartfile`). This is a strength for security but means all cryptographic primitives are the developer's own (Base32 decoder, TOTP generator) without external validation or testing.

---

## Missing Critical Features

**No iCloud Keychain / backup / restore:**
- Problem: `kSecAttrAccessibleAfterFirstUnlock` does NOT use `ThisDeviceOnly`, so items are technically eligible for iCloud Keychain sync — but no explicit `kSecAttrSynchronizable` key is set, meaning items are NOT synced by default. If a user gets a new device and restores from iCloud backup, TOTP secrets will not transfer (they are Keychain items without sync enabled).
- Blocks: User migration between devices requires re-scanning all QR codes.

**No account edit capability:**
- Problem: There is no way to edit an existing account's issuer, label, algorithm, or period after creation. The only mutations are delete and reorder.
- Files: `App/Views/ContentView.swift` (no edit navigation), `Shared/AccountStore.swift` (no update method)
- Blocks: Correcting mislabeled accounts.

**No biometric auth in keyboard extension:**
- Problem: The keyboard extension has `RequestsOpenAccess: false`, which means it cannot trigger biometric authentication. Any user who has the keyboard active can read and insert any TOTP code without authentication. The main app's biometric lock protects the app UI only, not the keyboard extension.
- Files: `KeyboardExtension/Info.plist:33`, `KeyboardExtension/KeyboardViewController.swift`
- Blocks: This is an architectural constraint of the iOS keyboard sandbox — it cannot be fully resolved without `RequestsOpenAccess: true`, which brings network access implications.

---

## Test Coverage Gaps

**Zero test files exist in the project:**
- What's not tested: Everything — TOTP generation correctness, Base32 decoding, Keychain CRUD, SharedDefaults round-trip, `Account.from(otpauthURL:)` URL parsing edge cases, `AccountStore` mutation logic.
- Files: All of `Shared/`, `App/`, `KeyboardExtension/`
- Risk: Silent regressions in TOTP code generation (wrong codes at period boundaries), Keychain data loss on schema changes, URL parsing failures for non-standard `otpauth://` URIs.
- Priority: High — `TOTPGenerator` and `Base32.decode` are pure functions with deterministic outputs and are straightforward to unit test against RFC 6238 test vectors. `Account.from(otpauthURL:)` has multiple parsing branches that are untested.

**TOTP boundary behavior untested:**
- What's not tested: Code generation at exactly `t = period` boundary (the counter rollover moment). Off-by-one in `floor(date.timeIntervalSince1970 / Double(period))` would produce wrong codes.
- Files: `Shared/TOTPGenerator.swift:25`
- Risk: Users get wrong codes at the exact second of rollover without knowing it.
- Priority: High.

**Keychain access group mismatch scenario untested:**
- What's not tested: Behavior when `accessGroup` does not match provisioning — `loadAll()` returns empty, `save()` throws, but the app shows an empty list with no error if `AccountStore.error` is not surfaced in the UI (which it currently is not — `ContentView` has no error banner).
- Files: `Shared/AccountStore.swift`, `App/Views/ContentView.swift`
- Risk: Users lose access to all accounts without any diagnostic message.
- Priority: Medium.

---

*Concerns audit: 2026-04-14*
