---
phase: 7
slug: faceid-capability-tokens
status: draft
shadcn_initialized: false
preset: not applicable
created: 2026-04-19
platform: native-ios
ui_framework: SwiftUI
min_deployment: iOS 16+
language: English only (matches `App/KeyAuthApp.swift`, no `Localizable.strings` in target)
---

# Phase 7 — UI Design Contract (FaceID Capability Tokens)

> Native iOS UI contract. Additive to Phase 6. This phase introduces exactly **two UI surfaces**: (1) a transient top-of-screen toast that fires when a silent in-window code is sent, and (2) a single `Toggle` row inside the existing `SettingsView`. Every token in this contract is inherited verbatim from Phase 6 `06-UI-SPEC.md` — no new palette, no new spacing, no new typography. Zero new dependencies (PROJECT.md constraint).

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native iOS, no component library) |
| Preset | not applicable |
| Component library | SwiftUI stdlib (`Toggle`, `Section`, `Form`, `Capsule`, `Image(systemName:)`, `Text`, `HStack`, `.overlay(alignment: .top)`, `.transition`) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (system default) — no custom fonts; Dynamic Type scales via SwiftUI text styles |
| Source of truth for tokens | `.planning/phases/06-icloud-keychain-sync/06-UI-SPEC.md` (do not re-specify; inherit) |

**Reuse targets (do not invent):**
- `App/Views/TransientToastOverlay.swift` — existing 42-LOC capsule overlay (Phase 6). Phase 7 parameterizes its `duration` property from hardcoded `3.0` → default-keeping `3.0` with a Phase-7 caller passing `2.0`. Single-line additive change.
- `App/Views/SettingsView.swift` — existing Phase 6 `Form { Section { Toggle … } }` container. Phase 7 adds exactly one `Section` with one `Toggle` row.
- `Shared/SyncPreference.swift` — shape-clone target for `TrustWindowPreference` (not a UI component, but binds the new Toggle).

---

## Component Inventory (exactly 2)

| # | Component | Status | File | Phase-7 changes |
|---|-----------|--------|------|-----------------|
| 1 | `TransientToastOverlay` | **Reused** (Phase 6) | `App/Views/TransientToastOverlay.swift` | Add `duration: Double = 3.0` property; replace hardcoded `3.0` in `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` with `.now() + duration`. Caller site for Phase 7 passes `2.0`. Nothing else changes inside the component. |
| 2 | `TrustWindowToggleRow` | **New** (inline inside `SettingsView`) | `App/Views/SettingsView.swift` (added `Section`) | Not a separate file — a second `Section { Toggle … } footer { Text … }` added below the existing Sync section. Visual parity with the Phase 6 Sync toggle is mandatory (inherit `Form` row chrome, `.regular`/`.footnote` typography, semantic colors). |

**Explicitly NOT introduced:**
- No new SwiftUI `View` struct file. `TrustWindowToggleRow` is a private computed var `trustWindowSection: some View` on `SettingsView`.
- No new overlay container. The existing `TransientToastOverlay` is mounted once on `ContentView.body` at the same hierarchy level as `.sheet(item: $relayClient.pendingCodeRequest)` and driven by `@EnvironmentObject var trustWindow: TrustWindowManager`'s `@Published var pendingToast: ToastMessage?`.
- No "Lock now" button (CONTEXT.md D-08 rejects this).
- No TTL slider, advanced settings, per-origin UI, per-account UI, active-tokens list (CONTEXT.md Deferred Ideas).
- No visual changes to `CodeApprovalView`, `ContentView` account list, empty state, pairing screen, or any other Phase 1–6 surface.

---

## Spacing Scale

Inherited from Phase 6 (multiples of 4 only):

| Token | Value | Usage in Phase 7 |
|-------|-------|------------------|
| xs | 4px | (not used in Phase 7 surfaces) |
| sm | 8px | Toast: `HStack(spacing: 8)` between SF Symbol icon and `Text`; toast top-edge inset from safe area (`.padding(.top, 8)`) |
| md | 16px | Toast: horizontal outer padding from screen edges (`.padding(.horizontal, 16)`), matches existing `TransientToastOverlay.swift:28` |
| lg | 24px | (not used in Phase 7 surfaces — Settings Form rows inherit default `Form` insets from iOS) |

**Toast internal padding (verbatim from existing component):**
- Horizontal: 12px
- Vertical: 8px
- Capsule shape; no border; no manual shadow (system capsule fill provides the subtle elevation)

