import Foundation

@MainActor
final class RelayClient: ObservableObject {
    static let shared = RelayClient()

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    @Published fileprivate(set) var state: ConnectionState = .disconnected
    @Published var pendingCodeRequest: CodeRequest?

    /// Called once after WebSocket connection is established. Set by pairing flow to send ack.
    var onConnected: (() -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var roomId: String?
    fileprivate var deviceToken: String?

    private init() {}

    // MARK: - Connection Lifecycle

    func connect(roomId: String, relayURL: String, deviceToken: String?) {
        guard state == .disconnected else { return }
        self.roomId = roomId
        self.deviceToken = deviceToken
        state = .connecting

        guard let url = URL(string: "\(relayURL)?roomId=\(roomId)") else {
            state = .disconnected
            return
        }

        session = makeSession()
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        pendingCodeRequest = nil
    }

    // MARK: - Sending

    func send(_ envelope: MessageEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { error in
            if let error {
                print("[RelayClient] Send error: \(error.localizedDescription)")
            }
        }
    }

    func sendPairingAck(publicKey: Data) {
        let envelope = MessageEnvelope(
            type: "pairing_ack",
            payload: ["publicKey": publicKey.base64EncodedString()]
        )
        send(envelope)
    }

    func registerToken(_ token: String) {
        self.deviceToken = token
        guard state == .connected else { return }
        let envelope = MessageEnvelope(type: "register_token", payload: ["deviceToken": token])
        send(envelope)
    }

    func sendEncryptedCode(_ code: String, requestId: String) {
        guard let sharedKey = PairingStore.shared.sharedKey else { return }
        let responseJSON: [String: String] = ["code": code, "requestId": requestId]
        guard let plaintext = try? JSONEncoder().encode(responseJSON),
              let encrypted = try? CryptoBoxManager.seal(plaintext, using: sharedKey)
        else { return }
        let envelope = MessageEnvelope(
            type: "code_response",
            payload: ["data": encrypted.base64EncodedString()]
        )
        send(envelope)
    }

    // MARK: - Receiving

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveLoop()  // MUST re-call for next message
                case .failure:
                    self.state = .disconnected
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(MessageEnvelope.self, from: data)
            else { return }

            switch envelope.type {
            case "joined":
                print("[RelayClient] Joined room successfully")

            case "error":
                let errorMsg = envelope.payload["message"] ?? "Unknown error"
                print("[RelayClient] Server error: \(errorMsg)")

            default:
                // Opaque forwarded message from Chrome extension -- decrypt
                guard let encryptedBase64 = envelope.payload["data"],
                      let encryptedData = Data(base64Encoded: encryptedBase64),
                      let sharedKey = PairingStore.shared.sharedKey,
                      let plaintext = try? CryptoBoxManager.open(encryptedData, using: sharedKey),
                      let request = try? JSONDecoder().decode(CodeRequest.self, from: plaintext)
                else { return }

                pendingCodeRequest = request
            }

        case .data:
            break  // Binary messages not expected

        @unknown default:
            break
        }
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: WebSocketDelegate.shared, delegateQueue: .main)
    }
}

// MARK: - WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    static let shared = WebSocketDelegate()

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            let relay = RelayClient.shared
            relay.state = .connected
            let joinPayload: [String: String] = relay.deviceToken.map { ["deviceToken": $0] } ?? [:]
            let joinEnvelope = MessageEnvelope(type: "join", payload: joinPayload)
            relay.send(joinEnvelope)
            relay.onConnected?()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            RelayClient.shared.state = .disconnected
        }
    }
}
