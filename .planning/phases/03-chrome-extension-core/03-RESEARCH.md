# Phase 03: Chrome Extension Core - Research

**Researched:** 2026-04-15
**Domain:** Chrome extension (Manifest V3, WXT, React), WebSocket service worker, E2E encryption (X25519 + ChaCha20-Poly1305 interop with CryptoKit), QR code generation
**Confidence:** HIGH

## Summary

Phase 3 builds the Chrome extension that completes the end-to-end code request flow. The extension consists of three layers: (1) a React popup UI rendered via WXT with three states (unpaired, connected, code-received), (2) a Manifest V3 service worker that maintains a WebSocket connection to the relay with 20-second keepalive pings, and (3) a crypto module using `@noble/curves` for X25519 key exchange, `@noble/ciphers` for ChaCha20-Poly1305 encryption, and `@noble/hashes` for HKDF-SHA256 key derivation -- all producing byte-identical output to the iOS CryptoKit implementation already deployed in Phase 2.

The most critical technical finding is the **wire format mismatch** between noble-ciphers and CryptoKit that must be handled explicitly. CryptoKit's `ChaChaPoly.SealedBox.combined` outputs `nonce(12) || ciphertext || tag(16)`, while noble-ciphers' `chacha20poly1305.encrypt()` outputs only `ciphertext || tag(16)` with the nonce supplied separately. The extension must manually prepend the 12-byte nonce when sending encrypted data (so iOS can reconstruct a `SealedBox` from `.combined`), and strip the first 12 bytes as nonce when receiving encrypted data from iOS. This is confirmed by examining `Shared/CryptoBoxManager.swift` lines 64-68 (seal) and 71-73 (open) which use `.combined` format exclusively. The HKDF derivation must use `salt: new Uint8Array(0)` (empty) and `info: new TextEncoder().encode("KeyAuth-E2E")` to match CryptoKit's `Data()` salt and `Data("KeyAuth-E2E".utf8)` info exactly.

**Primary recommendation:** Use `@noble/ciphers` v2.2.0, `@noble/curves` v2.2.0, and `@noble/hashes` v2.2.0 for the crypto layer. Wrap all crypto operations in a `CryptoBox` module that handles the nonce prepend/strip conversion between noble-ciphers format and CryptoKit wire format. Use `qrcode.react` v4.2.0 for QR generation. Use `chrome.storage.local` for persistent pairing data and `chrome.storage.session` for runtime connection state.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** WXT framework with React for the popup UI and TypeScript throughout
- **D-02:** Manifest V3 (WXT handles the boilerplate, HMR, and build config)
- **D-03:** Extension code lives in `extension/` directory at project root (monorepo alongside relay/ and iOS app)
- **D-04:** Minimal single-purpose popup -- connection status + "Request Code" button. No account list in the extension; the phone shows the approval screen with account selection.
- **D-05:** Clean minimal style with system colors -- white/dark background, subtle borders, system font. Small fixed-width popup (~320px). Matches Chrome's native extension aesthetic.
- **D-06:** Three popup states: (1) Not paired -- show "Pair" button, (2) Paired/connected -- show "Request Code" button with green status dot, (3) Code received -- show 6-digit code with countdown
- **D-07:** QR code generated in the popup itself -- extension generates roomId (UUID) + X25519 keypair, encodes `{ roomId, relayURL, publicKey }` as JSON, renders as QR code
- **D-08:** QR has a 5-minute TTL. Auto-refreshes (new roomId + keypair) when expired. Pairing tokens are single-use.
- **D-09:** After successful pairing (iOS app joins room and sends acknowledgment), popup shows a brief green checkmark animation then transitions to "Connected" state with green dot
- **D-10:** Pairing data (roomId, relay URL, encryption keys) stored in `chrome.storage.local` (persists across sessions)
- **D-11:** Large monospace 6-digit code displayed with space separator (e.g., "482 937"). Circular countdown ring showing seconds remaining in the TOTP period.
- **D-12:** One-click copy button below the code. Clipboard automatically cleared after 30 seconds. Brief "Copied!" toast confirmation.
- **D-13:** Code display auto-dismisses when the TOTP period expires (code becomes stale)
- **D-14:** `@noble/ciphers` library for ChaCha20-Poly1305 encryption (interoperable with iOS CryptoKit ChaChaPoly)
- **D-15:** `@noble/curves` library for X25519 key exchange (interoperable with iOS CryptoKit Curve25519.KeyAgreement)
- **D-16:** Wire format: `nonce(12) || ciphertext || tag(16)` -- same as iOS CryptoBoxManager
- **D-17:** HKDF-SHA256 key derivation with salt="" and info="KeyAuth-E2E" -- must match iOS CryptoBoxManager exactly
- **D-18:** Service worker manages the WebSocket connection to the relay. Reconnects on wake from idle.
- **D-19:** Connection state and pairing data stored in `chrome.storage.session` (survives service worker restarts within session)
- **D-20:** Service worker sends `join` message with stored device info on WebSocket connect

