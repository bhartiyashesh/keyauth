# Coding Conventions

**Analysis Date:** 2026-04-14

## Naming Patterns

**Files:**
- One type per file; file name matches the primary type it contains
- Views: `{Name}View.swift` — e.g., `AccountRowView.swift`, `LockScreenView.swift`
- UIKit cells: `{Name}Cell.swift` — e.g., `TOTPCodeCell.swift`
- Service/managers: `{Name}Manager.swift` — e.g., `KeychainManager.swift`, `BiometricAuthManager.swift`
- Utility namespaces: noun-only — e.g., `Base32.swift`, `SharedDefaults.swift`
- Data models: noun-only — e.g., `Account.swift`, `AccountStore.swift`

**Types:**
- `UpperCamelCase` for all type declarations (structs, classes, enums, protocols)
- Enums used as namespaces (no cases, only static members): `TOTPGenerator`, `Base32`, `SharedDefaults`
- Error types named `{Domain}Error` — e.g., `KeychainError`
- Simple value types named for their purpose: `BiometricType`, `OTPAlgorithm`

**Properties and Methods:**
- `lowerCamelCase` for all properties and functions
- Private helpers are always explicitly marked `private`
- Computed view-builder properties use `private var {name}: some View`
- Callback closure parameters named semantically: `onUnlock`, `onSave`, `onScanned`, `onCodeDetected`

**Constants:**
- `lowerCamelCase` for private static let values
- Bundle identifiers and suite names as string literals on the declaring type

## Type Design

**Value types for data models:**
- `Account` is a `struct` conforming to `Codable`, `Identifiable`, `Equatable`
- Enums serve as namespaces for stateless utilities (`TOTPGenerator`, `Base32`, `SharedDefaults`)

**Reference types for stateful services:**
- `final class` for singletons: `KeychainManager`, `BiometricAuthManager`
- `final class` for observable store: `AccountStore`
- UIKit types use `class` (`KeyboardViewController`, `TOTPCodeCell`)

**Singleton pattern:**
```swift
final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}
}
```
Used by `KeychainManager` (`Shared/KeychainManager.swift`) and `BiometricAuthManager` (`Shared/BiometricAuthManager.swift`).

**Enum namespace pattern (no instantiation):**
```swift
enum TOTPGenerator {
    static func generate(for account: Account, at date: Date = Date()) -> String? { ... }
    private static func hmacSHA(...) -> Data? { ... }
}
```
Used by `TOTPGenerator` (`Shared/TOTPGenerator.swift`), `Base32` (`Shared/Base32.swift`), and `SharedDefaults` (`Shared/SharedDefaults.swift`).

## Access Control

- All internal implementation details are explicitly `private`
- No `public` or `open` modifiers anywhere (internal access is implicit default)
- Singleton `init` is always `private init() {}`
- Helper functions within service types are `private func`
- Computed view sub-components are `private var`
- `final` applied to all class types that are not designed for subclassing

## SwiftUI Conventions

**View composition:**
- Each View is a `struct` in its own file under `App/Views/`
- Complex views extract sub-views as `private var` computed properties returning `some View`
- Example from `ContentView.swift`:
  ```swift
  private var emptyState: some View {
      VStack(spacing: 20) { ... }
  }
  ```

**State management:**
- `@State private var` for all local mutable state
- `@StateObject private var` for owned observable objects (app root only)
- `@EnvironmentObject var` (no access modifier) for injected store in child views
- `@Environment(\.dismiss) private var dismiss` for sheet dismissal

**Callbacks via closures:**
- Sheets receive completion callbacks as `let on{Action}: (Type) -> Void` or `var on{Action}: () -> Void`
- No delegates or NotificationCenter used within SwiftUI layer (except one background notification in `KeyAuthApp.swift`)

**Timer pattern in views:**
```swift
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
// Used with .onReceive(timer) { _ in updateCode() }
```
Used in `AccountRowView.swift`.

**Conditional availability:**
```swift
if #available(iOS 17.0, *) {
    Image(systemName: ...).symbolEffect(.pulse, options: .repeating)
} else {
    Image(systemName: ...)
}
```
Used in `LockScreenView.swift` for symbol effects.

## UIKit Conventions (Keyboard Extension)

**Lazy initialization for UI elements:**
```swift
private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    // configure...
    return cv
}()
```
All UI properties in `KeyboardViewController` (`KeyboardExtension/KeyboardViewController.swift`) use `private lazy var` with closure initializers.

**MARK sections for organization:**
```swift
// MARK: - State
// MARK: - UI Elements
// MARK: - Lifecycle
// MARK: - Data
// MARK: - UI Setup
// MARK: - UICollectionView (extension)
// MARK: - UIInputViewAudioFeedback (extension)
```

