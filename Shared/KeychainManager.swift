import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.keyauth.accounts"
    // Set to "TEAMID.com.keyauth.shared" with your actual Apple Team ID
    // for app-extension Keychain sharing. nil uses the default access group.
    private let accessGroup: String? = "W646UCTVQV.com.keyauth.shared"

    private init() {}

    // MARK: - CRUD

    func save(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)
        let key = account.id.uuidString
        let query: [String: Any] = baseQuery(for: key)

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

    func load(id: UUID) throws -> Account? {
        var query = baseQuery(for: id.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }

        return try JSONDecoder().decode(Account.self, from: data)
    }

    func loadAll() throws -> [Account] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [Data] else {
            if status == errSecItemNotFound { return [] }
            throw KeychainError.loadFailed(status)
        }

        let decoder = JSONDecoder()
        return items.compactMap { try? decoder.decode(Account.self, from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func delete(id: UUID) throws {
        let query = baseQuery(for: id.uuidString)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Helpers

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case updateFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .updateFailed(let s): return "Keychain update failed: \(s)"
        case .loadFailed(let s): return "Keychain load failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        }
    }
}
