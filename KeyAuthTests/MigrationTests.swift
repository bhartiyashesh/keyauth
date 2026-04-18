import XCTest
@testable import KeyAuth

/// MigrationTests — Phase 06 Plan 05 ICLOUD-07 coverage.
///
/// Exercises the three MigrationCoordinator operations (forward, reverse, destructive)
/// through MockKeychain, asserting counts, variant residue, SyncPreference state, and
/// the 10-second `toggleCooldownUntil` window. One static-source test enforces the
/// D-06 safety contract (stopSyncingThisDevice MUST NOT call deleteAllSynced).
@MainActor
final class MigrationTests: XCTestCase {
    private var mock: MockKeychain!
    private var store: AccountStore!
    private var migration: MigrationCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockKeychain()
        // Clear per-device flags so setUp is deterministic across runs.
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        UserDefaults.standard.removeObject(forKey: "hasSeenSyncFirstLaunchCard")
        SharedDefaults.saveAccounts([])
        store = AccountStore(keychain: mock)
        migration = MigrationCoordinator(keychain: mock, store: store)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        UserDefaults.standard.removeObject(forKey: "hasSeenSyncFirstLaunchCard")
        try await super.tearDown()
    }

    // MARK: - ICLOUD-07 forward migration

    func testMigrateAllToSyncForwardPath() async {
        for i in 0..<3 {
            try? mock.save(AccountFixtures.make(issuer: "svc\(i)"), synchronizable: false)
        }
        store.reload()

        let result = await migration.migrateAllToSync()

        XCTAssertEqual(result.ok, 3)
        XCTAssertEqual(result.failed, 0)
        let variants = try! mock.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 3, "Exactly 3 entries, all sync (non-sync deleted by step 2)")
        XCTAssertTrue(variants.allSatisfy { $0.isSync })
        XCTAssertTrue(SyncPreference.isEnabled)
    }

    func testMigrateAllToSyncPartialFailure() async {
        let failing = AccountFixtures.make(issuer: "fail-target")
        try? mock.save(AccountFixtures.make(issuer: "ok1"), synchronizable: false)
        try? mock.save(failing, synchronizable: false)
        try? mock.save(AccountFixtures.make(issuer: "ok2"), synchronizable: false)
        mock.failSaveForIDs.insert(failing.id)
        store.reload()

        let result = await migration.migrateAllToSync()

        XCTAssertEqual(result.ok, 2, "Two succeed around the failing one")
        XCTAssertEqual(result.failed, 1)
        XCTAssertTrue(SyncPreference.isEnabled,
            "Per-account failure must NOT block the SyncPreference flag")
    }

    func testMigrateAllToSyncSafeOrdering() async {
        let account = AccountFixtures.make()
        try? mock.save(account, synchronizable: false)
        store.reload()

        _ = await migration.migrateAllToSync()

        let variants = try! mock.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1)
        XCTAssertTrue(variants.first!.isSync,
            "Safe ordering: save-as-sync FIRST, deleteNonSyncOnly SECOND — only sync variant remains")
    }

    // MARK: - ICLOUD-07 reverse migration (D-06 safety)

    func testStopSyncingPreservesLocalAndDoesNotDeleteSynced() async {
        for i in 0..<3 {
            try? mock.save(AccountFixtures.make(issuer: "svc\(i)"), synchronizable: true)
        }
        SyncPreference.setEnabled(true)
        store.reload()

        await migration.stopSyncingThisDevice()

        let variants = try! mock.loadAllIncludingVariants()
        let syncedCount = variants.filter { $0.isSync }.count
        let localCount = variants.filter { !$0.isSync }.count
        XCTAssertEqual(syncedCount, 3,
            "D-06: synced copies MUST be preserved — other devices still have them")
        XCTAssertEqual(localCount, 3,
            "D-06: each account has a local copy after stopSyncing (re-saved as non-sync)")
        XCTAssertFalse(SyncPreference.isEnabled)
    }

    /// Static source grep — enforces the D-06 safety contract at test-time so a future
    /// refactor can't accidentally reintroduce a `deleteAllSynced()` or `delete(id:)` call
    /// inside `stopSyncingThisDevice`. If Xcode moves MigrationCoordinator.swift or the
    /// simulator sandbox blocks `#filePath`, this test falls back with a skip note.
    func testStopSyncingFunctionDoesNotCallDeleteAllSynced() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/MigrationCoordinator.swift")

        guard let src = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("MigrationCoordinator.swift not readable via #filePath (simulator sandbox)")
        }

        guard let start = src.range(of: "func stopSyncingThisDevice()")?.lowerBound else {
            return XCTFail("stopSyncingThisDevice not found in MigrationCoordinator.swift")
        }
        let tail = String(src[start...])
        let funcBody: String
        if let nextFunc = tail.range(of: "\n    func ") {
            funcBody = String(tail[..<nextFunc.lowerBound])
        } else {
            funcBody = tail
        }

        XCTAssertFalse(funcBody.contains("deleteAllSynced"),
            "D-06 safety: stopSyncingThisDevice MUST NOT call deleteAllSynced")
        XCTAssertFalse(funcBody.contains("delete(id:"),
            "D-06 safety: stopSyncingThisDevice MUST NOT call delete(id:) on synced items")
    }

    // MARK: - ICLOUD-07 destructive (D-05) + cooldown

    func testRemoveFromICloudAllDevicesDeletesSyncedPreservesLocal() async throws {
        let localOnly = AccountFixtures.make(issuer: "local-only")
        try mock.save(AccountFixtures.make(issuer: "synced1"), synchronizable: true)
        try mock.save(AccountFixtures.make(issuer: "synced2"), synchronizable: true)
        try mock.save(localOnly, synchronizable: false)
        SyncPreference.setEnabled(true)
        store.reload()

        try await migration.removeFromICloudAllDevices()

        let variants = try mock.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1, "Only the local-only item should remain")
        XCTAssertEqual(variants.first?.account.id, localOnly.id)
        XCTAssertFalse(SyncPreference.isEnabled)
    }

    func testRemoveFromICloudSetsCooldown() async throws {
        try await migration.removeFromICloudAllDevices()
        XCTAssertNotNil(migration.toggleCooldownUntil)
        XCTAssertGreaterThan(migration.toggleCooldownUntil!, Date())
        XCTAssertLessThan(migration.toggleCooldownUntil!, Date().addingTimeInterval(11),
            "10-second cooldown window per RESEARCH.md lines 676-684")
    }
}