### Claude's Discretion
- Exact popup dimensions and spacing
- QR code library choice (e.g., qrcode.react or similar)
- Service worker reconnection retry strategy
- How "Request Code" message is structured (just needs to be an opaque blob the relay forwards)
- Error state UI (connection lost, request timeout, etc.)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PAIR-01 | Chrome extension generates a QR code containing roomId and relay URL for one-time pairing | QR code library (qrcode.react), X25519 keypair generation via @noble/curves, QR payload format `{ roomId, relayURL, publicKey }` matching iOS `PairingQRPayload` Codable struct |
| PAIR-03 | Pairing tokens are single-use and expire after a TTL (e.g., 5 minutes) | 5-minute setTimeout auto-refresh in popup, regenerate roomId + keypair on expiry, service worker disconnects stale room on refresh |
| PAIR-05 | Extension popup shows pairing status indicator (connected/disconnected/paired) | Three-state popup design (D-06), chrome.storage.session for runtime state, message passing between service worker and popup |
| CODE-01 | User clicks extension popup, selects an account, and initiates a code request | Simplified per D-04: no account list, just "Request Code" button. Encrypted request sent via relay as opaque blob. iOS presents account selection. |
| CODE-03 | TOTP code is generated on the phone after biometric approval, then sent via relay to extension | Extension decrypts incoming `code_response` message using CryptoBox module. iOS sends `{ data: base64(nonce+ciphertext+tag) }` in payload. |
| CODE-04 | Extension popup displays the received code with an expiry countdown timer | Large monospace code with circular SVG countdown ring. Auto-dismiss on TOTP period expiry. |
| FILL-03 | Extension provides clipboard copy with automatic 30-second clear as fallback | `navigator.clipboard.writeText()` works directly in popup context with `clipboardWrite` permission. setTimeout for 30s auto-clear. |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WXT | 0.20.x | Extension build framework (Vite-based, file-based entrypoints, HMR) | Actively maintained, auto-generates manifest.json, handles MV3 service worker bundling |
| @wxt-dev/module-react | latest | React integration for WXT (Vite plugin, auto-imports) | Official WXT module for React popup/options page entrypoints |
| React | 19.x | Popup UI framework | User decision D-01; reactive state for popup transitions |
| TypeScript | 5.x | Language (via WXT) | Type safety for relay protocol envelopes and crypto types |
| @noble/ciphers | 2.2.0 | ChaCha20-Poly1305 authenticated encryption | Audited (cure53 Sept 2024), zero-dependency, tree-shakeable, interoperable with CryptoKit |
| @noble/curves | 2.2.0 | X25519 key exchange (ECDH) | Audited, zero-dependency, RFC 7748 compliant, ESM-only in v2 |
| @noble/hashes | 2.2.0 | HKDF-SHA256 key derivation | Required for HKDF step between X25519 shared secret and symmetric key |
| qrcode.react | 4.2.0 | QR code SVG rendering in React popup | Most popular React QR library (1230+ dependents), renders as SVG, no canvas needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Vite | 6.x (via WXT) | Bundler | Automatically used by WXT; no direct configuration needed |
| uuid | — | Generate roomId UUIDs | Could use `crypto.randomUUID()` (available in service worker and popup) instead |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| qrcode.react | react-qr-code 2.0.18 | Both work; qrcode.react has longer track record and more npm dependents. react-qr-code is slightly more recently published. Either is acceptable. |
| @noble/ciphers | libsodium-wrappers | libsodium is larger (~200KB), uses wasm, heavier for extension bundle. Noble is tree-shakeable and lighter. |
| crypto.randomUUID() | uuid npm package | crypto.randomUUID() is built-in to service worker and popup contexts. No external dependency needed. |
| React 19 | Vanilla TypeScript | User explicitly chose React in D-01. Stack research originally recommended vanilla TS for minimal popup, but user decision overrides. |

**Installation:**
```bash
# In extension/ directory
npx wxt@latest init  # Select React template
npm install @noble/ciphers @noble/curves @noble/hashes qrcode.react
npm install -D @wxt-dev/module-react
```

## Architecture Patterns

