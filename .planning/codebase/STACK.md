# Technology Stack

**Analysis Date:** 2026-04-14

## Languages

**Primary:**
- Swift 5.9 - All application code across both targets

**Secondary:**
- None

## Runtime

**Environment:**
- iOS 16.0+ (deployment target set in `project.yml`)
- Xcode 15.0 (minimum version declared in `project.yml`)

**Package Manager:**
- No third-party package manager (no SPM, CocoaPods, or Carthage)
- All dependencies are Apple system frameworks only
- Lockfile: Not applicable

## Frameworks

**Core (Main App Target - `KeyAuth`):**
- SwiftUI - All UI in the companion app (`App/Views/`)
- Combine - Reactive state management via `@Published` in `Shared/AccountStore.swift`
- AVFoundation - Camera access for QR code scanning in `App/Views/QRScannerView.swift`

**Core (Keyboard Extension Target - `KeyAuthKeyboard`):**
- UIKit - All UI in the keyboard extension (`KeyboardExtension/`)
  - `UIInputViewController` as root controller
  - `UICollectionView` with `UICollectionViewFlowLayout` for TOTP code list
  - `CAShapeLayer` for animated countdown rings

**Security:**
- Security framework - Raw Keychain API via `Shared/KeychainManager.swift`
  - `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`
  - `kSecClassGenericPassword` items with `kSecAttrAccessibleAfterFirstUnlock`
- LocalAuthentication - Face ID / Touch ID / passcode fallback via `Shared/BiometricAuthManager.swift`
  - `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`
  - Falls back to `.deviceOwnerAuthentication` (passcode)
- CommonCrypto - HMAC-SHA1/256/512 for TOTP generation in `Shared/TOTPGenerator.swift`
  - `CCHmac` with `kCCHmacAlgSHA1`, `kCCHmacAlgSHA256`, `kCCHmacAlgSHA512`

**Data Sharing:**
- Foundation (`UserDefaults` with App Group suite) - Cross-process data sharing via `Shared/SharedDefaults.swift`
  - Suite name: `group.com.keyauth.shared`

**Build/Dev:**
- XcodeGen - Project file generation from `project.yml` (no `.xcodeproj` is hand-maintained)

## Key Dependencies

**Critical (all Apple system frameworks — zero third-party):**
- `CommonCrypto` - TOTP HMAC computation; removing would break code generation entirely
- `Security` - Keychain storage; all secrets live here
- `LocalAuthentication` - App lock screen gating
- `AVFoundation` - QR code onboarding flow

## Configuration

**Build:**
- Project definition: `project.yml` (XcodeGen source of truth)
- Swift version: 5.9 (set globally in `project.yml` → `SWIFT_VERSION`)
- Deployment target: iOS 16.0
- Development Team: `W646UCTVQV` (hardcoded in `project.yml`)
- Keychain access group: `W646UCTVQV.com.keyauth.shared` (hardcoded in `Shared/KeychainManager.swift`)

**Entitlements:**
- App: `App/KeyAuth.entitlements`
  - App Group: `group.com.keyauth.shared`
  - Keychain Access Group: `$(AppIdentifierPrefix)com.keyauth.shared`
- Keyboard Extension: `KeyboardExtension/KeyAuthKeyboard.entitlements`
  - Same App Group and Keychain Access Group as the main app

**Info.plist values (declared in `project.yml`):**
- `NSFaceIDUsageDescription` - Required for Face ID
- `NSCameraUsageDescription` - Required for QR scanner

## Platform Requirements

**Development:**
- macOS with Xcode 15.0+
- XcodeGen CLI (to regenerate `KeyAuth.xcodeproj` from `project.yml`)
- Apple Developer account with Team ID `W646UCTVQV`

**Production:**
- iOS 16.0+ device
- Supported device family: iPhone only (`TARGETED_DEVICE_FAMILY: "1"`)
- Bundle IDs:
  - Main app: `com.keyauth.app`
  - Keyboard extension: `com.keyauth.app.keyboard`
- App extension type: `com.apple.keyboard-service` (custom keyboard)
- `RequestsOpenAccess: false` — keyboard runs in restricted sandbox with no network access

---

*Stack analysis: 2026-04-14*
