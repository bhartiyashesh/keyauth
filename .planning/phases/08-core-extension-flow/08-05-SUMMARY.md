---
phase: 08-core-extension-flow
plan: 05
subsystem: chrome-extension
tags: [content-script, totp-detection, auto-fill, tdd]
dependency_graph:
  requires: [08-03]
  provides: [FILL-01, FILL-02]
  affects: [extension/src/entrypoints/background.ts]
tech_stack:
  added: [jsdom]
  patterns: [3-layer-heuristic-detection, native-value-setter, wxt-content-script]
key_files:
  created:
    - extension/src/entrypoints/content.ts
    - extension/src/entrypoints/content-utils.ts
    - extension/src/entrypoints/__tests__/content.test.ts
  modified:
    - extension/package.json
    - extension/package-lock.json
decisions:
  - Used prototype chain walk for native value setter instead of global HTMLInputElement reference for jsdom compatibility
  - Used ownerDocument.defaultView.Event constructor for cross-context event dispatch
metrics:
  duration: 166s
  completed: 2026-04-21T13:21:18Z
  tasks: 1/1
  files_created: 3
  files_modified: 2
  test_count: 14
---

# Phase 08 Plan 05: Content Script TOTP Detection and Auto-Fill Summary

Content script with 3-layer TOTP field detection heuristics (autocomplete, name/id keywords, maxlength+submit proximity) and split-input handling for 6-digit OTP containers, using native value setter with event dispatch for React/Angular framework compatibility.

## Task Completion

| Task | Name | Type | Commit | Status |
|------|------|------|--------|--------|
| 1 | Create content script with TOTP detection and fill logic | auto (tdd) | 58b7953, a0954e0 | Done |

## TDD Gate Compliance

- RED gate: 58b7953 (test commit, 14 tests failing -- module not found)
- GREEN gate: a0954e0 (feat commit, 14 tests passing)
- REFACTOR gate: not needed -- code clean on first pass

## What Was Built

### content-utils.ts (Pure Detection + Fill Logic)
- `detectTOTPField(doc)`: 3-layer heuristic detection per D-04
  - Layer 1: `autocomplete="one-time-code"` (W3C standard, most reliable)
  - Layer 2: input name/id/placeholder containing otp, totp, 2fa, verification, code
  - Layer 3: maxlength=6 input inside a form with a submit button
  - Excludes password, hidden, and email input types
- `detectSplitInputs(doc)`: Finds 6 adjacent maxlength=1 inputs per D-06
  - Checks for OTP-related container class/id (otp, code, pin, verify)
  - Falls back to same-parent detection
- `attemptFill(doc, code)`: Orchestrates fill -- tries split inputs first, then single field
  - Returns boolean for service worker response
- Native value setter via prototype chain walk for React/Angular/Vue compatibility
- Event dispatch using ownerDocument.defaultView.Event for cross-context compatibility

### content.ts (WXT Entrypoint)
- `defineContentScript` with `matches: ['*://*/*']`, `runAt: 'document_idle'`
- Passive listener only (D-05 compliance) -- no proactive DOM scanning
- Responds to `fill_code` messages from service worker with `{ filled: boolean }`
- Context invalidation cleanup handler

### Test Coverage (14 tests)
- 7 detectTOTPField tests (all 3 layers + exclusions)
- 4 detectSplitInputs tests (valid containers, insufficient inputs, no inputs)
- 3 attemptFill integration tests (single fill, split fill, no field)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] HTMLInputElement not available in vitest global scope**
- **Found during:** Task 1 GREEN phase
- **Issue:** `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')` throws ReferenceError because vitest runs outside jsdom window context
- **Fix:** Replaced with prototype chain walk using `Object.getPrototypeOf(input)` to find native value setter from the element's own prototype hierarchy
- **Files modified:** extension/src/entrypoints/content-utils.ts
- **Commit:** a0954e0

**2. [Rule 1 - Bug] Event constructor mismatch between vitest and jsdom contexts**
- **Found during:** Task 1 GREEN phase
- **Issue:** `new Event('input')` from vitest global scope is not accepted by jsdom's `dispatchEvent` which expects its own Event type
- **Fix:** Used `input.ownerDocument.defaultView?.Event ?? Event` to get the Event constructor from the element's own window context
- **Files modified:** extension/src/entrypoints/content-utils.ts
- **Commit:** a0954e0

## Verification Results

- All 14 vitest tests pass (exit code 0)
- `defineContentScript` pattern confirmed in content.ts
- `fill_code` message handler confirmed in content.ts
- Test file exceeds 60 line minimum (163 lines)
- Content script at correct WXT path for auto-registration

## Self-Check: PASSED
