# Phase 6: iCloud Keychain Sync - Research

**Researched:** 2026-04-18
**Domain:** iOS Keychain Services (`kSecAttrSynchronizable`), iCloud Key-Value Store change notifications, Keychain access groups + entitlements, SwiftUI scene lifecycle, App Store Review Guideline 5.1.1
**Confidence:** HIGH on API mechanics / Keychain semantics; MEDIUM on sync propagation timing; LOW on iCloud Keychain OS-state detection (no public API exists)

## Summary

Phase 6 adds a sync scope to an already well-structured Keychain layer. The core technical insight is that `kSecAttrSynchronizable` is an **attribute that contributes to uniqueness** on a Keychain item — so a synced copy (`synchronizable=true`) and a local copy (`synchronizable=false`) of the same service+account pair can coexist, and every read / write / delete query MUST be explicit about which variant it targets (`true`, `false`, or `kSecAttrSynchronizableAny`). Getting this wrong is the single most common source of "invisible data" bugs in this domain [CITED: developer.apple.com forums thread/68843].

Phase 6 is a surprisingly tight fit for the existing codebase: `KeychainManager` is the single CRUD surface, `AccountStore.reload()` already rewrites `SharedDefaults` on every mutation (so the keyboard extension propagation chain already works end-to-end for iCloud pushes — no keyboard code changes needed). The missing pieces are:

1. A `SyncPreference` helper (reads a boolean from standard `UserDefaults` — NOT `NSUbiquitousKeyValueStore`, NOT Keychain — because the preference is per-device UX state)
2. Threading `kSecAttrSynchronizable` into all `KeychainManager` operations, with `kSecAttrSynchronizableAny` on every read/delete so both variants are found
3. An `accounts-version` counter in `NSUbiquitousKeyValueStore` as the cross-device "something changed" ping (works around the fact that the Keychain has no native change notification)
4. A new Settings surface, migration flow, dedup, and "Restoring…" empty state (all covered by the approved UI-SPEC)

The iOS minimum version question resolves cleanly: `kSecAttrSynchronizable` has been available since iOS 7.0.3 (reintroduced after the iOS 7.0 GM pull), `NSUbiquitousKeyValueStore` since iOS 5, and the project currently builds at `IPHONEOS_DEPLOYMENT_TARGET = 16.0` while UI-SPEC claims iOS 17+ — this mismatch is flagged as an open question but the simplest fix is to bump the deployment target to 17.0 since nothing in the existing code pre-dates iOS 17.

There is **no public API** to detect whether iCloud Keychain is enabled at the OS level. Apple's DTS engineer Quinn "The Eskimo!" confirmed in a 2016 thread that `SecItemAdd` with `kSecAttrSynchronizable=true` succeeds even when iCloud Keychain is disabled — the item is just never sent to the cloud [CITED: developer.apple.com forums thread/30699]. The honest answer for D-11 is not heuristic detection but **user-visible messaging plus proactive UX recovery**: if sync was ON and nothing propagates across a reasonable window, the app's behavior is still correct locally; if the user turns it OFF in iOS Settings mid-session, we'll observe the loss of `NSUbiquitousKeyValueStore` updates and can surface the D-12 inline copy. Deep-link to Settings is the correct recovery affordance, not a real-time detection loop.

**Primary recommendation:** Build a protocol-fronted `KeychainManager` so sync-attribute branching logic is unit-testable against a fake, keep the CRUD API shape identical but add a `synchronizable: Bool` parameter to `save`, migrate by re-saving as synchronizable then deleting the non-sync copy (in that order — see Migration Strategy), and use `NSUbiquitousKeyValueStore` purely as a change-ping counter, not as a data store.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Default Behavior & Onboarding:**
- **D-01:** NEW users default to `sync = ON`. First launch shows a one-time dismissible card above the empty accounts list explaining iCloud sync in plain language. Manageable in Settings.
- **D-02:** EXISTING users default to `sync = OFF` (preserve current behavior). No unsolicited prompt, banner, or modal. Discoverable via Settings only.
- **D-03:** Disclosure tone is plain-language and trust-focused. Example voice: *"Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."* Avoid jargon (E2E, CryptoKit) in the primary copy; jargon can live in an optional "How is this secured?" expandable.
- **D-04:** Disclosure copy lives inline directly under the toggle in Settings. Same copy reused verbatim on the new-user first-launch card for consistency.

**Disable Flow:**
- **D-05:** Turning the toggle OFF opens a confirmation sheet with two explicit choices:
  - **Stop syncing this device** — this device reverts to local-only, iCloud copy and other devices unaffected.
  - **Remove from iCloud on all devices** — destructive; purges synced items from iCloud, which propagates removal to every other signed-in device.
- **D-06:** When user picks "Stop syncing this device," local copies of all accounts are preserved on the current device (re-saved as non-synchronizable). Edits after that point stay local on this device.

**Migration:**
- **D-07:** Existing local-only accounts migrate to sync via a silent bulk migration when the user flips the toggle ON. No per-account confirmation. Progress indicator if total count > 10. Migration is: load each account, re-save with `kSecAttrSynchronizable: true`, delete the original non-sync record. One atomic op per account.
- **D-08:** Auto-dedup on first sync when accounts collide. Dedup key: `(issuer, label, secret)` — all three must match. Keeps the account with the earliest `createdAt`. One-time toast after migration: "Merged N duplicate accounts." Silent below the fold if N == 0.

