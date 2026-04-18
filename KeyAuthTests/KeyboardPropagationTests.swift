import XCTest
@testable import KeyAuth

/// ICLOUD-12: SharedDefaults propagation chain for the keyboard extension.
///
/// The keyboard extension reads `SharedDefaults.loadAccounts()` on every `viewWillAppear`
/// (see `KeyboardExtension/KeyboardViewController.swift` lines 72-92). ICLOUD-12 requires
/// that `AccountStore.reload()` writes the latest account list to `SharedDefaults` so the
/// keyboard's next activation reads fresh data.
///
/// Cross-process keyboard activation is not unit-testable — it is covered by the manual
/// QA test `2-DEV-01` step 5 (keyboard activation on Device B shows synced account).
/// These unit tests lock down the MAIN-APP side of the propagation chain: anything that
/// mutates `AccountStore.accounts` must land in `SharedDefaults` before returning.
@MainActor
final class KeyboardPropagationTests: XCTestCase {
    private var mock: MockKeychain!
    private var store: AccountStore!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockKeychain()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        SharedDefaults.saveAccounts([])  // clean slate
        store = AccountStore(keychain: mock)
    }

    override func tearDown() async throws {
        SharedDefaults.saveAccounts([])
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        try await super.tearDown()
    }

    // MARK: - ICLOUD-12: reload → SharedDefaults round-trip

    func testReloadWritesAccountsToSharedDefaults() throws {
        try mock.save(AccountFixtures.make(issuer: "A", sortOrder: 0), synchronizable: false)
        try mock.save(AccountFixtures.make(issuer: "B", sortOrder: 1), synchronizable: false)

        store.reload()
        let fromKeyboard = SharedDefaults.loadAccounts()

        XCTAssertEqual(fromKeyboard.count, 2,
            "ICLOUD-12: SharedDefaults must reflect Keychain state after reload")
        XCTAssertEqual(Set(fromKeyboard.map(\.issuer)), Set(["A", "B"]),
            "ICLOUD-12: both issuers must propagate")
    }

    // MARK: - ICLOUD-12: add path propagates

    func testAddPropagatesToSharedDefaults() {
        let account = AccountFixtures.make(issuer: "Propagated")
        store.add(account)

        let fromKeyboard = SharedDefaults.loadAccounts()
        XCTAssertTrue(fromKeyboard.contains { $0.id == account.id },
            "add(_:) must invoke reload which writes SharedDefaults so the keyboard sees the new account on next activation")
    }

    // MARK: - ICLOUD-12: delete path propagates

    func testDeletePropagatesToSharedDefaults() throws {
        let account = AccountFixtures.make(issuer: "ToBeDeleted")
        try mock.save(account, synchronizable: false)
        store.reload()
        XCTAssertEqual(SharedDefaults.loadAccounts().count, 1,
            "precondition: seeded account must be in SharedDefaults before delete")

        store.delete(account)
        XCTAssertEqual(SharedDefaults.loadAccounts().count, 0,
            "delete(_:) must update SharedDefaults via reload so the keyboard drops the deleted account on next activation")
    }

    // MARK: - ICLOUD-12 ∧ ICLOUD-08: dedup result written to SharedDefaults

    func testReloadAfterDedupWritesDedupedList() throws {
        // Three accounts with different UUIDs but identical dedup content — DedupKey
        // collapses them cross-id (Phase 2 of AccountStore.dedupInMemory). The keyboard
        // must see the DEDUPED list, not the raw Keychain load.
        try mock.save(AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGHIJKLMNOP"), synchronizable: false)
        try mock.save(AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGHIJKLMNOP"), synchronizable: false)
        try mock.save(AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGHIJKLMNOP"), synchronizable: false)

        store.reload()

        XCTAssertEqual(SharedDefaults.loadAccounts().count, 1,
            "ICLOUD-12 ∧ ICLOUD-08: dedup collapses to 1 and SharedDefaults reflects the deduped list — keyboard must not see duplicates")
    }

    // MARK: - ICLOUD-12: sort order preserved in SharedDefaults

    func testReloadPreservesSortOrderInSharedDefaults() throws {
        try mock.save(AccountFixtures.make(issuer: "Z", sortOrder: 2), synchronizable: false)
        try mock.save(AccountFixtures.make(issuer: "Y", sortOrder: 1), synchronizable: false)
        try mock.save(AccountFixtures.make(issuer: "X", sortOrder: 0), synchronizable: false)

        store.reload()
        let fromKeyboard = SharedDefaults.loadAccounts()

        XCTAssertEqual(fromKeyboard.map(\.issuer), ["X", "Y", "Z"],
            "SharedDefaults.loadAccounts applies the same sortOrder sort the keyboard relies on")
    }
}
