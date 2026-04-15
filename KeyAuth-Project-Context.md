# KeyAuth — Project Context

> Handover document for continuing development in a new session. Contains everything needed to understand, debug, and extend the project.

---

## What is KeyAuth

A TOTP authenticator built into an iOS custom keyboard extension. Users add 2FA accounts via a companion app (QR scan or manual entry), and TOTP codes appear in a scrollable bar above the QWERTY keys in the keyboard extension. Tapping a code inserts it directly into the active text field via `textDocumentProxy.insertText()` — no app switching, no clipboard.

**Core differentiator:** No "Allow Full Access" required. Secrets stay in the iOS Keychain, shared between app and extension via App Groups. The keyboard extension has zero network access.

---

## Architecture

```
┌─────────────────────────────────────┐
│  Companion App (SwiftUI)            │
│  • QR Scanner (AVFoundation)        │
│  • Account Manager (CRUD + reorder) │
│  • Biometric Gate (FaceID/TouchID)  │
│  • Manual Entry + Import            │
└──────────────┬──────────────────────┘
               │ writes to shared Keychain
┌──────────────▼──────────────────────┐
│  Shared Framework (App Group)       │
│  • TOTPGenerator (RFC 6238)         │
│  • KeychainManager (shared access)  │
│  • Account model (Codable)          │
│  • Base32 decoder                   │
│  • BiometricAuthManager             │
│  • AccountStore (ObservableObject)  │
└──────────────┬──────────────────────┘
               │ reads from shared Keychain
┌──────────────▼──────────────────────┐
│  Keyboard Extension (UIKit)         │
│  • UIInputViewController            │
│  • Auth bar (UICollectionView)      │
│  • QWERTY keyboard (UIStackView)    │
│  • Tap-to-insert (textDocumentProxy)│
│  • Countdown ring per code          │
└─────────────────────────────────────┘
```

---

## File Structure

```
KeyAuth/
├── project.yml                          # XcodeGen spec (generates .xcodeproj)
├── Shared/                              # Linked by BOTH targets
│   ├── Account.swift                    # Data model + otpauth:// URL parser
│   ├── AccountStore.swift               # @MainActor ObservableObject wrapping Keychain
│   ├── Base32.swift                     # Base32 decoder for TOTP secrets
│   ├── BiometricAuthManager.swift       # FaceID/TouchID with passcode fallback
│   ├── KeychainManager.swift            # Shared Keychain CRUD (App Group)
│   └── TOTPGenerator.swift              # RFC 6238 HMAC-SHA1/256/512
├── App/                                 # Companion app target
│   ├── KeyAuthApp.swift                 # @main entry, biometric gate, scenePhase lock
│   ├── Info.plist                       # NSCameraUsageDescription, NSFaceIDUsageDescription
│   ├── KeyAuth.entitlements             # App Groups + Keychain sharing
│   └── Views/
│       ├── ContentView.swift            # NavigationStack, account list, search, add menu
│       ├── AccountRowView.swift         # Issuer icon + code + countdown ring + tap-to-copy
│       ├── LockScreenView.swift         # Biometric unlock screen, auto-triggers on appear
│       ├── ManualEntryView.swift        # Form: issuer, label, secret, algorithm, digits, period
│       └── QRScannerView.swift          # AVFoundation camera + otpauth:// parsing
├── KeyboardExtension/                   # Keyboard extension target
│   ├── KeyboardViewController.swift     # UIInputViewController, QWERTY layout, auth bar
│   ├── TOTPCodeCell.swift               # UICollectionViewCell: issuer + code + countdown ring
│   ├── Info.plist                       # RequestsOpenAccess: false, keyboard-service
│   └── KeyAuthKeyboard.entitlements     # App Groups + Keychain sharing (mirrors app)
```

---

## Build & Run

