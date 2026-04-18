import XCTest
import Foundation
@testable import KeyAuth

@MainActor
final class ICloudStateObserverTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        try await super.tearDown()
    }

    func testSignOutSimulationFlipsSyncPreferenceOff() {
        SyncPreference.setEnabled(true)
        XCTAssertTrue(SyncPreference.isEnabled)

        let observer = ICloudStateObserver.shared
        // Prime the singleton into a "signed-in" state so the sign-out branch fires on
        // the next _simulateIdentityChange(newToken: nil) call. On iOS Simulator the
        // FileManager.default.ubiquityIdentityToken is nil by default, so the singleton's
        // initial isICloudSignedIn is false and the wasSignedIn guard would otherwise skip
        // the SyncPreference flip we're trying to verify.
        observer._primeAsSignedIn()
        XCTAssertTrue(observer.isICloudSignedIn)

        observer._simulateIdentityChange(newToken: nil)

        XCTAssertFalse(observer.isICloudSignedIn, "isICloudSignedIn must become false after token nil")
        XCTAssertFalse(SyncPreference.isEnabled, "ICLOUD-15: SyncPreference must flip OFF on sign-out")
        XCTAssertTrue(observer.didAccountChange, "didAccountChange must fire for UI to show D-12 copy")
    }

    func testInitialStateIsBooleanValid() {
        // Simulator iCloud state isn't deterministic — just verify no crash and type sanity.
        let observer = ICloudStateObserver.shared
        _ = observer.isICloudSignedIn  // reading must succeed
    }
}
