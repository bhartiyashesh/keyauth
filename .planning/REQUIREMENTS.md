# Requirements: KeyAuth v2.0 — Beautiful, Seamless, Untouchable

**Defined:** 2026-04-20
**Core Value:** 2FA codes appear exactly where you need them with zero friction. Secrets never leave the phone.

## v2.0 Requirements

### v1.0 Carry-Forward: Code Request & Delivery

- [ ] **CODE-03**: TOTP code is generated on the phone after biometric approval, then sent via relay to extension
- [ ] **CODE-04**: Extension popup displays the received code with an expiry countdown timer
- [ ] **CODE-05**: Extension surfaces relevant accounts based on the current website domain

### v1.0 Carry-Forward: Browser Integration

- [ ] **FILL-01**: Content script detects TOTP input fields using autocomplete attribute and heuristic fallbacks
- [ ] **FILL-02**: Extension auto-fills the detected TOTP field with the received code
- [ ] **FILL-03**: Extension provides clipboard copy with automatic 30-second clear as fallback

### v1.0 Carry-Forward: Resilience

- [ ] **RESIL-01**: Chrome extension service worker sends 20-second WebSocket keepalive pings
- [ ] **RESIL-02**: Both clients proactively reconnect before Railway's 15-minute WebSocket timeout
- [ ] **RESIL-03**: Chrome service worker rebuilds state from chrome.storage.session on every wake
- [ ] **RESIL-04**: iOS app registers APNs device token on every launch (handles token refresh)
- [ ] **RESIL-05**: Extension reconnects and rejoins room automatically on WebSocket drop

### v1.0 Carry-Forward: iOS App

- [ ] **IOS-03**: iOS app presents TOTP approval sheet (account name, site, approve/deny + Face ID)

### Extension Account Management (NEW)

- [ ] **EXT-01**: Phone sends encrypted account metadata (issuer, label, account ID — NOT secrets) to extension during pairing and whenever accounts are added/removed/edited on the phone
- [ ] **EXT-02**: Extension caches the account list locally in chrome.storage.local and displays it in the popup with full search/filter capability
- [ ] **EXT-03**: Extension popup includes a search bar that filters accounts by issuer or label as the user types, with instant results
- [ ] **EXT-04**: User selects a specific account in the extension, which sends a targeted "generate code for [account ID]" request — phone only needs to FaceID approve and respond
- [ ] **EXT-05**: Domain matching auto-highlights and sorts accounts matching the current tab's domain to the top of the list, reducing to one-click for the common case

### Smart Keyboard (NEW)

- [ ] **KEYB-01**: User's most recently used accounts appear first in the keyboard auth bar, sorted by a weighted score of recency (70%) and frequency (30%)
- [ ] **KEYB-02**: Usage data (lastUsed timestamp, useCount) is tracked in SharedDefaults when user taps a code in the keyboard, and persisted to Keychain by the companion app on foreground
- [ ] **KEYB-03**: Keyboard displays a filter bar (UIButton-based chips, not UITextField) that lets users narrow accounts by tapping issuer buttons
- [ ] **KEYB-04**: Filter bar shows top 5 issuer names as quick-filter chips; tapping one shows only that issuer's accounts
- [ ] **KEYB-05**: Accounts are grouped by issuer with visual section headers when more than 8 accounts exist
- [ ] **KEYB-06**: Base32.swift gains an `encode(Data) -> String` function (prerequisite for protobuf import)

### Google Authenticator Import (NEW)

