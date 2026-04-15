---
phase: 03-chrome-extension-core
plan: 01
subsystem: crypto, extension
tags: [wxt, react, noble-ciphers, noble-curves, noble-hashes, chacha20-poly1305, x25519, hkdf, chrome-extension, manifest-v3]

# Dependency graph
requires:
  - phase: 02-ios-relay-client-pairing
    provides: CryptoBoxManager.swift wire format (nonce||ciphertext||tag) and HKDF parameters
  - phase: 01-relay-server
    provides: MessageEnvelope protocol type and relay WebSocket server
provides:
  - WXT Chrome extension project scaffold with React and TypeScript
  - CryptoBox module (generateKeyPair, deriveSharedKey, seal, open) byte-identical to iOS CryptoKit
  - MessageEnvelope, PairingData, CodeRequest, CodeResponse types matching relay protocol
  - Chrome storage wrappers for pairing data persistence
  - Base64 encoding utilities for relay message payloads
affects: [03-02, 03-03, 04-content-script]

# Tech tracking
tech-stack:
  added: [wxt@0.20.22, react@19, @noble/ciphers@2.2.0, @noble/curves@2.2.0, @noble/hashes@2.2.0, qrcode.react@4.2.0, vitest@3.2.4]
  patterns: [nonce-prepend wire format interop, HKDF-SHA256 with empty salt, ESM .js import suffixes for noble v2]

key-files:
  created:
    - extension/package.json
    - extension/wxt.config.ts
    - extension/tsconfig.json
    - extension/src/lib/crypto.ts
    - extension/src/lib/types.ts
    - extension/src/lib/storage.ts
    - extension/src/lib/crypto.test.ts
    - extension/src/entrypoints/popup/App.tsx
    - extension/src/entrypoints/popup/main.tsx
    - extension/src/entrypoints/popup/index.html
    - extension/src/entrypoints/popup/style.css
  modified: []

key-decisions:
  - "Used x25519.utils.randomSecretKey() for noble-curves v2 (v1 had randomPrivateKey)"
  - "Import paths use .js suffix for noble v2 ESM-only packages"
  - "MessageEnvelope.v typed as literal 1, not number, for stricter type safety"

patterns-established:
  - "CryptoBox seal prepends nonce: combined.set(nonce, 0) then combined.set(ciphertextWithTag, 12)"
  - "CryptoBox open strips nonce: combined.slice(0, 12) for nonce, combined.slice(12) for ciphertext+tag"
  - "HKDF constants: HKDF_SALT = new Uint8Array(0), HKDF_INFO = TextEncoder().encode('KeyAuth-E2E')"
  - "Storage pattern: chrome.storage.local for persistent data, chrome.storage.session for runtime state"

requirements-completed: [PAIR-01, PAIR-03]

# Metrics
duration: 6min
completed: 2026-04-15
---

# Phase 3 Plan 1: Extension Scaffold and CryptoBox Summary

**WXT Chrome extension with CryptoBox module producing byte-identical ChaCha20-Poly1305 wire format to iOS CryptoKit ChaChaPoly**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-15T19:40:25Z
- **Completed:** 2026-04-15T19:45:56Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments
- Scaffolded WXT Chrome extension project with React 19, TypeScript, and all crypto dependencies
- Implemented CryptoBox module with X25519 key exchange, HKDF-SHA256 derivation, and ChaCha20-Poly1305 seal/open
- Wire format matches iOS CryptoBoxManager exactly: nonce(12) || ciphertext || tag(16)
- All 12 vitest tests pass including round-trip encryption, wire format validation, and base64 encoding
- Types match relay MessageEnvelope protocol (v:1, type, id, payload)

## Task Commits

Each task was committed atomically:

1. **Task 1: Scaffold WXT project and install dependencies** - `b4ff6f0` (feat)
2. **Task 2 RED: Add failing tests for CryptoBox, types, base64** - `8456e3a` (test)
3. **Task 2 GREEN: Implement CryptoBox module, types, storage** - `c02228d` (feat)

## Files Created/Modified
- `extension/package.json` - WXT project with noble crypto and React dependencies
- `extension/wxt.config.ts` - WXT config with React module, storage + clipboardWrite permissions
- `extension/tsconfig.json` - Strict TypeScript with ESNext and bundler resolution
- `extension/src/lib/crypto.ts` - CryptoBox: generateKeyPair, deriveSharedKey, seal, open, base64 helpers
- `extension/src/lib/crypto.test.ts` - 12 vitest tests covering all crypto operations
- `extension/src/lib/types.ts` - MessageEnvelope, PairingData, CodeRequest, CodeResponse, createEnvelope
- `extension/src/lib/storage.ts` - chrome.storage.local and session wrappers
- `extension/src/entrypoints/popup/` - Popup HTML, React root, placeholder App, CSS

## Decisions Made
- Used `x25519.utils.randomSecretKey()` instead of `randomPrivateKey()` -- noble-curves v2 renamed this method
- Added `.js` suffixes to all noble library imports -- required by v2 ESM-only packages
- Typed `MessageEnvelope.v` as literal `1` instead of `number` for stricter protocol conformance

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Noble v2 ESM import paths require .js suffix**
- **Found during:** Task 2 (CryptoBox implementation)
- **Issue:** Import `@noble/curves/ed25519` failed with "Missing specifier" -- v2 exports use `.js` suffix
- **Fix:** Changed all imports to include `.js` suffix (e.g., `@noble/curves/ed25519.js`)
- **Files modified:** extension/src/lib/crypto.ts
- **Verification:** Tests pass, build succeeds
- **Committed in:** c02228d

**2. [Rule 3 - Blocking] Noble-curves v2 renamed randomPrivateKey to randomSecretKey**
- **Found during:** Task 2 (CryptoBox implementation)
- **Issue:** `x25519.utils.randomPrivateKey()` is not a function in v2
- **Fix:** Changed to `x25519.utils.randomSecretKey()` which is the v2 equivalent
- **Files modified:** extension/src/lib/crypto.ts
- **Verification:** generateKeyPair test passes, returns valid 32-byte keypair
- **Committed in:** c02228d

---

**Total deviations:** 2 auto-fixed (2 blocking -- noble v2 API changes)
**Impact on plan:** Both fixes necessary for noble-curves v2 compatibility. No scope creep.

## Issues Encountered
None beyond the auto-fixed v2 API changes documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CryptoBox module ready for service worker WebSocket integration (Plan 02)
- Types ready for relay message handling
- Storage wrappers ready for pairing data persistence
- Build and test infrastructure established

## Self-Check: PASSED

All 14 files verified present. All 3 commits verified in git log.

---
*Phase: 03-chrome-extension-core*
*Completed: 2026-04-15*
