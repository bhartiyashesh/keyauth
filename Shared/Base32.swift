import Foundation

enum Base32 {
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    private static let lookupTable: [Character: UInt8] = {
        var table = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() {
            table[c] = UInt8(i)
        }
        return table
    }()

    static func decode(_ input: String) -> Data? {
        let clean = input.uppercased().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { return nil }

        var bits = 0
        var buffer: UInt64 = 0
        var bytes = [UInt8]()

        for char in clean {
            guard let value = lookupTable[char] else { return nil }
            buffer = (buffer << 5) | UInt64(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 0xFF))
            }
        }

        return Data(bytes)
    }
}
