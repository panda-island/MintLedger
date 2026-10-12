import SwiftUI

@main
struct MintLedgerWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchLedgerStore()
    @State private var lock = WatchPasscodeLockService()

    var body: some Scene {
        WindowGroup {
            Group {
                if lock.isEnabled && (lock.isLocked || scenePhase != .active) {
                    WatchLockView()
                        .disabled(scenePhase != .active)
                } else {
                    WatchDashboardView()
                }
            }
            .environment(store)
            .environment(lock)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .background { lock.lock() }
                if phase == .active { lock.refreshConfiguration() }
            }
        }
    }
}
