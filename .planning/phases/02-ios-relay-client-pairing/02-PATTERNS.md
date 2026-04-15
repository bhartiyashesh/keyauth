# Phase 02: iOS Relay Client + Pairing - Pattern Map

**Mapped:** 2026-04-15

## File Inventory

### New Files

| File | Role | Data Flow |
|------|------|-----------|
| `Shared/RelayClient.swift` | Service (singleton + observable) | Inbound: WebSocket messages from relay. Outbound: join/register_token/encrypted-code messages to relay. |
| `Shared/PairingStore.swift` | State store (observable) | Reads/writes pairing data to Keychain. Observed by views for paired/unpaired state. |
| `Shared/CryptoBoxManager.swift` | Stateless utility (enum namespace) | Inbound: encrypted Data from relay. Outbound: encrypted Data to relay. Pure transform. |
| `App/AppDelegate.swift` | Lifecycle delegate | Inbound: APNs device token from iOS, notification tap events. Outbound: token to RelayClient, navigation trigger to PairingStore/RelayClient. |
| `App/Views/PairingView.swift` | UI (SwiftUI view) | Reads PairingStore state. Triggers QR scanner or unpair action. |
| `App/Views/PairingQRScannerView.swift` | UI (SwiftUI view) | Wraps QRCameraPreview. Outputs parsed pairing JSON to PairingStore. |
| `App/Views/PairedDeviceView.swift` | UI (SwiftUI view) | Reads PairingStore for paired device info. Triggers unpair. |
| `App/Views/CodeApprovalView.swift` | UI (SwiftUI sheet) | Reads pending code request from RelayClient. Triggers biometric auth + code generation + encrypted send. |

### Modified Files

| File | Changes |
|------|---------|
| `App/KeyAuthApp.swift` | Add `@UIApplicationDelegateAdaptor(AppDelegate.self)`, add `@StateObject` for `PairingStore`, add foreground/background observers for RelayClient lifecycle, inject pairingStore into environment. |
| `App/Views/ContentView.swift` | Add pairing navigation item in toolbar, add connection status dot, add `.sheet` for CodeApprovalView when a pending request arrives. |
| `App/KeyAuth.entitlements` | Add `aps-environment` key for Push Notifications capability. |
| `Shared/KeychainManager.swift` | No code changes needed -- PairingStore uses its own service key (`com.keyauth.pairing`) via the same Keychain API pattern, but implemented directly in PairingStore (see rationale below). |

### Unchanged Files (Referenced)

| File | How Referenced |
|------|---------------|
| `Shared/BiometricAuthManager.swift` | Called directly in CodeApprovalView for Face ID / passcode gating. |
| `Shared/TOTPGenerator.swift` | Called in CodeApprovalView to generate the TOTP code after biometric approval. |
| `Shared/Account.swift` | Account struct matched by issuer+label from code request. |
| `Shared/AccountStore.swift` | Queried in CodeApprovalView to find the target account for code generation. |
| `App/Views/QRScannerView.swift` | Not modified; TOTP account QR scanning remains separate. PairingQRScannerView reuses QRCameraPreview. |

---

## Pattern Mapping: New File -> Closest Analog

### 1. `Shared/RelayClient.swift`

**Role:** WebSocket relay client -- connects, sends, receives, manages connection lifecycle.

**Closest Analog:** `Shared/AccountStore.swift`

**Why this analog:** Both are `@MainActor final class: ObservableObject` singletons that hold `@Published` state observed by SwiftUI views. AccountStore wraps Keychain CRUD; RelayClient wraps URLSessionWebSocketTask I/O. Same ownership pattern, same injection strategy.

**Pattern to follow from `Shared/AccountStore.swift`:**

```swift
// Shared/AccountStore.swift -- lines 1-11
import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?

    private let keychain = KeychainManager.shared

    init() {
        reload()
    }
```

**Apply as:**

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
    @Published var pendingCodeRequest: CodeRequest?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    private init() {}
