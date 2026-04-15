# Phase 02: iOS Relay Client + Pairing - Research

**Researched:** 2026-04-15
**Domain:** iOS networking (WebSocket), push notifications (APNs), cryptography (X25519 + ChaCha20-Poly1305), Keychain storage, SwiftUI navigation
**Confidence:** HIGH

## Summary

Phase 2 adds four major capabilities to the existing KeyAuth iOS app: (1) a WebSocket relay client using `URLSessionWebSocketTask`, (2) APNs push notification registration and handling, (3) a biometric-gated TOTP code approval flow, and (4) a pairing management screen. All of this uses exclusively Apple frameworks -- no external dependencies. The existing codebase provides reusable assets (`QRScannerView`, `BiometricAuthManager`, `KeychainManager`) and well-established patterns (`@MainActor` ObservableObject, singleton services, enum namespaces) that the new code should follow precisely.

The most significant technical finding is the E2E encryption approach: Apple's CryptoKit provides `Curve25519.KeyAgreement` for X25519 key exchange and `ChaChaPoly` for ChaCha20-Poly1305 authenticated encryption -- both built-in, zero dependencies, available since iOS 13. This is the correct replacement for the "tweetnacl equivalent" mentioned in the project decisions. The Chrome extension side (Phase 3) can use `@noble/curves` for X25519 and `@noble/ciphers` for ChaCha20-Poly1305, which are audited JS libraries that produce byte-compatible output. A defined wire format (`nonce [12] + ciphertext + tag [16]`) ensures cross-platform interoperability.

**Primary recommendation:** Use CryptoKit (Curve25519.KeyAgreement + ChaChaPoly) for E2E encryption instead of hand-rolling a TweetNaCl port. Define a `nonce||ciphertext||tag` wire format for relay messages. Build the relay client as a `@MainActor final class RelayClient: ObservableObject` singleton following the `AccountStore` pattern.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Dedicated navigation item (button or tab) on the main screen to access pairing
- **D-02:** Reuse the existing `QRScannerView` for scanning the Chrome extension's pairing QR code containing `{ roomId, relayURL, publicKey }`
- **D-03:** Single pairing only -- one browser paired at a time. Re-pairing replaces the previous pairing data.
- **D-04:** Pairing data (roomId, relay URL, encryption keys) stored in Keychain
- **D-05:** Pairing management screen shows the paired browser with an unpair button. Unpairing deletes Keychain data and disconnects from the relay room.
- **D-06:** Approval sheet shows account name + site + Approve button. "GitHub (user@email.com) is requesting a code". Approve button triggers Face ID.
- **D-07:** After biometric approval, code is generated, encrypted (secretbox), sent to relay, and the sheet auto-dismisses with a brief "Sent" confirmation.
- **D-08:** On biometric failure, retry biometric then fall back to device passcode -- same behavior as existing `BiometricAuthManager`
- **D-09:** Tapping the APNs alert push opens the app directly to the code approval screen
- **D-10:** No background WebSocket connection attempt. Connect to relay only when the app comes to foreground.
- **D-11:** Register for APNs on every app launch to handle token refreshes
- **D-12:** WebSocket connects when app enters foreground (if paired), disconnects when app enters background. Uses `URLSessionWebSocketTask`.
- **D-13:** Subtle status dot on the main screen showing connection state: green (connected), red (disconnected), orange (connecting).
- **D-14:** On foreground connect, send `join` message with device token so the relay knows where to send APNs pushes
- **D-15:** E2E encryption: X25519 key exchange during pairing. All relay messages encrypted with authenticated encryption -- relay never sees plaintext TOTP codes.

