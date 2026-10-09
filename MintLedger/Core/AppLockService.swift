import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLockService {
    static let enabledDefaultsKey = "mintledger.face-id-lock.enabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var isFaceIDAvailable = false
    private(set) var statusMessage: String?

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        isEnabled = enabled
        isLocked = enabled
    }

    func prepare() async {
        refreshAvailability()
        await unlockIfNeeded()
    }

    func setEnabled(_ enabled: Bool) async {
        statusMessage = nil

        guard enabled else {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            isEnabled = false
            isLocked = false
            return
        }

        refreshAvailability()
        guard isFaceIDAvailable else {
            statusMessage = "此裝置目前無法使用 Face ID，請先到 iPhone 設定完成 Face ID 設定。"
            return
        }

        let succeeded = await authenticate(reason: "確認由你啟用 MintLedger 的 Face ID 鎖定")
        guard succeeded else { return }

        defaults.set(true, forKey: Self.enabledDefaultsKey)
        isEnabled = true
        isLocked = false
        statusMessage = nil
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
        statusMessage = nil
    }

    func unlockIfNeeded() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        _ = await authenticate(reason: "使用 Face ID 開啟 MintLedger")
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isFaceIDAvailable = canEvaluate && context.biometryType == .faceID
    }

    @discardableResult
    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        statusMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = ""

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError),
              context.biometryType == .faceID else {
            isFaceIDAvailable = false
            statusMessage = "Face ID 無法使用，請檢查 iPhone 的 Face ID 與密碼設定。"
            return false
        }

        let result: Result<Bool, Error> = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(success))
                }
            }
        }

        switch result {
        case .success(true):
            isLocked = false
            statusMessage = nil
            return true
        case .success(false):
            statusMessage = "Face ID 驗證失敗，請再試一次。"
            return false
        case .failure(let error):
            statusMessage = message(for: error)
            return false
        }
    }

    private func message(for error: Error) -> String {
        guard let error = error as? LAError else {
            return "Face ID 驗證失敗：\(error.localizedDescription)"
        }

        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Face ID 驗證已取消。"
        case .biometryLockout:
            return "Face ID 已暫時鎖定，請先用 iPhone 密碼解鎖後再試。"
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "Face ID 尚未設定或目前無法使用。"
        case .authenticationFailed:
            return "Face ID 無法辨識，請再試一次。"
        default:
            return "Face ID 驗證失敗：\(error.localizedDescription)"
        }
    }
}
