# Codebase Structure

**Analysis Date:** 2026-04-14

## Directory Layout

```
KeyAuth/                              # Project root
├── project.yml                       # XcodeGen project spec (source of truth for targets/schemes)
├── README.md                         # Project readme
├── KeyAuth.xcodeproj/                # Generated Xcode project (do not edit directly)
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/
│       └── KeyAuth.xcscheme
├── App/                              # KeyAuth app target sources
│   ├── KeyAuthApp.swift              # @main app entry point
│   ├── Info.plist                    # App target plist
│   ├── KeyAuth.entitlements          # App Group + Keychain entitlements
│   └── Views/                        # All SwiftUI views
│       ├── ContentView.swift         # Root account list screen
│       ├── LockScreenView.swift      # Biometric lock gate
│       ├── AccountRowView.swift      # Per-account TOTP row with live countdown
│       ├── QRScannerView.swift       # Camera QR scan + AVFoundation bridge
│       └── ManualEntryView.swift     # Manual secret entry form
├── KeyboardExtension/                # KeyAuthKeyboard extension target sources
│   ├── KeyboardViewController.swift  # UIInputViewController; main extension controller
│   ├── TOTPCodeCell.swift            # UICollectionViewCell with CAShapeLayer countdown ring
│   ├── Info.plist                    # Extension target plist
│   └── KeyAuthKeyboard.entitlements  # App Group + Keychain entitlements (mirrors App)
└── Shared/                           # Compiled into BOTH targets
    ├── Account.swift                 # Core TOTP credential model + otpauth:// parser
    ├── AccountStore.swift            # SwiftUI ObservableObject — account state + Keychain CRUD
    ├── KeychainManager.swift         # Keychain CRUD (kSecClassGenericPassword)
    ├── SharedDefaults.swift          # App Group UserDefaults bridge for extension data
    ├── TOTPGenerator.swift           # RFC 6238 TOTP computation (pure function)
    ├── BiometricAuthManager.swift    # LAContext wrapper for Face ID / Touch ID
    └── Base32.swift                  # Base32 decoder (RFC 4648)
```

## Directory Purposes

**`App/`:**
- Purpose: SwiftUI companion app — the only place users manage accounts
- Contains: App entry point, all SwiftUI `View` structs, app entitlements and Info.plist
- Key files: `App/KeyAuthApp.swift`, `App/Views/ContentView.swift`
- Framework: SwiftUI + `@StateObject` / `@EnvironmentObject` state model

**`App/Views/`:**
- Purpose: All screen-level SwiftUI views
- Contains: Five view structs; no sub-directories
- Key files: `AccountRowView.swift` (most complex view — live timer, copy, countdown ring)

**`KeyboardExtension/`:**
- Purpose: UIKit keyboard extension — read-only TOTP display with one-tap insertion
- Contains: `UIInputViewController` subclass, one custom `UICollectionViewCell`
- Key files: `KeyboardViewController.swift` (all layout, data loading, timer, tap handling)
- Framework: UIKit only; no SwiftUI

**`Shared/`:**
- Purpose: Code compiled into both targets via XcodeGen `sources` entries
- Contains: Model, persistence, crypto, auth utilities
- Constraint: Must not import any framework unavailable to app extensions; currently uses only `Foundation`, `Security`, `CommonCrypto`, `LocalAuthentication`
- Note: `AccountStore.swift` is in `Shared/` but only used by the App target at runtime (keyboard never instantiates it)

## Key File Locations

**Entry Points:**
- `App/KeyAuthApp.swift`: SwiftUI `@main` app struct; owns `AccountStore`; controls lock state
- `KeyboardExtension/KeyboardViewController.swift`: `UIInputViewController` subclass; extension lifecycle

**Configuration:**
- `project.yml`: XcodeGen project spec; defines both targets, their source paths, entitlements, bundle IDs, deployment target (iOS 16.0), and scheme
- `App/KeyAuth.entitlements`: App Group (`group.com.keyauth.shared`) and Keychain group (`W646UCTVQV.com.keyauth.shared`)
- `KeyboardExtension/KeyAuthKeyboard.entitlements`: Identical entitlements to app — required for shared Keychain access group

