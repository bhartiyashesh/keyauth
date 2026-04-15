---
phase: 02
slug: ios-relay-client-pairing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) |
| **Config file** | None -- Wave 0 creates test target |
| **Quick run command** | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyAuthTests -quiet` |
| **Full suite command** | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | IOS-01 | — | WebSocket client connects/sends/receives | unit | `xcodebuild test -only-testing:KeyAuthTests/RelayClientTests` | No -- W0 | pending |
| 02-01-02 | 01 | 1 | IOS-04 | — | Pairing CRUD in Keychain | unit | `xcodebuild test -only-testing:KeyAuthTests/PairingStoreTests` | No -- W0 | pending |
| 02-01-03 | 01 | 1 | PAIR-02 | — | QR pairing JSON parsing | unit | `xcodebuild test -only-testing:KeyAuthTests/PairingQRTests` | No -- W0 | pending |
| 02-01-04 | 01 | 1 | CODE-02 | — | E2E encrypt/decrypt round-trip | unit | `xcodebuild test -only-testing:KeyAuthTests/CryptoBoxTests` | No -- W0 | pending |
| 02-02-01 | 02 | 1 | PAIR-04 | — | Device token in join message | unit | `xcodebuild test -only-testing:KeyAuthTests/RelayClientTests/testJoinMessageContainsDeviceToken` | No -- W0 | pending |
| 02-02-02 | 02 | 1 | IOS-02 | — | APNs registration and push handling | manual-only | N/A | N/A | pending |
| 02-03-01 | 03 | 2 | IOS-03 | — | Approval sheet triggers biometric | unit (view model) | `xcodebuild test -only-testing:KeyAuthTests/CodeApprovalTests` | No -- W0 | pending |

---

## Wave 0 Requirements

- [ ] `KeyAuthTests/` test target -- does not exist, must be created in Xcode project
- [ ] `KeyAuthTests/RelayClientTests.swift` -- covers IOS-01, PAIR-04
- [ ] `KeyAuthTests/PairingStoreTests.swift` -- covers IOS-04
- [ ] `KeyAuthTests/PairingQRTests.swift` -- covers PAIR-02
- [ ] `KeyAuthTests/CryptoBoxTests.swift` -- covers CODE-02
- [ ] `KeyAuthTests/CodeApprovalTests.swift` -- covers IOS-03

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| APNs push registration and delivery | IOS-02 | Requires physical device and Apple Push Notification service | 1. Run on device. 2. Grant notification permission. 3. Verify device token logged. 4. Send test push via relay. 5. Verify notification appears. |
| WebSocket connection to live relay | IOS-01 | URLSessionWebSocketTask requires actual network | 1. Pair with test relay. 2. Verify connection status dot turns green. 3. Send message from browser tab. 4. Verify message received on iOS. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
