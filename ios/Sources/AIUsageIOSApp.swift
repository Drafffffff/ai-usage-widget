import SwiftUI

@main
struct AIUsageIOSApp: App {
    @StateObject private var store = IOSStore()

    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .environmentObject(store)
        }
    }
}