**Multi-device & State:**
- **D-09:** Fresh install on a second device signed into the same iCloud shows a dedicated "Restoring your accounts from iCloud…" empty state with spinner. Falls back to the normal empty state if nothing arrives within ~30 seconds (tunable).
- **D-10:** In-session refresh uses two signals:
  - Reload accounts whenever the app becomes active (SwiftUI `.onChange(of: scenePhase)` or `UIApplication.didBecomeActiveNotification`).
  - On every `KeychainManager.save`, bump an `accounts-version` counter in `NSUbiquitousKeyValueStore`. Observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` — when the counter moves, trigger `AccountStore.reload()`. This covers mid-session updates from other devices.
- **D-11:** When iCloud Keychain is disabled at the OS level, the sync toggle is visible but disabled/grayed out with inline copy: "iCloud Keychain is turned off on this device." Provides a deep-link button to iOS Settings (`UIApplication.openSettingsURLString`).
- **D-12:** Mid-session iCloud sign-out handling: accounts stay visible (keychain cache), the toggle flips to OFF automatically, inline state flag shows "iCloud Keychain was disabled — sync stopped." No modals, no force-quit prompts.

**Sync Scope:**
- **D-13 (Claude's discretion):** Global sync toggle, not per-account. Scope of what syncs is ONLY `Account` records (TOTP secrets + metadata). Everything else stays local: `PairingStore`, `CryptoBoxManager` identity keys, APNs device token, biometric lock preference, sort order (see D-14).
- **D-14 (Claude's discretion):** Sort order (`Account.sortOrder`) syncs because it's part of the `Account` Codable payload. Reorder on one device propagates to others.

### Claude's Discretion

- **Settings screen architecture:** Already resolved by the approved UI-SPEC — gear button in toolbar, `NavigationLink` push.
- **Keyboard extension cache invalidation:** Accept propagation lag of ≤ one keyboard reactivation cycle after main-app reload. No keyboard-side changes needed.
- **Migration atomicity:** Recommend: log error, continue with remaining accounts, surface total count + failed count in a toast (matches UI-SPEC error copy).
- **Testing strategy:** Researcher investigates unit-testable paths (see Validation Architecture).

### Deferred Ideas (OUT OF SCOPE)

- **Per-account sync granularity** — global toggle only in v1.
- **Review screen for duplicates** — auto-dedup silently per D-08.
- **Backup codes / recovery codes** — separate security feature.
- **CloudKit-based sync** — iCloud Keychain is sufficient; revisit only if CloudKit offers a compelling capability.
- **Re-pair-on-new-device flow** — pairings correctly don't sync; separate UX phase.
- **PROJECT.md Core Value rewording** — owner decision, not a phase task.

</user_constraints>

<phase_requirements>

## Phase Requirements

**Status:** No formal requirement IDs exist yet for Phase 6. The ROADMAP.md entry says "Requirements: TBD." This research proposes new IDs in the `ICLOUD-NN` namespace (see § Proposed Requirements IDs below). The planner should formalize these in REQUIREMENTS.md as the first planner step.

**Mapping from ROADMAP.md success criteria to proposed IDs:**

| Success Criterion (ROADMAP phase 6) | Proposed ID | Research Support |
|-------------------------------------|-------------|------------------|
| SC-1: Accounts added on device A appear on device B within typical iCloud Keychain propagation time | ICLOUD-01 (sync save path), ICLOUD-02 (read both variants), ICLOUD-10 (scenePhase refresh), ICLOUD-11 (KVS change observer) | § Apple Platform Mechanics, § In-Session Refresh Architecture |
| SC-2: Clear disclosure before enabling + toggle off anytime | ICLOUD-04 (Settings surface), ICLOUD-05 (first-launch card), ICLOUD-06 (disable confirmation) | UI-SPEC + § App Store Review 5.1.1 Compliance |
| SC-3: Existing users can migrate with single confirmation, no loss, no duplicates | ICLOUD-07 (migration), ICLOUD-08 (dedup) | § Migration Strategy, § Dedup Strategy |
| SC-4: Disabling gives clear choice — per-device or remove-all | ICLOUD-06 (disable confirmation), ICLOUD-09 (destructive delete-all) | § Destructive "Remove from iCloud" Implementation |
| SC-5: Keyboard extension continues to see same accounts via App Group | ICLOUD-12 (keyboard propagation chain validation) | § Keyboard Extension Propagation |
| SC-6: Device-bound data (pairings, identity keys, APNs tokens) explicitly does NOT sync | ICLOUD-13 (sync scope isolation) | § Sync Scope (D-13, D-14 in CONTEXT.md) |

</phase_requirements>

## Project Constraints (from global CLAUDE.md)

The user's private global CLAUDE.md contains two constraints relevant to this phase:
- Never add Co-authored-by or AI/Claude mentions in git commit messages
- Never use Mermaid for diagrams — use Draw.io instead

The "no Vercel" constraint does not apply to Phase 6 (iOS-only, no hosting change).

No project-local `CLAUDE.md` exists. No `.claude/skills/` or `.agents/skills/` directory exists.

## Overview

Phase 6 extends an already-working local-only Keychain to support iCloud Keychain sync for **only the `Account` records** in `com.keyauth.accounts`. Six deliverables:

1. **`KeychainManager` extension:** `save(_:synchronizable:)`, and queries that include `kSecAttrSynchronizableAny` on every read/delete so both variants are visible
2. **`SyncPreference` helper:** a per-device boolean in standard `UserDefaults` (NOT iCloud) that gates which `synchronizable` value the save layer writes
3. **Settings surface** (`SettingsView`) plus toolbar entry from `ContentView` — already designed in UI-SPEC
4. **Migration flow:** OFF→ON bulk re-save; disable → two-path confirmation (per-device opt-out or destructive delete-all); auto-dedup
5. **"Restoring from iCloud…" empty state:** fresh-install UX with 30s timeout (tunable to 60s if QA finds it insufficient)
6. **In-session refresh:** scenePhase `.active` + `NSUbiquitousKeyValueStore.didChangeExternallyNotification` driven by an `accounts-version` counter

Nothing about the keyboard extension changes. Nothing about `PairingStore`, `CryptoBoxManager`, APNs device token handling changes — those use `kSecAttrService = "com.keyauth.pairing"` and are filtered to their own service, untouched by Phase 6's queries.

## Apple Platform Mechanics

### `kSecAttrSynchronizable` — Precise Semantics

**The critical fact:** `kSecAttrSynchronizable` contributes to Keychain item uniqueness. For `kSecClassGenericPassword`, the uniqueness tuple that drives `errSecDuplicateItem` on `SecItemAdd` is:

```
(kSecAttrAccessGroup, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable)
```

Sources: [CITED: developer.apple.com/forums/thread/68843] — Quinn "The Eskimo!" explicitly confirmed: *"`kSecAttrSynchronizable` is a uniqueness attribute … it should be included in all of those lists."* Supporting: [CITED: useyourloaf.com/blog/keychain-duplicate-item-when-adding-password/] confirms `(service, account)` for the base case; the forum correction extends the tuple for the synchronizable case.

**Consequence:** A synced and a non-synced copy of the same `(service, account)` pair can coexist simultaneously. During migration, the intermediate state is legitimate — a non-sync item and a sync item with identical `service`/`account`/`data` but different `synchronizable` values — the Keychain treats them as two separate entries. [VERIFIED: WebSearch cross-confirmed]

**Query matrix (this IS the bug prevention — get this right once, copy it to every call site):**

| Operation | `kSecAttrSynchronizable` in query | Behavior |
|-----------|-----------------------------------|----------|
| `SecItemAdd` insert | Set to `kCFBooleanTrue` OR `kCFBooleanFalse` (or omit for false) | Creates exactly one item with the specified sync attribute |
| `SecItemAdd` insert (omitted) | — | Defaults to `synchronizable=false` — item does NOT sync |
| `SecItemCopyMatching` read | Set to `kSecAttrSynchronizableAny` | Matches BOTH sync and non-sync items |
| `SecItemCopyMatching` read | Set to `kCFBooleanTrue` | Matches ONLY sync items |
| `SecItemCopyMatching` read | Omitted | Matches ONLY non-sync items (THIS IS THE BUG; omitting is NOT "any") |
| `SecItemUpdate` | Set to `kSecAttrSynchronizableAny` | Updates matching item; sync attribute on the item itself is NOT changed by update |
| `SecItemUpdate` change sync attribute | **Not supported via update** — you must delete and re-add | See Migration Strategy |
| `SecItemDelete` | Set to `kSecAttrSynchronizableAny` | Deletes BOTH sync and non-sync copies |
| `SecItemDelete` | Set to `kCFBooleanTrue` | Deletes ONLY sync copies (propagates to other devices) |
| `SecItemDelete` | Omitted | Deletes ONLY non-sync copies (local-only) |

**Compatibility with `kSecAttrAccessible`:**

[CITED: developer.apple.com/documentation/security/ksecattrsynchronizable] *"Items stored or obtained using the `kSecAttrSynchronizable` key may not also specify a `kSecAttrAccessible` value which is incompatible with syncing (namely, those whose names end with 'ThisDeviceOnly')."*

| Accessibility value | Compatible with sync? |
|---------------------|----------------------|
| `kSecAttrAccessibleWhenUnlocked` | YES |
| `kSecAttrAccessibleAfterFirstUnlock` | YES (current code — no change needed) |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | NO |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | NO |
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | NO |

The existing `KeychainManager.swift:32` uses `kSecAttrAccessibleAfterFirstUnlock` for `Account` items — already sync-compatible. No accessibility change needed for Phase 6. `PairingStore` and `CryptoBoxManager` also use `AfterFirstUnlock` but are device-bound by service-name isolation (`com.keyauth.pairing`), not by accessibility — they will NOT sync because we simply don't pass `kSecAttrSynchronizable=true` when saving them. This is correct design.

**Item class restriction:** Only `kSecClassGenericPassword` and `kSecClassInternetPassword` support sync. Certificates, keys, and identity items cannot sync. [CITED: developer.apple.com/documentation/security/ksecattrsynchronizable] — not a concern for Phase 6 (all `Account` items are `kSecClassGenericPassword`).

### Code-Level Examples

**Save with sync attribute:**

```swift
func save(_ account: Account, synchronizable: Bool) throws {
    let data = try JSONEncoder().encode(account)
    let key = account.id.uuidString
    let query = baseQuery(for: key, synchronizable: synchronizable)

    // Check if this specific (service, account, synchronizable) tuple exists
    let status = SecItemCopyMatching(query as CFDictionary, nil)

    if status == errSecSuccess {
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess else { throw KeychainError.updateFailed(updateStatus) }
    } else {
        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insertQuery[kSecAttrSynchronizable as String] = synchronizable
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw KeychainError.saveFailed(insertStatus) }
    }
}

private func baseQuery(for key: String, synchronizable: Bool) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecAttrSynchronizable as String: synchronizable
    ]
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
    return query
}
```

**Load all (both variants):**

```swift
func loadAll() throws -> [Account] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecAttrSynchronizable as String: kSecAttrSynchronizableAny  // CRITICAL
    ]
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let items = result as? [Data] else {
        if status == errSecItemNotFound { return [] }
        throw KeychainError.loadFailed(status)
    }

    let decoder = JSONDecoder()
    return items.compactMap { try? decoder.decode(Account.self, from: $0) }
        .sorted { $0.sortOrder < $1.sortOrder }
}
```

**Delete single item (both variants — used when user deletes an account from the main list):**

```swift
func delete(id: UUID) throws {
    var query = baseQuery(for: id.uuidString, synchronizable: false)
    query.removeValue(forKey: kSecAttrSynchronizable as String)
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny  // delete BOTH copies
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.deleteFailed(status)
    }
}
```

**Delete all synced copies only (destructive disable path, D-05 option 2):**

```swift
func deleteAllSynced() throws {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrSynchronizable as String: kCFBooleanTrue  // synced copies only
    ]
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.deleteFailed(status)
    }
}
```

### `NSUbiquitousKeyValueStore` — Contract and Quotas

**Purpose in Phase 6:** Not a data store. Used exclusively as a **cross-device ping** — a monotonically-incrementing `accounts-version` counter (`Int64`) that bumps on every local `save` / `delete`. Other devices observe `didChangeExternallyNotification` when the counter moves and call `AccountStore.reload()` to pull the fresh Keychain state.

**Quotas** [CITED: developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore]:
- 1 MB total per app
- 1024 keys max
- 1 MB per individual key
- Well within budget — we use ONE key storing an Int64

**Change reasons delivered in `userInfo[NSUbiquitousKeyValueStoreChangeReasonKey]`:**

| Reason constant | Raw value | Meaning | Phase 6 response |
|-----------------|-----------|---------|------------------|
| `NSUbiquitousKeyValueStoreServerChange` | 0 | Another device updated iCloud | Call `AccountStore.reload()` |
| `NSUbiquitousKeyValueStoreInitialSyncChange` | 1 | First fetch after sign-in or first launch | Call `AccountStore.reload()` (may fire "Restoring…" exit) |
| `NSUbiquitousKeyValueStoreQuotaViolationChange` | 2 | Storage quota exceeded | Cannot happen with single counter — log + ignore |
| `NSUbiquitousKeyValueStoreAccountChange` | 3 | User switched iCloud accounts | Clear local preference state, show D-12 copy |

Source: [CITED: apple.com docs, verified against opensource.apple.com Security-57740.1.18/KVSKeychainSyncingProxy/CKDKVSStore.m and matteozajac.medium.com]

**Delivery semantics — HONEST ASSESSMENT:**

- `didChangeExternallyNotification` is **not a guaranteed-delivery mechanism**. [CITED: developer.apple.com forums/727073 "Random delay in Keychain Sync" + multiple community reports] delivery is typically within 5 seconds under good network, but can take "hours or overnight" under bad conditions.
- iCloud can **coalesce** multiple rapid updates — if device A saves 10 accounts in 2 seconds, device B may see ONE notification representing the final state, not 10 notifications.
- App must call `.synchronize()` on `NSUbiquitousKeyValueStore.default` at launch to force a local fetch; this does NOT force a server pull — iCloud's own sync cadence governs that.
- This is actually **fine for Phase 6** because we're using the counter as a "something moved, come look" signal — coalescing is acceptable; we don't need to know how many changes, just that at least one occurred.

**Recommended observer pattern:**

```swift
// In AccountStore init (or KeyAuthApp)
NotificationCenter.default.addObserver(
    forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
    object: NSUbiquitousKeyValueStore.default,
    queue: .main
) { [weak self] notification in
    guard let userInfo = notification.userInfo,
          let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
    // Reload on ServerChange or InitialSyncChange (ignore quota/account)
    if reason == NSUbiquitousKeyValueStoreServerChange
        || reason == NSUbiquitousKeyValueStoreInitialSyncChange {
        self?.coalescedReload()
    } else if reason == NSUbiquitousKeyValueStoreAccountChange {
        self?.handleiCloudAccountChange()  // show D-12 copy, flip toggle to OFF
    }
}