### Claude's Discretion
- Relay client class design (singleton vs injected service)
- Exact status dot placement and animation
- Notification category/action identifiers
- How to surface "not paired" state to the user on the main screen
- WebSocket reconnection retry strategy within a single foreground session

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| IOS-01 | iOS app includes a WebSocket relay client (URLSessionWebSocketTask, foreground-only) | URLSessionWebSocketTask API research, message loop pattern, foreground/background lifecycle, relay protocol envelope |
| IOS-02 | iOS app registers for and handles APNs alert push notifications | UNUserNotificationCenter + UIApplication.registerForRemoteNotifications pattern, entitlements config, device token hex encoding |
| IOS-03 | iOS app presents a TOTP approval sheet (account name, site, approve/deny + Face ID) | Existing BiometricAuthManager reuse, SwiftUI sheet pattern, code generation via TOTPGenerator |
| IOS-04 | iOS app includes a pairing management screen (view paired devices, unpair) | Keychain-backed PairingStore pattern, SwiftUI List with delete, unpair = Keychain delete + WebSocket disconnect |
| PAIR-02 | iOS app scans pairing QR code and joins the relay room | Existing QRScannerView reuse with new JSON payload parser, CryptoKit X25519 key exchange at pair time |
| PAIR-04 | iOS app sends APNs device token to relay during pairing handshake | Device token sent in `join` message payload, relay `register_token` message type as fallback |
| CODE-02 | iOS app receives code request and prompts Face ID/Touch ID before generating code | ChaChaPoly decryption of incoming request, BiometricAuthManager.authenticate(), TOTPGenerator.generate(), ChaChaPoly encryption of response |

</phase_requirements>

## Standard Stack

### Core (Apple Frameworks Only -- No External Dependencies)
| Framework | Min iOS | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Foundation / URLSession | 13.0 | `URLSessionWebSocketTask` for WebSocket connectivity | Built-in, no dependencies, supports wss://, async/await |
| CryptoKit | 13.0 | `Curve25519.KeyAgreement` (X25519) + `ChaChaPoly` (ChaCha20-Poly1305) | Apple's native crypto, hardware-accelerated, zero-dependency replacement for TweetNaCl |
| UserNotifications | 10.0 | `UNUserNotificationCenter` for push permission + notification handling | Required Apple framework for APNs |
| UIKit | — | `UIApplicationDelegate` methods for device token + notification routing | Required for `didRegisterForRemoteNotificationsWithDeviceToken` |
| Security | — | Keychain Services for storing pairing data + encryption keys | Already used by existing `KeychainManager` |
| LocalAuthentication | — | `LAContext` for Face ID / Touch ID | Already used by existing `BiometricAuthManager` |
| SwiftUI | 13.0 | All new UI screens (pairing, approval sheet, status dot) | Existing app pattern |

### Relay Protocol (Server-Side Reference)
| Component | Version | Purpose | Wire Format |
|-----------|---------|---------|-------------|
| Message envelope | v: 1 | All relay messages | `{ v: 1, type: string, id: uuid, payload: {...} }` |
| `join` message | — | Room join + device token registration | `{ type: "join", payload: { deviceToken: "hex..." } }` |
| `register_token` | — | Device token update | `{ type: "register_token", payload: { deviceToken: "hex..." } }` |
| Opaque forward | — | Encrypted TOTP request/response | Relay forwards raw JSON to other client without inspection |

### Future Chrome Extension Crypto (Phase 3 -- Interop Reference)
| Library | Version | Purpose | Interop Notes |
|---------|---------|---------|---------------|
| `@noble/curves` | latest | X25519 key agreement in browser | `x25519.getSharedSecret(priv, pub)` -- byte-compatible with CryptoKit |
| `@noble/ciphers` | latest | ChaCha20-Poly1305 in browser | `chacha20poly1305(key, nonce).encrypt(data)` -- output is `ciphertext+tag`, nonce separate |

