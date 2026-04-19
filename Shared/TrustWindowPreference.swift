import Foundation

/// Per-device "allow silent-send trust window after FaceID" toggle state.
/// NOT stored in iCloud — this is UX state, not data.
///
/// Default behavior per Phase 7 CONTEXT.md D-16: ON for both new and existing users.
/// Unlike `SyncPreference`, which branches on the current-account count to honor the
/// iCloud-sync opt-in posture, TrustWindowPreference has no such branch — the feature
/// is strictly less restrictive than today's per-fetch FaceID, so "default ON" is
/// honored universally.
enum TrustWindowPreference {
    /// UserDefaults key for the actual on/off state.
    private static let enabledKey = "trust_window_enabled"
    /// Sentinel to detect first launch — MUST be distinct from SyncPreference's
    /// `hasLaunchedBefore` key to avoid cross-bootstrap short-circuit (Pitfall 6).
    private static let hasLaunchedBeforeKey = "hasLaunchedBeforeTrustWindow"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    /// Call ONCE from KeyAuthApp.onAppear (guarded by a didBootstrapTrustWindowPreference flag).
    /// Idempotent: second call on a launched-before device is a no-op.
    /// Per CONTEXT.md D-16, default is `true` for both new and existing users.
    static func bootstrap() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasLaunchedBeforeKey) { return }
        defaults.set(true, forKey: enabledKey)      // default ON (D-16)
        defaults.set(true, forKey: hasLaunchedBeforeKey)
    }
}
