# Architecture

**Analysis Date:** 2026-04-14

## Pattern Overview

**Overall:** Two-target iOS app with shared code layer

The project consists of two separate Xcode targets that compile the same `Shared/` directory:
- `KeyAuth` (SwiftUI companion app) — account management, biometric auth, QR/manual entry
- `KeyAuthKeyboard` (UIKit keyboard extension) — read-only TOTP display with one-tap code insertion

Both targets share data through two OS-level channels: a shared Keychain access group and an App Group UserDefaults suite. The keyboard extension never writes to the keychain; it only reads a serialized snapshot written by the app via `SharedDefaults`.

**Key Characteristics:**
- No networking — all computation is local (TOTP is a pure function of secret + time)
- No third-party dependencies — zero SPM/CocoaPods packages; relies only on system frameworks (`CommonCrypto`, `LocalAuthentication`, `AVFoundation`, `Security`)
- The keyboard extension uses `RequestsOpenAccess: false`, meaning it cannot access the keychain directly at runtime; it reads the App Group UserDefaults snapshot written by the main app
- Authentication is enforced in the app only — the keyboard extension has no auth gate

## Layers

**Model (Shared):**
- Purpose: Defines the core `Account` data type and its serialization/parsing
- Location: `Shared/Account.swift`
- Contains: `Account` struct (Codable, Identifiable, Equatable), `OTPAlgorithm` enum, `otpauth://` URL parser
- Depends on: `Shared/Base32.swift` (for secret validation during URL parsing)
- Used by: Both targets

**Crypto (Shared):**
- Purpose: Pure TOTP/HMAC computation and Base32 decoding
- Location: `Shared/TOTPGenerator.swift`, `Shared/Base32.swift`
- Contains: RFC 4226 HOTP + RFC 6238 TOTP algorithm; SHA-1/256/512 HMAC via CommonCrypto; dynamic truncation
- Depends on: `CommonCrypto` system framework, `Shared/Account.swift`
- Used by: `App/Views/AccountRowView.swift`, `KeyboardExtension/TOTPCodeCell.swift`, `KeyboardExtension/KeyboardViewController.swift`

**Persistence (Shared):**
- Purpose: Durable account storage (Keychain) and cross-target data bridge (App Group UserDefaults)
- Location: `Shared/KeychainManager.swift`, `Shared/SharedDefaults.swift`
- Contains: Full CRUD over Keychain (`kSecClassGenericPassword`, service `com.keyauth.accounts`, access group `W646UCTVQV.com.keyauth.shared`); read/write of JSON-encoded `[Account]` to App Group suite `group.com.keyauth.shared`
- Depends on: `Security` framework, `Shared/Account.swift`
- Used by: `Shared/AccountStore.swift` (Keychain + SharedDefaults write), `KeyboardExtension/KeyboardViewController.swift` (SharedDefaults read only)

**Auth (Shared):**
- Purpose: Biometric/passcode authentication gate
- Location: `Shared/BiometricAuthManager.swift`
- Contains: `BiometricAuthManager` singleton wrapping `LAContext`; detects Face ID / Touch ID availability; falls back to device passcode on biometric failure
- Depends on: `LocalAuthentication` framework
- Used by: `App/Views/LockScreenView.swift` only

**Store (Shared, App-only runtime):**
- Purpose: Observable account state for SwiftUI binding
- Location: `Shared/AccountStore.swift`
- Contains: `@MainActor` `ObservableObject` that wraps Keychain CRUD and keeps `SharedDefaults` in sync after every mutation
- Depends on: `Shared/KeychainManager.swift`, `Shared/SharedDefaults.swift`
- Used by: `App/KeyAuthApp.swift` (injected as `@StateObject`, passed via `@EnvironmentObject`)

**App UI (App target — SwiftUI):**
- Purpose: All user-facing screens for the companion app
- Location: `App/Views/`
- Contains: `ContentView`, `LockScreenView`, `AccountRowView`, `QRScannerView`, `ManualEntryView`
- Depends on: `Shared/AccountStore.swift`, `Shared/TOTPGenerator.swift`, `Shared/BiometricAuthManager.swift`, `AVFoundation`
- Used by: `App/KeyAuthApp.swift`

**Keyboard UI (KeyboardExtension target — UIKit):**
- Purpose: System keyboard extension displaying live TOTP codes
- Location: `KeyboardExtension/`
- Contains: `KeyboardViewController` (UIInputViewController), `TOTPCodeCell` (UICollectionViewCell with CAShapeLayer countdown ring)
- Depends on: `Shared/SharedDefaults.swift`, `Shared/TOTPGenerator.swift`, `Shared/Account.swift`
- Used by: iOS system keyboard infrastructure

## Data Flow

**Account Registration (QR Scan):**
1. User opens `QRScannerView` → `AVCaptureSession` detects QR metadata
2. `QRCameraPreview.Coordinator` calls `onCodeDetected(_:)` with raw string
3. `QRScannerView.handleCode(_:)` parses `otpauth://totp/...` URL via `Account.from(otpauthURL:)`
4. `Base32.decode` validates the secret during parse
5. Parsed `Account` passed to `store.add(_:)` via callback
6. `AccountStore.add` calls `KeychainManager.shared.save(_:)`, then `reload()`
7. `reload()` calls `SharedDefaults.saveAccounts(_:)` — JSON snapshot written to App Group UserDefaults

