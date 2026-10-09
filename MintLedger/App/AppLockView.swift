import SwiftUI
import UIKit

struct AppLockView: View {
    @Environment(AppLockService.self) private var appLock
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.mintLedger, Color(red: 0.04, green: 0.12, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text("MintLedger 已鎖定")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                if let statusMessage = appLock.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 30)
                }

                Button {
                    Task { await appLock.unlockIfNeeded() }
                } label: {
                    Label(
                        appLock.isAuthenticating ? "正在驗證…" : "使用 Face ID 解鎖",
                        systemImage: "faceid"
                    )
                    .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.mintLedger)
                .controlSize(.large)
                .disabled(appLock.isAuthenticating)

                if !appLock.isFaceIDAvailable {
                    Button("開啟 iPhone 設定") {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
    }
}
