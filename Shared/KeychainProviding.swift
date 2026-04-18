import Foundation

/// Scope of a Keychain query with respect to iCloud sync attribute.
enum SynchronizableScope {
    case localOnly   // kSecAttrSynchronizable = kCFBooleanFalse
    case syncedOnly  // kSecAttrSynchronizable = kCFBooleanTrue
    case any         // kSecAttrSynchronizable = kSecAttrSynchronizableAny
}

/// Sync-aware Keychain CRUD protocol. Enables unit tests via MockKeychain.
protocol KeychainProviding {
    func save(_ account: Account, synchronizable: Bool) throws
    func load(id: UUID) throws -> Account?
    func loadAll() throws -> [Account]
    func loadAllIncludingVariants() throws -> [(account: Account, isSync: Bool)]
    func delete(id: UUID) throws
    func deleteNonSyncOnly(id: UUID) throws
    func deleteAllSynced() throws
    func deleteAll() throws
}