### Alternatives Considered
| Instead of | Could Use | Why Not |
|------------|-----------|---------|
| CryptoKit ChaChaPoly | TweetNaCl Swift port (XSalsa20-Poly1305) | No pure-Swift TweetNaCl library exists without external C dependencies; CryptoKit is built-in, hardware-accelerated, and produces equivalent security. XSalsa20-Poly1305 and ChaCha20-Poly1305 are NOT interoperable -- would need same cipher on both sides. |
| CryptoKit ChaChaPoly | AES-GCM (also in CryptoKit) | ChaChaPoly is faster without hardware AES acceleration (most mobile devices have it, but ChaChaPoly is still preferred for simplicity and DJB-curve alignment) |
| `URLSessionWebSocketTask` | Starscream/SocketRocket | Project constraint: no external iOS dependencies |
| `@noble/ciphers` (Phase 3) | libsodium-wrappers | noble-ciphers is audited, tree-shakeable, zero-dependency, lighter bundle for Chrome extension |

## Architecture Patterns

### Recommended Project Structure
```
Shared/
├── RelayClient.swift          # WebSocket client (URLSessionWebSocketTask)
├── PairingStore.swift         # Pairing state (@MainActor ObservableObject)
├── CryptoBoxManager.swift     # E2E encryption (CryptoKit wrappers)
├── KeychainManager.swift      # EXTENDED: add pairing data CRUD
├── BiometricAuthManager.swift # UNCHANGED: reused for approval flow
├── TOTPGenerator.swift        # UNCHANGED: generates codes
├── Account.swift              # UNCHANGED
App/
├── KeyAuthApp.swift           # MODIFIED: add @StateObject pairingStore, APNs delegate
├── AppDelegate.swift          # NEW: UIApplicationDelegate for APNs token + notification routing
├── Views/
│   ├── ContentView.swift      # MODIFIED: add pairing navigation + status dot
│   ├── PairingView.swift      # NEW: pairing flow entry (scan QR / show status)
│   ├── PairingQRScannerView.swift  # NEW: wraps QRCameraPreview for pairing JSON
│   ├── PairedDeviceView.swift # NEW: paired device info + unpair button
│   ├── CodeApprovalView.swift # NEW: approval sheet (account, site, approve)
│   └── QRScannerView.swift    # UNCHANGED: still used for TOTP account QR scans
```

### Pattern 1: RelayClient as @MainActor ObservableObject Singleton

**What:** The WebSocket relay client follows the same pattern as `AccountStore` -- a `@MainActor final class` with `@Published` state properties that SwiftUI views can observe.

**When to use:** This is the correct pattern because multiple views need to observe connection state (ContentView status dot, PairingView, CodeApprovalView).