**Settings row padding:** Inherited from SwiftUI `Form` — do NOT override. `.listRowInsets` is not applied. The existing Phase 6 sync toggle row sets the visual rhythm; the new row sits in a sibling `Section` directly below and matches height + padding exactly because both use the same `Form { Section { Toggle } }` primitive.

**Apple HIG tap target (44×44pt minimum):** SwiftUI `Toggle` inside `Form` already clears this. No manual padding needed.

**Exceptions:** None.

---

## Typography

Use **SwiftUI text styles** (never raw `.system(size:)`). This is non-negotiable for Dynamic Type accessibility.

| Role | SwiftUI style | Weight | Usage in Phase 7 |
|------|---------------|--------|------------------|
| Body (primary) | `.body` | `.regular` | Settings toggle label: "Allow 2-minute trust window after FaceID" |
| Footnote (inline disclosure) | `.footnote` | `.regular` | Settings section footer helper text (see Copywriting Contract) — uses the native `Section { … } footer: { Text(…).font(.footnote).foregroundStyle(.secondary) }` style, matching the Phase 6 `syncSection` footer exactly |
| Caption (transient) | `.caption` | `.regular` | Toast body text: "Code sent for GitHub" |

**Weights used (exactly 2):** `.regular` (default) and `.semibold` (inherited from text styles — `.headline`/title styles that Phase 7 does NOT introduce, but inherit if Settings renders a section header; Phase 7 does not add a new section header).

**Dynamic Type:** Toast `.caption` scales with the user's preferred text size up through `.accessibility5` via SwiftUI defaults. Toast capsule expands vertically; horizontal wrapping is single-line (issuer names are short). If issuer name + "Code sent for " exceeds capsule width at XXL sizes, the capsule grows vertically and the text truncates with tail ellipsis at the SwiftUI default — acceptable because the first word "Code sent" is always visible.

**Monospaced:** Not used in Phase 7 (no TOTP digits are rendered by Phase-7 surfaces).

**Line heights:** Defer to SwiftUI text style defaults. Do not override.

---

## Color

Inherited from Phase 6. Zero new tokens. iOS semantic colors only.

| Role | Value | Phase-7 usage |
|------|-------|---------------|
| Dominant (60%) | `Color(.systemGroupedBackground)` | Settings screen background (inherited from Phase 6 `SettingsView`) |
| Secondary (30%) | `Color(.secondarySystemBackground)` | Toast capsule fill (`Capsule().fill(Color(.secondarySystemBackground))`, matches existing `TransientToastOverlay.swift:27`) |
| Secondary (30%) | `Color(.secondarySystemGroupedBackground)` | Settings Form row background (inherited from Phase 6) |
| Accent (10%) | `.blue` | Reserved list below |
| Destructive | `.red` | Not used in Phase 7 (no destructive actions — toggling OFF is reversible and non-destructive; no "Remove" language) |
| Text primary | `.primary` | Toggle label, toast body text (via `.caption` default) |
| Text secondary | `.secondary` | Section footer helper text, toast icon (see below) |

**Accent (`.blue`) is reserved for — explicit list, do not expand:**
1. The `Toggle` tint when the trust-window feature is ON (system default for toggles, inherited — do NOT override with `.tint(.blue)`, let SwiftUI paint it)
2. Nothing else in Phase 7

**Toast icon color:** `.secondary` (not `.blue`). Rationale: the toast is informational, not a state change the user acted on. Using `.secondary` keeps it visually quiet and prevents the toast from competing with the `.blue` accent reserved for the toggle state. The icon is the visual anchor; color is not the signal.

**Dark Mode:** Every color above is a semantic system color. Dark Mode adapts automatically with zero additional code. No hex values introduced. The capsule `Color(.secondarySystemBackground)` resolves to a dark-gray fill in Dark Mode that remains visually distinct from `Color(.systemBackground)` — same behavior as every other iOS-native toast.

**High Contrast / Increase Contrast:** iOS semantic colors automatically adjust. No override required.

---

## Copywriting Contract

All strings verbatim. Any edit must update this spec in the same commit (checker grep-asserts).

### Toast (silent-send confirmation)