```

**Key differences from analog:**
- RelayClient uses `static let shared` singleton (like `KeychainManager`, `BiometricAuthManager`) because it is a process-wide resource. AccountStore is injected as `@StateObject` because each app scene could theoretically have its own. RelayClient has exactly one WebSocket.
- RelayClient has `@Published private(set)` for state (views observe but never set). AccountStore has `@Published var` because views don't set it either, but the access control is implicit.
- RelayClient must implement the `URLSessionWebSocketDelegate` protocol to receive open/close events. Conform in an extension.

**Second analog for singleton pattern: `Shared/BiometricAuthManager.swift`:**

```swift
// Shared/BiometricAuthManager.swift -- lines 9-11
final class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    private init() {}
```

**Additional patterns specific to RelayClient:**

Receive loop (no codebase analog -- new pattern):
```swift
private func receiveLoop() {
    webSocketTask?.receive { [weak self] result in
        Task { @MainActor in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveLoop()  // re-invoke for next message
            case .failure(let error):
                self?.handleError(error)
            }
        }
    }
}
```

Send with error handling (follows AccountStore silent-discard pattern for best-effort operations):
```swift
func send(_ envelope: MessageEnvelope) {
    guard let data = try? JSONEncoder().encode(envelope),
          let json = String(data: data, encoding: .utf8) else { return }
    webSocketTask?.send(.string(json)) { [weak self] error in
        if let error {
            Task { @MainActor in self?.handleError(error) }
        }
    }
}
```

---

### 2. `Shared/PairingStore.swift`

**Role:** Observable state for pairing data -- isPaired, paired device info, Keychain CRUD for pairing keys.

**Closest Analog:** `Shared/AccountStore.swift`

**Why this analog:** Both are `@MainActor final class: ObservableObject` that wrap Keychain storage and expose `@Published` state. AccountStore manages `[Account]`; PairingStore manages a single `PairingData?`.

**Pattern to follow from `Shared/AccountStore.swift`:**

```swift
// Shared/AccountStore.swift -- lines 4-24
@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?

    private let keychain = KeychainManager.shared

    init() {
        reload()
    }

    func reload() {
        do {
            accounts = try keychain.loadAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
            accounts = []
        }
        SharedDefaults.saveAccounts(accounts)
    }
```

**Apply as:**

```swift
// Shared/PairingStore.swift
import Foundation
import CryptoKit

@MainActor
final class PairingStore: ObservableObject {
    static let shared = PairingStore()

    @Published private(set) var pairingData: PairingData?
    @Published var error: String?

    var isPaired: Bool { pairingData != nil }

    private init() {
        reload()
    }

    func reload() {
        do {
            pairingData = try loadFromKeychain()
            error = nil
        } catch {
            self.error = error.localizedDescription
            pairingData = nil
        }
    }
```

**Key differences from analog:**
- PairingStore stores a single Codable struct, not an array. Use a single Keychain item keyed by a fixed identifier (e.g., `kSecAttrAccount: "active_pairing"`).
- Uses `service: "com.keyauth.pairing"` to avoid collision with the account Keychain service (`com.keyauth.accounts`). Same `accessGroup` (`W646UCTVQV.com.keyauth.shared`).
- PairingStore implements its own Keychain read/write directly (same Security framework calls as `KeychainManager`), because the data shape and query differ. Follow the same `baseQuery` pattern.

**Keychain pattern to follow from `Shared/KeychainManager.swift`:**

```swift
// Shared/KeychainManager.swift -- lines 16-38 (save method)
func save(_ account: Account) throws {
    let data = try JSONEncoder().encode(account)
    let key = account.id.uuidString
    let query: [String: Any] = baseQuery(for: key)

    let status = SecItemCopyMatching(query as CFDictionary, nil)

    if status == errSecSuccess {
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainError.updateFailed(updateStatus)
        }
    } else {
        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainError.saveFailed(insertStatus)
        }
    }
}
```

**Apply the upsert pattern (check-then-update-or-insert) identically for pairing data:**

```swift
// PairingStore -- private keychain methods
private let service = "com.keyauth.pairing"
private let accessGroup: String? = "W646UCTVQV.com.keyauth.shared"
private let pairingKey = "active_pairing"

