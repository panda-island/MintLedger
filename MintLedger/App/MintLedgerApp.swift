import SwiftUI

@main
struct MintLedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = LedgerStore()
    @State private var showsLaunchAnimation = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .overlay {
                    if showsLaunchAnimation {
                        LaunchAnimationView()
                            .transition(.opacity.combined(with: .scale(scale: 1.03)))
                            .allowsHitTesting(false)
                    }
                }
                .task {
                    store.reload()
                    store.runDueRecurringEntries()
                    SharedLedgerStorage.refreshWidget()
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        showsLaunchAnimation = false
                    }
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
