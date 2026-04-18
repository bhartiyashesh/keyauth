import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?

    private let keychain: KeychainProviding
    private var reloadDebounceTask: Task<Void, Never>?
    private var kvsObserver: NSObjectProtocol?

    init(keychain: KeychainProviding = KeychainManager.shared) {
        self.keychain = keychain
        registerKVSObserver()
        reload()
    }

    deinit {
        if let observer = kvsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public CRUD

    func reload() {
        do {
            accounts = try keychain.loadAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
            accounts = []
        }
        SharedDefaults.saveAccounts(accounts)
    }

    /// Debounced reload — coalesces bursty KVS notifications per RESEARCH.md lines 624-634.
    func coalescedReload() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func add(_ account: Account) {
        var newAccount = account
        newAccount.sortOrder = accounts.count
        do {
            try keychain.save(newAccount, synchronizable: SyncPreference.isEnabled)
            bumpCounterIfSyncing()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ account: Account) {
        do {
            try keychain.delete(id: account.id)
            bumpCounterIfSyncing()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            try? keychain.delete(id: account.id)
        }
        bumpCounterIfSyncing()
        reload()
    }

    func move(from source: IndexSet, to destination: Int) {
        let moving = source.map { accounts[$0] }
        for index in source.sorted().reversed() {
            accounts.remove(at: index)
        }
        let insertAt = min(destination, accounts.count)
        accounts.insert(contentsOf: moving, at: insertAt)
        for (index, var account) in accounts.enumerated() {
            account.sortOrder = index
            try? keychain.save(account, synchronizable: SyncPreference.isEnabled)
        }
        bumpCounterIfSyncing()
        reload()
    }

    // MARK: - KVS wiring

    private func registerKVSObserver() {
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleKVSChange(notification)
            }
        }
    }

    private func handleKVSChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            coalescedReload()
        case NSUbiquitousKeyValueStoreAccountChange:
            // Per D-12 — handled by ICloudStateObserver too, but we reload defensively.
            SyncPreference.setEnabled(false)
            coalescedReload()
        default:
            break
        }
    }

    // MARK: - accounts-version counter

    /// Per RESEARCH.md lines 308-313: bump Int64 counter so other devices get a
    /// `didChangeExternallyNotification` ping. Only bump when sync is enabled
    /// (RESEARCH.md Open Question #6 — local-only saves don't need a ping).
    private func bumpCounterIfSyncing() {
        guard SyncPreference.isEnabled else { return }
        let store = NSUbiquitousKeyValueStore.default
        let current = store.longLong(forKey: "accounts-version")
        store.set(current + 1, forKey: "accounts-version")
        store.synchronize()
    }
}
