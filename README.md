# KeyAuth — Authenticator in Your Keyboard

TOTP authenticator built into an iOS keyboard extension. Tap a code, it inserts directly into the active text field — no app switching, no clipboard exposure.

## Architecture

```
┌─────────────────────────────────────┐
│  Companion App (SwiftUI)            │
│  • QR Scanner (AVFoundation)        │
│  • Account Manager (CRUD + reorder) │
│  • Biometric Gate (FaceID/TouchID)  │
│  • Manual Entry + Import            │
└──────────────┬──────────────────────┘
               │ writes
┌──────────────▼──────────────────────┐
│  Shared Framework (App Group)       │
│  • TOTPGenerator (RFC 6238)         │
│  • KeychainManager (shared access)  │
│  • Account model (Codable)          │
│  • Base32 decoder                   │
│  • BiometricAuthManager             │
└──────────────┬──────────────────────┘
               │ reads
┌──────────────▼──────────────────────┐
│  Keyboard Extension                 │
│  • Auth bar (horizontal scroll)     │
│  • QWERTY keyboard                  │
│  • Tap-to-insert (textDocumentProxy)│
│  • Countdown ring per code          │
└─────────────────────────────────────┘
```

## Security Model

- **No "Allow Full Access" required** — uses App Groups + shared Keychain access group
- **No network access** from the keyboard extension — TOTP codes are pure local math
- **No clipboard** — `textDocumentProxy.insertText()` injects directly into the text field
- **Secrets stored in iOS Keychain** with `kSecAttrAccessibleAfterFirstUnlock`
- **Biometric lock** on the companion app — auto-locks when backgrounded
- **iCloud Keychain sync** available via `kSecAttrSynchronizable` (opt-in)

## Project Structure

```
KeyAuth/
├── Shared/                        # Linked by both targets
│   ├── Account.swift              # Data model + otpauth:// parser
│   ├── AccountStore.swift         # ObservableObject wrapping Keychain
│   ├── Base32.swift               # Base32 decoder for TOTP secrets
│   ├── BiometricAuthManager.swift # FaceID/TouchID + passcode fallback
│   ├── KeychainManager.swift      # Shared Keychain CRUD
│   └── TOTPGenerator.swift        # RFC 6238 TOTP (SHA1/256/512)
├── App/                           # Companion app target
│   ├── KeyAuthApp.swift           # Entry point with biometric gate
│   ├── Info.plist                 # Camera + FaceID usage descriptions
│   ├── KeyAuth.entitlements       # App Groups + Keychain sharing
│   └── Views/
│       ├── ContentView.swift      # Account list with live codes
│       ├── AccountRowView.swift   # Row: issuer icon + code + countdown
│       ├── LockScreenView.swift   # Biometric unlock screen
│       ├── ManualEntryView.swift  # Manual secret key entry form
│       └── QRScannerView.swift    # AVFoundation QR scanner
├── KeyboardExtension/             # Keyboard extension target
│   ├── KeyboardViewController.swift  # UIInputViewController + QWERTY + auth bar
│   ├── TOTPCodeCell.swift         # Collection view cell: code + countdown ring
│   ├── Info.plist                 # Extension config (RequestsOpenAccess: false)
│   └── KeyAuthKeyboard.entitlements
└── project.yml                    # XcodeGen project spec
```

## Setup

### Option A: XcodeGen (recommended)

```bash
brew install xcodegen
cd KeyAuth
xcodegen generate
open KeyAuth.xcodeproj
```

### Option B: Manual Xcode Setup

1. Create a new iOS App project named "KeyAuth"
2. Add a new target → Custom Keyboard Extension named "KeyAuthKeyboard"
3. Add all `Shared/` files to **both** targets (check both in target membership)
4. Add `App/Views/` files to the **KeyAuth** app target only
5. Add `KeyboardExtension/` files to the **KeyAuthKeyboard** target only
6. Configure both targets:
   - Signing & Capabilities → + App Groups → `group.com.keyauth.shared`
   - Signing & Capabilities → + Keychain Sharing → `com.keyauth.shared`
7. In `KeychainManager.swift`, set `accessGroup` to `"YOURTEAMID.com.keyauth.shared"`
8. Build and run on a physical device (keyboard extensions don't work in simulator)

### Enable the Keyboard

1. Build & run the app on your device
2. Settings → General → Keyboard → Keyboards → Add New Keyboard
3. Select "KeyAuth — KeyAuthKeyboard"
4. **Do NOT enable "Allow Full Access"** — it's not needed

## How It Works

### Adding Accounts

1. Open the KeyAuth companion app
2. Authenticate with FaceID/TouchID
3. Tap + → Scan QR Code (or enter manually)
4. The `otpauth://` URL is parsed and the secret is stored in the shared Keychain

### Using Codes

1. In any app's login/2FA field, switch to the KeyAuth keyboard (globe key)
2. The auth bar at the top shows all your TOTP codes with live countdowns
3. Tap a code → it inserts directly into the text field
4. Switch back to your normal keyboard

### TOTP Implementation

Standard RFC 6238 with support for:
- **Algorithms**: HMAC-SHA1 (default), SHA-256, SHA-512
- **Digits**: 6 (default), 7, 8
- **Period**: 30s (default), 60s
- **URI format**: `otpauth://totp/Issuer:label?secret=BASE32&algorithm=SHA1&digits=6&period=30`

## Keyboard Extension Constraints

iOS keyboard extensions run in a sandboxed process with strict limits:
- **50MB memory limit** — TOTP is pure math, well within budget
- **No network access** without "Allow Full Access" — we don't need it
- **No access to GPS, camera, microphone**
- **Shared data only via App Groups / Keychain** — this is how we share secrets

## Roadmap

- [ ] iCloud Keychain sync toggle in settings
- [ ] Import from Google Authenticator (protobuf QR batch export)
- [ ] Import from Authy encrypted backup
- [ ] Issuer favicon fetching (companion app only, cached)
- [ ] Search/filter in the keyboard auth bar
- [ ] Widget for Lock Screen codes
- [ ] watchOS companion with codes on wrist
