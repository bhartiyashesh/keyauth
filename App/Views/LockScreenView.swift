import SwiftUI

struct LockScreenView: View {
    var onUnlock: () -> Void
    @State private var authFailed = false
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 100, height: 100)
                    if #available(iOS 17.0, *) {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 44))
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 44))
                            .foregroundStyle(.blue)
                    }
                }

                VStack(spacing: 6) {
                    Text("Better Authenticator")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Authenticate to view your codes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if authFailed {
                    Text("Authentication failed. Tap to retry.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    Task { await performAuth() }
                } label: {
                    Label("Unlock", systemImage: biometricIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)
                .padding(.bottom, 48)
            }
        }
        .task {
            await performAuth()
        }
    }

    @MainActor
    private func performAuth() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        authFailed = false
        let success = await BiometricAuthManager.shared.authenticate()
        if success {
            onUnlock()
        } else {
            authFailed = true
        }
    }

    private var biometricIcon: String {
        switch BiometricAuthManager.shared.availableBiometric {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.shield"
        }
    }
}
