import XCTest
import Foundation
@testable import KeyAuth

/// Wave 0 scaffold — filled in Plan 07-04 (RelayClient silent-send branch).
/// Uses CodeRequestFixtures + an injected account-resolver closure on RelayClient.
@MainActor
final class RelayClientSilentSendTests: XCTestCase {

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

    // FIDO-09: in-window + resolver returns account → silent send, pendingCodeRequest stays nil, toast fires
    func testSilentSendInWindow() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-04.")
    }

    // FIDO-10: in-window + resolver returns nil (ambiguous) → fall through to pendingCodeRequest, no send
    func testAmbiguousResolutionSetsPendingCodeRequest() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-04.")
    }

    // FIDO-09 complement: out-of-window always falls through regardless of resolver
    func testOutOfWindowAlwaysSetsPendingCodeRequest() throws {
        throw XCTSkip("Wave 0 scaffold — filled in Plan 07-04.")
    }
}
