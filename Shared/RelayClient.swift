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
    private(set) var roomId: String?
    private var relayURL: String?
    fileprivate var deviceToken: String?

    // Reconnection state
    fileprivate var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private var intentionalDisconnect = false
    private let reconnectBaseInterval: TimeInterval = 1.0
    private let reconnectMaxInterval: TimeInterval = 30.0

    // Keepalive
    private var keepaliveTimer: Timer?
    private let keepaliveInterval: TimeInterval = 20.0

    private init() {}

    // MARK: - Connection Lifecycle

    func connect(roomId: String, relayURL: String, deviceToken: String?) {
        // Allow reconnect even if already connecting/connected to the same room
        if state != .disconnected && self.roomId == roomId { return }

        cleanup()
        intentionalDisconnect = false
        self.roomId = roomId
        self.relayURL = relayURL
        self.deviceToken = deviceToken
        state = .connecting

        guard let url = URL(string: "\(relayURL)?roomId=\(roomId)") else {
            state = .disconnected
            return
        }

        print("[RelayClient] Connecting to room \(roomId.prefix(8))...")
        session = makeSession()
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
    }

    func disconnect() {
        intentionalDisconnect = true
        cleanup()
        state = .disconnected
        pendingCodeRequest = nil
    }

    /// Reconnect to the current room (e.g., after foreground resume)
    func reconnectIfNeeded() {
        guard state == .disconnected,
              !intentionalDisconnect,
              let roomId, let relayURL else { return }
        reconnectAttempts = 0 // Fresh foreground = reset backoff
        connect(roomId: roomId, relayURL: relayURL, deviceToken: deviceToken)
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

    func sendEncryptedCode(_ code: String, requestId: String, issuer: String, label: String) {
        guard let sharedKey = PairingStore.shared.sharedKey else { return }
        let responseJSON: [String: String] = ["code": code, "requestId": requestId, "issuer": issuer, "label": label]
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
                case .failure(let error):
                    print("[RelayClient] Receive error: \(error.localizedDescription)")
                    self.handleDisconnect()
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

            case "pong":
                break // Keepalive response

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
            break

        @unknown default:
            break
        }
    }

    // MARK: - Reconnection

    fileprivate func handleDisconnect() {
        stopTimers()
        state = .disconnected

        guard !intentionalDisconnect else { return }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped)
        let delay = min(reconnectBaseInterval * pow(2.0, Double(reconnectAttempts)), reconnectMaxInterval)
        reconnectAttempts += 1

        print("[RelayClient] Scheduling reconnect in \(delay)s (attempt \(reconnectAttempts))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let roomId = self.roomId, let relayURL = self.relayURL else { return }
                self.state = .disconnected // Reset so connect() guard passes
                self.connect(roomId: roomId, relayURL: relayURL, deviceToken: self.deviceToken)
            }
        }
    }

    // MARK: - Keepalive

    fileprivate func startKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .connected else { return }
                self.send(MessageEnvelope(type: "ping", payload: [:]))
            }
        }
    }

    // MARK: - Cleanup

    private func stopTimers() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    private func cleanup() {
        stopTimers()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

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
            relay.reconnectAttempts = 0 // Reset backoff on successful connect

            let joinPayload: [String: String] = relay.deviceToken.map { ["deviceToken": $0] } ?? [:]
            let joinEnvelope = MessageEnvelope(type: "join", payload: joinPayload)
            relay.send(joinEnvelope)

            // Start keepalive pings
            relay.startKeepalive()

            // Fire one-shot connected callback (used by pairing flow)
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
            print("[RelayClient] WebSocket closed, code: \(closeCode.rawValue)")
            RelayClient.shared.handleDisconnect()
        }
    }
}
