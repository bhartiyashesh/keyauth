import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @ObservedObject private var relayClient = RelayClient.shared
    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var searchText = ""

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
                        emptyState
                            .padding(.top, 80)
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
            .navigationTitle("Better Authenticator")
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

                Text("Add a 2FA account to get started.\nYour codes will also appear in the\nBetter Authenticator keyboard.")
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
