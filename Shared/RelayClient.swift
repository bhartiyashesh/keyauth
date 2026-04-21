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

    /// Resolves a decoded `CodeRequest` to a concrete `Account`. Set ONCE by KeyAuthApp.onAppear.
    /// Returns `nil` when the request is ambiguous — the silent-send branch falls through to FaceID.
    /// Anti-drift with `CodeApprovalView.onAppear` is guaranteed by Plan 07-05 routing both
    /// call sites through `AccountStore.resolve(for:)`.
    var accountResolver: ((CodeRequest) -> Account?)?

    /// Provides current account list for sending to extension on connect.
    /// Set once in KeyAuthApp.onAppear. Called on every WebSocket connection.
    var accountListProvider: (() -> [Account])?

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

    // Proactive reconnect (D-08: 13-min timer avoids Railway's 15-min WebSocket timeout)
    private var proactiveReconnectTimer: Timer?
    private let proactiveReconnectInterval: TimeInterval = 13 * 60 // 13 minutes

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

    /// Send account metadata list to paired Chrome extension (D-01).
    /// Called on every WebSocket connect so extension has fresh data.
    /// Only sends id, issuer, label — secrets NEVER leave the phone.
    func sendAccountListPayload(_ accounts: [Account]) {
        guard let sharedKey = PairingStore.shared.sharedKey else { return }
        let metadata: [[String: String]] = accounts.map {
            ["id": $0.id.uuidString, "issuer": $0.issuer, "label": $0.label]
        }
        let payload: [String: Any] = ["accounts": metadata]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let encrypted = try? CryptoBoxManager.seal(jsonData, using: sharedKey)
        else { return }
        let envelope = MessageEnvelope(
            type: "account_list",
            payload: ["data": encrypted.base64EncodedString()]
        )
        send(envelope)
        print("[RelayClient] Sent account list (\(metadata.count) accounts)")
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

                handleDecodedRequest(request)
            }

        case .data:
            break

        @unknown default:
            break
        }
    }

    /// Silent-send gate (Phase 7 FIDO-09 / FIDO-10). Extracted from the `default:` clause so
    /// unit tests can call it directly with a CodeRequestFixtures-built `CodeRequest` without
    /// needing a live WebSocket or PairingStore.
    ///
    /// Silent path (ALL must hold):
    ///   - `TrustWindowManager.shared.isInWindow == true` (FIDO-02 + Pitfall 7 lazy check)
    ///   - `TrustWindowPreference.isEnabled == true` (FIDO-03 / D-17 redundant guard)
    ///   - `accountResolver != nil`
    ///   - `accountResolver(request)` returns a non-nil `Account`
    ///   - `TOTPGenerator.generate(for: account)` returns a code
    ///
    /// Any failure → fall through to the existing `pendingCodeRequest = request` behavior
    /// (CodeApprovalView will present to the user).
    internal func handleDecodedRequest(_ request: CodeRequest) {
        if TrustWindowManager.shared.isInWindow,
           TrustWindowPreference.isEnabled,
           let resolver = accountResolver,
           let account = resolver(request),
           let code = TOTPGenerator.generate(for: account) {
            sendEncryptedCode(code, requestId: request.id,
                              issuer: account.issuer, label: account.label)
            TrustWindowManager.shared.showToast(for: account.issuer)
            return
        }

        pendingCodeRequest = request
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

    // MARK: - Proactive Reconnect

    fileprivate func startProactiveReconnect() {
        proactiveReconnectTimer?.invalidate()
        proactiveReconnectTimer = Timer.scheduledTimer(
            withTimeInterval: proactiveReconnectInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let roomId = self.roomId, let relayURL = self.relayURL else { return }
                print("[RelayClient] Proactive reconnect (13min timer)")
                // Graceful close — handleDisconnect will trigger scheduleReconnect
                self.webSocketTask?.cancel(with: .normalClosure, reason: "proactive".data(using: .utf8))
                self.webSocketTask = nil
                self.session?.invalidateAndCancel()
                self.session = nil
                self.stopTimers()
                self.state = .disconnected
                self.reconnectAttempts = 0 // Proactive reconnect = immediate retry, no backoff
                self.connect(roomId: roomId, relayURL: relayURL, deviceToken: self.deviceToken)
            }
        }
    }

    // MARK: - Cleanup

    private func stopTimers() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        proactiveReconnectTimer?.invalidate()
        proactiveReconnectTimer = nil
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

            // D-08/RESIL-02: Proactive reconnect before Railway 15-min timeout
            relay.startProactiveReconnect()

            // D-01: Send account list to extension on every connect
            if let accounts = relay.accountListProvider?() {
                relay.sendAccountListPayload(accounts)
            }

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
