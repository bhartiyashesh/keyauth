---
phase: 02-ios-relay-client-pairing
plan: 01
subsystem: crypto, networking
tags: [cryptokit, x25519, chacha20-poly1305, websocket, keychain, swift]

requires:
  - phase: 01-relay-server
    provides: "WebSocket relay server with MessageEnvelope protocol, room routing, APNs push"
provides:
  - "CryptoBoxManager: X25519 key generation, HKDF shared key derivation, ChaChaPoly seal/open"
  - "PairingStore: Keychain-backed pairing state with sharedKey accessor"
  - "RelayClient: WebSocket client with connection lifecycle, message handling, encryption"
  - "Relay protocol types: MessageEnvelope, CodeRequest, PairingQRPayload, PairingData"
affects: [02-ios-relay-client-pairing, 03-chrome-extension]

tech-stack:
  added: [CryptoKit]
  patterns: [fileprivate WebSocket delegate, caseless enum crypto namespace, Keychain upsert for pairing data]

key-files:
  created:
    - Shared/CryptoBoxManager.swift
    - Shared/PairingStore.swift
    - Shared/RelayClient.swift
  modified:
    - KeyAuth.xcodeproj/project.pbxproj

key-decisions:
  - "Used fileprivate(set) for RelayClient.state to allow WebSocketDelegate access within same file"
  - "Separate WebSocketDelegate class (not RelayClient extension) avoids nonisolated conformance complexity on @MainActor class"
  - "All relay protocol types colocated in CryptoBoxManager.swift for cohesion"

patterns-established:
  - "fileprivate WebSocket delegate pattern: separate class in same file accesses fileprivate properties"
  - "Keychain pairing service: com.keyauth.pairing with shared access group W646UCTVQV.com.keyauth.shared"
  - "E2E wire format: nonce(12) + ciphertext + tag(16) via ChaChaPoly.SealedBox.combined"

requirements-completed: [IOS-01, IOS-04, PAIR-02, CODE-02]

duration: 8min
completed: 2026-04-15
---

# Phase 02 Plan 01: Core Shared Services Summary

**X25519+ChaChaPoly E2E encryption, Keychain-backed pairing store, and URLSessionWebSocketTask relay client -- three zero-dependency Swift services**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-15T16:26:36Z
- **Completed:** 2026-04-15T16:34:56Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- CryptoBoxManager provides X25519 key generation, HKDF-SHA256 shared key derivation, and ChaChaPoly seal/open with nonce(12)+ciphertext+tag(16) wire format
- PairingStore persists PairingData (roomId, relayURL, encryption keys) to Keychain using the established upsert pattern, exposes isPaired and sharedKey for downstream consumers
- RelayClient manages WebSocket lifecycle with ConnectionState transitions, sends join with deviceToken on open, decrypts incoming code requests via CryptoBoxManager, and exposes pendingCodeRequest for the approval UI

## Task Commits

Each task was committed atomically:

1. **Task 1: CryptoBoxManager and relay protocol types** - `551088c` (feat)
2. **Task 2: PairingStore with Keychain persistence** - `2102979` (feat)
3. **Task 3: RelayClient WebSocket service** - `5bea9f0` (feat)

## Files Created/Modified
- `Shared/CryptoBoxManager.swift` - E2E encryption enum (X25519, ChaChaPoly) + relay protocol types (MessageEnvelope, CodeRequest, PairingQRPayload, PairingData)
- `Shared/PairingStore.swift` - @MainActor ObservableObject singleton with Keychain CRUD for pairing data
- `Shared/RelayClient.swift` - @MainActor ObservableObject singleton WebSocket client with receive loop, message decryption, and encrypted code sending
- `KeyAuth.xcodeproj/project.pbxproj` - Added all three files to both KeyAuth and KeyAuthKeyboard targets

## Decisions Made
- Used `fileprivate(set)` for RelayClient.state and `fileprivate` for deviceToken to allow the WebSocketDelegate (separate class in same file) to access them. This avoids making RelayClient conform to URLSessionWebSocketDelegate directly, which would require `nonisolated` methods on a `@MainActor` class.
- Colocated all relay protocol types (MessageEnvelope, CodeRequest, PairingQRPayload, PairingData) in CryptoBoxManager.swift since they are tightly coupled to the encryption/relay domain.
- Used `[String: String]` for MessageEnvelope payload instead of AnyCodable -- all Phase 2 payloads are string-valued (deviceToken hex, base64 encrypted data).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed private(set) access for WebSocket delegate**
- **Found during:** Task 3 (RelayClient WebSocket service)
- **Issue:** `@Published private(set) var state` and `private var deviceToken` prevented the WebSocketDelegate class from setting state and reading deviceToken in `didOpenWithProtocol`
- **Fix:** Changed to `fileprivate(set)` for state and `fileprivate` for deviceToken
- **Files modified:** Shared/RelayClient.swift
- **Verification:** Build succeeded after fix
- **Committed in:** 5bea9f0 (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Access control adjustment necessary for compile. No scope creep.

## Issues Encountered
- iPhone 16 simulator not available in Xcode -- used iPhone 15 simulator (device ID 8F13BE3C-4005-433E-A16B-70F71CE9957F) for all builds

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three Shared/ services ready for Plan 02 (pairing UI + QR scanner) and Plan 03 (code approval + lifecycle)
- PairingStore.savePairing() ready to be called from pairing QR scan flow
- RelayClient.connect() ready to be called on foreground entry
- RelayClient.pendingCodeRequest ready to trigger CodeApprovalView sheet
- No blockers for subsequent plans

---
*Phase: 02-ios-relay-client-pairing*
*Completed: 2026-04-15*
