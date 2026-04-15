import SwiftUI

struct PairingQRScannerView: View {
    let onPaired: (PairingQRPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRCameraPreview(onCodeDetected: handleCode)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .shadow(color: .black.opacity(0.3), radius: 10)

                    Spacer()

                    VStack(spacing: 8) {
                        Text("Scan pairing QR code")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("Scan Pairing Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleCode(_ code: String) {
        guard !scanned else { return }
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data)
        else {
            error = "Invalid pairing QR code"
            return
        }
        scanned = true
        onPaired(payload)
    }
}
