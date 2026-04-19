# Phase 7 QA Checklist

**Created:** 2026-04-19
**Scope:** Manual QA items not covered by automated tests. Owner: solo developer (Yashesh).

## 2-DEV-TW-01 — Toast visible above ContentView after sheet dismisses (FIDO-18)

**Preconditions:**
- Physical iPhone with FaceID enabled OR iOS Simulator with "Matching Face" toggled ON
- Chrome extension paired (Phase 1-3 flow complete)
- Phase 7 toggle is ON (default — verify by opening Settings and confirming "Allow 2-minute trust window after FaceID" shows ON)

**Steps:**
1. From Chrome extension, click "Request Code" for a paired account.
2. iOS app foregrounds, `CodeApprovalView` sheet appears.
3. Tap "Approve" — confirm FaceID succeeds (simulator: Features → Face ID → Matching Face).
4. Sheet auto-dismisses after ~1.5s. Note the time on a stopwatch.
5. WITHIN 2 MINUTES of step 3, request a second code from Chrome extension.
6. Observe: NO FaceID prompt appears; a toast capsule reading "Code sent for <issuer>" appears at the top of ContentView, above the safe-area notch, and fades out after ~2 seconds.

**Pass criteria:**
- [ ] Step 4 — first request goes through FaceID flow
- [ ] Step 6 — second request is silent (no FaceID prompt, no sheet)
- [ ] Step 6 — toast is visible above ContentView, with paperplane icon, readable in both Light and Dark mode
- [ ] Toast auto-dismisses in approximately 2 seconds

**Fail signals:**
- Second request still prompts FaceID → Plan 07-06 resolver wiring is broken OR Plan 07-03 `isInWindow` gate is broken
- Toast never appears → Plan 07-07 overlay is misattached OR `TrustWindowManager.pendingToast` is not wired
- Toast appears but covered by the sheet → Plan 07-07 overlay is applied below the `.sheet` level (should be at the same level)

## 2-DEV-TW-02 — Chrome extension source unchanged (FIDO-19)

**Preconditions:**
- Phase 7 branch checked out locally
- `main` branch represents pre-Phase-7 state

**Steps:**
1. Run: `git diff main...HEAD -- extension/`
2. Observe the output.

**Pass criteria:**
- [ ] The diff output is empty (zero lines of change under `extension/`)

**Fail signals:**
- Any file under `extension/` was modified — Phase 7 is iOS-only per CONTEXT.md D-15. Revert those changes before merging.

## 2-DEV-TW-03 (optional) — Settings toggle flips preference without dialog

**Preconditions:**
- Phase 7 Settings surface deployed

**Steps:**
1. Open Settings.
2. Observe "Security" section with "Allow 2-minute trust window after FaceID" toggle.
3. Flip OFF.
4. Navigate back to main screen and then back to Settings — confirm toggle is still OFF.
5. Flip ON. Confirm it persists.

**Pass criteria:**
- [ ] No confirmation dialog on flip (unlike Phase 6 Sync toggle OFF which DOES prompt)
- [ ] State persists across navigation and app re-launch

**Notes:** This is documented as covered by `testSetEnabledPersistsInUserDefaults` at the unit level; this manual walkthrough is belt-and-suspenders for UI behavior (no dialog).
