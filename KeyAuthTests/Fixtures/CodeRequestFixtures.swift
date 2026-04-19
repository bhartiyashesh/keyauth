import Foundation
@testable import KeyAuth

enum CodeRequestFixtures {
    static func make(
        id: String = UUID().uuidString,
        issuer: String = "GitHub",
        label: String = "user@example.com",
        domain: String? = "github.com"
    ) -> CodeRequest {
        CodeRequest(id: id, issuer: issuer, label: label, domain: domain)
    }

    /// Empty-issuer / empty-label variant used by silent-send ambiguity tests.
    static func empty(domain: String? = "github.com") -> CodeRequest {
        CodeRequest(id: UUID().uuidString, issuer: "", label: "", domain: domain)
    }
}
