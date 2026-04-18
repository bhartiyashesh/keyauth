import Foundation
import Combine

@MainActor
final class ICloudStateObserver: ObservableObject {
    static let shared = ICloudStateObserver()

    @Published private(set) var isICloudSignedIn: Bool
    @Published private(set) var didAccountChange: Bool = false

    // REVISION FIX — Warning 7: Use `AnyObject?` (Apple's documented opaque identity-token pattern)
    // instead of the `any (NSCoding & NSCopying & NSObjectProtocol)` existential composition, which
    // generates strict-concurrency warnings under Swift 6 language mode. The token is opaque —
    // we only use reference identity (isEqual) for comparison, never its protocol capabilities.
    // Apple's own docs for `FileManager.ubiquityIdentityToken` describe it as an opaque object
    // that "can be compared using the isEqual: method".
    private var previousIdentityToken: AnyObject?
    private var identityObserver: NSObjectProtocol?

    private init() {
        let token = FileManager.default.ubiquityIdentityToken
        self.isICloudSignedIn = (token != nil)
        self.previousIdentityToken = token as AnyObject?

        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleIdentityChange() }
        }
    }

    deinit {
        if let observer = identityObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleIdentityChange() {
        let newToken = FileManager.default.ubiquityIdentityToken
        let wasSignedIn = isICloudSignedIn
        isICloudSignedIn = (newToken != nil)

        if newToken == nil && wasSignedIn {
            // User signed out of iCloud (D-12).
            SyncPreference.setEnabled(false)
            didAccountChange = true
        } else if let prev = previousIdentityToken,
                  let new = newToken as AnyObject?,
                  !prev.isEqual(new) {
            // User switched iCloud accounts — treat like sign-out + sign-in.
            SyncPreference.setEnabled(false)
            didAccountChange = true
        } else {
            didAccountChange = false
        }
        previousIdentityToken = newToken as AnyObject?
    }

    /// Test-only state primer — forces `isICloudSignedIn = true` and a non-nil previous token
    /// so `_simulateIdentityChange(newToken: nil)` models a genuine sign-out transition.
    /// The simulator defaults to no iCloud account, so without this primer the singleton's
    /// `isICloudSignedIn` is already false when the test begins and the sign-out branch
    /// cannot fire.
    #if DEBUG
    internal func _primeAsSignedIn() {
        isICloudSignedIn = true
        previousIdentityToken = NSString(string: "test-primed-token")
        didAccountChange = false
    }

    /// Test-only reset hook — allows unit tests to simulate identity transitions.
    internal func _simulateIdentityChange(newToken: AnyObject?) {
        let wasSignedIn = isICloudSignedIn
        isICloudSignedIn = (newToken != nil)
        if newToken == nil && wasSignedIn {
            SyncPreference.setEnabled(false)
            didAccountChange = true
        } else if let prev = previousIdentityToken,
                  let new = newToken,
                  !prev.isEqual(new) {
            SyncPreference.setEnabled(false)
            didAccountChange = true
        } else {
            didAccountChange = false
        }
        previousIdentityToken = newToken
    }
    #endif
}
