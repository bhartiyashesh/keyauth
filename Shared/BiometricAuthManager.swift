import LocalAuthentication

enum BiometricType {
    case faceID
    case touchID
    case none
}

final class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    private init() {}

    var availableBiometric: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    func authenticate(reason: String = "Unlock KeyAuth") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            // Fall back to device passcode
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
            } catch {
                return false
            }
        }
    }
}
