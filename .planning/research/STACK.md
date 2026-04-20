# Technology Stack

**Project:** KeyAuth v2.0 -- New Feature Stack Additions
**Researched:** 2026-04-16
**Overall confidence:** HIGH

---

## Context

This file covers ONLY the stack additions needed for v2.0 new features: Google Authenticator protobuf import, encrypted backup export, recency/frequency tracking, and keyboard search/filter. The existing stack (CryptoKit, CommonCrypto, UIKit, Foundation, iCloud Keychain) is validated and not re-researched.

**Key constraint: Zero external iOS dependencies. All v2.0 features are achievable with system frameworks only.**

---

## 1. Google Authenticator Protobuf Import

### Technology: Hand-Rolled Proto3 Decoder (~120 lines Swift)

**Use Foundation `Data` only.** Do not add `apple/swift-protobuf` SPM package.

Google Auth's `otpauth-migration://` schema is trivially simple: 2 message types, 3 enums, 12 total fields. A full protobuf library (60K+ lines of code) for this is massive overkill and violates the zero-deps constraint.

### Verified Proto3 Schema

```
MigrationPayload {
  repeated OtpParameters otp_parameters = 1;  // wire type 2 (LEN)
  int32 version = 2;                          // wire type 0 (VARINT)
  int32 batch_size = 3;                       // wire type 0 (VARINT)
  int32 batch_index = 4;                      // wire type 0 (VARINT)
  int32 batch_id = 5;                         // wire type 0 (VARINT)
}

OtpParameters {
  bytes secret = 1;              // wire type 2 (LEN) -- RAW bytes, NOT base32
  string name = 2;               // wire type 2 (LEN) -- "Issuer:label" format
  string issuer = 3;             // wire type 2 (LEN)
  Algorithm algorithm = 4;       // wire type 0 (VARINT)
  DigitCount digits = 5;         // wire type 0 (VARINT)
  OtpType type = 6;              // wire type 0 (VARINT)
  int64 counter = 7;             // wire type 0 (VARINT) -- HOTP only
}

Algorithm:  0=UNSPECIFIED, 1=SHA1, 2=SHA256, 3=SHA512, 4=MD5
DigitCount: 0=UNSPECIFIED, 1=SIX, 2=EIGHT
OtpType:    0=UNSPECIFIED, 1=HOTP, 2=TOTP
```

### Wire Format Decoding Rules

Only two wire types needed:

| Wire Type | Number | Decoding |
|-----------|--------|----------|
| VARINT | 0 | Read bytes while MSB=1; combine lower 7 bits little-endian |
| LEN | 2 | Read varint (byte count), then read N bytes |

Tag decoding: `field_number = tag >> 3`, `wire_type = tag & 0x07`

The decoder needs 3 functions:
- `decodeVarint(from data: Data, at offset: inout Int) -> UInt64`
- `decodeLengthDelimited(from data: Data, at offset: inout Int) -> Data`
- `decodeMigrationPayload(data: Data) throws -> [GoogleAuthAccount]`

### Critical Integration Details

- **Secret field is RAW bytes** -- must Base32-encode before storing in `Account.secret`. Existing `Base32.swift` has `decode()` but needs `encode(Data) -> String` added (verify and add if missing).
- **Name field format** -- `"Issuer:label"` or just `"label"`. Parse with `split(separator: ":", maxSplits: 1)` -- same logic as existing `Account.from(otpauthURL:)`.
- **Algorithm mapping** -- Direct: 1=SHA1, 2=SHA256, 3=SHA512. Map 0 (UNSPECIFIED) to SHA1 (Google Auth default). Skip MD5 (4) -- not used in practice.
- **Filter HOTP entries** -- KeyAuth is TOTP-only. Show warning to user if HOTP accounts found.
- **Batch QR codes** -- Google Auth splits exports of >10 accounts across multiple QR codes. Track `batch_id` + `batch_index` to merge. Show progress ("Scanned 2 of 3 QR codes").
- **Dedup on import** -- Run imported accounts through existing `DedupKey` before adding to avoid duplicates.

### URI Decoding Pipeline

```
otpauth-migration://offline?data=<url-encoded-base64>
  |-> URL decode the data parameter
  |-> Base64 decode to raw bytes
  |-> Proto3 decode to [OtpParameters]
  |-> Map to [Account] (Base32-encode secrets, parse names, map enums)
  |-> Dedup against existing accounts
  |-> Add via AccountStore
```

---

## 2. Encrypted Backup Export/Import

### Technology: CommonCrypto PBKDF2 + CryptoKit AES-256-GCM

