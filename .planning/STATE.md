---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Phase 7 UI-SPEC approved
last_updated: "2026-04-19T15:23:48.670Z"
last_activity: 2026-04-19 -- Phase 7 planning complete
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 24
  completed_plans: 15
  percent: 63
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-14)

**Core value:** One-click TOTP code delivery from phone to browser — secrets never leave the phone
**Current focus:** Phase 06 — icloud-keychain-sync

## Current Position

Phase: 06 (icloud-keychain-sync) — EXECUTING
Plan: 6 of 6
Status: Ready to execute
Last activity: 2026-04-19 -- Phase 7 planning complete

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-relay-server P01 | 3min | 2 tasks | 9 files |
| Phase 01 P02 | 4min | 2 tasks | 4 files |
| Phase 01-relay-server P03 | 5min | 2 tasks | 2 files |
| Phase 01-relay-server P04 | 3min | 3 tasks | 1 files |
| Phase 02 P01 | 8min | 3 tasks | 4 files |
| Phase 02 P02 | 5min | 2 tasks | 6 files |
| Phase 03 P01 | 6min | 2 tasks | 15 files |
| Phase 03 P02 | 5min | 2 tasks | 6 files |
| Phase 06 P01 | 8min | 6 tasks | 12 files |
| Phase 06 P02 | 8min | 3 tasks | 4 files |
| Phase 06 P03 | 11min | 5 tasks | 9 files |
| Phase 06 P04 | 12min | 5 tasks | 6 files |
| Phase 06-icloud-keychain-sync P05 | 159min | 7 tasks | 11 files |
| Phase 06-icloud-keychain-sync P06 | 6min | 5 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Setup: TLS-only relay (no E2E encryption) — simplicity, user owns the relay, codes expire in 30s
- Setup: WebSocket relay over Bluetooth — Chrome extensions cannot use Web Bluetooth API
- Setup: Click-to-request flow — user initiates from extension, not auto-detect-push
- Setup: Railway for relay hosting — user's explicit preference, Vercel excluded
- Setup: APNs alert push (not silent) — silent push throttled at ~3/hour by Apple
- [Phase 01-relay-server]: Implicit room creation on first join -- no separate create API needed
- [Phase 01-relay-server]: 30-minute TTL default for room eviction, configurable via constructor
- [Phase 01-relay-server]: Room persists after client leave (D-06) -- TTL-based eviction handles cleanup
- [Phase 01-relay-server]: deviceToken stored on both Client and Room objects for APNs lookup flexibility
- [Phase 01-relay-server]: APNs push errors caught and logged, never thrown -- best-effort delivery
- [Phase 01-relay-server]: Support both APNS_KEY (base64) and APNS_KEY_PATH (file) for signing key flexibility
- [Phase 01-relay-server]: Dependency injection pattern for APNs test mocking (ESM-compatible)
- [Phase 01-relay-server]: ROOM_TTL_MINUTES env var defaults to 30 for configurable room eviction
- [Phase 01-relay-server]: APNs init wrapped in try/catch -- relay works without push credentials for local testing
- [Phase 01-relay-server]: noServer mode with manual handleUpgrade validates roomId and capacity before completing WebSocket handshake
- [Phase 02]: fileprivate(set) for RelayClient.state to allow WebSocketDelegate access within same file
- [Phase 02]: Separate WebSocketDelegate class avoids nonisolated conformance complexity on @MainActor class
- [Phase 02]: All relay protocol types colocated in CryptoBoxManager.swift for cohesion
- [Phase 02]: Closure callbacks (onDeviceToken, onNotificationTapped) on AppDelegate for APNs-to-SwiftUI communication
- [Phase 02]: PairingQRScannerView reuses QRCameraPreview -- same camera infra, only JSON parsing differs from QRScannerView
- [Phase 02]: aps-environment set to development -- switches to production automatically on App Store submission
- [Phase 03]: Used x25519.utils.randomSecretKey() for noble-curves v2 (v1 had randomPrivateKey)
- [Phase 03]: Noble v2 ESM imports require .js suffix on subpath exports
- [Phase 03]: MessageEnvelope.v typed as literal 1 for strict relay protocol conformance
- [Phase 03]: defineBackground used as WXT auto-imported global (not from wxt/sandbox)
- [Phase 03]: QR payload JSON matches iOS PairingQRPayload: { roomId, relayURL, publicKey }
- [Phase 03]: Service worker owns WebSocket; popup communicates via chrome.runtime.sendMessage only
- [Phase 06]: SyncPreference uses UserDefaults.standard (not App Group) — per-device UX state, not cross-process data
- [Phase 06]: KeyAuthTests added as TestableReference inside existing 'KeyAuth' scheme (no standalone scheme) — matches downstream plans 02-06
- [Phase 06]: KeychainProviding protocol declared in Shared/ with zero conformances; KeychainManager extension deferred to Plan 02
- [Phase 06]: Ruby xcodeproj gem used for all project.pbxproj edits to preserve UUIDs/scheme XML integrity
- [Phase 06]: [Phase 06]: service/accessGroup on KeychainManager changed from let to var to enable #if DEBUG test-only overrides; production API still immutable
- [Phase 06]: [Phase 06]: transient save(_:) shim retained in KeychainManager so AccountStore keeps compiling — TODO(Plan 03) removes it
- [Phase 06]: [Phase 06]: ICLOUD-13 static tests read Shared/*.swift via Bundle(for:).url(forResource:withExtension: 'swift.txt') — Run-Script build phase copies sources into the test bundle to bypass simulator sandbox
- [Phase 06]: [Phase 06]: KeychainProviding.swift and SyncPreference.swift wired into KeyAuthKeyboard target so the extension can compile the sync-aware KeychainManager
- [Phase 06]: Plan 03: AccountStore accepts injected KeychainProviding for testability; default remains KeychainManager.shared
- [Phase 06]: Plan 03: NSUbiquitousKeyValueStore accounts-version counter only bumps when SyncPreference.isEnabled (RESEARCH Open Q #6)
- [Phase 06]: Plan 03: ICloudStateObserver.previousIdentityToken typed AnyObject? (Apple opaque-token pattern) not the Swift 6-unfriendly existential composition
- [Phase 06]: Plan 03: Added com.apple.developer.ubiquity-kvstore-identifier entitlement (Rule 2) — required for KVS counter-ping to function in production and tests
- [Phase 06]: Plan 03: onChange(of:) uses iOS 16-compatible single-parameter form; project deployment target is 16.0 not 17.0
- [Phase 06]: Plan 04: D-05 per-option descriptions composed into .confirmationDialog message: closure as a multiline Text literal — SwiftUI cannot render per-Button inline descriptions
- [Phase 06]: Plan 04: Gear + Menu toolbar ordering via source-order (second source item appears LEFT due to Apple's right-to-left .primaryAction layout)
- [Phase 06]: Plan 04: SettingsView confirmationDialog action handlers are STUBS (setEnabled false + log for Stop syncing; log + bounce toggle ON for Remove) — Plan 06-05 wires MigrationCoordinator
- [Phase 06]: Plan 04: SettingsViewTests loads source via Bundle(for:).url(forResource:withExtension: 'swift.txt') — simulator sandbox blocks absolute #filePath reads; Run-Script build phase extended to copy the View files
- [Phase 06-icloud-keychain-sync]: Plan 05: Two-phase dedupInMemory in AccountStore — Phase 1 same-id variant collapse (in-memory only, no Keychain delete) resolves RESEARCH line 459 open question post-D-06; Phase 2 DedupKey cross-id dedup unchanged from plan spec
- [Phase 06-icloud-keychain-sync]: Plan 05: MigrationCoordinator created lazily in KeyAuthApp.onAppear via @State Optional + 'if let migration' body gate — works around SwiftUI's prohibition on cross-@StateObject references during View.init
- [Phase 06-icloud-keychain-sync]: Plan 05: RestoringFromCloudView.restoringTimeoutSeconds=30 is overridable via ContentView.evaluateRestoringState(timeout:) default parameter; RestoringStateTests injects 50ms for deterministic .restoring→.timedOut coverage (Blocker-3 closed)
- [Phase 06-icloud-keychain-sync]: Plan 05: DedupKey.swift added to KeyAuthKeyboard target (was missing from Plan 06-01) — AccountStore now references DedupKey and AccountStore is in the keyboard target
- [Phase 06-icloud-keychain-sync]: Plan 06: Hybrid coverage status vocabulary — Complete (automated) vs Complete (unit: TEST) / Manual QA pending 2-DEV-NN — preserves truth-in-claims while capturing real unit baselines for cross-device behaviors
- [Phase 06-icloud-keychain-sync]: Plan 06: TransientToastOverlay placement deferred to a polish plan — documented as non-orphan in TRACEABILITY.md Known Gaps since core dedup-count behavior is tested
- [Phase 06-icloud-keychain-sync]: Plan 06: ICLOUD-10 and ICLOUD-16 remain [ ] / Manual QA pending in REQUIREMENTS.md; 14 of 16 flipped to Complete (automated). ROADMAP Phase 6 does NOT flip to [x] until manual QA signs off 06-QA-CHECKLIST.md

### Pending Todos

None yet.

### Blockers/Concerns

- APNs p8 key and Team ID required before Phase 1 relay can send pushes — obtain from Apple Developer portal before starting Phase 2 work
- ~~Railway project must be created and CLI configured before Phase 1 deploy step~~ RESOLVED: deployed to cooperative-respect-production-29f8.up.railway.app

### Roadmap Evolution

- 2026-04-17: Phase 6 added — iCloud Keychain Sync (TOTP seed sync across Apple devices, user opt-in with migration)
- 2026-04-19: Phase 7 added — FaceID Capability Tokens (CTAP-inspired scoped+TTL authorization; mint after FaceID, reuse across {origin, account_id} for 5 min; eliminates re-prompts during re-auth loops without weakening phishing resistance)

## Session Continuity

Last session: 2026-04-19T14:29:18.034Z
Stopped at: Phase 7 UI-SPEC approved
Resume file: .planning/phases/07-faceid-capability-tokens/07-UI-SPEC.md
