import XCTest
import Combine
@testable import KeyAuth

@MainActor
final class AccountStoreTests: XCTestCase {
    private var mock: MockKeychain!
    private var kvs: NSUbiquitousKeyValueStore!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockKeychain()
        kvs = NSUbiquitousKeyValueStore.default
        kvs.removeObject(forKey: "accounts-version")
        kvs.synchronize()
        // Reset SyncPreference between tests
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        SharedDefaults.saveAccounts([])
    }

    override func tearDown() async throws {
        kvs.removeObject(forKey: "accounts-version")
        kvs.synchronize()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        SharedDefaults.saveAccounts([])
        try await super.tearDown()
    }

    // MARK: - ICLOUD-12: SharedDefaults propagation

    func testReloadPopulatesAccountsFromKeychain() throws {
        let seed = [
            AccountFixtures.make(issuer: "A", sortOrder: 0),
            AccountFixtures.make(issuer: "B", sortOrder: 1),
            AccountFixtures.make(issuer: "C", sortOrder: 2)
        ]
        for a in seed { try mock.save(a, synchronizable: false) }
        let store = AccountStore(keychain: mock)
        XCTAssertEqual(store.accounts.count, 3)
    }

    func testReloadWritesToSharedDefaults() throws {
        let seed = AccountFixtures.make(issuer: "SharedTest")
        try mock.save(seed, synchronizable: false)
        let store = AccountStore(keychain: mock)
        _ = store.accounts  // force init
        let fromShared = SharedDefaults.loadAccounts()
        XCTAssertEqual(fromShared.count, 1)
        XCTAssertEqual(fromShared.first?.issuer, "SharedTest")
    }

    // MARK: - ICLOUD-11: SyncPreference branching on add

    func testAddPassesSyncPreferenceIsEnabled() {
        SyncPreference.setEnabled(true)
        let store = AccountStore(keychain: mock)
        let account = AccountFixtures.make()
        store.add(account)
        XCTAssertTrue(mock.store.contains { $0.account.id == account.id && $0.isSync == true },
            "ICLOUD-11: add must save with synchronizable=true when SyncPreference.isEnabled")
    }

    func testAddPassesSyncPreferenceFalseWhenDisabled() {
        SyncPreference.setEnabled(false)
        let store = AccountStore(keychain: mock)
        let account = AccountFixtures.make()
        store.add(account)
        XCTAssertTrue(mock.store.contains { $0.account.id == account.id && $0.isSync == false },
            "add must save with synchronizable=false when SyncPreference disabled")
    }

    // MARK: - ICLOUD-11: coalesce debounce

    func testCoalescedReloadDebounces300ms() async throws {
        let store = AccountStore(keychain: mock)
        let baselineCalls = mock.loadAllCallCount
        // Fire 5 coalesced reloads in a burst
        for _ in 0..<5 { store.coalescedReload() }
        // Wait longer than debounce window
        try await Task.sleep(nanoseconds: 500_000_000)
        let delta = mock.loadAllCallCount - baselineCalls
        XCTAssertEqual(delta, 1, "5 rapid coalescedReload calls must coalesce into exactly 1 reload")
    }

    // MARK: - ICLOUD-11: counter bump gating

    func testBumpCounterSkippedWhenSyncDisabled() {
        SyncPreference.setEnabled(false)
        let store = AccountStore(keychain: mock)
        kvs.set(Int64(0), forKey: "accounts-version")
        store.add(AccountFixtures.make())
        XCTAssertEqual(kvs.longLong(forKey: "accounts-version"), 0,
            "Counter must NOT bump when SyncPreference is disabled (RESEARCH.md Open Q #6)")
    }

    func testBumpCounterIncrementsWhenSyncEnabled() {
        SyncPreference.setEnabled(true)
        let store = AccountStore(keychain: mock)
        kvs.set(Int64(5), forKey: "accounts-version")
        store.add(AccountFixtures.make())
        XCTAssertEqual(kvs.longLong(forKey: "accounts-version"), 6,
            "Counter must increment by 1 per save when sync enabled")
    }
}