**Core Logic:**
- `Shared/TOTPGenerator.swift`: RFC 6238 TOTP + RFC 4226 HOTP; call `TOTPGenerator.generate(for:)` anywhere
- `Shared/Account.swift`: `Account` struct definition and `otpauth://` URL parser
- `Shared/AccountStore.swift`: All account mutation logic; must only be used in App target
- `Shared/KeychainManager.swift`: All Keychain I/O; singleton `KeychainManager.shared`
- `Shared/SharedDefaults.swift`: Cross-target data bridge; `SharedDefaults.saveAccounts` / `loadAccounts`

**Testing:**
- Not present — no test targets, no test files, no test configuration

## Naming Conventions

**Files:**
- Swift source files use `UpperCamelCase` matching the primary type they define: `AccountStore.swift`, `TOTPGenerator.swift`, `KeyboardViewController.swift`
- Entitlement files: `<TargetName>.entitlements` pattern: `KeyAuth.entitlements`, `KeyAuthKeyboard.entitlements`
- Plists: `Info.plist` in each target directory

**Directories:**
- Target source directories are `UpperCamelCase` nouns matching role: `App/`, `KeyboardExtension/`, `Shared/`
- Sub-directories within `App/` are `UpperCamelCase` by type: `Views/`

**Types:**
- Structs and classes: `UpperCamelCase` — `Account`, `KeychainManager`, `BiometricAuthManager`
- Enums used as namespaces: `UpperCamelCase` caseless enums — `TOTPGenerator`, `SharedDefaults`, `Base32`
- Enum cases: `lowerCamelCase` — `.sha1`, `.sha256`, `.faceID`, `.touchID`
- Error enum cases: `lowerCamelCase` with descriptive name — `.saveFailed`, `.loadFailed`

**Functions and Properties:**
- `lowerCamelCase` throughout: `loadAccounts()`, `refreshDisplay()`, `availableBiometric`, `secondsRemaining`
- Private helpers prefixed contextually: `setupUI()`, `baseQuery(for:)`, `handleCode(_:)`
- MARK comments used for section headers: `// MARK: - Data`, `// MARK: - UI Setup`, `// MARK: - CRUD`

## Where to Add New Code

**New Shared Utility (available to both targets):**
- Implementation: `Shared/<UtilityName>.swift`
- Must not import UIKit or SwiftUI — both targets must compile it

**New App Screen (SwiftUI View):**
- Implementation: `App/Views/<ScreenName>View.swift`
- Add navigation/presentation from `App/Views/ContentView.swift` or relevant parent view

**New Account Mutation Operation:**
- Add method to `Shared/AccountStore.swift`
- Call `keychain.save/delete` then call `reload()` at end to keep `SharedDefaults` in sync

**New Keyboard Extension UI Component:**
- Implementation: `KeyboardExtension/<ComponentName>.swift`
- UIKit only; wire into `KeyboardViewController.swift`

**New Entitlement/Capability:**
- Add to both `App/KeyAuth.entitlements` AND `KeyboardExtension/KeyAuthKeyboard.entitlements`
- Update `project.yml` entitlements sections for both targets

**XcodeGen Project Regeneration:**
- After editing `project.yml`, run `xcodegen generate` from project root to regenerate `KeyAuth.xcodeproj`

## Special Directories

**`.planning/`:**
- Purpose: GSD planning documents and codebase analysis
- Generated: No (hand-curated)
- Committed: Yes

**`KeyAuth.xcodeproj/`:**
- Purpose: Xcode project bundle; managed by XcodeGen from `project.yml`
- Generated: Yes (via `xcodegen generate`)
- Committed: Yes (common for iOS teams without SPM workspace)
- Note: `project.pbxproj` is the authoritative build graph; `project.yml` is the human-editable source

---

*Structure analysis: 2026-04-14*