### Recommended Project Structure
```
extension/
├── src/
│   ├── entrypoints/
│   │   ├── popup/
│   │   │   ├── index.html           # WXT popup entrypoint
│   │   │   ├── main.tsx              # React root render
│   │   │   ├── App.tsx               # Main popup component (state machine)
│   │   │   └── style.css             # Minimal CSS (system font, ~320px width)
│   │   └── background.ts            # Service worker (WebSocket, keepalive, storage)
│   ├── components/
│   │   ├── PairingView.tsx           # QR code display + TTL countdown
│   │   ├── ConnectedView.tsx         # "Request Code" button + green status dot
│   │   ├── CodeView.tsx              # 6-digit code + circular countdown + copy
│   │   └── StatusDot.tsx             # Reusable status indicator component
│   ├── lib/
│   │   ├── crypto.ts                 # CryptoBox module (X25519, ChaCha20, HKDF)
│   │   ├── relay.ts                  # WebSocket client logic (connect, send, receive)
│   │   ├── storage.ts                # chrome.storage.local + session wrappers
│   │   └── types.ts                  # MessageEnvelope, PairingData, CodeResponse types
│   └── assets/
│       └── icon.png                  # Extension icon (16, 48, 128 variants)
├── public/
│   └── icon/
│       ├── 16.png
│       ├── 48.png
│       └── 128.png
├── wxt.config.ts                     # WXT config (React module, manifest overrides)
├── tsconfig.json
└── package.json
```

### Pattern 1: WXT Configuration with React
**What:** WXT uses `wxt.config.ts` for framework integration and manifest property overrides.
**When to use:** Project initialization and manifest configuration.
**Example:**
```typescript
// extension/wxt.config.ts
import { defineConfig } from 'wxt';

export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-react'],
  manifest: {
    name: 'KeyAuth',
    description: 'One-click TOTP codes from your phone',
    minimum_chrome_version: '116',
    permissions: ['storage', 'clipboardWrite'],
    action: {
      default_popup: 'popup.html',
      default_icon: {
        '16': 'icon/16.png',
        '48': 'icon/48.png',
        '128': 'icon/128.png',
      },
    },
  },
});
```
**Source:** WXT docs (wxt.dev/guide/essentials/config/manifest), Chrome MV3 docs

### Pattern 2: Service Worker WebSocket with 20s Keepalive
**What:** The background service worker opens a WebSocket to the relay and sends a ping every 20 seconds to keep the service worker alive (Chrome 116+ behavior: WebSocket messages reset the 30-second idle timer).
**When to use:** All WebSocket communication with the relay.
**Example:**
```typescript
// extension/src/entrypoints/background.ts
import { defineBackground } from 'wxt/sandbox';

export default defineBackground(() => {
  let ws: WebSocket | null = null;
  let keepAliveInterval: ReturnType<typeof setInterval> | null = null;

  async function connect() {
    const pairing = await chrome.storage.local.get(['roomId', 'relayURL']);
    if (!pairing.roomId || !pairing.relayURL) return;

    ws = new WebSocket(`${pairing.relayURL}?roomId=${pairing.roomId}`);

    ws.onopen = () => {
      // Send join message (relay protocol: { v:1, type:"join", id:uuid, payload:{} })
      ws!.send(JSON.stringify({
        v: 1,
        type: 'join',
        id: crypto.randomUUID(),
        payload: {},
      }));
      startKeepalive();
      chrome.storage.session.set({ connectionState: 'connected' });
    };

    ws.onmessage = (event) => {
      handleMessage(JSON.parse(event.data));
    };

    ws.onclose = () => {
      stopKeepalive();
      chrome.storage.session.set({ connectionState: 'disconnected' });
      // Reconnect after delay
      setTimeout(connect, 3000);
    };
  }

  function startKeepalive() {
    keepAliveInterval = setInterval(() => {
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          v: 1,
          type: 'ping',
          id: crypto.randomUUID(),
          payload: {},
        }));
      }
    }, 20_000); // 20 seconds per Chrome guidance
  }

  function stopKeepalive() {
    if (keepAliveInterval) {
      clearInterval(keepAliveInterval);
      keepAliveInterval = null;
    }
  }

  // Reconnect on service worker wake
  chrome.storage.local.get(['roomId']).then((data) => {
    if (data.roomId) connect();
  });
});
```
**Source:** Chrome developer docs (developer.chrome.com/docs/extensions/how-to/web-platform/websockets)

### Pattern 3: CryptoBox Module (Noble-Ciphers to CryptoKit Interop)
**What:** A module that wraps noble-ciphers to produce byte-identical output to iOS CryptoKit's `ChaChaPoly.SealedBox.combined` format.
**When to use:** All E2E encryption/decryption between extension and iOS app.

**Critical interop detail:**
- CryptoKit `.combined` = `nonce(12) || ciphertext || tag(16)`
- Noble-ciphers `encrypt()` = `ciphertext || tag(16)` (nonce supplied separately)
- **Extension must prepend nonce when sending, strip nonce when receiving**

