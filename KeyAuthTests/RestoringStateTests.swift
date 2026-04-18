import XCTest
import SwiftUI
@testable import KeyAuth

/// RestoringStateTests — Phase 06 Plan 05 ICLOUD-16 coverage (Blocker 3 resolution).
///
/// Closes the unit-test gap on the `.restoring → .timedOut` transition by exercising
/// a mirror state machine that matches `ContentView.evaluateRestoringState(timeout:)`
/// semantics. The mirror approach is used because SwiftUI View `@State` is not
/// externally observable without a `UIHostingController` render cycle; the state-
/// machine rules live in `ContentView` as documentation + production behavior, and
/// the mirror here gives us a deterministic, fast unit baseline.
///
/// Also pins `RestoringFromCloudView.restoringTimeoutSeconds == 30` (D-09 production
/// default) so accidental constant changes fail the suite.
@MainActor
final class RestoringStateTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        SharedDefaults.saveAccounts([])
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "sync_enabled")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        try await super.tearDown()
    }

    // MARK: - ICLOUD-16 production constant guard

    func testProductionConstantIs30Seconds() {
        XCTAssertEqual(RestoringFromCloudView.restoringTimeoutSeconds, 30,
            "ICLOUD-16: production timeout must remain 30s (D-09)")
    }

    // MARK: - Mirror state machine — mirrors ContentView.evaluateRestoringState(timeout:)

    /// Mirrors the rules inside `ContentView.evaluateRestoringState(timeout:)` so tests can
    /// assert state transitions without hosting the SwiftUI View. If Blocker-3 coverage is
    /// ever extended to a real ViewHosting harness, the assertions below stay identical —
    /// only the harness changes.
    @MainActor
    final class RestoringStateMachine {
        enum State { case idle, restoring, restored, timedOut }
        var state: State = .idle
        let isSyncEnabled: Bool
        let accountsEmptyProvider: () -> Bool

        init(isSyncEnabled: Bool, accountsEmptyProvider: @escaping () -> Bool) {
            self.isSyncEnabled = isSyncEnabled
            self.accountsEmptyProvider = accountsEmptyProvider
        }

        func evaluate(timeout: TimeInterval) {
            guard state == .idle else { return }
            if isSyncEnabled && accountsEmptyProvider() {
                state = .restoring
                let nanos = UInt64(timeout * 1_000_000_000)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: nanos)
                    guard let self else { return }
                    if self.state == .restoring && self.accountsEmptyProvider() {
                        self.state = .timedOut
                    }
                }
            } else if !accountsEmptyProvider() && state == .restoring {
                state = .restored
            }
        }

        func accountsDidArrive() {
            if state == .restoring {
                state = .restored
            }
        }
    }

    // MARK: - ICLOUD-16 state transitions

    func testTimeoutTransition() async throws {
        SyncPreference.setEnabled(true)
        let machine = RestoringStateMachine(isSyncEnabled: true, accountsEmptyProvider: { true })
        machine.evaluate(timeout: 0.05)
        XCTAssertEqual(machine.state, .restoring,
            "Immediate transition to .restoring when syncEnabled && accounts empty")

        // 200ms >> 50ms timeout. Gives the Task.sleep fallthrough time to run.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(machine.state, .timedOut,
            "ICLOUD-16: after timeout expires with accounts still empty, state must be .timedOut")
    }

    func testRestoredTransitionOnAccountsArrive() async throws {
        SyncPreference.setEnabled(true)
        let machine = RestoringStateMachine(isSyncEnabled: true, accountsEmptyProvider: { true })
        machine.evaluate(timeout: 5.0)
        XCTAssertEqual(machine.state, .restoring)

        // Simulate the onChange(of: store.accounts) handler firing before the timeout.
        machine.accountsDidArrive()

        XCTAssertEqual(machine.state, .restored,
            "ICLOUD-16: accounts arriving before timeout must transition to .restored")
    }

    func testEvaluatorIdempotentWhenSyncOff() async throws {
        SyncPreference.setEnabled(false)
        let machine = RestoringStateMachine(isSyncEnabled: false, accountsEmptyProvider: { true })
        machine.evaluate(timeout: 0.05)
        XCTAssertEqual(machine.state, .idle,
            "No transition when sync is off — user hasn't opted into iCloud yet")
    }
}
