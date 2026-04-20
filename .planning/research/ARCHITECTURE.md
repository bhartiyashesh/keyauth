# Architecture Research

**Domain:** v2.0 feature integration into existing TOTP authenticator (iOS + keyboard extension)
**Researched:** 2026-04-16
**Confidence:** HIGH

## System Overview -- Current + v2.0 Changes

```
+---------------------------------------------------------------------+
|                     Main App (SwiftUI)                               |
|  +----------------+  +------------------+  +---------------------+  |
|  | AccountStore   |  | MigrationCoord   |  | NEW: OnboardingMgr  |  |
|  | (@MainActor)   |  | (iCloud sync)    |  | (state machine)     |  |
|  +-------+--------+  +------------------+  +---------------------+  |
|          |                                                           |
|  +-------v--------+  +------------------+  +---------------------+  |
|  | KeychainMgr    |  | NEW: Protobuf    |  | NEW: ExportManager  |  |
|  | (CRUD, sync)   |  | Decoder (GA imp) |  | (AES-GCM export)   |  |
|  +-------+--------+  +------------------+  +---------------------+  |
+----------|-----------+------------------------------+----------------+
           |           |                              |
   +-------v--------+ | App Groups (UserDefaults)     |  Keychain
   | Keychain (iOS)  | +----v-------------------------+  (shared
   | access group:   | |                                  access group)
   | W646UCTVQV...   | |
   +-------+---------+ |
           |           |
+----------v-----------v----------------------------------------------+
|                   Keyboard Extension (UIKit)                         |
|  +-------------------+  +------------------+  +------------------+  |
|  | KeyboardViewCtrl  |  | NEW: FilterBar   |  | SharedDefaults   |  |
|  | UIInputViewCtrl   |  | (UIButton row,   |  | (reads accounts) |  |
|  | + UICollectionView|  |  NO UITextField) |  +------------------+  |
|  +-------------------+  +------------------+                         |
|  +-------------------+                                               |
|  | NEW: SmartSort    |  Sorts by lastUsed/useCount from SharedDefs   |
|  +-------------------+                                               |
+---------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Status |
|-----------|----------------|--------|
| Account (struct) | TOTP account model, Codable, otpauth:// parsing | MODIFY: add lastUsed, useCount |
| AccountStore | @MainActor CRUD, dedup, KVS observer, SharedDefaults push | MODIFY: track usage stats |
| KeychainManager | Keychain CRUD with sync-awareness | NO CHANGE |
| SharedDefaults | App Groups bridge (app -> keyboard) | MODIFY: include usage metadata, expose suite |
| KeyboardViewController | UIInputViewController, UICollectionView | MODIFY: add filter bar, smart sort, usage event writing |
| NEW: GoogleAuthImporter | Protobuf decode -> Account pipeline | NEW |
| NEW: ExportManager | Encrypted backup file generation | NEW |
| NEW: OnboardingManager | Onboarding state machine across app + extension | NEW |

## Integration Point 1: Account Model Migration (lastUsed / useCount)

### Problem

Adding `lastUsed: Date?` and `useCount: Int` to `Account` must not break decoding of existing Keychain JSON that lacks these fields.

### Solution: Optional properties with custom init(from:)

Swift's `Codable` automatically handles missing keys for Optional properties -- `JSONDecoder` calls `decodeIfPresent` which returns `nil` for absent keys. For `useCount` (non-optional Int with default 0), use a custom `init(from: Decoder)`.

**Confidence:** HIGH -- this is documented Swift Codable behavior. Optional properties decode to `nil` when the key is absent. No Keychain data migration needed.

### Modified Account struct

```swift
struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var issuer: String
    var label: String
    var secret: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var sortOrder: Int
    var createdAt: Date

    // v2.0 additions -- backward compatible
    var lastUsed: Date?      // nil = never used. Optional -> absent key decodes to nil
    var useCount: Int         // 0 = never used. Needs custom decoder for default

    init(
        id: UUID = UUID(),
        issuer: String,
        label: String,
        secret: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        sortOrder: Int = 0,
        lastUsed: Date? = nil,
        useCount: Int = 0
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
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        issuer = try container.decode(String.self, forKey: .issuer)
        label = try container.decode(String.self, forKey: .label)
        secret = try container.decode(String.self, forKey: .secret)
        algorithm = try container.decode(OTPAlgorithm.self, forKey: .algorithm)
        digits = try container.decode(Int.self, forKey: .digits)
        period = try container.decode(Int.self, forKey: .period)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Backward-compatible: missing keys get defaults
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
    }
}
```

### Why this is safe

1. Existing Keychain items are JSON blobs stored as `kSecValueData`. JSONDecoder with `decodeIfPresent` handles missing keys gracefully.
2. No need to version the data or run a migration pass. The first `save()` after a `reload()` will write the new fields.
3. iCloud Keychain sync: if device A (v2.0) saves an account with `lastUsed`, device B (v1.0) would need to handle unknown keys. Since we control both ends and v2.0 will be the only version, this is not a concern.
4. SharedDefaults also uses JSONEncoder/JSONDecoder on `[Account]` -- same backward compatibility applies.

### Usage tracking integration

When the keyboard inserts a code or CodeApprovalView sends a code via relay, call:

```swift
// In AccountStore
func recordUsage(for accountId: UUID) {
    guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
    accounts[idx].lastUsed = Date()
    accounts[idx].useCount += 1
    try? keychain.save(accounts[idx], synchronizable: SyncPreference.isEnabled)
    SharedDefaults.saveAccounts(accounts)
}
```

The keyboard extension calls this indirectly: after inserting a code, it writes the account ID + timestamp to a SharedDefaults key (`last_used_account`). On next app foreground, AccountStore reads and applies it. The keyboard cannot write to Keychain directly (it reads via SharedDefaults), so the "write-back" pattern uses App Groups UserDefaults as a message queue.

## Integration Point 2: Google Authenticator Protobuf Import

### Protobuf Schema (reverse-engineered, community-verified)

```protobuf
message MigrationPayload {
    repeated OtpParameters otp_parameters = 1;
    optional int32 version = 2;
    optional int32 batch_size = 3;
    optional int32 batch_index = 4;
    optional int32 batch_id = 5;
}

