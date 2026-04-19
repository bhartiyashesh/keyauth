import XCTest
@testable import KeyAuth

/// Phase 7 Plan 07-08 grep-based regression tests for CodeApprovalView.swift.
///
/// Strategy: `App/Views/CodeApprovalView.swift` is copied into the test bundle as
/// `CodeApprovalView.swift.txt` by the "Copy Shared Sources For Isolation Tests" Run-Script
/// phase (extended in Plan 07-05 Task 3). We grep the bundled source for:
///   - FIDO-08: the `TrustWindowManager.shared.mint()` call appears AFTER the
///     authenticate-success guard (regression against accidentally moving it above
///     the `guard success else { return }` block).
///   - FIDO-13: no remaining `startAutoRefresh` reference — the 5-minute Timer is gone.
@MainActor
final class CodeApprovalViewTests: XCTestCase {

    /// Loads the bundled `CodeApprovalView.swift.txt` resource from the test bundle.
    /// Mirrors the helper in SettingsViewTests.
    private func loadBundledSource(named name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let base = (name as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: base, withExtension: "swift.txt") else {
            XCTFail("Bundled source not found: \(base).swift.txt — Run-Script misconfigured?")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // FIDO-08: mint call appears AFTER authenticate success, BEFORE Task.sleep dismissal
    func testMintCallAppearsAfterAuthenticateSuccess() throws {
        let src = try loadBundledSource(named: "CodeApprovalView.swift")
        XCTAssertTrue(src.contains("TrustWindowManager.shared.mint()"),
            "FIDO-08: approveAndSend must call TrustWindowManager.shared.mint()")

        // Order sanity: the mint call must come AFTER `guard success else { return }` and AFTER
        // `sendEncryptedCode`. We assert by comparing NSString range locations.
        let ns = src as NSString
        let guardRange = ns.range(of: "guard success else")
        let sendRange = ns.range(of: "RelayClient.shared.sendEncryptedCode")
        let mintRange = ns.range(of: "TrustWindowManager.shared.mint()")

        XCTAssertNotEqual(guardRange.location, NSNotFound, "authenticate-success guard missing")
        XCTAssertNotEqual(sendRange.location, NSNotFound, "sendEncryptedCode call missing")
        XCTAssertNotEqual(mintRange.location, NSNotFound, "mint() call missing")

        XCTAssertGreaterThan(mintRange.location, guardRange.location,
            "FIDO-08: mint() must appear AFTER the `guard success else { return }` line")
        XCTAssertGreaterThan(mintRange.location, sendRange.location,
            "FIDO-08: mint() must appear AFTER sendEncryptedCode (so we only mint after the send is issued)")
    }

    // FIDO-13: startAutoRefresh is fully deleted from CodeApprovalView
    func testStartAutoRefreshIsAbsent() throws {
        let src = try loadBundledSource(named: "CodeApprovalView.swift")
        XCTAssertFalse(src.contains("startAutoRefresh"),
            "FIDO-13 / D-12: CodeApprovalView.swift must NOT contain any reference to startAutoRefresh (the 5-minute Timer was deleted in Plan 07-05)")
    }
}
