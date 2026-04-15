---
phase: 02-ios-relay-client-pairing
plan: 02
subsystem: ui, push-notifications
tags: [swiftui, apns, qr-scanner, x25519, pairing, uiapplicationdelegate]

requires:
  - phase: 02-ios-relay-client-pairing
    plan: 01
    provides: "CryptoBoxManager (X25519, ChaChaPoly), PairingStore (Keychain), RelayClient (WebSocket), relay protocol types"
provides:
  - "AppDelegate: APNs device token registration (hex encoded) and notification tap handling"
  - "Push Notifications entitlement (aps-environment=development)"
  - "PairingView: pairing flow entry point with QR scanner trigger and X25519 key exchange"
  - "PairingQRScannerView: QR scanner reusing QRCameraPreview for JSON payload parsing"
  - "PairedDeviceView: paired device info display with connection status dot and unpair button"
affects: [02-ios-relay-client-pairing, 03-chrome-extension]

tech-stack:
  added: [UserNotifications]
  patterns: [UIApplicationDelegateAdaptor for APNs in SwiftUI, closure callbacks for delegate-to-SwiftUI communication]

key-files:
  created:
    - App/AppDelegate.swift
    - App/Views/PairingView.swift
    - App/Views/PairingQRScannerView.swift
    - App/Views/PairedDeviceView.swift
  modified:
    - App/KeyAuth.entitlements
    - KeyAuth.xcodeproj/project.pbxproj

key-decisions:
  - "Closure callbacks (onDeviceToken, onNotificationTapped) on AppDelegate for delegate-to-SwiftUI communication -- matches existing onUnlock/onSave pattern"
  - "aps-environment set to development -- Xcode switches to production automatically on App Store submission"
  - "PairingQRScannerView reuses QRCameraPreview from QRScannerView.swift -- identical camera infra, only JSON parsing differs"

patterns-established:
  - "AppDelegate with closure callbacks: onDeviceToken and onNotificationTapped for APNs integration in SwiftUI apps"
  - "Pairing key exchange in view: handlePairingQR performs X25519 exchange inline after QR scan"

requirements-completed: [IOS-02, IOS-04, PAIR-02, PAIR-04]

duration: 5min
completed: 2026-04-15
---

# Phase 02 Plan 02: APNs Push + Pairing UI Summary

**AppDelegate for APNs device token handling, push entitlement, and three SwiftUI pairing views (scan QR, X25519 key exchange, paired device management with unpair)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-15T16:39:52Z
- **Completed:** 2026-04-15T16:45:02Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- AppDelegate handles APNs device token registration (hex encoded), foreground notification display (banner+sound), and notification tap routing via closure callbacks
- Push Notifications entitlement added to KeyAuth.entitlements (aps-environment=development)
- Three pairing views implement the complete pairing lifecycle: PairingView shows paired/unpaired state, PairingQRScannerView scans JSON QR codes using existing QRCameraPreview, PairedDeviceView shows connection status and supports unpairing

## Task Commits

Each task was committed atomically:

1. **Task 1: AppDelegate for APNs and push entitlement** - `7547d6f` (feat)
2. **Task 2: PairingView, PairingQRScannerView, and PairedDeviceView** - `2283f34` (feat)

## Files Created/Modified
- `App/AppDelegate.swift` - UIApplicationDelegate + UNUserNotificationCenterDelegate for APNs device token and notification handling
- `App/KeyAuth.entitlements` - Added aps-environment=development for Push Notifications capability
- `App/Views/PairingView.swift` - Pairing flow entry point with unpaired/paired conditional display and X25519 key exchange on QR scan
- `App/Views/PairingQRScannerView.swift` - QR scanner reusing QRCameraPreview for PairingQRPayload JSON decoding
- `App/Views/PairedDeviceView.swift` - Paired device info (room ID, paired date), connection status dot, and destructive unpair button
- `KeyAuth.xcodeproj/project.pbxproj` - Added all 4 new files to KeyAuth target

## Decisions Made
- Used closure callbacks (onDeviceToken, onNotificationTapped) on AppDelegate for delegate-to-SwiftUI communication, matching the existing onUnlock/onSave callback pattern used throughout the codebase
- Set aps-environment to development -- Xcode automatically switches to production when submitting to App Store
- PairingQRScannerView reuses QRCameraPreview directly from QRScannerView.swift rather than creating a new camera implementation -- only the handleCode parsing logic differs (JSON vs otpauth:// URL)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All pairing views ready for integration into ContentView (Plan 03: navigation item, status dot, code approval)
- AppDelegate ready for @UIApplicationDelegateAdaptor wiring in KeyAuthApp.swift (Plan 03)
- PairingView.handlePairingQR performs full X25519 exchange and connects RelayClient on successful scan
- PairedDeviceView unpair cleans up both Keychain (PairingStore) and WebSocket (RelayClient)
- No blockers for Plan 03

---
*Phase: 02-ios-relay-client-pairing*
*Completed: 2026-04-15*