// Bump on every local save
static func bumpAccountsVersion() {
    let store = NSUbiquitousKeyValueStore.default
    let current = store.longLong(forKey: "accounts-version")
    store.set(current + 1, forKey: "accounts-version")
    store.synchronize()
}
```

### iCloud Keychain State Detection — Honest Assessment

**There is no public API to check whether iCloud Keychain is enabled.** [CITED: developer.apple.com forums/thread/30699 and forums/thread/130776 — Quinn "The Eskimo!"] and multiple cross-referenced community sources all arrive at the same conclusion. Specifically:

- `SecItemAdd` with `kSecAttrSynchronizable=true` **succeeds silently** even when iCloud Keychain is disabled. The item simply stays local and never propagates.
- `FileManager.default.ubiquityIdentityToken` tells you whether the user is signed into iCloud (for iCloud Drive), NOT whether iCloud Keychain specifically is enabled. These are independent user-controlled toggles.
- `NSUbiquitousKeyValueStore.default.synchronize()` returning `false` hints at iCloud trouble but is not authoritative for Keychain state specifically.

**Recommended detection strategy for D-11 (iCloud Keychain OFF at OS level):**

Accept that we cannot directly detect this state. Instead, apply two complementary signals:

1. **`ubiquityIdentityToken == nil`:** user is not signed into iCloud at all. This IS detectable. In this case, show the D-11 copy "iCloud Keychain is turned off on this device" (accurate enough — iCloud itself is off, which implies iCloud Keychain is off), and disable the toggle.
2. **All other cases (signed into iCloud but Keychain state unknown):** Leave the toggle enabled. If the user enables sync and nothing propagates, it either works eventually (good) or Apple's own iOS Settings surface is where they'll learn their Keychain is off. The deep-link button to iOS Settings is the correct fallback.

**For D-12 (mid-session iCloud sign-out):** Observe `NSUbiquityIdentityDidChangeNotification`. When it fires, compare `ubiquityIdentityToken` to the previous value; if nil, flip the toggle OFF and show the D-12 copy. When the user signs back in, the token changes; the next scenePhase .active reloads state.

**Known limitation** flagged explicitly for the discuss-phase / user: **If the user signs into iCloud but has iCloud Keychain specifically disabled**, our toggle will appear enabled, sync will silently no-op, and the user will see no error — only the absence of new devices showing their accounts. This matches what every other third-party password manager experiences; it's a platform limitation, not a bug we can fix. The 30s "Restoring…" timeout with fallback to empty state (D-09) is the honest UX for this case.

### Keychain Access Group + iCloud Sync — Entitlement Audit

**Current entitlements:**

```xml
<!-- App/KeyAuth.entitlements -->
<key>aps-environment</key>
<string>development</string>
<key>com.apple.security.application-groups</key>
<array><string>group.com.keyauth.shared</string></array>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)com.keyauth.shared</string></array>

<!-- KeyboardExtension/KeyAuthKeyboard.entitlements — identical minus aps-environment -->
```

**Verdict:** `keychain-access-groups` is present and correctly set to `$(AppIdentifierPrefix)com.keyauth.shared` (which expands to `W646UCTVQV.com.keyauth.shared`). This is **sufficient for iCloud Keychain sync** — no additional entitlement is required.

[CITED: developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups and developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps] Access group items sync correctly when `kSecAttrSynchronizable=true` is set on save. The same Team ID must appear on all devices (guaranteed by same Apple ID + same App Store app).

**No separate "iCloud" entitlement is required.** iCloud Keychain sync is gated by:
1. App has `keychain-access-groups` entitlement (present ✓)
2. User has iCloud Keychain enabled in iOS Settings (user-controlled, cannot verify)
3. `kSecAttrSynchronizable=true` on save (what Phase 6 adds)

**Keyboard extension note:** The keyboard target's entitlements are identical for `keychain-access-groups`, but the keyboard does NOT call Keychain APIs — it reads from `SharedDefaults` (App Group UserDefaults). So the keyboard doesn't need iCloud awareness; it reads whatever JSON the main app wrote to `group.com.keyauth.shared`. This chain is already complete for local accounts; it will be complete for synced accounts the moment `AccountStore.reload()` fires from the KVS observer and writes the updated array to `SharedDefaults`. See § Keyboard Extension Propagation.

### iOS Version Requirements

| API | Min iOS | Notes |
|-----|---------|-------|
| `kSecAttrSynchronizable` | iOS 7.0.3 | [CITED: apple.com docs; iOS 7.0 GM temporarily pulled it, restored in 7.0.3] |
| `kSecAttrSynchronizableAny` | iOS 7.0.3 | Same availability as the above |
| `NSUbiquitousKeyValueStore` | iOS 5.0 | [CITED: apple.com docs] |
| `NSUbiquitousKeyValueStore.didChangeExternallyNotification` | iOS 5.0 | Same availability |
| `FileManager.default.ubiquityIdentityToken` | iOS 6.0 | [CITED: apple.com docs] |
| `NSUbiquityIdentityDidChangeNotification` | iOS 6.0 | Same availability |
| `ScenePhase` (SwiftUI) | iOS 14.0 | Current code uses SwiftUI; compatible |

**Current project state:** `IPHONEOS_DEPLOYMENT_TARGET = 16.0` (verified in `KeyAuth.xcodeproj/project.pbxproj`), but the approved UI-SPEC specifies `min_deployment: iOS 17+`. This is an inconsistency — neither Phase 6 requirements nor the UI-SPEC's SwiftUI usage strictly require iOS 17, but bumping the target to 17 is trivial and matches the UI-SPEC frontmatter. **Recommendation:** planner decides whether to bump the target to iOS 17.0 (easier — matches UI-SPEC, no downside since current userbase is assumed to be on recent iOS) or keep iOS 16 (requires correcting the UI-SPEC frontmatter). All Phase 6 APIs work on both.

## Migration Strategy

### The Core Algorithm

Per D-07: silent bulk migration when user flips toggle OFF→ON. Load each account, re-save as synchronizable, delete the original non-sync record. **Per account is atomic in the success case; partial failure continues (per CONTEXT.md Claude's discretion)**.

**Safe ordering:** **re-save as synchronizable FIRST, then delete the non-sync copy.** Rationale:

- **Failure mode A** (save-sync succeeds, delete-non-sync fails): Two copies of the same account exist — one synced, one local. `loadAll()` with `kSecAttrSynchronizableAny` returns both, `JSONDecoder` decodes both into identical `Account` values (same UUID). The deduplication pass (see § Dedup Strategy) collapses these into one. No user-visible harm.
- **Failure mode B** (save-sync fails, delete-non-sync fails): Nothing happened — account still exists as non-sync. Retry next time.
- **Failure mode C** (delete-non-sync-FIRST then save-sync fails): Account is **lost** — this is the catastrophic ordering. Never do this.

**`errSecDuplicateItem` handling:** The first time a device migrates, `SecItemAdd` with `synchronizable=true` will succeed because no synced copy exists. If the migration runs again (user toggles OFF then ON with a device already having synced copies from another device), `SecItemAdd` may return `errSecDuplicateItem` for accounts where a synced copy already exists from another device. **The handling:** catch `errSecDuplicateItem` specifically, fall through to `SecItemUpdate` on the existing synced item, then proceed to delete the non-sync copy. The existing `KeychainManager.save` already has this pattern (check via `SecItemCopyMatching` first) — with the `synchronizable` parameter threaded through, this works correctly.

### Partial-Failure Recovery

Per CONTEXT.md Claude's discretion + UI-SPEC error copy:

- Track `(done, total, failed)` during migration.
- On per-account failure: log the error, continue with next account, do NOT roll back already-migrated accounts.
- After all accounts processed: if `failed == 0`, show no toast (or the "Merged N duplicates" toast if dedup happened); if `failed > 0`, show: `"Moved {ok} accounts. {failed} couldn't be moved — try again in Settings."`
- Settings shows a "Retry migration" row when `failed > 0` — this re-runs the bulk migration only on items that are still non-sync (the successful items are already sync, so they're filtered out).

### Migration Pseudocode

```swift
@MainActor
func migrateAllToSync() async -> (ok: Int, failed: Int, deduped: Int) {
    var ok = 0, failed = 0, deduped = 0

    // Load ALL accounts (both sync and non-sync variants)
    let allAccounts = try keychain.loadAllIncludingVariants()  // returns [(Account, Bool isSync)]
    let nonSyncAccounts = allAccounts.filter { !$0.isSync }

    for (account, _) in nonSyncAccounts {
        do {
            // Step 1: re-save as synchronizable (may hit errSecDuplicateItem if synced copy exists)
            try keychain.save(account, synchronizable: true)
            ok += 1

            // Step 2: delete the non-sync copy (explicit synchronizable=false query)
            try keychain.deleteNonSyncOnly(id: account.id)

            // Progress update if > 10 total
            await MainActor.run { migrationProgress.done = ok }
        } catch {
            failed += 1
            Logger.warn("Migration failed for \(account.id): \(error)")
        }
    }

    // After migration: run dedup pass
    deduped = try await AccountStore.shared.dedupSyncedAccounts()

    SyncPreference.setEnabled(true)  // only set AFTER migration completes
    AccountStore.shared.reload()
    return (ok, failed, deduped)
}
```

**Toggle-during-migration:** Per UI-SPEC, the toggle is `.disabled(true)` during migration to prevent concurrent toggle. This is the correct UX and avoids a whole class of reentrancy bugs.

### Reverse Migration (D-06 "Stop syncing this device")

Same algorithm in reverse — for each synced account, re-save as `synchronizable=false` first, then delete the `synchronizable=true` copy.

**Critical subtlety about D-06:** When you delete the synced copy on this device with an explicit `synchronizable=true` query, iCloud **will propagate that deletion to other devices**. This is NOT what D-06 wants — D-06 wants other devices to keep their copies. **The correct implementation is different:** do NOT delete the synced copy via a `synchronizable=true` delete query. Instead:

**Correct D-06 algorithm (locally-scoped detach):**

```swift
for account in syncedAccounts {
    // Step 1: save as non-sync (creates local copy on this device)
    try keychain.save(account, synchronizable: false)
    // Step 2: do NOT delete the synced copy — it belongs to iCloud, shared with other devices
}
SyncPreference.setEnabled(false)
```

After step 1, there are two copies on this device: one synced, one non-sync. `loadAll()` with `SynchronizableAny` will return both, dedup collapses them. On subsequent saves (with `SyncPreference.enabled=false`), we only write the non-sync variant. The synced copy on THIS device continues to be updated from other devices (iCloud doesn't care that the user turned our toggle off — iCloud sees the items as still valid), but we never read from it because the dedup keeps the non-sync copy by createdAt tiebreaker (which will be same, so by insertion-order tiebreaker we keep whichever was first — see § Dedup Strategy).

**Simpler alternative:** On D-06, re-save as non-sync AND delete the synced copy via `synchronizable=true` query. This propagates deletion to other devices, which is NOT what D-06 wants. Reject this approach.

**Open question for the planner:** The dedup pass currently has only `(issuer, label, secret)` as key and `createdAt` as tiebreaker. For D-06, both copies have identical fields. The dedup must not delete either — it needs to know "these are the same, just keep ONE, but don't delete the synced one because it's co-owned by other devices." The simplest implementation: after D-06, the dedup pass prefers the non-sync copy for display and does NOT delete the synced copy. This means `loadAll()` returns only the non-sync copy after de-duplication in memory; the synced copy remains in iCloud Keychain, untouched.

## Dedup Strategy

### Key Computation

Per D-08: dedup key is `(issuer, label, secret)`. Tiebreaker: earliest `createdAt` wins.

**Normalization rules — decisions that affect correctness:**

| Field | Normalization | Rationale |
|-------|--------------|-----------|
| `issuer` | Unicode NFC normalize, trim ASCII whitespace, case-insensitive compare | "GitHub" and "github" and "GITHUB" should collide; Unicode homoglyphs don't |
| `label` | Unicode NFC normalize, trim ASCII whitespace, case-insensitive compare | Email addresses are case-insensitive in practice; "User@Example.com" and "user@example.com" collide |
| `secret` | Uppercase ASCII, strip ALL whitespace (not just trim) | Base32 is case-insensitive per RFC 4648; TOTP secrets are often pasted with spaces |

**Implementation:**

```swift
struct DedupKey: Hashable {
    let issuer: String
    let label: String
    let secret: String

