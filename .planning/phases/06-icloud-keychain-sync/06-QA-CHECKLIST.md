---
phase: 06-icloud-keychain-sync
document: manual-qa-checklist
status: draft
---

# Phase 6 — Two-Device Manual QA Checklist

> Phase-gate verification. Execute ALL 8 tests on two real devices signed into the same Apple ID with iCloud Keychain enabled.
> One tester per run. Record results below before marking the phase complete in ROADMAP.md.

## How to run the automated suite first

Before starting manual QA, confirm the automated suite is green. The `KeyAuth` Xcode scheme has `KeyAuthTests` wired as a TestableReference — no separate test scheme is needed.

```
xcodebuild test \
  -project KeyAuth.xcodeproj \
  -scheme KeyAuth \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.4' \
  -only-testing:KeyAuthTests
```

Suite must end at 62+ green with at most 1 documented `XCTSkip` (simulator-sandbox static-source grep). If the suite fails, STOP — do not proceed to manual QA.

## Run Record

| Field | Value |
|-------|-------|
| Tester name | _______________________________ |
| Run date | _______________________________ |
| Device A — model | _______________________________ |
| Device A — iOS version | _______________________________ |
| Device B — model | _______________________________ |
| Device B — iOS version | _______________________________ |
| Apple ID (last 4 of email) | _______________________________ |
| iCloud Keychain enabled on both? | [ ] Yes |
| Network conditions | _______________________________ |

## Setup Preconditions

