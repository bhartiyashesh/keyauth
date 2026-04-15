import Foundation
import Security
import CryptoKit

@MainActor
final class PairingStore: ObservableObject {
    static let shared = PairingStore()

    @Published private(set) var pairingData: PairingData?
    @Published var error: String?

    var isPaired: Bool { pairingData != nil }

    var sharedKey: SymmetricKey? {
        guard let raw = pairingData?.sharedKeyRaw else { return nil }
        return SymmetricKey(data: raw)
    }

    private let service = "com.keyauth.pairing"
    private let accessGroup: String? = "W646UCTVQV.com.keyauth.shared"
    private let pairingKey = "active_pairing"

    private init() {
        reload()
    }

    func reload() {
        do {
            pairingData = try loadFromKeychain()
            error = nil
        } catch {
            self.error = error.localizedDescription
            pairingData = nil
        }
    }

    func savePairing(_ pairing: PairingData) throws {
        try saveToKeychain(pairing)
        pairingData = pairing
        error = nil
    }

    func unpair() {
        deleteFromKeychain()
        pairingData = nil
        error = nil
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairingKey
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private func saveToKeychain(_ pairing: PairingData) throws {
        let data = try JSONEncoder().encode(pairing)
        let query = baseQuery()

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.updateFailed(updateStatus)
            }
        } else {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainError.saveFailed(insertStatus)
            }
        }
    }

    private func loadFromKeychain() throws -> PairingData? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }

        return try JSONDecoder().decode(PairingData.self, from: data)
    }

    private func deleteFromKeychain() {
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
    }
}