    init(_ account: Account) {
        self.issuer = account.issuer.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces).lowercased()
        self.label = account.label.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces).lowercased()
        self.secret = account.secret
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .uppercased()
    }
}
```

Note: Model's `Account.from(otpauthURL:)` already uppercases the secret when parsing. But manually-entered secrets may have whitespace/mixed case. The dedup normalization catches both.

### Tiebreaker Algorithm

Earliest `createdAt` wins. If both timestamps are identical to the millisecond (unlikely but possible in synthetic test fixtures), tiebreak by `id.uuidString` ascending to make it deterministic.

```swift
func dedupSyncedAccounts() -> Int {
    let accounts = try! keychain.loadAll()  // includes SynchronizableAny
    var groups: [DedupKey: [Account]] = [:]
    for account in accounts {
        groups[DedupKey(account), default: []].append(account)
    }
    var mergedCount = 0
    for (_, group) in groups where group.count > 1 {
        let sorted = group.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        let winner = sorted.first!
        for loser in sorted.dropFirst() {
            try? keychain.delete(id: loser.id)  // deletes both sync and non-sync variants
            mergedCount += 1
        }
    }
    return mergedCount
}
```

**Important:** The delete must use `kSecAttrSynchronizableAny` so BOTH the sync and non-sync copies of the loser are removed. This propagates the sync delete to other devices — which is desired in this case (dedup result is authoritative across the sync set).

### Toast Timing

Per D-08 + UI-SPEC: toast shown ONCE after migration completes. `N == 0` → silent. Copy: `"Merged {N} duplicate {account|accounts}"` (singular/plural via `String.localizedStringWithFormat`).

**When to run dedup:**

1. **After toggle OFF→ON migration:** run after bulk re-save completes (this is the "first sync" per CONTEXT.md D-08 terminology)
2. **After KVS-observer-driven reload:** dedup should ALSO run on `InitialSyncChange` for fresh installs on second device. This catches the case where device B had an account cached (from an earlier install of the app) that collides with what device A had been syncing.
3. **Do NOT run dedup on every `.active` scenePhase transition** — that would be wasteful and produce repeated toasts.

**Recommendation:** Centralize dedup in `AccountStore.reload()` but gate the toast on a flag `shouldShowDedupToast` that is set by the migration path and cleared after the toast fires. Observer-driven reloads run dedup silently (just log the count).

## Fresh Install "Restoring from iCloud" Flow

### How a Fresh Install Gets Synced Items

When the user installs the app on a new device and signs into the same Apple ID, iCloud Keychain begins propagating synced items to the local Keychain in the background. **There is no public API to observe this process.** The items simply "appear" in the Keychain when iOS's sync daemon (`securityd`) finishes pulling them.

[CITED: support.apple.com/guide/security/secure-keychain-syncing-sec0a319b35f/web and multiple community reports] Typical propagation times:
- Good conditions (strong network, device plugged in): 1-2 minutes
- Typical conditions: 5-15 minutes
- Bad conditions: "hours or overnight"

**The app cannot force a Keychain fetch.** `SecItemCopyMatching` with `kSecAttrSynchronizable=true` OR `kSecAttrSynchronizableAny` returns whatever is in the LOCAL Keychain at that moment — it does NOT trigger a pull from iCloud. The pull is managed entirely by `securityd`.

**However, we can use `NSUbiquitousKeyValueStore` as a proxy signal.** The `accounts-version` counter syncs via iCloud's KVS service (separate from iCloud Keychain but running on the same Apple ID). When `NSUbiquitousKeyValueStoreInitialSyncChange` fires on the fresh device, it means KVS has finished its initial fetch — which strongly correlates with iCloud Keychain being about to finish its fetch too (both run on the same sync infrastructure). This isn't a guarantee (KVS can fetch faster or slower than Keychain in edge cases) but it's the best signal available.

### Timeout Recommendation: 30s is aggressive, 60s is safer

**D-09 specifies ~30 seconds.** Evidence for and against:

- **For 30s:** UI responsiveness — users on a new device expect "fast or failed." 30s with a spinner is already long.
- **Against 30s:** Multiple forum reports show Keychain sync taking 1-2 minutes even on good networks on a freshly-installed device. 30s will timeout MOST fresh installs, not some edge cases.
- **Compromise:** Start at 30s but surface the fallback copy as "Still loading… You can leave this screen open" rather than "No accounts yet," letting the UI quietly continue polling via the `accounts-version` observer. On subsequent `.active` scenePhase or `InitialSyncChange` firings, the accounts will populate.

**Recommended implementation:**

```swift
enum SyncRestoreState {
    case idle
    case restoring(startedAt: Date)
    case restored
    case timedOut  // after 30s; UI falls through to "No accounts yet" but observer remains live
}

// On fresh-install detection:
// - syncPreference is default-ON (new user per D-01)
// - AccountStore.reload() returns empty
// - 30s timer starts
// - If during the timer, accounts-version changes OR scenePhase returns to .active with accounts > 0, transition to .restored
// - Otherwise transition to .timedOut (fall through to normal empty state)
```

**Distinguishing a true fresh-install-with-iCloud-incoming from a true fresh-install-with-no-accounts:** impossible to distinguish at app start. The 30s restoring state is a "benefit of the doubt" window — if nothing arrives, we assume no accounts exist and show the normal empty state (per UI-SPEC).

**Edge case:** Existing user with sync OFF installs on a new device. They default to sync OFF (D-02 logic triggers because an `hasSeenBefore` flag exists), so they see the normal empty state immediately — no "Restoring…" spinner. This is correct: the only path to the "Restoring…" state is `syncPreference.isEnabled = true AND accounts.isEmpty AND isFirstLaunchOnThisInstall`.

## In-Session Refresh Architecture

### The Two Signals (per D-10)

**Signal 1: scenePhase `.active` transition**

```swift
@Environment(\.scenePhase) var scenePhase

