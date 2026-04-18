import Foundation
@testable import KeyAuth

enum AccountFixtures {
    static func make(
        id: UUID = UUID(),
        issuer: String = "GitHub",
        label: String = "user@example.com",
        secret: String = "JBSWY3DPEHPK3PXP",
        sortOrder: Int = 0,
        createdAt: Date? = nil
    ) -> Account {
        let a = Account(
            id: id,
            issuer: issuer,
            label: label,
            secret: secret,
            sortOrder: sortOrder
        )
        guard let explicitDate = createdAt else { return a }

        // Account.createdAt is `let` — patch via JSON round-trip for explicit-timestamp tests.
        let template: [String: Any] = [
            "id": a.id.uuidString,
            "issuer": a.issuer,
            "label": a.label,
            "secret": a.secret,
            "algorithm": a.algorithm.rawValue,
            "digits": a.digits,
            "period": a.period,
            "sortOrder": a.sortOrder,
            "createdAt": explicitDate.timeIntervalSinceReferenceDate
        ]
        if let data = try? JSONSerialization.data(withJSONObject: template),
           let patched = try? JSONDecoder().decode(Account.self, from: data) {
            return patched
        }
        return a
    }
}
