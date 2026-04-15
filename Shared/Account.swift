import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var issuer: String
    var label: String
    var secret: String // Base32-encoded
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        issuer: String,
        label: String,
        secret: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.label = label
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    /// Parse otpauth://totp/Label?secret=BASE32&issuer=GitHub&digits=6&period=30&algorithm=SHA1
    static func from(otpauthURL url: URL) -> Account? {
        guard url.scheme == "otpauth",
              url.host == "totp",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let params = Dictionary(queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        }, uniquingKeysWith: { _, last in last })

        guard let secret = params["secret"], !secret.isEmpty else { return nil }

        // Path is /Issuer:label or /label
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathParts = path.split(separator: ":", maxSplits: 1)

        let issuer: String
        let label: String

        if let paramIssuer = params["issuer"], !paramIssuer.isEmpty {
            issuer = paramIssuer
            label = pathParts.count > 1
                ? String(pathParts[1]).trimmingCharacters(in: .whitespaces)
                : path.removingPercentEncoding ?? path
        } else if pathParts.count > 1 {
            issuer = String(pathParts[0]).trimmingCharacters(in: .whitespaces)
            label = String(pathParts[1]).trimmingCharacters(in: .whitespaces)
        } else {
            issuer = ""
            label = path.removingPercentEncoding ?? path
        }

        let algorithm: OTPAlgorithm
        switch params["algorithm"]?.uppercased() {
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: algorithm = .sha1
        }

        let digits = Int(params["digits"] ?? "") ?? 6
        let period = Int(params["period"] ?? "") ?? 30

        // Validate
        guard Base32.decode(secret) != nil else { return nil }
        guard [6, 7, 8].contains(digits) else { return nil }
        guard (10...120).contains(period) else { return nil }

        return Account(
            issuer: issuer,
            label: label,
            secret: secret.uppercased(),
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}