var body: some View {
    ContentView()
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                accountStore.reload()
                NSUbiquitousKeyValueStore.default.synchronize()  // force local fetch
            }
        }
}
```

`.active` fires when the user returns from app switcher, unlocks device, taps notification. This is the "user is looking at the app again" boundary. Reloading here catches most cross-device propagation without requiring the mid-session observer.

**Signal 2: `NSUbiquitousKeyValueStore.didChangeExternallyNotification`**

Covers the case where the user is actively using the app and another device pushes a change. This is rarer but happens — e.g., user on iPhone watching a code expire while iPad has added a new account.

### The `accounts-version` Counter

**Purpose:** The Keychain itself has no change notification. KVS does. We use KVS as a side-channel ping: "something changed, go look at Keychain."

**Counter semantics:**
- `Int64` stored at key `"accounts-version"` in `NSUbiquitousKeyValueStore.default`
- Bumped on every `KeychainManager.save` and `.delete` (when `SyncPreference.isEnabled = true`)
- Monotonically increasing per device; iCloud merges writes by last-writer-wins (acceptable — the counter is a trigger, not a source of truth)

**Why not store the account array in KVS directly?** 1 MB quota, 1024 keys — possible but tempting to misuse. Also, KVS is plaintext; Keychain is encrypted. Account secrets MUST NOT go in KVS. The counter is a safe ping only.

### Coalescing Reloads

Multiple rapid KVS notifications (e.g., migration on device A bumping the counter N times in 2 seconds, coalesced to a single fire on device B) should result in ONE reload, not N reloads. Debounce the observer:

```swift
private var reloadDebounceTask: Task<Void, Never>?

func coalescedReload() {
    reloadDebounceTask?.cancel()
    reloadDebounceTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 300_000_000)  // 300 ms
        guard !Task.isCancelled else { return }
        AccountStore.shared.reload()
    }
}
```

300 ms is enough to coalesce a burst but short enough to feel instantaneous. This also protects against a UI flash where the accounts list renders, then re-renders with a different order.

## Destructive "Remove from iCloud on all devices" Implementation

### Exact Query

Per D-05 option 2 — delete only synced items:

```swift
func deleteAllSynced() throws {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrSynchronizable as String: kCFBooleanTrue  // synced only, NOT SynchronizableAny
    ]
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.deleteFailed(status)
    }
}
```

**What this does:**
1. Deletes all synced copies on THIS device locally and immediately
2. iCloud Keychain propagates the deletion to every other signed-in device — eventually, same propagation timing as adds (seconds to hours)
3. Leaves any non-sync copies on THIS device alone (D-05 copy explicitly says "Accounts on this iPhone stay")

### Propagation Timing Expectation

**Honest disclosure for the UI:** The destructive action fires immediately on THIS device (synced copies gone). Propagation to OTHER devices is NOT under our control. Users may see accounts reappear briefly on other devices before they're deleted. This is iCloud's behavior, not ours.

**UI-SPEC implication:** The D-05 destructive copy "removes from your iPad, Apple Watch, and any other device signed into this iCloud" should NOT promise "immediately" or "right away." It promises eventual consistency. Current copy is already careful about this.

### Race Re-Enable Edge Case

**Scenario:** User taps "Remove from iCloud on all devices." Destructive delete fires. User, having second thoughts, immediately re-taps the sync toggle ON. If they do this FAST, the migration from local-only to synced may race with iCloud's deletion propagation — the newly-migrated account on this device could be deleted by iCloud's lagging delete before other devices see it.

**Recommended mitigation:** After a destructive delete, disable the toggle for **10 seconds** with no explanation. This is short enough to feel responsive but long enough to let the destructive propagation at least leave this device's outbound sync queue. This is cheap insurance against a confusing edge case.

```swift
@Published var toggleDisabledUntil: Date? = nil

func performDestructiveDelete() async throws {
    try keychain.deleteAllSynced()
    toggleDisabledUntil = Date().addingTimeInterval(10)
    // UI binds toggle.disabled = (toggleDisabledUntil ?? .distantPast) > Date()
}
```

An alternative is a "destructive action complete — cooldown" inline footnote, but that adds UI complexity for a rare case. The silent 10s cooldown is simpler and sufficient.

## iCloud Keychain State Detection (D-11, D-12 Implementation)

Consolidates the detection strategy from § Apple Platform Mechanics into the D-11/D-12 implementation.

### D-11: iCloud Keychain OFF at OS Level

**Detectable conditions:**
- `FileManager.default.ubiquityIdentityToken == nil` → user is not signed into iCloud at all. Treat as "iCloud Keychain is turned off on this device." Show D-11 copy, disable toggle.

**Undetectable condition:**
- User signed into iCloud but iCloud Keychain specifically disabled in iOS Settings. Toggle appears enabled; sync silently no-ops if enabled. The user will discover this when no propagation happens. The D-09 30s timeout on "Restoring…" is the UX catch here.

**Deep-link to Settings:**

```swift
if let url = URL(string: UIApplication.openSettingsURLString) {
    UIApplication.shared.open(url)
}
```

**Note:** `openSettingsURLString` opens the app's own Settings page, not the iCloud section directly. iOS does not expose a public URL for deep-linking to iCloud → Keychain specifically. The user has to navigate there themselves. This is a platform limitation; multiple password managers document this.

### D-12: Mid-session iCloud Sign-out

```swift
NotificationCenter.default.addObserver(
    forName: .NSUbiquityIdentityDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    let token = FileManager.default.ubiquityIdentityToken
    if token == nil {
        // User signed out of iCloud
        SyncPreference.setEnabled(false)
        self?.syncState = .signedOut
        // UI observes syncState and shows D-12 copy, flips toggle to OFF
    } else if let self, self.previousIdentityToken != nil, self.previousIdentityToken != token {
        // User switched iCloud accounts — same handling as sign-out + fresh sign-in
        self.handleiCloudAccountChange()
    }
    self?.previousIdentityToken = token
}
```

**No modal, no alert** per CONTEXT.md. The toggle flips OFF automatically, footer swaps from D-03 to D-12 copy. When user signs back in, scenePhase `.active` reloads and re-evaluates the toggle state.

**Data handling on sign-out:** Per CONTEXT.md "accounts stay visible (keychain cache)" — the non-sync copies remain readable on the device. iOS itself may eventually evict the locally-cached synced copies (behavior varies by iOS version, not under our control). We don't proactively re-save synced copies as non-sync on sign-out — that would be a large quiet data mutation. We simply treat the state as read-only until the user signs back in.

## Keyboard Extension Propagation

### Existing Chain (confirmed by reading `KeyboardViewController.swift`)

```
Main app Keychain mutation
    ↓ (AccountStore.reload() fires)
SharedDefaults.saveAccounts(accounts) writes JSON to group.com.keyauth.shared
    ↓ (keyboard becomes active via viewWillAppear)
SharedDefaults.loadAccounts() reads JSON
    ↓
Keyboard displays TOTP codes
```

**Verified from `KeyboardExtension/KeyboardViewController.swift` lines 72-92:** `loadAccounts()` is called on view load and on every `viewWillAppear`. The keyboard re-reads SharedDefaults on every activation.

### Phase 6 Propagation (synced accounts case)

```
Device B KeychainManager.save(..., synchronizable: true)
    ↓ iCloud Keychain propagates to Device A (seconds-hours)
Device A's AccountStore is unaware until triggered
    ↓ one of:
    (a) scenePhase .active → AccountStore.reload()
    (b) NSUbiquitousKeyValueStore.didChangeExternallyNotification → AccountStore.coalescedReload()
    ↓
AccountStore.reload() fires keychain.loadAll() with SynchronizableAny
    ↓ returns updated account list
SharedDefaults.saveAccounts(accounts) writes to group.com.keyauth.shared
    ↓ (keyboard becomes active next time user activates it)
SharedDefaults.loadAccounts() reads JSON
    ↓