| Condition | Copy |
|-----------|------|
| Matched account has a non-empty issuer | `"Code sent for %@"` (Swift `String.localizedStringWithFormat` with matched `account.issuer`; for new-user exemplar, renders as `"Code sent for GitHub"`) |
| Matched account has empty issuer OR no account matched (defensive fallback) | `"Code sent"` |
| Toast MUST NOT render | When the user is currently inside the FaceID mint flow (sheet is visible) — mint-flow feedback is the existing `codeSent = true` "Sent" `Label` inside `CodeApprovalView.swift:116-120`, NOT this toast. (See D-11 + RESEARCH.md Pitfall 3.) |

**Banned alternatives (do NOT substitute):**
- "Auto-approved" — exposes jargon
- "Token reused" — exposes jargon
- "Silent send" — leaks implementation
- "✓ Sent" — ambiguous (could be confused with the mint-flow confirmation)

**Rationale:** CONTEXT.md §Specifics: *"Toast text exemplar: 'Code sent for GitHub' — short, declarative, names the issuer."*

### Settings toggle row

| Element | Copy |
|---------|------|
| Toggle label | `"Allow 2-minute trust window after FaceID"` |
| Section header | (no header — toggle sits in its own `Section` with only a footer; Phase 6 Sync section also uses a header, so for visual rhythm the planner MAY add a `Text("Security")` header if a header is needed to separate from the Sync section. See Open Question 1 below.) |
| Section footer helper text | `"Skip FaceID for requests within 2 minutes of approval. Each new FaceID starts a fresh 2 minutes. The window ends when the app goes to the background."` |

**Verbatim rationale for helper text:**
- "Skip FaceID for requests within 2 minutes of approval." — captures D-01 + D-03.
- "Each new FaceID starts a fresh 2 minutes." — captures D-04 (explicit non-sliding-window semantics that users might assume without prompting).
- "The window ends when the app goes to the background." — captures D-05 (the single most user-visible revocation trigger; D-06 and D-07 need no user-facing explanation).

**Banned phrasings in helper text:**
- "Trust window" — jargon; users do not know this term
- "Capability token" — jargon (internal name, never user-visible)
- "TTL" / "expiry" / "revocation" — jargon
- "5 minutes" (old `CodeApprovalView.startAutoRefresh` value; D-12 removes this behavior; referencing it would confuse users who remember it)
- "iCloud" — irrelevant here; D-06 iCloud-change revocation is covered silently by existing Phase 6 copy when that state triggers

**Default state copy:** None required. The toggle renders `ON` for all users (D-16). No empty state, no error state, no toast for toggle-flip.

### Error state

**None.** Phase 7 has no user-visible error surfaces:
- Toggle flip cannot fail (UserDefaults write is synchronous and infallible in our usage).
- Silent-send failure (WebSocket `send` errors) is not surfaced to the user in Phase 7 — consistent with the existing `CodeApprovalView.approveAndSend` which is also fire-and-forget (RESEARCH.md Pitfall 5 + Open Question 2). If the send fails, the extension eventually times out and re-requests; the user re-experiences the normal FaceID flow. No Phase-7 copy covers this case.

### Destructive actions

**None.** Toggling OFF is reversible; no data deletion; no confirmation dialog; no destructive copy. (Contrast Phase 6, which had the destructive "Remove from iCloud on all devices" path.)

### Primary CTA

**None.** Phase 7 has no CTA. The toggle is the only interactive element; toggle actions do not use CTA semantics.

---

## Iconography

Exactly **one SF Symbol** introduced by Phase 7. Everything else is inherited or absent.

### Toast icon decision

**Chosen symbol:** `paperplane.fill`

| Candidate | Verdict | Rationale |
|-----------|---------|-----------|
| `paperplane.fill` | **CHOSEN** | Matches the toast verb "sent." iOS system precedent: Messages uses `paperplane` for send actions. AirDrop confirmation also uses a send-metaphor glyph. The user's mental model is "I sent a code to the browser," and the icon reinforces that verb directly. [VERIFIED: existing code — the Phase 6 `ContentView` does not use this symbol, so there is no conflict with an existing meaning.] |
| `checkmark.circle.fill` | Rejected | Already reserved in Phase 6 UI-SPEC for the "Merged N duplicate accounts" success toast. Reusing here would conflate two different semantics (merge vs send) under the same visual. |
| `faceid` | Rejected | The toast is the moment FaceID was **skipped**. Showing the FaceID symbol would be misleading. |
| `bolt.fill` / `sparkles` | Rejected | Jargon visuals — "instant" / "magic." User should understand what happened; cuteness obscures that. |
| No icon | Rejected | `TransientToastOverlay` signature already requires `icon: String` (a non-optional parameter since Phase 6). Changing the signature to make it optional is out of Phase-7 scope. The icon also serves users with low literacy / Dynamic Type truncation by carrying semantic weight beyond the text. |

