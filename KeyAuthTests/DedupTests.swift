import XCTest
@testable import KeyAuth

/// DedupTests — Phase 06 Plan 05 ICLOUD-08 coverage.
///
/// Two test groups:
/// 1. `DedupKey` normalization rules (issuer/label NFC + case-insensitive + whitespace
///    trim; secret uppercase + all-whitespace-strip per RFC 4648 Base32 case-insensitivity).
/// 2. `AccountStore.reload()` dedup pass behavior — earliest-createdAt tiebreak (D-08),
///    uuidString tiebreak when createdAt ties, lastDedupCount==0 on no-duplicates, and
///    Keychain-side deletion of losers.
@MainActor
final class DedupTests: XCTestCase {
    private var mock: MockKeychain!
    private var store: AccountStore!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockKeychain()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        SharedDefaults.saveAccounts([])
        store = AccountStore(keychain: mock)
    }

    // MARK: - DedupKey normalization rules (unit)

    func testDedupKeyCaseInsensitiveIssuer() {
        let a = AccountFixtures.make(issuer: "GitHub", label: "x", secret: "ABCDEFGH")
        let b = AccountFixtures.make(issuer: "github", label: "x", secret: "ABCDEFGH")
        XCTAssertEqual(DedupKey(a), DedupKey(b))
    }

    func testDedupKeyTrimsIssuerWhitespace() {
        let a = AccountFixtures.make(issuer: "GitHub", label: "x", secret: "ABCDEFGH")
        let b = AccountFixtures.make(issuer: "  GitHub  ", label: "x", secret: "ABCDEFGH")
        XCTAssertEqual(DedupKey(a), DedupKey(b))
    }

    func testDedupKeyUnicodeNFC() {
        let nfc = "\u{00E9}"      // é as single NFC codepoint
        let nfd = "e\u{0301}"     // e + combining acute — NFD form
        let a = AccountFixtures.make(issuer: nfc, label: "x", secret: "ABCDEFGH")
        let b = AccountFixtures.make(issuer: nfd, label: "x", secret: "ABCDEFGH")
        XCTAssertEqual(DedupKey(a), DedupKey(b),
            "NFC normalization must collapse equivalent Unicode forms")
    }

    func testDedupKeyStripsAllSecretWhitespace() {
        let a = AccountFixtures.make(secret: "JBSWY3DP")
        let b = AccountFixtures.make(secret: "JBSW Y3DP")
        let c = AccountFixtures.make(secret: "JBSW\nY3DP")
        XCTAssertEqual(DedupKey(a), DedupKey(b))
        XCTAssertEqual(DedupKey(a), DedupKey(c))
    }

    func testDedupKeySecretCaseInsensitive() {
        let a = AccountFixtures.make(secret: "JBSWY3DP")
        let b = AccountFixtures.make(secret: "jbswy3dp")
        XCTAssertEqual(DedupKey(a), DedupKey(b),
            "Base32 case-insensitive per RFC 4648 — 'JBSWY3DP' == 'jbswy3dp'")
    }

    // MARK: - AccountStore.reload() dedup pass (integration)

    func testDedupPassEarliestCreatedAtWins() {
        let early = AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGH",
            createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let mid = AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGH",
            createdAt: Date(timeIntervalSinceReferenceDate: 200))
        let late = AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGH",
            createdAt: Date(timeIntervalSinceReferenceDate: 300))
        try? mock.save(late, synchronizable: false)
        try? mock.save(early, synchronizable: false)
        try? mock.save(mid, synchronizable: false)

        store.reload()

        XCTAssertEqual(store.accounts.count, 1,
            "Three dupes collapse to one survivor")
        XCTAssertEqual(store.accounts.first?.id, early.id,
            "D-08: EARLIEST createdAt wins (ascending sort)")
        XCTAssertEqual(store.lastDedupCount, 2, "Two losers deleted")
    }

    func testDedupPassTiebreakByUUIDAscending() {
        let now = Date()
        let smallID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bigID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let a = AccountFixtures.make(id: smallID, issuer: "X", label: "y",
            secret: "ABCDEFGH", createdAt: now)
        let b = AccountFixtures.make(id: bigID, issuer: "X", label: "y",
            secret: "ABCDEFGH", createdAt: now)
        try? mock.save(b, synchronizable: false)
        try? mock.save(a, synchronizable: false)

        store.reload()

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts.first?.id, smallID,
            "Tiebreak when createdAt ties: uuidString ascending → smaller UUID wins")
    }

    func testDedupSilentWhenNoDuplicates() {
        try? mock.save(AccountFixtures.make(issuer: "A"), synchronizable: false)
        try? mock.save(AccountFixtures.make(issuer: "B"), synchronizable: false)
        try? mock.save(AccountFixtures.make(issuer: "C"), synchronizable: false)
        store.reload()
        XCTAssertEqual(store.accounts.count, 3)
        XCTAssertEqual(store.lastDedupCount, 0,
            "No duplicates → lastDedupCount==0 → toast suppressed")
    }

    func testDedupLosersRemovedFromKeychain() {
        for _ in 0..<3 {
            try? mock.save(
                AccountFixtures.make(issuer: "X", label: "y", secret: "ABCDEFGH"),
                synchronizable: false
            )
        }
        store.reload()
        XCTAssertEqual(try! mock.loadAll().count, 1,
            "Cross-id dedup losers MUST be deleted from the Keychain")
    }
}