Keyboard displays updated TOTP codes
```

**No keyboard code changes needed.** The chain is already complete. The keyboard sees updated accounts on its next activation cycle, which is "within one keyboard reactivation" per CONTEXT.md Claude's discretion acceptance.

**Propagation lag observable to user:** If the user adds an account on device A and immediately activates the keyboard on device B (without re-entering the KeyAuth main app), the keyboard will show the stale list until the user opens KeyAuth on device B. This is **acceptable** per CONTEXT.md and is an order-of-magnitude shorter than the iCloud sync latency anyway.

**No order-of-operations risk:** `AccountStore.reload()` synchronously writes to `SharedDefaults` before returning. The keyboard's next read will see fresh data as long as the main app's reload completed before the keyboard activates. No locking needed — `UserDefaults` with `synchronize()` (already in place in `SharedDefaults.swift`) is atomic for the write and read.

## Testing Strategy

### Unit-Testable Pieces

Everything below is mockable and fast (<5 ms per test):

1. **`DedupKey` normalization:** pure function, no Keychain. Test cases: unicode NFC, whitespace variants, case insensitivity, base32 canonicalization.
2. **Migration loop against a fake `KeychainManager`:** extract a `KeychainProviding` protocol:
    ```swift
    protocol KeychainProviding {
        func save(_ account: Account, synchronizable: Bool) throws
        func loadAll() throws -> [Account]
        func loadAllIncludingVariants() throws -> [(Account, Bool)]
        func delete(id: UUID, synchronizable: KeychainSyncScope) throws
        func deleteAllSynced() throws
    }
    ```
   The `AccountStore` and migration logic depend on `KeychainProviding`. `KeychainManager.shared` conforms in production; `MockKeychain` conforms in tests. Dedup, migration, partial-failure recovery all unit-testable.
3. **`SyncPreference` branching in `KeychainManager.save`:** test that synchronizable=true propagates to the actual query dict (via a test-only hook that returns the computed query).
4. **Coalesced reload debounce logic:** inject a clock, send 5 rapid "reload" pings, assert only 1 reload fires.
5. **`accounts-version` counter bump semantics:** mock `NSUbiquitousKeyValueStore` behind a protocol, verify bump happens exactly once per save/delete.

### On-Device Integration Tests (Single Device)

Runs on a real iOS Simulator or device via XCTest. Validates real Keychain round-trips without requiring two devices or real iCloud:

1. **Synchronizable save → load round-trip:** save with `synchronizable=true`, `loadAll()` returns it with correct data; query with `synchronizable=false` returns nothing for that item; query with `SynchronizableAny` returns it. Confirms our query layer is correct even without actual iCloud sync.
2. **Migration re-save + delete:** save with `synchronizable=false`, run migration, verify only the synchronizable=true copy remains.
3. **Partial-failure recovery:** inject a `MockKeychain` wrapper that fails save for a specific account ID; assert migration continues, `failed=1`, `ok = total-1`.
4. **Error classification:** `errSecDuplicateItem` maps to the re-save branch; `errSecMissingEntitlement` maps to a distinct error surface.

These tests **do not require** real iCloud propagation. They test the query mechanics and branching logic that cause 95% of the potential bugs.

### Two-Device Manual QA (Unavoidable)

Real iCloud propagation cannot be unit-tested. These acceptance tests cover the actual cross-device flow:

**Test 2-DEV-01: Basic account propagation**
- Prerequisite: Both devices signed into same Apple ID, iCloud Keychain enabled
- Device A: Sync ON, add account "test-alpha"
- Within 5 minutes, Device B should show "test-alpha" in the accounts list
- Keyboard on Device B, after switching to KeyAuth keyboard, shows the TOTP code for "test-alpha"

**Test 2-DEV-02: Migration with dedup**
- Device A: Sync OFF, add accounts "bank" and "email" locally
- Device B: Sync ON from a prior install, has accounts "bank" and "email" already synced (same issuer/label/secret)
- Device A: Enable sync
- Expected: Device A shows "Merged 2 duplicate accounts" toast; total count is 2 (not 4)
- Device B: account list unchanged

**Test 2-DEV-03: Stop syncing this device (D-06)**
- Device A and B both have sync ON with 3 accounts
- Device A: Toggle sync OFF, pick "Stop syncing this device"
- Expected: Device A keeps the 3 accounts visible
- Device A: Add account "local-only"
- Device B: does NOT see "local-only"
- Device A: Delete "bank" account
- Device B: "bank" is still present (because A's delete was local-only)

**Test 2-DEV-04: Remove from iCloud on all devices (D-05 destructive)**
- Device A and B both have sync ON with 3 accounts
- Device A: Toggle sync OFF, pick "Remove from iCloud on all devices"
- Expected (immediate): Device A's sync toggle shows OFF; accounts list on Device A **unchanged** (D-05 copy: "Accounts on this iPhone stay")
- Expected (within 5 min): Device B's accounts list becomes empty
- Device A: Re-enable sync → Device A re-uploads its 3 accounts → Device B sees them again within 5 min

**Test 2-DEV-05: Fresh-install restore**
- Device A has 5 accounts synced
- Install KeyAuth on Device B (fresh install), sign into same Apple ID
- Expected: Device B shows "Restoring your accounts from iCloud…" for up to 30 seconds
- Within 30s (likely) or after closing/reopening the app: Device B shows all 5 accounts

**Test 2-DEV-06: Mid-session external change**
- Device A: foreground, KeyAuth open, sync ON, 3 accounts
- Device B: add a 4th account
- Device A: after 5-60 seconds (without user action), Device A's list should add the 4th account (via KVS observer)

**Test 2-DEV-07: iCloud Keychain OFF (D-11)**
- Device A: Turn OFF iCloud Keychain in iOS Settings → iCloud → Keychain
- Launch KeyAuth on Device A
- Expected: Sync toggle is disabled, D-11 copy shown, "Open iOS Settings" button present and functional

**Test 2-DEV-08: Mid-session iCloud sign-out (D-12)**
- Device A: KeyAuth open, sync ON
- Sign out of iCloud in iOS Settings (without closing KeyAuth)
- Return to KeyAuth
- Expected: toggle flipped to OFF, D-12 copy shown, accounts list still visible locally

### CI Gating Recommendations

- **Per commit:** unit tests (<10 sec)
- **Per wave merge:** unit + single-device integration tests (<2 min on iOS Simulator)
- **Per phase gate:** all of the above PLUS all 8 two-device manual QA tests must pass on real hardware with the tester's Apple ID. Document the QA run in the phase summary with timestamps.
- **Release gate:** a second QA pass by a different person/Apple ID (different iCloud account) catches single-account-specific state bugs.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in) |
| Config file | None — test target must be created in Xcode (Wave 0 gap) |
| Quick run command | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyAuthTests/SyncPreferenceTests -only-testing:KeyAuthTests/DedupTests -only-testing:KeyAuthTests/MigrationTests -quiet` |
| Full suite command | `xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16' -quiet` |

### Phase Requirements → Test Map

| Proposed ID | Behavior | Test Type | Automated Command | File Exists? |
|-------------|----------|-----------|-------------------|-------------|
| ICLOUD-01 | `save(_:synchronizable:true)` sets kSecAttrSynchronizable in SecItemAdd query | unit | `xcodebuild test -only-testing:KeyAuthTests/KeychainManagerSyncTests/testSaveSynchronizableTrue` | ❌ Wave 0 |
| ICLOUD-02 | `loadAll()` includes kSecAttrSynchronizableAny and returns both variants | unit | `xcodebuild test -only-testing:KeyAuthTests/KeychainManagerSyncTests/testLoadAllIncludesBothVariants` | ❌ Wave 0 |
| ICLOUD-03 | `delete(id:)` removes both sync and non-sync copies | unit | `xcodebuild test -only-testing:KeyAuthTests/KeychainManagerSyncTests/testDeleteBothVariants` | ❌ Wave 0 |
| ICLOUD-04 | Settings surface renders toggle + disclosure with D-03 copy | unit (view snapshot) | `xcodebuild test -only-testing:KeyAuthTests/SettingsViewTests/testDisclosureCopyVerbatim` | ❌ Wave 0 |
| ICLOUD-05 | First-launch card shown only for new users (hasSeenCard=false) | unit | `xcodebuild test -only-testing:KeyAuthTests/FirstLaunchCardTests` | ❌ Wave 0 |
| ICLOUD-06 | Disable confirmation shows two buttons with correct destructive role | unit | `xcodebuild test -only-testing:KeyAuthTests/DisableConfirmationTests` | ❌ Wave 0 |
| ICLOUD-07 | Migration loop re-saves then deletes, handles errSecDuplicateItem, continues on partial failure | unit | `xcodebuild test -only-testing:KeyAuthTests/MigrationTests` | ❌ Wave 0 |
| ICLOUD-08 | Dedup collapses (issuer,label,secret) with earliest createdAt winner; normalizes case/whitespace | unit | `xcodebuild test -only-testing:KeyAuthTests/DedupTests` | ❌ Wave 0 |
| ICLOUD-09 | `deleteAllSynced()` uses kSecAttrSynchronizable=true (not Any) | unit | `xcodebuild test -only-testing:KeyAuthTests/KeychainManagerSyncTests/testDeleteAllSyncedQueryShape` | ❌ Wave 0 |
| ICLOUD-10 | scenePhase .active triggers AccountStore.reload() | unit (ViewModel) | `xcodebuild test -only-testing:KeyAuthTests/AccountStoreTests/testScenePhaseActiveTriggersReload` | ❌ Wave 0 |
| ICLOUD-11 | KVS didChangeExternallyNotification triggers coalesced reload; 5 rapid events = 1 reload | unit (injected clock) | `xcodebuild test -only-testing:KeyAuthTests/AccountStoreTests/testCoalescedReload` | ❌ Wave 0 |
| ICLOUD-12 | After AccountStore.reload(), SharedDefaults.loadAccounts() returns the updated list | integration | `xcodebuild test -only-testing:KeyAuthTests/KeyboardPropagationTests` | ❌ Wave 0 |
| ICLOUD-13 | PairingStore and CryptoBoxManager queries do NOT include kSecAttrSynchronizable=true | unit | `xcodebuild test -only-testing:KeyAuthTests/SyncScopeIsolationTests` | ❌ Wave 0 |
| SC-1, SC-3, SC-4, SC-5 from ROADMAP | Two-device cross-sync behavior | manual (two-device) | § Two-Device Manual QA list 2-DEV-01 through 2-DEV-08 | ❌ Wave 0 (manual checklist doc) |

### Sampling Rate

- **Per task commit:** unit tests + single-device integration tests for the tasks touched in this commit. Target <30 seconds.
- **Per wave merge:** full unit + integration suite on iPhone 16 simulator. Target <2 minutes.
- **Per phase gate:** full suite green AND all 8 two-device manual QA tests documented in a checklist file (`.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md`) with timestamps and device identifiers.

### Wave 0 Gaps

- [ ] `KeyAuthTests/` test target does not exist in `KeyAuth.xcodeproj` — Phase 2's research flagged this as a Wave 0 gap and it was never closed. Phase 6 must close it.
- [ ] `KeyAuthTests/KeychainManagerSyncTests.swift` — covers ICLOUD-01, ICLOUD-02, ICLOUD-03, ICLOUD-09
- [ ] `KeyAuthTests/SyncPreferenceTests.swift` — covers SyncPreference helper
- [ ] `KeyAuthTests/DedupTests.swift` — covers ICLOUD-08
- [ ] `KeyAuthTests/MigrationTests.swift` — covers ICLOUD-07 (both OFF→ON and D-06 reverse)
- [ ] `KeyAuthTests/SettingsViewTests.swift` — covers ICLOUD-04, ICLOUD-05, ICLOUD-06
- [ ] `KeyAuthTests/AccountStoreTests.swift` — covers ICLOUD-10, ICLOUD-11
- [ ] `KeyAuthTests/KeyboardPropagationTests.swift` — covers ICLOUD-12
- [ ] `KeyAuthTests/SyncScopeIsolationTests.swift` — covers ICLOUD-13
- [ ] `KeyAuthTests/Mocks/MockKeychain.swift` — shared test fixture for KeychainProviding protocol
- [ ] `.planning/phases/06-icloud-keychain-sync/06-QA-CHECKLIST.md` — manual two-device checklist (authoring, not a test artifact per se)

## App Store Review 5.1.1 Compliance Checklist

