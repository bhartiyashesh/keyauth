import SwiftUI

struct CodeApprovalView: View {
    let request: CodeRequest
    let onComplete: () -> Void
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var authFailed = false
    @State private var isAuthenticating = false
    @State private var codeSent = false

    var body: some View {
        VStack(spacing: 24) {
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

            // Request info
            VStack(spacing: 6) {
                Text("\(request.issuer) (\(request.label))")
                    .font(.headline)
                Text("is requesting a code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            .disabled(isAuthenticating || codeSent)
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
        .interactiveDismissDisabled()  // Prevent swipe dismiss -- must approve or deny
    }

    @MainActor
    private func approveAndSend() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        authFailed = false
        let success = await BiometricAuthManager.shared.authenticate(
            reason: "Approve code for \(request.issuer)"
        )

        guard success else {
            authFailed = true
            return
        }

        // Find matching account in local store
        guard let account = store.accounts.first(where: {
            $0.issuer == request.issuer && $0.label == request.label
        }) else { return }

        // Generate TOTP code
        guard let code = TOTPGenerator.generate(for: account) else { return }

        // Encrypt and send via relay
        RelayClient.shared.sendEncryptedCode(code, requestId: request.id)

        codeSent = true

        // Auto-dismiss after brief confirmation (per D-07)
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        onComplete()
    }
}