**Account Registration (Manual Entry):**
1. User fills `ManualEntryView` form
2. `save()` validates Base32 secret, constructs `Account`, calls `onSave` callback
3. Same path as steps 5-7 above

**TOTP Display in App:**
1. `AccountRowView` subscribes to a 1-second `Timer.publish` on `.main`
2. On each tick: calls `TOTPGenerator.generate(for:at:)` and `TOTPGenerator.secondsRemaining(period:at:)`
3. `TOTPGenerator` decodes Base32 secret → computes HMAC-SHA(counter) → dynamic truncation → mod 10^digits
4. Countdown ring animates via SwiftUI `.trim` modifier driven by `progress` computed property

**TOTP Display in Keyboard Extension:**
1. `KeyboardViewController.viewDidLoad` calls `SharedDefaults.loadAccounts()` — reads JSON snapshot from App Group UserDefaults
2. `startTimer()` fires a `Timer` every 1 second, calling `TOTPCodeCell.refreshDisplay()` on each visible cell
3. `refreshDisplay()` calls `TOTPGenerator.generate(for:at:)` directly
4. On cell tap: `didSelectItemAt` generates code and calls `textDocumentProxy.insertText(code)` — code is typed into the host app

**State Management:**
- App: `AccountStore` is the single source of truth, held as `@StateObject` in `KeyAuthApp`, distributed via `@EnvironmentObject`
- Keyboard: stateless pull — reads `SharedDefaults` on `viewWillAppear`, holds `[Account]` locally as a plain array
- No reactive bridge between targets — keyboard polls snapshot on appearance

## Key Abstractions

**`Account` struct:**
- Purpose: Canonical TOTP credential model
- Examples: `Shared/Account.swift`
- Pattern: Value type (`struct`), `Codable` for JSON serialization into both Keychain and UserDefaults, `Identifiable` for SwiftUI `ForEach`; includes static factory `from(otpauthURL:)` for QR parsing

**`TOTPGenerator` enum:**
- Purpose: Pure stateless TOTP computation namespace
- Examples: `Shared/TOTPGenerator.swift`
- Pattern: Caseless `enum` used as namespace (no instances); two `generate` overloads — one taking `Account`, one taking raw parameters; `secondsRemaining` helper for UI countdowns

**`KeychainManager` singleton:**
- Purpose: Durable encrypted account storage
- Examples: `Shared/KeychainManager.swift`
- Pattern: Shared singleton (`static let shared`), `private init()`; throws typed `KeychainError` enum; stores each account as a separate Keychain item keyed by `UUID.uuidString`

**`SharedDefaults` enum:**
- Purpose: Cross-target data bridge
- Examples: `Shared/SharedDefaults.swift`
- Pattern: Caseless `enum` used as namespace; writes full `[Account]` JSON snapshot to App Group suite `group.com.keyauth.shared`; keyboard reads this snapshot (no Keychain access needed in extension)

**`AccountStore` class:**
- Purpose: SwiftUI-observable account state with Keychain-backed persistence
- Examples: `Shared/AccountStore.swift`
- Pattern: `@MainActor final class`, `ObservableObject`; every mutating operation (add/delete/move) writes to Keychain then calls `reload()` which re-reads Keychain and syncs `SharedDefaults`

## Entry Points

**App Target:**
- Location: `App/KeyAuthApp.swift`
- Triggers: iOS app launch (`@main`)
- Responsibilities: Creates `AccountStore` as `@StateObject`; guards all content behind `LockScreenView`; re-locks on `UIApplicationDidEnterBackgroundNotification`

**Keyboard Extension:**
- Location: `KeyboardExtension/KeyboardViewController.swift`
- Triggers: iOS system when user activates the KeyAuth keyboard
- Responsibilities: Loads accounts from `SharedDefaults`; lays out `UICollectionView` of `TOTPCodeCell`; manages 1-second refresh timer; inserts code via `textDocumentProxy` on cell tap

## Error Handling

**Strategy:** Throw/catch with typed errors in the persistence layer; surface errors as `@Published var error: String?` on `AccountStore`; UI shows inline error text only in form views

**Patterns:**
- `KeychainManager` throws `KeychainError` (typed enum with `OSStatus` payload); all 4 CRUD operations throw
- `AccountStore` catches all Keychain errors and sets `self.error`; mutations that fail leave existing state intact
- `TOTPGenerator` returns `String?` (nil on Base32 decode failure); callers substitute `"------"` as the display fallback
- `BiometricAuthManager.authenticate` returns `Bool` via `async`; never throws; swallows `LAError` internally and falls back to device passcode
- `SharedDefaults` functions never throw — encode/decode failures are silently dropped; keyboard shows empty state if no accounts are available

## Cross-Cutting Concerns

**Logging:** None — no logging framework or `os_log` calls anywhere in the codebase
**Validation:** `Account.from(otpauthURL:)` validates Base32 secret, digit count (6/7/8), and period (10-120s); `ManualEntryView.save()` validates Base32 before constructing `Account`
**Authentication:** Enforced at app launch only (`LockScreenView` + `BiometricAuthManager`); re-engaged on background; keyboard extension has no auth gate (relies on device lock screen)

---

*Architecture analysis: 2026-04-14*
