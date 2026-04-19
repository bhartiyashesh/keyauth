import XCTest
import Foundation
@testable import KeyAuth

/// FIDO-09 / FIDO-10 unit coverage for the silent-send branch added to
/// `RelayClient.handleMessage`. The branch was extracted into an internal
/// `handleDecodedRequest(_:)` method plus an injectable `accountResolver`
/// closure so these tests need no WebSocket / PairingStore plumbing —
/// they feed a decoded `CodeRequest` fixture directly and script the
/// resolver's return value.
///
/// NOTE on `sendEncryptedCode`: we deliberately do NOT assert that bytes
/// reached the WebSocket. `PairingStore.shared.sharedKey` is `nil` in the
/// unit-test environment, so `sendEncryptedCode` internally early-returns.
/// That's acceptable for FIDO-09 — the unit contract is "silent branch
/// was taken (no FaceID prompt + toast fired)"; the wire-level integration
/// is covered by the manual QA flow in VALIDATION.md (FIDO-18).
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
        // Avoid leaking state between tests — both the resolver closure and the
        // pendingCodeRequest are writable on the shared singleton.
        RelayClient.shared.accountResolver = nil
        RelayClient.shared.pendingCodeRequest = nil
        TrustWindowManager.shared._resetForTests()
        try await super.tearDown()
    }

    // FIDO-09: in-window + resolver returns account → silent send, pendingCodeRequest stays nil, toast fires
    func testSilentSendInWindow() throws {
        TrustWindowPreference.bootstrap() // preference ON (D-16 default)
        TrustWindowManager.shared._resetForTests()
        TrustWindowManager.shared.mint() // opens 120s window
        RelayClient.shared.pendingCodeRequest = nil
        RelayClient.shared.accountResolver = { _ in
            AccountFixtures.make(issuer: "GitHub", label: "user@example.com")
        }

        let request = CodeRequestFixtures.make(issuer: "GitHub", label: "user@example.com")
        RelayClient.shared.handleDecodedRequest(request)

        // Silent path taken: no FaceID sheet would show
        XCTAssertNil(RelayClient.shared.pendingCodeRequest,
                     "Silent-send branch must NOT set pendingCodeRequest")
        // Toast fired with the issuer name
        XCTAssertEqual(TrustWindowManager.shared.pendingToast?.text, "Code sent for GitHub",
                       "showToast(for:) should publish 'Code sent for GitHub'")
    }

    // FIDO-10: in-window + resolver returns nil (ambiguous) → fall through to pendingCodeRequest, no send
    func testAmbiguousResolutionSetsPendingCodeRequest() throws {
        TrustWindowPreference.bootstrap()
        TrustWindowManager.shared._resetForTests()
        TrustWindowManager.shared.mint() // in-window, but resolver will return nil
        RelayClient.shared.pendingCodeRequest = nil
        RelayClient.shared.accountResolver = { _ in nil } // ambiguous — defer to FaceID

        let request = CodeRequestFixtures.empty(domain: "github.com")
        RelayClient.shared.handleDecodedRequest(request)

        // Fell through: FaceID sheet would appear
        XCTAssertNotNil(RelayClient.shared.pendingCodeRequest,
                        "Ambiguous resolver must fall through to pendingCodeRequest")
        XCTAssertEqual(RelayClient.shared.pendingCodeRequest?.id, request.id,
                       "pendingCodeRequest should be the exact request we handed in")
        // Toast did NOT fire — only the silent branch publishes a toast
        XCTAssertNil(TrustWindowManager.shared.pendingToast,
                     "Fall-through path must NOT publish a toast")
    }

    // FIDO-09 complement: out-of-window always falls through regardless of resolver
    func testOutOfWindowAlwaysSetsPendingCodeRequest() throws {
        TrustWindowPreference.bootstrap()
        TrustWindowManager.shared._resetForTests() // NO mint() — window is closed
        RelayClient.shared.pendingCodeRequest = nil
        // Resolver would happily return a match, but the window check must win.
        RelayClient.shared.accountResolver = { _ in
            AccountFixtures.make(issuer: "GitHub", label: "user@example.com")
        }

        let request = CodeRequestFixtures.make()
        RelayClient.shared.handleDecodedRequest(request)

        XCTAssertNotNil(RelayClient.shared.pendingCodeRequest,
                        "Out-of-window must fall through even when resolver succeeds")
        XCTAssertNil(TrustWindowManager.shared.pendingToast,
                     "Out-of-window path must NOT publish a toast")
    }
}
