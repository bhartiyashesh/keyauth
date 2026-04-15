import SwiftUI
import UserNotifications

@main
struct KeyAuthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var pairingStore = PairingStore.shared
    @State private var isUnlocked = false
    @State private var deviceToken: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(pairingStore)
                } else {
                    LockScreenView {
                        isUnlocked = true
                    }
                }
            }
            .onAppear {
                setupAppDelegate()
                requestPushPermissionAndRegister()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                // Reconnect with backoff reset (fresh foreground)
                RelayClient.shared.reconnectIfNeeded()
                connectRelayIfPaired()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification
                )
            ) { _ in
                isUnlocked = false
                RelayClient.shared.disconnect()
            }
        }
    }

    private func setupAppDelegate() {
        appDelegate.onDeviceToken = { token in
            self.deviceToken = token
            RelayClient.shared.registerToken(token)
        }
        appDelegate.onNotificationTapped = { userInfo in
            connectRelayIfPaired()
        }
    }

    private func requestPushPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func connectRelayIfPaired() {
        guard pairingStore.isPaired,
              let pairing = pairingStore.pairingData
        else { return }
        RelayClient.shared.connect(
            roomId: pairing.roomId,
            relayURL: pairing.relayURL,
            deviceToken: deviceToken
        )
    }
}