**Example:**
```typescript
// extension/src/lib/crypto.ts
import { x25519 } from '@noble/curves/ed25519.js';
import { chacha20poly1305 } from '@noble/ciphers/chacha.js';
import { randomBytes } from '@noble/ciphers/utils.js';
import { hkdf } from '@noble/hashes/hkdf.js';
import { sha256 } from '@noble/hashes/sha2.js';

const HKDF_SALT = new Uint8Array(0);  // Empty salt -- matches CryptoKit Data()
const HKDF_INFO = new TextEncoder().encode('KeyAuth-E2E');  // matches Data("KeyAuth-E2E".utf8)

/** Generate X25519 keypair for pairing */
export function generateKeyPair() {
  const { secretKey, publicKey } = x25519.keygen();
  return { privateKey: secretKey, publicKey };
}

/** Derive shared symmetric key via X25519 + HKDF-SHA256 */
export function deriveSharedKey(
  privateKey: Uint8Array,
  peerPublicKey: Uint8Array
): Uint8Array {
  const sharedSecret = x25519.getSharedSecret(privateKey, peerPublicKey);
  return hkdf(sha256, sharedSecret, HKDF_SALT, HKDF_INFO, 32);
}

/**
 * Encrypt plaintext.
 * Returns CryptoKit-compatible combined format: nonce(12) || ciphertext || tag(16)
 */
export function seal(plaintext: Uint8Array, sharedKey: Uint8Array): Uint8Array {
  const nonce = randomBytes(12);
  const cipher = chacha20poly1305(sharedKey, nonce);
  const ciphertextWithTag = cipher.encrypt(plaintext);  // ciphertext || tag(16)
  // Prepend nonce to match CryptoKit SealedBox.combined format
  const combined = new Uint8Array(12 + ciphertextWithTag.length);
  combined.set(nonce, 0);
  combined.set(ciphertextWithTag, 12);
  return combined;
}

/**
 * Decrypt CryptoKit-compatible combined format: nonce(12) || ciphertext || tag(16)
 */
export function open(combined: Uint8Array, sharedKey: Uint8Array): Uint8Array {
  const nonce = combined.slice(0, 12);
  const ciphertextWithTag = combined.slice(12);
  const cipher = chacha20poly1305(sharedKey, nonce);
  return cipher.decrypt(ciphertextWithTag);
}
```
**Source:** CryptoBoxManager.swift lines 64-73, @noble/ciphers README, @noble/hashes README

### Pattern 4: Popup-to-Service-Worker Communication
**What:** The popup (React) communicates with the service worker via `chrome.runtime.sendMessage` for actions and `chrome.storage.onChanged` for state updates.
**When to use:** All popup interactions that require service worker action (e.g., "Request Code" click).

**Example:**
```typescript
// Popup sends request to service worker
chrome.runtime.sendMessage({ type: 'request_code' });

// Service worker listens
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'request_code') {
    sendCodeRequest();
    sendResponse({ ok: true });
  }
});

// Service worker updates state via storage (popup observes)
chrome.storage.session.set({ lastCode: '482937', codeExpiry: Date.now() + 30000 });

// Popup observes state changes
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'session' && changes.lastCode) {
    setCode(changes.lastCode.newValue);
  }
});
```

### Pattern 5: QR Payload Structure
**What:** The QR code encodes JSON matching the iOS `PairingQRPayload` Codable struct.
**When to use:** Pairing flow in the popup.

**iOS expects this exact JSON structure** (from `Shared/CryptoBoxManager.swift` line 27-31):
```json
{
  "roomId": "uuid-string",
  "relayURL": "wss://cooperative-respect-production-29f8.up.railway.app",
  "publicKey": "base64-encoded-32-byte-X25519-public-key"
}
```

The `publicKey` field must be the raw 32-byte X25519 public key encoded as base64. iOS decodes this with `Data(base64Encoded:)` and reconstructs a `Curve25519.KeyAgreement.PublicKey(rawRepresentation:)`.

