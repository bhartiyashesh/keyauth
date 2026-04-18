---
phase: 6
slug: icloud-keychain-sync
status: draft
shadcn_initialized: false
preset: not applicable
created: 2026-04-17
platform: native-ios
ui_framework: SwiftUI
min_deployment: iOS 17+
---

# Phase 6 — UI Design Contract (iCloud Keychain Sync)

> Native iOS UI contract. No shadcn, no Tailwind. SwiftUI primitives only. Follows Apple Human Interface Guidelines. Adopts the existing KeyAuth app visual vocabulary (semantic colors, HIG text styles, `systemGroupedBackground`, blue accent, red destructive).

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native iOS, no component library) |
| Preset | not applicable |
| Component library | SwiftUI stdlib (`Form`, `Section`, `Toggle`, `NavigationStack`, `NavigationLink`, `.confirmationDialog`, `.sheet`, `ProgressView`, `Button`, `Label`) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (system default — no custom fonts; DxBurst is web-landing only and MUST NOT be used here) |

**Existing visual vocabulary adopted (do not invent new tokens):**
- Background: `Color(.systemGroupedBackground)`
- Card / row fill: `Color(.secondarySystemGroupedBackground)`
- Primary text: `.primary`
- Secondary text: `.secondary`
- Accent (interactive): `.blue` (matches `ContentView`, `LockScreenView`, `PairingView`, `CodeApprovalView`)
- Destructive: `.red` (matches `PairedDeviceView` Unpair, `AccountRowView` expiry warning)
- Success / confirmation: `.green` (matches "Copied" pill, `PairedDeviceView` paired icon)
- Warning / in-progress: `.orange` (matches connecting dot, mid-expiry ring)
- Icon-in-circle pattern: `Circle().fill(Color.blue.opacity(0.1)).frame(width: 88, height: 88)` + centered SF Symbol at `.font(.system(size: 36))`

---

## Spacing Scale

All values are multiples of 4. Matches the existing app (16 for row insets, 20/24 for stack gaps, 40 for horizontal screen padding).

| Token | Value | Usage in Phase 6 |
|-------|-------|------------------|
| xs | 4px | Icon-label gap inside buttons, `HStack(spacing: 4)` for status-dot rows |
| sm | 8px | Compact stack gaps (spinner + label), `Circle()` status-dot frame (8pt) |
| md | 16px | Form row insets, inline-card padding, `HStack(spacing: 16)` for row layout |
| lg | 24px | Vertical stack gaps on full-screen states ("Restoring…" spinner block), card padding |
| xl | 32px | Section breaks between the toggle row and the next subsection |
| 2xl | 40px | Horizontal screen padding on full-screen state views (`.padding(.horizontal, 40)`, matches `ContentView` empty state) |
| 3xl | 48px | Bottom padding under the primary button on full-screen flows (matches `LockScreenView`) |

**Exceptions:**
- Apple HIG minimum tap target: 44×44pt. The Settings deep-link button and "Stop syncing this device" / "Remove from iCloud" buttons must clear this. Vertical padding of 12pt on a 20pt label satisfies this.
- Icon-in-circle decorative size stays at 88×88pt (existing `ContentView.emptyState`, `PairingView`, `LockScreenView` convention). Do not renegotiate.

---

## Typography

Use **SwiftUI text styles**, not raw `.system(size:)`, wherever possible. Text styles scale with Dynamic Type automatically — this is non-negotiable for accessibility.

| Role | SwiftUI style | Weight | Usage in Phase 6 |
|------|---------------|--------|------------------|
| Title (section top) | `.title3` | `.semibold` | "Restoring your accounts from iCloud…" heading; Settings screen section-group titles if any |
| Heading (inline) | `.headline` | system default (semibold) | Disable-confirmation sheet title: "Disable iCloud sync?" |
| Body (primary copy) | `.body` | `.regular` | Toggle-row label "Sync with iCloud Keychain"; destructive-button labels; in-flow copy |
| Subheadline (supporting) | `.subheadline` | `.regular` | Description paragraph inside the first-launch card |
| Footnote (inline disclosure) | `.footnote` | `.regular` | Disclosure under the toggle (D-03 copy); iCloud-off inline copy (D-11); mid-session sign-out flag (D-12) — this is the native `Section` footer style |
| Caption (transient) | `.caption` | `.regular` | "Merged N duplicates" toast body |