**Protocol conformance in extensions:**
- `UICollectionViewDataSource` and `UICollectionViewDelegateFlowLayout` implemented in a single `extension KeyboardViewController`
- `UIInputViewAudioFeedback` in a separate extension

**Auto Layout:**
- Exclusively programmatic `NSLayoutConstraint.activate([...])` — no Storyboards or XIBs
- All views set `translatesAutoresizingMaskIntoConstraints = false`

**UICollectionViewCell pattern:**
- `final class` cells
- `static let reuseID = "TOTPCodeCell"` for dequeue identifier
- `configure(with:)` method for data binding
- `refreshDisplay()` for timer-driven updates
- `required init?(coder:)` always contains `fatalError("init(coder:) has not been implemented")`

## Import Organization

Single blank-line separation between import groups. No alphabetical enforcement observed — framework imports appear in dependency order.

**App target:**
```swift
import SwiftUI
import AVFoundation   // only where camera is used
```

**Keyboard extension:**
```swift
import UIKit
```

**Shared layer:**
```swift
import Foundation
import CommonCrypto   // TOTPGenerator only
import Security       // KeychainManager only
import LocalAuthentication  // BiometricAuthManager only
import Combine        // AccountStore only
```

## Error Handling

**Three distinct strategies used:**

**1. Throwing with typed errors (Keychain operations):**
- `KeychainManager` methods all `throws`
- Custom `KeychainError: LocalizedError` with associated `OSStatus` values
- Callers in `AccountStore` wrap with `do/catch`, set `self.error: String?` with `error.localizedDescription`

```swift
// Shared/KeychainManager.swift
func save(_ account: Account) throws {
    ...
    throw KeychainError.saveFailed(insertStatus)
}

// Shared/AccountStore.swift
do {
    try keychain.save(newAccount)
    reload()
} catch {
    self.error = error.localizedDescription
}
```

**2. Optional returns for recoverable absence (parsing/crypto):**
- `Base32.decode(_:) -> Data?` — returns `nil` for invalid input
- `TOTPGenerator.generate(...) -> String?` — returns `nil` on decode failure
- `Account.from(otpauthURL:) -> Account?` — returns `nil` for malformed URLs
- `KeychainManager.load(id:) -> Account?` — returns `nil` for not-found

**3. Silent discard with `try?` for best-effort operations:**
- `SharedDefaults.saveAccounts(_:)` uses `try? JSONEncoder().encode(...)`
- `AccountStore.delete(at:)` and `move(from:to:)` use `try? keychain.delete/save` for individual operations during bulk loops

**Error surface to UI:**
- `AccountStore.error: String?` (`@Published`) propagates errors to SwiftUI views
- `ManualEntryView` and `QRScannerView` use local `@State private var error: String?`
- Errors displayed inline as red `Text(error)` with `.foregroundStyle(.red)`

## Concurrency

**Swift Concurrency (`async/await`):**
- `BiometricAuthManager.authenticate()` is `async -> Bool`
- `LockScreenView.performAuth()` is `@MainActor private func performAuth() async`
- Called via `Task { await performAuth() }` from button, and via `.task { await performAuth() }` on appear

**`AccountStore` is fully `@MainActor`:**
```swift
@MainActor
final class AccountStore: ObservableObject { ... }
```

**Mixed dispatch in UIViewRepresentable bridge (`QRScannerView.swift`):**
- Camera session started on `DispatchQueue.global(qos: .userInitiated).async`
- Metadata delegate callbacks arrive on `.main` queue (explicitly set)

**Timer-based UI updates:**
- SwiftUI: Combine `Timer.publish` + `.onReceive`
- UIKit: `Timer.scheduledTimer` with `[weak self]` capture, invalidated in `viewDidDisappear`

## Comments

**When comments appear:**
- `/// Doc comments` on public-facing static factory methods: `/// Parse otpauth://totp/...` in `Account.swift`
- `/// Single-line doc` on static utility functions in `TOTPGenerator.swift`
- Inline `// RFC 4226` reference for the dynamic truncation algorithm
- `// MARK: - Section` used consistently throughout UIKit files
- Brief `// Top bar:` / `// Code` inline labels inside complex AutoLayout blocks

**No comments** in SwiftUI view bodies or on straightforward CRUD methods.

## Code Formatting

No linter config files detected (no `.swiftlint.yml`, `Xcode formatting settings`, or SwiftFormat config). Style is consistent throughout and appears enforced by Xcode default formatting:
- 4-space indentation
- Opening braces on same line
- Trailing commas in multi-line arrays and argument lists
- Blank line between each major section within a type

---

*Convention analysis: 2026-04-14*
