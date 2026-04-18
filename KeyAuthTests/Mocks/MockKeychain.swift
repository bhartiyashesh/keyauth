import Foundation
@testable import KeyAuth

/// In-memory KeychainProviding for unit tests. Models (account, isSync) tuples so the
/// same account.id can exist twice with different sync attributes (matching real Keychain).
final class MockKeychain: KeychainProviding {
    struct Entry { let account: Account; let isSync: Bool }
    var store: [Entry] = []
    var failSaveForIDs: Set<UUID> = []
    var failDeleteForIDs: Set<UUID> = []

    func save(_ account: Account, synchronizable: Bool) throws {
        if failSaveForIDs.contains(account.id) {
            throw KeychainError.saveFailed(-25293)
        }
        store.removeAll { $0.account.id == account.id && $0.isSync == synchronizable }
        store.append(Entry(account: account, isSync: synchronizable))
    }

    func load(id: UUID) throws -> Account? {
        store.first(where: { $0.account.id == id })?.account
    }

    func loadAll() throws -> [Account] {
        store.map(\.account).sorted { $0.sortOrder < $1.sortOrder }
    }

    func loadAllIncludingVariants() throws -> [(account: Account, isSync: Bool)] {
        store.map { ($0.account, $0.isSync) }
    }

    func delete(id: UUID) throws {
        if failDeleteForIDs.contains(id) { throw KeychainError.deleteFailed(-25300) }
        store.removeAll { $0.account.id == id }  // both variants — mirrors kSecAttrSynchronizableAny
    }

    func deleteNonSyncOnly(id: UUID) throws {
        store.removeAll { $0.account.id == id && !$0.isSync }
    }

    func deleteAllSynced() throws {
        store.removeAll { $0.isSync }
    }

    func deleteAll() throws {
        store.removeAll()
    }
}
