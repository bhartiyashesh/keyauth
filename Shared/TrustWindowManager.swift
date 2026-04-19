import Foundation
import Combine
import UIKit

/// Transient toast payload — driven by `TrustWindowManager.pendingToast` and consumed by
/// `ContentView`'s `.overlay(alignment: .top)` via the shared `TransientToastOverlay` component.
///
/// `Identifiable` + UUID `id` so SwiftUI's `.animation(value:)` crossfades when the text changes
/// mid-display during rapid-fire silent sends (RESEARCH.md Pitfall 4 — latest-wins semantics).
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

/// Holds the 2-minute trust window state granted after a successful FaceID (or passcode fallback)
/// approval. Purely in-memory — NOT persisted. Reset to `nil` on app launch (CONTEXT.md D-17 /
/// FIDO-17).
///
/// Revocation triggers (any one ends the window):
///   - `UIApplication.didEnterBackgroundNotification` (D-05)
///   - `ICloudStateObserver.shared.$didAccountChange == true` (D-06)
///   - 2-minute Timer expiry (D-07)
///
/// Usage:
///   - `KeyAuthApp.onAppear` calls `bootstrap()` once (idempotent — guarded internally by
///     `didBootstrap` so repeat invocations are safe no-ops).
///   - `CodeApprovalView.approveAndSend` calls `mint()` after FaceID success.
///   - `RelayClient.handleMessage` checks `isInWindow` to branch silent-send vs FaceID prompt.
///   - `RelayClient.handleMessage` calls `showToast(for:)` after a silent send.
@MainActor
final class TrustWindowManager: ObservableObject {
    static let shared = TrustWindowManager()

    /// Expiry timestamp for the active window. `nil` when no window is open.
    @Published private(set) var windowExpiresAt: Date?

    /// Transient toast driver. SwiftUI `ContentView.overlay` binds to this.
    @Published var pendingToast: ToastMessage?

    /// Injectable clock seam for deterministic expiry tests (FIDO-04 / FIDO-05).
    /// Defaults to `Date()` in production; tests assign a closure returning a controlled clock.
    var now: () -> Date = { Date() }

    /// Derived — returns `false` if no window OR if `now()` has passed `windowExpiresAt`.
    /// Lazy check guarantees silent-send never fires past expiry even if the scheduled
    /// Timer runs late (RESEARCH.md Pitfall 7 — belt-and-suspenders).
    var isInWindow: Bool {
        guard let exp = windowExpiresAt else { return false }
        return now() < exp
    }

    private var expiryTimer: Timer?
    private var toastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private init() {}

    /// Wire revocation observers. Idempotent — safe to call twice (second call is a no-op).
    /// Call ONCE from KeyAuthApp.onAppear after TrustWindowPreference.bootstrap().
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        // D-05 — background revokes.
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.revoke() }
            }
            .store(in: &cancellables)

        // D-06 — iCloud account change revokes.
        ICloudStateObserver.shared.$didAccountChange
            .sink { [weak self] changed in
                guard changed else { return }
                Task { @MainActor in self?.revoke() }
            }
            .store(in: &cancellables)
    }

    /// Opens a fresh `ttl`-second window iff the user has not disabled the feature (D-17).
    /// A second mint within the window REPLACES the prior expiry with a fresh TTL (D-04 —
    /// FaceID restart; NOT sliding-window). The previous Timer is invalidated first.
    func mint(ttl: TimeInterval = 120) {
        guard TrustWindowPreference.isEnabled else { return }
        expiryTimer?.invalidate()
        let expiry = now().addingTimeInterval(ttl)
        windowExpiresAt = expiry
        expiryTimer = Timer.scheduledTimer(withTimeInterval: ttl, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.revoke() }
        }
    }

    /// Ends the window immediately. Called by: background observer, iCloud-account-change
    /// observer, expiry Timer fire. Does NOT nil `pendingToast` — toast lifecycle is
    /// independent (UI-SPEC: toggle OFF does not force-revoke in-flight toasts).
    func revoke() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        windowExpiresAt = nil
    }

    /// Publishes a 2-second transient toast. Replaces any in-flight toast (Pitfall 4 —
    /// latest-wins). VoiceOver users get an unprompted announcement via UIAccessibility.post.
    func showToast(for issuer: String) {
        let text = issuer.isEmpty ? "Code sent" : "Code sent for \(issuer)"
        pendingToast = ToastMessage(text: text)

        // Accessibility: unprompted announcement so VoiceOver users learn a silent send occurred
        // even when the toast is not focused. UI-SPEC Open Question 3 chose UIAccessibility.post
        // (available since iOS 3) over iOS 17's AccessibilityNotification.Announcement.
        UIAccessibility.post(notification: .announcement, argument: text)

        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pendingToast = nil }
        }
    }

    // MARK: - Test-only helpers (DEBUG-guarded so they cannot ship in release builds)

    #if DEBUG
    /// Forces the expiry Timer to fire now without waiting 120s. Lets tests assert the
    /// post-expiry state machine (FIDO-05 / FIDO-12) without a real-time wait.
    internal func _fireExpiryTimerNow() {
        expiryTimer?.invalidate()
        revoke()
    }

    /// Resets the singleton to a clean state between tests without tearing down the Combine
    /// subscriptions (which other tests depend on for FIDO-06 / FIDO-07).
    internal func _resetForTests() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        toastTimer?.invalidate()
        toastTimer = nil
        windowExpiresAt = nil
        pendingToast = nil
        now = { Date() }
    }
    #endif
}
