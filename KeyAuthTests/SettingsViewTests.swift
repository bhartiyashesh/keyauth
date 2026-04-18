import XCTest
import SwiftUI
@testable import KeyAuth

/// SettingsViewTests — Phase 06 Plan 04 grep-based copy regression guards.
///
/// Strategy: SwiftUI Views are opaque at runtime (no ViewInspector or SnapshotTesting
/// per plan constraints), so we assert the VERBATIM UI-SPEC copy strings exist in the
/// source file contents. Test-bundle sandboxing on the simulator prevents absolute
/// `#filePath` lookups against the host filesystem (caught during the first test run —
/// `NSPOSIXErrorDomain Code=1 "Operation not permitted"`), so we mirror the pattern
/// established by Plan 06-02's `SyncScopeIsolationTests`: the "Copy Shared Sources For
/// Isolation Tests" Run-Script build phase copies `App/Views/SettingsView.swift` and
/// `App/Views/FirstLaunchSyncCard.swift` into the test bundle as `<name>.swift.txt`,
/// and we load them via `Bundle(for: Self.self).url(forResource:withExtension:)`.
///
/// See: .planning/phases/06-icloud-keychain-sync/06-UI-SPEC.md lines 131-170.
@MainActor
final class SettingsViewTests: XCTestCase {

    /// Load a Swift source file that was copied into the KeyAuthTests bundle as
    /// `<name>.swift.txt` by the Run-Script build phase. Mirrors the loader in
    /// `SyncScopeIsolationTests` — the `.swift.txt` suffix bypasses Xcode's refusal
    /// to bundle raw `.swift` files and stays sandbox-readable.
    private func loadBundledSource(named name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let base = (name as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: base, withExtension: "swift.txt") else {
            let listing = bundle.paths(forResourcesOfType: "txt", inDirectory: nil)
            XCTFail(
                "Bundled source resource not found: \(base).swift.txt. "
                + "Run-Script 'Copy Shared Sources For Isolation Tests' misconfigured? "
                + "Found .txt resources: \(listing)"
            )
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - ICLOUD-04: Settings surface verbatim copy

    func testSyncSectionFooterContainsD03Verbatim() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."),
            "ICLOUD-04: D-03 disclosure copy must appear verbatim in SettingsView")
    }

    func testToggleLabelMatchesUISpec() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("Toggle(\"Sync with iCloud Keychain\""),
            "ICLOUD-04: Toggle label must be 'Sync with iCloud Keychain'")
    }

    func testHowSecuredDisclosureGroup() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("DisclosureGroup(\"How is this secured?\")"),
            "ICLOUD-04: 'How is this secured?' DisclosureGroup must be present")
    }

    // MARK: - ICLOUD-05: First-launch card

    func testFirstLaunchCardTitle() throws {
        let src = try loadBundledSource(named: "FirstLaunchSyncCard.swift")
        XCTAssertTrue(src.contains("Sync across your Apple devices"),
            "ICLOUD-05: FirstLaunchSyncCard title must be 'Sync across your Apple devices'")
    }

    func testFirstLaunchCardBodyIsD03Verbatim() throws {
        let src = try loadBundledSource(named: "FirstLaunchSyncCard.swift")
        XCTAssertTrue(src.contains("Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."),
            "ICLOUD-05 / D-04: First-launch card body must be D-03 verbatim")
    }

    func testFirstLaunchCardCTAs() throws {
        let src = try loadBundledSource(named: "FirstLaunchSyncCard.swift")
        XCTAssertTrue(src.contains("Button(\"Got it\""),
            "ICLOUD-05: 'Got it' primary CTA required")
        XCTAssertTrue(src.contains("Button(\"Manage in Settings\""),
            "ICLOUD-05: 'Manage in Settings' secondary CTA required")
    }

    // MARK: - ICLOUD-06: Disable confirmation dialog

    func testDisableDialogTwoOptions() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("Button(\"Stop syncing this device\")"),
            "ICLOUD-06: 'Stop syncing this device' default-role button required")
        XCTAssertTrue(src.contains("Button(\"Remove from iCloud on all devices\", role: .destructive)"),
            "ICLOUD-06: 'Remove from iCloud on all devices' destructive-role button required")
        XCTAssertTrue(src.contains("confirmationDialog("),
            "ICLOUD-06: .confirmationDialog modifier required")
    }

    func testDisableDialogMessageBodyVerbatim() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("Choose what happens to the accounts already in iCloud."),
            "ICLOUD-06 / D-05: message body must be verbatim from UI-SPEC line 164")
    }

    /// REVISION FIX — Blocker 1: verbatim per-option descriptions from UI-SPEC lines 166 & 168.
    /// SwiftUI's .confirmationDialog cannot render per-Button descriptions, so both descriptions
    /// live in the `message:` closure. This test enforces both strings are present verbatim.
    func testDisableDialogOptionDescriptionsVerbatim() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        let stopSyncing = "Stop syncing this device: Your accounts stay on this iPhone. They remain in iCloud and on your other signed-in devices."
        let removeAll = "Remove from iCloud on all devices: This will remove your accounts from your iPad, Apple Watch, and any other device signed into this iCloud. Accounts on this iPhone stay."
        XCTAssertTrue(src.contains(stopSyncing),
            "D-05 option 1 description must appear VERBATIM in SettingsView (UI-SPEC line 166)")
        XCTAssertTrue(src.contains(removeAll),
            "D-05 option 2 description must appear VERBATIM in SettingsView (UI-SPEC line 168)")
    }

    // MARK: - ICLOUD-14: iCloud-off deep-link

    func testD11CopyAndDeepLink() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("iCloud Keychain is turned off on this device."),
            "ICLOUD-14: D-11 copy must be verbatim")
        XCTAssertTrue(src.contains("UIApplication.openSettingsURLString"),
            "ICLOUD-14: Deep-link to iOS Settings required")
        XCTAssertTrue(src.contains("\"Open iOS Settings\""),
            "ICLOUD-14: Button label must be 'Open iOS Settings'")
    }

    // MARK: - ICLOUD-15 UI-side: D-12 copy

    func testD12CopyWithEmDash() throws {
        let src = try loadBundledSource(named: "SettingsView.swift")
        XCTAssertTrue(src.contains("iCloud Keychain was disabled — sync stopped."),
            "D-12 copy must use the em-dash '—', not a hyphen")
    }

    // MARK: - Compile-time / init sanity

    /// Create a SettingsView with env objects wired in — proves the View's stored properties
    /// resolve, the body tree constructs, and no initializer branch crashes. Wrapping in a
    /// UIHostingController forces SwiftUI to evaluate the body graph once.
    func testSettingsViewInstantiationDoesNotCrash() {
        let store = AccountStore(keychain: MockKeychain())
        let view = SettingsView()
            .environmentObject(store)
            .environmentObject(ICloudStateObserver.shared)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "SettingsView hosting controller must materialize its root view")
    }
}