message OtpParameters {
    optional bytes  secret    = 1;  // Raw bytes (NOT base32)
    optional string name      = 2;  // "issuer:label" or just "label"
    optional string issuer    = 3;
    optional Algorithm algorithm = 4;
    optional DigitCount digits = 5;
    optional OtpType type     = 6;  // TOTP=2, HOTP=1
    optional int64 counter    = 7;  // HOTP only
}

enum Algorithm { UNSPECIFIED=0; SHA1=1; SHA256=2; SHA512=3; MD5=4; }
enum DigitCount { UNSPECIFIED=0; SIX=1; EIGHT=2; }
enum OtpType { UNSPECIFIED=0; HOTP=1; TOTP=2; }
```

**Confidence:** HIGH -- schema verified across multiple independent sources (Aegis PR #406, qistoph/otp_export, alexbakker blog, zwyx blog). Google does not publish an official spec, but the community schema has been stable since Google Authenticator 5.10+.

### Decode Pipeline

```
otpauth-migration://offline?data=BASE64_DATA
    |
    v
1. URL-decode the `data` query parameter
    |
    v
2. Base64-decode to raw bytes
    |
    v
3. Pure-Swift protobuf decode (no external library)
    |  - Read varint field tags
    |  - Extract repeated OtpParameters messages
    |  - For each: extract secret (bytes), name, issuer, algorithm, digits, type
    |
    v