### Anti-Patterns to Avoid
- **Do NOT store private keys in chrome.storage.session:** Session storage is in-memory but not encrypted. Store the derived shared key in `chrome.storage.local` (persists, survives browser restart). The private key should be discarded after deriving the shared key during pairing.
- **Do NOT use `managedNonce` wrapper from noble-ciphers:** It prepends the nonce in noble-ciphers' own format, but CryptoKit expects a specific layout. Handle nonce prepending manually to match CryptoKit's `SealedBox.combined` format exactly.
- **Do NOT use XChaCha20-Poly1305:** iOS CryptoKit only supports standard ChaCha20-Poly1305 (ChaChaPoly) with 12-byte nonces. Using XChaCha with 24-byte nonces would be incompatible.
- **Do NOT call `navigator.clipboard.writeText()` from the service worker:** It only works in popup/page contexts. The popup handles clipboard directly.
- **Do NOT use `localStorage` in the service worker:** Not available in MV3 service workers. Use `chrome.storage.session` or `chrome.storage.local`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| QR code generation | Custom canvas/SVG QR renderer | `qrcode.react` | QR encoding (error correction, masking, version selection) is a well-defined but complex algorithm |
| X25519 key exchange | Manual elliptic curve math | `@noble/curves` | Cryptographic implementations must be audited; noble-curves is cure53-audited |
| ChaCha20-Poly1305 | Manual AEAD cipher | `@noble/ciphers` | Same as above; cipher implementation requires formal audit |
| HKDF-SHA256 | Manual extract-then-expand | `@noble/hashes` | RFC 5869 implementation with edge cases around salt/info handling |
| UUID generation | Custom random ID | `crypto.randomUUID()` | Built-in, cryptographically random, available in service worker and popup |
| Base64 encoding | Custom encoder | `btoa()`/`atob()` or Uint8Array conversion helpers | Standard browser APIs; use helper for Uint8Array <-> base64 conversion |
| WebSocket keepalive | Custom Offscreen Document approach | 20s `setInterval` ping | Chrome 116+ explicitly extends service worker lifetime on WebSocket messages; no Offscreen API needed |

**Key insight:** The crypto layer (X25519 + ChaCha20-Poly1305 + HKDF) is the highest-risk custom code in this phase. Every byte of the wire format must match CryptoKit exactly. Using the audited noble libraries and wrapping them in a thin interop module is the only safe approach.

## Common Pitfalls

### Pitfall 1: Noble-Ciphers / CryptoKit Wire Format Mismatch
**What goes wrong:** Extension encrypts data using noble-ciphers, but iOS CryptoKit fails to decrypt because the byte layout differs.
**Why it happens:** Noble-ciphers `encrypt()` returns `ciphertext || tag(16)` with nonce separate. CryptoKit `SealedBox(combined:)` expects `nonce(12) || ciphertext || tag(16)`.
**How to avoid:** Always prepend the 12-byte nonce when sending, always strip first 12 bytes as nonce when receiving. See CryptoBox module pattern above.
**Warning signs:** "Authentication tag mismatch" or "Invalid seal" errors on either side.

### Pitfall 2: HKDF Parameter Mismatch
**What goes wrong:** Derived symmetric keys differ between JS and iOS despite same X25519 shared secret.
**Why it happens:** HKDF is parameter-sensitive. CryptoKit uses `salt: Data()` (empty), `sharedInfo: Data("KeyAuth-E2E".utf8)`, `outputByteCount: 32`. JS must match exactly: `hkdf(sha256, sharedSecret, new Uint8Array(0), new TextEncoder().encode("KeyAuth-E2E"), 32)`.
**How to avoid:** Use identical parameters. Test with known test vectors (generate on iOS, decrypt on JS, and vice versa).
**Warning signs:** Encryption succeeds but decryption fails on the other platform.

### Pitfall 3: Service Worker Termination Dropping WebSocket
**What goes wrong:** Service worker goes idle, WebSocket closes, extension appears disconnected.
**Why it happens:** Chrome terminates service workers after 30 seconds of inactivity. WebSocket messages only extend lifetime since Chrome 116.
**How to avoid:** 20-second ping interval (per Chrome docs). Set `minimum_chrome_version: "116"` in manifest. On service worker restart, re-read pairing data from `chrome.storage.local` and reconnect.
**Warning signs:** Intermittent "disconnected" status in popup despite relay being healthy.

### Pitfall 4: Popup Lifecycle Misunderstanding
**What goes wrong:** State stored in React component is lost when popup closes and re-opens.
**Why it happens:** The popup is destroyed every time the user clicks away. It is not a persistent page.
**How to avoid:** All state that must survive popup close/reopen goes in `chrome.storage.session` (connection state, last code) or `chrome.storage.local` (pairing data). Popup reads from storage on mount, observes `chrome.storage.onChanged` for updates.
**Warning signs:** Code displayed in popup disappears when user clicks outside and re-opens.

### Pitfall 5: QR Public Key Encoding Format
**What goes wrong:** iOS fails to parse the QR code's `publicKey` field.
**Why it happens:** `x25519.getPublicKey()` returns a `Uint8Array`. This must be base64-encoded (not hex, not raw bytes) to match iOS `Data(base64Encoded:)` parsing. Standard `btoa()` only works with strings, not Uint8Arrays.
**How to avoid:** Use a Uint8Array-to-base64 helper: `btoa(String.fromCharCode(...publicKey))` or a proper `uint8ArrayToBase64()` utility.
**Warning signs:** iOS `PairingQRScannerView` shows "Invalid pairing QR code" error.