**Weights used (exactly 2):** `.regular` (default) and `.semibold` (titles, primary CTA labels, destructive button label). No other weights.

**Line heights:** Defer to SwiftUI text style defaults (they already match HIG-correct heights — roughly 1.29 for body, 1.2 for headline). Do not override `.lineSpacing` on text styles.

**Dynamic Type:** Every text element above uses a style (not a hardcoded size), so Dynamic Type scales it. Do NOT hardcode `.font(.system(size:))` on Phase 6 copy except for decorative icon sizing.

**Monospaced:** Not used in Phase 6. (TOTP codes elsewhere use monospaced; no codes appear in this phase's surfaces.)

---

## Color

KeyAuth uses iOS **semantic colors**, not a custom palette. The 60/30/10 split applies as follows:

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `Color(.systemGroupedBackground)` | Settings screen background, full-screen state backgrounds (`Restoring…`, iCloud-off inline) |
| Secondary (30%) | `Color(.secondarySystemGroupedBackground)` | Form row backgrounds, inline first-launch card fill, confirmation sheet container |
| Accent (10%) | `.blue` (system blue) | Reserved-for list below |
| Destructive | `.red` (system red) | Reserved-for list below |
| Success (transient) | `.green` | Reserved-for list below |
| Warning (transient) | `.orange` | Reserved-for list below |

**Accent (`.blue`) is reserved for — explicit list, do not expand:**
1. The `Toggle` tint when sync is ON (system default for toggles, inherited)
2. "Open Settings" button on the iCloud-off disabled state (D-11)
3. "How is this secured?" expandable disclosure indicator (chevron + label color)
4. ProgressView tint during the >10-account migration (D-07)
5. ProgressView tint on the "Restoring from iCloud…" empty state (D-09)
6. The decorative icon-in-circle for the first-launch card (`icloud.and.arrow.up` at blue, `opacity(0.1)` circle fill — matches the app's established pattern)

**Destructive (`.red`) is reserved for:**
1. The "Remove from iCloud on all devices" button (D-05) — use `Button(role: .destructive)` which applies `.red` automatically; do not override
2. Nothing else in this phase

**Success (`.green`) is reserved for:**
1. The transient "Merged N duplicates" toast success icon (`checkmark.circle.fill`)
2. Nothing else in this phase

**Warning (`.orange`) is reserved for:**
1. Nothing in this phase (orange is already claimed by existing connection-dot "connecting" state in `ContentView` — do not reuse for sync state; in-progress sync uses blue ProgressView)

**Dark Mode:** Every color above is a semantic / system color, so Dark Mode is automatic with zero extra work. Do NOT introduce any hard-coded hex values. The first-launch card's `Color.blue.opacity(0.1)` fill resolves correctly in both modes because `.blue` is a dynamic system color.

---

## Copywriting Contract

**Voice rules (locked from CONTEXT.md D-03):**
- Plain language, trust-focused
- NO jargon in primary copy (no "E2E", "CryptoKit", "kSecAttr*", "synchronizable", "X25519")
- Jargon lives ONLY inside the optional "How is this secured?" expandable
- Apple HIG **sentence case** for all buttons and section titles (not Title Case)
- Destructive language must **name specific outcomes** (e.g., "removes from your iPad, Apple Watch, and any other device signed into this iCloud")

### Verbatim locked copy (use character-for-character from CONTEXT.md):

| ID | Copy (exact) |
|----|--------------|
| D-03 disclosure | *Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them.* |
| D-11 iCloud-off | *iCloud Keychain is turned off on this device.* |
| D-12 mid-session | *iCloud Keychain was disabled — sync stopped.* |

### Full copy table for every Phase 6 surface:

| Element | Copy |
|---------|------|
| Settings screen title | `Settings` |
| Settings → Sync section title | `Sync` (Form `Section("Sync")`) |
| Toggle label | `Sync with iCloud Keychain` |
| Toggle footer (inline disclosure, D-03) | *Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them.* |
| "How is this secured?" expandable — label | `How is this secured?` |
| "How is this secured?" expandable — body | *Your accounts are stored in iCloud Keychain. Apple encrypts them end-to-end using keys derived from your Apple ID and device passcode. Apple cannot read your 2FA secrets — not on their servers, not in transit.* (this section MAY use marginally more precise language since user opted in by expanding) |
| First-launch card title | `Sync across your Apple devices` |
| First-launch card body | *Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them.* (verbatim D-03 per D-04) |
| First-launch card CTA | `Got it` (dismisses card; does not toggle sync — sync is already ON for new users per D-01) |
| First-launch card secondary | `Manage in Settings` (opens Settings screen) |
| iCloud-off disabled state copy (D-11) | *iCloud Keychain is turned off on this device.* |
| iCloud-off "Open Settings" button | `Open iOS Settings` |
| Mid-session sign-out flag (D-12) | *iCloud Keychain was disabled — sync stopped.* |
| Restoring empty state title | `Restoring your accounts from iCloud…` |
| Restoring empty state body | *This usually takes a few seconds. You can leave this screen open.* |
| Restoring timeout fallback title | *(falls through to existing `ContentView.emptyState` — "No accounts yet" — no new copy needed)* |
| Migration progress (>10 accounts) title | `Moving your accounts to iCloud…` |
| Migration progress body | `{completed} of {total}` (dynamic; uses numerals) |
| Migration completion toast (N > 0) | `Merged {N} duplicate {account\|accounts}` (singular/plural; use `String.localizedStringWithFormat`) |
| Migration completion toast (N == 0) | *(silent — do not show)* |
| Disable confirmation sheet title | `Disable iCloud sync?` |
| Disable confirmation sheet body | *Choose what happens to the accounts already in iCloud.* |
| Disable option 1 (neutral) | `Stop syncing this device` |
| Disable option 1 description | *Your accounts stay on this iPhone. They remain in iCloud and on your other signed-in devices.* |
| Disable option 2 (destructive) | `Remove from iCloud on all devices` |
| Disable option 2 description | *This will remove your accounts from your iPad, Apple Watch, and any other device signed into this iCloud. Accounts on this iPhone stay.* |
| Disable cancel | `Cancel` (standard HIG confirmation dialog cancel) |
| Migration error toast (partial failure) | `Moved {ok} accounts. {failed} couldn't be moved — try again in Settings.` |

### Empty state taxonomy

| State | Surface | Copy |
|-------|---------|------|
| No accounts, sync OFF (existing) | `ContentView` empty state | `No accounts yet` / `Add a 2FA account to get started…` *(existing — unchanged)* |
| No accounts, sync ON, first launch of new user | `ContentView` + first-launch card above empty state | Card copy above + existing empty state below |
| No accounts, sync ON, fresh install on second device | `ContentView` replaced by "Restoring…" state | `Restoring your accounts from iCloud…` / spinner / *This usually takes a few seconds…* |
| Restoring timed out (~30s) | Fall through to existing `ContentView.emptyState` | `No accounts yet` (existing) — no new error copy |

### Error state taxonomy

| Error | Where | Copy | Recovery |
|-------|-------|------|----------|
| iCloud Keychain OFF at OS level | Settings toggle row footer | *iCloud Keychain is turned off on this device.* | `Open iOS Settings` button → `UIApplication.openSettingsURLString` |
| iCloud signed out mid-session | Settings toggle row footer (replaces disclosure until resolved) | *iCloud Keychain was disabled — sync stopped.* | No button — user resolves in iOS Settings; app polls on `scenePhase == .active` |
| Migration partial failure | Transient toast (same channel as "Merged N") | `Moved {ok} accounts. {failed} couldn't be moved — try again in Settings.` | User re-triggers by toggling off then on, or taps a "Retry migration" row that appears in Settings when `failedCount > 0` |
| Keychain error on save (rare) | Inline red `.footnote` under the toggle | `Couldn't update sync setting. Try again.` | Toggle reverts to previous state |

### Destructive actions

| Action | Confirmation pattern | Copy |
|--------|---------------------|------|
| "Remove from iCloud on all devices" | `.confirmationDialog` (native iOS; bottom-attached, action-sheet style on iPhone) with two labeled buttons per D-05 | See "Disable option 2" above. `Button(role: .destructive)` → auto-red. |

---

## Component Inventory (Phase 6 new surfaces)

SwiftUI-native only. No third-party components.

| Component | SwiftUI primitive | Notes |
|-----------|------------------|-------|
| `SettingsView` | `NavigationStack { Form { Section("Sync") { … } } }` | New file: `App/Views/SettingsView.swift`. Entry: `NavigationLink` pushed from `ContentView` toolbar (see Interaction section). |
| Sync toggle row | `Toggle("Sync with iCloud Keychain", isOn: $vm.syncEnabled)` | Inside `Section("Sync")` |
| Disclosure footer | `Section("Sync") { toggle } footer: { Text(d03Copy).font(.footnote).foregroundStyle(.secondary) }` | Native `Section` footer is the HIG-correct home for this copy |
| "How is this secured?" expandable | `DisclosureGroup("How is this secured?") { Text(techCopy) }` inside a secondary `Section` | Keeps the primary toggle area uncluttered |
| First-launch card | Inline `VStack` wrapped in `RoundedRectangle(cornerRadius: 16)` with `Color(.secondarySystemGroupedBackground)` fill, placed above `ContentView.emptyState` inside the existing `ScrollView`. Dismiss button (top-right `xmark.circle.fill` in `.secondary`). Persisted as `UserDefaults` bool `hasSeenSyncFirstLaunchCard`. | Mirrors `AccountRowView` card chrome (same corner radius, same fill) |
| iCloud-off disabled state | `Toggle(…).disabled(true)` + Section footer with the D-11 copy + a `Button("Open iOS Settings", action: openIOSSettings)` in a separate Section | "Open iOS Settings" is `.bordered` button style, blue tint (inherits) |
| Mid-session flag (D-12) | Section footer text replaces the default D-03 disclosure with D-12 copy when `syncState == .signedOut` | No modal, no alert. Silent inline per CONTEXT.md. |
| Disable confirmation | `.confirmationDialog("Disable iCloud sync?", isPresented: $showingDisableSheet, titleVisibility: .visible) { buttons } message: { Text(body) }` | Two buttons: "Stop syncing this device" (default role) and "Remove from iCloud on all devices" (`role: .destructive`) |
| Restoring empty state | New `RestoringFromCloudView`: `VStack(spacing: 24) { ProgressView().scaleEffect(1.4).tint(.blue); Text("Restoring…").font(.title3).fontWeight(.semibold); Text(body).font(.subheadline).foregroundStyle(.secondary) }` with `.padding(.horizontal, 40)` — mirrors `ContentView.emptyState` layout | Replaces `ContentView.emptyState` when `syncState == .restoring && accounts.isEmpty`. 30s timeout → fall through. |
| Migration progress (>10 accounts) | Inline `Section("Migrating") { HStack { ProgressView(value: Double(done)/Double(total)); Text("\(done) of \(total)") } }` in SettingsView. Disappears on completion. | Toggle is `.disabled(true)` during migration to prevent concurrent toggle (answer to "what happens if user taps during migration") |
| "Merged N duplicates" toast | New `TransientToastOverlay`: top-attached capsule, blue `secondarySystemBackground` fill, green `checkmark.circle.fill` icon, `.caption` copy, 3s auto-dismiss, `.transition(.move(edge: .top).combined(with: .opacity))`, library-free. | Silent when `N == 0`. Shown once after migration completes. |

---

## Interaction Patterns

### Settings entry (Claude's discretion per CONTEXT.md → decided here)

**Decision: Add a `ToolbarItem(placement: .primaryAction)` gear button to `ContentView`'s toolbar, to the LEFT of the existing add-account `+` menu. `NavigationLink` push, not modal sheet.**

Rationale:
- Existing `PairingView` uses `NavigationLink` push from the same toolbar (`ToolbarItem(placement: .navigationBarLeading)`). This is the established pattern — match it.
- Settings is a browse-and-configure surface, not a task with a commit/cancel boundary — `NavigationLink` matches iOS HIG for settings.
- Modal sheet would break the existing navigation rhythm (sheets in this app are for one-shot actions: scan QR, enter account, approve code).

Implementation sketch:
```swift
ToolbarItem(placement: .primaryAction) {
    NavigationLink { SettingsView() } label: {
        Image(systemName: "gearshape")
            .font(.title3)
    }
}
// existing Menu stays as a second .primaryAction ToolbarItem
```

### Toggle interaction state machine

| User state | Toggle state | Inline disclosure |
|------------|--------------|-------------------|
| iCloud Keychain OFF at OS level | Disabled (gray), shows current value (likely OFF) | D-11 copy + `Open iOS Settings` button |
| iCloud signed out mid-session (was ON) | Enabled visually but reflects forced-OFF state | D-12 copy |
| Sync OFF, user taps toggle → ON | Immediately shows ON; if >10 accounts, shows migration progress row below; toggle is `.disabled(true)` during migration | D-03 disclosure |
| Sync ON, user taps toggle → OFF | Intercept! Toggle snaps back to ON. `.confirmationDialog` appears with D-05 options. Only after user picks an option does toggle commit to OFF. If user taps Cancel, toggle stays ON. | D-03 (unchanged) |
| Migration in progress | Toggle disabled | Migration Section visible with progress |

### First-launch card lifecycle

- Shown only when: `isNewUser == true` AND `hasSeenSyncFirstLaunchCard == false` AND `accounts.isEmpty`
- Dismissed by: tapping `Got it`, or tapping the `xmark.circle.fill` close button, or adding a first account
- Persistence: `UserDefaults.standard.set(true, forKey: "hasSeenSyncFirstLaunchCard")` — NOT in iCloud (this is per-device UX state)
- Never shown to: existing users (D-02 — they default to sync OFF with no prompt)

### Restoring state lifecycle

- Enters when: fresh install AND iCloud signed in AND accounts.isEmpty AND AccountStore has not completed its first `reload()` AND iCloud Keychain items may propagate
- Exits when: first account arrives (immediate) OR 30s timeout (configurable constant) → fall through to `ContentView.emptyState`
- Spinner is `ProgressView()` tinted `.blue`, scaled 1.4x, placed inside the 88pt blue-tinted circle pattern for visual consistency with other empty states

### Disable confirmation dialog

Native `.confirmationDialog` (iPhone-appropriate; renders as bottom action sheet). Two actions:
1. `Button("Stop syncing this device") { … }` — default role, black text, no tint
2. `Button("Remove from iCloud on all devices", role: .destructive) { … }` — automatic red

Plus implicit `Cancel` (system-added for confirmationDialog with two+ actions).

### Toast placement and timing

- Position: top, below nav bar, horizontally inset 16pt
- Duration: 3 seconds auto-dismiss
- Animation: slide in from top + fade, slide out same
- Accessibility: `.accessibilityLabel("Merged \(n) duplicates")` + announces via `AccessibilityNotification.Announcement`

---

## Accessibility Contract

Required for every Phase 6 surface. Checker will audit.

| Element | VoiceOver label | Trait / role | Dynamic Type |
|---------|-----------------|--------------|--------------|
| Sync toggle | Inherits from `Toggle`: "Sync with iCloud Keychain, switch button, on/off" | `.isToggle` (default) | Yes (text style-based) |
| Disclosure footer | Inherits from `Text` inside `Section` footer | `.isStaticText` | Yes |
| "How is this secured?" DisclosureGroup | "How is this secured, collapsed/expanded" | `.isHeader` + `.isButton` (default) | Yes |
| First-launch card `Got it` | `accessibilityLabel("Dismiss sync onboarding")` | `.isButton` | Yes |
| First-launch card `xmark` | `accessibilityLabel("Dismiss")` | `.isButton` | Yes |
| Open iOS Settings button | `accessibilityHint("Opens the iOS Settings app")` | `.isButton` (default) | Yes |
| Restoring spinner | `.accessibilityLabel("Restoring your accounts from iCloud")` on the `ProgressView` | `.updatesFrequently` | Yes |
| Migration progress bar | `.accessibilityLabel("Migrating \(done) of \(total) accounts")` | `.updatesFrequently` | Yes |
| "Merged N duplicates" toast | `.accessibilityLabel("Merged \(n) duplicate accounts")` + `.accessibilityAddTraits(.isStaticText)` + fire `AccessibilityNotification.Announcement` on appear | — | Yes |
| Destructive confirmation "Remove from iCloud on all devices" | Inherits; VoiceOver will automatically announce "destructive" trait from `role: .destructive` | `.isButton` + destructive role | Yes |

**Dynamic Type:** Every visible string uses a SwiftUI text style (`.body`, `.footnote`, `.title3`, etc.), so type scales from xSmall through AX5. No hard-coded sizes in copy elements.

**Reduce Motion:** The toast transition should respect `@Environment(\.accessibilityReduceMotion)` — replace slide with a straight fade when reduced.

**Color contrast:** All copy uses `.primary` / `.secondary` against `Color(.systemGroupedBackground)` / `Color(.secondarySystemGroupedBackground)` — these combinations are WCAG AA compliant out of the box on both Light and Dark appearance.

---

## Dark Mode Contract

Every surface in Phase 6 must render correctly in Light, Dark, and Increase-Contrast variants. Because every color is semantic (no hex values), this is automatic. Verification during ui-audit:

- Screenshot `SettingsView` with toggle ON in Light + Dark → footer copy legible in both
- Screenshot first-launch card in Light + Dark → card chrome distinguishable from background in both
- Screenshot "Restoring…" state in Light + Dark → ProgressView `.blue` tint visible in both
- Screenshot disable confirmation in Light + Dark → destructive button red visible, "Stop syncing this device" black-text-on-light / white-text-on-dark
- Screenshot iCloud-off disabled toggle — gray-out rendering in both appearances

---

## Out of Scope (for this UI-SPEC)

- Custom fonts (DxBurst, etc.) — web landing-page only
- Custom color palette — semantic only
- Third-party component libraries
- Per-account sync toggles (CONTEXT.md Deferred)
- Duplicate resolution UI (CONTEXT.md Deferred — auto-dedup silently per D-08)
- Backup codes UI (CONTEXT.md Deferred)
- Android / web sync UI (CONTEXT.md out of scope)

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| none | — | not applicable (native iOS, no component registries in use) |

**No third-party SwiftUI component libraries are introduced in this phase.** All UI is built from SwiftUI stdlib primitives and SF Symbols. This keeps the iOS codebase at zero external dependencies (confirmed pattern from CONTEXT.md `code_context`: *"Zero external dependencies on iOS side — keep it that way."*).

---

## Pre-Populated Sources

| Source | Decisions Used |
|--------|---------------|
| CONTEXT.md | D-01 through D-14 (all 14 decisions) + Claude's Discretion (settings entry pattern, toast presentation, migration progress style, toggle-during-migration behavior) |
| REQUIREMENTS.md | Phase 6 success criteria (6 items) |
| ROADMAP.md | Phase 6 goal + success criteria |
| Existing codebase | `ContentView`, `AccountRowView`, `PairingView`, `PairedDeviceView`, `CodeApprovalView`, `LockScreenView`, `ManualEntryView`, `KeyAuthApp`, `AccountStore` — all visual tokens adopted from these |
| User input | 0 (all answers derivable from upstream + iOS HIG) |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending

---

*Phase: 06-icloud-keychain-sync*
*UI-SPEC drafted: 2026-04-17*
*Platform: Native iOS (SwiftUI), iOS 17+*
