import Foundation
import Combine

/// Phase 6 iCloud Keychain Sync — migration + destructive + reverse-detach coordinator.
///
/// Three public operations matching the decisions locked in RESEARCH.md §7-§9:
/// - `migrateAllToSync()` — D-07 forward migration (OFF→ON bulk re-save). Safe ordering:
///   save-as-sync FIRST, then `deleteNonSyncOnly`. Continues on per-account failure.
/// - `stopSyncingThisDevice()` — D-06 reverse / local detach. Re-saves synced accounts as
///   non-sync locally. Does NOT call `deleteAllSynced` or delete with sync=true — those would
///   propagate deletion through iCloud to the user's other devices.
/// - `removeFromICloudAllDevices()` — D-05 destructive. Calls `deleteAllSynced()` and starts a
///   10-second `toggleCooldownUntil` window (RESEARCH.md lines 676-684) to prevent race-re-enable.
///
/// Observed by SettingsView (@EnvironmentObject) for toggle disable state + progress rendering.
@MainActor
final class MigrationCoordinator: ObservableObject {
    struct Progress: Equatable { var done: Int; var total: Int; var failed: Int }

    @Published var progress: Progress = Progress(done: 0, total: 0, failed: 0)
    @Published var isRunning: Bool = false
    @Published var toggleCooldownUntil: Date? = nil
    @Published var lastMigrationResult: (ok: Int, failed: Int, deduped: Int)? = nil

    private let keychain: KeychainProviding
    private let store: AccountStore

    init(keychain: KeychainProviding = KeychainManager.shared, store: AccountStore) {
        self.keychain = keychain
        self.store = store
    }

    /// D-07 forward migration: OFF→ON bulk re-save.
    ///
    /// Safe ordering per RESEARCH.md lines 382-388: step 1 saves the synced variant BEFORE
    /// step 2 deletes the local-only variant. This guarantees the worst case on mid-loop
    /// failure is a duplicate (caught by the dedup pass in `AccountStore.reload`) rather
    /// than a lost account.
    ///
    /// Returns `(ok, failed, deduped)`. Per-account failures increment `failed` and
    /// the loop CONTINUES — we never roll back a successful migration on a later failure.
    /// `SyncPreference.setEnabled(true)` is set AFTER the loop so the flag reflects user intent
    /// even if some individual items failed.
    @discardableResult
    func migrateAllToSync() async -> (ok: Int, failed: Int, deduped: Int) {
        isRunning = true
        defer { isRunning = false }

        var ok = 0
        var failed = 0
        let all = (try? keychain.loadAllIncludingVariants()) ?? []
        let nonSync = all.filter { !$0.isSync }
        progress = Progress(done: 0, total: nonSync.count, failed: 0)

        for (account, _) in nonSync {
            do {
                // Step 1 — re-save as synchronizable. `KeychainManager.save` handles the
                // errSecDuplicateItem race via SecItemUpdate fallback.
                try keychain.save(account, synchronizable: true)
                // Step 2 — delete the local-only copy (but keep the just-created synced copy).
                try keychain.deleteNonSyncOnly(id: account.id)
                ok += 1
            } catch {
                failed += 1
            }
            progress = Progress(done: ok, total: nonSync.count, failed: failed)
        }

        SyncPreference.setEnabled(true)
        store.reload()  // dedup pass runs here; store.lastDedupCount is the output we want.
        let deduped = store.lastDedupCount
        let result = (ok: ok, failed: failed, deduped: deduped)
        lastMigrationResult = result
        return result
    }

    /// D-06 reverse migration / local detach: stop syncing THIS device without propagating
    /// deletion to the user's other signed-in devices.
    ///
    /// CRITICAL SAFETY CONTRACT (RESEARCH.md lines 442-458): this function ONLY re-saves
    /// each account as `synchronizable: false`. It MUST NOT call `deleteAllSynced()` or
    /// `delete(id:)` on a synced item — either of those would propagate the deletion
    /// through iCloud and wipe the data from iPad / Mac / other iPhone. The synced copy
    /// on the server stays as-is; this device simply has its own local-only copy going
    /// forward.
    ///
    /// Enforced at test-time by `MigrationTests.testStopSyncingFunctionDoesNotCallDeleteAllSynced`
    /// (static source-grep over this function body).
    func stopSyncingThisDevice() async {
        isRunning = true
        defer { isRunning = false }

        let all = (try? keychain.loadAllIncludingVariants()) ?? []
        let synced = all.filter { $0.isSync }

        for (account, _) in synced {
            // Re-save as non-sync creates a local-only copy. The synced variant is
            // intentionally left in place — other devices keep their data.
            try? keychain.save(account, synchronizable: false)
        }

        SyncPreference.setEnabled(false)
        store.reload()
    }

    /// D-05 destructive: remove all synced copies from iCloud (propagates to other devices)
    /// and start a 10-second `toggleCooldownUntil` window per RESEARCH.md lines 676-684 so the
    /// user can't immediately re-enable sync while CloudKit is still echoing the deletion.
    ///
    /// Non-sync local copies on this device are preserved — we only purge the synced variants.
    /// Throws if `keychain.deleteAllSynced()` throws.
    func removeFromICloudAllDevices() async throws {
        isRunning = true
        defer { isRunning = false }

        try keychain.deleteAllSynced()
        SyncPreference.setEnabled(false)
        toggleCooldownUntil = Date().addingTimeInterval(10)
        store.reload()
    }
}