### Pitfall 6: Base64 Encoding of Encrypted Payloads
**What goes wrong:** Relay forwards the message but decryption fails on the receiving end.
**Why it happens:** The iOS side sends/receives encrypted data as base64 strings in `payload.data`. The extension must also use base64 for the `data` field (not raw binary, not hex). iOS uses `encrypted.base64EncodedString()` to encode and `Data(base64Encoded:)` to decode.
**How to avoid:** Always base64-encode the combined `nonce || ciphertext || tag` bytes before putting in `payload.data`, and base64-decode on receive before passing to `open()`.
**Warning signs:** `Data(base64Encoded:)` returns nil on iOS, or `atob()` throws on JS side.

### Pitfall 7: Clipboard Auto-Clear Race Condition
**What goes wrong:** Clipboard clear fires after user has copied something else, erasing unrelated content.
**Why it happens:** Simple `setTimeout(clearClipboard, 30000)` does not check whether the clipboard still contains the TOTP code.
**How to avoid:** Store the copied code value, read clipboard before clearing, only clear if it still matches. Or accept the simpler approach (clear unconditionally) since 30 seconds is a short window and this is the standard pattern used by 1Password and Bitwarden.
**Warning signs:** User complaints about clipboard being cleared unexpectedly.

## Code Examples

### QR Code Display in React Popup
```tsx
// extension/src/components/PairingView.tsx
import { QRCodeSVG } from 'qrcode.react';
import { useEffect, useState } from 'react';
import { generateKeyPair } from '../lib/crypto';

const RELAY_URL = 'wss://cooperative-respect-production-29f8.up.railway.app';
const QR_TTL_MS = 5 * 60 * 1000; // 5 minutes

function uint8ArrayToBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

export function PairingView() {
  const [qrData, setQrData] = useState('');
  const [expiresAt, setExpiresAt] = useState(0);

  function generateQR() {
    const { privateKey, publicKey } = generateKeyPair();
    const roomId = crypto.randomUUID();
    const payload = JSON.stringify({
      roomId,
      relayURL: RELAY_URL,
      publicKey: uint8ArrayToBase64(publicKey),
    });
    setQrData(payload);
    setExpiresAt(Date.now() + QR_TTL_MS);

    // Store privateKey temporarily for pairing completion
    chrome.storage.session.set({
      pendingPairing: {
        roomId,
        privateKey: uint8ArrayToBase64(privateKey),
      },
    });

    // Tell service worker to connect to this room
    chrome.runtime.sendMessage({ type: 'start_pairing', roomId });
  }

  useEffect(() => {
    generateQR();
  }, []);

  // Auto-refresh on TTL expiry
  useEffect(() => {
    if (!expiresAt) return;
    const timeout = setTimeout(generateQR, expiresAt - Date.now());
    return () => clearTimeout(timeout);
  }, [expiresAt]);

  return (
    <div style={{ textAlign: 'center', padding: 16 }}>
      <p style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>
        Scan with KeyAuth on your phone
      </p>
      {qrData && (
        <QRCodeSVG
          value={qrData}
          size={200}
          level="M"
          style={{ margin: '0 auto' }}
        />
      )}
    </div>
  );
}
```
**Source:** qrcode.react docs, iOS PairingQRScannerView.swift expected payload format

### Relay Message Envelope Types (Extension Side)
```typescript
// extension/src/lib/types.ts

/** Must match relay/src/types.ts MessageEnvelope */
export interface MessageEnvelope {
  v: 1;
  type: string;
  id: string;
  payload: Record<string, unknown>;
}

/** Stored in chrome.storage.local after successful pairing */
export interface PairingData {
  roomId: string;
  relayURL: string;
  sharedKey: string;    // base64-encoded 32-byte derived symmetric key
  pairedAt: number;     // timestamp
}

/** Encrypted request sent to iOS (inside payload.data as base64) */
export interface CodeRequest {
  id: string;           // correlation ID echoed in response
  issuer: string;       // e.g., "GitHub" -- shown on iOS approval sheet
  label: string;        // e.g., "user@email.com"
}

/** Encrypted response from iOS (inside payload.data as base64) */
export interface CodeResponse {
  code: string;         // 6-digit TOTP code
  requestId: string;    // correlation ID from request
}

export function createEnvelope(type: string, payload: Record<string, unknown> = {}): MessageEnvelope {
  return { v: 1, type, id: crypto.randomUUID(), payload };
}
```

