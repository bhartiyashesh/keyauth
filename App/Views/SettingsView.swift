import SwiftUI

/// Phase 6 Settings surface — ICLOUD-04/05/06/14.
///
/// Copy strings below are VERBATIM from the UI-SPEC Copywriting Contract
/// (.planning/phases/06-icloud-keychain-sync/06-UI-SPEC.md lines 131-170).
/// Any change to these literals MUST update the UI-SPEC in the same commit —
/// SettingsViewTests.swift grep-asserts each string for regression safety.
///
/// NOTE (Plan 06-05 TODO): The two `confirmationDialog` action handlers are
/// intentionally stubbed. "Stop syncing this device" flips `SyncPreference` off
/// and logs — Plan 06-05 replaces this body with `MigrationCoordinator.stopSyncingThisDevice()`.
/// "Remove from iCloud on all devices" currently logs and bounces the toggle
/// back to ON (no state commit) — Plan 06-05 replaces this body with
/// `MigrationCoordinator.removeFromICloudAllDevices()`.
struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var icloud: ICloudStateObserver
    @State private var syncEnabled: Bool = SyncPreference.isEnabled
    @State private var showingDisableDialog = false
    @State private var toggleCooldownUntil: Date? = nil

    // UI-SPEC Copywriting Contract — VERBATIM strings. Do not alter without updating UI-SPEC.
    private let disclosureD03 = "Your 2FA accounts sync to your other Apple devices using iCloud Keychain. Protected by your Apple ID and device passcode. Apple can't read them."
    private let disclosureD11 = "iCloud Keychain is turned off on this device."
    private let disclosureD12 = "iCloud Keychain was disabled — sync stopped."
    private let howSecuredCopy = "Your accounts are stored in iCloud Keychain. Apple encrypts them end-to-end using keys derived from your Apple ID and device passcode. Apple cannot read your 2FA secrets — not on their servers, not in transit."

    // D-05 per-option descriptions (UI-SPEC lines 166 and 168) — VERBATIM. These live in the
    // confirmationDialog `message:` closure because SwiftUI's confirmationDialog cannot render
    // per-button descriptions inline.
    private let disableDialogMessageBody = "Choose what happens to the accounts already in iCloud."
    private let stopSyncingDescription = "Stop syncing this device: Your accounts stay on this iPhone. They remain in iCloud and on your other signed-in devices."
    private let removeFromICloudDescription = "Remove from iCloud on all devices: This will remove your accounts from your iPad, Apple Watch, and any other device signed into this iCloud. Accounts on this iPhone stay."

    var body: some View {
        Form {
            syncSection

            if !icloud.isICloudSignedIn {
                openSettingsSection
            }

            securedSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disable iCloud sync?",
            isPresented: $showingDisableDialog,
            titleVisibility: .visible
        ) {
            Button("Stop syncing this device") {
                // Plan 06-05 replaces this stub with MigrationCoordinator.stopSyncingThisDevice()
                print("[Settings] Stop syncing this device tapped — stub; Plan 06-05 wires MigrationCoordinator")
                SyncPreference.setEnabled(false)
                syncEnabled = false
            }
            Button("Remove from iCloud on all devices", role: .destructive) {
                // Plan 06-05 replaces this stub with MigrationCoordinator.removeFromICloudAllDevices()
                print("[Settings] Remove from iCloud on all devices tapped — stub; Plan 06-05 wires MigrationCoordinator")
                // Stub semantics: do NOT commit OFF — bounce the toggle back to ON.
                syncEnabled = true
            }
            Button("Cancel", role: .cancel) {
                // Cancel: toggle snaps back to ON (it was already forced back in handleToggleChange).
                syncEnabled = true
            }
        } message: {
            // VERBATIM D-05 per-option descriptions composed into the single message closure.
            // Blank lines separate the three paragraphs for readability in the native sheet.
            Text("""
            \(disableDialogMessageBody)

            \(stopSyncingDescription)

            \(removeFromICloudDescription)
            """)
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Sync with iCloud Keychain", isOn: $syncEnabled)
                .disabled(!icloud.isICloudSignedIn || isInCooldown)
                .onChange(of: syncEnabled) { newValue in
                    handleToggleChange(newValue: newValue)
                }
        } header: {
            Text("Sync")
        } footer: {
            Text(footerCopy)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var openSettingsSection: some View {
        Section {
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityHint("Opens the iOS Settings app")
        }
    }

    private var securedSection: some View {
        Section {
            DisclosureGroup("How is this secured?") {
                Text(howSecuredCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private var footerCopy: String {
        if !icloud.isICloudSignedIn { return disclosureD11 }
        if icloud.didAccountChange { return disclosureD12 }
        return disclosureD03
    }

    private var isInCooldown: Bool {
        guard let until = toggleCooldownUntil else { return false }
        return until > Date()
    }

    /// OFF-intercept state machine (UI-SPEC "Toggle interaction state machine"):
    /// - Old = ON, new = OFF → snap back to ON visually and open confirmation dialog; the
    ///   dialog's action buttons commit the final state.
    /// - Old = OFF, new = ON → flip SyncPreference on. Plan 06-05 will hook
    ///   MigrationCoordinator.migrateAllToSync() here.
    private func handleToggleChange(newValue: Bool) {
        let previousPreference = SyncPreference.isEnabled
        if previousPreference == true && newValue == false {
            // Snap back to ON visually until user picks an option in the confirmation dialog.
            syncEnabled = true
            showingDisableDialog = true
            return
        }
        if previousPreference == false && newValue == true {
            SyncPreference.setEnabled(true)
        }
    }
}
