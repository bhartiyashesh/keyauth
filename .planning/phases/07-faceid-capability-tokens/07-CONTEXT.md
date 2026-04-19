# Phase 7: FaceID Capability Tokens - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

After a FaceID-approved code request on the iOS app, open a **2-minute trust window** during which any subsequent code request from the **paired Chrome extension** is sent without re-prompting FaceID. Each silent send shows a brief toast on the phone so the user always knows a code went out. The window ends early when the app backgrounds or the iCloud account changes. Replaces the existing 5-minute Timer in `CodeApprovalView` that auto-pushes rotations for one account.

**Explicitly out of scope:**
- Per-account or per-origin scope refinement (single global window per pairing — the user explicitly rejected this complexity)
- "Lock now" UI button (the user rejected it — auto-revocation triggers are sufficient)
- Sliding-window TTL (each use does NOT extend; 2 min is fixed from the approval moment)
- Configurable TTL UI (2 min is the locked duration)
- Cross-pairing tokens (each pairing has its own independent window, but v1 is single-pairing per Phase 2 D-03)
- Phishing-origin enforcement at the token-check layer (origin is already captured but not used for scope matching — see "Security trade-off" below)

</domain>

<decisions>
## Implementation Decisions

### Trust Window Behavior
- **D-01:** A successful FaceID (or passcode-fallback per existing `BiometricAuthManager` policy) on a code request opens a **2-minute trust window**. Any subsequent code request received from the paired extension during the window is approved automatically without prompting FaceID.
- **D-02:** Window scope is **global per pairing** — covers any account and any site. The user explicitly chose simplicity over per-account/per-origin scope refinement.
- **D-03:** TTL is **fixed-from-mint** — exactly 2 minutes from the FaceID approval moment, regardless of how many silent sends occur during the window. Uses do NOT extend the window.
- **D-04:** Each FaceID approval restarts the window from a fresh 2 minutes. There is no way to extend a window without a new FaceID.

### Revocation Triggers (window ends early when ANY of these fire)
- **D-05:** App enters background (`UIApplication.didEnterBackgroundNotification`). This already triggers `isUnlocked = false` and `RelayClient.disconnect()` in `KeyAuthApp.swift` — the window invalidation hooks into the same lifecycle event.
- **D-06:** iCloud account change (`ICloudStateObserver.didAccountChange` becomes `true` — already wired in Phase 6).
- **D-07:** 2-minute timer expiry (the natural end).
- **D-08:** No "Lock now" button. The user explicitly rejected adding one. The three triggers above are sufficient.

### Silent-Send UX
- **D-09:** When a code is sent during an active window without FaceID, the phone shows a brief transient toast: **"Code sent for [issuer]"** (or "Code sent" if issuer is empty). Toast appears for ~2 seconds, then fades. Always visible — this is the user's only signal that a silent send happened.
- **D-10:** Toast must appear regardless of whether the app is foregrounded with `CodeApprovalView` open or backgrounded-then-foregrounded. If app is backgrounded the window is already revoked (D-05), so this case won't occur, but document the assumption.
- **D-11:** No `CodeApprovalView` sheet appears for silent sends — the toast is the entire UI for an in-window auto-approval. Sheet only appears for the FIRST request that mints the window OR after window expiry.

### Replacement of Existing 5-min Timer
- **D-12:** The current `CodeApprovalView.startAutoRefresh(account:)` Timer (5-min auto-push of TOTP rotations for one account) is **removed**. New behavior is purely request-driven: extension sends a `request_code` envelope when it needs a code; iOS sends one code per request, FaceID-gated or window-gated.
- **D-13:** Behavior change for existing users: codes no longer auto-arrive in the extension on TOTP rotation. The extension must explicitly request a fresh code if its cached one expires. The Phase 4 auto-fill flow already triggers `request_code` on TOTP-field detection, so this aligns with the intended UX.

### Security Trade-off (documented for planner + reviewer awareness)
- **D-14:** Choosing global scope means: if a phishing site triggers a `request_code` via the extension within 2 minutes of the user's last approval, that request will be auto-approved and a code sent. The user's only mitigation is the visible toast (D-09). This is the **deliberate trade-off** the user made when picking "any account, any site" scope. Document it explicitly in PLAN.md and surface it during code review.
- **D-15:** Origin is still captured by the extension via `chrome.tabs.query` (already implemented in `background.ts:351`) and travels in the encrypted `CodeRequest.domain` field. It is NOT used for window-scope checking in v1 (per D-02), but is still surfaced in the toast (D-09) and in any future per-origin capability token v2.

### Settings Surface
- **D-16:** A Settings toggle "Allow 2-minute trust window after FaceID" disables the entire feature. Default: **ON** for new users, **ON** for existing users (less restrictive than today, but aligned with the goal of reducing friction). When OFF, every request requires FaceID — same as today's behavior minus the Timer. Toggle lives in the existing `SettingsView` from Phase 6.
- **D-17:** When the toggle is OFF, no window is ever minted regardless of FaceID approvals.