**Recommendation (Claude's Discretion area):** Use singleton pattern (`static let shared`) rather than dependency injection. Rationale: the existing codebase uses singletons for all services (`KeychainManager.shared`, `BiometricAuthManager.shared`), and a relay client is a process-wide resource (one WebSocket per app).

**Example:**
```swift
// Shared/RelayClient.swift
import Foundation

@MainActor
final class RelayClient: ObservableObject {
    static let shared = RelayClient()

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: ConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var roomId: String?

    private init() {}

    func connect(roomId: String, relayURL: String, deviceToken: String?) {
        guard state == .disconnected else { return }
        self.roomId = roomId
        state = .connecting

        let url = URL(string: "\(relayURL)?roomId=\(roomId)")!
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: /* ... */, delegateQueue: .main)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        // Send join message after connection opens (in delegate callback)
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
    }

    func send(_ envelope: MessageEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        guard let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { [weak self] error in
            if let error {
                Task { @MainActor in self?.handleError(error) }
            }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveLoop() // CRITICAL: must re-call to get next message
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }
}
```

### Pattern 2: Message Envelope Codable Types

**What:** Swift types mirroring the relay's `MessageEnvelope` TypeScript type for JSON encoding/decoding.

**When to use:** All relay communication. The iOS app must produce/consume the exact `{ v: 1, type: string, id: string, payload: {...} }` format.

**Example:**
```swift
// Shared/RelayClient.swift (or a separate RelayTypes.swift)
struct MessageEnvelope: Codable {
    let v: Int
    let type: String
    let id: String
    let payload: [String: AnyCodable]  // or use JSONValue enum

    init(type: String, payload: [String: AnyCodable] = [:]) {
        self.v = 1
        self.type = type
        self.id = UUID().uuidString
        self.payload = payload
    }
}
```

**Note:** `payload` is `Record<string, unknown>` on the server side. In Swift, use a custom `AnyCodable` wrapper or a `JSONValue` enum to handle heterogeneous JSON values. Keep it minimal -- the payloads in this phase are simple (deviceToken string, encrypted data blobs).

### Pattern 3: CryptoKit E2E Encryption

**What:** X25519 key exchange at pairing time, ChaChaPoly symmetric encryption for all messages.

**Wire format for encrypted payloads:**
```
[nonce: 12 bytes][ciphertext: variable][tag: 16 bytes]
```
This matches CryptoKit's `ChaChaPoly.SealedBox.combined` property layout, and can be reconstructed on the JS side by splitting: `nonce = bytes[0:12]`, `ciphertext = bytes[12:-16]`, `tag = bytes[-16:]`.

**Example:**
```swift
// Shared/CryptoBoxManager.swift
import CryptoKit

enum CryptoBoxManager {
    // Generate keypair at pairing time
    static func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        return Curve25519.KeyAgreement.PrivateKey()
    }

    // Derive shared symmetric key from X25519 exchange
    static func deriveSharedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
            with: peerPublicKey
        )
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("KeyAuth-E2E".utf8),
            outputByteCount: 32
        )
    }

    // Encrypt a message
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return sealedBox.combined  // nonce (12) + ciphertext + tag (16)
    }

    // Decrypt a message
    static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}
```

### Pattern 4: AppDelegate for APNs in SwiftUI

**What:** SwiftUI uses `@UIApplicationDelegateAdaptor` to bridge `UIApplicationDelegate` methods needed for APNs device token and notification handling.

**Example:**
```swift
// App/AppDelegate.swift
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onDeviceToken: ((String) -> Void)?
    var onNotificationTapped: (([AnyHashable: Any]) -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        onDeviceToken?(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Log but don't crash -- push won't work but app remains functional
    }

    // Called when user taps a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        onNotificationTapped?(userInfo)
    }

    // Called when notification arrives while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

// App/KeyAuthApp.swift
@main
struct KeyAuthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var pairingStore = PairingStore()
    // ...
}
```

### Pattern 5: Foreground/Background Lifecycle

**What:** WebSocket connects on foreground, disconnects on background. Uses `NotificationCenter` observers.

**Example:**
```swift
// In RelayClient or KeyAuthApp
NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
    .sink { [weak self] _ in
        if pairingStore.isPaired {
            relayClient.connect(...)
        }
    }

NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
    .sink { [weak self] _ in
        relayClient.disconnect()
    }
```

### Anti-Patterns to Avoid
- **Keeping WebSocket alive in background:** iOS kills background sockets. Do NOT attempt background URLSession for WebSocket -- it is not supported. APNs push is the correct wakeup mechanism.
- **Caching the APNs device token:** Apple explicitly recommends registering on every launch. Token can change after OS updates, restore from backup, or app reinstall. Always re-register.
- **Calling `receive()` once:** `URLSessionWebSocketTask.receive()` delivers exactly one message per call. You MUST re-invoke it after each received message to form a receive loop.
- **Blocking the main thread with crypto:** CryptoKit operations are fast (sub-millisecond for ChaChaPoly seal/open on modern devices), but if paranoid, wrap in `Task.detached` with `@Sendable`.
- **Storing raw private keys in UserDefaults:** Encryption keys MUST go in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The existing `KeychainManager` already uses `kSecAttrAccessibleAfterFirstUnlock`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| X25519 key exchange | Custom Curve25519 implementation | `CryptoKit Curve25519.KeyAgreement` | Constant-time, hardware-accelerated, audited by Apple |
| Authenticated encryption | TweetNaCl Swift port, manual XSalsa20 | `CryptoKit ChaChaPoly` | Built-in since iOS 13, AEAD with nonce+tag, same security level |
| KDF from shared secret | Raw SHA256 of shared bytes | `SharedSecret.hkdfDerivedSymmetricKey()` | HKDF is the standard KDF, domain separation via `sharedInfo` param |
| JSON encoding for relay | Manual string concatenation | `Codable` structs + `JSONEncoder` | Handles escaping, Unicode, nested objects correctly |
| Device token hex encoding | Custom byte-to-hex | `deviceToken.map { String(format: "%02x", $0) }.joined()` | Standard pattern, matches what server expects |
| WebSocket reconnection | Complex state machine | Simple exponential backoff with 3 retries in a foreground session | Connection only lives during foreground; a fresh connect on each foreground entry is simpler |

**Key insight:** CryptoKit eliminates the entire "find a tweetnacl Swift equivalent" problem. Every crypto primitive needed (X25519, ChaCha20-Poly1305, HKDF-SHA256) is built into iOS 13+. No external dependency needed.

## Common Pitfalls

### Pitfall 1: URLSessionWebSocketTask Receive Loop
**What goes wrong:** Developer calls `receive()` once and wonders why only the first message arrives.
**Why it happens:** Unlike delegate-based WebSocket libraries, `URLSessionWebSocketTask.receive()` is a one-shot call. It completes with exactly one message.
**How to avoid:** Immediately call `receiveLoop()` again inside the success handler of each receive completion.
**Warning signs:** First message works, all subsequent messages are silent.

### Pitfall 2: APNs Device Token Format
**What goes wrong:** Device token sent to server as base64 or raw Data, server cannot use it for push.
**Why it happens:** `didRegisterForRemoteNotificationsWithDeviceToken` provides `Data`, not a string. The token must be hex-encoded.
**How to avoid:** Convert with `deviceToken.map { String(format: "%02x", $0) }.joined()`. The relay server's `apns2` library expects a hex string.
**Warning signs:** Push notifications never arrive; server logs "BadDeviceToken".

### Pitfall 3: ChaChaPoly Combined Format Mismatch
**What goes wrong:** iOS encrypts with CryptoKit ChaChaPoly, Chrome extension cannot decrypt (or vice versa).
**Why it happens:** CryptoKit `.combined` is `nonce(12) + ciphertext + tag(16)`. `@noble/ciphers` encrypt output is `ciphertext + tag(16)` with nonce separate. If both sides don't agree on wire format, decryption fails.
**How to avoid:** Define a wire format: `nonce(12) || ciphertext || tag(16)`. iOS sends `sealedBox.combined` directly. JS side splits first 12 bytes as nonce, last 16 as tag, middle as ciphertext.
**Warning signs:** `CryptoKitError.authenticationFailure` on decrypt.

### Pitfall 4: Missing Push Notification Entitlement
**What goes wrong:** `UIApplication.registerForRemoteNotifications()` silently fails or calls `didFailToRegister`.
**Why it happens:** The app's `.entitlements` file is missing `aps-environment` key, or the App ID doesn't have Push Notifications capability enabled in Apple Developer portal.
**How to avoid:** Add `aps-environment` to `App/KeyAuth.entitlements`. Enable Push Notifications in Xcode Signing & Capabilities. Ensure the Apple Developer portal App ID has Push Notifications enabled.
**Warning signs:** `didFailToRegisterForRemoteNotificationsWithError` called with "not entitled" error.

### Pitfall 5: Notification Tap Routing When App is Killed
**What goes wrong:** User taps push notification, app launches but doesn't navigate to approval screen.
**Why it happens:** When the app is launched from a killed state via notification tap, `didReceive response` fires BEFORE SwiftUI views are fully rendered. Navigation state isn't ready.
**How to avoid:** Store the pending notification data in a `@Published` property on the AppDelegate or a shared coordinator. SwiftUI views observe this on appear and present the approval sheet when non-nil.
**Warning signs:** Notification tap works when app is in background but not when cold-launched.

### Pitfall 6: Keychain Access Group for Pairing Keys
**What goes wrong:** Pairing data saved but can't be read back, or is accessible by wrong target.
**Why it happens:** The existing `KeychainManager` uses service `com.keyauth.accounts` and access group `W646UCTVQV.com.keyauth.shared`. Pairing data should use a different service identifier to avoid collisions with account data, but the same access group.
**How to avoid:** Use a different `kSecAttrService` value (e.g., `com.keyauth.pairing`) for pairing keychain items. Keep the same access group so both targets can access if needed in future.
**Warning signs:** `loadAll()` on accounts returns pairing data or vice versa; keychain errors.

### Pitfall 7: WebSocket Disconnect Race on Background
**What goes wrong:** App goes to background, WebSocket close frame not sent, relay thinks client is still connected. Next code request doesn't trigger APNs push because `hasIosClient()` returns true.
**Why it happens:** iOS suspends the app quickly on background entry. The close frame may not be sent in time.
**How to avoid:** Use `cancel(with: .goingAway, reason: nil)` which is faster than a clean close. The relay's `ws.on('close')` handler will fire either way (TCP FIN or timeout). The relay's `hasIosClient` checks `ws.readyState === OPEN`, so a dropped connection will eventually be detected.
**Warning signs:** APNs push not sent after app goes to background; relay log shows client still in room.

## Code Examples

### Complete Pairing Flow
```swift
// 1. User scans QR code containing: { "roomId": "uuid", "relayURL": "wss://...", "publicKey": "base64..." }
func handlePairingQR(_ jsonString: String) throws {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
          let roomId = json["roomId"],
          let relayURL = json["relayURL"],
          let peerPublicKeyBase64 = json["publicKey"],
          let peerPublicKeyData = Data(base64Encoded: peerPublicKeyBase64)
    else { throw PairingError.invalidQRCode }

    // 2. Generate our keypair
    let privateKey = CryptoBoxManager.generateKeyPair()
    let publicKey = privateKey.publicKey

    // 3. Derive shared key
    let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
    let sharedKey = try CryptoBoxManager.deriveSharedKey(privateKey: privateKey, peerPublicKey: peerPublicKey)

    // 4. Store pairing data in Keychain
    let pairingData = PairingData(
        roomId: roomId,
        relayURL: relayURL,
        privateKeyRaw: privateKey.rawRepresentation,
        peerPublicKeyRaw: peerPublicKeyData,
        sharedKeyRaw: sharedKey  // store derived key to avoid recomputing
    )
    try PairingStore.shared.savePairing(pairingData)

    // 5. Connect to relay
    RelayClient.shared.connect(roomId: roomId, relayURL: relayURL, deviceToken: currentDeviceToken)
}
```

### APNs Registration (Every Launch)
```swift
// In KeyAuthApp.swift or AppDelegate
func requestPushPermissionAndRegister() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        guard granted else { return }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
```

### Receiving and Handling a Code Request
```swift
// In RelayClient message handler
func handleIncomingMessage(_ data: Data) {
    // 1. Parse envelope
    guard let envelope = try? JSONDecoder().decode(MessageEnvelope.self, from: data) else { return }

    // 2. Decrypt payload (opaque forwarded message from extension)
    guard let encryptedBase64 = envelope.payload["data"] as? String,
          let encryptedData = Data(base64Encoded: encryptedBase64),
          let sharedKey = pairingStore.sharedKey
    else { return }

    guard let plaintext = try? CryptoBoxManager.open(encryptedData, using: sharedKey),
          let request = try? JSONDecoder().decode(CodeRequest.self, from: plaintext)
    else { return }

    // 3. Present approval sheet (triggers Face ID)
    pendingCodeRequest = request  // @Published triggers sheet presentation
}
```

### WebSocket Reconnection Strategy (Claude's Discretion)
```swift
// Recommended: simple retry with exponential backoff, max 3 attempts per foreground session
private var retryCount = 0
private let maxRetries = 3

private func scheduleReconnect() {
    guard retryCount < maxRetries else {
        state = .disconnected
        return
    }
    retryCount += 1
    let delay = Double(min(retryCount * retryCount, 9))  // 1s, 4s, 9s
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        if state == .disconnected {
            connect(/* reuse stored params */)
        }
    }
}

// Reset retry count on successful connection
private func onConnected() {
    retryCount = 0
    state = .connected
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Starscream / SocketRocket for WebSocket | `URLSessionWebSocketTask` | iOS 13 (2019) | No third-party dependency needed |
| Hand-rolled NaCl / OpenSSL wrappers | CryptoKit | iOS 13 (2019) | X25519, ChaChaPoly, HKDF all built-in |
| Silent APNs push for background wake | Alert APNs push | Always (silent throttled at ~3/hr) | Alert push is the reliable pattern |
| `UIApplicationDelegate` push methods | Still required (`@UIApplicationDelegateAdaptor`) | iOS 14+ | SwiftUI still needs UIKit bridge for APNs |
| NaCl `crypto_secretbox` (XSalsa20-Poly1305) | ChaCha20-Poly1305 (IETF standard, RFC 8439) | ~2020 | ChaCha20-Poly1305 is the modern AEAD; widely supported across platforms |

**Deprecated/outdated:**
- `UILocalNotification`: Replaced by `UNUserNotificationCenter` since iOS 10
- `application:didReceiveRemoteNotification:` (without fetchCompletionHandler): Use `UNUserNotificationCenterDelegate` methods instead
- Background `URLSession` for WebSocket: iOS does not support WebSocket in background URLSession configurations

## Open Questions

1. **QR Payload Format for Pairing**
   - What we know: The QR code will contain `{ roomId, relayURL, publicKey }` (from CONTEXT.md D-02)
   - What's unclear: Will `publicKey` be base64-encoded raw representation? Will there be additional fields (e.g., browser name for display on paired device screen)?
   - Recommendation: Use base64-encoded `Curve25519.KeyAgreement.PublicKey.rawRepresentation` (32 bytes). This is the simplest format and CryptoKit can reconstruct from raw bytes. Add an optional `name` field for display. Define this in Phase 2 and the Chrome extension (Phase 3) will produce it.

2. **Account Identification in Code Requests**
   - What we know: The Chrome extension sends a code request, and the approval sheet shows "account name + site" (D-06)
   - What's unclear: How does the extension specify which account? By account ID (UUID)? By issuer+label combo?
   - Recommendation: Use `issuer` + `label` fields in the encrypted request payload. The iOS app matches against its local `AccountStore` to find the account and generate the TOTP code. Exact matching logic can be refined in Phase 3.

3. **Shared Key Storage Format**
   - What we know: Pairing data goes in Keychain (D-04)
   - What's unclear: Should we store the derived `SymmetricKey`, or the private key + peer public key and re-derive on each use?
   - Recommendation: Store both the raw private key AND the derived shared key bytes. Private key needed if we ever need to re-derive (e.g., KDF parameter change). Shared key cached for performance. Both as `Data` in a single Codable struct in Keychain.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in) |
| Config file | None -- Wave 0 gap |
| Quick run command | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyAuthTests` |
| Full suite command | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IOS-01 | WebSocket relay client connects/sends/receives | unit | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/RelayClientTests` | No -- Wave 0 |
| IOS-02 | APNs registration and device token handling | manual-only | N/A (requires physical device + APNs) | N/A |
| IOS-03 | TOTP approval sheet shows account info and triggers biometric | unit (view model logic) | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/CodeApprovalTests` | No -- Wave 0 |
| IOS-04 | Pairing management CRUD | unit | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/PairingStoreTests` | No -- Wave 0 |
| PAIR-02 | QR code pairing JSON parsing | unit | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/PairingQRTests` | No -- Wave 0 |
| PAIR-04 | Device token sent in join message | unit | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/RelayClientTests/testJoinMessageContainsDeviceToken` | No -- Wave 0 |
| CODE-02 | E2E encrypt/decrypt round-trip | unit | `xcodebuild test -scheme KeyAuth -only-testing:KeyAuthTests/CryptoBoxTests` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyAuthTests -quiet`
- **Per wave merge:** Full test suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `KeyAuthTests/` test target -- does not exist, must be created in Xcode
- [ ] `KeyAuthTests/RelayClientTests.swift` -- covers IOS-01, PAIR-04
- [ ] `KeyAuthTests/PairingStoreTests.swift` -- covers IOS-04
- [ ] `KeyAuthTests/PairingQRTests.swift` -- covers PAIR-02
- [ ] `KeyAuthTests/CryptoBoxTests.swift` -- covers CODE-02 (encrypt/decrypt round-trip)
- [ ] `KeyAuthTests/CodeApprovalTests.swift` -- covers IOS-03 (view model logic only)
- [ ] XCTest target added to `KeyAuth.xcodeproj` with `Shared/` sources compiled into test target

## Sources

### Primary (HIGH confidence)
- [Apple CryptoKit Curve25519.KeyAgreement docs](https://developer.apple.com/documentation/cryptokit/curve25519/keyagreement) -- X25519 PrivateKey/PublicKey, sharedSecretFromKeyAgreement, HKDF derivation
- [Apple CryptoKit ChaChaPoly docs](https://developer.apple.com/documentation/cryptokit/chachapoly) -- seal/open API, SealedBox.combined format (nonce+ciphertext+tag), Nonce (12 bytes)
- [Apple URLSessionWebSocketTask docs](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) -- send/receive/sendPing API, Message enum, delegate protocol
- [Apple Registering for APNs docs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) -- registration flow, token handling best practices
- Existing relay source code: `relay/src/types.ts`, `relay/src/handlers.ts`, `relay/src/index.ts` -- definitive protocol reference
- Existing iOS source code: `Shared/KeychainManager.swift`, `Shared/BiometricAuthManager.swift`, `App/Views/QRScannerView.swift` -- reusable assets

### Secondary (MEDIUM confidence)
- [@noble/ciphers GitHub](https://github.com/paulmillr/noble-ciphers) -- ChaCha20-Poly1305 JS API, output format (ciphertext+tag, nonce separate)
- [@noble/curves npm](https://www.npmjs.com/package/@noble/curves) -- X25519 JS API, byte-compatible with CryptoKit Curve25519
- [iOS Push Notifications Guide (oneuptime.com)](https://oneuptime.com/blog/post/2026-02-02-ios-push-notifications/view) -- 2026 APNs integration patterns
- [Deep linking for notifications in SwiftUI (swiftwithmajid.com)](https://swiftwithmajid.com/2024/04/09/deep-linking-for-local-notifications-in-swiftui/) -- UNUserNotificationCenterDelegate + SwiftUI navigation

### Tertiary (LOW confidence)
- ChaChaPoly `.combined` byte order (`nonce + ciphertext + tag`): verified via multiple sources including interop articles, but Apple's own docs don't explicitly state byte order in plain text. Practically confirmed by cross-platform decryption examples.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All Apple frameworks, well-documented, verified against official docs
- Architecture: HIGH -- Patterns directly follow existing codebase conventions (verified by reading all source files)
- Pitfalls: HIGH -- Common iOS WebSocket/APNs/crypto issues well-documented across multiple sources
- E2E encryption interop: MEDIUM -- CryptoKit ChaChaPoly + @noble/ciphers compatibility is well-attested but the exact wire format needs to be validated with an end-to-end test (Phase 3)

**Research date:** 2026-04-15
**Valid until:** 2026-05-15 (stable -- Apple frameworks, no breaking changes expected)
