import XCTest
import Security
@testable import KeyAuth

/// Regression tests for ICLOUD-13: device-bound Keychain items (pairing, crypto keys) must
/// never acquire `kSecAttrSynchronizable=true`. Two guard layers:
///
/// 1. Source-level greps of `PairingStore.swift` and `CryptoBoxManager.swift` — prevent
///    future diffs from adding `kSecAttrSynchronizable` to these files. The source files
///    are copied into the KeyAuthTests bundle by the "Copy Shared Sources For Isolation
///    Tests" Run-Script build phase (see `KeyAuth.xcodeproj/project.pbxproj`); each file is
///    copied with a `.swift.txt` extension because Xcode's Copy-Resources phase refuses to
///    bundle `.swift` files as data, and `.txt` is sandbox-readable.
/// 2. Runtime test — save a dummy pairing via `PairingStore`, then query the real Keychain
///    with `kSecAttrSynchronizable = kCFBooleanTrue` and assert `errSecItemNotFound`.
final class SyncScopeIsolationTests: XCTestCase {

    // MARK: - Bundle-resource loader

    /// Load a Swift source file that was copied into the KeyAuthTests bundle as
    /// `<name>.swift.txt` by the Run-Script build phase. Using `Bundle(for:)` keeps the
    /// lookup sandbox-safe on the simulator — absolute `#filePath` paths into the host's
    /// project directory are blocked by the simulator sandbox.
    private func loadBundledSource(named name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        // Files are copied with a `.swift.txt` suffix; strip the `.swift` portion so
        // `forResource:` sees the true stem and `withExtension: "swift.txt"` matches.
        let base = (name as NSString).deletingPathExtension  // e.g. PairingStore
        guard let url = bundle.url(forResource: base, withExtension: "swift.txt") else {
            let listing = bundle.paths(forResourcesOfType: "txt", inDirectory: nil)
            XCTFail(
                "Bundled source resource not found: \(base).swift.txt. Resource-phase misconfigured? "
                + "Found .txt resources: \(listing)"
            )
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Static source-code greps

    func testPairingStoreSourceContainsNoSynchronizableTrue() throws {
        let source = try loadBundledSource(named: "PairingStore.swift")
        XCTAssertFalse(
            source.contains("kSecAttrSynchronizable"),
            "ICLOUD-13: PairingStore MUST NOT reference kSecAttrSynchronizable — pairings are device-bound"
        )
    }

    func testCryptoBoxManagerHasNoKeychainCalls() throws {
        let source = try loadBundledSource(named: "CryptoBoxManager.swift")
        for forbidden in ["SecItemAdd", "SecItemUpdate", "SecItemDelete", "kSecClass"] {
            XCTAssertFalse(
                source.contains(forbidden),
                "ICLOUD-13: CryptoBoxManager must not call Keychain APIs directly (forbidden token: \(forbidden))"
            )
        }
    }

    func testPairingServiceNameDoesNotOverlapWithAccountsService() throws {
        let pairingSrc = try loadBundledSource(named: "PairingStore.swift")
        let accountsSrc = try loadBundledSource(named: "KeychainManager.swift")
        XCTAssertTrue(
            pairingSrc.contains("\"com.keyauth.pairing\""),
            "PairingStore service literal must be com.keyauth.pairing"
        )
        XCTAssertTrue(
            accountsSrc.contains("\"com.keyauth.accounts\""),
            "KeychainManager service literal must be com.keyauth.accounts"
        )
    }

    // MARK: - Runtime verification: no synced items in the pairing service

    @MainActor
    func testPairingStoreRuntimeSavePreservesNonSync() throws {
        // Save a dummy pairing through the real PairingStore — this exercises the actual
        // SecItem* call path without needing a network round-trip.
        let store = PairingStore.shared
        let dummy = PairingData(
            roomId: "test-\(UUID().uuidString)",
            relayURL: "wss://test.example",
            privateKeyRaw: Data(count: 32),
            peerPublicKeyRaw: Data(count: 32),
            sharedKeyRaw: Data(count: 32),
            pairedAt: Date()
        )
        try store.savePairing(dummy)
        defer { store.unpair() }

        // Query the Keychain directly for SYNCED items in the pairing service. Any match here
        // would indicate PairingStore's insert leaked kSecAttrSynchronizable=true.
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.keyauth.pairing",
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        query[kSecAttrAccessGroup as String] = "W646UCTVQV.com.keyauth.shared"

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(
            status,
            errSecItemNotFound,
            "ICLOUD-13: No SYNCED items must exist in the pairing service after savePairing()"
        )
    }
}
