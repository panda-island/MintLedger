import LocalAuthentication
import SwiftUI

struct AppLockGate<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var isUnlocked = false
    @State private var errorMessage: String?
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        Group {
            if !appLockEnabled || isUnlocked {
                content
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 52)).foregroundStyle(Color.mintLedger)
                    Text("MintLedger 已鎖定").font(.title2.bold())
                    Text(errorMessage ?? "使用 Face ID 或裝置密碼解鎖").foregroundStyle(.secondary)
                    Button("解鎖", action: authenticate).buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .task { if appLockEnabled { authenticate() } }
        .onChange(of: scenePhase) {
            if scenePhase == .background { isUnlocked = false }
            if scenePhase == .active && appLockEnabled { authenticate() }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedCancelTitle = "稍後"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解鎖你的本機帳本") { success, error in
            Task { @MainActor in
                isUnlocked = success
                errorMessage = success ? nil : error?.localizedDescription
            }
        }
    }
}