4. Map to [Account] via new Account.from(migrationParameters:)
    |  - secret: Base32-ENCODE the raw bytes (GA stores raw, KeyAuth stores base32)
    |  - name: split on ":" for issuer:label (same logic as otpauth:// parser)
    |  - algorithm: map enum (1->SHA1, 2->SHA256, 3->SHA512)
    |  - digits: map enum (1->6, 2->8), default 6
    |  - type: skip HOTP entries (KeyAuth is TOTP-only)
    |  - counter: ignored (TOTP only)
    |
    v
5. Feed into AccountStore.add() which handles dedup + Keychain save + SharedDefaults push
```

### New Component: GoogleAuthImporter

```swift
enum GoogleAuthImporter {
    struct MigrationPayload {
        let accounts: [OtpParameters]
        let batchSize: Int
        let batchIndex: Int
        let batchId: Int
    }

    struct OtpParameters {
        let secret: Data         // Raw bytes
        let name: String
        let issuer: String
        let algorithm: Int       // 0=unspec, 1=SHA1, 2=SHA256, 3=SHA512
        let digits: Int          // 0=unspec, 1=six, 2=eight
        let type: Int            // 1=HOTP, 2=TOTP
        let counter: Int64
    }

    /// Decode otpauth-migration:// URL into Account array.
    /// Returns only TOTP accounts (skips HOTP).
    static func decode(url: URL) -> [Account]? {
        guard url.scheme == "otpauth-migration",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = Data(base64Encoded: dataParam) else {
            return nil
        }
        let payload = decodeProtobuf(data)
        return payload.accounts
            .filter { $0.type != 1 }  // Skip HOTP
            .compactMap { param -> Account? in
                let base32Secret = Base32.encode(param.secret)
                guard !base32Secret.isEmpty else { return nil }
                return Account(
                    issuer: param.issuer,
                    label: extractLabel(from: param.name, issuer: param.issuer),
                    secret: base32Secret,
                    algorithm: mapAlgorithm(param.algorithm),
                    digits: param.digits == 2 ? 8 : 6,
                    period: 30
                )
            }
    }

    /// Pure Swift protobuf decoder -- no external library.
    /// Only needs to handle: varint, length-delimited wire types.
    private static func decodeProtobuf(_ data: Data) -> MigrationPayload { ... }
}
```

### Critical implementation notes

1. **Secret encoding mismatch:** Google stores raw bytes in the protobuf `secret` field. KeyAuth stores Base32-encoded strings. You must `Base32.encode()` the raw bytes. The existing `Base32` module currently only has `decode()` -- you need to add an `encode(Data) -> String` method.

2. **Batch scanning:** Google Authenticator splits large exports across multiple QR codes (batch_size > 1). The UI must support scanning multiple QR codes in sequence and accumulating results before calling `AccountStore.add()` in a loop.

3. **Dedup on import:** The existing cross-id dedup in `AccountStore.dedupInMemory()` will catch duplicates if the user re-imports. No additional dedup logic needed in the importer.

4. **name field parsing:** The `name` field format is "Issuer:label" or just "label" -- identical to the path parsing in `Account.from(otpauthURL:)`. Extract and reuse that logic.

## Integration Point 3: Keyboard Search Without "Allow Full Access"

### Key constraint

A UITextField placed inside the keyboard extension's `inputView` does NOT require "Allow Full Access". Full Access is only needed for network, shared containers with containing app (beyond App Groups), pasteboard, location, etc. Standard UIKit views work in the sandboxed keyboard.

**Confidence:** HIGH -- Apple's Custom Keyboard documentation explicitly states you can "add objects such as views, controls, and gesture recognizers" to the input view controller's primary view. Full Access gates are only on specific APIs (network, pasteboard, etc.), not on UIKit views.

### The first-responder problem

The critical challenge: when the user taps a UITextField inside the keyboard, it becomes first responder. This steals focus from the host app's text field. After that, `textDocumentProxy.insertText()` stops working because the proxy now points to the keyboard's own text field.

### Solution: Do NOT use UITextField -- use a button-based filter bar

```
+------------------------------------------------------------------+
| [globe] [shield] KeyAuth          [A][B]...[Z] [X clear]        |  <- top bar with letter filter
|------------------------------------------------------------------|
| [GitHub - user@email.com          123 456  (27)]                 |
| [Google - work@company.com        789 012  (15)]                 |
| [Slack  - myaccount              345 678  (22)]                  |
+------------------------------------------------------------------+
```

**Approach: Character-button filter bar (no UITextField)**

1. Add a horizontally-scrolling UIStackView of tappable letter buttons (A-Z) + a clear button to the top bar area.
2. Tapping a letter filters `accounts` to those whose issuer starts with that letter.
3. No first-responder conflict -- buttons never steal focus from the host app's text field.
4. Accounts list remains in UICollectionView, filtered by the selected letter prefix.
5. `textDocumentProxy.insertText()` continues to work normally.

**Why NOT a UITextField workaround:**

Various workarounds exist (override `canBecomeFirstResponder`, immediately resign, custom CALayer-based text rendering). All are fragile across iOS versions and violate the UIKit responder chain contract. The button filter is robust, simple, and achieves 90% of the search value for TOTP accounts (most users have < 30 accounts; alphabetical filtering by issuer first letter is sufficient).

### Implementation in KeyboardViewController

```swift
// Add to KeyboardViewController:
private var filterLetter: String? = nil
private var allAccounts: [Account] = []

private var displayedAccounts: [Account] {
    guard let letter = filterLetter else { return sortedAccounts }
    return sortedAccounts.filter {
        $0.issuer.localizedUppercase.hasPrefix(letter.uppercased())
    }
}

// Smart sort: recency + frequency hybrid
private var sortedAccounts: [Account] {
    allAccounts.sorted { a, b in
        // Primary: accounts used in last 5 minutes go first (active session)
        let recentThreshold = Date().addingTimeInterval(-300)
        let aRecent = (a.lastUsed ?? .distantPast) > recentThreshold
        let bRecent = (b.lastUsed ?? .distantPast) > recentThreshold
        if aRecent != bRecent { return aRecent }

        // Secondary: use count (frequency)
        if a.useCount != b.useCount { return a.useCount > b.useCount }

        // Tertiary: original sort order
        return a.sortOrder < b.sortOrder
    }
}
```

The filter bar is a horizontal UIScrollView with a UIStackView of UIButtons placed between the top bar and the collection view. Total height increase: ~32pt, keeping the keyboard within comfortable bounds (~252pt total).

## Integration Point 4: Encrypted Backup Export

### Architecture

ExportManager reads all accounts from AccountStore (already loaded from Keychain), serializes to JSON, encrypts with a user-provided password, and writes to a `.keyauth` file that can be shared via UIActivityViewController.

### File format specification (.keyauth)

```
+--------------------------------------------------+
| Bytes 0-7:   Magic number "KEYAUTH\0" (8 bytes)  |
| Bytes 8-9:   Format version (UInt16 BE) = 1      |
| Bytes 10-13: KDF iterations (UInt32 BE)           |
| Bytes 14-29: Salt (16 bytes, random)              |
| Bytes 30-41: Nonce/IV (12 bytes, random)          |
| Bytes 42+:   AES-256-GCM ciphertext + tag         |
|              (plaintext = JSON array of Account)   |
+--------------------------------------------------+
```

### Encryption pipeline

```
User password
    |
    v
PBKDF2-SHA256 (password, salt, iterations=600_000) -> 32-byte key
    |
    v
AES-256-GCM(key, nonce, plaintext=JSON) -> ciphertext + 16-byte auth tag
    |
    v
Write header + salt + nonce + ciphertext to .keyauth file
```

### Implementation

```swift
import CryptoKit
import CommonCrypto  // for PBKDF2

enum ExportManager {
    static func export(accounts: [Account], password: String) throws -> Data {
        let json = try JSONEncoder().encode(accounts)
        let salt = randomBytes(16)
        let nonce = randomBytes(12)
        let iterations: UInt32 = 600_000

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealedBox = try AES.GCM.seal(
            json,
            using: key,
            nonce: AES.GCM.Nonce(data: nonce)
        )

        var output = Data()
        output.append(contentsOf: "KEYAUTH\0".utf8)
        output.append(contentsOf: withUnsafeBytes(of: UInt16(1).bigEndian) { Array($0) })
        output.append(contentsOf: withUnsafeBytes(of: iterations.bigEndian) { Array($0) })
        output.append(salt)
        output.append(nonce)
        output.append(sealedBox.ciphertext + sealedBox.tag)
        return output
    }

    static func decrypt(data: Data, password: String) throws -> [Account] {
        // Parse header, extract salt/nonce/iterations, derive key, decrypt
        guard data.count > 42 else { throw ExportError.invalidFormat }
        guard String(data: data[0..<7], encoding: .utf8) == "KEYAUTH" else {
            throw ExportError.invalidMagic
        }
        // ... extract fields by offset, derive key, AES.GCM.open()
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var derivedKey = Data(count: 32)
        let passwordData = password.data(using: .utf8)!
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ExportError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
```

### Why these choices

| Decision | Rationale |
|----------|-----------|
| AES-256-GCM | Authenticated encryption. Available in CryptoKit (no external dependency). |
| PBKDF2-SHA256 | Available in CommonCrypto (ships with iOS). 600K iterations is OWASP 2023 recommendation. |
| Custom binary format | Simple, self-contained. No protobuf or ASN.1 dependency. Easy to parse cross-platform. |
| JSON plaintext | Reuses existing Account Codable. No separate serialization logic. |
| Magic number + version | File type detection. Forward compatibility for format changes. |

### Data flow

```
SettingsView "Export Backup" button
    |
    v
Prompt for password (+ confirm)
    |
    v
ExportManager.export(accounts: store.accounts, password: pwd)
    |  reads from AccountStore.accounts (already loaded from Keychain)
    |  NOT from SharedDefaults (may be stale or have dedup artifacts)
    v
UIActivityViewController with temporary .keyauth file
    |
    v
User shares to Files, AirDrop, email, etc.
```

## Integration Point 5: Onboarding State Machine

### State management across app + keyboard extension

The onboarding flow has two audiences:
1. **Main app:** Welcome screens, import prompt, keyboard activation guide
2. **Keyboard extension:** Needs to know "has user completed onboarding?" to show/hide help hints

### State storage

Use SharedDefaults (App Groups UserDefaults) -- the same mechanism already bridging accounts between app and extension. Both processes can read and write to it.

```swift
enum OnboardingState: String, Codable {
    case notStarted          // Fresh install
    case welcomeCompleted    // Saw welcome screens
    case accountsAdded       // Has at least one account
    case keyboardEnabled     // System keyboard is activated
    case keyboardTested      // User actually used the keyboard once
    case completed           // Full onboarding done
}

enum OnboardingManager {
    private static let key = "onboarding_state"
    private static let keyboardHintShownKey = "keyboard_hint_shown"

    static var state: OnboardingState {
        guard let raw = SharedDefaults.suite?.string(forKey: key),
              let state = OnboardingState(rawValue: raw) else {
            return .notStarted
        }
        return state
    }

    static func advance(to newState: OnboardingState) {
        SharedDefaults.suite?.set(newState.rawValue, forKey: key)
        SharedDefaults.suite?.synchronize()
    }

    static var hasShownKeyboardHint: Bool {
        SharedDefaults.suite?.bool(forKey: keyboardHintShownKey) ?? false
    }

    static func markKeyboardHintShown() {
        SharedDefaults.suite?.set(true, forKey: keyboardHintShownKey)
    }
}
```

### SharedDefaults modification needed

The existing `SharedDefaults` enum uses `private static var suite`. Change to `static var suite` (internal access) so OnboardingManager and other shared components can use it directly. This is a one-word change with zero behavioral impact.

### Keyboard extension reads onboarding state

```swift
// In KeyboardViewController.viewDidLoad():
if OnboardingManager.state == .keyboardEnabled && !OnboardingManager.hasShownKeyboardHint {
    showFirstUseHint()  // "Tap any code to insert it directly"
    OnboardingManager.markKeyboardHintShown()
}
```

### Keyboard extension writes onboarding advancement

```swift
// In KeyboardViewController.collectionView(_:didSelectItemAt:):
// After successful code insertion:
if OnboardingManager.state == .keyboardEnabled {
    OnboardingManager.advance(to: .keyboardTested)
}
```

### Keyboard activation detection

There is no reliable API to detect if a custom keyboard is enabled in system settings. The standard heuristic:

```swift
// Poll on app foreground (sceneDidBecomeActive):
static func checkKeyboardEnabled() -> Bool {
    // Read the system preference file (best-effort, may not work on all iOS versions)
    // Alternative: use UITextInputMode.activeInputModes (unreliable)
    //
    // Most robust approach: ask the user to confirm in the onboarding flow
    // with a "I've added the keyboard" button, then verify by showing a
    // test text field and checking if the keyboard appears.
    return false // Placeholder -- needs manual confirmation in practice
}
```

**Recommended approach:** Do not auto-detect. Instead, guide the user with step-by-step instructions and a "Done" button. On the next screen, show a test text field. If the user can switch to the KeyAuth keyboard, mark `keyboardEnabled`. This is the pattern used by Grammarly, SwiftKey, and other keyboard extensions.

## Data Flow Changes Summary

### Current data flow (v1.0)

```
Keychain --> AccountStore --> SharedDefaults --> Keyboard (read-only)
```

### New data flow (v2.0)

```
Keychain --> AccountStore --> SharedDefaults --> Keyboard
                 ^                  |                |
                 |            Onboarding state       |
                 |            (read/write both)      |
                 |                                   v
            recordUsage() <-- "last_used_account" <-- Keyboard writes
                 |                                     usage event after
                 |                                     code insertion
            ExportManager.export(store.accounts)
                 |
            GoogleAuthImporter.decode(url) --> store.add() loop
```

### Usage tracking round-trip (keyboard -> app)

1. Keyboard inserts code for account X
2. Keyboard writes to SharedDefaults: `["accountId": "uuid", "timestamp": "ISO8601"]`
3. App foregrounds (or AccountStore reload fires)
4. AccountStore reads `last_used_account` from SharedDefaults
5. AccountStore calls `recordUsage(for: uuid)` which updates Keychain + clears the SharedDefaults key
6. `SharedDefaults.saveAccounts()` propagates updated lastUsed/useCount back to keyboard

This avoids giving the keyboard extension direct Keychain write access while keeping usage stats persistent.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Keyboard writing directly to Keychain

**What people do:** Give the keyboard extension write access to Keychain to update lastUsed.
**Why it's wrong:** Keychain writes from the extension can race with writes from the main app. The existing architecture deliberately treats the keyboard as read-only (via SharedDefaults). Introducing writes creates a sync conflict surface the current dedup pipeline does not handle.
**Do this instead:** Use SharedDefaults as a message queue. Keyboard writes a "usage event"; main app reads and applies on next reload.

### Anti-Pattern 2: UITextField in keyboard for search

**What people do:** Add a UITextField to the keyboard view for full-text search.
**Why it's wrong:** Steals first responder from the host app's text field. After the user taps the search field, `textDocumentProxy.insertText()` stops working. The user must tap back into the host app's field, defeating the purpose.
**Do this instead:** Use a letter-button filter bar (UIButtons) that never becomes first responder.

### Anti-Pattern 3: External protobuf library for GA import

**What people do:** Add swift-protobuf or another protobuf library to decode MigrationPayload.
**Why it's wrong:** Violates the "no external iOS dependencies" constraint. The GA protobuf schema is simple (6 field types, no nesting beyond repeated messages).
**Do this instead:** Write a minimal pure-Swift protobuf decoder that handles varint + length-delimited wire types. Approximately 100 lines of code.

### Anti-Pattern 4: Storing onboarding state in UserDefaults.standard

**What people do:** Use `UserDefaults.standard` for onboarding flags.
**Why it's wrong:** The keyboard extension runs in a separate process and cannot read `UserDefaults.standard` from the main app.
**Do this instead:** Store in App Groups UserDefaults (`SharedDefaults.suite`), which both the app and the keyboard extension can access.

### Anti-Pattern 5: Reading from Keychain in ExportManager

**What people do:** Have ExportManager call `KeychainManager.loadAll()` directly.
**Why it's wrong:** Creates a second call path that bypasses the dedup pipeline in AccountStore. Could export duplicate accounts that `dedupInMemory` had already collapsed.
**Do this instead:** Read from `AccountStore.accounts` which is the post-dedup, canonical account list.

## Recommended Build Order (Dependency-Aware)

```
Phase 1: Account model + smart sort (foundation for everything)
    - Add lastUsed/useCount to Account with backward-compatible decoder
    - Add Base32.encode() (needed by GA importer in Phase 3)
    - Add recordUsage() to AccountStore
    - Add usage writeback mechanism in SharedDefaults
    - Update KeyboardViewController: smart sort + usage event writing
    WHY FIRST: Every other feature depends on the updated Account model.

Phase 2: Keyboard filter bar
    - Add FilterBarView (horizontal scrolling letter buttons)
    - Integrate into KeyboardViewController layout (between top bar and collection)
    - Wire filtering logic to displayedAccounts
    WHY SECOND: Small, self-contained, immediately testable in keyboard.
               Depends only on Phase 1 (smart sort).

Phase 3: Google Authenticator import
    - GoogleAuthImporter: pure-Swift protobuf decoder + Account mapping
    - Base32.encode() (should be done in Phase 1)
    - ImportView UI (QR scan, batch handling UI, preview list, confirm button)
    WHY THIRD: Depends on Account model being stable. Gives users a way to
              populate accounts (makes onboarding more useful).

Phase 4: Encrypted backup export
    - ExportManager (PBKDF2 + AES-GCM, CryptoKit + CommonCrypto)
    - ExportView UI (password entry, confirm, share sheet)
    - Decrypt function (for future import, useful for round-trip testing)
    WHY FOURTH: Independent of other features. Needs stable Account model.

Phase 5: Onboarding flow
    - OnboardingManager (state machine in SharedDefaults)
    - OnboardingView (welcome screens)
    - KeyboardSetupGuideView (activation walkthrough with illustrations)
    - Import prompt (links to Phase 3 ImportView)
    - Keyboard first-use hint overlay
    WHY LAST: Touches the most surfaces (app + keyboard + settings detection).
             Benefits from all other features being complete so onboarding can
             reference them (import, keyboard usage, export as backup step).
```

## New Files Summary

```
Shared/
    Account.swift                  # MODIFY: add lastUsed, useCount, custom init(from:)
    AccountStore.swift             # MODIFY: add recordUsage(), consumeUsageEvent()
    SharedDefaults.swift           # MODIFY: make suite internal, add usage event keys
    GoogleAuthImporter.swift       # NEW: protobuf decode + Account mapping
    ExportManager.swift            # NEW: encrypted backup export/import
    OnboardingManager.swift        # NEW: onboarding state machine
    Base32.swift                   # MODIFY: add encode(Data) -> String

KeyboardExtension/
    KeyboardViewController.swift   # MODIFY: filter bar, smart sort, usage writeback
    FilterBarView.swift            # NEW: horizontal letter-button UIView

App/Views/
    OnboardingView.swift           # NEW: welcome + keyboard guide screens
    ImportView.swift               # NEW: GA import flow (scan, preview, confirm)
    ExportView.swift               # NEW: password entry + export trigger
    KeyboardSetupGuideView.swift   # NEW: step-by-step keyboard activation
```

## Sources

- [Apple Custom Keyboard Extension Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) -- capabilities, restrictions, Full Access requirements
- [Parsing Google Authenticator Export QR Codes (Alex Bakker)](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html) -- protobuf schema and decoding process
- [qistoph/otp_export OtpMigration.proto](https://github.com/qistoph/otp_export/blob/master/OtpMigration.proto) -- protobuf schema definition file
- [Google Authenticator Export Format (Zwyx)](https://zwyx.dev/blog/google-authenticator-export-format) -- additional schema verification
- [Swift Codable Backward Compatibility (Lightricks)](https://medium.com/lightricks-tech-blog/backwards-compatibility-in-swift-990d3ca05624) -- optional property migration pattern
- [Swift Forums: Decoding Optionals Missing in JSON](https://forums.swift.org/t/decoding-of-optionals-missing-in-json/52475) -- decodeIfPresent behavior
- [UIInputViewController Documentation](https://developer.apple.com/documentation/uikit/uiinputviewcontroller) -- keyboard extension API

---
*Architecture research for: KeyAuth v2.0 feature integration*
*Researched: 2026-04-16*