Per [CITED: developer.apple.com/app-store/review/guidelines/] 5.1.1:

> *"Data Collection and Storage. Apps must clearly disclose what data they collect, how it's collected, and all the ways it will be used… Apps must respect the user's permission settings and not attempt to manipulate, trick, or force people to consent to unnecessary data access."*

### Disclosure copy review

UI-SPEC D-03 copy: *"Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."*

- [x] **Discloses what data moves to iCloud:** "2FA accounts" — user understands this is their TOTP secrets
- [x] **Discloses where it goes:** "your other Apple devices using iCloud Keychain"
- [x] **Discloses protection mechanism:** "Apple ID and device passcode"
- [x] **Addresses privacy concern:** "Apple can't read them" (accurate — iCloud Keychain is E2E encrypted)
- [x] **Plain language, no jargon** per D-03 voice rules

Verdict: Compliant. The disclosure is honest, specific, and in plain language.

### Consent UX review

- **New users (D-01):** Default sync=ON with dismissible first-launch card. **Is this "consent"?**

  Apple's guideline 5.1.1 requires "clearly disclose" + "respect user permission settings." It does NOT require affirmative opt-in for all data processing — it requires transparency and an easy opt-out. Default-ON with a visible disclosure and an always-available opt-out in Settings **is typically compliant** for features that serve the user's own benefit (cross-device backup of their own passwords is user-benefit, analogous to iCloud Photos which is also default-off → user enables → never re-prompted).

  **Risk factor:** Apple reviewers occasionally flag default-ON sync features for more explicit consent. If the review risk is non-trivial, the safer pattern is **default-OFF for new users with a prominent opt-in card on first launch** ("Sync across your devices? YES / NO") rather than default-ON with a dismissible disclosure.

  **Recommendation for discuss-phase reconsideration:** The CONTEXT.md D-01 decision (default=ON for new users) is locked, so this research respects it. But flag in the risk section for the planner: the safer App Store review posture is default-OFF with an explicit first-launch opt-in. If the planner/user wants to hedge, switching D-01 to "default-OFF for new users with an explicit opt-in card" is a small UX change and zero code impact.

- **Existing users (D-02):** Default sync=OFF, no prompt. Discoverable via Settings only. **Fully compliant** — this is the classic "add feature without prompting" pattern that never triggers review friction.

### Opt-out review

- [x] Settings → Sync → toggle OFF is always available when iCloud Keychain is enabled
- [x] Destructive option "Remove from iCloud on all devices" gives user full data control
- [x] Per-device opt-out "Stop syncing this device" gives granular control
- [x] No nag screens, no "are you sure?" recycling, no dark patterns

Verdict: Compliant.

### Privacy policy implications

If the app has a privacy policy (check `.planning/` — currently not found), add a clause: *"Account data (TOTP secrets and metadata) may be synchronized to the user's other Apple devices via iCloud Keychain at the user's option. Apple manages this sync using end-to-end encryption; the developer cannot access this data."* This is a factual addition, not a compliance-driven rewrite.

## Risks & Gotchas

### Risk 1: Uniqueness query misconstruction in one code path

**What goes wrong:** A single `SecItemCopyMatching` or `SecItemDelete` call that forgets `kSecAttrSynchronizableAny` becomes invisible to one variant. Symptoms: user deletes an account, it "comes back" after reopening app (because only non-sync was deleted and sync copy remains).

**Mitigation:** Encapsulate all query construction in **one** private `baseQuery(for:synchronizable:)` helper (the existing `KeychainManager` already has this pattern — extend it). Code-review every SecItem* call against the matrix table in § Apple Platform Mechanics. Unit test ICLOUD-02 and ICLOUD-03 catch this mechanically.

### Risk 2: D-06 deletion semantics misunderstanding

**What goes wrong:** Engineer reads D-06 literally ("re-save as non-synchronizable, preserving local copy") and writes code that also deletes the synced copy. Result: other devices lose accounts when user just wanted to stop syncing this device.

**Mitigation:** § Migration Strategy explicitly documents the correct algorithm. Unit test ICLOUD-07 verifies the reverse migration does NOT call `delete` with `synchronizable=true`. Two-device QA test 2-DEV-03 catches this end-to-end.

### Risk 3: Accessibility attribute reset on re-save

**What goes wrong:** The current `KeychainManager.save` only sets `kSecAttrAccessible` on the ADD branch (not the UPDATE branch). If a sync attribute change requires delete+add (which it does, per § Migration Strategy), the accessibility attribute might get dropped or set incorrectly.

**Mitigation:** The `save` function already sets `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` on every ADD. As long as the migration path always goes through a fresh ADD (which it does — we delete then re-add the synced version), the accessibility attribute is correctly set. Unit test: verify the computed add-query dict contains `kSecAttrAccessible`.

### Risk 4: `accounts-version` counter race with pre-existing value

**What goes wrong:** Fresh install on device B. KVS pulls down `accounts-version = 42` from iCloud. Device B's local `AccountStore` initializes before KVS has finished its first pull. `AccountStore.reload()` runs against an empty Keychain (iCloud Keychain also hasn't pulled yet), shows empty list, writes to SharedDefaults. Later, KVS fires `InitialSyncChange` and we reload — but we've already written a "zero accounts" state to SharedDefaults, and the keyboard may have read it.

**Mitigation:** 
1. Always use the `InitialSyncChange` reason to trigger a reload (already planned).
2. On fresh-install detection, show the "Restoring…" empty state INSTEAD OF writing `[]` to SharedDefaults. The SharedDefaults write only happens after the first non-empty reload OR after the 30s timeout expires.
3. Keyboard already handles "0 accounts" gracefully (shows its own empty state), so even in the edge case, the user sees a stale empty keyboard for at most one activation cycle — not a data bug.

### Risk 5: iCloud propagation latency misinterpreted as a bug

**What goes wrong:** Beta tester adds an account on device A, checks device B within 30 seconds, sees nothing, reports "sync is broken."

**Mitigation:** This is a documentation / expectation issue, not a code issue. The "Restoring…" 30s window sets expectation honestly. The release notes and Settings disclosure should set the expectation: "Syncing usually happens within a few minutes, sometimes longer on slow networks." Add this to the "How is this secured?" expandable copy proactively.

## Proposed Requirements IDs

**For the planner to formalize in `.planning/REQUIREMENTS.md`:**

```markdown
### iCloud Keychain Sync

- [ ] **ICLOUD-01**: `KeychainManager.save` accepts a `synchronizable: Bool` parameter and sets `kSecAttrSynchronizable` accordingly on SecItemAdd
- [ ] **ICLOUD-02**: All Keychain read queries (`loadAll`, `load`) include `kSecAttrSynchronizable: kSecAttrSynchronizableAny` so both synced and non-synced items are matched
- [ ] **ICLOUD-03**: `KeychainManager.delete(id:)` removes both the synced and non-synced copies of the specified account
- [ ] **ICLOUD-04**: A Settings screen is accessible from the main toolbar via a gear button and contains a "Sync with iCloud Keychain" toggle with the D-03 disclosure footer verbatim
- [ ] **ICLOUD-05**: New users (with no prior `hasSeenSyncFirstLaunchCard` flag) see a first-launch card above the accounts empty state with the D-03 copy and a "Got it" dismiss action
- [ ] **ICLOUD-06**: Turning the sync toggle OFF opens a confirmation with two explicit options: "Stop syncing this device" (default) and "Remove from iCloud on all devices" (destructive, `role: .destructive`)
- [ ] **ICLOUD-07**: Flipping the toggle OFF→ON migrates all local-only accounts to synced storage by re-saving each with `synchronizable=true` and deleting the original non-sync copy, continuing on partial failure and surfacing the final count
- [ ] **ICLOUD-08**: After migration or fresh-sync, accounts with identical `(normalized issuer, normalized label, canonicalized secret)` are deduplicated to the one with the earliest `createdAt`; a toast shows "Merged N duplicate accounts" when N > 0
- [ ] **ICLOUD-09**: The "Remove from iCloud on all devices" action executes `SecItemDelete` with `kSecAttrSynchronizable: true` (not `SynchronizableAny`), preserving any non-synchronizable copies on the current device
- [ ] **ICLOUD-10**: When the app's `scenePhase` becomes `.active`, `AccountStore.reload()` is invoked and `NSUbiquitousKeyValueStore.synchronize()` is called
- [ ] **ICLOUD-11**: On every `KeychainManager.save` or `.delete` with sync enabled, an `accounts-version` Int64 counter in `NSUbiquitousKeyValueStore` is incremented; an observer on `didChangeExternallyNotification` triggers a coalesced (300ms debounce) `AccountStore.reload()` on `ServerChange` or `InitialSyncChange` reasons
- [ ] **ICLOUD-12**: After `AccountStore.reload()` completes, the updated account list is written to `SharedDefaults` so the keyboard extension's next activation reads fresh data
- [ ] **ICLOUD-13**: `PairingStore`, `CryptoBoxManager`, APNs device token storage, and any other per-device state do NOT set `kSecAttrSynchronizable=true` on their Keychain items; these items remain local to each device
- [ ] **ICLOUD-14**: When `FileManager.default.ubiquityIdentityToken` is nil, the sync toggle is disabled and shows the D-11 inline copy with a functional "Open iOS Settings" deep-link button
- [ ] **ICLOUD-15**: On `NSUbiquityIdentityDidChangeNotification` when the token becomes nil, the sync toggle flips to OFF and the D-12 inline copy is shown; when the token changes to a different non-nil value, the app treats this as a new iCloud account (clears SyncPreference, shows D-12 copy)
- [ ] **ICLOUD-16**: Fresh install with `syncPreference.enabled=true` AND empty accounts list shows "Restoring your accounts from iCloud…" state for up to 30 seconds; if `accounts-version` changes or accounts arrive within the window, transition to normal state; otherwise fall through to normal empty state

**Traceability:**
| Requirement | Phase | Status |
|-------------|-------|--------|
| ICLOUD-01 through ICLOUD-16 | Phase 6 | Pending |
```

