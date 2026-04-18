import SwiftUI
import UserNotifications

@main
struct KeyAuthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var pairingStore = PairingStore.shared
    @StateObject private var icloudState = ICloudStateObserver.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var deviceToken: String?
    @State private var didBootstrapSyncPreference = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(pairingStore)
                        .environmentObject(icloudState)
                } else {
                    LockScreenView {
                        isUnlocked = true
                    }
                }
            }
            .onAppear {
                bootstrapSyncPreferenceOnce()
                setupAppDelegate()
                requestPushPermissionAndRegister()
                // Ensure KVS has latest state cached locally.
                NSUbiquitousKeyValueStore.default.synchronize()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    store.reload()
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
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

    private func bootstrapSyncPreferenceOnce() {
        guard !didBootstrapSyncPreference else { return }
        didBootstrapSyncPreference = true
        // Bootstrap needs the existing account count to differentiate new users (D-01) from
        // existing users (D-02). Read SharedDefaults directly to avoid instantiating AccountStore twice.
        let existingCount = SharedDefaults.loadAccounts().count
        SyncPreference.bootstrap(existingAccountCount: existingCount)
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