private func saveToKeychain(_ pairing: PairingData) throws {
    let data = try JSONEncoder().encode(pairing)
    let query = baseQuery()

    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainError.updateFailed(updateStatus)
        }
    } else {
        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainError.saveFailed(insertStatus)
        }
    }
}
```

**PairingData struct (follows Account struct pattern from `Shared/Account.swift`):**

```swift
struct PairingData: Codable {
    let roomId: String
    let relayURL: String
    let privateKeyRaw: Data      // Curve25519 private key raw bytes
    let peerPublicKeyRaw: Data   // Peer's public key raw bytes
    let sharedKeyRaw: Data       // Derived symmetric key (32 bytes)
    let pairedAt: Date
}
```

---

### 3. `Shared/CryptoBoxManager.swift`

**Role:** Stateless E2E encryption -- X25519 key generation, shared key derivation, ChaChaPoly seal/open.

**Closest Analog:** `Shared/TOTPGenerator.swift`

**Why this analog:** Both are caseless `enum` namespaces containing only `static` functions. TOTPGenerator does pure crypto transforms (HMAC-SHA + truncation). CryptoBoxManager does pure crypto transforms (X25519 + ChaChaPoly). Same structural pattern.

**Pattern to follow from `Shared/TOTPGenerator.swift`:**

```swift
// Shared/TOTPGenerator.swift -- lines 1-7
import Foundation
import CommonCrypto

enum TOTPGenerator {
    /// Generate a TOTP code for the given account at the current time
    static func generate(for account: Account, at date: Date = Date()) -> String? {
        guard let secretData = Base32.decode(account.secret) else { return nil }
```

**Apply as:**

```swift
// Shared/CryptoBoxManager.swift
import Foundation
import CryptoKit

enum CryptoBoxManager {
    /// Generate a new X25519 keypair for pairing
    static func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        return Curve25519.KeyAgreement.PrivateKey()
    }

    /// Derive shared symmetric key from X25519 key exchange
    static func deriveSharedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("KeyAuth-E2E".utf8),
            outputByteCount: 32
        )
    }

    /// Encrypt plaintext. Returns nonce(12) + ciphertext + tag(16).
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return sealedBox.combined
    }

    /// Decrypt combined data (nonce + ciphertext + tag).
    static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}
```

**Key parallel with analog:**
- Both use `enum` (no cases) as namespace -- matches `TOTPGenerator`, `Base32`, `SharedDefaults` convention.
- Both use `static func` exclusively.
- CryptoBoxManager `throws` on crypto failure (like `KeychainManager`), rather than returning optionals (like `TOTPGenerator`). Rationale: crypto failures are exceptional and should propagate, unlike Base32 decode which is a validation check.
- Private helpers marked `private static func` (same as TOTPGenerator's `private static func hmacSHA`).

**Wire format agreement:**
- `seal()` returns `ChaChaPoly.SealedBox.combined` which is `nonce(12) || ciphertext || tag(16)`
- Chrome extension (Phase 3) splits: `nonce = bytes[0:12]`, `ciphertext = bytes[12:-16]`, `tag = bytes[-16:]`
- This format is defined in the research doc and must not change.

---

### 4. `App/AppDelegate.swift`

**Role:** UIApplicationDelegate bridged into SwiftUI for APNs device token and notification tap handling.

**Closest Analog:** No direct analog in codebase. New pattern.

**Nearest reference:** `App/KeyAuthApp.swift` (existing app entry point that will host the delegate adaptor).

**Pattern from `App/KeyAuthApp.swift`:**

```swift
// App/KeyAuthApp.swift -- full file
import SwiftUI

@main
struct KeyAuthApp: App {
    @StateObject private var store = AccountStore()
    @State private var isUnlocked = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                } else {
                    LockScreenView {
                        isUnlocked = true
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidEnterBackgroundNotification"))
            ) { _ in
                isUnlocked = false
            }
        }
    }
}
```

**Apply as:**

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
        // Silent -- push won't work but app remains functional
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        onNotificationTapped?(userInfo)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
```

**Modified `App/KeyAuthApp.swift`:**

