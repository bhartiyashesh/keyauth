import XCTest
import Foundation
@testable import KeyAuth

/// Wave 0 scaffold — filled in Plan 07-02 (TrustWindowPreference helper).
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
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-02.")
    }

    // FIDO-14: setEnabled persists through a re-read
    func testSetEnabledPersistsInUserDefaults() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-02.")
    }

    // FIDO-14: bootstrap is idempotent — second call after setEnabled(false) does not flip back to ON
    func testBootstrapIsIdempotentAfterManualSet() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-02.")
    }
}