**Size:** SwiftUI default for `Image(systemName:)` inside `.caption` text — no manual sizing. The existing `TransientToastOverlay` does not size the image, and Dynamic Type scales it alongside the text.

**Color:** `.secondary` (see Color section above).

### Settings row iconography

**None.** The toggle row has no leading icon — matches the Phase 6 Sync toggle row exactly (no icon on that row either). SwiftUI `Toggle("…", isOn: …)` renders label + control only.

---

## Interaction Patterns

### Toast (silent-send confirmation)

**Lifecycle:**
```
idle ──(silent-send fires)──▶ appearing (transition in, ~200ms)
                              │
                              ▼
                            visible (remains up to 2.0s)
                              │
                              ▼
                            fading (transition out, ~200ms)
                              │
                              ▼
                            dismissed (pendingToast = nil)
```

**Trigger:** `TrustWindowManager.showToast(for: account.issuer)` sets `@Published var pendingToast: ToastMessage?`. Called from `RelayClient.handleMessage` silent-send branch AFTER `sendEncryptedCode` returns (fire-and-forget; see RESEARCH.md Pitfall 5).

**Duration:** 2.0 seconds total visible window (CONTEXT.md D-09). This is passed as the `duration` parameter to the parameterized `TransientToastOverlay`. The existing Phase 6 value of 3.0 is preserved as the component's default; Phase 7 is the explicit 2.0 caller. Phase 6's never-fired instance is unaffected because it is never mounted.

**Position:** `.overlay(alignment: .top)` on `ContentView.body` at the same hierarchy level as the existing `.sheet(item: $relayClient.pendingCodeRequest)` modifier.

**Safe area:** The overlay is attached to `ContentView.body` which is inside `NavigationStack`. SwiftUI's `.overlay` respects the safe area by default — the toast appears below the notch/Dynamic Island. An explicit `.padding(.top, 8)` (sm token) adds the standard iOS breathing room between the status bar and the capsule top edge.

**Animation:**
- Transition (inherited from `TransientToastOverlay.swift:29-31`):
  - Reduce-Motion OFF: `AnyTransition.move(edge: .top).combined(with: .opacity)` (slides down from above and fades in)
  - Reduce-Motion ON: `AnyTransition.opacity` (straight opacity fade — no motion)
- Animation driver (NEW — added when mounting on `ContentView`): `.animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)`.

**Sheet/overlay interaction:**
- While `CodeApprovalView` sheet is presented (mint flow), the overlay is OBSCURED by the sheet — standard SwiftUI behavior. The Phase 7 design never fires a toast during the mint flow (mint-flow uses the existing inline "Sent" label inside the sheet). So the obscuration never matters in practice. [CITED: RESEARCH.md Pitfall 3 + simplykyra.com on SwiftUI overlay-sheet interaction]
- After the sheet dismisses, the overlay is visible above `ContentView`. Silent sends occur ONLY after the sheet is gone (D-11).
- **Invariant** (document for reviewers): First request of a session → sheet visible → mint on approve → sheet auto-dismisses after 1.5s → window is now open → subsequent requests within 2 min are silent and show toast. Toast never visually collides with the sheet.