```swift
// App/KeyAuthApp.swift -- modified
import SwiftUI

@main
struct KeyAuthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var pairingStore = PairingStore.shared
    @State private var isUnlocked = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(pairingStore)
                } else {
                    LockScreenView {
                        isUnlocked = true
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                if pairingStore.isPaired {
                    // Connect relay on foreground
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification
                )
            ) { _ in
                isUnlocked = false
                RelayClient.shared.disconnect()
            }
        }
    }
}
```

**Conventions followed:**
- `final class` for delegate (matches all class types in codebase)
- Closure callbacks (`onDeviceToken`, `onNotificationTapped`) for delegate->SwiftUI communication (matches `onUnlock`, `onSave`, `onScanned` callback pattern)
- `@UIApplicationDelegateAdaptor` is the standard SwiftUI bridge for UIKit delegate methods
- Background notification name changed from string literal `"UIApplicationDidEnterBackgroundNotification"` to the actual `UIApplication.didEnterBackgroundNotification` notification (minor improvement)

---

### 5. `App/Views/PairingView.swift`

**Role:** Pairing flow entry point -- shows unpaired state with "Pair Browser" button, or paired state with device info.

**Closest Analog:** `App/Views/ContentView.swift` (navigation-driven view with conditional empty/populated states)

**Pattern to follow from `App/Views/ContentView.swift`:**

```swift
// App/Views/ContentView.swift -- lines 1-8, 17-42
struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var showingScanner = false
    @State private var showingManualEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.accounts.isEmpty {
                    emptyState
                        .padding(.top, 80)
                } else {
                    // populated state
                }
            }
            .toolbar { ... }
            .sheet(isPresented: $showingScanner) { ... }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) { ... }
    }
```

**Apply as:**

```swift
// App/Views/PairingView.swift
import SwiftUI

struct PairingView: View {
    @EnvironmentObject var pairingStore: PairingStore
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if pairingStore.isPaired {
                    pairedContent
                } else {
                    unpairedContent
                }
            }
            .navigationTitle("Browser Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                PairingQRScannerView { pairingJSON in
                    handlePairingQR(pairingJSON)
                    showingScanner = false
                }
            }
        }
    }

    private var unpairedContent: some View {
        VStack(spacing: 20) { ... }  // Empty state with "Pair Browser" button
    }

    private var pairedContent: some View {
        PairedDeviceView()
    }
}
```

**Conventions matched:**
- `@EnvironmentObject` for injected store (same as ContentView uses `AccountStore`)
- `@State private var` for sheet presentation toggle
- `private var ... : some View` for extracted sub-views
- `.sheet(isPresented:)` for modal presentation
- Closure callback from scanner sheet

---

### 6. `App/Views/PairingQRScannerView.swift`