### Circular Countdown Ring (SVG)
```tsx
// extension/src/components/CodeView.tsx
interface CountdownRingProps {
  secondsRemaining: number;
  totalSeconds: number;  // 30 for TOTP
  size: number;
}

function CountdownRing({ secondsRemaining, totalSeconds, size }: CountdownRingProps) {
  const radius = (size - 4) / 2;
  const circumference = 2 * Math.PI * radius;
  const progress = secondsRemaining / totalSeconds;
  const dashOffset = circumference * (1 - progress);

  return (
    <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
      <circle
        cx={size / 2} cy={size / 2} r={radius}
        fill="none" stroke="#e0e0e0" strokeWidth={3}
      />
      <circle
        cx={size / 2} cy={size / 2} r={radius}
        fill="none"
        stroke={secondsRemaining <= 5 ? '#ef4444' : '#22c55e'}
        strokeWidth={3}
        strokeDasharray={circumference}
        strokeDashoffset={dashOffset}
        strokeLinecap="round"
        style={{ transition: 'stroke-dashoffset 1s linear' }}
      />
      <text
        x={size / 2} y={size / 2}
        textAnchor="middle" dominantBaseline="central"
        style={{ transform: 'rotate(90deg)', transformOrigin: 'center', fontSize: 14 }}
      >
        {secondsRemaining}s
      </text>
    </svg>
  );
}
```

