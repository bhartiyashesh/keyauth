import Foundation
import CommonCrypto

enum TOTPGenerator {
    /// Generate a TOTP code for the given account at the current time
    static func generate(for account: Account, at date: Date = Date()) -> String? {
        guard let secretData = Base32.decode(account.secret) else { return nil }
        return generate(
            secret: secretData,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            date: date
        )
    }

    /// Core TOTP: HMAC(secret, timeCounter) → dynamic truncation → mod 10^digits
    static func generate(
        secret: Data,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        date: Date = Date()
    ) -> String? {
        let counter = UInt64(floor(date.timeIntervalSince1970) / Double(period))
        var bigEndianCounter = counter.bigEndian

        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)

        guard let hmac = hmacSHA(algorithm: algorithm, key: secret, data: counterData) else {
            return nil
        }

        // Dynamic truncation (RFC 4226 §5.4)
        let offset = Int(hmac[hmac.count - 1] & 0x0F)
        let truncated = (UInt32(hmac[offset]) & 0x7F) << 24
            | UInt32(hmac[offset + 1]) << 16
            | UInt32(hmac[offset + 2]) << 8
            | UInt32(hmac[offset + 3])

        let mod = UInt32(pow(10, Double(digits)))
        let code = truncated % mod

        return String(format: "%0\(digits)d", code)
    }

    /// Seconds remaining until the current TOTP code expires
    static func secondsRemaining(period: Int = 30, at date: Date = Date()) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    // MARK: - HMAC

    private static func hmacSHA(algorithm: OTPAlgorithm, key: Data, data: Data) -> Data? {
        let ccAlgorithm: CCHmacAlgorithm
        let digestLength: Int

        switch algorithm {
        case .sha1:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA1)
            digestLength = Int(CC_SHA1_DIGEST_LENGTH)
        case .sha256:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA256)
            digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        case .sha512:
            ccAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA512)
            digestLength = Int(CC_SHA512_DIGEST_LENGTH)
        }

        var hmac = [UInt8](repeating: 0, count: digestLength)

        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(
                    ccAlgorithm,
                    keyPtr.baseAddress, key.count,
                    dataPtr.baseAddress, data.count,
                    &hmac
                )
            }
        }

        return Data(hmac)
    }
}
