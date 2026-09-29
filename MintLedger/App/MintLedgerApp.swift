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
                    SharedLedgerStorage.refreshWidget()
                }
                .onOpenURL { _ in
                    store.reload()
                    SharedLedgerStorage.refreshWidget()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.reload()
                    store.runDueRecurringEntries()
                    SharedLedgerStorage.refreshWidget()
                }
        }
    }
}
