# Pitfalls Research

**Domain:** iOS TOTP Authenticator -- v2.0 feature additions (smart keyboard, protobuf import, encrypted export, onboarding)
**Researched:** 2026-04-16
**Confidence:** HIGH (verified against existing codebase, Apple docs, community experience)

## Critical Pitfalls

### Pitfall 1: UITextField Inside Keyboard Extension Steals Text Input Proxy

**What goes wrong:**
Adding a search/filter UITextField inside the keyboard extension causes all typed text to route to the host app instead of the search field. When the UITextField becomes firstResponder, `textDocumentProxy.insertText()` stops working for code insertion. The keyboard appears broken -- user types a search query but characters appear in the host app's text field.

**Why it happens:**
iOS keyboard extensions route all input through `textDocumentProxy`, which always points to the host app's active text field. When you add a UITextField inside your keyboard view and give it focus, iOS does NOT automatically redirect the proxy. The system was designed so keyboard extensions produce text, not consume it. Standard `becomeFirstResponder()` on an embedded UITextField creates a conflict between two input targets.

**How to avoid:**
Do NOT use UITextField or UISearchBar for the search field. Instead, build a custom tap-target view that collects individual key taps and assembles the search string manually:
1. Create a custom `SearchBarView` (UIView subclass) with a display label showing current query text
2. Add a row of alphabet buttons (A-Z) below or overlaying the account list when search is active
3. Each button tap appends to an in-memory `searchQuery: String` and filters `accounts` array
4. A backspace button removes the last character; a clear button resets
5. Filter the existing `accounts` array using `searchQuery` against `issuer` and `label` fields

This avoids the textDocumentProxy conflict entirely. The search "keyboard" is just tappable buttons within your keyboard view -- no UITextField, no firstResponder conflict.

**Warning signs:**
- Characters appearing in the host app while typing in your search field
- `textDocumentProxy.insertText()` silently stops working after search field gains focus
- Tap on a TOTP code cell inserts nothing after interacting with search

**Phase to address:**
Smart Keyboard phase (search/filter feature). This must be the first design decision -- the entire search UI architecture depends on avoiding UITextField.

---

### Pitfall 2: Keyboard Extension Memory Crash During Search With Many Accounts

**What goes wrong:**
The keyboard extension crashes silently (jetsammed by iOS) when loading and filtering a large account list. Users with 50+ accounts trigger the ~30MB memory limit. The crash is silent -- iOS kills the extension process and the keyboard simply disappears, replaced by the default keyboard. No crash log appears in the user-visible crash reporter.

**Why it happens:**
iOS keyboard extensions have a hard memory ceiling of approximately 30-48MB (varies by device and system pressure). The current implementation loads ALL accounts from SharedDefaults into memory, creates UICollectionView cells for all of them, and runs a 1-second timer refreshing visible cells. Adding search UI (alphabet buttons, filtered results, animations) increases the baseline memory. On older devices (iPhone SE 2nd gen, iPad mini), the ceiling is closer to 30MB.

**How to avoid:**
1. Keep the account list as `[FilterableAccount]` structs (id, issuer, label only -- NO secret, NO full Account object) for display/filtering. Load secrets on-demand only when user taps to insert.
2. Pre-compute the filtered list when search query changes; do NOT keep multiple copies of the full account array.
3. Use `UICollectionView` cell reuse aggressively -- the current implementation already does this, but verify no strong references to cells exist in closures.
4. Profile with Instruments (Allocations) under the keyboard extension target, NOT the main app target. Extensions have separate memory limits.
5. Set a practical upper bound: if user has 200+ accounts, paginate or show "showing first 100 results."
6. Avoid loading any images/icons for accounts in the keyboard extension.

**Warning signs:**
- Keyboard disappears without warning during use (check Console.app for `jetsam` events)
- Memory usage above 20MB in Instruments when profiling keyboard extension
- CollectionView scroll stutter (precedes jetsam by moments)

