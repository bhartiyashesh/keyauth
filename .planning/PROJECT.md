# KeyAuth — Better Authenticator

## What This Is

A cross-platform TOTP authenticator that eliminates 2FA friction. An iOS app with a custom keyboard extension inserts codes directly into any text field. A Chrome extension requests codes from the phone over an E2E encrypted relay — one click, FaceID approve, code appears. Smart sorting, batch import, and guided onboarding make it the authenticator people actually want to switch to.

## Core Value

2FA codes appear exactly where you need them — in the keyboard, in the browser — with zero friction, zero clipboard, zero app-switching. Secrets never leave the phone.

## Current Milestone: v2.0 Beautiful, Seamless, Untouchable

**Goal:** Complete the core extension flow and make KeyAuth the authenticator people actually want to switch to by solving the pain points that plague every competitor.

**Target features:**
- Complete v1.0 core (code display, autofill, resilience)
- Smart keyboard (recency sorting, search/filter)
- Google Authenticator batch import
- Onboarding flow + keyboard activation guide
- Encrypted backup export

## Requirements

### Validated

- ✓ TOTP generation (RFC 6238, SHA-1/256/512) — v1.0
- ✓ Account management (add/edit/delete, QR scan, manual entry) — v1.0
- ✓ Biometric authentication (Face ID/Touch ID) — v1.0
- ✓ Keyboard extension with tap-to-insert — v1.0
- ✓ Shared data via App Groups + Keychain — v1.0
- ✓ WebSocket relay server on Railway (rooms, APNs, health check) — v1.0 Phase 1
- ✓ iOS relay client + push notification handling — v1.0 Phase 2
- ✓ QR code pairing between extension and phone — v1.0 Phase 2-3
- ✓ Chrome extension core (popup, service worker, E2E crypto) — v1.0 Phase 3
- ✓ iCloud Keychain sync with dedup and migration — v1.0 Phase 6
- ✓ FaceID capability tokens (2-min trust window) — v1.0 Phase 7

### Active

- [ ] Code display with countdown + clipboard copy in extension (v1.0 remaining)
- [ ] Auto-fill TOTP fields + domain matching in browser (v1.0 remaining)
- [ ] Resilience: reconnection, session rebuild, keepalive (v1.0 remaining)
- [ ] Smart keyboard: recency/frequency sorting, search/filter
- [ ] Google Authenticator batch import (otpauth-migration:// protobuf)
- [ ] Onboarding flow: welcome screens, keyboard activation guide, pairing walkthrough
- [ ] Encrypted backup export (.keyauth file)

### Out of Scope

- Passkey support — TOTP isn't dying soon, defer to v3.0+
- Bluetooth/local communication — Chrome extensions can't use Web Bluetooth API
- Firefox/Safari extension — Chrome only for now
- Self-hosted relay option — Railway-hosted only
- Syncing secrets to the browser — secrets stay on the phone
- Authy encrypted backup import — complex format, low priority vs Google Auth
- watchOS companion — defer to v3.0
- App Store submission — defer to v3.0

## Context

**Existing codebase:** KeyAuth is a working iOS app (SwiftUI companion + UIKit keyboard extension) with zero external iOS dependencies. Chrome extension (React 19 + WXT) and relay server (Node.js) are functional. iCloud Keychain sync and FaceID capability tokens are built. E2E encryption (X25519 + ChaCha20Poly1305) secures all relay communication.

**User research (2026-04-16):** Researched authenticator complaints across X, forums, tech blogs, and app reviews. Identified 9 pain points: phone loss lockout (#1), app-switching friction (#2), no desktop access (#3), phone transfer nightmare (#4), cumulative micro-friction (#5), setup complexity (#6), sync trust issues (#7), time drift (#8), passkeys confusion (#9). v2.0 features directly address #2, #3, #4, #5, #6, and #7.

**v1.0 status:** Phases 1-2 complete, Phase 3 partially complete (2/3 plans), Phases 4-5 not started, Phases 6-7 complete (pending manual QA). Remaining v1.0 work rolled into v2.0.

## Constraints

- **No external iOS dependencies**: Zero third-party packages on iOS — keep it that way
- **Chrome Manifest V3**: Service workers, no persistent background connections
- **Relay hosting**: Railway only. Never Vercel
- **TOTP code lifetime**: 30-second window for full request-approve-deliver flow
- **Protobuf for Google Auth import**: Need to decode Google's `otpauth-migration://` format — pure Swift implementation, no external protobuf library

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| E2E encrypted relay (X25519 + ChaCha20Poly1305) | Zero-knowledge relay, server sees only opaque blobs | ✓ Good |
| WebSocket relay, not Bluetooth | Chrome extensions can't use Web Bluetooth API | ✓ Good |
| Click-to-request, not auto-detect-push | User initiates from extension; auto-fill after code arrives | ✓ Good |
| Railway for relay hosting | User's preferred platform; Vercel excluded | ✓ Good |
| APNs alert push (not silent) | Silent push throttled ~3/hour by Apple | ✓ Good |
| iCloud Keychain sync (not CloudKit) | Apple-managed E2E encryption, zero server cost | ✓ Good |
| FaceID 2-min trust window | Eliminates re-prompts during re-auth loops | ✓ Good |
| Defer passkeys to v3.0+ | TOTP adoption still dominant, keep v2.0 focused | — Pending |
| Roll v1.0 remaining into v2.0 | Unify completion + new features in one milestone | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-20 after milestone v2.0 initialization*
