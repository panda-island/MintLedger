import SwiftUI

@main
struct MintLedgerWatchApp: App {
    @State private var store = WatchLedgerStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environment(store)
        }
    }
}
