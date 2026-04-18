import Foundation

/// Normalized dedup key for Account: (issuer, label, secret).
/// Per RESEARCH.md § Dedup Strategy: Unicode NFC + case-insensitive + ASCII whitespace trim.
/// Secret: uppercase + strip ALL whitespace (Base32 is case-insensitive per RFC 4648).
struct DedupKey: Hashable {
    let issuer: String
    let label: String
    let secret: String

    init(_ account: Account) {
        self.issuer = account.issuer
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        self.label = account.label
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        self.secret = account.secret
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .uppercased()
    }
}
