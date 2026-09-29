import SwiftUI

@main
struct MintLedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = LedgerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    store.reload()
                    store.runDueRecurringEntries()
                }
                .onOpenURL { _ in store.reload() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.reload()
                    store.runDueRecurringEntries()
                }
        }
    }
}