### Clipboard Copy with Auto-Clear
```typescript
// In popup context (has DOM access)
async function copyCodeToClipboard(code: string) {
  await navigator.clipboard.writeText(code);

  // Auto-clear after 30 seconds
  setTimeout(async () => {
    try {
      await navigator.clipboard.writeText('');
    } catch {
      // Popup may be closed by now; best-effort clear
    }
  }, 30_000);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MV2 background pages (persistent) | MV3 service workers (ephemeral) | Chrome 88+ (MV3 launch) | WebSocket must use keepalive ping; state must be in chrome.storage |
| Offscreen Document for WebSocket | 20s ping keepalive in service worker | Chrome 116 (Aug 2023) | WebSocket messages extend service worker lifetime; no Offscreen Document needed |
| tweetnacl (NaCl box) | @noble/ciphers + @noble/curves | 2023-2024 | Noble libraries are audited, ESM-native, tree-shakeable, actively maintained |
| @noble/ciphers v1.x | v2.2.0 (ESM-only, import with .js suffix) | April 2026 | v2.x requires `.js` extension in imports; breaking change from v1 |
| @noble/curves v1.x | v2.2.0 (ESM-only) | April 2026 | v2.x is ESM-only, simplified API, keygen() method added |
| chrome.storage.session 1MB quota | 10MB quota | Chrome 112 (2023) | Ample room for connection state and temporary data |

**Deprecated/outdated:**
- `tweetnacl`: Referenced in earlier project decisions but superseded by noble libraries per Phase 2 research. CryptoKit uses ChaCha20-Poly1305, not XSalsa20-Poly1305.
- `CRXJS`: Was unmaintained for 3+ years. New maintainers shipped 2.0 in 2025 but long-term commitment uncertain.
- `Plasmo`: In maintenance mode as of 2025. React-first with outdated dependencies.

## Open Questions

1. **Pairing Acknowledgment Message Format**
   - What we know: After iOS scans QR and joins the room, it should send an acknowledgment so the extension knows pairing is complete. The relay forwards any opaque message.
   - What's unclear: The exact message type the iOS side sends after pairing. Looking at `RelayClient.swift`, the iOS sends a `join` message on connect but no explicit "pairing complete" message. The extension may need to detect pairing by: (a) receiving the iOS public key in a `pairing_ack` message, or (b) considering pairing complete when a second client joins the room (relay could notify, but currently does not).
   - Recommendation: Define a `pairing_ack` opaque message type that iOS sends after joining the room with its public key. The extension receives this, completes the ECDH key exchange, derives the shared key, and stores pairing data. This is the cleanest approach and aligns with the relay's opaque forwarding design.

2. **Code Request Content**
   - What we know: Per D-04, the extension has no account list. User just clicks "Request Code." The iOS side shows the approval sheet with account selection.
   - What's unclear: What should the encrypted code_request payload contain if there is no specific account selected on the extension side?
   - Recommendation: Send a minimal request `{ id: uuid, issuer: "", label: "" }` (empty issuer/label). iOS interprets empty fields as "user picks account." Alternatively, send only `{ id: uuid, type: "code_request" }`. The iOS `CodeRequest` struct has `id`, `issuer`, and `label` fields (from `CryptoBoxManager.swift`).

3. **Service Worker Reconnection Strategy**
   - What we know: Service worker must reconnect on WebSocket close and on wake from idle.
   - What's unclear: Exact backoff strategy for reconnection attempts.
   - Recommendation: Exponential backoff starting at 1 second, capped at 30 seconds: 1s, 2s, 4s, 8s, 16s, 30s. Reset backoff on successful connection. This is a standard pattern and prevents hammering the relay during outages.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Vitest (via WXT, which uses Vite internally) for unit tests; node:test for crypto interop tests |
| Config file | None -- Wave 0 |
| Quick run command | `cd extension && npx vitest run --reporter=verbose` |
| Full suite command | `cd extension && npx vitest run` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PAIR-01 | QR payload contains roomId, relayURL, publicKey in correct JSON format | unit | `npx vitest run src/lib/crypto.test.ts -t "QR payload"` | Wave 0 |
| PAIR-03 | QR auto-refreshes after 5-minute TTL (new roomId + keypair) | unit | `npx vitest run src/components/PairingView.test.tsx -t "TTL"` | Wave 0 |
| PAIR-05 | Popup shows correct state for disconnected/connected/paired | unit | `npx vitest run src/entrypoints/popup/App.test.tsx -t "states"` | Wave 0 |
| CODE-01 | Request Code sends encrypted message via relay | unit | `npx vitest run src/lib/relay.test.ts -t "request"` | Wave 0 |
| CODE-03 | Decrypted code_response yields valid 6-digit code | unit | `npx vitest run src/lib/crypto.test.ts -t "decrypt"` | Wave 0 |
| CODE-04 | Countdown timer decrements and auto-dismisses at 0 | unit | `npx vitest run src/components/CodeView.test.tsx -t "countdown"` | Wave 0 |
| FILL-03 | Clipboard copy writes code, auto-clears after 30s | manual-only | Manual test in Chrome (clipboard API requires browser context) | N/A |
| CRYPTO-INTEROP | JS encrypt -> Swift decrypt and Swift encrypt -> JS decrypt produce identical results | integration | `npx tsx src/lib/crypto.interop.test.ts` (using node:test with known test vectors from iOS) | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd extension && npx vitest run --reporter=verbose`
- **Per wave merge:** `cd extension && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `extension/vitest.config.ts` -- Vitest configuration for extension project
- [ ] `extension/src/lib/crypto.test.ts` -- Unit tests for CryptoBox seal/open, key derivation, QR payload format
- [ ] `extension/src/lib/crypto.interop.test.ts` -- Cross-platform interop test vectors (values generated by iOS CryptoKit)
- [ ] `extension/src/lib/relay.test.ts` -- Unit tests for message envelope creation, WebSocket message handling
- [ ] `extension/src/components/CodeView.test.tsx` -- Countdown timer behavior tests
- [ ] Framework install: `npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom`

## Sources

### Primary (HIGH confidence)
- Chrome WebSocket in MV3 service workers: https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets -- 20s keepalive, Chrome 116+ lifetime extension
- Chrome service worker lifecycle: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
- Chrome storage API: https://developer.chrome.com/docs/extensions/reference/api/storage -- session vs local, quotas
- @noble/ciphers v2.2.0: https://github.com/paulmillr/noble-ciphers -- ChaCha20-Poly1305 API, encrypt returns ciphertext+tag
- @noble/curves v2.2.0: https://github.com/paulmillr/noble-curves -- x25519 keygen, getPublicKey, getSharedSecret
- @noble/hashes v2.2.0: https://github.com/paulmillr/noble-hashes -- HKDF API with sha256
- WXT docs: https://wxt.dev/guide/essentials/entrypoints.html -- file-based entrypoints, popup directory structure
- WXT React setup: https://wxt.dev/guide/essentials/frontend-frameworks -- @wxt-dev/module-react configuration
- Existing iOS code: `Shared/CryptoBoxManager.swift`, `Shared/RelayClient.swift`, `Shared/PairingStore.swift` -- actual wire format and protocol implementation
- Relay server code: `relay/src/types.ts`, `relay/src/handlers.ts` -- MessageEnvelope type, handler routing

### Secondary (MEDIUM confidence)
- qrcode.react v4.2.0: https://github.com/zpao/qrcode.react -- React QR component, SVG rendering
- Chrome clipboard in popups: https://developer.chrome.com/blog/Offscreen-Documents-in-Manifest-v3 -- popup context supports navigator.clipboard directly
- WXT manifest config: https://wxt.dev/guide/essentials/config/manifest -- permissions, manifest overrides in wxt.config.ts

### Tertiary (LOW confidence)
- Service worker reconnection patterns: Multiple community posts and Chrome discussion groups -- no single authoritative source for exponential backoff in MV3 context

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all library versions verified against npm/GitHub, WXT docs confirmed, noble libraries confirmed v2.2.0 released April 2026
- Architecture: HIGH -- WXT file-based entrypoints verified, Chrome storage APIs verified, relay protocol verified from existing source code
- Crypto interop: HIGH -- CryptoBoxManager.swift source code examined directly; noble-ciphers encrypt output format confirmed (ciphertext+tag, nonce separate); HKDF parameters matched
- Pitfalls: HIGH -- wire format mismatch identified from first-party source code analysis; service worker lifetime behavior confirmed from Chrome developer docs

**Research date:** 2026-04-15
**Valid until:** 2026-05-15 (stable -- noble v2 just released, WXT actively maintained, Chrome MV3 is mature)
