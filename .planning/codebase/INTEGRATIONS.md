# External Integrations

**Analysis Date:** 2026-04-14

## APIs & External Services

**None.** This app has zero network requests and no external API dependencies. All functionality is entirely on-device. The keyboard extension explicitly sets `RequestsOpenAccess: false` in `project.yml`, meaning it cannot make network calls even if the code attempted to.

## Data Storage

**Secrets / Account Data:**
- Type: iOS Keychain (`kSecClassGenericPassword`)
- Client: Raw Security framework (`Shared/KeychainManager.swift`)
- Service name: `com.keyauth.accounts`
- Access group: `W646UCTVQV.com.keyauth.shared` (shared between app and keyboard extension)
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock` — data survives device restart, accessible while device is unlocked or after first unlock post-boot
- Serialization: `JSONEncoder` / `JSONDecoder` on `Account` structs

**Cross-Process Cache (App → Keyboard Extension):**
- Type: `UserDefaults` with App Group suite
- Suite name: `group.com.keyauth.shared`
- Key: `shared_accounts`
- Client: `Shared/SharedDefaults.swift`
- Flow: `AccountStore` writes to `SharedDefaults` on every mutation; `KeyboardViewController` reads from `SharedDefaults` on every `viewWillAppear`
- Serialization: `JSONEncoder` / `JSONDecoder` on `[Account]`

**File Storage:**
- Local filesystem only: Not applicable (no file-based persistence)

**Caching:**
- No explicit cache layer beyond the `UserDefaults` App Group mirror described above

## Authentication & Identity

**Biometric / Device Auth:**
- Provider: Apple `LocalAuthentication` framework (`Shared/BiometricAuthManager.swift`)
- Supported: Face ID, Touch ID, device passcode fallback
- Trigger: App foreground — `LockScreenView` gates `ContentView` until auth succeeds
  (`App/KeyAuthApp.swift`, `App/Views/LockScreenView.swift`)
- Re-lock: App re-locks on `UIApplicationDidEnterBackgroundNotification`
- No custom auth server, tokens, or session management of any kind

## TOTP Standard Compliance

**Protocol:** RFC 6238 (TOTP) / RFC 4226 (HOTP base)
- Implementation: `Shared/TOTPGenerator.swift`
- Secret encoding: Base32 (RFC 4648), decoded in `Shared/Base32.swift`
- HMAC algorithms supported: SHA-1, SHA-256, SHA-512 (via `CommonCrypto`)
- Onboarding URI format: `otpauth://totp/` (Google Authenticator URI scheme), parsed in `Shared/Account.swift`

## Camera

**Framework:** `AVFoundation`
- Usage: QR code scanning during account setup (`App/Views/QRScannerView.swift`)
- Implementation: `AVCaptureSession` + `AVCaptureMetadataOutput` with `.qr` metadata type
- Permission: `NSCameraUsageDescription` declared in `project.yml`
- Scope: One-time per account addition; session stops immediately after a valid code is detected

## Monitoring & Observability

**Error Tracking:** None — no crash reporting or analytics SDK
**Logs:** No structured logging; errors are surfaced as `String?` on `AccountStore.error` published property
**Analytics:** None

## CI/CD & Deployment

**Hosting:** Not applicable (native iOS app; distributed via App Store or TestFlight)
**CI Pipeline:** None detected (no `.github/`, `.gitlab-ci.yml`, `Fastfile`, or similar)
**Signing:** Manual — hardcoded `DEVELOPMENT_TEAM: W646UCTVQV` in `project.yml`

## Environment Configuration

**Required env vars:** None — the app has no server-side configuration or API keys
**Secrets location:** All user secrets (TOTP seeds) are stored exclusively in the iOS Keychain at runtime; no secrets are present in source code except the Apple Team ID

## Webhooks & Callbacks

**Incoming:** None
**Outgoing:** None

---

*Integration audit: 2026-04-14*