**Tap / swipe dismiss:** **Not implemented.** Rationale:
1. The 2-second auto-fade is the entire UX — matching iOS system toasts (AirDrop "Sent," Control Center copy confirmations, iOS 16+ Live Activity mini-feedback).
2. The capsule is a small top-of-screen target. Adding tap-to-dismiss invites accidental interactions while the user is actively using the app underneath.
3. No competing iOS system toast (Apple's own) supports tap-dismiss. Users expect passive transient feedback.
4. If the user needs a log of silent sends, that is a deferred (v2) "activity log" feature.

**Queue behavior (rapid silent sends within the 2s window):** **Latest wins, timer resets.** When a second silent send fires before the first toast's 2s timer has elapsed:
1. `TrustWindowManager.showToast(for:)` is called again.
2. `toastTimer?.invalidate()` cancels the pending dismiss.
3. `pendingToast` is reassigned to the new `ToastMessage` — SwiftUI's `.animation(.easeInOut(duration: 0.2), value:)` animates the text crossfade since the `ToastMessage.id` (UUID) changes.
4. A fresh 2s timer starts.

**Rationale:** Queueing multiple toasts would require a persistent view stack that contradicts the "transient" mental model. CONTEXT.md D-09 frames the toast as "the user's only signal that a silent send happened" — for the rapid-fire case, the user still sees at least one toast; the newest is the most relevant (current request). In practice, Chrome-extension-driven rapid fire is unlikely within 2 min (human-speed re-auth loops are seconds-apart, not milliseconds-apart), so Pitfall 4 is a degenerate case the Phase-7 design accepts. [CITED: RESEARCH.md Pitfall 4]

**Cross-phase consistency:** The Phase 6 "Merged N duplicates" toast uses the identical `TransientToastOverlay` at `.overlay(alignment: .top)` with `checkmark.circle.fill` + `.green`. Phase 7's "Code sent for X" toast uses the same overlay with `paperplane.fill` + `.secondary`. Both toasts share capsule shape, horizontal padding, transition, and safe-area behavior. A user who sees both during a session perceives a consistent transient-feedback language. The ONLY visual distinction is icon + color (semantic difference: success vs informational).

### Settings toggle row

**Lifecycle:**
```
idle → flipped → idle
```

**States:**
- `on` (default for all users per D-16)
- `off` (user-toggled)

**No disabled state.** Unlike Phase 6's Sync toggle (which disables during iCloud-off state and migration), Phase 7's toggle has no external dependencies — it is a pure UserDefaults boolean. It can always be flipped.

**No confirmation dialog.** Toggle flip applies immediately:
- ON → OFF: `TrustWindowPreference.setEnabled(false)` → future mint calls become no-ops (D-17); any currently-active window continues to expire naturally (the toggle does NOT force-revoke in-flight windows — the next revocation trigger handles it). The user has no way to observe an "in-flight window" anyway, so this distinction is invisible.
- OFF → ON: `TrustWindowPreference.setEnabled(true)` → future FaceID approvals mint normally; the current session's next approval is the first one that benefits from the window.

**No toast on flip.** The toggle's visual state (slider animating) is sufficient feedback — matches every other SwiftUI `Toggle` in the app. No "Trust window enabled" toast (would be noise).

**VoiceOver label:** Inherited from `Toggle("Allow 2-minute trust window after FaceID", isOn: $enabled)` — SwiftUI emits the correct accessibility trait (`.isToggle`) and announces the label + state. No custom `.accessibilityLabel` needed.

---

## Accessibility

### Toast

- **VoiceOver:** The existing `TransientToastOverlay.swift:32` already calls `.accessibilityLabel(message)` on the capsule. For Phase 7 the caller passes the full rendered string (e.g., `"Code sent for GitHub"`), which VoiceOver reads when it focuses the toast.
- **Announcement (post-focus):** A 2-second transient that may appear without user focus MUST also be announced unprompted. The planner MUST additionally post `UIAccessibility.post(notification: .announcement, argument: toast.text)` at the moment `pendingToast` is set (implementation lives inside `TrustWindowManager.showToast(for:)` to keep the announcement co-located with the visual trigger). This follows Apple's HIG accessibility guidance for transient status feedback — without it, VoiceOver users would never learn a silent send occurred.
- **Dynamic Type:** `.caption` scales with the user's preferred size through `.accessibility5`. The capsule grows vertically; single-line truncation with tail ellipsis is the default at the largest sizes. Acceptable because "Code sent" (first phrase) is always visible.
- **Reduce Motion:** Handled by the existing component — opacity-only fade when `accessibilityReduceMotion == true`.
- **Increase Contrast:** Semantic colors adapt automatically.
- **Color blindness:** Icon carries redundant meaning alongside text — does not rely on color to convey "sent" state.

### Settings toggle

- **VoiceOver:** Inherited from SwiftUI `Toggle`. Reads "Allow 2-minute trust window after FaceID, switch button, on/off." No custom hint needed — the label is self-explanatory and the footer (if VoiceOver lands there next) provides context.
- **Dynamic Type:** Toggle label (`.body`) scales through `.accessibility5`; footer (`.footnote`) also scales. Text wraps within the row — Form row auto-grows in height.
- **Hit target:** SwiftUI `Toggle` inside `Form` is already 44pt+ tall.
- **Focus order:** Sits in the natural form order below the existing Sync section. No manual focus override.

---

## Cross-phase Consistency Checklist

These constraints ensure Phase 7 surfaces feel like part of the same app as Phase 1–6:

- [x] **Toggle visual rhythm matches Phase 6 Sync toggle.** Same `Form { Section { Toggle } footer: { Text } }` primitive. Same `.body` label, same `.footnote` footer, same `.secondary` footer color, same system-default toggle tint. No custom spacing, no `.listRowBackground`, no `.listRowInsets` overrides.
  - Reference: `App/Views/SettingsView.swift:89-103` (Phase 6 `syncSection`) — planner must pattern-match this exactly.
- [x] **Toast reuses existing `TransientToastOverlay` component.** Does NOT introduce a second toast primitive. Phase-6 and Phase-7 toasts share capsule, padding, transition, reduce-motion behavior.
  - Reference: `App/Views/TransientToastOverlay.swift:1-42`.
- [x] **Color tokens are inherited verbatim from Phase 6 UI-SPEC.** No new hex values. No new palette. No extension to the Accent reserved-for list.
- [x] **No new SF Symbols beyond `paperplane.fill` are introduced.** All other imagery reuses what Phase 6 already established (or uses nothing).
- [x] **English-only.** Matches the rest of the app (no `Localizable.strings` exists; PROJECT.md does not mandate localization).
- [x] **Dark Mode and Increase Contrast work automatically** via semantic colors. No testing checklist item required beyond "visually confirm toast is legible in Dark Mode" during manual QA.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| (native iOS — no registry) | none | not applicable |

No shadcn, no third-party SwiftUI libraries, no package-manager dependencies. PROJECT.md Constraints: *"No external iOS dependencies. The iOS app has zero third-party packages — keep it that way."* All SwiftUI primitives, SF Symbols, and the one reused `TransientToastOverlay` are in-repo or Apple-framework-provided. Vetting gate does not apply.

---

## Open Questions for Planner

1. **Section header for the new toggle in `SettingsView`?**
   - Phase 6 Sync section uses `header: { Text("Sync") }`. The new trust-window toggle is a security preference.
   - **Recommendation:** Add `header: { Text("Security") }` to the new section. Rationale: (a) visual rhythm — a headerless section below a headered section reads as orphaned; (b) future-friendly — a "Security" section can absorb later biometric-preference toggles without renaming; (c) zero extra copy cost.
   - Planner decides: confirm with checker. If declined, the section renders with only a footer — still valid, just less visually structured.

2. **Ordering within `SettingsView`?**
   - Phase 6 currently renders: `syncSection` → (optional) `migrationProgressSection` → (optional) `openSettingsSection` → `securedSection` ("How is this secured?").
   - **Recommendation:** Insert the new `trustWindowSection` BETWEEN `syncSection` and the conditional Phase-6 sections. Rendered order becomes: `syncSection` → `trustWindowSection` → conditional Phase-6 sections → `securedSection`. Rationale: trust window is a primary preference (same tier as sync), not a conditional state block. Placing it above the conditional blocks reads naturally for users arriving to flip the toggle.
   - Planner decides. Any order that keeps `syncSection` first and `securedSection` last is acceptable.

3. **Toast announcement API — `UIAccessibility.post` vs `AccessibilityNotification.Announcement`?**
   - iOS 17+ introduces `AccessibilityNotification.Announcement(…).post()`. Our deployment target is iOS 16. Use `UIAccessibility.post(notification: .announcement, argument: …)` — available since iOS 3, no deprecation.
   - **Recommendation:** `UIAccessibility.post(notification: .announcement, argument: toast.text)`. Planner: confirm with checker.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS (exact strings defined; helper text fits D-01/D-03/D-04/D-05; no jargon; no banned phrasings)
- [ ] Dimension 2 Visuals: PASS (component inventory = 2 items; one SF Symbol chosen with rationale; icon role explicit)
- [ ] Dimension 3 Color: PASS (all tokens inherited from Phase 6; zero new palette; accent reserved-for list explicit)
- [ ] Dimension 4 Typography: PASS (3 text styles declared, 2 weights max, all Dynamic-Type-safe via SwiftUI styles)
- [ ] Dimension 5 Spacing: PASS (multiples-of-4 scale, toast internals inherited verbatim from existing `TransientToastOverlay`, Form rows use SwiftUI defaults)
- [ ] Dimension 6 Registry Safety: PASS (native iOS, no registry, Apple frameworks only)

**Approval:** pending
