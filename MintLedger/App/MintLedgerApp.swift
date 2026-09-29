import SwiftUI

@main
struct MintLedgerApp: App {
    @State private var store = LedgerStore()

    var body: some Scene {
        WindowGroup {
            AppLockGate {
                RootView()
                    .environment(store)
                    .task {
                        store.reload()
                        store.runDueRecurringEntries()
                    }
                    .onOpenURL { _ in store.reload() }
            }
        }
    }
}