- [ ] **IMPORT-01**: User can scan Google Authenticator export QR codes (otpauth-migration:// protobuf format) via camera, with support for multi-QR batch exports (progress indicator showing "QR 2 of 3")
- [ ] **IMPORT-02**: Protobuf decoder handles the Google Auth MigrationPayload schema (OtpParameters with secret, name, issuer, algorithm, digits, type fields) in pure Swift with no external dependencies
- [ ] **IMPORT-03**: Decoded protobuf secrets (raw bytes) are Base32-encoded and converted to Account objects via the existing Account.from(otpauthURL:) pipeline
- [ ] **IMPORT-04**: User can paste an otpauth:// URI directly to add an account (for power users with secrets in text/notes)
- [ ] **IMPORT-05**: After import completes, a summary screen shows count of imported, skipped (duplicate), and failed accounts

### Onboarding (NEW)

- [ ] **ONBOARD-01**: First launch shows a keyboard activation guide with step-by-step instructions to enable KeyAuth keyboard in iOS Settings (with illustrations per step)
- [ ] **ONBOARD-02**: Onboarding includes an import wizard offering "Import from Google Authenticator", "Scan QR Code", or "Enter Manually" as entry points
- [ ] **ONBOARD-03**: Onboarding includes a pairing walkthrough explaining how to connect the Chrome extension (Install extension → Scan QR → Done)
- [ ] **ONBOARD-04**: Onboarding state is versioned (integer, not boolean) in SharedDefaults so both app and keyboard extension can read it, and future onboarding additions don't reset completed steps
- [ ] **ONBOARD-05**: Existing users upgrading with accounts already present see an abbreviated onboarding (keyboard activation + import wizard only, skip intro)

### Encrypted Backup (NEW)

- [ ] **BACKUP-01**: User can export all TOTP accounts to a password-protected .keyauth file using AES-256-GCM encryption with PBKDF2-SHA256 key derivation (600,000+ iterations)
- [ ] **BACKUP-02**: Export file format includes a cleartext header (magic bytes, version, salt, iteration count) followed by encrypted JSON payload, enabling future format upgrades
- [ ] **BACKUP-03**: User can import a previously exported .keyauth file by entering the password, with duplicate detection against existing accounts
- [ ] **BACKUP-04**: Settings shows a "Last exported" date and a periodic reminder nudge if user has 3+ accounts but hasn't exported in 30+ days
- [ ] **BACKUP-05**: Export/import uses only system frameworks (CryptoKit AES.GCM + CommonCrypto CCKeyDerivationPBKDF) with no external dependencies

## v3.0+ Requirements

### Passkeys

- **PASS-01**: Passkey credential provider (ASCredentialProviderViewController)
- **PASS-02**: Account model supports both TOTP and passkey credential types

### Platform Expansion

- **PLAT-01**: Firefox extension (WXT supports cross-browser)
- **PLAT-02**: Safari extension
- **PLAT-03**: Self-hosted relay option with Docker image
- **WATCH-01**: watchOS companion app
- **STORE-01**: App Store submission and listing

### Enhanced UX

- **UX-01**: Countdown-aware delivery (wait for next period if <5s remaining)
- **UX-02**: Auto-detect TOTP field and prompt without clicking extension icon
- **UX-03**: Usage analytics dashboard in companion app

## Out of Scope

| Feature | Reason |
|---------|--------|
| Passkey support | TOTP still dominant; defer to v3.0+ |
| Welcome intro screens | Get to value faster — keyboard activation is more actionable |
| Authy encrypted import | Complex proprietary format, low ROI vs Google Auth |
| watchOS companion | Separate milestone |
| Usage analytics dashboard | Nice-to-have, not core to "seamless" goal |
| CSV/JSON plain-text import | Security risk — plaintext secrets in files |
| TOTP seed storage in browser | Core security model — secrets never leave the phone |
| Bluetooth/local transport | Chrome extensions can't use Web Bluetooth API |
| Auto-fill on page load (no user action) | Security anti-pattern (confirmed by 1Password, Bitwarden) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CODE-03 | TBD | Pending |
| CODE-04 | TBD | Pending |
| CODE-05 | TBD | Pending |
| FILL-01 | TBD | Pending |
| FILL-02 | TBD | Pending |
| FILL-03 | TBD | Pending |
| RESIL-01 | TBD | Pending |
| RESIL-02 | TBD | Pending |
| RESIL-03 | TBD | Pending |
| RESIL-04 | TBD | Pending |
| RESIL-05 | TBD | Pending |
| IOS-03 | TBD | Pending |
| EXT-01 | TBD | Pending |
| EXT-02 | TBD | Pending |
| EXT-03 | TBD | Pending |
| EXT-04 | TBD | Pending |
| EXT-05 | TBD | Pending |
| KEYB-01 | TBD | Pending |
| KEYB-02 | TBD | Pending |
| KEYB-03 | TBD | Pending |
| KEYB-04 | TBD | Pending |
| KEYB-05 | TBD | Pending |
| KEYB-06 | TBD | Pending |
| IMPORT-01 | TBD | Pending |
| IMPORT-02 | TBD | Pending |
| IMPORT-03 | TBD | Pending |
| IMPORT-04 | TBD | Pending |
| IMPORT-05 | TBD | Pending |
| ONBOARD-01 | TBD | Pending |
| ONBOARD-02 | TBD | Pending |
| ONBOARD-03 | TBD | Pending |
| ONBOARD-04 | TBD | Pending |
| ONBOARD-05 | TBD | Pending |
| BACKUP-01 | TBD | Pending |
| BACKUP-02 | TBD | Pending |
| BACKUP-03 | TBD | Pending |
| BACKUP-04 | TBD | Pending |
| BACKUP-05 | TBD | Pending |

**Coverage:**
- v2.0 requirements: 37 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 37

---
*Requirements defined: 2026-04-20*
*Last updated: 2026-04-20 after milestone v2.0 definition*
