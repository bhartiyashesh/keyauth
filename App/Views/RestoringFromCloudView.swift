import SwiftUI

/// ICLOUD-16 — empty-state "Restoring your accounts from iCloud…" screen per UI-SPEC.
///
/// Shown by `ContentView` when `syncState == .restoring` (sync just flipped ON, accounts
/// still empty within the `restoringTimeoutSeconds` window). Falls through to the regular
/// empty-state after the timeout expires.
///
/// Copy strings below are VERBATIM from the UI-SPEC Copywriting Contract
/// (.planning/phases/06-icloud-keychain-sync/06-UI-SPEC.md lines 156-157).
struct RestoringFromCloudView: View {
    /// ICLOUD-16 timeout (seconds). Default 30; overridable for unit tests via
    /// `ContentView.evaluateRestoringState(timeout:)` parameter.
    /// Production consumers use the default; `RestoringStateTests` injects sub-second values
    /// to verify the `.restoring → .timedOut` state transition deterministically.
    static let restoringTimeoutSeconds: TimeInterval = 30

    // UI-SPEC copy — VERBATIM. Renamed to `titleCopy` / `bodyCopy` (not `title`/`body`) to
    // avoid collision with SwiftUI View's required `var body: some View` (same fix as
    // FirstLaunchSyncCard in Plan 06-04).
    private let titleCopy = "Restoring your accounts from iCloud…"
    private let bodyCopy = "This usually takes a few seconds. You can leave this screen open."

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 88, height: 88)
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.blue)
            }
            VStack(spacing: 6) {
                Text(titleCopy)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text(bodyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Restoring your accounts from iCloud")
    }
}
