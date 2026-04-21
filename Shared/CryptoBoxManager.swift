import Foundation
import CryptoKit

// MARK: - Relay Protocol Types

struct MessageEnvelope: Codable {
    let v: Int
    let type: String
    let id: String
    let payload: [String: String]

    init(type: String, payload: [String: String] = [:]) {
        self.v = 1
        self.type = type
        self.id = UUID().uuidString
        self.payload = payload
    }
}

struct CodeRequest: Codable, Identifiable {
    let id: String
    let issuer: String
    let label: String
    let domain: String?
    let accountId: String?  // UUID string from Account.id; used for targeted code generation (D-02)
}

struct PairingQRPayload: Codable {
    let roomId: String
    let relayURL: String
    let publicKey: String  // base64-encoded Curve25519 public key (32 bytes)
}

struct PairingData: Codable {
    let roomId: String
    let relayURL: String
    let privateKeyRaw: Data       // Curve25519 private key raw bytes (32)
    let peerPublicKeyRaw: Data    // Peer's public key raw bytes (32)
    let sharedKeyRaw: Data        // HKDF-derived symmetric key (32 bytes)
    let pairedAt: Date
}

// MARK: - E2E Encryption

enum CryptoBoxManager {
    /// Generate a new X25519 keypair for pairing
    static func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        return Curve25519.KeyAgreement.PrivateKey()
    }

    /// Derive shared symmetric key from X25519 key exchange
    static func deriveSharedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("KeyAuth-E2E".utf8),
            outputByteCount: 32
        )
    }

    /// Encrypt plaintext. Returns nonce(12) + ciphertext + tag(16).
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return sealedBox.combined  // nonce(12) + ciphertext + tag(16)
    }

    /// Decrypt combined data (nonce + ciphertext + tag).
    static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}
