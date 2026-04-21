---
phase: 8
slug: core-extension-flow
status: active
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-20
audited: 2026-04-21
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest ^3.1.0 |
| **Config file** | extension/vitest.config.ts (or WXT default) |
| **Quick run command** | `cd extension && npx vitest run` |
| **Full suite command** | `cd extension && npx vitest run` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd extension && npx vitest run`
- **After every plan wave:** Run `cd extension && npx vitest run`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-02 | 01 | 1 | CODE-05 | T-08-01 | Domain matching uses only public metadata | unit | `npx vitest run src/lib/__tests__/domain-match.test.ts` | Yes (11 tests) | COVERED |
| 08-02-01 | 02 | 2 | CODE-05 | T-08-03 | Account list request stays within extension ID | manual | Build check: `npx wxt build` | N/A | manual-only |
| 08-02-02 | 02 | 2 | CODE-04 | — | CodeView renders when activeCodes populated | manual | Build check: `npx wxt build` | N/A | manual-only |
| 08-03-01 | 03 | 2 | CODE-03 | T-08-06 | account_list decrypted with authenticated cipher | unit | `npx vitest run src/entrypoints/__tests__/account-list-decryption.test.ts` | Yes (5 tests) | COVERED |
| 08-03-01 | 03 | 2 | RESIL-01 | — | 20s keepalive prevents worker termination | unit | `npx vitest run src/entrypoints/__tests__/background-resilience.test.ts` | Yes | COVERED |
| 08-03-01 | 03 | 2 | RESIL-02 | — | Proactive reconnect at 13min | unit | `npx vitest run src/entrypoints/__tests__/background-resilience.test.ts` | Yes | COVERED |
| 08-03-01 | 03 | 2 | RESIL-05 | — | Auto-reconnect on WebSocket drop | unit | `npx vitest run src/entrypoints/__tests__/background-resilience.test.ts` | Yes | COVERED |
| 08-04-01 | 04 | 2 | CODE-03 | T-08-09 | accountId validated against UUID store | manual | Xcode build succeeds | N/A | manual-only |
| 08-04-01 | 04 | 2 | IOS-03 | — | handleDecodedRequest sets pendingCodeRequest | manual | Xcode build succeeds | N/A | manual-only |
| 08-04-02 | 04 | 2 | RESIL-02 | T-08-10 | 13-min proactive reconnect | manual | Xcode build succeeds | N/A | manual-only |
| 08-04-02 | 04 | 2 | RESIL-04 | — | APNs token registered on every launch | manual | Xcode build succeeds | N/A | manual-only |
| 08-05-01 | 05 | 3 | FILL-01 | T-08-11 | Content script in ISOLATED world | unit | `npx vitest run src/entrypoints/__tests__/content.test.ts` | Yes (14 tests) | COVERED |
| 08-05-01 | 05 | 3 | FILL-02 | T-08-12 | Fill dispatches events for framework compat | unit | `npx vitest run src/entrypoints/__tests__/content.test.ts` | Yes | COVERED |
| 08-06-01 | 06 | 3 | RESIL-03 | T-08-15 | shouldBeConnected flag in session storage | unit | `npx vitest run src/entrypoints/__tests__/background-resilience.test.ts` | Yes (5 tests) | COVERED |
| 08-06-02 | 06 | 3 | RESIL-05 | T-08-14 | Exponential backoff caps at 30s | unit | `npx vitest run src/entrypoints/__tests__/background-resilience.test.ts` | Yes | COVERED |

*Status: 9 COVERED, 6 manual-only — all automated requirements verified*

---

## Wave 0 Requirements

- [ ] `extension/src/lib/__tests__/domain-match.test.ts` -- covers CODE-05
- [ ] `extension/src/entrypoints/__tests__/content.test.ts` -- covers FILL-01, FILL-02
- [ ] `extension/src/entrypoints/__tests__/background-resilience.test.ts` -- covers RESIL-02, RESIL-03, RESIL-05
- [ ] `jsdom` + `@types/jsdom` dev dependencies for content script testing

*Wave 0 tests are created inline with their respective plan tasks (TDD approach).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| iOS presents TOTP approval sheet on relay message | IOS-03 | Requires physical iOS device with FaceID | 1. Open extension, click account. 2. On phone, verify CodeApprovalView appears with correct account name and domain. 3. Approve with FaceID. 4. Verify code appears in extension. |
| APNs token registration on every launch | RESIL-04 | Requires iOS device with push notification entitlement | 1. Kill app and relaunch. 2. Check Xcode console for "[RelayClient] registerToken" log. 3. Verify token sent to relay (check relay logs). |
| End-to-end happy path (click account -> approve -> auto-fill) | CODE-03 + CODE-04 + FILL-02 | Integration across 3 systems | 1. Open extension on a site with TOTP field. 2. Click matching account. 3. Approve on phone. 4. Verify code auto-fills in page field AND shows in popup with countdown. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready

---

## Validation Audit 2026-04-21

| Metric | Count |
|--------|-------|
| Gaps found | 1 |
| Resolved | 1 |
| Escalated | 0 |

**New test file:** `extension/src/entrypoints/__tests__/account-list-decryption.test.ts` (5 tests)
**Total automated tests:** 47 (42 existing + 5 new)
**All passing:** Yes
