---
phase: 8
slug: core-extension-flow
status: approved
shadcn_initialized: false
preset: none
created: 2026-04-20
---

# Phase 8 — UI Design Contract

> Visual and interaction contract for the Chrome extension popup account list, code display, reconnection states, and content script auto-fill indicator. iOS approval sheet (CodeApprovalView) is already built — minimal visual changes.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none |
| Preset | not applicable |
| Component library | none (vanilla React + plain CSS) |
| Icon library | none (inline SVG where needed) |
| Font | system-ui, -apple-system, sans-serif |

---

## Spacing Scale

Declared values (must be multiples of 4):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon gaps, inline padding |
| sm | 8px | Compact element spacing, QR container padding, card internal padding |
| lg | 16px | Section padding, popup body padding, list item padding |
| xl | 24px | Major section breaks |
| 2xl | 32px | Not used this phase |

No exceptions — all values from standard set {4, 8, 16, 24, 32, 48, 64}. Existing code patterns using non-standard values will be migrated to nearest standard token during implementation.

---

## Typography

| Role | Size | Weight | Line Height | Font |
|------|------|--------|-------------|------|
| Body / Label | 13px | 400 | 1.4 | system-ui |
| Small | 11px | 400 | 1.3 | system-ui |
| Heading | 16px | 600 | 1.3 | system-ui |
| Code | 28px | 600 | 1.0 | SF Mono, Menlo, Consolas, monospace |

---

## Color

| Role | Light | Dark | Usage |
|------|-------|------|-------|
| Dominant (60%) | #ffffff | #1a1a1a | Popup background |
| Secondary (30%) | rgba(128,128,128,0.04) | rgba(255,255,255,0.04) | Cards, account list items |
| Accent (10%) | #3b82f6 | #2563eb | Primary CTA buttons, selected account highlight border, "Request Another" link |
| Success | #22c55e | #22c55e | Countdown ring (>5s), "Copied" status, connected dot |
| Warning | #f59e0b | #f59e0b | Connecting dot, countdown ring pulse state, "Reconnecting" text |
| Destructive | #ef4444 | #ef4444 | Disconnected dot, countdown ring (<5s), Unpair action, dismiss hover |
| Border | #e5e5e5 | #333333 | Card borders, header separator, account list dividers |
| Muted text | #666666 | #999999 | Secondary labels, status text |

Accent reserved for: primary action buttons (`btn-primary`), account list item active/selected border, "Request Another Code" link text, code hover border highlight, domain-matched account top-sort indicator.

---

## Component Inventory

### New Components (Phase 8)

| Component | Purpose | States |
|-----------|---------|--------|
| `AccountList` | Scrollable list of accounts from phone | loading, populated, empty (no accounts synced) |
| `AccountItem` | Single account row (badge + issuer + label) | default, domain-matched (highlighted), tapped/requesting |
| `DomainMatchBadge` | Small indicator showing domain match | visible when domain matches issuer |
| `ReconnectingBanner` | Inline banner during reconnection | visible only during `connecting` state after a drop |

### Existing Components (No Changes)

| Component | Status |
|-----------|--------|
| `CodeView` | Complete — code display, countdown ring, copy, auto-clear |
| `StatusDot` | Complete — extend state mapping to include `reconnecting` (same as `connecting` visually) |
| `PairingView` | Complete — QR code + TTL countdown |
| `ConnectedView` | Refactor — replace "Request Code" button with AccountList |

### Content Script (Invisible)

The content script has no persistent visual UI. It operates invisibly to detect and fill TOTP fields. No design contract needed for detection logic.

---

## Interaction Contracts

### Account List Flow

1. User opens popup while connected → sees account list (not "Request Code" button)
2. Accounts matching current tab domain sort to top with a subtle left-border accent indicator (2px solid accent)
3. User clicks an account → account item shows spinner state (opacity 0.6 + loading indicator) → request sent to phone
4. Phone approves → code appears in CodeView (existing component) replacing account list
5. If code expires or user dismisses → returns to account list

### Reconnection Flow

1. WebSocket drops → StatusDot turns amber (connecting), inline text changes to "Reconnecting..."
2. Reconnection succeeds → StatusDot turns green, text returns to "Connected", account list re-fetches
3. If user clicks account while disconnected → show inline message "Reconnecting..." below the account item (not a modal, not blocking)

### Auto-Fill Flow (No UI in popup)

1. Code received → content script checks for TOTP field on active page
2. If field found → fill immediately, no user confirmation
3. If no field → code shows in popup only (existing CodeView behavior)
4. Split-input fields (6 separate inputs) → distribute digits across all inputs

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | Click any account below to request its code |
| Empty state heading | No accounts yet |
| Empty state body | Open KeyAuth on your iPhone to sync your accounts. Make sure both devices are connected. |
| Error: disconnected | Connection lost. Reconnecting... |
| Error: request timeout | Request timed out. Make sure your iPhone is nearby and unlocked. |
| Error: no phone response | No response from phone. Open KeyAuth on your iPhone and try again. |
| Destructive: Unpair | Unpair this device? You will need to scan the QR code again to reconnect. Confirmation: browser `confirm()` dialog. |
| Domain match hint | Suggested for this site |
| Reconnecting inline | Reconnecting... |
| Code requesting state | Waiting for approval... |

---

## Layout Specifications

### Popup Dimensions

| Property | Value |
|----------|-------|
| Width | 320px (fixed, existing) |
| Min height | 200px |
| Max height | 500px |
| Overflow | scroll on account list only |

### Account List Item

| Property | Value |
|----------|-------|
| Height | 48px (touch-friendly) |
| Padding | 8px 16px |
| Border radius | 10px (matches code-card) |
| Badge size | 28px x 28px (matches existing code-account-badge) |
| Badge radius | 7px |
| Gap (badge to text) | 8px |
| Border (domain match) | 2px solid #3b82f6 left border |
| Background (hover) | rgba(59, 130, 246, 0.06) light / rgba(59, 130, 246, 0.12) dark |
| Cursor | pointer |

### Reconnecting Banner

| Property | Value |
|----------|-------|
| Position | Below header, above account list |
| Padding | 8px 16px |
| Background | rgba(245, 158, 11, 0.08) |
| Text color | #f59e0b (warning) |
| Font size | 13px |
| Border radius | 0 (full-width strip) |

---

## State Machine (Popup Views)

```
unpaired → PairingView (QR code)
connecting → AccountList + ReconnectingBanner
connected → AccountList (full functionality) — focal point: first domain-matched account item; if no match, top account item
requesting → AccountList with selected item in loading state
code_received → CodeView (existing)
disconnected → AccountList (disabled clicks) + ReconnectingBanner
```

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| N/A | none | not applicable — no component library registry in use |

---

## iOS Approval Sheet (Existing — Minimal Changes)

CodeApprovalView.swift is already built (Phase 2 + Phase 7). Phase 8 wires it to relay messages. No visual changes needed beyond ensuring:
- Account name and issuer display correctly from relay message payload
- Trust window silent-send path triggers TransientToastOverlay (already built)
- APNs notification tap opens directly to CodeApprovalView

No new iOS UI components required for this phase.

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved (2026-04-20)