**Phase to address:**
Smart Keyboard phase. Memory profiling must be part of the acceptance criteria for this phase.

---

### Pitfall 3: Hand-Rolling Protobuf Parser With Off-By-One Varint Decoding

**What goes wrong:**
The custom protobuf decoder silently produces corrupted data -- wrong secrets, truncated issuer names, or crashes on valid Google Authenticator exports. Users import their accounts and get wrong TOTP codes, which locks them out of services. This is catastrophic because the user may have already deleted Google Authenticator.

**Why it happens:**
Protobuf wire format parsing requires handling varint encoding (variable-length integers using 7-bit groups with continuation bits), wire types (varint=0, length-delimited=2, 32-bit=5), and nested messages. Common mistakes in hand-rolled parsers:

1. **Varint continuation bit mishandling:** Each byte's MSB indicates "more bytes follow." Failing to mask the MSB (byte & 0x7F) before shifting corrupts the value. Shifting in the wrong direction (big-endian vs little-endian varint) silently produces wrong field numbers.
2. **Field number extraction error:** The tag varint encodes `(fieldNumber << 3) | wireType`. Forgetting the 3-bit shift means field 1 (tag byte 0x0A for length-delimited) gets parsed as field 0.
3. **Nested message boundaries:** `OtpParameters` is a length-delimited field inside `MigrationPayload`. Failing to limit the sub-parser to the declared byte length causes it to read into the next OtpParameters entry, corrupting all subsequent accounts.
4. **Missing/zero-value fields:** Proto2 optional fields may be absent. Proto3 default values (0, empty string) are not written to the wire. The parser must handle absent fields gracefully and apply defaults (algorithm=SHA1, digits=6, type=TOTP).

**How to avoid:**
1. Write the parser against the known proto definition:
   - MigrationPayload: field 1 (repeated OtpParameters), fields 2-5 (version/batch metadata)
   - OtpParameters: field 1 (bytes secret), field 2 (string name), field 3 (string issuer), field 4 (enum algorithm), field 5 (enum digits), field 6 (enum type), field 7 (int64 counter)
2. Implement varint decoding as a standalone, thoroughly unit-tested function.
3. For each length-delimited field, create a sub-Data slice and parse ONLY within those bounds.
4. Write test cases using real Google Authenticator export data (create test accounts in GA, export, capture the base64 payload).
5. Handle unknown field numbers by skipping them (read wire type, skip appropriate bytes) -- Google may add fields in future versions.
6. Validate parsed secrets by generating a TOTP code and comparing with the source app before deleting the source.

**Warning signs:**
- Parsed account count doesn't match expected count from Google Authenticator
- Base32-encoding of parsed secret bytes doesn't produce valid TOTP codes
- Parser crashes on exports with many accounts (batch QR codes)

**Phase to address:**
Google Authenticator Import phase. Requires extensive test fixtures and must NOT be shipped without real-device testing against actual GA exports.

---

### Pitfall 4: Weak Key Derivation in Encrypted Backup Export

**What goes wrong:**
The encrypted backup file uses PBKDF2 with too few iterations or a weak configuration, making brute-force attacks feasible. An attacker who obtains the `.keyauth` backup file can crack the password and extract all TOTP secrets. Since TOTP secrets are long-lived (rarely rotated), a single breach compromises all the user's 2FA accounts.

**Why it happens:**
Developers copy PBKDF2 examples from Stack Overflow or tutorials that use 1,000-10,000 iterations. In 2026, GPUs can test billions of PBKDF2-SHA256 hashes per second at low iteration counts. Additionally, developers may:
- Use a short or fixed salt (or no salt at all)
- Derive a key shorter than 256 bits
- Use CBC mode instead of an AEAD cipher (enabling padding oracle attacks)
- Not include a version byte in the file format, preventing future algorithm upgrades

