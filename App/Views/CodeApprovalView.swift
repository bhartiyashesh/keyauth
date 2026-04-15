import SwiftUI

struct CodeApprovalView: View {
    let request: CodeRequest
    let onComplete: () -> Void
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: Account?
    @State private var authFailed = false
    @State private var isAuthenticating = false
    @State private var codeSent = false

    private var needsAccountPicker: Bool {
        request.issuer.isEmpty && request.label.isEmpty
    }

    /// Accounts matching the domain from the code request (e.g., "github.com" matches issuer "GitHub")
    private var domainMatchedAccounts: [Account] {
        guard let domain = request.domain, !domain.isEmpty else { return [] }
        let domainLower = domain.lowercased()
        return store.accounts.filter { account in
            let issuerLower = account.issuer.lowercased()
            // "github.com" matches "GitHub", "google.com" matches "Google"
            return domainLower.contains(issuerLower) || issuerLower.contains(domainLower.replacingOccurrences(of: ".com", with: ""))
        }
    }

    /// Accounts to show in the picker: domain matches first, then the rest
    private var sortedAccounts: [Account] {
        let matched = Set(domainMatchedAccounts.map(\.id))
        let rest = store.accounts.filter { !matched.contains($0.id) }
        return domainMatchedAccounts + rest
    }

    private var headerSubtitle: String {
        if !needsAccountPicker {
            return "\(request.issuer) (\(request.label)) is requesting a code"
        }
        if let domain = request.domain, !domain.isEmpty {
            if domainMatchedAccounts.count == 1 {
                return "Send code for \(domainMatchedAccounts[0].issuer) on \(domain)?"
            }
            return "Pick an account for \(domain)"
        }
        return "Pick an account to send a code for"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Request icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "key.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }

            // Header
            Text("Code Request")
                .font(.headline)
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Account picker when extension doesn't specify
            if needsAccountPicker {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedAccounts) { account in
                            Button {
                                selectedAccount = account
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.issuer)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(account.label)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedAccount?.id == account.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedAccount?.id == account.id
                                              ? Color.blue.opacity(0.1)
                                              : Color(.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 200)
            }

            if authFailed {
                Text("Authentication failed. Tap Approve to retry.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if codeSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            }

            // Approve button
            Button {
                Task { await approveAndSend() }
            } label: {
                Label("Approve", systemImage: "faceid")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating || codeSent || (needsAccountPicker && selectedAccount == nil))
            .padding(.horizontal, 40)

            // Deny button
            Button("Deny") {
                onComplete()
            }
            .font(.system(size: 15))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .interactiveDismissDisabled()
        .onAppear {
            if !needsAccountPicker {
                // Exact issuer/label match
                selectedAccount = store.accounts.first(where: {
                    $0.issuer == request.issuer && $0.label == request.label
                })
            } else if domainMatchedAccounts.count == 1 {
                // Single domain match -- auto-select
                selectedAccount = domainMatchedAccounts.first
            } else if store.accounts.count == 1 {
                // Only one account total -- auto-select
                selectedAccount = store.accounts.first
            }
        }
    }

    @MainActor
    private func approveAndSend() async {
        guard !isAuthenticating else { return }

        let account: Account
        if let selected = selectedAccount {
            account = selected
        } else if !needsAccountPicker,
                  let found = store.accounts.first(where: {
                      $0.issuer == request.issuer && $0.label == request.label
                  }) {
            account = found
        } else {
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        authFailed = false
        let success = await BiometricAuthManager.shared.authenticate(
            reason: "Approve code for \(account.issuer)"
        )

        guard success else {
            authFailed = true
            return
        }

        // Generate and send the first code
        guard let code = TOTPGenerator.generate(for: account) else { return }
        RelayClient.shared.sendEncryptedCode(code, requestId: request.id, issuer: account.issuer, label: account.label)

        codeSent = true

        // Start auto-refresh: keep sending fresh codes for 5 minutes
        startAutoRefresh(account: account)

        // Auto-dismiss after brief confirmation
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        onComplete()
    }

    private func startAutoRefresh(account: Account) {
        // Track last sent code to avoid sending duplicates
        var lastSentCode = TOTPGenerator.generate(for: account) ?? ""

        // Refresh every 1 second, check if code changed (new TOTP period)
        // Stop after 5 minutes (300 seconds)
        let maxDuration: TimeInterval = 300
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            Task { @MainActor in
                // Stop after 5 minutes
                if Date().timeIntervalSince(startTime) > maxDuration {
                    timer.invalidate()
                    return
                }

                // Stop if relay disconnected
                guard RelayClient.shared.state == .connected else {
                    timer.invalidate()
                    return
                }

                // Check if TOTP code changed (new period)
                guard let newCode = TOTPGenerator.generate(for: account),
                      newCode != lastSentCode else { return }

                lastSentCode = newCode
                RelayClient.shared.sendEncryptedCode(
                    newCode, requestId: UUID().uuidString,
                    issuer: account.issuer, label: account.label
                )
                print("[CodeApproval] Auto-refreshed code for \(account.issuer)")
            }
        }
    }
}

