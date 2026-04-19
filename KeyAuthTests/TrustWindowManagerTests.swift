import XCTest
import Foundation
@testable import KeyAuth

/// Wave 0 scaffold — filled in Plan 07-03 (TrustWindowManager core) and Plan 07-07
/// (toast assertion for FIDO-11/FIDO-12). Every method throws XCTSkip at this stage so
/// the file compiles and the full test suite stays green while the production code catches up.
@MainActor
final class TrustWindowManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "trust_window_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBeforeTrustWindow")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "trust_window_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBeforeTrustWindow")
        try await super.tearDown()
    }

    // FIDO-01: singleton shape + initial state
    func testInitialState_isInWindowIsFalse() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03 (TrustWindowManager core).")
    }

    // FIDO-02: mint sets windowExpiresAt = now + 120s
    func testMintSetsExpiryTo120sFromNow() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-03: mint is no-op when TrustWindowPreference.isEnabled == false
    func testMintNoOpWhenPreferenceDisabled() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-04: re-mint replaces (fresh 2 min, not extended)
    func testReMintReplacesExpiry() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03 (injected clock).")
    }

    // FIDO-05: isInWindow lazy expiry check
    func testIsInWindowLazyExpiryCheck() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03 (injected clock).")
    }

    // FIDO-06: UIApplication.didEnterBackgroundNotification revokes
    func testBackgroundNotificationRevokes() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-07: ICloudStateObserver.$didAccountChange revokes
    func testICloudAccountChangeRevokes() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-11: toast text — matched issuer branch
    func testToastTextForMatchedIssuer() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-11: toast text — empty issuer fallback
    func testToastTextFallbackEmpty() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-12: toast auto-dismiss after 2s
    func testToastAutoDismissAfter2s() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }

    // FIDO-17: window not persisted across launches
    func testSingletonStateIsNotPersisted() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-03.")
    }
}
