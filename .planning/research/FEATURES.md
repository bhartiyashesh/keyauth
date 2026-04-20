# Feature Landscape

**Domain:** TOTP Authenticator v2.0 — Import, Smart Keyboard, Onboarding, Encrypted Export
**Researched:** 2026-04-16
**Overall confidence:** HIGH (competitor patterns well-documented); MEDIUM (protobuf wire format details)

---

## 1. Google Authenticator Batch Import

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Scan GA export QR code via camera | Every competitor (2FAS, Aegis, Ente Auth) supports this as primary import method | Medium | Camera permission (already have from QR scan), protobuf decoder |
| Parse `otpauth-migration://offline?data=` protobuf | This is the only format GA exports; without it, import is impossible | Medium-High | Pure Swift protobuf decoder (no external deps per constraint) |
| Multi-batch QR support (batch_size/batch_index/batch_id) | GA splits exports into multiple QR codes when >10 accounts; must handle all batches | Medium | State tracking across scans |
| Dedup against existing accounts | Users may already have some accounts; importing duplicates is a common complaint | Low | Existing `dedupInMemory` logic in AccountStore |
| Show import preview before saving | 2FAS and Ente Auth show what will be imported; users want to review before commit | Low | UI only |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Import from screenshot/photo (image QR decode) | Aegis supports this; GA blocks screenshots so user photographs with another device | Medium | Vision framework VNDetectBarcodesRequest |
| Same-device import via photo library | 2FAS supports uploading screenshot of QR; critical for single-device users | Low-Medium | UIImagePickerController + Vision QR detection |
| Import progress indicator with account count | Reassures users during multi-batch imports that nothing was lost | Low | UI only |
| Batch validation report (skipped/failed entries) | No competitor does this well; users worry about silent failures | Low | UI only |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Importing via file/JSON from GA | GA does not export files, only QR codes; building file import for GA suggests a nonexistent workflow | Support QR scan only for GA specifically |
| Auto-detecting GA export without user action | Clipboard snooping or background scanning is privacy-hostile | User-initiated scan flow |
| Supporting HOTP import silently | GA exports may contain HOTP tokens; counter state can desync | Import HOTP but show a warning that counter sync is best-effort |

### Protobuf Format Specification (HIGH confidence)

The `otpauth-migration://offline?data=<base64>` format decodes to:

```protobuf
message MigrationPayload {
  repeated OtpParameters otp_parameters = 1;
  int32 version = 2;
  int32 batch_size = 3;
  int32 batch_index = 4;
  int32 batch_id = 5;
}

message OtpParameters {
  bytes secret = 1;
  string name = 2;
  string issuer = 3;
  Algorithm algorithm = 4;
  DigitCount digits = 5;
  OtpType type = 6;
  int64 counter = 7;
}

enum Algorithm { SHA1=1; SHA256=2; SHA512=3; MD5=4; }
enum DigitCount { SIX=1; EIGHT=2; }
enum OtpType { HOTP=1; TOTP=2; }
```

