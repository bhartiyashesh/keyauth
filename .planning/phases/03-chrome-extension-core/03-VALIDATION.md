---
phase: 03
slug: chrome-extension-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Vitest (via WXT/Vite) for unit tests; node:test for crypto interop |
| **Config file** | None -- Wave 0 creates |
| **Quick run command** | `cd extension && npx vitest run --reporter=verbose` |
| **Full suite command** | `cd extension && npx vitest run` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | PAIR-01 | — | QR payload JSON format | unit | `npx vitest run src/lib/crypto.test.ts -t "QR payload"` | No -- W0 | pending |
| 03-01-02 | 01 | 1 | PAIR-03 | — | Crypto seal/open round-trip | unit | `npx vitest run src/lib/crypto.test.ts -t "decrypt"` | No -- W0 | pending |
| 03-02-01 | 02 | 2 | CODE-01 | — | Request Code message via relay | unit | `npx vitest run src/lib/relay.test.ts -t "request"` | No -- W0 | pending |
| 03-02-02 | 02 | 2 | PAIR-05 | — | Popup state machine (3 states) | unit | `npx vitest run src/entrypoints/popup/App.test.tsx -t "states"` | No -- W0 | pending |
| 03-03-01 | 03 | 3 | CODE-04 | — | Countdown timer + auto-dismiss | unit | `npx vitest run src/components/CodeView.test.tsx -t "countdown"` | No -- W0 | pending |
| 03-03-02 | 03 | 3 | FILL-03 | — | Clipboard copy + 30s auto-clear | manual-only | N/A | N/A | pending |
| INTEROP | 01 | 1 | CODE-03 | — | JS/Swift encrypt/decrypt interop | integration | `npx tsx src/lib/crypto.interop.test.ts` | No -- W0 | pending |

---

## Wave 0 Requirements

- [ ] `extension/vitest.config.ts` -- Vitest configuration
- [ ] `extension/src/lib/crypto.test.ts` -- CryptoBox seal/open, key derivation, QR payload tests
- [ ] `extension/src/lib/crypto.interop.test.ts` -- Cross-platform test vectors from iOS CryptoKit
- [ ] `extension/src/lib/relay.test.ts` -- Message envelope creation, WebSocket message handling
- [ ] `extension/src/components/CodeView.test.tsx` -- Countdown timer behavior
- [ ] Framework install: `npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Clipboard copy + auto-clear | FILL-03 | Clipboard API requires browser context | 1. Click copy button in popup. 2. Verify clipboard contains code. 3. Wait 30s. 4. Verify clipboard is cleared. |
| QR code scan by iOS | PAIR-01 | Requires physical iOS device | 1. Open extension popup. 2. Scan QR with iOS KeyAuth app. 3. Verify pairing completes. |
| End-to-end code request | CODE-01+CODE-03 | Requires paired iOS + relay | 1. Pair extension with phone. 2. Click Request Code. 3. Approve on phone. 4. Verify code appears in popup. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
