# Phase 6: iCloud Keychain Sync - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Sync TOTP account secrets (`Account` items in `KeychainManager`) across the user's Apple devices via iCloud Keychain, using `kSecAttrSynchronizable`. Includes:
- A Settings surface with a sync toggle, plain-language disclosure, and iCloud-state awareness
- Migration of existing local-only accounts to synced storage
- Duplicate detection and resolution when multiple devices sync for the first time
- A "restoring from iCloud" empty state on fresh installs signed into the same Apple ID
- Refresh mechanism to reflect iCloud-pushed changes while the app is foreground/active

**Explicitly out of scope:**
- Syncing device-bound data (pairings, identity keys, APNs device token) — these stay local
- Multi-user / family-sharing flows beyond what iCloud Keychain provides natively
- Backup codes / recovery codes (separate future phase)
- Cross-ecosystem sync (Android, web, non-Apple devices)
- Account-level sync granularity (global toggle only)

</domain>

<decisions>
## Implementation Decisions

### Default Behavior & Onboarding
- **D-01:** NEW users default to `sync = ON`. First launch shows a one-time dismissible card above the empty accounts list explaining iCloud sync in plain language. Manageable in Settings.
- **D-02:** EXISTING users default to `sync = OFF` (preserve current behavior). No unsolicited prompt, banner, or modal. Discoverable via Settings only.
- **D-03:** Disclosure tone is plain-language and trust-focused. Example voice: *"Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."* Avoid jargon (E2E, CryptoKit) in the primary copy; jargon can live in an optional "How is this secured?" expandable.
- **D-04:** Disclosure copy lives inline directly under the toggle in Settings. Same copy reused verbatim on the new-user first-launch card for consistency.

### Disable Flow
- **D-05:** Turning the toggle OFF opens a confirmation sheet with two explicit choices:
  - **Stop syncing this device** — this device reverts to local-only, iCloud copy and other devices unaffected.
  - **Remove from iCloud on all devices** — destructive; purges synced items from iCloud, which propagates removal to every other signed-in device. Copy must explicitly name what happens ("This will remove your accounts from your iPad, Apple Watch, and any other device signed into this iCloud.").
- **D-06:** When user picks "Stop syncing this device," local copies of all accounts are preserved on the current device (re-saved as non-synchronizable). Edits after that point stay local on this device.

### Migration
- **D-07:** Existing local-only accounts migrate to sync via a **silent bulk migration** when the user flips the toggle ON. No per-account confirmation. Progress indicator if total count > 10. Migration is: load each account, re-save with `kSecAttrSynchronizable: true`, delete the original non-sync record. One atomic op per account.
- **D-08:** **Auto-dedup** on first sync when accounts collide. Dedup key: `(issuer, label, secret)` — all three must match. Keeps the account with the earliest `createdAt`. One-time toast after migration: "Merged N duplicate accounts." Silent below the fold if N == 0.