**How to avoid:**
1. Use PBKDF2-SHA512 via CommonCrypto's `CCKeyDerivationPBKDF` with at least 600,000 iterations (OWASP 2023 recommendation for SHA-256; 210,000 for SHA-512). Use `CCCalibratePBKDF` to auto-calibrate for ~500ms derivation time on the user's device, with a floor of 210,000 iterations.
2. Generate a 16-byte (128-bit) random salt per export using `SecRandomCopyBytes`.
3. Derive a 256-bit key.
4. Encrypt with AES-256-GCM (available via CryptoKit's `AES.GCM.seal`) or ChaCha20-Poly1305 (already used in the relay E2E encryption). Both are AEAD ciphers providing authentication.
5. File format: `[1-byte version][16-byte salt][4-byte iteration count (big-endian)][12-byte nonce][ciphertext+tag]`. Including the iteration count allows future increases without breaking old files.
6. Enforce minimum password length (8 characters) and show a strength indicator. Reject empty passwords.
7. Include a known plaintext prefix in the decrypted data (magic bytes like "KEYAUTH\x01") so decryption can verify success before attempting JSON decode.

**Warning signs:**
- Iteration count below 100,000 in the code
- No salt, or a hardcoded salt string
- Using AES-CBC instead of AES-GCM
- No version byte in the file header
- Password accepted without minimum length check

**Phase to address:**
Encrypted Backup Export phase. Security review of the key derivation parameters must be an explicit acceptance criterion.

---

### Pitfall 5: Recency Tracking Bloats Keychain Item Size and Breaks Sync

**What goes wrong:**
Adding `lastUsed: Date` and `useCount: Int` fields to the `Account` struct causes frequent Keychain writes on every code insertion from the keyboard. Each write triggers an iCloud Keychain sync, creating sync storms across devices. Worse, if recency data differs between devices (user taps different codes on iPhone vs iPad), sync conflicts cause the dedup logic to fight with recency updates, potentially losing accounts.

**Why it happens:**
The current `Account` struct is stored as JSON in each Keychain item. Adding mutable fields like `lastUsed` and `useCount` means every tap-to-insert triggers: JSON encode -> Keychain SecItemUpdate -> iCloud sync push -> KVS notification on other devices -> reload on other devices. For a user inserting 5-10 codes per day, this creates 5-10x more Keychain writes than the current near-zero write frequency after initial setup.

Additionally, iCloud Keychain sync is eventually-consistent. Two devices updating the same item's `lastUsed` timestamp create a conflict. Apple's resolution is last-write-wins, which means whichever device syncs last overwrites the other's recency data AND potentially the rest of the Account data if the JSON blob is treated as atomic.

**How to avoid:**
Store recency data SEPARATELY from TOTP secrets:
1. Use **App Group UserDefaults** (SharedDefaults) for recency metadata: `[UUID: RecencyInfo]` where `RecencyInfo` contains `lastUsed: Date` and `useCount: Int`.
2. NEVER add mutable high-frequency fields to the `Account` struct or Keychain items.
3. The keyboard extension already reads from SharedDefaults -- it can read AND write recency data there without Keychain access.
4. The main app reads recency data from SharedDefaults to sort the account list.
5. Recency data is device-local by design -- each device has its own usage patterns. This is a feature, not a bug.
6. If cross-device recency is desired later, use NSUbiquitousKeyValueStore (1MB limit, 1024 keys max) with coalesced/throttled writes.

**Warning signs:**
- `Account` struct gains new mutable fields beyond the original set
- Keychain writes happening on every code tap in the keyboard extension
- iCloud sync conflicts appearing in Console.app logs after using codes on multiple devices
- `coalescedReload()` firing constantly during normal use

**Phase to address:**
Smart Keyboard phase (recency sorting). The data model decision must happen BEFORE implementing sort logic.

---

### Pitfall 6: Onboarding Flow Blocks Existing Users Who Just Updated

**What goes wrong:**
After a v2.0 update, existing users with configured accounts are forced through a multi-screen onboarding flow designed for fresh installs. They must swipe through "Welcome to KeyAuth" screens, re-enable the keyboard, and re-pair their Chrome extension -- even though everything is already set up. Users perceive this as the app "forgetting" their setup and may panic-delete and reinstall.

**Why it happens:**
The onboarding state is tracked by a simple boolean like `hasCompletedOnboarding` in UserDefaults. On a fresh v2.0 install, this flag doesn't exist, so onboarding shows. But the flag also doesn't exist for users upgrading from v1.0 (which had no onboarding flow). The code treats "no flag" as "new user" when it should also check for existing data.

**How to avoid:**
1. Check for existing state BEFORE showing onboarding: `KeychainManager.shared.loadAll().isEmpty` and `PairingStore` emptiness and keyboard extension enabled status.
2. Use a versioned onboarding key: `onboarding_completed_v2` rather than a generic boolean. This allows showing v2.0-specific screens (new features tour) to v1.0 upgraders while skipping the basic setup screens.
3. Implement three onboarding paths:
   - **Fresh install (no accounts, no pairing):** Full onboarding -- welcome, keyboard enable guide, add first account, optional pairing
   - **Upgrade with data (accounts exist):** Abbreviated -- "What's new in v2.0" (1-2 screens), skip keyboard/pairing setup if already done
   - **Upgrade without data (accounts empty, but app was installed):** Treat as fresh but skip the "Welcome to KeyAuth" brand introduction
4. Gate each onboarding screen independently: keyboard setup screen only shows if `UIInputViewController` self-check fails; pairing screen only shows if PairingStore is empty.
5. Store the onboarding version completed, not just a boolean: `UserDefaults.set(2, forKey: "onboarding_version_completed")`. Future v3.0 can show delta onboarding.

**Warning signs:**
- Single boolean `hasCompletedOnboarding` in the code
- No conditional checks for existing Keychain data before showing onboarding
- Onboarding flow has no "Skip" option
- No differentiation between fresh install and app update

**Phase to address:**
Onboarding phase. The state detection logic must be implemented and tested before building any onboarding UI screens.

---

### Pitfall 7: Protobuf Batch QR Codes Silently Dropped

**What goes wrong:**
Google Authenticator splits large account lists across multiple QR codes (batched export). The app scans the first QR code, imports those accounts, and presents a success screen. The user closes the import flow without scanning the remaining QR codes, losing half their accounts. They only discover this days later when a missing account's code is needed.

**Why it happens:**
The `MigrationPayload` protobuf includes `batch_size`, `batch_index`, and `batch_id` fields. If the parser ignores batch metadata, it treats each QR code as a complete, independent import. The UI shows "Imported 10 accounts" after the first scan, and the user reasonably assumes they're done.

**How to avoid:**
1. Parse `batch_size` and `batch_index` from every `MigrationPayload`.
2. If `batch_size > 1`, show a progress indicator: "Scanned QR code 1 of 3 -- scan next code to continue."
3. Keep the camera scanner open between batch scans. Do NOT dismiss it after the first successful scan.
4. Track scanned batches by `batch_id` and `batch_index`. Warn if the user tries to dismiss with unscanned batches: "You've scanned 1 of 3 export codes. X accounts may not be imported. Continue anyway?"
5. Allow re-scanning the same batch (idempotent -- dedup by secret content, not by batch metadata).
6. Store partially-imported batch state so the user can resume later.

**Warning signs:**
- Import flow immediately shows "Done" without checking batch metadata
- No multi-QR-code scanning UI
- Camera dismisses after first successful scan
- No "X of Y" progress indicator during import

**Phase to address:**
Google Authenticator Import phase. Batch handling is not optional -- Google Auth uses batches for any user with more than ~10 accounts.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store recency in Account struct | Simpler data model, single source of truth | Sync storms, Keychain write amplification, conflict hell | Never -- the write frequency difference is too great |
| Skip protobuf varint edge cases (>5 byte varints) | Faster initial implementation | Crash on accounts with high counter values (HOTP) or future proto changes | Never -- varints up to 10 bytes must be handled per spec |
| Hardcode PBKDF2 iteration count | Simpler code, predictable performance | Becomes weak as hardware improves, no way to upgrade without breaking old files | Only if version byte allows future upgrade path |
| Use UserDefaults for all search state in keyboard | Avoids memory management complexity | UserDefaults.synchronize() is expensive, 30MB limit includes serialization overhead | Early prototype only, must optimize before release |
| Single onboarding boolean | Simple conditional logic | Cannot do incremental onboarding for future versions | Never -- use versioned integer from day one |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Google Authenticator export | Assuming URL-decoded base64 is standard base64 | The `data` parameter is URL-encoded, then base64-encoded. Must URL-decode first, then handle base64 padding (`+` as `%2B`, `/` as `%2F`, `=` as `%3D`). Also handle both standard and URL-safe base64 variants. |
| SharedDefaults (App Group) | Writing recency data synchronously on every code tap | Batch/debounce writes. `UserDefaults.synchronize()` is blocking I/O. In the keyboard extension, defer writes by 2 seconds after last tap using a debounce timer. |
| Keychain + iCloud sync | Adding new fields to Account struct without Codable migration | Old Keychain items encoded with v1 Account struct will fail to decode if new required fields are added. All new fields MUST have defaults or be Optional. Test by encoding with old struct, decoding with new struct. |
| CryptoKit / CommonCrypto | Using CryptoKit's AES.GCM in the keyboard extension | CryptoKit should be available in extensions, but verify the entitlements. The keyboard extension does NOT have network access, so encryption/decryption for backup must happen in the main app only. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Filtering accounts with String.contains() on every keystroke | Visible lag after 3rd character typed in search, keyboard feels frozen | Pre-compute lowercased issuer+label once at load time, filter against pre-computed values | 100+ accounts with complex Unicode issuers |
| Reloading entire CollectionView on filter change | Flash/flicker on each keystroke, scroll position lost | Use `performBatchUpdates` with calculated insertions/deletions, or maintain two arrays (full + filtered) and diff | 50+ accounts visible |
| Timer-based TOTP refresh in keyboard (1-second interval) | CPU usage stays elevated, battery drain reported by users | Only refresh visible cells, pause timer when keyboard is not visible (`viewDidDisappear` already handles this -- verify it fires reliably) | Always -- even with 10 accounts, unnecessary 1s polling wastes cycles |
| JSON encoding full Account array to SharedDefaults on every reload | Blocking main thread in keyboard extension, dropped frames | Only write to SharedDefaults when accounts actually change (compare hash/count), not on every `reload()` call | 30+ accounts, ~50KB+ JSON payload |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Including TOTP secrets in the backup filename or metadata | Secrets visible to anyone with file system access, iCloud Drive, or AirDrop preview | Filename should be generic: `keyauth-backup-2026-04-16.keyauth`. Never include account names or secrets in unencrypted metadata. |
| Using ECB mode or CBC without authentication for backup encryption | Ciphertext manipulation goes undetected; padding oracle attacks reveal plaintext | Use AEAD cipher only: AES-256-GCM or ChaCha20-Poly1305. Both authenticate and encrypt in one operation. |
| Allowing backup export without biometric/passcode gate | Any app with file access can trigger export and intercept the file | Gate backup export behind FaceID/TouchID. The `BiometricAuthManager` already exists -- reuse it. |
| Not zeroing derived key material after use | Key material persists in memory, accessible via memory dump | Use `Data` with immediate overwrite after encryption completes. Swift's ARC doesn't guarantee immediate deallocation. Call `resetBytes(in:)` on mutable Data. In practice, Swift makes true zeroing difficult -- at minimum avoid storing keys in String (which copies freely). |
| Protobuf parser accepting malformed field lengths | Buffer over-read if length-delimited field declares a length larger than remaining data | Validate: `declaredLength <= remainingBytes` before reading any length-delimited field. Reject the entire payload on violation. |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Search bar always visible in keyboard, reducing code list space | Only 1-2 codes visible when search is shown; defeats purpose of quick access | Show search only when tapped (toggle via magnifying glass icon). Default view shows sorted codes without search chrome. |
| Importing duplicates from Google Auth without warning | User ends up with doubled accounts, confused which is which | Before import, check existing accounts by DedupKey (issuer+label+secret). Show "5 new, 3 already exist -- import new only?" dialog. |
| Backup export produces file with no clear way to restore | User exports backup "just in case" but never tests restore. When they need it, they can't figure out how to import. | Include a "Test your backup" prompt after export. The import flow should handle `.keyauth` files via iOS share sheet / file picker. |
| Onboarding keyboard activation guide shows wrong Settings path | iOS versions change the path to enable third-party keyboards. Hardcoded screenshots become wrong. | Use text-based instructions with the current iOS version's path. Better: deep-link to Settings if possible (`UIApplication.openSettingsURL` goes to app settings, not keyboard settings -- be honest about the limitation). |
| Recency sort feels wrong after importing many accounts | User imports 30 accounts from Google Auth; all have the same "last used" timestamp (never); sort order is arbitrary | For newly imported accounts, use `sortOrder` as tiebreaker when `lastUsed` is nil/never. Preserve the import order as the initial sort. |

## "Looks Done But Isn't" Checklist

- [ ] **Protobuf parser:** Often missing handling for unknown field numbers -- verify the parser skips unrecognized fields without crashing (Google may add fields in future GA versions)
- [ ] **Protobuf parser:** Often missing batch QR code support -- verify `batch_size > 1` is handled with multi-scan UI
- [ ] **Protobuf parser:** Often missing URL decoding of the base64 data parameter -- verify `%2B`, `%2F`, `%3D` are decoded before base64 decode
- [ ] **Encrypted backup:** Often missing version byte in file header -- verify first byte is a version identifier for future format upgrades
- [ ] **Encrypted backup:** Often missing import/restore flow -- verify the `.keyauth` file can be opened from Files app, AirDrop, and share sheet
- [ ] **Keyboard search:** Often missing memory profiling under extension constraints -- verify with Instruments against keyboard extension target (not main app)
- [ ] **Keyboard search:** Often missing fallback for textDocumentProxy conflict -- verify typing into search does NOT insert characters into host app
- [ ] **Onboarding:** Often missing upgrade path detection -- verify existing v1.0 users see abbreviated flow, not full onboarding
- [ ] **Onboarding:** Often missing keyboard-already-enabled detection -- verify the "enable keyboard" screen is skipped if keyboard is already active
- [ ] **Recency tracking:** Often missing separation from Keychain data -- verify recency writes go to SharedDefaults, NOT Keychain items
- [ ] **Account struct:** Often missing Codable backward compatibility -- verify v1.0 encoded Account JSON decodes correctly with v2.0 struct (new fields must be Optional or have CodingKeys defaults)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Protobuf parser corrupts imported secrets | HIGH | Users locked out of services. Must re-scan original QR codes from each service. Implement pre-import validation: generate TOTP code from parsed secret and display alongside GA's current code for user to visually verify before committing. |
| Weak backup encryption discovered post-release | MEDIUM | Bump file format version. New exports use stronger parameters. Old files still decrypt with old parameters (version byte dispatches). Cannot retroactively fix already-exported files -- notify users to re-export. |
| Recency data stored in Keychain causing sync storms | MEDIUM | Migrate recency fields out of Account struct into SharedDefaults. Requires Codable migration (add `recencyMigratedV2` flag). Old struct decodes with Optional recency fields that get ignored. |
| Onboarding shown to existing users | LOW | Add upgrade detection retroactively. Check for existing Keychain accounts on launch. Set `onboarding_version_completed = 2` silently if accounts exist and onboarding hasn't been completed. |
| Keyboard extension jetsammed during search | LOW | Reduce memory footprint: load only filterable metadata, lazy-load full Account on tap. Profile and iterate. No data loss -- extension restarts on next keyboard switch. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| UITextField proxy conflict in keyboard | Smart Keyboard | Manual test: type in search, then tap code cell -- text must insert into host app, not search field |
| Keyboard memory crash | Smart Keyboard | Instruments profile showing peak memory under 25MB with 100 accounts loaded and search active |
| Protobuf varint/parsing errors | Google Auth Import | Unit tests with real GA export payloads (1 account, 10 accounts, batch export, SHA256/512 accounts) |
| Batch QR codes dropped | Google Auth Import | Manual test: export 15+ accounts from GA (forces batching), verify all imported |
| Weak key derivation | Encrypted Backup Export | Code review: iteration count >= 210,000, random salt, AEAD cipher, version byte present |
| Recency in Keychain | Smart Keyboard | Code review: no new mutable fields added to Account struct, recency in SharedDefaults only |
| Onboarding blocks upgraders | Onboarding | Manual test: install v1.0, add accounts, upgrade to v2.0 -- verify abbreviated onboarding |
| Account struct Codable break | All phases adding fields | Unit test: encode Account with v1.0 fields, decode with v2.0 struct, verify no data loss |

## Sources

- [Apple Developer Forums: Keyboard Extension Memory Issue](https://developer.apple.com/forums/thread/85478) -- HIGH confidence
- [KeyboardKit: How to type into a text input within a keyboard extension](https://keyboardkit.com/blog/2023/11/13/how-to-type-within-a-keyboard-extension) -- HIGH confidence
- [Apple Developer Forums: Keyboard Extension Crashes](https://developer.apple.com/forums/thread/105815) -- HIGH confidence
- [Fleksy: Limitations of Custom Keyboards on iOS](https://www.fleksy.com/blog/limitations-of-custom-keyboards-on-ios/) -- MEDIUM confidence
- [Igor Kulman: Dealing with memory limits in iOS app extensions](https://blog.kulman.sk/dealing-with-memory-limits-in-app-extensions/) -- MEDIUM confidence
- [Protocol Buffers Encoding Guide](https://protobuf.dev/programming-guides/encoding/) -- HIGH confidence
- [Kreya: Demystifying the protobuf wire format](https://kreya.app/blog/protocolbuffers-wire-format/) -- HIGH confidence
- [Alex Bakker: Parsing Google Authenticator export QR codes](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html) -- MEDIUM confidence
- [qistoph/otp_export: Google Authenticator export format](https://github.com/qistoph/otp_export) -- HIGH confidence
- [Jimmy0w0: Google Authenticator Deep Dive into Exported Data](https://jimmy0w0.me/posts/google-authenticator-a-deep-dive-into-exported-data-en/) -- MEDIUM confidence
- [OWASP/NIST PBKDF2 Iteration Recommendations](https://jp-east.mas.scc.lac.co.jp/iOS/en/build/html/subPage/Cryptography_Requirements.html) -- HIGH confidence
- [Andy Ibanez: When CryptoKit is not Enough](https://www.andyibanez.com/posts/cryptokit-not-enough/) -- MEDIUM confidence
- [Apple: kSecAttrSynchronizable Documentation](https://developer.apple.com/documentation/security/ksecattrsynchronizable) -- HIGH confidence
- [Apple: Onboarding HIG](https://developer.apple.com/design/human-interface-guidelines/onboarding) -- HIGH confidence
- [Apple Developer Forums: Keychain Storage Size](https://developer.apple.com/forums/thread/73314) -- MEDIUM confidence

---
*Pitfalls research for: KeyAuth v2.0 feature additions*
*Researched: 2026-04-16*
