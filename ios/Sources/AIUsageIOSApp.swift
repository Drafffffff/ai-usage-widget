import SwiftUI

@main
struct AIUsageIOSApp: App {
    @StateObject private var store = IOSStore()

    init() {
        NotificationScheduler.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .environmentObject(store)
        }
    }
}