### Multi-device & State
- **D-09:** Fresh install on a second device signed into the same iCloud shows a dedicated "Restoring your accounts from iCloud…" empty state with spinner. Falls back to the normal empty state if nothing arrives within ~30 seconds (tunable).
- **D-10:** In-session refresh uses **two signals:**
  - Reload accounts whenever the app becomes active (SwiftUI `.onChange(of: scenePhase)` or `UIApplication.didBecomeActiveNotification`).
  - On every `KeychainManager.save`, bump an `accounts-version` counter in `NSUbiquitousKeyValueStore`. Observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` — when the counter moves, trigger `AccountStore.reload()`. This covers mid-session updates from other devices.
- **D-11:** When iCloud Keychain is disabled at the OS level, the sync toggle is visible but disabled/grayed out with inline copy: "iCloud Keychain is turned off on this device." Provides a deep-link button to iOS Settings (`UIApplication.openSettingsURLString`).
- **D-12:** Mid-session iCloud sign-out handling: accounts stay visible (keychain cache), the toggle flips to OFF automatically, inline state flag shows "iCloud Keychain was disabled — sync stopped." No modals, no force-quit prompts.

### Sync Scope (not discussed, Claude's discretion)
- **D-13 (Claude's discretion):** Global sync toggle, not per-account. Scope of what syncs is ONLY `Account` records (TOTP secrets + metadata). Everything else stays local: `PairingStore` (device-specific WebSocket pairings), `CryptoBoxManager` identity keys (device-bound X25519), APNs device token (device-specific), biometric lock preference (per-device UX), sort order (ambiguous — see next line).
- **D-14 (Claude's discretion):** Sort order (`Account.sortOrder`) syncs because it's part of the `Account` Codable payload. This means reorder on one device propagates to others. Acceptable and expected.

### Claude's Discretion
- **Settings screen architecture:** No Settings screen exists in the app today. Planner/researcher may propose: (a) a gear button in the main toolbar opening a `NavigationLink` → `SettingsView`, or (b) a modal sheet. Decide based on existing navigation patterns and minimum change surface.
- **Keyboard extension cache invalidation:** Keyboard reads accounts from `SharedDefaults` (App Group UserDefaults), not Keychain directly. When iCloud pushes new accounts in, the main app reloads and writes to `SharedDefaults` — but keyboard's `viewWillAppear` is the only moment it re-reads. Document the propagation lag in context notes; accept that fresh accounts become available in the keyboard ≤ one keyboard reactivation cycle after main-app reload.
- **Migration atomicity:** If migration fails mid-bulk (Keychain error), decide whether to roll back or resume from failure point. Recommend: log error, continue with remaining accounts, surface total count + failed count in a toast.
- **Testing strategy:** Two-device manual testing is unavoidable (iCloud Keychain can't be mocked in simulator reliably). Researcher should investigate if `XCTest` has any viable paths for unit-testing the sync attribute logic separately from the actual iCloud round-trip.

### Folded Todos
_None — no pending todos matched this phase._

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level
- `.planning/PROJECT.md` — Core value, constraints, existing key decisions (note: Core Value copy will need updating to reflect the iCloud-sync nuance honestly)
- `.planning/REQUIREMENTS.md` — Active requirements; Phase 6 will add new requirements in the ICLOUD-NN or SYNC-NN namespace

### iOS Code (existing patterns to preserve)
- `Shared/KeychainManager.swift` — All Keychain CRUD lives here; modify `save`, `load`, `loadAll`, `delete`, `deleteAll` queries to include `kSecAttrSynchronizable: kSecAttrSynchronizableAny` so both synced and local items are matched
- `Shared/AccountStore.swift` — Reactive layer; `reload()` pattern writes to `SharedDefaults` after every Keychain change, keyboard extension depends on this
- `Shared/SharedDefaults.swift` — App Group UserDefaults bridge between main app and keyboard extension
- `Shared/Account.swift` — `Codable` struct; `createdAt` field is the tiebreaker for dedup
- `App/Views/ContentView.swift` — Entry point for Settings surfacing (toolbar button)

### Apple Platform Docs (for researcher)
- Apple Keychain Services: `kSecAttrSynchronizable`, `kSecAttrSynchronizableAny`, interaction with `kSecAttrAccessible`
- `NSUbiquitousKeyValueStore` — change notifications, quotas (1 MB total, 1024 keys), propagation semantics
- iOS Settings deep-link (`UIApplication.openSettingsURLString`) behavior and gotchas
- App Store Review Guideline 5.1.1 (privacy, data storage disclosure) — relevant because sync moves secrets to iCloud

### Prior Phase Context (security model reference)
- `.planning/phases/02-ios-relay-client-pairing/02-02-PLAN.md` — Keychain access group setup and entitlements
- `Shared/PairingStore.swift`, `Shared/CryptoBoxManager.swift` — Examples of device-bound Keychain items that MUST NOT sync (reference for what NOT to touch)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `KeychainManager.shared` — Single Keychain CRUD surface; extend rather than replace. Existing `kSecAttrAccessibleAfterFirstUnlock` at line 32 is already sync-compatible (no accessibility change needed).
- `AccountStore` — `@MainActor ObservableObject` with `reload()` / `add()` / `delete()` / `move()`. Already propagates to `SharedDefaults` on every reload.
- `SharedDefaults` — App Group bridge at `group.com.keyauth.shared`. Reads/writes JSON-encoded `[Account]`.
- Existing toolbar in `ContentView.swift:42` has pairing (leading) and add-account menu (trailing) — natural place to add a gear/Settings button.

### Established Patterns
- **Keychain access group:** `W646UCTVQV.com.keyauth.shared` for app+keyboard sharing. Must be preserved on every `save` query when adding the sync attribute.
- **Zero external dependencies on iOS side** — keep it that way. iCloud sync uses only `Security` framework and `Foundation` (`NSUbiquitousKeyValueStore`).
- **SwiftUI + `@ObservableObject`** for the app target; `@Published` drives view updates.
- **Codable JSON in Keychain** — account payload is JSON-encoded `Data` in `kSecValueData`; sync attribute is orthogonal.

### Integration Points
- **Settings UI** — new surface. Entry from `ContentView` toolbar. Likely `SettingsView` with sync toggle, biometric lock toggle (future), version info.
- **`AccountStore.init()`** — add iCloud-state check on init and on every `scenePhase` transition to `.active` to drive the "Restoring from iCloud…" empty state.
- **`KeychainManager.save`** — branch on a `SyncPreference` flag (from a new `SyncPreference` helper or stored in `SharedDefaults`) to set `kSecAttrSynchronizable: true | false`.
- **`KeychainManager` queries (load/loadAll/delete/deleteAll)** — add `kSecAttrSynchronizable: kSecAttrSynchronizableAny` so we match both synced and non-synced items during migration and disable flows. THIS IS A MANDATORY QUERY CHANGE; missing it will produce invisible data bugs where synced items appear missing.
- **`NSUbiquitousKeyValueStore` change observer** — new addition, wired in `KeyAuthApp` or `AppDelegate` to trigger `AccountStore.reload()` on external changes.

</code_context>

<specifics>
## Specific Ideas

- **Disclosure voice exemplar:** *"Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."* Use as the reference voice for all Phase 6 copy. Planner should not invent a different tone.
- **Destructive button language on "Remove from iCloud":** Must name specific devices when possible. If we can detect paired devices or iCloud device list, show them. Otherwise generic ("your iPad, Apple Watch, and any other device signed into this iCloud").
- **One-time "Merged N duplicates" toast** is silent when N == 0. Never show an empty toast.
- **Restoring state timeout:** ~30 seconds is the starting tunable. Researcher should check typical iCloud Keychain propagation latency — may need to be longer (60s+) for cold sync across regions.

</specifics>

<deferred>
## Deferred Ideas

- **Per-account sync granularity** — e.g., "sync personal accounts but not work 2FA." Decided against as a v1 feature (global toggle only). If user demand surfaces post-ship, reconsider as a Phase 7 or v1.1 capability.
- **Review screen for duplicates** — user-facing duplicate resolution UI. Decided against (auto-dedup silently instead). If dedup accuracy proves insufficient in practice, revisit.
- **Backup codes / recovery codes** — separate security feature. Not part of this phase.
- **CloudKit-based sync** — alternative to iCloud Keychain for richer conflict resolution. Decided against (iCloud Keychain is simpler, free, zero external deps). Future reconsideration only if CloudKit offers a compelling capability (e.g., shared accounts across non-Apple-ID family members).
- **Re-pair-on-new-device flow** — when a user picks up a new iPhone, pairings don't sync (correctly). Future UX work to make the "re-pair Chrome extension on new iPhone" experience smoother belongs in a separate phase.
- **PROJECT.md Core Value rewording** — the phrase "secrets never leave the phone" is technically inaccurate once iCloud sync ships. Consider rewording to "secrets never leave your Apple devices" or "secrets never leave systems you control." Owner decision, not a phase task.

### Reviewed Todos (not folded)
_None — no todos were reviewed._

</deferred>

---

*Phase: 06-icloud-keychain-sync*
*Context gathered: 2026-04-17*
