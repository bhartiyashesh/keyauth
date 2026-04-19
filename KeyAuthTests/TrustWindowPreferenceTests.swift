import XCTest
import Foundation
@testable import KeyAuth

/// Plan 07-02: FIDO-14 and FIDO-16 unit tests — bootstrap default ON,
/// setEnabled round-trip persistence, bootstrap idempotency.
@MainActor
final class TrustWindowPreferenceTests: XCTestCase {

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

    // FIDO-16: fresh-install bootstrap defaults to ON
    func testBootstrapDefaultsToEnabled() throws {
        TrustWindowPreference.bootstrap()
        XCTAssertTrue(TrustWindowPreference.isEnabled,
            "FIDO-16 / D-16: fresh install must default trust_window_enabled = true")
    }

    // FIDO-14: setEnabled persists through a re-read
    func testSetEnabledPersistsInUserDefaults() throws {
        TrustWindowPreference.setEnabled(false)
        XCTAssertFalse(TrustWindowPreference.isEnabled)
        TrustWindowPreference.setEnabled(true)
        XCTAssertTrue(TrustWindowPreference.isEnabled)
    }

    // FIDO-14 / Pitfall 6: bootstrap is idempotent — does NOT overwrite user's manual OFF
    func testBootstrapIsIdempotentAfterManualSet() throws {
        TrustWindowPreference.bootstrap()       // first launch — sets ON
        TrustWindowPreference.setEnabled(false) // user toggles OFF in Settings
        TrustWindowPreference.bootstrap()       // subsequent launch — MUST be a no-op
        XCTAssertFalse(TrustWindowPreference.isEnabled,
            "bootstrap() must not re-enable after a manual setEnabled(false)")
    }
}