**Role:** QR scanner specifically for pairing JSON payload (not otpauth:// URLs).

**Closest Analog:** `App/Views/QRScannerView.swift`

**Why this analog:** Identical camera/scanning infrastructure. Only the payload parsing differs (JSON instead of otpauth:// URL).

**Pattern to follow from `App/Views/QRScannerView.swift`:**

```swift
// App/Views/QRScannerView.swift -- lines 4-71 (full view structure)
struct QRScannerView: View {
    let onScanned: (Account) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRCameraPreview(onCodeDetected: handleCode)
                    .ignoresSafeArea()
                VStack { /* overlay UI */ }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleCode(_ code: String) {
        guard !scanned else { return }
        guard let url = URL(string: code) else {
            error = "Invalid QR code"
            return
        }
        guard let account = Account.from(otpauthURL: url) else {
            error = "Not a valid authenticator QR code"
            return
        }
        scanned = true
        onScanned(account)
    }
}
```

**Apply as:**

```swift
// App/Views/PairingQRScannerView.swift
import SwiftUI

struct PairingQRScannerView: View {
    let onPaired: (PairingQRPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRCameraPreview(onCodeDetected: handleCode)
                    .ignoresSafeArea()
                VStack { /* same overlay structure as QRScannerView */ }
            }
            .navigationTitle("Scan Pairing Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleCode(_ code: String) {
        guard !scanned else { return }
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data)
        else {
            error = "Invalid pairing QR code"
            return
        }
        scanned = true
        onPaired(payload)
    }
}
```

**Key reuse:** `QRCameraPreview` (the UIViewRepresentable at lines 75-145 of `App/Views/QRScannerView.swift`) is used directly. It provides raw string output via `onCodeDetected`. Only the `handleCode` parsing logic changes.

**PairingQRPayload struct:**
```swift
struct PairingQRPayload: Codable {
    let roomId: String
    let relayURL: String
    let publicKey: String  // base64-encoded Curve25519 public key (32 bytes)
}
```

---

### 7. `App/Views/PairedDeviceView.swift`

**Role:** Shows paired browser info + unpair button.

**Closest Analog:** Combination of `App/Views/ContentView.swift` (list-with-delete pattern) and `App/Views/LockScreenView.swift` (single-action centered layout).

**Pattern to follow from `App/Views/LockScreenView.swift`:**

```swift
// App/Views/LockScreenView.swift -- lines 3-6 (callback + state pattern)
struct LockScreenView: View {
    var onUnlock: () -> Void
    @State private var authFailed = false
    @State private var isAuthenticating = false
```

**Apply as:**

```swift
// App/Views/PairedDeviceView.swift
import SwiftUI

struct PairedDeviceView: View {
    @EnvironmentObject var pairingStore: PairingStore

    var body: some View {
        VStack(spacing: 20) {
            // Paired device info card
            // ...

            Button(role: .destructive) {
                pairingStore.unpair()
                RelayClient.shared.disconnect()
            } label: {
                Label("Unpair Browser", systemImage: "xmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }
}
```

**Conventions matched:**
- Destructive button uses `role: .destructive` (same pattern as delete in ContentView context menu)
- Button styling matches ContentView empty-state button pattern (`.buttonStyle(.bordered)`, explicit frame)
- `@EnvironmentObject` for store access

---

### 8. `App/Views/CodeApprovalView.swift`

**Role:** Sheet presented when a code request arrives. Shows account info, Approve button, triggers Face ID, generates + encrypts + sends code.

**Closest Analog:** `App/Views/LockScreenView.swift` (biometric auth flow with async/await + state management)

**Why this analog:** Both present a biometric prompt and handle success/failure state. LockScreenView unlocks the app; CodeApprovalView approves a code send.

**Pattern to follow from `App/Views/LockScreenView.swift`:**

```swift
// App/Views/LockScreenView.swift -- lines 72-85 (auth flow)
@MainActor
private func performAuth() async {
    guard !isAuthenticating else { return }
    isAuthenticating = true
    defer { isAuthenticating = false }

    authFailed = false
    let success = await BiometricAuthManager.shared.authenticate()
    if success {
        onUnlock()
    } else {
        authFailed = true
    }
}
```

**Apply as:**

```swift
// App/Views/CodeApprovalView.swift
import SwiftUI

struct CodeApprovalView: View {
    let request: CodeRequest
    let onComplete: () -> Void
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var authFailed = false
    @State private var isAuthenticating = false
    @State private var codeSent = false

    var body: some View {
        VStack(spacing: 24) {
            // Request info: account name, site
            Text("\(request.issuer) (\(request.label))")
                .font(.headline)
            Text("is requesting a code")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if authFailed {
                Text("Authentication failed. Tap to retry.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if codeSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button {
                Task { await approveAndSend() }
            } label: {
                Label("Approve", systemImage: "faceid")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating || codeSent)
        }
        .padding(40)
    }

    @MainActor
    private func approveAndSend() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        authFailed = false
        let success = await BiometricAuthManager.shared.authenticate(
            reason: "Approve code for \(request.issuer)"
        )

        guard success else {
            authFailed = true
            return
        }

        // Find account and generate code
        guard let account = store.accounts.first(where: {
            $0.issuer == request.issuer && $0.label == request.label
        }) else { return }

        guard let code = TOTPGenerator.generate(for: account) else { return }

        // Encrypt and send
        guard let sharedKey = PairingStore.shared.sharedKey else { return }
        let responsePayload = try? JSONEncoder().encode(["code": code])
        guard let plaintext = responsePayload,
              let encrypted = try? CryptoBoxManager.seal(plaintext, using: sharedKey)
        else { return }

        let envelope = MessageEnvelope(
            type: "code_response",
            payload: ["data": encrypted.base64EncodedString()]
        )
        RelayClient.shared.send(envelope)

        codeSent = true
        // Auto-dismiss after brief confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onComplete()
        }
    }
}
```

**Conventions matched:**
- `guard !isAuthenticating` + `defer { isAuthenticating = false }` -- exact pattern from LockScreenView
- `await BiometricAuthManager.shared.authenticate(reason:)` -- same call, custom reason string
- `Task { await ... }` from button action -- same invocation pattern as LockScreenView
- Error state as red text -- matches LockScreenView and ManualEntryView error display
- Closure callback `onComplete` -- matches `onUnlock`, `onSave` pattern
- `@Environment(\.dismiss)` for sheet dismissal -- used in ManualEntryView, QRScannerView

---

## Integration Points

### ContentView.swift Modifications

**Status dot addition (follows existing HStack patterns in AccountRowView):**

```swift
// In ContentView toolbar, add alongside existing plus button
ToolbarItem(placement: .navigationBarLeading) {
    NavigationLink {
        PairingView()
    } label: {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Image(systemName: "link")
                .font(.system(size: 16))
        }
    }
}

private var statusDotColor: Color {
    switch RelayClient.shared.state {
    case .connected: return .green
    case .connecting: return .orange
    case .disconnected: return .red
    }
}
```

**Code approval sheet (follows existing .sheet pattern):**

```swift
// In ContentView body, add after existing sheets
.sheet(item: $relayClient.pendingCodeRequest) { request in
    CodeApprovalView(request: request) {
        relayClient.pendingCodeRequest = nil
    }
    .environmentObject(store)
}
```

### KeyAuth.entitlements Modification

**Add APNs entitlement:**
```xml
<key>aps-environment</key>
<string>development</string>
```

### Relay Protocol Types

**MessageEnvelope (Swift mirror of `relay/src/types.ts`):**

```swift
struct MessageEnvelope: Codable {
    let v: Int
    let type: String
    let id: String
    let payload: [String: String]

    init(type: String, payload: [String: String] = [:]) {
        self.v = 1
        self.type = type
        self.id = UUID().uuidString
        self.payload = payload
    }
}
```

**CodeRequest (incoming from Chrome extension, after decryption):**

```swift
struct CodeRequest: Codable, Identifiable {
    let id: String
    let issuer: String
    let label: String
}
```

---

## Convention Summary for All New Files

| Convention | Rule | Source |
|------------|------|--------|
| File naming | One type per file, name matches primary type | All existing files |
| Singletons | `final class`, `static let shared`, `private init()` | `Shared/KeychainManager.swift`, `Shared/BiometricAuthManager.swift` |
| Enum namespaces | Caseless `enum`, `static func` only | `Shared/TOTPGenerator.swift`, `Shared/SharedDefaults.swift` |
| Observable stores | `@MainActor final class: ObservableObject`, `@Published` state | `Shared/AccountStore.swift` |
| SwiftUI views | `struct`, own file in `App/Views/`, sub-views as `private var` | All files in `App/Views/` |
| Callbacks | `let on{Action}: (Type) -> Void` | `QRScannerView.onScanned`, `LockScreenView.onUnlock`, `ManualEntryView.onSave` |
| Error display | `@State private var error: String?`, red `Text(error)` | `ManualEntryView`, `QRScannerView` |
| Access control | `private` on all helpers, `private(set)` on published state that views should not write | Throughout codebase |
| Imports | Framework imports only, one per line, no alphabetical enforcement | Throughout codebase |
| Error handling | `throws` with typed errors for persistence, optional returns for parsing, `try?` for best-effort | `KeychainManager`, `TOTPGenerator`, `SharedDefaults` |
| Biometric auth | `await BiometricAuthManager.shared.authenticate(reason:)`, `guard !isAuthenticating` + `defer` | `LockScreenView` |
| Sheet dismissal | `@Environment(\.dismiss) private var dismiss` | `ManualEntryView`, `QRScannerView` |

---

*Pattern map: 2026-04-15*
*Phase: 02-ios-relay-client-pairing*