### Claude's Discretion
- **In-memory token store architecture:** A singleton (e.g., `TrustWindowManager`) on `@MainActor` holding `windowExpiresAt: Date?`. Observes the three revocation triggers and exposes `isInWindow: Bool` to `RelayClient` / `CodeApprovalView` callers. NOT persisted to Keychain or `UserDefaults` — purely transient, reset on app launch.
- **Toast UI implementation:** Reuse the transient-overlay pattern referenced in Phase 6's deferred `TransientToastOverlay` (06 plan 06 deferred-polish item). Coordinate with that backlog if it exists; otherwise implement inline as a SwiftUI `.overlay(alignment: .top)` driven by an `@Published` toast state on the manager. Keep it dependency-free (Apple frameworks only — see PROJECT.md constraint).
- **`LAContext` reuse vs new context per send:** Phase description suggests `touchIDAuthenticationAllowableReuseDuration`. Up to the planner: either (a) hold one `LAContext` for 120s with `touchIDAuthenticationAllowableReuseDuration = 120` and rely on it, or (b) skip `LAContext.evaluatePolicy` entirely during the window (just emit the code based on `TrustWindowManager.isInWindow`). Option (b) is simpler and equivalent for our scope. Recommend (b) unless a security review surfaces a concrete reason to keep `LAContext` in the loop.
- **Background revocation timing:** `didEnterBackgroundNotification` fires the moment the app loses foreground (covered apps, app switcher, lock screen). No grace period — window dies instantly. This is the safest interpretation of D-05 and matches how `isUnlocked = false` already works.
- **Where to mint the window:** Inside `CodeApprovalView.approveAndSend` immediately after `BiometricAuthManager.shared.authenticate` returns `true`, before `RelayClient.shared.sendEncryptedCode`. The mint is conditional on `SyncPreference`-style enable check (D-17).
- **Where the silent path lives:** `RelayClient.handleMessage` (where `CodeRequest` is decoded today, around line 161-164 of `RelayClient.swift`) checks `TrustWindowManager.isInWindow`. If yes, looks up the account from request issuer/label, generates code, sends, fires toast — no `pendingCodeRequest` set. If no, falls through to today's `pendingCodeRequest = request` (which presents `CodeApprovalView`).
- **Account resolution for silent send:** Use the same matching logic as `CodeApprovalView.onAppear` (exact issuer+label match, then domain-match fallback for single-result, then single-account fallback). If multiple matches AND no exact issuer+label, the silent path MUST defer to FaceID (re-prompt). Document this fallback rule explicitly.
- **Toast text when issuer is empty (extension didn't send issuer/label):** Use the matched account's issuer for the toast.

### Folded Todos
_None — no pending todos matched this phase._

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### iOS Code (extend, do not replace)
- `Shared/BiometricAuthManager.swift` — Singleton with `authenticate(reason:) async -> Bool`. Already handles biometric → passcode fallback. Window mints on success regardless of method.
- `Shared/RelayClient.swift` §140-165 — Where `CodeRequest` is decoded and `pendingCodeRequest` is set. Silent-send branch goes here.
- `App/Views/CodeApprovalView.swift` §163-203 (`approveAndSend`) — Where the window mint goes. §205-240 (`startAutoRefresh`) — Method to be deleted per D-12.
- `App/KeyAuthApp.swift` §65-72 — Existing `didEnterBackgroundNotification` handler. Hook the window-revoke into this same site.
- `Shared/ICloudStateObserver.swift` — `didAccountChange: Bool` published property (Phase 6). Window observes this for revocation trigger D-06.
- `Shared/CryptoBoxManager.swift` §20-25 — `CodeRequest` struct (`id`, `issuer`, `label`, `domain?`). No new fields needed for v1 — origin trust deferred (see D-14/D-15).
- `Shared/AccountStore.swift` — Source of truth for account lookup during silent send (issuer/label matching).

### Chrome Extension (already complete — reference only)
- `extension/src/entrypoints/background.ts` §348-364 — Origin capture via `chrome.tabs.query`. Already in place; no extension changes needed for Phase 7 v1. The `domain` field in the encrypted `CodeRequest` payload is the origin signal.

### Phase 7 ROADMAP entry
- `.planning/ROADMAP.md` §124-138 — Phase 7 Goal, Description, Depends-on. Note that the description mentions `touchIDAuthenticationAllowableReuseDuration` and origin-scoped tokens — Claude's Discretion section covers the `LAContext` decision; D-14 documents the deliberate divergence on origin scoping.

### Apple Platform Docs (for researcher)
- `LAContext.touchIDAuthenticationAllowableReuseDuration` — Up to 5 min reuse window for biometric evaluation. Reference for the planner's `LAContext` reuse decision.
- `UIApplication.didEnterBackgroundNotification` — Already in use; confirm it fires for app switcher previews and lock screen.
- `Timer` invalidation lifecycle — for the 2-min countdown timer.
- App Store Review Guideline 5.1.1 (privacy, security) — silent send + toast UX should be reviewed for "user must be aware" compliance. The visible toast is the compliance signal.

### Prior Phase Context (decisions to honor)
- `.planning/phases/02-ios-relay-client-pairing/02-CONTEXT.md` D-08 — Biometric → passcode fallback policy. Window mints on either path.
- `.planning/phases/06-icloud-keychain-sync/06-CONTEXT.md` — `ICloudStateObserver` is the canonical source for D-06 trigger.
- `.planning/PROJECT.md` Constraints — "No external iOS dependencies." Window manager + toast must use only Apple frameworks.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BiometricAuthManager.shared.authenticate(reason:)` — call as-is; window mint is post-call.
- `ICloudStateObserver.shared.didAccountChange` — already `@Published`, observe via `.sink` or Combine in the new manager.
- `RelayClient.handleMessage` switch statement at `default:` branch — natural insertion point for the silent-send check.
- `CodeApprovalView.onAppear` account-matching logic — duplicate (or extract to a shared helper) for the silent-send path.
- Phase 6 `SyncPreference` pattern (UserDefaults-backed Bool with `bootstrap` + `setEnabled`) — clone the shape for the new `TrustWindowPreference` toggle (D-16).

### Established Patterns
- `final class … { static let shared … }` for stateful singletons (`BiometricAuthManager`, `RelayClient`, `PairingStore`, `AccountStore`).
- `@MainActor` ObservableObject when the singleton publishes UI-relevant state.
- Lifecycle observers wired in `KeyAuthApp.swift` `body` Scene closure.
- SwiftUI `@StateObject` injection from `KeyAuthApp` → `ContentView` → child views via `@EnvironmentObject`.
- Zero external dependencies on iOS — `Foundation`, `LocalAuthentication`, `CryptoKit`, `SwiftUI`, `Combine` only.

### Integration Points
- **`KeyAuthApp.swift`**: instantiate `TrustWindowManager.shared` (no-op singleton, but `@StateObject` it for dependency injection); wire revocation triggers (background notification, `ICloudStateObserver` Combine subscription) here.
- **`RelayClient.swift`**: silent-send branch in `handleMessage` `default:` clause; emits toast via the manager.
- **`CodeApprovalView.swift`**: mint window post-`authenticate` success; delete `startAutoRefresh` and its caller.
- **`SettingsView.swift` (from Phase 6)**: add the "Allow 2-minute trust window after FaceID" toggle row.
- **Toast overlay**: SwiftUI `.overlay(alignment: .top)` on `ContentView`, driven by `@Published var pendingToast: ToastMessage?` on `TrustWindowManager`.

</code_context>

<specifics>
## Specific Ideas

- **The user's exact framing:** *"if we request code and we approve with face id on the phone and we request again we should not need to have face id on the phone again, the app should share the code without faceid for 2 minutes."* This is the entire feature spec. Every implementation decision must serve this sentence.
- **2 minutes is a hard number, not a starting point.** Do not surface a TTL slider or "advanced settings" — the user explicitly chose simplicity over configurability.
- **Toast text exemplar:** "Code sent for GitHub" — short, declarative, names the issuer. NOT "Auto-approved" or "Token reused" or any jargon. The user must instantly understand what happened.
- **No "Lock now" UI** — the user rejected this explicitly. Don't add it back during planning.
- **Removing the existing 5-min Timer is a feature, not a regression.** Today's Timer surprises users with phantom code pushes. The new model is "ask, get one code, repeat as needed." Cleaner mental model.

</specifics>

<deferred>
## Deferred Ideas

- **Per-origin / per-account scoped tokens** — the original Phase 7 description proposed `{origin, account_id}` scope for phishing resistance. Deferred to a v2 (or Phase 8) if the global 2-min window's phishing exposure proves to be a real-world problem post-launch. The user explicitly chose global scope for v1 simplicity (D-02, D-14).
- **"Lock now" button** — explicitly rejected by user. If a future security incident makes manual lock necessary, revisit.
- **Configurable TTL** — fixed at 2 min. Reconsider only if user feedback says 2 min is too short or too long.
- **Sliding-window TTL** (each use extends the window) — rejected for simplicity (D-03). Reconsider if the 2-min cap proves frustrating in real usage.
- **Active-tokens UI** (list of live windows with per-token revoke) — not needed when there's only one global window per pairing.
- **`LAContext.touchIDAuthenticationAllowableReuseDuration`-based approach** — Claude's discretion suggests skipping `LAContext` reuse in favor of a pure timer flag. If a security reviewer requires staying in the `LAContext` evaluation flow, revisit.
- **Origin-strength upgrades** (eTLD+1 normalization via PSL, full-URL scoping, tabId binding) — only relevant if per-origin scope is reintroduced (above).
- **Persisting the window across app launches** — explicitly NOT done. Window dies on background; relaunch is always FaceID. Don't reconsider — this is core to the security model.
- **Requirements registration** — Phase 7 currently has TBD requirements. Planner should register `FIDO-01` through `FIDO-NN` covering: window mint trigger, 2-min duration, three revocation triggers, silent-send + toast UX, Timer removal, settings toggle, default ON behavior. Coordinate with REQUIREMENTS.md update.

### Reviewed Todos (not folded)
_None — no todos were reviewed._

</deferred>

---

*Phase: 07-faceid-capability-tokens*
*Context gathered: 2026-04-19*
