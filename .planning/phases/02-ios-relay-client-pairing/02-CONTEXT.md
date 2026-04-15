# Phase 2: iOS Relay Client + Pairing - Context

**Gathered:** 2026-04-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Add WebSocket relay connectivity, APNs push notification handling, TOTP code request approval, and pairing management to the existing KeyAuth iOS app. The iOS app must connect to the deployed relay server, register for push notifications, present a biometric-gated approval flow when a code is requested, and provide a screen to manage paired browsers. No changes to the keyboard extension or relay server.

</domain>

<decisions>
## Implementation Decisions

### Pairing Flow UX
- **D-01:** Dedicated navigation item (button or tab) on the main screen to access pairing -- keeps it discoverable since it's a one-time setup step
- **D-02:** Reuse the existing `QRScannerView` (AVCaptureSession + QR metadata detection) for scanning the Chrome extension's pairing QR code containing `{ roomId, relayURL, publicKey }`
- **D-03:** Single pairing only -- one browser paired at a time. Re-pairing replaces the previous pairing data. Matches the relay's 2-client-per-room constraint.
- **D-04:** Pairing data (roomId, relay URL, encryption keys) stored in Keychain -- consistent with how account secrets are stored, survives app reinstall
- **D-05:** Pairing management screen shows the paired browser with an unpair button. Unpairing deletes Keychain data and disconnects from the relay room.

### Code Approval Experience
- **D-06:** Approval sheet shows account name + site + Approve button. Clean and minimal: "GitHub (user@email.com) is requesting a code". Approve button triggers Face ID.
- **D-07:** After biometric approval, code is generated, encrypted (tweetnacl secretbox), sent to relay, and the sheet auto-dismisses with a brief "Sent" confirmation. Fastest possible flow.
- **D-08:** On biometric failure, retry biometric then fall back to device passcode -- same behavior as existing `BiometricAuthManager` (already handles this with `LAPolicy.deviceOwnerAuthentication`)

### Push Notification Behavior
- **D-09:** Tapping the APNs alert push opens the app directly to the code approval screen (deep-link via notification action or userInfo routing)
- **D-10:** No background WebSocket connection attempt -- iOS kills background sockets. Connect to relay only when the app comes to foreground after the user taps the notification.
- **D-11:** Register for APNs on every app launch to handle token refreshes (required by Apple best practice)

### Relay Client Lifecycle
- **D-12:** WebSocket connects when app enters foreground (if paired), disconnects when app enters background. Uses `URLSessionWebSocketTask` (no third-party dependencies).
- **D-13:** Subtle status dot on the main screen showing connection state: green (connected), red (disconnected), orange (connecting). Non-intrusive, always visible near the pairing section.
- **D-14:** On foreground connect, send `join` message with device token so the relay knows where to send APNs pushes
- **D-15:** E2E encryption: X25519 key exchange happens during pairing (keys stored in Keychain). All relay messages encrypted with tweetnacl secretbox -- relay never sees plaintext TOTP codes.

### Claude's Discretion
- Relay client class design (singleton vs injected service)
- Exact status dot placement and animation
- Notification category/action identifiers
- How to surface "not paired" state to the user on the main screen
- WebSocket reconnection retry strategy within a single foreground session

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Relay Protocol (from Phase 1)
- `.planning/phases/01-relay-server/01-CONTEXT.md` — Message envelope protocol (D-01 through D-05), room lifecycle, APNs integration decisions
- `relay/src/types.ts` — `MessageEnvelope` type definition (`{ v, type, id, payload }`)
- `relay/src/handlers.ts` — Message handler routing (join, register_token, opaque forward)

### Existing iOS Architecture
- `.planning/codebase/ARCHITECTURE.md` — Two-target app structure, data flow, key abstractions
- `.planning/codebase/CONVENTIONS.md` — Naming patterns, type design (enum namespaces, final class singletons), SwiftUI/UIKit conventions
- `Shared/BiometricAuthManager.swift` — Existing biometric auth singleton (reuse for approval flow)
- `App/Views/QRScannerView.swift` — Existing QR scanner (reuse for pairing)
- `Shared/KeychainManager.swift` — Existing Keychain CRUD (extend for pairing data storage)
- `Shared/AccountStore.swift` — Observable account state (@MainActor ObservableObject pattern to follow)

### Project Constraints
- `.planning/PROJECT.md` — No external iOS dependencies, URLSessionWebSocketTask required, E2E encryption decision
- `.planning/REQUIREMENTS.md` — IOS-01 through IOS-04, PAIR-02, PAIR-04, CODE-02 requirement definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `QRScannerView` — AVCaptureSession + QR metadata detection; can be reused for pairing QR scan with a different `onCodeDetected` handler
- `BiometricAuthManager` — Singleton with `async authenticate() -> Bool`; use directly in the approval flow
- `KeychainManager` — Full CRUD with typed errors; extend to store pairing data (roomId, relay URL, encryption keys)
- `AccountStore` — Pattern to follow for a new `RelayManager` or `PairingStore` observable class

### Established Patterns
- Enum-namespace for stateless utilities (`TOTPGenerator`, `Base32`, `SharedDefaults`)
- `final class` singletons with `static let shared` and `private init()` for services
- `@MainActor` ObservableObject for SwiftUI state
- Closure callbacks (`onSave`, `onUnlock`) for sheet results
- Programmatic Auto Layout in UIKit, SwiftUI for app views

### Integration Points
- `App/KeyAuthApp.swift` — Entry point; new relay/pairing state objects injected here as `@StateObject`
- `App/Views/ContentView.swift` — Main screen; add pairing navigation item and connection status dot here
- APNs device token flows: `UIApplicationDelegate.didRegisterForRemoteNotificationsWithDeviceToken` → store → send to relay on `join`
- Notification tap routing: `UNUserNotificationCenterDelegate.didReceive` → present approval sheet

</code_context>

<specifics>
## Specific Ideas

- The approval flow should be fast — user taps push notification, sees the approval sheet, Face ID, done. Minimal friction.
- E2E encryption via tweetnacl was explicitly decided in Phase 1 discussion — the relay must never see plaintext TOTP codes
- The app should feel the same as it does now for users who haven't paired — pairing is additive, not disruptive

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 02-ios-relay-client-pairing*
*Context gathered: 2026-04-15*