Both frameworks are already linked in the project. No new imports needed.

### Encryption Scheme

```
User password
  |-> PBKDF2-HMAC-SHA256 (600,000 iterations, 16-byte random salt)
  |-> 32-byte derived key
  |-> SymmetricKey
  |-> AES.GCM.seal(accountsJSON, using: key)
  |-> .keyauth file
```

### PBKDF2 Key Derivation (CommonCrypto -- already linked)

```swift
import CommonCrypto

func deriveKey(password: String, salt: Data, iterations: UInt32 = 600_000) -> Data {
    var derivedKey = Data(count: 32)
    let passwordData = Data(password.utf8)
    derivedKey.withUnsafeMutableBytes { derivedBytes in
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
                    derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    32
                )
            }
        }
    }
    return derivedKey
}
```

### AES-256-GCM Encryption (CryptoKit -- already linked)

```swift
import CryptoKit

// Encrypt
let key = SymmetricKey(data: derivedKeyData)
let sealed = try AES.GCM.seal(plaintext, using: key)
// sealed.nonce (12 bytes), sealed.ciphertext, sealed.tag (16 bytes)

// Decrypt
let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
let decrypted = try AES.GCM.open(box, using: key)
```

### .keyauth File Format

```json
{
  "version": 1,
  "salt": "<base64 16-byte salt>",
  "iterations": 600000,
  "nonce": "<base64 12-byte nonce>",
  "ciphertext": "<base64 encrypted accounts JSON>",
  "tag": "<base64 16-byte GCM auth tag>"
}
```

**Why JSON wrapper (not raw binary):**
- `version` field enables future format evolution
- `iterations` stored in file so we can increase later without breaking old exports
- Human-debuggable if something goes wrong
- Base64 overhead is negligible (accounts metadata is typically <50KB)

**Why AES-GCM not ChaChaPoly:** AES-GCM is the industry standard for encrypted file formats. More universally understood and interoperable if we later add Android or web import. ChaChaPoly would also work (already used for relay E2E) but AES-GCM is the better choice for files.

### Iteration Count Rationale

OWASP 2025 recommends 600,000 for PBKDF2-HMAC-SHA256. Storing iterations in the file means:
- Old exports at 600K remain decryptable forever
- New exports can bump to 800K+ when hardware advances
- No hardcoded assumption in the decoder

### Salt Generation

```swift
var salt = Data(count: 16)
_ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
```

`SecRandomCopyBytes` from the Security framework (already linked for Keychain operations).

### File Sharing

Register `.keyauth` UTI via `UniformTypeIdentifiers` framework. Export via `UIActivityViewController` (share sheet). Import via document picker or "Open In" from Files app.

---

## 3. Recency/Frequency Tracking

### Technology: Extend Account Codable struct + SharedDefaults

No new frameworks. Two new fields on the existing model.

### Account Model Changes

```swift
struct Account: Codable, Identifiable, Equatable {
    // ... existing fields (id, issuer, label, secret, algorithm, digits, period, sortOrder, createdAt) ...
    var lastUsedAt: Date?    // nil = never used. Updated on code insertion.
    var useCount: Int         // 0 = never used. Incremented on each use.
}
```

