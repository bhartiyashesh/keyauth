import SwiftUI

/// Phase 6 ICLOUD-05 — first-launch iCloud sync onboarding card.
///
/// Renders above `ContentView.emptyState` when `SyncPreference.shouldShowFirstLaunchCard`
/// returns true (new user, sync ON, accounts empty, not yet dismissed).
///
/// Copy strings are VERBATIM per UI-SPEC Copywriting Contract (UI-SPEC lines 149-152).
/// The body copy is identical to D-03 per D-04 (consistent disclosure across surfaces).
struct FirstLaunchSyncCard: View {
    let onDismiss: () -> Void
    let onManage: () -> Void

    // UI-SPEC copy — VERBATIM. Body copy mirrors D-03 per D-04.
    private let titleCopy = "Sync across your Apple devices"
    private let bodyCopy = "Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleCopy)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(bodyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Got it", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Dismiss sync onboarding")
                Button("Manage in Settings", action: onManage)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}
