import SwiftUI

struct PairedDeviceView: View {
    @EnvironmentObject var pairingStore: PairingStore

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text("Browser Paired")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let pairing = pairingStore.pairingData {
                    Text("Room: \(String(pairing.roomId.prefix(8)))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Paired \(pairing.pairedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                pairingStore.unpair()
                RelayClient.shared.disconnect()
            } label: {
                Label("Unpair Browser", systemImage: "xmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 40)
    }

    private var statusDotColor: Color {
        switch RelayClient.shared.state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch RelayClient.shared.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        }
    }
}