- [ ] Both devices run the same build of KeyAuth (commit SHA: _______________)
- [ ] Both devices signed into the same Apple ID
- [ ] iOS Settings → Apple ID → iCloud → Passwords & Keychain: ON on both
- [ ] Fresh install on Device B (or Device B's KeyAuth data cleared)
- [ ] Stable Wi-Fi on both
- [ ] Automated suite is green (see "How to run the automated suite first" above)

---

## Test 2-DEV-01: Basic account propagation (SC-1, ICLOUD-01/02/10/11)

**Preconditions:**
- Both devices signed into same Apple ID, iCloud Keychain ON.
- KeyAuth installed on both. Device A has no existing accounts (or empty list).

**Steps:**
1. Device A: Open KeyAuth → Settings → enable "Sync with iCloud Keychain" toggle
2. Device A: Add a test account "test-alpha" (any valid Base32 secret, e.g. `JBSWY3DPEHPK3PXP`)
3. Wait up to 5 minutes (typical iCloud Keychain propagation)
4. Device B: Open KeyAuth → observe accounts list
5. Device B: Switch to the KeyAuth keyboard in any text field (Notes app, Messages) → observe "test-alpha" TOTP code appears

**Expected:**
- Device B shows "test-alpha" in the accounts list without any user action
- Device B's keyboard extension displays the TOTP code for "test-alpha" when activated

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-02: Migration with dedup (SC-3, ICLOUD-07/08)

**Preconditions:**
- Device A: Sync OFF. No prior sync state.
- Device B: Sync ON from a prior install. Has accounts "bank" and "email" synced.

**Steps:**
1. Device A: Sync OFF. Add accounts "bank" and "email" locally with IDENTICAL issuer/label/secret to what Device B already has synced
2. Device A: Open Settings → flip "Sync with iCloud Keychain" toggle ON
3. Observe Device A immediately after toggle flip
4. Wait 5 minutes
5. Device B: Observe accounts list

**Expected:**
- Device A shows "Merged 2 duplicate accounts" toast (green checkmark, 3s dismiss) — or equivalent toast copy from `TransientToastOverlay`
- Device A's account count is 2 (not 4)
- Device B's account list remains unchanged (still 2)

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-03: Stop syncing this device (SC-4, ICLOUD-06, D-06)

**Preconditions:**
- Device A and B both have sync ON with 3 identical synced accounts ("bank", "email", "github").

**Steps:**
1. Device A: Settings → flip sync toggle OFF
2. Confirmation dialog appears → pick "Stop syncing this device" (default button)
3. Device A: Verify all 3 accounts still visible
4. Device A: Add account "local-only"
5. Wait 5 minutes
6. Device B: Check accounts list
7. Device A: Delete "bank" account
8. Wait 5 minutes
9. Device B: Check if "bank" still present

**Expected:**
- Step 2: Dialog shows two buttons: "Stop syncing this device" (default) and "Remove from iCloud on all devices" (red/destructive)
- Step 3: Device A keeps the 3 accounts
- Step 6: Device B does NOT see "local-only" (Device A's adds are now local-only)
- Step 9: "bank" is STILL PRESENT on Device B (Device A's delete was local-only, did not propagate)

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-04: Remove from iCloud on all devices (SC-4, ICLOUD-09, D-05)

**Preconditions:**
- Device A and B both have sync ON with 3 accounts.

**Steps:**
1. Device A: Settings → flip sync toggle OFF
2. Confirmation dialog appears → pick "Remove from iCloud on all devices" (destructive button)
3. Device A: Observe accounts list and toggle state immediately
4. Device A: Attempt to re-enable the sync toggle within 10 seconds
5. Wait 5-10 minutes
6. Device B: Observe accounts list
7. Device A: Wait 10s after step 2, then re-enable sync toggle
8. Wait 5 minutes
9. Device B: Observe accounts list again

**Expected:**
- Step 3: Device A's sync toggle shows OFF; accounts list on Device A unchanged (D-05 copy says "Accounts on this iPhone stay")
- Step 4: Toggle is DISABLED / cannot be re-enabled (10-second cooldown per MigrationCoordinator.toggleCooldownUntil)
- Step 6: Device B's accounts list becomes empty (or strictly smaller)
- Step 7: Toggle can be re-enabled after the 10s cooldown
- Step 9: Device B re-receives the 3 accounts via fresh sync

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-05: Fresh-install restore (SC-1, ICLOUD-16, D-09)

**Preconditions:**
- Device A has 5 accounts synced.
- Device B: KeyAuth is uninstalled.

**Steps:**
1. Device B: Reinstall KeyAuth from TestFlight / Xcode / App Store
2. Device B: Open the app
3. Observe first-launch UI

**Expected:**
- Device B shows "Restoring your accounts from iCloud…" state (ellipsis character `…`, not three dots) for up to 30 seconds (production default; unit-tested via `RestoringStateTests.testTimeoutTransition`)
- Within 30s (typical) OR after closing/reopening the app: Device B shows all 5 accounts
- If 30s passes with no accounts arriving: Device B falls through to "No accounts yet" empty state (not stuck on spinner)

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________
**Observed restore time:** _______ seconds

---

## Test 2-DEV-06: Mid-session external change (SC-1, ICLOUD-11)

**Preconditions:**
- Device A: KeyAuth foregrounded, sync ON, 3 accounts visible.
- Device B: sync ON with same 3 accounts.

**Steps:**
1. Device A: Ensure KeyAuth is in foreground, accounts list visible
2. Device B: Add a 4th account
3. On Device A, WITHOUT user action (do not background/foreground), wait up to 60 seconds
4. Observe Device A's accounts list

**Expected:**
- Device A's list updates to include the 4th account (via `NSUbiquitousKeyValueStore.didChangeExternallyNotification` observer → coalesced reload)
- No manual refresh needed

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-07: iCloud Keychain OFF at OS level (SC-2, ICLOUD-14, D-11)

**Preconditions:**
- Device A: KeyAuth installed.

**Steps:**
1. Device A: iOS Settings → [Apple ID at top] → iCloud → Passwords & Keychain → toggle OFF (accept any warning dialog)
2. Launch KeyAuth → tap Settings gear

**Expected:**
- Sync toggle is visible but DISABLED (grayed out, non-interactive)
- Inline footer shows: "iCloud Keychain is turned off on this device."
- "Open iOS Settings" button is present and functional; tapping it opens the iOS Settings app

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Test 2-DEV-08: Mid-session iCloud sign-out (SC-4, ICLOUD-15, D-12)

**Preconditions:**
- Device A: KeyAuth open, sync ON, accounts visible.

**Steps:**
1. Device A: KeyAuth open, sync toggle ON, accounts list showing
2. WITHOUT closing KeyAuth, switch to iOS Settings → tap Apple ID (top of list) → Sign Out
3. Return to KeyAuth (via app switcher or Home)

**Expected:**
- Sync toggle auto-flips to OFF
- Inline footer swaps to: "iCloud Keychain was disabled — sync stopped." (note the em dash `—`, not hyphen)
- Accounts list remains VISIBLE (cached locally; not wiped)
- No modal, no alert, no force-quit prompt appears

**Result:** [ ] PASS [ ] FAIL
**Notes:** _______________________________________

---

## Overall Phase Gate

| Requirement | Status |
|-------------|--------|
| All 8 tests PASS | [ ] Yes [ ] No |
| Tester signature | _______________________________ |
| Date | _______________________________ |
| ROADMAP Phase 6 can be marked complete | [ ] Yes [ ] No |

If any test fails, file an issue in `.planning/STATE.md` under Blockers/Concerns and DO NOT mark Phase 6 complete in ROADMAP.md.

## Success Criteria Cross-Reference

| Success Criterion | Tests Gating It |
|-------------------|-----------------|
| SC-1 Cross-device sync propagation works | 2-DEV-01, 2-DEV-05, 2-DEV-06 |
| SC-2 iCloud-unavailable path is honest (no lying toggle) | 2-DEV-07 |
| SC-3 Migration + dedup does not duplicate accounts | 2-DEV-02 |
| SC-4 User can stop syncing without losing local data | 2-DEV-03, 2-DEV-04, 2-DEV-08 |
| SC-5 Keyboard extension sees synced accounts | 2-DEV-01 step 5 (keyboard activation check) |
| SC-6 Per-device pairings do NOT sync | Side-observe during 2-DEV-03 — pairings from Device A should NOT appear on Device B |
