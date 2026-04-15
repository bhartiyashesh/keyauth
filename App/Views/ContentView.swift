import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
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
            ScrollView {
                if store.accounts.isEmpty {
                    emptyState
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredAccounts) { account in
                            AccountRowView(account: account)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(account)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("KeyAuth")
            .searchable(text: $searchText, prompt: "Search accounts")
            .toolbar {
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

                Text("Add a 2FA account to get started.\nYour codes will also appear in the\nKeyAuth keyboard.")
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
