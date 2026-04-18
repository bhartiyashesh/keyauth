import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    // Service/access-group are `var` to allow #if DEBUG test-only overrides; production
    // callers never mutate them outside `_setServiceForTesting` / `_resetToProductionService`.
    private var service: String = "com.keyauth.accounts"
    // Set to "TEAMID.com.keyauth.shared" with your actual Apple Team ID
    // for app-extension Keychain sharing. nil disables the access group (used by tests).
    private var accessGroup: String? = "W646UCTVQV.com.keyauth.shared"

    private init() {}

    #if DEBUG
    /// Test-only hook — override the service name and access group so `KeychainManagerSyncTests`
    /// can run against isolated Keychain items without polluting real user data.
    internal func _setServiceForTesting(_ service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Test-only hook — restore production values after a test finishes.
    internal func _resetToProductionService() {
        self.service = "com.keyauth.accounts"
        self.accessGroup = "W646UCTVQV.com.keyauth.shared"
    }
    #endif

    // MARK: - CRUD (sync-aware)

    func save(_ account: Account, synchronizable: Bool) throws {
        let data = try JSONEncoder().encode(account)
        let key = account.id.uuidString
        let scope: SynchronizableScope = synchronizable ? .syncedOnly : .localOnly
        let query = baseQuery(for: key, synchronizable: scope)

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
            if insertStatus == errSecDuplicateItem {
                // RESEARCH.md lines 386-388: another device's synced copy may have raced our
                // SecItemCopyMatching existence check. Fall through to SecItemUpdate.
                let updateStatus = SecItemUpdate(
                    query as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary
                )
                guard updateStatus == errSecSuccess else {
                    throw KeychainError.updateFailed(updateStatus)
                }
            } else if insertStatus != errSecSuccess {
                throw KeychainError.saveFailed(insertStatus)
            }
        }
    }

    func load(id: UUID) throws -> Account? {
        var query = baseQuery(for: id.uuidString, synchronizable: .any)
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
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
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

    /// Returns every account together with its sync attribute. Used by the Plan 05
    /// MigrationCoordinator to distinguish local-only from synced variants.
    func loadAllIncludingVariants() throws -> [(account: Account, isSync: Bool)] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound { return [] }
            throw KeychainError.loadFailed(status)
        }

        let decoder = JSONDecoder()
        return items.compactMap { item -> (account: Account, isSync: Bool)? in
            guard let data = item[kSecValueData as String] as? Data,
                  let account = try? decoder.decode(Account.self, from: data) else {
                return nil
            }
            let isSync = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
            return (account, isSync)
        }
    }

    /// Deletes BOTH sync and non-sync copies of the given account (uses SynchronizableAny).
    func delete(id: UUID) throws {
        let query = baseQuery(for: id.uuidString, synchronizable: .any)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Deletes ONLY the non-synchronizable copy (used by MigrationCoordinator step 2 — the
    /// forward-migration "safe ordering" cleanup after re-saving as synced).
    func deleteNonSyncOnly(id: UUID) throws {
        let query = baseQuery(for: id.uuidString, synchronizable: .localOnly)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Deletes ALL synced copies in this service (used by D-05 "Remove from iCloud on all devices").
    /// Uses `kSecAttrSynchronizable = kCFBooleanTrue` (NOT `kSecAttrSynchronizableAny`) so
    /// non-sync local copies survive the purge.
    func deleteAllSynced() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
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

    /// Single source of truth for Keychain query construction.
    /// RESEARCH.md Risk 1 mitigation: every SecItem* call routes through here so that the
    /// `kSecAttrSynchronizable` attribute is explicit on every operation.
    private func baseQuery(for key: String, synchronizable: SynchronizableScope) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        switch synchronizable {
        case .localOnly:
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        case .syncedOnly:
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        case .any:
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
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

extension KeychainManager: KeychainProviding {}
