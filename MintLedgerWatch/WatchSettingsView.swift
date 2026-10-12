import SwiftUI

struct WatchSettingsView: View {
    @Environment(WatchPasscodeLockService.self) private var lock
    @State private var action: WatchPasscodeAction?

    var body: some View {
        List {
            Section("密碼鎖") {
                Label(lock.isEnabled ? "已啟用" : "未啟用", systemImage: lock.isEnabled ? "lock.fill" : "lock.open")
                if lock.isEnabled {
                    Button("更改密碼") { action = .change }
                    Button("關閉密碼鎖") { action = .disable }
                    Button("立即鎖定") { lock.lock() }
                } else {
                    Button("啟用密碼鎖") { action = .enable }
                }
            }
            Section {
                Text("啟用後，重新開啟 App 時須輸入 4 位數密碼。密碼僅保存在這支手錶，不會與 iPhone 同步。請記住密碼。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .sheet(item: $action) { action in
            NavigationStack {
                WatchPasscodeSetupView(action: action)
            }
            .environment(lock)
        }
    }
}

enum WatchPasscodeAction: String, Identifiable {
    case enable, change, disable
    var id: String { rawValue }
}

private struct WatchPasscodeSetupView: View {
    @Environment(WatchPasscodeLockService.self) private var lock
    @Environment(\.dismiss) private var dismiss
    let action: WatchPasscodeAction
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var message: String?

    private var needsCurrentPIN: Bool { action != .enable && currentPIN.isEmpty }
    private var title: String {
        if needsCurrentPIN { return action == .disable ? "輸入密碼以關閉" : "輸入目前密碼" }
        return newPIN.isEmpty ? "設定 4 位數密碼" : "再次輸入新密碼"
    }

    var body: some View {
        WatchPasscodeView(title: title, message: message, retryAfter: lock.retryAfter) { pin in
            submit(pin)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .onDisappear {
            currentPIN = ""
            newPIN = ""
        }
    }

    private func submit(_ pin: String) {
        message = nil
        do {
            if needsCurrentPIN {
                if action == .disable {
                    try lock.disable(currentPIN: pin)
                    dismiss()
                } else {
                    try lock.verify(pin: pin)
                    currentPIN = pin
                }
                return
            }
            if newPIN.isEmpty {
                newPIN = pin
                return
            }
            guard pin == newPIN else {
                newPIN = ""
                message = "兩次密碼不同，請重新設定。"
                return
            }
            if action == .enable {
                try lock.enable(pin: pin)
            } else {
                try lock.changePIN(currentPIN: currentPIN, newPIN: pin)
            }
            currentPIN = ""
            newPIN = ""
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
