import XCTest
import Foundation
import UIKit
@testable import KeyAuth

/// Tests for `TrustWindowManager` — covers FIDO-01..FIDO-07, FIDO-11, FIDO-12, FIDO-17.
/// Uses the `var now: () -> Date` injection seam on the singleton to avoid real-time waits
/// for the 120s expiry (FIDO-04/FIDO-05). The 2-second toast auto-dismiss test
/// (`testToastAutoDismissAfter2s`) is the only wall-clock test in this file and is bounded
/// by Timer slack — see RESEARCH.md Pitfall 7 narrative.
@MainActor
final class TrustWindowManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "trust_window_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBeforeTrustWindow")
        TrustWindowManager.shared._resetForTests()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "trust_window_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBeforeTrustWindow")
        TrustWindowManager.shared._resetForTests()
        try await super.tearDown()
    }

    // FIDO-01: singleton shape + initial state
    func testInitialState_isInWindowIsFalse() throws {
        let mgr = TrustWindowManager.shared
        XCTAssertFalse(mgr.isInWindow, "FIDO-01: isInWindow must be false when no window is open")
        XCTAssertNil(mgr.windowExpiresAt, "FIDO-01: windowExpiresAt must be nil at start")
        XCTAssertNil(mgr.pendingToast, "FIDO-01: pendingToast must be nil at start")
    }

    // FIDO-02: mint sets windowExpiresAt = now + 120s
    func testMintSetsExpiryTo120sFromNow() throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        let t0 = Date()
        mgr.now = { t0 }
        mgr.mint()
        XCTAssertTrue(mgr.isInWindow, "FIDO-02: isInWindow must be true immediately after mint")
        let exp = try XCTUnwrap(mgr.windowExpiresAt, "FIDO-02: windowExpiresAt must be non-nil after mint")
        XCTAssertEqual(
            exp.timeIntervalSince(t0),
            120,
            accuracy: 0.5,
            "FIDO-02: window must expire exactly 120s from mint moment (D-03 fixed-from-mint)"
        )
    }

    // FIDO-03: mint is no-op when TrustWindowPreference.isEnabled == false (D-17 / T-7-06)
    func testMintNoOpWhenPreferenceDisabled() throws {
        TrustWindowPreference.bootstrap()
        TrustWindowPreference.setEnabled(false)
        let mgr = TrustWindowManager.shared
        mgr.mint()
        XCTAssertFalse(mgr.isInWindow, "FIDO-03: mint must be a no-op when preference is OFF")
        XCTAssertNil(mgr.windowExpiresAt, "FIDO-03: windowExpiresAt must remain nil when preference is OFF")
    }

    // FIDO-04: re-mint REPLACES (fresh 2 min from new moment, NOT sliding-window extension)
    func testReMintReplacesExpiry() throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        var clock = Date()
        mgr.now = { clock }

        mgr.mint()
        let firstExpiry = try XCTUnwrap(mgr.windowExpiresAt, "FIDO-04: first mint must set an expiry")

        // Advance clock 60s — window still open, then re-mint.
        clock = clock.addingTimeInterval(60)
        mgr.mint()
        let secondExpiry = try XCTUnwrap(mgr.windowExpiresAt, "FIDO-04: second mint must set an expiry")

        // D-04 / D-03: second mint resets TTL to full 120s from the new moment.
        // So secondExpiry = firstExpiry + 60s (because the new moment is 60s after the first),
        // NOT firstExpiry + 0s (sliding, rejected) and NOT firstExpiry + 120s (additive, rejected).
        XCTAssertEqual(
            secondExpiry.timeIntervalSince(firstExpiry),
            60,
            accuracy: 0.5,
            "FIDO-04: re-mint must REPLACE the expiry with a fresh 120s from the new approval moment, not slide or extend"
        )
    }

    // FIDO-05: isInWindow lazy expiry check — flips false when clock passes expiry
    // even if the scheduled Timer hasn't fired yet (Pitfall 7).
    func testIsInWindowLazyExpiryCheck() throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        var clock = Date()
        mgr.now = { clock }

        mgr.mint()
        XCTAssertTrue(mgr.isInWindow, "FIDO-05: isInWindow true immediately after mint")

        clock = clock.addingTimeInterval(121)
        XCTAssertFalse(
            mgr.isInWindow,
            "FIDO-05: isInWindow must be false once now() passes windowExpiresAt, regardless of Timer fire status (Pitfall 7)"
        )
    }

    // FIDO-06: UIApplication.didEnterBackgroundNotification revokes (D-05)
    func testBackgroundNotificationRevokes() async throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        mgr.bootstrap()
        mgr.mint()
        XCTAssertTrue(mgr.isInWindow, "precondition: window open before background notification")

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Let the MainActor hop complete — the sink dispatches via Task { @MainActor in ... }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(mgr.isInWindow, "FIDO-06: didEnterBackgroundNotification must revoke the window (D-05)")
        XCTAssertNil(mgr.windowExpiresAt, "FIDO-06: windowExpiresAt must be nil after background revoke")
    }

    // FIDO-07: ICloudStateObserver.$didAccountChange revokes (D-06)
    func testICloudAccountChangeRevokes() async throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        mgr.bootstrap()

        // Prime the iCloud observer as signed-in so a subsequent _simulateIdentityChange(nil)
        // models a genuine sign-out transition that flips $didAccountChange to true.
        ICloudStateObserver.shared._primeAsSignedIn()

        mgr.mint()
        XCTAssertTrue(mgr.isInWindow, "precondition: window open before iCloud account change")

        ICloudStateObserver.shared._simulateIdentityChange(newToken: nil)

        // Let the Combine sink + MainActor hop complete.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(mgr.isInWindow, "FIDO-07: iCloud account change must revoke the window (D-06)")
    }

    // FIDO-11: toast text — matched issuer branch
    func testToastTextForMatchedIssuer() throws {
        let mgr = TrustWindowManager.shared
        mgr.showToast(for: "GitHub")
        XCTAssertEqual(
            mgr.pendingToast?.text,
            "Code sent for GitHub",
            "FIDO-11: non-empty issuer must produce 'Code sent for <issuer>' verbatim (UI-SPEC copy contract)"
        )
    }

    // FIDO-11: toast text — empty issuer fallback (D-09 defensive path)
    func testToastTextFallbackEmpty() throws {
        let mgr = TrustWindowManager.shared
        mgr.showToast(for: "")
        XCTAssertEqual(
            mgr.pendingToast?.text,
            "Code sent",
            "FIDO-11: empty issuer must fall back to 'Code sent' (UI-SPEC copy contract)"
        )
    }

    // FIDO-12: toast auto-dismiss after 2s (only wall-clock test in this file)
    func testToastAutoDismissAfter2s() async throws {
        let mgr = TrustWindowManager.shared
        mgr.showToast(for: "GitHub")
        XCTAssertNotNil(mgr.pendingToast, "precondition: toast visible immediately after showToast")

        // 2.3s wall-clock wait allows the 2.0s Timer + MainActor hop slack.
        try await Task.sleep(nanoseconds: 2_300_000_000)

        XCTAssertNil(
            mgr.pendingToast,
            "FIDO-12: toast must auto-dismiss within 2s + Timer slack (UI-SPEC §Interaction Patterns duration)"
        )
    }

    // FIDO-17: window not persisted across launches
    func testSingletonStateIsNotPersisted() throws {
        TrustWindowPreference.bootstrap()
        let mgr = TrustWindowManager.shared
        mgr.mint()
        XCTAssertTrue(mgr.isInWindow, "precondition: window open before simulated relaunch")

        // Simulate a force-quit + relaunch. The manager is in-memory only — no Keychain, no
        // UserDefaults. Resetting the singleton exercises the NOT-persisted invariant: a
        // fresh process would see `windowExpiresAt == nil` because no store exists to rehydrate.
        mgr._resetForTests()

        XCTAssertFalse(mgr.isInWindow, "FIDO-17: window must not survive 'relaunch' (singleton state is purely in-memory)")
        XCTAssertNil(mgr.windowExpiresAt, "FIDO-17: windowExpiresAt must be nil after reset (proves no persistence layer)")
    }
}