**Backward compatibility:** Use `init(from decoder:)` with defaults:
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... decode existing fields ...
    lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
}
```

Existing accounts encoded without these fields will decode successfully with `lastUsedAt = nil` and `useCount = 0`.

### Smart Sort Algorithm

```swift
func smartScore(lastUsed: Date?, useCount: Int) -> Double {
    let recencyScore: Double
    if let lastUsed = lastUsed {
        let hoursSince = Date().timeIntervalSince(lastUsed) / 3600
        recencyScore = max(0, 1.0 - (hoursSince / 168)) // Decays over 1 week
    } else {
        recencyScore = 0
    }
    let frequencyScore = min(1.0, Double(useCount) / 50.0) // Caps at 50 uses
    return recencyScore * 0.7 + frequencyScore * 0.3 // Recency dominates
}
```

Recency should dominate because during re-auth flows, the user needs the same account they used seconds ago. Frequency is a tiebreaker for accounts not recently used.

### Update Flow

1. Keyboard extension: user taps code -> `textDocumentProxy.insertText(code)` -> update `lastUsedAt = Date()` and `useCount += 1`
2. Write updated account back to SharedDefaults (App Group) -- keyboard extension already reads from SharedDefaults
3. On next `AccountStore.reload()`, main app picks up usage data and persists to Keychain

**Important:** Keyboard extension should write usage updates to SharedDefaults, NOT directly to Keychain. Keychain writes from extensions can be slow and the extension has limited execution time. SharedDefaults write is fast. The main app syncs to Keychain on next launch.

---

## 4. Search/Filter in Keyboard Extension

### Technology: Custom UILabel-based filter (NO UITextField)

**Critical constraint: UITextField inside UIInputViewController breaks the responder chain.** Once a UITextField becomes first responder inside the keyboard extension, `textDocumentProxy.insertText()` stops working. This is confirmed across Apple Developer Forums and community reports. UISearchBar has the same problem (it contains UITextField internally).

### Recommended Approach: Issuer Filter Chips + Optional Letter Search

**Primary: Horizontal scrolling filter chips**

```
[ All ] [ GitHub ] [ Google ] [ AWS ] [ Discord ] [ ... ]
```

- Show unique issuers as tappable chips, ordered by usage frequency
- Tapping a chip filters the collection view to that issuer's accounts only
- Tap again (or tap "All") to deselect
- No text input needed -- avoids responder chain problem entirely
- Better UX for keyboards: recognition over recall, one-tap filtering

**Secondary (for 50+ accounts): Letter-button search bar**

A custom control that mimics a text field without using UITextField:

- UILabel with rounded rect background and placeholder text ("Search...")
- Tapping reveals a horizontally scrolling row of letter buttons (A-Z, 0-9, backspace, clear)
- Each button tap appends to a filter string stored in a plain `String` property
- The UILabel displays the current filter text
- The collection view filters accounts whose issuer or label contains the filter string
- No UITextField, no UIResponder involvement, no first-responder stealing

### Animated Filtering with Diffable Data Source

Replace the current manual `UICollectionViewDataSource` with `UICollectionViewDiffableDataSource`:

```swift
private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Account> = {
    UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, account in
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TOTPCodeCell.reuseID, for: indexPath) as! TOTPCodeCell
        cell.configure(with: account)
        return cell
    }
}()

func applyFilter(_ query: String) {
    let filtered = query.isEmpty
        ? accounts
        : accounts.filter { $0.issuer.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) }
    var snapshot = NSDiffableDataSourceSnapshot<Int, Account>()
    snapshot.appendSections([0])
    snapshot.appendItems(filtered)
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

Requires `Account` to conform to `Hashable` (currently `Equatable` -- add `Hashable` conformance, which is trivial since all fields are hashable).

### Layout Change

Current keyboard layout:
```
[ Globe ] [ Shield ] [ KeyAuth ]
[ --------------------------------- ]
[ Collection View (scrollable)      ]
[ --------------------------------- ]
```

New layout with filter:
```
[ Globe ] [ Shield ] [ KeyAuth ] [ Search icon ]
[ All ] [ GitHub ] [ Google ] [ AWS ] [ ... ]    <- horizontal scroll chips
[ --------------------------------- ]
[ Collection View (scrollable)      ]
[ --------------------------------- ]
```

The filter chip row adds ~32pt to keyboard height. Acceptable within the 220pt current height or bump to 260pt.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Hand-rolled protobuf decoder | `apple/swift-protobuf` SPM | External dep. Schema is trivially simple (7 fields, 3 enums). |
| PBKDF2 via CommonCrypto | scrypt or Argon2 via third-party lib | Would add external dep. PBKDF2 at 600K iterations is OWASP-compliant. |
| AES-256-GCM via CryptoKit | ChaChaPoly (already used for relay) | AES-GCM is the standard for file encryption. More interoperable. |
| Filter chips (no text input) | UITextField in keyboard extension | UITextField steals first responder, breaks textDocumentProxy. |
| Filter chips (no text input) | UISearchBar in keyboard extension | Same problem -- contains UITextField internally. |
| Custom UILabel search | Full mini-QWERTY inside keyboard | QWERTY-inside-QWERTY is confusing UX. Chips + letter strip is clearer. |
| JSON .keyauth format | Raw binary format | JSON is debuggable, versionable, extensible. Negligible overhead. |
| SharedDefaults for usage tracking | Core Data / SQLite | Overkill for 2 fields on an existing Codable struct. |
| Diffable data source | Manual reloadData() | Animated transitions for filtering. Available iOS 13+. |
| `useCount` + `lastUsedAt` on Account | Separate usage tracking store | Keeps model cohesive. Backward-compatible via optional decoding. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `apple/swift-protobuf` | External dependency. Violates zero-deps constraint. 60K+ lines for a 7-field schema. | ~120 lines of hand-rolled varint + LEN decoder |
| `CryptoSwift` | External dependency. CommonCrypto + CryptoKit cover PBKDF2 + AES-GCM. | `CommonCrypto.CCKeyDerivationPBKDF` + `CryptoKit.AES.GCM` |
| `UITextField` in keyboard | Steals first responder. `textDocumentProxy.insertText()` stops working. | Custom UILabel-based filter or issuer chips |
| `UISearchBar` in keyboard | Contains UITextField internally. Same responder chain problem. | Custom UILabel-based filter or issuer chips |
| Core Data for usage tracking | Overkill. Account model is already JSON in Keychain. | Add `lastUsedAt` and `useCount` to existing `Account` struct |
| `SwiftProtobuf` | Same as `apple/swift-protobuf`. SPM name differs but same package. | Hand-rolled decoder |
| Argon2 / bcrypt for KDF | Not available in system frameworks. Would require external dep. | PBKDF2 via CommonCrypto at 600K+ iterations |