## References

### Primary (HIGH confidence)
- [Apple: kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable) — attribute semantics, accessibility compatibility
- [Apple: kSecAttrSynchronizableAny](https://developer.apple.com/documentation/security/ksecattrsynchronizableany) — query-time any-match constant
- [Apple: NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore) — quotas (1 MB, 1024 keys), semantics
- [Apple: didChangeExternallyNotification](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/didchangeexternallynotification) — notification contract
- [Apple: Keychain Access Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups)
- [Apple: Sharing access to keychain items](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- [Apple: Secure keychain syncing](https://support.apple.com/guide/security/secure-keychain-syncing-sec0a319b35f/web) — iCloud Keychain architecture, E2E model
- [Apple: FileManager.ubiquityIdentityToken](https://developer.apple.com/documentation/foundation/filemanager/ubiquityidentitytoken)
- [Apple Developer Forums thread 68843](https://developer.apple.com/forums/thread/68843) — Quinn "The Eskimo!" confirms `kSecAttrSynchronizable` contributes to uniqueness
- [Apple Developer Forums thread 30699](https://developer.apple.com/forums/thread/30699) — detecting iCloud Keychain enabled (no public API)
- [Apple Developer Forums thread 130776](https://developer.apple.com/forums/thread/130776) — iCloud Keychain access scope (team-only)
- [Apple App Store Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
- Existing code: `Shared/KeychainManager.swift`, `Shared/AccountStore.swift`, `Shared/SharedDefaults.swift`, `KeyboardExtension/KeyboardViewController.swift`
- Phase 02 research: `.planning/phases/02-ios-relay-client-pairing/02-RESEARCH.md`

### Secondary (MEDIUM confidence)
- [Use Your Loaf: Keychain duplicate item when adding password](https://useyourloaf.com/blog/keychain-duplicate-item-when-adding-password/) — uniqueness rules for generic passwords
- [Damian Mehers: Sharing tokens via iCloud Keychain](https://damian.fyi/swift/2020/07/23/sharing-tokens-between-macos-ios-and-watchos-using-icloud-keychain.html) — cross-platform code examples
- [Mateusz Zając: NSUbiquitousKeyValueStore + SwiftUI](https://matteozajac.medium.com/keeping-app-preferences-in-sync-with-nsubiquitouskeyvaluestore-fb621826432c) — observer pattern, synchronize() timing
- [Fatbobman: Using NSUbiquitousKeyValueStore with SwiftUI](https://fatbobman.com/en/posts/nsubiquitouskeyvaluestore/) — change reason handling
- [Apple Open Source: CKDKVSStore.m](https://opensource.apple.com/source/Security/Security-57740.1.18/KVSKeychainSyncingProxy/CKDKVSStore.m.auto.html) — internal implementation reference for KVS + Keychain proxy

### Tertiary (LOW confidence — verify if critical)
- [Apple Developer Forums: Random delay in Keychain Sync](https://forums.developer.apple.com/forums/thread/727073) — community reports of propagation latency "random"
- [Michael Tsai: Apple silently enables iCloud Keychain](https://mjtsai.com/blog/2024/05/21/apple-updates-silently-enable-icloud-keychain/) — context on Apple's default-ON sync philosophy

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 300ms debounce for coalesced reloads is sufficient for typical KVS bursts | § In-Session Refresh Architecture | LOW — if wrong, user sees a visible list flash; tune to 500ms |
| A2 | 10-second post-destructive-delete toggle cooldown is sufficient to avoid race | § Destructive "Remove from iCloud" Implementation | LOW — if wrong, user can still re-trigger destructive action manually; edge case only |
| A3 | KVS `InitialSyncChange` correlates strongly with iCloud Keychain fetch completion on fresh installs | § Fresh Install "Restoring from iCloud" Flow | MEDIUM — if wrong, "Restoring…" times out before Keychain has actually fetched; mitigation: increase timeout to 60s, document in release notes |
| A4 | iCloud Keychain sync propagation typically completes within 30 seconds on good network | § Testing Strategy (test 2-DEV-05) | MEDIUM — forum reports suggest 1-15 minutes is more typical; the 30s `Restoring…` timeout may trigger often, but the UX fallthrough to "No accounts yet" is acceptable because accounts will arrive later |
| A5 | Apple App Store Review 5.1.1 considers default-ON iCloud sync with disclosure-only consent compliant | § App Store Review 5.1.1 Compliance | MEDIUM — flagged as risk; safer default is opt-in but CONTEXT.md locks default-ON |
| A6 | Unicode NFC normalization + case-insensitive compare + ASCII whitespace trim is sufficient dedup normalization | § Dedup Strategy | LOW — if wrong, rare false-negatives (e.g., visually-identical accounts not merged); user can manually delete |
| A7 | The existing `kSecAttrAccessibleAfterFirstUnlock` is preserved through migration re-save cycles | § Risk 3 | LOW — unit test verifies this |
| A8 | Keyboard extension doesn't need sync-awareness (propagation works via existing SharedDefaults chain) | § Keyboard Extension Propagation | LOW — verified by reading KeyboardViewController.swift; `viewWillAppear` always re-reads |
| A9 | `NSUbiquitousKeyValueStore.synchronize()` call on `.active` scenePhase helps ensure local KVS has latest changes | § In-Session Refresh Architecture | LOW — Apple docs recommend this pattern; worst case is no-op |
| A10 | The current `IPHONEOS_DEPLOYMENT_TARGET = 16.0` vs UI-SPEC `iOS 17+` inconsistency does not block Phase 6; bumping to iOS 17.0 is trivial | § iOS Version Requirements | LOW — all required APIs available since iOS 5/7 |

## Open Questions

1. **iOS deployment target inconsistency (iOS 16 in project vs iOS 17+ in UI-SPEC)**
   - What we know: `project.pbxproj` says `IPHONEOS_DEPLOYMENT_TARGET = 16.0`; UI-SPEC frontmatter says `min_deployment: iOS 17+`
   - What's unclear: which is authoritative; does Phase 6 require anything iOS 17-specific?
   - Recommendation: bump to iOS 17.0 to match UI-SPEC. No Phase 6 API requires iOS 17 specifically (all work on iOS 13+), but aligning with UI-SPEC is clean. Planner: include this as a small task in Wave 0.

2. **Default sync=ON for new users vs App Store review risk**
   - What we know: D-01 locks default-ON; § App Store Review 5.1.1 notes the risk
   - What's unclear: tolerance for review friction
   - Recommendation: ship as D-01 specifies; have a fallback plan (flip to default-OFF with explicit opt-in card) ready if review rejects. Low technical cost to switch.

3. **"Restoring from iCloud…" timeout: 30s vs 60s**
   - What we know: D-09 says ~30s is a starting point; forum data suggests real propagation is often 1-15 min
   - What's unclear: user tolerance for longer spinners
   - Recommendation: ship at 30s as specified; expose it as a constant `RESTORING_TIMEOUT_SECONDS` that QA can adjust. After one round of manual two-device testing, revisit.

4. **Where to store `SyncPreference` — standard UserDefaults vs App Group UserDefaults vs Keychain**
   - What we know: the toggle state is per-device UX state, not cross-device
   - Options:
     - (a) Standard `UserDefaults.standard` — per-device, per-app. Cleared on uninstall. ✓ recommended
     - (b) App Group `UserDefaults(suiteName: "group.com.keyauth.shared")` — per-device but shared with keyboard. Not needed because keyboard doesn't need to know sync state. ✗
     - (c) Keychain with `kSecAttrSynchronizable=false` — overkill for a boolean; no security benefit. ✗
   - Recommendation: (a). `UserDefaults.standard.bool(forKey: "syncEnabled")`.

5. **Normalization of secret in dedup — case + whitespace only, or also remove padding `=`?**
   - What we know: Base32 secrets may or may not include `=` padding
   - What's unclear: whether two secrets differing only in padding should dedup
   - Recommendation: strip trailing `=` characters AND whitespace when computing dedup key. Decode and compare the binary secret for maximum accuracy, but the existing `Base32.decode` is a helpful reference: if both inputs decode to the same bytes, they are the same secret even if the base32 strings differ in case/whitespace/padding. Implementation: use `Base32.decode(secret.trimmingPadding().uppercased())?.base64EncodedString()` as the canonical form.

6. **Should the `accounts-version` counter be scoped to sync-enabled state?**
   - What we know: We bump the counter on every save when sync is enabled
   - What's unclear: if sync is OFF on device A and user adds an account locally, do we still bump the counter? (No other device will see anything since the save wasn't synced.)
   - Recommendation: only bump when `SyncPreference.enabled == true AND synchronizable save succeeded`. Skip bumps on local-only saves. This keeps the counter correlated with "iCloud state changed" meaning.

## Metadata

**Confidence breakdown:**
- Keychain semantics & query mechanics: HIGH — verified against Apple docs and multiple cross-platform references
- `NSUbiquitousKeyValueStore` contract: HIGH — official docs + forum confirmations
- Migration algorithm safety ordering: HIGH — reasoned from first principles + Apple forum guidance
- Dedup normalization rules: MEDIUM — based on common sense + Base32 canonicalization; may need iteration if QA finds edge cases
- iCloud sync propagation latency: LOW — reports are "random" (Apple's word); 30s timeout chosen per CONTEXT.md may be too short in practice
- iCloud Keychain state detection: LOW — no public API; workaround pattern (ubiquityIdentityToken + deep-link) is the industry-standard compromise
- App Store Review 5.1.1 compliance for default-ON: MEDIUM — reasoned but not battle-tested; flagged as a risk

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (Apple platform APIs stable; propagation-latency assumptions may need post-QA tuning)

---

*Phase: 06-icloud-keychain-sync*
*Research conducted: 2026-04-18*
