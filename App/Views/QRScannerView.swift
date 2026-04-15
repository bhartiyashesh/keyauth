import SwiftUI
import AVFoundation

struct QRScannerView: View {
    let onScanned: (Account) -> Void
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

                    // Scanning frame overlay
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .shadow(color: .black.opacity(0.3), radius: 10)

                    Spacer()

                    VStack(spacing: 8) {
                        Text("Point at a QR code")
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
            .navigationTitle("Scan QR Code")
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

        guard let url = URL(string: code) else {
            error = "Invalid QR code"
            return
        }

        guard let account = Account.from(otpauthURL: url) else {
            error = "Not a valid authenticator QR code"
            return
        }

        scanned = true
        onScanned(account)
    }
}

// MARK: - Camera Preview

struct QRCameraPreview: UIViewRepresentable {
    let onCodeDetected: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return view
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        let onCodeDetected: (String) -> Void

        init(onCodeDetected: @escaping (String) -> Void) {
            self.onCodeDetected = onCodeDetected
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else { return }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            session?.stopRunning()
            onCodeDetected(value)
        }
    }
}