## Version Compatibility

| Component | Minimum iOS | Notes |
|-----------|-------------|-------|
| `AES.GCM` (CryptoKit) | iOS 13+ | Same minimum as existing ChaChaPoly usage |
| `CCKeyDerivationPBKDF` (CommonCrypto) | iOS 2+ | System framework since the beginning |
| `UICollectionViewDiffableDataSource` | iOS 13+ | Replaces manual `reloadData()` for animated filtering |
| `SecRandomCopyBytes` (Security) | iOS 2+ | Already linked for Keychain operations |
| `UniformTypeIdentifiers` | iOS 14+ | For `.keyauth` UTI registration. If targeting iOS 13, fall back to legacy UTI strings. |
| Base32 encode (custom) | N/A | Existing `Base32.swift` -- verify it has `encode(Data) -> String` or add it |

## Installation

**No new packages to install on iOS.** All features use existing system frameworks.

**Verify existing Base32.swift has encode capability:**
```bash
# Check if Base32.swift has an encode function
grep -n "func encode" Shared/Base32.swift
```
If missing, add `static func encode(_ data: Data) -> String` using RFC 4648 alphabet.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Protobuf schema | HIGH | Cross-verified from 3 independent sources (alexbakker, qistoph, zwyx.dev). All agree on field numbers and types. |
| Protobuf wire format | HIGH | Verified against official protobuf.dev encoding spec. |
| PBKDF2 + AES-GCM | HIGH | Both are system frameworks already in use. OWASP iteration count verified. |
| UITextField keyboard breakage | HIGH | Confirmed via Apple Developer Forums and multiple community reports. Known limitation since iOS 8. |
| Diffable data source | HIGH | Standard UIKit API since iOS 13. Well-documented. |
| Account model backward compat | HIGH | Standard Codable pattern with `decodeIfPresent` + defaults. |
| .keyauth file format | MEDIUM | Our own design. JSON wrapper approach is common (1Password, Bitwarden use similar). |
| Smart sort algorithm | MEDIUM | Custom weighting. Will need tuning with real usage data. |

---

## Sources

- [Google Auth protobuf schema -- alexbakker.me](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html) -- HIGH confidence
- [Google Auth export format -- qistoph/otp_export](https://github.com/qistoph/otp_export) -- HIGH confidence
- [Google Auth export format -- zwyx.dev](https://zwyx.dev/blog/google-authenticator-export-format) -- HIGH confidence
- [Protocol Buffers wire format -- protobuf.dev](https://protobuf.dev/programming-guides/encoding/) -- HIGH confidence (official)
- [AES.GCM -- Apple Developer Documentation](https://developer.apple.com/documentation/cryptokit/aes/gcm) -- HIGH confidence
- [CommonCrypto PBKDF2 -- Apple open source](https://opensource.apple.com/source/CommonCrypto/CommonCrypto-55010/doc/CCCommonKeyDerivation.3cc.auto.html) -- HIGH confidence
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) -- HIGH confidence
- [PBKDF2 iterations 2025 -- dev.to](https://dev.to/securebitchat/why-you-should-use-310000-iterations-with-pbkdf2-in-2025-3o1e) -- MEDIUM confidence
- [UITextField in keyboard extension -- Apple Developer Forums](https://developer.apple.com/forums/thread/114827) -- HIGH confidence
- [Custom Keyboard Programming Guide -- Apple](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) -- HIGH confidence
- [Keyboard extension limitations -- inFullMobile](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694) -- MEDIUM confidence

---
*Stack research for: KeyAuth v2.0 feature additions*
*Researched: 2026-04-16*
