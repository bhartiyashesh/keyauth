# Phase 3: Chrome Extension Core - Context

**Gathered:** 2026-04-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the Chrome extension popup, service worker, and WebSocket client that completes the full request-to-code flow end-to-end. The extension generates a pairing QR code, connects to the relay via WebSocket, sends code requests to the paired iOS app, receives encrypted TOTP codes, and displays them with a countdown timer. No content script or auto-fill (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Extension Framework
- **D-01:** WXT framework with React for the popup UI and TypeScript throughout
- **D-02:** Manifest V3 (WXT handles the boilerplate, HMR, and build config)
- **D-03:** Extension code lives in `extension/` directory at project root (monorepo alongside relay/ and iOS app)

### Extension Popup Design
- **D-04:** Minimal single-purpose popup -- connection status + "Request Code" button. No account list in the extension; the phone shows the approval screen with account selection.
- **D-05:** Clean minimal style with system colors -- white/dark background, subtle borders, system font. Small fixed-width popup (~320px). Matches Chrome's native extension aesthetic.
- **D-06:** Three popup states: (1) Not paired -- show "Pair" button, (2) Paired/connected -- show "Request Code" button with green status dot, (3) Code received -- show 6-digit code with countdown

### QR Pairing Flow
- **D-07:** QR code generated in the popup itself -- extension generates roomId (UUID) + X25519 keypair, encodes `{ roomId, relayURL, publicKey }` as JSON, renders as QR code
- **D-08:** QR has a 5-minute TTL. Auto-refreshes (new roomId + keypair) when expired. Pairing tokens are single-use.
- **D-09:** After successful pairing (iOS app joins room and sends acknowledgment), popup shows a brief green checkmark animation then transitions to "Connected" state with green dot
- **D-10:** Pairing data (roomId, relay URL, encryption keys) stored in `chrome.storage.local` (persists across sessions)

### Code Display + Clipboard
- **D-11:** Large monospace 6-digit code displayed with space separator (e.g., "482 937"). Circular countdown ring showing seconds remaining in the TOTP period.
- **D-12:** One-click copy button below the code. Clipboard automatically cleared after 30 seconds. Brief "Copied!" toast confirmation.
- **D-13:** Code display auto-dismisses when the TOTP period expires (code becomes stale)

### E2E Encryption (from Phase 1+2)
- **D-14:** `@noble/ciphers` library for ChaCha20-Poly1305 encryption (interoperable with iOS CryptoKit ChaChaPoly)
- **D-15:** `@noble/curves` library for X25519 key exchange (interoperable with iOS CryptoKit Curve25519.KeyAgreement)
- **D-16:** Wire format: `nonce(12) || ciphertext || tag(16)` -- same as iOS CryptoBoxManager
- **D-17:** HKDF-SHA256 key derivation with salt="" and info="KeyAuth-E2E" -- must match iOS CryptoBoxManager exactly

### Service Worker
- **D-18:** Service worker manages the WebSocket connection to the relay. Reconnects on wake from idle.
- **D-19:** Connection state and pairing data stored in `chrome.storage.session` (survives service worker restarts within session)
- **D-20:** Service worker sends `join` message with stored device info on WebSocket connect

### Claude's Discretion
- Exact popup dimensions and spacing
- QR code library choice (e.g., qrcode.react or similar)
- Service worker reconnection retry strategy
- How "Request Code" message is structured (just needs to be an opaque blob the relay forwards)
- Error state UI (connection lost, request timeout, etc.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Relay Protocol (from Phase 1)
- `.planning/phases/01-relay-server/01-CONTEXT.md` -- Message envelope protocol, room lifecycle, APNs integration
- `relay/src/types.ts` -- MessageEnvelope type `{ v, type, id, payload }`
- `relay/src/handlers.ts` -- join, register_token, opaque forward routing

### iOS E2E Encryption (from Phase 2)
- `Shared/CryptoBoxManager.swift` -- CryptoKit implementation: Curve25519 + ChaChaPoly + HKDF-SHA256. The JS implementation MUST produce byte-identical output.
- `.planning/phases/02-ios-relay-client-pairing/02-RESEARCH.md` -- CryptoKit/noble-ciphers interop details, wire format

### Project Constraints
- `.planning/PROJECT.md` -- Chrome Manifest V3 constraints, relay URL, E2E encryption decision
- `.planning/REQUIREMENTS.md` -- PAIR-01, PAIR-03, PAIR-05, CODE-01, CODE-03, CODE-04, FILL-03 definitions
- `.planning/research/STACK.md` -- WXT framework choice rationale

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Relay server is live at `wss://cooperative-respect-production-29f8.up.railway.app`
- Relay protocol types already defined in `relay/src/types.ts` -- extension client must match this protocol
- Research from `.planning/research/STACK.md` recommends WXT for the extension framework

### Established Patterns
- Relay uses versioned JSON envelope `{ v:1, type, id, payload }`
- Only `join` and `register_token` are server-understood; everything else is opaque forwarded
- iOS sends encrypted blobs in `payload.data` as base64 strings

### Integration Points
- Extension WebSocket connects to relay URL with `?roomId=<uuid>` query parameter
- Extension generates QR payload `{ roomId, relayURL, publicKey }` that iOS `PairingQRScannerView` parses
- Extension receives encrypted code responses from iOS, decrypts with shared key
- Pairing handshake: extension joins room first, iOS scans QR and joins same room, key exchange completes

</code_context>

<specifics>
## Specific Ideas

- The popup should feel like a utility -- fast to open, fast to get a code, fast to close. No unnecessary screens or loading states.
- The circular countdown ring gives immediate visual feedback about code freshness without needing to read numbers.
- QR code in the popup (not a new tab) keeps the pairing flow contained and quick.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 03-chrome-extension-core*
*Context gathered: 2026-04-15*
