import SwiftUI

/// ICLOUD-16 state machine for the "Restoring from iCloud" empty-state.
/// Transitions are driven by `ContentView.evaluateRestoringState(timeout:)` + the
/// `onChange(of: store.accounts)` observer in ContentView.body.
enum SyncState { case idle, restoring, restored, timedOut }

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var trustWindow: TrustWindowManager
    @ObservedObject private var relayClient = RelayClient.shared
    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var searchText = ""
    @State private var navigateToSettings = false
    @State private var syncState: SyncState = .idle
    @State private var restoringStartedAt: Date? = nil

    var filteredAccounts: [Account] {
        if searchText.isEmpty { return store.accounts }
        return store.accounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            if syncState == .restoring {
                                RestoringFromCloudView()
                                    .padding(.top, 80)
                            } else {
                                if SyncPreference.shouldShowFirstLaunchCard(accountsIsEmpty: true) {
                                    FirstLaunchSyncCard(
                                        onDismiss: {
                                            SyncPreference.markFirstLaunchCardSeen()
                                        },
                                        onManage: {
                                            SyncPreference.markFirstLaunchCardSeen()
                                            navigateToSettings = true
                                        }
                                    )
                                    .padding(.top, 24)
                                }
                                emptyState
                                    .padding(.top, SyncPreference.shouldShowFirstLaunchCard(accountsIsEmpty: true) ? 24 : 80)
                            }
                        }
                    }
                } else {
                    List {
                        ForEach(filteredAccounts) { account in
                            AccountRowView(account: account)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onDelete { offsets in
                            store.delete(at: offsets)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Much Better Authenticator")
            .searchable(text: $searchText, prompt: "Search accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        PairingView()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusDotColor)
                                .frame(width: 8, height: 8)
                            Image(systemName: "link")
                                .font(.system(size: 16))
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            showingManualEntry = true
                        } label: {
                            Label("Enter Manually", systemImage: "keyboard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $navigateToSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { account in
                    store.add(account)
                    showingScanner = false
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView { account in
                    store.add(account)
                    showingManualEntry = false
                }
            }
            .sheet(item: $relayClient.pendingCodeRequest) { request in
                CodeApprovalView(request: request) {
                    relayClient.pendingCodeRequest = nil
                }
                .environmentObject(store)
            }
            .overlay(alignment: .top) {
                if let toast = trustWindow.pendingToast {
                    TransientToastOverlay(
                        message: toast.text,
                        icon: "paperplane.fill",
                        iconColor: .secondary,
                        duration: 2.0,
                        isPresented: .constant(true)
                    )
                    .padding(.top, 8)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: trustWindow.pendingToast)
            .onAppear {
                evaluateRestoringState()
            }
            .onChange(of: store.accounts) { newAccounts in
                if !newAccounts.isEmpty && syncState == .restoring {
                    syncState = .restored
                }
            }
        }
    }

    /// ICLOUD-16 restoring state machine.
    ///
    /// Trigger conditions for the `.idle → .restoring` transition: sync is enabled AND
    /// accounts are still empty (fresh install / KVS not yet delivered). Enters `.restoring`
    /// immediately, schedules a `timeout`-second delayed fallthrough to `.timedOut` if
    /// accounts are still empty when the timer fires. If accounts arrive before the timer,
    /// `onChange(of: store.accounts)` flips state to `.restored` instead.
    ///
    /// `timeout` defaults to `RestoringFromCloudView.restoringTimeoutSeconds` (30s production
    /// value per D-09). `RestoringStateTests` injects sub-second values (50ms) to
    /// deterministically exercise the `.restoring → .timedOut` transition without waiting
    /// half a minute per test.
    ///
    /// Method is `internal` (default) so `@testable import KeyAuth` can reach it.
    func evaluateRestoringState(timeout: TimeInterval = RestoringFromCloudView.restoringTimeoutSeconds) {
        guard syncState == .idle else { return }
        if SyncPreference.isEnabled && store.accounts.isEmpty {
            syncState = .restoring
            restoringStartedAt = Date()
            let timeoutNanos = UInt64(timeout * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanos)
                if syncState == .restoring && store.accounts.isEmpty {
                    syncState = .timedOut
                }
            }
        } else if !store.accounts.isEmpty && syncState == .restoring {
            syncState = .restored
        }
    }

    private var statusDotColor: Color {
        switch relayClient.state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                Text("No accounts yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add a 2FA account to get started.\nYour codes will also appear in the\nMuch Better Authenticator keyboard.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: 240)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingManualEntry = true
                } label: {
                    Label("Enter Manually", systemImage: "keyboard")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: 240)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }
}
