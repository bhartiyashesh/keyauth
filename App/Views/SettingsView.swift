import SwiftUI

/// Phase 6 Settings surface — ICLOUD-04/05/06/07/14/16.
///
/// Copy strings below are VERBATIM from the UI-SPEC Copywriting Contract
/// (.planning/phases/06-icloud-keychain-sync/06-UI-SPEC.md lines 131-170).
/// Any change to these literals MUST update the UI-SPEC in the same commit —
/// SettingsViewTests.swift grep-asserts each string for regression safety.
///
/// Plan 06-05 wired the three formerly-stubbed call sites (OFF→ON migration in
/// `handleToggleChange`, `Stop syncing this device`, `Remove from iCloud on all devices`)
/// to the real `MigrationCoordinator`. The toggle is now `.disabled` during migration
/// AND during the 10-second destructive cooldown. A migration-progress Section renders
/// when `total > 10`.
struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var icloud: ICloudStateObserver
    @EnvironmentObject var migration: MigrationCoordinator
    @State private var syncEnabled: Bool = SyncPreference.isEnabled
    @State private var showingDisableDialog = false

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

            if migration.isRunning && migration.progress.total > 10 {
                migrationProgressSection
            }

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
                Task {
                    await migration.stopSyncingThisDevice()
                    syncEnabled = false
                }
            }
            Button("Remove from iCloud on all devices", role: .destructive) {
                Task {
                    do {
                        try await migration.removeFromICloudAllDevices()
                    } catch {
                        // Error already surfaced via AccountStore.error.
                    }
                    syncEnabled = false
                }
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
                .disabled(!icloud.isICloudSignedIn || isInCooldown || migration.isRunning)
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

    /// Rendered in `body` when `migration.isRunning && migration.progress.total > 10`.
    /// Header copy is VERBATIM per UI-SPEC Migration Progress section.
    private var migrationProgressSection: some View {
        Section {
            HStack {
                ProgressView(
                    value: Double(migration.progress.done) / Double(max(migration.progress.total, 1))
                )
                Text("\(migration.progress.done) of \(migration.progress.total)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Migrating \(migration.progress.done) of \(migration.progress.total) accounts"
                    )
            }
        } header: {
            Text("Moving your accounts to iCloud…")
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
        guard let until = migration.toggleCooldownUntil else { return false }
        return until > Date()
    }

    /// OFF-intercept state machine (UI-SPEC "Toggle interaction state machine"):
    /// - Old = ON, new = OFF → snap back to ON visually and open confirmation dialog; the
    ///   dialog's action buttons commit the final state.
    /// - Old = OFF, new = ON → kick off `MigrationCoordinator.migrateAllToSync()`. The
    ///   coordinator sets `SyncPreference.setEnabled(true)` after the bulk re-save loop,
    ///   updates `store.lastDedupCount`, and exposes `isRunning`/`progress` for the UI.
    private func handleToggleChange(newValue: Bool) {
        let previousPreference = SyncPreference.isEnabled
        if previousPreference == true && newValue == false {
            // Snap back to ON visually until user picks an option in the confirmation dialog.
            syncEnabled = true
            showingDisableDialog = true
            return
        }
        if previousPreference == false && newValue == true {
            Task {
                _ = await migration.migrateAllToSync()
                // Dedup count is surfaced via store.lastDedupCount; downstream toast UI may
                // be rendered by ContentView overlay or a future Settings footer.
            }
        }
    }
}
