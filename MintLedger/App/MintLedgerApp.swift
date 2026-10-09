import SwiftUI

@main
struct MintLedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = LedgerStore()
    @State private var cloudBackup = ICloudBackupService()
    @State private var watchSync = PhoneWatchSyncService()
    @State private var appLock = AppLockService()
    @State private var showsLaunchAnimation = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloudBackup)
                .environment(appLock)
                .overlay {
                    if showsLaunchAnimation {
                        LaunchAnimationView()
                            .transition(.opacity.combined(with: .scale(scale: 1.03)))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    // Keep the lock view mounted while LocalAuthentication dismisses its
                    // system sheet. Removing the view hierarchy in the same update as a
                    // successful Face ID callback can race the sheet dismissal on device.
                    AppLockView()
                        .opacity(isAppLockPresented ? 1 : 0)
                        .allowsHitTesting(isAppLockPresented)
                        .accessibilityHidden(!isAppLockPresented)
                }
                .task {
                    store.reload()
                    store.runDueRecurringEntries()
                    SharedLedgerStorage.refreshWidget()
                    if !isRunningTests {
                        watchSync.start(store: store)
                        await cloudBackup.prepare()
                        scheduleCloudBackup()
                    }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        showsLaunchAnimation = false
                    }
                    if !isRunningTests {
                        appLock.prepare()
                        await appLock.unlockIfNeeded()
                    }
                }
                .onOpenURL { url in
                    store.reload()
                    SharedLedgerStorage.refreshWidget()
                    watchSync.sendSnapshot()
                    scheduleCloudBackup()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        appLock.lock()
                        return
                    }
                    guard phase == .active else { return }
                    store.reload()
                    store.runDueRecurringEntries()
                    SharedLedgerStorage.refreshWidget()
                    guard !isRunningTests else { return }
                    watchSync.sendSnapshot()
                    Task {
                        await appLock.unlockIfNeeded()
                        await cloudBackup.refreshAccountStatus()
                        scheduleCloudBackup()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ledgerStoreDidPersist)) { _ in
                    watchSync.sendSnapshot()
                    scheduleCloudBackup()
                }
        }
    }

    private func scheduleCloudBackup() {
        guard !isRunningTests else { return }
        guard let data = try? store.encodedBackup() else { return }
        cloudBackup.scheduleAutomaticBackup(data: data)
    }

    private var isAppLockPresented: Bool {
        appLock.isEnabled
            && (appLock.isLocked || scenePhase != .active)
            && !showsLaunchAnimation
    }

    private var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

private struct LaunchAnimationView: View {
    @State private var lifts = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.mintLedger.opacity(0.96), Color(red: 0.05, green: 0.16, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                    .scaleEffect(lifts ? 1 : 0.72)
                    .opacity(lifts ? 1 : 0)
                Text("MintLedger")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(lifts ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                lifts = true
            }
        }
    }
}
