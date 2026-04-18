import Foundation

/// Per-device iCloud-sync toggle state. NOT stored in iCloud (this is UX state, not data).
enum SyncPreference {
    private static let enabledKey = "sync_enabled"
    private static let hasSeenFirstLaunchCardKey = "hasSeenSyncFirstLaunchCard"
    private static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    static var hasSeenFirstLaunchCard: Bool {
        UserDefaults.standard.bool(forKey: hasSeenFirstLaunchCardKey)
    }

    static func markFirstLaunchCardSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenFirstLaunchCardKey)
    }

    /// Per CONTEXT.md D-01 (new users default sync=ON) vs D-02 (existing users default OFF).
    /// Call ONCE from KeyAuthApp.onAppear before AccountStore init.
    static func bootstrap(existingAccountCount: Int) {
        let defaults = UserDefaults.standard
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedBeforeKey)
        if hasLaunchedBefore { return }

        let isExistingUser = existingAccountCount > 0
        defaults.set(!isExistingUser, forKey: enabledKey)
        defaults.set(true, forKey: hasLaunchedBeforeKey)
    }

    /// Per UI-SPEC First-launch card lifecycle: show only for new users with empty list.
    static func shouldShowFirstLaunchCard(accountsIsEmpty: Bool) -> Bool {
        return isEnabled && !hasSeenFirstLaunchCard && accountsIsEmpty
    }
}
