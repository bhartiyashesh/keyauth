import XCTest
@testable import KeyAuth

final class KeyAuthTests: XCTestCase {
    func testTargetBuildsAndRuns() throws {
        XCTAssertTrue(true)
    }

    func testMockKeychainSaveAndLoad() throws {
        let mock = MockKeychain()
        let account = AccountFixtures.make()
        try mock.save(account, synchronizable: false)
        let loaded = try mock.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, account.id)
    }

    func testDedupKeyNormalization() {
        let a = AccountFixtures.make(issuer: "GitHub", label: "user@example.com", secret: "JBSWY3DPEHPK3PXP")
        let b = AccountFixtures.make(issuer: "  github  ", label: "User@Example.com", secret: "jbswy3dpehpk3pxp")
        XCTAssertEqual(DedupKey(a), DedupKey(b))
    }

    func testSyncPreferenceBootstrapNewUser() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hasLaunchedBefore")
        defaults.removeObject(forKey: "sync_enabled")
        SyncPreference.bootstrap(existingAccountCount: 0)
        XCTAssertTrue(SyncPreference.isEnabled, "New user (D-01) must default sync=ON")
    }

    func testSyncPreferenceBootstrapExistingUser() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hasLaunchedBefore")
        defaults.removeObject(forKey: "sync_enabled")
        SyncPreference.bootstrap(existingAccountCount: 5)
        XCTAssertFalse(SyncPreference.isEnabled, "Existing user (D-02) must default sync=OFF")
    }
}