**Implementation approach:** The constraint is "no external iOS dependencies." Protobuf wire format is simple enough for a hand-rolled decoder (~150-200 lines Swift). Fields are varint-tagged (field_number << 3 | wire_type). Wire types: 0=varint, 2=length-delimited. No need for full protobuf library. Reference implementations: [dim13/otpauth](https://github.com/dim13/otpauth) (Go), [qistoph/otp_export](https://github.com/qistoph/otp_export) (Python).

### How Competitors Handle It

| App | Method | UX Flow | Multi-batch | Dedup |
|-----|--------|---------|-------------|-------|
| **2FAS** | Camera scan of GA QR | Menu > Import > Google Authenticator > Scan QR | Repeat scan for each batch (max 10 per QR) | Silent dedup |
| **Aegis** | Camera scan OR image import | Settings > Import > Google Authenticator > Scan/Select image | Scans one batch at a time, error if unrelated batches mixed | Manual review |
| **Ente Auth** | Camera scan (mobile) | Settings > Data > Import > Google Authenticator | Supports multi-batch | Append (no dedup shown) |
| **Raivo** | Via migration link extraction | Manual/technical: extract link from QR, convert to otpauth:// | Not streamlined | Manual |

---

## 2. Smart Keyboard (Recency Sorting + Search/Filter)

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Recency/frequency sorting | Users with 20+ accounts need most-used codes at top; scrolling kills the speed advantage of a keyboard | Low-Medium | New `lastUsedAt: Date?` field on Account, persist via App Group UserDefaults |
| Search/filter by issuer or label | With 10+ accounts, visual scanning fails; every password manager keyboard has search | Medium | UITextField in keyboard extension, filter logic on data source |
| Tap-to-insert (already built) | Core keyboard functionality | -- | Already exists in KeyboardViewController |
| Visual feedback on insert (checkmark/highlight) | Confirms action completed; standard in clipboard/keyboard tools | Low | Animation on TOTPCodeCell |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Adaptive sorting (recency + frequency blend) | Pure recency forgets "weekly" accounts; blended score surfaces the right code contextually | Medium | Algorithm: `score = 0.7 * recency_rank + 0.3 * frequency_rank` |
| Pinned favorites (manual pin to top) | Users have 2-3 "always" accounts; pins guarantee they're first regardless of algorithm | Low | `isPinned: Bool` flag on Account, sort pinned-first |
| Compact/expanded layout toggle | Some prefer seeing more accounts at once vs larger tap targets | Low | Layout toggle in App Group UserDefaults |
| Contextual empty state | When search returns no results, show "No matches" instead of blank | Low | UI only |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full-text autocomplete from typed text | Keyboard extensions scanning input text is privacy-hostile; Apple may reject | Use explicit search bar within the keyboard UI |
| Network requests from keyboard | Requires "Allow Full Access" which destroys user trust and Apple scrutinizes | All data via App Group shared container; no network needed |
| Alphabetical-only sorting | Ignores usage patterns; forces scroll every time | Default to recency, offer alpha as option |
| Domain-aware auto-suggestion from Chrome context | Would require relay communication to keyboard extension; too complex, cross-system | Defer to v3.0 |

### Implementation Notes

- **Data flow:** Main app writes `lastUsedAt` timestamps to App Group `UserDefaults` dictionary (keyed by account UUID). Keyboard reads on `viewWillAppear`. No Full Access needed.
- **Search UX:** Thin search bar at top of keyboard (replaces title label area when active). Real-time filtering of `accounts` array. Dismiss with X button or tap outside.
- **Existing architecture:** `KeyboardViewController` uses `UICollectionView` with vertical scroll layout. Adding search = inserting `UITextField` above collection view + filtering data source array. Sort comparator changes from `sortOrder` to computed recency score.
- **No Full Access required:** KeyAuth uses App Groups + shared Keychain (`W646UCTVQV.com.keyauth.shared`). The keyboard reads account data from shared Keychain and usage stats from App Group UserDefaults. No network, no clipboard monitoring.

---

## 3. Onboarding Flow + Keyboard Activation Guide

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Step-by-step keyboard enable walkthrough | iOS requires 6-8 taps in Settings to enable a custom keyboard; users abandon without guidance | Medium | Multi-screen UI with illustrations/animations |
| Button to open Settings app | Reduces friction by 2-3 steps; `UIApplication.openSettingsURLString` is the safe API | Low | Standard UIKit API |
| Detection of keyboard enabled state | App should detect success and advance onboarding automatically | Medium | Check `UITextInputMode.activeInputModes` on `willEnterForeground` |
| Explain "No Full Access needed" | KeyAuth doesn't need Full Access; this is a trust differentiator vs SwiftKey/Gboard | Low | Copy/UI only |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Animated walkthrough (not static screenshots) | Competitors use static images; animation feels premium, reduces user error | Medium | Native UIView/SwiftUI animations (no external deps) |
| "Test it now" inline verification | After enabling, show a text field where user tries the keyboard immediately | Low | Embedded UITextField |
| Chrome extension pairing as onboarding step | Unified flow: enable keyboard + pair extension in one sequence | Low | Existing PairingView integrated into flow |
| Contextual re-prompt if keyboard disabled later | If user disables keyboard, show dismissable banner in app | Low | Check on `sceneDidBecomeActive` |
| Import as final onboarding step | "Bring your accounts" reduces time-to-value | Low | Links to GA Import flow |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Blocking app until keyboard enabled | Users may only want Chrome extension; don't gate access | Persistent but dismissable prompt |
| Requesting Full Access | KeyAuth works without it; asking destroys trust and differentiator | Explicitly say "we never need Full Access" |
| Private API deep links (`App-prefs:root=`) | Apple rejects apps using this; documented rejections in forums | Use only `UIApplication.openSettingsURLString` |
| Skipping onboarding entirely for existing users | Users upgrading to v2.0 may not have keyboard enabled yet | Show onboarding if keyboard not detected, regardless of account count |

### Recommended Onboarding Flow

```
Screen 1: Welcome + value prop
  "Your codes, in any text field. No app-switching."
  [Get Started] button

Screen 2: Enable Keyboard (critical step)
  - Animated diagram: Settings > General > Keyboard > Keyboards > Add > KeyAuth
  - [Open Settings] button (UIApplication.openSettingsURLString)
  - Live status indicator: "Waiting..." / "Keyboard enabled!"
  - Auto-advances when detected via UITextInputMode check on foreground

Screen 3: Try It
  - Text field: "Tap here, switch to KeyAuth keyboard, tap any code"
  - Success celebration (checkmark animation)
  - [Continue] button

Screen 4: Import Accounts (optional, skippable)
  - "Import from Google Authenticator" (links to import flow)
  - "I'll add accounts manually" (skip)

Screen 5: Pair Chrome Extension (optional, skippable)
  - Brief explanation + [Set Up Now] / [Maybe Later]
  - Links to existing PairingView if chosen
```

### How Keyboard Apps Handle Onboarding

| App | Approach | Key Pattern |
|-----|----------|-------------|
| **Gboard** | Aggressive multi-step with screenshots, deep link to settings, verification step | Does NOT let you proceed until keyboard is confirmed enabled |
| **SwiftKey** | Tutorial overlay with numbered steps, "Open Settings" button | Re-prompts on every launch if not enabled |
| **Fleksy** | Interactive demo keyboard in-app before asking to enable | Lets users experience value first, then asks for activation |

**Best practice synthesis:** Show value first (Screen 1), make activation as guided as possible (Screen 2), verify success immediately (Screen 3). Never block, always detect.

---

## 4. Encrypted Backup Export

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Password-protected export file | Aegis, 2FAS, Ente Auth all offer encrypted exports; unencrypted export of TOTP secrets is negligent | Medium | CryptoKit (AES-GCM) or CommonCrypto |
| PBKDF2 key derivation from password | Industry standard; prevents brute-force on export files | Low | CommonCrypto `CCKeyDerivationPBKDF` (system framework) |
| JSON-based format (encrypted payload in cleartext wrapper) | Universal pattern (2FAS uses `.2fas` JSON, Aegis uses JSON vault, Ente uses encrypted text) | Low | JSONEncoder |
| Export all accounts at once | Users want complete backup, not per-account | Low | Existing `keychain.loadAll()` |
| Share sheet for saving | Users need to save to Files, AirDrop, email, etc. | Low | UIActivityViewController |
| Biometric confirmation before export | Exporting secrets is security-sensitive | Low | Existing BiometricAuthManager |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `.keyauth` custom file extension with UTI | Branded file type; tapping file opens KeyAuth import flow automatically | Medium | UTI declaration in Info.plist, document type handler |
| Password strength indicator | Prevents users from protecting secrets with "1234" | Low | Basic entropy calculation |
| Cleartext metadata header (date, version, count) | Verify file validity without decrypting; Aegis does this | Low | JSON structure |
| Round-trip import of `.keyauth` files | Backup without restore is useless | Medium | Decrypt + parse + dedup |
| Export count/date shown in settings | Users want to know when they last backed up | Low | UserDefaults timestamp |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Unencrypted export option | Plaintext TOTP secrets in a file is a security disaster | Always encrypt; no "skip password" option |
| Auto-upload to iCloud Drive | Already have iCloud Keychain sync; auto-uploading files adds confusion | Manual export only via share sheet |
| Proprietary binary format | Opaque formats prevent recovery and interop | JSON with documented schema |
| Export without authentication gate | Too easy to accidentally export secrets | Always require FaceID/passcode |
| Compatibility with other apps' import | Trying to match Aegis/2FAS format adds complexity for marginal gain | Use own `.keyauth` format; can add export-as-otpauth-text later |

### How Competitors Handle Encrypted Export

| App | Format | Encryption | KDF | UX Flow |
|-----|--------|-----------|-----|---------|
| **Aegis** | JSON vault (`.json`) | AES-256-GCM | scrypt (N=32768, r=8, p=1) | Settings > Export > Enter vault password > Share |
| **2FAS** | JSON (`.2fas`) | AES-256-GCM | PBKDF2-SHA256 (10K iterations) | Settings > Export > Set password > Share |
| **Ente Auth** | Encrypted text | XChaCha20-Poly1305 | Password-derived (details unclear) | Settings > Data > Export > Encrypted > Password |
| **Raivo** | ZIP archive | Password-protected ZIP | ZIP encryption (weak) | Settings > Export > Enter master password |

### Recommended Export Format (`.keyauth`)

```json
{
  "version": 1,
  "app": "KeyAuth",
  "exportedAt": "2026-04-16T12:00:00Z",
  "accountCount": 15,
  "encryption": {
    "algorithm": "AES-256-GCM",
    "kdf": "PBKDF2-SHA256",
    "iterations": 600000,
    "saltBase64": "...",
    "nonceBase64": "..."
  },
  "dataBase64": "...AES-GCM encrypted JSON array of Account objects..."
}
```

**Encryption flow:**
1. User enters password (min 8 chars, strength indicator shown)
2. FaceID/passcode confirmation
3. Generate random 16-byte salt
4. Derive key: `PBKDF2(password, salt, iterations=600000, keyLen=32, hash=SHA256)`
5. Generate random 12-byte nonce
6. Encrypt: `AES-256-GCM(key, nonce, plaintext=JSON-encoded [Account] array)`
7. Package into `.keyauth` JSON with cleartext metadata
8. Present share sheet

**Why 600K iterations:** OWASP 2023 recommends minimum 600,000 for PBKDF2-SHA256. 2FAS uses only 10K which is dangerously low. Aegis uses scrypt which is better but unavailable natively in iOS without external deps.

**Why AES-256-GCM over XChaCha20:** CryptoKit provides `AES.GCM` natively. ChaCha20 is available via CryptoKit too, but GCM is the industry standard for file encryption and matches what Aegis and 2FAS use.

---

## Feature Dependencies (v2.0 scope)

```
Onboarding ──> No deps on other new features (ship first)
           ──> Can reference Import + Pairing as optional steps

GA Import  ──> Account model (existing, no changes needed)
           ──> QR Scanner (existing camera flow, add image-scan)
           ──> Pure Swift protobuf decoder (NEW ~150-200 lines)
           ──> AccountStore.save (existing)
           ──> Dedup logic (existing dedupInMemory)

Smart Keyboard ──> Account model + new `lastUsedAt: Date?` field
              ──> SharedDefaults / App Group UserDefaults (existing)
              ──> KeyboardViewController refactor (search bar + sort)

Encrypted Export ──> Account model (existing)
                ──> KeychainManager.loadAll (existing)
                ──> CryptoKit AES.GCM (system framework)
                ──> CommonCrypto PBKDF2 (system framework)
                ──> UTI declaration (.keyauth) in Info.plist
                ──> Round-trip import needs own decrypt + parse
```

---

## MVP Recommendation

**Priority order:**

1. **Onboarding flow** — Zero dependencies, immediately improves activation rate, should ship first so every new user gets guided setup. Without this, keyboard adoption is crippled.

2. **Google Auth Import** — Biggest barrier to switching apps; gets users' existing accounts into KeyAuth. This is why people don't switch authenticators. Protobuf decoder is the only novel work.

3. **Smart Keyboard (search + recency)** — Improves daily UX for users with many accounts. Benefits from having import done first (users need accounts to sort). Usage data needs time to accumulate.

4. **Encrypted Export** — Important for trust and safety narrative but not blocking daily usage. Ship last because it's the "insurance" feature — users need it to exist but rarely invoke it.

**Defer to v2.1+:**
- Domain-aware auto-suggestion from Chrome extension context (HIGH complexity, cross-system)
- Import from screenshot/photo via Vision framework (nice-to-have; camera scan covers primary flow)
- Pinned favorites (can add after recency sorting proves its value)

---

## Sources

- [2FAS Import Guide](https://2fas.com/support/2fas-auth-mobile-app/how-to-move-transfer-tokens-codes-from-google-authenticator-to-2fas/)
- [Aegis Google Auth Import PR #406](https://github.com/beemdevelopment/Aegis/pull/406/files)
- [Aegis Image Import PR #958](https://github.com/beemdevelopment/Aegis/pull/958)
- [Ente Auth Import Help](https://ente.com/help/auth/migration/import)
- [Ente Auth Export Help](https://ente.com/help/auth/migration/export)
- [Google Auth Export Format — Alex Bakker](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html)
- [Google Auth Export Format — qistoph](https://github.com/qistoph/otp_export)
- [dim13/otpauth Go decoder](https://github.com/dim13/otpauth)
- [2FAS Backup Decryptor (format reverse-engineered)](https://github.com/elliotwutingfeng/2fas-backup-decryptor)
- [2FAS Backup Format Issue #117](https://github.com/twofas/2fas-android/issues/117)
- [Apple: Custom Keyboard Extension Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Apple: Opening Keyboard Settings (QA1924)](https://developer.apple.com/library/archive/qa/qa1924/_index.html)
- [Keyboard Onboarding UX — Prototypr](https://blog.prototypr.io/how-to-create-a-smooth-installation-process-for-your-ios-keyboard-extension-ae9bf8f08eff)
- [Aegis Authenticator — AES-256-GCM encryption](https://getaegis.app/)
- [Ente Auth — E2E encrypted backups](https://ente.com/auth/)
- [OWASP Password Storage Cheat Sheet (PBKDF2 iterations)](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Raivo OTP FAQ](https://raivo-otp.com/faq/)
- [Best 2FA Apps Comparison 2026](https://stateofsurveillance.org/guides/basic/2fa-app-comparison/)
