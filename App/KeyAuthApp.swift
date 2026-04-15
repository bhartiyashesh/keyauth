import SwiftUI

@main
struct KeyAuthApp: App {
    @StateObject private var store = AccountStore()
    @State private var isUnlocked = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(store)
                } else {
                    LockScreenView {
                        isUnlocked = true
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidEnterBackgroundNotification"))
            ) { _ in
                isUnlocked = false
            }
        }
    }
}
