import XCTest
@testable import KeyAuth

/// Live-simulator Keychain round-trips for the sync-aware KeychainManager rewrite (Plan 06-02).
/// Each test uses a UUID-suffixed service via `_setServiceForTesting` so results stay isolated
/// from real user data. `tearDown` wipes everything and resets the service to production values.
///
/// Covers requirements:
/// - ICLOUD-01: `save(_:synchronizable:)` persists the sync attribute exactly as specified.
/// - ICLOUD-02: `loadAll()` / `loadAllIncludingVariants()` use `kSecAttrSynchronizableAny`, so
///   both sync and non-sync variants are returned.
/// - ICLOUD-03: `delete(id:)` removes BOTH variants.
/// - ICLOUD-07 prep: `deleteNonSyncOnly(id:)` + migration-safe ordering leave the synced copy.
/// - ICLOUD-09: `deleteAllSynced()` uses `kCFBooleanTrue` (not SynchronizableAny) — local-only
///   items survive a destructive purge.
final class KeychainManagerSyncTests: XCTestCase {
    private var sut: KeychainManager!
    private var testService: String!

    override func setUp() {
        super.setUp()
        sut = KeychainManager.shared
        testService = "com.keyauth.tests.\(UUID().uuidString)"
        sut._setServiceForTesting(testService, accessGroup: nil)
    }

    override func tearDown() {
        try? sut.deleteAll()
        sut._resetToProductionService()
        super.tearDown()
    }

    // MARK: - ICLOUD-01: save persists the kSecAttrSynchronizable attribute

    func testSaveSynchronizableTrue() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: true)
        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.account.id, account.id)
        XCTAssertEqual(variants.first?.isSync, true, "ICLOUD-01: synchronizable=true must persist")
    }

    func testSaveSynchronizableFalse() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: false)
        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.isSync, false, "ICLOUD-01: synchronizable=false must persist")
    }

    // MARK: - ICLOUD-02: loadAll includes SynchronizableAny — both variants visible

    func testLoadAllIncludesBothVariants() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: true)
        try sut.save(account, synchronizable: false)
        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(
            variants.count, 2,
            "Keychain uniqueness includes synchronizable; two variants should coexist"
        )
        XCTAssertTrue(variants.contains(where: { $0.isSync }))
        XCTAssertTrue(variants.contains(where: { !$0.isSync }))
    }

    func testLoadAllWithOnlyLocalVariant() throws {
        try sut.save(AccountFixtures.make(), synchronizable: false)
        XCTAssertEqual(
            try sut.loadAll().count, 1,
            "loadAll must find local-only items via SynchronizableAny"
        )
    }

    func testLoadAllWithOnlySyncVariant() throws {
        try sut.save(AccountFixtures.make(), synchronizable: true)
        XCTAssertEqual(
            try sut.loadAll().count, 1,
            "loadAll must find synced items via SynchronizableAny"
        )
    }

    // MARK: - ICLOUD-03: delete removes both variants

    func testDeleteRemovesBothVariants() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: true)
        try sut.save(account, synchronizable: false)
        try sut.delete(id: account.id)
        XCTAssertEqual(
            try sut.loadAllIncludingVariants().count, 0,
            "delete(id:) must remove BOTH variants"
        )
    }

    // MARK: - ICLOUD-07 prep: deleteNonSyncOnly preserves synced copy

    func testDeleteNonSyncOnlyLeavesSyncedCopy() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: true)
        try sut.save(account, synchronizable: false)
        try sut.deleteNonSyncOnly(id: account.id)
        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.isSync, true, "deleteNonSyncOnly must preserve the synced copy")
    }

    // MARK: - ICLOUD-09: deleteAllSynced uses kSecAttrSynchronizable=true, not Any

    func testDeleteAllSyncedPreservesLocalVariants() throws {
        let synced1 = AccountFixtures.make(issuer: "GitHub")
        let synced2 = AccountFixtures.make(issuer: "GitLab")
        let local = AccountFixtures.make(issuer: "Bitbucket")
        try sut.save(synced1, synchronizable: true)
        try sut.save(synced2, synchronizable: true)
        try sut.save(local, synchronizable: false)

        try sut.deleteAllSynced()

        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1, "deleteAllSynced must not touch local-only items")
        XCTAssertEqual(variants.first?.isSync, false)
        XCTAssertEqual(variants.first?.account.id, local.id)
    }

    // MARK: - ICLOUD-07 prep: migration safe-ordering (re-save then delete local)

    func testMigrationSafeOrdering() throws {
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: false)   // initial local state
        try sut.save(account, synchronizable: true)    // step 1: re-save as synced
        try sut.deleteNonSyncOnly(id: account.id)      // step 2: cleanup local copy
        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.isSync, true)
        XCTAssertEqual(variants.first?.account.id, account.id)
    }

    // MARK: - errSecDuplicateItem / update-fallthrough

    func testSaveTwiceUpdatesInPlace() throws {
        let original = AccountFixtures.make(issuer: "GitHub", label: "octocat")
        try sut.save(original, synchronizable: true)

        // Re-save same id with changed issuer — must update, not duplicate, not throw.
        var updated = original
        updated.issuer = "GitLab"
        try sut.save(updated, synchronizable: true)

        let variants = try sut.loadAllIncludingVariants()
        XCTAssertEqual(variants.count, 1, "Second save of same id+sync must update, not duplicate")
        XCTAssertEqual(variants.first?.account.issuer, "GitLab")
    }

    // MARK: - kSecAttrAccessibleAfterFirstUnlock preserved on every insert

    func testSaveSetsAccessibleAfterFirstUnlock() throws {
        // Indirect assertion: after save, an update must succeed without re-specifying
        // kSecAttrAccessible (the add branch set it once; update must not fail on
        // accessibility-mismatch).
        let account = AccountFixtures.make()
        try sut.save(account, synchronizable: false)
        var updated = account
        updated.label = "new-label"
        XCTAssertNoThrow(
            try sut.save(updated, synchronizable: false),
            "If kSecAttrAccessible was dropped, re-save could fail on accessibility mismatch"
        )
    }
}
