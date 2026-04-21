---
phase: 08-core-extension-flow
plan: 01
subsystem: extension-foundation
tags: [types, storage, domain-matching, tdd]
dependency_graph:
  requires: []
  provides: [AccountMetadata, CodeRequest.domain, saveAccounts, loadAccounts, clearAccounts, domainMatchesIssuer, sortAccountsByDomain]
  affects: [extension/src/lib/types.ts, extension/src/lib/storage.ts]
tech_stack:
  added: []
  patterns: [TDD red-green, iOS-parity string-contains matching, session-only storage]
key_files:
  created:
    - extension/src/lib/domain-match.ts
    - extension/src/lib/__tests__/domain-match.test.ts
  modified:
    - extension/src/lib/types.ts
    - extension/src/lib/storage.ts
decisions:
  - Domain matching uses TLD stripping for .com/.org/.io/.net/.dev/.app/.co (extends iOS .com-only)
  - Account storage uses chrome.storage.session (cleared on browser close, per D-01)
metrics:
  duration: 2m
  completed: "2026-04-21T13:08:18Z"
  tasks_completed: 2
  tasks_total: 2
  test_count: 11
  test_pass: 11
---

# Phase 8 Plan 01: Foundation Types and Domain Matching Summary

AccountMetadata type, CodeRequest.domain field, session storage helpers, and domain matching utility with iOS-parity string-contains logic -- all with 11 passing tests.

## Task Results

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add AccountMetadata type, extend CodeRequest, add storage helpers | 9073c5a | types.ts, storage.ts |
| 2 (RED) | Failing tests for domain matching | 6256bff | __tests__/domain-match.test.ts |
| 2 (GREEN) | Implement domain matching utility | 96e0b38 | domain-match.ts |

## TDD Gate Compliance

- RED gate: `test(08-01)` commit 6256bff -- tests fail (module not found)
- GREEN gate: `feat(08-01)` commit 96e0b38 -- all 11 tests pass
- REFACTOR gate: not needed (implementation clean on first pass)

## What Was Built

### Types (extension/src/lib/types.ts)
- `AccountMetadata` interface: id, issuer, label fields for cross-component account representation
- `CodeRequest.domain` field: carries current tab hostname for domain matching (mirrors iOS CodeRequest)

### Storage (extension/src/lib/storage.ts)
- `saveAccounts(accounts)`: stores array in chrome.storage.session under "accounts" key
- `loadAccounts()`: retrieves from session storage, returns [] if missing
- `clearAccounts()`: removes "accounts" key from session storage
- Import updated to include AccountMetadata

### Domain Matching (extension/src/lib/domain-match.ts)
- `domainMatchesIssuer(domain, issuer)`: case-insensitive string-contains matching mirroring iOS CodeApprovalView.swift logic
- `sortAccountsByDomain(accounts, domain)`: stable sort putting domain-matched accounts first
- TLD stripping extended beyond iOS (.com) to include .org, .io, .net, .dev, .app, .co
- www prefix stripping for cleaner base domain extraction

### Tests (extension/src/lib/__tests__/domain-match.test.ts)
- 8 tests for domainMatchesIssuer: match, no-match, empty inputs, subdomain, TLD, www prefix
- 3 tests for sortAccountsByDomain: matched-first, order-preserved, empty-domain
- 60 lines total (exceeds 40-line minimum)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Enhancement] Extended TLD stripping beyond iOS .com-only**
- **Found during:** Task 2
- **Issue:** iOS only strips .com, but extension users visit .io, .dev, .app domains regularly
- **Fix:** Added .org, .io, .net, .dev, .app, .co to TLD strip regex
- **Files modified:** extension/src/lib/domain-match.ts
- **Commit:** 96e0b38

## Known Stubs

None -- all functions are fully implemented with real logic.

## Verification

- All 11 vitest tests pass (exit code 0)
- AccountMetadata exported from types.ts
- CodeRequest has domain field
- 3 account storage functions exported from storage.ts
- domainMatchesIssuer('github.com', 'GitHub') returns true (iOS parity confirmed)
- domainMatchesIssuer('accounts.google.com', 'Google') returns true (iOS parity confirmed)

## Self-Check: PASSED

All 4 created/modified files exist. All 3 commits verified in git log.