### Prerequisites
- Xcode 15+
- Physical iPhone (keyboard extensions don't work in simulator)
- Apple Developer account (free works for personal device testing)

### Steps
```bash
brew install xcodegen        # one time
cd KeyAuth
xcodegen generate
open KeyAuth.xcodeproj
```

1. Select **KeyAuth** target (the app, not KeyAuthKeyboard) in the scheme dropdown
2. Set Team in Signing & Capabilities for BOTH targets
3. Update `KeychainManager.swift` line ~7: set `accessGroup` to `"YOURTEAMID.com.keyauth.shared"`
4. Select your physical iPhone as run destination
5. Cmd+R

### Enable the keyboard after install
Settings → General → Keyboard → Keyboards → Add New Keyboard → KeyAuth

**IMPORTANT:** Do NOT enable "Allow Full Access" — it's not needed and we explicitly don't want it.

---

## Key Technical Decisions

### Why App Groups + Shared Keychain (not Allow Full Access)
iOS keyboard extensions run in a sandbox. With `RequestsOpenAccess: false`, the extension has no network, no pasteboard, no location. Data sharing between app and extension happens via:
- **Keychain Access Group**: `$(AppIdentifierPrefix)com.keyauth.shared` in both entitlements
- **kSecAttrAccessibleAfterFirstUnlock**: Allows keyboard to read secrets after first device unlock (keyboard extensions run in this context)

### Why UIKit for the keyboard (not SwiftUI)
`UIInputViewController` is a UIKit class. SwiftUI hosting inside keyboard extensions has known memory issues and the 50MB limit is tight. The companion app uses SwiftUI freely.

### Why custom QWERTY (not just the auth bar)
Apple requires custom keyboards to provide text input. A keyboard that only shows TOTP codes and no keys would be rejected by App Review. The QWERTY implementation is minimal but functional — users can type normally and tap codes from the auth bar.

### TOTP Implementation
RFC 6238 compliant: `HMAC(secret, floor(unixTime / period))` → dynamic truncation → `mod 10^digits`
- Algorithms: SHA-1 (default), SHA-256, SHA-512
- Digits: 6 (default), 7, 8
- Period: 30s (default), configurable 10-120s
- URI: `otpauth://totp/Issuer:label?secret=BASE32&algorithm=SHA1&digits=6&period=30`

### Test vector
```
Secret: JBSWY3DPEHPK3PXP (Base32)
Algorithm: SHA1, Digits: 6, Period: 30
```
Cross-check against Google Authenticator or any RFC 6238 compliant app.

---

## Known Issues / Current Blockers

### Build Scheme Selection
When running from Xcode, the **KeyAuthKeyboard** extension target may be selected by default. It prompts "Choose an app to run" showing Siri/Today — this is wrong. **Switch scheme to KeyAuth** (the main app target). The extension deploys automatically as part of the app bundle.

### KeychainManager accessGroup
Currently set to `nil` for development. In production this MUST be set to `"TEAMID.com.keyauth.shared"` for the extension to read accounts. Without this, the keyboard will show zero codes.

### Potential Issues to Watch
1. **Keychain serialization**: `Account` uses `JSONEncoder` — if the model changes, old Keychain entries may fail to decode. Need migration strategy.
2. **Memory pressure**: Keyboard extensions have a 50MB limit. Current implementation is well within budget (pure math, no images, no network) but monitor if adding features.
3. **AccountStore is @MainActor**: Works for the SwiftUI app but the keyboard extension accesses `KeychainManager.shared` directly (not through `AccountStore`) since it's UIKit.
4. **Timer invalidation**: `KeyboardViewController.displayTimer` is invalidated in `viewDidDisappear` but keyboard extension lifecycle is non-obvious — may need to also handle `viewWillDisappear`.
5. **QRCameraPreview uses UIScreen.main.bounds**: Deprecated in iOS 16+, should use view's own bounds.

---

## Security Model

| Property | Implementation |
|----------|---------------|
| Secret storage | iOS Keychain, `kSecAttrAccessibleAfterFirstUnlock` |
| App ↔ Extension sharing | Keychain Access Group (no files, no UserDefaults) |
| Network from extension | None (`RequestsOpenAccess: false`) |
| Clipboard exposure | None — `textDocumentProxy.insertText()` injects directly |
| App lock | FaceID/TouchID via `LAContext`, auto-locks on background |
| iCloud sync | Possible via `kSecAttrSynchronizable: true` (not yet enabled) |

---

## Planned Features (Roadmap)

### Phase 2: Polish
- [ ] iCloud Keychain sync toggle in settings
- [ ] Import from Google Authenticator (protobuf QR batch export parsing)
- [ ] Import from Authy encrypted backup
- [ ] Issuer favicon fetching (companion app only, cached locally)
- [ ] Search/filter in the keyboard auth bar
- [ ] Shift key + caps lock in keyboard
- [ ] Number row / symbol layer in keyboard

### Phase 3: Platform Expansion
- [ ] Chrome extension with push-to-fill (E2E encrypted relay, secrets never leave phone)
  - QR pairing: extension generates X25519 keypair, phone scans to establish channel
  - Flow: extension detects TOTP field → push via relay → phone FaceID → encrypted code relay → auto-fill
  - Relay is zero-knowledge (dumb WebSocket pipe)
  - Tech: Manifest V3, tweetnacl/libsodium, WebSocket relay on Railway
- [ ] watchOS companion
- [ ] Lock Screen widget

### Phase 4: Growth
- [ ] App Store submission
- [ ] Marketing site
- [ ] Freemium model (free up to N accounts, paid for unlimited + sync)

---

## Dependencies

**Zero external dependencies.** Everything uses Apple frameworks:
- `Foundation` — data types, JSON encoding
- `Security` — Keychain Services
- `CommonCrypto` — HMAC-SHA1/256/512
- `LocalAuthentication` — FaceID/TouchID
- `AVFoundation` — QR code scanning
- `UIKit` — keyboard extension
- `SwiftUI` — companion app UI

Build tool: `xcodegen` (generates .xcodeproj from `project.yml`)

---

## Complete Source Code

### Shared/Base32.swift
```swift
import Foundation

enum Base32 {
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    private static let lookupTable: [Character: UInt8] = {
        var table = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() {
            table[c] = UInt8(i)
        }
        return table
    }()

    static func decode(_ input: String) -> Data? {
        let clean = input.uppercased().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { return nil }

        var bits = 0
        var buffer: UInt64 = 0
        var bytes = [UInt8]()

        for char in clean {
            guard let value = lookupTable[char] else { return nil }
            buffer = (buffer << 5) | UInt64(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 0xFF))
            }
        }

        return Data(bytes)
    }
}
```

### Shared/Account.swift
```swift
import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var issuer: String
    var label: String
    var secret: String // Base32-encoded
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        issuer: String,
        label: String,
        secret: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.label = label
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    /// Parse otpauth://totp/Label?secret=BASE32&issuer=GitHub&digits=6&period=30&algorithm=SHA1
    static func from(otpauthURL url: URL) -> Account? {
        guard url.scheme == "otpauth",
              url.host == "totp",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let params = Dictionary(queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        }, uniquingKeysWith: { _, last in last })

        guard let secret = params["secret"], !secret.isEmpty else { return nil }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathParts = path.split(separator: ":", maxSplits: 1)

        let issuer: String
        let label: String

        if let paramIssuer = params["issuer"], !paramIssuer.isEmpty {
            issuer = paramIssuer
            label = pathParts.count > 1
                ? String(pathParts[1]).trimmingCharacters(in: .whitespaces)
                : path.removingPercentEncoding ?? path
        } else if pathParts.count > 1 {
            issuer = String(pathParts[0]).trimmingCharacters(in: .whitespaces)
            label = String(pathParts[1]).trimmingCharacters(in: .whitespaces)
        } else {
            issuer = ""
            label = path.removingPercentEncoding ?? path
        }

        let algorithm: OTPAlgorithm
        switch params["algorithm"]?.uppercased() {
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: algorithm = .sha1
        }

        let digits = Int(params["digits"] ?? "") ?? 6
        let period = Int(params["period"] ?? "") ?? 30

        guard Base32.decode(secret) != nil else { return nil }
        guard [6, 7, 8].contains(digits) else { return nil }
        guard (10...120).contains(period) else { return nil }

        return Account(
            issuer: issuer,
            label: label,
            secret: secret.uppercased(),
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}
```

### Shared/TOTPGenerator.swift
```swift
import Foundation
import CommonCrypto

enum TOTPGenerator {
    static func generate(for account: Account, at date: Date = Date()) -> String? {
        guard let secretData = Base32.decode(account.secret) else { return nil }
        return generate(
            secret: secretData,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            date: date
        )
    }

    static func generate(
        secret: Data,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        date: Date = Date()
    ) -> String? {
        let counter = UInt64(floor(date.timeIntervalSince1970) / Double(period))
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)

        guard let hmac = hmacSHA(algorithm: algorithm, key: secret, data: counterData) else {
            return nil
        }

        let offset = Int(hmac[hmac.count - 1] & 0x0F)
        let truncated = (UInt32(hmac[offset]) & 0x7F) << 24
            | UInt32(hmac[offset + 1]) << 16
            | UInt32(hmac[offset + 2]) << 8
            | UInt32(hmac[offset + 3])

        let mod = UInt32(pow(10, Double(digits)))
        let code = truncated % mod

        return String(format: "%0\(digits)d", code)
    }

    static func secondsRemaining(period: Int = 30, at date: Date = Date()) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    private static func hmacSHA(algorithm: OTPAlgorithm, key: Data, data: Data) -> Data? {
        let ccAlgorithm: CCHmacAlgorithm
        let digestLength: Int

        switch algorithm {
        case .sha1:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA1)
            digestLength = Int(CC_SHA1_DIGEST_LENGTH)
        case .sha256:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA256)
            digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        case .sha512:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA512)
            digestLength = Int(CC_SHA512_DIGEST_LENGTH)
        }

        var hmac = [UInt8](repeating: 0, count: digestLength)

        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(
                    ccAlgorithm,
                    keyPtr.baseAddress, key.count,
                    dataPtr.baseAddress, data.count,
                    &hmac
                )
            }
        }

        return Data(hmac)
    }
}
```

### Shared/KeychainManager.swift
```swift
import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.keyauth.accounts"
    // TODO: Set to "TEAMID.com.keyauth.shared" in production
    private let accessGroup: String? = nil

    private init() {}

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

    func load(id: UUID) throws -> Account? {
        var query = baseQuery(for: id.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }

        return try JSONDecoder().decode(Account.self, from: data)
    }

    func loadAll() throws -> [Account] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [Data] else {
            if status == errSecItemNotFound { return [] }
            throw KeychainError.loadFailed(status)
        }

        let decoder = JSONDecoder()
        return items.compactMap { try? decoder.decode(Account.self, from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func delete(id: UUID) throws {
        let query = baseQuery(for: id.uuidString)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case updateFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .updateFailed(let s): return "Keychain update failed: \(s)"
        case .loadFailed(let s): return "Keychain load failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        }
    }
}
```

### Shared/AccountStore.swift
```swift
import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?

    private let keychain = KeychainManager.shared

    init() { reload() }

    func reload() {
        do {
            accounts = try keychain.loadAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
            accounts = []
        }
    }

    func add(_ account: Account) {
        var newAccount = account
        newAccount.sortOrder = accounts.count
        do {
            try keychain.save(newAccount)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ account: Account) {
        do {
            try keychain.delete(id: account.id)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            try? keychain.delete(id: account.id)
        }
        reload()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        for (index, var account) in accounts.enumerated() {
            account.sortOrder = index
            try? keychain.save(account)
        }
        reload()
    }
}
```

### Shared/BiometricAuthManager.swift
```swift
import LocalAuthentication

enum BiometricType {
    case faceID
    case touchID
    case none
}

final class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    private init() {}

    var availableBiometric: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    func authenticate(reason: String = "Unlock KeyAuth") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
            } catch {
                return false
            }
        }
    }
}
```

### App/KeyAuthApp.swift
```swift
import SwiftUI

@main
struct KeyAuthApp: App {
    @StateObject private var store = AccountStore()
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                } else {
                    LockScreenView(isUnlocked: $isUnlocked)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    isUnlocked = false
                }
            }
        }
    }
}
```

### App/Views/ContentView.swift
```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var searchText = ""

    var filteredAccounts: [Account] {
        if searchText.isEmpty { return store.accounts }
        return store.accounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("KeyAuth")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            showingManualEntry = true
                        } label: {
                            Label("Enter Manually", systemImage: "keyboard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { account in
                    store.add(account)
                    showingScanner = false
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView { account in
                    store.add(account)
                    showingManualEntry = false
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No accounts yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add an account by scanning a QR code or entering a setup key manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 12) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan QR", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    showingManualEntry = true
                } label: {
                    Label("Manual", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }

    private var accountList: some View {
        List {
            ForEach(filteredAccounts) { account in
                AccountRowView(account: account)
            }
            .onDelete(perform: store.delete(at:))
            .onMove(perform: store.move(from:to:))
        }
        .searchable(text: $searchText, prompt: "Search accounts")
        .refreshable { store.reload() }
    }
}
```

### App/Views/AccountRowView.swift
```swift
import SwiftUI

struct AccountRowView: View {
    let account: Account

    @State private var code: String = "------"
    @State private var secondsRemaining: Int = 30
    @State private var copied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var progress: Double { Double(secondsRemaining) / Double(account.period) }

    var timerColor: Color {
        if secondsRemaining <= 5 { return .red }
        if secondsRemaining <= 10 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(issuerColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(issuerInitial)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(issuerColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer.isEmpty ? "Unknown" : account.issuer)
                    .font(.subheadline).fontWeight(.medium)
                Text(account.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(formattedCode)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                    .foregroundStyle(copied ? .green : .primary)
                ZStack {
                    Circle().stroke(timerColor.opacity(0.2), lineWidth: 3).frame(width: 32, height: 32)
                    Circle().trim(from: 0, to: progress)
                        .stroke(timerColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: secondsRemaining)
                    Text("\(secondsRemaining)")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.medium).foregroundStyle(timerColor)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .onReceive(timer) { _ in updateCode() }
        .onAppear { updateCode() }
    }

    private func updateCode() {
        let now = Date()
        code = TOTPGenerator.generate(for: account, at: now) ?? "------"
        secondsRemaining = TOTPGenerator.secondsRemaining(period: account.period, at: now)
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }

    private var formattedCode: String {
        guard code.count >= 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[code.startIndex..<mid]) \(code[mid..<code.endIndex])"
    }

    private var issuerInitial: String { String(account.issuer.prefix(1)).uppercased() }

    private var issuerColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .mint]
        return colors[abs(account.issuer.hashValue) % colors.count]
    }
}
```

### App/Views/LockScreenView.swift
```swift
import SwiftUI

struct LockScreenView: View {
    @Binding var isUnlocked: Bool
    @State private var authFailed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: biometricIcon)
                .font(.system(size: 64))
                .foregroundStyle(.accentColor)
                .symbolEffect(.pulse, options: .repeating)
            Text("KeyAuth").font(.largeTitle).fontWeight(.bold)
            Text("Authenticate to view your codes")
                .font(.subheadline).foregroundStyle(.secondary)
            if authFailed {
                Text("Authentication failed. Tap to retry.")
                    .font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Button { authenticate() } label: {
                Label("Unlock", systemImage: biometricIcon)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
        .onAppear { authenticate() }
    }

    private func authenticate() {
        Task {
            let success = await BiometricAuthManager.shared.authenticate()
            await MainActor.run {
                if success { withAnimation { isUnlocked = true } }
                else { authFailed = true }
            }
        }
    }

    private var biometricIcon: String {
        switch BiometricAuthManager.shared.availableBiometric {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.shield"
        }
    }
}
```

### App/Views/ManualEntryView.swift
```swift
import SwiftUI

struct ManualEntryView: View {
    let onSave: (Account) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var label = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Issuer (e.g. GitHub)", text: $issuer)
                        .textContentType(.organizationName).autocorrectionDisabled()
                    TextField("Label (e.g. user@email.com)", text: $label)
                        .textContentType(.emailAddress).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Secret Key") {
                    TextField("Base32 secret key", text: $secret)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Advanced") {
                    Picker("Algorithm", selection: $algorithm) {
                        ForEach(OTPAlgorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Digits", selection: $digits) {
                        Text("6").tag(6); Text("7").tag(7); Text("8").tag(8)
                    }
                    Picker("Period", selection: $period) {
                        Text("30 seconds").tag(30); Text("60 seconds").tag(60)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(secret.isEmpty)
                }
            }
        }
    }

    private func save() {
        let cleanSecret = secret.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "").uppercased()
        guard Base32.decode(cleanSecret) != nil else { error = "Invalid Base32 secret key"; return }
        let account = Account(issuer: issuer.isEmpty ? "Unknown" : issuer,
            label: label.isEmpty ? issuer : label, secret: cleanSecret,
            algorithm: algorithm, digits: digits, period: period)
        onSave(account)
    }
}
```

### App/Views/QRScannerView.swift
```swift
import SwiftUI
import AVFoundation

struct QRScannerView: View {
    let onScanned: (Account) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRCameraPreview(onCodeDetected: handleCode).ignoresSafeArea()
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .shadow(color: .black.opacity(0.3), radius: 10)
                    Spacer()
                    VStack(spacing: 8) {
                        Text("Point at a QR code").font(.headline).foregroundStyle(.white)
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 20).padding(.vertical, 8)
                                .background(.ultraThinMaterial).clipShape(Capsule())
                        }
                    }.padding(.bottom, 60)
                }
            }
            .navigationTitle("Scan QR Code").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func handleCode(_ code: String) {
        guard !scanned else { return }
        guard let url = URL(string: code) else { error = "Invalid QR code"; return }
        guard let account = Account.from(otpauthURL: url) else {
            error = "Not a valid authenticator QR code"; return
        }
        scanned = true
        onScanned(account)
    }
}

struct QRCameraPreview: UIViewRepresentable {
    let onCodeDetected: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }

        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCodeDetected: onCodeDetected) }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        let onCodeDetected: (String) -> Void
        init(onCodeDetected: @escaping (String) -> Void) { self.onCodeDetected = onCodeDetected }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                          didOutput metadataObjects: [AVMetadataObject],
                          from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr, let value = object.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            session?.stopRunning()
            onCodeDetected(value)
        }
    }
}
```

### KeyboardExtension/KeyboardViewController.swift
```swift
// Full source: 278 lines — UIInputViewController with QWERTY layout + auth bar
// See KeyboardExtension/KeyboardViewController.swift in the project zip
// Key components:
// - authBarCollectionView: horizontal UICollectionView of TOTPCodeCell
// - toggleButton: show/hide auth bar
// - nextKeyboardButton: globe key for switching keyboards
// - keyboardStack: UIStackView with 3 letter rows + bottom row (globe, space, return)
// - didSelectItemAt: calls textDocumentProxy.insertText(code) + haptic feedback
// - 1-second Timer refreshes all visible cells
```

### KeyboardExtension/TOTPCodeCell.swift
```swift
// Full source: 154 lines — UICollectionViewCell
// See KeyboardExtension/TOTPCodeCell.swift in the project zip
// Key components:
// - issuerLabel (10pt, secondary)
// - codeLabel (18pt monospaced, formatted "123 456")
// - countdownRing (CAShapeLayer, animated strokeEnd)
// - refreshDisplay(): generates TOTP, updates ring progress, red color in last 5s
// - flashInserted(): green flash animation on tap
```

### Config Files

**App/Info.plist**: `NSCameraUsageDescription` + `NSFaceIDUsageDescription`

**KeyboardExtension/Info.plist**: `NSExtensionPointIdentifier: com.apple.keyboard-service`, `RequestsOpenAccess: false`

**Both .entitlements files**: `com.apple.security.application-groups: [group.com.keyauth.shared]`, `keychain-access-groups: [$(AppIdentifierPrefix)com.keyauth.shared]`

**project.yml**: XcodeGen spec with two targets (KeyAuth app + KeyAuthKeyboard extension), iOS 16.0 deployment, Swift 5.9.

---

## Instructions for AI Assistants

When continuing work on this project:
1. The user's name is Yashesh. He's a Principal Software Engineer with deep iOS/Swift and enterprise auth expertise.
2. Generate code directly — don't ask clarifying questions unless genuinely blocked.
3. Never use Vercel — use Railway for any backend/relay deployment.
4. Never use Mermaid for diagrams — use Draw.io.
5. Never attribute AI as co-author in commits.
6. The project has zero external dependencies — keep it that way unless there's a strong reason.
7. Keyboard extensions have a 50MB memory limit and can't use SwiftUI hosting reliably.
8. The `accessGroup` in `KeychainManager` is `nil` for dev — this is intentional but must be set for the extension to actually read accounts.
