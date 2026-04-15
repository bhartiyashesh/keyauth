import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var error: String?

    private let keychain = KeychainManager.shared

    init() {
        reload()
    }

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

    func add(_ account: Account) {
        var newAccount = account
        newAccount.sortOrder = accounts.count
        do {
            try keychain.save(newAccount)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ account: Account) {
        do {
            try keychain.delete(id: account.id)
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
            try? keychain.save(account)
        }
        reload()
    }
}
