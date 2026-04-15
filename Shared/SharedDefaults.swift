import Foundation

enum SharedDefaults {
    private static let suiteName = "group.com.keyauth.shared"
    private static let accountsKey = "shared_accounts"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func saveAccounts(_ accounts: [Account]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        suite?.set(data, forKey: accountsKey)
        suite?.synchronize()
    }

    static func loadAccounts() -> [Account] {
        guard let data = suite?.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else {
            return []
        }
        return accounts.sorted { $0.sortOrder < $1.sortOrder }
    }
}
