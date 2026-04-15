import SwiftUI
import CryptoKit

struct PairingView: View {
    @EnvironmentObject var pairingStore: PairingStore
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if pairingStore.isPaired {
                    PairedDeviceView()
                        .environmentObject(pairingStore)
                } else {
                    unpairedContent
                }
            }
            .navigationTitle("Browser Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                PairingQRScannerView { payload in
                    handlePairingQR(payload)
                    showingScanner = false
                }
            }
        }
    }

    private var unpairedContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                Text("No browser paired")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Scan the QR code shown in the\nKeyAuth Chrome extension to pair.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingScanner = true
            } label: {
                Label("Pair Browser", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 40)
    }

    private func handlePairingQR(_ payload: PairingQRPayload) {
        do {
            // Generate our keypair
            let privateKey = CryptoBoxManager.generateKeyPair()

            // Decode peer's public key from base64
            guard let peerPublicKeyData = Data(base64Encoded: payload.publicKey) else { return }
            let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)

            // Derive shared key
            let sharedKey = try CryptoBoxManager.deriveSharedKey(privateKey: privateKey, peerPublicKey: peerPublicKey)

            // Extract raw bytes from SymmetricKey
            let sharedKeyRaw = sharedKey.withUnsafeBytes { Data($0) }

            // Save pairing data
            let pairingData = PairingData(
                roomId: payload.roomId,
                relayURL: payload.relayURL,
                privateKeyRaw: privateKey.rawRepresentation,
                peerPublicKeyRaw: peerPublicKeyData,
                sharedKeyRaw: sharedKeyRaw,
                pairedAt: Date()
            )
            try pairingStore.savePairing(pairingData)

            // Connect to relay and send pairing ack with our public key
            let relay = RelayClient.shared
            let ourPublicKeyData = privateKey.publicKey.rawRepresentation
            relay.connect(
                roomId: payload.roomId,
                relayURL: payload.relayURL,
                deviceToken: nil  // Will be registered via AppDelegate callback
            )
            // Send pairing_ack after connection is established
            relay.onConnected = {
                relay.sendPairingAck(publicKey: ourPublicKeyData)
                relay.onConnected = nil
            }
        } catch {
            // Pairing failed -- error surfaced via pairingStore.error
        }
    }
}
